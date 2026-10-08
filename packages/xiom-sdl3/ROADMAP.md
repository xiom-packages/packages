# xiom.sdl3 -- Roadmap

**Version**: v0.3.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no link dependency) | Done -- `sdl3_load`/`sdl3_close` over `xiom.ffi.dl` |
| SKIP-when-absent / ABI-mismatch detection | Done -- `SDL3_LOAD_ABSENT` / `SDL3_LOAD_ABI` |
| Smoke suite (init/version/quit, timer/event) | Done |
| Resource loader (separate stage) | Done -- `sdl3_load_resources` (19 symbols) |
| Window (hidden, size/title/show/hide) | Done -- 0.3.0 |
| Renderer (draw color, clear, present) | Done -- 0.3.0 |
| Texture (RGBA8888 create/destroy) | Done -- 0.3.0 |
| Gamepad (enumeration + open/close seam) | Done -- 0.3.0 (device paths SKIP when none) |
| Full constant tables | Phase 2 |
| Event decoding (owned buffers) | Phase 2 |
| POSIX soname fallback | Phase 2 |

## Phase 2 (remaining)

1. Event decoding: `SDL_Event` as an owned XIOM buffer (`Vec[UInt8]`,
   56/128-byte union per platform) with typed accessors for QUIT / KEY /
   WINDOW_CLOSE / MOUSE events; keep `sdl3_poll_event(ptr)` as the raw seam.
2. Restore the full SDL3 3.4.8 constant tables from git history (window
   flags, pixel formats, event types) and re-attach the constant checks.
3. Surface layer: texture update from a pixel buffer
   (`SDL_UpdateTexture`), `SDL_SetTextureBlendMode`, renderer vsync.
4. POSIX loader fallback (`libSDL3.so.0`) when a Linux CI target exists.
5. OpenGL-context interop with `xiom.opengl` (attribute setup only; no
   cross-package imports -- both packages stay independent).
6. Re-evaluate the enum/const workarounds at each pin per the v0.64.1 sweep
   in `docs/BINDINGS-COMPILER-FINDINGS.md` (B-01/B-05/B-08 still open).
