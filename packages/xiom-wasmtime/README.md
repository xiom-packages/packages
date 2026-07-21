# xiom-wasmtime

Wasmtime &mdash; standalone WebAssembly runtime (Bytecode Alliance). Engine, Store, Module compilation, Instance instantiation, function calling.

## Quick Start

```xiom
use xiom.wasmtime;
```

## Building

```powershell
xiomc --release wasmtime.xi -o wasmtime.exe
```

## Dependencies

- `xiom.ffi` (stdlib)
- Wasmtime &mdash; system-installed or downloaded from Bytecode Alliance

## Package Structure

```
├── wasmtime.xi          # Main module
├── tests/
│   └── test_conformance.xi  # Conformance tests
├── SPEC.md              # Full specification
├── ROADMAP.md           # Development roadmap
└── package.xi           # Package manifest
```

## License

MIT OR Apache-2.0
