// XIOM -- xiom.retry: retry policies, exponential backoff, circuit breaker
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure deterministic policy engine: no sleeping, no clock access, no
// environment access. Every function takes its inputs explicitly (including
// `now_secs` where time matters); the caller performs the sleeping and the
// wiring. Free functions only -- XIOM v0.61.x has no methods.

module xiom.retry

/// Failure budget and backoff policy.
///
/// All fields are implementation details; construct through retry_new and
/// read through the accessors below. Clamped invariants: max_attempts >= 1,
/// base_delay_secs >= 0, factor >= 1, max_delay_secs >= base_delay_secs.
pub type RetryPolicy = {
  max_attempts: Int;
  base_delay_secs: Int;
  factor: Int;
  max_delay_secs: Int;
}

/// Create a retry policy with clamped inputs.
/// Params: max_attempts - total attempt budget (clamped to >= 1);
///         base_delay_secs - delay before the first retry (clamped to >= 0);
///         factor - exponential multiplier (clamped to >= 1);
///         max_delay_secs - delay ceiling (clamped to >= base_delay_secs).
/// Returns: the clamped policy. No error path.
/// Complexity: O(1).
pub fn retry_new(max_attempts: Int, base_delay_secs: Int, factor: Int, max_delay_secs: Int) -> RetryPolicy {
  var attempts = max_attempts;
  if attempts < 1 { attempts = 1; }
  var base = base_delay_secs;
  if base < 0 { base = 0; }
  var mult = factor;
  if mult < 1 { mult = 1; }
  var ceiling = max_delay_secs;
  if ceiling < base { ceiling = base; }
  return RetryPolicy{ max_attempts: attempts; base_delay_secs: base; factor: mult; max_delay_secs: ceiling; };
}

/// Total attempt budget (always >= 1). Complexity: O(1).
pub fn retry_max_attempts(p: &RetryPolicy) -> Int {
  return p.max_attempts;
}

/// Delay before the first retry, in seconds (always >= 0). Complexity: O(1).
pub fn retry_base_delay_secs(p: &RetryPolicy) -> Int {
  return p.base_delay_secs;
}

/// Exponential multiplier (always >= 1). Complexity: O(1).
pub fn retry_factor(p: &RetryPolicy) -> Int {
  return p.factor;
}

/// Delay ceiling in seconds (always >= base_delay_secs). Complexity: O(1).
pub fn retry_max_delay_secs(p: &RetryPolicy) -> Int {
  return p.max_delay_secs;
}

/// Delay before retry number `attempt` (1-based), in seconds:
/// `base_delay_secs * factor^(attempt-1)`, clamped to `max_delay_secs`.
/// Attempt values below 1 are treated as the first attempt (base delay).
/// The loop stops multiplying as soon as the delay reaches the ceiling, so
/// the product can never overflow and the work is bounded by the number of
/// doublings below the ceiling, not by `attempt`.
/// Params: p - the policy; attempt - 1-based retry number.
/// Complexity: O(min(attempt, log(max_delay / base_delay))) with factor > 1.
pub fn retry_delay_secs(p: &RetryPolicy, attempt: Int) -> Int {
  var n = attempt;
  if n < 1 { n = 1; }
  var delay = p.base_delay_secs;
  if p.factor <= 1 {
    if delay > p.max_delay_secs { delay = p.max_delay_secs; }
    return delay;
  }
  var step = 1;
  while step < n {
    if delay >= p.max_delay_secs { break; }
    if delay == 0 { break; }
    if delay > p.max_delay_secs / p.factor {
      delay = p.max_delay_secs;
      break;
    }
    delay = delay * p.factor;
    if delay > p.max_delay_secs { delay = p.max_delay_secs; }
    step = step + 1;
  }
  if delay > p.max_delay_secs { delay = p.max_delay_secs; }
  return delay;
}

/// True when one more attempt is allowed: attempts_done < max_attempts.
/// Complexity: O(1).
pub fn retry_should_retry(p: &RetryPolicy, attempts_done: Int) -> Bool {
  return attempts_done < p.max_attempts;
}

// Deterministic small integer hash: mixes seed with attempt (xorshift-style)
// and returns a non-negative value. All shifts operate on non-negative
// values, so the result is fully defined and reproducible.
fn _retry_jitter_hash(seed: Int, attempt: Int) -> Int {
  var h = seed * 2654435761 + attempt * 40503;
  h = h ^ (h >> 13);
  h = h & 0x00FFFFFFFFFFFFFF;
  h = h ^ (h << 7);
  h = h ^ (h >> 17);
  h = h & 0x7FFFFFFFFFFFFFFF;
  return h;
}

/// Deterministic jittered delay for retry number `attempt`.
/// The jitter comes only from `seed` and `attempt` -- there is no randomness
/// source -- and the result lies in [delay/2, delay] where
/// delay = retry_delay_secs(p, attempt). Same inputs always produce the same
/// output, so callers can reproduce a run exactly.
/// Params: p - the policy; attempt - 1-based retry number; seed - caller seed.
/// Complexity: O(retry_delay_secs).
pub fn retry_jittered_delay(p: &RetryPolicy, attempt: Int, seed: Int) -> Int {
  let delay = retry_delay_secs(p, attempt);
  let half = delay / 2;
  let span = delay - half + 1;
  let mixed = _retry_jitter_hash(seed, attempt);
  let offset = mixed % span;
  return half + offset;
}

/// Attempt counter and last computed delay for a caller-driven retry loop.
pub type RetryState = {
  attempts_done: Int;
  last_delay_secs: Int;
}

