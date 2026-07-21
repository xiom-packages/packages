# xiom-jolt

Jolt Physics &mdash; multi-threaded 3D physics engine. Rigid body dynamics, ray casting, collision detection.

## Quick Start

```xiom
use xiom.jolt;
```

## Building

```powershell
xiom --release jolt.xi -o jolt.exe
```

## Dependencies

- Jolt Physics &mdash; system-installed or built from source

## Package Structure

```
├── jolt.xi              # Main module
├── jolt.xiom-bind       # Raw FFI bindings
├── jolt_safe.xi          # Safe wrapper layer
├── demo_jolt.xi          # Interactive demo
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── AUDIT.md             # Safety audit report
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
