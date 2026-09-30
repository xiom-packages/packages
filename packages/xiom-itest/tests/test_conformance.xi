// XIOM -- xiom.itest conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM xiom.itest harness model against
// the documented semantics in SPEC.md.
//
// Coverage: empty state, suite/fixture declaration validation, LIFO
// teardown, suite lifecycle errors, step and dependency validation, cycle
// rejection, declaration-order scheduling, suite-open gating, skip
// propagation (direct and transitive), retry backoff growth and capping,
// attempt timeouts (terminal, retried, and partial-tick remainder),
// assertion catalog success and failure kinds, structured-failure
// accessors and bounds, per-suite and overall aggregation, teardown on
// failure, and the exact text report for both an empty and a populated
// harness. All Str comparisons go through str_compare.

module itest_tests
use xiom.io; use xiom.test; use xiom.itest;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when the result fails with exactly the message `want`.
fn err_is(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when the result succeeds with exactly `want`.
fn ok_is(r: Result[Int, Str], want: Int) -> Bool {
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

// A suite "s" with one step "job" and the given retry configuration.
fn one_job(h: &mut ITest, max_attempts: Int, base: Int, cap: Int) {
  itest_add_suite(h, "s");
  itest_add_step(h, 0, "job");
  itest_step_set_retries(h, 0, max_attempts, base, cap);
  itest_begin_suite(h, 0);
}

fn t1() -> TestResult {
  let h = itest_new();
  var ok = itest_suite_count(&h) == 0;
  if itest_step_count(&h) != 0 { ok = false; }
  if itest_fixture_count(&h) != 0 { ok = false; }
  if itest_failure_count(&h) != 0 { ok = false; }
  if itest_now(&h) != 0 { ok = false; }
  if !itest_all_done(&h) { ok = false; }
  if itest_passed_count(&h) != 0 { ok = false; }
  if itest_pending_count(&h) != 0 { ok = false; }
  return assert(ok, "a fresh harness is empty and done");
}

fn t2() -> TestResult {
  var h = itest_new();
  var ok = err_is(itest_add_suite(&mut h, ""), "itest: invalid suite name");
  if !ok_is(itest_add_suite(&mut h, "s"), 0) { ok = false; }
  if !err_is(itest_add_suite(&mut h, "s"), "itest: duplicate suite 's'") { ok = false; }
  if itest_suite_count(&h) != 1 { ok = false; }
  if !streq(itest_suite_name(&h, 0), "s") { ok = false; }
  if !streq(itest_suite_name(&h, 1), "") { ok = false; }
  return assert(ok, "suite declaration validates names and indexes");
}

fn t3() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_setup(&mut h, 0, "A");
  itest_add_setup(&mut h, 0, "B");
  itest_add_teardown(&mut h, 0, "C");
  itest_add_teardown(&mut h, 0, "D");
  var ok = itest_fixture_count(&h) == 0;
  itest_begin_suite(&mut h, 0);
  if itest_fixture_count(&h) != 2 { ok = false; }
  if !streq(itest_fixture_name(&h, 0), "A") { ok = false; }
  if !streq(itest_fixture_name(&h, 1), "B") { ok = false; }
  if itest_fixture_phase(&h, 0) != ITEST_SETUP { ok = false; }
  itest_end_suite(&mut h, 0);
  if itest_fixture_count(&h) != 4 { ok = false; }
  if !streq(itest_fixture_name(&h, 2), "D") { ok = false; }
  if !streq(itest_fixture_name(&h, 3), "C") { ok = false; }
  if itest_fixture_phase(&h, 2) != ITEST_TEARDOWN { ok = false; }
  if itest_fixture_suite(&h, 3) != 0 { ok = false; }
  if !streq(itest_fixture_name(&h, 4), "") { ok = false; }
  return assert(ok, "setup runs in order and teardown runs LIFO");
}

fn t4() -> TestResult {
  var h = itest_new();
  var ok = ok_is(itest_add_suite(&mut h, "s"), 0);
  if !err_is(itest_add_setup(&mut h, 5, "f"), "itest: suite index out of range") { ok = false; }
  if !err_is(itest_end_suite(&mut h, 0), "itest: suite is not open") { ok = false; }
  if !ok_is(itest_begin_suite(&mut h, 0), 0) { ok = false; }
  if !err_is(itest_begin_suite(&mut h, 0), "itest: suite already open") { ok = false; }
  if !ok_is(itest_end_suite(&mut h, 0), 0) { ok = false; }
  if !err_is(itest_end_suite(&mut h, 0), "itest: suite already closed") { ok = false; }
  if itest_suite_state(&h, 0) != ITEST_SUITE_CLOSED { ok = false; }
  if itest_suite_state(&h, 9) != -1 { ok = false; }
  if !streq(itest_suite_state_name(ITEST_SUITE_CLOSED), "closed") { ok = false; }
  if !streq(itest_suite_state_name(7), "") { ok = false; }
  return assert(ok, "suite lifecycle transitions are strict");
}

fn t5() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  var ok = ok_is(itest_add_step(&mut h, 0, "a"), 0);
  if !ok_is(itest_add_step(&mut h, 0, "b"), 1) { ok = false; }
  if !err_is(itest_add_step(&mut h, 0, "a"), "itest: duplicate step 'a'") { ok = false; }
  if !err_is(itest_add_step(&mut h, 5, "x"), "itest: suite index out of range") { ok = false; }
  if !err_is(itest_step_depends_on(&mut h, 0, "a"), "itest: step cannot depend on itself") { ok = false; }
  if !err_is(itest_step_depends_on(&mut h, 0, "ghost"), "itest: unknown dependency 'ghost'") { ok = false; }
  if !ok_is(itest_step_depends_on(&mut h, 0, "b"), 1) { ok = false; }
  if !err_is(itest_step_depends_on(&mut h, 0, "b"), "itest: duplicate dependency 'b'") { ok = false; }
  if itest_step_dep_count(&h, 0) != 1 { ok = false; }
  if !streq(itest_step_dep(&h, 0, 0), "b") { ok = false; }
  if !streq(itest_step_dep(&h, 0, 1), "") { ok = false; }
  if !streq(itest_step_name(&h, 1), "b") { ok = false; }
  if itest_step_suite(&h, 0) != 0 { ok = false; }
  if itest_step_status(&h, 0) != ITEST_PENDING { ok = false; }
  if itest_step_max_attempts(&h, 0) != 1 { ok = false; }
  if itest_step_timeout(&h, 0) != 0 { ok = false; }
  var h2 = itest_new();
  itest_add_suite(&mut h2, "s");
  itest_add_step(&mut h2, 0, "a");
  itest_add_step(&mut h2, 0, "b");
  itest_add_step(&mut h2, 0, "c");
  itest_add_step(&mut h2, 0, "d");
  if !ok_is(itest_step_depends_on(&mut h2, 1, "a"), 1) { ok = false; }
  if !ok_is(itest_step_depends_on(&mut h2, 2, "a"), 1) { ok = false; }
  if !ok_is(itest_step_depends_on(&mut h2, 1, "c"), 2) { ok = false; }
  if itest_step_dep_count(&h2, 1) != 2 { ok = false; }
  if !streq(itest_step_dep(&h2, 1, 0), "a") { ok = false; }
  if !streq(itest_step_dep(&h2, 1, 1), "c") { ok = false; }
  if !streq(itest_step_dep(&h2, 2, 0), "a") { ok = false; }
  if !ok_is(itest_step_depends_on(&mut h2, 3, "b"), 1) { ok = false; }
  if !streq(itest_step_dep(&h2, 3, 0), "b") { ok = false; }
  return assert(ok, "step and dependency declarations validate");
}

