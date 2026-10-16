// xiom.gles conformance suite -- ANGLE (libEGL + libGLESv2) loader/probe.
//
// The probe is capability-staged and never FAILs on a missing runtime:
//   present ANGLE    -> symbol stage + display/pbuffer/context + strings
//   missing libs     -> GLES_LOAD_ABSENT (SKIP; exercised deterministically
//                       below with bogus sonames)
//   no display       -> GLES_LOAD_NO_CONTEXT (SKIP)
//   broken install   -> GLES_LOAD_ABI (FAIL -- never a silent SKIP)
//
// Runtime note: put a directory containing libEGL.dll + libGLESv2.dll on the
// DLL search path for the live path, e.g.
//   $env:PATH = "<payload dir with libEGL.dll>;" + $env:PATH
// (an Electron app's payload such as VS Code's versioned app dir works).
//
// Build+run through the runner (compiles src/gles_probe.c via port.args.json):
//   scripts/port.ps1 -Package xiom.gles

module gles_conformance

use xiom.io;
use xiom.convert;
use xiom.gles;
use xiom.gles.gles_api;
use xiom.gles.egl_api;
use xiom.gles.gles_names;
use xiom.gles.egl_names;
use xiom.gles.gles_cmds_01;
use xiom.gles.gles_cmds_02;
use xiom.gles.gles_cmds_03;
use xiom.gles.gles_cmds_04;
use xiom.gles.gles_consts_1;
use xiom.gles.gles_consts_2;
use xiom.gles.gles_consts_3;
use xiom.gles.gles_consts_4;
use xiom.gles.gles_consts_5;
use xiom.gles.gles_android_cmds_01;
use xiom.gles.gles_android_cmds_02;
use xiom.gles.gles_android_cmds_03;
use xiom.gles.gles_android_cmds_04;
use xiom.gles.gles_android_cmds_05;
use xiom.gles.gles_android_consts_1;
use xiom.gles.gles_android_consts_2;
use xiom.gles.gles_android_consts_3;
use xiom.gles.gles_android_consts_4;
use xiom.gles.gles_android_consts_5;
use xiom.gles.egl_cmds_01;
use xiom.gles.egl_cmds_02;
use xiom.gles.egl_consts_1;
use xiom.gles.egl_consts_2;
use xiom.gles.egl_consts_3;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn has_str(v: Vec[Str], s: Str) -> Bool {
  var i = 0;
  while i < v.len() {
    if v[i] == s { return true; }
    i = i + 1;
  }
  return false;
}

fn t_constants() -> Bool {
  var ok = true;
  if GLES_LOAD_ABSENT != 0 || GLES_LOAD_NO_CONTEXT != 1 || GLES_LOAD_ABI != 2 { ok = false; }
  if GLES_SESSION_CLIENT_VERSION != 3 { ok = false; }
  if GL_VENDOR != 0x1F00 || GL_RENDERER != 0x1F01 || GL_VERSION != 0x1F02 { ok = false; }
  if GL_ARRAY_BUFFER != 0x8892 || GL_BUFFER_SIZE != 0x8764 || GL_STATIC_DRAW != 0x88E4 { ok = false; }
  if GL_MAJOR_VERSION != 0x821B { ok = false; }
  if EGL_VERSION != 0x3054 || EGL_VENDOR != 0x3053 { ok = false; }
  if EGL_OPENGL_ES_API != 0x30A0 || EGL_PBUFFER_BIT != 0x0001 { ok = false; }
  return ok;
}

