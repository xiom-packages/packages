// XIOM -- xiom.autoscale: deterministic autoscaling policy model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure deterministic autoscaling engine: no threads, no clock, no sleeping,
// no environment access. Time is an explicit integer tick sequence and every
// function takes its inputs explicitly. Free functions only (no methods, no
// lambdas, no function tables); every division truncates toward zero.
//
// Model:
//   * AutoscaleSeries -- a fixed-capacity ring buffer of Int metric samples
//     plus rolling-window aggregates (sum/min/max/avg) over the most recent
//     N stored samples. Pushes overwrite the oldest sample when full.
//   * AutoscalePolicy -- scale-up/down thresholds with a hysteresis band, a
//     minimum hysteresis margin, per-direction cooldowns in ticks, minimum
//     and maximum replica bounds, a consecutive-breach requirement, and a
//     step that is either fixed (+/- N replicas) or proportional in basis
//     points (bps) of the current replica count. autoscale_policy_check
//     validates every invariant and returns the first violated code.
//   * AutoscaleController -- the state machine: replicas, tick counter,
//     per-direction breach streaks and last-action ticks, an embedded metric
//     series, and one decision record per tick stored as mirrored parallel
//     Int vectors (no Vec[StructType] in this compiler): tick, action,
//     from/to replicas, reason code and the observed value.
//
// Decision rule (evaluated on every tick):
//   observed >= up_threshold   -> up breach
//   observed <= down_threshold -> down breach
//   otherwise                  -> inside the hysteresis band (both streaks
//                                 reset to zero)
// A direction only acts after `breach_threshold` consecutive breaches in
// that direction, while outside its cooldown, and while not already at its
// bound. Actions do not reset the breach streak: the cooldown is the rate
// limiter. The step always clamps to at least one replica, so a proportional
// step never rounds down to zero.
//
// v0.62.2 notes that shaped this module:
//   * free functions only; no self methods, no lambdas, no fn-tables, and
//     no Vec[StructType] -- decision records are mirrored parallel Vec[Int];
//   * no Vec[Str] anywhere: reason codes are Ints and the catalog lives in
//     autoscale_reason_text, which avoids the v0.62.2 Vec[Str].push
//     mis-lowering entirely;
//   * no &mut Int parameters -- scalar state is threaded through struct
//     fields (the v0.62.2 &mut Int write-drop workaround);
//   * explicit &mut at every mutating call site, and &/&mut on nested
//     struct fields;
//   * every loop has a strictly increasing counter, so every loop
//     terminates; every window is clamped to the stored length;
//   * saturating addition/subtraction and a split multiply-then-divide keep
//     aggregates, cooldown arithmetic and proportional steps inside the
//     Int range.

module xiom.autoscale

// --------------------------------------------------
//  Constants
// --------------------------------------------------

const _ASC_I64_MAX: Int = 9223372036854775807;
const _ASC_REPLICA_MAX: Int = 1000000000;
const _ASC_CAP_MAX: Int = 1000000;
const _ASC_TICK_MAX: Int = 9223372036854775806;
const _ASC_BPS: Int = 10000;

// Step modes.
const _ASC_STEP_FIXED: Int = 0;
const _ASC_STEP_BPS: Int = 1;

// Action codes.
const _ASC_ACTION_NONE: Int = 0;
const _ASC_ACTION_UP: Int = 1;
const _ASC_ACTION_DOWN: Int = 2;

// Reason codes (see autoscale_reason_text).
const _ASC_R_UP: Int = 1;
const _ASC_R_DOWN: Int = 2;
const _ASC_R_BAND: Int = 3;
const _ASC_R_STREAK_UP: Int = 4;
const _ASC_R_STREAK_DOWN: Int = 5;
const _ASC_R_COOLDOWN_UP: Int = 6;
const _ASC_R_COOLDOWN_DOWN: Int = 7;
const _ASC_R_AT_MAX: Int = 8;
const _ASC_R_AT_MIN: Int = 9;
const _ASC_R_BAD_POLICY: Int = 10;
const _ASC_R_TICK_OVERFLOW: Int = 11;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// Fixed-capacity metric ring buffer. `values` holds the last
/// min(count, capacity) pushes in chronological order (index 0 oldest);
/// `head` is the next write slot once the buffer is full. Fields are
/// implementation details; construct with autoscale_series_new, feed with
/// autoscale_series_push and read with autoscale_series_* accessors.
pub type AutoscaleSeries = {
  capacity: Int;
  count: Int;
  head: Int;
  values: Vec[Int];
}

