// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.countdown conformance tests (22 checks)
//
// Covers: creation defaults and bounds; one-shot exact expiry, overshoot and
// disarm; restart/re-arm; repeating period boundaries including large and
// exactly-aligned advances; elapsed/remaining/next-expiry queries; the
// overflow guard at the 2^62-1 boundary; handle validity, destruction,
// slot reuse and the 256-handle cap; fan-out waiters (release, ack,
// unwatch, late registration, per-handle ids, enumeration and the
// 512-waiter cap); the reset rules that preserve generation and waiters;
// and the pinned error catalog. One fixture is replayed twice to pin
// determinism.
//
// All state is built in-test: every test starts with countdown_clear(), the
// full registry reset. Str equality goes through str_compare (BUG 17
// discipline) and every Result is inspected through the typed helpers
// below.

module countdown_tests
use xiom.io; use xiom.test; use xiom.countdown;
use xiom.string.compare;

// --------------------------------------------------
//  Result helpers (one typed inspection per Result value)
// --------------------------------------------------

// True when the Result is Err with exactly the (code, handle, value) triple.
fn err_is(r: Result[Int, CountdownError], code: Int, handle: Int, value: Int) -> Bool {
  if r.is_ok { return false; }
  let e: CountdownError = r.error;
  if e.code != code { return false; }
  if e.handle != handle { return false; }
  return e.value == value;
}

// True when the Result is Ok with the given value.
fn ok_is(r: Result[Int, CountdownError], want: Int) -> Bool {
  if !r.is_ok { return false; }
  let v: Int = r.value;
  return v == want;
}

// True when the Bool Result is Ok with the given value.
fn bool_is(r: Result[Bool, CountdownError], want: Bool) -> Bool {
  if !r.is_ok { return false; }
  let v: Bool = r.value;
  return v == want;
}

// True when the Bool Result is Err with exactly the (code, handle, value)
// triple.
fn bool_err_is(r: Result[Bool, CountdownError], code: Int, handle: Int, value: Int) -> Bool {
  if r.is_ok { return false; }
  let e: CountdownError = r.error;
  if e.code != code { return false; }
  if e.handle != handle { return false; }
  return e.value == value;
}

// True when countdown_error_message(code) equals `want` byte-wise.
fn msg_is(code: Int, want: Str) -> Bool {
  let m: Str = countdown_error_message(code);
  return compare.str_compare(m, want) == 0;
}

// Append the Ok value of an Int Result to `out`, or `marker` on Err.
fn append_int(out: &mut Vec[Int], r: Result[Int, CountdownError], marker: Int) {
  if r.is_ok {
    let v: Int = r.value;
    out.push(v);
  } else {
    out.push(marker);
  }
}

// Append 1/0 for an Ok Bool Result to `out`, or `marker` on Err.
fn append_bool(out: &mut Vec[Int], r: Result[Bool, CountdownError], marker: Int) {
  if r.is_ok {
    let v: Bool = r.value;
    if v {
      out.push(1);
    } else {
      out.push(0);
    }
  } else {
    out.push(marker);
  }
}

// --------------------------------------------------
//  Determinism fixture
// --------------------------------------------------

