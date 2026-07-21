# xiom-blas — Linear Algebra

High-performance BLAS/LAPACK bindings for XIOM. Matrix operations, vector math, and linear system solvers for ML and scientific computing.

## Install

```powershell
xiom pkg install xiom-blas
```

## Requirements

- **OpenBLAS** (or any CBLAS-compatible library)
  - Linux: `apt install libopenblas-dev`
  - macOS: `brew install openblas`
  - Windows: vcpkg (`vcpkg install openblas`)

## Link Flags

```
-l openblas -l lapack
```

## Quick Start

```xiom
use xiom.blas;

fn main() -> Result[Unit, Str] {
  let a = matrix_new(2, 3);
  let b = matrix_new(3, 2);

  let c = matrix_multiply(&a, &b)?;

  return Ok(());
}
```

## API Overview

| Module | File | Purpose |
|--------|------|---------|
| `xiom.blas` | `blas.xi` | FFI declarations (BLAS calls) |
| `xiom.blas.linalg` | `src/linalg.xi` | Pure XIOM linear algebra with contracts |

### Matrix Operations

```xiom
let m = matrix_new(4, 4);              // Zero-initialized 4x4
let val = matrix_get(&m, 0, 1);        // Read element
matrix_set(&mut m, 0, 1, 3.14);       // Write element

let t = matrix_transpose(&m);          // Transpose
let s = matrix_scale(&m, 2.0);         // Scalar multiply
let sum = matrix_add(&a, &b)?;          // Element-wise add
let prod = matrix_multiply(&a, &b)?;    // BLAS gemm
let inv = matrix_inverse(&m)?;          // Compute inverse
let det = matrix_determinant(&m);       // Determinant via LU
```

### Linear Systems

```xiom
let a = matrix_new(3, 3);
let b = vec![1.0, 2.0, 3.0];
let x = solve_linear_system(&a, &b)?;   // Solve Ax = b
```

### Identity Matrix

```xiom
let id = identity(4);                   // 4x4 identity
```

## Contracts

All dimension mismatches are caught via `requires:` contracts:
- `a.cols == b.rows` for matrix multiplication
- `m.rows == m.cols` for determinant/inverse
- `a.rows == b.rows && a.cols == b.cols` for addition/subtraction

## License

MIT or Apache-2.0, at your option.
