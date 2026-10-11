// XIOM -- xiom.glfw: GLFW bindings via dynamic loader (engine surface).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader path (same pattern as xiom.sdl3). The package does
// NOT link GLFW at build time. `glfw_load` resolves `glfw3.dll` through
// `xiom.ffi.dl` at runtime and every call goes through fn-pointer casts in
// this single module -- the ONLY module in the package with `unsafe`.
//
// Classification (the suite maps it to markers):
//   GLFW_LOAD_ABSENT  -> backend missing -> SKIP (CI stays green)
//   GLFW_LOAD_NO_PLATFORM -> glfwInit failed (no display/platform) -> SKIP
//   GLFW_LOAD_ABI     -> library present but exports missing -> FAIL
//
// Coverage: 0.3.0 -- engine surface: init/hints, window lifecycle + attrs,
// events (poll/wait), input polling (key/mouse/cursor + modes), monitors +
// video modes, clipboard, time, GL-context basics, Win32 native accessors,
// and the Vulkan helpers (supported / instance proc / required extensions /
// win32 surface). 0.4.0 adds gamma ramps, cursors, window icons,
// joystick/gamepad polling and the Vulkan-loader hook. 0.5.0 completes the
// surface (124/124): the 20 event-callback setters (fixed-dispatcher +
// fn-registry ABI; see the 0.5.0 section) and glfwInitAllocator.
//
// G2 pin (SPEC.md): soname `glfw3.dll` (Windows) + upstream tag 3.4 header
// hash + resolved symbol set. Vulkan helpers are resolved best-effort
// (build-dependent; 0 = absent, wrappers return explicit errors).
//
// B-11 discipline: every out-param uses an XIOM-owned byte slot read back
// byte-wise (no compiler out-slots), matching the Vulkan probe finding.

module xiom.glfw

use xiom.convert;
use xiom.ffi;
use xiom.ffi.dl;

// =========================================================================
// Identity and constants (pinned from GLFW 3.4 glfw3.h)
// =========================================================================

pub const GLFW3_SONAME: Str = "glfw3.dll";

// Probe outcome kinds.
pub const GLFW_LOAD_ABSENT: Int = 0;      // backend missing -> SKIP
pub const GLFW_LOAD_NO_PLATFORM: Int = 1; // glfwInit failed (headless) -> SKIP
pub const GLFW_LOAD_ABI: Int = 2;         // exports missing -> FAIL

// Version / boolean / input states.
pub const GLFW_VERSION_MAJOR: Int = 3;
pub const GLFW_VERSION_MINOR: Int = 4;
pub const GLFW_VERSION_REVISION: Int = 0;
pub const GLFW_TRUE: Int = 1;
pub const GLFW_FALSE: Int = 0;
pub const GLFW_RELEASE: Int = 0;
pub const GLFW_PRESS: Int = 1;
pub const GLFW_REPEAT: Int = 2;

// Joystick hats.
pub const GLFW_HAT_CENTERED: Int = 0;
pub const GLFW_HAT_UP: Int = 1;
pub const GLFW_HAT_RIGHT: Int = 2;
pub const GLFW_HAT_DOWN: Int = 4;
pub const GLFW_HAT_LEFT: Int = 8;

// Keys.
pub const GLFW_KEY_UNKNOWN: Int = -1;
pub const GLFW_KEY_SPACE: Int = 32;
pub const GLFW_KEY_APOSTROPHE: Int = 39;
pub const GLFW_KEY_COMMA: Int = 44;
pub const GLFW_KEY_MINUS: Int = 45;
pub const GLFW_KEY_PERIOD: Int = 46;
pub const GLFW_KEY_SLASH: Int = 47;
pub const GLFW_KEY_0: Int = 48;
pub const GLFW_KEY_1: Int = 49;
pub const GLFW_KEY_2: Int = 50;
pub const GLFW_KEY_3: Int = 51;
pub const GLFW_KEY_4: Int = 52;
pub const GLFW_KEY_5: Int = 53;
pub const GLFW_KEY_6: Int = 54;
pub const GLFW_KEY_7: Int = 55;
pub const GLFW_KEY_8: Int = 56;
pub const GLFW_KEY_9: Int = 57;
pub const GLFW_KEY_SEMICOLON: Int = 59;
pub const GLFW_KEY_EQUAL: Int = 61;
pub const GLFW_KEY_A: Int = 65;
pub const GLFW_KEY_B: Int = 66;
pub const GLFW_KEY_C: Int = 67;
pub const GLFW_KEY_D: Int = 68;
pub const GLFW_KEY_E: Int = 69;
pub const GLFW_KEY_F: Int = 70;
pub const GLFW_KEY_G: Int = 71;
pub const GLFW_KEY_H: Int = 72;
pub const GLFW_KEY_I: Int = 73;
pub const GLFW_KEY_J: Int = 74;
pub const GLFW_KEY_K: Int = 75;
pub const GLFW_KEY_L: Int = 76;
pub const GLFW_KEY_M: Int = 77;
pub const GLFW_KEY_N: Int = 78;
pub const GLFW_KEY_O: Int = 79;
pub const GLFW_KEY_P: Int = 80;
pub const GLFW_KEY_Q: Int = 81;
pub const GLFW_KEY_R: Int = 82;
pub const GLFW_KEY_S: Int = 83;
pub const GLFW_KEY_T: Int = 84;
pub const GLFW_KEY_U: Int = 85;
pub const GLFW_KEY_V: Int = 86;
pub const GLFW_KEY_W: Int = 87;
pub const GLFW_KEY_X: Int = 88;
pub const GLFW_KEY_Y: Int = 89;
pub const GLFW_KEY_Z: Int = 90;
pub const GLFW_KEY_LEFT_BRACKET: Int = 91;
pub const GLFW_KEY_BACKSLASH: Int = 92;
pub const GLFW_KEY_RIGHT_BRACKET: Int = 93;
pub const GLFW_KEY_GRAVE_ACCENT: Int = 96;
pub const GLFW_KEY_WORLD_1: Int = 161;
pub const GLFW_KEY_WORLD_2: Int = 162;
pub const GLFW_KEY_ESCAPE: Int = 256;
pub const GLFW_KEY_ENTER: Int = 257;
pub const GLFW_KEY_TAB: Int = 258;
pub const GLFW_KEY_BACKSPACE: Int = 259;
pub const GLFW_KEY_INSERT: Int = 260;
pub const GLFW_KEY_DELETE: Int = 261;
pub const GLFW_KEY_RIGHT: Int = 262;
pub const GLFW_KEY_LEFT: Int = 263;
pub const GLFW_KEY_DOWN: Int = 264;
pub const GLFW_KEY_UP: Int = 265;
pub const GLFW_KEY_PAGE_UP: Int = 266;
pub const GLFW_KEY_PAGE_DOWN: Int = 267;
pub const GLFW_KEY_HOME: Int = 268;
pub const GLFW_KEY_END: Int = 269;
pub const GLFW_KEY_CAPS_LOCK: Int = 280;
pub const GLFW_KEY_SCROLL_LOCK: Int = 281;
pub const GLFW_KEY_NUM_LOCK: Int = 282;
pub const GLFW_KEY_PRINT_SCREEN: Int = 283;
pub const GLFW_KEY_PAUSE: Int = 284;
pub const GLFW_KEY_F1: Int = 290;
pub const GLFW_KEY_F2: Int = 291;
pub const GLFW_KEY_F3: Int = 292;
pub const GLFW_KEY_F4: Int = 293;
pub const GLFW_KEY_F5: Int = 294;
pub const GLFW_KEY_F6: Int = 295;
pub const GLFW_KEY_F7: Int = 296;
pub const GLFW_KEY_F8: Int = 297;
pub const GLFW_KEY_F9: Int = 298;
pub const GLFW_KEY_F10: Int = 299;
pub const GLFW_KEY_F11: Int = 300;
pub const GLFW_KEY_F12: Int = 301;
pub const GLFW_KEY_F13: Int = 302;
pub const GLFW_KEY_F14: Int = 303;
pub const GLFW_KEY_F15: Int = 304;
pub const GLFW_KEY_F16: Int = 305;
pub const GLFW_KEY_F17: Int = 306;
pub const GLFW_KEY_F18: Int = 307;
pub const GLFW_KEY_F19: Int = 308;
pub const GLFW_KEY_F20: Int = 309;
pub const GLFW_KEY_F21: Int = 310;
pub const GLFW_KEY_F22: Int = 311;
pub const GLFW_KEY_F23: Int = 312;
pub const GLFW_KEY_F24: Int = 313;
pub const GLFW_KEY_F25: Int = 314;
pub const GLFW_KEY_KP_0: Int = 320;
pub const GLFW_KEY_KP_1: Int = 321;
pub const GLFW_KEY_KP_2: Int = 322;
pub const GLFW_KEY_KP_3: Int = 323;
pub const GLFW_KEY_KP_4: Int = 324;
pub const GLFW_KEY_KP_5: Int = 325;
pub const GLFW_KEY_KP_6: Int = 326;
pub const GLFW_KEY_KP_7: Int = 327;
pub const GLFW_KEY_KP_8: Int = 328;
pub const GLFW_KEY_KP_9: Int = 329;
pub const GLFW_KEY_KP_DECIMAL: Int = 330;
pub const GLFW_KEY_KP_DIVIDE: Int = 331;
pub const GLFW_KEY_KP_MULTIPLY: Int = 332;
pub const GLFW_KEY_KP_SUBTRACT: Int = 333;
pub const GLFW_KEY_KP_ADD: Int = 334;
pub const GLFW_KEY_KP_ENTER: Int = 335;
pub const GLFW_KEY_KP_EQUAL: Int = 336;
pub const GLFW_KEY_LEFT_SHIFT: Int = 340;
pub const GLFW_KEY_LEFT_CONTROL: Int = 341;
pub const GLFW_KEY_LEFT_ALT: Int = 342;
pub const GLFW_KEY_LEFT_SUPER: Int = 343;
pub const GLFW_KEY_RIGHT_SHIFT: Int = 344;
pub const GLFW_KEY_RIGHT_CONTROL: Int = 345;
pub const GLFW_KEY_RIGHT_ALT: Int = 346;
pub const GLFW_KEY_RIGHT_SUPER: Int = 347;
pub const GLFW_KEY_MENU: Int = 348;

// Modifier bits.
pub const GLFW_MOD_SHIFT: Int = 0x0001;
pub const GLFW_MOD_CONTROL: Int = 0x0002;
pub const GLFW_MOD_ALT: Int = 0x0004;
pub const GLFW_MOD_SUPER: Int = 0x0008;
pub const GLFW_MOD_CAPS_LOCK: Int = 0x0010;
pub const GLFW_MOD_NUM_LOCK: Int = 0x0020;

// Mouse buttons / joystick ids.
pub const GLFW_MOUSE_BUTTON_1: Int = 0;
pub const GLFW_MOUSE_BUTTON_2: Int = 1;
pub const GLFW_MOUSE_BUTTON_3: Int = 2;
pub const GLFW_MOUSE_BUTTON_4: Int = 3;
pub const GLFW_MOUSE_BUTTON_5: Int = 4;
pub const GLFW_MOUSE_BUTTON_6: Int = 5;
pub const GLFW_MOUSE_BUTTON_7: Int = 6;
pub const GLFW_MOUSE_BUTTON_8: Int = 7;
pub const GLFW_JOYSTICK_1: Int = 0;
pub const GLFW_JOYSTICK_LAST_CONST: Int = 15;

// Error codes.
pub const GLFW_NO_ERROR: Int = 0;
pub const GLFW_NOT_INITIALIZED: Int = 0x00010001;
pub const GLFW_NO_CURRENT_CONTEXT: Int = 0x00010002;
pub const GLFW_INVALID_ENUM: Int = 0x00010003;
pub const GLFW_INVALID_VALUE: Int = 0x00010004;
pub const GLFW_OUT_OF_MEMORY: Int = 0x00010005;
pub const GLFW_API_UNAVAILABLE: Int = 0x00010006;
pub const GLFW_VERSION_UNAVAILABLE: Int = 0x00010007;
pub const GLFW_PLATFORM_ERROR: Int = 0x00010008;
pub const GLFW_FORMAT_UNAVAILABLE: Int = 0x00010009;
pub const GLFW_NO_WINDOW_CONTEXT: Int = 0x0001000A;
pub const GLFW_CURSOR_UNAVAILABLE: Int = 0x0001000B;
pub const GLFW_FEATURE_UNAVAILABLE: Int = 0x0001000C;
pub const GLFW_FEATURE_UNIMPLEMENTED: Int = 0x0001000D;
pub const GLFW_PLATFORM_UNAVAILABLE: Int = 0x0001000E;

// Window attributes.
pub const GLFW_FOCUSED: Int = 0x00020001;
pub const GLFW_ICONIFIED: Int = 0x00020002;
pub const GLFW_RESIZABLE: Int = 0x00020003;
pub const GLFW_VISIBLE: Int = 0x00020004;
pub const GLFW_DECORATED: Int = 0x00020005;
pub const GLFW_AUTO_ICONIFY: Int = 0x00020006;
pub const GLFW_FLOATING: Int = 0x00020007;
pub const GLFW_MAXIMIZED: Int = 0x00020008;
pub const GLFW_CENTER_CURSOR: Int = 0x00020009;
pub const GLFW_TRANSPARENT_FRAMEBUFFER: Int = 0x0002000A;
pub const GLFW_HOVERED: Int = 0x0002000B;
pub const GLFW_FOCUS_ON_SHOW: Int = 0x0002000C;
pub const GLFW_MOUSE_PASSTHROUGH: Int = 0x0002000D;
pub const GLFW_POSITION_X: Int = 0x0002000E;
pub const GLFW_POSITION_Y: Int = 0x0002000F;

