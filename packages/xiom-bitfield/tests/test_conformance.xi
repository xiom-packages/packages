// XIOM -- xiom.bitfield conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pins the documented API: masks (0/1/8/31/32/63/64), field extraction
// across byte boundaries, invalid-field results, set/clear/toggle exactness,
// over-wide field masking, popcount (including INT64_MIN), leading and
// trailing zeros, bit reversal, byte swaps and rotations at widths 8/32/64
// with n reduced mod width.
//
// The suite avoids `&`, `|` and shifts too, so it does not depend on the
// v0.61.3 bitwise codegen path; expected values are decimal literals and
// INT64_MIN is written as 0 - INT64_MAX - 1.

module bitfield_tests
use xiom.io; use xiom.test;
use xiom.bitfield;

fn i64min() -> Int {
  return 0 - 9223372036854775807 - 1;
}

// 0x0102030405060708 as a signed-positive Int literal.
fn pattern() -> Int {
  return 72623859790382856;
}

fn t1() -> TestResult {
  var ok = bit_mask(0) == 0;
  if bit_mask(-1) != 0 { ok = false; }
  if bit_mask(1) != 1 { ok = false; }
  if bit_mask(8) != 255 { ok = false; }
  if bit_mask(31) != 2147483647 { ok = false; }
  if bit_mask(32) != 4294967295 { ok = false; }
  if bit_mask(63) != 9223372036854775807 { ok = false; }
  if bit_mask(64) != -1 { ok = false; }
  if bit_mask(100) != -1 { ok = false; }
  return assert(ok, "bit_mask pinned at 0, 1, 8, 31, 32, 63, 64, 100");
}

fn t2() -> TestResult {
  let v = pattern();
  var ok = bit_get(v, 0, 8) == 8;
  if bit_get(v, 8, 8) != 7 { ok = false; }
  if bit_get(v, 16, 8) != 6 { ok = false; }
  if bit_get(v, 56, 8) != 1 { ok = false; }
  if bit_get(v, 4, 8) != 112 { ok = false; }
  if bit_get(v, 24, 16) != 1029 { ok = false; }
  if bit_get(v, 32, 32) != 16909060 { ok = false; }
  if bit_get(v, 56, 4) != 1 { ok = false; }
  if bit_get(v, 60, 4) != 0 { ok = false; }
  return assert(ok, "bit_get across byte boundaries on 0x0102030405060708");
}

fn t3() -> TestResult {
  let v = pattern();
  var ok = bit_get(v, -1, 8) == 0;
  if bit_get(v, 64, 1) != 0 { ok = false; }
  if bit_get(v, 0, 0) != 0 { ok = false; }
  if bit_get(v, 0, -5) != 0 { ok = false; }
  if bit_get(v, 60, 8) != 0 { ok = false; }
  if bit_get(v, 0, 65) != 0 { ok = false; }
  if bit_get(v, 33, 32) != 0 { ok = false; }
  if bit_get(i64min(), 0, 64) != i64min() { ok = false; }
  if bit_get(-1, 0, 64) != -1 { ok = false; }
  if bit_get(i64min(), 63, 1) != 1 { ok = false; }
  if bit_get(i64min(), 62, 1) != 0 { ok = false; }
  return assert(ok, "bit_get invalid => 0; full-width and sign-bit reads");
}

fn t4() -> TestResult {
  let v = pattern();
  var ok = bit_set(0, 0, 8, 171) == 171;
  if bit_set(0, 8, 8, 255) != 65280 { ok = false; }
  if bit_set(4294967295, 8, 8, 18) != 4294906623 { ok = false; }
  if bit_set(-1, 0, 4, 0) != -16 { ok = false; }
  if bit_set(0, 63, 1, 1) != i64min() { ok = false; }
  if bit_set(-1, 0, 32, 0) != -4294967296 { ok = false; }
  if bit_set(0, 32, 16, 4660) != 20014547599360 { ok = false; }
  if bit_set(0, 60, 4, 7) != 8070450532247928832 { ok = false; }
  if bit_set(0, 16, 8, 6) != 393216 { ok = false; }
  if bit_set(v, 8, 8, 18) != 72623859790385672 { ok = false; }
  return assert(ok, "bit_set replaces exactly the selected field");
}

