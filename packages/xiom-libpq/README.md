# xiom-libpq

libpq &mdash; PostgreSQL C client library. Connection management, query execution, result parsing.

## Quick Start

```xiom
use xiom.libpq;
```

## Building

```powershell
xiomc --release libpq.xi -o libpq.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- libpq &mdash; system-installed (`apt install libpq-dev`)

## Package Structure

```
├── libpq.xi             # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
