# xiom.blas Specification

**Version:** 0.1.0 (folded 2026-10-17; parked seed completed over the live
`xiom.openblas` seam, eco-v0.1.193)
**Status:** conformance-green on compiler v0.64.5 (50/50 x2; typed-absent
runtime SKIP recorded; real-library probe SKIP x2 + present x2)
**Depends on:** `xiom.std` (stdlib), `xiom.openblas` 0.1.0 (the system
OpenBLAS seam; path dependency for the build)

## Overview

Safe BLAS/LAPACK-style linear algebra for XIOM: a value-semantics row-major
dense `Float64` matrix with shape-checked, typed errors, layered over the
`xiom.openblas`-backed primitives. No `unsafe` and no `extern` in this
package's modules; the BLAS runtime is never vendored, linked, or
redistributed here -- it ships via `xiom.openblas`' own loader/SKIP rules
(see PROVENANCE.md).

## Architecture

```
+---------------------------------------------------------------+
|  src/linalg.xi   xiom.blas.linalg                              |
|  SPEC surface: matrix_multiply, matrix_vector_multiply,        |
|  vector_dot, vector_scale, matrix_scale, matrix_determinant,   |
|  matrix_inverse, solve_linear_system (partial pivoting)        |
+---------------------------------------------------------------+
|  src/blas.xi     xiom.blas                                     |
|  DenseMatrix type; construction/access/element-wise; FFI seam: |
|  matmul, matvec, ddot, daxpy, scal  ->  delegates to openblas  |
+---------------------------------------------------------------+
|  xiom.openblas (path dep)                                      |
|  matrix pool + gemm/gemv/dot/axpy (pure-XIOM reference offline;|
|  real cblas_* wire-in = its ROADMAP Phase 1 remainder)         |
+---------------------------------------------------------------+
|  src/runtime.xi  xiom.blas.runtime                             |
|  typed availability classifier (ABSENT/PRESENT/ABI) mirroring  |
|  the canonical xiom.openblas probe rules                       |
+---------------------------------------------------------------+
```

### Design decisions

- **`DenseMatrix` is a flat row-major `Vec[Float64]` with explicit
  `rows`/`cols`.** Element `(i, j)` is at index `i * cols + j`.
- **The FFI seam delegates; it does not declare C.** `matmul`/`matvec`/
  `ddot`/`daxpy` convert to/from the `xiom.openblas` pool (Int handles) and
  call its declared surface. `blas.xiom-bind` keeps the declarative C ABI
  mapping for documentation; link resolution is owned by `xiom.openblas`
  (offline: its stub bridge; real: its loader rules).
- **Pure decompositions are self-contained.** `matrix_determinant`,
  `matrix_inverse` (Gauss-Jordan) and `solve_linear_system` (Gaussian
  elimination) implement **partial pivoting** directly in XIOM -- they need
  no runtime and no C. All share the same zero-pivot singularity test.
- **No aliases across name-colliding surfaces.** Seed names were renamed
  (see Deltas) because the v0.64.5 resolver mis-binds same-named
  declarations across imported modules. Collisions were removed at the
  source; every seam call inside the package is fully qualified
  (`xiom.blas.*`).

## Type system

| Type | Definition |
|------|------------|
| `DenseMatrix` | `{ rows: Int; cols: Int; data: Vec[Float64]; }` `derive[Clone]` |
| `RuntimeProbe` | `{ kind: Int; path: Str; message: Str; }` (`xiom.blas.runtime`) |

Runtime classification constants: `BLAS_RT_ABSENT = 0` (SKIP),
`BLAS_RT_PRESENT = 1`, `BLAS_RT_ABI = 2` (loud FAIL).

## API surface (delivered) and error modes

### Construction (xiom.blas)

| Function | Contract | Errors |
|----------|----------|--------|
| `matrix_new(rows, cols)` | `rows > 0`, `cols > 0`; zero-filled | -- |
| `matrix_zeros(rows, cols)` | `rows > 0`, `cols > 0` | -- |
| `matrix_identity(n)` | `n > 0` | -- |
| `vector_zeros(n)` / `vector_ones(n)` | `n > 0` | -- |

