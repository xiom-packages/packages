// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.k8s.rolling: rolling-update replica math
// Port task: replace the xiom.k8s placeholder with a real, tested, pure-XIOM
// package (no API server, no networking, no FFI).
//
// Pure integer model of Deployment rolling updates:
//   * maxSurge / maxUnavailable are absolute counts or percentages;
//     percentages round up for maxSurge and down for maxUnavailable
//     (the Kubernetes rounding rule);
//   * one round starts up to maxSurge new pods plus replacements for any
//     capacity deficit, then retires up to maxUnavailable old pods plus one
//     per new pod above the desired count, so the total replica count stays
//     inside [desired - maxUnavailable, desired + maxSurge];
//   * the schedule records the new-replica count after every round and ends
//     exactly at `desired`;
//   * the simulation is bounded by K8S_ROLLING_MAX_ROUNDS and every loop is
//     deterministic (no clock, no randomness).
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err are constructed
// only inside the _r_* leaf helpers; no Vec[Float64] (integer millicores /
// whole replicas only); no Vec[StructType].

module xiom.k8s.rolling

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Bound on rolling-update rounds (2 * the 256-object cluster limit).
pub const K8S_ROLLING_MAX_ROUNDS: Int = 1024;

/// Default maxSurge percentage for new Deployments.
pub const K8S_ROLLING_DEFAULT_SURGE_PCT: Int = 25;

/// Default maxUnavailable percentage for new Deployments.
pub const K8S_ROLLING_DEFAULT_UNAVAILABLE_PCT: Int = 25;

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only)
// ---------------------------------------------------------------------------

fn _r_ok_vec(v: Vec[Int]) -> Result[Vec[Int], Str] { return Ok(v); }
fn _r_err_vec(m: Str) -> Result[Vec[Int], Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Strategy resolution
// ---------------------------------------------------------------------------

/// Resolve one strategy term: the absolute `amount` when `is_percent` is
/// false, otherwise `amount` percent of `desired` rounded up (round_up) or
/// down (truncating). Negative inputs return -1.
/// Complexity: O(1).
pub fn rolling_resolve(desired: Int, amount: Int, is_percent: Bool, round_up: Bool) -> Int {
  if desired < 0 || amount < 0 { return -1; }
  if !is_percent { return amount; }
  let product = desired * amount;
  if round_up { return (product + 99) / 100; }
  return product / 100;
}

/// maxSurge replica count: percentages round up. Complexity: O(1).
pub fn rolling_surge(desired: Int, amount: Int, is_percent: Bool) -> Int {
  return rolling_resolve(desired, amount, is_percent, true);
}

/// maxUnavailable replica count: percentages round down. Complexity: O(1).
pub fn rolling_unavailable(desired: Int, amount: Int, is_percent: Bool) -> Int {
  return rolling_resolve(desired, amount, is_percent, false);
}

/// True when a resolved strategy can progress: both terms >= 0 and not both
/// zero. Complexity: O(1).
pub fn rolling_valid(surge: Int, unavail: Int) -> Bool {
  if surge < 0 || unavail < 0 { return false; }
  return surge + unavail > 0;
}

// ---------------------------------------------------------------------------
// Round simulation
// ---------------------------------------------------------------------------

/// New-replica count after each round of a rolling update that replaces
/// `desired` old replicas with `desired` new ones, given resolved counts.
/// The final schedule entry is always `desired`.
/// Errors: "rolling: desired replicas must be >= 0", "rolling: maxSurge must
/// be >= 0", "rolling: maxUnavailable must be >= 0" or "rolling: maxSurge and
/// maxUnavailable cannot both be zero".
/// Complexity: O(rounds), rounds <= K8S_ROLLING_MAX_ROUNDS.
pub fn rolling_schedule(desired: Int, surge: Int, unavail: Int) -> Result[Vec[Int], Str] {
  if desired < 0 { return _r_err_vec("rolling: desired replicas must be >= 0"); }
  if surge < 0 { return _r_err_vec("rolling: maxSurge must be >= 0"); }
  if unavail < 0 { return _r_err_vec("rolling: maxUnavailable must be >= 0"); }
  if surge + unavail == 0 {
    if desired == 0 { return _r_ok_vec(Vec[Int].new()); }
    return _r_err_vec("rolling: maxSurge and maxUnavailable cannot both be zero");
  }
  var out = Vec[Int].new();
  var old = desired;
  var fresh = 0;
  var rounds = 0;
  while (old > 0 || fresh < desired) && rounds < K8S_ROLLING_MAX_ROUNDS {
    // Create phase: refill a capacity deficit first, then use maxSurge.
    var add = desired - fresh;
    let room = desired + surge - (old + fresh);
    if add > room { add = room; }
    var add_cap = surge;
    let deficit = desired - (old + fresh);
    if deficit > 0 { add_cap = surge + deficit; }
    if add > add_cap { add = add_cap; }
    if add < 0 { add = 0; }
    fresh = fresh + add;
    // Retire phase: maxUnavailable plus one per new pod above the desired
    // count (a ready replacement frees an old pod).
    var rem = old;
    var delete_cap = unavail;
    let surplus = old + fresh - desired;
    if surplus > 0 { delete_cap = unavail + surplus; }
    if rem > delete_cap { rem = delete_cap; }
    let avail_cap = old + fresh - (desired - unavail);
    if rem > avail_cap { rem = avail_cap; }
    if rem < 0 { rem = 0; }
    old = old - rem;
    if add == 0 && rem == 0 {
      return _r_err_vec("rolling: no progress possible");
    }
    out.push(fresh);
    rounds = rounds + 1;
  }
  if old > 0 || fresh < desired {
    return _r_err_vec("rolling: no progress possible");
  }
  return _r_ok_vec(out);
}

/// Number of rounds required, or -1 when the strategy cannot progress.
/// Complexity: O(rounds).
pub fn rolling_rounds(desired: Int, surge: Int, unavail: Int) -> Int {
  match rolling_schedule(desired, surge, unavail) {
    Ok(v) => { return v.len(); },
    Err(_) => { return -1; },
  }
  return -1;
}
