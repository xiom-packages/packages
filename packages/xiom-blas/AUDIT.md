# xiom.blas Audit

**Fold:** 2026-10-17, agent `am:feat-blas-fold` (worktree feat/blas-fold),
compiler v0.64.5 pin (`%LOCALAPPDATA%\xiom.new.0645`).
**Verdict:** suite 50/50 x2 green; real-lib probe SKIP x2 + present x2 green;
typed-absent SKIP recorded on this host.

## 1. Baseline (pre-fold state, v0.64.6)

`.\scripts\port.ps1 -Package xiom.blas` on the parked seed failed with
**112 type errors** -- the declared suite had never compiled:

- `use xiom.blas.linalg;` + `linalg.matrix_new(...)` could not resolve: the
  seed's `src/linalg.xi` declared its functions `fn` (private), and the
  v0.64.5 resolver does not support partial-alias qualified calls from the
  test module.
- `src/linalg.xi` imported the parent module `xiom.blas` while `blas.xi`
  lived at the package root: intra-package imports only resolve inside one
  source directory, so the module catalog was effectively unloadable
  (see finding C3 below).
- The FFI seam (`matmul`, `matvec`, `dot`, `axpy`, `scal`) was a set of
  bodiless forward declarations with a link-time mapping that was never
  wired to any provider -- calling them either failed to link or jumped to
  a null/undefined symbol (observed access violation when first exercised).
- `AUDIT.md`/`STATUS.json` claimed no evidence (`tests.status: unknown`);
  the seed audit's "PASSES" rows were stale.

## 2. Delivered changes (all inside `packages/xiom-blas/`)

| File | Change |
|------|--------|
| `src/blas.xi` (moved from `blas.xi`) | `DenseMatrix` (renamed, see D2); FFI seam implemented by delegation to `xiom.openblas` (`__pool_from_matrix`/`__matrix_from_pool` conversion helpers); shape checks return typed `Err(Str)` before any delegation; `scal` pure loop; pool handles freed on every error path. |
| `src/linalg.xi` | Rewritten over `xiom.blas.DenseMatrix`: `matrix_multiply`/`matrix_vector_multiply`/`vector_dot`/`vector_scale` delegate via **fully qualified** `xiom.blas.*` calls; `matrix_scale`, `matrix_determinant` (LU), `matrix_inverse` (Gauss-Jordan), `solve_linear_system` (Gaussian elimination + back substitution) all reimplemented **with partial pivoting** and typed error paths (non-square / length mismatch / singular). |
| `src/runtime.xi` (new) | Module `xiom.blas.runtime`: typed availability classifier (`BLAS_RT_ABSENT`/`PRESENT`/`ABI`) mirroring the canonical `xiom.openblas` probe rules; stdlib `ffi.dl` only (no `unsafe`, no calls through the loaded library). |
| `tests/test_conformance.xi` | Rewritten: 50 checks (runtime classifier, construction/access, element-wise, seam, SPEC names, decompositions, coverage walk); epos-style `[PASS]`/`[FAIL]` runner with `port.ps1`-countable markers; typed-absent SKIP recorded in-suite. |
| `tests/probe_real_blas.xi` (new) | Real-library leg (SKIP-safe) reusing `xiom.openblas`' canonical probe shim; present path pins real `cblas_ddot`/`cblas_dgemm` goldens **and** safe-layer goldens on identical inputs. |
| `tests/test_blas.xi` | Removed (subsumed by `test_conformance.xi`). |
| `xiom.toml` (new) | `[dependencies] xiom.openblas = { path = "../xiom-openblas" }` -- catalog source root for the seam (same pattern as `xiom.numpy`). |
| `port.args.json` (new) | `--c-source ${PACKAGE_DIR}/../xiom-openblas/bridge/openblas_bridge.c` -- the openblas-owned stub link seam for the offline leg. |
| `package.xi` | `deps` += `"xiom.openblas": "0.1.0"`. |
| Docs | README/SPEC rewritten; PROVENANCE/ROADMAP added; STATUS recorded from the runs. |

## 3. Compiler findings (v0.64.5 toolchain, bindings lane)

### C1 -- cross-module same-name TYPE mis-binding (ship-blocker worked around)

- **Symptom:** a program whose unit carries both `xiom.blas` and
  `xiom.openblas` faulted (exit `0xC0000005`) inside `xiom.openblas`'
  pure-XIOM `matrix_free`.
- **Diagnosis (IR evidence):** both modules declare `pub type Matrix`
  (safe layer: struct; openblas: `Int` handle). The resolver bound the
  short name `Matrix` in the openblas call sites to the *other* package's
  struct: `call void @openblas.matrix_free(%struct.xiom.blas.Matrix %tmp52)`
  -- an 8-byte handle loaded as a 24-byte struct, so the pool index read
  garbage.