fn t6() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_step(&mut h, 0, "a");
  itest_add_step(&mut h, 0, "b");
  itest_add_step(&mut h, 0, "c");
  itest_step_depends_on(&mut h, 1, "a");
  itest_step_depends_on(&mut h, 2, "b");
  var ok = itest_next_step(&mut h) == -1;
  if !ok_is(itest_begin_suite(&mut h, 0), 0) { ok = false; }
  if itest_next_step(&mut h) != 0 { ok = false; }
  if itest_begin_step(&mut h, 1) != -1 { ok = false; }
  if itest_begin_step(&mut h, 0) != ITEST_RUNNING { ok = false; }
  if itest_begin_step(&mut h, 0) != -1 { ok = false; }
  if itest_next_step(&mut h) != -1 { ok = false; }
  if itest_finish_step(&mut h, 0, true) != ITEST_PASSED { ok = false; }
  if itest_next_step(&mut h) != 1 { ok = false; }
  itest_begin_step(&mut h, 1);
  itest_finish_step(&mut h, 1, true);
  if itest_next_step(&mut h) != 2 { ok = false; }
  itest_begin_step(&mut h, 2);
  itest_finish_step(&mut h, 2, true);
  if itest_next_step(&mut h) != -1 { ok = false; }
  if !itest_all_done(&h) { ok = false; }
  return assert(ok, "the scheduler gates steps on open suite, deps and single-flight");
}

