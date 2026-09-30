# xiom.itest -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.itest` (`src/itest.xi`). Pure XIOM, no FFI, no process or file
I/O.

## 1. Scope

A deterministic integration-test harness model driven by the caller:

- `itest_new` builds an empty harness;
- `itest_add_suite` / `itest_add_setup` / `itest_add_teardown` /
  `itest_add_step` / `itest_step_depends_on` / `itest_step_set_retries` /
  `itest_step_set_timeout` declare the run and validate every input;
- `itest_begin_suite` / `itest_end_suite` drive suite lifecycle and the
  fixture log;
- `itest_next_step` / `itest_begin_step` / `itest_finish_step` /
  `itest_tick` drive step scheduling, attempts, retries and timeouts;
- the assertion catalog records structured failures instead of aborting;
- accessors and aggregation expose the state; `itest_report` renders it.

## 2. Non-goals

- **No execution**: the library never spawns processes, reads files or calls
  into C. The caller performs the integration work and reports each attempt
  outcome through `itest_finish_step`.
- **No wall-clock time**: time is a logical tick counter advanced only by
  `itest_tick`.
- **No concurrency**: at most one step is RUNNING by construction.
- **No auto-run**: `itest_tick` never starts or finishes a step except for
  attempt timeouts; `itest_next_step` never begins an attempt.
- **No before-each/after-each step fixtures**: fixtures are suite-level only.
- **No persistence, no registry, no FFI**: in-memory values only.

## 3. Data model

```xi
pub type ITest = {
  // suites
  suite_names: Vec[Str];
  suite_state: Vec[Int];          // ITEST_SUITE_NEW / OPEN / CLOSED
  // declared fixtures
  setup_names: Vec[Str];          // setup fixtures, declaration order
  setup_suite: Vec[Int];          // owning suite of each entry
  teardown_names: Vec[Str];       // teardown fixtures, declaration order
  teardown_suite: Vec[Int];
  // fixture execution log
  fixture_log: Vec[Str];
  fixture_log_suite: Vec[Int];
  fixture_log_phase: Vec[Int];    // ITEST_SETUP / ITEST_TEARDOWN
  // steps
  step_names: Vec[Str];
  step_suites: Vec[Int];
  step_deps: Vec[Str];            // flat dependency-name list
  step_dep_start: Vec[Int];       // start of each step's dep slice
  step_dep_count: Vec[Int];       // length of each step's dep slice
  step_max_attempts: Vec[Int];    // >= 1
  step_backoff_base: Vec[Int];    // ticks, 0 = no backoff
  step_backoff_cap: Vec[Int];     // ticks, 0 = no backoff
  step_timeout: Vec[Int];         // ticks, 0 = none
  step_status: Vec[Int];          // ITEST_PENDING/RUNNING/PASSED/FAILED/SKIPPED
  step_attempts: Vec[Int];
  step_elapsed: Vec[Int];         // ticks of the current attempt
  step_ticks: Vec[Int];           // ticks of finished/completed attempts
  step_wait: Vec[Int];            // remaining retry backoff
  step_messages: Vec[Str];        // skip reason / terminal failure text
  // structured assertion failures
  fail_steps: Vec[Int];
  fail_attempts: Vec[Int];
  fail_kinds: Vec[Str];
  fail_expected: Vec[Str];
  fail_actual: Vec[Str];
  fail_messages: Vec[Str];
  // clock
  now: Int;
}
```

Step vectors are index-aligned in declaration order and are clamped to
their minimum length by every accessor, so a hand-built `ITest` cannot be
read out of range. A step's dependency slice is contiguous:
`step_dep_start[i] .. step_dep_start[i] + step_dep_count[i]` into
`step_deps`. Declaring a dependency after other steps have declared theirs
relocates the step's existing slice to the end of `step_deps`, so slices
never interleave.

## 4. Semantics

### 4.1 Declaration

1. **Names** are non-empty and NUL-free; suite names are unique per
   harness, step names are globally unique, fixture names are unique per
   suite and per phase. Comparisons are byte-wise and case-sensitive.
2. Every declaration failure returns `Err(<message>)` and never mutates the
   harness.
3. A new step defaults to one attempt, base 0, cap 0, timeout 0 and
   PENDING.
4. `itest_step_depends_on` rejects unknown names, self-dependencies,
   duplicate dependencies and cycles (checked transitively over the
   dependency graph), so the graph is acyclic. `Ok(n)` returns the
   step's dependency count after the call.

### 4.2 Suite lifecycle

