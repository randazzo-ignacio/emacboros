;; -*- lexical-binding: t; -*-

;;; Delegate Tool for gptel - Multi-Agent Delegation
;; Allows an agent to spawn a sub-agent with a specific profile to handle a sub-task.
;;
;; The delegate spawns a temporary gptel buffer, loads the target agent profile,
;; sends the task as a prompt, waits for the response, and returns it.
;; The delegate tool is available to sub-agents up to a maximum depth
;; (my-gptel--delegate-max-depth, default 3) to allow multi-hop chains
;; while preventing infinite recursion.

(require 'gptel)
(require 'cl-lib)
(require 'subr-x)

;;; Buffer-local state for tracking delegate completion

(defvar-local my-gptel--delegate-response nil
  "Buffer-local: captures the final response text from a delegate request.
Set by `my-gptel--delegate-completion-hook' when the gptel FSM reaches DONE.")

(defvar-local my-gptel--delegate-done nil
  "Buffer-local: flag set when delegate request completes (success or error).
Set by `my-gptel--delegate-completion-hook'.")

(defvar-local my-gptel--delegate-depth 0
  "Buffer-local: current delegation depth for this agent session.
0 = top-level agent (not spawned via delegate).
1+ = spawned via delegate. Used to limit recursion depth.")

(defconst my-gptel--delegate-max-depth 3
  "Maximum delegation depth allowed. Prevents infinite recursion
while permitting multi-hop chains (e.g., A -> B -> A -> B).")

;;; Internal functions

(defun my-gptel--load-agent-profile (agent-name)
  "Load an agent profile by name from agents.d directory.
Returns the profile string or nil if not found."
  ;; Prevent path traversal - only allow alphanumeric, dash, underscore
  (unless (string-match-p "^[a-zA-Z0-9_-]+$" agent-name)
    (error "Invalid agent name: '%s'. Only alphanumeric, dash, underscore allowed." agent-name))
  (let* ((agent-dir (expand-file-name "agents.d" user-emacs-directory))
         (filepath (expand-file-name (format "%s.org" agent-name) agent-dir)))
    ;; Extra safety: ensure filepath stays within agent-dir
    (unless (string-prefix-p agent-dir (file-truename filepath))
      (error "Path traversal attempt blocked for agent: '%s'" agent-name))
    (when (file-exists-p filepath)
      (my-gptel-read-agent-profile filepath))))

(defun my-gptel--delegate-completion-hook (start end)
  "Hook for `gptel-post-response-functions' to capture delegate response.
START and END are buffer positions of the inserted response."
  (setq my-gptel--delegate-response
        (buffer-substring-no-properties start end))
  (setq my-gptel--delegate-done t))

(defun my-gptel--spawn-delegate (agent-name task context)
  "Spawn a delegate buffer with AGENT-NAME profile, send TASK with CONTEXT.
Returns a plist with :buffer, :task-id, :agent, :start-time."
  (let* ((profile (my-gptel--load-agent-profile agent-name))
         (task-id (format "delegate-%s-%d-%d" agent-name (emacs-pid) (float-time)))
         (buf (get-buffer-create (format "*gptel-delegate-%s*" task-id)))
         (full-prompt (format "DELEGATED TASK FROM PARENT AGENT\n==============================\n\nCONTEXT:\n%s\n\nTASK:\n%s"
                              context task)))
                (unless profile
      (error "Agent profile '%s' not found in agents.d/" agent-name))
    ;; Read parent's delegation depth BEFORE switching to new buffer
    (let ((parent-depth (if (boundp 'my-gptel--delegate-depth)
                            my-gptel--delegate-depth
                          0)))
      (with-current-buffer buf
        (text-mode)
        (gptel-mode 1)
        ;; Set the agent profile as the system prompt
        (setq-local gptel-system-prompt profile)
        ;; Track delegation depth: inherit parent's depth + 1
        (setq-local my-gptel--delegate-depth (1+ parent-depth))
        ;; Only remove delegate tool if we've hit max depth (recursion limit)
        (when (>= my-gptel--delegate-depth my-gptel--delegate-max-depth)
          (setq-local gptel-tools
                      (cl-remove-if (lambda (tool)
                                      (equal (gptel-tool-name tool) "delegate"))
                                    (copy-sequence gptel-tools))))
        ;; Initialize completion state
        (setq-local my-gptel--delegate-response nil)
        (setq-local my-gptel--delegate-done nil)
        ;; Add completion hook (buffer-local, runs at DONE/ERRS state)
        (add-hook 'gptel-post-response-functions
                  #'my-gptel--delegate-completion-hook
                  nil t)
        ;; Insert the prompt text into the buffer, then call gptel-send
        ;; with NO argument (nil arg = normal send, reads buffer up to point).
        ;; Do NOT pass the prompt string as an argument to gptel-send --
        ;; gptel-send's optional arg is a prefix arg, not a prompt.
        (insert full-prompt)
        (let ((response-start (point)))
          (gptel-send)
          (list :buffer buf :task-id task-id :agent agent-name
                              :start-time (current-time) :response-start response-start))))))

(defun my-gptel--wait-for-delegate (delegate-info timeout)
  "Wait for delegate buffer to finish processing. Returns the response string.
TIMEOUT in seconds (nil = wait forever).
On timeout, returns whatever partial response was generated so far,
behaving as if the sub-agent simply reached its output limit."
  (let* ((buf (plist-get delegate-info :buffer))
         (task-id (plist-get delegate-info :task-id))
         (start (plist-get delegate-info :start-time))
         (resp-start (plist-get delegate-info :response-start))
         (deadline (when timeout (time-add start (seconds-to-time timeout))))
         response)
    (unwind-protect
        (progn
                    ;; Poll for completion flag (set by gptel-post-response-functions hook)
          ;; Use accept-process-output to yield to Emacs' event loop, allowing
          ;; redisplay, input processing, and -- critically -- gptel's own
          ;; url-retrieve/curl process output to flow. This keeps Emacs
          ;; responsive while waiting for the sub-agent to finish.
          (while (and (buffer-live-p buf)
                      (not (buffer-local-value 'my-gptel--delegate-done buf))
                      (or (null timeout)
                          (time-less-p (current-time) deadline)))
            (accept-process-output nil 0.1))
          ;; Check for buffer death, timeout, or completion
          (cond
           ((not (buffer-live-p buf))
            (setq response nil))
           ((and timeout
                 (not (buffer-local-value 'my-gptel--delegate-done buf)))
            ;; Timeout reached: abort the request and capture partial response
                        (gptel-abort buf)
            (accept-process-output nil 0.3)  ; brief pause to let abort settle
            (let ((partial
                   (when (buffer-live-p buf)
                     (with-current-buffer buf
                       (let ((end (point-max)))
                         (if (and resp-start (< resp-start end))
                             (buffer-substring-no-properties resp-start end)
                           ""))))))
              (setq response
                    (if (and partial (string-match-p "\\S-" partial))
                        (format "[TIMEOUT after %ds — partial response captured]\n\n%s"
                                timeout partial)
                      (format "[TIMEOUT after %ds — no response was generated before timeout]"
                              timeout)))))
           (t
            (setq response
                  (buffer-local-value 'my-gptel--delegate-response buf)))))
      ;; Always clean up the delegate buffer
      (when (buffer-live-p buf)
        (kill-buffer buf)))
    response))

;;; Tool function (matches gptel calling convention: positional args)

(defun my-gptel-tool-delegate (agent task &optional context timeout)
  "Delegate a task to a sub-agent with a specific profile.
AGENT: Profile name (string) - must exist as .org file in agents.d/
TASK: What you want the sub-agent to accomplish (string).
CONTEXT: Relevant context from the current conversation (string, optional).
TIMEOUT: Maximum seconds to wait for delegate response (integer, optional, default 600).
Matches gptel tool calling convention: individual positional arguments
via `gptel--map-tool-args' -> `apply'."
  ;; Validate inputs
  (unless (and agent (stringp agent) (> (length agent) 0)
               (string-match "[^[:space:]]" agent))
    (error "Delegate tool: :agent must be a non-empty string"))
  (unless (and task (stringp task) (> (length task) 0)
               (string-match "[^[:space:]]" task))
    (error "Delegate tool: :task must be a non-empty string"))
  (let* ((context (or context "No additional context provided."))
         (timeout (cond
                   ((integerp timeout) timeout)
                   ((stringp timeout) (string-to-number timeout))
                   ((numberp timeout) (floor timeout))
                   (t 600)))
         (delegate-info (my-gptel--spawn-delegate agent task context))
         (response (my-gptel--wait-for-delegate delegate-info timeout)))
    (if (and response (string-match-p "\\S-" response))
        (format "Delegate '%s' completed:\n\n%s" agent response)
      (format "Delegate '%s' returned empty response (timeout: %ds)." agent timeout))))

;; Register the delegate tool
(add-to-list 'gptel-tools
 (gptel-make-tool
  :name "delegate"
  :description "Spawn a sub-agent with a specific profile to handle a sub-task. Returns the sub-agent's final response. Use for complex tasks requiring specialized expertise or parallel processing."
  :args (list '(:name "agent" :type "string" :description "Profile name (e.g., 'coder', 'reviewer', 'researcher', 'ouroboros'). Must exist as .org file in agents.d/")
              '(:name "task" :type "string" :description "What you want the sub-agent to accomplish. Be specific and detailed.")
              '(:name "context" :type "string" :description "Relevant context from the current conversation to pass along. Optional but recommended.")
              '(:name "timeout" :type "integer" :description "Maximum seconds to wait for delegate response. Default 600." :optional t))
  :function #'my-gptel-tool-delegate))

(provide 'delegate_tool)