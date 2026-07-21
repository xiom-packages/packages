# xiom-raylib

Raylib &mdash; simple game framework. System-installed.

## Quick Start

```xiom
use xiom.raylib;
```

## Building

```powershell
xiom --release raylib.xi -o raylib.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- raylib &mdash; system-installed (`apt install libraylib-dev`)

## Package Structure

```
├── raylib.xi            # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
