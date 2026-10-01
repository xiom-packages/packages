// XIOM -- xiom.svm conformance tests (23 checks)
// Port task: prove the pure-XIOM xiom.svm module against its documented
// fixed-point contract (scaled integers only, no floats, no FFI, no I/O in
// the library).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module svm_tests
use xiom.io; use xiom.test; use xiom.svm;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every dump and
// error-message check below is routed through streq instead of `==`.

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

fn v3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
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

// The separable two-dimensional fixture (scale 1e-4): three positive rows
// around (+1.5, +1.5) and three negative rows around (-1.5, -1.5).
fn separable_features() -> Vec[Int] {
  return v12(15000, 15000, 18000, 12000, 12000, 18000, -15000, -15000, -18000, -12000, -12000, -18000);
}

fn separable_labels() -> Vec[Int] {
  return v6(1, 1, 1, -1, -1, -1);
}

fn one_row() -> Vec[Int] {
  return v1(10000);
}

fn one_label() -> Vec[Int] {
  return v1(1);
}

// One row of the (6 x 2) separable fixture as its own 1 x 2 row vector.
fn one_row_of(features: &Vec[Int], r: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(features[r * 2]);
  v.push(features[r * 2 + 1]);
  return v;
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
    Err(_) => { return -2; },
  }
  return -2;
}

fn empty_model() -> SvmModel {
  return SvmModel{ n_features: 0; n_rows: 0; epochs: 0; learning_rate: 0; decay: 0; seed: 0; weights: empty_ints(); bias: 0; };
}

fn model_of(r: Result[SvmModel, Str]) -> SvmModel {
  match r {
    Ok(m) => { return m; },
    Err(_) => { return empty_model(); },
  }
  return empty_model();
}

fn dump_of(r: Result[SvmModel, Str]) -> Str {
  match r {
    Ok(m) => {
      let d = svm_dump(&m);
      return d;
    },
    Err(_) => { return ""; },
  }
  return "";
}

// ---------------------------------------------------------------------------
// Error-message predicates
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

