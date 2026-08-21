# xiom-llvm

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** LLVM backend integration for the XIOM compiler.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `context` | LLVM context, module, and builder setup |
| `lower` | XIOM IR to LLVM IR lowering |
| `types` | XIOM type to LLVM type mapping |
| `abi` | Calling conventions and data layout |
| `opt` | LLVM pass pipeline and optimization flags |
