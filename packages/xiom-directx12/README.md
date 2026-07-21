# xiom-directx12

Direct3D 12 &mdash; Microsoft's low-level graphics API. Explicit GPU control. Windows only.

## Quick Start

```xiom
use xiom.directx12;
```

## Building

```powershell
xiom --release directx12.xi -o directx12.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- DirectX 12 SDK &mdash; Windows system-installed

## Package Structure

```
├── directx12.xi         # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
