// XIOM -- xiom.jev.selection: deterministic selection over typed answers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The probabilistic-selection core of the System One tier: pick from, or
// gate on, a probability distribution without any hidden randomness.
//
// Rules (pinned; see SPEC.md section 7):
//
//   * argmax -- the index of the maximum micro value; ties resolve to the
//     lowest index (wire/criterion order). All-zero or empty -> -1 (count 0)
//     / index 0 for an all-zero vector with count >= 1.
//   * threshold -- inclusive (micro >= threshold), labels returned in
//     criterion order.
//   * sample -- caller-supplied entropy: the package NEVER draws entropy
//     itself. u = ((entropy % total) + total) % total (Euclidean modulo, so
//     any Int -- including negative -- maps deterministically into
//     [0, total)); option j owns the half-open interval
//     [cum_before_j, cum_before_j + micro_j); an exact boundary selects the
//     later option; zero-probability options are never selected. total <= 0
//     or no probabilities -> -1. Same entropy + same distribution -> same
//     choice, on every run and platform.
//   * score rounding -- round to the nearest level, halves away from zero
//     (equivalently, half-up for the non-negative score domain);
//     normalization divides by the top level number with the same half-up
//     rounding, so a score on the 0..1 scale keeps six decimal digits.
//   * noul gating -- noul_yes is inclusive at the threshold; the
//     confidence-style spread of a noul is |2p - 1|.

module xiom.jev.selection

use xiom.jev.types;
use xiom.string.compare;

// --------------------------------------------------
//  Probability selection
// --------------------------------------------------

/// answer_argmax is the index of answer i's maximum probability entry, ties
/// to the lowest index; -1 when the answer has no probabilities.
/// Complexity: O(n). Pure.
pub fn answer_argmax(r: &Response, i: Int) -> Int {
  let n: Int = types.response_prob_count(r, i);
  if n <= 0 { return -1; }
  var best: Int = 0;
  var best_m: Int = types.response_prob_micro(r, i, 0);
  var j: Int = 1;
  while j < n {
    let m: Int = types.response_prob_micro(r, i, j);
    if m > best_m {
      best_m = m;
      best = j;
    }
    j = j + 1;
  }
  return best;
}

/// answer_argmax_label is the label of answer i's argmax entry ("" when the
/// answer has no probabilities). Complexity: O(n). Pure.
pub fn answer_argmax_label(r: &Response, i: Int) -> Str {
  let j: Int = answer_argmax(r, i);
  if j < 0 { return ""; }
  return types.response_prob_label(r, i, j);
}

/// answer_max_micro is answer i's maximum micro value (-1 when the answer
/// has no probabilities). Complexity: O(n). Pure.
pub fn answer_max_micro(r: &Response, i: Int) -> Int {
  let n: Int = types.response_prob_count(r, i);
  if n <= 0 { return -1; }
  var best_m: Int = types.response_prob_micro(r, i, 0);
  var j: Int = 1;
  while j < n {
    let m: Int = types.response_prob_micro(r, i, j);
    if m > best_m { best_m = m; }
    j = j + 1;
  }
  return best_m;
}

/// answer_count_at_or_above counts answer i's entries with micro >=
/// threshold_micro. Complexity: O(n). Pure.
pub fn answer_count_at_or_above(r: &Response, i: Int, threshold_micro: Int) -> Int {
  let n: Int = types.response_prob_count(r, i);
  var c: Int = 0;
  var j: Int = 0;
  while j < n {
    let m: Int = types.response_prob_micro(r, i, j);
    if m >= threshold_micro { c = c + 1; }
    j = j + 1;
  }
  return c;
}

/// answer_labels_at_or_above returns answer i's labels with micro >=
/// threshold_micro, in criterion order. Complexity: O(n). Pure.
pub fn answer_labels_at_or_above(r: &Response, i: Int, threshold_micro: Int) -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  let n: Int = types.response_prob_count(r, i);
  var j: Int = 0;
  while j < n {
    let m: Int = types.response_prob_micro(r, i, j);
    if m >= threshold_micro {
      let l: Str = types.response_prob_label(r, i, j);
      out.push(l);
    }
    j = j + 1;
  }
  return out;
}

