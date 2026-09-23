# xiom.lru -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.lru` (`src/lru.xi`). Manifest: `package.xi` (name `xiom.lru`,
version `0.1.0`). Depends on `xiom.std` (`xiom.collect.stringmap`).

## Scope

A bounded least-recently-used cache over `Str` keys and `Int` values:

- fixed capacity fixed at construction, clamped to a minimum of 1;
- O(1) amortized `lru_put`, `lru_get`, `lru_peek`, `lru_contains`,
  `lru_remove`;
- recency promotion on `lru_get` and on updates through `lru_put`;
- eviction of the least recently used entry when a new key exceeds capacity;
- cumulative statistics: hits, misses, evictions;
- enumeration of live keys in most-recent-first order (`lru_keys_mru`, O(n)).

## Non-goals

- Generics (not available in XIOM v0.61.x): keys are `Str`, values `Int`.
- Thread safety, concurrent access, or internal locking.
- TTL/expiry, max-by-weight, cost-aware or frequency-aware eviction
  (`xiom.collect.tinylfu` covers admission filtering separately).
- Serialization, persistence, or iteration over values.
- Dynamic capacity changes after construction.

## API signatures

All functions are free functions in module `xiom.lru`:

```xi
pub type LruCache = { capacity: Int; map: StringMap; keys: Vec[Str];
  values: Vec[Int]; prev: Vec[Int]; next: Vec[Int]; free: Vec[Int];
  head: Int; tail: Int; size: Int; hits: Int; misses: Int;
  evictions: Int; }

pub fn lru_new(capacity: Int) -> LruCache
pub fn lru_put(c: &mut LruCache, key: Str, value: Int)
pub fn lru_get(c: &mut LruCache, key: Str) -> Option[Int]
pub fn lru_peek(c: &LruCache, key: Str) -> Option[Int]
pub fn lru_contains(c: &LruCache, key: Str) -> Bool
pub fn lru_remove(c: &mut LruCache, key: Str) -> Bool
pub fn lru_clear(c: &mut LruCache)
pub fn lru_len(c: &LruCache) -> Int
pub fn lru_capacity(c: &LruCache) -> Int
pub fn lru_hits(c: &LruCache) -> Int
pub fn lru_misses(c: &LruCache) -> Int
pub fn lru_evictions(c: &LruCache) -> Int
pub fn lru_keys_mru(c: &LruCache) -> Vec[Str]
```

`LruCache` is an opaque value type; all fields are internal implementation
details and must not be touched by callers.

## Representation

- `map: StringMap` stores `key -> node index` (stdlib SipHash-2-4 map).
- `keys`/`values`/`prev`/`next` are index-aligned node arenas forming a
  doubly linked list. `head` is MRU, `tail` is LRU, `-1` terminates.
- `free` is a free list of node indices released by `lru_remove`,
  `lru_clear` and `_evict_lru`; `_node_alloc` reuses them before growing the
  arenas.
- `size` mirrors the number of live nodes and equals the number of live
  `StringMap` entries.

## Semantics

`lru_new(capacity)`
: Returns an empty cache. `capacity < 1` is clamped to 1. All statistics
  start at 0. No error path.

`lru_put(c, key, value)`
: Existing key: value is replaced in place, the node is promoted to MRU, no
  eviction occurs, statistics are unchanged.
  New key: when `size == capacity`, the LRU (tail) entry is removed and
  `evictions` is incremented first, then the new entry is inserted at MRU.
  Total live entries never exceed capacity.

`lru_get(c, key)`
: Hit: the node is promoted to MRU, `hits` is incremented, `Some(value)` is
  returned. Miss: `misses` is incremented, `None` is returned. Absent keys
  are never an error.

`lru_peek(c, key)`
: Returns `Some(value)` or `None`; recency order and all statistics are
  untouched. Safe to call through an immutable reference.

`lru_contains(c, key)`
: True iff a live entry exists; no side effects.

