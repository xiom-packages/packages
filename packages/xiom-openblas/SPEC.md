# xiom.openblas -- SPEC

**Phase**: 1 (Core Foundation) | **Priority**: CRITICAL
**Status**: Phase 1 implemented and conformance-green (32/32 x2 on compiler v0.64.5).
Two-leg split: an offline leg (stub link-seam bridge, no system OpenBLAS required)
and a real-library leg (runtime-detected OpenBLAS probe, SKIP-safe when absent).
**Depends on**: xiom.ffi (stdlib), xiom.alloc (stdlib)

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

// BLAS Level 1 (vector-vector)
pub fn dot(x: &Vec[Float64], y: &Vec[Float64], n: Int) -> Float64
pub fn axpy(alpha: Float64, x: &Vec[Float64], y: &mut Vec[Float64], n: Int)

// BLAS Level 2 (matrix-vector)
pub fn gemv(trans: Bool, m: Int, n: Int, alpha: Float64, A: &Matrix, x: &Vec[Float64], beta: Float64, y: &mut Vec[Float64])

// BLAS Level 3 (matrix-matrix)
pub fn gemm(transA: Bool, transB: Bool, m: Int, n: Int, k: Int, alpha: Float64, A: &Matrix, B: &Matrix, beta: Float64, C: &mut Matrix)

// LAPACK
pub fn svd(A: &Matrix) -> Result[(Matrix, Matrix, Matrix), Str]
pub fn eigen_sym(A: &Matrix) -> Result[(Matrix, Matrix), Str]
pub fn solve(A: &Matrix, b: &Vec[Float64]) -> Result[Matrix, Str]
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
| Offline conformance | `tests/test_conformance.xi` linked with `bridge/openblas_bridge.c` (stub link-seam; wired via `port.args.json`). All numbers come from the pure-XIOM reference paths in `openblas.xi`; the stub symbols are declared but never called. | `.\scripts\port.ps1 -Package xiom-openblas -TimeoutSec 180` | No |
| Real library | `tests/probe_real_openblas.xi` + `tests/probe_openblas_shim.c`: detects a system OpenBLAS at runtime (XIOM_OPENBLAS_LIB override, standard locations, then OS loader search = PATH), exercises real `cblas_ddot` and `cblas_dgemm`; prints `[SKIP]` and exits 0 when absent. | see tests/probe_real_openblas.xi header (direct `xiom --run` invocation) | Yes (else SKIP) |

The offline leg is stub-safe *by design* and documented as such; it is not a
claim that BLAS is computed by OpenBLAS. The real leg is the OpenBLAS truth:
last verified on this machine against a real LP64 OpenBLAS DLL (scipy wheel
copy) -- `cblas_ddot == 32` and 2x2 `cblas_dgemm == [[19,22],[43,50]]` both
passed; on the same box, without the override, the probe SKIPs cleanly
(nothing standard-named on PATH/standard locations).

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | BLAS Level 1-3 + matrix create/free | Weekend (remaining: wire real cblas_*/LAPACK calls) |
| 2 | LAPACK: SVD, Eigendecomp, Solve, LU, QR | Weekend |
| 3 | Sparse matrix support | Week |
| 4 | Multi-threaded BLAS configuration | Day |

## Implementation (Phase 1)

### Files
| File | Lines | Purpose |
|------|-------|---------|
| `openblas.xi` | 368 | Module `xiom.openblas` -- extern C surface (int32 blasint ABI), pool, safe wrappers (pure-XIOM paths), LAPACK stubs |
| `bridge/openblas_bridge.c` | 129 | Stub link-seam resolving the extern C surface for the offline leg (validates pointers; computes nothing; LAPACK writes info=-999) |
| `port.args.json` | 4 | Wires `--c-source ${PACKAGE_DIR}/bridge/openblas_bridge.c` into the port.ps1 suite invocation |
| `tests/test_conformance.xi` | 536 | 32 conformance tests (same checks/names/order as the original suite), rewritten to the current xiom.test API |
| `tests/probe_real_openblas.xi` | 147 | SKIP-safe real-library probe (real leg); exercises real cblas_ddot/cblas_dgemm |
| `tests/probe_openblas_shim.c` | 175 | Probe-local C shim: runtime OpenBLAS detection/loading + real cblas calls (int32 ABI) |
| `ROADMAP.md` | -- | Phased plan: Core -> LAPACK full -> Sparse -> MT -> Integration |
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

pub fn gemv(trans: Bool, m: Int, n: Int, alpha: Float64, A: &Matrix, x: &Vec[Float64], beta: Float64, y: &mut Vec[Float64])
pub fn gemm(transA: Bool, transB: Bool, m: Int, n: Int, k: Int, alpha: Float64, A: &Matrix, B: &Matrix, beta: Float64, C: &mut Matrix)

pub fn svd(A: &Matrix) -> Result[(Matrix, Matrix, Matrix), Str]
pub fn eigen_sym(A: &Matrix) -> Result[(Matrix, Matrix), Str]
pub fn solve(A: &Matrix, b: &Vec[Float64]) -> Result[Matrix, Str]
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

### Internal architecture
- **Pool**: 5 parallel `Vec` arrays (`__pool_data`, `__pool_rows`, `__pool_cols`, `__pool_start`, `__pool_used`)
- **Handle**: 1-based index into pool; 0 = invalid
- **BLAS 1-3**: pure XIOM loop implementations (reference path; linked OpenBLAS wiring pending)
- **LAPACK**: stub implementations returning identity/zero placeholders
- **Offline link seam**: `bridge/openblas_bridge.c` resolves the extern C surface; never called by the module

## What xiom.numpy Phase 2 must call from this package
- `matrix_create` / `matrix_set` / `matrix_get` / `matrix_rows` / `matrix_cols`
  as the host-side dense buffer for ndarray storage and einsum-style loops;
- `dot`, `axpy`, `gemv`, `gemm` as the BLAS fast paths behind numpy `dot` /
  `matmul` semantics (pool layout is row-major, index = row * cols + col --
  the same layout the numpy bridge marshals into CBLAS RowMajor);
- `svd` / `eigen_sym` / `solve` for the linalg surface; Phase 2 should treat
  them as placeholders until the real LAPACK wiring lands (both packages'
  Phase 2);
- the extern seam convention: keep `bridge/openblas_bridge.c` out of any build
  that links a real OpenBLAS (duplicate symbols); the real leg is the shim
  pattern in `tests/probe_openblas_shim.c`.

## XIOM design notes
- `pub type Matrix = Int` (newtype, opaque handle)
- Public error paths use `Result`/neutral values (see delta table)
- Return `Result[T, Str]` for allocation/calculation failures
