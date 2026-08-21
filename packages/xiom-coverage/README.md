# xiom-coverage

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Code coverage collection and report generation.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `coverage/collect` | Runtime tracking of executed lines and branches |
| `coverage/summary` | Aggregation into per-file and overall coverage metrics |
| `coverage/report` | Emits text, JSON, and HTML coverage reports |
