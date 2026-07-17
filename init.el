;;; init.el --- A fast, modern, VSCode-flavored Emacs -*- lexical-binding: t; -*-
;;; Commentary:
;;
;;  Goals:
;;    1. Near-instant startup (deferred loading, GC + handler tricks).
;;    2. Modern: everything via use-package.
;;    3. Behaves like a standard editor (VSCode-ish): cut/copy/paste,
;;       M-backspace deletes (does NOT copy), VSCode word motion,
;;       multiple cursors, move/duplicate lines, smart Home.
;;    4. Works great in the terminal (-nw).
;;    5. Full IDE: completion, tree-sitter, eglot (LSP), flymake.
;;    6. First-class Markdown with native syntax highlighting inside
;;       fenced code blocks for every language you have a mode for.
;;
;;  First launch will download packages (one-time, a little slow).
;;  Every launch after that is fast.  See README.md for keybindings.
;;
;;; Code:

;;; ----------------------------------------------------------------------------
;;; Restore startup-time hacks once we're up
;;; ----------------------------------------------------------------------------
(add-hook 'emacs-startup-hook
          (lambda ()
            ;; Put the file-name handler list back (early-init nulled it).
            (setq file-name-handler-alist my--file-name-handler-alist)
            (let ((elapsed (float-time (time-subtract after-init-time
                                                      before-init-time))))
              (message "Emacs ready in %.2fs with %d GCs"
                       elapsed gcs-done))))

