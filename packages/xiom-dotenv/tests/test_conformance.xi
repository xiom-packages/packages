// XIOM -- xiom.dotenv conformance tests (18 checks)
// Greenfield package: prove the pure-XIOM xiom.dotenv module against its
// documented dotenv grammar, quoting rules and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: simple pairs, empty values, unquoted trimming, full-line and
// trailing comments, '#' inside quotes, double-quoted escapes, single-quoted
// literals, the export prefix, duplicate last-wins/position semantics, missing
// keys, key order/copy semantics, bad escapes, unterminated quotes, malformed
// lines, emit quoting rules, emit -> parse round trips and CRLF input.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/str_at/opt_str_is instead of `==`.

module dotenv_tests
use xiom.io; use xiom.test; use xiom.dotenv;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn str_at(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  let got: Str = v[i];
  return streq(got, want);
}

fn opt_str_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_str_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// True when the text fails to parse with a "dotenv: " error message.
fn parse_err_prefix(text: Str) -> Bool {
  let r = dotenv_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "dotenv: "); },
  }
  return false;
}

fn t1() -> TestResult {
  let r = dotenv_parse("A=1\nB=two");
  var ok = false;
  match r {
    Ok(e) => {
      ok = dotenv_len(&e) == 2;
      if !dotenv_has(&e, "A") { ok = false; }
      if !dotenv_has(&e, "B") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "A"), "1") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "B"), "two") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "simple pairs");
}

fn t2() -> TestResult {
  let r = dotenv_parse("EMPTY=\nSPACES=   \nB=2");
  var ok = false;
  match r {
    Ok(e) => {
      ok = dotenv_len(&e) == 3;
      if !opt_str_is(dotenv_get(&e, "EMPTY"), "") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "SPACES"), "") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "B"), "2") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty values");
}

fn t3() -> TestResult {
  let r = dotenv_parse("A  =  hello world  \nB = \t spaced\t ");
  var ok = false;
  match r {
    Ok(e) => {
      ok = dotenv_len(&e) == 2;
      if !opt_str_is(dotenv_get(&e, "A"), "hello world") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "B"), "spaced") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "unquoted values are trimmed");
}

fn t4() -> TestResult {
  let r = dotenv_parse("# comment\n   # indented comment\n\nA=1\n");
  var ok = false;
  match r {
    Ok(e) => {
      ok = dotenv_len(&e) == 1;
      if !opt_str_is(dotenv_get(&e, "A"), "1") { ok = false; }
      if dotenv_has(&e, "comment") { ok = false; }
      if dotenv_has(&e, "indented") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "full-line comments and blank lines are ignored");
}

fn t5() -> TestResult {
  let r = dotenv_parse("A=1 # note\nB=two#three\nC=x  # c");
  var ok = false;
  match r {
    Ok(e) => {
      ok = dotenv_len(&e) == 3;
      if !opt_str_is(dotenv_get(&e, "A"), "1") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "B"), "two#three") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "C"), "x") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "trailing comments need whitespace before #");
}

fn t6() -> TestResult {
  let r = dotenv_parse("A=\"a#b\"\nB='c#d'\nC=plain#kept");
  var ok = false;
  match r {
    Ok(e) => {
      ok = dotenv_len(&e) == 3;
      if !opt_str_is(dotenv_get(&e, "A"), "a#b") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "B"), "c#d") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "C"), "plain#kept") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "# inside quotes is kept");
}

fn t7() -> TestResult {
  let r = dotenv_parse("A=\"a\\nb\\tc\\\"d\\\\e\"\nB=\"x\\ry\"");
  var ok = false;
  match r {
    Ok(e) => {
      ok = dotenv_len(&e) == 2;
      if !opt_str_is(dotenv_get(&e, "A"), "a\nb\tc\"d\\e") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "B"), "x\ry") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "double-quoted values decode \\n \\t \\r \\\" \\\\");
}

fn t8() -> TestResult {
  let r = dotenv_parse("WIN='C:\\tmp\\new'\nQ='say \"hi\"'");
  var ok = false;
  match r {
    Ok(e) => {
      ok = dotenv_len(&e) == 2;
      if !opt_str_is(dotenv_get(&e, "WIN"), "C:\\tmp\\new") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "Q"), "say \"hi\"") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "single-quoted values are literal (no escapes)");
}

fn t9() -> TestResult {
  let r = dotenv_parse("export FOO=bar\nexport  SPACED = x\nexportedFOO=y");
  var ok = false;
  match r {
    Ok(e) => {
      ok = dotenv_len(&e) == 3;
      if !opt_str_is(dotenv_get(&e, "FOO"), "bar") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "SPACED"), "x") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "exportedFOO"), "y") { ok = false; }
      if dotenv_has(&e, "export") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "export prefix is stripped only before whitespace");
}

fn t10() -> TestResult {
  let r = dotenv_parse("A=1\nB=2\nA=3\nA=4");
  var ok = false;
  match r {
    Ok(e) => {
      ok = dotenv_len(&e) == 2;
      if !opt_str_is(dotenv_get(&e, "A"), "4") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "B"), "2") { ok = false; }
      var ks = dotenv_keys(&e);
      if ks.len() != 2 { ok = false; }
      if !str_at(&ks, 0, "A") { ok = false; }
      if !str_at(&ks, 1, "B") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate keys: last wins, first position kept");
}

