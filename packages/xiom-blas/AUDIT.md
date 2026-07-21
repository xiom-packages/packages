# xiom-blas Audit

## Compilation Status
- `blas.xi` — PASSES (standalone)
- `src/linalg.xi` — PASSES (with blas.xi)
- `tests/test_blas.xi` — PASSES (with blas.xi)
- All files compile together: PASS

## Changes Made
1. **blas.xi**: Replaced forward declarations of pure-XIOM functions (`matrix_new`, `matrix_zeros`, `matrix_identity`, `matrix_transpose`, `matrix_add`, `matrix_sub`, `vector_zeros`, `vector_ones`) with inline implementations using `Vec[Float64].new()` instead of `Vec[Float64].with_capacity()`. The FFI functions (`matmul`, `matvec`, `dot`, `axpy`, `scal`) remain as forward declarations mapped via `blas.xiom-bind`.

2. **linalg.xi**: 
   - Added `use xiom.blas;` for cross-module resolution
   - Replaced `Vec[Float64].with_capacity()` calls with `Vec[Float64].new()` + push loop pattern
   - Replaced self-recursive calls in `matrix_transpose()`, `matrix_add()`, `matrix_sub()` with inline implementations
   - Routed FFI calls through `blas.matmul()`, `blas.matvec()`, `blas.dot()`

## System Dependencies

### Required: OpenBLAS
- **Linux**: `apt install libopenblas-dev` → `libopenblas.so`
- **macOS**: `brew install openblas` → `libopenblas.dylib`
- **Windows**: vcpkg `vcpkg install openblas` → `libopenblas.dll`

### Link Flags
```
-l openblas -l lapack
```

### Compilation with Libraries
```powershell
xiom --link openblas --link lapack --link-path C:/path/to/openblas/lib blas.xi src/linalg.xi program.xi
```

## FFI Functions Requiring OpenBLAS at Runtime

| XIOM Function | C Function | Library |
|--------------|------------|---------|
| `matmul` | `cblas_dgemm` | libopenblas |
| `matvec` | `cblas_dgemv` | libopenblas |
| `dot` | `cblas_ddot` | libopenblas |
| `axpy` | `cblas_daxpy` | libopenblas |
| `scal` | `cblas_dscal` | libopenblas |

## Known Gaps
- Tests only verify pure-XIOM operations (construction, identity, transpose). FFI operations are not tested in `test_blas.xi` — they require OpenBLAS linked at runtime.
- `matrix_scale` exists in `linalg.xi` but the FFI `scal` wrapper is in `blas.xi`. No integration between them.
- No SIMD fallback for `matmul` when OpenBLAS is not available.