// One fixed create/advance/watch sequence; returns the observed value of
// every step in call order (a failing step appends its negative marker in
// place of the value, so t21's pinned list catches it).
fn scenario_run() -> Vec[Int] {
  var out = Vec[Int].new();
  countdown_clear();
  append_int(&mut out, countdown_create(10), -1);
  append_int(&mut out, countdown_create_repeating(3), -2);
  append_int(&mut out, countdown_watch(0, 7), -3);
  append_int(&mut out, countdown_watch(1, 7), -4);
  append_int(&mut out, countdown_advance(0, 4), -5);
  append_int(&mut out, countdown_remaining(0), -6);
  append_int(&mut out, countdown_elapsed(0), -7);
  append_int(&mut out, countdown_advance(0, 6), -8);
  append_int(&mut out, countdown_remaining(0), -9);
  append_bool(&mut out, countdown_is_armed(0), -10);
  append_int(&mut out, countdown_advance(1, 1), -11);
  append_int(&mut out, countdown_remaining(1), -12);
  append_int(&mut out, countdown_advance(1, 2), -13);
  append_int(&mut out, countdown_fire_count(1), -14);
  append_int(&mut out, countdown_advance(1, 7), -15);
  append_int(&mut out, countdown_remaining(1), -16);
  append_int(&mut out, countdown_fire_count(1), -17);
  append_bool(&mut out, countdown_wait_released(0, 7), -18);
  append_bool(&mut out, countdown_wait_released(1, 7), -19);
  append_bool(&mut out, countdown_wait_ack(1, 7), -20);
  append_bool(&mut out, countdown_wait_released(1, 7), -21);
  append_int(&mut out, countdown_waiter_count(0), -22);
  append_int(&mut out, countdown_waiter_count(1), -23);
  append_int(&mut out, countdown_destroy(0), -24);
  let total: Int = countdown_waiter_total();
  out.push(total);
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create(10), 0);
  if countdown_count() != 1 { ok = false; }
  if countdown_capacity() != 256 { ok = false; }
  if !countdown_is_valid(0) { ok = false; }
  if countdown_is_valid(1) { ok = false; }
  if !ok_is(countdown_initial(0), 10) { ok = false; }
  if !ok_is(countdown_remaining(0), 10) { ok = false; }
  if !ok_is(countdown_elapsed(0), 0) { ok = false; }
  if !ok_is(countdown_period(0), 0) { ok = false; }
  if !ok_is(countdown_fire_count(0), 0) { ok = false; }
  if !ok_is(countdown_next_expiry(0), 10) { ok = false; }
  if !bool_is(countdown_is_armed(0), true) { ok = false; }
  if !bool_is(countdown_is_expired(0), false) { ok = false; }
  if !ok_is(countdown_watch(0, 1), 0) { ok = false; }
  if !ok_is(countdown_create(5), 1) { ok = false; }
  if countdown_count() != 2 { ok = false; }
  if !ok_is(countdown_initial(1), 5) { ok = false; }
  countdown_clear();
  if countdown_count() != 0 { ok = false; }
  if countdown_waiter_total() != 0 { ok = false; }
  if countdown_is_valid(0) { ok = false; }
  return assert(ok, "create defaults: handle 0, full duration armed, counters zero");
}

fn t2() -> TestResult {
  countdown_clear();
  var ok = err_is(countdown_create(0), 1, -1, 0);
  if !err_is(countdown_create(-3), 1, -1, -3) { ok = false; }
  if !err_is(countdown_create(4611686018427387904), 2, -1, 4611686018427387904) { ok = false; }
  if !ok_is(countdown_create(4611686018427387903), 0) { ok = false; }
  if !err_is(countdown_create_repeating(0), 1, -1, 0) { ok = false; }
  if !err_is(countdown_create_repeating(4611686018427387904), 2, -1, 4611686018427387904) { ok = false; }
  if countdown_count() != 1 { ok = false; }
  return assert(ok, "create validates duration bounds; the 2^62-1 boundary is accepted");
}

fn t3() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create(10), 0);
  if !ok_is(countdown_advance(0, 4), 0) { ok = false; }
  if !ok_is(countdown_remaining(0), 6) { ok = false; }
  if !ok_is(countdown_elapsed(0), 4) { ok = false; }
  if !ok_is(countdown_next_expiry(0), 10) { ok = false; }
  if !bool_is(countdown_is_armed(0), true) { ok = false; }
  if !bool_is(countdown_is_expired(0), false) { ok = false; }
  if !ok_is(countdown_advance(0, 6), 1) { ok = false; }
  if !ok_is(countdown_remaining(0), 0) { ok = false; }
  if !ok_is(countdown_elapsed(0), 10) { ok = false; }
  if !ok_is(countdown_fire_count(0), 1) { ok = false; }
  if !bool_is(countdown_is_armed(0), false) { ok = false; }
  if !bool_is(countdown_is_expired(0), true) { ok = false; }
  if !err_is(countdown_advance(0, 1), 6, 0, 1) { ok = false; }
  if !ok_is(countdown_remaining(0), 0) { ok = false; }
  if !ok_is(countdown_elapsed(0), 10) { ok = false; }
  if !ok_is(countdown_rearm(0), 10) { ok = false; }
  if !ok_is(countdown_remaining(0), 10) { ok = false; }
  if !ok_is(countdown_elapsed(0), 0) { ok = false; }
  if !bool_is(countdown_is_armed(0), true) { ok = false; }
  if !ok_is(countdown_fire_count(0), 1) { ok = false; }
  return assert(ok, "one-shot fires exactly at its deadline, disarms, then re-arms");
}

