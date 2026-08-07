# xiom-neural

> **Status:** PLACEHOLDER — reserved, spec pending. No implementation yet.
> **Scope:** Neural network construction and training primitives.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `network` | Container for composed network graphs. |
| `layer` | Layer interface and registration. |
| `forward` | Forward pass execution engine. |
| `backward` | Backpropagation and gradient computation. |
| `weight` | Weight initialization schemes. |
| `state` | Parameter and state dict management. |