// The android leg: generated runtime-load candidates + the measured NDK
// r27b delta (GLES2/GLES3/KHR extension surface) + the EGL android family
// (measured complete over the NDK EGL headers; see docs/COVERAGE.md).
fn t_android_delta() -> Bool {
  var ok = true;

  // Runtime-load candidates (Windows ANGLE DLLs retained + Android system).
  let egl_c = egl_load_candidates();
  let gles_c = gles_load_candidates();
  if egl_c.len() != EGL_LOAD_CANDIDATE_COUNT || EGL_LOAD_CANDIDATE_COUNT != 3 { ok = false; }
  if gles_c.len() != GLES_LOAD_CANDIDATE_COUNT || GLES_LOAD_CANDIDATE_COUNT != 5 { ok = false; }
  if !has_str(egl_c, "libEGL.dll") || !has_str(egl_c, "EGL.dll") { ok = false; }
  if !has_str(egl_c, "libEGL.so") { ok = false; }
  if !has_str(gles_c, "libGLESv2.dll") || !has_str(gles_c, "GLESv2.dll") { ok = false; }
  if !has_str(gles_c, "libGLESv2.so") || !has_str(gles_c, "libGLESv3.so") { ok = false; }
  if !has_str(gles_c, "libGLESv1_CM.so") { ok = false; }

  // Android delta command surface (NDK r27b GLES2/GLES3/KHR beyond core).
  let anc = gles_android_cmd_names();
  if anc.len() != GLES_ANDROID_CMD_COUNT || GLES_ANDROID_CMD_COUNT != 494 { ok = false; }
  if !has_str(anc, "glBlendBarrierKHR") || !has_str(anc, "glDebugMessageCallbackKHR") { ok = false; }
  if !has_str(anc, "glEGLImageTargetTexture2DOES") || !has_str(anc, "glGetObjectLabelKHR") { ok = false; }

  // Android delta constants (spot values from the pinned dispatch).
  if GLES_ANDROID_CONST_COUNT != 1225 { ok = false; }
  if GL_TEXTURE_EXTERNAL_OES != 0x8D65 || GL_SAMPLER_EXTERNAL_OES != 0x8D66 { ok = false; }
  if GL_ETC1_RGB8_OES != 0x8D64 { ok = false; }
  if GL_DEBUG_OUTPUT_KHR != 0x92E0 || GL_MAX_LABEL_LENGTH_KHR != 0x82E8 { ok = false; }
  if GL_TEXTURE_MAX_ANISOTROPY_EXT != 0x84FE || GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT != 0x84FF { ok = false; }

  // EGL android family (carried by the EGL 1.5 + extensions surface).
  let en = egl_cmd_names();
  if !has_str(en, "eglCreateNativeClientBufferANDROID") || !has_str(en, "eglGetNativeClientBufferANDROID") { ok = false; }
  if !has_str(en, "eglGetFrameTimestampsANDROID") || !has_str(en, "eglPresentationTimeANDROID") { ok = false; }
  if !has_str(en, "eglDupNativeFenceFDANDROID") || !has_str(en, "eglSetBlobCacheFuncsANDROID") { ok = false; }
  if EGL_NATIVE_BUFFER_ANDROID != 0x3140 || EGL_PLATFORM_ANDROID_KHR != 0x3141 { ok = false; }
  if EGL_RECORDABLE_ANDROID != 0x3142 || EGL_FRAMEBUFFER_TARGET_ANDROID != 0x3147 { ok = false; }
  if EGL_SYNC_NATIVE_FENCE_FD_ANDROID != 0x3145 || EGL_NO_NATIVE_FENCE_FD_ANDROID != -1 { ok = false; }
  if EGL_FRONT_BUFFER_AUTO_REFRESH_ANDROID != 0x314C { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.gles conformance tests (ANGLE loader/probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: kinds + GL/EGL enums (generated)");
  failed = failed + report(t_android_delta(),
    "android delta: loader candidates + NDK r27b surface (" + to_string(GLES_ANDROID_CMD_COUNT) + " cmds + " + to_string(GLES_ANDROID_CONST_COUNT) + " consts + EGL android family)");

  // SKIP-path classification, deterministic on every host (bogus pair).
  let missing = gles_probe_named("xiom-absent-egl-xyz.dll", "xiom-absent-gles-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus pair unexpectedly produced a context");
  } else {
    failed = failed + report(missing.error.kind == GLES_LOAD_ABSENT,
      "skip-path: absent pair classified as GLES_LOAD_ABSENT (SKIP)");
  }

  // Default runtime probe.
  let p = gles_probe();
  if p.is_ok {
    let info: GlesInfo = p.value;
    failed = failed + report(info.egl_version.len() > 0, "egl: EGL_VERSION = " + info.egl_version);
    failed = failed + report(info.gles_version.len() > 0, "gles: GL_VERSION = " + info.gles_version);
    failed = failed + report(info.gles_renderer.len() > 0, "gles: GL_RENDERER = " + info.gles_renderer);
    if info.glsl.len() > 0 {
      failed = failed + report(true, "gles: GL_SHADING_LANGUAGE_VERSION = " + info.glsl);
    } else {
      failed = failed + report(true, "gles: GL_SHADING_LANGUAGE_VERSION absent (ES2-only context)");
    }
  } else {
    if p.error.kind == GLES_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- ANGLE not present (" + p.error.message + ")");
    } else if p.error.kind == GLES_LOAD_NO_CONTEXT {
      failed = failed + report(true, "probe: SKIP -- no EGL context available (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // Live session: the generated GLES + EGL surfaces resolve through it.
  if p.is_ok {
    let so = gles_session_open(GLES_SESSION_CLIENT_VERSION);
    if so.is_ok {
      let api = gles_api_new();
      let eapi = egl_api_new();
      failed = failed + report(gles_session_is_active(), "session: ES context active");
      let dpy = gles_session_display();
      failed = failed + report(dpy != 0, "session: EGLDisplay live");

      // GLES oracle set: every core command (ES 2.0 -> 3.2) must resolve.
      let gnames = gles_cmd_names();
      var gunresolved: Int = 0;
      var gi = 0;
      while gi < gnames.len() {
        if gles_api_resolve(&api, gnames[gi].c_str()) == 0 {
          gunresolved = gunresolved + 1;
        }
        gi = gi + 1;
      }
      failed = failed + report(gnames.len() == GLES_CMD_COUNT && gunresolved == 0,
        "surface: " + to_string(GLES_CMD_COUNT) + " ES core commands resolved (unresolved=" + to_string(gunresolved) + ")");

      // EGL oracle: the 1.5 feature set must resolve (extension commands are
      // driver/implementation-conditional).
      let enames = egl_core_names();
      var eunresolved: Int = 0;
      var ei = 0;
      while ei < enames.len() {
        if egl_api_resolve(&eapi, enames[ei].c_str()) == 0 {
          eunresolved = eunresolved + 1;
        }
        ei = ei + 1;
      }
      failed = failed + report(enames.len() == EGL_CORE_COUNT && eunresolved == 0,
        "egl: " + to_string(EGL_CORE_COUNT) + " core commands resolved (unresolved=" + to_string(eunresolved) + ")");

      // Android delta commands: extension-conditional by nature (the live
      // runtime advertises a subset); report the count, never fail on it.
      let anames = gles_android_cmd_names();
      var aresolved: Int = 0;
      var ai = 0;
      while ai < anames.len() {
        if gles_api_resolve(&api, anames[ai].c_str()) != 0 {
          aresolved = aresolved + 1;
        }
        ai = ai + 1;
      }
      failed = failed + report(true,
        "android delta: " + to_string(aresolved) + "/" + to_string(GLES_ANDROID_CMD_COUNT) + " extension commands resolved on the live runtime (extension-conditional)");

      // Oracle counts (emitted == registry).
      failed = failed + report(gles_cmd_names().len() == GLES_CMD_COUNT && egl_cmd_names().len() == EGL_CMD_COUNT,
        "oracle: " + to_string(GLES_CMD_COUNT) + " GLES + " + to_string(EGL_CMD_COUNT) + " EGL commands");

      failed = failed + report(gles_api_resolve(&api, "glXiomNotACommand".c_str()) == 0,
        "surface: bogus command resolves to 0");

      // glGetString through the generated wrapper.
      let vptr = gl_get_string(&api, GL_VERSION as UInt32);
      let vstr = unsafe { Str::from_c_str(vptr) };
      failed = failed + report(vstr.len() > 0,
        "surface: glGetString(GL_VERSION) = " + vstr);

      // EGL wrapper: eglQueryString(display, EGL_VERSION).
      let evptr = egl_query_string(&eapi, dpy, EGL_VERSION as Int32);
      let evstr = unsafe { Str::from_c_str(evptr) };
      failed = failed + report(evstr.len() > 0, "egl: eglQueryString(EGL_VERSION) = " + evstr);

      let _ = gl_get_error(&api);
      var majs: Vec[Int32] = Vec[Int32].new();
      majs.push(0);
      gl_get_integerv(&api, GL_MAJOR_VERSION as UInt32, majs.as_mut_ptr());
      failed = failed + report(majs[0] >= 2,
        "surface: glGetIntegerv(GL_MAJOR_VERSION) = " + to_string(majs[0] as Int));

      // Buffer roundtrip (ES2 path).
      var ids: Vec[UInt32] = Vec[UInt32].new();
      ids.push(0);
      gl_gen_buffers(&api, 1, ids.as_mut_ptr());
      if ids[0] != 0 {
        gl_bind_buffer(&api, GL_ARRAY_BUFFER as UInt32, ids[0]);
        var bytes: Vec[UInt8] = Vec[UInt8].new();
        var b = 0;
        while b < 64 { bytes.push((b & 0xFF) as UInt8); b = b + 1; }
        gl_buffer_data(&api, GL_ARRAY_BUFFER as UInt32, 64, bytes.as_mut_ptr(), GL_STATIC_DRAW as UInt32);
        var sz: Vec[Int32] = Vec[Int32].new();
        sz.push(0);
        gl_get_buffer_parameteriv(&api, GL_ARRAY_BUFFER as UInt32, GL_BUFFER_SIZE as UInt32, sz.as_mut_ptr());
        let buferr = gl_get_error(&api);
        failed = failed + report(sz[0] == 64 && buferr == 0,
          "surface: buffer roundtrip (size=" + to_string(sz[0] as Int) + " err=" + to_string(buferr as Int) + ")");
        gl_bind_buffer(&api, GL_ARRAY_BUFFER as UInt32, 0);
        gl_delete_buffers(&api, 1, ids.as_mut_ptr());
      } else {
        failed = failed + report(false, "surface: glGenBuffers returned 0");
      }

      gles_session_close();
      failed = failed + report(!gles_session_is_active(), "session: closed");
    } else if so.error.kind == GLES_LOAD_ABSENT || so.error.kind == GLES_LOAD_NO_CONTEXT {
      failed = failed + report(true, "session: SKIP -- unavailable (" + so.error.message + ")");
    } else {
      failed = failed + report(false, "session: open failed -- " + so.error.message);
    }
  }

  // Unload must be safe even after a failed probe.
  gles_unload();
  failed = failed + report(true, "loader: unload path exercised");

  if failed == 0 {
    io.println("xiom.gles: all tests passed");
  } else {
    io.println("xiom.gles: tests failed");
  }
  return failed;
}
