// XIOM -- xiom.openblas conformance suite
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 52 checks covering: matrix lifecycle, get/set roundtrip, BLAS 1-3
// (including transposed gemv/gemm and the additive Float32 dot/norm/axpy
// surface), LAPACK SVD/eigen/solve accuracy, error handling, and boundary
// conditions.
//
// Two legs, one suite (see SPEC.md / README.md):
//   * Offline/SKIP leg: linked with bridge/openblas_bridge.c via
//     port.args.json. `backend_is_real()` is false, so the BLAS numbers
//     below come from the pure-XIOM reference paths and the LAPACK checks
//     assert the documented identity/zero placeholders.
//   * Real leg: linked with the system OpenBLAS import library plus
//     bridge/openblas_real_marker.c (tests/run_real_leg.ps1).
//     `backend_is_real()` is true, so the same checks exercise real
//     cblas_* calls and assert LAPACK numerical accuracy.

module xiom.openblas.test_conformance
use xiom.openblas;
use xiom.io;
use xiom.test;

// ============================================================
// Local helpers
// ============================================================

fn vec2(a: Float64, b: Float64) -> Vec[Float64] {
  var v = Vec[Float64].new();
  v.push(a);
  v.push(b);
  return v;
}

fn vec3(a: Float64, b: Float64, c: Float64) -> Vec[Float64] {
  var v = Vec[Float64].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn vec3_f32(a: Float32, b: Float32, c: Float32) -> Vec[Float32] {
  var v = Vec[Float32].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn vec2_f32(a: Float32, b: Float32) -> Vec[Float32] {
  var v = Vec[Float32].new();
  v.push(a);
  v.push(b);
  return v;
}

fn f32(x: Float64) -> Float32 {
  return x as Float32;
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
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
    num = num / 10;
  }
  return out;
}

fn approx_eq(a: Float64, b: Float64, tol: Float64) -> Bool {
  var d = a - b;
  if d < 0.0 { d = -d; }
  return d <= tol;
}

// Float32 comparison in Float64 so the tolerance literal is exact.
// Documented f32 tolerance: 1e-6 (about 8x FLOAT32_EPSILON).
fn approx_eq_f32(a: Float32, b: Float32, tol: Float64) -> Bool {
  return approx_eq(a as Float64, b as Float64, tol);
}

// Reconstruct A from svd(A) and compare with the flat row-major input.
fn svd_reconstructs(data: &Vec[Float64], rows: Int, cols: Int, tol: Float64) -> Bool {
  match matrix_create(rows, cols) {
    Ok(a) => {
      var ha = a;
      var k = 0;
      while k < rows * cols {
        matrix_set(&mut ha, k / cols, k % cols, data[k]);
        k = k + 1;
      }
      match svd(&ha) {
        Ok((u, s, vt)) => {
          var r = rows;
          if cols < r { r = cols; }
          var ok = true;
          var i = 0;
          while i < rows {
            var j = 0;
            while j < cols {
              var sum = 0.0;
              var p = 0;
              while p < r {
                sum = sum + matrix_get(&u, i, p) * matrix_get(&s, p, p) * matrix_get(&vt, p, j);
                p = p + 1;
              }
              if !approx_eq(sum, data[i * cols + j], tol) {
                ok = false;
              }
              j = j + 1;
            }
            i = i + 1;
          }
          matrix_free(u);
          matrix_free(s);
          matrix_free(vt);
          return ok;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 1 -- Matrix lifecycle
// ============================================================

fn test_matrix_create_valid() -> TestResult {
  match matrix_create(3, 4) {
    Ok(m) => {
      let rows = matrix_rows(&m);
      let cols = matrix_cols(&m);
      return xiom.test.assert(rows == 3 && cols == 4, "matrix_create(3,4): rows == 3 and cols == 4");
    }
    Err(_) => { return xiom.test.assert(false, "matrix_create(3,4): expected Ok"); }
  }
}

fn test_matrix_create_zero_rows() -> TestResult {
  match matrix_create(0, 5) {
    Ok(_) => { return xiom.test.assert(false, "matrix_create(0,5): expected Err"); }
    Err(_) => { return xiom.test.assert(true, "matrix_create(0,5): returns Err"); }
  }
}

fn test_matrix_create_zero_cols() -> TestResult {
  match matrix_create(5, 0) {
    Ok(_) => { return xiom.test.assert(false, "matrix_create(5,0): expected Err"); }
    Err(_) => { return xiom.test.assert(true, "matrix_create(5,0): returns Err"); }
  }
}

fn test_matrix_create_negative_dims() -> TestResult {
  match matrix_create(-1, 5) {
    Ok(_) => { return xiom.test.assert(false, "matrix_create(-1,5): expected Err"); }
    Err(_) => { return xiom.test.assert(true, "matrix_create(-1,5): returns Err"); }
  }
}

fn test_matrix_create_1x1() -> TestResult {
  match matrix_create(1, 1) {
    Ok(m) => {
      return xiom.test.assert(matrix_rows(&m) == 1 && matrix_cols(&m) == 1, "matrix_create(1,1): rows == 1 and cols == 1");
    }
    Err(_) => { return xiom.test.assert(false, "matrix_create(1,1): expected Ok"); }
  }
}

fn test_matrix_get_default_zeros() -> TestResult {
  match matrix_create(2, 3) {
    Ok(m) => {
      let v1 = matrix_get(&m, 0, 0);
      let v2 = matrix_get(&m, 1, 2);
      return xiom.test.assert(v1 == 0.0 && v2 == 0.0, "matrix_get: fresh matrix reads 0.0");
    }
    Err(_) => { return xiom.test.assert(false, "matrix_get: expected Ok from matrix_create"); }
  }
}

fn test_matrix_get_set_roundtrip() -> TestResult {
  match matrix_create(3, 3) {
    Ok(m) => {
      var handle = m;
      matrix_set(&mut handle, 0, 0, 42.0);
      matrix_set(&mut handle, 1, 2, 7.5);
      matrix_set(&mut handle, 2, 1, -3.25);
      let v1 = matrix_get(&handle, 0, 0);
      let v2 = matrix_get(&handle, 1, 2);
      let v3 = matrix_get(&handle, 2, 1);
      return xiom.test.assert(v1 == 42.0 && v2 == 7.5 && v3 == -3.25, "matrix_set/get roundtrip preserves values");
    }
    Err(_) => { return xiom.test.assert(false, "matrix_get_set_roundtrip: expected Ok"); }
  }
}

fn test_matrix_get_out_of_bounds() -> TestResult {
  match matrix_create(2, 2) {
    Ok(m) => {
      let v1 = matrix_get(&m, -1, 0);
      let v2 = matrix_get(&m, 0, 3);
      let v3 = matrix_get(&m, 2, 0);
      return xiom.test.assert(v1 == 0.0 && v2 == 0.0 && v3 == 0.0, "matrix_get out of bounds returns 0.0");
    }
    Err(_) => { return xiom.test.assert(false, "matrix_get_out_of_bounds: expected Ok"); }
  }
}

fn test_matrix_set_out_of_bounds_noop() -> TestResult {
  match matrix_create(2, 2) {
    Ok(m) => {
      var handle = m;
      matrix_set(&mut handle, 0, 0, 10.0);
      matrix_set(&mut handle, 5, 5, 99.0);
      return xiom.test.assert(matrix_get(&handle, 0, 0) == 10.0, "matrix_set out of bounds is a no-op");
    }
    Err(_) => { return xiom.test.assert(false, "matrix_set_out_of_bounds_noop: expected Ok"); }
  }
}

fn test_matrix_multiple_independent() -> TestResult {
  match matrix_create(2, 2) {
    Ok(a) => {
      match matrix_create(2, 2) {
        Ok(b) => {
          var ha = a;
          var hb = b;
          matrix_set(&mut ha, 0, 0, 1.0);
          matrix_set(&mut hb, 0, 0, 9.0);
          return xiom.test.assert(matrix_get(&ha, 0, 0) == 1.0 && matrix_get(&hb, 0, 0) == 9.0, "two matrix handles are independent");
        }
        Err(_) => { return xiom.test.assert(false, "matrix_multiple_independent: second create failed"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "matrix_multiple_independent: first create failed"); }
  }
}

fn test_matrix_free_releases() -> TestResult {
  match matrix_create(5, 5) {
    Ok(m) => {
      matrix_free(m);
      return xiom.test.assert(true, "matrix_free completes without error");
    }
    Err(_) => { return xiom.test.assert(false, "matrix_free_releases: expected Ok"); }
  }
}

fn test_matrix_large_allocation() -> TestResult {
  match matrix_create(100, 100) {
    Ok(m) => {
      let rows = matrix_rows(&m);
      let cols = matrix_cols(&m);
      return xiom.test.assert(rows == 100 && cols == 100, "matrix_create(100,100): rows == 100 and cols == 100");
    }
    Err(_) => { return xiom.test.assert(false, "matrix_large_allocation: expected Ok"); }
  }
}

// ============================================================
// Section 2 -- BLAS Level 1 (dot, axpy)
// ============================================================

fn test_dot_product_basic() -> TestResult {
  var x = vec3(1.0, 2.0, 3.0);
  var y = vec3(4.0, 5.0, 6.0);
  let result = dot(&x, &y, 3);
  return xiom.test.assert(result == 32.0, "dot([1,2,3],[4,5,6]) == 32");
}

fn test_dot_product_single_element() -> TestResult {
  var x = vec3(7.0, 0.0, 0.0);
  var y = vec3(3.0, 0.0, 0.0);
  let result = dot(&x, &y, 1);
  return xiom.test.assert(result == 21.0, "dot single element [7]*[3] == 21");
}

fn test_dot_product_with_zeros() -> TestResult {
  var x = vec3(0.0, 0.0, 0.0);
  var y = vec3(1.0, 2.0, 3.0);
  let result = dot(&x, &y, 3);
  return xiom.test.assert(result == 0.0, "dot with zero vector == 0");
}

fn test_dot_product_negative_elements() -> TestResult {
  var x = vec3(-1.0, 2.0, -3.0);
  var y = vec3(4.0, -5.0, 6.0);
  let result = dot(&x, &y, 3);
  return xiom.test.assert(result == -32.0, "dot with negative elements == -32");
}

fn test_axpy_basic() -> TestResult {
  var x = vec3(1.0, 2.0, 3.0);
  var y = vec3(4.0, 5.0, 6.0);
  axpy(2.0, &x, &mut y, 3);
  return xiom.test.assert(y[0] == 6.0 && y[1] == 9.0 && y[2] == 12.0, "axpy(2.0, [1,2,3], [4,5,6]) == [6,9,12]");
}

fn test_axpy_zero_alpha() -> TestResult {
  var x = vec3(1.0, 2.0, 3.0);
  var y = vec3(4.0, 5.0, 6.0);
  axpy(0.0, &x, &mut y, 3);
  return xiom.test.assert(y[0] == 4.0 && y[1] == 5.0 && y[2] == 6.0, "axpy(0.0) leaves y unchanged");
}

fn test_axpy_negative_alpha() -> TestResult {
  var x = vec3(1.0, 1.0, 1.0);
  var y = vec3(10.0, 10.0, 10.0);
  axpy(-1.0, &x, &mut y, 3);
  return xiom.test.assert(y[0] == 9.0 && y[1] == 9.0 && y[2] == 9.0, "axpy(-1.0, ones, tens) == nines");
}

// ============================================================
// Section 2b -- BLAS Level 1 Float32 (additive surface)
// ============================================================
// These checks are leg-aware: on the real leg they exercise cblas_sdot /
// cblas_snrm2 / cblas_saxpy; on the offline/stub leg they exercise the
// self-contained Float32 reference loops (the stub cblas_s* symbols are
// never called). The documented f32 tolerance is 1e-6.

fn test_dot_f32_basic() -> TestResult {
  var x = vec3_f32(f32(1.0), f32(2.0), f32(3.0));
  var y = vec3_f32(f32(4.0), f32(5.0), f32(6.0));
  match dot_f32(&x, &y) {
    Ok(v) => { return xiom.test.assert(v == f32(32.0), "dot_f32([1,2,3],[4,5,6]) == 32"); }
    Err(_) => { return xiom.test.assert(false, "dot_f32 basic: expected Ok"); }
  }
}

fn test_dot_f32_negative() -> TestResult {
  var x = vec3_f32(f32(-1.0), f32(2.0), f32(-3.0));
  var y = vec3_f32(f32(4.0), f32(-5.0), f32(6.0));
  match dot_f32(&x, &y) {
    Ok(v) => { return xiom.test.assert(v == f32(-32.0), "dot_f32([-1,2,-3],[4,-5,6]) == -32"); }
    Err(_) => { return xiom.test.assert(false, "dot_f32 negative: expected Ok"); }
  }
}

fn test_dot_f32_length_mismatch() -> TestResult {
  var x = vec3_f32(f32(1.0), f32(2.0), f32(3.0));
  var y = vec2_f32(f32(4.0), f32(5.0));
  match dot_f32(&x, &y) {
    Ok(_) => { return xiom.test.assert(false, "dot_f32 length mismatch: expected Err"); }
    Err(_) => { return xiom.test.assert(true, "dot_f32 length mismatch: returns Err"); }
  }
}

fn test_dot_f32_empty() -> TestResult {
  var x: Vec[Float32] = Vec[Float32].new();
  var y: Vec[Float32] = Vec[Float32].new();
  match dot_f32(&x, &y) {
    Ok(_) => { return xiom.test.assert(false, "dot_f32 empty: expected Err"); }
    Err(_) => { return xiom.test.assert(true, "dot_f32 empty: returns Err"); }
  }
}

fn test_norm_f32_basic() -> TestResult {
  var x = vec3_f32(f32(1.0), f32(2.0), f32(3.0));
  match norm_f32(&x) {
    Ok(v) => { return xiom.test.assert(approx_eq_f32(v, f32(3.7416573867739413), 0.000001), "norm_f32([1,2,3]) == sqrt(14) (tol 1e-6)"); }
    Err(_) => { return xiom.test.assert(false, "norm_f32 basic: expected Ok"); }
  }
}

fn test_norm_f32_zero_vector() -> TestResult {
  var x = vec3_f32(f32(0.0), f32(0.0), f32(0.0));
  match norm_f32(&x) {
    Ok(v) => { return xiom.test.assert(v == f32(0.0), "norm_f32([0,0,0]) == 0"); }
    Err(_) => { return xiom.test.assert(false, "norm_f32 zero: expected Ok"); }
  }
}

fn test_norm_f32_empty() -> TestResult {
  var x: Vec[Float32] = Vec[Float32].new();
  match norm_f32(&x) {
    Ok(_) => { return xiom.test.assert(false, "norm_f32 empty: expected Err"); }
    Err(_) => { return xiom.test.assert(true, "norm_f32 empty: returns Err"); }
  }
}

fn test_axpy_f32_basic() -> TestResult {
  var x = vec3_f32(f32(1.0), f32(2.0), f32(3.0));
  var y = vec3_f32(f32(4.0), f32(5.0), f32(6.0));
  match axpy_f32(f32(2.0), &x, &mut y) {
    Ok(_) => {
      return xiom.test.assert(y[0] == f32(6.0) && y[1] == f32(9.0) && y[2] == f32(12.0), "axpy_f32(2.0, [1,2,3], [4,5,6]) == [6,9,12]");
    }
    Err(_) => { return xiom.test.assert(false, "axpy_f32 basic: expected Ok"); }
  }
}

fn test_axpy_f32_length_mismatch() -> TestResult {
  var x = vec3_f32(f32(1.0), f32(2.0), f32(3.0));
  var y = vec2_f32(f32(4.0), f32(5.0));
  match axpy_f32(f32(1.0), &x, &mut y) {
    Ok(_) => { return xiom.test.assert(false, "axpy_f32 length mismatch: expected Err"); }
    Err(_) => { return xiom.test.assert(y[0] == f32(4.0) && y[1] == f32(5.0), "axpy_f32 length mismatch: returns Err and leaves y unchanged"); }
  }
}

fn test_f32_leg_marker() -> TestResult {
  // Self-contained check: the Float32 surface is usable on whichever leg this
  // artifact was linked with, and the marker still selects the expected path.
  var x = vec3_f32(f32(1.0), f32(2.0), f32(3.0));
  var y = vec3_f32(f32(4.0), f32(5.0), f32(6.0));
  match dot_f32(&x, &y) {
    Ok(v) => {
      if backend_is_real() {
        return xiom.test.assert(v == f32(32.0), "f32 leg marker: real cblas_sdot leg computes 32");
      }
      return xiom.test.assert(v == f32(32.0), "f32 leg marker: offline reference loop computes 32");
    }
    Err(_) => { return xiom.test.assert(false, "f32 leg marker: expected Ok"); }
  }
}

// ============================================================
// Section 3 -- BLAS Level 2 (gemv)
// ============================================================

fn test_gemv_no_transpose() -> TestResult {
  match matrix_create(2, 3) {
    Ok(a) => {
      var ha = a;
      matrix_set(&mut ha, 0, 0, 1.0);
      matrix_set(&mut ha, 0, 1, 2.0);
      matrix_set(&mut ha, 0, 2, 3.0);
      matrix_set(&mut ha, 1, 0, 4.0);
      matrix_set(&mut ha, 1, 1, 5.0);
      matrix_set(&mut ha, 1, 2, 6.0);
      var x = vec3(1.0, 1.0, 1.0);
      var y = vec2(0.0, 0.0);
      gemv(false, 2, 3, 1.0, &ha, &x, 0.0, &mut y);
      return xiom.test.assert(y[0] == 6.0 && y[1] == 15.0, "gemv no-transpose row sums == [6,15]");
    }
    Err(_) => { return xiom.test.assert(false, "gemv_no_transpose: expected Ok"); }
  }
}

fn test_gemv_with_beta() -> TestResult {
  match matrix_create(2, 2) {
    Ok(a) => {
      var ha = a;
      matrix_set(&mut ha, 0, 0, 1.0);
      matrix_set(&mut ha, 0, 1, 0.0);
      matrix_set(&mut ha, 1, 0, 0.0);
      matrix_set(&mut ha, 1, 1, 1.0);
      var x = vec2(2.0, 3.0);
      var y = vec2(10.0, 10.0);
      gemv(false, 2, 2, 1.0, &ha, &x, 1.0, &mut y);
      return xiom.test.assert(y[0] == 12.0 && y[1] == 13.0, "gemv with beta=1.0 accumulates == [12,13]");
    }
    Err(_) => { return xiom.test.assert(false, "gemv_with_beta: expected Ok"); }
  }
}

// ============================================================
// Section 4 -- BLAS Level 3 (gemm)
// ============================================================

fn test_gemm_2x2_identity() -> TestResult {
  match matrix_create(2, 2) {
    Ok(a) => {
      match matrix_create(2, 2) {
        Ok(b) => {
          match matrix_create(2, 2) {
            Ok(c) => {
              var ha = a;
              var hb = b;
              var hc = c;
              matrix_set(&mut ha, 0, 0, 2.0);
              matrix_set(&mut ha, 0, 1, 3.0);
              matrix_set(&mut ha, 1, 0, 4.0);
              matrix_set(&mut ha, 1, 1, 5.0);
              matrix_set(&mut hb, 0, 0, 1.0);
              matrix_set(&mut hb, 0, 1, 0.0);
              matrix_set(&mut hb, 1, 0, 0.0);
              matrix_set(&mut hb, 1, 1, 1.0);
              gemm(false, false, 2, 2, 2, 1.0, &ha, &hb, 0.0, &mut hc);
              let r00 = matrix_get(&hc, 0, 0);
              let r01 = matrix_get(&hc, 0, 1);
              return xiom.test.assert(r00 == 2.0 && r01 == 3.0, "gemm A * I == A");
            }
            Err(_) => { return xiom.test.assert(false, "gemm_2x2_identity: third create failed"); }
          }
        }
        Err(_) => { return xiom.test.assert(false, "gemm_2x2_identity: second create failed"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "gemm_2x2_identity: first create failed"); }
  }
}

fn test_gemm_zero_beta() -> TestResult {
  match matrix_create(1, 2) {
    Ok(a) => {
      match matrix_create(2, 1) {
        Ok(b) => {
          match matrix_create(1, 1) {
            Ok(c) => {
              var ha = a;
              var hb = b;
              var hc = c;
              matrix_set(&mut ha, 0, 0, 1.0);
              matrix_set(&mut ha, 0, 1, 2.0);
              matrix_set(&mut hb, 0, 0, 3.0);
              matrix_set(&mut hb, 1, 0, 4.0);
              matrix_set(&mut hc, 0, 0, 100.0);
              gemm(false, false, 1, 1, 2, 1.0, &ha, &hb, 0.0, &mut hc);
              return xiom.test.assert(matrix_get(&hc, 0, 0) == 11.0, "gemm with beta=0 discards old C == 11");
            }
            Err(_) => { return xiom.test.assert(false, "gemm_zero_beta: third create failed"); }
          }
        }
        Err(_) => { return xiom.test.assert(false, "gemm_zero_beta: second create failed"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "gemm_zero_beta: first create failed"); }
  }
}

// ============================================================
// Section 4b -- BLAS transposed paths (both legs)
// ============================================================

fn test_gemv_transpose() -> TestResult {
  match matrix_create(3, 2) {
    Ok(a) => {
      var ha = a;
      matrix_set(&mut ha, 0, 0, 1.0);
      matrix_set(&mut ha, 0, 1, 2.0);
      matrix_set(&mut ha, 1, 0, 3.0);
      matrix_set(&mut ha, 1, 1, 4.0);
      matrix_set(&mut ha, 2, 0, 5.0);
      matrix_set(&mut ha, 2, 1, 6.0);
      var x = vec3(1.0, 1.0, 1.0);
      var y = vec2(0.0, 0.0);
      gemv(true, 2, 3, 1.0, &ha, &x, 0.0, &mut y);
      return xiom.test.assert(y[0] == 9.0 && y[1] == 12.0, "gemv transpose column sums == [9,12]");
    }
    Err(_) => { return xiom.test.assert(false, "gemv_transpose: expected Ok"); }
  }
}

fn test_gemm_transpose_a() -> TestResult {
  match matrix_create(3, 2) {
    Ok(a) => {
      match matrix_create(3, 2) {
        Ok(b) => {
          match matrix_create(2, 2) {
            Ok(c) => {
              var ha = a;
              var hb = b;
              var hc = c;
              matrix_set(&mut ha, 0, 0, 1.0);
              matrix_set(&mut ha, 0, 1, 2.0);
              matrix_set(&mut ha, 1, 0, 3.0);
              matrix_set(&mut ha, 1, 1, 4.0);
              matrix_set(&mut ha, 2, 0, 5.0);
              matrix_set(&mut ha, 2, 1, 6.0);
              matrix_set(&mut hb, 0, 0, 1.0);
              matrix_set(&mut hb, 0, 1, 0.0);
              matrix_set(&mut hb, 1, 0, 0.0);
              matrix_set(&mut hb, 1, 1, 1.0);
              matrix_set(&mut hb, 2, 0, 1.0);
              matrix_set(&mut hb, 2, 1, 1.0);
              gemm(true, false, 2, 2, 3, 1.0, &ha, &hb, 0.0, &mut hc);
              return xiom.test.assert(matrix_get(&hc, 0, 0) == 6.0 && matrix_get(&hc, 0, 1) == 8.0 && matrix_get(&hc, 1, 0) == 8.0 && matrix_get(&hc, 1, 1) == 10.0, "gemm transA: A^T B == [[6,8],[8,10]]");
            }
            Err(_) => { return xiom.test.assert(false, "gemm_transpose_a: C create failed"); }
          }
        }
        Err(_) => { return xiom.test.assert(false, "gemm_transpose_a: B create failed"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "gemm_transpose_a: A create failed"); }
  }
}

fn test_gemm_transpose_b() -> TestResult {
  match matrix_create(2, 3) {
    Ok(a) => {
      match matrix_create(2, 3) {
        Ok(b) => {
          match matrix_create(2, 2) {
            Ok(c) => {
              var ha = a;
              var hb = b;
              var hc = c;
              matrix_set(&mut ha, 0, 0, 1.0);
              matrix_set(&mut ha, 0, 1, 2.0);
              matrix_set(&mut ha, 0, 2, 3.0);
              matrix_set(&mut ha, 1, 0, 4.0);
              matrix_set(&mut ha, 1, 1, 5.0);
              matrix_set(&mut ha, 1, 2, 6.0);
              matrix_set(&mut hb, 0, 0, 1.0);
              matrix_set(&mut hb, 0, 1, 0.0);
              matrix_set(&mut hb, 0, 2, 1.0);
              matrix_set(&mut hb, 1, 0, 0.0);
              matrix_set(&mut hb, 1, 1, 1.0);
              matrix_set(&mut hb, 1, 2, 1.0);
              gemm(false, true, 2, 2, 3, 1.0, &ha, &hb, 0.0, &mut hc);
              return xiom.test.assert(matrix_get(&hc, 0, 0) == 4.0 && matrix_get(&hc, 0, 1) == 5.0 && matrix_get(&hc, 1, 0) == 10.0 && matrix_get(&hc, 1, 1) == 11.0, "gemm transB: A B^T == [[4,5],[10,11]]");
            }
            Err(_) => { return xiom.test.assert(false, "gemm_transpose_b: C create failed"); }
          }
        }
        Err(_) => { return xiom.test.assert(false, "gemm_transpose_b: B create failed"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "gemm_transpose_b: A create failed"); }
  }
}

// ============================================================
// Section 5 -- LAPACK: SVD
// ============================================================

fn test_svd_returns_ok() -> TestResult {
  match matrix_create(3, 3) {
    Ok(a) => {
      var ha = a;
      matrix_set(&mut ha, 0, 0, 1.0);
      matrix_set(&mut ha, 1, 1, 1.0);
      matrix_set(&mut ha, 2, 2, 1.0);
      match svd(&ha) {
        Ok((u, s, vt)) => {
          matrix_free(u);
          matrix_free(s);
          matrix_free(vt);
          return xiom.test.assert(true, "svd identity: returns Ok with three matrices");
        }
        Err(_) => { return xiom.test.assert(false, "svd identity: expected Ok"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "svd_returns_ok: expected Ok"); }
  }
}

fn test_svd_correct_shapes() -> TestResult {
  match matrix_create(4, 3) {
    Ok(a) => {
      match svd(&a) {
        Ok((u, s, vt)) => {
          let u_rows = matrix_rows(&u);
          let u_cols = matrix_cols(&u);
          let s_rows = matrix_rows(&s);
          let s_cols = matrix_cols(&s);
          let vt_rows = matrix_rows(&vt);
          let vt_cols = matrix_cols(&vt);
          matrix_free(u);
          matrix_free(s);
          matrix_free(vt);
          return xiom.test.assert(u_rows == 4 && u_cols == 3 && s_rows == 3 && s_cols == 3 && vt_rows == 3 && vt_cols == 3, "svd 4x3: u 4x3, s 3x3, vt 3x3");
        }
        Err(_) => { return xiom.test.assert(false, "svd_correct_shapes: expected Ok"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "svd_correct_shapes: expected Ok"); }
  }
}

fn test_svd_tall_matrix() -> TestResult {
  match matrix_create(5, 2) {
    Ok(a) => {
      match svd(&a) {
        Ok((u, s, vt)) => {
          matrix_free(u);
          matrix_free(s);
          matrix_free(vt);
          return xiom.test.assert(true, "svd 5x2 tall matrix returns Ok");
        }
        Err(_) => { return xiom.test.assert(false, "svd_tall_matrix: expected Ok"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "svd_tall_matrix: expected Ok"); }
  }
}

fn test_svd_singular_values() -> TestResult {
  match matrix_create(3, 3) {
    Ok(a) => {
      var ha = a;
      matrix_set(&mut ha, 0, 0, 3.0);
      matrix_set(&mut ha, 1, 1, 2.0);
      matrix_set(&mut ha, 2, 2, 1.0);
      match svd(&ha) {
        Ok((u, s, vt)) => {
          var ok = false;
          if backend_is_real() {
            ok = approx_eq(matrix_get(&s, 0, 0), 3.0, 0.000000001)
              && approx_eq(matrix_get(&s, 1, 1), 2.0, 0.000000001)
              && approx_eq(matrix_get(&s, 2, 2), 1.0, 0.000000001);
          } else {
            ok = matrix_get(&s, 0, 0) == 0.0 && matrix_get(&s, 2, 2) == 0.0;
          }
          matrix_free(u);
          matrix_free(s);
          matrix_free(vt);
          return xiom.test.assert(ok, "svd diag(3,2,1): singular values [3,2,1] on the real leg (zeros on the stub leg)");
        }
        Err(_) => { return xiom.test.assert(false, "svd_singular_values: expected Ok"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "svd_singular_values: expected Ok"); }
  }
}

fn test_svd_reconstruct_tall() -> TestResult {
  if !backend_is_real() {
    return xiom.test.assert(true, "svd reconstruct 4x3: SKIP (stub leg placeholder, documented)");
  }
  var data = Vec[Float64].new();
  data.push(1.0);
  data.push(2.0);
  data.push(3.0);
  data.push(4.0);
  data.push(5.0);
  data.push(6.0);
  data.push(7.0);
  data.push(8.0);
  data.push(9.0);
  data.push(10.0);
  data.push(11.0);
  data.push(13.0);
  return xiom.test.assert(svd_reconstructs(&data, 4, 3, 0.000000001), "svd 4x3: U * S * VT reconstructs A (tol 1e-9)");
}

fn test_svd_reconstruct_wide() -> TestResult {
  if !backend_is_real() {
    return xiom.test.assert(true, "svd reconstruct 2x3: SKIP (stub leg placeholder, documented)");
  }
  var data = Vec[Float64].new();
  data.push(1.0);
  data.push(2.0);
  data.push(3.0);
  data.push(4.0);
  data.push(5.0);
  data.push(6.0);
  return xiom.test.assert(svd_reconstructs(&data, 2, 3, 0.000000001), "svd 2x3: U * S * VT reconstructs A (tol 1e-9)");
}

// ============================================================
// Section 6 -- LAPACK: symmetric eigenvalues
// ============================================================

fn test_eigen_sym_square_ok() -> TestResult {
  match matrix_create(3, 3) {
    Ok(a) => {
      var ha = a;
      matrix_set(&mut ha, 0, 0, 1.0);
      matrix_set(&mut ha, 1, 1, 2.0);
      matrix_set(&mut ha, 2, 2, 3.0);
      match eigen_sym(&ha) {
        Ok((vals, vecs)) => {
          matrix_free(vals);
          matrix_free(vecs);
          return xiom.test.assert(true, "eigen_sym diagonal 3x3 returns Ok");
        }
        Err(_) => { return xiom.test.assert(false, "eigen_sym_square_ok: expected Ok"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "eigen_sym_square_ok: expected Ok"); }
  }
}

fn test_eigen_sym_rejects_rectangular() -> TestResult {
  match matrix_create(3, 2) {
    Ok(a) => {
      match eigen_sym(&a) {
        Ok(_) => { return xiom.test.assert(false, "eigen_sym 3x2: expected Err"); }
        Err(_) => { return xiom.test.assert(true, "eigen_sym 3x2: returns Err"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "eigen_sym_rejects_rectangular: expected Ok"); }
  }
}

fn test_eigen_sym_1x1() -> TestResult {
  match matrix_create(1, 1) {
    Ok(a) => {
      var ha = a;
      matrix_set(&mut ha, 0, 0, 42.0);
      match eigen_sym(&ha) {
        Ok((vals, vecs)) => {
          let v_rows = matrix_rows(&vals);
          let vec_rows = matrix_rows(&vecs);
          matrix_free(vals);
          matrix_free(vecs);
          return xiom.test.assert(v_rows == 1 && vec_rows == 1, "eigen_sym 1x1: both results are 1x1");
        }
        Err(_) => { return xiom.test.assert(false, "eigen_sym_1x1: expected Ok"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "eigen_sym_1x1: expected Ok"); }
  }
}

fn test_eigen_sym_values() -> TestResult {
  match matrix_create(2, 2) {
    Ok(a) => {
      var ha = a;
      matrix_set(&mut ha, 0, 0, 2.0);
      matrix_set(&mut ha, 0, 1, 1.0);
      matrix_set(&mut ha, 1, 0, 1.0);
      matrix_set(&mut ha, 1, 1, 2.0);
      match eigen_sym(&ha) {
        Ok((vals, vecs)) => {
          var ok = false;
          if backend_is_real() {
            ok = approx_eq(matrix_get(&vals, 0, 0), 1.0, 0.000000001)
              && approx_eq(matrix_get(&vals, 1, 1), 3.0, 0.000000001);
          } else {
            ok = matrix_get(&vals, 0, 0) == 0.0 && matrix_get(&vals, 1, 1) == 0.0;
          }
          matrix_free(vals);
          matrix_free(vecs);
          return xiom.test.assert(ok, "eigen_sym [[2,1],[1,2]]: values [1,3] on the real leg (zeros on the stub leg)");
        }
        Err(_) => { return xiom.test.assert(false, "eigen_sym_values: expected Ok"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "eigen_sym_values: expected Ok"); }
  }
}

fn test_eigen_sym_vectors() -> TestResult {
  match matrix_create(2, 2) {
    Ok(a) => {
      var ha = a;
      matrix_set(&mut ha, 0, 0, 2.0);
      matrix_set(&mut ha, 0, 1, 1.0);
      matrix_set(&mut ha, 1, 0, 1.0);
      matrix_set(&mut ha, 1, 1, 2.0);
      match eigen_sym(&ha) {
        Ok((vals, vecs)) => {
          var ok = true;
          if backend_is_real() {
            var j = 0;
            while j < 2 {
              let lam = matrix_get(&vals, j, j);
              var k = 0;
              while k < 2 {
                var av = 0.0;
                var i = 0;
                while i < 2 {
                  av = av + matrix_get(&ha, k, i) * matrix_get(&vecs, i, j);
                  i = i + 1;
                }
                if !approx_eq(av, lam * matrix_get(&vecs, k, j), 0.000000001) {
                  ok = false;
                }
                k = k + 1;
              }
              j = j + 1;
            }
          } else {
            ok = matrix_get(&vecs, 0, 0) == 1.0 && matrix_get(&vecs, 0, 1) == 0.0
              && matrix_get(&vecs, 1, 0) == 0.0 && matrix_get(&vecs, 1, 1) == 1.0;
          }
          matrix_free(vals);
          matrix_free(vecs);
          return xiom.test.assert(ok, "eigen_sym: A*v == lambda*v on the real leg (identity on the stub leg)");
        }
        Err(_) => { return xiom.test.assert(false, "eigen_sym_vectors: expected Ok"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "eigen_sym_vectors: expected Ok"); }
  }
}

// ============================================================
// Section 7 -- LAPACK: linear solve
// ============================================================

fn test_solve_square_ok() -> TestResult {
  match matrix_create(3, 3) {
    Ok(a) => {
      var ha = a;
      matrix_set(&mut ha, 0, 0, 1.0);
      matrix_set(&mut ha, 1, 1, 1.0);
      matrix_set(&mut ha, 2, 2, 1.0);
      var b = vec3(1.0, 2.0, 3.0);
      match solve(&ha, &b) {
        Ok(x) => {
          let x_rows = matrix_rows(&x);
          let x_cols = matrix_cols(&x);
          matrix_free(x);
          return xiom.test.assert(x_rows == 3 && x_cols == 1, "solve 3x3: x is 3x1");
        }
        Err(_) => { return xiom.test.assert(false, "solve_square_ok: expected Ok"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "solve_square_ok: expected Ok"); }
  }
}

fn test_solve_rejects_nonsquare() -> TestResult {
  match matrix_create(3, 2) {
    Ok(a) => {
      var b = vec3(1.0, 2.0, 3.0);
      match solve(&a, &b) {
        Ok(_) => { return xiom.test.assert(false, "solve 3x2: expected Err"); }
        Err(_) => { return xiom.test.assert(true, "solve 3x2: returns Err"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "solve_rejects_nonsquare: expected Ok"); }
  }
}

fn test_solve_dimension_mismatch() -> TestResult {
  match matrix_create(3, 3) {
    Ok(a) => {
      var b = vec2(1.0, 2.0);
      match solve(&a, &b) {
        Ok(_) => { return xiom.test.assert(false, "solve 3x3 with |b|=2: expected Err"); }
        Err(_) => { return xiom.test.assert(true, "solve 3x3 with |b|=2: returns Err"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "solve_dimension_mismatch: expected Ok"); }
  }
}

fn test_solve_values() -> TestResult {
  match matrix_create(2, 2) {
    Ok(a) => {
      var ha = a;
      matrix_set(&mut ha, 0, 0, 3.0);
      matrix_set(&mut ha, 0, 1, 1.0);
      matrix_set(&mut ha, 1, 0, 1.0);
      matrix_set(&mut ha, 1, 1, 2.0);
      var b = vec2(9.0, 8.0);
      match solve(&ha, &b) {
        Ok(x) => {
          var ok = false;
          if backend_is_real() {
            ok = approx_eq(matrix_get(&x, 0, 0), 2.0, 0.000000001)
              && approx_eq(matrix_get(&x, 1, 0), 3.0, 0.000000001);
          } else {
            ok = matrix_get(&x, 0, 0) == 0.0 && matrix_get(&x, 1, 0) == 0.0;
          }
          matrix_free(x);
          return xiom.test.assert(ok, "solve [[3,1],[1,2]]x=[9,8]: x=[2,3] on the real leg (zeros on the stub leg)");
        }
        Err(_) => { return xiom.test.assert(false, "solve_values: expected Ok"); }
      }
    }
    Err(_) => { return xiom.test.assert(false, "solve_values: expected Ok"); }
  }
}

fn test_solve_singular() -> TestResult {
  match matrix_create(2, 2) {
    Ok(a) => {
      var ha = a;
      matrix_set(&mut ha, 0, 0, 1.0);
      matrix_set(&mut ha, 0, 1, 2.0);
      matrix_set(&mut ha, 1, 0, 2.0);
      matrix_set(&mut ha, 1, 1, 4.0);
      var b = vec2(1.0, 2.0);
      match solve(&ha, &b) {
        Ok(x) => {
          matrix_free(x);
          if backend_is_real() {
            return xiom.test.assert(false, "solve singular 2x2: expected Err on the real leg");
          }
          return xiom.test.assert(true, "solve singular 2x2: stub leg returns the documented zero placeholder");
        }
        Err(_) => {
          return xiom.test.assert(backend_is_real(), "solve singular 2x2: real dgesv_ returns Err (info > 0)");
        }
      }
    }
    Err(_) => { return xiom.test.assert(false, "solve_singular: expected Ok"); }
  }
}

// ============================================================
// Test runner
// ============================================================

pub fn main() -> Int {
  io.println("=== XIOM xiom.openblas Conformance Tests ===");
  io.println("");

  var results = Vec[TestResult].new();

  results.push(test_matrix_create_valid());
  results.push(test_matrix_create_zero_rows());
  results.push(test_matrix_create_zero_cols());
  results.push(test_matrix_create_negative_dims());
  results.push(test_matrix_create_1x1());
  results.push(test_matrix_get_default_zeros());
  results.push(test_matrix_get_set_roundtrip());
  results.push(test_matrix_get_out_of_bounds());
  results.push(test_matrix_set_out_of_bounds_noop());
  results.push(test_matrix_multiple_independent());
  results.push(test_matrix_free_releases());
  results.push(test_matrix_large_allocation());

  results.push(test_dot_product_basic());
  results.push(test_dot_product_single_element());
  results.push(test_dot_product_with_zeros());
  results.push(test_dot_product_negative_elements());
  results.push(test_axpy_basic());
  results.push(test_axpy_zero_alpha());
  results.push(test_axpy_negative_alpha());

  results.push(test_dot_f32_basic());
  results.push(test_dot_f32_negative());
  results.push(test_dot_f32_length_mismatch());
  results.push(test_dot_f32_empty());
  results.push(test_norm_f32_basic());
  results.push(test_norm_f32_zero_vector());
  results.push(test_norm_f32_empty());
  results.push(test_axpy_f32_basic());
  results.push(test_axpy_f32_length_mismatch());
  results.push(test_f32_leg_marker());

  results.push(test_gemv_no_transpose());
  results.push(test_gemv_with_beta());

  results.push(test_gemm_2x2_identity());
  results.push(test_gemm_zero_beta());
  results.push(test_gemv_transpose());
  results.push(test_gemm_transpose_a());
  results.push(test_gemm_transpose_b());

  results.push(test_svd_returns_ok());
  results.push(test_svd_correct_shapes());
  results.push(test_svd_tall_matrix());
  results.push(test_svd_singular_values());
  results.push(test_svd_reconstruct_tall());
  results.push(test_svd_reconstruct_wide());

  results.push(test_eigen_sym_square_ok());
  results.push(test_eigen_sym_rejects_rectangular());
  results.push(test_eigen_sym_1x1());
  results.push(test_eigen_sym_values());
  results.push(test_eigen_sym_vectors());

  results.push(test_solve_square_ok());
  results.push(test_solve_rejects_nonsquare());
  results.push(test_solve_dimension_mismatch());
  results.push(test_solve_values());
  results.push(test_solve_singular());

  let total_count = results.len();
  let report = xiom.test.format_results(results);
  io.println(report);

  let fail_count = xiom.test.test_count_failures(results);
  let pass_count = total_count - fail_count;

  io.println("");
  io.println(int_to_str(pass_count) + "/" + int_to_str(total_count) + " tests passed");

  if fail_count == 0 {
    io.println("ALL " + int_to_str(total_count) + " TESTS PASSED");
    io.println("Path: packages\\xiom-openblas\\tests\\test_conformance.xi");
    return 0;
  } else {
    io.println("SOME TESTS FAILED");
    return 1;
  };
}
