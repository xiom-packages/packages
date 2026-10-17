// XIOM -- xiom.cublas conformance suite (0.1.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 21 checks with a live runtime, 5 on a host without one (the runtime
// section collapses to one classified SKIP line):
//   SECTION A (4): always-run -- deterministic SKIP classification (bogus
//     directory), status-name mapping, invalid-handle classification, and
//     the pinned ABI constants.
//   SECTION B (17): cuBLAS live -- load, handle create/version/setStream,
//     device-buffer helpers, sgemm/dgemm, saxpy, sdot, sscal, snrm2,
//     sgemv/dgemv (real numerical results), destroy, unload.
//
// Runtime: the user's own cuBLAS installation -- `XIOM_CUBLAS_DIR` (e.g.
// the pip wheel's nvidia/cublas/bin) or the OS module search.  Nothing is
// downloaded or shipped.  Run:
//   scripts/port.ps1 -Package xiom.cublas -TimeoutSec 300

module cublas_conformance

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.cublas;

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

fn f32s(v: Float32) -> Str {
  if v < 0.0 as Float32 { return "-" + f32s(0.0 as Float32 - v); }
  let whole = v as Int;
  let frac = ((v - whole as Float32) * 1000.0 as Float32) as Int;
  return i2s(whole) + "." + i2s(frac);
}

fn f64s(v: Float64) -> Str {
  if v < 0.0 { return "-" + f64s(0.0 - v); }
  let whole = v as Int;
  let frac = ((v - whole as Float64) * 1000000.0) as Int;
  return i2s(whole) + "." + i2s(frac);
}

fn approx32(a: Float32, b: Float32, tol: Float32) -> Bool {
  var d = a - b;
  if d < 0.0 as Float32 { d = 0.0 as Float32 - d; }
  return d <= tol;
}

fn approx64(a: Float64, b: Float64, tol: Float64) -> Bool {
  var d = a - b;
  if d < 0.0 { d = 0.0 - d; }
  return d <= tol;
}

fn expect_unit(r: Result[Unit, CublasError], name: Str) -> Int {
  if r.is_ok { return report(true, name); }
  return report(false, name + ": " + r.error.message);
}

