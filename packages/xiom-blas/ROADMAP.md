# ROADMAP -- xiom.blas

## Phase 0 -- Seed + park (done, 2026-09/10)

- [x] Package scaffold (`package.xi`, seed `blas.xi` + `blas.xiom-bind`)
- [x] Seed tests/spec (never compiled; parked until the system-BLAS seam
      existed -- `xiom.openblas`)

## Phase 1 -- Fold over xiom.openblas (CURRENT, 0.1.0, done 2026-10-17)

- [x] Safe value type (`DenseMatrix`, row-major `Vec[Float64]`) with
      shape-checked, typed errors; no `unsafe`/`extern` in the API
- [x] FFI seam delegates to the `xiom.openblas` declared surface
      (`gemm`/`gemv`/`dot`/`axpy`), with pool conversion + frees on every path
- [x] Pure decompositions with partial pivoting (det/inverse/solve)
- [x] Runtime availability classifier mirroring the canonical rules
- [x] Offline suite 50/50 x2 (typed-absent SKIP recorded) + real-lib probe
      SKIP x2 + present x2 green on v0.64.5
- [x] Coverage table + compile-evidenced declared-set walk

## Phase 2 -- Real cblas wire-in (gated on xiom.openblas Phase 1 remainder)

- [ ] Flip the seam's reference loops to real `cblas_dgemm`/`dgemv`/`ddot`/
      `daxpy` calls once `xiom.openblas` lands its Phase-1 remainder
      (no API change here; the probe's present-path goldens already pin the
      equivalence)
- [ ] Add `cblas_dscal` to the seam and route `scal`/`vector_scale` through it
- [ ] Numerical-accuracy harness (relative-error bounds vs the reference
      loops on larger shapes)

## Phase 3 -- LAPACK surface (gated on xiom.openblas LAPACK)

- [ ] `svd`, `eigen_sym`, `solve` wrappers over the seam once its LAPACK
      stubs are replaced with real `dgesvd_`/`dsyev_`/`dgesv_` invocations
- [ ] LU/QR/Cholesky wrappers (partial pivoting already in-tree for solve)

## Phase 4 -- Ecosystem

- [ ] Publish gate: allowlist + registry (R-series), after Phase 2
- [ ] `xiom.vectors` contract alignment (accelerator-behind-contract position
      stays: this package mirrors, never defines, the portable contract)
- [ ] Reference consumers: examples for `xiom.numpy`-style interop