fn t4() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create(5), 0);
  if !ok_is(countdown_advance(0, 9), 1) { ok = false; }
  if !ok_is(countdown_remaining(0), 0) { ok = false; }
  if !ok_is(countdown_elapsed(0), 9) { ok = false; }
  if !ok_is(countdown_fire_count(0), 1) { ok = false; }
  if !ok_is(countdown_reset(0, 3), 3) { ok = false; }
  if !ok_is(countdown_initial(0), 3) { ok = false; }
  if !ok_is(countdown_remaining(0), 3) { ok = false; }
  if !ok_is(countdown_elapsed(0), 0) { ok = false; }
  if !bool_is(countdown_is_armed(0), true) { ok = false; }
  if !ok_is(countdown_advance(0, 1), 0) { ok = false; }
  if !ok_is(countdown_remaining(0), 2) { ok = false; }
  if !ok_is(countdown_fire_count(0), 1) { ok = false; }
  if !err_is(countdown_reset(0, 0), 1, 0, 0) { ok = false; }
  if !err_is(countdown_reset(0, -1), 1, 0, -1) { ok = false; }
  if !err_is(countdown_reset(99, 5), 5, 99, 5) { ok = false; }
  return assert(ok, "one-shot overshoot is absorbed; reset re-arms with a new duration");
}

fn t5() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create(5), 0);
  if !ok_is(countdown_advance(0, 0), 0) { ok = false; }
  if !ok_is(countdown_remaining(0), 5) { ok = false; }
  if !ok_is(countdown_elapsed(0), 0) { ok = false; }
  if !ok_is(countdown_advance(0, 5), 1) { ok = false; }
  if !ok_is(countdown_advance(0, 0), 0) { ok = false; }
  if !ok_is(countdown_elapsed(0), 5) { ok = false; }
  if !ok_is(countdown_fire_count(0), 1) { ok = false; }
  return assert(ok, "zero ticks is always a state no-op, even when disarmed");
}

fn t6() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create(5), 0);
  if !err_is(countdown_advance(0, -1), 3, 0, -1) { ok = false; }
  if !err_is(countdown_advance(0, -100), 3, 0, -100) { ok = false; }
  if !ok_is(countdown_remaining(0), 5) { ok = false; }
  if !ok_is(countdown_elapsed(0), 0) { ok = false; }
  if !err_is(countdown_advance(77, -1), 5, 77, -1) { ok = false; }
  return assert(ok, "negative advances are rejected untouched; handle errors win");
}

fn t7() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create_repeating(4), 0);
  if !ok_is(countdown_period(0), 4) { ok = false; }
  if !ok_is(countdown_initial(0), 4) { ok = false; }
  if !ok_is(countdown_remaining(0), 4) { ok = false; }
  if !bool_is(countdown_is_armed(0), true) { ok = false; }
  if !ok_is(countdown_advance(0, 3), 0) { ok = false; }
  if !ok_is(countdown_remaining(0), 1) { ok = false; }
  if !ok_is(countdown_advance(0, 1), 1) { ok = false; }
  if !ok_is(countdown_remaining(0), 4) { ok = false; }
  if !ok_is(countdown_fire_count(0), 1) { ok = false; }
  if !bool_is(countdown_is_armed(0), true) { ok = false; }
  if !ok_is(countdown_advance(0, 4), 1) { ok = false; }
  if !ok_is(countdown_fire_count(0), 2) { ok = false; }
  if !ok_is(countdown_advance(0, 2), 0) { ok = false; }
  if !ok_is(countdown_remaining(0), 2) { ok = false; }
  if !ok_is(countdown_elapsed(0), 10) { ok = false; }
  if !ok_is(countdown_next_expiry(0), 12) { ok = false; }
  return assert(ok, "repeating countdown fires on every boundary and re-arms");
}

