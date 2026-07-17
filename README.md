# Emacs config

A fast, modern, VSCode-flavored Emacs setup. Built around `use-package`,
tree-sitter, `eglot` (LSP), `vertico`/`corfu` completion, and Catppuccin.
Works equally well in the GUI and the terminal (`emacs -nw`).

## First launch

The very first start downloads ~30 packages from ELPA/MELPA, so it takes a
minute. **Let it finish.** Every launch afterward is fast (typically well
under a second; the echo area prints the exact startup time).

If anything looks off on the first run, just restart Emacs once — packages
are compiled lazily and a second start settles everything.

## What makes it fast

- GC is paused during startup and managed adaptively by `gcmh` afterward.
- The file-name handler list is nulled during startup and restored after.
- UI chrome (menu/tool/scroll bars) is killed *before* the first frame, with
  the background pre-painted to avoid a white flash.
- Packages load lazily — on a keypress, a command, or a file type — so almost
  nothing runs at startup.

## Standard-editor (VSCode-style) keys

| Key | Action |
|-----|--------|
| `M-Backspace` / `C-Backspace` | Delete word left — **does not copy to clipboard** |
| `M-d` / `C-Delete` | Delete word right (also no copy) |
| `C-c` / `C-x` / `C-v` | Copy / cut / paste when a region is selected (CUA) |
| `C-/` / `C-M-/` | Undo / redo (linear, like VSCode). Not `C-z` — that backgrounds Emacs in a terminal |
| `C-a` / `Home` | Smart Home: first non-whitespace, then column 0 |
| `M-↑` / `M-↓` | Move line/region up / down |
| `M-S-↑` / `M-S-↓` | Duplicate line up / down |
| `M-;` | Toggle comment on the line/region |
| `C-=` / `C-+` | Expand / shrink selection by semantic unit |
| Type with a region active | Replaces the selection |

Word motion (`M-f` / `M-b` and `M-Backspace`) already matches macOS VSCode's
Option-arrow/Option-Delete stops, so no remap was needed there.

## Multiple cursors (VSCode-style)

| Key | Action |
|-----|--------|
| `C-d` | Select word, then add the next occurrence (VSCode `Cmd-D`) |
| `C-c C-d` | Add a cursor at **all** occurrences |
| `C->` / `C-<` | Add cursor at next / previous occurrence |
| `C-S-↑` / `C-S-↓` | Add a cursor on the line above / below |
| `C-S-click` | Add/remove a cursor at the click |
| `C-c C-SPC` | One cursor per line of the selection |

## Finding things

| Key | Action |
|-----|--------|
| `C-s` | Search lines in this buffer (`consult-line`) |
| `C-x b` | Switch buffer (with preview) |
| `C-c f` | Search the whole project (`ripgrep` — install `rg`) |
| `C-c r` | Recent files |
| `M-y` | Browse the kill ring |
| `M-g g` / `M-g i` | Go to line / jump to symbol or heading |
| `C-;` | Jump to any visible character (avy) |
| `C-.` | Context actions on the thing at point (embark) |

## IDE features (LSP via eglot)

eglot starts **automatically** when you open a file *and* its language server
is installed. Nothing pops up for languages whose server you don't have.

| Key (in code buffers) | Action |
|-----|--------|
| `C-c l l` | Start/connect eglot manually |
| `C-c l r` | Rename symbol |
| `C-c l a` | Code actions / quick-fixes |
| `C-c l f` | Format buffer |
| `C-c l d` | Show documentation |
| `C-c l s` | Search workspace symbols |
| `M-n` / `M-p` | Next / previous diagnostic |
| `C-c !` | List all diagnostics |

**Symbol navigation (xref):**

| Key | Action |
|-----|--------|
| `M-.` | Jump to definition (`<F12>` also works, VSCode-style) |
| `M-?` | Find references — list every place a symbol is used |
| `M-,` | **Go back** — return to exactly where you invoked `M-.` / `M-?` from |
| `C-M-,` | Go forward (undoes a `M-,` if you backed up too far) |

These are stock Emacs bindings, not remapped by this config. With eglot
attached, `M-.`/`M-?` use the language server's real symbol data instead of
a text search, so "definition" and "references" are accurate even across
files. Each jump pushes a marker, so you can chase a call three definitions
deep and then tap `M-,` three times to retrace your steps back out.

**Looking up documentation for a symbol:**

| Key | Action |
|-----|--------|
| *(resting on a symbol)* | eldoc shows its signature/type in the echo area automatically — no key needed |
| `C-c l h` | Force that signature into the echo area right now |
| `C-c l d` | Same info in a scrollable buffer (`eldoc-doc-buffer`) — better for long docs |
| `C-c C-d` | `helpful-at-point` — full docs for whatever's under the cursor: docstring, source, references |
| `C-h f` / `C-h v` | `helpful-callable` / `helpful-variable` — describe any function/variable by name |