/// Autoscaling policy. `up_threshold`/`down_threshold` are the breach
/// bounds (inclusive) and the open interval between them is the hysteresis
/// band; `min_hysteresis` is the smallest required gap. `up_cooldown` and
/// `down_cooldown` are minimum tick gaps between actions of the same
/// direction. `breach_threshold` is the number of consecutive breaching
/// samples required before a direction may act. `step_mode` selects a fixed
/// step (`step_fixed` replicas) or a proportional step (`step_bps` basis
/// points of the current count). `series_capacity` is the controller's ring
/// size. The constructor stores inputs verbatim; autoscale_policy_check
/// reports malformed combinations.
pub type AutoscalePolicy = {
  metric: Str;
  min_replicas: Int;
  max_replicas: Int;
  up_threshold: Int;
  down_threshold: Int;
  min_hysteresis: Int;
  up_cooldown: Int;
  down_cooldown: Int;
  breach_threshold: Int;
  step_mode: Int;
  step_fixed: Int;
  step_bps: Int;
  series_capacity: Int;
}

/// Autoscaling state machine. `ticks` is the number of accepted ticks,
/// `replicas` the current target, `last_up_tick`/`last_down_tick` the tick
/// of the last action per direction, and `up_streak`/`down_streak` the
/// consecutive-breaches counters. `record_*` are the mirrored decision
/// records appended once per accepted tick (and once per refused tick):
/// record i is (record_tick[i], record_action[i], record_from[i],
/// record_to[i], record_reason[i], record_detail[i]) where `detail` is the
/// observed metric for policy decisions or the policy error code when the
/// tick was refused.
pub type AutoscaleController = {
  policy: AutoscalePolicy;
  series: AutoscaleSeries;
  replicas: Int;
  ticks: Int;
  last_up_tick: Int;
  last_down_tick: Int;
  up_streak: Int;
  down_streak: Int;
  record_tick: Vec[Int];
  record_action: Vec[Int];
  record_from: Vec[Int];
  record_to: Vec[Int];
  record_reason: Vec[Int];
  record_detail: Vec[Int];
}

// --------------------------------------------------
//  Arithmetic helpers (truncating, overflow-guarded)
// --------------------------------------------------

// Truncating division toward zero, independent of native Int semantics.
fn _asc_trunc_div(a: Int, b: Int) -> Int {
  if b == 0 { return 0; }
  if a == (0 - _ASC_I64_MAX - 1) && b == -1 { return _ASC_I64_MAX; }
  var x = a;
  var y = b;
  var neg = false;
  if x < 0 {
    neg = !neg;
    x = 0 - x;
  }
  if y < 0 {
    neg = !neg;
    y = 0 - y;
  }
  let q = x / y;
  if neg { return 0 - q; }
  return q;
}

// Truncating remainder matching _asc_trunc_div (sign of the dividend).
fn _asc_trunc_mod(a: Int, b: Int) -> Int {
  if b == 0 { return 0; }
  let q = _asc_trunc_div(a, b);
  return a - q * b;
}

// Saturating a + b.
fn _asc_add_sat(a: Int, b: Int) -> Int {
  if b > 0 && a > _ASC_I64_MAX - b { return _ASC_I64_MAX; }
  if b < 0 && a < (0 - _ASC_I64_MAX - 1) - b { return 0 - _ASC_I64_MAX - 1; }
  return a + b;
}

// Saturating a - b.
fn _asc_sub_sat(a: Int, b: Int) -> Int {
  if b > 0 && a < (0 - _ASC_I64_MAX - 1) + b { return 0 - _ASC_I64_MAX - 1; }
  if b < 0 && a > _ASC_I64_MAX + b { return _ASC_I64_MAX; }
  return a - b;
}

// trunc(v * bps / 10000) computed without ever forming v * bps: the value is
// split into a quotient and a remainder of 10000 so both partial products
// stay bounded (bps is clamped to [0, 10000] first). Exact for every Int v.
fn _asc_mul_div_bps(v: Int, bps: Int) -> Int {
  var b = bps;
  if b < 0 { b = 0; }
  if b > _ASC_BPS { b = _ASC_BPS; }
  let q = _asc_trunc_div(v, _ASC_BPS);
  let r = _asc_trunc_mod(v, _ASC_BPS);
  return q * b + _asc_trunc_div(r * b, _ASC_BPS);
}

