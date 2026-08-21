// XIOM -- BLAS/LAPACK Bindings (Linear Algebra)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.blas

pub type Matrix = { rows: Int; cols: Int; data: Vec[Float64]; } derive[Clone]

pub fn matmul(a: &Matrix, b: &Matrix) -> Result[Matrix, Str];
pub fn matvec(a: &Matrix, x: &Vec[Float64]) -> Result[Vec[Float64], Str];
pub fn dot(x: &Vec[Float64], y: &Vec[Float64]) -> Float64;
pub fn axpy(alpha: Float64, x: &Vec[Float64], y: &mut Vec[Float64]);
pub fn scal(alpha: Float64, x: &mut Vec[Float64]);

pub fn matrix_new(rows: Int, cols: Int) -> Matrix
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
  return Matrix{ rows: rows, cols: cols, data: data };
}

pub fn matrix_zeros(rows: Int, cols: Int) -> Matrix
  requires: rows > 0
  requires: cols > 0
{
  return matrix_new(rows, cols);
}

pub fn matrix_identity(n: Int) -> Matrix
  requires: n > 0
{
  var m = matrix_new(n, n);
  var i = 0;
  while i < n {
    m.data[i * n + i] = 1.0;
    i = i + 1;
  };
  return m;
}

pub fn matrix_transpose(a: &Matrix) -> Matrix
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

pub fn matrix_add(a: &Matrix, b: &Matrix) -> Result[Matrix, Str]
  requires: a.rows > 0
  requires: a.cols > 0
  requires: b.rows > 0
  requires: b.cols > 0
{
  if a.rows != b.rows || a.cols != b.cols {
    return Err("dimension mismatch");
  };
  var result = matrix_new(a.rows, a.cols);
  var i = 0;
  while i < a.data.len() {
    result.data[i] = a.data[i] + b.data[i];
    i = i + 1;
  };
  return Ok(result);
}

pub fn matrix_sub(a: &Matrix, b: &Matrix) -> Result[Matrix, Str]
  requires: a.rows > 0
  requires: a.cols > 0
  requires: b.rows > 0
  requires: b.cols > 0
{
  if a.rows != b.rows || a.cols != b.cols {
    return Err("dimension mismatch");
  };
  var result = matrix_new(a.rows, a.cols);
  var i = 0;
  while i < a.data.len() {
    result.data[i] = a.data[i] - b.data[i];
    i = i + 1;
  };
  return Ok(result);
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