5. `itest_begin_suite` requires state NEW, sets the suite OPEN and appends
   the suite's setup fixtures to the fixture log in declaration order.
6. `itest_end_suite` requires state OPEN, sets the suite CLOSED and appends
   the suite's teardown fixtures LIFO (reverse declaration order). Closing
   is independent of step outcomes, so teardown always runs, including
   after failures.
7. Fixture log entries record name, owning suite and phase
   (`ITEST_SETUP`, `ITEST_TEARDOWN`).

### 4.3 Scheduling and dependencies

8. `itest_next_step` first propagates skips: every PENDING step with a
   dependency that is FAILED or SKIPPED becomes SKIPPED with reason
   `itest: skipped: dependency '<dep>' failed` or
   `itest: skipped: dependency '<dep>' skipped`, where `<dep>` is the first
   blocking dependency in declaration order. Propagation repeats until
   stable, so chains propagate.
9. `itest_next_step` then returns the first PENDING step, in declaration
   order, whose `step_wait` is 0, whose suite is OPEN, and every dependency
   of which is PASSED. It returns -1 when no step is runnable, and also -1
   while any step is RUNNING (one step in flight at a time).
10. `itest_begin_step` requires the step to be PENDING with wait 0, its
    suite OPEN, all dependencies PASSED, and no other step RUNNING. It
    increments `step_attempts`, sets status RUNNING, resets the attempt
    clock and clears the step message; it returns `ITEST_RUNNING` (1) or
    -1. Ineligible transitions never mutate state.
11. `itest_finish_step` requires status RUNNING (else -1). The attempt's
    elapsed ticks are added to `step_ticks` and the elapsed counter resets.

### 4.4 Attempts, retries and backoff

12. On a **passed** attempt the step becomes PASSED, `step_wait` is 0 and
    the message is cleared.
13. On a **failed** attempt with `attempts < max_attempts` the step returns
    to PENDING with
    `itest_step_wait = min(base * 2^(attempts-1), cap)`, where `attempts` is
    the number of attempts already made; if `base <= 0` or `cap <= 0` the
    wait is 0 (immediate retry). `itest_finish_step` returns ITEST_PENDING.
    The doubling saturates at `cap`, so large attempt counts cannot
    overflow.
14. On the last failed attempt the step becomes FAILED with
    `itest: step '<name>' failed after <n> attempt(s)` (`attempt` for n = 1,
    otherwise `attempts`); `itest_finish_step` returns ITEST_FAILED.
15. `itest_tick(ticks)` with `ticks <= 0` does nothing. Otherwise it adds
    `ticks` to `now`, then, per step:
    - RUNNING: `elapsed` grows by `ticks`; if a timeout `t > 0` exists and
      `ticks >= t - elapsed`, the attempt is failed **at the instant
      `elapsed` would reach `t`**: the attempt contributes `t - elapsed`
      more ticks to `step_ticks`, and the leftover `ticks - (t - elapsed)`
      ticks immediately reduce the new backoff wait (never below 0). With
      attempts remaining the step returns to PENDING, else it becomes
      FAILED with
      `itest: step '<name>' timed out after <t> ticks (attempt <a> of <m>)`.
    - PENDING with `wait > 0`: `wait` shrinks by `ticks`, never below 0.
16. Ticking never starts an attempt: a step whose wait reaches 0 becomes
    eligible for the next `itest_next_step` call.

### 4.5 Assertions

17. The eleven catalog checks each return their condition. On a failing
    condition they append one structured record
    `(step, current attempt, kind, expected, actual, message)`:
    kinds `true`, `false`, `eq_int`, `ne_int`, `lt_int`, `le_int`, `gt_int`,
    `ge_int`, `eq_str`, `ne_str`, `contains_str`; int values are recorded as
    decimal text, byte/string values verbatim (for `contains_str`, expected
    is the needle and actual the haystack).
18. Assertions never change step status; the caller decides the attempt
    outcome, typically
    `itest_finish_step(h, s, itest_attempt_failure_count(h, s) == 0)`.
19. The failure log is append-only: failures from an earlier attempt remain
    after a successful retry. `itest_attempt_failure_count` counts only the
    step's current attempt; `itest_step_assert_failures` counts all.

### 4.6 Reporting

