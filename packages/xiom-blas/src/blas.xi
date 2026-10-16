// XIOM -- xiom.blas: BLAS/LAPACK bindings, safe XIOM-level surface.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Fold (2026-10-17): the parked safe-linalg package is now layered over the
// live xiom.openblas seam (eco-v0.1.193). The FFI-backed primitives
// (matmul/matvec/dot/axpy) delegate into `xiom.openblas`'s declared surface;
// nothing is vendored here and no `unsafe`/`extern` appears in this package
// -- the BLAS runtime ships (and is loaded/SKIP-classified) entirely by
// xiom.openblas. See PROVENANCE.md / SPEC.md for the dependency story.
//
// Layering (per SPEC.md):
//   src/linalg.xi    safe linear-algebra surface (matrix_multiply, solve, ...)
//   blas.xi          DenseMatrix value type + construction/access + FFI seam
//   blas.xiom-bind   C ABI mapping (declarative; the seam resolves at link)
//
// Row-major layout: element (i, j) is at index i * cols + j.
//
// Type name (delta vs the seed SPEC's `Matrix`): the safe-layer type is
// `DenseMatrix`, NOT `Matrix`. xiom.openblas also declares `pub type Matrix`
// (an Int pool handle), and the v0.64.5 name-resolver mis-binds same-named
// types across imported modules: a unit holding both packages lowered the
// openblas handle as this struct and faulted (0xC0000005) on `matrix_free`.
// Renaming removes the collision. Exact repro + evidence in AUDIT.md.

module xiom.blas

use xiom.openblas;

pub type DenseMatrix = { rows: Int; cols: Int; data: Vec[Float64]; } derive[Clone]

// ============================================================
// Construction
// ============================================================

pub fn matrix_new(rows: Int, cols: Int) -> DenseMatrix
  requires: rows > 0
  requires: cols > 0
  ensures: result.rows == rows
  ensures: result.cols == cols
  ensures: result.data.len() == rows * cols
{
  var data = Vec[Float64].new();
  var i = 0;
  while i < rows * cols {
    data.push(0.0);
    i = i + 1;
  };
  return DenseMatrix{ rows: rows, cols: cols, data: data };
}

pub fn matrix_zeros(rows: Int, cols: Int) -> DenseMatrix
  requires: rows > 0
  requires: cols > 0
{
  return matrix_new(rows, cols);
}

pub fn matrix_identity(n: Int) -> DenseMatrix
  requires: n > 0
  ensures: result.rows == n
  ensures: result.cols == n
{
  var m = matrix_new(n, n);
  var i = 0;
  while i < n {
    m.data[i * n + i] = 1.0;
    i = i + 1;
  };
  return m;
}

pub fn vector_zeros(n: Int) -> Vec[Float64]
  requires: n > 0
  ensures: result.len() == n
{
  var v = Vec[Float64].new();
  var i = 0;
  while i < n {
    v.push(0.0);
    i = i + 1;
  };
  return v;
}

pub fn vector_ones(n: Int) -> Vec[Float64]
  requires: n > 0
  ensures: result.len() == n
{
  var v = Vec[Float64].new();
  var i = 0;
  while i < n {
    v.push(1.0);
    i = i + 1;
  };
  return v;
}

// ============================================================
// Element access
// ============================================================

pub fn matrix_get(m: &DenseMatrix, row: Int, col: Int) -> Float64
  requires: row >= 0
  requires: col >= 0
  requires: row < m.rows
  requires: col < m.cols
{
  return m.data[row * m.cols + col];
}

pub fn matrix_set(m: &mut DenseMatrix, row: Int, col: Int, val: Float64)
  requires: row >= 0
  requires: col >= 0
  requires: row < m.rows
  requires: col < m.cols
{
  m.data[row * m.cols + col] = val;
}

// ============================================================
// Pure-XIOM element-wise operations
// ============================================================

pub fn matrix_add(a: &DenseMatrix, b: &DenseMatrix) -> Result[DenseMatrix, Str]
  requires: a.rows > 0
  requires: a.cols > 0
  requires: b.rows > 0
  requires: b.cols > 0
  ensures: !result.is_ok() || result.unwrap().rows == a.rows
  ensures: !result.is_ok() || result.unwrap().cols == a.cols
{
  if a.rows != b.rows || a.cols != b.cols {
    return Err("matrix_add: shape mismatch (a.rows, a.cols) != (b.rows, b.cols)");
  };
  var result = matrix_new(a.rows, a.cols);
  var i = 0;
  while i < a.data.len() {
    result.data[i] = a.data[i] + b.data[i];
    i = i + 1;
  };
  return Ok(result);
}

pub fn matrix_sub(a: &DenseMatrix, b: &DenseMatrix) -> Result[DenseMatrix, Str]
  requires: a.rows > 0
  requires: a.cols > 0
  requires: b.rows > 0
  requires: b.cols > 0
  ensures: !result.is_ok() || result.unwrap().rows == a.rows
  ensures: !result.is_ok() || result.unwrap().cols == a.cols
{
  if a.rows != b.rows || a.cols != b.cols {
    return Err("matrix_sub: shape mismatch (a.rows, a.cols) != (b.rows, b.cols)");
  };
  var result = matrix_new(a.rows, a.cols);
  var i = 0;
  while i < a.data.len() {
    result.data[i] = a.data[i] - b.data[i];
    i = i + 1;
  };
  return Ok(result);
}

