# xiom-ozz

Ozz Animation &mdash; open-source skeletal animation library. Runtime playback and blending.

## Quick Start

```xiom
use xiom.ozz;
```

## Building

```powershell
xiom --release ozz.xi -o ozz.exe
```

## Dependencies

- Ozz Animation &mdash; system-installed or built from source

## Package Structure

```
├── ozz.xi               # Main module
├── src/                 # Source files
├── examples/            # Usage examples
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── AUDIT.md             # Safety audit report
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
