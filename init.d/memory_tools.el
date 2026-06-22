;; -*- lexical-binding: t; -*-

;;; Memory Summarization Tool for gptel
;; Provides an interactive command (C-c m) that summarizes the current
;; conversation into the loaded agent's MEMORIES section.
;;
;; Design:
;; - Manual trigger: user decides when to summarize (C-c m in gptel-mode)
;; - Synchronous: uses accept-process-output pattern (same as execute_code_local)
;;   so Emacs stays responsive but the user waits for completion
;; - Same model: uses the currently configured gptel-model and gptel-backend
;; - No race conditions: single-threaded, user-initiated
;; - Rolling summary: old MEMORIES + conversation -> new concise MEMORIES
;; - Auto-reloads agent profile after update so new memories take effect

(require 'gptel)
(require 'json)
(require 'cl-lib)
(require 'subr-x)

;;; --- Configuration ---

(defcustom my-gptel-memory-max-entries 20
  "Maximum number of memory entries the summarizer should retain.
The summarizer is instructed to keep at most this many concise bullet points,
prioritizing the most important and recent information."
  :type 'integer
  :group 'gptel)

(defcustom my-gptel-memory-timeout 120
  "Timeout in seconds for the summarization API call.
If the model does not respond within this time, the operation is aborted
and a partial result (if any) is returned."
  :type 'integer
  :group 'gptel)

(defconst my-gptel-memory-system-prompt
  (concat
   "You are a memory summarization engine for an AI agent system.\n"
   "Your job is to maintain a concise, rolling memory log for an agent.\n\n"
   "You will receive:\n"
   "1. CURRENT MEMORIES: The agent's existing memory entries.\n"
   "2. CONVERSATION: The recent conversation between the user and the agent.\n\n"
   "Produce an updated set of memory entries that:\n"
   "- Retains all critical facts: agent identity, capabilities, key decisions, persistent notes.\n"
   "- Adds new important information from the conversation: tasks completed, files modified, bugs found, architecture decisions, tool changes.\n"
   (format "- Drops or merges obsolete entries to keep the total under %d bullet points.\n"
           my-gptel-memory-max-entries)
   "- Each entry is a single line starting with '- ' (markdown bullet).\n"
   "- Entries are factual, concise, and specific (no vague statements).\n"
   "- Do NOT include operational logs -- those go to HISTORY.log separately.\n"
   "- Do NOT include a header or any text outside the bullet list.\n\n"
   "Output ONLY the bullet-point memory entries. No preamble, no explanation.")
  "System prompt for the summarizer. Instructs the model to produce
a concise rolling summary of the agent's memory.")

;;; --- Internal functions ---

(defun my-gptel--memory-extract-section (filepath)
  "Extract the * MEMORIES section from FILEPATH.
Returns a cons: (full-content . memories-text) where memories-text
is everything after the '* MEMORIES' heading (or empty string if not found)."
  (with-temp-buffer
    (insert-file-contents filepath)
    (let* ((content (buffer-string))
           (marker "* MEMORIES")
           (marker-pos (search-forward marker nil t)))
      (if marker-pos
          (progn
            (forward-line 1)
            (let ((memories (buffer-substring-no-properties (point) (point-max))))
              (cons content (string-trim memories))))
        (cons content "")))))

(defun my-gptel--memory-extract-conversation ()
  "Extract conversation text from the current gptel buffer.
Returns the plain text of the buffer up to point-max, with gptel
text properties stripped. This includes all user messages and
assistant responses in the chat."
  (buffer-substring-no-properties (point-min) (point-max)))

(defun my-gptel--memory-build-payload (current-memories conversation)
  "Build the JSON payload string for the Ollama /api/chat endpoint.
CURRENT-MEMORIES is the existing memory text.
CONVERSATION is the conversation text to summarize."
  (let* ((system-prompt my-gptel-memory-system-prompt)
         (user-message (format "CURRENT MEMORIES:\n%s\n\nCONVERSATION:\n%s"
                                (if (string-empty-p current-memories)
                                    "(none yet)"
                                  current-memories)
                                conversation))
         (model-name (if (symbolp gptel-model)
                         (symbol-name gptel-model)
                       gptel-model)))
    (json-serialize
     `(:model ,model-name
       :messages [(:role "system" :content ,system-prompt)
                  (:role "user" :content ,user-message)]
       :stream :json-false
       :options (:temperature 0.3
                 :top_p 0.9
                 :num_ctx 32768
                 :num_predict 4096))
     :null-object :null
     :false-object :json-false)))

(defun my-gptel--memory-call-ollama (payload timeout)
  "Send PAYLOAD (JSON string) to the Ollama /api/chat endpoint.
Uses make-process + accept-process-output for responsive waiting.
TIMEOUT in seconds. Returns the response content string, or
an error string starting with 'Error:'."
  (let* ((host (gptel-backend-host gptel-backend))
         (url (format "http://%s/api/chat" host))
         (buf (generate-new-buffer " *gptel-memory-summary*"))
         (start-time (current-time))
         (deadline (time-add start-time (seconds-to-time timeout)))
         (done nil)
         (exit-code nil)
         proc)
    (setq proc
          (make-process
           :name "gptel-memory-curl"
           :buffer buf
           :command (list "curl" "-s" "-X" "POST" url
                          "-H" "Content-Type: application/json"
                          "-d" payload)
           :sentinel
           (lambda (p event)
             (when (memq (process-status p) '(exit signal))
               (setq exit-code (process-exit-status p))
               (setq done t)))))
    (while (and (not done)
                (process-live-p proc)
                (time-less-p (current-time) deadline))
      (accept-process-output nil 0.1))
    (unwind-protect
        (let ((raw-output (with-current-buffer buf (buffer-string))))
          (cond
           ((not done)
            (delete-process proc)
            (let ((partial (with-current-buffer buf (buffer-string))))
              (if (string-match-p "\\S-" partial)
                  (format "Error: Timeout after %ds. Partial output:\n%s" timeout partial)
                (format "Error: Timeout after %ds. No output received." timeout))))
           ((and exit-code (/= exit-code 0))
            (format "Error: curl exited with code %d. Output:\n%s" exit-code raw-output))
           (t
            (condition-case err
                (let ((json-object-type 'plist)
                      (json-array-type 'vector))
                  (with-temp-buffer
                    (insert raw-output)
                    (goto-char (point-min))
                    (let* ((parsed (json-read))
                           (message-obj (plist-get parsed :message)))
                      (if message-obj
                          (or (plist-get message-obj :content)
                              (format "Error: Empty message content. Raw:\n%s" raw-output))
                        (format "Error: No message in response. Raw:\n%s" raw-output)))))
              (error
               (format "Error parsing JSON: %s\nRaw output:\n%s"
                       (error-message-string err) raw-output))))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(defun my-gptel--memory-update-org-file (filepath new-memories)
  "Update the * MEMORIES section in FILEPATH with NEW-MEMORIES.
Replaces everything after the '* MEMORIES' heading with the new content.
Uses atomic write (temp file + rename) for safety."
  (let* ((content (with-temp-buffer
                    (insert-file-contents filepath)
                    (buffer-string)))
         (marker "* MEMORIES")
         (marker-pos (string-search marker content)))
    (if marker-pos
        (let* ((before (substring content 0 marker-pos))
               (new-content (concat before marker "\n" new-memories "\n"))
               (tmp-file (make-temp-file "gptel-memory-")))
          (with-temp-file tmp-file
            (insert new-content))
          (rename-file tmp-file filepath t)
          (format "SUCCESS: Updated MEMORIES in %s" filepath))
      (let* ((new-content (concat content
                                  (unless (string-suffix-p "\n" content) "\n")
                                  "\n* MEMORIES\n" new-memories "\n"))
             (tmp-file (make-temp-file "gptel-memory-")))
        (with-temp-file tmp-file
          (insert new-content))
        (rename-file tmp-file filepath t)
        (format "SUCCESS: Added MEMORIES section to %s" filepath)))))

(defun my-gptel--memory-count-entries (memories-text)
  "Count the number of bullet-point entries in MEMORIES-TEXT."
  (let ((count 0)
        (start 0))
    (while (string-match "^- " memories-text start)
      (setq count (1+ count))
      (setq start (match-end 0)))
    count))

;;; --- Interactive command ---

(defun my-gptel-summarize-memories ()
  "Summarize the current conversation into the loaded agent's MEMORIES section.
Uses the configured Ollama backend and model to produce a rolling summary.
Synchronous: Emacs stays responsive via accept-process-output but the user
waits for completion. After updating, reloads the agent profile so new
memories take effect immediately."
  (interactive)
  (condition-case err
      (let* ((agent-file (if (and (boundp 'my-gptel--current-agent-file)
                                   my-gptel--current-agent-file
                                   (file-exists-p my-gptel--current-agent-file))
                              my-gptel--current-agent-file
                            (error "No agent profile loaded in this buffer. Load one with C-c a first.")))
             (extracted (my-gptel--memory-extract-section agent-file))
             (current-memories (cdr extracted))
             (conversation (my-gptel--memory-extract-conversation))
             (payload (my-gptel--memory-build-payload current-memories conversation))
             (model-name (if (symbolp gptel-model)
                             (symbol-name gptel-model)
                           gptel-model)))
        (when (< (length (string-trim conversation)) 50)
          (error "Conversation is too short to summarize. Have a meaningful exchange first."))
        (message "[Summarizing memories with %s...]" model-name)
        (let ((result (my-gptel--memory-call-ollama payload my-gptel-memory-timeout)))
          (if (string-prefix-p "Error:" result)
              (progn
                (message "%s" result)
                (user-error "%s" result))
            (let* ((new-memories (string-trim result))
                   (entry-count (my-gptel--memory-count-entries new-memories))
                   (update-result (my-gptel--memory-update-org-file agent-file new-memories)))
              (my-gptel-tool-reload-agent)
              (message "[Memories updated: %d entries written to %s]"
                        entry-count
                        (file-name-nondirectory agent-file))
              (format "%s. %d entries written." update-result entry-count)))))
    (error
     (message "Memory summarization failed: %s" (error-message-string err))
     (user-error "Memory summarization failed: %s" (error-message-string err)))))

;;; --- Keybinding ---

(with-eval-after-load 'gptel
  (keymap-set gptel-mode-map "C-c m" #'my-gptel-summarize-memories))

(provide 'memory_tools)