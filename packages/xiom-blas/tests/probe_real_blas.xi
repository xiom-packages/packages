// probe_real_blas.xi -- SKIP-safe REAL OpenBLAS proof for xiom.blas.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// NOT part of scripts/port.ps1 (the conformance suite stays offline).
// This is the real-library leg: it reuses **xiom.openblas' own probe shim**
// (packages/xiom-openblas/tests/probe_openblas_shim.c, live in
// eco-v0.1.193) so the runtime availability rules are the canonical ones
// (XIOM_OPENBLAS_LIB override -> standard locations -> OS loader sonames;
// loaded-but-missing-exports is a loud FAIL). When no library is found the
// probe prints [SKIP] and exits 0, so it is safe on any machine.
//
// Present path (library found) proves, in order:
//   1. real `cblas_ddot` == 32 and real `cblas_dgemm` == [[19,22],[43,50]]
//      (the same goldens xiom.openblas' probe pins);
//   2. the SAFE LAYER computes the same values on the same inputs
//      (`vector_dot`, `matrix_multiply` via the xiom.blas -> xiom.openblas
//      seam), so the safe surface is end-to-end the openblas-backed one.
//
// Run (from the package directory; --c-source requires absolute paths):
//   xiom --run tests\probe_real_blas.xi ^
//       --c-source <repo>\packages\xiom-openblas\tests\probe_openblas_shim.c ^
//       --c-source <repo>\packages\xiom-openblas\bridge\openblas_bridge.c
//
// Optional explicit library override (canonical rule 1):
//   set XIOM_OPENBLAS_LIB=C:\somewhere\libopenblas.dll
//
// Exit codes: 0 = PASS or SKIP, 1 = FAIL (found but broken / wrong math).

module blas_real_probe

use xiom.io;
use xiom.blas;
use xiom.blas.linalg;

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

fn vec3f(a: Float64, b: Float64, c: Float64) -> Vec[Float64] {
  var v = Vec[Float64].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn vec4f(a: Float64, b: Float64, c: Float64, d: Float64) -> Vec[Float64] {
  var v = Vec[Float64].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

pub fn main() -> Int {
  io.println("=== xiom.blas real-library probe (safe layer over the xiom.openblas seam) ===");

  let found = unsafe { xiom_probe_open() };
  if found == 0 {
    io.println("[SKIP] no system OpenBLAS found (libopenblas.dll / openblas64_.dll / libopenblas.so)");
    io.println("[SKIP] searched: XIOM_OPENBLAS_LIB, standard locations, then OS loader search (PATH)");
    io.println("[SKIP] offline coverage: scripts\\port.ps1 -Package xiom.blas");
    return 0;
  }
  if found == 2 {
    io.println("[FAIL] a library loaded but does not export cblas_ddot + cblas_dgemm");
    io.println("[FAIL] path: " + found_lib_path());
    return 1;
  }

  io.println("[INFO] loaded: " + found_lib_path());

  // ---- 1. real cblas evidence over the canonical shim ---------------------
  var x = vec3f(1.0, 2.0, 3.0);
  var y = vec3f(4.0, 5.0, 6.0);
  let d = unsafe { xiom_probe_ddot(3, &x[0], &y[0]) };
  if d != 32.0 {
    io.println("[FAIL] real cblas_ddot([1,2,3],[4,5,6]) wrong (expected 32)");
    return 1;
  }
  io.println("[PASS] real cblas_ddot([1,2,3],[4,5,6]) == 32");

  var ra = vec4f(1.0, 2.0, 3.0, 4.0);
  var rb = vec4f(5.0, 6.0, 7.0, 8.0);
  var rc = vec4f(0.0, 0.0, 0.0, 0.0);
  let dc = unsafe { xiom_probe_dgemm(2, 2, 2, &ra[0], &rb[0], &mut rc[0]) };
  if dc != 0 {
    io.println("[FAIL] real cblas_dgemm rc wrong");
    return 1;
  }
  if rc[0] != 19.0 || rc[1] != 22.0 || rc[2] != 43.0 || rc[3] != 50.0 {
    io.println("[FAIL] real cblas_dgemm 2x2 product wrong");
    return 1;
  }
  io.println("[PASS] real cblas_dgemm 2x2 == [[19,22],[43,50]]");

  // ---- 2. the safe layer on the same inputs -------------------------------
  let dot_safe = vector_dot(&x, &y);
  if dot_safe != 32.0 {
    io.println("[FAIL] safe layer vector_dot != real cblas_ddot golden");
    return 1;
  }
  io.println("[PASS] safe layer vector_dot == 32 (same golden as real cblas_ddot)");

  var am = matrix_new(2, 2);
  am.data[0] = 1.0; am.data[1] = 2.0; am.data[2] = 3.0; am.data[3] = 4.0;
  var b = matrix_new(2, 2);
  b.data[0] = 5.0; b.data[1] = 6.0; b.data[2] = 7.0; b.data[3] = 8.0;
  match matrix_multiply(&am, &b) {
    Ok(c) => {
      if c.data[0] != 19.0 || c.data[1] != 22.0 || c.data[2] != 43.0 || c.data[3] != 50.0 {
        io.println("[FAIL] safe layer matrix_multiply wrong on the dgemm golden");
        return 1;
      };
      io.println("[PASS] safe layer matrix_multiply == [[19,22],[43,50]] (same golden as real cblas_dgemm)");
    }
    Err(e) => {
      io.println("[FAIL] safe layer matrix_multiply: " + e);
      return 1;
    }
  }

  io.println("[PASS] real OpenBLAS runtime exercised; safe layer matches on identical inputs");
  return 0;
}
