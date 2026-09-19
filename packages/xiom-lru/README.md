# xiom.lru

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Least-recently-used cache with O(1) access and eviction.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `lru/cache` | Bounded LRU cache keyed by arbitrary types |
| `lru/list` | Doubly-linked list backing insertion-order tracking |