fn t5() -> TestResult {
  var ok = bit_set(0, 0, 4, 255) == 15;
  if bit_set(0, 4, 4, 171) != 176 { ok = false; }
  if bit_set(0, 0, 8, 511) != 255 { ok = false; }
  if bit_set(0, 0, 1, 3) != 1 { ok = false; }
  if bit_set(0, 0, 2, 6) != 2 { ok = false; }
  if bit_set(-1, 8, 8, -1) != -1 { ok = false; }
  if bit_set(-1, 8, 8, 256) != -65281 { ok = false; }
  return assert(ok, "a field wider than width is masked to the low width bits");
}

fn t6() -> TestResult {
  let v = pattern();
  var ok = bit_clear(4294967295, 8, 8) == 4294902015;
  if bit_clear(-1, 0, 64) != 0 { ok = false; }
  if bit_clear(-1, 63, 1) != 9223372036854775807 { ok = false; }
  if bit_clear(0, 0, 8) != 0 { ok = false; }
  if bit_clear(-1, 0, 32) != -4294967296 { ok = false; }
  if bit_clear(-1, 60, 4) != 1152921504606846975 { ok = false; }
  if bit_clear(v, 8, 8) != 72623859790381064 { ok = false; }
  if bit_clear(v, 4, 4) != v { ok = false; }
  return assert(ok, "bit_clear zeroes exactly the selected field");
}

fn t7() -> TestResult {
  let v = pattern();
  var ok = bit_set(v, -1, 4, 1) == v;
  if bit_set(v, 64, 1, 1) != v { ok = false; }
  if bit_set(v, 60, 8, 255) != v { ok = false; }
  if bit_set(v, 0, 0, 1) != v { ok = false; }
  if bit_set(v, 0, 65, 1) != v { ok = false; }
  if bit_clear(v, -1, 4) != v { ok = false; }
  if bit_clear(v, 64, 1) != v { ok = false; }
  if bit_clear(v, 60, 8) != v { ok = false; }
  if bit_clear(v, 0, 65) != v { ok = false; }
  if bit_clear(v, 0, 0) != v { ok = false; }
  return assert(ok, "invalid fields leave set/clear inputs unchanged");
}

fn t8() -> TestResult {
  let v = pattern();
  var ok = bit_toggle(0, 0) == 1;
  if bit_toggle(1, 0) != 0 { ok = false; }
  if bit_toggle(0, 63) != i64min() { ok = false; }
  if bit_toggle(i64min(), 63) != 0 { ok = false; }
  if bit_toggle(-1, 5) != -33 { ok = false; }
  if bit_toggle(0, 5) != 32 { ok = false; }
  if bit_toggle(v, 8) != 72623859790382600 { ok = false; }
  if bit_toggle(v, 3) != 72623859790382848 { ok = false; }
  if bit_toggle(0, -1) != 0 { ok = false; }
  if bit_toggle(0, 64) != 0 { ok = false; }
  if bit_toggle(7, 64) != 7 { ok = false; }
  return assert(ok, "bit_toggle flips exactly one bit");
}

fn t9() -> TestResult {
  var ok = bit_count_ones(0) == 0;
  if bit_count_ones(1) != 1 { ok = false; }
  if bit_count_ones(15) != 4 { ok = false; }
  if bit_count_ones(255) != 8 { ok = false; }
  if bit_count_ones(-1) != 64 { ok = false; }
  if bit_count_ones(i64min()) != 1 { ok = false; }
  if bit_count_ones(9223372036854775807) != 63 { ok = false; }
  if bit_count_ones(6148914691236517205) != 32 { ok = false; }
  if bit_count_ones(-6148914691236517206) != 32 { ok = false; }
  return assert(ok, "popcount: 0, 1, 0x0F, -1, sign bit, alternating 32/32");
}

