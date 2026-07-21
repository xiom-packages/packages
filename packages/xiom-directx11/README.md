# xiom-directx11

Direct3D 11 &mdash; Microsoft's graphics API. Part of the DirectX SDK. Windows only.

## Quick Start

```xiom
use xiom.directx11;
```

## Building

```powershell
xiomc --release directx11.xi -o directx11.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- DirectX SDK &mdash; Windows system-installed

## Package Structure

```
├── directx11.xi         # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