// --------------------------------------------------
//  Metric series (fixed-capacity ring buffer)
// --------------------------------------------------

/// Create an empty series. `capacity` is clamped to [1, 1000000].
/// Complexity: O(1).
pub fn autoscale_series_new(capacity: Int) -> AutoscaleSeries {
  var cap = capacity;
  if cap < 1 { cap = 1; }
  if cap > _ASC_CAP_MAX { cap = _ASC_CAP_MAX; }
  return AutoscaleSeries{ capacity: cap; count: 0; head: 0; values: Vec[Int].new() };
}

/// Configured ring capacity (always in [1, 1000000]). Complexity: O(1).
pub fn autoscale_series_capacity(s: &AutoscaleSeries) -> Int {
  return s.capacity;
}

/// Total pushes ever recorded (can exceed capacity). Complexity: O(1).
pub fn autoscale_series_count(s: &AutoscaleSeries) -> Int {
  return s.count;
}

/// Samples currently stored (min(count, capacity)). Complexity: O(1).
pub fn autoscale_series_len(s: &AutoscaleSeries) -> Int {
  return s.values.len();
}

/// Push one sample. When the ring is full the oldest sample is overwritten,
/// so the stored window always holds the newest samples. Complexity: O(1).
pub fn autoscale_series_push(s: &mut AutoscaleSeries, value: Int) {
  if s.values.len() < s.capacity {
    s.values.push(value);
    s.head = s.values.len() % s.capacity;
  } else {
    s.values[s.head] = value;
    s.head = (s.head + 1) % s.capacity;
  }
  s.count = s.count + 1;
}

/// Stored sample `i` in chronological order (0 = oldest stored, len-1 =
/// newest). Out-of-range indexes return 0. Complexity: O(1).
pub fn autoscale_series_at(s: &AutoscaleSeries, i: Int) -> Int {
  let n = s.values.len();
  if i < 0 || i >= n { return 0; }
  if n < s.capacity { return s.values[i]; }
  return s.values[(s.head + i) % s.capacity];
}

// Effective window length: 0 when `window <= 0` or the series is empty,
// otherwise min(window, stored). No loop.
fn _asc_window_len(s: &AutoscaleSeries, window: Int) -> Int {
  let n = s.values.len();
  if window <= 0 { return 0; }
  if window > n { return n; }
  return window;
}

/// Saturating sum of the most recent `window` samples (0 when the window is
/// empty). Complexity: O(window).
pub fn autoscale_series_sum(s: &AutoscaleSeries, window: Int) -> Int {
  let n = _asc_window_len(s, window);
  if n == 0 { return 0; }
  let total = s.values.len();
  var acc = 0;
  var i = total - n;
  while i < total {
    acc = _asc_add_sat(acc, autoscale_series_at(s, i));
    i = i + 1;
  }
  return acc;
}

/// Minimum of the most recent `window` samples (0 when the window is
/// empty). Complexity: O(window).
pub fn autoscale_series_min(s: &AutoscaleSeries, window: Int) -> Int {
  let n = _asc_window_len(s, window);
  if n == 0 { return 0; }
  let total = s.values.len();
  var acc = autoscale_series_at(s, total - n);
  var i = total - n + 1;
  while i < total {
    let v = autoscale_series_at(s, i);
    if v < acc { acc = v; }
    i = i + 1;
  }
  return acc;
}

/// Maximum of the most recent `window` samples (0 when the window is
/// empty). Complexity: O(window).
pub fn autoscale_series_max(s: &AutoscaleSeries, window: Int) -> Int {
  let n = _asc_window_len(s, window);
  if n == 0 { return 0; }
  let total = s.values.len();
  var acc = autoscale_series_at(s, total - n);
  var i = total - n + 1;
  while i < total {
    let v = autoscale_series_at(s, i);
    if v > acc { acc = v; }
    i = i + 1;
  }
  return acc;
}

/// Integer average of the most recent `window` samples:
/// trunc(sum / n) toward zero (0 when the window is empty).
/// Complexity: O(window).
pub fn autoscale_series_avg(s: &AutoscaleSeries, window: Int) -> Int {
  let n = _asc_window_len(s, window);
  if n == 0 { return 0; }
  return _asc_trunc_div(autoscale_series_sum(s, window), n);
}

