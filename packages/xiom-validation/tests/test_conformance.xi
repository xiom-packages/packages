// XIOM -- xiom.validation conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.validation module against its documented
// accept/reject sets.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 5. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// No Str equality is used anywhere in this suite, so BUG 17 (`==` on Str
// values read from Vec[Str] elements lowers to a pointer comparison) cannot
// apply here.

module validation_tests
use xiom.io; use xiom.test; use xiom.validation;

fn t1() -> TestResult {
  var ok = valid_is_email("a@b.co");
  if !valid_is_email("first.last+tag@sub.domain.org") { ok = false; }
  if !valid_is_email("user_name%x-1@example.com") { ok = false; }
  if !valid_is_email("A.B@Example.COM") { ok = false; }
  return assert(ok, "email: valid basic addresses");
}

fn t2() -> TestResult {
  var ok = !valid_is_email("no-at-sign.com");
  if valid_is_email("two@@at.co") { ok = false; }
  if valid_is_email("a@b@c.co") { ok = false; }
  if valid_is_email("") { ok = false; }
  if valid_is_email("@missing.co") { ok = false; }
  if valid_is_email("missing@") { ok = false; }
  return assert(ok, "email: exactly one @ and non-empty sides");
}

fn t3() -> TestResult {
  var ok = valid_is_email("a.b@x.co");
  if valid_is_email(".lead@x.co") { ok = false; }
  if valid_is_email("trail.@x.co") { ok = false; }
  if valid_is_email("two..dots@x.co") { ok = false; }
  if !valid_is_email("a_b+c%d-e@x.co") { ok = false; }
  return assert(ok, "email: local part dot rules and charset");
}

fn t4() -> TestResult {
  var ok = valid_is_email("a@b.co");
  if valid_is_email("a@b") { ok = false; }
  if valid_is_email("a@b.c") { ok = false; }
  if valid_is_email("a@b..co") { ok = false; }
  if valid_is_email("a@-bad.co") { ok = false; }
  if valid_is_email("a@bad-.co") { ok = false; }
  if valid_is_email("a@b.") { ok = false; }
  return assert(ok, "email: domain labels need a dot and clean dashes");
}

fn t5() -> TestResult {
  var ok = valid_is_email("a@b.cd");
  if valid_is_email("a@b.c0") { ok = false; }
  if valid_is_email("a@b.c_") { ok = false; }
  if valid_is_email("a b@x.co") { ok = false; }
  if valid_is_email("café@x.co") { ok = false; }
  if valid_is_email("a@exämple.co") { ok = false; }
  if !valid_is_email("a@b.museum") { ok = false; }
  return assert(ok, "email: ASCII only, letter TLD of length >= 2");
}

fn t6() -> TestResult {
  var local = "";
  var i = 0;
  while i < 64 {
    local = local + "a";
    i = i + 1;
  }
  var ok = valid_is_email(local + "@x.co");
  if valid_is_email(local + "a@x.co") { ok = false; }
  return assert(ok, "email: local part is 1..64 characters");
}

fn t7() -> TestResult {
  var ok = valid_is_ipv4("0.0.0.0");
  if !valid_is_ipv4("255.255.255.255") { ok = false; }
  if !valid_is_ipv4("192.168.1.1") { ok = false; }
  if !valid_is_ipv4("10.0.255.9") { ok = false; }
  return assert(ok, "ipv4: valid dotted quads");
}

fn t8() -> TestResult {
  var ok = !valid_is_ipv4("256.0.0.1");
  if valid_is_ipv4("1.2.3") { ok = false; }
  if valid_is_ipv4("1.2.3.4.5") { ok = false; }
  if valid_is_ipv4("01.2.3.4") { ok = false; }
  if valid_is_ipv4("1..2.3") { ok = false; }
  if valid_is_ipv4("1.2.3.") { ok = false; }
  if valid_is_ipv4("a.b.c.d") { ok = false; }
  if valid_is_ipv4("") { ok = false; }
  if valid_is_ipv4("1.2.3.256") { ok = false; }
  return assert(ok, "ipv4: rejects range, count, leading-zero and junk");
}