fn t8() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create_repeating(3), 0);
  if !ok_is(countdown_advance(0, 1000000), 333333) { ok = false; }
  if !ok_is(countdown_remaining(0), 2) { ok = false; }
  if !ok_is(countdown_fire_count(0), 333333) { ok = false; }
  if !ok_is(countdown_elapsed(0), 1000000) { ok = false; }
  if !ok_is(countdown_next_expiry(0), 1000002) { ok = false; }
  return assert(ok, "one large advance records every crossed period boundary");
}

fn t9() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create_repeating(5), 0);
  if !ok_is(countdown_advance(0, 5), 1) { ok = false; }
  if !ok_is(countdown_remaining(0), 5) { ok = false; }
  if !ok_is(countdown_advance(0, 15), 3) { ok = false; }
  if !ok_is(countdown_remaining(0), 5) { ok = false; }
  if !ok_is(countdown_fire_count(0), 4) { ok = false; }
  if !ok_is(countdown_elapsed(0), 20) { ok = false; }
  if !ok_is(countdown_advance(0, 4), 0) { ok = false; }
  if !ok_is(countdown_remaining(0), 1) { ok = false; }
  if !ok_is(countdown_advance(0, 1), 1) { ok = false; }
  if !ok_is(countdown_fire_count(0), 5) { ok = false; }
  return assert(ok, "advances landing exactly on a boundary record that boundary");
}

fn t10() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create_repeating(10), 0);
  if !ok_is(countdown_advance(0, 4), 0) { ok = false; }
  if !ok_is(countdown_reset(0, 3), 3) { ok = false; }
  if !ok_is(countdown_period(0), 3) { ok = false; }
  if !ok_is(countdown_remaining(0), 3) { ok = false; }
  if !ok_is(countdown_elapsed(0), 0) { ok = false; }
  if !ok_is(countdown_fire_count(0), 0) { ok = false; }
  if !ok_is(countdown_advance(0, 7), 2) { ok = false; }
  if !ok_is(countdown_remaining(0), 2) { ok = false; }
  if !ok_is(countdown_fire_count(0), 2) { ok = false; }
  if !ok_is(countdown_rearm(0), 3) { ok = false; }
  if !ok_is(countdown_remaining(0), 3) { ok = false; }
  if !ok_is(countdown_elapsed(0), 0) { ok = false; }
  if !ok_is(countdown_fire_count(0), 2) { ok = false; }
  if !ok_is(countdown_advance(0, 3), 1) { ok = false; }
  return assert(ok, "reset replaces the repeating period; rearm reuses the stored period");
}

fn t11() -> TestResult {
  countdown_clear();
  let m: Int = 4611686018427387903;
  var ok = ok_is(countdown_create_repeating(m), 0);
  if !ok_is(countdown_advance(0, m), 1) { ok = false; }
  if !ok_is(countdown_elapsed(0), m) { ok = false; }
  if !ok_is(countdown_remaining(0), m) { ok = false; }
  if !ok_is(countdown_fire_count(0), 1) { ok = false; }
  if !err_is(countdown_advance(0, 1), 4, 0, 1) { ok = false; }
  if !ok_is(countdown_elapsed(0), m) { ok = false; }
  if !ok_is(countdown_fire_count(0), 1) { ok = false; }
  if !ok_is(countdown_advance(0, 0), 0) { ok = false; }
  if !ok_is(countdown_create(m), 1) { ok = false; }
  if !ok_is(countdown_advance(1, m), 1) { ok = false; }
  if !err_is(countdown_advance(1, 1), 6, 1, 1) { ok = false; }
  return assert(ok, "elapsed is capped at 2^62-1; an overflowing advance is rejected whole");
}

