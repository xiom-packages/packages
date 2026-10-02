// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.salt conformance tests (28 checks)
// Port task: prove the pure-XIOM xiom.salt module against its documented
// model: typed grains with precedence and aggregation, glob / regex-subset /
// grain / compound minion targeting, top-file targeting, pillar merge
// precedence, state declaration and requisite builders, stable topological
// run ordering, require / watch / onchanges execution semantics (including
// the *_in inverses and failure propagation), the canonical run report, and
// the event bus with payload framing and reactor dispatch.
//
// Coverage map: t01 grains builders/types/getters; t02 grain precedence;
// t03 grain merge and aggregation; t04 grains render; t05 glob matching;
// t06 regex literals/dot/quantifiers; t07 regex anchors/escapes; t08 grain
// glob match; t09 grain regex match; t10 compound and/or/not precedence;
// t11 compound parentheses; t12 compound term prefixes; t13 compound error
// catalog; t14 top-file targeting order; t15 top error propagation;
// t16 pillar set/get/level/origin; t17 pillar merge and first position;
// t18 pillar render; t19 state/requisite builders; t20 stable topological
// order; t21 cycle and unknown-id errors; t22 require failure propagation;
// t23 watch triggers; t24 onchanges triggers; t25 inverse requisites;
// t26 canonical run render; t27 event publish/frame; t28 reactor match and
// dispatch order.
//
// All Str equality goes through str_compare (BUG 17: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison), so every comparison
// below is routed through streq / vec_eq / opt_is.

