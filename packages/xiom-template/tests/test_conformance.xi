// XIOM -- xiom.template conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.template module against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/ok_is/err_is instead of `==`.

module template_tests
use xiom.io; use xiom.test; use xiom.template;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is Ok and its payload is exactly `want`.
fn ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  return streq(r.value, want);
}

// True when r is Err and its message is exactly `want`.
fn err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// Small Vec[Str] builders for inline key/value tables.
fn v1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn v2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn v3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

// Element-wise list checks (via str_compare, never `==`).
fn list_is(items: &Vec[Str], a: Str) -> Bool {
  if items.len() != 1 {
    return false;
  }
  let first: Str = items[0];
  return streq(first, a);
}

fn list_is2(items: &Vec[Str], a: Str, b: Str) -> Bool {
  if items.len() != 2 {
    return false;
  }
  let first: Str = items[0];
  let second: Str = items[1];
  var ok = streq(first, a);
  if !streq(second, b) { ok = false; }
  return ok;
}

fn list_is3(items: &Vec[Str], a: Str, b: Str, c: Str) -> Bool {
  if items.len() != 3 {
    return false;
  }
  let first: Str = items[0];
  let second: Str = items[1];
  let third: Str = items[2];
  var ok = streq(first, a);
  if !streq(second, b) { ok = false; }
  if !streq(third, c) { ok = false; }
  return ok;
}

fn t1() -> TestResult {
  var empty = Vec[Str].new();
  let r = template_render("Hello, world!", &empty, &empty);
  var ok = ok_is(r, "Hello, world!");
  let l = template_render_lenient("Hello, world!", &empty, &empty);
  if !streq(l, "Hello, world!") { ok = false; }
  return assert(ok, "plain text passes through unchanged");
}

fn t2() -> TestResult {
  var keys = v1("name");
  var values = v1("Ada");
  let r = template_render("Hello, {{name}}!", &keys, &values);
  return assert(ok_is(r, "Hello, Ada!"), "single placeholder substitutes");
}

fn t3() -> TestResult {
  var keys = v3("a", "b", "c");
  var values = v3("1", "2", "3");
  let r = template_render("{{a}}+{{b}}={{c}}", &keys, &values);
  return assert(ok_is(r, "1+2=3"), "multiple placeholders substitute");
}

fn t4() -> TestResult {
  var keys = v1("name");
  var values = v1("Ada");
  let r = template_render("{{ name }}/{{name }}/{{  name  }}", &keys, &values);
  return assert(ok_is(r, "Ada/Ada/Ada"), "spaces inside braces are ignored");
}

fn t5() -> TestResult {
  var keys = v1("name");
  var values = v1("Ada");
  let r = template_render("Hi {{who}}!", &keys, &values);
  return assert(err_is(r, "template: missing key: who"), "missing key is an Err in strict mode");
}

fn t6() -> TestResult {
  var keys = v1("name");
  var values = v1("Ada");
  let r = template_render_lenient("Hi {{who}}!", &keys, &values);
  return assert(streq(r, "Hi !"), "missing key renders empty in lenient mode");
}

fn t7() -> TestResult {
  var keys = v2("k", "k");
  var values = v2("first", "second");
  let r = template_render("{{k}}/{{k}}", &keys, &values);
  var ok = ok_is(r, "first/first");
  var keys2 = v2("k", "k");
  var values2 = v2("first", "second");
  let l = template_render_lenient("{{k}}", &keys2, &values2);
  if !streq(l, "first") { ok = false; }
  return assert(ok, "duplicate key: the first match wins");
}

fn t8() -> TestResult {
  var empty = Vec[Str].new();
  let r1 = template_render("a{{! note }}b", &empty, &empty);
  var ok = ok_is(r1, "ab");
  let r2 = template_render("a{{!note}}b", &empty, &empty);
  if !ok_is(r2, "ab") { ok = false; }
  let r3 = template_render("{{ ! spaced }}x", &empty, &empty);
  if !ok_is(r3, "x") { ok = false; }
  return assert(ok, "comments are removed");
}

fn t9() -> TestResult {
  var empty = Vec[Str].new();
  let r1 = template_render("{{{{", &empty, &empty);
  var ok = ok_is(r1, "{{");
  let r2 = template_render("a{{{{b", &empty, &empty);
  if !ok_is(r2, "a{{b") { ok = false; }
  let r3 = template_render("{{{{name}}", &empty, &empty);
  if !ok_is(r3, "{{name}}") { ok = false; }
  return assert(ok, "quadruple braces emit one literal {{");
}

fn t10() -> TestResult {
  var empty = Vec[Str].new();
  let r1 = template_render("a {{b", &empty, &empty);
  var ok = err_is(r1, "template: unterminated placeholder");
  let r2 = template_render("{{", &empty, &empty);
  if !err_is(r2, "template: unterminated placeholder") { ok = false; }
  let r3 = template_render("x{{! never closed", &empty, &empty);
  if !err_is(r3, "template: unterminated placeholder") { ok = false; }
  return assert(ok, "unterminated placeholder is an Err in strict mode");
}

fn t11() -> TestResult {
  var empty = Vec[Str].new();
  let r1 = template_render_lenient("a {{b", &empty, &empty);
  var ok = streq(r1, "a ");
  let r2 = template_render_lenient("{{", &empty, &empty);
  if !streq(r2, "") { ok = false; }
  let r3 = template_render_lenient("x{{! never closed", &empty, &empty);
  if !streq(r3, "x") { ok = false; }
  return assert(ok, "unterminated placeholder drops the tail in lenient mode");
}

