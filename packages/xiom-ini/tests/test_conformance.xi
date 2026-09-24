// XIOM -- xiom.ini conformance tests (20 checks)
// Greenfield package: prove the pure-XIOM xiom.ini module against its
// documented INI line grammar, merge rules and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: global and section entries, both separators, full-line comments
// of both kinds, whitespace trimming, empty-key and malformed-line errors,
// duplicate last-wins/position semantics, CRLF input, get/has, per-section
// key order, section order, set replace vs append, remove existing/absent,
// emit round trip, emit global-first layout, empty documents and invalid
// section headers.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq/str_at/opt_str_is instead of `==`.

module ini_tests
use xiom.io; use xiom.test; use xiom.ini;
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

fn new_ini() -> Ini {
  return Ini{ sections: Vec[Str].new(); keys: Vec[Str].new(); values: Vec[Str].new(); };
}

// True when the text fails to parse with an "ini: " error message.
fn parse_err_prefix(text: Str) -> Bool {
  let r = ini_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "ini: "); },
  }
  return false;
}

fn t1() -> TestResult {
  let r = ini_parse("top = 1\n[server]\nhost = localhost\nport = 8080");
  var ok = false;
  match r {
    Ok(x) => {
      ok = opt_str_is(ini_get(&x, "", "top"), "1");
      if !opt_str_is(ini_get(&x, "server", "host"), "localhost") { ok = false; }
      if !opt_str_is(ini_get(&x, "server", "port"), "8080") { ok = false; }
      if ini_has(&x, "server", "top") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse global and section entries");
}

fn t2() -> TestResult {
  let r = ini_parse("a: 1\n[db]\nuser : ada\npass:secret");
  var ok = false;
  match r {
    Ok(x) => {
      ok = opt_str_is(ini_get(&x, "", "a"), "1");
      if !opt_str_is(ini_get(&x, "db", "user"), "ada") { ok = false; }
      if !opt_str_is(ini_get(&x, "db", "pass"), "secret") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "colon separator splits key and value");
}

fn t3() -> TestResult {
  let r = ini_parse("; semi comment\n# hash comment\n   ; indented\n\n[log]\n; inner\n# inner hash\nlevel = info\nplain = 1 ; kept # kept\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = !ini_has(&x, "", "semi");
      if ini_has(&x, "", "hash") { ok = false; }
      if !opt_str_is(ini_get(&x, "log", "level"), "info") { ok = false; }
      if !opt_str_is(ini_get(&x, "log", "plain"), "1 ; kept # kept") { ok = false; }
      var ks = ini_keys(&x, "log");
      if ks.len() != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "full-line ; and # comments are skipped; inline markers are data");
}

fn t4() -> TestResult {
  let r = ini_parse("  spaced  =   padded value  \n\t[ sec ]\t\n\t k\t:\tv\t");
  var ok = false;
  match r {
    Ok(x) => {
      ok = opt_str_is(ini_get(&x, "", "spaced"), "padded value");
      if !opt_str_is(ini_get(&x, "sec", "k"), "v") { ok = false; }
      if ini_has(&x, "", " spaced") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "whitespace is trimmed around keys, values and section names");
}

fn t5() -> TestResult {
  var ok = parse_err_prefix(" = value");
  if !parse_err_prefix(":value") { ok = false; }
  if !parse_err_prefix("   =  ") { ok = false; }
  if !parse_err_prefix("[a]\n=1") { ok = false; }
  return assert(ok, "empty key is Err");
}

fn t6() -> TestResult {
  let r = ini_parse("a = 1\nb = 2\na = 3\nc = 4\na = 5\n[s]\nk = 1\nk = 2\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = opt_str_is(ini_get(&x, "", "a"), "5");
      if !opt_str_is(ini_get(&x, "", "b"), "2") { ok = false; }
      var ks = ini_keys(&x, "");
      if ks.len() != 3 { ok = false; }
      if !str_at(&ks, 0, "a") { ok = false; }
      if !str_at(&ks, 1, "b") { ok = false; }
      if !str_at(&ks, 2, "c") { ok = false; }
      if !opt_str_is(ini_get(&x, "s", "k"), "2") { ok = false; }
      var sk = ini_keys(&x, "s");
      if sk.len() != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate pairs: last wins, first position kept");
}

fn t7() -> TestResult {
  let r = ini_parse("a = 1\r\n[win]\r\npath = C:\\tmp\r\n\r\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = opt_str_is(ini_get(&x, "", "a"), "1");
      if !opt_str_is(ini_get(&x, "win", "path"), "C:\\tmp") { ok = false; }
      var secs = ini_sections(&x);
      if secs.len() != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF line endings parse");
}

fn t8() -> TestResult {
  let r = ini_parse("A = 1\n[s]\nB = 2");
  var ok = false;
  match r {
    Ok(x) => {
      ok = ini_has(&x, "", "A");
      if !opt_str_is(ini_get(&x, "", "A"), "1") { ok = false; }
      if ini_has(&x, "", "a") { ok = false; }
      if !opt_str_none(ini_get(&x, "", "a")) { ok = false; }
      if !opt_str_none(ini_get(&x, "S", "B")) { ok = false; }
      if !opt_str_none(ini_get(&x, "missing", "B")) { ok = false; }
      if !opt_str_is(ini_get(&x, "s", "B"), "2") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "get/has are byte-exact and case-sensitive; absent pairs yield None");
}

fn t9() -> TestResult {
  let r = ini_parse("[z]\nq = 1\n[s]\nb = 2\na = 3\n[z]\nr = 4\n");
  var ok = false;
  match r {
    Ok(x) => {
      var zk = ini_keys(&x, "z");
      ok = zk.len() == 2;
      if !str_at(&zk, 0, "q") { ok = false; }
      if !str_at(&zk, 1, "r") { ok = false; }
      var sk = ini_keys(&x, "s");
      if sk.len() != 2 { ok = false; }
      if !str_at(&sk, 0, "b") { ok = false; }
      if !str_at(&sk, 1, "a") { ok = false; }
      var nk = ini_keys(&x, "none");
      if nk.len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ini_keys returns each section's keys in entry order");
}

fn t10() -> TestResult {
  let r = ini_parse("g = 0\n[b]\nx = 1\n[a]\ny = 2\n[b]\nz = 3\n");
  var ok = false;
  match r {
    Ok(x) => {
      var secs = ini_sections(&x);
      ok = secs.len() == 3;
      if !str_at(&secs, 0, "") { ok = false; }
      if !str_at(&secs, 1, "b") { ok = false; }
      if !str_at(&secs, 2, "a") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ini_sections returns first-seen order, global section included");
}

fn t11() -> TestResult {
  let r = ini_parse("[b]\nx = 1\n[a]\ny = 2\n");
  var ok = false;
  match r {
    Ok(x) => {
      var secs = ini_sections(&x);
      ok = secs.len() == 2;
      if !str_at(&secs, 0, "b") { ok = false; }
      if !str_at(&secs, 1, "a") { ok = false; }
      var e = new_ini();
      var es = ini_sections(&e);
      if es.len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "the global section is listed only when it has entries");
}

fn t12() -> TestResult {
  var x = new_ini();
  ini_set(&mut x, "", "a", "1");
  ini_set(&mut x, "s", "k", "v");
  ini_set(&mut x, "", "b", "2");
  ini_set(&mut x, "s", "k", "v2");
  var ks = ini_keys(&x, "");
  var ok = ks.len() == 2;
  if !str_at(&ks, 0, "a") { ok = false; }
  if !str_at(&ks, 1, "b") { ok = false; }
  if !opt_str_is(ini_get(&x, "", "a"), "1") { ok = false; }
  if !opt_str_is(ini_get(&x, "s", "k"), "v2") { ok = false; }
  var sk = ini_keys(&x, "s");
  if sk.len() != 1 { ok = false; }
  return assert(ok, "ini_set replaces an existing pair in place");
}

fn t13() -> TestResult {
  var x = new_ini();
  ini_set(&mut x, "s", "a", "1");
  ini_set(&mut x, "s", "b", "2");
  ini_set(&mut x, "", "g", "3");
  var sk = ini_keys(&x, "s");
  var ok = sk.len() == 2;
  if !str_at(&sk, 0, "a") { ok = false; }
  if !str_at(&sk, 1, "b") { ok = false; }
  if !opt_str_is(ini_get(&x, "s", "b"), "2") { ok = false; }
  if !opt_str_is(ini_get(&x, "", "g"), "3") { ok = false; }
  var secs = ini_sections(&x);
  if secs.len() != 2 { ok = false; }
  if !str_at(&secs, 0, "s") { ok = false; }
  if !str_at(&secs, 1, "") { ok = false; }
  return assert(ok, "ini_set appends new pairs and keeps first-seen order");
}

fn t14() -> TestResult {
  var x = new_ini();
  ini_set(&mut x, "", "a", "1");
  ini_set(&mut x, "", "b", "2");
  ini_set(&mut x, "", "c", "3");
  ini_set(&mut x, "s", "k", "4");
  var ok = ini_remove(&mut x, "", "b");
  if !ini_remove(&mut x, "s", "k") { ok = false; }
  if ini_has(&x, "", "b") { ok = false; }
  if !opt_str_is(ini_get(&x, "", "c"), "3") { ok = false; }
  var ks = ini_keys(&x, "");
  if ks.len() != 2 { ok = false; }
  if !str_at(&ks, 0, "a") { ok = false; }
  if !str_at(&ks, 1, "c") { ok = false; }
  var secs = ini_sections(&x);
  if secs.len() != 1 { ok = false; }
  if !str_at(&secs, 0, "") { ok = false; }
  return assert(ok, "ini_remove compacts the arrays and drops emptied sections");
}

fn t15() -> TestResult {
  var x = new_ini();
  ini_set(&mut x, "s", "k", "v");
  var ok = !ini_remove(&mut x, "s", "missing");
  if ini_remove(&mut x, "other", "k") { ok = false; }
  if ini_remove(&mut x, "", "k") { ok = false; }
  if !opt_str_is(ini_get(&x, "s", "k"), "v") { ok = false; }
  return assert(ok, "ini_remove returns false when the pair is absent");
}

fn t16() -> TestResult {
  let r1 = ini_parse("g = 1\n\n[server]\nhost = localhost\nport = 8080\n\n[client]\nname = ada\n");
  var ok = false;
  match r1 {
    Ok(x1) => {
      let text = ini_emit(&x1);
      let r2 = ini_parse(text);
      match r2 {
        Ok(x2) => {
          ok = opt_str_is(ini_get(&x2, "", "g"), "1");
          if !opt_str_is(ini_get(&x2, "server", "host"), "localhost") { ok = false; }
          if !opt_str_is(ini_get(&x2, "server", "port"), "8080") { ok = false; }
          if !opt_str_is(ini_get(&x2, "client", "name"), "ada") { ok = false; }
          if ini_has(&x2, "server", "g") { ok = false; }
          var secs = ini_sections(&x2);
          if secs.len() != 3 { ok = false; }
          if !str_at(&secs, 0, "") { ok = false; }
          if !str_at(&secs, 1, "server") { ok = false; }
          if !str_at(&secs, 2, "client") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit then parse round-trips sections, keys and values");
}

fn t17() -> TestResult {
  var x = new_ini();
  ini_set(&mut x, "beta", "b", "2");
  ini_set(&mut x, "", "g", "1");
  ini_set(&mut x, "alpha", "a", "3");
  let got = ini_emit(&x);
  let want = "g = 1\n\n[beta]\nb = 2\n\n[alpha]\na = 3";
  var ok = streq(got, want);
  let r = ini_parse(got);
  match r {
    Ok(y) => {
      if !opt_str_is(ini_get(&y, "", "g"), "1") { ok = false; }
      if !opt_str_is(ini_get(&y, "beta", "b"), "2") { ok = false; }
      if !opt_str_is(ini_get(&y, "alpha", "a"), "3") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit writes global entries first and separates groups with a blank line");
}

fn t18() -> TestResult {
  let r = ini_parse("");
  var ok = false;
  match r {
    Ok(x) => {
      var secs = ini_sections(&x);
      ok = secs.len() == 0;
      var ks = ini_keys(&x, "");
      if ks.len() != 0 { ok = false; }
      if !streq(ini_emit(&x), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = ini_parse("; only comment\n\n   \n# another\n");
  match r2 {
    Ok(x2) => {
      var secs2 = ini_sections(&x2);
      if secs2.len() != 0 { ok = false; }
      if !streq(ini_emit(&x2), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and comment-only documents parse to zero entries and emit empty text");
}

fn t19() -> TestResult {
  var ok = parse_err_prefix("[unclosed");
  if !parse_err_prefix("[a]b]") { ok = false; }
  if !parse_err_prefix("[]") { ok = false; }
  if !parse_err_prefix("[") { ok = false; }
  if !parse_err_prefix("  [  ]  ") { ok = false; }
  if !parse_err_prefix("[a][b]") { ok = false; }
  return assert(ok, "malformed and empty section headers are Err");
}

fn t20() -> TestResult {
  var ok = parse_err_prefix("justakey");
  if !parse_err_prefix("key value") { ok = false; }
  if !parse_err_prefix("  leading word  ") { ok = false; }
  if !parse_err_prefix("key.value") { ok = false; }
  return assert(ok, "non-blank lines without a separator are Err");
}

fn main() -> Int {
  io.println("=== xiom.ini conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.ini: all tests passed");
  } else {
    io.println("xiom.ini: tests failed");
  }
  return failed;
}
