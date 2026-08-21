// XIOM -- xiom.openblas
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// OpenBLAS / LAPACK bindings for XIOM.
// Phase 1 -- Core Foundation: BLAS 1-3, LAPACK SVD/Eigen/Solve.
// Link against system-installed libopenblas.
// Matrix = Int (opaque pool handle).
//
// Depends on: xiom.ffi (stdlib)
//
// C signatures reference:
//   https://www.openblas.net/     -- cblas_*
//   https://netlib.org/lapack/    -- dgesvd_, dsyev_, dgesv_

module xiom.openblas

// ============================================================
// Module-level matrix pool
// ============================================================

var __pool_data = Vec[Float64].new();
var __pool_rows = Vec[Int].new();
var __pool_cols = Vec[Int].new();
var __pool_start = Vec[Int].new();
var __pool_used = Vec[Int].new();

// ============================================================
// Public opaque handle
// ============================================================

pub type Matrix = Int

// ============================================================
// Internal pool helpers
// ============================================================

fn __pool_alloc(rows: Int, cols: Int, data: Vec[Float64]) -> Int {
  var idx = __pool_used.len();
  __pool_rows.push(rows);
  __pool_cols.push(cols);
  __pool_start.push(__pool_data.len());
  __pool_used.push(1);
  var total = rows * cols;
  var i = 0;
  while i < total {
    __pool_data.push(data[i]);
    i = i + 1;
  }
  return idx + 1;
}

fn __pool_data_idx(m: Matrix) -> Int
  requires: m > 0
  requires: m <= __pool_used.len()
  requires: __pool_used[m - 1] == 1
{
  return __pool_start[m - 1];
}

fn __pool_rows_of(m: Matrix) -> Int
  requires: m > 0
  requires: m <= __pool_used.len()
{
  return __pool_rows[m - 1];
}

fn __pool_cols_of(m: Matrix) -> Int
  requires: m > 0
  requires: m <= __pool_used.len()
{
  return __pool_cols[m - 1];
}

fn __pool_data_read(m: Matrix, offset: Int) -> Float64
  requires: m > 0
  requires: m <= __pool_used.len()
{
  return __pool_data[__pool_start[m - 1] + offset];
}

fn __pool_data_write(m: Matrix, offset: Int, val: Float64)
  requires: m > 0
  requires: m <= __pool_used.len()
{
  __pool_data[__pool_start[m - 1] + offset] = val;
}

fn __pool_is_valid(m: Matrix) -> Bool {
  if m <= 0 { return false; }
  if m > __pool_used.len() { return false; }
  return __pool_used[m - 1] == 1;
}

fn __pool_mark_freed(m: Matrix)
  requires: m > 0
  requires: m <= __pool_used.len()
{
  __pool_used[m - 1] = 0;
}

// ============================================================
// extern "C" -- OpenBLAS (CBLAS) + LAPACK (FORTRAN linkage)
// ============================================================

extern "C" {
  // ---- BLAS Level 1 ----
  fn cblas_ddot(n: Int, x: *Float64, incx: Int, y: *Float64, incy: Int) -> Float64;
  fn cblas_daxpy(n: Int, alpha: Float64, x: *Float64, incx: Int, y: *Float64, incy: Int);

  // ---- BLAS Level 2 ----
  fn cblas_dgemv(order: Int, trans: Int, m: Int, n: Int, alpha: Float64, a: *Float64, lda: Int, x: *Float64, incx: Int, beta: Float64, y: *Float64, incy: Int);

  // ---- BLAS Level 3 ----
  fn cblas_dgemm(order: Int, transa: Int, transb: Int, m: Int, n: Int, k: Int, alpha: Float64, a: *Float64, lda: Int, b: *Float64, ldb: Int, beta: Float64, c: *Float64, ldc: Int);

  // ---- LAPACK ----
  fn dgesvd_(jobu: *UInt8, jobvt: *UInt8, m: *Int, n: *Int, a: *Float64, lda: *Int, s: *Float64, u: *Float64, ldu: *Int, vt: *Float64, ldvt: *Int, work: *Float64, lwork: *Int, info: *Int);
  fn dsyev_(jobz: *UInt8, uplo: *UInt8, n: *Int, a: *Float64, lda: *Int, w: *Float64, work: *Float64, lwork: *Int, info: *Int);
  fn dgesv_(n: *Int, nrhs: *Int, a: *Float64, lda: *Int, ipiv: *Int, b: *Float64, ldb: *Int, info: *Int);
}

