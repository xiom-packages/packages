// XIOM -- xiom.lexing conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.lexing module against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module lexing_tests
use xiom.io; use xiom.test; use xiom.lexing;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every token check
// below is routed through streq/scan_is instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// The lexer used by most tests: keywords "let" and "if"; operators "=", "==",
// "-", "->", "+" and "*".
fn make_lx() -> Lexer {
  var lx = lexer_new();
  lexer_add_keyword(&mut lx, "let");
  lexer_add_keyword(&mut lx, "if");
  lexer_add_operator(&mut lx, "=");
  lexer_add_operator(&mut lx, "==");
  lexer_add_operator(&mut lx, "-");
  lexer_add_operator(&mut lx, "->");
  lexer_add_operator(&mut lx, "+");
  lexer_add_operator(&mut lx, "*");
  return lx;
}

fn w1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn w2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn w3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
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

fn w5(a: Str, b: Str, c: Str, d: Str, e: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

fn w6(a: Str, b: Str, c: Str, d: Str, e: Str, f: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

fn wi6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

// True when scanning `text` yields exactly the wanted kinds and texts.
fn scan_is(lx: &Lexer, text: Str, want_kinds: &Vec[Str], want_texts: &Vec[Str]) -> Bool {
  let r = lexer_scan(lx, text);
  match r {
    Ok(t) => {
      if t.kinds.len() != want_kinds.len() { return false; }
      if t.texts.len() != want_texts.len() { return false; }
      var i = 0;
      while i < want_kinds.len() {
        if !streq(t.kinds[i], want_kinds[i]) { return false; }
        if !streq(t.texts[i], want_texts[i]) { return false; }
        i = i + 1;
      }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

// True when scanning `text` fails with exactly the error `want`.
fn scan_err_is(lx: &Lexer, text: Str, want: Str) -> Bool {
  let r = lexer_scan(lx, text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when the scan of `text` records exactly the wanted byte offsets.
fn scan_starts_is(lx: &Lexer, text: Str, want_starts: &Vec[Int]) -> Bool {
  let r = lexer_scan(lx, text);
  match r {
    Ok(t) => {
      if t.starts.len() != want_starts.len() { return false; }
      var i = 0;
      while i < want_starts.len() {
        let got: Int = t.starts[i];
        let want: Int = want_starts[i];
        if got != want { return false; }
        i = i + 1;
      }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  var lx = make_lx();
  let wk = w2("ident", "ident");
  let wt = w2("foo", "bar");
  return assert(scan_is(&lx, "foo bar", &wk, &wt), "identifiers: maximal [A-Za-z_][A-Za-z0-9_]* runs");
}

fn t2() -> TestResult {
  var lx = make_lx();
  let wk = w4("kw", "ident", "kw", "ident");
  let wt = w4("let", "x", "if", "y");
  return assert(scan_is(&lx, "let x if y", &wk, &wt), "keywords vs idents: exact registered text is kw");
}

fn t3() -> TestResult {
  var lx = make_lx();
  let wk = w4("kw", "kw", "ident", "ident");
  let wt = w4("let", "if", "letx", "Let");
  return assert(scan_is(&lx, "let if letx Let", &wk, &wt), "two keywords: exact match, case-sensitive, prefixes stay idents");
}

fn t4() -> TestResult {
  var lx = make_lx();
  let wk = w4("int", "int", "int", "int");
  let wt = w4("0", "42", "007", "1234567890");
  return assert(scan_is(&lx, "0 42 007 1234567890", &wk, &wt), "integers: [0-9]+ verbatim, leading zeros preserved");
}

fn t5() -> TestResult {
  var lx = make_lx();
  let wk = w1("str");
  let wt = w1("say \"hi\"");
  return assert(scan_is(&lx, "\"say \\\"hi\\\"\"", &wk, &wt), "strings: escaped quotes decode");
}

fn t6() -> TestResult {
  var lx = make_lx();
  let wk = w1("str");
  let wt = w1("a\\b\nc\td");
  return assert(scan_is(&lx, "\"a\\\\b\\nc\\td\"", &wk, &wt), "strings: backslash, LF and TAB escapes decode");
}

fn t7() -> TestResult {
  var lx = make_lx();
  let wk = w1("str");
  let we = w1("");
  var ok = scan_is(&lx, "\"\"", &wk, &we);
  let wt = w1("  ");
  if !scan_is(&lx, "\"  \"", &wk, &wt) { ok = false; }
  return assert(ok, "strings: empty literal and whitespace-only literal");
}

fn t8() -> TestResult {
  var lx = make_lx();
  let wk = w3("ident", "op", "ident");
  let wt = w3("a", "==", "b");
  var ok = scan_is(&lx, "a==b", &wk, &wt);
  let wt2 = w3("a", "=", "b");
  if !scan_is(&lx, "a=b", &wk, &wt2) { ok = false; }
  return assert(ok, "operators: longest match == beats =");
}

fn t9() -> TestResult {
  var lx = make_lx();
  let wk = w3("ident", "op", "ident");
  let wt = w3("x", "->", "y");
  var ok = scan_is(&lx, "x->y", &wk, &wt);
  let wt2 = w3("x", "-", "y");
  if !scan_is(&lx, "x-y", &wk, &wt2) { ok = false; }
  return assert(ok, "operators: longest match -> beats -");
}

fn t10() -> TestResult {
  var lx = make_lx();
  let wk = w5("op", "op", "op", "op", "op");
  let wt = w5("==", "->", "-", "+", "*");
  return assert(scan_is(&lx, "==->-+*", &wk, &wt), "operators: operator-only input splits by longest match");
}

fn t11() -> TestResult {
  var lx = make_lx();
  let wk = w6("kw", "ident", "op", "int", "op", "ident");
  let wt = w6("let", "x", "=", "42", "-", "y");
  var ok = scan_is(&lx, "let x = 42 - y", &wk, &wt);
  let ws = wi6(0, 4, 6, 8, 11, 13);
  if !scan_starts_is(&lx, "let x = 42 - y", &ws) { ok = false; }
  return assert(ok, "mixed expression: kinds, texts and byte positions");
}

fn t12() -> TestResult {
  var lx = make_lx();
  let wk = w2("kw", "ident");
  let wt = w2("let", "x");
  return assert(scan_is(&lx, "\t let\n\n x \r\n", &wk, &wt), "whitespace: space, tab, LF and CR are skipped");
}

fn t13() -> TestResult {
  var lx = make_lx();
  var ok = scan_err_is(&lx, "a @b", "lexing: unexpected byte at 2");
  if !scan_err_is(&lx, "$", "lexing: unexpected byte at 0") { ok = false; }
  return assert(ok, "errors: unexpected byte reports its position");
}

fn t14() -> TestResult {
  var lx = make_lx();
  let we = Vec[Str].new();
  let we2 = Vec[Str].new();
  var ok = scan_is(&lx, "", &we, &we2);
  let we3 = Vec[Str].new();
  let we4 = Vec[Str].new();
  if !scan_is(&lx, "   ", &we3, &we4) { ok = false; }
  let we5 = Vec[Str].new();
  let we6 = Vec[Str].new();
  if !scan_is(&lx, "\n\t\r ", &we5, &we6) { ok = false; }
  return assert(ok, "empty input: no tokens for empty or whitespace-only text");
}

fn t15() -> TestResult {
  var lx = make_lx();
  let r = lexer_scan(&lx, "let");
  match r {
    Ok(t) => {
      var ok = lexer_token_count(&t) == 1;
      if !streq(lexer_kind(&t, -1), "") { ok = false; }
      if !streq(lexer_kind(&t, 1), "") { ok = false; }
      if !streq(lexer_text(&t, -5), "") { ok = false; }
      if !streq(lexer_text(&t, 9), "") { ok = false; }
      if lexer_start(&t, -1) != -1 { ok = false; }
      if lexer_start(&t, 1) != -1 { ok = false; }
      return assert(ok, "accessors: out-of-range indices return \"\" and -1");
    },
    Err(_) => { return assert(false, "accessors: out-of-range scan failed"); },
  }
  return assert(false, "unreachable");
}

fn t16() -> TestResult {
  var lx = make_lx();
  let wk = w4("ident", "ident", "ident", "ident");
  let wt = w4("_x", "__", "_9", "x_");
  return assert(scan_is(&lx, "_x __ _9 x_", &wk, &wt), "identifiers: underscores start and continue tokens");
}

fn t17() -> TestResult {
  var lx = make_lx();
  let wk = w4("ident", "int", "ident", "ident");
  let wt = w4("a1b2", "1", "a", "x9");
  return assert(scan_is(&lx, "a1b2 1a x9", &wk, &wt), "identifiers: digits are interior, a leading digit starts an int");
}

fn t18() -> TestResult {
  var lx = make_lx();
  let wk = w3("kw", "ident", "op");
  let wt = w3("let", "x", "=");
  var ok = scan_is(&lx, "let x =", &wk, &wt);
  if !scan_is(&lx, "let x =", &wk, &wt) { ok = false; }
  if !scan_err_is(&lx, "@", "lexing: unexpected byte at 0") { ok = false; }
  if !scan_err_is(&lx, "@", "lexing: unexpected byte at 0") { ok = false; }
  return assert(ok, "repeated scans: same input, same tokens and same error");
}

fn t19() -> TestResult {
  var lx = make_lx();
  var ok = scan_err_is(&lx, "\"abc", "lexing: unterminated string at 0");
  if !scan_err_is(&lx, "a \"b", "lexing: unterminated string at 2") { ok = false; }
  return assert(ok, "errors: unterminated string reports the opening quote");
}

fn t20() -> TestResult {
  var lx = make_lx();
  return assert(scan_err_is(&lx, "\"a\\qb\"", "lexing: invalid escape at 2"), "errors: unknown escape reports the backslash");
}

fn t21() -> TestResult {
  var lx = make_lx();
  let wk = w1("str");
  let wt = w1("= +");
  var ok = scan_is(&lx, "\"= +\"", &wk, &wt);
  let wk2 = w2("op", "str");
  let wt2 = w2("=", "x");
  if !scan_is(&lx, "=\"x\"", &wk2, &wt2) { ok = false; }
  return assert(ok, "strings: operator characters and spaces inside quotes are text");
}

fn t22() -> TestResult {
  var lx = make_lx();
  let r = lexer_scan(&lx, "let x = 7");
  match r {
    Ok(t) => {
      var ok = lexer_token_count(&t) == 4;
      if !streq(lexer_kind(&t, 0), "kw") { ok = false; }
      if !streq(lexer_text(&t, 0), "let") { ok = false; }
      if lexer_start(&t, 0) != 0 { ok = false; }
      if !streq(lexer_kind(&t, 1), "ident") { ok = false; }
      if !streq(lexer_text(&t, 1), "x") { ok = false; }
      if lexer_start(&t, 1) != 4 { ok = false; }
      if !streq(lexer_kind(&t, 2), "op") { ok = false; }
      if !streq(lexer_text(&t, 2), "=") { ok = false; }
      if lexer_start(&t, 2) != 6 { ok = false; }
      if !streq(lexer_kind(&t, 3), "int") { ok = false; }
      if !streq(lexer_text(&t, 3), "7") { ok = false; }
      if lexer_start(&t, 3) != 8 { ok = false; }
      return assert(ok, "accessors: kind, text and start for every token");
    },
    Err(_) => { return assert(false, "accessors: valid scan failed"); },
  }
  return assert(false, "unreachable");
}

fn t23() -> TestResult {
  var lx = lexer_new();
  lexer_add_keyword(&mut lx, "let");
  var ok = scan_err_is(&lx, "=", "lexing: unexpected byte at 0");
  if !scan_err_is(&lx, "let =", "lexing: unexpected byte at 4") { ok = false; }
  return assert(ok, "operators: unregistered operator bytes are errors");
}

fn t24() -> TestResult {
  var lx = make_lx();
  let wk = w3("ident", "ident", "kw");
  let wt = w3("lets", "letter", "let");
  return assert(scan_is(&lx, "lets letter let", &wk, &wt), "keywords: only the exact text matches, not prefixes");
}

fn main() -> Int {
  io.println("=== xiom.lexing conformance tests ===");
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
    io.println("xiom.lexing: all tests passed");
  } else {
    io.println("xiom.lexing: tests failed");
  }
  return failed;
}
