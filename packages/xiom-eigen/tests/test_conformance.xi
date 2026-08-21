// XIOM -- xiom.eigen conformance test suite
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 21 tests covering: matrix lifecycle, get/set roundtrip,
// matrix algebra (multiply, transpose), decomposition stubs
// (determinant, inverse, solve, SVD, eigenvalues), and error handling.
// Returns 0 on full pass, nonzero on first failure.

module xiom.eigen.test_conformance
use xiom.eigen;

// ============================================================
// Section 1 -- Matrix lifecycle
// ============================================================

fn test_matrix_create_valid() -> Bool {
  match eigen.matrix_create(3, 4) {
    Ok(m) => {
      return eigen.matrix_rows(&m) == 3 && eigen.matrix_cols(&m) == 4;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_create_zero_rows() -> Bool {
  match eigen.matrix_create(0, 5) {
    Ok(_) => { return false; }
    Err(_) => { return true; }
  }
}

fn test_matrix_create_zero_cols() -> Bool {
  match eigen.matrix_create(5, 0) {
    Ok(_) => { return false; }
    Err(_) => { return true; }
  }
}

fn test_matrix_create_negative_dims() -> Bool {
  match eigen.matrix_create(-1, 5) {
    Ok(_) => { return false; }
    Err(_) => { return true; }
  }
}

fn test_matrix_create_1x1() -> Bool {
  match eigen.matrix_create(1, 1) {
    Ok(m) => {
      return eigen.matrix_rows(&m) == 1 && eigen.matrix_cols(&m) == 1;
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 2 -- Element access
// ============================================================

fn test_matrix_get_default_zeros() -> Bool {
  match eigen.matrix_create(2, 3) {
    Ok(m) => {
      return eigen.matrix_get(&m, 0, 0) == 0.0 &&
             eigen.matrix_get(&m, 0, 1) == 0.0 &&
             eigen.matrix_get(&m, 1, 2) == 0.0;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_get_set_roundtrip() -> Bool {
  match eigen.matrix_create(3, 3) {
    Ok(mut m) => {
      eigen.matrix_set(&mut m, 0, 0, 1.0);
      eigen.matrix_set(&mut m, 1, 1, 2.0);
      eigen.matrix_set(&mut m, 2, 2, 3.0);
      return eigen.matrix_get(&m, 0, 0) == 1.0 &&
             eigen.matrix_get(&m, 1, 1) == 2.0 &&
             eigen.matrix_get(&m, 2, 2) == 3.0;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_get_set_diagonal() -> Bool {
  match eigen.matrix_create(4, 4) {
    Ok(mut m) => {
      eigen.matrix_set(&mut m, 0, 0, 5.0);
      eigen.matrix_set(&mut m, 1, 1, 7.0);
      eigen.matrix_set(&mut m, 3, 3, 11.0);
      return eigen.matrix_get(&m, 0, 0) == 5.0 &&
             eigen.matrix_get(&m, 1, 1) == 7.0 &&
             eigen.matrix_get(&m, 3, 3) == 11.0 &&
             eigen.matrix_get(&m, 0, 3) == 0.0;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_get_out_of_bounds() -> Bool {
  match eigen.matrix_create(2, 2) {
    Ok(m) => {
      return eigen.matrix_get(&m, 3, 0) == 0.0 &&
             eigen.matrix_get(&m, 0, 3) == 0.0;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_get_negative_indices() -> Bool {
  match eigen.matrix_create(2, 2) {
    Ok(m) => {
      return eigen.matrix_get(&m, -1, 0) == 0.0 &&
             eigen.matrix_get(&m, 0, -1) == 0.0;
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_rows_cols() -> Bool {
  match eigen.matrix_create(7, 11) {
    Ok(m) => {
      return eigen.matrix_rows(&m) == 7 && eigen.matrix_cols(&m) == 11;
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 3 -- Matrix algebra
// ============================================================

fn test_matrix_multiply_square() -> Bool {
  match eigen.matrix_create(2, 2) {
    Ok(mut a) => {
      eigen.matrix_set(&mut a, 0, 0, 1.0);
      eigen.matrix_set(&mut a, 0, 1, 2.0);
      eigen.matrix_set(&mut a, 1, 0, 3.0);
      eigen.matrix_set(&mut a, 1, 1, 4.0);
      match eigen.matrix_create(2, 2) {
        Ok(mut b) => {
          eigen.matrix_set(&mut b, 0, 0, 2.0);
          eigen.matrix_set(&mut b, 0, 1, 0.0);
          eigen.matrix_set(&mut b, 1, 0, 1.0);
          eigen.matrix_set(&mut b, 1, 1, 2.0);
          match eigen.matrix_multiply(&a, &b) {
            Ok(c) => {
              return eigen.matrix_get(&c, 0, 0) == 4.0 &&
                     eigen.matrix_get(&c, 0, 1) == 4.0 &&
                     eigen.matrix_get(&c, 1, 0) == 10.0 &&
                     eigen.matrix_get(&c, 1, 1) == 8.0;
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

fn test_matrix_multiply_dimension_mismatch() -> Bool {
  match eigen.matrix_create(2, 3) {
    Ok(a) => {
      match eigen.matrix_create(4, 2) {
        Ok(b) => {
          match eigen.matrix_multiply(&a, &b) {
            Ok(_) => { return false; }
            Err(_) => { return true; }
          }
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_transpose_square() -> Bool {
  match eigen.matrix_create(2, 2) {
    Ok(mut m) => {
      eigen.matrix_set(&mut m, 0, 1, 5.0);
      eigen.matrix_set(&mut m, 1, 0, 3.0);
      match eigen.matrix_transpose(&m) {
        Ok(t) => {
          return eigen.matrix_rows(&t) == 2 &&
                 eigen.matrix_cols(&t) == 2 &&
                 eigen.matrix_get(&t, 0, 1) == 3.0 &&
                 eigen.matrix_get(&t, 1, 0) == 5.0;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_transpose_rectangular() -> Bool {
  match eigen.matrix_create(3, 2) {
    Ok(m) => {
      match eigen.matrix_transpose(&m) {
        Ok(t) => {
          return eigen.matrix_rows(&t) == 2 && eigen.matrix_cols(&t) == 3;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 4 -- Determinant
// ============================================================

fn test_matrix_determinant_identity() -> Bool {
  match eigen.matrix_create(3, 3) {
    Ok(mut m) => {
      eigen.matrix_set(&mut m, 0, 0, 1.0);
      eigen.matrix_set(&mut m, 1, 1, 1.0);
      eigen.matrix_set(&mut m, 2, 2, 1.0);
      match eigen.matrix_determinant(&m) {
        Ok(d) => { return d == 1.0; }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_determinant_zero() -> Bool {
  match eigen.matrix_create(2, 2) {
    Ok(m) => {
      match eigen.matrix_determinant(&m) {
        Ok(d) => { return d == 0.0; }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_determinant_rectangular() -> Bool {
  match eigen.matrix_create(2, 3) {
    Ok(m) => {
      match eigen.matrix_determinant(&m) {
        Ok(_) => { return false; }
        Err(_) => { return true; }
      }
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 5 -- Inverse
// ============================================================

fn test_matrix_inverse_identity() -> Bool {
  match eigen.matrix_create(3, 3) {
    Ok(mut m) => {
      eigen.matrix_set(&mut m, 0, 0, 1.0);
      eigen.matrix_set(&mut m, 1, 1, 1.0);
      eigen.matrix_set(&mut m, 2, 2, 1.0);
      match eigen.matrix_inverse(&m) {
        Ok(inv) => {
          return eigen.matrix_get(&inv, 0, 0) == 1.0 &&
                 eigen.matrix_get(&inv, 1, 1) == 1.0 &&
                 eigen.matrix_get(&inv, 2, 2) == 1.0;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_matrix_inverse_singular() -> Bool {
  match eigen.matrix_create(2, 2) {
    Ok(m) => {
      match eigen.matrix_inverse(&m) {
        Ok(_) => { return false; }
        Err(_) => { return true; }
      }
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 6 -- Linear solve
// ============================================================

fn test_solve_identity_system() -> Bool {
  match eigen.matrix_create(2, 2) {
    Ok(mut a) => {
      eigen.matrix_set(&mut a, 0, 0, 1.0);
      eigen.matrix_set(&mut a, 1, 1, 1.0);
      var b = [5.0, 3.0];
      match eigen.solve(&a, &b) {
        Ok(x) => {
          return x[0] == 5.0 && x[1] == 3.0;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_solve_rejects_nonsquare() -> Bool {
  match eigen.matrix_create(3, 2) {
    Ok(a) => {
      var b = [1.0, 2.0, 3.0];
      match eigen.solve(&a, &b) {
        Ok(_) => { return false; }
        Err(_) => { return true; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_solve_dimension_mismatch() -> Bool {
  match eigen.matrix_create(3, 3) {
    Ok(mut a) => {
      eigen.matrix_set(&mut a, 0, 0, 1.0);
      eigen.matrix_set(&mut a, 1, 1, 1.0);
      eigen.matrix_set(&mut a, 2, 2, 1.0);
      var b = [1.0, 2.0];
      match eigen.solve(&a, &b) {
        Ok(_) => { return false; }
        Err(_) => { return true; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_solve_singular_matrix() -> Bool {
  match eigen.matrix_create(2, 2) {
    Ok(a) => {
      var b = [1.0, 2.0];
      match eigen.solve(&a, &b) {
        Ok(_) => { return false; }
        Err(_) => { return true; }
      }
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 7 -- SVD
// ============================================================

fn test_svd_returns_ok() -> Bool {
  match eigen.matrix_create(3, 3) {
    Ok(mut m) => {
      eigen.matrix_set(&mut m, 0, 0, 1.0);
      eigen.matrix_set(&mut m, 1, 1, 1.0);
      eigen.matrix_set(&mut m, 2, 2, 1.0);
      match eigen.svd(&m) {
        Ok(_) => { return true; }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_svd_correct_shapes() -> Bool {
  match eigen.matrix_create(4, 3) {
    Ok(mut m) => {
      eigen.matrix_set(&mut m, 0, 0, 1.0);
      match eigen.svd(&m) {
        Ok((u, s, vt)) => {
          return eigen.matrix_rows(&u) == 4 &&
                 eigen.matrix_cols(&u) == 3 &&
                 eigen.matrix_rows(&s) == 3 &&
                 eigen.matrix_cols(&s) == 3 &&
                 eigen.matrix_rows(&vt) == 3 &&
                 eigen.matrix_cols(&vt) == 3;
        }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Section 8 -- Eigenvalues
// ============================================================

fn test_eigenvalues_square_ok() -> Bool {
  match eigen.matrix_create(3, 3) {
    Ok(mut m) => {
      eigen.matrix_set(&mut m, 0, 0, 1.0);
      eigen.matrix_set(&mut m, 1, 1, 1.0);
      eigen.matrix_set(&mut m, 2, 2, 1.0);
      match eigen.eigenvalues(&m) {
        Ok(_) => { return true; }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return false; }
  }
}

fn test_eigenvalues_rejects_rectangular() -> Bool {
  match eigen.matrix_create(3, 2) {
    Ok(m) => {
      match eigen.eigenvalues(&m) {
        Ok(_) => { return false; }
        Err(_) => { return true; }
      }
    }
    Err(_) => { return false; }
  }
}

// ============================================================
// Test runner
// ============================================================

fn main() -> Int {
  if !test_matrix_create_valid() { return 1; }
  if !test_matrix_create_zero_rows() { return 2; }
  if !test_matrix_create_zero_cols() { return 3; }
  if !test_matrix_create_negative_dims() { return 4; }
  if !test_matrix_create_1x1() { return 5; }
  if !test_matrix_get_default_zeros() { return 6; }
  if !test_matrix_get_set_roundtrip() { return 7; }
  if !test_matrix_get_set_diagonal() { return 8; }
  if !test_matrix_get_out_of_bounds() { return 9; }
  if !test_matrix_get_negative_indices() { return 10; }
  if !test_matrix_rows_cols() { return 11; }
  if !test_matrix_multiply_square() { return 12; }
  if !test_matrix_multiply_dimension_mismatch() { return 13; }
  if !test_matrix_transpose_square() { return 14; }
  if !test_matrix_transpose_rectangular() { return 15; }
  if !test_matrix_determinant_identity() { return 16; }
  if !test_matrix_determinant_zero() { return 17; }
  if !test_matrix_determinant_rectangular() { return 18; }
  if !test_matrix_inverse_identity() { return 19; }
  if !test_matrix_inverse_singular() { return 20; }
  if !test_solve_identity_system() { return 21; }
  if !test_solve_rejects_nonsquare() { return 22; }
  if !test_solve_dimension_mismatch() { return 23; }
  if !test_solve_singular_matrix() { return 24; }
  if !test_svd_returns_ok() { return 25; }
  if !test_svd_correct_shapes() { return 26; }
  if !test_eigenvalues_square_ok() { return 27; }
  if !test_eigenvalues_rejects_rectangular() { return 28; }
  return 0;
}