fn t7() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_step(&mut h, 0, "a");
  itest_add_step(&mut h, 0, "b");
  itest_add_step(&mut h, 0, "c");
  itest_step_depends_on(&mut h, 1, "a");
  itest_step_depends_on(&mut h, 2, "b");
  itest_begin_suite(&mut h, 0);
  itest_begin_step(&mut h, 0);
  var ok = itest_finish_step(&mut h, 0, false) == ITEST_FAILED;
  if itest_next_step(&mut h) != -1 { ok = false; }
  if itest_step_status(&h, 1) != ITEST_SKIPPED { ok = false; }
  if itest_step_status(&h, 2) != ITEST_SKIPPED { ok = false; }
  if !streq(itest_step_message(&h, 0), "itest: step 'a' failed after 1 attempt") { ok = false; }
  if !streq(itest_step_message(&h, 1), "itest: skipped: dependency 'a' failed") { ok = false; }
  if !streq(itest_step_message(&h, 2), "itest: skipped: dependency 'b' skipped") { ok = false; }
  if itest_failed_count(&h) != 1 { ok = false; }
  if itest_skipped_count(&h) != 2 { ok = false; }
  if !itest_all_done(&h) { ok = false; }
  return assert(ok, "a failed step skips its dependents transitively");
}

fn t8() -> TestResult {
  var h = itest_new();
  one_job(&mut h, 3, 2, 5);
  var ok = itest_next_step(&mut h) == 0;
  if itest_begin_step(&mut h, 0) != ITEST_RUNNING { ok = false; }
  itest_tick(&mut h, 2);
  if itest_finish_step(&mut h, 0, false) != ITEST_PENDING { ok = false; }
  if itest_step_wait(&h, 0) != 2 { ok = false; }
  if itest_next_step(&mut h) != -1 { ok = false; }
  itest_tick(&mut h, 1);
  if itest_step_wait(&h, 0) != 1 { ok = false; }
  if itest_next_step(&mut h) != -1 { ok = false; }
  itest_tick(&mut h, 1);
  if itest_step_wait(&h, 0) != 0 { ok = false; }
  if itest_next_step(&mut h) != 0 { ok = false; }
  itest_begin_step(&mut h, 0);
  if itest_step_attempts(&h, 0) != 2 { ok = false; }
  itest_tick(&mut h, 3);
  if itest_finish_step(&mut h, 0, false) != ITEST_PENDING { ok = false; }
  if itest_step_wait(&h, 0) != 4 { ok = false; }
  itest_tick(&mut h, 4);
  if itest_next_step(&mut h) != 0 { ok = false; }
  itest_begin_step(&mut h, 0);
  if itest_finish_step(&mut h, 0, true) != ITEST_PASSED { ok = false; }
  if itest_step_ticks(&h, 0) != 5 { ok = false; }
  if itest_step_attempts(&h, 0) != 3 { ok = false; }
  if itest_now(&h) != 11 { ok = false; }
  if !itest_all_done(&h) { ok = false; }
  return assert(ok, "retries double the backoff and pass on the last attempt");
}

