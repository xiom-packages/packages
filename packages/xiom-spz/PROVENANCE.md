# PROVENANCE -- xiom.spz

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage).

## Upstream (oracle)

- `github.com/nianticlabs/spz`, tag **v3.0.0** = commit
  **`5bf2945de1a003cee07133b1e495fe9c6ffdc7e7`** ("[perf] Use
  std::nth_element for medianVolume() (#79)").
- Clone: `E:\repos\spz` (shallow at the tag; re-checked out with LF line
  endings so vendored copies are byte-identical to the git blobs).
- License verified in the clone: **MIT** (`vendor/spz/LICENSE`, "Copyright (c)
  2025 Niantic Labs / Adobe Inc." with the 2024 Niantic notice in the .cc
  headers). Class: permissive -- vendoring is allowed.
- Prepared by: `docs/prep/codec-wave-b.md` sec. 4 (this package implements the
  "read/unpack mandatory; pack optional" recommendation with pack included).

## Vendored files (byte pins)

All hashes are SHA256 over the stored LF bytes; the full table is regenerated
by `python tools/build_vendor.py` into `docs/vendor_manifest.json`
(33 files). Key rows:

| Vendored | Origin | Bytes | SHA256 |
|----------|--------|-------|--------|
| `vendor/spz/load-spz.h` | spz v3.0.0 `src/cc/` | 7,468 | `6cd6f4da127c743961f07daa6a6572296df3962df220ee9204d46a5a7ed78198` |
| `vendor/spz/load-spz.cc` | spz v3.0.0 `src/cc/` | 51,249 | `17a6d1804b829a3604830d312560548f6e104aba32214f70d015dd0a453a55ed` |
| `vendor/spz/splat-types.h` | spz v3.0.0 `src/cc/` | 11,109 | `c25a2aa5415d72f2985121a320b946917517e925784b2be2329d93ed2301c724` |
| `vendor/spz/splat-types.cc` | spz v3.0.0 `src/cc/` | 4,003 | `c91f19bb96fbf89393bd07c336c93d96f5990dda12e348defbbf089f434cab7c` |
| `vendor/spz/splat-c-types.h` | spz v3.0.0 `src/cc/` | 1,914 | `726aa56d344821e665db4e0191b67e2d34b24395629cc0bc824f06b28ccd6ee6` |
| `vendor/spz/splat-c-types.cc` | spz v3.0.0 `src/cc/` | 1,114 | `f37b8a3d52fa5637d9899d32f873315e061e022fa9cb6cfbe3d76e07d0e966f7` |
| `vendor/spz/LICENSE` | spz v3.0.0 root | 1,090 | `8b1234cafec672d87a126d13bf3740858ae1a2761383342c2d0225154bb523ca` |
| `vendor/zlib/*` (22 files) | `github.com/madler/zlib` tag **v1.3.1** = `51b7f2a` (the exact version spz's CMake FetchContent pins, SHA256 `9a93b2b7...`) | 1,034,172 total | see manifest |
| `vendor/zstd/zstd.c` | `github.com/facebook/zstd` v1.5.7 single-file amalgamation | 2,174,920 | `208e110a1f052d007242d4eef6ed20a03ab1dc6e13eb2c4ff8d158112120ba8e` |
| `vendor/zstd/zstd.h` | zstd v1.5.7 `lib/` | 181,748 | `9b4bc8245565c98ccfc61c07749928b57e7c0f6fddb0530c4f6aa1971893d88b` |
| `vendor/zstd/zstd_errors.h` | zstd v1.5.7 `lib/` | 4,278 | `66a8c3f71d12ea6e797e4f622f31f3f8f81c41b36f48cad4f5de7d8bfb6aac0a` |
| `vendor/zstd/LICENSE` | zstd dual BSD-3/GPLv2; **BSD-3-Clause** selected | 1,549 | `7055266497633c9025b777c78eb7235af13922117480ed5c674677adc381c9d8` |

Notes:

- The zstd artifacts are **byte-identical to the fleet-vendored copy** of
  `xiom.zstd` 0.2.0 (its SPEC.md pins the same `208E110A...`/`9B4BC824...`
  hashes). Upstream spz pins zstd 1.5.6 via FetchContent; this package
  deliberately aligns to the already-vendored **1.5.7** (zstd frames are
  version-stable, no API break) per the single-vendored-copy policy.
- zlib is the only new clone this package introduced (`E:\repos\zlib`,
  v1.3.1 = `51b7f2a`); zlib's license (zlib license) is permissive and its
  LICENSE is vendored. `gz*`/`compress.c`/`uncompr.c` are not vendored --
  only the files the upstream inflate/deflate paths reference.

## Derived build copy (single documented edit)

The pinned toolchain's `--c-source` facility has no include-directory flag
(verified on v0.64.4: `xiom --help` offers none; clang is invoked from a
scratch cwd), so `load-spz.cc`'s two angle includes cannot resolve to the
sibling vendor trees. `tools/build_vendor.py` emits
`vendor/spz/load-spz.build.cc`: the pinned source with **exactly two**
rewrites, each verified to apply once:

    #include <zlib.h>  ->  #include "../zlib/zlib.h"
    #include <zstd.h>  ->  #include "../zstd/zstd.h"

Input, output and rewrite list are hashed into `docs/vendor_manifest.json`.
No other byte of the upstream file is touched. `src/zstd_all.c` is our
compile shim (`STATIC_BMI2 0`, the same shim xiom.zstd ships) around the
unmodified amalgamation.

## Derived vs independent

- **Derived (verbatim vendored):** the six `src/cc` files, zlib sources,
  zstd amalgamation and headers, and all LICENSE files listed above.
- **Original to this package:** `src/spz_bridge.cpp` (flat C ABI over the
  C++ API), `src/spz.xi` / `src/spz_ffi.xi` / `src/spz_math.xi`,
  `tests/test_conformance.xi`, `tools/build_vendor.py`,
  `tools/surface_spz.py`, and the compile shim `src/zstd_all.c`.
- **Coverage proof:** `docs/COVERAGE.md` + `docs/surface_spz.json` -- 53
  declared items from the pinned headers (29 bridged with bridge symbol +
  XIOM wrapper, 21 modeled as XIOM types/constants, 3 audited non-goals),
  fail-closed against the header text and the code symbols.

## Test vectors

Upstream ships no spz vector corpus. The conformance suite builds a
deterministic 6-point/degree-2 Gaussian fixture in XIOM and pins the
**quantizer byte values** against the formulas read from the pinned
`load-spz.cc` (`round(sigmoid(-2)*255)=30`, `(-9.9375+10)*16=1`,
`round(0.5*0.15*255+127.5)=147`, 24-bit fixed-point position bytes); the v3
round trip additionally proves `serialize + compressGzipped` reproduces the
container byte-for-byte.

## Clone ledger

Rows in `E:\repos\CLEANUP.md` (bindings lane, review after 2026-12-01):
`spz` (pre-existing wave-B row), `zlib` and `lz4` (rows added 2026-10-13),
`zstd` (pre-existing). Re-carve procedure: SPEC.md sec. 8.
