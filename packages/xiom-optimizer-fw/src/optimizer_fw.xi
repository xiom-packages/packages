// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.optimizer_fw: a deterministic optimization framework over
// caller-provided integer objective records.
//
// Scope: pure, IO-free single-variable integer search. There are no function
// pointers, no closures, no `Vec[StructType]` and no generic callbacks: an
// objective is an OPTIMIZER-FW RECORD -- a sample table built from a value
// vector plus a base and a stride (optfw_table_new) or an explicit value list
// built from parallel xs/vs vectors (optfw_list_new). Both constructors feed
// one push site (_obj_push), so the two parallel vectors cannot drift.
//
// Evaluation is nearest-sample and piecewise constant: optfw_eval(o, x) is
// the value of the sample whose position is closest to x, with ties keeping
// the earliest sample. On a table built with stride 1 this is an ordinary
// array lookup; on any other record it is the documented total extension to
// every integer x (so proposals that land between samples remain meaningful).
// An empty objective has no value: optfw_eval returns the reserved sentinel
// OPT_NONE.
//
// Four searches share the same objective and stopping records:
//   * optfw_grid_search       -- exhaustive (early-stoppable) stepped scan;
//   * optfw_hill_first/best   -- hill climbing with first / best improvement
//                                and integer step halving on a stall;
//   * optfw_anneal            -- simulated annealing with an LCG random
//                                stream and a fixed-point geometric cooling
//                                schedule (integer Metropolis acceptance);
//   * optfw_restart_search    -- deterministic random restarts of best-
//                                improvement hill climbing.
//
// Every search returns an OptResult (best point, best value, iterations
// consumed, stop reason, improvement flag) and has a `_trace` twin that also
// appends one (iteration, best-so-far value, current value) row per iteration
// to a caller-owned OptTrace -- three parallel `Vec[Int]` fields fed by one
// push site, so a trace cannot drift. Best-so-far updates use strict `>`:
// ties always keep the earliest best.
//
// Stopping rules (OptStop) are shared by every search:
//   * max_iters  -- hard iteration cap, clamped to >= 1, so every loop is
//                   bounded and the searches always terminate;
//   * no_improve -- stop after this many consecutive iterations without a
//                   strict best-value improvement (0 or negative disables
//                   the rule; a step halving counts as a non-improvement);
//   * floor      -- stop as soon as the best value reaches this floor
//                   (the sentinel OPT_NONE disables the rule).
// Rationale for the clamping: termination is guaranteed by construction --
// max_iters caps every loop, grid strides advance by a non-negative remainder
// check, hill step halving reaches 0, and annealing's LCG always advances.
//
// Language notes (XIOM v0.62.2): free functions only; no `self`, no lambdas,
// no `Vec[StructType]`, no `Result` values; every Int read from a Vec goes
// through a typed local; all arithmetic is the platform's 64-bit signed Int
// and wraps on overflow (hostile extreme bounds are the caller's
// responsibility, exactly as in xiom.optimizer).

module xiom.optimizer_fw

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Reserved "no value" sentinel (Int min + 1): returned by optfw_eval for an
/// empty objective and by the optfw_obj_v / optfw_trace_* accessors when the
/// index is out of range. Also the value that disables OptStop.floor.
/// Callers must not use it as a real objective value.
pub const OPT_NONE: Int = 0 - 0x7FFFFFFFFFFFFFFF;

/// Reason: no stop rule fired (used by optfw_reason_name only).
pub const OPT_REASON_NONE: Int = 0;

/// Reason: the max_iters cap was reached.
pub const OPT_REASON_MAX_ITERS: Int = 1;

/// Reason: the no-improvement window was exhausted.
pub const OPT_REASON_NO_IMPROVE: Int = 2;

/// Reason: the best value reached the value floor.
pub const OPT_REASON_FLOOR: Int = 3;

/// Reason: the search space or restart budget was consumed normally.
pub const OPT_REASON_EXHAUSTED: Int = 4;

/// Reason: hill climbing halved its step to 0 (a stall at step 1).
pub const OPT_REASON_STEP_ZERO: Int = 5;

/// Reason: degenerate input (empty objective or an empty range hi < lo);
/// no iteration was performed.
pub const OPT_REASON_EMPTY: Int = 6;

/// Iteration budget of each climb inside optfw_restart_search.
pub const OPT_RESTART_CLIMB_ITERS: Int = 64;

/// LCG multiplier of the framework's deterministic random stream.
pub const OPT_LCG_MUL: Int = 1103515245;

/// LCG increment of the framework's deterministic random stream.
pub const OPT_LCG_INC: Int = 12345;

/// LCG modulus mask: the stream state stays in [0, 2^31 - 1].
pub const OPT_LCG_MASK: Int = 0x7FFFFFFF;

/// Per-restart seed spread multiplier (Knuth's golden-ratio constant).
pub const OPT_SEED_SPREAD: Int = 2654435761;

