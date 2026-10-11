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
// release-3.4.8 header; verified byte-identical in the release-3.2.10 clone).
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
pub const SDL_PIXELFORMAT_RGBA8888: Int = 0x16462004;
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
// REL-20261011-0304-bindings), so the pump path keeps consume semantics
// (`sdl3_poll_event(lib, 0)`) and event tests decode self-built buffers.
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
//
// SDL_EventFilter / SDL_EventWatcher are C callbacks (`bool/void (*)(void*
// userdata, SDL_Event* event)`).  ABI (proven by docs/repro/bindings-pilot/
// cb-abi; finding B-13): only a fixed top-level dispatcher's NAME may cross
// into C -- fn-typed PARAM values marshal to 0.  So each registration hands
// SDL ONE fixed dispatcher; user handlers live in a module-level `Vec[fn]`
// registry (m130 element ABI, last set wins).  The dispatcher copies the
// 128-byte event into an owned buffer (our memcpy, safe read direction) so
// handlers use the 0.4.0 decode accessors; this avoids the B-11
// foreign-write readback path entirely.
//
// v0.64.3 constraint (finding B-15): `Vec[fn]` element CALLS with >= 2
// arguments type their result as `()` -- so handler types here take the
// event only (1-arg calls, proven) and the caller's userdata is exposed via
// `sdl3_filter_userdata()` / `sdl3_watch_userdata()`.  Dispatcher bodies
// also avoid `return;` in explicitly `-> Unit` fns (finding B-14).
//
// SDL semantics: the filter runs as events are flushed (pump); returning
// false DROPS the event.  Watches observe without consuming.
// =========================================================================

var sdl3_filter_handlers: Vec[fn(Vec[UInt8]) -> Bool] = Vec[fn(Vec[UInt8]) -> Bool].new();
var sdl3_watch_handlers: Vec[fn(Vec[UInt8]) -> Unit] = Vec[fn(Vec[UInt8]) -> Unit].new();
var sdl3_filter_user: Int = 0;
var sdl3_watch_user: Int = 0;

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

/// Fixed filter dispatcher (the address SDL keeps); last handler wins.
fn sdl3_filter_dispatch(userdata: Int, event: Int) -> UInt8 {
  if event == 0 {
    return 1 as UInt8;
  }
  if sdl3_filter_handlers.len() == 0 {
    return 1 as UInt8;
  }
  let buf = ev_copy_from(event);
  let h = sdl3_filter_handlers[sdl3_filter_handlers.len() - 1];
  let keep = h(buf);
  if keep {
    return 1 as UInt8;
  }
  return 0 as UInt8;
}

/// Fixed watch dispatcher; observers cannot consume.
fn sdl3_watch_dispatch(userdata: Int, event: Int) -> Unit {
  if event != 0 {
    if sdl3_watch_handlers.len() != 0 {
      let buf = ev_copy_from(event);
      let h = sdl3_watch_handlers[sdl3_watch_handlers.len() - 1];
      h(buf);
    }
  }
}

/// Userdata passed at filter registration (SDL hands it to the dispatcher;
/// the 1-arg handler shape reads it here).
/// Complexity: O(1).
pub fn sdl3_filter_userdata() -> Int
  requires: true
{
  return sdl3_filter_user;
}

/// Userdata passed at watch registration.
/// Complexity: O(1).
pub fn sdl3_watch_userdata() -> Int
  requires: true
{
  return sdl3_watch_user;
}

/// SDL_SetEventFilter(dispatcher, userdata).  The handler
/// `fn(event: Vec[UInt8]) -> Bool` decides per event: true keeps it, false
/// drops it (last registered wins; call `sdl3_clear_event_filter` to
/// remove).  Read the registration userdata with `sdl3_filter_userdata()`.
/// Complexity: O(1).
pub fn sdl3_set_event_filter(lib: &Sdl3Library, filter: fn(Vec[UInt8]) -> Bool, userdata: Int) -> Bool
  requires: lib.handle != 0
{
  sdl3_filter_handlers.push(filter);
  sdl3_filter_user = userdata;
  unsafe {
    let f = lib.p_set_event_filter as fn(fn(Int, Int) -> UInt8, Int);
    f(sdl3_filter_dispatch, userdata);
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

/// SDL_AddEventWatch(dispatcher, userdata) -- observe events without
/// consuming.  The handler is `fn(event: Vec[UInt8]) -> Unit` (last
/// registered wins; read the userdata via `sdl3_watch_userdata`; remove
/// with the same userdata via `sdl3_remove_event_watch`).
/// Complexity: O(1).
pub fn sdl3_add_event_watch(lib: &Sdl3Library, watch: fn(Vec[UInt8]) -> Unit, userdata: Int) -> Bool
  requires: lib.handle != 0
{
  sdl3_watch_handlers.push(watch);
  sdl3_watch_user = userdata;
  unsafe {
    let f = lib.p_add_event_watch as fn(fn(Int, Int) -> Unit, Int) -> UInt8;
    return (f(sdl3_watch_dispatch, userdata) as Int) != 0;
  }
}

/// SDL_RemoveEventWatch(dispatcher, userdata); pass the userdata used at
/// registration (the registered handler is the fixed dispatcher).
/// Complexity: O(1).
pub fn sdl3_remove_event_watch(lib: &Sdl3Library, userdata: Int) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_remove_event_watch as fn(fn(Int, Int) -> Unit, Int);
    f(sdl3_watch_dispatch, userdata);
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
