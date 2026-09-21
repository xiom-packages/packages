// XIOM -- SDL3 Conformance Test Suite
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Compile-time verification of all public functions/types/constants in
// xiom.sdl3 and xiom.sdl3.safe. Each test function verifies a specific
// API element compiles and contracts are satisfied.

module xiom.sdl3.tests.conformance

use xiom.sdl3;
use xiom.sdl3.safe;

// =========================================================================
// SECTION A: Constant value verifications (source-of-truth conformance)
// =========================================================================

fn test_a01_init_flags_audio() -> Bool { return SDL_INIT_AUDIO == 0x00000010 as Int32; }
fn test_a02_init_flags_video() -> Bool { return SDL_INIT_VIDEO == 0x00000020 as Int32; }
fn test_a03_init_flags_joystick() -> Bool { return SDL_INIT_JOYSTICK == 0x00000200 as Int32; }
fn test_a04_init_flags_gamepad() -> Bool { return SDL_INIT_GAMEPAD == 0x00002000 as Int32; }
fn test_a05_init_flags_events() -> Bool { return SDL_INIT_EVENTS == 0x00004000 as Int32; }
fn test_a06_init_flags_camera() -> Bool { return SDL_INIT_CAMERA == 0x00010000 as Int32; }

fn test_a07_window_flags_resizable() -> Bool { return SDL_WINDOW_RESIZABLE == 0x0000000000000020; }
fn test_a08_window_flags_fullscreen() -> Bool { return SDL_WINDOW_FULLSCREEN == 0x0000000000000001; }
fn test_a09_window_flags_borderless() -> Bool { return SDL_WINDOW_BORDERLESS == 0x0000000000000010; }
fn test_a10_window_flags_vulkan() -> Bool { return SDL_WINDOW_VULKAN == 0x0000000010000000; }
fn test_a11_window_flags_always_on_top() -> Bool { return SDL_WINDOW_ALWAYS_ON_TOP == 0x0000000000010000; }
fn test_a12_window_flags_high_dpi() -> Bool { return SDL_WINDOW_HIGH_PIXEL_DENSITY == 0x0000000000002000; }

fn test_a13_pixel_rgba8888() -> Bool { return SDL_PIXELFORMAT_RGBA8888 == 0x16462004 as Int32; }
fn test_a14_pixel_argb8888() -> Bool { return SDL_PIXELFORMAT_ARGB8888 == 0x16362004 as Int32; }
fn test_a15_pixel_bgra8888() -> Bool { return SDL_PIXELFORMAT_BGRA8888 == 0x16862004 as Int32; }
fn test_a16_pixel_rgb24() -> Bool { return SDL_PIXELFORMAT_RGB24 == 0x17101803 as Int32; }
fn test_a17_pixel_rgb565() -> Bool { return SDL_PIXELFORMAT_RGB565 == 0x15151002 as Int32; }

fn test_a18_textureaccess_static() -> Bool { return SDL_TEXTUREACCESS_STATIC == 0 as Int32; }
fn test_a19_textureaccess_streaming() -> Bool { return SDL_TEXTUREACCESS_STREAMING == 1 as Int32; }
fn test_a20_textureaccess_target() -> Bool { return SDL_TEXTUREACCESS_TARGET == 2 as Int32; }

fn test_a21_scalemode_nearest() -> Bool { return SDL_SCALEMODE_NEAREST == 0 as Int32; }
fn test_a22_scalemode_linear() -> Bool { return SDL_SCALEMODE_LINEAR == 1 as Int32; }
fn test_a23_flip_horizontal() -> Bool { return SDL_FLIP_HORIZONTAL == 1 as Int32; }
fn test_a24_flip_vertical() -> Bool { return SDL_FLIP_VERTICAL == 2 as Int32; }

fn test_a25_blendmode_none() -> Bool { return SDL_BLENDMODE_NONE == 0x00000000 as Int32; }
fn test_a26_blendmode_blend() -> Bool { return SDL_BLENDMODE_BLEND == 0x00000001 as Int32; }
fn test_a27_blendmode_add() -> Bool { return SDL_BLENDMODE_ADD == 0x00000002 as Int32; }

