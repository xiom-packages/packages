# xiom.interrupt

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Interrupt registration, priority, and dispatch for external and peripheral sources.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `handler` | ISR registration and dispatch. |
| `priority` | Priority and preemption configuration. |
| `enable` | Interrupt enable/disable. |
| `defer` | Deferred work scheduling. |
