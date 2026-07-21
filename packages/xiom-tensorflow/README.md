# xiom-tensorflow

TensorFlow C API (libtensorflow) &mdash; Google's ML framework. Alternative to PyTorch/LibTorch. Larger ecosystem, TF Serving, TF Lite.

## Quick Start

```xiom
use xiom.tensorflow;
```

## Building

```powershell
xiomc --release tensorflow.xi -o tensorflow.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- TensorFlow C library &mdash; system-installed

## Package Structure

```
├── tensorflow.xi        # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
