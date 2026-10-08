// XIOM -- xiom.raylib: raylib bindings via dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader path (same pattern as xiom.sdl3 / xiom.glfw). The
// package does NOT link raylib at build time. `raylib_load` resolves
// `raylib.dll` through `xiom.ffi.dl` at runtime and every call goes through
// fn-pointer casts in this single module -- the ONLY module in the package
// with `unsafe`.
//
// Classification (the suite maps it to markers):
//   RAYLIB_LOAD_ABSENT    -> backend missing -> SKIP (CI stays green)
//   RAYLIB_LOAD_NO_WINDOW -> InitWindow produced no ready window (headless)
//                            -> SKIP
//   RAYLIB_LOAD_ABI       -> library present but exports missing -> FAIL
//
// Coverage (pilot smoke): trace-log + config flags, hidden-window init,
// window size/close, timer + frame time + FPS + target FPS, one hidden
// begin/clear/end frame. Textures/models/sounds/input are Phase 2
// (ROADMAP.md); the pre-pilot static-extern module is preserved in git
// history only (it required a system-installed raylib at link time and could
// not satisfy the SKIP-when-absent gate).
//
// G2 pin (SPEC.md): soname `raylib.dll` (Windows) + upstream tag 5.5 header
// hash + resolved symbol set.

module xiom.raylib

use xiom.ffi.dl;

// =========================================================================
// Identity and constants
// =========================================================================

pub const RAYLIB_SONAME: Str = "raylib.dll";

// Trace log levels (raylib 5.5).
pub const LOG_ALL: Int = 0;
pub const LOG_TRACE: Int = 1;
pub const LOG_DEBUG: Int = 2;
pub const LOG_INFO: Int = 3;
pub const LOG_WARNING: Int = 4;
pub const LOG_ERROR: Int = 5;
pub const LOG_FATAL: Int = 6;
pub const LOG_NONE: Int = 7;

// Config flags (raylib 5.5): hidden window keeps the smoke headless-safe.
pub const FLAG_WINDOW_HIDDEN: Int = 0x00000080;

// Packed colors (0xRRGGBBAA).
pub const RAYWHITE: Int = 0xFFFFFFFF;
pub const BLACK: Int = 0x000000FF;
pub const RED: Int = 0xFF0000FF;
pub const GREEN: Int = 0x00FF00FF;
pub const BLUE: Int = 0x0000FFFF;

// Input constants (documented for callers; input API is Phase 2).
pub const KEY_ESCAPE: Int = 256;
pub const MOUSE_BUTTON_LEFT: Int = 0;
pub const MOUSE_BUTTON_RIGHT: Int = 1;

// Probe outcome kinds.
pub const RAYLIB_LOAD_ABSENT: Int = 0;    // backend missing -> SKIP
pub const RAYLIB_LOAD_NO_WINDOW: Int = 1; // no ready window (headless) -> SKIP
pub const RAYLIB_LOAD_ABI: Int = 2;       // exports missing -> FAIL

pub type RaylibLoadError = {
  kind: Int;
  message: Str;
}

pub type RaylibWindowSize = {
  width: Int;
  height: Int;
}

/// A loaded raylib.  Owned by the caller; release with `raylib_close`.
pub type RaylibLibrary = {
  handle: Int;
  p_set_trace_log_level: Int;
  p_set_config_flags: Int;
  p_init_window: Int;
  p_is_window_ready: Int;
  p_window_should_close: Int;
  p_close_window: Int;
  p_get_window_width: Int;
  p_get_window_height: Int;
  p_get_time: Int;
  p_get_frame_time: Int;
  p_get_fps: Int;
  p_set_target_fps: Int;
  p_begin_drawing: Int;
  p_clear_background: Int;
  p_end_drawing: Int;
}

// =========================================================================
// Color helpers (pure; packed 0xRRGGBBAA)
// =========================================================================

/// Pack (r, g, b, a) into a raylib Color value.
/// Complexity: O(1).
pub fn color_rgba(r: Int, g: Int, b: Int, a: Int) -> Int
  requires: r >= 0
  requires: r <= 255
  requires: g >= 0
  requires: g <= 255
  requires: b >= 0
  requires: b <= 255
  requires: a >= 0
  requires: a <= 255
{
  return (r * 16777216) + (g * 65536) + (b * 256) + a;
}

