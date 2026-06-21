;; -*- lexical-binding: t; -*-

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

(add-to-list 'load-path (expand-file-name "init.d" user-emacs-directory))

;; UI cleanup
(load "ui_cleanup.el")

;; Evil mode setup
(load "evil_mode.el")

;; GPTEL backend configuration
(load "gptel_setup.el")

;; Native filesystem tools for gptel
(load "fs_tools.el")

;; Replacement utility tool
(load "replacement_tool.el")

;; Dynamic agent loader
(load "agent_loader.el")