fn t9() -> TestResult {
  var h = itest_new();
  one_job(&mut h, 3, 4, 5);
  itest_begin_step(&mut h, 0);
  itest_finish_step(&mut h, 0, false);
  var ok = itest_step_wait(&h, 0) == 4;
  itest_tick(&mut h, 4);
  itest_begin_step(&mut h, 0);
  itest_finish_step(&mut h, 0, false);
  if itest_step_wait(&h, 0) != 5 { ok = false; }
  itest_tick(&mut h, 5);
  if itest_next_step(&mut h) != 0 { ok = false; }
  var h2 = itest_new();
  one_job(&mut h2, 2, 0, 0);
  itest_begin_step(&mut h2, 0);
  itest_finish_step(&mut h2, 0, false);
  if itest_step_wait(&h2, 0) != 0 { ok = false; }
  if itest_next_step(&mut h2) != 0 { ok = false; }
  return assert(ok, "backoff is capped and base 0 retries immediately");
}

fn t10() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_step(&mut h, 0, "slow");
  itest_step_set_timeout(&mut h, 0, 5);
  itest_begin_suite(&mut h, 0);
  itest_begin_step(&mut h, 0);
  itest_tick(&mut h, 4);
  var ok = itest_step_status(&h, 0) == ITEST_RUNNING;
  if itest_step_elapsed(&h, 0) != 4 { ok = false; }
  itest_tick(&mut h, 1);
  if itest_step_status(&h, 0) != ITEST_FAILED { ok = false; }
  if !streq(itest_step_message(&h, 0), "itest: step 'slow' timed out after 5 ticks (attempt 1 of 1)") { ok = false; }
  if itest_step_ticks(&h, 0) != 5 { ok = false; }
  if !itest_all_done(&h) { ok = false; }
  return assert(ok, "a running attempt times out at its tick limit");
}

fn t11() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_step(&mut h, 0, "flaky");
  itest_step_set_retries(&mut h, 0, 2, 3, 9);
  itest_step_set_timeout(&mut h, 0, 5);
  itest_begin_suite(&mut h, 0);
  itest_begin_step(&mut h, 0);
  itest_tick(&mut h, 10);
  var ok = itest_step_status(&h, 0) == ITEST_PENDING;
  if itest_step_wait(&h, 0) != 0 { ok = false; }
  if itest_step_ticks(&h, 0) != 5 { ok = false; }
  if itest_next_step(&mut h) != 0 { ok = false; }
  itest_begin_step(&mut h, 0);
  if itest_step_attempts(&h, 0) != 2 { ok = false; }
  if itest_finish_step(&mut h, 0, true) != ITEST_PASSED { ok = false; }
  if itest_step_ticks(&h, 0) != 5 { ok = false; }
  if !itest_all_done(&h) { ok = false; }
  return assert(ok, "a timed-out attempt retries and leftover ticks cancel its backoff");
}

fn t12() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_step(&mut h, 0, "checks");
  itest_begin_suite(&mut h, 0);
  itest_begin_step(&mut h, 0);
  var ok = itest_assert_true(&mut h, 0, true, "true ok");
  if !itest_assert_false(&mut h, 0, false, "false ok") { ok = false; }
  if !itest_assert_eq_int(&mut h, 0, 2, 2, "eq int ok") { ok = false; }
  if !itest_assert_ne_int(&mut h, 0, 1, 2, "ne int ok") { ok = false; }
  if !itest_assert_lt_int(&mut h, 0, 1, 2, "lt ok") { ok = false; }
  if !itest_assert_le_int(&mut h, 0, 2, 2, "le ok") { ok = false; }
  if !itest_assert_gt_int(&mut h, 0, 3, 2, "gt ok") { ok = false; }
  if !itest_assert_ge_int(&mut h, 0, 3, 3, "ge ok") { ok = false; }
  if !itest_assert_eq_str(&mut h, 0, "abc", "abc", "eq str ok") { ok = false; }
  if !itest_assert_ne_str(&mut h, 0, "abc", "abd", "ne str ok") { ok = false; }
  if !itest_assert_contains_str(&mut h, 0, "hello world", "lo wo", "contains ok") { ok = false; }
  if itest_failure_count(&h) != 0 { ok = false; }
  if itest_attempt_failure_count(&h, 0) != 0 { ok = false; }
  if itest_finish_step(&mut h, 0, true) != ITEST_PASSED { ok = false; }
  return assert(ok, "every assertion kind passes on true conditions");
}