/// Alpha byte of a packed color.
/// Complexity: O(1).
pub fn color_alpha(c: Int) -> Int
  requires: c >= 0
{
  return c % 256;
}

/// Red byte of a packed color.
/// Complexity: O(1).
pub fn color_red(c: Int) -> Int
  requires: c >= 0
{
  return (c / 16777216) % 256;
}

/// Green byte of a packed color.
/// Complexity: O(1).
pub fn color_green(c: Int) -> Int
  requires: c >= 0
{
  return (c / 65536) % 256;
}

/// Blue byte of a packed color.
/// Complexity: O(1).
pub fn color_blue(c: Int) -> Int
  requires: c >= 0
{
  return (c / 256) % 256;
}

// =========================================================================
// Loader
// =========================================================================

/// Load raylib.dll and resolve the smoke API.  Nothing is leaked: the handle
/// is closed when a symbol is missing.
/// Complexity: O(symbols).
pub fn raylib_load() -> Result[RaylibLibrary, RaylibLoadError] {
  let h = dl.dl_open(RAYLIB_SONAME);
  if !h.is_ok {
    return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;

  let a1 = dl.dl_sym(handle, "SetTraceLogLevel");
  if !a1.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "SetTraceLogLevel: " + a1.error }); }
  let a2 = dl.dl_sym(handle, "SetConfigFlags");
  if !a2.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "SetConfigFlags: " + a2.error }); }
  let a3 = dl.dl_sym(handle, "InitWindow");
  if !a3.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "InitWindow: " + a3.error }); }
  let a4 = dl.dl_sym(handle, "IsWindowReady");
  if !a4.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "IsWindowReady: " + a4.error }); }
  let a5 = dl.dl_sym(handle, "WindowShouldClose");
  if !a5.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "WindowShouldClose: " + a5.error }); }
  let a6 = dl.dl_sym(handle, "CloseWindow");
  if !a6.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "CloseWindow: " + a6.error }); }
  let a7 = dl.dl_sym(handle, "GetWindowWidth");
  var w_addr = 0;
  if a7.is_ok {
    w_addr = a7.value;
  } else {
    let a7b = dl.dl_sym(handle, "GetScreenWidth");
    if !a7b.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "GetWindowWidth/GetScreenWidth: " + a7b.error }); }
    w_addr = a7b.value;
  }
  let a8 = dl.dl_sym(handle, "GetWindowHeight");
  var h_addr = 0;
  if a8.is_ok {
    h_addr = a8.value;
  } else {
    let a8b = dl.dl_sym(handle, "GetScreenHeight");
    if !a8b.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "GetWindowHeight/GetScreenHeight: " + a8b.error }); }
    h_addr = a8b.value;
  }
  let a9 = dl.dl_sym(handle, "GetTime");
  if !a9.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "GetTime: " + a9.error }); }
  let a10 = dl.dl_sym(handle, "GetFrameTime");
  if !a10.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "GetFrameTime: " + a10.error }); }
  let a11 = dl.dl_sym(handle, "GetFPS");
  if !a11.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "GetFPS: " + a11.error }); }
  let a12 = dl.dl_sym(handle, "SetTargetFPS");
  if !a12.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "SetTargetFPS: " + a12.error }); }
  let a13 = dl.dl_sym(handle, "BeginDrawing");
  if !a13.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "BeginDrawing: " + a13.error }); }
  let a14 = dl.dl_sym(handle, "ClearBackground");
  if !a14.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "ClearBackground: " + a14.error }); }
  let a15 = dl.dl_sym(handle, "EndDrawing");
  if !a15.is_ok { var ig = dl.dl_close(handle); return Err(RaylibLoadError{ kind: RAYLIB_LOAD_ABI; message: "EndDrawing: " + a15.error }); }

  return Ok(RaylibLibrary{
    handle: handle,
    p_set_trace_log_level: a1.value,
    p_set_config_flags: a2.value,
    p_init_window: a3.value,
    p_is_window_ready: a4.value,
    p_window_should_close: a5.value,
    p_close_window: a6.value,
    p_get_window_width: w_addr,
    p_get_window_height: h_addr,
    p_get_time: a9.value,
    p_get_frame_time: a10.value,
    p_get_fps: a11.value,
    p_set_target_fps: a12.value,
    p_begin_drawing: a13.value,
    p_clear_background: a14.value,
    p_end_drawing: a15.value,
  });
}

