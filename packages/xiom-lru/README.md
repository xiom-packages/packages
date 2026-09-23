# xiom.lru

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** a bounded least-recently-used cache for `Str` keys and `Int`
> values with O(1) amortized get/put/remove and eviction statistics.
> **Deps:** `xiom.std` only (`xiom.collect.stringmap`).

## What it is

`xiom.lru` is a fixed-capacity recency cache. Key -> node index lives in a
`StringMap`; recency order is a doubly linked list over parallel
`keys`/`values`/`prev`/`next` arenas with a free list, so `lru_put`,
`lru_get` and `lru_remove` are O(1) amortized. `head` is the most recently
used entry, `tail` the eviction victim.

## API

| Function | Returns | Description |
|---|---|---|
| `lru_new(capacity)` | `LruCache` | Empty cache; capacity below 1 clamps to 1. |
| `lru_put(&mut c, key, value)` | `Unit` | Insert or update; entry becomes MRU; evicts the LRU entry when over capacity and increments `evictions`. |
| `lru_get(&mut c, key)` | `Option[Int]` | Promotes on hit (`hits++`), `None` on miss (`misses++`). |
| `lru_peek(c, key)` | `Option[Int]` | Read-only lookup: no promotion, no statistics. |
| `lru_contains(c, key)` | `Bool` | Presence check; no recency or statistics change. |
| `lru_remove(&mut c, key)` | `Bool` | `true` when removed, `false` when absent. |
| `lru_clear(&mut c)` | `Unit` | Drops all entries; keeps capacity and cumulative statistics. |
| `lru_len(c)` | `Int` | Number of live entries. |
| `lru_capacity(c)` | `Int` | Maximum live entries (always >= 1). |
| `lru_hits(c)` | `Int` | Cumulative successful `lru_get` calls. |
| `lru_misses(c)` | `Int` | Cumulative failed `lru_get` calls. |
| `lru_evictions(c)` | `Int` | Cumulative capacity-driven evictions. |
| `lru_keys_mru(c)` | `Vec[Str]` | Live keys, most recently used first. |

## Usage

```xi
use xiom.lru;
use xiom.io;

var cache = lru_new(2);
lru_put(&mut cache, "a", 1);
lru_put(&mut cache, "b", 2);
lru_put(&mut cache, "c", 3);              // evicts "a" (LRU)
io.println(lru_contains(&cache, "a"));    // false
lru_get(&mut cache, "b");                 // promotes "b" to MRU
let keys = lru_keys_mru(&cache);
io.println(keys[0]);                      // "b"
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.lru
```

Expected: the namespaced module passes the section-4 namespace rule, 16
`[PASS]` lines, and a final `port: PASS (passed=16 failed=0 exit=0)`.

## Limitations

- `Str` keys and `Int` values only (XIOM v0.61.x has no generics).
- Capacity is clamped to >= 1; `lru_new(0)` and negatives become 1.
- `lru_clear` intentionally keeps the cumulative hit/miss/eviction counters,
  matching their definition as lifetime statistics.
- Not thread-safe; it is a plain value type with no internal locking.
- No TTL/expiry, no max-by-weight or cost-aware eviction, no iteration over
  values (`lru_keys_mru` is the only enumeration, O(n)).
- The underlying `StringMap` retains dead arena slots internally (stdlib
  design), so its memory tracks total inserts rather than live entries.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
