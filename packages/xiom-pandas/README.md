# xiom-pandas

Pandas &mdash; data analysis library. Pandas 2.0+ backend is Apache Arrow. Wraps Arrow C++ directly with zero Python overhead.

## Quick Start

```xiom
use xiom.pandas;
```

## Building

```powershell
xiomc --release pandas.xi -o pandas.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- `xiom-arrow` (Apache Arrow &mdash; Pandas 2.0+ backend)
- Apache Arrow &mdash; system-installed

## Package Structure

```
├── pandas.xi            # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
