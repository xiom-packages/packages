# AUDIT: xiom.glfw

## Status (2026-10-08)

Dynamic-loader implementation at 0.2.0. The pre-pilot bridge path
(`bridge/glfw_bridge.c` linked against GLFW headers/import libs, module
mis-declared as `xiom.glwf`) was removed: it could not satisfy the
SKIP-when-absent gate. It is preserved in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.0 |
| Upstream pin | GLFW 3.4 (tag `3.4`), soname `glfw3.dll` |
| Link model | none at build time; runtime resolution via `xiom.ffi.dl` |
| FFI confinement | all `unsafe`/fn-pointer casts in `glfw.xi` (single module, G5) |
| Suite | `tests/test_conformance.xi` |
| Runs | absent: PASS 3/3 x2; present (GLFW 3.4.0): PASS 9/9 x2 -- both via `scripts/port.ps1` |

## G2 pin

- Soname: `glfw3.dll`; header `GLFW/glfw3.h` SHA256 `AA370985...B73C`
  (tag 3.4); resolved symbol set of six functions. Full table + re-pin
  procedure: `SPEC.md` §2.
- Local positive-path sample (not the pin): official
  `glfw-3.4.bin.WIN64.zip` (`lib-vc2022\glfw3.dll`, SHA256 `4429ADFF...C14BB1`,
  FileVersion 3.4.0); runtime build string `3.4.0 Win32 WGL Null EGL OSMesa
  VisualC DLL`.

## Design notes

- Classification distinguishes absent (SKIP), init/platform failure (SKIP
  with GLFW error text), and export mismatch (FAIL); nothing is silently
  skipped on a broken install.
- Version reads and error capture use XIOM-owned out-param slots
  (`glfwGetVersion` int*, `glfwGetError` const char**) -- no malloc/free in
  confined blocks (finding B-05).
- No `port.args.json`: the loader compiles no C source and needs no extra
  flags.

## Known limitations

- Windows soname only (`glfw3.dll`); `libglfw.so.3` is a Phase 2 item.
- Smoke scope: window/input/monitor resources are Phase 2.
- The headless-present path (glfwInit fails) is code-reviewed but was not
  reproducible on this host (desktop session available).
