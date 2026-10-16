// XIOM -- xiom.gles: OpenGL ES + EGL bindings via a runtime-loaded
// implementation (Windows ANGLE pair or the Android system libraries).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: capability probe + live session with SKIP semantics, backed by the
// small vendored bridge `src/gles_probe.c` (compiled with `--c-source`; see
// port.args.json).  The bridge resolves the runtime at RUNTIME
// (LoadLibraryA/GetProcAddress on Windows, dlopen/dlsym elsewhere +
// eglGetProcAddress) and performs a staged probe on a PBUFFER surface (no
// window system dependency):
//
//   Stage 1 symbols -- EGL exports + glGetString (the GLES library or
//                      eglGetProcAddress)
//   Stage 2 context -- default display -> initialize -> bind ES API ->
//                      choose config (pbuffer, RGBA8) -> pbuffer surface +
//                      ES3 context (falls back to ES2) -> GL strings
//
// Loader candidates (generated: `egl_names.egl_load_candidates()` /
// `gles_names.gles_load_candidates()`): the Windows ANGLE DLL pair first,
// then the Android system sonames -- `libEGL.so` with `libGLESv2.so`, then
// `libGLESv3.so`, then `libGLESv1_CM.so` (last resort; see SPEC.md sec. 2).
//
// Classification (the suite maps it to markers):
//   GLES_LOAD_ABSENT     -> SKIP  (runtime libs missing; CI stays green)
//   GLES_LOAD_NO_CONTEXT -> SKIP  (no display/config/context)
//   GLES_LOAD_ABI        -> FAIL  (present but exports missing)
//
// Runtime note: the implementation is NOT vendored -- on Windows put a
// directory containing `libEGL.dll` + `libGLESv2.dll` on the DLL search
// path (e.g. the payload directory of an Electron app such as VS Code);
// on Android the platform libraries are used directly.  Absent -> SKIP.
//
// The generated surfaces (modules `xiom.gles.gles_cmds_*` from the pinned
// Khronos `gl.xml`, `xiom.gles.gles_android_cmds_*` for the NDK r27b
// android delta, `xiom.gles.egl_cmds_*` from the pinned EGL-Registry
// `egl.xml`; see PROVENANCE.md) resolve each entry point per call through
// `src/gles_api.xi` / `src/egl_api.xi` and this module's `gles_get_proc`
// (eglGetProcAddress -> GLES library -> EGL library) / `gles_egl_proc`
// (eglGetProcAddress -> EGL library).  All hand-written `unsafe`/`extern`
// stay in this module; the generated modules carry only the mechanical
// resolve + cast call.

module xiom.gles

extern "C" {
  fn xgs_load_named(egl_soname: *UInt8, gles_soname: *UInt8) -> Int32;
  fn xgs_load() -> Int32;
  fn xgs_error() -> *UInt8;
  fn xgs_query() -> Int32;
  fn xgs_egl_version() -> *UInt8;
  fn xgs_egl_vendor() -> *UInt8;
  fn xgs_gles_vendor() -> *UInt8;
  fn xgs_gles_renderer() -> *UInt8;
  fn xgs_gles_version() -> *UInt8;
  fn xgs_gles_glsl() -> *UInt8;
  fn xgs_session_open(client_version: Int32) -> Int32;
  fn xgs_session_active() -> Int32;
  fn xgs_session_display() -> Int;
  fn xgs_get_proc(name: *UInt8) -> Int;
  fn xgs_egl_proc(name: *UInt8) -> Int;
  fn xgs_session_close();
  fn xgs_unload();
}

// =========================================================================
// Identity and classification
// =========================================================================

// Runtime-load candidate sonames are GENERATED (one const home):
//   egl_names.egl_load_candidates()   -- EGL side (Windows ANGLE + Android)
//   gles_names.gles_load_candidates() -- GLES side
// The bridge probes the candidate PAIRS in order: the Windows ANGLE DLLs
// (libEGL.dll/libGLESv2.dll, fallback EGL.dll/GLESv2.dll) and then the
// Android system libraries (libEGL.so with libGLESv2.so -> libGLESv3.so ->
// libGLESv1_CM.so); see `xgs_pairs` in src/gles_probe.c.

// Probe outcome kinds.
pub const GLES_LOAD_ABSENT: Int = 0;     // runtime libs missing -> SKIP
pub const GLES_LOAD_NO_CONTEXT: Int = 1; // no display/config/context -> SKIP
pub const GLES_LOAD_ABI: Int = 2;        // exports missing -> FAIL

pub type GlesProbeError = {
  kind: Int;
  message: Str;
}

pub type GlesInfo = {
  egl_version: Str;
  egl_vendor: Str;
  gles_vendor: Str;
  gles_renderer: Str;
  gles_version: Str;
  glsl: Str;
}

pub type GlesSession = {
  client_version: Int;
}

// =========================================================================
// Probe API
// =========================================================================

/// Probe an explicitly named EGL/GLES pair.  Useful for tests: a bogus pair
/// exercises the ABSENT/SKIP classification deterministically even on hosts
/// that ship ANGLE.
/// Complexity: O(load + display + pbuffer + context + strings).
pub fn gles_probe_named(egl_soname: Str, gles_soname: Str) -> Result[GlesInfo, GlesProbeError]
  requires: egl_soname.len() > 0
  requires: gles_soname.len() > 0
{
  let rc = unsafe { xgs_load_named(egl_soname.c_str(), gles_soname.c_str()) as Int };
  return gles_probe_staged(rc);
}