// Framebuffer / context hints.
pub const GLFW_RED_BITS: Int = 0x00021001;
pub const GLFW_GREEN_BITS: Int = 0x00021002;
pub const GLFW_BLUE_BITS: Int = 0x00021003;
pub const GLFW_ALPHA_BITS: Int = 0x00021004;
pub const GLFW_DEPTH_BITS: Int = 0x00021005;
pub const GLFW_STENCIL_BITS: Int = 0x00021006;
pub const GLFW_ACCUM_RED_BITS: Int = 0x00021007;
pub const GLFW_ACCUM_GREEN_BITS: Int = 0x00021008;
pub const GLFW_ACCUM_BLUE_BITS: Int = 0x00021009;
pub const GLFW_ACCUM_ALPHA_BITS: Int = 0x0002100A;
pub const GLFW_AUX_BUFFERS: Int = 0x0002100B;
pub const GLFW_STEREO: Int = 0x0002100C;
pub const GLFW_SAMPLES: Int = 0x0002100D;
pub const GLFW_SRGB_CAPABLE: Int = 0x0002100E;
pub const GLFW_REFRESH_RATE: Int = 0x0002100F;
pub const GLFW_DOUBLEBUFFER: Int = 0x00021010;
pub const GLFW_CLIENT_API: Int = 0x00022001;
pub const GLFW_CONTEXT_VERSION_MAJOR: Int = 0x00022002;
pub const GLFW_CONTEXT_VERSION_MINOR: Int = 0x00022003;
pub const GLFW_CONTEXT_REVISION: Int = 0x00022004;
pub const GLFW_CONTEXT_ROBUSTNESS: Int = 0x00022005;
pub const GLFW_OPENGL_FORWARD_COMPAT: Int = 0x00022006;
pub const GLFW_CONTEXT_DEBUG: Int = 0x00022007;
pub const GLFW_OPENGL_PROFILE: Int = 0x00022008;
pub const GLFW_CONTEXT_RELEASE_BEHAVIOR: Int = 0x00022009;
pub const GLFW_CONTEXT_NO_ERROR: Int = 0x0002200A;
pub const GLFW_CONTEXT_CREATION_API: Int = 0x0002200B;
pub const GLFW_SCALE_TO_MONITOR: Int = 0x0002200C;
pub const GLFW_SCALE_FRAMEBUFFER: Int = 0x0002200D;
pub const GLFW_WIN32_KEYBOARD_MENU: Int = 0x00025001;
pub const GLFW_WIN32_SHOWDEFAULT: Int = 0x00025002;
pub const GLFW_NO_API: Int = 0;
pub const GLFW_OPENGL_API: Int = 0x00030001;
pub const GLFW_OPENGL_ES_API: Int = 0x00030002;
pub const GLFW_NO_ROBUSTNESS: Int = 0;
pub const GLFW_NO_RESET_NOTIFICATION: Int = 0x00031001;
pub const GLFW_LOSE_CONTEXT_ON_RESET: Int = 0x00031002;
pub const GLFW_OPENGL_ANY_PROFILE: Int = 0;
pub const GLFW_OPENGL_CORE_PROFILE: Int = 0x00032001;
pub const GLFW_OPENGL_COMPAT_PROFILE: Int = 0x00032002;

// Input modes and cursor modes.
pub const GLFW_CURSOR: Int = 0x00033001;
pub const GLFW_STICKY_KEYS: Int = 0x00033002;
pub const GLFW_STICKY_MOUSE_BUTTONS: Int = 0x00033003;
pub const GLFW_LOCK_KEY_MODS: Int = 0x00033004;
pub const GLFW_RAW_MOUSE_MOTION: Int = 0x00033005;
pub const GLFW_CURSOR_NORMAL: Int = 0x00034001;
pub const GLFW_CURSOR_HIDDEN: Int = 0x00034002;
pub const GLFW_CURSOR_DISABLED: Int = 0x00034003;
pub const GLFW_CURSOR_CAPTURED: Int = 0x00034004;

// Context release / creation APIs.
pub const GLFW_ANY_RELEASE_BEHAVIOR: Int = 0;
pub const GLFW_RELEASE_BEHAVIOR_FLUSH: Int = 0x00035001;
pub const GLFW_RELEASE_BEHAVIOR_NONE: Int = 0x00035002;
pub const GLFW_NATIVE_CONTEXT_API: Int = 0x00036001;
pub const GLFW_EGL_CONTEXT_API: Int = 0x00036002;
pub const GLFW_OSMESA_CONTEXT_API: Int = 0x00036003;

// Standard cursor shapes (0.4.0 uses; constants pinned now).
pub const GLFW_ARROW_CURSOR: Int = 0x00036001;
pub const GLFW_IBEAM_CURSOR: Int = 0x00036002;
pub const GLFW_CROSSHAIR_CURSOR: Int = 0x00036003;
pub const GLFW_POINTING_HAND_CURSOR: Int = 0x00036004;
pub const GLFW_RESIZE_EW_CURSOR: Int = 0x00036005;
pub const GLFW_RESIZE_NS_CURSOR: Int = 0x00036006;
pub const GLFW_RESIZE_NWSE_CURSOR: Int = 0x00036007;
pub const GLFW_RESIZE_NESW_CURSOR: Int = 0x00036008;
pub const GLFW_RESIZE_ALL_CURSOR: Int = 0x00036009;
pub const GLFW_NOT_ALLOWED_CURSOR: Int = 0x0003600A;

// Connection events / init hints / platform ids.
pub const GLFW_CONNECTED: Int = 0x00040001;
pub const GLFW_DISCONNECTED: Int = 0x00040002;
pub const GLFW_JOYSTICK_HAT_BUTTONS: Int = 0x00050001;
pub const GLFW_ANGLE_PLATFORM_TYPE: Int = 0x00050002;
pub const GLFW_PLATFORM: Int = 0x00050003;
pub const GLFW_ANY_PLATFORM: Int = 0x00060000;
pub const GLFW_PLATFORM_WIN32: Int = 0x00060001;
pub const GLFW_PLATFORM_COCOA: Int = 0x00060002;
pub const GLFW_PLATFORM_WAYLAND: Int = 0x00060003;
pub const GLFW_PLATFORM_X11: Int = 0x00060004;
pub const GLFW_PLATFORM_NULL: Int = 0x00060005;
pub const GLFW_ANY_POSITION: Int = 0x80000000;
pub const GLFW_DONT_CARE: Int = -1;

// =========================================================================
// Types
// =========================================================================

pub type GlfwLoadError = {
  kind: Int;
  message: Str;
}

/// An inited GLFW library handle.  Owned by the caller; release with
/// `glfw_close` after `glfw_terminate`.
pub type GlfwLibrary = {
  handle: Int;
  p_init: Int;
  p_terminate: Int;
  p_init_hint: Int;
  p_get_version: Int;
  p_get_version_string: Int;
  p_get_error: Int;
  p_get_platform: Int;
  p_platform_supported: Int;
  p_default_window_hints: Int;
  p_window_hint: Int;
  p_window_hint_string: Int;
  p_create_window: Int;
  p_destroy_window: Int;
  p_window_should_close: Int;
  p_set_window_should_close: Int;
  p_get_window_title: Int;
  p_set_window_title: Int;
  p_get_window_pos: Int;
  p_set_window_pos: Int;
  p_get_window_size: Int;
  p_set_window_size: Int;
  p_set_window_size_limits: Int;
  p_set_window_aspect_ratio: Int;
  p_get_framebuffer_size: Int;
  p_get_window_frame_size: Int;
  p_get_window_content_scale: Int;
  p_get_window_opacity: Int;
  p_set_window_opacity: Int;
  p_iconify_window: Int;
  p_restore_window: Int;
  p_maximize_window: Int;
  p_show_window: Int;
  p_hide_window: Int;
  p_focus_window: Int;
  p_request_window_attention: Int;
  p_get_window_monitor: Int;
  p_set_window_monitor: Int;
  p_get_window_attrib: Int;
  p_set_window_attrib: Int;
  p_set_window_user_pointer: Int;
  p_get_window_user_pointer: Int;
  p_poll_events: Int;
  p_wait_events: Int;
  p_wait_events_timeout: Int;
  p_post_empty_event: Int;
  p_get_input_mode: Int;
  p_set_input_mode: Int;
  p_raw_mouse_motion_supported: Int;
  p_get_key_name: Int;
  p_get_key_scancode: Int;
  p_get_key: Int;
  p_get_mouse_button: Int;
  p_get_cursor_pos: Int;
  p_set_cursor_pos: Int;
  p_get_monitors: Int;
  p_get_primary_monitor: Int;
  p_get_monitor_pos: Int;
  p_get_monitor_workarea: Int;
  p_get_monitor_physical_size: Int;
  p_get_monitor_content_scale: Int;
  p_get_monitor_name: Int;
  p_set_monitor_user_pointer: Int;
  p_get_monitor_user_pointer: Int;
  p_get_video_modes: Int;
  p_get_video_mode: Int;
  p_set_gamma: Int;
  p_set_clipboard_string: Int;
  p_get_clipboard_string: Int;
  p_get_time: Int;
  p_set_time: Int;
  p_get_timer_value: Int;
  p_get_timer_frequency: Int;
  p_make_context_current: Int;
  p_get_current_context: Int;
  p_swap_buffers: Int;
  p_swap_interval: Int;
  p_extension_supported: Int;
  p_get_proc_address: Int;
  p_get_win32_adapter: Int;
  p_get_win32_monitor: Int;
  p_get_win32_window: Int;
  // 0.4.0 additions.
  p_get_gamma_ramp: Int;
  p_set_gamma_ramp: Int;
  p_set_window_icon: Int;
  p_create_cursor: Int;
  p_create_standard_cursor: Int;
  p_destroy_cursor: Int;
  p_set_cursor: Int;
  p_joystick_present: Int;
  p_get_joystick_axes: Int;
  p_get_joystick_buttons: Int;
  p_get_joystick_hats: Int;
  p_get_joystick_name: Int;
  p_get_joystick_guid: Int;
  p_set_joystick_user_pointer: Int;
  p_get_joystick_user_pointer: Int;
  p_joystick_is_gamepad: Int;
  p_get_gamepad_name: Int;
  p_get_gamepad_state: Int;
  p_update_gamepad_mappings: Int;
  p_init_vulkan_loader: Int;
  // 0.5.0 additions: 20 event-callback setters + glfwInitAllocator.
  p_set_error_callback: Int;
  p_set_monitor_callback: Int;
  p_set_joystick_callback: Int;
  p_set_window_pos_callback: Int;
  p_set_window_size_callback: Int;
  p_set_window_close_callback: Int;
  p_set_window_refresh_callback: Int;
  p_set_window_focus_callback: Int;
  p_set_window_iconify_callback: Int;
  p_set_window_maximize_callback: Int;
  p_set_framebuffer_size_callback: Int;
  p_set_window_content_scale_callback: Int;
  p_set_key_callback: Int;
  p_set_char_callback: Int;
  p_set_char_mods_callback: Int;
  p_set_mouse_button_callback: Int;
  p_set_cursor_pos_callback: Int;
  p_set_cursor_enter_callback: Int;
  p_set_scroll_callback: Int;
  p_set_drop_callback: Int;
  p_init_allocator: Int;
  // Optional (build-dependent; 0 = export absent).
  p_vulkan_supported: Int;
  p_get_required_instance_extensions: Int;
  p_get_instance_proc_address: Int;
  p_get_physical_device_presentation_support: Int;
  p_create_window_surface: Int;
}

/// A GLFW window handle (`GLFWwindow*`).
pub type GlfwWindow = {
  handle: Int;
}

/// A GLFW monitor handle (`GLFWmonitor*`).
pub type GlfwMonitor = {
  handle: Int;
}

/// `GLFWvidmode` (six packed int32 fields, 24 bytes on the wire).
pub type GlfwVidmode = {
  width: Int;
  height: Int;
  red_bits: Int;
  green_bits: Int;
  blue_bits: Int;
  refresh_rate: Int;
}

// =========================================================================
// XIOM-owned byte slots + readers (B-11 discipline: no compiler out-slots)
// =========================================================================

fn slot_new(n: Int) -> Vec[UInt8]
  requires: n > 0
  requires: n <= 4096
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

/// Copy `n` bytes from a foreign pointer into an XIOM-owned slot (memcpy;
/// no pointer arithmetic, no C allocation).
fn copy_from(ptr: Int, n: Int) -> Vec[UInt8]
  requires: ptr != 0
  requires: n > 0
  requires: n <= 4096
{
  var s = slot_new(n);
  unsafe {
    memcpy(s.as_mut_ptr() as *UInt8, ptr as *UInt8, n);
  }
  return s;
}

fn read_u32_le(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn read_i32_le(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let u = read_u32_le(buf, off);
  if u >= 0x80000000 { return u - 0x100000000; }
  return u;
}

fn read_u64_le(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  let b4 = buf[off + 4] as Int;
  let b5 = buf[off + 5] as Int;
  let b6 = buf[off + 6] as Int;
  let b7 = buf[off + 7] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
       | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56);
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

/// IEEE-754 binary32 bits -> Float64 (pure arithmetic; avoids the
/// Result[Float32] payload-extraction codegen bug, relay family stdlib-5).
fn f32_from_bits(bits: Int) -> Float64
  requires: bits >= 0
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

/// IEEE-754 binary64 bits -> Float64 (pure arithmetic).
fn f64_from_bits(bits: Int) -> Float64
  requires: bits >= 0
{
  let sign = if ((bits >> 63) & 1) == 1 { -1.0 } else { 1.0 };
  let exp = (bits >> 52) & 0x7FF;
  let frac = bits & 0xFFFFFFFFFFFFF;
  if exp == 0 {
    if frac == 0 { return sign * 0.0; }
    return sign * (frac as Float64) * pow2i(-1074);
  }
  if exp == 2047 { return 0.0; }
  return sign * (1.0 + (frac as Float64) / 4503599627370496.0) * pow2i(exp - 1023);
}

fn read_f32_le(buf: &Vec[UInt8], off: Int) -> Float64
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  return f32_from_bits(read_u32_le(buf, off));
}

fn read_f64_le(buf: &Vec[UInt8], off: Int) -> Float64
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  return f64_from_bits(read_u64_le(buf, off));
}

// =========================================================================
// Loader
// =========================================================================

