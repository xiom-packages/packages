# SPEC: xiom.sdl3 -- SDL3 bindings via dynamic loader

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.sdl3` |
| Version | 0.11.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | SDL3 -- https://github.com/libsdl-org/SDL |
| Upstream version pinned | **3.4.8** (tag `release-3.4.8`) |
| Upstream license | zlib (bindings only; no code vendored) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (loader path is OS-agnostic in design; soname here is `SDL3.dll`) |
| Compiler pin | v0.64.3 |

## 2. G2 pin: soname + dev header hash set

**Soname (runtime contract):** `SDL3.dll` (Windows). The loader passes this
exact name to `LoadLibraryA` through `xiom.ffi.dl`; there is no link-time
dependency, no import library, and nothing vendored.

**Header set pinned** (fetched verbatim from
`https://raw.githubusercontent.com/libsdl-org/SDL/release-3.4.8/include/SDL3/<file>`):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `SDL.h` | 2,985 | `3E706319D35E274FF52BAD9D1376AE33C746CA188A2A12050AD79D7F45D0C9F8` |
| `SDL_version.h` | 5,809 | `9EC5E010A50FC115E48029B5AECC9D81479958EFF08AFEC536E322961B3B16DD` |
| `SDL_init.h` | 20,850 | `54F65B10221DE0E1EE59B99D01661A56472BC9ABB05690C0D5BD787670965A8D` |
| `SDL_timer.h` | 14,683 | `60A809DF30E0C549A91B986F517FF94515AB80A529DB95D97655A2C417F0F927` |
| `SDL_events.h` | 71,602 | `C3D19BB38D0F1B72B10C2490486E3D1926289DBB1E4062ED58A6D101F6D1CD43` |
| `SDL_error.h` | 7,095 | `C3FB65E2899D341F84AB3A0BBE99646D51EFAB252290FFF28CE36FFC7B5F9A34` |
| `SDL_stdinc.h` | 205,856 | `C8975D3B37C6E2E18CEE44F449DEB523A7DEF9A55A80E9DE949C4734A209293D` |
| **manifest (name+hash lines, LF)** | 566 | **`FD61D35102FDAC6FDDB944ED0192DFE4058222FDC531327F74264FF53B0E3023`** |

The manifest hash is the compact pin: SHA256 over the seven
`"<name> <sha256>"` lines joined with LF. Re-verify by re-fetching the tag
and recomputing (see `scripts`-free procedure below).

**Reference runtime sample used for local positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| DLL | `C:\VulkanSDK\1.4.350.0\Bin\SDL3.dll` (shipped with the Vulkan SDK) |
| FileVersion | 3.4.8.0 |
| Bytes | 4,165,560 |
| SHA256 | `6E2B4B6A60AFC19C0C03C4518910953EA0DBA7B5201C0B48D2927F2D9BA5C263` |
| Runtime report | `SDL_GetVersion()` = 3004008 (3.4.8), revision non-empty |

### Re-pin procedure

1. Pick the new upstream tag; re-fetch the seven headers from
   `raw.githubusercontent.com/libsdl-org/SDL/<tag>/include/SDL3/`.
2. Recompute per-file SHA256 and the manifest hash; update the table and the
   version row here, plus `README.md`/`AUDIT.md`, in one commit.
3. Re-run the suite with a matching runtime DLL on PATH (`port.ps1 -Package
   xiom.sdl3`) and record the run; the suite asserts runtime major == 3 and
   reports the actual version, so a mismatch is visible but not fatal.
4. If the API subset changes (new symbols in `sdl3_load`), update the G5
   confinement note and the suite's smoke coverage in the same commit.

## 3. Design: dynamic loader path (system-library pattern)

- **No link-time dependency.** The package never declares `extern "C"` SDL
  symbols; `sdl3_load()` resolves `SDL3.dll` at runtime via `xiom.ffi.dl`
  (`xiom_dl_open`/`xiom_dl_sym` runtime shims), and every call is a
  fn-pointer cast executed inside `src/../sdl3.xi` (`module xiom.sdl3`) --
  the ONLY module in the package with `unsafe`.
- **SKIP semantics.** When the DLL cannot be loaded, `sdl3_load` returns
  `Err(kind = SDL3_LOAD_ABSENT)`. The suite prints explicit `SKIP` labels
  under `[PASS]` markers (the packages runner counts markers and fails a run
  with zero markers) and exits 0, so CI without SDL3 stays green.