fn t13() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_step(&mut h, 0, "cat");
  itest_begin_suite(&mut h, 0);
  itest_begin_step(&mut h, 0);
  var ok = !itest_assert_true(&mut h, 0, false, "m1");
  if itest_assert_false(&mut h, 0, true, "m2") { ok = false; }
  if itest_assert_eq_int(&mut h, 0, 7, 9, "m3") { ok = false; }
  if itest_assert_ne_int(&mut h, 0, 3, 3, "m4") { ok = false; }
  if itest_assert_lt_int(&mut h, 0, 5, 5, "m5") { ok = false; }
  if itest_assert_le_int(&mut h, 0, 6, 5, "m6") { ok = false; }
  if itest_assert_gt_int(&mut h, 0, 4, 4, "m7") { ok = false; }
  if itest_assert_ge_int(&mut h, 0, 3, 4, "m8") { ok = false; }
  if itest_assert_eq_str(&mut h, 0, "aa", "ab", "m9") { ok = false; }
  if itest_assert_ne_str(&mut h, 0, "same", "same", "m10") { ok = false; }
  if itest_assert_contains_str(&mut h, 0, "abc", "z", "m11") { ok = false; }
  if itest_failure_count(&h) != 11 { ok = false; }
  if itest_step_assert_failures(&h, 0) != 11 { ok = false; }
  if itest_attempt_failure_count(&h, 0) != 11 { ok = false; }
  if !streq(itest_failure_kind(&h, 0), "true") { ok = false; }
  if !streq(itest_failure_kind(&h, 1), "false") { ok = false; }
  if !streq(itest_failure_kind(&h, 2), "eq_int") { ok = false; }
  if !streq(itest_failure_kind(&h, 3), "ne_int") { ok = false; }
  if !streq(itest_failure_kind(&h, 4), "lt_int") { ok = false; }
  if !streq(itest_failure_kind(&h, 5), "le_int") { ok = false; }
  if !streq(itest_failure_kind(&h, 6), "gt_int") { ok = false; }
  if !streq(itest_failure_kind(&h, 7), "ge_int") { ok = false; }
  if !streq(itest_failure_kind(&h, 8), "eq_str") { ok = false; }
  if !streq(itest_failure_kind(&h, 9), "ne_str") { ok = false; }
  if !streq(itest_failure_kind(&h, 10), "contains_str") { ok = false; }
  if !streq(itest_failure_expected(&h, 1), "false") { ok = false; }
  if !streq(itest_failure_actual(&h, 1), "true") { ok = false; }
  if !streq(itest_failure_expected(&h, 2), "7") { ok = false; }
  if !streq(itest_failure_actual(&h, 2), "9") { ok = false; }
  if !streq(itest_failure_expected(&h, 10), "z") { ok = false; }
  if !streq(itest_failure_actual(&h, 10), "abc") { ok = false; }
  if !streq(itest_failure_message(&h, 2), "m3") { ok = false; }
  if itest_failure_step(&h, 2) != 0 { ok = false; }
  if itest_failure_suite(&h, 2) != 0 { ok = false; }
  if itest_failure_attempt(&h, 2) != 1 { ok = false; }
  return assert(ok, "failing assertions record all structured failure kinds");
}

fn t14() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_step(&mut h, 0, "one");
  itest_begin_suite(&mut h, 0);
  itest_begin_step(&mut h, 0);
  itest_assert_eq_int(&mut h, 0, 1, 2, "boom");
  var ok = itest_failure_count(&h) == 1;
  if itest_failure_step(&h, 1) != -1 { ok = false; }
  if !streq(itest_failure_kind(&h, -1), "") { ok = false; }
  if !streq(itest_failure_expected(&h, 5), "") { ok = false; }
  if !streq(itest_failure_actual(&h, 5), "") { ok = false; }
  if !streq(itest_failure_message(&h, -2), "") { ok = false; }
  if itest_failure_attempt(&h, 5) != -1 { ok = false; }
  if itest_failure_suite(&h, 5) != -1 { ok = false; }
  if !streq(itest_failure_message(&h, 0), "boom") { ok = false; }
  if itest_step_assert_failures(&h, 0) != 1 { ok = false; }
  if itest_step_assert_failures(&h, 9) != 0 { ok = false; }
  if itest_attempt_failure_count(&h, 9) != 0 { ok = false; }
  return assert(ok, "failure accessors are bounds-safe and complete");
}

