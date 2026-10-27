# xiom.openblas -- SPEC

**Phase**: 1 (Core Foundation) + Phase 2 LU/QR/Cholesky subset | **Priority**: CRITICAL
**Status**: Phase 1 COMPLETE and the Phase 2 LU/QR/Cholesky subset landed;
conformance-green (71/71 x2 on compiler v0.64.9) on both legs: an offline
stub/SKIP artifact (no OpenBLAS required) and a real linked OpenBLAS artifact
(BLAS 1-3 + LAPACK SVD/eigen/solve + dgetrf/dgetrs, dgeqrf/dorgqr,
dpotrf/dpotrs). The 71 checks are the original 42 Float64 checks, 10 additive
Float32 checks (`dot_f32`, `norm_f32`, `axpy_f32`) for the xvector P3 hot
path, and 19 Phase 2 LU/QR/Cholesky checks.
**Depends on**: xiom.convert (stdlib), xiom.ffi (stdlib), xiom.alloc (stdlib)

## What it wraps
OpenBLAS -- optimized Basic Linear Algebra Subprograms (BLAS) and LAPACK.
Foundation for ALL scientific computing and ML packages.

## Dependencies

| What | How | Size |
|------|-----|------|
| OpenBLAS | System-installed (optional at Phase 1; required for the real leg/production speedup). `winget install OpenBLAS`, `apt install libopenblas-dev` | ~30MB |
| C compiler | For building the bridge .obj | -- |

## Bundling strategy
**System-installed only.** OpenBLAS is available on every platform via package
managers. Never bundle -- link against system library. Phase 1 additionally
ships a *stub* C bridge so the package compiles and tests offline with no
OpenBLAS installed (see Two-leg split below).

## API surface

```xiom
module xiom.openblas

// Matrix creation
pub fn matrix_create(rows: Int, cols: Int) -> Result[Matrix, Str]
pub fn matrix_free(m: Matrix)
pub fn matrix_get(m: &Matrix, row: Int, col: Int) -> Float64
pub fn matrix_set(m: &mut Matrix, row: Int, col: Int, val: Float64)

// BLAS Level 1 (vector-vector, Float64)
pub fn dot(x: &Vec[Float64], y: &Vec[Float64], n: Int) -> Float64
pub fn axpy(alpha: Float64, x: &Vec[Float64], y: &mut Vec[Float64], n: Int)

// BLAS Level 1 (vector-vector, Float32 -- additive hot-path surface)
pub fn dot_f32(a: &Vec[Float32], b: &Vec[Float32]) -> Result[Float32, Str]
pub fn norm_f32(a: &Vec[Float32]) -> Result[Float32, Str]
pub fn axpy_f32(alpha: Float32, x: &Vec[Float32], y: &mut Vec[Float32]) -> Result[Unit, Str]

// BLAS Level 2 (matrix-vector)
pub fn gemv(trans: Bool, m: Int, n: Int, alpha: Float64, A: &Matrix, x: &Vec[Float64], beta: Float64, y: &mut Vec[Float64])

// BLAS Level 3 (matrix-matrix)
pub fn gemm(transA: Bool, transB: Bool, m: Int, n: Int, k: Int, alpha: Float64, A: &Matrix, B: &Matrix, beta: Float64, C: &mut Matrix)

// LAPACK
pub fn svd(A: &Matrix) -> Result[(Matrix, Matrix, Matrix), Str]
pub fn eigen_sym(A: &Matrix) -> Result[(Matrix, Matrix), Str]
pub fn solve(A: &Matrix, b: &Vec[Float64]) -> Result[Matrix, Str]
pub fn lu_factor(A: &Matrix) -> Result[(Matrix, Matrix), Str]
pub fn lu_solve(LU: &Matrix, piv: &Matrix, b: &Vec[Float64]) -> Result[Matrix, Str]
pub fn qr(A: &Matrix) -> Result[(Matrix, Matrix), Str]
pub fn cholesky(A: &Matrix) -> Result[Matrix, Str]
pub fn cholesky_solve(L: &Matrix, b: &Vec[Float64]) -> Result[Matrix, Str]
```

## Contract coverage target
- Matrix operations validate dimensions and return `Err`/neutral values on
  invalid input (see the v0.64.5 delta table: contracts that the conformance
  suite intentionally violates were moved into the `Result`/guard paths,
  because v0.64.5 enforces `requires` at runtime with a process panic).
- Memory allocation: `Result` with error message.

## Two-leg split (Phase 1 verification architecture)

