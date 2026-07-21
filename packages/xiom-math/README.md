# xiom-math

XIOM math &mdash; standard library mathematics module. Vectors, matrices, quaternions, transforms.

## Quick Start

```xiom
use xiom.math;
```

## Building

```powershell
xiomc --release math.xi -o math.exe
```

## Dependencies

- None (pure XIOM standard library)

## Package Structure

```
├── math.xi              # Main module
├── src/                 # Source files
├── examples/            # Usage examples
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── ROADMAP.md           # Development roadmap
├── AUDIT.md             # Safety audit report
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
