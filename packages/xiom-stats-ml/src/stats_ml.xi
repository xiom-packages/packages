// XIOM -- xiom.stats_ml: fixed-point ML evaluation metrics
// Port task: replace the xiom.stats-ml placeholder with a pure-XIOM module
// (scaled integers only: no floats, no FFI, no I/O, no Vec[Float64]).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   - confusion matrix: multi-class, built from parallel label vectors; the
//     distinct classes are collected in first-occurrence order (y_true first,
//     then any label seen only in y_pred); cells are a flat row-major
//     Vec[Int] of counts, true class i x predicted class j at i*k + j.
//   - per-class precision/recall/F1 and the macro averages, all in basis
//     points (10000 bps = 1.0), with round-half-away-from-zero; a zero
//     denominator yields 0 (documented "no positive predictions" / "no
//     support" conventions).
//   - accuracy in basis points.
//   - Cohen's kappa in basis points from the exact integer ratio
//     (D*N - S) / (N^2 - S), one rounding; the degenerate S == N^2 case is
//     defined as 0.
//   - ROC threshold sweep for a binary integer-scored classifier: one point
//     per distinct score (descending), TPR/FPR in basis points, and AUC by
//     the trapezoid rule over the points plus the implicit (0,0) and (1,1)
//     endpoints, in fixed point.
//   - calibration bins over integer scores in [0, 10000]: per-bin count,
//     positive count, mean score and empirical positive rate, plus the
//     expected calibration error (ECE) in basis points.
//   - class balance: first-occurrence per-class counts, majority/minority
//     counts and the minority/majority ratio in basis points.
//   - classification report: a deterministic ASCII text renderer.
//
// v0.62.1 notes that shaped this module:
//   * Str values are never compared with `==` (BUG 17 lowers `==` on Str
//     values read from Vec elements to a pointer comparison); every label
//     comparison goes through string.str_compare with both sides bound to
//     typed locals first.
//   * every Vec[Int] / Vec[Str] element read binds the element to a typed
//     local before it is used.
//   * Ok/Err construction is confined to the leaf helpers at the bottom
//     (_ok_cm/_err_cm/_ok_bal/_err_bal/_ok_roc/_err_roc/_ok_bins/_err_bins/
//     _ok_int/_err_int).
//   * free functions only: no methods, no generics, no callbacks, no indexed
//     function-table dispatch; struct fields are parallel Vecs.

module xiom.stats_ml

use xiom.string;
use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Basis-point scale: 10000 bps = 1.0.
const _ML_BPS: Int = 10000;
const _ML_INT_MAX: Int = 9223372036854775807;
// floor(sqrt(INT_MAX)); guards N*N and k*k.
const _ML_SQRT_MAX: Int = 3037000499;
// floor(INT_MAX / 10000); guards num * 10000.
const _ML_SCALE_MAX: Int = 922337203685477;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Multi-class confusion matrix over `k` distinct classes.
///
/// `classes` holds the distinct labels in first-occurrence order and
/// `counts` is a flat row-major matrix of length k*k: the count of samples
/// whose true class is `i` and predicted class is `j` lives at `i*k + j`.
/// `total` is the number of samples. Fields are implementation detail; use
/// the stats_ml_cm_* accessors.
pub type ConfusionMatrix = {
  classes: Vec[Str];
  counts: Vec[Int];
  k: Int;
  total: Int;
}

/// Class-balance summary of a label vector.
///
/// `classes`/`counts` are parallel (first-occurrence order), `total` is the
/// sample count, `majority`/`minority` are the largest/smallest per-class
/// counts and `ratio_bps` = round_half_away(10000 * minority / majority),
/// so 10000 means perfectly balanced.
pub type ClassBalance = {
  classes: Vec[Str];
  counts: Vec[Int];
  total: Int;
  k: Int;
  majority: Int;
  minority: Int;
  ratio_bps: Int;
}

/// ROC threshold sweep over a binary integer-scored classifier.
///
/// One point per distinct observed score, in descending score order, so FPR
/// is non-decreasing. Parallel vectors (same length `n_points`): `thresholds`,
/// `fpr_bps`, `tpr_bps`, `tp`, `fp`. `positives`/`negatives` are the class
/// counts; `auc_bps` is the trapezoid AUC plus the implicit (0,0) start and
/// (1,1) end, in basis points (10000 = perfect ranking).
pub type RocCurve = {
  thresholds: Vec[Int];
  fpr_bps: Vec[Int];
  tpr_bps: Vec[Int];
  tp: Vec[Int];
  fp: Vec[Int];
  positives: Int;
  negatives: Int;
  auc_bps: Int;
  n_points: Int;
}

