# ROADMAP -- xiom.openblas

## Phase 1 -- Core Foundation (CURRENT)

**Status:** COMPLETE -- conformance-green (42/42 x2 on compiler v0.64.6) on both
legs: the offline stub/SKIP artifact and the real linked OpenBLAS artifact
(OpenBLAS v0.3.34 Windows x64 LP64/Int32, BSD-3-Clause; see PROVENANCE.md).

- [x] Module scaffold (`module xiom.openblas`)
- [x] `pub type Matrix = Int` opaque handle
- [x] Internal pool-based matrix storage (5 parallel Vecs)
- [x] `extern "C"` block: cblas_ddot, cblas_daxpy, cblas_dgemv, cblas_dgemm
      (int32 blasint ABI, matching real LP64 OpenBLAS)
- [x] `extern "C"` block: dgesvd_, dsyev_, dgesv_ (LAPACK FORTRAN linkage)
- [x] `matrix_create` / `matrix_free` / `matrix_get` / `matrix_set` with contracts
- [x] `matrix_rows` / `matrix_cols` accessors
- [x] Safe wrappers: `dot`, `axpy`, `gemv`, `gemm` (pure XIOM loop impl)
- [x] LAPACK stubs: `svd`, `eigen_sym`, `solve` (return identity/zero placeholders)
- [x] 32 conformance tests in `tests/test_conformance.xi` (xiom.test API)
- [x] Offline stub link-seam: `bridge/openblas_bridge.c` + `port.args.json`
      (suite compiles/runs on machines with no OpenBLAS installed)
- [x] Real-library probe: `tests/probe_real_openblas.xi` + shim (runtime
      detection; SKIP-safe; real cblas_ddot + cblas_dgemm verified on this box
      against an LP64 OpenBLAS build when pointed at it via XIOM_OPENBLAS_LIB)
- [x] Link the suite against real system OpenBLAS at build time (replace the
      stub seam with a real import library; do not link both) --
      `bridge/openblas_real_marker.c` + `--link-path <root>/lib --link
      libopenblas`; `tests/run_real_leg.ps1` keeps the offline artifact on the
      stub seam. `xiom_openblas_backend()` selects the leg at runtime.
- [x] Replace pure-XIOM loops with `cblas_*` calls via raw pointer extraction
      (`cblas_ddot`/`daxpy`/`dgemv`/`dgemm` over pool/Vec pointers; transposed
      paths included; pure-XIOM kept only as the offline fallback)
- [x] Replace LAPACK stubs with real `dgesvd_`/`dsyev_`/`dgesv_` invocations
      (column-major marshalling, economy SVD, ascending eigenpairs, LU pivots)
- [x] Workspace query for allocation (bridge C memory into XIOM Vec): LAPACK
      `lwork = -1` query, then an XIOM `Vec[Float64]` of exactly `lwork` slots
      is handed to the second call; `ipiv` is an int32 view over Vec storage
- [x] Run test suite with linked OpenBLAS, verify numerical accuracy --
      42/42 x2 on both legs; U*S*VT reconstruction (4x3 and 2x3, tol 1e-9),
      singular values, symmetric eigenpairs, and solve values asserted
      (evidence in README.md / docs/REAL-LEG.md)

**Effort:** Phase 1 complete (real leg landed 2026-10-17)

## Phase 2 -- LAPACK Full Coverage

- [ ] `dgetrf` / `dgetrs` (LU decomposition + solve)
- [ ] `dgeqrf` / `dorgqr` (QR decomposition)
- [ ] `dpotrf` / `dpotrs` (Cholesky)
- [ ] `dgeev` (non-symmetric eigenvalues)
- [ ] `dgesdd` (divide-and-conquer SVD, faster)
- [ ] `dgelss` / `dgelsd` (least-squares)
- [ ] Workspace auto-sizing helpers for LAPACK `lwork` queries

**Effort:** ~3 days

## Phase 3 -- Sparse Matrix Support

- [ ] `SparseMatrix` opaque handle type
- [ ] CSR / CSC / COO format constructors
- [ ] `sparse_to_dense` / `dense_to_sparse`
- [ ] Sparse BLAS wrappers (if available in OpenBLAS build)
- [ ] Banded matrix support (`dgbmv`, `dgbsv`)

**Effort:** ~1 week

## Phase 4 -- Multi-threaded Configuration

- [ ] `set_num_threads(n: Int)` wrapper over `openblas_set_num_threads`
- [ ] `get_num_threads() -> Int`
- [ ] `get_parallel() -> Int` (current parallel mode)
- [ ] Thread-aware pool: ensure Matrix handles are thread-safe
- [ ] Per-operation thread override patterns

**Effort:** ~1 day

## Phase 5 -- Ecosystem Integration

- [ ] `package.toml` manifest for `xiom.openblas`
- [ ] CI: matrix of (Linux, macOS, Windows) x (system OpenBLAS, build from source);
      the probe's SKIP-safe design lets CI keep an OpenBLAS-free leg
- [ ] Downstream package smoke tests: verify `xiom-lapacke`, `xiom-arpack`, etc. link correctly
- [ ] Downstream consumer: xiom.numpy Phase 2 uses this package for its BLAS/LAPACK-backed ops (see SPEC.md "What xiom.numpy Phase 2 must call")
- [ ] Benchmark suite: vs NumPy, vs Eigen, vs raw C -- publish in docs/benchmarks.md

**Effort:** ongoing
