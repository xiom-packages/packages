// XIOM -- xiom.rate: deterministic rate limiters with explicit clocks
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure deterministic rate-limit policy engine: no clock access, no sleeping,
// no environment access. Every function takes its inputs explicitly,
// including `now_ms`; the caller reads the clock and performs the waiting.
// Free functions only -- XIOM v0.61.x has no methods. All times and durations
// are integer milliseconds and every division truncates toward zero.

module xiom.rate

/// Token bucket: `capacity` tokens, refilled at `refill_per_sec` tokens per
/// second from the last settled millisecond (`last_ms`). Fields are
/// implementation details; construct with rate_bucket_new and read with
/// rate_bucket_tokens / rate_bucket_capacity.
/// Clamped invariants: capacity >= 1, refill_per_sec >= 0, tokens <= capacity.
pub type TokenBucket = {
  capacity: Int;
  tokens: Int;
  refill_per_sec: Int;
  last_ms: Int;
}

/// Create a token bucket with clamped inputs.
/// Params: capacity - bucket size in tokens (clamped to >= 1);
///         refill_per_sec - refill rate in tokens per second (clamped to >= 0);
///         now_ms - caller clock reading that starts the refill clock.
/// Returns: a bucket whose tokens start full and whose last_ms = now_ms.
/// No error path. Complexity: O(1).
pub fn rate_bucket_new(capacity: Int, refill_per_sec: Int, now_ms: Int) -> TokenBucket {
  var cap = capacity;
  if cap < 1 { cap = 1; }
  var refill = refill_per_sec;
  if refill < 0 { refill = 0; }
  return TokenBucket{ capacity: cap; tokens: cap; refill_per_sec: refill; last_ms: now_ms; };
}

/// Settle the refill clock up to now_ms. Time going backwards is a no-op.
///
/// Truncation policy (pinned by the conformance tests):
/// - `elapsed = max(0, now_ms - last_ms)`;
/// - `gained = elapsed * refill_per_sec / 1000` (truncated);
/// - when `refill_per_sec == 0` or the bucket is (or becomes) saturated, the
///   whole elapsed span is consumed: `last_ms = now_ms`;
/// - when `gained == 0`, nothing changes -- the elapsed span is carried, so
///   the first whole token still lands exactly at 1000 / refill_per_sec ms;
/// - otherwise only the milliseconds the granted tokens are worth are
///   consumed: `last_ms = last_ms + gained * 1000 / refill_per_sec`, and the
///   unearned remainder is carried to the next call.
/// Complexity: O(1).
pub fn rate_bucket_refill(b: &mut TokenBucket, now_ms: Int) {
  if now_ms <= b.last_ms { return; }
  let elapsed = now_ms - b.last_ms;
  if b.refill_per_sec <= 0 {
    b.last_ms = now_ms;
    return;
  }
  if b.tokens >= b.capacity {
    b.last_ms = now_ms;
    return;
  }
  let gained = elapsed * b.refill_per_sec / 1000;
  if gained <= 0 { return; }
  if b.tokens + gained >= b.capacity {
    b.tokens = b.capacity;
    b.last_ms = now_ms;
    return;
  }
  b.tokens = b.tokens + gained;
  b.last_ms = b.last_ms + gained * 1000 / b.refill_per_sec;
}

/// Refill up to now_ms and, when `cost <= capacity`, spend `cost` tokens.
/// Params: b - the bucket; now_ms - caller clock reading;
///         cost - tokens requested; `cost <= 0` is always allowed and spends
///         nothing.
/// Returns: true when the cost was spent (or cost <= 0); false when the
/// bucket holds fewer than `cost` tokens, in which case nothing is spent.
/// Complexity: O(1).
pub fn rate_bucket_allow(b: &mut TokenBucket, now_ms: Int, cost: Int) -> Bool {
  rate_bucket_refill(b, now_ms);
  if cost <= 0 { return true; }
  if b.tokens >= cost {
    b.tokens = b.tokens - cost;
    return true;
  }
  return false;
}

