# xiom.audit

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Security audit event logging and tamper-evident trails.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `log` | Structured audit event emission |
| `chain` | Hash-chained tamper-evident log |
| `query` | Audit trail search and export |
| `sink` | Pluggable audit storage backends |