20. `itest_report` renders, in order: the summary line
    `xiom.itest report: suites=S steps=N passed=P failed=F skipped=K pending=Q running=R tick=T`;
    one block per suite, `suite '<name>': passed=P failed=F skipped=K pending=Q`
    plus one line per step of that suite in declaration order:
    - `  [PASS] <name> attempts=<a> ticks=<t>`
    - `  [FAIL] <name> attempts=<a> ticks=<t>: <message>` (message omitted
      when empty)
    - `  [SKIP] <name>: <message>` (message omitted when empty)
    - `  [PENDING] <name> attempts=<a> ticks=<t>` plus ` wait=<w>` when
      `w > 0`
    - `  [RUNNING] <name> attempts=<a> elapsed=<e>`;
    then `fixtures=N` plus `  [setup] <fixture> (suite '<name>')` /
    `  [teardown] <fixture> (suite '<name>')` lines in execution order;
    then `assertion-failures=N` plus one line per failure:
    `  [FAIL] suite '<s>' step '<step>' attempt=<a> kind=<kind> expected '<e>' actual '<a>'[: <message>]`.
21. Every line ends with `"\n"`, so the empty harness renders exactly:
    `xiom.itest report: suites=0 steps=0 passed=0 failed=0 skipped=0 pending=0 running=0 tick=0\nfixtures=0\nassertion-failures=0\n`.
    The output is byte-stable for a given state. Steps whose suite index is
    out of range are not listed.

### 4.7 Determinism

22. All operations are pure state transitions over the public vectors; the
    same call sequence always produces the same state and report. There is
    no RNG, no I/O and no time source.

## 5. Error catalog

| Condition | Exact message |
|---|---|
| Suite name empty or contains NUL | `itest: invalid suite name` |
| Suite name already declared | `itest: duplicate suite '<name>'` |
| Fixture name empty or contains NUL | `itest: invalid fixture name` |
| Setup fixture already declared for the suite | `itest: duplicate setup fixture '<name>'` |
| Teardown fixture already declared for the suite | `itest: duplicate teardown fixture '<name>'` |
| Step name empty or contains NUL | `itest: invalid step name` |
| Step name already declared | `itest: duplicate step '<name>'` |
| Suite index out of range | `itest: suite index out of range` |
| Step index out of range | `itest: step index out of range` |
| Dependency name empty or contains NUL | `itest: invalid dependency name` |
| Dependency names no declared step | `itest: unknown dependency '<name>'` |
| The dependency is the step itself | `itest: step cannot depend on itself` |
| The dependency is already declared for the step | `itest: duplicate dependency '<name>'` |
| The dependency already depends on the step | `itest: dependency cycle '<name>'` |
| max_attempts < 1 | `itest: max attempts must be >= 1` |
| base < 0 | `itest: backoff base must be >= 0` |
| cap < 0 | `itest: backoff cap must be >= 0` |
| timeout < 0 | `itest: timeout must be >= 0` |
| Begin an open suite | `itest: suite already open` |
| End a closed suite | `itest: suite already closed` |
| End a suite that is still NEW | `itest: suite is not open` |

Step messages (data, not errors):

| Condition | Exact message |
|---|---|
| Dependency failed | `itest: skipped: dependency '<dep>' failed` |
| Dependency skipped | `itest: skipped: dependency '<dep>' skipped` |
| Attempts exhausted | `itest: step '<name>' failed after <n> attempt(s)` |
| Timeout on the last attempt | `itest: step '<name>' timed out after <t> ticks (attempt <a> of <m>)` |

## 6. API contract

