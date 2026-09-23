# xiom.timeout -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.timeout` (`src/timeout.xi`). Manifest: `package.xi` (name
`xiom.timeout`, version `0.1.0`). Depends on `xiom.std` (no library imports;
tests use `xiom.test` and `xiom.io`).

## Scope

A pure deterministic timeout/deadline arithmetic engine:

- a timeout policy with a default budget and a ceiling;
- effective-budget negotiation for a request (`negative -> default`,
  `else min(requested, max)`);
- deadlines as `(start_ms, budget_ms)` value pairs;
- remaining time, expiry, and elapsed-time queries against a caller-supplied
  `now_ms`;
- budget extension and reset, returning new deadline values;
- elapsed progress in permille, clamped to `0..1000`.

Everything is caller-owned values and explicit inputs; the module performs no
I/O, no sleeping, and no clock or environment access.

## Non-goals

- Reading the clock or sleeping: the caller reads time and passes `now_ms`.
- Timers, cancellation tokens, or scheduling: deadlines are static values.
- Wall-clock semantics or an epoch: only differences of the supplied
  milliseconds are meaningful.
- Non-integer durations, Float types (the pure-Int design excludes them).
- Thread safety, locking, or shared deadlines across threads.
- Mutation in place: every transformation returns a new value.

## API signatures

All functions are free functions in module `xiom.timeout`:

```xi
pub type TimeoutPolicy = { default_ms: Int; max_ms: Int; }
pub type Deadline = { start_ms: Int; budget_ms: Int; }

pub fn timeout_new(default_ms: Int, max_ms: Int) -> TimeoutPolicy
pub fn timeout_default_ms(p: &TimeoutPolicy) -> Int
pub fn timeout_max_ms(p: &TimeoutPolicy) -> Int
pub fn timeout_effective_ms(p: &TimeoutPolicy, requested_ms: Int) -> Int
pub fn deadline_new(start_ms: Int, budget_ms: Int) -> Deadline
pub fn deadline_from_policy(p: &TimeoutPolicy, start_ms: Int, requested_ms: Int) -> Deadline
pub fn deadline_remaining_ms(d: &Deadline, now_ms: Int) -> Int
pub fn deadline_expired(d: &Deadline, now_ms: Int) -> Bool
pub fn deadline_elapsed_ms(d: &Deadline, now_ms: Int) -> Int
pub fn deadline_extend(d: &Deadline, extra_ms: Int) -> Deadline
pub fn deadline_reset(d: &Deadline, now_ms: Int, budget_ms: Int) -> Deadline
pub fn deadline_progress_permille(d: &Deadline, now_ms: Int) -> Int
```

Both types are opaque value types: fields are internal implementation details
and callers construct through the constructors and read through the
functions above.

## Semantics

### TimeoutPolicy

`timeout_new` clamps with no error path. `timeout_effective_ms` selects the
default for a negative request and caps the rest at the ceiling.

| Input | Clamp / rule | Result |
|---|---|---|
| `default_ms < 0` | `default_ms = 0` | `default_ms = 0` |
| `max_ms < default_ms` | `max_ms = default_ms` | `max_ms = default_ms` |
| `timeout_effective_ms(p, r)`, `r < 0` | select default | `p.default_ms` |
| `timeout_effective_ms(p, r)`, `r >= 0`, `r > p.max_ms` | cap at ceiling | `p.max_ms` |
| `timeout_effective_ms(p, r)`, `r >= 0`, `r <= p.max_ms` | identity | `r` |

Note: `r = 0` is a valid request and yields `0`; only negative values select
the default.

### Deadline

`deadline_new(start_ms, budget_ms)` clamps `budget_ms >= 0`; `start_ms` is
never clamped (it is an arbitrary caller timestamp).

| Query | Definition |
|---|---|
| `deadline_remaining_ms(d, now)` | `max(0, d.start_ms + d.budget_ms - now)` |
| `deadline_expired(d, now)` | `deadline_remaining_ms(d, now) == 0` |
| `deadline_elapsed_ms(d, now)` | `max(0, now - d.start_ms)` |
| `deadline_progress_permille(d, now)` | see below |

`deadline_remaining_ms` is computed branch-wise so it never forms
`start + budget` in a way that can overflow a large budget:

- `now <= start`: `budget + (start - now)` -- the lead time is included in
  the remaining time;
- `now > start` and `now - start >= budget`: `0`;
- otherwise: `budget - (now - start)`.

