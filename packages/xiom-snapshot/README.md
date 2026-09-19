# xiom.snapshot

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Snapshot testing: capture, compare, and update serialized values.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `snapshot/store` | On-disk persistence of captured snapshots |
| `snapshot/compare` | Structural diffing of snapshot output |
| `snapshot/update` | Regeneration and acceptance of new snapshots |
