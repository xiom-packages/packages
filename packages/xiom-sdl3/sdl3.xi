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
// Coverage (pilot smoke): init / quit / was_init, version + revision, ticks +
// performance counter, delay, pump/poll events, error string.  Window /
// renderer / texture / gamepad resources are Phase 2 (see ROADMAP.md); the
// pre-pilot constant tables and resource wrappers are preserved in git
// history (the file was rewritten at 0.2.0 to the loader design).

module xiom.sdl3

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
pub const SDL_EVENT_WINDOW_CLOSE_REQUESTED: Int = 0x210;

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
  p_get_error: Int;
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
    p_get_error: a11.value,
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

/// SDL_WasInit(flags) -> bool.
/// Complexity: O(1).
pub fn sdl3_was_init(lib: &Sdl3Library, flags: Int) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_was_init as fn(Int) -> UInt8;
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

/// SDL_PollEvent(event) -> bool.  Pass event_ptr = 0 to pump/clear without a
/// buffer; returns true when at least one event was processed.
/// Complexity: O(1).
pub fn sdl3_poll_event(lib: &Sdl3Library, event_ptr: Int) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_poll_event as fn(Int) -> UInt8;
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
pub const SDL_PIXELFORMAT_RGBA8888: Int = 0x16462004;
pub const SDL_TEXTUREACCESS_STATIC: Int = 0;

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
