# xiom.ttl

> **Status:** `incubating` -- implemented and conformance-tested; NOT published yet.
> **Scope:** an in-memory time-to-live cache with lazy and eager expiration,
> capacity-bounded eviction, and hit/miss/expiration statistics.
> **Deps:** `xiom.std` only (uses `xiom.collect.stringmap` and `xiom.time`).

## Scope

`xiom.ttl` stores `Str -> Int` entries that expire after a per-entry TTL.
Expiry is lazy on lookup (`ttl_get`), on demand (`ttl_evict_expired`), and
implicit under capacity pressure (the earliest-expiring entry is evicted when
a full cache receives a new key). Expired entries never count as live in
`ttl_peek`, `ttl_contains`, `ttl_len` or `ttl_remaining_secs`.

## API

| Function | Signature | Description |
|---|---|---|
| `ttl_new` | `(capacity: Int, default_ttl_secs: Int) -> TtlCache` | Create a cache; `capacity >= 1`, `default_ttl_secs >= 0`. |
| `ttl_insert` | `(c: &mut TtlCache, key: Str, value: Int)` | Insert/replace using the default TTL. |
| `ttl_insert_with_ttl` | `(c: &mut TtlCache, key: Str, value: Int, ttl_secs: Int)` | Insert/replace with an explicit TTL; `ttl_secs <= 0` is already expired. |
| `ttl_get` | `(c: &mut TtlCache, key: Str) -> Option[Int]` | Lazy expiry lookup; expired entries are removed and counted (`expirations++`, `misses++`). |
| `ttl_peek` | `(c: &TtlCache, key: Str) -> Option[Int]` | Read-only lookup; `None` when absent or expired, no counter changes. |
| `ttl_evict_expired` | `(c: &mut TtlCache) -> Int` | Eager sweep; returns the number removed (`expirations += count`). |
| `ttl_contains` | `(c: &TtlCache, key: Str) -> Bool` | `false` for expired entries. |
| `ttl_remove` | `(c: &mut TtlCache, key: Str) -> Bool` | `true` only when a live entry was removed; an expired key returns `false` (and is discarded). |
| `ttl_clear` | `(c: &mut TtlCache)` | Remove all entries and reset hits/misses/expirations; capacity and default TTL are kept. |
| `ttl_len` | `(c: &TtlCache) -> Int` | Number of live (unexpired) entries. |
| `ttl_capacity` | `(c: &TtlCache) -> Int` | Configured maximum entries. |
| `ttl_hits` | `(c: &TtlCache) -> Int` | Successful `ttl_get` calls. |
| `ttl_misses` | `(c: &TtlCache) -> Int` | `ttl_get` calls with no live entry. |
| `ttl_expirations` | `(c: &TtlCache) -> Int` | Entries discarded because they had expired. |
| `ttl_remaining_secs` | `(c: &TtlCache, key: Str) -> Option[Int]` | Seconds left in `(0, stored_ttl]`; `None` when absent or expired. |

Full semantics, fields and error paths: [SPEC.md](SPEC.md).

## Usage

```xi
use xiom.ttl;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  var c = ttl_new(128, 60);                 // 128 entries, 60 s default
  ttl_insert(&mut c, "session:42", 7);      // live for 60 s
  ttl_insert_with_ttl(&mut c, "flash", 1, 0); // already expired

  let got = ttl_get(&mut c, "session:42");
  match got {
    Some(v) => { io.println("value " + to_string(v)); },
    None => { io.println("expired"); },
  };

  let swept = ttl_evict_expired(&mut c);    // 1
  io.println("swept " + to_string(swept));
  io.println("live " + to_string(ttl_len(&c)));
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.ttl
```

Expected tail: `port: PASS (passed=14 failed=0 exit=0)`.

Equivalent raw compiler invocation from `packages/xiom-ttl/`:

```
xiom --run tests/test_conformance.xi
```

## Limitations

- Expiry uses the wall clock at **second resolution** (`xiom.time.unix_timestamp`),
  so TTLs are accurate to about one second and an entry with `ttl_secs <= 0`
  is expired immediately. Wall-clock jumps can expire entries early or late.
- Single-threaded: the cache has no locking, so concurrent access is the
  caller's responsibility.
- `ttl_get`, `ttl_evict_expired` and `ttl_len` are `O(stored)` scans --
  the cache is optimized for correctness and small/medium capacities, not
  for millions of keys.
- Only `Str` keys and `Int` values are supported.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
