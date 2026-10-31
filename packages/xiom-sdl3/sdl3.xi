// XIOM -- xiom.sdl3: SDL3 (Simple DirectMedia Layer 3) bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader path (pilot). The package does NOT link against SDL3
// at build time. `sdl3_load` resolves SDL3.dll through `xiom.ffi.dl` at
// runtime (LoadLibraryA/GetProcAddress shims built into the XIOM runtime) and
// every call goes through fn-pointer casts inside this module -- the ONLY
// module in the package that contains `unsafe`. When SDL3.dll is absent the
// suite reports SKIP, so CI without the SDK stays green.
//
// G2 pin (SPEC.md): soname `SDL3.dll`; upstream tag release-3.4.8 header set
// (SDL.h, SDL_version.h, SDL_init.h, SDL_timer.h, SDL_events.h, SDL_error.h,
// SDL_stdinc.h) hashed in SPEC.md §2.
//
// Coverage: init / quit / was_init, version + revision, ticks + performance
// counter, delay, pump/poll/push events, error string; resource stage (window,
// renderer, texture, gamepad enumeration); 0.4.0 adds SDL_Event decoding from
// an owned 128-byte buffer with typed accessors (offsets pinned to the
// release-3.4.8 header; verified byte-identical in the release-3.2.10 clone);
// 0.13.0 adds capture streams (default recording device + GetAudioStreamData
// /available/clear/format); 0.14.0 adds pointer capture + per-window relative
// mouse + global/relative mouse state; 0.15.0 adds the joystick open/read
// surface (virtual-joystick instrumented); 0.16.0 adds drag-drop payload
// decode (SDL_DropEvent, DLL-independent); 0.19.0 adds joystick caps
// (properties flags + num-getters/type), the haptic wave-form surface
// (periodic encode + create/update/run/stop with typed errors) and the
// pen/tablet decode path (motion/touch/button/proximity + tool-type query).
// The full pre-pilot constant tables stay in git history (ROADMAP.md).

module xiom.sdl3

use xiom.ffi;
use xiom.ffi.dl;

// =========================================================================
// Library identity and init flags
// =========================================================================

/// Runtime library name resolved by the loader (Windows soname).
pub const SDL3_SONAME: Str = "SDL3.dll";

pub const SDL_INIT_TIMER: Int = 0x00000001;
pub const SDL_INIT_AUDIO: Int = 0x00000010;
pub const SDL_INIT_VIDEO: Int = 0x00000020;
pub const SDL_INIT_JOYSTICK: Int = 0x00000200;
pub const SDL_INIT_HAPTIC: Int = 0x00001000;
pub const SDL_INIT_GAMEPAD: Int = 0x00002000;
pub const SDL_INIT_EVENTS: Int = 0x00004000;
pub const SDL_INIT_SENSOR: Int = 0x00008000;
pub const SDL_INIT_CAMERA: Int = 0x00010000;

// A small, verified subset of the window/event constant tables (the full
// pre-pilot tables are in git history; they return with Phase 2 resources).
pub const SDL_WINDOW_FULLSCREEN: Int = 0x0000000000000001;
pub const SDL_WINDOW_OPENGL: Int = 0x0000000000000002;
pub const SDL_WINDOW_HIDDEN: Int = 0x0000000000000008;
pub const SDL_WINDOW_RESIZABLE: Int = 0x0000000000000020;
pub const SDL_WINDOW_VULKAN: Int = 0x0000000010000000;
pub const SDL_EVENT_QUIT: Int = 0x100;
pub const SDL_EVENT_KEY_DOWN: Int = 0x300;
pub const SDL_EVENT_KEY_UP: Int = 0x301;
pub const SDL_EVENT_TEXT_INPUT: Int = 0x303;
// Window-event family (sequential from 0x202 per the pinned header).
pub const SDL_EVENT_WINDOW_SHOWN: Int = 0x202;
pub const SDL_EVENT_WINDOW_HIDDEN: Int = 0x203;
pub const SDL_EVENT_WINDOW_EXPOSED: Int = 0x204;
pub const SDL_EVENT_WINDOW_MOVED: Int = 0x205;
pub const SDL_EVENT_WINDOW_RESIZED: Int = 0x206;
pub const SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED: Int = 0x207;
pub const SDL_EVENT_WINDOW_MINIMIZED: Int = 0x209;
pub const SDL_EVENT_WINDOW_MAXIMIZED: Int = 0x20A;
pub const SDL_EVENT_WINDOW_RESTORED: Int = 0x20B;
pub const SDL_EVENT_WINDOW_MOUSE_ENTER: Int = 0x20C;
pub const SDL_EVENT_WINDOW_MOUSE_LEAVE: Int = 0x20D;
pub const SDL_EVENT_WINDOW_FOCUS_GAINED: Int = 0x20E;
pub const SDL_EVENT_WINDOW_FOCUS_LOST: Int = 0x20F;
pub const SDL_EVENT_WINDOW_CLOSE_REQUESTED: Int = 0x210;
pub const SDL_EVENT_MOUSE_MOTION: Int = 0x400;
pub const SDL_EVENT_MOUSE_BUTTON_DOWN: Int = 0x401;
pub const SDL_EVENT_MOUSE_BUTTON_UP: Int = 0x402;
pub const SDL_EVENT_MOUSE_WHEEL: Int = 0x403;
pub const SDL_EVENT_USER: Int = 0x8000;

// SDL_Scancode examples (USB-HID; pinned from the release-3.4.8 header).
pub const SDL_SCANCODE_A: Int = 4;
pub const SDL_SCANCODE_ESCAPE: Int = 41;
pub const SDL_SCANCODE_SPACE: Int = 44;

// =========================================================================
// 0.11.0: full constant tables -- source-generated from the release-3.2.10
// headers (values verified against the pinned release-3.4.8 semantics);
// names already defined above are not repeated.  Regenerate with the same
// enum-parse approach whenever the pin moves.
// =========================================================================

// ---- full event types (source-generated from the release-3.2.10 SDL_events.h enum) ----
pub const SDL_EVENT_FIRST: Int = 0;
pub const SDL_EVENT_TERMINATING: Int = 257;
pub const SDL_EVENT_LOW_MEMORY: Int = 258;
pub const SDL_EVENT_WILL_ENTER_BACKGROUND: Int = 259;
pub const SDL_EVENT_DID_ENTER_BACKGROUND: Int = 260;
pub const SDL_EVENT_WILL_ENTER_FOREGROUND: Int = 261;
pub const SDL_EVENT_DID_ENTER_FOREGROUND: Int = 262;
pub const SDL_EVENT_LOCALE_CHANGED: Int = 263;
pub const SDL_EVENT_SYSTEM_THEME_CHANGED: Int = 264;
pub const SDL_EVENT_DISPLAY_ORIENTATION: Int = 337;
pub const SDL_EVENT_DISPLAY_ADDED: Int = 338;
pub const SDL_EVENT_DISPLAY_REMOVED: Int = 339;
pub const SDL_EVENT_DISPLAY_MOVED: Int = 340;
pub const SDL_EVENT_DISPLAY_DESKTOP_MODE_CHANGED: Int = 341;
pub const SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED: Int = 342;
pub const SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED: Int = 343;
pub const SDL_EVENT_WINDOW_METAL_VIEW_RESIZED: Int = 520;
pub const SDL_EVENT_WINDOW_HIT_TEST: Int = 529;
pub const SDL_EVENT_WINDOW_ICCPROF_CHANGED: Int = 530;
pub const SDL_EVENT_WINDOW_DISPLAY_CHANGED: Int = 531;
pub const SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED: Int = 532;
pub const SDL_EVENT_WINDOW_SAFE_AREA_CHANGED: Int = 533;
pub const SDL_EVENT_WINDOW_OCCLUDED: Int = 534;
pub const SDL_EVENT_WINDOW_ENTER_FULLSCREEN: Int = 535;
pub const SDL_EVENT_WINDOW_LEAVE_FULLSCREEN: Int = 536;
pub const SDL_EVENT_WINDOW_DESTROYED: Int = 537;
pub const SDL_EVENT_WINDOW_HDR_STATE_CHANGED: Int = 538;
pub const SDL_EVENT_TEXT_EDITING: Int = 770;
pub const SDL_EVENT_KEYMAP_CHANGED: Int = 772;
pub const SDL_EVENT_KEYBOARD_ADDED: Int = 773;
pub const SDL_EVENT_KEYBOARD_REMOVED: Int = 774;
pub const SDL_EVENT_TEXT_EDITING_CANDIDATES: Int = 775;
pub const SDL_EVENT_MOUSE_ADDED: Int = 1028;
pub const SDL_EVENT_MOUSE_REMOVED: Int = 1029;
pub const SDL_EVENT_JOYSTICK_AXIS_MOTION: Int = 1536;
pub const SDL_EVENT_JOYSTICK_BALL_MOTION: Int = 1537;
pub const SDL_EVENT_JOYSTICK_HAT_MOTION: Int = 1538;
pub const SDL_EVENT_JOYSTICK_BUTTON_DOWN: Int = 1539;
pub const SDL_EVENT_JOYSTICK_BUTTON_UP: Int = 1540;
pub const SDL_EVENT_JOYSTICK_ADDED: Int = 1541;
pub const SDL_EVENT_JOYSTICK_REMOVED: Int = 1542;
pub const SDL_EVENT_JOYSTICK_BATTERY_UPDATED: Int = 1543;
pub const SDL_EVENT_JOYSTICK_UPDATE_COMPLETE: Int = 1544;
pub const SDL_EVENT_GAMEPAD_AXIS_MOTION: Int = 1616;
pub const SDL_EVENT_GAMEPAD_BUTTON_DOWN: Int = 1617;
pub const SDL_EVENT_GAMEPAD_BUTTON_UP: Int = 1618;
pub const SDL_EVENT_GAMEPAD_ADDED: Int = 1619;
pub const SDL_EVENT_GAMEPAD_REMOVED: Int = 1620;
pub const SDL_EVENT_GAMEPAD_REMAPPED: Int = 1621;
pub const SDL_EVENT_GAMEPAD_TOUCHPAD_DOWN: Int = 1622;
pub const SDL_EVENT_GAMEPAD_TOUCHPAD_MOTION: Int = 1623;
pub const SDL_EVENT_GAMEPAD_TOUCHPAD_UP: Int = 1624;
pub const SDL_EVENT_GAMEPAD_SENSOR_UPDATE: Int = 1625;
pub const SDL_EVENT_GAMEPAD_UPDATE_COMPLETE: Int = 1626;
pub const SDL_EVENT_GAMEPAD_STEAM_HANDLE_UPDATED: Int = 1627;
pub const SDL_EVENT_FINGER_DOWN: Int = 1792;
pub const SDL_EVENT_FINGER_UP: Int = 1793;
pub const SDL_EVENT_FINGER_MOTION: Int = 1794;
pub const SDL_EVENT_FINGER_CANCELED: Int = 1795;
pub const SDL_EVENT_CLIPBOARD_UPDATE: Int = 2304;
pub const SDL_EVENT_DROP_FILE: Int = 4096;
pub const SDL_EVENT_DROP_TEXT: Int = 4097;
pub const SDL_EVENT_DROP_BEGIN: Int = 4098;
pub const SDL_EVENT_DROP_COMPLETE: Int = 4099;
pub const SDL_EVENT_DROP_POSITION: Int = 4100;
pub const SDL_EVENT_AUDIO_DEVICE_ADDED: Int = 4352;
pub const SDL_EVENT_AUDIO_DEVICE_REMOVED: Int = 4353;
pub const SDL_EVENT_AUDIO_DEVICE_FORMAT_CHANGED: Int = 4354;
pub const SDL_EVENT_SENSOR_UPDATE: Int = 4608;
pub const SDL_EVENT_PEN_PROXIMITY_IN: Int = 4864;
pub const SDL_EVENT_PEN_PROXIMITY_OUT: Int = 4865;
pub const SDL_EVENT_PEN_DOWN: Int = 4866;
pub const SDL_EVENT_PEN_UP: Int = 4867;
pub const SDL_EVENT_PEN_BUTTON_DOWN: Int = 4868;
pub const SDL_EVENT_PEN_BUTTON_UP: Int = 4869;
pub const SDL_EVENT_PEN_MOTION: Int = 4870;
pub const SDL_EVENT_PEN_AXIS: Int = 4871;
pub const SDL_EVENT_CAMERA_DEVICE_ADDED: Int = 5120;
pub const SDL_EVENT_CAMERA_DEVICE_REMOVED: Int = 5121;
pub const SDL_EVENT_CAMERA_DEVICE_APPROVED: Int = 5122;
pub const SDL_EVENT_CAMERA_DEVICE_DENIED: Int = 5123;
pub const SDL_EVENT_RENDER_TARGETS_RESET: Int = 8192;
pub const SDL_EVENT_RENDER_DEVICE_RESET: Int = 8193;
pub const SDL_EVENT_RENDER_DEVICE_LOST: Int = 8194;
pub const SDL_EVENT_PRIVATE0: Int = 16384;
pub const SDL_EVENT_PRIVATE1: Int = 16385;
pub const SDL_EVENT_PRIVATE2: Int = 16386;
pub const SDL_EVENT_PRIVATE3: Int = 16387;
pub const SDL_EVENT_POLL_SENTINEL: Int = 32512;
pub const SDL_EVENT_LAST: Int = 65535;

// ---- window flags (SDL_video.h) ----
pub const SDL_WINDOW_FULLSCREEN: Int = 1;
pub const SDL_WINDOW_OPENGL: Int = 2;
pub const SDL_WINDOW_OCCLUDED: Int = 4;
pub const SDL_WINDOW_BORDERLESS: Int = 16;
pub const SDL_WINDOW_RESIZABLE: Int = 32;
pub const SDL_WINDOW_MINIMIZED: Int = 64;
pub const SDL_WINDOW_MAXIMIZED: Int = 128;
pub const SDL_WINDOW_MOUSE_GRABBED: Int = 256;
pub const SDL_WINDOW_INPUT_FOCUS: Int = 512;
pub const SDL_WINDOW_MOUSE_FOCUS: Int = 1024;
pub const SDL_WINDOW_EXTERNAL: Int = 2048;
pub const SDL_WINDOW_MODAL: Int = 4096;
pub const SDL_WINDOW_HIGH_PIXEL_DENSITY: Int = 8192;
pub const SDL_WINDOW_MOUSE_CAPTURE: Int = 16384;
pub const SDL_WINDOW_MOUSE_RELATIVE_MODE: Int = 32768;
pub const SDL_WINDOW_ALWAYS_ON_TOP: Int = 65536;
pub const SDL_WINDOW_UTILITY: Int = 131072;
pub const SDL_WINDOW_TOOLTIP: Int = 262144;
pub const SDL_WINDOW_POPUP_MENU: Int = 524288;
pub const SDL_WINDOW_KEYBOARD_GRABBED: Int = 1048576;
pub const SDL_WINDOW_METAL: Int = 536870912;
pub const SDL_WINDOW_TRANSPARENT: Int = 1073741824;
pub const SDL_WINDOW_NOT_FOCUSABLE: Int = 2147483648;

// ---- key modifiers (SDL_keycode.h) ----
pub const SDL_KMOD_NONE: Int = 0;
pub const SDL_KMOD_LSHIFT: Int = 1;
pub const SDL_KMOD_RSHIFT: Int = 2;
pub const SDL_KMOD_LEVEL5: Int = 4;
pub const SDL_KMOD_LCTRL: Int = 64;
pub const SDL_KMOD_RCTRL: Int = 128;
pub const SDL_KMOD_LALT: Int = 256;
pub const SDL_KMOD_RALT: Int = 512;
pub const SDL_KMOD_LGUI: Int = 1024;
pub const SDL_KMOD_RGUI: Int = 2048;
pub const SDL_KMOD_NUM: Int = 4096;
pub const SDL_KMOD_CAPS: Int = 8192;
pub const SDL_KMOD_MODE: Int = 16384;
pub const SDL_KMOD_SCROLL: Int = 32768;

// ---- pixel formats with explicit values (SDL_pixels.h) ----
pub const SDL_PIXELFORMAT_INDEX1LSB: Int = 286261504;
pub const SDL_PIXELFORMAT_INDEX1MSB: Int = 287310080;
pub const SDL_PIXELFORMAT_INDEX2LSB: Int = 470811136;
pub const SDL_PIXELFORMAT_INDEX2MSB: Int = 471859712;
pub const SDL_PIXELFORMAT_INDEX4LSB: Int = 303039488;
pub const SDL_PIXELFORMAT_INDEX4MSB: Int = 304088064;
pub const SDL_PIXELFORMAT_INDEX8: Int = 318769153;
pub const SDL_PIXELFORMAT_RGB332: Int = 336660481;
pub const SDL_PIXELFORMAT_XRGB4444: Int = 353504258;
pub const SDL_PIXELFORMAT_XBGR4444: Int = 357698562;
pub const SDL_PIXELFORMAT_XRGB1555: Int = 353570562;
pub const SDL_PIXELFORMAT_XBGR1555: Int = 357764866;
pub const SDL_PIXELFORMAT_ARGB4444: Int = 355602434;
pub const SDL_PIXELFORMAT_RGBA4444: Int = 356651010;
pub const SDL_PIXELFORMAT_ABGR4444: Int = 359796738;
pub const SDL_PIXELFORMAT_BGRA4444: Int = 360845314;
pub const SDL_PIXELFORMAT_ARGB1555: Int = 355667970;
pub const SDL_PIXELFORMAT_RGBA5551: Int = 356782082;
pub const SDL_PIXELFORMAT_ABGR1555: Int = 359862274;
pub const SDL_PIXELFORMAT_BGRA5551: Int = 360976386;
pub const SDL_PIXELFORMAT_RGB565: Int = 353701890;
pub const SDL_PIXELFORMAT_BGR565: Int = 357896194;
pub const SDL_PIXELFORMAT_RGB24: Int = 386930691;
pub const SDL_PIXELFORMAT_BGR24: Int = 390076419;
pub const SDL_PIXELFORMAT_XRGB8888: Int = 370546692;
pub const SDL_PIXELFORMAT_RGBX8888: Int = 371595268;
pub const SDL_PIXELFORMAT_XBGR8888: Int = 374740996;
pub const SDL_PIXELFORMAT_BGRX8888: Int = 375789572;
pub const SDL_PIXELFORMAT_ARGB8888: Int = 372645892;
pub const SDL_PIXELFORMAT_BGRA8888: Int = 377888772;
pub const SDL_PIXELFORMAT_XRGB2101010: Int = 370614276;
pub const SDL_PIXELFORMAT_XBGR2101010: Int = 374808580;
pub const SDL_PIXELFORMAT_ARGB2101010: Int = 372711428;
pub const SDL_PIXELFORMAT_ABGR2101010: Int = 376905732;
pub const SDL_PIXELFORMAT_RGB48: Int = 403714054;
pub const SDL_PIXELFORMAT_BGR48: Int = 406859782;
pub const SDL_PIXELFORMAT_RGBA64: Int = 404766728;
pub const SDL_PIXELFORMAT_ARGB64: Int = 405815304;
pub const SDL_PIXELFORMAT_BGRA64: Int = 407912456;
pub const SDL_PIXELFORMAT_ABGR64: Int = 408961032;
pub const SDL_PIXELFORMAT_RGB48_FLOAT: Int = 437268486;
pub const SDL_PIXELFORMAT_BGR48_FLOAT: Int = 440414214;
pub const SDL_PIXELFORMAT_RGBA64_FLOAT: Int = 438321160;
pub const SDL_PIXELFORMAT_ARGB64_FLOAT: Int = 439369736;
pub const SDL_PIXELFORMAT_BGRA64_FLOAT: Int = 441466888;
pub const SDL_PIXELFORMAT_ABGR64_FLOAT: Int = 442515464;
pub const SDL_PIXELFORMAT_RGB96_FLOAT: Int = 454057996;
pub const SDL_PIXELFORMAT_BGR96_FLOAT: Int = 457203724;
pub const SDL_PIXELFORMAT_RGBA128_FLOAT: Int = 455114768;
pub const SDL_PIXELFORMAT_ARGB128_FLOAT: Int = 456163344;
pub const SDL_PIXELFORMAT_BGRA128_FLOAT: Int = 458260496;
pub const SDL_PIXELFORMAT_ABGR128_FLOAT: Int = 459309072;
pub const SDL_PIXELFORMAT_YV12: Int = 842094169;
pub const SDL_PIXELFORMAT_IYUV: Int = 1448433993;
pub const SDL_PIXELFORMAT_YUY2: Int = 844715353;
pub const SDL_PIXELFORMAT_UYVY: Int = 1498831189;
pub const SDL_PIXELFORMAT_YVYU: Int = 1431918169;
pub const SDL_PIXELFORMAT_NV12: Int = 842094158;
pub const SDL_PIXELFORMAT_NV21: Int = 825382478;
pub const SDL_PIXELFORMAT_P010: Int = 808530000;
pub const SDL_PIXELFORMAT_EXTERNAL_OES: Int = 542328143;
pub const SDL_PIXELFORMAT_MJPG: Int = 1196444237;

/// SDL_VERSIONNUM(major, minor, patch) as returned by SDL_GetVersion.
/// Complexity: O(1).
pub fn sdl3_versionnum(major: Int, minor: Int, patch: Int) -> Int
  requires: major > 0
  requires: minor >= 0
  requires: patch >= 0
{
  return major * 1000000 + minor * 1000 + patch;
}

/// Major component of an SDL_VERSIONNUM value.
/// Complexity: O(1).
pub fn sdl3_version_major(version: Int) -> Int
  requires: version >= 0
{
  return version / 1000000;
}

/// Minor component of an SDL_VERSIONNUM value.
/// Complexity: O(1).
pub fn sdl3_version_minor(version: Int) -> Int
  requires: version >= 0
{
  return (version % 1000000) / 1000;
}

/// Patch component of an SDL_VERSIONNUM value.
/// Complexity: O(1).
pub fn sdl3_version_patch(version: Int) -> Int
  requires: version >= 0
{
  return version % 1000;
}

// =========================================================================
// Loader
// =========================================================================

/// Failure modes of `sdl3_load`, distinguishing "library absent" (callers
/// report SKIP) from "library present but ABI symbols missing" (callers
/// report FAIL -- a real install/SDK mismatch).
pub const SDL3_LOAD_ABSENT: Int = 0;
pub const SDL3_LOAD_ABI: Int = 1;

pub type Sdl3LoadError = {
  kind: Int;
  message: Str;
}

/// A loaded SDL3 library.  `handle` is the dl handle; the `p_*` fields are
/// resolved symbol addresses.  Owned by the caller; release with `sdl3_close`.
pub type Sdl3Library = {
  handle: Int;
  p_init: Int;
  p_quit: Int;
  p_was_init: Int;
  p_get_version: Int;
  p_get_revision: Int;
  p_get_ticks: Int;
  p_get_performance_counter: Int;
  p_delay: Int;
  p_pump_events: Int;
  p_poll_event: Int;
  p_push_event: Int;
  p_get_error: Int;
  p_set_event_filter: Int;
  p_add_event_watch: Int;
  p_remove_event_watch: Int;
  p_get_displays: Int;
  p_get_primary_display: Int;
  p_get_display_name: Int;
  p_get_display_bounds: Int;
  p_get_display_usable_bounds: Int;
  p_get_current_display_mode: Int;
  p_get_desktop_display_mode: Int;
  p_get_keyboard_state: Int;
  p_get_mod_state: Int;
  p_get_keyboard_focus: Int;
  p_free: Int;
  p_get_base_path: Int;
  p_get_pref_path: Int;
  p_get_current_directory: Int;
  p_create_directory: Int;
  p_remove_path: Int;
  p_get_path_info: Int;
  p_get_mouse_state: Int;
  p_get_audio_playback_devices: Int;
  p_get_audio_recording_devices: Int;
  p_get_audio_device_name: Int;
  p_get_current_audio_driver: Int;
  p_get_joysticks: Int;
  p_get_joystick_name_for_id: Int;
  p_open_audio_device_stream: Int;
  p_put_audio_stream_data: Int;
  p_resume_audio_stream_device: Int;
  p_pause_audio_stream_device: Int;
  p_destroy_audio_stream: Int;
  p_get_audio_stream_queued: Int;
  p_audio_stream_device_paused: Int;
  p_get_audio_stream_data: Int;
  p_get_audio_stream_available: Int;
  p_clear_audio_stream: Int;
  p_get_audio_stream_format: Int;
  p_get_global_mouse_state: Int;
  p_get_relative_mouse_state: Int;
  p_set_window_relative_mouse_mode: Int;
  p_get_window_relative_mouse_mode: Int;
  p_capture_mouse: Int;
  p_open_joystick: Int;
  p_close_joystick: Int;
  p_joystick_connected: Int;
  p_joystick_name: Int;
  p_joystick_axis: Int;
  p_joystick_button: Int;
  p_set_joystick_virtual_axis: Int;
  p_set_joystick_virtual_button: Int;
  p_attach_virtual_joystick: Int;
  p_detach_virtual_joystick: Int;
  p_get_joystick_properties: Int;
  p_get_boolean_property: Int;
  p_set_boolean_property: Int;
  p_get_num_joystick_axes: Int;
  p_get_num_joystick_buttons: Int;
  p_get_num_joystick_hats: Int;
  p_get_num_joystick_balls: Int;
  p_get_joystick_type: Int;
  p_get_haptics: Int;
  p_get_haptic_from_id: Int;
  p_get_haptic_name: Int;
  p_get_haptic_name_for_id: Int;
  p_open_haptic: Int;
  p_close_haptic: Int;
  p_is_joystick_haptic: Int;
  p_open_haptic_from_joystick: Int;
  p_get_haptic_features: Int;
  p_get_max_haptic_effects: Int;
  p_get_max_haptic_effects_playing: Int;
  p_get_num_haptic_axes: Int;
  p_haptic_effect_supported: Int;
  p_create_haptic_effect: Int;
  p_update_haptic_effect: Int;
  p_run_haptic_effect: Int;
  p_stop_haptic_effect: Int;
  p_destroy_haptic_effect: Int;
  p_get_haptic_effect_status: Int;
  p_haptic_rumble_supported: Int;
  p_init_haptic_rumble: Int;
  p_play_haptic_rumble: Int;
  p_stop_haptic_rumble: Int;
  p_get_pen_device_type: Int;
  p_get_display_content_scale: Int;
  p_set_clipboard_text: Int;
  p_get_clipboard_text: Int;
  p_has_clipboard_text: Int;
  p_set_primary_selection_text: Int;
  p_get_primary_selection_text: Int;
  p_has_primary_selection_text: Int;
  p_load_bmp: Int;
  p_save_bmp: Int;
  p_create_surface: Int;
  p_destroy_surface: Int;
}

