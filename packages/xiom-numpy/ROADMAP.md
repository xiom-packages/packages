# xiom.numpy -- Roadmap

**Module**: `xiom.numpy`
**Last updated**: 2026-10-16

## Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Core Foundation -- types, extern C, safe wrappers, conformance tests | Done -- GREEN 30/30 x2 (v0.64.5, 2026-10-16; link bridge `bridge/numpy_bridge.c`) |
| 2 | C bridge -- compile numpy_c_* bridge .obj, link against system NumPy + OpenBLAS | Pending |
| 3 | Linear algebra -- SVD, inv, reductions (sum, mean, max) | Pending |
| 4 | Broadcasting + reshaping -- reshape, transpose | Pending |
| 5 | Advanced -- FFT, random, advanced indexing | Pending |
| 6 | Interop -- zero-copy tensor sharing with xiom.libtorch, xiom.pandas | Pending |

## Phase 1 deliverables (Done)

| File | Lines | Description |
|------|-------|-------------|
| `src/numpy.xi` | ~224 | Module with 4 dtype constants, 17 extern C FFI declarations, 17 safe wrappers with `requires` contracts |
| `tests/test_conformance.xi` | ~402 | 30 conformance checks: dtype constants, creation ops, element-wise ops, linear algebra ops, contract verification (rewritten to the v0.64.5 `xiom.test` API) |
| `bridge/numpy_bridge.c` | ~123 | Phase-1 link bridge: all 17 `numpy_c_*` symbols with argument validation; reports the NumPy backend unavailable (Phase 2 replaces it with PyArray-backed code) |
| `port.args.json` | 4 | Wires `--c-source bridge/numpy_bridge.c` into `port.ps1` suite runs (sqlite/stb/cuda pattern) |
| `ROADMAP.md` | this file | Roadmap and status tracking |

## Phase 2 -- C bridge

- Replace `bridge/numpy_bridge.c` (same 17 symbols, same signatures) with the
  PyArray-backed `numpy_c_bridge.c` against NumPy headers and OpenBLAS
- Ensure all 17 extern C symbols resolve at link time
- Update `tests/test_conformance.xi`: flip the twelve "returns Err" checks to
  validate runtime results (creation, element-wise, linear algebra)

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
- `xiom.openblas` -- BLAS/LAPACK backend for linear algebra ops
- System NumPy installation -- C headers at `numpy/core/include/`

## Relationship to other packages

| Package | Relationship |
|---------|-------------|
| `xiom.openblas` | NumPy delegates BLAS/LAPACK to OpenBLAS |
| `xiom.libtorch` | Zero-copy tensor sharing between NDArray and LibTorch tensors |
| `xiom.pandas` | DataFrame storage backed by NumPy arrays |
| `xiom.scipy` | Scientific routines operating on NumPy arrays |
