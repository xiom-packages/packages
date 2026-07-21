# xiom-opengl

OpenGL 4.6 &mdash; cross-platform graphics API. Legacy support for Linux/macOS, embedded systems (OpenGL ES), WebGL transpilation target.

## Quick Start

```xiom
use xiom.opengl;
```

## Building

```powershell
xiom --release opengl.xi -o opengl.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- `xiom-glfw` (window creation)
- OpenGL &mdash; system-installed

## Package Structure

```
├── opengl.xi            # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