/// Load SDL3.dll and resolve the smoke API.  Err(kind=SDL3_LOAD_ABSENT) when
/// the library cannot be loaded; Err(kind=SDL3_LOAD_ABI) when it loads but a
/// symbol is missing (nothing is leaked: the handle is closed on failure).
/// Complexity: O(symbols).
pub fn sdl3_load() -> Result[Sdl3Library, Sdl3LoadError] {
  let h = dl.dl_open(SDL3_SONAME);
  if !h.is_ok {
    return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;

  let a1 = dl.dl_sym(handle, "SDL_Init");
  if !a1.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_Init: " + a1.error }); }
  let a2 = dl.dl_sym(handle, "SDL_Quit");
  if !a2.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_Quit: " + a2.error }); }
  let a3 = dl.dl_sym(handle, "SDL_WasInit");
  if !a3.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_WasInit: " + a3.error }); }
  let a4 = dl.dl_sym(handle, "SDL_GetVersion");
  if !a4.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetVersion: " + a4.error }); }
  let a5 = dl.dl_sym(handle, "SDL_GetRevision");
  if !a5.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetRevision: " + a5.error }); }
  let a6 = dl.dl_sym(handle, "SDL_GetTicks");
  if !a6.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetTicks: " + a6.error }); }
  let a7 = dl.dl_sym(handle, "SDL_GetPerformanceCounter");
  if !a7.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetPerformanceCounter: " + a7.error }); }
  let a8 = dl.dl_sym(handle, "SDL_Delay");
  if !a8.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_Delay: " + a8.error }); }
  let a9 = dl.dl_sym(handle, "SDL_PumpEvents");
  if !a9.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_PumpEvents: " + a9.error }); }
  let a10 = dl.dl_sym(handle, "SDL_PollEvent");
  if !a10.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_PollEvent: " + a10.error }); }
  let a11 = dl.dl_sym(handle, "SDL_GetError");
  if !a11.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetError: " + a11.error }); }
  let a12 = dl.dl_sym(handle, "SDL_PushEvent");
  if !a12.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_PushEvent: " + a12.error }); }
  let a13 = dl.dl_sym(handle, "SDL_SetEventFilter");
  if !a13.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetEventFilter: " + a13.error }); }
  let a14 = dl.dl_sym(handle, "SDL_AddEventWatch");
  if !a14.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_AddEventWatch: " + a14.error }); }
  let a15 = dl.dl_sym(handle, "SDL_RemoveEventWatch");
  if !a15.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_RemoveEventWatch: " + a15.error }); }
  let a16 = dl.dl_sym(handle, "SDL_GetDisplays");
  if !a16.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetDisplays: " + a16.error }); }
  let a17 = dl.dl_sym(handle, "SDL_GetPrimaryDisplay");
  if !a17.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetPrimaryDisplay: " + a17.error }); }
  let a18 = dl.dl_sym(handle, "SDL_GetDisplayName");
  if !a18.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetDisplayName: " + a18.error }); }
  let a19 = dl.dl_sym(handle, "SDL_GetDisplayBounds");
  if !a19.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetDisplayBounds: " + a19.error }); }
  let a20 = dl.dl_sym(handle, "SDL_GetDisplayUsableBounds");
  if !a20.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetDisplayUsableBounds: " + a20.error }); }
  let a21 = dl.dl_sym(handle, "SDL_GetCurrentDisplayMode");
  if !a21.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetCurrentDisplayMode: " + a21.error }); }
  let a22 = dl.dl_sym(handle, "SDL_GetDesktopDisplayMode");
  if !a22.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetDesktopDisplayMode: " + a22.error }); }
  let a23 = dl.dl_sym(handle, "SDL_GetKeyboardState");
  if !a23.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetKeyboardState: " + a23.error }); }
  let a24 = dl.dl_sym(handle, "SDL_GetModState");
  if !a24.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetModState: " + a24.error }); }
  let a25 = dl.dl_sym(handle, "SDL_GetKeyboardFocus");
  if !a25.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetKeyboardFocus: " + a25.error }); }
  let a26 = dl.dl_sym(handle, "SDL_free");
  if !a26.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_free: " + a26.error }); }
  let a27 = dl.dl_sym(handle, "SDL_GetBasePath");
  if !a27.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetBasePath: " + a27.error }); }
  let a28 = dl.dl_sym(handle, "SDL_GetPrefPath");
  if !a28.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetPrefPath: " + a28.error }); }
  let a29 = dl.dl_sym(handle, "SDL_GetCurrentDirectory");
  if !a29.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetCurrentDirectory: " + a29.error }); }
  let a30 = dl.dl_sym(handle, "SDL_CreateDirectory");
  if !a30.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_CreateDirectory: " + a30.error }); }
  let a31 = dl.dl_sym(handle, "SDL_RemovePath");
  if !a31.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_RemovePath: " + a31.error }); }
  let a32 = dl.dl_sym(handle, "SDL_GetPathInfo");
  if !a32.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetPathInfo: " + a32.error }); }
  let a33 = dl.dl_sym(handle, "SDL_GetMouseState");
  if !a33.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetMouseState: " + a33.error }); }
  let a34 = dl.dl_sym(handle, "SDL_GetAudioPlaybackDevices");
  if !a34.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetAudioPlaybackDevices: " + a34.error }); }
  let a35 = dl.dl_sym(handle, "SDL_GetAudioRecordingDevices");
  if !a35.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetAudioRecordingDevices: " + a35.error }); }
  let a36 = dl.dl_sym(handle, "SDL_GetAudioDeviceName");
  if !a36.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetAudioDeviceName: " + a36.error }); }
  let a37 = dl.dl_sym(handle, "SDL_GetCurrentAudioDriver");
  if !a37.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetCurrentAudioDriver: " + a37.error }); }
  let a38 = dl.dl_sym(handle, "SDL_GetJoysticks");
  if !a38.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetJoysticks: " + a38.error }); }
  let a39 = dl.dl_sym(handle, "SDL_GetJoystickNameForID");
  if !a39.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetJoystickNameForID: " + a39.error }); }
  let a40 = dl.dl_sym(handle, "SDL_OpenAudioDeviceStream");
  if !a40.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_OpenAudioDeviceStream: " + a40.error }); }
  let a41 = dl.dl_sym(handle, "SDL_PutAudioStreamData");
  if !a41.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_PutAudioStreamData: " + a41.error }); }
  let a42 = dl.dl_sym(handle, "SDL_ResumeAudioStreamDevice");
  if !a42.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_ResumeAudioStreamDevice: " + a42.error }); }
  let a43 = dl.dl_sym(handle, "SDL_PauseAudioStreamDevice");
  if !a43.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_PauseAudioStreamDevice: " + a43.error }); }
  let a44 = dl.dl_sym(handle, "SDL_DestroyAudioStream");
  if !a44.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_DestroyAudioStream: " + a44.error }); }
  let a45 = dl.dl_sym(handle, "SDL_GetAudioStreamQueued");
  if !a45.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetAudioStreamQueued: " + a45.error }); }
  let a46 = dl.dl_sym(handle, "SDL_AudioStreamDevicePaused");
  if !a46.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_AudioStreamDevicePaused: " + a46.error }); }
  let a47 = dl.dl_sym(handle, "SDL_GetAudioStreamData");
  if !a47.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetAudioStreamData: " + a47.error }); }
  let a48 = dl.dl_sym(handle, "SDL_GetAudioStreamAvailable");
  if !a48.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetAudioStreamAvailable: " + a48.error }); }
  let a49 = dl.dl_sym(handle, "SDL_ClearAudioStream");
  if !a49.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_ClearAudioStream: " + a49.error }); }
  let a50 = dl.dl_sym(handle, "SDL_GetAudioStreamFormat");
  if !a50.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetAudioStreamFormat: " + a50.error }); }
  let a51 = dl.dl_sym(handle, "SDL_GetGlobalMouseState");
  if !a51.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetGlobalMouseState: " + a51.error }); }
  let a52 = dl.dl_sym(handle, "SDL_GetRelativeMouseState");
  if !a52.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetRelativeMouseState: " + a52.error }); }
  let a53 = dl.dl_sym(handle, "SDL_SetWindowRelativeMouseMode");
  if !a53.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetWindowRelativeMouseMode: " + a53.error }); }
  let a54 = dl.dl_sym(handle, "SDL_GetWindowRelativeMouseMode");
  if !a54.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetWindowRelativeMouseMode: " + a54.error }); }
  let a55 = dl.dl_sym(handle, "SDL_CaptureMouse");
  if !a55.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_CaptureMouse: " + a55.error }); }
  let a56 = dl.dl_sym(handle, "SDL_OpenJoystick");
  if !a56.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_OpenJoystick: " + a56.error }); }
  let a57 = dl.dl_sym(handle, "SDL_CloseJoystick");
  if !a57.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_CloseJoystick: " + a57.error }); }
  let a58 = dl.dl_sym(handle, "SDL_JoystickConnected");
  if !a58.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_JoystickConnected: " + a58.error }); }
  let a59 = dl.dl_sym(handle, "SDL_GetJoystickName");
  if !a59.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetJoystickName: " + a59.error }); }
  let a60 = dl.dl_sym(handle, "SDL_GetJoystickAxis");
  if !a60.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetJoystickAxis: " + a60.error }); }
  let a61 = dl.dl_sym(handle, "SDL_GetJoystickButton");
  if !a61.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetJoystickButton: " + a61.error }); }
  let a62 = dl.dl_sym(handle, "SDL_SetJoystickVirtualAxis");
  if !a62.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetJoystickVirtualAxis: " + a62.error }); }
  let a63 = dl.dl_sym(handle, "SDL_SetJoystickVirtualButton");
  if !a63.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetJoystickVirtualButton: " + a63.error }); }
  let a64 = dl.dl_sym(handle, "SDL_AttachVirtualJoystick");
  if !a64.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_AttachVirtualJoystick: " + a64.error }); }
  let a65 = dl.dl_sym(handle, "SDL_DetachVirtualJoystick");
  if !a65.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_DetachVirtualJoystick: " + a65.error }); }
  let a66 = dl.dl_sym(handle, "SDL_GetJoystickProperties");
  if !a66.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetJoystickProperties: " + a66.error }); }
  let a67 = dl.dl_sym(handle, "SDL_GetBooleanProperty");
  if !a67.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetBooleanProperty: " + a67.error }); }
  let a68 = dl.dl_sym(handle, "SDL_SetBooleanProperty");
  if !a68.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetBooleanProperty: " + a68.error }); }
  let a69 = dl.dl_sym(handle, "SDL_GetNumJoystickAxes");
  if !a69.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetNumJoystickAxes: " + a69.error }); }
  let a70 = dl.dl_sym(handle, "SDL_GetNumJoystickButtons");
  if !a70.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetNumJoystickButtons: " + a70.error }); }
  let a71 = dl.dl_sym(handle, "SDL_GetNumJoystickHats");
  if !a71.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetNumJoystickHats: " + a71.error }); }
  let a72 = dl.dl_sym(handle, "SDL_GetNumJoystickBalls");
  if !a72.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetNumJoystickBalls: " + a72.error }); }
  let a73 = dl.dl_sym(handle, "SDL_GetJoystickType");
  if !a73.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetJoystickType: " + a73.error }); }
  let a74 = dl.dl_sym(handle, "SDL_GetHaptics");
  if !a74.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetHaptics: " + a74.error }); }
  let a75 = dl.dl_sym(handle, "SDL_GetHapticFromID");
  if !a75.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetHapticFromID: " + a75.error }); }
  let a76 = dl.dl_sym(handle, "SDL_GetHapticName");
  if !a76.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetHapticName: " + a76.error }); }
  let a77 = dl.dl_sym(handle, "SDL_GetHapticNameForID");
  if !a77.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetHapticNameForID: " + a77.error }); }
  let a78 = dl.dl_sym(handle, "SDL_OpenHaptic");
  if !a78.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_OpenHaptic: " + a78.error }); }
  let a79 = dl.dl_sym(handle, "SDL_CloseHaptic");
  if !a79.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_CloseHaptic: " + a79.error }); }
  let a80 = dl.dl_sym(handle, "SDL_IsJoystickHaptic");
  if !a80.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_IsJoystickHaptic: " + a80.error }); }
  let a81 = dl.dl_sym(handle, "SDL_OpenHapticFromJoystick");
  if !a81.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_OpenHapticFromJoystick: " + a81.error }); }
  let a82 = dl.dl_sym(handle, "SDL_GetHapticFeatures");
  if !a82.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetHapticFeatures: " + a82.error }); }
  let a83 = dl.dl_sym(handle, "SDL_GetMaxHapticEffects");
  if !a83.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetMaxHapticEffects: " + a83.error }); }
  let a84 = dl.dl_sym(handle, "SDL_GetMaxHapticEffectsPlaying");
  if !a84.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetMaxHapticEffectsPlaying: " + a84.error }); }
  let a85 = dl.dl_sym(handle, "SDL_GetNumHapticAxes");
  if !a85.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetNumHapticAxes: " + a85.error }); }
  let a86 = dl.dl_sym(handle, "SDL_HapticEffectSupported");
  if !a86.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_HapticEffectSupported: " + a86.error }); }
  let a87 = dl.dl_sym(handle, "SDL_CreateHapticEffect");
  if !a87.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_CreateHapticEffect: " + a87.error }); }
  let a88 = dl.dl_sym(handle, "SDL_UpdateHapticEffect");
  if !a88.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_UpdateHapticEffect: " + a88.error }); }
  let a89 = dl.dl_sym(handle, "SDL_RunHapticEffect");
  if !a89.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_RunHapticEffect: " + a89.error }); }
  let a90 = dl.dl_sym(handle, "SDL_StopHapticEffect");
  if !a90.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_StopHapticEffect: " + a90.error }); }
  let a91 = dl.dl_sym(handle, "SDL_DestroyHapticEffect");
  if !a91.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_DestroyHapticEffect: " + a91.error }); }
  let a92 = dl.dl_sym(handle, "SDL_GetHapticEffectStatus");
  if !a92.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetHapticEffectStatus: " + a92.error }); }
  let a93 = dl.dl_sym(handle, "SDL_HapticRumbleSupported");
  if !a93.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_HapticRumbleSupported: " + a93.error }); }
  let a94 = dl.dl_sym(handle, "SDL_InitHapticRumble");
  if !a94.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_InitHapticRumble: " + a94.error }); }
  let a95 = dl.dl_sym(handle, "SDL_PlayHapticRumble");
  if !a95.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_PlayHapticRumble: " + a95.error }); }
  let a96 = dl.dl_sym(handle, "SDL_StopHapticRumble");
  if !a96.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_StopHapticRumble: " + a96.error }); }
  let a97 = dl.dl_sym(handle, "SDL_GetPenDeviceType");
  if !a97.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetPenDeviceType: " + a97.error }); }
  let a98 = dl.dl_sym(handle, "SDL_GetDisplayContentScale");
  if !a98.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetDisplayContentScale: " + a98.error }); }
  let a99 = dl.dl_sym(handle, "SDL_SetClipboardText");
  if !a99.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetClipboardText: " + a99.error }); }
  let a100 = dl.dl_sym(handle, "SDL_GetClipboardText");
  if !a100.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetClipboardText: " + a100.error }); }
  let a101 = dl.dl_sym(handle, "SDL_HasClipboardText");
  if !a101.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_HasClipboardText: " + a101.error }); }
  let a102 = dl.dl_sym(handle, "SDL_SetPrimarySelectionText");
  if !a102.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetPrimarySelectionText: " + a102.error }); }
  let a103 = dl.dl_sym(handle, "SDL_GetPrimarySelectionText");
  if !a103.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetPrimarySelectionText: " + a103.error }); }
  let a104 = dl.dl_sym(handle, "SDL_HasPrimarySelectionText");
  if !a104.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_HasPrimarySelectionText: " + a104.error }); }
  let a105 = dl.dl_sym(handle, "SDL_LoadBMP");
  if !a105.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_LoadBMP: " + a105.error }); }
  let a106 = dl.dl_sym(handle, "SDL_SaveBMP");
  if !a106.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SaveBMP: " + a106.error }); }
  let a107 = dl.dl_sym(handle, "SDL_CreateSurface");
  if !a107.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_CreateSurface: " + a107.error }); }
  let a108 = dl.dl_sym(handle, "SDL_DestroySurface");
  if !a108.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_DestroySurface: " + a108.error }); }

  return Ok(Sdl3Library{
    handle: handle,
    p_init: a1.value,
    p_quit: a2.value,
    p_was_init: a3.value,
    p_get_version: a4.value,
    p_get_revision: a5.value,
    p_get_ticks: a6.value,
    p_get_performance_counter: a7.value,
    p_delay: a8.value,
    p_pump_events: a9.value,
    p_poll_event: a10.value,
    p_push_event: a12.value,
    p_get_error: a11.value,
    p_set_event_filter: a13.value,
    p_add_event_watch: a14.value,
    p_remove_event_watch: a15.value,
    p_get_displays: a16.value,
    p_get_primary_display: a17.value,
    p_get_display_name: a18.value,
    p_get_display_bounds: a19.value,
    p_get_display_usable_bounds: a20.value,
    p_get_current_display_mode: a21.value,
    p_get_desktop_display_mode: a22.value,
    p_get_keyboard_state: a23.value,
    p_get_mod_state: a24.value,
    p_get_keyboard_focus: a25.value,
    p_free: a26.value,
    p_get_base_path: a27.value,
    p_get_pref_path: a28.value,
    p_get_current_directory: a29.value,
    p_create_directory: a30.value,
    p_remove_path: a31.value,
    p_get_path_info: a32.value,
    p_get_mouse_state: a33.value,
    p_get_audio_playback_devices: a34.value,
    p_get_audio_recording_devices: a35.value,
    p_get_audio_device_name: a36.value,
    p_get_current_audio_driver: a37.value,
    p_get_joysticks: a38.value,
    p_get_joystick_name_for_id: a39.value,
    p_open_audio_device_stream: a40.value,
    p_put_audio_stream_data: a41.value,
    p_resume_audio_stream_device: a42.value,
    p_pause_audio_stream_device: a43.value,
    p_destroy_audio_stream: a44.value,
    p_get_audio_stream_queued: a45.value,
    p_audio_stream_device_paused: a46.value,
    p_get_audio_stream_data: a47.value,
    p_get_audio_stream_available: a48.value,
    p_clear_audio_stream: a49.value,
    p_get_audio_stream_format: a50.value,
    p_get_global_mouse_state: a51.value,
    p_get_relative_mouse_state: a52.value,
    p_set_window_relative_mouse_mode: a53.value,
    p_get_window_relative_mouse_mode: a54.value,
    p_capture_mouse: a55.value,
    p_open_joystick: a56.value,
    p_close_joystick: a57.value,
    p_joystick_connected: a58.value,
    p_joystick_name: a59.value,
    p_joystick_axis: a60.value,
    p_joystick_button: a61.value,
    p_set_joystick_virtual_axis: a62.value,
    p_set_joystick_virtual_button: a63.value,
    p_attach_virtual_joystick: a64.value,
    p_detach_virtual_joystick: a65.value,
    p_get_joystick_properties: a66.value,
    p_get_boolean_property: a67.value,
    p_set_boolean_property: a68.value,
    p_get_num_joystick_axes: a69.value,
    p_get_num_joystick_buttons: a70.value,
    p_get_num_joystick_hats: a71.value,
    p_get_num_joystick_balls: a72.value,
    p_get_joystick_type: a73.value,
    p_get_haptics: a74.value,
    p_get_haptic_from_id: a75.value,
    p_get_haptic_name: a76.value,
    p_get_haptic_name_for_id: a77.value,
    p_open_haptic: a78.value,
    p_close_haptic: a79.value,
    p_is_joystick_haptic: a80.value,
    p_open_haptic_from_joystick: a81.value,
    p_get_haptic_features: a82.value,
    p_get_max_haptic_effects: a83.value,
    p_get_max_haptic_effects_playing: a84.value,
    p_get_num_haptic_axes: a85.value,
    p_haptic_effect_supported: a86.value,
    p_create_haptic_effect: a87.value,
    p_update_haptic_effect: a88.value,
    p_run_haptic_effect: a89.value,
    p_stop_haptic_effect: a90.value,
    p_destroy_haptic_effect: a91.value,
    p_get_haptic_effect_status: a92.value,
    p_haptic_rumble_supported: a93.value,
    p_init_haptic_rumble: a94.value,
    p_play_haptic_rumble: a95.value,
    p_stop_haptic_rumble: a96.value,
    p_get_pen_device_type: a97.value,
    p_get_display_content_scale: a98.value,
    p_set_clipboard_text: a99.value,
    p_get_clipboard_text: a100.value,
    p_has_clipboard_text: a101.value,
    p_set_primary_selection_text: a102.value,
    p_get_primary_selection_text: a103.value,
    p_has_primary_selection_text: a104.value,
    p_load_bmp: a105.value,
    p_save_bmp: a106.value,
    p_create_surface: a107.value,
    p_destroy_surface: a108.value,
  });
}

/// Release a loaded library handle.
/// Complexity: O(1).
pub fn sdl3_close(lib: &Sdl3Library) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

// =========================================================================
// Safe call wrappers (confined: fn-pointer casts live here)
// =========================================================================

/// SDL_Init(flags) -> bool.  Use SDL_INIT_EVENTS | SDL_INIT_TIMER for a
/// headless smoke; VIDEO/AUDIO require a device.
/// Complexity: O(1).
pub fn sdl3_init(lib: &Sdl3Library, flags: Int) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_init as fn(Int) -> UInt8;
    return (f(flags) as Int) != 0;
  }
}

/// SDL_Quit().
/// Complexity: O(1).
pub fn sdl3_quit(lib: &Sdl3Library)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_quit as fn();
    f();
  }
}

/// SDL_WasInit(flags) -> SDL_InitFlags mask (Uint32; 0 = none initialized);
/// true when any requested bit is set.
/// Complexity: O(1).
pub fn sdl3_was_init(lib: &Sdl3Library, flags: Int) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    // B-19: SDL_InitFlags is Uint32 -- declaring UInt8 here truncates the
    // mask to its low byte (16384 -> 0) on toolchains that honor declared
    // return widths (m263+).
    let f = lib.p_was_init as fn(Int) -> UInt32;
    return (f(flags) as Int) != 0;
  }
}

/// SDL_GetVersion() -> SDL_VERSIONNUM int.
/// Complexity: O(1).
pub fn sdl3_get_version(lib: &Sdl3Library) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_version as fn() -> Int32;
    return f() as Int;
  }
}

