;; -*- lexical-binding: t; -*-

;;; Delegate Tool for gptel - Multi-Agent Delegation (Async)
;; Allows an agent to spawn a sub-agent with a specific profile to handle a sub-task.
;;
;; This is an ASYNC tool: the function receives a callback as its first
;; argument (per gptel's :async convention) and calls it with the result when
;; the sub-agent completes. This keeps Emacs responsive during delegation and
;; allows nested delegation chains without freezing the editor.

(require 'gptel)
(require 'cl-lib)
(require 'subr-x)

;;; Buffer-local state for tracking delegation depth

(defvar-local my-gptel--delegate-depth 0
  "Buffer-local: current delegation depth for this agent session.
0 = top-level agent (not spawned via delegate).
1+ = spawned via delegate. Used to limit recursion depth.")

(defconst my-gptel--delegate-max-depth 3
  "Maximum delegation depth allowed.
Prevents infinite recursion while permitting multi-hop chains.")

;;; Internal functions

(defun my-gptel--load-agent-profile (agent-name)
  "Load an agent profile by name from agents.d/<name>/prompt.org.
Returns the profile string or nil if not found."
  (unless (string-match-p "^[a-zA-Z0-9_-]+$" agent-name)
    (error "Invalid agent name: '%s'" agent-name))
  (let* ((agent-dir (expand-file-name "agents.d" user-emacs-directory))
         (prompt-path (expand-file-name (format "%s/prompt.org" agent-name) agent-dir)))
    (unless (string-prefix-p agent-dir (file-truename prompt-path))
      (error "Path traversal attempt blocked for agent: '%s'" agent-name))
    (when (file-exists-p prompt-path)
      (my-gptel-read-agent-profile prompt-path))))

;;; Timeout handler (extracted to reduce nesting depth)

(defun my-gptel--delegate-timeout-handler (buf callback agent completed
                                               resp-start timeout-secs)
  "Handle a delegate timeout.
This function is called by a timer when the sub-agent hasn't completed
within TIMEOUT-SECS.  It aborts the gptel request and calls CALLBACK
with a timeout message or partial response."
  (cond
   ((not (buffer-live-p buf))
    (unless completed
      (funcall callback
               (format "Delegate '%s' buffer was killed before completion." agent))))
   (completed)  ; Already done, nothing to do
   (t
    (gptel-abort buf)
    ;; Fallback: if gptel-abort doesn't trigger the post-response hook,
    ;; force completion after a brief delay.
    (run-with-timer
     1 nil
     (lambda ()
       (unless completed
         (let ((partial
                (when (buffer-live-p buf)
                  (with-current-buffer buf
                    (if (and resp-start (< resp-start (point-max)))
                        (buffer-substring-no-properties resp-start (point-max))
                      "")))))
           (when (buffer-live-p buf) (kill-buffer buf))
           (funcall callback
                    (if (and partial (string-match-p "\\S-" partial))
                        (format "[TIMEOUT after %ds -- partial response captured]\n\n%s"
                                timeout-secs partial)
                      (format "[TIMEOUT after %ds -- no response was generated before timeout]"
                              timeout-secs))))))))))

;;; Async tool function

(defun my-gptel-tool-delegate (callback agent task &optional context timeout)
  "Delegate a task to a sub-agent with a specific profile.  ASYNC tool.
CALLBACK is gptel's async tool callback.  AGENT is the profile name.
TASK is the task description.  CONTEXT is optional context.
TIMEOUT is optional max seconds to wait (default 600)."
  (let* ((ctx (or context "No additional context provided."))
         (timeout-secs (cond
                        ((integerp timeout) timeout)
                        ((stringp timeout) (string-to-number timeout))
                        ((numberp timeout) (floor timeout))
                        (t 600)))
         (agent-valid (and agent (stringp agent) (> (length agent) 0)
                           (string-match "[^[:space:]]" agent)))
         (task-valid (and task (stringp task) (> (length task) 0)
                          (string-match "[^[:space:]]" task))))
    (cond
     ((not agent-valid)
      (funcall callback "Delegate tool error: :agent must be a non-empty string"))
     ((not task-valid)
      (funcall callback "Delegate tool error: :task must be a non-empty string"))
     (t
      (let ((profile (my-gptel--load-agent-profile agent)))
        (if (not profile)
            (funcall callback
                     (format "Agent profile '%s' not found in agents.d/" agent))
          (my-gptel--spawn-async-delegate
           callback agent task ctx timeout-secs profile)))))))

(defun my-gptel--spawn-async-delegate (callback agent task ctx timeout-secs profile)
  "Spawn an async delegate buffer and send the task."
  (let* ((parent-depth (if (boundp 'my-gptel--delegate-depth)
                           my-gptel--delegate-depth 0))
         (task-id (format "delegate-%s-%d-%d" agent (emacs-pid) (float-time)))
         (buf (get-buffer-create (format "*gptel-delegate-%s*" task-id)))
         (full-prompt (format "DELEGATED TASK FROM PARENT AGENT\n==============================\n\nCONTEXT:\n%s\n\nTASK:\n%s"
                              ctx task))
         (timer nil)
         (completed nil)
         (resp-start nil))
    (with-current-buffer buf
      (text-mode)
      (gptel-mode 1)
      (setq-local gptel-system-prompt profile)
      (setq-local my-gptel--delegate-depth (1+ parent-depth))
      (setq-local gptel-confirm-tool-calls nil)
      (when (>= my-gptel--delegate-depth my-gptel--delegate-max-depth)
        (setq-local gptel-tools
                    (cl-remove-if (lambda (tool)
                                    (equal (gptel-tool-name tool) "delegate"))
                                  (copy-sequence gptel-tools))))

      ;; Completion hook: called by gptel at DONE, ERRS, or ABRT state.
      (let ((completion-fn
             (lambda (start end)
               (unless completed
                 (setq completed t)
                 (when timer (cancel-timer timer))
                 (let ((response
                        (if (and (numberp start) (numberp end) (< start end))
                            (buffer-substring-no-properties start end)
                          "")))
                   (when (buffer-live-p buf) (kill-buffer buf))
                   (funcall callback
                            (if (and response (string-match-p "\\S-" response))
                                (format "Delegate '%s' completed:\n\n%s" agent response)
                              (format "Delegate '%s' returned empty response (timeout: %ds)."
                                      agent timeout-secs))))))))
        (add-hook 'gptel-post-response-functions completion-fn nil t)

        ;; Timeout timer: fires once after timeout-secs.
        (setq timer
              (run-with-timer
               timeout-secs nil
               (lambda ()
                 (my-gptel--delegate-timeout-handler
                  buf callback agent completed
                  resp-start timeout-secs))))

        ;; Insert the prompt text into the buffer and send.
        (insert full-prompt)
        (setq resp-start (point))
        (gptel-send)))))

;; Register the delegate tool (async)
(add-to-list 'gptel-tools
 (gptel-make-tool
  :name "delegate"
  :description "Spawn a sub-agent with a specific profile to handle a sub-task. Returns the sub-agent's final response. Use for complex tasks requiring specialized expertise or parallel processing."
  :args (list '(:name "agent" :type "string" :description "Profile name (e.g., 'coder', 'reviewer', 'researcher', 'mccarthy'). Must exist as agents.d/<name>/prompt.org")
              '(:name "task" :type "string" :description "What you want the sub-agent to accomplish. Be specific and detailed.")
              '(:name "context" :type "string" :description "Relevant context from the current conversation to pass along. Optional but recommended.")
              '(:name "timeout" :type "integer" :description "Maximum seconds to wait for delegate response. Default 600." :optional t))
  :async t
  :function #'my-gptel-tool-delegate))

(provide 'delegate_tool)