fn t9() -> TestResult {
  var ok = valid_is_ipv4("0.1.2.3");
  if valid_is_ipv4("00.1.2.3") { ok = false; }
  if valid_is_ipv4("1.02.3.4") { ok = false; }
  if valid_is_ipv4("1.2.3.04") { ok = false; }
  if !valid_is_ipv4("1.2.3.0") { ok = false; }
  if valid_is_ipv4(".1.2.3") { ok = false; }
  if valid_is_ipv4("1.2.3.+4") { ok = false; }
  return assert(ok, "ipv4: only a bare 0 may start with 0");
}

fn t10() -> TestResult {
  var ok = valid_is_ipv6("::1");
  if !valid_is_ipv6("fe80::1") { ok = false; }
  if !valid_is_ipv6("2001:db8:0:0:0:0:0:1") { ok = false; }
  if !valid_is_ipv6("1:2:3:4:5:6:7:8") { ok = false; }
  if !valid_is_ipv6("::") { ok = false; }
  if !valid_is_ipv6("2001:db8::") { ok = false; }
  return assert(ok, "ipv6: :: compression and full eight groups");
}

fn t11() -> TestResult {
  var ok = !valid_is_ipv6(":::");
  if valid_is_ipv6("12345::") { ok = false; }
  if valid_is_ipv6(":") { ok = false; }
  if valid_is_ipv6(":::1") { ok = false; }
  if valid_is_ipv6("1:2:3:4:5:6:7:8:9") { ok = false; }
  if valid_is_ipv6("1::2::3") { ok = false; }
  if valid_is_ipv6("") { ok = false; }
  return assert(ok, "ipv6: rejects triple colon, long group, nine groups");
}

fn t12() -> TestResult {
  var ok = valid_is_ipv6("ABCD::EF01");
  if !valid_is_ipv6("1:2:3:4:5:6:7::") { ok = false; }
  if valid_is_ipv6("1:2:3:4:5:6:7:8::") { ok = false; }
  if valid_is_ipv6("g::1") { ok = false; }
  if valid_is_ipv6("fe80::1:") { ok = false; }
  if valid_is_ipv6(":fe80::1") { ok = false; }
  return assert(ok, "ipv6: hex case, :: bound and stray colons");
}

fn t13() -> TestResult {
  var ok = valid_is_hex("deadBEEF");
  if !valid_is_hex("0123456789abcdef") { ok = false; }
  if !valid_is_hex("0") { ok = false; }
  if !valid_is_hex("A") { ok = false; }
  if !valid_is_hex("00ff") { ok = false; }
  return assert(ok, "hex: valid [0-9A-Fa-f] strings");
}

fn t14() -> TestResult {
  var ok = !valid_is_hex("");
  if valid_is_hex("0x12") { ok = false; }
  if valid_is_hex("12 34") { ok = false; }
  if valid_is_hex("xyz") { ok = false; }
  if valid_is_hex("12g4") { ok = false; }
  if valid_is_hex("dead-beef") { ok = false; }
  return assert(ok, "hex: rejects empty, prefixes, spaces and junk");
}

fn t15() -> TestResult {
  var ok = valid_is_uuid("550e8400-e29b-41d4-a716-446655440000");
  if !valid_is_uuid("550E8400-E29B-41D4-A716-446655440000") { ok = false; }
  if !valid_is_uuid("00000000-0000-0000-0000-000000000000") { ok = false; }
  return assert(ok, "uuid: canonical 8-4-4-4-12, case-insensitive");
}

fn t16() -> TestResult {
  var ok = !valid_is_uuid("550e8400-e29b-41d4-a716-44665544000");
  if valid_is_uuid("550e8400-e29b-41d4-a716-4466554400000") { ok = false; }
  if valid_is_uuid("550e8400e29b-41d4-a716-446655440000") { ok = false; }
  if valid_is_uuid("550e8400-e29b41d4-a716-446655440000") { ok = false; }
  if valid_is_uuid("550e8400-e29b-41d4-a716-44665544zzzz") { ok = false; }
  if valid_is_uuid("") { ok = false; }
  return assert(ok, "uuid: rejects wrong length, hyphen and hex errors");
}

fn t17() -> TestResult {
  var ok = valid_is_slug("hello");
  if !valid_is_slug("hello-world") { ok = false; }
  if !valid_is_slug("a1-b2-c3") { ok = false; }
  if !valid_is_slug("abc123") { ok = false; }
  if !valid_is_slug("x") { ok = false; }
  return assert(ok, "slug: lowercase alnum words joined by single dashes");
}

