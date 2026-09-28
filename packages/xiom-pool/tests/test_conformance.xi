// XIOM -- xiom.pool conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM xiom.pool slot state machine:
// capacities, borrow order, exhaustion, raw and lease releases, generation
// staleness, counters, high-water tracking and drains.
//
// The suite drives the pool exclusively through its public API. Every Str
// comparison goes through str_compare, and every Vec element read is bound
// to a typed local.

module pool_tests
use xiom.io; use xiom.test; use xiom.pool;
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

// True when borrowing yields exactly `want`.
fn borrow_is(p: &mut Pool, want: Int) -> Bool {
  let r = pool_borrow(p);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

// True when a raw release of `id` succeeds with Ok(id).
fn release_is(p: &mut Pool, id: Int) -> Bool {
  let r = pool_release(p, id);
  match r {
    Ok(v) => { return v == id; },
    Err(_) => { return false; },
  }
  return false;
}

// True when a lease release succeeds with Ok(want_id).
fn lease_release_is(p: &mut Pool, lease: Int, want_id: Int) -> Bool {
  let r = pool_release_lease(p, lease);
  match r {
    Ok(v) => { return v == want_id; },
    Err(_) => { return false; },
  }
  return false;
}

// Borrow a lease or fail the check.
fn lease_is(p: &mut Pool, want: Int) -> Bool {
  let r = pool_borrow_lease(p);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  let p = pool_new(3);
  var ok = pool_capacity(&p) == 3;
  if pool_available(&p) != 3 { ok = false; }
  if pool_in_use(&p) != 0 { ok = false; }
  if pool_high_water(&p) != 0 { ok = false; }
  if pool_total_borrows(&p) != 0 { ok = false; }
  if pool_total_releases(&p) != 0 { ok = false; }
  if pool_is_borrowed(&p, 0) { ok = false; }
  return assert(ok, "a fresh pool reports capacity and zeroed counters");
}

fn t2() -> TestResult {
  var p = pool_new(3);
  var ok = borrow_is(&mut p, 0);
  if !borrow_is(&mut p, 1) { ok = false; }
  if !borrow_is(&mut p, 2) { ok = false; }
  if pool_in_use(&p) != 3 { ok = false; }
  if pool_available(&p) != 0 { ok = false; }
  if pool_high_water(&p) != 3 { ok = false; }
  if pool_total_borrows(&p) != 3 { ok = false; }
  if !pool_is_borrowed(&p, 1) { ok = false; }
  return assert(ok, "a fresh pool hands out slots in ascending order");
}

fn t3() -> TestResult {
  var p = pool_new(2);
  var ok = borrow_is(&mut p, 0);
  if !borrow_is(&mut p, 1) { ok = false; }
  if !err_is(pool_borrow(&mut p), "pool: exhausted") { ok = false; }
  if pool_available(&p) != 0 { ok = false; }
  if pool_in_use(&p) != 2 { ok = false; }
  return assert(ok, "exhausted pools reject borrows with a deterministic error");
}

fn t4() -> TestResult {
  var zero = pool_new(0);
  var ok = pool_capacity(&zero) == 0;
  if !err_is(pool_borrow(&mut zero), "pool: exhausted") { ok = false; }
  var neg = pool_new(-4);
  if pool_capacity(&neg) != 0 { ok = false; }
  if !err_is(pool_borrow_lease(&mut neg), "pool: exhausted") { ok = false; }
  return assert(ok, "zero and negative capacities are valid but never lend");
}

fn t5() -> TestResult {
  var p = pool_new(3);
  var ok = borrow_is(&mut p, 0);
  if !borrow_is(&mut p, 1) { ok = false; }
  if !borrow_is(&mut p, 2) { ok = false; }
  if !release_is(&mut p, 1) { ok = false; }
  if !borrow_is(&mut p, 1) { ok = false; }
  if !release_is(&mut p, 2) { ok = false; }
  if !borrow_is(&mut p, 2) { ok = false; }
  if pool_available(&p) != 0 { ok = false; }
  return assert(ok, "a released slot is reused by the next borrow (LIFO)");
}

fn t6() -> TestResult {
  var p = pool_new(3);
  var ok = err_is(pool_release(&mut p, -1), "pool: bad slot -1");
  if !err_is(pool_release(&mut p, 3), "pool: bad slot 3") { ok = false; }
  if !err_is(pool_release(&mut p, 0), "pool: slot 0 is not borrowed") { ok = false; }
  if !borrow_is(&mut p, 0) { ok = false; }
  if !release_is(&mut p, 0) { ok = false; }
  if !err_is(pool_release(&mut p, 0), "pool: slot 0 is not borrowed") { ok = false; }
  if pool_total_borrows(&p) != 1 { ok = false; }
  if pool_total_releases(&p) != 1 { ok = false; }
  return assert(ok, "raw releases reject bad ids and repeated releases");
}

fn t7() -> TestResult {
  var p = pool_new(2);
  var ok = lease_is(&mut p, 3);
  if !lease_is(&mut p, 4) { ok = false; }
  if !lease_release_is(&mut p, 3, 0) { ok = false; }
  if pool_in_use(&p) != 1 { ok = false; }
  if !pool_is_borrowed(&p, 1) { ok = false; }
  return assert(ok, "lease tokens encode slot id and generation");
}

fn t8() -> TestResult {
  var p = pool_new(2);
  var ok = lease_is(&mut p, 3);
  if !lease_release_is(&mut p, 3, 0) { ok = false; }
  if !err_is(pool_release_lease(&mut p, 3), "pool: stale lease 3") { ok = false; }
  if !lease_is(&mut p, 6) { ok = false; }
  if !err_is(pool_release_lease(&mut p, 3), "pool: stale lease 3") { ok = false; }
  if !lease_release_is(&mut p, 6, 0) { ok = false; }
  return assert(ok, "a used or outdated lease is rejected as stale");
}

fn t9() -> TestResult {
  var p = pool_new(2);
  var ok = err_is(pool_release_lease(&mut p, -5), "pool: bad lease -5");
  if !err_is(pool_release_lease(&mut p, 0), "pool: bad lease 0") { ok = false; }
  if !err_is(pool_release_lease(&mut p, 2), "pool: bad lease 2") { ok = false; }
  var zero = pool_new(0);
  if !err_is(pool_release_lease(&mut zero, 1), "pool: bad lease 1") { ok = false; }
  return assert(ok, "undecodable lease tokens are rejected as bad leases");
}

fn t10() -> TestResult {
  var p = pool_new(3);
  var ok = borrow_is(&mut p, 0);
  if !borrow_is(&mut p, 1) { ok = false; }
  if !borrow_is(&mut p, 2) { ok = false; }
  if !release_is(&mut p, 0) { ok = false; }
  if !release_is(&mut p, 1) { ok = false; }
  if !release_is(&mut p, 2) { ok = false; }
  if !borrow_is(&mut p, 2) { ok = false; }
  if pool_high_water(&p) != 3 { ok = false; }
  if pool_in_use(&p) != 1 { ok = false; }
  return assert(ok, "high water remembers the peak in-use count");
}

fn t11() -> TestResult {
  var p = pool_new(2);
  var ok = pool_generation(&p, 0) == 0;
  if !borrow_is(&mut p, 0) { ok = false; }
  if pool_generation(&p, 0) != 1 { ok = false; }
  if !release_is(&mut p, 0) { ok = false; }
  if pool_generation(&p, 0) != 1 { ok = false; }
  if !borrow_is(&mut p, 0) { ok = false; }
  if pool_generation(&p, 0) != 2 { ok = false; }
  if pool_generation(&p, -1) != -1 { ok = false; }
  if pool_generation(&p, 2) != -1 { ok = false; }
  return assert(ok, "generations advance once per borrow");
}

fn t12() -> TestResult {
  var p = pool_new(4);
  var ok = borrow_is(&mut p, 0);
  if !borrow_is(&mut p, 1) { ok = false; }
  if !borrow_is(&mut p, 2) { ok = false; }
  if pool_drain(&mut p) != 3 { ok = false; }
  if pool_in_use(&p) != 0 { ok = false; }
  if pool_available(&p) != 4 { ok = false; }
  if pool_total_releases(&p) != 3 { ok = false; }
  if pool_drain(&mut p) != 0 { ok = false; }
  if !borrow_is(&mut p, 0) { ok = false; }
  return assert(ok, "drain releases every borrowed slot and reports the count");
}

fn t13() -> TestResult {
  var p = pool_new(2);
  var ok = borrow_is(&mut p, 0);
  if !release_is(&mut p, 0) { ok = false; }
  if !borrow_is(&mut p, 0) { ok = false; }
  if !borrow_is(&mut p, 1) { ok = false; }
  if !release_is(&mut p, 1) { ok = false; }
  if !release_is(&mut p, 0) { ok = false; }
  if pool_total_borrows(&p) != 3 { ok = false; }
  if pool_total_releases(&p) != 3 { ok = false; }
  if pool_high_water(&p) != 2 { ok = false; }
  return assert(ok, "borrow and release totals accumulate across cycles");
}

fn t14() -> TestResult {
  var p = pool_new(5);
  var ok = true;
  var i = 0;
  while i < 5 {
    let r = pool_borrow(&mut p);
    match r {
      Ok(_) => {
        if pool_capacity(&p) != pool_available(&p) + pool_in_use(&p) { ok = false; }
      },
      Err(_) => { ok = false; },
    }
    i = i + 1;
  }
  i = 0;
  while i < 5 {
    if !release_is(&mut p, i) { ok = false; }
    if pool_capacity(&p) != pool_available(&p) + pool_in_use(&p) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "capacity always equals available plus in_use");
}

fn t15() -> TestResult {
  var p = pool_new(3);
  var ok = lease_is(&mut p, 4);
  if !borrow_is(&mut p, 1) { ok = false; }
  if !lease_is(&mut p, 6) { ok = false; }
  if !pool_is_borrowed(&p, 0) { ok = false; }
  if !pool_is_borrowed(&p, 1) { ok = false; }
  if !pool_is_borrowed(&p, 2) { ok = false; }
  if !lease_release_is(&mut p, 4, 0) { ok = false; }
  if pool_is_borrowed(&p, 0) { ok = false; }
  if !borrow_is(&mut p, 0) { ok = false; }
  if !pool_is_borrowed(&p, 0) { ok = false; }
  return assert(ok, "leases and raw borrows share one free stack");
}

fn t16() -> TestResult {
  var p = pool_new(1);
  var ok = lease_is(&mut p, 2);
  if !lease_release_is(&mut p, 2, 0) { ok = false; }
  if !lease_is(&mut p, 4) { ok = false; }
  if !lease_release_is(&mut p, 4, 0) { ok = false; }
  if !lease_is(&mut p, 6) { ok = false; }
  if pool_generation(&p, 0) != 3 { ok = false; }
  return assert(ok, "single-slot pools advance one generation per borrow");
}

fn t17() -> TestResult {
  var empty = pool_new(2);
  var ok = pool_drain(&empty) == 0;
  if pool_total_releases(&empty) != 0 { ok = false; }
  var p = pool_new(3);
  if !borrow_is(&mut p, 0) { ok = false; }
  if !borrow_is(&mut p, 1) { ok = false; }
  if pool_drain(&p) != 2 { ok = false; }
  if !borrow_is(&mut p, 0) { ok = false; }
  if !borrow_is(&mut p, 1) { ok = false; }
  if !borrow_is(&mut p, 2) { ok = false; }
  return assert(ok, "draining an idle pool is a no-op and restores fresh order");
}

fn t18() -> TestResult {
  var p = pool_new(2);
  var ok = lease_is(&mut p, 3);
  if !lease_release_is(&mut p, 3, 0) { ok = false; }
  if !borrow_is(&mut p, 0) { ok = false; }
  if !err_is(pool_release_lease(&mut p, 3), "pool: stale lease 3") { ok = false; }
  if pool_in_use(&p) != 1 { ok = false; }
  return assert(ok, "a generation bump invalidates the previous lease");
}

fn t19() -> TestResult {
  var p = pool_new(2);
  var ok = pool_available(&p) == 2;
  if !borrow_is(&mut p, 0) { ok = false; }
  if !borrow_is(&mut p, 1) { ok = false; }
  if pool_available(&p) != 0 { ok = false; }
  if !release_is(&mut p, 0) { ok = false; }
  if pool_available(&p) != 1 { ok = false; }
  if pool_available(&p) + pool_in_use(&p) != pool_capacity(&p) { ok = false; }
  return assert(ok, "available and in_use never go out of range");
}

fn t20() -> TestResult {
  var p = pool_new(1);
  var ok = lease_is(&mut p, 2);
  if !lease_release_is(&mut p, 2, 0) { ok = false; }
  if !lease_is(&mut p, 4) { ok = false; }
  if !lease_release_is(&mut p, 4, 0) { ok = false; }
  if !lease_is(&mut p, 6) { ok = false; }
  if !lease_release_is(&mut p, 6, 0) { ok = false; }
  return assert(ok, "leases issued across cycles are pairwise distinct");
}

fn t21() -> TestResult {
  let p = pool_new(2);
  var ok = !pool_is_borrowed(&p, -1);
  if pool_is_borrowed(&p, 2) { ok = false; }
  if pool_generation(&p, 9) != -1 { ok = false; }
  var q = pool_new(1);
  if pool_capacity(&q) != 1 { ok = false; }
  if pool_high_water(&q) != 0 { ok = false; }
  return assert(ok, "slot accessors are bounds-safe");
}

fn t22() -> TestResult {
  var p = pool_new(3);
  var ok = lease_is(&mut p, 4);
  if !lease_is(&mut p, 5) { ok = false; }
  if !lease_release_is(&mut p, 4, 0) { ok = false; }
  if pool_drain(&p) != 1 { ok = false; }
  if pool_in_use(&p) != 0 { ok = false; }
  if pool_total_borrows(&p) != 2 { ok = false; }
  if pool_total_releases(&p) != 2 { ok = false; }
  if !err_is(pool_release_lease(&mut p, 5), "pool: stale lease 5") { ok = false; }
  return assert(ok, "drain counts leased slots and invalidates their tokens");
}

fn main() -> Int {
  io.println("=== xiom.pool conformance tests ===");
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
    io.println("xiom.pool: all tests passed");
  } else {
    io.println("xiom.pool: tests failed");
  }
  return failed;
}
