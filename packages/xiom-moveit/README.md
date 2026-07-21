# xiom-moveit

MoveIt &mdash; Motion planning framework. System-installed.

## Quick Start

```xiom
use xiom.moveit;
```

## Building

```powershell
xiomc --release moveit.xi -o moveit.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- MoveIt2 &mdash; system-installed (ROS 2 package)

## Package Structure

```
├── moveit.xi            # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