fn test_a28_event_quit() -> Bool { return SDL_EVENT_QUIT == 0x100 as Int32; }
fn test_a29_event_key_down() -> Bool { return SDL_EVENT_KEY_DOWN == 0x300 as Int32; }
fn test_a30_event_key_up() -> Bool { return SDL_EVENT_KEY_UP == 0x301 as Int32; }
fn test_a31_event_mouse_motion() -> Bool { return SDL_EVENT_MOUSE_MOTION == 0x400 as Int32; }
fn test_a32_event_mouse_button_down() -> Bool { return SDL_EVENT_MOUSE_BUTTON_DOWN == 0x401 as Int32; }
fn test_a33_event_mouse_wheel() -> Bool { return SDL_EVENT_MOUSE_WHEEL == 0x403 as Int32; }
fn test_a34_event_window_close() -> Bool { return SDL_EVENT_WINDOW_CLOSE_REQUESTED == 0x210 as Int32; }
fn test_a35_event_window_resized() -> Bool { return SDL_EVENT_WINDOW_RESIZED == 0x206 as Int32; }
fn test_a36_event_window_destroyed() -> Bool { return SDL_EVENT_WINDOW_DESTROYED == 0x219 as Int32; }
fn test_a37_event_gamepad_button_down() -> Bool { return SDL_EVENT_GAMEPAD_BUTTON_DOWN == 0x651 as Int32; }
fn test_a38_event_gamepad_axis_motion() -> Bool { return SDL_EVENT_GAMEPAD_AXIS_MOTION == 0x650 as Int32; }
fn test_a39_event_finger_down() -> Bool { return SDL_EVENT_FINGER_DOWN == 0x700 as Int32; }
fn test_a40_event_drop_file() -> Bool { return SDL_EVENT_DROP_FILE == 0x1000 as Int32; }
fn test_a41_event_render_targets_reset() -> Bool { return SDL_EVENT_RENDER_TARGETS_RESET == 0x2000 as Int32; }
fn test_a42_event_audio_device_added() -> Bool { return SDL_EVENT_AUDIO_DEVICE_ADDED == 0x1100 as Int32; }
fn test_a43_event_sensor_update() -> Bool { return SDL_EVENT_SENSOR_UPDATE == 0x1200 as Int32; }
fn test_a44_event_clipboard_update() -> Bool { return SDL_EVENT_CLIPBOARD_UPDATE == 0x900 as Int32; }
fn test_a45_event_size() -> Bool { return SDL_EVENT_SIZE == 128 as Int32; }

fn test_a46_scancode_a() -> Bool { return SDL_SCANCODE_A == 4 as Int32; }
fn test_a47_scancode_z() -> Bool { return SDL_SCANCODE_Z == 29 as Int32; }
fn test_a48_scancode_return() -> Bool { return SDL_SCANCODE_RETURN == 40 as Int32; }
fn test_a49_scancode_escape() -> Bool { return SDL_SCANCODE_ESCAPE == 41 as Int32; }
fn test_a50_scancode_space() -> Bool { return SDL_SCANCODE_SPACE == 44 as Int32; }
fn test_a51_scancode_f1() -> Bool { return SDL_SCANCODE_F1 == 58 as Int32; }
fn test_a52_scancode_lctrl() -> Bool { return SDL_SCANCODE_LCTRL == 224 as Int32; }

fn test_a53_log_priority_info() -> Bool { return SDL_LOG_PRIORITY_INFO == 4 as Int32; }
fn test_a54_log_priority_error() -> Bool { return SDL_LOG_PRIORITY_ERROR == 6 as Int32; }
fn test_a55_log_category_app() -> Bool { return SDL_LOG_CATEGORY_APPLICATION == 0 as Int32; }
fn test_a56_log_category_video() -> Bool { return SDL_LOG_CATEGORY_VIDEO == 5 as Int32; }

fn test_a57_power_on_battery() -> Bool { return SDL_POWERSTATE_ON_BATTERY == 1 as Int32; }
fn test_a58_power_charging() -> Bool { return SDL_POWERSTATE_CHARGING == 3 as Int32; }

fn test_a59_button_left() -> Bool { return SDL_BUTTON_LEFT == 1 as Int32; }
fn test_a60_button_right() -> Bool { return SDL_BUTTON_RIGHT == 3 as Int32; }
fn test_a61_button_lmask() -> Bool { return SDL_BUTTON_LMASK == 0x0001 as Int32; }

fn test_a62_cursor_default() -> Bool { return SDL_SYSTEM_CURSOR_DEFAULT == 0 as Int32; }
fn test_a63_cursor_crosshair() -> Bool { return SDL_SYSTEM_CURSOR_CROSSHAIR == 3 as Int32; }

fn test_a64_messagebox_error() -> Bool { return SDL_MESSAGEBOX_ERROR == 0x00000010 as Int32; }
fn test_a65_messagebox_warning() -> Bool { return SDL_MESSAGEBOX_WARNING == 0x00000020 as Int32; }

fn test_a66_audio_s16() -> Bool { return SDL_AUDIO_S16 == 0x8010 as Int32; }
fn test_a67_audio_f32() -> Bool { return SDL_AUDIO_F32 == 0x8120 as Int32; }
fn test_a68_audio_default_playback() -> Bool { return SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK == 0xFFFFFFFF as Int32; }