// --------------------------------------------------
//  Policy
// --------------------------------------------------

/// Create a policy with defaults: no cooldowns, breach_threshold 1, fixed
/// step of one replica, and a 16-slot series. Inputs are stored verbatim;
/// call autoscale_policy_check before driving a controller. The builders
/// autoscale_policy_with_* derive modified copies.
pub fn autoscale_policy_new(metric_name: Str, min_replicas: Int, max_replicas: Int, up_threshold: Int, down_threshold: Int, min_hysteresis: Int) -> AutoscalePolicy {
  return AutoscalePolicy{
    metric: metric_name;
    min_replicas: min_replicas;
    max_replicas: max_replicas;
    up_threshold: up_threshold;
    down_threshold: down_threshold;
    min_hysteresis: min_hysteresis;
    up_cooldown: 0;
    down_cooldown: 0;
    breach_threshold: 1;
    step_mode: _ASC_STEP_FIXED;
    step_fixed: 1;
    step_bps: 0;
    series_capacity: 16;
  };
}

/// Copy of `p` with both direction cooldowns set (in ticks).
pub fn autoscale_policy_with_cooldowns(p: AutoscalePolicy, up_ticks: Int, down_ticks: Int) -> AutoscalePolicy {
  var q = p;
  q.up_cooldown = up_ticks;
  q.down_cooldown = down_ticks;
  return q;
}

/// Copy of `p` with the consecutive-breach requirement set.
pub fn autoscale_policy_with_breach(p: AutoscalePolicy, n: Int) -> AutoscalePolicy {
  var q = p;
  q.breach_threshold = n;
  return q;
}

/// Copy of `p` switched to a fixed step of `n` replicas.
pub fn autoscale_policy_with_step_fixed(p: AutoscalePolicy, n: Int) -> AutoscalePolicy {
  var q = p;
  q.step_mode = _ASC_STEP_FIXED;
  q.step_fixed = n;
  q.step_bps = 0;
  return q;
}

/// Copy of `p` switched to a proportional step of `bps` basis points
/// (2500 = 25% of the current replica count, truncated).
pub fn autoscale_policy_with_step_bps(p: AutoscalePolicy, bps: Int) -> AutoscalePolicy {
  var q = p;
  q.step_mode = _ASC_STEP_BPS;
  q.step_bps = bps;
  return q;
}

/// Copy of `p` with the controller ring capacity set.
pub fn autoscale_policy_with_series_capacity(p: AutoscalePolicy, capacity: Int) -> AutoscalePolicy {
  var q = p;
  q.series_capacity = capacity;
  return q;
}

/// First violated policy invariant, or 0 when the policy is well formed.
/// Check order (first hit wins):
///   1  empty metric name
///   2  min_replicas < 0
///   3  max_replicas < min_replicas
///   4  max_replicas > 1000000000
///   5  up_threshold <= down_threshold
///   6  min_hysteresis < 0 or the threshold gap is below the margin
///   7  a cooldown is negative
///   8  breach_threshold < 1
///   9  step_mode is neither 0 (fixed) nor 1 (bps)
///   10 fixed step < 1
///   11 proportional step outside [1, 10000] bps
///   12 series_capacity outside [1, 1000000]
/// Complexity: O(1).
pub fn autoscale_policy_check(p: &AutoscalePolicy) -> Int {
  if p.metric.len() == 0 { return 1; }
  if p.min_replicas < 0 { return 2; }
  if p.max_replicas < p.min_replicas { return 3; }
  if p.max_replicas > _ASC_REPLICA_MAX { return 4; }
  if p.up_threshold <= p.down_threshold { return 5; }
  if p.min_hysteresis < 0 { return 6; }
  if _asc_sub_sat(p.up_threshold, p.down_threshold) < p.min_hysteresis { return 6; }
  if p.up_cooldown < 0 || p.down_cooldown < 0 { return 7; }
  if p.breach_threshold < 1 { return 8; }
  if p.step_mode != _ASC_STEP_FIXED && p.step_mode != _ASC_STEP_BPS { return 9; }
  if p.step_mode == _ASC_STEP_FIXED {
    if p.step_fixed < 1 { return 10; }
  } else {
    if p.step_bps < 1 || p.step_bps > _ASC_BPS { return 11; }
  }
  if p.series_capacity < 1 || p.series_capacity > _ASC_CAP_MAX { return 12; }
  return 0;
}