| Leg | What it is | How to run | Needs OpenBLAS? |
|-----|-----------|------------|-----------------|
| Offline/SKIP | `tests/test_conformance.xi` linked with `bridge/openblas_bridge.c` (stub link-seam; wired via `port.args.json`). `xiom_openblas_backend()` returns 0, so BLAS numbers come from the pure-XIOM reference paths and LAPACK returns the documented identity/zero placeholders; the stub C symbols are never called. | `.\scripts\port.ps1 -Package xiom.openblas -TimeoutSec 300` | No |
| Real linked | the same suite linked against the system OpenBLAS import library plus `bridge/openblas_real_marker.c` (marker only -- no stub symbols). `xiom_openblas_backend()` returns 1, so `cblas_*` and `dgesvd_`/`dsyev_`/`dgesv_`, `dgetrf_`/`dgetrs_`, `dgeqrf_`/`dorgqr_`,
and `dpotrf_`/`dpotrs_` are called over raw Vec/pool pointers. SKIPs cleanly
when no build is found. | `.\packages\xiom.openblas\tests\run_real_leg.ps1 -Require` | Yes (else SKIP) |
| Runtime probe (legacy) | `tests/probe_real_openblas.xi` + `tests/probe_openblas_shim.c`: runtime-detected `cblas_ddot`/`cblas_dgemm` smoke check; kept SKIP-safe. | see tests/probe_real_openblas.xi header | Yes (else SKIP) |

The offline leg is stub-safe *by design*; it is not a claim that BLAS is
computed by OpenBLAS. The linked real leg is the OpenBLAS truth. Verified on
2026-10-17 against the official OpenBLAS **v0.3.34** Windows x64 **LP64/Int32**
build (`typedef int blasint`, `USE_64BITINT=` empty; SHA256 `e9cb6134...`,
BSD-3-Clause -- `PROVENANCE.md`): `42/42` checks x2, including `U*S*VT`
reconstruction for 4x3 and 2x3 inputs, `diag(3,2,1)` singular values,
`A*v = lambda*v` eigenpair residuals, `solve([[3,1],[1,2]],[9,8]) = [2,3]`,
and singular-matrix `dgesv_` returning `Err` (`info > 0`).

Re-verified on 2026-10-21 with the additive Float32 surface: `52/52` checks
x2 on the offline leg (compiler v0.64.8) and `52/52` on the linked real leg
against the same v0.3.34 build, exercising `cblas_sdot`, `cblas_snrm2`, and
`cblas_saxpy` with `[1,2,3] . [4,5,6] = 32`, `norm([1,2,3]) = sqrt(14)`
(tolerance `1e-6`), and fail-closed length/empty `Err` paths.

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | BLAS Level 1-3 + matrix create/free | Weekend (remaining: wire real cblas_*/LAPACK calls) |
| 2 | LAPACK: SVD, Eigendecomp, Solve, LU, QR, Cholesky (LU/QR/Cholesky landed 2026-10-22; `dgeev` deferred) | Weekend |
| 3 | Sparse matrix support | Week |
| 4 | Multi-threaded BLAS configuration | Day |

## Implementation (Phase 1)

### Files
| File | Lines | Purpose |
|------|-------|---------|
| `openblas.xi` | 1418 | Module `xiom.openblas` -- extern C surface (int32 blasint ABI + gfortran hidden lengths), pool, leg marker, real cblas/LAPACK marshalling (Float64 + Float32), pure-XIOM fallback (LU/QR/Cholesky included) |
| `bridge/openblas_bridge.c` | 270 | Offline stub link-seam (backend marker 0; validates pointers; computes nothing; LAPACK writes info=-999; includes dgetrf/dgetrs, dgeqrf/dorgqr, dpotrf/dpotrs) |
| `bridge/openblas_real_marker.c` | 18 | Real-leg marker only (backend 1); deliberately defines no cblas/LAPACK symbol |
| `port.args.json` | 4 | Wires `--c-source ${PACKAGE_DIR}/bridge/openblas_bridge.c` into the port.ps1 suite invocation |
| `tests/test_conformance.xi` | 1754 | 71 conformance checks on the current xiom.test API; leg-aware LAPACK accuracy (SVD/eigen/solve + LU/QR/Cholesky) and Float32 checks |
| `tests/run_real_leg.ps1` | 171 | Real linked leg: OpenBLAS discovery, ILP64 refusal, PATH, link args, 2x PASS/FAIL gate |
| `tests/probe_real_openblas.xi` | 159 | Legacy SKIP-safe runtime probe; exercises real cblas_ddot/cblas_dgemm |
| `tests/probe_openblas_shim.c` | 191 | Probe-local C shim: runtime OpenBLAS detection/loading + real cblas calls (int32 ABI) |
| `PROVENANCE.md` | -- | OpenBLAS v0.3.34 pin, BSD-3-Clause, SHA256/MD5, LP64/Int32 evidence |
| `ROADMAP.md` | -- | Phased plan: Core (complete) -> LAPACK full -> Sparse -> MT -> Integration |
| `SPEC.md` | -- | This file |