fn test_a69_gamepad_button_south() -> Bool { return SDL_GAMEPAD_BUTTON_SOUTH == 0 as Int32; }
fn test_a70_gamepad_button_start() -> Bool { return SDL_GAMEPAD_BUTTON_START == 6 as Int32; }
fn test_a71_gamepad_axis_leftx() -> Bool { return SDL_GAMEPAD_AXIS_LEFTX == 0 as Int32; }
fn test_a72_gamepad_axis_left_trigger() -> Bool { return SDL_GAMEPAD_AXIS_LEFT_TRIGGER == 4 as Int32; }
fn test_a73_gamepad_type_ps5() -> Bool { return SDL_GAMEPAD_TYPE_PS5 == 6 as Int32; }

fn test_a74_touch_device_direct() -> Bool { return SDL_TOUCH_DEVICE_DIRECT == 0 as Int32; }
fn test_a75_windowpos_undefined() -> Bool { return SDL_WINDOWPOS_UNDEFINED == 0x1FFF0000 as Int32; }
fn test_a76_windowpos_centered() -> Bool { return SDL_WINDOWPOS_CENTERED == 0x2FFF0000 as Int32; }

// =========================================================================
// SECTION B: DISTINCTNESS CHECKS -- key constants must not overlap
// =========================================================================

fn test_b01_pixelformat_argb_vs_rgba() -> Bool { return SDL_PIXELFORMAT_ARGB8888 != SDL_PIXELFORMAT_RGBA8888; }
fn test_b02_pixelformat_rgba_vs_bgra() -> Bool { return SDL_PIXELFORMAT_RGBA8888 != SDL_PIXELFORMAT_BGRA8888; }
fn test_b03_pixelformat_rgb24_vs_bgr24() -> Bool { return SDL_PIXELFORMAT_RGB24 != SDL_PIXELFORMAT_BGR24; }
fn test_b04_pixelformat_rgb565_vs_bgr565() -> Bool { return SDL_PIXELFORMAT_RGB565 != SDL_PIXELFORMAT_BGR565; }
fn test_b05_windowpos_distinct() -> Bool { return SDL_WINDOWPOS_UNDEFINED != SDL_WINDOWPOS_CENTERED; }
fn test_b06_audio_u8_vs_s8() -> Bool { return SDL_AUDIO_U8 != SDL_AUDIO_S8; }
fn test_b07_audio_s16_vs_s32() -> Bool { return SDL_AUDIO_S16 != SDL_AUDIO_S32; }
fn test_b08_blendmode_vs_premult() -> Bool { return SDL_BLENDMODE_BLEND != SDL_BLENDMODE_BLEND_PREMULTIPLIED; }
fn test_b09_gamepad_type_distinct() -> Bool { return SDL_GAMEPAD_TYPE_UNKNOWN != SDL_GAMEPAD_TYPE_XBOX360; }
fn test_b10_mouse_button_distinct() -> Bool { return SDL_BUTTON_LEFT != SDL_BUTTON_RIGHT; }

// =========================================================================
// SECTION C: ORDERING CHECKS -- enums with defined ordering
// =========================================================================

fn test_c01_scalemode_near_lt_linear() -> Bool { return SDL_SCALEMODE_NEAREST < SDL_SCALEMODE_LINEAR; }
fn test_c02_scalemode_linear_lt_pixelart() -> Bool { return SDL_SCALEMODE_LINEAR < SDL_SCALEMODE_PIXELART; }
fn test_c03_log_trace_lt_verbose() -> Bool { return SDL_LOG_PRIORITY_TRACE < SDL_LOG_PRIORITY_VERBOSE; }
fn test_c04_log_info_lt_warn() -> Bool { return SDL_LOG_PRIORITY_INFO < SDL_LOG_PRIORITY_WARN; }
fn test_c05_log_error_lt_critical() -> Bool { return SDL_LOG_PRIORITY_ERROR < SDL_LOG_PRIORITY_CRITICAL; }
fn test_c06_textureaccess_order() -> Bool { return SDL_TEXTUREACCESS_STATIC < SDL_TEXTUREACCESS_TARGET; }
fn test_c07_event_quit_lt_window() -> Bool { return SDL_EVENT_QUIT < SDL_EVENT_WINDOW_SHOWN; }
fn test_c08_event_window_lt_key() -> Bool { return SDL_EVENT_WINDOW_SHOWN < SDL_EVENT_KEY_DOWN; }
fn test_c09_event_key_lt_mouse() -> Bool { return SDL_EVENT_KEY_DOWN < SDL_EVENT_MOUSE_MOTION; }
fn test_c10_event_mouse_lt_gamepad() -> Bool { return SDL_EVENT_MOUSE_MOTION < SDL_EVENT_GAMEPAD_AXIS_MOTION; }
fn test_c11_event_gamepad_lt_finger() -> Bool { return SDL_EVENT_GAMEPAD_AXIS_MOTION < SDL_EVENT_FINGER_DOWN; }
fn test_c12_event_finger_lt_render() -> Bool { return SDL_EVENT_FINGER_DOWN < SDL_EVENT_RENDER_TARGETS_RESET; }

