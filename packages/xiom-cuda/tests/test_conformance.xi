// xiom.cuda conformance suite -- CUDA driver API via the runtime loader
// (nvcuda.dll), nothing vendored.
//
// Build+run (the --c-source list rides in port.args.json):
//   scripts/port.ps1 -Package xiom.cuda

module cuda_conformance

use xiom.io;
use xiom.test;
use xiom.cuda;

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
  io.println("=== xiom.cuda conformance tests (driver API, runtime loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. SKIP-path classification, deterministic on every host (bogus module).
  let missing = cuda_probe_named("xiom-absent-cuda-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus loader unexpectedly succeeded");
  } else {
    failed = failed + report(missing.error.kind == CU_LOAD_ABSENT,
      "skip-path: missing loader classified as CU_LOAD_ABSENT (SKIP)");
  }

  // 2. Live probe (or SKIP on a host without an NVIDIA GPU).
  let p = cuda_probe();
  if p.is_ok {
    failed = failed + report(true,
      "probe: CUDA driver " + i2s(p.value.driver_version)
        + ", devices=" + i2s(p.value.device_count)
        + ", name=" + p.value.device_name
        + ", cc=" + i2s(p.value.compute_capability));
    failed = failed + report(p.value.driver_version > 0 && p.value.device_count >= 1,
      "version/devices sane");
    failed = failed + report(p.value.device_name.len() > 0,
      "device name reported");
    failed = failed + report(p.value.memtest_ok,
      "host -> device -> host pattern round trip verified");
  } else {
    if p.error.kind == CU_LOAD_ABSENT || p.error.kind == CU_NO_DEVICE {
      failed = failed + report(true, "probe: SKIP -- " + p.error.message);
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.cuda: all tests passed");
  } else {
    io.println("xiom.cuda: tests failed");
  }
  return failed;
}
