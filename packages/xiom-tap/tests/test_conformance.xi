// XIOM -- xiom.tap conformance tests (24 checks)
// Greenfield package: prove the pure-XIOM xiom.tap module against the
// documented TAP subset, its error catalog and its canonical emitter.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: version/plan/results happy path, SKIP/TODO directives in mixed
// case, comments and diagnostics, blank lines and CRLF, plan-last streams,
// "1..0", streams without a plan, Bail out! (with and without reason, parse
// stopping), every error catalog entry (bad plan, duplicate plan, plan after
// tests, non-sequential and negative numbers, bad directive, text before
// plan, unrecognized line, bad/misplaced version line, YAML block), the
// canonical line writers, description/directive boundary rules, accessor
// bounds, the builder API and full round trips.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq/test_is/doc_equal instead of `==`.

module tap_tests
use xiom.io; use xiom.test; use xiom.tap;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when result `i` of `d` has exactly the wanted shape.
fn test_is(d: &TapDoc, i: Int, number: Int, verdict: Bool, desc: Str, dir: Str, reason: Str) -> Bool {
  if tap_number(d, i) != number { return false; }
  if tap_is_ok(d, i) != verdict { return false; }
  if !streq(tap_description(d, i), desc) { return false; }
  if !streq(tap_directive(d, i), dir) { return false; }
  if !streq(tap_reason(d, i), reason) { return false; }
  return true;
}