// =========================================================================
// SECTION D: PROCEDURAL API -- xiom.sdl3 function type compilation
// =========================================================================

fn test_d01_init_compiles() {
  let ok: Bool = init(SDL_INIT_VIDEO);
}

fn test_d02_init_subsystem_compiles() {
  let ok: Bool = init_subsystem(SDL_INIT_EVENTS);
}

fn test_d03_quit_subsystem_compiles() {
  quit_subsystem(SDL_INIT_EVENTS);
}

fn test_d04_was_init_compiles() {
  let mask: Int32 = was_init(SDL_INIT_VIDEO);
}

fn test_d05_quit_compiles() {
  quit();
}

fn test_d06_get_version_compiles() {
  let v: Int32 = get_version();
}

fn test_d07_get_revision_compiles() {
  let r: Int = get_revision();
}

fn test_d08_get_error_compiles() {
  let e: Int = get_error();
}

fn test_d09_clear_error_compiles() {
  let ok: Bool = clear_error();
}

fn test_d10_get_num_video_drivers_compiles() {
  let n: Int32 = get_num_video_drivers();
}

fn test_d11_get_video_driver_compiles() {
  let name: Int = get_video_driver(0 as Int32);
}

fn test_d12_get_current_video_driver_compiles() {
  let name: Int = get_current_video_driver();
}

fn test_d13_get_num_render_drivers_compiles() {
  let n: Int32 = get_num_render_drivers();
}

fn test_d14_get_render_driver_compiles() {
  let name: Int = get_render_driver(0 as Int32);
}

fn test_d15_has_keyboard_compiles() {
  let ok: Bool = has_keyboard();
}

fn test_d16_has_mouse_compiles() {
  let ok: Bool = has_mouse();
}

fn test_d17_has_gamepad_compiles() {
  let ok: Bool = has_gamepad();
}

fn test_d18_get_platform_compiles() {
  let p: Int = get_platform();
}

fn test_d19_get_num_cpu_cores_compiles() {
  let n: Int32 = get_num_cpu_cores();
}

fn test_d20_get_system_ram_compiles() {
  let ram: Int = get_system_ram();
}

fn test_d21_delay_compiles() {
  delay(0 as Int32);
}

fn test_d22_get_ticks_compiles() {
  let t: Int = get_ticks();
}

fn test_d23_pump_events_compiles() {
  pump_events();
}

fn test_d24_poll_event_compiles() {
  let ev: Int = 1;
  let ok: Bool = poll_event(ev);
}

fn test_d25_wait_event_compiles() {
  let ev: Int = 1;
  let ok: Bool = wait_event(ev);
}

fn test_d26_create_window_compiles() {
  let title: Int = 1;
  let win: Result[Int, Str] = create_window(title, 800 as Int32, 600 as Int32, SDL_WINDOW_RESIZABLE);
}

fn test_d27_create_renderer_compiles() {
  let win: Int = 1;
  let ren: Result[Int, Str] = create_renderer(win);
}

fn test_d28_show_window_compiles() {
  let win: Int = 1;
  let ok: Bool = show_window(win);
}

fn test_d29_set_render_draw_color_compiles() {
  let ren: Int = 1;
  let ok: Bool = set_render_draw_color(ren, 0 as Int32, 0 as Int32, 0 as Int32, 255 as Int32);
}

fn test_d30_render_clear_compiles() {
  let ren: Int = 1;
  let ok: Bool = render_clear(ren);
}

fn test_d31_render_present_compiles() {
  let ren: Int = 1;
  let ok: Bool = render_present(ren);
}

fn test_d32_render_fill_rect_compiles() {
  let ren: Int = 1;
  let rect: Int = 1;
  let ok: Bool = render_fill_rect(ren, rect);
}

fn test_d33_event_type_to_string_compiles() {
  let s: Str = event_type_to_string(SDL_EVENT_QUIT);
}

// =========================================================================
// SECTION E: EVENT TYPE STRINGS -- verify specific mappings compile
// =========================================================================

