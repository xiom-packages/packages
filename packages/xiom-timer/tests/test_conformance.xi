// XIOM -- xiom.timer conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers: default 4x64 geometry, granularities and caps; every geometry
// validation code; the delay-to-level and delay-to-slot breakdown helpers
// (including deadlines that are not aligned to a slot boundary); the
// insert/advance/cancel matrix with pending/scheduled accessors; duplicate
// and unknown-id errors; exact tick firing; same-deadline FIFO within a
// bucket (both back-to-back and across insert times); cancel-before-fire;
// one-level and multi-level cascades with pinned cascade counts; a small
// 2x4 wheel wrap boundary including a direct cascade fire; long idle
// advances; the max-delay boundary and max+1 rejection; replay determinism;
// zero/negative advance; pool capacity plus released-slot reuse; the
// cross-bucket ordering of one tick (cascade fires before level 0); and the
// pinned error-message catalog.
//
// All state is built in-test: every test starts with timer_configure, which
// is a full reset (entries, clock, counters). Str equality goes through
// str_compare (BUG 17 discipline) and every timer Result is consumed exactly
// once, through the typed helpers below.

module timer_tests
use xiom.io; use xiom.test; use xiom.timer;
use xiom.string.compare;

// --------------------------------------------------
//  Result helpers (one consumption per Result value)
// --------------------------------------------------

// True when the Result is Err with exactly the (code, id, delay) triple.
fn err_is(r: Result[Int, TimerError], code: Int, id: Int, delay: Int) -> Bool {
  if r.is_ok { return false; }
  let e: TimerError = r.error;
  if e.code != code { return false; }
  if e.id != id { return false; }
  return e.delay == delay;
}

// True when the Result is Ok with the given value.
fn ok_is(r: Result[Int, TimerError], want: Int) -> Bool {
  if !r.is_ok { return false; }
  let v: Int = r.value;
  return v == want;
}

// Ok value of a Result[Int, Str], or -999999 when Err (keeps a broken
// expectation failing loudly in the comparisons that follow).
fn fired_at(i: Int) -> Int {
  let r = timer_fired_id(i);
  if !r.is_ok { return -999999; }
  let v: Int = r.value;
  return v;
}

// True when timer_error_message(code) equals `want` byte-wise.
fn msg_is(code: Int, want: Str) -> Bool {
  let m: Str = timer_error_message(code);
  return compare.str_compare(m, want) == 0;
}

// Append every id of the most recent advance to `out` (an Err accessor
// yields -1000 so a broken run is visible instead of silently short).
fn append_fired(out: &mut Vec[Int]) {
  var i = 0;
  let n = timer_fired_count();
  while i < n {
    let r = timer_fired_id(i);
    if r.is_ok {
      let v: Int = r.value;
      out.push(v);
    } else {
      out.push(-1000);
    }
    i = i + 1;
  }
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if timer_levels() != 4 { ok = false; }
  if timer_slots() != 64 { ok = false; }
  if timer_max_delay() != 16777215 { ok = false; }
  if timer_capacity() != 1024 { ok = false; }
  if timer_now() != 0 { ok = false; }
  if timer_pending_count() != 0 { ok = false; }
  if timer_cascade_count() != 0 { ok = false; }
  if timer_fired_count() != 0 { ok = false; }
  if !ok_is(timer_level_granularity(0), 1) { ok = false; }
  if !ok_is(timer_level_granularity(1), 64) { ok = false; }
  if !ok_is(timer_level_granularity(2), 4096) { ok = false; }
  if !ok_is(timer_level_granularity(3), 262144) { ok = false; }
  if !err_is(timer_level_granularity(4), 12, 4, -1) { ok = false; }
  if !err_is(timer_level_granularity(-1), 12, -1, -1) { ok = false; }
  return assert(ok, "configure 4x64: caps, granularities, empty counters");
}

fn t2() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !err_is(timer_configure(0, 64), 1, 0, 64) { ok = false; }
  if !err_is(timer_configure(4, 1), 2, 4, 1) { ok = false; }
  if !err_is(timer_configure(9, 70), 3, 9, 70) { ok = false; }
  if !err_is(timer_configure(4, 1025), 4, 4, 1025) { ok = false; }
  if !err_is(timer_configure(8, 1024), 5, 8, 1024) { ok = false; }
  // geometry is untouched by failed configurations
  if timer_levels() != 4 { ok = false; }
  if timer_slots() != 64 { ok = false; }
  if timer_max_delay() != 16777215 { ok = false; }
  // boundary-valid shapes still configure
  if !ok_is(timer_configure(1, 2), 1) { ok = false; }
  if !ok_is(timer_configure(8, 2), 255) { ok = false; }
  if timer_levels() != 8 { ok = false; }
  if timer_slots() != 2 { ok = false; }
  if !ok_is(timer_configure(4, 64), 16777215) { ok = false; }
  return assert(ok, "geometry validation 1..5, rejected bad shapes, kept good shapes");
}

