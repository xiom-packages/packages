# PROVENANCE: xiom.stb

## 1. Vendored upstream

| Field | Value |
|---|---|
| Project | stb (single-header libraries: stb_image.h, stb_image_write.h) |
| Repository | `https://github.com/nothings/stb` |
| Pin | commit **`2c980bb59875b0d32144a71867fbdebb2f77cd20`** (2026-08-02) |
| Licence | dual **public domain / MIT** (stb's own grant, embedded at the end of each header) |
| Clone verified | `E:\repos\stb` (2026-10-14; fetch `--depth 1` at the pin commit); `git rev-parse HEAD` == pin |
| Extraction | Canonical bytes via `git cat-file blob`; the clone worktree is autocrlf-converted on Windows, so file-level comparison must use the blobs |
| Vendoring | Both headers copied **unmodified** into `vendor/` (no include rewriting, no build config) |

Byte-identity verification (2026-10-14): `git hash-object --no-filters`
of each vendored file equals the upstream blob:

| Vendored file | Upstream blob (git sha1) | Checkout SHA256 (as vendored) |
|---|---|---|
| `vendor/stb_image.h` | `9eedabedc45b3e6fd88fae6f14a160b4d53272ec` | `594C2FE35D49488B4382DBFAEC8F98366DEFCA819D916AC95BECF3E75F4200B3` |
| `vendor/stb_image_write.h` | `e4b32ed1bc32ef9c962acbf47a9d10af01939e08` | `CBD5F0AD7A9CF4468AFFB36354A1D233803F2C12473CF1A8E32053CB6914A05` |

Sizes (canonical/LF): `stb_image.h` 283,010 B; `stb_image_write.h` 71,221 B.

## 2. Package-local code

| Path | Licence | Notes |
|---|---|---|
| `stb.xi` | MIT OR Apache-2.0 (XIOM Authors) | safe wrappers + the HDR class surface; consts derived from the vendored header |
| `src/stb_all.c` | MIT OR Apache-2.0 (XIOM Authors) | one TU: both `STB_*_IMPLEMENTATION` macros + probe bridge (0.2.0) + HDR bridge (0.3.0) |
| `tests/test_conformance.xi` | MIT OR Apache-2.0 (XIOM Authors) | 18 checks; fixtures generated in-suite (Radiance RGBE bytes, 1x1 gray BMP) |

## 3. Derived vs independent

- The bridge is **package-local** code (no upstream code copied beyond
  the vendored headers); it drives only the documented public stb API.
- The measured behaviours pinned in the suite (PNG 85 bytes, checksum
  8400, RGBE `ldexp(1, e-136)` scaling, `pow(f, 1/gamma) * 255 + 0.5`
  remap, LDR->float `pow(b/255, gamma) * scale`) are read from the
  vendored header's implementation and pinned as golden values; no
  upstream test vectors exist for these (stb ships none for 2.x).
- No test data files imported; every fixture is built byte-by-byte in the
  suite.

## 4. Re-carve procedure

1. `git -C E:\repos\stb fetch --depth 1 origin <new-pin>` and check out
   the commit; update the pin here + `SPEC.md` section 2.
2. Extract with `git cat-file blob <pin>:<path>` (NEVER the autocrlf
   worktree copy) and compare the new blob sha1s.
3. If the headers changed: re-copy into `vendor/`, refresh the SHA256
   table, re-run the suite x2, review whether the HDR surface table in
   `SPEC.md` section 4 changed (new public HDR entries are coverage
   obligations), record `STATUS.json`.
4. stb is header-only; there is no build system to port. Keep the
   clone until the CLEANUP review date (2026-12-01).