// ---------------------------------------------------------------------------
// Records
// ---------------------------------------------------------------------------

/// An objective record: parallel sample positions and sample values. For a
/// sample table, xs[i] == base + i * stride; for an explicit value list, xs
/// is the caller's list. Values are compared with strict `>` (larger is
/// better; the framework maximizes).
pub type OptObjective = {
  xs: Vec[Int];
  vs: Vec[Int];
}

/// Shared stopping rules. max_iters is a hard cap clamped to >= 1 by
/// optfw_stop_new; no_improve <= 0 disables the window rule; floor ==
/// OPT_NONE disables the value-floor rule.
pub type OptStop = {
  max_iters: Int;
  no_improve: Int;
  floor: Int;
}

/// Simulated-annealing knobs: proposal radius step (clamped to >= 0), PRNG
/// seed, starting temperature (clamped to >= 1), and the fixed-point cooling
/// ratio cool_num / cool_den (cool_den clamped to >= 1, cool_num clamped
/// into [0, cool_den]).
pub type OptAnnealCfg = {
  step: Int;
  seed: Int;
  temp_start: Int;
  cool_num: Int;
  cool_den: Int;
}

/// Search outcome: the best point found (x), its value (value), the number of
/// iterations consumed (iters), the stop reason (one OPT_REASON_*), and
/// whether the best differs from the starting point.
pub type OptResult = {
  x: Int;
  value: Int;
  iters: Int;
  reason: Int;
  improved: Bool;
}