fn t15() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s0");
  itest_add_suite(&mut h, "s1");
  itest_add_step(&mut h, 0, "a");
  itest_add_step(&mut h, 0, "b");
  itest_add_step(&mut h, 0, "c");
  itest_add_step(&mut h, 1, "d");
  itest_step_depends_on(&mut h, 2, "b");
  itest_begin_suite(&mut h, 0);
  itest_begin_step(&mut h, 0);
  itest_finish_step(&mut h, 0, true);
  itest_begin_step(&mut h, 1);
  itest_finish_step(&mut h, 1, false);
  var ok = ok_is(itest_end_suite(&mut h, 0), 0);
  itest_begin_suite(&mut h, 1);
  if itest_next_step(&mut h) != 3 { ok = false; }
  itest_begin_step(&mut h, 3);
  itest_finish_step(&mut h, 3, true);
  if itest_next_step(&mut h) != -1 { ok = false; }
  itest_end_suite(&mut h, 1);
  if itest_passed_count(&h) != 2 { ok = false; }
  if itest_failed_count(&h) != 1 { ok = false; }
  if itest_skipped_count(&h) != 1 { ok = false; }
  if itest_pending_count(&h) != 0 { ok = false; }
  if itest_running_count(&h) != 0 { ok = false; }
  if itest_count(&h, ITEST_PASSED) != 2 { ok = false; }
  if itest_suite_step_count(&h, 0) != 3 { ok = false; }
  if itest_suite_passed(&h, 0) != 1 { ok = false; }
  if itest_suite_failed(&h, 0) != 1 { ok = false; }
  if itest_suite_skipped(&h, 0) != 1 { ok = false; }
  if itest_suite_pending(&h, 0) != 0 { ok = false; }
  if itest_suite_step_count(&h, 1) != 1 { ok = false; }
  if itest_suite_passed(&h, 1) != 1 { ok = false; }
  if itest_suite_failed(&h, 1) != 0 { ok = false; }
  if !itest_all_done(&h) { ok = false; }
  if !streq(itest_status_name(ITEST_PASSED), "passed") { ok = false; }
  if !streq(itest_status_name(ITEST_SKIPPED), "skipped") { ok = false; }
  if !streq(itest_status_name(99), "") { ok = false; }
  return assert(ok, "per-suite and overall aggregation agree");
}

fn t16() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_setup(&mut h, 0, "s1");
  itest_add_setup(&mut h, 0, "s2");
  itest_add_teardown(&mut h, 0, "t1");
  itest_add_teardown(&mut h, 0, "t2");
  itest_add_step(&mut h, 0, "boom");
  itest_begin_suite(&mut h, 0);
  itest_begin_step(&mut h, 0);
  var ok = itest_finish_step(&mut h, 0, false) == ITEST_FAILED;
  if !ok_is(itest_end_suite(&mut h, 0), 0) { ok = false; }
  if itest_fixture_count(&h) != 4 { ok = false; }
  if !streq(itest_fixture_name(&h, 0), "s1") { ok = false; }
  if !streq(itest_fixture_name(&h, 1), "s2") { ok = false; }
  if !streq(itest_fixture_name(&h, 2), "t2") { ok = false; }
  if !streq(itest_fixture_name(&h, 3), "t1") { ok = false; }
  if itest_fixture_phase(&h, 2) != ITEST_TEARDOWN { ok = false; }
  if itest_suite_state(&h, 0) != ITEST_SUITE_CLOSED { ok = false; }
  return assert(ok, "teardown still runs after a step failure");
}

