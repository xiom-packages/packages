# xiom.backoff -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.backoff` (`src/backoff.xi`). Pure XIOM, no FFI, no sleeping,
no clock.

## 1. Scope

Deterministic retry-delay computation:

- `BackoffPolicy` values for constant, linear and exponential growth with an
  optional raw-delay cap and jitter mode;
- constructors (`backoff_constant`, `backoff_linear`, `backoff_exponential`,
  `backoff_with_jitter`, `backoff_with_cap`) and read-only accessors;
- `backoff_raw_delay` (growth only) and `backoff_delay` (growth, cap and
  jitter) with validation;
- `RetryState`: a policy snapshot with an attempt budget, `retry_next`,
  `retry_reset` and budget accessors.

All arithmetic is integer; all functions are pure; the module never waits.

## 2. Non-goals

- **No sleeping, timers or clocks**: the caller waits, the module computes.
- **No random source**: jitter consumes an explicit deterministic unit, so
  the caller owns randomness.
- **No custom jitter distributions**: only `none`, `full` and `equal`.
- **No retry-loop side effects**: the state machine hands out delays; it
  never invokes a callback or performs the retried operation.
- **No persistence, no concurrency, no async integration.**
- No FFI, no file I/O, no registry integration; in-memory only.

## 3. Data model

```xi
pub type BackoffPolicy = {
  kind: Int;         // 0 constant, 1 linear, 2 exponential
  base_ms: Int;      // attempt-1 delay (>= 0)
  step_ms: Int;      // linear increment (>= 0)
  factor_num: Int;   // exponential numerator (>= 1)
  factor_den: Int;   // exponential denominator (>= 1)
  cap_ms: Int;       // raw-delay cap; -1 (or any negative) = uncapped
  jitter: Int;       // 0 none, 1 full, 2 equal
}

pub type RetryState = {
  kind: Int; base_ms: Int; step_ms: Int;
  factor_num: Int; factor_den: Int; cap_ms: Int; jitter: Int;
  max_attempts: Int; // >= 0
  used: Int;         // attempts handed out; 0 <= used <= max_attempts
}
```

`RetryState` is a flat snapshot: `retry_new` copies the policy fields at
construction, so later changes to the source policy do not affect the state.

## 4. Arithmetic

Saturation bound `backoff_max_delay()` = **1,000,000,000,000** ms. Addition
and multiplication inside growth computation saturate at this bound instead
of wrapping; there is no overflow error.

Growth of attempt `N` (N >= 1), all integer:

| kind | raw delay |
|---|---|
| constant | `base` |
| linear | `base + step * (N - 1)`, saturating |
| exponential | `base * (factor_num / factor_den)^(N - 1)`, with truncation after every multiply, saturating |

The exponential loop checks `v > MAX / factor_num` before each multiply and
returns `MAX` when the next product would exceed the bound, so the exact
saturation point is deterministic: with `base = 1`, `num = 10`, `den = 1`,
attempt 12 yields `10^11`, attempts 13 and beyond yield `MAX`.

Pipeline of `backoff_delay(p, N, unit)`:

1. validate `N >= 1`, `unit in [0, 10000)`, `jitter in [0, 2]`;
2. compute the raw delay (section above);
3. apply the cap: when `cap_ms >= 0` and `raw > cap_ms`, use `cap_ms`;
4. apply jitter:
   - `0` none: `d = raw`;
   - `1` full: `d = raw * unit / 10000` (floor);
   - `2` equal: `d = raw / 2 + raw * unit / 20000` (floor).

Because the cap is applied before jitter and jitter only scales down, the
result always lies in `[0, cap]` when capped, and in `[0, MAX]` otherwise.
With `unit = 0`, full jitter yields `0` and equal jitter yields `raw / 2`.

## 5. Error catalog

| Condition | Exact message |
|---|---|
| `attempt < 1` (`backoff_delay`, `backoff_raw_delay`, via `retry_next`) | `backoff: bad attempt <n>` |
| `jitter_unit < 0` or `>= 10000` | `backoff: bad jitter unit <n>` |
| policy carries `jitter` outside `0..2` (hand-built) | `backoff: bad jitter mode <m>` |
| `retry_next` with no attempt left | `backoff: attempts exhausted` |

Failed calls never mutate a `RetryState` and never consume an attempt.

## 6. API contract

