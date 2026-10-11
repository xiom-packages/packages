// Manual diagnostic probe -- kept as the repro for the 2026-10-11
// `f64_from_bits` clause fix (negative IEEE-754 sign bit). NOT part of the
// conformance suite; port.ps1 does not run it. It warps the PHYSICAL cursor
// (user32 SetCursorPos) to (window.x-50, window.y-50), so run it only
// deliberately on a desktop session.
//
// Hypothesis: `f64_from_bits` (glfw.xi) carries `requires: bits >= 0`, but a
// raw IEEE-754 bit pattern read as a signed Int is negative whenever the
// sign bit is set (any negative float -- e.g. a window-relative cursor
// coordinate left/above the window). The conformance suite died at
// "contract violated: requires at 598:13" when its cursor readback happened
// to be negative; glfw_set_cursor_pos(1,1) is a silent no-op on a hidden
// unfocused window, so the suite actually reads the live physical cursor.
//
// Experiment (deterministic): warp the PHYSICAL cursor (user32 SetCursorPos,
// the same link the suite uses) to (window.x-50, window.y-50) so the
// window-relative readback is exactly (-50,-50) -- negative sign bit set.
// Expectation: pre-warp read prints positive; post-warp read crashes at
// requires 598:13 (before the fix) / prints -50,-50 (after the fix).
//
// Run (from packages/xiom-glfw, GLFW DLL dir on PATH):
//   xiom --run tests/probe_neg_f64.xi --link user32

module probe_neg_f64

use xiom.io;
use xiom.convert;
use xiom.glfw;

extern "C" {
  fn SetCursorPos(x: Int32, y: Int32) -> Int32;
}

fn main() {
  let l = glfw_load();
  if !l.is_ok { io.println("no GLFW: " + l.error.message); return; }
  let lib: GlfwLibrary = l.value;

  if !glfw_init(&lib) {
    io.println("init failed: " + glfw_last_error(&lib));
    return;
  }

  glfw_default_window_hints(&lib);
  glfw_window_hint(&lib, GLFW_VISIBLE, GLFW_FALSE);
  glfw_window_hint(&lib, GLFW_CLIENT_API, GLFW_NO_API);
  let cw = glfw_create_window(&lib, 400, 300, "neg f64 probe", 0, 0);
  if !cw.is_ok { io.println("no window: " + cw.error); return; }
  let w: GlfwWindow = cw.value;

  let wp = glfw_get_window_pos(&lib, &w);
  io.println("window at " + to_string(wp.x) + "," + to_string(wp.y));

  let before = glfw_get_cursor_pos(&lib, &w);
  io.println("pre-warp: x=" + to_string(before.x as Int) + " y=" + to_string(before.y as Int));

  var wr = 0;
  unsafe {
    wr = SetCursorPos((wp.x - 50) as Int32, (wp.y - 50) as Int32) as Int;
  }
  io.println("SetCursorPos(" + to_string(wp.x - 50) + "," + to_string(wp.y - 50)
    + ") -> " + to_string(wr) + "; reading back now");

  let after = glfw_get_cursor_pos(&lib, &w);
  io.println("post-warp: x=" + to_string(after.x as Int) + " y=" + to_string(after.y as Int));

  glfw_destroy_window(&lib, &w);
  glfw_terminate(&lib);
  glfw_close(&lib);
}
