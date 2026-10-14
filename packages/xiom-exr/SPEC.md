# SPEC: xiom.exr -- OpenEXR reader via vendored tinyexr

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.exr` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | tinyexr -- https://github.com/syoyo/tinyexr |
| Upstream version | tag **`v3.2.0`** = commit **`6f470c9ab24bf3992bc512ce07e8ecb00d9bf105`** |
| Upstream license | **BSD-3-Clause** (`vendor/tinyexr/LICENSE`); bundled miniz: MIT / public domain (`vendor/tinyexr/LICENSE-miniz`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); the vendored C++ is portable |
| Compiler pin | v0.64.4 (`--cxx-standard 17`) |

## 2. Vendored path (G2 pin + one mechanical rewrite)

Seven files are vendored from the pin by `tools/vendor_exr.py`
(binary-safe `git cat-file blob`; the clone worktree is autocrlf-converted,
so worktree copies are never trusted):

| Vendored file | Upstream path | Vendored SHA256 |
|---|---|---|
| `vendor/tinyexr/tinyexr.h` | `tinyexr.h` (**rewritten**) | `9969C3C992...` (see `vendor/FILES.sha256`) |
| `vendor/tinyexr/exr_reader.hh` | `exr_reader.hh` | `9E0BFEF048...` |
| `vendor/tinyexr/streamreader.hh` | `streamreader.hh` | `81F2D15029...` |
| `vendor/tinyexr/miniz.h` | `deps/miniz/miniz.h` | `295D1A0041...` |
| `vendor/tinyexr/miniz.c` | `deps/miniz/miniz.c` | `8756860E8A...` |
| `vendor/tinyexr/LICENSE` | `LICENSE` | `B90388AAAD...` |
| `vendor/tinyexr/LICENSE-miniz` | `deps/miniz/LICENSE` | `0115478D56...` |

**The one rewrite**: `#include <miniz.h>` -> `#include "miniz.h"` in
`tinyexr.h`. The toolchain has no `-I` flag for `--c-source` files, so the
angle include cannot resolve the vendored miniz; the quoted form resolves
relative to the vendored header's own directory. Exactly one occurrence is
asserted by the tool. `vendor/FILES.sha256` records the upstream blob sha1,
the raw upstream sha256, and the vendored sha256 per file. Drift guard:
`python tools/vendor_exr.py --check`.

## 3. Build model

- One C++ TU: `src/exr_bridge.cpp` (`TINYEXR_IMPLEMENTATION` +
  `TINYEXR_USE_MINIZ 1`) with a plain-C ABI.
- One C TU: `vendor/tinyexr/miniz.c`.
- Link list in `port.args.json` (`--cxx-standard 17`, internal
  `--timeout 600`); `scripts/port.ps1 -TimeoutSec 300+`.

## 4. Design and safe boundary (G5)

`exr.xi` is the only module with `unsafe`/`extern "C"`. The bridge keeps
ONE loaded image (session) and ONE saved buffer C-side; XIOM never sees a
tinyexr pointer:

1. `exr_load_from_memory` / `exr_load_from_file` parse version + header +
   image into the session; HALF channels request FLOAT data (tinyexr's own
   half->float conversion); UINT channels stay UINT for the loader.
2. `exr_take_image` copies metadata (dimensions, compression, data window,
   per-channel declared types and names) and the pixel planes into owned
   XIOM slots: one `Vec[UInt8]` for all planes (channel-major, float32
   little-endian; UINT data is widened by the bridge inside `memcpy`
   territory), one push-growth buffer per channel name.
3. `exrprobe_release()` frees the session after every load; the save path
   caches the last writer output for one copy-out and is released the same
   way.

Discipline: B-11 (one owned slot per out-param), B-17 (no pointer
arithmetic on the XIOM side), B-20/B-24 (no foreign-pointer reads; names
are copied into owned buffers before `Str::from_c_str`), B-25 (no handle
casts), B-26 (flat `Result[_, ExrError]`; no nested enum payloads), B-27
(no `ffi.write_*_at`; the save spec is length-validated, not patched), B-28
(`Vec.push` growth; never `with_len`), B-02/B-03 (`exr_error_name` uses
literals).

