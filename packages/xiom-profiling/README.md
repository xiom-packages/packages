# xiom.profiling

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** CPU, memory, and wall-clock profiling utilities.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `profiling/timer` | High-resolution timing of code sections |
| `profiling/sampler` | Periodic sampling of stacks and allocations |
| `profiling/flame` | Flame-graph style aggregation of sampled stacks |
