# xiom-assimp

Assimp &mdash; 3D model import library. System-installed libassimp.

## Quick Start

```xiom
use xiom.assimp;
```

## Building

```powershell
xiomc --release assimp.xi -o assimp.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- Assimp &mdash; system-installed (`apt install libassimp-dev`)

## Package Structure

```
├── assimp.xi            # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