## 5. Declared surface (100% documented)

| # | Declared item | tinyexr entry | Package binding | Status |
|---|---|---|---|---|
| 1 | read from memory | `ParseEXRVersionFromMemory` + `ParseEXRHeaderFromMemory` + `LoadEXRImageFromMemory` | `exr_load_from_memory(bytes)` | bound + tested |
| 2 | read from file | `ParseEXRVersionFromFile` + `ParseEXRHeaderFromFile` + `LoadEXRImageFromFile` | `exr_load_from_file(path)` | bound + tested |
| 3 | detect (memory) | `IsEXRFromMemory` | `exr_is_exr_from_memory(bytes)` | bound + tested |
| 4 | detect (file) | `IsEXR` | `exr_is_exr_from_file(path)` | bound + tested |
| 5 | dimensions | `EXRImage.width/height` | `ExrImage.width/height` | tested |
| 6 | channel count | `EXRImage.num_channels` | `ExrImage.channels`, `names.len()` | tested |
| 7 | channel names | `EXRChannelInfo.name` | `ExrImage.names` + `exr_channel_index` | tested |
| 8 | pixel types (declared) | `EXRChannelInfo.pixel_type` | `ExrImage.pixel_types` + `EXR_PIXELTYPE_*` | tested |
| 9 | compression | `EXRHeader.compression_type` | `ExrImage.compression` + `EXR_COMPRESSION_*` | tested |
| 10 | data window | `EXRHeader.data_window` | `ExrImage.window_min_x..window_max_y` | tested |
| 11 | owned float channel buffers | loaded `EXRImage.images` (float) | `ExrImage.data` planar f32 LE + `exr_pixel_f64` | tested |
| 12 | save to memory | `SaveEXRImageToMemory` (incl. HALF output) | `exr_save_to_memory(spec)` | bound + tested |
| 13 | typed errors | tinyexr error codes + messages | `Result[_, ExrError]`, `exr_error_name`, `EXR_ERROR_*` | tested |

Constants exposed (from the pinned header): `EXR_ERROR_*` (15),
`EXR_PIXELTYPE_UINT/HALF/FLOAT`, `EXR_COMPRESSION_NONE/RLE/ZIPS/ZIP/PIZ/
PXR24/B44/B44A/DWAA/DWAB`, `EXR_TILE_ONE_LEVEL/MIPMAP_LEVELS/
RIPMAP_LEVELS/ROUND_DOWN/ROUND_UP`, `EXR_MAX_HEADER_ATTRIBUTES` (1024),
`EXR_MAX_CUSTOM_ATTRIBUTES` (128), `EXR_MAX_CHANNELS` (bridge bound, 32).

Explicit non-goals (documented, not gaps): tiled / multipart / deep
images (the declared reader is single-part scanline), `LoadEXR` /
`LoadEXRWithLayer` RGBA convenience wrappers, `EXRLayers`, `EXRNumLevels`,
custom-attribute enumeration, file writing (`SaveEXRImageToFile`),
ZFP-compressed files (upstream default keeps `TINYEXR_USE_ZFP 0`).

## 6. Test contract

Suite: `tests/test_conformance.xi` -- 12 checks: constant pins + typed
error names; save fp32/is_exr; exact 3x2x3 read (18 values, name lookup,
declared types); metadata (compression NONE + data window); save
determinism; fp16 round trip (declared HALF, exact values); file entries +
missing path typed error; 4-channel RGBA alpha plane; garbage ->
`INVALID_MAGIC_NUMBER`; truncated -> `INVALID_DATA`; save-spec validation;
load determinism.

```
scripts/port.ps1 -Package xiom.exr -TimeoutSec 300
```

Watchdog: >=300 s (two TUs, one a ~390 KB C++ header; ~40 s on the
development machine).

## 7. Scope

Reader-first: every declared read/metadata item plus the save path used
for fixtures and round trips. The suite builds every fixture through
tinyexr's own writer, so the reader is verified against the reference
writer, not hand-rolled bytes.
