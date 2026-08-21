# xiom-retry

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Retry, backoff, and circuit-breaking policies for resilient calls.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `retry/policy` | Configurable retry counts, intervals, and stop conditions |
| `retry/backoff` | Constant, linear, and exponential backoff strategies |
| `retry/circuit` | Circuit breaker state tracking and trip thresholds |