fn t12() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create(4), 0);
  if !ok_is(countdown_create(6), 1) { ok = false; }
  if countdown_count() != 2 { ok = false; }
  if !ok_is(countdown_advance(1, 2), 0) { ok = false; }
  if !ok_is(countdown_destroy(0), 0) { ok = false; }
  if countdown_count() != 1 { ok = false; }
  if countdown_is_valid(0) { ok = false; }
  if !err_is(countdown_destroy(0), 5, 0, -1) { ok = false; }
  if !err_is(countdown_advance(0, 1), 5, 0, 1) { ok = false; }
  if !err_is(countdown_remaining(0), 5, 0, -1) { ok = false; }
  if !bool_err_is(countdown_is_armed(0), 5, 0, -1) { ok = false; }
  if !ok_is(countdown_create(2), 0) { ok = false; }
  if countdown_count() != 2 { ok = false; }
  return assert(ok, "destroyed handles are invalid and their slots are recycled");
}

fn t13() -> TestResult {
  countdown_clear();
  var ok = true;
  var failures = 0;
  var i = 0;
  while i < 256 {
    if !ok_is(countdown_create(i + 1), i) { failures = failures + 1; }
    i = i + 1;
  }
  if failures != 0 { ok = false; }
  if countdown_count() != 256 { ok = false; }
  if !err_is(countdown_create(1), 7, -1, -1) { ok = false; }
  if !ok_is(countdown_destroy(100), 0) { ok = false; }
  if countdown_count() != 255 { ok = false; }
  if !ok_is(countdown_create(9), 100) { ok = false; }
  if countdown_count() != 256 { ok = false; }
  if !ok_is(countdown_remaining(100), 9) { ok = false; }
  return assert(ok, "the 256-handle pool is capped and released slots are reused");
}

fn t14() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create(10), 0);
  if !ok_is(countdown_watch(0, 11), 0) { ok = false; }
  if !ok_is(countdown_watch(0, 12), 0) { ok = false; }
  if !ok_is(countdown_watch(0, 13), 0) { ok = false; }
  if countdown_waiter_total() != 3 { ok = false; }
  if !ok_is(countdown_waiter_count(0), 3) { ok = false; }
  if !ok_is(countdown_destroy(0), 3) { ok = false; }
  if countdown_waiter_total() != 0 { ok = false; }
  if countdown_is_valid(0) { ok = false; }
  return assert(ok, "destroy unregisters the waiters it owned");
}

fn t15() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create(10), 0);
  if !err_is(countdown_watch(9, 1), 5, 9, 1) { ok = false; }
  if !ok_is(countdown_watch(0, 5), 0) { ok = false; }
  if !err_is(countdown_watch(0, 5), 9, 0, 5) { ok = false; }
  var failures = 0;
  var i = 0;
  while i < 511 {
    if !ok_is(countdown_watch(0, i + 100), 0) { failures = failures + 1; }
    i = i + 1;
  }
  if failures != 0 { ok = false; }
  if countdown_waiter_total() != 512 { ok = false; }
  if countdown_waiter_capacity() != 512 { ok = false; }
  if !err_is(countdown_watch(0, 9999), 10, 0, 9999) { ok = false; }
  if !err_is(countdown_watch(0, 5), 9, 0, 5) { ok = false; }
  if !ok_is(countdown_destroy(0), 512) { ok = false; }
  if countdown_waiter_total() != 0 { ok = false; }
  return assert(ok, "watch rejects unknown handles, duplicates and a full waiter pool");
}

