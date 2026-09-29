// XIOM -- xiom.ensemble conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.ensemble module against its documented
// fixed-point contract (scaled integers only, no floats, no FFI, no I/O in
// the library).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module ensemble_tests
use xiom.io; use xiom.test; use xiom.ensemble;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every label and
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

fn v9(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int, i: Int) -> Vec[Int] {
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

fn empty_strs() -> Vec[Str] {
  return Vec[Str].new();
}

fn s1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn s2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn s3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn s4(a: Str, b: Str, c: Str, d: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn s5(a: Str, b: Str, c: Str, d: Str, e: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
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
    Err(_) => { return -1; },
  }
  return -1;
}

fn vote_of(r: Result[VoteResult, Str]) -> VoteResult {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return VoteResult{ winner: ""; winner_count: 0; classes: empty_strs(); counts: empty_ints(); n_models: 0; n_classes: 0; }; },
  }
  return VoteResult{ winner: ""; winner_count: 0; classes: empty_strs(); counts: empty_ints(); n_models: 0; n_classes: 0; };
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

fn vote_err(r: Result[VoteResult, Str], want: Str) -> Bool {
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
  var ok = ensemble_bps() == 10000;
  if ensemble_lcg_multiplier() != 48271 { ok = false; }
  if ensemble_lcg_modulus() != 2147483647 { ok = false; }
  return assert(ok, "constant accessors report 10000 / 48271 / 2147483647");
}

fn t2() -> TestResult {
  let labels = s3("a", "a", "b");
  let res = vote_of(ensemble_hard_vote(&labels));
  let winner: Str = ensemble_vote_winner(&res);
  var ok = ensemble_vote_n_models(&res) == 3;
  if !streq(winner, "a") { ok = false; }
  if ensemble_vote_winner_count(&res) != 2 { ok = false; }
  if ensemble_vote_n_classes(&res) != 2 { ok = false; }
  let c0: Str = ensemble_vote_class(&res, 0);
  let c1: Str = ensemble_vote_class(&res, 1);
  if !streq(c0, "a") { ok = false; }
  if !streq(c1, "b") { ok = false; }
  if ensemble_vote_count(&res, 0) != 2 { ok = false; }
  if ensemble_vote_count(&res, 1) != 1 { ok = false; }
  return assert(ok, "hard vote tallies the majority with first-occurrence classes");
}

fn t3() -> TestResult {
  let tie = s2("a", "b");
  let r1 = vote_of(ensemble_hard_vote(&tie));
  let w1: Str = ensemble_vote_winner(&r1);
  var ok = streq(w1, "a");
  let tie2 = s2("b", "a");
  let r2 = vote_of(ensemble_hard_vote(&tie2));
  let w2: Str = ensemble_vote_winner(&r2);
  if !streq(w2, "b") { ok = false; }
  let tie3 = s4("b", "b", "a", "a");
  let r3 = vote_of(ensemble_hard_vote(&tie3));
  let w3: Str = ensemble_vote_winner(&r3);
  if !streq(w3, "b") { ok = false; }
  if ensemble_vote_winner_count(&r3) != 2 { ok = false; }
  let tie4 = s5("x", "y", "x", "y", "z");
  let r4 = vote_of(ensemble_hard_vote(&tie4));
  let w4: Str = ensemble_vote_winner(&r4);
  if !streq(w4, "x") { ok = false; }
  if ensemble_vote_n_classes(&r4) != 3 { ok = false; }
  return assert(ok, "hard vote ties go to the lowest first-occurrence index");
}

fn t4() -> TestResult {
  let empty = empty_strs();
  var ok = vote_err(ensemble_hard_vote(&empty), "ensemble: labels must not be empty");
  let one = s1("only");
  let res = vote_of(ensemble_hard_vote(&one));
  let w: Str = ensemble_vote_winner(&res);
  if !streq(w, "only") { ok = false; }
  if ensemble_vote_winner_count(&res) != 1 { ok = false; }
  if ensemble_vote_n_classes(&res) != 1 { ok = false; }
  return assert(ok, "hard vote rejects empty input and accepts a single ballot");
}

