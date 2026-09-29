# xiom.wasmtime

> **Status:** `incubating` -- not yet conformance-tested; not yet published to the XIOM registry.
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