/// Calibration bins over integer scores in [0, 10000] (basis points).
///
/// Parallel vectors of length `n_bins`: `counts`, `positives`, `score_sum`
/// (raw sum of scores per bin), `mean_score_bps` and `positive_rate_bps`.
/// Empty bins have count 0 and zeroed mean/rate.
pub type CalibrationBins = {
  n_bins: Int;
  counts: Vec[Int];
  positives: Vec[Int];
  score_sum: Vec[Int];
  mean_score_bps: Vec[Int];
  positive_rate_bps: Vec[Int];
}

// ---------------------------------------------------------------------------
// Scale
// ---------------------------------------------------------------------------

/// Basis-point scale of every metric in this module (10000). Complexity: O(1).
pub fn stats_ml_bps() -> Int {
  return _ML_BPS;
}

// ---------------------------------------------------------------------------
// Confusion matrix
// ---------------------------------------------------------------------------

/// Build a multi-class confusion matrix from parallel label vectors.
///
/// Params: y_true / y_pred - one class label per sample, equal length, not
///         empty.
/// Returns: Ok(ConfusionMatrix) with distinct labels in first-occurrence
/// order (all of y_true scanned first, then labels seen only in y_pred).
/// Error case: Err("stats_ml: ...") for a length mismatch or an empty input.
/// Complexity: O(n * k) comparisons in the number of samples.
pub fn stats_ml_confusion_matrix(y_true: &Vec[Str], y_pred: &Vec[Str]) -> Result[ConfusionMatrix, Str] {
  let n = y_true.len();
  if y_pred.len() != n {
    return _err_cm("stats_ml: label vectors must have equal length");
  }
  if n <= 0 {
    return _err_cm("stats_ml: label vectors must not be empty");
  }
  var classes = Vec[Str].new();
  var i = 0;
  while i < n {
    let t: Str = y_true[i];
    let ti = _class_find(&classes, t);
    if ti < 0 {
      classes.push(t);
    }
    let p: Str = y_pred[i];
    let pi = _class_find(&classes, p);
    if pi < 0 {
      classes.push(p);
    }
    i = i + 1;
  }
  let k = classes.len();
  if k > _ML_SQRT_MAX {
    return _err_cm("stats_ml: class count too large");
  }
  var counts = Vec[Int].new();
  var z = 0;
  while z < k * k {
    counts.push(0);
    z = z + 1;
  }
  i = 0;
  while i < n {
    let t: Str = y_true[i];
    let p: Str = y_pred[i];
    let ti = _class_find(&classes, t);
    let pi = _class_find(&classes, p);
    let at = ti * k + pi;
    let old: Int = counts[at];
    counts[at] = old + 1;
    i = i + 1;
  }
  return _ok_cm(ConfusionMatrix{ classes: classes; counts: counts; k: k; total: n; });
}

/// Number of distinct classes. Complexity: O(1).
pub fn stats_ml_cm_k(cm: &ConfusionMatrix) -> Int {
  return cm.k;
}

/// Number of samples in the matrix. Complexity: O(1).
pub fn stats_ml_cm_total(cm: &ConfusionMatrix) -> Int {
  return cm.total;
}

/// Class label at index `i`, or "" when `i` is out of range. Complexity: O(1).
pub fn stats_ml_cm_class(cm: &ConfusionMatrix, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= cm.classes.len() {
    return "";
  }
  let s: Str = cm.classes[i];
  return s;
}

