// XIOM -- xiom.properties conformance tests (21 checks)
// Greenfield package: prove the pure-XIOM xiom.properties module against its
// documented logical-line grammar, escape rules and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: simple pairs, '=' and ':' separators, whitespace separators,
// '#'/'!' comments, leading whitespace on keys, one- and two-step
// continuations, the \n \t \r \f \\ escapes, unknown escapes taken literally,
// \uXXXX UTF-8 decoding, malformed \u errors, escaped separators in keys,
// values containing '=' and ':', duplicate last-wins/position, missing keys,
// props_set replace/append immutability, emit escaping, emit -> parse round
// trips, empty/comment-only input and CRLF (plus lone CR) line endings.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/str_at/opt_str_is instead of `==`.

module properties_tests
use xiom.io; use xiom.test; use xiom.properties;
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

// Byte `i` of `s` widened to 0..255 (byte_at is signed above 0x7F).
fn byte_is(s: Str, i: Int, want: Int) -> Bool {
  if i < 0 || i >= s.len() { return false; }
  return ((string.byte_at(s, i) as Int) & 0xFF) == want;
}

// True when the text fails to parse with a "properties: " error message.
fn parse_err_prefix(text: Str) -> Bool {
  let r = props_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "properties: "); },
  }
  return false;
}

fn t1() -> TestResult {
  let r = props_parse("A=1\nB=two");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 2;
      if !opt_str_is(props_get(&p, "A"), "1") { ok = false; }
      if !opt_str_is(props_get(&p, "B"), "two") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "simple pairs");
}

fn t2() -> TestResult {
  let r = props_parse("A=1\nB:2\nC : 3\nD = x");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 4;
      if !opt_str_is(props_get(&p, "A"), "1") { ok = false; }
      if !opt_str_is(props_get(&p, "B"), "2") { ok = false; }
      if !opt_str_is(props_get(&p, "C"), "3") { ok = false; }
      if !opt_str_is(props_get(&p, "D"), "x") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "= and : separators with optional whitespace");
}

fn t3() -> TestResult {
  let r = props_parse("A 1\nB\t2\nC three words");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 3;
      if !opt_str_is(props_get(&p, "A"), "1") { ok = false; }
      if !opt_str_is(props_get(&p, "B"), "2") { ok = false; }
      if !opt_str_is(props_get(&p, "C"), "three words") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "unseparated whitespace ends the key");
}

fn t4() -> TestResult {
  let r = props_parse("# comment\n! bang\n   # indented\n\nA=1\n!B=2\n");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 1;
      if !opt_str_is(props_get(&p, "A"), "1") { ok = false; }
      if !opt_str_none(props_get(&p, "B")) { ok = false; }
      if !opt_str_none(props_get(&p, "comment")) { ok = false; }
      if !opt_str_none(props_get(&p, "bang")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "full-line # and ! comments and blank lines are ignored");
}

fn t5() -> TestResult {
  let r = props_parse("   A=1\n\tB=2\n  C : 3");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 3;
      if !opt_str_is(props_get(&p, "A"), "1") { ok = false; }
      if !opt_str_is(props_get(&p, "B"), "2") { ok = false; }
      if !opt_str_is(props_get(&p, "C"), "3") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "leading whitespace around keys is skipped");
}

fn t6() -> TestResult {
  let r = props_parse("A=one\\\ntwo\nB=x\\\n   y");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 2;
      if !opt_str_is(props_get(&p, "A"), "onetwo") { ok = false; }
      if !opt_str_is(props_get(&p, "B"), "xy") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "trailing backslash continues, leading whitespace stripped");
}

fn t7() -> TestResult {
  let r = props_parse("A=a\\\nb\\\nc\nB=x\\\\\nC=z");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 3;
      if !opt_str_is(props_get(&p, "A"), "abc") { ok = false; }
      if !opt_str_is(props_get(&p, "B"), "x\\") { ok = false; }
      if !opt_str_is(props_get(&p, "C"), "z") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "two continuations join; an even backslash run ends the line");
}

fn t8() -> TestResult {
  let r = props_parse("A=a\\nb\\tc\\rd\\\\e\nB=x\\fy");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 2;
      if !opt_str_is(props_get(&p, "A"), "a\nb\tc\rd\\e") { ok = false; }
      let b = props_get(&p, "B");
      match b {
        Some(v) => {
          if v.len() != 3 { ok = false; }
          if !byte_is(v, 0, 120) { ok = false; }
          if !byte_is(v, 1, 12) { ok = false; }
          if !byte_is(v, 2, 121) { ok = false; }
        },
        None => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "\\n \\t \\r \\f and \\\\ decode");
}

