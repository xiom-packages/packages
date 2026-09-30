// XIOM -- xiom.stats_ml conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.stats_ml module against its documented
// fixed-point contract (scaled integers only, no floats, no FFI, no I/O in
// the library).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module stats_ml_tests
use xiom.io; use xiom.test; use xiom.stats_ml;
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

fn rep_str(s: Str, n: Int) -> Vec[Str] {
  var v = Vec[Str].new();
  var i = 0;
  while i < n {
    v.push(s);
    i = i + 1;
  }
  return v;
}

fn chain2_str(a: &Vec[Str], b: &Vec[Str]) -> Vec[Str] {
  var v = Vec[Str].new();
  var i = 0;
  while i < a.len() {
    let x: Str = a[i];
    v.push(x);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    let x: Str = b[i];
    v.push(x);
    i = i + 1;
  }
  return v;
}

fn chain4_str(a: &Vec[Str], b: &Vec[Str], c: &Vec[Str], d: &Vec[Str]) -> Vec[Str] {
  return chain2_str(&chain2_str(a, b), &chain2_str(c, d));
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

// Fixture A: binary 2x2 confusion [[8,2],[2,8]], classes cat/dog, N=20.
fn fixture_a_true() -> Vec[Str] {
  return chain2_str(&rep_str("cat", 10), &rep_str("dog", 10));
}

fn fixture_a_pred() -> Vec[Str] {
  return chain4_str(&rep_str("cat", 8), &rep_str("dog", 2), &rep_str("dog", 8), &rep_str("cat", 2));
}

// Fixture R3: 2x2 confusion [[3,1],[1,2]], classes a/b, N=7.
fn fixture_r3_true() -> Vec[Str] {
  return chain4_str(&rep_str("a", 3), &rep_str("a", 1), &rep_str("b", 1), &rep_str("b", 2));
}

fn fixture_r3_pred() -> Vec[Str] {
  return chain4_str(&rep_str("a", 3), &rep_str("b", 1), &rep_str("a", 1), &rep_str("b", 2));
}

// ---------------------------------------------------------------------------
// Result extractors with graceful fallbacks: a construction failure makes
// the value checks fail instead of aborting the whole suite.
// ---------------------------------------------------------------------------

fn cm_of(r: Result[ConfusionMatrix, Str]) -> ConfusionMatrix {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return ConfusionMatrix{ classes: Vec[Str].new(); counts: Vec[Int].new(); k: 0; total: 0; }; },
  }
  return ConfusionMatrix{ classes: Vec[Str].new(); counts: Vec[Int].new(); k: 0; total: 0; };
}

fn bal_of(r: Result[ClassBalance, Str]) -> ClassBalance {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return ClassBalance{ classes: Vec[Str].new(); counts: Vec[Int].new(); total: 0; k: 0; majority: 0; minority: 0; ratio_bps: 0; }; },
  }
  return ClassBalance{ classes: Vec[Str].new(); counts: Vec[Int].new(); total: 0; k: 0; majority: 0; minority: 0; ratio_bps: 0; };
}

fn roc_of(r: Result[RocCurve, Str]) -> RocCurve {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return RocCurve{ thresholds: Vec[Int].new(); fpr_bps: Vec[Int].new(); tpr_bps: Vec[Int].new(); tp: Vec[Int].new(); fp: Vec[Int].new(); positives: 0; negatives: 0; auc_bps: -1; n_points: -1; }; },
  }
  return RocCurve{ thresholds: Vec[Int].new(); fpr_bps: Vec[Int].new(); tpr_bps: Vec[Int].new(); tp: Vec[Int].new(); fp: Vec[Int].new(); positives: 0; negatives: 0; auc_bps: -1; n_points: -1; };
}

