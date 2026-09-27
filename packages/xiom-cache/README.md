# xiom.cache

Deterministic in-memory cache eviction structures over `Int` keys and `Int`
values: **LRU**, **LFU**, **CLOCK** (second chance) and **TTL**. No threads,
no clocks, no FFI: every decision follows from the call sequence alone.

> **Status:** implemented, `0.1.0`. Conformance suite: 26 checks, all green on
> compiler v0.61.3. See `SPEC.md` for the full data model, semantics, ordering
> guarantees and error catalog.

## Scope

* Four capacity-bounded policies with a uniform API:
  `create / put / get / peek / remove / evict_one / clear / len / contains /
  capacity / stats / last_evicted` (LRU additionally has `touch`).
* Integer-only state, deterministic eviction order, and an eviction log
  (`<policy>_last_evicted`) designed for tests and diagnostics.
* TTL is tick-based: entries carry absolute `expire_at` ticks and the caller
  passes `now`; there is no hidden wall clock. `ttl_sweep(now)` evicts expired
  entries in insertion order.
* `peek` never changes policy state or counters; `get` is the only operation
  that moves `hits`/`misses`.

Not in scope (honest limits):

* **One live instance per policy.** Each policy is module-level singleton
  state, like the `xiom.timer` wheel; `lru_create` resets the LRU cache, it
  does not mint a second one. The four policies are independent of each other.
* Keys and values are `Int` only; there is no generic or `Str` key support and
  no serialization.
* No background expiry: expired TTL entries are removed by `ttl_sweep`, by
  `ttl_get`, by `ttl_put` over an expired key, or by `ttl_evict_one`.
* LFU/CLOCK/TTL find keys by scanning the slot table (`O(capacity)`); only LRU
  is `O(1)` expected. See the complexity table in `SPEC.md`.

## Usage

```xiom
use xiom.cache;
use xiom.io;

fn main() -> Int {
  let r = lru_create(2);
  if !r.is_ok { return 1; }
  let a = lru_put(10, 100);
  let b = lru_put(20, 200);
  let g = lru_get(10);            // hit: moves 10 to the MRU end
  let c = lru_put(30, 300);       // full: evicts 20 (least recently used)
  io.println("evicted: " + lru_last_evicted().value);
  let s = lru_stats();
  io.println("hits/size: " + s.hits + "/" + s.size);
  return 0;
}
```

TTL usage: ticks are yours to define (a logical counter, a frame number, a
monotonic millisecond bucket, ...).

```xiom
let tc = ttl_create(64);
let p = ttl_put(7, 700, 0, 30);   // key 7 expires at tick 30
let g = ttl_get(7, 29);           // Ok(700)
let e = ttl_get(7, 30);           // Err(code 4, maybe_expired) + eviction
let w = ttl_sweep(100);           // Ok(n) removed, insertion order
```

## API at a glance

| Operation | LRU | LFU | CLOCK | TTL |
|-----------|-----|-----|-------|-----|
| create(capacity) | `lru_create` | `lfu_create` | `clock_create` | `ttl_create` |
| put | `lru_put(k,v)` | `lfu_put(k,v)` | `clock_put(k,v)` | `ttl_put(k,v,now,expire_at)` |
| get | `lru_get(k)` | `lfu_get(k)` | `clock_get(k)` | `ttl_get(k,now)` |
| peek | `lru_peek(k)` | `lfu_peek(k)` | `clock_peek(k)` | `ttl_peek(k,now)` |
| remove | `lru_remove(k)` | `lfu_remove(k)` | `clock_remove(k)` | `ttl_remove(k)` |
| evict_one | `lru_evict_one` | `lfu_evict_one` | `clock_evict_one` | `ttl_evict_one` |
| clear / len / contains | `lru_*` | `lfu_*` | `clock_*` | `ttl_*` |
| capacity / stats / last_evicted | `lru_*` | `lfu_*` | `clock_*` | `ttl_*` |

All fallible operations return `Result[Int, CacheError]`; `CacheStats` is
returned by value; `cache_error_message(code)` pins every message and
`cache_max_capacity()` is 1048576.

## Testing

From the repository root:

```powershell
.\scripts\port.ps1 -Package xiom.cache
```
