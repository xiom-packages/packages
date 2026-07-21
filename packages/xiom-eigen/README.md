# xiom-eigen

Eigen &mdash; C++ template library for linear algebra. Header-only.

## Quick Start

```xiom
use xiom.eigen;
```

## Building

```powershell
xiomc --release eigen.xi -o eigen.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- Eigen 3.4 &mdash; header-only (`apt install libeigen3-dev`)

## Package Structure

```
├── eigen.xi             # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
