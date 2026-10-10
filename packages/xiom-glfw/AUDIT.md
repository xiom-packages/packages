# AUDIT: xiom.glfw

## Status (2026-10-10)

Dynamic-loader implementation at 0.3.0 (engine surface). No upstream code is
vendored; the runtime contract is the `glfw3.dll` soname plus a resolved
export set (85 fail-closed + 5 best-effort Vulkan helpers).

| Item | State |
|------|-------|
| Compiler | xiom v0.64.2 |
| Upstream pin | GLFW 3.4 (header SHA256 `AA370985...`); zlib license |
| Link model | none (runtime `LoadLibrary` through `xiom.ffi.dl`) |
| FFI confinement | all `unsafe`/`extern` in `glfw.xi` (G5) |
| Slots | XIOM-owned `Vec[UInt8]` + byte-wise reads (B-11 discipline); `ffi.memcpy` for foreign arrays; pure-arithmetic f32/f64 bit decode |
| Suite | `tests/test_conformance.xi`, 28 checks positive / SKIP-labels when absent |
| Runs | **28/28 x2** on 2026-10-10 (official 3.4 win64 DLL; ~12 s/run) |

## Design notes

- **Fail-closed loader**: 85 core exports resolved into an 86-field
  `GlfwLibrary` (one `dl_sym` per name list entry; any miss closes the
  handle and returns `GLFW_LOAD_ABI`). The 5 Vulkan helper exports are
  best-effort (0 = absent; typed errors from the wrappers).
- **Avoided codegen landmines (v0.64.2, each with lane evidence):**
  - fp returns through cast calls (0/garbage) -> time/opacity value checks
    are labelled SKIPs; repro bundle filed.
  - Vec-of-struct element extraction (AV) -> `Vec[Int]` monitor handles +
    raw vidmode buffers.
  - `Result[Vec[...]]` payload extraction (AV) -> `GlfwExtNames` struct.
  - `Result[Float32/Float64]` payload extraction (ret-float IR mismatch)
    -> pure bit-decode readers.
- **Windowed checks are headless-safe**: hidden (`GLFW_VISIBLE=GLFW_FALSE`)
  `GLFW_NO_API` window; nothing is shown on screen; the suite leaves GLFW
  terminated and the library handle closed.
- **Win32 + Vulkan helpers** give the engine the HWND path and surface
  creation without any Vulkan headers at build time (raw `Int` handles).

## Known limitations

- Floating-point-return functions unverifiable on v0.64.2 (see above).
- Event callbacks (key/char/mouse/scroll/drop/window) not bound yet
  (0.4.0; C callback ABI unproven).
- joystick/gamepad, cursors, gamma ramps, window icons: 0.4.0.
- Windows x64 primary; POSIX soname documented only.