/// Probe the default runtime: the candidate pairs in the bridge (the Windows
/// ANGLE DLLs first, then the Android system sonames -- see the generated
/// `egl_load_candidates()` / `gles_load_candidates()`).  None present ->
/// SKIP.
/// Complexity: O(load + display + pbuffer + context + strings).
pub fn gles_probe() -> Result[GlesInfo, GlesProbeError]
  requires: true
{
  let rc = unsafe { xgs_load() as Int };
  return gles_probe_staged(rc);
}

/// Shared staging after a load attempt: classify the load result, then run
/// the display -> initialize -> API bind -> config -> pbuffer -> context ->
/// strings probe on it.
fn gles_probe_staged(rc: Int) -> Result[GlesInfo, GlesProbeError]
  requires: true
{
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xgs_error()) };
    if rc == 1 {
      return Err(GlesProbeError{ kind: GLES_LOAD_ABSENT; message: msg });
    }
    return Err(GlesProbeError{ kind: GLES_LOAD_ABI; message: msg });
  }

  let q = unsafe { xgs_query() as Int };
  if q != 0 {
    let msg = unsafe { Str::from_c_str(xgs_error()) };
    unsafe { xgs_unload(); }
    if q == 2 {
      return Err(GlesProbeError{ kind: GLES_LOAD_ABI; message: msg });
    }
    return Err(GlesProbeError{ kind: GLES_LOAD_NO_CONTEXT; message: msg });
  }

  let egl_version = unsafe { Str::from_c_str(xgs_egl_version()) };
  let egl_vendor = unsafe { Str::from_c_str(xgs_egl_vendor()) };
  let gles_vendor = unsafe { Str::from_c_str(xgs_gles_vendor()) };
  let gles_renderer = unsafe { Str::from_c_str(xgs_gles_renderer()) };
  let gles_version = unsafe { Str::from_c_str(xgs_gles_version()) };
  let glsl = unsafe { Str::from_c_str(xgs_gles_glsl()) };
  unsafe { xgs_unload(); }

  return Ok(GlesInfo{
    egl_version: egl_version,
    egl_vendor: egl_vendor,
    gles_vendor: gles_vendor,
    gles_renderer: gles_renderer,
    gles_version: gles_version,
    glsl: glsl,
  });
}

// =========================================================================
// Session API: a live ES context for the generated wrappers
// (src/gles_cmds_*.xi, src/egl_cmds_*.xi).
// =========================================================================

pub const GLES_SESSION_CLIENT_VERSION: Int = 3;

/// Open the default runtime with an ES context of the requested client
/// version (>= 2; version 3 falls back to 2) on a 64x64 pbuffer and keep it
/// current for the session.  The generated wrappers resolve their entry
/// points through it.  Close with `gles_session_close` (or `gles_unload`,
/// which closes it first).
/// Complexity: O(load + display + pbuffer + context).
pub fn gles_session_open(client_version: Int) -> Result[GlesSession, GlesProbeError]
  requires: client_version >= 2
{
  let rc = unsafe { xgs_load() as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xgs_error()) };
    if rc == 1 {
      return Err(GlesProbeError{ kind: GLES_LOAD_ABSENT; message: msg });
    }
    return Err(GlesProbeError{ kind: GLES_LOAD_ABI; message: msg });
  }
  let q = unsafe { xgs_session_open(client_version as Int32) as Int };
  if q != 0 {
    let msg = unsafe { Str::from_c_str(xgs_error()) };
    unsafe { xgs_unload(); }
    if q == 2 {
      return Err(GlesProbeError{ kind: GLES_LOAD_ABI; message: msg });
    }
    return Err(GlesProbeError{ kind: GLES_LOAD_NO_CONTEXT; message: msg });
  }
  return Ok(GlesSession{ client_version: client_version });
}

/// True while a session context is current.
/// Complexity: O(1).
pub fn gles_session_is_active() -> Bool
  requires: true
{
  unsafe { return (xgs_session_active() as Int) != 0; }
}

/// The live session's raw `EGLDisplay` (0 when no session is live).
/// Complexity: O(1).
pub fn gles_session_display() -> Int
  requires: true
{
  unsafe { return xgs_session_display(); }
}

/// Resolve a GLES command through the live runtime: `eglGetProcAddress`
/// first, then the `libGLESv2`/`libEGL` export tables.  Returns 0 when
/// unresolved.  This is the resolver the generated `gles_*` wrappers use.
/// Complexity: O(1).
pub fn gles_get_proc(name: *UInt8) -> Int
  requires: true
{
  unsafe { return xgs_get_proc(name); }
}

/// Resolve an EGL command: `eglGetProcAddress` first, then the `libEGL`
/// export table.  Returns 0 when unresolved.  The resolver the generated
/// `egl_*` wrappers use.
/// Complexity: O(1).
pub fn gles_egl_proc(name: *UInt8) -> Int
  requires: true
{
  unsafe { return xgs_egl_proc(name); }
}

/// Close the session (surface/context/display) and unload ANGLE.  Safe when
/// no session is open.
/// Complexity: O(teardown).
pub fn gles_session_close()
  requires: true
{
  unsafe { xgs_unload(); }
}

/// Release any runtime handles held by the probe.  Safe to call when nothing
/// is loaded.
/// Complexity: O(1).
pub fn gles_unload()
  requires: true
{
  unsafe { xgs_unload(); }
}