fn t9() -> TestResult {
  let r = props_parse("E=\\u00e9\nM=\\u4e2D\nA=\\u0041");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 3;
      let e = props_get(&p, "E");
      match e {
        Some(v) => {
          if v.len() != 2 { ok = false; }
          if !byte_is(v, 0, 195) { ok = false; }
          if !byte_is(v, 1, 169) { ok = false; }
        },
        None => { ok = false; },
      }
      let m = props_get(&p, "M");
      match m {
        Some(v) => {
          if v.len() != 3 { ok = false; }
          if !byte_is(v, 0, 228) { ok = false; }
          if !byte_is(v, 1, 184) { ok = false; }
          if !byte_is(v, 2, 173) { ok = false; }
        },
        None => { ok = false; },
      }
      if !opt_str_is(props_get(&p, "A"), "A") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "\\uXXXX decodes to UTF-8 (2- and 3-byte forms, mixed case)");
}

fn t10() -> TestResult {
  var ok = parse_err_prefix("A=\\u12");
  if !parse_err_prefix("A=\\uZZZZ") { ok = false; }
  if !parse_err_prefix("A=\\u00e") { ok = false; }
  if !parse_err_prefix("\\u12=1") { ok = false; }
  return assert(ok, "truncated or non-hex \\u escapes are Err");
}

fn t11() -> TestResult {
  let r = props_parse("a\\=b=1\na\\:b:c\\ d");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 2;
      if !opt_str_is(props_get(&p, "a=b"), "1") { ok = false; }
      if !opt_str_is(props_get(&p, "a:b"), "c d") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "escaped '=' ':' and space stay in the key");
}

fn t12() -> TestResult {
  let r = props_parse("A=x=y:z\nB=:x\nC = :\nD=a=b=c");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 4;
      if !opt_str_is(props_get(&p, "A"), "x=y:z") { ok = false; }
      if !opt_str_is(props_get(&p, "B"), ":x") { ok = false; }
      if !opt_str_is(props_get(&p, "C"), ":") { ok = false; }
      if !opt_str_is(props_get(&p, "D"), "a=b=c") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "values keep '=' and ':' after the first separator");
}

fn t13() -> TestResult {
  let r = props_parse("A=1\nB=2\nA=3\nB=4\nA=5");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 2;
      if !opt_str_is(props_get(&p, "A"), "5") { ok = false; }
      if !opt_str_is(props_get(&p, "B"), "4") { ok = false; }
      let ks = props_keys(&p);
      if ks.len() != 2 { ok = false; }
      if !str_at(&ks, 0, "A") { ok = false; }
      if !str_at(&ks, 1, "B") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate keys: last wins, first position kept");
}

