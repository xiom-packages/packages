// XIOM -- xiom.jev.retry: bounded retry policy for transient failures
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// M2 chunk 1 (ROADMAP "retry policy for 429/529/503 with bounded backoff
// (mirror S9)"). The reference client (browser-use/jev-ultrafast, see
// SPEC.md section 2/S9) retries the System One call on the transient HTTP
// statuses 429 (rate limited), 503 (unavailable) and 529 (overloaded) with a
// bounded exponential backoff. This module is the PURE decision core of that
// policy: it classifies a status and computes the deterministic delay, so the
// whole policy is offline-testable. The transport module (xiom.jev.client)
// owns the actual sleep + loop and adds no policy of its own.
//
// Determinism (house rule): the delay is a pure integer function of the retry
// number (no clock, no randomness, no jitter), so the same attempt always
// yields the same milliseconds on every run and platform. Jitter, when a
// caller wants it, is layered on top from caller-supplied entropy like
// xiom.jev.selection's sample-by-probability.
//
//   retry_is_retryable: 1 for 429/503/529, else 0.
//   retry_backoff_millis(attempt, base, cap): base * 2^(attempt-1), clamped
//     to cap. `attempt` is the 1-based retry number (the first retry is
//     attempt 1 -> base). attempt < 1 or base < 1 -> 0. cap < 1 means "no
//     cap"; growth is still bounded (2^39 * base) so the value cannot
//     overflow a 63-bit Int. The computed delay never exceeds cap.
//
// Defaults mirror the reference client's intent: four attempts total (the
// initial call plus three retries), a 500 ms base and a 30 s cap.

module xiom.jev.retry

// --------------------------------------------------
//  Defaults
// --------------------------------------------------

/// default_max_attempts is the total number of attempts (initial + retries)
/// the client makes before surfacing the typed HttpStatus.
/// Complexity: O(1). Pure.
pub fn default_max_attempts() -> Int {
  return 4;
}

/// default_base_millis is the first backoff delay in milliseconds.
/// Complexity: O(1). Pure.
pub fn default_base_millis() -> Int {
  return 500;
}

/// default_cap_millis is the maximum backoff delay in milliseconds.
/// Complexity: O(1). Pure.
pub fn default_cap_millis() -> Int {
  return 30000;
}

// --------------------------------------------------
//  Classification
// --------------------------------------------------

/// retry_is_retryable is 1 when a non-2xx status is a transient condition the
/// policy retries (429 rate limited, 503 unavailable, 529 overloaded), else
/// 0. Complexity: O(1). Pure.
pub fn retry_is_retryable(status: Int) -> Int {
  if status == 429 { return 1; }
  if status == 503 { return 1; }
  if status == 529 { return 1; }
  return 0;
}

// --------------------------------------------------
//  Backoff
// --------------------------------------------------

/// retry_backoff_millis is the deterministic delay before retry number
/// `attempt` (1-based): `base_millis * 2^(attempt-1)` clamped to `cap_millis`
/// (a cap < 1 means no cap, growth still bounded). Returns 0 when attempt < 1
/// or base_millis < 1. Complexity: O(attempt), bounded to 40 doublings.
/// Pure.
pub fn retry_backoff_millis(attempt: Int, base_millis: Int, cap_millis: Int) -> Int {
  if attempt < 1 { return 0; }
  if base_millis < 1 { return 0; }
  var limit: Int = attempt;
  if limit > 40 { limit = 40; }
  var delay: Int = base_millis;
  var k: Int = 1;
  while k < limit {
    if cap_millis >= 1 && delay >= cap_millis { break; }
    delay = delay + delay;
    k = k + 1;
  }
  if cap_millis >= 1 && delay > cap_millis { delay = cap_millis; }
  return delay;
}
