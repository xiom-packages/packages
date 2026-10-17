# AUDIT: xiom.cublas

## Status (2026-10-17)

| Item | State |
|------|-------|
| Version | 0.1.0 (loader-only, nothing vendored) |
| Compiler | xiom v0.64.6 (pin) |
| Upstream | NVIDIA cuBLAS 12.9.2 (`nvidia-cublas-cu12` 12.9.2.10 wheel; proprietary) |
| Link model | one `--c-source` TU (`src/cublas_bridge.c`); `cublas64_12.dll` loaded at run time |
| FFI confinement | all `unsafe`/`extern` in `cublas.xi` (G5) |
| Suite | `tests/test_conformance.xi` |
| Live runs | **62/62 x2** on the host RTX 3070 Ti (driver 13.4, cuBLAS 120902) |
| SKIP run | **5/5** with the runtime absent (`CUBLAS_LOAD_ABSENT`) |
| Publish | false -- new 0.1.0, allowlist append owned by the native lane |

## Design notes

- **Loader-only**: `cublas64_13/12/11/10.dll` fallbacks; explicit
  `cublas_load_from(dir)` is strict (no bare-name fallback) so the SKIP
  path is deterministic on any host. `XIOM_CUBLAS_DIR` drives the live
  leg; the OS search is the fallback.
- **Context ownership**: the bridge loads `nvcuda.dll`, calls `cuInit` and
  creates one context (`cuCtxCreate_v2`); the cuBLAS handle is created on
  it. `CUBLAS_LOAD_NO_DEVICE` (driver/device absent) is a typed SKIP.
- **Scalar returns without out-param slots**: `sdot`/`ddot`/`snrm2` cache
  the result in the bridge and XIOM reads it through a second accessor
  (B-11 discipline, same posture as `xiom.cuda`).
- **Opaque values as `Int`**: handles and device addresses cross as
  `int64_t`; XIOM never dereferences foreign memory (G5).
- **Column-major pass-through**: the wrappers do not reinterpret
  matrices; the suite demonstrates the row-major transpose identity.

## Run matrix (live leg)

| Package | Compiler | Checks | Result | Host |
|---------|----------|--------|--------|------|
| xiom.cublas | v0.64.6 | 62 | PASS x2 | RTX 3070 Ti, driver 13.4, cuBLAS 12.9.2 |
| xiom.cublas (no runtime) | v0.64.6 | 5 | PASS (SKIP line green) | same host, `XIOM_CUBLAS_DIR` unset |

Numbers exercised: sgemm/dgemm `[19,22,43,50]`; saxpy `[12,24,36]`;
sdot/ddot `168`; sscal `[3,6,9]`; snrm2 `5`; sgemv/dgemv `[6,15]`.

## Known limitations

- Windows x64 only (LoadLibrary + `nvcuda.dll`).
- Single-threaded bridge and thread-affine context; create/destroy on the
  same thread.
- Declared surface is the 16 essentials; batched/strided/`gemmEx`/`trsm`/
  `cublasLt` are out of scope for 0.1.0.
- Device buffers are contiguous Float32/Float64 spans allocated through
  the driver API; no ownership tracking beyond explicit free.
