// xiom.ozz conformance suite -- vendored C++ amalgamation path.
//
// Proves the real binding against the vendored ozz-animation 0.16.0
// amalgamations compiled into the test binary:
//   scripts/port.ps1 -Package xiom.ozz
// (port.args.json passes vendor/ozz_all.cpp + vendor/ozz_bridge.cpp).
//
// Coverage: math primitives, offline RawSkeleton -> runtime Skeleton, and a
// LocalToModelJob run with verified model-space translations.  There is no
// SKIP path (the library is compiled in).

module ozz_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.ozz;

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

fn main() -> Int {
  io.println("=== xiom.ozz conformance tests (vendored amalgamation) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(ozz_math_ok(),
    "math: Float3 dot/cross + quaternion axis rotation (90deg about Z maps X->Y)");
  failed = failed + report(ozz_skeleton_ok(),
    "skeleton: offline RawSkeleton -> runtime Skeleton (2 joints, parents -1/0)");
  failed = failed + report(ozz_local_to_model_ok(),
    "local_to_model: root at origin, child translated (0,1,0) in model space");

  let all = ozz_probe();
  if all.is_ok {
    failed = failed + report(true, "aggregate: ozz_probe() all green");
  } else {
    failed = failed + report(false, "aggregate: " + all.error);
  }

  if failed == 0 {
    io.println("xiom.ozz: all tests passed");
  } else {
    io.println("xiom.ozz: tests failed");
  }
  return failed;
}