/// The fail-closed export set (order must match `GlfwLibrary`).
/// Complexity: O(1).
fn glfw_symbol_names() -> Vec[Str]
  requires: true
{
  var n: Vec[Str] = Vec[Str].new();
  n.push("glfwInit");                              // 0
  n.push("glfwTerminate");                         // 1
  n.push("glfwInitHint");                          // 2
  n.push("glfwGetVersion");                        // 3
  n.push("glfwGetVersionString");                  // 4
  n.push("glfwGetError");                          // 5
  n.push("glfwGetPlatform");                       // 6
  n.push("glfwPlatformSupported");                 // 7
  n.push("glfwDefaultWindowHints");                // 8
  n.push("glfwWindowHint");                        // 9
  n.push("glfwWindowHintString");                  // 10
  n.push("glfwCreateWindow");                      // 11
  n.push("glfwDestroyWindow");                     // 12
  n.push("glfwWindowShouldClose");                 // 13
  n.push("glfwSetWindowShouldClose");              // 14
  n.push("glfwGetWindowTitle");                    // 15
  n.push("glfwSetWindowTitle");                    // 16
  n.push("glfwGetWindowPos");                      // 17
  n.push("glfwSetWindowPos");                      // 18
  n.push("glfwGetWindowSize");                     // 19
  n.push("glfwSetWindowSize");                     // 20
  n.push("glfwSetWindowSizeLimits");               // 21
  n.push("glfwSetWindowAspectRatio");              // 22
  n.push("glfwGetFramebufferSize");                // 23
  n.push("glfwGetWindowFrameSize");                // 24
  n.push("glfwGetWindowContentScale");             // 25
  n.push("glfwGetWindowOpacity");                  // 26
  n.push("glfwSetWindowOpacity");                  // 27
  n.push("glfwIconifyWindow");                     // 28
  n.push("glfwRestoreWindow");                     // 29
  n.push("glfwMaximizeWindow");                    // 30
  n.push("glfwShowWindow");                        // 31
  n.push("glfwHideWindow");                        // 32
  n.push("glfwFocusWindow");                       // 33
  n.push("glfwRequestWindowAttention");            // 34
  n.push("glfwGetWindowMonitor");                  // 35
  n.push("glfwSetWindowMonitor");                  // 36
  n.push("glfwGetWindowAttrib");                   // 37
  n.push("glfwSetWindowAttrib");                   // 38
  n.push("glfwSetWindowUserPointer");              // 39
  n.push("glfwGetWindowUserPointer");              // 40
  n.push("glfwPollEvents");                        // 41
  n.push("glfwWaitEvents");                        // 42
  n.push("glfwWaitEventsTimeout");                 // 43
  n.push("glfwPostEmptyEvent");                    // 44
  n.push("glfwGetInputMode");                      // 45
  n.push("glfwSetInputMode");                      // 46
  n.push("glfwRawMouseMotionSupported");           // 47
  n.push("glfwGetKeyName");                        // 48
  n.push("glfwGetKeyScancode");                    // 49
  n.push("glfwGetKey");                            // 50
  n.push("glfwGetMouseButton");                    // 51
  n.push("glfwGetCursorPos");                      // 52
  n.push("glfwSetCursorPos");                      // 53
  n.push("glfwGetMonitors");                       // 54
  n.push("glfwGetPrimaryMonitor");                 // 55
  n.push("glfwGetMonitorPos");                     // 56
  n.push("glfwGetMonitorWorkarea");                // 57
  n.push("glfwGetMonitorPhysicalSize");            // 58
  n.push("glfwGetMonitorContentScale");            // 59
  n.push("glfwGetMonitorName");                    // 60
  n.push("glfwSetMonitorUserPointer");             // 61
  n.push("glfwGetMonitorUserPointer");             // 62
  n.push("glfwGetVideoModes");                     // 63
  n.push("glfwGetVideoMode");                      // 64
  n.push("glfwSetGamma");                          // 65
  n.push("glfwSetClipboardString");                // 66
  n.push("glfwGetClipboardString");                // 67
  n.push("glfwGetTime");                           // 68
  n.push("glfwSetTime");                           // 69
  n.push("glfwGetTimerValue");                     // 70
  n.push("glfwGetTimerFrequency");                 // 71
  n.push("glfwMakeContextCurrent");                // 72
  n.push("glfwGetCurrentContext");                 // 73
  n.push("glfwSwapBuffers");                       // 74
  n.push("glfwSwapInterval");                      // 75
  n.push("glfwExtensionSupported");                // 76
  n.push("glfwGetProcAddress");                    // 77
  n.push("glfwGetWin32Adapter");                   // 78
  n.push("glfwGetWin32Monitor");                   // 79
  n.push("glfwGetWin32Window");                    // 80
  // 0.4.0 additions (order must match GlfwLibrary).
  n.push("glfwGetGammaRamp");                      // 81
  n.push("glfwSetGammaRamp");                      // 82
  n.push("glfwSetWindowIcon");                     // 83
  n.push("glfwCreateCursor");                      // 84
  n.push("glfwCreateStandardCursor");              // 85
  n.push("glfwDestroyCursor");                     // 86
  n.push("glfwSetCursor");                         // 87
  n.push("glfwJoystickPresent");                   // 88
  n.push("glfwGetJoystickAxes");                   // 89
  n.push("glfwGetJoystickButtons");                // 90
  n.push("glfwGetJoystickHats");                   // 91
  n.push("glfwGetJoystickName");                   // 92
  n.push("glfwGetJoystickGUID");                   // 93
  n.push("glfwSetJoystickUserPointer");            // 94
  n.push("glfwGetJoystickUserPointer");            // 95
  n.push("glfwJoystickIsGamepad");                 // 96
  n.push("glfwGetGamepadName");                    // 97
  n.push("glfwGetGamepadState");                   // 98
  n.push("glfwUpdateGamepadMappings");             // 99
  n.push("glfwInitVulkanLoader");                  // 100
  // 0.5.0 additions (order must match GlfwLibrary).
  n.push("glfwSetErrorCallback");                  // 101
  n.push("glfwSetMonitorCallback");                // 102
  n.push("glfwSetJoystickCallback");               // 103
  n.push("glfwSetWindowPosCallback");              // 104
  n.push("glfwSetWindowSizeCallback");             // 105
  n.push("glfwSetWindowCloseCallback");            // 106
  n.push("glfwSetWindowRefreshCallback");          // 107
  n.push("glfwSetWindowFocusCallback");            // 108
  n.push("glfwSetWindowIconifyCallback");          // 109
  n.push("glfwSetWindowMaximizeCallback");         // 110
  n.push("glfwSetFramebufferSizeCallback");        // 111
  n.push("glfwSetWindowContentScaleCallback");     // 112
  n.push("glfwSetKeyCallback");                    // 113
  n.push("glfwSetCharCallback");                   // 114
  n.push("glfwSetCharModsCallback");               // 115
  n.push("glfwSetMouseButtonCallback");            // 116
  n.push("glfwSetCursorPosCallback");              // 117
  n.push("glfwSetCursorEnterCallback");            // 118
  n.push("glfwSetScrollCallback");                 // 119
  n.push("glfwSetDropCallback");                   // 120
  n.push("glfwInitAllocator");                     // 121
  return n;
}

/// Load glfw3.dll and resolve the engine surface.  Fail-closed: any missing
/// core export closes the handle and reports `GLFW_LOAD_ABI`.  The Vulkan
/// helpers are resolved best-effort (0 when the build lacks them).
/// Complexity: O(symbols).
pub fn glfw_load() -> Result[GlfwLibrary, GlfwLoadError] {
  let h = dl.dl_open(GLFW3_SONAME);
  if !h.is_ok {
    return Err(GlfwLoadError{ kind: GLFW_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;

  var ptrs: Vec[Int] = Vec[Int].new();
  let names = glfw_symbol_names();
  var i = 0;
  while i < names.len() {
    let r = dl.dl_sym(handle, names[i]);
    if !r.is_ok {
      var ig = dl.dl_close(handle);
      return Err(GlfwLoadError{ kind: GLFW_LOAD_ABI; message: names[i] + ": " + r.error });
    }
    ptrs.push(r.value);
    i = i + 1;
  }

  // Optional Vulkan helpers (GLFW builds without Vulkan support omit them).
  var ov: Vec[Int] = Vec[Int].new();
  var k = 0;
  let vnames: Vec[Str] = glfw_vulkan_symbol_names();
  while k < vnames.len() {
    let r = dl.dl_sym(handle, vnames[k]);
    if r.is_ok {
      ov.push(r.value);
    } else {
      ov.push(0);
    }
    k = k + 1;
  }

  return Ok(GlfwLibrary{
    handle: handle,
    p_init: ptrs[0],
    p_terminate: ptrs[1],
    p_init_hint: ptrs[2],
    p_get_version: ptrs[3],
    p_get_version_string: ptrs[4],
    p_get_error: ptrs[5],
    p_get_platform: ptrs[6],
    p_platform_supported: ptrs[7],
    p_default_window_hints: ptrs[8],
    p_window_hint: ptrs[9],
    p_window_hint_string: ptrs[10],
    p_create_window: ptrs[11],
    p_destroy_window: ptrs[12],
    p_window_should_close: ptrs[13],
    p_set_window_should_close: ptrs[14],
    p_get_window_title: ptrs[15],
    p_set_window_title: ptrs[16],
    p_get_window_pos: ptrs[17],
    p_set_window_pos: ptrs[18],
    p_get_window_size: ptrs[19],
    p_set_window_size: ptrs[20],
    p_set_window_size_limits: ptrs[21],
    p_set_window_aspect_ratio: ptrs[22],
    p_get_framebuffer_size: ptrs[23],
    p_get_window_frame_size: ptrs[24],
    p_get_window_content_scale: ptrs[25],
    p_get_window_opacity: ptrs[26],
    p_set_window_opacity: ptrs[27],
    p_iconify_window: ptrs[28],
    p_restore_window: ptrs[29],
    p_maximize_window: ptrs[30],
    p_show_window: ptrs[31],
    p_hide_window: ptrs[32],
    p_focus_window: ptrs[33],
    p_request_window_attention: ptrs[34],
    p_get_window_monitor: ptrs[35],
    p_set_window_monitor: ptrs[36],
    p_get_window_attrib: ptrs[37],
    p_set_window_attrib: ptrs[38],
    p_set_window_user_pointer: ptrs[39],
    p_get_window_user_pointer: ptrs[40],
    p_poll_events: ptrs[41],
    p_wait_events: ptrs[42],
    p_wait_events_timeout: ptrs[43],
    p_post_empty_event: ptrs[44],
    p_get_input_mode: ptrs[45],
    p_set_input_mode: ptrs[46],
    p_raw_mouse_motion_supported: ptrs[47],
    p_get_key_name: ptrs[48],
    p_get_key_scancode: ptrs[49],
    p_get_key: ptrs[50],
    p_get_mouse_button: ptrs[51],
    p_get_cursor_pos: ptrs[52],
    p_set_cursor_pos: ptrs[53],
    p_get_monitors: ptrs[54],
    p_get_primary_monitor: ptrs[55],
    p_get_monitor_pos: ptrs[56],
    p_get_monitor_workarea: ptrs[57],
    p_get_monitor_physical_size: ptrs[58],
    p_get_monitor_content_scale: ptrs[59],
    p_get_monitor_name: ptrs[60],
    p_set_monitor_user_pointer: ptrs[61],
    p_get_monitor_user_pointer: ptrs[62],
    p_get_video_modes: ptrs[63],
    p_get_video_mode: ptrs[64],
    p_set_gamma: ptrs[65],
    p_set_clipboard_string: ptrs[66],
    p_get_clipboard_string: ptrs[67],
    p_get_time: ptrs[68],
    p_set_time: ptrs[69],
    p_get_timer_value: ptrs[70],
    p_get_timer_frequency: ptrs[71],
    p_make_context_current: ptrs[72],
    p_get_current_context: ptrs[73],
    p_swap_buffers: ptrs[74],
    p_swap_interval: ptrs[75],
    p_extension_supported: ptrs[76],
    p_get_proc_address: ptrs[77],
    p_get_win32_adapter: ptrs[78],
    p_get_win32_monitor: ptrs[79],
    p_get_win32_window: ptrs[80],
    p_get_gamma_ramp: ptrs[81],
    p_set_gamma_ramp: ptrs[82],
    p_set_window_icon: ptrs[83],
    p_create_cursor: ptrs[84],
    p_create_standard_cursor: ptrs[85],
    p_destroy_cursor: ptrs[86],
    p_set_cursor: ptrs[87],
    p_joystick_present: ptrs[88],
    p_get_joystick_axes: ptrs[89],
    p_get_joystick_buttons: ptrs[90],
    p_get_joystick_hats: ptrs[91],
    p_get_joystick_name: ptrs[92],
    p_get_joystick_guid: ptrs[93],
    p_set_joystick_user_pointer: ptrs[94],
    p_get_joystick_user_pointer: ptrs[95],
    p_joystick_is_gamepad: ptrs[96],
    p_get_gamepad_name: ptrs[97],
    p_get_gamepad_state: ptrs[98],
    p_update_gamepad_mappings: ptrs[99],
    p_init_vulkan_loader: ptrs[100],
    p_set_error_callback: ptrs[101],
    p_set_monitor_callback: ptrs[102],
    p_set_joystick_callback: ptrs[103],
    p_set_window_pos_callback: ptrs[104],
    p_set_window_size_callback: ptrs[105],
    p_set_window_close_callback: ptrs[106],
    p_set_window_refresh_callback: ptrs[107],
    p_set_window_focus_callback: ptrs[108],
    p_set_window_iconify_callback: ptrs[109],
    p_set_window_maximize_callback: ptrs[110],
    p_set_framebuffer_size_callback: ptrs[111],
    p_set_window_content_scale_callback: ptrs[112],
    p_set_key_callback: ptrs[113],
    p_set_char_callback: ptrs[114],
    p_set_char_mods_callback: ptrs[115],
    p_set_mouse_button_callback: ptrs[116],
    p_set_cursor_pos_callback: ptrs[117],
    p_set_cursor_enter_callback: ptrs[118],
    p_set_scroll_callback: ptrs[119],
    p_set_drop_callback: ptrs[120],
    p_init_allocator: ptrs[121],
    p_vulkan_supported: ov[0],
    p_get_required_instance_extensions: ov[1],
    p_get_instance_proc_address: ov[2],
    p_get_physical_device_presentation_support: ov[3],
    p_create_window_surface: ov[4],
  });
}

/// Optional Vulkan helper export names (order matches the `ov` vector).
/// Complexity: O(1).
fn glfw_vulkan_symbol_names() -> Vec[Str]
  requires: true
{
  var n: Vec[Str] = Vec[Str].new();
  n.push("glfwVulkanSupported");                                  // 0
  n.push("glfwGetRequiredInstanceExtensions");                    // 1
  n.push("glfwGetInstanceProcAddress");                           // 2
  n.push("glfwGetPhysicalDevicePresentationSupport");             // 3
  n.push("glfwCreateWindowSurface");                              // 4
  return n;
}

/// Release the library handle.
/// Complexity: O(1).
pub fn glfw_close(lib: &GlfwLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

// =========================================================================
// Small value types for paired/rect outputs
// =========================================================================

pub type GlfwIVec2 = { x: Int; y: Int; }
pub type GlfwFVec2 = { x: Float64; y: Float64; }
pub type GlfwRect = { x: Int; y: Int; width: Int; height: Int; }
pub type GlfwFrameSize = { left: Int; top: Int; right: Int; bottom: Int; }
pub type GlfwCursorPos = { x: Float64; y: Float64; }

/// Required Vulkan instance extensions as raw C-string pointers (GLFW
/// returns 2 on Windows: `VK_KHR_surface`, `VK_KHR_win32_surface`).  A small
/// struct payload keeps clear of the Result[Vec[...]] extraction codegen bug;
/// convert with `Str::from_c_str(p as *UInt8)` while the pointers are live.
pub type GlfwExtNames = { count: Int; p0: Int; p1: Int; }

// =========================================================================
// Init / version / error / platform
// =========================================================================

/// glfwInit() -> TRUE on success.
/// Complexity: O(platform init).
pub fn glfw_init(lib: &GlfwLibrary) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_init as fn() -> Int32;
    return f() != 0;
  }
}

/// glfwTerminate().
/// Complexity: O(1).
pub fn glfw_terminate(lib: &GlfwLibrary)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_terminate as fn();
    f();
  }
}

