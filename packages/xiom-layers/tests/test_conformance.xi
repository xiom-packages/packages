// XIOM -- xiom.layers conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.layers module against its documented
// precedence, sentinel, provenance, shadowed-value, flattening and diff
// rules with deterministic fixture-driven checks.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: later-layer precedence and first-introduction order, the
// explicit replace sentinel, append folding and fresh appends, append after
// delete, tombstones and resurrection, shadowed-layer/value queries, the
// "!!" escape and near-miss sentinels, empty append payloads, provenance
// through mixed entry kinds, order stability across delete/resurrect,
// layers_add validation (name, alignment, key and duplicate rules), the
// layer diff (added/removed/changed) and its errors, FlatMap queries and
// canonical rendering, tombstone ordering, purity/determinism, control-byte
// passthrough and the public predicates.
//
// All Str equality goes through compare.str_compare (BUG 17 lowers `==` on
// Str values read from Vec[Str] elements to a pointer comparison), and every
// element read below binds to a typed local first.

module layers_tests
use xiom.io; use xiom.test; use xiom.layers;
use xiom.string.compare; use xiom.core;

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

fn str_vec_is(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() {
    return false;
  }
  let got: Str = v[i];
  return streq(got, want);
}

fn int_vec_is(v: &Vec[Int], i: Int, want: Int) -> Bool {
  if i < 0 || i >= v.len() {
    return false;
  }
  let got: Int = v[i];
  return got == want;
}