fn f32x4(a: Float32, b: Float32, c: Float32, d: Float32) -> Vec[Float32] {
  var v = Vec[Float32].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn f64x4(a: Float64, b: Float64, c: Float64, d: Float64) -> Vec[Float64] {
  var v = Vec[Float64].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn f32x3(a: Float32, b: Float32, c: Float32) -> Vec[Float32] {
  var v = Vec[Float32].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn f64x3(a: Float64, b: Float64, c: Float64) -> Vec[Float64] {
  var v = Vec[Float64].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn f32x6(a: Float32, b: Float32, c: Float32, d: Float32, e: Float32,
          f: Float32) -> Vec[Float32] {
  var v = Vec[Float32].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

fn f64x6(a: Float64, b: Float64, c: Float64, d: Float64, e: Float64,
          f: Float64) -> Vec[Float64] {
  var v = Vec[Float64].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

// =========================================================================
// SECTION A -- always-run (no runtime needed)
// =========================================================================

fn test_a1_skip_path() -> Int {
  let r = cublas_load_from("xiom-absent-cublas-probe-xyz");
  var ok = false;
  if r.is_err {
    ok = r.error.kind == CUBLAS_LOAD_ABSENT;
  }
  return report(ok, "skip-path: absent directory classified as CUBLAS_LOAD_ABSENT (SKIP)");
}

fn test_a2_status_names() -> Int {
  let ok = str_compare(cublas_status_name(0), "CUBLAS_STATUS_SUCCESS") == 0
    && str_compare(cublas_status_name(7), "CUBLAS_STATUS_INVALID_VALUE") == 0
    && str_compare(cublas_status_name(15), "CUBLAS_STATUS_NOT_SUPPORTED") == 0;
  return report(ok, "status map: 0/7/15 have the pinned cuBLAS names");
}

fn test_a3_invalid_handle() -> Int {
  let fake = CublasLibrary{ h: 12345 };
  let r = cublas_create(&fake);
  var ok = false;
  if r.is_err {
    ok = r.error.kind == CUBLAS_LOAD_RUNTIME;
  }
  return report(ok, "typed error: create on a stale module handle is CUBLAS_LOAD_RUNTIME");
}

fn test_a4_constants() -> Int {
  let ok = CUBLAS_OP_N == 0 && CUBLAS_OP_T == 1 && CUBLAS_OP_C == 2
    && CUBLAS_STATUS_SUCCESS == 0
    && CUBLAS_STATUS_NOT_INITIALIZED == 1
    && CUBLAS_STATUS_INVALID_VALUE == 7
    && CUBLAS_STATUS_NOT_SUPPORTED == 15;
  return report(ok, "ABI constants: CUBLAS_OP_* and status values match the pin");
}

// =========================================================================
// SECTION B -- live cuBLAS (or one classified SKIP)
// =========================================================================

fn test_b_live() -> Int {
  let lr = cublas_load();
  if lr.is_err {
    if lr.error.kind == CUBLAS_LOAD_ABSENT || lr.error.kind == CUBLAS_LOAD_NO_DEVICE {
      return report(true, "live: SKIP -- " + lr.error.message);
    }
    return report(false, "live: load failed -- " + lr.error.message);
  }
  let lib = lr.value;
  var failed = 0;
  failed = failed + report(true, "live: cuBLAS runtime loaded (XIOM_CUBLAS_DIR / OS search)");

  let hr = cublas_create(&lib);
  if hr.is_err {
    failed = failed + report(false, "create: " + hr.error.message);
    let _ = cublas_unload(&lib);
    return failed;
  }
  let h = hr.value;
  failed = failed + report(true, "create: handle created (cublasCreate_v2)");

  let vr = cublas_get_version(&h);
  if vr.is_ok {
    failed = failed + report(vr.value > 0,
      "version: " + i2s(vr.value) + " (cublasGetVersion_v2)");
  } else {
    failed = failed + report(false, "version: " + vr.error.message);
  }

  failed = failed + expect_unit(cublas_set_stream(&h, 0),
    "setStream: default stream bound");

  // ---- single precision buffers ----
  let ar = cublas_buffer_alloc(16);
  let br = cublas_buffer_alloc(16);
  let cr = cublas_buffer_alloc(16);
  let xr = cublas_buffer_alloc(12);
  let yr = cublas_buffer_alloc(12);
  let gr = cublas_buffer_alloc(24);
  let zr = cublas_buffer_alloc(8);
  if ar.is_err || br.is_err || cr.is_err || xr.is_err || yr.is_err || gr.is_err
      || zr.is_err {
    failed = failed + report(false, "device buffers: allocation failed");
    let _ = cublas_destroy(&h);
    let _ = cublas_unload(&lib);
    return failed;
  }
  let da = ar.value;
  let db = br.value;
  let dc = cr.value;
  let dx = xr.value;
  let dy = yr.value;
  let dg = gr.value;
  let dz = zr.value;
  failed = failed + report(true, "device buffers: 7 allocations (cuMemAlloc_v2)");

  var a32 = f32x4(1.0 as Float32, 2.0 as Float32, 3.0 as Float32, 4.0 as Float32);
  var b32 = f32x4(5.0 as Float32, 6.0 as Float32, 7.0 as Float32, 8.0 as Float32);
  failed = failed + expect_unit(cublas_buffer_upload_f32(&da, &a32), "upload: A (f32)");
  failed = failed + expect_unit(cublas_buffer_upload_f32(&db, &b32), "upload: B (f32)");

  failed = failed + expect_unit(
    cublas_sgemm(&h, CUBLAS_OP_N, CUBLAS_OP_N, 2, 2, 2, 1.0 as Float32,
                 &db, 2, &da, 2, 0.0 as Float32, &dc, 2),
    "sgemm: 2x2 C = A*B issued");

  var c32 = Vec[Float32].with_len(4);
  failed = failed + expect_unit(cublas_buffer_download_f32(&dc, &mut c32), "download: C (f32)");
  let sgemm_ok = approx32(c32[0], 19.0 as Float32, 0.001 as Float32)
    && approx32(c32[1], 22.0 as Float32, 0.001 as Float32)
    && approx32(c32[2], 43.0 as Float32, 0.001 as Float32)
    && approx32(c32[3], 50.0 as Float32, 0.001 as Float32);
  failed = failed + report(sgemm_ok,
    "sgemm: row-major result [19,22,43,50], got [" + f32s(c32[0]) + ","
      + f32s(c32[1]) + "," + f32s(c32[2]) + "," + f32s(c32[3]) + "]");

  var x32 = f32x3(1.0 as Float32, 2.0 as Float32, 3.0 as Float32);
  var y32 = f32x3(10.0 as Float32, 20.0 as Float32, 30.0 as Float32);
  failed = failed + expect_unit(cublas_buffer_upload_f32(&dx, &x32), "upload: x (f32)");
  failed = failed + expect_unit(cublas_buffer_upload_f32(&dy, &y32), "upload: y (f32)");
  failed = failed + expect_unit(
    cublas_saxpy(&h, 3, 2.0 as Float32, &dx, 1, &dy, 1), "saxpy: y = 2*x + y issued");

  var y32o = Vec[Float32].with_len(3);
  failed = failed + expect_unit(cublas_buffer_download_f32(&dy, &mut y32o), "download: y (f32)");
  let saxpy_ok = approx32(y32o[0], 12.0 as Float32, 0.001 as Float32)
    && approx32(y32o[1], 24.0 as Float32, 0.001 as Float32)
    && approx32(y32o[2], 36.0 as Float32, 0.001 as Float32);
  failed = failed + report(saxpy_ok,
    "saxpy: result [12,24,36], got [" + f32s(y32o[0]) + "," + f32s(y32o[1])
      + "," + f32s(y32o[2]) + "]");

  let dr = cublas_sdot(&h, 3, &dx, 1, &dy, 1);
  if dr.is_ok {
    failed = failed + report(approx32(dr.value, 168.0 as Float32, 0.001 as Float32),
      "sdot: x.y = 168, got " + f32s(dr.value));
  } else {
    failed = failed + report(false, "sdot: " + dr.error.message);
  }

  failed = failed + expect_unit(cublas_sscal(&h, 3, 3.0 as Float32, &dx, 1),
    "sscal: x = 3*x issued");
  var x32o = Vec[Float32].with_len(3);
  failed = failed + expect_unit(cublas_buffer_download_f32(&dx, &mut x32o), "download: x (f32)");
  let sscal_ok = approx32(x32o[0], 3.0 as Float32, 0.001 as Float32)
    && approx32(x32o[1], 6.0 as Float32, 0.001 as Float32)
    && approx32(x32o[2], 9.0 as Float32, 0.001 as Float32);
  failed = failed + report(sscal_ok, "sscal: result [3,6,9]");

  var n32 = f32x3(3.0 as Float32, 4.0 as Float32, 0.0 as Float32);
  failed = failed + expect_unit(cublas_buffer_upload_f32(&dx, &n32), "upload: norm input (f32)");
  let nr = cublas_snrm2(&h, 2, &dx, 1);
  if nr.is_ok {
    failed = failed + report(approx32(nr.value, 5.0 as Float32, 0.001 as Float32),
      "snrm2: ||[3,4]|| = 5, got " + f32s(nr.value));
  } else {
    failed = failed + report(false, "snrm2: " + nr.error.message);
  }

  var g32 = f32x6(1.0 as Float32, 2.0 as Float32, 3.0 as Float32,
                  4.0 as Float32, 5.0 as Float32, 6.0 as Float32);
  var o32 = f32x3(1.0 as Float32, 1.0 as Float32, 1.0 as Float32);
  var z32 = Vec[Float32].with_len(2);
  failed = failed + expect_unit(cublas_buffer_upload_f32(&dg, &g32), "upload: gemv A (f32)");
  failed = failed + expect_unit(cublas_buffer_upload_f32(&dx, &o32), "upload: gemv x (f32)");
  failed = failed + expect_unit(
    cublas_sgemv(&h, CUBLAS_OP_T, 3, 2, 1.0 as Float32, &dg, 3, &dx, 1,
                 0.0 as Float32, &dz, 1),
    "sgemv: 2x3 row-major A * ones issued");
  failed = failed + expect_unit(cublas_buffer_download_f32(&dz, &mut z32), "download: gemv y (f32)");
  let sgemv_ok = approx32(z32[0], 6.0 as Float32, 0.001 as Float32)
    && approx32(z32[1], 15.0 as Float32, 0.001 as Float32);
  failed = failed + report(sgemv_ok,
    "sgemv: result [6,15], got [" + f32s(z32[0]) + "," + f32s(z32[1]) + "]");

  // ---- double precision ----
  let adr = cublas_buffer_alloc(32);
  let bdr = cublas_buffer_alloc(32);
  let cdr = cublas_buffer_alloc(32);
  let gdr = cublas_buffer_alloc(48);
  let zdr = cublas_buffer_alloc(16);
  let xdr = cublas_buffer_alloc(24);
  let ydr = cublas_buffer_alloc(24);
  if adr.is_err || bdr.is_err || cdr.is_err || gdr.is_err || zdr.is_err
      || xdr.is_err || ydr.is_err {
    failed = failed + report(false, "device buffers: f64 allocation failed");
    let _ = cublas_destroy(&h);
    let _ = cublas_unload(&lib);
    return failed;
  }
  let dda = adr.value;
  let ddb = bdr.value;
  let ddc = cdr.value;
  let ddg = gdr.value;
  let ddz = zdr.value;
  let ddx = xdr.value;
  let ddy = ydr.value;

  var a64 = f64x4(1.0, 2.0, 3.0, 4.0);
  var b64 = f64x4(5.0, 6.0, 7.0, 8.0);
  failed = failed + expect_unit(cublas_buffer_upload_f64(&dda, &a64), "upload: A (f64)");
  failed = failed + expect_unit(cublas_buffer_upload_f64(&ddb, &b64), "upload: B (f64)");
  failed = failed + expect_unit(
    cublas_dgemm(&h, CUBLAS_OP_N, CUBLAS_OP_N, 2, 2, 2, 1.0, &ddb, 2, &dda, 2,
                 0.0, &ddc, 2),
    "dgemm: 2x2 C = A*B issued");
  var c64 = Vec[Float64].with_len(4);
  failed = failed + expect_unit(cublas_buffer_download_f64(&ddc, &mut c64), "download: C (f64)");
  let dgemm_ok = approx64(c64[0], 19.0, 1e-9) && approx64(c64[1], 22.0, 1e-9)
    && approx64(c64[2], 43.0, 1e-9) && approx64(c64[3], 50.0, 1e-9);
  failed = failed + report(dgemm_ok,
    "dgemm: result [19,22,43,50], got [" + f64s(c64[0]) + "," + f64s(c64[1])
      + "," + f64s(c64[2]) + "," + f64s(c64[3]) + "]");

  var x64 = f64x3(1.0, 2.0, 3.0);
  var y64 = f64x3(10.0, 20.0, 30.0);
  failed = failed + expect_unit(cublas_buffer_upload_f64(&ddx, &x64), "upload: x (f64)");
  failed = failed + expect_unit(cublas_buffer_upload_f64(&ddy, &y64), "upload: y (f64)");
  failed = failed + expect_unit(
    cublas_daxpy(&h, 3, 2.0, &ddx, 1, &ddy, 1), "daxpy: y = 2*x + y issued");
  let ddr = cublas_ddot(&h, 3, &ddx, 1, &ddy, 1);
  if ddr.is_ok {
    failed = failed + report(approx64(ddr.value, 168.0, 1e-9),
      "ddot: x.y = 168, got " + f64s(ddr.value));
  } else {
    failed = failed + report(false, "ddot: " + ddr.error.message);
  }
  failed = failed + expect_unit(cublas_dscal(&h, 3, 0.5, &ddx, 1),
    "dscal: x = 0.5*x issued");
  let dnr = cublas_dnrm2(&h, 3, &ddx, 1);
  if dnr.is_ok {
    failed = failed + report(dnr.value > 0.0, "dnrm2: positive norm " + f64s(dnr.value));
  } else {
    failed = failed + report(false, "dnrm2: " + dnr.error.message);
  }

  var g64 = f64x6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0);
  var o64 = f64x3(1.0, 1.0, 1.0);
  var z64 = Vec[Float64].with_len(2);
  failed = failed + expect_unit(cublas_buffer_upload_f64(&ddg, &g64), "upload: gemv A (f64)");
  failed = failed + expect_unit(cublas_buffer_upload_f64(&ddx, &o64), "upload: gemv x (f64)");
  failed = failed + expect_unit(
    cublas_dgemv(&h, CUBLAS_OP_T, 3, 2, 1.0, &ddg, 3, &ddx, 1, 0.0, &ddz, 1),
    "dgemv: 2x3 row-major A * ones issued");
  failed = failed + expect_unit(cublas_buffer_download_f64(&ddz, &mut z64), "download: gemv y (f64)");
  let dgemv_ok = approx64(z64[0], 6.0, 1e-9) && approx64(z64[1], 15.0, 1e-9);
  failed = failed + report(dgemv_ok,
    "dgemv: result [6,15], got [" + f64s(z64[0]) + "," + f64s(z64[1]) + "]");

  // ---- teardown ----
  let rr = cublas_destroy(&h);
  if rr.is_ok {
    failed = failed + report(true, "destroy: handle released (cublasDestroy_v2)");
  } else {
    failed = failed + report(false, "destroy: " + rr.error.message);
  }

  failed = failed + expect_unit(cublas_buffer_free(&da), "free: A (f32)");
  failed = failed + expect_unit(cublas_buffer_free(&db), "free: B (f32)");
  failed = failed + expect_unit(cublas_buffer_free(&dc), "free: C (f32)");
  failed = failed + expect_unit(cublas_buffer_free(&dx), "free: x (f32)");
  failed = failed + expect_unit(cublas_buffer_free(&dy), "free: y (f32)");
  failed = failed + expect_unit(cublas_buffer_free(&dg), "free: gemv A (f32)");
  failed = failed + expect_unit(cublas_buffer_free(&dz), "free: gemv y (f32)");
  failed = failed + expect_unit(cublas_buffer_free(&dda), "free: A (f64)");
  failed = failed + expect_unit(cublas_buffer_free(&ddb), "free: B (f64)");
  failed = failed + expect_unit(cublas_buffer_free(&ddc), "free: C (f64)");
  failed = failed + expect_unit(cublas_buffer_free(&ddg), "free: gemv A (f64)");
  failed = failed + expect_unit(cublas_buffer_free(&ddz), "free: gemv y (f64)");
  failed = failed + expect_unit(cublas_buffer_free(&ddx), "free: x (f64)");
  failed = failed + expect_unit(cublas_buffer_free(&ddy), "free: y (f64)");

  failed = failed + expect_unit(cublas_unload(&lib), "unload: module + context released");
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.cublas conformance tests (0.1.0, loader-only) ===");
  io.flush_stdout();
  var failed = 0;
  failed = failed + test_a1_skip_path();
  failed = failed + test_a2_status_names();
  failed = failed + test_a3_invalid_handle();
  failed = failed + test_a4_constants();
  failed = failed + test_b_live();
  if failed == 0 {
    io.println("xiom.cublas: all tests passed");
  } else {
    io.println("xiom.cublas: tests failed");
  }
  return failed;
}