/// glfwInitHint(hint, value).
/// Complexity: O(1).
pub fn glfw_init_hint(lib: &GlfwLibrary, hint: Int, value: Int)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_init_hint as fn(Int32, Int32);
    f(hint as Int32, value as Int32);
  }
}

/// glfwGetVersion() packed as major*10000 + minor*100 + rev (3.4.0 -> 30400).
/// Complexity: O(1).
pub fn glfw_get_version(lib: &GlfwLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    var sm = slot_new(4);
    var sn = slot_new(4);
    var sr = slot_new(4);
    let f = lib.p_get_version as fn(*UInt8, *UInt8, *UInt8);
    f(sm.as_mut_ptr() as *UInt8, sn.as_mut_ptr() as *UInt8, sr.as_mut_ptr() as *UInt8);
    let major = read_u32_le(&sm, 0);
    let minor = read_u32_le(&sn, 0);
    let rev = read_u32_le(&sr, 0);
    return major * 10000 + minor * 100 + rev;
  }
}

/// glfwGetVersionString() -> compiler/platform description ("" when NULL).
/// Complexity: O(len).
pub fn glfw_get_version_string(lib: &GlfwLibrary) -> Str
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_version_string as fn() -> *UInt8;
    let p = f();
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// glfwGetError(NULL) -> last error code (0 when none).
/// Complexity: O(1).
pub fn glfw_last_error_code(lib: &GlfwLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_error as fn(Int) -> Int32;
    return f(0) as Int;
  }
}

/// glfwGetError(&desc) -> description of the last error ("" when none).
/// Complexity: O(len).
pub fn glfw_last_error(lib: &GlfwLibrary) -> Str
  requires: lib.handle != 0
{
  unsafe {
    var slot = slot_new(8);
    let f = lib.p_get_error as fn(*UInt8) -> Int32;
    let code = f(slot.as_mut_ptr() as *UInt8) as Int;
    if code == 0 { return ""; }
    let ptr = read_u64_le(&slot, 0);
    if ptr == 0 { return ""; }
    return Str::from_c_str(ptr as *UInt8);
  }
}

/// glfwGetPlatform() -> GLFW_PLATFORM_* id of the current platform.
/// Complexity: O(1).
pub fn glfw_platform(lib: &GlfwLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_platform as fn() -> Int32;
    return f() as Int;
  }
}

/// glfwPlatformSupported(platform).
/// Complexity: O(1).
pub fn glfw_platform_supported(lib: &GlfwLibrary, platform: Int) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_platform_supported as fn(Int32) -> Int32;
    return f(platform as Int32) != 0;
  }
}

// =========================================================================
// Window hints
// =========================================================================

/// glfwDefaultWindowHints().
/// Complexity: O(1).
pub fn glfw_default_window_hints(lib: &GlfwLibrary)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_default_window_hints as fn();
    f();
  }
}

/// glfwWindowHint(hint, value).
/// Complexity: O(1).
pub fn glfw_window_hint(lib: &GlfwLibrary, hint: Int, value: Int)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_window_hint as fn(Int32, Int32);
    f(hint as Int32, value as Int32);
  }
}

/// glfwWindowHintString(hint, value).
/// Complexity: O(len).
pub fn glfw_window_hint_string(lib: &GlfwLibrary, hint: Int, value: Str)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_window_hint_string as fn(Int32, *UInt8);
    f(hint as Int32, value as *UInt8);
  }
}

// =========================================================================
// Window lifecycle
// =========================================================================

/// glfwCreateWindow() -> the window, or Err with the GLFW error text.
/// `monitor`/`share` are raw handles (0 = none).  Use
/// `GLFW_VISIBLE = GLFW_FALSE` (via `glfw_window_hint`) for headless-safe
/// smoke tests.
/// Complexity: O(window).
pub fn glfw_create_window(lib: &GlfwLibrary, width: Int, height: Int, title: Str,
    monitor: Int, share: Int) -> Result[GlfwWindow, Str]
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_create_window as fn(Int32, Int32, *UInt8, *UInt8, *UInt8) -> *UInt8;
    let p = f(width as Int32, height as Int32, title as *UInt8,
              monitor as *UInt8, share as *UInt8);
    if (p as Int) == 0 {
      return Err(glfw_last_error(lib));
    }
    return Ok(GlfwWindow{ handle: p as Int });
  }
}

/// glfwDestroyWindow().
/// Complexity: O(1).
pub fn glfw_destroy_window(lib: &GlfwLibrary, w: &GlfwWindow)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_destroy_window as fn(*UInt8);
    f(w.handle as *UInt8);
  }
}

/// glfwWindowShouldClose().
/// Complexity: O(1).
pub fn glfw_window_should_close(lib: &GlfwLibrary, w: &GlfwWindow) -> Bool
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_window_should_close as fn(*UInt8) -> Int32;
    return f(w.handle as *UInt8) != 0;
  }
}

/// glfwSetWindowShouldClose(value).
/// Complexity: O(1).
pub fn glfw_set_window_should_close(lib: &GlfwLibrary, w: &GlfwWindow, value: Bool)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let v: Int32 = if value { 1 } else { 0 };
    let f = lib.p_set_window_should_close as fn(*UInt8, Int32);
    f(w.handle as *UInt8, v);
  }
}

/// glfwGetWindowTitle() ("" when NULL).
/// Complexity: O(len).
pub fn glfw_get_window_title(lib: &GlfwLibrary, w: &GlfwWindow) -> Str
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_get_window_title as fn(*UInt8) -> *UInt8;
    let p = f(w.handle as *UInt8);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// glfwSetWindowTitle(title).
/// Complexity: O(len).
pub fn glfw_set_window_title(lib: &GlfwLibrary, w: &GlfwWindow, title: Str)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_window_title as fn(*UInt8, *UInt8);
    f(w.handle as *UInt8, title as *UInt8);
  }
}

/// glfwGetWindowPos() -> (x, y) screen coordinates.
/// Complexity: O(1).
pub fn glfw_get_window_pos(lib: &GlfwLibrary, w: &GlfwWindow) -> GlfwIVec2
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    var sx = slot_new(4);
    var sy = slot_new(4);
    let f = lib.p_get_window_pos as fn(*UInt8, *UInt8, *UInt8);
    f(w.handle as *UInt8, sx.as_mut_ptr() as *UInt8, sy.as_mut_ptr() as *UInt8);
    return GlfwIVec2{ x: read_i32_le(&sx, 0); y: read_i32_le(&sy, 0); };
  }
}

/// glfwSetWindowPos(x, y).
/// Complexity: O(1).
pub fn glfw_set_window_pos(lib: &GlfwLibrary, w: &GlfwWindow, x: Int, y: Int)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_window_pos as fn(*UInt8, Int32, Int32);
    f(w.handle as *UInt8, x as Int32, y as Int32);
  }
}

/// glfwGetWindowSize() -> (width, height) of the content area.
/// Complexity: O(1).
pub fn glfw_get_window_size(lib: &GlfwLibrary, w: &GlfwWindow) -> GlfwIVec2
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    var sw = slot_new(4);
    var sh = slot_new(4);
    let f = lib.p_get_window_size as fn(*UInt8, *UInt8, *UInt8);
    f(w.handle as *UInt8, sw.as_mut_ptr() as *UInt8, sh.as_mut_ptr() as *UInt8);
    return GlfwIVec2{ x: read_i32_le(&sw, 0); y: read_i32_le(&sh, 0); };
  }
}

/// glfwSetWindowSize(width, height).
/// Complexity: O(1).
pub fn glfw_set_window_size(lib: &GlfwLibrary, w: &GlfwWindow, width: Int, height: Int)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_window_size as fn(*UInt8, Int32, Int32);
    f(w.handle as *UInt8, width as Int32, height as Int32);
  }
}

/// glfwSetWindowSizeLimits(minw, minh, maxw, maxh) (GLFW_DONT_CARE allowed).
/// Complexity: O(1).
pub fn glfw_set_window_size_limits(lib: &GlfwLibrary, w: &GlfwWindow,
    minw: Int, minh: Int, maxw: Int, maxh: Int)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_window_size_limits as fn(*UInt8, Int32, Int32, Int32, Int32);
    f(w.handle as *UInt8, minw as Int32, minh as Int32, maxw as Int32, maxh as Int32);
  }
}

/// glfwSetWindowAspectRatio(numerator, denominator).
/// Complexity: O(1).
pub fn glfw_set_window_aspect_ratio(lib: &GlfwLibrary, w: &GlfwWindow,
    numerator: Int, denominator: Int)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_window_aspect_ratio as fn(*UInt8, Int32, Int32);
    f(w.handle as *UInt8, numerator as Int32, denominator as Int32);
  }
}

/// glfwGetFramebufferSize() -> (width, height) in pixels.
/// Complexity: O(1).
pub fn glfw_get_framebuffer_size(lib: &GlfwLibrary, w: &GlfwWindow) -> GlfwIVec2
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    var sw = slot_new(4);
    var sh = slot_new(4);
    let f = lib.p_get_framebuffer_size as fn(*UInt8, *UInt8, *UInt8);
    f(w.handle as *UInt8, sw.as_mut_ptr() as *UInt8, sh.as_mut_ptr() as *UInt8);
    return GlfwIVec2{ x: read_i32_le(&sw, 0); y: read_i32_le(&sh, 0); };
  }
}

/// glfwGetWindowFrameSize() -> (left, top, right, bottom).
/// Complexity: O(1).
pub fn glfw_get_window_frame_size(lib: &GlfwLibrary, w: &GlfwWindow) -> GlfwFrameSize
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    var sl = slot_new(4);
    var st = slot_new(4);
    var sr = slot_new(4);
    var sb = slot_new(4);
    let f = lib.p_get_window_frame_size as fn(*UInt8, *UInt8, *UInt8, *UInt8, *UInt8);
    f(w.handle as *UInt8, sl.as_mut_ptr() as *UInt8, st.as_mut_ptr() as *UInt8,
      sr.as_mut_ptr() as *UInt8, sb.as_mut_ptr() as *UInt8);
    return GlfwFrameSize{ left: read_i32_le(&sl, 0); top: read_i32_le(&st, 0);
                          right: read_i32_le(&sr, 0); bottom: read_i32_le(&sb, 0); };
  }
}

/// glfwGetWindowContentScale() -> (xscale, yscale).
/// Complexity: O(1).
pub fn glfw_get_window_content_scale(lib: &GlfwLibrary, w: &GlfwWindow) -> GlfwFVec2
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    var sx = slot_new(4);
    var sy = slot_new(4);
    let f = lib.p_get_window_content_scale as fn(*UInt8, *UInt8, *UInt8);
    f(w.handle as *UInt8, sx.as_mut_ptr() as *UInt8, sy.as_mut_ptr() as *UInt8);
    return GlfwFVec2{ x: read_f32_le(&sx, 0);
                      y: read_f32_le(&sy, 0); };
  }
}

/// glfwGetWindowOpacity().
/// Complexity: O(1).
pub fn glfw_get_window_opacity(lib: &GlfwLibrary, w: &GlfwWindow) -> Float64
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_get_window_opacity as fn(*UInt8) -> Float32;
    let v: Float32 = f(w.handle as *UInt8);
    return v as Float64;
  }
}

/// glfwSetWindowOpacity(opacity).
/// Complexity: O(1).
pub fn glfw_set_window_opacity(lib: &GlfwLibrary, w: &GlfwWindow, opacity: Float32)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_window_opacity as fn(*UInt8, Float32);
    f(w.handle as *UInt8, opacity);
  }
}

/// glfwIconifyWindow().
/// Complexity: O(1).
pub fn glfw_iconify_window(lib: &GlfwLibrary, w: &GlfwWindow)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_iconify_window as fn(*UInt8);
    f(w.handle as *UInt8);
  }
}

/// glfwRestoreWindow().
/// Complexity: O(1).
pub fn glfw_restore_window(lib: &GlfwLibrary, w: &GlfwWindow)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_restore_window as fn(*UInt8);
    f(w.handle as *UInt8);
  }
}

/// glfwMaximizeWindow().
/// Complexity: O(1).
pub fn glfw_maximize_window(lib: &GlfwLibrary, w: &GlfwWindow)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_maximize_window as fn(*UInt8);
    f(w.handle as *UInt8);
  }
}