/// True when autoscale_policy_check returns 0. Complexity: O(1).
pub fn autoscale_policy_check_ok(p: &AutoscalePolicy) -> Bool {
  return autoscale_policy_check(p) == 0;
}

/// Human text for a policy check code (0 = "ok"). Complexity: O(1).
pub fn autoscale_policy_error_text(code: Int) -> Str {
  if code == 0 { return "ok"; }
  if code == 1 { return "metric name is empty"; }
  if code == 2 { return "min_replicas is negative"; }
  if code == 3 { return "max_replicas is below min_replicas"; }
  if code == 4 { return "max_replicas exceeds the supported maximum"; }
  if code == 5 { return "up_threshold must exceed down_threshold"; }
  if code == 6 { return "hysteresis margin is negative or wider than the threshold gap"; }
  if code == 7 { return "a cooldown is negative"; }
  if code == 8 { return "breach_threshold is below 1"; }
  if code == 9 { return "step_mode is neither fixed (0) nor bps (1)"; }
  if code == 10 { return "fixed step is below 1"; }
  if code == 11 { return "proportional step is outside [1, 10000] bps"; }
  if code == 12 { return "series_capacity is outside [1, 1000000]"; }
  return "unknown policy code";
}

/// Step in replicas for `replicas` under `p`, always at least 1:
/// mode 0 returns step_fixed; mode 1 returns max(1, replicas * step_bps /
/// 10000) with truncation. Complexity: O(1).
pub fn autoscale_step(p: &AutoscalePolicy, replicas: Int) -> Int {
  var delta = 1;
  if p.step_mode == _ASC_STEP_FIXED {
    delta = p.step_fixed;
  } else {
    delta = _asc_mul_div_bps(replicas, p.step_bps);
  }
  if delta < 1 { delta = 1; }
  return delta;
}

// --------------------------------------------------
//  Decision catalog
// --------------------------------------------------

/// Text for an action code: 0 "none", 1 "scale-up", 2 "scale-down".
/// Complexity: O(1).
pub fn autoscale_action_text(action: Int) -> Str {
  if action == _ASC_ACTION_UP { return "scale-up"; }
  if action == _ASC_ACTION_DOWN { return "scale-down"; }
  return "none";
}

/// Text for a decision reason code (see SPEC.md section 6).
/// Complexity: O(1).
pub fn autoscale_reason_text(code: Int) -> Str {
  if code == _ASC_R_UP { return "scale-up: up threshold breached"; }
  if code == _ASC_R_DOWN { return "scale-down: down threshold breached"; }
  if code == _ASC_R_BAND { return "hold: metric inside hysteresis band"; }
  if code == _ASC_R_STREAK_UP { return "hold: up breach streak below required"; }
  if code == _ASC_R_STREAK_DOWN { return "hold: down breach streak below required"; }
  if code == _ASC_R_COOLDOWN_UP { return "hold: up cooldown active"; }
  if code == _ASC_R_COOLDOWN_DOWN { return "hold: down cooldown active"; }
  if code == _ASC_R_AT_MAX { return "hold: already at max replicas"; }
  if code == _ASC_R_AT_MIN { return "hold: already at min replicas"; }
  if code == _ASC_R_BAD_POLICY { return "refused: invalid policy"; }
  if code == _ASC_R_TICK_OVERFLOW { return "refused: tick counter overflow"; }
  return "unknown reason";
}

// --------------------------------------------------
//  Controller
// --------------------------------------------------

/// Create a controller for `p` with the initial replica count clamped into
/// [min_replicas, max_replicas] (when those bounds are themselves inverted,
/// min_replicas wins after clamping). Cooldowns are treated as satisfied at
/// tick 0. Complexity: O(1).
pub fn autoscale_controller_new(p: AutoscalePolicy, initial_replicas: Int) -> AutoscaleController {
  let cap = p.series_capacity;
  let init_up = _asc_sub_sat(0, p.up_cooldown);
  let init_down = _asc_sub_sat(0, p.down_cooldown);
  var r = initial_replicas;
  if r > p.max_replicas { r = p.max_replicas; }
  if r < p.min_replicas { r = p.min_replicas; }
  return AutoscaleController{
    policy: p;
    series: autoscale_series_new(cap);
    replicas: r;
    ticks: 0;
    last_up_tick: init_up;
    last_down_tick: init_down;
    up_streak: 0;
    down_streak: 0;
    record_tick: Vec[Int].new();
    record_action: Vec[Int].new();
    record_from: Vec[Int].new();
    record_to: Vec[Int].new();
    record_reason: Vec[Int].new();
    record_detail: Vec[Int].new();
  };
}