### API surface (implemented)
```xiom
module xiom.openblas

pub type Matrix = Int;

pub fn matrix_create(rows: Int, cols: Int) -> Result[Matrix, Str]
pub fn matrix_free(m: Matrix)
pub fn matrix_get(m: &Matrix, row: Int, col: Int) -> Float64
pub fn matrix_set(m: &mut Matrix, row: Int, col: Int, val: Float64)
pub fn matrix_rows(m: &Matrix) -> Int
pub fn matrix_cols(m: &Matrix) -> Int

pub fn dot(x: &Vec[Float64], y: &Vec[Float64], n: Int) -> Float64
pub fn axpy(alpha: Float64, x: &Vec[Float64], y: &mut Vec[Float64], n: Int)

pub fn dot_f32(a: &Vec[Float32], b: &Vec[Float32]) -> Result[Float32, Str]
pub fn norm_f32(a: &Vec[Float32]) -> Result[Float32, Str]
pub fn axpy_f32(alpha: Float32, x: &Vec[Float32], y: &mut Vec[Float32]) -> Result[Unit, Str]

pub fn gemv(trans: Bool, m: Int, n: Int, alpha: Float64, A: &Matrix, x: &Vec[Float64], beta: Float64, y: &mut Vec[Float64])
pub fn gemm(transA: Bool, transB: Bool, m: Int, n: Int, k: Int, alpha: Float64, A: &Matrix, B: &Matrix, beta: Float64, C: &mut Matrix)

pub fn svd(A: &Matrix) -> Result[(Matrix, Matrix, Matrix), Str]
pub fn eigen_sym(A: &Matrix) -> Result[(Matrix, Matrix), Str]
pub fn solve(A: &Matrix, b: &Vec[Float64]) -> Result[Matrix, Str]
pub fn lu_factor(A: &Matrix) -> Result[(Matrix, Matrix), Str]
pub fn lu_solve(LU: &Matrix, piv: &Matrix, b: &Vec[Float64]) -> Result[Matrix, Str]
pub fn qr(A: &Matrix) -> Result[(Matrix, Matrix), Str]
pub fn cholesky(A: &Matrix) -> Result[Matrix, Str]
pub fn cholesky_solve(L: &Matrix, b: &Vec[Float64]) -> Result[Matrix, Str]
```

### Delta from original SPEC
| Item | SPEC (original) | Implemented | Reason |
|------|-----------------|-------------|--------|
| `matrix_new` | `matrix_new` | `matrix_create` | More descriptive; matches ecosystem convention |
| `dot` params | `dot(n, x, y)` | `dot(x, y, n)` | Vectors first, count last (ergonomic) |
| `axpy` params | `axpy(n, a, x, y)` | `axpy(alpha, x, y, n)` | Alpha first (BLAS convention), count last |
| `svd` return | `(Matrix, Vec, Matrix)` | `(Matrix, Matrix, Matrix)` | S_diag as diagonal matrix (uniform return) |
| `eigen_sym` return | `(Vec, Matrix)` | `(Matrix, Matrix)` | Eigenvalues as diagonal matrix (uniform return) |
| `solve` return | `Vec[Float64]` | `Matrix` (nx1) | Column vector as Matrix (uniform handle) |

