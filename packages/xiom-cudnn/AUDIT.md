# AUDIT: xiom.cudnn

## Status (2026-10-17)

| Item | State |
|------|-------|
| Version | 0.1.0 |
| Compiler | xiom v0.64.6 |
| Upstream | `nvidia-cudnn-cu12` 9.27.0.42 (proprietary NVIDIA EULA; nothing vendored) |
| Companion runtimes | `nvidia-cublas-cu12` 12.9.2.10 (needed by cuDNN 9 sub-libraries), `nvcuda.dll` (driver) |
| Link model | one `--c-source` TU (`src/cudnn_bridge.c`); `cudnn64_9.dll` / `cudnn64_8.dll` and `nvcuda.dll` are `LoadLibrary`'d at run time |
| FFI confinement | all `unsafe`/`extern` in the root module `cudnn.xi` (G5) |
| Declared coverage | 25/25 cuDNN entry points + 11/11 CUDA support entry points bound and exercised |
| Suite | `tests/test_conformance.xi`, 60 checks (deterministic SKIP + live probe + full low-level surface) |
| Runs | 60/60 x2 on the pin (cuDNN 92700, RTX 3070 Ti, cc 806) |
| License check | done before use (`PROVENANCE.md` §2); no NVIDIA file committed |

## Design notes

- **Runtime loader only.** The package has no link-time dependency on cuDNN
  or CUDA. An explicit directory is searched as `<dir>\`, `<dir>\bin\`,
  `<dir>\nvidia\cudnn\bin\`; a `.dll` path is accepted; otherwise
  `XIOM_CUDNN_DIR`, `CUDNN_DIR`, then PATH. `cudnn64_9.dll` is preferred,
  `cudnn64_8.dll` is the fallback. A bogus explicit directory never falls
  back to PATH, so the SKIP path is deterministic.
- **Classic graph-free API.** The mission's essentials subset is covered by
  the classic forward calls (still exported by 9.27, marked deprecated
  upstream). The graph/frontend route is a separate roadmap decision; this
  keeps the ABI pin small and auditable.
- **Out-params into XIOM-owned slots.** `cudnnGetTensor4dDescriptor` writes
  nine `int64_t` slots into a `Vec[Int]`; the loader/probe write their
  results into `Vec[Int]` / `Vec[Float32]` buffers. No foreign pointer is
  read through (B-20/B-11).
- **Packed/scalar C boundary.** Handle/descriptor factories return the
  opaque pointer as `Int64` (0 on failure) and expose `cn_last_status()` /
  `cn_last_error()`; status-returning calls return the raw code.
- **Classification.** `-100`/`-102`/`-104` are SKIP; `-101`, positive
  `cudnnStatus_t`, and other runtime failures are FAIL with the upstream
  error text (`cudnnGetErrorString`) in the typed error.
- **Probe determinism.** 1x1x4x4 input `1..16`, 1x1x3x3 all-ones filter,
  valid convolution -> `54/63/90/99`; ReLU identity and a negative-input
  clamp check; 2x2 max pool -> `99`; channel softmax over `(1,2,3,4)` with
  sum ~1. The same values are checked through the public low-level wrappers.

## Known limitations

- 4D NCHW float only; default stream 0; no backward/graph/fused surface.
- The probe requires `cublasLt64_12.dll` for cuDNN 9's engine sub-libraries
  (the wheel declares `nvidia-cublas-cu12` as a dependency). The bridge
  resolves cuDNN explicitly but the cuBLAS dependency is found via PATH --
  the suite is SKIP-safe if it is missing.
- `cudnn64_8.dll` fallback is implemented but not live-tested on this host.
- Windows x64 only in 0.1.0.
- Coverage is 100% of the **declared essentials subset**, not all cuDNN
  symbols.