fn t14() -> TestResult {
  let r = props_parse("A=1");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 1;
      if !opt_str_none(props_get(&p, "missing")) { ok = false; }
      if !opt_str_none(props_get(&p, "a")) { ok = false; }
      if !opt_str_is(props_get(&p, "A"), "1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "missing keys yield None; keys are case-sensitive");
}

fn t15() -> TestResult {
  let r = props_parse("A=1\nB=2");
  var ok = false;
  match r {
    Ok(p) => {
      let q = props_set(&p, "A", "9");
      ok = props_count(&q) == 2;
      if !opt_str_is(props_get(&q, "A"), "9") { ok = false; }
      if !opt_str_is(props_get(&q, "B"), "2") { ok = false; }
      let ks = props_keys(&q);
      if !str_at(&ks, 0, "A") { ok = false; }
      if !str_at(&ks, 1, "B") { ok = false; }
      if !opt_str_is(props_get(&p, "A"), "1") { ok = false; }
      if props_count(&p) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "props_set replaces in place and returns a new Props");
}

fn t16() -> TestResult {
  let r = props_parse("A=1");
  var ok = false;
  match r {
    Ok(p) => {
      let q = props_set(&p, "C", "3");
      ok = props_count(&q) == 2;
      let ks = props_keys(&q);
      if !str_at(&ks, 1, "C") { ok = false; }
      if !opt_str_is(props_get(&q, "C"), "3") { ok = false; }
      if props_count(&p) != 1 { ok = false; }
      if !opt_str_none(props_get(&p, "C")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "props_set appends a new key and leaves the original alone");
}

fn t17() -> TestResult {
  var p = Props{ keys: Vec[Str].new(); values: Vec[Str].new(); };
  p.keys.push("plain"); p.values.push("x");
  p.keys.push("eq=key"); p.values.push("y");
  p.keys.push(" sp key"); p.values.push("v");
  p.keys.push("a\nb"); p.values.push("l1\nl2");
  p.keys.push("path"); p.values.push("a\\b");
  p.keys.push("colon:key"); p.values.push(":lead");
  p.keys.push("hash#key"); p.values.push("#lead");
  p.keys.push("bang!key"); p.values.push("!lead");
  p.keys.push("vspace"); p.values.push(" lead");
  p.keys.push("café"); p.values.push("café");
  let got = props_emit(&p);
  let want = "plain=x\neq\\=key=y\n\\ sp\\ key=v\na\\nb=l1\\nl2\npath=a\\\\b\ncolon\\:key=\\:lead\nhash\\#key=\\#lead\nbang\\!key=\\!lead\nvspace=\\ lead\ncafé=café";
  return assert(streq(got, want), "emit escapes controls, key specials and leading spaces");
}

fn t18() -> TestResult {
  let r1 = props_parse("A=plain\nB=two words\nC=x=y:z\nD=a\\ b\nE=\nF=café\nG=\\ lead\nH=\\#lead\nI=tab\\tend\nJ=\\=x");
  var ok = false;
  match r1 {
    Ok(p) => {
      let out = props_emit(&p);
      let r2 = props_parse(out);
      match r2 {
        Ok(q) => {
          ok = props_count(&q) == props_count(&p);
          if !opt_str_is(props_get(&q, "A"), "plain") { ok = false; }
          if !opt_str_is(props_get(&q, "B"), "two words") { ok = false; }
          if !opt_str_is(props_get(&q, "C"), "x=y:z") { ok = false; }
          if !opt_str_is(props_get(&q, "D"), "a b") { ok = false; }
          if !opt_str_is(props_get(&q, "E"), "") { ok = false; }
          if !opt_str_is(props_get(&q, "F"), "café") { ok = false; }
          if !opt_str_is(props_get(&q, "G"), " lead") { ok = false; }
          if !opt_str_is(props_get(&q, "H"), "#lead") { ok = false; }
          if !opt_str_is(props_get(&q, "I"), "tab\tend") { ok = false; }
          if !opt_str_is(props_get(&q, "J"), "=x") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit then parse round-trips keys and values");
}

fn t19() -> TestResult {
  let e = props_parse("");
  var ok = false;
  match e {
    Ok(p) => {
      ok = props_count(&p) == 0;
      if !streq(props_emit(&p), "") { ok = false; }
      let ks = props_keys(&p);
      if ks.len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let c = props_parse("# only\n\n   \n! bang");
  match c {
    Ok(p2) => {
      if props_count(&p2) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and comment-only documents parse to zero entries");
}

fn t20() -> TestResult {
  let r = props_parse("A=1\r\nB : 2\r\n\r\n# c\r\nC=a\\\r\n  b");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 3;
      if !opt_str_is(props_get(&p, "A"), "1") { ok = false; }
      if !opt_str_is(props_get(&p, "B"), "2") { ok = false; }
      if !opt_str_is(props_get(&p, "C"), "ab") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let m = props_parse("X=1\rY=2");
  match m {
    Ok(p2) => {
      if props_count(&p2) != 2 { ok = false; }
      if !opt_str_is(props_get(&p2, "X"), "1") { ok = false; }
      if !opt_str_is(props_get(&p2, "Y"), "2") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF and lone-CR line endings parse");
}

fn t21() -> TestResult {
  let r = props_parse("A=\\q\\=\\:\\#\\!\\ \nK\\ x=1");
  var ok = false;
  match r {
    Ok(p) => {
      ok = props_count(&p) == 2;
      if !opt_str_is(props_get(&p, "A"), "q=:#! ") { ok = false; }
      if !opt_str_is(props_get(&p, "K x"), "1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "unknown escapes yield the escaped byte itself");
}

fn main() -> Int {
  io.println("=== xiom.properties conformance tests ===");
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
    io.println("xiom.properties: all tests passed");
  } else {
    io.println("xiom.properties: tests failed");
  }
  return failed;
}
