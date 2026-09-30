// XIOM -- xiom.environment conformance tests (23 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the pure-XIOM xiom.environment module against its documented
// expansion grammar: ${VAR}, ${VAR:-default}, ${VAR-default}, ${VAR:+alt},
// ${VAR:?message}, the $$ escape, single-quoted (literal) and double-quoted
// (expanding) spans, nested expansions with a depth cap, the strict/lenient
// unknown-variable policy, the error catalog and the referenced-name list.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/names_are instead of `==`. Tests dispatch
// directly (t1() ... t23()); no fn tables are used.

module environment_tests
use xiom.io; use xiom.test; use xiom.environment;
use xiom.string.compare;

// --------------------------------------------------
//  Test helpers (fixture builders and comparators)
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn mk_vars() -> EnvVars {
  var v = EnvVars{ names: Vec[Str].new(); values: Vec[Str].new() };
  return v;
}

fn add_var(vars: &mut EnvVars, name: Str, value: Str) {
  vars.names.push(name);
  vars.values.push(value);
}

fn svec0() -> Vec[Str] {
  return Vec[Str].new();
}

fn svec1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn svec2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn svec3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn names_are(e: &Expansion, want: &Vec[Str]) -> Bool {
  if e.names.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < e.names.len() {
    let got: Str = e.names[i];
    let exp: Str = want[i];
    if compare.str_compare(got, exp) != 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn text_is(src: Str, vars: &EnvVars, strict: Bool, want: Str) -> Bool {
  let r = env_expand(src, vars, strict);
  match r {
    Ok(e) => { return streq(e.text, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn err_is(src: Str, vars: &EnvVars, strict: Bool, want: Str) -> Bool {
  let r = env_expand(src, vars, strict);
  match r {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn names_is(src: Str, vars: &EnvVars, strict: Bool, want: &Vec[Str]) -> Bool {
  let r = env_expand(src, vars, strict);
  match r {
    Ok(e) => { return names_are(&e, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn pairs_text_is(src: Str, pairs: &Vec[Str], strict: Bool, want: Str) -> Bool {
  let r = env_expand_pairs(src, pairs, strict);
  match r {
    Ok(e) => { return streq(e.text, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn pairs_err_is(src: Str, pairs: &Vec[Str], strict: Bool, want: Str) -> Bool {
  let r = env_expand_pairs(src, pairs, strict);
  match r {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "1");
  var ok = text_is("${A}", &vs, true, "1");
  if !text_is("x${A}y", &vs, true, "x1y") { ok = false; }
  return assert(ok, "single ${VAR} substitution");
}

fn t2() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "1");
  add_var(&mut vs, "B", "two");
  add_var(&mut vs, "C", "3");
  var ok = text_is("${A}+${B}=${C}", &vs, true, "1+two=3");
  if !text_is("${A}${A}${B}", &vs, true, "11two") { ok = false; }
  return assert(ok, "multiple and repeated references");
}

fn t3() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "E", "");
  add_var(&mut vs, "S", "val");
  var ok = text_is("${U:-def}", &vs, true, "def");
  if !text_is("${E:-def}", &vs, true, "def") { ok = false; }
  if !text_is("${S:-def}", &vs, true, "val") { ok = false; }
  if !text_is("${E:-}", &vs, true, "") { ok = false; }
  if !text_is("${U:-}", &vs, true, "") { ok = false; }
  return assert(ok, "${VAR:-default} covers unset or empty");
}

fn t4() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "E", "");
  add_var(&mut vs, "S", "val");
  var ok = text_is("${U-def}", &vs, true, "def");
  if !text_is("${E-def}", &vs, true, "") { ok = false; }
  if !text_is("${S-def}", &vs, true, "val") { ok = false; }
  return assert(ok, "${VAR-default} covers unset only; empty stays empty");
}

fn t5() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "E", "");
  add_var(&mut vs, "S", "val");
  var ok = text_is("${S:+alt}", &vs, true, "alt");
  if !text_is("${E:+alt}", &vs, true, "") { ok = false; }
  if !text_is("${U:+alt}", &vs, true, "") { ok = false; }
  if !text_is("${S:+}", &vs, true, "") { ok = false; }
  return assert(ok, "${VAR:+alt} needs set and non-empty");
}

fn t6() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "E", "");
  add_var(&mut vs, "S", "val");
  var ok = err_is("${U:?boom}", &vs, true, "environment: U: boom");
  if !err_is("${E:?boom}", &vs, true, "environment: E: boom") { ok = false; }
  if !err_is("${E:?}", &vs, true, "environment: E: unset or empty") { ok = false; }
  if !text_is("${S:?boom}", &vs, true, "val") { ok = false; }
  return assert(ok, "${VAR:?message} fails when unset or empty");
}

fn t7() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "S", "val");
  var ok = err_is("${U:?bad ${S}}", &vs, true, "environment: U: bad val");
  if !err_is("${U:?${S}}", &vs, true, "environment: U: val") { ok = false; }
  return assert(ok, ":? message is itself expanded");
}

fn t8() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "1");
  var ok = err_is("${WHO}", &vs, true, "environment: undefined variable: WHO");
  var empty = mk_vars();
  if !err_is("${X}", &empty, true, "environment: undefined variable: X") { ok = false; }
  if !text_is("plain text", &empty, true, "plain text") { ok = false; }
  return assert(ok, "strict mode rejects unknown variables");
}

fn t9() -> TestResult {
  var vs = mk_vars();
  var ok = text_is("[${MISSING}]", &vs, false, "[]");
  if !text_is("${MISSING:-fallback}", &vs, false, "fallback") { ok = false; }
  return assert(ok, "lenient mode expands unknown variables to empty");
}

fn t10() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "1");
  var ok = text_is("$$", &vs, true, "$");
  if !text_is("$$5", &vs, true, "$5") { ok = false; }
  if !text_is("$${A}", &vs, true, "${A}") { ok = false; }
  if !text_is("$$$$", &vs, true, "$$") { ok = false; }
  if !text_is("a$$b", &vs, true, "a$b") { ok = false; }
  return assert(ok, "$$ is one literal dollar");
}