- **ABI mismatch is a failure.** If the DLL loads but a symbol is missing,
  the loader closes the handle and returns `Err(kind = SDL3_LOAD_ABI)`; the
  suite reports `[FAIL]` -- a present-but-wrong library must not silently
  skip the smoke.
- **Public API (safe):** `sdl3_load`, `sdl3_close`, `sdl3_init`,
  `sdl3_quit`, `sdl3_was_init`, `sdl3_get_version`, `sdl3_get_revision`,
  `sdl3_get_ticks`, `sdl3_get_performance_counter`, `sdl3_delay`,
  `sdl3_pump_events`, `sdl3_poll_event`, `sdl3_get_error`, plus the
  version-arithmetic helpers and the curated constant set.
- **Resource stage (Phase 2, separate loader):** `sdl3_load_resources`,
  `sdl3_resources_close`, `sdl3_create_window`, `sdl3_destroy_window`,
  `sdl3_show_window`, `sdl3_hide_window`, `sdl3_window_size`,
  `sdl3_set_window_title`, `sdl3_create_renderer`, `sdl3_destroy_renderer`,
  `sdl3_set_render_draw_color`, `sdl3_render_clear`, `sdl3_render_present`,
  `sdl3_create_texture`, `sdl3_destroy_texture`, `sdl3_has_gamepad`,
  `sdl3_gamepad_count`, `sdl3_open_gamepad`, `sdl3_close_gamepad`, with
  `Sdl3Resources` / `Sdl3WindowSize`. A missing resource symbol fails only
  this stage (`SDL3_LOAD_ABI`); the smoke stage is unaffected. Window-
  dependent checks SKIP on hosts that cannot create a window.

**0.3.1 addition (engine ask `REL-20261010-1834-engine-3`, 2026-10-11):**
`SDL_PushEvent` joined the resolved symbol set and the loader struct
(`sdl3_push_event`); the suite gained a headless event-pump proof -- inject
a synthetic user event (0x8000) into a 128-byte XIOM slot, pump, consume
with `poll(NULL)` (22/22 x2 with SDL 3.4.8).  Buffer readback is deferred:
on this host reading the foreign-written event buffer reproduces the
B-11-family slot corruption (recycled bytes after the call; addendum item
filed to the compiler lane).

**0.4.0 addition (event decoding, 2026-10-11):** `SDL_Event` decoded from an
owned 128-byte buffer (`SDL_EVENT_SIZE`; the union's `padding[128]` pins the
size).  Shared header: type u32 @0, reserved u32 @4, timestamp u64 @8,
windowID u32 @16; keyboard: scancode @24, key @28, mod @32 (u16), down @36,
repeat @37; mouse motion: state @24, x/y/xrel/yrel f32 @28/32/36/40; mouse
button: button @24, down @25, clicks @26, x/y @28/32; window: data1 @20,
data2 @24 (Sint32).  Offsets verified in the pinned `release-3.4.8` header
and byte-identical in the local `release-3.2.10` clone.  Accessors are pure
XIOM; f32 fields have `_bits` accessors plus `sdl3_f32_from_bits` (B-12
discipline -- no fp cast-call returns).  The suite decodes self-built buffers
in every shape (DLL-free) and injects a synthetic KEY_DOWN through the real
queue (consume semantics; B-11 readback deferral unchanged).

**0.5.0 addition (event filter + watch, 2026-10-11):** `SDL_SetEventFilter`,
`SDL_AddEventWatch`, `SDL_RemoveEventWatch` joined the resolved symbol set
(so the ABI-mismatch classification covers them).  Each registration hands
SDL a FIXED top-level dispatcher (`sdl3_filter_dispatch` /
`sdl3_watch_dispatch`; B-13: fn-typed param values cannot cross into C);
user handlers live in module-level `Vec[fn]` registries (m130 element ABI,
last registered wins).  The dispatcher copies the 128-byte `SDL_Event` into
an owned buffer via our own `ffi.memcpy` (safe read direction) so handlers
decode with the 0.4.0 accessors and the B-11 foreign-write readback path is
never touched.  Handler shapes are 1-argument (event only) because
`Vec[fn]` element calls with >= 2 arguments type their result as `()`
(finding B-15); the registration userdata is exposed via
`sdl3_filter_userdata()` / `sdl3_watch_userdata()`.  Dispatcher bodies avoid
bare `return;` in explicitly `-> Unit` fns (finding B-14).  Semantics
proven by the suite: a keep-filter passes a pushed KEY_DOWN to the poll; a
rejecting filter makes `SDL_PushEvent` itself return false (drop proof);
the watch observes without consuming and removal stops further firing.

