# xiom-jit-fw

> **Status:** PLACEHOLDER — reserved, spec pending. No implementation yet.
> **Scope:** Framework for just-in-time compilation and execution.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `engine` | JIT compilation and execution engine |
| `exec` | Generated code loading and invocation |
| `cache` | Compiled artifact caching |
| `trampoline` | Call-back trampolines and closure adapters |
| `monitor` | Compilation telemetry and statistics |
