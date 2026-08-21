# xiom-backoff

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Backoff strategies and retry loops for transient failure recovery.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `backoff/strategy` | Exponential and jittered backoff policies |
| `backoff/retry` | Retry loop with cap and reset |
