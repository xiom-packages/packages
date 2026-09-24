# xiom.rate

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** deterministic rate limiters with explicit clocks: a token bucket
> with millisecond refill, and a fixed-window counter.
> **Deps:** `xiom.std` only (the library imports nothing; tests use
> `xiom.test` and `xiom.io`).

## What it is

`xiom.rate` decides whether a call is admitted under a rate budget, without
reading a clock, sleeping, or touching the environment. Every function is a
free function and pure: the caller reads the clock and passes `now_ms` in, so
the same inputs and the same call sequence always produce the same outputs.

Two independent limiters:

- **`TokenBucket`** -- a bucket of `capacity` tokens refilled at
  `refill_per_sec` tokens per second. Each call spends `cost` tokens
  (`rate_bucket_allow`); `rate_bucket_retry_after_ms` reports how long until a
  cost is affordable.
- **`WindowLimit`** -- a fixed window of `window_ms` milliseconds admitting at
  most `max_count` calls. The span rebases to the first call after it has
  fully elapsed.

## Clock policy

- Time is always an explicit integer-millisecond parameter (`now_ms`,
  `last_ms`, `start_ms`). The module never calls a clock.
- Time going backwards (`now_ms <= last_ms` for the bucket, `now_ms < start_ms`
  for the window) is a no-op: no tokens, no reset, no state change.
- Truncation is defined, not incidental. A refill converts only the whole
  milliseconds its granted tokens are worth
  (`last_ms += gained * 1000 / refill_per_sec`) and carries the rest, so the
  first whole token lands exactly at `1000 / refill_per_sec` ms after the last
  settlement (e.g. with refill 1, a check at 500 ms grants nothing and the
  token still arrives at 1000 ms). The clock is consumed wholesale only when
  `refill_per_sec == 0` or the bucket is saturated. Full rules in SPEC.md.
- `rate_bucket_retry_after_ms` rounds up (`ceil`) to the next whole
  millisecond and returns `-1` when `refill_per_sec == 0` and the cost can
  never be met.

## API

| Function | Returns | Description |
|---|---|---|
| `rate_bucket_new(capacity, refill_per_sec, now_ms)` | `TokenBucket` | Clamps `capacity >= 1`, `refill_per_sec >= 0`; tokens start full, `last_ms = now_ms`. |
| `rate_bucket_refill(&mut b, now_ms)` | `Unit` | Settles the refill clock to `now_ms`; backwards time is a no-op. |
| `rate_bucket_allow(&mut b, now_ms, cost)` | `Bool` | Refills, then spends `cost` when affordable; `cost <= 0` is always allowed and spends nothing. |
| `rate_bucket_tokens(b)` | `Int` | Tokens currently available. |
| `rate_bucket_capacity(b)` | `Int` | Bucket size (>= 1). |
| `rate_bucket_retry_after_ms(b, cost)` | `Int` | 0 when affordable, `-1` when `refill_per_sec == 0`, else `ceil((cost - tokens) * 1000 / refill)`. |
| `rate_window_new(window_ms, max_count, now_ms)` | `WindowLimit` | Clamps `window_ms >= 1`, `max_count >= 1`; count 0, `start_ms = now_ms`. |
| `rate_window_allow(&mut w, now_ms)` | `Bool` | Rebases the span when it has fully elapsed, then admits one call while below `max_count`. |
| `rate_window_count(w)` | `Int` | Admissions in the current span. |
| `rate_window_retry_after_ms(w, now_ms)` | `Int` | 0 when a call would be admitted now, else `start_ms + window_ms - now_ms`. |
| `rate_window_reset(&mut w, now_ms)` | `Unit` | Rebases the span at `now_ms`: count 0. |

## Usage

```xi
use xiom.rate;

var b = rate_bucket_new(100, 10, 0);     // 100 tokens, 10 tokens/sec
rate_bucket_allow(&mut b, 0, 70);        // true, 30 tokens left
rate_bucket_allow(&mut b, 0, 40);        // false, nothing spent
rate_bucket_retry_after_ms(&b, 40);      // 1000 ms (10 tokens owed, 10/sec)
rate_bucket_allow(&mut b, 2000, 40);     // true, refill + spend

var w = rate_window_new(60000, 5, 0);    // 5 calls per minute
rate_window_allow(&mut w, 0);            // true  (1/5)
rate_window_allow(&mut w, 100);          // true  (2/5)
rate_window_retry_after_ms(&w, 200);     // 0 while below max_count
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.rate
```

Expected: the module passes the section-4 namespace rule, 19 `[PASS]` lines,
and a final `port: PASS (passed=19 failed=0 exit=0)`.

## Limitations

- **Single process.** The limiters are plain value types owned by one caller:
  no shared memory, no locking, no cross-process or distributed budget.
- **Integer milliseconds.** All durations and timestamps are `Int`
  milliseconds; there is no sub-millisecond resolution and no `Float` type.
  Rates above 1000 tokens/sec are coarser than the clock (see SPEC.md).
- **No persistence.** State lives only in the values the caller holds; nothing
  is written to disk and nothing survives a restart. Recreate the bucket or
  window at startup as part of the application's warm-up.
- **Caller-owned time.** A wrong, stale, or non-monotonic `now_ms` only
  affects the documented window comparisons; the limiter cannot detect it.
- Readers take `&`, mutators take `&mut`; no function panics or returns an
  error type.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
