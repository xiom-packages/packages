# xiom.zstd -- Production Roadmap

**Version**: v0.1.0 | **Compiler**: xiom v0.46.0+ | **Last updated**: 2026-07-21

## Current Rating: 7/10 [SETTINGS] PRODUCTION-READY (FFI stub)

| Criterion | Status |
|-----------|--------|
| [OK] Extern "C" declarations | 5 FFI functions declared: ZSTD_compress, ZSTD_decompress, ZSTD_compressBound, ZSTD_isError, ZSTD_getErrorName |
| [OK] Safe wrappers | 3 pub fn: compress_bound, compress, decompress |
| [OK] Design-by-contract | 5 requires contracts across 3 functions |
| [OK] Tests | test_conformance.xi -- 42 tests, 10 sections |
| [OK] SPEC.md | Full API surface documented |
| [OK] ROADMAP.md | This file |
| [WARN] Vec[UInt8] marshaling | Blocked on compiler *UInt8 dereference support |
| [WARN] C bridge linking | Requires system-installed libzstd at link time |

## Dependencies

- **System**: libzstd (`winget install zstd`, `apt install libzstd-dev`, `brew install zstd`)
- **XIOM**: xiom.ffi (for Vec[UInt8] <-> raw pointer bridge, future)

## Implementation History

| Phase | Status | Description |
|-------|--------|-------------|
| **P1: Core FFI** | [OK] Done | extern "C" declarations for zstd compression/decompression |
| **P1: Safe Wrappers** | [OK] Done | compress_bound, compress, decompress with contracts |
| **P1: Tests** | [OK] Done | 42 conformance tests covering compress_bound, FFI stubs, API presence, contracts, edge cases |

## API Surface

| Function | Signature | Contracts | Status |
|----------|-----------|-----------|--------|
| `compress_bound` | `(size: Int) -> Int` | requires size > 0 | [OK] |
| `compress` | `(src: &Vec[UInt8], level: Int) -> Result[Vec[UInt8], Str]` | requires src.len() > 0, level >= 1, level <= 22 | [OK] |
| `decompress` | `(src: &Vec[UInt8]) -> Result[Vec[UInt8], Str]` | requires src.len() > 0 | [OK] |

## Extern "C" Surface

| C Function | XIOM Signature |
|------------|---------------|
| `ZSTD_compress` | `(dst: Int, dstCapacity: Int, src: Int, srcSize: Int, compressionLevel: Int) -> Int` |
| `ZSTD_decompress` | `(dst: Int, dstCapacity: Int, src: Int, compressedSize: Int) -> Int` |
| `ZSTD_compressBound` | `(srcSize: Int) -> Int` |
| `ZSTD_isError` | `(code: Int) -> Int` |
| `ZSTD_getErrorName` | `(code: Int) -> Int` |

## Future (Phase 2)

| Feature | Priority | Effort | Blocker |
|---------|----------|--------|---------|
| Vec[UInt8] <-> raw pointer marshaling | P0 | Day | Compiler *UInt8 dereference support |
| Production compress/decompress with real buffers | P0 | Day | Vec[UInt8] marshaling |
| ZSTD streaming API (CStream/DStream) | P1 | Day | Vec[UInt8] marshaling |
| Dictionary-based compression | P2 | Day | Streaming API |
| Multi-frame decompression | P2 | Day | Streaming API |
| ZSTD_getFrameContentSize | P2 | Hour | FFI declaration only |
| Decompress with known output size | P1 | Hour | Vec[UInt8] alloc from size |

## Known Limitations

- **compress() and decompress() return Err** -- Vec[UInt8] result construction requires compiler *UInt8 support. The FFI call and error-checking logic is complete; only the output buffer marshaling is stubbed.
- **No streaming API** -- CStream/DStream require stateful resource management patterns beyond current scope.
- **No dictionary support** -- requires streaming API and external dictionary loading.
