# xiom.cache -- specification

Version 0.1.0. Module `xiom.cache`. Compiler baseline v0.61.3.

This document is the source of truth for the data model, per-policy semantics,
ordering guarantees and the error catalog. The README is the entry point; the
conformance suite in `tests/test_conformance.xi` pins every rule stated here.

## 1. Identity and scope

* Package `xiom.cache`, category `data`, module `xiom.cache`.
* Deterministic in-memory cache eviction structures over `Int` keys and `Int`
  values. No threads, no clocks, no FFI, no allocation after creation.
* Four policies: LRU, LFU, CLOCK, TTL. Uniform API per policy.

## 2. State model

### 2.1 Singleton policies

Each policy owns module-level state (the `xiom.timer` wheel pattern). There is
one live instance per policy, and the four policies never interact.

* `<policy>_create(capacity)` is a full reset of that policy: entries,
  counters and the last-evicted record are all rebuilt for `capacity` slots.
  It returns `Ok(capacity)`.
* On invalid capacity the call returns `Err` and the previous state of that
  policy is left untouched.
* If no create has happened yet, the first operation on a policy lazily builds
  a default cache with capacity 16 (documented behavior, not an error).
* `<policy>_clear()` is a full reset too, preserving the capacity; `<policy>_len()`
  becomes 0, all counters reset, and `<policy>_last_evicted()` goes back to the
  `no eviction yet` error.

### 2.2 Slot table and free list

Every policy preallocates `capacity` slots at create time, held in parallel
`Vec[Int]` arrays (no `Vec[StructType]`, no per-entry heap nodes):

* `keys` / `vals`: payload of a slot; meaningful only while `alive == 1`.
* `alive`: `1` for live slots, `0` for free slots.
* A free list threads free slots through one integer vector (the policy's
  "link" array; LRU reuses `hnext`). `create` builds the free list
  `0 -> 1 -> ... -> capacity-1`; removing or evicting an entry pushes its slot
  back to the head, so slots are reused.
* Removed key/value residue in free slots is ignored: every scan checks
  `alive` (and `find` also compares the key).

A live entry's `find` result is its slot index; `-1` (`_CA_NONE`) means absent.

### 2.3 Counters and the eviction log

`CacheStats = { hits; misses; evictions; size }`, returned by value:

| Field | Moved by |
|-------|----------|
| `hits` | `get` on a usable entry |
| `misses` | `get` when no usable entry is found: unknown key, or (TTL) a present-but-expired entry |
| `evictions` | policy removals: `evict_one`, capacity replacement during `put`, expired removals (`ttl_get` / `ttl_put` / `ttl_sweep`), CLOCK/LRU/FIFO policy removals |
| `size` | current physically present entry count (`len`) |

`peek`, `contains`, `len`, `capacity`, `stats`, `touch` (LRU) and explicit
`remove`/`clear` never move `hits`/`misses`. Explicit `remove` and `clear` are
**not** evictions.

Every policy eviction records its key. `<policy>_last_evicted()` returns
`Ok(key)` for the most recent eviction since the last create/clear, or
`Err(code 6, key = -1, detail = -1)` when none has happened.

`put` returns `Ok(evicted)` where `evicted` is the number of evictions that
call caused (`0` or `1` in every policy).

## 3. Error catalog

`CacheError = { code: Int; key: Int; detail: Int }`. `detail` and `key` carry
the offending values where the rule mentions them, else `-1`.

| Code | Message | Raised by | key | detail |
|------|---------|-----------|-----|--------|
| 1 | `cache: capacity must be positive` | `<policy>_create(capacity <= 0)` | -1 | capacity |
| 2 | `cache: capacity exceeds maximum` | `<policy>_create(capacity > 1048576)` | -1 | capacity |
| 3 | `cache: unknown key` | `get`/`peek`/`remove`/`touch` on an absent key | key | -1 |
| 4 | `cache: entry expired` | `ttl_get`/`ttl_peek` on a present entry with `exp <= now` | key | stale `exp` |
| 5 | `cache: cache is empty` | `<policy>_evict_one` with no live entries | -1 | -1 |
| 6 | `cache: no eviction yet` | `<policy>_last_evicted` before any eviction | -1 | -1 |
| 7 | `cache: expiry must be in the future` | `ttl_put` with `expire_at <= now` | key | `expire_at` |

Codes outside 1..7 map to `cache: unknown error` in
`cache_error_message(code)`.

`cache_max_capacity()` returns 1048576 (2^20). Capacities above it are
rejected with code 2; capacities below 1 with code 1.

## 4. LRU

### 4.1 Data model

Parallel `Vec[Int]` fields of length `capacity`:

* `keys`, `vals` -- payload per slot.
* `prev`, `next` -- doubly linked **recency list**; `head` (`prev == -1`) is
  the least recently used slot, `tail` (`next == -1`) the most recently used.
