# xiom.sdl3

SDL3 (Simple DirectMedia Layer 3) bindings for XIOM via a **dynamic loader**:
`sdl3_load()` resolves `SDL3.dll` at runtime and every call goes through
resolved function pointers. No link-time dependency, no vendored code, no
build flags -- and the conformance suite reports **SKIP** (green) when SDL3
is not installed.

> **Status:** `incubating` -- **0.22.0 window surface tier** (engine ask
> `REL-20261031-1423-engine-4`): **icon + surface** (`sdl3_set_window_icon`,
> `sdl3_load_bmp`, `sdl3_save_bmp`, `sdl3_create_surface`,
> `sdl3_destroy_surface`), **native window handle**
> (`sdl3_window_properties`, `sdl3_get_pointer_property`,
> `sdl3_get_number_property`, `sdl3_window_native_handle` ->
> `Sdl3NativeWindow` for Win32 HWND / X11 / Wayland / Cocoa), and an
> **SDL_Vulkan_CreateSurface wrapper** (`sdl3_vulkan_create_surface` with an
> owned 8-byte `sdl3_vulkan_surface_slot`, zeroed before the call).  The
> 0.21.0 A14 surface (window identity/geometry, typed focus/DPI routing,
> IME, clipboard + primary selection) stays live and is confirmed by the
> suite.  Additive over 0.21.0; SDL3 3.4.8 symbols only.  Suite **85/85 x2**
> with the official SDL 3.4.8 DLL + absent **9/9 x2** (decode/encode arms
> run without the DLL).  **0.22.0 published 2026-10-31** as single tag
> `xiom-sdl3/v0.22.0` (sha256 `cb78bdfe...`; registry latest verified).
> Previous: 0.21.0 A14 UI platform surface (engine ask
> `REL-20261021-1652-engine-5`); 0.20.0 callback direct handoff; 0.19.0
> device surface (joystick caps, haptic wave forms, pen/tablet decode);
> 0.18.0 foreign-written event
> readback (B-11 addendum retired on v0.64.4); 0.16.1 fixed the `SDL_WasInit`
> return width (B-19).  0.15.0 shipped in `eco-v0.1.151`; 0.16.0 in
> `eco-v0.1.152`; 0.16.1 in `eco-v0.1.160` (sha256 `f2d99b9e...`); 0.17.0
> published in `eco-v0.1.162` (sha256 `2f162d32...`); 0.18.0 in
> `eco-v0.1.173` (sha256 `544c59b8...`).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.sdl3;

