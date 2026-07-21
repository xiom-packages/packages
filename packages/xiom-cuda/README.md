# xiom-cuda

CUDA Toolkit &mdash; NVIDIA GPU computing (cuBLAS, cuDNN, cuFFT, cuRAND).

## Quick Start

```xiom
use xiom.cuda;
```

## Building

```powershell
xiom --release cuda.xi -o cuda.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- `xiom-libtorch` (for tensor interop)
- CUDA Toolkit 12.x &mdash; system-installed (`nvidia-smi` to check)

## Package Structure

```
├── cuda.xi              # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