/// answer_sample_index samples answer i's distribution from caller-supplied
/// `entropy` (any Int; see the module header for the exact interval rules).
/// Complexity: O(n). Pure.
pub fn answer_sample_index(r: &Response, i: Int, entropy: Int) -> Int {
  let n: Int = types.response_prob_count(r, i);
  if n <= 0 { return -1; }
  var total: Int = 0;
  var j: Int = 0;
  while j < n {
    total = total + types.response_prob_micro(r, i, j);
    j = j + 1;
  }
  if total <= 0 { return -1; }
  var u: Int = entropy % total;
  if u < 0 { u = u + total; }
  var cum: Int = 0;
  j = 0;
  while j < n {
    cum = cum + types.response_prob_micro(r, i, j);
    if u < cum { return j; }
    j = j + 1;
  }
  return n - 1;
}

/// answer_sample_label is the label sampled from answer i's distribution
/// with caller-supplied entropy ("" when no selection is possible).
/// Complexity: O(n). Pure.
pub fn answer_sample_label(r: &Response, i: Int, entropy: Int) -> Str {
  let j: Int = answer_sample_index(r, i, entropy);
  if j < 0 { return ""; }
  return types.response_prob_label(r, i, j);
}

/// choice_answer_covers_question is the fail-closed cross-check between a
/// choice answer and the question it answers: 1 when answer i is a choice
/// answer, q is a choice question, and the probability labels and the
/// question's option labels are the same set (same size; every label
/// found); 0 otherwise. Score questions and noul answers return 0 (noul
/// carries no distribution; scores are checked by key subset at parse time).
/// Complexity: O(n^2). Pure.
pub fn choice_answer_covers_question(r: &Response, i: Int, q: &Question) -> Int {
  if types.response_kind(r, i) != types.KIND_CHOICE { return 0; }
  let qk: Int = q.kind;
  if qk != types.KIND_CHOICE { return 0; }
  let labels: Vec[Str] = q.labels;
  let n: Int = types.response_prob_count(r, i);
  if labels.len() != n { return 0; }
  var j: Int = 0;
  while j < n {
    let want: Str = types.response_prob_label(r, i, j);
    var found: Bool = false;
    var k: Int = 0;
    while k < labels.len() {
      let have: Str = labels[k];
      if compare.str_compare(have, want) == 0 {
        found = true;
        break;
      }
      k = k + 1;
    }
    if !found { return 0; }
    j = j + 1;
  }
  return 1;
}

// --------------------------------------------------
//  Score and noul helpers
// --------------------------------------------------

/// score_round_level rounds a score given in micro units to the nearest
/// rubric level (halves away from zero). Complexity: O(1). Pure.
pub fn score_round_level(score_micro: Int) -> Int {
  if score_micro <= 0 { return 0; }
  return (score_micro + 500000) / 1000000;
}

/// score_normalized_micro puts score_micro on the 0..1000000 scale by
/// dividing by `top_level` (the highest level number, len(criteria) - 1),
/// rounding halves away from zero. Returns 0 when top_level <= 0.
/// Complexity: O(1). Pure.
pub fn score_normalized_micro(score_micro: Int, top_level: Int) -> Int {
  if score_micro <= 0 { return 0; }
  if top_level <= 0 { return 0; }
  let q: Int = score_micro / top_level;
  let rem: Int = score_micro % top_level;
  if rem * 2 >= top_level { return q + 1; }
  return q;
}

/// noul_yes gates a noul value with an inclusive threshold: 1 when
/// noul_micro >= threshold_micro, else 0. Complexity: O(1). Pure.
pub fn noul_yes(noul_micro: Int, threshold_micro: Int) -> Int {
  if noul_micro >= threshold_micro { return 1; }
  return 0;
}

/// noul_confidence_micro is the confidence-style spread of a noul value:
/// |2p - 1| in micro units (0 at p = 0.5, 1000000 at p = 0 or 1).
/// Complexity: O(1). Pure.
pub fn noul_confidence_micro(noul_micro: Int) -> Int {
  let d: Int = 2 * noul_micro - 1000000;
  if d < 0 { return -d; }
  return d;
}