;;; ----------------------------------------------------------------------------
;;; Package system + use-package bootstrap
;;; ----------------------------------------------------------------------------
(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/"))
      package-archive-priorities
      '(("gnu" . 10) ("nongnu" . 8) ("melpa" . 5)))

(unless (bound-and-true-p package--initialized)
  (package-initialize))

;; First run: make sure we actually have an archive index before installing.
(unless package-archive-contents
  (ignore-errors (package-refresh-contents)))

;; use-package ships with Emacs 29+, but install it just in case.
(unless (package-installed-p 'use-package)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t        ; auto-install missing packages
      use-package-always-defer  nil      ; we defer explicitly where it helps
      use-package-expand-minimally t
      use-package-compute-statistics nil)

;;; ----------------------------------------------------------------------------
;;; Keep ~/.emacs.d tidy + adaptive garbage collection
;;; ----------------------------------------------------------------------------
(use-package no-littering
  :demand t
  :config
  (setq backup-directory-alist
        `((".*" . ,(no-littering-expand-var-file-name "backup/")))
        auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t)))
  ;; Stash customize output away so it never clutters init.el.
  (setq custom-file (no-littering-expand-etc-file-name "custom.el"))
  (when (file-exists-p custom-file)
    (load custom-file nil t)))

(use-package gcmh
  :demand t
  :init (setq gcmh-idle-delay 'auto
              gcmh-high-cons-threshold (* 128 1024 1024))
  :config (gcmh-mode 1))

;;; ----------------------------------------------------------------------------
;;; Sane, modern defaults
;;; ----------------------------------------------------------------------------
(use-package emacs
  :ensure nil
  :init
  (setq-default
   indent-tabs-mode nil                 ; spaces, not tabs
   tab-width 4
   fill-column 100
   truncate-lines nil)
  (setq
   ;; Editing
   sentence-end-double-space nil
   require-final-newline t
   kill-do-not-save-duplicates t
   ;; Scrolling that feels native
   scroll-margin 3
   scroll-conservatively 101
   scroll-preserve-screen-position t
   mouse-wheel-scroll-amount '(2 ((shift) . 1))
   mouse-wheel-progressive-speed nil
   ;; Files / safety
   create-lockfiles nil
   make-backup-files t
   backup-by-copying t
   delete-old-versions t
   version-control t
   vc-follow-symlinks t
   ;; UX
   use-short-answers t                  ; y/n instead of yes/no
   ring-bell-function 'ignore
   confirm-kill-processes nil
   echo-keystrokes 0.02
   help-window-select t
   ;; Clipboard: integrate with the system clipboard everywhere.
   select-enable-clipboard t
   select-enable-primary t
   save-interprogram-paste-before-kill t
   ;; Completion plumbing
   tab-always-indent 'complete
   completion-ignore-case t
   read-file-name-completion-ignore-case t
   read-buffer-completion-ignore-case t)
  (set-default-coding-systems 'utf-8)
  (prefer-coding-system 'utf-8)
  :config
  ;; Core editing minor modes that make Emacs feel like a normal editor.
  (delete-selection-mode 1)             ; typing replaces the selection
  (electric-pair-mode 1)                ; auto-close brackets/quotes
  (show-paren-mode 1)
  (setq show-paren-delay 0
        show-paren-when-point-inside-paren t)
  (global-auto-revert-mode 1)           ; reload files changed on disk
  (setq global-auto-revert-non-file-buffers t)
  (savehist-mode 1)                     ; persist minibuffer history
  (save-place-mode 1)                   ; reopen files at last position
  (recentf-mode 1)
  (setq recentf-max-saved-items 300)
  (column-number-mode 1)
  (when (fboundp 'pixel-scroll-precision-mode)
    (pixel-scroll-precision-mode 1))
  ;; CUA: standard cut/copy/paste on C-x/C-c/C-v (only when a region is
  ;; active; otherwise they stay as prefix keys) plus rectangles on C-RET.
  (cua-mode 1)
  ;; Line numbers in code and prose, absolute like VSCode.
  (setq display-line-numbers-width 3)
  (dolist (hook '(prog-mode-hook text-mode-hook conf-mode-hook))
    (add-hook hook #'display-line-numbers-mode))
  ;; Highlight the current line.
  (dolist (hook '(prog-mode-hook text-mode-hook conf-mode-hook))
    (add-hook hook #'hl-line-mode)))

;; GUI font: use the first installed monospace font we find.
(when (display-graphic-p)
  (catch 'done
    (dolist (f '("JetBrainsMono Nerd Font" "JetBrains Mono" "Fira Code"
                 "Cascadia Code" "Hack" "Menlo" "DejaVu Sans Mono"))
      (when (find-font (font-spec :name f))
        (set-face-attribute 'default nil :family f :height 130)
        (throw 'done t)))))

;;; ----------------------------------------------------------------------------
;;; Environment: make Emacs find your toolchain (the macOS GUI PATH problem)
;;; ----------------------------------------------------------------------------
;; A GUI Emacs started from Finder/Dock does NOT inherit your shell PATH, so
;; clangd / cmake / lldb-dap / ripgrep / language servers come up "not found".
;; We (1) pull PATH from your login shell, and (2) add the usual toolchain
;; directories explicitly (Homebrew is keg-only for llvm, so lldb-dap lives in
;; a dir that's never on PATH by default).
(defun my/prepend-to-path (dir)
  "Add DIR to the front of `exec-path' and $PATH when it exists."
  (when (and dir (file-directory-p dir))
    (add-to-list 'exec-path dir)
    (setenv "PATH" (concat dir path-separator (getenv "PATH")))))

(dolist (d (list "/opt/homebrew/bin"
                 "/opt/homebrew/sbin"
                 "/usr/local/bin"
                 "/opt/homebrew/opt/llvm/bin"   ; clangd, clang-format, lldb-dap (Apple Silicon)
                 "/usr/local/opt/llvm/bin"      ; same, Intel macs
                 "/Library/Developer/CommandLineTools/usr/bin"
                 (expand-file-name "~/.cargo/bin")
                 (expand-file-name "~/go/bin")))
  (my/prepend-to-path d))

(use-package exec-path-from-shell
  :if (memq window-system '(mac ns x))
  :config
  (setq exec-path-from-shell-variables '("PATH" "MANPATH" "LIBRARY_PATH"))
  (exec-path-from-shell-initialize))

;;; ----------------------------------------------------------------------------
;;; Look & feel: Catppuccin theme (+ Modus as a built-in light fallback)
;;; ----------------------------------------------------------------------------
(use-package catppuccin-theme
  :demand t
  :init (setq catppuccin-flavor 'mocha) ; mocha | macchiato | frappe | latte
  :config (load-theme 'catppuccin :no-confirm))

(defun my/toggle-light-dark ()
  "Flip between Catppuccin Mocha (dark) and the built-in Modus Operandi (light)."
  (interactive)
  (if (memq 'catppuccin custom-enabled-themes)
      (progn (mapc #'disable-theme custom-enabled-themes)
             (load-theme 'modus-operandi t))
    (mapc #'disable-theme custom-enabled-themes)
    (load-theme 'catppuccin t)))

(use-package doom-modeline
  :init
  (setq doom-modeline-icon (display-graphic-p)
        doom-modeline-height 28
        doom-modeline-bar-width 3
        doom-modeline-buffer-encoding nil)
  :hook (after-init . doom-modeline-mode))

;; Pretty icons in GUI (needs `M-x nerd-icons-install-fonts' once).
(use-package nerd-icons
  :if (display-graphic-p))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package which-key
  :init (which-key-mode)
  :config (setq which-key-idle-delay 0.4
                which-key-sort-order 'which-key-prefix-then-key-order))

;;; ----------------------------------------------------------------------------
;;; Minibuffer completion stack: vertico + orderless + marginalia + consult
;;; ----------------------------------------------------------------------------
(use-package vertico
  :init (vertico-mode)
  :config (setq vertico-cycle t
                vertico-count 14))

(use-package orderless
  :init
  (setq completion-styles '(orderless basis)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))

(use-package marginalia
  :init (marginalia-mode))

(use-package consult
  :bind (("C-s"   . consult-line)          ; find in file
         ("C-x b" . consult-buffer)        ; switch buffer
         ("C-x 4 b" . consult-buffer-other-window)
         ("M-y"   . consult-yank-pop)      ; browse the kill ring
         ("M-g g" . consult-goto-line)
         ("M-g i" . consult-imenu)         ; jump to symbol/heading
         ("C-c f" . consult-ripgrep)       ; search the project (needs ripgrep)
         ("C-c F" . consult-find)
         ("C-c r" . consult-recent-file)
         ("C-c !" . consult-flymake))      ; list diagnostics
  :init (setq consult-narrow-key "<"
              register-preview-delay 0.2
              xref-show-xrefs-function #'consult-xref
              xref-show-definitions-function #'consult-xref))

(use-package embark
  :bind (("C-." . embark-act)
         ("M-." . embark-dwim)
         ("C-h B" . embark-bindings)))

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;;; ----------------------------------------------------------------------------
;;; In-buffer completion: corfu + cape (works in the terminal too)
;;; ----------------------------------------------------------------------------
(use-package corfu
  :init (global-corfu-mode)
  :config
  (setq corfu-auto t
        corfu-auto-delay 0.15           ; small pause before popping up
        corfu-auto-prefix 2             ; need >=2 chars typed
        corfu-cycle t
        corfu-preselect 'first          ; highlight the top item, like VSCode
        corfu-quit-no-match 'separator
        corfu-quit-at-boundary 'separator
        corfu-scroll-margin 4
        ;; Give the popup a clean VSCode-ish frame: icon gutter on the left,
        ;; a little breathing room, a slim scrollbar on the right.
        corfu-min-width 28
        corfu-max-width 100
        corfu-left-margin-width 0.8
        corfu-right-margin-width 0.8
        corfu-bar-width 0.3)
  ;; Enter and Tab both accept the highlighted candidate (VSCode behavior).
  (keymap-set corfu-map "RET" #'corfu-insert)
  (keymap-set corfu-map "TAB" #'corfu-insert)
  (keymap-set corfu-map "<tab>" #'corfu-insert)
  ;; The little documentation panel that slides out to the side.
  (corfu-popupinfo-mode 1)
  (setq corfu-popupinfo-delay '(0.5 . 0.3))

  ;; --- Auto-popup ONLY in code (like VSCode IntelliSense) -------------------
  ;; In prose (Markdown, Org, plain text) and other non-code buffers, the
  ;; popup never fires on its own -- press TAB / M-TAB to complete on demand.
  (defun my/corfu-auto-by-mode ()
    "Enable Corfu auto-popup only in programming/config buffers."
    (setq-local corfu-auto (derived-mode-p 'prog-mode 'conf-mode)))
  (add-hook 'after-change-major-mode-hook #'my/corfu-auto-by-mode))

;; VSCode-style kind icons in the popup (GUI only; needs a Nerd Font, which
;; you can install with `M-x nerd-icons-install-fonts').
(use-package nerd-icons-corfu
  :if (display-graphic-p)
  :after corfu
  :config (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

;; Render the Corfu popup in text terminals.
(use-package corfu-terminal
  :unless (display-graphic-p)
  :after corfu
  :config (corfu-terminal-mode 1))

(use-package cape
  :init
  ;; Keyword + file completion are cheap and precise.  dabbrev (whole-word
  ;; guessing) is the chatty one, so it only runs in code, where auto-popup
  ;; is enabled -- in prose it won't surface unless you ask for it.
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-keyword)
  (add-to-list 'completion-at-point-functions #'cape-dabbrev)
  (setq cape-dabbrev-min-length 3))     ; don't suggest off a single letter

;;; ----------------------------------------------------------------------------
;;; Tree-sitter: modern, fast syntax highlighting + structural editing
;;; ----------------------------------------------------------------------------
(use-package treesit-auto
  :demand t
  :init (setq treesit-auto-install 'prompt) ; offer to fetch grammars on demand
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode))

;;; ----------------------------------------------------------------------------
;;; LSP via eglot (built-in, lightweight, fast)
;;; ----------------------------------------------------------------------------
;; Servers are launched on demand with `C-c l l' (or auto when present).
;; Install the relevant server binary for full IDE features per language
;; (pyright, typescript-language-server, rust-analyzer, gopls, clangd,
;; jdtls, etc.).  See README.md.
(use-package eglot
  :ensure nil
  :commands (eglot eglot-ensure)
  :init
  ;; Auto-start eglot in these modes *only if* a server is on PATH, so you
  ;; never get an error popup for a language whose server isn't installed.
  (defun my/eglot-ensure-if-available ()
    "Start eglot only when its language-server binary is actually on PATH.
Loads eglot lazily (only when you open one of these files) so startup
stays fast, and never throws a popup for a server you haven't installed."
    (when (require 'eglot nil t)
      (let* ((guess   (ignore-errors (eglot--guess-contact)))
             (contact (nth 3 guess))
             (program (and (consp contact) (seq-find #'stringp contact))))
        (when (and program (executable-find program))
          (eglot-ensure)))))
  (dolist (hook '(python-ts-mode-hook
                  js-ts-mode-hook typescript-ts-mode-hook tsx-ts-mode-hook
                  rust-ts-mode-hook go-ts-mode-hook
                  c-ts-mode-hook c++-ts-mode-hook
                  java-ts-mode-hook sh-mode-hook bash-ts-mode-hook))
    (add-hook hook #'my/eglot-ensure-if-available))
  :bind (:map prog-mode-map
         ("C-c l l" . eglot)
         ("C-c l r" . eglot-rename)
         ("C-c l a" . eglot-code-actions)
         ("C-c l f" . eglot-format-buffer)
         ("C-c l d" . eldoc-doc-buffer)
         ("C-c l h" . eldoc)
         ("C-c l s" . consult-eglot-symbols))
  :config
  (setq eglot-autoshutdown t            ; kill the server when the last buffer closes
        eglot-events-buffer-size 0      ; don't log everything (faster)
        eglot-sync-connect 1
        eglot-extend-to-xref t))

(use-package consult-eglot
  :after (consult eglot))

;; Diagnostics (eglot drives flymake under the hood).
(use-package flymake
  :ensure nil
  :hook (prog-mode . flymake-mode)
  :bind (:map flymake-mode-map
         ("M-n" . flymake-goto-next-error)
         ("M-p" . flymake-goto-prev-error)))

;;; ----------------------------------------------------------------------------
;;; Language modes (tree-sitter handles most highlighting via treesit-auto)
;;; ----------------------------------------------------------------------------
(use-package yaml-mode  :mode ("\\.ya?ml\\'"))
(use-package json-mode  :mode ("\\.json\\'"))
(use-package toml-mode  :mode ("\\.toml\\'"))
(use-package dockerfile-mode)
(use-package web-mode
  ;; HTML/templating; tree-sitter owns .jsx/.tsx (tsx-ts-mode) for better LSP.
  :mode ("\\.html?\\'" "\\.vue\\'" "\\.svelte\\'" "\\.php\\'" "\\.erb\\'")
  :config (setq web-mode-markup-indent-offset 2
                web-mode-css-indent-offset 2
                web-mode-code-indent-offset 2))
(use-package clojure-mode)
(use-package cider :after clojure-mode :defer t)
(use-package rust-mode :defer t)
(use-package go-mode :defer t)
(use-package swift-mode :defer t)

;;; ----------------------------------------------------------------------------
;;; Markdown: native syntax highlighting inside fenced code blocks
;;; ----------------------------------------------------------------------------
(use-package markdown-mode
  :mode (("README\\.md\\'" . gfm-mode)
         ("\\.md\\'"       . markdown-mode)
         ("\\.markdown\\'" . markdown-mode))
  :init
  (setq markdown-command "pandoc"
        ;; THE important one: fontify code inside ``` fences using each
        ;; language's real major mode -> full highlighting for any language
        ;; you have a mode for (Python, JS, Rust, C, etc.).
        markdown-fontify-code-blocks-natively t
        markdown-enable-highlighting-syntax t
        markdown-enable-math t
        markdown-header-scaling t
        markdown-asymmetric-header t
        markdown-hide-urls nil
        markdown-fontify-whole-heading-line t)
  :config
  ;; Map common fenced-code language tags to the right major mode so the
  ;; tag spelling never matters (e.g. ```sh, ```js, ```c++, ```yml).
  (dolist (pair '(("sh"         . sh-mode)
                  ("shell"      . sh-mode)
                  ("bash"       . sh-mode)
                  ("zsh"        . sh-mode)
                  ("console"    . sh-mode)
                  ("py"         . python-mode)
                  ("python"     . python-mode)
                  ("js"         . js-mode)
                  ("javascript" . js-mode)
                  ("jsx"        . js-mode)
                  ("ts"         . typescript-ts-mode)
                  ("typescript" . typescript-ts-mode)
                  ("tsx"        . tsx-ts-mode)
                  ("json"       . json-mode)
                  ("yaml"       . yaml-mode)
                  ("yml"        . yaml-mode)
                  ("toml"       . conf-toml-mode)
                  ("rust"       . rust-mode)
                  ("rs"         . rust-mode)
                  ("go"         . go-mode)
                  ("c"          . c-mode)
                  ("c++"        . c++-mode)
                  ("cpp"        . c++-mode)
                  ("java"       . java-mode)
                  ("swift"      . swift-mode)
                  ("clojure"    . clojure-mode)
                  ("clj"        . clojure-mode)
                  ("elisp"      . emacs-lisp-mode)
                  ("emacs-lisp" . emacs-lisp-mode)
                  ("xml"        . nxml-mode)
                  ("html"       . web-mode)
                  ("css"        . css-mode)))
    (add-to-list 'markdown-code-lang-modes pair)))

;;; ----------------------------------------------------------------------------
;;; C / C++ development: clangd, CMake/Make, debugging, format-on-save
;;; ----------------------------------------------------------------------------

;; --- Tree-sitter indentation for C/C++ --------------------------------------
(setq c-ts-mode-indent-offset 4
      c-ts-mode-indent-style 'k&r)

;; --- clangd: turn on the good stuff -----------------------------------------
;; Background indexing, clang-tidy lints, smart header insertion, detailed
;; completion.  This overrides eglot's default bare "clangd" invocation for
;; every C/C++/ObjC mode.  Requires the `clangd' binary on PATH (ships with
;; LLVM; `brew install llvm' or your distro's clang/clangd package).
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '((c++-ts-mode c-ts-mode c++-mode c-mode objc-mode)
                 . ("clangd"
                    "--background-index"
                    "--clang-tidy"
                    "--completion-style=detailed"
                    "--header-insertion=iwyu"
                    "--header-insertion-decorators=0"
                    "--pch-storage=memory"
                    "-j=4"))))

;; --- CMake & Makefile editing -----------------------------------------------
(use-package cmake-mode
  :mode (("CMakeLists\\.txt\\'" . cmake-mode)
         ("\\.cmake\\'"         . cmake-mode)))
;; (makefile-mode is built in and already handles Makefile/*.mk.)

;; --- Build helpers (CMake) + compile_commands.json plumbing -----------------
(defun my/project-root ()
  "Return the current project's root directory (or `default-directory')."
  (if-let ((proj (project-current))) (project-root proj) default-directory))

(defun my/cmake-root ()
  "Return the top-most ancestor directory that contains a CMakeLists.txt.
This walks UP from the current file, so build/debug commands work no
matter which source file (e.g. src/main.cpp) is open.  Falls back to the
project root, then `default-directory', if no CMakeLists.txt is found."
  (let ((dir default-directory)
        (root nil)
        (hit nil))
    (while (setq hit (locate-dominating-file dir "CMakeLists.txt"))
      (setq root hit
            dir (file-name-directory (directory-file-name hit))))
    ;; expand-file-name turns "~/..." into a real absolute path -- the debug
    ;; adapter and the inferior process can't expand "~" themselves.
    (expand-file-name (or root (my/project-root)))))

(defun my/cmake-configure ()
  "Configure a CMake project into ./build with compile_commands.json + debug info.
Runs in the CMake project root, found by searching upward for CMakeLists.txt."
  (interactive)
  (let ((default-directory (my/cmake-root)))
    (message "CMake root: %s" default-directory)
    (compile (concat "cmake -S . -B build "
                     "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON "
                     "-DCMAKE_BUILD_TYPE=Debug"))))

(defun my/cmake-build ()
  "Build the CMake project in ./build using all cores.
Runs in the CMake project root, found by searching upward for CMakeLists.txt."
  (interactive)
  (let ((default-directory (my/cmake-root)))
    (compile "cmake --build build -j")))

(defun my/clangd-point-to-build ()
  "Write a .clangd file so clangd reads build/compile_commands.json.
Written at the CMake project root.  Run this once per project after the
first CMake configure; then clangd gets accurate flags with no symlinking."
  (interactive)
  (let ((file (expand-file-name ".clangd" (my/cmake-root))))
    (with-temp-file file
      (insert "CompileFlags:\n  CompilationDatabase: build\n"))
    (message "Wrote %s — clangd now uses build/.  Restart eglot to apply." file)))

;; --- Colorized, auto-scrolling compile buffer -------------------------------
(setq compilation-scroll-output 'first-error
      compilation-ask-about-save nil
      compilation-always-kill t)
(with-eval-after-load 'compile
  (require 'ansi-color)
  (add-hook 'compilation-filter-hook #'ansi-color-compilation-filter))

;; Pin the compilation window to the bottom at 30% height; reuse it on
;; rebuilds so it never spawns an additional split.
(add-to-list 'display-buffer-alist
             '("\\*compilation\\*"
               (display-buffer-reuse-window display-buffer-at-bottom)
               (window-height . 0.25)))

;; Auto-close after a clean build (1.5 s delay so you can see "finished").
;; Errors keep the window open so you can read them.
(defun my/compilation-auto-close (buf string)
  (when (string-match-p "finished" string)
    (run-with-timer 1.5 nil #'delete-windows-on buf)))
(add-hook 'compilation-finish-functions #'my/compilation-auto-close)

;; --- Debugging via DAP (dape): works with lldb and gdb ----------------------
;; `C-c d d' prompts for a configuration.  Use `lldb-cmake' (macOS) or
;; `gdb-cmake' (Linux) below -- they find your built executable automatically
;; instead of LLDB's bogus default of "a.out".

(defun my/lldb-dap-path ()
  "Locate an lldb-dap executable on PATH or in common macOS LLVM locations."
  (or (executable-find "lldb-dap")
      (executable-find "lldb-vscode")
      (seq-find #'file-executable-p
                (list "/opt/homebrew/opt/llvm/bin/lldb-dap"
                      "/usr/local/opt/llvm/bin/lldb-dap"
                      "/Library/Developer/CommandLineTools/usr/bin/lldb-dap"))
      "lldb-dap"))                      ; bare name -> a clear "not found" error

(defun my/debug-find-executable ()
  "Return the program to debug: the built binary under ./build, or ask.
Walks up to the CMake root, looks for an executable file in build/,
returns it when there's exactly one, otherwise prompts."
  (let* ((root  (my/cmake-root))
         (build (expand-file-name "build" root))
         (exes  (when (file-directory-p build)
                  (seq-filter
                   (lambda (f)
                     (and (file-regular-p f)
                          (file-executable-p f)
                          (not (string-match-p "/CMakeFiles/" f))
                          (not (string-match-p
                                "\\.\\(o\\|a\\|so\\|dylib\\|cmake\\|txt\\|json\\|ninja\\)\\'"
                                f))))
                   (directory-files-recursively build "" nil)))))
    (cond ((null exes)
           (read-file-name "Executable to debug: " build nil t))
          ((= (length exes) 1) (car exes))
          (t (completing-read "Executable to debug: " exes nil t)))))

(use-package dape
  :init (setq dape-buffer-window-arrangement 'right
              dape-inlay-hints t)
  :bind (("C-c d d" . dape)                      ; start / pick a debug config
         ("C-c d b" . dape-breakpoint-toggle)
         ("C-c d B" . dape-breakpoint-remove-all)
         ("C-c d c" . dape-continue)
         ("C-c d n" . dape-next)                 ; step over
         ("C-c d s" . dape-step-in)
         ("C-c d o" . dape-step-out)
         ("C-c d r" . dape-restart)
         ("C-c d p" . dape-pause)
         ("C-c d i" . dape-info)                 ; locals / stack / breakpoints
         ("C-c d e" . dape-evaluate-expression)  ; eval expr at point / minibuffer
         ("C-c d w" . dape-watch-dwim)           ; add expression to the Watch list
         ("C-c d R" . dape-repl)
         ("C-c d q" . dape-quit))
  :config
  ;; Ready-made configs that build first, then debug ./build/<exe>.
  (add-to-list 'dape-configs
               `(lldb-cmake
                 modes (c-mode c-ts-mode c++-mode c++-ts-mode rust-mode rust-ts-mode)
                 ensure dape-ensure-command
                 command my/lldb-dap-path
                 command-cwd my/cmake-root
                 compile "cmake --build build -j"
                 :type "lldb-dap"
                 :request "launch"
                 :cwd my/cmake-root
                 :program my/debug-find-executable
                 :stopOnEntry nil))
  (add-to-list 'dape-configs
               `(gdb-cmake
                 modes (c-mode c-ts-mode c++-mode c++-ts-mode rust-mode rust-ts-mode)
                 ensure dape-ensure-command
                 command "gdb"
                 command-args ("--interpreter=dap")
                 command-cwd my/cmake-root
                 compile "cmake --build build -j"
                 :request "launch"
                 :cwd my/cmake-root
                 :program my/debug-find-executable
                 :stopAtBeginningOfMainSubprogram nil))

  ;; When the debuggee exits, lldb-dap fires a `stopped' event with
  ;; reason "exited" before tearing down the session.  Without this,
  ;; dape fetches the current frame and drops you into assembly for
  ;; the C-runtime teardown.  Quit immediately instead.
  (defun my/dape-quit-on-process-exit ()
    (when-let* ((conn (dape--live-connection 'last t)))
      (when (equal (dape--state-reason conn) "exited")
        (run-with-timer 0 nil #'dape-quit))))
  (add-hook 'dape-stopped-hook #'my/dape-quit-on-process-exit)

  ;; The Locals/Stack/Breakpoints side windows are born from a plain 50/50
  ;; split and never grow with their content.  In the GUI that 50% is wide
  ;; enough to read; in a narrower terminal frame it isn't, which is why it
  ;; looks fine one place and cramped the other.  Auto-fit each side window
  ;; to its longest line (capped so it can't swallow the source window)
  ;; every time dape refreshes the UI, so both front ends behave the same.
  (defun my/dape-fit-info-windows ()
    "Resize dape-info side windows to fit their buffer content."
    (dolist (win (window-list))
      (with-current-buffer (window-buffer win)
        (when (derived-mode-p 'dape-info-parent-mode)
          (let ((fit-window-to-buffer-horizontally t))
            (fit-window-to-buffer win nil nil 100 20))))))
  (add-hook 'dape-update-ui-hook #'my/dape-fit-info-windows))

;; dape-repl is comint-derived and the debuggee's stdout often arrives with
;; \r\n line endings (pty translation, Windows-built binaries, etc.), which
;; Emacs renders as a literal ^M.  Strip it in every comint buffer (repl,
;; shell, compile) instead of just dape-repl, since the cause is generic.
(add-hook 'comint-output-filter-functions #'comint-strip-ctrl-m)

;; --- VSCode F-key debugging / navigation ------------------------------------
;; F5       Start or Continue   (VSCode: Start Debugging / Continue)
;; F10      Step Over           (VSCode: Step Over)
;; F11      Step Into           (VSCode: Step Into)
;; S-F11    Step Out            (VSCode: Step Out)
;; F12      Go to Definition    (VSCode: Go to Definition)
(defun my/dape-f5 ()
  "VSCode F5: continue a paused session; start dape if none exists."
  (interactive)
  ;; dape--live-connection 'stopped returns the paused connection or nil (nowarn=t).
  ;; All dape commands take conn via their interactive spec, so call-interactively
  ;; is required — a bare (dape-continue) call skips the interactive form and
  ;; immediately signals wrong-number-of-arguments.
  (if (and (featurep 'dape) (dape--live-connection 'stopped t))
      (call-interactively #'dape-continue)
    (call-interactively #'dape)))

(global-set-key (kbd "<f5>")    #'my/dape-f5)
(global-set-key (kbd "<f10>")   #'dape-next)
(global-set-key (kbd "<f11>")   #'dape-step-in)
(global-set-key (kbd "S-<f11>") #'dape-step-out)
(global-set-key (kbd "<f12>")   #'xref-find-definitions)

;; --- Format C/C++ on save with clang-format (apheleia) ----------------------
;; Picks up a .clang-format file in the project if present; otherwise uses
;; clang-format's LLVM default.  Scoped to C/C++ only so other languages are
;; untouched.  Requires the `clang-format' binary on PATH.
(use-package apheleia
  :hook ((c-ts-mode c++-ts-mode c-mode c++-mode) . apheleia-mode)
  :config
  (add-to-list 'apheleia-mode-alist '(c-ts-mode . clang-format))
  (add-to-list 'apheleia-mode-alist '(c++-ts-mode . clang-format)))

;; --- Extras: view disassembly for the function/region at point --------------
(use-package disaster
  :commands (disaster)
  :init (with-eval-after-load 'cc-mode
          (define-key prog-mode-map (kbd "C-c x d") #'disaster)))

;; --- Toolchain doctor: what can Emacs actually find? ------------------------
(defun my/cpp-doctor ()
  "Report which C/C++ toolchain programs Emacs can locate on its PATH."
  (interactive)
  (let ((tools '(("clangd"       . "LSP: completion, diagnostics, navigation")
                 ("clang-format" . "format-on-save")
                 ("clang-tidy"   . "lint")
                 ("cmake"        . "build system  (C-c c g / C-c c b)")
                 ("make"         . "Makefile builds")
                 ("lldb-dap"     . "debug adapter (LLVM) -- needed by C-c d d")
                 ("gdb"          . "debug adapter (alternative)")
                 ("rg"           . "project search  (C-c f)")))
        (ok t))
    (with-current-buffer (get-buffer-create "*cpp-doctor*")
      (erase-buffer)
      (insert "C/C++ toolchain — as seen by Emacs\n")
      (insert "==================================\n\n")
      (dolist (tc tools)
        (let ((found (executable-find (car tc))))
          (unless found (setq ok nil))
          (insert (format "  %-14s %s\n                 %s\n\n"
                          (car tc)
                          (if found (concat "✓ " found) "✗ MISSING")
                          (cdr tc)))))
      (insert (if ok
                  "All set — you're good to build and debug.\n"
                "Anything MISSING is either not installed or not on Emacs's PATH.\n\
See README.md → \"C/C++ prerequisites\" for the install commands, then\n\
restart Emacs so the new PATH is picked up.\n"))
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

;; --- Build / compile keybindings (global; handy in any language) ------------
(global-set-key (kbd "C-c c ?") #'my/cpp-doctor)      ; check the toolchain
(global-set-key (kbd "C-c c c") #'compile)            ; run an arbitrary build cmd
(global-set-key (kbd "C-c c r") #'recompile)          ; repeat the last build
(global-set-key (kbd "C-c c k") #'kill-compilation)
(global-set-key (kbd "C-c c g") #'my/cmake-configure) ; (g)enerate build dir
(global-set-key (kbd "C-c c b") #'my/cmake-build)
(global-set-key (kbd "C-c c j") #'my/clangd-point-to-build)

;;; ----------------------------------------------------------------------------
;;; VSCode-style editing: deletes, word motion, undo/redo, multiple cursors
;;; ----------------------------------------------------------------------------

;; --- Deletes that do NOT touch the kill ring (clipboard) ---------------------
(defun my/delete-word (arg)
  "Delete characters forward to end of word.  Do NOT save to the kill ring.
With prefix ARG, delete that many words."
  (interactive "p")
  (delete-region (point) (progn (forward-word arg) (point))))

(defun my/backward-delete-word (arg)
  "Delete characters backward to start of word.  Do NOT save to the kill ring.
This is the VSCode/Option-Backspace behavior."
  (interactive "p")
  (my/delete-word (- arg)))

;; --- Smart Home: bounce between first non-whitespace and column 0 ------------
(defun my/smart-beginning-of-line ()
  "Move to first non-whitespace char; press again to go to column 0 (VSCode Home)."
  (interactive)
  (let ((orig (point)))
    (back-to-indentation)
    (when (= orig (point))
      (move-beginning-of-line 1))))

;; --- Duplicate the current line up or down (VSCode Shift+Alt+Up/Down) --------
(defun my/copy-line-down ()
  "Duplicate the current line below and keep the cursor column."
  (interactive)
  (let ((col (current-column))
        (text (buffer-substring (line-beginning-position) (line-end-position))))
    (end-of-line) (newline) (insert text) (move-to-column col)))

(defun my/copy-line-up ()
  "Duplicate the current line above and keep the cursor column."
  (interactive)
  (let ((col (current-column))
        (text (buffer-substring (line-beginning-position) (line-end-position))))
    (beginning-of-line) (insert text) (newline) (forward-line -1)
    (move-to-column col)))

;; --- Add a cursor on the line above/below (VSCode Alt+Cmd+Up/Down) -----------
(defun my/mc-add-cursor-below ()
  "Add a fake cursor on the next line (keeps adding downward)."
  (interactive)
  (require 'multiple-cursors)
  (let ((col (current-column)))
    (mc/create-fake-cursor-at-point)
    (forward-line 1)
    (move-to-column col))
  (mc/maybe-multiple-cursors-mode))

(defun my/mc-add-cursor-above ()
  "Add a fake cursor on the previous line (keeps adding upward)."
  (interactive)
  (require 'multiple-cursors)
  (let ((col (current-column)))
    (mc/create-fake-cursor-at-point)
    (forward-line -1)
    (move-to-column col))
  (mc/maybe-multiple-cursors-mode))

;; --- Robust, linear undo/redo (terminal-friendly) -----------------------------
;; C-z is avoided: in a terminal it sends SIGTSTP and backgrounds Emacs.
;; C-/ and C-M-/ both survive terminal mode (no Shift-modifier ambiguity).
(use-package undo-fu
  :config
  (global-set-key (kbd "C-/")   #'undo-fu-only-undo)
  (global-set-key (kbd "C-M-/") #'undo-fu-only-redo))

(use-package undo-fu-session
  :after undo-fu
  :config (undo-fu-session-global-mode 1)) ; undo history survives restarts

;; --- Move lines/regions up and down (VSCode Alt+Up/Down) ---------------------
(use-package move-text
  :config (move-text-default-bindings)) ; binds M-up / M-down

;; --- Expand selection by semantic units (VSCode Shift+Alt+Right) -------------
(use-package expand-region
  :bind (("C-=" . er/expand-region)
         ("C-+" . er/contract-region)))

;; --- Jump anywhere on screen -------------------------------------------------
(use-package avy
  :bind (("C-;" . avy-goto-char-timer)
         ("C-:" . avy-goto-line)))

;; --- Multiple cursors that behave like VSCode --------------------------------
(use-package multiple-cursors
  :init (setq mc/always-run-for-all t)
  :bind (("C-d"          . mc/mark-next-like-this-word)  ; add next occurrence (Cmd+D)
         ("C->"          . mc/mark-next-like-this)
         ("C-<"          . mc/mark-previous-like-this)
         ("C-c C-d"      . mc/mark-all-like-this-dwim)   ; select all occurrences
         ("C-c C-SPC"    . mc/edit-lines)                ; cursor per selected line
         ("C-S-<down>"   . my/mc-add-cursor-below)
         ("C-S-<up>"     . my/mc-add-cursor-above)
         ("C-S-<mouse-1>" . mc/add-cursor-on-click)))    ; Ctrl-Shift click adds cursor

;;; ----------------------------------------------------------------------------
;;; Global keybindings (the "standard editor" layer)
;;; ----------------------------------------------------------------------------
;; Deletes (no clipboard pollution) — the headline request.
(global-set-key (kbd "M-DEL")        #'my/backward-delete-word)
(global-set-key (kbd "<M-backspace>") #'my/backward-delete-word)
(global-set-key (kbd "<C-backspace>") #'my/backward-delete-word)
(global-set-key (kbd "M-d")          #'my/delete-word)
(global-set-key (kbd "<C-delete>")   #'my/delete-word)

;; Home/End like a normal editor.
(global-set-key (kbd "C-a")   #'my/smart-beginning-of-line)
(global-set-key (kbd "<home>") #'my/smart-beginning-of-line)

;; Line manipulation.
(global-set-key (kbd "M-S-<down>") #'my/copy-line-down)   ; duplicate down
(global-set-key (kbd "M-S-<up>")   #'my/copy-line-up)     ; duplicate up

;; Comment toggle (moved off C-/, which now drives undo).
(global-set-key (kbd "M-;")   #'comment-line)

;; Quick window / buffer ops.
(global-set-key (kbd "C-c k") #'kill-current-buffer)
(global-set-key (kbd "M-o")   #'other-window)

;;; ----------------------------------------------------------------------------
;;; Better help, project, version control
;;; ----------------------------------------------------------------------------
(use-package helpful
  :bind (([remap describe-function] . helpful-callable)
         ([remap describe-variable] . helpful-variable)
         ([remap describe-key]      . helpful-key)
         ([remap describe-command]  . helpful-command)
         ("C-h F" . helpful-function)))

(use-package magit
  :bind (("C-x g" . magit-status))
  ;; :commands (magit-status magit-dispatch)
  :init (setq magit-define-global-key-bindings nil))

;; project.el is built in; just give it a friendlier search default.
(use-package project
  :ensure nil
  :bind (("C-x p" . project-prefix-map)))

;; Trim only the whitespace you actually touched (no noisy diffs).
(use-package ws-butler
  :hook ((prog-mode text-mode conf-mode) . ws-butler-mode))

;;; ----------------------------------------------------------------------------
;;; Terminal niceties: mouse + real system clipboard over SSH/tmux
;;; ----------------------------------------------------------------------------
(unless (display-graphic-p)
  (xterm-mouse-mode 1)                  ; click, scroll, select with the mouse
  (setq mouse-wheel-up-event 'mouse-5
        mouse-wheel-down-event 'mouse-4))

;; clipetty pushes kills to the system clipboard via OSC-52 even inside a
;; terminal / tmux / SSH session, so copy/paste "just works" everywhere.
(use-package clipetty
  :hook (after-init . global-clipetty-mode))

;; install nerd fonts if not installed (GUI only: `find-font' can't see
;; installed fonts from a terminal frame, so this check always "fails"
;; and re-downloads on every -nw launch if left unguarded).
(use-package nerd-icons
  :ensure t
  :config
  ;; 1. Define a helper function to verify if a font is accessible by Emacs
  (defun my/font-available-p (font-name)
    "Return non-nil if FONT-NAME is available on the system."
    (and (fboundp 'find-font)
         (find-font (font-spec :name font-name))))

  ;; 2. Automatically download the glyph pack if it's missing
  (when (display-graphic-p)
    (unless (my/font-available-p "Symbols Nerd Font Mono")
      (message "Nerd Fonts missing! Initiating automated download...")
      ;; This non-interactive flag forces the download without prompting you for a [y/n] confirmation
      (nerd-icons-install-fonts t))))

;; ADDITIONAL (UNRELATED TO CPP DEV)


(use-package volatile-highlights
  :defer t
  :ensure t
  :hook
  (after-init . volatile-highlights-mode))

;; the scratch buffer will persist between runs
(use-package persistent-scratch
  :ensure t
  :defer t
  ;; This tells use-package to load the package
  ;; automatically after Emacs finishes initializing
  :hook (after-init . persistent-scratch-setup-default)
  :config
  (progn
    (setq scratch-buffers '("*scratch*" "*copy-log*"))
    (persistent-scratch-autosave-mode)))

(use-package saveplace
  :defer t
  :ensure t
  :hook (after-init . save-place-mode)
  :config
  (setq save-place t) ; Enable save-place-mode
  (setq save-place-file (concat user-emacs-directory "places"))) ; Set the save file location

(use-package free-keys
  :defer t
  :ensure nil
  :commands free-keys)

(use-package helpful
  :defer t
  :ensure t
  :bind
  (("C-h f" . helpful-callable)
   ("C-h v" . helpful-variable)
   ("C-h k" . helpful-key)
   ("C-c C-d" . helpful-at-point)
   ("C-h F" . helpful-function)
   ("C-h C" . helpful-command)))


(use-package winner
  :defer t
  :ensure nil ;; Built-in package, so no installation is needed
  :hook (after-init . winner-mode) ;; Enable winner-mode after Emacs starts
  :bind (("C-c <left>"  . winner-undo)  ;; Undo window layout changes
         ("C-c <right>" . winner-redo)) ;; Redo window layout changes
  :custom
  (winner-boring-buffers '("*Completions*" "*Compile-Log*" "*helm*" "*Help*"))
  :config
  (message "Winner mode is active!"))



;; move where i mean
(use-package mwim
  :defer t
  :ensure t
  :bind
  ("C-a" . mwim-beginning-of-code-or-line)
  ("C-e" . mwim-end-of-code-or-line))

(use-package windmove
  :ensure nil
  :config
  (windmove-default-keybindings))

;;; init.el ends here
(provide 'init)
