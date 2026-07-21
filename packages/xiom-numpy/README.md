# xiom-numpy

NumPy C API &mdash; the fundamental array computing library for scientific Python. ND-array operations, broadcasting, linear algebra, FFT, random numbers.

## Quick Start

```xiom
use xiom.numpy;
```

## Building

```powershell
xiom --release numpy.xi -o numpy.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- `xiom-openblas` (BLAS/LAPACK backend)
- NumPy C headers &mdash; system-installed

## Package Structure

```
├── numpy.xi             # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
