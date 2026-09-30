// XIOM -- xiom.itest: deterministic integration-test harness model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no process or file I/O. This module
// models an integration-test run as a plain value that a caller drives one
// explicit step at a time:
//
//   suites -> fixtures (setup runs in declaration order; teardown is LIFO)
//     -> steps (declaration-order scheduler, dependencies, skip propagation,
//        retries with capped tick backoff, per-attempt tick timeouts)
//     -> assertions (fixed catalog, structured failure records)
//     -> aggregation and a deterministic text report.
//
// Time is a logical clock measured in ticks. Nothing executes on its own:
// `itest_tick` only advances the clock, and the only automatic transitions
// are dependency skip propagation (in itest_next_step) and attempt timeouts
// (in itest_tick). Attempt outcomes are supplied by the caller through
// itest_finish_step.
//
// Language notes (XIOM v0.62.2): free functions only; flat parallel Vecs
// instead of Vec[StructType]; every Str element read is bound to a typed
// local and compared with xiom.string.compare.str_compare; Result[Int, Str]
// values are constructed only in the leaf helpers _ok_int/_err_int.

module xiom.itest

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Status and phase codes
// --------------------------------------------------

/// Step has not run yet (fresh or waiting for a retry backoff).
pub const ITEST_PENDING: Int = 0;
/// Step attempt is in progress.
pub const ITEST_RUNNING: Int = 1;
/// Step finished successfully.
pub const ITEST_PASSED: Int = 2;
/// Step exhausted its attempts (or timed out terminally).
pub const ITEST_FAILED: Int = 3;
/// Step was skipped because a dependency failed or was skipped.
pub const ITEST_SKIPPED: Int = 4;

/// Suite never opened.
pub const ITEST_SUITE_NEW: Int = 0;
/// Suite open: setup fixtures ran, steps may run.
pub const ITEST_SUITE_OPEN: Int = 1;
/// Suite closed: teardown fixtures ran.
pub const ITEST_SUITE_CLOSED: Int = 2;

/// Fixture log phase: a setup fixture.
pub const ITEST_SETUP: Int = 0;
/// Fixture log phase: a teardown fixture.
pub const ITEST_TEARDOWN: Int = 1;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One integration-test run: suites, declared fixtures, steps and their
/// scheduling configuration, runtime state, the fixture execution log and
/// the structured assertion-failure log.
///
/// All declaration vectors are index-aligned per step (or per suite) in
/// declaration order; runtime vectors mirror them. Step dependencies live in
/// one flat `step_deps` list; step `i` owns the slice starting at
/// `step_dep_start[i]` with `step_dep_count[i]` entries. Read fields through
/// the accessors so out-of-range indices stay safe.
pub type ITest = {
  suite_names: Vec[Str];
  suite_state: Vec[Int];
  setup_names: Vec[Str];
  setup_suite: Vec[Int];
  teardown_names: Vec[Str];
  teardown_suite: Vec[Int];
  fixture_log: Vec[Str];
  fixture_log_suite: Vec[Int];
  fixture_log_phase: Vec[Int];
  step_names: Vec[Str];
  step_suites: Vec[Int];
  step_deps: Vec[Str];
  step_dep_start: Vec[Int];
  step_dep_count: Vec[Int];
  step_max_attempts: Vec[Int];
  step_backoff_base: Vec[Int];
  step_backoff_cap: Vec[Int];
  step_timeout: Vec[Int];
  step_status: Vec[Int];
  step_attempts: Vec[Int];
  step_elapsed: Vec[Int];
  step_ticks: Vec[Int];
  step_wait: Vec[Int];
  step_messages: Vec[Str];
  fail_steps: Vec[Int];
  fail_attempts: Vec[Int];
  fail_kinds: Vec[Str];
  fail_expected: Vec[Str];
  fail_actual: Vec[Str];
  fail_messages: Vec[Str];
  now: Int;
}

// --------------------------------------------------
//  Counts and bounds
// --------------------------------------------------

// Number of steps: the minimum length of every step vector, so a hand-built
// state with drifted vectors cannot be read out of range.
fn _step_count(h: &ITest) -> Int {
  var n = h.step_names.len();
  if h.step_suites.len() < n { n = h.step_suites.len(); }
  if h.step_dep_start.len() < n { n = h.step_dep_start.len(); }
  if h.step_dep_count.len() < n { n = h.step_dep_count.len(); }
  if h.step_max_attempts.len() < n { n = h.step_max_attempts.len(); }
  if h.step_backoff_base.len() < n { n = h.step_backoff_base.len(); }
  if h.step_backoff_cap.len() < n { n = h.step_backoff_cap.len(); }
  if h.step_timeout.len() < n { n = h.step_timeout.len(); }
  if h.step_status.len() < n { n = h.step_status.len(); }
  if h.step_attempts.len() < n { n = h.step_attempts.len(); }
  if h.step_elapsed.len() < n { n = h.step_elapsed.len(); }
  if h.step_ticks.len() < n { n = h.step_ticks.len(); }
  if h.step_wait.len() < n { n = h.step_wait.len(); }
  if h.step_messages.len() < n { n = h.step_messages.len(); }
  return n;
}

// Number of suites: the minimum length of the suite vectors.
fn _suite_count(h: &ITest) -> Int {
  var n = h.suite_names.len();
  if h.suite_state.len() < n { n = h.suite_state.len(); }
  return n;
}

// Number of executed fixtures in the log: the minimum length of the three
// fixture-log vectors.
fn _fixture_count(h: &ITest) -> Int {
  var n = h.fixture_log.len();
  if h.fixture_log_suite.len() < n { n = h.fixture_log_suite.len(); }
  if h.fixture_log_phase.len() < n { n = h.fixture_log_phase.len(); }
  return n;
}

// Number of structured assertion failures: the minimum length of the six
// failure vectors.
fn _failure_count(h: &ITest) -> Int {
  var n = h.fail_steps.len();
  if h.fail_attempts.len() < n { n = h.fail_attempts.len(); }
  if h.fail_kinds.len() < n { n = h.fail_kinds.len(); }
  if h.fail_expected.len() < n { n = h.fail_expected.len(); }
  if h.fail_actual.len() < n { n = h.fail_actual.len(); }
  if h.fail_messages.len() < n { n = h.fail_messages.len(); }
  return n;
}

// Number of declared setup fixtures: the minimum length of the two vectors.
fn _setup_decl_count(h: &ITest) -> Int {
  var n = h.setup_names.len();
  if h.setup_suite.len() < n { n = h.setup_suite.len(); }
  return n;
}

// Number of declared teardown fixtures: the minimum of the two vectors.
fn _teardown_decl_count(h: &ITest) -> Int {
  var n = h.teardown_names.len();
  if h.teardown_suite.len() < n { n = h.teardown_suite.len(); }
  return n;
}

// --------------------------------------------------
//  Names and lookups
// --------------------------------------------------

