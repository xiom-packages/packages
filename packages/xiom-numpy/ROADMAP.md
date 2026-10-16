# xiom.numpy -- Roadmap

**Module**: `xiom.numpy`
**Last updated**: 2026-10-16

## Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Core Foundation -- types, extern C, safe wrappers, conformance tests | Done -- GREEN 30/30 x2 (v0.64.5, 2026-10-16; link bridge `bridge/numpy_bridge.c`) |
| 2 | C bridge -- compile numpy_c_* bridge .obj, link against system NumPy + OpenBLAS | Pending |
| 3 | Linear algebra -- SVD, inv, reductions (sum, mean, max) | Partial -- reductions + inv DONE (Phase-3b) -- GREEN 130/130 x2 (v0.64.6, 2026-10-16); SVD pending |
| 4 | Broadcasting + reshaping -- reshape, transpose | DONE (first half) -- GREEN 103/103 x2 (v0.64.6, 2026-10-16) |
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

## Phase 4 -- Broadcasting + reshaping (first half done)

Landed (2026-10-16, v0.64.6): NumPy broadcasting for
`array_add`/`array_sub`/`array_mul`/`array_div` (right-aligned shape
compatibility, stride-0 stretched axes), N-D row-major stride handling over the
flat f64 arena, and copy-based `array_reshape` (C-order) + `array_transpose`
(reverse axes). Suite `tests/test_conformance.xi` grew 83 -> 103 checks (20 new
hand-computed f64 goldens) and is GREEN x2.

## Phase 2 -- C bridge

- Replace `bridge/numpy_bridge.c` (same 17 symbols, same signatures) with the
  PyArray-backed `numpy_c_bridge.c` against NumPy headers and OpenBLAS
- Ensure all 17 extern C symbols resolve at link time
- Update `tests/test_conformance.xi`: flip the twelve "returns Err" checks to
  validate runtime results (creation, element-wise, linear algebra)

## Phase 3 -- Linear algebra (reductions + inv done)

Landed (2026-10-16, v0.64.6): axis-aware reductions `array_sum` / `array_mean` /
`array_max` / `array_min` over the flat f64 arena (`axis == -1` = full-array
reduction yielding shape `[1]`; `axis` in `[0, ndim)` drops that axis), and
`array_inv` (self-contained Gauss-Jordan with partial pivoting, fail-closed on
singular/non-square). Suite `tests/test_conformance.xi` grew 103 -> 130 checks
(27 new: 14 reduction, 8 inverse, 5 contract) and is GREEN x2.

Remaining Phase-3 work:
- `svd(a: &NDArray) -> Result[(NDArray, NDArray, NDArray), Str]` -- deferred:
  `xiom.openblas.svd` is still a Phase-1 stub (identity/zero placeholders), and a
  correct SVD needs a one-sided Jacobi / eigen routine, not a trivial extension
  of Gauss-Jordan. Build it once the real LAPACK wiring (or a self-contained
  Jacobi path) exists.

Historical Phase-3 plan (originally listed here):
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
