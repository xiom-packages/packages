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
//     satisfies the extern "C" surface below without a system OpenBLAS.
//     `xiom_openblas_backend()` returns 0 on this leg, so every public
//     operation runs the pure-XIOM reference loops in this file; the stub
//     C symbols are never called.
//   * Real leg (tests/run_real_leg.ps1 + tests/test_conformance.xi): the
//     same module is linked against the system OpenBLAS import library and
//     bridge/openblas_real_marker.c (marker only -- no cblas/LAPACK stub
//     symbols). `xiom_openblas_backend()` returns 1, so the public API
//     marshals pool/Vec memory into cblas_* and dgesvd_/dsyev_/dgesv_.
//     Never link both legs into one artifact (duplicate cblas symbols).
//
// The older runtime-detect probe (tests/probe_real_openblas.xi) is kept as
// a SKIP-safe smoke check; the linked suite is the authoritative real leg.
//
// Depends on: xiom.convert (stdlib), xiom.ffi (stdlib)
//
// C signatures reference (int32 blasint, standard LP64 OpenBLAS build;
// the ILP64 openblas64_ variant is Phase-2 scope). LAPACK entry points are
// Fortran symbols and carry hidden `size_t` character-length arguments
// (gfortran convention; lapack.h defines LAPACK_FORTRAN_STRLEN_END):
//   https://www.openblas.net/     -- cblas_*
//   https://netlib.org/lapack/    -- dgesvd_, dsyev_, dgesv_

module xiom.openblas

use xiom.convert;

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
// (stub link-seam, never called); the real leg resolves them against the
// linked OpenBLAS import library. `xiom_openblas_backend` is defined by
// exactly one of the two leg markers (stub bridge = 0, real marker = 1).

extern "C" {
  // ---- leg marker (defined by the selected C bridge, never by OpenBLAS) ----
  fn xiom_openblas_backend() -> Int32;

  // ---- BLAS Level 1 ----
  fn cblas_ddot(n: Int32, x: *Float64, incx: Int32, y: *Float64, incy: Int32) -> Float64;
  fn cblas_daxpy(n: Int32, alpha: Float64, x: *Float64, incx: Int32, y: *Float64, incy: Int32);

  // ---- BLAS Level 2 ----
  fn cblas_dgemv(order: Int32, trans: Int32, m: Int32, n: Int32, alpha: Float64, a: *Float64, lda: Int32, x: *Float64, incx: Int32, beta: Float64, y: *Float64, incy: Int32);

  // ---- BLAS Level 3 ----
  fn cblas_dgemm(order: Int32, transa: Int32, transb: Int32, m: Int32, n: Int32, k: Int32, alpha: Float64, a: *Float64, lda: Int32, b: *Float64, ldb: Int32, beta: Float64, c: *Float64, ldc: Int32);

  // ---- LAPACK (Fortran int32 arguments + hidden character lengths) ----
  fn dgesvd_(jobu: *UInt8, jobvt: *UInt8, m: *Int32, n: *Int32, a: *Float64, lda: *Int32, s: *Float64, u: *Float64, ldu: *Int32, vt: *Float64, ldvt: *Int32, work: *Float64, lwork: *Int32, info: *Int32, jobu_len: UInt, jobvt_len: UInt);
  fn dsyev_(jobz: *UInt8, uplo: *UInt8, n: *Int32, a: *Float64, lda: *Int32, w: *Float64, work: *Float64, lwork: *Int32, info: *Int32, jobz_len: UInt, uplo_len: UInt);
  fn dgesv_(n: *Int32, nrhs: *Int32, a: *Float64, lda: *Int32, ipiv: *Int32, b: *Float64, ldb: *Int32, info: *Int32);
}

// ============================================================
// Backend leg marker
// ============================================================

