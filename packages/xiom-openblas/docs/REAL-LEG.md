# xiom.openblas -- Phase 1 real-leg verification record

Date: 2026-10-17
Compiler: XIOM v0.64.6 (`COMPILER_VERSION` pin; installed toolchain)
Stdlib: `E:\xiom-lang\stdlib`
OpenBLAS: official **v0.3.34** Windows x64 **LP64/Int32** build
(`OpenBLAS-0.3.34-x64.zip`, SHA256 `e9cb6134541f36c27346d5fc5995652f060fba227cebbbabcbda5a5a44d7c76b`;
BSD-3-Clause -- see `PROVENANCE.md`), extracted at
`E:\repos\openblas\v0.3.34-x64`.

## Commands and results

### Offline / SKIP leg (stub seam; no OpenBLAS required)

```
.\scripts\port.ps1 -Package xiom.openblas -TimeoutSec 300
```

- run 1: `42/42` checks, `program_exit=0`, `port: PASS`
- run 2: `42/42` checks, `program_exit=0`, `port: PASS`

This artifact links `bridge/openblas_bridge.c`; `backend_is_real()` is false.
BLAS checks run the pure-XIOM reference paths and the LAPACK checks assert the
documented identity/zero placeholders.

### Real linked leg (system OpenBLAS import library)

```
.\packages\xiom.openblas\tests\run_real_leg.ps1 -Require
```

- run 1: `42/42` checks, `program_exit=0`
- run 2: `42/42` checks, `program_exit=0`
- runner verdict: `real leg: PASS (2/2 runs green)`

Link line used by the runner (no stub seam):

```
xiom --run tests\test_conformance.xi ^
    --c-source bridge\openblas_real_marker.c ^
    --link-path E:\repos\openblas\v0.3.34-x64\lib ^
    --link libopenblas
```

`backend_is_real()` is true in this artifact; the suite calls real
`cblas_ddot`/`cblas_daxpy`/`cblas_dgemv`/`cblas_dgemm` and real
`dgesvd_`/`dsyev_`/`dgesv_`.

### Legacy runtime probe (kept SKIP-safe)

```
set XIOM_OPENBLAS_LIB=E:\repos\openblas\v0.3.34-x64\bin\libopenblas.dll
xiom --run tests\probe_real_openblas.xi --c-source tests\probe_openblas_shim.c
```

```
[INFO] loaded: E:\repos\openblas\v0.3.34-x64\bin\libopenblas.dll
[PASS] real cblas_ddot == 32
[PASS] real cblas_dgemm 2x2 product == [[19,22],[43,50]]
[PASS] real OpenBLAS exercised (ddot + dgemm)
```

## Numerical-accuracy assertions (real leg)

These are the new leg-aware checks in `tests/test_conformance.xi`; on the
offline leg each asserts the documented placeholder instead.

| Check | Input | Expected / tolerance | Result |
|-------|-------|----------------------|--------|
| `dot` | `[1,2,3] . [4,5,6]` | `32` (exact) | PASS |
| `axpy` | `2*[1,2,3] + [4,5,6]` | `[6,9,12]` (exact) | PASS |
| `gemv` no-trans | `[[1,2,3],[4,5,6]] * [1,1,1]` | `[6,15]` (exact) | PASS |
| `gemv` trans | `[[1,2],[3,4],[5,6]]^T * [1,1,1]` | `[9,12]` (exact) | PASS |
| `gemm` transA | `[[1,2],[3,4],[5,6]]^T * [[1,0],[0,1],[1,1]]` | `[[6,8],[8,10]]` (exact) | PASS |
| `gemm` transB | `[[1,2,3],[4,5,6]] * [[1,0,1],[0,1,1]]^T` | `[[4,5],[10,11]]` (exact) | PASS |
| `svd` singular values | `diag(3,2,1)` | `[3,2,1]`, tol `1e-9` | PASS |
| `svd` reconstruction | 4x3 `A=[[1,2,3],[4,5,6],[7,8,9],[10,11,13]]` | `max abs(U*S*VT - A) <= 1e-9` | PASS |
| `svd` reconstruction | 2x3 `A=[[1,2,3],[4,5,6]]` | `max abs(U*S*VT - A) <= 1e-9` | PASS |
| `eigen_sym` values | `[[2,1],[1,2]]` | ascending `[1,3]`, tol `1e-9` | PASS |
| `eigen_sym` vectors | `[[2,1],[1,2]]` | `A*v_j = w_j*v_j`, tol `1e-9` | PASS |
| `solve` values | `A=[[3,1],[1,2]]`, `b=[9,8]` | `x=[2,3]`, tol `1e-9` | PASS |
| `solve` singular | `A=[[1,2],[2,4]]`, `b=[1,2]` | `Err` (`dgesv_ info > 0`) | PASS |

## ABI evidence used by the real leg

- `blasint` is 32-bit: `include/openblas_config.h` line 89
  `typedef int blasint;`; `OPENBLAS_USE64BITINT` is not defined.
- `lib/pkgconfig/openblas.pc`: `USE_64BITINT=` (empty), version `0.3.34`.
- LAPACK Fortran symbols on this build take hidden `size_t` character lengths;
  `dgesvd_`/`dsyev_` declarations pass them. `dgesv_` has no character args.
- `tests/run_real_leg.ps1` refuses an `OPENBLAS_USE64BITINT` build and never
  compiles `bridge/openblas_bridge.c` together with OpenBLAS.
