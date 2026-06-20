;; -*- lexical-binding: t; -*-

;; --- Emacs 30 'cl.el' Polyfill ---
(eval-and-compile
  (require 'cl-lib)
  (unless (fboundp 'incf)
    (defmacro incf (place &optional val)
      `(cl-incf ,place ,val)))
  (unless (fboundp 'decf)
    (defmacro decf (place &optional val)
      `(cl-decf ,place ,val))))

;;; 1. UI CLEANUP
;; Strip away the graphical interface for a cleaner terminal-like feel.
(menu-bar-mode -1)
(tool-bar-mode -1)
;(scroll-bar-mode -1)
(setq inhibit-startup-message t)

;;; 2. PACKAGE MANAGER SETUP
;; Emacs needs to know where to download community packages (MELPA).
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(setq package-install-upgrade-built-in t)
(package-initialize)

;; Refresh package lists if we are missing information
(unless package-archive-contents
  (package-refresh-contents))

;;; 3. EVIL MODE (Vim Keybindings)
;; Install and configure evil-mode automatically.
(use-package evil
  :ensure t                 ; Tells Emacs to download it if missing
  :init                     ; Run this before loading the package
  (setq evil-want-integration t)
  (setq evil-want-keybinding nil) ; Required for evil-collection
  :config                   ; Run this after loading the package
  (evil-mode 1))            ; Turn it on globally

;; evil-collection adds Vim keys to Emacs' internal menus (like package manager)
(use-package evil-collection
  :after evil
  :ensure t
  :config
  (evil-collection-init))

;;; 4. GPTEL (Local Ollama Setup)
(use-package gptel
  :ensure t
  :config
  ;; Tell gptel to use your local Ollama server
  (setq gptel-backend (gptel-make-ollama "Ollama"
                        :host "192.168.2.69:11434"
                        :stream t
                        :models '("qwen2.5-coder-ctx64k:latest")))
  
  ;; Set the blazing fast 7B model as your default
  (setq gptel-model "qwen2.5-coder-ctx64k:latest"))

;;; 5. GPTEL TOOL CALLING (Docker Sandbox Execution)

; Enable tool use globally for gptel
(setq gptel-use-tools t)

;; Define the execution tool
(setq gptel-tools
      (list
       (gptel-make-tool
        :name "execute_code"
        :description "Execute a shell command or python script securely inside an Alpine Linux Docker sandbox. Use this to test code, run calculations, or inspect environments."
        :args (list '(:name "command" 
                      :type "string" 
                      :description "The exact shell command to run. To run Python, use: python -c '...'"))
        :function (lambda (command)
                    (let* ((server-user "nacho") ; <-- CHANGE THIS to your server's SSH username
                           (server-ip "192.168.2.69")
                           ;; Construct the SSH command to pipe into docker
                           (full-cmd (format "ssh %s@%s 'docker exec ai-sandbox sh -c %s'"
                                             server-user
                                             server-ip
                                             (shell-quote-argument command))))
                      (with-temp-message (format "Running in sandbox: %s" command)
                        ;; Execute the command and capture the output to feed back to the LLM
                        (shell-command-to-string full-cmd)))))))

;;; 6. NATIVE FILESYSTEM TOOLS (No MCP required)

;; Native Directory Lister
(add-to-list 'gptel-tools
             (gptel-make-tool
              :name "list_directory"
              :description "List the contents of a local directory. Use this to find files on the machine running Emacs."
              :args (list '(:name "path" :type "string" :description "Absolute path to the directory."))
              :function (lambda (path)
                          (condition-case nil
                              ;; directory-files returns a list. "^[^.]" hides hidden files like . and ..
                              (mapconcat #'identity (directory-files (expand-file-name path) nil "^[^.]") "\n")
                            (error (format "Error: Directory '%s' not found or permission denied." path))))))

;; Native File Reader
(add-to-list 'gptel-tools
             (gptel-make-tool
              :name "read_file"
              :description "Read the text contents of a local file into context."
              :args (list '(:name "filepath" :type "string" :description "Absolute path to the file."))
              :function (lambda (filepath)
                          (condition-case nil
                              (with-temp-buffer
                                (insert-file-contents (expand-file-name filepath))
                                (buffer-string))
                            (error (format "Error: File '%s' not found or cannot be read." filepath))))))

;; Native File Writer (Overwrites or Creates New Files)
(add-to-list 'gptel-tools
             (gptel-make-tool
              :name "write_file"
              :description "Create a new file or completely overwrite an existing file with new text content. Use this to save new agent profiles or rewrite configurations."
              :args (list '(:name "filepath" :type "string" :description "Absolute path to the destination file.")
                          '(:name "content" :type "string" :description "The full text content to write into the file."))
              :function (lambda (filepath content)
                          (condition-case nil
                              (progn
                                ;; Ensure the parent directory exists before writing
                                (make-directory (file-name-directory (expand-file-name filepath)) t)
                                (with-temp-file (expand-file-name filepath)
                                  (insert content))
                                (format "Success: File written to '%s'." filepath))
                            (error (format "Error: Failed to write file to '%s'." filepath))))))

;; Native File Appender (Appends to the bottom of a file)
(add-to-list 'gptel-tools
             (gptel-make-tool
              :name "append_file"
              :description "Append text content to the end of an existing file. Use this to add new notes, logs, or subheadings to a file without erasing its current contents."
              :args (list '(:name "filepath" :type "string" :description "Absolute path to the file.")
                          '(:name "content" :type "string" :description "The text content to add to the end of the file."))
              :function (lambda (filepath content)
                          (condition-case nil
                              (progn
                                (write-region content nil (expand-file-name filepath) t)
                                (format "Success: Content appended to '%s'." filepath))
                            (error (format "Error: Failed to append to '%s'." filepath))))))

(defun ouroboros-replace-in-file (path search-text replace-text)
  "Find SEARCH-TEXT in PATH and replace it with REPLACE-TEXT."
  (condition-case err
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        ;; We use search-forward instead of regex to prevent LLM regex hallucinations
        (if (search-forward search-text nil t)
            (progn
              (replace-match replace-text t t)
              (write-region (point-min) (point-max) path)
              (format "SUCCESS: Replaced text in %s" path))
          (format "ERROR: Could not find the exact target string in %s. Check your spelling and try again." path)))
    (error (format "ERROR modifying file: %s" err))))

;; Register the new tool
(add-to-list 'gptel-tools
             (gptel-make-tool
              :name "replace_in_file"
              :description "Surgically replace a specific block of text in an existing file."
              :args '((:name "path" :type string :description "Target file path")
                      (:name "search_text" :type string :description "The exact existing text to find")
                      (:name "replace_text" :type string :description "The new text to insert"))
              :function #'ouroboros-replace-in-file))

;;; 7. DYNAMIC AGENT LOADER

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
  "Prompt the user to select an agent persona and inject it into gptel."
  (interactive)
  (let* ((agent-dir (expand-file-name "agents.d" user-emacs-directory))
         (_ (unless (file-directory-p agent-dir)
              (make-directory agent-dir t)))
         (agent-files (directory-files agent-dir nil "\\.org$"))
         (selected-file (completing-read "Select Agent Persona: " agent-files nil t))
         (full-path (expand-file-name selected-file agent-dir))
         ;; Strip hidden text properties (like colors) so the API gets pure text
         (parsed-profile (substring-no-properties (my-gptel-read-agent-profile full-path))))
    
    (unless (derived-mode-p 'gptel-mode)
      (gptel-mode 1))
    
    ;; 1. Set the public user-facing variable
    (setq-local gptel-system-message parsed-profile)
    
    ;; 2. THE MISSING LINK: Overwrite the hidden transient shadow variable
    (setq-local gptel--system-message parsed-profile)
    
    (message "✅ Agent [%s] loaded! Context starts with: %s..." 
             selected-file 
             (replace-regexp-in-string "\n" " " (substring parsed-profile 0 (min 60 (length parsed-profile)))))))

;; Bind it to a convenient shortcut in your gptel chat buffers
(with-eval-after-load 'gptel
  (keymap-set gptel-mode-map "C-c a" #'my-gptel-load-agent))

(require 'json)
(defun ouroboros-universal-tool-interceptor (beg end)
  "Bypass the LLM provider API. Parse JSON tool blocks safely, inject results, 
and automatically chain the next LLM turn if a tool was run."
  (message "Ouroboros: Scanning response for tool blocks...")
  (let ((tool-executed-p nil))
    (save-excursion
      (save-restriction
        (narrow-to-region beg end)
        (goto-char (point-min))
        
        (while (re-search-forward (rx "```tool" (zero-or-more (any space "\n" "\r"))
                                      (group (minimal-match (zero-or-more anything)))
                                      "\n" (zero-or-more space) "```")
                                  nil t)
          (let* ((json-str (match-string 1))
                 (_ (message "Ouroboros: Found JSON block: %s" (string-trim json-str)))
                 (json-object-type 'alist)
                 (json-array-type 'list)
                 (tool-expr (condition-case err
                                (json-read-from-string json-str)
                              (error nil)))
                 result)
            (if (not tool-expr)
                (setq result (format "ERROR: Tool block must be valid JSON. Got: %s" json-str))
              (let* ((tool-name (cdr (assoc 'name tool-expr)))
                     ;; V6.1 Fix: Support both standard LLM naming conventions
                     (args-alist (or (cdr (assoc 'args tool-expr))
                                     (cdr (assoc 'arguments tool-expr))))
                     (tool (cl-find tool-name gptel-tools :key #'gptel-tool-name :test #'equal)))
                (if (not tool)
                    (setq result (format "ERROR: Tool '%s' not found in system." tool-name))
                  (let* ((func (gptel-tool-function tool))
                         (tool-args-def (gptel-tool-args tool))
                         (positional-args
                          (mapcar (lambda (arg-def)
                                    (let* ((arg-name (plist-get arg-def :name))
                                           (val (cdr (assoc (intern arg-name) args-alist))))
                                      val))
                                  tool-args-def)))
                    (message "Ouroboros: Executing %s with args %S" tool-name positional-args)
                    (setq result (condition-case err
                                     (apply func positional-args)
                                   (error (format "EXECUTION ERROR: %s" err))))))))
            
            (setq result (or result "Tool executed, but returned no value."))
            (setq tool-executed-p t)
            
            (goto-char (match-end 0))
            (insert (format "\n\n**[SYSTEM INJECTION: Tool Result]**\n```text\n%s\n```\n" result))
            (message "Ouroboros: Tool execution injected successfully.")))))
    
    (when tool-executed-p
      (message "Ouroboros: Chaining next execution turn automatically...")
      (run-at-time "0.1 sec" nil 
                   (lambda (buf)
                     (with-current-buffer buf
                       (goto-char (point-max))
                       (gptel-send)))
                   (current-buffer)))))
(add-hook 'gptel-post-response-functions #'ouroboros-universal-tool-interceptor)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages nil)
 '(package-vc-selected-packages
   '((gptel-mcp :url "https://github.com/lizqwerscott/gptel-mcp.el"))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
