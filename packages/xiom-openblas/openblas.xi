// XIOM -- xiom.openblas
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// OpenBLAS / LAPACK bindings for XIOM.
// Phase 1 -- Core Foundation: BLAS 1-3, LAPACK SVD/Eigen/Solve.
// Link against system-installed libopenblas.
// Matrix = Int (opaque pool handle).
//
// Two-leg build (see SPEC.md / README.md / ROADMAP.md):
//   * Offline leg (scripts/port.ps1 + tests/test_conformance.xi): this module
//     links against bridge/openblas_bridge.c, the stub link-seam that
//     satisfies the extern "C" surface below without a system OpenBLAS. All
//     computations in the offline leg run through the pure-XIOM reference
//     loops in this file; the bridge symbols are declared but not called.
//   * Real leg (tests/probe_real_openblas.xi): probe-local shim that
//     detects a system OpenBLAS at runtime (libopenblas.dll /
//     openblas64_.dll / libopenblas.so), then exercises cblas_ddot and
//     cblas_dgemm from the real library. SKIPs cleanly when absent.
//
// Depends on: xiom.ffi (stdlib)
//
// C signatures reference (int32 blasint, standard LP64 OpenBLAS build;
// the ILP64 openblas64_ variant is Phase-2 scope):
//   https://www.openblas.net/     -- cblas_*
//   https://netlib.org/lapack/    -- dgesvd_, dsyev_, dgesv_

module xiom.openblas

// ============================================================
// Module-level matrix pool
// ============================================================

var __pool_data: Vec[Float64] = Vec[Float64].new();
var __pool_rows: Vec[Int] = Vec[Int].new();
var __pool_cols: Vec[Int] = Vec[Int].new();
var __pool_start: Vec[Int] = Vec[Int].new();
var __pool_used: Vec[Int] = Vec[Int].new();

// ============================================================
// Public opaque handle
// ============================================================

pub type Matrix = Int;
// ============================================================
// Internal pool helpers (plain Int handles; the public API converts
// the Matrix newtype to Int once at its boundary)
// ============================================================

