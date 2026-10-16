// XIOM -- xiom.openblas conformance suite
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 32 checks covering: matrix lifecycle, get/set roundtrip, BLAS 1-3,
// LAPACK Phase-1 stub paths, error handling, and boundary conditions.
// Same checks / names / order as the original suite, rewritten to the
// current xiom.test API (TestResult + format_results).
//
// Offline-leg note (see SPEC.md): the module is compiled and linked with
// bridge/openblas_bridge.c (stub link-seam via port.args.json), so this
// suite runs with no system OpenBLAS installed. All numbers below come
// from the pure-XIOM reference paths in openblas.xi.

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
// Section 5 -- LAPACK: SVD (Phase 1 stub paths)
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

// ============================================================
// Section 6 -- LAPACK: symmetric eigenvalues (Phase 1 stub paths)
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

// ============================================================
// Section 7 -- LAPACK: linear solve (Phase 1 stub paths)
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

  results.push(test_gemv_no_transpose());
  results.push(test_gemv_with_beta());

  results.push(test_gemm_2x2_identity());
  results.push(test_gemm_zero_beta());

  results.push(test_svd_returns_ok());
  results.push(test_svd_correct_shapes());
  results.push(test_svd_tall_matrix());

  results.push(test_eigen_sym_square_ok());
  results.push(test_eigen_sym_rejects_rectangular());
  results.push(test_eigen_sym_1x1());

  results.push(test_solve_square_ok());
  results.push(test_solve_rejects_nonsquare());
  results.push(test_solve_dimension_mismatch());

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
