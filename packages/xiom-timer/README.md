# xiom.timer

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Hardware timer/counter services for delays, scheduling, and timing measurement.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `delay` | Blocking delay operations. |
| `oneshot` | One-shot timeout callbacks. |
| `periodic` | Repeating tick callbacks. |
| `capture` | Input capture timestamping. |
| `counter` | Free-running counter access. |
