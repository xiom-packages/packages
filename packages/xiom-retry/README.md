# xiom.retry

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure deterministic retry policy engine: exponential backoff with
> a delay ceiling, deterministic jitter, caller-driven retry state, and
> circuit-breaker state with a half-open probe window.
> **Deps:** `xiom.std` only (the library imports nothing; tests use
> `xiom.test` and `xiom.io`).

## What it is

`xiom.retry` decides when and how long to wait between retries, and when to
stop retrying entirely, without performing any waiting itself. Every function
is a free function and pure: all inputs (including `now_secs` where time
matters) are passed in by the caller, so the same inputs always produce the
same outputs. The caller performs the sleeping, the real call, and the wiring.

Two independent pieces:

- **`RetryPolicy` / `RetryState`** -- attempt budget and exponential backoff
  (`base * factor^(attempt-1)`, clamped to a ceiling), plus an optional
  deterministic jitter in `[delay/2, delay]` derived from a caller seed.
- **`CircuitBreaker`** -- a failure threshold that opens the breaker, a
  cooldown window, and a derived half-open state that admits a single probe
  call. The caller reports each outcome with `circuit_record_success` /
  `circuit_record_failure`.

## API

| Function | Returns | Description |
|---|---|---|
| `retry_new(max_attempts, base_delay_secs, factor, max_delay_secs)` | `RetryPolicy` | Clamps to `max_attempts >= 1`, `base_delay_secs >= 0`, `factor >= 1`, `max_delay_secs >= base_delay_secs`. |
| `retry_max_attempts(p)` | `Int` | Attempt budget (>= 1). |
| `retry_base_delay_secs(p)` | `Int` | First delay in seconds (>= 0). |
| `retry_factor(p)` | `Int` | Exponential multiplier (>= 1). |
| `retry_max_delay_secs(p)` | `Int` | Delay ceiling (>= base delay). |
| `retry_delay_secs(p, attempt)` | `Int` | `base * factor^(attempt-1)` clamped to the ceiling; overflow-safe (stops multiplying at the ceiling). |
| `retry_should_retry(p, attempts_done)` | `Bool` | `attempts_done < max_attempts`. |
| `retry_jittered_delay(p, attempt, seed)` | `Int` | Deterministic jitter in `[delay/2, delay]`; same inputs, same output. |
| `retry_state_new()` | `RetryState` | Fresh state (0 attempts, 0 last delay). |
| `retry_state_next(&mut s, p)` | `Option[Int]` | Consumes one attempt: `Some(delay)` or `None` when the budget is exhausted. |
| `retry_state_attempts(s)` | `Int` | Attempts consumed so far. |
| `retry_state_last_delay(s)` | `Int` | Delay stored by the last successful `retry_state_next`. |
| `retry_state_reset(&mut s)` | `Unit` | Back to the fresh state. |
| `circuit_new(failure_threshold, reset_after_secs)` | `CircuitBreaker` | Closed breaker; clamps to `threshold >= 1`, `reset_after_secs >= 0`. |
| `circuit_state(c)` | `Int` | `0` = closed, `1` = open. |
| `circuit_allow(c, now_secs)` | `Bool` | Closed: true. Open: true from the probe window on. |
| `circuit_is_half_open(c, now_secs)` | `Bool` | Open and `now_secs >= opened_at + reset_after_secs`. |
| `circuit_record_success(&mut c, now_secs)` | `Unit` | Closes the breaker and clears failures. |
| `circuit_record_failure(&mut c, now_secs)` | `Unit` | Counts failures; trips at the threshold or re-arms after a failed probe. |
| `circuit_failures(c)` | `Int` | Consecutive failures; frozen while open. |
| `circuit_trips(c)` | `Int` | Opens so far (initial trip + failed probes). |
| `circuit_reset(&mut c)` | `Unit` | Full reset: closed, no failures, no trips. |

## Usage

```xi
use xiom.retry;

let p = retry_new(5, 1, 2, 30);        // 5 attempts, 1s base, x2, ceiling 30s
retry_delay_secs(&p, 1);               // 1
retry_delay_secs(&p, 4);               // 8
retry_delay_secs(&p, 5);               // 16
retry_jittered_delay(&p, 4, 12345);    // 4..8, reproducible

var st = retry_state_new();
match retry_state_next(&mut st, &p) {
  Some(delay) => { /* the caller sleeps `delay` seconds here */ },
  None => {},
}

var cb = circuit_new(3, 30);           // trip after 3 failures, 30s cooldown
circuit_allow(&cb, 1000);              // true while closed
circuit_record_failure(&mut cb, 1001);
circuit_record_success(&mut cb, 1002); // closes and clears failures
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.retry
```

Expected: the module passes the section-4 namespace rule, 21 `[PASS]` lines,
and a final `port: PASS (passed=21 failed=0 exit=0)`.

## Limitations

- Pure policy engine: it never sleeps, reads a clock, or touches the
  environment. The caller owns waiting and time (`now_secs` is always an
  explicit input).
- `Int` seconds only; no fractional or sub-second delays.
- Jitter is deterministic by design (seed and attempt hashed): it decorrelates
  retries within a run, but is not a security or load-balancing randomness
  source.
- Circuit breaker `failures` is frozen while open; a failure report before the
  probe window changes nothing.
- Value types only; not thread-safe and no shared/locked breaker across
  threads.
- Readers take `&`, mutators take `&mut`; no function panics.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
