// xiom.numpy -- OPTIONAL real-leg acceleration probe.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// THIS FILE IS NOT PART OF THE OFFLINE CONFORMANCE SUITE. `scripts/port.ps1`
// always runs `tests/test_conformance.xi`; this probe is only meaningful when
// the artifact is linked against real OpenBLAS plus
// `../xiom-openblas/bridge/openblas_real_marker.c` (never together with the
// stub bridge):
//
//   xiom --run tests/probe_numpy_real_leg.xi ^
//       --c-source ../xiom-openblas/bridge/openblas_real_marker.c ^
//       --link-path <openblas>/lib --link libopenblas
//
// `tests/run_real_leg.ps1` runs this probe and sets XIOM_NO_DEP_PORT_ARGS=1:
// without it, the path dependency's shipped `port.args.json` is auto-applied
// at consumer build time, so the stub bridge is linked too and lld reports a
// duplicate `xiom_openblas_backend` symbol. The offline conformance suite
// (port.ps1) remains authoritative for AccelLeg.SelfContained.
//
// Purpose: prove the Phase-3d dispatch selected AccelLeg.OpenBlasReal and
// that the accelerated matmul/dot results agree with the documented goldens.
// The same goldens run through the self-contained fallback in the offline
// conformance suite, so a PASS here pins dispatch + result equivalence across
// the two legs.

module numpy_real_leg_probe

use xiom.io;
use xiom.numpy;

fn v2(a: Int, b: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  s.push(b);
  return s;
}

fn v1(a: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  return s;
}

fn fd4(a: Float64, b: Float64, c: Float64, d: Float64) -> Vec[Float64] {
  var s = Vec[Float64].new();
  s.push(a); s.push(b); s.push(c); s.push(d);
  return s;
}

fn fd6(a: Float64, b: Float64, c: Float64, d: Float64, e: Float64, f: Float64) -> Vec[Float64] {
  var s = Vec[Float64].new();
  s.push(a); s.push(b); s.push(c); s.push(d); s.push(e); s.push(f);
  return s;
}

fn mk(data: &Vec[Float64], shape: &Vec[Int]) -> NDArray {
  match array_from_data(data, shape) {
    Ok(h) => { return h; },
    Err(_) => { return 0; },
  };
}

fn get2(h: NDArray, i: Int, j: Int) -> Float64 {
  var idx = v2(i, j);
  match array_get(&h, &idx) {
    Ok(v) => { return v; },
    Err(_) => { return 0.0; },
  };
}

fn get1(h: NDArray, i: Int) -> Float64 {
  var idx = Vec[Int].new();
  idx.push(i);
  match array_get(&h, &idx) {
    Ok(v) => { return v; },
    Err(_) => { return 0.0; },
  };
}

fn close(a: Float64, b: Float64) -> Bool {
  if a < b { return (b - a) < 0.000000001; }
  return (a - b) < 0.000000001;
}

fn main() -> Int {
  io.println("=== xiom.numpy OPTIONAL real-leg probe ===");

  let leg = acceleration_leg();
  if leg != AccelLeg.OpenBlasReal {
    io.println("[FAIL] acceleration_leg() != OpenBlasReal -- this artifact is not the real leg");
    io.println("       link --c-source ../xiom-openblas/bridge/openblas_real_marker.c --link libopenblas");
    return 1;
  }
  io.println("[PASS] acceleration_leg() == OpenBlasReal");

  var failures = 0;

  var a = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v2(2, 2));
  var b = mk(&fd4(5.0, 6.0, 7.0, 8.0), &v2(2, 2));
  match array_matmul(&a, &b) {
    Ok(h) => {
      if (close(get2(h, 0, 0), 19.0) && close(get2(h, 1, 1), 50.0)) {
        io.println("[PASS] real matmul 2x2 == [[19,22],[43,50]]");
      } else {
        io.println("[FAIL] real matmul 2x2 mismatch");
        failures = failures + 1;
      };
    },
    Err(_) => {
      io.println("[FAIL] real matmul 2x2 returned Err");
      failures = failures + 1;
    },
  };

  var c = mk(&fd4(1.5, 2.0, 3.0, 4.5), &v2(2, 2));
  var d = mk(&fd4(0.5, 1.0, 2.0, -1.0), &v2(2, 2));
  match array_matmul(&c, &d) {
    Ok(h) => {
      if (close(get2(h, 0, 0), 4.75) && close(get2(h, 0, 1), -0.5)
        && close(get2(h, 1, 0), 10.5) && close(get2(h, 1, 1), -1.5)) {
        io.println("[PASS] real matmul fractional golden matches offline fallback");
      } else {
        io.println("[FAIL] real matmul fractional golden mismatch");
        failures = failures + 1;
      };
    },
    Err(_) => {
      io.println("[FAIL] real matmul fractional returned Err");
      failures = failures + 1;
    },
  };

  var e = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v2(2, 3));
  var f = mk(&fd6(7.0, 8.0, 9.0, 10.0, 11.0, 12.0), &v2(3, 2));
  match array_matmul(&e, &f) {
    Ok(h) => {
      if (close(get2(h, 0, 0), 58.0) && close(get2(h, 1, 1), 154.0)) {
        io.println("[PASS] real matmul 2x3 * 3x2 == [[58,64],[139,154]]");
      } else {
        io.println("[FAIL] real matmul nonsquare mismatch");
        failures = failures + 1;
      };
    },
    Err(_) => {
      io.println("[FAIL] real matmul nonsquare returned Err");
      failures = failures + 1;
    },
  };

  var xv = mk(&fd4(1.5, 2.0, 2.0, -1.0), &v1(4));
  var y = mk(&fd4(2.0, -1.0, 1.5, 2.0), &v1(4));
  match array_dot(&xv, &y) {
    Ok(h) => {
      if (close(get1(h, 0), 2.0)) {
        io.println("[PASS] real dot == 2 (matches offline golden)");
      } else {
        io.println("[FAIL] real dot mismatch");
        failures = failures + 1;
      };
    },
    Err(_) => {
      io.println("[FAIL] real dot returned Err");
      failures = failures + 1;
    },
  };

  var m = mk(&fd4(4.0, 7.0, 2.0, 6.0), &v2(2, 2));
  match array_inv(&m) {
    Ok(h) => {
      if (close(get2(h, 0, 0), 0.6) && close(get2(h, 0, 1), -0.7)
        && close(get2(h, 1, 0), -0.2) && close(get2(h, 1, 1), 0.4)) {
        io.println("[PASS] inv golden (self-contained fallback on this leg)");
      } else {
        io.println("[FAIL] inv golden mismatch");
        failures = failures + 1;
      };
    },
    Err(_) => {
      io.println("[FAIL] inv golden returned Err");
      failures = failures + 1;
    },
  };

  if failures == 0 {
    io.println("ALL REAL-LEG PROBE CHECKS PASSED");
    return 0;
  }
  io.println("REAL-LEG PROBE FAILURES: " + "see above");
  return 1;
}
