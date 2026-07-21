# xiom-box2d

Box2D &mdash; 2D physics engine. Real-time rigid body simulation for games.

## Quick Start

```xiom
use xiom.box2d;
```

## Building

```powershell
xiom --release box2d.xi -o box2d.exe
```

## Dependencies

- Box2D &mdash; system-installed or built from source

## Package Structure

```
├── box2d.xi             # Main module
├── box2d.xiom-bind      # Raw FFI bindings
├── box2d_safe.xi         # Safe wrapper layer
├── demo_box2d.xi         # Interactive demo
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── AUDIT.md             # Safety audit report
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