// True when `text` fails to parse with exactly the message `want`.
fn err_is(text: Str, want: Str) -> Bool {
  let r = tap_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Structural equality of two parsed documents.
fn doc_equal(a: &TapDoc, b: &TapDoc) -> Bool {
  if tap_version(a) != tap_version(b) { return false; }
  if tap_planned(a) != tap_planned(b) { return false; }
  if tap_bailed(a) != tap_bailed(b) { return false; }
  if !streq(tap_bail_reason(a), tap_bail_reason(b)) { return false; }
  if tap_test_count(a) != tap_test_count(b) { return false; }
  if tap_diagnostic_count(a) != tap_diagnostic_count(b) { return false; }
  var i = 0;
  while i < tap_test_count(a) {
    if tap_number(a, i) != tap_number(b, i) { return false; }
    if tap_is_ok(a, i) != tap_is_ok(b, i) { return false; }
    if !streq(tap_description(a, i), tap_description(b, i)) { return false; }
    if !streq(tap_directive(a, i), tap_directive(b, i)) { return false; }
    if !streq(tap_reason(a, i), tap_reason(b, i)) { return false; }
    i = i + 1;
  }
  i = 0;
  while i < tap_diagnostic_count(a) {
    if !streq(tap_diagnostic(a, i), tap_diagnostic(b, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// parse -> emit -> parse is structure-preserving and emit is idempotent.
fn round_trip(text: Str) -> Bool {
  let r1 = tap_parse(text);
  match r1 {
    Ok(d1) => {
      let once = tap_emit(&d1);
      let r2 = tap_parse(once);
      match r2 {
        Ok(d2) => {
          if !doc_equal(&d1, &d2) { return false; }
          let twice = tap_emit(&d2);
          return streq(once, twice);
        },
        Err(_) => { return false; },
      }
    },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  let r = tap_parse("TAP version 13\n1..3\nok 1 first\nnot ok 2 second\nok 3 third\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = tap_version(&d) == 13;
      if tap_planned(&d) != 3 { ok = false; }
      if tap_test_count(&d) != 3 { ok = false; }
      if !test_is(&d, 0, 1, true, "first", "", "") { ok = false; }
      if !test_is(&d, 1, 2, false, "second", "", "") { ok = false; }
      if !test_is(&d, 2, 3, true, "third", "", "") { ok = false; }
      if tap_passed(&d) != 2 { ok = false; }
      if tap_failed(&d) != 1 { ok = false; }
      if tap_skipped(&d) != 0 { ok = false; }
      if tap_todo(&d) != 0 { ok = false; }
      if tap_bailed(&d) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "version, plan and flat results parse with summary counts");
}

fn t2() -> TestResult {
  let r = tap_parse("1..4\nok 1 plain\nok 2 later # SKIP not ready\nnot ok 3 broken # TODO fix it\nok 4 passed # todo unplanned win\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = test_is(&d, 0, 1, true, "plain", "", "");
      if !test_is(&d, 1, 2, true, "later", "skip", "not ready") { ok = false; }
      if !test_is(&d, 2, 3, false, "broken", "todo", "fix it") { ok = false; }
      if !test_is(&d, 3, 4, true, "passed", "todo", "unplanned win") { ok = false; }
      if tap_passed(&d) != 1 { ok = false; }
      if tap_failed(&d) != 0 { ok = false; }
      if tap_skipped(&d) != 1 { ok = false; }
      if tap_todo(&d) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "SKIP and TODO directives are case-insensitive and summarized");
}

fn t3() -> TestResult {
  let r = tap_parse("# stream note\n1..2\n# before ok\nok 1 a\n#\nnot ok 2 b\n# after\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = tap_diagnostic_count(&d) == 4;
      if !streq(tap_diagnostic(&d, 0), "stream note") { ok = false; }
      if !streq(tap_diagnostic(&d, 1), "before ok") { ok = false; }
      if !streq(tap_diagnostic(&d, 2), "") { ok = false; }
      if !streq(tap_diagnostic(&d, 3), "after") { ok = false; }
      if tap_test_count(&d) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "comment lines are captured raw as diagnostics");
}

fn t4() -> TestResult {
  let r = tap_parse("  TAP version 13  \r\n\r\n1..2\r\n\tok 1  spaced out  \r\nnot ok 2\tsecond\r\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = tap_version(&d) == 13;
      if tap_planned(&d) != 2 { ok = false; }
      if !test_is(&d, 0, 1, true, "spaced out", "", "") { ok = false; }
      if !test_is(&d, 1, 2, false, "second", "", "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF, blank lines and surrounding whitespace are tolerated");
}

fn t5() -> TestResult {
  let r = tap_parse("ok 1 a\nok 2 b\n1..2");
  var ok = false;
  match r {
    Ok(d) => {
      ok = tap_planned(&d) == 2;
      if tap_test_count(&d) != 2 { ok = false; }
      if !streq(tap_emit(&d), "1..2\nok 1 a\nok 2 b\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a plan after the last test parses and emits first");
}

fn t6() -> TestResult {
  let r = tap_parse("1..0\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = tap_planned(&d) == 0;
      if tap_test_count(&d) != 0 { ok = false; }
      if !streq(tap_emit(&d), "1..0\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "the 1..0 plan is valid and reports zero planned tests");
}

fn t7() -> TestResult {
  let r = tap_parse("ok 1 lone\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = tap_planned(&d) == -1;
      if tap_test_count(&d) != 1 { ok = false; }
      if !streq(tap_emit(&d), "ok 1 lone\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a stream without a plan reports planned = -1");
}

fn t8() -> TestResult {
  let r = tap_parse("1..5\nok 1 a\nBail out! disk full\nok 2 b\n---\n# not seen\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = tap_bailed(&d);
      if !streq(tap_bail_reason(&d), "disk full") { ok = false; }
      if tap_test_count(&d) != 1 { ok = false; }
      if tap_planned(&d) != 5 { ok = false; }
      if tap_diagnostic_count(&d) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "Bail out! stops the parse and records its reason");
}

fn t9() -> TestResult {
  let r = tap_parse("Bail out!");
  var ok = false;
  match r {
    Ok(d) => {
      ok = tap_bailed(&d);
      if !streq(tap_bail_reason(&d), "") { ok = false; }
      if tap_test_count(&d) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a bare Bail out! line has an empty reason");
}

fn t10() -> TestResult {
  var ok = err_is("1..x", "tap: bad plan at 1");
  if !err_is("1..-1", "tap: bad plan at 1") { ok = false; }
  if !err_is("0..2", "tap: bad plan at 1") { ok = false; }
  if !err_is("2..5", "tap: bad plan at 1") { ok = false; }
  if !err_is("1..", "tap: bad plan at 1") { ok = false; }
  if !err_is("1..2..3", "tap: bad plan at 1") { ok = false; }
  if !err_is("1..99999999999999999999", "tap: bad plan at 1") { ok = false; }
  return assert(ok, "malformed plan lines are Err with the line number");
}

fn t11() -> TestResult {
  var ok = err_is("1..1\n1..1", "tap: duplicate plan at 2");
  if !err_is("1..0\n1..0\n", "tap: duplicate plan at 2") { ok = false; }
  return assert(ok, "a second plan line is Err");
}

fn t12() -> TestResult {
  var ok = err_is("ok 1 a\n1..2\nok 2 b", "tap: plan after tests at 2");
  if !err_is("ok 1 a\nok 2 b\n1..2\nok 3 c", "tap: plan after tests at 3") { ok = false; }
  if !round_trip("ok 1 a\n1..1") { ok = false; }
  return assert(ok, "a plan between tests is Err; plan-last is accepted");
}

fn t13() -> TestResult {
  var ok = err_is("ok 2 a", "tap: non-sequential test number at 1: got 2, expected 1");
  if !err_is("1..3\nok 1 a\nok 3 b", "tap: non-sequential test number at 3: got 3, expected 2") { ok = false; }
  if !err_is("1..1\nok 0 a", "tap: non-sequential test number at 2: got 0, expected 1") { ok = false; }
  return assert(ok, "test numbers must be sequential from 1 in stream order");
}

fn t14() -> TestResult {
  var ok = err_is("ok -1 x", "tap: negative test number at 1");
  if !err_is("1..2\nnot ok -2 x", "tap: negative test number at 2") { ok = false; }
  return assert(ok, "a leading minus is Err, not a wrapped number");
}

fn t15() -> TestResult {
  var ok = err_is("1..1\nok 1 x # nope", "tap: bad directive at 2");
  if !err_is("1..1\nok 1 x #", "tap: bad directive at 2") { ok = false; }
  if !err_is("1..1\nok 1 x # TODO(y)", "tap: bad directive at 2") { ok = false; }
  return assert(ok, "only SKIP and TODO open a valid directive");
}

fn t16() -> TestResult {
  var ok = err_is("hello\n1..1", "tap: text before plan at 1");
  if !err_is("1..1\nhello", "tap: unrecognized line at 2") { ok = false; }
  if !err_is("1..1\nok 1 a\nok", "tap: bad test line at 3") { ok = false; }
  if !round_trip("# comment first\n1..1") { ok = false; }
  return assert(ok, "text before the plan and unknown lines after it are Err");
}

fn t17() -> TestResult {
  var ok = err_is("TAP version x\n1..1", "tap: bad version line at 1");
  if !err_is("TAP version 0\n", "tap: bad version line at 1") { ok = false; }
  if !err_is("1..1\nTAP version 13", "tap: misplaced version line at 2") { ok = false; }
  if !err_is("# c\nTAP version 13", "tap: misplaced version line at 2") { ok = false; }
  if !err_is("TAP versioning 13\n", "tap: text before plan at 1") { ok = false; }
  return assert(ok, "the version line must be the first non-blank line");
}

fn t18() -> TestResult {
  var ok = err_is("1..1\nok 1\n  ---\n  message: hi\n  ...", "tap: yaml diagnostics unsupported at 3");
  if !err_is("1..1\nok 1\n...", "tap: yaml diagnostics unsupported at 3") { ok = false; }
  if !err_is("---\n1..1", "tap: yaml diagnostics unsupported at 1") { ok = false; }
  return assert(ok, "YAML diagnostic blocks are rejected, not parsed");
}

fn t19() -> TestResult {
  var ok = round_trip("TAP version 13\n# diagnostic one\n1..4\nok 1 passes\nnot ok 2 fails # TODO fix later\nok 3 skipped thing # SKIP not ready\nnot ok 4 # SKIP\n");
  if !round_trip("1..2\nok 1 a\nnot ok 2 b\n") { ok = false; }
  if !round_trip("ok 1 a\nok 2 b\n1..2\n") { ok = false; }
  if !round_trip("TAP version 13\n# only a note\n") { ok = false; }
  if !round_trip("1..1\nok 1 a\nBail out! gone\n") { ok = false; }
  if !round_trip("1..0\n") { ok = false; }
  if !round_trip("1..2\nok 1\nok 2 note # SKIP see #4\n") { ok = false; }
  return assert(ok, "round trip preserves the parsed structure and is idempotent");
}

fn t20() -> TestResult {
  var ok = streq(tap_write_version(13), "TAP version 13");
  if !streq(tap_write_version(0), "") { ok = false; }
  if !streq(tap_write_version(-2), "") { ok = false; }
  if !streq(tap_write_plan(0), "1..0") { ok = false; }
  if !streq(tap_write_plan(4), "1..4") { ok = false; }
  if !streq(tap_write_plan(-1), "") { ok = false; }
  if !streq(tap_write_test(1, true, "passes", "", ""), "ok 1 passes") { ok = false; }
  if !streq(tap_write_test(2, false, "", "", ""), "not ok 2") { ok = false; }
  if !streq(tap_write_test(3, true, "skip me", "SKIP", "not ready"), "ok 3 skip me # SKIP not ready") { ok = false; }
  if !streq(tap_write_test(4, false, "later", "todo", "fix"), "not ok 4 later # TODO fix") { ok = false; }
  if !streq(tap_write_test(5, true, "x", "unknown", "y"), "ok 5 x # unknown y") { ok = false; }
  if !streq(tap_write_comment("hi"), "# hi") { ok = false; }
  if !streq(tap_write_comment(""), "#") { ok = false; }
  if !streq(tap_write_bail("boom"), "Bail out! boom") { ok = false; }
  if !streq(tap_write_bail(""), "Bail out!") { ok = false; }
  return assert(ok, "canonical line writers format every line kind");
}

fn t21() -> TestResult {
  let r = tap_parse("1..2\nok 1 issue#42 fixed\nnot ok 2 # SKIP\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = test_is(&d, 0, 1, true, "issue#42 fixed", "", "");
      if !test_is(&d, 1, 2, false, "", "skip", "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = tap_parse("1..2\nok 1 abc   def  \nok 2  x # todo later  \n");
  var ok2 = false;
  match r2 {
    Ok(d) => {
      ok2 = test_is(&d, 0, 1, true, "abc   def", "", "");
      if !test_is(&d, 1, 2, true, "x", "todo", "later") { ok2 = false; }
    },
    Err(_) => { ok2 = false; },
  }
  let r3 = tap_parse("1..3\nok 1\nnot ok 2 # SKIP see #4\nok 03 #skip trailing\n");
  var ok3 = false;
  match r3 {
    Ok(d) => {
      ok3 = test_is(&d, 0, 1, true, "", "", "");
      if !test_is(&d, 1, 2, false, "", "skip", "see #4") { ok3 = false; }
      if !test_is(&d, 2, 3, true, "", "skip", "trailing") { ok3 = false; }
    },
    Err(_) => { ok3 = false; },
  }
  return assert(ok && ok2 && ok3, "hash boundaries and whitespace trimming in descriptions");
}

fn t22() -> TestResult {
  let r = tap_parse("1..1\nok 1 a\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = tap_number(&d, 0) == 1;
      if tap_number(&d, -1) != -1 { ok = false; }
      if tap_number(&d, 1) != -1 { ok = false; }
      if tap_is_ok(&d, 9) { ok = false; }
      if !streq(tap_description(&d, 9), "") { ok = false; }
      if !streq(tap_directive(&d, -5), "") { ok = false; }
      if !streq(tap_reason(&d, 4), "") { ok = false; }
      if !streq(tap_diagnostic(&d, 0), "") { ok = false; }
      if tap_test_count(&d) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "accessors are bounds-safe and return empty sentinels");
}

fn t23() -> TestResult {
  var d = tap_doc_new();
  tap_set_version(&mut d, 13);
  tap_set_plan(&mut d, 2);
  tap_add_diagnostic(&mut d, "built by xiom.tap");
  tap_add_test(&mut d, true, "first", "", "");
  tap_add_test(&mut d, false, "second", "TODO", "later");
  tap_set_bail(&mut d, "stop");
  let wanted = "TAP version 13\n# built by xiom.tap\n1..2\nok 1 first\nnot ok 2 second # TODO later\nBail out! stop\n";
  var ok = streq(tap_emit(&d), wanted);
  if tap_test_count(&d) != 2 { ok = false; }
  if !streq(tap_directive(&d, 1), "todo") { ok = false; }
  if !round_trip(wanted) { ok = false; }
  return assert(ok, "the builder API and tap_emit produce canonical TAP");
}

fn t24() -> TestResult {
  let r = tap_parse("");
  var ok = false;
  match r {
    Ok(d) => {
      ok = tap_version(&d) == 0;
      if tap_planned(&d) != -1 { ok = false; }
      if tap_test_count(&d) != 0 { ok = false; }
      if tap_diagnostic_count(&d) != 0 { ok = false; }
      if tap_bailed(&d) { ok = false; }
      if !streq(tap_emit(&d), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = tap_parse("\n \n\t\n");
  var ok2 = false;
  match r2 {
    Ok(d) => { ok2 = tap_test_count(&d) == 0 && tap_planned(&d) == -1; },
    Err(_) => { ok2 = false; },
  }
  return assert(ok && ok2, "empty and blank-only streams parse to an empty document");
}

fn main() -> Int {
  io.println("=== xiom.tap conformance tests ===");
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
    io.println("xiom.tap: all tests passed");
  } else {
    io.println("xiom.tap: tests failed");
  }
  return failed;
}
