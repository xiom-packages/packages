# SPEC: xiom.stb -- stb image codecs (vendored stb_image + stb_image_write)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.stb` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | stb -- https://github.com/nothings/stb |
| Upstream version | commit **`2c980bb59875b0d32144a71867fbdebb2f77cd20`** (2026-08-02) |
| Upstream license | dual **public domain / MIT** (stb's own grant, embedded at the end of each header) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); the vendored headers are portable C |
| Compiler pin | v0.64.2 |

## 2. Vendored path (G2 pin)

The two headers are vendored **unmodified** in `vendor/`; one TU
(`src/stb_all.c`, the miniaudio single-header method) carries
`STB_IMAGE_IMPLEMENTATION` + `STB_IMAGE_WRITE_IMPLEMENTATION` plus the
probe bridge. No system library, no SDK.

### Pinned headers

| Artifact | Size | SHA256 |
|----------|------|--------|
| `stb_image.h` | 283,010 B | `594C2FE35D49488B4382DBFAEC8F98366DEFCA819D916AC95BECF3E75F4200B3` |
| `stb_image_write.h` | 71,221 B | `CBD5F0AD7A9CF4468AFFB36354A1D2338034F2C12473CF1A8E32053CB6914A05` |

Re-pin: fetch both headers at the new commit hash, verify the sizes/hashes,
re-copy byte-for-byte, update this table + `README.md`/`AUDIT.md`, re-run
`scripts/port.ps1 -Package xiom.stb` x2, record `STATUS.json`.

## 3. Design and safe boundary (G5)

`stb.xi` is the only module with `unsafe`/`extern "C"`. The bridge exposes
scalar getters only (no out-param slots; B-11 family avoidance). The probe
is self-contained and allocation-lean:

1. builds a 4x4 RGBA gradient in memory;
2. encodes it to PNG with `stbi_write_png_to_mem`;
3. decodes the PNG with `stbi_load_from_memory(req_comp=4)`, verifies
   dimensions, every pixel, and the checksum (deterministic: 8400);
4. decodes a hardcoded 1x1 24-bit BMP (red) and checks dims/channels/pixel;
5. frees everything (encoder buffer via `STBIW_FREE`, decoded images via
   `stbi_image_free`).

There is no SKIP path -- the codecs always compile in.

## 4. Test contract

Suite: `tests/test_conformance.xi` -- 5 checks: `STBI_VERSION`, PNG encode
> 0 bytes + round-trip, decoded checksum == 8400, BMP decode (1x1 red),
repeated-probe determinism.

```
scripts/port.ps1 -Package xiom.stb
```

Watchdog: >=180 s (one C TU; a few seconds on the development machine).

## 5. Scope

Pilot: the codec pipeline end-to-end (PNG write+read, BMP read, in memory).
Typed XIOM wrappers (`Image` decode/encode helpers, file paths, error
strings, PNG/JPG/GIF/TGA encoding variants, HDR) are Phase 2
(`ROADMAP.md`); `xiom.image` remains the pure-XIOM pipeline for
BMP/PPM + conversions, and the two packages compose. The pre-pilot
declaration-only module is preserved in git history.
