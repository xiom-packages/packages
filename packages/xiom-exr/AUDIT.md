# AUDIT: xiom.exr

## Status (2026-10-14)

New package at 0.1.0: OpenEXR reader over vendored tinyexr v3.2.0.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.4 (`--cxx-standard 17`) |
| Upstream | tinyexr tag v3.2.0 = `6f470c9a...` (BSD-3; miniz MIT/public domain) |
| License verification | `vendor/tinyexr/LICENSE` + `LICENSE-miniz` vendored from the pin (BSD-3 / MIT text confirmed 2026-10-14) |
| Link model | one C++ TU (`src/exr_bridge.cpp`) + one C TU (`vendor/tinyexr/miniz.c`); `port.args.json` |
| FFI confinement | all `unsafe`/`extern` in the root module `exr.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 12 checks |
| Runs | 12/12 x2 on the pin |
| Clone | `E:\repos\tinyexr` (tag v3.2.0; CLEANUP row added; worktree autocrlf-converted -- re-carve via `git cat-file blob`) |

## Design notes

- The bridge uses only tinyexr's public extern "C" API (the C API IS
  present; no C++ classes cross TU boundaries) and owns one load session +
  one save buffer. XIOM never holds a tinyexr pointer: names and planes are
  copied into owned slots byte-wise (B-20/B-24), one owned slot per
  out-param (B-11).
- HALF channels load as FLOAT through tinyexr's own
  `requested_pixel_types` conversion; UINT channels stay UINT in the
  loader (tinyexr rejects FLOAT requests for them) and the bridge widens
  them to float32 during copy-out. `pixel_type` metadata always reports
  the DECLARED file type.
- One mechanical include rewrite (`<miniz.h>` -> `"miniz.h"`) is applied
  and recorded (SPEC section 2, `tools/vendor_exr.py`; the toolchain has
  no `-I` for `--c-source` files); every other byte is the upstream
  blob at the pin (`vendor/FILES.sha256`).
- The suite never hand-rolls an EXR byte stream: fixtures are produced by
  tinyexr's own `SaveEXRImageToMemory` (the reference writer), then read
  back -- writer/reader parity in one process.
- Corrupt paths verified against upstream behavior: garbage ->
  `INVALID_MAGIC_NUMBER`; truncation (8 or 24 bytes) -> `INVALID_DATA`
  ("Invalid/Corrupted data found when decoding pixels").

## Known limitations

- Single-part scanline images only (no tiled / multipart / deep); no
  custom-attribute enumeration; no ZFP (upstream default off).
- The bridge accepts up to `EXR_MAX_CHANNELS` (32) channels per save.
- `exrprobe_image_bytes` is int-sized: images whose planar float payload
  exceeds 2 GiB are rejected by the bridge's size checks (documented bound).
- NaN/Inf float patterns decode to 0 in the exact Float64 helper (finite
  values only; documented on the function).
- Windows x64 primary; the vendored C++ path is portable.
