// XIOM -- xiom.envsubst conformance tests (22 checks)
// Greenfield package: prove the pure-XIOM xiom.envsubst module against its
// documented ${VAR} grammar, missing-value modes and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: single/multiple/repeated references, strict and lenient missing
// values, "$$" literalization, lone "{" and lone "$" literals, unterminated
// "${", nested-looking "${A${B}}", digits and underscores in names, invalid
// name characters, the pairs variant (including "=" in values and malformed
// pairs), single-pass no-re-scan, empty inputs, has_vars, names order/skip
// rules, case-sensitivity and duplicate/short-table lookup semantics.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/ok_is/err_is/list_is* instead of `==`.

module envsubst_tests
use xiom.io; use xiom.test; use xiom.envsubst;
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

// Small Vec[Str] builders for inline name/value and pair tables.
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

// True when strict expansion of `text` fails with the invalid-name error.
fn invalid_is(text: Str) -> Bool {
  var none = Vec[Str].new();
  let r = envsubst_expand(text, &none, &none, false);
  return err_is(r, "envsubst: invalid variable name");
}

fn t1() -> TestResult {
  var names = v1("NAME");
  var values = v1("Ada");
  let r = envsubst_expand("Hello, ${NAME}!", &names, &values, false);
  return assert(ok_is(r, "Hello, Ada!"), "single ${VAR} substitutes");
}

fn t2() -> TestResult {
  var names = v3("A", "B", "C");
  var values = v3("1", "2", "3");
  let r = envsubst_expand("${A}+${B}=${C}", &names, &values, false);
  return assert(ok_is(r, "1+2=3"), "multiple ${VAR}s substitute");
}

fn t3() -> TestResult {
  var names = v2("A", "B");
  var values = v2("x", "y");
  let r1 = envsubst_expand("${A}-${A}-${A}", &names, &values, false);
  var ok = ok_is(r1, "x-x-x");
  let r2 = envsubst_expand("${A}${A}", &names, &values, false);
  if !ok_is(r2, "xx") { ok = false; }
  return assert(ok, "repeated references expand every time");
}

fn t4() -> TestResult {
  var names = v1("NAME");
  var values = v1("Ada");
  let r = envsubst_expand("Hi ${WHO}!", &names, &values, false);
  var ok = err_is(r, "envsubst: undefined variable: WHO");
  var none = Vec[Str].new();
  let r2 = envsubst_expand("${A}", &none, &none, false);
  if !err_is(r2, "envsubst: undefined variable: A") { ok = false; }
  return assert(ok, "an undefined variable is Err in strict mode");
}

fn t5() -> TestResult {
  var names = v1("NAME");
  var values = v1("Ada");
  let r = envsubst_expand("Hi ${WHO}!", &names, &values, true);
  var ok = ok_is(r, "Hi !");
  var none = Vec[Str].new();
  let r2 = envsubst_expand("${A}${B}", &none, &none, true);
  if !ok_is(r2, "") { ok = false; }
  return assert(ok, "an undefined variable expands to \"\" in lenient mode");
}

fn t6() -> TestResult {
  var none = Vec[Str].new();
  let r1 = envsubst_expand("cost: $$5", &none, &none, false);
  var ok = ok_is(r1, "cost: $5");
  let r2 = envsubst_expand("$$", &none, &none, false);
  if !ok_is(r2, "$") { ok = false; }
  var names = v1("A");
  var values = v1("1");
  let r3 = envsubst_expand("$${A}", &names, &values, false);
  if !ok_is(r3, "${A}") { ok = false; }
  return assert(ok, "$$ expands to a literal $ (so $${A} stays literal)");
}

fn t7() -> TestResult {
  var none = Vec[Str].new();
  let r1 = envsubst_expand("a{b} c", &none, &none, false);
  var ok = ok_is(r1, "a{b} c");
  let r2 = envsubst_expand("}{", &none, &none, false);
  if !ok_is(r2, "}{") { ok = false; }
  let r3 = envsubst_expand("{$A}", &none, &none, false);
  if !ok_is(r3, "{$A}") { ok = false; }
  return assert(ok, "a '{' not preceded by '$' is literal text");
}

