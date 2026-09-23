// XIOM -- xiom.scheduler conformance tests (28 checks)
// Port task: prove the pure-XIOM xiom.scheduler module against its documented
// cron semantics (UTC, pure civil-date math).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through streq instead of `==`. Vec[Int] element reads use a
// typed `let`.
//
// Epoch anchors used below (verified against Unix time, UTC):
//   2026-01-01T00:00:00Z = 1767225600 (Thursday)
//   2026-01-01T00:15:00Z = 1767226500
//   2026-01-01T00:03:20Z = 1767225800
//   2026-01-01T09:30:00Z = 1767259800
//   2026-01-02T00:00:00Z = 1767312000 (Friday)
//   2026-01-04T00:00:00Z = 1767484800 (Sunday)
//   2026-01-08T00:00:00Z = 1767830400 (Thursday)
//   2026-01-15T00:00:00Z = 1768435200 (Thursday)
//   2026-02-01T00:00:00Z = 1769904000
//   2028-02-29T00:00:00Z = 1835395200

module scheduler_tests
use xiom.io; use xiom.test; use xiom.scheduler;
use xiom.string;
use xiom.string.compare;

const _T_JAN1: Int = 1767225600;
const _T_0015: Int = 1767226500;
const _T_0003: Int = 1767225800;
const _T_0001: Int = 1767225660;
const _T_0930: Int = 1767259800;
const _T_JAN2: Int = 1767312000;
const _T_JAN2_0930: Int = 1767346200;
const _T_JAN4: Int = 1767484800;
const _T_JAN8: Int = 1767830400;
const _T_JAN15: Int = 1768435200;
const _T_FEB1: Int = 1769904000;
const _T_MAR1: Int = 1772323200;
const _T_FEB29_2028: Int = 1835395200;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn int_at(v: &Vec[Int], i: Int, want: Int) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  let x: Int = v[i];
  return x == want;
}

fn parse_ok(expr: Str) -> Bool {
  match cron_parse(expr) {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

fn err_prefix(expr: Str) -> Bool {
  match cron_parse(expr) {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "cron: "); },
  }
  return false;
}

