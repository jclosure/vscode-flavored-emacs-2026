# cpp-demo — a sandbox for testing the C++ setup

A tiny CMake project (a `main` plus a small `demo::` math library) for
exercising every part of the Emacs C++ workflow.

```
cpp-demo/
├── CMakeLists.txt        # C++20, exports compile_commands.json, -Wall -Wextra
├── .clang-format         # LLVM style, 4-space indent
├── include/mathutils.hpp # declarations
└── src/
    ├── main.cpp          # drives the library
    └── mathutils.cpp     # definitions
```

## Try it, step by step

Open `src/main.cpp` in Emacs, then:

1. **Build it.** `C-c c g` to configure into `build/`, then `C-c c b` to build.
   These find the project root by walking **up** to the nearest `CMakeLists.txt`,
   so they work even though `main.cpp` lives in `src/` (the CMakeLists.txt is one
   level up). `C-c c g` prints the detected "CMake root" in the minibuffer.
   (Or one-shot from a shell: `cmake -S . -B build && cmake --build build`.)
2. **Point clangd at the build.** `C-c c j` writes a `.clangd` file, then
   `C-c l l` reconnects. Now diagnostics/headers are exact.
3. **Completion.** Inside `main`, type `demo::` and watch the candidates pop up.
4. **Navigation.** Cursor on `factorial` → `M-.` jumps to the header, `M-,`
   jumps back. `C-c l s` searches all symbols.
5. **Hover / docs.** `C-c l d` shows the signature of the symbol at point.
6. **Rename.** Cursor on `total` in `main.cpp` → `C-c l r` renames every use.
7. **Format on save.** Mangle the indentation, then `C-x C-s` — clang-format
   tidies it up automatically (using `.clang-format`).
8. **See a diagnostic.** Delete a semicolon or call `demo::factorial()` with no
   argument; clangd underlines it and `C-c !` lists the error.
9. **Debug.** Put the cursor on the `const long total = ...` line in `main.cpp`,
   `C-c d b` to set a breakpoint, then `C-c d d` and pick **`lldb-cmake`**
   (macOS) or **`gdb-cmake`** (Linux). It rebuilds and launches `build/demo`
   automatically (no need to type a path). Then `C-c d n` to step, `C-c d s` to
   step into `demo::sum`, and `C-c d i` to inspect locals. `factorial` is
   recursive, so it gives you a nice deep call stack to walk.
10. **Disassemble.** Cursor inside `fibonacci`, `C-c x d` shows the asm.

Expected program output:

```
== Emacs C++ demo ==
sum   = 35
max   = 9
1! = 1   fib(1) = 1
...
primes <= 20: 2 3 5 7 11 13 17 19
```
