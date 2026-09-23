# xiom.ttl SPEC

## Package Overview

`xiom.ttl` is an in-memory time-to-live cache for `Str -> Int` entries with
lazy and eager expiration, capacity-bounded eviction, and hit/miss/expiration
statistics. One module: `xiom.ttl` (`src/ttl.xi`).

## Scope

- Store, replace, read, and remove cached integer values keyed by strings.
- Per-entry TTL in whole seconds from the wall clock (`xiom.time.unix_timestamp`).
- Lazy expiry on lookup, eager sweep (`ttl_evict_expired`), and expiry-aware
  capacity eviction.
- Statistics: hits, misses, expirations.

## Non-Goals

- No persistence, no eviction by access recency (LRU), no TTL refresh on read.
- No threads, locks, or atomics (single-threaded callers only).
- No generic value types: values are `Int`, keys are `Str`.
- No monotonic clock: TTL uses wall-clock seconds, not `Instant`.

## Data Model (all fields internal)

`pub type TtlCache` holds:

| Field | Type | Meaning |
|---|---|---|
| `capacity` | `Int` | Maximum stored entries, `>= 1`. |
| `default_ttl` | `Int` | Seconds used by `ttl_insert`, `>= 0`. |
| `index` | `StringMap` | `key -> slot` (xiom.collect.stringmap). |
| `keys` | `Vec[Str]` | `slot -> key`. |
| `values` | `Vec[Int]` | `slot -> value`. |
| `expires` | `Vec[Int]` | `slot -> Unix seconds when the entry dies`. |
| `live` | `Vec[Bool]` | `slot -> stored (not removed)`. |
| `count` | `Int` | Stored entries, expired-but-unswept included. |
| `hits`, `misses`, `expirations` | `Int` | Statistics. |

Slots are appended in insertion order and never reused, so a lower slot index
is an older first insertion; that ordering is the eviction tie-break.
`count` can exceed `ttl_len(c)` while expired entries await a sweep.

## API Signatures

```
pub fn ttl_new(capacity: Int, default_ttl_secs: Int) -> TtlCache
pub fn ttl_insert(c: &mut TtlCache, key: Str, value: Int)
pub fn ttl_insert_with_ttl(c: &mut TtlCache, key: Str, value: Int, ttl_secs: Int)
pub fn ttl_get(c: &mut TtlCache, key: Str) -> Option[Int]
pub fn ttl_peek(c: &TtlCache, key: Str) -> Option[Int]
pub fn ttl_evict_expired(c: &mut TtlCache) -> Int
pub fn ttl_contains(c: &TtlCache, key: Str) -> Bool
pub fn ttl_remove(c: &mut TtlCache, key: Str) -> Bool
pub fn ttl_clear(c: &mut TtlCache)
pub fn ttl_len(c: &TtlCache) -> Int
pub fn ttl_capacity(c: &TtlCache) -> Int
pub fn ttl_hits(c: &TtlCache) -> Int
pub fn ttl_misses(c: &TtlCache) -> Int
pub fn ttl_expirations(c: &TtlCache) -> Int
pub fn ttl_remaining_secs(c: &TtlCache, key: Str) -> Option[Int]
```

## Semantics

- **Expiry predicate:** an entry is expired when `expires_at <= now`
  (`now = unix_timestamp()` at call time). Therefore `ttl_secs == 0` and
  negative TTLs store entries that are already expired.
- **`ttl_new`:** `requires: capacity >= 1 && default_ttl_secs >= 0`.
  There is no other public constructor; a zero capacity would make eviction
  unable to make room, so it is rejected by contract.
- **`ttl_insert` / `ttl_insert_with_ttl`:** insert or replace. Replacing an
  entry updates value and expiry, keeps its slot (so its first-insertion
  order is preserved), and does not touch hit/miss counters. When a *new*
  key arrives and `count >= capacity`, entries are evicted until a slot
  frees: the earliest `expires_at` goes first; ties go to the older
  insertion. Evicting an already-expired entry counts in `expirations`;
  evicting a live one does not.
