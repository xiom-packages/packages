// xiom.imgui conformance suite -- vendored Dear ImGui v1.92.9b core (headless).
//
// Build+run (the --c-source list rides in port.args.json):
//   scripts/port.ps1 -Package xiom.imgui

module imgui_conformance

use xiom.io;
use xiom.test;
use xiom.imgui;

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

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var v = n;
  if v < 0 {
    neg = true;
    v = 0 - v;
  }
  var buf = "";
  while v > 0 {
    let digit = v % 10;
    v = v / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  if neg { return "-" + buf; }
  return buf;
}

fn main() -> Int {
  io.println("=== xiom.imgui conformance tests (vendored v1.92.9b) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. Version pin (packed number + string).
  let v = imgui_version();
  let vs = imgui_version_str();
  failed = failed + report(v == 19291 && vs == "1.92.9b",
    "version: " + vs + " (" + i2s(v) + ")");

  // 2. Headless frame with a text window tessellates draw data.
  let f = imgui_frame();
  if f.is_ok {
    failed = failed + report(f.value.vertices > 0 && f.value.indices > 0 && f.value.cmd_lists >= 1,
      "frame: vertices=" + i2s(f.value.vertices) + " indices=" + i2s(f.value.indices)
        + " cmd_lists=" + i2s(f.value.cmd_lists));
  } else {
    failed = failed + report(false, "frame: " + f.error);
  }

  // 3. Empty frame (no windows) produces zero draw lists.
  let e = imgui_empty_frame();
  if e.is_ok {
    failed = failed + report(e.value == 0, "empty frame: cmd_lists=" + i2s(e.value));
  } else {
    failed = failed + report(false, "empty frame: " + e.error);
  }

  // 4. Determinism: a repeated frame yields identical counts.
  let f2 = imgui_frame();
  let same = f.is_ok && f2.is_ok
    && f2.value.vertices == f.value.vertices
    && f2.value.indices == f.value.indices;
  failed = failed + report(same, "determinism: repeated frame identical");

  if failed == 0 {
    io.println("xiom.imgui: all tests passed");
  } else {
    io.println("xiom.imgui: tests failed");
  }
  return failed;
}
