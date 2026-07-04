// XIOM — BLAS/LAPACK Bindings (Linear Algebra)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.blas

pub type Matrix = { rows: Int; cols: Int; data: Vec[Float64]; } derive[Clone]

pub fn matmul(a: &Matrix, b: &Matrix) -> Result[Matrix, Str];
pub fn matvec(a: &Matrix, x: &Vec[Float64]) -> Result[Vec[Float64], Str];
pub fn dot(x: &Vec[Float64], y: &Vec[Float64]) -> Float64;
pub fn axpy(alpha: Float64, x: &Vec[Float64], y: &mut Vec[Float64]);
pub fn scal(alpha: Float64, x: &mut Vec[Float64]);

pub fn matrix_new(rows: Int, cols: Int) -> Matrix;
pub fn matrix_zeros(rows: Int, cols: Int) -> Matrix;
pub fn matrix_identity(n: Int) -> Matrix;
pub fn matrix_transpose(a: &Matrix) -> Matrix;
pub fn matrix_add(a: &Matrix, b: &Matrix) -> Result[Matrix, Str];
pub fn matrix_sub(a: &Matrix, b: &Matrix) -> Result[Matrix, Str];
pub fn vector_zeros(n: Int) -> Vec[Float64];
pub fn vector_ones(n: Int) -> Vec[Float64];
