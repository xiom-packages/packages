# xiom.rate -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.rate` (`src/rate.xi`). Manifest: `package.xi` (name `xiom.rate`,
version `0.1.0`). Depends on `xiom.std` (no library imports; tests use
`xiom.test` and `xiom.io`).

## Scope

A pure deterministic rate-limit policy engine with explicit clocks:

- token bucket with millisecond refill, saturation clamp, and a defined
  truncation-carry policy;
- affordability/retry queries for a requested cost;
- fixed-window counter with a span rebased when it has fully elapsed;
- bookkeeping accessors (tokens, capacity, window count).

Everything is caller-owned values and explicit inputs; the module performs no
I/O, no sleeping, and no clock or environment access.

## Non-goals

- Reading a clock, sleeping, or scheduling: the caller owns time and waiting.
- Blocking, queueing, or delaying calls: only admit/reject decisions.
- Distributed or cross-process budgets; shared memory or locking.
- Persistence: no file, environment, or registry state.
- Non-integer time or rates; `Float` types are excluded.
- Sliding-window (log) rate limiting: the window here is a fixed span.

## API signatures

All functions are free functions in module `xiom.rate`:

```xi
pub type TokenBucket = { capacity: Int; tokens: Int; refill_per_sec: Int; last_ms: Int; }
pub type WindowLimit = { window_ms: Int; max_count: Int; start_ms: Int; count: Int; }

pub fn rate_bucket_new(capacity: Int, refill_per_sec: Int, now_ms: Int) -> TokenBucket
pub fn rate_bucket_refill(b: &mut TokenBucket, now_ms: Int)
pub fn rate_bucket_allow(b: &mut TokenBucket, now_ms: Int, cost: Int) -> Bool
pub fn rate_bucket_tokens(b: &TokenBucket) -> Int
pub fn rate_bucket_capacity(b: &TokenBucket) -> Int
pub fn rate_bucket_retry_after_ms(b: &TokenBucket, cost: Int) -> Int
pub fn rate_window_new(window_ms: Int, max_count: Int, now_ms: Int) -> WindowLimit
pub fn rate_window_allow(w: &mut WindowLimit, now_ms: Int) -> Bool
pub fn rate_window_count(w: &WindowLimit) -> Int
pub fn rate_window_retry_after_ms(w: &WindowLimit, now_ms: Int) -> Int
pub fn rate_window_reset(w: &mut WindowLimit, now_ms: Int)
```

Both types are opaque value types: fields are internal implementation details
and callers use the constructors and accessors.

## Algorithms

### Token bucket

State: `capacity >= 1`, `0 <= tokens <= capacity`, `refill_per_sec >= 0`,
`last_ms` is the last settled millisecond.

`rate_bucket_new(capacity, refill_per_sec, now_ms)` clamps `capacity >= 1` and
`refill_per_sec >= 0`, sets `tokens = capacity` (starts full) and
`last_ms = now_ms`.

`rate_bucket_refill(b, now_ms)`:

1. `if now_ms <= last_ms: return` (time going backwards or standing still is a
   no-op).
2. `elapsed = now_ms - last_ms`.
3. `if refill_per_sec == 0: last_ms = now_ms; return` (no refill; consume the
   whole span).
4. `if tokens >= capacity: last_ms = now_ms; return` (already saturated;
   consume the whole span).
5. `gained = elapsed * refill_per_sec / 1000` (truncated).
6. `if gained <= 0: return` (nothing earned; carry the whole span).
7. `if tokens + gained >= capacity: tokens = capacity; last_ms = now_ms;
   return` (saturation; consume the whole span).
8. `tokens = tokens + gained`;
   `last_ms = last_ms + gained * 1000 / refill_per_sec`.

`rate_bucket_allow(b, now_ms, cost)`:

1. `rate_bucket_refill(b, now_ms)` (allow always refills first).
2. `if cost <= 0: return true` (spends nothing).
3. `if tokens >= cost: tokens = tokens - cost; return true`.
4. `return false` (nothing spent; the bucket is unchanged apart from step 1).

`rate_bucket_retry_after_ms(b, cost)` (read-only, no refill):

1. `if cost <= 0: return 0`.
2. `if tokens >= cost: return 0`.
3. `if refill_per_sec <= 0: return -1` (the cost can never be met).
4. `deficit = cost - tokens`;
   `whole = deficit / refill_per_sec`, `remainder = deficit % refill_per_sec`;
   `ms = whole * 1000`, and when `remainder > 0`
   `ms = ms + (remainder * 1000 + refill_per_sec - 1) / refill_per_sec`.
   This is exactly `ceil(deficit * 1000 / refill_per_sec)` computed without
   forming the product `deficit * 1000`, so large deficits do not overflow.

### Truncation and carry rules (normative)

- Refill is truncated: `gained` uses floor division, so a bucket accrues
  exactly `floor(elapsed_ms * refill_per_sec / 1000)` whole tokens.
- When `gained == 0` the elapsed span is **not** consumed: at `now_ms = 500`
  with `refill_per_sec = 1` a bucket that was emptied at 0 still has 0 tokens
  and `last_ms` is still 0, so the first token lands exactly at 1000 ms. This
  is pinned by test 4.
- When tokens are granted and the bucket does not saturate, only the
  milliseconds the granted tokens are worth are consumed
  (`consumed_ms = gained * 1000 / refill_per_sec`, truncated), and the
  unearned remainder stays in `last_ms`. For `refill_per_sec <= 1000` this
  keeps accrual exact up to less than one token of carried residue, e.g.
  `refill_per_sec = 3`: at 1000 ms tokens = 3, at 1334 ms tokens = 4, at
  2000 ms tokens = 6.
