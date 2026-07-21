module blas_tests
use xiom.test;
use xiom.blas;

fn test_matrix_new() -> TestResult {
  let m = matrix_new(3, 4);
  return assert(m.rows == 3 && m.cols == 4, "blas: matrix dimensions");
}

fn test_matrix_zeros() -> TestResult {
  let m = matrix_zeros(2, 2);
  return assert(m.rows == 2, "blas: zeros created");
}

fn test_matrix_identity() -> TestResult {
  let m = matrix_identity(3);
  return assert(m.rows == 3 && m.cols == 3, "blas: identity dimensions");
}

fn test_matrix_transpose() -> TestResult {
  let a = matrix_new(2, 3);
  let b = matrix_transpose(&a);
  return assert(b.rows == 3 && b.cols == 2, "blas: transpose dimensions");
}

fn test_vector_zeros() -> TestResult {
  let v = vector_zeros(5);
  return assert(v.len() == 5, "blas: vector zeros length");
}

fn main() -> Int {
  var tests = [test_matrix_new, test_matrix_zeros, test_matrix_identity, test_matrix_transpose, test_vector_zeros];
  return test.run_all(tests);
}
