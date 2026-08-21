# xiom-lockfree

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Lock-free concurrent data structures built on atomic primitives.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `lockfree/queue` | Lock-free queue with safe concurrent enqueue and dequeue |
| `lockfree/stack` | Treiber-style lock-free stack |
| `lockfree/hash` | Concurrent lock-free hash map |
| `lockfree/counter` | Atomic counters and accumulators |
