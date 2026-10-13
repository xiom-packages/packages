# xiom.zstd

Zstandard (de)compression bindings for XIOM. The official **single-file
zstd 1.5.7 amalgamation** is vendored in `vendor/` (BSD-3-Clause) and
compiled into the test binary -- no system library, no runtime DLL.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.4): 24/24 with
> a real ratio (8192 -> 34 bytes), byte-identical round-trips, and the 0.3.0
> ZSTC container framing surface (random-access frame index).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.zstd;

fn main() {
  var data: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 4096 {
    data.push(65 as UInt8);
    i = i + 1;
  }
  let packed = zstd_compress(&mut data, 3);
  if !packed.is_ok {
    io.println("compress failed: " + packed.error);
    return;
  }
  var p: Vec[UInt8] = packed.value;
  io.println("compressed to " + to_string(p.len()) + " bytes");
  let restored = zstd_decompress_auto(&mut p);
  if restored.is_ok {
    io.println("restored " + to_string(restored.value.len()) + " bytes");
  }
}
```

## Container (ZSTC) quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.zstd;

fn main() {
  // Compress two chunks independently, then frame them in one container.
  var chunk_a: Vec[UInt8] = Vec[UInt8].new();
  var chunk_b: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 1000 { chunk_a.push((65 + i % 16) as UInt8); i = i + 1; }
  i = 0;
  while i < 500  { chunk_b.push((97 + i % 16) as UInt8); i = i + 1; }

  var frames: Vec[Vec[UInt8]] = Vec[Vec[UInt8]].new();
  let ca = zstd_compress(&mut chunk_a, 3);
  let cb = zstd_compress(&mut chunk_b, 3);
  if ca.is_ok { frames.push(ca.value); }
  if cb.is_ok { frames.push(cb.value); }

  let w = zstd_container_write(&frames);
  if !w.is_ok {
    io.println("container write failed: " + w.error);
    return;
  }
  var container: Vec[UInt8] = w.value;

  let o = zstd_container_open(&container);
  if o.is_ok {
    let c = o.value;
    io.println("frames: " + to_string(zstd_container_frame_count(&c)));
    let f1 = zstd_container_frame_at(&container, &c, 1);   // random access
    let f0 = zstd_container_frame_at(&container, &c, 0);   // any order
    if f0.is_ok { io.println("frame 0: " + to_string(f0.value.len()) + " bytes"); }
    if f1.is_ok { io.println("frame 1: " + to_string(f1.value.len()) + " bytes"); }
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Version | `zstd_version`, `zstd_version_number` |
| Size | `zstd_compress_bound`, `zstd_frame_content_size` |
| Codec | `zstd_compress(src, level)`, `zstd_decompress(src, out_capacity)`, `zstd_decompress_auto(src)` |
| Errors | `zstd_is_error`, `zstd_error_name` |
| Container write | `zstd_container_write`, `zstd_container_builder_new/append/count/finalize` |
| Container read | `zstd_container_open`, `zstd_container_frame_count`, `zstd_container_total_size`, `zstd_container_index_offset`, `zstd_container_frame_offset/size/out_size`, `zstd_container_seek`, `zstd_container_frame_at` |
| Constants | `ZSTD_CONTENTSIZE_UNKNOWN/-ERROR`, `ZSTC_MAGIC_LEN`, `ZSTC_HEADER_LEN`, `ZSTC_INDEX_ENTRY_LEN`, `ZSTC_FORMAT_VERSION` |

All fallible calls return `Result[_, Str]` with typed container errors
(`zstd.container: ...`) or `ZSTD_getErrorName` text. Inputs are
`&mut Vec[UInt8]` (the confined module needs `as_mut_ptr`). The container
format (header + raw frames + 12-byte-per-frame index; empty container valid;
corrupt/truncated input -> typed error) is documented in `SPEC.md` section 5.

## Build note

`port.args.json` compiles `src/zstd_all.c` (a 4-line shim pinning
`STATIC_BMI2 0` around the vendored amalgamation); the vendored file itself
is unmodified. Full provenance + re-pin: `SPEC.md` section 2 and
`PROVENANCE.md`.

## Tests

```
scripts/port.ps1 -Package xiom.zstd -TimeoutSec 240
```

Expected: 24 `[PASS]`, exit 0 (version 1.5.7, real ratio, identical
round-trips, invalid frame rejected; container multi-frame round-trips,
out-of-order random access, seek, builder, empty container/frame, typed
corrupt/truncated errors). Streaming contexts/dictionaries are Phase 2
(`ROADMAP.md`).
