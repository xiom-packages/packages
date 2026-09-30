// XIOM -- xiom.randomforest conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.randomforest module against its
// documented integer contract (no floats, no FFI, no I/O in the library).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare (BUG 17 lowers `==` on Str
// values read from Vec elements to a pointer comparison), and every
// Vec[Int] element read binds a typed local first. Test functions are
// called directly from main: indexed function-table dispatch is avoided.

module randomforest_tests
use xiom.io; use xiom.test; use xiom.randomforest;
use xiom.string; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

fn empty_ints() -> Vec[Int] {
  return Vec[Int].new();
}

fn v1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn v2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn v4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn v6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

fn v8(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  return v;
}

fn v12(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int, i: Int, j: Int, k: Int, l: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  v.push(i);
  v.push(j);
  v.push(k);
  v.push(l);
  return v;
}

fn v16(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int, i: Int, j: Int, k: Int, l: Int, m: Int, n: Int, o: Int, p: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  v.push(i);
  v.push(j);
  v.push(k);
  v.push(l);
  v.push(m);
  v.push(n);
  v.push(o);
  v.push(p);
  return v;
}

fn v24(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int, i: Int, j: Int, k: Int, l: Int, m: Int, n: Int, o: Int, p: Int, q: Int, r: Int, s: Int, t: Int, u: Int, w: Int, x: Int, y: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  v.push(i);
  v.push(j);
  v.push(k);
  v.push(l);
  v.push(m);
  v.push(n);
  v.push(o);
  v.push(p);
  v.push(q);
  v.push(r);
  v.push(s);
  v.push(t);
  v.push(u);
  v.push(w);
  v.push(x);
  v.push(y);
  return v;
}

// Perfectly separable 8x2 fixture: feature 0 determines the label, feature
// 1 is its reversed mirror (a redundant, equally good split).
fn sep_features() -> Vec[Int] {
  return v16(0, 7, 1, 6, 2, 5, 3, 4, 4, 3, 5, 2, 6, 1, 7, 0);
}

fn sep_labels() -> Vec[Int] {
  return v8(0, 0, 0, 0, 1, 1, 1, 1);
}

fn sep_idx() -> Vec[Int] {
  return v8(0, 1, 2, 3, 4, 5, 6, 7);
}

// Noisy 12x2 fixture: mixed labels so training depends on the bootstrap
// draw; feature 1 is a scrambled permutation.
fn noi_features() -> Vec[Int] {
  return v24(0, 5, 1, 2, 2, 8, 3, 1, 4, 9, 5, 3, 6, 7, 7, 0, 8, 6, 9, 4, 10, 10, 11, 3);
}

fn noi_labels() -> Vec[Int] {
  return v12(0, 1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 0);
}

// One row of a row-major feature matrix.
fn row_of(features: &Vec[Int], n_features: Int, r: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var j = 0;
  while j < n_features {
    let x: Int = features[r * n_features + j];
    out.push(x);
    j = j + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Result extractors with graceful fallbacks: a construction failure makes
// the value checks fail instead of aborting the whole suite.
// ---------------------------------------------------------------------------

fn ints_of(r: Result[Vec[Int], Str]) -> Vec[Int] {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_ints(); },
  }
  return empty_ints();
}