fn t12() -> TestResult {
  var keys = v2("a", "b");
  var values = v2("1", "2");
  let r = template_render("{{a}}{{b}}{{a}}{{b}}", &keys, &values);
  return assert(ok_is(r, "1212"), "adjacent placeholders render back to back");
}

fn t13() -> TestResult {
  var empty = Vec[Str].new();
  let r = template_render("", &empty, &empty);
  var ok = ok_is(r, "");
  let l = template_render_lenient("", &empty, &empty);
  if !streq(l, "") { ok = false; }
  let ks = template_keys("");
  if ks.len() != 0 { ok = false; }
  return assert(ok, "empty template renders empty and has no keys");
}

fn t14() -> TestResult {
  var keys = v1("a");
  var values = v1("");
  let r = template_render("x{{a}}y", &keys, &values);
  var ok = ok_is(r, "xy");
  var keys2 = v2("a", "b");
  var values2 = v2("", "B");
  let r2 = template_render("{{a}}{{b}}", &keys2, &values2);
  if !ok_is(r2, "B") { ok = false; }
  return assert(ok, "an empty value substitutes as empty (not missing)");
}

fn t15() -> TestResult {
  let ks = template_keys("{{b}} {{a}} {{b}} {{c}} {{a}}");
  var ok = list_is3(&ks, "b", "a", "c");
  let ks2 = template_keys("{{x}}{{! a }}{{a}}{{a}}{{!x}}");
  if !list_is2(&ks2, "x", "a") { ok = false; }
  let ks3 = template_keys("{{{{ {{z}}");
  if !list_is(&ks3, "z") { ok = false; }
  return assert(ok, "template_keys is first-seen, deduped and comment-free");
}

fn t16() -> TestResult {
  var keys = v1("b");
  let need = template_needs_keys("{{a}}{{b}}{{c}}{{a}}", &keys);
  var ok = list_is2(&need, "a", "c");
  var none = Vec[Str].new();
  let all = template_needs_keys("{{a}}{{b}}{{a}}", &none);
  if !list_is2(&all, "a", "b") { ok = false; }
  let commented = template_needs_keys("{{!x}}{{a}}", &none);
  if !list_is(&commented, "a") { ok = false; }
  return assert(ok, "template_needs_keys reports missing keys in first-seen order");
}

fn t17() -> TestResult {
  var keys = v2("a", "b");
  var values = v2("{{b}}", "EXPANDED");
  let r = template_render("{{a}}", &keys, &values);
  var ok = ok_is(r, "{{b}}");
  let r2 = template_render("{{a}}{{a}}", &keys, &values);
  if !ok_is(r2, "{{b}}{{b}}") { ok = false; }
  var keys1 = v1("a");
  var values1 = v1("{{name}}");
  let l = template_render_lenient("x{{a}}", &keys1, &values1);
  if !streq(l, "x{{name}}") { ok = false; }
  return assert(ok, "substituted values are not re-expanded (single pass)");
}

fn t18() -> TestResult {
  var keys = v1("");
  var values = v1("E");
  let r = template_render("[{{}}]", &keys, &values);
  var ok = ok_is(r, "[E]");
  var empty = Vec[Str].new();
  let r2 = template_render("[{{}}]", &empty, &empty);
  if !err_is(r2, "template: missing key: ") { ok = false; }
  let l = template_render_lenient("[{{}}]", &empty, &empty);
  if !streq(l, "[]") { ok = false; }
  return assert(ok, "the empty name matches the empty-string key");
}

fn t19() -> TestResult {
  var keys = v1("");
  var values = v1("E");
  let r = template_render("{{  }}", &keys, &values);
  var ok = ok_is(r, "E");
  var empty = Vec[Str].new();
  let r2 = template_render("{{  }}", &empty, &empty);
  if !err_is(r2, "template: missing key: ") { ok = false; }
  return assert(ok, "a whitespace-only placeholder is the empty name");
}

fn t20() -> TestResult {
  var keys = v1("x");
  var values = v1("é");
  let r = template_render("café {{x}} ✓", &keys, &values);
  var ok = ok_is(r, "café é ✓");
  let ks = template_keys("café {{x}} ✓");
  if !list_is(&ks, "x") { ok = false; }
  return assert(ok, "non-ASCII text passes through byte-exact");
}

fn t21() -> TestResult {
  var keys = v2("a", "b");
  var values = v1("1");
  let r1 = template_render("{{a}}", &keys, &values);
  var ok = ok_is(r1, "1");
  let r2 = template_render("{{b}}", &keys, &values);
  if !err_is(r2, "template: missing key: b") { ok = false; }
  let need = template_needs_keys("{{a}}{{b}}", &keys);
  if need.len() != 0 { ok = false; }
  return assert(ok, "a key without a parallel value counts as missing");
}

fn t22() -> TestResult {
  var empty = Vec[Str].new();
  let r1 = template_render("a {b} c", &empty, &empty);
  var ok = ok_is(r1, "a {b} c");
  let r2 = template_render("}{", &empty, &empty);
  if !ok_is(r2, "}{") { ok = false; }
  let r3 = template_render("a}}b", &empty, &empty);
  if !ok_is(r3, "a}}b") { ok = false; }
  var keys = v1("a");
  var values = v1("X");
  let r4 = template_render("{{a}}}", &keys, &values);
  if !ok_is(r4, "X}") { ok = false; }
  return assert(ok, "lone braces and stray }} are literal text");
}

fn main() -> Int {
  io.println("=== xiom.template conformance tests ===");
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
    io.println("xiom.template: all tests passed");
  } else {
    io.println("xiom.template: tests failed");
  }
  return failed;
}
