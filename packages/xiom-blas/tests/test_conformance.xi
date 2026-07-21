module conformance_tests
use xiom.test;
use xiom.blas;
use xiom.blas.linalg;

fn test_blas_matrix_new() -> TestResult {
  let m = matrix_new(3, 4);
  return assert(m.rows == 3 && m.cols == 4 && m.data.len() == 12, "blas: matrix_new dimensions");
}

fn test_blas_matrix_zeros() -> TestResult {
  let m = matrix_zeros(2, 2);
  return assert(m.rows == 2 && m.cols == 2 && m.data[0] == 0.0, "blas: matrix_zeros zero-filled");
}

fn test_blas_matrix_identity() -> TestResult {
  let m = matrix_identity(3);
  return assert(
    m.data[0] == 1.0 && m.data[1] == 0.0 && m.data[2] == 0.0 &&
    m.data[3] == 0.0 && m.data[4] == 1.0 && m.data[5] == 0.0 &&
    m.data[6] == 0.0 && m.data[7] == 0.0 && m.data[8] == 1.0,
    "blas: matrix_identity diagonal=1 off-diagonal=0"
  );
}

fn test_blas_matrix_transpose() -> TestResult {
  let m = matrix_new(2, 3);
  let mt = matrix_transpose(&m);
  return assert(mt.rows == 3 && mt.cols == 2, "blas: matrix_transpose rows/cols swapped");
}

fn test_blas_matrix_add() -> TestResult {
  let a = matrix_identity(2);
  let b = matrix_identity(2);
  let r = matrix_add(&a, &b);
  if r.is_err() { return assert(false, "blas: matrix_add should not fail"); };
  let s = r.unwrap();
  return assert(s.data[0] == 2.0 && s.data[1] == 0.0 && s.data[2] == 0.0 && s.data[3] == 2.0, "blas: matrix_add element-wise");
}

fn test_blas_matrix_sub() -> TestResult {
  let a = matrix_identity(2);
  let b = matrix_identity(2);
  let r = matrix_sub(&a, &b);
  if r.is_err() { return assert(false, "blas: matrix_sub should not fail"); };
  let s = r.unwrap();
  return assert(s.data[0] == 0.0 && s.data[1] == 0.0 && s.data[2] == 0.0 && s.data[3] == 0.0, "blas: matrix_sub element-wise");
}

fn test_blas_vector_zeros() -> TestResult {
  let v = vector_zeros(5);
  return assert(v.len() == 5 && v[0] == 0.0 && v[4] == 0.0, "blas: vector_zeros length and content");
}

fn test_blas_vector_ones() -> TestResult {
  let v = vector_ones(3);
  return assert(v.len() == 3 && v[0] == 1.0 && v[1] == 1.0 && v[2] == 1.0, "blas: vector_ones length and content");
}

fn test_blas_matrix_add_dimension_mismatch() -> TestResult {
  let a = matrix_new(2, 3);
  let b = matrix_new(3, 2);
  let r = matrix_add(&a, &b);
  return assert(r.is_err(), "blas: matrix_add dimension mismatch returns Err");
}

fn test_blas_matrix_sub_dimension_mismatch() -> TestResult {
  let a = matrix_new(2, 3);
  let b = matrix_new(3, 2);
  let r = matrix_sub(&a, &b);
  return assert(r.is_err(), "blas: matrix_sub dimension mismatch returns Err");
}

fn test_linalg_matrix_new() -> TestResult {
  let m = linalg.matrix_new(4, 5);
  return assert(m.rows == 4 && m.cols == 5 && m.data.len() == 20, "linalg: matrix_new dimensions");
}

fn test_linalg_identity() -> TestResult {
  let m = linalg.identity(4);
  return assert(
    m.rows == 4 && m.cols == 4 &&
    m.data[0] == 1.0 && m.data[3] == 0.0 && m.data[5] == 1.0 && m.data[15] == 1.0,
    "linalg: identity diagonal and dimensions"
  );
}

fn test_linalg_matrix_get() -> TestResult {
  let m = linalg.matrix_new(3, 3);
  linalg.matrix_set(&m, 1, 1, 42.0);
  return assert(linalg.matrix_get(&m, 1, 1) == 42.0, "linalg: matrix_get after matrix_set round-trip");
}

fn test_linalg_matrix_add() -> TestResult {
  let a = linalg.identity(3);
  let b = linalg.identity(3);
  let r = linalg.matrix_add(&a, &b);
  if r.is_err() { return assert(false, "linalg: matrix_add should not fail"); };
  let s = r.unwrap();
  return assert(s.data[0] == 2.0 && s.data[4] == 2.0 && s.data[8] == 2.0, "linalg: matrix_add doubles identity");
}

fn test_linalg_matrix_sub() -> TestResult {
  let a = linalg.identity(2);
  let b = linalg.identity(2);
  let r = linalg.matrix_sub(&a, &b);
  if r.is_err() { return assert(false, "linalg: matrix_sub should not fail"); };
  let s = r.unwrap();
  return assert(s.data[0] == 0.0 && s.data[3] == 0.0, "linalg: matrix_sub subtracts identity to zero");
}

