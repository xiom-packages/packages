// XIOM -- xiom.yaml conformance tests (25 checks)
// Port task: prove the pure-XIOM xiom.yaml module against its documented YAML
// subset, dotted-path lookup model and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: every scalar kind (str/int/bool/null), nested mappings, block
// lists, inline lists, quoted strings with escapes, comments, blank lines,
// CRLF input, indentation jumps, tab indentation, duplicate keys,
// unterminated quotes and other malformed lines, accessor kind enforcement,
// list lookups, missing keys, empty input, deep nesting and the flat
// dotted-path namespace.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through streq/str_at/opt_str_is instead of `==`.

module yaml_tests
use xiom.io; use xiom.test; use xiom.yaml;
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

// True when the text fails to parse with a message starting `prefix`.
fn parse_err_has(text: Str, prefix: Str) -> Bool {
  let r = yaml_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

// True when the text fails to parse with a "yaml: " error message.
fn parse_err_yaml(text: Str) -> Bool {
  return parse_err_has(text, "yaml: ");
}

fn parse_ok_count(text: Str, want: Int) -> Bool {
  let r = yaml_parse(text);
  match r {
    Ok(d) => { return yaml_key_count(&d) == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  let r = yaml_parse("name: xiom yaml");
  var ok = false;
  match r {
    Ok(d) => {
      ok = yaml_has(&d, "name");
      if !opt_int_is(yaml_kind(&d, "name"), 0) { ok = false; }
      if !opt_str_is(yaml_get_str(&d, "name"), "xiom yaml") { ok = false; }
      if !opt_int_none(yaml_get_int(&d, "name")) { ok = false; }
      if yaml_key_count(&d) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "plain string scalar");
}

fn t2() -> TestResult {
  let r = yaml_parse("port: 8080\nlow: -42\nzero: 0\npad: 007\nnegzero: -0");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(yaml_kind(&d, "port"), 1);
      if !opt_int_is(yaml_get_int(&d, "port"), 8080) { ok = false; }
      if !opt_int_is(yaml_get_int(&d, "low"), -42) { ok = false; }
      if !opt_int_is(yaml_get_int(&d, "zero"), 0) { ok = false; }
      if !opt_int_is(yaml_get_int(&d, "pad"), 7) { ok = false; }
      if !opt_int_is(yaml_get_int(&d, "negzero"), 0) { ok = false; }
      if !opt_str_none(yaml_get_str(&d, "port")) { ok = false; }
      if !opt_bool_none(yaml_get_bool(&d, "port")) { ok = false; }
      if yaml_key_count(&d) != 5 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "integer scalars, canonical text and negatives");
}

fn t3() -> TestResult {
  let r = yaml_parse("enabled: true\ndebug: false");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(yaml_kind(&d, "enabled"), 2);
      if !opt_bool_is(yaml_get_bool(&d, "enabled"), true) { ok = false; }
      if !opt_bool_is(yaml_get_bool(&d, "debug"), false) { ok = false; }
      if !opt_int_none(yaml_get_int(&d, "debug")) { ok = false; }
      if !opt_str_none(yaml_get_str(&d, "debug")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "boolean scalars");
}

fn t4() -> TestResult {
  let r = yaml_parse("explicit: null\ntilde: ~\ndangling:");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(yaml_kind(&d, "explicit"), 3);
      if !opt_int_is(yaml_kind(&d, "tilde"), 3) { ok = false; }
      if !opt_int_is(yaml_kind(&d, "dangling"), 3) { ok = false; }
      if !opt_str_none(yaml_get_str(&d, "explicit")) { ok = false; }
      if !opt_int_none(yaml_get_int(&d, "tilde")) { ok = false; }
      if !opt_bool_none(yaml_get_bool(&d, "dangling")) { ok = false; }
      if yaml_key_count(&d) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "null scalars and an empty value at EOF are null");
}

fn t5() -> TestResult {
  let r = yaml_parse("win: 'C:\\tmp\\new'\nq: 'say \"hi\"'\nhash: 'a # b'");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(yaml_get_str(&d, "win"), "C:\\tmp\\new");
      if !opt_str_is(yaml_get_str(&d, "q"), "say \"hi\"") { ok = false; }
      if !opt_str_is(yaml_get_str(&d, "hash"), "a # b") { ok = false; }
      if !opt_int_is(yaml_kind(&d, "win"), 0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "single-quoted scalars are literal");
}

fn t6() -> TestResult {
  let r = yaml_parse("s: \"a\\nb\\tc\\\"d\\\\e\"\nnumstr: \"123\"");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(yaml_get_str(&d, "s"), "a\nb\tc\"d\\e");
      if !opt_int_none(yaml_get_int(&d, "s")) { ok = false; }
      if !opt_str_is(yaml_get_str(&d, "numstr"), "123") { ok = false; }
      if !opt_int_none(yaml_get_int(&d, "numstr")) { ok = false; }
      if yaml_key_count(&d) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "double-quoted scalars decode \\n \\t \\\" \\\\ and stay str");
}

fn t7() -> TestResult {
  let r = yaml_parse("# full line\n   # indented comment\nname: a # trailing\nq: \"a # b\"\nfrag: c#d\nend: 1\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = yaml_key_count(&d) == 4;
      if !opt_str_is(yaml_get_str(&d, "name"), "a") { ok = false; }
      if !opt_str_is(yaml_get_str(&d, "q"), "a # b") { ok = false; }
      if !opt_str_is(yaml_get_str(&d, "frag"), "c#d") { ok = false; }
      if !opt_int_is(yaml_get_int(&d, "end"), 1) { ok = false; }
      if yaml_has(&d, "full") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "comments need whitespace before # and respect quotes");
}

fn t8() -> TestResult {
  let r = yaml_parse("a: 1\n\n   \nb: 2\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = yaml_key_count(&d) == 2;
      if !opt_int_is(yaml_get_int(&d, "a"), 1) { ok = false; }
      if !opt_int_is(yaml_get_int(&d, "b"), 2) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !parse_ok_count("", 0) { ok = false; }
  if !parse_ok_count("   \n\n\t\n", 0) { ok = false; }
  if !parse_ok_count("# only a comment\n\n   # another\n", 0) { ok = false; }
  return assert(ok, "blank lines are ignored and empty input is an empty document");
}

fn t9() -> TestResult {
  let r = yaml_parse("server:\n  host: localhost\n  port: 9000\n  tls:\n    enabled: true\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(yaml_get_str(&d, "server.host"), "localhost");
      if !opt_int_is(yaml_get_int(&d, "server.port"), 9000) { ok = false; }
      if !opt_bool_is(yaml_get_bool(&d, "server.tls.enabled"), true) { ok = false; }
      if yaml_key_count(&d) != 3 { ok = false; }
      if yaml_has(&d, "server") { ok = false; }
      if yaml_has(&d, "server.tls") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "nested mappings build dotted paths with no container entries");
}

fn t10() -> TestResult {
  let r = yaml_parse("a:\n  b:\n    c:\n      d:\n        e: deep\nx: 2");
  var ok = false;
  match r {
    Ok(d) => {
      ok = yaml_has(&d, "a.b.c.d.e");
      if !opt_str_is(yaml_get_str(&d, "a.b.c.d.e"), "deep") { ok = false; }
      if !opt_int_is(yaml_get_int(&d, "x"), 2) { ok = false; }
      if yaml_key_count(&d) != 2 { ok = false; }
      var ks = yaml_keys(&d);
      if !str_at(&ks, 0, "a.b.c.d.e") { ok = false; }
      if !str_at(&ks, 1, "x") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "deep nesting with a consistent step is pinned");
}

fn t11() -> TestResult {
  let r = yaml_parse("ports:\n  - 80\n  - 443\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(yaml_kind(&d, "ports"), 4);
      var ports = yaml_get_str_list(&d, "ports");
      if ports.len() != 2 { ok = false; }
      if !str_at(&ports, 0, "80") { ok = false; }
      if !str_at(&ports, 1, "443") { ok = false; }
      if !opt_str_none(yaml_get_str(&d, "ports")) { ok = false; }
      if !opt_int_none(yaml_get_int(&d, "ports")) { ok = false; }
      if yaml_get_str_list(&d, "missing").len() != 0 { ok = false; }
      if yaml_key_count(&d) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "block lists under a key are str-lists");
}

fn t12() -> TestResult {
  let r = yaml_parse("names:\n  - \"Ada Lovelace\"\n  - 'Grace Hopper'\n  - plain item\n  - 42\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(yaml_kind(&d, "names"), 4);
      var names = yaml_get_str_list(&d, "names");
      if names.len() != 4 { ok = false; }
      if !str_at(&names, 0, "Ada Lovelace") { ok = false; }
      if !str_at(&names, 1, "Grace Hopper") { ok = false; }
      if !str_at(&names, 2, "plain item") { ok = false; }
      if !str_at(&names, 3, "42") { ok = false; }
      if yaml_key_count(&d) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "block list items decode quotes and keep plain text");
}

fn t13() -> TestResult {
  let r = yaml_parse("tags: [a, b, c]\nnums: [1, -2, 3]\nempty: []\ntrail: [x, y,]\nq: [\"a b\", 'c']\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(yaml_kind(&d, "tags"), 4);
      var tags = yaml_get_str_list(&d, "tags");
      if tags.len() != 3 { ok = false; }
      if !str_at(&tags, 0, "a") { ok = false; }
      if !str_at(&tags, 2, "c") { ok = false; }
      var nums = yaml_get_str_list(&d, "nums");
      if nums.len() != 3 { ok = false; }
      if !str_at(&nums, 0, "1") { ok = false; }
      if !str_at(&nums, 1, "-2") { ok = false; }
      if !str_at(&nums, 2, "3") { ok = false; }
      if !opt_int_is(yaml_kind(&d, "empty"), 4) { ok = false; }
      if yaml_get_str_list(&d, "empty").len() != 0 { ok = false; }
      var trail = yaml_get_str_list(&d, "trail");
      if trail.len() != 2 { ok = false; }
      if !str_at(&trail, 1, "y") { ok = false; }
      var q = yaml_get_str_list(&d, "q");
      if q.len() != 2 { ok = false; }
      if !str_at(&q, 0, "a b") { ok = false; }
      if !str_at(&q, 1, "c") { ok = false; }
      if yaml_key_count(&d) != 5 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "inline scalar lists, empty list and trailing comma");
}

fn t14() -> TestResult {
  let r = yaml_parse("a: 1\r\nserver:\r\n  host: h\r\nlist:\r\n  - x\r\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_int_is(yaml_get_int(&d, "a"), 1);
      if !opt_str_is(yaml_get_str(&d, "server.host"), "h") { ok = false; }
      var list = yaml_get_str_list(&d, "list");
      if list.len() != 1 { ok = false; }
      if !str_at(&list, 0, "x") { ok = false; }
      if yaml_key_count(&d) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF line endings parse");
}

fn t15() -> TestResult {
  let r = yaml_parse("b: 1\na: 2\nc: 3");
  var ok = false;
  match r {
    Ok(d) => {
      ok = yaml_key_count(&d) == 3;
      var ks = yaml_keys(&d);
      if ks.len() != 3 { ok = false; }
      if !str_at(&ks, 0, "b") { ok = false; }
      if !str_at(&ks, 1, "a") { ok = false; }
      if !str_at(&ks, 2, "c") { ok = false; }
      ks.push("zzz");
      if yaml_key_count(&d) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "yaml_keys keeps document order and copies");
}

fn t16() -> TestResult {
  let r = yaml_parse("a: 1");
  var ok = false;
  match r {
    Ok(d) => {
      ok = !yaml_has(&d, "missing");
      if !opt_int_none(yaml_kind(&d, "missing")) { ok = false; }
      if !opt_str_none(yaml_get_str(&d, "missing")) { ok = false; }
      if !opt_int_none(yaml_get_int(&d, "missing")) { ok = false; }
      if !opt_bool_none(yaml_get_bool(&d, "missing")) { ok = false; }
      if yaml_get_str_list(&d, "missing").len() != 0 { ok = false; }
      if !yaml_has(&d, "a") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "missing keys yield false/None/empty");
}

fn t17() -> TestResult {
  let r = yaml_parse("s: x\ni: 1\nb: true\nn: null\nl: [a]\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(yaml_get_str(&d, "s"), "x");
      if !opt_int_none(yaml_get_int(&d, "s")) { ok = false; }
      if !opt_str_none(yaml_get_str(&d, "i")) { ok = false; }
      if !opt_int_is(yaml_get_int(&d, "i"), 1) { ok = false; }
      if !opt_bool_none(yaml_get_bool(&d, "i")) { ok = false; }
      if !opt_bool_is(yaml_get_bool(&d, "b"), true) { ok = false; }
      if !opt_int_none(yaml_get_int(&d, "b")) { ok = false; }
      if !opt_str_none(yaml_get_str(&d, "b")) { ok = false; }
      if !opt_int_is(yaml_kind(&d, "n"), 3) { ok = false; }
      if !opt_str_none(yaml_get_str(&d, "n")) { ok = false; }
      if !opt_int_none(yaml_get_int(&d, "n")) { ok = false; }
      if !opt_bool_none(yaml_get_bool(&d, "n")) { ok = false; }
      if !opt_str_none(yaml_get_str(&d, "l")) { ok = false; }
      if !opt_int_none(yaml_get_int(&d, "l")) { ok = false; }
      if !opt_bool_none(yaml_get_bool(&d, "l")) { ok = false; }
      if yaml_get_str_list(&d, "i").len() != 0 { ok = false; }
      if yaml_get_str_list(&d, "l").len() != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "accessors enforce the stored kind");
}

fn t18() -> TestResult {
  var ok = parse_err_has("a: 1\n  b: 2", "yaml: indentation jump");
  if !parse_err_has("a:\n  b: 1\n    c: 2", "yaml: indentation jump") { ok = false; }
  if !parse_err_has("a:\n    b: 1\n  c: 2", "yaml: indentation jump") { ok = false; }
  if !parse_err_has("a:\n   b: 1\nc:\n d: 2", "yaml: indentation jump") { ok = false; }
  if !parse_err_has(" k: 1", "yaml: indentation jump") { ok = false; }
  if !parse_err_yaml("a: 1\n  b: 2") { ok = false; }
  return assert(ok, "indentation jumps and inconsistent steps are Err");
}

fn t19() -> TestResult {
  var ok = parse_err_has("\ta: 1", "yaml: tab indentation");
  if !parse_err_has("  \tb: 1", "yaml: tab indentation") { ok = false; }
  if !parse_err_has("a:\n\tb: 1", "yaml: tab indentation") { ok = false; }
  if !parse_err_has("a:\n  \tb: 1", "yaml: tab indentation") { ok = false; }
  if !parse_ok_count("#\tcomment\n\t# tab comment\na: 1\n", 1) { ok = false; }
  if !parse_ok_count("a:\t1\n", 1) { ok = false; }
  return assert(ok, "tab indentation is rejected, tabs inside content are not");
}

fn t20() -> TestResult {
  var ok = parse_err_has("a: 1\na: 2", "yaml: duplicate key");
  if !parse_err_has("x: 1\nx: 2", "yaml: duplicate key: x") { ok = false; }
  if !parse_err_has("a:\n  b: 1\n  b: 2", "yaml: duplicate key") { ok = false; }
  if !parse_err_has("a:\n  b: 1\na:\n  c: 2", "yaml: duplicate key") { ok = false; }
  if !parse_err_has("a:\n  - x\na: 1", "yaml: duplicate key") { ok = false; }
  if !parse_err_has("a: 1\na:\n  b: 2", "yaml: duplicate key") { ok = false; }
  return assert(ok, "duplicate leaf keys and container re-open are Err");
}

fn t21() -> TestResult {
  var ok = parse_err_has("a: \"abc", "yaml: unterminated quote");
  if !parse_err_has("b: 'xyz", "yaml: unterminated quote") { ok = false; }
  if !parse_err_has("l:\n  - \"abc", "yaml: unterminated quote") { ok = false; }
  if !parse_err_has("i: [a, \"b]", "yaml: unterminated quote") { ok = false; }
  if !parse_err_has("a: \"bad\\q\"", "yaml: invalid escape") { ok = false; }
  if !parse_err_has("a: \"x\" y", "yaml: unexpected text after quoted value") { ok = false; }
  if !parse_err_has("a: 'x' y", "yaml: unexpected text after quoted value") { ok = false; }
  return assert(ok, "quote errors: unterminated, bad escape, trailing text");
}

fn t22() -> TestResult {
  var ok = parse_err_has("- a", "yaml: malformed list item");
  if !parse_err_has("a:\n- b", "yaml: malformed list item") { ok = false; }
  if !parse_err_has("a:\n  - \n  - b", "yaml: malformed list item") { ok = false; }
  if !parse_err_has("a:\n  - x\n  b: 1", "yaml: malformed list item") { ok = false; }
  if !parse_err_has("a:\n  - [x]", "yaml: malformed list item") { ok = false; }
  if !parse_err_has("a:\n  - b: c", "yaml: malformed list item") { ok = false; }
  if !parse_err_has("a:\n  - - x", "yaml: malformed list item") { ok = false; }
  return assert(ok, "empty, nested and mixed list items are Err");
}

fn t23() -> TestResult {
  var ok = parse_err_has("a: [x, y", "yaml: malformed inline list");
  if !parse_err_has("a: [x,, y]", "yaml: malformed inline list") { ok = false; }
  if !parse_err_has("a: [x, y] junk", "yaml: malformed inline list") { ok = false; }
  if !parse_err_has("a: [x, {y}]", "yaml: malformed inline list") { ok = false; }
  if !parse_err_has("a: [x: y]", "yaml: malformed inline list") { ok = false; }
  if !parse_err_yaml("a: [x") { ok = false; }
  return assert(ok, "malformed inline lists are Err");
}

fn t24() -> TestResult {
  var ok = parse_err_has("no colon here", "yaml: expected 'key: value'");
  if !parse_err_has(": v", "yaml: empty key") { ok = false; }
  if !parse_err_has("\"q\": v", "yaml: quoted keys are not supported") { ok = false; }
  if !parse_err_has("a: b: c", "yaml: malformed value for key: a") { ok = false; }
  if !parse_err_has("a: {x}", "yaml: malformed value for key: a") { ok = false; }
  if !parse_err_has("a: - x", "yaml: malformed value for key: a") { ok = false; }
  return assert(ok, "structural line errors are Err");
}

fn t25() -> TestResult {
  let r1 = yaml_parse("a.b: 1");
  let r2 = yaml_parse("a:\n  b: 2");
  var ok = false;
  match r1 {
    Ok(d1) => {
      ok = yaml_has(&d1, "a.b");
      if !opt_int_is(yaml_get_int(&d1, "a.b"), 1) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  match r2 {
    Ok(d2) => {
      if !yaml_has(&d2, "a.b") { ok = false; }
      if !opt_int_is(yaml_get_int(&d2, "a.b"), 2) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a dotted key and a nested mapping share one flat namespace");
}

fn main() -> Int {
  io.println("=== xiom.yaml conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.yaml: all tests passed");
  } else {
    io.println("xiom.yaml: tests failed");
  }
  return failed;
}
