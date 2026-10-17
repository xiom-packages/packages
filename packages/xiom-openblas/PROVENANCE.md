# PROVENANCE -- xiom.openblas

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage).

- **Upstream project:** OpenBLAS -- https://github.com/OpenMathLib/OpenBLAS
  (BSD-3-Clause; the license text was verified from the pinned source tag,
  see the hash below). OpenBLAS itself is based on GotoBLAS2 1.13 BSD and
  imports Reference-LAPACK routines.

- **Declared pin (G2):** release **v0.3.34** (published 2026-07-16), official
  Windows x64 binary asset
  `OpenBLAS-0.3.34-x64.zip`
  (https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.34/OpenBLAS-0.3.34-x64.zip).

  | Item | Value |
  |------|-------|
  | Asset bytes | 40,860,061 |
  | SHA256 | `E9CB6134541F36C27346D5FC5995652F060FBA227CEBBABCBDA5A5A44D7C76B` |
  | GitHub release `digest` | `sha256:e9cb6134541f36c27346d5fc5995652f060fba227cebbbabcbda5a5a44d7c76b` (match) |
  | Upstream-published MD5 | `5047115a08a7d39471375a25994108c5` (verified locally: match) |
  | `bin/libopenblas.dll` SHA256 | `0486735C359A67419D8832E3C40E2837F8762BAEBCDF4B62D3B18C91F9ECE12E` |
  | `bin/libopenblas.dll` bytes | 51,379,251 |

  Verification machine layout: `E:\repos\openblas\v0.3.34-x64` (zip kept at
  `E:\repos\openblas\OpenBLAS-0.3.34-x64.zip`). Nothing from this build is
  vendored into the repository.

- **License (checked before use):** OpenBLAS is **BSD-3-Clause**
  (`Copyright (c) 2011-2014, The OpenBLAS Project`). The binary zip does not
  carry a LICENSE file, so the license text was fetched from the pinned tag:
  https://raw.githubusercontent.com/OpenMathLib/OpenBLAS/v0.3.34/LICENSE
  (1,548 bytes; SHA256
  `190B5A9C8D9723FE958AD33916BD7346D96FAB3C5EA90832BB02D854F620FCFF`).
  Redistribution is not performed by this package (system-installed only);
  if a downstream distributor bundles the DLL, the BSD-3-Clause notice and
  disclaimer must be reproduced.

- **ABI evidence -- LP64 / int32 `blasint` (this is the declared ABI):**
  - `include/openblas_config.h` line 89: `typedef int blasint;`
    (`OPENBLAS_USE64BITINT` is **not** defined in this build).
  - `lib/pkgconfig/openblas.pc`: `openblas_config= USE_64BITINT= ...`
    (empty value), `version=0.3.34`.
  - The release also publishes `OpenBLAS-0.3.34-x64-64.zip`, which is the
    ILP64 (`OPENBLAS_USE64BITINT`) variant. It was deliberately **not**
    used; `tests/run_real_leg.ps1` refuses a build whose config header
    defines `OPENBLAS_USE64BITINT`.
  - LAPACK entry points are Fortran symbols with hidden `size_t` character
    lengths (`lapack.h` defines `LAPACK_FORTRAN_STRLEN_END`); the extern
    block in `openblas.xi` passes them for `dgesvd_`/`dsyev_`. `dgesv_` has
    no character arguments.

- **Import libraries present in the asset:** `lib/libopenblas.lib` (MSVC)
  and `lib/libopenblas.dll.a` (MinGW); the XIOM real leg links with
  `--link-path <root>\lib --link libopenblas` and loads
  `bin/libopenblas.dll` from PATH. The DLL is a DYNAMIC_ARCH build
  (`DYNAMIC_ARCH=1 DYNAMIC_OLDER=1`, `MAX_THREADS=64` per the pkg-config
  metadata), so the same artifact covers the x86_64 microarchitecture range.

- **Declared surface:** the package binds 4 CBLAS functions
  (`cblas_ddot`, `cblas_daxpy`, `cblas_dgemv`, `cblas_dgemm`) and 3 LAPACK
  routines (`dgesvd_`, `dsyev_`, `dgesv_`), plus the leg marker defined by
  the selected C bridge. Every symbol was resolved from
  `lib/libopenblas.def` / the linked artifact, not from memory.

- **Source study clone:** not required -- the pin is an official binary
  release; headers + `libopenblas.def` are the declaration oracle.

- **Re-pin procedure:** download the new official `-x64.zip` asset, verify
  the GitHub `digest` (SHA256), extract to
  `E:\repos\openblas\v<version>-x64`, confirm `typedef int blasint;` in
  `include/openblas_config.h`, then run
  `tests\run_real_leg.ps1 -OpenBlasRoot <root> -Require` twice and record
  the result in `STATUS.json` / `docs/REAL-LEG.md`.
