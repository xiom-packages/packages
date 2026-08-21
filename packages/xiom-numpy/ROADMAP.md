# xiom-numpy -- Roadmap

**Module**: `xiom.numpy`
**Last updated**: 2026-07-21

## Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Core Foundation -- types, extern C, safe wrappers, conformance tests | Done |
| 2 | C bridge -- compile numpy_c_* bridge .obj, link against system NumPy + OpenBLAS | Pending |
| 3 | Linear algebra -- SVD, inv, reductions (sum, mean, max) | Pending |
| 4 | Broadcasting + reshaping -- reshape, transpose | Pending |
| 5 | Advanced -- FFT, random, advanced indexing | Pending |
| 6 | Interop -- zero-copy tensor sharing with xiom-libtorch, xiom-pandas | Pending |

## Phase 1 deliverables (Done)

| File | Lines | Description |
|------|-------|-------------|
| `src/numpy.xi` | ~230 | Module with 4 dtype constants, 17 extern C FFI declarations, 17 safe wrappers with `requires` contracts |
| `tests/test_conformance.xi` | ~310 | 30 conformance tests: dtype constants, creation ops, element-wise ops, linear algebra ops, contract verification |
| `ROADMAP.md` | this file | Roadmap and status tracking |

## Phase 2 -- C bridge

- Compile NumPy C API bridge (`numpy_c_bridge.c`) against NumPy headers and OpenBLAS
- Ensure all 17 extern C symbols resolve at link time
- Update `tests/test_conformance.xi` to validate runtime results

## Phase 3 -- Linear algebra

- `svd(a: &NDArray) -> Result[(NDArray, NDArray, NDArray), Str]`
- `inv(a: &NDArray) -> Result[NDArray, Str]`
- `sum(arr: &NDArray, axis: Int) -> Result[NDArray, Str]`
- `mean(arr: &NDArray, axis: Int) -> Result[NDArray, Str]`
- `max(arr: &NDArray, axis: Int) -> Result[NDArray, Str]`

## Phase 4 -- Broadcasting + reshaping

- `reshape(arr: &NDArray, new_shape: Vec[Int]) -> Result[NDArray, Str]`
- `transpose(arr: &NDArray) -> Result[NDArray, Str]`
- Broadcasting rules enforced at runtime with shape compatibility checks

## Dependencies

- `xiom.ffi` (stdlib) -- extern C calling convention
- `xiom-openblas` -- BLAS/LAPACK backend for linear algebra ops
- System NumPy installation -- C headers at `numpy/core/include/`

## Relationship to other packages

| Package | Relationship |
|---------|-------------|
| `xiom-openblas` | NumPy delegates BLAS/LAPACK to OpenBLAS |
| `xiom-libtorch` | Zero-copy tensor sharing between NDArray and LibTorch tensors |
| `xiom-pandas` | DataFrame storage backed by NumPy arrays |
| `xiom-scipy` | Scientific routines operating on NumPy arrays |
