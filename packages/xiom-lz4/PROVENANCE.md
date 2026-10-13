# PROVENANCE -- xiom.lz4

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage).

## Upstream (oracle)

- `github.com/lz4/lz4`, tag **v1.10.0** = commit
  **`ebb370ca83af193212df4dcbadcc5d87bc0de2f0`** (latest stable release at the
  time of the wave; 2024-07-22).
- Clone: `E:\repos\lz4` (shallow at the tag, re-checked out with LF line
  endings so vendored copies are byte-identical to the git blobs).
- License verified in the clone: `lib/` is **BSD-2-Clause** (`vendor/lz4/LICENSE`,
  "Copyright (c) 2011-2020, Yann Collet"); the repository root also carries
  GPL-2.0 for non-`lib` material, which is **not** vendored. Class:
  permissive (lib) -- vendoring is allowed.
- Prepared by: `docs/prep/codec-wave-b.md` sec. 4/5 (this package implements
  full-surface binding of `lz4.h` + `lz4hc.h` + `lz4frame.h`).

## Vendored files (byte pins)

All hashes are SHA256 over the stored LF bytes; `.gitattributes` pins
`vendor/** -text`.

| Vendored | Bytes | SHA256 |
|----------|-------|--------|
| `vendor/lz4/lz4.c` | 118,145 | `9396f7de527bc8435de9c7569fb7998e56545a84b4f3c2d808c0235c01774539` |
| `vendor/lz4/lz4.h` | 46,014 | `26b82efc53d1570f3b54eef02e9c4764c1ad374ff03cac04e2ced5ea4d4c552f` |
| `vendor/lz4/lz4hc.c` | 93,376 | `126cafafdb91767e6e55238298a910903851b35b2cee27ce80ae2280469ee232` |
| `vendor/lz4/lz4hc.h` | 20,308 | `e43824e8a9ba16f54100c4ccbccfa5782a858ca9ab83c48aac303fea3e76e21e` |
| `vendor/lz4/lz4frame.c` | 91,373 | `44f421bea199c7f11da263c717f063228cd2c8c05a8384d327b49cc81ccfbac4` |
| `vendor/lz4/lz4frame.h` | 36,085 | `b845db4b7ee1bfa64b8f641a94f62e7f636a8b5d673cc61766413782283aaad1` |
| `vendor/lz4/lz4frame_static.h` | 2,044 | `31ab72a6e97e4fa0bedd4420d24a3f1f8024cbfa1d8ffad88c87cbb4e04f769d` |
| `vendor/lz4/xxhash.c` | 34,122 | `b667033dc735fb5ea5648e0a61a2e065e5ef5bbda53669730063bd856c643c48` |
| `vendor/lz4/xxhash.h` | 13,466 | `aefdd236f35130495c18764cabed3f7b216906855fc5e6a9025cd2040bc84444` |
| `vendor/lz4/LICENSE` | 1,311 | `8b58c446121a109ccf32edc094bba3010a3d85e4ee3702950db55e4d3e87736c` |
| `vendor/lz4/README.md` | 9,063 | `a26e68719f64ebdef6ea1a9c0ca7bf76892a49d041e336364bcf91bbfb1875eb` |

`lz4frame.c` needs `xxhash.c` (compiled separately; `lz4frame.c` only includes
`xxhash.h`), and `lz4.c`/`lz4hc.c` are self-contained beyond `lib/` headers.
`lz4file.c`/`lz4file.h` (stdio convenience layer) are **not** part of the
three target headers and are not vendored.

## Derived vs independent

- **Derived (verbatim vendored):** the eleven `lib/` files above.
- **Original to this package:** `src/lz4_bridge.c` (null pointer, string
  copies, LZ4F slot struct helpers, CustomMem-by-value advanced creators, one
  decompression loop), `tools/gen_lz4_ffi.py` (generator + fail-closed
  coverage checker), `src/lz4_ffi.xi` (generated 1:1 surface), `src/lz4.xi`
  (facade), `tests/test_conformance.xi`.
- **Coverage proof:** `docs/COVERAGE.md` + `docs/surface_lz4.json` -- all
  **111 declared functions** of the three pinned headers have an `extern "C"`
  declaration and a `pub fn` wrapper in `src/lz4_ffi.xi` (66 stable, 34
  deprecated, 11 static-linking-only); the checker fails closed if any name
  is missing from the header text or the module.

## Test vectors

Upstream ships its own test suite but no redistributable vector files that
cover the bound surface; the conformance suite builds deterministic inputs in
XIOM (repeating patterns for compressible data, an LCG for incompressible
data) and asserts byte-exact round trips plus the exact LZ4F error codes for
corrupted frames (content checksum -> `ERROR_contentChecksum_invalid`).

## Clone ledger

Rows in `E:\repos\CLEANUP.md` (bindings lane, review after 2026-12-01):
`lz4` (added 2026-10-13), plus the spz-wave `zlib` row. Re-carve procedure:
SPEC.md sec. 8.
