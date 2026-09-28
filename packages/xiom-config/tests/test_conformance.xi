// XIOM -- xiom.config conformance tests (27 checks)
// Port task: prove the pure-XIOM xiom.config module against its documented
// grammar, merge precedence, typed getters, schema validation and rendering.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: simple pairs, sections and dotted-key normalization, nested and
// reopened sections, full-line and trailing comments, a literal leading '#'
// value, whitespace trimming, empty values, duplicate last-wins/position
// semantics, CRLF/lone-CR/no-final-newline input, the parse error catalog,
// lookup/enumeration and fresh-copy semantics, the entries tuple, merge
// precedence defaults <- file <- overrides, merge/set edge cases, str/int/
// bool getters with defaults and Err variants (including range errors and the
// documented int minimum rejection), schema pass, schema multi-error ordering,
// allowed-list token trimming, schema alignment guard, canonical rendering
// and render -> parse round trips.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/str_vec_is/opt_str_is instead of `==`.

module config_tests
use xiom.io; use xiom.test; use xiom.config;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
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

fn str_vec_is(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() {
    return false;
  }
  let got: Str = v[i];
  return streq(got, want);
}

fn vec_eq(a: &Vec[Str], b: &Vec[Str]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Str = a[i];
    let y: Str = b[i];
    if !streq(x, y) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Length of the parsed config, or -1 when the text fails to parse.
fn parse_ok_len(text: Str) -> Int {
  let r = config_parse(text);
  match r {
    Ok(c) => { return config_len(&c); },
    Err(_) => { return -1; },
  }
  return -1;
}

// True when `key` parses to exactly `want`.
fn parse_get_is(text: Str, key: Str, want: Str) -> Bool {
  let r = config_parse(text);
  match r {
    Ok(c) => { return opt_str_is(config_get(&c, key), want); },
    Err(_) => { return false; },
  }
  return false;
}

// True when parsing fails with exactly the error `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = config_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn try_str_ok_is(c: &Config, key: Str, want: Str) -> Bool {
  let r = config_try_str(c, key);
  match r {
    Ok(v) => { return streq(v, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn try_str_err_is(c: &Config, key: Str, want: Str) -> Bool {
  let r = config_try_str(c, key);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn try_int_ok_is(c: &Config, key: Str, want: Int) -> Bool {
  let r = config_try_int(c, key);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn try_int_err_is(c: &Config, key: Str, want: Str) -> Bool {
  let r = config_try_int(c, key);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn try_bool_ok_is(c: &Config, key: Str, want: Bool) -> Bool {
  let r = config_try_bool(c, key);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn try_bool_err_is(c: &Config, key: Str, want: Str) -> Bool {
  let r = config_try_bool(c, key);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn t01() -> TestResult {
  let text = "host = localhost\nport = 8080";
  var ok = parse_ok_len(text) == 2;
  if !parse_get_is(text, "host", "localhost") { ok = false; }
  if !parse_get_is(text, "port", "8080") { ok = false; }
  if parse_get_is(text, "HOST", "localhost") { ok = false; }
  if parse_get_is(text, "missing", "x") { ok = false; }
  return assert(ok, "parse: simple pairs, lookups are case-sensitive");
}

fn t02() -> TestResult {
  let text = "[server]\nhost = localhost\n[db]\nserver.host = replica\nnested.name = x";
  var ok = parse_ok_len(text) == 3;
  if !parse_get_is(text, "server.host", "localhost") { ok = false; }
  if !parse_get_is(text, "db.server.host", "replica") { ok = false; }
  if !parse_get_is(text, "db.nested.name", "x") { ok = false; }
  return assert(ok, "parse: sections prefix plain keys, dotted keys compose");
}

fn t03() -> TestResult {
  let text = "[a.b]\nk = 1\n[empty]\n[a.b]\nj = 2";
  var ok = parse_ok_len(text) == 2;
  if !parse_get_is(text, "a.b.k", "1") { ok = false; }
  if !parse_get_is(text, "a.b.j", "2") { ok = false; }
  return assert(ok, "parse: nested sections and reopened sections merge");
}

fn t04() -> TestResult {
  let text = "# full line\n; also full\n   # indented\n\ncolor = #ff0000\nname = a#b\nmsg = hello ; note\nkey = v # note\n";
  var ok = parse_ok_len(text) == 4;
  if !parse_get_is(text, "color", "#ff0000") { ok = false; }
  if !parse_get_is(text, "name", "a#b") { ok = false; }
  if !parse_get_is(text, "msg", "hello") { ok = false; }
  if !parse_get_is(text, "key", "v") { ok = false; }
  return assert(ok, "parse: comments are cut, a leading '#' stays literal");
}

fn t05() -> TestResult {
  let text = "  a  =  one two  \n\tb\t=\t\nc = x\ty";
  var ok = parse_ok_len(text) == 3;
  if !parse_get_is(text, "a", "one two") { ok = false; }
  if !parse_get_is(text, "b", "") { ok = false; }
  if !parse_get_is(text, "c", "x\ty") { ok = false; }
  return assert(ok, "parse: whitespace trims at both ends, empty values stay empty");
}

fn t06() -> TestResult {
  let text = "a = 1\nb = 2\na = 3";
  let r = config_parse(text);
  var ok = false;
  match r {
    Ok(c) => {
      let ks = config_keys(&c);
      ok = config_len(&c) == 2;
      if !opt_str_is(config_get(&c, "a"), "3") { ok = false; }
      if !opt_str_is(config_get(&c, "b"), "2") { ok = false; }
      if !str_vec_is(&ks, 0, "a") { ok = false; }
      if !str_vec_is(&ks, 1, "b") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse: duplicates last-wins, first position kept");
}

fn t07() -> TestResult {
  var ok = parse_ok_len("x = 1\r\ny = 2\r\nz = 3") == 3;
  if !parse_get_is("x = 1\r\ny = 2\r\nz = 3", "z", "3") { ok = false; }
  if parse_ok_len("p = 1\rq = 2") != 2 { ok = false; }
  if !parse_get_is("p = 1\rq = 2", "q", "2") { ok = false; }
  if parse_ok_len("only = last") != 1 { ok = false; }
  return assert(ok, "parse: CRLF, lone CR and a final line without newline");
}

fn t08() -> TestResult {
  var ok = parse_err_is("justkey", "config: expected '=' in line: justkey");
  if !parse_err_is("= 1", "config: missing key in line: = 1") { ok = false; }
  if !parse_err_is("a b = 1", "config: malformed key in line: a b = 1") { ok = false; }
  if !parse_err_is("a..b = 1", "config: malformed key in line: a..b = 1") { ok = false; }
  if !parse_err_is("a. = 1", "config: malformed key in line: a. = 1") { ok = false; }
  if !parse_err_is(".a = 1", "config: malformed key in line: .a = 1") { ok = false; }
  if !parse_err_is("a#b = 1", "config: malformed key in line: a#b = 1") { ok = false; }
  return assert(ok, "parse errors: missing '=', empty key, malformed dotted keys");
}

fn t09() -> TestResult {
  var ok = parse_err_is("[x", "config: malformed section header in line: [x");
  if !parse_err_is("[]", "config: empty section header in line: []") { ok = false; }
  if !parse_err_is("[a b]", "config: malformed section header in line: [a b]") { ok = false; }
  if !parse_err_is("[a..b]", "config: malformed section header in line: [a..b]") { ok = false; }
  if !parse_err_is("[x] junk", "config: unexpected text after section header in line: [x] junk") { ok = false; }
  if parse_ok_len("[x] # comment\na = 1") != 1 { ok = false; }
  return assert(ok, "parse errors: malformed headers, trailing comment allowed");
}

fn t10() -> TestResult {
  let r = config_parse("a = 1\nb = 2");
  var ok = false;
  match r {
    Ok(c) => {
      ok = config_len(&c) == 2;
      if !config_has(&c, "a") { ok = false; }
      if config_has(&c, "zz") { ok = false; }
      if !opt_str_none(config_get(&c, "zz")) { ok = false; }
      var ks = config_keys(&c);
      var vs = config_values(&c);
      if !str_vec_is(&ks, 0, "a") { ok = false; }
      if !str_vec_is(&vs, 1, "2") { ok = false; }
      ks.push("mutated");
      vs.push("mutated");
      if config_len(&c) != 2 { ok = false; }
      if config_has(&c, "mutated") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "lookup, has, len and fresh-copy enumeration");
}

fn t11() -> TestResult {
  let r = config_parse("[s]\nb = 2\na = 1");
  var ok = false;
  match r {
    Ok(c) => {
      let pair = config_entries(&c);
      let ks = pair.0;
      let vs = pair.1;
      ok = ks.len() == 2;
      if vs.len() != 2 { ok = false; }
      if !str_vec_is(&ks, 0, "s.b") { ok = false; }
      if !str_vec_is(&vs, 0, "2") { ok = false; }
      if !str_vec_is(&ks, 1, "s.a") { ok = false; }
      if !str_vec_is(&vs, 1, "1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "entries returns parallel (keys, values) copies");
}

fn t12() -> TestResult {
  var defaults = config_new();
  defaults = config_set(&defaults, "host", "localhost");
  defaults = config_set(&defaults, "port", "80");
  var file = config_set(&defaults, "port", "8080");
  file = config_set(&file, "debug", "false");
  var overrides = config_new();
  overrides = config_set(&overrides, "port", "9000");
  overrides = config_set(&overrides, "name", "svc");
  let merged = config_resolve(&defaults, &file, &overrides);
  let pair = config_entries(&merged);
  let ks = pair.0;
  let vs = pair.1;
  var ok = config_len(&merged) == 4;
  if !str_vec_is(&ks, 0, "host") { ok = false; }
  if !str_vec_is(&ks, 1, "port") { ok = false; }
  if !str_vec_is(&ks, 2, "debug") { ok = false; }
  if !str_vec_is(&ks, 3, "name") { ok = false; }
  if !str_vec_is(&vs, 0, "localhost") { ok = false; }
  if !str_vec_is(&vs, 1, "9000") { ok = false; }
  if !str_vec_is(&vs, 2, "false") { ok = false; }
  if !str_vec_is(&vs, 3, "svc") { ok = false; }
  if !opt_str_is(config_get(&defaults, "port"), "80") { ok = false; }
  if config_has(&overrides, "host") { ok = false; }
  return assert(ok, "merge: defaults <- file <- overrides, inputs untouched");
}

fn t13() -> TestResult {
  var a = config_new();
  a = config_set(&a, "k", "v");
  let empty = config_new();
  let m1 = config_merge(&empty, &a);
  let m2 = config_merge(&a, &empty);
  let m3 = config_merge(&empty, &empty);
  var ok = config_len(&m1) == 1;
  if !opt_str_is(config_get(&m1, "k"), "v") { ok = false; }
  if config_len(&m2) != 1 { ok = false; }
  if config_len(&m3) != 0 { ok = false; }
  return assert(ok, "merge: empty base and empty overlay are identity");
}

fn t14() -> TestResult {
  let c = config_parse("a = 1\nb = 2\nc = 3");
  var ok = false;
  match c {
    Ok(base) => {
      var set = config_set(&base, "b", "9");
      set = config_set(&set, "d", "4");
      let ks = config_keys(&set);
      ok = config_len(&set) == 4;
      if !str_vec_is(&ks, 0, "a") { ok = false; }
      if !str_vec_is(&ks, 1, "b") { ok = false; }
      if !str_vec_is(&ks, 3, "d") { ok = false; }
      if !opt_str_is(config_get(&set, "b"), "9") { ok = false; }
      if !opt_str_is(config_get(&base, "b"), "2") { ok = false; }
      if config_len(&base) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "config_set: replace keeps position, new key appends");
}

fn t15() -> TestResult {
  let r = config_parse("s = hello\nempty =");
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(config_get_str(&c, "s", "dflt"), "hello");
      if !streq(config_get_str(&c, "empty", "dflt"), "") { ok = false; }
      if !streq(config_get_str(&c, "zz", "dflt"), "dflt") { ok = false; }
      if !try_str_ok_is(&c, "s", "hello") { ok = false; }
      if !try_str_err_is(&c, "zz", "config: missing key: zz") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "str getter: value, empty value, default and Err");
}

fn t16() -> TestResult {
  let text = "a = 42\nb = -7\nc = +5\nd = 0\ne = 9223372036854775807\nf = -9223372036854775807\ng = 007";
  let r = config_parse(text);
  var ok = false;
  match r {
    Ok(c) => {
      ok = try_int_ok_is(&c, "a", 42);
      if !try_int_ok_is(&c, "b", -7) { ok = false; }
      if !try_int_ok_is(&c, "c", 5) { ok = false; }
      if !try_int_ok_is(&c, "d", 0) { ok = false; }
      if !try_int_ok_is(&c, "e", 9223372036854775807) { ok = false; }
      if !try_int_ok_is(&c, "f", -9223372036854775807) { ok = false; }
      if !try_int_ok_is(&c, "g", 7) { ok = false; }
      if config_get_int(&c, "a", -1) != 42 { ok = false; }
      if config_get_int(&c, "zz", -1) != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "int getter: signs, zeros, 64-bit bounds and defaults");
}

fn t17() -> TestResult {
  let r = config_parse("t = abc\nu =\nv = 12 3\nw = +\nx = 1+\ny = -");
  var ok = false;
  match r {
    Ok(c) => {
      ok = try_int_err_is(&c, "t", "config: invalid integer for key t: abc");
      if !try_int_err_is(&c, "u", "config: invalid integer for key u: ") { ok = false; }
      if !try_int_err_is(&c, "v", "config: invalid integer for key v: 12 3") { ok = false; }
      if !try_int_err_is(&c, "w", "config: invalid integer for key w: +") { ok = false; }
      if !try_int_err_is(&c, "x", "config: invalid integer for key x: 1+") { ok = false; }
      if !try_int_err_is(&c, "y", "config: invalid integer for key y: -") { ok = false; }
      if !try_int_err_is(&c, "zz", "config: missing key: zz") { ok = false; }
      if config_get_int(&c, "t", 99) != 99 { ok = false; }
      if config_get_int(&c, "zz", 7) != 7 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "int getter errors: malformed text, missing key, defaults");
}

fn t18() -> TestResult {
  let r = config_parse("big = 9223372036854775808\nnegmin = -9223372036854775808\nhuge = 99999999999999999999");
  var ok = false;
  match r {
    Ok(c) => {
      ok = try_int_err_is(&c, "big", "config: integer out of range for key big: 9223372036854775808");
      if !try_int_err_is(&c, "negmin", "config: integer out of range for key negmin: -9223372036854775808") { ok = false; }
      if !try_int_err_is(&c, "huge", "config: integer out of range for key huge: 99999999999999999999") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "int getter errors: range overflow and the documented minimum");
}

fn t19() -> TestResult {
  let r = config_parse("a = true\nb = FALSE\nc = Yes\nd = no\ne = 1\nf = 0\ng = TrUe\nh = NO");
  var ok = false;
  match r {
    Ok(c) => {
      ok = config_get_bool(&c, "a", false);
      if config_get_bool(&c, "b", true) { ok = false; }
      if !config_get_bool(&c, "c", false) { ok = false; }
      if config_get_bool(&c, "d", true) { ok = false; }
      if !config_get_bool(&c, "e", false) { ok = false; }
      if config_get_bool(&c, "f", true) { ok = false; }
      if !config_get_bool(&c, "g", false) { ok = false; }
      if config_get_bool(&c, "h", true) { ok = false; }
      if !try_bool_ok_is(&c, "a", true) { ok = false; }
      if !try_bool_ok_is(&c, "b", false) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bool getter: true/false/1/0/yes/no, ASCII case-insensitive");
}

fn t20() -> TestResult {
  let r = config_parse("a = maybe\nb = on\nok = yes");
  var ok = false;
  match r {
    Ok(c) => {
      ok = !config_get_bool(&c, "a", false);
      if config_get_bool(&c, "a", true) != true { ok = false; }
      if config_get_bool(&c, "b", false) { ok = false; }
      if !try_bool_ok_is(&c, "ok", true) { ok = false; }
      if !try_bool_err_is(&c, "a", "config: invalid boolean for key a: maybe") { ok = false; }
      if !try_bool_err_is(&c, "b", "config: invalid boolean for key b: on") { ok = false; }
      if !try_bool_err_is(&c, "zz", "config: missing key: zz") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bool errors: invalid text, 'on' rejected, missing key, defaults");
}

fn t21() -> TestResult {
  let r = config_parse("host = localhost\nport = 8080\ndebug = no\nmode = fast");
  var ok = false;
  match r {
    Ok(c) => {
      var s = config_schema_new();
      s = config_schema_add(&s, "host", "str", true, "");
      s = config_schema_add(&s, "port", "int", true, "");
      s = config_schema_add(&s, "debug", "bool", false, "");
      s = config_schema_add(&s, "mode", "str", false, "fast,slow");
      s = config_schema_add(&s, "optional_missing", "str", false, "");
      let errs = config_validate(&c, &s);
      ok = errs.len() == 0;
      if !config_valid(&c, &s) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "schema pass: required present, optional missing, enum ok");
}

fn t22() -> TestResult {
  let r = config_parse("port = nope\ndebug = maybe\nmode = turbo\nname = x");
  var ok = false;
  match r {
    Ok(c) => {
      var s = config_schema_new();
      s = config_schema_add(&s, "host", "str", true, "");
      s = config_schema_add(&s, "port", "int", true, "");
      s = config_schema_add(&s, "debug", "bool", true, "");
      s = config_schema_add(&s, "mode", "str", false, "fast,slow");
      s = config_schema_add(&s, "extra", "flt", false, "");
      let errs = config_validate(&c, &s);
      ok = errs.len() == 5;
      if !str_vec_is(&errs, 0, "config: missing required key: host") { ok = false; }
      if !str_vec_is(&errs, 1, "config: invalid integer for key port: nope") { ok = false; }
      if !str_vec_is(&errs, 2, "config: invalid boolean for key debug: maybe") { ok = false; }
      if !str_vec_is(&errs, 3, "config: value not allowed for key mode: turbo") { ok = false; }
      if !str_vec_is(&errs, 4, "config: unknown schema type for key extra: flt") { ok = false; }
      if config_valid(&c, &s) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "schema fails with ALL errors in schema order");
}

fn t23() -> TestResult {
  let r = config_parse("d = 8\nloose = elsewhere");
  var ok = false;
  match r {
    Ok(c) => {
      var s = config_schema_new();
      s = config_schema_add(&s, "d", "int", false, " 7 , 8 ");
      s = config_schema_add(&s, "q", "str", false, "a,b");
      let errs = config_validate(&c, &s);
      ok = errs.len() == 0;
    },
    Err(_) => { ok = false; },
  }
  let r2 = config_parse("d = 9");
  var ok2 = false;
  match r2 {
    Ok(c2) => {
      var s2 = config_schema_new();
      s2 = config_schema_add(&s2, "d", "int", false, " 7 , 8 ");
      let errs2 = config_validate(&c2, &s2);
      ok2 = errs2.len() == 1;
      if !str_vec_is(&errs2, 0, "config: value not allowed for key d: 9") { ok2 = false; }
    },
    Err(_) => { ok2 = false; },
  }
  return assert(ok && ok2, "allowed tokens trim, unlisted config keys are ignored");
}

fn t24() -> TestResult {
  let r = config_parse("a = 1\nb = 2");
  var ok = false;
  match r {
    Ok(c) => {
      let s = Schema{ keys: Vec[Str].new(); types: Vec[Str].new(); required: Vec[Int].new(); allowed: Vec[Str].new(); };
      s.keys.push("a");
      s.keys.push("b");
      s.types.push("int");
      s.required.push(0);
      s.allowed.push("");
      let errs = config_validate(&c, &s);
      ok = errs.len() == 1;
      if !str_vec_is(&errs, 0, "config: schema vectors are not aligned at index 1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "misaligned schema vectors are reported, not crashing");
}

fn t25() -> TestResult {
  let r = config_parse("[s]\nb = 2\na = 1\n# c\n");
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(config_render(&c), "s.b = 2\ns.a = 1");
    },
    Err(_) => { ok = false; },
  }
  let empty = config_new();
  if !streq(config_render(&empty), "") { ok = false; }
  return assert(ok, "render: insertion order, dotted keys, empty config");
}

fn t26() -> TestResult {
  let text = "# top\n[server]\nhost = localhost\nport = 8080 # inline\n\n[db]\nurl = postgres://x\nname = main\nname = test\n";
  let r = config_parse(text);
  var ok = false;
  match r {
    Ok(c) => {
      let out = config_render(&c);
      let r2 = config_parse(out);
      match r2 {
        Ok(c2) => {
          let p1 = config_entries(&c);
          let p2 = config_entries(&c2);
          ok = vec_eq(&p1.0, &p2.0) && vec_eq(&p1.1, &p2.1);
          if config_len(&c) != 4 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "render -> parse round-trip preserves keys and values");
}

fn t27() -> TestResult {
  let r1 = config_parse("[a]\nx = 1");
  let r2 = config_parse("[b]\nx = 2\ny = 3");
  var ok = false;
  match r1 {
    Ok(base) => {
      match r2 {
        Ok(over) => {
          let m = config_merge(&base, &over);
          let out = config_render(&m);
          ok = streq(out, "a.x = 1\nb.x = 2\nb.y = 3");
          let r3 = config_parse(out);
          match r3 {
            Ok(m2) => {
              let p1 = config_entries(&m);
              let p2 = config_entries(&m2);
              if !vec_eq(&p1.0, &p2.0) { ok = false; }
              if !vec_eq(&p1.1, &p2.1) { ok = false; }
            },
            Err(_) => { ok = false; },
          }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "merged config renders canonically and round-trips");
}

fn main() -> Int {
  io.println("=== xiom.config conformance tests ===");
  var failed: Int = 0;
  let r01 = t01();
  if r01.passed { io.println("  [PASS] " + r01.name); } else { io.println("  [FAIL] " + r01.name); failed = failed + 1; }
  let r02 = t02();
  if r02.passed { io.println("  [PASS] " + r02.name); } else { io.println("  [FAIL] " + r02.name); failed = failed + 1; }
  let r03 = t03();
  if r03.passed { io.println("  [PASS] " + r03.name); } else { io.println("  [FAIL] " + r03.name); failed = failed + 1; }
  let r04 = t04();
  if r04.passed { io.println("  [PASS] " + r04.name); } else { io.println("  [FAIL] " + r04.name); failed = failed + 1; }
  let r05 = t05();
  if r05.passed { io.println("  [PASS] " + r05.name); } else { io.println("  [FAIL] " + r05.name); failed = failed + 1; }
  let r06 = t06();
  if r06.passed { io.println("  [PASS] " + r06.name); } else { io.println("  [FAIL] " + r06.name); failed = failed + 1; }
  let r07 = t07();
  if r07.passed { io.println("  [PASS] " + r07.name); } else { io.println("  [FAIL] " + r07.name); failed = failed + 1; }
  let r08 = t08();
  if r08.passed { io.println("  [PASS] " + r08.name); } else { io.println("  [FAIL] " + r08.name); failed = failed + 1; }
  let r09 = t09();
  if r09.passed { io.println("  [PASS] " + r09.name); } else { io.println("  [FAIL] " + r09.name); failed = failed + 1; }
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
  if failed == 0 {
    io.println("xiom.config: all tests passed");
  } else {
    io.println("xiom.config: tests failed");
  }
  return failed;
}