fn int_of(r: Result[Int, Str]) -> Int {
  match r {
    Ok(x) => { return x; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn forest_of(r: Result[Forest, Str]) -> Forest {
  match r {
    Ok(f) => { return f; },
    Err(_) => {
      return Forest{ n_features: 0; n_classes: 0; classes: empty_ints(); n_trees: 0; tree_root: Vec[Int].new(); nodes: Vec[Int].new(); };
    },
  }
  return Forest{ n_features: 0; n_classes: 0; classes: empty_ints(); n_trees: 0; tree_root: Vec[Int].new(); nodes: Vec[Int].new(); };
}

fn str_of(r: Result[Str, Str]) -> Str {
  match r {
    Ok(s) => { return s; },
    Err(_) => { return ""; },
  }
  return "";
}

// ---------------------------------------------------------------------------
// Error predicates
// ---------------------------------------------------------------------------

fn ints_err(r: Result[Vec[Int], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn int_err(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn forest_err(r: Result[Forest, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn str_err(r: Result[Str, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Vector predicates
// ---------------------------------------------------------------------------

fn ints_equal(a: &Vec[Int], b: &Vec[Int]) -> Bool {
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

fn ints_in_range(v: &Vec[Int], lo: Int, hi: Int) -> Bool {
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    if x < lo {
      return false;
    }
    if x > hi {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = randomforest_lcg_multiplier() == 48271;
  if randomforest_lcg_modulus() != 2147483647 { ok = false; }
  if randomforest_max_depth_limit() != 64 { ok = false; }
  if randomforest_max_rows() != 1000000 { ok = false; }
  if randomforest_max_trees() != 100000 { ok = false; }
  if randomforest_node_stride() != 8 { ok = false; }
  if randomforest_lcg_step(0) != 48271 { ok = false; }
  if randomforest_lcg_step(1) != 96542 { ok = false; }
  if randomforest_lcg_step(-1) != 96542 { ok = false; }
  if randomforest_lcg_step(2) != 144813 { ok = false; }
  return assert(ok, "constants and LCG step match the documented values");
}

fn t2() -> TestResult {
  let a = ints_of(randomforest_bootstrap_indices(1, 1000, 16));
  let b = ints_of(randomforest_bootstrap_indices(1, 1000, 16));
  var ok = a.len() == 16;
  if !ints_equal(&a, &b) { ok = false; }
  if !ints_in_range(&a, 0, 999) { ok = false; }
  return assert(ok, "bootstrap is deterministic and in range");
}

fn t3() -> TestResult {
  let k1 = ints_of(randomforest_bootstrap_indices(1, 10, 2));
  var ok = k1.len() == 2;
  if k1.len() == 2 {
    let x: Int = k1[0];
    let y: Int = k1[1];
    if x != 1 { ok = false; }
    if y != 7 { ok = false; }
  }
  let k0 = ints_of(randomforest_bootstrap_indices(0, 10, 1));
  if k0.len() != 1 { ok = false; }
  if k0.len() == 1 {
    let x0: Int = k0[0];
    if x0 != 0 { ok = false; }
  }
  let big1 = ints_of(randomforest_bootstrap_indices(1, 1000, 8));
  let big2 = ints_of(randomforest_bootstrap_indices(2, 1000, 8));
  if big1.len() != 8 { ok = false; }
  if big2.len() != 8 { ok = false; }
  if big1.len() == 8 && big2.len() == 8 {
    let f1: Int = big1[0];
    let f2: Int = big2[0];
    if f1 != 541 { ok = false; }
    if f2 != 812 { ok = false; }
  }
  let neg = ints_of(randomforest_bootstrap_indices(-1, 10, 2));
  if !ints_equal(&neg, &k1) { ok = false; }
  return assert(ok, "bootstrap fixed vectors and seed normalization");
}

fn t4() -> TestResult {
  var ok = ints_err(randomforest_bootstrap_indices(1, 0, 4), "randomforest: dataset size must be positive");
  if !ints_err(randomforest_bootstrap_indices(1, 10, -1), "randomforest: sample count must not be negative") { ok = false; }
  let z = ints_of(randomforest_bootstrap_indices(7, 10, 0));
  if z.len() != 0 { ok = false; }
  return assert(ok, "bootstrap validates its arguments");
}

fn t5() -> TestResult {
  let feats = sep_features();
  let labels = sep_labels();
  let idx = sep_idx();
  let fr = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 1, 1));
  var ok = randomforest_n_trees(&fr) == 1;
  if randomforest_n_features(&fr) != 2 { ok = false; }
  if randomforest_n_classes(&fr) != 2 { ok = false; }
  if randomforest_n_nodes(&fr) != 3 { ok = false; }
  if randomforest_tree_root(&fr, 0) != 0 { ok = false; }
  if randomforest_tree_n_nodes(&fr, 0) != 3 { ok = false; }
  if randomforest_tree_depth(&fr, 0) != 1 { ok = false; }
  if randomforest_node_feature(&fr, 0) != 0 { ok = false; }
  if randomforest_node_threshold(&fr, 0) != 3 { ok = false; }
  if randomforest_node_count(&fr, 0) != 8 { ok = false; }
  if randomforest_node_label(&fr, 0) != 0 { ok = false; }
  if randomforest_node_depth(&fr, 0) != 0 { ok = false; }
  if randomforest_node_left(&fr, 0) != 1 { ok = false; }
  if randomforest_node_right(&fr, 0) != 2 { ok = false; }
  if randomforest_is_leaf(&fr, 0) { ok = false; }
  if !randomforest_is_leaf(&fr, 1) { ok = false; }
  if !randomforest_is_leaf(&fr, 2) { ok = false; }
  if randomforest_node_label(&fr, 1) != 0 { ok = false; }
  if randomforest_node_label(&fr, 2) != 1 { ok = false; }
  if randomforest_node_count(&fr, 1) != 4 { ok = false; }
  if randomforest_node_count(&fr, 2) != 4 { ok = false; }
  if randomforest_node_depth(&fr, 1) != 1 { ok = false; }
  let c0: Int = randomforest_class(&fr, 0);
  let c1: Int = randomforest_class(&fr, 1);
  if c0 != 0 { ok = false; }
  if c1 != 1 { ok = false; }
  if randomforest_class_index(&fr, 1) != 1 { ok = false; }
  return assert(ok, "build_tree learns the separable split with pure children");
}

fn t6() -> TestResult {
  let feats = sep_features();
  let labels = sep_labels();
  let idx = sep_idx();
  let f0 = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 0, 1));
  var ok = randomforest_n_nodes(&f0) == 1;
  if !randomforest_is_leaf(&f0, 0) { ok = false; }
  if randomforest_node_label(&f0, 0) != 0 { ok = false; }
  if randomforest_node_count(&f0, 0) != 8 { ok = false; }
  if randomforest_tree_depth(&f0, 0) != 0 { ok = false; }
  let f5 = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 3, 5));
  if randomforest_n_nodes(&f5) != 1 { ok = false; }
  let f2 = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 2, 2));
  if randomforest_n_nodes(&f2) != 3 { ok = false; }
  if randomforest_node_threshold(&f2, 0) != 3 { ok = false; }
  return assert(ok, "max_depth and min_samples stop splitting");
}

fn t7() -> TestResult {
  let feats = v4(9, 9, 9, 9);
  let labels = v4(1, 0, 1, 0);
  let idx = v4(0, 1, 2, 3);
  let fr = forest_of(randomforest_build_tree(&feats, 4, 1, &labels, &idx, 3, 1));
  var ok = randomforest_n_nodes(&fr) == 1;
  if !randomforest_is_leaf(&fr, 0) { ok = false; }
  if randomforest_node_label(&fr, 0) != 1 { ok = false; }
  if randomforest_n_classes(&fr) != 2 { ok = false; }
  return assert(ok, "a constant feature cannot split and a tie picks the first class");
}

fn t8() -> TestResult {
  let feats = v6(0, 0, 1, 1, 2, 2);
  let labels = v6(0, 1, 0, 1, 0, 1);
  let idx = v6(0, 1, 2, 3, 4, 5);
  let fr = forest_of(randomforest_build_tree(&feats, 6, 1, &labels, &idx, 1, 1));
  var ok = randomforest_node_feature(&fr, 0) == 0;
  if randomforest_node_threshold(&fr, 0) != 0 { ok = false; }
  if randomforest_n_nodes(&fr) != 3 { ok = false; }
  return assert(ok, "split-score ties keep the lowest threshold");
}

fn t9() -> TestResult {
  let feats = v16(0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7);
  let labels = sep_labels();
  let idx = sep_idx();
  let fr = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 1, 1));
  var ok = randomforest_node_feature(&fr, 0) == 0;
  if randomforest_node_threshold(&fr, 0) != 3 { ok = false; }
  return assert(ok, "equally good features split on the lowest feature index");
}

fn t10() -> TestResult {
  let feats = v4(9, 9, 9, 9);
  let labels = v4(3, 1, 3, 0);
  let idx = v4(0, 1, 2, 3);
  let fr = forest_of(randomforest_build_tree(&feats, 4, 1, &labels, &idx, 2, 1));
  var ok = randomforest_n_classes(&fr) == 3;
  if randomforest_class(&fr, 0) != 3 { ok = false; }
  if randomforest_class(&fr, 1) != 1 { ok = false; }
  if randomforest_class(&fr, 2) != 0 { ok = false; }
  if randomforest_class_index(&fr, 1) != 1 { ok = false; }
  if randomforest_class_index(&fr, 9) != -1 { ok = false; }
  if randomforest_node_label(&fr, 0) != 3 { ok = false; }
  return assert(ok, "classes keep first-occurrence order and majority ties pick the first");
}

fn t11() -> TestResult {
  let feats = sep_features();
  let labels = sep_labels();
  let idx = sep_idx();
  let fr = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 2, 1));
  let pred = ints_of(randomforest_predict(&fr, &feats, 8));
  var ok = pred.len() == 8;
  if pred.len() == 8 {
    var i = 0;
    while i < 8 {
      let got: Int = pred[i];
      var want = 0;
      if i >= 4 { want = 1; }
      if got != want { ok = false; }
      i = i + 1;
    }
  }
  var r = 0;
  while r < 8 {
    let rowv = row_of(&feats, 2, r);
    let one = int_of(randomforest_predict_tree_row(&fr, 0, &rowv));
    let all: Int = pred[r];
    if one != all { ok = false; }
    r = r + 1;
  }
  return assert(ok, "predict classifies the separable fixture and matches the single tree");
}

