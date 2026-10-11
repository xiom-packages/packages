# AUDIT: xiom.glfw

## Status (2026-10-11)

Dynamic-loader implementation at **0.5.0 (full surface, 124/124 core
exports)**. No upstream code is vendored; the runtime contract is the
`glfw3.dll` soname plus a resolved export set (124 fail-closed + 5
best-effort Vulkan helpers).

| Item | State |
|------|-------|
| Compiler | xiom v0.64.3 |
| Upstream pin | GLFW 3.4 (header SHA256 `AA370985...`); zlib license |
| Link model | none (runtime `LoadLibrary` through `xiom.ffi.dl`); suite links `user32` for WM round trips |
| FFI confinement | all `unsafe`/`extern` in `glfw.xi` (G5) |
| Slots | XIOM-owned `Vec[UInt8]` + byte-wise reads (B-11 discipline); `ffi.memcpy` for foreign arrays; pure-arithmetic f32/f64 bit decode; allocator struct written into a 32-byte slot |
| Suite | `tests/test_conformance.xi`, 37 checks positive / SKIP-labels when absent |
| Runs | **37/37 x2** positive + **3/3** absent-SKIP on 2026-10-11 (official 3.4 win64 DLL; ~15 s/run) |

## Design notes

- **Fail-closed loader**: 124 core exports resolved into a 127-field
  `GlfwLibrary` (one `dl_sym` per name list entry; any miss closes the
  handle and returns `GLFW_LOAD_ABI`). The 5 Vulkan helper exports are
  best-effort (0 = absent; typed errors from the wrappers).
- **Callback ABI (0.5.0)**: fixed top-level dispatcher per event type (the
  only address handed to the DLL) + a module-level `Vec[fn]` registry of
  user handlers. Verified end-to-end: error callback (synchronous GLFW
  error), key callback (posted `WM_KEYDOWN` + poll), close callback (posted
  `WM_CLOSE` + poll). ABI probe: `docs/repro/bindings-pilot/cb-abi/`.
  Finding **B-13**: fn-typed PARAM values marshal to `0` at the C boundary
  (cast, re-pass, copy-to-local, struct field -- all 0); bare top-level fn
  names and locals are correct. The registry design avoids params entirely.
- **glfwInitAllocator** takes raw callback addresses (`alloc as Int`);
  verified with a bump-arena allocator (alloc/realloc/dealloc callbacks
  fired during a second init+window cycle; user pointer echoed).
- **Avoided codegen landmines (v0.64.3, each with lane evidence):**
  - fp returns through cast calls (0/garbage) -> time/opacity value checks
    are labelled SKIPs; repro bundle filed (B-12).
  - Vec-of-struct element extraction (AV) -> `Vec[Int]` monitor handles +
    raw vidmode buffers.
  - `Result[Vec[...]]` payload extraction (AV) -> `GlfwExtNames` struct.
  - `Result[Float32/Float64]` payload extraction (ret-float IR mismatch)
    -> pure bit-decode readers.
  - fn-typed params as C callbacks (0) -> dispatcher + registry (B-13).
- **Windowed checks are headless-safe**: hidden (`GLFW_VISIBLE=GLFW_FALSE`)
  `GLFW_NO_API` window; nothing is shown on screen; the suite leaves GLFW
  terminated and the library handle closed.
- **Win32 + Vulkan helpers** give the engine the HWND path and surface
  creation without any Vulkan headers at build time (raw `Int` handles).

## Known limitations

- Floating-point-return functions unverifiable on v0.64.3 (B-12; see above).
- Callback handlers are process-global per event type (last set wins);
  per-window routing happens inside the handler via the window handle.
- Float32 callback params (content scale) are marshalled to Float64 for the
  handler; the C->XIOM float path is registered but not event-fired in the
  suite (no deterministic headless trigger).
- Windows x64 primary; POSIX soname documented only.