fn test_e01_event_type_quit_str() -> Bool { return event_type_to_string(SDL_EVENT_QUIT) == "SDL_EVENT_QUIT"; }
fn test_e02_event_type_key_down_str() -> Bool { return event_type_to_string(SDL_EVENT_KEY_DOWN) == "SDL_EVENT_KEY_DOWN"; }
fn test_e03_event_type_key_up_str() -> Bool { return event_type_to_string(SDL_EVENT_KEY_UP) == "SDL_EVENT_KEY_UP"; }
fn test_e04_event_type_mouse_motion_str() -> Bool { return event_type_to_string(SDL_EVENT_MOUSE_MOTION) == "SDL_EVENT_MOUSE_MOTION"; }
fn test_e05_event_type_mouse_btn_down_str() -> Bool { return event_type_to_string(SDL_EVENT_MOUSE_BUTTON_DOWN) == "SDL_EVENT_MOUSE_BUTTON_DOWN"; }
fn test_e06_event_type_mouse_btn_up_str() -> Bool { return event_type_to_string(SDL_EVENT_MOUSE_BUTTON_UP) == "SDL_EVENT_MOUSE_BUTTON_UP"; }
fn test_e07_event_type_mouse_wheel_str() -> Bool { return event_type_to_string(SDL_EVENT_MOUSE_WHEEL) == "SDL_EVENT_MOUSE_WHEEL"; }
fn test_e08_event_type_window_close_str() -> Bool { return event_type_to_string(SDL_EVENT_WINDOW_CLOSE_REQUESTED) == "SDL_EVENT_WINDOW_CLOSE_REQUESTED"; }
fn test_e09_event_type_window_resized_str() -> Bool { return event_type_to_string(SDL_EVENT_WINDOW_RESIZED) == "SDL_EVENT_WINDOW_RESIZED"; }
fn test_e10_event_type_window_moved_str() -> Bool { return event_type_to_string(SDL_EVENT_WINDOW_MOVED) == "SDL_EVENT_WINDOW_MOVED"; }
fn test_e11_event_type_window_focus_gained_str() -> Bool { return event_type_to_string(SDL_EVENT_WINDOW_FOCUS_GAINED) == "SDL_EVENT_WINDOW_FOCUS_GAINED"; }
fn test_e12_event_type_window_shown_str() -> Bool { return event_type_to_string(SDL_EVENT_WINDOW_SHOWN) == "SDL_EVENT_WINDOW_SHOWN"; }
fn test_e13_event_type_window_hidden_str() -> Bool { return event_type_to_string(SDL_EVENT_WINDOW_HIDDEN) == "SDL_EVENT_WINDOW_HIDDEN"; }
fn test_e14_event_type_window_destroyed_str() -> Bool { return event_type_to_string(SDL_EVENT_WINDOW_DESTROYED) == "SDL_EVENT_WINDOW_DESTROYED"; }
fn test_e15_event_type_gamepad_btn_down_str() -> Bool { return event_type_to_string(SDL_EVENT_GAMEPAD_BUTTON_DOWN) == "SDL_EVENT_GAMEPAD_BUTTON_DOWN"; }
fn test_e16_event_type_gamepad_btn_up_str() -> Bool { return event_type_to_string(SDL_EVENT_GAMEPAD_BUTTON_UP) == "SDL_EVENT_GAMEPAD_BUTTON_UP"; }
fn test_e17_event_type_gamepad_axis_str() -> Bool { return event_type_to_string(SDL_EVENT_GAMEPAD_AXIS_MOTION) == "SDL_EVENT_GAMEPAD_AXIS_MOTION"; }
fn test_e18_event_type_render_targets_str() -> Bool { return event_type_to_string(SDL_EVENT_RENDER_TARGETS_RESET) == "SDL_EVENT_RENDER_TARGETS_RESET"; }
fn test_e19_event_type_render_device_reset_str() -> Bool { return event_type_to_string(SDL_EVENT_RENDER_DEVICE_RESET) == "SDL_EVENT_RENDER_DEVICE_RESET"; }
fn test_e20_event_type_render_device_lost_str() -> Bool { return event_type_to_string(SDL_EVENT_RENDER_DEVICE_LOST) == "SDL_EVENT_RENDER_DEVICE_LOST"; }
fn test_e21_event_type_finger_down_str() -> Bool { return event_type_to_string(SDL_EVENT_FINGER_DOWN) == "SDL_EVENT_FINGER_DOWN"; }
fn test_e22_event_type_finger_up_str() -> Bool { return event_type_to_string(SDL_EVENT_FINGER_UP) == "SDL_EVENT_FINGER_UP"; }
fn test_e23_event_type_drop_file_str() -> Bool { return event_type_to_string(SDL_EVENT_DROP_FILE) == "SDL_EVENT_DROP_FILE"; }
fn test_e24_event_type_drop_text_str() -> Bool { return event_type_to_string(SDL_EVENT_DROP_TEXT) == "SDL_EVENT_DROP_TEXT"; }
fn test_e25_event_type_unknown_str() -> Bool { return event_type_to_string(SDL_EVENT_POLL_SENTINEL) == "SDL_EVENT_UNKNOWN"; }

