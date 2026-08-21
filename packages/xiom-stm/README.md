# xiom-stm

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Software transactional memory for composable atomic operations.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `stm/txn` | Transaction context with automatic retry and rollback |
| `stm/var` | Transactional shared variables |
| `stm/retry` | Blocking primitives that wait on transaction dependencies |
