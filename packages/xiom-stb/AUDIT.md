# AUDIT: xiom.stb

## Status (2026-10-10)

Vendored single-header implementation at 0.2.0. The pre-pilot module
(declaration-only bindings, no implementation -- the reason the name sat on
the allowlist's deliberately-excluded list) is preserved in git history.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.2 |
| Upstream | stb commit `2c980bb5...` (public domain / MIT) |
| Link model | one `--c-source` TU (`src/stb_all.c`) holding both implementations + the probe bridge |
| FFI confinement | all `unsafe`/`extern` in the root module `stb.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 5 checks (real encode/decode) |
| Runs | 5/5 x2 on the pin (PNG 85 bytes, checksum 8400, BMP 1x1 red) |
| Allowlist | **append requested** (xiom.stb was excluded as declaration-only; now real) |

## Design notes

- One TU carries `STB_IMAGE_IMPLEMENTATION` +
  `STB_IMAGE_WRITE_IMPLEMENTATION` and the `stbprobe_*` functions (the
  miniaudio method). The probe is C (plain linkage) with cached scalar
  results -- no out-param slots (B-11 family avoidance).
- The probe needs no external fixture: PNG is produced and consumed
  in-memory, and the BMP proof is a hardcoded 58-byte 1x1 red file.
- Deterministic values: encoded PNG = 85 bytes; decoded RGBA checksum =
  8400 (60/120/180/255 gradient); both asserted by the suite.
- `stb_image` freed with `stbi_image_free`; the encoder buffer with
  `STBIW_FREE` (its documented free).

## Known limitations

- Pilot surface: the probe only; typed `Image` wrappers and the wider
  format matrix (JPG/GIF/TGA animation, HDR) are Phase 2.
- `xiom.image` (pure XIOM BMP/PPM pipeline) stays the conversion home;
  this package adds the vendored codecs for PNG and friends.
- Windows x64 primary; the vendored C path is portable.
