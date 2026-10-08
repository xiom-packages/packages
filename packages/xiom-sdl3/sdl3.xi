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
