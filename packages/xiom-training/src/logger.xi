// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.training.logger: training metric log
// Part of the xiom.training package.
//
// A metric log is two parallel Vec[Int] vectors (steps and losses) fed by a
// single push site, so a log built through tlog_record cannot drift.
// tlog_record threads state through its return: the input log is never
// modified, which makes call sites explicit and audit-friendly at the
// conformance/metric-logging scale this library targets.

module xiom.training.logger

use xiom.training;
use xiom.convert;

/// A training metric log: parallel step and loss vectors.
pub type TrainLog = {
  steps: Vec[Int];
  losses: Vec[Int];
}

fn _tlog_make(steps: Vec[Int], losses: Vec[Int]) -> TrainLog {
  return TrainLog{ steps: steps; losses: losses; };
}

fn _tlog_push(l: &mut TrainLog, step: Int, loss: Int) {
  l.steps.push(step);
  l.losses.push(loss);
}

/// A fresh empty log. Complexity: O(1).
pub fn tlog_new() -> TrainLog {
  return _tlog_make(Vec[Int].new(), Vec[Int].new());
}

/// Append one (step, loss) row, returning a new log: the input log is not
/// modified. When the input has drifted (vectors of different length), only
/// the paired prefix is copied, so the result is always consistent.
/// Params: l - the log to extend; step, loss - the row to append.
/// Returns: the extended log. Complexity: O(l.steps.len()).
pub fn tlog_record(l: &TrainLog, step: Int, loss: Int) -> TrainLog {
  var out = tlog_new();
  var n = l.steps.len();
  if l.losses.len() < n {
    n = l.losses.len();
  }
  var i = 0;
  while i < n {
    let sv: Int = l.steps[i];
    let lv: Int = l.losses[i];
    _tlog_push(&mut out, sv, lv);
    i = i + 1;
  }
  _tlog_push(&mut out, step, loss);
  return out;
}

/// Number of rows. Complexity: O(1).
pub fn tlog_len(l: &TrainLog) -> Int {
  return l.steps.len();
}

/// True when the parallel vectors have equal length. Complexity: O(1).
pub fn tlog_is_consistent(l: &TrainLog) -> Bool {
  return l.steps.len() == l.losses.len();
}

/// Step of row i, or TRAIN_NONE when out of range. Complexity: O(1).
pub fn tlog_step(l: &TrainLog, i: Int) -> Int {
  if i < 0 || i >= l.steps.len() {
    return TRAIN_NONE;
  }
  let v: Int = l.steps[i];
  return v;
}

/// Loss of row i, or TRAIN_NONE when out of range. Complexity: O(1).
pub fn tlog_loss(l: &TrainLog, i: Int) -> Int {
  if i < 0 || i >= l.losses.len() {
    return TRAIN_NONE;
  }
  let v: Int = l.losses[i];
  return v;
}

/// Loss of the last row, or TRAIN_NONE when empty. Complexity: O(1).
pub fn tlog_last_loss(l: &TrainLog) -> Int {
  let n = tlog_len(l);
  if n == 0 {
    return TRAIN_NONE;
  }
  return tlog_loss(l, n - 1);
}

/// Smallest loss, or TRAIN_NONE when empty or drifted. Ties keep the first
/// (earliest) row. Complexity: O(n).
pub fn tlog_min_loss(l: &TrainLog) -> Int {
  if !tlog_is_consistent(l) {
    return TRAIN_NONE;
  }
  let n = l.losses.len();
  if n == 0 {
    return TRAIN_NONE;
  }
  let first: Int = l.losses[0];
  var best = first;
  var i = 1;
  while i < n {
    let v: Int = l.losses[i];
    if v < best {
      best = v;
    }
    i = i + 1;
  }
  return best;
}

/// Step of the first minimal loss, or TRAIN_NONE when empty or drifted.
/// Complexity: O(n).
pub fn tlog_best_step(l: &TrainLog) -> Int {
  if !tlog_is_consistent(l) {
    return TRAIN_NONE;
  }
  let n = l.losses.len();
  if n == 0 {
    return TRAIN_NONE;
  }
  let first: Int = l.losses[0];
  var best = first;
  var bi = 0;
  var i = 1;
  while i < n {
    let v: Int = l.losses[i];
    if v < best {
      best = v;
      bi = i;
    }
    i = i + 1;
  }
  return tlog_step(l, bi);
}

/// Mean loss rounded to nearest with ties away from zero, or TRAIN_NONE when
/// empty, drifted, an entry exceeds +-100000000, or the sum would overflow.
/// Complexity: O(n).
pub fn tlog_mean_loss(l: &TrainLog) -> Int {
  if !tlog_is_consistent(l) {
    return TRAIN_NONE;
  }
  let n = l.losses.len();
  if n == 0 {
    return TRAIN_NONE;
  }
  var total: Int = 0;
  var i = 0;
  while i < n {
    let v: Int = l.losses[i];
    let mag = _tr_abs(v);
    if mag > _TR_MAX_GRAD {
      return TRAIN_NONE;
    }
    if total > _TR_INT_HI - mag {
      return TRAIN_NONE;
    }
    total = total + v;
    i = i + 1;
  }
  return _tr_div_round(total, n);
}

/// One-line summary: "n=<rows> last=<last> mean=<mean> best_step=<step>";
/// "n=0 last=none mean=none best_step=none" for an empty log and "drift" for
/// an inconsistent one. Complexity: O(n).
pub fn tlog_summary(l: &TrainLog) -> Str {
  if !tlog_is_consistent(l) {
    return "drift";
  }
  let n = tlog_len(l);
  if n == 0 {
    return "n=0 last=none mean=none best_step=none";
  }
  return "n=" + int_to_string(n) + " last=" + int_to_string(tlog_last_loss(l)) + " mean=" + int_to_string(tlog_mean_loss(l)) + " best_step=" + int_to_string(tlog_best_step(l));
}
