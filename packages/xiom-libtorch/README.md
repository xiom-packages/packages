# xiom-libtorch

LibTorch &mdash; PyTorch C++ API. Full ML/DL framework with CUDA support.

## Quick Start

```xiom
use xiom.libtorch;
```

## Building

```powershell
xiomc --release libtorch.xi -o libtorch.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- LibTorch &mdash; system-installed (PyTorch C++ distribution)

## Package Structure

```
├── libtorch.xi          # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
