// xiom.opengl conformance suite -- staged loader probe (GPU-lite path).
//
// The probe is capability-staged and never FAILs on a missing GPU or display:
//   present runtime  -> symbol stage + contextless stage + VENDOR/VERSION...
//   missing library  -> OPENGL_LOAD_ABSENT (SKIP; exercised deterministically
//                       below with a bogus soname)
//   no display       -> OPENGL_LOAD_NO_CONTEXT (SKIP)
//   broken install   -> OPENGL_LOAD_ABI (FAIL -- never a silent SKIP)
//
// Build+run through the runner (compiles src/gl_probe.c via port.args.json):
//   scripts/port.ps1 -Package xiom.opengl
// or directly:
//   xiom --run tests/test_conformance.xi --c-source <abs>/src/gl_probe.c

module opengl_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.ffi;
use xiom.opengl;
use xiom.opengl.glapi;
use xiom.opengl.names;
use xiom.opengl.cmds_01;
use xiom.opengl.cmds_02;
use xiom.opengl.cmds_03;
use xiom.opengl.cmds_04;
use xiom.opengl.cmds_05;
use xiom.opengl.cmds_06;
use xiom.opengl.cmds_07;
use xiom.opengl.consts_1;
use xiom.opengl.consts_2;
use xiom.opengl.consts_3;
use xiom.opengl.consts_4;
use xiom.opengl.consts_5;
use xiom.opengl.consts_6;

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

