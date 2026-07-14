;;; early-init.el --- Loaded before GUI/package init -*- lexical-binding: t; -*-
;;; Commentary:
;; This file runs before the package system and the first frame are
;; created.  Everything here exists to make startup as fast as possible
;; and to avoid any visible flicker.  Heavy lifting lives in init.el.
;;; Code:

;; --- Garbage collection: pause it during startup -----------------------------
;; A huge threshold means the GC essentially never runs while we boot.
;; gcmh (configured in init.el) takes over once Emacs is idle.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; --- Neutralize the file-name handler list during startup --------------------
;; Every `load'/`require' walks this list; emptying it removes a lot of
;; regexp work.  init.el restores the original value after startup.
(defvar my--file-name-handler-alist file-name-handler-alist)
(unless (or (daemonp) noninteractive)
  (setq file-name-handler-alist nil))

;; --- Package system ----------------------------------------------------------
;; Let Emacs initialize packages automatically (so installed packages are
;; on the load-path before init.el), but use the precomputed quickstart
;; autoload file when present for a faster boot.
(setq package-enable-at-startup t
      package-quickstart t)

;; --- Frame / UI: kill the chrome before the first frame ----------------------
;; Setting these in `default-frame-alist' avoids creating then destroying
;; the toolbar/menubar (which causes a flash and a relayout).
(setq default-frame-alist
      '((menu-bar-lines . 0)
        (tool-bar-lines . 0)
        (vertical-scroll-bars . nil)
        (horizontal-scroll-bars . nil)
        (width . 110)
        (height . 38)
        ;; Pre-paint with catppuccin-mocha colors so there is no white
        ;; flash before the theme loads.  Harmless if you switch to a
        ;; light theme later.
        (background-color . "#1e1e2e")
        (foreground-color . "#cdd6f4")))

(menu-bar-mode -1)
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
(when (fboundp 'horizontal-scroll-bar-mode) (horizontal-scroll-bar-mode -1))
(when (fboundp 'tooltip-mode) (tooltip-mode -1))

;; --- Misc startup speedups ---------------------------------------------------
(setq frame-inhibit-implied-resize t      ; don't resize frame as fonts load
      frame-resize-pixelwise t
      inhibit-startup-screen t
      inhibit-startup-echo-area-message user-login-name
      initial-scratch-message nil
      inhibit-compacting-font-caches t
      inhibit-x-resources t
      use-file-dialog nil
      use-dialog-box nil
      ;; Don't bother loading the site default.
      site-run-file nil
      ;; Quiet, asynchronous native compilation.
      native-comp-async-report-warnings-errors 'silent
      load-prefer-newer t)

(provide 'early-init)
;;; early-init.el ends here
