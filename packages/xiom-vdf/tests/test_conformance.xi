// XIOM -- xiom.vdf conformance tests (23 checks)
// Greenfield package: prove the pure-XIOM xiom.vdf module against its
// documented Valve KeyValues grammar, case/duplicate rules and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: simple pairs, root key order, nested fetch by dotted path,
// whitespace and CRLF tolerance, quoted escapes, unquoted values, unquoted
// key rejection, // comments, duplicate and case-insensitive lookup,
// typed lookups, empty documents, empty values, empty keys, unterminated
// strings and blocks, unexpected '}', keys without values, bad escapes,
// the depth limit, canonical emit and round trips, duplicate blocks and path
// edge cases.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq/str_at/opt_* instead of `==`.

module vdf_tests
use xiom.io; use xiom.test; use xiom.vdf;
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

fn opt_int_is(o: Option[Int], want: Int) -> Bool {
  match o {
    Some(v) => { return v == want; },
    None => { return false; },
  }
  return false;
}

fn opt_int_none(o: Option[Int]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn opt_bool_is(o: Option[Bool], want: Bool) -> Bool {
  match o {
    Some(v) => { return v == want; },
    None => { return false; },
  }
  return false;
}

fn opt_bool_none(o: Option[Bool]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn parse_ok(text: Str) -> Bool {
  let r = vdf_parse(text);
  match r {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

// True when the text fails to parse with exactly `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = vdf_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn t1() -> TestResult {
  let r = vdf_parse("\"name\" \"xiom\"");
  var ok = false;
  match r {
    Ok(d) => {
      ok = vdf_has(&d, "name");
      if !opt_str_is(vdf_get_str(&d, "name"), "xiom") { ok = false; }
      if vdf_has(&d, "missing") { ok = false; }
      if !opt_str_none(vdf_get_str(&d, "missing")) { ok = false; }
      if !opt_int_none(vdf_get_int(&d, "name")) { ok = false; }
      if !opt_bool_none(vdf_get_bool(&d, "name")) { ok = false; }
      var ks = vdf_root_keys(&d);
      if ks.len() != 1 { ok = false; }
      if !str_at(&ks, 0, "name") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "simple quoted pair");
}

fn t2() -> TestResult {
  let r = vdf_parse("\"b\" \"2\"\n\"a\" \"1\"\n\"c\" \"3\"");
  var ok = false;
  match r {
    Ok(d) => {
      var ks = vdf_root_keys(&d);
      ok = ks.len() == 3;
      if !str_at(&ks, 0, "b") { ok = false; }
      if !str_at(&ks, 1, "a") { ok = false; }
      if !str_at(&ks, 2, "c") { ok = false; }
      if !opt_str_is(vdf_get_str(&d, "a"), "1") { ok = false; }
      if !opt_str_is(vdf_get_str(&d, "b"), "2") { ok = false; }
      if !opt_str_is(vdf_get_str(&d, "c"), "3") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "root keys keep document order");
}

fn t3() -> TestResult {
  let r = vdf_parse("\"settings\"\n{\n\"player\"\n{\n\"name\" \"ada\"\n\"level\" \"7\"\n}\n}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = vdf_has(&d, "settings");
      if !vdf_has(&d, "settings.player") { ok = false; }
      if !opt_str_is(vdf_get_str(&d, "settings.player.name"), "ada") { ok = false; }
      if !opt_int_is(vdf_get_int(&d, "settings.player.level"), 7) { ok = false; }
      if vdf_has(&d, "settings.player.missing") { ok = false; }
      if !opt_str_none(vdf_get_str(&d, "settings.player.missing")) { ok = false; }
      var ks = vdf_child_keys(&d, "settings.player");
      if ks.len() != 2 { ok = false; }
      if !str_at(&ks, 0, "name") { ok = false; }
      if !str_at(&ks, 1, "level") { ok = false; }
      var rk = vdf_root_keys(&d);
      if rk.len() != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "nested fetch by dotted path");
}

fn t4() -> TestResult {
  let r = vdf_parse("  \"a\"   \"1\"  \r\n\r\n\t\"b\"\t{\r\n\t\"c\"\t\"2\"\r\n}\t");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(vdf_get_str(&d, "a"), "1");
      if !opt_str_is(vdf_get_str(&d, "b.c"), "2") { ok = false; }
      var ks = vdf_root_keys(&d);
      if ks.len() != 2 { ok = false; }
      if !str_at(&ks, 0, "a") { ok = false; }
      if !str_at(&ks, 1, "b") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "whitespace, tabs and CRLF are tolerated");
}

fn t5() -> TestResult {
  let r = vdf_parse("\"s\" \"a\\nb\\tc\\\"d\\\\e\"");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(vdf_get_str(&d, "s"), "a\nb\tc\"d\\e");
      var ks = vdf_root_keys(&d);
      if ks.len() != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "quoted strings decode \\n \\t \\\" \\\\ escapes");
}

fn t6() -> TestResult {
  let r = vdf_parse("\"ratio\" 1.5\n\"count\" 42\n\"on\" 1\n\"off\" FALSE\n\"url\" http://example.com/x\n\"flag\" true");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(vdf_get_str(&d, "ratio"), "1.5");
      if !opt_int_is(vdf_get_int(&d, "count"), 42) { ok = false; }
      if !opt_bool_is(vdf_get_bool(&d, "on"), true) { ok = false; }
      if !opt_bool_is(vdf_get_bool(&d, "off"), false) { ok = false; }
      if !opt_str_is(vdf_get_str(&d, "url"), "http://example.com/x") { ok = false; }
      if !opt_bool_is(vdf_get_bool(&d, "flag"), true) { ok = false; }
      if !opt_int_none(vdf_get_int(&d, "ratio")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "unquoted tokens are accepted as values");
}

fn t7() -> TestResult {
  var ok = parse_err_is("foo \"bar\"", "vdf: stray token: foo");
  if !parse_err_is("\"a\" \"b\" 42", "vdf: stray token: 42") { ok = false; }
  if !parse_err_is("\"a\" { baz \"c\" }", "vdf: stray token: baz") { ok = false; }
  if !parse_err_is("{ \"a\" \"b\" }", "vdf: stray token: {") { ok = false; }
  return assert(ok, "an unquoted token where a key is expected is Err");
}

fn t8() -> TestResult {
  let r = vdf_parse("// top\n\"a\" \"1\" // trailing\n// middle\n\n\"b\" \"2\"");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(vdf_get_str(&d, "a"), "1");
      if !opt_str_is(vdf_get_str(&d, "b"), "2") { ok = false; }
      var ks = vdf_root_keys(&d);
      if ks.len() != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "// line comments and blank lines are skipped");
}

fn t9() -> TestResult {
  let r = vdf_parse("\"k\" \"1\"\n\"K\" \"2\"\n\"k\" \"3\"");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(vdf_get_str(&d, "k"), "3");
      if !opt_str_is(vdf_get_str(&d, "K"), "3") { ok = false; }
      var ks = vdf_root_keys(&d);
      if ks.len() != 3 { ok = false; }
      if !str_at(&ks, 0, "k") { ok = false; }
      if !str_at(&ks, 1, "K") { ok = false; }
      if !str_at(&ks, 2, "k") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate keys: all preserved, last wins on lookup");
}

fn t10() -> TestResult {
  let r = vdf_parse("\"Settings\"\n{\n\"PlayerName\" \"ada\"\n}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(vdf_get_str(&d, "settings.playername"), "ada");
      if !opt_str_is(vdf_get_str(&d, "SETTINGS.PLAYERNAME"), "ada") { ok = false; }
      var ks = vdf_child_keys(&d, "SeTtInGs");
      if ks.len() != 1 { ok = false; }
      if !str_at(&ks, 0, "PlayerName") { ok = false; }
      var rk = vdf_root_keys(&d);
      if !str_at(&rk, 0, "Settings") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "lookup is ASCII case-insensitive, keys keep their case");
}

fn t11() -> TestResult {
  let r = vdf_parse("\"neg\" \"-42\"\n\"zero\" \"0\"\n\"pad\" \"007\"\n\"bad\" \"12x\"\n\"dash\" \"-\"\n\"plus\" \"+5\"\n\"t1\" \"1\"\n\"t2\" \"true\"\n\"t3\" \"TRUE\"\n\"f1\" \"0\"\n\"f2\" \"false\"\n\"f3\" \"False\"\n\"x\" \"yes\"");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(vdf_get_int(&d, "neg"), -42);
      if !opt_int_is(vdf_get_int(&d, "zero"), 0) { ok = false; }
      if !opt_int_is(vdf_get_int(&d, "pad"), 7) { ok = false; }
      if !opt_int_none(vdf_get_int(&d, "bad")) { ok = false; }
      if !opt_int_none(vdf_get_int(&d, "dash")) { ok = false; }
      if !opt_int_none(vdf_get_int(&d, "plus")) { ok = false; }
      if !opt_bool_is(vdf_get_bool(&d, "t1"), true) { ok = false; }
      if !opt_bool_is(vdf_get_bool(&d, "t2"), true) { ok = false; }
      if !opt_bool_is(vdf_get_bool(&d, "t3"), true) { ok = false; }
      if !opt_bool_is(vdf_get_bool(&d, "f1"), false) { ok = false; }
      if !opt_bool_is(vdf_get_bool(&d, "f2"), false) { ok = false; }
      if !opt_bool_is(vdf_get_bool(&d, "f3"), false) { ok = false; }
      if !opt_bool_none(vdf_get_bool(&d, "x")) { ok = false; }
      if !opt_int_none(vdf_get_int(&d, "t2")) { ok = false; }
      if !opt_bool_none(vdf_get_bool(&d, "neg")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "typed lookups parse decimal ints and 0/1/true/false");
}

fn t12() -> TestResult {
  var ok = false;
  let r1 = vdf_parse("");
  match r1 {
    Ok(d) => {
      var ks = vdf_root_keys(&d);
      ok = ks.len() == 0;
      if !streq(vdf_emit(&d), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = vdf_parse("// c\n\n  \n");
  match r2 {
    Ok(d2) => {
      var ks2 = vdf_root_keys(&d2);
      if ks2.len() != 0 { ok = false; }
      if !streq(vdf_emit(&d2), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and comment-only documents emit nothing");
}

fn t13() -> TestResult {
  let r = vdf_parse("\"a\" \"\"");
  var ok = false;
  match r {
    Ok(d) => {
      ok = vdf_has(&d, "a");
      if !opt_str_is(vdf_get_str(&d, "a"), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !parse_err_is("\"\" \"x\"", "vdf: empty key") { ok = false; }
  if !parse_err_is("\"\"", "vdf: empty key") { ok = false; }
  return assert(ok, "empty values are legal, empty keys are Err");
}

fn t14() -> TestResult {
  var ok = parse_err_is("\"a\" \"unterminated", "vdf: unterminated quoted string");
  if !parse_err_is("\"a\" \"x\ny\"", "vdf: unterminated quoted string") { ok = false; }
  if !parse_err_is("\"a\\\"", "vdf: unterminated quoted string") { ok = false; }
  return assert(ok, "unterminated quoted strings are Err");
}

fn t15() -> TestResult {
  var ok = parse_err_is("\"a\" { \"b\" \"1\"", "vdf: unterminated block");
  if !parse_err_is("\"a\" { \"b\" { }", "vdf: unterminated block") { ok = false; }
  if !parse_err_is("\"a\" {", "vdf: unterminated block") { ok = false; }
  return assert(ok, "unterminated blocks are Err at EOF");
}

fn t16() -> TestResult {
  var ok = parse_err_is("}", "vdf: unexpected '}'");
  if !parse_err_is("\"a\" \"1\" }", "vdf: unexpected '}'") { ok = false; }
  if !parse_err_is("\"a\" { } }", "vdf: unexpected '}'") { ok = false; }
  return assert(ok, "a '}' with no open block is Err");
}

fn t17() -> TestResult {
  var ok = parse_err_is("\"a\"", "vdf: key without value: a");
  if !parse_err_is("\"a\" }", "vdf: key without value: a") { ok = false; }
  if !parse_err_is("\"a\" \"b\"\n\"c\"", "vdf: key without value: c") { ok = false; }
  if !parse_err_is("\"a\" { \"b\" }", "vdf: key without value: b") { ok = false; }
  return assert(ok, "a key with no value before EOF or '}' is Err");
}

fn t18() -> TestResult {
  var ok = parse_err_is("\"a\" \"x\\qz\"", "vdf: bad escape: \\q");
  if !parse_err_is("\"k\\q\" \"v\"", "vdf: bad escape: \\q") { ok = false; }
  if !parse_err_is("\"a\" \"x\\ry\"", "vdf: bad escape: \\r") { ok = false; }
  return assert(ok, "escapes other than \\n \\t \\\" \\\\ are Err");
}

fn t19() -> TestResult {
  let deep_ok = string.str_repeat("\"k\" {", 64) + "\"v\" \"1\"" + string.str_repeat("}", 64);
  let deep_bad = string.str_repeat("\"k\" {", 65) + "\"v\" \"1\"" + string.str_repeat("}", 65);
  var ok = false;
  let r = vdf_parse(deep_ok);
  match r {
    Ok(d) => {
      let path = string.str_repeat("k.", 64) + "v";
      ok = vdf_has(&d, path);
      if !opt_str_is(vdf_get_str(&d, path), "1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !parse_err_is(deep_bad, "vdf: depth exceeded (max 64)") { ok = false; }
  return assert(ok, "64 open blocks are accepted, 65 are Err");
}

fn t20() -> TestResult {
  let r1 = vdf_parse("// note\n\"a\" \"1\"\n\"b\"\n{\n\t\"c\" \"2\"\n\t\"d\" { \"e\" \"3\" }\n}\n\"a\" \"4\"\n");
  var ok = false;
  match r1 {
    Ok(d1) => {
      let got = vdf_emit(&d1);
      let want = "\"a\" \"1\"\n\"b\"\n{\n\t\"c\" \"2\"\n\t\"d\"\n\t{\n\t\t\"e\" \"3\"\n\t}\n}\n\"a\" \"4\"\n";
      ok = streq(got, want);
      let r2 = vdf_parse(got);
      match r2 {
        Ok(d2) => {
          if !opt_str_is(vdf_get_str(&d2, "a"), "4") { ok = false; }
          if !opt_str_is(vdf_get_str(&d2, "b.c"), "2") { ok = false; }
          if !opt_str_is(vdf_get_str(&d2, "b.d.e"), "3") { ok = false; }
          var ks = vdf_root_keys(&d2);
          if ks.len() != 3 { ok = false; }
          if !str_at(&ks, 0, "a") { ok = false; }
          if !str_at(&ks, 1, "b") { ok = false; }
          if !str_at(&ks, 2, "a") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical emit is exact and re-parses");
}

fn t21() -> TestResult {
  let r = vdf_parse("\"n\" { \"v\" \"1\" }\n\"n\" { \"v\" \"2\" }");
  var ok = false;
  match r {
    Ok(d) => {
      var ks = vdf_root_keys(&d);
      ok = ks.len() == 2;
      if !str_at(&ks, 0, "n") { ok = false; }
      if !str_at(&ks, 1, "n") { ok = false; }
      if !opt_str_is(vdf_get_str(&d, "n.v"), "2") { ok = false; }
      var ck = vdf_child_keys(&d, "n");
      if ck.len() != 1 { ok = false; }
      let want = "\"n\"\n{\n\t\"v\" \"1\"\n}\n\"n\"\n{\n\t\"v\" \"2\"\n}\n";
      if !streq(vdf_emit(&d), want) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate blocks are preserved, the last one wins lookup");
}

fn t22() -> TestResult {
  let r = vdf_parse("\"a\" { \"b\" \"1\" }");
  var ok = false;
  match r {
    Ok(d) => {
      ok = vdf_has(&d, "");
      if !vdf_has(&d, "a") { ok = false; }
      if !vdf_has(&d, "a.b") { ok = false; }
      if !opt_str_is(vdf_get_str(&d, "A.B"), "1") { ok = false; }
      if !opt_str_none(vdf_get_str(&d, "a..b")) { ok = false; }
      if !opt_str_none(vdf_get_str(&d, "a.b.")) { ok = false; }
      if !opt_str_none(vdf_get_str(&d, ".a.b")) { ok = false; }
      if !opt_str_none(vdf_get_str(&d, "a.b.c")) { ok = false; }
      if !opt_str_none(vdf_get_str(&d, "a")) { ok = false; }
      if !opt_int_none(vdf_get_int(&d, "a")) { ok = false; }
      if !opt_bool_none(vdf_get_bool(&d, "a")) { ok = false; }
      if vdf_child_keys(&d, "a.b").len() != 0 { ok = false; }
      if vdf_child_keys(&d, "missing").len() != 0 { ok = false; }
      var ck = vdf_child_keys(&d, "");
      if ck.len() != 1 { ok = false; }
      if !str_at(&ck, 0, "a") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "path edge cases and kind-checked accessors");
}

fn t23() -> TestResult {
  let r = vdf_parse("\"q\" \"a\\\"b\\\\c\"");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(vdf_get_str(&d, "q"), "a\"b\\c");
      let want = "\"q\" \"a\\\"b\\\\c\"\n";
      if !streq(vdf_emit(&d), want) { ok = false; }
      let r2 = vdf_parse(vdf_emit(&d));
      match r2 {
        Ok(d2) => {
          if !opt_str_is(vdf_get_str(&d2, "q"), "a\"b\\c") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit escapes quotes and backslashes exactly");
}

fn main() -> Int {
  io.println("=== xiom.vdf conformance tests ===");
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
    io.println("xiom.vdf: all tests passed");
  } else {
    io.println("xiom.vdf: tests failed");
  }
  return failed;
}
