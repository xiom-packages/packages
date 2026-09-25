// XIOM -- xiom.cron conformance tests (25 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the pure-XIOM xiom.cron module against its documented 5-field
// grammar, macro table, canonical emit/describe contract and error catalog.
// Str equality is routed through xiom.string.compare.str_compare (BUG 17:
// `==` on a Str read from a Vec[Str] element lowers to a pointer compare).
// Test functions are called directly from main; there is no Vec[fn] dispatch.

module cron_tests
use xiom.io; use xiom.test; use xiom.cron;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn t_err_is(expr: Str, want: Str) -> Bool {
  match cron_parse(expr) {
    Ok(c) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn t_count_is(expr: Str, field: Int, want: Int) -> Bool {
  match cron_parse(expr) {
    Ok(c) => { return cron_field_count(&c, field) == want; },
    Err(e) => { return false; },
  }
}

fn t_at_is(expr: Str, field: Int, i: Int, want: Int) -> Bool {
  match cron_parse(expr) {
    Ok(c) => { return cron_field_at(&c, field, i) == want; },
    Err(e) => { return false; },
  }
}

fn t_emit_is(expr: Str, want: Str) -> Bool {
  match cron_parse(expr) {
    Ok(c) => { return streq(cron_emit(&c), want); },
    Err(e) => { return false; },
  }
}

fn t_describe_is(expr: Str, want: Str) -> Bool {
  match cron_parse(expr) {
    Ok(c) => { return streq(cron_describe(&c), want); },
    Err(e) => { return false; },
  }
}

fn t_valid_is(expr: Str, want: Bool) -> Bool {
  return cron_valid(expr) == want;
}

fn t_expand_is(macro_name: Str, want: Str) -> Bool {
  match cron_expand_macro(macro_name) {
    Ok(s) => { return streq(s, want); },
    Err(e) => { return false; },
  }
}

fn t_expand_err_is(macro_name: Str, want: Str) -> Bool {
  match cron_expand_macro(macro_name) {
    Ok(s) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn t_fields_match(a: &CronExpr, b: &CronExpr, field: Int) -> Bool {
  let na = cron_field_count(a, field);
  if na != cron_field_count(b, field) { return false; }
  var i = 0;
  while i < na {
    let x: Int = cron_field_at(a, field, i);
    let y: Int = cron_field_at(b, field, i);
    if x != y { return false; }
    i = i + 1;
  }
  return true;
}

fn t_same_expr(a: Str, b: Str) -> Bool {
  let pa = cron_parse(a);
  match pa {
    Ok(ca) => {
      let pb = cron_parse(b);
      match pb {
        Ok(cb) => {
          var ok = true;
          var f = 0;
          while f < 5 {
            if !t_fields_match(&ca, &cb, f) { ok = false; }
            f = f + 1;
          }
          return ok;
        },
        Err(e) => { return false; },
      }
    },
    Err(e) => { return false; },
  }
}

fn t_roundtrip(expr: Str) -> Bool {
  let pa = cron_parse(expr);
  match pa {
    Ok(ca) => {
      let emitted = cron_emit(&ca);
      let pb = cron_parse(emitted);
      match pb {
        Ok(cb) => {
          var ok = true;
          var f = 0;
          while f < 5 {
            if !t_fields_match(&ca, &cb, f) { ok = false; }
            f = f + 1;
          }
          return ok;
        },
        Err(e) => { return false; },
      }
    },
    Err(e) => { return false; },
  }
}

fn t1() -> TestResult {
  var ok = t_count_is("* * * * *", 0, 60);
  if !t_count_is("* * * * *", 1, 24) { ok = false; }
  if !t_count_is("* * * * *", 2, 31) { ok = false; }
  if !t_count_is("* * * * *", 3, 12) { ok = false; }
  if !t_count_is("* * * * *", 4, 7) { ok = false; }
  if !t_at_is("* * * * *", 0, 0, 0) { ok = false; }
  if !t_at_is("* * * * *", 0, 59, 59) { ok = false; }
  if !t_at_is("* * * * *", 1, 23, 23) { ok = false; }
  if !t_at_is("* * * * *", 2, 0, 1) { ok = false; }
  if !t_at_is("* * * * *", 2, 30, 31) { ok = false; }
  if !t_at_is("* * * * *", 3, 11, 12) { ok = false; }
  if !t_at_is("* * * * *", 4, 6, 6) { ok = false; }
  return assert(ok, "wildcard: every field spans its full range");
}

fn t2() -> TestResult {
  var ok = t_count_is("0 12 1 1 0", 0, 1);
  if !t_count_is("0 12 1 1 0", 1, 1) { ok = false; }
  if !t_count_is("0 12 1 1 0", 2, 1) { ok = false; }
  if !t_count_is("0 12 1 1 0", 3, 1) { ok = false; }
  if !t_count_is("0 12 1 1 0", 4, 1) { ok = false; }
  if !t_at_is("0 12 1 1 0", 0, 0, 0) { ok = false; }
  if !t_at_is("0 12 1 1 0", 1, 0, 12) { ok = false; }
  if !t_at_is("0 12 1 1 0", 2, 0, 1) { ok = false; }
  if !t_at_is("0 12 1 1 0", 3, 0, 1) { ok = false; }
  if !t_at_is("0 12 1 1 0", 4, 0, 0) { ok = false; }
  return assert(ok, "single values: one entry per field, exact values");
}

fn t3() -> TestResult {
  var ok = t_count_is("1,2,3 20,21,22,23 * * *", 0, 3);
  if !t_at_is("1,2,3 20,21,22,23 * * *", 0, 0, 1) { ok = false; }
  if !t_at_is("1,2,3 20,21,22,23 * * *", 0, 2, 3) { ok = false; }
  if !t_count_is("1,2,3 20,21,22,23 * * *", 1, 4) { ok = false; }
  if !t_at_is("1,2,3 20,21,22,23 * * *", 1, 3, 23) { ok = false; }
  if !t_count_is("3,1,3,2 * * * *", 0, 3) { ok = false; }
  if !t_at_is("3,1,3,2 * * * *", 0, 0, 1) { ok = false; }
  if !t_at_is("3,1,3,2 * * * *", 0, 1, 2) { ok = false; }
  if !t_at_is("3,1,3,2 * * * *", 0, 2, 3) { ok = false; }
  if !t_at_is("59,0,30 * * * *", 0, 0, 0) { ok = false; }
  if !t_at_is("59,0,30 * * * *", 0, 1, 30) { ok = false; }
  if !t_at_is("59,0,30 * * * *", 0, 2, 59) { ok = false; }
  return assert(ok, "lists: sorted and duplicate-free");
}

fn t4() -> TestResult {
  var ok = t_count_is("10-15 0-4 1-3 6-8 *", 0, 6);
  if !t_at_is("10-15 0-4 1-3 6-8 *", 0, 0, 10) { ok = false; }
  if !t_at_is("10-15 0-4 1-3 6-8 *", 0, 5, 15) { ok = false; }
  if !t_count_is("10-15 0-4 1-3 6-8 *", 1, 5) { ok = false; }
  if !t_count_is("10-15 0-4 1-3 6-8 *", 2, 3) { ok = false; }
  if !t_count_is("10-15 0-4 1-3 6-8 *", 3, 3) { ok = false; }
  if !t_at_is("10-15 0-4 1-3 6-8 *", 3, 0, 6) { ok = false; }
  if !t_count_is("0-59 0-23 1-31 1-12 0-7", 0, 60) { ok = false; }
  if !t_count_is("0-59 0-23 1-31 1-12 0-7", 1, 24) { ok = false; }
  if !t_count_is("0-59 0-23 1-31 1-12 0-7", 2, 31) { ok = false; }
  if !t_count_is("0-59 0-23 1-31 1-12 0-7", 3, 12) { ok = false; }
  if !t_count_is("0-59 0-23 1-31 1-12 0-7", 4, 7) { ok = false; }
  if !t_count_is("5-5 * * * *", 0, 1) { ok = false; }
  if !t_at_is("5-5 * * * *", 0, 0, 5) { ok = false; }
  return assert(ok, "ranges: inclusive spans and explicit full ranges");
}

fn t5() -> TestResult {
  var ok = t_count_is("*/15 */6 */10 */3 */2", 0, 4);
  if !t_at_is("*/15 */6 */10 */3 */2", 0, 0, 0) { ok = false; }
  if !t_at_is("*/15 */6 */10 */3 */2", 0, 3, 45) { ok = false; }
  if !t_count_is("*/15 */6 */10 */3 */2", 1, 4) { ok = false; }
  if !t_at_is("*/15 */6 */10 */3 */2", 1, 1, 6) { ok = false; }
  if !t_at_is("*/15 */6 */10 */3 */2", 1, 3, 18) { ok = false; }
  if !t_count_is("*/15 */6 */10 */3 */2", 2, 4) { ok = false; }
  if !t_at_is("*/15 */6 */10 */3 */2", 2, 0, 1) { ok = false; }
  if !t_at_is("*/15 */6 */10 */3 */2", 2, 3, 31) { ok = false; }
  if !t_count_is("*/15 */6 */10 */3 */2", 3, 4) { ok = false; }
  if !t_at_is("*/15 */6 */10 */3 */2", 3, 0, 1) { ok = false; }
  if !t_at_is("*/15 */6 */10 */3 */2", 3, 3, 10) { ok = false; }
  if !t_count_is("*/15 */6 */10 */3 */2", 4, 4) { ok = false; }
  if !t_at_is("*/15 */6 */10 */3 */2", 4, 0, 0) { ok = false; }
  if !t_at_is("*/15 */6 */10 */3 */2", 4, 3, 6) { ok = false; }
  return assert(ok, "steps: */n starts at the field low bound");
}

fn t6() -> TestResult {
  var ok = t_count_is("1-10/3 5-23/6 * * 5-7/2", 0, 4);
  if !t_at_is("1-10/3 5-23/6 * * 5-7/2", 0, 0, 1) { ok = false; }
  if !t_at_is("1-10/3 5-23/6 * * 5-7/2", 0, 3, 10) { ok = false; }
  if !t_count_is("1-10/3 5-23/6 * * 5-7/2", 1, 4) { ok = false; }
  if !t_at_is("1-10/3 5-23/6 * * 5-7/2", 1, 0, 5) { ok = false; }
  if !t_at_is("1-10/3 5-23/6 * * 5-7/2", 1, 3, 23) { ok = false; }
  if !t_count_is("1-10/3 5-23/6 * * 5-7/2", 4, 2) { ok = false; }
  if !t_at_is("1-10/3 5-23/6 * * 5-7/2", 4, 0, 0) { ok = false; }
  if !t_at_is("1-10/3 5-23/6 * * 5-7/2", 4, 1, 5) { ok = false; }
  if !t_count_is("50-59/100 * * * *", 0, 1) { ok = false; }
  if !t_at_is("50-59/100 * * * *", 0, 0, 50) { ok = false; }
  if !t_count_is("*/100 * * * *", 0, 1) { ok = false; }
  if !t_at_is("*/100 * * * *", 0, 0, 0) { ok = false; }
  if !t_count_is("*/59 * * * *", 0, 2) { ok = false; }
  if !t_at_is("*/59 * * * *", 0, 1, 59) { ok = false; }
  return assert(ok, "range steps: a-b/n, oversized steps and the 7->0 wrap");
}

fn t7() -> TestResult {
  var ok = t_count_is("* * * JAN-DEC MON-FRI", 3, 12);
  if !t_count_is("* * * JAN-DEC MON-FRI", 4, 5) { ok = false; }
  if !t_at_is("* * * JAN-DEC MON-FRI", 4, 0, 1) { ok = false; }
  if !t_at_is("* * * JAN-DEC MON-FRI", 4, 4, 5) { ok = false; }
  if !t_count_is("* * * jan,JUL sun", 3, 2) { ok = false; }
  if !t_at_is("* * * jan,JUL sun", 3, 0, 1) { ok = false; }
  if !t_at_is("* * * jan,JUL sun", 3, 1, 7) { ok = false; }
  if !t_count_is("* * * jan,JUL sun", 4, 1) { ok = false; }
  if !t_at_is("* * * jan,JUL sun", 4, 0, 0) { ok = false; }
  if !t_count_is("* * * Sep *", 3, 1) { ok = false; }
  if !t_at_is("* * * Sep *", 3, 0, 9) { ok = false; }
  if !t_count_is("* * * * sat,sun", 4, 2) { ok = false; }
  if !t_at_is("* * * * sat,sun", 4, 0, 0) { ok = false; }
  if !t_at_is("* * * * sat,sun", 4, 1, 6) { ok = false; }
  return assert(ok, "names: JAN-DEC and SUN-SAT, case-insensitive");
}

fn t8() -> TestResult {
  var ok = t_count_is("* * * * 7", 4, 1);
  if !t_at_is("* * * * 7", 4, 0, 0) { ok = false; }
  if !t_count_is("* * * * 0,7", 4, 1) { ok = false; }
  if !t_at_is("* * * * 0,7", 4, 0, 0) { ok = false; }
  if !t_count_is("* * * * 5-7", 4, 3) { ok = false; }
  if !t_at_is("* * * * 5-7", 4, 0, 0) { ok = false; }
  if !t_at_is("* * * * 5-7", 4, 1, 5) { ok = false; }
  if !t_at_is("* * * * 5-7", 4, 2, 6) { ok = false; }
  if !t_count_is("* * * * 0-6", 4, 7) { ok = false; }
  if !t_count_is("* * * * 6-7", 4, 2) { ok = false; }
  if !t_at_is("* * * * 6-7", 4, 0, 0) { ok = false; }
  if !t_at_is("* * * * 6-7", 4, 1, 6) { ok = false; }
  return assert(ok, "day-of-week: 7 normalizes to Sunday 0");
}

fn t9() -> TestResult {
  var ok = t_count_is("@hourly", 0, 1);
  if !t_at_is("@hourly", 0, 0, 0) { ok = false; }
  if !t_count_is("@hourly", 1, 24) { ok = false; }
  if !t_count_is("@hourly", 2, 31) { ok = false; }
  if !t_count_is("@daily", 1, 1) { ok = false; }
  if !t_at_is("@daily", 1, 0, 0) { ok = false; }
  if !t_count_is("@daily", 2, 31) { ok = false; }
  if !t_count_is("@weekly", 4, 1) { ok = false; }
  if !t_at_is("@weekly", 4, 0, 0) { ok = false; }
  if !t_count_is("@monthly", 2, 1) { ok = false; }
  if !t_at_is("@monthly", 2, 0, 1) { ok = false; }
  if !t_count_is("@monthly", 4, 7) { ok = false; }
  if !t_count_is("@yearly", 3, 1) { ok = false; }
  if !t_at_is("@yearly", 3, 0, 1) { ok = false; }
  if !t_count_is("@annually", 2, 1) { ok = false; }
  return assert(ok, "macros: @hourly @daily @weekly @monthly @yearly @annually");
}

fn t10() -> TestResult {
  var ok = t_expand_is("@hourly", "0 * * * *");
  if !t_expand_is("@daily", "0 0 * * *") { ok = false; }
  if !t_expand_is("@midnight", "0 0 * * *") { ok = false; }
  if !t_expand_is("@weekly", "0 0 * * 0") { ok = false; }
  if !t_expand_is("@monthly", "0 0 1 * *") { ok = false; }
  if !t_expand_is("@yearly", "0 0 1 1 *") { ok = false; }
  if !t_expand_is("@annually", "0 0 1 1 *") { ok = false; }
  if !t_expand_err_is("@foo", "cron: bad macro: @foo") { ok = false; }
  if !t_expand_err_is("@DAILY", "cron: bad macro: @DAILY") { ok = false; }
  if !t_expand_err_is("hourly", "cron: bad macro: hourly") { ok = false; }
  if !t_expand_err_is("", "cron: bad macro: ") { ok = false; }
  return assert(ok, "macro expansion: canonical text and bad-macro errors");
}

fn t11() -> TestResult {
  var ok = t_same_expr("@hourly", "0 * * * *");
  if !t_same_expr("@daily", "0 0 * * *") { ok = false; }
  if !t_same_expr("@midnight", "0 0 * * *") { ok = false; }
  if !t_same_expr("@weekly", "0 0 * * 0") { ok = false; }
  if !t_same_expr("@monthly", "0 0 1 * *") { ok = false; }
  if !t_same_expr("@yearly", "0 0 1 1 *") { ok = false; }
  if !t_same_expr("@annually", "0 0 1 1 *") { ok = false; }
  return assert(ok, "macros: equivalent to their five-field expansions");
}

fn t12() -> TestResult {
  var ok = t_emit_is("30,0 9-17 * * MON-FRI", "0,30 9-17 * * 1-5");
  if !t_emit_is("*/15 * * * *", "0,15,30,45 * * * *") { ok = false; }
  if !t_emit_is("@yearly", "0 0 1 1 *") { ok = false; }
  if !t_emit_is("0-59 0-23 1-31 1-12 0-7", "* * * * *") { ok = false; }
  if !t_emit_is("07 * * * *", "7 * * * *") { ok = false; }
  if !t_emit_is("59,0,30 0 * * *", "0,30,59 0 * * *") { ok = false; }
  if !t_emit_is("* * * * 6,0", "* * * * 0,6") { ok = false; }
  if !t_emit_is("* * * * 7", "* * * * 0") { ok = false; }
  if !t_emit_is("1,2,3,4,5 * * * *", "1-5 * * * *") { ok = false; }
  if !t_emit_is("1,2,4,5 * * * *", "1-2,4-5 * * * *") { ok = false; }
  return assert(ok, "emit: canonical text, runs as a-b, full fields as *");
}

fn t13() -> TestResult {
  var ok = t_roundtrip("* * * * *");
  if !t_roundtrip("0 0 1 1 *") { ok = false; }
  if !t_roundtrip("*/15 */6 */10 */3 */2") { ok = false; }
  if !t_roundtrip("0,30 9-17 * * MON-FRI") { ok = false; }
  if !t_roundtrip("@weekly") { ok = false; }
  if !t_roundtrip("3,1,2 1-4/2 * JAN,JUL 7") { ok = false; }
  if !t_roundtrip("59 23 31 12 6") { ok = false; }
  if !t_roundtrip("1-10/3 5-23/6 2,15 2,11 SUN,SAT") { ok = false; }
  return assert(ok, "round-trip: parse(emit(parse(x))) preserves every field");
}

fn t14() -> TestResult {
  var ok = t_describe_is("* * * * *", "minute *; hour *; day-of-month *; month *; day-of-week *");
  if !t_describe_is("0,30 9-17 1,15 * MON-FRI", "minute 0,30; hour 9-17; day-of-month 1,15; month *; day-of-week MON-FRI") { ok = false; }
  if !t_describe_is("@yearly", "minute 0; hour 0; day-of-month 1; month JAN; day-of-week *") { ok = false; }
  if !t_describe_is("* * * 3,6,9 *", "minute *; hour *; day-of-month *; month MAR,JUN,SEP; day-of-week *") { ok = false; }
  if !t_describe_is("* * * * 1,2,3,4,5", "minute *; hour *; day-of-month *; month *; day-of-week MON-FRI") { ok = false; }
  return assert(ok, "describe: labelled summary with names for month and dow");
}

fn t15() -> TestResult {
  var ok = t_err_is("", "cron: empty expression");
  if !t_err_is("   ", "cron: empty expression") { ok = false; }
  if !t_err_is(" \t \r\n ", "cron: empty expression") { ok = false; }
  return assert(ok, "errors: empty and whitespace-only expressions");
}

fn t16() -> TestResult {
  var ok = t_err_is("* * *", "cron: expected 5 fields, got 3");
  if !t_err_is("* * * *", "cron: expected 5 fields, got 4") { ok = false; }
  if !t_err_is("* * * * * *", "cron: expected 5 fields, got 6") { ok = false; }
  if !t_err_is("*", "cron: expected 5 fields, got 1") { ok = false; }
  return assert(ok, "errors: wrong field count names the actual count");
}

fn t17() -> TestResult {
  var ok = t_err_is("60 * * * *", "cron: value out of range: 60 in minute");
  if !t_err_is("* 24 * * *", "cron: value out of range: 24 in hour") { ok = false; }
  if !t_err_is("* * 0 * *", "cron: value out of range: 0 in day-of-month") { ok = false; }
  if !t_err_is("* * 32 * *", "cron: value out of range: 32 in day-of-month") { ok = false; }
  if !t_err_is("* * * 0 *", "cron: value out of range: 0 in month") { ok = false; }
  if !t_err_is("* * * 13 *", "cron: value out of range: 13 in month") { ok = false; }
  if !t_err_is("* * * * 8", "cron: value out of range: 8 in day-of-week") { ok = false; }
  if !t_err_is("1-99 * * * *", "cron: value out of range: 99 in minute") { ok = false; }
  if !t_err_is("999999999999 * * * *", "cron: value out of range: 999999999999 in minute") { ok = false; }
  return assert(ok, "errors: numeric values outside the field bounds");
}

fn t18() -> TestResult {
  var ok = t_err_is("x * * * *", "cron: unknown value: x in minute");
  if !t_err_is("* * * JANUARY *", "cron: unknown value: JANUARY in month") { ok = false; }
  if !t_err_is("* * * * MONDAY", "cron: unknown value: MONDAY in day-of-week") { ok = false; }
  if !t_err_is("* * * SUN *", "cron: unknown value: SUN in month") { ok = false; }
  if !t_err_is("* * FOO * *", "cron: unknown value: FOO in day-of-month") { ok = false; }
  if !t_err_is("* * * 12A *", "cron: unknown value: 12A in month") { ok = false; }
  if !t_err_is("* * * * * *", "cron: expected 5 fields, got 6") { ok = false; }
  return assert(ok, "errors: unknown value tokens name the token and field");
}

fn t19() -> TestResult {
  var ok = t_err_is("*/0 * * * *", "cron: step must be > 0 in minute");
  if !t_err_is("1-5/0 * * * *", "cron: step must be > 0 in minute") { ok = false; }
  if !t_err_is("* * * * */0", "cron: step must be > 0 in day-of-week") { ok = false; }
  if !t_err_is("*/x * * * *", "cron: bad step: x in minute") { ok = false; }
  if !t_err_is("*/ * * * *", "cron: bad step in minute") { ok = false; }
  if !t_err_is("1-5/ * * * *", "cron: bad step in minute") { ok = false; }
  if !t_err_is("*/2x * * * *", "cron: bad step: 2x in minute") { ok = false; }
  return assert(ok, "errors: step zero, missing step and non-digit step");
}

fn t20() -> TestResult {
  var ok = t_err_is("1-2-3 * * * *", "cron: bad token: 1-2-3 in minute");
  if !t_err_is("5/2 * * * *", "cron: bad token: 5/2 in minute") { ok = false; }
  if !t_err_is("-5 * * * *", "cron: bad token: -5 in minute") { ok = false; }
  if !t_err_is("5- * * * *", "cron: bad token: 5- in minute") { ok = false; }
  if !t_err_is("*/2/3 * * * *", "cron: bad token: */2/3 in minute") { ok = false; }
  if !t_err_is("* * * * MON-", "cron: bad token: MON- in day-of-week") { ok = false; }
  if !t_err_is("* * * * -FRI", "cron: bad token: -FRI in day-of-week") { ok = false; }
  return assert(ok, "errors: malformed item shapes are bad tokens");
}

fn t21() -> TestResult {
  var ok = t_err_is("5-1 * * * *", "cron: range start > end: 5-1 in minute");
  if !t_err_is("* * 20-5 * *", "cron: range start > end: 20-5 in day-of-month") { ok = false; }
  if !t_err_is("* * * JUL-JAN *", "cron: range start > end: JUL-JAN in month") { ok = false; }
  if !t_count_is("5-5 * * * *", 0, 1) { ok = false; }
  if !t_at_is("5-5 * * * *", 0, 0, 5) { ok = false; }
  if !t_count_is("* * * * MON-MON", 4, 1) { ok = false; }
  if !t_at_is("* * * * MON-MON", 4, 0, 1) { ok = false; }
  return assert(ok, "errors: reversed ranges are rejected, equal ends accepted");
}

fn t22() -> TestResult {
  var ok = t_err_is("1,,2 * * * *", "cron: empty list item in minute");
  if !t_err_is(",1 * * * *", "cron: empty list item in minute") { ok = false; }
  if !t_err_is("1, * * * *", "cron: empty list item in minute") { ok = false; }
  if !t_err_is("1,2, * * * *", "cron: empty list item in minute") { ok = false; }
  return assert(ok, "errors: empty list items are named per field");
}

fn t23() -> TestResult {
  var ok = t_count_is("* * * * *", 9, 0);
  let r = cron_parse("0 12 1 1 0");
  match r {
    Ok(c) => {
      if cron_field_at(&c, 0, -1) != -1 { ok = false; }
      if cron_field_at(&c, 0, 1) != -1 { ok = false; }
      if cron_field_count(&c, CRON_FIELD_HOUR) != 1 { ok = false; }
      if cron_hour_at(&c, 0) != 12 { ok = false; }
      if cron_minute_count(&c) != 1 { ok = false; }
      if cron_day_at(&c, 0) != 1 { ok = false; }
      if cron_month_at(&c, 0) != 1 { ok = false; }
      if cron_dow_at(&c, 0) != 0 { ok = false; }
      if !streq(cron_field_name(CRON_FIELD_DAY), "day-of-month") { ok = false; }
      if !streq(cron_field_name(9), "") { ok = false; }
    },
    Err(e) => { ok = false; },
  }
  return assert(ok, "accessors: counts, bounds, field names and constants");
}

fn t24() -> TestResult {
  var ok = t_valid_is("* * * * *", true);
  if !t_valid_is("@daily", true) { ok = false; }
  if !t_valid_is("@midnight", true) { ok = false; }
  if !t_valid_is("0 0 1 1 MON", true) { ok = false; }
  if !t_valid_is("", false) { ok = false; }
  if !t_valid_is("   ", false) { ok = false; }
  if !t_valid_is("60 * * * *", false) { ok = false; }
  if !t_valid_is("* * * * * *", false) { ok = false; }
  if !t_valid_is("@nope", false) { ok = false; }
  return assert(ok, "cron_valid: true exactly when cron_parse succeeds");
}

fn t25() -> TestResult {
  var ok = t_count_is("  0   0  * * *  ", 0, 1);
  if !t_at_is("  0   0  * * *  ", 0, 0, 0) { ok = false; }
  if !t_count_is("0\t0\t*\t*\t*", 1, 1) { ok = false; }
  if !t_count_is("0\n0\n*\n*\n*", 2, 31) { ok = false; }
  if !t_count_is("0\r\n0\r\n*\r\n*\r\n*", 3, 12) { ok = false; }
  if !t_count_is("07,007 * * * *", 0, 1) { ok = false; }
  if !t_at_is("07,007 * * * *", 0, 0, 7) { ok = false; }
  if !t_emit_is("07 08 09 010 06", "7 8 9 10 6") { ok = false; }
  return assert(ok, "whitespace: separators trimmed, leading zeros accepted");
}

fn main() -> Int {
  io.println("=== xiom.cron conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.cron: all tests passed");
  } else {
    io.println("xiom.cron: tests failed");
  }
  return failed;
}
