# xiom-scipy

SciPy &mdash; scientific computing library. Provides algorithms: optimization, integration, interpolation, signal processing, statistics, sparse matrices.

## Quick Start

```xiom
use xiom.scipy;
```

## Building

```powershell
xiom --release scipy.xi -o scipy.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- `xiom.math` (for pure-XIOM stats)
- `xiom-numpy` (future)
- `xiom-openblas` (future)
- System-installed C/Fortran libraries per module

## Package Structure

```
├── scipy.xi             # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
