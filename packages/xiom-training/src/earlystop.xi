// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.training.earlystop: patience-based early stopping
// Part of the xiom.training package.
//
// Min-mode (lower is better) and max-mode (higher is better) early stopping
// with a strict minimum delta. The state is a plain record threaded through
// returns: es_update consumes a state and produces the next one. Stopping
// fires once the number of consecutive non-improving updates reaches
// patience.

module xiom.training.earlystop

use xiom.training;

/// Early-stopping state: the best metric seen, the number of consecutive
/// non-improving updates, the configured patience and minimum delta, the
/// comparison mode and the stop flag.
pub type EsState = {
  best: Int;
  bad: Int;
  patience: Int;
  min_delta: Int;
  mode: Int;
  stopped: Bool;
}

fn _es_make(best: Int, bad: Int, patience: Int, min_delta: Int, mode: Int, stopped: Bool) -> EsState {
  return EsState{ best: best; bad: bad; patience: patience; min_delta: min_delta; mode: mode; stopped: stopped; };
}

fn _ok_es(s: EsState) -> Result[EsState, Str] {
  return Ok(s);
}

fn _err_es(m: Str) -> Result[EsState, Str] {
  return Err(m);
}

fn _es_validate(patience: Int, min_delta: Int, mode: Int) -> Str {
  if mode != ES_MODE_MIN && mode != ES_MODE_MAX {
    return "training: early-stop mode must be ES_MODE_MIN or ES_MODE_MAX";
  }
  if patience < 1 {
    return "training: early-stop patience must be >= 1";
  }
  if min_delta < 0 {
    return "training: early-stop min_delta must be non-negative";
  }
  if min_delta > _TR_MAX_COORD {
    return "training: early-stop min_delta exceeds the supported envelope";
  }
  return "";
}

fn _es_new(best: Int, patience: Int, min_delta: Int, mode: Int) -> Result[EsState, Str] {
  let err = _es_validate(patience, min_delta, mode);
  if err.len() != 0 {
    return _err_es(err);
  }
  return _ok_es(_es_make(best, 0, patience, min_delta, mode, false));
}

/// New min-mode state (lower metric is better).
/// Params: best - initial best metric; patience - non-improving updates
///         tolerated, >= 1; min_delta - strict improvement margin, >= 0.
/// Returns: Ok(state). Error case: Err("training: ...") for patience < 1 or
/// min_delta outside [0, 1000000]. Complexity: O(1).
pub fn es_new_min(best: Int, patience: Int, min_delta: Int) -> Result[EsState, Str] {
  return _es_new(best, patience, min_delta, ES_MODE_MIN);
}

/// New max-mode state (higher metric is better). Params as es_new_min.
pub fn es_new_max(best: Int, patience: Int, min_delta: Int) -> Result[EsState, Str] {
  return _es_new(best, patience, min_delta, ES_MODE_MAX);
}

/// Best metric of the state. Complexity: O(1).
pub fn es_best(s: &EsState) -> Int {
  return s.best;
}

/// Consecutive non-improving updates of the state. Complexity: O(1).
pub fn es_bad(s: &EsState) -> Int {
  return s.bad;
}

/// Configured patience. Complexity: O(1).
pub fn es_patience(s: &EsState) -> Int {
  return s.patience;
}

/// Configured minimum delta. Complexity: O(1).
pub fn es_min_delta(s: &EsState) -> Int {
  return s.min_delta;
}

/// Comparison mode (ES_MODE_MIN or ES_MODE_MAX). Complexity: O(1).
pub fn es_mode(s: &EsState) -> Int {
  return s.mode;
}

/// Whether the state has stopped. Complexity: O(1).
pub fn es_stopped(s: &EsState) -> Bool {
  return s.stopped;
}

/// Strict improvement test: min mode is metric < best - min_delta, max mode
/// is metric > best + min_delta. Complexity: O(1).
pub fn es_is_improvement(s: &EsState, metric: Int) -> Bool {
  if s.mode == ES_MODE_MIN {
    return metric < s.best - s.min_delta;
  }
  return metric > s.best + s.min_delta;
}

/// Apply one metric to the state.
/// Params: s - current state (returned unchanged once stopped); metric - the
///         new metric.
/// Returns: the updated state: on improvement the best metric and a zero bad
/// counter; otherwise bad + 1, with stopped set once bad reaches patience.
/// Error case: none (states come from es_new_min/es_new_max).
/// Complexity: O(1).
pub fn es_update(s: EsState, metric: Int) -> EsState {
  if s.stopped {
    return s;
  }
  if es_is_improvement(&s, metric) {
    return _es_make(metric, 0, s.patience, s.min_delta, s.mode, false);
  }
  let nb = s.bad + 1;
  if nb >= s.patience {
    return _es_make(s.best, nb, s.patience, s.min_delta, s.mode, true);
  }
  return _es_make(s.best, nb, s.patience, s.min_delta, s.mode, false);
}

/// Scan a metric trace from the first metric onward until patience is
/// exhausted; metrics after a stop are not consumed.
/// Params: metrics - non-empty metric trace; patience, min_delta, mode - as
///         for es_new_min/es_new_max.
/// Returns: Ok(the final state).
/// Error case: Err("training: ...") for an empty trace or invalid
/// configuration. Complexity: O(metrics.len()).
pub fn es_run(metrics: &Vec[Int], patience: Int, min_delta: Int, mode: Int) -> Result[EsState, Str] {
  let err = _es_validate(patience, min_delta, mode);
  if err.len() != 0 {
    return _err_es(err);
  }
  let n = metrics.len();
  if n == 0 {
    return _err_es("training: early-stop run needs at least one metric");
  }
  let m0: Int = metrics[0];
  var cur = _es_make(m0, 0, patience, min_delta, mode, false);
  var i = 1;
  while i < n && !cur.stopped {
    let v: Int = metrics[i];
    cur = es_update(cur, v);
    i = i + 1;
  }
  return _ok_es(cur);
}