fn t11() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "1");
  var ok = text_is("$", &vs, true, "$");
  if !text_is("$A", &vs, true, "$A") { ok = false; }
  if !text_is("a$", &vs, true, "a$") { ok = false; }
  if !text_is("$ {A}", &vs, true, "$ {A}") { ok = false; }
  return assert(ok, "bare $ and $NAME are literal; only ${NAME} expands");
}

fn t12() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "1");
  var ok = text_is("'${A}'", &vs, true, "${A}");
  if !text_is("'$$'", &vs, true, "$$") { ok = false; }
  if !text_is("'a b'", &vs, true, "a b") { ok = false; }
  if !text_is("'it''s'", &vs, true, "its") { ok = false; }
  if !text_is("'a\"b'", &vs, true, "a\"b") { ok = false; }
  return assert(ok, "single-quoted spans are literal and unquoted");
}

fn t13() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "1");
  var ok = text_is("\"${A}\"", &vs, true, "1");
  if !text_is("\"a${A}b\"", &vs, true, "a1b") { ok = false; }
  if !text_is("\"$${A}\"", &vs, true, "${A}") { ok = false; }
  if !text_is("\"it's\"", &vs, true, "it's") { ok = false; }
  if !text_is("\"a'b'c\"", &vs, true, "a'b'c") { ok = false; }
  return assert(ok, "double-quoted spans expand and are unquoted");
}

fn t14() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "1");
  var ok = text_is("'${A}'${A}", &vs, true, "${A}1");
  if !text_is("pre\"${A}\"post", &vs, true, "pre1post") { ok = false; }
  if !text_is("\"x\"'y'", &vs, true, "xy") { ok = false; }
  return assert(ok, "quoted and unquoted segments concatenate");
}

fn t15() -> TestResult {
  var vs = mk_vars();
  var ok = err_is("'abc", &vs, true, "environment: unterminated single quote");
  if !err_is("\"abc", &vs, true, "environment: unterminated double quote") { ok = false; }
  if !err_is("a'b", &vs, true, "environment: unterminated single quote") { ok = false; }
  return assert(ok, "unterminated quotes are errors");
}

fn t16() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "1");
  var ok = err_is("${A", &vs, true, "environment: unterminated reference");
  if !err_is("${", &vs, true, "environment: unterminated reference") { ok = false; }
  if !err_is("a ${B", &vs, false, "environment: unterminated reference") { ok = false; }
  return assert(ok, "unterminated references are errors in both modes");
}

