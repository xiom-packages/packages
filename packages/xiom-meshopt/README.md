# xiom-meshopt

meshoptimizer &mdash; mesh optimization library. Simplification, vertex cache optimization, overdraw reduction.

## Quick Start

```xiom
use xiom.meshopt;
```

## Building

```powershell
xiom --release meshopt.xi -o meshopt.exe
```

## Dependencies

- meshoptimizer &mdash; system-installed or built from source

## Package Structure

```
├── meshopt.xi           # Main module
├── src/                 # Source files
├── examples/            # Usage examples
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── AUDIT.md             # Safety audit report
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
