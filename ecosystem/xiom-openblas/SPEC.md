# xiom-openblas — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: CRITICAL
**Status**: SPEC only — no implementation yet
**Depends on**: xiom.ffi (stdlib)

## What it wraps
OpenBLAS — optimized Basic Linear Algebra Subprograms (BLAS) and LAPACK.
Foundation for ALL scientific computing and ML packages.

## Dependencies

| What | How | Size |
|------|-----|------|
| OpenBLAS | System-installed. `winget install OpenBLAS`, `apt install libopenblas-dev` | ~30MB |
| C compiler | For building bridge .obj | — |

## Bundling strategy
**System-installed only.** OpenBLAS is available on every platform via package managers.
Never bundle — link against system library.

## API surface

```xiom
module xiom.openblas

// Matrix creation
pub fn matrix_new(rows: Int, cols: Int) -> Result[Matrix, Str]
pub fn matrix_free(m: Matrix)
pub fn matrix_get(m: &Matrix, row: Int, col: Int) -> Float64
pub fn matrix_set(m: &mut Matrix, row: Int, col: Int, val: Float64)

// BLAS Level 1 (vector-vector)
pub fn dot(n: Int, x: &Vec[Float64], y: &Vec[Float64]) -> Float64
pub fn axpy(n: Int, a: Float64, x: &Vec[Float64], y: &mut Vec[Float64])

// BLAS Level 2 (matrix-vector)
pub fn gemv(trans: Bool, m: Int, n: Int, a: Float64, A: &Matrix, x: &Vec[Float64], b: Float64, y: &mut Vec[Float64])

// BLAS Level 3 (matrix-matrix)
pub fn gemm(transA: Bool, transB: Bool, m: Int, n: Int, k: Int, alpha: Float64, A: &Matrix, B: &Matrix, beta: Float64, C: &mut Matrix)

// LAPACK
pub fn svd(A: &Matrix) -> Result[(Matrix, Vec[Float64], Matrix), Str]
pub fn eigen_sym(A: &Matrix) -> Result[(Vec[Float64], Matrix), Str]
pub fn solve(A: &Matrix, b: &Vec[Float64]) -> Result[Vec[Float64], Str]
```

## Contract coverage target
- All matrix operations: `requires: m.rows > 0, m.cols > 0`
- Dimension compatibility checked at call site
- Memory allocation: `Result` with error message

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | BLAS Level 1-3 + matrix create/free | Weekend |
| 2 | LAPACK: SVD, Eigendecomp, Solve, LU, QR | Weekend |
| 3 | Sparse matrix support | Week |
| 4 | Multi-threaded BLAS configuration | Day |

## XIOM design notes
- `pub type Matrix = Int` (newtype, opaque handle)
- All functions have `requires`/`ensures` contracts
- Return `Result[T, Str]` for allocation/calculation failures