fn t11() -> TestResult {
  let r = dotenv_parse("A=1");
  var ok = false;
  match r {
    Ok(e) => {
      ok = !dotenv_has(&e, "missing");
      if !opt_str_none(dotenv_get(&e, "missing")) { ok = false; }
      if !opt_str_none(dotenv_get(&e, "a")) { ok = false; }
      if !opt_str_is(dotenv_get(&e, "A"), "1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "missing keys yield has=false and get=None");
}

fn t12() -> TestResult {
  let r = dotenv_parse("B=1\nA=2\nC=3");
  var ok = false;
  match r {
    Ok(e) => {
      ok = dotenv_len(&e) == 3;
      var ks = dotenv_keys(&e);
      if ks.len() != 3 { ok = false; }
      if !str_at(&ks, 0, "B") { ok = false; }
      if !str_at(&ks, 1, "A") { ok = false; }
      if !str_at(&ks, 2, "C") { ok = false; }
      ks.push("zzz");
      if dotenv_len(&e) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "keys keep document order and are copied");
}

fn t13() -> TestResult {
  var ok = parse_err_prefix("A=\"bad\\q\"");
  if !parse_err_prefix("B=\"bad\\z\"") { ok = false; }
  return assert(ok, "bad double-quote escapes are Err");
}

fn t14() -> TestResult {
  var ok = parse_err_prefix("A=\"abc");
  if !parse_err_prefix("B='abc") { ok = false; }
  return assert(ok, "unterminated quotes are Err");
}

fn t15() -> TestResult {
  var ok = parse_err_prefix("not a kv line");
  if !parse_err_prefix("=1") { ok = false; }
  if !parse_err_prefix("1BAD=x") { ok = false; }
  if !parse_err_prefix("A B=1") { ok = false; }
  if !parse_err_prefix("A=\"x\"junk") { ok = false; }
  return assert(ok, "malformed lines are Err");
}

fn t16() -> TestResult {
  var e = EnvFile{ keys: Vec[Str].new(); values: Vec[Str].new(); };
  e.keys.push("PLAIN"); e.values.push("abc");
  e.keys.push("EMPTY"); e.values.push("");
  e.keys.push("SPACED"); e.values.push("a b");
  e.keys.push("HASH"); e.values.push("a#b");
  e.keys.push("DQ"); e.values.push("a\"b");
  e.keys.push("SQ"); e.values.push("a'b");
  e.keys.push("BS"); e.values.push("a\\b");
  e.keys.push("TAB"); e.values.push("a\tb");
  e.keys.push("NONASCII"); e.values.push("café");
  e.keys.push("MULTI"); e.values.push("l1\nl2");
  let got = dotenv_emit(&e);
  let want = "PLAIN=abc\nEMPTY=\"\"\nSPACED=\"a b\"\nHASH=\"a#b\"\nDQ=\"a\\\"b\"\nSQ=\"a'b\"\nBS=a\\b\nTAB=\"a\\tb\"\nNONASCII=\"café\"\nMULTI=\"l1\\nl2\"";
  var ok = streq(got, want);
  return assert(ok, "emit quotes empty/space/#/quote/non-ASCII and re-escapes");
}

fn t17() -> TestResult {
  let r1 = dotenv_parse("A=plain\nB=two words\nC=\"x\\ny\"\nD='a#b'\nE=\nF=café\n");
  var ok = false;
  match r1 {
    Ok(e1) => {
      let emitted = dotenv_emit(&e1);
      if !string.str_contains(emitted, "\"two words\"") { ok = false; }
      let r2 = dotenv_parse(emitted);
      match r2 {
        Ok(e2) => {
          ok = dotenv_len(&e2) == 6;
          if !opt_str_is(dotenv_get(&e2, "A"), "plain") { ok = false; }
          if !opt_str_is(dotenv_get(&e2, "B"), "two words") { ok = false; }
          if !opt_str_is(dotenv_get(&e2, "C"), "x\ny") { ok = false; }
          if !opt_str_is(dotenv_get(&e2, "D"), "a#b") { ok = false; }
          if !opt_str_is(dotenv_get(&e2, "E"), "") { ok = false; }
          if !opt_str_is(dotenv_get(&e2, "F"), "café") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit then parse round-trips keys and values");
}

fn t18() -> TestResult {
  let r = dotenv_parse("A=1\r\nB=\"x\"\r\nC='y'\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      ok = dotenv_len(&e) == 3;
      if !opt_str_is(dotenv_get(&e, "A"), "1") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "B"), "x") { ok = false; }
      if !opt_str_is(dotenv_get(&e, "C"), "y") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF line endings parse");
}

fn main() -> Int {
  io.println("=== xiom.dotenv conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.dotenv: all tests passed");
  } else {
    io.println("xiom.dotenv: tests failed");
  }
  return failed;
}
