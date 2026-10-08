// XIOM -- xiom.opengl: OpenGL loader/probe bindings (GPU-lite path).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: capability probe with SKIP semantics, backed by the small vendored
// bridge `src/gl_probe.c` (compiled with `--c-source`, see port.args.json).
// The bridge resolves opengl32.dll + user32/gdi32 at RUNTIME
// (LoadLibraryA/GetProcAddress) and performs the staged probe:
//
//   Stage 1 symbols     -- opengl32 exports + wgl* + Win32 window/DC calls
//   Stage 2 contextless -- glGetString(GL_VERSION) with no current context
//                          (expected NULL; proves the call path is safe)
//   Stage 3 context     -- 1x1 static window + pixel format + WGL context,
//                          then VENDOR/RENDERER/VERSION/GLSL, full cleanup
//
// Classification (the suite maps it to markers):
//   OPENGL_LOAD_ABSENT     -> SKIP  (library missing; CI stays green)
//   OPENGL_LOAD_NO_CONTEXT -> SKIP  (no display/pixel format/context)
//   OPENGL_LOAD_ABI        -> FAIL  (library present but exports missing)
//
// The bridge carries the Win32 struct work (PIXELFORMATDESCRIPTOR) in C: a
// pure-XIOM version of the context path proved compiler-fragile on v0.64.0
// (see docs/BINDINGS-COMPILER-FINDINGS.md, B-09). All XIOM `unsafe` and
// `extern "C"` stay confined to this single module (G5).
//
// G2 pin: soname `opengl32.dll` (Windows system component) + the bridge's
// resolved symbol set + PIXELFORMATDESCRIPTOR layout; local runtime sample
// recorded in SPEC.md §2 as reference, not as the pin.

module xiom.opengl

extern "C" {
  fn xgl_load_named(soname: *UInt8) -> Int32;
  fn xgl_load() -> Int32;
  fn xgl_error() -> *UInt8;
  fn xgl_contextless_len() -> Int32;
  fn xgl_query() -> Int32;
  fn xgl_query_core(major: Int32, minor: Int32, flags: Int32) -> Int32;
  fn xgl_core_major() -> Int32;
  fn xgl_core_minor() -> Int32;
  fn xgl_extension_count() -> Int32;
  fn xgl_extension_head() -> *UInt8;
  fn xgl_has_extension(name: *UInt8) -> Int32;
  fn xgl_vendor() -> *UInt8;
  fn xgl_renderer() -> *UInt8;
  fn xgl_version() -> *UInt8;
  fn xgl_glsl() -> *UInt8;
  fn xgl_unload();
}

// =========================================================================
// Identity and GL enums
// =========================================================================

pub const OPENGL_GL_SONAME: Str = "opengl32.dll";

pub const GL_VENDOR: Int = 0x1F00;
pub const GL_RENDERER: Int = 0x1F01;
pub const GL_VERSION: Int = 0x1F02;
pub const GL_EXTENSIONS: Int = 0x1F03;
pub const GL_SHADING_LANGUAGE_VERSION: Int = 0x8B8C;

// PIXELFORMATDESCRIPTOR values used by the bridge (documentation/pin only).
pub const PFD_DOUBLEBUFFER: Int = 0x00000001;
pub const PFD_DRAW_TO_WINDOW: Int = 0x00000004;
pub const PFD_SUPPORT_OPENGL: Int = 0x00000020;
pub const PFD_TYPE_RGBA: Int = 0;
pub const PFD_MAIN_PLANE: Int = 0;
pub const PFD_SIZE: Int = 40;

// Probe outcome kinds.
pub const OPENGL_LOAD_ABSENT: Int = 0;     // library missing -> SKIP
pub const OPENGL_LOAD_NO_CONTEXT: Int = 1; // no display/format/context -> SKIP
pub const OPENGL_LOAD_ABI: Int = 2;        // exports missing -> FAIL

pub type GlProbeError = {
  kind: Int;
  message: Str;
}

pub type GlInfo = {
  vendor: Str;
  renderer: Str;
  version: Str;
  glsl: Str;
  contextless_len: Int;
}

/// Core-context probe result: strings plus the negotiated core version and
/// the extension count / head (first up to four extension names).
pub type GlCoreInfo = {
  vendor: Str;
  renderer: Str;
  version: Str;
  glsl: Str;
  major: Int;
  minor: Int;
  extension_count: Int;
  extension_head: Str;
}

// =========================================================================
// Probe API
// =========================================================================