/// glfwShowWindow().
/// Complexity: O(1).
pub fn glfw_show_window(lib: &GlfwLibrary, w: &GlfwWindow)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_show_window as fn(*UInt8);
    f(w.handle as *UInt8);
  }
}

/// glfwHideWindow().
/// Complexity: O(1).
pub fn glfw_hide_window(lib: &GlfwLibrary, w: &GlfwWindow)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_hide_window as fn(*UInt8);
    f(w.handle as *UInt8);
  }
}

/// glfwFocusWindow().
/// Complexity: O(1).
pub fn glfw_focus_window(lib: &GlfwLibrary, w: &GlfwWindow)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_focus_window as fn(*UInt8);
    f(w.handle as *UInt8);
  }
}

/// glfwRequestWindowAttention().
/// Complexity: O(1).
pub fn glfw_request_window_attention(lib: &GlfwLibrary, w: &GlfwWindow)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_request_window_attention as fn(*UInt8);
    f(w.handle as *UInt8);
  }
}

/// glfwGetWindowMonitor() -> raw monitor handle (0 = windowed).
/// Complexity: O(1).
pub fn glfw_get_window_monitor(lib: &GlfwLibrary, w: &GlfwWindow) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_get_window_monitor as fn(*UInt8) -> *UInt8;
    return f(w.handle as *UInt8) as Int;
  }
}

/// glfwSetWindowMonitor(monitor, x, y, width, height, refresh_rate);
/// `monitor` 0 = windowed mode.
/// Complexity: O(1).
pub fn glfw_set_window_monitor(lib: &GlfwLibrary, w: &GlfwWindow, monitor: Int,
    x: Int, y: Int, width: Int, height: Int, refresh_rate: Int)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_window_monitor as fn(*UInt8, *UInt8, Int32, Int32, Int32, Int32, Int32);
    f(w.handle as *UInt8, monitor as *UInt8, x as Int32, y as Int32,
      width as Int32, height as Int32, refresh_rate as Int32);
  }
}

/// glfwGetWindowAttrib(attrib).
/// Complexity: O(1).
pub fn glfw_get_window_attrib(lib: &GlfwLibrary, w: &GlfwWindow, attrib: Int) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_get_window_attrib as fn(*UInt8, Int32) -> Int32;
    return f(w.handle as *UInt8, attrib as Int32) as Int;
  }
}

/// glfwSetWindowAttrib(attrib, value).
/// Complexity: O(1).
pub fn glfw_set_window_attrib(lib: &GlfwLibrary, w: &GlfwWindow, attrib: Int, value: Int)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_window_attrib as fn(*UInt8, Int32, Int32);
    f(w.handle as *UInt8, attrib as Int32, value as Int32);
  }
}

/// glfwSetWindowUserPointer(pointer).
/// Complexity: O(1).
pub fn glfw_set_window_user_pointer(lib: &GlfwLibrary, w: &GlfwWindow, pointer: Int)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_window_user_pointer as fn(*UInt8, *UInt8);
    f(w.handle as *UInt8, pointer as *UInt8);
  }
}

/// glfwGetWindowUserPointer().
/// Complexity: O(1).
pub fn glfw_get_window_user_pointer(lib: &GlfwLibrary, w: &GlfwWindow) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_get_window_user_pointer as fn(*UInt8) -> *UInt8;
    return f(w.handle as *UInt8) as Int;
  }
}

// =========================================================================
// Events
// =========================================================================

/// glfwPollEvents().
/// Complexity: O(events).
pub fn glfw_poll_events(lib: &GlfwLibrary)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_poll_events as fn();
    f();
  }
}

/// glfwWaitEvents() (blocks until at least one event).
/// Complexity: O(events).
pub fn glfw_wait_events(lib: &GlfwLibrary)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_wait_events as fn();
    f();
  }
}

/// glfwWaitEventsTimeout(seconds).
/// Complexity: O(events).
pub fn glfw_wait_events_timeout(lib: &GlfwLibrary, seconds: Float64)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_wait_events_timeout as fn(Float64);
    f(seconds);
  }
}

/// glfwPostEmptyEvent().
/// Complexity: O(1).
pub fn glfw_post_empty_event(lib: &GlfwLibrary)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_post_empty_event as fn();
    f();
  }
}

// =========================================================================
// Input (polling)
// =========================================================================

/// glfwGetInputMode(mode).
/// Complexity: O(1).
pub fn glfw_get_input_mode(lib: &GlfwLibrary, w: &GlfwWindow, mode: Int) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_get_input_mode as fn(*UInt8, Int32) -> Int32;
    return f(w.handle as *UInt8, mode as Int32) as Int;
  }
}

/// glfwSetInputMode(mode, value).
/// Complexity: O(1).
pub fn glfw_set_input_mode(lib: &GlfwLibrary, w: &GlfwWindow, mode: Int, value: Int)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_input_mode as fn(*UInt8, Int32, Int32);
    f(w.handle as *UInt8, mode as Int32, value as Int32);
  }
}

/// glfwRawMouseMotionSupported().
/// Complexity: O(1).
pub fn glfw_raw_mouse_motion_supported(lib: &GlfwLibrary) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_raw_mouse_motion_supported as fn() -> Int32;
    return f() != 0;
  }
}

/// glfwGetKeyName(key, scancode) ("" when the key has no name).
/// Complexity: O(len).
pub fn glfw_get_key_name(lib: &GlfwLibrary, key: Int, scancode: Int) -> Str
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_key_name as fn(Int32, Int32) -> *UInt8;
    let p = f(key as Int32, scancode as Int32);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// glfwGetKeyScancode(key).
/// Complexity: O(1).
pub fn glfw_get_key_scancode(lib: &GlfwLibrary, key: Int) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_key_scancode as fn(Int32) -> Int32;
    return f(key as Int32) as Int;
  }
}

/// glfwGetKey(key) -> GLFW_PRESS / GLFW_RELEASE / GLFW_REPEAT.
/// Complexity: O(1).
pub fn glfw_get_key(lib: &GlfwLibrary, w: &GlfwWindow, key: Int) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_get_key as fn(*UInt8, Int32) -> Int32;
    return f(w.handle as *UInt8, key as Int32) as Int;
  }
}

/// glfwGetMouseButton(button).
/// Complexity: O(1).
pub fn glfw_get_mouse_button(lib: &GlfwLibrary, w: &GlfwWindow, button: Int) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_get_mouse_button as fn(*UInt8, Int32) -> Int32;
    return f(w.handle as *UInt8, button as Int32) as Int;
  }
}

/// glfwGetCursorPos() -> (x, y).
/// Complexity: O(1).
pub fn glfw_get_cursor_pos(lib: &GlfwLibrary, w: &GlfwWindow) -> GlfwCursorPos
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    var sx = slot_new(8);
    var sy = slot_new(8);
    let f = lib.p_get_cursor_pos as fn(*UInt8, *UInt8, *UInt8);
    f(w.handle as *UInt8, sx.as_mut_ptr() as *UInt8, sy.as_mut_ptr() as *UInt8);
    return GlfwCursorPos{ x: read_f64_le(&sx, 0); y: read_f64_le(&sy, 0); };
  }
}

/// glfwSetCursorPos(x, y).
/// Complexity: O(1).
pub fn glfw_set_cursor_pos(lib: &GlfwLibrary, w: &GlfwWindow, x: Float64, y: Float64)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_cursor_pos as fn(*UInt8, Float64, Float64);
    f(w.handle as *UInt8, x, y);
  }
}

// =========================================================================
// Monitors
// =========================================================================

/// glfwGetMonitors() -> raw monitor handles (wrap with
/// `GlfwMonitor{ handle: m }` for the monitor functions).  A Vec[Int] keeps
/// clear of the Vec-of-struct element-extraction codegen bug.
/// Complexity: O(monitors).
pub fn glfw_get_monitors(lib: &GlfwLibrary) -> Vec[Int]
  requires: lib.handle != 0
{
  unsafe {
    var sc = slot_new(4);
    let f = lib.p_get_monitors as fn(*UInt8) -> *UInt8;
    let arr = f(sc.as_mut_ptr() as *UInt8);
    var out: Vec[Int] = Vec[Int].new();
    let n = read_i32_le(&sc, 0);
    if (arr as Int) == 0 || n <= 0 { return out; }
    let buf = copy_from(arr as Int, n * 8);
    var i = 0;
    while i < n {
      out.push(read_u64_le(&buf, i * 8));
      i = i + 1;
    }
    return out;
  }
}

/// glfwGetPrimaryMonitor() -> raw monitor handle.
/// Complexity: O(1).
pub fn glfw_get_primary_monitor(lib: &GlfwLibrary) -> Result[Int, Str]
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_primary_monitor as fn() -> *UInt8;
    let p = f();
    if (p as Int) == 0 {
      return Err(glfw_last_error(lib));
    }
    return Ok(p as Int);
  }
}

/// glfwGetMonitorPos() -> (x, y).
/// Complexity: O(1).
pub fn glfw_get_monitor_pos(lib: &GlfwLibrary, m: &GlfwMonitor) -> GlfwIVec2
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    var sx = slot_new(4);
    var sy = slot_new(4);
    let f = lib.p_get_monitor_pos as fn(*UInt8, *UInt8, *UInt8);
    f(m.handle as *UInt8, sx.as_mut_ptr() as *UInt8, sy.as_mut_ptr() as *UInt8);
    return GlfwIVec2{ x: read_i32_le(&sx, 0); y: read_i32_le(&sy, 0); };
  }
}

/// glfwGetMonitorWorkarea().
/// Complexity: O(1).
pub fn glfw_get_monitor_workarea(lib: &GlfwLibrary, m: &GlfwMonitor) -> GlfwRect
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    var sx = slot_new(4);
    var sy = slot_new(4);
    var sw = slot_new(4);
    var sh = slot_new(4);
    let f = lib.p_get_monitor_workarea as fn(*UInt8, *UInt8, *UInt8, *UInt8, *UInt8);
    f(m.handle as *UInt8, sx.as_mut_ptr() as *UInt8, sy.as_mut_ptr() as *UInt8,
      sw.as_mut_ptr() as *UInt8, sh.as_mut_ptr() as *UInt8);
    return GlfwRect{ x: read_i32_le(&sx, 0); y: read_i32_le(&sy, 0);
                     width: read_i32_le(&sw, 0); height: read_i32_le(&sh, 0); };
  }
}

/// glfwGetMonitorPhysicalSize() -> (width_mm, height_mm).
/// Complexity: O(1).
pub fn glfw_get_monitor_physical_size(lib: &GlfwLibrary, m: &GlfwMonitor) -> GlfwIVec2
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    var sw = slot_new(4);
    var sh = slot_new(4);
    let f = lib.p_get_monitor_physical_size as fn(*UInt8, *UInt8, *UInt8);
    f(m.handle as *UInt8, sw.as_mut_ptr() as *UInt8, sh.as_mut_ptr() as *UInt8);
    return GlfwIVec2{ x: read_i32_le(&sw, 0); y: read_i32_le(&sh, 0); };
  }
}

/// glfwGetMonitorContentScale() -> (xscale, yscale).
/// Complexity: O(1).
pub fn glfw_get_monitor_content_scale(lib: &GlfwLibrary, m: &GlfwMonitor) -> GlfwFVec2
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    var sx = slot_new(4);
    var sy = slot_new(4);
    let f = lib.p_get_monitor_content_scale as fn(*UInt8, *UInt8, *UInt8);
    f(m.handle as *UInt8, sx.as_mut_ptr() as *UInt8, sy.as_mut_ptr() as *UInt8);
    return GlfwFVec2{ x: read_f32_le(&sx, 0);
                      y: read_f32_le(&sy, 0); };
  }
}

/// glfwGetMonitorName() ("" when NULL).
/// Complexity: O(len).
pub fn glfw_get_monitor_name(lib: &GlfwLibrary, m: &GlfwMonitor) -> Str
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    let f = lib.p_get_monitor_name as fn(*UInt8) -> *UInt8;
    let p = f(m.handle as *UInt8);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// glfwSetMonitorUserPointer(pointer).
/// Complexity: O(1).
pub fn glfw_set_monitor_user_pointer(lib: &GlfwLibrary, m: &GlfwMonitor, pointer: Int)
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    let f = lib.p_set_monitor_user_pointer as fn(*UInt8, *UInt8);
    f(m.handle as *UInt8, pointer as *UInt8);
  }
}

/// glfwGetMonitorUserPointer().
/// Complexity: O(1).
pub fn glfw_get_monitor_user_pointer(lib: &GlfwLibrary, m: &GlfwMonitor) -> Int
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    let f = lib.p_get_monitor_user_pointer as fn(*UInt8) -> *UInt8;
    return f(m.handle as *UInt8) as Int;
  }
}

/// glfwGetVideoModes() -> packed 24-byte records (width, height, red_bits,
/// green_bits, blue_bits, refresh_rate as little-endian int32 x6).  Decode
/// with `glfw_vidmode_count` / `glfw_vidmode_at` (raw buffer; keeps clear of
/// the Vec-of-struct element-extraction codegen bug).
/// Complexity: O(modes).
pub fn glfw_get_video_modes_raw(lib: &GlfwLibrary, m: &GlfwMonitor) -> Vec[UInt8]
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    var sc = slot_new(4);
    let f = lib.p_get_video_modes as fn(*UInt8, *UInt8) -> *UInt8;
    let arr = f(m.handle as *UInt8, sc.as_mut_ptr() as *UInt8);
    let n = read_i32_le(&sc, 0);
    if (arr as Int) == 0 || n <= 0 {
      var e: Vec[UInt8] = Vec[UInt8].new();
      return e;
    }
    return copy_from(arr as Int, n * 24);
  }
}