### Element access (xiom.blas)

| Function | Contract |
|----------|----------|
| `matrix_get(m, row, col)` | `row < m.rows`, `col < m.cols` |
| `matrix_set(m, row, col, val)` | `row < m.rows`, `col < m.cols` |

### Element-wise (pure; xiom.blas / xiom.blas.linalg)

| Function | Error mode |
|----------|------------|
| `matrix_add(a, b)` / `matrix_sub(a, b)` | `Err(Str)` on shape mismatch |
| `matrix_transpose(a)` | contract-checked |
| `matrix_scale(a, scalar)` | contract-checked |

### FFI-backed (delegated to the `xiom.openblas` seam)

| Seam (`xiom.blas`) | SPEC name (`xiom.blas.linalg`) | openblas call |
|--------------------|-------------------------------|---------------|
| `matmul(a, b)` | `matrix_multiply(a, b)` | `gemm(false,false)` over the pool |
| `matvec(m, v)` | `matrix_vector_multiply(m, v)` | `gemv(false)` over the pool |
| `ddot(x, y)` | `vector_dot(x, y)` | `dot(x, y, n)` |
| `daxpy(alpha, x, y)` | -- | `axpy(alpha, x, y, n)` |
| `scal(alpha, x)` | `vector_scale(alpha, v)` | pure loop (see Deltas) |

All matrix shapes are validated before delegation and returned as typed
`Err(Str)`; vector ops carry `requires` length contracts.

### Pure decompositions (xiom.blas.linalg)

| Function | Algorithm | Error mode |
|----------|-----------|------------|
| `matrix_determinant(a)` | LU with partial pivoting | `0.0` exactly when singular; `requires: rows == cols` |
| `matrix_inverse(a)` | Gauss-Jordan on `[A | I]`, partial pivoting | `Err` on non-square or singular |
| `solve_linear_system(a, b)` | Gaussian elimination + back substitution, partial pivoting | `Err` on non-square, length mismatch, or singular |

### Runtime classifier (xiom.blas.runtime)

| Function | Contract |
|----------|----------|
| `runtime_probe_named(path)` | classify one candidate: load + require `cblas_ddot` + `cblas_dgemm` |
| `runtime_probe()` | canonical rules: `XIOM_OPENBLAS_LIB` -> standard locations -> bare sonames |

## Coverage table (standing owner policy)

Every declared member below is exercised by `tests/test_conformance.xi`
(exact dyadic goldens; error paths asserted as typed `Err`) and included in
the compile-evidenced never-run walk (`blas_surface_coverage`).

| # | Declared member | Module | Impl path | Suite check |
|---|-----------------|--------|-----------|-------------|
| 1 | `matrix_new` | xiom.blas | pure XIOM | `matrix_new(3,4)` shapes |
| 2 | `matrix_zeros` | xiom.blas | pure XIOM | zero-filled |
| 3 | `matrix_identity` | xiom.blas | pure XIOM | diagonal 1 / off-diagonal 0 |
| 4 | `vector_zeros` | xiom.blas | pure XIOM | length+content |
| 5 | `vector_ones` | xiom.blas | pure XIOM | length+content |
| 6 | `matrix_get` | xiom.blas | pure XIOM | set/get roundtrip |
| 7 | `matrix_set` | xiom.blas | pure XIOM | set/get roundtrip |
| 8 | `matrix_add` | xiom.blas | pure XIOM | values + mismatch Err |
| 9 | `matrix_sub` | xiom.blas | pure XIOM | values + mismatch Err |
| 10 | `matrix_transpose` | xiom.blas | pure XIOM | values + shape |
| 11 | `matmul` | xiom.blas | openblas delegate | 2x2/rect/identity + mismatch Err |
| 12 | `matvec` | xiom.blas | openblas delegate | [17,39] + mismatch Err |
| 13 | `ddot` | xiom.blas | openblas delegate | 32 + empty 0.0 |
| 14 | `daxpy` | xiom.blas | openblas delegate | y = 2x + y |
| 15 | `scal` | xiom.blas | pure XIOM | 0.5 * [1,2,3] |
| 16 | `matrix_multiply` | xiom.blas.linalg | openblas delegate | [[19,22],[43,50]] |
| 17 | `matrix_vector_multiply` | xiom.blas.linalg | openblas delegate | [17,39] |
| 18 | `vector_dot` | xiom.blas.linalg | openblas delegate | 32 |
| 19 | `vector_scale` | xiom.blas.linalg | pure XIOM | 0.25 * [2,4] |
| 20 | `matrix_scale` | xiom.blas.linalg | pure XIOM | *2 exact |
| 21 | `matrix_determinant` | xiom.blas.linalg | pure LU + pivoting | -1 pivot case, -2, 0, 24 |
| 22 | `matrix_inverse` | xiom.blas.linalg | pure Gauss-Jordan | exact halves + pivot + singular/non-square Err |
| 23 | `solve_linear_system` | xiom.blas.linalg | pure Gauss + back-sub | 3 systems + 3 Err paths |
| A | `runtime_probe_named` / `runtime_probe` | xiom.blas.runtime | stdlib `ffi.dl` | constants + absent + ABI + full probe |
| B | coverage walk (23/23) | all | compile-evidenced | `coverage: 23/23 declared members` |

