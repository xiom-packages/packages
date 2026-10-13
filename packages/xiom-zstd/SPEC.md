# SPEC: xiom.zstd -- Zstandard bindings (vendored amalgamation) + ZSTC container

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.zstd` |
| Version | 0.3.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Zstandard -- https://github.com/facebook/zstd |
| Upstream version pinned | **v1.5.7** (tag object `ac66b19e`, commit `f8745da6ff1ad1e7bab384bd1f9d742439278e99`) |
| Upstream license | BSD-3-Clause (chosen from the dual BSD-3/GPLv2; `vendor/LICENSE`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (no platform-specific XIOM code) |
| Compiler pin | v0.64.4 |
| Modules | `xiom.zstd` (declared in `package.xi`) |

## 2. Vendored path (G2 pin)

The official **single-file amalgamation** is vendored into `vendor/` and
compiled into the test binary via `--c-source` (no system library, no runtime
DLL). Generated from the pinned release with the upstream tool:

```
python combine.py -r ../../lib -x legacy/zstd_legacy.h -o zstd.c zstd-in.c
```

run from `build/single_file_libs/` of `zstd-1.5.7`.

| File | Bytes | SHA256 |
|------|-------|--------|
| `vendor/zstd.c` (generated; **LF-normalized**) | 2,174,920 | `208E110A1F052D007242D4EEF6ED20A03AB1DC6E13EB2C4FF8D158112120BA8E` |
| `vendor/zstd.h` (from `lib/`) | 181,748 | `9B4BC8245565C98CCFC61C07749928B57E7C0F6FDDB0530C4F6AA1971893D88B` |
| `vendor/LICENSE` (BSD-3-Clause) | 1,549 | `7055266497633C9025B777C78EB7235AF13922117480ED5C674677ADC381C9D8` |

Line-ending note: `combine.py` run under Windows Python writes CRLF; the
vendored file is normalized to LF (and `.gitattributes` pins `vendor/** -text`)
so the pin is over the stored LF bytes. On re-pin, normalize CRLF -> LF before
computing the SHA256.

Independent parity check (0.3.0 touch, 2026-10-13): `vendor/zstd.h` is
byte-identical to `lib/zstd.h` at the pinned commit in the upstream study
clone `E:\repos\zstd` (tag `v1.5.7`).

### Source archive provenance

| Artifact | Value |
|----------|-------|
| Download | https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz |
| SHA256 (verified against the published `.sha256` asset) | `eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3` |

### Build shim

`src/zstd_all.c` (our code) sets `#define STATIC_BMI2 0` and includes the
vendored `zstd.c`: the xiom link line compiles C sources with baseline
x86-64 features, and zstd's `bits.h` would otherwise take the BMI2
intrinsics path (`_bzhi_u64`) without a `-mbmi2` target. The vendored file is
unmodified; properly `target("bmi2")`-attributed paths in the decompressor
remain available.

### Re-pin procedure

1. Download the new official release; verify its published SHA256.
2. Regenerate the amalgamation with the upstream `combine.py` command above.
3. Replace `vendor/zstd.c`, `vendor/zstd.h`, `vendor/LICENSE`; recompute the
   table; update version rows in `README.md`/`AUDIT.md`/`PROVENANCE.md` in the
   same commit.
4. Re-run `scripts/port.ps1 -Package xiom.zstd -TimeoutSec 240` (x2) and
   record the matrix.

## 3. Design and safe boundary (G5)

| Module | File | Role |
|--------|------|------|
| `xiom.zstd` | `zstd.xi` | The only module with `extern "C"`: raw declarations + safe wrappers (version, bound, compress, decompress, frame size, error detection/naming) + the pure-XIOM ZSTC container surface |
| shim | `src/zstd_all.c` | Compiles the vendored amalgamation with the intrinsics pin |

API returns owned `Vec[UInt8]` results and `Result[_, Str]` errors carrying
`ZSTD_getErrorName` text; inputs are `&mut Vec[UInt8]` (the confined module
needs `as_mut_ptr`). Error sentinels `ZSTD_CONTENTSIZE_UNKNOWN/-ERROR` are
exposed for `zstd_frame_content_size`.

Call convention note: for a resource-owning API on this pin, `&mut` input
buffers mirror the proven `as_mut_ptr` idiom (see the sqlite/glfw/sdl3
packages). Streaming contexts with reusable buffers are Phase 2.

Container discipline: every container primitive is pure XIOM over owned
`Vec[UInt8]` buffers (byte-indexed reads; no foreign pointers, no pointer
arithmetic, no libc). Only the frame content-size query and the per-frame
decompression cross the FFI boundary, and both go through the wrappers above
with an owned buffer per call.

## 4. API surface (0.3.0)

| Area | Functions |
|------|-----------|
| Version | `zstd_version`, `zstd_version_number` |
| Size / errors | `zstd_compress_bound`, `zstd_frame_content_size`, `zstd_is_error`, `zstd_error_name` |
| One-shot codec | `zstd_compress(src, level)`, `zstd_decompress(src, out_capacity)`, `zstd_decompress_auto(src)` |
| Container write | `zstd_container_write(frames)` |
| Container builder | `zstd_container_builder_new`, `zstd_container_builder_append`, `zstd_container_builder_count`, `zstd_container_builder_finalize` |
| Container read | `zstd_container_open(data)`, `zstd_container_frame_count`, `zstd_container_total_size`, `zstd_container_index_offset` |
| Container access | `zstd_container_frame_offset`, `zstd_container_frame_size`, `zstd_container_frame_out_size`, `zstd_container_seek`, `zstd_container_frame_at(data, c, i)` |
| Constants | `ZSTD_CONTENTSIZE_UNKNOWN/-ERROR`, `ZSTC_MAGIC_LEN`, `ZSTC_HEADER_LEN`, `ZSTC_INDEX_ENTRY_LEN`, `ZSTC_FORMAT_VERSION` |
| Types | `ZstdContainer`, `ZstdContainerBuilder` |

## 5. ZSTC container format (own format, version 1)

Purpose: a general-purpose container + random-access framing surface for the
engine pipeline (relay `REL-20261013-1926-packages`, wave A2): N
independently compressed zstd frames in one buffer, addressable by index in
any order. All integers are **little-endian**. The format is original to this
package (not the upstream zstd "seekable format" plugin).

```
+----------------------------+ byte 0
| header (16 bytes)          |
+----------------------------+ byte 16
| frame 0 (raw zstd frame)   |
| frame 1                    |
| ...                        |
| frame N-1                  |
+----------------------------+ byte index_offset
| index entry 0 (12 bytes)   |
| ...                        |
| index entry N-1            |
+----------------------------+ byte len (exact)
```

Header (16 bytes):

| Offset | Size | Field | Written / accepted value |
|--------|------|-------|--------------------------|
| 0 | 4 | magic | `"ZSTC"` = `5A 53 54 43` |
| 4 | 2 | format version | `1`; any other value rejected |
| 6 | 2 | flags | `0`; any nonzero value rejected (version-1 readers) |
| 8 | 4 | frame_count | N (u32) |
| 12 | 4 | index_offset | absolute offset of the index table (u32) |

Frame region: N raw zstd frames back to back starting at offset 16, stored
exactly as supplied (no padding, no re-compression). The writer only accepts
frames whose zstd frame header records a content size (frames produced by
`zstd_compress` qualify).

Index table: N entries of 12 bytes at `index_offset`:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | frame_offset: absolute offset of the frame's first byte (u32) |
| 4 | 4 | compressed_size: stored frame length in bytes (u32, nonzero) |
| 8 | 4 | decompressed_size: frame content size recorded at write time (u32) |

Format invariants (validated by `zstd_container_open`, in this order):

1. `len >= 16`, else `"zstd.container: truncated header"`.
2. magic matches, else `"zstd.container: bad magic"`.
3. version == 1, else `"zstd.container: unsupported version"`.
4. flags == 0, else `"zstd.container: unsupported flags"`.
5. `16 <= index_offset <= len` and
   `index_offset + frame_count * 12 == len` (exact size; no trailing bytes),
   else `"zstd.container: truncated index"`.
6. Every entry: `frame_offset` is exactly the running end of the previous
   frame (first frame at 16), `compressed_size > 0`, and the frame region
   does not cross `index_offset`; after the last entry the running end equals
   `index_offset`. Violation (including zero frames with
   `index_offset > 16`), else `"zstd.container: bad frame index"`.

Consequently the container is fully described by its bytes: header + frames +
index cover `[0, len)` with no gaps and no overlaps. Frame *payloads* are not
parsed at open time; a structurally valid container whose payload is corrupt
fails at `zstd_container_frame_at` with a typed error.

The empty container is valid: `len == 16`, `frame_count == 0`,
`index_offset == 16`, zero index entries.

### Container error catalog (all `Result[_, Str]`, never a crash)

| Error | Raised by |
|-------|-----------|
| `zstd.container: empty frame` | writer/builder append, zero-length frame |
| `zstd.container: not a zstd frame` | writer/builder append, garbage input (content-size sentinel `ZSTD_CONTENTSIZE_ERROR`) |
| `zstd.container: frame content size unknown` | writer/builder append, valid frame without a recorded content size |
| `zstd.container: container too large` | writer/builder, u32 index field overflow |
| `zstd.container: truncated header` | open, `len < 16` |
| `zstd.container: bad magic` | open |
| `zstd.container: unsupported version` | open |
| `zstd.container: unsupported flags` | open |
| `zstd.container: truncated index` | open, index/offset size violations |
| `zstd.container: bad frame index` | open, entry contiguity/size violations |
| `zstd.container: frame out of range` | `seek`, `frame_at`, index < 0 or >= frame_count |
| `zstd.container: truncated frame` | `frame_at`, buffer shorter than the recorded range |
| `zstd.container: decompress failed (...)` | `frame_at`, stored payload not decompressible (zstd error name embedded) |
| `zstd.container: frame size mismatch` | `frame_at`, decompressed size != recorded `decompressed_size` |

### Container semantics

- `zstd_container_write(frames)`: one-shot write; frame order preserved; an
  empty frame list yields the 16-byte empty container.
- Builder: `new` -> `append` (validates and copies the frame; on Err the
  builder is unchanged) -> `finalize` (emits the same bytes as
  `zstd_container_write` for the same frames; the builder is not consumed and
  can be appended to and finalized again).
- Reader: `open` parses and validates the index; the container buffer stays
  owned by the caller, and every accessor takes it by reference.
- Random access: `frame_at(data, c, i)` slices the stored frame out of `data`
  into an owned buffer and decompresses it; frames can be read in any order,
  repeatedly, independently. A frame recorded with `decompressed_size == 0`
  yields an empty Ok buffer (decompression is still attempted with a 1-byte
  scratch capacity so a lying zero is caught).
- `seek(c, i)` resolves the absolute byte offset of frame `i` for callers
  that want the stored (still compressed) frame bytes; combine with
  `frame_size` to slice.

## 6. Test matrix

| Configuration | Command | Result |
|---------------|---------|--------|
| Vendored amalgamation + container (0.3.0) | `scripts/port.ps1 -Package xiom.zstd -TimeoutSec 240` | **PASS 24/24 x2 (2026-10-13, compiler v0.64.4)** -- 8 codec checks (version 1.5.7, `compressBound` sanity, 8192 -> 34 bytes at level 3, frame content size 8192, round-trip identity, auto-size identity, incompressible 2048-byte identity, invalid frame rejected) + 16 container checks: 3-frame write layout, open/accessors, in-order round-trip, out-of-order + repeated `frame_at`, seek byte ranges, out-of-range typed errors, empty container, builder == one-shot, builder validation, corrupt magic/version/flags, truncations, corrupt index, corrupt payload (siblings still readable), index size fraud, empty frame |
| Vendored amalgamation (0.2.0) | `scripts/port.ps1 -Package xiom.zstd` | **PASS 8/8 x2** -- 2026-10-08, compiler v0.64.1 (historical) |

No SKIP path exists (the library is compiled in). `port.args.json` passes the
shim; the packages runner resolves `${PACKAGE_DIR}` and the 240 s watchdog
covers the amalgamation compile (~40-60 s).

## 7. Scope

Delivered: one-shot compress/decompress, frame-size queries, error reporting,
and (0.3.0) the ZSTC container framing surface: one-shot writer, append +
finalize builder, validated reader with random access (`frame_at`,
seek-by-index), typed container errors and the documented own format above.

Out of scope: streaming `ZSTD_CCtx`/`ZSTD_DCtx`, dictionaries, checksum
control, long mode and the remaining zstd C API (explicit non-goals, Phase 2
in `ROADMAP.md`). The pre-pilot module was a null-pointer stub ("blocked on
compiler *UInt8 dereference support" -- since disproven) and is preserved in
git history.