// Append one decision record (mirrored parallel vectors).
fn _asc_push_record(c: &mut AutoscaleController, tick: Int, action: Int, from_n: Int, to_n: Int, reason: Int, detail: Int) {
  c.record_tick.push(tick);
  c.record_action.push(action);
  c.record_from.push(from_n);
  c.record_to.push(to_n);
  c.record_reason.push(reason);
  c.record_detail.push(detail);
}

// Validate the policy and advance the tick for an accepted sample. Returns 0
// on success; -1 when the tick was refused, in which case a record has been
// appended and no state was advanced.
fn _asc_begin_tick(c: &mut AutoscaleController, value: Int) -> Int {
  if c.ticks >= _ASC_TICK_MAX {
    let t = c.ticks;
    let r0 = c.replicas;
    _asc_push_record(c, t, _ASC_ACTION_NONE, r0, r0, _ASC_R_TICK_OVERFLOW, value);
    return -1;
  }
  let bad = autoscale_policy_check(&c.policy);
  if bad != 0 {
    let t = c.ticks;
    let r0 = c.replicas;
    _asc_push_record(c, t, _ASC_ACTION_NONE, r0, r0, _ASC_R_BAD_POLICY, bad);
    return -1;
  }
  c.ticks = c.ticks + 1;
  autoscale_series_push(&mut c.series, value);
  return 0;
}

// Apply one decision for `observed` (the tick must already be advanced and
// the sample pushed). Returns the action code.
fn _asc_decide(c: &mut AutoscaleController, observed: Int) -> Int {
  let pol = c.policy;
  let t = c.ticks;
  let from = c.replicas;
  var to = from;
  var action = _ASC_ACTION_NONE;
  var reason = _ASC_R_BAND;
  if observed >= pol.up_threshold {
    c.up_streak = c.up_streak + 1;
    c.down_streak = 0;
    if c.up_streak < pol.breach_threshold {
      reason = _ASC_R_STREAK_UP;
    } elif from >= pol.max_replicas {
      reason = _ASC_R_AT_MAX;
    } elif _asc_sub_sat(t, c.last_up_tick) < pol.up_cooldown {
      reason = _ASC_R_COOLDOWN_UP;
    } else {
      let delta = autoscale_step(&pol, from);
      to = _asc_add_sat(from, delta);
      if to > pol.max_replicas { to = pol.max_replicas; }
      c.replicas = to;
      c.last_up_tick = t;
      action = _ASC_ACTION_UP;
      reason = _ASC_R_UP;
    }
  } elif observed <= pol.down_threshold {
    c.down_streak = c.down_streak + 1;
    c.up_streak = 0;
    if c.down_streak < pol.breach_threshold {
      reason = _ASC_R_STREAK_DOWN;
    } elif from <= pol.min_replicas {
      reason = _ASC_R_AT_MIN;
    } elif _asc_sub_sat(t, c.last_down_tick) < pol.down_cooldown {
      reason = _ASC_R_COOLDOWN_DOWN;
    } else {
      let delta2 = autoscale_step(&pol, from);
      to = _asc_sub_sat(from, delta2);
      if to < pol.min_replicas { to = pol.min_replicas; }
      c.replicas = to;
      c.last_down_tick = t;
      action = _ASC_ACTION_DOWN;
      reason = _ASC_R_DOWN;
    }
  } else {
    c.up_streak = 0;
    c.down_streak = 0;
  }
  _asc_push_record(c, t, action, from, to, reason, observed);
  return action;
}

/// Feed one raw metric sample and evaluate the policy on it.
/// Returns the action code (0 none, 1 scale-up, 2 scale-down) or -1 when the
/// tick was refused (invalid policy or tick overflow); a refusal appends a
/// record and leaves all state unchanged. Complexity: O(1) plus one record
/// append.
pub fn autoscale_controller_tick(c: &mut AutoscaleController, value: Int) -> Int {
  if _asc_begin_tick(c, value) != 0 { return -1; }
  return _asc_decide(c, value);
}