fn t16() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create(10), 0);
  if !ok_is(countdown_watch(0, 7), 0) { ok = false; }
  if !ok_is(countdown_watch(0, 8), 0) { ok = false; }
  if !ok_is(countdown_watch(0, 9), 0) { ok = false; }
  if !bool_is(countdown_wait_released(0, 7), false) { ok = false; }
  if !bool_is(countdown_wait_released(0, 8), false) { ok = false; }
  if !bool_is(countdown_wait_released(0, 9), false) { ok = false; }
  if !ok_is(countdown_released_waiter_count(0), 0) { ok = false; }
  if !ok_is(countdown_advance(0, 10), 1) { ok = false; }
  if !bool_is(countdown_wait_released(0, 7), true) { ok = false; }
  if !bool_is(countdown_wait_released(0, 8), true) { ok = false; }
  if !bool_is(countdown_wait_released(0, 9), true) { ok = false; }
  if !ok_is(countdown_released_waiter_count(0), 3) { ok = false; }
  if !bool_is(countdown_wait_ack(0, 8), true) { ok = false; }
  if !bool_is(countdown_wait_released(0, 8), false) { ok = false; }
  if !bool_is(countdown_wait_released(0, 7), true) { ok = false; }
  if !ok_is(countdown_released_waiter_count(0), 2) { ok = false; }
  if !ok_is(countdown_unwatch(0, 7), 2) { ok = false; }
  if !ok_is(countdown_waiter_count(0), 2) { ok = false; }
  if !err_is(countdown_unwatch(0, 7), 8, 0, 7) { ok = false; }
  if !bool_err_is(countdown_wait_released(0, 7), 8, 0, 7) { ok = false; }
  return assert(ok, "one expiry releases every pending waiter; ack re-arms exactly one");
}

fn t17() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create(5), 0);
  if !ok_is(countdown_watch(0, 1), 0) { ok = false; }
  if !ok_is(countdown_advance(0, 5), 1) { ok = false; }
  if !ok_is(countdown_watch(0, 2), 1) { ok = false; }
  if !bool_is(countdown_wait_released(0, 1), true) { ok = false; }
  if !bool_is(countdown_wait_released(0, 2), false) { ok = false; }
  if !ok_is(countdown_rearm(0), 5) { ok = false; }
  if !ok_is(countdown_advance(0, 5), 1) { ok = false; }
  if !ok_is(countdown_fire_count(0), 2) { ok = false; }
  if !bool_is(countdown_wait_released(0, 1), true) { ok = false; }
  if !bool_is(countdown_wait_released(0, 2), true) { ok = false; }
  if !bool_is(countdown_is_expired(0), true) { ok = false; }
  return assert(ok, "late waiters start at the current generation; rearm keeps them");
}

fn t18() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create(10), 0);
  if !ok_is(countdown_create(10), 1) { ok = false; }
  if !ok_is(countdown_watch(0, 5), 0) { ok = false; }
  if !ok_is(countdown_watch(0, 6), 0) { ok = false; }
  if !ok_is(countdown_watch(0, 7), 0) { ok = false; }
  if !ok_is(countdown_watch(1, 5), 0) { ok = false; }
  if !ok_is(countdown_waiter_count(0), 3) { ok = false; }
  if !ok_is(countdown_waiter_count(1), 1) { ok = false; }
  if !ok_is(countdown_waiter_at(0, 0), 5) { ok = false; }
  if !ok_is(countdown_waiter_at(0, 1), 6) { ok = false; }
  if !ok_is(countdown_waiter_at(0, 2), 7) { ok = false; }
  if !err_is(countdown_waiter_at(0, 3), 11, 0, 3) { ok = false; }
  if !err_is(countdown_waiter_at(0, -1), 11, 0, -1) { ok = false; }
  if !err_is(countdown_waiter_at(9, 0), 5, 9, 0) { ok = false; }
  return assert(ok, "waiter ids are per countdown; waiter_at enumerates in slot order");
}

