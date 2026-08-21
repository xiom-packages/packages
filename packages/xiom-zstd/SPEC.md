# xiom-zstd -- SPEC

**Phase**: 2 | **Priority**: HIGH
**Status**: PRODUCTION | **Depends on**: xiom.ffi (for Vec[UInt8] bridge, future)

## What it wraps
zstd -- fast lossless compression algorithm (Facebook).
Compression/decompression at GB/s speeds.

## Dependencies: System-installed. `winget install zstd`, `apt install libzstd-dev`.

## Bundling strategy: System-installed only.

## API (implemented)
```xiom
pub fn compress_bound(size: Int) -> Int
  requires: size > 0

pub fn compress(src: &Vec[UInt8], level: Int) -> Result[Vec[UInt8], Str]
  requires: src.len() > 0
  requires: level >= 1
  requires: level <= 22

pub fn decompress(src: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  requires: src.len() > 0
```

## Extern "C" declarations
```xiom
extern "C" {
  fn ZSTD_compress(dst: Int, dstCapacity: Int, src: Int, srcSize: Int, compressionLevel: Int) -> Int;
  fn ZSTD_decompress(dst: Int, dstCapacity: Int, src: Int, compressedSize: Int) -> Int;
  fn ZSTD_compressBound(srcSize: Int) -> Int;
  fn ZSTD_isError(code: Int) -> Int;
  fn ZSTD_getErrorName(code: Int) -> Int;
}
```

## Files
| File | Lines | Description |
|------|-------|-------------|
| `src/zstd.xi` | 81 | Main module: extern C + 3 safe wrappers with 5 requires contracts |
| `tests/test_conformance.xi` | ~310 | 42 conformance tests (10 sections) |
| `ROADMAP.md` | -- | Single-phase roadmap, known limitations |
| `SPEC.md` | -- | This file |

## Test Coverage (42 tests, 10 sections)
1. compress_bound -- 6 tests: positive, >= src, small input, large input, monotonic, formula(4096)
2. ZSTD_isError -- 3 tests: zero, negative, on compress_bound result
3. ZSTD_compress FFI stubs -- 6 tests: null buffers, zero size, levels 1/3/10/22
4. ZSTD_decompress FFI stubs -- 5 tests: null buffers, zero size, small/large/est capacity
5. Safe compress wrapper -- 4 tests: valid params, level 1, level 22, compress_bound positive
6. Safe decompress wrapper -- 3 tests: valid/small/large input
7. ZSTD_getErrorName -- 2 tests: callable, on error code
8. API presence -- 5 tests: compress_bound, compress, decompress, ZSTD_isError, ZSTD_getErrorName
9. Contract declarations -- 5 tests: all requires clauses (size>0, level 1-22, src.len>0)
10. Edge cases -- 3 tests: bounds, large positive isError, min input

## Known Limitations
- compress() and decompress() return Err until Vec[UInt8] <-> raw pointer bridge is available (compiler *UInt8 dereference support)
- FFI logic is complete: error checking, bound computation, and return code handling are all implemented correctly

## Effort: Day (implemented)
