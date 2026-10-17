// XIOM -- xiom.cusparse conformance suite (0.1.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 25 checks with a live runtime, 5 on a host without one (the runtime
// section collapses to one classified SKIP line):
//   SECTION A (4): deterministic SKIP classification (bogus directory),
//     status-name mapping, stale-module-handle classification, and the
//     pinned ABI constants.
//   SECTION B (21): cuSPARSE live -- load, handle create/version/setStream,
//     legacy mat descriptor create/set/destroy, CSR + dense descriptors,
//     SpMV (f64 and f32) and SpMM (f64) with real numerical results,
//     buffer-size queries, descriptor/handle teardown, unload.
//
// Runtime: the user's own cuSPARSE installation -- `XIOM_CUSPARSE_DIR`
// (e.g. the pip wheel's nvidia/cusparse/bin) or the OS module search.
// Nothing is downloaded or shipped.  Run:
//   scripts/port.ps1 -Package xiom.cusparse -TimeoutSec 300

module cusparse_conformance

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.cusparse;

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

fn expect_unit(r: Result[Unit, CusparseError], name: Str) -> Int {
  if r.is_ok { return report(true, name); }
  return report(false, name + ": " + r.error.message);
}

// =========================================================================
// SECTION A -- always-run (no runtime needed)
// =========================================================================

fn test_a1_skip_path() -> Int {
  let r = cusparse_load_from("xiom-absent-cusparse-probe-xyz");
  var ok = false;
  if r.is_err {
    ok = r.error.kind == CUSPARSE_LOAD_ABSENT;
  }
  return report(ok, "skip-path: absent directory classified as CUSPARSE_LOAD_ABSENT (SKIP)");
}

fn test_a2_status_names() -> Int {
  let ok = str_compare(cusparse_status_name(0), "CUSPARSE_STATUS_SUCCESS") == 0
    && str_compare(cusparse_status_name(8), "CUSPARSE_STATUS_MATRIX_TYPE_NOT_SUPPORTED") == 0
    && str_compare(cusparse_status_name(11), "CUSPARSE_STATUS_INSUFFICIENT_RESOURCES") == 0;
  return report(ok, "status map: 0/8/11 have the pinned cuSPARSE names");
}

fn test_a3_invalid_module() -> Int {
  let fake = CusparseLibrary{ h: 12345 };
  let r = cusparse_create(&fake);
  var ok = false;
  if r.is_err {
    ok = r.error.kind == CUSPARSE_LOAD_RUNTIME;
  }
  return report(ok, "typed error: handle on a stale module is CUSPARSE_LOAD_RUNTIME");
}

fn test_a4_constants() -> Int {
  let ok = CUSPARSE_INDEX_32I == 2 && CUSPARSE_INDEX_64I == 3
    && CUSPARSE_INDEX_BASE_ZERO == 0 && CUSPARSE_MATRIX_TYPE_GENERAL == 0
    && CUSPARSE_ORDER_COL == 1 && CUSPARSE_ORDER_ROW == 2
    && CUSPARSE_SPMV_ALG_DEFAULT == 0 && CUSPARSE_SPMM_CSR_ALG1 == 4
    && CUDA_R_32F == 0 && CUDA_R_64F == 1;
  return report(ok, "ABI constants: index/order/alg/data-type values match the pin");
}

// =========================================================================
// SECTION B -- live cuSPARSE (or one classified SKIP)
// =========================================================================