fn t_constants() -> Bool {
  var ok = true;
  if GL_VENDOR != 0x1F00 { ok = false; }
  if GL_RENDERER != 0x1F01 { ok = false; }
  if GL_VERSION != 0x1F02 { ok = false; }
  if GL_SHADING_LANGUAGE_VERSION != 0x8B8C { ok = false; }
  if (PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER) != 0x25 { ok = false; }
  if PFD_SIZE != 40 { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.opengl conformance tests (loader probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: GL enums + PFD flags/layout");

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = opengl_probe_named("xiom-absent-gl-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly produced a context");
  } else {
    failed = failed + report(missing.error.kind == OPENGL_LOAD_ABSENT,
      "skip-path: absent library classified as OPENGL_LOAD_ABSENT (SKIP)");
  }

  // Default runtime probe.
  let p = opengl_probe();
  if p.is_ok {
    let info: GlInfo = p.value;
    failed = failed + report(info.vendor.len() > 0, "context: GL_VENDOR = " + info.vendor);
    failed = failed + report(info.version.len() > 0, "context: GL_VERSION = " + info.version);
    failed = failed + report(info.renderer.len() > 0, "context: GL_RENDERER = " + info.renderer);
    if info.glsl.len() > 0 {
      failed = failed + report(true, "context: GL_SHADING_LANGUAGE_VERSION = " + info.glsl);
    } else {
      failed = failed + report(true, "context: GL_SHADING_LANGUAGE_VERSION absent (legacy context)");
    }
    if info.contextless_len == 0 {
      failed = failed + report(true, "contextless: glGetString(VERSION) NULL before wglMakeCurrent (expected)");
    } else {
      failed = failed + report(true, "contextless: glGetString(VERSION) returned " + to_string(info.contextless_len) + " chars without a context");
    }
  } else {
    if p.error.kind == OPENGL_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- OpenGL runtime not present (" + p.error.message + ")");
    } else if p.error.kind == OPENGL_LOAD_NO_CONTEXT {
      failed = failed + report(true, "probe: SKIP -- no WGL context available (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // Phase 2: core-profile context probe (3.3 core) + extension scan.
  if p.is_ok {
    let core = opengl_probe_core(3, 3);
    if core.is_ok {
      let ci: GlCoreInfo = core.value;
      failed = failed + report(ci.major >= 3,
        "core: negotiated " + to_string(ci.major) + "." + to_string(ci.minor) + " core (" + ci.version + ")");
      failed = failed + report(ci.extension_count > 0,
        "core: extension count = " + to_string(ci.extension_count));
      failed = failed + report(ci.extension_head.len() > 0,
        "core: extension head = " + ci.extension_head);

      let bogus = opengl_has_extension("GL_XIOM_NOT_AN_EXTENSION");
      if bogus.is_ok {
        failed = failed + report(!bogus.value, "core: bogus extension correctly absent");
      } else {
        failed = failed + report(false, "core: extension scan failed -- " + bogus.error.message);
      }
      let aniso = opengl_has_extension("GL_EXT_texture_filter_anisotropic");
      if aniso.is_ok {
        if aniso.value {
          failed = failed + report(true, "core: GL_EXT_texture_filter_anisotropic present");
        } else {
          failed = failed + report(true, "core: GL_EXT_texture_filter_anisotropic not present (driver-dependent)");
        }
      } else {
        failed = failed + report(true, "core: extension scan SKIP -- " + aniso.error.message);
      }
    } else {
      if core.error.kind == OPENGL_LOAD_NO_CONTEXT {
        failed = failed + report(true, "core: SKIP -- no core context available (" + core.error.message + ")");
      } else if core.error.kind == OPENGL_LOAD_ABSENT {
        failed = failed + report(true, "core: SKIP -- OpenGL runtime not present");
      } else {
        failed = failed + report(false, "core: probe failed -- " + core.error.message);
      }
    }
  }

  // 0.4.0: full-surface session -- the generated core-4.6 wrappers
  // (Khronos OpenGL-Registry gl.xml; PROVENANCE.md).  Resolution check:
  // every core command in the registry-derived name table must resolve.
  if p.is_ok {
    let so = opengl_session_open(OPENGL_SESSION_MAJOR, OPENGL_SESSION_MINOR);
    if so.is_ok {
      let api = gl_api_new();
      failed = failed + report(opengl_session_is_active(), "surface: session context active (4.6 core)");

      let cnames = gl_cmd_names();
      var unresolved: Int = 0;
      var i = 0;
      while i < cnames.len() {
        if gl_api_resolve(&api, cnames[i].c_str()) == 0 {
          unresolved = unresolved + 1;
        }
        i = i + 1;
      }
      failed = failed + report(cnames.len() == GL_CMD_COUNT && unresolved == 0,
        "surface: " + to_string(GL_CMD_COUNT) + " core commands resolved (unresolved=" + to_string(unresolved) + ")");
      failed = failed + report(gl_api_resolve(&api, "glXiomNotACommand".c_str()) == 0,
        "surface: bogus command resolves to 0");

      failed = failed + report(GL_MAJOR_VERSION == 0x821B && GL_ARRAY_BUFFER == 0x8892
          && GL_COMPILE_STATUS == 0x8B81 && GL_VERTEX_SHADER == 0x8B31,
        "surface: generated consts (GL_MAJOR_VERSION/ARRAY_BUFFER/COMPILE_STATUS/VERTEX_SHADER)");

      let _ = gl_get_error(&api);
      var majs: Vec[Int32] = Vec[Int32].new();
      majs.push(0);
      gl_get_integerv(&api, GL_MAJOR_VERSION as UInt32, majs.as_mut_ptr());
      failed = failed + report(majs[0] >= 4,
        "surface: glGetIntegerv(GL_MAJOR_VERSION) = " + to_string(majs[0] as Int));

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

      let sh = gl_create_shader(&api, GL_VERTEX_SHADER as UInt32);
      if sh != 0 {
        let srctext: Str = "#version 330 core\nvoid main() { gl_Position = vec4(0.0, 0.0, 0.0, 1.0); }\n";
        var ptrs: Vec[UInt8] = Vec[UInt8].new();
        var k = 0;
        while k < 8 { ptrs.push(0 as UInt8); k = k + 1; }
        unsafe {
          ffi.ptr_write_u64_le(ptrs.as_mut_ptr(), srctext.c_str() as Int);
        }
        gl_shader_source(&api, sh, 1, ptrs.as_mut_ptr(), 0 as *Int32);
        gl_compile_shader(&api, sh);
        var st: Vec[Int32] = Vec[Int32].new();
        st.push(0);
        gl_get_shaderiv(&api, sh, GL_COMPILE_STATUS as UInt32, st.as_mut_ptr());
        failed = failed + report(st[0] == 1, "surface: shader compile status=" + to_string(st[0] as Int));
        gl_delete_shader(&api, sh);
      } else {
        failed = failed + report(false, "surface: glCreateShader returned 0");
      }

      opengl_session_close();
      failed = failed + report(!opengl_session_is_active(), "surface: session closed");
    } else if so.error.kind == OPENGL_LOAD_ABSENT || so.error.kind == OPENGL_LOAD_NO_CONTEXT {
      failed = failed + report(true, "surface: SKIP -- session unavailable (" + so.error.message + ")");
    } else {
      failed = failed + report(false, "surface: session open failed -- " + so.error.message);
    }
  }

  // Unload must be safe even after a failed probe.
  opengl_unload();
  failed = failed + report(true, "loader: unload path exercised");

  if failed == 0 {
    io.println("xiom.opengl: all tests passed");
  } else {
    io.println("xiom.opengl: tests failed");
  }
  return failed;
}
