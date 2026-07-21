# xiom-ros2

ROS 2 &mdash; Robot Operating System middleware. System-installed.

## Quick Start

```xiom
use xiom.ros2;
```

## Building

```powershell
xiom --release ros2.xi -o ros2.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- `xiom.test`
- ROS 2 Humble/Iron &mdash; system-installed

## Package Structure

```
├── ros2.xi              # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
