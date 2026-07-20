# xiom-zstd — SPEC

**Phase**: 2 | **Priority**: HIGH
**Status**: SPEC only | **Depends on**: xiom.ffi

## What it wraps
zstd — fast lossless compression algorithm (Facebook).
Compression/decompression at GB/s speeds.

## Dependencies: System-installed. `winget install zstd`, `apt install libzstd-dev`.

## Bundling strategy: System-installed only.

## API (minimal)
```xiom
pub fn compress(data: Vec[UInt8], level: Int) -> Vec[UInt8]
pub fn decompress(data: Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn compress_bound(size: Int) -> Int
```

## Effort: Day