fn t5() -> TestResult {
  let labels = s3("c", "a", "c");
  let res = vote_of(ensemble_hard_vote(&labels));
  var ok = ensemble_vote_class_index(&res, "c") == 0;
  if ensemble_vote_class_index(&res, "a") != 1 { ok = false; }
  if ensemble_vote_class_index(&res, "zz") != -1 { ok = false; }
  let out_class: Str = ensemble_vote_class(&res, 5);
  if !streq(out_class, "") { ok = false; }
  let neg_class: Str = ensemble_vote_class(&res, -1);
  if !streq(neg_class, "") { ok = false; }
  if ensemble_vote_count(&res, 5) != 0 { ok = false; }
  if ensemble_vote_count(&res, -2) != 0 { ok = false; }
  return assert(ok, "vote accessors are range-safe and index labels by str_compare");
}

fn t6() -> TestResult {
  let probs = v6(1000, 2000, 7000, 3000, 2000, 5000);
  let out = ints_of(ensemble_soft_vote(&probs, 2, 3));
  var ok = out.len() == 3;
  if out.len() == 3 {
    let a: Int = out[0];
    let b: Int = out[1];
    let c: Int = out[2];
    if a != 2000 { ok = false; }
    if b != 2000 { ok = false; }
    if c != 6000 { ok = false; }
  }
  return assert(ok, "soft vote averages per-class probabilities");
}

fn t7() -> TestResult {
  let probs = v4(1, 1, 0, 2);
  let out = ints_of(ensemble_soft_vote(&probs, 2, 2));
  var ok = out.len() == 2;
  if out.len() == 2 {
    let a: Int = out[0];
    let b: Int = out[1];
    if a != 1 { ok = false; }
    if b != 2 { ok = false; }
  }
  return assert(ok, "soft vote rounds halves away from zero");
}

fn t8() -> TestResult {
  let probs = v4(1000, 2000, 3000, 4000);
  var ok = ints_err(ensemble_soft_vote(&probs, 0, 2), "ensemble: model count must be positive");
  if !ints_err(ensemble_soft_vote(&probs, 2, 0), "ensemble: class count must be positive") { ok = false; }
  let short = v2(1, 2);
  if !ints_err(ensemble_soft_vote(&short, 2, 2), "ensemble: probability length does not match the shape") { ok = false; }
  let neg = v4(1, -1, 0, 0);
  if !ints_err(ensemble_soft_vote(&neg, 2, 2), "ensemble: probabilities must not be negative") { ok = false; }
  return assert(ok, "soft vote validates shape and probabilities");
}

fn t9() -> TestResult {
  let probs = v4(100, 0, 0, 200);
  let weights = v2(1, 3);
  let out = ints_of(ensemble_soft_vote_weighted(&probs, &weights, 2, 2));
  var ok = out.len() == 2;
  if out.len() == 2 {
    let a: Int = out[0];
    let b: Int = out[1];
    if a != 25 { ok = false; }
    if b != 150 { ok = false; }
  }
  return assert(ok, "weighted soft vote divides by the weight sum");
}

fn t10() -> TestResult {
  let probs = v4(1, 0, 0, 0);
  let weights = v2(1, 1);
  let out = ints_of(ensemble_soft_vote_weighted(&probs, &weights, 2, 2));
  var ok = out.len() == 2;
  if out.len() == 2 {
    let a: Int = out[0];
    let b: Int = out[1];
    if a != 1 { ok = false; }
    if b != 0 { ok = false; }
  }
  let probs2 = v4(1, 0, 99, 99);
  let weights2 = v2(1, 0);
  let out2 = ints_of(ensemble_soft_vote_weighted(&probs2, &weights2, 2, 2));
  if out2.len() != 2 { ok = false; }
  if out2.len() == 2 {
    let a2: Int = out2[0];
    let b2: Int = out2[1];
    if a2 != 1 { ok = false; }
    if b2 != 0 { ok = false; }
  }
  return assert(ok, "weighted soft vote rounds halves away and honors zero weights");
}