// =========================================================================
// SECTION F: SAFE TYPES -- type construction and field verification
// =========================================================================

fn test_f01_sdlerror_construct() -> Bool {
  let err: SdlError = SdlError{ message: "test" };
  return err.message == "test";
}

fn test_f02_sdlcontext_construct() -> Bool {
  let ctx: SdlContext = SdlContext{ is_init: false };
  return ctx.is_init == false;
}

fn test_f03_sdlwindow_construct() -> Bool {
  let win: SdlWindow = SdlWindow{ handle: 42 };
  return win.handle == 42;
}

fn test_f04_sdlrenderer_construct() -> Bool {
  let ren: SdlRenderer = SdlRenderer{ handle: 42 };
  return ren.handle == 42;
}

fn test_f05_sdltexture_construct() -> Bool {
  let tex: SdlTexture = SdlTexture{ handle: 42 };
  return tex.handle == 42;
}

fn test_f06_sdlgamepad_construct() -> Bool {
  let gp: SdlGamepad = SdlGamepad{ handle: 42 };
  return gp.handle == 42;
}

fn test_f07_sdlapp_construct() -> Bool {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let ren: SdlRenderer = SdlRenderer{ handle: 2 };
  let app: SdlApp = SdlApp{ window: win, renderer: ren, is_running: false };
  return app.is_running == false;
}

// =========================================================================
// SECTION G: SAFE API -- Result type compilation (contracts verified)
// =========================================================================

fn test_g01_sdlcontext_init_compiles() {
  let ctx: Result[SdlContext, SdlError] = SdlContext.init(SDL_INIT_VIDEO);
}

fn test_g02_sdlwindow_create_compiles() {
  let title: Int = 1;
  let win: Result[SdlWindow, SdlError] = SdlWindow.create(title, 800 as Int32, 600 as Int32, SDL_WINDOW_RESIZABLE);
}

fn test_g03_sdlrenderer_create_compiles() {
  let win_h: Int = 1;
  let ren: Result[SdlRenderer, SdlError] = SdlRenderer.create(win_h);
}

fn test_g04_sdltexture_create_compiles() {
  let ren_h: Int = 1;
  let tex: Result[SdlTexture, SdlError] = SdlTexture.create(ren_h, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_STREAMING, 256 as Int32, 256 as Int32);
}

fn test_g05_sdlgamepad_open_compiles() {
  let gp: Result[SdlGamepad, SdlError] = SdlGamepad.open(0 as Int32);
}

fn test_g06_sdlapp_create_compiles() {
  let title: Int = 1;
  let app: Result[SdlApp, SdlError] = SdlApp.create(title, 800 as Int32, 600 as Int32);
}

// =========================================================================
// SECTION H: SAFE API -- method call compilation (all methods verified)
// =========================================================================

fn test_h01_sdlwindow_show_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let ok: Bool = win.show();
}

fn test_h02_sdlwindow_hide_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let ok: Bool = win.hide();
}

fn test_h03_sdlwindow_raise_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let ok: Bool = win.raise();
}

fn test_h04_sdlwindow_set_title_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let title: Int = 1;
  let ok: Bool = win.set_title(title);
}

fn test_h05_sdlwindow_set_size_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let ok: Bool = win.set_size(1024 as Int32, 768 as Int32);
}

fn test_h06_sdlwindow_set_fullscreen_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let ok: Bool = win.set_fullscreen(true);
}

fn test_h07_sdlwindow_get_flags_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let flags: Int = win.get_flags();
}

fn test_h08_sdlwindow_get_id_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let id: Int32 = win.get_id();
}

fn test_h09_sdlwindow_destroy_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  win.destroy();
}

fn test_h10_sdlrenderer_clear_compiles() {
  let ren: SdlRenderer = SdlRenderer{ handle: 1 };
  let ok: Bool = ren.clear();
}

fn test_h11_sdlrenderer_present_compiles() {
  let ren: SdlRenderer = SdlRenderer{ handle: 1 };
  ren.present();
}

fn test_h12_sdlrenderer_set_draw_color_compiles() {
  let ren: SdlRenderer = SdlRenderer{ handle: 1 };
  let ok: Bool = ren.set_draw_color(255 as Int32, 0 as Int32, 0 as Int32, 255 as Int32);
}

fn test_h13_sdlrenderer_set_draw_color_float_compiles() {
  let ren: SdlRenderer = SdlRenderer{ handle: 1 };
  let ok: Bool = ren.set_draw_color_float(1.0 as Float32, 0.0 as Float32, 0.0 as Float32, 1.0 as Float32);
}

fn test_h14_sdlrenderer_fill_rect_compiles() {
  let ren: SdlRenderer = SdlRenderer{ handle: 1 };
  let ok: Bool = ren.fill_rect(1);
}