/// Probe an explicitly named OpenGL runtime.  Useful for tests: a bogus name
/// exercises the ABSENT/SKIP classification deterministically even on hosts
/// that have a GPU.
/// Complexity: O(load + window + context + strings).
pub fn opengl_probe_named(soname: Str) -> Result[GlInfo, GlProbeError]
  requires: soname.len() > 0
{
  let rc = unsafe { xgl_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xgl_error()) };
    if rc == 1 {
      return Err(GlProbeError{ kind: OPENGL_LOAD_ABSENT; message: msg });
    }
    return Err(GlProbeError{ kind: OPENGL_LOAD_ABI; message: msg });
  }

  let ctxless = unsafe { xgl_contextless_len() as Int };

  let q = unsafe { xgl_query() as Int };
  if q != 0 {
    let msg = unsafe { Str::from_c_str(xgl_error()) };
    unsafe { xgl_unload(); }
    if q == 2 {
      return Err(GlProbeError{ kind: OPENGL_LOAD_ABI; message: msg });
    }
    return Err(GlProbeError{ kind: OPENGL_LOAD_NO_CONTEXT; message: msg });
  }

  let vendor = unsafe { Str::from_c_str(xgl_vendor()) };
  let renderer = unsafe { Str::from_c_str(xgl_renderer()) };
  let version = unsafe { Str::from_c_str(xgl_version()) };
  let glsl = unsafe { Str::from_c_str(xgl_glsl()) };
  unsafe { xgl_unload(); }

  return Ok(GlInfo{
    vendor: vendor,
    renderer: renderer,
    version: version,
    glsl: glsl,
    contextless_len: ctxless,
  });
}

/// Probe the default runtime (`opengl32.dll`).
/// Complexity: O(load + window + context + strings).
pub fn opengl_probe() -> Result[GlInfo, GlProbeError]
  requires: true
{
  return opengl_probe_named(OPENGL_GL_SONAME);
}

/// Probe an explicitly named runtime with a **core-profile** context of the
/// requested version (`major` >= 3).  Resolves `wglCreateContextAttribsARB`
/// through a temporary classic context, then reports the negotiated version
/// plus the extension count and the first few extension names.
/// Complexity: O(load + 2 contexts + extension scan).
pub fn opengl_probe_core_named(soname: Str, major: Int, minor: Int) -> Result[GlCoreInfo, GlProbeError]
  requires: soname.len() > 0
  requires: major >= 3
  requires: minor >= 0
{
  let rc = unsafe { xgl_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xgl_error()) };
    if rc == 1 {
      return Err(GlProbeError{ kind: OPENGL_LOAD_ABSENT; message: msg });
    }
    return Err(GlProbeError{ kind: OPENGL_LOAD_ABI; message: msg });
  }

  let q = unsafe { xgl_query_core(major as Int32, minor as Int32, 0 as Int32) as Int };
  if q != 0 {
    let msg = unsafe { Str::from_c_str(xgl_error()) };
    unsafe { xgl_unload(); }
    if q == 2 {
      return Err(GlProbeError{ kind: OPENGL_LOAD_ABI; message: msg });
    }
    return Err(GlProbeError{ kind: OPENGL_LOAD_NO_CONTEXT; message: msg });
  }

  let vendor = unsafe { Str::from_c_str(xgl_vendor()) };
  let renderer = unsafe { Str::from_c_str(xgl_renderer()) };
  let version = unsafe { Str::from_c_str(xgl_version()) };
  let glsl = unsafe { Str::from_c_str(xgl_glsl()) };
  let vmajor = unsafe { xgl_core_major() as Int };
  let vminor = unsafe { xgl_core_minor() as Int };
  let ext_count = unsafe { xgl_extension_count() as Int };
  let ext_head = unsafe { Str::from_c_str(xgl_extension_head()) };
  unsafe { xgl_unload(); }

  return Ok(GlCoreInfo{
    vendor: vendor,
    renderer: renderer,
    version: version,
    glsl: glsl,
    major: vmajor,
    minor: vminor,
    extension_count: ext_count,
    extension_head: ext_head,
  });
}

/// Probe the default runtime with a core-profile context.
/// Complexity: O(load + 2 contexts + extension scan).
pub fn opengl_probe_core(major: Int, minor: Int) -> Result[GlCoreInfo, GlProbeError]
  requires: major >= 3
  requires: minor >= 0
{
  return opengl_probe_core_named(OPENGL_GL_SONAME, major, minor);
}

/// True when the named extension is present in the runtime's extension list
/// (exact match; scanned with a 3.3 core context).
/// Complexity: O(load + context + extensions).
pub fn opengl_has_extension_named(soname: Str, name: Str) -> Result[Bool, GlProbeError]
  requires: soname.len() > 0
  requires: name.len() > 0
{
  let rc = unsafe { xgl_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xgl_error()) };
    if rc == 1 {
      return Err(GlProbeError{ kind: OPENGL_LOAD_ABSENT; message: msg });
    }
    return Err(GlProbeError{ kind: OPENGL_LOAD_ABI; message: msg });
  }
  let r = unsafe { xgl_has_extension(name.c_str()) as Int };
  if r < 0 {
    let msg = unsafe { Str::from_c_str(xgl_error()) };
    unsafe { xgl_unload(); }
    return Err(GlProbeError{ kind: OPENGL_LOAD_NO_CONTEXT; message: msg });
  }
  unsafe { xgl_unload(); }
  if r == 1 {
    return Ok(true);
  }
  return Ok(false);
}

/// Default-runtime extension check.
/// Complexity: O(load + context + extensions).
pub fn opengl_has_extension(name: Str) -> Result[Bool, GlProbeError]
  requires: name.len() > 0
{
  return opengl_has_extension_named(OPENGL_GL_SONAME, name);
}

/// Release any runtime handles held by the probe.  Safe to call when nothing
/// is loaded.
/// Complexity: O(1).
pub fn opengl_unload()
  requires: true
{
  unsafe { xgl_unload(); }
}
