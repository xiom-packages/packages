# xiom-zstd

zstd &mdash; fast lossless compression algorithm (Facebook). Compression/decompression at GB/s speeds.

## Quick Start

```xiom
use xiom.zstd;
```

## Building

```powershell
xiom --release zstd.xi -o zstd.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- zstd &mdash; system-installed (`winget install zstd`, `apt install libzstd-dev`)

## Package Structure

```
├── zstd.xi              # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