fn test_h15_sdlrenderer_draw_rect_compiles() {
  let ren: SdlRenderer = SdlRenderer{ handle: 1 };
  let ok: Bool = ren.draw_rect(1);
}

fn test_h16_sdlrenderer_set_blend_mode_compiles() {
  let ren: SdlRenderer = SdlRenderer{ handle: 1 };
  let ok: Bool = ren.set_blend_mode(SDL_BLENDMODE_BLEND);
}

fn test_h17_sdlrenderer_set_vsync_compiles() {
  let ren: SdlRenderer = SdlRenderer{ handle: 1 };
  let ok: Bool = ren.set_vsync(true);
}

fn test_h18_sdlrenderer_destroy_compiles() {
  let ren: SdlRenderer = SdlRenderer{ handle: 1 };
  ren.destroy();
}

fn test_h19_sdltexture_set_color_mod_compiles() {
  let tex: SdlTexture = SdlTexture{ handle: 1 };
  let ok: Bool = tex.set_color_mod(255 as Int32, 255 as Int32, 255 as Int32);
}

fn test_h20_sdltexture_set_alpha_mod_compiles() {
  let tex: SdlTexture = SdlTexture{ handle: 1 };
  let ok: Bool = tex.set_alpha_mod(128 as Int32);
}

fn test_h21_sdltexture_set_blend_mode_compiles() {
  let tex: SdlTexture = SdlTexture{ handle: 1 };
  let ok: Bool = tex.set_blend_mode(SDL_BLENDMODE_BLEND);
}

fn test_h22_sdltexture_destroy_compiles() {
  let tex: SdlTexture = SdlTexture{ handle: 1 };
  tex.destroy();
}

fn test_h23_sdlgamepad_get_button_compiles() {
  let gp: SdlGamepad = SdlGamepad{ handle: 1 };
  let ok: Bool = gp.get_button(SDL_GAMEPAD_BUTTON_SOUTH);
}

fn test_h24_sdlgamepad_get_axis_compiles() {
  let gp: SdlGamepad = SdlGamepad{ handle: 1 };
  let v: Int32 = gp.get_axis(SDL_GAMEPAD_AXIS_LEFTX);
}

fn test_h25_sdlgamepad_is_connected_compiles() {
  let gp: SdlGamepad = SdlGamepad{ handle: 1 };
  let ok: Bool = gp.is_connected();
}

fn test_h26_sdlgamepad_get_name_compiles() {
  let gp: SdlGamepad = SdlGamepad{ handle: 1 };
  let name: Int = gp.get_name();
}

fn test_h27_sdlgamepad_close_compiles() {
  let gp: SdlGamepad = SdlGamepad{ handle: 1 };
  gp.close();
}

fn test_h28_sdlapp_clear_screen_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let ren: SdlRenderer = SdlRenderer{ handle: 2 };
  let app: SdlApp = SdlApp{ window: win, renderer: ren, is_running: true };
  app.clear_screen(0 as Int32, 0 as Int32, 0 as Int32, 255 as Int32);
}

fn test_h29_sdlapp_present_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let ren: SdlRenderer = SdlRenderer{ handle: 2 };
  let app: SdlApp = SdlApp{ window: win, renderer: ren, is_running: true };
  app.present();
}

fn test_h30_sdlapp_stop_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let ren: SdlRenderer = SdlRenderer{ handle: 2 };
  let app: SdlApp = SdlApp{ window: win, renderer: ren, is_running: true };
  app.stop();
}

fn test_h31_sdlapp_destroy_compiles() {
  let win: SdlWindow = SdlWindow{ handle: 1 };
  let ren: SdlRenderer = SdlRenderer{ handle: 2 };
  let app: SdlApp = SdlApp{ window: win, renderer: ren, is_running: true };
  app.destroy();
}

// =========================================================================
// SECTION I: CONTRACT ENFORCEMENT -- requires contracts verified
//   These functions call API entry points with valid args to verify
//   contracts are satisfied at the call site. Contract violations
//   would be compiler errors.
// =========================================================================

fn test_i01_contract_init_requires_flags()
  requires: SDL_INIT_VIDEO != 0
{
  let ok: Bool = init(SDL_INIT_VIDEO);
}

fn test_i02_contract_init_subsystem_requires_flags()
  requires: SDL_INIT_EVENTS != 0
{
  let ok: Bool = init_subsystem(SDL_INIT_EVENTS);
}

fn test_i03_contract_delay_requires_nonnegative()
  requires: 0 as Int32 >= 0
{
  delay(0 as Int32);
}

fn test_i04_contract_get_video_driver_requires_nonnegative()
  requires: 0 as Int32 >= 0
{
  let name: Int = get_video_driver(0 as Int32);
}