/// SDL_GetRevision() -> revision string ("" when the library returns NULL).
/// Complexity: O(len).
pub fn sdl3_get_revision(lib: &Sdl3Library) -> Str
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_revision as fn() -> *UInt8;
    let p = f();
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// SDL_GetTicks() -> milliseconds since init (Uint64).
/// Complexity: O(1).
pub fn sdl3_get_ticks(lib: &Sdl3Library) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_ticks as fn() -> UInt64;
    return f() as Int;
  }
}

/// SDL_GetPerformanceCounter() -> monotonic counter (Uint64).
/// Complexity: O(1).
pub fn sdl3_get_performance_counter(lib: &Sdl3Library) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_performance_counter as fn() -> UInt64;
    return f() as Int;
  }
}

/// SDL_Delay(ms).
/// Complexity: O(1).
pub fn sdl3_delay(lib: &Sdl3Library, ms: Int)
  requires: lib.handle != 0
  requires: ms >= 0
{
  unsafe {
    let f = lib.p_delay as fn(Int);
    f(ms);
  }
}

/// SDL_PumpEvents().
/// Complexity: O(1).
pub fn sdl3_pump_events(lib: &Sdl3Library)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_pump_events as fn();
    f();
  }
}

/// SDL_PollEvent(event) -> bool.  Pass an owned-buffer address
/// (`buf.as_mut_ptr() as Int`) to CONSUME the head event into it.  Passing 0
/// (NULL) is a PEEK on the pinned 3.4.8 runtime: it returns true when a real
/// event is pending but leaves it queued (it only clears SDL's internal poll
/// sentinel and reports false at the end of the poll cycle) -- the suite's
/// drain helper consumes into a scratch buffer instead.
/// Complexity: O(1).
pub fn sdl3_poll_event(lib: &Sdl3Library, event_ptr: Int) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_poll_event as fn(Int) -> UInt8;
    return (f(event_ptr) as Int) != 0;
  }
}

/// SDL_PushEvent(event) -> bool.  Lets a headless caller inject a synthetic
/// event (the headless-friendly event-pump proof for the engine ask
/// REL-20261010-1834-engine-3); returns false when the queue rejects it.
/// Complexity: O(1).
pub fn sdl3_push_event(lib: &Sdl3Library, event_ptr: Int) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_push_event as fn(Int) -> UInt8;
    return (f(event_ptr) as Int) != 0;
  }
}

/// SDL_GetError() -> current error string ("" when none).
/// Complexity: O(len).
pub fn sdl3_get_error(lib: &Sdl3Library) -> Str
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_error as fn() -> *UInt8;
    let p = f();
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

// =========================================================================
// Phase 2: window / renderer / texture / gamepad resources over the loader
// =========================================================================

// SDL pixel formats / texture access for the smoke.
// NOTE on 8888 naming (engine ask REL-20261011-1321-engine): SDL names
// 32-bit formats MSB-first (`SDL_PIXELFORMAT_RGBA8888` = R is the most
// significant byte).  On little-endian memory that byte order REVERSES:
// RGBA8888 lands in memory as A,B,G,R and ABGR8888 lands as R,G,B,A --
// `SDL_PIXELFORMAT_ABGR8888` is the "byte-order RGBA" array as produced by
// a plain RGBA8 framebuffer.
pub const SDL_PIXELFORMAT_RGBA8888: Int = 0x16462004;
pub const SDL_PIXELFORMAT_ABGR8888: Int = 0x16762004;
pub const SDL_TEXTUREACCESS_STATIC: Int = 0;
pub const SDL_TEXTUREACCESS_STREAMING: Int = 1;

pub type Sdl3WindowSize = {
  width: Int;
  height: Int;
}

/// Resolved addresses for the resource stage.  Separate from `Sdl3Library`
/// so a host with an older SDL3 still gets the smoke SKIP classification:
/// a missing resource symbol fails only the resource stage (`SDL3_LOAD_ABI`).
pub type Sdl3Resources = {
  handle: Int;
  p_create_window: Int;
  p_destroy_window: Int;
  p_show_window: Int;
  p_hide_window: Int;
  p_get_window_size: Int;
  p_set_window_title: Int;
  p_create_renderer: Int;
  p_destroy_renderer: Int;
  p_set_render_draw_color: Int;
  p_render_clear: Int;
  p_render_present: Int;
  p_create_texture: Int;
  p_destroy_texture: Int;
  p_get_gamepads: Int;
  p_open_gamepad: Int;
  p_close_gamepad: Int;
  p_has_gamepad: Int;
  p_free: Int;
  p_get_error: Int;
  p_update_texture: Int;
  p_render_texture: Int;
  p_set_render_vsync: Int;
  p_set_window_size: Int;
  p_set_window_resizable: Int;
  p_get_window_id: Int;
  p_get_window_from_id: Int;
  p_get_window_position: Int;
  p_set_window_position: Int;
  p_get_window_size_pixels: Int;
  p_get_window_display_scale: Int;
  p_get_display_for_window: Int;
  p_start_text_input: Int;
  p_stop_text_input: Int;
  p_text_input_active: Int;
  p_set_text_input_area: Int;
  p_get_text_input_area: Int;
  p_clear_composition: Int;
  p_set_window_icon: Int;
  p_get_window_properties: Int;
  p_get_pointer_property: Int;
  p_get_number_property: Int;
  p_vulkan_create_surface: Int;
}

fn sdl3_res_error(r: &Sdl3Resources) -> Str
  requires: r.handle != 0
{
  unsafe {
    let f = r.p_get_error as fn() -> *UInt8;
    let p = f();
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// Resource-stage loader: resolves the window/renderer/texture/gamepad API.
/// Complexity: O(symbols).
pub fn sdl3_load_resources() -> Result[Sdl3Resources, Sdl3LoadError] {
  let h = dl.dl_open(SDL3_SONAME);
  if !h.is_ok {
    return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;

  let a1 = dl.dl_sym(handle, "SDL_CreateWindow");
  if !a1.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_CreateWindow: " + a1.error }); }
  let a2 = dl.dl_sym(handle, "SDL_DestroyWindow");
  if !a2.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_DestroyWindow: " + a2.error }); }
  let a3 = dl.dl_sym(handle, "SDL_ShowWindow");
  if !a3.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_ShowWindow: " + a3.error }); }
  let a4 = dl.dl_sym(handle, "SDL_HideWindow");
  if !a4.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_HideWindow: " + a4.error }); }
  let a5 = dl.dl_sym(handle, "SDL_GetWindowSize");
  if !a5.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetWindowSize: " + a5.error }); }
  let a6 = dl.dl_sym(handle, "SDL_SetWindowTitle");
  if !a6.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetWindowTitle: " + a6.error }); }
  let a7 = dl.dl_sym(handle, "SDL_CreateRenderer");
  if !a7.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_CreateRenderer: " + a7.error }); }
  let a8 = dl.dl_sym(handle, "SDL_DestroyRenderer");
  if !a8.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_DestroyRenderer: " + a8.error }); }
  let a9 = dl.dl_sym(handle, "SDL_SetRenderDrawColor");
  if !a9.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetRenderDrawColor: " + a9.error }); }
  let a10 = dl.dl_sym(handle, "SDL_RenderClear");
  if !a10.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_RenderClear: " + a10.error }); }
  let a11 = dl.dl_sym(handle, "SDL_RenderPresent");
  if !a11.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_RenderPresent: " + a11.error }); }
  let a12 = dl.dl_sym(handle, "SDL_CreateTexture");
  if !a12.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_CreateTexture: " + a12.error }); }
  let a13 = dl.dl_sym(handle, "SDL_DestroyTexture");
  if !a13.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_DestroyTexture: " + a13.error }); }
  let a14 = dl.dl_sym(handle, "SDL_GetGamepads");
  if !a14.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetGamepads: " + a14.error }); }
  let a15 = dl.dl_sym(handle, "SDL_OpenGamepad");
  if !a15.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_OpenGamepad: " + a15.error }); }
  let a16 = dl.dl_sym(handle, "SDL_CloseGamepad");
  if !a16.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_CloseGamepad: " + a16.error }); }
  let a17 = dl.dl_sym(handle, "SDL_HasGamepad");
  if !a17.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_HasGamepad: " + a17.error }); }
  let a18 = dl.dl_sym(handle, "SDL_free");
  if !a18.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_free: " + a18.error }); }
  let a19 = dl.dl_sym(handle, "SDL_GetError");
  if !a19.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetError: " + a19.error }); }
  let a20 = dl.dl_sym(handle, "SDL_UpdateTexture");
  if !a20.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_UpdateTexture: " + a20.error }); }
  let a21 = dl.dl_sym(handle, "SDL_RenderTexture");
  if !a21.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_RenderTexture: " + a21.error }); }
  let a22 = dl.dl_sym(handle, "SDL_SetRenderVSync");
  if !a22.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetRenderVSync: " + a22.error }); }
  let a23 = dl.dl_sym(handle, "SDL_SetWindowSize");
  if !a23.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetWindowSize: " + a23.error }); }
  let a24 = dl.dl_sym(handle, "SDL_SetWindowResizable");
  if !a24.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetWindowResizable: " + a24.error }); }
  let a25 = dl.dl_sym(handle, "SDL_GetWindowID");
  if !a25.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetWindowID: " + a25.error }); }
  let a26 = dl.dl_sym(handle, "SDL_GetWindowFromID");
  if !a26.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetWindowFromID: " + a26.error }); }
  let a27 = dl.dl_sym(handle, "SDL_GetWindowPosition");
  if !a27.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetWindowPosition: " + a27.error }); }
  let a28 = dl.dl_sym(handle, "SDL_SetWindowPosition");
  if !a28.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetWindowPosition: " + a28.error }); }
  let a29 = dl.dl_sym(handle, "SDL_GetWindowSizeInPixels");
  if !a29.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetWindowSizeInPixels: " + a29.error }); }
  let a30 = dl.dl_sym(handle, "SDL_GetWindowDisplayScale");
  if !a30.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetWindowDisplayScale: " + a30.error }); }
  let a31 = dl.dl_sym(handle, "SDL_GetDisplayForWindow");
  if !a31.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetDisplayForWindow: " + a31.error }); }
  let a32 = dl.dl_sym(handle, "SDL_StartTextInput");
  if !a32.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_StartTextInput: " + a32.error }); }
  let a33 = dl.dl_sym(handle, "SDL_StopTextInput");
  if !a33.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_StopTextInput: " + a33.error }); }
  let a34 = dl.dl_sym(handle, "SDL_TextInputActive");
  if !a34.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_TextInputActive: " + a34.error }); }
  let a35 = dl.dl_sym(handle, "SDL_SetTextInputArea");
  if !a35.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetTextInputArea: " + a35.error }); }
  let a36 = dl.dl_sym(handle, "SDL_GetTextInputArea");
  if !a36.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetTextInputArea: " + a36.error }); }
  let a37 = dl.dl_sym(handle, "SDL_ClearComposition");
  if !a37.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_ClearComposition: " + a37.error }); }
  let a38 = dl.dl_sym(handle, "SDL_SetWindowIcon");
  if !a38.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_SetWindowIcon: " + a38.error }); }
  let a39 = dl.dl_sym(handle, "SDL_GetWindowProperties");
  if !a39.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetWindowProperties: " + a39.error }); }
  let a40 = dl.dl_sym(handle, "SDL_GetPointerProperty");
  if !a40.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetPointerProperty: " + a40.error }); }
  let a41 = dl.dl_sym(handle, "SDL_GetNumberProperty");
  if !a41.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_GetNumberProperty: " + a41.error }); }
  let a42 = dl.dl_sym(handle, "SDL_Vulkan_CreateSurface");
  if !a42.is_ok { var ig = dl.dl_close(handle); return Err(Sdl3LoadError{ kind: SDL3_LOAD_ABI; message: "SDL_Vulkan_CreateSurface: " + a42.error }); }

  return Ok(Sdl3Resources{
    handle: handle,
    p_create_window: a1.value,
    p_destroy_window: a2.value,
    p_show_window: a3.value,
    p_hide_window: a4.value,
    p_get_window_size: a5.value,
    p_set_window_title: a6.value,
    p_create_renderer: a7.value,
    p_destroy_renderer: a8.value,
    p_set_render_draw_color: a9.value,
    p_render_clear: a10.value,
    p_render_present: a11.value,
    p_create_texture: a12.value,
    p_destroy_texture: a13.value,
    p_get_gamepads: a14.value,
    p_open_gamepad: a15.value,
    p_close_gamepad: a16.value,
    p_has_gamepad: a17.value,
    p_free: a18.value,
    p_get_error: a19.value,
    p_update_texture: a20.value,
    p_render_texture: a21.value,
    p_set_render_vsync: a22.value,
    p_set_window_size: a23.value,
    p_set_window_resizable: a24.value,
    p_get_window_id: a25.value,
    p_get_window_from_id: a26.value,
    p_get_window_position: a27.value,
    p_set_window_position: a28.value,
    p_get_window_size_pixels: a29.value,
    p_get_window_display_scale: a30.value,
    p_get_display_for_window: a31.value,
    p_start_text_input: a32.value,
    p_stop_text_input: a33.value,
    p_text_input_active: a34.value,
    p_set_text_input_area: a35.value,
    p_get_text_input_area: a36.value,
    p_clear_composition: a37.value,
    p_set_window_icon: a38.value,
    p_get_window_properties: a39.value,
    p_get_pointer_property: a40.value,
    p_get_number_property: a41.value,
    p_vulkan_create_surface: a42.value,
  });
}

/// Release the resource-stage handle.
/// Complexity: O(1).
pub fn sdl3_resources_close(r: &Sdl3Resources) -> Result[Unit, Str]
  requires: r.handle != 0
{
  return dl.dl_close(r.handle);
}

/// SDL_CreateWindow(title, w, h, flags).  Use SDL_WINDOW_HIDDEN for a
/// headless-safe window.
/// Complexity: O(1).
pub fn sdl3_create_window(r: &Sdl3Resources, title: Str, w: Int, h: Int, flags: Int) -> Result[Int, Str]
  requires: r.handle != 0
  requires: title.len() > 0
  requires: w > 0
  requires: h > 0
{
  unsafe {
    let f = r.p_create_window as fn(*UInt8, Int, Int, Int) -> Int;
    let win = f(title.c_str(), w, h, flags);
    if win == 0 {
      return Err(sdl3_res_error(r));
    }
    return Ok(win);
  }
}

/// SDL_DestroyWindow.
/// Complexity: O(1).
pub fn sdl3_destroy_window(r: &Sdl3Resources, win: Int)
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_destroy_window as fn(Int);
    f(win);
  }
}

/// SDL_ShowWindow -> bool.
/// Complexity: O(1).
pub fn sdl3_show_window(r: &Sdl3Resources, win: Int) -> Bool
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_show_window as fn(Int) -> UInt8;
    return (f(win) as Int) != 0;
  }
}

/// SDL_HideWindow -> bool.
/// Complexity: O(1).
pub fn sdl3_hide_window(r: &Sdl3Resources, win: Int) -> Bool
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_hide_window as fn(Int) -> UInt8;
    return (f(win) as Int) != 0;
  }
}

/// SDL_GetWindowSize -> Sdl3WindowSize.
/// Complexity: O(1).
pub fn sdl3_window_size(r: &Sdl3Resources, win: Int) -> Sdl3WindowSize
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    var sw = sdl3_slot4();
    var sh = sdl3_slot4();
    let f = r.p_get_window_size as fn(Int, *UInt8, *UInt8);
    f(win, sw.as_mut_ptr(), sh.as_mut_ptr());
    return Sdl3WindowSize{ width: sdl3_read_u32(&sw), height: sdl3_read_u32(&sh) };
  }
}

/// SDL_SetWindowTitle -> bool.
/// Complexity: O(1).
pub fn sdl3_set_window_title(r: &Sdl3Resources, win: Int, title: Str) -> Bool
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_set_window_title as fn(Int, *UInt8) -> UInt8;
    return (f(win, title.c_str()) as Int) != 0;
  }
}

/// SDL_CreateRenderer(window, NULL) -> renderer handle.
/// Complexity: O(1).
pub fn sdl3_create_renderer(r: &Sdl3Resources, win: Int) -> Result[Int, Str]
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_create_renderer as fn(Int, Int) -> Int;
    let ren = f(win, 0);
    if ren == 0 {
      return Err(sdl3_res_error(r));
    }
    return Ok(ren);
  }
}

/// SDL_DestroyRenderer.
/// Complexity: O(1).
pub fn sdl3_destroy_renderer(r: &Sdl3Resources, ren: Int)
  requires: r.handle != 0
  requires: ren != 0
{
  unsafe {
    let f = r.p_destroy_renderer as fn(Int);
    f(ren);
  }
}

/// SDL_SetRenderDrawColor(r, g, b, a) -> bool.
/// Complexity: O(1).
pub fn sdl3_set_render_draw_color(r: &Sdl3Resources, ren: Int, rr: Int, gg: Int, bb: Int, aa: Int) -> Bool
  requires: r.handle != 0
  requires: ren != 0
  requires: rr >= 0
  requires: rr <= 255
  requires: gg >= 0
  requires: gg <= 255
  requires: bb >= 0
  requires: bb <= 255
  requires: aa >= 0
  requires: aa <= 255
{
  unsafe {
    let f = r.p_set_render_draw_color as fn(Int, Int, Int, Int, Int) -> UInt8;
    return (f(ren, rr, gg, bb, aa) as Int) != 0;
  }
}

/// SDL_RenderClear -> bool.
/// Complexity: O(1).
pub fn sdl3_render_clear(r: &Sdl3Resources, ren: Int) -> Bool
  requires: r.handle != 0
  requires: ren != 0
{
  unsafe {
    let f = r.p_render_clear as fn(Int) -> UInt8;
    return (f(ren) as Int) != 0;
  }
}

/// SDL_RenderPresent -> bool.
/// Complexity: O(1).
pub fn sdl3_render_present(r: &Sdl3Resources, ren: Int) -> Bool
  requires: r.handle != 0
  requires: ren != 0
{
  unsafe {
    let f = r.p_render_present as fn(Int) -> UInt8;
    return (f(ren) as Int) != 0;
  }
}

/// SDL_CreateTexture(renderer, format, access, w, h) -> texture handle.
/// Complexity: O(1).
pub fn sdl3_create_texture(r: &Sdl3Resources, ren: Int, format: Int, access: Int, w: Int, h: Int) -> Result[Int, Str]
  requires: r.handle != 0
  requires: ren != 0
  requires: w > 0
  requires: h > 0
{
  unsafe {
    let f = r.p_create_texture as fn(Int, Int, Int, Int, Int) -> Int;
    let tex = f(ren, format, access, w, h);
    if tex == 0 {
      return Err(sdl3_res_error(r));
    }
    return Ok(tex);
  }
}

/// SDL_DestroyTexture.
/// Complexity: O(1).
pub fn sdl3_destroy_texture(r: &Sdl3Resources, tex: Int)
  requires: r.handle != 0
  requires: tex != 0
{
  unsafe {
    let f = r.p_destroy_texture as fn(Int);
    f(tex);
  }
}

/// SDL_HasGamepad -> bool.
/// Complexity: O(1).
pub fn sdl3_has_gamepad(r: &Sdl3Resources) -> Bool
  requires: r.handle != 0
{
  unsafe {
    let f = r.p_has_gamepad as fn() -> UInt8;
    return (f() as Int) != 0;
  }
}

/// Attached gamepad count (SDL_GetGamepads + SDL_free of the array).
/// Complexity: O(gamepads).
pub fn sdl3_gamepad_count(r: &Sdl3Resources) -> Int
  requires: r.handle != 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = r.p_get_gamepads as fn(*UInt8) -> Int;
    let arr = f(slot.as_mut_ptr());
    let n = sdl3_read_u32(&slot);
    if arr != 0 {
      let fr = r.p_free as fn(Int);
      fr(arr);
    }
    return n;
  }
}

/// SDL_OpenGamepad(instance_id) -> gamepad handle.
/// Complexity: O(1).
pub fn sdl3_open_gamepad(r: &Sdl3Resources, id: Int) -> Result[Int, Str]
  requires: r.handle != 0
  requires: id >= 0
{
  unsafe {
    let f = r.p_open_gamepad as fn(Int) -> Int;
    let gp = f(id);
    if gp == 0 {
      return Err(sdl3_res_error(r));
    }
    return Ok(gp);
  }
}

/// SDL_CloseGamepad.
/// Complexity: O(1).
pub fn sdl3_close_gamepad(r: &Sdl3Resources, gp: Int)
  requires: r.handle != 0
  requires: gp != 0
{
  unsafe {
    let f = r.p_close_gamepad as fn(Int);
    f(gp);
  }
}

// =========================================================================
// 0.8.0: display blit -- texture upload + render copy + vsync (engine ask
// REL-20261011-1153-engine).  The pixel buffer is an XIOM-owned Vec that SDL
// READS (SDL_UpdateTexture with a NULL rect uploads the whole texture); no
// foreign-write readback is involved (B-11 path avoided).  SDL3's blit is
// `SDL_RenderTexture` (the SDL2-era `RenderCopy` was renamed).
// =========================================================================

/// SDL_UpdateTexture(tex, NULL, pixels, w*4): upload a tightly packed
/// RGBA8 frame (w*h*4 bytes) into the whole texture.
/// Complexity: O(w*h).
pub fn sdl3_update_texture(r: &Sdl3Resources, tex: Int, pixels: &mut Vec[UInt8], w: Int, h: Int) -> Bool
  requires: r.handle != 0
  requires: tex != 0
  requires: w > 0
  requires: h > 0
  requires: pixels.len() >= w * h * 4
{
  unsafe {
    let f = r.p_update_texture as fn(Int, Int, *UInt8, Int) -> UInt8;
    let pitch = w * 4;
    return (f(tex, 0, pixels.as_mut_ptr(), pitch) as Int) != 0;
  }
}

/// SDL_RenderTexture(ren, tex, NULL, NULL): stretch the whole texture over
/// the render target (clear before, present after).
/// Complexity: O(1).
pub fn sdl3_render_texture(r: &Sdl3Resources, ren: Int, tex: Int) -> Bool
  requires: r.handle != 0
  requires: ren != 0
  requires: tex != 0
{
  unsafe {
    let f = r.p_render_texture as fn(Int, Int, Int, Int) -> UInt8;
    return (f(ren, tex, 0, 0) as Int) != 0;
  }
}

/// SDL_SetRenderVSync(ren, vsync): 1 = on (FIFO), 0 = off, -1 = adaptive.
/// Complexity: O(1).
pub fn sdl3_set_render_vsync(r: &Sdl3Resources, ren: Int, vsync: Int) -> Bool
  requires: r.handle != 0
  requires: ren != 0
  requires: vsync >= -1
  requires: vsync <= 1
{
  unsafe {
    let f = r.p_set_render_vsync as fn(Int, Int) -> UInt8;
    return (f(ren, vsync) as Int) != 0;
  }
}