* `buckets` -- hash-index bucket heads, length `capacity`.
* `hnext`, `hprev` -- separate-chaining **hash index** links. While a slot is
  free, `hnext` is the free-list link and `hprev` is `-1`.
* `alive` -- `0/1`.

Hash: `bucket(key) = mix(key) % capacity`, where `mix` reduces the key to a
non-negative 32-bit value and applies two multiplicative rounds plus
add-shift finalization (exact 32x32 modular arithmetic via 16-bit halves).
The index is internal: no API exposes bucket counts or hash values.

### 4.2 Semantics

* `put(key, value)`:
  * existing key: replace value, move the slot to the MRU tail, `Ok(0)`.
  * new key, `size < capacity`: allocate a free slot, insert, `Ok(0)`.
  * new key, cache full: evict the recency-list **head** (least recently
    used), record it, insert the new key at the tail, `Ok(1)`.
* `get(key)`: on a hit, return the value and move the slot to the tail
  (`hits+1`); on a miss, `Err(3)` (`misses+1`).
* `peek(key)`: return the value without touching recency or counters;
  `Err(3)` when absent.
* `touch(key)`: move to the tail without touching `hits`; `Err(3)` when absent.
* `remove(key)`: unlink from both lists, release the slot, return the old
  value; not an eviction; `Err(3)` when absent.
* `evict_one()`: evict the head, return the key; `Err(5)` when empty.
* `clear()`: full reset, capacity preserved.

### 4.3 Complexity

`O(1)` expected per operation: find and unlink use `hprev`/`hnext`, recency
updates use `prev`/`next`, allocation uses the free-list head. `create`/`clear`
are `O(capacity)`.

## 5. LFU

### 5.1 Data model

Parallel `Vec[Int]` fields of length `capacity`:

* `keys`, `vals` -- payload per slot.
* `freq` -- access count: `1` on insert, `+1` on every `get` hit and every
  `put` over an existing key.
* `seq` -- insertion ordinal, assigned at **first** insert from a per-epoch
  counter; preserved across updates. Smaller `seq` = earlier first insert.
* `alive`, `link` (free list).

### 5.2 Semantics

* Victim = live slot minimizing `(freq, seq)` lexicographically: lowest
  frequency first; among equal frequencies, the earliest first insert.
* `put` over an existing key replaces the value, raises `freq` by 1 and keeps
  `seq`. `put` over a full cache evicts the victim first (`Ok(1)`).
* `get` hit raises `freq`; `peek` does not. `remove` releases the slot; a
  later re-insert of the same key gets a fresh `freq = 1` and a new `seq`.
* `evict_one()` evicts the victim and returns its key; `Err(5)` when empty.

### 5.3 Complexity

`find`, `put`, `evict_one` and the tie-break scan are `O(capacity)`; `len`,
`capacity` and `stats` are `O(1)`.

## 6. CLOCK (second chance)

### 6.1 Data model

Parallel `Vec[Int]` fields of length `capacity`:

* `keys`, `vals` -- payload per slot.
* `ref` -- `0/1` reference bit.
* `alive`, `link` (free list).
* `hand` -- slot index the sweep inspects next; reset to `0` by create/clear.

### 6.2 Semantics

* A new insert or an update sets `ref = 1`; a `get` hit sets `ref = 1`.
  `peek` does not touch `ref`.
* `evict_one()` / the capacity replacement in `put` run one hand sweep:
  * inspect the slot at `hand`, then advance `hand` by one (mod capacity);
  * free slots are skipped (the hand still advances);
  * a live slot with `ref == 1` gets a **second chance**: `ref` is set to `0`
    and the sweep continues;
  * the first live slot with `ref == 0` is evicted.
* The sweep inspects at most `2 * capacity` slots, so it always terminates:
  after one full pass every live slot has `ref == 0` (unless it was re-set,
  which cannot happen inside a sweep), and the next pass evicts one.
  `ref` bits cleared by a sweep stay cleared until a future `get`/`put`.
* `evict_one()` returns the victim's key; `Err(5)` when empty.

### 6.3 Complexity

`O(capacity)` per operation (find scan and sweep). `create`/`clear` `O(capacity)`.

## 7. TTL

### 7.1 Data model

Parallel `Vec[Int]` fields of length `capacity`:

* `keys`, `vals` -- payload per slot.
* `exp` -- absolute expire tick. An entry is **expired** at tick `now` when
  `exp <= now`.
* `prev`, `next` -- doubly linked **insertion-order list**: head is the
  oldest insertion, tail the newest. `next` doubles as the free-list link
  while a slot is free.
* `alive` -- `0/1`.

Ticks are plain `Int`s supplied by the caller; negative ticks are legal and no
tick arithmetic overflows in practice (`exp - now` is never computed; all
comparisons use `exp <= now` directly).

### 7.2 Physical vs logical presence