fn test_linalg_matrix_scale() -> TestResult {
  let m = linalg.identity(2);
  let s = linalg.matrix_scale(&m, 3.0);
  return assert(s.data[0] == 3.0 && s.data[1] == 0.0 && s.data[2] == 0.0 && s.data[3] == 3.0, "linalg: matrix_scale multiplies diagonal");
}

fn test_linalg_matrix_transpose() -> TestResult {
  let m = linalg.matrix_new(3, 2);
  linalg.matrix_set(&m, 0, 1, 5.0);
  let t = linalg.matrix_transpose(&m);
  return assert(t.rows == 2 && t.cols == 3 && linalg.matrix_get(&t, 1, 0) == 5.0, "linalg: matrix_transpose dimensions and element swap");
}

fn test_linalg_vector_dot() -> TestResult {
  let a = vector_ones(3);
  let b = vector_ones(3);
  return assert(linalg.vector_dot(&a, &b) == 3.0, "linalg: vector_dot of ones equals len");
}

fn test_linalg_matrix_determinant_identity() -> TestResult {
  let m = linalg.identity(3);
  return assert(linalg.matrix_determinant(&m) == 1.0, "linalg: determinant of identity is 1");
}

fn test_linalg_matrix_determinant_zero() -> TestResult {
  let m = linalg.matrix_new(2, 2);
  return assert(linalg.matrix_determinant(&m) == 0.0, "linalg: determinant of zero matrix is 0");
}

fn test_linalg_matrix_inverse_identity() -> TestResult {
  let m = linalg.identity(3);
  let r = linalg.matrix_inverse(&m);
  if r.is_err() { return assert(false, "linalg: matrix_inverse of identity should succeed"); };
  let inv = r.unwrap();
  return assert(
    linalg.matrix_get(&inv, 0, 0) == 1.0 &&
    linalg.matrix_get(&inv, 1, 1) == 1.0 &&
    linalg.matrix_get(&inv, 2, 2) == 1.0,
    "linalg: inverse of identity is identity"
  );
}

fn test_linalg_matrix_inverse_singular() -> TestResult {
  let m = linalg.matrix_new(2, 2);
  let r = linalg.matrix_inverse(&m);
  return assert(r.is_err(), "linalg: matrix_inverse of singular matrix returns Err");
}

fn test_linalg_solve_linear_system() -> TestResult {
  let a = linalg.identity(3);
  var b = vector_ones(3);
  b[2] = 7.0;
  let r = linalg.solve_linear_system(&a, &b);
  if r.is_err() { return assert(false, "linalg: solve of identity system should succeed"); };
  let x = r.unwrap();
  return assert(x[0] == 1.0 && x[1] == 1.0 && x[2] == 7.0, "linalg: solve x = b for identity A");
}

fn test_linalg_solve_singular() -> TestResult {
  let a = linalg.matrix_new(2, 2);
  let b = vector_ones(2);
  let r = linalg.solve_linear_system(&a, &b);
  return assert(r.is_err(), "linalg: solve of singular matrix returns Err");
}

fn test_linalg_matrix_multiply_identity() -> TestResult {
  let a = linalg.identity(3);
  let b = linalg.identity(3);
  let r = linalg.matrix_multiply(&a, &b);
  if r.is_err() { return assert(false, "linalg: matrix_multiply of identity should succeed"); };
  let p = r.unwrap();
  return assert(
    p.rows == 3 && p.cols == 3 &&
    linalg.matrix_get(&p, 0, 0) == 1.0 &&
    linalg.matrix_get(&p, 1, 1) == 1.0 &&
    linalg.matrix_get(&p, 2, 2) == 1.0,
    "linalg: matrix_multiply identity * identity = identity"
  );
}

fn test_linalg_matrix_vector_multiply() -> TestResult {
  let a = linalg.identity(2);
  var v = vector_ones(2);
  v[1] = 3.0;
  let r = linalg.matrix_vector_multiply(&a, &v);
  if r.is_err() { return assert(false, "linalg: matrix_vector_multiply of identity should succeed"); };
  let x = r.unwrap();
  return assert(x[0] == 1.0 && x[1] == 3.0, "linalg: identity * vec = vec");
}

fn main() -> Int {
  var tests = [
    test_blas_matrix_new,
    test_blas_matrix_zeros,
    test_blas_matrix_identity,
    test_blas_matrix_transpose,
    test_blas_matrix_add,
    test_blas_matrix_sub,
    test_blas_vector_zeros,
    test_blas_vector_ones,
    test_blas_matrix_add_dimension_mismatch,
    test_blas_matrix_sub_dimension_mismatch,
    test_linalg_matrix_new,
    test_linalg_identity,
    test_linalg_matrix_get,
    test_linalg_matrix_add,
    test_linalg_matrix_sub,
    test_linalg_matrix_scale,
    test_linalg_matrix_transpose,
    test_linalg_vector_dot,
    test_linalg_matrix_determinant_identity,
    test_linalg_matrix_determinant_zero,
    test_linalg_matrix_inverse_identity,
    test_linalg_matrix_inverse_singular,
    test_linalg_solve_linear_system,
    test_linalg_solve_singular,
    test_linalg_matrix_multiply_identity,
    test_linalg_matrix_vector_multiply,
  ];
  return test.run_all(tests);
}