- **`ttl_get`:** live entry -> `Some(value)`, `hits++`. Expired entry ->
  removed, `expirations++`, `misses++`, `None`. Absent -> `misses++`, `None`.
- **`ttl_peek`:** no mutation of any kind; `None` when absent or expired.
- **`ttl_evict_expired`:** removes every expired entry and returns the count;
  `expirations` increases by the same count.
- **`ttl_contains`:** true only for live entries; no mutation, no counters.
- **`ttl_remove`:** live entry -> removed, `true`. Stored-but-expired entry ->
  discarded and counted in `expirations`, returns `false` (it was logically
  absent). Absent key -> `false` no-op.
- **`ttl_clear`:** clears entries and resets `hits`, `misses`, `expirations`
  to 0; `capacity` and `default_ttl` are preserved.
- **`ttl_len`:** counts stored, unexpired entries (`O(stored)` scan).
- **`ttl_remaining_secs`:** `Some(expires_at - now)` in `(0, stored_ttl]` for
  live entries; `None` when absent or expired.

## Error Paths

The API is total: there are no `Result` returns and no panics at runtime.
Invalid configuration is expressed as a `requires` contract on `ttl_new`
(`capacity >= 1`, `default_ttl_secs >= 0`); all other operations are
well-defined for every state, including absent keys, expired keys, and
empty caches. A caller that bypasses `ttl_new` and constructs a `TtlCache`
literal with `capacity < 1` violates the documented invariant.

## Test Plan

`tests/test_conformance.xi` (14 deterministic tests, no sleeping; expiry is
forced with `ttl_secs <= 0`, liveness with TTLs of 30..1000 s):

| Test | Checks |
|---|---|
| ttl 0 expires immediately | `ttl_get` None, `expirations=1`, `misses=1` |
| negative ttl | already expired on insert |
| large ttl is live | value 42 returned, `hits=1` |
| peek on expired | None with no counter/len changes (peek cannot mutate: it takes `&TtlCache`; lazy removal is covered by the next test) |
| evict_expired count | 2 expired + 1 live -> returns 2, `expirations=2`, `len=1` |
| get on expired | `expirations` and `misses` increment, entry removed |
| hits on live get | 2 gets -> `hits=2`, `misses=0` |
| len excludes expired | live+expired stored -> `len=1` |
| remaining_secs | in `(0, ttl]` when live; None when absent/expired |
| capacity eviction | full cache keeps the two latest-expiry entries, `capacity` honored |
| remove | live -> true; second remove -> false; `len=0` |
| clear | entries and statistics reset, capacity preserved |
| contains on expired | true for live, false for expired |
| insert_with_ttl override | explicit ttl beats the default |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.ttl
```

Expected: `port: PASS (passed=14 failed=0 exit=0)`.

## Known Limitations

- **Second-resolution wall clock.** `unix_timestamp()` has 1-second
  granularity, and is not monotonic: clock adjustments can expire entries
  early or late. TTL 0 means "expires at the current second", so an entry
  inserted with `ttl_secs == 0` may be observed as expired in the same
  second (by design, tested).
- **No concurrency support.** No locking; callers must serialize access or
  keep one cache per thread.
- **Linear scans.** `ttl_get`, `ttl_evict_expired` and `ttl_len` scan every
  stored slot (`O(stored)`); `ttl_find`-style random access is `O(1)` via
  the `StringMap`.
- **Memory is not reclaimed eagerly.** Eviction marks slots dead; arena
  memory and the key `Str` handles remain referenced until `ttl_clear`
  replaces the arenas (removed keys are unlinked from the map immediately).
- **`ttl_remove` of an expired key returns false** while still discarding the
  stale record and incrementing `expirations`; this is a deliberate
  "logically absent" choice (see Semantics).
- **`clear` resets statistics** as well as entries; only the capacity and
  default TTL survive.