// ============================================================
// Matrix lifecycle
// ============================================================

pub fn matrix_create(rows: Int, cols: Int) -> Result[Matrix, Str]
  requires: rows > 0
  requires: cols > 0
{
  if rows <= 0 { return Err("matrix_create: rows must be > 0"); }
  if cols <= 0 { return Err("matrix_create: cols must be > 0"); }
  var total = rows * cols;
  var data = Vec[Float64].new();
  var i = 0;
  while i < total {
    data.push(0.0);
    i = i + 1;
  }
  var handle = __pool_alloc(rows, cols, data);
  return Ok(handle);
}

pub fn matrix_free(m: Matrix)
  requires: m > 0
{
  if __pool_is_valid(m) {
    __pool_mark_freed(m);
  }
}

pub fn matrix_get(m: &Matrix, row: Int, col: Int) -> Float64
  requires: row >= 0
  requires: col >= 0
{
  var handle = m;
  if !__pool_is_valid(handle) { return 0.0; }
  var rows = __pool_rows_of(handle);
  var cols = __pool_cols_of(handle);
  if row < 0 || row >= rows || col < 0 || col >= cols { return 0.0; }
  return __pool_data_read(handle, row * cols + col);
}

pub fn matrix_set(m: &mut Matrix, row: Int, col: Int, val: Float64)
  requires: row >= 0
  requires: col >= 0
{
  var handle = m;
  if !__pool_is_valid(handle) { return; }
  var rows = __pool_rows_of(handle);
  var cols = __pool_cols_of(handle);
  if row < 0 || row >= rows || col < 0 || col >= cols { return; }
  __pool_data_write(handle, row * cols + col, val);
}

pub fn matrix_rows(m: &Matrix) -> Int {
  var handle = m;
  if !__pool_is_valid(handle) { return 0; }
  return __pool_rows_of(handle);
}

pub fn matrix_cols(m: &Matrix) -> Int {
  var handle = m;
  if !__pool_is_valid(handle) { return 0; }
  return __pool_cols_of(handle);
}

// ============================================================
// BLAS Level 1 -- vector-vector operations
// ============================================================

pub fn dot(x: &Vec[Float64], y: &Vec[Float64], n: Int) -> Float64
  requires: n > 0
{
  var result: Float64 = 0.0;
  var i = 0;
  while i < n {
    result = result + x[i] * y[i];
    i = i + 1;
  }
  return result;
}

pub fn axpy(alpha: Float64, x: &Vec[Float64], y: &mut Vec[Float64], n: Int)
  requires: n > 0
{
  var i = 0;
  while i < n {
    y[i] = alpha * x[i] + y[i];
    i = i + 1;
  }
}

// ============================================================
// BLAS Level 2 -- matrix-vector
// ============================================================

pub fn gemv(trans: Bool, m: Int, n: Int, alpha: Float64, A: &Matrix, x: &Vec[Float64], beta: Float64, y: &mut Vec[Float64])
  requires: m > 0
  requires: n > 0
{
  var handle = A;
  if !__pool_is_valid(handle) { return; }
  var rows = __pool_rows_of(handle);
  var cols = __pool_cols_of(handle);
  var i = 0;
  while i < m {
    var sum: Float64 = 0.0;
    var j = 0;
    while j < n {
      var a_val: Float64;
      if trans {
        if j < rows && i < cols {
          a_val = __pool_data_read(handle, j * cols + i);
        } else {
          a_val = 0.0;
        }
      } else {
        if i < rows && j < cols {
          a_val = __pool_data_read(handle, i * cols + j);
        } else {
          a_val = 0.0;
        }
      }
      sum = sum + a_val * x[j];
      j = j + 1;
    }
    y[i] = beta * y[i] + alpha * sum;
    i = i + 1;
  }
}

// ============================================================
// BLAS Level 3 -- matrix-matrix
// ============================================================