fn t19() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create(4), 0);
  if !ok_is(countdown_watch(0, 0), 0) { ok = false; }
  if !ok_is(countdown_watch(0, -7), 0) { ok = false; }
  if !bool_is(countdown_wait_ack(0, 0), false) { ok = false; }
  if !bool_is(countdown_wait_released(0, -7), false) { ok = false; }
  if !ok_is(countdown_advance(0, 4), 1) { ok = false; }
  if !bool_is(countdown_wait_released(0, 0), true) { ok = false; }
  if !bool_is(countdown_wait_released(0, -7), true) { ok = false; }
  if !bool_is(countdown_wait_ack(0, -7), true) { ok = false; }
  if !bool_is(countdown_wait_ack(0, -7), false) { ok = false; }
  if !ok_is(countdown_waiter_count(0), 2) { ok = false; }
  return assert(ok, "zero and negative waiter ids are legal; ack consumes one release");
}

fn t20() -> TestResult {
  var ok = msg_is(1, "countdown: ticks must be positive");
  if !msg_is(2, "countdown: ticks exceed maximum") { ok = false; }
  if !msg_is(3, "countdown: negative advance") { ok = false; }
  if !msg_is(4, "countdown: elapsed ticks would overflow") { ok = false; }
  if !msg_is(5, "countdown: unknown handle") { ok = false; }
  if !msg_is(6, "countdown: countdown is disarmed") { ok = false; }
  if !msg_is(7, "countdown: countdown capacity is full") { ok = false; }
  if !msg_is(8, "countdown: unknown waiter") { ok = false; }
  if !msg_is(9, "countdown: duplicate waiter") { ok = false; }
  if !msg_is(10, "countdown: waiter capacity is full") { ok = false; }
  if !msg_is(11, "countdown: waiter index out of range") { ok = false; }
  if !msg_is(99, "countdown: unknown error") { ok = false; }
  return assert(ok, "error catalog messages are pinned");
}

fn t21() -> TestResult {
  let a = scenario_run();
  let b = scenario_run();
  var want = Vec[Int].new();
  want.push(0);
  want.push(1);
  want.push(0);
  want.push(0);
  want.push(0);
  want.push(6);
  want.push(4);
  want.push(1);
  want.push(0);
  want.push(0);
  want.push(0);
  want.push(2);
  want.push(1);
  want.push(1);
  want.push(2);
  want.push(2);
  want.push(3);
  want.push(1);
  want.push(1);
  want.push(1);
  want.push(0);
  want.push(1);
  want.push(1);
  want.push(1);
  want.push(1);
  var ok = a.len() == want.len();
  if b.len() != want.len() { ok = false; }
  if ok {
    var i = 0;
    while i < a.len() {
      let x: Int = a[i];
      let y: Int = b[i];
      let z: Int = want[i];
      if x != y { ok = false; }
      if x != z { ok = false; }
      i = i + 1;
    }
  }
  return assert(ok, "replaying one fixture yields identical observable output");
}

fn t22() -> TestResult {
  countdown_clear();
  var ok = ok_is(countdown_create_repeating(7), 0);
  var expiries = 0;
  var i = 0;
  while i < 50 {
    let r = countdown_advance(0, 1);
    if r.is_ok {
      let v: Int = r.value;
      expiries = expiries + v;
    } else {
      expiries = expiries - 1000;
    }
    i = i + 1;
  }
  if expiries != 7 { ok = false; }
  if !ok_is(countdown_fire_count(0), 7) { ok = false; }
  if !ok_is(countdown_elapsed(0), 50) { ok = false; }
  if !ok_is(countdown_remaining(0), 6) { ok = false; }
  if !ok_is(countdown_next_expiry(0), 56) { ok = false; }
  if !ok_is(countdown_create_repeating(7), 1) { ok = false; }
  if !ok_is(countdown_advance(1, 50), 7) { ok = false; }
  if !ok_is(countdown_remaining(1), 6) { ok = false; }
  if !ok_is(countdown_elapsed(1), 50) { ok = false; }
  return assert(ok, "fifty single-tick advances equal one 50-tick advance");
}

fn main() -> Int {
  io.println("=== xiom.countdown conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.countdown: all tests passed");
  } else {
    io.println("xiom.countdown: tests failed");
  }
  return failed;
}
