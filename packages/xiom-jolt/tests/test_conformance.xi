// xiom.jolt conformance suite -- vendored Jolt Physics v5.6.0 core.
//
// Build+run (the --c-source list rides in port.args.json):
//   scripts/port.ps1 -Package xiom.jolt
// NOTE: Jolt needs C++17; on the v0.64.2 canonical install the suite cannot
// build (C++14 default).  Verified on the v0.64.3 install (shadow during the
// canonical swap); re-run through port.ps1 after the native repin.

module jolt_conformance

use xiom.io;
use xiom.test;
use xiom.jolt;

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
  io.println("=== xiom.jolt conformance tests (vendored v5.6.0) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. Resting drop: 1 m box from y=5 settles on a ground (top at y=0);
  //    the center lands at ~0.5 (half extent) within tolerance.
  let d = jolt_drop();
  if d.is_ok {
    failed = failed + report(d.value.final_y_milli >= 400 && d.value.final_y_milli <= 600,
      "drop: final_y=" + i2s(d.value.final_y_milli) + " milli, awake=" + b2s(d.value.awake));
    failed = failed + report(!d.value.awake, "drop: body asleep after settling");
  } else {
    failed = failed + report(false, "drop: " + d.error);
  }

  // 2. Velocity hand-off: a free box given vx=5 m/s keeps it through a step.
  let im = jolt_impulse_vx();
  if im.is_ok {
    failed = failed + report(im.value >= 4500 && im.value <= 5500,
      "impulse: vx=" + i2s(im.value) + " milli");
  } else {
    failed = failed + report(false, "impulse: " + im.error);
  }

  // 3. Determinism: a repeated drop yields the same final y.
  let d2 = jolt_drop();
  let same = d.is_ok && d2.is_ok && d2.value.final_y_milli == d.value.final_y_milli;
  failed = failed + report(same, "determinism: repeated drop identical");

  if failed == 0 {
    io.println("xiom.jolt: all tests passed");
  } else {
    io.println("xiom.jolt: tests failed");
  }
  return failed;
}