/// Convergence trace: three parallel Vec fields pushed together by
/// _trace_push. Row i records the 1-based iteration number, the best-so-far
/// value after that iteration, and the current value at its end.
pub type OptTrace = {
  iters: Vec[Int];
  bests: Vec[Int];
  currents: Vec[Int];
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Absolute value of v. Wraps on the extreme Int min value instead of trapping.
fn _optfw_abs(v: Int) -> Int {
  if v < 0 { return 0 - v; }
  return v;
}

// Clamp x into [lo, hi]. Callers must pass lo <= hi.
fn _optfw_clamp(x: Int, lo: Int, hi: Int) -> Int {
  if x < lo { return lo; }
  if x > hi { return hi; }
  return x;
}

// Single constructor site for OptResult.
fn _optfw_result(x: Int, value: Int, iters: Int, reason: Int, improved: Bool) -> OptResult {
  return OptResult{ x: x; value: value; iters: iters; reason: reason; improved: improved; };
}

// Degenerate-input result: no iteration ran. The value is OPT_NONE for an
// empty objective, else the (nearest-sample) evaluation at x.
fn _optfw_degenerate(o: &OptObjective, x: Int) -> OptResult {
  var v = OPT_NONE;
  if optfw_obj_len(o) > 0 {
    v = optfw_eval(o, x);
  }
  return _optfw_result(x, v, 0, OPT_REASON_EMPTY, false);
}

// The single push site for the two parallel objective vectors.
fn _obj_push(o: &mut OptObjective, x: Int, v: Int) {
  o.xs.push(x);
  o.vs.push(v);
}

// The single push site for the three parallel trace vectors.
fn _trace_push(t: &mut OptTrace, iter: Int, best: Int, current: Int) {
  t.iters.push(iter);
  t.bests.push(best);
  t.currents.push(current);
}

// Clamped hard iteration cap of a stop record (always >= 1).
fn _optfw_cap(stop: &OptStop) -> Int {
  var cap = stop.max_iters;
  if cap < 1 { cap = 1; }
  return cap;
}

// ---------------------------------------------------------------------------
// Objective construction and evaluation
// ---------------------------------------------------------------------------

/// Build a sample-table objective: values[i] is the value of the point
/// `lo + i * stride`, i in [0, values.len()).
/// Params: values - sample values; lo - position of the first sample;
///         step - sample stride, clamped to >= 1.
/// Returns: the objective record. Positions saturate only by Int wrapping at
/// extreme inputs.
/// Complexity: O(values.len()).
pub fn optfw_table_new(values: &Vec[Int], lo: Int, step: Int) -> OptObjective {
  var o = OptObjective{ xs: Vec[Int].new(); vs: Vec[Int].new(); };
  var s = step;
  if s < 1 { s = 1; }
  let n = values.len();
  var i = 0;
  while i < n {
    let v: Int = values[i];
    _obj_push(&mut o, lo + i * s, v);
    i = i + 1;
  }
  return o;
}

/// Build an explicit-value-list objective from parallel position and value
/// vectors. The shorter vector bounds the record: only min(xs.len, vs.len)
/// samples are copied, so the result is always consistent.
/// Params: xs - sample positions (as given; not required to be sorted);
///         vs - sample values.
/// Returns: the objective record.
/// Complexity: O(min(xs.len, vs.len)).
pub fn optfw_list_new(xs: &Vec[Int], vs: &Vec[Int]) -> OptObjective {
  var o = OptObjective{ xs: Vec[Int].new(); vs: Vec[Int].new(); };
  var n = xs.len();
  if vs.len() < n { n = vs.len(); }
  var i = 0;
  while i < n {
    let xv: Int = xs[i];
    let vv: Int = vs[i];
    _obj_push(&mut o, xv, vv);
    i = i + 1;
  }
  return o;
}

/// Number of samples in the objective. Complexity: O(1).
pub fn optfw_obj_len(o: &OptObjective) -> Int {
  return o.xs.len();
}

/// True when both parallel vectors have the same length. Complexity: O(1).
pub fn optfw_obj_is_consistent(o: &OptObjective) -> Bool {
  return o.xs.len() == o.vs.len();
}

/// Position of sample i, or 0 when out of range. Complexity: O(1).
pub fn optfw_obj_x(o: &OptObjective, i: Int) -> Int {
  if i < 0 || i >= o.xs.len() {
    return 0;
  }
  let v: Int = o.xs[i];
  return v;
}

/// Value of sample i, or OPT_NONE when out of range. Complexity: O(1).
pub fn optfw_obj_v(o: &OptObjective, i: Int) -> Int {
  if i < 0 || i >= o.vs.len() {
    return OPT_NONE;
  }
  let v: Int = o.vs[i];
  return v;
}

/// Position of the first sample, or 0 when empty. Complexity: O(1).
pub fn optfw_obj_first(o: &OptObjective) -> Int {
  return optfw_obj_x(o, 0);
}

/// Position of the last sample, or 0 when empty. Complexity: O(1).
pub fn optfw_obj_last(o: &OptObjective) -> Int {
  return optfw_obj_x(o, o.xs.len() - 1);
}

/// Evaluate the objective at x by nearest sample: the value of the sample
/// whose position is closest to x, with ties keeping the earliest sample.
/// Params: o - the objective; x - any integer point.
/// Returns: the sample value, or OPT_NONE when the objective is empty.
/// Complexity: O(samples). Positions and differences wrap at extreme values;
/// callers keep coordinates far from the Int extremes.
pub fn optfw_eval(o: &OptObjective, x: Int) -> Int {
  let n = o.xs.len();
  if n == 0 { return OPT_NONE; }
  var m = n;
  if o.vs.len() < m { m = o.vs.len(); }
  if m == 0 { return OPT_NONE; }
  let x0: Int = o.xs[0];
  var best_i = 0;
  var best_d = _optfw_abs(x - x0);
  var i = 1;
  while i < m {
    let xi: Int = o.xs[i];
    let d = _optfw_abs(x - xi);
    if d < best_d {
      best_d = d;
      best_i = i;
    }
    i = i + 1;
  }
  let v: Int = o.vs[best_i];
  return v;
}

// ---------------------------------------------------------------------------
// Stopping rules
// ---------------------------------------------------------------------------

/// Build a stopping record. max_iters is clamped to >= 1 (a search always
/// performs at least one iteration and is always bounded); no_improve <= 0
/// disables the window rule; floor == OPT_NONE disables the floor rule.
/// Params: max_iters - hard iteration cap; no_improve - window length;
///         floor - best-value target.
/// Returns: the OptStop record. Complexity: O(1).
pub fn optfw_stop_new(max_iters: Int, no_improve: Int, floor: Int) -> OptStop {
  var cap = max_iters;
  if cap < 1 { cap = 1; }
  return OptStop{ max_iters: cap; no_improve: no_improve; floor: floor; };
}

/// Hard iteration cap of a stop record. Complexity: O(1).
pub fn optfw_stop_max_iters(s: &OptStop) -> Int {
  return s.max_iters;
}

/// No-improvement window of a stop record (<= 0 means disabled). O(1).
pub fn optfw_stop_no_improve(s: &OptStop) -> Int {
  return s.no_improve;
}

/// Value floor of a stop record (OPT_NONE means disabled). Complexity: O(1).
pub fn optfw_stop_floor(s: &OptStop) -> Int {
  return s.floor;
}

// ---------------------------------------------------------------------------
// Convergence traces
// ---------------------------------------------------------------------------

/// A fresh empty trace. Params: none. Returns: the trace record. O(1).
pub fn optfw_trace_new() -> OptTrace {
  return OptTrace{ iters: Vec[Int].new(); bests: Vec[Int].new(); currents: Vec[Int].new(); };
}

/// Number of trace rows. Complexity: O(1).
pub fn optfw_trace_len(t: &OptTrace) -> Int {
  return t.iters.len();
}

/// True when all three parallel trace vectors have the same length. O(1).
pub fn optfw_trace_is_consistent(t: &OptTrace) -> Bool {
  return t.iters.len() == t.bests.len() && t.iters.len() == t.currents.len();
}

/// Iteration number of trace row i, or 0 when out of range. Complexity: O(1).
pub fn optfw_trace_iter(t: &OptTrace, i: Int) -> Int {
  if i < 0 || i >= t.iters.len() {
    return 0;
  }
  let v: Int = t.iters[i];
  return v;
}

/// Best-so-far value of trace row i, or OPT_NONE when out of range. O(1).
pub fn optfw_trace_best(t: &OptTrace, i: Int) -> Int {
  if i < 0 || i >= t.bests.len() {
    return OPT_NONE;
  }
  let v: Int = t.bests[i];
  return v;
}

/// Current value of trace row i, or OPT_NONE when out of range. O(1).
pub fn optfw_trace_current(t: &OptTrace, i: Int) -> Int {
  if i < 0 || i >= t.currents.len() {
    return OPT_NONE;
  }
  let v: Int = t.currents[i];
  return v;
}

// ---------------------------------------------------------------------------
// Result accessors
// ---------------------------------------------------------------------------

/// Best point of a result. Complexity: O(1).
pub fn optfw_result_x(r: &OptResult) -> Int {
  return r.x;
}

/// Best value of a result (OPT_NONE for an empty objective). O(1).
pub fn optfw_result_value(r: &OptResult) -> Int {
  return r.value;
}

/// Iterations consumed by a result. Complexity: O(1).
pub fn optfw_result_iters(r: &OptResult) -> Int {
  return r.iters;
}

/// Stop reason of a result (one OPT_REASON_*). Complexity: O(1).
pub fn optfw_result_reason(r: &OptResult) -> Int {
  return r.reason;
}

/// True when the best point differs from the starting point. O(1).
pub fn optfw_result_improved(r: &OptResult) -> Bool {
  return r.improved;
}

// ---------------------------------------------------------------------------
// Annealing configuration and deterministic random stream
// ---------------------------------------------------------------------------

/// Build an annealing configuration. step is clamped to >= 0 (a radius of 0
/// proposes only the current point); temp_start is clamped to >= 1 by the
/// schedule; cool_den is clamped to >= 1 and cool_num into [0, cool_den].
/// Params: step - proposal radius; seed - PRNG root; temp_start - starting
///         temperature; cool_num/cool_den - fixed-point cooling ratio.
/// Returns: the OptAnnealCfg record. Complexity: O(1).
pub fn optfw_anneal_cfg_new(step: Int, seed: Int, temp_start: Int, cool_num: Int, cool_den: Int) -> OptAnnealCfg {
  return OptAnnealCfg{ step: step; seed: seed; temp_start: temp_start; cool_num: cool_num; cool_den: cool_den; };
}

/// Proposal radius of a configuration, clamped to >= 0. Complexity: O(1).
pub fn optfw_cfg_step(c: &OptAnnealCfg) -> Int {
  var s = c.step;
  if s < 0 { s = 0; }
  return s;
}

/// PRNG seed of a configuration. Complexity: O(1).
pub fn optfw_cfg_seed(c: &OptAnnealCfg) -> Int {
  return c.seed;
}

/// Starting temperature of a configuration. Complexity: O(1).
pub fn optfw_cfg_temp_start(c: &OptAnnealCfg) -> Int {
  return c.temp_start;
}

/// Fixed-point cooling numerator of a configuration. Complexity: O(1).
pub fn optfw_cfg_cool_num(c: &OptAnnealCfg) -> Int {
  return c.cool_num;
}

/// Fixed-point cooling denominator of a configuration. Complexity: O(1).
pub fn optfw_cfg_cool_den(c: &OptAnnealCfg) -> Int {
  return c.cool_den;
}

/// Advance the framework's deterministic LCG one step: state' =
/// (state * OPT_LCG_MUL + OPT_LCG_INC) mod 2^31, starting from the low 31
/// bits of `state`. Params: state - any Int. Returns: the next state/draw in
/// [0, 2^31 - 1]. The stream is a reproducibility device, NOT cryptographic.
/// Complexity: O(1).
pub fn optfw_lcg_next(state: Int) -> Int {
  let s = state & OPT_LCG_MASK;
  return (s * OPT_LCG_MUL + OPT_LCG_INC) & OPT_LCG_MASK;
}

/// Deterministic per-restart seed: restart `index` (0-based) of a sequence
/// rooted at `base`, spread far apart by the odd multiplier before mixing.
/// Params: base - stream root; index - restart ordinal.
/// Returns: a seed in [0, 2^31 - 1]. Complexity: O(1).
pub fn optfw_seed_at(base: Int, index: Int) -> Int {
  return optfw_lcg_next(base + (index + 1) * OPT_SEED_SPREAD);
}

/// One fixed-point cooling step: max(1, temp * cool_num / cool_den) with
/// integer truncation. cool_den is clamped to >= 1, cool_num into
/// [0, cool_den], and the result is clamped to >= 1, so the temperature is
/// non-increasing and never leaves [1, temp]. Params: temp - current
/// temperature; cool_num/cool_den - ratio. Returns: the next temperature.
/// Complexity: O(1).
pub fn optfw_temp_next(temp: Int, cool_num: Int, cool_den: Int) -> Int {
  var t = temp;
  if t < 1 { t = 1; }
  var num = cool_num;
  if num < 0 { num = 0; }
  var den = cool_den;
  if den < 1 { den = 1; }
  if num > den { num = den; }
  var next = (t * num) / den;
  if next < 1 { next = 1; }
  return next;
}

/// Temperature after `steps` cooling steps: the result of applying
/// optfw_temp_next `steps` times to max(1, temp_start). steps <= 0 returns
/// the clamped start. The sequence is non-increasing and, when
/// cool_num < cool_den, it reaches 1 in finite steps. Params: temp_start -
/// starting temperature; cool_num/cool_den - ratio; steps - cooling steps.
/// Returns: the temperature at that step. Complexity: O(steps).
pub fn optfw_temp_at(temp_start: Int, cool_num: Int, cool_den: Int, steps: Int) -> Int {
  var t = temp_start;
  if t < 1 { t = 1; }
  var i = 0;
  while i < steps {
    t = optfw_temp_next(t, cool_num, cool_den);
    i = i + 1;
  }
  return t;
}

// ---------------------------------------------------------------------------
// Grid search
// ---------------------------------------------------------------------------

// Shared grid-search core. The scan walks x = lo, lo + s, lo + 2s, ... while
// the next step fits inside hi (a non-negative remainder check, so no stride
// can overflow the loop), updating the best on strict improvement. The
// no-improve counter counts samples that did not set a new best (the first
// sample always counts as an improvement).
fn _grid_core(o: &OptObjective, lo: Int, hi: Int, step: Int, stop: &OptStop, tr: &mut OptTrace) -> OptResult {
  var s = step;
  if s < 1 { s = 1; }
  let cap = _optfw_cap(stop);
  let window = stop.no_improve;
  let floor = stop.floor;
  if hi < lo || optfw_obj_len(o) == 0 {
    return _optfw_degenerate(o, lo);
  }
  var x = lo;
  var best_x = lo;
  var best_v = OPT_NONE;
  var has_best = false;
  var misses = 0;
  var iters = 0;
  var reason = OPT_REASON_EXHAUSTED;
  var running = true;
  while running {
    if iters >= cap {
      reason = OPT_REASON_MAX_ITERS;
      running = false;
    } else if floor != OPT_NONE && best_v >= floor && has_best {
      reason = OPT_REASON_FLOOR;
      running = false;
    } else if window >= 1 && misses >= window {
      reason = OPT_REASON_NO_IMPROVE;
      running = false;
    } else {
      let v = optfw_eval(o, x);
      if !has_best || v > best_v {
        best_v = v;
        best_x = x;
        has_best = true;
        misses = 0;
      } else {
        misses = misses + 1;
      }
      iters = iters + 1;
      _trace_push(tr, iters, best_v, v);
      if s > hi - x {
        running = false;
      } else {
        x = x + s;
      }
    }
  }
  var improved = false;
  if best_x != lo {
    improved = true;
  }
  return _optfw_result(best_x, best_v, iters, reason, improved);
}

/// Exhaustive stepped grid search over [lo, hi], early-stoppable by the
/// shared rules. Samples x = lo, lo + step, ... while the next stride fits in
/// hi; a strictly larger value replaces the incumbent, so ties keep the
/// smallest x. step is clamped to >= 1. An empty range (hi < lo) or an empty
/// objective returns x = lo with reason OPT_REASON_EMPTY and no iterations.
/// Params: o - objective; lo/hi - inclusive range; step - stride;
///         stop - stopping rules.
/// Returns: the best sampled point. Complexity: O(samples * samples(o)).
pub fn optfw_grid_search(o: &OptObjective, lo: Int, hi: Int, step: Int, stop: &OptStop) -> OptResult {
  var tr = optfw_trace_new();
  return _grid_core(o, lo, hi, step, stop, &mut tr);
}

/// optfw_grid_search plus a convergence trace: one row per sample considered
/// (iteration number, best-so-far value, sample value). Params: as
/// optfw_grid_search plus tr - the trace to append to (mutated).
/// Returns: the best sampled point. Complexity: as optfw_grid_search.
pub fn optfw_grid_search_trace(o: &OptObjective, lo: Int, hi: Int, step: Int, stop: &OptStop, tr: &mut OptTrace) -> OptResult {
  return _grid_core(o, lo, hi, step, stop, tr);
}

// ---------------------------------------------------------------------------
// Hill climbing
// ---------------------------------------------------------------------------

// Shared hill-climbing core. The current point starts at start clamped into
// [lo, hi]. Each iteration evaluates the clamped neighbours x - s and x + s:
//   * best_mode == 0 (first improvement): move to x - s as soon as it scores
//     strictly higher than the current point, otherwise to x + s;
//   * best_mode == 1 (best improvement): evaluate both and move to the higher
//     score when it is strictly above the current point (ties keep x - s).
// A move only ever raises the score. A stall halves the integer step; a step
// of 1 halves to 0 and terminates the walk. The no-improve counter counts
// iterations without a move (halvings included); the trace records the
// post-iteration current value.
fn _hill_core(o: &OptObjective, start: Int, lo: Int, hi: Int, step: Int, stop: &OptStop, best_mode: Int, tr: &mut OptTrace) -> OptResult {
  if hi < lo || optfw_obj_len(o) == 0 {
    return _optfw_degenerate(o, start);
  }
  let cap = _optfw_cap(stop);
  let window = stop.no_improve;
  let floor = stop.floor;
  var s = step;
  if s < 1 { s = 1; }
  var x = _optfw_clamp(start, lo, hi);
  let start_x = x;
  var cur = optfw_eval(o, x);
  var best_x = x;
  var best_v = cur;
  var misses = 0;
  var iters = 0;
  var reason = OPT_REASON_STEP_ZERO;
  var running = true;
  while running {
    if iters >= cap {
      reason = OPT_REASON_MAX_ITERS;
      running = false;
    } else if floor != OPT_NONE && best_v >= floor {
      reason = OPT_REASON_FLOOR;
      running = false;
    } else if window >= 1 && misses >= window {
      reason = OPT_REASON_NO_IMPROVE;
      running = false;
    } else if s < 1 {
      reason = OPT_REASON_STEP_ZERO;
      running = false;
    } else {
      let left = _optfw_clamp(x - s, lo, hi);
      let right = _optfw_clamp(x + s, lo, hi);
      var moved = false;
      if best_mode == 0 {
        let lv = optfw_eval(o, left);
        if lv > cur {
          x = left;
          cur = lv;
          moved = true;
        } else {
          let rv = optfw_eval(o, right);
          if rv > cur {
            x = right;
            cur = rv;
            moved = true;
          }
        }
      } else {
        let lv = optfw_eval(o, left);
        let rv = optfw_eval(o, right);
        if lv > cur && lv >= rv {
          x = left;
          cur = lv;
          moved = true;
        } else if rv > cur && rv > lv {
          x = right;
          cur = rv;
          moved = true;
        }
      }
      iters = iters + 1;
      if moved {
        misses = 0;
        if cur > best_v {
          best_v = cur;
          best_x = x;
        }
      } else {
        misses = misses + 1;
        s = s / 2;
      }
      _trace_push(tr, iters, best_v, cur);
    }
  }
  var improved = false;
  if best_x != start_x {
    improved = true;
  }
  return _optfw_result(best_x, best_v, iters, reason, improved);
}

/// Hill climbing with FIRST improvement: move to x - step as soon as it beats
/// the current point, otherwise to x + step; halve the step on a stall.
/// Params: o - objective; start - initial point (clamped into [lo, hi]);
///         lo/hi - inclusive bounds; step - initial step (clamped to >= 1);
///         stop - stopping rules.
/// Returns: the best point visited. The score never decreases. step 1 that
/// stalls halves to 0 and stops with OPT_REASON_STEP_ZERO.
/// Complexity: O(iters * samples(o)).
pub fn optfw_hill_first(o: &OptObjective, start: Int, lo: Int, hi: Int, step: Int, stop: &OptStop) -> OptResult {
  var tr = optfw_trace_new();
  return _hill_core(o, start, lo, hi, step, stop, 0, &mut tr);
}

/// optfw_hill_first plus a convergence trace (one row per iteration).
/// Params: as optfw_hill_first plus tr - the trace (mutated).
/// Returns: the best point visited. Complexity: as optfw_hill_first.
pub fn optfw_hill_first_trace(o: &OptObjective, start: Int, lo: Int, hi: Int, step: Int, stop: &OptStop, tr: &mut OptTrace) -> OptResult {
  return _hill_core(o, start, lo, hi, step, stop, 0, tr);
}

/// Hill climbing with BEST improvement: evaluate both neighbours and move to
/// the strictly higher score (ties keep x - step); halve the step on a stall.
/// Params: as optfw_hill_first. Returns: the best point visited.
/// Complexity: O(iters * samples(o)).
pub fn optfw_hill_best(o: &OptObjective, start: Int, lo: Int, hi: Int, step: Int, stop: &OptStop) -> OptResult {
  var tr = optfw_trace_new();
  return _hill_core(o, start, lo, hi, step, stop, 1, &mut tr);
}

/// optfw_hill_best plus a convergence trace (one row per iteration).
/// Params: as optfw_hill_best plus tr - the trace (mutated).
/// Returns: the best point visited. Complexity: as optfw_hill_best.
pub fn optfw_hill_best_trace(o: &OptObjective, start: Int, lo: Int, hi: Int, step: Int, stop: &OptStop, tr: &mut OptTrace) -> OptResult {
  return _hill_core(o, start, lo, hi, step, stop, 1, tr);
}

// ---------------------------------------------------------------------------
// Simulated annealing
// ---------------------------------------------------------------------------

// Shared annealing core. Step k (1-based) runs at temperature
// optfw_temp_at(temp_start, cool_num, cool_den, k - 1) and proposes
// nx = clamp(x + delta, lo, hi) with delta = draw % (2 * step + 1) - step in
// [-step, step]. An improving candidate is always accepted; otherwise the
// move is accepted when a second draw satisfies
// draw % (temp + 1) > |value(nx) - value(x)| -- the integer Metropolis
// approximation of exp(-cost / temp). On acceptance the walk moves; the
// best-so-far record updates only on a strict improvement (ties keep the
// earliest best). The no-improve counter counts iterations that did not set
// a new best (accepted sideways moves included).
fn _anneal_core(o: &OptObjective, start: Int, lo: Int, hi: Int, cfg: &OptAnnealCfg, stop: &OptStop, tr: &mut OptTrace) -> OptResult {
  if hi < lo || optfw_obj_len(o) == 0 {
    return _optfw_degenerate(o, start);
  }
  let cap = _optfw_cap(stop);
  let window = stop.no_improve;
  let floor = stop.floor;
  var radius = cfg.step;
  if radius < 0 { radius = 0; }
  var t0 = cfg.temp_start;
  if t0 < 1 { t0 = 1; }
  var temp = t0;
  var x = _optfw_clamp(start, lo, hi);
  let start_x = x;
  var cur = optfw_eval(o, x);
  var best_x = x;
  var best_v = cur;
  var rng = optfw_lcg_next(cfg.seed);
  var misses = 0;
  var iters = 0;
  var reason = OPT_REASON_MAX_ITERS;
  var running = true;
  while running {
    if iters >= cap {
      reason = OPT_REASON_MAX_ITERS;
      running = false;
    } else if floor != OPT_NONE && best_v >= floor {
      reason = OPT_REASON_FLOOR;
      running = false;
    } else if window >= 1 && misses >= window {
      reason = OPT_REASON_NO_IMPROVE;
      running = false;
    } else {
      rng = optfw_lcg_next(rng);
      let delta = rng % (2 * radius + 1) - radius;
      let nx = _optfw_clamp(x + delta, lo, hi);
      let cv = optfw_eval(o, nx);
      var accept = false;
      if cv > cur {
        accept = true;
      } else {
        rng = optfw_lcg_next(rng);
        let cost = _optfw_abs(cv - cur);
        if rng % (temp + 1) > cost {
          accept = true;
        }
      }
      iters = iters + 1;
      if accept {
        x = nx;
        cur = cv;
        if cur > best_v {
          best_v = cur;
          best_x = x;
          misses = 0;
        } else {
          misses = misses + 1;
        }
      } else {
        misses = misses + 1;
      }
      _trace_push(tr, iters, best_v, cur);
      temp = optfw_temp_next(temp, cfg.cool_num, cfg.cool_den);
    }
  }
  var improved = false;
  if best_x != start_x {
    improved = true;
  }
  return _optfw_result(best_x, best_v, iters, reason, improved);
}

/// Simulated annealing over [lo, hi] with the framework's deterministic LCG
/// and a fixed-point geometric cooling schedule: step k (1-based) runs at
/// optfw_temp_at(temp_start, cool_num, cool_den, k - 1), so the temperature
/// is non-increasing and clamped to >= 1. start is clamped into [lo, hi].
/// The returned point is the best SEEN (the walk may end elsewhere).
/// Params: o - objective; start - initial point; lo/hi - inclusive bounds;
///         cfg - proposal radius, seed, temperature and cooling ratio;
///         stop - stopping rules.
/// Returns: the best point seen. Same inputs reproduce the same walk.
/// Complexity: O(iters * samples(o)).
pub fn optfw_anneal(o: &OptObjective, start: Int, lo: Int, hi: Int, cfg: &OptAnnealCfg, stop: &OptStop) -> OptResult {
  var tr = optfw_trace_new();
  return _anneal_core(o, start, lo, hi, cfg, stop, &mut tr);
}

/// optfw_anneal plus a convergence trace (one row per step: iteration number,
/// best-so-far value, current value after the step). Params: as optfw_anneal
/// plus tr - the trace (mutated). Returns: the best point seen.
/// Complexity: as optfw_anneal.
pub fn optfw_anneal_trace(o: &OptObjective, start: Int, lo: Int, hi: Int, cfg: &OptAnnealCfg, stop: &OptStop, tr: &mut OptTrace) -> OptResult {
  return _anneal_core(o, start, lo, hi, cfg, stop, tr);
}

// ---------------------------------------------------------------------------
// Random restarts
// ---------------------------------------------------------------------------

// Shared restart core. The global best is seeded with the value at lo; then
// each restart i samples a start x0 = lo + (optfw_seed_at(seed, i) % span)
// with span = hi - lo + 1 (so x0 is in [lo, hi]) and runs a best-improvement
// hill climb with an internal budget of OPT_RESTART_CLIMB_ITERS iterations.
// The global best updates on strict improvement. Stop rules: floor -- stop as
// soon as the global best reaches it; no_improve -- window over restarts
// without a new global best; max_iters -- cap on the number of restarts; the
// run ends with OPT_REASON_EXHAUSTED when `restarts` restarts complete.
fn _restart_core(o: &OptObjective, lo: Int, hi: Int, restarts: Int, step: Int, seed: Int, stop: &OptStop, tr: &mut OptTrace) -> OptResult {
  if hi < lo || optfw_obj_len(o) == 0 {
    return _optfw_degenerate(o, lo);
  }
  let cap = _optfw_cap(stop);
  let window = stop.no_improve;
  let floor = stop.floor;
  let span = hi - lo + 1;
  var best_x = lo;
  var best_v = optfw_eval(o, lo);
  var misses = 0;
  var iters = 0;
  var reason = OPT_REASON_EXHAUSTED;
  var running = true;
  while running {
    if floor != OPT_NONE && best_v >= floor {
      reason = OPT_REASON_FLOOR;
      running = false;
    } else if window >= 1 && misses >= window {
      reason = OPT_REASON_NO_IMPROVE;
      running = false;
    } else if iters >= restarts {
      reason = OPT_REASON_EXHAUSTED;
      running = false;
    } else if iters >= cap {
      reason = OPT_REASON_MAX_ITERS;
      running = false;
    } else {
      let x0 = lo + (optfw_seed_at(seed, iters) % span);
      var sub = optfw_trace_new();
      let climb_stop = optfw_stop_new(OPT_RESTART_CLIMB_ITERS, 0, OPT_NONE);
      let r = _hill_core(o, x0, lo, hi, step, &climb_stop, 1, &mut sub);
      var improved = false;
      if r.value > best_v {
        best_v = r.value;
        best_x = r.x;
        improved = true;
      }
      iters = iters + 1;
      if improved {
        misses = 0;
      } else {
        misses = misses + 1;
      }
      _trace_push(tr, iters, best_v, r.value);
    }
  }
  var improved = false;
  if best_x != lo {
    improved = true;
  }
  return _optfw_result(best_x, best_v, iters, reason, improved);
}

/// Deterministic random-restart search: hill climbing (best improvement)
/// from `restarts` LCG-sampled starts in [lo, hi], each with an internal
/// budget of OPT_RESTART_CLIMB_ITERS iterations. The running best is seeded
/// with the value at lo, so restarts < 1 returns lo. A strictly larger climb
/// outcome replaces the running best (ties keep the earliest).
/// Params: o - objective; lo/hi - inclusive bounds; restarts - number of
///         climbs; step - hill-climb step; seed - PRNG root; stop - rules.
/// Returns: the best point among the seeded point and all climbs. Same
/// inputs always reproduce the same run. Complexity: O(iters * samples(o)).
pub fn optfw_restart_search(o: &OptObjective, lo: Int, hi: Int, restarts: Int, step: Int, seed: Int, stop: &OptStop) -> OptResult {
  var tr = optfw_trace_new();
  return _restart_core(o, lo, hi, restarts, step, seed, stop, &mut tr);
}

/// optfw_restart_search plus a convergence trace: one row per restart
/// (restart number, best-so-far value, value returned by that restart's
/// climb). Params: as optfw_restart_search plus tr - the trace (mutated).
/// Returns: the best point found. Complexity: as optfw_restart_search.
pub fn optfw_restart_search_trace(o: &OptObjective, lo: Int, hi: Int, restarts: Int, step: Int, seed: Int, stop: &OptStop, tr: &mut OptTrace) -> OptResult {
  return _restart_core(o, lo, hi, restarts, step, seed, stop, tr);
}

// ---------------------------------------------------------------------------
// Names
// ---------------------------------------------------------------------------

/// Name of a stop reason constant ("none", "max-iters", "no-improve",
/// "floor", "exhausted", "step-zero", "empty"). Params: reason - an
/// OPT_REASON_* value. Returns: the name; "none" for unknown values. O(1).
pub fn optfw_reason_name(reason: Int) -> Str {
  if reason == OPT_REASON_MAX_ITERS {
    return "max-iters";
  }
  if reason == OPT_REASON_NO_IMPROVE {
    return "no-improve";
  }
  if reason == OPT_REASON_FLOOR {
    return "floor";
  }
  if reason == OPT_REASON_EXHAUSTED {
    return "exhausted";
  }
  if reason == OPT_REASON_STEP_ZERO {
    return "step-zero";
  }
  if reason == OPT_REASON_EMPTY {
    return "empty";
  }
  return "none";
}
