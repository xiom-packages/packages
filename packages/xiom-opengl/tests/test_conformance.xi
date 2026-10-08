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
use xiom.opengl;

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