/// Index of `label` in first-occurrence order, or -1 when unseen.
/// Comparison uses string.str_compare. Complexity: O(k).
pub fn stats_ml_cm_class_index(cm: &ConfusionMatrix, label: Str) -> Int {
  var i = 0;
  while i < cm.classes.len() {
    let known: Str = cm.classes[i];
    if string.str_compare(known, label) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Count in cell (true `i`, predicted `j`), or 0 when out of range.
/// Complexity: O(1).
pub fn stats_ml_cm_cell(cm: &ConfusionMatrix, i: Int, j: Int) -> Int {
  if i < 0 {
    return 0;
  }
  if j < 0 {
    return 0;
  }
  if i >= cm.k {
    return 0;
  }
  if j >= cm.k {
    return 0;
  }
  let v: Int = cm.counts[i * cm.k + j];
  return v;
}

/// Support of class `i` (row sum), or 0 when out of range. Complexity: O(k).
pub fn stats_ml_cm_row_sum(cm: &ConfusionMatrix, i: Int) -> Int {
  return _cm_row_sum(cm, i);
}

/// Number of predictions of class `j` (column sum), or 0 when out of range.
/// Complexity: O(k).
pub fn stats_ml_cm_col_sum(cm: &ConfusionMatrix, j: Int) -> Int {
  return _cm_col_sum(cm, j);
}

// ---------------------------------------------------------------------------
// Per-class and macro metrics
// ---------------------------------------------------------------------------

/// Precision of class `i` in basis points: round_half_away(10000 * TP / (TP +
/// FP)); 0 when the class has no predicted positives. Out-of-range `i` is 0.
/// Complexity: O(k).
pub fn stats_ml_precision_bps(cm: &ConfusionMatrix, i: Int) -> Int {
  let tp = _cm_tp(cm, i);
  let den = _cm_col_sum(cm, i);
  if den <= 0 {
    return 0;
  }
  return _div_round(tp * _ML_BPS, den);
}

/// Recall of class `i` in basis points: round_half_away(10000 * TP / support);
/// 0 when the class has no support. Out-of-range `i` is 0. Complexity: O(k).
pub fn stats_ml_recall_bps(cm: &ConfusionMatrix, i: Int) -> Int {
  let tp = _cm_tp(cm, i);
  let den = _cm_row_sum(cm, i);
  if den <= 0 {
    return 0;
  }
  return _div_round(tp * _ML_BPS, den);
}

/// F1 of class `i` in basis points: round_half_away(2 * P * R / (P + R)) on
/// the per-class precision/recall basis-point values; 0 when P + R == 0.
/// Out-of-range `i` is 0. Complexity: O(k).
pub fn stats_ml_f1_bps(cm: &ConfusionMatrix, i: Int) -> Int {
  let p = stats_ml_precision_bps(cm, i);
  let r = stats_ml_recall_bps(cm, i);
  let den = p + r;
  if den <= 0 {
    return 0;
  }
  return _div_round(2 * p * r, den);
}

/// Macro precision: round_half_away(sum_i precision_bps(i) / k). 0 for an
/// empty matrix. Complexity: O(k^2).
pub fn stats_ml_macro_precision_bps(cm: &ConfusionMatrix) -> Int {
  let k = cm.k;
  if k <= 0 {
    return 0;
  }
  var s: Int = 0;
  var i = 0;
  while i < k {
    s = s + stats_ml_precision_bps(cm, i);
    i = i + 1;
  }
  return _div_round(s, k);
}

/// Macro recall: round_half_away(sum_i recall_bps(i) / k). 0 for an empty
/// matrix. Complexity: O(k^2).
pub fn stats_ml_macro_recall_bps(cm: &ConfusionMatrix) -> Int {
  let k = cm.k;
  if k <= 0 {
    return 0;
  }
  var s: Int = 0;
  var i = 0;
  while i < k {
    s = s + stats_ml_recall_bps(cm, i);
    i = i + 1;
  }
  return _div_round(s, k);
}

/// Macro F1: round_half_away(sum_i f1_bps(i) / k). 0 for an empty matrix.
/// Complexity: O(k^2).
pub fn stats_ml_macro_f1_bps(cm: &ConfusionMatrix) -> Int {
  let k = cm.k;
  if k <= 0 {
    return 0;
  }
  var s: Int = 0;
  var i = 0;
  while i < k {
    s = s + stats_ml_f1_bps(cm, i);
    i = i + 1;
  }
  return _div_round(s, k);
}

/// Accuracy in basis points: round_half_away(10000 * diagonal / total); 0 for
/// an empty matrix. Complexity: O(k).
pub fn stats_ml_accuracy_bps(cm: &ConfusionMatrix) -> Int {
  let n = cm.total;
  if n <= 0 {
    return 0;
  }
  var d: Int = 0;
  var i = 0;
  while i < cm.k {
    d = d + _cm_tp(cm, i);
    i = i + 1;
  }
  return _div_round(d * _ML_BPS, n);
}

/// Cohen's kappa in basis points, computed from the exact integer ratio
/// kappa = (D*N - S) / (N^2 - S), where D is the diagonal sum, N the total
/// and S = sum_i row_i * col_i; the single final division rounds half away
/// from zero and scales by 10000. When S == N^2 (chance agreement is 1) the
/// result is defined as 0.
/// Error case: Err("stats_ml: ...") for an empty matrix, N too large to square
/// or a numerator too large to scale.
/// Complexity: O(k).
pub fn stats_ml_kappa_bps(cm: &ConfusionMatrix) -> Result[Int, Str] {
  let n = cm.total;
  if n <= 0 {
    return _err_int("stats_ml: kappa requires a non-empty matrix");
  }
  if n > _ML_SQRT_MAX {
    return _err_int("stats_ml: kappa sample count too large");
  }
  var d: Int = 0;
  var s: Int = 0;
  var i = 0;
  while i < cm.k {
    let tp = _cm_tp(cm, i);
    let rs = _cm_row_sum(cm, i);
    let cs = _cm_col_sum(cm, i);
    d = d + tp;
    s = s + rs * cs;
    i = i + 1;
  }
  let num = d * n - s;
  let den = n * n - s;
  if den <= 0 {
    return _ok_int(0);
  }
  if num > _ML_SCALE_MAX {
    return _err_int("stats_ml: kappa scale overflows");
  }
  if num < 0 - _ML_SCALE_MAX {
    return _err_int("stats_ml: kappa scale overflows");
  }
  return _ok_int(_div_round(num * _ML_BPS, den));
}

// ---------------------------------------------------------------------------
// ROC / AUC
// ---------------------------------------------------------------------------

/// ROC threshold sweep and trapezoid AUC for a binary integer-scored model.
///
/// Params: scores - one integer score per sample (any range; ties supported);
///         labels - 0 (negative) or 1 (positive), same length, not empty.
/// Returns: Ok(RocCurve) with one point per distinct score, in descending
/// score order. At a point, a sample is predicted positive when its score is
/// >= the threshold; `tpr_bps` = round_half_away(10000 * TP / positives) and
/// `fpr_bps` = round_half_away(10000 * FP / negatives). `auc_bps` connects
/// the points in FPR order with the implicit (0,0) and (1,1) endpoints using
/// the trapezoid rule: area2 = sum_segments dfpr * (tpr + prev_tpr) plus the
/// final segment, then auc_bps = round_half_away(area2 / 20000).
/// Error case: Err("stats_ml: ...") for a length mismatch, an empty input, a
/// label other than 0/1, or a class with no samples.
/// Complexity: O(n * d) for n samples and d distinct scores (O(n^2) worst).
pub fn stats_ml_roc_curve(scores: &Vec[Int], labels: &Vec[Int]) -> Result[RocCurve, Str] {
  let n = scores.len();
  if labels.len() != n {
    return _err_roc("stats_ml: score and label vectors must have equal length");
  }
  if n <= 0 {
    return _err_roc("stats_ml: score and label vectors must not be empty");
  }
  var p: Int = 0;
  var q: Int = 0;
  var i = 0;
  while i < n {
    let y: Int = labels[i];
    if y == 1 {
      p = p + 1;
    } else {
      if y == 0 {
        q = q + 1;
      } else {
        return _err_roc("stats_ml: labels must be 0 or 1");
      }
    }
    i = i + 1;
  }
  if p <= 0 {
    return _err_roc("stats_ml: roc requires at least one positive label");
  }
  if q <= 0 {
    return _err_roc("stats_ml: roc requires at least one negative label");
  }
  var th = Vec[Int].new();
  i = 0;
  while i < n {
    let sc: Int = scores[i];
    _insert_unique_sorted_desc(&mut th, sc);
    i = i + 1;
  }
  var fprs = Vec[Int].new();
  var tprs = Vec[Int].new();
  var tps = Vec[Int].new();
  var fps = Vec[Int].new();
  i = 0;
  while i < th.len() {
    let t: Int = th[i];
    var tp: Int = 0;
    var fp: Int = 0;
    var j = 0;
    while j < n {
      let sc: Int = scores[j];
      if sc >= t {
        let y: Int = labels[j];
        if y == 1 {
          tp = tp + 1;
        } else {
          fp = fp + 1;
        }
      }
      j = j + 1;
    }
    tps.push(tp);
    fps.push(fp);
    tprs.push(_div_round(tp * _ML_BPS, p));
    fprs.push(_div_round(fp * _ML_BPS, q));
    i = i + 1;
  }
  var area2: Int = 0;
  var prev_fpr: Int = 0;
  var prev_tpr: Int = 0;
  i = 0;
  while i < th.len() {
    let f: Int = fprs[i];
    let tr: Int = tprs[i];
    let dfpr = f - prev_fpr;
    let sumtpr = tr + prev_tpr;
    area2 = area2 + dfpr * sumtpr;
    prev_fpr = f;
    prev_tpr = tr;
    i = i + 1;
  }
  let last_fpr = _ML_BPS - prev_fpr;
  let last_tpr = _ML_BPS + prev_tpr;
  area2 = area2 + last_fpr * last_tpr;
  let auc = _div_round(area2, 20000);
  return _ok_roc(RocCurve{ thresholds: th; fpr_bps: fprs; tpr_bps: tprs; tp: tps; fp: fps; positives: p; negatives: q; auc_bps: auc; n_points: th.len(); });
}

/// Number of ROC points (distinct scores). Complexity: O(1).
pub fn stats_ml_roc_n_points(curve: &RocCurve) -> Int {
  return curve.n_points;
}

/// Positive-class sample count. Complexity: O(1).
pub fn stats_ml_roc_positives(curve: &RocCurve) -> Int {
  return curve.positives;
}

/// Negative-class sample count. Complexity: O(1).
pub fn stats_ml_roc_negatives(curve: &RocCurve) -> Int {
  return curve.negatives;
}

/// Trapezoid AUC in basis points (10000 = perfect). Complexity: O(1).
pub fn stats_ml_roc_auc_bps(curve: &RocCurve) -> Int {
  return curve.auc_bps;
}

/// Score threshold of point `k`, or 0 when out of range. Complexity: O(1).
pub fn stats_ml_roc_threshold(curve: &RocCurve, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= curve.thresholds.len() {
    return 0;
  }
  let v: Int = curve.thresholds[k];
  return v;
}

/// FPR of point `k` in basis points, or 0 when out of range. Complexity: O(1).
pub fn stats_ml_roc_fpr_bps(curve: &RocCurve, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= curve.fpr_bps.len() {
    return 0;
  }
  let v: Int = curve.fpr_bps[k];
  return v;
}

/// TPR of point `k` in basis points, or 0 when out of range. Complexity: O(1).
pub fn stats_ml_roc_tpr_bps(curve: &RocCurve, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= curve.tpr_bps.len() {
    return 0;
  }
  let v: Int = curve.tpr_bps[k];
  return v;
}

/// Cumulative true positives at point `k`, or 0 when out of range.
/// Complexity: O(1).
pub fn stats_ml_roc_tp(curve: &RocCurve, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= curve.tp.len() {
    return 0;
  }
  let v: Int = curve.tp[k];
  return v;
}

/// Cumulative false positives at point `k`, or 0 when out of range.
/// Complexity: O(1).
pub fn stats_ml_roc_fp(curve: &RocCurve, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= curve.fp.len() {
    return 0;
  }
  let v: Int = curve.fp[k];
  return v;
}

// ---------------------------------------------------------------------------
// Calibration bins
// ---------------------------------------------------------------------------

/// Bin index of a basis-point `score` in [0, 10000] over `n_bins` equal-width
/// bins, or -1 when `score`/`n_bins` is out of range. Bin j covers
/// [j*10000/n_bins, (j+1)*10000/n_bins); the score 10000 is clamped into the
/// last bin. Complexity: O(1).
pub fn stats_ml_bin_index(score: Int, n_bins: Int) -> Int {
  if n_bins <= 0 {
    return -1;
  }
  if n_bins > _ML_BPS {
    return -1;
  }
  if score < 0 {
    return -1;
  }
  if score > _ML_BPS {
    return -1;
  }
  var j = score * n_bins / _ML_BPS;
  if j >= n_bins {
    j = n_bins - 1;
  }
  return j;
}

/// Histogram of integer scores in [0, 10000] into `n_bins` equal-width bins.
///
/// Params: scores - predicted probabilities in basis points; labels - 0/1,
///         same length, not empty; n_bins - in [1, 10000].
/// Returns: Ok(CalibrationBins) with, per bin, the count, positive count, raw
/// score sum, rounded mean score and rounded empirical positive rate
/// (10000 * positives / count; 0 for an empty bin).
/// Error case: Err("stats_ml: ...") for a bad bin count, a length mismatch, an
/// empty input, a score outside [0, 10000] or a label other than 0/1.
/// Complexity: O(n + n_bins).
pub fn stats_ml_calibration_bins(scores: &Vec[Int], labels: &Vec[Int], n_bins: Int) -> Result[CalibrationBins, Str] {
  if n_bins <= 0 {
    return _err_bins("stats_ml: bin count must be positive");
  }
  if n_bins > _ML_BPS {
    return _err_bins("stats_ml: bin count must not exceed 10000");
  }
  let n = scores.len();
  if labels.len() != n {
    return _err_bins("stats_ml: score and label vectors must have equal length");
  }
  if n <= 0 {
    return _err_bins("stats_ml: score and label vectors must not be empty");
  }
  var counts = Vec[Int].new();
  var positives = Vec[Int].new();
  var sums = Vec[Int].new();
  var z = 0;
  while z < n_bins {
    counts.push(0);
    positives.push(0);
    sums.push(0);
    z = z + 1;
  }
  var i = 0;
  while i < n {
    let sc: Int = scores[i];
    if sc < 0 {
      return _err_bins("stats_ml: scores must be in [0, 10000]");
    }
    if sc > _ML_BPS {
      return _err_bins("stats_ml: scores must be in [0, 10000]");
    }
    let y: Int = labels[i];
    if y != 0 {
      if y != 1 {
        return _err_bins("stats_ml: labels must be 0 or 1");
      }
    }
    let j = stats_ml_bin_index(sc, n_bins);
    let c: Int = counts[j];
    counts[j] = c + 1;
    if y == 1 {
      let pc: Int = positives[j];
      positives[j] = pc + 1;
    }
    let sm: Int = sums[j];
    sums[j] = sm + sc;
    i = i + 1;
  }
  var means = Vec[Int].new();
  var rates = Vec[Int].new();
  var b = 0;
  while b < n_bins {
    let c: Int = counts[b];
    let pc: Int = positives[b];
    let sm: Int = sums[b];
    if c <= 0 {
      means.push(0);
      rates.push(0);
    } else {
      means.push(_div_round(sm, c));
      rates.push(_div_round(pc * _ML_BPS, c));
    }
    b = b + 1;
  }
  return _ok_bins(CalibrationBins{ n_bins: n_bins; counts: counts; positives: positives; score_sum: sums; mean_score_bps: means; positive_rate_bps: rates; });
}

/// Number of calibration bins. Complexity: O(1).
pub fn stats_ml_bins_count(bins: &CalibrationBins) -> Int {
  return bins.n_bins;
}

/// Sample count in bin `j`, or 0 when out of range. Complexity: O(1).
pub fn stats_ml_bin_count(bins: &CalibrationBins, j: Int) -> Int {
  if j < 0 {
    return 0;
  }
  if j >= bins.counts.len() {
    return 0;
  }
  let v: Int = bins.counts[j];
  return v;
}

/// Positive count in bin `j`, or 0 when out of range. Complexity: O(1).
pub fn stats_ml_bin_positives(bins: &CalibrationBins, j: Int) -> Int {
  if j < 0 {
    return 0;
  }
  if j >= bins.positives.len() {
    return 0;
  }
  let v: Int = bins.positives[j];
  return v;
}

/// Mean score of bin `j` in basis points, or 0 when out of range (an empty
/// in-range bin also reports 0). Complexity: O(1).
pub fn stats_ml_bin_mean_score_bps(bins: &CalibrationBins, j: Int) -> Int {
  if j < 0 {
    return 0;
  }
  if j >= bins.mean_score_bps.len() {
    return 0;
  }
  let v: Int = bins.mean_score_bps[j];
  return v;
}

/// Empirical positive rate of bin `j` in basis points, or 0 when out of range
/// (an empty in-range bin also reports 0). Complexity: O(1).
pub fn stats_ml_bin_positive_rate_bps(bins: &CalibrationBins, j: Int) -> Int {
  if j < 0 {
    return 0;
  }
  if j >= bins.positive_rate_bps.len() {
    return 0;
  }
  let v: Int = bins.positive_rate_bps[j];
  return v;
}

/// Expected calibration error in basis points:
/// round_half_away(sum_j count_j * |positive_rate_j - mean_score_j| / total),
/// on the rounded per-bin basis-point values. 0 for an empty histogram.
/// Complexity: O(n_bins).
pub fn stats_ml_calibration_ece_bps(bins: &CalibrationBins) -> Int {
  var total: Int = 0;
  var acc: Int = 0;
  var j = 0;
  while j < bins.n_bins {
    let c: Int = bins.counts[j];
    let r: Int = bins.positive_rate_bps[j];
    let m: Int = bins.mean_score_bps[j];
    var d = r - m;
    if d < 0 {
      d = 0 - d;
    }
    total = total + c;
    acc = acc + c * d;
    j = j + 1;
  }
  if total <= 0 {
    return 0;
  }
  return _div_round(acc, total);
}

// ---------------------------------------------------------------------------
// Class balance
// ---------------------------------------------------------------------------

/// Class-balance summary of a label vector.
///
/// Params: labels - class labels, not empty.
/// Returns: Ok(ClassBalance) with first-occurrence classes and counts,
/// `majority`/`minority` counts and `ratio_bps` =
/// round_half_away(10000 * minority / majority).
/// Error case: Err("stats_ml: labels must not be empty") for an empty input.
/// Complexity: O(n * k).
pub fn stats_ml_class_balance(labels: &Vec[Str]) -> Result[ClassBalance, Str] {
  let n = labels.len();
  if n <= 0 {
    return _err_bal("stats_ml: labels must not be empty");
  }
  var classes = Vec[Str].new();
  var counts = Vec[Int].new();
  var i = 0;
  while i < n {
    let lab: Str = labels[i];
    let idx = _class_find(&classes, lab);
    if idx < 0 {
      classes.push(lab);
      counts.push(1);
    } else {
      let c: Int = counts[idx];
      counts[idx] = c + 1;
    }
    i = i + 1;
  }
  let k = classes.len();
  var mx: Int = 0;
  var mn: Int = 0;
  let first: Int = counts[0];
  mx = first;
  mn = first;
  var t = 1;
  while t < k {
    let c: Int = counts[t];
    if c > mx {
      mx = c;
    }
    if c < mn {
      mn = c;
    }
    t = t + 1;
  }
  let ratio = _div_round(mn * _ML_BPS, mx);
  return _ok_bal(ClassBalance{ classes: classes; counts: counts; total: n; k: k; majority: mx; minority: mn; ratio_bps: ratio; });
}

/// Number of distinct classes. Complexity: O(1).
pub fn stats_ml_balance_k(bal: &ClassBalance) -> Int {
  return bal.k;
}

/// Number of samples. Complexity: O(1).
pub fn stats_ml_balance_total(bal: &ClassBalance) -> Int {
  return bal.total;
}

/// Majority (largest) per-class count. Complexity: O(1).
pub fn stats_ml_balance_majority(bal: &ClassBalance) -> Int {
  return bal.majority;
}

/// Minority (smallest) per-class count. Complexity: O(1).
pub fn stats_ml_balance_minority(bal: &ClassBalance) -> Int {
  return bal.minority;
}

/// Minority/majority ratio in basis points (10000 = perfectly balanced).
/// Complexity: O(1).
pub fn stats_ml_balance_ratio_bps(bal: &ClassBalance) -> Int {
  return bal.ratio_bps;
}

/// Class label at index `i`, or "" when out of range. Complexity: O(1).
pub fn stats_ml_balance_class(bal: &ClassBalance, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= bal.classes.len() {
    return "";
  }
  let s: Str = bal.classes[i];
  return s;
}

/// Count of the class at index `i`, or 0 when out of range. Complexity: O(1).
pub fn stats_ml_balance_count(bal: &ClassBalance, i: Int) -> Int {
  if i < 0 {
    return 0;
  }
  if i >= bal.counts.len() {
    return 0;
  }
  let v: Int = bal.counts[i];
  return v;
}

// ---------------------------------------------------------------------------
// Classification report
// ---------------------------------------------------------------------------

/// Render a deterministic ASCII classification report for a confusion matrix.
///
/// Format (one line per class, all metrics in basis points):
///   line 1: "xiom.stats_ml classification report"
///   line 2: "classes=<k> samples=<n> accuracy_bps=<a> kappa_bps=<x>"
///   then:   "class[<i>] \"<label>\" support=<s> precision_bps=<p>
///            recall_bps=<r> f1_bps=<f>"
///   last:   "macro precision_bps=<p> recall_bps=<r> f1_bps=<f>"
/// kappa_bps in the header is 0 when the kappa guard reports an error.
/// Complexity: O(k^2).
pub fn stats_ml_classification_report(cm: &ConfusionMatrix) -> Str {
  var out: Str = "xiom.stats_ml classification report";
  out = out + "\nclasses=" + convert.int_to_string(cm.k);
  out = out + " samples=" + convert.int_to_string(cm.total);
  out = out + " accuracy_bps=" + convert.int_to_string(stats_ml_accuracy_bps(cm));
  out = out + " kappa_bps=" + convert.int_to_string(_kappa_value(cm));
  var i = 0;
  while i < cm.k {
    let lab: Str = cm.classes[i];
    out = out + "\nclass[" + convert.int_to_string(i) + "] \"" + lab + "\"";
    out = out + " support=" + convert.int_to_string(_cm_row_sum(cm, i));
    out = out + " precision_bps=" + convert.int_to_string(stats_ml_precision_bps(cm, i));
    out = out + " recall_bps=" + convert.int_to_string(stats_ml_recall_bps(cm, i));
    out = out + " f1_bps=" + convert.int_to_string(stats_ml_f1_bps(cm, i));
    i = i + 1;
  }
  out = out + "\nmacro precision_bps=" + convert.int_to_string(stats_ml_macro_precision_bps(cm));
  out = out + " recall_bps=" + convert.int_to_string(stats_ml_macro_recall_bps(cm));
  out = out + " f1_bps=" + convert.int_to_string(stats_ml_macro_f1_bps(cm));
  return out;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Truncating division with halves rounded away from zero (b > 0). The
// doubled remainder cannot overflow for the denominators used here: counts
// (<= sample count), class counts, N^2 and 20000; see SPEC.md.
fn _div_round(a: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  var mag = r;
  if mag < 0 {
    mag = 0 - mag;
  }
  if mag * 2 >= b {
    if a < 0 {
      return q - 1;
    }
    return q + 1;
  }
  return q;
}

// First-occurrence index of `label` in `classes`, or -1. Comparisons go
// through string.str_compare with both operands bound to typed locals.
fn _class_find(classes: &Vec[Str], label: Str) -> Int {
  var i = 0;
  while i < classes.len() {
    let known: Str = classes[i];
    if string.str_compare(known, label) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True positives of class i (diagonal cell), 0 when i is out of range.
fn _cm_tp(cm: &ConfusionMatrix, i: Int) -> Int {
  if i < 0 {
    return 0;
  }
  if i >= cm.k {
    return 0;
  }
  let v: Int = cm.counts[i * cm.k + i];
  return v;
}

// Row sum (support) of class i, 0 when i is out of range.
fn _cm_row_sum(cm: &ConfusionMatrix, i: Int) -> Int {
  if i < 0 {
    return 0;
  }
  if i >= cm.k {
    return 0;
  }
  var s: Int = 0;
  var j = 0;
  while j < cm.k {
    let v: Int = cm.counts[i * cm.k + j];
    s = s + v;
    j = j + 1;
  }
  return s;
}

// Column sum (predicted count) of class j, 0 when j is out of range.
fn _cm_col_sum(cm: &ConfusionMatrix, j: Int) -> Int {
  if j < 0 {
    return 0;
  }
  if j >= cm.k {
    return 0;
  }
  var s: Int = 0;
  var i = 0;
  while i < cm.k {
    let v: Int = cm.counts[i * cm.k + j];
    s = s + v;
    i = i + 1;
  }
  return s;
}

// Insert x into v keeping v strictly descending and unique (v is small: one
// entry per distinct score). Mutates v through an explicit &mut at the call
// site. Complexity: O(d) per insert.
fn _insert_unique_sorted_desc(v: &mut Vec[Int], x: Int) {
  var i = 0;
  while i < v.len() {
    let cur: Int = v[i];
    if cur == x {
      return;
    }
    if cur < x {
      v.insert(i, x);
      return;
    }
    i = i + 1;
  }
  v.push(x);
}

// Kappa as a plain Int for the report renderer: 0 when the guarded public
// function reports an error.
fn _kappa_value(cm: &ConfusionMatrix) -> Int {
  let r = stats_ml_kappa_bps(cm);
  match r {
    Ok(v) => { return v; },
    Err(_) => { return 0; },
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_cm(v: ConfusionMatrix) -> Result[ConfusionMatrix, Str] {
  return Ok(v);
}

fn _err_cm(msg: Str) -> Result[ConfusionMatrix, Str] {
  return Err(msg);
}

fn _ok_bal(v: ClassBalance) -> Result[ClassBalance, Str] {
  return Ok(v);
}

fn _err_bal(msg: Str) -> Result[ClassBalance, Str] {
  return Err(msg);
}

fn _ok_roc(v: RocCurve) -> Result[RocCurve, Str] {
  return Ok(v);
}

fn _err_roc(msg: Str) -> Result[RocCurve, Str] {
  return Err(msg);
}

fn _ok_bins(v: CalibrationBins) -> Result[CalibrationBins, Str] {
  return Ok(v);
}

fn _err_bins(msg: Str) -> Result[CalibrationBins, Str] {
  return Err(msg);
}

fn _ok_int(x: Int) -> Result[Int, Str] {
  return Ok(x);
}

fn _err_int(msg: Str) -> Result[Int, Str] {
  return Err(msg);
}