### v0.64.5 drift fixes (this pass)
| Item | Change | Reason |
|------|--------|--------|
| Module-level pool | `var __pool_x: Vec[T] = Vec[T].new();` explicit annotations | v0.64.5 does not infer module-level `Vec[T].new()` types ("catalog body" errors) |
| `Matrix` numeric ops | internals use `Int` handles; each public fn converts once (`var h: Int = m;`) | v0.64.5 treats `pub type Matrix = Int` as nominal; `>`/`-` on it do not type-check |
| `matrix_create` contracts | `requires: rows > 0`/`cols > 0` moved into the `Err` path | v0.64.5 enforces `requires` at runtime (panic); the mandated suite checks that invalid dims return `Err` |
| `matrix_get`/`matrix_set` contracts | `requires: row >= 0`/`col >= 0` moved into in-body bounds guards | same reason; out-of-bounds reads must return 0.0 / skip write (suite checks) |
| `matrix_free` contract | `requires: m != 0` (was `m > 0`) | ordering comparison on the `Matrix` newtype does not type-check |
| extern C ABI | `blasint` params `Int` -> `Int32` | honesty: real OpenBLAS LP64 uses int32; the declarations are the Phase-2 wiring target |
| Suite API | rewritten to `xiom.test` TestResult API | old suite used an exit-code style API removed from the current stdlib |

### Phase 1 real-leg delta (2026-10-17)
| Item | Change | Reason |
|------|--------|--------|
| Leg selection | `xiom_openblas_backend()` marker + `bridge/openblas_real_marker.c` | One suite, two artifacts; stub and real symbols never coexist |
| BLAS wiring | `dot`/`axpy`/`gemv`/`gemm` call `cblas_*` on the real leg | Real acceleration via raw pool/Vec pointers |
| LAPACK wiring | `svd`/`eigen_sym`/`solve` call `dgesvd_`/`dsyev_`/`dgesv_` | Real SVD/eigen/solve (replaces placeholders on the real leg) |
| LAPACK ABI | Hidden `size_t` character lengths appended to `dgesvd_`/`dsyev_` | gfortran convention (`LAPACK_FORTRAN_STRLEN_END`) |
| Workspace | `lwork = -1` query, then allocate an XIOM `Vec[Float64]` of `lwork` | No guessed workspace sizes |
| Pivots | `ipiv` viewed as `*Int32` over a `Float64` Vec (n*4 bytes) | `Vec[T]` slots are 8 bytes, so `Vec[Int32]` would not be contiguous |
| Accuracy | New leg-aware suite checks (reconstruction, singular values, eigenpair residual, solve, singular Err) | Numerical evidence, not just shape checks |
| Platform | Real leg verified against OpenBLAS v0.3.34 x64 LP64/Int32; ILP64 refused | Matches the int32 `blasint` declarations |

### Float32 delta (2026-10-21, REL-20261021-1121-xvector)
| Item | Change | Reason |
|------|--------|--------|
| `dot_f32` | `cblas_sdot` on the real leg; self-contained Float32 loop offline | xvector P3 kernel seam must not widen f32 data to f64 |
| `norm_f32` | `cblas_snrm2` on the real leg; Float32 sum-of-squares offline (only the scalar sqrt is evaluated in Float64) | f32 norm without converting the vector |
| `axpy_f32` | `cblas_saxpy` on the real leg; Float32 loop offline | Optional trivial Level-1 companion for the same seam |
| Validation | `Result[_, Str]`: empty input and length mismatch return `Err` before any pointer is taken | Fail-closed edge handling; no silent stub result |
| Stub seam | `bridge/openblas_bridge.c` also defines `cblas_sdot`/`cblas_snrm2`/`cblas_saxpy` (never called: marker 0 selects the reference loops) | Offline artifact links without real OpenBLAS |
| Tolerance | Documented f32 tolerance `1e-6` (~8x `FLOAT32_EPSILON`), used by the norm test | Explicit f32 accuracy contract |
| API stability | Float64 surface unchanged | Additive release |

