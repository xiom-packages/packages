# SPEC: xiom.sdl3 -- SDL3 bindings via dynamic loader

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.sdl3` |
| Version | 0.22.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | SDL3 -- https://github.com/libsdl-org/SDL |
| Upstream version pinned | **3.4.8** (tag `release-3.4.8`) |
| Upstream license | zlib (bindings only; no code vendored) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (loader path is OS-agnostic in design; soname here is `SDL3.dll`) |
| Compiler pin | v0.65.4 |

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
with `poll(NULL)` (22/22 x2 with SDL 3.4.8).  Buffer readback was deferred
at the time: on v0.64.3 reading the foreign-written event buffer reproduced
the B-11-family slot corruption (recycled bytes; addendum item
`REL-20261011-0304` filed to the compiler lane).  **RETIRED on v0.64.4 --
see the 0.18.0 addition below.**

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
queue (the true-consume route; the 0.19.0 correction below retires the
old poll(NULL) "consume" wording -- NULL is a peek on 3.4.8).

**0.5.0 addition (event filter + watch, 2026-10-11; lifted in 0.20.0):**
`SDL_SetEventFilter`, `SDL_AddEventWatch`, `SDL_RemoveEventWatch` joined
the resolved symbol set (so the ABI-mismatch classification covers them).
0.20.0 hands handlers DIRECTLY to SDL (B-22 fixed, m277; the 0.5.0 fixed
dispatchers + `Vec[fn]` registries + userdata accessors are gone; B-15
fixed too, so the natural `(userdata, event)` shape is used).  Handlers
copy the 128-byte `SDL_Event` from its raw address with our own
`ffi.memcpy` via `sdl3_event_copy` (safe read direction; the B-11
foreign-write readback path is never touched) and decode with the 0.4.0
accessors.  Removal passes the SAME handler + userdata (SDL matches the
pair).  Semantics proven by the suite: a keep-filter passes a pushed
KEY_DOWN to the poll; a rejecting filter makes `SDL_PushEvent` itself
return false (drop proof); the watch observes without consuming and
removal stops further firing.

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

**0.12.0 addition (audio streaming + mouse wheel, 2026-10-11; engine asks):
** 7 symbols joined the core loader: `SDL_OpenAudioDeviceStream` (called
with a NULL callback = push mode), `SDL_PutAudioStreamData`,
`SDL_ResumeAudioStreamDevice`, `SDL_PauseAudioStreamDevice`,
`SDL_DestroyAudioStream`, `SDL_GetAudioStreamQueued`,
`SDL_AudioStreamDevicePaused`.  `SDL_AudioSpec` = {format u32 @0, channels
i32 @4, freq i32 @8}; `SDL_AUDIO_F32` (0x8120) and
`SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK` exported.  **Important verification
note:** the spec MUST be built with byte-indexed slot writes; a first build
using `ffi.ptr_write_u32_le(slot + N)` lost the non-base fields and the
runtime rejected it -- that is now compiler finding **B-16** with repro
`docs/repro/bindings-pilot/ptr-slot-write/` (ptr_write_sum=11 vs
byte_index_sum=66).  Suite: 7680 B of silence (960 frames F32/2ch/48k)
pushed, device resumed (not paused) and paused again.  Mouse wheel: layout
pinned (x @24, y @28, direction @32, mouse_x @36, mouse_y @40) with 7
accessors + `SDL_MOUSEWHEEL_NORMAL/FLIPPED` (engine ask
`REL-20261011-1411-engine-2`).

**0.13.0 addition (capture streams + stream query, 2026-10-11):** 4 symbols
joined the core loader: `SDL_GetAudioStreamData`, `SDL_GetAudioStreamAvailable`,
`SDL_ClearAudioStream`, `SDL_GetAudioStreamFormat`.
`SDL_AUDIO_DEVICE_DEFAULT_RECORDING` (0xFFFFFFFE) exported;
`sdl3_open_audio_recording_stream` reuses the shared
`SDL_OpenAudioDeviceStream` path (NULL callback = pull mode).  Suite: the
default recording device opens (wasapi), reports its format, resumes, and
drains 8192 B of PCM into an owned buffer (avail=11520, pause-again +
clear OK); the available/clear semantics are proven deterministically on a
push stream (push 4096 B -> avail=4096 -> clear -> queued=0, avail=0,
read-after-clear=0).  **Compiler finding B-17 found + worked around:** the
first build passed one 24-byte slot with `dst_spec = slot.as_mut_ptr() + 12`
and read the dst spec as zeros -- the `+ 12` pointer is miscompiled to a
wild address, SDL wrote the spec into unowned memory and the process died
with STATUS_HEAP_CORRUPTION on ~30-50 % of runs (same binary).  All
out-params now use one separate slot per pointer (format query: two 12-byte
slots; mouse state: two 4-byte slots); repro
`docs/repro/bindings-pilot/ptr-arith/`.  With the fix the 3.4.8 DLL writes
BOTH format specs (src=dst=33056/2ch/48000Hz).

**0.14.0 addition (pointer capture + relative mouse, 2026-10-11):** 5
symbols joined the core loader: `SDL_GetGlobalMouseState`,
`SDL_GetRelativeMouseState` (each writes two f32 out-params into one owned
slot per pointer -- B-17 discipline), `SDL_SetWindowRelativeMouseMode`,
`SDL_GetWindowRelativeMouseMode` (SDL3 exposes relative mode per window),
`SDL_CaptureMouse`.  Suite: the global state reads the live cursor
(1684,386 on this host), the relative state reads 0,0 idle with mask 0,
the per-window relative-mode round trip is true/true/false/false, and the
capture toggle calls succeed (enable=false on a hidden window is the
documented foreground-only behavior; disable=true).

**0.15.0 addition (live joystick path, 2026-10-11):** 10 symbols joined
the core loader: `SDL_OpenJoystick`, `SDL_CloseJoystick`,
`SDL_JoystickConnected`, `SDL_GetJoystickName`, `SDL_GetJoystickAxis`
(16-bit result sign-extended explicitly), `SDL_GetJoystickButton`,
`SDL_SetJoystickVirtualAxis`, `SDL_SetJoystickVirtualButton`,
`SDL_AttachVirtualJoystick`, `SDL_DetachVirtualJoystick` (`Sdl3` +
`SDL_VIRTUAL_JOYSTICK_DESC_SIZE`).  `SDL_AttachVirtualJoystick` builds the
`SDL_VirtualJoystickDesc` as a 136-byte x64 slot with byte-indexed writes
(`version` = sizeof(desc) per the `SDL_INIT_INTERFACE` convention, type =
`SDL_JOYSTICK_TYPE_UNKNOWN`, full valid masks, name pointer into the
caller's `Str` which SDL keeps).  Suite: a hardware-free virtual pad is
attached, opened through the real read path, fed axis0=16384 + button1,
read back exactly, and detached -- no SKIP.

**0.16.0 addition (drag-drop payload decode, 2026-10-11):** pure-buffer
`SDL_DropEvent` accessors (no new DLL symbols): `sdl3_event_drop_window_id`
(u32 @16), `sdl3_event_drop_x`/`_y` (f32 @20/@24),
`sdl3_event_drop_source`/`_data` (ptr @32/@40 -> `Str::from_c_str`,
`""` when NULL), plus `sdl3_str_c_ptr` for building synthetic C structures.
The SDL_EVENT_DROP_* type constants already existed (0.11.0 tables).
Because the arm is DLL-independent it joins the decode layer that runs in
BOTH shapes -- the absent baseline becomes 5 checks.

**0.18.0 addition (foreign-written event readback, 2026-10-13):** the
B-11-addendum deferral is RETIRED on v0.64.4.  Re-testing the addendum
reproducer (`REL-20261011-0304`) shows the SDL-written event buffer reads
back EXACTLY: poll a pushed `SDL_EVENT_USER` (0x8000) into an owned
128-byte slot, decode `type` byte-indexed -> `0x8000` (no recycled
bytes; previously `0x33323100`/`0x04040404` on v0.64.3).  The suite now
witnesses both the user-event readback and the full `KEY_DOWN` readback
decode (type/scancode/key/down via the 0.4.0 accessors over a
FOREIGN-written buffer).  The general B-11 (driver-thread slot recycle,
`xiom.vma` packed-return workaround) remains open and is not claimed
fixed by this re-test.

**0.19.0 addition (device surface, 2026-10-13; engine ask
`REL-20261013-2324-engine`):** 32 symbols joined the core loader, all
verified by the generator's new device-surface audit (declared in the
pinned headers AND exported by the DLL AND carrying a generated wrapper;
see below).

- **Joystick caps (typed queries).** SDL3 has no
  `SDL_JoystickHasRumble`-style functions in the pinned 3.4.8 headers:
  capabilities are BOOLEAN strings on the joystick properties group.
  `sdl3_joystick_properties` (`SDL_GetJoystickProperties`) + the five
  `SDL_PROP_JOYSTICK_CAP_*_BOOLEAN` names read through
  `SDL_GetBooleanProperty` back `sdl3_joystick_has_rumble`,
  `_has_rumble_triggers`, `_has_mono_led`, `_has_rgb_led`,
  `_has_player_led`; `SDL_GetNumJoystickAxes/Buttons/Hats/Balls` and
  `SDL_GetJoystickType` back the counts/kind; `sdl3_joystick_caps`
  aggregates everything into `Sdl3JoystickCaps` (missing properties
  group -> all-false/zero record, no silent nulls).  The suite proves the
  virtual pad's 2 axes/2 buttons/type 0 with all flags naturally false,
  then witnesses the flag READ path positively by flipping
  `SDL.joystick.cap.rumble` on the SDL-owned group (true -> read true ->
  reset false -> read false).
- **Haptic wave forms.** `SDL_HapticEffect` is a 72-byte x64 union
  (`SDL_HAPTIC_EFFECT_SIZE`; sizeof/offsets computed by the generator's
  Win64 layout engine and cross-checked with a clang `offsetof` probe
  against the pinned headers).  `sdl3_haptic_encode_periodic` validates
  (wave in SINE/SQUARE/TRIANGLE/SAWTOOTHUP/SAWTOOTHDOWN, direction
  encoding, range checks per field) and writes `SDL_HapticPeriodic`
  byte-indexed (`type` u16 @0, `direction{type u8 @4, dir[3] s32
  @8/12/16}`, `length` u32 @20, `delay/button/interval` u16 @24/26/28 =
  0 trigger-less, `period` @30, `magnitude` @32, `offset` @34, `phase`
  @36, `attack_*` @38/40, `fade_*` @42/44).  `sdl3_haptic_open`/
  `open_from_joystick`/`create_periodic`/`update_periodic`/`run`/`stop`
  return typed `Sdl3HapticError{kind, message}` (`SDL3_HAPTIC_ERR_PARAM`
  for encode violations, `_OPEN/_CREATE/_UPDATE/_RUN/_STOP` with the
  `SDL_GetError` string otherwise); `effect_supported`, `status`,
  `destroy`, the `GetHaptics` enumeration (`count`/`at`/`name_for_id`),
  features/max-effects/axes getters, and the rumble convenience layer
  (`rumble_supported`/`init`/`play`/`stop`) complete the surface.  The
  suite proves the encode + typed PARAM error + enumeration + typed OPEN
  error (unknown id) + the not-haptic virtual pad path
  (`SDL_OpenHapticFromJoystick` typed error) with no hardware; the
  device path (SINE create/run/status/stop/destroy + rumble) is written
  and runs when `SDL_GetHaptics` finds a device (SKIP on this host).
- **Pen/tablet decoding path.** Layouts pinned to the 3.4.8 headers
  (Win64 sizes 24/40/40/40; verified offsets): every pen event carries
  windowID u32 @16 and `which` (pen id) u32 @20; motion/touch/button add
  `pen_state` u32 @24 (`SDL_PEN_INPUT_*`), x f32 @28, y f32 @32; touch:
  `eraser` u8 @36, `down` u8 @37; button: `button` u8 @36, `down` u8
  @37; proximity in/out decode to the windowID/`which` pair.
  `sdl3_pen_device_type` (`SDL_GetPenDeviceType`) is the tool-type
  query, `SDL_PEN_DEVICE_TYPE_INVALID` for an unknown id.  The suite
  decodes self-built buffers for all four members (DLL-free), pushes a
  synthetic PEN_MOTION through the real queue and decodes it from the
  SDL-written buffer, and probes the tool-type query for an unknown id.
- **Suite semantics correction found by the pen-live check:**
  `SDL_PollEvent(NULL)` on the pinned 3.4.8 runtime is a PEEK (a pending
  real event is reported but NOT removed; only SDL's internal poll
  sentinel is cleared), and a poll that meets that sentinel returns
  false with events queued right behind it.  The suite's drains now
  consume into an owned scratch buffer and pushed-event checks match on
  the event type for a bounded number of polls (`drain_events`/
  `poll_for`); the two legacy injection checks were tightened the same
  way.  The 0.3.1/0.18.0 history is preserved: true consumption always
  polls into an XIOM-owned buffer.
- **Generator extension (100% declared additions kept):** the generator
  now audits the device-surface additions against the pinned inputs at
  generation time: 32/32 symbols declared+exported+wrapped, 45/45
  constant values (property strings, haptic/pen/joystick tables) match
  the headers, and 14/14 Win64 layouts (pen/touch event structs + haptic
  periodic/union members) match the pinned offsets -- mismatch aborts
  generation.  The audit lands in `docs/gen_manifest.json` under
  `device_surface`; declared/exported/target stay 1271/1270/1269 and the
  full-surface suite stays 1269/1269 bound, 1270/1270 resolved.

**0.21.0 addition (A14 UI platform surface, 2026-10-21; engine ask
`REL-20261021-1652-engine-5`):** 20 symbols joined the two loaders, all
declared and exported by the pinned SDL 3.4.8 ABI.  Window-scoped calls
stay on the resource loader (they take `SDL_Window*`); global clipboard and
the extra display query stay on the core loader.

- **Window identity + geometry (7 resource + 1 core symbol; plus the pure
  `sdl3_display_index` composition).**
  `SDL_GetWindowID` -> `sdl3_window_id` (u32 id as Int) and
  `SDL_GetWindowFromID` -> `sdl3_window_from_id` (0 when stale) give the
  identity round trip; `SDL_GetWindowPosition`/`SDL_SetWindowPosition` ->
  `sdl3_window_position` (`Sdl3WindowPosition{ok,x,y}`; two owned i32
  slots) / `sdl3_set_window_position`; `SDL_GetWindowSizeInPixels` ->
  `sdl3_window_size_pixels` (`Sdl3PixelSize{ok,width,height}`);
  `SDL_GetWindowDisplayScale` -> `sdl3_window_display_scale` (Float64);
  `SDL_GetDisplayForWindow` -> `sdl3_window_display` (display id).
  `SDL_GetDisplayContentScale` -> `sdl3_display_content_scale` and
  `sdl3_display_index` (position of a display id in the existing
  `SDL_GetDisplays` enumeration, -1 when absent) complete the
  monitor/display pair for a window.  The two float returns were
  re-verified on v0.64.8 (B-12 fix: both read 1.0 on this box); event
  payload floats still decode through `sdl3_f32_from_bits`.
- **Per-window focus + DPI-change routing (pure decode, no symbols).**
  `sdl3_event_window_focus` returns `Sdl3WindowFocus{state, window_id}`
  where state is `SDL3_WINDOW_FOCUS_GAINED/LOST/NONE` for
  `SDL_EVENT_WINDOW_FOCUS_GAINED/LOST` (windowID u32 @16);
  `sdl3_event_is_focus_change` is the filter predicate.
  `sdl3_event_dpi_change` returns `Sdl3DpiChange{reason, window_id,
  display_id, pixel_width, pixel_height}` for
  `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED` (data1/data2 = new pixel size),
  `SDL_EVENT_WINDOW_DISPLAY_CHANGED` (data1 = new display id) and
  `SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED`; `sdl3_event_is_dpi_change` is
  the predicate.  Both work inside the existing filter/watch callbacks
  (copy the raw address with `sdl3_event_copy`).  A watch test pushes all
  five event kinds plus three text kinds through the real queue and
  verifies the typed values.
- **Text input + IME (6 resource symbols + pure decode).**
  `SDL_StartTextInput`/`SDL_StopTextInput`/`SDL_TextInputActive` ->
  `sdl3_start_text_input`/`sdl3_stop_text_input`/`sdl3_text_input_active`;
  `SDL_SetTextInputArea`/`SDL_GetTextInputArea` ->
  `sdl3_set_text_input_area` (16-byte rect slot built byte-indexed,
  B-16) and `sdl3_get_text_input_area` (`Sdl3TextInputArea{ok,x,y,w,h,
  cursor}` with separate rect/cursor slots); `SDL_ClearComposition` ->
  `sdl3_clear_composition`.  The cursor is the IME caret offset relative
  to rect.x -- the accessor the IME path needs.  Decode:
  `SDL_TextEditingEvent` (pinned x64: text ptr @24, start i32 @32,
  length i32 @36, windowID @16) -> `sdl3_event_text_editing`
  (`Sdl3TextEditing{window_id, text, start, length}`);
  `SDL_TextInputEvent` (text ptr @24) -> `sdl3_event_text_input` (the
  committed UTF-8, copied).  **Cancellation:** SDL 3.4.8 has no
  `SDL_EVENT_TEXT_EDITING_CANCELLED`; SDL signals cancellation by sending
  a `TEXT_EDITING` event with an empty/NULL preedit.  `sdl3_event_text_kind`
  classifies those as `SDL3_TEXT_EVENT_CANCELLED` (non-empty preedit =
  EDITING, TEXT_INPUT = COMMIT, other = NONE), giving consumers a typed
  cancellation signal without inventing an SDL event type.  The suite
  exercises start/active/area/cursor/clear/stop live on a hidden window
  and decodes preedit/commit/cancel from owned buffers.
- **Clipboard + primary selection (6 core symbols).**
  `SDL_SetClipboardText`/`SDL_GetClipboardText`/`SDL_HasClipboardText` ->
  `sdl3_set_clipboard_text`/`sdl3_get_clipboard_text`/
  `sdl3_has_clipboard_text`; the same trio for
  `SDL_SetPrimarySelectionText`/`Get`/`Has` ->
  `sdl3_set_primary_selection_text`/`sdl3_get_primary_selection_text`/
  `sdl3_has_primary_selection_text`.  Getters return caller-owned
  `char *` per the pin: copied with `Str::from_c_str` then `SDL_free`d.
  The primary-selection setter returns false + `SDL_GetError` where the
  platform has no primary selection (the typed-unsupported path; the
  suite reports SKIP there and falls back).  On this Windows host the
  primary selection round trip is live (set/has/get true), so the suite
  covers both branches (live here, SKIP elsewhere).
- **B-series discipline:** all handles stay `Int`; every out-param gets
  its own owned byte slot; the 16-byte `SDL_Rect` in-param is written
  byte-indexed; no pointer arithmetic crosses a foreign call.  The new
  code adds no `unsafe` outside the existing confined call wrappers.

**0.22.0 addition (window surface tier, 2026-10-31; engine ask
`REL-20261031-1423-engine-4`):** 9 symbols joined the two loaders, all
declared and exported by the pinned SDL 3.4.8 ABI.  Surface creators live
on the core loader (no window needed); window-scoped calls stay on the
resource loader.

- **Surface + icon (4 core + 1 resource symbol).**
  `SDL_CreateSurface`/`SDL_DestroySurface` ->
  `sdl3_create_surface(width, height, format)` (owned `SDL_Surface*`,
  `Err` carries `SDL_GetError`) / `sdl3_destroy_surface`; `SDL_LoadBMP` ->
  `sdl3_load_bmp(path)` (owned surface); `SDL_SaveBMP` ->
  `sdl3_save_bmp(surface, path)` (`Result[Unit, Str]`); `SDL_SetWindowIcon`
  -> `sdl3_set_window_icon(win, surface)` (SDL copies what it needs; the
  caller keeps and destroys the surface).  Formats use the existing
  `SDL_PIXELFORMAT_RGBA8888`/`ABGR8888` constants.  The suite proves a
  4x3 RGBA create -> SaveBMP -> LoadBMP -> destroy round trip and a typed
  error for a missing file, then sets a 2x2 icon on a hidden window.
- **Native window handle (1 resource symbol + 2 property getters).**
  `SDL_GetWindowProperties` -> `sdl3_window_properties(win)` (the
  `SDL_PropertiesID` as `Int`); `SDL_GetPointerProperty`/
  `SDL_GetNumberProperty` -> `sdl3_get_pointer_property`/
  `sdl3_get_number_property` (`UInt32` id, name, 0 fallback).
  `sdl3_window_native_handle(win)` composes them into
  `Sdl3NativeWindow{ok, kind, handle}` and resolves, in order:
  `SDL_PROP_WINDOW_WIN32_HWND_POINTER` (HWND),
  `SDL_PROP_WINDOW_X11_WINDOW_NUMBER` (X11 window id),
  `SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER` (wl_surface*),
  `SDL_PROP_WINDOW_COCOA_WINDOW_POINTER` (NSWindow*); kind is
  `SDL3_NATIVE_WINDOW_WIN32/X11/WAYLAND/COCOA/NONE`.  On this host the
  hidden window reports kind=WIN32 with a non-zero HWND.  The engine's
  `win_icon.cpp` GetProcAddress shim can now be replaced portably.
- **Vulkan surface wrapper (1 resource symbol).**
  `SDL_Vulkan_CreateSurface` -> `sdl3_vulkan_create_surface(win, instance,
  slot)`; `slot` is an owned 8-byte `Vec[UInt8]` from
  `sdl3_vulkan_surface_slot()`, zeroed before the call so a failed create
  reads back 0 through `sdl3_vulkan_surface_value(slot)`.  The allocator
  is NULL; the engine owns the `VkInstance` and the instance-extension
  negotiation.  The suite verifies the typed rejection path (instance=0)
  and the zeroed out-slot; the positive path is the engine's live device.
- **B-series discipline:** the new out-param uses the existing owned-slot
  helpers (`sdl3_slot`, `sdl3_write_u64_le`, `sdl3_read_u64_at`); every
  string property is passed with `.c_str()`; no pointer arithmetic
  crosses a foreign call.

## 4. Test matrix (recorded 2026-10-31, compiler v0.65.4)

| Configuration | Command | Result |
|---------------|---------|--------|
| SDL3 absent (CI shape) | `port.ps1 -Package xiom.sdl3` with the Vulkan SDK dir filtered out of PATH | **PASS, 9/9 x2** (`loader: SKIP ... code 126`, `smoke: SKIP ...`; decode + UI-decode + haptic encode + device constants still run -- all pure XIOM) |
| SDL3 3.4.8 present | same command, default PATH | **PASS, 85/85 x2** -- previous 81 checks + surface create/SaveBMP/LoadBMP/destroy + window icon + native handle (Win32) + Vulkan CreateSurface typed rejection |
| Full surface (generated modules) | `xiom --run tests/test_full_surface.xi` with SDL3 on PATH | PASS: bound 1269/1269, resolved 1270/1270 exports (2026-10-14, unchanged by 0.19.0) |
| Device ABIs | generator audit + clang `x86_64-pc-windows-msvc` offsetof/sizeof probe against the pinned headers | 32/32 symbols, 45/45 constants, 14/14 layouts (2026-10-14) |
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
