# xiom.blas Specification

## Overview
BLAS/LAPACK FFI bindings for XIOM. Provides high-performance linear algebra via OpenBLAS (or any CBLAS-compatible library). Targets ML, scientific computing, and numerical workflows.

## Architecture

### Layers
```
+--------------------------------------+
|  src/linalg.xi   (Safe XIOM API)     |
|  Matrix, vector ops with contracts   |
|--------------------------------------|
|  blas.xi         (Raw FFI decls)     |
|  matmul, matvec, dot, axpy, scal     |
|--------------------------------------|
|  blas.xiom-bind  (C ABI mapping)     |
|  cblas_dgemm, cblas_ddot, etc.       |
`--------------------------------------+
```

### Design Decisions
- `Matrix` is a flat row-major `Vec[Float64]` with explicit `rows`/`cols` metadata.
- All operations validate dimension compatibility before calling BLAS.
- The `linalg` module provides pure-XIOM operations (LU decomposition, Gaussian elimination) independent of the FFI path for operations not in standard BLAS.

## Type System

### Matrix
```
pub type Matrix = { data: Vec[Float64]; rows: Int; cols: Int; }
```
- Row-major ordering: element `(i, j)` is at index `i * cols + j`.
- Default-constructed matrices are zero-filled.
- `derive[Clone]` for value semantics.

### Dimension Contracts
Every matrix-producing function enforces:
- `requires: rows > 0, cols > 0` on construction
- `requires: a.cols == b.rows` on multiplication
- `requires: a.rows == b.rows, a.cols == b.cols` on addition/subtraction
- `requires: a.len() == b.len()` on vector dot product

## API Surface

### Construction
| Function | Description |
|----------|-------------|
| `matrix_new(rows, cols)` | Zero-initialized matrix |
| `matrix_zeros(rows, cols)` | Explicit zero matrix |
| `identity(n)` | Identity matrix (n x n) |

### Element Access
| Function | Contract |
|----------|----------|
| `matrix_get(m, row, col)` | `requires: row < m.rows, col < m.cols` |
| `matrix_set(m, row, col, val)` | `requires: row < m.rows, col < m.cols` |

### Linear Algebra (FFI via BLAS)
| Function | BLAS Call | Contract |
|----------|-----------|----------|
| `matrix_multiply(a, b)` | `cblas_dgemm` | `a.cols == b.rows` |
| `matrix_vector_multiply(m, v)` | `cblas_dgemv` | `m.cols == v.len()` |
| `vector_dot(a, b)` | `cblas_ddot` | `a.len() == b.len()` |
| `vector_scale(alpha, v)` | `cblas_dscal` | -- |

### Pure XIOM Operations
| Function | Algorithm |
|----------|-----------|
| `matrix_add(a, b)` | Element-wise |
| `matrix_sub(a, b)` | Element-wise |
| `matrix_scale(m, s)` | Scalar multiply |
| `matrix_transpose(m)` | Row-column swap |
| `matrix_determinant(m)` | LU decomposition |
| `matrix_inverse(m)` | LU with forward/back substitution |
| `solve_linear_system(a, b)` | Gaussian elimination with partial pivoting |

## External Dependencies
- **Runtime:** OpenBLAS -- `libopenblas.dll` / `libopenblas.so`
- **Fallback:** Any CBLAS-compatible library (Netlib BLAS, ATLAS, Intel MKL)
- **Link flags:** `-l openblas -l lapack`

## Error Handling
1. Dimension mismatches return `Err(Str)` with descriptive message.
2. Singular matrices during `inverse()` or `solve_linear_system()` return `Err("singular matrix")`.
3. BLAS errors (negative dimensions, invalid leading dimensions) propagate as strings.
4. Index out-of-bounds on `get`/`set` is caught by contracts at compile time.