fn t12() -> TestResult {
  let feats = sep_features();
  let labels = sep_labels();
  let idx = sep_idx();
  let fr = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 2, 1));
  var ok = ints_err(randomforest_predict(&fr, &feats, 0), "randomforest: row count must be positive");
  let short = v2(0, 7);
  if !ints_err(randomforest_predict(&fr, &short, 2), "randomforest: features length does not match the shape") { ok = false; }
  let rowv = v2(0, 7);
  if !int_err(randomforest_predict_tree_row(&fr, 1, &rowv), "randomforest: tree index out of range") { ok = false; }
  if !int_err(randomforest_predict_tree_row(&fr, -1, &rowv), "randomforest: tree index out of range") { ok = false; }
  let bad = v1(3);
  if !int_err(randomforest_predict_tree_row(&fr, 0, &bad), "randomforest: feature count does not match the forest") { ok = false; }
  return assert(ok, "predict validates shapes and indices");
}

fn t13() -> TestResult {
  let feats = sep_features();
  let labels = sep_labels();
  let idx = sep_idx();
  let fr = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 1, 1));
  var ok = randomforest_node_feature(&fr, 99) == -2;
  if randomforest_node_feature(&fr, -1) != -2 { ok = false; }
  if randomforest_node_feature(&fr, 1) != -1 { ok = false; }
  if randomforest_node_threshold(&fr, 99) != 0 { ok = false; }
  if randomforest_node_left(&fr, 99) != -1 { ok = false; }
  if randomforest_node_right(&fr, -1) != -1 { ok = false; }
  if randomforest_node_label(&fr, 99) != 0 { ok = false; }
  if randomforest_node_count(&fr, 99) != 0 { ok = false; }
  if randomforest_node_depth(&fr, 99) != -1 { ok = false; }
  if randomforest_is_leaf(&fr, 99) { ok = false; }
  if randomforest_tree_root(&fr, 9) != -1 { ok = false; }
  if randomforest_tree_n_nodes(&fr, 9) != 0 { ok = false; }
  if randomforest_tree_depth(&fr, 9) != -1 { ok = false; }
  if randomforest_class(&fr, 9) != 0 { ok = false; }
  return assert(ok, "accessors are range-safe");
}

