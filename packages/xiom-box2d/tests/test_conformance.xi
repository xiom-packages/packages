// xiom.box2d conformance suite -- vendored Box2D v3.1.1 (C API).
//
// Build+run (the --c-source list rides in port.args.json):
//   scripts/port.ps1 -Package xiom.box2d

module box2d_conformance

use xiom.io;
use xiom.test;
use xiom.box2d;

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
  io.println("=== xiom.box2d conformance tests (vendored v3.1.1) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. Version pin (v3.1.x).
  let v = b2_version();
  let major = v >> 16;
  let minor = (v >> 8) & 255;
  failed = failed + report(major == 3 && minor == 1, "version: " + b2_version_str(v));

  // 2. Default gravity read back from a live world.
  let g = b2_gravity();
  if g.is_ok {
    failed = failed + report(g.value.gx_milli == 0 && g.value.gy_milli == -10000,
      "gravity: (" + i2s(g.value.gx_milli) + ", " + i2s(g.value.gy_milli) + ") milli");
  } else {
    failed = failed + report(false, "gravity: " + g.error);
  }

  // 3. Resting drop: 1x1 box from y=10 settles on a ground (top at y=0);
  //    the center lands at ~0.5 (half extent) within tolerance.
  let d = b2_drop(10000, B2_DEFAULT_STEPS);
  if d.is_ok {
    failed = failed + report(d.value.final_y_milli >= 400 && d.value.final_y_milli <= 600,
      "drop: final_y=" + i2s(d.value.final_y_milli) + " milli, awake=" + b2s(d.value.awake));
  } else {
    failed = failed + report(false, "drop: " + d.error);
  }

  // 4. Impulse -> velocity on a free box (mass 1 kg): dv = J / m.
  let im = b2_impulse(5000);
  if im.is_ok {
    failed = failed + report(im.value >= 4500 && im.value <= 5500,
      "impulse: vx=" + i2s(im.value) + " milli");
  } else {
    failed = failed + report(false, "impulse: " + im.error);
  }

  // 5. Determinism: a repeated drop yields the same final y.
  let d2 = b2_drop(10000, B2_DEFAULT_STEPS);
  let same = d.is_ok && d2.is_ok && d2.value.final_y_milli == d.value.final_y_milli;
  failed = failed + report(same, "determinism: repeated drop identical");

  if failed == 0 {
    io.println("xiom.box2d: all tests passed");
  } else {
    io.println("xiom.box2d: tests failed");
  }
  return failed;
}
