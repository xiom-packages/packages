# AUDIT: xiom.cusparse

## Status (2026-10-17)

| Item | State |
|------|-------|
| Version | 0.1.0 (loader-only, nothing vendored) |
| Compiler | xiom v0.64.6 (pin) |
| Upstream | NVIDIA cuSPARSE 12.5.10 (`nvidia-cusparse-cu12` 12.5.10.65 wheel; proprietary) |
| Link model | one `--c-source` TU (`src/cusparse_bridge.c`); `cusparse64_12.dll` + `nvJitLink_120_0.dll` loaded at run time |
| FFI confinement | all `unsafe`/`extern` in `cusparse.xi` (G5) |
| Suite | `tests/test_conformance.xi` |
| Live runs | **54/54 x2** on the host RTX 3070 Ti (driver 13.4, cuSPARSE 12510) |
| SKIP run | **5/5** with the runtime absent (`CUSPARSE_LOAD_ABSENT`) |
| Publish | false -- new 0.1.0, allowlist append owned by the native lane |

## Design notes

- **Loader-only**: `cusparse64_13/12/11/10.dll` fallbacks; explicit
  `cusparse_load_from(dir)` is strict (no bare-name fallback) so the SKIP
  path is deterministic on any host. `XIOM_CUSPARSE_DIR` drives the live
  leg; the OS search is the fallback.
- **Context ownership**: the bridge loads `nvcuda.dll`, calls `cuInit` and
  creates one context (`cuCtxCreate_v2`); handles/descriptors live on it.
  `CUSPARSE_LOAD_NO_DEVICE` (driver/device absent) is a typed SKIP.
- **HOST scalar mode**: the generic API defaults to HOST pointer mode, so
  `alpha`/`beta` cross as XIOM values and the bridge builds a float or
  double local by `computeType` (other types -> NOT_SUPPORTED).
- **Descriptors**: the generic CSR/DnVec/DnMat descriptors drive SpMV and
  SpMM; the legacy `cusparseMatDescr_t` is exposed and tested standalone.
- **External buffer**: the buffer-size queries are always exercised and
  the returned workspace is allocated and passed to the exec call
  (0-byte estimates pass a null device pointer, which the API accepts).
- **Int32 index uploads**: the CSR row offsets/column indices are moved
  through the driver API with dedicated i32 helpers (no float
  reinterpretation).

## Run matrix (live leg)

| Package | Compiler | Checks | Result | Host |
|---------|----------|--------|--------|------|
| xiom.cusparse | v0.64.6 | 54 | PASS x2 | RTX 3070 Ti, driver 13.4, cuSPARSE 12.5.10 |
| xiom.cusparse (no runtime) | v0.64.6 | 5 | PASS (SKIP line green) | same host, `XIOM_CUSPARSE_DIR` unset |

Numbers exercised: SpMV (f64 and f32) `A*x = [5,6,13]`; SpMM (f64)
`A*B = [[3,1],[0,3],[5,4]]`; buffer queries 8 bytes for both algorithms.

## Known limitations

- Windows x64 only (LoadLibrary + `nvcuda.dll`).
- Single-threaded bridge and thread-affine context; create/destroy on the
  same thread.
- Declared surface is CSR + dense descriptors with SpMV/SpMM; COO/BSR/CSC,
  SpGEMM, triangular solves and preprocess APIs are out of scope for
  0.1.0.
- Compute/value types limited to `CUDA_R_32F` / `CUDA_R_64F`.
- The generic API's device-pointer mode and 64-bit index arrays are
  supported by the binding (CUSPARSE_INDEX_64I is a valid argument) but
  the suite exercises 32-bit indices.
