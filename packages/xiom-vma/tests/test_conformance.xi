// xiom.vma conformance suite -- vendored VMA 3.4.0 + Vulkan-Headers core,
// runtime loader (vulkan-1.dll) via the bridge.
//
// Build+run (the --c-source list rides in port.args.json):
//   scripts/port.ps1 -Package xiom.vma

module vma_conformance

use xiom.io;
use xiom.test;
use xiom.vma;

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
  io.println("=== xiom.vma conformance tests (vendored v3.4.0) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. SKIP-path classification, deterministic on every host (bogus module).
  let missing = vma_probe_named("xiom-absent-vulkan-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus loader unexpectedly succeeded");
  } else {
    failed = failed + report(missing.error.kind == VMA_LOAD_ABSENT,
      "skip-path: missing loader classified as VMA_LOAD_ABSENT (SKIP)");
  }

  // 2. Live probe (or SKIP on a host without a Vulkan device).
  let p = vma_probe();
  if p.is_ok {
    failed = failed + report(true,
      "probe: VMA allocator live -- heaps=" + i2s(p.value.heap_count)
        + " alloc_size=" + i2s(p.value.alloc_size)
        + " verify=" + i2s(p.value.verify));
    failed = failed + report(p.value.alloc_size == 65536,
      "alloc: requested 65536, reported " + i2s(p.value.alloc_size));
    failed = failed + report(p.value.verify == 1,
      "mapped pattern write/read-back verified");
    failed = failed + report(p.value.heap_count > 0,
      "memory heaps reported: " + i2s(p.value.heap_count));
  } else {
    if p.error.kind == VMA_LOAD_ABSENT || p.error.kind == VMA_NO_DEVICE {
      failed = failed + report(true, "probe: SKIP -- " + p.error.message);
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.vma: all tests passed");
  } else {
    io.println("xiom.vma: tests failed");
  }
  return failed;
}