/// Number of records in a `glfw_get_video_modes_raw` buffer.
/// Complexity: O(1).
pub fn glfw_vidmode_count(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 24
{
  return buf.len() / 24;
}

/// Decode record `i` from a `glfw_get_video_modes_raw` buffer.
/// Complexity: O(1).
pub fn glfw_vidmode_at(buf: &Vec[UInt8], i: Int) -> GlfwVidmode
  requires: i >= 0
  requires: buf.len() >= (i + 1) * 24
{
  let o = i * 24;
  return GlfwVidmode{
    width: read_i32_le(buf, o + 0);
    height: read_i32_le(buf, o + 4);
    red_bits: read_i32_le(buf, o + 8);
    green_bits: read_i32_le(buf, o + 12);
    blue_bits: read_i32_le(buf, o + 16);
    refresh_rate: read_i32_le(buf, o + 20);
  };
}

/// glfwGetVideoMode() -> the monitor's current mode.
/// Complexity: O(1).
pub fn glfw_get_video_mode(lib: &GlfwLibrary, m: &GlfwMonitor) -> GlfwVidmode
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    let f = lib.p_get_video_mode as fn(*UInt8) -> *UInt8;
    let p = f(m.handle as *UInt8);
    if (p as Int) == 0 {
      return GlfwVidmode{ width: 0; height: 0; red_bits: 0;
                          green_bits: 0; blue_bits: 0; refresh_rate: 0; };
    }
    let buf = copy_from(p as Int, 24);
    return GlfwVidmode{
      width: read_i32_le(&buf, 0);
      height: read_i32_le(&buf, 4);
      red_bits: read_i32_le(&buf, 8);
      green_bits: read_i32_le(&buf, 12);
      blue_bits: read_i32_le(&buf, 16);
      refresh_rate: read_i32_le(&buf, 20);
    };
  }
}

/// glfwSetGamma(gamma).
/// Complexity: O(gamma table).
pub fn glfw_set_gamma(lib: &GlfwLibrary, m: &GlfwMonitor, gamma: Float32)
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    let f = lib.p_set_gamma as fn(*UInt8, Float32);
    f(m.handle as *UInt8, gamma);
  }
}

// =========================================================================
// Clipboard
// =========================================================================

/// glfwSetClipboardString(string).
/// Complexity: O(len).
pub fn glfw_set_clipboard_string(lib: &GlfwLibrary, w: &GlfwWindow, s: Str)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_clipboard_string as fn(*UInt8, *UInt8);
    f(w.handle as *UInt8, s as *UInt8);
  }
}

/// glfwGetClipboardString() ("" when empty/NULL).
/// Complexity: O(len).
pub fn glfw_get_clipboard_string(lib: &GlfwLibrary, w: &GlfwWindow) -> Str
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_get_clipboard_string as fn(*UInt8) -> *UInt8;
    let p = f(w.handle as *UInt8);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

// =========================================================================
// Time
// =========================================================================

/// glfwGetTime() -> seconds since glfwInit (0.0 before init).
/// Complexity: O(1).
pub fn glfw_get_time(lib: &GlfwLibrary) -> Float64
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_time as fn() -> Float64;
    return f();
  }
}

/// glfwSetTime(time).
/// Complexity: O(1).
pub fn glfw_set_time(lib: &GlfwLibrary, time: Float64)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_set_time as fn(Float64);
    f(time);
  }
}

/// glfwGetTimerValue() -> raw timer ticks.
/// Complexity: O(1).
pub fn glfw_get_timer_value(lib: &GlfwLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_timer_value as fn() -> Int64;
    return f() as Int;
  }
}

/// glfwGetTimerFrequency() -> ticks per second.
/// Complexity: O(1).
pub fn glfw_get_timer_frequency(lib: &GlfwLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_timer_frequency as fn() -> Int64;
    return f() as Int;
  }
}

// =========================================================================
// GL context basics
// =========================================================================

/// glfwMakeContextCurrent(window).
/// Complexity: O(1).
pub fn glfw_make_context_current(lib: &GlfwLibrary, w: &GlfwWindow)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_make_context_current as fn(*UInt8);
    f(w.handle as *UInt8);
  }
}

/// glfwGetCurrentContext() -> raw handle (0 when none).
/// Complexity: O(1).
pub fn glfw_get_current_context(lib: &GlfwLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_current_context as fn() -> *UInt8;
    return f() as Int;
  }
}

/// glfwSwapBuffers().
/// Complexity: O(1).
pub fn glfw_swap_buffers(lib: &GlfwLibrary, w: &GlfwWindow)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_swap_buffers as fn(*UInt8);
    f(w.handle as *UInt8);
  }
}

/// glfwSwapInterval(interval).
/// Complexity: O(1).
pub fn glfw_swap_interval(lib: &GlfwLibrary, interval: Int)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_swap_interval as fn(Int32);
    f(interval as Int32);
  }
}

/// glfwExtensionSupported(extension).
/// Complexity: O(len).
pub fn glfw_extension_supported(lib: &GlfwLibrary, name: Str) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_extension_supported as fn(*UInt8) -> Int32;
    return f(name as *UInt8) != 0;
  }
}

/// glfwGetProcAddress(procname) -> raw GL proc address (0 when absent).
/// Complexity: O(len).
pub fn glfw_get_proc_address(lib: &GlfwLibrary, name: Str) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_proc_address as fn(*UInt8) -> *UInt8;
    return f(name as *UInt8) as Int;
  }
}

// =========================================================================
// Win32 native accessors
// =========================================================================

/// glfwGetWin32Adapter() ("" when NULL).
/// Complexity: O(len).
pub fn glfw_get_win32_adapter(lib: &GlfwLibrary, m: &GlfwMonitor) -> Str
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    let f = lib.p_get_win32_adapter as fn(*UInt8) -> *UInt8;
    let p = f(m.handle as *UInt8);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// glfwGetWin32Monitor() -> HMONITOR (0 when none).
/// Complexity: O(1).
pub fn glfw_get_win32_monitor(lib: &GlfwLibrary, m: &GlfwMonitor) -> Int
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    let f = lib.p_get_win32_monitor as fn(*UInt8) -> *UInt8;
    return f(m.handle as *UInt8) as Int;
  }
}

/// glfwGetWin32Window() -> HWND (for Vulkan surfaces / engine interop).
/// Complexity: O(1).
pub fn glfw_get_win32_window(lib: &GlfwLibrary, w: &GlfwWindow) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_get_win32_window as fn(*UInt8) -> *UInt8;
    return f(w.handle as *UInt8) as Int;
  }
}

// =========================================================================
// Vulkan helpers (optional exports; Err when the build lacks them)
// =========================================================================

/// glfwVulkanSupported().
/// Complexity: O(1).
pub fn glfw_vulkan_supported(lib: &GlfwLibrary) -> Result[Bool, Str]
  requires: lib.handle != 0
{
  if lib.p_vulkan_supported == 0 {
    return Err("glfwVulkanSupported not exported by this GLFW build");
  }
  unsafe {
    let f = lib.p_vulkan_supported as fn() -> Int32;
    return Ok(f() != 0);
  }
}

/// glfwGetRequiredInstanceExtensions() -> names required to create a
/// Vulkan instance for window surfaces (struct payload; see `GlfwExtNames`).
/// Complexity: O(extensions).
pub fn glfw_get_required_instance_extensions(lib: &GlfwLibrary) -> Result[GlfwExtNames, Str]
  requires: lib.handle != 0
{
  if lib.p_get_required_instance_extensions == 0 {
    return Err("glfwGetRequiredInstanceExtensions not exported by this GLFW build");
  }
  unsafe {
    var sc = slot_new(4);
    let f = lib.p_get_required_instance_extensions as fn(*UInt8) -> *UInt8;
    let arr = f(sc.as_mut_ptr() as *UInt8);
    let n = read_i32_le(&sc, 0);
    if (arr as Int) == 0 || n <= 0 {
      return Err(glfw_last_error(lib));
    }
    let buf = copy_from(arr as Int, n * 8);
    var p0 = 0;
    var p1 = 0;
    if n > 0 { p0 = read_u64_le(&buf, 0); }
    if n > 1 { p1 = read_u64_le(&buf, 8); }
    return Ok(GlfwExtNames{ count: n; p0: p0; p1: p1; });
  }
}

/// glfwGetInstanceProcAddress(instance, procname) -> raw proc address.
/// Complexity: O(len).
pub fn glfw_get_instance_proc_address(lib: &GlfwLibrary, instance: Int, name: Str) -> Int
  requires: lib.handle != 0
{
  if lib.p_get_instance_proc_address == 0 {
    return 0;
  }
  unsafe {
    let f = lib.p_get_instance_proc_address as fn(*UInt8, *UInt8) -> *UInt8;
    return f(instance as *UInt8, name as *UInt8) as Int;
  }
}

/// glfwGetPhysicalDevicePresentationSupport(instance, device, queue_family).
/// Complexity: O(1).
pub fn glfw_get_physical_device_presentation_support(lib: &GlfwLibrary, instance: Int,
    device: Int, queue_family: Int) -> Result[Bool, Str]
  requires: lib.handle != 0
{
  if lib.p_get_physical_device_presentation_support == 0 {
    return Err("glfwGetPhysicalDevicePresentationSupport not exported by this GLFW build");
  }
  unsafe {
    let f = lib.p_get_physical_device_presentation_support as fn(*UInt8, *UInt8, Int32) -> Int32;
    return Ok(f(instance as *UInt8, device as *UInt8, queue_family as Int32) != 0);
  }
}

/// glfwCreateWindowSurface(instance, window) -> VkSurfaceKHR (Int handle).
/// Complexity: O(1).
pub fn glfw_create_window_surface(lib: &GlfwLibrary, instance: Int, w: &GlfwWindow)
    -> Result[Int, Str]
  requires: lib.handle != 0
  requires: w.handle != 0
{
  if lib.p_create_window_surface == 0 {
    return Err("glfwCreateWindowSurface not exported by this GLFW build");
  }
  unsafe {
    var ss = slot_new(8);
    let f = lib.p_create_window_surface as fn(*UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    let rc = f(instance as *UInt8, w.handle as *UInt8, 0 as *UInt8,
               ss.as_mut_ptr() as *UInt8) as Int;
    if rc != 0 {
      return Err("glfwCreateWindowSurface failed: VkResult " + int_to_string(rc));
    }
    return Ok(read_u64_le(&ss, 0));
  }
}

// =========================================================================
// 0.4.0: gamma ramps, cursors, window icon, joystick/gamepad, loader hook
// =========================================================================

/// Build a GLFWimage record (width i32, height i32, pixels ptr) in an
/// XIOM-owned slot pointing at `rgba`.
fn glfw_make_image(width: Int, height: Int, rgba: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  requires: width > 0
  requires: height > 0
  requires: rgba.len() >= width * height * 4
{
  var img = slot_new(16);
  unsafe {
    let raw = img.as_mut_ptr() as *UInt8;
    let r = safe_ptr_from_raw(raw, 16);
    if !r.is_ok {
      return Err("image slot wrap failed: " + r.error);
    }
    var sp = r.value;
    var a = safe_ptr_write_i32(&mut sp, 0, width);
    var b = safe_ptr_write_i32(&mut sp, 4, height);
    var c = safe_ptr_write_i64(&mut sp, 8, rgba.as_mut_ptr() as Int);
    if !a.is_ok || !b.is_ok || !c.is_ok {
      return Err("image slot write failed");
    }
  }
  return Ok(img);
}

/// glfwGetGammaRamp() -> raw GLFWgammaramp copy (1536 bytes: little-endian
/// u16 red[256] + green[256] + blue[256]).  Empty when the monitor has none.
/// Complexity: O(1).
pub fn glfw_get_gamma_ramp_raw(lib: &GlfwLibrary, m: &GlfwMonitor) -> Vec[UInt8]
  requires: lib.handle != 0
  requires: m.handle != 0
{
  unsafe {
    let f = lib.p_get_gamma_ramp as fn(*UInt8) -> *UInt8;
    let p = f(m.handle as *UInt8);
    if (p as Int) == 0 {
      var e: Vec[UInt8] = Vec[UInt8].new();
      return e;
    }
    return copy_from(p as Int, 1536);
  }
}

/// glfwSetGammaRamp() from a raw 1536-byte ramp buffer.
/// Complexity: O(1).
pub fn glfw_set_gamma_ramp_raw(lib: &GlfwLibrary, m: &GlfwMonitor, buf: &Vec[UInt8])
  requires: lib.handle != 0
  requires: m.handle != 0
  requires: buf.len() == 1536
{
  unsafe {
    let f = lib.p_set_gamma_ramp as fn(*UInt8, *UInt8);
    f(m.handle as *UInt8, buf.as_mut_ptr() as *UInt8);
  }
}

/// glfwSetWindowIcon() with a single RGBA8 image.
/// Complexity: O(w*h).
pub fn glfw_set_window_icon(lib: &GlfwLibrary, w: &GlfwWindow, width: Int, height: Int,
    rgba: &Vec[UInt8]) -> Result[Unit, Str]
  requires: lib.handle != 0
  requires: w.handle != 0
  requires: width > 0
  requires: height > 0
  requires: rgba.len() >= width * height * 4
{
  let mk = glfw_make_image(width, height, rgba);
  if !mk.is_ok {
    return Err(mk.error);
  }
  var img: Vec[UInt8] = mk.value;
  unsafe {
    let f = lib.p_set_window_icon as fn(*UInt8, Int32, *UInt8);
    f(w.handle as *UInt8, 1, img.as_mut_ptr() as *UInt8);
  }
  return Ok(());
}

/// glfwCreateStandardCursor(shape) -> cursor handle (0 = failure).
/// Complexity: O(1).
pub fn glfw_create_standard_cursor(lib: &GlfwLibrary, shape: Int) -> Result[Int, Str]
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_create_standard_cursor as fn(Int32) -> *UInt8;
    let p = f(shape as Int32);
    if (p as Int) == 0 {
      return Err(glfw_last_error(lib));
    }
    return Ok(p as Int);
  }
}

/// glfwCreateCursor() from RGBA8 pixels.
/// Complexity: O(w*h).
pub fn glfw_create_cursor(lib: &GlfwLibrary, width: Int, height: Int, xhot: Int, yhot: Int,
    rgba: &Vec[UInt8]) -> Result[Int, Str]
  requires: lib.handle != 0
  requires: width > 0
  requires: height > 0
  requires: rgba.len() >= width * height * 4
{
  let mk = glfw_make_image(width, height, rgba);
  if !mk.is_ok {
    return Err(mk.error);
  }
  var img: Vec[UInt8] = mk.value;
  unsafe {
    let f = lib.p_create_cursor as fn(*UInt8, Int32, Int32) -> *UInt8;
    let p = f(img.as_mut_ptr() as *UInt8, xhot as Int32, yhot as Int32);
    if (p as Int) == 0 {
      return Err(glfw_last_error(lib));
    }
    return Ok(p as Int);
  }
}

