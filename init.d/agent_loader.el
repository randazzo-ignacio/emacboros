;; -*- lexical-binding: t; -*-

;;; Dynamic Agent Loader for gptel
(defun my-gptel-read-agent-profile (filepath)
  "Read an Org file and seamlessly expand all #+INCLUDE directives."
  (require 'ox)
  (with-temp-buffer
    ;; Anchor the temporary buffer to the agent directory so relative paths work
    (setq default-directory (file-name-directory filepath))
    
    (insert-file-contents filepath)
    ;; Briefly activate org-mode so the export engine understands the syntax
    (org-mode) 
    ;; Magically flatten all #+INCLUDE tags into one cohesive document
    (org-export-expand-include-keyword) 
    (buffer-string)))

(defun my-gptel-load-agent ()
  "Prompt user to select an agent persona and inject it into gptel."
  (interactive)
  (let* ((agent-dir (expand-file-name "agents.d" user-emacs-directory))
         (_ (unless (file-directory-p agent-dir)
              (make-directory agent-dir t)))
         (files (directory-files agent-dir nil "\.org$"))
         (chosen (completing-read "Select Agent Persona: " files nil t))
         (full-path (expand-file-name chosen agent-dir))
         (profile (my-gptel-read-agent-profile full-path)))
    (when (not (derived-mode-p 'gptel-mode))
      (gptel-mode 1))
    (setq-local gptel-system-message profile)
    (setq-local gptel--system-message profile)
    ;; Track which agent file was loaded (for reload_agent tool)
    (setq-local my-gptel--current-agent-file full-path)
    (message "[OK] Agent %s loaded!" chosen)))

(with-eval-after-load 'gptel
  (keymap-set gptel-mode-map "C-c a" #'my-gptel-load-agent))
