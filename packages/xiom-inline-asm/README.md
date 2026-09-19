# xiom.inline-asm

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Inline assembly support with operand constraints.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `parse` | Inline asm template and operand parsing |
| `constraints` | Operand constraint classification |
| `lower` | Asm node lowering into the codegen backend |
| `targets` | Architecture-specific instruction handling |
| `regs` | Register allocation hints and clobber lists |