fn t3() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !ok_is(timer_bucket_level(1), 0) { ok = false; }
  if !ok_is(timer_bucket_level(63), 0) { ok = false; }
  if !ok_is(timer_bucket_level(64), 1) { ok = false; }
  if !ok_is(timer_bucket_level(4095), 1) { ok = false; }
  if !ok_is(timer_bucket_level(4096), 2) { ok = false; }
  if !ok_is(timer_bucket_level(262143), 2) { ok = false; }
  if !ok_is(timer_bucket_level(262144), 3) { ok = false; }
  if !ok_is(timer_bucket_level(16777215), 3) { ok = false; }
  if !err_is(timer_bucket_level(0), 6, -1, 0) { ok = false; }
  if !err_is(timer_bucket_level(-5), 6, -1, -5) { ok = false; }
  if !err_is(timer_bucket_level(16777216), 7, -1, 16777216) { ok = false; }
  return assert(ok, "delay-to-level breakdown with pinned boundaries and errors");
}

fn t4() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !ok_is(timer_bucket_slot(5), 5) { ok = false; }
  if !ok_is(timer_bucket_slot(63), 63) { ok = false; }
  if !ok_is(timer_bucket_slot(64), 1) { ok = false; }
  if !ok_is(timer_bucket_slot(100), 1) { ok = false; }
  if !ok_is(timer_bucket_slot(128), 2) { ok = false; }
  if !ok_is(timer_bucket_slot(4096), 1) { ok = false; }
  if !ok_is(timer_bucket_slot(262144), 1) { ok = false; }
  if !ok_is(timer_bucket_slot(16777215), 63) { ok = false; }
  // alignment matters: the slot is computed from the absolute deadline
  if !ok_is(timer_advance(63), 0) { ok = false; }
  if timer_now() != 63 { ok = false; }
  if !ok_is(timer_bucket_slot(1), 0) { ok = false; }
  if !ok_is(timer_bucket_slot(100), 2) { ok = false; }
  if !err_is(timer_bucket_slot(0), 6, -1, 0) { ok = false; }
  if !err_is(timer_bucket_slot(16777216), 7, -1, 16777216) { ok = false; }
  return assert(ok, "delay-to-slot breakdown uses divisor/modulo of the deadline");
}

fn t5() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !ok_is(timer_insert(7, 10), 0) { ok = false; }
  if timer_pending_count() != 1 { ok = false; }
  if !timer_is_scheduled(7) { ok = false; }
  if timer_is_scheduled(8) { ok = false; }
  if !ok_is(timer_cancel(7), 10) { ok = false; }
  if timer_pending_count() != 0 { ok = false; }
  if timer_is_scheduled(7) { ok = false; }
  if !err_is(timer_cancel(7), 9, 7, -1) { ok = false; }
  // ids are caller handles: zero and negative ids are legal
  if !ok_is(timer_insert(0, 3), 0) { ok = false; }
  if !ok_is(timer_insert(-4, 3), 0) { ok = false; }
  if timer_pending_count() != 2 { ok = false; }
  if !err_is(timer_insert(-4, 2), 8, -4, 2) { ok = false; }
  if !ok_is(timer_cancel(0), 3) { ok = false; }
  if !ok_is(timer_cancel(-4), 3) { ok = false; }
  if timer_pending_count() != 0 { ok = false; }
  return assert(ok, "insert/cancel matrix: pending, scheduled, unknown and duplicate ids");
}

fn t6() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !err_is(timer_insert(1, 0), 6, 1, 0) { ok = false; }
  if !err_is(timer_insert(1, -3), 6, 1, -3) { ok = false; }
  if !err_is(timer_insert(1, 16777216), 7, 1, 16777216) { ok = false; }
  if !ok_is(timer_insert(1, 16777215), 3) { ok = false; }
  if !err_is(timer_insert(1, 5), 8, 1, 5) { ok = false; }
  if timer_pending_count() != 1 { ok = false; }
  if !ok_is(timer_cancel(1), 16777215) { ok = false; }
  // a fired id is free to reuse
  if !ok_is(timer_insert(2, 1), 0) { ok = false; }
  if !ok_is(timer_advance(1), 1) { ok = false; }
  if timer_is_scheduled(2) { ok = false; }
  if !ok_is(timer_insert(2, 1), 0) { ok = false; }
  if !ok_is(timer_cancel(2), 1) { ok = false; }
  return assert(ok, "insert rejects non-positive/oversized delays and duplicate ids");
}

