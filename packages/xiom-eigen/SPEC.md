# xiom-eigen — SPEC

**Phase**: 2 (Scientific) | **Priority**: HIGH
**Status**: IMPLEMENTING — Phase 1 (Core Foundation)
**Depends on**: xiom.ffi

## What it wraps
Eigen — C++ template library for linear algebra. Header-only.
Used in robotics (ROS), computer vision, physics simulation.

## Dependencies
| What | How | Size |
|------|-----|------|
| Eigen 3.4 | `apt install libeigen3-dev` or download headers | ~5MB headers |

## Bundling strategy
**Header-only download.** No DLL. Compile into bridge .obj.
`wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz`

## Architecture

```
packages/xiom-eigen/
├── eigen.xi                    # Module xiom.eigen (~330 lines)
│   ├── Internal pool storage   # 5 parallel Vecs (data, rows, cols, start, used)
│   ├── pub type EigenMatrix    # Opaque Int handle
│   ├── extern "C" block        # Thin C bridge declarations
│   ├── Matrix lifecycle        # matrix_create, matrix_free, matrix_get/set, matrix_rows/cols
│   ├── Matrix algebra          # matrix_multiply, matrix_transpose
│   ├── Decompositions          # matrix_determinant, matrix_inverse, solve
│   └── Stubs                   # svd, eigenvalues (placeholders until bridge linked)
├── tests/
│   └── test_conformance.xi     # 28 tests (Bool-return runner)
├── SPEC.md
└── ROADMAP.md
```

### Layers
```
┌──────────────────────────────────────┐
│  eigen.xi        (Safe XIOM API)     │
│  Matrix ops with requires contracts  │
├──────────────────────────────────────┤
│  Internal pool   (5 Vec storage)     │
│  Opaque Int handles                  │
├──────────────────────────────────────┤
│  extern "C"      (C bridge declarations) │
│  eigen_matrix_create, eigen_svd, ... │
├──────────────────────────────────────┤
│  eigen_bridge.cpp   (to be written)  │
│  Compiles against Eigen 3.4 headers  │
└──────────────────────────────────────┘
```

## Type System

### EigenMatrix
```
pub type EigenMatrix = Int
```
- Opaque integer handle into the module-level pool.
- Pool stores metadata (rows, cols, used flag) and flat Float64 data.
- Row-major ordering: element `(i, j)` at index `i * cols + j`.
- Handles 1-indexed; pool entry at `handle - 1`.

### Dimension Contracts
| Function | Contract |
|----------|----------|
| `matrix_create(rows, cols)` | `requires: rows > 0, cols > 0` |
| `matrix_multiply(a, b)` | `requires: a_cols == b_rows` |
| `matrix_determinant(m)` | `requires: rows == cols` |
| `matrix_inverse(m)` | `requires: rows == cols, det != 0` |
| `solve(a, b)` | `requires: rows == cols, b.len() == rows` |
| `svd(a)` | `requires: rows > 0, cols > 0` |
| `eigenvalues(a)` | `requires: rows == cols` |

## API Surface

### Lifecycle
| Function | Returns | Description |
|----------|---------|-------------|
| `matrix_create(rows, cols)` | `Result[EigenMatrix, Str]` | Zero-initialized matrix |
| `matrix_free(m)` | — | Mark handle freed in pool |
| `matrix_get(m, row, col)` | `Float64` | Element access (returns 0.0 OOB) |
| `matrix_set(m, row, col, val)` | — | Element write (no-op OOB) |
| `matrix_rows(m)` | `Int` | Row count (0 if invalid) |
| `matrix_cols(m)` | `Int` | Column count (0 if invalid) |

### Algebra (Pure XIOM)
| Function | Algorithm | Returns |
|----------|-----------|---------|
| `matrix_multiply(a, b)` | Triple-nested loop | `Result[EigenMatrix, Str]` |
| `matrix_transpose(m)` | Row-col swap loop | `Result[EigenMatrix, Str]` |
| `matrix_determinant(m)` | LU decomposition | `Result[Float64, Str]` |
| `matrix_inverse(m)` | Gauss-Jordan elimination | `Result[EigenMatrix, Str]` |
| `solve(a, b)` | Via inverse + mat-vec multiply | `Result[Vec[Float64], Str]` |

### Decomposition Stubs (placeholder until C bridge linked)
| Function | Current Behavior | Returns |
|----------|-----------------|---------|
| `svd(a)` | Returns identity U, zero S, identity V^T | `Result[(EigenMatrix, EigenMatrix, EigenMatrix), Str]` |
| `eigenvalues(a)` | Returns zero values, identity vectors | `Result[(EigenMatrix, EigenMatrix), Str]` |

### C Bridge (extern "C" — to be implemented in eigen_bridge.cpp)
| C Function | Eigen Class | Description |
|------------|-------------|-------------|
| `eigen_matrix_create` | `MatrixXd` | Allocate dynamic matrix |
| `eigen_matrix_free` | — | Free matrix handle |
| `eigen_matrix_get` | `operator()` | Read element |
| `eigen_matrix_set` | `operator()` | Write element |
| `eigen_matrix_multiply` | `operator*` | Matrix product |
| `eigen_matrix_inverse` | `.inverse()` | Full-pivot LU inverse |
| `eigen_matrix_transpose` | `.transpose()` | Transpose |
| `eigen_matrix_determinant` | `.determinant()` | Determinant |
| `eigen_solve` | `.colPivHouseholderQr().solve()` | Linear system |
| `eigen_svd` | `JacobiSVD` | Singular value decomposition |
| `eigen_eigenvalues` | `EigenSolver` / `SelfAdjointEigenSolver` | Eigenvalue decomposition |

## Error Handling
1. Dimension mismatches return `Err(Str)` with descriptive message.
2. Singular matrices during `inverse()` or `solve()` return `Err("singular matrix")`.
3. Out-of-bounds `get`/`set` silently returns 0.0 or no-ops (contracts catch at compile time).
4. Invalid handles on pool operations return 0/empty gracefully.

## Testing
- **File:** `tests/test_conformance.xi`
- **Count:** 28 tests
- **Pattern:** `fn test_*() -> Bool` with manual `main() -> Int` runner
- **Coverage:** lifecycle (5), element access (5), algebra (4), determinant (3), inverse (2), solve (4), SVD (2), eigenvalues (2), metadata (1)

## Next Steps (see ROADMAP.md)
1. Download Eigen 3.4 headers
2. Write `eigen_bridge.cpp` — thin C ABI over Eigen templates
3. Compile bridge `.obj` and link against XIOM module
4. Replace pure-XIOM loops with Eigen-native calls
5. Replace SVD/eigenvalues stubs with real Eigen decompositions

## Verified
- [x] Module compiles (syntax valid)
- [ ] Tests pass with pure-XIOM implementations
- [ ] C bridge linked at compile time
- [ ] Numerical accuracy benchmarked against NumPy reference