**0.6.0 addition (displays + keyboard, 2026-10-11):** 11 symbols joined the
core loader: `SDL_GetDisplays` (+ `SDL_free` of the returned array),
`SDL_GetPrimaryDisplay`, `SDL_GetDisplayName`, `SDL_GetDisplayBounds`,
`SDL_GetDisplayUsableBounds`, `SDL_GetCurrentDisplayMode`,
`SDL_GetDesktopDisplayMode`, `SDL_GetKeyboardState`, `SDL_GetModState`,
`SDL_GetKeyboardFocus`.  Needs `SDL_INIT_VIDEO`; the suite SKIPs the block
when video init fails.  `SDL_Rect` out-params use owned 16-byte slots
(proven readback direction); the display list and `SDL_DisplayMode` are
SDL-owned memory read with `ffi.ptr_read_*` (read direction proven by the
0.5.0 event copy); `SDL_DisplayMode` layout pinned from the release-3.2.10
header (ABI-stable): displayID/format u32, w/h i32, pixel_density @16 f32,
refresh_rate @20 f32 -- floats decode via `sdl3_f32_from_bits` (B-12
discipline).  `SDL_GetDisplays` returns one id per `sdl3_display_at` call
(array fetched + freed per call; O(displays)).

**0.7.0 addition (filesystem, 2026-10-11):** 6 symbols joined the core
loader: `SDL_GetBasePath`, `SDL_GetPrefPath`, `SDL_GetCurrentDirectory`,
`SDL_CreateDirectory`, `SDL_RemovePath`, `SDL_GetPathInfo`.  Ownership per
the pin: BasePath is SDL-owned (copied, never freed); PrefPath and
CurrentDirectory are caller-owned and freed via `SDL_free` after the copy
into an XIOM Str.  `SDL_PathInfo` layout pinned (type i32 @0, size u64 @8,
create @16, modify @24, access @32; SDL_Time = Sint64 ns); read from an
owned 40-byte slot (proven readback direction).  `SDL_PATHTYPE_*` constants
exported.  The suite's create/remove round trip runs under
`%APPDATA%\xiom-lane\sdl3-conformance\` (SDL_GetPrefPath creates it; the
suite removes the subdir and the app dir after asserting
`SDL_PATHTYPE_DIRECTORY` + a positive mtime) -- no shared-toolchain paths
are touched (ops hygiene item REL-20261011-1134-ops).

**0.8.0 addition (display blit, 2026-10-11; engine ask
`REL-20261011-1153-engine`):** 3 symbols joined the RESOURCES loader:
`SDL_UpdateTexture`, `SDL_RenderTexture` (SDL3's RenderTexture -- the
SDL2-era RenderCopy was renamed), `SDL_SetRenderVSync`.  The pixel buffer
is an XIOM-owned Vec that SDL READS (`sdl3_update_texture` computes
`pitch = w*4`, passes a NULL rect = whole texture, requires
`pixels.len() >= w*h*4`); no foreign-write readback is involved (B-11 path
avoided).  `SDL_TEXTUREACCESS_STREAMING` exported.  Engine done-bar met:
`examples/demo_sdl3.xi` runs on this box (hidden window -> 64x64 RGBA
checker -> update/vsync/blit/present all true -> clean shutdown), and the
suite carries the same 64x64 blit check.

**0.9.0 addition (mouse + window contract, 2026-10-11; engine input layer):
** `SDL_GetMouseState` joined the core loader (two f32 OUT-params + u32
mask; slot readback + `sdl3_f32_from_bits`, B-12 discipline);
`SDL_SetWindowSize` + `SDL_SetWindowResizable` joined the RESOURCES loader.
The full `SDL_EVENT_WINDOW_*` family is exported (SHOWN 0x202 .. 
CLOSE_REQUESTED 0x210, sequential per the pinned header).  The suite proves
the engine's typed route end-to-end: an event watch observes
`SDL_SetWindowSize(300,180)` -> `SDL_EVENT_WINDOW_RESIZED` with
data1/data2 = 300/180 decoded from the copied buffer, plus the size
readback; mouse state idle (buttons=0, coords decode).  README carries the
engine event-loop snippet (watch + decode + drain).

**0.10.0 addition (audio + joystick enumeration, 2026-10-11; engine device
selection + `REL-20261011-1321-engine`):** 6 symbols joined the core loader:
`SDL_GetAudioPlaybackDevices`, `SDL_GetAudioRecordingDevices`,
`SDL_GetAudioDeviceName`, `SDL_GetCurrentAudioDriver`, `SDL_GetJoysticks`,
`SDL_GetJoystickNameForID`.  Device arrays are caller-owned (freed via
`SDL_free`; fetched + freed per `_at` call); device/driver strings are
SDL-owned consts (copied, never freed).  `SDL_PIXELFORMAT_ABGR8888`
(0x16762004) exported with the 8888 naming note: SDL names are MSB-first,
so on little-endian `ABGR8888` is the byte-order `R,G,B,A` array a plain
RGBA8 framebuffer produces (the engine asked for exactly that).
Requires `SDL_INIT_AUDIO`/`JOYSTICK`; the suite SKIPs the block when init
fails.

**0.11.0 addition (full constant tables, 2026-10-11):** ~190 constants
source-generated from the release-3.2.10 headers (same values as the
release-3.4.8 pin semantics): the complete `SDL_EVENT_*` enum (90 new
entries beyond the previously shipped subset), the 23 remaining window
flags, all 14 `SDL_KMOD_*` modifiers and 62 explicit-value pixel formats
(`SDL_PIXELFORMAT_*`, including the RGB565/24/48, XRGB/BGRX/ARGB/BGRA
families and the NV12/NV21/YV12/IYUV/P010/MJPG fourCCs).  Names already
defined in earlier sections are not repeated.  The suite samples ~20
values across all four families (FIRST/LAST/TEXT_EDITING/
JOYSTICK_AXIS_MOTION/GAMEPAD_ADDED/AUDIO_DEVICE_ADDED/POLL_SENTINEL,
FULLSCREEN/BORDERLESS/RESIZABLE/HIGH_PIXEL_DENSITY/TRANSPARENT,
LSHIFT/LCTRL/RALT/NUM/SCROLL, RGB565/XRGB8888/NV12).

## 4. Test matrix (recorded 2026-10-11, compiler v0.64.3)

| Configuration | Command | Result |
|---------------|---------|--------|
| SDL3 absent (CI shape) | `port.ps1 -Package xiom.sdl3` with the Vulkan SDK dir filtered out of PATH | **PASS, 4/4 x2** (`loader: SKIP ... code 126`, `smoke: SKIP ...`; decode layer still runs -- it is pure XIOM) |
| SDL3 3.4.8 present | same command, default PATH | **PASS, 48/48 x2** -- same 48 checks with the constant test now covering the full tables (sampled) |
| Demo probe | `xiom --run examples/demo_sdl3.xi` with SDL3 on PATH | exit 0; blit section prints update=true vsync=true blit=true present=true; closed cleanly (2026-10-11) |

No `port.args.json` is needed: the suite compiles no C source and needs no
extra compiler flags (this is the design win of the loader path over a C
bridge). `scripts/port.ps1` runs it unchanged.

## 5. Compiler notes

- The loader module avoids the binding-lane resolver pitfalls documented in
  `docs/BINDINGS-COMPILER-FINDINGS.md`: all exported functions carry the
  `sdl3_` prefix (no generic `up`/`open`-class names), no exported-const
  references inside confined blocks, no cross-module const aliases, no
  child->parent imports (single module), no malloc/free in confined blocks.
- `xiom.ffi.dl`'s stale "Int-to-pointer casts are broken" smoke note does
  not apply: the fn-pointer cast idiom used here is proven by this suite
  (see the stdlib wishlist item W-4 in `docs/BINDINGS-STDLIB-WISHLIST.md`).
- 0.3.0 runs recorded on **v0.64.1** (the resolver picks the installed
  0.64.1 over the v0.64.0 pin); the lane re-tests at each pin -- see the
  v0.64.1 sweep in `docs/BINDINGS-COMPILER-FINDINGS.md` (B-06/B-09 fixed,
  B-01/B-05/B-08 open).

## 6. Scope

0.8.0 covers the pilot smoke, the resource stage (window/renderer/texture/
gamepad), the event layer (decode + filter/watch), displays/keyboard,
filesystem basics and the display blit. Remaining Phase 2 items: the full
constant tables (git history), audio/joystick coverage, POSIX soname
fallback, and opengl-context interop -- see `ROADMAP.md`.
