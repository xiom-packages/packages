// XIOM -- xiom.timeout: deterministic deadline and timeout arithmetic
// Port task: replace the xiom.timeout placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure deterministic arithmetic engine: no clock access, no sleeping, no
// environment access. Every function takes its inputs explicitly -- the
// caller reads the clock and passes `now_ms` / `start_ms` in, so the same
// inputs always produce the same outputs. Free functions only: XIOM v0.61.x
// has no methods. All durations and timestamps are integer milliseconds.

module xiom.timeout

/// Timeout budget policy: a default and a ceiling, in milliseconds.
/// Fields are implementation details; construct with timeout_new and read
/// with timeout_default_ms / timeout_max_ms.
/// Clamped invariants: default_ms >= 0, max_ms >= default_ms.
pub type TimeoutPolicy = {
  default_ms: Int;
  max_ms: Int;
}

/// A running deadline: the instant it started plus its budget, in
/// milliseconds. Fields are implementation details; construct with
/// deadline_new or deadline_from_policy.
/// Clamped invariant: budget_ms >= 0.
pub type Deadline = {
  start_ms: Int;
  budget_ms: Int;
}

/// Create a timeout policy with clamped inputs.
/// Params: default_ms - budget used when a request is negative (clamped to >= 0);
///         max_ms - ceiling for any requested budget (clamped to >= default_ms).
/// Returns: the clamped policy. No error path.
/// Complexity: O(1).
pub fn timeout_new(default_ms: Int, max_ms: Int) -> TimeoutPolicy {
  var fallback = default_ms;
  if fallback < 0 { fallback = 0; }
  var ceiling = max_ms;
  if ceiling < fallback { ceiling = fallback; }
  return TimeoutPolicy{ default_ms: fallback; max_ms: ceiling; };
}

/// Default budget in milliseconds (always >= 0). Complexity: O(1).
pub fn timeout_default_ms(p: &TimeoutPolicy) -> Int {
  return p.default_ms;
}

/// Maximum budget in milliseconds (always >= default_ms). Complexity: O(1).
pub fn timeout_max_ms(p: &TimeoutPolicy) -> Int {
  return p.max_ms;
}

/// Effective budget for one request, in milliseconds.
/// requested_ms < 0 selects the policy default; otherwise the result is
/// min(requested_ms, max_ms). Complexity: O(1).
pub fn timeout_effective_ms(p: &TimeoutPolicy, requested_ms: Int) -> Int {
  if requested_ms < 0 { return p.default_ms; }
  if requested_ms > p.max_ms { return p.max_ms; }
  return requested_ms;
}

/// Create a deadline starting at start_ms with the given budget.
/// Params: start_ms - caller clock reading when the deadline starts;
///         budget_ms - allowed duration (clamped to >= 0).
/// Returns: the clamped deadline. No error path.
/// Complexity: O(1).
pub fn deadline_new(start_ms: Int, budget_ms: Int) -> Deadline {
  var budget = budget_ms;
  if budget < 0 { budget = 0; }
  return Deadline{ start_ms: start_ms; budget_ms: budget; };
}

/// Create a deadline whose budget is the policy-effective value for the
/// request. Params: p - the policy; start_ms - caller clock reading;
/// requested_ms - requested budget, negative to select the default.
/// Returns: deadline_new(start_ms, timeout_effective_ms(p, requested_ms)).
/// Complexity: O(1).
pub fn deadline_from_policy(p: &TimeoutPolicy, start_ms: Int, requested_ms: Int) -> Deadline {
  return deadline_new(start_ms, timeout_effective_ms(p, requested_ms));
}

/// Milliseconds left before expiry: max(0, start_ms + budget_ms - now_ms).
/// now_ms <= start_ms returns the full budget plus the lead time. The
/// arithmetic never forms start + budget or budget - used without a guard,
/// so large budgets stay exact. Complexity: O(1).
pub fn deadline_remaining_ms(d: &Deadline, now_ms: Int) -> Int {
  if now_ms <= d.start_ms {
    let lead = d.start_ms - now_ms;
    return d.budget_ms + lead;
  }
  let used = now_ms - d.start_ms;
  if used >= d.budget_ms { return 0; }
  return d.budget_ms - used;
}

/// True when now_ms is at or past start_ms + budget_ms, i.e. no time is left.
/// Complexity: O(1).
pub fn deadline_expired(d: &Deadline, now_ms: Int) -> Bool {
  return deadline_remaining_ms(d, now_ms) == 0;
}

/// Milliseconds elapsed since the deadline started:
/// max(0, now_ms - start_ms). The value keeps growing after the budget is
/// spent (it is not clamped to budget_ms); it is clamped at 0 for now_ms at
/// or before start_ms. Complexity: O(1).
pub fn deadline_elapsed_ms(d: &Deadline, now_ms: Int) -> Int {
  if now_ms <= d.start_ms { return 0; }
  return now_ms - d.start_ms;
}

/// Return a new deadline with the same start and budget_ms + extra_ms,
/// clamped to >= 0. extra_ms may be negative to shrink the budget; shrinking
/// past zero yields a zero budget (already expired). The original deadline
/// value is unchanged. Complexity: O(1).
pub fn deadline_extend(d: &Deadline, extra_ms: Int) -> Deadline {
  var budget = d.budget_ms + extra_ms;
  if budget < 0 { budget = 0; }
  return Deadline{ start_ms: d.start_ms; budget_ms: budget; };
}

/// Return a new deadline that starts at now_ms with the given budget
/// (clamped to >= 0). The deadline passed in is the value being reset; it is
/// unchanged. Complexity: O(1).
pub fn deadline_reset(d: &Deadline, now_ms: Int, budget_ms: Int) -> Deadline {
  return deadline_new(now_ms, budget_ms);
}

/// Elapsed fraction of the deadline in permille (0..1000), clamped.
/// 0 at or before start_ms; 1000 at or after expiry; in between it is
/// elapsed * 1000 / (elapsed + remaining), truncated toward zero.
/// Complexity: O(1).
pub fn deadline_progress_permille(d: &Deadline, now_ms: Int) -> Int {
  let remaining = deadline_remaining_ms(d, now_ms);
  if remaining == 0 { return 1000; }
  let elapsed = deadline_elapsed_ms(d, now_ms);
  if elapsed == 0 { return 0; }
  let total = elapsed + remaining;
  var permille = (elapsed * 1000) / total;
  if permille < 0 { permille = 0; }
  if permille > 1000 { permille = 1000; }
  return permille;
}
