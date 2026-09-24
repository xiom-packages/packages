// XIOM -- xiom.pagination conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.pagination module and its documented
// clamping rules, half-open windows and opaque cursor tokens.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: page_offset (including overflow clamping),
// page_count (exact/ceiling/empty), page_bounds (first/middle/last/
// out-of-range), page_has_next, page_has_prev, page_last, page_clamp and
// cursor_encode/cursor_decode (round-trips, pinned known tokens, strict
// alphabet/padding/shape rejection, negative-input clamping, canonical
// unpadded output).
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq instead of `==`.

module pagination_tests
use xiom.io; use xiom.test; use xiom.pagination;
use xiom.string; use xiom.string.compare;

// 64-bit signed maximum, the value page_offset clamps to and cursor_decode
// accepts as the largest encodable number.
const T_MAX: Int = 9223372036854775807;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is Ok and carries exactly (want_off, want_lim).
fn ok_is(r: Result[(Int, Int), Str], want_off: Int, want_lim: Int) -> Bool {
  match r {
    Ok(t) => {
      return t.0 == want_off && t.1 == want_lim;
    },
    Err(_) => {},
  }
  return false;
}

// True when r is an Err whose message is exactly `want`.
fn err_is(r: Result[(Int, Int), Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when r is an Err whose message starts with "pagination: ".
fn err_prefix(r: Result[(Int, Int), Str]) -> Bool {
  if r.is_ok {
    return false;
  }
  let m = r.error;
  if m.len() < 12 {
    return false;
  }
  return streq(string.str_slice(m, 0, 12), "pagination: ");
}

// True when page_bounds returns exactly (want_start, want_end).
fn bounds_is(page: Int, per: Int, total: Int, want_start: Int, want_end: Int) -> Bool {
  let (s, e) = page_bounds(page, per, total);
  return s == want_start && e == want_end;
}

fn t1() -> TestResult {
  var ok = page_offset(1, 10) == 0;
  if page_offset(2, 10) != 10 { ok = false; }
  if page_offset(5, 25) != 100 { ok = false; }
  if page_offset(0, 10) != 0 { ok = false; }
  if page_offset(-3, 10) != 0 { ok = false; }
  if page_offset(5, 0) != 0 { ok = false; }
  if page_offset(5, -2) != 0 { ok = false; }
  return assert(ok, "page_offset: (page-1)*per_page with invalid inputs as 0");
}

fn t2() -> TestResult {
  var ok = page_offset(T_MAX, 1) == T_MAX - 1;
  if page_offset(2, T_MAX) != T_MAX { ok = false; }
  if page_offset(T_MAX - 1, 1) != T_MAX - 2 { ok = false; }
  if page_offset(T_MAX, 2) != T_MAX { ok = false; }
  if page_offset(T_MAX, T_MAX) != T_MAX { ok = false; }
  return assert(ok, "page_offset: overflow-safe clamp to Int max");
}

fn t3() -> TestResult {
  var ok = page_count(100, 10) == 10;
  if page_count(10, 10) != 1 { ok = false; }
  if page_count(0, 10) != 0 { ok = false; }
  if page_count(-5, 10) != 0 { ok = false; }
  if page_count(100, 0) != 0 { ok = false; }
  if page_count(100, -1) != 0 { ok = false; }
  return assert(ok, "page_count: exact division and empty inputs");
}

fn t4() -> TestResult {
  var ok = page_count(101, 10) == 11;
  if page_count(1, 10) != 1 { ok = false; }
  if page_count(99, 10) != 10 { ok = false; }
  if page_count(T_MAX, 1) != T_MAX { ok = false; }
  if page_count(T_MAX, 2) != 4611686018427387904 { ok = false; }
  return assert(ok, "page_count: ceiling division without overflow");
}

fn t5() -> TestResult {
  var ok = bounds_is(1, 10, 100, 0, 10);
  if !bounds_is(2, 10, 100, 10, 20) { ok = false; }
  if !bounds_is(2, 25, 60, 25, 50) { ok = false; }
  if !bounds_is(3, 25, 60, 50, 60) { ok = false; }
  return assert(ok, "page_bounds: first and middle pages are half-open windows");
}

fn t6() -> TestResult {
  var ok = bounds_is(10, 10, 100, 90, 100);
  if !bounds_is(4, 10, 95, 30, 40) { ok = false; }
  if !bounds_is(10, 10, 95, 90, 95) { ok = false; }
  let half = T_MAX / 2 + 1;
  if !bounds_is(2, half, T_MAX, half, T_MAX) { ok = false; }
  return assert(ok, "page_bounds: last page clamped to total without overflow");
}

fn t7() -> TestResult {
  var ok = bounds_is(11, 10, 100, 0, 0);
  if !bounds_is(99, 10, 100, 0, 0) { ok = false; }
  if !bounds_is(0, 10, 100, 0, 0) { ok = false; }
  if !bounds_is(-1, 10, 100, 0, 0) { ok = false; }
  if !bounds_is(1, 0, 100, 0, 0) { ok = false; }
  if !bounds_is(1, -4, 100, 0, 0) { ok = false; }
  if !bounds_is(1, 10, 0, 0, 0) { ok = false; }
  if !bounds_is(1, 10, -5, 0, 0) { ok = false; }
  return assert(ok, "page_bounds: out-of-range page and invalid inputs yield (0,0)");
}

fn t8() -> TestResult {
  var ok = page_has_next(1, 10, 100);
  if page_has_next(10, 10, 100) { ok = false; }
  if page_has_next(11, 10, 100) { ok = false; }
  if !page_has_next(9, 10, 95) { ok = false; }
  if page_has_next(10, 10, 95) { ok = false; }
  if page_has_next(0, 10, 100) { ok = false; }
  if page_has_next(1, 0, 100) { ok = false; }
  if page_has_next(1, 10, 0) { ok = false; }
  return assert(ok, "page_has_next: true exactly while page < last");
}

fn t9() -> TestResult {
  var ok = !page_has_prev(1);
  if !page_has_prev(2) { ok = false; }
  if page_has_prev(0) { ok = false; }
  if page_has_prev(-5) { ok = false; }
  if !page_has_prev(T_MAX) { ok = false; }
  return assert(ok, "page_has_prev: page > 1");
}

fn t10() -> TestResult {
  var ok = page_last(100, 10) == 10;
  if page_last(101, 10) != 11 { ok = false; }
  if page_last(0, 10) != 0 { ok = false; }
  if page_last(10, 0) != 0 { ok = false; }
  if page_last(10, 10) != 1 { ok = false; }
  return assert(ok, "page_last: 0 when there are no pages");
}

fn t11() -> TestResult {
  var ok = page_clamp(5, 100, 10) == 5;
  if page_clamp(0, 100, 10) != 1 { ok = false; }
  if page_clamp(-9, 100, 10) != 1 { ok = false; }
  if page_clamp(11, 100, 10) != 10 { ok = false; }
  if page_clamp(99, 100, 10) != 10 { ok = false; }
  if page_clamp(5, 0, 10) != 1 { ok = false; }
  if page_clamp(5, 10, 0) != 1 { ok = false; }
  return assert(ok, "page_clamp: 1..last and 1 when empty");
}

fn t12() -> TestResult {
  var ok = ok_is(cursor_decode(cursor_encode(0, 10)), 0, 10);
  if !ok_is(cursor_decode(cursor_encode(123, 50)), 123, 50) { ok = false; }
  if !ok_is(cursor_decode(cursor_encode(0, 1)), 0, 1) { ok = false; }
  if !ok_is(cursor_decode(cursor_encode(1, 1)), 1, 1) { ok = false; }
  if !ok_is(cursor_decode(cursor_encode(999, 1000)), 999, 1000) { ok = false; }
  return assert(ok, "cursor: encode/decode round-trips");
}

fn t13() -> TestResult {
  var ok = ok_is(cursor_decode(cursor_encode(T_MAX, T_MAX)), T_MAX, T_MAX);
  if !ok_is(cursor_decode(cursor_encode(999999999, 1000000)), 999999999, 1000000) { ok = false; }
  if !ok_is(cursor_decode("MDoxMA"), 0, 10) { ok = false; }
  if !ok_is(cursor_decode("MTIzOjUw"), 123, 50) { ok = false; }
  if !ok_is(cursor_decode("OTIyMzM3MjAzNjg1NDc3NTgwNzox"), T_MAX, 1) { ok = false; }
  if !streq(cursor_encode(0, 10), "MDoxMA") { ok = false; }
  if !streq(cursor_encode(123, 50), "MTIzOjUw") { ok = false; }
  return assert(ok, "cursor: pinned known tokens and large values");
}

fn t14() -> TestResult {
  var ok = err_prefix(cursor_decode("!"));
  if !err_prefix(cursor_decode("MDoxMA=")) { ok = false; }
  if !err_prefix(cursor_decode("MDoxMA==")) { ok = false; }
  if !err_prefix(cursor_decode("MDox+MA")) { ok = false; }
  if !err_prefix(cursor_decode("MDox/MA")) { ok = false; }
  if !err_prefix(cursor_decode(" MDoxMA")) { ok = false; }
  if !err_prefix(cursor_decode("MDoxMA\n")) { ok = false; }
  if !err_prefix(cursor_decode("MDoxgé")) { ok = false; }
  if err_prefix(cursor_decode("MDoxMA")) { ok = false; }
  return assert(ok, "cursor_decode: bad alphabet and padding are Err");
}

fn t15() -> TestResult {
  var ok = err_is(cursor_decode(""), "pagination: empty cursor");
  if !err_prefix(cursor_decode("YWJj")) { ok = false; }
  if !err_prefix(cursor_decode("A")) { ok = false; }
  if !err_prefix(cursor_decode("MDoxM")) { ok = false; }
  if !err_prefix(cursor_decode("MDow")) { ok = false; }
  if !err_prefix(cursor_decode("MDA6MTA")) { ok = false; }
  if !err_prefix(cursor_decode("MDo")) { ok = false; }
  if !err_prefix(cursor_decode("OjEw")) { ok = false; }
  if !err_prefix(cursor_decode("MTo6Mg")) { ok = false; }
  if !err_prefix(cursor_decode("LTE6NQ")) { ok = false; }
  if !err_prefix(cursor_decode("OTIyMzM3MjAzNjg1NDc3NTgwODox")) { ok = false; }
  if !err_prefix(cursor_decode("MTo5MjIzMzcyMDM2ODU0Nzc1ODA4")) { ok = false; }
  return assert(ok, "cursor_decode: bad shape, empty and overflow are Err");
}

fn t16() -> TestResult {
  var ok = streq(cursor_encode(-5, 0), cursor_encode(0, 1));
  if !streq(cursor_encode(0, 1), "MDox") { ok = false; }
  if !streq(cursor_encode(-100, -7), cursor_encode(0, 1)) { ok = false; }
  if !ok_is(cursor_decode(cursor_encode(-100, -7)), 0, 1) { ok = false; }
  if !ok_is(cursor_decode("MDo1"), 0, 5) { ok = false; }
  return assert(ok, "cursor_encode: negative offset and limit are clamped");
}

fn t17() -> TestResult {
  let short = cursor_encode(0, 10);
  var ok = !string.str_contains(short, "=");
  if string.str_contains(short, "+") { ok = false; }
  if string.str_contains(short, "/") { ok = false; }
  let large = cursor_encode(T_MAX, T_MAX);
  if large.len() != 52 { ok = false; }
  if string.str_contains(large, "=") { ok = false; }
  return assert(ok, "cursor: canonical unpadded URL-safe alphabet");
}

fn t18() -> TestResult {
  var ok = page_count(0, 10) == 0;
  if page_last(0, 10) != 0 { ok = false; }
  if !bounds_is(1, 10, 0, 0, 0) { ok = false; }
  if page_has_next(1, 10, 0) { ok = false; }
  if page_has_prev(1) { ok = false; }
  if page_clamp(7, 0, 10) != 1 { ok = false; }
  return assert(ok, "empty collection: no pages, clamp reports page 1");
}

fn t19() -> TestResult {
  let total = 95;
  let per = 10;
  let last = page_last(total, per);
  var ok = last == 10;
  var p = 1;
  while p <= last {
    let (s, e) = page_bounds(p, per, total);
    if s != page_offset(p, per) { ok = false; }
    if e > total { ok = false; }
    if s >= e { ok = false; }
    if p < last {
      if e - s != per { ok = false; }
      let (ns, ne) = page_bounds(p + 1, per, total);
      if e != ns { ok = false; }
      if ne <= ns { ok = false; }
    } else {
      if e != total { ok = false; }
    }
    p = p + 1;
  }
  return assert(ok, "consistency: bounds tile [0,total) and match page_offset");
}

fn t20() -> TestResult {
  let total = 23;
  let per = 5;
  let last = page_last(total, per);
  var ok = last == 5;
  var p = 1;
  while p <= last + 1 {
    let next = page_has_next(p, per, total);
    if p < last && !next { ok = false; }
    if p >= last && next { ok = false; }
    let prev = page_has_prev(p);
    if p > 1 && !prev { ok = false; }
    if p <= 1 && prev { ok = false; }
    p = p + 1;
  }
  return assert(ok, "consistency: has_next/has_prev agree with page_last");
}

fn main() -> Int {
  io.println("=== xiom.pagination conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.pagination: all tests passed");
  } else {
    io.println("xiom.pagination: tests failed");
  }
  return failed;
}
