# xiom-lzfse

LZFSE &mdash; Apple's lossless compression algorithm. High compression ratio and speed.

## Quick Start

```xiom
use xiom.lzfse;
```

## Building

```powershell
xiom --release lzfse.xi -o lzfse.exe
```

## Dependencies

- LZFSE &mdash; system-installed or built from source

## Package Structure

```
├── lzfse.xi             # Main module
├── src/                 # Source files
├── examples/            # Usage examples
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── AUDIT.md             # Safety audit report
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
