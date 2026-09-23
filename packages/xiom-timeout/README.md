# xiom.timeout

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** deterministic deadline and timeout arithmetic with explicit
> clocks: timeout policies with defaults and ceilings, and deadlines that
> track remaining time, expiry, elapsed time, extension, reset, and progress.
> **Deps:** `xiom.std` only (the library imports nothing; tests use
> `xiom.test` and `xiom.io`).

## What it is

`xiom.timeout` computes how much time is left, whether a deadline has
expired, and how far a deadline has progressed, without ever reading a clock
itself. Every function is a free function and pure: all inputs (including
`now_ms` and `start_ms`) are passed in by the caller, so the same inputs
always produce the same outputs. Timestamps and budgets are integer
milliseconds; the caller owns the real clock and the actual waiting.

Two independent pieces:

- **`TimeoutPolicy`** -- a default budget for requests that do not specify
  one, and a ceiling that caps any request.
- **`Deadline`** -- a start instant plus a budget. Queries report remaining
  time, expiry, elapsed time, and progress; `deadline_extend` and
  `deadline_reset` return new deadline values (the originals are unchanged).

## API

| Function | Returns | Description |
|---|---|---|
| `timeout_new(default_ms, max_ms)` | `TimeoutPolicy` | Clamps to `default_ms >= 0`, `max_ms >= default_ms`. |
| `timeout_default_ms(p)` | `Int` | Default budget in ms (>= 0). |
| `timeout_max_ms(p)` | `Int` | Ceiling in ms (>= default). |
| `timeout_effective_ms(p, requested_ms)` | `Int` | `requested_ms < 0` selects the default; otherwise `min(requested_ms, max_ms)`. |
| `deadline_new(start_ms, budget_ms)` | `Deadline` | Deadline from `start_ms` with budget clamped to >= 0. |
| `deadline_from_policy(p, start_ms, requested_ms)` | `Deadline` | `deadline_new(start_ms, timeout_effective_ms(p, requested_ms))`. |
| `deadline_remaining_ms(d, now_ms)` | `Int` | `max(0, start + budget - now)`; before the start it includes the lead time. |
| `deadline_expired(d, now_ms)` | `Bool` | True from `start + budget` on (remaining is zero). |
| `deadline_elapsed_ms(d, now_ms)` | `Int` | `max(0, now - start)`; keeps growing past expiry. |
| `deadline_extend(d, extra_ms)` | `Deadline` | New deadline with `budget + extra_ms` clamped to >= 0. |
| `deadline_reset(d, now_ms, budget_ms)` | `Deadline` | New deadline starting at `now_ms` with the given budget (clamped >= 0). |
| `deadline_progress_permille(d, now_ms)` | `Int` | Elapsed fraction in 0..1000, truncated; 1000 from expiry on. |

All functions are total: there is no error path and no function panics.

## Usage

```xi
use xiom.timeout;

let p = timeout_new(500, 5000);          // default 500ms, ceiling 5000ms
timeout_effective_ms(&p, -1);            // 500  (default)
timeout_effective_ms(&p, 9000);          // 5000 (clamped to the ceiling)

let d = deadline_from_policy(&p, 1000, 2000);   // starts at t=1000, budget 2000
deadline_remaining_ms(&d, 1500);         // 1500
deadline_expired(&d, 3000);              // true  (1000 + 2000)
deadline_progress_permille(&d, 2000);    // 500

let longer = deadline_extend(&d, 1000);  // budget becomes 3000
let fresh  = deadline_reset(&d, 4000, -1); // negative: clamped to 0 (expired at 4000)
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.timeout
```

Expected: the module passes the section-4 namespace rule, 21 `[PASS]` lines,
and a final `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

The suite is `tests/test_conformance.xi` (21 named checks): policy clamping;
accessors; effective budget at the default/zero/max/above-max boundaries;
negative budget clamping; deadline remaining before, at, and after expiry;
the exact expiry boundary; elapsed clamping; extend (positive, negative,
below zero, original unchanged); reset; progress 0/500/1000 with truncation
and clamping; a zero-budget deadline; and large millisecond values.

## Limitations

- Pure arithmetic engine: it never reads a clock, sleeps, or touches the
  environment. The caller supplies `now_ms` and performs the waiting.
- Integer milliseconds only; no fractional seconds and no sub-millisecond
  precision.
- Timestamps are caller-supplied `Int`s in an unspecific epoch; only
  differences are meaningful. Extreme values wrap with the platform's 64-bit
  signed arithmetic rather than trapping.
- `deadline_extend` / `deadline_reset` return new values; deadlines are plain
  values and are not mutated in place, shared, or synchronized across threads.
- `deadline_elapsed_ms` is not clamped to the budget: after expiry it keeps
  growing (documented by design).
- A zero-budget deadline is expired from its start instant; there is no
  separate "not yet started" expiry state.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