// A declaration name is valid when it is non-empty and contains no 0x00 byte
// (built strings are NUL-terminated, so NUL bytes inside a name are unsafe).
fn _name_ok(name: Str) -> Bool {
  let n = name.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  while i < n {
    if string.byte_at(name, i) == 0u8 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Index of the suite named `name`, or -1.
fn _suite_index(h: &ITest, name: Str) -> Int {
  var i = 0;
  let n = _suite_count(h);
  while i < n {
    let cur: Str = h.suite_names[i];
    if compare.str_compare(cur, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the step named `name`, or -1.
fn _step_index(h: &ITest, name: Str) -> Int {
  var i = 0;
  let n = _step_count(h);
  while i < n {
    let cur: Str = h.step_names[i];
    if compare.str_compare(cur, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the declared setup fixture `name` owned by `suite`, or -1.
fn _setup_fixture_index(h: &ITest, suite: Int, name: Str) -> Int {
  var i = 0;
  let n = _setup_decl_count(h);
  while i < n {
    let owner: Int = h.setup_suite[i];
    if owner == suite {
      let cur: Str = h.setup_names[i];
      if compare.str_compare(cur, name) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// Index of the declared teardown fixture `name` owned by `suite`, or -1.
fn _teardown_fixture_index(h: &ITest, suite: Int, name: Str) -> Int {
  var i = 0;
  let n = _teardown_decl_count(h);
  while i < n {
    let owner: Int = h.teardown_suite[i];
    if owner == suite {
      let cur: Str = h.teardown_names[i];
      if compare.str_compare(cur, name) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// True when suite `s` exists and is open.
fn _suite_is_open(h: &ITest, s: Int) -> Bool {
  let n = _suite_count(h);
  if s < 0 || s >= n {
    return false;
  }
  let st: Int = h.suite_state[s];
  return st == ITEST_SUITE_OPEN;
}

// --------------------------------------------------
//  Dependencies
// --------------------------------------------------

// Number of declared dependencies of `step` (0 for an out-of-range step).
fn _dep_count_at(h: &ITest, step: Int) -> Int {
  if step < 0 || step >= _step_count(h) {
    return 0;
  }
  let c: Int = h.step_dep_count[step];
  if c < 0 {
    return 0;
  }
  return c;
}

// `k`-th declared dependency name of `step`, or "" out of range.
fn _dep_at(h: &ITest, step: Int, k: Int) -> Str {
  if k < 0 || k >= _dep_count_at(h, step) {
    return "";
  }
  let base: Int = h.step_dep_start[step];
  let idx = base + k;
  if idx < 0 || idx >= h.step_deps.len() {
    return "";
  }
  let v: Str = h.step_deps[idx];
  return v;
}

// True when every declared dependency of `step` is satisfied (unknown
// dependency names are ignored). A dependency is satisfied only by PASSED.
fn _deps_satisfied(h: &ITest, step: Int) -> Bool {
  var k = 0;
  let n = _dep_count_at(h, step);
  while k < n {
    let dn: Str = _dep_at(h, step, k);
    let di = _step_index(h, dn);
    if di >= 0 {
      let st: Int = h.step_status[di];
      if st != ITEST_PASSED {
        return false;
      }
    }
    k = k + 1;
  }
  return true;
}

// Index of the first dependency of `step` that FAILED or was SKIPPED, or -1.
fn _first_blocking_dep(h: &ITest, step: Int) -> Int {
  var k = 0;
  let n = _dep_count_at(h, step);
  while k < n {
    let dn: Str = _dep_at(h, step, k);
    let di = _step_index(h, dn);
    if di >= 0 {
      let st: Int = h.step_status[di];
      if st == ITEST_FAILED || st == ITEST_SKIPPED {
        return di;
      }
    }
    k = k + 1;
  }
  return -1;
}

// Mark PENDING steps whose dependency FAILED or was SKIPPED as SKIPPED,
// repeating until a full pass changes nothing so skips propagate through
// chains. Each outer iteration marks at least one new step (bounded by the
// step count) or terminates.
fn _propagate_skips(h: &mut ITest) {
  var changed = true;
  while changed {
    changed = false;
    var i = 0;
    let n = _step_count(h);
    while i < n {
      let st: Int = h.step_status[i];
      if st == ITEST_PENDING {
        let b = _first_blocking_dep(h, i);
        if b >= 0 {
          let bst: Int = h.step_status[b];
          let bname: Str = h.step_names[b];
          if bst == ITEST_FAILED {
            h.step_messages[i] = "itest: skipped: dependency '" + bname + "' failed";
          } else {
            h.step_messages[i] = "itest: skipped: dependency '" + bname + "' skipped";
          }
          h.step_status[i] = ITEST_SKIPPED;
          h.step_wait[i] = 0;
          changed = true;
        }
      }
      i = i + 1;
    }
  }
}

// True when `from` depends on `target` transitively (or directly). Iterative
// relaxation: every outer pass marks at least one new step reachable or ends,
// so a hand-built cyclic graph cannot loop forever.
fn _dep_reaches(h: &ITest, from: Int, target: Int) -> Bool {
  let n = _step_count(h);
  if from < 0 || from >= n || target < 0 || target >= n {
    return false;
  }
  var seen = Vec[Int].new();
  var i = 0;
  while i < n {
    seen.push(0);
    i = i + 1;
  }
  seen[from] = 1;
  var changed = true;
  while changed {
    changed = false;
    i = 0;
    while i < n {
      let sv: Int = seen[i];
      if sv == 1 {
        if i == target {
          return true;
        }
        var k = 0;
        while k < _dep_count_at(h, i) {
          let dn: Str = _dep_at(h, i, k);
          let di = _step_index(h, dn);
          if di >= 0 {
            let dsv: Int = seen[di];
            if dsv == 0 {
              seen[di] = 1;
              changed = true;
            }
          }
          k = k + 1;
        }
      }
      i = i + 1;
    }
  }
  return false;
}

// --------------------------------------------------
//  Retry backoff and failure recording
// --------------------------------------------------

// Backoff ticks to wait before the retry that follows the attempts already
// made: min(base * 2^(attempts-1), cap), with 0 when base <= 0 or cap <= 0.
// Doubling stops at the cap, so large attempt counts cannot overflow.
fn _backoff_for(h: &ITest, step: Int) -> Int {
  let a: Int = h.step_attempts[step];
  let base: Int = h.step_backoff_base[step];
  let cap: Int = h.step_backoff_cap[step];
  if base <= 0 || cap <= 0 {
    return 0;
  }
  var w = base;
  if w > cap {
    w = cap;
  }
  var k = 1;
  while k < a && w < cap {
    if w > cap - w {
      w = cap;
    } else {
      w = w + w;
    }
    k = k + 1;
  }
  return w;
}

// "attempt" for 1, "attempts" otherwise.
fn _attempt_word(n: Int) -> Str {
  if n == 1 {
    return "attempt";
  }
  return "attempts";
}

// Append one structured failure for `step`. The attempt number is the step's
// current attempt count (0 when `step` is out of range).
fn _record_failure(h: &mut ITest, step: Int, kind: Str, expected: Str, actual: Str, message: Str) {
  var attempt: Int = 0;
  let n = _step_count(h);
  if step >= 0 && step < n {
    let a: Int = h.step_attempts[step];
    attempt = a;
  }
  h.fail_steps.push(step);
  h.fail_attempts.push(attempt);
  h.fail_kinds.push(kind);
  h.fail_expected.push(expected);
  h.fail_actual.push(actual);
  h.fail_messages.push(message);
}

// --------------------------------------------------
//  Construction
// --------------------------------------------------

/// A fresh, empty harness: no suites, no fixtures, no steps, clock at 0.
/// Params: none.
/// Returns: an empty ITest.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_new() -> ITest {
  return ITest{
    suite_names: Vec[Str].new();
    suite_state: Vec[Int].new();
    setup_names: Vec[Str].new();
    setup_suite: Vec[Int].new();
    teardown_names: Vec[Str].new();
    teardown_suite: Vec[Int].new();
    fixture_log: Vec[Str].new();
    fixture_log_suite: Vec[Int].new();
    fixture_log_phase: Vec[Int].new();
    step_names: Vec[Str].new();
    step_suites: Vec[Int].new();
    step_deps: Vec[Str].new();
    step_dep_start: Vec[Int].new();
    step_dep_count: Vec[Int].new();
    step_max_attempts: Vec[Int].new();
    step_backoff_base: Vec[Int].new();
    step_backoff_cap: Vec[Int].new();
    step_timeout: Vec[Int].new();
    step_status: Vec[Int].new();
    step_attempts: Vec[Int].new();
    step_elapsed: Vec[Int].new();
    step_ticks: Vec[Int].new();
    step_wait: Vec[Int].new();
    step_messages: Vec[Str].new();
    fail_steps: Vec[Int].new();
    fail_attempts: Vec[Int].new();
    fail_kinds: Vec[Str].new();
    fail_expected: Vec[Str].new();
    fail_actual: Vec[Str].new();
    fail_messages: Vec[Str].new();
    now: 0;
  };
}

// --------------------------------------------------
//  Declaration API
// --------------------------------------------------

/// Declare a suite. Suites are declared before the fixtures and steps that
/// belong to them.
/// Params: h - the harness; name - non-empty, NUL-free, case-sensitive and
/// unique.
/// Returns: Ok(index) with the suite's declaration index.
/// Error case: Err("itest: invalid suite name") or
/// Err("itest: duplicate suite '<name>'"); a failed call never mutates h.
/// Complexity: O(suites).
pub fn itest_add_suite(h: &mut ITest, name: Str) -> Result[Int, Str] {
  if !_name_ok(name) {
    return _err_int("itest: invalid suite name");
  }
  if _suite_index(h, name) >= 0 {
    return _err_int("itest: duplicate suite '" + name + "'");
  }
  h.suite_names.push(name);
  h.suite_state.push(ITEST_SUITE_NEW);
  return _ok_int(_suite_count(h) - 1);
}

/// Declare a setup fixture of `suite`. Setup fixtures run in declaration
/// order when the suite is opened.
/// Params: h - the harness; suite - a declared suite index; fixture -
/// non-empty, NUL-free and unique among this suite's setup fixtures.
/// Returns: Ok(index) with the declaration index of the fixture entry.
/// Error case: Err("itest: suite index out of range"),
/// Err("itest: invalid fixture name") or
/// Err("itest: duplicate setup fixture '<name>'"); never mutates h on error.
/// Complexity: O(fixtures).
pub fn itest_add_setup(h: &mut ITest, suite: Int, fixture: Str) -> Result[Int, Str] {
  if suite < 0 || suite >= _suite_count(h) {
    return _err_int("itest: suite index out of range");
  }
  if !_name_ok(fixture) {
    return _err_int("itest: invalid fixture name");
  }
  if _setup_fixture_index(h, suite, fixture) >= 0 {
    return _err_int("itest: duplicate setup fixture '" + fixture + "'");
  }
  h.setup_names.push(fixture);
  h.setup_suite.push(suite);
  return _ok_int(_setup_decl_count(h) - 1);
}

/// Declare a teardown fixture of `suite`. Teardown fixtures run LIFO
/// (reverse declaration order) when the suite is closed, whether its steps
/// passed or failed.
/// Params: h - the harness; suite - a declared suite index; fixture -
/// non-empty, NUL-free and unique among this suite's teardown fixtures.
/// Returns: Ok(index) with the declaration index of the fixture entry.
/// Error case: Err("itest: suite index out of range"),
/// Err("itest: invalid fixture name") or
/// Err("itest: duplicate teardown fixture '<name>'"); never mutates h.
/// Complexity: O(fixtures).
pub fn itest_add_teardown(h: &mut ITest, suite: Int, fixture: Str) -> Result[Int, Str] {
  if suite < 0 || suite >= _suite_count(h) {
    return _err_int("itest: suite index out of range");
  }
  if !_name_ok(fixture) {
    return _err_int("itest: invalid fixture name");
  }
  if _teardown_fixture_index(h, suite, fixture) >= 0 {
    return _err_int("itest: duplicate teardown fixture '" + fixture + "'");
  }
  h.teardown_names.push(fixture);
  h.teardown_suite.push(suite);
  return _ok_int(_teardown_decl_count(h) - 1);
}

/// Declare a step of `suite`. Step names form a global, case-sensitive
/// namespace for dependencies. Defaults: one attempt, no backoff, no
/// timeout, PENDING.
/// Params: h - the harness; suite - a declared suite index; name -
/// non-empty, NUL-free and globally unique.
/// Returns: Ok(index) with the step's declaration index.
/// Error case: Err("itest: suite index out of range"),
/// Err("itest: invalid step name") or Err("itest: duplicate step '<name>'");
/// never mutates h on error.
/// Complexity: O(steps).
pub fn itest_add_step(h: &mut ITest, suite: Int, name: Str) -> Result[Int, Str] {
  if suite < 0 || suite >= _suite_count(h) {
    return _err_int("itest: suite index out of range");
  }
  if !_name_ok(name) {
    return _err_int("itest: invalid step name");
  }
  if _step_index(h, name) >= 0 {
    return _err_int("itest: duplicate step '" + name + "'");
  }
  h.step_names.push(name);
  h.step_suites.push(suite);
  h.step_dep_start.push(h.step_deps.len());
  h.step_dep_count.push(0);
  h.step_max_attempts.push(1);
  h.step_backoff_base.push(0);
  h.step_backoff_cap.push(0);
  h.step_timeout.push(0);
  h.step_status.push(ITEST_PENDING);
  h.step_attempts.push(0);
  h.step_elapsed.push(0);
  h.step_ticks.push(0);
  h.step_wait.push(0);
  h.step_messages.push("");
  return _ok_int(_step_count(h) - 1);
}

/// Declare that `step` depends on the step named `dep`. A step runs only
/// when every dependency has PASSED; when a dependency FAILED or was
/// SKIPPED, the step is itself marked SKIPPED by the next
/// itest_next_step call. Self-dependencies, duplicates and cycles are
/// rejected at declaration time, so the dependency graph stays acyclic.
/// Params: h - the harness; step - a declared step index; dep - the name of
/// a declared, different step.
/// Returns: Ok(n) with the number of dependencies of `step` after the call.
/// Error case: Err("itest: step index out of range"),
/// Err("itest: invalid dependency name"),
/// Err("itest: unknown dependency '<name>'"),
/// Err("itest: step cannot depend on itself"),
/// Err("itest: duplicate dependency '<name>'") or
/// Err("itest: dependency cycle '<name>'"); never mutates h on error.
/// Complexity: O(steps + dependencies).
pub fn itest_step_depends_on(h: &mut ITest, step: Int, dep: Str) -> Result[Int, Str] {
  let n = _step_count(h);
  if step < 0 || step >= n {
    return _err_int("itest: step index out of range");
  }
  if !_name_ok(dep) {
    return _err_int("itest: invalid dependency name");
  }
  let di = _step_index(h, dep);
  if di < 0 {
    return _err_int("itest: unknown dependency '" + dep + "'");
  }
  let self_name: Str = h.step_names[step];
  if compare.str_compare(self_name, dep) == 0 {
    return _err_int("itest: step cannot depend on itself");
  }
  var k = 0;
  while k < _dep_count_at(h, step) {
    let cur: Str = _dep_at(h, step, k);
    if compare.str_compare(cur, dep) == 0 {
      return _err_int("itest: duplicate dependency '" + dep + "'");
    }
    k = k + 1;
  }
  if _dep_reaches(h, di, step) {
    return _err_int("itest: dependency cycle '" + dep + "'");
  }
  let c: Int = h.step_dep_count[step];
  let old_start: Int = h.step_dep_start[step];
  let new_start = h.step_deps.len();
  if c > 0 {
    var k = 0;
    while k < c {
      let v: Str = h.step_deps[old_start + k];
      h.step_deps.push(v);
      k = k + 1;
    }
  }
  h.step_dep_start[step] = new_start;
  h.step_deps.push(dep);
  h.step_dep_count[step] = c + 1;
  return _ok_int(c + 1);
}

/// Configure retries for `step`. The retry that follows a failed attempt `a`
/// waits min(base * 2^(a-1), cap) ticks before the step becomes eligible
/// again; the wait elapses only through explicit itest_tick calls. base 0 or
/// cap 0 means no backoff (an immediate retry).
/// Params: h - the harness; step - a declared step index; max_attempts - the
/// total attempt budget (>= 1); base - the first backoff in ticks (>= 0);
/// cap - the backoff ceiling in ticks (>= 0).
/// Returns: Ok(step).
/// Error case: Err("itest: step index out of range"),
/// Err("itest: max attempts must be >= 1"),
/// Err("itest: backoff base must be >= 0") or
/// Err("itest: backoff cap must be >= 0"); never mutates h on error.
/// Complexity: O(1).
pub fn itest_step_set_retries(h: &mut ITest, step: Int, max_attempts: Int, base: Int, cap: Int) -> Result[Int, Str] {
  let n = _step_count(h);
  if step < 0 || step >= n {
    return _err_int("itest: step index out of range");
  }
  if max_attempts < 1 {
    return _err_int("itest: max attempts must be >= 1");
  }
  if base < 0 {
    return _err_int("itest: backoff base must be >= 0");
  }
  if cap < 0 {
    return _err_int("itest: backoff cap must be >= 0");
  }
  h.step_max_attempts[step] = max_attempts;
  h.step_backoff_base[step] = base;
  h.step_backoff_cap[step] = cap;
  return _ok_int(step);
}

/// Set the per-attempt tick timeout of `step`. While an attempt is RUNNING
/// its elapsed ticks grow with itest_tick; the tick that brings the elapsed
/// time to `ticks` fails the attempt (and, when attempts remain, arms a
/// retry). 0 disables the timeout.
/// Params: h - the harness; step - a declared step index; ticks - the
/// timeout in ticks (>= 0; 0 = none).
/// Returns: Ok(step).
/// Error case: Err("itest: step index out of range") or
/// Err("itest: timeout must be >= 0"); never mutates h on error.
/// Complexity: O(1).
pub fn itest_step_set_timeout(h: &mut ITest, step: Int, ticks: Int) -> Result[Int, Str] {
  let n = _step_count(h);
  if step < 0 || step >= n {
    return _err_int("itest: step index out of range");
  }
  if ticks < 0 {
    return _err_int("itest: timeout must be >= 0");
  }
  h.step_timeout[step] = ticks;
  return _ok_int(step);
}

// --------------------------------------------------
//  Suite lifecycle
// --------------------------------------------------

/// Open `suite`: mark it open and append its setup fixtures to the fixture
/// log in declaration order. Steps of the suite become candidates for
/// itest_next_step only while it is open.
/// Params: h - the harness; suite - a declared suite index.
/// Returns: Ok(suite) on success.
/// Error case: Err("itest: suite index out of range"),
/// Err("itest: suite already open") or Err("itest: suite already closed").
/// Complexity: O(fixtures).
pub fn itest_begin_suite(h: &mut ITest, suite: Int) -> Result[Int, Str] {
  let n = _suite_count(h);
  if suite < 0 || suite >= n {
    return _err_int("itest: suite index out of range");
  }
  let st: Int = h.suite_state[suite];
  if st == ITEST_SUITE_OPEN {
    return _err_int("itest: suite already open");
  }
  if st == ITEST_SUITE_CLOSED {
    return _err_int("itest: suite already closed");
  }
  h.suite_state[suite] = ITEST_SUITE_OPEN;
  var i = 0;
  let total = _setup_decl_count(h);
  while i < total {
    let owner: Int = h.setup_suite[i];
    if owner == suite {
      let fname: Str = h.setup_names[i];
      h.fixture_log.push(fname);
      h.fixture_log_suite.push(suite);
      h.fixture_log_phase.push(ITEST_SETUP);
    }
    i = i + 1;
  }
  return _ok_int(suite);
}

/// Close `suite`: mark it closed and append its teardown fixtures to the
/// fixture log LIFO (reverse declaration order). Teardown runs on failure
/// too: the caller can always close an open suite, whatever its step
/// outcomes were.
/// Params: h - the harness; suite - a declared suite index.
/// Returns: Ok(suite) on success.
/// Error case: Err("itest: suite index out of range") or
/// Err("itest: suite is not open").
/// Complexity: O(fixtures).
pub fn itest_end_suite(h: &mut ITest, suite: Int) -> Result[Int, Str] {
  let n = _suite_count(h);
  if suite < 0 || suite >= n {
    return _err_int("itest: suite index out of range");
  }
  let st: Int = h.suite_state[suite];
  if st == ITEST_SUITE_CLOSED {
    return _err_int("itest: suite already closed");
  }
  if st != ITEST_SUITE_OPEN {
    return _err_int("itest: suite is not open");
  }
  h.suite_state[suite] = ITEST_SUITE_CLOSED;
  let total = _teardown_decl_count(h);
  var i = total - 1;
  while i >= 0 {
    let owner: Int = h.teardown_suite[i];
    if owner == suite {
      let fname: Str = h.teardown_names[i];
      h.fixture_log.push(fname);
      h.fixture_log_suite.push(suite);
      h.fixture_log_phase.push(ITEST_TEARDOWN);
    }
    i = i - 1;
  }
  return _ok_int(suite);
}

// --------------------------------------------------
//  Driver: scheduler, attempts, ticks
// --------------------------------------------------

/// Advance the harness to its next runnable step and return its index.
/// First propagates dependency skips (PENDING steps whose dependency FAILED
/// or was SKIPPED become SKIPPED). Then scans steps in declaration order and
/// returns the first PENDING step that is not waiting for a retry backoff,
/// belongs to an open suite and has every dependency PASSED. Returns -1 when
/// no step is runnable; -1 also while any step is RUNNING, because a step is
/// always driven to completion before the next one begins.
/// Params: h - the harness.
/// Returns: the step index, or -1.
/// Error case: none.
/// Complexity: O(steps^2 + dependencies) in the worst case (skip
/// propagation); O(steps) typical.
pub fn itest_next_step(h: &mut ITest) -> Int {
  var i = 0;
  let n = _step_count(h);
  while i < n {
    let st: Int = h.step_status[i];
    if st == ITEST_RUNNING {
      return -1;
    }
    i = i + 1;
  }
  _propagate_skips(h);
  i = 0;
  while i < n {
    let st: Int = h.step_status[i];
    if st == ITEST_PENDING {
      let w: Int = h.step_wait[i];
      if w == 0 {
        let s: Int = h.step_suites[i];
        if _suite_is_open(h, s) {
          if _deps_satisfied(h, i) {
            return i;
          }
        }
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Begin the next attempt of `step`: requires PENDING, no pending backoff,
/// an open owning suite, all dependencies PASSED and no other RUNNING step.
/// Increments the attempt count, marks the step RUNNING and resets the
/// attempt clock.
/// Params: h - the harness; step - a step index.
/// Returns: ITEST_RUNNING (1) on success, -1 when the step is not eligible.
/// Error case: none (ineligible transitions are refused without mutation).
/// Complexity: O(steps + dependencies).
pub fn itest_begin_step(h: &mut ITest, step: Int) -> Int {
  let n = _step_count(h);
  if step < 0 || step >= n {
    return -1;
  }
  if h.step_status[step] != ITEST_PENDING {
    return -1;
  }
  let w: Int = h.step_wait[step];
  if w != 0 {
    return -1;
  }
  let s: Int = h.step_suites[step];
  if !_suite_is_open(h, s) {
    return -1;
  }
  if !_deps_satisfied(h, step) {
    return -1;
  }
  var i = 0;
  while i < n {
    let st: Int = h.step_status[i];
    if st == ITEST_RUNNING {
      return -1;
    }
    i = i + 1;
  }
  let a: Int = h.step_attempts[step];
  h.step_attempts[step] = a + 1;
  h.step_status[step] = ITEST_RUNNING;
  h.step_elapsed[step] = 0;
  h.step_messages[step] = "";
  return ITEST_RUNNING;
}

/// Finish the current attempt of a RUNNING `step` with the caller-supplied
/// outcome. The attempt's elapsed ticks are folded into the step's total.
/// On success the step becomes PASSED. On failure with attempts remaining
/// the step returns to PENDING with a capped backoff wait; on the last
/// failed attempt it becomes FAILED with a terminal message.
/// Params: h - the harness; step - a step index; passed - the attempt
/// outcome.
/// Returns: the new status code (ITEST_PASSED, ITEST_PENDING or
/// ITEST_FAILED), or -1 when `step` is not RUNNING.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_finish_step(h: &mut ITest, step: Int, passed: Bool) -> Int {
  let n = _step_count(h);
  if step < 0 || step >= n {
    return -1;
  }
  if h.step_status[step] != ITEST_RUNNING {
    return -1;
  }
  let elapsed: Int = h.step_elapsed[step];
  let total: Int = h.step_ticks[step];
  h.step_ticks[step] = total + elapsed;
  h.step_elapsed[step] = 0;
  if passed {
    h.step_status[step] = ITEST_PASSED;
    h.step_wait[step] = 0;
    h.step_messages[step] = "";
    return ITEST_PASSED;
  }
  let a: Int = h.step_attempts[step];
  let m: Int = h.step_max_attempts[step];
  if a < m {
    h.step_status[step] = ITEST_PENDING;
    h.step_wait[step] = _backoff_for(h, step);
    h.step_messages[step] = "";
    return ITEST_PENDING;
  }
  let name: Str = h.step_names[step];
  h.step_status[step] = ITEST_FAILED;
  h.step_wait[step] = 0;
  h.step_messages[step] = "itest: step '" + name + "' failed after " + int_to_string(a) + " " + _attempt_word(a);
  return ITEST_FAILED;
}

/// Advance the logical clock by `ticks` (> 0; other values are ignored).
/// RUNNING steps gain elapsed time; the tick that brings an attempt to its
/// timeout fails the attempt (arming a retry when attempts remain, where
/// only the ticks after the timeout instant count against the backoff).
/// PENDING steps with a retry wait have it reduced, never below 0. Ticking
/// never starts or finishes a step by itself.
/// Params: h - the harness; ticks - ticks to advance.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(steps).
pub fn itest_tick(h: &mut ITest, ticks: Int) {
  if ticks <= 0 {
    return;
  }
  h.now = h.now + ticks;
  var i = 0;
  let n = _step_count(h);
  while i < n {
    let st: Int = h.step_status[i];
    if st == ITEST_RUNNING {
      let t: Int = h.step_timeout[i];
      let e: Int = h.step_elapsed[i];
      if t > 0 && ticks >= t - e {
        let used = t - e;
        let rest = ticks - used;
        let total: Int = h.step_ticks[i];
        h.step_ticks[i] = total + e + used;
        h.step_elapsed[i] = 0;
        let a: Int = h.step_attempts[i];
        let m: Int = h.step_max_attempts[i];
        let name: Str = h.step_names[i];
        if a < m {
          h.step_status[i] = ITEST_PENDING;
          var w = _backoff_for(h, i);
          if w > rest {
            w = w - rest;
          } else {
            w = 0;
          }
          h.step_wait[i] = w;
          h.step_messages[i] = "";
        } else {
          h.step_status[i] = ITEST_FAILED;
          h.step_wait[i] = 0;
          h.step_messages[i] = "itest: step '" + name + "' timed out after " + int_to_string(t)
            + " ticks (attempt " + int_to_string(a) + " of " + int_to_string(m) + ")";
        }
      } else {
        h.step_elapsed[i] = e + ticks;
      }
    } elif st == ITEST_PENDING {
      let w: Int = h.step_wait[i];
      if w > 0 {
        if w > ticks {
          h.step_wait[i] = w - ticks;
        } else {
          h.step_wait[i] = 0;
        }
      }
    }
    i = i + 1;
  }
}

// --------------------------------------------------
//  Assertion catalog (structured failures)
// --------------------------------------------------
//
// Every assertion checks a condition and, when it does not hold, appends one
// structured failure (step, current attempt, kind, expected, actual,
// message) to the failure log before returning false. Assertions never
// change step status: the caller decides the attempt outcome from the
// return value (or via itest_attempt_failure_count) and calls
// itest_finish_step. The failure log is append-only, so failures from an
// attempt that was later retried successfully stay visible.

/// Assert that `cond` is true. Failure kind "true".
/// Params: h - the harness; step - the step the assertion belongs to (any
/// index; out-of-range steps record -1); cond - the condition; message - the
/// failure text.
/// Returns: cond.
/// Error case: none.
/// Complexity: O(1) plus one failure record.
pub fn itest_assert_true(h: &mut ITest, step: Int, cond: Bool, message: Str) -> Bool {
  if cond {
    return true;
  }
  _record_failure(h, step, "true", "true", "false", message);
  return false;
}

/// Assert that `cond` is false. Failure kind "false".
/// Params/Returns: as itest_assert_true; passes when cond is false.
/// Error case: none.
/// Complexity: O(1) plus one failure record.
pub fn itest_assert_false(h: &mut ITest, step: Int, cond: Bool, message: Str) -> Bool {
  if !cond {
    return true;
  }
  _record_failure(h, step, "false", "false", "true", message);
  return false;
}

/// Assert `expected == actual`. Failure kind "eq_int".
/// Params: h - the harness; step - the owning step; expected/actual - the
/// compared values; message - the failure text. Expected/actual are recorded
/// as decimal text.
/// Returns: true when equal.
/// Error case: none.
/// Complexity: O(1) plus one failure record.
pub fn itest_assert_eq_int(h: &mut ITest, step: Int, expected: Int, actual: Int, message: Str) -> Bool {
  if expected == actual {
    return true;
  }
  _record_failure(h, step, "eq_int", int_to_string(expected), int_to_string(actual), message);
  return false;
}

/// Assert `expected != actual`. Failure kind "ne_int".
/// Params/Returns: as itest_assert_eq_int.
/// Error case: none.
/// Complexity: O(1) plus one failure record.
pub fn itest_assert_ne_int(h: &mut ITest, step: Int, expected: Int, actual: Int, message: Str) -> Bool {
  if expected != actual {
    return true;
  }
  _record_failure(h, step, "ne_int", int_to_string(expected), int_to_string(actual), message);
  return false;
}

/// Assert `left < right`. Failure kind "lt_int".
/// Params: h - the harness; step - the owning step; left/right - the
/// compared values; message - the failure text.
/// Returns: true when left < right.
/// Error case: none.
/// Complexity: O(1) plus one failure record.
pub fn itest_assert_lt_int(h: &mut ITest, step: Int, left: Int, right: Int, message: Str) -> Bool {
  if left < right {
    return true;
  }
  _record_failure(h, step, "lt_int", int_to_string(left), int_to_string(right), message);
  return false;
}

/// Assert `left <= right`. Failure kind "le_int".
/// Params/Returns: as itest_assert_lt_int.
/// Error case: none.
/// Complexity: O(1) plus one failure record.
pub fn itest_assert_le_int(h: &mut ITest, step: Int, left: Int, right: Int, message: Str) -> Bool {
  if left <= right {
    return true;
  }
  _record_failure(h, step, "le_int", int_to_string(left), int_to_string(right), message);
  return false;
}

/// Assert `left > right`. Failure kind "gt_int".
/// Params/Returns: as itest_assert_lt_int.
/// Error case: none.
/// Complexity: O(1) plus one failure record.
pub fn itest_assert_gt_int(h: &mut ITest, step: Int, left: Int, right: Int, message: Str) -> Bool {
  if left > right {
    return true;
  }
  _record_failure(h, step, "gt_int", int_to_string(left), int_to_string(right), message);
  return false;
}

/// Assert `left >= right`. Failure kind "ge_int".
/// Params/Returns: as itest_assert_lt_int.
/// Error case: none.
/// Complexity: O(1) plus one failure record.
pub fn itest_assert_ge_int(h: &mut ITest, step: Int, left: Int, right: Int, message: Str) -> Bool {
  if left >= right {
    return true;
  }
  _record_failure(h, step, "ge_int", int_to_string(left), int_to_string(right), message);
  return false;
}

/// Assert that two strings are byte-equal (str_compare == 0). Failure kind
/// "eq_str"; expected/actual are recorded verbatim.
/// Params: h - the harness; step - the owning step; expected/actual - the
/// compared strings; message - the failure text.
/// Returns: true when equal.
/// Error case: none.
/// Complexity: O(len).
pub fn itest_assert_eq_str(h: &mut ITest, step: Int, expected: Str, actual: Str, message: Str) -> Bool {
  if compare.str_compare(expected, actual) == 0 {
    return true;
  }
  _record_failure(h, step, "eq_str", expected, actual, message);
  return false;
}

/// Assert that two strings differ. Failure kind "ne_str".
/// Params/Returns: as itest_assert_eq_str; passes when the strings differ.
/// Error case: none.
/// Complexity: O(len).
pub fn itest_assert_ne_str(h: &mut ITest, step: Int, expected: Str, actual: Str, message: Str) -> Bool {
  if compare.str_compare(expected, actual) != 0 {
    return true;
  }
  _record_failure(h, step, "ne_str", expected, actual, message);
  return false;
}

/// Assert that `haystack` contains `needle` (byte search). Failure kind
/// "contains_str"; expected records the needle, actual the haystack.
/// Params: h - the harness; step - the owning step; haystack - the searched
/// string; needle - the required substring; message - the failure text.
/// Returns: true when contained.
/// Error case: none.
/// Complexity: O(len(haystack) * len(needle)).
pub fn itest_assert_contains_str(h: &mut ITest, step: Int, haystack: Str, needle: Str, message: Str) -> Bool {
  if string.str_contains(haystack, needle) {
    return true;
  }
  _record_failure(h, step, "contains_str", needle, haystack, message);
  return false;
}

// --------------------------------------------------
//  Step accessors
// --------------------------------------------------

/// Number of declared steps.
/// Params: h - the harness.
/// Returns: the step count.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_count(h: &ITest) -> Int {
  return _step_count(h);
}

/// Name of step `i`.
/// Params: h - the harness; i - the step index.
/// Returns: the name, or "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_name(h: &ITest, i: Int) -> Str {
  if i < 0 || i >= _step_count(h) {
    return "";
  }
  return h.step_names[i];
}

/// Owning suite index of step `i`.
/// Params: h - the harness; i - the step index.
/// Returns: the suite index, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_suite(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _step_count(h) {
    return -1;
  }
  let v: Int = h.step_suites[i];
  return v;
}

/// Status of step `i`: one of the ITEST_* step codes.
/// Params: h - the harness; i - the step index.
/// Returns: the status, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_status(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _step_count(h) {
    return -1;
  }
  let v: Int = h.step_status[i];
  return v;
}

/// Attempts made by step `i` so far.
/// Params: h - the harness; i - the step index.
/// Returns: the count, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_attempts(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _step_count(h) {
    return -1;
  }
  let v: Int = h.step_attempts[i];
  return v;
}

/// Total ticks consumed by step `i` across its finished/completed attempts.
/// Params: h - the harness; i - the step index.
/// Returns: the tick total, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_ticks(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _step_count(h) {
    return -1;
  }
  let v: Int = h.step_ticks[i];
  return v;
}

/// Ticks consumed by the current RUNNING attempt of step `i` (0 otherwise).
/// Params: h - the harness; i - the step index.
/// Returns: the elapsed ticks, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_elapsed(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _step_count(h) {
    return -1;
  }
  let v: Int = h.step_elapsed[i];
  return v;
}

/// Remaining retry-backoff ticks of step `i`.
/// Params: h - the harness; i - the step index.
/// Returns: the wait, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_wait(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _step_count(h) {
    return -1;
  }
  let v: Int = h.step_wait[i];
  return v;
}

/// Report message of step `i`: the skip reason or terminal failure text for
/// FAILED/SKIPPED steps, "" otherwise.
/// Params: h - the harness; i - the step index.
/// Returns: the message, or "" when there is none or `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_message(h: &ITest, i: Int) -> Str {
  if i < 0 || i >= _step_count(h) {
    return "";
  }
  return h.step_messages[i];
}

/// Configured attempt budget of step `i`.
/// Params: h - the harness; i - the step index.
/// Returns: the budget (>= 1), or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_max_attempts(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _step_count(h) {
    return -1;
  }
  let v: Int = h.step_max_attempts[i];
  return v;
}

