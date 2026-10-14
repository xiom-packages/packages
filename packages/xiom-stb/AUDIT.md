# AUDIT: xiom.stb

## Status (2026-10-14)

Vendored single-header implementation at 0.3.0 with the full HDR class
surface. The pre-pilot module (declaration-only bindings, no
implementation) is preserved in git history.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.4 |
| Upstream | stb commit `2c980bb5...` (public domain / MIT); re-verified 2026-10-14, vendored blobs byte-identical |
| Link model | one `--c-source` TU (`src/stb_all.c`) holding both implementations + the probe/HDR bridge |
| FFI confinement | all `unsafe`/`extern` in the root module `stb.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 18 checks (probe + HDR class + corrupt paths) |
| Runs | 18/18 x2 on the pin (HDR fixture values exact; gamma remaps byte-exact) |
| Allowlist | allowlisted (row `xiom.stb`; 0.2.0 published in eco-v0.1.139) |

## Design notes

- One TU carries `STB_IMAGE_IMPLEMENTATION` +
  `STB_IMAGE_WRITE_IMPLEMENTATION`, the 0.2.0 probe, and the 0.3.0 HDR
  bridge (the miniaudio method).
- The HDR bridge caches one decoded image C-side and copies it into
  XIOM-owned slots byte-wise (`stbprobe_img_copy`): no foreign-pointer
  reads (B-20), one owned slot per out-param (B-11), no handle casts
  (B-25), no `Result[Option[_]]` (B-26).
- `*_from_callbacks` entries run on the bridge's own memory-cursor
  `stbi_io_callbacks`; XIOM fn-params cannot cross to C on the pin
  (B-13/B-22) -- documented non-goal in SPEC section 4.
- The HDR fixture is generated in-suite (Radiance RGBE, flat path,
  width 4 < 8); all decoded values are exact powers of two or small
  integers, so the checks are exact-equality, not tolerance-based.
- The LDR->HDR knobs are exercised through `stbi_loadf` on an in-suite
  1x1 gray-128 BMP (linear exactness + exact doubling + gamma range).
- `stb_float32_from_bytes` reconstructs finite float32 patterns exactly
  (integer mantissa math, no bitcast intrinsic and no foreign reads).

## Known limitations

- General LDR loaders (`stbi_load` family) beyond the HDR->LDR remap
  witness, and all `stbi_write_*` encoders, remain Phase 3 (ROADMAP).
- The `*_from_callbacks` entries do not accept user XIOM callbacks
  (compiler B-13/B-22); the bridge-provided memory cursor is the only
  callback source.
- `stb_float32_from_bytes` maps NaN/Inf patterns to 0 (finite values
  only); documented on the function.
- Windows x64 primary; the vendored C path is portable.
