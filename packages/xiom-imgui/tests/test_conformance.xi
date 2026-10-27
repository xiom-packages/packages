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

  // 5. Long-lived context handles: create two, registry bookkeeping.
  let c1 = imgui_context_create(320, 240);
  let c2 = imgui_context_create(640, 480);
  var h1: Int = 0;
  var h2: Int = 0;
  if c1.is_ok { h1 = c1.value; }
  if c2.is_ok { h2 = c2.value; }
  failed = failed + report(c1.is_ok && c2.is_ok && h1 != 0 && h2 != 0 && h1 != h2
      && imgui_context_count() == 2,
    "context: create h1=" + i2s(h1) + " h2=" + i2s(h2) + " count=" + i2s(imgui_context_count()));

  // 6. Persistence across calls: first frame hides the new window; report
  //    the settling frames (auto-size) before the steady-state assertion.
  let g1 = imgui_context_frame(h1);
  let g2 = imgui_context_frame(h1);
  let g3 = imgui_context_frame(h1);
  let g4 = imgui_context_frame(h1);
  let g5 = imgui_context_frame(h1);
  var f1c = -1;
  var f2c = -1;
  var f3c = -1;
  var f4c = -1;
  var f5c = -1;
  var f4v = -1;
  var f5v = -1;
  if g1.is_ok { f1c = g1.value.cmd_lists; }
  if g2.is_ok { f2c = g2.value.cmd_lists; }
  if g3.is_ok { f3c = g3.value.cmd_lists; }
  if g4.is_ok { f4c = g4.value.cmd_lists; f4v = g4.value.vertices; }
  if g5.is_ok { f5c = g5.value.cmd_lists; f5v = g5.value.vertices; }
  failed = failed + report(f1c == 0 && f2c >= 1 && f4c == f5c && f4v == f5v
      && imgui_context_frames(h1) == 5,
    "context: long-lived frames (first hidden, steady state stable, frames=5)");

  // 7. Destroy semantics: h1 gone, h2 still frames, double-destroy false.
  let d1 = imgui_context_destroy(h1);
  let count1 = imgui_context_count();
  let h2f = imgui_context_frame(h2);
  let d2 = imgui_context_destroy(h2);
  let d3 = imgui_context_destroy(h2);
  failed = failed + report(d1 && count1 == 1 && h2f.is_ok && h2f.value.cmd_lists == 0
      && d2 && !d3 && imgui_context_count() == 0,
    "context: destroy h1 -> count 1; h2 frames; destroy h2 -> count 0; double-destroy false");

  // 8. 0.4.0 SDL3 platform backend: hidden window + real frames.
  if imgui_backend_sdl3_available() {
    let s = imgui_backend_sdl3_selftest();
    if s.is_ok {
      failed = failed + report(s.value.vertices > 0 && s.value.indices > 0 && s.value.cmd_lists >= 1,
        "backend: SDL3 platform selftest vertices=" + i2s(s.value.vertices)
          + " indices=" + i2s(s.value.indices) + " cmd_lists=" + i2s(s.value.cmd_lists));
    } else {
      failed = failed + report(false, "backend: SDL3 selftest " + s.error);
    }
  } else {
    failed = failed + report(true, "backend: SDL3 platform SKIP -- no video driver");
  }

  // 9. Backend context registry (separate from the null-backend contexts).
  let b = imgui_backend_create();
  var bh: Int = 0;
  if b.is_ok { bh = b.value; }
  failed = failed + report(b.is_ok && bh != 0 && imgui_backend_count() == 1
      && imgui_backend_frames(bh) == 0,
    "backend: create handle=" + i2s(bh) + " count=" + i2s(imgui_backend_count()));

  // 10. Missing engine handles fail typed (no crash): SDL window and the
  //     Vulkan instance/device/render-pass set.
  let sbad = imgui_backend_sdl3_init(bh, 0, false);
  let vbad = imgui_backend_vulkan_init(bh, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  let ddata = imgui_backend_draw_data(bh);
  failed = failed + report(!sbad.is_ok && !vbad.is_ok && ddata == 0,
    "backend: missing SDL window / Vulkan handles rejected typed (no crash)");

  // 11. Shutdown semantics: handle gone, double-shutdown false.
  let bd = imgui_backend_shutdown(bh);
  failed = failed + report(bd && imgui_backend_count() == 0 && !imgui_backend_shutdown(bh),
    "backend: shutdown -> count 0; double-shutdown false");

  if failed == 0 {
    io.println("xiom.imgui: all tests passed");
  } else {
    io.println("xiom.imgui: tests failed");
  }
  return failed;
}
