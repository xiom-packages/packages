# xiom.itest

> **Status:** `incubating` -- conformance-tested (24/24); not yet published on the XIOM registry.
> **Scope:** a deterministic integration-test harness model: suites, fixtures,
> dependency-aware steps, retries with capped tick backoff, tick timeouts,
> a structured assertion catalog, aggregation and a text report.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare` and `xiom.convert`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.itest` models an integration-test run as a plain value that a caller
drives one explicit step at a time. There are no processes, no file I/O and
no FFI: the library is a pure state machine plus a renderer, so the same
call sequence always produces the same state and the same report.

- **Suites and fixtures** -- a suite is declared, opened (`itest_begin_suite`
  runs its setup fixtures in declaration order) and closed
  (`itest_end_suite` runs its teardown fixtures LIFO, failure or not). The
  fixture execution log records every fixture in order with suite and phase.
- **Steps and dependencies** -- steps belong to suites and declare
  dependencies by name. Dependencies are validated at declaration time:
  empty/unknown names, self-dependencies, duplicates and cycles are rejected,
  so the graph stays acyclic. The scheduler (`itest_next_step`) runs steps in
  declaration order, only while their suite is open and after every
  dependency has PASSED. A step whose dependency FAILED or was SKIPPED is
  itself marked SKIPPED with an exact reason, transitively.
- **Retries and backoff** -- a failed attempt with attempts left returns the
  step to PENDING with `min(base * 2^(attempts-1), cap)` ticks of backoff.
  The wait elapses only through explicit `itest_tick` calls; `base`/`cap` of
  0 mean an immediate retry.
- **Timeouts** -- a step may set a per-attempt tick timeout. The tick that
  brings a RUNNING attempt to its timeout fails the attempt (arming a retry
  when attempts remain); only the ticks after the timeout instant count
  against the new backoff.
- **Assertions** -- a fixed catalog of eleven checks (`true`, `false`,
  `eq_int`, `ne_int`, `lt_int`, `le_int`, `gt_int`, `ge_int`, `eq_str`,
  `ne_str`, `contains_str`) records structured failures (step, attempt, kind,
  expected, actual, message) instead of aborting. The log is append-only.
- **Results** -- per-suite and overall counts by status, plus
  `itest_report` for a deterministic text report (summary, suites, steps,
  fixture log, assertion failures).

## API

