;; -*- lexical-binding: t; -*-

(setq evil-want-integration t)
(setq evil-want-keybinding nil)

(use-package evil
  :ensure t
  :init (setq evil-want-integration t)
  :config (evil-mode 1))

(use-package evil-collection
  :after evil
  :ensure t
  :config (evil-collection-init))
