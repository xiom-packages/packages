# SPEC: xiom.lz4 -- LZ4 (block, HC, frame) bindings

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.lz4` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | LZ4 -- https://github.com/lz4/lz4 |
| Upstream pin | tag **v1.10.0** = `ebb370ca83af193212df4dcbadcc5d87bc0de2f0` |
| Upstream license | BSD-2-Clause (`lib/`; `vendor/lz4/LICENSE`); the GPL-2.0 root material is not vendored |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (no platform-specific XIOM code) |
| Compiler pin | v0.64.4 |

## 2. Vendored path (G2 pin)

`vendor/lz4/` holds the eleven `lib/` files at the pin (lz4.c/h, lz4hc.c/h,
lz4frame.c/h, lz4frame_static.h, xxhash.c/h, LICENSE, README.md); every file
is byte-pinned (PROVENANCE.md + `.gitattributes vendor/** -text`).  The four
`.c` files plus `src/lz4_bridge.c` compile into the test binary via
`port.args.json` -- no system library, no runtime DLL, no network.

## 3. Design and safe boundary (G5)

| Module | File | Role |
|--------|------|------|
| `xiom.lz4` | `src/lz4.xi` | facade: constants, `Lz4Error`, frame slot helpers, one-shot helpers (no `unsafe`) |
| `xiom.lz4.ffi` | `src/lz4_ffi.xi` | the ONLY module with `extern "C"`; **complete 1:1 surface** (111 functions, generated, fail-closed verified) |
| bridge | `src/lz4_bridge.c` | null pointer, string copies, LZ4F struct-slot helpers, CustomMem-by-value creators, one decompression loop (our code, MIT OR Apache-2.0) |

Toolchain v0.64.4 discipline (docs/BINDINGS-COMPILER-FINDINGS.md), all
verified empirically during this wave:

- **Opaque handles cross as `Int`** (stream/context pointers); never
  `Int as *UInt8` (B-25).
- **Pointer values never round-trip through XIOM.**  A non-null pointer
  returned from a C call and then passed back arrives corrupted (measured:
  `LZ4F_compressFrameBound` returned a wrapped ~7e9 value for a valid prefs
  slot); only `.as_mut_ptr()` materialized at the call site, and NULL produced
  by C (`xlz4_null`, B-23), are address-faithful.  Consequence: nullable
  parameters are surfaced as owned byte slots (`&mut Vec[UInt8]`, zeroed =
  upstream defaults), not as pointer values.
- **C `int` returns cross as `Int32` and are sign-extended in the wrapper**:
  declaring them as `Int` zero-extends, so every negative error code appears
  as a ~2^32 positive value (verified).
- Struct parameters are caller-owned byte slots built/read by bridge helpers;
  in/out counts are slot-based; no pointer arithmetic in XIOM
  (B-17/B-20/B-24).

## 4. Frame struct slots

| Slot | Bytes | Constant | Helpers (xiom.lz4.ffi) |
|------|-------|----------|------------------------|
| `LZ4F_frameInfo_t` | 32 | `LZ4F_FRAME_INFO_BYTES` | `frame_info_default`, `frame_info_get` |
| `LZ4F_preferences_t` | 56 | `LZ4F_PREFERENCES_BYTES` | `prefs_default`, `prefs_set`, `prefs_get` |
| `LZ4F_compressOptions_t` | 16 | `LZ4F_COMPRESS_OPTIONS_BYTES` | `compress_options_default/_set` |
| `LZ4F_decompressOptions_t` | 16 | `LZ4F_DECOMPRESS_OPTIONS_BYTES` | `decompress_options_default/_set` |
| `LZ4F_CustomMem` | 32 | `LZ4F_CUSTOM_MEM_BYTES` | `custom_mem_default` |

Sizes are pinned by `static_assert`s in the bridge (a mismatch fails the
build, not the test).  A zeroed slot is the upstream default for every
struct (`contentSize == 0` means "unknown", identical to NULL prefs).

## 5. Error model

- Block/HC codecs return `int`: negative = failure (`lz4_block_error`,
  messages documented as "corrupt/truncated input or output capacity too
  small").
- Frame codecs return `size_t` / `LZ4F_errorCode_t`: `lz4f_is_error(code)`,
  `lz4f_error(code)` and `lz4f_error_message(code)` (bridge-copied
  `LZ4F_getErrorName` text).  `lz4f_get_error_code(code)` maps back to the
  `LZ4F_ERROR_*` enum constants exposed by the facade.
- `lz4f_decompress` (facade) and `ffi.lz4f_decompress_all` (bridge loop)
  decode exactly one complete frame from a buffer: truncated input reports a
  typed error (`ERROR_frameHeader_incomplete` / `ERROR_decompressionFailed`),
  a full destination reports `ERROR_dstMaxSize_tooSmall`.
- Block format carries no checksum (by design): corrupted blocks may decode
  to different bytes; frame content/block checksums are the integrity layer
  (test asserts `ERROR_contentChecksum_invalid` exactly).

## 6. Coverage (100% of the declared surface)

`docs/COVERAGE.md` / `docs/surface_lz4.json`, generated fail-closed by
`python tools/gen_lz4_ffi.py` from the pinned headers:

- **111 declared functions**: 66 stable, 34 deprecated (obsolete sections,
  bound for completeness with `legacy_`-disambiguated names where needed),
  11 static-linking-only (`LZ4_STATIC_LINKING_ONLY` sections; symbols exist
  in the static build, no upstream ABI-stability promise).
- 109/111 are exercised by the conformance suite; the two
  `*_withPrefix64k` obsolete entries are bound but not called (see sec. 7).
- Version 1.10.0 of `lib/` (note: the wave prep doc referenced v1.9.4; the
  task specified "latest stable release tag", which is v1.10.0).

## 7. Test matrix (recorded 2026-10-13, compiler v0.64.4)

`scripts/port.ps1 -Package xiom.lz4 -TimeoutSec 600` -- **81/81 PASS x2**
(counts and commit in STATUS.json), plus one deliberate `[SKIP]`:

- block: compressible/incompressible/empty round trips, ratio bound,
  `compressBound`, `decompress_safe_partial`, `compress_destSize`
  (62/1000 bytes consumed for a 64-byte target), destination-too-small,
  1-byte truncation, invalid 0xFF stream, flipped-bit detection;
- state: `sizeofState` (16416), `initStream`, `compress_fast_extState`,
  `_fastReset`, obsolete `resetStream`, `compress_destSize_extState`;
- streaming: linked-block continue + stream decode, dictionaries
  (`loadDict`/`loadDictSlow`/`saveDict`/`attach_dictionary`/
  `setStreamDecode`), partial-with-dict;
- HC: levels 2..12, monotone ratio, streaming continue with prefix decode,
  dict/attach, extState + fastReset + destSize variants,
  `setCompressionLevel`, `favorDecompressionSpeed`;
- deprecated block + HC: every obsolete entry called and round-tripped where
  safe (`decompress_fast` returns the consumed size; the two
  `*_withPrefix64k` entries are `[SKIP]`: their documented precondition -- a
  64 KB dictionary immediately before `dstBuffer` -- cannot be expressed
  through XIOM-owned buffers without pointer arithmetic, B-17);
- frame: one-shot (magic, header size 7/15, frameInfo, content size), checksum
  corruption -> exact `ERROR_contentChecksum_invalid`, 1 MB independent-block
  frame with block checksums (300 KB round trip), truncated frame typed error,
  streaming begin/update/flush/end (buffered + autoFlush), 1:1 decompress,
  `resetDecompressionContext`, dict/CDict paths (incl.
  `compressFrame_usingCDict`, `compressBegin_usingCDict`),
  `uncompressedUpdate`, static helpers (`getBlockSize`, `getErrorCode`) and
  the three CustomMem advanced creators.

## 8. Re-pin procedure

1. Fetch the new tag into `E:\repos\lz4` (`core.autocrlf=false` so vendor
   bytes are LF).
2. Replace `vendor/lz4/*`, recompute the PROVENANCE table.
3. Re-run `python tools/gen_lz4_ffi.py` (regenerates `src/lz4_ffi.xi`,
   `docs/COVERAGE.md`, `docs/surface_lz4.json`; fails closed if a new
   declaration is unmapped or a name collides).
4. Re-run the suite x2 and record; update PROVENANCE/SPEC/README in the same
   commit.

## 9. Non-goals

- `lz4file.h` (stdio file API, `LZ4F_readOpen` etc.): not part of the three
  target headers; file I/O stays with XIOM (the vendored header is present
  only for pin fidelity).
- `xxhash.h` public API: vendored only as lz4frame's internal dependency;
  not bound (no XXH_* exports promised).
- Custom allocator *callbacks* (nonzero `LZ4F_CustomMem` function pointers):
  the struct slot is bound and zeroed slots select the default allocators,
  but passing XIOM-defined C callbacks is out of scope (B-13/B-22 callback
  discipline).
