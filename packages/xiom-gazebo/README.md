# xiom-gazebo

Gazebo &mdash; Robot simulation engine (gz-sim / Ignition Gazebo). System-installed.

## Quick Start

```xiom
use xiom.gazebo;
```

## Building

```powershell
xiom --release gazebo.xi -o gazebo.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- `xiom.io`
- `xiom.test`
- Gazebo &mdash; system-installed

## Package Structure

```
├── gazebo.xi            # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
