// XIOM -- xiom.alerting conformance tests (21 checks)
// Port task: prove the pure-XIOM xiom.alerting module against its documented state machine.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module alerting_tests
use xiom.io; use xiom.test; use xiom.alerting;

// Read-only operations are wrapped in small helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001). Each helper calls the real `&`-based API.

fn firing_of(s: &mut AlertState) -> Bool {
  return alert_is_firing(s);
}

fn fired_of(s: &mut AlertState) -> Int {
  return alert_fired_count(s);
}

fn resolved_of(s: &mut AlertState) -> Int {
  return alert_resolved_count(s);
}

fn breaches_of(s: &mut AlertState) -> Int {
  return alert_breaches(s);
}

fn observe(r: &AlertRule, s: &mut AlertState, v: Int) -> Bool {
  return alert_observe(r, s, v);
}

// Builders keep every bound Vec construction local to one function body.

fn series_5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a); v.push(b); v.push(c); v.push(d); v.push(e);
  return v;
}

fn series_7(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a); v.push(b); v.push(c); v.push(d); v.push(e); v.push(f); v.push(g);
  return v;
}

fn series_repeat(value: Int, n: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < n {
    v.push(value);
    i = i + 1;
  }
  return v;
}

fn t1() -> TestResult {
  let r = alert_rule_new(10, true, 4);
  var ok = r.threshold == 10;
  if !r.above { ok = false; }
  if r.consecutive != 4 { ok = false; }
  return assert(ok, "rule_new stores threshold, direction and streak");
}

fn t2() -> TestResult {
  let zero = alert_rule_new(5, false, 0);
  let neg = alert_rule_new(5, false, -7);
  var ok = zero.consecutive == 1;
  if neg.consecutive != 1 { ok = false; }
  if zero.threshold != 5 { ok = false; }
  if zero.above { ok = false; }
  return assert(ok, "rule_new clamps consecutive 0 and -7 to 1");
}

fn t3() -> TestResult {
  var st = alert_state_new();
  var ok = !firing_of(&mut st);
  if fired_of(&mut st) != 0 { ok = false; }
  if resolved_of(&mut st) != 0 { ok = false; }
  if breaches_of(&mut st) != 0 { ok = false; }
  return assert(ok, "state_new starts clear with zero counters");
}

fn t4() -> TestResult {
  let r = alert_rule_new(10, true, 1);
  var st = alert_state_new();
  let e1 = observe(&r, &mut st, 10);
  let e2 = observe(&r, &mut st, 11);
  var ok = e1;
  if e2 { ok = false; }
  if fired_of(&mut st) != 1 { ok = false; }
  if !firing_of(&mut st) { ok = false; }
  if breaches_of(&mut st) != 2 { ok = false; }
  return assert(ok, "consecutive=1 fires on the first breach, edge returned once");
}

fn t5() -> TestResult {
  let r = alert_rule_new(10, true, 3);
  var st = alert_state_new();
  let e1 = observe(&r, &mut st, 10);
  let e2 = observe(&r, &mut st, 10);
  let e3 = observe(&r, &mut st, 10);
  let e4 = observe(&r, &mut st, 10);
  var ok = !e1;
  if e2 { ok = false; }
  if !e3 { ok = false; }
  if e4 { ok = false; }
  if fired_of(&mut st) != 1 { ok = false; }
  if breaches_of(&mut st) != 4 { ok = false; }
  if !firing_of(&mut st) { ok = false; }
  return assert(ok, "consecutive=3 fires exactly on the third breach");
}

fn t6() -> TestResult {
  let r = alert_rule_new(10, true, 3);
  var st = alert_state_new();
  let e1 = observe(&r, &mut st, 12);
  let e2 = observe(&r, &mut st, 12);
  let e3 = observe(&r, &mut st, 4);
  let e4 = observe(&r, &mut st, 12);
  let e5 = observe(&r, &mut st, 12);
  var ok = !e1;
  if e2 { ok = false; }
  if e3 { ok = false; }
  if e4 { ok = false; }
  if e5 { ok = false; }
  if breaches_of(&mut st) != 2 { ok = false; }
  if fired_of(&mut st) != 0 { ok = false; }
  if firing_of(&mut st) { ok = false; }
  return assert(ok, "non-breach resets the streak before it can fire");
}

