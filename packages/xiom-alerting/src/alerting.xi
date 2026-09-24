// XIOM -- xiom.alerting: threshold alert rules with breach streaks and firing state
// Port task: replace the xiom.alerting placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure deterministic state machine: no clock access, no I/O, no FFI, no global
// state. The caller supplies every sample (the `value` argument of
// alert_observe, or the whole series of alert_evaluate / alert_transition_count)
// and owns the AlertState. Free functions only -- XIOM v0.61.x has no methods.
//
// Semantics (see SPEC.md for the full table):
//   - a sample breaches when value >= threshold (above = true) or
//     value <= threshold (above = false); equality is always a breach,
//   - `consecutive` consecutive breaching samples fire the alert exactly once
//     (the observe call that fires returns true -- the fired edge),
//   - the first non-breaching sample while firing resolves the alert and
//     counts once; it also clears the breach streak,
//   - a non-breaching sample while not firing just clears the streak,
//   - every later non-breaching sample while not firing changes nothing.

module xiom.alerting

/// Threshold rule: fire when `consecutive` consecutive samples breach.
///
/// All fields are implementation details; construct through alert_rule_new.
/// Invariant: consecutive >= 1 (clamped by the constructor).
pub type AlertRule = {
  threshold: Int;
  above: Bool;
  consecutive: Int;
}

/// Create a threshold rule.
/// Params: threshold - comparison level;
///         above - true: breach when value >= threshold; false: breach when
///                 value <= threshold;
///         consecutive - breaching samples needed to fire (clamped to >= 1).
/// Returns: the clamped rule. No error path. Complexity: O(1).
pub fn alert_rule_new(threshold: Int, above: Bool, consecutive: Int) -> AlertRule {
  var n = consecutive;
  if n < 1 { n = 1; }
  return AlertRule{ threshold: threshold; above: above; consecutive: n; };
}

/// Firing state and lifetime counters for one rule.
///
/// Every field is an internal implementation detail; construct through
/// alert_state_new and read through the alert_* accessors. `breaches` is the
/// current consecutive breach streak (0 while not firing), `firing` is the
/// alert signal, `fired_count` counts fired edges and `resolved_count` counts
/// resolve edges (each at most once per transition).
pub type AlertState = {
  breaches: Int;
  firing: Bool;
  fired_count: Int;
  resolved_count: Int;
}

/// Fresh state: no streak, not firing, zero counters. No error path.
/// Complexity: O(1).
pub fn alert_state_new() -> AlertState {
  return AlertState{ breaches: 0; firing: false; fired_count: 0; resolved_count: 0; };
}

// Breach predicate: equality is a breach in both directions.
fn _alert_is_breach(r: &AlertRule, value: Int) -> Bool {
  if r.above { return value >= r.threshold; }
  return value <= r.threshold;
}

/// Feed one sample to the state machine.
/// Breach: the streak grows by one; when it reaches r.consecutive and the
/// alert is not already firing, firing becomes true, fired_count grows by one
/// and the return value is true (the fired edge). Breaching samples while
/// firing only grow the streak (no new edge).
/// Non-breach while firing: resolved_count grows by one, firing becomes false
/// and the streak resets to 0; the return value is false.
/// Non-breach while not firing: the streak resets to 0 (a no-op when it is
/// already 0); the return value is false.
/// Params: r - the rule; s - the mutable state; value - one sample.
/// Returns: true exactly on the sample that fires the alert.
/// Complexity: O(1).
pub fn alert_observe(r: &AlertRule, s: &mut AlertState, value: Int) -> Bool {
  if _alert_is_breach(r, value) {
    s.breaches = s.breaches + 1;
    if s.breaches >= r.consecutive {
      if !s.firing {
        s.firing = true;
        s.fired_count = s.fired_count + 1;
        return true;
      }
    }
    return false;
  }
  if s.firing {
    s.resolved_count = s.resolved_count + 1;
    s.firing = false;
  }
  s.breaches = 0;
  return false;
}

/// Fold alert_observe over a whole series into a fresh state.
/// Params: r - the rule; values - the samples in observation order.
/// Returns: the final AlertState. An empty series yields alert_state_new().
/// No error path. Complexity: O(n) in values.
pub fn alert_evaluate(r: &AlertRule, values: &Vec[Int]) -> AlertState {
  var s = alert_state_new();
  var i = 0;
  while i < values.len() {
    let v: Int = values[i];
    alert_observe(r, &mut s, v);
    i = i + 1;
  }
  return s;
}

/// Whether the alert is currently firing. Complexity: O(1).
pub fn alert_is_firing(s: &AlertState) -> Bool {
  return s.firing;
}

/// Fired edges so far (transitions into firing). Complexity: O(1).
pub fn alert_fired_count(s: &AlertState) -> Int {
  return s.fired_count;
}

/// Resolve edges so far (transitions out of firing). Complexity: O(1).
pub fn alert_resolved_count(s: &AlertState) -> Int {
  return s.resolved_count;
}

/// Current consecutive breach streak; 0 while not firing.
/// Complexity: O(1).
pub fn alert_breaches(s: &AlertState) -> Int {
  return s.breaches;
}

/// Number of fired edges across a series (the count of alert_observe calls
/// that would return true, in order). An empty series has zero edges.
/// Params: r - the rule; values - the samples in observation order.
/// No error path. Complexity: O(n) in values.
pub fn alert_transition_count(r: &AlertRule, values: &Vec[Int]) -> Int {
  var s = alert_state_new();
  var edges = 0;
  var i = 0;
  while i < values.len() {
    let v: Int = values[i];
    let fired = alert_observe(r, &mut s, v);
    if fired { edges = edges + 1; }
    i = i + 1;
  }
  return edges;
}