* **Logically present and usable**: `alive == 1` and `exp > now`.
* **Physically present but expired**: `alive == 1` and `exp <= now`. It still
  occupies capacity and counts in `len`/`stats.size` until it is removed by
  `ttl_sweep`, `ttl_get`, `ttl_evict_one`, `ttl_put` (over that key), or
  `ttl_remove`.
* `ttl_contains(key, now)` is false for expired entries; `ttl_peek` returns
  `Err(4)` without removing anything or moving counters.

### 7.3 Semantics

* `ttl_put(key, value, now, expire_at)`:
  * rejects `expire_at <= now` with `Err(7)`, state unchanged;
  * existing live key: replace value and expiry; the entry becomes the
    **newest** in insertion order; `Ok(0)`;
  * existing expired key: the stale entry is removed as an **eviction**
    (recorded), then the key is inserted fresh; `Ok(1)`;
  * new key with room: insert, appended as newest; `Ok(0)`;
  * new key and full: evict the live entry with the **smallest expire tick**,
    ties broken by insertion order (oldest first), record it, then insert;
    `Ok(1)`.
* `ttl_get(key, now)`:
  * usable entry: return value, `hits+1`;
  * absent: `Err(3)`, `misses+1`;
  * present but expired: remove it as an eviction (`evictions+1`, recorded),
    `misses+1`, and return `Err(4)` with `detail = exp`. This is
    **expired-on-get**: the stale value is never served.
* `ttl_peek(key, now)`: usable -> `Ok(value)`; absent -> `Err(3)`; expired ->
  `Err(4)` with no state change at all.
* `ttl_remove(key)`: removes whatever is physically present (live or expired)
  and returns its stored value; explicitly requested, so **not an eviction**;
  `Err(3)` when absent.
* `ttl_evict_one()`: evicts the smallest-expire entry, ties by insertion
  order; returns its key; `Err(5)` when empty. Expiry is not consulted: an
  expired entry is simply the earliest candidate.
* `ttl_sweep(now)`: walks the insertion-order list from the oldest entry and
  evicts every entry with `exp <= now` in that order. Returns
  `Ok(swept)` with the number removed (`0` is normal). Each removal is a
  recorded eviction; after the call `last_evicted` holds the last key swept.

### 7.4 Complexity

`O(capacity)` per operation; `ttl_sweep` is `O(number of live entries)` for
the walk plus `O(1)` per eviction.

## 8. Ordering guarantees

Everything is deterministic. Given the same call sequence, the same state and
the same results are produced on every run:

1. **LRU** evicts the least recently used slot; the recency list is exact.
2. **LFU** evicts the live slot with the minimum `(freq, seq)`.
3. **CLOCK** sweeps from the current hand, wrapping modulo capacity; the
   sweep order is fixed, and only free-slot skipping affects it.
4. **TTL** sweep and capacity eviction walk in insertion order, where every
   successful `ttl_put` makes its entry newest.
5. Hash-index iteration is never exposed; bucket layout cannot leak into
   observable behavior. Evictions, removals and sweep counts are fully
   reproducible from the call sequence.
6. `last_evicted` and the counters are exact; no operation is affected by
   timing, allocation addresses or external state.

## 9. API matrix

For P in {`lru`, `lfu`, `clock`, `ttl`}:

| Function | Returns | Fallible |
|----------|---------|----------|
| `P_create(capacity)` | `Result[Int, CacheError]` (`Ok(capacity)`) | yes |
| `P_put(key, value)` (TTL: `+ now, expire_at`) | `Result[Int, CacheError]` (`Ok(evicted)`) | TTL yes |
| `P_get(key)` (TTL: `+ now`) | `Result[Int, CacheError]` (`Ok(value)`) | yes |
| `P_peek(key)` (TTL: `+ now`) | `Result[Int, CacheError]` (`Ok(value)`) | yes |
| `P_remove(key)` | `Result[Int, CacheError]` (`Ok(value)`) | yes |
| `P_evict_one()` | `Result[Int, CacheError]` (`Ok(key)`) | yes |
| `P_clear()` | (none) | no |
| `P_len()` | `Int` | no |
| `P_capacity()` | `Int` | no |
| `P_contains(key)` (TTL: `+ now`) | `Bool` | no |
| `P_stats()` | `CacheStats` | no |
| `P_last_evicted()` | `Result[Int, CacheError]` (`Ok(key)`) | yes |
| `lru_touch(key)` | `Result[Int, CacheError]` (`Ok(value)`) | yes |

Shared: `cache_max_capacity() -> Int`, `cache_error_message(code) -> Str`.

## 10. Known limitations

* One live instance per policy (module-level state). Multiple concurrent
  caches require driving one policy per module instance or a future
  handle-based API.
* Int-only keys and values; no `Str` keys, no serialization, no persistence.
* LFU/CLOCK/TTL are linear-scan lookups; only LRU is `O(1)` expected.
* TTL does not expire anything by itself: without `ttl_sweep` (or a `get` /
  `put` / `evict_one` touch) expired entries keep occupying capacity.