fn err_is(expr: Str, want: Str) -> Bool {
  match cron_parse(expr) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn desc_is(expr: Str, want: Str) -> Bool {
  match cron_parse(expr) {
    Ok(s) => { return streq(cron_describe(&s), want); },
    Err(_) => { return false; },
  }
  return false;
}

fn round_trips(expr: Str) -> Bool {
  match cron_parse(expr) {
    Ok(s) => {
      let once = cron_describe(&s);
      match cron_parse(once) {
        Ok(s2) => { return streq(cron_describe(&s2), once); },
        Err(_) => { return false; },
      }
    },
    Err(_) => { return false; },
  }
  return false;
}

fn matches_at(expr: Str, t: Int) -> Bool {
  match cron_parse(expr) {
    Ok(s) => { return cron_matches(&s, t); },
    Err(_) => { return false; },
  }
  return false;
}

fn next_is(expr: Str, from: Int, want: Int) -> Bool {
  match cron_parse_next(expr, from) {
    Ok(t) => { return t == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn next_err_is(expr: Str, from: Int, want: Str) -> Bool {
  match cron_parse_next(expr, from) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn t1() -> TestResult {
  let r = cron_parse("* * * * *");
  var ok = false;
  match r {
    Ok(s) => {
      ok = s.minutes.len() == 60;
      if s.hours.len() != 24 { ok = false; }
      if s.days.len() != 31 { ok = false; }
      if s.months.len() != 12 { ok = false; }
      if s.weekdays.len() != 7 { ok = false; }
      if !int_at(&s.minutes, 0, 0) { ok = false; }
      if !int_at(&s.minutes, 59, 59) { ok = false; }
      if !int_at(&s.hours, 23, 23) { ok = false; }
      if !int_at(&s.days, 30, 31) { ok = false; }
      if !int_at(&s.months, 11, 12) { ok = false; }
      if !int_at(&s.weekdays, 6, 6) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse star fields to the full allowed ranges");
}

fn t2() -> TestResult {
  let r = cron_parse("30 9 1 6 4");
  var ok = false;
  match r {
    Ok(s) => {
      ok = s.minutes.len() == 1;
      if s.hours.len() != 1 { ok = false; }
      if s.days.len() != 1 { ok = false; }
      if s.months.len() != 1 { ok = false; }
      if s.weekdays.len() != 1 { ok = false; }
      if !int_at(&s.minutes, 0, 30) { ok = false; }
      if !int_at(&s.hours, 0, 9) { ok = false; }
      if !int_at(&s.days, 0, 1) { ok = false; }
      if !int_at(&s.months, 0, 6) { ok = false; }
      if !int_at(&s.weekdays, 0, 4) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse single values into one-element fields");
}

fn t3() -> TestResult {
  let r = cron_parse("5,10,12,30 * * * *");
  var ok = false;
  match r {
    Ok(s) => {
      ok = s.minutes.len() == 4;
      if !int_at(&s.minutes, 0, 5) { ok = false; }
      if !int_at(&s.minutes, 1, 10) { ok = false; }
      if !int_at(&s.minutes, 2, 12) { ok = false; }
      if !int_at(&s.minutes, 3, 30) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse a comma list");
}

fn t4() -> TestResult {
  let r = cron_parse("10-15 * * * *");
  var ok = false;
  match r {
    Ok(s) => {
      ok = s.minutes.len() == 6;
      if !int_at(&s.minutes, 0, 10) { ok = false; }
      if !int_at(&s.minutes, 5, 15) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse a range a-b inclusively");
}

fn t5() -> TestResult {
  let r = cron_parse("*/15 * * * *");
  var ok = false;
  match r {
    Ok(s) => {
      ok = s.minutes.len() == 4;
      if !int_at(&s.minutes, 0, 0) { ok = false; }
      if !int_at(&s.minutes, 1, 15) { ok = false; }
      if !int_at(&s.minutes, 2, 30) { ok = false; }
      if !int_at(&s.minutes, 3, 45) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse a */n step over the whole range");
}

fn t6() -> TestResult {
  let r = cron_parse("1-10/3 * * * *");
  var ok = false;
  match r {
    Ok(s) => {
      ok = s.minutes.len() == 4;
      if !int_at(&s.minutes, 0, 1) { ok = false; }
      if !int_at(&s.minutes, 1, 4) { ok = false; }
      if !int_at(&s.minutes, 2, 7) { ok = false; }
      if !int_at(&s.minutes, 3, 10) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse an a-b/n range step");
}

fn t7() -> TestResult {
  let r = cron_parse("30,5,15,5 * * * *");
  var ok = false;
  match r {
    Ok(s) => {
      ok = s.minutes.len() == 3;
      if !int_at(&s.minutes, 0, 5) { ok = false; }
      if !int_at(&s.minutes, 1, 15) { ok = false; }
      if !int_at(&s.minutes, 2, 30) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !desc_is("30,5,15,5 * * * *", "5,15,30 * * * *") { ok = false; }
  if !desc_is("1,1 * * * *", "1 * * * *") { ok = false; }
  return assert(ok, "fields are sorted ascending and deduplicated");
}

fn t8() -> TestResult {
  var ok = !parse_ok("");
  if parse_ok("* * * *") { ok = false; }
  if parse_ok("* * * * * *") { ok = false; }
  if parse_ok("   ") { ok = false; }
  if !err_is("* * * *", "cron: expected 5 fields, got 4") { ok = false; }
  return assert(ok, "a non-5-field expression is rejected");
}

fn t9() -> TestResult {
  var ok = err_prefix("60 * * * *");
  if !err_prefix("* 24 * * *") { ok = false; }
  if !err_prefix("* * 0 * *") { ok = false; }
  if !err_prefix("* * 32 * *") { ok = false; }
  if !err_prefix("* * * 0 *") { ok = false; }
  if !err_prefix("* * * 13 *") { ok = false; }
  if !err_prefix("* * * * 7") { ok = false; }
  if !err_prefix("* * * * 8") { ok = false; }
  if !parse_ok("59 23 31 12 6") { ok = false; }
  return assert(ok, "values outside the allowed range are rejected");
}

fn t10() -> TestResult {
  var ok = err_prefix("abc * * * *");
  if !err_prefix("1a * * * *") { ok = false; }
  if !err_prefix("-5 * * * *") { ok = false; }
  if !err_prefix("5- * * * *") { ok = false; }
  if !err_prefix("1..2 * * * *") { ok = false; }
  if !err_prefix("1/2 * * * *") { ok = false; }
  return assert(ok, "non-numeric fields and a/n steps are rejected");
}

fn t11() -> TestResult {
  var ok = err_prefix("5-1 * * * *");
  if !err_prefix("1-70 * * * *") { ok = false; }
  if !err_prefix("*/0 * * * *") { ok = false; }
  if !err_prefix("*/ * * * *") { ok = false; }
  if !err_prefix("1-10/0 * * * *") { ok = false; }
  if !err_prefix("*/x * * * *") { ok = false; }
  if !err_prefix("1-10/ * * * *") { ok = false; }
  if !err_prefix("10-5/2 * * * *") { ok = false; }
  return assert(ok, "reversed ranges and malformed or zero steps are rejected");
}

fn t12() -> TestResult {
  var ok = err_prefix("1, * * * *");
  if !err_prefix(",1 * * * *") { ok = false; }
  if !err_prefix("1,,2 * * * *") { ok = false; }
  if !err_prefix("'* * * * *") { ok = false; }
  return assert(ok, "empty list items are rejected");
}

fn t13() -> TestResult {
  var ok = err_prefix("-1 * * * *");
  if !err_prefix("0-0-0 * * * *") { ok = false; }
  if !err_prefix("* * * * 4-3") { ok = false; }
  if !err_prefix("* * * * 0,9") { ok = false; }
  return assert(ok, "every parse error starts with \"cron: \"");
}

fn t14() -> TestResult {
  var ok = desc_is("0 0 * * *", "0 0 * * *");
  if !desc_is("* * * * *", "* * * * *") { ok = false; }
  if !desc_is("30 9 * * 4", "30 9 * * 4") { ok = false; }
  return assert(ok, "describe re-emits unrestricted fields as *");
}

fn t15() -> TestResult {
  var ok = desc_is("*/15 9 1,2 6 4", "0,15,30,45 9 1,2 6 4");
  if !desc_is("10-12 * * * *", "10,11,12 * * * *") { ok = false; }
  if !desc_is("1-10/3 0 1 1 0", "1,4,7,10 0 1 1 0") { ok = false; }
  if !desc_is("0 0 1,15 1,6,12 1,3,5", "0 0 1,15 1,6,12 1,3,5") { ok = false; }
  return assert(ok, "describe emits canonical ascending comma lists");
}

fn t16() -> TestResult {
  var ok = round_trips("*/15 * * * *");
  if !round_trips("0 0 1 * *") { ok = false; }
  if !round_trips("30,5,15 * 2 * *") { ok = false; }
  if !round_trips("* * * * *") { ok = false; }
  if !round_trips("1-10/3 0-23/2 1,15 1,6,12 0,3,5") { ok = false; }
  return assert(ok, "describe output parses back to the same description");
}

fn t17() -> TestResult {
  var ok = matches_at("0 0 * * *", _T_JAN1);
  if matches_at("0 0 * * *", _T_0001) { ok = false; }
  if matches_at("0 0 * * *", _T_0930) { ok = false; }
  if !matches_at("* * * * *", _T_0001) { ok = false; }
  if !matches_at("0 0 * * *", _T_JAN2) { ok = false; }
  return assert(ok, "0 0 * * * matches 2026-01-01T00:00:00Z (1767225600)");
}

fn t18() -> TestResult {
  var ok = matches_at("0 0 * * *", _T_JAN1 + 1);
  if !matches_at("0 0 * * *", _T_JAN1 + 30) { ok = false; }
  if !matches_at("*/15 * * * *", _T_0015 + 1) { ok = false; }
  if matches_at("0 0 * * *", _T_JAN1 + 60) { ok = false; }
  return assert(ok, "an instant matches the UTC minute that contains it");
}

fn t19() -> TestResult {
  var ok = matches_at("*/15 * * * *", _T_JAN1);
  if !matches_at("*/15 * * * *", _T_0015) { ok = false; }
  if matches_at("*/15 * * * *", _T_0003) { ok = false; }
  if matches_at("*/15 * * * *", _T_0001) { ok = false; }
  if !matches_at("30 9 * * *", _T_0930) { ok = false; }
  if matches_at("30 9 * * *", _T_JAN1) { ok = false; }
  if !matches_at("5,10,12,30 * * * *", _T_0003 + 120) { ok = false; }
  if !matches_at("10-15 * * * *", _T_0003 + 540) { ok = false; }
  return assert(ok, "step, list and range schedules match the right minutes");
}

fn t20() -> TestResult {
  var ok = matches_at("0 0 * * 4", _T_JAN1);
  if matches_at("0 0 * * 4", _T_JAN2) { ok = false; }
  if !matches_at("0 0 * * 5", _T_JAN2) { ok = false; }
  if !matches_at("0 0 * * 0", _T_JAN4) { ok = false; }
  if matches_at("0 0 * * 0", _T_JAN1) { ok = false; }
  if !matches_at("0 0 * * 0,2,4,6", _T_JAN4) { ok = false; }
  return assert(ok, "weekday restriction: 0=Sunday, 4=Thursday");
}

fn t21() -> TestResult {
  var ok = matches_at("0 0 * 2 *", _T_FEB1);
  if matches_at("0 0 * 2 *", _T_JAN1) { ok = false; }
  if !matches_at("0 0 15 1 *", _T_JAN15) { ok = false; }
  if matches_at("0 0 15 1 *", _T_JAN1) { ok = false; }
  if !matches_at("0 0 * 1 *", _T_JAN1) { ok = false; }
  if !matches_at("0 0 1 2 *", _T_FEB1) { ok = false; }
  return assert(ok, "month and day-of-month restrictions match");
}

fn t22() -> TestResult {
  var ok = matches_at("0 0 1 * 4", _T_JAN1);
  if !matches_at("0 0 15 * 4", _T_JAN8) { ok = false; }
  if !matches_at("0 0 15 * 4", _T_JAN15) { ok = false; }
  if matches_at("0 0 15 * 4", _T_JAN2) { ok = false; }
  if !matches_at("0 0 2 * 4", _T_JAN2) { ok = false; }
  if !matches_at("0 0 2 * 4", _T_JAN8) { ok = false; }
  if !matches_at("0 0 15 * *", _T_JAN15) { ok = false; }
  if matches_at("0 0 15 * *", _T_JAN8) { ok = false; }
  return assert(ok, "day-of-month OR weekday applies only when both are restricted");
}

fn t23() -> TestResult {
  var ok = next_is("0 0 2 * 4", _T_JAN1, _T_JAN2);
  if !next_is("0 0 15 * 4", _T_JAN1, _T_JAN8) { ok = false; }
  if !next_is("0 0 1 * 4", _T_JAN1, _T_JAN8) { ok = false; }
  if !next_is("0 0 15 * *", _T_JAN8, _T_JAN15) { ok = false; }
  return assert(ok, "next honors the day-or-weekday rule");
}

fn t24() -> TestResult {
  var ok = next_is("30 9 * * *", _T_JAN1, _T_0930);
  if !next_is("30 9 * * *", _T_0930, _T_JAN2_0930) { ok = false; }
  if !next_is("* * * * *", _T_JAN1, _T_JAN1 + 60) { ok = false; }
  if !next_is("0 0 * * *", _T_JAN1, _T_JAN2) { ok = false; }
  if !next_is("0 0 * * *", _T_JAN1 + 30, _T_JAN2) { ok = false; }
  return assert(ok, "next returns the strictly following matching minute");
}

fn t25() -> TestResult {
  var ok = next_is("0 0 1 * *", _T_JAN1, _T_FEB1);
  if !next_is("0 0 15 * *", _T_JAN1, _T_JAN15) { ok = false; }
  if !next_is("0 0 * 2 *", _T_JAN1, _T_FEB1) { ok = false; }
  if !next_is("0 0 1 3 *", _T_JAN1, _T_MAR1) { ok = false; }
  if !next_is("0 0 * * 4", _T_JAN1, _T_JAN8) { ok = false; }
  return assert(ok, "next crosses day, month and weekday boundaries");
}

fn t26() -> TestResult {
  var ok = next_is("0 0 29 2 *", _T_JAN1, _T_FEB29_2028);
  if !matches_at("0 0 29 2 *", _T_FEB29_2028) { ok = false; }
  if matches_at("0 0 29 2 *", _T_JAN1) { ok = false; }
  if !next_is("0 0 29 2 *", _T_FEB29_2028, 1961625600) { ok = false; }
  return assert(ok, "leap-day schedules scan across years");
}

fn t27() -> TestResult {
  var ok = next_err_is("0 0 30 2 *", _T_JAN1, "cron: no match within 4 years");
  if !next_err_is("0 0 31 4 *", _T_JAN1, "cron: no match within 4 years") { ok = false; }
  if next_err_is("0 0 1 1 *", _T_JAN1, "cron: no match within 4 years") { ok = false; }
  return assert(ok, "impossible dates fail with the 4-year scan error");
}

fn t28() -> TestResult {
  var ok = next_is("30 9 * * *", _T_JAN1, _T_0930);
  if !err_prefix("nope") { ok = false; }
  var bad = cron_parse_next("not a cron", 0);
  var prefixed = false;
  match bad {
    Ok(_) => { prefixed = false; },
    Err(e) => { prefixed = string.str_starts_with(e, "cron: "); },
  }
  if !prefixed { ok = false; }
  if !next_err_is("0 0 30 2 *", _T_JAN1, "cron: no match within 4 years") { ok = false; }
  return assert(ok, "cron_parse_next composes parse and next");
}

fn main() -> Int {
  io.println("=== xiom.scheduler conformance tests ===");
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.scheduler: all tests passed");
  } else {
    io.println("xiom.scheduler: tests failed");
  }
  return failed;
}