fn model_err(r: Result[SvmModel, Str], want: Str) -> Bool {
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

fn is_permutation(v: &Vec[Int], n: Int) -> Bool {
  if v.len() != n {
    return false;
  }
  var seen = Vec[Int].new();
  var i = 0;
  while i < n {
    seen.push(0);
    i = i + 1;
  }
  i = 0;
  while i < n {
    let x: Int = v[i];
    if x < 0 || x >= n {
      return false;
    }
    let s: Int = seen[x];
    if s != 0 {
      return false;
    }
    seen[x] = 1;
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = svm_scale() == 10000;
  if svm_lcg_multiplier() != 48271 { ok = false; }
  if svm_lcg_modulus() != 2147483647 { ok = false; }
  if svm_max_feature() != 1000000000 { ok = false; }
  if svm_max_rows() != 1000000 { ok = false; }
  if svm_max_features() != 4096 { ok = false; }
  if svm_max_epochs() != 1000 { ok = false; }
  if svm_max_eta() != 1000000000 { ok = false; }
  if svm_max_decay() != 1000000000 { ok = false; }
  return assert(ok, "constant accessors report the documented envelope");
}

fn t2() -> TestResult {
  var ok = svm_lcg_step(0) == 48271;
  if svm_lcg_step(1) != 96542 { ok = false; }
  if svm_lcg_step(2) != 144813 { ok = false; }
  if svm_lcg_step(-1) != 96542 { ok = false; }
  if svm_lcg_step(2147483648) != svm_lcg_step(2) { ok = false; }
  return assert(ok, "LCG step matches the documented MINSTD recurrence");
}

fn t3() -> TestResult {
  let a = ints_of(svm_shuffle_indices(1, 8));
  let b = ints_of(svm_shuffle_indices(2, 8));
  let c = ints_of(svm_shuffle_indices(1, 4));
  let d = ints_of(svm_shuffle_indices(7, 4));
  var ok = ints_equal(&a, &v8(7, 3, 0, 2, 1, 4, 6, 5));
  if !ints_equal(&b, &v8(3, 5, 2, 0, 1, 7, 6, 4)) { ok = false; }
  if !ints_equal(&c, &v4(3, 0, 2, 1)) { ok = false; }
  if !ints_equal(&d, &v4(0, 1, 2, 3)) { ok = false; }
  return assert(ok, "shuffle matches pinned vectors across seeds");
}

fn t4() -> TestResult {
  let a = ints_of(svm_shuffle_indices(42, 16));
  let b = ints_of(svm_shuffle_indices(42, 16));
  var ok = is_permutation(&a, 16);
  if !ints_equal(&a, &b) { ok = false; }
  if a.len() == 16 && b.len() == 16 {
    let a0: Int = a[0];
    let b0: Int = b[0];
    if a0 != b0 { ok = false; }
  }
  return assert(ok, "shuffle is a reproducible permutation for one seed");
}

fn t5() -> TestResult {
  var ok = ints_err(svm_shuffle_indices(1, 0), "svm: shuffle size must be positive");
  if !ints_err(svm_shuffle_indices(1, -3), "svm: shuffle size must be positive") { ok = false; }
  if !ints_err(svm_shuffle_indices(1, 1000001), "svm: shuffle size exceeds the limit") { ok = false; }
  let one = ints_of(svm_shuffle_indices(1, 1));
  if one.len() != 1 { ok = false; }
  if one.len() == 1 {
    let x: Int = one[0];
    if x != 0 { ok = false; }
  }
  return assert(ok, "shuffle validates its size");
}

fn t6() -> TestResult {
  let one = svm_train(&one_row(), 1, 1, &one_label(), 1, 10000, 0, 1);
  let m = model_of(one);
  var ok = svm_n_features(&m) == 1;
  if svm_n_rows(&m) != 1 { ok = false; }
  if svm_epochs(&m) != 1 { ok = false; }
  if svm_initial_rate(&m) != 10000 { ok = false; }
  if svm_decay(&m) != 0 { ok = false; }
  if svm_seed(&m) != 1 { ok = false; }
  if svm_weight(&m, 0) != 10000 { ok = false; }
  if svm_bias(&m) != 10000 { ok = false; }
  if int_of(svm_score(&m, &one_row())) != 20000 { ok = false; }
  if int_of(svm_margin(&m, &one_row(), 1)) != 20000 { ok = false; }
  let pred = ints_of(svm_predict(&m, &one_row(), 1));
  if !ints_equal(&pred, &v1(1)) { ok = false; }
  if int_of(svm_accuracy(&m, &one_row(), 1, &one_label())) != 10000 { ok = false; }
  return assert(ok, "one-row training pins the exact update arithmetic");
}

fn t7() -> TestResult {
  var neg = Vec[Int].new();
  neg.push(-1);
  let one = svm_train(&one_row(), 1, 1, &neg, 1, 10000, 0, 1);
  let m = model_of(one);
  var ok = svm_weight(&m, 0) == 0 - 10000;
  if svm_bias(&m) != 0 - 10000 { ok = false; }
  if int_of(svm_score(&m, &one_row())) != 0 - 20000 { ok = false; }
  if int_of(svm_margin(&m, &one_row(), -1)) != 20000 { ok = false; }
  let pred = ints_of(svm_predict(&m, &one_row(), 1));
  if !ints_equal(&pred, &v1(-1)) { ok = false; }
  if int_of(svm_accuracy(&m, &one_row(), 1, &neg)) != 10000 { ok = false; }
  return assert(ok, "negative labels flip weight, bias and decision sign");
}

fn t8() -> TestResult {
  let one = svm_train(&one_row(), 1, 1, &one_label(), 1, 10000, 0, 1);
  let expected = "svm model: scale=10000 features=1 epochs=1 lr=10000 decay=0 seed=1 rows=1\nw0=10000\nbias=10000\n";
  var ok = streq(dump_of(one), expected);
  return assert(ok, "model dump text is pinned for the one-row model");
}

fn t9() -> TestResult {
  let sev = svm_train(&separable_features(), 6, 2, &separable_labels(), 5, 10000, 1, 7);
  let m = model_of(sev);
  var ok = svm_n_features(&m) == 2;
  if svm_weight(&m, 0) != 18000 { ok = false; }
  if svm_weight(&m, 1) != 12000 { ok = false; }
  if svm_bias(&m) != 0 - 10000 { ok = false; }
  let pred = ints_of(svm_predict(&m, &separable_features(), 6));
  if !ints_equal(&pred, &separable_labels()) { ok = false; }
  if int_of(svm_accuracy(&m, &separable_features(), 6, &separable_labels())) != 10000 { ok = false; }
  let margins = ints_of(svm_margins(&m, &separable_features(), 6, &separable_labels()));
  if !ints_equal(&margins, &v6(35000, 36800, 33200, 55000, 56800, 53200)) { ok = false; }
  return assert(ok, "separable data converges with the pinned model and margins");
}

fn t10() -> TestResult {
  let sev = svm_train(&separable_features(), 6, 2, &separable_labels(), 5, 10000, 1, 7);
  let m = model_of(sev);
  let margins = ints_of(svm_margins(&m, &separable_features(), 6, &separable_labels()));
  var ok = margins.len() == 6;
  var r = 0;
  while r < margins.len() {
    let mr: Int = margins[r];
    if mr <= 0 {
      ok = false;
    }
    let y: Int = separable_labels()[r];
    let direct = int_of(svm_margin(&m, &one_row_of(separable_features(), r), y));
    if direct != mr {
      ok = false;
    }
    r = r + 1;
  }
  let neg_margin = int_of(svm_margin(&m, &one_row(), -1));
  if neg_margin >= 0 {
    ok = false;
  }
  return assert(ok, "margin vector mirrors per-row signed margins");
}

fn t11() -> TestResult {
  let a = svm_train(&separable_features(), 6, 2, &separable_labels(), 5, 10000, 1, 7);
  let b = svm_train(&separable_features(), 6, 2, &separable_labels(), 5, 10000, 1, 7);
  let c = svm_train(&separable_features(), 6, 2, &separable_labels(), 5, 10000, 1, 9);
  let da = dump_of(a);
  let db = dump_of(b);
  let dc = dump_of(c);
  let ma = model_of(svm_train(&separable_features(), 6, 2, &separable_labels(), 5, 10000, 1, 7));
  var ok = streq(da, db);
  if streq(da, dc) { ok = false; }
  if int_of(svm_accuracy(&ma, &separable_features(), 6, &separable_labels())) != 10000 { ok = false; }
  let mc = model_of(c);
  if int_of(svm_accuracy(&mc, &separable_features(), 6, &separable_labels())) != 10000 { ok = false; }
  if svm_weight(&mc, 0) != 12000 { ok = false; }
  if svm_weight(&mc, 1) != 18000 { ok = false; }
  return assert(ok, "training is seed-reproducible and seed-dependent");
}

fn t12() -> TestResult {
  let one = svm_train(&one_row(), 1, 1, &one_label(), 1, 10000, 0, 1);
  let m = model_of(one);
  var ok = int_of(svm_support_vector_count(&m, &one_row(), 1, &one_label(), 10000)) == 1;
  if int_of(svm_support_vector_count(&m, &one_row(), 1, &one_label(), 9999)) != 0 { ok = false; }
  if int_of(svm_support_vector_count(&m, &one_row(), 1, &one_label(), 0)) != 0 { ok = false; }
  let sev = model_of(svm_train(&separable_features(), 6, 2, &separable_labels(), 5, 10000, 1, 7));
  let c0 = int_of(svm_support_vector_count(&sev, &separable_features(), 6, &separable_labels(), 0));
  let c1 = int_of(svm_support_vector_count(&sev, &separable_features(), 6, &separable_labels(), 5000));
  let c2 = int_of(svm_support_vector_count(&sev, &separable_features(), 6, &separable_labels(), 1000000000));
  if c0 != 0 { ok = false; }
  if c1 != 0 { ok = false; }
  if c2 != 6 { ok = false; }
  if !(c0 <= c1 && c1 <= c2) { ok = false; }
  return assert(ok, "support vectors are counted inside the margin band");
}

fn t13() -> TestResult {
  let m = model_of(svm_train(&one_row(), 1, 1, &one_label(), 1, 10000, 0, 1));
  let f3 = v3(10000, -10000, 20000);
  let l3 = v3(1, -1, 1);
  var ok = int_of(svm_accuracy(&m, &f3, 3, &l3)) == 6667;
  let pred = ints_of(svm_predict(&m, &f3, 3));
  if !ints_equal(&pred, &v3(1, 1, 1)) { ok = false; }
  let f2 = v2(10000, 0);
  let l2 = v2(1, -1);
  if int_of(svm_accuracy(&m, &f2, 2, &l2)) != 5000 { ok = false; }
  return assert(ok, "accuracy rounds half away from zero in basis points");
}

fn t14() -> TestResult {
  let m = model_of(svm_train(&one_row(), 1, 1, &one_label(), 1, 10000, 0, 1));
  let w = svm_weights(&m);
  var ok = w.len() == 1;
  if !ints_equal(&w, &v1(10000)) { ok = false; }
  if svm_weight(&m, 0) != 10000 { ok = false; }
  if svm_weight(&m, 1) != 0 { ok = false; }
  if svm_weight(&m, -1) != 0 { ok = false; }
  return assert(ok, "the weight vector is a range-safe copy");
}

fn t15() -> TestResult {
  var ok = int_of(svm_eta(10000, 0, 0)) == 10000;
  if int_of(svm_eta(10000, 0, 50)) != 10000 { ok = false; }
  if int_of(svm_eta(10000, 1, 0)) != 10000 { ok = false; }
  if int_of(svm_eta(10000, 1, 10000)) != 5000 { ok = false; }
  if int_of(svm_eta(10000, 1, 30000)) != 2500 { ok = false; }
  return assert(ok, "learning-rate schedule decays exactly as specified");
}

fn t16() -> TestResult {
  var ok = int_err(svm_eta(0, 0, 0), "svm: initial learning rate must be positive");
  if !int_err(svm_eta(1000000001, 0, 0), "svm: initial learning rate exceeds the limit") { ok = false; }
  if !int_err(svm_eta(10000, -1, 0), "svm: decay must not be negative") { ok = false; }
  if !int_err(svm_eta(10000, 1000000001, 0), "svm: decay exceeds the limit") { ok = false; }
  if !int_err(svm_eta(10000, 0, -1), "svm: step must not be negative") { ok = false; }
  if !int_err(svm_eta(10000, 0, 1000000001), "svm: step exceeds the limit") { ok = false; }
  return assert(ok, "eta validates its parameters");
}

fn t17() -> TestResult {
  let labels = v1(1);
  var ok = model_err(svm_train(&empty_ints(), 0, 2, &labels, 1, 100, 0, 1), "svm: row count must be positive");
  if !model_err(svm_train(&v2(1, 2), 1, 0, &labels, 1, 100, 0, 1), "svm: feature count must be positive") { ok = false; }
  if !model_err(svm_train(&empty_ints(), 1000001, 1, &labels, 1, 100, 0, 1), "svm: dataset too large") { ok = false; }
  if !model_err(svm_train(&empty_ints(), 1, 4097, &labels, 1, 100, 0, 1), "svm: feature count exceeds the limit") { ok = false; }
  if !model_err(svm_train(&v2(1, 2), 2, 2, &labels, 1, 100, 0, 1), "svm: features length does not match the shape") { ok = false; }
  let two_labels = v2(1, -1);
  if !model_err(svm_train(&v2(1, 2), 1, 2, &two_labels, 1, 100, 0, 1), "svm: label count does not match row count") { ok = false; }
  if !model_err(svm_train(&v1(1000000001), 1, 1, &labels, 1, 100, 0, 1), "svm: feature magnitude exceeds the limit") { ok = false; }
  return assert(ok, "train validates the matrix shape and magnitudes");
}

fn t18() -> TestResult {
  var zero = Vec[Int].new();
  zero.push(0);
  var two = Vec[Int].new();
  two.push(2);
  var minus_two = Vec[Int].new();
  minus_two.push(-2);
  var ok = model_err(svm_train(&one_row(), 1, 1, &zero, 1, 100, 0, 1), "svm: labels must be +1 or -1");
  if !model_err(svm_train(&one_row(), 1, 1, &two, 1, 100, 0, 1), "svm: labels must be +1 or -1") { ok = false; }
  if !model_err(svm_train(&one_row(), 1, 1, &minus_two, 1, 100, 0, 1), "svm: labels must be +1 or -1") { ok = false; }
  return assert(ok, "train accepts only the labels +1 and -1");
}

fn t19() -> TestResult {
  var ok = model_err(svm_train(&one_row(), 1, 1, &one_label(), 0, 100, 0, 1), "svm: epoch count must be positive");
  if !model_err(svm_train(&one_row(), 1, 1, &one_label(), 1001, 100, 0, 1), "svm: epoch count exceeds the limit") { ok = false; }
  if !model_err(svm_train(&one_row(), 1, 1, &one_label(), 1, 0, 0, 1), "svm: initial learning rate must be positive") { ok = false; }
  if !model_err(svm_train(&one_row(), 1, 1, &one_label(), 1, 1000000001, 0, 1), "svm: initial learning rate exceeds the limit") { ok = false; }
  if !model_err(svm_train(&one_row(), 1, 1, &one_label(), 1, 100, -1, 1), "svm: decay must not be negative") { ok = false; }
  if !model_err(svm_train(&one_row(), 1, 1, &one_label(), 1, 100, 1000000001, 1), "svm: decay exceeds the limit") { ok = false; }
  return assert(ok, "train validates epochs, rate and decay");
}

fn t20() -> TestResult {
  let m = model_of(svm_train(&one_row(), 1, 1, &one_label(), 1, 10000, 0, 1));
  var ok = int_err(svm_score(&m, &v2(1, 2)), "svm: feature count does not match the model");
  if !int_err(svm_margin(&m, &one_row(), 0), "svm: label must be +1 or -1") { ok = false; }
  if !int_err(svm_margin(&m, &one_row(), 2), "svm: label must be +1 or -1") { ok = false; }
  if !int_err(svm_score(&m, &v1(1000000001)), "svm: feature magnitude exceeds the limit") { ok = false; }
  return assert(ok, "score and margin validate row width, label and magnitude");
}

fn t21() -> TestResult {
  let m = model_of(svm_train(&one_row(), 1, 1, &one_label(), 1, 10000, 0, 1));
  var ok = int_err(svm_support_vector_count(&m, &one_row(), 1, &one_label(), -1), "svm: band must not be negative");
  if !int_err(svm_support_vector_count(&m, &one_row(), 1, &one_label(), 9223372036854775807), "svm: band exceeds the limit") { ok = false; }
  return assert(ok, "support-vector band is validated");
}

fn t22() -> TestResult {
  var big = Vec[Int].new();
  big.push(1000000000);
  var one = Vec[Int].new();
  one.push(1);
  let trained = svm_train(&big, 1, 1, &one, 1, 1000000000, 0, 1);
  let m = model_of(trained);
  var ok = svm_weight(&m, 0) == 100000000000000;
  if !int_err(svm_score(&m, &big), "svm: dot product overflows") { ok = false; }
  if !int_err(svm_accuracy(&m, &big, 1, &one), "svm: dot product overflows") { ok = false; }
  if !ints_err(svm_predict(&m, &big, 1), "svm: dot product overflows") { ok = false; }
  if !model_err(svm_train(&big, 1, 1, &one, 2, 1000000000, 0, 1), "svm: dot product overflows") { ok = false; }
  return assert(ok, "dot products fail closed when the accumulator overflows");
}

fn t23() -> TestResult {
  let sev = svm_train(&separable_features(), 6, 2, &separable_labels(), 5, 10000, 1, 7);
  let expected = "svm model: scale=10000 features=2 epochs=5 lr=10000 decay=1 seed=7 rows=6\nw0=18000\nw1=12000\nbias=-10000\n";
  var ok = streq(dump_of(sev), expected);
  return assert(ok, "model dump text is pinned for the separable fixture");
}

fn main() -> Int {
  io.println("=== xiom.svm conformance tests ===");
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
    io.println("xiom.svm: all tests passed");
  } else {
    io.println("xiom.svm: tests failed");
  }
  return failed;
}