fn t14() -> TestResult {
  let feats = sep_features();
  let labels = sep_labels();
  let idx = sep_idx();
  var ok = forest_err(randomforest_build_tree(&feats, 0, 2, &labels, &idx, 1, 1), "randomforest: row count must be positive");
  if !forest_err(randomforest_build_tree(&feats, 8, 0, &labels, &idx, 1, 1), "randomforest: feature count must be positive") { ok = false; }
  let bad_features = v1(1);
  if !forest_err(randomforest_build_tree(&bad_features, 8, 2, &labels, &idx, 1, 1), "randomforest: features length does not match the shape") { ok = false; }
  let bad_labels = v1(1);
  if !forest_err(randomforest_build_tree(&feats, 8, 2, &bad_labels, &idx, 1, 1), "randomforest: label count does not match row count") { ok = false; }
  let none = empty_ints();
  if !forest_err(randomforest_build_tree(&feats, 8, 2, &labels, &none, 1, 1), "randomforest: sample indices must not be empty") { ok = false; }
  let bad_idx = v2(0, 8);
  if !forest_err(randomforest_build_tree(&feats, 8, 2, &labels, &bad_idx, 1, 1), "randomforest: sample index out of range") { ok = false; }
  let neg_idx = v2(-1, 0);
  if !forest_err(randomforest_build_tree(&feats, 8, 2, &labels, &neg_idx, 1, 1), "randomforest: sample index out of range") { ok = false; }
  if !forest_err(randomforest_build_tree(&feats, 8, 2, &labels, &idx, -1, 1), "randomforest: max depth must not be negative") { ok = false; }
  if !forest_err(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 65, 1), "randomforest: max depth exceeds the limit") { ok = false; }
  if !forest_err(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 1, 0), "randomforest: min samples must be positive") { ok = false; }
  return assert(ok, "build_tree validates data, indices, depth and min-samples");
}

