// XIOM -- xiom.toml conformance tests (21 checks)
// Port task: prove the pure-XIOM xiom.toml module against its documented
// TOML v1.0 subset.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module toml_tests
use xiom.io; use xiom.test; use xiom.toml;
use xiom.string;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through streq/str_at/opt_str_is instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn str_at(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  return streq(v[i], want);
}

fn int_at(v: &Vec[Int], i: Int, want: Int) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  return v[i] == want;
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

fn parse_fails(text: Str) -> Bool {
  let r = toml_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return true;
}

fn parse_err_toml(text: Str) -> Bool {
  let r = toml_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "toml: "); },
  }
  return false;
}

fn parse_ok_count(text: Str, want: Int) -> Bool {
  let r = toml_parse(text);
  match r {
    Ok(d) => { return toml_key_count(&d) == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  let r = toml_parse("name = \"xiom\"");
  var ok = false;
  match r {
    Ok(d) => {
      ok = toml_has(&d, "name");
      if !opt_int_is(toml_kind(&d, "name"), 0) { ok = false; }
      if !opt_str_is(toml_get_str(&d, "name"), "xiom") { ok = false; }
      if !opt_int_none(toml_get_int(&d, "name")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "simple string value");
}

fn t2() -> TestResult {
  let r = toml_parse("port = 8080\nmax = 65535");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(toml_kind(&d, "port"), 1);
      if !opt_int_is(toml_get_int(&d, "port"), 8080) { ok = false; }
      if !opt_int_is(toml_get_int(&d, "max"), 65535) { ok = false; }
      if !opt_str_none(toml_get_str(&d, "port")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "simple integer values");
}

fn t3() -> TestResult {
  let r = toml_parse("enabled = true\ndebug = false");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(toml_kind(&d, "enabled"), 2);
      if !opt_bool_is(toml_get_bool(&d, "enabled"), true) { ok = false; }
      if !opt_bool_is(toml_get_bool(&d, "debug"), false) { ok = false; }
      if !opt_int_none(toml_get_int(&d, "debug")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "boolean values");
}

fn t4() -> TestResult {
  let r = toml_parse("# a full-line comment\n\n   \nport = 1  # trailing comment\nname = \"a#b\"\nfrag = 'c#d'\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = toml_key_count(&d) == 3;
      if !opt_int_is(toml_get_int(&d, "port"), 1) { ok = false; }
      if !opt_str_is(toml_get_str(&d, "name"), "a#b") { ok = false; }
      if !opt_str_is(toml_get_str(&d, "frag"), "c#d") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "comments and blank lines are ignored");
}

fn t5() -> TestResult {
  let r = toml_parse("server.host = \"localhost\"\nserver.port = 9000");
  var ok = false;
  match r {
    Ok(d) => {
      ok = toml_has(&d, "server.host");
      if !toml_has(&d, "server.port") { ok = false; }
      if !opt_str_is(toml_get_str(&d, "server.host"), "localhost") { ok = false; }
      if !opt_int_is(toml_get_int(&d, "server.port"), 9000) { ok = false; }
      var ks = toml_keys(&d);
      if !str_at(&ks, 0, "server.host") { ok = false; }
      if !str_at(&ks, 1, "server.port") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "dotted keys build dotted paths");
}

fn t6() -> TestResult {
  let r = toml_parse("[server]\nhost = \"localhost\"\nport = 9000\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = toml_has(&d, "server.host");
      if !opt_str_is(toml_get_str(&d, "server.host"), "localhost") { ok = false; }
      if !opt_int_is(toml_get_int(&d, "server.port"), 9000) { ok = false; }
      if toml_has(&d, "host") { ok = false; }
      if toml_key_count(&d) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "table headers prefix keys");
}

fn t7() -> TestResult {
  let r = toml_parse("[a.b]\nx = 1\n[a.c]\ny = 2\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = toml_has(&d, "a.b.x");
      if !toml_has(&d, "a.c.y") { ok = false; }
      if !opt_int_is(toml_get_int(&d, "a.b.x"), 1) { ok = false; }
      if !opt_int_is(toml_get_int(&d, "a.c.y"), 2) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "nested table headers build nested paths");
}

fn t8() -> TestResult {
  let r = toml_parse("\"my key\" = 7\n'lit key' = \"v\"");
  var ok = false;
  match r {
    Ok(d) => {
      ok = toml_has(&d, "my key");
      if !toml_has(&d, "lit key") { ok = false; }
      if !opt_int_is(toml_get_int(&d, "my key"), 7) { ok = false; }
      if !opt_str_is(toml_get_str(&d, "lit key"), "v") { ok = false; }
      var ks = toml_keys(&d);
      if !str_at(&ks, 0, "my key") { ok = false; }
      if !str_at(&ks, 1, "lit key") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "quoted keys keep their text");
}

fn t9() -> TestResult {
  let r = toml_parse("s = \"a\\nb\\tc\\\"d\\\\e\"");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(toml_get_str(&d, "s"), "a\nb\tc\"d\\e");
      if toml_key_count(&d) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "basic strings decode \\n \\t \\\" \\\\ escapes");
}

fn t10() -> TestResult {
  let r = toml_parse("win = 'C:\\tmp\\new'\nq = 'say \"hi\"'");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(toml_get_str(&d, "win"), "C:\\tmp\\new");
      if !opt_str_is(toml_get_str(&d, "q"), "say \"hi\"") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "literal strings keep bytes verbatim");
}

fn t11() -> TestResult {
  let r = toml_parse("low = -42\nzero = 0\nneg = -7");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(toml_get_int(&d, "low"), -42);
      if !opt_int_is(toml_get_int(&d, "zero"), 0) { ok = false; }
      if !opt_int_is(toml_get_int(&d, "neg"), -7) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "negative and zero integers");
}

fn t12() -> TestResult {
  let r = toml_parse("tags = [\"a\", \"b\", \"c\"]\npaths = ['x', \"y\\nz\"]");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(toml_kind(&d, "tags"), 3);
      var tags = toml_get_str_array(&d, "tags");
      if tags.len() != 3 { ok = false; }
      if !str_at(&tags, 0, "a") { ok = false; }
      if !str_at(&tags, 1, "b") { ok = false; }
      if !str_at(&tags, 2, "c") { ok = false; }
      var paths = toml_get_str_array(&d, "paths");
      if paths.len() != 2 { ok = false; }
      if !str_at(&paths, 0, "x") { ok = false; }
      if !str_at(&paths, 1, "y\nz") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "string arrays decode quoted and literal items");
}

fn t13() -> TestResult {
  let r = toml_parse("nums = [1, -2, 3]\nempty = []\ntrail = [ 4 , 5 , ]");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(toml_kind(&d, "nums"), 4);
      var nums = toml_get_int_array(&d, "nums");
      if nums.len() != 3 { ok = false; }
      if !int_at(&nums, 0, 1) { ok = false; }
      if !int_at(&nums, 1, -2) { ok = false; }
      if !int_at(&nums, 2, 3) { ok = false; }
      if !opt_int_is(toml_kind(&d, "empty"), 3) { ok = false; }
      if toml_get_str_array(&d, "empty").len() != 0 { ok = false; }
      var trail = toml_get_int_array(&d, "trail");
      if trail.len() != 2 { ok = false; }
      if !int_at(&trail, 0, 4) { ok = false; }
      if !int_at(&trail, 1, 5) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "int arrays, empty arrays and trailing commas");
}

fn t14() -> TestResult {
  let r = toml_parse("[svc]\nports = [80, 443]");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(toml_kind(&d, "svc.ports"), 4);
      var ports = toml_get_int_array(&d, "svc.ports");
      if ports.len() != 2 { ok = false; }
      if !int_at(&ports, 0, 80) { ok = false; }
      if !int_at(&ports, 1, 443) { ok = false; }
      if !opt_str_none(toml_get_str(&d, "svc.ports")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !parse_err_toml("bad = [1, \"a\"]") { ok = false; }
  if !parse_err_toml("bad = [[1]]") { ok = false; }
  if !parse_err_toml("bad = [true]") { ok = false; }
  return assert(ok, "arrays are typed and reject mixed or nested items");
}

fn t15() -> TestResult {
  var ok = parse_err_toml("a = 1\na = 2");
  if !parse_err_toml("t.x = 1\nt.x = 2") { ok = false; }
  if !parse_err_toml("[srv]\np = 1\np = 2") { ok = false; }
  return assert(ok, "duplicate keys are errors");
}

fn t16() -> TestResult {
  var ok = parse_err_toml("[a]\nx = 1\n[a]\ny = 2");
  if !parse_err_toml("[a.b]\nx = 1\n[a.b]\ny = 2") { ok = false; }
  if !parse_err_toml("[a.b]\nx = 1\nx = 2") { ok = false; }
  return assert(ok, "duplicate tables and table-scoped keys are errors");
}

fn t17() -> TestResult {
  var ok = parse_err_toml("this is not toml");
  if !parse_err_toml("x =") { ok = false; }
  if !parse_err_toml("= 1") { ok = false; }
  if !parse_err_toml("[unclosed") { ok = false; }
  if !parse_err_toml("x = 1 2") { ok = false; }
  if !parse_err_toml("[a] junk") { ok = false; }
  if !parse_err_toml("[[products]]") { ok = false; }
  if !parse_err_toml("x = \"unterminated") { ok = false; }
  if !parse_fails("bad = [1, \"a\"]") { ok = false; }
  return assert(ok, "malformed lines and unsupported tables are errors");
}

fn t18() -> TestResult {
  let r = toml_parse("b = 1\na = 2\nc = 3");
  var ok = false;
  match r {
    Ok(d) => {
      ok = toml_key_count(&d) == 3;
      var ks = toml_keys(&d);
      if ks.len() != 3 { ok = false; }
      if !str_at(&ks, 0, "b") { ok = false; }
      if !str_at(&ks, 1, "a") { ok = false; }
      if !str_at(&ks, 2, "c") { ok = false; }
      ks.push("zzz");
      if toml_key_count(&d) != 3 { ok = false; }
      if !parse_ok_count("", 0) { ok = false; }
      if !parse_ok_count("# only a comment\n\n", 0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "toml_keys keeps document order and copies");
}

fn t19() -> TestResult {
  let r = toml_parse("a = 1");
  var ok = false;
  match r {
    Ok(d) => {
      ok = !toml_has(&d, "missing");
      if !opt_int_none(toml_kind(&d, "missing")) { ok = false; }
      if !opt_str_none(toml_get_str(&d, "missing")) { ok = false; }
      if !opt_int_none(toml_get_int(&d, "missing")) { ok = false; }
      if !opt_bool_none(toml_get_bool(&d, "missing")) { ok = false; }
      if toml_get_str_array(&d, "missing").len() != 0 { ok = false; }
      if toml_get_int_array(&d, "missing").len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "missing keys yield false/None/empty");
}

fn t20() -> TestResult {
  let r = toml_parse("s = \"x\"\ni = 1\nb = true\nt = [\"a\"]");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_none(toml_get_int(&d, "s"));
      if !opt_str_none(toml_get_str(&d, "i")) { ok = false; }
      if !opt_int_none(toml_get_int(&d, "b")) { ok = false; }
      if !opt_bool_none(toml_get_bool(&d, "s")) { ok = false; }
      if !opt_str_none(toml_get_str(&d, "t")) { ok = false; }
      if toml_get_str_array(&d, "i").len() != 0 { ok = false; }
      if toml_get_int_array(&d, "s").len() != 0 { ok = false; }
      if !opt_int_is(toml_kind(&d, "t"), 3) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "accessors enforce the stored kind");
}

fn t21() -> TestResult {
  let r = toml_parse("  spaced   =   42  # note\n[ sec ]\n inner = \"v\"");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(toml_kind(&d, "spaced"), 1);
      if !opt_int_is(toml_get_int(&d, "spaced"), 42) { ok = false; }
      if !opt_str_is(toml_get_str(&d, "sec.inner"), "v") { ok = false; }
      if toml_key_count(&d) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "intra-line whitespace is tolerated");
}

fn main() -> Int {
  io.println("=== xiom.toml conformance tests ===");
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
    io.println("xiom.toml: all tests passed");
  } else {
    io.println("xiom.toml: tests failed");
  }
  return failed;
}
