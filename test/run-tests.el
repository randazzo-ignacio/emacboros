;; -*- lexical-binding: t; -*-

;;; Test Runner for Agentic Emacs Framework
;; 
;; Batch entry point: loads all source modules, loads all test files,
;; and runs the full ERT suite.
;;
;; Usage:
;;   emacs --batch -l /root/.emacs.d/test/run-tests.el
;;
;; Or from within Emacs:
;;   M-x load-file RET /root/.emacs.d/test/run-tests.el RET
;;   M-x ert RET t RET

;; --- Bootstrap: package system and gptel ---

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

;; Ensure gptel is installed
(unless (package-installed-p 'gptel)
  (package-install 'gptel))

(require 'gptel)
(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'json)

;; --- Load all source modules ---

(let ((init-dir (expand-file-name "init.d" user-emacs-directory)))
  (add-to-list 'load-path init-dir)
  (dolist (file (directory-files init-dir t "\\.el\\'"))
    (load (file-name-sans-extension file) nil t)))

;; --- Load all test files ---

(let ((test-dir (expand-file-name "test" user-emacs-directory)))
  (add-to-list 'load-path test-dir)
  (dolist (file (directory-files test-dir t "^test-.*\\.el\\'"))
    (load (file-name-sans-extension file) nil t)))

;; --- Run tests ---

(if noninteractive
    ;; Batch mode: exit with appropriate code
    (ert-run-tests-batch-and-exit)
  ;; Interactive: just message
  (message "Test files loaded. Run M-x ert RET t RET to execute."))