// Out-param slot helpers for the resource stage (4-byte int*).
fn sdl3_slot4() -> Vec[UInt8]
  requires: true
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 4 {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn sdl3_read_u32(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 4
{
  let b0 = buf[0] as Int;
  let b1 = buf[1] as Int;
  let b2 = buf[2] as Int;
  let b3 = buf[3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

// =========================================================================
// 0.4.0: SDL_Event decoding from an owned 128-byte buffer
//
// SDL_Event is a 128-byte union (`padding[128]` in the pinned release-3.4.8
// header; member layouts byte-identical in the release-3.2.10 clone).  Every
// member starts with the 8-byte header: type u32 @0, reserved u32 @4,
// timestamp u64 @8; window-scoped members carry windowID u32 @16.
//
// B-11 note: the accessors below are pure XIOM reads and safe on any buffer
// -- but SDL writing INTO an XIOM-owned buffer (`SDL_PollEvent(ptr)`) can
// come back corrupted on v0.64.3 (lane reproducer
// REL-20261011-0304-bindings; RETIRED on v0.64.4 -- see 0.18.0 below), so
// the suite keeps old decode checks on self-built buffers.  0.19.0
// correction: SDL_PollEvent(NULL) is a PEEK on the pinned 3.4.8 runtime (no
// consume for real events; it only clears SDL's poll sentinel), so queue
// draining MUST poll into an owned scratch buffer.
// =========================================================================

/// Size of an `SDL_Event` on the pinned headers (write one when pushing).
pub const SDL_EVENT_SIZE: Int = 128;

// Offsets pinned to the release-3.4.8 headers (== 3.2.10).
fn ev_read_u8(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 1
{
  return buf[off] as Int;
}

fn ev_read_u16(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 2
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  return b0 | (b1 << 8);
}

fn ev_read_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn ev_read_i32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let u = ev_read_u32(buf, off);
  if u >= 0x80000000 { return u - 0x100000000; }
  return u;
}

fn ev_read_u64(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  let lo = ev_read_u32(buf, off);
  let hi = ev_read_u32(buf, off + 4);
  return lo | (hi << 32);
}

/// 2^e for small |e| (pure float arithmetic; e in [-1074, 1024]).
fn pow2i(e: Int) -> Float64
  requires: e >= -1074
  requires: e <= 1024
{
  var r = 1.0;
  var i = e;
  while i > 0 {
    r = r * 2.0;
    i = i - 1;
  }
  while i < 0 {
    r = r / 2.0;
    i = i + 1;
  }
  return r;
}

/// IEEE-754 binary32 bits -> Float64 (pure arithmetic; avoids fp cast-call
/// returns, B-12).
pub fn sdl3_f32_from_bits(bits: Int) -> Float64
  requires: bits >= 0
  requires: bits <= 0xFFFFFFFF
{
  let sign = if ((bits >> 31) & 1) == 1 { -1.0 } else { 1.0 };
  let exp = (bits >> 23) & 0xFF;
  let frac = bits & 0x7FFFFF;
  if exp == 0 {
    if frac == 0 { return sign * 0.0; }
    return sign * (frac as Float64) * pow2i(-149);
  }
  if exp == 255 { return 0.0; }
  return sign * (1.0 + (frac as Float64) / 8388608.0) * pow2i(exp - 127);
}

/// Event type (u32 @0) -- compare against `SDL_EVENT_*`.
/// Complexity: O(1).
pub fn sdl3_event_type(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 4
{
  return ev_read_u32(buf, 0);
}

/// Event timestamp in nanoseconds (u64 @8).
/// Complexity: O(1).
pub fn sdl3_event_timestamp(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 16
{
  return ev_read_u64(buf, 8);
}

/// Window id the event belongs to (u32 @16; 0 when not window-scoped).
/// Complexity: O(1).
pub fn sdl3_event_window_id(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 20
{
  return ev_read_u32(buf, 16);
}

/// Key event: physical scancode (u32 @24) -- compare against `SDL_SCANCODE_*`.
/// Complexity: O(1).
pub fn sdl3_event_key_scancode(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 28
{
  return ev_read_u32(buf, 24);
}

/// Key event: virtual keycode (u32 @28; ASCII value for printable keys).
/// Complexity: O(1).
pub fn sdl3_event_key_code(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 32
{
  return ev_read_u32(buf, 28);
}

/// Key event: modifier mask (u16 @32).
/// Complexity: O(1).
pub fn sdl3_event_key_mods(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 34
{
  return ev_read_u16(buf, 32);
}

/// Key event: pressed flag (u8 @36).
/// Complexity: O(1).
pub fn sdl3_event_key_down(buf: &Vec[UInt8]) -> Bool
  requires: buf.len() >= 37
{
  return ev_read_u8(buf, 36) != 0;
}

/// Key event: repeat flag (u8 @37).
/// Complexity: O(1).
pub fn sdl3_event_key_repeat(buf: &Vec[UInt8]) -> Bool
  requires: buf.len() >= 38
{
  return ev_read_u8(buf, 37) != 0;
}

/// Mouse-motion event: button state mask (u32 @24).
/// Complexity: O(1).
pub fn sdl3_event_mouse_state(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 28
{
  return ev_read_u32(buf, 24);
}

/// Mouse x as raw f32 bits (u32 @28; decode with `sdl3_f32_from_bits`).
/// Works for motion and button events (same offset).
/// Complexity: O(1).
pub fn sdl3_event_mouse_x_bits(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 32
{
  return ev_read_u32(buf, 28);
}

/// Mouse y as raw f32 bits (u32 @32).
/// Complexity: O(1).
pub fn sdl3_event_mouse_y_bits(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 36
{
  return ev_read_u32(buf, 32);
}

/// Mouse x as Float64 (motion and button events).
/// Complexity: O(1).
pub fn sdl3_event_mouse_x(buf: &Vec[UInt8]) -> Float64
  requires: buf.len() >= 32
{
  return sdl3_f32_from_bits(ev_read_u32(buf, 28));
}

/// Mouse y as Float64 (motion and button events).
/// Complexity: O(1).
pub fn sdl3_event_mouse_y(buf: &Vec[UInt8]) -> Float64
  requires: buf.len() >= 36
{
  return sdl3_f32_from_bits(ev_read_u32(buf, 32));
}

/// Mouse-button event: button index (u8 @24).
/// Complexity: O(1).
pub fn sdl3_event_mouse_button(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 25
{
  return ev_read_u8(buf, 24);
}

/// Mouse-button event: pressed flag (u8 @25).
/// Complexity: O(1).
pub fn sdl3_event_mouse_button_down(buf: &Vec[UInt8]) -> Bool
  requires: buf.len() >= 26
{
  return ev_read_u8(buf, 25) != 0;
}

/// Mouse-button event: click count (u8 @26; 2 = double click).
/// Complexity: O(1).
pub fn sdl3_event_mouse_clicks(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 27
{
  return ev_read_u8(buf, 26);
}

/// Window event: data1 (Sint32 @20).
/// Complexity: O(1).
pub fn sdl3_event_window_data1(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 24
{
  return ev_read_i32(buf, 20);
}

/// Window event: data2 (Sint32 @24).
/// Complexity: O(1).
pub fn sdl3_event_window_data2(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 28
{
  return ev_read_i32(buf, 24);
}

// =========================================================================
// 0.5.0: event filter + event watch (C callbacks into XIOM)
// 0.20.0: DIRECT HANDOFF + shape widening -- handlers take the NATURAL C
// shape `(userdata, event)` and are handed to SDL as-is (B-22 fixed, m277:
// fn-typed param values marshal through cast-call positions exactly; B-15
// fixed as well, so 2-arg shapes are no longer forced through a registry).
// The 0.5.0 dispatchers, registries and userdata accessors are gone: each
// handler receives its own registration userdata, so multiple watches each
// route their own state.  The raw `SDL_Event*` address is only valid during
// the call (SDL semantics); copy it into an owned buffer with the 0.4.0
// decode accessors via `sdl3_event_copy`.  Filters: return 1 to keep the
// event, 0 to drop it.  Watches observe without consuming.  Removal passes
// the SAME handler fn + userdata (SDL matches the pair).
// =========================================================================

/// Copy the foreign SDL_Event into an owned 128-byte buffer.
fn ev_copy_from(event: Int) -> Vec[UInt8]
  requires: event != 0
{
  var buf: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 128 {
    buf.push(0 as UInt8);
    i = i + 1;
  }
  unsafe {
    ffi.memcpy(buf.as_mut_ptr(), event as *UInt8, 128);
  }
  return buf;
}

/// Copy the foreign SDL_Event -- passed to a filter/watch handler as its raw
/// address -- into an owned 128-byte buffer for the decode accessors
/// (null-safe: returns an empty buffer for 0).
/// Complexity: O(1).
pub fn sdl3_event_copy(event: Int) -> Vec[UInt8]
  requires: true
{
  if event == 0 {
    return Vec[UInt8].new();
  }
  return ev_copy_from(event);
}

/// SDL_SetEventFilter(handler, userdata) -- direct handoff.  The handler
/// `fn(userdata: Int, event: Int) -> UInt8` decides per event: return 1 to
/// keep it, 0 to drop it.  Read the event bytes with
/// `sdl3_event_copy(event)`.  Handlers must be env-free (top-level fns).
/// Complexity: O(1).
pub fn sdl3_set_event_filter(lib: &Sdl3Library, filter: fn(Int, Int) -> UInt8, userdata: Int) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_set_event_filter as fn(fn(Int, Int) -> UInt8, Int);
    f(filter, userdata);
  }
  return true;
}

/// SDL_SetEventFilter(NULL, NULL) -- removes the filter.
/// Complexity: O(1).
pub fn sdl3_clear_event_filter(lib: &Sdl3Library) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_set_event_filter as fn(Int, Int);
    f(0, 0);
  }
  return true;
}

/// SDL_AddEventWatch(handler, userdata) -- direct handoff; observes events
/// without consuming.  The handler `fn(userdata: Int, event: Int) -> Unit`
/// receives its own registration userdata (multiple watches each route
/// their own state).  Remove with the SAME handler + userdata (SDL matches
/// the pair).  Handlers must be env-free.
/// Complexity: O(1).
pub fn sdl3_add_event_watch(lib: &Sdl3Library, watch: fn(Int, Int) -> Unit, userdata: Int) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_add_event_watch as fn(fn(Int, Int) -> Unit, Int) -> UInt8;
    return (f(watch, userdata) as Int) != 0;
  }
}

/// SDL_RemoveEventWatch(handler, userdata) -- pass the SAME handler fn and
/// userdata used at registration (SDL matches the pair).
/// Complexity: O(1).
pub fn sdl3_remove_event_watch(lib: &Sdl3Library, watch: fn(Int, Int) -> Unit, userdata: Int) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_remove_event_watch as fn(fn(Int, Int) -> Unit, Int);
    f(watch, userdata);
  }
  return true;
}

// =========================================================================
// 0.6.0: displays + keyboard state (needs SDL_INIT_VIDEO)
//
// Out-params go through owned byte slots (proven readback direction); the
// display list and the SDL_DisplayMode struct are SDL-owned memory read
// with ffi.ptr_read_* (read direction proven by the 0.5.0 event copy).
// SDL_Rect = 4x int32; SDL_DisplayMode layout pinned from the release-3.2.10
// header (ABI-stable in SDL3): displayID u32 @0, format u32 @4, w @8, h @12,
// pixel_density f32 @16, refresh_rate f32 @20.
// =========================================================================

pub type Sdl3Rect = {
  x: Int;
  y: Int;
  w: Int;
  h: Int;
}

pub type Sdl3DisplayMode = {
  pixel_format: Int;
  w: Int;
  h: Int;
  pixel_density: Float64;
  refresh_rate: Float64;
}

// Generic zeroed slot (any size).
fn sdl3_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn sdl3_read_u32_at(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn sdl3_read_i32_at(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let u = sdl3_read_u32_at(buf, off);
  if u >= 0x80000000 { return u - 0x100000000; }
  return u;
}

// Signed i32 at a raw address.
fn ptr_i32(q: Int) -> Int
  requires: q != 0
{
  unsafe {
    let u = ffi.ptr_read_u32_le(q as *UInt8);
    if u >= 0x80000000 { return u - 0x100000000; }
    return u;
  }
}

// f32 at a raw address, decoded pure-arithmetic (B-12 discipline).
fn ptr_f32(q: Int) -> Float64
  requires: q != 0
{
  unsafe {
    return sdl3_f32_from_bits(ffi.ptr_read_u32_le(q as *UInt8));
  }
}

fn sdl3_mode_from_ptr(p: Int) -> Sdl3DisplayMode
  requires: p != 0
{
  return Sdl3DisplayMode{
    pixel_format: unsafe { ffi.ptr_read_u32_le((p + 4) as *UInt8) },
    w: ptr_i32(p + 8),
    h: ptr_i32(p + 12),
    pixel_density: ptr_f32(p + 16),
    refresh_rate: ptr_f32(p + 20),
  };
}

/// SDL_GetDisplays count (array freed via SDL_free).  Requires VIDEO.
/// Complexity: O(displays).
pub fn sdl3_display_count(lib: &Sdl3Library) -> Int
  requires: lib.handle != 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = lib.p_get_displays as fn(*UInt8) -> Int;
    let arr = f(slot.as_mut_ptr());
    let n = sdl3_read_u32(&slot);
    if arr != 0 {
      let fr = lib.p_free as fn(Int);
      fr(arr);
    }
    return n;
  }
}

/// i-th display id from SDL_GetDisplays (0 when out of range).
/// Complexity: O(displays).
pub fn sdl3_display_at(lib: &Sdl3Library, i: Int) -> Int
  requires: lib.handle != 0
  requires: i >= 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = lib.p_get_displays as fn(*UInt8) -> Int;
    let arr = f(slot.as_mut_ptr());
    let n = sdl3_read_u32(&slot);
    var id = 0;
    if arr != 0 {
      if i < n {
        id = ffi.ptr_read_u32_le((arr + i * 4) as *UInt8);
      }
      let fr = lib.p_free as fn(Int);
      fr(arr);
    }
    return id;
  }
}

/// SDL_GetPrimaryDisplay id.
/// Complexity: O(1).
pub fn sdl3_primary_display(lib: &Sdl3Library) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_primary_display as fn() -> Int32;
    return f() as Int;
  }
}

/// SDL_GetDisplayName ("" when SDL has no name).
/// Complexity: O(len).
pub fn sdl3_display_name(lib: &Sdl3Library, id: Int) -> Str
  requires: lib.handle != 0
  requires: id >= 0
{
  unsafe {
    let f = lib.p_get_display_name as fn(Int) -> *UInt8;
    let p = f(id);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// SDL_GetDisplayBounds -> Sdl3Rect (zeros on failure).
/// Complexity: O(1).
pub fn sdl3_display_bounds(lib: &Sdl3Library, id: Int) -> Sdl3Rect
  requires: lib.handle != 0
  requires: id >= 0
{
  unsafe {
    var slot = sdl3_slot(16);
    let f = lib.p_get_display_bounds as fn(Int, *UInt8) -> UInt8;
    let ok = (f(id, slot.as_mut_ptr()) as Int) != 0;
    if !ok { return Sdl3Rect{ x: 0; y: 0; w: 0; h: 0 }; }
    return Sdl3Rect{
      x: sdl3_read_i32_at(&slot, 0),
      y: sdl3_read_i32_at(&slot, 4),
      w: sdl3_read_i32_at(&slot, 8),
      h: sdl3_read_i32_at(&slot, 12),
    };
  }
}

/// SDL_GetDisplayUsableBounds -> Sdl3Rect (zeros on failure).
/// Complexity: O(1).
pub fn sdl3_display_usable_bounds(lib: &Sdl3Library, id: Int) -> Sdl3Rect
  requires: lib.handle != 0
  requires: id >= 0
{
  unsafe {
    var slot = sdl3_slot(16);
    let f = lib.p_get_display_usable_bounds as fn(Int, *UInt8) -> UInt8;
    let ok = (f(id, slot.as_mut_ptr()) as Int) != 0;
    if !ok { return Sdl3Rect{ x: 0; y: 0; w: 0; h: 0 }; }
    return Sdl3Rect{
      x: sdl3_read_i32_at(&slot, 0),
      y: sdl3_read_i32_at(&slot, 4),
      w: sdl3_read_i32_at(&slot, 8),
      h: sdl3_read_i32_at(&slot, 12),
    };
  }
}

/// SDL_GetCurrentDisplayMode (all-zero struct when SDL returns NULL).
/// Complexity: O(1).
pub fn sdl3_display_mode(lib: &Sdl3Library, id: Int) -> Sdl3DisplayMode
  requires: lib.handle != 0
  requires: id >= 0
{
  unsafe {
    let f = lib.p_get_current_display_mode as fn(Int) -> Int;
    let p = f(id);
    if p == 0 { return Sdl3DisplayMode{ pixel_format: 0; w: 0; h: 0; pixel_density: 0.0; refresh_rate: 0.0 }; }
    return sdl3_mode_from_ptr(p);
  }
}

/// SDL_GetDesktopDisplayMode (all-zero struct when SDL returns NULL).
/// Complexity: O(1).
pub fn sdl3_desktop_display_mode(lib: &Sdl3Library, id: Int) -> Sdl3DisplayMode
  requires: lib.handle != 0
  requires: id >= 0
{
  unsafe {
    let f = lib.p_get_desktop_display_mode as fn(Int) -> Int;
    let p = f(id);
    if p == 0 { return Sdl3DisplayMode{ pixel_format: 0; w: 0; h: 0; pixel_density: 0.0; refresh_rate: 0.0 }; }
    return sdl3_mode_from_ptr(p);
  }
}

/// SDL_GetKeyboardState: number of scancodes in the state array (0 when
/// unavailable; ~512 with VIDEO initialized).
/// Complexity: O(1).
pub fn sdl3_keyboard_state_count(lib: &Sdl3Library) -> Int
  requires: lib.handle != 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = lib.p_get_keyboard_state as fn(*UInt8) -> Int;
    let p = f(slot.as_mut_ptr());
    if p == 0 { return 0; }
    return sdl3_read_u32(&slot);
  }
}

/// True when the given scancode is currently held (SDL_GetKeyboardState).
/// Complexity: O(1).
pub fn sdl3_keyboard_key_down(lib: &Sdl3Library, scancode: Int) -> Bool
  requires: lib.handle != 0
  requires: scancode >= 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = lib.p_get_keyboard_state as fn(*UInt8) -> Int;
    let p = f(slot.as_mut_ptr());
    let n = sdl3_read_u32(&slot);
    if p == 0 { return false; }
    if scancode >= n { return false; }
    let b = ffi.ptr_read_u8((p + scancode) as *UInt8);
    return (b as Int) != 0;
  }
}

/// SDL_GetModState -> SDL_Keymod (masked to 16 bits).
/// Complexity: O(1).
pub fn sdl3_mod_state(lib: &Sdl3Library) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_mod_state as fn() -> Int32;
    return (f() as Int) & 0xFFFF;
  }
}

/// SDL_GetKeyboardFocus -> focused window handle (0 when none).
/// Complexity: O(1).
pub fn sdl3_keyboard_focus(lib: &Sdl3Library) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_keyboard_focus as fn() -> Int;
    return f();
  }
}

// =========================================================================
// 0.7.0: filesystem basics (no subsystem init required)
//
// SDL_GetBasePath returns an SDL-owned const string (do NOT free);
// SDL_GetPrefPath / SDL_GetCurrentDirectory return caller-owned strings that
// are freed with SDL_free after copying into an XIOM Str.  SDL_PathInfo
// layout pinned from the release-3.2.10 header (SDL_Time = Sint64 ns):
// type i32 @0, size u64 @8, create_time @16, modify_time @24, access @32.
// =========================================================================

pub const SDL_PATHTYPE_NONE: Int = 0;
pub const SDL_PATHTYPE_FILE: Int = 1;
pub const SDL_PATHTYPE_DIRECTORY: Int = 2;
pub const SDL_PATHTYPE_OTHER: Int = 3;

pub type Sdl3PathInfo = {
  kind: Int;
  size: Int;
  create_time: Int;
  modify_time: Int;
  exists: Bool;
}

fn sdl3_read_u64_at(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  let lo = sdl3_read_u32_at(buf, off);
  let hi = sdl3_read_u32_at(buf, off + 4);
  return lo | (hi << 32);
}

/// SDL_GetBasePath (SDL-owned string, copied; "" on error).  Read-only.
/// Complexity: O(len).
pub fn sdl3_get_base_path(lib: &Sdl3Library) -> Str
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_base_path as fn() -> Int;
    let p = f();
    if p == 0 { return ""; }
    return Str::from_c_str(p as *UInt8);
  }
}

/// SDL_GetPrefPath(org, app): creates and returns the per-user directory
/// (caller-owned; copied then SDL_free'd here).  "" on error.
/// Complexity: O(len).
pub fn sdl3_get_pref_path(lib: &Sdl3Library, org: Str, app: Str) -> Str
  requires: lib.handle != 0
  requires: org.len() > 0
  requires: app.len() > 0
{
  unsafe {
    let f = lib.p_get_pref_path as fn(*UInt8, *UInt8) -> Int;
    let p = f(org.c_str(), app.c_str());
    if p == 0 { return ""; }
    let s = Str::from_c_str(p as *UInt8);
    let fr = lib.p_free as fn(Int);
    fr(p);
    return s;
  }
}

/// SDL_GetCurrentDirectory (caller-owned; copied then SDL_free'd here).
/// Complexity: O(len).
pub fn sdl3_get_current_directory(lib: &Sdl3Library) -> Str
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_current_directory as fn() -> Int;
    let p = f();
    if p == 0 { return ""; }
    let s = Str::from_c_str(p as *UInt8);
    let fr = lib.p_free as fn(Int);
    fr(p);
    return s;
  }
}

/// SDL_CreateDirectory -> bool.
/// Complexity: O(1).
pub fn sdl3_create_directory(lib: &Sdl3Library, path: Str) -> Bool
  requires: lib.handle != 0
  requires: path.len() > 0
{
  unsafe {
    let f = lib.p_create_directory as fn(*UInt8) -> UInt8;
    return (f(path.c_str()) as Int) != 0;
  }
}

/// SDL_RemovePath (file or EMPTY directory) -> bool.
/// Complexity: O(1).
pub fn sdl3_remove_path(lib: &Sdl3Library, path: Str) -> Bool
  requires: lib.handle != 0
  requires: path.len() > 0
{
  unsafe {
    let f = lib.p_remove_path as fn(*UInt8) -> UInt8;
    return (f(path.c_str()) as Int) != 0;
  }
}

/// SDL_GetPathInfo -> Sdl3PathInfo (`exists=false` + zeroed fields on error).
/// Complexity: O(1).
pub fn sdl3_get_path_info(lib: &Sdl3Library, path: Str) -> Sdl3PathInfo
  requires: lib.handle != 0
  requires: path.len() > 0
{
  unsafe {
    var slot = sdl3_slot(40);
    let f = lib.p_get_path_info as fn(*UInt8, *UInt8) -> UInt8;
    let ok = (f(path.c_str(), slot.as_mut_ptr()) as Int) != 0;
    if !ok {
      return Sdl3PathInfo{ kind: SDL_PATHTYPE_NONE; size: 0; create_time: 0; modify_time: 0; exists: false };
    }
    return Sdl3PathInfo{
      kind: sdl3_read_u32_at(&slot, 0),
      size: sdl3_read_u64_at(&slot, 8),
      create_time: sdl3_read_u64_at(&slot, 16),
      modify_time: sdl3_read_u64_at(&slot, 24),
      exists: true,
    };
  }
}

// =========================================================================
// 0.9.0: mouse state + window contract setters (engine input layer)
//
// SDL_GetMouseState writes two f32 OUT-params (window-relative) and returns
// the button mask as a u32; slot readback + pure-arithmetic f32 decode
// (B-12 discipline).  Window setters back the engine window contract
// (resize/resizable); the typed resize/focus events flow through the 0.4.0
// decode accessors via an event watch (see README "engine event loop").
// =========================================================================

pub type Sdl3MouseState = {
  x: Float64;
  y: Float64;
  buttons: Int;
}

/// SDL_GetMouseState -> Sdl3MouseState (x/y window-relative, f32 decoded).
/// Requires VIDEO.  Out-params use TWO separate owned slots: pointer
/// arithmetic on `as_mut_ptr()` is miscompiled on v0.64.3 (B-17 -- it
/// yields wild addresses), so never pass `base + N` to foreign calls.
/// Complexity: O(1).
pub fn sdl3_mouse_state(lib: &Sdl3Library) -> Sdl3MouseState
  requires: lib.handle != 0
{
  unsafe {
    var xslot = sdl3_slot(4);
    var yslot = sdl3_slot(4);
    let f = lib.p_get_mouse_state as fn(*UInt8, *UInt8) -> Int32;
    let buttons = f(xslot.as_mut_ptr(), yslot.as_mut_ptr());
    return Sdl3MouseState{
      x: sdl3_f32_from_bits(sdl3_read_u32_at(&xslot, 0)),
      y: sdl3_f32_from_bits(sdl3_read_u32_at(&yslot, 0)),
      buttons: buttons as Int,
    };
  }
}

/// SDL_SetWindowSize(win, w, h); a WINDOW_RESIZED (+PIXEL_SIZE_CHANGED)
/// event is queued for the next pump.
/// Complexity: O(1).
pub fn sdl3_set_window_size(r: &Sdl3Resources, win: Int, w: Int, h: Int) -> Bool
  requires: r.handle != 0
  requires: win != 0
  requires: w > 0
  requires: h > 0
{
  unsafe {
    let f = r.p_set_window_size as fn(Int, Int, Int) -> UInt8;
    return (f(win, w, h) as Int) != 0;
  }
}

/// SDL_SetWindowResizable(win, resizable) -> bool.
/// Complexity: O(1).
pub fn sdl3_set_window_resizable(r: &Sdl3Resources, win: Int, resizable: Bool) -> Bool
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_set_window_resizable as fn(Int, UInt8) -> UInt8;
    let v: UInt8 = if resizable { 1 as UInt8 } else { 0 as UInt8 };
    return (f(win, v) as Int) != 0;
  }
}