fn t17() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "build");
  itest_add_setup(&mut h, 0, "db");
  itest_add_setup(&mut h, 0, "cache");
  itest_add_teardown(&mut h, 0, "drop-db");
  itest_add_teardown(&mut h, 0, "stop-cache");
  itest_add_step(&mut h, 0, "compile");
  itest_add_step(&mut h, 0, "link");
  itest_add_step(&mut h, 0, "deploy");
  itest_step_depends_on(&mut h, 2, "link");
  itest_step_set_retries(&mut h, 1, 2, 0, 0);
  itest_begin_suite(&mut h, 0);
  itest_begin_step(&mut h, 0);
  itest_tick(&mut h, 3);
  itest_finish_step(&mut h, 0, true);
  itest_begin_step(&mut h, 1);
  itest_tick(&mut h, 3);
  itest_finish_step(&mut h, 1, false);
  itest_begin_step(&mut h, 1);
  itest_tick(&mut h, 4);
  itest_assert_eq_int(&mut h, 1, 0, 1, "exit code");
  itest_finish_step(&mut h, 1, false);
  itest_next_step(&mut h);
  itest_end_suite(&mut h, 0);
  let want = "xiom.itest report: suites=1 steps=3 passed=1 failed=1 skipped=1 pending=0 running=0 tick=10\n"
    + "suite 'build': passed=1 failed=1 skipped=1 pending=0\n"
    + "  [PASS] compile attempts=1 ticks=3\n"
    + "  [FAIL] link attempts=2 ticks=7: itest: step 'link' failed after 2 attempts\n"
    + "  [SKIP] deploy: itest: skipped: dependency 'link' failed\n"
    + "fixtures=4\n"
    + "  [setup] db (suite 'build')\n"
    + "  [setup] cache (suite 'build')\n"
    + "  [teardown] stop-cache (suite 'build')\n"
    + "  [teardown] drop-db (suite 'build')\n"
    + "assertion-failures=1\n"
    + "  [FAIL] suite 'build' step 'link' attempt=2 kind=eq_int expected '0' actual '1': exit code\n";
  return assert(streq(itest_report(&h), want), "the report renders the full run deterministically");
}

fn t18() -> TestResult {
  let h = itest_new();
  let want = "xiom.itest report: suites=0 steps=0 passed=0 failed=0 skipped=0 pending=0 running=0 tick=0\n"
    + "fixtures=0\n"
    + "assertion-failures=0\n";
  return assert(streq(itest_report(&h), want), "an empty harness renders a stable empty report");
}

fn t19() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_step(&mut h, 0, "job");
  var ok = err_is(itest_step_set_retries(&mut h, 0, 0, 0, 0), "itest: max attempts must be >= 1");
  if !err_is(itest_step_set_retries(&mut h, 0, 2, -1, 0), "itest: backoff base must be >= 0") { ok = false; }
  if !err_is(itest_step_set_retries(&mut h, 0, 2, 0, -1), "itest: backoff cap must be >= 0") { ok = false; }
  if !err_is(itest_step_set_timeout(&mut h, 0, -1), "itest: timeout must be >= 0") { ok = false; }
  if !err_is(itest_step_set_timeout(&mut h, 9, 1), "itest: step index out of range") { ok = false; }
  if !ok_is(itest_step_set_retries(&mut h, 0, 5, 3, 7), 0) { ok = false; }
  if itest_step_max_attempts(&h, 0) != 5 { ok = false; }
  if itest_step_backoff_base(&h, 0) != 3 { ok = false; }
  if itest_step_backoff_cap(&h, 0) != 7 { ok = false; }
  if !ok_is(itest_step_set_timeout(&mut h, 0, 9), 0) { ok = false; }
  if itest_step_timeout(&h, 0) != 9 { ok = false; }
  return assert(ok, "retry and timeout configuration validate their inputs");
}

