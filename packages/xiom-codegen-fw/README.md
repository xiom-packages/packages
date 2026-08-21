# xiom-codegen-fw

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Framework for target-agnostic code generation pipelines.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `ir` | Intermediate representation value types |
| `context` | Codegen session and target context |
| `emit` | Instruction emission primitives |
| `lower` | AST-to-IR lowering passes |
| `layout` | Data layout and ABI convention handling |
| `targets` | Backend target abstraction |