/// Configured backoff base of step `i`, in ticks.
/// Params: h - the harness; i - the step index.
/// Returns: the base (0 = no backoff), or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_backoff_base(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _step_count(h) {
    return -1;
  }
  let v: Int = h.step_backoff_base[i];
  return v;
}

/// Configured backoff cap of step `i`, in ticks.
/// Params: h - the harness; i - the step index.
/// Returns: the cap (0 = no backoff), or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_backoff_cap(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _step_count(h) {
    return -1;
  }
  let v: Int = h.step_backoff_cap[i];
  return v;
}

/// Configured tick timeout of step `i`.
/// Params: h - the harness; i - the step index.
/// Returns: the timeout (0 = none), or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_timeout(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _step_count(h) {
    return -1;
  }
  let v: Int = h.step_timeout[i];
  return v;
}

/// Number of declared dependencies of step `i`.
/// Params: h - the harness; i - the step index.
/// Returns: the count, or 0 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_dep_count(h: &ITest, i: Int) -> Int {
  return _dep_count_at(h, i);
}

/// `k`-th declared dependency name of step `i`, in declaration order.
/// Params: h - the harness; i - the step index; k - the dependency position.
/// Returns: the name, or "" when out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_step_dep(h: &ITest, i: Int, k: Int) -> Str {
  return _dep_at(h, i, k);
}

