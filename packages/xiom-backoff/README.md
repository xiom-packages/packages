# xiom.backoff

> **Status:** `stable` -- conformance-tested (22/22); published at `v0.1.0` on the XIOM registry.
> **Scope:** deterministic constant, linear and exponential backoff policies
> with cap and jitter, plus a retry state machine (attempt budget, reset).
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.convert.int_to_string`;
> tests additionally use `xiom.string.compare`, `xiom.test` and `xiom.io`).

## What it is

`xiom.backoff` computes retry delays as pure integer arithmetic. It never
sleeps, never reads a clock and never calls a random source: the caller asks
for the delay of attempt N and, when jitter is enabled, passes a
deterministic unit in `[0, 10000)` from its own randomness. That makes every
function a pure function of its arguments -- which is exactly what the
conformance suite pins.

- **Policies** -- constant, linear (`base + step*(N-1)`) and exponential
  (`base * (num/den)^(N-1)`, truncated after each multiply), with an optional
  raw-delay cap and jitter (`0` none, `1` full, `2` equal).
- **State machine** -- `retry_new` snapshots a policy with an attempt budget;
  `retry_next` hands out the next delay and consumes one attempt;
  `retry_reset` restores the budget; accessors report used/remaining.
- **Safety rails** -- delays saturate at `backoff_max_delay()` (1,000,000,000,000
  ms) instead of wrapping; the cap is applied to the raw delay *before*
  jitter, so a jittered delay never exceeds the cap; invalid attempts, jitter
  units and jitter modes are deterministic `Err`s.

## API

| Function | Returns | Description |
|---|---|---|
| `backoff_constant(delay_ms)` | `BackoffPolicy` | Every attempt waits `delay_ms`. |
| `backoff_linear(first_ms, step_ms, cap_ms)` | `BackoffPolicy` | `first + step*(N-1)`. |
| `backoff_exponential(first_ms, num, den, cap_ms)` | `BackoffPolicy` | `first * (num/den)^(N-1)`. |
| `backoff_with_jitter(p, mode)` | `BackoffPolicy` | Copy with jitter `0`/`1`/`2` (invalid modes become `0`). |
| `backoff_with_cap(p, cap_ms)` | `BackoffPolicy` | Copy with a new cap; negative = uncapped. |
| `backoff_kind(p)` | `Int` | `0` constant, `1` linear, `2` exponential. |
| `backoff_base(p)` | `Int` | Attempt-1 delay. |
| `backoff_step(p)` | `Int` | Linear increment. |
| `backoff_factor_num(p)` / `backoff_factor_den(p)` | `Int` | Exponential ratio. |
| `backoff_cap_ms(p)` | `Int` | Raw-delay cap; negative = uncapped. |
| `backoff_jitter_mode(p)` | `Int` | `0` none, `1` full, `2` equal. |
| `backoff_max_delay()` | `Int` | The saturation bound. |
| `backoff_raw_delay(p, attempt)` | `Result[Int, Str]` | Delay before cap and jitter. |
| `backoff_delay(p, attempt, jitter_unit)` | `Result[Int, Str]` | Final delay for attempt N. |
| `retry_new(p, max_attempts)` | `RetryState` | Budget state over a policy snapshot. |
| `retry_next(s, jitter_unit)` | `Result[Int, Str]` | Next delay; consumes one attempt. |
| `retry_reset(s)` | nothing | Restores the full budget. |
| `retry_used(s)` / `retry_remaining(s)` / `retry_max_attempts(s)` | `Int` | Budget counters. |
| `retry_exhausted(s)` | `Bool` | True when no attempt is left. |

## Usage

```xi
use xiom.backoff;
use xiom.io;

fn main() -> Int {
  let p = backoff_exponential(100, 2, 1, 5000);
  var s = retry_new(&p, 4);
  var i = 0;
  while i < 4 {
    let d = retry_next(&mut s, 0);   // deterministic: no jitter
    match d {
      Ok(ms) => { io.println(ms); }, // 100, 200, 400, 800
      Err(e) => { io.println(e); },
    }
    i = i + 1;
  }
  io.println(retry_exhausted(&s));   // false: 4 of 4 used
  retry_reset(&mut s);
  io.println(retry_remaining(&s));   // 4
  return 0;
}
```

Jittered policy (the unit comes from the caller's own random source):

```xi
let p = backoff_with_jitter(&backoff_linear(100, 50, 400), 1);
let d = backoff_delay(&p, 3, 5000);   // Ok(100): raw 200 * 5000 / 10000
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.backoff
```

Expected tail: 22 `[PASS]` lines, `xiom.backoff: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`. The test module
emits four benign E001 borrow warnings (the same advisory class as
`xiom.tls`'s suite); they do not affect the exit code.

## Limitations

- No sleeping and no timers: the module computes delays; the caller waits.
- No random source: jitter takes an explicit unit in `[0, 10000)`, so
  callers choose (and test) their own randomness.
- Jitter modes are fixed (`none`, `full`, `equal`); decorrelated-jitter or
  custom distributions are not provided.
- Delay arithmetic is integer milliseconds; fractional growth truncates
  after every multiply (documented), and negative constructor inputs are
  clamped to 0.
- Delays saturate at `backoff_max_delay()` rather than wrapping; there is no
  overflow error.
- The retry state is a plain value: no persistence, no persistence across
  processes, no concurrency.
- In-memory only: no FFI, no file I/O.

See `SPEC.md` for the exact arithmetic, error catalog and test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