// =========================================================================
// 0.10.0: audio + joystick enumeration (engine device selection)
//
// SDL_GetAudioPlaybackDevices / SDL_GetAudioRecordingDevices /
// SDL_GetJoysticks return caller-owned arrays of u32 ids (freed via
// SDL_free; fetched + freed per `_at` call, O(devices)).  Names and the
// driver string are SDL-owned const strings (copied, never freed).
// =========================================================================

/// SDL_GetAudioPlaybackDevices count.  Requires SDL_INIT_AUDIO.
/// Complexity: O(devices).
pub fn sdl3_audio_playback_count(lib: &Sdl3Library) -> Int
  requires: lib.handle != 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = lib.p_get_audio_playback_devices as fn(*UInt8) -> Int;
    let arr = f(slot.as_mut_ptr());
    let n = sdl3_read_u32(&slot);
    if arr != 0 {
      let fr = lib.p_free as fn(Int);
      fr(arr);
    }
    return n;
  }
}

/// i-th playback device id (0 when out of range).
/// Complexity: O(devices).
pub fn sdl3_audio_playback_at(lib: &Sdl3Library, i: Int) -> Int
  requires: lib.handle != 0
  requires: i >= 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = lib.p_get_audio_playback_devices as fn(*UInt8) -> Int;
    let arr = f(slot.as_mut_ptr());
    let n = sdl3_read_u32(&slot);
    var id = 0;
    if arr != 0 {
      if i < n {
        id = ffi.ptr_read_u32_le((arr + i * 4) as *UInt8);
      }
      let fr = lib.p_free as fn(Int);
      fr(arr);
    }
    return id;
  }
}

/// SDL_GetAudioRecordingDevices count.
/// Complexity: O(devices).
pub fn sdl3_audio_recording_count(lib: &Sdl3Library) -> Int
  requires: lib.handle != 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = lib.p_get_audio_recording_devices as fn(*UInt8) -> Int;
    let arr = f(slot.as_mut_ptr());
    let n = sdl3_read_u32(&slot);
    if arr != 0 {
      let fr = lib.p_free as fn(Int);
      fr(arr);
    }
    return n;
  }
}

/// i-th recording device id (0 when out of range).
/// Complexity: O(devices).
pub fn sdl3_audio_recording_at(lib: &Sdl3Library, i: Int) -> Int
  requires: lib.handle != 0
  requires: i >= 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = lib.p_get_audio_recording_devices as fn(*UInt8) -> Int;
    let arr = f(slot.as_mut_ptr());
    let n = sdl3_read_u32(&slot);
    var id = 0;
    if arr != 0 {
      if i < n {
        id = ffi.ptr_read_u32_le((arr + i * 4) as *UInt8);
      }
      let fr = lib.p_free as fn(Int);
      fr(arr);
    }
    return id;
  }
}

/// SDL_GetAudioDeviceName (SDL-owned string, copied; "" for unknown ids).
/// Complexity: O(len).
pub fn sdl3_audio_device_name(lib: &Sdl3Library, id: Int) -> Str
  requires: lib.handle != 0
  requires: id >= 0
{
  unsafe {
    let f = lib.p_get_audio_device_name as fn(Int) -> *UInt8;
    let p = f(id);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// SDL_GetCurrentAudioDriver (SDL-owned string, copied; "" before AUDIO init).
/// Complexity: O(len).
pub fn sdl3_current_audio_driver(lib: &Sdl3Library) -> Str
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_current_audio_driver as fn() -> Int;
    let p = f();
    if p == 0 { return ""; }
    return Str::from_c_str(p as *UInt8);
  }
}

/// SDL_GetJoysticks count (needs JOYSTICK for populated results).
/// Complexity: O(joysticks).
pub fn sdl3_joystick_count(lib: &Sdl3Library) -> Int
  requires: lib.handle != 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = lib.p_get_joysticks as fn(*UInt8) -> Int;
    let arr = f(slot.as_mut_ptr());
    let n = sdl3_read_u32(&slot);
    if arr != 0 {
      let fr = lib.p_free as fn(Int);
      fr(arr);
    }
    return n;
  }
}

/// i-th joystick instance id (0 when out of range).
/// Complexity: O(joysticks).
pub fn sdl3_joystick_at(lib: &Sdl3Library, i: Int) -> Int
  requires: lib.handle != 0
  requires: i >= 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = lib.p_get_joysticks as fn(*UInt8) -> Int;
    let arr = f(slot.as_mut_ptr());
    let n = sdl3_read_u32(&slot);
    var id = 0;
    if arr != 0 {
      if i < n {
        id = ffi.ptr_read_u32_le((arr + i * 4) as *UInt8);
      }
      let fr = lib.p_free as fn(Int);
      fr(arr);
    }
    return id;
  }
}

/// SDL_GetJoystickNameForID (SDL-owned string, copied; "" for unknown ids).
/// Complexity: O(len).
pub fn sdl3_joystick_name_for_id(lib: &Sdl3Library, id: Int) -> Str
  requires: lib.handle != 0
  requires: id >= 0
{
  unsafe {
    let f = lib.p_get_joystick_name_for_id as fn(Int) -> *UInt8;
    let p = f(id);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

// =========================================================================
// 0.12.0: audio streaming (silent push path) + mouse-wheel event accessors
//
// Audio: SDL_OpenAudioDeviceStream with a NULL callback/userdata gives a
// PUSH stream -- we feed interleaved PCM from an XIOM buffer
// (SDL_PutAudioStreamData, own-buffer read direction) and control the
// device with resume/pause.  SDL_AudioSpec = { format u32 @0, channels i32
// @4, freq i32 @8 } (pinned); SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK requests
// the default output.  No C callback threads are involved.
// Wheel: SDL_MouseWheelEvent layout (pinned): x f32 @24, y f32 @28,
// direction u32 @32, mouse_x f32 @36, mouse_y f32 @40.
// =========================================================================

pub const SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK: Int = 0xFFFFFFFF;
pub const SDL_AUDIO_DEVICE_DEFAULT_RECORDING: Int = 0xFFFFFFFE;
pub const SDL_AUDIO_F32: Int = 0x8120;
pub const SDL_MOUSEWHEEL_NORMAL: Int = 0;
pub const SDL_MOUSEWHEEL_FLIPPED: Int = 1;

/// Little-endian u32 store into an XIOM-owned byte slot (B-11 discipline:
/// byte-indexed writes, the proven in-param slot path).
fn sdl3_write_u32_le(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  buf[off + 0] = ( v        & 0xFF) as UInt8;
  buf[off + 1] = ((v >>  8) & 0xFF) as UInt8;
  buf[off + 2] = ((v >> 16) & 0xFF) as UInt8;
  buf[off + 3] = ((v >> 24) & 0xFF) as UInt8;
}

/// SDL_OpenAudioDeviceStream(devid, {format, channels, freq}, NULL, NULL)
/// shared path: the spec is the APP side (input for playback, output for
/// recording); a NULL callback keeps the stream in push/pull mode.  The
/// spec slot is built with byte-indexed writes (B-16 discipline).  Returns
/// the stream handle (0 on failure; see the error string).
fn sdl3_open_device_stream(lib: &Sdl3Library, devid: Int, format: Int, channels: Int, freq: Int) -> Int
  requires: lib.handle != 0
  requires: format > 0
  requires: channels > 0
  requires: freq > 0
{
  unsafe {
    var slot = sdl3_slot(12);
    // format u32 @0, channels i32 @4, freq i32 @8 (byte-indexed writes).
    sdl3_write_u32_le(&mut slot, 0, format);
    sdl3_write_u32_le(&mut slot, 4, channels);
    sdl3_write_u32_le(&mut slot, 8, freq);
    let f = lib.p_open_audio_device_stream as fn(Int, *UInt8, Int, Int) -> Int;
    return f(devid, slot.as_mut_ptr(), 0, 0);
  }
}

/// SDL_OpenAudioDeviceStream(DEFAULT_PLAYBACK, ...) -> push stream handle
/// (0 on failure; see the error string).  Requires SDL_INIT_AUDIO.
/// Complexity: O(device open).
pub fn sdl3_open_audio_playback_stream(lib: &Sdl3Library, format: Int, channels: Int, freq: Int) -> Int
  requires: lib.handle != 0
  requires: format > 0
  requires: channels > 0
  requires: freq > 0
{
  return sdl3_open_device_stream(lib, SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, format, channels, freq);
}

/// SDL_OpenAudioDeviceStream(DEFAULT_RECORDING, ...) -> pull (capture)
/// stream handle: resume it, then drain PCM with
/// sdl3_get_audio_stream_data.  Returns 0 when no recording device exists
/// or access is denied (mic privacy) -- callers treat that as SKIP.
/// Requires SDL_INIT_AUDIO.
/// Complexity: O(device open).
pub fn sdl3_open_audio_recording_stream(lib: &Sdl3Library, format: Int, channels: Int, freq: Int) -> Int
  requires: lib.handle != 0
  requires: format > 0
  requires: channels > 0
  requires: freq > 0
{
  return sdl3_open_device_stream(lib, SDL_AUDIO_DEVICE_DEFAULT_RECORDING, format, channels, freq);
}

/// SDL_PutAudioStreamData(stream, buf, len): queue `len` bytes of
/// interleaved PCM from an XIOM buffer (SDL reads our memory).
/// Complexity: O(len).
pub fn sdl3_put_audio_stream_data(lib: &Sdl3Library, stream: Int, buf: &mut Vec[UInt8], len: Int) -> Bool
  requires: lib.handle != 0
  requires: stream != 0
  requires: len > 0
  requires: buf.len() >= len
{
  unsafe {
    let f = lib.p_put_audio_stream_data as fn(Int, *UInt8, Int) -> UInt8;
    return (f(stream, buf.as_mut_ptr(), len) as Int) != 0;
  }
}

/// SDL_ResumeAudioStreamDevice -> bool (starts playback of queued data).
/// Complexity: O(1).
pub fn sdl3_resume_audio_stream_device(lib: &Sdl3Library, stream: Int) -> Bool
  requires: lib.handle != 0
  requires: stream != 0
{
  unsafe {
    let f = lib.p_resume_audio_stream_device as fn(Int) -> UInt8;
    return (f(stream) as Int) != 0;
  }
}

/// SDL_PauseAudioStreamDevice -> bool.
/// Complexity: O(1).
pub fn sdl3_pause_audio_stream_device(lib: &Sdl3Library, stream: Int) -> Bool
  requires: lib.handle != 0
  requires: stream != 0
{
  unsafe {
    let f = lib.p_pause_audio_stream_device as fn(Int) -> UInt8;
    return (f(stream) as Int) != 0;
  }
}

/// SDL_AudioStreamDevicePaused -> bool.
/// Complexity: O(1).
pub fn sdl3_audio_stream_device_paused(lib: &Sdl3Library, stream: Int) -> Bool
  requires: lib.handle != 0
  requires: stream != 0
{
  unsafe {
    let f = lib.p_audio_stream_device_paused as fn(Int) -> UInt8;
    return (f(stream) as Int) != 0;
  }
}

/// SDL_GetAudioStreamQueued -> bytes still queued.
/// Complexity: O(1).
pub fn sdl3_get_audio_stream_queued(lib: &Sdl3Library, stream: Int) -> Int
  requires: lib.handle != 0
  requires: stream != 0
{
  unsafe {
    let f = lib.p_get_audio_stream_queued as fn(Int) -> Int32;
    return f(stream) as Int;
  }
}

/// SDL_DestroyAudioStream (closes the device; nil-safe at the caller).
/// Complexity: O(1).
pub fn sdl3_destroy_audio_stream(lib: &Sdl3Library, stream: Int)
  requires: lib.handle != 0
  requires: stream != 0
{
  unsafe {
    let f = lib.p_destroy_audio_stream as fn(Int);
    f(stream);
  }
}

/// Mouse-wheel event: horizontal scroll (f32 @24).
/// Complexity: O(1).
pub fn sdl3_event_wheel_x(ev: &Vec[UInt8]) -> Float64
  requires: ev.len() >= 28
{
  return sdl3_f32_from_bits(sdl3_read_u32_at(ev, 24));
}

/// Mouse-wheel event: vertical scroll (f32 @28).
/// Complexity: O(1).
pub fn sdl3_event_wheel_y(ev: &Vec[UInt8]) -> Float64
  requires: ev.len() >= 32
{
  return sdl3_f32_from_bits(sdl3_read_u32_at(ev, 28));
}

/// Mouse-wheel event: raw horizontal bits (u32 @24).
/// Complexity: O(1).
pub fn sdl3_event_wheel_x_bits(ev: &Vec[UInt8]) -> Int
  requires: ev.len() >= 28
{
  return sdl3_read_u32_at(ev, 24);
}

/// Mouse-wheel event: raw vertical bits (u32 @28).
/// Complexity: O(1).
pub fn sdl3_event_wheel_y_bits(ev: &Vec[UInt8]) -> Int
  requires: ev.len() >= 32
{
  return sdl3_read_u32_at(ev, 28);
}

/// Mouse-wheel event: direction (u32 @32; SDL_MOUSEWHEEL_NORMAL/FLIPPED).
/// Complexity: O(1).
pub fn sdl3_event_wheel_direction(ev: &Vec[UInt8]) -> Int
  requires: ev.len() >= 36
{
  return sdl3_read_u32_at(ev, 32);
}

/// Mouse-wheel event: cursor x when the wheel fired (f32 @36).
/// Complexity: O(1).
pub fn sdl3_event_wheel_mouse_x(ev: &Vec[UInt8]) -> Float64
  requires: ev.len() >= 40
{
  return sdl3_f32_from_bits(sdl3_read_u32_at(ev, 36));
}

/// Mouse-wheel event: cursor y when the wheel fired (f32 @40).
/// Complexity: O(1).
pub fn sdl3_event_wheel_mouse_y(ev: &Vec[UInt8]) -> Float64
  requires: ev.len() >= 44
{
  return sdl3_f32_from_bits(sdl3_read_u32_at(ev, 40));
}

// =========================================================================
// 0.13.0: capture streams + stream query (default recording device)
//
// SDL_OpenAudioDeviceStream with SDL_AUDIO_DEVICE_DEFAULT_RECORDING and a
// NULL callback gives a PULL stream: resume it and drain converted PCM with
// SDL_GetAudioStreamData into an XIOM-owned buffer.  SDL_GetAudioStreamFormat
// fills two SDL_AudioSpecs (12 bytes each: format u32 @0, channels i32 @4,
// freq i32 @8); for a recording stream the APP side is the output (dst),
// for a playback stream it is the input (src).  SDL_GetAudioStreamAvailable
// reports readable converted bytes; SDL_ClearAudioStream drops queued data.
// =========================================================================

/// SDL_GetAudioStreamData(stream, buf, len) -> bytes read (>= 0) or -1 on
/// failure.  SDL writes into the XIOM-owned buffer (read direction); `len`
/// must be <= buf.len().
/// Complexity: O(len).
pub fn sdl3_get_audio_stream_data(lib: &Sdl3Library, stream: Int, buf: &mut Vec[UInt8], len: Int) -> Int
  requires: lib.handle != 0
  requires: stream != 0
  requires: len > 0
  requires: buf.len() >= len
{
  unsafe {
    let f = lib.p_get_audio_stream_data as fn(Int, *UInt8, Int) -> Int32;
    return f(stream, buf.as_mut_ptr(), len) as Int;
  }
}

/// SDL_GetAudioStreamAvailable -> converted bytes currently readable
/// (>= 0) or -1 on failure.
/// Complexity: O(1).
pub fn sdl3_get_audio_stream_available(lib: &Sdl3Library, stream: Int) -> Int
  requires: lib.handle != 0
  requires: stream != 0
{
  unsafe {
    let f = lib.p_get_audio_stream_available as fn(Int) -> Int32;
    return f(stream) as Int;
  }
}

/// SDL_ClearAudioStream -> bool (drops every queued/available byte).
/// Complexity: O(1).
pub fn sdl3_clear_audio_stream(lib: &Sdl3Library, stream: Int) -> Bool
  requires: lib.handle != 0
  requires: stream != 0
{
  unsafe {
    let f = lib.p_clear_audio_stream as fn(Int) -> UInt8;
    return (f(stream) as Int) != 0;
  }
}

/// Stream format pair read back from SDL_GetAudioStreamFormat.  For a
/// playback stream src is the app side; for a recording stream dst is the
/// app side (the requested spec either way).
pub type Sdl3AudioStreamFormat = {
  ok: Bool;
  src_format: Int;
  src_channels: Int;
  src_freq: Int;
  dst_format: Int;
  dst_channels: Int;
  dst_freq: Int;
}

/// SDL_GetAudioStreamFormat -> Sdl3AudioStreamFormat (ok=false on failure;
/// see sdl3_get_error).  The two SDL_AudioSpecs are filled into TWO
/// separate owned 12-byte slots -- pointer arithmetic (`base + 12`) is
/// miscompiled on v0.64.3 and yields wild addresses (B-17), so this must
/// NOT pass one slot with an offset.
/// Complexity: O(1).
pub fn sdl3_get_audio_stream_format(lib: &Sdl3Library, stream: Int) -> Sdl3AudioStreamFormat
  requires: lib.handle != 0
  requires: stream != 0
{
  unsafe {
    var srcslot = sdl3_slot(12);
    var dstslot = sdl3_slot(12);
    let f = lib.p_get_audio_stream_format as fn(Int, *UInt8, *UInt8) -> UInt8;
    let ok = (f(stream, srcslot.as_mut_ptr(), dstslot.as_mut_ptr()) as Int) != 0;
    if !ok {
      return Sdl3AudioStreamFormat{ ok: false; src_format: 0; src_channels: 0; src_freq: 0; dst_format: 0; dst_channels: 0; dst_freq: 0 };
    }
    return Sdl3AudioStreamFormat{
      ok: true,
      src_format: sdl3_read_u32_at(&srcslot, 0),
      src_channels: sdl3_read_u32_at(&srcslot, 4),
      src_freq: sdl3_read_u32_at(&srcslot, 8),
      dst_format: sdl3_read_u32_at(&dstslot, 0),
      dst_channels: sdl3_read_u32_at(&dstslot, 4),
      dst_freq: sdl3_read_u32_at(&dstslot, 8),
    };
  }
}

// =========================================================================
// 0.14.0: pointer capture + relative mouse + global/relative state
//
// SDL_GetGlobalMouseState / SDL_GetRelativeMouseState write two f32
// OUT-params (one owned slot each; B-17 discipline -- no pointer
// arithmetic) and return the button mask.  SDL3 exposes relative mode
// PER WINDOW (SDL_Set/GetWindowRelativeMouseMode); SDL_CaptureMouse drives
// drag capture (foreground window only -- a false return without a focused
// window is informational, not an error).
// =========================================================================

/// SDL_GetGlobalMouseState -> Sdl3MouseState (desktop-global x/y, f32
/// decoded; buttons = mask).  Requires VIDEO.
/// Complexity: O(1).
pub fn sdl3_global_mouse_state(lib: &Sdl3Library) -> Sdl3MouseState
  requires: lib.handle != 0
{
  unsafe {
    var xslot = sdl3_slot(4);
    var yslot = sdl3_slot(4);
    let f = lib.p_get_global_mouse_state as fn(*UInt8, *UInt8) -> Int32;
    let buttons = f(xslot.as_mut_ptr(), yslot.as_mut_ptr());
    return Sdl3MouseState{
      x: sdl3_f32_from_bits(sdl3_read_u32_at(&xslot, 0)),
      y: sdl3_f32_from_bits(sdl3_read_u32_at(&yslot, 0)),
      buttons: buttons as Int,
    };
  }
}

/// SDL_GetRelativeMouseState -> Sdl3MouseState (x/y = motion since the
/// previous call, f32 decoded; buttons = mask).  Requires VIDEO.
/// Complexity: O(1).
pub fn sdl3_relative_mouse_state(lib: &Sdl3Library) -> Sdl3MouseState
  requires: lib.handle != 0
{
  unsafe {
    var xslot = sdl3_slot(4);
    var yslot = sdl3_slot(4);
    let f = lib.p_get_relative_mouse_state as fn(*UInt8, *UInt8) -> Int32;
    let buttons = f(xslot.as_mut_ptr(), yslot.as_mut_ptr());
    return Sdl3MouseState{
      x: sdl3_f32_from_bits(sdl3_read_u32_at(&xslot, 0)),
      y: sdl3_f32_from_bits(sdl3_read_u32_at(&yslot, 0)),
      buttons: buttons as Int,
    };
  }
}

/// SDL_SetWindowRelativeMouseMode(win, enabled) -> bool (per-window
/// relative mode; engine pointer-look).  Requires VIDEO.
/// Complexity: O(1).
pub fn sdl3_set_window_relative_mouse_mode(lib: &Sdl3Library, win: Int, enabled: Bool) -> Bool
  requires: lib.handle != 0
  requires: win != 0
{
  unsafe {
    let f = lib.p_set_window_relative_mouse_mode as fn(Int, UInt8) -> UInt8;
    let v: UInt8 = if enabled { 1 as UInt8 } else { 0 as UInt8 };
    return (f(win, v) as Int) != 0;
  }
}

/// SDL_GetWindowRelativeMouseMode(win) -> bool.
/// Complexity: O(1).
pub fn sdl3_window_relative_mouse_mode(lib: &Sdl3Library, win: Int) -> Bool
  requires: lib.handle != 0
  requires: win != 0
{
  unsafe {
    let f = lib.p_get_window_relative_mouse_mode as fn(Int) -> UInt8;
    return (f(win) as Int) != 0;
  }
}

/// SDL_CaptureMouse(enabled) -> bool (drag capture; only allowed for the
/// foreground window, so a false return without focus is informational).
/// Complexity: O(1).
pub fn sdl3_capture_mouse(lib: &Sdl3Library, enabled: Bool) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_capture_mouse as fn(UInt8) -> UInt8;
    let v: UInt8 = if enabled { 1 as UInt8 } else { 0 as UInt8 };
    return (f(v) as Int) != 0;
  }
}

// =========================================================================
// 0.15.0: joystick open/read surface + virtual-joystick instrumentation
//
// SDL_OpenJoystick/CloseJoystick over an instance id, axis (Sint16) and
// button (bool) reads, connected + name queries.  SDL_AttachVirtualJoystick
// gives a hardware-free path through the REAL open/read code (the suite
// feeds it with SDL_SetJoystickVirtualAxis/Button): the desc is a 136-byte
// x64 slot built with byte-indexed writes (B-16/B-17); `version` =
// sizeof(desc) per SDL_INIT_INTERFACE, type = SDL_JOYSTICK_TYPE_UNKNOWN,
// full valid masks, and the name pointer points at the caller's Str which
// SDL KEEPS -- pass a string that outlives the joystick.
// =========================================================================

/// SDL_VirtualJoystickDesc size on the x64 ABI (the `version` value
/// SDL_INIT_INTERFACE writes).
pub const SDL_VIRTUAL_JOYSTICK_DESC_SIZE: Int = 136;