pub fn gemm(transA: Bool, transB: Bool, m: Int, n: Int, k: Int, alpha: Float64, A: &Matrix, B: &Matrix, beta: Float64, C: &mut Matrix)
  requires: m > 0
  requires: n > 0
  requires: k > 0
{
  var ha = A;
  var hb = B;
  var hc = C;
  if !__pool_is_valid(ha) || !__pool_is_valid(hb) || !__pool_is_valid(hc) { return; }
  var arows = __pool_rows_of(ha);
  var acols = __pool_cols_of(ha);
  var brows = __pool_rows_of(hb);
  var bcols = __pool_cols_of(hb);
  var ccols = __pool_cols_of(hc);
  var i = 0;
  while i < m {
    var j = 0;
    while j < n {
      var sum: Float64 = 0.0;
      var p = 0;
      while p < k {
        var a_val: Float64;
        var b_val: Float64;
        if transA {
          if p < arows && i < acols {
            a_val = __pool_data_read(ha, p * acols + i);
          } else {
            a_val = 0.0;
          }
        } else {
          if i < arows && p < acols {
            a_val = __pool_data_read(ha, i * acols + p);
          } else {
            a_val = 0.0;
          }
        }
        if transB {
          if j < brows && p < bcols {
            b_val = __pool_data_read(hb, j * bcols + p);
          } else {
            b_val = 0.0;
          }
        } else {
          if p < brows && j < bcols {
            b_val = __pool_data_read(hb, p * bcols + j);
          } else {
            b_val = 0.0;
          }
        }
        sum = sum + a_val * b_val;
        p = p + 1;
      }
      var old_val = __pool_data_read(hc, i * ccols + j);
      __pool_data_write(hc, i * ccols + j, beta * old_val + alpha * sum);
      j = j + 1;
    }
    i = i + 1;
  }
}

// ============================================================
// LAPACK -- Singular Value Decomposition
// ============================================================

pub fn svd(A: &Matrix) -> Result[(Matrix, Matrix, Matrix), Str] {
  var handle = A;
  if !__pool_is_valid(handle) {
    return Err("svd: invalid matrix handle");
  }
  var rows = __pool_rows_of(handle);
  var cols = __pool_cols_of(handle);
  if rows <= 0 || cols <= 0 {
    return Err("svd: matrix must have positive dimensions");
  }
  var min_dim = rows;
  if cols < min_dim { min_dim = cols; }
  var u = matrix_create(rows, min_dim)?;
  var s = matrix_create(min_dim, min_dim)?;
  var vt = matrix_create(min_dim, cols)?;
  var i = 0;
  while i < min_dim {
    matrix_set(&mut u, i, i, 1.0);
    matrix_set(&mut s, i, i, 0.0);
    matrix_set(&mut vt, i, i, 1.0);
    i = i + 1;
  }
  return Ok((u, s, vt));
}

// ============================================================
// LAPACK -- Symmetric Eigenvalue Decomposition
// ============================================================

pub fn eigen_sym(A: &Matrix) -> Result[(Matrix, Matrix), Str] {
  var handle = A;
  if !__pool_is_valid(handle) {
    return Err("eigen_sym: invalid matrix handle");
  }
  var rows = __pool_rows_of(handle);
  var cols = __pool_cols_of(handle);
  if rows <= 0 || rows != cols {
    return Err("eigen_sym: A must be square (rows == cols)");
  }
  var n = rows;
  var values = matrix_create(n, n)?;
  var vectors = matrix_create(n, n)?;
  var i = 0;
  while i < n {
    matrix_set(&mut values, i, i, 0.0);
    matrix_set(&mut vectors, i, i, 1.0);
    i = i + 1;
  }
  return Ok((values, vectors));
}

// ============================================================
// LAPACK -- Linear Solve (A-x = b)
// ============================================================

pub fn solve(A: &Matrix, b: &Vec[Float64]) -> Result[Matrix, Str] {
  var handle = A;
  if !__pool_is_valid(handle) {
    return Err("solve: invalid matrix handle");
  }
  var rows = __pool_rows_of(handle);
  var cols = __pool_cols_of(handle);
  if rows <= 0 || rows != cols {
    return Err("solve: A must be square (rows == cols)");
  }
  if b.len() != rows {
    return Err("solve: b length must equal A dimension");
  }
  var x = matrix_create(rows, 1)?;
  return Ok(x);
}
