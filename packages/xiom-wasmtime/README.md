# xiom.wasmtime

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** WebAssembly runtime host bindings over Wasmtime.
> **Deps:** stdlib; wraps C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `engine` | Global Wasmtime engine configuration |
| `store` | Per-context store state |
| `module` | Compiled WebAssembly module |
| `instance` | Instantiated module with exports |
| `linker` | Host import resolution |
| `func` | Host function wrappers |