fn t17() -> TestResult {
  var vs = mk_vars();
  var ok = err_is("${}", &vs, true, "environment: invalid variable name");
  if !err_is("${1A}", &vs, true, "environment: invalid variable name") { ok = false; }
  if !err_is("${.x}", &vs, true, "environment: invalid variable name") { ok = false; }
  if !err_is("${:x}", &vs, false, "environment: invalid variable name") { ok = false; }
  return assert(ok, "invalid variable names are errors");
}

fn t18() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "1");
  var ok = err_is("${A+x}", &vs, true, "environment: unsupported operator: +");
  if !err_is("${A?}", &vs, true, "environment: unsupported operator: ?") { ok = false; }
  if !err_is("${A:b}", &vs, true, "environment: unsupported operator: :b") { ok = false; }
  if !err_is("${A:}", &vs, true, "environment: unsupported operator: :") { ok = false; }
  if !err_is("${A.b}", &vs, true, "environment: unsupported operator: .") { ok = false; }
  return assert(ok, "unsupported operators are errors");
}

fn t19() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "");
  add_var(&mut vs, "B", "bee");
  var ok = text_is("${A:-${B}}", &vs, true, "bee");
  if !text_is("${A:-${C:-deep}}", &vs, true, "deep") { ok = false; }
  if !text_is("${B:-${A}}", &vs, true, "bee") { ok = false; }
  if !err_is("${A:-${NOPE}}", &vs, true, "environment: undefined variable: NOPE") { ok = false; }
  var vs2 = mk_vars();
  add_var(&mut vs2, "A", "set");
  if !text_is("${A:-${NOPE}}", &vs2, true, "set") { ok = false; }
  return assert(ok, "nested references expand when an operand is selected");
}

fn t20() -> TestResult {
  var vs = mk_vars();
  var ok = text_is("${A:-${A:-${A:-${A:-${A:-${A:-${A:-${A:-x}}}}}}}}", &vs, true, "x");
  if !err_is("${A:-${A:-${A:-${A:-${A:-${A:-${A:-${A:-${A:-x}}}}}}}}}", &vs, true, "environment: nesting too deep") { ok = false; }
  return assert(ok, "nesting is capped at eight operand levels");
}

fn t21() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "");
  add_var(&mut vs, "B", "2");
  var want1 = svec3("A", "B", "NOPE");
  var ok = names_is("${A}${B}${A}${NOPE}", &vs, false, &want1);
  var vs2 = mk_vars();
  add_var(&mut vs2, "A", "set");
  var want2 = svec1("A");
  if !names_is("${A:-${B}}", &vs2, true, &want2) { ok = false; }
  var want3 = svec2("A", "B");
  if !names_is("${A:-${B}}", &vs, true, &want3) { ok = false; }
  var want0 = svec0();
  if !names_is("'${A}'", &vs, true, &want0) { ok = false; }
  return assert(ok, "referenced names are distinct and evaluation-scoped");
}

fn t22() -> TestResult {
  var pairs = Vec[Str].new();
  pairs.push("A=1");
  pairs.push("B=two=three");
  pairs.push("NOEQ");
  pairs.push("=skip");
  pairs.push("A=2");
  var ok = pairs_text_is("${A}|${B}", &pairs, true, "1|two=three");
  let vs = env_vars_from_pairs(&pairs);
  if !text_is("${A}", &vs, true, "1") { ok = false; }
  var empty = Vec[Str].new();
  if !pairs_err_is("${A}", &empty, true, "environment: undefined variable: A") { ok = false; }
  return assert(ok, "pairs input: first duplicate wins, malformed skipped");
}

fn t23() -> TestResult {
  var vs = mk_vars();
  add_var(&mut vs, "A", "café");
  var ok = text_is("", &vs, true, "");
  if !text_is("plain $ text {}", &vs, true, "plain $ text {}") { ok = false; }
  if !text_is("café ${A}", &vs, true, "café café") { ok = false; }
  if !text_is("'café'", &vs, true, "café") { ok = false; }
  return assert(ok, "empty and plain input; non-ASCII passes through");
}

fn main() -> Int {
  io.println("=== xiom.environment conformance tests ===");
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
    io.println("xiom.environment: all tests passed");
  } else {
    io.println("xiom.environment: tests failed");
  }
  return failed;
}
