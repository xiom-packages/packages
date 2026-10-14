# SPEC: xiom.stb -- stb image codecs (vendored stb_image + stb_image_write)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.stb` |
| Version | 0.3.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | stb -- https://github.com/nothings/stb |
| Upstream version | commit **`2c980bb59875b0d32144a71867fbdebb2f77cd20`** (2026-08-02) |
| Upstream license | dual **public domain / MIT** (stb's own grant, embedded at the end of each header) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); the vendored headers are portable C |
| Compiler pin | v0.64.4 |

## 2. Vendored path (G2 pin)

The two headers are vendored **unmodified** in `vendor/`; one TU
(`src/stb_all.c`, the miniaudio single-header method) carries
`STB_IMAGE_IMPLEMENTATION` + `STB_IMAGE_WRITE_IMPLEMENTATION` plus the
probe/HDR bridge. No system library, no SDK.

### Pinned headers

| Artifact | Canonical blob (git sha1 @ pin) | Checkout SHA256 |
|----------|-------------------------------|-----------------|
| `stb_image.h` | `9eedabedc45b3e6fd88fae6f14a160b4d53272ec` | `594C2FE35D49488B4382DBFAEC8F98366DEFCA819D916AC95BECF3E75F4200B3` |
| `stb_image_write.h` | `e4b32ed1bc32ef9c962acbf47a9d10af01939e08` | `CBD5F0AD7A9CF4468AFFB36354A1D233803F2C12473CF1A8E32053CB6914A05` |

The 2026-10-14 re-pin verification (`E:\repos\stb` at the pin) confirms the
vendored worktree bytes are byte-identical to the canonical git blobs
(`git hash-object --no-filters` matches). The clone's own checkout is
autocrlf-converted on Windows; a re-carve must extract with
`git cat-file blob`, never from the clone's worktree files.

Re-pin: fetch both headers at the new commit hash, verify the blob/sha256
identity, re-copy byte-for-byte, update this table + `PROVENANCE.md`/
`AUDIT.md`/`README.md`, re-run `scripts/port.ps1 -Package xiom.stb` x2,
record `STATUS.json`.

## 3. Design and safe boundary (G5)

`stb.xi` is the only module with `unsafe`/`extern "C"`. The bridge
(`src/stb_all.c`) exposes scalar getters and byte-slot copy-out functions
only. The probe (0.2.0) is self-contained; the HDR class layer (0.3.0)
adds one bridge-owned cached image:

1. every loader caches its decoded image C-side
   (`stbprobe_loadf_mem` / `_callbacks` / `_file` / `_from_file`,
   `stbprobe_load8_mem`);
2. the XIOM side allocates an owned slot of exactly
   `stbprobe_img_bytes()` bytes (push-growth; `Vec.with_len` is B-28-broken
   on the pin) and copies the pixels out byte-wise via
   `stbprobe_img_copy` -- native data never crosses back as a foreign
   pointer (B-20/B-24), one owned slot per out-param (B-11);
3. `stbprobe_img_release()` frees the cached image after every load.

The `*_from_callbacks` entries are driven by the bridge's own
memory-cursor `stbi_io_callbacks` set: arbitrary XIOM fn-params cannot
cross to C on the pin (B-13/B-22), so user callbacks are a documented
non-goal, while the entries themselves are bound and exercised.

## 4. Declared surface -- the HDR class (100%)

Every `.hdr`-related public entry of the vendored `stb_image.h` is bound:

| # | stb_image.h entry | Package binding | Status |
|---|-------------------|-----------------|--------|
| 1 | `stbi_is_hdr` | `stb_hdr_is(path)` | bound + tested |
| 2 | `stbi_is_hdr_from_memory` | `stb_hdr_is_from_memory(bytes)` | bound + tested |
| 3 | `stbi_is_hdr_from_callbacks` | `stb_hdr_is_from_callbacks(bytes)` | bound + tested |
| 4 | `stbi_is_hdr_from_file` | `stb_hdr_is_from_file(path)` (bridge FILE*) | bound + tested |
| 5 | `stbi_loadf` | `stb_loadf(path, desired)` | bound + tested |
| 6 | `stbi_loadf_from_memory` | `stb_loadf_from_memory(bytes, desired)` | bound + tested |
| 7 | `stbi_loadf_from_callbacks` | `stb_loadf_from_callbacks(bytes, desired)` | bound + tested |
| 8 | `stbi_loadf_from_file` | `stb_loadf_from_file(path, desired)` (bridge FILE*) | bound + tested |
| 9 | `stbi_hdr_to_ldr_gamma` | `stb_hdr_to_ldr_gamma(gamma)` | bound + tested |
| 10 | `stbi_hdr_to_ldr_scale` | `stb_hdr_to_ldr_scale(scale)` | bound + tested |
| 11 | `stbi_ldr_to_hdr_gamma` | `stb_ldr_to_hdr_gamma(gamma)` | bound + tested |
| 12 | `stbi_ldr_to_hdr_scale` | `stb_ldr_to_hdr_scale(scale)` | bound + tested |
| -- | `stbi_load_from_memory` (HDR->LDR remap witness) | `stb_load_rgba8_from_memory(bytes, desired)` | bound + tested |

Error surface: every fallible call returns `Result[_, StbError]` with
`code` in {`STB_ERR_LOAD`=1, `STB_ERR_ARG`=2, `STB_ERR_STATE`=3} and the
`stbi_failure_reason()` text as `message` (`stb_failure_reason()` exposes
it directly). Constants: `STBI_DEFAULT/GREY/GREY_ALPHA/RGB/RGB_ALPHA`
(the `req_comp` flags) and `STBI_MAX_DIMENSIONS` (16777216).

Exact value helpers: `stb_float32_from_bytes`, `stb_f32_at`,
`stb_pixel_f64` reconstruct every finite float32 pattern exactly as
Float64 without a bitcast intrinsic.

Explicit non-goals (Phase 3 in `ROADMAP.md`): `stbi_load`/
`stbi_load_from_file`/`stbi_load_from_callbacks` general LDR entries and
the LDR encoders (`stbi_write_*`); user-supplied XIOM `stbi_io_callbacks`.

## 5. Test contract

Suite: `tests/test_conformance.xi` -- 18 checks: `STBI_VERSION`, the PNG
probe (size, round trip, checksum, BMP, determinism), then the HDR class:
is_hdr classification, exact float values of the in-test 4x1 `.hdr`
fixture (generated byte-by-byte in the suite), RGBA request, callbacks
byte-identity, the four file entries on a temp fixture, the gamma=1/2
HDR->LDR byte-exact remaps, the LDR->HDR knobs on an in-test 1x1 gray BMP
(linear exact + scale doubling + gamma range check), the HDR->LDR remap
witness, three corrupt-input typed-error paths (garbage, bad FORMAT, bad
layout), a missing-file path, and load determinism.

```
scripts/port.ps1 -Package xiom.stb
```

Watchdog: >=240 s (one C TU; a few seconds on the development machine).

## 6. Scope

The codec pipeline end-to-end plus the complete HDR class surface. LDR
encode variants (JPG/GIF/TGA writers, flip/quality parameters) and typed
`Image` helpers are Phase 3 (`ROADMAP.md`); `xiom.image` remains the
pure-XIOM pipeline for BMP/PPM + conversions, and the two packages compose
(`stb_loadf_*` output feeds float pipelines; `stb_load_rgba8_*` feeds
`xiom.image`).