fn t7() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !ok_is(timer_insert(1, 5), 0) { ok = false; }
  if !ok_is(timer_advance(4), 0) { ok = false; }
  if timer_fired_count() != 0 { ok = false; }
  if timer_pending_count() != 1 { ok = false; }
  if timer_now() != 4 { ok = false; }
  if !ok_is(timer_advance(1), 1) { ok = false; }
  if timer_now() != 5 { ok = false; }
  if timer_fired_count() != 1 { ok = false; }
  if fired_at(0) != 1 { ok = false; }
  if timer_pending_count() != 0 { ok = false; }
  let oob = timer_fired_id(1);
  var ok2 = !oob.is_ok;
  if ok2 {
    let m: Str = oob.error;
    if compare.str_compare(m, "timer: fired index out of range") != 0 { ok2 = false; }
  }
  if !ok2 { ok = false; }
  // the fired output resets on every advance, including zero
  if !ok_is(timer_advance(0), 0) { ok = false; }
  if timer_fired_count() != 0 { ok = false; }
  return assert(ok, "firing is tick-exact; fired ids are exposed in order");
}

fn t8() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !ok_is(timer_insert(10, 7), 0) { ok = false; }
  if !ok_is(timer_insert(11, 7), 0) { ok = false; }
  if !ok_is(timer_insert(12, 7), 0) { ok = false; }
  if !ok_is(timer_advance(7), 3) { ok = false; }
  if timer_fired_count() != 3 { ok = false; }
  if fired_at(0) != 10 { ok = false; }
  if fired_at(1) != 11 { ok = false; }
  if fired_at(2) != 12 { ok = false; }
  return assert(ok, "same-deadline inserts keep FIFO order within the bucket");
}

fn t9() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !ok_is(timer_insert(20, 10), 0) { ok = false; }
  if !ok_is(timer_advance(3), 0) { ok = false; }
  if !ok_is(timer_insert(21, 7), 0) { ok = false; }
  // both deadlines are tick 10 and both land in the level-0 bucket 10
  if !ok_is(timer_bucket_level(10), 0) { ok = false; }
  if !ok_is(timer_advance(7), 2) { ok = false; }
  if fired_at(0) != 20 { ok = false; }
  if fired_at(1) != 21 { ok = false; }
  return assert(ok, "entries reaching one bucket at different times stay FIFO");
}

fn t10() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !ok_is(timer_insert(30, 5), 0) { ok = false; }
  if !ok_is(timer_insert(31, 5), 0) { ok = false; }
  if !ok_is(timer_cancel(30), 5) { ok = false; }
  if timer_pending_count() != 1 { ok = false; }
  if !ok_is(timer_advance(5), 1) { ok = false; }
  if fired_at(0) != 31 { ok = false; }
  if timer_is_scheduled(30) { ok = false; }
  if timer_pending_count() != 0 { ok = false; }
  return assert(ok, "cancelled ids never fire; the rest of the bucket still does");
}

fn t11() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !ok_is(timer_insert(40, 100), 1) { ok = false; }
  if timer_cascade_count() != 0 { ok = false; }
  if !ok_is(timer_advance(64), 0) { ok = false; }
  if timer_now() != 64 { ok = false; }
  if timer_cascade_count() != 1 { ok = false; }
  if timer_pending_count() != 1 { ok = false; }
  if !ok_is(timer_advance(36), 1) { ok = false; }
  if fired_at(0) != 40 { ok = false; }
  if timer_now() != 100 { ok = false; }
  if timer_cascade_count() != 1 { ok = false; }
  return assert(ok, "a 100-tick delay cascades at tick 64 and fires at 100");
}

fn t12() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !ok_is(timer_insert(50, 262213), 3) { ok = false; }
  if !ok_is(timer_advance(262144), 0) { ok = false; }
  if timer_cascade_count() != 1 { ok = false; }
  if !ok_is(timer_advance(64), 0) { ok = false; }
  if timer_cascade_count() != 2 { ok = false; }
  if !ok_is(timer_advance(5), 1) { ok = false; }
  if fired_at(0) != 50 { ok = false; }
  if timer_now() != 262213 { ok = false; }
  return assert(ok, "one delay cascades 3 -> 1 -> 0 across two wraps");
}