fn t15() -> TestResult {
  let feats = noi_features();
  let labels = noi_labels();
  let a = forest_of(randomforest_train(&feats, 12, 2, &labels, 3, 3, 1, 1));
  let b = forest_of(randomforest_train(&feats, 12, 2, &labels, 3, 3, 1, 1));
  var ok = randomforest_n_trees(&a) == 3;
  if randomforest_n_trees(&b) != 3 { ok = false; }
  if randomforest_n_nodes(&a) != randomforest_n_nodes(&b) { ok = false; }
  var t = 0;
  while t < 3 {
    let da = str_of(randomforest_dump_tree(&a, t));
    let db = str_of(randomforest_dump_tree(&b, t));
    if !streq(da, db) { ok = false; }
    t = t + 1;
  }
  var prev = -1;
  t = 0;
  var sum = 0;
  while t < 3 {
    let rt: Int = randomforest_tree_root(&a, t);
    if rt <= prev { ok = false; }
    prev = rt;
    let d: Int = randomforest_tree_depth(&a, t);
    if d < 0 { ok = false; }
    if d > 3 { ok = false; }
    sum = sum + randomforest_tree_n_nodes(&a, t);
    t = t + 1;
  }
  if sum != randomforest_n_nodes(&a) { ok = false; }
  let pa = ints_of(randomforest_predict(&a, &feats, 12));
  let pb = ints_of(randomforest_predict(&b, &feats, 12));
  if !ints_equal(&pa, &pb) { ok = false; }
  if pa.len() != 12 { ok = false; }
  if !ints_in_range(&pa, 0, 1) { ok = false; }
  return assert(ok, "train is deterministic and the forest structure is consistent");
}

fn t16() -> TestResult {
  // Two rows: seed 1 draws the bootstrap {1, 1} (a pure leaf), seed 2 draws
  // {0, 1} (a split), so the pinned seeds must produce different trees.
  let feats = v2(0, 5);
  let labels = v2(0, 1);
  let a = forest_of(randomforest_train(&feats, 2, 1, &labels, 1, 2, 1, 1));
  let c = forest_of(randomforest_train(&feats, 2, 1, &labels, 1, 2, 1, 2));
  var ok = randomforest_n_nodes(&a) == 1;
  if randomforest_n_nodes(&c) != 3 { ok = false; }
  let da = str_of(randomforest_dump_tree(&a, 0));
  let dc = str_of(randomforest_dump_tree(&c, 0));
  if streq(da, dc) { ok = false; }
  if randomforest_node_label(&a, 0) != 1 { ok = false; }
  if randomforest_node_threshold(&c, 0) != 0 { ok = false; }
  return assert(ok, "different seeds produce different forests");
}

