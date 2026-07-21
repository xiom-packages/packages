# xiom-arrow

Apache Arrow &mdash; in-memory columnar data format. Pandas backend, zero-copy data sharing between libraries.

## Quick Start

```xiom
use xiom.arrow;
```

## Building

```powershell
xiom --release arrow.xi -o arrow.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- Apache Arrow &mdash; system-installed (`apt install libarrow-dev`)

## Package Structure

```
├── arrow.xi             # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