/// Little-endian u16 store into an XIOM-owned byte slot (B-16 discipline).
fn sdl3_write_u16_le(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 2
{
  buf[off + 0] = (v & 0xFF) as UInt8;
  buf[off + 1] = ((v >> 8) & 0xFF) as UInt8;
}

/// Little-endian u64 store (two byte-indexed u32 halves).
fn sdl3_write_u64_le(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  sdl3_write_u32_le(buf, off, v & 0xFFFFFFFF);
  sdl3_write_u32_le(buf, off + 4, (v >> 32) & 0xFFFFFFFF);
}

/// SDL_OpenJoystick(instance_id) -> handle (0 on failure; see the error
/// string).  Requires SDL_INIT_JOYSTICK.
/// Complexity: O(1).
pub fn sdl3_open_joystick(lib: &Sdl3Library, id: Int) -> Int
  requires: lib.handle != 0
  requires: id > 0
{
  unsafe {
    let f = lib.p_open_joystick as fn(Int) -> Int;
    return f(id);
  }
}

/// SDL_CloseJoystick(handle).
/// Complexity: O(1).
pub fn sdl3_close_joystick(lib: &Sdl3Library, joy: Int)
  requires: lib.handle != 0
  requires: joy != 0
{
  unsafe {
    let f = lib.p_close_joystick as fn(Int);
    f(joy);
  }
}

/// SDL_JoystickConnected -> bool.
/// Complexity: O(1).
pub fn sdl3_joystick_connected(lib: &Sdl3Library, joy: Int) -> Bool
  requires: lib.handle != 0
  requires: joy != 0
{
  unsafe {
    let f = lib.p_joystick_connected as fn(Int) -> UInt8;
    return (f(joy) as Int) != 0;
  }
}

/// SDL_GetJoystickName (SDL-owned string, copied; "" on failure).
/// Complexity: O(len).
pub fn sdl3_joystick_name(lib: &Sdl3Library, joy: Int) -> Str
  requires: lib.handle != 0
  requires: joy != 0
{
  unsafe {
    let f = lib.p_joystick_name as fn(Int) -> *UInt8;
    let p = f(joy);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// SDL_GetJoystickAxis -> -32768..32767 (0 when the axis is absent).
/// The 16-bit return is sign-extended explicitly (the ABI guarantees only
/// the low 16 bits).
/// Complexity: O(1).
pub fn sdl3_joystick_axis(lib: &Sdl3Library, joy: Int, axis: Int) -> Int
  requires: lib.handle != 0
  requires: joy != 0
  requires: axis >= 0
{
  unsafe {
    let f = lib.p_joystick_axis as fn(Int, Int) -> Int32;
    let raw = (f(joy, axis) as Int) & 0xFFFF;
    if raw >= 0x8000 {
      return raw - 0x10000;
    }
    return raw;
  }
}

/// SDL_GetJoystickButton -> bool.
/// Complexity: O(1).
pub fn sdl3_joystick_button(lib: &Sdl3Library, joy: Int, button: Int) -> Bool
  requires: lib.handle != 0
  requires: joy != 0
  requires: button >= 0
{
  unsafe {
    let f = lib.p_joystick_button as fn(Int, Int) -> UInt8;
    return (f(joy, button) as Int) != 0;
  }
}

/// SDL_SetJoystickVirtualAxis(joy, axis, value) -> bool (Sint16 value).
/// Complexity: O(1).
pub fn sdl3_set_joystick_virtual_axis(lib: &Sdl3Library, joy: Int, axis: Int, value: Int) -> Bool
  requires: lib.handle != 0
  requires: joy != 0
  requires: axis >= 0
  requires: value >= -32768
  requires: value <= 32767
{
  unsafe {
    let f = lib.p_set_joystick_virtual_axis as fn(Int, Int, Int) -> UInt8;
    return (f(joy, axis, value) as Int) != 0;
  }
}

/// SDL_SetJoystickVirtualButton(joy, button, down) -> bool.
/// Complexity: O(1).
pub fn sdl3_set_joystick_virtual_button(lib: &Sdl3Library, joy: Int, button: Int, down: Bool) -> Bool
  requires: lib.handle != 0
  requires: joy != 0
  requires: button >= 0
{
  unsafe {
    let f = lib.p_set_joystick_virtual_button as fn(Int, Int, UInt8) -> UInt8;
    let v: UInt8 = if down { 1 as UInt8 } else { 0 as UInt8 };
    return (f(joy, button, v) as Int) != 0;
  }
}

/// SDL_AttachVirtualJoystick -> instance id (0 on failure).  `name` must
/// outlive the joystick (SDL keeps the pointer).  Requires
/// SDL_INIT_JOYSTICK.
/// Complexity: O(1).
pub fn sdl3_attach_virtual_joystick(lib: &Sdl3Library, name: Str, naxes: Int, nbuttons: Int) -> Int
  requires: lib.handle != 0
  requires: name.len() > 0
  requires: naxes > 0
  requires: naxes <= 16
  requires: nbuttons > 0
  requires: nbuttons <= 32
{
  unsafe {
    var slot = sdl3_slot(SDL_VIRTUAL_JOYSTICK_DESC_SIZE);
    // version u32 @0 = sizeof(desc) (SDL_INIT_INTERFACE convention);
    // type u16 @4 = SDL_JOYSTICK_TYPE_UNKNOWN (0), vendor/product @8/@10 = 0.
    sdl3_write_u32_le(&mut slot, 0, SDL_VIRTUAL_JOYSTICK_DESC_SIZE);
    sdl3_write_u16_le(&mut slot, 12, naxes);
    sdl3_write_u16_le(&mut slot, 14, nbuttons);
    // balls/hats/touchpads/sensors @16-23 = 0; padding2 @24 = 0.
    let bmask = (1 << nbuttons) - 1;  // button_mask u32 @28
    let amask = (1 << naxes) - 1;     // axis_mask u32 @32
    sdl3_write_u32_le(&mut slot, 28, bmask);
    sdl3_write_u32_le(&mut slot, 32, amask);
    let np = name.c_str() as Int;     // name ptr @40
    sdl3_write_u64_le(&mut slot, 40, np);
    // touchpads @48 / sensors @56 / userdata @64 / callbacks @72-135 = 0.
    let f = lib.p_attach_virtual_joystick as fn(*UInt8) -> Int;
    return f(slot.as_mut_ptr());
  }
}

/// SDL_DetachVirtualJoystick(instance_id) -> bool.
/// Complexity: O(1).
pub fn sdl3_detach_virtual_joystick(lib: &Sdl3Library, id: Int) -> Bool
  requires: lib.handle != 0
  requires: id > 0
{
  unsafe {
    let f = lib.p_detach_virtual_joystick as fn(Int) -> UInt8;
    return (f(id) as Int) != 0;
  }
}

// =========================================================================
// 0.16.0: drag-drop payload decoding (SDL_DropEvent, pure buffer reads)
//
// SDL_DropEvent layout (pinned to the 3.4.8 header): type u32 @0,
// reserved u32 @4, timestamp u64 @8, windowID u32 @16, x f32 @20, y f32
// @24, source ptr @32, data ptr @40 (48 bytes).  source/data are SDL-owned
// C strings valid for the duration of the event; NULL decodes to "".
// The SDL_EVENT_DROP_* type constants are already exported (0.11.0 tables).
// =========================================================================

/// Little-endian u64 read from an owned byte buffer (two u32 halves).
fn sdl3_read_u64_at(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  let lo = sdl3_read_u32_at(buf, off);
  let hi = sdl3_read_u32_at(buf, off + 4);
  return lo | (hi << 32);
}

/// Raw pointer to a Str's NUL-terminated bytes (for building synthetic
/// C-side structures in tests/tools; valid while `s` lives).
/// Complexity: O(1).
pub fn sdl3_str_c_ptr(s: Str) -> Int
  requires: s.len() > 0
{
  unsafe {
    return s.c_str() as Int;
  }
}

/// SDL_DropEvent windowID (u32 @16).
/// Complexity: O(1).
pub fn sdl3_event_drop_window_id(ev: &Vec[UInt8]) -> Int
  requires: ev.len() >= 48
{
  return sdl3_read_u32_at(ev, 16);
}

/// SDL_DropEvent x (f32 @20, window-relative).
/// Complexity: O(1).
pub fn sdl3_event_drop_x(ev: &Vec[UInt8]) -> Float64
  requires: ev.len() >= 48
{
  return sdl3_f32_from_bits(sdl3_read_u32_at(ev, 20));
}

/// SDL_DropEvent y (f32 @24, window-relative).
/// Complexity: O(1).
pub fn sdl3_event_drop_y(ev: &Vec[UInt8]) -> Float64
  requires: ev.len() >= 48
{
  return sdl3_f32_from_bits(sdl3_read_u32_at(ev, 24));
}

/// SDL_DropEvent source (ptr @32 -> SDL-owned C string, copied; "" when
/// NULL).
/// Complexity: O(len).
pub fn sdl3_event_drop_source(ev: &Vec[UInt8]) -> Str
  requires: ev.len() >= 48
{
  unsafe {
    let p = sdl3_read_u64_at(ev, 32);
    if p == 0 { return ""; }
    return Str::from_c_str(p as *UInt8);
  }
}

/// SDL_DropEvent data (ptr @40 -> SDL-owned C string, copied; "" when
/// NULL): the file name for SDL_EVENT_DROP_FILE, the text for
/// SDL_EVENT_DROP_TEXT.
/// Complexity: O(len).
pub fn sdl3_event_drop_data(ev: &Vec[UInt8]) -> Str
  requires: ev.len() >= 48
{
  unsafe {
    let p = sdl3_read_u64_at(ev, 40);
    if p == 0 { return ""; }
    return Str::from_c_str(p as *UInt8);
  }
}

// =========================================================================
// 0.19.0: joystick CAPS accessors (engine ask REL-20261013-2324-engine)
//
// SDL3 has no SDL_JoystickHasRumble/LED style functions in the pinned 3.4.8
// headers: capabilities are BOOLEAN strings on the joystick properties group
// (SDL_GetJoystickProperties -> SDL_GetBooleanProperty).  The five
// SDL_PROP_JOYSTICK_CAP_* keys and the num-getters (axes/buttons/hats/balls)
// plus SDL_GetJoystickType are exposed as typed queries; sdl3_joystick_caps
// aggregates them into one struct.  A missing properties group reads as an
// all-false/zero caps record (no silent nulls).
// =========================================================================

/// Joystick capability property name: mono LED with adjustable brightness.
pub const SDL_PROP_JOYSTICK_CAP_MONO_LED_BOOLEAN: Str = "SDL.joystick.cap.mono_led";
/// Joystick capability property name: RGB LED.
pub const SDL_PROP_JOYSTICK_CAP_RGB_LED_BOOLEAN: Str = "SDL.joystick.cap.rgb_led";
/// Joystick capability property name: player LED.
pub const SDL_PROP_JOYSTICK_CAP_PLAYER_LED_BOOLEAN: Str = "SDL.joystick.cap.player_led";
/// Joystick capability property name: left/right rumble.
pub const SDL_PROP_JOYSTICK_CAP_RUMBLE_BOOLEAN: Str = "SDL.joystick.cap.rumble";
/// Joystick capability property name: simple trigger rumble.
pub const SDL_PROP_JOYSTICK_CAP_TRIGGER_RUMBLE_BOOLEAN: Str = "SDL.joystick.cap.trigger_rumble";

/// SDL_JoystickType values (3.4.8 enum).
pub const SDL_JOYSTICK_TYPE_UNKNOWN: Int = 0;
pub const SDL_JOYSTICK_TYPE_GAMEPAD: Int = 1;
pub const SDL_JOYSTICK_TYPE_WHEEL: Int = 2;
pub const SDL_JOYSTICK_TYPE_ARCADE_STICK: Int = 3;
pub const SDL_JOYSTICK_TYPE_FLIGHT_STICK: Int = 4;
pub const SDL_JOYSTICK_TYPE_DANCE_PAD: Int = 5;
pub const SDL_JOYSTICK_TYPE_GUITAR: Int = 6;
pub const SDL_JOYSTICK_TYPE_DRUM_KIT: Int = 7;
pub const SDL_JOYSTICK_TYPE_ARCADE_PAD: Int = 8;
pub const SDL_JOYSTICK_TYPE_THROTTLE: Int = 9;
pub const SDL_JOYSTICK_TYPE_COUNT: Int = 10;

/// Typed joystick capabilities: counts + kind from the joystick getters,
/// capability flags from the properties group.  All fields are exact reads;
/// no field is approximated.
pub type Sdl3JoystickCaps = {
  axes: Int;
  buttons: Int;
  hats: Int;
  balls: Int;
  kind: Int;
  has_rumble: Bool;
  has_rumble_triggers: Bool;
  has_mono_led: Bool;
  has_rgb_led: Bool;
  has_player_led: Bool;
}

/// SDL_GetJoystickProperties -> properties id (0 on failure).  The id backs
/// every SDL_PROP_JOYSTICK_CAP_* read below.
/// Complexity: O(1).
pub fn sdl3_joystick_properties(lib: &Sdl3Library, joy: Int) -> Int
  requires: lib.handle != 0
  requires: joy != 0
{
  unsafe {
    let f = lib.p_get_joystick_properties as fn(Int) -> UInt32;
    return f(joy) as Int;
  }
}

/// SDL_GetBooleanProperty(props, name, fallback) -> bool.
/// Complexity: O(len(name)).
pub fn sdl3_property_bool(lib: &Sdl3Library, props: Int, name: Str, fallback: Bool) -> Bool
  requires: lib.handle != 0
  requires: props != 0
  requires: name.len() > 0
{
  unsafe {
    let f = lib.p_get_boolean_property as fn(Int, *UInt8, UInt8) -> UInt8;
    let dv: UInt8 = if fallback { 1 as UInt8 } else { 0 as UInt8 };
    return (f(props, name.c_str(), dv) as Int) != 0;
  }
}

/// SDL_SetBooleanProperty(props, name, value) -> bool.  Writes a property on
/// a properties group SDL returned (e.g. instrumenting a capability read);
/// SDL's own cap flags are set by the device open path.
/// Complexity: O(len(name)).
pub fn sdl3_set_boolean_property(lib: &Sdl3Library, props: Int, name: Str, value: Bool) -> Bool
  requires: lib.handle != 0
  requires: props != 0
  requires: name.len() > 0
{
  unsafe {
    let f = lib.p_set_boolean_property as fn(Int, *UInt8, UInt8) -> UInt8;
    let v: UInt8 = if value { 1 as UInt8 } else { 0 as UInt8 };
    return (f(props, name.c_str(), v) as Int) != 0;
  }
}

fn sdl3_joystick_cap_flag(lib: &Sdl3Library, joy: Int, name: Str) -> Bool
  requires: lib.handle != 0
  requires: joy != 0
{
  let props = sdl3_joystick_properties(lib, joy);
  if props == 0 { return false; }
  return sdl3_property_bool(lib, props, name, false);
}

/// Has left/right rumble (`SDL.joystick.cap.rumble`).
/// Complexity: O(1).
pub fn sdl3_joystick_has_rumble(lib: &Sdl3Library, joy: Int) -> Bool
  requires: lib.handle != 0
  requires: joy != 0
{
  return sdl3_joystick_cap_flag(lib, joy, SDL_PROP_JOYSTICK_CAP_RUMBLE_BOOLEAN);
}

/// Has simple trigger rumble (`SDL.joystick.cap.trigger_rumble`).
/// Complexity: O(1).
pub fn sdl3_joystick_has_rumble_triggers(lib: &Sdl3Library, joy: Int) -> Bool
  requires: lib.handle != 0
  requires: joy != 0
{
  return sdl3_joystick_cap_flag(lib, joy, SDL_PROP_JOYSTICK_CAP_TRIGGER_RUMBLE_BOOLEAN);
}

/// Has a mono LED (`SDL.joystick.cap.mono_led`).
/// Complexity: O(1).
pub fn sdl3_joystick_has_mono_led(lib: &Sdl3Library, joy: Int) -> Bool
  requires: lib.handle != 0
  requires: joy != 0
{
  return sdl3_joystick_cap_flag(lib, joy, SDL_PROP_JOYSTICK_CAP_MONO_LED_BOOLEAN);
}

/// Has an RGB LED (`SDL.joystick.cap.rgb_led`).
/// Complexity: O(1).
pub fn sdl3_joystick_has_rgb_led(lib: &Sdl3Library, joy: Int) -> Bool
  requires: lib.handle != 0
  requires: joy != 0
{
  return sdl3_joystick_cap_flag(lib, joy, SDL_PROP_JOYSTICK_CAP_RGB_LED_BOOLEAN);
}

/// Has a player LED (`SDL.joystick.cap.player_led`).
/// Complexity: O(1).
pub fn sdl3_joystick_has_player_led(lib: &Sdl3Library, joy: Int) -> Bool
  requires: lib.handle != 0
  requires: joy != 0
{
  return sdl3_joystick_cap_flag(lib, joy, SDL_PROP_JOYSTICK_CAP_PLAYER_LED_BOOLEAN);
}

/// SDL_GetNumJoystickAxes.
/// Complexity: O(1).
pub fn sdl3_joystick_num_axes(lib: &Sdl3Library, joy: Int) -> Int
  requires: lib.handle != 0
  requires: joy != 0
{
  unsafe {
    let f = lib.p_get_num_joystick_axes as fn(Int) -> Int32;
    return f(joy) as Int;
  }
}

/// SDL_GetNumJoystickButtons.
/// Complexity: O(1).
pub fn sdl3_joystick_num_buttons(lib: &Sdl3Library, joy: Int) -> Int
  requires: lib.handle != 0
  requires: joy != 0
{
  unsafe {
    let f = lib.p_get_num_joystick_buttons as fn(Int) -> Int32;
    return f(joy) as Int;
  }
}

/// SDL_GetNumJoystickHats.
/// Complexity: O(1).
pub fn sdl3_joystick_num_hats(lib: &Sdl3Library, joy: Int) -> Int
  requires: lib.handle != 0
  requires: joy != 0
{
  unsafe {
    let f = lib.p_get_num_joystick_hats as fn(Int) -> Int32;
    return f(joy) as Int;
  }
}

/// SDL_GetNumJoystickBalls.
/// Complexity: O(1).
pub fn sdl3_joystick_num_balls(lib: &Sdl3Library, joy: Int) -> Int
  requires: lib.handle != 0
  requires: joy != 0
{
  unsafe {
    let f = lib.p_get_num_joystick_balls as fn(Int) -> Int32;
    return f(joy) as Int;
  }
}

/// SDL_GetJoystickType -> SDL_JOYSTICK_TYPE_* (unknown = 0).
/// Complexity: O(1).
pub fn sdl3_joystick_type(lib: &Sdl3Library, joy: Int) -> Int
  requires: lib.handle != 0
  requires: joy != 0
{
  unsafe {
    let f = lib.p_get_joystick_type as fn(Int) -> Int32;
    return f(joy) as Int;
  }
}

/// One typed caps record for a joystick: counts + kind + the five
/// capability flags (see Sdl3JoystickCaps).
/// Complexity: O(1).
pub fn sdl3_joystick_caps(lib: &Sdl3Library, joy: Int) -> Sdl3JoystickCaps
  requires: lib.handle != 0
  requires: joy != 0
{
  return Sdl3JoystickCaps{
    axes: sdl3_joystick_num_axes(lib, joy);
    buttons: sdl3_joystick_num_buttons(lib, joy);
    hats: sdl3_joystick_num_hats(lib, joy);
    balls: sdl3_joystick_num_balls(lib, joy);
    kind: sdl3_joystick_type(lib, joy);
    has_rumble: sdl3_joystick_has_rumble(lib, joy);
    has_rumble_triggers: sdl3_joystick_has_rumble_triggers(lib, joy);
    has_mono_led: sdl3_joystick_has_mono_led(lib, joy);
    has_rgb_led: sdl3_joystick_has_rgb_led(lib, joy);
    has_player_led: sdl3_joystick_has_player_led(lib, joy);
  };
}

// =========================================================================
// 0.19.0: haptic wave forms (SDL_haptic.h, engine ask REL-20261013-2324)
//
// SDL_HapticEffect is a 72-byte x64 union (sizeof pinned by the generator's
// Win64 layout audit; cross-checked with a clang offsetof probe on the same
// headers).  The wave-form members are SDL_HapticPeriodic:
//   type u16 @0, direction{ type u8 @4, dir[3] s32 @8/12/16 },
//   length u32 @20, delay u16 @24, button u16 @26, interval u16 @28,
//   period u16 @30, magnitude s16 @32, offset s16 @34, phase u16 @36,
//   attack_length u16 @38, attack_level u16 @40, fade_length u16 @42,
//   fade_level u16 @44.
// sdl3_haptic_encode_periodic validates + writes the slot with byte-indexed
// stores (B-16/B-17); the create/update/run/stop wrappers return typed
// Sdl3HapticError (kind + SDL_GetError message) instead of silent false.
// =========================================================================

/// SDL_HAPTIC_INFINITY (u32 max): duration for a forever effect.
pub const SDL_HAPTIC_INFINITY: Int = 4294967295;
/// Wave-form effect types (SDL_HapticEffectType).
pub const SDL_HAPTIC_SINE: Int = 2;
pub const SDL_HAPTIC_SQUARE: Int = 4;
pub const SDL_HAPTIC_TRIANGLE: Int = 8;
pub const SDL_HAPTIC_SAWTOOTHUP: Int = 16;
pub const SDL_HAPTIC_SAWTOOTHDOWN: Int = 32;
/// Direction encodings (SDL_HapticDirectionType).
pub const SDL_HAPTIC_POLAR: Int = 0;
pub const SDL_HAPTIC_CARTESIAN: Int = 1;
pub const SDL_HAPTIC_SPHERICAL: Int = 2;
/// sizeof(SDL_HapticEffect) on Win64 (MSVC x64): the owned effect-slot size.
pub const SDL_HAPTIC_EFFECT_SIZE: Int = 72;

/// Typed haptic error kinds (the message carries SDL_GetError()).
pub const SDL3_HAPTIC_ERR_PARAM: Int = 0;
pub const SDL3_HAPTIC_ERR_OPEN: Int = 1;
pub const SDL3_HAPTIC_ERR_CREATE: Int = 2;
pub const SDL3_HAPTIC_ERR_UPDATE: Int = 3;
pub const SDL3_HAPTIC_ERR_RUN: Int = 4;
pub const SDL3_HAPTIC_ERR_STOP: Int = 5;

pub type Sdl3HapticError = {
  kind: Int;
  message: Str;
}

/// Parameters of an SDL_HapticPeriodic wave-form effect.  Time values are
/// milliseconds; magnitudes are signed -32768..32767; phase is in hundredths
/// of a degree; the direction follows SDL_HapticDirection (dir[3]).
pub type Sdl3HapticPeriodic = {
  wave: Int;
  length: Int;
  period: Int;
  magnitude: Int;
  offset: Int;
  phase: Int;
  attack_length: Int;
  attack_level: Int;
  fade_length: Int;
  fade_level: Int;
  dir_type: Int;
  dir0: Int;
  dir1: Int;
  dir2: Int;
}

fn sdl3_haptic_err(kind: Int, message: Str) -> Sdl3HapticError {
  return Sdl3HapticError{ kind: kind; message: message };
}

/// Validate + encode a periodic wave-form effect into a caller-owned
/// SDL_HAPTIC_EFFECT_SIZE slot (byte-indexed stores; delay/button/interval
/// are encoded as 0 = trigger-less).  Err(kind = SDL3_HAPTIC_ERR_PARAM) on
/// out-of-range or unknown parameters; the slot is untouched in that case.
/// Complexity: O(1).
pub fn sdl3_haptic_encode_periodic(slot: &mut Vec[UInt8], eff: Sdl3HapticPeriodic) -> Result[Unit, Sdl3HapticError] {
  if slot.len() < SDL_HAPTIC_EFFECT_SIZE {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_PARAM, "effect slot must be >= SDL_HAPTIC_EFFECT_SIZE"));
  }
  let wave_ok = eff.wave == SDL_HAPTIC_SINE || eff.wave == SDL_HAPTIC_SQUARE
    || eff.wave == SDL_HAPTIC_TRIANGLE || eff.wave == SDL_HAPTIC_SAWTOOTHUP
    || eff.wave == SDL_HAPTIC_SAWTOOTHDOWN;
  if !wave_ok {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_PARAM, "wave must be SDL_HAPTIC_SINE/SQUARE/TRIANGLE/SAWTOOTHUP/SAWTOOTHDOWN"));
  }
  let dir_ok = eff.dir_type == SDL_HAPTIC_POLAR || eff.dir_type == SDL_HAPTIC_CARTESIAN
    || eff.dir_type == SDL_HAPTIC_SPHERICAL;
  if !dir_ok {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_PARAM, "dir_type must be SDL_HAPTIC_POLAR/CARTESIAN/SPHERICAL"));
  }
  if eff.length < 0 || eff.length > SDL_HAPTIC_INFINITY {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_PARAM, "length out of u32 range"));
  }
  if eff.period < 0 || eff.period > 65535 {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_PARAM, "period out of u16 range"));
  }
  if eff.magnitude < -32768 || eff.magnitude > 32767 {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_PARAM, "magnitude out of s16 range"));
  }
  if eff.offset < -32768 || eff.offset > 32767 {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_PARAM, "offset out of s16 range"));
  }
  if eff.phase < 0 || eff.phase > 65535 {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_PARAM, "phase out of u16 range"));
  }
  if eff.attack_length < 0 || eff.attack_length > 65535 || eff.attack_level < 0 || eff.attack_level > 65535 {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_PARAM, "attack out of u16 range"));
  }
  if eff.fade_length < 0 || eff.fade_length > 65535 || eff.fade_level < 0 || eff.fade_level > 65535 {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_PARAM, "fade out of u16 range"));
  }
  sdl3_write_u16_le(slot, 0, eff.wave);
  slot[4] = (eff.dir_type & 0xFF) as UInt8;
  sdl3_write_u32_le(slot, 8, eff.dir0 & 0xFFFFFFFF);
  sdl3_write_u32_le(slot, 12, eff.dir1 & 0xFFFFFFFF);
  sdl3_write_u32_le(slot, 16, eff.dir2 & 0xFFFFFFFF);
  sdl3_write_u32_le(slot, 20, eff.length & 0xFFFFFFFF);
  sdl3_write_u16_le(slot, 30, eff.period);
  sdl3_write_u16_le(slot, 32, eff.magnitude & 0xFFFF);
  sdl3_write_u16_le(slot, 34, eff.offset & 0xFFFF);
  sdl3_write_u16_le(slot, 36, eff.phase);
  sdl3_write_u16_le(slot, 38, eff.attack_length);
  sdl3_write_u16_le(slot, 40, eff.attack_level);
  sdl3_write_u16_le(slot, 42, eff.fade_length);
  sdl3_write_u16_le(slot, 44, eff.fade_level);
  return Ok(());
}