- **Repro shape:** unit importing both packages; bind a value from
  `xiom.openblas.matrix_create(...)`, then call `matrix_free` on it.
  Minimal dir: `packages/xiom-blas/tests/` pre-fix (channel: safe-layer
  `DenseMatrix` rename stops it).
- **Resolution (package-side):** safe-layer type renamed to `DenseMatrix`;
  **no same-named type crosses the two packages anymore.**

### C2 -- same-name function mis-binding + silent argument drop

- **Symptom:** with `d ∈ linalg.vector_dot` compiling, the emitted IR
  contained `call double @openblas.dot(%struct.Vec* %a, %struct.Vec* %b)` --
  a **2-argument call to the 3-parameter** `xiom.openblas.dot`; the missing
  `n` lowered as garbage, so `requires: n > 0` trapped at run time
  (`contract violated: requires at openblas.xi:202:13`).
- **Context:** the unqualified `dot(a, b)` inside `src/linalg.xi` resolved
  to the transitively visible `xiom.openblas.dot` (same name, different
  arity) instead of `xiom.blas.dot` from the direct import. No arity
  diagnostic was emitted.
- **Resolution (package-side):** every seam call inside the package is now
  fully qualified (`xiom.blas.ddot`, `xiom.blas.matmul`, ...), AND the two
  seam members whose names carry identical leading parameter types in both
  packages (`dot`, `axpy`) were renamed to `ddot`/`daxpy` (BLAS
  double-precision convention) so no same-name/ambiguous-signature pair can
  ever be re-bound in a consumer unit. Tests call the SPEC names
  (`vector_dot`) or the unambiguous seam names. `matrix_get`/`matrix_set`
  keep their names: their first parameter type differs across the two
  packages (`DenseMatrix` vs `Int` handle), so the resolver has a type
  discriminant (binding verified in IR).
- **Sibling-class:** `identity(n)` aliasing was dropped for the same
  reason (`xiom.convert.identity[T]` binds over it in any unit importing
  both) -- the delivered constructor is `matrix_identity(n)`.

### C3 -- a broken sibling module poisons the whole package catalog

- During bring-up, any syntax/type error in one module of the package
  (e.g. a temporarily broken `src/linalg.xi`) made *unrelated* modules stop
  resolving in test-entry compiles (`undefined variable 'matrix_new'` while
  compiling `tests/*.xi`, with no diagnostic naming the broken module).
- Practical rule (verified): keep every module of the package parseable at
  all times; module layout must keep all package modules in one directory
  (`src/`) -- a package-root module file is not resolvable from `src/` or
  `tests/` entries (this is why the seed failed; all modules moved to
  `src/` like `xiom.numpy`/`xiom.epos`/`xiom.sqlite`).

## 4. Verification evidence (all on compiler v0.64.5)

| Leg | Command | Result |
|-----|---------|--------|
| Offline suite x2 | `.\scripts\port.ps1 -Package xiom.blas -TimeoutSec 300` | **PASS 50/50** (run 1 full, run 2 `-Quiet`), both `program_exit=0`; namespace-check 3 modules OK |
| Real-lib probe (absent) x2 | `xiom --run tests\probe_real_blas.xi --c-source ...\probe_openblas_shim.c --c-source ...\openblas_bridge.c` | **[SKIP] x2**, exit 0 (no system OpenBLAS on this host by the canonical rules) |
| Real-lib probe (present) x2 | same + `XIOM_OPENBLAS_LIB=...\GIMP 2\bin\libopenblas.dll` (canonical override) | **5/5 PASS x2**, exit 0: real `cblas_ddot == 32`, real `cblas_dgemm == [[19,22],[43,50]]`, safe-layer goldens equal |
| ABI loud-FAIL control | same + `XIOM_OPENBLAS_LIB=...\Julia-1.11.6\bin\libopenblas64_.dll` (ILP64) | **[FAIL] exit 1** ("loaded but does not export cblas_ddot + cblas_dgemm") -- matches `xiom.openblas`' documented classification |
| In-suite classifier | suite section 0 | typed-absent SKIP recorded; bogus-soname ABSENT and kernel32 ABI paths deterministic |

Exact goldens are dyadic rationals (integers/halves) so all comparisons are
exact `Float64` equality; no tolerances were used.

## 5. Known gaps / notes

- The real `cblas_*` wire-in of the seam is `xiom.openblas` ROADMAP Phase-1
  remainder; until then the delegated numbers come from its pure-XIOM
  reference paths (identical on the pinned goldens, proven by the probe).
- `matrix_determinant` keeps a `requires: rows == cols` contract
  (infallible return type); `matrix_inverse`/`solve_linear_system` return
  typed `Err` for non-square input instead.
- `xiom.geom.vector` also exports a `dot(a, b)`; consumers importing both
  should prefer `vector_dot`.