/// Feed one raw metric sample, then evaluate the policy on the integer
/// average of the most recent `window` stored samples (including the new
/// one). Same contract as autoscale_controller_tick. Complexity: O(window).
pub fn autoscale_controller_tick_avg(c: &mut AutoscaleController, value: Int, window: Int) -> Int {
  if _asc_begin_tick(c, value) != 0 { return -1; }
  let observed = autoscale_series_avg(&c.series, window);
  return _asc_decide(c, observed);
}

/// Copy of the controller's policy. Complexity: O(1).
pub fn autoscale_controller_policy(c: &AutoscaleController) -> AutoscalePolicy {
  return c.policy;
}

/// Current replica target. Complexity: O(1).
pub fn autoscale_controller_replicas(c: &AutoscaleController) -> Int {
  return c.replicas;
}

/// Number of accepted ticks (refusals do not count). Complexity: O(1).
pub fn autoscale_controller_ticks(c: &AutoscaleController) -> Int {
  return c.ticks;
}

/// Consecutive up-threshold breaches currently standing. Complexity: O(1).
pub fn autoscale_controller_up_streak(c: &AutoscaleController) -> Int {
  return c.up_streak;
}

/// Consecutive down-threshold breaches currently standing. Complexity: O(1).
pub fn autoscale_controller_down_streak(c: &AutoscaleController) -> Int {
  return c.down_streak;
}

/// Tick of the last scale-up action. Complexity: O(1).
pub fn autoscale_controller_last_up_tick(c: &AutoscaleController) -> Int {
  return c.last_up_tick;
}

/// Tick of the last scale-down action. Complexity: O(1).
pub fn autoscale_controller_last_down_tick(c: &AutoscaleController) -> Int {
  return c.last_down_tick;
}

/// Stored samples in the controller's metric series. Complexity: O(1).
pub fn autoscale_controller_series_len(c: &AutoscaleController) -> Int {
  return autoscale_series_len(&c.series);
}

/// Stored controller sample `i` in chronological order (out of range 0).
/// Complexity: O(1).
pub fn autoscale_controller_series_at(c: &AutoscaleController, i: Int) -> Int {
  return autoscale_series_at(&c.series, i);
}

/// Rolling-window average over the controller's series. Complexity: O(window).
pub fn autoscale_controller_series_avg(c: &AutoscaleController, window: Int) -> Int {
  return autoscale_series_avg(&c.series, window);
}

/// Number of decision records (one per attempted tick). Complexity: O(1).
pub fn autoscale_controller_record_count(c: &AutoscaleController) -> Int {
  return c.record_tick.len();
}

// Guarded Int-vector read; out-of-range returns -1.
fn _asc_rec(v: &Vec[Int], i: Int) -> Int {
  if i < 0 || i >= v.len() { return -1; }
  return v[i];
}

/// Record field of record `i` (out of range -1 for tick/action/from/to/
/// reason, and the detail accessor likewise).
pub fn autoscale_controller_record_tick(c: &AutoscaleController, i: Int) -> Int {
  return _asc_rec(&c.record_tick, i);
}

/// Action code of record `i` (0/1/2).
pub fn autoscale_controller_record_action(c: &AutoscaleController, i: Int) -> Int {
  return _asc_rec(&c.record_action, i);
}

/// Replicas before record `i`.
pub fn autoscale_controller_record_from(c: &AutoscaleController, i: Int) -> Int {
  return _asc_rec(&c.record_from, i);
}

/// Replicas after record `i`.
pub fn autoscale_controller_record_to(c: &AutoscaleController, i: Int) -> Int {
  return _asc_rec(&c.record_to, i);
}

/// Reason code of record `i`.
pub fn autoscale_controller_record_reason(c: &AutoscaleController, i: Int) -> Int {
  return _asc_rec(&c.record_reason, i);
}

/// Observed value of record `i` (the raw sample, the window average, or the
/// policy check code when the record is a refusal).
pub fn autoscale_controller_record_detail(c: &AutoscaleController, i: Int) -> Int {
  return _asc_rec(&c.record_detail, i);
}

/// Reason code of the newest record, or -1 when there is none.
/// Complexity: O(1).
pub fn autoscale_controller_last_reason(c: &AutoscaleController) -> Int {
  let n = c.record_reason.len();
  if n == 0 { return -1; }
  return c.record_reason[n - 1];
}
