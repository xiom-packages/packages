# xiom-flash

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** NOR/NAND flash memory program, erase, and status management.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `read` | Block/page read operations. |
| `write` | Page program operations. |
| `erase` | Sector/block erase. |
| `status` | Device status and busy polling. |
| `cfi` | Flash identification and geometry. |