/// SDL_GetHaptics count (array freed via SDL_free).  Requires
/// SDL_INIT_HAPTIC.
/// Complexity: O(devices).
pub fn sdl3_haptic_count(lib: &Sdl3Library) -> Int
  requires: lib.handle != 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = lib.p_get_haptics as fn(*UInt8) -> Int;
    let arr = f(slot.as_mut_ptr());
    let n = sdl3_read_u32(&slot);
    if arr != 0 {
      let fr = lib.p_free as fn(Int);
      fr(arr);
    }
    return n;
  }
}

/// i-th haptic device id (0 when out of range; array freed via SDL_free).
/// Complexity: O(devices).
pub fn sdl3_haptic_at(lib: &Sdl3Library, i: Int) -> Int
  requires: lib.handle != 0
  requires: i >= 0
{
  unsafe {
    var slot = sdl3_slot4();
    let f = lib.p_get_haptics as fn(*UInt8) -> Int;
    let arr = f(slot.as_mut_ptr());
    let n = sdl3_read_u32(&slot);
    var id = 0;
    if arr != 0 {
      if i < n {
        id = ffi.ptr_read_u32_le((arr + i * 4) as *UInt8);
      }
      let fr = lib.p_free as fn(Int);
      fr(arr);
    }
    return id;
  }
}

/// SDL_GetHapticNameForID (SDL-owned string, copied; "" for unknown ids).
/// Complexity: O(len).
pub fn sdl3_haptic_name_for_id(lib: &Sdl3Library, id: Int) -> Str
  requires: lib.handle != 0
  requires: id > 0
{
  unsafe {
    let f = lib.p_get_haptic_name_for_id as fn(Int) -> *UInt8;
    let p = f(id);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// SDL_GetHapticFromID -> handle (0 when the id is not openable).
/// Complexity: O(1).
pub fn sdl3_haptic_from_id(lib: &Sdl3Library, id: Int) -> Int
  requires: lib.handle != 0
  requires: id > 0
{
  unsafe {
    let f = lib.p_get_haptic_from_id as fn(Int) -> Int;
    return f(id);
  }
}

/// SDL_GetHapticName (SDL-owned string, copied; "" on failure).
/// Complexity: O(len).
pub fn sdl3_haptic_name(lib: &Sdl3Library, haptic: Int) -> Str
  requires: lib.handle != 0
  requires: haptic != 0
{
  unsafe {
    let f = lib.p_get_haptic_name as fn(Int) -> *UInt8;
    let p = f(haptic);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// SDL_OpenHaptic(id) -> handle.  Err(kind = SDL3_HAPTIC_ERR_OPEN) carries
/// the SDL error string (not-haptic device, no SDL_INIT_HAPTIC, ...).
/// Complexity: O(device open).
pub fn sdl3_haptic_open(lib: &Sdl3Library, id: Int) -> Result[Int, Sdl3HapticError]
  requires: lib.handle != 0
  requires: id > 0
{
  unsafe {
    let f = lib.p_open_haptic as fn(Int) -> Int;
    let h = f(id);
    if h == 0 {
      return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_OPEN, sdl3_get_error(lib)));
    }
    return Ok(h);
  }
}

/// SDL_CloseHaptic.
/// Complexity: O(1).
pub fn sdl3_haptic_close(lib: &Sdl3Library, haptic: Int)
  requires: lib.handle != 0
  requires: haptic != 0
{
  unsafe {
    let f = lib.p_close_haptic as fn(Int);
    f(haptic);
  }
}

/// SDL_IsJoystickHaptic.
/// Complexity: O(1).
pub fn sdl3_is_joystick_haptic(lib: &Sdl3Library, joy: Int) -> Bool
  requires: lib.handle != 0
  requires: joy != 0
{
  unsafe {
    let f = lib.p_is_joystick_haptic as fn(Int) -> UInt8;
    return (f(joy) as Int) != 0;
  }
}

/// SDL_OpenHapticFromJoystick -> handle.  Err(kind = SDL3_HAPTIC_ERR_OPEN)
/// when the joystick is not haptic (the engine's device-selection probe).
/// Complexity: O(1).
pub fn sdl3_open_haptic_from_joystick(lib: &Sdl3Library, joy: Int) -> Result[Int, Sdl3HapticError]
  requires: lib.handle != 0
  requires: joy != 0
{
  unsafe {
    let f = lib.p_open_haptic_from_joystick as fn(Int) -> Int;
    let h = f(joy);
    if h == 0 {
      return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_OPEN, sdl3_get_error(lib)));
    }
    return Ok(h);
  }
}

/// SDL_GetHapticFeatures (SDL_HAPTIC_* mask of supported effect classes).
/// Complexity: O(1).
pub fn sdl3_haptic_features(lib: &Sdl3Library, haptic: Int) -> Int
  requires: lib.handle != 0
  requires: haptic != 0
{
  unsafe {
    let f = lib.p_get_haptic_features as fn(Int) -> UInt32;
    return f(haptic) as Int;
  }
}

/// SDL_GetMaxHapticEffects.
/// Complexity: O(1).
pub fn sdl3_haptic_max_effects(lib: &Sdl3Library, haptic: Int) -> Int
  requires: lib.handle != 0
  requires: haptic != 0
{
  unsafe {
    let f = lib.p_get_max_haptic_effects as fn(Int) -> Int32;
    return f(haptic) as Int;
  }
}

/// SDL_GetMaxHapticEffectsPlaying.
/// Complexity: O(1).
pub fn sdl3_haptic_max_effects_playing(lib: &Sdl3Library, haptic: Int) -> Int
  requires: lib.handle != 0
  requires: haptic != 0
{
  unsafe {
    let f = lib.p_get_max_haptic_effects_playing as fn(Int) -> Int32;
    return f(haptic) as Int;
  }
}

/// SDL_GetNumHapticAxes.
/// Complexity: O(1).
pub fn sdl3_haptic_num_axes(lib: &Sdl3Library, haptic: Int) -> Int
  requires: lib.handle != 0
  requires: haptic != 0
{
  unsafe {
    let f = lib.p_get_num_haptic_axes as fn(Int) -> Int32;
    return f(haptic) as Int;
  }
}

/// SDL_HapticEffectSupported(haptic, slot) -> bool: probe a slot encoded by
/// sdl3_haptic_encode_periodic before creating it.
/// Complexity: O(1).
pub fn sdl3_haptic_effect_supported(lib: &Sdl3Library, haptic: Int, slot: &mut Vec[UInt8]) -> Bool
  requires: lib.handle != 0
  requires: haptic != 0
  requires: slot.len() >= SDL_HAPTIC_EFFECT_SIZE
{
  unsafe {
    let f = lib.p_haptic_effect_supported as fn(Int, *UInt8) -> UInt8;
    return (f(haptic, slot.as_mut_ptr()) as Int) != 0;
  }
}

/// Encode + SDL_CreateHapticEffect -> effect id.  Err(kind =
/// SDL3_HAPTIC_ERR_PARAM) for bad parameters, (kind = SDL3_HAPTIC_ERR_CREATE)
/// when SDL rejects the effect (message = SDL_GetError()).
/// Complexity: O(1).
pub fn sdl3_haptic_create_periodic(lib: &Sdl3Library, haptic: Int, eff: Sdl3HapticPeriodic) -> Result[Int, Sdl3HapticError]
  requires: lib.handle != 0
  requires: haptic != 0
{
  var slot = sdl3_slot(SDL_HAPTIC_EFFECT_SIZE);
  let enc = sdl3_haptic_encode_periodic(&mut slot, eff);
  if !enc.is_ok { return Err(enc.error); }
  var id: Int = -1;
  unsafe {
    let f = lib.p_create_haptic_effect as fn(Int, *UInt8) -> Int32;
    id = f(haptic, slot.as_mut_ptr()) as Int;
  }
  if id < 0 {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_CREATE, sdl3_get_error(lib)));
  }
  return Ok(id);
}

/// Encode + SDL_UpdateHapticEffect(effect, eff).  Typed errors as above.
/// Complexity: O(1).
pub fn sdl3_haptic_update_periodic(lib: &Sdl3Library, haptic: Int, effect_id: Int, eff: Sdl3HapticPeriodic) -> Result[Unit, Sdl3HapticError]
  requires: lib.handle != 0
  requires: haptic != 0
  requires: effect_id >= 0
{
  var slot = sdl3_slot(SDL_HAPTIC_EFFECT_SIZE);
  let enc = sdl3_haptic_encode_periodic(&mut slot, eff);
  if !enc.is_ok { return Err(enc.error); }
  var ok: Bool = false;
  unsafe {
    let f = lib.p_update_haptic_effect as fn(Int, Int, *UInt8) -> UInt8;
    ok = (f(haptic, effect_id, slot.as_mut_ptr()) as Int) != 0;
  }
  if !ok {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_UPDATE, sdl3_get_error(lib)));
  }
  return Ok(());
}

/// SDL_RunHapticEffect(effect, iterations).  iterations = SDL_HAPTIC_INFINITY
/// runs until stopped.
/// Complexity: O(1).
pub fn sdl3_haptic_run(lib: &Sdl3Library, haptic: Int, effect_id: Int, iterations: Int) -> Result[Unit, Sdl3HapticError]
  requires: lib.handle != 0
  requires: haptic != 0
  requires: effect_id >= 0
  requires: iterations >= 0
{
  var ok: Bool = false;
  unsafe {
    let f = lib.p_run_haptic_effect as fn(Int, Int, Int) -> UInt8;
    ok = (f(haptic, effect_id, iterations) as Int) != 0;
  }
  if !ok {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_RUN, sdl3_get_error(lib)));
  }
  return Ok(());
}

/// SDL_GetHapticEffectStatus -> bool.
/// Complexity: O(1).
pub fn sdl3_haptic_status(lib: &Sdl3Library, haptic: Int, effect_id: Int) -> Bool
  requires: lib.handle != 0
  requires: haptic != 0
  requires: effect_id >= 0
{
  unsafe {
    let f = lib.p_get_haptic_effect_status as fn(Int, Int) -> UInt8;
    return (f(haptic, effect_id) as Int) != 0;
  }
}

/// SDL_StopHapticEffect(effect).  Typed error on failure.
/// Complexity: O(1).
pub fn sdl3_haptic_stop(lib: &Sdl3Library, haptic: Int, effect_id: Int) -> Result[Unit, Sdl3HapticError]
  requires: lib.handle != 0
  requires: haptic != 0
  requires: effect_id >= 0
{
  var ok: Bool = false;
  unsafe {
    let f = lib.p_stop_haptic_effect as fn(Int, Int) -> UInt8;
    ok = (f(haptic, effect_id) as Int) != 0;
  }
  if !ok {
    return Err(sdl3_haptic_err(SDL3_HAPTIC_ERR_STOP, sdl3_get_error(lib)));
  }
  return Ok(());
}

/// SDL_DestroyHapticEffect(effect).
/// Complexity: O(1).
pub fn sdl3_haptic_destroy(lib: &Sdl3Library, haptic: Int, effect_id: Int)
  requires: lib.handle != 0
  requires: haptic != 0
  requires: effect_id >= 0
{
  unsafe {
    let f = lib.p_destroy_haptic_effect as fn(Int, Int);
    f(haptic, effect_id);
  }
}

/// SDL_HapticRumbleSupported.
/// Complexity: O(1).
pub fn sdl3_haptic_rumble_supported(lib: &Sdl3Library, haptic: Int) -> Bool
  requires: lib.handle != 0
  requires: haptic != 0
{
  unsafe {
    let f = lib.p_haptic_rumble_supported as fn(Int) -> UInt8;
    return (f(haptic) as Int) != 0;
  }
}

/// SDL_InitHapticRumble.
/// Complexity: O(1).
pub fn sdl3_haptic_init_rumble(lib: &Sdl3Library, haptic: Int) -> Bool
  requires: lib.handle != 0
  requires: haptic != 0
{
  unsafe {
    let f = lib.p_init_haptic_rumble as fn(Int) -> UInt8;
    return (f(haptic) as Int) != 0;
  }
}

/// SDL_PlayHapticRumble(strength 0..1, length_ms).
/// Complexity: O(1).
pub fn sdl3_haptic_play_rumble(lib: &Sdl3Library, haptic: Int, strength: Float64, length_ms: Int) -> Bool
  requires: lib.handle != 0
  requires: haptic != 0
  requires: strength >= 0.0
  requires: strength <= 1.0
  requires: length_ms >= 0
{
  unsafe {
    let v_strength: Float32 = strength as Float32;
    let f = lib.p_play_haptic_rumble as fn(Int, Float32, Int) -> UInt8;
    return (f(haptic, v_strength, length_ms) as Int) != 0;
  }
}

/// SDL_StopHapticRumble.
/// Complexity: O(1).
pub fn sdl3_haptic_stop_rumble(lib: &Sdl3Library, haptic: Int) -> Bool
  requires: lib.handle != 0
  requires: haptic != 0
{
  unsafe {
    let f = lib.p_stop_haptic_rumble as fn(Int) -> UInt8;
    return (f(haptic) as Int) != 0;
  }
}

// =========================================================================
// 0.19.0: PEN/TABLET decoding path (engine ask REL-20261013-2324)
//
// SDL_PenProximityEvent / SDL_PenMotionEvent / SDL_PenTouchEvent /
// SDL_PenButtonEvent layouts pinned to the 3.4.8 header (Win64 sizes 24/40/
// 40/40; the generator's layout audit gates the offsets): every pen event
// carries type u32 @0, reserved u32 @4, timestamp u64 @8, windowID u32 @16,
// which (pen instance id) u32 @20; motion/touch/button continue with
// pen_state u32 @24 (SDL_PEN_INPUT_* mask), x f32 @28, y f32 @32; touch:
// eraser u8 @36, down u8 @37; button: button u8 @36, down u8 @37.
// SDL_EVENT_PEN_DOWN/UP are the "touched/lifted" pair (eraser flag included);
// proximity in/out decode to the same windowID/which pair.  Tool type is a
// typed query: sdl3_pen_device_type (SDL_GetPenDeviceType; INVALID for a
// stale/unknown pen id).  All decoders are pure XIOM buffer reads and run
// with or without the DLL (0.18.0 readback route).
// =========================================================================

/// SDL_PenDeviceType values.
pub const SDL_PEN_DEVICE_TYPE_INVALID: Int = -1;
pub const SDL_PEN_DEVICE_TYPE_UNKNOWN: Int = 0;
pub const SDL_PEN_DEVICE_TYPE_DIRECT: Int = 1;
pub const SDL_PEN_DEVICE_TYPE_INDIRECT: Int = 2;

/// SDL_PenInputFlags bits (the `pen_state` field of motion/touch/button
/// events).
pub const SDL_PEN_INPUT_DOWN: Int = 1;
pub const SDL_PEN_INPUT_BUTTON_1: Int = 2;
pub const SDL_PEN_INPUT_BUTTON_2: Int = 4;
pub const SDL_PEN_INPUT_BUTTON_3: Int = 8;
pub const SDL_PEN_INPUT_BUTTON_4: Int = 16;
pub const SDL_PEN_INPUT_BUTTON_5: Int = 32;
pub const SDL_PEN_INPUT_ERASER_TIP: Int = 1073741824;
pub const SDL_PEN_INPUT_IN_PROXIMITY: Int = 2147483648;

/// SDL_GetPenDeviceType -> SDL_PEN_DEVICE_TYPE_*; INVALID (-1) for an
/// unknown/stale pen instance id (callers treat that as "no tablet").
/// Complexity: O(1).
pub fn sdl3_pen_device_type(lib: &Sdl3Library, id: Int) -> Int
  requires: lib.handle != 0
  requires: id > 0
{
  unsafe {
    let f = lib.p_get_pen_device_type as fn(Int) -> Int32;
    return f(id) as Int;
  }
}

/// Pen event: windowID (u32 @16; shared by all pen event members).
/// Complexity: O(1).
pub fn sdl3_event_pen_window_id(ev: &Vec[UInt8]) -> Int
  requires: ev.len() >= 20
{
  return ev_read_u32(ev, 16);
}

/// Pen event: `which` = pen instance id (u32 @20; proximity/motion/touch/
/// button all carry it).  Feed it to sdl3_pen_device_type for the tool type.
/// Complexity: O(1).
pub fn sdl3_event_pen_which(ev: &Vec[UInt8]) -> Int
  requires: ev.len() >= 24
{
  return ev_read_u32(ev, 20);
}

/// Pen motion/touch/button event: complete input state at event time
/// (u32 @24; mask of SDL_PEN_INPUT_*).  Proximity events have no state:
/// requires len >= 28, callers use it on motion/touch/button members only.
/// Complexity: O(1).
pub fn sdl3_event_pen_state(ev: &Vec[UInt8]) -> Int
  requires: ev.len() >= 28
{
  return ev_read_u32(ev, 24);
}

/// Pen event: x as raw f32 bits (u32 @28).
/// Complexity: O(1).
pub fn sdl3_event_pen_x_bits(ev: &Vec[UInt8]) -> Int
  requires: ev.len() >= 32
{
  return ev_read_u32(ev, 28);
}

/// Pen event: y as raw f32 bits (u32 @32).
/// Complexity: O(1).
pub fn sdl3_event_pen_y_bits(ev: &Vec[UInt8]) -> Int
  requires: ev.len() >= 36
{
  return ev_read_u32(ev, 32);
}

/// Pen event: x (f32 @28, window-relative) as Float64.
/// Complexity: O(1).
pub fn sdl3_event_pen_x(ev: &Vec[UInt8]) -> Float64
  requires: ev.len() >= 32
{
  return sdl3_f32_from_bits(ev_read_u32(ev, 28));
}

/// Pen event: y (f32 @32, window-relative) as Float64.
/// Complexity: O(1).
pub fn sdl3_event_pen_y(ev: &Vec[UInt8]) -> Float64
  requires: ev.len() >= 36
{
  return sdl3_f32_from_bits(ev_read_u32(ev, 32));
}

/// Pen TOUCH event (SDL_EVENT_PEN_DOWN/PEN_UP): eraser tip active (u8 @36).
/// Complexity: O(1).
pub fn sdl3_event_pen_touch_eraser(ev: &Vec[UInt8]) -> Bool
  requires: ev.len() >= 37
{
  return ev_read_u8(ev, 36) != 0;
}

/// Pen TOUCH event: pen touching the surface (u8 @37; true for PEN_DOWN,
/// false for PEN_UP).
/// Complexity: O(1).
pub fn sdl3_event_pen_touch_down(ev: &Vec[UInt8]) -> Bool
  requires: ev.len() >= 38
{
  return ev_read_u8(ev, 37) != 0;
}

/// Pen BUTTON event: button index (u8 @36; first pen button is 1).
/// Complexity: O(1).
pub fn sdl3_event_pen_button(ev: &Vec[UInt8]) -> Int
  requires: ev.len() >= 37
{
  return ev_read_u8(ev, 36);
}

/// Pen BUTTON event: pressed flag (u8 @37).
/// Complexity: O(1).
pub fn sdl3_event_pen_button_down(ev: &Vec[UInt8]) -> Bool
  requires: ev.len() >= 38
{
  return ev_read_u8(ev, 37) != 0;
}

// =========================================================================
// 0.21.0: UI platform surface (engine ask REL-20261021-1652-engine-5, A14)
//
// Window identity/geometry, per-window focus + DPI-change routing, text
// input/IME and clipboard, all by function over the pinned 3.4.8 ABI.
// Window-scoped calls live on the resource loader (they take SDL_Window*);
// global clipboard and display enumeration live on the core loader.  Every
// out-param gets its own owned slot (B-17): no pointer arithmetic reaches a
// foreign call.  Float returns were re-verified on v0.64.8 (B-12 fixed for
// this shape: SDL_GetWindowDisplayScale/GetDisplayContentScale read 1.0 on
// the box); event payload floats still decode through sdl3_f32_from_bits.
// =========================================================================

pub const SDL3_WINDOW_FOCUS_NONE: Int = 0;
pub const SDL3_WINDOW_FOCUS_GAINED: Int = 1;
pub const SDL3_WINDOW_FOCUS_LOST: Int = 2;

pub const SDL3_DPI_CHANGE_NONE: Int = 0;
pub const SDL3_DPI_CHANGE_PIXEL_SIZE: Int = 1;
pub const SDL3_DPI_CHANGE_DISPLAY: Int = 2;
pub const SDL3_DPI_CHANGE_DISPLAY_SCALE: Int = 3;

/// Package-level text event kinds.  SDL3 has no dedicated
/// `SDL_EVENT_TEXT_EDITING_CANCELLED`: cancellation is delivered as a
/// normal `SDL_EVENT_TEXT_EDITING` whose preedit text is empty (or NULL);
/// `sdl3_event_text_kind` classifies that case as CANCELLED so consumers
/// get a typed cancellation signal without inventing an SDL event type.
pub const SDL3_TEXT_EVENT_NONE: Int = 0;
pub const SDL3_TEXT_EVENT_EDITING: Int = 1;
pub const SDL3_TEXT_EVENT_COMMIT: Int = 2;
pub const SDL3_TEXT_EVENT_CANCELLED: Int = 3;

pub type Sdl3WindowPosition = {
  ok: Bool;
  x: Int;
  y: Int;
}

pub type Sdl3PixelSize = {
  ok: Bool;
  width: Int;
  height: Int;
}

pub type Sdl3TextInputArea = {
  ok: Bool;
  x: Int;
  y: Int;
  w: Int;
  h: Int;
  cursor: Int;
}

/// Typed focus routing: `state` is SDL3_WINDOW_FOCUS_* and `window_id` is
/// the SDL window id carried at event offset 16 (0 for non-focus events).
pub type Sdl3WindowFocus = {
  state: Int;
  window_id: Int;
}

/// Typed DPI-change routing.  `reason` is SDL3_DPI_CHANGE_*:
/// PIXEL_SIZE -> pixel_width/pixel_height; DISPLAY -> display_id;
/// DISPLAY_SCALE -> the window's display scale changed (query it with
/// sdl3_window_display_scale).
pub type Sdl3DpiChange = {
  reason: Int;
  window_id: Int;
  display_id: Int;
  pixel_width: Int;
  pixel_height: Int;
}

/// SDL_TextEditingEvent decode (Win64 layout: text ptr @24, start i32 @32,
/// length i32 @36; windowID u32 @16).  `text` is the preedit/composition
/// string; `start`/`length` are UTF-8 character offsets into it (-1 when
/// unset).  The pointer is SDL-owned and only valid for the event delivery.
pub type Sdl3TextEditing = {
  window_id: Int;
  text: Str;
  start: Int;
  length: Int;
}

/// SDL_GetWindowID -> SDL_WindowID (0 for an invalid window).
/// Complexity: O(1).
pub fn sdl3_window_id(r: &Sdl3Resources, win: Int) -> Int
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_get_window_id as fn(Int) -> Int32;
    return f(win) as Int;
  }
}

/// SDL_GetWindowFromID -> SDL_Window* handle (0 when the id is stale).
/// Complexity: O(1).
pub fn sdl3_window_from_id(r: &Sdl3Resources, id: Int) -> Int
  requires: r.handle != 0
  requires: id > 0
{
  unsafe {
    let f = r.p_get_window_from_id as fn(Int) -> Int;
    return f(id);
  }
}

/// SDL_GetWindowPosition -> Sdl3WindowPosition (ok=false + 0,0 on failure).
/// Coordinates are in the virtual desktop space.
/// Complexity: O(1).
pub fn sdl3_window_position(r: &Sdl3Resources, win: Int) -> Sdl3WindowPosition
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    var sx = sdl3_slot4();
    var sy = sdl3_slot4();
    let f = r.p_get_window_position as fn(Int, *UInt8, *UInt8) -> UInt8;
    let ok = (f(win, sx.as_mut_ptr(), sy.as_mut_ptr()) as Int) != 0;
    if !ok {
      return Sdl3WindowPosition{ ok: false; x: 0; y: 0 };
    }
    return Sdl3WindowPosition{
      ok: true;
      x: sdl3_read_i32_at(&sx, 0);
      y: sdl3_read_i32_at(&sy, 0);
    };
  }
}