fn t10() -> TestResult {
  var ok = bit_leading_zeros(0) == 64;
  if bit_leading_zeros(1) != 63 { ok = false; }
  if bit_leading_zeros(2) != 62 { ok = false; }
  if bit_leading_zeros(255) != 56 { ok = false; }
  if bit_leading_zeros(256) != 55 { ok = false; }
  if bit_leading_zeros(4294967295) != 32 { ok = false; }
  if bit_leading_zeros(9223372036854775807) != 1 { ok = false; }
  if bit_leading_zeros(-1) != 0 { ok = false; }
  if bit_leading_zeros(i64min()) != 0 { ok = false; }
  return assert(ok, "leading zeros: 0 => 64, 1 => 63, negatives => 0");
}

fn t11() -> TestResult {
  var ok = bit_trailing_zeros(0) == 64;
  if bit_trailing_zeros(1) != 0 { ok = false; }
  if bit_trailing_zeros(2) != 1 { ok = false; }
  if bit_trailing_zeros(3) != 0 { ok = false; }
  if bit_trailing_zeros(256) != 8 { ok = false; }
  if bit_trailing_zeros(65280) != 8 { ok = false; }
  if bit_trailing_zeros(-1) != 0 { ok = false; }
  if bit_trailing_zeros(i64min()) != 63 { ok = false; }
  if bit_trailing_zeros(9223372036854775807) != 0 { ok = false; }
  return assert(ok, "trailing zeros: 0 => 64, 1 => 0, INT64_MIN => 63");
}

fn t12() -> TestResult {
  var ok = bit_reverse(0, 8) == 0;
  if bit_reverse(1, 8) != 128 { ok = false; }
  if bit_reverse(128, 8) != 1 { ok = false; }
  if bit_reverse(183, 8) != 237 { ok = false; }
  if bit_reverse(18, 8) != 72 { ok = false; }
  if bit_reverse(255, 8) != 255 { ok = false; }
  if bit_reverse(3, 1) != 1 { ok = false; }
  if bit_reverse(0, 1) != 0 { ok = false; }
  if bit_reverse(32768, 8) != 0 { ok = false; }
  return assert(ok, "bit_reverse width 8 pinned (0xB7 -> 0xED)");
}

fn t13() -> TestResult {
  var ok = bit_reverse(4660, 16) == 11336;
  if bit_reverse(1, 16) != 32768 { ok = false; }
  if bit_reverse(32768, 16) != 1 { ok = false; }
  if bit_reverse(255, 16) != 65280 { ok = false; }
  if bit_reverse(65280, 16) != 255 { ok = false; }
  if bit_reverse(-1, 16) != 65535 { ok = false; }
  if bit_reverse(-1, 8) != 255 { ok = false; }
  return assert(ok, "bit_reverse width 16 pinned (0x1234 -> 0x2C48)");
}

fn t14() -> TestResult {
  var ok = bit_reverse(1, 64) == i64min();
  if bit_reverse(i64min(), 64) != 1 { ok = false; }
  if bit_reverse(-1, 64) != -1 { ok = false; }
  if bit_reverse(0, 64) != 0 { ok = false; }
  if bit_reverse(5, 0) != 0 { ok = false; }
  if bit_reverse(5, -3) != 0 { ok = false; }
  if bit_reverse(5, 65) != 0 { ok = false; }
  return assert(ok, "bit_reverse width 64 round-trips; invalid widths => 0");
}

fn t15() -> TestResult {
  var ok = bit_byte_swap16(0) == 0;
  if bit_byte_swap16(4660) != 13330 { ok = false; }
  if bit_byte_swap16(255) != 65280 { ok = false; }
  if bit_byte_swap16(65535) != 65535 { ok = false; }
  if bit_byte_swap16(-1) != 65535 { ok = false; }
  if bit_byte_swap16(305419896) != 30806 { ok = false; }
  if bit_byte_swap16(i64min()) != 0 { ok = false; }
  return assert(ok, "bit_byte_swap16 pinned (0x1234 -> 0x3412)");
}