// --------------------------------------------------
//  Suite, fixture and clock accessors
// --------------------------------------------------

/// Number of declared suites.
/// Params: h - the harness.
/// Returns: the suite count.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_suite_count(h: &ITest) -> Int {
  return _suite_count(h);
}

/// Name of suite `s`.
/// Params: h - the harness; s - the suite index.
/// Returns: the name, or "" when `s` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_suite_name(h: &ITest, s: Int) -> Str {
  if s < 0 || s >= _suite_count(h) {
    return "";
  }
  return h.suite_names[s];
}

/// Lifecycle state of suite `s`: ITEST_SUITE_NEW, ITEST_SUITE_OPEN or
/// ITEST_SUITE_CLOSED.
/// Params: h - the harness; s - the suite index.
/// Returns: the state, or -1 when `s` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_suite_state(h: &ITest, s: Int) -> Int {
  if s < 0 || s >= _suite_count(h) {
    return -1;
  }
  let v: Int = h.suite_state[s];
  return v;
}

/// Number of fixtures in the execution log.
/// Params: h - the harness.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_fixture_count(h: &ITest) -> Int {
  return _fixture_count(h);
}

/// Name of executed fixture `i`, in execution order.
/// Params: h - the harness; i - the log index.
/// Returns: the name, or "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_fixture_name(h: &ITest, i: Int) -> Str {
  if i < 0 || i >= _fixture_count(h) {
    return "";
  }
  return h.fixture_log[i];
}

