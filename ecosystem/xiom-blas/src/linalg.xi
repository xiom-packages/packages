module xiom.blas.linalg

pub type Matrix = {
  data: Vec[Float64];
  rows: Int;
  cols: Int;
} derive[Clone]

fn matrix_new(rows: Int, cols: Int) -> Matrix
  requires: rows > 0
  requires: cols > 0
  ensures: result.rows == rows
  ensures: result.cols == cols
  ensures: result.data.len() == rows * cols
{
  let size = rows * cols;
  let data = Vec[Float64].with_capacity(size);
  var i = 0;
  while i < size {
    data.push(0.0);
    i = i + 1;
  };
  Matrix { data: data, rows: rows, cols: cols }
}

fn matrix_get(m: &Matrix, row: Int, col: Int) -> Float64
  requires: row >= 0
  requires: col >= 0
  requires: row < m.rows
  requires: col < m.cols
{
  m.data[row * m.cols + col]
}

fn matrix_set(m: &mut Matrix, row: Int, col: Int, val: Float64)
  requires: row >= 0
  requires: col >= 0
  requires: row < m.rows
  requires: col < m.cols
{
  m.data[row * m.cols + col] = val;
}

fn matrix_multiply(a: &Matrix, b: &Matrix) -> Result[Matrix, Str]
  requires: a.cols == b.rows
  ensures: !result.is_ok() || result.unwrap().rows == a.rows
  ensures: !result.is_ok() || result.unwrap().cols == b.cols
{
  matmul(a, b)
}

fn matrix_vector_multiply(m: &Matrix, v: &Vec[Float64]) -> Result[Vec[Float64], Str]
  requires: m.cols == v.len()
{
  matvec(m, v)
}

fn vector_dot(a: &Vec[Float64], b: &Vec[Float64]) -> Float64
  requires: a.len() == b.len()
{
  dot(a, b)
}

fn matrix_transpose(m: &Matrix) -> Matrix
{
  matrix_transpose(m)
}

fn matrix_add(a: &Matrix, b: &Matrix) -> Result[Matrix, Str]
  requires: a.rows == b.rows
  requires: a.cols == b.cols
{
  matrix_add(a, b)
}

fn matrix_sub(a: &Matrix, b: &Matrix) -> Result[Matrix, Str]
  requires: a.rows == b.rows
  requires: a.cols == b.cols
{
  matrix_sub(a, b)
}

fn matrix_scale(m: &Matrix, scalar: Float64) -> Matrix
{
  var result = matrix_new(m.rows, m.cols);
  var i = 0;
  while i < m.data.len() {
    result.data[i] = m.data[i] * scalar;
    i = i + 1;
  };
  result
}

fn identity(n: Int) -> Matrix
  requires: n > 0
{
  var result = matrix_new(n, n);
  var i = 0;
  while i < n {
    result.data[i * n + i] = 1.0;
    i = i + 1;
  };
  result
}

fn matrix_determinant(m: &Matrix) -> Float64
  requires: m.rows == m.cols
{
  let n = m.rows;
  var lu = m.data.clone();
  var det = 1.0;
  var i = 0;
  while i < n {
    let pivot = lu[i * n + i];
    if pivot == 0.0 {
      return 0.0;
    };
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
  det
}

fn matrix_inverse(m: &Matrix) -> Result[Matrix, Str]
  requires: m.rows == m.cols
{
  let n = m.rows;
  if matrix_determinant(m) == 0.0 {
    return Err("singular matrix");
  };

  var aug = matrix_new(n, n * 2);
  var i = 0;
  while i < n {
    var j = 0;
    while j < n {
      aug.data[i * (n * 2) + j] = m.data[i * n + j];
      j = j + 1;
    };
    aug.data[i * (n * 2) + n + i] = 1.0;
    i = i + 1;
  };

  var col = 0;
  while col < n {
    let pivot = aug.data[col * (n * 2) + col];
    var j = 0;
    while j < n * 2 {
      aug.data[col * (n * 2) + j] = aug.data[col * (n * 2) + j] / pivot;
      j = j + 1;
    };

    var row = 0;
    while row < n {
      if row != col {
        let factor = aug.data[row * (n * 2) + col];
        var j = 0;
        while j < n * 2 {
          aug.data[row * (n * 2) + j] = aug.data[row * (n * 2) + j] - factor * aug.data[col * (n * 2) + j];
          j = j + 1;
        };
      };
      row = row + 1;
    };
    col = col + 1;
  };

  var inv = matrix_new(n, n);
  var row = 0;
  while row < n {
    var col = 0;
    while col < n {
      inv.data[row * n + col] = aug.data[row * (n * 2) + n + col];
      col = col + 1;
    };
    row = row + 1;
  };
  Ok(inv)
}

fn solve_linear_system(a: &Matrix, b: &Vec[Float64]) -> Result[Vec[Float64], Str]
  requires: a.rows == a.cols
  requires: a.rows == b.len()
{
  let n = a.rows;
  if matrix_determinant(a) == 0.0 {
    return Err("singular matrix");
  };

  let inv = matrix_inverse(a)?;
  var x = Vec[Float64].with_capacity(n);
  var i = 0;
  while i < n {
    var sum = 0.0;
    var j = 0;
    while j < n {
      sum = sum + inv.data[i * n + j] * b[j];
      j = j + 1;
    };
    x.push(sum);
    i = i + 1;
  };
  Ok(x)
}