fn t13() -> TestResult {
  var ok = ok_is(timer_configure(2, 4), 15);
  if !ok_is(timer_level_granularity(0), 1) { ok = false; }
  if !ok_is(timer_level_granularity(1), 4) { ok = false; }
  if !err_is(timer_insert(60, 16), 7, 60, 16) { ok = false; }
  if !ok_is(timer_insert(60, 15), 1) { ok = false; }
  if !ok_is(timer_insert(61, 3), 0) { ok = false; }
  if !ok_is(timer_insert(62, 4), 1) { ok = false; }
  if !ok_is(timer_advance(3), 1) { ok = false; }
  if fired_at(0) != 61 { ok = false; }
  if !ok_is(timer_advance(1), 1) { ok = false; }
  if fired_at(0) != 62 { ok = false; }
  if !ok_is(timer_advance(11), 1) { ok = false; }
  if fired_at(0) != 60 { ok = false; }
  if timer_cascade_count() != 1 { ok = false; }
  if timer_now() != 15 { ok = false; }
  return assert(ok, "2x4 wheel: wrap boundary, direct cascade fire, exact deadline");
}

fn t14() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !ok_is(timer_insert(70, 5), 0) { ok = false; }
  if !ok_is(timer_insert(71, 999999), 3) { ok = false; }
  if !ok_is(timer_advance(1000000), 2) { ok = false; }
  if fired_at(0) != 70 { ok = false; }
  if fired_at(1) != 71 { ok = false; }
  if timer_now() != 1000000 { ok = false; }
  if timer_pending_count() != 0 { ok = false; }
  // an empty wheel jumps in one step
  if !ok_is(timer_advance(1000000), 0) { ok = false; }
  if timer_now() != 2000000 { ok = false; }
  if timer_fired_count() != 0 { ok = false; }
  return assert(ok, "long idle advance fires both ends and empties the wheel");
}

fn t15() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !ok_is(timer_insert(80, 16777215), 3) { ok = false; }
  if !ok_is(timer_cancel(80), 16777215) { ok = false; }
  if !err_is(timer_insert(81, 16777216), 7, 81, 16777216) { ok = false; }
  // the boundary fires exactly at the maximum for a small geometry
  if !ok_is(timer_configure(3, 16), 4095) { ok = false; }
  if !ok_is(timer_insert(82, 4095), 2) { ok = false; }
  if !ok_is(timer_advance(4095), 1) { ok = false; }
  if fired_at(0) != 82 { ok = false; }
  if timer_now() != 4095 { ok = false; }
  if !err_is(timer_insert(83, 4096), 7, 83, 4096) { ok = false; }
  return assert(ok, "max delay is representable; max+1 is rejected");
}

// One fixed insert/advance/cancel scenario; returns the fired ids in order
// (any failed step appends a negative marker so t16 fails loudly).
fn scenario_run() -> Vec[Int] {
  var out = Vec[Int].new();
  if !ok_is(timer_configure(3, 8), 511) { out.push(-1); }
  if !ok_is(timer_insert(1, 5), 0) { out.push(-2); }
  if !ok_is(timer_insert(2, 70), 2) { out.push(-3); }
  if !ok_is(timer_insert(3, 8), 1) { out.push(-4); }
  if !ok_is(timer_insert(4, 300), 2) { out.push(-5); }
  if !ok_is(timer_cancel(3), 8) { out.push(-6); }
  if !ok_is(timer_advance(6), 1) { out.push(-7); }
  append_fired(&mut out);
  if !ok_is(timer_advance(64), 1) { out.push(-8); }
  append_fired(&mut out);
  if !ok_is(timer_advance(230), 1) { out.push(-9); }
  append_fired(&mut out);
  return out;
}

fn t16() -> TestResult {
  let a = scenario_run();
  let b = scenario_run();
  var ok = a.len() == 3;
  if b.len() != 3 { ok = false; }
  if ok {
    let a0: Int = a[0];
    let a1: Int = a[1];
    let a2: Int = a[2];
    let b0: Int = b[0];
    let b1: Int = b[1];
    let b2: Int = b[2];
    if a0 != 1 { ok = false; }
    if a1 != 2 { ok = false; }
    if a2 != 4 { ok = false; }
    if a0 != b0 { ok = false; }
    if a1 != b1 { ok = false; }
    if a2 != b2 { ok = false; }
  }
  if timer_cascade_count() != 3 { ok = false; }
  return assert(ok, "replaying one scenario yields identical fired output");
}