/// glfwDestroyCursor().
/// Complexity: O(1).
pub fn glfw_destroy_cursor(lib: &GlfwLibrary, cursor: Int)
  requires: lib.handle != 0
  requires: cursor != 0
{
  unsafe {
    let f = lib.p_destroy_cursor as fn(*UInt8);
    f(cursor as *UInt8);
  }
}

/// glfwSetCursor() (0 restores the default arrow).
/// Complexity: O(1).
pub fn glfw_set_cursor(lib: &GlfwLibrary, w: &GlfwWindow, cursor: Int)
  requires: lib.handle != 0
  requires: w.handle != 0
{
  unsafe {
    let f = lib.p_set_cursor as fn(*UInt8, *UInt8);
    f(w.handle as *UInt8, cursor as *UInt8);
  }
}

/// glfwJoystickPresent().
/// Complexity: O(1).
pub fn glfw_joystick_present(lib: &GlfwLibrary, jid: Int) -> Bool
  requires: lib.handle != 0
  requires: jid >= 0 && jid < 16
{
  unsafe {
    let f = lib.p_joystick_present as fn(Int32) -> Int32;
    return f(jid as Int32) != 0;
  }
}

/// glfwGetJoystickAxes() -> raw f32 little-endian pairs (4 bytes per axis);
/// empty when the joystick is absent.
/// Complexity: O(axes).
pub fn glfw_get_joystick_axes_raw(lib: &GlfwLibrary, jid: Int) -> Vec[UInt8]
  requires: lib.handle != 0
  requires: jid >= 0 && jid < 16
{
  unsafe {
    var sc = slot_new(4);
    let f = lib.p_get_joystick_axes as fn(Int32, *UInt8) -> *UInt8;
    let p = f(jid as Int32, sc.as_mut_ptr() as *UInt8);
    let n = read_i32_le(&sc, 0);
    if (p as Int) == 0 || n <= 0 {
      var e: Vec[UInt8] = Vec[UInt8].new();
      return e;
    }
    return copy_from(p as Int, n * 4);
  }
}

/// glfwGetJoystickButtons() -> raw button bytes; empty when absent.
/// Complexity: O(buttons).
pub fn glfw_get_joystick_buttons_raw(lib: &GlfwLibrary, jid: Int) -> Vec[UInt8]
  requires: lib.handle != 0
  requires: jid >= 0 && jid < 16
{
  unsafe {
    var sc = slot_new(4);
    let f = lib.p_get_joystick_buttons as fn(Int32, *UInt8) -> *UInt8;
    let p = f(jid as Int32, sc.as_mut_ptr() as *UInt8);
    let n = read_i32_le(&sc, 0);
    if (p as Int) == 0 || n <= 0 {
      var e: Vec[UInt8] = Vec[UInt8].new();
      return e;
    }
    return copy_from(p as Int, n);
  }
}

/// glfwGetJoystickHats() -> raw hat bytes; empty when absent.
/// Complexity: O(hats).
pub fn glfw_get_joystick_hats_raw(lib: &GlfwLibrary, jid: Int) -> Vec[UInt8]
  requires: lib.handle != 0
  requires: jid >= 0 && jid < 16
{
  unsafe {
    var sc = slot_new(4);
    let f = lib.p_get_joystick_hats as fn(Int32, *UInt8) -> *UInt8;
    let p = f(jid as Int32, sc.as_mut_ptr() as *UInt8);
    let n = read_i32_le(&sc, 0);
    if (p as Int) == 0 || n <= 0 {
      var e: Vec[UInt8] = Vec[UInt8].new();
      return e;
    }
    return copy_from(p as Int, n);
  }
}

/// glfwGetJoystickName() ("" when absent/NULL).
/// Complexity: O(len).
pub fn glfw_get_joystick_name(lib: &GlfwLibrary, jid: Int) -> Str
  requires: lib.handle != 0
  requires: jid >= 0 && jid < 16
{
  unsafe {
    let f = lib.p_get_joystick_name as fn(Int32) -> *UInt8;
    let p = f(jid as Int32);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// glfwGetJoystickGUID() ("" when absent/NULL).
/// Complexity: O(len).
pub fn glfw_get_joystick_guid(lib: &GlfwLibrary, jid: Int) -> Str
  requires: lib.handle != 0
  requires: jid >= 0 && jid < 16
{
  unsafe {
    let f = lib.p_get_joystick_guid as fn(Int32) -> *UInt8;
    let p = f(jid as Int32);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// glfwSetJoystickUserPointer().
/// Complexity: O(1).
pub fn glfw_set_joystick_user_pointer(lib: &GlfwLibrary, jid: Int, pointer: Int)
  requires: lib.handle != 0
  requires: jid >= 0 && jid < 16
{
  unsafe {
    let f = lib.p_set_joystick_user_pointer as fn(Int32, *UInt8);
    f(jid as Int32, pointer as *UInt8);
  }
}

/// glfwGetJoystickUserPointer().
/// Complexity: O(1).
pub fn glfw_get_joystick_user_pointer(lib: &GlfwLibrary, jid: Int) -> Int
  requires: lib.handle != 0
  requires: jid >= 0 && jid < 16
{
  unsafe {
    let f = lib.p_get_joystick_user_pointer as fn(Int32) -> *UInt8;
    return f(jid as Int32) as Int;
  }
}

/// glfwJoystickIsGamepad().
/// Complexity: O(1).
pub fn glfw_joystick_is_gamepad(lib: &GlfwLibrary, jid: Int) -> Bool
  requires: lib.handle != 0
  requires: jid >= 0 && jid < 16
{
  unsafe {
    let f = lib.p_joystick_is_gamepad as fn(Int32) -> Int32;
    return f(jid as Int32) != 0;
  }
}

/// glfwGetGamepadName() ("" when not a gamepad).
/// Complexity: O(len).
pub fn glfw_get_gamepad_name(lib: &GlfwLibrary, jid: Int) -> Str
  requires: lib.handle != 0
  requires: jid >= 0 && jid < 16
{
  unsafe {
    let f = lib.p_get_gamepad_name as fn(Int32) -> *UInt8;
    let p = f(jid as Int32);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// glfwGetGamepadState() -> raw 40-byte GLFWgamepadstate copy
/// (15 button bytes at 0..14, 16 bytes pad, 6 little-endian f32 axes at
/// 16..39).  Empty when the jid is not a gamepad.
/// Complexity: O(1).
pub fn glfw_get_gamepad_state_raw(lib: &GlfwLibrary, jid: Int) -> Vec[UInt8]
  requires: lib.handle != 0
  requires: jid >= 0 && jid < 16
{
  unsafe {
    var s = slot_new(40);
    let f = lib.p_get_gamepad_state as fn(Int32, *UInt8) -> Int32;
    let rc = f(jid as Int32, s.as_mut_ptr() as *UInt8);
    if rc == 0 {
      var e: Vec[UInt8] = Vec[UInt8].new();
      return e;
    }
    return s;
  }
}

/// Button byte from a `glfw_get_gamepad_state_raw` buffer.
/// Complexity: O(1).
pub fn glfw_gamepad_button(buf: &Vec[UInt8], i: Int) -> Int
  requires: i >= 0
  requires: i < 15
  requires: buf.len() >= 40
{
  return buf[i] as Int;
}

/// Axis value from a `glfw_get_gamepad_state_raw` buffer (f32 decode).
/// Complexity: O(1).
pub fn glfw_gamepad_axis(buf: &Vec[UInt8], i: Int) -> Float64
  requires: i >= 0
  requires: i < 6
  requires: buf.len() >= 40
{
  return f32_from_bits(read_u32_le(buf, 16 + i * 4));
}

/// glfwUpdateGamepadMappings() from a mapping string.
/// Complexity: O(len).
pub fn glfw_update_gamepad_mappings(lib: &GlfwLibrary, mappings: Str) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_update_gamepad_mappings as fn(*UInt8) -> Int32;
    return f(mappings as *UInt8) != 0;
  }
}

/// glfwInitVulkanLoader() -- pass the address of a custom
/// `vkGetInstanceProcAddr` (e.g. from the crafted loader) BEFORE `glfwInit`.
/// Complexity: O(1).
pub fn glfw_init_vulkan_loader(lib: &GlfwLibrary, get_instance_proc_addr: Int)
  requires: lib.handle != 0
  requires: get_instance_proc_addr != 0
{
  unsafe {
    let f = lib.p_init_vulkan_loader as fn(*UInt8);
    f(get_instance_proc_addr as *UInt8);
  }
}

// =========================================================================
// 0.5.0: event-callback setters + glfwInitAllocator (124/124)
//
// ABI (proven by docs/repro/bindings-pilot/cb-abi on v0.64.3): only a bare
// top-level fn NAME marshals to a C function pointer; fn-typed parameter
// VALUES do not (finding B-13).  Design: each event type has ONE fixed
// top-level dispatcher whose address is handed to the DLL; user handlers
// live in module-level `Vec[fn]` registries (m130 element semantics; push of
// a fn-typed param + element call proven by probe6).  Handlers are
// process-global per event type (last set wins); window handlers receive the
// window handle so multi-window callers can route inside the handler.
// =========================================================================

/// Little-endian u64 store into an XIOM-owned byte slot (B-11 discipline).
/// Complexity: O(1).
fn write_u64_le(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  buf[off + 0] = ( v        & 0xFF) as UInt8;
  buf[off + 1] = ((v >>  8) & 0xFF) as UInt8;
  buf[off + 2] = ((v >> 16) & 0xFF) as UInt8;
  buf[off + 3] = ((v >> 24) & 0xFF) as UInt8;
  buf[off + 4] = ((v >> 32) & 0xFF) as UInt8;
  buf[off + 5] = ((v >> 40) & 0xFF) as UInt8;
  buf[off + 6] = ((v >> 48) & 0xFF) as UInt8;
  buf[off + 7] = ((v >> 56) & 0xFF) as UInt8;
}

// ---- handler registries (one per event type; last set wins) ---------------

var cb_error_handlers: Vec[fn(Int32, Str) -> Unit] = Vec[fn(Int32, Str) -> Unit].new();
var cb_monitor_handlers: Vec[fn(Int, Int32) -> Unit] = Vec[fn(Int, Int32) -> Unit].new();
var cb_joystick_handlers: Vec[fn(Int32, Int32) -> Unit] = Vec[fn(Int32, Int32) -> Unit].new();
var cb_window_pos_handlers: Vec[fn(Int, Int32, Int32) -> Unit] = Vec[fn(Int, Int32, Int32) -> Unit].new();
var cb_window_size_handlers: Vec[fn(Int, Int32, Int32) -> Unit] = Vec[fn(Int, Int32, Int32) -> Unit].new();
var cb_window_close_handlers: Vec[fn(Int) -> Unit] = Vec[fn(Int) -> Unit].new();
var cb_window_refresh_handlers: Vec[fn(Int) -> Unit] = Vec[fn(Int) -> Unit].new();
var cb_window_focus_handlers: Vec[fn(Int, Int32) -> Unit] = Vec[fn(Int, Int32) -> Unit].new();
var cb_window_iconify_handlers: Vec[fn(Int, Int32) -> Unit] = Vec[fn(Int, Int32) -> Unit].new();
var cb_window_maximize_handlers: Vec[fn(Int, Int32) -> Unit] = Vec[fn(Int, Int32) -> Unit].new();
var cb_framebuffer_size_handlers: Vec[fn(Int, Int32, Int32) -> Unit] = Vec[fn(Int, Int32, Int32) -> Unit].new();
var cb_content_scale_handlers: Vec[fn(Int, Float64, Float64) -> Unit] = Vec[fn(Int, Float64, Float64) -> Unit].new();
var cb_key_handlers: Vec[fn(Int, Int32, Int32, Int32, Int32) -> Unit] = Vec[fn(Int, Int32, Int32, Int32, Int32) -> Unit].new();
var cb_char_handlers: Vec[fn(Int, Int32) -> Unit] = Vec[fn(Int, Int32) -> Unit].new();
var cb_char_mods_handlers: Vec[fn(Int, Int32, Int32) -> Unit] = Vec[fn(Int, Int32, Int32) -> Unit].new();
var cb_mouse_button_handlers: Vec[fn(Int, Int32, Int32, Int32) -> Unit] = Vec[fn(Int, Int32, Int32, Int32) -> Unit].new();
var cb_cursor_pos_handlers: Vec[fn(Int, Float64, Float64) -> Unit] = Vec[fn(Int, Float64, Float64) -> Unit].new();
var cb_cursor_enter_handlers: Vec[fn(Int, Int32) -> Unit] = Vec[fn(Int, Int32) -> Unit].new();
var cb_scroll_handlers: Vec[fn(Int, Float64, Float64) -> Unit] = Vec[fn(Int, Float64, Float64) -> Unit].new();
var cb_drop_handlers: Vec[fn(Int, Int32, Vec[Str]) -> Unit] = Vec[fn(Int, Int32, Vec[Str]) -> Unit].new();

// ---- fixed dispatchers (the addresses handed to the DLL) ------------------

fn cb_error_dispatch(code: Int32, desc: *UInt8) -> Unit {
  if cb_error_handlers.len() > 0 {
    var d = "";
    if desc != 0 {
      d = Str::from_c_str(desc);
    }
    let h = cb_error_handlers[cb_error_handlers.len() - 1];
    h(code, d);
  }
}

fn cb_monitor_dispatch(monitor: Int, event: Int32) -> Unit {
  if cb_monitor_handlers.len() > 0 {
    let h = cb_monitor_handlers[cb_monitor_handlers.len() - 1];
    h(monitor, event);
  }
}

fn cb_joystick_dispatch(jid: Int32, event: Int32) -> Unit {
  if cb_joystick_handlers.len() > 0 {
    let h = cb_joystick_handlers[cb_joystick_handlers.len() - 1];
    h(jid, event);
  }
}

fn cb_window_pos_dispatch(win: Int, xpos: Int32, ypos: Int32) -> Unit {
  if cb_window_pos_handlers.len() > 0 {
    let h = cb_window_pos_handlers[cb_window_pos_handlers.len() - 1];
    h(win, xpos, ypos);
  }
}

fn cb_window_size_dispatch(win: Int, width: Int32, height: Int32) -> Unit {
  if cb_window_size_handlers.len() > 0 {
    let h = cb_window_size_handlers[cb_window_size_handlers.len() - 1];
    h(win, width, height);
  }
}

fn cb_window_close_dispatch(win: Int) -> Unit {
  if cb_window_close_handlers.len() > 0 {
    let h = cb_window_close_handlers[cb_window_close_handlers.len() - 1];
    h(win);
  }
}

fn cb_window_refresh_dispatch(win: Int) -> Unit {
  if cb_window_refresh_handlers.len() > 0 {
    let h = cb_window_refresh_handlers[cb_window_refresh_handlers.len() - 1];
    h(win);
  }
}

fn cb_window_focus_dispatch(win: Int, focused: Int32) -> Unit {
  if cb_window_focus_handlers.len() > 0 {
    let h = cb_window_focus_handlers[cb_window_focus_handlers.len() - 1];
    h(win, focused);
  }
}

fn cb_window_iconify_dispatch(win: Int, iconified: Int32) -> Unit {
  if cb_window_iconify_handlers.len() > 0 {
    let h = cb_window_iconify_handlers[cb_window_iconify_handlers.len() - 1];
    h(win, iconified);
  }
}

fn cb_window_maximize_dispatch(win: Int, maximized: Int32) -> Unit {
  if cb_window_maximize_handlers.len() > 0 {
    let h = cb_window_maximize_handlers[cb_window_maximize_handlers.len() - 1];
    h(win, maximized);
  }
}

fn cb_framebuffer_size_dispatch(win: Int, width: Int32, height: Int32) -> Unit {
  if cb_framebuffer_size_handlers.len() > 0 {
    let h = cb_framebuffer_size_handlers[cb_framebuffer_size_handlers.len() - 1];
    h(win, width, height);
  }
}

fn cb_content_scale_dispatch(win: Int, xscale: Float32, yscale: Float32) -> Unit {
  if cb_content_scale_handlers.len() > 0 {
    let h = cb_content_scale_handlers[cb_content_scale_handlers.len() - 1];
    h(win, xscale as Float64, yscale as Float64);
  }
}

fn cb_key_dispatch(win: Int, key: Int32, scancode: Int32, action: Int32, mods: Int32) -> Unit {
  if cb_key_handlers.len() > 0 {
    let h = cb_key_handlers[cb_key_handlers.len() - 1];
    h(win, key, scancode, action, mods);
  }
}

fn cb_char_dispatch(win: Int, codepoint: Int32) -> Unit {
  if cb_char_handlers.len() > 0 {
    let h = cb_char_handlers[cb_char_handlers.len() - 1];
    h(win, codepoint);
  }
}

fn cb_char_mods_dispatch(win: Int, codepoint: Int32, mods: Int32) -> Unit {
  if cb_char_mods_handlers.len() > 0 {
    let h = cb_char_mods_handlers[cb_char_mods_handlers.len() - 1];
    h(win, codepoint, mods);
  }
}

fn cb_mouse_button_dispatch(win: Int, button: Int32, action: Int32, mods: Int32) -> Unit {
  if cb_mouse_button_handlers.len() > 0 {
    let h = cb_mouse_button_handlers[cb_mouse_button_handlers.len() - 1];
    h(win, button, action, mods);
  }
}

fn cb_cursor_pos_dispatch(win: Int, xpos: Float64, ypos: Float64) -> Unit {
  if cb_cursor_pos_handlers.len() > 0 {
    let h = cb_cursor_pos_handlers[cb_cursor_pos_handlers.len() - 1];
    h(win, xpos, ypos);
  }
}

fn cb_cursor_enter_dispatch(win: Int, entered: Int32) -> Unit {
  if cb_cursor_enter_handlers.len() > 0 {
    let h = cb_cursor_enter_handlers[cb_cursor_enter_handlers.len() - 1];
    h(win, entered);
  }
}

fn cb_scroll_dispatch(win: Int, xoffset: Float64, yoffset: Float64) -> Unit {
  if cb_scroll_handlers.len() > 0 {
    let h = cb_scroll_handlers[cb_scroll_handlers.len() - 1];
    h(win, xoffset, yoffset);
  }
}

fn cb_drop_dispatch(win: Int, path_count: Int32, paths: *UInt8) -> Unit {
  if cb_drop_handlers.len() > 0 {
    var ps: Vec[Str] = Vec[Str].new();
    unsafe {
      let n = path_count as Int;
      var i = 0;
      while i < n {
        let p = ffi.ptr_read_u64_le(paths + i * 8);
        if p != 0 {
          ps.push(Str::from_c_str(p as *UInt8));
        }
        i = i + 1;
      }
    }
    let h = cb_drop_handlers[cb_drop_handlers.len() - 1];
    h(win, path_count, ps);
  }
}

// ---- public setters (previous raw callback address, 0 = none) -------------

/// glfwSetErrorCallback() -- process-global error handler.
/// Complexity: O(1).
pub fn glfw_set_error_callback(lib: &GlfwLibrary, handler: fn(Int32, Str) -> Unit) -> Int
  requires: lib.handle != 0
{
  cb_error_handlers.push(handler);
  unsafe {
    let f = lib.p_set_error_callback as fn(fn(Int32, *UInt8) -> Unit) -> *UInt8;
    let prev = f(cb_error_dispatch);
    return prev as Int;
  }
}

/// glfwSetMonitorCallback() -- process-global monitor handler.
/// Complexity: O(1).
pub fn glfw_set_monitor_callback(lib: &GlfwLibrary, handler: fn(Int, Int32) -> Unit) -> Int
  requires: lib.handle != 0
{
  cb_monitor_handlers.push(handler);
  unsafe {
    let f = lib.p_set_monitor_callback as fn(fn(Int, Int32) -> Unit) -> *UInt8;
    let prev = f(cb_monitor_dispatch);
    return prev as Int;
  }
}

/// glfwSetJoystickCallback() -- process-global joystick handler.
/// Complexity: O(1).
pub fn glfw_set_joystick_callback(lib: &GlfwLibrary, handler: fn(Int32, Int32) -> Unit) -> Int
  requires: lib.handle != 0
{
  cb_joystick_handlers.push(handler);
  unsafe {
    let f = lib.p_set_joystick_callback as fn(fn(Int32, Int32) -> Unit) -> *UInt8;
    let prev = f(cb_joystick_dispatch);
    return prev as Int;
  }
}

/// glfwSetWindowPosCallback().
/// Complexity: O(1).
pub fn glfw_set_window_pos_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Int32, Int32) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_window_pos_handlers.push(handler);
  unsafe {
    let f = lib.p_set_window_pos_callback as fn(*UInt8, fn(Int, Int32, Int32) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_window_pos_dispatch);
    return prev as Int;
  }
}

/// glfwSetWindowSizeCallback().
/// Complexity: O(1).
pub fn glfw_set_window_size_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Int32, Int32) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_window_size_handlers.push(handler);
  unsafe {
    let f = lib.p_set_window_size_callback as fn(*UInt8, fn(Int, Int32, Int32) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_window_size_dispatch);
    return prev as Int;
  }
}

