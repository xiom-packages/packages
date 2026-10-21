# xiom.openblas

> **Status:** `incubating` -- conformance-green on compiler v0.64.8 (52/52,
> two consecutive runs on the offline leg; 52/52 on the linked real leg);
> published in `eco-v0.1.193`
> (sha256 `a6740ae1...`, 2026-10-16); `0.1.1` in `eco-v0.1.200`
> (sha256 `43d609d3...`, 2026-10-19 -- Phase-1 real cblas/LAPACK leg).
> **Unreleased additive Float32 surface** (`dot_f32`/`norm_f32`/`axpy_f32`,
> REL-20261021-1121-xvector) -- Float64 API unchanged.
> **Scope:** OpenBLAS backend integration and acceleration (BLAS 1-3, LAPACK
> SVD/eigen/solve, matrix lifecycle).
> **Deps:** stdlib; wraps C (FFI) through a declared extern "C" surface.

## Two-leg verification (see SPEC.md)

The same suite (`tests/test_conformance.xi`, 52 checks) runs on two separate
artifacts; the stub seam and real OpenBLAS are never linked together.

| Leg | Command | Backend | OpenBLAS needed |
|-----|---------|---------|-----------------|
| Offline/SKIP | `.\scripts\port.ps1 -Package xiom.openblas -TimeoutSec 300` | `bridge/openblas_bridge.c` stub (`xiom_openblas_backend() == 0`); BLAS comes from the pure-XIOM reference loops (Float64 + Float32), LAPACK returns the documented identity/zero placeholders | No |
| Real linked | `.\packages\xiom.openblas\tests\run_real_leg.ps1 -Require` | system OpenBLAS import library + `bridge/openblas_real_marker.c` (`xiom_openblas_backend() == 1`); real `cblas_*` (including `cblas_sdot`/`cblas_snrm2`/`cblas_saxpy`) and `dgesvd_`/`dsyev_`/`dgesv_` | Yes, else `[SKIP]` exit 0 |

The real leg discovers a build via `-OpenBlasRoot`, `XIOM_OPENBLAS_ROOT`,
`XIOM_OPENBLAS_LIB` (DLL path), or the pinned verification path
`E:\repos\openblas\v0.3.34-x64`; it sets PATH to the build's `bin` and links
`lib\libopenblas.lib`. An ILP64 build is refused (this package uses the
int32 `blasint` ABI).

The older runtime-detect probe (`tests/probe_real_openblas.xi` +
`tests/probe_openblas_shim.c`) is kept as a SKIP-safe smoke check for
`cblas_ddot`/`cblas_dgemm`; the linked suite is the authoritative real leg.

## Real-leg evidence

Verified on 2026-10-17 against the official OpenBLAS **v0.3.34** Windows x64
LP64 build (SHA256 `e9cb6134...`, BSD-3-Clause; see `PROVENANCE.md`), and
re-verified on 2026-10-21 with the additive Float32 surface:

- real leg `52/52` checks (includes `U*S*VT` reconstruction for 4x3 and
  2x3 inputs, `diag(3,2,1)` singular values, `A*v = lambda*v`, and
  `solve([[3,1],[1,2]], [9,8]) = [2,3]`);
- real Float32 calls: `cblas_sdot([1,2,3],[4,5,6]) = 32`,
  `cblas_snrm2([1,2,3]) = sqrt(14)` (tolerance `1e-6`),
  `cblas_saxpy(2, [1,2,3], [4,5,6]) = [6,9,12]`;
- offline/SKIP leg `52/52` checks x2 (same baseline + transposed BLAS paths,
  self-contained Float32 reference loops, LAPACK placeholder checks);
- `xiom --sandbox openblas.xi`: 0 HIGH / 0 MEDIUM findings (11 LOW:
  the audit does not recognize the `// SAFETY:` comments in this compiler
  version).

## Layout

| Path | Purpose |
|------|---------|
| `openblas.xi` | Module `xiom.openblas`: pool, public API (Float64 + Float32), leg marker, extern C surface (int32 blasint ABI + gfortran LAPACK hidden lengths) |
| `bridge/openblas_bridge.c` | Offline stub link-seam (wired via `port.args.json`); backend marker 0; computes nothing |
| `bridge/openblas_real_marker.c` | Real-leg marker only (backend 1); no cblas/LAPACK symbols |
| `port.args.json` | Wires the stub bridge into `scripts/port.ps1` |
| `tests/test_conformance.xi` | 52 conformance checks; leg-aware LAPACK accuracy and Float32 assertions |
| `tests/run_real_leg.ps1` | Real linked leg: discovery, PATH, link, 2x run + PASS/FAIL gate |
| `tests/probe_real_openblas.xi` + `tests/probe_openblas_shim.c` | Legacy SKIP-safe runtime probe |
| `PROVENANCE.md` | OpenBLAS pin, license, checksums, LP64/Int32 evidence |

## Integration notes

- Distinct from the `xiom-blas` seed package (`src/linalg.xi` + `blas.xiom-bind`),
  which is a reference/struct-based BLAS implementation; `xiom.openblas` is the
  system-OpenBLAS seam for the ML/AI stack.
- `xiom.numpy` Phase 2 consumes the matrix lifecycle, `dot`/`axpy`/`gemv`/`gemm`
  fast paths and the linalg surface from here (see SPEC.md).
- xvector P3 consumes `dot_f32`/`norm_f32`/`axpy_f32` directly: the Float32
  data is never widened to Float64, and empty/length-mismatched inputs return
  a typed `Err` before any C pointer is taken. On the real leg these call
  `cblas_sdot`/`cblas_snrm2`/`cblas_saxpy`; the offline artifact uses
  self-contained Float32 reference loops (documented f32 tolerance `1e-6`).
- Never link `bridge/openblas_bridge.c` together with a real OpenBLAS or with
  `bridge/openblas_real_marker.c` (duplicate stub/marker symbols). The two legs
  are separate artifacts; choose exactly one.

## Libs inventory

| Lib | Description |
|-----|-------------|
| `openblas` | OpenBLAS runtime bindings (extern "C" surface + leg marker). |
| `gemm` | Matrix-matrix multiply (`cblas_dgemm` on the real leg; pure-XIOM fallback offline). |
| `gemv` | Matrix-vector multiply (`cblas_dgemv`; transposed path included). |
| `dot` | Vector dot product (`cblas_ddot`). |
| `axpy` | Vector alpha-x-plus-y (`cblas_daxpy`). |
| `dot_f32` | Float32 vector dot product (`cblas_sdot` on the real leg; Float32 reference loop offline). |
| `norm_f32` | Float32 Euclidean norm (`cblas_snrm2` on the real leg; Float32 reference loop offline). |
| `axpy_f32` | Float32 alpha-x-plus-y (`cblas_saxpy` on the real leg; Float32 reference loop offline). |
| `svd` | Economy SVD (`dgesvd_`, workspace query). |
| `eigen_sym` | Symmetric eigen decomposition (`dsyev_`, workspace query). |
| `solve` | Linear solve (`dgesv_`, LU with partial pivoting). |
| `thread` | Threading control (Phase 4 -- `openblas_set_num_threads`). |
| `info` | Runtime/version info (Phase 4). |