/// Tokens currently available. Complexity: O(1).
pub fn rate_bucket_tokens(b: &TokenBucket) -> Int {
  return b.tokens;
}

/// Configured bucket size (always >= 1). Complexity: O(1).
pub fn rate_bucket_capacity(b: &TokenBucket) -> Int {
  return b.capacity;
}

/// Milliseconds until `cost` tokens are affordable at the current rate.
/// Reads the bucket as-is (no refill). Returns 0 when `cost` is already
/// affordable or `cost <= 0`; -1 when `refill_per_sec == 0` and the cost can
/// never be met; otherwise `ceil((cost - tokens) * 1000 / refill_per_sec)`,
/// always rounded up to a whole millisecond. The result is an upper bound
/// while part of an unearned millisecond is still carried in `last_ms`.
/// Complexity: O(1).
pub fn rate_bucket_retry_after_ms(b: &TokenBucket, cost: Int) -> Int {
  if cost <= 0 { return 0; }
  if b.tokens >= cost { return 0; }
  if b.refill_per_sec <= 0 { return -1; }
  let deficit = cost - b.tokens;
  let whole = deficit / b.refill_per_sec;
  let remainder = deficit % b.refill_per_sec;
  var ms = whole * 1000;
  if remainder > 0 {
    ms = ms + (remainder * 1000 + b.refill_per_sec - 1) / b.refill_per_sec;
  }
  return ms;
}

/// Fixed window counter: at most `max_count` admissions per `window_ms` span,
/// rebased to `now_ms` whenever the span has fully elapsed. Fields are
/// implementation details; construct with rate_window_new and read with
/// rate_window_count / rate_window_retry_after_ms.
/// Clamped invariants: window_ms >= 1, max_count >= 1, count <= max_count.
pub type WindowLimit = {
  window_ms: Int;
  max_count: Int;
  start_ms: Int;
  count: Int;
}

/// Create a fixed window with clamped inputs.
/// Params: window_ms - span length in milliseconds (clamped to >= 1);
///         max_count - admissions per span (clamped to >= 1);
///         now_ms - caller clock reading that starts the first span.
/// Returns: a window with count 0 and start_ms = now_ms. No error path.
/// Complexity: O(1).
pub fn rate_window_new(window_ms: Int, max_count: Int, now_ms: Int) -> WindowLimit {
  var span = window_ms;
  if span < 1 { span = 1; }
  var limit = max_count;
  if limit < 1 { limit = 1; }
  return WindowLimit{ window_ms: span; max_count: limit; start_ms: now_ms; count: 0; };
}

/// Admit one call at now_ms against the fixed window.
/// When `now_ms - start_ms >= window_ms` the span is rebased first
/// (`start_ms = now_ms`, `count = 0`); a `now_ms` before `start_ms` never
/// rebases. Then one admission is granted while `count < max_count`.
/// Returns: true when admitted, false when the current span is full.
/// Complexity: O(1).
pub fn rate_window_allow(w: &mut WindowLimit, now_ms: Int) -> Bool {
  if now_ms - w.start_ms >= w.window_ms {
    w.start_ms = now_ms;
    w.count = 0;
  }
  if w.count < w.max_count {
    w.count = w.count + 1;
    return true;
  }
  return false;
}

/// Admissions counted in the current span. Complexity: O(1).
pub fn rate_window_count(w: &WindowLimit) -> Int {
  return w.count;
}

/// Milliseconds until the window admits again.
/// Returns 0 when a call would be admitted now (count below max_count, or the
/// span has fully elapsed); otherwise `start_ms + window_ms - now_ms`.
/// Complexity: O(1).
pub fn rate_window_retry_after_ms(w: &WindowLimit, now_ms: Int) -> Int {
  if w.count < w.max_count { return 0; }
  if now_ms - w.start_ms >= w.window_ms { return 0; }
  return w.start_ms + w.window_ms - now_ms;
}

/// Rebase the window at now_ms: start_ms = now_ms and count = 0.
/// Complexity: O(1).
pub fn rate_window_reset(w: &mut WindowLimit, now_ms: Int) {
  w.start_ms = now_ms;
  w.count = 0;
}
