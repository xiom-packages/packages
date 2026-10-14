# PROVENANCE: xiom.exr

## 1. Vendored upstream

| Field | Value |
|---|---|
| Project | tinyexr (single-header OpenEXR reader/writer + `exr_reader.hh` + `streamreader.hh`) |
| Repository | `https://github.com/syoyo/tinyexr` |
| Pin | tag **`v3.2.0`** = commit **`6f470c9ab24bf3992bc512ce07e8ecb00d9bf105`** |
| Licence | **BSD-3-Clause** (`LICENSE`); bundled `deps/miniz` is MIT / public domain (`deps/miniz/LICENSE`) |
| Clone verified | `E:\repos\tinyexr` (2026-10-14; fetch `--depth 1` + tags); `git rev-parse v3.2.0^{commit}` == pin |
| Extraction | `tools/vendor_exr.py` via binary-safe `git cat-file blob` (the clone worktree is autocrlf-converted on Windows) |
| Transform | EXACTLY ONE mechanical include rewrite in `tinyexr.h`: `#include <miniz.h>` -> `#include "miniz.h"` (needed because the toolchain passes no `-I` for `--c-source` files; quoted includes resolve next to the vendored header). The tool asserts exactly one occurrence; every other byte is upstream. |
| Manifest | `vendor/FILES.sha256` (upstream blob sha1, raw upstream sha256, vendored sha256, size per file) |
| Drift guard | `python tools/vendor_exr.py --check` re-extracts and byte-compares without writing |

Vendored pin at 2026-10-14:

| File | Upstream blob sha1 | Vendored sha256 |
|---|---|---|
| `tinyexr.h` (rewritten) | `7a3948d10736659c12a9e2216ecb96800cfaf810` | `9969C3C992...` (full value in `vendor/FILES.sha256`) |
| `exr_reader.hh` | `8ea0d666fd87a4873e0bf15f6b60c7b9ee979d1f` | `9E0BFEF048...` |
| `streamreader.hh` | `3dbf278b37f588fe75e60beaf634b0171254063d` | `81F2D15029...` |
| `miniz.h` | `9fcfffcc8cd7ac9e9d9af271cffdbc8d0a58a9ea` | `295D1A0041...` |
| `miniz.c` | `fb674701e4ca3721fce332641a81950656844ef8` | `8756860E8A...` |
| `LICENSE` | `d89add6035dec9702111554125242da1add8a8a9` | `B90388AAAD...` |
| `deps/miniz/LICENSE` | `1982f4bb8f4afa3dcbe803887fb4af7573430e51` | `0115478D56...` |

Note: `tinyexr.h` at v3.2.0 is byte-identical to the master tip observed
2026-10-14 (`1fd840b9`); the tag is the pin because it is a stable release.

## 2. Package-local code

| Path | Licence | Notes |
|---|---|---|
| `exr.xi` | MIT OR Apache-2.0 (XIOM Authors) | declared reader surface + typed errors + exact f32->f64 helper |
| `src/exr_bridge.cpp` | MIT OR Apache-2.0 (XIOM Authors) | C-ABI bridge over tinyexr's public C API; owns the load session + save buffer; all copy-out |
| `tools/vendor_exr.py` | MIT OR Apache-2.0 (XIOM Authors) | pin extraction + include rewrite + manifest + drift guard |
| `tests/test_conformance.xi` | MIT OR Apache-2.0 (XIOM Authors) | 12 checks; fixtures built through tinyexr's own writer |

## 3. Derived vs independent

- No upstream code is copied outside `vendor/`; the bridge only calls the
  documented public API (`ParseEXR*`, `LoadEXRImage*`, `SaveEXRImageToMemory`,
  `IsEXR*`, `Init*`, `Free*`).
- No test data files are imported: every fixture is generated in-suite by
  the vendored writer, then read back (writer/reader parity).
- Measured behaviors pinned in the suite: garbage -> `INVALID_MAGIC_NUMBER`
  (-1); truncated by 8/24 bytes -> `INVALID_DATA` (-4) with
  "Invalid/Corrupted data found when decoding pixels."; HALF/FLOAT declaration
  preserved; NONE compression + data-window metadata for the writer output.

## 4. Re-carve procedure

1. `git -C E:\repos\tinyexr fetch --tags` and check out the new tag;
   update `PIN` in `tools/vendor_exr.py` + this file + `SPEC.md` section 1-2.
2. Run `python tools/vendor_exr.py` (writes + manifest), review the diff of
   `vendor/FILES.sha256`, then `python tools/vendor_exr.py --check`.
3. If the upstream include set changed (new sibling headers), update the
   `FILES` map and the `.gitattributes`/link list accordingly.
4. Re-run the suite x2, review whether the declared-surface table in
   `SPEC.md` section 5 needs new rows, record `STATUS.json`.
5. Keep `E:\repos\tinyexr` until the CLEANUP review date (2026-12-01).