fn t8() -> TestResult {
  var none = Vec[Str].new();
  let r1 = envsubst_expand("a ${B", &none, &none, false);
  var ok = err_is(r1, "envsubst: unterminated variable reference");
  let r2 = envsubst_expand("${", &none, &none, true);
  if !err_is(r2, "envsubst: unterminated variable reference") { ok = false; }
  var names = v1("A");
  var values = v1("1");
  let r3 = envsubst_expand("x ${1", &names, &values, false);
  if !err_is(r3, "envsubst: unterminated variable reference") { ok = false; }
  return assert(ok, "an unterminated \"${\" is Err in both modes");
}

fn t9() -> TestResult {
  var names = v2("A", "B");
  var values = v2("1", "2");
  let r1 = envsubst_expand("${A${B}}", &names, &values, false);
  var ok = err_is(r1, "envsubst: invalid variable name");
  let r2 = envsubst_expand("x${A}y}", &names, &values, false);
  if !ok_is(r2, "x1y}") { ok = false; }
  return assert(ok, "nested-looking ${A${B}} is invalid; text after the first } is literal");
}

fn t10() -> TestResult {
  var names = v3("_A1b", "X2", "_");
  var values = v3("u", "v", "w");
  let r = envsubst_expand("${_A1b}${X2}${_}", &names, &values, false);
  return assert(ok_is(r, "uvw"), "names may contain digits and underscores");
}

fn t11() -> TestResult {
  var ok = invalid_is("${}");
  if !invalid_is("${1A}") { ok = false; }
  if !invalid_is("${A-B}") { ok = false; }
  if !invalid_is("${A B}") { ok = false; }
  if !invalid_is("${A$}") { ok = false; }
  if !invalid_is("${A.}") { ok = false; }
  var none = Vec[Str].new();
  let lenient = envsubst_expand("${1A}", &none, &none, true);
  if !err_is(lenient, "envsubst: invalid variable name") { ok = false; }
  return assert(ok, "invalid name characters inside braces are Err in both modes");
}

fn t12() -> TestResult {
  var pairs = v3("HOST=localhost", "PORT=8080", "URL=a=b");
  let r = envsubst_expand_pairs("${HOST}:${PORT}/?u=${URL}", &pairs, false);
  var ok = ok_is(r, "localhost:8080/?u=a=b");
  var dup = v2("A=1", "A=2");
  let r2 = envsubst_expand_pairs("${A}", &dup, false);
  if !ok_is(r2, "1") { ok = false; }
  return assert(ok, "pairs expand; values may contain '='; first duplicate wins");
}

fn t13() -> TestResult {
  var pairs = v3("NOVALUE", "A=1", "=orphan");
  let r = envsubst_expand_pairs("${A}", &pairs, false);
  var ok = ok_is(r, "1");
  let r2 = envsubst_expand_pairs("x${NOVALUE}y", &pairs, false);
  if !err_is(r2, "envsubst: undefined variable: NOVALUE") { ok = false; }
  let r3 = envsubst_expand_pairs("x${NOVALUE}y", &pairs, true);
  if !ok_is(r3, "xy") { ok = false; }
  var only = v1("=orphan");
  let r4 = envsubst_expand_pairs("${A}", &only, true);
  if !ok_is(r4, "") { ok = false; }
  return assert(ok, "pairs without '=' or with an empty name are ignored");
}

fn t14() -> TestResult {
  var names = v2("A", "B");
  var values = v2("${B}", "2");
  let r = envsubst_expand("${A}", &names, &values, false);
  var ok = ok_is(r, "${B}");
  let r2 = envsubst_expand("${A}${B}", &names, &values, false);
  if !ok_is(r2, "${B}2") { ok = false; }
  var pairs = v1("A=${B}");
  let r3 = envsubst_expand_pairs("${A}", &pairs, false);
  if !ok_is(r3, "${B}") { ok = false; }
  return assert(ok, "substituted values are not re-scanned (single pass)");
}

fn t15() -> TestResult {
  var none = Vec[Str].new();
  let r1 = envsubst_expand("", &none, &none, false);
  var ok = ok_is(r1, "");
  let r2 = envsubst_expand("plain text", &none, &none, false);
  if !ok_is(r2, "plain text") { ok = false; }
  var pairs = Vec[Str].new();
  let r3 = envsubst_expand_pairs("", &pairs, false);
  if !ok_is(r3, "") { ok = false; }
  let ns = envsubst_names("");
  if ns.len() != 0 { ok = false; }
  if envsubst_has_vars("") { ok = false; }
  return assert(ok, "empty text and empty tables behave");
}