/// True when this artifact is linked against real OpenBLAS (the real leg).
/// False on the documented stub/SKIP leg, where the public operations run
/// the pure-XIOM reference paths instead of the stub C symbols.
pub fn backend_is_real() -> Bool {
  // The marker takes no arguments, touches no memory, and returns an int
  // written by the linked leg marker (stub bridge or real marker).
  // SAFETY: the extern call has no pointer arguments or memory access.
  let flag = unsafe { xiom_openblas_backend() };
  return flag == 1;
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
  if backend_is_real() {
    // requires n > 0 and the callers guarantee x.len()/y.len() >= n; both
    // Vec pointers are contiguous Float64 spans and inc = 1 stays in range.
    // SAFETY: the span lengths and n bound every cblas_ddot access.
    return unsafe { cblas_ddot(n as Int32, &x[0], 1, &y[0], 1) };
  }
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
  if backend_is_real() {
    // requires n > 0 and the callers guarantee x.len()/y.len() >= n; x is
    // read-only, y is uniquely borrowed, inc = 1 stays in range.
    // SAFETY: the span lengths and n bound every cblas_daxpy access.
    unsafe { cblas_daxpy(n as Int32, alpha, &x[0], 1, &mut y[0], 1); }
    return;
  }
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
  if backend_is_real() {
    let start = __pool_data_idx(handle);
    // Row-major CBLAS. With trans, the wrapper's A is stored n x m and
    // produces y(m) = A^T x(n); CBLAS sees that as an m_c=n, n_c=m Trans.
    if trans {
      // Handle validation guarantees the pool span covers rows*cols; lda =
      // cols; x/y lengths follow the documented transposed contract.
      // SAFETY: the validated span, lda, and contract lengths bound all access.
      unsafe { cblas_dgemv(101, 112, n as Int32, m as Int32, alpha, &__pool_data[start], cols as Int32, &x[0], 1, beta, &mut y[0], 1); }
    } else {
      // Same span/lda reasoning for the no-trans contract.
      // SAFETY: the validated span, lda, and contract lengths bound all access.
      unsafe { cblas_dgemv(101, 111, m as Int32, n as Int32, alpha, &__pool_data[start], cols as Int32, &x[0], 1, beta, &mut y[0], 1); }
    }
    return;
  }
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
  if backend_is_real() {
    let astart = __pool_data_idx(ha);
    let bstart = __pool_data_idx(hb);
    let cstart = __pool_data_idx(hc);
    let ta: Int32 = if transA { 112 } else { 111 };
    let tb: Int32 = if transB { 112 } else { 111 };
    // All three handles were validated; astart/bstart/cstart are pool spans
    // whose strides acols/bcols/ccols are the row-major leading dimensions.
    // SAFETY: the m/n/k contract keeps every CBLAS read/write inside those spans.
    unsafe { cblas_dgemm(101, ta, tb, m as Int32, n as Int32, k as Int32, alpha, &__pool_data[astart], acols as Int32, &__pool_data[bstart], bcols as Int32, beta, &mut __pool_data[cstart], ccols as Int32); }
    return;
  }
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
// LAPACK helpers
// ============================================================

// Copy a pool matrix (row-major) into a fresh column-major buffer.
// Column-major element (i, j) lives at i + j * rows.
fn __to_col_major(handle: Int) -> Vec[Float64] {
  let rows = __pool_rows_of(handle);
  let cols = __pool_cols_of(handle);
  var out = Vec[Float64].with_len(rows * cols);
  var i = 0;
  while i < rows {
    var j = 0;
    while j < cols {
      out[i + j * rows] = __pool_data_read(handle, i * cols + j);
      j = j + 1;
    }
    i = i + 1;
  }
  return out;
}

// Fill a freshly created pool matrix from a row-major Vec.
fn __fill_row_major(handle: Int, data: &Vec[Float64]) {
  let total = __pool_rows_of(handle) * __pool_cols_of(handle);
  var i = 0;
  while i < total {
    __pool_data_write(handle, i, data[i]);
    i = i + 1;
  }
}

// ============================================================
// LAPACK -- Singular Value Decomposition
// ============================================================
// Real leg: dgesvd_ (economy U/VT), workspace query first, then a second
// call with the allocated XIOM Vec workspace. The (m x n) row-major input
// is copied to a column-major scratch; results are converted back.
// Offline leg: identity/zero placeholders with correct shapes (the
// documented SKIP path).

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

  if backend_is_real() {
    var a_c = __to_col_major(handle);
    var sv = Vec[Float64].with_len(min_dim);
    var u_c = Vec[Float64].with_len(rows * min_dim);
    var vt_c = Vec[Float64].with_len(min_dim * cols);
    var work_query = Vec[Float64].with_len(1);

    var jobu: UInt8 = 83;   // 'S'
    var jobvt: UInt8 = 83;  // 'S'
    var m32: Int32 = rows as Int32;
    var n32: Int32 = cols as Int32;
    var lda32: Int32 = rows as Int32;
    var ldu32: Int32 = rows as Int32;
    var ldvt32: Int32 = min_dim as Int32;
    var lwork32: Int32 = -1;
    var info32: Int32 = 0;

    // Workspace query: lwork = -1, one-element work buffer. a_c/u_c/vt_c/sv/
    // work_query are non-empty Vec spans sized from rows/cols/min_dim; all
    // scalar pointers point at live Int32/UInt8 variables.
    // SAFETY: the sized spans above bound every LAPACK read/write.
    unsafe {
      dgesvd_(&mut jobu, &mut jobvt, &mut m32, &mut n32, &mut a_c[0], &mut lda32,
              &mut sv[0], &mut u_c[0], &mut ldu32, &mut vt_c[0], &mut ldvt32,
              &mut work_query[0], &mut lwork32, &mut info32, 1 as UInt, 1 as UInt);
    }
    if info32 != 0 {
      return Err("svd: dgesvd_ workspace query failed (info=" + convert.int_to_string(info32 as Int) + ")");
    }
    let lwork = work_query[0] as Int;
    if lwork < 1 {
      return Err("svd: dgesvd_ returned an invalid workspace size");
    }
    var work = Vec[Float64].with_len(lwork);
    lwork32 = lwork as Int32;
    info32 = 0;
    // work has exactly the lwork slots the query returned; the LAPACK minimum
    // lwork for economy SVD is >= 1, and all other spans are unchanged.
    // SAFETY: the queried work length and sized spans bound every access.
    unsafe {
      dgesvd_(&mut jobu, &mut jobvt, &mut m32, &mut n32, &mut a_c[0], &mut lda32,
              &mut sv[0], &mut u_c[0], &mut ldu32, &mut vt_c[0], &mut ldvt32,
              &mut work[0], &mut lwork32, &mut info32, 1 as UInt, 1 as UInt);
    }
    if info32 != 0 {
      return Err("svd: dgesvd_ failed (info=" + convert.int_to_string(info32 as Int) + ")");
    }

    // u_c is column-major (rows x min_dim); convert to row-major.
    var u_rm = Vec[Float64].with_len(rows * min_dim);
    var i = 0;
    while i < rows {
      var j = 0;
      while j < min_dim {
        u_rm[i * min_dim + j] = u_c[i + j * rows];
        j = j + 1;
      }
      i = i + 1;
    }
    // Singular values as a diagonal min_dim x min_dim matrix.
    var s_rm = Vec[Float64].with_len(min_dim * min_dim);
    i = 0;
    while i < min_dim {
      s_rm[i * min_dim + i] = sv[i];
      i = i + 1;
    }
    // vt_c is column-major (min_dim x cols); convert to row-major.
    var vt_rm = Vec[Float64].with_len(min_dim * cols);
    i = 0;
    while i < min_dim {
      var j = 0;
      while j < cols {
        vt_rm[i * cols + j] = vt_c[i + j * min_dim];
        j = j + 1;
      }
      i = i + 1;
    }

    var u = matrix_create(rows, min_dim)?;
    var s = matrix_create(min_dim, min_dim)?;
    var vt = matrix_create(min_dim, cols)?;
    var hu: Int = u;
    var hs: Int = s;
    var hvt: Int = vt;
    __fill_row_major(hu, &u_rm);
    __fill_row_major(hs, &s_rm);
    __fill_row_major(hvt, &vt_rm);
    return Ok((u, s, vt));
  }

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
// Real leg: dsyev_ (jobz='V', uplo='U'), workspace query first.
// Eigenvalues ascending; eigenvectors are the columns of V (row-major
// after conversion). Offline leg: zero values / identity vectors.

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

  if backend_is_real() {
    var a_c = __to_col_major(handle);
    var w = Vec[Float64].with_len(n);
    var work_query = Vec[Float64].with_len(1);

    var jobz: UInt8 = 86;  // 'V'
    var uplo: UInt8 = 85;  // 'U'
    var n32: Int32 = n as Int32;
    var lda32: Int32 = n as Int32;
    var lwork32: Int32 = -1;
    var info32: Int32 = 0;

    // a_c has n*n doubles (lda = n), w has n doubles, and the one-element
    // work_query is the documented lwork=-1 query buffer.
    // SAFETY: those sized spans bound every dsyev_ read/write.
    unsafe {
      dsyev_(&mut jobz, &mut uplo, &mut n32, &mut a_c[0], &mut lda32,
             &mut w[0], &mut work_query[0], &mut lwork32, &mut info32, 1 as UInt, 1 as UInt);
    }
    if info32 != 0 {
      return Err("eigen_sym: dsyev_ workspace query failed (info=" + convert.int_to_string(info32 as Int) + ")");
    }
    let lwork = work_query[0] as Int;
    if lwork < 1 {
      return Err("eigen_sym: dsyev_ returned an invalid workspace size");
    }
    var work = Vec[Float64].with_len(lwork);
    lwork32 = lwork as Int32;
    info32 = 0;
    // work has exactly the lwork slots returned by the query; the n*n a_c
    // span and n-element w span are unchanged from the query call.
    // SAFETY: the queried work length and sized spans bound every access.
    unsafe {
      dsyev_(&mut jobz, &mut uplo, &mut n32, &mut a_c[0], &mut lda32,
             &mut w[0], &mut work[0], &mut lwork32, &mut info32, 1 as UInt, 1 as UInt);
    }
    if info32 != 0 {
      return Err("eigen_sym: dsyev_ failed (info=" + convert.int_to_string(info32 as Int) + ")");
    }

    // Eigenvalues as a diagonal n x n matrix.
    var values_rm = Vec[Float64].with_len(n * n);
    var i = 0;
    while i < n {
      values_rm[i * n + i] = w[i];
      i = i + 1;
    }
    // a_c now holds eigenvectors in columns (column-major); convert.
    var vectors_rm = Vec[Float64].with_len(n * n);
    i = 0;
    while i < n {
      var j = 0;
      while j < n {
        vectors_rm[i * n + j] = a_c[i + j * n];
        j = j + 1;
      }
      i = i + 1;
    }

    var values = matrix_create(n, n)?;
    var vectors = matrix_create(n, n)?;
    var hv: Int = values;
    var hvec: Int = vectors;
    __fill_row_major(hv, &values_rm);
    __fill_row_major(hvec, &vectors_rm);
    return Ok((values, vectors));
  }

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
// Real leg: dgesv_ (LU with partial pivoting; ipiv is a raw int32 scratch
// carved from a Float64 Vec's first n*4 bytes). Offline leg: zero vector
// with the right shape.

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
  var n = rows;

  if backend_is_real() {
    var a_c = __to_col_major(handle);
    var b_c = Vec[Float64].with_len(n);
    var i = 0;
    while i < n {
      b_c[i] = b[i];
      i = i + 1;
    }
    // n int32 pivot indices = n*4 bytes; a Float64 Vec provides the
    // contiguous raw storage (the Vec element stride is 8 bytes, so half
    // the slots are enough for the int32 view).
    var ipiv_storage = Vec[Float64].with_len((n + 1) / 2);

    var n32: Int32 = n as Int32;
    var nrhs32: Int32 = 1;
    var lda32: Int32 = n as Int32;
    var ldb32: Int32 = n as Int32;
    var info32: Int32 = 0;
    // a_c has n*n doubles (lda = n), b_c has n doubles (ldb = n), and
    // ipiv_storage has ceil(n/2) eight-byte slots = at least n*4 bytes for
    // the required int32 pivot array.
    // SAFETY: those sized spans bound every dgesv_ read/write.
    unsafe {
      dgesv_(&mut n32, &mut nrhs32, &mut a_c[0], &mut lda32,
             ipiv_storage.as_mut_ptr() as *Int32, &mut b_c[0], &mut ldb32, &mut info32);
    }
    if info32 > 0 {
      return Err("solve: matrix is singular (info=" + convert.int_to_string(info32 as Int) + ")");
    }
    if info32 < 0 {
      return Err("solve: dgesv_ rejected an argument (info=" + convert.int_to_string(info32 as Int) + ")");
    }

    var x = matrix_create(n, 1)?;
    var hx: Int = x;
    i = 0;
    while i < n {
      __pool_data_write(hx, i, b_c[i]);
      i = i + 1;
    }
    return Ok(x);
  }

  var x = matrix_create(rows, 1)?;
  return Ok(x);
}