fn t17() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !err_is(timer_cancel(999), 9, 999, -1) { ok = false; }
  if !ok_is(timer_insert(90, 2), 0) { ok = false; }
  if !ok_is(timer_advance(2), 1) { ok = false; }
  if !err_is(timer_cancel(90), 9, 90, -1) { ok = false; }
  if timer_pending_count() != 0 { ok = false; }
  return assert(ok, "cancelling an unknown or already-fired id is Err code 9");
}

fn t18() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  if !ok_is(timer_insert(95, 3), 0) { ok = false; }
  if !err_is(timer_advance(-1), 10, -1, -1) { ok = false; }
  if timer_now() != 0 { ok = false; }
  if timer_pending_count() != 1 { ok = false; }
  if !ok_is(timer_advance(0), 0) { ok = false; }
  if timer_now() != 0 { ok = false; }
  if timer_pending_count() != 1 { ok = false; }
  if !ok_is(timer_advance(3), 1) { ok = false; }
  if fired_at(0) != 95 { ok = false; }
  return assert(ok, "negative advance is Err; zero advance is a state no-op");
}

fn t19() -> TestResult {
  var ok = ok_is(timer_configure(2, 4), 15);
  var i = 0;
  var failures = 0;
  while i < 1024 {
    let r = timer_insert(i + 1, 15);
    if !r.is_ok { failures = failures + 1; }
    i = i + 1;
  }
  if failures != 0 { ok = false; }
  if timer_pending_count() != 1024 { ok = false; }
  if !err_is(timer_insert(2000, 1), 11, 2000, 1) { ok = false; }
  if !ok_is(timer_advance(15), 1024) { ok = false; }
  if timer_fired_count() != 1024 { ok = false; }
  if fired_at(0) != 1 { ok = false; }
  if fired_at(512) != 513 { ok = false; }
  if fired_at(1023) != 1024 { ok = false; }
  if timer_pending_count() != 0 { ok = false; }
  // released pool slots are reused after the fires
  if !ok_is(timer_insert(2000, 1), 0) { ok = false; }
  if !ok_is(timer_advance(1), 1) { ok = false; }
  if fired_at(0) != 2000 { ok = false; }
  return assert(ok, "pool capacity is enforced and released slots are reusable");
}

fn t20() -> TestResult {
  var ok = msg_is(1, "timer: levels must be positive");
  if !msg_is(2, "timer: slots must be at least 2") { ok = false; }
  if !msg_is(3, "timer: levels exceeds maximum") { ok = false; }
  if !msg_is(4, "timer: slots exceeds maximum") { ok = false; }
  if !msg_is(5, "timer: geometry exceeds maximum delay") { ok = false; }
  if !msg_is(6, "timer: delay must be positive") { ok = false; }
  if !msg_is(7, "timer: delay exceeds maximum") { ok = false; }
  if !msg_is(8, "timer: duplicate id") { ok = false; }
  if !msg_is(9, "timer: unknown id") { ok = false; }
  if !msg_is(10, "timer: negative advance") { ok = false; }
  if !msg_is(11, "timer: entry pool is full") { ok = false; }
  if !msg_is(12, "timer: level out of range") { ok = false; }
  if !msg_is(99, "timer: unknown error") { ok = false; }
  return assert(ok, "error catalog messages are pinned");
}

fn t21() -> TestResult {
  var ok = ok_is(timer_configure(4, 64), 16777215);
  // id 300 sits at level 1 (delay 64) and fires from the tick-64 cascade;
  // id 301 lands at level 0 (deadline 64) and fires from the level-0 bucket
  // of the same tick. Documented order: cascade fires first, then level 0.
  if !ok_is(timer_insert(300, 64), 1) { ok = false; }
  if !ok_is(timer_advance(40), 0) { ok = false; }
  if !ok_is(timer_insert(301, 24), 0) { ok = false; }
  if !ok_is(timer_advance(24), 2) { ok = false; }
  if timer_fired_count() != 2 { ok = false; }
  if fired_at(0) != 300 { ok = false; }
  if fired_at(1) != 301 { ok = false; }
  // a direct fire during a cascade is not a downward move
  if timer_cascade_count() != 0 { ok = false; }
  if timer_now() != 64 { ok = false; }
  return assert(ok, "same-tick ordering: cascades fire before the level-0 bucket");
}

fn main() -> Int {
  io.println("=== xiom.timer conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.timer: all tests passed");
  } else {
    io.println("xiom.timer: tests failed");
  }
  return failed;
}
