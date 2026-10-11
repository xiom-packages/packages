# xiom.sdl3 -- Roadmap

**Version**: v0.10.0 | **Compiler**: xiom v0.64.3 | **Last updated**: 2026-10-11

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no link dependency) | Done -- `sdl3_load`/`sdl3_close` over `xiom.ffi.dl` |
| SKIP-when-absent / ABI-mismatch detection | Done -- `SDL3_LOAD_ABSENT` / `SDL3_LOAD_ABI` |
| Smoke suite (init/version/quit, timer/event) | Done |
| Resource loader (separate stage) | Done -- `sdl3_load_resources` (22 symbols) |
| Window (hidden, size/title/show/hide) | Done -- 0.3.0 |
| Renderer (draw color, clear, present) | Done -- 0.3.0 |
| Texture (RGBA8888 create/destroy) | Done -- 0.3.0 |
| Gamepad (enumeration + open/close seam) | Done -- 0.3.0 (device paths SKIP when none) |
| Event decoding (owned 128-byte buffer + typed accessors) | Done -- 0.4.0 |
| Synthetic event injection (user + KEY_DOWN) | Done -- 0.3.1/0.4.0 |
| Event filter + watch (callbacks, keep/drop) | Done -- 0.5.0 |
| Displays + video modes + keyboard state | Done -- 0.6.0 |
| Filesystem basics (base/pref/cwd, create/remove/path-info) | Done -- 0.7.0 |
| Display blit (texture upload + RenderTexture + vsync) | Done -- 0.8.0 (engine ask 1153) |
| Mouse state + window contract + typed window events | Done -- 0.9.0 (engine input layer) |
| Audio + joystick enumeration | Done -- 0.10.0 |
| Full constant tables | Phase 2 |
| POSIX soname fallback | Phase 2 |

## Phase 2 (remaining)

1. Restore the full SDL3 3.4.8 constant tables from git history (window
   flags, pixel formats, event types) and re-attach the constant checks.
2. Surface layer: texture update from a pixel buffer (done -- 0.8.0),
   `SDL_SetTextureBlendMode` + mono/alpha formats next.
3. Poll-into-owned-buffer decoding once the B-11-family foreign-write
   readback is fixed on the pin (re-test the addendum reproducer first).
4. POSIX loader fallback (`libSDL3.so.0`) when a Linux CI target exists.
5. OpenGL-context interop with `xiom.opengl` (attribute setup only; no
   cross-package imports -- both packages stay independent).
6. Broader API growth from `E:\repos\SDL3`: audio device OPEN/streaming
   (playback path), joystick open/axis/button reads, pointer capture /
   relative mouse (displays + video modes + keyboard state in 0.6.0,
   filesystem in 0.7.0, blit in 0.8.0, mouse + window contract in 0.9.0,
   audio/joystick enumeration in 0.10.0; the full-coverage drive
   continues).