pub fn matrix_transpose(a: &DenseMatrix) -> DenseMatrix
  requires: a.rows > 0
  requires: a.cols > 0
  ensures: result.rows == a.cols
  ensures: result.cols == a.rows
{
  var t = matrix_new(a.cols, a.rows);
  var i = 0;
  while i < a.rows {
    var j = 0;
    while j < a.cols {
      t.data[j * a.rows + i] = a.data[i * a.cols + j];
      j = j + 1;
    };
    i = i + 1;
  };
  return t;
}

// ============================================================
// FFI-backed primitives (delegated to the xiom.openblas seam)
// ============================================================
//
// The openblas pool stores row-major matrices behind Int handles; every
// public function below is shape-checked first and converts across the
// boundary explicitly. Offline (no system OpenBLAS) the seam computes the
// same numbers through its pure-XIOM reference paths; once the seam's real
// cblas wire-in lands (xiom.openblas ROADMAP Phase 1 remainder) these calls
// become real cblas_dgemm/dgemv/ddot/daxpy traffic with no API change here.

fn __pool_from_matrix(m: &DenseMatrix) -> Result[Int, Str]
  requires: m.rows > 0
  requires: m.cols > 0
  ensures: m.data.len() == m.rows * m.cols
{
  match xiom.openblas.matrix_create(m.rows, m.cols) {
    Ok(h) => {
      var hm = h;
      var i = 0;
      while i < m.data.len() {
        xiom.openblas.matrix_set(&mut hm, i / m.cols, i % m.cols, m.data[i]);
        i = i + 1;
      };
      return Ok(hm);
    }
    Err(e) => { return Err(e); }
  }
}

fn __matrix_from_pool(h: Int, rows: Int, cols: Int) -> DenseMatrix
  requires: rows > 0
  requires: cols > 0
  ensures: result.rows == rows
  ensures: result.cols == cols
{
  var out = matrix_new(rows, cols);
  var i = 0;
  while i < out.data.len() {
    out.data[i] = xiom.openblas.matrix_get(&h, i / cols, i % cols);
    i = i + 1;
  };
  return out;
}

pub fn matmul(a: &DenseMatrix, b: &DenseMatrix) -> Result[DenseMatrix, Str]
  requires: a.rows > 0
  requires: a.cols > 0
  requires: b.rows > 0
  requires: b.cols > 0
  ensures: !result.is_ok() || result.unwrap().rows == a.rows
  ensures: !result.is_ok() || result.unwrap().cols == b.cols
{
  if a.cols != b.rows {
    return Err("matmul: shape mismatch (a.cols != b.rows)");
  };
  match __pool_from_matrix(a) {
    Ok(ha) => {
      match __pool_from_matrix(b) {
        Ok(hb) => {
          match xiom.openblas.matrix_create(a.rows, b.cols) {
            Ok(hc) => {
              var hcm = hc;
              xiom.openblas.gemm(false, false, a.rows, b.cols, a.cols, 1.0, &ha, &hb, 0.0, &mut hcm);
              let out = __matrix_from_pool(hcm, a.rows, b.cols);
              xiom.openblas.matrix_free(ha);
              xiom.openblas.matrix_free(hb);
              xiom.openblas.matrix_free(hcm);
              return Ok(out);
            }
            Err(e) => {
              xiom.openblas.matrix_free(ha);
              xiom.openblas.matrix_free(hb);
              return Err(e);
            }
          }
        }
        Err(e) => {
          xiom.openblas.matrix_free(ha);
          return Err(e);
        }
      }
    }
    Err(e) => { return Err(e); }
  }
}

pub fn matvec(m: &DenseMatrix, v: &Vec[Float64]) -> Result[Vec[Float64], Str]
  requires: m.rows > 0
  requires: m.cols > 0
  ensures: !result.is_ok() || result.unwrap().len() == m.rows
{
  if m.cols != v.len() {
    return Err("matvec: shape mismatch (m.cols != v.len())");
  };
  match __pool_from_matrix(m) {
    Ok(hm) => {
      var y = vector_zeros(m.rows);
      xiom.openblas.gemv(false, m.rows, m.cols, 1.0, &hm, v, 0.0, &mut y);
      xiom.openblas.matrix_free(hm);
      return Ok(y);
    }
    Err(e) => { return Err(e); }
  }
}

pub fn ddot(x: &Vec[Float64], y: &Vec[Float64]) -> Float64
  requires: x.len() == y.len()
{
  if x.len() == 0 {
    return 0.0;
  };
  return xiom.openblas.dot(x, y, x.len());
}

pub fn daxpy(alpha: Float64, x: &Vec[Float64], y: &mut Vec[Float64])
  requires: x.len() == y.len()
{
  if x.len() == 0 {
    return;
  };
  xiom.openblas.axpy(alpha, x, y, x.len());
}

pub fn scal(alpha: Float64, x: &mut Vec[Float64]) {
  var i = 0;
  while i < x.len() {
    x[i] = alpha * x[i];
    i = i + 1;
  };
}