fn t16() -> TestResult {
  var ok = bit_byte_swap32(0) == 0;
  if bit_byte_swap32(1) != 16777216 { ok = false; }
  if bit_byte_swap32(287454020) != 1144201745 { ok = false; }
  if bit_byte_swap32(305419896) != 2018915346 { ok = false; }
  if bit_byte_swap32(-1) != 4294967295 { ok = false; }
  if bit_byte_swap32(16711935) != 4278255360 { ok = false; }
  if bit_byte_swap32(i64min()) != 0 { ok = false; }
  return assert(ok, "bit_byte_swap32 pinned (0x11223344 -> 0x44332211)");
}

fn t17() -> TestResult {
  var ok = bit_rotate_left(129, 8, 1) == 3;
  if bit_rotate_left(129, 8, 8) != 129 { ok = false; }
  if bit_rotate_left(129, 8, 9) != 3 { ok = false; }
  if bit_rotate_left(129, 8, -1) != 192 { ok = false; }
  if bit_rotate_left(129, 8, -8) != 129 { ok = false; }
  if bit_rotate_left(0, 8, 5) != 0 { ok = false; }
  if bit_rotate_left(255, 8, 3) != 255 { ok = false; }
  if bit_rotate_left(1, 8, 7) != 128 { ok = false; }
  return assert(ok, "bit_rotate_left width 8 with n mod width");
}

fn t18() -> TestResult {
  var ok = bit_rotate_left(2147483649, 32, 1) == 3;
  if bit_rotate_left(305419896, 32, 8) != 878082066 { ok = false; }
  if bit_rotate_left(305419896, 32, 32) != 305419896 { ok = false; }
  if bit_rotate_left(305419896, 32, 40) != 878082066 { ok = false; }
  if bit_rotate_left(-1, 32, 7) != 4294967295 { ok = false; }
  if bit_rotate_left(1, 32, 31) != 2147483648 { ok = false; }
  if bit_rotate_left(2147483648, 32, 1) != 1 { ok = false; }
  return assert(ok, "bit_rotate_left width 32 with n mod width");
}

fn t19() -> TestResult {
  var ok = bit_rotate_right(3, 8, 1) == 129;
  if bit_rotate_right(129, 8, 1) != 192 { ok = false; }
  if bit_rotate_right(305419896, 32, 8) != 2014458966 { ok = false; }
  if bit_rotate_right(1, 64, 1) != i64min() { ok = false; }
  if bit_rotate_right(i64min(), 64, 1) != 4611686018427387904 { ok = false; }
  if bit_rotate_right(-1, 64, 13) != -1 { ok = false; }
  if bit_rotate_right(3, 8, -1) != 6 { ok = false; }
  if bit_rotate_right(3, 8, 16) != 3 { ok = false; }
  if bit_rotate_right(32769, 16, 1) != 49152 { ok = false; }
  return assert(ok, "bit_rotate_right at widths 8/16/32/64 with n mod width");
}

fn t20() -> TestResult {
  var ok = bit_rotate_left(i64min() + 1, 64, 1) == 3;
  if bit_rotate_left(1, 64, 1) != 2 { ok = false; }
  if bit_rotate_left(1, 64, 64) != 1 { ok = false; }
  if bit_rotate_left(-1, 64, 5) != -1 { ok = false; }
  if bit_rotate_left(9223372036854775807, 64, 1) != -2 { ok = false; }
  if bit_rotate_left(1, 1, 7) != 1 { ok = false; }
  if bit_rotate_left(0, 1, 7) != 0 { ok = false; }
  if bit_rotate_left(5, 0, 3) != 0 { ok = false; }
  if bit_rotate_left(5, 65, 3) != 0 { ok = false; }
  if bit_rotate_left(5, -1, 3) != 0 { ok = false; }
  if bit_rotate_right(5, 0, 3) != 0 { ok = false; }
  if bit_rotate_right(5, 65, 3) != 0 { ok = false; }
  if bit_rotate_right(5, -1, 3) != 0 { ok = false; }
  return assert(ok, "width 64 rotation wraps the sign bit; invalid widths => 0");
}

fn main() -> Int {
  io.println("=== xiom.bitfield conformance tests ===");
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
    io.println("xiom.bitfield: all tests passed");
  } else {
    io.println("xiom.bitfield: tests failed");
  }
  return failed;
}