**Closing a help/doc window when you're done:** don't switch to it and hit
`q` — from wherever you are, `C-c <left>` (`winner-undo`) restores the
window layout to before it popped up. This is generic, not doc-specific: it
undoes the last window-layout change, so it also works for compile output,
grep results, magit status, etc.

Install the server binaries you want (examples):

```
pip install pyright                              # Python
npm i -g typescript typescript-language-server   # JS / TS / JSX / TSX
rustup component add rust-analyzer               # Rust
go install golang.org/x/tools/gopls@latest       # Go
# clangd (C/C++), jdtls (Java), bash-language-server, yaml-language-server, etc.
```

Tree-sitter grammars are fetched on demand the first time you open a file in
a language (Emacs will ask). Say yes once per language.

## C / C++ development

clangd gives you completion, diagnostics, rename, go-to-def, and hover; the
keys below add building, debugging, and clang-format-on-save.

### C/C++ prerequisites

Emacs only drives these tools — you need the binaries installed. **Check what
Emacs can currently find with `C-c c ?`** (`M-x my/cpp-doctor`); it lists every
tool as ✓ found or ✗ missing.

**macOS install:**

```sh
xcode-select --install          # clang, lldb, make (if you don't have them)
brew install llvm cmake ripgrep # clangd, clang-format, clang-tidy, lldb-dap, cmake, rg
```

`lldb-dap` (the debugger adapter) is the one people trip on. It is **not** part
of Apple's Command Line Tools — it comes with Homebrew's `llvm`. Homebrew keeps
`llvm` "keg-only," so the binary lives at:

```
/opt/homebrew/opt/llvm/bin/lldb-dap   # Apple Silicon
/usr/local/opt/llvm/bin/lldb-dap      # Intel
```

…which is **not on your PATH by default**. This config already adds those
directories (and imports your shell PATH via `exec-path-from-shell`), so after
`brew install llvm` just **restart Emacs** and run `C-c c ?` to confirm
`lldb-dap` shows ✓. If you started Emacs from the Dock/Finder, restarting is
what lets it see the newly installed tools.

**Linux install:**

```sh
sudo apt install clangd clang-format clang-tidy cmake gdb ripgrep
# lldb users: sudo apt install lldb   (provides lldb-dap on recent LLVM)
```

Then `C-c d d` → pick the `lldb-dap` (macOS) or `gdb` (Linux) configuration.

clangd is tuned with `--background-index --clang-tidy --header-insertion=iwyu`
and PCH in memory. clang-format runs on save (apheleia) and honors a
`.clang-format` file in your project.

The build/debug commands find the project root by searching **upward** for the
nearest `CMakeLists.txt`, so they work from any file in the tree — e.g. with
`src/main.cpp` open, `C-c c g` still configures at the project top, not in
`src/`. (`C-c c g` echoes the detected "CMake root" in the minibuffer.) No
`.git` or project marker is required.

**Typical workflow for a CMake project:**

1. `C-c c g` — configure into `./build` at the CMake root (exports
   `compile_commands.json`, `CMAKE_BUILD_TYPE=Debug`).
2. `C-c c j` — write a `.clangd` file pointing at `build/` so clangd gets
   exact compile flags (run once per project; then `C-c l l` to reconnect).
3. `C-c c b` — **build only**, no debugger: `cmake --build build -j` in a
   plain compile buffer. `C-c c r` rebuilds (repeats last command), `C-c c k`
   kills it. Use this when you just want to check for compile errors — see
   below for `C-c d d`, which builds *and* launches the debugger.

For plain Makefiles just use `C-c c c` and type `make` (it remembers it for
`C-c c r`). The compile buffer is colorized and auto-scrolls to the first error
(`M-n` / `M-p` jump between them).

**Debugging** (DAP via `dape`, works with lldb or gdb). `C-c d d` **builds
and launches the debugger** — if you just want to build, use `C-c c b`
instead (see above). Once a session starts, `C-c d <key>` is really just a
launcher — after any one of them runs, Emacs's `repeat-mode` lets you press
the **bare letter** again with no prefix, so most of a session is just
tapping single keys.

**Most used** — these are also the ones shown live in the mode line while a
repeat streak is active:

| Key (`C-c d …`, or bare once repeating) | Action |
|-----|--------|
| `n` | Step over |
| `s` | Step into |
| `o` | Step out |
| `c` | Continue |
| `b` | Toggle breakpoint |
| `C` | Conditional breakpoint at point (prompts `Condition:`) |
| `e` | Evaluate expression at point / minibuffer |

