// XIOM -- xiom.rate: deterministic rate limiters with explicit clocks
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure deterministic rate-limit policy engine: no clock access, no sleeping,
// no environment access. Every function takes its inputs explicitly,
// including `now_ms`; the caller reads the clock and performs the waiting.
// Free functions only -- XIOM v0.61.x has no methods. All times and durations
// are integer milliseconds and every division truncates toward zero.
//
// Keyed layer: KeyedBuckets / KeyedWindows keep one existing limiter per Str
// key, created on first use and bounded by rate_keyed_prune /
// rate_window_keyed_prune. Every admission decision delegates to the
// primitives below; the keyed code adds lookup, bookkeeping and memory
// hygiene only.

module xiom.rate

use xiom.string;

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
pub fn rate_bucket_refill(b: &mut TokenBucket, now_ms: Int)
  ensures: b.capacity >= 1;
  ensures: b.tokens >= 0 && b.tokens <= b.capacity;
{
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
pub fn rate_bucket_allow(b: &mut TokenBucket, now_ms: Int, cost: Int) -> Bool
  ensures: b.tokens >= 0 && b.tokens <= b.capacity;
  ensures: result && cost > 0 => b.tokens >= b.tokens@pre - cost;
  ensures: result && cost <= 0 => b.tokens >= b.tokens@pre;
{
  rate_bucket_refill(b, now_ms);
  if cost <= 0 { return true; }
  if b.tokens >= cost {
    b.tokens = b.tokens - cost;
    return true;
  }
  return false;
}

/// Tokens currently available. Complexity: O(1).
pub fn rate_bucket_tokens(b: &TokenBucket) -> Int
  ensures: result >= 0 && result <= b.capacity;
{
  return b.tokens;
}

/// Configured bucket size (always >= 1). Complexity: O(1).
pub fn rate_bucket_capacity(b: &TokenBucket) -> Int
  ensures: result >= 1;
{
  return b.capacity;
}

/// Milliseconds until `cost` tokens are affordable at the current rate.
/// Reads the bucket as-is (no refill). Returns 0 when `cost` is already
/// affordable or `cost <= 0`; -1 when `refill_per_sec == 0` and the cost can
/// never be met; otherwise `ceil((cost - tokens) * 1000 / refill_per_sec)`,
/// always rounded up to a whole millisecond. The result is an upper bound
/// while part of an unearned millisecond is still carried in `last_ms`.
/// Complexity: O(1).
pub fn rate_bucket_retry_after_ms(b: &TokenBucket, cost: Int) -> Int
  ensures: cost <= 0 => result == 0;
  ensures: b.tokens >= cost => result == 0;
{
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
pub fn rate_window_allow(w: &mut WindowLimit, now_ms: Int) -> Bool
  ensures: w.count >= 0 && w.count <= w.max_count;
  ensures: result => w.count >= 1;
{
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
pub fn rate_window_count(w: &WindowLimit) -> Int
  ensures: result >= 0 && result <= w.max_count;
{
  return w.count;
}

/// Milliseconds until the window admits again.
/// Returns 0 when a call would be admitted now (count below max_count, or the
/// span has fully elapsed); otherwise `start_ms + window_ms - now_ms`.
/// Complexity: O(1).
pub fn rate_window_retry_after_ms(w: &WindowLimit, now_ms: Int) -> Int
  ensures: result >= 0;
{
  if w.count < w.max_count { return 0; }
  if now_ms - w.start_ms >= w.window_ms { return 0; }
  return w.start_ms + w.window_ms - now_ms;
}

/// Rebase the window at now_ms: start_ms = now_ms and count = 0.
/// Complexity: O(1).
pub fn rate_window_reset(w: &mut WindowLimit, now_ms: Int)
  ensures: w.count == 0;
{
  w.start_ms = now_ms;
  w.count = 0;
}

// ============================================================================
// Keyed layer -- one limiter per string key
// ============================================================================
//
// KeyedBuckets / KeyedWindows own a linear Vec of (key, limiter) entries.
// Lookups compare keys byte-wise through `str_compare`, so any Str value is a
// valid key and no hashing is involved. Entries are created on first use with
// a full limiter and are only removed explicitly or by prune, which bounds
// memory when keys come from untrusted callers. Every admission decision
// delegates to the primitives above; the keyed layer adds lookup, bookkeeping
// and hygiene only.

/// One keyed token bucket: `key` is the caller identity and `bucket` is a
/// plain TokenBucket owned by value.
pub type KeyedBucketEntry = {
  key: Str;
  bucket: TokenBucket;
}

/// A set of token buckets keyed by Str sharing one capacity and refill rate.
/// Fields are implementation details; construct with rate_keyed_new and use
/// the rate_keyed_* functions.
pub type KeyedBuckets = {
  entries: Vec[KeyedBucketEntry];
  capacity: Int;
  refill_per_sec: Int;
}

/// One keyed fixed window: `key` is the caller identity and `window` is a
/// plain WindowLimit owned by value.
pub type KeyedWindowEntry = {
  key: Str;
  window: WindowLimit;
}

/// A set of fixed windows keyed by Str sharing one span and limit. Fields are
/// implementation details; construct with rate_window_keyed_new and use the
/// rate_window_keyed_* functions.
pub type KeyedWindows = {
  entries: Vec[KeyedWindowEntry];
  window_ms: Int;
  max_count: Int;
}

/// Entry index for `key`, or -1 when absent. Linear scan; keys compare
/// byte-wise through str_compare. Complexity: O(n).
fn _keyed_find(k: &KeyedBuckets, key: Str) -> Int {
  var i = 0;
  while i < k.entries.len() {
    if string.str_compare(k.entries[i].key, key) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Entry index for `key`, or -1 when absent. Complexity: O(n).
fn _window_keyed_find(w: &KeyedWindows, key: Str) -> Int {
  var i = 0;
  while i < w.entries.len() {
    if string.str_compare(w.entries[i].key, key) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Create an empty keyed bucket store with the constructor policy of
/// rate_bucket_new: `capacity` clamps to >= 1 and `refill_per_sec` to >= 0.
/// Every bucket created for a new key inherits this capacity and rate and
/// starts full at the caller's now_ms.
/// Params: capacity - per-key bucket size in tokens;
///         refill_per_sec - per-key refill rate in tokens per second.
/// Returns: a KeyedBuckets with no entries. No error path.
/// Complexity: O(1) + one empty Vec.
pub fn rate_keyed_new(capacity: Int, refill_per_sec: Int) -> KeyedBuckets {
  let template = rate_bucket_new(capacity, refill_per_sec, 0);
  return KeyedBuckets{
    entries: Vec[KeyedBucketEntry].new();
    capacity: template.capacity;
    refill_per_sec: template.refill_per_sec;
  };
}

/// Admit one call for `key` at now_ms. An unknown key is created on first use
/// as a full bucket at now_ms, so a key's first call always succeeds; known
/// keys are settled with rate_bucket_refill and then spend one token through
/// rate_bucket_allow.
/// Params: k - the keyed store; key - caller identity; now_ms - caller clock.
/// Returns: true when admitted, false when that key's bucket is empty after
/// refill. Complexity: O(n) lookup + O(1) amortized insert.
pub fn rate_keyed_allow(k: &mut KeyedBuckets, key: Str, now_ms: Int) -> Bool {
  let at = _keyed_find(k, key);
  if at >= 0 {
    var b = k.entries[at].bucket;
    rate_bucket_refill(&mut b, now_ms);
    let admitted = rate_bucket_allow(&mut b, now_ms, 1);
    k.entries[at].bucket = b;
    return admitted;
  }
  var fresh = rate_bucket_new(k.capacity, k.refill_per_sec, now_ms);
  let created = rate_bucket_allow(&mut fresh, now_ms, 1);
  k.entries.push(KeyedBucketEntry{ key: key; bucket: fresh; });
  return created;
}

/// Tokens available to `key` after settling at now_ms. The probe works on a
/// copy of the stored bucket, so reading tokens never advances that key.
/// Unknown keys report `capacity` (a bucket created now would be full).
/// Complexity: O(n) lookup + O(1).
pub fn rate_keyed_tokens(k: &KeyedBuckets, key: Str, now_ms: Int) -> Int
  ensures: result >= 0 && result <= k.capacity;
{
  let at = _keyed_find(k, key);
  if at < 0 { return k.capacity; }
  var b = k.entries[at].bucket;
  rate_bucket_refill(&mut b, now_ms);
  return rate_bucket_tokens(&b);
}

/// Milliseconds until `cost` tokens are affordable for `key`, after settling
/// the stored bucket at now_ms (the store is not mutated). Unknown keys report
/// 0 when `cost <= capacity` (a fresh bucket is full) and -1 otherwise (a
/// bucket created now could never meet the cost); known keys delegate to
/// rate_bucket_retry_after_ms. Complexity: O(n) lookup + O(1).
pub fn rate_keyed_retry_after_ms(k: &KeyedBuckets, key: Str, cost: Int, now_ms: Int) -> Int {
  let at = _keyed_find(k, key);
  if at < 0 {
    if cost <= k.capacity { return 0; }
    return -1;
  }
  var b = k.entries[at].bucket;
  rate_bucket_refill(&mut b, now_ms);
  return rate_bucket_retry_after_ms(&b, cost);
}

/// Number of tracked keys. Complexity: O(1).
pub fn rate_keyed_count(k: &KeyedBuckets) -> Int
  ensures: result >= 0;
{
  return k.entries.len();
}

/// True when `key` is tracked. Complexity: O(n).
pub fn rate_keyed_contains(k: &KeyedBuckets, key: Str) -> Bool {
  return _keyed_find(k, key) >= 0;
}

/// Remove `key` and its bucket. Returns: true when an entry was removed,
/// false when the key was not tracked. Complexity: O(n).
pub fn rate_keyed_remove(k: &mut KeyedBuckets, key: Str) -> Bool {
  let at = _keyed_find(k, key);
  if at < 0 { return false; }
  k.entries.remove(at);
  return true;
}

/// Remove every entry whose bucket, after settling at now_ms, is full (no
/// pending debt): a saturated bucket carries no state a future call could use,
/// so it is safe to forget. Kept entries are written back settled.
/// Returns: the number of entries removed, >= 0. Complexity: O(n).
pub fn rate_keyed_prune(k: &mut KeyedBuckets, now_ms: Int) -> Int
  ensures: result >= 0;
{
  var removed = 0;
  var i = 0;
  while i < k.entries.len() {
    var b = k.entries[i].bucket;
    rate_bucket_refill(&mut b, now_ms);
    if b.tokens >= b.capacity {
      k.entries.remove(i);
      removed = removed + 1;
    } else {
      k.entries[i].bucket = b;
      i = i + 1;
    }
  }
  return removed;
}

/// Create an empty keyed window store with the constructor policy of
/// rate_window_new: `window_ms` clamps to >= 1 and `max_count` to >= 1. Every
/// window created for a new key inherits this span and limit and starts with
/// count 0 at the caller's now_ms.
/// Params: window_ms - per-key span length in milliseconds;
///         max_count - per-key admissions per span.
/// Returns: a KeyedWindows with no entries. No error path.
/// Complexity: O(1) + one empty Vec.
pub fn rate_window_keyed_new(window_ms: Int, max_count: Int) -> KeyedWindows {
  let template = rate_window_new(window_ms, max_count, 0);
  return KeyedWindows{
    entries: Vec[KeyedWindowEntry].new();
    window_ms: template.window_ms;
    max_count: template.max_count;
  };
}

/// Admit one call for `key` at now_ms. An unknown key is created on first use
/// with an empty span at now_ms, so a key's first call always succeeds; known
/// keys delegate to rate_window_allow (whose boundary rule rebases an elapsed
/// span). Complexity: O(n) lookup + O(1) amortized insert.
pub fn rate_window_keyed_allow(w: &mut KeyedWindows, key: Str, now_ms: Int) -> Bool {
  let at = _window_keyed_find(w, key);
  if at >= 0 {
    var win = w.entries[at].window;
    let admitted = rate_window_allow(&mut win, now_ms);
    w.entries[at].window = win;
    return admitted;
  }
  var fresh = rate_window_new(w.window_ms, w.max_count, now_ms);
  let created = rate_window_allow(&mut fresh, now_ms);
  w.entries.push(KeyedWindowEntry{ key: key; window: fresh; });
  return created;
}

/// Admissions counted for `key` in the current span: 0 for an unknown key and
/// 0 once the stored span has fully elapsed (a call now would rebase it),
/// otherwise the stored count. Read-only. Complexity: O(n) lookup + O(1).
pub fn rate_window_keyed_count(w: &KeyedWindows, key: Str, now_ms: Int) -> Int
  ensures: result >= 0;
{
  let at = _window_keyed_find(w, key);
  if at < 0 { return 0; }
  let win = w.entries[at].window;
  if now_ms - win.start_ms >= win.window_ms { return 0; }
  return rate_window_count(&win);
}

/// Milliseconds until `key` admits again (0 when an unknown key or a call
/// would be admitted now); known keys delegate to
/// rate_window_retry_after_ms. Read-only. Complexity: O(n) lookup + O(1).
pub fn rate_window_keyed_retry_after_ms(w: &KeyedWindows, key: Str, now_ms: Int) -> Int {
  let at = _window_keyed_find(w, key);
  if at < 0 { return 0; }
  let win = w.entries[at].window;
  return rate_window_retry_after_ms(&win, now_ms);
}

/// Number of tracked keys. Complexity: O(1).
pub fn rate_window_keyed_count_keys(w: &KeyedWindows) -> Int
  ensures: result >= 0;
{
  return w.entries.len();
}

/// Remove `key` and its window. Returns: true when an entry was removed,
/// false when the key was not tracked. Complexity: O(n).
pub fn rate_window_keyed_remove(w: &mut KeyedWindows, key: Str) -> Bool {
  let at = _window_keyed_find(w, key);
  if at < 0 { return false; }
  w.entries.remove(at);
  return true;
}

/// Remove every entry whose window span has fully elapsed at now_ms
/// (`now_ms - start_ms >= window_ms`): such a window is indistinguishable from
/// a fresh one on the next call. Returns: the number removed, >= 0.
/// Complexity: O(n).
pub fn rate_window_keyed_prune(w: &mut KeyedWindows, now_ms: Int) -> Int
  ensures: result >= 0;
{
  var removed = 0;
  var i = 0;
  while i < w.entries.len() {
    if now_ms - w.entries[i].window.start_ms >= w.entries[i].window.window_ms {
      w.entries.remove(i);
      removed = removed + 1;
    } else {
      i = i + 1;
    }
  }
  return removed;
}