/// Owning suite index of executed fixture `i`.
/// Params: h - the harness; i - the log index.
/// Returns: the suite index, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_fixture_suite(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _fixture_count(h) {
    return -1;
  }
  let v: Int = h.fixture_log_suite[i];
  return v;
}

/// Phase of executed fixture `i`: ITEST_SETUP or ITEST_TEARDOWN.
/// Params: h - the harness; i - the log index.
/// Returns: the phase, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_fixture_phase(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _fixture_count(h) {
    return -1;
  }
  let v: Int = h.fixture_log_phase[i];
  return v;
}

/// Current value of the logical clock, in ticks.
/// Params: h - the harness.
/// Returns: the tick count.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_now(h: &ITest) -> Int {
  return h.now;
}

// --------------------------------------------------
//  Aggregation
// --------------------------------------------------

/// Number of steps with status `status`.
/// Params: h - the harness; status - an ITEST_* step code.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(steps).
pub fn itest_count(h: &ITest, status: Int) -> Int {
  var c = 0;
  var i = 0;
  let n = _step_count(h);
  while i < n {
    let st: Int = h.step_status[i];
    if st == status {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Number of PASSED steps. Params: h. Returns: the count. Complexity: O(steps).
pub fn itest_passed_count(h: &ITest) -> Int {
  return itest_count(h, ITEST_PASSED);
}

/// Number of FAILED steps. Params: h. Returns: the count. Complexity: O(steps).
pub fn itest_failed_count(h: &ITest) -> Int {
  return itest_count(h, ITEST_FAILED);
}

/// Number of SKIPPED steps. Params: h. Returns: the count. Complexity: O(steps).
pub fn itest_skipped_count(h: &ITest) -> Int {
  return itest_count(h, ITEST_SKIPPED);
}

/// Number of PENDING steps. Params: h. Returns: the count. Complexity: O(steps).
pub fn itest_pending_count(h: &ITest) -> Int {
  return itest_count(h, ITEST_PENDING);
}

/// Number of RUNNING steps. Params: h. Returns: the count. Complexity: O(steps).
pub fn itest_running_count(h: &ITest) -> Int {
  return itest_count(h, ITEST_RUNNING);
}

/// True when no step is PENDING or RUNNING.
/// Params: h - the harness.
/// Returns: the flag.
/// Error case: none.
/// Complexity: O(steps).
pub fn itest_all_done(h: &ITest) -> Bool {
  var i = 0;
  let n = _step_count(h);
  while i < n {
    let st: Int = h.step_status[i];
    if st == ITEST_PENDING || st == ITEST_RUNNING {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Number of steps owned by suite `s`.
/// Params: h - the harness; s - the suite index.
/// Returns: the count (0 for an out-of-range suite).
/// Error case: none.
/// Complexity: O(steps).
pub fn itest_suite_step_count(h: &ITest, s: Int) -> Int {
  var c = 0;
  var i = 0;
  let n = _step_count(h);
  while i < n {
    let owner: Int = h.step_suites[i];
    if owner == s {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Number of steps of suite `s` with status `status`.
/// Params: h - the harness; s - the suite index; status - an ITEST_* code.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(steps).
pub fn itest_suite_count_status(h: &ITest, s: Int, status: Int) -> Int {
  var c = 0;
  var i = 0;
  let n = _step_count(h);
  while i < n {
    let owner: Int = h.step_suites[i];
    if owner == s {
      let st: Int = h.step_status[i];
      if st == status {
        c = c + 1;
      }
    }
    i = i + 1;
  }
  return c;
}

/// Number of PASSED steps of suite `s`.
/// Params: h - the harness; s - the suite index.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(steps).
pub fn itest_suite_passed(h: &ITest, s: Int) -> Int {
  return itest_suite_count_status(h, s, ITEST_PASSED);
}

/// Number of FAILED steps of suite `s`.
/// Params: h - the harness; s - the suite index.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(steps).
pub fn itest_suite_failed(h: &ITest, s: Int) -> Int {
  return itest_suite_count_status(h, s, ITEST_FAILED);
}

/// Number of SKIPPED steps of suite `s`.
/// Params: h - the harness; s - the suite index.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(steps).
pub fn itest_suite_skipped(h: &ITest, s: Int) -> Int {
  return itest_suite_count_status(h, s, ITEST_SKIPPED);
}

/// Number of PENDING steps of suite `s`.
/// Params: h - the harness; s - the suite index.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(steps).
pub fn itest_suite_pending(h: &ITest, s: Int) -> Int {
  return itest_suite_count_status(h, s, ITEST_PENDING);
}

// --------------------------------------------------
//  Failure log accessors
// --------------------------------------------------

/// Number of structured assertion failures recorded.
/// Params: h - the harness.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_failure_count(h: &ITest) -> Int {
  return _failure_count(h);
}

/// Step index recorded in failure `i`.
/// Params: h - the harness; i - the failure index.
/// Returns: the step index (possibly -1), or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_failure_step(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _failure_count(h) {
    return -1;
  }
  let v: Int = h.fail_steps[i];
  return v;
}

/// Owning suite index of failure `i`, resolved through its step.
/// Params: h - the harness; i - the failure index.
/// Returns: the suite index, or -1 when `i` or its step is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_failure_suite(h: &ITest, i: Int) -> Int {
  let s = itest_failure_step(h, i);
  if s < 0 || s >= _step_count(h) {
    return -1;
  }
  let v: Int = h.step_suites[s];
  return v;
}

/// Attempt number recorded in failure `i` (the step's attempt count when the
/// assertion ran).
/// Params: h - the harness; i - the failure index.
/// Returns: the attempt, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_failure_attempt(h: &ITest, i: Int) -> Int {
  if i < 0 || i >= _failure_count(h) {
    return -1;
  }
  let v: Int = h.fail_attempts[i];
  return v;
}

/// Assertion kind of failure `i`: "true", "false", "eq_int", "ne_int",
/// "lt_int", "le_int", "gt_int", "ge_int", "eq_str", "ne_str" or
/// "contains_str".
/// Params: h - the harness; i - the failure index.
/// Returns: the kind, or "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_failure_kind(h: &ITest, i: Int) -> Str {
  if i < 0 || i >= _failure_count(h) {
    return "";
  }
  return h.fail_kinds[i];
}

/// Expected-value text of failure `i`.
/// Params: h - the harness; i - the failure index.
/// Returns: the text, or "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_failure_expected(h: &ITest, i: Int) -> Str {
  if i < 0 || i >= _failure_count(h) {
    return "";
  }
  return h.fail_expected[i];
}

/// Actual-value text of failure `i`.
/// Params: h - the harness; i - the failure index.
/// Returns: the text, or "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_failure_actual(h: &ITest, i: Int) -> Str {
  if i < 0 || i >= _failure_count(h) {
    return "";
  }
  return h.fail_actual[i];
}

/// Caller-supplied message of failure `i`.
/// Params: h - the harness; i - the failure index.
/// Returns: the message, or "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_failure_message(h: &ITest, i: Int) -> Str {
  if i < 0 || i >= _failure_count(h) {
    return "";
  }
  return h.fail_messages[i];
}