fn t17() -> TestResult {
  let feats = sep_features();
  let labels = sep_labels();
  var ok = forest_err(randomforest_train(&feats, 8, 2, &labels, 0, 1, 1, 1), "randomforest: tree count must be positive");
  if !forest_err(randomforest_train(&feats, 8, 2, &labels, 100001, 1, 1, 1), "randomforest: tree count exceeds the limit") { ok = false; }
  if !forest_err(randomforest_train(&feats, 8, 2, &labels, 3, 65, 1, 1), "randomforest: max depth exceeds the limit") { ok = false; }
  if !forest_err(randomforest_train(&feats, 8, 2, &labels, 3, -1, 1, 1), "randomforest: max depth must not be negative") { ok = false; }
  if !forest_err(randomforest_train(&feats, 8, 2, &labels, 3, 1, 0, 1), "randomforest: min samples must be positive") { ok = false; }
  let short_labels = v2(0, 1);
  if !forest_err(randomforest_train(&feats, 8, 2, &short_labels, 3, 1, 1, 1), "randomforest: label count does not match row count") { ok = false; }
  return assert(ok, "train validates its configuration");
}

fn t18() -> TestResult {
  let feats = sep_features();
  let labels = sep_labels();
  let idx = sep_idx();
  let fr = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 1, 1));
  let imp = randomforest_feature_importance(&fr);
  let wimp = randomforest_feature_importance_weighted(&fr);
  var ok = imp.len() == 2;
  if wimp.len() != 2 { ok = false; }
  if imp.len() == 2 {
    let i0: Int = imp[0];
    let i1: Int = imp[1];
    if i0 != 1 { ok = false; }
    if i1 != 0 { ok = false; }
  }
  if wimp.len() == 2 {
    let w0: Int = wimp[0];
    let w1: Int = wimp[1];
    if w0 != 8 { ok = false; }
    if w1 != 0 { ok = false; }
  }
  // A constant noise feature is never used; the informative feature wins.
  let feats2 = v16(0, 5, 1, 5, 2, 5, 3, 5, 4, 5, 5, 5, 6, 5, 7, 5);
  let fr2 = forest_of(randomforest_train(&feats2, 8, 2, &labels, 4, 3, 1, 7));
  let imp2 = randomforest_feature_importance(&fr2);
  let wimp2 = randomforest_feature_importance_weighted(&fr2);
  if imp2.len() != 2 { ok = false; }
  if wimp2.len() != 2 { ok = false; }
  if imp2.len() == 2 {
    let a0: Int = imp2[0];
    let a1: Int = imp2[1];
    if a1 != 0 { ok = false; }
    if a0 < 1 { ok = false; }
    if wimp2.len() == 2 {
      let b0: Int = wimp2[0];
      let b1: Int = wimp2[1];
      if b1 != 0 { ok = false; }
      if b0 < a0 { ok = false; }
    }
  }
  return assert(ok, "feature importance counts and ranks the useful feature");
}

fn t19() -> TestResult {
  let feats = sep_features();
  let labels = sep_labels();
  let idx = sep_idx();
  let fr = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 1, 1));
  let d = str_of(randomforest_dump_tree(&fr, 0));
  let want = "tree 0: nodes=3 depth=1\n[0] f0 <= 3 (n=8, label=0)\n  [1] leaf label=0 (n=4)\n  [2] leaf label=1 (n=4)\n";
  var ok = streq(d, want);
  let f0 = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &idx, 0, 1));
  let d0 = str_of(randomforest_dump_tree(&f0, 0));
  let want0 = "tree 0: nodes=1 depth=0\n[0] leaf label=0 (n=8)\n";
  if !streq(d0, want0) { ok = false; }
  if !str_err(randomforest_dump_tree(&fr, 3), "randomforest: tree index out of range") { ok = false; }
  if !str_err(randomforest_dump_tree(&fr, -1), "randomforest: tree index out of range") { ok = false; }
  return assert(ok, "dump matches the documented format and rejects bad tree indices");
}

