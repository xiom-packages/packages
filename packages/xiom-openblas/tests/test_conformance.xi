// XIOM -- xiom.openblas conformance test suite
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 26 tests covering: matrix lifecycle, get/set roundtrip, BLAS 1-3,
// LAPACK stub paths, error handling, and boundary conditions.
// Returns 0 on full pass, nonzero on first failure.

module xiom.openblas.test_conformance
use xiom.openblas;

// ============================================================
// Section 1 -- Matrix lifecycle
// ============================================================

fn test_matrix_create_valid() -> Bool {
  match openblas.matrix_create(3, 4) {
    Ok(m) => {
      var rows = openblas.matrix_rows(&m);
      var cols = openblas.matrix_cols(&m);
      return rows == 3 && cols == 4;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_create_zero_rows() -> Bool {
  match openblas.matrix_create(0, 5) {
    Ok(_) => { return false; }
    Err(_) => { return true; }
  }
}

fn test_matrix_create_zero_cols() -> Bool {
  match openblas.matrix_create(5, 0) {
    Ok(_) => { return false; }
    Err(_) => { return true; }
  }
}

fn test_matrix_create_negative_dims() -> Bool {
  match openblas.matrix_create(-1, 5) {
    Ok(_) => { return false; }
    Err(_) => { return true; }
  }
}

fn test_matrix_create_1x1() -> Bool {
  match openblas.matrix_create(1, 1) {
    Ok(m) => {
      return openblas.matrix_rows(&m) == 1 && openblas.matrix_cols(&m) == 1;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_get_default_zeros() -> Bool {
  match openblas.matrix_create(2, 3) {
    Ok(m) => {
      var v1 = openblas.matrix_get(&m, 0, 0);
      var v2 = openblas.matrix_get(&m, 1, 2);
      return v1 == 0.0 && v2 == 0.0;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_get_set_roundtrip() -> Bool {
  match openblas.matrix_create(3, 3) {
    Ok(m) => {
      var handle = m;
      openblas.matrix_set(&mut handle, 0, 0, 42.0);
      openblas.matrix_set(&mut handle, 1, 2, 7.5);
      openblas.matrix_set(&mut handle, 2, 1, -3.25);
      var v1 = openblas.matrix_get(&handle, 0, 0);
      var v2 = openblas.matrix_get(&handle, 1, 2);
      var v3 = openblas.matrix_get(&handle, 2, 1);
      return v1 == 42.0 && v2 == 7.5 && v3 == -3.25;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_get_out_of_bounds() -> Bool {
  match openblas.matrix_create(2, 2) {
    Ok(m) => {
      var v1 = openblas.matrix_get(&m, -1, 0);
      var v2 = openblas.matrix_get(&m, 0, 3);
      var v3 = openblas.matrix_get(&m, 2, 0);
      return v1 == 0.0 && v2 == 0.0 && v3 == 0.0;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_set_out_of_bounds_noop() -> Bool {
  match openblas.matrix_create(2, 2) {
    Ok(m) => {
      var handle = m;
      openblas.matrix_set(&mut handle, 0, 0, 10.0);
      openblas.matrix_set(&mut handle, 5, 5, 99.0);
      var v = openblas.matrix_get(&handle, 0, 0);
      return v == 10.0;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_multiple_independent() -> Bool {
  match openblas.matrix_create(2, 2) {
    Ok(a) => {
      match openblas.matrix_create(2, 2) {
        Ok(b) => {
          var ha = a;
          var hb = b;
          openblas.matrix_set(&mut ha, 0, 0, 1.0);
          openblas.matrix_set(&mut hb, 0, 0, 9.0);
          return openblas.matrix_get(&ha, 0, 0) == 1.0
              && openblas.matrix_get(&hb, 0, 0) == 9.0;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_free_releases() -> Bool {
  match openblas.matrix_create(5, 5) {
    Ok(m) => {
      openblas.matrix_free(m);
      return true;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_large_allocation() -> Bool {
  match openblas.matrix_create(100, 100) {
    Ok(m) => {
      var rows = openblas.matrix_rows(&m);
      var cols = openblas.matrix_cols(&m);
      return rows == 100 && cols == 100;
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 2 -- BLAS Level 1 (dot, axpy)
// ============================================================

fn test_dot_product_basic() -> Bool {
  var x = [1.0, 2.0, 3.0];
  var y = [4.0, 5.0, 6.0];
  var result = openblas.dot(&x, &y, 3);
  return result == 32.0;
}

fn test_dot_product_single_element() -> Bool {
  var x = [7.0];
  var y = [3.0];
  var result = openblas.dot(&x, &y, 1);
  return result == 21.0;
}

fn test_dot_product_with_zeros() -> Bool {
  var x = [0.0, 0.0, 0.0];
  var y = [1.0, 2.0, 3.0];
  var result = openblas.dot(&x, &y, 3);
  return result == 0.0;
}

fn test_dot_product_negative_elements() -> Bool {
  var x = [-1.0, 2.0, -3.0];
  var y = [4.0, -5.0, 6.0];
  var result = openblas.dot(&x, &y, 3);
  return result == -32.0;
}

fn test_axpy_basic() -> Bool {
  var x = [1.0, 2.0, 3.0];
  var y = [4.0, 5.0, 6.0];
  openblas.axpy(2.0, &x, &mut y, 3);
  return y[0] == 6.0 && y[1] == 9.0 && y[2] == 12.0;
}

fn test_axpy_zero_alpha() -> Bool {
  var x = [1.0, 2.0, 3.0];
  var y = [4.0, 5.0, 6.0];
  openblas.axpy(0.0, &x, &mut y, 3);
  return y[0] == 4.0 && y[1] == 5.0 && y[2] == 6.0;
}

fn test_axpy_negative_alpha() -> Bool {
  var x = [1.0, 1.0, 1.0];
  var y = [10.0, 10.0, 10.0];
  openblas.axpy(-1.0, &x, &mut y, 3);
  return y[0] == 9.0 && y[1] == 9.0 && y[2] == 9.0;
}

// ============================================================
// Section 3 -- BLAS Level 2 (gemv)
// ============================================================

fn test_gemv_no_transpose() -> Bool {
  match openblas.matrix_create(2, 3) {
    Ok(a) => {
      var ha = a;
      openblas.matrix_set(&mut ha, 0, 0, 1.0);
      openblas.matrix_set(&mut ha, 0, 1, 2.0);
      openblas.matrix_set(&mut ha, 0, 2, 3.0);
      openblas.matrix_set(&mut ha, 1, 0, 4.0);
      openblas.matrix_set(&mut ha, 1, 1, 5.0);
      openblas.matrix_set(&mut ha, 1, 2, 6.0);
      var x = [1.0, 1.0, 1.0];
      var y = [0.0, 0.0];
      openblas.gemv(false, 2, 3, 1.0, &ha, &x, 0.0, &mut y);
      return y[0] == 6.0 && y[1] == 15.0;
    }
    Err(_) => { return false; }
  }
}

fn test_gemv_with_beta() -> Bool {
  match openblas.matrix_create(2, 2) {
    Ok(a) => {
      var ha = a;
      openblas.matrix_set(&mut ha, 0, 0, 1.0);
      openblas.matrix_set(&mut ha, 0, 1, 0.0);
      openblas.matrix_set(&mut ha, 1, 0, 0.0);
      openblas.matrix_set(&mut ha, 1, 1, 1.0);
      var x = [2.0, 3.0];
      var y = [10.0, 10.0];
      openblas.gemv(false, 2, 2, 1.0, &ha, &x, 1.0, &mut y);
      return y[0] == 12.0 && y[1] == 13.0;
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 4 -- BLAS Level 3 (gemm)
// ============================================================

fn test_gemm_2x2_identity() -> Bool {
  match openblas.matrix_create(2, 2) {
    Ok(a) => {
      match openblas.matrix_create(2, 2) {
        Ok(b) => {
          match openblas.matrix_create(2, 2) {
            Ok(c) => {
              var ha = a;
              var hb = b;
              var hc = c;
              openblas.matrix_set(&mut ha, 0, 0, 2.0);
              openblas.matrix_set(&mut ha, 0, 1, 3.0);
              openblas.matrix_set(&mut ha, 1, 0, 4.0);
              openblas.matrix_set(&mut ha, 1, 1, 5.0);
              openblas.matrix_set(&mut hb, 0, 0, 1.0);
              openblas.matrix_set(&mut hb, 0, 1, 0.0);
              openblas.matrix_set(&mut hb, 1, 0, 0.0);
              openblas.matrix_set(&mut hb, 1, 1, 1.0);
              openblas.gemm(false, false, 2, 2, 2, 1.0, &ha, &hb, 0.0, &mut hc);
              var r00 = openblas.matrix_get(&hc, 0, 0);
              var r01 = openblas.matrix_get(&hc, 0, 1);
              return r00 == 2.0 && r01 == 3.0;
            }
            Err(_) => { return false; }
          }
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_gemm_zero_beta() -> Bool {
  match openblas.matrix_create(1, 2) {
    Ok(a) => {
      match openblas.matrix_create(2, 1) {
        Ok(b) => {
          match openblas.matrix_create(1, 1) {
            Ok(c) => {
              var ha = a;
              var hb = b;
              var hc = c;
              openblas.matrix_set(&mut ha, 0, 0, 1.0);
              openblas.matrix_set(&mut ha, 0, 1, 2.0);
              openblas.matrix_set(&mut hb, 0, 0, 3.0);
              openblas.matrix_set(&mut hb, 1, 0, 4.0);
              openblas.matrix_set(&mut hc, 0, 0, 100.0);
              openblas.gemm(false, false, 1, 1, 2, 1.0, &ha, &hb, 0.0, &mut hc);
              return openblas.matrix_get(&hc, 0, 0) == 11.0;
            }
            Err(_) => { return false; }
          }
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 5 -- LAPACK: SVD
// ============================================================

fn test_svd_returns_ok() -> Bool {
  match openblas.matrix_create(3, 3) {
    Ok(a) => {
      var ha = a;
      openblas.matrix_set(&mut ha, 0, 0, 1.0);
      openblas.matrix_set(&mut ha, 1, 1, 1.0);
      openblas.matrix_set(&mut ha, 2, 2, 1.0);
      match openblas.svd(&ha) {
        Ok((u, s, vt)) => {
          openblas.matrix_free(u);
          openblas.matrix_free(s);
          openblas.matrix_free(vt);
          return true;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_svd_correct_shapes() -> Bool {
  match openblas.matrix_create(4, 3) {
    Ok(a) => {
      match openblas.svd(&a) {
        Ok((u, s, vt)) => {
          var u_rows = openblas.matrix_rows(&u);
          var u_cols = openblas.matrix_cols(&u);
          var s_rows = openblas.matrix_rows(&s);
          var s_cols = openblas.matrix_cols(&s);
          var vt_rows = openblas.matrix_rows(&vt);
          var vt_cols = openblas.matrix_cols(&vt);
          openblas.matrix_free(u);
          openblas.matrix_free(s);
          openblas.matrix_free(vt);
          return u_rows == 4 && u_cols == 3
              && s_rows == 3 && s_cols == 3
              && vt_rows == 3 && vt_cols == 3;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_svd_tall_matrix() -> Bool {
  match openblas.matrix_create(5, 2) {
    Ok(a) => {
      match openblas.svd(&a) {
        Ok((u, s, vt)) => {
          openblas.matrix_free(u);
          openblas.matrix_free(s);
          openblas.matrix_free(vt);
          return true;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 6 -- LAPACK: symmetric eigenvalues
// ============================================================

fn test_eigen_sym_square_ok() -> Bool {
  match openblas.matrix_create(3, 3) {
    Ok(a) => {
      var ha = a;
      openblas.matrix_set(&mut ha, 0, 0, 1.0);
      openblas.matrix_set(&mut ha, 1, 1, 2.0);
      openblas.matrix_set(&mut ha, 2, 2, 3.0);
      match openblas.eigen_sym(&ha) {
        Ok((vals, vecs)) => {
          openblas.matrix_free(vals);
          openblas.matrix_free(vecs);
          return true;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_eigen_sym_rejects_rectangular() -> Bool {
  match openblas.matrix_create(3, 2) {
    Ok(a) => {
      match openblas.eigen_sym(&a) {
        Ok(_) => { return false; }
        Err(_) => { return true; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_eigen_sym_1x1() -> Bool {
  match openblas.matrix_create(1, 1) {
    Ok(a) => {
      var ha = a;
      openblas.matrix_set(&mut ha, 0, 0, 42.0);
      match openblas.eigen_sym(&ha) {
        Ok((vals, vecs)) => {
          var v_rows = openblas.matrix_rows(&vals);
          var vec_rows = openblas.matrix_rows(&vecs);
          openblas.matrix_free(vals);
          openblas.matrix_free(vecs);
          return v_rows == 1 && vec_rows == 1;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 7 -- LAPACK: linear solve
// ============================================================

fn test_solve_square_ok() -> Bool {
  match openblas.matrix_create(3, 3) {
    Ok(a) => {
      var ha = a;
      openblas.matrix_set(&mut ha, 0, 0, 1.0);
      openblas.matrix_set(&mut ha, 1, 1, 1.0);
      openblas.matrix_set(&mut ha, 2, 2, 1.0);
      var b = [1.0, 2.0, 3.0];
      match openblas.solve(&ha, &b) {
        Ok(x) => {
          var x_rows = openblas.matrix_rows(&x);
          var x_cols = openblas.matrix_cols(&x);
          openblas.matrix_free(x);
          return x_rows == 3 && x_cols == 1;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_solve_rejects_nonsquare() -> Bool {
  match openblas.matrix_create(3, 2) {
    Ok(a) => {
      var b = [1.0, 2.0, 3.0];
      match openblas.solve(&a, &b) {
        Ok(_) => { return false; }
        Err(_) => { return true; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_solve_dimension_mismatch() -> Bool {
  match openblas.matrix_create(3, 3) {
    Ok(a) => {
      var b = [1.0, 2.0];
      match openblas.solve(&a, &b) {
        Ok(_) => { return false; }
        Err(_) => { return true; }
      }
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 8 -- Test runner
// ============================================================

fn main() -> Int {
  if !test_matrix_create_valid() { return 1; }
  if !test_matrix_create_zero_rows() { return 2; }
  if !test_matrix_create_zero_cols() { return 3; }
  if !test_matrix_create_negative_dims() { return 4; }
  if !test_matrix_create_1x1() { return 5; }
  if !test_matrix_get_default_zeros() { return 6; }
  if !test_matrix_get_set_roundtrip() { return 7; }
  if !test_matrix_get_out_of_bounds() { return 8; }
  if !test_matrix_set_out_of_bounds_noop() { return 9; }
  if !test_matrix_multiple_independent() { return 10; }
  if !test_matrix_free_releases() { return 11; }
  if !test_matrix_large_allocation() { return 12; }
  if !test_dot_product_basic() { return 13; }
  if !test_dot_product_single_element() { return 14; }
  if !test_dot_product_with_zeros() { return 15; }
  if !test_dot_product_negative_elements() { return 16; }
  if !test_axpy_basic() { return 17; }
  if !test_axpy_zero_alpha() { return 18; }
  if !test_axpy_negative_alpha() { return 19; }
  if !test_gemv_no_transpose() { return 20; }
  if !test_gemv_with_beta() { return 21; }
  if !test_gemm_2x2_identity() { return 22; }
  if !test_gemm_zero_beta() { return 23; }
  if !test_svd_returns_ok() { return 24; }
  if !test_svd_correct_shapes() { return 25; }
  if !test_svd_tall_matrix() { return 26; }
  if !test_eigen_sym_square_ok() { return 27; }
  if !test_eigen_sym_rejects_rectangular() { return 28; }
  if !test_eigen_sym_1x1() { return 29; }
  if !test_solve_square_ok() { return 30; }
  if !test_solve_rejects_nonsquare() { return 31; }
  if !test_solve_dimension_mismatch() { return 32; }
  return 0;
}