## Deltas vs the seed SPEC

| Seed | Delivered | Reason |
|------|-----------|--------|
| `pub type Matrix` | `pub type DenseMatrix` | Same-name collision with `xiom.openblas.Matrix`; cross-module mis-binding faulted the pool handle as a struct (access violation) under the v0.64.5 resolver. Repro + evidence in AUDIT.md. |
| `identity(n)` | `matrix_identity(n)` | `identity` collides with `xiom.convert.identity[T]`; a unit importing both binds the foreign generic (observed in this package's own suite). |
| seam `dot` / `axpy` | `ddot` / `daxpy` | Same-name declarations in `xiom.openblas` with identical leading parameter types (no type-based disambiguation); an unqualified call can silently bind to the wrong arity and drop an argument (observed: AUDIT.md C2). The `d`-prefixed names mirror the CBLAS double-precision surface and collide with nothing. |
| seam calls inside the package | fully qualified `xiom.blas.*` | The resolver mis-bound an unqualified `dot(a, b)` inside `xiom.blas.linalg` to the 3-argument `xiom.openblas.dot` and silently dropped the third argument (contract trap at run time). |
| `vector_scale` -> `cblas_dscal` | pure XIOM loop | The live `xiom.openblas` seam declares no `dscal` wrapper; the seam stays the single home for a future real wire-in. |
| `blas.xi` at package root | `src/blas.xi` | v0.64.5 resolves intra-package modules only within one source directory; all modules now live in `src/` (matches `xiom.numpy`/`xiom.epos`/`xiom.sqlite` layout). |
| LAPACK surface (seed table) | out of scope (0.1.0) | The live `xiom.openblas` LAPACK paths (`svd`/`eigen_sym`/`solve`) are Phase-1 stubs; the safe layer delivers self-contained decompositions instead and keeps the seam as the accel target (ROADMAP). |

## External dependencies

- **Runtime:** OpenBLAS (`libopenblas.dll` / `libopenblas.so`) -- loaded and
  classified exclusively by `xiom.openblas`' rules; nothing vendored here.
- **Build:** `xiom.openblas` path dependency (`../xiom-openblas`) via
  `xiom.toml`; offline link seam is its `bridge/openblas_bridge.c`
  (wired via `port.args.json`).

## Error handling

1. Shape violations return `Err(Str)` with descriptive messages before any
   work (never a contract trap on user-input shapes).
2. Singular matrices (exact zero pivot after partial-pivot selection)
   return `Err("... singular matrix ...")`; `matrix_determinant` returns
   exactly `0.0`.
3. Index/contract violations on construction/access are caught by
   `requires` (compile time where provable; runtime-checked traps
   otherwise).
4. No silent failures and no `unsafe` at the API boundary.
