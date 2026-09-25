// XIOM -- xiom.gbnf conformance tests (30 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the pure-XIOM xiom.gbnf module against its SPEC.md: the supported
// GBNF subset, the structural checks, the error catalog and the canonical
// parse -> emit -> parse round-trip.

module gbnf_tests
use xiom.io; use xiom.test; use xiom.gbnf;
use xiom.string;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every name and text
// check below is routed through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when parsing `text` fails with exactly the error `want`.
fn err_is(text: Str, want: Str) -> Bool {
  let r = gbnf_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when parsing `text` succeeds with exactly `want` rules.
fn rules_are(text: Str, want: Int) -> Bool {
  let r = gbnf_parse(text);
  match r {
    Ok(g) => { return gbnf_rule_count(&g) == want; },
    Err(_) => { return false; },
  }
  return false;
}

// True when the canonical text of `text` is `want` and re-canonicalizing it
// yields `want` again (parse -> emit -> parse -> emit is idempotent).
fn canon_is(text: Str, want: Str) -> Bool {
  let r = gbnf_parse(text);
  match r {
    Ok(g) => {
      let once = gbnf_emit(&g);
      if !streq(once, want) { return false; }
      let r2 = gbnf_parse(once);
      match r2 {
        Ok(g2) => { return streq(gbnf_emit(&g2), want); },
        Err(_) => { return false; },
      }
    },
    Err(_) => { return false; },
  }
  return false;
}

// True when the references of rule `rule` equal `want`.
fn refs_are(g: &GbnfGrammar, rule: Int, want: &Vec[Str]) -> Bool {
  let got = gbnf_rule_refs(g, rule);
  if got.len() != want.len() { return false; }
  var i = 0;
  while i < want.len() {
    let a: Str = got[i];
    let b: Str = want[i];
    if compare.str_compare(a, b) != 0 { return false; }
    i = i + 1;
  }
  return true;
}

fn w1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn w4(a: Str, b: Str, c: Str, d: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn t1() -> TestResult {
  let text = "root ::= \"hello\"\n";
  let r = gbnf_parse(text);
  var ok = false;
  match r {
    Ok(g) => {
      ok = gbnf_rule_count(&g) == 1;
      if !streq(gbnf_root_name(&g), "root") { ok = false; }
      if !streq(gbnf_rule_name(&g, 0), "root") { ok = false; }
      if !gbnf_has_rule(&g, "root") { ok = false; }
      if gbnf_has_rule(&g, "missing") { ok = false; }
      if gbnf_node_count(&g, 0) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !canon_is(text, text) { ok = false; }
  return assert(ok, "simple rule: parse, accessors and canonical emit");
}

fn t2() -> TestResult {
  let text = "root ::= a\nb ::= \"x\"\nc ::= b\na ::= \"y\"\n";
  let r = gbnf_parse(text);
  var ok = false;
  match r {
    Ok(g) => {
      ok = gbnf_rule_count(&g) == 4;
      if !streq(gbnf_rule_name(&g, 0), "root") { ok = false; }
      if !streq(gbnf_rule_name(&g, 1), "b") { ok = false; }
      if !streq(gbnf_rule_name(&g, 2), "c") { ok = false; }
      if !streq(gbnf_rule_name(&g, 3), "a") { ok = false; }
      if !streq(gbnf_root_name(&g), "root") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !canon_is(text, text) { ok = false; }
  return assert(ok, "ordered rule list: names and emission keep definition order");
}

fn t3() -> TestResult {
  let text = "root ::= \"a\" | \"b\" | \"c\"";
  var ok = canon_is(text, "root ::= \"a\" | \"b\" | \"c\"\n");
  let r = gbnf_parse(text);
  match r {
    Ok(g) => { if gbnf_node_count(&g, 0) != 4 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "alternation: n-ary tree with canonical spacing");
}

fn t4() -> TestResult {
  var ok = canon_is("root ::= \"a\" \"b\" \"c\"", "root ::= \"a\" \"b\" \"c\"\n");
  if !canon_is("root ::= \"a\"\n  \"b\" \"c\"", "root ::= \"a\" \"b\" \"c\"\n") { ok = false; }
  let r = gbnf_parse("root ::= \"a\" \"b\" \"c\"");
  match r {
    Ok(g) => { if gbnf_node_count(&g, 0) != 4 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "sequence: whitespace and newlines between terms normalized");
}

fn t5() -> TestResult {
  var ok = canon_is("root ::= \"a\" (\"b\" | \"c\") \"d\"", "root ::= \"a\" (\"b\" | \"c\") \"d\"\n");
  if !canon_is("root ::= ((\"x\"))", "root ::= \"x\"\n") { ok = false; }
  if !canon_is("root ::= (\"a\" \"b\") \"c\"", "root ::= \"a\" \"b\" \"c\"\n") { ok = false; }
  if !canon_is("root ::= \"a\" | \"b\" \"c\"", "root ::= \"a\" | \"b\" \"c\"\n") { ok = false; }
  return assert(ok, "grouping: transparency, precedence and required parentheses");
}

fn t6() -> TestResult {
  let text = "root ::= \"a\"* \"b\"+ \"c\"?";
  var ok = canon_is(text, "root ::= \"a\"* \"b\"+ \"c\"?\n");
  let r = gbnf_parse(text);
  match r {
    Ok(g) => { if gbnf_node_count(&g, 0) != 7 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "repetition: *, + and ? suffixes");
}

fn t7() -> TestResult {
  var ok = canon_is("root ::= (\"a\" | \"b\")* (\"c\" \"d\")+", "root ::= (\"a\" | \"b\")* (\"c\" \"d\")+\n");
  if !err_is("root ::= \"a\" * \"b\"", "gbnf: unexpected byte at 13") { ok = false; }
  if !err_is("root ::= \"a\"*?", "gbnf: unexpected byte at 13") { ok = false; }
  return assert(ok, "repetition: groups need parentheses; suffixes must be adjacent");
}

fn t8() -> TestResult {
  let text = "root ::= \"\\x41\\n\\t\\r\\\"\\\\\"";
  let want = "root ::= \"A\\n\\t\\r\\\"\\\\\"\n";
  var ok = canon_is(text, want);
  if !canon_is("root ::= \"\\x4a\"", "root ::= \"J\"\n") { ok = false; }
  return assert(ok, "string escapes: \\xNN \\n \\t \\r \\\" \\\\ decode and re-escape");
}

fn t9() -> TestResult {
  var ok = canon_is("root ::= \"a\nb\"", "root ::= \"a\\nb\"\n");
  if !canon_is("root ::= \"a\rb\"", "root ::= \"a\\rb\"\n") { ok = false; }
  if !canon_is("root ::= \"a\tb\"", "root ::= \"a\\tb\"\n") { ok = false; }
  return assert(ok, "string literals may span lines; control bytes canonicalize");
}

fn t10() -> TestResult {
  var ok = canon_is("root ::= \"\\x01\\x7F\"", "root ::= \"\\x01\\x7f\"\n");
  if !canon_is("root ::= [\\x00-\\x1f]", "root ::= [\\x00-\\x1f]\n") { ok = false; }
  return assert(ok, "control bytes emit as lower-case \\xNN escapes");
}

fn t11() -> TestResult {
  let text = "root ::= [a-z] [^0-9] [abc]";
  var ok = canon_is(text, "root ::= [a-z] [^0-9] [abc]\n");
  let r = gbnf_parse(text);
  match r {
    Ok(g) => { if gbnf_node_count(&g, 0) != 4 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "character classes: ranges, negation and literal sets");
}

fn t12() -> TestResult {
  var ok = canon_is("root ::= [-a] [a-] [a\\-z]", "root ::= [\\-a] [a\\-] [a\\-z]\n");
  return assert(ok, "character classes: - is a literal at the edges and when escaped");
}

fn t13() -> TestResult {
  let text = "root ::= [\\]\\\\\\^\\-\\n]";
  let want = "root ::= [\\]\\\\\\^\\-\\n]\n";
  return assert(canon_is(text, want), "character classes: ] \\ ^ - and \\n escapes");
}

fn t14() -> TestResult {
  var ok = canon_is("root ::= [\\x00-\\x1F\\x7f]", "root ::= [\\x00-\\x1f\\x7f]\n");
  if !canon_is("root ::= [A-Z]", "root ::= [A-Z]\n") { ok = false; }
  return assert(ok, "character classes: hex escapes and hex range endpoints");
}

fn t15() -> TestResult {
  let text = "# leading\nroot ::= \"a\" # trailing\n  | \"b\"\n# done\n";
  var ok = canon_is(text, "root ::= \"a\" | \"b\"\n");
  if !canon_is("# only a comment", "") { ok = false; }
  if !rules_are("# leading\n\n root ::= \"a\" # trailing\n", 1) { ok = false; }
  return assert(ok, "comments and whitespace are dropped by the canonical form");
}

fn t16() -> TestResult {
  var ok = canon_is("root ::= \"a#b\" # real comment", "root ::= \"a#b\"\n");
  if !canon_is("root ::= \"#\"", "root ::= \"#\"\n") { ok = false; }
  return assert(ok, "a hash inside a string literal is data, not a comment");
}

fn t17() -> TestResult {
  var ok = canon_is("root::=\"a\"|\"b\"", "root ::= \"a\" | \"b\"\n");
  if !canon_is("root::=  \"a\"\"b\"  ", "root ::= \"a\" \"b\"\n") { ok = false; }
  return assert(ok, "compact whitespace-free input is accepted and canonicalized");
}

fn t18() -> TestResult {
  let text = "root ::= a b\na ::= \"x\"\nb ::= a\n";
  var ok = canon_is(text, text);
  if !rules_are(text, 3) { ok = false; }
  if !gbnf_has_rule_test() { ok = false; }
  return assert(ok, "consecutive rule lines and forward references");
}

// Helper for t18: forward references resolve after the whole grammar is read.
fn gbnf_has_rule_test() -> Bool {
  let r = gbnf_parse("root ::= a\nb ::= a\na ::= \"x\"\n");
  match r {
    Ok(g) => { return gbnf_has_rule(&g, "a"); },
    Err(_) => { return false; },
  }
  return false;
}

fn t19() -> TestResult {
  let text = "root ::= a b (c | a)\na ::= \"x\"\nb ::= a\nc ::= \"z\"\n";
  let r = gbnf_parse(text);
  var ok = false;
  match r {
    Ok(g) => {
      let want0 = w4("a", "b", "c", "a");
      ok = refs_are(&g, 0, &want0);
      let want1 = w1("a");
      if !refs_are(&g, 2, &want1) { ok = false; }
      let none = Vec[Str].new();
      if !refs_are(&g, 3, &none) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "rule references are reported in source order");
}

fn t20() -> TestResult {
  var ok = err_is("a ::= \"x\"\na ::= \"y\"", "gbnf: duplicate rule \"a\" at 10");
  if !err_is("root ::= \"a\"\nroot ::= \"b\"", "gbnf: duplicate rule \"root\" at 13") { ok = false; }
  return assert(ok, "duplicate rule names are rejected with the definition offset");
}

fn t21() -> TestResult {
  var ok = err_is("root ::= missing b\nb ::= \"x\"\n", "gbnf: unresolved reference \"missing\" in rule \"root\"");
  if !err_is("root ::= a\na ::= b\n", "gbnf: unresolved reference \"b\" in rule \"a\"") { ok = false; }
  return assert(ok, "unresolved rule references are rejected");
}

fn t22() -> TestResult {
  var ok = err_is("root ::= \"abc", "gbnf: unterminated string at 9");
  if !err_is("root ::= [a-z", "gbnf: unterminated character class at 9") { ok = false; }
  if !err_is("root ::= (\"a\"", "gbnf: unterminated group at 9") { ok = false; }
  return assert(ok, "unterminated string, class and group report the opening offset");
}

fn t23() -> TestResult {
  var ok = err_is("root ::= []", "gbnf: empty character class at 9");
  if !err_is("root ::= [^]", "gbnf: empty character class at 9") { ok = false; }
  if !err_is("root ::= [z-a]", "gbnf: reversed character range at 10") { ok = false; }
  return assert(ok, "empty classes and reversed ranges are malformed");
}

fn t24() -> TestResult {
  var ok = err_is("root ::= ", "gbnf: empty expression at 9");
  if !err_is("root ::= | \"x\"", "gbnf: empty expression at 9") { ok = false; }
  if !err_is("root ::= \"x\" |", "gbnf: empty expression at 14") { ok = false; }
  if !err_is("root ::= ()", "gbnf: empty expression at 10") { ok = false; }
  if !err_is("root ::= \"a\" | | \"b\"", "gbnf: empty expression at 15") { ok = false; }
  return assert(ok, "empty rule bodies, alternatives and groups are malformed");
}

fn t25() -> TestResult {
  var ok = err_is("root ::= \"\\q\"", "gbnf: invalid escape in string at 10");
  if !err_is("root ::= [\\q]", "gbnf: invalid escape in character class at 10") { ok = false; }
  if !err_is("root ::= \"\\x4\"", "gbnf: invalid hex escape at 10") { ok = false; }
  if !err_is("root ::= \"abc\\", "gbnf: invalid escape in string at 13") { ok = false; }
  if !err_is("root ::= \"\\x00\"", "gbnf: NUL byte is not supported at 10") { ok = false; }
  return assert(ok, "unsupported and malformed escapes are rejected");
}

fn t26() -> TestResult {
  var ok = err_is("root ::= \"a\"\n)", "gbnf: expected rule name at 13");
  if !err_is("root = \"a\"", "gbnf: expected '::=' at 5") { ok = false; }
  if !err_is("root ::= @", "gbnf: unexpected byte at 9") { ok = false; }
  if !err_is("1abc ::= \"x\"", "gbnf: expected rule name at 0") { ok = false; }
  if !err_is("root ::= \"a\"\nfoo", "gbnf: unresolved reference \"foo\" in rule \"root\"") { ok = false; }
  return assert(ok, "top-level junk, missing ::= and invalid rule names are rejected");
}

fn t27() -> TestResult {
  let r = gbnf_parse("");
  var ok = false;
  match r {
    Ok(g) => {
      ok = gbnf_rule_count(&g) == 0;
      if !streq(gbnf_root_name(&g), "") { ok = false; }
      if !streq(gbnf_emit(&g), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !rules_are("# only a comment\n\n", 0) { ok = false; }
  let v = gbnf_validate("# only a comment");
  match v {
    Ok(n) => { if n != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let v2 = gbnf_validate("root ::= \"a\"");
  match v2 {
    Ok(n2) => { if n2 != 1 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty grammar, comments-only input and gbnf_validate");
}

fn t28() -> TestResult {
  let v = gbnf_validate("root ::= @");
  var ok = false;
  match v {
    Ok(_) => { ok = false; },
    Err(e) => { ok = string.str_starts_with(e, "gbnf: "); },
  }
  let r = gbnf_parse("root ::= root \"a\" | \"b\"");
  match r {
    Ok(g) => {
      if gbnf_rule_count(&g) != 1 { ok = false; }
      let want = w1("root");
      if !refs_are(&g, 0, &want) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "gbnf_validate reports gbnf: errors; left recursion is accepted");
}

fn t29() -> TestResult {
  let text = "# expression grammar\nroot    ::= expr\nexpr    ::= term ((\"+\" | \"-\") term)*\nterm    ::= factor ((\"*\" | \"/\") factor)*\nfactor  ::= number | \"(\" expr \")\"\nnumber  ::= [0-9]+ (\".\" [0-9]+)?\nws      ::= [ \\t]*\n";
  let want = "root ::= expr\nexpr ::= term ((\"+\" | \"-\") term)*\nterm ::= factor ((\"*\" | \"/\") factor)*\nfactor ::= number | \"(\" expr \")\"\nnumber ::= [0-9]+ (\".\" [0-9]+)?\nws ::= [ \\t]*\n";
  var ok = canon_is(text, want);
  if !rules_are(text, 6) { ok = false; }
  return assert(ok, "realistic grammar: canonical form and idempotent round-trip");
}

fn t30() -> TestResult {
  let r = gbnf_parse("root ::= \"a\"\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = streq(gbnf_rule_name(&g, -1), "");
      if !streq(gbnf_rule_name(&g, 1), "") { ok = false; }
      if gbnf_node_count(&g, -1) != -1 { ok = false; }
      if gbnf_node_count(&g, 1) != -1 { ok = false; }
      let rr = gbnf_rule_refs(&g, 9);
      if rr.len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let re = gbnf_parse("");
  match re {
    Ok(e) => {
      if !streq(gbnf_root_name(&e), "") { ok = false; }
      if !streq(gbnf_rule_name(&e, 0), "") { ok = false; }
      if e.names.len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "out-of-range accessors return \"\" and -1");
}

fn main() -> Int {
  io.println("=== xiom.gbnf conformance tests ===");
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
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.gbnf: all tests passed");
  } else {
    io.println("xiom.gbnf: tests failed");
  }
  return failed;
}
