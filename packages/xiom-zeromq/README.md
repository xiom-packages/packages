# xiom-zeromq

libzmq &mdash; high-performance asynchronous messaging library. Supports PUB/SUB, REQ/REP, PUSH/PULL, and other messaging patterns.

## Quick Start

```xiom
use xiom.zeromq;
```

## Building

```powershell
xiom --release zeromq.xi -o zeromq.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- ZeroMQ &mdash; system-installed (`winget install zeromq`, `apt install libzmq3-dev`)

## Package Structure

```
├── zeromq.xi            # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
