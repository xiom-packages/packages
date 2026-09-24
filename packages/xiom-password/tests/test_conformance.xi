// XIOM -- xiom.password conformance tests (23 checks)
// Port task: prove the pure-XIOM xiom.password module against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: the four ASCII byte-class detectors, the class count, longest
// byte-identical runs, the documented 0..100 score (length base, class
// bonus, run penalty, all-digit penalty, clamping), feedback order and the
// score-80 cutoff, case-insensitive common-password matching, and the
// recommend_min thresholds including the documented clamping.

module password_tests
use xiom.io; use xiom.test; use xiom.password;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every vector element
// check below is routed through streq/vec_eq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn vec_eq(got: &Vec[Str], want: &Vec[Str]) -> Bool {
  if got.len() != want.len() { return false; }
  var i = 0;
  while i < got.len() {
    if !streq(got[i], want[i]) { return false; }
    i = i + 1;
  }
  return true;
}

fn vec1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn vec4(a: Str, b: Str, c: Str, d: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn vec5(a: Str, b: Str, c: Str, d: Str, e: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

fn t1() -> TestResult {
  var ok = password_has_lower("abc");
  if !password_has_lower("aB1!") { ok = false; }
  if password_has_lower("ABC123!") { ok = false; }
  if password_has_lower("") { ok = false; }
  if password_has_lower("\u{00E9}") { ok = false; }
  if password_has_lower("\u{4ED6}\u{4EEC}") { ok = false; }
  if !password_has_lower("caf\u{00E9}") { ok = false; }
  return assert(ok, "has_lower: ASCII a-z only, non-ASCII letters excluded");
}

fn t2() -> TestResult {
  var ok = password_has_upper("ABC");
  if !password_has_upper("aB") { ok = false; }
  if password_has_upper("abc") { ok = false; }
  if password_has_upper("123!") { ok = false; }
  if password_has_upper("") { ok = false; }
  if password_has_upper("\u{00C9}") { ok = false; }
  if password_has_upper("\u{4ED6}") { ok = false; }
  return assert(ok, "has_upper: ASCII A-Z only, non-ASCII letters excluded");
}

fn t3() -> TestResult {
  var ok = password_has_digit("123");
  if !password_has_digit("a1") { ok = false; }
  if password_has_digit("abc!") { ok = false; }
  if password_has_digit("") { ok = false; }
  if password_has_digit("\u{FF11}") { ok = false; }
  if password_has_digit("caf\u{00E9}") { ok = false; }
  return assert(ok, "has_digit: ASCII 0-9 only, non-ASCII digits excluded");
}

fn t4() -> TestResult {
  var ok = password_has_symbol("!");
  if !password_has_symbol("~") { ok = false; }
  if !password_has_symbol("_") { ok = false; }
  if password_has_symbol(" ") { ok = false; }
  if password_has_symbol("\u{007F}") { ok = false; }
  if password_has_symbol("a") { ok = false; }
  if password_has_symbol("0") { ok = false; }
  if password_has_symbol("") { ok = false; }
  if password_has_symbol("\u{00E9}") { ok = false; }
  return assert(ok, "has_symbol: printable 33..126 minus alphanumerics");
}

fn t5() -> TestResult {
  var ok = password_class_count("") == 0;
  if password_class_count(" ") != 0 { ok = false; }
  if password_class_count("\u{00E9}") != 0 { ok = false; }
  if password_class_count("abc") != 1 { ok = false; }
  if password_class_count("!@#$") != 1 { ok = false; }
  if password_class_count("abc123") != 2 { ok = false; }
  if password_class_count("abcABC") != 2 { ok = false; }
  if password_class_count("abc123!") != 3 { ok = false; }
  if password_class_count("abcABC123") != 3 { ok = false; }
  if password_class_count("abcABC123!") != 4 { ok = false; }
  return assert(ok, "class_count: 0..4 over the four ASCII classes");
}

fn t6() -> TestResult {
  var ok = password_longest_run("") == 0;
  if password_longest_run("a") != 1 { ok = false; }
  if password_longest_run("ab") != 1 { ok = false; }
  if password_longest_run("aa") != 2 { ok = false; }
  if password_longest_run("aab") != 2 { ok = false; }
  if password_longest_run("abbc") != 2 { ok = false; }
  if password_longest_run("abbccc") != 3 { ok = false; }
  return assert(ok, "longest_run: empty is 0, repeat-free is 1");
}

fn t7() -> TestResult {
  var ok = password_longest_run("aaaa") == 4;
  if password_longest_run("aAaA") != 1 { ok = false; }
  if password_longest_run("a1a1a1") != 1 { ok = false; }
  if password_longest_run("abccba") != 2 { ok = false; }
  if password_longest_run("   ") != 3 { ok = false; }
  if password_longest_run("aabbb") != 3 { ok = false; }
  if password_longest_run("0000aaaa") != 4 { ok = false; }
  return assert(ok, "longest_run: byte-identical runs, case-sensitive");
}

fn t8() -> TestResult {
  var ok = password_score("") == 0;
  if password_score("a") != 14 { ok = false; }
  if password_score("ab") != 18 { ok = false; }
  if password_score("abc") != 22 { ok = false; }
  if password_score("abcd") != 26 { ok = false; }
  if password_score("ab1") != 32 { ok = false; }
  return assert(ok, "score: empty is 0, length base is 4 per byte");
}

fn t9() -> TestResult {
  var ok = password_score("aB3!") == 56;
  if password_score("aB3!a") != 60 { ok = false; }
  if password_score("aB3!aB3!aB3!aB3!") != 100 { ok = false; }
  if password_score("aaaaaaaaaaaaaaa") != 5 { ok = false; }
  return assert(ok, "score: +10 per class, length base caps at 60");
}

fn t10() -> TestResult {
  var ok = password_score("aa") == 18;
  if password_score("aaa") != 17 { ok = false; }
  if password_score("aaaa") != 16 { ok = false; }
  if password_score("aaaaaa") != 14 { ok = false; }
  if password_score("aabbb") != 25 { ok = false; }
  if password_score("aaabbb") != 24 { ok = false; }
  return assert(ok, "score: runs of 3+ lose 5 per byte beyond two");
}

fn t11() -> TestResult {
  var ok = password_score("1234567") == 18;
  if password_score("12345678") != 42 { ok = false; }
  if password_score("123456") != 14 { ok = false; }
  if password_score("1") != 0 { ok = false; }
  if password_score("11") != 0 { ok = false; }
  if password_score("1111111") != 0 { ok = false; }
  return assert(ok, "score: all-digit under 8 bytes loses 20, clamps at 0");
}

fn t12() -> TestResult {
  var ok = password_score("Xk9#mQ2!vL7@pR4$") == 100;
  if password_score("Tr0ub4dor&3xK9zQw") != 100 { ok = false; }
  if password_score("correct horse battery staple") != 70 { ok = false; }
  return assert(ok, "score: long mixed passwords top out at 100");
}

fn t13() -> TestResult {
  var ok = password_score("Ab3!eF6@gH") == 80;
  if password_score("Abbb3!eF6@g") != 79 { ok = false; }
  var strong = password_feedback("Xk9#mQ2!vL7@pR4$");
  if strong.len() != 0 { ok = false; }
  var at80 = password_feedback("Ab3!eF6@gH");
  if at80.len() != 0 { ok = false; }
  var at79 = password_feedback("Abbb3!eF6@g");
  if !vec_eq(&at79, &vec1("Avoid repeated characters")) { ok = false; }
  return assert(ok, "feedback: empty at score 80+, one item at 79");
}

fn t14() -> TestResult {
  var got = password_feedback("abc");
  var want = vec4("Use at least 8 characters", "Add uppercase letters", "Add digits", "Add symbols");
  var ok = vec_eq(&got, &want);
  return assert(ok, "feedback: length first, then missing classes in order");
}

fn t15() -> TestResult {
  var got = password_feedback("");
  var want = vec5("Use at least 8 characters", "Add lowercase letters", "Add uppercase letters", "Add digits", "Add symbols");
  var ok = vec_eq(&got, &want);
  return assert(ok, "feedback: empty password asks for length and 4 classes");
}

fn t16() -> TestResult {
  var got4 = password_feedback("1234");
  var want4 = vec5("Use at least 8 characters", "Add lowercase letters", "Add uppercase letters", "Add symbols", "Avoid all-digit passwords");
  var ok = vec_eq(&got4, &want4);
  var got8 = password_feedback("12345678");
  var want8 = vec4("Add lowercase letters", "Add uppercase letters", "Add symbols", "Avoid all-digit passwords");
  if !vec_eq(&got8, &want8) { ok = false; }
  return assert(ok, "feedback: digit-only passwords get class and digit advice");
}

fn t17() -> TestResult {
  var got = password_feedback("aaaaaaaaaaaaaa");
  var want = vec4("Add uppercase letters", "Add digits", "Add symbols", "Avoid repeated characters");
  var ok = vec_eq(&got, &want);
  return assert(ok, "feedback: a long run adds one advice item");
}

fn t18() -> TestResult {
  var list = Vec[Str].new();
  list.push("password");
  list.push("123456");
  list.push("qwerty");
  var ok = password_is_common("PASSWORD", &list);
  if !password_is_common("Password", &list) { ok = false; }
  if !password_is_common("password", &list) { ok = false; }
  if password_is_common("passw0rd", &list) { ok = false; }
  if password_is_common("", &list) { ok = false; }
  var empty = Vec[Str].new();
  if password_is_common("password", &empty) { ok = false; }
  return assert(ok, "is_common: case-insensitive exact match, empty list");
}

fn t19() -> TestResult {
  var list = Vec[Str].new();
  list.push("");
  list.push("Admin");
  list.push("root");
  var ok = password_is_common("", &list);
  if !password_is_common("aDMIN", &list) { ok = false; }
  if !password_is_common("ROOT", &list) { ok = false; }
  if password_is_common("adm", &list) { ok = false; }
  if password_is_common("adminx", &list) { ok = false; }
  return assert(ok, "is_common: whole string only, empty entry matches empty");
}

fn t20() -> TestResult {
  var ok = password_recommend_min("abc", 3, 1);
  if password_recommend_min("abc", 4, 1) { ok = false; }
  if password_recommend_min("abc", 3, 2) { ok = false; }
  if !password_recommend_min("abc", 2, 1) { ok = false; }
  if password_recommend_min("", 1, 0) { ok = false; }
  if !password_recommend_min("", 0, 0) { ok = false; }
  if password_recommend_min("", 0, 1) { ok = false; }
  if !password_recommend_min("aB1!", 4, 4) { ok = false; }
  if password_recommend_min("aB1!", 5, 4) { ok = false; }
  if password_recommend_min("aB1", 4, 4) { ok = false; }
  return assert(ok, "recommend_min: length and class thresholds at boundary");
}

fn t21() -> TestResult {
  var ok = password_recommend_min("aB1!", 0, 5);
  if password_recommend_min("abc", 0, 5) { ok = false; }
  if !password_recommend_min("abc", -3, -1) { ok = false; }
  if !password_recommend_min("", -1, -1) { ok = false; }
  if !password_recommend_min("aB1!x", 5, 4) { ok = false; }
  if password_recommend_min("abc", 4, -1) { ok = false; }
  return assert(ok, "recommend_min: classes clamp to 0..4, min_len <= 0 free");
}

fn t22() -> TestResult {
  let pw = "caf\u{00E9}";
  var ok = password_has_lower(pw);
  if password_has_upper(pw) { ok = false; }
  if password_has_digit(pw) { ok = false; }
  if password_has_symbol(pw) { ok = false; }
  if password_class_count(pw) != 1 { ok = false; }
  if pw.len() != 5 { ok = false; }
  if password_longest_run(pw) != 1 { ok = false; }
  if password_score(pw) != 30 { ok = false; }
  var got = password_feedback(pw);
  var want = vec4("Use at least 8 characters", "Add uppercase letters", "Add digits", "Add symbols");
  if !vec_eq(&got, &want) { ok = false; }
  return assert(ok, "non-ASCII bytes: length and runs only, no class");
}

fn t23() -> TestResult {
  var ok = password_has_symbol("`");
  if !password_has_symbol("{}") { ok = false; }
  if !password_has_symbol("@") { ok = false; }
  if !password_has_symbol("_-'") { ok = false; }
  if password_has_symbol("  ") { ok = false; }
  if password_has_symbol("a1") { ok = false; }
  if password_has_symbol("\u{0009}") { ok = false; }
  if password_class_count("_-'") != 1 { ok = false; }
  return assert(ok, "has_symbol: punctuation counts, whitespace/alnum not");
}

fn main() -> Int {
  io.println("=== xiom.password conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.password: all tests passed");
  } else {
    io.println("xiom.password: tests failed");
  }
  return failed;
}
