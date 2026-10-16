# SPEC: xiom.brotli -- real RFC 7932 brotli bindings (vendored google/brotli)

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.brotli` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Brotli -- https://github.com/google/brotli |
| Upstream version pinned | **v1.2.0** -- commit `028fb5a23661f123017c060daa546b55cf4bde29` (2025-10-27; latest stable release) |
| Upstream license | MIT (Copyright (c) 2009, 2010, 2013-2016 by the Brotli Authors; `vendor/brotli/LICENSE`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (no platform-specific XIOM code) |
| Compiler pin | v0.64.5 |
| Modules | `xiom.brotli` (declared in `package.xi`) |
| Purpose | real RFC 7932 streams (`Content-Encoding: br`) -- NOT the stdlib's partial `xiom.compress.brotli` framing |

## 2. Vendored path (G2 pin)

The upstream C sources are vendored into `vendor/brotli/` (BSD/MIT-family
vendored tree; see `PROVENANCE.md`) and compiled into the test binary via
`--c-source` (no system library, no runtime DLL, no dl-load).

Vendored layout (upstream `c/` level stripped; everything else identical):

```
vendor/brotli/LICENSE
vendor/brotli/include/brotli/{port,types,shared_dictionary,decode,encode}.h
vendor/brotli/common/*.c,*.h     (dictionary rebuild inputs not vendored)
vendor/brotli/dec/*.c,*.h
vendor/brotli/enc/*.c,*.h        (the experimental *.cc static-init not vendored)
```

| Artifact | Value |
|----------|-------|
| Vendored tree | 107 files, sha256 digest (sorted `relpath:sha256` lines, LF) `C3D54D20A17A3AF26BE29CC4E8EF15AC5CA72C1614173788CBBEE8852E23C642` |
| Delta vs upstream | **exactly 24 lines** in **16 files** (one mechanical angle-include rewrite, below); all other bytes identical; LF-normalized (Windows checkout) |
| Generation/verification tool | `tools/gen_brotli.py` (`--write`, `--verify`, `--print-tree`); fails unless the rewrite count is exactly 24 |
| Upstream blob verification | done against `git archive` bytes of the pin (raw blobs, not the autocrlf-converted worktree) on 2026-10-16: `--verify` OK |

### The one mechanical rewrite

The xiom `--c-source` link line adds no `-I` include path, so angle includes
of the public headers cannot resolve. Each

```
#include <brotli/NAME.h>
```

is rewritten to a relative quoted include:

| File location | Rewritten to |
|---------------|--------------|
| `include/brotli/*` (public headers) | `#include "NAME.h"` (same directory) |
| `common/`, `dec/`, `enc/` | `#include "../include/brotli/NAME.h"` |

All other include forms (quoted relative includes, system headers) are
untouched. Same class of documented vendor normalization as `xiom.exr`
(`<miniz.h>` -> `"miniz.h"`) and `xiom.openpgl` (include rewrite + LF).

### Public header pin (SHA256)

| Header | Vendored (post-rewrite, LF) | Upstream raw blob @ pin |
|--------|------------------------------|--------------------------|
| `include/brotli/port.h` | `72B484D7A2561F3A9AD35EBD0D4F97F7A2D9863B619782ADA5B083A4B6F40DF5` | identical |
| `include/brotli/types.h` | `EBBD136DC411CC8167636D6F54B66AD0C234DC18989265C37A28C242EAAE2EFD` | identical |
| `include/brotli/shared_dictionary.h` | `47C0D9C543E124C14E2062B2210036FE5745CD3199055810B762479515B60FED` | `86230F0AAF533044D85D92F84B5AEC8B7E4E231D4B64B098604083E7866E8097` |
| `include/brotli/decode.h` | `A5BDEDE1D50951D65D5D4DBD8DAFDBF19B6AA94B004EBB2C12104BE61CBE8E9C` | `027B91E62E85DE6955E6334628B2BA0C77901A449E169FD9F95D6EA1CC91F980` |
| `include/brotli/encode.h` | `1BF3216E1F956334AC2E605884E783A1F0D87FB91D528B8FCE7DED85D989ED4C` | `F1842E38DA557EFAC517A35F1B27D288D464A723EF50316D3D20FE03F6046C06` |
| `LICENSE` | `3D180008E36922A4E8DAEC11C34C7AF264FED5962D07924AEA928C38E8663C94` | identical |

Per-file hashes for the whole tree: `python tools/gen_brotli.py --print-tree`.

### Re-pin procedure

1. Update the study clone (`E:\repos\brotli`) to the new tag; verify `LICENSE`.
2. Run `python tools/gen_brotli.py --write --clone <clone>`; if the
   angle-include count changed, re-bless `EXPECTED_REWRITES` (documented
   delta) in the same commit.
3. Run `--verify` against the `git archive` bytes of the new pin.
4. Refresh the tables above (tree digest, header hashes), `README.md`,
   `AUDIT.md`, `PROVENANCE.md`; re-run the suite x2 and record in
   `STATUS.json`.

### Build shim

`port.args.json` compiles, in one clang invocation:

* `src/brotli_bridge.c` (our code: the NULL/pointer-cursor/foreign-copy
  helpers XIOM cannot express, see section 3), and
* the **35 vendored translation units** -- exactly the upstream CMake
  default set (`c/common/*.c`, `c/dec/*.c`, `c/enc/*.c`).

pinned flags: `--opt-level 0` (port-time link speed; the C code is
correctness-neutral across optimization levels, and the suite exercises the
real codec paths) and `--timeout 1800` (35 upstream units + the runtime at
link time; use `-TimeoutSec 2400` at the runner).

## 3. Design and safe boundary (G5)

| Module | File | Role |
|--------|------|------|
| `xiom.brotli` | `brotli.xi` | The only module with `extern "C"`: raw declarations + every safe wrapper + the pure-XIOM HTTP helpers |
| bridge | `src/brotli_bridge.c` | NULL-allocator creation, stream pointer cursors, size_t in/out slots, foreign-pointer copies (`TakeOutput`, error strings), sign-correct error codes |

ABI/discipline notes (lane findings B-11..B-32):

* handles are opaque `Int` values produced by the bridge (never
  `x as *UInt8`; the bridge casts to the pointer type);
* out-params are dedicated owned `Vec[UInt8]` slots read byte-indexed
  little-endian (one slot per out-param); `BrotliDecoderGetErrorCode` goes
  through the bridge as `int64_t` so negative codes keep their sign;
* no bare `null` reaches C -- creation uses `BrotliDecoderCreateInstance(NULL,
  NULL, NULL)` / `BrotliEncoderCreateInstance(NULL, NULL, NULL)` inside the
  bridge;
* streaming cursors (`const uint8_t**`, `uint8_t**`) and all pointer
  arithmetic live in C; XIOM passes `(buffer, len, offset)`;
* `BrotliEncoderTakeOutput`'s foreign pointer and
  `BrotliDecoderErrorString`'s `const char*` are copied into owned buffers
  in C -- XIOM never reads a foreign pointer;
* owned buffers are push-growth (`_br_zeros`; never `Vec.with_len`, B-28);
* flat outcome structs only -- no `Result[Option[T]]` (B-26).

## 4. Declared surface (100% bound)

The declared C surface is **16 upstream functions** from the pinned public
headers; every one has a safe wrapper (16/16; 0 skips). Everything else in
`decode.h`/`encode.h` is an explicit non-goal (section 7).

| # | Upstream (pinned header) | Binding path | Public wrapper |
|---|--------------------------|--------------|----------------|
| 1 | `BrotliDecoderCreateInstance` | bridge `xb_decoder_create` (NULL allocators) | `brotli_decoder_new` |
| 2 | `BrotliDecoderDecompressStream` | bridge `xb_decoder_stream` (cursors + slots) | `brotli_decoder_push` / `brotli_decompress` / `brotli_decompress_auto` |
| 3 | `BrotliDecoderDecompress` | bridge `xb_decoder_decompress_oneshot` (size_t in/out) | `brotli_decompress_oneshot` |
| 4 | `BrotliDecoderDestroyInstance` | direct extern | `brotli_decoder_destroy` |
| 5 | `BrotliDecoderGetErrorCode` | bridge `xb_decoder_error_code` (int64 sign) | `brotli_decoder_error_code` |
| 6 | `BrotliDecoderErrorString` | bridge `xb_decoder_error_string` (copy) | `brotli_decoder_error_string` |
| 7 | `BrotliDecoderVersion` | direct extern | `brotli_decoder_version` (+ `brotli_version`) |
| 8 | `BrotliEncoderCreateInstance` | bridge `xb_encoder_create` (NULL allocators + 3 params) | `brotli_encoder_new` |
| 9 | `BrotliEncoderCompress` | bridge `xb_encoder_compress_oneshot` (size_t in/out) | `brotli_compress` |
| 10 | `BrotliEncoderCompressStream` | bridge `xb_encoder_stream` (cursors + slots) | `brotli_encoder_push` |
| 11 | `BrotliEncoderSetParameter` | direct extern | `brotli_encoder_set_parameter` |
| 12 | `BrotliEncoderTakeOutput` | bridge `xb_encoder_take_output` (copy) | `brotli_encoder_take_output` |
| 13 | `BrotliEncoderIsFinished` | direct extern | `brotli_encoder_is_finished` |
| 14 | `BrotliEncoderMaxCompressedSize` | direct extern | `brotli_compress_bound` |
| 15 | `BrotliEncoderDestroyInstance` | direct extern | `brotli_encoder_destroy` |
| 16 | `BrotliEncoderVersion` | direct extern | `brotli_encoder_version` |

Constant coverage (full enums, values from the pinned headers):
`BrotliDecoderResult` (4), `BrotliDecoderErrorCode` (30: 0..3, -1..-16,
-18..-20, -21/-22/-25/-26/-27/-30/-31; the reserved gaps stay gaps),
`BrotliEncoderMode` (3), `BrotliEncoderParameter` (10),
`BrotliEncoderOperation` (4), plus the documented ranges/defaults
(`BROTLI_MIN/MAX_QUALITY`, `BROTLI_MIN/MAX_WINDOW_BITS`,
`BROTLI_LARGE_MAX_WINDOW_BITS`, `BROTLI_MIN/MAX_INPUT_BLOCK_BITS`,
`BROTLI_DEFAULT_QUALITY/WINDOW/MODE`).

## 5. Error catalog (typed; never a crash)

| Error (`Result[_, Str]`) | Raised by |
|--------------------------|-----------|
| `brotli.decoder: invalid session` | `brotli_decoder_push` with handle 0 |
| `brotli.decoder: empty input` | all decode wrappers with a zero-length source |
| `brotli.decoder: source offset out of range` | offset outside `[0, len]` |
| `brotli.decoder: create failed` | session allocation failure |
| `brotli.decoder: corrupt stream (<upstream error string>)` | `brotli_decompress`/`_auto`, decoder ERROR result (e.g. `_ERROR_FORMAT_EXUBERANT_NIBBLE`) |
| `brotli.decoder: truncated stream` | input exhausted while the decoder needs more |
| `brotli.decoder: output exceeds capacity` | bounded decode over `out_capacity` |
| `brotli.decoder: one-shot decompress failed (corrupt input or insufficient output capacity)` | `brotli_decompress_oneshot` (the upstream one-shot cannot distinguish the two) |
| `brotli.encoder: invalid quality` / `invalid lgwin` / `invalid mode` | range validation (quality 0..11, lgwin 10..24, mode 0..2) |
| `brotli.encoder: create failed` | session allocation/parameter failure |
| `brotli.encoder: invalid session` | `brotli_encoder_push`/`take_output` with handle 0 |
| `brotli.encoder: source offset out of range` | offset outside `[0, len]` |
| `brotli.encoder: invalid operation` | op outside `BROTLI_OPERATION_*` |
| `brotli.encoder: compress stream failed` | upstream returned BROTLI_FALSE |
| `brotli.encoder: max_take must be positive` | `brotli_encoder_take_output` with `max_take < 1` |

Upstream v1.2.0 note: `BrotliEncoderSetParameter` stores out-of-range
quality/lgwin/mode values without complaint, so range validation is enforced
by the wrapper (the pinned headers' documented ranges) before any session is
created.

## 6. Test matrix

| Configuration | Command | Result |
|---------------|---------|--------|
| Vendored brotli v1.2.0 (0.1.0) | `scripts/port.ps1 -Package xiom.brotli -TimeoutSec 2400` | **PASS 26/26 x2 on compiler v0.64.5** -- see below |

Suite (`tests/test_conformance.xi`, 26 checks): version pin (decoder ==
encoder == 1.2.0), compress bound (1006/2, negative-is-0), round trips
across **quality 0..11** on 16 KiB text, real ratio (16384 -> 75 at q11),
binary LCG noise, 1-byte and 0-byte inputs, 128 KiB large input, **8
upstream golden vectors decoded byte-identically** (imported from the pinned
clone's `tests/testdata`), the literal one-shot decoder against a vector,
the raw progress contract (consumed/written), **chunked streaming decode**
(333-byte input steps + 7-byte output chunks), **streaming encode byte-equal
to one-shot** and a `TakeOutput` drain run, typed corrupt/truncated/oversize
errors (exact strings; never a crash), parameter and 0-handle misuse,
upstream error-string mapping, and the RFC 9110 `Content-Encoding: br`
helpers.

## 7. Scope

Delivered: the full declared decoder + encoder surface above (one-shot and
streaming, parameter control, TakeOutput/IsFinished), upstream error codes
and strings, and the HTTP content-coding helpers.

Out of scope at 0.1.0 (explicit non-goals, not silent gaps): custom
dictionaries (`BrotliDecoderAttachDictionary`,
`BrotliEncoderPrepareDictionary`, `BrotliEncoderAttachPreparedDictionary`,
`BrotliEncoderGetPreparedDictionarySize`), `BrotliDecoderSetParameter`
(ring-buffer/large-window decoder flags), `BrotliDecoderTakeOutput`,
`BrotliDecoderHasMoreOutput`, `BrotliDecoderIsUsed`,
`BrotliDecoderIsFinished`, metadata callbacks, Large-Window Brotli streams
(lgwin > 24), `BrotliEncoderEstimatePeakMemoryUsage`, the C++ API, and the
CLI (`c/tools`) -- see `ROADMAP.md` phase 2.