```xi
pub fn backoff_constant(delay_ms: Int) -> BackoffPolicy
pub fn backoff_linear(first_ms: Int, step_ms: Int, cap_ms: Int) -> BackoffPolicy
pub fn backoff_exponential(first_ms: Int, factor_num: Int, factor_den: Int, cap_ms: Int) -> BackoffPolicy
pub fn backoff_with_jitter(p: &BackoffPolicy, mode: Int) -> BackoffPolicy
pub fn backoff_with_cap(p: &BackoffPolicy, cap_ms: Int) -> BackoffPolicy
pub fn backoff_kind(p: &BackoffPolicy) -> Int
pub fn backoff_base(p: &BackoffPolicy) -> Int
pub fn backoff_step(p: &BackoffPolicy) -> Int
pub fn backoff_factor_num(p: &BackoffPolicy) -> Int
pub fn backoff_factor_den(p: &BackoffPolicy) -> Int
pub fn backoff_cap_ms(p: &BackoffPolicy) -> Int
pub fn backoff_jitter_mode(p: &BackoffPolicy) -> Int
pub fn backoff_max_delay() -> Int
pub fn backoff_raw_delay(p: &BackoffPolicy, attempt: Int) -> Result[Int, Str]
pub fn backoff_delay(p: &BackoffPolicy, attempt: Int, jitter_unit: Int) -> Result[Int, Str]
pub fn retry_new(p: &BackoffPolicy, max_attempts: Int) -> RetryState
pub fn retry_next(s: &mut RetryState, jitter_unit: Int) -> Result[Int, Str]
pub fn retry_reset(s: &mut RetryState)
pub fn retry_used(s: &RetryState) -> Int
pub fn retry_remaining(s: &RetryState) -> Int
pub fn retry_max_attempts(s: &RetryState) -> Int
pub fn retry_exhausted(s: &RetryState) -> Bool
```

Constructor clamps: `base_ms`/`step_ms` -> `>= 0`; `factor_num`/
`factor_den` -> `>= 1`; `retry_new` clamps `max_attempts` to `>= 0`;
`backoff_with_jitter` maps an out-of-range mode to `0`; `cap_ms` is stored
as given (negative = uncapped). `retry_remaining` clamps at 0 even for a
hand-built inconsistent state.

Complexity: O(1) for constant and linear policies; O(attempt) for
exponential policies (the growth loop); everything else is O(1).

## 7. Test matrix

`tests/test_conformance.xi` (module `backoff_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All expected values are hand-computed integers.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | constant policy | growth table |
| t2 | linear growth | growth table |
| t3 | linear cap | rules 3, 4 |
| t4 | exponential 2x | growth table |
| t5 | exponential 3/2 truncation | section 4 |
| t6 | exponential cap | rules 3, 4 |
| t7 | constructor clamps | section 6 |
| t8 | full jitter | rule 4 |
| t9 | equal jitter | rule 4 |
| t10 | cap before jitter | rule 3 before 4 |
| t11 | bad attempts | section 5 |
| t12 | bad jitter units | section 5 |
| t13 | bad jitter mode | section 5 |
| t14 | exponential saturation | section 4 |
| t15 | linear saturation | section 4 |
| t16 | retry walk and exhaustion | section 5, 6 |
| t17 | retry_reset | section 6 |
| t18 | zero/negative budgets | section 6 |
| t19 | retry jitter | rule 4 |
| t20 | state snapshots the policy | section 3 |
| t21 | failed retry does not consume | section 5 |
| t22 | budget accessors | section 6 |

## 8. Known limitations

- Delays are integer milliseconds with truncated division; no fractional or
  floating-point delays.
- Only three jitter modes; no decorrelated jitter or custom distributions.
- Saturation is silent (by design); a caller that needs to detect saturation
  compares against `backoff_max_delay()`.
- The retry state is a value, not a service: no persistence, no concurrent
  use, no callbacks.
- A hand-built policy can carry an out-of-range jitter mode; `backoff_delay`
  rejects it, but the accessor still reports it.
- No sleeping, clocks, timers or randomness.

## 9. Compiler / stdlib notes (v0.61.3)

Free functions only; `Result` construction confined to the leaf helpers
`_ok_int` / `_err_int`; policies and states are flat `struct`s with `Int`
fields only (no `Vec[StructType]`, no nested struct fields). Struct-literal
returns (for example `_state_policy`) are used freely; only `Ok`/`Err`
construction is confined to leaf helpers. Int constants of value
1,000,000,000,000 and the saturating add/multiply helpers keep every
intermediate within `Int` range, so no wrap can occur. The test module emits
four benign E001 borrow warnings on the interleaved `&`/`&mut` retry-state
calls (the same advisory class as `xiom.tls`'s suite); they do not affect
the run, and the suite is green with `program_exit=0`.