/// Release the library handle.
/// Complexity: O(1).
pub fn raylib_close(lib: &RaylibLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

// =========================================================================
// Safe call wrappers (confined: fn-pointer casts live here)
// =========================================================================

/// SetTraceLogLevel(level).  Call before InitWindow to quiet startup output.
/// Complexity: O(1).
pub fn raylib_set_trace_log_level(lib: &RaylibLibrary, level: Int)
  requires: lib.handle != 0
  requires: level >= 0
{
  unsafe {
    let f = lib.p_set_trace_log_level as fn(Int);
    f(level);
  }
}

/// SetConfigFlags(flags).  Use FLAG_WINDOW_HIDDEN for a headless-safe smoke.
/// Complexity: O(1).
pub fn raylib_set_config_flags(lib: &RaylibLibrary, flags: Int)
  requires: lib.handle != 0
  requires: flags >= 0
{
  unsafe {
    let f = lib.p_set_config_flags as fn(Int);
    f(flags);
  }
}

/// InitWindow(width, height, title).
/// Complexity: O(platform init).
pub fn raylib_init_window(lib: &RaylibLibrary, w: Int, h: Int, title: Str)
  requires: lib.handle != 0
  requires: w > 0
  requires: h > 0
  requires: title.len() > 0
{
  unsafe {
    let f = lib.p_init_window as fn(Int, Int, *UInt8);
    f(w, h, title.c_str());
  }
}

/// IsWindowReady -> bool.
/// Complexity: O(1).
pub fn raylib_is_window_ready(lib: &RaylibLibrary) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_is_window_ready as fn() -> UInt8;
    return (f() as Int) != 0;
  }
}

/// WindowShouldClose -> bool.
/// Complexity: O(1).
pub fn raylib_window_should_close(lib: &RaylibLibrary) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_window_should_close as fn() -> UInt8;
    return (f() as Int) != 0;
  }
}

/// CloseWindow.
/// Complexity: O(1).
pub fn raylib_close_window(lib: &RaylibLibrary)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_close_window as fn();
    f();
  }
}

/// GetWindowWidth/GetWindowHeight as a struct.
/// Complexity: O(1).
pub fn raylib_window_size(lib: &RaylibLibrary) -> RaylibWindowSize
  requires: lib.handle != 0
{
  unsafe {
    let fw = lib.p_get_window_width as fn() -> Int32;
    let fh = lib.p_get_window_height as fn() -> Int32;
    return RaylibWindowSize{ width: fw() as Int, height: fh() as Int };
  }
}

/// GetTime -> seconds since InitWindow.
/// Complexity: O(1).
pub fn raylib_get_time(lib: &RaylibLibrary) -> Float64
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_time as fn() -> Float64;
    return f();
  }
}

/// GetFrameTime -> seconds of the last frame.
/// Complexity: O(1).
pub fn raylib_get_frame_time(lib: &RaylibLibrary) -> Float64
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_frame_time as fn() -> Float32;
    let t: Float32 = f();
    return t as Float64;
  }
}

/// GetFPS -> frames per second (last second).
/// Complexity: O(1).
pub fn raylib_get_fps(lib: &RaylibLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_get_fps as fn() -> Int32;
    return f() as Int;
  }
}

/// SetTargetFPS(fps).
/// Complexity: O(1).
pub fn raylib_set_target_fps(lib: &RaylibLibrary, fps: Int)
  requires: lib.handle != 0
  requires: fps >= 0
{
  unsafe {
    let f = lib.p_set_target_fps as fn(Int);
    f(fps);
  }
}

/// BeginDrawing (start one frame).
/// Complexity: O(1).
pub fn raylib_begin_drawing(lib: &RaylibLibrary)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_begin_drawing as fn();
    f();
  }
}

/// ClearBackground(color).
/// Complexity: O(1).
pub fn raylib_clear_background(lib: &RaylibLibrary, color: Int)
  requires: lib.handle != 0
  requires: color >= 0
{
  unsafe {
    let f = lib.p_clear_background as fn(Int);
    f(color);
  }
}

/// EndDrawing (finish one frame).
/// Complexity: O(1).
pub fn raylib_end_drawing(lib: &RaylibLibrary)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_end_drawing as fn();
    f();
  }
}