fn t11() -> TestResult {
  let probs = v4(1, 2, 3, 4);
  let wrong = v1(1);
  var ok = ints_err(ensemble_soft_vote_weighted(&probs, &wrong, 2, 2), "ensemble: weight count does not match model count");
  let neg_w = v2(1, -1);
  if !ints_err(ensemble_soft_vote_weighted(&probs, &neg_w, 2, 2), "ensemble: weights must not be negative") { ok = false; }
  let zero_w = v2(0, 0);
  if !ints_err(ensemble_soft_vote_weighted(&probs, &zero_w, 2, 2), "ensemble: weight sum must be positive") { ok = false; }
  let neg_p = v4(1, -1, 0, 0);
  let ok_w = v2(1, 1);
  if !ints_err(ensemble_soft_vote_weighted(&neg_p, &ok_w, 2, 2), "ensemble: probabilities must not be negative") { ok = false; }
  return assert(ok, "weighted soft vote validates weights and probabilities");
}

fn t12() -> TestResult {
  var ok = ensemble_lcg_step(0) == 48271;
  if ensemble_lcg_step(1) != 96542 { ok = false; }
  if ensemble_lcg_step(-1) != 96542 { ok = false; }
  if ensemble_lcg_step(2) != 144813 { ok = false; }
  if ensemble_lcg_step(2147483648) != ensemble_lcg_step(2) { ok = false; }
  return assert(ok, "LCG step matches the documented MINSTD recurrence");
}

fn t13() -> TestResult {
  let a = ints_of(ensemble_bootstrap_indices(1, 1000, 16));
  let b = ints_of(ensemble_bootstrap_indices(1, 1000, 16));
  var ok = a.len() == 16;
  if !ints_equal(&a, &b) { ok = false; }
  if !ints_in_range(&a, 0, 999) { ok = false; }
  return assert(ok, "bootstrap is deterministic and in range for one seed");
}

fn t14() -> TestResult {
  let a = ints_of(ensemble_bootstrap_indices(1, 1000, 8));
  let b = ints_of(ensemble_bootstrap_indices(2, 1000, 8));
  var ok = a.len() == 8;
  if b.len() != 8 { ok = false; }
  if ints_equal(&a, &b) { ok = false; }
  if a.len() == 8 && b.len() == 8 {
    let a0: Int = a[0];
    let b0: Int = b[0];
    if a0 != 541 { ok = false; }
    if b0 != 812 { ok = false; }
  }
  let kat = ints_of(ensemble_bootstrap_indices(1, 10, 2));
  if kat.len() != 2 { ok = false; }
  if kat.len() == 2 {
    let k0: Int = kat[0];
    let k1: Int = kat[1];
    if k0 != 1 { ok = false; }
    if k1 != 7 { ok = false; }
  }
  let zero = ints_of(ensemble_bootstrap_indices(0, 10, 1));
  if zero.len() != 1 { ok = false; }
  if zero.len() == 1 {
    let z0: Int = zero[0];
    if z0 != 0 { ok = false; }
  }
  return assert(ok, "bootstrap differs across seeds and matches fixed vectors");
}

fn t15() -> TestResult {
  var ok = ints_err(ensemble_bootstrap_indices(1, 0, 4), "ensemble: dataset size must be positive");
  if !ints_err(ensemble_bootstrap_indices(1, 10, -1), "ensemble: sample count must not be negative") { ok = false; }
  let zero_len = ints_of(ensemble_bootstrap_indices(7, 10, 0));
  if zero_len.len() != 0 { ok = false; }
  return assert(ok, "bootstrap validates size and count");
}