```xi
pub const ITEST_PENDING: Int = 0      // step codes
pub const ITEST_RUNNING: Int = 1
pub const ITEST_PASSED: Int = 2
pub const ITEST_FAILED: Int = 3
pub const ITEST_SKIPPED: Int = 4
pub const ITEST_SUITE_NEW: Int = 0    // suite states
pub const ITEST_SUITE_OPEN: Int = 1
pub const ITEST_SUITE_CLOSED: Int = 2
pub const ITEST_SETUP: Int = 0        // fixture phases
pub const ITEST_TEARDOWN: Int = 1

pub fn itest_new() -> ITest
pub fn itest_add_suite(h: &mut ITest, name: Str) -> Result[Int, Str]
pub fn itest_add_setup(h: &mut ITest, suite: Int, fixture: Str) -> Result[Int, Str]
pub fn itest_add_teardown(h: &mut ITest, suite: Int, fixture: Str) -> Result[Int, Str]
pub fn itest_add_step(h: &mut ITest, suite: Int, name: Str) -> Result[Int, Str]
pub fn itest_step_depends_on(h: &mut ITest, step: Int, dep: Str) -> Result[Int, Str]
pub fn itest_step_set_retries(h: &mut ITest, step: Int, max_attempts: Int, base: Int, cap: Int) -> Result[Int, Str]
pub fn itest_step_set_timeout(h: &mut ITest, step: Int, ticks: Int) -> Result[Int, Str]
pub fn itest_begin_suite(h: &mut ITest, suite: Int) -> Result[Int, Str]
pub fn itest_end_suite(h: &mut ITest, suite: Int) -> Result[Int, Str]
pub fn itest_next_step(h: &mut ITest) -> Int
pub fn itest_begin_step(h: &mut ITest, step: Int) -> Int
pub fn itest_finish_step(h: &mut ITest, step: Int, passed: Bool) -> Int
pub fn itest_tick(h: &mut ITest, ticks: Int)
pub fn itest_assert_true(h: &mut ITest, step: Int, cond: Bool, message: Str) -> Bool
pub fn itest_assert_false(h: &mut ITest, step: Int, cond: Bool, message: Str) -> Bool
pub fn itest_assert_eq_int(h: &mut ITest, step: Int, expected: Int, actual: Int, message: Str) -> Bool
pub fn itest_assert_ne_int(h: &mut ITest, step: Int, expected: Int, actual: Int, message: Str) -> Bool
pub fn itest_assert_lt_int(h: &mut ITest, step: Int, left: Int, right: Int, message: Str) -> Bool
pub fn itest_assert_le_int(h: &mut ITest, step: Int, left: Int, right: Int, message: Str) -> Bool
pub fn itest_assert_gt_int(h: &mut ITest, step: Int, left: Int, right: Int, message: Str) -> Bool
pub fn itest_assert_ge_int(h: &mut ITest, step: Int, left: Int, right: Int, message: Str) -> Bool
pub fn itest_assert_eq_str(h: &mut ITest, step: Int, expected: Str, actual: Str, message: Str) -> Bool
pub fn itest_assert_ne_str(h: &mut ITest, step: Int, expected: Str, actual: Str, message: Str) -> Bool
pub fn itest_assert_contains_str(h: &mut ITest, step: Int, haystack: Str, needle: Str, message: Str) -> Bool
pub fn itest_step_count(h: &ITest) -> Int
pub fn itest_step_name(h: &ITest, i: Int) -> Str
pub fn itest_step_suite(h: &ITest, i: Int) -> Int
pub fn itest_step_status(h: &ITest, i: Int) -> Int
pub fn itest_step_attempts(h: &ITest, i: Int) -> Int
pub fn itest_step_ticks(h: &ITest, i: Int) -> Int
pub fn itest_step_elapsed(h: &ITest, i: Int) -> Int
pub fn itest_step_wait(h: &ITest, i: Int) -> Int
pub fn itest_step_message(h: &ITest, i: Int) -> Str
pub fn itest_step_max_attempts(h: &ITest, i: Int) -> Int
pub fn itest_step_backoff_base(h: &ITest, i: Int) -> Int
pub fn itest_step_backoff_cap(h: &ITest, i: Int) -> Int
pub fn itest_step_timeout(h: &ITest, i: Int) -> Int
pub fn itest_step_dep_count(h: &ITest, i: Int) -> Int
pub fn itest_step_dep(h: &ITest, i: Int, k: Int) -> Str
pub fn itest_suite_count(h: &ITest) -> Int
pub fn itest_suite_name(h: &ITest, s: Int) -> Str
pub fn itest_suite_state(h: &ITest, s: Int) -> Int
pub fn itest_fixture_count(h: &ITest) -> Int
pub fn itest_fixture_name(h: &ITest, i: Int) -> Str
pub fn itest_fixture_suite(h: &ITest, i: Int) -> Int
pub fn itest_fixture_phase(h: &ITest, i: Int) -> Int
pub fn itest_now(h: &ITest) -> Int
pub fn itest_count(h: &ITest, status: Int) -> Int
pub fn itest_passed_count(h: &ITest) -> Int
pub fn itest_failed_count(h: &ITest) -> Int
pub fn itest_skipped_count(h: &ITest) -> Int
pub fn itest_pending_count(h: &ITest) -> Int
pub fn itest_running_count(h: &ITest) -> Int
pub fn itest_all_done(h: &ITest) -> Bool
pub fn itest_suite_step_count(h: &ITest, s: Int) -> Int
pub fn itest_suite_count_status(h: &ITest, s: Int, status: Int) -> Int
pub fn itest_suite_passed(h: &ITest, s: Int) -> Int
pub fn itest_suite_failed(h: &ITest, s: Int) -> Int
pub fn itest_suite_skipped(h: &ITest, s: Int) -> Int
pub fn itest_suite_pending(h: &ITest, s: Int) -> Int
pub fn itest_failure_count(h: &ITest) -> Int
pub fn itest_failure_step(h: &ITest, i: Int) -> Int
pub fn itest_failure_suite(h: &ITest, i: Int) -> Int
pub fn itest_failure_attempt(h: &ITest, i: Int) -> Int
pub fn itest_failure_kind(h: &ITest, i: Int) -> Str
pub fn itest_failure_expected(h: &ITest, i: Int) -> Str
pub fn itest_failure_actual(h: &ITest, i: Int) -> Str
pub fn itest_failure_message(h: &ITest, i: Int) -> Str
pub fn itest_step_assert_failures(h: &ITest, step: Int) -> Int
pub fn itest_attempt_failure_count(h: &ITest, step: Int) -> Int
pub fn itest_status_name(status: Int) -> Str
pub fn itest_suite_state_name(state: Int) -> Str
pub fn itest_report(h: &ITest) -> Str
```

