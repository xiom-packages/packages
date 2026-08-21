# xiom-wasm

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** WebAssembly backend for the XIOM compiler.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `module` | WASM module and section construction |
| `emit` | Instruction encoding and binary emission |
| `imports` | Import/export and host function bindings |
| `mem` | Linear memory and memory operation lowering |
| `runtime` | Runtime glue and start-up shims |