fn t16() -> TestResult {
  let vectors = v9(1, 2, 3, 4, 5, 6, 7, 8, 9);
  let out = ints_of(ensemble_bagging_combine(&vectors, 3, 3));
  var ok = out.len() == 3;
  if out.len() == 3 {
    let a: Int = out[0];
    let b: Int = out[1];
    let c: Int = out[2];
    if a != 4 { ok = false; }
    if b != 5 { ok = false; }
    if c != 6 { ok = false; }
  }
  let pair = v4(1, 0, 0, 0);
  let out2 = ints_of(ensemble_bagging_combine(&pair, 2, 2));
  if out2.len() != 2 { ok = false; }
  if out2.len() == 2 {
    let a2: Int = out2[0];
    let b2: Int = out2[1];
    if a2 != 1 { ok = false; }
    if b2 != 0 { ok = false; }
  }
  let signed = v3(-1, 1, -2);
  let out3 = ints_of(ensemble_bagging_combine(&signed, 3, 1));
  if out3.len() != 1 { ok = false; }
  if out3.len() == 1 {
    let s0: Int = out3[0];
    if s0 != -1 { ok = false; }
  }
  return assert(ok, "bagging averages entries in order with signed rounding");
}

fn t17() -> TestResult {
  let vectors = v4(1, 2, 3, 4);
  var ok = ints_err(ensemble_bagging_combine(&vectors, 0, 2), "ensemble: vector count must be positive");
  if !ints_err(ensemble_bagging_combine(&vectors, 2, 0), "ensemble: vector length must be positive") { ok = false; }
  let short = v2(1, 2);
  if !ints_err(ensemble_bagging_combine(&short, 2, 2), "ensemble: vectors length does not match the shape") { ok = false; }
  if !ints_err(ensemble_bagging_combine(&short, 9223372036854775807, 2), "ensemble: dimensions overflow") { ok = false; }
  return assert(ok, "bagging validates shape and dimensions");
}

fn t18() -> TestResult {
  let preds = v12(1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0);
  var ok = int_of(ensemble_pair_disagreement_bps(&preds, 3, 4, 0, 1)) == 5000;
  if int_of(ensemble_pair_disagreement_bps(&preds, 3, 4, 0, 2)) != 10000 { ok = false; }
  if int_of(ensemble_pair_disagreement_bps(&preds, 3, 4, 1, 2)) != 5000 { ok = false; }
  if int_of(ensemble_pair_disagreement_bps(&preds, 3, 4, 1, 0)) != 5000 { ok = false; }
  let mean = int_of(ensemble_disagreement_bps(&preds, 3, 4));
  if mean != 6667 { ok = false; }
  return assert(ok, "disagreement is pooled pairwise bps");
}

fn t19() -> TestResult {
  let preds = v12(1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0);
  var ok = int_err(ensemble_pair_disagreement_bps(&preds, 3, 4, 0, 0), "ensemble: model indices must be distinct");
  if !int_err(ensemble_pair_disagreement_bps(&preds, 3, 4, 3, 1), "ensemble: model index out of range") { ok = false; }
  if !int_err(ensemble_pair_disagreement_bps(&preds, 3, 4, 0, -1), "ensemble: model index out of range") { ok = false; }
  if !int_err(ensemble_pair_disagreement_bps(&preds, 3, 0, 0, 1), "ensemble: sample count must be positive") { ok = false; }
  let short = v2(1, 2);
  if !int_err(ensemble_pair_disagreement_bps(&short, 1, 4, 0, 1), "ensemble: predictions length does not match the shape") { ok = false; }
  if !int_err(ensemble_disagreement_bps(&short, 1, 2), "ensemble: need at least 2 models") { ok = false; }
  return assert(ok, "disagreement validates indices and shapes");
}