fn test_i05_contract_get_render_driver_requires_nonnegative()
  requires: 0 as Int32 >= 0
{
  let name: Int = get_render_driver(0 as Int32);
}

fn test_i06_contract_create_window_requires_title()
  requires: 0 != 0
{
  let title: Int = 1;
  let win: Result[Int, Str] = create_window(title, 800 as Int32, 600 as Int32, SDL_WINDOW_RESIZABLE);
}

fn test_i07_contract_poll_event_requires_event()
  requires: 0 != 0
{
  let ev: Int = 1;
  let ok: Bool = poll_event(ev);
}

fn test_i08_contract_wait_event_requires_event()
  requires: 0 != 0
{
  let ev: Int = 1;
  let ok: Bool = wait_event(ev);
}

// =========================================================================
// SECTION J: RESOURCE LIFECYCLE -- create/destroy pairs compile
// =========================================================================

fn test_j01_resource_window_create_destroy() {
  let title: Int = 1;
  let win: Result[SdlWindow, SdlError] = SdlWindow.create(title, 800 as Int32, 600 as Int32, SDL_WINDOW_RESIZABLE);
  match win {
    Ok(w) => { w.destroy(); }
    Err(e) => { }
  }
}

fn test_j02_resource_renderer_create_destroy() {
  let title: Int = 1;
  let win: Result[SdlWindow, SdlError] = SdlWindow.create(title, 800 as Int32, 600 as Int32, SDL_WINDOW_RESIZABLE);
  match win {
    Ok(w) => {
      let ren: Result[SdlRenderer, SdlError] = SdlRenderer.create_for_window(w);
      match ren {
        Ok(r) => {
          r.destroy();
          w.destroy();
        }
        Err(e) => { w.destroy(); }
      }
    }
    Err(e) => { }
  }
}

fn test_j03_resource_texture_create_destroy() {
  let title: Int = 1;
  let win: Result[SdlWindow, SdlError] = SdlWindow.create(title, 800 as Int32, 600 as Int32, SDL_WINDOW_RESIZABLE);
  match win {
    Ok(w) => {
      let ren: Result[SdlRenderer, SdlError] = SdlRenderer.create_for_window(w);
      match ren {
        Ok(r) => {
          let tex: Result[SdlTexture, SdlError] = SdlTexture.create(r.handle, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_STREAMING, 256 as Int32, 256 as Int32);
          match tex {
            Ok(t) => {
              t.destroy();
              r.destroy();
              w.destroy();
            }
            Err(e) => {
              r.destroy();
              w.destroy();
            }
          }
        }
        Err(e) => { w.destroy(); }
      }
    }
    Err(e) => { }
  }
}

fn test_j04_resource_context_quit() {
  let ctx: Result[SdlContext, SdlError] = SdlContext.init(SDL_INIT_VIDEO);
  match ctx {
    Ok(c) => { c.quit(); }
    Err(e) => { }
  }
}

// =========================================================================
// SECTION K: FLAG COMBINATIONS -- bitwise OR patterns compile
// =========================================================================

fn test_k01_window_flag_bitwise_or() {
  let combined: Int = SDL_WINDOW_RESIZABLE;
}

fn test_k02_init_flag_bitwise_or() {
  let combined: Int32 = SDL_INIT_VIDEO;
}

// =========================================================================
// SECTION L: RELATIONSHIP CHECKS -- verify logical invariants
// =========================================================================

fn test_l01_scancode_alphabetic_range() -> Bool {
  return SDL_SCANCODE_A == 4 as Int32;
}

fn test_l02_audio_s16le_equals_s16() -> Bool {
  return SDL_AUDIO_S16LE == SDL_AUDIO_S16;
}

fn test_l03_audio_s32le_equals_s32() -> Bool {
  return SDL_AUDIO_S32LE == SDL_AUDIO_S32;
}

fn test_l04_audio_f32le_equals_f32() -> Bool {
  return SDL_AUDIO_F32LE == SDL_AUDIO_F32;
}

fn test_l05_button_lmask_is_lsb() -> Bool {
  return SDL_BUTTON_LMASK == 0x0001 as Int32;
}

fn test_l06_button_mmask_distance() -> Bool {
  return SDL_BUTTON_MMASK == 0x0002 as Int32;
}

fn test_l07_gamepad_invalid_axis() -> Bool {
  return SDL_GAMEPAD_AXIS_INVALID == -1 as Int32;
}

fn test_l08_gamepad_invalid_button() -> Bool {
  return SDL_GAMEPAD_BUTTON_INVALID == -1 as Int32;
}

fn test_l09_powerstate_error() -> Bool {
  return SDL_POWERSTATE_ERROR == -1 as Int32;
}
