# xiom-openblas

OpenBLAS &mdash; optimized Basic Linear Algebra Subprograms (BLAS) and LAPACK. Foundation for ALL scientific computing and ML packages.

## Quick Start

```xiom
use xiom.openblas;
```

## Building

```powershell
xiomc --release openblas.xi -o openblas.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- `xiom.alloc` (stdlib)
- OpenBLAS &mdash; system-installed (`apt install libopenblas-dev`)

## Package Structure

```
├── openblas.xi          # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