fn t20() -> TestResult {
  let thirds = v3(1, 1, 1);
  let n1 = ints_of(ensemble_normalize_weights(&thirds, 10000));
  var ok = n1.len() == 3;
  if n1.len() == 3 {
    let a: Int = n1[0];
    let b: Int = n1[1];
    let c: Int = n1[2];
    if a != 3334 { ok = false; }
    if b != 3333 { ok = false; }
    if c != 3333 { ok = false; }
  }
  if ensemble_weight_sum(&n1) != 10000 { ok = false; }
  let two_one = v2(2, 1);
  let n2 = ints_of(ensemble_normalize_weights(&two_one, 100));
  if n2.len() != 2 { ok = false; }
  if n2.len() == 2 {
    let a2: Int = n2[0];
    let b2: Int = n2[1];
    if a2 != 67 { ok = false; }
    if b2 != 33 { ok = false; }
  }
  let with_zero = v2(1, 0);
  let n3 = ints_of(ensemble_normalize_weights(&with_zero, 7));
  if n3.len() != 2 { ok = false; }
  if n3.len() == 2 {
    let a3: Int = n3[0];
    let b3: Int = n3[1];
    if a3 != 7 { ok = false; }
    if b3 != 0 { ok = false; }
  }
  let tie = v2(1, 1);
  let n4 = ints_of(ensemble_normalize_weights(&tie, 1));
  if n4.len() != 2 { ok = false; }
  if n4.len() == 2 {
    let a4: Int = n4[0];
    let b4: Int = n4[1];
    if a4 != 1 { ok = false; }
    if b4 != 0 { ok = false; }
  }
  if ensemble_weight_sum(&n4) != 1 { ok = false; }
  return assert(ok, "weight normalization sums exactly to the scale");
}

fn t21() -> TestResult {
  let empty = empty_ints();
  let weights = v2(1, 1);
  var ok = ints_err(ensemble_normalize_weights(&empty, 100), "ensemble: weights must not be empty");
  if !ints_err(ensemble_normalize_weights(&weights, 0), "ensemble: scale must be positive") { ok = false; }
  if !ints_err(ensemble_normalize_weights(&weights, -5), "ensemble: scale must be positive") { ok = false; }
  let zeros = v2(0, 0);
  if !ints_err(ensemble_normalize_weights(&zeros, 100), "ensemble: weight sum must be positive") { ok = false; }
  let neg = v2(-1, 2);
  if !ints_err(ensemble_normalize_weights(&neg, 100), "ensemble: weights must not be negative") { ok = false; }
  return assert(ok, "weight normalization validates its inputs");
}

fn t22() -> TestResult {
  let big = v1(9223372036854775807);
  var ok = ints_err(ensemble_normalize_weights(&big, 2), "ensemble: weight scale overflows");
  let big_sum = v2(9223372036854775807, 1);
  if !ints_err(ensemble_normalize_weights(&big_sum, 5), "ensemble: weight sum overflows") { ok = false; }
  return assert(ok, "weight normalization guards overflow");
}

fn t23() -> TestResult {
  let w = v3(1, 2, 3);
  var ok = ensemble_weight_sum(&w) == 6;
  let empty = empty_ints();
  if ensemble_weight_sum(&empty) != 0 { ok = false; }
  let signed = v2(-4, 10);
  if ensemble_weight_sum(&signed) != 6 { ok = false; }
  return assert(ok, "weight_sum is the plain arithmetic sum");
}

fn t24() -> TestResult {
  let empty = empty_ints();
  var ok = ints_err(ensemble_soft_vote(&empty, 9223372036854775807, 2), "ensemble: dimensions overflow");
  let big = v2(9223372036854775807, 1);
  if !ints_err(ensemble_soft_vote(&big, 2, 1), "ensemble: probability sum overflows") { ok = false; }
  let probs = v2(9223372036854775807, 0);
  let weights = v2(2, 0);
  if !ints_err(ensemble_soft_vote_weighted(&probs, &weights, 2, 1), "ensemble: weighted product overflows") { ok = false; }
  let half = 9223372036854775807 / 2 + 1;
  let probs2 = v2(half, half);
  let weights2 = v2(1, 1);
  if !ints_err(ensemble_soft_vote_weighted(&probs2, &weights2, 2, 1), "ensemble: weighted sum overflows") { ok = false; }
  return assert(ok, "soft vote guards Int overflow");
}

fn main() -> Int {
  io.println("=== xiom.ensemble conformance tests ===");
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
    io.println("xiom.ensemble: all tests passed");
  } else {
    io.println("xiom.ensemble: tests failed");
  }
  return failed;
}