/// SDL_SetWindowPosition (virtual desktop coordinates) -> bool.  A
/// WINDOW_MOVED (+ DISPLAY_CHANGED on a monitor change) event is queued.
/// Complexity: O(1).
pub fn sdl3_set_window_position(r: &Sdl3Resources, win: Int, x: Int, y: Int) -> Bool
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_set_window_position as fn(Int, Int, Int) -> UInt8;
    return (f(win, x, y) as Int) != 0;
  }
}

/// SDL_GetWindowSizeInPixels -> Sdl3PixelSize (ok=false + 0x0 on failure).
/// This is the physical framebuffer size; divide by the logical
/// sdl3_window_size to recover the DPI scale when needed.
/// Complexity: O(1).
pub fn sdl3_window_size_pixels(r: &Sdl3Resources, win: Int) -> Sdl3PixelSize
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    var sw = sdl3_slot4();
    var sh = sdl3_slot4();
    let f = r.p_get_window_size_pixels as fn(Int, *UInt8, *UInt8) -> UInt8;
    let ok = (f(win, sw.as_mut_ptr(), sh.as_mut_ptr()) as Int) != 0;
    if !ok {
      return Sdl3PixelSize{ ok: false; width: 0; height: 0 };
    }
    return Sdl3PixelSize{
      ok: true;
      width: sdl3_read_i32_at(&sw, 0);
      height: sdl3_read_i32_at(&sh, 0);
    };
  }
}

/// SDL_GetWindowDisplayScale -> window DPI scale (1.0 = 96 DPI logical;
/// 0.0 when the window is invalid).  This is the S5 cross-monitor signal;
/// pair it with SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED.
/// Complexity: O(1).
pub fn sdl3_window_display_scale(r: &Sdl3Resources, win: Int) -> Float64
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_get_window_display_scale as fn(Int) -> Float32;
    return f(win) as Float64;
  }
}

/// SDL_GetDisplayForWindow -> display id the window is on (0 on failure).
/// Use sdl3_display_index + sdl3_display_bounds for the index/bounds pair.
/// Complexity: O(1).
pub fn sdl3_window_display(r: &Sdl3Resources, win: Int) -> Int
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_get_display_for_window as fn(Int) -> Int32;
    return f(win) as Int;
  }
}

/// Index of a display id in the SDL_GetDisplays enumeration (-1 when the id
/// is not in the list).  SDL3 identifies monitors by id; this recovers the
/// index a UI/toolkit may need.
/// Complexity: O(displays^2) (the display list is fetched per probe).
pub fn sdl3_display_index(lib: &Sdl3Library, id: Int) -> Int
  requires: lib.handle != 0
  requires: id >= 0
{
  let n = sdl3_display_count(lib);
  var i = 0;
  while i < n {
    if sdl3_display_at(lib, i) == id { return i; }
    i = i + 1;
  }
  return -1;
}

/// SDL_GetDisplayContentScale -> display content scale (0.0 for an unknown
/// display).  Float return re-verified on v0.64.8.
/// Complexity: O(1).
pub fn sdl3_display_content_scale(lib: &Sdl3Library, id: Int) -> Float64
  requires: lib.handle != 0
  requires: id >= 0
{
  unsafe {
    let f = lib.p_get_display_content_scale as fn(Int) -> Float32;
    return f(id) as Float64;
  }
}

/// SDL_StartTextInput(window) -> bool: enables UTF-8 text input events and
/// the platform IME for that window.
/// Complexity: O(1).
pub fn sdl3_start_text_input(r: &Sdl3Resources, win: Int) -> Bool
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_start_text_input as fn(Int) -> UInt8;
    return (f(win) as Int) != 0;
  }
}

/// SDL_StopTextInput(window) -> bool: disables text input/IME for the
/// window (SDL also hides an on-screen keyboard it showed).
/// Complexity: O(1).
pub fn sdl3_stop_text_input(r: &Sdl3Resources, win: Int) -> Bool
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_stop_text_input as fn(Int) -> UInt8;
    return (f(win) as Int) != 0;
  }
}

/// SDL_TextInputActive(window) -> whether text input events are enabled.
/// Complexity: O(1).
pub fn sdl3_text_input_active(r: &Sdl3Resources, win: Int) -> Bool
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_text_input_active as fn(Int) -> UInt8;
    return (f(win) as Int) != 0;
  }
}

/// SDL_SetTextInputArea(window, rect, cursor) -> bool.  `rect` is the IME
/// candidate anchor in window coordinates; `cursor` is the caret offset
/// relative to rect.x (UTF-8 character units, platform dependent).  The
/// 16-byte rect slot is built with byte-indexed writes (B-16).
/// Complexity: O(1).
pub fn sdl3_set_text_input_area(r: &Sdl3Resources, win: Int, area: Sdl3Rect, cursor: Int) -> Bool
  requires: r.handle != 0
  requires: win != 0
  requires: area.w >= 0
  requires: area.h >= 0
  requires: cursor >= 0
{
  unsafe {
    var slot = sdl3_slot(16);
    sdl3_write_u32_le(&mut slot, 0, area.x);
    sdl3_write_u32_le(&mut slot, 4, area.y);
    sdl3_write_u32_le(&mut slot, 8, area.w);
    sdl3_write_u32_le(&mut slot, 12, area.h);
    let f = r.p_set_text_input_area as fn(Int, *UInt8, Int) -> UInt8;
    return (f(win, slot.as_mut_ptr(), cursor) as Int) != 0;
  }
}

/// SDL_GetTextInputArea(window, &rect, &cursor) -> Sdl3TextInputArea
/// (ok=false + zeroed fields on failure).  `cursor` is the IME caret
/// offset relative to rect.x.
/// Complexity: O(1).
pub fn sdl3_get_text_input_area(r: &Sdl3Resources, win: Int) -> Sdl3TextInputArea
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    var rect = sdl3_slot(16);
    var cursor = sdl3_slot4();
    let f = r.p_get_text_input_area as fn(Int, *UInt8, *UInt8) -> UInt8;
    let ok = (f(win, rect.as_mut_ptr(), cursor.as_mut_ptr()) as Int) != 0;
    if !ok {
      return Sdl3TextInputArea{ ok: false; x: 0; y: 0; w: 0; h: 0; cursor: 0 };
    }
    return Sdl3TextInputArea{
      ok: true;
      x: sdl3_read_i32_at(&rect, 0);
      y: sdl3_read_i32_at(&rect, 4);
      w: sdl3_read_i32_at(&rect, 8);
      h: sdl3_read_i32_at(&rect, 12);
      cursor: sdl3_read_i32_at(&cursor, 0);
    };
  }
}

/// SDL_ClearComposition(window) -> bool: dismisses the IME composition
/// window without disabling text input.
/// Complexity: O(1).
pub fn sdl3_clear_composition(r: &Sdl3Resources, win: Int) -> Bool
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_clear_composition as fn(Int) -> UInt8;
    return (f(win) as Int) != 0;
  }
}

/// SDL_SetClipboardText -> bool.  `text` is UTF-8; an empty string clears
/// the textual clipboard.  Clipboard functions take no window.
/// Complexity: O(len).
pub fn sdl3_set_clipboard_text(lib: &Sdl3Library, text: Str) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_set_clipboard_text as fn(*UInt8) -> UInt8;
    return (f(text.c_str()) as Int) != 0;
  }
}

/// SDL_GetClipboardText -> UTF-8 text ("" when empty/unavailable).  The
/// SDL-owned return is copied then freed with SDL_free.
/// Complexity: O(len).
pub fn sdl3_get_clipboard_text(lib: &Sdl3Library) -> Str
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_clipboard_text as fn() -> Int;
    let p = f();
    if p == 0 { return ""; }
    let s = Str::from_c_str(p as *UInt8);
    let fr = lib.p_free as fn(Int);
    fr(p);
    return s;
  }
}

/// SDL_HasClipboardText -> whether the clipboard holds a non-empty text.
/// Complexity: O(1).
pub fn sdl3_has_clipboard_text(lib: &Sdl3Library) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_has_clipboard_text as fn() -> UInt8;
    return (f() as Int) != 0;
  }
}

/// SDL_SetPrimarySelectionText -> bool.  Where the platform has no primary
/// selection (e.g. Windows), SDL returns false and sets an error string:
/// that is the typed-unsupported path consumers fall back from.
/// Complexity: O(len).
pub fn sdl3_set_primary_selection_text(lib: &Sdl3Library, text: Str) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_set_primary_selection_text as fn(*UInt8) -> UInt8;
    return (f(text.c_str()) as Int) != 0;
  }
}

/// SDL_GetPrimarySelectionText -> UTF-8 text ("" when empty/unsupported).
/// The SDL-owned return is copied then freed with SDL_free.
/// Complexity: O(len).
pub fn sdl3_get_primary_selection_text(lib: &Sdl3Library) -> Str
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_primary_selection_text as fn() -> Int;
    let p = f();
    if p == 0 { return ""; }
    let s = Str::from_c_str(p as *UInt8);
    let fr = lib.p_free as fn(Int);
    fr(p);
    return s;
  }
}

/// SDL_HasPrimarySelectionText -> whether the primary selection holds a
/// non-empty text (false where the platform has no primary selection).
/// Complexity: O(1).
pub fn sdl3_has_primary_selection_text(lib: &Sdl3Library) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_has_primary_selection_text as fn() -> UInt8;
    return (f() as Int) != 0;
  }
}

/// Focus routing for WINDOW_FOCUS_GAINED/LOST: window id + gained/lost.
/// Non-focus events classify as SDL3_WINDOW_FOCUS_NONE (window id still
/// decoded from offset 16).
/// Complexity: O(1).
pub fn sdl3_event_window_focus(ev: &Vec[UInt8]) -> Sdl3WindowFocus
  requires: ev.len() >= 20
{
  let t = sdl3_event_type(ev);
  let wid = sdl3_event_window_id(ev);
  if t == SDL_EVENT_WINDOW_FOCUS_GAINED {
    return Sdl3WindowFocus{ state: SDL3_WINDOW_FOCUS_GAINED; window_id: wid };
  }
  if t == SDL_EVENT_WINDOW_FOCUS_LOST {
    return Sdl3WindowFocus{ state: SDL3_WINDOW_FOCUS_LOST; window_id: wid };
  }
  return Sdl3WindowFocus{ state: SDL3_WINDOW_FOCUS_NONE; window_id: wid };
}

/// True for WINDOW_FOCUS_GAINED/LOST (the per-window focus signal).
/// Complexity: O(1).
pub fn sdl3_event_is_focus_change(ev: &Vec[UInt8]) -> Bool
  requires: ev.len() >= 20
{
  return sdl3_event_window_focus(ev).state != SDL3_WINDOW_FOCUS_NONE;
}

/// DPI-change routing: PIXEL_SIZE_CHANGED (data1xdata2),
/// DISPLAY_CHANGED (data1 = new display id) and
/// DISPLAY_SCALE_CHANGED all classify to a typed Sdl3DpiChange.
/// Complexity: O(1).
pub fn sdl3_event_dpi_change(ev: &Vec[UInt8]) -> Sdl3DpiChange
  requires: ev.len() >= 28
{
  let t = sdl3_event_type(ev);
  let wid = sdl3_event_window_id(ev);
  if t == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED {
    return Sdl3DpiChange{
      reason: SDL3_DPI_CHANGE_PIXEL_SIZE;
      window_id: wid;
      display_id: 0;
      pixel_width: sdl3_event_window_data1(ev);
      pixel_height: sdl3_event_window_data2(ev);
    };
  }
  if t == SDL_EVENT_WINDOW_DISPLAY_CHANGED {
    return Sdl3DpiChange{
      reason: SDL3_DPI_CHANGE_DISPLAY;
      window_id: wid;
      display_id: sdl3_event_window_data1(ev);
      pixel_width: 0;
      pixel_height: 0;
    };
  }
  if t == SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED {
    return Sdl3DpiChange{
      reason: SDL3_DPI_CHANGE_DISPLAY_SCALE;
      window_id: wid;
      display_id: 0;
      pixel_width: 0;
      pixel_height: 0;
    };
  }
  return Sdl3DpiChange{
    reason: SDL3_DPI_CHANGE_NONE;
    window_id: wid;
    display_id: 0;
    pixel_width: 0;
    pixel_height: 0;
  };
}

/// True for the three DPI-change signals above.
/// Complexity: O(1).
pub fn sdl3_event_is_dpi_change(ev: &Vec[UInt8]) -> Bool
  requires: ev.len() >= 28
{
  return sdl3_event_dpi_change(ev).reason != SDL3_DPI_CHANGE_NONE;
}

/// SDL_TextEditingEvent decode (composition/preedit).  `text` is copied
/// from the event-owned C string ("" when NULL); start/length are i32.
/// Complexity: O(len).
pub fn sdl3_event_text_editing(ev: &Vec[UInt8]) -> Sdl3TextEditing
  requires: ev.len() >= 40
{
  unsafe {
    let p = sdl3_read_u64_at(ev, 24);
    let text = if p == 0 { "" } else { Str::from_c_str(p as *UInt8) };
    return Sdl3TextEditing{
      window_id: sdl3_read_u32_at(ev, 16);
      text: text;
      start: sdl3_read_i32_at(ev, 32);
      length: sdl3_read_i32_at(ev, 36);
    };
  }
}

/// SDL_TextInputEvent decode (the committed UTF-8 text).  The pointer is
/// SDL-owned and only valid for the event delivery; copied here ("" when
/// NULL).
/// Complexity: O(len).
pub fn sdl3_event_text_input(ev: &Vec<UInt8>) -> Str
  requires: ev.len() >= 32
{
  unsafe {
    let p = sdl3_read_u64_at(ev, 24);
    if p == 0 { return ""; }
    return Str::from_c_str(p as *UInt8);
  }
}

/// Classify a text event into SDL3_TEXT_EVENT_*: EDITING for a non-empty
/// preedit, CANCELLED for an empty/NULL preedit (SDL3's cancellation
/// signal), COMMIT for TEXT_INPUT, NONE for every other event type.
/// Complexity: O(len).
pub fn sdl3_event_text_kind(ev: &Vec<UInt8>) -> Int
  requires: ev.len() >= 40
{
  let t = sdl3_event_type(ev);
  if t == SDL_EVENT_TEXT_INPUT {
    return SDL3_TEXT_EVENT_COMMIT;
  }
  if t == SDL_EVENT_TEXT_EDITING {
    let te = sdl3_event_text_editing(ev);
    if te.text.len() == 0 {
      return SDL3_TEXT_EVENT_CANCELLED;
    }
    return SDL3_TEXT_EVENT_EDITING;
  }
  return SDL3_TEXT_EVENT_NONE;
}

// =========================================================================
// 0.22.0: window surface tier (engine ask REL-20261031-1423-engine-4)
//
// Icon + BMP + surface create/destroy, the native window handle through
// SDL_GetWindowProperties, and an SDL_Vulkan_CreateSurface wrapper.  The
// surface creators live on the core loader (they need no window); the
// window-scoped calls live on the resource loader like every other
// SDL_Window* entry point.  Out-params get their own owned slot (B-17):
// the VkSurfaceKHR slot is zeroed before the call so a failed create
// never exposes a stale handle.  This host's SDL3 3.4.8 exports every
// symbol; the resource loader still fails closed (SDL3_LOAD_ABI) when a
// host build omits Vulkan support.
// =========================================================================

/// Native window property keys (SDL_GetWindowProperties).
/// Win32: HWND pointer; X11: window id number; Wayland: wl_surface pointer;
/// Cocoa: NSWindow pointer.
pub const SDL_PROP_WINDOW_WIN32_HWND_POINTER: Str = "SDL.window.win32.hwnd";
pub const SDL_PROP_WINDOW_X11_WINDOW_NUMBER: Str = "SDL.window.x11.window";
pub const SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER: Str = "SDL.window.wayland.surface";
pub const SDL_PROP_WINDOW_COCOA_WINDOW_POINTER: Str = "SDL.window.cocoa.window";

/// Native handle kind reported by sdl3_window_native_handle.
pub const SDL3_NATIVE_WINDOW_NONE: Int = 0;
pub const SDL3_NATIVE_WINDOW_WIN32: Int = 1;
pub const SDL3_NATIVE_WINDOW_X11: Int = 2;
pub const SDL3_NATIVE_WINDOW_WAYLAND: Int = 3;
pub const SDL3_NATIVE_WINDOW_COCOA: Int = 4;

/// Native window handle.  `handle` is an HWND (WIN32), an X11 window id
/// (X11), a wl_surface* (WAYLAND) or an NSWindow* (COCOA); 0 with
/// kind=NONE when the platform exposes none (e.g. dummy/offscreen).
pub type Sdl3NativeWindow = {
  ok: Bool;
  kind: Int;
  handle: Int;
}

/// SDL_LoadBMP(path) -> SDL_Surface* (owned; release with
/// sdl3_destroy_surface).  Err carries SDL_GetError() when the file is
/// missing or not a BMP.
/// Complexity: O(file size).
pub fn sdl3_load_bmp(lib: &Sdl3Library, path: Str) -> Result[Int, Str]
  requires: lib.handle != 0
  requires: path.len() > 0
{
  unsafe {
    let f = lib.p_load_bmp as fn(*UInt8) -> Int;
    let s = f(path.c_str());
    if s == 0 {
      return Err(sdl3_get_error(lib));
    }
    return Ok(s);
  }
}

/// SDL_SaveBMP(surface, path) -> Result.  Writes the surface as a 24/32-bit
/// BMP (SDL converts as needed); Err carries SDL_GetError().
/// Complexity: O(surface size).
pub fn sdl3_save_bmp(lib: &Sdl3Library, surface: Int, path: Str) -> Result[Unit, Str]
  requires: lib.handle != 0
  requires: surface != 0
  requires: path.len() > 0
{
  unsafe {
    let f = lib.p_save_bmp as fn(Int, *UInt8) -> UInt8;
    if (f(surface, path.c_str()) as Int) == 0 {
      return Err(sdl3_get_error(lib));
    }
    return Ok(());
  }
}

/// SDL_CreateSurface(width, height, format) -> SDL_Surface* (owned; release
/// with sdl3_destroy_surface).  `format` is an SDL_PIXELFORMAT_* value;
/// RGBA8888/ABGR8888 are exported.  Err carries SDL_GetError().
/// Complexity: O(width * height).
pub fn sdl3_create_surface(lib: &Sdl3Library, width: Int, height: Int, format: Int) -> Result[Int, Str]
  requires: lib.handle != 0
  requires: width > 0
  requires: height > 0
  requires: format > 0
{
  unsafe {
    let f = lib.p_create_surface as fn(Int, Int, Int) -> Int;
    let s = f(width, height, format);
    if s == 0 {
      return Err(sdl3_get_error(lib));
    }
    return Ok(s);
  }
}

/// SDL_DestroySurface (frees the surface and its pixels).  Safe to call
/// with a surface returned by sdl3_create_surface / sdl3_load_bmp only.
/// Complexity: O(1) plus the surface's own pixel free.
pub fn sdl3_destroy_surface(lib: &Sdl3Library, surface: Int)
  requires: lib.handle != 0
  requires: surface != 0
{
  unsafe {
    let f = lib.p_destroy_surface as fn(Int);
    f(surface);
  }
}

/// SDL_SetWindowIcon(window, surface) -> bool.  SDL copies what it needs;
/// the caller keeps ownership of `surface` and may destroy it afterwards.
/// Complexity: O(icon size).
pub fn sdl3_set_window_icon(r: &Sdl3Resources, win: Int, surface: Int) -> Bool
  requires: r.handle != 0
  requires: win != 0
  requires: surface != 0
{
  unsafe {
    let f = r.p_set_window_icon as fn(Int, Int) -> UInt8;
    return (f(win, surface) as Int) != 0;
  }
}

/// SDL_GetWindowProperties -> SDL_PropertiesID (0 when the window is
/// invalid).  Feed the id to the property getters below; the id is owned
/// by SDL and only valid while the window lives.
/// Complexity: O(1).
pub fn sdl3_window_properties(r: &Sdl3Resources, win: Int) -> Int
  requires: r.handle != 0
  requires: win != 0
{
  unsafe {
    let f = r.p_get_window_properties as fn(Int) -> UInt32;
    return f(win) as Int;
  }
}

/// SDL_GetPointerProperty(props, name) -> pointer value (0 when absent).
/// `name` is one of the SDL_PROP_WINDOW_* keys; the Win32/Cocoa/Wayland
/// handles are pointer properties.
/// Complexity: O(len(name)).
pub fn sdl3_get_pointer_property(r: &Sdl3Resources, props: Int, name: Str) -> Int
  requires: r.handle != 0
  requires: props != 0
  requires: name.len() > 0
{
  unsafe {
    let f = r.p_get_pointer_property as fn(UInt32, *UInt8, Int) -> Int;
    return f(props as UInt32, name.c_str(), 0);
  }
}

/// SDL_GetNumberProperty(props, name) -> number value (0 when absent).
/// The X11 window id is a number property.
/// Complexity: O(len(name)).
pub fn sdl3_get_number_property(r: &Sdl3Resources, props: Int, name: Str) -> Int
  requires: r.handle != 0
  requires: props != 0
  requires: name.len() > 0
{
  unsafe {
    let f = r.p_get_number_property as fn(UInt32, *UInt8, Int) -> Int;
    return f(props as UInt32, name.c_str(), 0);
  }
}

/// Resolve the native window handle through the window properties:
/// Win32 HWND pointer first, then X11 window number, Wayland surface
/// pointer and Cocoa window pointer.  ok=false + kind=NONE + handle=0 when
/// the platform exposes no native handle (dummy/offscreen).
/// Complexity: O(1).
pub fn sdl3_window_native_handle(r: &Sdl3Resources, win: Int) -> Sdl3NativeWindow
  requires: r.handle != 0
  requires: win != 0
{
  let props = sdl3_window_properties(r, win);
  if props == 0 {
    return Sdl3NativeWindow{ ok: false; kind: SDL3_NATIVE_WINDOW_NONE; handle: 0 };
  }
  let hwnd = sdl3_get_pointer_property(r, props, SDL_PROP_WINDOW_WIN32_HWND_POINTER);
  if hwnd != 0 {
    return Sdl3NativeWindow{ ok: true; kind: SDL3_NATIVE_WINDOW_WIN32; handle: hwnd };
  }
  let x11 = sdl3_get_number_property(r, props, SDL_PROP_WINDOW_X11_WINDOW_NUMBER);
  if x11 != 0 {
    return Sdl3NativeWindow{ ok: true; kind: SDL3_NATIVE_WINDOW_X11; handle: x11 };
  }
  let wl = sdl3_get_pointer_property(r, props, SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER);
  if wl != 0 {
    return Sdl3NativeWindow{ ok: true; kind: SDL3_NATIVE_WINDOW_WAYLAND; handle: wl };
  }
  let cocoa = sdl3_get_pointer_property(r, props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER);
  if cocoa != 0 {
    return Sdl3NativeWindow{ ok: true; kind: SDL3_NATIVE_WINDOW_COCOA; handle: cocoa };
  }
  return Sdl3NativeWindow{ ok: false; kind: SDL3_NATIVE_WINDOW_NONE; handle: 0 };
}

/// SDL_Vulkan_CreateSurface(window, instance, NULL, &surface) wrapper.
/// `out` is an owned 8-byte slot (create it with
/// sdl3_vulkan_surface_slot); it is zeroed before the call, so a failed
/// create reads back 0.  Returns false and leaves SDL_GetError() set when
/// the window was not created with SDL_WINDOW_VULKAN, the instance is 0,
/// or the Vulkan loader rejects the surface.
/// Complexity: O(1).
pub fn sdl3_vulkan_create_surface(r: &Sdl3Resources, win: Int, instance: Int, out: &mut Vec[UInt8]) -> Bool
  requires: r.handle != 0
  requires: win != 0
  requires: out.len() >= 8
{
  unsafe {
    sdl3_write_u64_le(out, 0, 0);
    let f = r.p_vulkan_create_surface as fn(Int, Int, Int, *UInt8) -> UInt8;
    return (f(win, instance, 0, out.as_mut_ptr()) as Int) != 0;
  }
}

/// Owned zeroed 8-byte slot for a VkSurfaceKHR out-param.
/// Complexity: O(1).
pub fn sdl3_vulkan_surface_slot() -> Vec[UInt8] {
  return sdl3_slot(8);
}

/// Read the VkSurfaceKHR back from a slot filled by
/// sdl3_vulkan_create_surface (0 when the create failed).
/// Complexity: O(1).
pub fn sdl3_vulkan_surface_value(out: &Vec[UInt8]) -> Int
  requires: out.len() >= 8
{
  return sdl3_read_u64_at(out, 0);
}