fn t16() -> TestResult {
  var ok = envsubst_has_vars("a${X}b");
  if envsubst_has_vars("plain") { ok = false; }
  if envsubst_has_vars("$") { ok = false; }
  if envsubst_has_vars("$X") { ok = false; }
  if !envsubst_has_vars("${") { ok = false; }
  if !envsubst_has_vars("$${A}") { ok = false; }
  return assert(ok, "has_vars is a raw \"${\" scan (over-reports by design)");
}

fn t17() -> TestResult {
  let ks = envsubst_names("${B} ${A} ${B} ${C} ${A}");
  var ok = list_is3(&ks, "B", "A", "C");
  let ks2 = envsubst_names("${A}${}${1x}-${A}");
  if !list_is(&ks2, "A") { ok = false; }
  let ks3 = envsubst_names("$${A}");
  if ks3.len() != 0 { ok = false; }
  let ks4 = envsubst_names("${A}${");
  if !list_is(&ks4, "A") { ok = false; }
  return assert(ok, "envsubst_names is first-seen, deduped and skips malformed refs");
}

fn t18() -> TestResult {
  var names = v1("name");
  var values = v1("Ada");
  let r1 = envsubst_expand("${name}", &names, &values, false);
  var ok = ok_is(r1, "Ada");
  let r2 = envsubst_expand("${NAME}", &names, &values, false);
  if !err_is(r2, "envsubst: undefined variable: NAME") { ok = false; }
  let r3 = envsubst_expand("${NAME}", &names, &values, true);
  if !ok_is(r3, "") { ok = false; }
  return assert(ok, "lookups are exact and case-sensitive");
}

fn t19() -> TestResult {
  var names = v1("E");
  var values = v1("");
  let r = envsubst_expand("x${E}y", &names, &values, false);
  var ok = ok_is(r, "xy");
  let r2 = envsubst_expand("${E}", &names, &values, true);
  if !ok_is(r2, "") { ok = false; }
  return assert(ok, "a present empty value is not an undefined name");
}

fn t20() -> TestResult {
  var names = v2("A", "A");
  var values = v2("first", "second");
  let r = envsubst_expand("${A}", &names, &values, false);
  var ok = ok_is(r, "first");
  var names2 = v2("A", "B");
  var values2 = v1("1");
  let r2 = envsubst_expand("${A}", &names2, &values2, false);
  if !ok_is(r2, "1") { ok = false; }
  let r3 = envsubst_expand("${B}", &names2, &values2, false);
  if !err_is(r3, "envsubst: undefined variable: B") { ok = false; }
  let r4 = envsubst_expand("${B}", &names2, &values2, true);
  if !ok_is(r4, "") { ok = false; }
  return assert(ok, "first duplicate wins; a name without a value is undefined");
}

fn t21() -> TestResult {
  var names = v2("A", "B");
  var values = v2("1", "2");
  let r1 = envsubst_expand("${A}${B}", &names, &values, false);
  var ok = ok_is(r1, "12");
  var none = Vec[Str].new();
  let r2 = envsubst_expand("$X", &none, &none, false);
  if !ok_is(r2, "$X") { ok = false; }
  let r3 = envsubst_expand("$ {A}", &none, &none, false);
  if !ok_is(r3, "$ {A}") { ok = false; }
  let r4 = envsubst_expand("a$", &none, &none, false);
  if !ok_is(r4, "a$") { ok = false; }
  return assert(ok, "adjacent references expand; a lone $ is literal");
}

fn t22() -> TestResult {
  var pairs = v2("A=1", "=junk");
  let r1 = envsubst_expand_pairs("${A}${MISS}", &pairs, true);
  var ok = ok_is(r1, "1");
  var none = Vec[Str].new();
  let r2 = envsubst_expand_pairs("${A}", &none, false);
  if !err_is(r2, "envsubst: undefined variable: A") { ok = false; }
  let r3 = envsubst_expand_pairs("${A}", &none, true);
  if !ok_is(r3, "") { ok = false; }
  return assert(ok, "the pairs variant honours missing_empty and an empty table");
}

fn main() -> Int {
  io.println("=== xiom.envsubst conformance tests ===");
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
    io.println("xiom.envsubst: all tests passed");
  } else {
    io.println("xiom.envsubst: tests failed");
  }
  return failed;
}