- The whole elapsed span is consumed only when `refill_per_sec == 0` or the
  bucket is saturated (already full, or filled by this call). Saturation
  discards excess accrual; since the bucket is full, no usable credit is lost.
- `retry_after_ms` rounds up to a whole millisecond. At `now_ms = 500` with
  `refill_per_sec = 1` and 0 tokens it reports 1000 ms, even though the
  carried millisecond makes the actual wait 500 ms: the result is an upper
  bound whenever a sub-token residue is carried.
- Integer resolution: for `refill_per_sec > 1000` the sub-millisecond accrual
  interval cannot be represented, so the carried residue truncates to zero and
  the same elapsed millisecond can be counted once more on the next call
  (granting at most `refill_per_sec / 1000` extra tokens per call). Configure
  rates at or below 1000 tokens/sec for exact accounting; the conformance
  suite pins behaviour at `refill_per_sec <= 1000`.

### Fixed window

State: `window_ms >= 1`, `max_count >= 1`, `count <= max_count`, `start_ms`
starts the current span.

`rate_window_new(window_ms, max_count, now_ms)` clamps `window_ms >= 1` and
`max_count >= 1`, sets `count = 0`, `start_ms = now_ms`.

`rate_window_allow(w, now_ms)`:

1. `if now_ms - start_ms >= window_ms: start_ms = now_ms; count = 0`
   (rebases at the first call at or after the boundary; `now_ms < start_ms`
   never rebases).
2. `if count < max_count: count = count + 1; return true`.
3. `return false`.

`rate_window_retry_after_ms(w, now_ms)` (read-only):
`if count < max_count: return 0`; `if now_ms - start_ms >= window_ms:
return 0`; otherwise `return start_ms + window_ms - now_ms`.

`rate_window_reset(w, now_ms)` sets `start_ms = now_ms` and `count = 0`.
`rate_window_count(w)` returns `count`.

### Clock policy summary

- Time is always an explicit integer-millisecond input; the module has no
  clock.
- Backwards time is a no-op for the bucket refill; for the window it never
  rebases and only affects the documented `start_ms + window_ms - now_ms`
  arithmetic.
- Windows rebase at the first admitted-or-rejected call at or after the
  boundary, not on a timer.

## Complexity

| Operation | Complexity |
|---|---|
| `rate_bucket_new`, `rate_bucket_tokens`, `rate_bucket_capacity` | O(1) |
| `rate_bucket_refill`, `rate_bucket_allow`, `rate_bucket_retry_after_ms` | O(1) |
| `rate_window_new`, `rate_window_allow`, `rate_window_count` | O(1) |
| `rate_window_retry_after_ms`, `rate_window_reset` | O(1) |

All operations are constant time; there are no loops and no allocation.

## Test plan

`tests/test_conformance.xi` (`module rate_tests`, 19 named checks, hello-style
`main` that prints `[PASS]`/`[FAIL]` per check, a summary line, and returns the
failure count):

1. bucket starts full and its accessors report capacity;
2. refill grants exactly one token at 1000 ms with refill 1 (999 ms: 0);
3. capacity clamps to at least 1 and refill to at least 0;
4. truncated 500 ms refill is carried until a whole token is due (pins the
   carry policy: nothing at 500 ms, one token at 1000 ms);
5. `allow` spends exactly the requested cost (including 0 and negative costs);
6. `allow` rejects a cost above capacity without spending;
7. `retry_after` reports the token cost in ms with refill 2;
8. `retry_after` rounds the wait up to the next whole token (refill 3:
   334/667/1000/1334 ms for deficits 1/2/3/4);
9. `retry_after` is -1 when refill is 0 and something is owed;
10. window admits `max_count` calls then blocks;
11. window resets exactly at the window boundary;
12. window `retry_after` counts down to the current span end;
13. `window_reset` rebases the span explicitly and the boundary still applies;
14. time going backwards changes neither bucket (clock not rewound) nor window
    (no rebase);
15. zero and negative inputs are clamped (capacity, refill, window, max_count);
16. large millisecond values stay exact (timestamps around 4e12, capacity and
    refill 1e6/1000);
17. identical inputs and call sequences stay deterministic (two buckets and
    two windows);
18. bucket never accrues past capacity (saturation clamps and consumes the
    span);
19. `allow` refills before it spends (a call exactly at the refill instant
    succeeds).

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.rate
```

Last verified: compiler 0.61.3, `port: PASS (passed=19 failed=0 exit=0)`.

## Known limitations

- Single process: plain value types, no shared or distributed budget, no
  locking.
- Integer milliseconds only; no sub-millisecond or `Float` support, and rates
  above 1000 tokens/sec are coarser than the clock (see truncation rules).
- No persistence: state lives in the caller's values and is lost on restart.
- Fixed window, not sliding window: a burst at a span boundary can admit up to
  `2 * max_count` calls across the boundary.
- Pure policy: a wrong or non-monotonic `now_ms` is not detectable.
- Extreme values wrap with the platform's 64-bit signed arithmetic rather than
  trapping; the module assumes `elapsed * refill_per_sec` and
  `gained * 1000` stay in range for realistic rate-limiter budgets.

## Compiler / stdlib notes for v0.61.3

- Free functions only (no methods), no lambdas, no `Vec[StructType]`, no
  `Vec[fn]` dispatch, no `Str` comparisons: none of the v0.61.3 traps are
  touched.
- Advisory E001 ("cannot borrow as mutable while immutably borrowed") fires
  when a `&local` call is followed by a `&mut local` call on the same local in
  one function. The tests route read-only checks through tiny helpers that
  take `&mut` and call the real `&`-based API internally; the harness run is
  warning-free.
- No `Result` values are created, so the struct-returning `Ok`/`Err`
  miscompile is avoided entirely; the tests use plain `assert`.
- The constructors return struct values directly and the module has no error
  path.
