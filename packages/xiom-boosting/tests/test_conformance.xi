// XIOM -- xiom.boosting conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.boosting module against its documented
// fixed-point contract (no floats, no FFI, no I/O in the library).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare (BUG 17 lowers `==` on Str
// values read from Vec elements to a pointer comparison), and every
// Vec[Int] element read binds a typed local first. Test functions are
// called directly from main: indexed function-table dispatch is avoided.

module boosting_tests
use xiom.io; use xiom.test; use xiom.boosting;
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

// Perfectly separable 8x1 regression fixture: feature 0 splits at 3.
fn sep_features() -> Vec[Int] {
  return v8(0, 1, 2, 3, 4, 5, 6, 7);
}

fn sep_targets() -> Vec[Int] {
  return v8(0, 0, 0, 0, 10000, 10000, 10000, 10000);
}

// Alternating 8x1 fixture: every adjacent pair differs, so a depth-2 tree is
// needed to isolate the residual structure.
fn alt_features() -> Vec[Int] {
  return v8(0, 1, 2, 3, 4, 5, 6, 7);
}

fn alt_targets() -> Vec[Int] {
  return v8(0, 10000, 0, 10000, 0, 10000, 0, 10000);
}

// Separable 8x2 fixture: feature 0 determines the target, feature 1 mirrors
// it (redundant, equally good).
fn sep2_features() -> Vec[Int] {
  return v16(0, 7, 1, 6, 2, 5, 3, 4, 4, 3, 5, 2, 6, 1, 7, 0);
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

fn str_of(r: Result[Str, Str]) -> Str {
  match r {
    Ok(s) => { return s; },
    Err(_) => { return ""; },
  }
  return "";
}

fn model_of(r: Result[Model, Str]) -> Model {
  match r {
    Ok(m) => { return m; },
    Err(_) => {
      return Model{ n_features: 0; n_stages: 0; lr_bp: 1; base: 0; tree_root: Vec[Int].new(); nodes: Vec[Int].new(); };
    },
  }
  return Model{ n_features: 0; n_stages: 0; lr_bp: 1; base: 0; tree_root: Vec[Int].new(); nodes: Vec[Int].new(); };
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

fn str_err(r: Result[Str, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn model_err(r: Result[Model, Str], want: Str) -> Bool {
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

fn ints_non_increasing(v: &Vec[Int]) -> Bool {
  var i = 1;
  while i < v.len() {
    let a: Int = v[i - 1];
    let b: Int = v[i];
    if b > a {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Count nodes with a non-leaf split feature across every stage.
fn count_split_nodes(m: &Model) -> Int {
  let n_nodes = boosting_n_nodes(m);
  var total: Int = 0;
  var k = 0;
  while k < n_nodes {
    let f: Int = boosting_node_feature(m, k);
    if f >= 0 {
      total = total + 1;
    }
    k = k + 1;
  }
  return total;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = boosting_scale() == 10000;
  if boosting_bps() != 10000 { ok = false; }
  if boosting_lcg_multiplier() != 48271 { ok = false; }
  if boosting_lcg_modulus() != 2147483647 { ok = false; }
  if boosting_max_depth_limit() != 2 { ok = false; }
  if boosting_max_rows() != 4096 { ok = false; }
  if boosting_max_stages() != 64 { ok = false; }
  if boosting_lr_max() != 10000 { ok = false; }
  if boosting_value_max() != 100000 { ok = false; }
  if boosting_node_stride() != 8 { ok = false; }
  if boosting_lcg_step(0) != 48271 { ok = false; }
  if boosting_lcg_step(1) != 96542 { ok = false; }
  if boosting_lcg_step(-1) != 96542 { ok = false; }
  if boosting_lcg_step(2) != 144813 { ok = false; }
  return assert(ok, "constants and LCG step match the documented values");
}

fn t2() -> TestResult {
  let a = ints_of(boosting_subsample_indices(1, 1000, 16));
  let b = ints_of(boosting_subsample_indices(1, 1000, 16));
  var ok = a.len() == 16;
  if !ints_equal(&a, &b) { ok = false; }
  if !ints_in_range(&a, 0, 999) { ok = false; }
  return assert(ok, "subsample indices are deterministic and in range");
}

fn t3() -> TestResult {
  let k1 = ints_of(boosting_subsample_indices(1, 10, 2));
  var ok = k1.len() == 2;
  if k1.len() == 2 {
    let x: Int = k1[0];
    let y: Int = k1[1];
    if x != 1 { ok = false; }
    if y != 7 { ok = false; }
  }
  let k0 = ints_of(boosting_subsample_indices(0, 10, 1));
  if k0.len() != 1 { ok = false; }
  if k0.len() == 1 {
    let x0: Int = k0[0];
    if x0 != 0 { ok = false; }
  }
  let neg = ints_of(boosting_subsample_indices(-1, 10, 2));
  if !ints_equal(&neg, &k1) { ok = false; }
  return assert(ok, "subsample fixed vectors and seed normalization");
}

fn t4() -> TestResult {
  var ok = ints_err(boosting_subsample_indices(1, 0, 4), "boosting: dataset size must be positive");
  if !ints_err(boosting_subsample_indices(1, 10, -1), "boosting: sample count must not be negative") { ok = false; }
  let z = ints_of(boosting_subsample_indices(7, 10, 0));
  if z.len() != 0 { ok = false; }
  return assert(ok, "subsample indices validate their arguments");
}

fn t5() -> TestResult {
  let feats = sep_features();
  let targets = sep_targets();
  let m = model_of(boosting_train(&feats, 8, 1, &targets, 1, 1, 10000, 0, 0, 1));
  var ok = boosting_base(&m) == 5000;
  if boosting_n_stages(&m) != 1 { ok = false; }
  let pred = ints_of(boosting_predict(&m, &feats, 8));
  if !ints_equal(&pred, &targets) { ok = false; }
  let trace = ints_of(boosting_loss_trace(&m, &feats, 8, &targets));
  if trace.len() != 2 { ok = false; }
  if trace.len() == 2 {
    let l0: Int = trace[0];
    let l1: Int = trace[1];
    if l0 != 25000000 { ok = false; }
    if l1 != 0 { ok = false; }
  }
  return assert(ok, "full learning rate fits the separable fixture exactly");
}

fn t6() -> TestResult {
  let feats = sep_features();
  let targets = sep_targets();
  let m = model_of(boosting_train(&feats, 8, 1, &targets, 1, 1, 10000, 0, 0, 1));
  var ok = boosting_n_features(&m) == 1;
  if boosting_lr_bp(&m) != 10000 { ok = false; }
  if boosting_n_nodes(&m) != 3 { ok = false; }
  if boosting_tree_root(&m, 0) != 0 { ok = false; }
  if boosting_tree_n_nodes(&m, 0) != 3 { ok = false; }
  if boosting_tree_depth(&m, 0) != 1 { ok = false; }
  if boosting_is_leaf(&m, 0) { ok = false; }
  if !boosting_is_leaf(&m, 1) { ok = false; }
  if !boosting_is_leaf(&m, 2) { ok = false; }
  if boosting_node_feature(&m, 0) != 0 { ok = false; }
  if boosting_node_threshold(&m, 0) != 3 { ok = false; }
  if boosting_node_count(&m, 0) != 8 { ok = false; }
  if boosting_node_value(&m, 0) != 0 { ok = false; }
  if boosting_node_depth(&m, 0) != 0 { ok = false; }
  if boosting_node_left(&m, 0) != 1 { ok = false; }
  if boosting_node_right(&m, 0) != 2 { ok = false; }
  if boosting_node_value(&m, 1) != -5000 { ok = false; }
  if boosting_node_value(&m, 2) != 5000 { ok = false; }
  if boosting_node_count(&m, 1) != 4 { ok = false; }
  if boosting_node_count(&m, 2) != 4 { ok = false; }
  if boosting_node_depth(&m, 1) != 1 { ok = false; }
  let imp = boosting_feature_importance(&m);
  if imp.len() != 1 { ok = false; }
  if imp.len() == 1 {
    let i0: Int = imp[0];
    if i0 != 1 { ok = false; }
  }
  return assert(ok, "the stump splits feature 0 at 3 with pure children");
}

fn t7() -> TestResult {
  let feats = sep_features();
  let targets = sep_targets();
  let m = model_of(boosting_train(&feats, 8, 1, &targets, 1, 1, 10000, 0, 0, 1));
  let d = str_of(boosting_dump(&m));
  let want = "model: stages=1 features=1 lr_bp=10000 base=5000\ntree 0: nodes=3 depth=1\n[0] f0 <= 3 (n=8, value=0)\n  [1] leaf value=-5000 (n=4)\n  [2] leaf value=5000 (n=4)\n";
  return assert(streq(d, want), "dump matches the documented format");
}

fn t8() -> TestResult {
  let feats = sep_features();
  let targets = sep_targets();
  let half = model_of(boosting_train(&feats, 8, 1, &targets, 1, 1, 5000, 0, 0, 1));
  let full = model_of(boosting_train(&feats, 8, 1, &targets, 1, 1, 10000, 0, 0, 1));
  let ph = ints_of(boosting_predict(&half, &feats, 8));
  var ok = ph.len() == 8;
  if ph.len() == 8 {
    let p0: Int = ph[0];
    let p7: Int = ph[7];
    if p0 != 2500 { ok = false; }
    if p7 != 7500 { ok = false; }
  }
  let lh = ints_of(boosting_loss_trace(&half, &feats, 8, &targets));
  let lf = ints_of(boosting_loss_trace(&full, &feats, 8, &targets));
  if lh.len() != 2 { ok = false; }
  if lf.len() != 2 { ok = false; }
  if lh.len() == 2 {
    let a: Int = lh[1];
    if a != 6250000 { ok = false; }
    if a <= lf[1] { ok = false; }
  }
  return assert(ok, "a smaller learning rate shrinks the update and the loss gain");
}

fn t9() -> TestResult {
  let feats = sep_features();
  let targets = sep_targets();
  let m = model_of(boosting_train(&feats, 8, 1, &targets, 2, 1, 5000, 0, 0, 1));
  let trace = ints_of(boosting_loss_trace(&m, &feats, 8, &targets));
  var ok = boosting_n_stages(&m) == 2;
  if trace.len() != 3 { ok = false; }
  if !ints_non_increasing(&trace) { ok = false; }
  if trace.len() == 3 {
    let l0: Int = trace[0];
    let l1: Int = trace[1];
    let l2: Int = trace[2];
    if l0 != 25000000 { ok = false; }
    if l1 != 6250000 { ok = false; }
    if l2 != 1562500 { ok = false; }
    if l2 >= l1 { ok = false; }
    if l1 >= l0 { ok = false; }
  }
  return assert(ok, "staged loss decreases monotonically across two stages");
}

fn t10() -> TestResult {
  let feats = sep_features();
  let targets = sep_targets();
  let m = model_of(boosting_train(&feats, 8, 1, &targets, 2, 1, 10000, 0, 0, 1));
  let staged = ints_of(boosting_predict_staged(&m, &feats, 8, 2));
  let full = ints_of(boosting_predict(&m, &feats, 8));
  var ok = staged.len() == 16;
  if staged.len() == 16 {
    var r = 0;
    while r < 8 {
      let s: Int = staged[r];
      let f: Int = full[r];
      if s != f { ok = false; }
      r = r + 1;
    }
  }
  return assert(ok, "staged predictions end at the full prediction");
}

fn t11() -> TestResult {
  let feats = sep_features();
  let targets = sep_targets();
  let m = model_of(boosting_train(&feats, 8, 1, &targets, 1, 1, 10000, 0, 0, 1));
  var ok = ints_err(boosting_predict(&m, &feats, 0), "boosting: row count must be positive");
  let short = v4(0, 1, 2, 3);
  if !ints_err(boosting_predict(&m, &short, 8), "boosting: features length does not match the shape") { ok = false; }
  if !ints_err(boosting_predict_staged(&m, &feats, 8, 0), "boosting: stage count must be positive") { ok = false; }
  if !ints_err(boosting_predict_staged(&m, &feats, 8, 3), "boosting: stage count exceeds the model") { ok = false; }
  if !int_err(boosting_predict_row(&m, &short), "boosting: feature count does not match the model") { ok = false; }
  return assert(ok, "prediction APIs validate their shapes and stage bounds");
}

fn t12() -> TestResult {
  let feats = sep_features();
  let targets = sep_targets();
  var ok = model_err(boosting_train(&feats, 8, 1, &targets, 0, 1, 10000, 0, 0, 1), "boosting: stage count must be positive");
  if !model_err(boosting_train(&feats, 8, 1, &targets, 65, 1, 10000, 0, 0, 1), "boosting: stage count exceeds the limit") { ok = false; }
  if !model_err(boosting_train(&feats, 8, 1, &targets, 1, -1, 10000, 0, 0, 1), "boosting: max depth must not be negative") { ok = false; }
  if !model_err(boosting_train(&feats, 8, 1, &targets, 1, 3, 10000, 0, 0, 1), "boosting: max depth exceeds the limit") { ok = false; }
  if !model_err(boosting_train(&feats, 8, 1, &targets, 1, 1, 0, 0, 0, 1), "boosting: learning rate must be positive") { ok = false; }
  if !model_err(boosting_train(&feats, 8, 1, &targets, 1, 1, 10001, 0, 0, 1), "boosting: learning rate exceeds the limit") { ok = false; }
  return assert(ok, "train validates stages, depth and learning rate");
}

fn t13() -> TestResult {
  let feats = sep2_features();
  let targets = sep_targets();
  var ok = model_err(boosting_train(&feats, 8, 2, &targets, 1, 1, 10000, -1, 0, 1), "boosting: row subsample must not be negative");
  if !model_err(boosting_train(&feats, 8, 2, &targets, 1, 1, 10000, 9, 0, 1), "boosting: row subsample exceeds the row count") { ok = false; }
  if !model_err(boosting_train(&feats, 8, 2, &targets, 1, 1, 10000, 0, -1, 1), "boosting: feature subsample must not be negative") { ok = false; }
  if !model_err(boosting_train(&feats, 8, 2, &targets, 1, 1, 10000, 0, 3, 1), "boosting: feature subsample exceeds the feature count") { ok = false; }
  return assert(ok, "train validates the subsample counts");
}

fn t14() -> TestResult {
  let feats = sep_features();
  let targets = sep_targets();
  var ok = model_err(boosting_train(&feats, 0, 1, &targets, 1, 1, 10000, 0, 0, 1), "boosting: row count must be positive");
  if !model_err(boosting_train(&feats, 8, 0, &targets, 1, 1, 10000, 0, 0, 1), "boosting: feature count must be positive") { ok = false; }
  let shortf = v4(0, 1, 2, 3);
  if !model_err(boosting_train(&shortf, 8, 1, &targets, 1, 1, 10000, 0, 0, 1), "boosting: features length does not match the shape") { ok = false; }
  let shortt = v2(0, 0);
  if !model_err(boosting_train(&feats, 8, 1, &shortt, 1, 1, 10000, 0, 0, 1), "boosting: target count does not match row count") { ok = false; }
  let bigt = v8(0, 0, 0, 0, 0, 0, 0, 200000);
  if !model_err(boosting_train(&feats, 8, 1, &bigt, 1, 1, 10000, 0, 0, 1), "boosting: target out of range") { ok = false; }
  return assert(ok, "train validates the data shape and target range");
}

fn t15() -> TestResult {
  let feats = sep2_features();
  let targets = sep_targets();
  let a = model_of(boosting_train(&feats, 8, 2, &targets, 3, 1, 5000, 4, 0, 7));
  let b = model_of(boosting_train(&feats, 8, 2, &targets, 3, 1, 5000, 4, 0, 7));
  var ok = boosting_n_stages(&a) == 3;
  if boosting_n_nodes(&a) != boosting_n_nodes(&b) { ok = false; }
  let da = str_of(boosting_dump(&a));
  let db = str_of(boosting_dump(&b));
  if !streq(da, db) { ok = false; }
  let pa = ints_of(boosting_predict(&a, &feats, 8));
  let pb = ints_of(boosting_predict(&b, &feats, 8));
  if !ints_equal(&pa, &pb) { ok = false; }
  return assert(ok, "row subsampling is deterministic for one seed");
}

fn t16() -> TestResult {
  let feats = sep2_features();
  let targets = sep_targets();
  let a = model_of(boosting_train(&feats, 8, 2, &targets, 3, 1, 5000, 0, 0, 1));
  let b = model_of(boosting_train(&feats, 8, 2, &targets, 3, 1, 5000, 0, 0, 999));
  let da = str_of(boosting_dump(&a));
  let db = str_of(boosting_dump(&b));
  return assert(streq(da, db), "full-data training is independent of the seed");
}

fn t17() -> TestResult {
  let feats = sep_features();
  let targets = sep_targets();
  let f0 = model_of(boosting_train(&feats, 8, 1, &targets, 1, 0, 10000, 0, 0, 1));
  var ok = boosting_n_nodes(&f0) == 1;
  if !boosting_is_leaf(&f0, 0) { ok = false; }
  if boosting_tree_depth(&f0, 0) != 0 { ok = false; }
  let imp0 = boosting_feature_importance(&f0);
  if imp0.len() != 1 { ok = false; }
  if imp0.len() == 1 {
    let i0: Int = imp0[0];
    if i0 != 0 { ok = false; }
  }
  let af = alt_features();
  let at = alt_targets();
  let d2 = model_of(boosting_train(&af, 8, 1, &at, 1, 2, 10000, 0, 0, 1));
  if boosting_tree_depth(&d2, 0) != 2 { ok = false; }
  if boosting_n_nodes(&d2) < 5 { ok = false; }
  return assert(ok, "max_depth 0 yields one leaf and depth 2 recurses once");
}

fn t18() -> TestResult {
  let feats = sep_features();
  let targets = sep_targets();
  let m = model_of(boosting_train(&feats, 8, 1, &targets, 1, 1, 10000, 0, 0, 1));
  var ok = boosting_tree_root(&m, 9) == -1;
  if boosting_tree_root(&m, -1) != -1 { ok = false; }
  if boosting_tree_n_nodes(&m, 9) != 0 { ok = false; }
  if boosting_tree_depth(&m, 9) != -1 { ok = false; }
  if boosting_is_leaf(&m, 99) { ok = false; }
  if boosting_node_feature(&m, 99) != -2 { ok = false; }
  if boosting_node_feature(&m, -1) != -2 { ok = false; }
  if boosting_node_feature(&m, 1) != -1 { ok = false; }
  if boosting_node_threshold(&m, 99) != 0 { ok = false; }
  if boosting_node_left(&m, 99) != -1 { ok = false; }
  if boosting_node_right(&m, 99) != -1 { ok = false; }
  if boosting_node_value(&m, 99) != 0 { ok = false; }
  if boosting_node_count(&m, 99) != 0 { ok = false; }
  if boosting_node_depth(&m, 99) != -1 { ok = false; }
  return assert(ok, "accessors are range-safe");
}

fn t19() -> TestResult {
  let feats = sep2_features();
  let targets = sep_targets();
  let m = model_of(boosting_train(&feats, 8, 2, &targets, 2, 1, 10000, 0, 1, 3));
  let imp = boosting_feature_importance(&m);
  var ok = imp.len() == 2;
  let splits = count_split_nodes(&m);
  if splits < 1 { ok = false; }
  var sum: Int = 0;
  var i = 0;
  while i < imp.len() {
    let x: Int = imp[i];
    sum = sum + x;
    i = i + 1;
  }
  if sum != splits { ok = false; }
  return assert(ok, "feature importance counts exactly the split nodes");
}

fn t20() -> TestResult {
  let feats = sep_features();
  let targets = sep_targets();
  let m = model_of(boosting_train(&feats, 8, 1, &targets, 1, 1, 10000, 0, 0, 1));
  var ok = ints_err(boosting_loss_trace(&m, &feats, 0, &targets), "boosting: row count must be positive");
  let short = v4(0, 1, 2, 3);
  if !ints_err(boosting_loss_trace(&m, &short, 8, &targets), "boosting: features length does not match the shape") { ok = false; }
  let shortt = v2(0, 0);
  if !ints_err(boosting_loss_trace(&m, &feats, 8, &shortt), "boosting: target count does not match row count") { ok = false; }
  let pred = ints_of(boosting_predict(&m, &feats, 8));
  let row3 = v1(3);
  let row5 = v1(5);
  let one3 = int_of(boosting_predict_row(&m, &row3));
  let one5 = int_of(boosting_predict_row(&m, &row5));
  if pred.len() != 8 { ok = false; }
  if pred.len() == 8 {
    let p3: Int = pred[3];
    let p5: Int = pred[5];
    if one3 != p3 { ok = false; }
    if one5 != p5 { ok = false; }
  }
  if one3 != 0 { ok = false; }
  if one5 != 10000 { ok = false; }
  return assert(ok, "loss trace validates inputs and predict_row matches predict");
}

fn main() -> Int {
  io.println("=== xiom.boosting conformance tests ===");
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
    io.println("xiom.boosting: all tests passed");
  } else {
    io.println("xiom.boosting: tests failed");
  }
  return failed;
}