`lru_remove(c, key)`
: Removed: the map entry is dropped, the node unlinked and pushed on the
  free list, `size` decremented, `true` returned. Absent: no state change,
  `false` returned. Statistics are untouched.

`lru_clear(c)`
: Removes every entry and resets recency and the free list. Capacity is
  preserved. Cumulative `hits`/`misses`/`evictions` are intentionally
  retained (lifetime statistics); construct a new cache for zeroed counters.

Statistics getters
: `lru_hits`, `lru_misses`, `lru_evictions` return the cumulative counters.
  Only `lru_get` moves hits/misses; only capacity-driven evictions in
  `lru_put` move `evictions`.

`lru_keys_mru(c)`
: Returns a fresh `Vec[Str]` with live keys from MRU to LRU; empty for an
  empty cache.

Error paths: none. There are no panicking inputs; sub-1 capacity is clamped,
absent keys yield `None`/`false`, and duplicate keys update in place.

## Complexity

| Operation | Complexity |
|---|---|
| `lru_new` | O(1) |
| `lru_put` / `lru_get` / `lru_peek` / `lru_contains` / `lru_remove` | O(1) amortized |
| `lru_len` / `lru_capacity` / `lru_hits` / `lru_misses` / `lru_evictions` | O(1) |
| `lru_clear` | O(n) |
| `lru_keys_mru` | O(n) |

## Test plan

`tests/test_conformance.xi` (`module lru_tests`, 16 named checks, hello-style
`main` that prints `[PASS]`/`[FAIL]` per check, a summary line, and returns
the failure count):

1. capacity 1 keeps only the newest entry;
2. capacity below 1 clamps to 1;
3. evicts the least recently used entry;
4. `lru_get` promotes the entry to MRU;
5. put on existing key updates value without eviction;
6. put on existing key keeps it MRU;
7. `lru_peek` does not promote recency;
8. `lru_peek` changes no statistics;
9. remove existing key returns true and frees it;
10. remove absent key returns false and changes nothing;
11. `lru_clear` drops entries, keeps capacity and statistics;
12. `lru_len` tracks live entries;
13. hits and misses are counted per `lru_get`;
14. `lru_evictions` counts only capacity-driven evictions;
15. `lru_keys_mru` is ordered most recent first;
16. duplicate puts do not grow `len`.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.lru
```

Last verified: compiler 0.61.3, `port: PASS (passed=16 failed=0 exit=0)`.

## Known limitations

- `Str` keys / `Int` values only; no generics in the language.
- Capacity is fixed at construction and clamped to >= 1; the effective
  capacity of a requested value < 1 is 1.
- `lru_clear` keeps cumulative statistics by design (see semantics).
- Not thread-safe.
- The stdlib `StringMap` never compacts: removed/evicted keys leave dead
  slots in its internal arenas, so map memory tracks total inserts. The LRU
  own arenas do reuse slots via the free list.
- Enumeration copies keys (`lru_keys_mru`), and there is no values iterator.

## Compiler / stdlib notes for v0.61.3

- `str_compare` lives in `xiom.string.compare`; `use xiom.string;` does not
  export it. Tests import `xiom.string.compare` and call
  `compare.str_compare(a, b)`. This deviates from the porter brief, which
  listed `str_compare` under `use xiom.string;`.
- Vec-sourced `Str` elements are compared only via `str_compare` (BUG 17:
  `==` between `Str` values read from a `Vec` lowers to a pointer compare).
- Advisory warning E001 ("cannot borrow as mutable while immutably
  borrowed") is emitted when a `&local` call is followed by `&mut local` in
  the same function. The tests therefore route read-only checks through tiny
  helpers that take `&mut LruCache` and call the real `&LruCache` API
  internally; the final harness run is warning-free.
- `&mut` on a struct field passed to a free function is safe here
  (`string_map_put(&mut c.map, ...)`), unlike the `&mut Vec` copy issue
  documented as BUG 16 in the stdlib (which this module avoids by never
  passing its arena vectors as `&mut Vec` arguments).
