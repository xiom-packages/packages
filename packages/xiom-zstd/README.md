# xiom.zstd

Zstandard (de)compression bindings for XIOM. The official **single-file
zstd 1.5.7 amalgamation** is vendored in `vendor/` (BSD-3-Clause) and
compiled into the test binary -- no system library, no runtime DLL.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.1): 8/8 with
> a real ratio (8192 -> 34 bytes) and byte-identical round-trips.
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

## API

| Area | Functions |
|------|-----------|
| Version | `zstd_version`, `zstd_version_number` |
| Size | `zstd_compress_bound`, `zstd_frame_content_size` |
| Codec | `zstd_compress(src, level)`, `zstd_decompress(src, out_capacity)`, `zstd_decompress_auto(src)` |
| Errors | `zstd_is_error`, `zstd_error_name` |
| Constants | `ZSTD_CONTENTSIZE_UNKNOWN/-ERROR` |

All fallible calls return `Result[_, Str]` with `ZSTD_getErrorName` text.
Inputs are `&mut Vec[UInt8]` (the confined module needs `as_mut_ptr`).

## Build note

`port.args.json` compiles `src/zstd_all.c` (a 4-line shim pinning
`STATIC_BMI2 0` around the vendored amalgamation); the vendored file itself
is unmodified. Full provenance + re-pin: `SPEC.md` §2.

## Tests

```
scripts/port.ps1 -Package xiom.zstd
```

Expected: 8 `[PASS]`, exit 0 (version 1.5.7, real ratio, identical
round-trips, invalid frame rejected). Streaming/dictionaries are Phase 2
(`ROADMAP.md`).
