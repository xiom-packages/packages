# PROVENANCE -- xiom.blas

Upstream / dependency provenance for `xiom.blas` 0.1.0 (folded 2026-10-17).

## Nothing is vendored

This package **vendors no third-party source, binaries, headers, or
libraries**. It contains only first-party XIOM code:

| Path | Origin |
|------|--------|
| `src/blas.xi`, `src/linalg.xi`, `src/runtime.xi` | XIOM Authors (this repository) |
| `blas.xiom-bind` | XIOM Authors -- declarative C ABI mapping for the seam symbols (`cblas_dgemm`/`dgemv`/`ddot`/`daxpy`/`dscal`); documentation of the CBLAS surface, no code |
| `tests/*` | XIOM Authors |

## The BLAS runtime ships via xiom.openblas

The OpenBLAS runtime is **not acquired, bundled, or redistributed by this
package**. The dependency story:

- **Package dependency:** `xiom.openblas` 0.1.0 (`package.xi` deps) --
  published in `eco-v0.1.193` (2026-10-16, sha256 `a6740ae1...`), the
  system-OpenBLAS seam of the ML/AI stack.
- **Build dependency:** path dependency `../xiom-openblas` via `xiom.toml`
  (the v0.64.x catalog source-root resolver reads `xiom.toml`
  `[dependencies]`; same pattern as `xiom.numpy`).
- **Offline link seam:** `port.args.json` links
  `xiom.openblas`' `bridge/openblas_bridge.c` (its documented stub
  link-seam; computes nothing -- the offline numbers come from the seam's
  pure-XIOM reference paths). The bridge file is owned by `xiom.openblas`
  and referenced, not copied.
- **Real runtime acquisition:** entirely by `xiom.openblas`' loader/SKIP
  rules -- nothing is installed or modified by this package or its tests.
  `xiom.blas.runtime` mirrors those canonical rules for classification:
  1. `XIOM_OPENBLAS_LIB` environment override;
  2. standard install locations (`C:\OpenBLAS\...`, `C:\Program Files\OpenBLAS\...`,
     msys2/chocolatey paths; `/usr/local/lib`, `/usr/lib`, ... on POSIX);
  3. bare sonames through the OS loader search order (`libopenblas.dll`,
     `openblas64_.dll`, `openblas.dll`, `libopenblas.so`, `libopenblas.so.0`).
  A candidate counts as present only when it loads **and** exports both
  `cblas_ddot` and `cblas_dgemm`; loaded-without-exports is a loud ABI
  failure, never a silent skip.
- **Real-library probe:** `tests/probe_real_blas.xi` reuses
  `xiom.openblas`' own `tests/probe_openblas_shim.c` (the canonical
  detection+call shim; the C shim exists because Float64 returns through
  dlsym'd fn pointers are unreliable on the v0.64.5 toolchain, recorded in
  `xiom.openblas`' findings). No copy is kept here.

## Upstream license posture

- OpenBLAS: BSD-3-Clause. Not redistributed here (system-installed only).
- `xiom.openblas` (this repository): MIT OR Apache-2.0.
- This package: MIT OR Apache-2.0 (see `package.xi`).

## Repro pins

- Compiler: v0.64.5 (lane pin; `%LOCALAPPDATA%\xiom.new.0645`).
- `xiom.openblas` tree: identical to the live eco-v0.1.193 landing
  (module + bridge + probe shim; the branch carries the upstream commits
  verbatim -- no local edits to that package).
- Suite x2: 50/50 on v0.64.5 (records in `STATUS.json`).
