# xiom.cache

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** General-purpose in-memory caching with TTL and eviction.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `cache/store` | Thread-safe key-value cache with pluggable eviction |
| `cache/ttl` | Time-to-live expiry and lazy invalidation |
| `cache/refresh` | Background refresh of stale or near-expiry entries |
