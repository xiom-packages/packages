# xiom.openblas

> **Status:** `incubating` -- conformance-green on compiler v0.64.5 (32/32, two
> consecutive runs); not yet published to the XIOM registry.
> **Scope:** OpenBLAS backend integration and acceleration (BLAS 1-3, LAPACK
> surface, matrix lifecycle).
> **Deps:** stdlib; wraps C (FFI) through a declared extern "C" surface.

## Two-leg verification (see SPEC.md)

| Leg | Command | OpenBLAS needed |
|-----|---------|-----------------|
| Offline conformance (stub link-seam, documented backend-unavailable-by-design for the C symbols; numbers come from the pure-XIOM reference paths) | `.\scripts\port.ps1 -Package xiom-openblas -TimeoutSec 180` | No |
| Real-library probe (runtime detection; SKIP-safe) | `xiom --run tests\probe_real_openblas.xi --c-source <pkg>\tests\probe_openblas_shim.c` | Yes, else `[SKIP]` exit 0 |

The real leg detects `libopenblas.dll` / `openblas64_.dll` / `openblas.dll`
(Windows) or `libopenblas.so` / `libopenblas.so.0` (POSIX) via the
`XIOM_OPENBLAS_LIB` override, standard install locations, then the OS loader
search order (PATH on Windows, ld.so + `LD_LIBRARY_PATH` on POSIX). It
exercises real `cblas_ddot` and `cblas_dgemm` and never installs anything.

## Layout

| Path | Purpose |
|------|---------|
| `openblas.xi` | Module `xiom.openblas`: pool, public API, extern C surface (int32 blasint ABI) |
| `bridge/openblas_bridge.c` | Offline stub link-seam (wired via `port.args.json`); computes nothing |
| `tests/test_conformance.xi` | 32 conformance checks on the current xiom.test API |
| `tests/probe_real_openblas.xi` + `tests/probe_openblas_shim.c` | Real-library probe (real leg) |

## Integration notes

- Distinct from the `xiom-blas` seed package (`src/linalg.xi` + `blas.xiom-bind`),
  which is a reference/struct-based BLAS implementation; `xiom.openblas` is the
  system-OpenBLAS seam for the ML/AI stack.
- `xiom.numpy` Phase 2 consumes the matrix lifecycle, `dot`/`axpy`/`gemv`/`gemm`
  fast paths and the linalg surface from here (see SPEC.md).
- Never link `bridge/openblas_bridge.c` together with a real OpenBLAS
  (duplicate symbols); drop the `--c-source` entry and link the system import
  library instead (ROADMAP Phase 1 remainder).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `openblas` | OpenBLAS runtime bindings (extern "C" surface + offline stub seam). |
| `gemm` | Matrix-matrix multiply (pure-XIOM path; real cblas wiring pending). |
| `gemv` | Matrix-vector multiply. |
| `dot` | Vector dot product (cblas_ddot seam). |
| `thread` | Threading control (Phase 4 -- `openblas_set_num_threads`). |
| `info` | Runtime/version info (Phase 4). |
