# xiom-sql

XIOM SQL &mdash; database abstraction module. SQL generation, connection pooling, result mapping.

## Quick Start

```xiom
use xiom.sql;
```

## Building

```powershell
xiomc --release sql.xi -o sql.exe
```

## Dependencies

- `xiom-libpq` (PostgreSQL backend)
- SQLite (embedded backend)

## Package Structure

```
├── sql.xi               # Main module
├── sqlite.xiom-bind     # SQLite FFI bindings
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── ROADMAP.md           # Development roadmap
├── AUDIT.md             # Safety audit report
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