fn bins_of(r: Result[CalibrationBins, Str]) -> CalibrationBins {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return CalibrationBins{ n_bins: 0; counts: Vec[Int].new(); positives: Vec[Int].new(); score_sum: Vec[Int].new(); mean_score_bps: Vec[Int].new(); positive_rate_bps: Vec[Int].new(); }; },
  }
  return CalibrationBins{ n_bins: 0; counts: Vec[Int].new(); positives: Vec[Int].new(); score_sum: Vec[Int].new(); mean_score_bps: Vec[Int].new(); positive_rate_bps: Vec[Int].new(); };
}

fn int_of(r: Result[Int, Str]) -> Int {
  match r {
    Ok(x) => { return x; },
    Err(_) => { return -1; },
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Error-message predicates
// ---------------------------------------------------------------------------

fn cm_err(r: Result[ConfusionMatrix, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn bal_err(r: Result[ClassBalance, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn roc_err(r: Result[RocCurve, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn bins_err(r: Result[CalibrationBins, Str], want: Str) -> Bool {
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = stats_ml_bps() == 10000;
  if stats_ml_bin_index(0, 4) != 0 { ok = false; }
  if stats_ml_bin_index(4999, 4) != 1 { ok = false; }
  if stats_ml_bin_index(5000, 4) != 2 { ok = false; }
  if stats_ml_bin_index(9999, 4) != 3 { ok = false; }
  if stats_ml_bin_index(10000, 4) != 3 { ok = false; }
  if stats_ml_bin_index(-1, 4) != -1 { ok = false; }
  if stats_ml_bin_index(10001, 4) != -1 { ok = false; }
  if stats_ml_bin_index(0, 0) != -1 { ok = false; }
  if stats_ml_bin_index(0, 10001) != -1 { ok = false; }
  return assert(ok, "scale is 10000 and bin_index clamps the top edge");
}

fn t2() -> TestResult {
  let cm = cm_of(stats_ml_confusion_matrix(&fixture_a_true(), &fixture_a_pred()));
  var ok = stats_ml_cm_k(&cm) == 2;
  if stats_ml_cm_total(&cm) != 20 { ok = false; }
  let c0: Str = stats_ml_cm_class(&cm, 0);
  let c1: Str = stats_ml_cm_class(&cm, 1);
  if !streq(c0, "cat") { ok = false; }
  if !streq(c1, "dog") { ok = false; }
  if stats_ml_cm_cell(&cm, 0, 0) != 8 { ok = false; }
  if stats_ml_cm_cell(&cm, 0, 1) != 2 { ok = false; }
  if stats_ml_cm_cell(&cm, 1, 0) != 2 { ok = false; }
  if stats_ml_cm_cell(&cm, 1, 1) != 8 { ok = false; }
  if stats_ml_cm_class_index(&cm, "cat") != 0 { ok = false; }
  if stats_ml_cm_class_index(&cm, "dog") != 1 { ok = false; }
  if stats_ml_cm_class_index(&cm, "zz") != -1 { ok = false; }
  if stats_ml_cm_row_sum(&cm, 0) != 10 { ok = false; }
  if stats_ml_cm_col_sum(&cm, 1) != 10 { ok = false; }
  let far: Str = stats_ml_cm_class(&cm, 5);
  if !streq(far, "") { ok = false; }
  if stats_ml_cm_cell(&cm, 5, 0) != 0 { ok = false; }
  if stats_ml_cm_cell(&cm, 0, -1) != 0 { ok = false; }
  if stats_ml_cm_row_sum(&cm, -1) != 0 { ok = false; }
  if stats_ml_cm_col_sum(&cm, 9) != 0 { ok = false; }
  return assert(ok, "confusion matrix builds cells, classes and safe accessors");
}

fn t3() -> TestResult {
  let cm = cm_of(stats_ml_confusion_matrix(&fixture_a_true(), &fixture_a_pred()));
  var ok = stats_ml_precision_bps(&cm, 0) == 8000;
  if stats_ml_precision_bps(&cm, 1) != 8000 { ok = false; }
  if stats_ml_recall_bps(&cm, 0) != 8000 { ok = false; }
  if stats_ml_recall_bps(&cm, 1) != 8000 { ok = false; }
  if stats_ml_f1_bps(&cm, 0) != 8000 { ok = false; }
  if stats_ml_f1_bps(&cm, 1) != 8000 { ok = false; }
  if stats_ml_accuracy_bps(&cm) != 8000 { ok = false; }
  if stats_ml_macro_precision_bps(&cm) != 8000 { ok = false; }
  if stats_ml_macro_recall_bps(&cm) != 8000 { ok = false; }
  if stats_ml_macro_f1_bps(&cm) != 8000 { ok = false; }
  return assert(ok, "symmetric 2x2 matrix yields 8000 bps across all metrics");
}

fn t4() -> TestResult {
  let yt = rep_str("a", 32);
  let yp = chain2_str(&rep_str("a", 1), &rep_str("b", 31));
  let cm = cm_of(stats_ml_confusion_matrix(&yt, &yp));
  var ok = stats_ml_cm_cell(&cm, 0, 0) == 1;
  if stats_ml_cm_cell(&cm, 0, 1) != 31 { ok = false; }
  if stats_ml_precision_bps(&cm, 0) != 10000 { ok = false; }
  if stats_ml_recall_bps(&cm, 0) != 313 { ok = false; }
  if stats_ml_f1_bps(&cm, 0) != 607 { ok = false; }
  if stats_ml_accuracy_bps(&cm) != 313 { ok = false; }
  if stats_ml_macro_precision_bps(&cm) != 5000 { ok = false; }
  if stats_ml_macro_recall_bps(&cm) != 157 { ok = false; }
  if stats_ml_macro_f1_bps(&cm) != 304 { ok = false; }
  return assert(ok, "0.5 bps values round half away from zero (312.5 -> 313)");
}

fn t5() -> TestResult {
  let cm3 = cm_of(stats_ml_confusion_matrix(&fixture_r3_true(), &fixture_r3_pred()));
  var ok = stats_ml_precision_bps(&cm3, 0) == 7500;
  if stats_ml_precision_bps(&cm3, 1) != 6667 { ok = false; }
  if stats_ml_recall_bps(&cm3, 1) != 6667 { ok = false; }
  if stats_ml_f1_bps(&cm3, 1) != 6667 { ok = false; }
  if stats_ml_macro_precision_bps(&cm3) != 7084 { ok = false; }
  if stats_ml_accuracy_bps(&cm3) != 7143 { ok = false; }
  let yt = chain2_str(&rep_str("a", 3), &rep_str("b", 1));
  let yp = chain2_str(&chain2_str(&rep_str("a", 2), &rep_str("b", 1)), &rep_str("a", 1));
  let cm2 = cm_of(stats_ml_confusion_matrix(&yt, &yp));
  if stats_ml_precision_bps(&cm2, 0) != 6667 { ok = false; }
  if stats_ml_macro_precision_bps(&cm2) != 3334 { ok = false; }
  if stats_ml_macro_recall_bps(&cm2) != 3334 { ok = false; }
  return assert(ok, "macro averages round the half-bps mean away from zero");
}

fn t6() -> TestResult {
  let cm = cm_of(stats_ml_confusion_matrix(&fixture_a_true(), &fixture_a_pred()));
  var ok = int_of(stats_ml_kappa_bps(&cm)) == 6000;
  let diag_t = chain2_str(&rep_str("a", 5), &rep_str("b", 5));
  let diag_p = chain2_str(&rep_str("a", 5), &rep_str("b", 5));
  let diag = cm_of(stats_ml_confusion_matrix(&diag_t, &diag_p));
  if int_of(stats_ml_kappa_bps(&diag)) != 10000 { ok = false; }
  let one_t = rep_str("a", 3);
  let one_p = rep_str("a", 3);
  let one = cm_of(stats_ml_confusion_matrix(&one_t, &one_p));
  if int_of(stats_ml_kappa_bps(&one)) != 0 { ok = false; }
  return assert(ok, "kappa is exact fixed point and 0 for the degenerate matrix");
}

fn t7() -> TestResult {
  let cm3 = cm_of(stats_ml_confusion_matrix(&fixture_r3_true(), &fixture_r3_pred()));
  var ok = int_of(stats_ml_kappa_bps(&cm3)) == 4167;
  let yt = chain2_str(&rep_str("a", 3), &rep_str("b", 1));
  let yp = chain2_str(&chain2_str(&rep_str("a", 2), &rep_str("b", 1)), &rep_str("a", 1));
  let cm2 = cm_of(stats_ml_confusion_matrix(&yt, &yp));
  if int_of(stats_ml_kappa_bps(&cm2)) != -3333 { ok = false; }
  let yt2 = chain2_str(&rep_str("a", 2), &rep_str("b", 2));
  let yp2 = chain2_str(&chain2_str(&rep_str("a", 1), &rep_str("b", 1)), &chain2_str(&rep_str("a", 1), &rep_str("b", 1)));
  let chance = cm_of(stats_ml_confusion_matrix(&yt2, &yp2));
  if int_of(stats_ml_kappa_bps(&chance)) != 0 { ok = false; }
  return assert(ok, "kappa handles positive, negative and chance-level matrices");
}

fn t8() -> TestResult {
  let short = rep_str("a", 1);
  var ok = cm_err(stats_ml_confusion_matrix(&short, &rep_str("a", 2)), "stats_ml: label vectors must have equal length");
  let empty = Vec[Str].new();
  if !cm_err(stats_ml_confusion_matrix(&empty, &empty), "stats_ml: label vectors must not be empty") { ok = false; }
  let yt = chain2_str(&rep_str("a", 1), &rep_str("a", 1));
  let yp = chain2_str(&rep_str("a", 1), &rep_str("b", 1));
  let cm = cm_of(stats_ml_confusion_matrix(&yt, &yp));
  if stats_ml_cm_k(&cm) != 2 { ok = false; }
  let c1: Str = stats_ml_cm_class(&cm, 1);
  if !streq(c1, "b") { ok = false; }
  return assert(ok, "confusion matrix validates and appends prediction-only classes");
}

fn t9() -> TestResult {
  let labels = v4(1, 1, 0, 0);
  let scores = v4(4, 3, 2, 1);
  let curve = roc_of(stats_ml_roc_curve(&scores, &labels));
  var ok = stats_ml_roc_n_points(&curve) == 4;
  if stats_ml_roc_positives(&curve) != 2 { ok = false; }
  if stats_ml_roc_negatives(&curve) != 2 { ok = false; }
  if stats_ml_roc_auc_bps(&curve) != 10000 { ok = false; }
  if stats_ml_roc_threshold(&curve, 0) != 4 { ok = false; }
  if stats_ml_roc_tpr_bps(&curve, 0) != 5000 { ok = false; }
  if stats_ml_roc_fpr_bps(&curve, 0) != 0 { ok = false; }
  if stats_ml_roc_tp(&curve, 0) != 1 { ok = false; }
  if stats_ml_roc_fp(&curve, 0) != 0 { ok = false; }
  if stats_ml_roc_tpr_bps(&curve, 1) != 10000 { ok = false; }
  if stats_ml_roc_fpr_bps(&curve, 3) != 10000 { ok = false; }
  return assert(ok, "ROC sweep of a perfectly ranked classifier has AUC 10000");
}

fn t10() -> TestResult {
  let labels = v4(1, 0, 1, 0);
  let scores = v4(1, 2, 3, 4);
  let curve = roc_of(stats_ml_roc_curve(&scores, &labels));
  var ok = stats_ml_roc_auc_bps(&curve) == 2500;
  if stats_ml_roc_threshold(&curve, 0) != 4 { ok = false; }
  if stats_ml_roc_fpr_bps(&curve, 0) != 5000 { ok = false; }
  if stats_ml_roc_tpr_bps(&curve, 0) != 0 { ok = false; }
  if stats_ml_roc_fpr_bps(&curve, 2) != 10000 { ok = false; }
  if stats_ml_roc_tpr_bps(&curve, 2) != 5000 { ok = false; }
  if stats_ml_roc_tpr_bps(&curve, 3) != 10000 { ok = false; }
  return assert(ok, "ROC trapezoid gives 2500 for an interleaved ranking");
}

fn t11() -> TestResult {
  let t_labels = v2(1, 0);
  let t_scores = v2(5, 5);
  let tie = roc_of(stats_ml_roc_curve(&t_scores, &t_labels));
  var ok = stats_ml_roc_n_points(&tie) == 1;
  if stats_ml_roc_auc_bps(&tie) != 5000 { ok = false; }
  let labels = v6(1, 1, 0, 0, 0, 0);
  let scores = v6(1, 1, 0, 0, 0, 0);
  let curve = roc_of(stats_ml_roc_curve(&scores, &labels));
  if stats_ml_roc_auc_bps(&curve) != 10000 { ok = false; }
  return assert(ok, "tied scores yield AUC 5000; flat positives rank perfectly");
}

fn t12() -> TestResult {
  let scores = v4(1, 2, 3, 4);
  var ok = roc_err(stats_ml_roc_curve(&scores, &v2(1, 0)), "stats_ml: score and label vectors must have equal length");
  let empty = Vec[Int].new();
  if !roc_err(stats_ml_roc_curve(&empty, &empty), "stats_ml: score and label vectors must not be empty") { ok = false; }
  let bad = v4(2, 0, 1, 0);
  if !roc_err(stats_ml_roc_curve(&scores, &bad), "stats_ml: labels must be 0 or 1") { ok = false; }
  let no_pos = v4(0, 0, 0, 0);
  if !roc_err(stats_ml_roc_curve(&scores, &no_pos), "stats_ml: roc requires at least one positive label") { ok = false; }
  let no_neg = v4(1, 1, 1, 1);
  if !roc_err(stats_ml_roc_curve(&scores, &no_neg), "stats_ml: roc requires at least one negative label") { ok = false; }
  let good = v4(1, 1, 0, 0);
  let curve = roc_of(stats_ml_roc_curve(&scores, &good));
  if stats_ml_roc_threshold(&curve, 9) != 0 { ok = false; }
  if stats_ml_roc_fpr_bps(&curve, -1) != 0 { ok = false; }
  if stats_ml_roc_tp(&curve, 99) != 0 { ok = false; }
  return assert(ok, "ROC validates inputs and its accessors are range safe");
}

// Build the 100-sample, 4-bin calibration fixture: bin b holds 25 samples,
// score 1250, and b+1 positives inside it.
fn cal_scores() -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < 100 {
    let b = i / 25;
    v.push(b * 2500 + 1250);
    i = i + 1;
  }
  return v;
}

fn cal_labels() -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < 100 {
    let b = i / 25;
    let within = i - b * 25;
    if within <= b {
      v.push(1);
    } else {
      v.push(0);
    }
    i = i + 1;
  }
  return v;
}

fn t13() -> TestResult {
  let bins = bins_of(stats_ml_calibration_bins(&cal_scores(), &cal_labels(), 4));
  var ok = stats_ml_bins_count(&bins) == 4;
  if stats_ml_bin_count(&bins, 0) != 25 { ok = false; }
  if stats_ml_bin_count(&bins, 3) != 25 { ok = false; }
  if stats_ml_bin_positives(&bins, 0) != 1 { ok = false; }
  if stats_ml_bin_positives(&bins, 3) != 4 { ok = false; }
  if stats_ml_bin_mean_score_bps(&bins, 0) != 1250 { ok = false; }
  if stats_ml_bin_mean_score_bps(&bins, 3) != 8750 { ok = false; }
  if stats_ml_bin_positive_rate_bps(&bins, 0) != 400 { ok = false; }
  if stats_ml_bin_positive_rate_bps(&bins, 1) != 800 { ok = false; }
  if stats_ml_bin_positive_rate_bps(&bins, 2) != 1200 { ok = false; }
  if stats_ml_bin_positive_rate_bps(&bins, 3) != 1600 { ok = false; }
  if stats_ml_calibration_ece_bps(&bins) != 4000 { ok = false; }
  return assert(ok, "calibration bins report counts, means, rates and ECE");
}

fn t14() -> TestResult {
  let scores = v4(0, 1250, 9999, 10000);
  let labels = v4(0, 1, 0, 1);
  let bins = bins_of(stats_ml_calibration_bins(&scores, &labels, 4));
  var ok = stats_ml_bin_count(&bins, 0) == 2;
  if stats_ml_bin_count(&bins, 3) != 2 { ok = false; }
  let bad_scores = v4(0, -1, 0, 0);
  if !bins_err(stats_ml_calibration_bins(&bad_scores, &labels, 4), "stats_ml: scores must be in [0, 10000]") { ok = false; }
  let high_scores = v4(0, 10001, 0, 0);
  if !bins_err(stats_ml_calibration_bins(&high_scores, &labels, 4), "stats_ml: scores must be in [0, 10000]") { ok = false; }
  if !bins_err(stats_ml_calibration_bins(&scores, &labels, 0), "stats_ml: bin count must be positive") { ok = false; }
  if !bins_err(stats_ml_calibration_bins(&scores, &labels, 10001), "stats_ml: bin count must not exceed 10000") { ok = false; }
  if !bins_err(stats_ml_calibration_bins(&scores, &v2(0, 1), 4), "stats_ml: score and label vectors must have equal length") { ok = false; }
  let empty = Vec[Int].new();
  if !bins_err(stats_ml_calibration_bins(&empty, &empty, 4), "stats_ml: score and label vectors must not be empty") { ok = false; }
  let bad_labels = v4(0, 2, 0, 1);
  if !bins_err(stats_ml_calibration_bins(&scores, &bad_labels, 4), "stats_ml: labels must be 0 or 1") { ok = false; }
  if stats_ml_bin_count(&bins, 9) != 0 { ok = false; }
  if stats_ml_bin_mean_score_bps(&bins, -1) != 0 { ok = false; }
  return assert(ok, "calibration validates bins, scores, labels and ranges");
}

fn t15() -> TestResult {
  let scores = v2(0, 10000);
  let labels = v2(1, 0);
  let bins = bins_of(stats_ml_calibration_bins(&scores, &labels, 3));
  var ok = stats_ml_bin_count(&bins, 1) == 0;
  if stats_ml_bin_mean_score_bps(&bins, 1) != 0 { ok = false; }
  if stats_ml_bin_positive_rate_bps(&bins, 1) != 0 { ok = false; }
  if stats_ml_bin_mean_score_bps(&bins, 2) != 10000 { ok = false; }
  if stats_ml_bin_positive_rate_bps(&bins, 0) != 10000 { ok = false; }
  if stats_ml_calibration_ece_bps(&bins) != 10000 { ok = false; }
  return assert(ok, "empty calibration bins report zeros and ECE spans extremes");
}

fn t16() -> TestResult {
  let cm = cm_of(stats_ml_confusion_matrix(&fixture_r3_true(), &fixture_r3_pred()));
  let want = "xiom.stats_ml classification report\nclasses=2 samples=7 accuracy_bps=7143 kappa_bps=4167\nclass[0] \"a\" support=4 precision_bps=7500 recall_bps=7500 f1_bps=7500\nclass[1] \"b\" support=3 precision_bps=6667 recall_bps=6667 f1_bps=6667\nmacro precision_bps=7084 recall_bps=7084 f1_bps=7084";
  let got = stats_ml_classification_report(&cm);
  return assert(streq(got, want), "classification report renders the exact R3 text");
}

fn t17() -> TestResult {
  let cm = cm_of(stats_ml_confusion_matrix(&fixture_a_true(), &fixture_a_pred()));
  let want = "xiom.stats_ml classification report\nclasses=2 samples=20 accuracy_bps=8000 kappa_bps=6000\nclass[0] \"cat\" support=10 precision_bps=8000 recall_bps=8000 f1_bps=8000\nclass[1] \"dog\" support=10 precision_bps=8000 recall_bps=8000 f1_bps=8000\nmacro precision_bps=8000 recall_bps=8000 f1_bps=8000";
  let got = stats_ml_classification_report(&cm);
  var ok = streq(got, want);
  let st = chain2_str(&rep_str("x y", 2), &rep_str("z", 1));
  let sp = chain2_str(&rep_str("x y", 2), &rep_str("z", 1));
  let spaced = cm_of(stats_ml_confusion_matrix(&st, &sp));
  let text = stats_ml_classification_report(&spaced);
  if !string.str_contains(text, "class[0] \"x y\"") { ok = false; }
  if !string.str_contains(text, "class[1] \"z\"") { ok = false; }
  return assert(ok, "classification report text is exact and preserves spaced labels");
}

fn t18() -> TestResult {
  var yt = Vec[Str].new();
  var yp = Vec[Str].new();
  var i = 0;
  while i < 1000 {
    let m = i % 10;
    if m < 7 {
      yt.push("pos");
    } else {
      yt.push("neg");
    }
    if m < 6 {
      yp.push("pos");
    } else {
      yp.push("neg");
    }
    i = i + 1;
  }
  let cm = cm_of(stats_ml_confusion_matrix(&yt, &yp));
  var ok = stats_ml_cm_total(&cm) == 1000;
  if stats_ml_cm_cell(&cm, 0, 0) != 600 { ok = false; }
  if stats_ml_accuracy_bps(&cm) != 9000 { ok = false; }
  if stats_ml_macro_precision_bps(&cm) != 8750 { ok = false; }
  if stats_ml_macro_recall_bps(&cm) != 9286 { ok = false; }
  if stats_ml_macro_f1_bps(&cm) != 8901 { ok = false; }
  if int_of(stats_ml_kappa_bps(&cm)) != 7826 { ok = false; }
  return assert(ok, "N=1000 confusion matrix matches the fixed-point expectations");
}

fn t19() -> TestResult {
  var scores = Vec[Int].new();
  var labels = Vec[Int].new();
  var i = 0;
  while i < 1000 {
    scores.push(i % 100);
    if i < 500 {
      labels.push(1);
    } else {
      labels.push(0);
    }
    i = i + 1;
  }
  let curve = roc_of(stats_ml_roc_curve(&scores, &labels));
  var ok = stats_ml_roc_n_points(&curve) == 100;
  if stats_ml_roc_positives(&curve) != 500 { ok = false; }
  if stats_ml_roc_negatives(&curve) != 500 { ok = false; }
  if stats_ml_roc_auc_bps(&curve) != 5000 { ok = false; }
  var prev_fpr: Int = 0;
  var prev_tpr: Int = 0;
  var j = 0;
  while j < stats_ml_roc_n_points(&curve) {
    let f = stats_ml_roc_fpr_bps(&curve, j);
    let t = stats_ml_roc_tpr_bps(&curve, j);
    if f < prev_fpr { ok = false; }
    if t < prev_tpr { ok = false; }
    if f > 10000 { ok = false; }
    if t > 10000 { ok = false; }
    prev_fpr = f;
    prev_tpr = t;
    j = j + 1;
  }
  if prev_fpr != 10000 { ok = false; }
  if prev_tpr != 10000 { ok = false; }
  return assert(ok, "N=1000 ROC sweep is monotone with AUC 5000");
}

fn t20() -> TestResult {
  let yt = chain2_str(&rep_str("a", 2), &chain2_str(&rep_str("b", 2), &rep_str("c", 2)));
  let yp = chain2_str(&chain2_str(&chain2_str(&rep_str("a", 1), &rep_str("b", 1)), &chain2_str(&rep_str("b", 1), &rep_str("c", 1))), &chain2_str(&rep_str("c", 1), &rep_str("a", 1)));
  let cm = cm_of(stats_ml_confusion_matrix(&yt, &yp));
  var ok = stats_ml_cm_k(&cm) == 3;
  if stats_ml_cm_total(&cm) != 6 { ok = false; }
  if stats_ml_cm_cell(&cm, 0, 1) != 1 { ok = false; }
  if stats_ml_cm_cell(&cm, 1, 2) != 1 { ok = false; }
  if stats_ml_cm_cell(&cm, 2, 0) != 1 { ok = false; }
  if stats_ml_cm_row_sum(&cm, 0) != 2 { ok = false; }
  if stats_ml_cm_row_sum(&cm, 2) != 2 { ok = false; }
  if stats_ml_cm_col_sum(&cm, 1) != 2 { ok = false; }
  if stats_ml_accuracy_bps(&cm) != 5000 { ok = false; }
  if stats_ml_cm_class_index(&cm, "c") != 2 { ok = false; }
  if stats_ml_cm_class_index(&cm, "q") != -1 { ok = false; }
  let c2: Str = stats_ml_cm_class(&cm, 2);
  let c3: Str = stats_ml_cm_class(&cm, 3);
  if !streq(c2, "c") { ok = false; }
  if !streq(c3, "") { ok = false; }
  return assert(ok, "3x3 confusion matrix rows, columns and accuracy");
}

fn t21() -> TestResult {
  let counts = v2(3, 2);
  let one = chain2_str(&rep_str("a", 3), &rep_str("b", 2));
  let bal = bal_of(stats_ml_class_balance(&one));
  var ok = stats_ml_balance_k(&bal) == 2;
  if stats_ml_balance_total(&bal) != 5 { ok = false; }
  if stats_ml_balance_majority(&bal) != 3 { ok = false; }
  if stats_ml_balance_minority(&bal) != 2 { ok = false; }
  if stats_ml_balance_ratio_bps(&bal) != 6667 { ok = false; }
  let c0: Str = stats_ml_balance_class(&bal, 0);
  if !streq(c0, "a") { ok = false; }
  if stats_ml_balance_count(&bal, 1) != 2 { ok = false; }
  if stats_ml_balance_count(&bal, 9) != 0 { ok = false; }
  let c9: Str = stats_ml_balance_class(&bal, 9);
  if !streq(c9, "") { ok = false; }
  let even = bal_of(stats_ml_class_balance(&chain2_str(&rep_str("a", 4), &rep_str("b", 4))));
  if stats_ml_balance_ratio_bps(&even) != 10000 { ok = false; }
  let empty = Vec[Str].new();
  if !bal_err(stats_ml_class_balance(&empty), "stats_ml: labels must not be empty") { ok = false; }
  if counts.len() != 2 { ok = false; }
  return assert(ok, "class balance counts, ratio and empty-input error");
}

fn t22() -> TestResult {
  let yt = chain4_str(&rep_str("a", 1), &rep_str("b", 1), &rep_str("c", 1), &rep_str("d", 1));
  let yp = chain4_str(&rep_str("a", 1), &rep_str("b", 1), &rep_str("c", 1), &rep_str("d", 1));
  let cm = cm_of(stats_ml_confusion_matrix(&yt, &yp));
  var ok = stats_ml_cm_k(&cm) == 4;
  if stats_ml_cm_total(&cm) != 4 { ok = false; }
  if int_of(stats_ml_kappa_bps(&cm)) != 10000 { ok = false; }
  if stats_ml_accuracy_bps(&cm) != 10000 { ok = false; }
  let report = stats_ml_classification_report(&cm);
  if !string.str_contains(report, "samples=4") { ok = false; }
  if !string.str_contains(report, "kappa_bps=10000") { ok = false; }
  return assert(ok, "4-class diagonal matrix is perfect and renders in the report");
}

fn main() -> Int {
  io.println("=== xiom.stats_ml conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.stats_ml: all tests passed");
  } else {
    io.println("xiom.stats_ml: tests failed");
  }
  return failed;
}
