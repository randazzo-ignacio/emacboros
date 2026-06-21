;; -*- lexical-binding: t; -*-

(add-to-list 'load-path (expand-file-name "init.d" user-emacs-directory))

;; Package manager setup
(load "package_setup.el")

;; UI cleanup
(load "ui_cleanup.el")

;; Evil mode setup
(load "evil_mode.el")

;; GPTEL backend configuration
(load "gptel_setup.el")

;; Native filesystem tools for gptel
(load "fs_tools.el")
;; Local code execution tools for gptel
(load "code_tools.el")

;; Replacement utility tool
(load "replacement_tool.el")

;; Dynamic agent loader
(load "agent_loader.el")

;; Multi-agent delegation tool
(load "delegate_tool.el")
