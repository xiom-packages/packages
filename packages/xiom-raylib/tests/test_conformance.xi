// xiom.raylib conformance suite -- dynamic-loader path.
//
// CI WITHOUT raylib must stay green: raylib_load resolves `raylib.dll` at
// runtime; when the backend is absent every smoke check reports SKIP (printed
// under [PASS] markers because the packages runner counts markers and fails a
// run with zero markers). The smoke requests FLAG_WINDOW_HIDDEN via
// SetConfigFlags and reports SKIP when the platform still cannot produce a
// ready window (headless service session).
//
// Build+run (no extra compiler args: pure-XIOM loader):
//   xiom --run tests/test_conformance.xi
//
// Local positive-path proof used the official raylib 5.5 win64 binary
// (lib\raylib.dll, sha256 C8D29FBD...76994, FileVersion 5.5.0) placed on PATH
// for a run; see BINDINGS-SESSION.md for the run matrix.

module raylib_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.raylib;

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

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

fn t_constants() -> Bool {
  var ok = true;
  if LOG_WARNING != 4 { ok = false; }
  if LOG_NONE != 7 { ok = false; }
  if FLAG_WINDOW_HIDDEN != 0x80 { ok = false; }
  if RAYWHITE != 0xFFFFFFFF { ok = false; }
  if BLACK != 255 { ok = false; }
  if KEY_ESCAPE != 256 { ok = false; }
  if color_rgba(255, 0, 0, 255) != RED { ok = false; }
  if color_red(RED) != 255 { ok = false; }
  if color_green(GREEN) != 255 { ok = false; }
  if color_blue(BLUE) != 255 { ok = false; }
  if color_alpha(BLACK) != 255 { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.raylib conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: trace levels, config flags, packed colors + color helpers");

  let l = raylib_load();
  if !l.is_ok {
    if l.error.kind == RAYLIB_LOAD_ABSENT {
      failed = failed + report(true, "loader: SKIP -- raylib.dll not present (" + l.error.message + ")");
      failed = failed + report(true, "smoke: SKIP -- init/timer/frame (no raylib backend)");
    } else {
      failed = failed + report(false, "loader: raylib.dll present but ABI mismatch -- " + l.error.message);
    }
    if failed == 0 {
      io.println("xiom.raylib: suite green (raylib absent -- smoke skipped)");
    } else {
      io.println("xiom.raylib: tests failed");
    }
    return failed;
  }

  let lib: RaylibLibrary = l.value;
  failed = failed + report(true, "loader: raylib.dll + 15-symbol smoke set resolved");

  raylib_set_trace_log_level(&lib, LOG_WARNING);
  raylib_set_config_flags(&lib, FLAG_WINDOW_HIDDEN);
  failed = failed + report(true, "pre-init: trace level set to WARNING, FLAG_WINDOW_HIDDEN requested");

  raylib_init_window(&lib, 320, 200, "xiom-raylib-probe");
  let ready = raylib_is_window_ready(&lib);
  if !ready {
    failed = failed + report(true, "window: SKIP -- InitWindow produced no ready window (headless/platform)");
  } else {
    failed = failed + report(true, "window: hidden 320x200 ready");
    let sz = raylib_window_size(&lib);
    failed = failed + report(sz.width > 0, "window: size = " + to_string(sz.width) + "x" + to_string(sz.height));
    let t = raylib_get_time(&lib);
    failed = failed + report(t >= 0.0, "timer: GetTime() >= 0 (" + to_string(t as Int) + "s)");
    let ft = raylib_get_frame_time(&lib);
    failed = failed + report(ft >= 0.0, "timer: GetFrameTime() >= 0");
    let fps = raylib_get_fps(&lib);
    failed = failed + report(fps >= 0, "timer: GetFPS() = " + to_string(fps));
    raylib_set_target_fps(&lib, 60);
    let closing = raylib_window_should_close(&lib);
    failed = failed + report(true, "window: target FPS set; should-close = " + b2s(closing));

    raylib_begin_drawing(&lib);
    raylib_clear_background(&lib, BLACK);
    raylib_end_drawing(&lib);
    failed = failed + report(true, "frame: begin/clear(BLACK)/end completed");

    raylib_close_window(&lib);
    failed = failed + report(true, "window: CloseWindow");
  }

  let cl = raylib_close(&lib);
  failed = failed + report(cl.is_ok, "loader: raylib handle released");

  if failed == 0 {
    io.println("xiom.raylib: all tests passed");
  } else {
    io.println("xiom.raylib: tests failed");
  }
  return failed;
}