| Function | Returns | Description |
|---|---|---|
| `itest_new()` | `ITest` | Fresh empty harness, clock at 0. |
| `itest_add_suite(h, name)` | `Result[Int, Str]` | Declare a suite; `Ok(index)`. |
| `itest_add_setup(h, suite, fixture)` | `Result[Int, Str]` | Declare a setup fixture. |
| `itest_add_teardown(h, suite, fixture)` | `Result[Int, Str]` | Declare a teardown fixture. |
| `itest_add_step(h, suite, name)` | `Result[Int, Str]` | Declare a step (1 attempt, no backoff, no timeout). |
| `itest_step_depends_on(h, step, dep)` | `Result[Int, Str]` | Add a dependency; `Ok(count)`. |
| `itest_step_set_retries(h, step, max_attempts, base, cap)` | `Result[Int, Str]` | Attempt budget and capped backoff. |
| `itest_step_set_timeout(h, step, ticks)` | `Result[Int, Str]` | Per-attempt timeout (0 = none). |
| `itest_begin_suite(h, suite)` | `Result[Int, Str]` | Open a suite; runs setup fixtures. |
| `itest_end_suite(h, suite)` | `Result[Int, Str]` | Close a suite; runs teardown fixtures LIFO. |
| `itest_next_step(h)` | `Int` | Propagate skips; index of the next runnable step, or -1. |
| `itest_begin_step(h, step)` | `Int` | Start an attempt; `ITEST_RUNNING` or -1. |
| `itest_finish_step(h, step, passed)` | `Int` | End the attempt; new status or -1. |
| `itest_tick(h, ticks)` | nothing | Advance the clock; apply timeouts and backoff. |
| `itest_assert_true(h, step, cond, message)` | `Bool` | Assert true; kind `true`. |
| `itest_assert_false(h, step, cond, message)` | `Bool` | Assert false; kind `false`. |
| `itest_assert_eq_int(h, step, expected, actual, message)` | `Bool` | Kind `eq_int`. |
| `itest_assert_ne_int(h, step, expected, actual, message)` | `Bool` | Kind `ne_int`. |
| `itest_assert_lt_int(h, step, left, right, message)` | `Bool` | Kind `lt_int`. |
| `itest_assert_le_int(h, step, left, right, message)` | `Bool` | Kind `le_int`. |
| `itest_assert_gt_int(h, step, left, right, message)` | `Bool` | Kind `gt_int`. |
| `itest_assert_ge_int(h, step, left, right, message)` | `Bool` | Kind `ge_int`. |
| `itest_assert_eq_str(h, step, expected, actual, message)` | `Bool` | Kind `eq_str` (byte equality). |
| `itest_assert_ne_str(h, step, expected, actual, message)` | `Bool` | Kind `ne_str`. |
| `itest_assert_contains_str(h, step, haystack, needle, message)` | `Bool` | Kind `contains_str`. |
| `itest_step_count(h)` / `itest_suite_count(h)` | `Int` | Declared counts. |
| `itest_step_name(h, i)` / `itest_step_suite(h, i)` | `Str` / `Int` | Step identity; -1 out of range. |
| `itest_step_status(h, i)` | `Int` | `ITEST_PENDING/RUNNING/PASSED/FAILED/SKIPPED`. |
| `itest_step_attempts(h, i)` / `itest_step_ticks(h, i)` / `itest_step_elapsed(h, i)` / `itest_step_wait(h, i)` | `Int` | Attempt count, total ticks, current-attempt ticks, backoff left. |
| `itest_step_message(h, i)` | `Str` | Skip reason or terminal failure text. |
| `itest_step_max_attempts(h, i)` / `itest_step_backoff_base(h, i)` / `itest_step_backoff_cap(h, i)` / `itest_step_timeout(h, i)` | `Int` | Configured values. |
| `itest_step_dep_count(h, i)` / `itest_step_dep(h, i, k)` | `Int` / `Str` | Dependency list of a step. |
| `itest_suite_name(h, s)` / `itest_suite_state(h, s)` | `Str` / `Int` | Suite identity and `ITEST_SUITE_NEW/OPEN/CLOSED`. |
| `itest_fixture_count(h)` / `itest_fixture_name(h, i)` / `itest_fixture_suite(h, i)` / `itest_fixture_phase(h, i)` | `Int` / `Str` / `Int` / `Int` | Fixture execution log (`ITEST_SETUP`/`ITEST_TEARDOWN`). |
| `itest_now(h)` | `Int` | Current tick. |
| `itest_count(h, status)` | `Int` | Steps with a status. |
| `itest_passed_count(h)` / `itest_failed_count(h)` / `itest_skipped_count(h)` / `itest_pending_count(h)` / `itest_running_count(h)` | `Int` | Overall aggregation. |
| `itest_all_done(h)` | `Bool` | No PENDING or RUNNING steps. |
| `itest_suite_step_count(h, s)` / `itest_suite_count_status(h, s, status)` | `Int` | Per-suite step counts. |
| `itest_suite_passed(h, s)` / `itest_suite_failed(h, s)` / `itest_suite_skipped(h, s)` / `itest_suite_pending(h, s)` | `Int` | Per-suite aggregation. |
| `itest_failure_count(h)` | `Int` | Structured assertion failures. |
| `itest_failure_step(h, i)` / `itest_failure_suite(h, i)` / `itest_failure_attempt(h, i)` | `Int` | Failure location and attempt. |
| `itest_failure_kind(h, i)` / `itest_failure_expected(h, i)` / `itest_failure_actual(h, i)` / `itest_failure_message(h, i)` | `Str` | Structured failure fields. |
| `itest_step_assert_failures(h, step)` | `Int` | Failures for a step across attempts. |
| `itest_attempt_failure_count(h, step)` | `Int` | Failures for a step's current attempt. |
| `itest_status_name(status)` / `itest_suite_state_name(state)` | `Str` | Code names. |
| `itest_report(h)` | `Str` | Deterministic text report. |

## Usage

```xi
use xiom.itest;
use xiom.io;

fn main() -> Int {
  var h = itest_new();
  itest_add_suite(&mut h, "build");
  itest_add_setup(&mut h, 0, "db");
  itest_add_teardown(&mut h, 0, "drop-db");
  itest_add_step(&mut h, 0, "compile");
  itest_add_step(&mut h, 0, "link");
  itest_step_depends_on(&mut h, 1, "compile");
  itest_step_set_retries(&mut h, 1, 2, 2, 4);
  itest_begin_suite(&mut h, 0);

  var s = itest_next_step(&mut h);
  while s >= 0 {
    itest_begin_step(&mut h, s);
    itest_tick(&mut h, 1);                                // pretend work
    itest_assert_eq_int(&mut h, s, 0, 0, "exit code");    // real checks go here
    itest_finish_step(&mut h, s, itest_attempt_failure_count(&h, s) == 0);
    itest_tick(&mut h, itest_step_wait(&h, s));           // consume any backoff
    s = itest_next_step(&mut h);
  }
  itest_end_suite(&mut h, 0);
  io.println(itest_report(&h));
  return itest_failed_count(&h);
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.itest
```

Expected tail: 24 `[PASS]` lines, `xiom.itest: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- Model only: the library never executes anything. The caller performs the
  actual integration work and reports each attempt outcome through
  `itest_finish_step`; there is no process spawning, no file I/O, no FFI.
- One step is in flight at a time: `itest_begin_step` refuses while another
  step is RUNNING, so attempts are serialized by construction.
- Time is a logical tick count, not wall-clock time.
- Tick steps are caller-granular: an eligible step is not started by
  `itest_tick` itself; the caller must call `itest_next_step` /
  `itest_begin_step` afterwards.
- The assertion log is append-only, so failures from an attempt that was
  later retried successfully stay visible; use
  `itest_attempt_failure_count` for the current attempt only.
- Steps whose suite index is out of range (only possible with a hand-built
  `ITest`) are omitted from the report; the API keeps vectors aligned.

See `SPEC.md` for the exact semantics, error catalog, report grammar and
test matrix. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
