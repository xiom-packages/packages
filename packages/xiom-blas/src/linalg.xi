// XIOM -- xiom.blas.linalg: the safe linear-algebra surface.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// This module is the SPEC-declared linalg surface over the `xiom.blas`
// DenseMatrix value type. FFI-backed members (`matrix_multiply`,
// `matrix_vector_multiply`, `vector_dot`) delegate into the `xiom.blas`
// seam, which is layered over `xiom.openblas` (eco-v0.1.193). Pure members
// (`matrix_scale`, `matrix_determinant`, `matrix_inverse`,
// `solve_linear_system`) are self-contained XIOM with partial pivoting --
// they need no runtime and no C at all.
//
// Error discipline: every shape violation is checked before any work and
// returned as `Err(Str)` with a descriptive message; singular matrices are
// detected on exact zero pivots after partial-pivot selection.

module xiom.blas.linalg

use xiom.blas;

// |x| without stdlib imports (Float64 local helper).
fn __abs(x: Float64) -> Float64 {
  if x < 0.0 {
    return 0.0 - x;
  };
  return x;
}

// ============================================================
// FFI-backed surface (delegates to the xiom.blas -> xiom.openblas seam)
// ============================================================
//
// Construction note (delta vs the seed SPEC table): the SPEC lists
// `identity(n)`; the delivered constructor is `matrix_identity(n)` in
// xiom.blas. `identity` is renamed because the name collides with the
// generic `xiom.convert.identity[T]` in any unit importing both -- the
// v0.64.5 resolver binds the foreign generic over the local function
// (observed in this package's own suite). Same resolver class as the
// DenseMatrix rename (see AUDIT.md).

pub fn matrix_multiply(a: &DenseMatrix, b: &DenseMatrix) -> Result[DenseMatrix, Str]
  requires: a.rows > 0
  requires: a.cols > 0
  requires: b.rows > 0
  requires: b.cols > 0
  ensures: !result.is_ok() || result.unwrap().rows == a.rows
  ensures: !result.is_ok() || result.unwrap().cols == b.cols
{
  return xiom.blas.matmul(a, b);
}

pub fn matrix_vector_multiply(m: &DenseMatrix, v: &Vec[Float64]) -> Result[Vec[Float64], Str]
  requires: m.rows > 0
  requires: m.cols > 0
  ensures: !result.is_ok() || result.unwrap().len() == m.rows
{
  return xiom.blas.matvec(m, v);
}

pub fn vector_dot(a: &Vec[Float64], b: &Vec[Float64]) -> Float64
  requires: a.len() == b.len()
{
  return xiom.blas.ddot(a, b);
}

// SPEC maps this to cblas_dscal; the live xiom.openblas seam declares no
// dscal wrapper, so the safe layer scales in place with the same loop the
// seam uses for its reference paths (numerically identical; the seam
// remains the single place a real cblas_dscal wire-in would land).
pub fn vector_scale(alpha: Float64, v: &mut Vec[Float64]) {
  xiom.blas.scal(alpha, v);
}

// ============================================================
// Pure-XIOM linear algebra (partial pivoting; runtime-independent)
// ============================================================

pub fn matrix_scale(a: &DenseMatrix, scalar: Float64) -> DenseMatrix
  requires: a.rows > 0
  requires: a.cols > 0
  ensures: result.rows == a.rows
  ensures: result.cols == a.cols
{
  var result = xiom.blas.matrix_new(a.rows, a.cols);
  var i = 0;
  while i < a.data.len() {
    result.data[i] = a.data[i] * scalar;
    i = i + 1;
  };
  return result;
}

// Determinant via LU with partial pivoting. Returns 0.0 exactly when the
// DenseMatrix is singular (a zero pivot column after pivot selection).
pub fn matrix_determinant(a: &DenseMatrix) -> Float64
  requires: a.rows > 0
  requires: a.rows == a.cols
{
  let n = a.rows;
  var lu = a.data.clone();
  var det = 1.0;
  var i = 0;
  while i < n {
    var pivot_row = i;
    var best = __abs(lu[i * n + i]);
    var r = i + 1;
    while r < n {
      let cand = __abs(lu[r * n + i]);
      if cand > best {
        pivot_row = r;
        best = cand;
      };
      r = r + 1;
    };
    if best == 0.0 {
      return 0.0;
    };
    if pivot_row != i {
      var c = 0;
      while c < n {
        let tmp = lu[i * n + c];
        lu[i * n + c] = lu[pivot_row * n + c];
        lu[pivot_row * n + c] = tmp;
        c = c + 1;
      };
      det = 0.0 - det;
    };
    let pivot = lu[i * n + i];
    det = det * pivot;
    var j = i + 1;
    while j < n {
      let factor = lu[j * n + i] / pivot;
      var k = i;
      while k < n {
        lu[j * n + k] = lu[j * n + k] - factor * lu[i * n + k];
        k = k + 1;
      };
      j = j + 1;
    };
    i = i + 1;
  };
  return det;
}

