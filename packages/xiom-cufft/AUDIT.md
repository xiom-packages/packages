# AUDIT: xiom.cufft

## Status (2026-10-17)

| Item | State |
|------|-------|
| Version | 0.1.0 (loader-only, nothing vendored) |
| Compiler | xiom v0.64.6 (pin) |
| Upstream | NVIDIA cuFFT 11.4.1 (`nvidia-cufft-cu12` 11.4.1.4 wheel; proprietary) |
| Link model | one `--c-source` TU (`src/cufft_bridge.c`); `cufft64_11.dll` loaded at run time |
| FFI confinement | all `unsafe`/`extern` in `cufft.xi` (G5) |
| Suite | `tests/test_conformance.xi` |
| Live runs | **45/45 x2** on the host RTX 3070 Ti (driver 13.4, cuFFT 11401) |
| SKIP run | **5/5** with the runtime absent (`CUFFT_LOAD_ABSENT`) |
| Publish | false -- new 0.1.0, allowlist append owned by the native lane |

## Design notes

- **Loader-only**: `cufft64_12/11/10.dll` fallbacks; explicit
  `cufft_load_from(dir)` is strict (no bare-name fallback) so the SKIP
  path is deterministic on any host. `XIOM_CUFFT_DIR` drives the live
  leg; the OS search is the fallback.
- **Context ownership**: the bridge loads `nvcuda.dll`, calls `cuInit` and
  creates one context (`cuCtxCreate_v2`); plans are created on it.
  `CUFFT_LOAD_NO_DEVICE` (driver/device absent) is a typed SKIP.
- **Plan handles as `Int`**: cuFFT's `cufftHandle` is an `int`; the bridge
  returns `-1` on failure and caches the `cufftResult` for the typed
  error, so a zero handle is never confused with success.
- **Unnormalized transforms**: the suite asserts the documented scaling
  (DC=8 for eight ones; inverse gives 8.0/N=1.0 after scaling; 2D Z2Z
  inverse gives 16.0 = N^2).
- **R2C/C2R layout**: the suite uses the true `N/2+1` complex output size
  (5 bins for N=8), not the padded buffer length.

## Run matrix (live leg)

| Package | Compiler | Checks | Result | Host |
|---------|----------|--------|--------|------|
| xiom.cufft | v0.64.6 | 45 | PASS x2 | RTX 3070 Ti, driver 13.4, cuFFT 11.4.1 |
| xiom.cufft (no runtime) | v0.64.6 | 5 | PASS (SKIP line green) | same host, `XIOM_CUFFT_DIR` unset |

Numbers exercised: R2C eight ones -> `8+0i`; C2R round trip -> `8.0`
(unnormalized); 4x4 Z2Z forward DC -> `16+0i`, inverse -> `16.0`
everywhere; D2Z/Z2D -> `8+0i` / `8.0`.

## Known limitations

- Windows x64 only (LoadLibrary + `nvcuda.dll`).
- Single-threaded bridge and thread-affine context; create/destroy on the
  same thread.
- Declared surface is 1D/2D plans + the six transform types; 3D,
  `cufftPlanMany`, plan properties and `cufftXt` are out of scope for
  0.1.0.
- Device buffers are contiguous Float32/Float64 spans; complex buffers are
  interleaved `2*N` spans.
