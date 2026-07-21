# xiom-libuv

libuv &mdash; cross-platform asynchronous I/O library (used by Node.js). Event loop, TCP/UDP sockets, file I/O, timers, child processes.

## Quick Start

```xiom
use xiom.libuv;
```

## Building

```powershell
xiom --release libuv.xi -o libuv.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- libuv &mdash; system-installed (`apt install libuv1-dev`)

## Package Structure

```
├── libuv.xi             # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
