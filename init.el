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
        (set-face-attribute 'default nil :family f :height 180) ; 18pt
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
  (setq completion-styles '(orderless basic)
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

;; Render the Corfu popup in text terminals. Only needed before Emacs 31:
;; with tty child frames Corfu draws its popup in a terminal on its own,
;; and warns "`corfu-terminal' is not needed" if this package loads anyway.
(use-package corfu-terminal
  :unless (or (display-graphic-p) (featurep 'tty-child-frames))
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
                    ;; Without this, clangd's own GCC-toolchain
                    ;; auto-detection can silently disagree with the
                    ;; compiler compile_commands.json actually recorded --
                    ;; e.g. on a system with both gcc-13 (full C++ headers)
                    ;; and a partial gcc-14 (C only, no headers) installed
                    ;; side by side, clangd defaulted to the newest version
                    ;; number regardless of which one the project actually
                    ;; built with, producing bogus "'vector' file not
                    ;; found" errors on a project that compiles fine. This
                    ;; lets clangd actually invoke whatever gcc/g++/clang
                    ;; driver compile_commands.json names, to ask it
                    ;; directly for its real search paths, instead of
                    ;; guessing. No hardcoded path/version -- portable
                    ;; across machines and GCC/Clang versions.
                    "--query-driver=/usr/bin/**,/usr/local/bin/**,/opt/homebrew/**/bin/**"
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

(defun my/cxx-compiler-override ()
  "On Linux, prefer the newest g++-N found on PATH; nil elsewhere.
Ubuntu's apt packages leave the default `c++'/`g++' symlink pointed at
whichever version was installed first, even after a newer one (e.g.
g++-14, installed for C++23 std-lib support -- see README) lands
alongside it.  Each GCC version only searches its own matching
/usr/include/c++/N headers, so the build has to be pointed at the
newer compiler explicitly.  Not needed on macOS: Apple's clang already
tracks current C++ standards on its own."
  (when (eq system-type 'gnu/linux)
    (car (sort
          (seq-mapcat
           (lambda (dir)
             (and (file-directory-p dir)
                  (directory-files dir t "\\`g\\+\\+-[0-9]+\\'")))
           exec-path)
          (lambda (a b)
            (> (string-to-number
                (car (last (split-string (file-name-nondirectory a) "-"))))
               (string-to-number
                (car (last (split-string (file-name-nondirectory b) "-"))))))))))

(defun my/cmake-configure ()
  "Configure a CMake project into ./build with compile_commands.json + debug info.
Runs in the CMake project root, found by searching upward for CMakeLists.txt."
  (interactive)
  (let ((default-directory (my/cmake-root)))
    (message "CMake root: %s" default-directory)
    (compile (concat "cmake -S . -B build "
                     "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON "
                     "-DCMAKE_BUILD_TYPE=Debug"
                     (if-let* ((cxx (my/cxx-compiler-override)))
                         (format " -DCMAKE_CXX_COMPILER=%s" (shell-quote-argument cxx))
                       "")))))

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
  "Locate an lldb-dap executable on PATH or in common install locations."
  (or (executable-find "lldb-dap")
      (executable-find "lldb-vscode")
      (seq-find #'file-executable-p
                (list "/opt/homebrew/opt/llvm/bin/lldb-dap"
                      "/usr/local/opt/llvm/bin/lldb-dap"
                      "/Library/Developer/CommandLineTools/usr/bin/lldb-dap"))
      ;; Debian/Ubuntu's llvm packages only ship versioned binaries
      ;; (lldb-dap-18, lldb-dap-19, ...), never the bare `lldb-dap' name --
      ;; unlike lldb/lldb-server/lldb-argdumper, which DO get an unversioned
      ;; symlink via the separate `lldb' apt package.  lldb-dap was simply
      ;; left out of that convenience symlink set (checked directly with
      ;; `update-alternatives --list lldb-dap`: no alternatives registered).
      ;; So: search PATH for any `lldb-dap-N' and take the highest N.  This
      ;; needs no maintenance when Ubuntu ships lldb-dap-19, -20, etc. --
      ;; it was tested against lldb-dap-18 (Ubuntu 24.04 noble) but doesn't
      ;; hardcode that version anywhere.
      (car (sort
            (seq-mapcat
             (lambda (dir)
               (and (file-directory-p dir)
                    (directory-files dir t "\\`lldb-dap-[0-9]+\\'")))
             exec-path)
            (lambda (a b)
              (> (string-to-number
                  (car (last (split-string (file-name-nondirectory a) "-"))))
                 (string-to-number
                  (car (last (split-string (file-name-nondirectory b) "-"))))))))
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
              ;; Inlay hints auto-evaluate every variable visible in the
              ;; source window on each stop.  If a breakpoint lands before a
              ;; local's constructor has run -- e.g. a std::vector with
              ;; garbage begin/end pointers -- evaluating it can hang gdb's
              ;; pretty-printer instead of erroring, producing an :evaluate
              ;; timeout.  Off by default; explicit C-c d e / C-c d w still
              ;; work fine when you actually want a value.
              dape-inlay-hints nil)
  :bind (("C-c d d" . dape)                      ; start / pick a debug config
         ("C-c d b" . dape-breakpoint-toggle)
         ("C-c d B" . dape-breakpoint-remove-all)
         ("C-c d C" . dape-breakpoint-expression) ; conditional breakpoint at point
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
  ;; NOTE: gdb 15.1's DAP mode (Ubuntu 24.04) has two confirmed bugs that
  ;; make it unreliable for this workflow: (1) `launch' doesn't wait for
  ;; `configurationDone' before running, so breakpoints often lose the race
  ;; against a fast program and never bind; (2) evaluating an uninitialized
  ;; STL object (e.g. a std::vector before its constructor runs) can hang
  ;; gdb's DAP command loop *permanently*, taking the whole session -- and
  ;; under load, the machine -- down with it. Neither bug exists in
  ;; lldb-dap; prefer `lldb-cmake' on Linux too when it's available
  ;; (`apt install lldb' -- Ubuntu ships it as a versioned binary like
  ;; lldb-dap-18, which `my/lldb-dap-path' finds automatically).  There is
  ;; no reliable client-side workaround for bug (1): forcing an early stop
  ;; via `stopAtBeginningOfMainSubprogram' just trades it for bug (2), since
  ;; dape auto-evaluates visible locals on every stop and that early stop
  ;; lands before their constructors run.
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

  ;; lldb-dap 18 crashes (free(): invalid pointer, or "terminate called
  ;; without an active exception") if sent a :terminate or :disconnect
  ;; request after the debuggee has already exited on its own -- confirmed
  ;; directly against the adapter, both requests reproduce it every time.
  ;; This isn't just our own dape-quit call above: dape.el's OWN built-in
  ;; handler for the adapter's `terminated' event *always* calls
  ;; `dape-kill' too, unconditionally, regardless of how the session got
  ;; there.  So the fix has to be in `dape-kill' itself: if the connection
  ;; already knows the debuggee is gone (state `exited' or `terminated'),
  ;; there's nothing left alive to ask to terminate -- skip the request
  ;; and close the connection directly instead of calling ORIG-FN.  This is
  ;; a no-op (falls through to ORIG-FN) for any adapter/state that doesn't
  ;; match, so it's safe cross-platform even where this bug doesn't exist.
  (define-advice dape-kill (:around (orig-fn conn &optional cb with-disconnect) my/skip-request-if-already-exited)
    (if (and conn (jsonrpc-running-p conn)
             (memq (dape--state conn) '(exited terminated)))
        (progn (dape--shutdown conn) (dape--request-continue cb))
      (funcall orig-fn conn cb with-disconnect)))

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
  (add-hook 'dape-update-ui-hook #'my/dape-fit-info-windows)

  ;; dape's own repeat map binds "e" to dape-breakpoint-expression (asks for
  ;; a "Condition:"), but our C-c d e goes to dape-evaluate-expression.
  ;; Realign so bare "e" during a repeat streak matches C-c d e, and give
  ;; the displaced conditional-breakpoint command its own key: "C".
  (define-key dape-global-map "e" #'dape-evaluate-expression)
  (define-key dape-global-map "C" #'dape-breakpoint-expression))

;; After any `C-c d <key>' command, let the bare key repeat it: `n' keeps
;; stepping over, `s'/`o' step in/out, `b' toggles a breakpoint, etc.  dape
;; already tags dape-next/dape-step-in/... with Emacs's `repeat-map'
;; property (see dape-global-map in dape.el) using the same letters as our
;; own C-c d bindings; repeat-mode is just off by default, so turn it on.
(repeat-mode 1)

;; The repeat-mode hint normally lives in the echo area, where it gets
;; clobbered by any other `message' call — compile output, "Compilation
;; finished", eldoc, dape's own status pings — which is constant background
;; noise while debugging.  Move the hint to the mode line instead: nothing
;; else writes there, so it stays visible for the whole repeat streak.
(defvar my/repeat-mode-line-string nil)

;; `mode-line-misc-info' is a standard component of every mode-line, so
;; `add-to-list'-ing onto its global value (the first thing tried here)
;; makes the hint show in every window, not just the one it's meant for.
;; Scope it locally to dape-repl instead, since that's the window that's
;; always on screen during a session and the natural "status bar" for it.
(add-hook 'dape-repl-mode-hook
          (lambda ()
            (setq-local mode-line-misc-info
                        (cons '(my/repeat-mode-line-string my/repeat-mode-line-string)
                              mode-line-misc-info))))

;; dape's own map has ~29 keys (see dape-global-map); showing all of them
;; makes for an unreadably long mode line.  Trim to the handful actually
;; used mid-session — see the "Most used" table in README.md.  Any other
;; repeat map (C-x o, M-g M-n, ...) that doesn't define these keys falls
;; back to the full list, so this stays generically useful, not dape-only.
(defvar my/repeat-mode-line-primary-keys '(?n ?s ?o ?c ?b ?C ?e)
  "Keys shown in the trimmed repeat-mode mode-line hint, in display order.")

(defun my/repeat-echo-mode-line (keymap)
  "Show a trimmed repeat-mode hint for KEYMAP in the mode line."
  (setq my/repeat-mode-line-string
        (when keymap
          (let ((keys (seq-filter (lambda (k) (lookup-key keymap (vector k)))
                                   my/repeat-mode-line-primary-keys)))
            (propertize
             (concat " "
                     (if keys
                         (format "Repeat with %s"
                                 (mapconcat (lambda (k) (key-description (vector k)))
                                            keys ", "))
                       (repeat-echo-message-string keymap))
                     " ")
             'face 'mode-line-emphasis))))
  (force-mode-line-update t))

(setq repeat-echo-function #'my/repeat-echo-mode-line)

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
This is the VSCode/Option-Backspace behavior: stops at the left margin
instead of crossing into the line above.  Pressed again right at column
0, it deletes the newline, joining with the line above -- also VSCode's
behavior."
  (interactive "p")
  (if (bolp)
      (unless (bobp)
        (delete-char -1))
    (let ((start (point))
          (target (save-excursion (forward-word (- arg)) (point))))
      (delete-region start (max target (line-beginning-position))))))

;; --- Jump to the matching brace/paren/bracket/quote, vi-%/VSCode-Go-to-Bracket
;; A hand-rolled version of this (using the syntax table directly) got
;; confused in C++: template angle brackets (`vector<int>') aren't a real
;; delimiter pair, but naive bracket-scanning doesn't know that, so it could
;; overshoot.  smartparens' own sexp-scanning already knows exactly which
;; characters are configured as real pairs per major mode, so delegate to it
;; instead of re-deriving that logic by hand.
(use-package smartparens
  :config (require 'smartparens-config))

(defun my/goto-match-paren ()
  "Jump to the matching delimiter: parens, brackets, braces, or quotes.
Works whether point sits just before an opening delimiter or just
after a closing one.  Call again from the destination to jump back.
If a region is active (e.g. after C-SPC), the jump extends the
selection instead of collapsing it -- Emacs deactivates the mark
after any command by default unless told not to."
  (interactive)
  (setq deactivate-mark nil)
  (let ((forward (sp-get-sexp))
        (backward (sp-get-sexp t)))
    (cond
     ((and forward (= (plist-get forward :beg) (point)))
      (goto-char (plist-get forward :end)))
     ((and backward (= (plist-get backward :end) (point)))
      (goto-char (plist-get backward :beg)))
     (t (message "Not on a matching delimiter")))))
;; Deliberately NOT on a C-c/C-x/C-v prefix: cua-mode rebinds all three of
;; those to fire copy/cut/paste immediately whenever a region is active
;; (with only a brief timing-based window to fall through to their normal
;; prefix-key role), so C-c <letter> is unreachable -- typing the second
;; key just self-inserts and replaces the selection.  That timing window
;; is also tuned for local keyboard latency, not SSH, so it's especially
;; unreliable here.  C-% isn't one of the three keys CUA intercepts, so
;; it works the same whether or not a region is active.
(global-set-key (kbd "C-%") #'my/goto-match-paren)

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

  ;; 2. Windows: `nerd-icons-install-fonts' only knows the Linux/macOS font
  ;; dirs, so on Windows it prompts for a "Font installation directory" and
  ;; then just downloads the file -- Windows fonts must also be registered,
  ;; so the font stays missing and the prompt comes back every launch.
  ;; Install per-user instead: same file, into the user font dir, registered
  ;; under HKCU (no admin). Takes effect on the next Emacs start.
  (defun my/install-nerd-icons-font-windows ()
    "Download and register the nerd-icons font for the current Windows user."
    (interactive)
    (let* ((dir (expand-file-name "Microsoft/Windows/Fonts/" (getenv "LOCALAPPDATA")))
           (dest (expand-file-name "SymbolsNerdFontMono-Regular.ttf" dir))
           (win-dest (subst-char-in-string ?/ ?\\ dest)))
      (make-directory dir t)
      (url-copy-file "https://raw.githubusercontent.com/rainstormstudio/nerd-icons.el/main/fonts/NFM.ttf"
                     dest t)
      (call-process "reg" nil nil nil "add"
                    "HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts"
                    "/v" "Symbols Nerd Font Mono (TrueType)" "/t" "REG_SZ"
                    "/d" win-dest "/f")
      (message "Installed Symbols Nerd Font Mono to %s -- restart Emacs to use it" win-dest)))

  ;; 3. Automatically download the glyph pack if it's missing
  (when (display-graphic-p)
    (unless (my/font-available-p "Symbols Nerd Font Mono")
      (message "Nerd Fonts missing! Initiating automated download...")
      (if (eq system-type 'windows-nt)
          (my/install-nerd-icons-font-windows)
        ;; This non-interactive flag forces the download without prompting you for a [y/n] confirmation
        (nerd-icons-install-fonts t)))))

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

;;; ----------------------------------------------------------------------------
;;; Mail: mu4e + mbsync (Gmail), signed/encrypted via the YubiKey OpenPGP card
;;; forwarded from the local machine over the ssh gpg-agent-extra-socket
;;; forward (see ~/.ssh/config Host ubuntu.local on the client side). PIN and
;;; touch prompts appear on the *client* machine, not here.
;;; ----------------------------------------------------------------------------
(let ((mu4e-dir
       (car (append
             (file-expand-wildcards "/usr/share/emacs/site-lisp/elpa/mu4e-*")
             (file-expand-wildcards "/opt/homebrew/Cellar/mu/*/share/emacs/site-lisp/mu/mu4e")
             (file-expand-wildcards "/usr/local/Cellar/mu/*/share/emacs/site-lisp/mu/mu4e")))))
  (if mu4e-dir
      (add-to-list 'load-path mu4e-dir)
    (message "mu4e: not installed on this machine (apt mu4e-elpa or brew mu); mail disabled")))
;; Soft require: mu/mu4e has no native Windows build, and a hard failure here
;; would abort init. Everything below is plain setq/defun on top of built-in
;; libraries (smtpmail, mml2015, gnus-art), so it's harmless without mu4e;
;; the one mu4e-dependent form (the keymap binding) waits on eval-after-load.
(require 'mu4e nil t)

(setq mu4e-maildir "~/Mail"
      mu4e-get-mail-command "mbsync -a"
      mu4e-update-interval 300 ; Update every 5 minutes
      mu4e-attachment-dir  "~/Downloads"
      mu4e-change-filenames-when-moving t) ; mbsync/maildir-friendly renames

;; Configure folders (Gmail uses [Gmail]/...)
(setq mu4e-drafts-folder "/[Gmail]/Drafts"
      mu4e-sent-folder   "/[Gmail]/Sent Mail"
      mu4e-trash-folder  "/[Gmail]/Trash"
      mu4e-refile-folder "/[Gmail]/All Mail")

;; Sending Mail via SMTP (Emacs' built-in smtpmail, no local MTA needed)
(setq message-send-mail-function 'smtpmail-send-it
      smtpmail-starttls-credentials '(("smtp.gmail.com" 587 nil nil))
      smtpmail-default-smtp-server "smtp.gmail.com"
      smtpmail-smtp-server "smtp.gmail.com"
      smtpmail-smtp-service 587)

(setq user-mail-address "jclosure@gmail.com"
      user-full-name    "Joel Holder")

;;; --- PGP/MIME signing & encryption (mml2015 -> gpg -> forwarded agent) -----
(require 'mml2015)
(setq mml2015-use 'epg               ; use Emacs' epg.el, talks to gpg/gpg-agent
      mml2015-encrypt-to-self t      ; always add yourself as a recipient too
      mml2015-sign-with-sender t)    ; pick the signing key from the From: address
;; Don't set epg-pinentry-mode to 'loopback here: leaving it at the default
;; means the (forwarded) local gpg-agent uses ITS OWN pinentry-program
;; (pinentry-qt) on the client, popping the PIN/touch prompt there.

;; Signature verification on incoming mail (mm-decode, not mml2015 - separate
;; layer, separate defaults). mm-decrypt-option defaults to nil, which Gnus
;; treats as "ask" - that's why decrypting already worked with no setup here.
;; mm-verify-option's default is the literal symbol 'never - explicitly
;; suppressed, not "ask" - so a signed message's signature was never actually
;; being checked, no matter what key you pressed; there's no dedicated
;; "verify" key in mu4e, it's supposed to just happen automatically on open,
;; same as decrypt. Both MIME container types need to be buttonized
;; explicitly: the Ubuntu/Debian Emacs 29 Gnus build leaves this variable nil,
;; while the Mac build supplies multipart/alternative by default. Without the
;; explicit entries, HTML/plain-format chooser buttons disappear on Linux.
(require 'gnus-art) ; gnus-buttonized-mime-types lives here, not autoloaded
(setq mm-verify-option 'always)
(add-to-list 'gnus-buttonized-mime-types "multipart/signed")
(add-to-list 'gnus-buttonized-mime-types "multipart/alternative")

;; Preserve HTML section/heading colors, but ask SHR to correct low contrast.
;; Defaults are distance 5 / luminance 40; 10 / 60 follows Tassilo Horn's
;; example: https://yhetil.org/emacs-user/877g3cfnwp.fsf@gnu.org/
;; Bind for the whole render, including temporary table-cell buffers. EWW
;; and other SHR consumers retain their own color settings.
(defvar shr-use-colors)
(defvar shr-color-visible-distance-min)
(defvar shr-color-visible-luminance-min)
(defvar my/mu4e-rendering nil)

(defun my/mu4e-strip-terminal-face-extension (face)
  "Remove `:extend' from FACE when it is a face property plist."
  (cond
   ((and (listp face) (keywordp (car face)))
    (let ((rest (copy-sequence face)) result)
      (while rest
        (let ((key (pop rest))
              (value (pop rest)))
          (unless (eq key :extend)
            (setq result (cons value (cons key result))))))
      (nreverse result)))
   ((listp face) (mapcar #'my/mu4e-strip-terminal-face-extension face))
   (t face)))

(defun my/mu4e-no-terminal-background-extension
    (add-face start end face &optional append object)
  "Call ADD-FACE without SHR's line-extending background on a terminal."
  (funcall add-face start end
           (if (and my/mu4e-rendering (not (display-graphic-p)))
               (my/mu4e-strip-terminal-face-extension face)
             face)
           append object))

;; HTML mail commonly supplies white, gray, or very pale backgrounds. Keep
;; those colored regions, but translate them into a small set of muted
;; Catppuccin-Mocha colors so they fit the dark Emacs frame. Colored sender
;; backgrounds retain their hue family; neutral backgrounds use surfaces.
(defcustom my/mu4e-html-background-palette
  '((neutral-dark . "#181825")
    (neutral . "#313244")
    (rose . "#4a303b")
    (peach . "#4b3b2f")
    (green . "#304338")
    (teal . "#2d4144")
    (blue . "#303a52")
    (mauve . "#403450")
    (pink . "#493342"))
  "Curated dark backgrounds for colored HTML mail regions."
  :type '(alist :key-type symbol :value-type color))

(defun my/mu4e-html-color-rgb (hex)
  "Parse HEX into normalized RGB values without relying on frame colors."
  (let* ((digits (and (string-prefix-p "#" hex) (substring hex 1)))
         (length (and digits (length digits))))
    (when (and length (memq length '(3 6 12)))
      (let* ((width (/ length 3))
             (maximum (float (1- (expt 16 width)))))
        (mapcar (lambda (start)
                  (/ (string-to-number
                      (substring digits start (+ start width)) 16)
                     maximum))
                (list 0 width (* 2 width)))))))

(defun my/mu4e-html-background-color (background)
  "Map HTML BACKGROUND to a readable, muted mu4e palette color."
  (let* ((hex (and background (shr-color->hexadecimal background)))
         (rgb (and hex (my/mu4e-html-color-rgb hex)))
         (hsl (and rgb (apply #'color-rgb-to-hsl rgb)))
         (hue (and hsl (nth 0 hsl)))
         (saturation (and hsl (nth 1 hsl)))
         (lightness (and hsl (nth 2 hsl))))
    (cond
     ((null hsl) background)
     ((< saturation 0.12)
      (alist-get (if (< lightness 0.25) 'neutral-dark 'neutral)
                my/mu4e-html-background-palette))
     ((or (< hue 0.06) (>= hue 0.94))
      (alist-get 'rose my/mu4e-html-background-palette))
     ((< hue 0.16) (alist-get 'peach my/mu4e-html-background-palette))
     ((< hue 0.43) (alist-get 'green my/mu4e-html-background-palette))
     ((< hue 0.58) (alist-get 'teal my/mu4e-html-background-palette))
     ((< hue 0.72) (alist-get 'blue my/mu4e-html-background-palette))
     ((< hue 0.88) (alist-get 'mauve my/mu4e-html-background-palette))
     (t (alist-get 'pink my/mu4e-html-background-palette)))))

(defun my/mu4e-palette-color-check (check fg bg)
  "Call SHR color CHECK with a curated background during mu4e renders."
  (funcall check fg
           (if my/mu4e-rendering
               (my/mu4e-html-background-color bg)
             bg)))

(defun my/mu4e-readable-html-colors (render &rest args)
  "Call RENDER with ARGS, using stronger HTML contrast only in mu4e."
  (if (derived-mode-p 'mu4e-view-mode)
      (let ((my/mu4e-rendering t)
            (shr-use-colors t)
            (shr-color-visible-distance-min 10)
            (shr-color-visible-luminance-min 60))
        (apply render args))
    (apply render args)))
(with-eval-after-load 'shr
  (require 'shr-color)
  ;; Also support re-evaluating this block in a running Emacs.
  (advice-remove 'shr-insert-document #'my/mu4e-use-theme-colors)
  (advice-remove 'shr-color-check #'my/mu4e-palette-color-check)
  (advice-remove 'add-face-text-property
                 #'my/mu4e-no-terminal-background-extension)
  (advice-add 'shr-insert-document :around #'my/mu4e-readable-html-colors)
  ;; SHR renders table cells in temporary buffers, so the dynamic render flag
  ;; is more reliable than checking the current buffer's major mode here.
  (advice-add 'shr-color-check :around #'my/mu4e-palette-color-check)
  ;; `shr-colorize-region' uses :extend t for backgrounds. In a terminal that
  ;; paints past the actual mail region and produces colored lines jutting out
  ;; from the block, so keep backgrounds bounded to the rendered text there.
  (advice-add 'add-face-text-property :around
              #'my/mu4e-no-terminal-background-extension))

;; HTML mail panels for terminal Emacs.  shr paints an email's background
;; colors only under the text it draws, so in a terminal a colored section
;; shows up as a stack of lines of different lengths, with the indentation
;; and table padding left uncolored, instead of one solid block.
;;
;; After shr renders a mail part, square each colored section off into a
;; panel: table-cell padding becomes real spaces in the cell's color, every
;; line gets its section's background from the left edge out to one shared
;; right edge (the widest line of the part), gaps between runs of one color
;; take that color, and blank lines between lines of the same color are
;; filled too.  The email's own layout
;; (tables, columns, indentation) is left as shr drew it, and text that
;; already has its own background (buttons, badges) keeps it.  Colors still
;; come from the palette advice above.
;;
;; Also, scoped to mail rendering (mm-shr) so eww keeps its normal look:
;; - fill to a fixed readable width; mm-shr uses `fill-column' as the width
;;   when `shr-use-fonts' is nil
;; - drop aria-hidden junk (e.g. hidden preheader text)
;; shr has to be loaded first: init.el is lexically bound, so `let' on
;; a variable that isn't declared yet would bind it lexically and do nothing.
(require 'shr)

(defvar my/mail-html-max-width 100
  "Maximum column width for rendered HTML mail.")

(defun my/mail-face-background (face)
  "Return the background color in FACE (a face plist or list of them)."
  (cond ((null face) nil)
        ((and (consp face) (keywordp (car face))) (plist-get face :background))
        ((consp face) (seq-some #'my/mail-face-background face))))

(defun my/mail-background-at (pos)
  (my/mail-face-background (get-text-property pos 'face)))

(defun my/mail-line-background (bol eol)
  "Background covering at least half the visible text between BOL and EOL."
  (let ((counts nil) (total 0))
    (dotimes (i (- eol bol))
      (let ((pos (+ bol i)))
        (unless (memq (char-after pos) '(?\s ?\t))
          (setq total (1+ total))
          (when-let* ((bg (my/mail-background-at pos)))
            (setf (alist-get bg counts 0 nil #'equal)
                  (1+ (alist-get bg counts 0 nil #'equal)))))))
    (when-let* ((best (car (sort counts (lambda (a b) (> (cdr a) (cdr b)))))))
      (when (>= (* 2 (cdr best)) total)
        (car best)))))

(defun my/mail-expand-align-spaces (start end)
  "Turn shr's `:align-to' stretch characters into real spaces.
shr pads each table cell with one character whose display property
stretches it to the next column.  Text measurement (and so the panel
edge) only works on real spaces; the copies keep the cell's face, so
cells stay colored all the way across."
  (save-excursion
    (goto-char start)
    (let ((end (copy-marker end)))
      (while (< (point) end)
        (let ((display (get-text-property (point) 'display)))
          (if (not (and (eq (car-safe display) 'space)
                        (plist-get (cdr display) :align-to)))
              (goto-char (next-single-property-change (point) 'display nil end))
            (let* ((align (plist-get (cdr display) :align-to))
                   (column (if (consp align)
                               (/ (car align) (frame-char-width))
                             align))
                   (props (text-properties-at (point)))
                   (count (max 0 (- column (current-column))))
                   (spaces (make-string count ?\s)))
              (delete-char 1)
              (set-text-properties 0 count props spaces)
              (remove-text-properties 0 count '(display nil) spaces)
              (insert spaces)))))
      (set-marker end nil))))

(defun my/mail-pin-backgrounds (start end)
  "Keep the email's colors in front of named faces that carry a background.
Some shr faces inherit `default' (in Emacs 30 `shr-h5' and `shr-h6' are
just `(:inherit default)'), which brings the theme's background along.
shr puts the named face first in the face list, so it wins over the
email's color: every word of an <h5> showed the theme background while
the spaces between them, which don't get the heading face, showed the
panel.  Put the email color first again wherever that happens."
  (let ((pos start))
    (while (< pos end)
      (let* ((next (min end (next-single-property-change pos 'face nil end)))
             (face (get-text-property pos 'face))
             (bg (my/mail-face-background face)))
        (when (and bg (consp face) (not (keywordp (car face)))
                   (seq-some (lambda (f)
                               (and (symbolp f) (facep f)
                                    (face-background f nil t)))
                             face))
          (add-face-text-property pos next (list :background bg)))
        (setq pos next)))))

(defun my/mail-whitespace-runs (bol eol)
  "Return (START . END) for each run of spaces between BOL and EOL."
  (let ((runs nil) (pos bol))
    (while (< pos eol)
      (if (not (eq (char-after pos) ?\s))
          (setq pos (1+ pos))
        (let ((run-end pos))
          (while (and (< run-end eol) (eq (char-after run-end) ?\s))
            (setq run-end (1+ run-end)))
          (push (cons pos run-end) runs)
          (setq pos run-end))))
    (nreverse runs)))

(defun my/mail-set-background (start end bg)
  "Make BG the visible background of START..END, keeping other face attributes."
  (add-face-text-property start end (list :background bg)))

(defun my/mail-paint-line (bol bg width &optional above)
  "Paint the line at BOL as part of a BG panel that is WIDTH columns wide.
A blank line copies the backgrounds of the line at ABOVE, when given,
so margins and cell edges continue straight through it."
  (goto-char bol)
  ;; Trailing blanks past the panel edge would stick out once painted.
  (move-to-column width)
  (when (and (< (point) (line-end-position))
             (string-blank-p (buffer-substring (point) (line-end-position))))
    (delete-region (point) (line-end-position)))
  (end-of-line)
  (when (< (current-column) width)
    (insert (make-string (- width (current-column)) ?\s)))
  (let ((eol (line-end-position)))
    (if (string-blank-p (buffer-substring bol eol))
        (progn
          (my/mail-set-background bol eol bg)
          (when above
            (dotimes (i (- eol bol))
              (when-let* ((color (my/mail-background-at (+ above i))))
                (my/mail-set-background (+ bol i) (+ bol i 1) color)))))
      (dolist (run (my/mail-whitespace-runs bol eol))
        (let* ((start (car run))
               (end (cdr run))
               (left (and (> start bol) (my/mail-background-at (1- start))))
               (right (and (< end eol) (my/mail-background-at end)))
               (own (my/mail-background-at start)))
          (cond
           ;; Padding to the panel edge continues the last cell's color.
           ((= end eol) (my/mail-set-background start end (or left bg)))
           ;; A gap between two stretches of one color is part of them.
           ((and left (equal left right)) (my/mail-set-background start end left))
           ;; Any other uncolored gap gets the panel color.
           ((null own) (my/mail-set-background start end bg)))))
      ;; Visible text with no background of its own sits on the panel.
      (let ((pos bol))
        (while (< pos eol)
          (let ((next (min eol (next-single-property-change pos 'face nil eol))))
            (unless (my/mail-background-at pos)
              (add-face-text-property pos next (list :background bg) t))
            (setq pos next))))
      (my/mail-close-slivers bol eol))))

(defvar my/mail-sliver-max-width 2
  "Widest blank run `my/mail-close-slivers' treats as a nesting artifact.")

(defun my/mail-close-slivers (bol eol)
  "Give thin blank stripes between BOL and EOL the color around them.
Marketing mail nests full-width wrapper tables (often #fff) around
fixed-width colored sections.  A browser puts those sections flush, but
shr indents each nested table by a column or two, which exposes the
wrapper as thin vertical stripes through the section.  A blank run at
most `my/mail-sliver-max-width' columns wide with the same color on both
sides takes that color; wider runs are real gutters and stay."
  (let ((runs nil) (pos bol))
    ;; Split the line into runs of one background color.
    (while (< pos eol)
      (let ((color (my/mail-background-at pos)) (end (1+ pos)))
        (while (and (< end eol) (equal (my/mail-background-at end) color))
          (setq end (1+ end)))
        (push (list pos end color) runs)
        (setq pos end)))
    (setq runs (vconcat (nreverse runs)))
    (dotimes (i (length runs))
      (when (and (> i 0) (< (1+ i) (length runs)))
        (pcase-let ((`(,start ,end ,_) (aref runs i))
                    (`(,_ ,_ ,left) (aref runs (1- i)))
                    (`(,_ ,_ ,right) (aref runs (1+ i))))
          (when (and left (equal left right)
                     (<= (- end start) my/mail-sliver-max-width)
                     (string-blank-p (buffer-substring start end)))
            (my/mail-set-background start end left)
            ;; Later runs compare against this one's new color.
            (setf (nth 2 (aref runs i)) left)))))))

(defun my/mail-paint-gap (bol above below width &optional page)
  "Fill the blank line at BOL between the lines at ABOVE and BELOW.
Each column takes the color the two lines share there.  Where they differ
(a button row under a section, or two sibling sections), the column
continues the last shared color to its left, which is the panel enclosing
both; before the first shared column, it takes the first shared color to
its right.  When the lines share no color at all (two differently colored
rows, e.g. chat bubbles), the line takes PAGE, the email's page color.
Without both neighbors, empty the line so leftover colored spaces don't
show as a stub."
  ;; Read the colors before touching the buffer: inserting into this line
  ;; shifts BELOW.
  (let ((colors
         (and above below
              (let ((above-end (save-excursion (goto-char above)
                                               (line-end-position)))
                    (below-end (save-excursion (goto-char below)
                                               (line-end-position)))
                    (shared nil) (outer nil) (colors nil))
                (dotimes (i width)
                  (let ((up (and (< (+ above i) above-end)
                                 (my/mail-background-at (+ above i))))
                        (down (and (< (+ below i) below-end)
                                   (my/mail-background-at (+ below i)))))
                    (push (and (equal up down) up) shared)))
                (setq shared (nreverse shared))
                (setq outer (or (seq-find #'identity shared) page))
                (dolist (color shared)
                  (when color (setq outer color))
                  (push outer colors))
                (nreverse colors)))))
    (goto-char bol)
    (delete-region bol (line-end-position))
    (when colors
      (insert (make-string width ?\s))
      (seq-do-indexed (lambda (color i)
                        (when color
                          (my/mail-set-background (+ bol i) (+ bol i 1) color)))
                      colors)
      ;; Unpainted trailing columns would just be stray spaces.
      (while (and (> (point) bol) (not (my/mail-background-at (1- (point)))))
        (backward-char 1))
      (delete-region (point) (line-end-position)))))

(defun my/mail-page-color (lines)
  "The most common panel color among LINES: the email's page background."
  (let ((counts nil))
    (seq-doseq (line lines)
      (when-let* ((bg (aref line 1)))
        (setf (alist-get bg counts 0 nil #'equal)
              (1+ (alist-get bg counts 0 nil #'equal)))))
    (car (car (sort counts (lambda (a b) (> (cdr a) (cdr b))))))))

(defun my/mail-paint-panels (start end)
  "Square off the background-colored sections between START and END."
  (my/mail-expand-align-spaces start end)
  (my/mail-pin-backgrounds start end)
  (save-excursion
    (let ((lines nil) (width 0) (gaps nil) (page nil))
      (goto-char start)
      (while (and (< (point) end) (not (eobp)))
        (let* ((bol (point))
               (eol (line-end-position))
               (blank (string-blank-p (buffer-substring bol eol))))
          (unless blank
            (end-of-line)
            (skip-chars-backward " \t" bol)
            (setq width (max width (current-column))))
          (push (vector (copy-marker bol)
                        (unless blank (my/mail-line-background bol eol))
                        blank)
                lines)
          (goto-char eol)
          (forward-line 1)))
      (setq lines (vconcat (nreverse lines)))
      ;; A blank line belongs to a panel when the nearest non-blank lines
      ;; above and below it are both in that panel.
      (dotimes (i (length lines))
        (when (aref (aref lines i) 2)
          (let ((above (seq-find (lambda (l) (not (aref l 2)))
                                 (reverse (seq-subseq lines 0 i))))
                (below (seq-find (lambda (l) (not (aref l 2)))
                                 (seq-subseq lines (1+ i)))))
            (when (and above below (aref above 1)
                       (equal (aref above 1) (aref below 1)))
              (aset (aref lines i) 1 (aref above 1))))))
      (dotimes (i (length lines))
        (let* ((line (aref lines i))
               (bol (marker-position (aref line 0)))
               (prev (and (> i 0) (aref lines (1- i)))))
          (cond ((aref line 1)
                 (my/mail-paint-line
                  bol (aref line 1) width
                  ;; The line above, when it is in the same panel.
                  (and prev (equal (aref prev 1) (aref line 1))
                       (marker-position (aref prev 0)))))
                ((aref line 2) (push i gaps)))))
      ;; A blank line outside any panel is a gap between two differently
      ;; colored panels.  Both usually sit inside an outer wrapper (the
      ;; email's page background), so emptying the gap showed the theme
      ;; background as a dark stripe across the wrapper.  Fill it from the
      ;; painted lines around it instead; this runs after the loop above so
      ;; the line below is already painted.
      (setq page (my/mail-page-color lines))
      (dolist (i gaps)
        (let ((above (seq-find (lambda (l) (not (aref l 2)))
                               (reverse (seq-subseq lines 0 i))))
              (below (seq-find (lambda (l) (not (aref l 2)))
                               (seq-subseq lines (1+ i)))))
          (my/mail-paint-gap (marker-position (aref (aref lines i) 0))
                             (and above (marker-position (aref above 0)))
                             (and below (marker-position (aref below 0)))
                             width page)))
      (my/mail-align-panel-left-edges lines)
      (seq-doseq (line lines)
        (set-marker (aref line 0) nil)))))

(defvar my/mail-ragged-edge-max 3
  "Most columns `my/mail-align-panel-left-edges' extends a panel line by.")

(defun my/mail-panel-start (bol bg)
  "Column of the first BG-colored character on the line at BOL, or nil."
  (save-excursion
    (goto-char bol)
    (let ((eol (line-end-position)))
      (while (and (< (point) eol) (not (equal (my/mail-background-at (point)) bg)))
        (forward-char 1))
      (and (< (point) eol) (- (point) bol)))))

(defun my/mail-align-panel-left-edges (lines)
  "Even out the left edge of each panel in LINES.
shr indents nested tables by a column or two, and not every row of a
section is nested equally deep, so a panel's color can start a few
columns later on some lines (a notch at its top-left corner).  Within a
run of lines in one panel, fill blank columns back to the panel's
leftmost start, up to `my/mail-ragged-edge-max' columns."
  (let ((i 0) (n (length lines)))
    (while (< i n)
      (let ((bg (aref (aref lines i) 1)) (j i))
        (while (and (< j n) bg (equal (aref (aref lines j) 1) bg))
          (setq j (1+ j)))
        (if (= j i)
            (setq i (1+ i))
          (let* ((bols (mapcar (lambda (k) (marker-position (aref (aref lines k) 0)))
                               (number-sequence i (1- j))))
                 (starts (mapcar (lambda (bol) (my/mail-panel-start bol bg)) bols))
                 (edge (apply #'min (or (delq nil (copy-sequence starts)) '(0)))))
            (cl-mapc
             (lambda (bol start)
               (when (and start (< edge start (+ edge my/mail-ragged-edge-max 1))
                          (string-blank-p (buffer-substring (+ bol edge) (+ bol start))))
                 (my/mail-set-background (+ bol edge) (+ bol start) bg)))
             bols starts))
          (setq i j))))))

(defvar my/mail-html-rendering nil
  "Non-nil while `mm-shr' renders a mail part.")

(defvar my/mail-skip-extra-images nil
  "Non-nil while shr re-inserts a table's images in terminal mail.")

(defun my/mail-skip-table-extra-strings (orig &rest args)
  "Around advice for `shr-collect-extra-strings-in-table'.
After each top-level table shr re-inserts the table's images, because GUI
Emacs can't place images inside table cells.  A terminal already shows the
image's alt text inside its cell, so in terminal mail the copy is noise.

Only the images are skipped.  The same pass also renders content that sits
outside any <td> (stray strings, and tables placed directly in a <tr>,
which is how Reddit digests hold every post); skipping the whole pass
dropped all of that."
  (let ((my/mail-skip-extra-images
         (and my/mail-html-rendering (not (display-graphic-p)))))
    (apply orig args)))

(defun my/mail-skip-extra-image (orig tag-name dom &rest args)
  "Around advice for `shr-indirect-call': see `my/mail-skip-table-extra-strings'."
  (cond
   ((and my/mail-skip-extra-images (memq tag-name '(img object))) nil)
   ;; A table rendered from that pass is real content: render it normally,
   ;; images included.
   ((eq tag-name 'table)
    (let ((my/mail-skip-extra-images nil))
      (apply orig tag-name dom args)))
   (t (apply orig tag-name dom args))))

(defun my/mail-text-style-warnings (start end)
  "Drop the emoji selector from shr's suspicious-link warning.
shr inserts \"⚠\" plus U+FE0F after a link whose text names a different
host than its target.  Emacs counts that as one column, but terminals
draw the emoji form two columns wide, so the line sticks out past its
panel.  The plain ⚠ is one column everywhere; its help-echo stays."
  (save-excursion
    (goto-char start)
    (while (search-forward "⚠️" end t)
      (delete-region (1- (point)) (point)))))

(defun my/mu4e-make-room-for-url-numbers ()
  "After `mu4e--view-activate-urls', keep panel lines at their width.
mu4e shows a link number such as [1] after each URL in the visible text,
as an overlay string added after shr laid out the mail.  Take that many
trailing padding spaces off the line so its panel keeps one right edge.
Also drop the zero-width space mu4e puts in front of the number: a
terminal draws it as a full column."
  (let ((inhibit-read-only t))
    (save-excursion
      (dolist (ov (overlays-in (point-min) (point-max)))
        (when-let* (((overlay-get ov 'mu4e-overlay))
                    (after (overlay-get ov 'after-string)))
          (setq after (string-replace "​" "" after))
          (overlay-put ov 'after-string after)
          (goto-char (overlay-end ov))
          (let* ((eol (line-end-position))
                 (padding (save-excursion
                            (goto-char eol)
                            (skip-chars-backward " " (overlay-end ov))
                            (point)))
                 (room (min (string-width after) (- eol padding))))
            (delete-region (- eol room) eol)))))))

(advice-add 'mu4e--view-activate-urls :after
            #'my/mu4e-make-room-for-url-numbers)

(defun my/mm-shr-clean-layout (orig &rest args)
  "Around advice for `mm-shr': readable width and solid color panels."
  (let* ((window (or (get-buffer-window (current-buffer)) (selected-window)))
         (fill-column (max 40 (min my/mail-html-max-width
                                   (- (window-width window) 2))))
         (shr-use-fonts nil)
         (shr-discard-aria-hidden t)
         (shr-bullet "• ")
         (shr-hr-line ?─)
         (my/mail-html-rendering t)
         (start (point-marker))
         (end (copy-marker (point) t)))
    (prog1 (apply orig args)
      (my/mail-text-style-warnings start end)
      (my/mail-paint-panels start end)
      (set-marker start nil)
      (set-marker end nil))))

;; Keep the palette backgrounds dark.  When text and background are too
;; close, `shr-color-visible' moves both their lightness apart unless told
;; the background is fixed.  Dark email text (#333) on a palette panel
;; (#313244) needs the 60-point lightness gap set above, so shr lifted the
;; panel to a light gray and kept the text dark, and the theme's light-blue
;; `shr-link' color, which shr never checks, ended up unreadable on it.  In
;; mail, keep the background and adjust only the text.
(defun my/mail-keep-background-contrast (orig bg fg &optional fixed-background)
  "Around advice for `shr-color-visible': in mail, only adjust the text color."
  (funcall orig bg fg (or fixed-background my/mu4e-rendering)))

;; Remove the earlier layout-table flattening if this block is re-evaluated
;; in a running Emacs that still has it.
(when (fboundp 'my/shr-flatten-layout-table)
  (advice-remove 'shr-tag-table #'my/shr-flatten-layout-table))
(advice-add 'shr-color-visible :around #'my/mail-keep-background-contrast)
(advice-add 'shr-collect-extra-strings-in-table :around
            #'my/mail-skip-table-extra-strings)
(advice-add 'shr-indirect-call :around #'my/mail-skip-extra-image)
(advice-add 'mm-shr :around #'my/mm-shr-clean-layout)

;; Color the Gnus/mu4e MIME and multipart/alternative chooser buttons. Keep
;; this face-only: no mouse-map changes and no background color, to avoid
;; terminal click artifacts.
(defface my/mu4e-mime-button-face
  '((t :foreground "cyan" :weight bold :underline t))
  "Face for mu4e/Gnus MIME and attachment buttons.")
(setq gnus-article-button-face 'my/mu4e-mime-button-face)

;; The real standard mml/message-mode bindings for whole-message PGP/MIME are
;; C-c C-m c p (encrypt) and C-c C-m s p (sign) - NOT "C-c C-m e p"/"e s" as
;; an earlier version of this comment claimed; "e" under that prefix is
;; mml-attach-external, unrelated. Also: C-m itself is a fragile key to rely
;; on at all in a terminal session (emacs -nw over ssh) - it's historically
;; the same byte as plain RET, and a terminal using a modern keyboard
;; protocol to disambiguate them (Ghostty/cmux does) can leak raw escape
;; bytes into the buffer as literal text if Emacs doesn't fully consume the
;; sequence, instead of the chord registering at all. M-x sidesteps this
;; entirely (no raw terminal key parsing involved), hence these two
;; convenience wrappers - prefer M-x my/mu4e-toggle-encryption / -signing
;; over the raw C-c C-m keychords in a terminal session.
(defun my/mu4e-toggle-encryption ()
  "Toggle PGP/MIME encryption for the current message."
  (interactive)
  (mml-secure-message-encrypt-pgpmime))

(defun my/mu4e-toggle-signing ()
  "Toggle PGP/MIME signing for the current message."
  (interactive)
  (mml-secure-message-sign-pgpmime))

;; g (mu4e-view-go-to-url) relies on mu4e's own regex-based buffer scan
;; (mu4e--view-linkify-buffer-text, in mu4e-view.el), which only catches URLs
;; that appear as literal visible text. shr (Emacs's HTML renderer, which
;; mu4e uses for HTML mail) has a TTY-specific rendering path: on a graphic
;; frame links render one way, but in a terminal (emacs -nw, e.g. any ssh
;; session) it instead embeds the URL as a hidden/invisible bracketed
;; annotation right after the link text - real buffer text, but mu4e's
;; regex scanner still misses it in practice on these emails, so g reports
;; "No links for this message" even though the link is right there and
;; genuinely clickable via TAB + RET (which goes through shr's own keymap,
;; not mu4e's scanner, and always worked). Confirmed 2026-08-18: same email,
;; g works fine in GUI Emacs, fails every time over ssh/emacs -nw.
;;
;; Fix: read shr's own 'shr-url text property directly instead of relying on
;; mu4e's regex - the exact same property/traversal shr itself uses
;; internally (see shr.el's own use of next-single-property-change on
;; 'shr-url), so this works regardless of how shr chose to render the link.
(defun my/mu4e-view-collect-shr-urls ()
  "Collect distinct URLs from `shr-url' text properties in the
current buffer, in document order."
  (let (urls (pos (point-min)))
    (while (< pos (point-max))
      (let ((url (get-text-property pos 'shr-url)))
        (when (and url (not (member url urls)))
          (push url urls)))
      (setq pos (or (next-single-property-change pos 'shr-url) (point-max))))
    (nreverse urls)))

(defun my/mu4e-view-go-to-url (&optional _multi)
  "Like `mu4e-view-go-to-url', but finds links via shr's own
'shr-url text properties instead of mu4e's regex-based buffer scan -
see the comment above for why that scan misses some real,
shr-rendered links in a terminal session."
  (interactive "P")
  (let ((urls (my/mu4e-view-collect-shr-urls)))
    (cond
     ((null urls) (mu4e-error "No links for this message"))
     ((= (length urls) 1)
      (let ((url (car urls)))
        (if (string-prefix-p "mailto:" url)
            (browse-url-mail url)
          (browse-url url))))
     (t (let ((choice (completing-read "URL to visit: " urls nil t)))
          (if (string-prefix-p "mailto:" choice)
              (browse-url-mail choice)
            (browse-url choice)))))))

(defun my/mu4e-headers-mouse-1-view-message (event)
  "Open the mu4e header clicked by mouse EVENT."
  (interactive "e")
  (let ((pos (posn-point (event-end event)))
        (window (posn-window (event-end event))))
    (when (and (windowp window) (integer-or-marker-p pos))
      (select-window window)
      (goto-char pos)
      (mu4e-headers-view-message))))

(with-eval-after-load 'mu4e
  (define-key mu4e-view-mode-map (kbd "g") #'my/mu4e-view-go-to-url)
  ;; Mouse convenience: left-click a message in the headers list to open it.
  ;; Do not bind mouse-4/mouse-5; terminal Emacs often reports scroll wheel
  ;; events as those buttons.
  (define-key mu4e-headers-mode-map [mouse-1] #'my/mu4e-headers-mouse-1-view-message)
  ;; Also bind at mu4e-view level.  shr links have their own keymap below, but
  ;; this gives us a fallback if terminal mouse events bypass the shr map.
  (define-key mu4e-view-mode-map [mouse-1] #'my/shr-browse-url-mouse)
  (define-key mu4e-view-mode-map [C-mouse-1] #'my/shr-browse-url-mouse))

(defun my/shr-url-at-or-near (pos)
  "Return the `shr-url' at POS or a few chars around it."
  (when (integer-or-marker-p pos)
    (catch 'url
      (dolist (p (number-sequence (max (point-min) (- pos 3))
                                  (min (point-max) (+ pos 3))))
        (let ((url (or (get-text-property p 'shr-url)
                       (get-text-property (max (point-min) (1- p)) 'shr-url))))
          (when url
            (throw 'url url)))))))

(defun my/shr-browse-url-mouse (event)
  "Open the shr URL clicked by mouse EVENT via `browse-url'.
This is for terminal Emacs/mu4e: HTML links like \"View Message\" are not
literal URLs, so the terminal cannot open them; Emacs must read the hidden
`shr-url' property and pass it to our `browse-url' ssh-back opener."
  (interactive "e")
  (let* ((pos (posn-point (event-end event)))
         (window (posn-window (event-end event)))
         url)
    ;; Important: mouse events may arrive while another window/buffer is still
    ;; current.  Text properties are buffer-local, so select/use the clicked
    ;; window's buffer before reading `shr-url'.  Batch tests had the right
    ;; buffer current already; real mouse clicks in mu4e often do not.
    (when (windowp window)
      (select-window window))
    (setq url (my/shr-url-at-or-near pos))
    (if url
        (browse-url url)
      (message "No shr-url at click position"))))

(with-eval-after-load 'shr
  ;; The proper place to make HTML mail links mouse-clickable is `shr-map',
  ;; not `mu4e-view-mode-map': shr puts this local keymap on rendered link
  ;; text.  Bind mouse-1 only; binding down-mouse-1 as well double-opens.
  (define-key shr-map [mouse-1] #'my/shr-browse-url-mouse)
  (define-key shr-map [C-mouse-1] #'my/shr-browse-url-mouse))

;; browse-url over ssh: this Emacs instance may run -nw on ubuntu while the
;; browser we actually want is on the SSH client.  If that client is Windows,
;; ask it to run PowerShell Start-Process; otherwise ask it to run a small
;; bash snippet using xdg-open/open.  If that SSH-back path is unavailable,
;; fall back to OSC 52 so the URL at least lands in the local clipboard.
(defvar my/ssh-client-user "joel_"
  "Account to ssh back to when opening URLs from remote Emacs.")

(defun my/osc52-copy-to-local-clipboard (text)
  "Copy TEXT into the local machine's system clipboard via OSC 52,
even when Emacs is running remotely under `emacs -nw' over ssh."
  (let ((b64 (base64-encode-string (encode-coding-string text 'utf-8 t) t)))
    (send-string-to-terminal (format "\e]52;c;%s\a" b64))))

(defun my/ssh-client-target ()
  "Return user@host for the machine that initiated this SSH session."
  (when-let* ((ssh-client (getenv "SSH_CLIENT"))
              (client-host (car (split-string ssh-client))))
    (format "%s@%s" my/ssh-client-user client-host)))

(defconst my/ssh-back-options
  '("-o" "BatchMode=yes"
    "-o" "ConnectTimeout=3"
    "-o" "StrictHostKeyChecking=accept-new"))

(defun my/ssh-client-windows-p (ssh target)
  "Return non-nil if TARGET looks like a Windows OpenSSH server."
  (zerop (apply #'call-process ssh nil nil nil
                (append my/ssh-back-options
                        (list target "cmd.exe" "/c" "ver")))))

(defun my/open-url-via-forwarder (url)
  "Open URL through the launcher-provided local HTTP forwarder."
  (when-let* ((endpoint (getenv "MU4E_OPEN_URL_ENDPOINT"))
              (curl (executable-find "curl")))
    (zerop
     (call-process curl nil nil nil
                   "--max-time" "2"
                   "--silent" "--show-error" "--fail"
                   "--request" "POST"
                   "--data-urlencode" (concat "url=" url)
                   endpoint))))

(defun my/open-url-on-ssh-client (url)
  "Open URL in the browser on the machine that initiated this SSH session.
Return non-nil if the request was successfully handed off."
  (or (my/open-url-via-forwarder url)
      (when-let* ((target (my/ssh-client-target))
                  (ssh (executable-find "ssh")))
        (if (my/ssh-client-windows-p ssh target)
            ;; Fallback for Windows clients when the fast forwarded opener is
            ;; unavailable.  Encode the whole PowerShell command as UTF-16LE
            ;; base64 so long tracking URLs survive command-line parsing.
            (let* ((quoted-url (replace-regexp-in-string "'" "''" url t t))
                   (ps-command (format "Start-Process -FilePath '%s'" quoted-url))
                   (encoded-command
                    (base64-encode-string
                     (encode-coding-string ps-command 'utf-16le t) t)))
              (zerop
               (apply #'call-process ssh nil nil nil
                      (append my/ssh-back-options
                              (list target
                                    "powershell.exe" "-NoProfile" "-NonInteractive"
                                    "-EncodedCommand" encoded-command)))))
          (zerop
           (apply #'call-process ssh nil nil nil
                  (append my/ssh-back-options
                          (list target
                                "bash" "-lc"
                                "url=$1; if command -v xdg-open >/dev/null 2>&1; then nohup xdg-open \"$url\" >/dev/null 2>&1 & elif command -v open >/dev/null 2>&1; then nohup open \"$url\" >/dev/null 2>&1 & else exit 127; fi"
                                "bash" url))))))))

(defun my/browse-url-local-aware (url &rest args)
  "`browse-url-browser-function' that opens URLs on the local SSH client.
Use the normal browser for graphical/local Emacs; over SSH, open on the
client via ssh, with OSC 52 clipboard fallback."
  (if (or (display-graphic-p) (not (getenv "SSH_CLIENT")))
      (apply #'browse-url-default-browser url args)
    (unless (my/open-url-on-ssh-client url)
      (my/osc52-copy-to-local-clipboard url)
      (message "Could not open browser on SSH client; copied link to local clipboard: %s" url))))

(setq browse-url-browser-function #'my/browse-url-local-aware)

(provide 'init-mu4e)

;;; init.el ends here
(provide 'init)