fn t20() -> TestResult {
  // Two conflicting leaf trees: the vote ties 1-1, so the lowest class
  // index (class 0) wins.
  let nodes01 = v16(-1, 0, -1, -1, 1, 4, 1, 0, -1, 0, -1, -1, 0, 4, 1, 0);
  var roots01 = Vec[Int].new();
  roots01.push(0);
  roots01.push(1);
  var classes01 = Vec[Int].new();
  classes01.push(0);
  classes01.push(1);
  let fr01 = Forest{ n_features: 1; n_classes: 2; classes: classes01; n_trees: 2; tree_root: roots01; nodes: nodes01; };
  let rowv = v1(0);
  var ok = int_of(randomforest_predict_tree_row(&fr01, 0, &rowv)) == 1;
  if int_of(randomforest_predict_tree_row(&fr01, 1, &rowv)) != 0 { ok = false; }
  let pred01 = ints_of(randomforest_predict(&fr01, &rowv, 1));
  if pred01.len() != 1 { ok = false; }
  if pred01.len() == 1 {
    let p0: Int = pred01[0];
    if p0 != 0 { ok = false; }
  }
  // Classes in a different order: the tie goes to class 5, not class 7.
  let nodes57 = v16(-1, 0, -1, -1, 7, 4, 1, 0, -1, 0, -1, -1, 5, 4, 1, 0);
  var roots57 = Vec[Int].new();
  roots57.push(0);
  roots57.push(1);
  var classes57 = Vec[Int].new();
  classes57.push(5);
  classes57.push(7);
  let fr57 = Forest{ n_features: 1; n_classes: 2; classes: classes57; n_trees: 2; tree_root: roots57; nodes: nodes57; };
  let pred57 = ints_of(randomforest_predict(&fr57, &rowv, 1));
  if pred57.len() != 1 { ok = false; }
  if pred57.len() == 1 {
    let p1: Int = pred57[0];
    if p1 != 5 { ok = false; }
  }
  // Three trees: a real majority (7, 7, 5) beats the tie rule.
  let nodes3 = v24(-1, 0, -1, -1, 7, 4, 1, 0, -1, 0, -1, -1, 7, 4, 1, 0, -1, 0, -1, -1, 5, 4, 1, 0);
  var roots3 = Vec[Int].new();
  roots3.push(0);
  roots3.push(1);
  roots3.push(2);
  var classes3 = Vec[Int].new();
  classes3.push(5);
  classes3.push(7);
  let fr3 = Forest{ n_features: 1; n_classes: 2; classes: classes3; n_trees: 3; tree_root: roots3; nodes: nodes3; };
  let pred3 = ints_of(randomforest_predict(&fr3, &rowv, 1));
  if pred3.len() != 1 { ok = false; }
  if pred3.len() == 1 {
    let p2: Int = pred3[0];
    if p2 != 7 { ok = false; }
  }
  return assert(ok, "forest voting breaks ties by the lowest class index");
}

fn t21() -> TestResult {
  let feats = noi_features();
  let labels = noi_labels();
  let fr = forest_of(randomforest_train(&feats, 12, 2, &labels, 4, 3, 1, 5));
  let pred = ints_of(randomforest_predict(&fr, &feats, 12));
  var ok = pred.len() == 12;
  if randomforest_n_trees(&fr) != 4 { ok = false; }
  var r = 0;
  while r < 12 {
    let rowv = row_of(&feats, 2, r);
    var votes = Vec[Int].new();
    var c = 0;
    while c < randomforest_n_classes(&fr) {
      votes.push(0);
      c = c + 1;
    }
    var t = 0;
    while t < 4 {
      let lbl = int_of(randomforest_predict_tree_row(&fr, t, &rowv));
      let ci: Int = randomforest_class_index(&fr, lbl);
      if ci < 0 { ok = false; }
      if ci >= 0 {
        let h: Int = votes[ci];
        votes[ci] = h + 1;
      }
      t = t + 1;
    }
    var best = 0;
    var best_count: Int = votes[0];
    var c2 = 1;
    while c2 < votes.len() {
      let h2: Int = votes[c2];
      if h2 > best_count {
        best_count = h2;
        best = c2;
      }
      c2 = c2 + 1;
    }
    let expected: Int = randomforest_class(&fr, best);
    let got: Int = pred[r];
    if expected != got { ok = false; }
    r = r + 1;
  }
  return assert(ok, "forest predictions are the majority of the per-tree votes");
}

