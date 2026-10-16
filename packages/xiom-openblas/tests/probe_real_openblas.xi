// probe_real_openblas.xi -- SKIP-safe REAL OpenBLAS proof (real leg).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// NOT part of scripts/port.ps1 (the conformance suite stays offline via
// bridge/openblas_bridge.c). This probe detects a system OpenBLAS at
// runtime and, when found, exercises the real library:
//   1. cblas_ddot([1,2,3], [4,5,6]) must return 32.0;
//   2. cblas_dgemm must compute [[1,2],[3,4]] * [[5,6],[7,8]]
//      = [[19,22],[43,50]] (row-major, alpha 1, beta 0).
// When no library is found the probe prints [SKIP] and exits 0, so it is
// safe to run on any machine; nothing is installed or modified.
//
// Detection (in tests/probe_openblas_shim.c): XIOM_OPENBLAS_LIB override,
// then standard install locations, then bare sonames
// (libopenblas.dll / openblas64_.dll / openblas.dll on Windows,
// libopenblas.so / libopenblas.so.0 on POSIX) through the OS loader search
// order, which covers PATH on Windows and ld.so + LD_LIBRARY_PATH on POSIX.
//
// Run (from the package directory; --c-source requires an absolute path
// because clang links from a scratch working directory):
//   xiom --run tests\probe_real_openblas.xi ^
//       --c-source E:\xiom-packages\packages\packages\xiom-openblas\tests\probe_openblas_shim.c
//
// Optional explicit library override (any path; useful to exercise the
// probe against a known build, e.g. a Julia or scipy wheel copy):
//   set XIOM_OPENBLAS_LIB=C:\somewhere\libopenblas.dll
//
// Exit codes: 0 = PASS or SKIP, 1 = FAIL (found but broken / wrong math).

module openblas_real_probe

use xiom.io;

extern "C" {
  fn xiom_probe_open() -> Int;
  fn xiom_probe_path(dst: *UInt8, cap: Int) -> Int;
  fn xiom_probe_ddot(n: Int, x: *Float64, y: *Float64) -> Float64;
  fn xiom_probe_dgemm(m: Int, k: Int, n: Int, a: *Float64, b: *Float64, c: *Float64) -> Int;
}

fn bytes_to_str(data: &Vec[UInt8]) -> Str {
  var fresh = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    fresh.push(data[i]);
    i = i + 1;
  }
  return Str::from_utf8(fresh);
}

fn found_lib_path() -> Str {
  var buf = Vec[UInt8].with_len(1024);
  let plen = unsafe { xiom_probe_path(buf.as_mut_ptr(), 1024) };
  if plen <= 0 { return ""; }
  var trimmed = Vec[UInt8].new();
  var i = 0;
  while i < plen {
    trimmed.push(buf[i]);
    i = i + 1;
  }
  return bytes_to_str(&trimmed);
}

pub fn main() -> Int {
  io.println("=== xiom.openblas real-library probe ===");

  let found = unsafe { xiom_probe_open() };
  if found == 0 {
    io.println("[SKIP] no system OpenBLAS found (libopenblas.dll / openblas64_.dll / openblas.so)");
    io.println("[SKIP] searched: XIOM_OPENBLAS_LIB, standard locations, then OS loader search (PATH)");
    io.println("[SKIP] offline coverage: scripts\\port.ps1 -Package xiom-openblas");
    return 0;
  }
  if found == 2 {
    io.println("[FAIL] a library loaded but does not export cblas_ddot + cblas_dgemm");
    io.println("[FAIL] path: " + found_lib_path());
    return 1;
  }

  io.println("[INFO] loaded: " + found_lib_path());

  var x = Vec[Float64].new();
  x.push(1.0);
  x.push(2.0);
  x.push(3.0);
  var y = Vec[Float64].new();
  y.push(4.0);
  y.push(5.0);
  y.push(6.0);
  let d = unsafe { xiom_probe_ddot(3, &x[0], &y[0]) };
  if d != 32.0 {
    io.println("[FAIL] real cblas_ddot([1,2,3],[4,5,6]) = " + str_of(d) + " (expected 32)");
    return 1;
  }
  io.println("[PASS] real cblas_ddot == 32");

  // A = [[1,2],[3,4]], B = [[5,6],[7,8]] row-major; C must be [[19,22],[43,50]].
  var a = Vec[Float64].new();
  a.push(1.0);
  a.push(2.0);
  a.push(3.0);
  a.push(4.0);
  var b = Vec[Float64].new();
  b.push(5.0);
  b.push(6.0);
  b.push(7.0);
  b.push(8.0);
  var c = Vec[Float64].new();
  c.push(0.0);
  c.push(0.0);
  c.push(0.0);
  c.push(0.0);
  let rc = unsafe { xiom_probe_dgemm(2, 2, 2, &a[0], &b[0], &mut c[0]) };
  if rc != 0 {
    io.println("[FAIL] xiom_probe_dgemm rc = " + str_of_int(rc));
    return 1;
  }
  if c[0] != 19.0 || c[1] != 22.0 || c[2] != 43.0 || c[3] != 50.0 {
    io.println("[FAIL] real cblas_dgemm result: [" + str_of(c[0]) + ", " + str_of(c[1]) + ", " + str_of(c[2]) + ", " + str_of(c[3]) + "] (expected [19, 22, 43, 50])");
    return 1;
  }
  io.println("[PASS] real cblas_dgemm 2x2 product == [[19,22],[43,50]]");
  io.println("[PASS] real OpenBLAS exercised (ddot + dgemm)");
  return 0;
}

// Floating point to display string (one decimal minimum, exact for the
// small integers used here).
fn str_of(v: Float64) -> Str {
  var n = v as Int;
  return str_of_int(n);
}

// Int to decimal string (local; avoids extra stdlib imports in the probe).
fn str_of_int(n0: Int) -> Str {
  var n = n0;
  var neg = false;
  if n < 0 { neg = true; n = -n; }
  if n == 0 { return "0"; }
  var out = "";
  while n > 0 {
    let d = n % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    n = n / 10;
  }
  if neg { return "-" + out; }
  return out;
}