module salt_tests
use xiom.io; use xiom.test; use xiom.salt;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn opt_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn opt_int_is(o: Option[Int], want: Int) -> Bool {
  match o {
    Some(v) => {
      let got: Int = v;
      return got == want;
    },
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
    Some(v) => {
      let got: Bool = v;
      if got && want {
        return true;
      }
      if !got && !want {
        return true;
      }
      return false;
    },
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

fn vec_is(v: &Vec[Str], i: Int, want: Str) -> Bool {
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

fn ints_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn ints2(x: Int, y: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(x);
  v.push(y);
  return v;
}

fn ints3(x: Int, y: Int, z: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(x);
  v.push(y);
  v.push(z);
  return v;
}

fn ints6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

fn strs2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn strs3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn strs5(a: Str, b: Str, c: Str, d: Str, e: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

// The standard grain fixture.
fn facts() -> GrainSet {
  var g = salt_grains_new();
  salt_grains_set_str(&mut g, "os", "Ubuntu", "core");
  salt_grains_set_str(&mut g, "os_family", "Debian", "core");
  salt_grains_set_str(&mut g, "env", "prod", "config");
  salt_grains_set_str(&mut g, "role", "web", "custom");
  salt_grains_set_int(&mut g, "cpus", 4, "config");
  salt_grains_set_bool(&mut g, "master", true, "custom");
  return g;
}

fn tgt_is(id: Str, gs: &GrainSet, expr: Str, want: Bool) -> Bool {
  let r = salt_target_match(id, gs, expr);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn tgt_err(id: Str, gs: &GrainSet, expr: Str, want: Str) -> Bool {
  let r = salt_target_match(id, gs, expr);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn order_is(sls: &SLS, want: &Vec[Int]) -> Bool {
  let r = salt_run_order(sls);
  match r {
    Ok(v) => { return ints_eq(&v, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn order_err(sls: &SLS, want: Str) -> Bool {
  let r = salt_run_order(sls);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn run_err(sls: &SLS, want: Str) -> Bool {
  let r = salt_run(sls);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn run_expect(sls: &SLS, u: Int, n: Int, fl: Int, sk: Int, w: Int, oc: Int, ch: Int) -> Bool {
  let r = salt_run(sls);
  match r {
    Ok(rep) => {
      var ok = rep.applied == u;
      if rep.noop != n { ok = false; }
      if rep.failed != fl { ok = false; }
      if rep.skipped != sk { ok = false; }
      if rep.watches != w { ok = false; }
      if rep.onchanges != oc { ok = false; }
      if rep.changes != ch { ok = false; }
      if rep.total != u + n + fl + sk { ok = false; }
      return ok;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn run_render(sls: &SLS) -> Str {
  let r = salt_run(sls);
  match r {
    Ok(rep) => { return salt_run_render(&rep); },
    Err(e) => { return "ERR:" + e; },
  }
  return "";
}

// t01 -- grain builders, type tags, levels and typed getters.
fn t01() -> TestResult {
  let g = facts();
  var ok = salt_grains_type(&g, "os") == 0;
  if salt_grains_type(&g, "cpus") != 1 { ok = false; }
  if salt_grains_type(&g, "master") != 2 { ok = false; }
  if salt_grains_type(&g, "ghost") != -1 { ok = false; }
  if salt_grains_level(&g, "os") != 0 { ok = false; }
  if salt_grains_level(&g, "env") != 1 { ok = false; }
  if salt_grains_level(&g, "role") != 2 { ok = false; }
  if !opt_is(salt_grains_get_str(&g, "os"), "Ubuntu") { ok = false; }
  if !opt_int_is(salt_grains_get_int(&g, "cpus"), 4) { ok = false; }
  if !opt_bool_is(salt_grains_get_bool(&g, "master"), true) { ok = false; }
  if !opt_none(salt_grains_get_str(&g, "cpus")) { ok = false; }
  if !opt_int_none(salt_grains_get_int(&g, "os")) { ok = false; }
  if !opt_bool_none(salt_grains_get_bool(&g, "ghost")) { ok = false; }
  if g.keys.len() != 6 { ok = false; }
  return assert(ok, "grains: typed builders, levels and typed getters");
}

// t02 -- precedence core < config < custom, same-level last-wins, first
// position kept, unknown level rejected.
fn t02() -> TestResult {
  var g = salt_grains_new();
  salt_grains_set_str(&mut g, "os", "Ubuntu", "core");
  salt_grains_set_str(&mut g, "os", "FreeBSD", "core");
  salt_grains_set_str(&mut g, "os", "Debian", "config");
  salt_grains_set_str(&mut g, "os", "CentOS", "core");
  var ok = opt_is(salt_grains_get_str(&g, "os"), "Debian");
  if salt_grains_level(&g, "os") != 1 { ok = false; }
  if !vec_is(&g.keys, 0, "os") { ok = false; }
  if g.keys.len() != 1 { ok = false; }
  salt_grains_set_str(&mut g, "os", "Gentoo", "custom");
  if !opt_is(salt_grains_get_str(&g, "os"), "Gentoo") { ok = false; }
  if salt_grains_level(&g, "os") != 2 { ok = false; }
  salt_grains_set_str(&mut g, "os", "Late", "config");
  if !opt_is(salt_grains_get_str(&g, "os"), "Gentoo") { ok = false; }
  if salt_grains_set_str(&mut g, "bad", "x", "forced") { ok = false; }
  if salt_grains_type(&g, "bad") != -1 { ok = false; }
  return assert(ok, "grains: core < config < custom, last-wins, first position");
}

// t03 -- grain merge precedence is order-independent and inputs are not
// modified; aggregation counts by type.
fn t03() -> TestResult {
  var a = salt_grains_new();
  salt_grains_set_str(&mut a, "os", "Ubuntu", "core");
  salt_grains_set_str(&mut a, "role", "db", "core");
  salt_grains_set_int(&mut a, "cpus", 2, "core");
  var b = salt_grains_new();
  salt_grains_set_str(&mut b, "os", "Debian", "config");
  salt_grains_set_bool(&mut b, "master", true, "custom");
  let m = salt_grains_merge(&a, &b);
  var ok = opt_is(salt_grains_get_str(&m, "os"), "Debian");
  if salt_grains_level(&m, "os") != 1 { ok = false; }
  if !opt_is(salt_grains_get_str(&m, "role"), "db") { ok = false; }
  if !opt_int_is(salt_grains_get_int(&m, "cpus"), 2) { ok = false; }
  if !opt_bool_is(salt_grains_get_bool(&m, "master"), true) { ok = false; }
  if !opt_is(salt_grains_get_str(&a, "os"), "Ubuntu") { ok = false; }
  let r = salt_grains_merge(&b, &a);
  if !opt_is(salt_grains_get_str(&r, "os"), "Debian") { ok = false; }
  if salt_grains_agg(&m, 0) != 2 { ok = false; }
  if salt_grains_agg(&m, 1) != 1 { ok = false; }
  if salt_grains_agg(&m, 2) != 1 { ok = false; }
  return assert(ok, "grains: merge precedence, immutability and aggregation");
}

// t04 -- canonical grain render.
fn t04() -> TestResult {
  var g = salt_grains_new();
  salt_grains_set_str(&mut g, "os", "Ubuntu", "core");
  salt_grains_set_int(&mut g, "cpus", 4, "config");
  let want = "grains: count=2 str=1 int=1 bool=0\nos=Ubuntu type=str level=core\ncpus=4 type=int level=config";
  var ok = streq(salt_grains_render(&g), want);
  var e = salt_grains_new();
  if !streq(salt_grains_render(&e), "grains: count=0 str=0 int=0 bool=0") { ok = false; }
  return assert(ok, "grains: canonical render");
}

// t05 -- glob matching: '*' and '?' plus exact and empty patterns.
fn t05() -> TestResult {
  var ok = salt_glob_match("web*", "web-01");
  if !salt_glob_match("web?", "web1") { ok = false; }
  if salt_glob_match("web?", "web") { ok = false; }
  if salt_glob_match("web?", "web12") { ok = false; }
  if !salt_glob_match("*", "") { ok = false; }
  if !salt_glob_match("web*", "web") { ok = false; }
  if salt_glob_match("web*", "db") { ok = false; }
  if !salt_glob_match("*db*", "adbc") { ok = false; }
  if !salt_glob_match("a*b*c", "aXbYc") { ok = false; }
  if salt_glob_match("a*b*c", "acb") { ok = false; }
  if !salt_glob_match("", "") { ok = false; }
  if salt_glob_match("", "x") { ok = false; }
  return assert(ok, "targeting: glob '*' and '?'");
}

// t06 -- regex subset: literals, dot and the greedy quantifiers.
fn t06() -> TestResult {
  var ok = salt_regex_match("abc", "xxabcyy");
  if salt_regex_match("abc", "ab") { ok = false; }
  if !salt_regex_match("a.c", "abc") { ok = false; }
  if salt_regex_match("a.c", "ac") { ok = false; }
  if !salt_regex_match("ab*c", "ac") { ok = false; }
  if !salt_regex_match("ab*c", "abbbc") { ok = false; }
  if salt_regex_match("ab*c", "adc") { ok = false; }
  if salt_regex_match("ab+c", "ac") { ok = false; }
  if !salt_regex_match("ab+c", "abc") { ok = false; }
  if !salt_regex_match("ab?c", "ac") { ok = false; }
  if !salt_regex_match("ab?c", "abc") { ok = false; }
  if salt_regex_match("ab?c", "abbc") { ok = false; }
  return assert(ok, "targeting: regex literals, dot and quantifiers");
}

// t07 -- regex anchors, search semantics and escapes.
fn t07() -> TestResult {
  var ok = salt_regex_match("^abc", "abcd");
  if salt_regex_match("^abc$", "abcd") { ok = false; }
  if !salt_regex_match("^abc$", "abc") { ok = false; }
  if !salt_regex_match("c$", "abc") { ok = false; }
  if salt_regex_match("c$", "ab") { ok = false; }
  if !salt_regex_match("b", "abc") { ok = false; }
  if salt_regex_match("^b", "abc") { ok = false; }
  if !salt_regex_match("a\\.b", "a.b") { ok = false; }
  if salt_regex_match("a\\.b", "axb") { ok = false; }
  if !salt_regex_match("", "anything") { ok = false; }
  if !salt_regex_match(".*", "anything") { ok = false; }
  return assert(ok, "targeting: regex anchors, search and escapes");
}

// t08 -- grain glob matching and absence rules.
fn t08() -> TestResult {
  let g = facts();
  var ok = salt_grain_match(&g, "os:Ub*");
  if !salt_grain_match(&g, "os:Ubuntu") { ok = false; }
  if salt_grain_match(&g, "os:ubuntu") { ok = false; }
  if !salt_grain_match(&g, "role:w?b") { ok = false; }
  if !salt_grain_match(&g, "cpus:4") { ok = false; }
  if salt_grain_match(&g, "ghost:*") { ok = false; }
  if salt_grain_match(&g, "nosuch") { ok = false; }
  if salt_grain_match(&g, ":x") { ok = false; }
  return assert(ok, "targeting: grain glob match");
}

// t09 -- grain regex matching and absence rules.
fn t09() -> TestResult {
  let g = facts();
  var ok = salt_grain_match_regex(&g, "os:^U.*u$");
  if !salt_grain_match_regex(&g, "cpus:^4$") { ok = false; }
  if salt_grain_match_regex(&g, "os:^D") { ok = false; }
  if salt_grain_match_regex(&g, "ghost:.*") { ok = false; }
  if salt_grain_match_regex(&g, "os") { ok = false; }
  return assert(ok, "targeting: grain regex match");
}

// t10 -- compound and/or/not precedence: not > and > or.
fn t10() -> TestResult {
  let g = facts();
  var ok = tgt_is("web-01", &g, "G@web* and I@os:Ubuntu", true);
  if !tgt_is("web-01", &g, "G@db* or I@os:Ubuntu", true) { ok = false; }
  if !tgt_is("web-01", &g, "not G@db*", true) { ok = false; }
  if !tgt_is("web-01", &g, "not G@web*", false) { ok = false; }
  if !tgt_is("web-01", &g, "G@db* and G@web* or I@os:Ubuntu", true) { ok = false; }
  if !tgt_is("web-01", &g, "I@os:Ubuntu or G@db* and G@web*", true) { ok = false; }
  if !tgt_is("web-01", &g, "not G@db* and G@web*", true) { ok = false; }
  if tgt_is("web-01", &g, "not G@db* and G@web*", false) { ok = false; }
  return assert(ok, "targeting: compound and/or/not precedence");
}

// t11 -- compound parentheses.
fn t11() -> TestResult {
  let g = facts();
  var ok = tgt_is("web-01", &g, "(G@db* or G@web*) and I@env:prod", true);
  if !tgt_is("web-01", &g, "(G@db* or G@web*) and I@env:dev", false) { ok = false; }
  if !tgt_is("web-01", &g, "((G@web*))", true) { ok = false; }
  if !tgt_is("web-01", &g, "not (G@db* or G@web*)", false) { ok = false; }
  return assert(ok, "targeting: compound parentheses");
}

// t12 -- compound term prefixes G@ E@ I@ P@ and the bare glob.
fn t12() -> TestResult {
  let g = facts();
  var ok = tgt_is("web-01", &g, "E@^web-.+$", true);
  if !tgt_is("web-01", &g, "E@^db-.+$", false) { ok = false; }
  if !tgt_is("web-01", &g, "I@os:Ubu*", true) { ok = false; }
  if !tgt_is("web-01", &g, "P@os:^Ubu.*$", true) { ok = false; }
  if !tgt_is("web-01", &g, "P@os:^Ubu$", false) { ok = false; }
  if !tgt_is("web-01", &g, "web-0?", true) { ok = false; }
  if !tgt_is("web-01", &g, "G@web-0?", true) { ok = false; }
  if !tgt_is("web-01", &g, "G@db*", false) { ok = false; }
  return assert(ok, "targeting: G@ E@ I@ P@ and bare-glob terms");
}

// t13 -- compound error catalog.
fn t13() -> TestResult {
  let g = facts();
  var ok = tgt_err("web-01", &g, "", "salt: targeting: unexpected end of expression");
  if !tgt_err("web-01", &g, "(", "salt: targeting: unexpected end of expression") { ok = false; }
  if !tgt_err("web-01", &g, "(G@web*", "salt: targeting: expected ')'") { ok = false; }
  if !tgt_err("web-01", &g, "G@web* and", "salt: targeting: unexpected end of expression") { ok = false; }
  if !tgt_err("web-01", &g, "I@os", "salt: targeting: malformed grain term: I@os") { ok = false; }
  if !tgt_err("web-01", &g, "P@os", "salt: targeting: malformed grain term: P@os") { ok = false; }
  if !tgt_err("web-01", &g, "G@web* G@db*", "salt: targeting: unexpected token: G@db*") { ok = false; }
  if !tgt_err("web-01", &g, ")", "salt: targeting: unexpected token: )") { ok = false; }
  if !tgt_err("web-01", &g, "or G@web*", "salt: targeting: unexpected token: or") { ok = false; }
  return assert(ok, "targeting: malformed compound expressions");
}

// t14 -- top-file targeting yields SLS names in declaration order.
fn t14() -> TestResult {
  let g = facts();
  var top = salt_top_new();
  salt_top_add(&mut top, "G@web*", "web.sls");
  salt_top_add(&mut top, "I@os:Ubuntu", "base.sls");
  salt_top_add(&mut top, "G@db*", "db.sls");
  salt_top_add(&mut top, "G@web*", "extra.sls");
  let r = salt_top_sls(&top, "web-01", &g);
  var ok = false;
  match r {
    Ok(v) => { ok = vec_eq(&v, &strs3("web.sls", "base.sls", "extra.sls")); },
    Err(_) => { ok = false; },
  }
  let r2 = salt_top_sls(&top, "db-01", &g);
  match r2 {
    Ok(v2) => {
      if !vec_eq(&v2, &strs2("base.sls", "db.sls")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "pillar: top-file targeting order");
}

// t15 -- top-file target errors propagate.
fn t15() -> TestResult {
  let g = facts();
  var top = salt_top_new();
  salt_top_add(&mut top, "G@web* and", "x.sls");
  salt_top_add(&mut top, "G@db*", "db.sls");
  let r = salt_top_sls(&top, "web-01", &g);
  var ok = false;
  match r {
    Ok(_) => { ok = false; },
    Err(e) => { ok = streq(e, "salt: targeting: unexpected end of expression"); },
  }
  return assert(ok, "pillar: top target errors propagate");
}

// t16 -- pillar set/get/level/origin and the precedence rule.
fn t16() -> TestResult {
  var p = salt_pillar_new();
  var ok = salt_pillar_set(&mut p, "port", "80", "base", "default");
  salt_pillar_set(&mut p, "port", "8080", "env", "site");
  salt_pillar_set(&mut p, "port", "9000", "override", "cli");
  if !opt_is(salt_pillar_get(&p, "port"), "9000") { ok = false; }
  if salt_pillar_level(&p, "port") != 2 { ok = false; }
  if !opt_is(salt_pillar_origin(&p, "port"), "cli") { ok = false; }
  salt_pillar_set(&mut p, "port", "1", "base", "late");
  if !opt_is(salt_pillar_get(&p, "port"), "9000") { ok = false; }
  salt_pillar_set(&mut p, "a", "1", "base", "o1");
  salt_pillar_set(&mut p, "a", "2", "base", "o2");
  if !opt_is(salt_pillar_get(&p, "a"), "2") { ok = false; }
  if !opt_is(salt_pillar_origin(&p, "a"), "o2") { ok = false; }
  if salt_pillar_set(&mut p, "x", "y", "forced", "z") { ok = false; }
  if !opt_none(salt_pillar_get(&p, "ghost")) { ok = false; }
  if salt_pillar_level(&p, "ghost") != -1 { ok = false; }
  if !opt_none(salt_pillar_origin(&p, "ghost")) { ok = false; }
  return assert(ok, "pillar: set/get/level/origin precedence");
}

// t17 -- pillar merge: precedence, first position, immutability.
fn t17() -> TestResult {
  var p1 = salt_pillar_new();
  salt_pillar_set(&mut p1, "k", "1", "base", "src1");
  salt_pillar_set(&mut p1, "only_b", "4", "base", "src1");
  var p2 = salt_pillar_new();
  salt_pillar_set(&mut p2, "k", "2", "env", "src2");
  salt_pillar_set(&mut p2, "only_o", "5", "env", "src2");
  let m = salt_pillar_merge(&p1, &p2);
  var ok = opt_is(salt_pillar_get(&m, "k"), "2");
  if salt_pillar_level(&m, "k") != 1 { ok = false; }
  if !opt_is(salt_pillar_origin(&m, "k"), "src2") { ok = false; }
  if !opt_is(salt_pillar_get(&m, "only_b"), "4") { ok = false; }
  if !opt_is(salt_pillar_get(&m, "only_o"), "5") { ok = false; }
  if m.keys.len() != 3 { ok = false; }
  if !vec_is(&m.keys, 0, "k") { ok = false; }
  if !vec_is(&m.keys, 1, "only_b") { ok = false; }
  if !vec_is(&m.keys, 2, "only_o") { ok = false; }
  if !opt_is(salt_pillar_get(&p1, "k"), "1") { ok = false; }
  let m2 = salt_pillar_merge(&p2, &p1);
  if !opt_is(salt_pillar_get(&m2, "k"), "2") { ok = false; }
  if salt_pillar_level(&m2, "k") != 1 { ok = false; }
  if !vec_is(&m2.keys, 0, "k") { ok = false; }
  if !vec_is(&m2.keys, 1, "only_o") { ok = false; }
  if !vec_is(&m2.keys, 2, "only_b") { ok = false; }
  return assert(ok, "pillar: merge precedence and first position");
}

// t18 -- canonical pillar render.
fn t18() -> TestResult {
  var p = salt_pillar_new();
  salt_pillar_set(&mut p, "k", "2", "env", "src2");
  salt_pillar_set(&mut p, "only_b", "4", "base", "src1");
  salt_pillar_set(&mut p, "only_o", "5", "env", "src2");
  let want = "pillar: count=3\nk=2 level=env origin=src2\nonly_b=4 level=base origin=src1\nonly_o=5 level=env origin=src2";
  var ok = streq(salt_pillar_render(&p), want);
  var e = salt_pillar_new();
  if !streq(salt_pillar_render(&e), "pillar: count=0") { ok = false; }
  return assert(ok, "pillar: canonical render");
}

// t19 -- state and requisite builders, validation and accessors.
fn t19() -> TestResult {
  var s = salt_sls_new("web");
  let i0 = salt_state_add(&mut s, "pkg", "pkg.installed", "nginx");
  let i1 = salt_state_add(&mut s, "svc", "service.running", "nginx");
  let i2 = salt_state_add(&mut s, "cfg", "file.managed", "/etc/nginx.conf");
  var ok = i0 == 0 && i1 == 1 && i2 == 2 && salt_state_count(&s) == 3;
  if !streq(salt_state_id(&s, 0), "pkg") { ok = false; }
  if !streq(salt_state_fun(&s, 1), "service.running") { ok = false; }
  if !streq(salt_state_name(&s, 2), "/etc/nginx.conf") { ok = false; }
  if !streq(salt_state_id(&s, 9), "") { ok = false; }
  if salt_state_add(&mut s, "", "pkg.installed", "x") != -1 { ok = false; }
  if salt_state_add(&mut s, "ok2", "", "x") != -1 { ok = false; }
  if salt_state_add(&mut s, "ok3", "pkg.installed", "") != -1 { ok = false; }
  if salt_state_count(&s) != 3 { ok = false; }
  if !salt_state_set_outcome(&mut s, 0, 1, 5) { ok = false; }
  if salt_state_set_outcome(&mut s, 9, 0, 1) { ok = false; }
  if !salt_state_watch(&mut s, 1, "pkg") { ok = false; }
  if salt_state_watch(&mut s, 9, "pkg") { ok = false; }
  if salt_state_watch(&mut s, 1, "") { ok = false; }
  if salt_requisite_count(&s) != 1 { ok = false; }
  if salt_requisite_owner(&s, 0) != 1 { ok = false; }
  if salt_requisite_kind(&s, 0) != 1 { ok = false; }
  if !streq(salt_requisite_target(&s, 0), "pkg") { ok = false; }
  if salt_requisite_kind(&s, 9) != -1 { ok = false; }
  return assert(ok, "states: builders, validation and accessors");
}

// t20 -- stable topological order and declaration-order tie-break.
fn t20() -> TestResult {
  var s = salt_sls_new("chain");
  salt_state_add(&mut s, "pkg", "pkg.installed", "nginx");
  salt_state_add(&mut s, "cfg", "file.managed", "/etc/nginx.conf");
  salt_state_add(&mut s, "svc", "service.running", "nginx");
  salt_state_require(&mut s, 1, "pkg");
  salt_state_require(&mut s, 2, "cfg");
  var ok = order_is(&s, &ints3(0, 1, 2));
  var t = salt_sls_new("reversed");
  salt_state_add(&mut t, "svc", "service.running", "nginx");
  salt_state_add(&mut t, "cfg", "file.managed", "/etc/nginx.conf");
  salt_state_require(&mut t, 0, "cfg");
  if !order_is(&t, &ints2(1, 0)) { ok = false; }
  var d = salt_sls_new("diamond");
  salt_state_add(&mut d, "pkg", "pkg.installed", "nginx");
  salt_state_add(&mut d, "a", "file.managed", "/a");
  salt_state_add(&mut d, "b", "file.managed", "/b");
  salt_state_require(&mut d, 1, "pkg");
  salt_state_require(&mut d, 2, "pkg");
  if !order_is(&d, &ints3(0, 1, 2)) { ok = false; }
  return assert(ok, "states: stable topological order");
}

// t21 -- cycle and unknown-target errors.
fn t21() -> TestResult {
  var s = salt_sls_new("cycle");
  salt_state_add(&mut s, "a", "pkg.installed", "x");
  salt_state_add(&mut s, "b", "pkg.installed", "y");
  salt_state_require(&mut s, 0, "b");
  salt_state_require(&mut s, 1, "a");
  var ok = order_err(&s, "salt: requisite cycle");
  if !run_err(&s, "salt: requisite cycle") { ok = false; }
  var g = salt_sls_new("ghost");
  salt_state_add(&mut g, "a", "pkg.installed", "x");
  salt_state_require(&mut g, 0, "ghost");
  if !order_err(&g, "salt: unknown state id: ghost") { ok = false; }
  if !run_err(&g, "salt: unknown state id: ghost") { ok = false; }
  return assert(ok, "states: cycle and unknown-id errors");
}

// t22 -- require failure propagation and the skip chain.
fn t22() -> TestResult {
  var s = salt_sls_new("prop");
  salt_state_add(&mut s, "pkg", "pkg.installed", "nginx");
  salt_state_add(&mut s, "cfg", "file.managed", "/etc/nginx.conf");
  salt_state_add(&mut s, "svc", "service.running", "nginx");
  salt_state_require(&mut s, 1, "pkg");
  salt_state_require(&mut s, 2, "cfg");
  salt_state_set_outcome(&mut s, 0, 1, 0);
  var ok = run_expect(&s, 0, 0, 1, 2, 0, 0, 0);
  let want = "salt run: total=3 applied=0 noop=0 failed=1 skipped=2\nwatches=0 onchanges=0 changes=0\nevent: failed: pkg\nevent: skipped: cfg (requisite failed: pkg)\nevent: skipped: svc (requisite failed: cfg)";
  if !streq(run_render(&s), want) { ok = false; }
  return assert(ok, "states: require failure propagates as skips");
}

// t23 -- watch triggers fire only when the watched state applied changes.
fn t23() -> TestResult {
  var s = salt_sls_new("watch");
  salt_state_add(&mut s, "tpl", "file.managed", "/etc/app.conf");
  salt_state_add(&mut s, "svc", "service.running", "app");
  salt_state_watch(&mut s, 1, "tpl");
  salt_state_set_outcome(&mut s, 1, 0, 0);
  var ok = run_expect(&s, 1, 1, 0, 0, 1, 0, 1);
  let want = "salt run: total=2 applied=1 noop=1 failed=0 skipped=0\nwatches=1 onchanges=0 changes=1\nevent: applied: tpl (changes=1)\nevent: noop: svc\nevent: watch: tpl -> svc";
  if !streq(run_render(&s), want) { ok = false; }
  var n = salt_sls_new("watch-noop");
  salt_state_add(&mut n, "tpl", "file.managed", "/etc/app.conf");
  salt_state_add(&mut n, "svc", "service.running", "app");
  salt_state_watch(&mut n, 1, "tpl");
  salt_state_set_outcome(&mut n, 0, 0, 0);
  salt_state_set_outcome(&mut n, 1, 0, 0);
  if !run_expect(&n, 0, 2, 0, 0, 0, 0, 0) { ok = false; }
  return assert(ok, "states: watch triggers on change only");
}

// t24 -- onchanges triggers fire only when the watched state applied changes.
fn t24() -> TestResult {
  var s = salt_sls_new("onchanges");
  salt_state_add(&mut s, "tpl", "file.managed", "/etc/app.conf");
  salt_state_add(&mut s, "svc", "service.running", "app");
  salt_state_onchanges(&mut s, 1, "tpl");
  salt_state_set_outcome(&mut s, 1, 0, 0);
  var ok = run_expect(&s, 1, 1, 0, 0, 0, 1, 1);
  let want = "salt run: total=2 applied=1 noop=1 failed=0 skipped=0\nwatches=0 onchanges=1 changes=1\nevent: applied: tpl (changes=1)\nevent: noop: svc\nevent: onchanges: tpl -> svc";
  if !streq(run_render(&s), want) { ok = false; }
  var n = salt_sls_new("onchanges-noop");
  salt_state_add(&mut n, "tpl", "file.managed", "/etc/app.conf");
  salt_state_add(&mut n, "svc", "service.running", "app");
  salt_state_onchanges(&mut n, 1, "tpl");
  salt_state_set_outcome(&mut n, 0, 0, 0);
  salt_state_set_outcome(&mut n, 1, 0, 0);
  if !run_expect(&n, 0, 2, 0, 0, 0, 0, 0) { ok = false; }
  return assert(ok, "states: onchanges triggers on change only");
}

// t25 -- inverse requisites: require_in, watch_in and onchanges_in.
fn t25() -> TestResult {
  var s = salt_sls_new("inverse");
  salt_state_add(&mut s, "a", "pkg.installed", "x");
  salt_state_add(&mut s, "b", "service.running", "x");
  salt_state_require_in(&mut s, 0, "b");
  salt_state_add(&mut s, "w0", "file.managed", "/w0");
  salt_state_add(&mut s, "w1", "service.running", "w1");
  salt_state_watch_in(&mut s, 2, "w1");
  salt_state_add(&mut s, "c0", "file.managed", "/c0");
  salt_state_add(&mut s, "c1", "service.running", "c1");
  salt_state_onchanges_in(&mut s, 4, "c1");
  salt_state_set_outcome(&mut s, 3, 0, 0);
  salt_state_set_outcome(&mut s, 5, 0, 0);
  var ok = order_is(&s, &ints6(0, 1, 2, 3, 4, 5));
  if !run_expect(&s, 4, 2, 0, 0, 1, 1, 4) { ok = false; }
  return assert(ok, "states: inverse requisites order and triggers");
}

// t26 -- canonical run render for a default two-state SLS and an empty SLS.
fn t26() -> TestResult {
  var s = salt_sls_new("run");
  salt_state_add(&mut s, "pkg", "pkg.installed", "nginx");
  salt_state_add(&mut s, "svc", "service.running", "nginx");
  salt_state_require(&mut s, 1, "pkg");
  let want = "salt run: total=2 applied=2 noop=0 failed=0 skipped=0\nwatches=0 onchanges=0 changes=2\nevent: applied: pkg (changes=1)\nevent: applied: svc (changes=1)";
  var ok = streq(run_render(&s), want);
  var e = salt_sls_new("empty");
  if !streq(run_render(&e), "salt run: total=0 applied=0 noop=0 failed=0 skipped=0\nwatches=0 onchanges=0 changes=0") { ok = false; }
  return assert(ok, "states: canonical run render");
}

// t27 -- event publish, payload framing and tag accessors.
fn t27() -> TestResult {
  var buf = salt_eventbuf_new();
  let e0 = salt_event_publish(&mut buf, "salt/job/1/ret");
  let e1 = salt_event_publish(&mut buf, "salt/minion/web-01/start");
  let e2 = salt_event_publish(&mut buf, "salt/minion/web-02/stop");
  var ok = e0 == 0 && e1 == 1 && e2 == 2 && salt_event_count(&buf) == 3;
  if !salt_event_put(&mut buf, e0, "id", "web-01") { ok = false; }
  if !salt_event_put(&mut buf, e0, "fun", "state.sls") { ok = false; }
  if !salt_event_put(&mut buf, e1, "id", "web-01") { ok = false; }
  if !streq(salt_event_tag(&buf, 0), "salt/job/1/ret") { ok = false; }
  if !streq(salt_event_tag(&buf, 7), "") { ok = false; }
  if !streq(salt_event_frame(&buf, 0), "salt/job/1/ret|id=web-01;fun=state.sls") { ok = false; }
  if !streq(salt_event_frame(&buf, 1), "salt/minion/web-01/start|id=web-01") { ok = false; }
  if !streq(salt_event_frame(&buf, 2), "salt/minion/web-02/stop|") { ok = false; }
  if !streq(salt_event_frame(&buf, 9), "") { ok = false; }
  if salt_event_put(&mut buf, 9, "k", "v") { ok = false; }
  if salt_event_put(&mut buf, -1, "k", "v") { ok = false; }
  return assert(ok, "events: publish order, framing and accessors");
}

// t28 -- reactor glob matching and dispatch order.
fn t28() -> TestResult {
  var buf = salt_eventbuf_new();
  salt_event_publish(&mut buf, "salt/job/1/ret");
  salt_event_publish(&mut buf, "salt/minion/web-01/start");
  salt_event_publish(&mut buf, "salt/minion/web-02/stop");
  var r = salt_reactor_new();
  salt_reactor_add(&mut r, "salt/job/*/ret", "state.sls");
  salt_reactor_add(&mut r, "salt/minion/*/start", "grains.items");
  salt_reactor_add(&mut r, "salt/*", "log");
  let m1 = salt_reactor_match(&r, "salt/job/1/ret");
  var ok = vec_eq(&m1, &strs2("state.sls", "log"));
  let m2 = salt_reactor_match(&r, "none");
  var none = Vec[Str].new();
  if !vec_eq(&m2, &none) { ok = false; }
  let d = salt_reactor_dispatch(&r, &buf);
  if !vec_eq(&d, &strs5("0:state.sls", "0:log", "1:grains.items", "1:log", "2:log")) { ok = false; }
  return assert(ok, "reactor: glob match and dispatch order");
}

fn main() -> Int {
  io.println("=== xiom.salt conformance tests ===");
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
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.salt: all tests passed");
  } else {
    io.println("xiom.salt: tests failed");
  }
  return failed;
}