fn str_vec_eq(a: &Vec[Str], b: &Vec[Str]) -> Bool {
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

// True when the map holds `key` with value `want` and winning layer
// `want_layer`.
fn map_is(m: &FlatMap, key: Str, want: Str, want_layer: Int) -> Bool {
  let o = flatmap_get(m, key);
  if !opt_str_is(o, want) {
    return false;
  }
  let l = flatmap_layer(m, key);
  return opt_int_is(l, want_layer);
}

// One-element Str vector.
fn sv1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

// Two-element Str vector.
fn sv2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

// Three-element Str vector.
fn sv3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

// Four-element Str vector.
fn sv4(a: Str, b: Str, c: Str, d: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

// Build a one-layer stack; a fixture that fails to add is a test bug and
// aborts with the layers_add error message.
fn stack1(name: Str, ks: &Vec[Str], vs: &Vec[Str]) -> LayerStack {
  let s = layers_new();
  return add_ok(&s, name, ks, vs);
}

// layers_add with the Ok value returned; Err panics (fixture bug).
fn add_ok(s: &LayerStack, name: Str, ks: &Vec[Str], vs: &Vec[Str]) -> LayerStack {
  let r = layers_add(s, name, ks, vs);
  match r {
    Ok(ns) => { return ns; },
    Err(e) => { core.panic("layers fixture: " + e); },
  }
  return layers_new();
}

// True when layers_add fails with exactly the error `want`.
fn add_err_is(s: &LayerStack, name: Str, ks: &Vec[Str], vs: &Vec[Str], want: Str) -> Bool {
  let r = layers_add(s, name, ks, vs);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when layers_diff fails with exactly the error `want`.
fn diff_err_is(s: &LayerStack, base: Int, other: Int, want: Str) -> Bool {
  let r = layers_diff(s, base, other);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// --------------------------------------------------
//  t01-t08: precedence, sentinels, provenance, shadowed values
// --------------------------------------------------

fn t01() -> TestResult {
  let k0 = sv2("a", "b");
  let v0 = sv2("1", "2");
  let s = stack1("defaults", &k0, &v0);
  let k1 = sv1("a");
  let v1 = sv1("3");
  let s2 = add_ok(&s, "overrides", &k1, &v1);
  let m = layers_flatten(&s2);
  var ok = flatmap_len(&m) == 2;
  if !map_is(&m, "a", "3", 1) { ok = false; }
  if !map_is(&m, "b", "2", 0) { ok = false; }
  let mk = flatmap_keys(&m);
  if !str_vec_is(&mk, 0, "a") { ok = false; }
  if !str_vec_is(&mk, 1, "b") { ok = false; }
  return assert(ok, "flatten: later layer wins per key, first-introduction order kept");
}

fn t02() -> TestResult {
  let k0 = sv1("a");
  let v0 = sv1("1");
  let s = stack1("base", &k0, &v0);
  let k1 = sv1("a");
  let v1 = sv1("!replace:9");
  let s2 = add_ok(&s, "top", &k1, &v1);
  let m = layers_flatten(&s2);
  var ok = map_is(&m, "a", "9", 1);
  if !layers_is_replace("!replace:9") { ok = false; }
  if layers_is_replace("9") { ok = false; }
  if layers_is_replace("!replace") { ok = false; }
  return assert(ok, "replace: the explicit sentinel equals a plain set");
}

fn t03() -> TestResult {
  let k0 = sv1("a");
  let v0 = sv1("one");
  let s0 = stack1("base", &k0, &v0);
  let k1 = sv1("a");
  let v1 = sv1("!append:two");
  let s1 = add_ok(&s0, "mid", &k1, &v1);
  let k2 = sv2("a", "b");
  let v2 = sv2("!append:three", "!append:solo");
  let s2 = add_ok(&s1, "top", &k2, &v2);
  let m = layers_flatten(&s2);
  var ok = map_is(&m, "a", "one,two,three", 2);
  if !map_is(&m, "b", "solo", 2) { ok = false; }
  if !layers_is_append("!append:x") { ok = false; }
  if layers_is_append("!append") { ok = false; }
  return assert(ok, "append: folds in layer order, fresh when the key is new");
}

fn t04() -> TestResult {
  let k0 = sv1("a");
  let v0 = sv1("one");
  let s0 = stack1("base", &k0, &v0);
  let k1 = sv1("a");
  let v1 = sv1("!delete");
  let s1 = add_ok(&s0, "mid", &k1, &v1);
  let k2 = sv1("a");
  let v2 = sv1("!append:x");
  let s2 = add_ok(&s1, "top", &k2, &v2);
  let m = layers_flatten(&s2);
  var ok = map_is(&m, "a", "x", 2);
  let sl = layers_shadowed_layers(&s2, "a");
  let sv = layers_shadowed_values(&s2, "a");
  if sl.len() != 2 { ok = false; }
  if !int_vec_is(&sl, 0, 0) { ok = false; }
  if !int_vec_is(&sl, 1, 1) { ok = false; }
  if !str_vec_is(&sv, 0, "one") { ok = false; }
  if !str_vec_is(&sv, 1, "!delete") { ok = false; }
  if !layers_is_delete("!delete") { ok = false; }
  if layers_is_delete("!delete ") { ok = false; }
  return assert(ok, "append after delete starts fresh; the tombstone stays shadowed");
}

fn t05() -> TestResult {
  let k0 = sv2("a", "b");
  let v0 = sv2("1", "2");
  let s0 = stack1("base", &k0, &v0);
  let k1 = sv1("b");
  let v1 = sv1("!delete");
  let s1 = add_ok(&s0, "top", &k1, &v1);
  let m = layers_flatten(&s1);
  var ok = flatmap_len(&m) == 1;
  if !flatmap_has(&m, "a") { ok = false; }
  if flatmap_has(&m, "b") { ok = false; }
  if !opt_str_none(flatmap_get(&m, "b")) { ok = false; }
  if !opt_int_none(flatmap_layer(&m, "b")) { ok = false; }
  if !layers_has(&s1, "b") { ok = false; }
  if !opt_int_is(layers_winner(&s1, "b"), 1) { ok = false; }
  let tb = layers_tombstones(&s1);
  if tb.len() != 1 { ok = false; }
  if !str_vec_is(&tb, 0, "b") { ok = false; }
  return assert(ok, "delete: tombstones the key in the flat map, records provenance");
}

fn t06() -> TestResult {
  let k0 = sv1("a");
  let v0 = sv1("1");
  let s0 = stack1("base", &k0, &v0);
  let k1 = sv1("a");
  let v1 = sv1("!delete");
  let s1 = add_ok(&s0, "mid", &k1, &v1);
  let k2 = sv1("a");
  let v2 = sv1("9");
  let s2 = add_ok(&s1, "top", &k2, &v2);
  let m = layers_flatten(&s2);
  var ok = map_is(&m, "a", "9", 2);
  if !opt_int_is(layers_winner(&s2, "a"), 2) { ok = false; }
  let tb = layers_tombstones(&s2);
  if tb.len() != 0 { ok = false; }
  let sl = layers_shadowed_layers(&s2, "a");
  let sv = layers_shadowed_values(&s2, "a");
  if sl.len() != 2 { ok = false; }
  if !str_vec_is(&sv, 0, "1") { ok = false; }
  if !str_vec_is(&sv, 1, "!delete") { ok = false; }
  return assert(ok, "delete then resurrect: the key is live again, winner is the revival layer");
}

fn t07() -> TestResult {
  let k0 = sv1("a");
  let v0 = sv1("1");
  let s0 = stack1("l0", &k0, &v0);
  let k1 = sv1("a");
  let v1 = sv1("2");
  let s1 = add_ok(&s0, "l1", &k1, &v1);
  let k2 = sv1("a");
  let v2 = sv1("3");
  let s2 = add_ok(&s1, "l2", &k2, &v2);
  let m = layers_flatten(&s2);
  var ok = map_is(&m, "a", "3", 2);
  let sl = layers_shadowed_layers(&s2, "a");
  let sv = layers_shadowed_values(&s2, "a");
  if sl.len() != 2 { ok = false; }
  if !int_vec_is(&sl, 0, 0) { ok = false; }
  if !int_vec_is(&sl, 1, 1) { ok = false; }
  if !str_vec_is(&sv, 0, "1") { ok = false; }
  if !str_vec_is(&sv, 1, "2") { ok = false; }
  if !opt_int_is(layers_winner(&s2, "a"), 2) { ok = false; }
  return assert(ok, "shadowed: losing entries in stack order, raw texts aligned with layers");
}

fn t08() -> TestResult {
  let k0 = sv1("a");
  let v0 = sv1("1");
  let s = stack1("base", &k0, &v0);
  let sl = layers_shadowed_layers(&s, "missing");
  let sv = layers_shadowed_values(&s, "missing");
  let m = layers_flatten(&s);
  var ok = sl.len() == 0;
  if sv.len() != 0 { ok = false; }
  if layers_has(&s, "missing") { ok = false; }
  if !opt_int_none(layers_winner(&s, "missing")) { ok = false; }
  if flatmap_has(&m, "missing") { ok = false; }
  if !opt_str_none(flatmap_get(&m, "missing")) { ok = false; }
  if !opt_int_none(flatmap_layer(&m, "missing")) { ok = false; }
  return assert(ok, "absent key: empty shadow vectors, no provenance, absent from the map");
}

// --------------------------------------------------
//  t09-t13: escapes, near-miss literals, empty payloads, order stability
// --------------------------------------------------

fn t09() -> TestResult {
  let k = sv3("a", "b", "c");
  let v = sv3("!!hello", "!!append:x", "!!delete");
  let s = stack1("base", &k, &v);
  let m = layers_flatten(&s);
  var ok = flatmap_len(&m) == 3;
  if !map_is(&m, "a", "!hello", 0) { ok = false; }
  if !map_is(&m, "b", "!append:x", 0) { ok = false; }
  if !map_is(&m, "c", "!delete", 0) { ok = false; }
  let tb = layers_tombstones(&s);
  if tb.len() != 0 { ok = false; }
  if !layers_is_escaped("!!x") { ok = false; }
  if layers_is_escaped("!x") { ok = false; }
  if layers_is_delete("!!delete") { ok = false; }
  if layers_is_append("!!append:x") { ok = false; }
  return assert(ok, "escape: one '!' is stripped, the rest is stored literally");
}

fn t10() -> TestResult {
  let k = sv4("a", "b", "c", "d");
  let v = sv4("!delete ", "!append", "!APPEND:x", "!replace");
  let s = stack1("base", &k, &v);
  let m = layers_flatten(&s);
  var ok = flatmap_len(&m) == 4;
  if !map_is(&m, "a", "!delete ", 0) { ok = false; }
  if !map_is(&m, "b", "!append", 0) { ok = false; }
  if !map_is(&m, "c", "!APPEND:x", 0) { ok = false; }
  if !map_is(&m, "d", "!replace", 0) { ok = false; }
  if layers_is_delete("!delete ") { ok = false; }
  if layers_is_append("!append") { ok = false; }
  if layers_is_append("!APPEND:x") { ok = false; }
  if layers_is_replace("!replace") { ok = false; }
  return assert(ok, "sentinel matching is exact and case-sensitive; near misses stay literal");
}

fn t11() -> TestResult {
  let k0 = sv1("a");
  let v0 = sv1("x");
  let s0 = stack1("base", &k0, &v0);
  let k1 = sv2("a", "c");
  let v1 = sv2("!append:", "!append:");
  let s1 = add_ok(&s0, "top", &k1, &v1);
  let m = layers_flatten(&s1);
  var ok = map_is(&m, "a", "x,", 1);
  if !map_is(&m, "c", "", 1) { ok = false; }
  if !flatmap_has(&m, "c") { ok = false; }
  return assert(ok, "append with an empty payload: separator only, fresh empty value");
}

fn t12() -> TestResult {
  let k0 = sv1("a");
  let v0 = sv1("1");
  let s0 = stack1("l0", &k0, &v0);
  let k1 = sv1("a");
  let v1 = sv1("!append:2");
  let s1 = add_ok(&s0, "l1", &k1, &v1);
  let k2 = sv1("a");
  let v2 = sv1("!replace:3");
  let s2 = add_ok(&s1, "l2", &k2, &v2);
  let m = layers_flatten(&s2);
  var ok = map_is(&m, "a", "3", 2);
  let sv = layers_shadowed_values(&s2, "a");
  if sv.len() != 2 { ok = false; }
  if !str_vec_is(&sv, 0, "1") { ok = false; }
  if !str_vec_is(&sv, 1, "!append:2") { ok = false; }
  return assert(ok, "replace discards the accumulated append fold");
}

fn t13() -> TestResult {
  let k0 = sv3("a", "b", "c");
  let v0 = sv3("1", "2", "3");
  let s0 = stack1("base", &k0, &v0);
  let k1 = sv1("b");
  let v1 = sv1("!delete");
  let s1 = add_ok(&s0, "mid", &k1, &v1);
  let k2 = sv2("b", "d");
  let v2 = sv2("9", "4");
  let s2 = add_ok(&s1, "top", &k2, &v2);
  let m = layers_flatten(&s2);
  var ok = flatmap_len(&m) == 4;
  if !map_is(&m, "a", "1", 0) { ok = false; }
  if !map_is(&m, "b", "9", 2) { ok = false; }
  if !map_is(&m, "c", "3", 0) { ok = false; }
  if !map_is(&m, "d", "4", 2) { ok = false; }
  let mk = flatmap_keys(&m);
  if !str_vec_is(&mk, 0, "a") { ok = false; }
  if !str_vec_is(&mk, 1, "b") { ok = false; }
  if !str_vec_is(&mk, 2, "c") { ok = false; }
  if !str_vec_is(&mk, 3, "d") { ok = false; }
  return assert(ok, "order: a resurrected key keeps its first position, new keys append");
}

// --------------------------------------------------
//  t14-t17: build validation and layer diff
// --------------------------------------------------

fn t14() -> TestResult {
  let s0 = layers_new();
  let ka = sv2("a", "b");
  let va = sv1("1");
  var ok = add_err_is(&s0, "first", &ka, &va, "layers: keys and values are not aligned");
  let k1 = sv1("a");
  let v1 = sv1("1");
  let s1 = stack1("base", &k1, &v1);
  let k2 = sv1("x");
  let v2 = sv1("9");
  if !add_err_is(&s1, "base", &k2, &v2, "layers: duplicate layer name: base") { ok = false; }
  if !add_err_is(&s1, "", &k2, &v2, "layers: layer name must not be empty") { ok = false; }
  return assert(ok, "layers_add: rejects misaligned vectors, duplicate names, empty names");
}

fn t15() -> TestResult {
  let s0 = layers_new();
  var ok = true;
  let kb = sv2("a..b", "x");
  let vb = sv2("1", "2");
  if !add_err_is(&s0, "l", &kb, &vb, "layers: invalid key: a..b") { ok = false; }
  let kc = sv2("a b", "x");
  let vc = sv2("1", "2");
  if !add_err_is(&s0, "l", &kc, &vc, "layers: invalid key: a b") { ok = false; }
  let kd = sv2("a", "a");
  let vd = sv2("1", "2");
  if !add_err_is(&s0, "l", &kd, &vd, "layers: duplicate key in layer: a") { ok = false; }
  return assert(ok, "layers_add: validates dotted keys and per-layer key uniqueness");
}

fn t16() -> TestResult {
  let k0 = sv3("a", "b", "c");
  let v0 = sv3("1", "2", "3");
  let s0 = stack1("base", &k0, &v0);
  let k1 = sv3("a", "b", "d");
  let v1 = sv3("1", "9", "4");
  let s1 = add_ok(&s0, "other", &k1, &v1);
  let r = layers_diff(&s1, 0, 1);
  var ok = false;
  match r {
    Ok(d) => {
      ok = d.added.len() == 1;
      if d.removed.len() != 1 { ok = false; }
      if d.changed.len() != 1 { ok = false; }
      if !str_vec_is(&d.added, 0, "d") { ok = false; }
      if !str_vec_is(&d.removed, 0, "c") { ok = false; }
      if !str_vec_is(&d.changed, 0, "b") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "diff: added/removed/changed over raw layer entry text");
}

fn t17() -> TestResult {
  let k0 = sv1("a");
  let v0 = sv1("1");
  let s = stack1("base", &k0, &v0);
  var ok = diff_err_is(&s, 0, 5, "layers: no layer at index 5");
  if !diff_err_is(&s, -1, 0, "layers: no layer at index -1") { ok = false; }
  if !diff_err_is(&s, 0, -2, "layers: no layer at index -2") { ok = false; }
  return assert(ok, "diff: out-of-range indices are Err with the exact message");
}

// --------------------------------------------------
//  t18-t22: map queries, tombstones, purity, control bytes, predicates
// --------------------------------------------------

fn t18() -> TestResult {
  let k0 = sv2("a", "b");
  let v0 = sv2("1", "2");
  let s0 = stack1("base", &k0, &v0);
  let m = layers_flatten(&s0);
  var ok = flatmap_len(&m) == 2;
  if !opt_str_is(flatmap_get(&m, "a"), "1") { ok = false; }
  if !opt_int_is(flatmap_layer(&m, "a"), 0) { ok = false; }
  if flatmap_has(&m, "c") { ok = false; }
  let mv = flatmap_values(&m);
  if !str_vec_is(&mv, 0, "1") { ok = false; }
  if !str_vec_is(&mv, 1, "2") { ok = false; }
  let ents = flatmap_entries(&m);
  if !str_vec_is(&ents.0, 0, "a") { ok = false; }
  if !str_vec_is(&ents.1, 1, "2") { ok = false; }
  let r = flatmap_render(&m);
  if !streq(r, "a = 1\nb = 2") { ok = false; }
  let ek = Vec[Str].new();
  let ev = Vec[Str].new();
  let se = stack1("empty", &ek, &ev);
  let me = layers_flatten(&se);
  let empty = flatmap_render(&me);
  if !streq(empty, "") { ok = false; }
  return assert(ok, "map queries and canonical rendering (empty map renders as empty text)");
}

fn t19() -> TestResult {
  let k0 = sv3("a", "b", "c");
  let v0 = sv3("1", "2", "3");
  let s0 = stack1("base", &k0, &v0);
  let k1 = sv2("b", "c");
  let v1 = sv2("!delete", "!delete");
  let s1 = add_ok(&s0, "top", &k1, &v1);
  let tb = layers_tombstones(&s1);
  let m = layers_flatten(&s1);
  var ok = tb.len() == 2;
  if !str_vec_is(&tb, 0, "b") { ok = false; }
  if !str_vec_is(&tb, 1, "c") { ok = false; }
  if flatmap_len(&m) != 1 { ok = false; }
  if !flatmap_has(&m, "a") { ok = false; }
  return assert(ok, "tombstones: first-introduction order, deleted keys absent from the map");
}

fn t20() -> TestResult {
  let k0 = sv2("a", "b");
  let v0 = sv2("1", "2");
  let s = stack1("base", &k0, &v0);
  let m1 = layers_flatten(&s);
  let m2 = layers_flatten(&s);
  let k1 = flatmap_keys(&m1);
  let k2 = flatmap_keys(&m2);
  let v1 = flatmap_values(&m1);
  let v2 = flatmap_values(&m2);
  var ok = str_vec_eq(&k1, &k2);
  if !str_vec_eq(&v1, &v2) { ok = false; }
  if layers_count(&s) != 1 { ok = false; }
  if layers_layer_len(&s, 0) != 2 { ok = false; }
  if layers_layer_len(&s, 9) != 0 { ok = false; }
  if !opt_str_is(layers_name(&s, 0), "base") { ok = false; }
  if !opt_str_none(layers_name(&s, 5)) { ok = false; }
  return assert(ok, "flatten is pure and deterministic; the stack is not mutated");
}

fn t21() -> TestResult {
  let k0 = sv1("a");
  let v0 = sv1("l\u{0001}1");
  let s0 = stack1("base", &k0, &v0);
  let k1 = sv1("a");
  let v1 = sv1("!append:r\u{007F}2");
  let s1 = add_ok(&s0, "top", &k1, &v1);
  let m = layers_flatten(&s1);
  var ok = map_is(&m, "a", "l\u{0001}1,r\u{007F}2", 1);
  let r = flatmap_render(&m);
  if !streq(r, "a = l\u{0001}1,r\u{007F}2") { ok = false; }
  return assert(ok, "control bytes (\\u{0001}, \\u{007F}) pass through flatten and render");
}

fn t22() -> TestResult {
  var ok = layers_key_valid("a.b.c");
  if layers_key_valid("a..b") { ok = false; }
  if layers_key_valid("") { ok = false; }
  if layers_key_valid("a b") { ok = false; }
  if layers_key_valid("a=b") { ok = false; }
  if layers_key_valid("a#b") { ok = false; }
  if layers_key_valid("a.") { ok = false; }
  if layers_key_valid(".a") { ok = false; }
  let s0 = layers_new();
  let k = sv1("a");
  let v = sv1("1");
  let s1 = add_ok(&s0, "l", &k, &v);
  if layers_count(&s0) != 0 { ok = false; }
  if layers_count(&s1) != 1 { ok = false; }
  if layers_layer_len(&s1, 0) != 1 { ok = false; }
  return assert(ok, "key validity rule and stack introspection helpers");
}

// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.layers conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.layers: all tests passed");
  } else {
    io.println("xiom.layers: tests failed");
  }
  return failed;
}