fn t22() -> TestResult {
  let feats = sep_features();
  let labels = sep_labels();
  let sub0 = v2(0, 1);
  let fr0 = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &sub0, 2, 1));
  var ok = randomforest_n_nodes(&fr0) == 1;
  if randomforest_node_label(&fr0, 0) != 0 { ok = false; }
  if randomforest_node_count(&fr0, 0) != 2 { ok = false; }
  let sub1 = v2(0, 7);
  let fr1 = forest_of(randomforest_build_tree(&feats, 8, 2, &labels, &sub1, 2, 1));
  if randomforest_n_nodes(&fr1) != 3 { ok = false; }
  if randomforest_node_count(&fr1, 0) != 2 { ok = false; }
  if randomforest_node_feature(&fr1, 0) != 0 { ok = false; }
  if randomforest_node_threshold(&fr1, 0) != 0 { ok = false; }
  return assert(ok, "build_tree trains on exactly the supplied row indices");
}

fn t23() -> TestResult {
  let feats = noi_features();
  let labels = noi_labels();
  let fr_train = forest_of(randomforest_train(&feats, 12, 2, &labels, 1, 3, 1, 1));
  let idx = ints_of(randomforest_bootstrap_indices(1, 12, 12));
  let fr_direct = forest_of(randomforest_build_tree(&feats, 12, 2, &labels, &idx, 3, 1));
  var ok = idx.len() == 12;
  if randomforest_n_nodes(&fr_train) != randomforest_n_nodes(&fr_direct) { ok = false; }
  let d1 = str_of(randomforest_dump_tree(&fr_train, 0));
  let d2 = str_of(randomforest_dump_tree(&fr_direct, 0));
  if !streq(d1, d2) { ok = false; }
  return assert(ok, "train with one tree equals build_tree on its bootstrap indices");
}

fn t24() -> TestResult {
  let feats = noi_features();
  let labels = noi_labels();
  let fr = forest_of(randomforest_train(&feats, 12, 2, &labels, 5, 3, 2, 9));
  var ok = randomforest_n_trees(&fr) == 5;
  if randomforest_n_nodes(&fr) < 5 { ok = false; }
  if randomforest_n_classes(&fr) != 2 { ok = false; }
  let n_nodes: Int = randomforest_n_nodes(&fr);
  var t = 0;
  while t < 5 {
    let d: Int = randomforest_tree_depth(&fr, t);
    if d < 0 { ok = false; }
    if d > 3 { ok = false; }
    let count: Int = randomforest_tree_n_nodes(&fr, t);
    if count < 1 { ok = false; }
    let root: Int = randomforest_tree_root(&fr, t);
    if root < 0 { ok = false; }
    if root >= n_nodes { ok = false; }
    var k = root;
    let end: Int = root + count;
    while k < end {
      let lab: Int = randomforest_node_label(&fr, k);
      let ci: Int = randomforest_class_index(&fr, lab);
      if ci < 0 { ok = false; }
      if !randomforest_is_leaf(&fr, k) {
        let f: Int = randomforest_node_feature(&fr, k);
        if f < 0 { ok = false; }
        if f >= 2 { ok = false; }
      }
      k = k + 1;
    }
    t = t + 1;
  }
  return assert(ok, "every tree obeys the depth bound and carries valid labels");
}

fn main() -> Int {
  io.println("=== xiom.randomforest conformance tests ===");
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
    io.println("xiom.randomforest: all tests passed");
  } else {
    io.println("xiom.randomforest: tests failed");
  }
  return failed;
}
