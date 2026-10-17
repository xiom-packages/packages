# xiom.blas

> **Status:** `incubating` -- conformance-green (50/50, two consecutive runs
> on v0.64.6; typed-absent runtime SKIP recorded). Fold completed
> 2026-10-17: the parked safe-linalg package is now layered over the live
> `xiom.openblas` seam. Published in `eco-v0.1.194` (sha256 `bee07a38...`,
> 2026-10-17).
> **Scope:** safe BLAS-style linear algebra -- a row-major dense `Float64`
> matrix value type with shape-checked, typed errors and no `unsafe` at the
> API boundary.
> **Deps:** stdlib + `xiom.openblas` 0.1.0 (the system-OpenBLAS seam; the
> BLAS runtime itself is never vendored, linked, or redistributed here).

## What this is

`xiom.blas` is the **safe XIOM-level linalg surface**: construction, element
access, element-wise operations, the BLAS 1-3 primitives, and self-contained
LU/Gauss-Jordan decompositions -- all over a value-semantics `DenseMatrix`
(flat row-major `Vec[Float64]` + `rows`/`cols`).

The FFI-backed primitives (`matmul`, `matvec`, `ddot`, `daxpy` and their
SPEC-level names `matrix_multiply`, `matrix_vector_multiply`, `vector_dot`)
delegate into the **`xiom.openblas` declared surface** (matrix pool +
`gemm`/`gemv`/`dot`/`axpy`). Offline, that seam computes the same numbers
through its pure-XIOM reference paths; when its real `cblas_*` wire-in lands
(`xiom.openblas` ROADMAP Phase 1 remainder) the traffic becomes real
OpenBLAS calls with **no API change here**. Nothing in this package is
vendored and no `unsafe`/`extern` appears in its modules; the runtime ships
(and is loaded/SKIP-classified) entirely by `xiom.openblas`.

## Two-leg verification (same shape as xiom.openblas)

| Leg | Command | OpenBLAS needed |
|-----|---------|-----------------|
| Offline conformance (link seam: `xiom.openblas`' stub bridge via `port.args.json`; typed-absent runtime SKIP recorded in-suite) | `.\scripts\port.ps1 -Package xiom.blas -TimeoutSec 300` | No |
| Real-library probe (reuses `xiom.openblas`' canonical probe shim; SKIP-safe) | see below | Yes, else `[SKIP]` exit 0 |

Real-library leg (from the package directory; absolute `--c-source` paths):

```
xiom --run tests\probe_real_blas.xi ^
    --c-source <repo>\packages\xiom-openblas\tests\probe_openblas_shim.c ^
    --c-source <repo>\packages\xiom-openblas\bridge\openblas_bridge.c
```

The probe uses the **canonical availability rules** (`XIOM_OPENBLAS_LIB`
override -> standard install locations -> bare sonames via the OS loader
search order; loaded-but-missing-exports is a loud FAIL) and, on the present
path, pins real `cblas_ddot == 32` + `cblas_dgemm == [[19,22],[43,50]]` and
checks the safe layer computes the **same goldens** on the same inputs.
Optional override: `set XIOM_OPENBLAS_LIB=C:\somewhere\libopenblas.dll`.

## Layout

| Path | Purpose |
|------|---------|
| `src/blas.xi` | Module `xiom.blas`: `DenseMatrix`, construction/access, element-wise ops, FFI seam (`matmul`/`matvec`/`ddot`/`daxpy`/`scal`; delegates to `xiom.openblas`) |
| `src/linalg.xi` | Module `xiom.blas.linalg`: SPEC-declared surface (`matrix_multiply`, `solve_linear_system`, ...), pure decompositions with partial pivoting |
| `src/runtime.xi` | Module `xiom.blas.runtime`: typed runtime-availability classifier (`BLAS_RT_ABSENT`/`PRESENT`/`ABI`) mirroring the canonical rules |
| `blas.xiom-bind` | Declarative C ABI mapping (the seam symbols; link resolution is owned by `xiom.openblas`) |
| `tests/test_conformance.xi` | 50-check conformance suite (offline leg) |
| `tests/probe_real_blas.xi` | Real-library probe (real leg; reuses the openblas shim) |
| `xiom.toml` / `port.args.json` | Path dependency on `../xiom-openblas` / stub link seam |

## Quickstart

```xiom
use xiom.blas;
use xiom.blas.linalg;

// construction -- row-major, zero-filled
var a = matrix_new(2, 2);
a.data[0] = 1.0; a.data[1] = 2.0; a.data[2] = 3.0; a.data[3] = 4.0;
let i = matrix_identity(2);

// FFI-backed multiply (delegates to the xiom.openblas seam)
match matrix_multiply(&a, &i) {
  Ok(c) => { /* c == a */ }
  Err(e) => { /* typed shape error */ }
}

// pure decompositions (self-contained; no runtime needed)
let det = matrix_determinant(&a);              // -2
match matrix_inverse(&a) { Ok(inv) => { /* ... */ } Err(e) => { /* singular */ } }
let rhs = vector_zeros(2);
match solve_linear_system(&a, &rhs) { Ok(x) => { /* ... */ } Err(e) => { /* ... */ } }

// runtime availability (canonical xiom.openblas rules)
let rt = runtime_probe();
if rt.kind == BLAS_RT_ABSENT { /* SKIP: no system OpenBLAS */ }
```

## SPEC deltas (v0.64.5 resolver-driven renames; see AUDIT.md)

| Seed name | Delivered | Why |
|-----------|-----------|-----|
| `Matrix` (type) | `DenseMatrix` | `xiom.openblas` also declares `pub type Matrix` (Int handle); a unit carrying both packages mis-bound the handle as this struct and faulted on `matrix_free` (access violation). Rename removes the collision. |
| `identity(n)` | `matrix_identity(n)` | `identity` collides with the generic `xiom.convert.identity[T]` in any unit importing both. |
| seam `dot` / `axpy` | `ddot` / `daxpy` | Same-name declarations in `xiom.openblas` with identical leading parameter types: no type-based disambiguation, and an unqualified call could silently bind to the 4-arg `openblas.axpy`/3-arg `openblas.dot` and drop an argument (observed; see AUDIT.md C2). The `d`-prefixed names mirror the CBLAS double-precision surface and collide with nothing. |
| `vector_scale` = `cblas_dscal` | pure-XIOM loop | The live `xiom.openblas` seam declares no `dscal` wrapper; the loop is numerically identical and the seam remains the single home for a future real `cblas_dscal` wire-in. |

## Coverage

All 23 delivered public members across `xiom.blas` + `xiom.blas.linalg` are
exercised by the conformance suite (exact dyadic goldens; shape-error paths
asserted as typed `Err`), and the full declared surface is additionally
**compile-evidenced** by a never-run walk (`blas_surface_coverage`). See the
coverage table in SPEC.md for the member -> test mapping.