Out-of-range positional accessors are bounds-safe: step names, step
messages, suite names, fixture names and failure strings return `""`;
indices return `-1` (`itest_step_suite`, `itest_step_status`, ...,
`itest_step_wait`, `itest_failure_step`, `itest_failure_suite`,
`itest_failure_attempt`); counts return 0 (`itest_step_dep_count`,
`itest_attempt_failure_count`); `itest_suite_state_name`,
`itest_status_name` return `""` for unknown codes. Declaration and suite
lifecycle calls return `Result[Int, Str]`; driver calls return status/code
sentinels (-1 on refusal). Complexity: declarations and name lookups
O(steps/suites/fixtures); `itest_next_step` O(steps^2 + dependencies) worst
case (skip propagation), O(steps) typical; everything else O(steps) or
O(1) except the report, which is O(state size).

## 7. Test matrix

`tests/test_conformance.xi` (module `itest_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All string comparisons go through `str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | fresh harness | section 3, 4.7 |
| t2 | suite declaration validation | rule 1, 2 |
| t3 | setup order / teardown LIFO | rule 5, 6, 7 |
| t4 | suite lifecycle transitions | rule 5, 6, section 5 |
| t5 | step/dependency validation, interleaved deps | rules 1-4, section 5 |
| t6 | scheduler gating, single-flight | rules 9, 10 |
| t7 | transitive skip propagation | rule 8, section 5 |
| t8 | retry backoff growth and success | rules 12-14 |
| t9 | backoff cap and zero-base retry | rule 13 |
| t10 | terminal timeout | rules 15(2) |
| t11 | timeout retry and leftover ticks | rule 15 |
| t12 | assertion catalog success path | rule 17 |
| t13 | all eleven failure kinds | rule 17, 19 |
| t14 | failure accessor bounds | section 6 |
| t15 | per-suite and overall aggregation | rule 20 aggregates |
| t16 | teardown after failure | rule 6 |
| t17 | full report text | rules 20, 21 |
| t18 | empty report text | rule 21 |
| t19 | retry/timeout config validation | section 5 |
| t20 | driver misuse refusals | rules 10-11 |
| t21 | cycle rejection | rule 4 |
| t22 | tick clamping and non-positive ticks | rule 15 |
| t23 | failure message wording | section 5 |
| t24 | cross-suite dependencies | rules 8, 9 |

## 8. Known limitations

- Model only; the caller must perform all real work (no processes, files,
  sockets or FFI).
- Serialized attempts: one RUNNING step at a time; there is no parallel
  scheduling.
- Ticks are logical units; the library has no wall-clock notion.
- After an attempt fails, the caller must call `itest_tick`/`itest_next_step`
  to continue; nothing advances automatically.
- No per-step fixtures and no nested suites.
- A hand-built `ITest` with mismatched parallel vectors is clamped rather
  than repaired.

## 9. Compiler / stdlib notes (v0.62.2)

Free functions only; flat parallel `Vec`s instead of `Vec[StructType]`;
`Result[Int, Str]` construction confined to the leaf helpers `_ok_int` /
`_err_int`; every `Str` element read is bound to a typed local and compared
with `str_compare` (BUG 17); mutating functions take `&mut ITest` and are
called with an explicit `&mut` at every call site. The report is built once
with `xiom.string.builder` over `Vec[UInt8]` and materialized with
`sb_to_str`; integers are formatted with `xiom.convert.int_to_string` (never
`sb_push_int`). The suite is green on v0.62.2 with `program_exit=0`.