fn t18() -> TestResult {
  var ok = !valid_is_slug("");
  if valid_is_slug("-hello") { ok = false; }
  if valid_is_slug("hello-") { ok = false; }
  if valid_is_slug("hello--world") { ok = false; }
  if valid_is_slug("Hello") { ok = false; }
  if valid_is_slug("hello_world") { ok = false; }
  if valid_is_slug("hello world") { ok = false; }
  if valid_is_slug("héllo") { ok = false; }
  if valid_is_slug("-") { ok = false; }
  return assert(ok, "slug: rejects empty, dashes, case and non-ASCII");
}

fn t19() -> TestResult {
  var ok = valid_is_date_ymd(2000, 2, 29);
  if !valid_is_date_ymd(2024, 2, 29) { ok = false; }
  if valid_is_date_ymd(1900, 2, 29) { ok = false; }
  if valid_is_date_ymd(2100, 2, 29) { ok = false; }
  if !valid_is_date_ymd(2004, 2, 29) { ok = false; }
  if !valid_is_date_ymd(2400, 2, 29) { ok = false; }
  return assert(ok, "dates: Gregorian century leap rules");
}

fn t20() -> TestResult {
  var ok = valid_is_date_ymd(2024, 1, 31);
  if !valid_is_date_ymd(2024, 12, 31) { ok = false; }
  if valid_is_date_ymd(2024, 4, 31) { ok = false; }
  if valid_is_date_ymd(2024, 6, 31) { ok = false; }
  if valid_is_date_ymd(2024, 9, 31) { ok = false; }
  if valid_is_date_ymd(2024, 11, 31) { ok = false; }
  if valid_is_date_ymd(2024, 13, 1) { ok = false; }
  if valid_is_date_ymd(2024, 0, 1) { ok = false; }
  if valid_is_date_ymd(2024, 1, 0) { ok = false; }
  if valid_is_date_ymd(2024, 1, 32) { ok = false; }
  if valid_is_date_ymd(0, 1, 1) { ok = false; }
  if valid_is_date_ymd(-1, 1, 1) { ok = false; }
  return assert(ok, "dates: month lengths and day bounds");
}

fn t21() -> TestResult {
  var ok = !valid_is_date_ymd(2024, 2, 30);
  if valid_is_date_ymd(2023, 2, 29) { ok = false; }
  if !valid_is_date_ymd(2023, 2, 28) { ok = false; }
  if !valid_is_date_ymd(1900, 2, 28) { ok = false; }
  if valid_is_date_ymd(2024, 2, 0) { ok = false; }
  return assert(ok, "dates: February 28/29/30 behaviour");
}

fn t22() -> TestResult {
  var ok = valid_is_port(1);
  if !valid_is_port(80) { ok = false; }
  if !valid_is_port(443) { ok = false; }
  if !valid_is_port(65535) { ok = false; }
  if valid_is_port(0) { ok = false; }
  if valid_is_port(65536) { ok = false; }
  if valid_is_port(-1) { ok = false; }
  return assert(ok, "ports: 1..65535 inclusive");
}

fn t23() -> TestResult {
  var ok = valid_is_email("a@b.co");
  if !valid_is_email("a@b.cd") { ok = false; }
  if valid_is_email("a@b.c") { ok = false; }
  if valid_is_email("a@b.co2") { ok = false; }
  if valid_is_email("a@b_c.co") { ok = false; }
  if valid_is_email("a@[127.0.0.1]") { ok = false; }
  return assert(ok, "email: TLD letters and domain charset");
}

fn t24() -> TestResult {
  var ok = valid_is_ipv6("::");
  if !valid_is_ipv6("1::") { ok = false; }
  if !valid_is_ipv6("::8") { ok = false; }
  if !valid_is_ipv6("1::8") { ok = false; }
  if valid_is_ipv6("1:2:3:4:5:6:7:8::") { ok = false; }
  if valid_is_ipv6("1::2:3:4:5:6:7:8") { ok = false; }
  return assert(ok, "ipv6: :: stands for one or more zero groups");
}

fn main() -> Int {
  io.println("=== xiom.validation conformance tests ===");
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
    io.println("xiom.validation: all tests passed");
  } else {
    io.println("xiom.validation: tests failed");
  }
  return failed;
}