/// glfwSetWindowCloseCallback().
/// Complexity: O(1).
pub fn glfw_set_window_close_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_window_close_handlers.push(handler);
  unsafe {
    let f = lib.p_set_window_close_callback as fn(*UInt8, fn(Int) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_window_close_dispatch);
    return prev as Int;
  }
}

/// glfwSetWindowRefreshCallback().
/// Complexity: O(1).
pub fn glfw_set_window_refresh_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_window_refresh_handlers.push(handler);
  unsafe {
    let f = lib.p_set_window_refresh_callback as fn(*UInt8, fn(Int) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_window_refresh_dispatch);
    return prev as Int;
  }
}

/// glfwSetWindowFocusCallback().
/// Complexity: O(1).
pub fn glfw_set_window_focus_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Int32) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_window_focus_handlers.push(handler);
  unsafe {
    let f = lib.p_set_window_focus_callback as fn(*UInt8, fn(Int, Int32) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_window_focus_dispatch);
    return prev as Int;
  }
}

/// glfwSetWindowIconifyCallback().
/// Complexity: O(1).
pub fn glfw_set_window_iconify_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Int32) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_window_iconify_handlers.push(handler);
  unsafe {
    let f = lib.p_set_window_iconify_callback as fn(*UInt8, fn(Int, Int32) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_window_iconify_dispatch);
    return prev as Int;
  }
}

/// glfwSetWindowMaximizeCallback().
/// Complexity: O(1).
pub fn glfw_set_window_maximize_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Int32) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_window_maximize_handlers.push(handler);
  unsafe {
    let f = lib.p_set_window_maximize_callback as fn(*UInt8, fn(Int, Int32) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_window_maximize_dispatch);
    return prev as Int;
  }
}

/// glfwSetFramebufferSizeCallback().
/// Complexity: O(1).
pub fn glfw_set_framebuffer_size_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Int32, Int32) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_framebuffer_size_handlers.push(handler);
  unsafe {
    let f = lib.p_set_framebuffer_size_callback as fn(*UInt8, fn(Int, Int32, Int32) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_framebuffer_size_dispatch);
    return prev as Int;
  }
}

/// glfwSetWindowContentScaleCallback() -- C floats are widened to Float64.
/// Complexity: O(1).
pub fn glfw_set_window_content_scale_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Float64, Float64) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_content_scale_handlers.push(handler);
  unsafe {
    let f = lib.p_set_window_content_scale_callback as fn(*UInt8, fn(Int, Float32, Float32) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_content_scale_dispatch);
    return prev as Int;
  }
}

/// glfwSetKeyCallback().
/// Complexity: O(1).
pub fn glfw_set_key_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Int32, Int32, Int32, Int32) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_key_handlers.push(handler);
  unsafe {
    let f = lib.p_set_key_callback as fn(*UInt8, fn(Int, Int32, Int32, Int32, Int32) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_key_dispatch);
    return prev as Int;
  }
}

/// glfwSetCharCallback() (Unicode code point).
/// Complexity: O(1).
pub fn glfw_set_char_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Int32) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_char_handlers.push(handler);
  unsafe {
    let f = lib.p_set_char_callback as fn(*UInt8, fn(Int, Int32) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_char_dispatch);
    return prev as Int;
  }
}

/// glfwSetCharModsCallback() (deprecated in GLFW 3.4, still exported).
/// Complexity: O(1).
pub fn glfw_set_char_mods_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Int32, Int32) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_char_mods_handlers.push(handler);
  unsafe {
    let f = lib.p_set_char_mods_callback as fn(*UInt8, fn(Int, Int32, Int32) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_char_mods_dispatch);
    return prev as Int;
  }
}

/// glfwSetMouseButtonCallback().
/// Complexity: O(1).
pub fn glfw_set_mouse_button_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Int32, Int32, Int32) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_mouse_button_handlers.push(handler);
  unsafe {
    let f = lib.p_set_mouse_button_callback as fn(*UInt8, fn(Int, Int32, Int32, Int32) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_mouse_button_dispatch);
    return prev as Int;
  }
}

/// glfwSetCursorPosCallback().
/// Complexity: O(1).
pub fn glfw_set_cursor_pos_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Float64, Float64) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_cursor_pos_handlers.push(handler);
  unsafe {
    let f = lib.p_set_cursor_pos_callback as fn(*UInt8, fn(Int, Float64, Float64) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_cursor_pos_dispatch);
    return prev as Int;
  }
}

/// glfwSetCursorEnterCallback().
/// Complexity: O(1).
pub fn glfw_set_cursor_enter_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Int32) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_cursor_enter_handlers.push(handler);
  unsafe {
    let f = lib.p_set_cursor_enter_callback as fn(*UInt8, fn(Int, Int32) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_cursor_enter_dispatch);
    return prev as Int;
  }
}

/// glfwSetScrollCallback().
/// Complexity: O(1).
pub fn glfw_set_scroll_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Float64, Float64) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_scroll_handlers.push(handler);
  unsafe {
    let f = lib.p_set_scroll_callback as fn(*UInt8, fn(Int, Float64, Float64) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_scroll_dispatch);
    return prev as Int;
  }
}

/// glfwSetDropCallback() -- file paths are copied into an owned Vec[Str]
/// while the C pointer array is live.
/// Complexity: O(paths).
pub fn glfw_set_drop_callback(lib: &GlfwLibrary, w: &GlfwWindow,
    handler: fn(Int, Int32, Vec[Str]) -> Unit) -> Int
  requires: lib.handle != 0
  requires: w.handle != 0
{
  cb_drop_handlers.push(handler);
  unsafe {
    let f = lib.p_set_drop_callback as fn(*UInt8, fn(Int, Int32, *UInt8) -> Unit) -> *UInt8;
    let prev = f(w.handle as *UInt8, cb_drop_dispatch);
    return prev as Int;
  }
}

// ---- glfwInitAllocator ----------------------------------------------------

/// glfwInitAllocator() with raw C-ABI callback addresses (call BEFORE
/// glfwInit).  Pass top-level XIOM fns cast with `as Int`:
///   allocate   = `fn(size: Int, user: Int) -> Int`   (returns the block)
///   reallocate = `fn(block: Int, size: Int, user: Int) -> Int`
///   deallocate = `fn(block: Int, user: Int) -> Int`  (return ignored)
/// The 32-byte GLFWallocator struct is built in an XIOM-owned slot (B-11);
/// `reallocate`/`deallocate` may be 0 (GLFW then requires the corresponding
/// handler to handle NULL calls itself); `allocate` is required.
/// Complexity: O(1).
pub fn glfw_init_allocator_raw(lib: &GlfwLibrary, allocate: Int,
    reallocate: Int, deallocate: Int, user: Int)
  requires: lib.handle != 0
  requires: allocate != 0
{
  unsafe {
    var s = slot_new(32);
    write_u64_le(&mut s, 0, allocate);
    write_u64_le(&mut s, 8, reallocate);
    write_u64_le(&mut s, 16, deallocate);
    write_u64_le(&mut s, 24, user);
    let f = lib.p_init_allocator as fn(*UInt8);
    f(s.as_mut_ptr() as *UInt8);
  }
}