/// Fresh state: zero attempts, zero last delay. Complexity: O(1).
pub fn retry_state_new() -> RetryState {
  return RetryState{ attempts_done: 0; last_delay_secs: 0; };
}

/// Advance the state by one attempt.
/// While attempts_done < max_attempts: increments attempts_done, stores the
/// delay for the new attempt in last_delay_secs and returns Some(delay).
/// Otherwise returns None and changes nothing (attempts_done stays capped at
/// the budget, last_delay_secs keeps its previous value).
/// Params: s - the mutable state; p - the policy.
/// Complexity: O(retry_delay_secs).
pub fn retry_state_next(s: &mut RetryState, p: &RetryPolicy) -> Option[Int] {
  if s.attempts_done >= p.max_attempts {
    return None;
  }
  s.attempts_done = s.attempts_done + 1;
  let delay = retry_delay_secs(p, s.attempts_done);
  s.last_delay_secs = delay;
  return Some(delay);
}

/// Attempts consumed so far. Complexity: O(1).
pub fn retry_state_attempts(s: &RetryState) -> Int {
  return s.attempts_done;
}

/// Delay stored by the most recent successful retry_state_next (0 before the
/// first call). Complexity: O(1).
pub fn retry_state_last_delay(s: &RetryState) -> Int {
  return s.last_delay_secs;
}

/// Reset to the fresh state: zero attempts, zero last delay. Complexity: O(1).
pub fn retry_state_reset(s: &mut RetryState) {
  s.attempts_done = 0;
  s.last_delay_secs = 0;
}

/// Circuit breaker. `state` is 0 = closed, 1 = open. Half-open is derived,
/// not stored: an open breaker whose cooldown has elapsed is half-open and
/// admits a single probe call.
pub type CircuitBreaker = {
  state: Int;
  failures: Int;
  failure_threshold: Int;
  reset_after_secs: Int;
  opened_at: Int;
  trips: Int;
}

/// Create a closed circuit breaker.
/// Params: failure_threshold - consecutive failures that trip it
///         (clamped to >= 1);
///         reset_after_secs - cooldown before a probe (clamped to >= 0).
/// Returns: closed breaker with zero failures, zero trips, opened_at 0.
/// Complexity: O(1).
pub fn circuit_new(failure_threshold: Int, reset_after_secs: Int) -> CircuitBreaker {
  var threshold = failure_threshold;
  if threshold < 1 { threshold = 1; }
  var window = reset_after_secs;
  if window < 0 { window = 0; }
  return CircuitBreaker{ state: 0; failures: 0; failure_threshold: threshold; reset_after_secs: window; opened_at: 0; trips: 0; };
}

/// Breaker state: 0 = closed, 1 = open. Complexity: O(1).
pub fn circuit_state(c: &CircuitBreaker) -> Int {
  return c.state;
}

/// True when a call is allowed now. Closed: always true. Open: true only once
/// the probe window is reached (now_secs >= opened_at + reset_after_secs).
/// Complexity: O(1).
pub fn circuit_allow(c: &CircuitBreaker, now_secs: Int) -> Bool {
  if c.state == 0 { return true; }
  return now_secs >= c.opened_at + c.reset_after_secs;
}

/// True when the breaker is open AND the probe window has been reached, i.e.
/// the next allowed call is the half-open probe. Complexity: O(1).
pub fn circuit_is_half_open(c: &CircuitBreaker, now_secs: Int) -> Bool {
  if c.state == 0 { return false; }
  return now_secs >= c.opened_at + c.reset_after_secs;
}

/// Record a successful call: failures = 0, state = closed.
/// `now_secs` is accepted for call-site symmetry and stored as the closing
/// time in `opened_at`; the field is only read while the breaker is open, so
/// this has no effect on allow/half-open decisions.
pub fn circuit_record_success(c: &mut CircuitBreaker, now_secs: Int) {
  c.failures = 0;
  c.state = 0;
  c.opened_at = now_secs;
}

/// Record a failed call.
/// Closed: increments failures and, once failures >= failure_threshold, opens
/// the breaker (state = 1, opened_at = now_secs, trips + 1).
/// Open, probe window reached (now_secs >= opened_at + reset_after_secs): the
/// probe failed -- opened_at = now_secs and trips + 1; the breaker stays open
/// and `failures` is left unchanged.
/// Open, before the window: nothing changes. Documented behaviour: a stray
/// failure report at this point cannot extend the cooldown or move opened_at
/// (failures is frozen while open).
pub fn circuit_record_failure(c: &mut CircuitBreaker, now_secs: Int) {
  if c.state == 0 {
    c.failures = c.failures + 1;
    if c.failures >= c.failure_threshold {
      c.state = 1;
      c.opened_at = now_secs;
      c.trips = c.trips + 1;
    }
    return;
  }
  if now_secs >= c.opened_at + c.reset_after_secs {
    c.opened_at = now_secs;
    c.trips = c.trips + 1;
  }
}

/// Consecutive failures since the last success or reset; frozen while open
/// (see circuit_record_failure). Complexity: O(1).
pub fn circuit_failures(c: &CircuitBreaker) -> Int {
  return c.failures;
}

/// Times the breaker opened: the initial trip plus every failed probe.
/// Complexity: O(1).
pub fn circuit_trips(c: &CircuitBreaker) -> Int {
  return c.trips;
}

/// Full reset: closed, zero failures, zero trips, opened_at 0. Complexity: O(1).
pub fn circuit_reset(c: &mut CircuitBreaker) {
  c.state = 0;
  c.failures = 0;
  c.opened_at = 0;
  c.trips = 0;
}