fn t20() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_step(&mut h, 0, "a");
  itest_begin_suite(&mut h, 0);
  var ok = itest_finish_step(&mut h, 0, true) == -1;
  if itest_begin_step(&mut h, 0) != ITEST_RUNNING { ok = false; }
  if itest_finish_step(&mut h, 0, true) != ITEST_PASSED { ok = false; }
  if itest_finish_step(&mut h, 0, true) != -1 { ok = false; }
  if itest_begin_step(&mut h, 0) != -1 { ok = false; }
  if itest_begin_step(&mut h, -1) != -1 { ok = false; }
  if itest_begin_step(&mut h, 4) != -1 { ok = false; }
  if itest_step_status(&h, 4) != -1 { ok = false; }
  if itest_step_ticks(&h, 4) != -1 { ok = false; }
  return assert(ok, "driver transitions reject invalid steps and states");
}

fn t21() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_step(&mut h, 0, "a");
  itest_add_step(&mut h, 0, "b");
  var ok = ok_is(itest_step_depends_on(&mut h, 1, "a"), 1);
  if !err_is(itest_step_depends_on(&mut h, 0, "b"), "itest: dependency cycle 'b'") { ok = false; }
  if itest_step_dep_count(&h, 0) != 0 { ok = false; }
  return assert(ok, "dependency cycles are rejected at declaration");
}

fn t22() -> TestResult {
  var h = itest_new();
  one_job(&mut h, 2, 5, 5);
  itest_begin_step(&mut h, 0);
  itest_finish_step(&mut h, 0, false);
  var ok = itest_step_wait(&h, 0) == 5;
  itest_tick(&mut h, 0);
  if itest_step_wait(&h, 0) != 5 { ok = false; }
  itest_tick(&mut h, -3);
  if itest_step_wait(&h, 0) != 5 { ok = false; }
  if itest_now(&h) != 0 { ok = false; }
  itest_tick(&mut h, 9);
  if itest_step_wait(&h, 0) != 0 { ok = false; }
  if itest_now(&h) != 9 { ok = false; }
  if itest_next_step(&mut h) != 0 { ok = false; }
  return assert(ok, "tick clamps backoff at zero and ignores non-positive ticks");
}

fn t23() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "s");
  itest_add_step(&mut h, 0, "x");
  itest_add_step(&mut h, 0, "y");
  itest_step_set_retries(&mut h, 1, 2, 0, 0);
  itest_begin_suite(&mut h, 0);
  itest_begin_step(&mut h, 0);
  itest_finish_step(&mut h, 0, false);
  var ok = streq(itest_step_message(&h, 0), "itest: step 'x' failed after 1 attempt");
  itest_begin_step(&mut h, 1);
  itest_finish_step(&mut h, 1, false);
  if itest_step_status(&h, 1) != ITEST_PENDING { ok = false; }
  itest_begin_step(&mut h, 1);
  itest_finish_step(&mut h, 1, true);
  if itest_step_status(&h, 1) != ITEST_PASSED { ok = false; }
  if !streq(itest_step_message(&h, 1), "") { ok = false; }
  if itest_step_attempts(&h, 1) != 2 { ok = false; }
  return assert(ok, "terminal and retry-success messages are exact");
}

fn t24() -> TestResult {
  var h = itest_new();
  itest_add_suite(&mut h, "a");
  itest_add_suite(&mut h, "b");
  itest_add_step(&mut h, 0, "build");
  itest_add_step(&mut h, 1, "deploy");
  itest_step_depends_on(&mut h, 1, "build");
  itest_begin_suite(&mut h, 1);
  var ok = itest_next_step(&mut h) == -1;
  itest_begin_suite(&mut h, 0);
  if itest_next_step(&mut h) != 0 { ok = false; }
  itest_begin_step(&mut h, 0);
  itest_finish_step(&mut h, 0, true);
  if itest_next_step(&mut h) != 1 { ok = false; }
  itest_begin_step(&mut h, 1);
  itest_finish_step(&mut h, 1, true);
  if itest_next_step(&mut h) != -1 { ok = false; }
  if !itest_all_done(&h) { ok = false; }
  if itest_passed_count(&h) != 2 { ok = false; }
  return assert(ok, "dependencies work across suites once both are open");
}

fn main() -> Int {
  io.println("=== xiom.itest conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.itest: all tests passed");
  } else {
    io.println("xiom.itest: tests failed");
  }
  return failed;
}