fn main() {
  let l = sdl3_load();
  if !l.is_ok {
    io.println("SDL3 unavailable: " + l.error.message);  // SKIP in CI
    return;
  }
  let lib: Sdl3Library = l.value;
  if sdl3_init(&lib, SDL_INIT_TIMER | SDL_INIT_EVENTS) {
    sdl3_delay(&lib, 16);
    sdl3_pump_events(&lib);
    let had_event = sdl3_poll_event(&lib, 0);
    sdl3_quit(&lib);
  }
  let cl = sdl3_close(&lib);
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `sdl3_load`, `sdl3_close`, `Sdl3Library`, `Sdl3LoadError` |
| Lifecycle | `sdl3_init`, `sdl3_quit`, `sdl3_was_init` |
| Version | `sdl3_get_version`, `sdl3_get_revision`, `sdl3_versionnum`, `sdl3_version_major/minor/patch` |
| Timer | `sdl3_get_ticks`, `sdl3_get_performance_counter`, `sdl3_delay` |
| Events | `sdl3_pump_events`, `sdl3_poll_event`, `sdl3_push_event` |
| Event filter/watch (0.5.0; direct handoff 0.20.0) | `sdl3_set_event_filter(filter, userdata)` (return `1` to keep / `0` to drop), `sdl3_clear_event_filter`, `sdl3_add_event_watch(watch, userdata)`, `sdl3_remove_event_watch(watch, userdata)`, `sdl3_event_copy(event)` -- handlers take the natural `(userdata, event)` shape and copy the raw address into an owned buffer |
| Displays/keyboard (0.6.0) | `sdl3_display_count`, `sdl3_display_at`, `sdl3_primary_display`, `sdl3_display_name`, `sdl3_display_bounds`, `sdl3_display_usable_bounds`, `sdl3_display_mode`, `sdl3_desktop_display_mode` (`Sdl3Rect`/`Sdl3DisplayMode`), `sdl3_keyboard_state_count`, `sdl3_keyboard_key_down(scancode)`, `sdl3_mod_state`, `sdl3_keyboard_focus` -- all require SDL_INIT_VIDEO |
| Window identity/geometry (0.21.0) | `sdl3_window_id(win)`, `sdl3_window_from_id(id)`, `sdl3_window_position(win)` (`Sdl3WindowPosition`), `sdl3_set_window_position(win, x, y)`, `sdl3_window_size_pixels(win)` (`Sdl3PixelSize`), `sdl3_window_display_scale(win)`, `sdl3_window_display(win)`, `sdl3_display_index(id)`, `sdl3_display_content_scale(id)` -- resource-stage except the last two (core display enumeration) |
| Focus/DPI routing (0.21.0) | `sdl3_event_window_focus(ev)` (`Sdl3WindowFocus`: gained/lost + window id), `sdl3_event_is_focus_change`, `sdl3_event_dpi_change(ev)` (`Sdl3DpiChange`: pixel-size / display / display-scale), `sdl3_event_is_dpi_change`; `SDL3_WINDOW_FOCUS_*`, `SDL3_DPI_CHANGE_*` |
| Text input/IME (0.21.0) | `sdl3_start_text_input(win)`, `sdl3_stop_text_input(win)`, `sdl3_text_input_active(win)`, `sdl3_set_text_input_area(win, rect, cursor)`, `sdl3_get_text_input_area(win)` (`Sdl3TextInputArea` with cursor), `sdl3_clear_composition(win)`; decode: `sdl3_event_text_editing(ev)` (`Sdl3TextEditing`: preedit/start/length), `sdl3_event_text_input(ev)` (committed UTF-8), `sdl3_event_text_kind(ev)` -> `SDL3_TEXT_EVENT_EDITING/COMMIT/CANCELLED` (cancellation is SDL3's empty-preedit editing event) |
| Clipboard (0.21.0) | `sdl3_set_clipboard_text`, `sdl3_get_clipboard_text`, `sdl3_has_clipboard_text`, `sdl3_set_primary_selection_text`, `sdl3_get_primary_selection_text`, `sdl3_has_primary_selection_text` -- UTF-8; the primary-selection setter returns false + `SDL_GetError` where the platform has no primary selection (callers SKIP/fall back) |
| Surface/icon/native handle (0.22.0) | `sdl3_create_surface(w, h, format)` / `sdl3_destroy_surface`, `sdl3_load_bmp(path)` / `sdl3_save_bmp(surface, path)` (owned `SDL_Surface*` as `Int`), `sdl3_set_window_icon(win, surface)`; `sdl3_window_properties(win)`, `sdl3_get_pointer_property` / `sdl3_get_number_property`, `sdl3_window_native_handle(win)` (`Sdl3NativeWindow{ok,kind,handle}`; `SDL3_NATIVE_WINDOW_WIN32/X11/WAYLAND/COCOA/NONE`), `SDL_PROP_WINDOW_WIN32_HWND_POINTER` / `_X11_WINDOW_NUMBER` / `_WAYLAND_SURFACE_POINTER` / `_COCOA_WINDOW_POINTER`; `sdl3_vulkan_create_surface(win, instance, slot)` + `sdl3_vulkan_surface_slot()` / `sdl3_vulkan_surface_value(slot)` -- pass-through wrapper, the engine owns the `VkInstance` |
| Filesystem (0.7.0) | `sdl3_get_base_path` (SDL-owned, copied), `sdl3_get_pref_path(org, app)` + `sdl3_get_current_directory` (freed after copy), `sdl3_create_directory`, `sdl3_remove_path`, `sdl3_get_path_info` (`Sdl3PathInfo`; `SDL_PATHTYPE_*`) |
| Display blit (0.8.0) | `sdl3_update_texture(res, tex, pixels, w, h)` (RGBA8 upload from an XIOM buffer), `sdl3_render_texture(res, ren, tex)` (whole-texture blit), `sdl3_set_render_vsync(res, ren, vsync)` -- `SDL_TEXTUREACCESS_STREAMING` exported; clear -> update -> blit -> present is the minimal engine present path |
| Input/window contract (0.9.0) | `sdl3_mouse_state` (`Sdl3MouseState`: window-relative x/y + button mask), `sdl3_set_window_size`, `sdl3_set_window_resizable`, the full `SDL_EVENT_WINDOW_*` family (RESIZED/MOVED/PIXEL_SIZE_CHANGED/FOCUS_*/MINIMIZED/MAXIMIZED/RESTORED/SHOWN/HIDDEN/EXPOSED/CLOSE_REQUESTED) |
| Audio/joystick (0.10.0) | `sdl3_audio_playback_count/at`, `sdl3_audio_recording_count/at`, `sdl3_audio_device_name`, `sdl3_current_audio_driver` (requires `SDL_INIT_AUDIO`); `sdl3_joystick_count/at`, `sdl3_joystick_name_for_id` (requires `SDL_INIT_JOYSTICK`); constant `SDL_PIXELFORMAT_ABGR8888` |
| Audio stream (0.12.0) | `sdl3_open_audio_playback_stream(format, channels, freq)` (default device, NULL callback = push mode), `sdl3_put_audio_stream_data(stream, buf, len)`, `sdl3_resume/pause_audio_stream_device`, `sdl3_audio_stream_device_paused`, `sdl3_get_audio_stream_queued`, `sdl3_destroy_audio_stream`; `SDL_AUDIO_F32`, `SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK` |
| Audio capture (0.13.0) | `sdl3_open_audio_recording_stream(format, channels, freq)` (default recording device, NULL callback = pull mode; returns 0 -> SKIP), `sdl3_get_audio_stream_data(stream, buf, len)` (bytes read into an XIOM buffer), `sdl3_get_audio_stream_available`, `sdl3_clear_audio_stream`, `sdl3_get_audio_stream_format` (`Sdl3AudioStreamFormat`); `SDL_AUDIO_DEVICE_DEFAULT_RECORDING` |
| Pointer/relative mouse (0.14.0) | `sdl3_global_mouse_state`, `sdl3_relative_mouse_state` (`Sdl3MouseState`: x/y + button mask), `sdl3_set_window_relative_mouse_mode(win, enabled)` + `sdl3_window_relative_mouse_mode(win)` (per-window relative mode), `sdl3_capture_mouse(enabled)` -- require `SDL_INIT_VIDEO` |
| Joystick live path (0.15.0) | `sdl3_open_joystick(id)` / `sdl3_close_joystick`, `sdl3_joystick_connected`, `sdl3_joystick_name`, `sdl3_joystick_axis` (signed, -32768..32767), `sdl3_joystick_button`, `sdl3_set_joystick_virtual_axis/button`, `sdl3_attach_virtual_joystick(name, naxes, nbuttons)` / `sdl3_detach_virtual_joystick(id)` -- hardware-free instrumentation for the real read path |
| Joystick caps (0.19.0) | `sdl3_joystick_caps(joy)` (`Sdl3JoystickCaps`: axes/buttons/hats/balls + type + the five flags), `sdl3_joystick_has_rumble`, `sdl3_joystick_has_rumble_triggers`, `sdl3_joystick_has_mono_led`, `sdl3_joystick_has_rgb_led`, `sdl3_joystick_has_player_led`, `sdl3_joystick_num_axes/buttons/hats/balls`, `sdl3_joystick_type`, `sdl3_joystick_properties`, `sdl3_property_bool`/`sdl3_set_boolean_property`; `SDL_PROP_JOYSTICK_CAP_*`, `SDL_JOYSTICK_TYPE_*` -- SDL3 exposes caps as boolean strings on the joystick properties group (no `SDL_JoystickHasRumble` function in 3.4.8) |
| Haptic wave forms (0.19.0) | `sdl3_haptic_encode_periodic(slot, eff)` (validated `SDL_HapticPeriodic` encode, `SDL_HAPTIC_EFFECT_SIZE` = 72), `sdl3_haptic_create_periodic/update_periodic` -> typed `Sdl3HapticError` (`kind` = `SDL3_HAPTIC_ERR_PARAM/OPEN/CREATE/UPDATE/RUN/STOP` + `SDL_GetError` message), `sdl3_haptic_effect_supported`, `sdl3_haptic_run/status/stop/destroy`, `sdl3_haptic_count/at/from_id`, `sdl3_haptic_name/name_for_id`, `sdl3_haptic_open/close`, `sdl3_is_joystick_haptic`, `sdl3_open_haptic_from_joystick`, `sdl3_haptic_features`, `sdl3_haptic_max_effects/max_effects_playing/num_axes`, rumble: `sdl3_haptic_rumble_supported/init/play/stop`; `SDL_HAPTIC_SINE/SQUARE/TRIANGLE/SAWTOOTHUP/SAWTOOTHDOWN/POLAR/CARTESIAN/SPHERICAL/INFINITY` |
| Pen/tablet decode (0.19.0) | `sdl3_pen_device_type(id)` (`SDL_PEN_DEVICE_TYPE_*`; INVALID for unknown ids), pen event accessors: `sdl3_event_pen_window_id/_which/_state`, `sdl3_event_pen_x/_y` (+`_bits`), touch: `sdl3_event_pen_touch_eraser/_touch_down`, button: `sdl3_event_pen_button/_button_down`; `SDL_PEN_INPUT_*` flags |
| Drag-drop (0.16.0) | `sdl3_event_drop_window_id`, `sdl3_event_drop_x/_y`, `sdl3_event_drop_source/_data` (payload C-string copies; `""` when NULL), `sdl3_str_c_ptr` (build synthetic C structures); `SDL_EVENT_DROP_*` constants from the 0.11.0 tables |
| Mouse wheel (0.12.0) | `sdl3_event_wheel_x/_y` (+`_bits`), `sdl3_event_wheel_direction`, `sdl3_event_wheel_mouse_x/_y`; `SDL_MOUSEWHEEL_NORMAL/FLIPPED` |
| Event decode (0.4.0) | `sdl3_event_type`, `sdl3_event_timestamp`, `sdl3_event_window_id`, `sdl3_event_key_scancode/key_code/mods/down/repeat`, `sdl3_event_mouse_state/x_bits/y_bits/x/y/button/button_down/clicks`, `sdl3_event_window_data1/data2`, `sdl3_f32_from_bits`, `SDL_EVENT_SIZE` |
| Error | `sdl3_get_error` |
| Resources | `sdl3_load_resources`, `sdl3_resources_close`, `sdl3_create_window`, `sdl3_destroy_window`, `sdl3_show_window`, `sdl3_hide_window`, `sdl3_window_size`, `sdl3_set_window_title`, `sdl3_create_renderer`, `sdl3_destroy_renderer`, `sdl3_set_render_draw_color`, `sdl3_render_clear`, `sdl3_render_present`, `sdl3_create_texture`, `sdl3_destroy_texture`, `sdl3_has_gamepad`, `sdl3_gamepad_count`, `sdl3_open_gamepad`, `sdl3_close_gamepad` |
| Constants | `SDL_INIT_*`, `SDL_WINDOW_*`, `SDL_EVENT_*`, `SDL_PIXELFORMAT_RGBA8888`, `SDL_TEXTUREACCESS_*`, `SDL3_SONAME`, `SDL3_LOAD_*` |

Failure model: `sdl3_load` distinguishes **absent** (`kind =
SDL3_LOAD_ABSENT` -> callers SKIP) from **ABI mismatch** (`kind =
SDL3_LOAD_ABI` -> callers FAIL). Everything else is `Bool`/value returns
with contracts; no silent nulls.

Pointer discipline (**B-17**, v0.64.3): never pass pointer arithmetic
(`buf.as_mut_ptr() + N`) to a foreign call -- it compiles to a wild address.
Every out-param gets its own owned slot; address math, when unavoidable,
stays in `Int` (`(addr + N) as *UInt8`).

**Pixel-format naming (8888):** SDL names 32-bit formats MSB-first
(`SDL_PIXELFORMAT_RGBA8888` = R most significant). On little-endian memory
the byte order reverses: RGBA8888 lands as `A,B,G,R`; **`ABGR8888` is the
byte-order RGBA array** as produced by a plain RGBA8 framebuffer (pass it
to `sdl3_create_texture` for `sdl3_update_texture` uploads).

## Engine event loop (typed events via the watch)

SDL_Event data read back from a `SDL_PollEvent`-written buffer was corrupted
on v0.64.3 (B-11 family; retired at v0.64.4), and the watch route stays the
typed one: register an event watch once; each queued event arrives as its
raw address (valid only during the call) and is COPIED into an owned buffer
with `sdl3_event_copy(event)` for the 0.4.0 accessors. Handlers take the
natural `(userdata, event)` shape (direct handoff, 0.20.0). Drain the queue
by polling into an owned scratch buffer (`SDL_PollEvent(NULL)` is only a
peek on 3.4.8).

```xiom
use xiom.io;
use xiom.sdl3;

var running: Bool = true;

fn on_event(userdata: Int, event: Int) -> Unit {
  let ev = sdl3_event_copy(event);
  let t = sdl3_event_type(&ev);
  if t == SDL_EVENT_QUIT { running = false; }
  if t == SDL_EVENT_WINDOW_CLOSE_REQUESTED { running = false; }
  if t == SDL_EVENT_WINDOW_RESIZED {
    io.println("resize " + to_string(sdl3_event_window_data1(&ev))
      + "x" + to_string(sdl3_event_window_data2(&ev)));
  }
  // Per-window focus (0.21.0): gained/lost + window id.
  let focus = sdl3_event_window_focus(&ev);
  if focus.state != SDL3_WINDOW_FOCUS_NONE {
    io.println("focus window " + to_string(focus.window_id)
      + " state " + to_string(focus.state));
  }
  // DPI-change routing (0.21.0): pixel size / display / display scale.
  let dpi = sdl3_event_dpi_change(&ev);
  if dpi.reason != SDL3_DPI_CHANGE_NONE {
    io.println("dpi change reason " + to_string(dpi.reason));
  }
  // IME (0.21.0): preedit, commit, and typed cancellation.
  let tk = sdl3_event_text_kind(&ev);
  if tk == SDL3_TEXT_EVENT_COMMIT { io.println("text " + sdl3_event_text_input(&ev)); }
  if tk == SDL3_TEXT_EVENT_EDITING {
    let te = sdl3_event_text_editing(&ev);
    io.println("preedit " + te.text);
  }
}

fn run(lib: &Sdl3Library) {
  let w = sdl3_add_event_watch(lib, on_event, 0);
  while running {
    sdl3_pump_events(lib);
    // drain: poll into an owned 128-byte buffer until it reports false
    // frame: engine render -> sdl3_update_texture -> sdl3_render_texture -> present
  }
  let removed = sdl3_remove_event_watch(lib, on_event, 0);
}
```

## Runtime requirements

Put `SDL3.dll` (3.4.x) on the loader search path: next to the executable or
anywhere on `PATH`. G2 pin (soname + header-set manifest hash): `SPEC.md` §2.

## Tests

```
xiom --run tests/test_conformance.xi
```

- With SDL3: 85 `[PASS]` (decode layers incl. pen/tablet + drag-drop +
  haptic encode, smoke + hidden window, renderer clear/present, textures,
  gamepad enumeration, synthetic event injection incl. a PEN_MOTION
  readback, filter keep/drop + watch semantics, displays + keyboard,
  filesystem round trip, 64x64 RGBA blit, window resize typed event +
  mouse, joystick live path + caps queries, audio/joystick enumeration,
  7680 B silent push stream, haptic enumeration + typed errors, window
  identity/position/pixels/display scale + display index, IME
  start/area/cursor/stop, focus + DPI + IME routing through the watch,
  clipboard + primary-selection round trips, surface create/SaveBMP/
  LoadBMP/destroy round trip, window icon, Win32/X11/Wayland/Cocoa native
  handle, Vulkan CreateSurface typed rejection), exit 0 (~15 s).
- Without SDL3: the loader smoke reports explicit `SKIP` labels and stays
  green (9 markers); the decode/encode + UI-decode arms run in both shapes
  (pure XIOM; no DLL needed).

Queue semantics note (0.19.0 correction): `SDL_PollEvent(NULL)` on the
pinned 3.4.8 runtime REPORTS a pending event but does not consume it (it
only clears SDL's internal poll sentinel); and a poll that meets that
sentinel returns false with events still queued behind it. Draining
therefore polls into an owned scratch buffer, and checks that expect a
pushed event match on its type for a bounded number of polls (the suite's
`drain_events`/`poll_for` helpers).

On the dev box (`C:\VulkanSDK\1.4.350.0\Bin` on PATH) the live shape is
exercised with a hidden window; filtering that directory off PATH reproduces
the absent shape (9/9 green, explicit SKIP labels).

Full matrix + re-pin procedure: `SPEC.md` §4/§2. The full constant tables,
texture updates/vsync and the POSIX soname remain (`ROADMAP.md`).