`deadline_expired` is exactly "remaining is zero", so expiry starts at
`start + budget` and a zero-budget deadline is expired at its start instant.

`deadline_elapsed_ms` is not clamped to the budget; after expiry it keeps
growing with `now - start` (this is what distinguishes "over the deadline by
1000ms" from "expired").

Transformations (return new values; the receiver is unchanged):

- `deadline_extend(d, extra_ms)` = `deadline_new(d.start_ms, d.budget_ms + extra_ms)`;
  a negative `extra_ms` shrinks the budget and a reduction past zero clamps to
  a zero budget.
- `deadline_reset(d, now_ms, budget_ms)` = `deadline_new(now_ms, budget_ms)`;
  the new deadline starts at `now_ms` and the negative-budget clamp applies.

`deadline_progress_permille(d, now)`:

1. `remaining = deadline_remaining_ms(d, now)`; if it is `0`, return `1000`.
2. `elapsed = deadline_elapsed_ms(d, now)`; if it is `0`, return `0`.
3. `total = elapsed + remaining` (strictly positive here);
   return `(elapsed * 1000) / total`, clamped to `0..1000`.

Results: `0` at or before the start; `500` at the exact midpoint; `1000` from
expiry on; truncation toward zero in between (`1/3 -> 333`, `2/3 -> 666`).
A zero-budget deadline reports `0` before its start and `1000` at/after it.

Error paths: none. Every function is total; hostile or stale `now_ms` values
only affect the documented comparisons.

## Complexity

| Operation | Complexity |
|---|---|
| `timeout_new`, policy accessors | O(1) |
| `timeout_effective_ms` | O(1) |
| `deadline_new`, `deadline_from_policy` | O(1) |
| `deadline_remaining_ms` | O(1) |
| `deadline_expired` | O(1) |
| `deadline_elapsed_ms` | O(1) |
| `deadline_extend`, `deadline_reset` | O(1) |
| `deadline_progress_permille` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module timeout_tests`, 21 named checks:
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count):

1. constructor clamps default and ceiling;
2. accessors return the constructor values;
3. negative request selects the default;
4. requested budget is capped at the maximum (0, 1, max, max+1, large);
5. zero policy collapses every request to zero;
6. `deadline_new` clamps a negative budget to zero;
7. `deadline_from_policy` uses the effective budget;
8. remaining before the start includes the lead time;
9. remaining counts down across the budget;
10. remaining clamps to zero at and after expiry;
11. expiry starts exactly at `start + budget`;
12. elapsed is clamped below the start and grows past expiry;
13. extend returns a longer deadline and leaves the original;
14. extend clamps a negative extension at zero;
15. reset rebases the deadline at a new start and budget;
16. reset clamps a negative budget to zero;
17. progress is zero at and before the start;
18. progress reports elapsed permille at the midpoint (500, 333, 666, 1000);
19. progress clamps to 1000 after expiry;
20. zero budget expires exactly at the start instant;
21. large millisecond values stay exact.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.timeout
```

Last verified: compiler 0.61.3, `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Pure arithmetic engine: the caller reads the clock and performs the wait;
  the module has no clock, no environment access, no I/O.
- Integer milliseconds only; there is no sub-millisecond or Float support.
- Extreme `Int` values wrap with the platform's 64-bit signed arithmetic
  rather than trapping; budgets large enough to overflow a sum are handled by
  the branch-wise remaining computation, but the lead-time branch can still
  wrap at absurd magnitudes.
- Deadlines are plain values; sharing them across threads is the caller's
  problem (no locking).
- `deadline_elapsed_ms` intentionally keeps growing past expiry.
- `deadline_reset` ignores the deadline's old budget outright: the caller
  passes the replacement budget, and a negative value clamps to zero.

## Compiler / stdlib notes for v0.61.3

- Free functions only (no methods), no lambdas, no `Vec` at all, and no
  `Result` channel: none of the known 0.61.x miscompilation traps apply.
- `deadline_reset` takes the deadline being reset as its first parameter for
  call-site symmetry; the result is derived only from `now_ms` and
  `budget_ms`, and the compiler raises no diagnostic for the unused
  reference parameter.
- The tests take only `&`-references, so advisory E001 (a `&` read followed
  by a `&mut` call on the same local) cannot fire and no `&mut` helper
  wrappers are needed.
- No `Str` values and no `Vec[Str]` reads, so BUG 17 (`==` on Str elements
  lowering to pointer comparison) is avoided entirely; the suite does not
  import `xiom.string.compare`.
