# xiom-sdl3

SDL3 &mdash; cross-platform multimedia. System-installed.

## Quick Start

```xiom
use xiom.sdl3;
```

## Building

```powershell
xiomc --release sdl3.xi -o sdl3.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- SDL3 &mdash; system-installed

## Package Structure

```
├── sdl3.xi              # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