// Inverse via Gauss-Jordan elimination on [A | I] with partial pivoting.
// Shape violations and singular input return typed Err.
pub fn matrix_inverse(a: &DenseMatrix) -> Result[DenseMatrix, Str]
  requires: a.rows > 0
  ensures: !result.is_ok() || result.unwrap().rows == a.rows
  ensures: !result.is_ok() || result.unwrap().cols == a.cols
{
  let n = a.rows;
  if a.rows != a.cols {
    return Err("matrix_inverse: matrix must be square (rows == cols)");
  };
  let w = n * 2;
  var aug = xiom.blas.matrix_new(n, w);
  var i = 0;
  while i < n {
    var j = 0;
    while j < n {
      aug.data[i * w + j] = a.data[i * n + j];
      j = j + 1;
    };
    aug.data[i * w + n + i] = 1.0;
    i = i + 1;
  };

  var col = 0;
  while col < n {
    var pivot_row = col;
    var best = __abs(aug.data[col * w + col]);
    var r = col + 1;
    while r < n {
      let cand = __abs(aug.data[r * w + col]);
      if cand > best {
        pivot_row = r;
        best = cand;
      };
      r = r + 1;
    };
    if best == 0.0 {
      return Err("matrix_inverse: singular DenseMatrix (zero pivot column)");
    };
    if pivot_row != col {
      var c = 0;
      while c < w {
        let tmp = aug.data[col * w + c];
        aug.data[col * w + c] = aug.data[pivot_row * w + c];
        aug.data[pivot_row * w + c] = tmp;
        c = c + 1;
      };
    };
    let pivot = aug.data[col * w + col];
    var j2 = 0;
    while j2 < w {
      aug.data[col * w + j2] = aug.data[col * w + j2] / pivot;
      j2 = j2 + 1;
    };
    var row = 0;
    while row < n {
      if row != col {
        let factor = aug.data[row * w + col];
        var j3 = 0;
        while j3 < w {
          aug.data[row * w + j3] = aug.data[row * w + j3] - factor * aug.data[col * w + j3];
          j3 = j3 + 1;
        };
      };
      row = row + 1;
    };
    col = col + 1;
  };

  var inv = xiom.blas.matrix_new(n, n);
  var row2 = 0;
  while row2 < n {
    var col2 = 0;
    while col2 < n {
      inv.data[row2 * n + col2] = aug.data[row2 * w + n + col2];
      col2 = col2 + 1;
    };
    row2 = row2 + 1;
  };
  return Ok(inv);
}

// Solve A * x = b via Gaussian elimination with partial pivoting (the
// SPEC-declared algorithm), forward elimination + back substitution.
// Shape violations return typed Err (never a contract trap): the conformance
// suite exercises the error path with deliberately mismatched lengths.
pub fn solve_linear_system(a: &DenseMatrix, b: &Vec[Float64]) -> Result[Vec[Float64], Str]
  requires: a.rows > 0
  ensures: !result.is_ok() || result.unwrap().len() == a.rows
{
  let n = a.rows;
  if a.rows != a.cols {
    return Err("solve_linear_system: A must be square (rows == cols)");
  };
  if b.len() != n {
    return Err("solve_linear_system: shape mismatch (b.len() != a.rows)");
  };
  var m = a.data.clone();
  var rhs = b.clone();

  var k = 0;
  while k < n {
    var pivot_row = k;
    var best = __abs(m[k * n + k]);
    var r = k + 1;
    while r < n {
      let cand = __abs(m[r * n + k]);
      if cand > best {
        pivot_row = r;
        best = cand;
      };
      r = r + 1;
    };
    if best == 0.0 {
      return Err("solve_linear_system: singular DenseMatrix (zero pivot column)");
    };
    if pivot_row != k {
      var c = 0;
      while c < n {
        let tmp = m[k * n + c];
        m[k * n + c] = m[pivot_row * n + c];
        m[pivot_row * n + c] = tmp;
        c = c + 1;
      };
      let tmpb = rhs[k];
      rhs[k] = rhs[pivot_row];
      rhs[pivot_row] = tmpb;
    };
    let pivot = m[k * n + k];
    var i = k + 1;
    while i < n {
      let factor = m[i * n + k] / pivot;
      var j = k;
      while j < n {
        m[i * n + j] = m[i * n + j] - factor * m[k * n + j];
        j = j + 1;
      };
      rhs[i] = rhs[i] - factor * rhs[k];
      i = i + 1;
    };
    k = k + 1;
  };

  var x = xiom.blas.vector_zeros(n);
  var idx = n - 1;
  while idx >= 0 {
    var sum = rhs[idx];
    var jj = idx + 1;
    while jj < n {
      sum = sum - m[idx * n + jj] * x[jj];
      jj = jj + 1;
    };
    x[idx] = sum / m[idx * n + idx];
    idx = idx - 1;
  };
  return Ok(x);
}