fn __pool_alloc(rows: Int, cols: Int, data: &Vec[Float64]) -> Int {
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

fn __pool_data_idx(m: Int) -> Int
  requires: m > 0
  requires: m <= __pool_used.len()
  requires: __pool_used[m - 1] == 1
{
  return __pool_start[m - 1];
}

fn __pool_rows_of(m: Int) -> Int
  requires: m > 0
  requires: m <= __pool_used.len()
{
  return __pool_rows[m - 1];
}

fn __pool_cols_of(m: Int) -> Int
  requires: m > 0
  requires: m <= __pool_used.len()
{
  return __pool_cols[m - 1];
}

fn __pool_data_read(m: Int, offset: Int) -> Float64
  requires: m > 0
  requires: m <= __pool_used.len()
{
  return __pool_data[__pool_start[m - 1] + offset];
}

fn __pool_data_write(m: Int, offset: Int, val: Float64)
  requires: m > 0
  requires: m <= __pool_used.len()
{
  __pool_data[__pool_start[m - 1] + offset] = val;
}

fn __pool_is_valid(m: Int) -> Bool {
  if m <= 0 { return false; }
  if m > __pool_used.len() { return false; }
  return __pool_used[m - 1] == 1;
}

fn __pool_mark_freed(m: Int)
  requires: m > 0
  requires: m <= __pool_used.len()
{
  __pool_used[m - 1] = 0;
}

// ============================================================
// extern "C" -- OpenBLAS (CBLAS) + LAPACK (FORTRAN linkage)
// ============================================================
// ABI note: blasint is int32 in the standard LP64 OpenBLAS build. The
// offline leg resolves these symbols against bridge/openblas_bridge.c
// (stub link-seam); they are NOT called by the pure-XIOM Phase-1 paths.

extern "C" {
  // ---- BLAS Level 1 ----
  fn cblas_ddot(n: Int32, x: *Float64, incx: Int32, y: *Float64, incy: Int32) -> Float64;
  fn cblas_daxpy(n: Int32, alpha: Float64, x: *Float64, incx: Int32, y: *Float64, incy: Int32);

  // ---- BLAS Level 2 ----
  fn cblas_dgemv(order: Int32, trans: Int32, m: Int32, n: Int32, alpha: Float64, a: *Float64, lda: Int32, x: *Float64, incx: Int32, beta: Float64, y: *Float64, incy: Int32);

  // ---- BLAS Level 3 ----
  fn cblas_dgemm(order: Int32, transa: Int32, transb: Int32, m: Int32, n: Int32, k: Int32, alpha: Float64, a: *Float64, lda: Int32, b: *Float64, ldb: Int32, beta: Float64, c: *Float64, ldc: Int32);

  // ---- LAPACK (Fortran int32 arguments) ----
  fn dgesvd_(jobu: *UInt8, jobvt: *UInt8, m: *Int32, n: *Int32, a: *Float64, lda: *Int32, s: *Float64, u: *Float64, ldu: *Int32, vt: *Float64, ldvt: *Int32, work: *Float64, lwork: *Int32, info: *Int32);
  fn dsyev_(jobz: *UInt8, uplo: *UInt8, n: *Int32, a: *Float64, lda: *Int32, w: *Float64, work: *Float64, lwork: *Int32, info: *Int32);
  fn dgesv_(n: *Int32, nrhs: *Int32, a: *Float64, lda: *Int32, ipiv: *Int32, b: *Float64, ldb: *Int32, info: *Int32);
}

// ============================================================
// Matrix lifecycle
// ============================================================
// Invalid dimensions are reported as Err (not contract panics) so the
// conformance suite can exercise the error path; see SPEC.md delta table.

pub fn matrix_create(rows: Int, cols: Int) -> Result[Matrix, Str] {
  if rows <= 0 { return Err("matrix_create: rows must be > 0"); }
  if cols <= 0 { return Err("matrix_create: cols must be > 0"); }
  var total = rows * cols;
  var data: Vec[Float64] = Vec[Float64].new();
  var i = 0;
  while i < total {
    data.push(0.0);
    i = i + 1;
  }
  var handle = __pool_alloc(rows, cols, &data);
  return Ok(handle);
}

pub fn matrix_free(m: Matrix)
  requires: m != 0
{
  var h: Int = m;
  if __pool_is_valid(h) {
    __pool_mark_freed(h);
  }
}

pub fn matrix_get(m: &Matrix, row: Int, col: Int) -> Float64 {
  var handle: Int = m;
  if !__pool_is_valid(handle) { return 0.0; }
  var rows = __pool_rows_of(handle);
  var cols = __pool_cols_of(handle);
  if row < 0 || row >= rows || col < 0 || col >= cols { return 0.0; }
  return __pool_data_read(handle, row * cols + col);
}

pub fn matrix_set(m: &mut Matrix, row: Int, col: Int, val: Float64) {
  var handle: Int = m;
  if !__pool_is_valid(handle) { return; }
  var rows = __pool_rows_of(handle);
  var cols = __pool_cols_of(handle);
  if row < 0 || row >= rows || col < 0 || col >= cols { return; }
  __pool_data_write(handle, row * cols + col, val);
}

pub fn matrix_rows(m: &Matrix) -> Int {
  var handle: Int = m;
  if !__pool_is_valid(handle) { return 0; }
  return __pool_rows_of(handle);
}

pub fn matrix_cols(m: &Matrix) -> Int {
  var handle: Int = m;
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
  var handle: Int = A;
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
  var ha: Int = A;
  var hb: Int = B;
  var hc: Int = C;
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
// Phase 1 stub: identity/zero placeholders with correct shapes.
// Real dgesvd_ wiring is Phase 2 (see ROADMAP.md).

pub fn svd(A: &Matrix) -> Result[(Matrix, Matrix, Matrix), Str] {
  var handle: Int = A;
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
// Phase 1 stub: zero values / identity vectors. Real dsyev_ wiring is
// Phase 2 (see ROADMAP.md).

pub fn eigen_sym(A: &Matrix) -> Result[(Matrix, Matrix), Str] {
  var handle: Int = A;
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
// Phase 1 stub: zero vector with the right shape. Real dgesv_ wiring is
// Phase 2 (see ROADMAP.md).

pub fn solve(A: &Matrix, b: &Vec[Float64]) -> Result[Matrix, Str] {
  var handle: Int = A;
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