**Everything else** (still repeatable, just left off the mode-line hint to
keep it short):

| Key | Action |
|-----|--------|
| `C-c d d` | Start — pick an lldb or gdb configuration |
| `C-c d B` | Remove all breakpoints |
| `C-c d r` / `C-c d p` / `C-c d q` | Restart / pause / quit |
| `C-c d i` / `C-c d R` | Info windows (locals, stack) / debug REPL |

A repeat streak ends the moment you press a key that isn't in the map (the
mode-line hint disappears then too — nothing is shown outside a streak).
Full key list for any repeat map, dape's or otherwise: `M-x describe-repeat-maps`.

At the `C-c d d` prompt pick one of the ready-made configs:

- **`lldb-cmake`** (macOS) — uses `lldb-dap` from LLVM.
- **`gdb-cmake`** (Linux) — uses `gdb --interpreter=dap` (gdb ≥ 14).

Both **build the project first** (`cmake --build build`), then debug the
executable found under `build/` automatically — no more LLDB's bogus `a.out`
default. If `build/` has more than one executable, you'll be asked which to
debug; if it has none, you'll be prompted for a path (build first with
`C-c c b`). The plain built-in `dape` configs still exist if you want to point
at an adapter/program manually.

**Conditional breakpoint example** — say you're chasing a bug that only shows
up on the 100th iteration of a loop:

```c
for (int i = 0; i < 1000; i++) {
    process(i);       // <- put point on this line
}
```

1. Put point on the `process(i)` line and press `C-c d C`.
2. At the `Condition:` prompt, type `i == 100` and hit Enter.
3. `C-c d c` (continue) — execution now runs freely and only stops when
   `i` reaches 100, instead of you stepping through 99 boring iterations
   or babysitting a plain breakpoint.
4. To clear it, put point back on the line, press `C-c d C` again, and
   submit an empty string.

Works with any boolean expression the debuggee's language understands —
`ptr == NULL`, `count > threshold`, `strcmp(name, "bob") == 0`, etc. Combine
with `C-c d w` (watch an expression) to see it update live in the Watch panel
as you continue/step.

**Extras:** `C-c x d` disassembles the function at point (needs `objdump`).
`C-c l f` formats on demand, `C-c l a` runs clang-tidy/clangd quick-fixes,
`C-c l r` renames across the project.

## Markdown

Full GitHub-flavored Markdown with **native syntax highlighting inside fenced
code blocks** — each ` ``` ` block is highlighted by that language's real major
mode. Common tag spellings are aliased (`sh`, `py`, `js`, `c++`, `yml`, …) so
highlighting works regardless of how you label the fence. `M-x markdown-live-preview-mode`
needs `pandoc` if you want HTML preview.

## Completion / IntelliSense

In-buffer completion is Corfu, tuned to feel like VSCode:

- **Auto-popup fires only in code.** Programming and config buffers get
  suggestions automatically (after 2 characters, a 0.15s pause). In Markdown,
  Org, plain text, and other non-code buffers it never pops up on its own —
  press `TAB` (or `M-TAB`) to complete on demand. This is what stopped the
  chattiness in prose.
- **Top item is preselected**, and both `Enter` and `Tab` accept it.
- **Kind icons** appear on the left in the GUI (run `M-x nerd-icons-install-fonts`
  once). The icon gutter is why candidates now line up cleanly under the cursor
  instead of looking offset. In a terminal, icons are omitted (install a Nerd
  Font in your terminal if you want them there too).
- A small **documentation panel** slides out beside the popup after a short
  delay.

Tweakables in `init.el` (the `corfu` block): `corfu-auto-delay`,
`corfu-auto-prefix`, and `corfu-popupinfo-delay`. To also auto-complete in a
prose mode, you can add `(setq-local corfu-auto t)` to that mode's hook.

## Terminal use

Designed for `emacs -nw`: mouse click/scroll/select is on, the Corfu
completion popup renders in text mode, and `clipetty` syncs every kill to your
system clipboard over SSH/tmux via OSC-52. Use a true-color terminal for the
best Catppuccin rendering.

## Theme

Catppuccin **Mocha** by default. `M-x my/toggle-light-dark` flips to the
built-in **Modus Operandi** light theme. Change the flavor by setting
`catppuccin-flavor` (`mocha`, `macchiato`, `frappe`, `latte`) in `init.el`.

For GUI icons run once: `M-x nerd-icons-install-fonts`.

## Files

- `early-init.el` — pre-frame startup tuning.
- `init.el` — everything else, organized into commented sections.
- `cpp-demo/` — a small CMake project for exercising the C/C++ workflow.
- `var/`, `etc/` — auto-managed by `no-littering` (backups, history, custom).

## License

Released under the [MIT License](LICENSE).