fn t7() -> TestResult {
  let r = alert_rule_new(10, true, 1);
  var st = alert_state_new();
  let e1 = observe(&r, &mut st, 10);
  let e2 = observe(&r, &mut st, 9);
  let e3 = observe(&r, &mut st, 9);
  let e4 = observe(&r, &mut st, 8);
  var ok = e1;
  if e2 { ok = false; }
  if e3 { ok = false; }
  if e4 { ok = false; }
  if resolved_of(&mut st) != 1 { ok = false; }
  if fired_of(&mut st) != 1 { ok = false; }
  if firing_of(&mut st) { ok = false; }
  if breaches_of(&mut st) != 0 { ok = false; }
  return assert(ok, "first clear sample resolves once and clears the streak");
}

fn t8() -> TestResult {
  let r = alert_rule_new(10, true, 1);
  var st = alert_state_new();
  let e1 = observe(&r, &mut st, 10);
  let e2 = observe(&r, &mut st, 1);
  let e3 = observe(&r, &mut st, 10);
  var ok = e1;
  if e2 { ok = false; }
  if !e3 { ok = false; }
  if fired_of(&mut st) != 2 { ok = false; }
  if resolved_of(&mut st) != 1 { ok = false; }
  if !firing_of(&mut st) { ok = false; }
  return assert(ok, "a second fire after a resolve is a new edge");
}

fn t9() -> TestResult {
  let r = alert_rule_new(10, true, 2);
  var st = alert_state_new();
  let e1 = observe(&r, &mut st, 20);
  let e2 = observe(&r, &mut st, 20);
  let e3 = observe(&r, &mut st, 20);
  let e4 = observe(&r, &mut st, 30);
  var ok = !e1;
  if !e2 { ok = false; }
  if e3 { ok = false; }
  if e4 { ok = false; }
  if !firing_of(&mut st) { ok = false; }
  if fired_of(&mut st) != 1 { ok = false; }
  if breaches_of(&mut st) != 4 { ok = false; }
  if resolved_of(&mut st) != 0 { ok = false; }
  return assert(ok, "breaches while firing raise the streak but not the edge");
}

fn t10() -> TestResult {
  let r = alert_rule_new(10, false, 1);
  var st = alert_state_new();
  let e1 = observe(&r, &mut st, 11);
  let e2 = observe(&r, &mut st, 9);
  let e3 = observe(&r, &mut st, 11);
  var ok = !e1;
  if !e2 { ok = false; }
  if e3 { ok = false; }
  if fired_of(&mut st) != 1 { ok = false; }
  if resolved_of(&mut st) != 1 { ok = false; }
  if firing_of(&mut st) { ok = false; }
  return assert(ok, "above=false breaches on values at or below the threshold");
}

fn t11() -> TestResult {
  let r = alert_rule_new(10, true, 1);
  var below = alert_state_new();
  var at = alert_state_new();
  let e1 = observe(&r, &mut below, 9);
  let e2 = observe(&r, &mut at, 10);
  var ok = !e1;
  if !e2 { ok = false; }
  if firing_of(&mut below) { ok = false; }
  if !firing_of(&mut at) { ok = false; }
  return assert(ok, "value == threshold is a breach when above=true");
}

fn t12() -> TestResult {
  let r = alert_rule_new(10, false, 1);
  var above = alert_state_new();
  var at = alert_state_new();
  let e1 = observe(&r, &mut above, 11);
  let e2 = observe(&r, &mut at, 10);
  var ok = !e1;
  if !e2 { ok = false; }
  if firing_of(&mut above) { ok = false; }
  if !firing_of(&mut at) { ok = false; }
  return assert(ok, "value == threshold is a breach when above=false");
}

fn t13() -> TestResult {
  let r = alert_rule_new(10, true, 0);
  var st = alert_state_new();
  let e1 = observe(&r, &mut st, 10);
  let e2 = observe(&r, &mut st, 10);
  var ok = e1;
  if e2 { ok = false; }
  if r.consecutive != 1 { ok = false; }
  if fired_of(&mut st) != 1 { ok = false; }
  return assert(ok, "consecutive=0 behaves as 1 after clamping");
}

fn t14() -> TestResult {
  let r = alert_rule_new(10, true, -3);
  var st = alert_state_new();
  let e1 = observe(&r, &mut st, 10);
  var ok = e1;
  if r.consecutive != 1 { ok = false; }
  if fired_of(&mut st) != 1 { ok = false; }
  return assert(ok, "consecutive=-3 behaves as 1 after clamping");
}