fn test_b_live() -> Int {
  let lr = cusparse_load();
  if lr.is_err {
    if lr.error.kind == CUSPARSE_LOAD_ABSENT || lr.error.kind == CUSPARSE_LOAD_NO_DEVICE {
      return report(true, "live: SKIP -- " + lr.error.message);
    }
    return report(false, "live: load failed -- " + lr.error.message);
  }
  let lib = lr.value;
  var failed = 0;
  failed = failed + report(true, "live: cuSPARSE runtime loaded (XIOM_CUSPARSE_DIR / OS search)");

  let hr = cusparse_create(&lib);
  if hr.is_err {
    failed = failed + report(false, "create: " + hr.error.message);
    let _ = cusparse_unload(&lib);
    return failed;
  }
  let h = hr.value;
  failed = failed + report(true, "create: handle created (cusparseCreate)");

  let vr = cusparse_get_version(&h);
  if vr.is_ok {
    failed = failed + report(vr.value > 0,
      "version: " + i2s(vr.value) + " (cusparseGetVersion)");
  } else {
    failed = failed + report(false, "version: " + vr.error.message);
  }
  failed = failed + expect_unit(cusparse_set_stream(&h, 0),
    "setStream: default stream bound");

  // ---- legacy matrix descriptor ----
  let md = cusparse_create_mat_descr();
  if md.is_err {
    failed = failed + report(false, "matDescr: " + md.error.message);
    let _ = cusparse_destroy(&h);
    let _ = cusparse_unload(&lib);
    return failed;
  }
  let descr = md.value;
  failed = failed + report(true, "matDescr: legacy descriptor created");
  failed = failed + expect_unit(cusparse_set_mat_type(&descr, CUSPARSE_MATRIX_TYPE_GENERAL),
    "matDescr: GENERAL matrix type set");
  failed = failed + expect_unit(cusparse_set_mat_index_base(&descr, CUSPARSE_INDEX_BASE_ZERO),
    "matDescr: zero index base set");
  failed = failed + expect_unit(cusparse_destroy_mat_descr(&descr),
    "matDescr: descriptor destroyed");

  // ---- device buffers (A = [[2,0,1],[0,3,0],[1,0,4]] in CSR) ----
  let ro = cusparse_buffer_alloc(16);   // 4 int32: 0,2,3,5
  let ci = cusparse_buffer_alloc(20);   // 5 int32: 0,2,1,0,2
  let va = cusparse_buffer_alloc(40);   // 5 f64: 2,1,3,1,4
  let vx = cusparse_buffer_alloc(24);   // 3 f64
  let vy = cusparse_buffer_alloc(24);   // 3 f64
  let vb = cusparse_buffer_alloc(48);   // 3x2 f64 row-major
  let vc = cusparse_buffer_alloc(48);   // 3x2 f64 row-major
  if ro.is_err || ci.is_err || va.is_err || vx.is_err || vy.is_err
      || vb.is_err || vc.is_err {
    failed = failed + report(false, "device buffers: allocation failed");
    let _ = cusparse_destroy(&h);
    let _ = cusparse_unload(&lib);
    return failed;
  }
  let dro = ro.value;
  let dci = ci.value;
  let dva = va.value;
  let dvx = vx.value;
  let dvy = vy.value;
  let dvb = vb.value;
  let dvc = vc.value;
  failed = failed + report(true, "device buffers: 7 allocations (cuMemAlloc_v2)");

  var row_offsets = Vec[Int32].with_len(4);
  row_offsets[0] = 0 as Int32;
  row_offsets[1] = 2 as Int32;
  row_offsets[2] = 3 as Int32;
  row_offsets[3] = 5 as Int32;
  var col_indices = Vec[Int32].with_len(5);
  col_indices[0] = 0 as Int32;
  col_indices[1] = 2 as Int32;
  col_indices[2] = 1 as Int32;
  col_indices[3] = 0 as Int32;
  col_indices[4] = 2 as Int32;
  var a_vals = Vec[Float64].with_len(5);
  a_vals[0] = 2.0;
  a_vals[1] = 1.0;
  a_vals[2] = 3.0;
  a_vals[3] = 1.0;
  a_vals[4] = 4.0;
  var x_vals = Vec[Float64].with_len(3);
  x_vals[0] = 1.0;
  x_vals[1] = 2.0;
  x_vals[2] = 3.0;
  var y_vals = Vec[Float64].with_len(3);
  y_vals[0] = 0.0;
  y_vals[1] = 0.0;
  y_vals[2] = 0.0;
  var b_vals = Vec[Float64].with_len(6);
  b_vals[0] = 1.0;
  b_vals[1] = 0.0;
  b_vals[2] = 0.0;
  b_vals[3] = 1.0;
  b_vals[4] = 1.0;
  b_vals[5] = 1.0;
  var c_vals = Vec[Float64].with_len(6);
  var zi = 0;
  while zi < 6 {
    c_vals[zi] = 0.0;
    zi = zi + 1;
  }

  failed = failed + expect_unit(cusparse_buffer_upload_i32(&dro, &row_offsets),
    "upload: CSR row offsets (i32)");
  failed = failed + expect_unit(cusparse_buffer_upload_i32(&dci, &col_indices),
    "upload: CSR column indices (i32)");
  failed = failed + expect_unit(cusparse_buffer_upload_f64(&dva, &a_vals),
    "upload: CSR values (f64)");
  failed = failed + expect_unit(cusparse_buffer_upload_f64(&dvx, &x_vals),
    "upload: x (f64)");
  failed = failed + expect_unit(cusparse_buffer_upload_f64(&dvy, &y_vals),
    "upload: y (f64)");
  failed = failed + expect_unit(cusparse_buffer_upload_f64(&dvb, &b_vals),
    "upload: B (f64, row-major 3x2)");
  failed = failed + expect_unit(cusparse_buffer_upload_f64(&dvc, &c_vals),
    "upload: C (f64, zeroed 3x2)");

  // ---- CSR + dense-vector descriptors (f64) ----
  let sr = cusparse_create_csr(&h, 3, 3, 5, &dro, &dci, &dva,
                               CUSPARSE_INDEX_32I, CUSPARSE_INDEX_32I,
                               CUSPARSE_INDEX_BASE_ZERO, CUDA_R_64F);
  if sr.is_err {
    failed = failed + report(false, "createCsr: " + sr.error.message);
    let _ = cusparse_destroy(&h);
    let _ = cusparse_unload(&lib);
    return failed;
  }
  let sp = sr.value;
  failed = failed + report(true, "createCsr: 3x3 / 5 nnz descriptor created");

  let xr = cusparse_create_dnvec(&h, 3, &dvx, CUDA_R_64F);
  let yr = cusparse_create_dnvec(&h, 3, &dvy, CUDA_R_64F);
  if xr.is_err || yr.is_err {
    failed = failed + report(false, "createDnVec: f64 descriptors failed");
    let _ = cusparse_destroy_spmat(&sp);
    let _ = cusparse_destroy(&h);
    let _ = cusparse_unload(&lib);
    return failed;
  }
  let vec_x = xr.value;
  let vec_y = yr.value;
  failed = failed + report(true, "createDnVec: x and y descriptors created");

  // ---- SpMV (f64) ----
  let sbr = cusparse_spmv_buffer_size(&h, CUSPARSE_OPERATION_NON_TRANSPOSE, 1.0,
                                      &sp, &vec_x, 0.0, &vec_y, CUDA_R_64F,
                                      CUSPARSE_SPMV_ALG_DEFAULT);
  if sbr.is_err {
    failed = failed + report(false, "spmv bufferSize: " + sbr.error.message);
  } else {
    failed = failed + report(sbr.value >= 0,
      "spmv bufferSize: " + i2s(sbr.value) + " bytes");
    var sbuf = CusparseDevicePtr{ p: 0 };
    if sbr.value > 0 {
      let ab = cusparse_buffer_alloc(sbr.value);
      if ab.is_ok { sbuf = ab.value; }
    }
    let ex = cusparse_spmv(&h, CUSPARSE_OPERATION_NON_TRANSPOSE, 1.0, &sp,
                           &vec_x, 0.0, &vec_y, CUDA_R_64F,
                           CUSPARSE_SPMV_ALG_DEFAULT, &sbuf);
    if ex.is_err {
      failed = failed + report(false, "spmv: " + ex.error.message);
    } else {
      var got = Vec[Float64].with_len(3);
      let dl = cusparse_buffer_download_f64(&dvy, &mut got);
      if dl.is_err {
        failed = failed + report(false, "spmv download: " + dl.error.message);
      } else {
        let ok = approx64(got[0], 5.0, 1e-9) && approx64(got[1], 6.0, 1e-9)
          && approx64(got[2], 13.0, 1e-9);
        failed = failed + report(ok,
          "spmv: A*x = [5,6,13], got [" + f64s(got[0]) + "," + f64s(got[1])
            + "," + f64s(got[2]) + "]");
      }
    }
    if sbuf.p != 0 {
      let fb = cusparse_buffer_free(&sbuf);
      failed = failed + expect_unit(fb, "spmv: external buffer released");
    }
  }

  // ---- SpMV (f32) ----
  let v32 = cusparse_buffer_alloc(20);
  let x32 = cusparse_buffer_alloc(12);
  let y32 = cusparse_buffer_alloc(12);
  if v32.is_err || x32.is_err || y32.is_err {
    failed = failed + report(false, "device buffers: f32 allocation failed");
  } else {
    let dv32 = v32.value;
    let dx32 = x32.value;
    let dy32 = y32.value;
    var av32 = Vec[Float32].with_len(5);
    av32[0] = 2.0 as Float32;
    av32[1] = 1.0 as Float32;
    av32[2] = 3.0 as Float32;
    av32[3] = 1.0 as Float32;
    av32[4] = 4.0 as Float32;
    var xv32 = Vec[Float32].with_len(3);
    xv32[0] = 1.0 as Float32;
    xv32[1] = 2.0 as Float32;
    xv32[2] = 3.0 as Float32;
    var yv32 = Vec[Float32].with_len(3);
    yv32[0] = 0.0 as Float32;
    yv32[1] = 0.0 as Float32;
    yv32[2] = 0.0 as Float32;
    failed = failed + expect_unit(cusparse_buffer_upload_f32(&dv32, &av32),
      "upload: CSR values (f32)");
    failed = failed + expect_unit(cusparse_buffer_upload_f32(&dx32, &xv32),
      "upload: x (f32)");
    failed = failed + expect_unit(cusparse_buffer_upload_f32(&dy32, &yv32),
      "upload: y (f32)");

    let s32 = cusparse_create_csr(&h, 3, 3, 5, &dro, &dci, &dv32,
                                  CUSPARSE_INDEX_32I, CUSPARSE_INDEX_32I,
                                  CUSPARSE_INDEX_BASE_ZERO, CUDA_R_32F);
    let x32r = cusparse_create_dnvec(&h, 3, &dx32, CUDA_R_32F);
    let y32r = cusparse_create_dnvec(&h, 3, &dy32, CUDA_R_32F);
    if s32.is_err || x32r.is_err || y32r.is_err {
      failed = failed + report(false, "f32 descriptors: creation failed");
    } else {
      let sp32 = s32.value;
      let vx32 = x32r.value;
      let vy32 = y32r.value;
      let sb32 = cusparse_spmv_buffer_size(&h, CUSPARSE_OPERATION_NON_TRANSPOSE,
                                           1.0, &sp32, &vx32, 0.0, &vy32,
                                           CUDA_R_32F, CUSPARSE_SPMV_ALG_DEFAULT);
      if sb32.is_err {
        failed = failed + report(false, "f32 spmv bufferSize: " + sb32.error.message);
      } else {
        var b32 = CusparseDevicePtr{ p: 0 };
        if sb32.value > 0 {
          let ab = cusparse_buffer_alloc(sb32.value);
          if ab.is_ok { b32 = ab.value; }
        }
        let ex32 = cusparse_spmv(&h, CUSPARSE_OPERATION_NON_TRANSPOSE, 1.0,
                                 &sp32, &vx32, 0.0, &vy32, CUDA_R_32F,
                                 CUSPARSE_SPMV_ALG_DEFAULT, &b32);
        if ex32.is_err {
          failed = failed + report(false, "f32 spmv: " + ex32.error.message);
        } else {
          var got32 = Vec[Float32].with_len(3);
          let dl32 = cusparse_buffer_download_f32(&dy32, &mut got32);
          if dl32.is_err {
            failed = failed + report(false, "f32 spmv download: " + dl32.error.message);
          } else {
            let ok32 = approx32(got32[0], 5.0 as Float32, 0.001 as Float32)
              && approx32(got32[1], 6.0 as Float32, 0.001 as Float32)
              && approx32(got32[2], 13.0 as Float32, 0.001 as Float32);
            failed = failed + report(ok32,
              "spmv (f32): A*x = [5,6,13], got [" + f32s(got32[0]) + ","
                + f32s(got32[1]) + "," + f32s(got32[2]) + "]");
          }
        }
        if b32.p != 0 {
          let fb = cusparse_buffer_free(&b32);
          failed = failed + expect_unit(fb, "f32 spmv: external buffer released");
        }
      }
      failed = failed + expect_unit(cusparse_destroy_spmat(&sp32), "destroySpMat: f32");
      failed = failed + expect_unit(cusparse_destroy_dnvec(&vx32), "destroyDnVec: f32 x");
      failed = failed + expect_unit(cusparse_destroy_dnvec(&vy32), "destroyDnVec: f32 y");
    }
    failed = failed + expect_unit(cusparse_buffer_free(&dv32), "free: values (f32)");
    failed = failed + expect_unit(cusparse_buffer_free(&dx32), "free: x (f32)");
    failed = failed + expect_unit(cusparse_buffer_free(&dy32), "free: y (f32)");
  }

  // ---- SpMM (f64): C = A * B, A 3x3 CSR, B/C 3x2 row-major ----
  let bmr = cusparse_create_dnmat(&h, 3, 2, 2, &dvb, CUDA_R_64F, CUSPARSE_ORDER_ROW);
  let cmr = cusparse_create_dnmat(&h, 3, 2, 2, &dvc, CUDA_R_64F, CUSPARSE_ORDER_ROW);
  if bmr.is_err || cmr.is_err {
    failed = failed + report(false, "createDnMat: SpMM descriptors failed");
  } else {
    let mat_b = bmr.value;
    let mat_c = cmr.value;
    failed = failed + report(true, "createDnMat: B and C 3x2 row-major descriptors created");
    let smr = cusparse_spmm_buffer_size(&h, CUSPARSE_OPERATION_NON_TRANSPOSE,
                                        CUSPARSE_OPERATION_NON_TRANSPOSE, 1.0,
                                        &sp, &mat_b, 0.0, &mat_c, CUDA_R_64F,
                                        CUSPARSE_SPMM_ALG_DEFAULT);
    if smr.is_err {
      failed = failed + report(false, "spmm bufferSize: " + smr.error.message);
    } else {
      failed = failed + report(smr.value >= 0,
        "spmm bufferSize: " + i2s(smr.value) + " bytes");
      var mbuf = CusparseDevicePtr{ p: 0 };
      if smr.value > 0 {
        let ab = cusparse_buffer_alloc(smr.value);
        if ab.is_ok { mbuf = ab.value; }
      }
      let em = cusparse_spmm(&h, CUSPARSE_OPERATION_NON_TRANSPOSE,
                             CUSPARSE_OPERATION_NON_TRANSPOSE, 1.0, &sp,
                             &mat_b, 0.0, &mat_c, CUDA_R_64F,
                             CUSPARSE_SPMM_ALG_DEFAULT, &mbuf);
      if em.is_err {
        failed = failed + report(false, "spmm: " + em.error.message);
      } else {
        var cout = Vec[Float64].with_len(6);
        let dlc = cusparse_buffer_download_f64(&dvc, &mut cout);
        if dlc.is_err {
          failed = failed + report(false, "spmm download: " + dlc.error.message);
        } else {
          let okc = approx64(cout[0], 3.0, 1e-9) && approx64(cout[1], 1.0, 1e-9)
            && approx64(cout[2], 0.0, 1e-9) && approx64(cout[3], 3.0, 1e-9)
            && approx64(cout[4], 5.0, 1e-9) && approx64(cout[5], 4.0, 1e-9);
          failed = failed + report(okc,
            "spmm: A*B = [[3,1],[0,3],[5,4]], got [[" + f64s(cout[0]) + ","
              + f64s(cout[1]) + "],[" + f64s(cout[2]) + "," + f64s(cout[3])
              + "],[" + f64s(cout[4]) + "," + f64s(cout[5]) + "]]");
        }
      }
      if mbuf.p != 0 {
        let fb = cusparse_buffer_free(&mbuf);
        failed = failed + expect_unit(fb, "spmm: external buffer released");
      }
    }
    failed = failed + expect_unit(cusparse_destroy_dnmat(&mat_b), "destroyDnMat: B");
    failed = failed + expect_unit(cusparse_destroy_dnmat(&mat_c), "destroyDnMat: C");
  }

  // ---- teardown ----
  failed = failed + expect_unit(cusparse_destroy_spmat(&sp), "destroySpMat: CSR (f64)");
  failed = failed + expect_unit(cusparse_destroy_dnvec(&vec_x), "destroyDnVec: x (f64)");
  failed = failed + expect_unit(cusparse_destroy_dnvec(&vec_y), "destroyDnVec: y (f64)");
  failed = failed + expect_unit(cusparse_buffer_free(&dro), "free: row offsets");
  failed = failed + expect_unit(cusparse_buffer_free(&dci), "free: column indices");
  failed = failed + expect_unit(cusparse_buffer_free(&dva), "free: values (f64)");
  failed = failed + expect_unit(cusparse_buffer_free(&dvx), "free: x (f64)");
  failed = failed + expect_unit(cusparse_buffer_free(&dvy), "free: y (f64)");
  failed = failed + expect_unit(cusparse_buffer_free(&dvb), "free: B (f64)");
  failed = failed + expect_unit(cusparse_buffer_free(&dvc), "free: C (f64)");
  failed = failed + expect_unit(cusparse_destroy(&h), "destroy: handle");
  failed = failed + expect_unit(cusparse_unload(&lib), "unload: module + context released");
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.cusparse conformance tests (0.1.0, loader-only) ===");
  io.flush_stdout();
  var failed = 0;
  failed = failed + test_a1_skip_path();
  failed = failed + test_a2_status_names();
  failed = failed + test_a3_invalid_module();
  failed = failed + test_a4_constants();
  failed = failed + test_b_live();
  if failed == 0 {
    io.println("xiom.cusparse: all tests passed");
  } else {
    io.println("xiom.cusparse: tests failed");
  }
  return failed;
}
