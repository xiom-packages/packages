// XIOM -- xiom.glfw: GLFW bindings via dynamic loader.
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
// Coverage (pilot smoke): init / terminate, version (packed + string), timer,
// last-error accessor. Window/input/monitor resources are Phase 2
// (ROADMAP.md); the pre-pilot C-bridge wrapper set is preserved in git
// history only (it required GLFW headers/import libs at build time and could
// not satisfy the SKIP-when-absent gate).
//
// G2 pin (SPEC.md): soname `glfw3.dll` (Windows) / `libglfw.so.3` (POSIX,
// Phase 2) + upstream tag 3.4 header hash + resolved symbol set.

module xiom.glfw

use xiom.ffi.dl;

// =========================================================================
// Identity and constants
// =========================================================================

pub const GLFW3_SONAME: Str = "glfw3.dll";

pub const GLFW_TRUE: Int = 1;
pub const GLFW_FALSE: Int = 0;
pub const GLFW_KEY_ESCAPE: Int = 256;
pub const GLFW_PRESS: Int = 1;
pub const GLFW_RELEASE: Int = 0;
pub const GLFW_CLIENT_API: Int = 0x00022001;
pub const GLFW_NO_API: Int = 0;

// Probe outcome kinds.
pub const GLFW_LOAD_ABSENT: Int = 0;      // backend missing -> SKIP
pub const GLFW_LOAD_NO_PLATFORM: Int = 1; // glfwInit failed (headless) -> SKIP
pub const GLFW_LOAD_ABI: Int = 2;         // exports missing -> FAIL

pub type GlfwLoadError = {
  kind: Int;
  message: Str;
}

/// A loaded GLFW library.  Owned by the caller; release with `glfw_close`.
pub type GlfwLibrary = {
  handle: Int;
  p_init: Int;
  p_terminate: Int;
  p_get_version: Int;
  p_get_version_string: Int;
  p_get_time: Int;
  p_get_error: Int;
}

// =========================================================================
// Out-param slot helpers (XIOM-owned buffers; no malloc/free)
// =========================================================================

fn slot_new(n: Int) -> Vec[UInt8]
  requires: n > 0
  requires: n <= 64
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn read_u32_le(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 4
{
  let b0 = buf[0] as Int;
  let b1 = buf[1] as Int;
  let b2 = buf[2] as Int;
  let b3 = buf[3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn read_u64_le(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 8
{
  let b0 = buf[0] as Int;
  let b1 = buf[1] as Int;
  let b2 = buf[2] as Int;
  let b3 = buf[3] as Int;
  let b4 = buf[4] as Int;
  let b5 = buf[5] as Int;
  let b6 = buf[6] as Int;
  let b7 = buf[7] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
       | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56);
}

// =========================================================================
// Loader
// =========================================================================

/// Load glfw3.dll and resolve the smoke API.  Nothing is leaked: the handle
/// is closed when a symbol is missing.
/// Complexity: O(symbols).
pub fn glfw_load() -> Result[GlfwLibrary, GlfwLoadError] {
  let h = dl.dl_open(GLFW3_SONAME);
  if !h.is_ok {
    return Err(GlfwLoadError{ kind: GLFW_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;

  let a1 = dl.dl_sym(handle, "glfwInit");
  if !a1.is_ok { var ig = dl.dl_close(handle); return Err(GlfwLoadError{ kind: GLFW_LOAD_ABI; message: "glfwInit: " + a1.error }); }
  let a2 = dl.dl_sym(handle, "glfwTerminate");
  if !a2.is_ok { var ig = dl.dl_close(handle); return Err(GlfwLoadError{ kind: GLFW_LOAD_ABI; message: "glfwTerminate: " + a2.error }); }
  let a3 = dl.dl_sym(handle, "glfwGetVersion");
  if !a3.is_ok { var ig = dl.dl_close(handle); return Err(GlfwLoadError{ kind: GLFW_LOAD_ABI; message: "glfwGetVersion: " + a3.error }); }
  let a4 = dl.dl_sym(handle, "glfwGetVersionString");
  if !a4.is_ok { var ig = dl.dl_close(handle); return Err(GlfwLoadError{ kind: GLFW_LOAD_ABI; message: "glfwGetVersionString: " + a4.error }); }
  let a5 = dl.dl_sym(handle, "glfwGetTime");
  if !a5.is_ok { var ig = dl.dl_close(handle); return Err(GlfwLoadError{ kind: GLFW_LOAD_ABI; message: "glfwGetTime: " + a5.error }); }
  let a6 = dl.dl_sym(handle, "glfwGetError");
  if !a6.is_ok { var ig = dl.dl_close(handle); return Err(GlfwLoadError{ kind: GLFW_LOAD_ABI; message: "glfwGetError: " + a6.error }); }

  return Ok(GlfwLibrary{
    handle: handle,
    p_init: a1.value,
    p_terminate: a2.value,
    p_get_version: a3.value,
    p_get_version_string: a4.value,
    p_get_time: a5.value,
    p_get_error: a6.value,
  });
}

/// Release the library handle.
/// Complexity: O(1).
pub fn glfw_close(lib: &GlfwLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

// =========================================================================
// Safe call wrappers (confined: fn-pointer casts live here)
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

/// glfwGetVersion() packed as major*10000 + minor*100 + rev
/// (3.4.0 -> 30400).
/// Complexity: O(1).
pub fn glfw_get_version(lib: &GlfwLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    var sm = slot_new(4);
    var sn = slot_new(4);
    var sr = slot_new(4);
    let f = lib.p_get_version as fn(*UInt8, *UInt8, *UInt8);
    f(sm.as_mut_ptr(), sn.as_mut_ptr(), sr.as_mut_ptr());
    let major = read_u32_le(&sm);
    let minor = read_u32_le(&sn);
    let rev = read_u32_le(&sr);
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
    let code = f(slot.as_mut_ptr()) as Int;
    if code == 0 { return ""; }
    let ptr = read_u64_le(&slot);
    if ptr == 0 { return ""; }
    return Str::from_c_str(ptr as *UInt8);
  }
}
