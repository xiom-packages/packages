# xiom-openssl

OpenSSL &mdash; TLS/cryptography. System-installed.

## Quick Start

```xiom
use xiom.openssl;
```

## Building

```powershell
xiom --release openssl.xi -o openssl.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- `xiom.string`
- `xiom.core`
- OpenSSL &mdash; system-installed (`winget install OpenSSL`, `apt install libssl-dev`)

## Package Structure

```
├── openssl.xi           # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