### Phase 2 LAPACK delta (2026-10-22)
| Item | Change | Reason |
|------|--------|--------|
| LU | `lu_factor(A) -> (LU, piv)` calls `dgetrf_` on the real leg; partial-pivoting reference loops offline | Packed L/U layout and 1-based pivot indices; `P*A = L*U` |
| LU solve | `lu_solve(LU, piv, b)` calls `dgetrs_` (`trans='N'`) on the real leg; forward/back substitution offline | Reuses the factor, no refactorization |
| Pivot return | `piv` is an n x 1 `Matrix` of exact 1-based Float64 integers, not `Vec[Int]` | Compiler defect (FIXED in v0.65.2): a `Vec` inside a cross-module `Result[(nominal, Vec[Int]), Str]` lost its contents (see `docs/COMPILER-DEFECT-vec-tuple.md`). The `Matrix` return is retained for API compatibility; a `Vec[Int]` variant is a future-major option |
| QR | `qr(A) -> (Q, R)` calls `dgeqrf_` then `dorgqr_` (both workspace-queried) on the real leg; modified Gram-Schmidt offline | Reduced/economy shapes Q (m x k), R (k x n), `A = Q*R` |
| Cholesky | `cholesky(A) -> L` calls `dpotrf_` (`uplo='L'`) on the real leg; Cholesky-Crout offline | Returns the lower factor, `A = L*L^T`; `info > 0` -> non-SPD `Err` |
| Cholesky solve | `cholesky_solve(L, b)` calls `dpotrs_` (`uplo='L'`) on the real leg; forward/back substitution offline | Reuses the factor |
| Errors | `Result[_, Str]`: singular (`dgetrf` zero pivot / zero U diagonal), non-positive Cholesky pivot, non-square, invalid handle, pivot shape/range, and b-length mismatch | Fail-closed, no pointer taken on invalid input |
| Tolerance | Suite tolerance `1e-9` for the LU/Cholesky goldens and QR reconstruction/orthogonality; QR sign convention is not asserted | Matches the existing Float64 policy (`solve`/`svd` use `1e-9`) |
| `dgeev` | NOT implemented | Non-symmetric eigenpairs have complex-output shape; the return contract is unpinned (reported as skipped in ROADMAP) |
### Internal architecture
- **Pool**: 5 parallel `Vec` arrays (`__pool_data`, `__pool_rows`, `__pool_cols`, `__pool_start`, `__pool_used`)
- **Handle**: 1-based index into pool; 0 = invalid
- **Leg marker**: `xiom_openblas_backend()` (0 = stub bridge, 1 = real marker)
- **BLAS 1-3 (real leg)**: `cblas_ddot`/`daxpy`/`dgemv`/`dgemm` over raw pointers to the pool span / Vec data; `CblasRowMajor` (101), NoTrans/Trans (111/112), `lda` = the pool matrix column count
- **BLAS 1-3 (offline leg)**: the pure-XIOM reference loops (same public semantics, including the transposed paths)
- **BLAS Level 1 Float32 (real leg)**: `cblas_sdot`/`cblas_snrm2`/`cblas_saxpy` over raw `Vec[Float32]` pointers, inc = 1; gated on `backend_is_real()`
- **BLAS Level 1 Float32 (offline leg)**: Float32 accumulation loops; `norm_f32` takes the scalar square root through `xiom.math.sqrt` (Float64) and narrows the result back to Float32
- **LAPACK (real leg)**: row-major pool -> column-major scratch, `lwork = -1` workspace query, then an XIOM `Vec[Float64]` of exactly `lwork` slots; `dgesvd_` economy U/VT, `dsyev_` (`jobz='V'`, `uplo='U'`), `dgesv_` with an int32 `ipiv` view over Vec storage; `dgetrf_`/`dgetrs_` (LU + pivots), `dgeqrf_`/`dorgqr_` (QR), `dpotrf_`/`dpotrs_` (`uplo='L'`); results converted back to row-major
- **LAPACK SVD/eigen/solve (offline leg)**: documented identity/zero placeholders with correct shapes. **LU/QR/Cholesky (offline leg)**: self-contained LU with partial pivoting, modified Gram-Schmidt QR, and Cholesky-Crout, so those operations are deterministic and numerically tested on both legs
- **Link seams**: exactly one of `bridge/openblas_bridge.c` (offline) or `bridge/openblas_real_marker.c` + OpenBLAS import library (real); never both

## What xiom.numpy Phase 2 must call from this package
- `matrix_create` / `matrix_set` / `matrix_get` / `matrix_rows` / `matrix_cols`
  as the host-side dense buffer for ndarray storage and einsum-style loops;
- `dot`, `axpy`, `gemv`, `gemm` as the BLAS fast paths behind numpy `dot` /
  `matmul` semantics (pool layout is row-major, index = row * cols + col --
  the same layout the numpy bridge marshals into CBLAS RowMajor);
- `svd` / `eigen_sym` / `solve` for the linalg surface; they are real LAPACK
  operations on the linked real leg and the documented placeholders on the
  offline/SKIP leg (`backend_is_real()` tells the two apart);
- the extern seam convention: keep `bridge/openblas_bridge.c` out of any build
  that links a real OpenBLAS (duplicate symbols); the real leg is the shim
  pattern in `tests/probe_openblas_shim.c`.

## XIOM design notes
- `pub type Matrix = Int` (newtype, opaque handle)
- Public error paths use `Result`/neutral values (see delta table)
- Return `Result[T, Str]` for allocation/calculation failures
