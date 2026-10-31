# xiom.sdl3 -- Roadmap

**Version**: v0.22.0 | **Compiler**: xiom v0.65.4 | **Last updated**: 2026-10-31

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no link dependency) | Done -- `sdl3_load`/`sdl3_close` over `xiom.ffi.dl` |
| SKIP-when-absent / ABI-mismatch detection | Done -- `SDL3_LOAD_ABSENT` / `SDL3_LOAD_ABI` |
| Smoke suite (init/version/quit, timer/event) | Done |
| Resource loader (separate stage) | Done -- `sdl3_load_resources` (42 symbols) |
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
| Full constant tables (events/flags/keymods/pixel formats) | Done -- 0.11.0 (source-generated) |
| Push audio streaming + mouse wheel accessors | Done -- 0.12.0 |
| Capture streams + stream query (recording device, GetAudioStreamData, available/clear/format; separate out-param slots per B-17) | Done -- 0.13.0 |
| Pointer capture + relative mouse (per-window) + global/relative state | Done -- 0.14.0 |
| Joystick open/axis/button reads (virtual-joystick instrumented, no hardware) | Done -- 0.15.0 |
| Drag-drop payload decode (SDL_DropEvent, DLL-independent) | Done -- 0.16.0 |
| Foreign-written event readback (poll into an owned buffer) | Done -- 0.18.0 (B-11 addendum retired on v0.64.4; user-event + KEY_DOWN readback witnesses live) |
| Joystick caps (rumble/LED flags + counts/type) as typed queries | Done -- 0.19.0 (property-flag path incl. positive round trip witness) |
| Haptic wave forms (periodic encode/create/run/stop, typed errors) | Done -- 0.19.0 (device path SKIP-safe; not-haptic typed-error witness live) |
| Pen/tablet decode (motion/touch/button/proximity + tool type) | Done -- 0.19.0 (DLL-free decode + queue readback witness) |
| A14 UI platform (window identity/geometry, focus + DPI routing, IME, clipboard) | Done -- 0.21.0 (engine ask `REL-20261021-1652-engine-5`; hidden-window live legs + typed watch routing) |
| Window surface tier (icon/BMP/surface, native handle, Vulkan surface) | Done -- 0.22.0 (engine ask `REL-20261031-1423-engine-4`; BMP round trip + Win32 HWND + Vulkan typed rejection live) |
| POSIX soname fallback | Phase 2 |

## Phase 2 (remaining)

1. Regenerate the constant tables at each pin move (the extraction recipe:
   comment-strip + enum-parse + macro-eval vs the new headers); extend with
   the remaining #define-style tables (KMOD combos done; scancodes/keycodes
   next if a consumer needs them).
2. Surface layer: texture update from a pixel buffer (done -- 0.8.0),
   `SDL_SetTextureBlendMode` + mono/alpha formats next.
3. ~~Poll-into-owned-buffer decoding once the B-11-family foreign-write
   readback is fixed on the pin~~ **DONE -- 0.18.0** (re-tested the
   addendum reproducer on v0.64.4: the SDL-written buffer reads back
   exactly; user-event + KEY_DOWN readback checks live in the suite;
   the general B-11 driver-thread shape stays open, see `xiom.vma`).
4. POSIX loader fallback (`libSDL3.so.0`) when a Linux CI target exists.
5. OpenGL-context interop with `xiom.opengl` (attribute setup only; no
   cross-package imports -- both packages stay independent).
6. Broader API growth from `E:\repos\SDL3`: recording streams + audio
   capture (done -- 0.13.0), joystick open/axis/button reads (needs a pad on
   the box), pointer capture / relative mouse, drag-and-drop payloads
   (displays + video modes + keyboard state in 0.6.0, filesystem in 0.7.0,
   blit in 0.8.0, mouse + window contract in 0.9.0, audio/joystick
   enumeration in 0.10.0, tables in 0.11.0, push audio + wheel in 0.12.0,
   capture streams + query in 0.13.0, pointer/relative mouse in 0.14.0,
   live joystick reads in 0.15.0, drag-drop payload decode in 0.16.0,
   foreign-written event readback in 0.18.0, joystick caps + haptic wave
   forms + pen/tablet decode in 0.19.0, A14 window/focus/DPI/IME/clipboard
   surface in 0.21.0, icon/BMP/surface + native handle + Vulkan surface
   wrapper in 0.22.0; the full-coverage drive continues).