fn t15() -> TestResult {
  let r = alert_rule_new(10, true, 2);
  var vals = series_7(5, 11, 12, 3, 20, 21, 1);
  var st = alert_evaluate(&r, &vals);
  var ok = fired_of(&mut st) == 2;
  if resolved_of(&mut st) != 2 { ok = false; }
  if breaches_of(&mut st) != 0 { ok = false; }
  if firing_of(&mut st) { ok = false; }
  if alert_transition_count(&r, &vals) != 2 { ok = false; }
  return assert(ok, "evaluate pins fires, resolves and breaches on a mixed series");
}

fn t16() -> TestResult {
  let r = alert_rule_new(10, true, 2);
  var empty = Vec[Int].new();
  var st = alert_evaluate(&r, &empty);
  var ok = !firing_of(&mut st);
  if fired_of(&mut st) != 0 { ok = false; }
  if resolved_of(&mut st) != 0 { ok = false; }
  if breaches_of(&mut st) != 0 { ok = false; }
  if alert_transition_count(&r, &empty) != 0 { ok = false; }
  return assert(ok, "empty series evaluates to a fresh state with no edges");
}

fn t17() -> TestResult {
  let r = alert_rule_new(10, true, 2);
  var vals = series_repeat(12, 5);
  var st = alert_evaluate(&r, &vals);
  var ok = firing_of(&mut st);
  if fired_of(&mut st) != 1 { ok = false; }
  if resolved_of(&mut st) != 0 { ok = false; }
  if breaches_of(&mut st) != 5 { ok = false; }
  if alert_transition_count(&r, &vals) != 1 { ok = false; }
  return assert(ok, "all-breaching series fires once and stays firing");
}

fn t18() -> TestResult {
  let r = alert_rule_new(10, true, 2);
  var vals = series_repeat(3, 5);
  var st = alert_evaluate(&r, &vals);
  var ok = !firing_of(&mut st);
  if fired_of(&mut st) != 0 { ok = false; }
  if resolved_of(&mut st) != 0 { ok = false; }
  if breaches_of(&mut st) != 0 { ok = false; }
  if alert_transition_count(&r, &vals) != 0 { ok = false; }
  return assert(ok, "all-clear series never fires and never resolves");
}

fn t19() -> TestResult {
  let big = alert_rule_new(1000000000, true, 1);
  var big_st = alert_state_new();
  let b1 = observe(&big, &mut big_st, 999999999);
  let b2 = observe(&big, &mut big_st, 1000000000);
  var ok = !b1;
  if !b2 { ok = false; }
  if fired_of(&mut big_st) != 1 { ok = false; }
  let small = alert_rule_new(-1000000000, false, 2);
  var small_st = alert_state_new();
  let s1 = observe(&small, &mut small_st, -999999999);
  let s2 = observe(&small, &mut small_st, -1000000000);
  let s3 = observe(&small, &mut small_st, -2000000000);
  if s1 { ok = false; }
  if s2 { ok = false; }
  if !s3 { ok = false; }
  if fired_of(&mut small_st) != 1 { ok = false; }
  return assert(ok, "large and negative extreme values compare exactly");
}

fn t20() -> TestResult {
  let r = alert_rule_new(10, true, 2);
  var st = alert_state_new();
  let e1 = observe(&r, &mut st, 10);
  let e2 = observe(&r, &mut st, 12);
  let e3 = observe(&r, &mut st, 1);
  var ok = !e1;
  if !e2 { ok = false; }
  if e3 { ok = false; }
  if firing_of(&mut st) { ok = false; }
  if fired_of(&mut st) != 1 { ok = false; }
  if resolved_of(&mut st) != 1 { ok = false; }
  if breaches_of(&mut st) != 0 { ok = false; }
  return assert(ok, "state accessors report firing and all counters");
}

fn t21() -> TestResult {
  let r = alert_rule_new(10, true, 1);
  var vals = series_5(10, 0, 10, 4, 10);
  var ok = alert_transition_count(&r, &vals) == 3;
  var st = alert_evaluate(&r, &vals);
  if fired_of(&mut st) != 3 { ok = false; }
  if resolved_of(&mut st) != 2 { ok = false; }
  if !firing_of(&mut st) { ok = false; }
  if breaches_of(&mut st) != 1 { ok = false; }
  return assert(ok, "transition_count counts every fired edge");
}

fn main() -> Int {
  io.println("=== xiom.alerting conformance tests ===");
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
    io.println("xiom.alerting: all tests passed");
  } else {
    io.println("xiom.alerting: tests failed");
  }
  return failed;
}