/// Number of recorded assertion failures for `step`, across all attempts.
/// Params: h - the harness; step - the step index.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(failures).
pub fn itest_step_assert_failures(h: &ITest, step: Int) -> Int {
  var c = 0;
  var i = 0;
  let n = _failure_count(h);
  while i < n {
    let fs: Int = h.fail_steps[i];
    if fs == step {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Number of recorded assertion failures for `step` in its current attempt,
/// so a caller can finish the attempt with
/// `itest_finish_step(h, step, itest_attempt_failure_count(h, step) == 0)`.
/// Params: h - the harness; step - the step index.
/// Returns: the count (0 for an out-of-range step).
/// Error case: none.
/// Complexity: O(failures).
pub fn itest_attempt_failure_count(h: &ITest, step: Int) -> Int {
  if step < 0 || step >= _step_count(h) {
    return 0;
  }
  let want: Int = h.step_attempts[step];
  var c = 0;
  var i = 0;
  let n = _failure_count(h);
  while i < n {
    let fs: Int = h.fail_steps[i];
    if fs == step {
      let fa: Int = h.fail_attempts[i];
      if fa == want {
        c = c + 1;
      }
    }
    i = i + 1;
  }
  return c;
}

// --------------------------------------------------
//  Names for codes
// --------------------------------------------------

/// Human-readable step status name: "pending", "running", "passed",
/// "failed", "skipped"; "" for any other value.
/// Params: status - an ITEST_* step code.
/// Returns: the name.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_status_name(status: Int) -> Str {
  if status == ITEST_PENDING {
    return "pending";
  }
  if status == ITEST_RUNNING {
    return "running";
  }
  if status == ITEST_PASSED {
    return "passed";
  }
  if status == ITEST_FAILED {
    return "failed";
  }
  if status == ITEST_SKIPPED {
    return "skipped";
  }
  return "";
}

/// Human-readable suite state name: "new", "open", "closed"; "" for any
/// other value.
/// Params: state - an ITEST_SUITE_* code.
/// Returns: the name.
/// Error case: none.
/// Complexity: O(1).
pub fn itest_suite_state_name(state: Int) -> Str {
  if state == ITEST_SUITE_NEW {
    return "new";
  }
  if state == ITEST_SUITE_OPEN {
    return "open";
  }
  if state == ITEST_SUITE_CLOSED {
    return "closed";
  }
  return "";
}

// --------------------------------------------------
//  Text report
// --------------------------------------------------

// The bracketed tag of a step status in the report.
fn _status_tag(status: Int) -> Str {
  if status == ITEST_PENDING {
    return "PENDING";
  }
  if status == ITEST_RUNNING {
    return "RUNNING";
  }
  if status == ITEST_PASSED {
    return "PASS";
  }
  if status == ITEST_FAILED {
    return "FAIL";
  }
  if status == ITEST_SKIPPED {
    return "SKIP";
  }
  return "?";
}

// Append one newline.
fn _push_nl(out: &mut Vec[UInt8]) {
  out.push(10u8);
}

// Append "\n  " (newline plus the two-space step indent).
fn _push_step_indent(out: &mut Vec[UInt8]) {
  out.push(10u8);
  out.push(32u8);
  out.push(32u8);
}

// Append one report line for step `i` (leading newline and two-space indent).
fn _report_step(out: &mut Vec[UInt8], h: &ITest, i: Int) {
  let st: Int = h.step_status[i];
  let name: Str = h.step_names[i];
  _push_step_indent(out);
  builder.sb_push_str(out, "[");
  builder.sb_push_str(out, _status_tag(st));
  builder.sb_push_str(out, "] ");
  builder.sb_push_str(out, name);
  if st == ITEST_SKIPPED {
    let smsg: Str = h.step_messages[i];
    if compare.str_compare(smsg, "") != 0 {
      builder.sb_push_str(out, ": ");
      builder.sb_push_str(out, smsg);
    }
    return;
  }
  let a: Int = h.step_attempts[i];
  builder.sb_push_str(out, " attempts=");
  builder.sb_push_str(out, int_to_string(a));
  if st == ITEST_RUNNING {
    let e: Int = h.step_elapsed[i];
    builder.sb_push_str(out, " elapsed=");
    builder.sb_push_str(out, int_to_string(e));
    return;
  }
  let t: Int = h.step_ticks[i];
  builder.sb_push_str(out, " ticks=");
  builder.sb_push_str(out, int_to_string(t));
  if st == ITEST_PENDING {
    let w: Int = h.step_wait[i];
    if w > 0 {
      builder.sb_push_str(out, " wait=");
      builder.sb_push_str(out, int_to_string(w));
    }
    return;
  }
  let msg: Str = h.step_messages[i];
  if compare.str_compare(msg, "") != 0 {
    builder.sb_push_str(out, ": ");
    builder.sb_push_str(out, msg);
  }
}

// Append the fixtures section.
fn _report_fixtures(out: &mut Vec[UInt8], h: &ITest) {
  builder.sb_push_str(out, "fixtures=");
  builder.sb_push_str(out, int_to_string(_fixture_count(h)));
  var i = 0;
  let n = _fixture_count(h);
  while i < n {
    let fname: Str = h.fixture_log[i];
    let fs: Int = h.fixture_log_suite[i];
    let fp: Int = h.fixture_log_phase[i];
    _push_step_indent(out);
    if fp == ITEST_SETUP {
      builder.sb_push_str(out, "[setup] ");
    } else {
      builder.sb_push_str(out, "[teardown] ");
    }
    builder.sb_push_str(out, fname);
    builder.sb_push_str(out, " (suite '");
    let sname: Str = itest_suite_name(h, fs);
    builder.sb_push_str(out, sname);
    builder.sb_push_str(out, "')");
    i = i + 1;
  }
  _push_nl(out);
}

// Append the assertion-failure section.
fn _report_failures(out: &mut Vec[UInt8], h: &ITest) {
  builder.sb_push_str(out, "assertion-failures=");
  builder.sb_push_str(out, int_to_string(_failure_count(h)));
  var i = 0;
  let n = _failure_count(h);
  while i < n {
    let fs: Int = h.fail_steps[i];
    let attempt: Int = h.fail_attempts[i];
    let kind: Str = h.fail_kinds[i];
    let exp: Str = h.fail_expected[i];
    let act: Str = h.fail_actual[i];
    let msg: Str = h.fail_messages[i];
    _push_step_indent(out);
    builder.sb_push_str(out, "[FAIL] suite '");
    let sname: Str = itest_suite_name(h, itest_failure_suite(h, i));
    builder.sb_push_str(out, sname);
    builder.sb_push_str(out, "' step '");
    let step_name: Str = itest_step_name(h, fs);
    builder.sb_push_str(out, step_name);
    builder.sb_push_str(out, "' attempt=");
    builder.sb_push_str(out, int_to_string(attempt));
    builder.sb_push_str(out, " kind=");
    builder.sb_push_str(out, kind);
    builder.sb_push_str(out, " expected '");
    builder.sb_push_str(out, exp);
    builder.sb_push_str(out, "' actual '");
    builder.sb_push_str(out, act);
    builder.sb_push_str(out, "'");
    if compare.str_compare(msg, "") != 0 {
      builder.sb_push_str(out, ": ");
      builder.sb_push_str(out, msg);
    }
    i = i + 1;
  }
  _push_nl(out);
}

/// Render the whole harness as deterministic text.
/// Params: h - the harness.
/// Returns: a Str with, in order: a summary line
/// (`xiom.itest report: suites=S steps=N passed=P failed=F skipped=K
/// pending=Q running=R tick=T`), one block per suite (`suite '<name>':
/// passed=... failed=... skipped=... pending=...` followed by one indented
/// line per step, `[PASS|FAIL|SKIP|PENDING|RUNNING] <name> ...`), the fixture
/// log section (`fixtures=N` plus `[setup]`/`[teardown] <name> (suite
/// '<name>')` lines in execution order), and the assertion-failure section
/// (`assertion-failures=N` plus one structured-failure line per record).
/// Steps whose suite index is out of range are not listed. The output is
/// byte-stable for a given state; every line ends with "\n".
/// Error case: none.
/// Complexity: O(suites + steps + fixtures + failures).
pub fn itest_report(h: &ITest) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "xiom.itest report: suites=");
  builder.sb_push_str(&mut out, int_to_string(_suite_count(h)));
  builder.sb_push_str(&mut out, " steps=");
  builder.sb_push_str(&mut out, int_to_string(_step_count(h)));
  builder.sb_push_str(&mut out, " passed=");
  builder.sb_push_str(&mut out, int_to_string(itest_passed_count(h)));
  builder.sb_push_str(&mut out, " failed=");
  builder.sb_push_str(&mut out, int_to_string(itest_failed_count(h)));
  builder.sb_push_str(&mut out, " skipped=");
  builder.sb_push_str(&mut out, int_to_string(itest_skipped_count(h)));
  builder.sb_push_str(&mut out, " pending=");
  builder.sb_push_str(&mut out, int_to_string(itest_pending_count(h)));
  builder.sb_push_str(&mut out, " running=");
  builder.sb_push_str(&mut out, int_to_string(itest_running_count(h)));
  builder.sb_push_str(&mut out, " tick=");
  builder.sb_push_str(&mut out, int_to_string(h.now));
  var s = 0;
  let sc = _suite_count(h);
  while s < sc {
    _push_nl(&mut out);
    builder.sb_push_str(&mut out, "suite '");
    let sname: Str = h.suite_names[s];
    builder.sb_push_str(&mut out, sname);
    builder.sb_push_str(&mut out, "': passed=");
    builder.sb_push_str(&mut out, int_to_string(itest_suite_passed(h, s)));
    builder.sb_push_str(&mut out, " failed=");
    builder.sb_push_str(&mut out, int_to_string(itest_suite_failed(h, s)));
    builder.sb_push_str(&mut out, " skipped=");
    builder.sb_push_str(&mut out, int_to_string(itest_suite_skipped(h, s)));
    builder.sb_push_str(&mut out, " pending=");
    builder.sb_push_str(&mut out, int_to_string(itest_suite_pending(h, s)));
    var i = 0;
    let n = _step_count(h);
    while i < n {
      let owner: Int = h.step_suites[i];
      if owner == s {
        _report_step(&mut out, h, i);
      }
      i = i + 1;
    }
    s = s + 1;
  }
  _push_nl(&mut out);
  _report_fixtures(&mut out, h);
  _report_failures(&mut out, h);
  return builder.sb_to_str(&out);
}
