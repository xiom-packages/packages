# xiom-openblas — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: CRITICAL
**Status**: Phase 1 implemented (stub computations, contracts, tests)
**Depends on**: xiom.ffi (stdlib), xiom.alloc (stdlib)

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

## Implementation (Phase 1)

### Files
| File | Lines | Purpose |
|------|-------|---------|
| `openblas.xi` | ~330 | Module `xiom.openblas` — extern C block, pool, safe wrappers, LAPACK stubs |
| `tests/test_conformance.xi` | ~350 | 32 conformance tests — lifecycle, BLAS 1-3, LAPACK stubs, error paths |
| `ROADMAP.md` | — | Phased plan: Core → LAPACK full → Sparse → MT → Integration |
| `SPEC.md` | — | This file (updated) |

### API surface (implemented)
```xiom
module xiom.openblas

pub type Matrix = Int

pub fn matrix_create(rows: Int, cols: Int) -> Result[Matrix, Str]
pub fn matrix_free(m: Matrix)
pub fn matrix_get(m: &Matrix, row: Int, col: Int) -> Float64
pub fn matrix_set(m: &mut Matrix, row: Int, col: Int, val: Float64)
pub fn matrix_rows(m: &Matrix) -> Int
pub fn matrix_cols(m: &Matrix) -> Int

pub fn dot(x: &Vec[Float64], y: &Vec[Float64], n: Int) -> Float64
pub fn axpy(alpha: Float64, x: &Vec[Float64], y: &mut Vec[Float64], n: Int)

pub fn gemv(trans: Bool, m: Int, n: Int, alpha: Float64, A: &Matrix, x: &Vec[Float64], beta: Float64, y: &mut Vec[Float64])
pub fn gemm(transA: Bool, transB: Bool, m: Int, n: Int, k: Int, alpha: Float64, A: &Matrix, B: &Matrix, beta: Float64, C: &mut Matrix)

pub fn svd(A: &Matrix) -> Result[(Matrix, Matrix, Matrix), Str]
pub fn eigen_sym(A: &Matrix) -> Result[(Matrix, Matrix), Str]
pub fn solve(A: &Matrix, b: &Vec[Float64]) -> Result[Matrix, Str]
```

### Delta from original SPEC
| Item | SPEC (original) | Implemented | Reason |
|------|-----------------|-------------|--------|
| `matrix_new` | `matrix_new` | `matrix_create` | More descriptive; matches ecosystem convention |
| `dot` params | `dot(n, x, y)` | `dot(x, y, n)` | Vectors first, count last (ergonomic) |
| `axpy` params | `axpy(n, a, x, y)` | `axpy(alpha, x, y, n)` | Alpha first (BLAS convention), count last |
| `svd` return | `(Matrix, Vec, Matrix)` | `(Matrix, Matrix, Matrix)` | S_diag as diagonal matrix (uniform return) |
| `eigen_sym` return | `(Vec, Matrix)` | `(Matrix, Matrix)` | Eigenvalues as diagonal matrix (uniform return) |
| `solve` return | `Vec[Float64]` | `Matrix` (n×1) | Column vector as Matrix (uniform handle) |

### Internal architecture
- **Pool**: 5 parallel `Vec` arrays (`__pool_data`, `__pool_rows`, `__pool_cols`, `__pool_start`, `__pool_used`)
- **Handle**: 1-based index into pool; 0 = invalid
- **BLAS 1-3**: Pure XIOM loop implementations (linked OpenBLAS pending)
- **LAPACK**: Stub implementations returning identity/zero placeholders
- **Contracts**: `requires` on all dimension and bounds checks

## XIOM design notes
- `pub type Matrix = Int` (newtype, opaque handle)
- All functions have `requires`/`ensures` contracts
- Return `Result[T, Str]` for allocation/calculation failures
