// XIOM -- xiom.metrics: counters, gauges, and histograms for in-process metrics
// Port task: replace the xiom.metrics placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure deterministic value types: no clock access, no I/O, no allocation
// beyond the histogram bucket vectors, no FFI. Free functions only -- XIOM
// v0.61.x has no methods. Histograms use the classic cumulative-bucket shape:
// `counts` has bounds.len() + 1 entries, bucket i counts observations
// v <= bounds[i] that no earlier bucket took, and the final bucket counts
// everything above the last bound (the +Inf bucket). The caller is
// responsible for passing ascending bounds (see README Limitations).

module xiom.metrics

/// Monotonic process-local counter.
///
/// `value` is an internal implementation detail; construct through
/// metric_counter_new and read through metric_counter_value.
pub type Counter = {
  value: Int;
}

/// Create a counter at zero. No error path. Complexity: O(1).
pub fn metric_counter_new() -> Counter {
  return Counter{ value: 0; };
}

/// Current counter value. Complexity: O(1).
pub fn metric_counter_value(c: &Counter) -> Int {
  return c.value;
}

/// Increment the counter by 1. Complexity: O(1).
pub fn metric_counter_inc(c: &mut Counter) {
  c.value = c.value + 1;
}

/// Add `delta` to the counter; negative deltas subtract.
/// Complexity: O(1).
pub fn metric_counter_add(c: &mut Counter, delta: Int) {
  c.value = c.value + delta;
}

/// Reset the counter to zero. Complexity: O(1).
pub fn metric_counter_reset(c: &mut Counter) {
  c.value = 0;
}

/// Point-in-time integer gauge.
///
/// `value` is an internal implementation detail; construct through
/// metric_gauge_new and read through metric_gauge_value.
pub type Gauge = {
  value: Int;
}

/// Create a gauge holding `initial`. No clamping, no error path.
/// Complexity: O(1).
pub fn metric_gauge_new(initial: Int) -> Gauge {
  return Gauge{ value: initial; };
}

/// Current gauge value. Complexity: O(1).
pub fn metric_gauge_value(g: &Gauge) -> Int {
  return g.value;
}

/// Set the gauge to `v`. Complexity: O(1).
pub fn metric_gauge_set(g: &mut Gauge, v: Int) {
  g.value = v;
}

/// Add `delta` to the gauge; negative deltas subtract.
/// Complexity: O(1).
pub fn metric_gauge_add(g: &mut Gauge, delta: Int) {
  g.value = g.value + delta;
}

/// Integer histogram with caller-supplied cumulative bucket bounds.
///
/// Every field is an internal implementation detail; callers must go through
/// the free functions below. `bounds` is a private copy of the bounds passed
/// to metric_histogram_new (used as given, ascending assumed); `counts` has
/// bounds.len() + 1 entries: bucket i counts observations v <= bounds[i] that
/// no earlier bucket took, and the last bucket counts v > last bound (the
/// +Inf bucket). `count` is the total observations, `sum` their arithmetic
/// sum, and `min`/`max` the extremes (both 0 while `count` is 0).
pub type Histogram = {
  bounds: Vec[Int];
  counts: Vec[Int];
  count: Int;
  sum: Int;
  min: Int;
  max: Int;
}

/// Create an empty histogram over `bounds`.
/// Params: bounds - cumulative bucket upper bounds, used as given (the caller
///         must pass them sorted ascending for meaningful buckets).
/// Returns: a histogram with bounds.len() + 1 zeroed buckets and zeroed
/// statistics. The bounds are copied, so later changes to the caller's Vec
/// do not affect the histogram. No error path. Complexity: O(n) in bounds.
pub fn metric_histogram_new(bounds: &Vec[Int]) -> Histogram {
  var copied = Vec[Int].new();
  var i = 0;
  while i < bounds.len() {
    let b: Int = bounds[i];
    copied.push(b);
    i = i + 1;
  }
  var counts = Vec[Int].new();
  var j = 0;
  while j <= copied.len() {
    counts.push(0);
    j = j + 1;
  }
  return Histogram{ bounds: copied; counts: counts; count: 0; sum: 0; min: 0; max: 0; };
}

/// Record one observation `v`.
/// Updates count, sum, min and max (min and max start at the first observed
/// value) and increments exactly one bucket: the first bucket i with
/// v <= bounds[i], or the final bucket when v exceeds every bound.
/// Complexity: O(n) in bounds (first-fit scan).
pub fn metric_histogram_observe(h: &mut Histogram, v: Int) {
  if h.count == 0 {
    h.min = v;
    h.max = v;
  } else {
    if v < h.min { h.min = v; }
    if v > h.max { h.max = v; }
  }
  h.count = h.count + 1;
  h.sum = h.sum + v;
  var idx = h.bounds.len();
  var i = 0;
  while i < h.bounds.len() {
    let b: Int = h.bounds[i];
    if v <= b {
      idx = i;
      break;
    }
    i = i + 1;
  }
  h.counts[idx] = h.counts[idx] + 1;
}

/// Observation count in bucket `index`.
/// Params: h - the histogram; index - bucket index.
/// Returns: the bucket count, or 0 when `index` is negative or beyond the
/// last bucket. No error path. Complexity: O(1).
pub fn metric_histogram_bucket_count(h: &Histogram, index: Int) -> Int {
  if index < 0 { return 0; }
  if index >= h.counts.len() { return 0; }
  let got: Int = h.counts[index];
  return got;
}

/// Number of buckets (always bounds.len() + 1, at least 1).
/// Complexity: O(1).
pub fn metric_histogram_bucket_len(h: &Histogram) -> Int {
  return h.counts.len();
}

/// Total observations recorded. Complexity: O(1).
pub fn metric_histogram_count(h: &Histogram) -> Int {
  return h.count;
}

/// Arithmetic sum of all observed values. Complexity: O(1).
pub fn metric_histogram_sum(h: &Histogram) -> Int {
  return h.sum;
}

/// Smallest observed value, or 0 when the histogram is empty.
/// Complexity: O(1).
pub fn metric_histogram_min(h: &Histogram) -> Int {
  return h.min;
}

/// Largest observed value, or 0 when the histogram is empty.
/// Complexity: O(1).
pub fn metric_histogram_max(h: &Histogram) -> Int {
  return h.max;
}

/// Integer mean sum/count (floor), or 0 when the histogram is empty.
/// Complexity: O(1).
pub fn metric_histogram_mean(h: &Histogram) -> Int {
  if h.count == 0 { return 0; }
  return h.sum / h.count;
}

/// Drop every observation: zeroes all buckets and count/sum/min/max, and
/// keeps the bounds (bucket layout is unchanged, so the histogram can be
/// reused). Complexity: O(n) in buckets.
pub fn metric_histogram_reset(h: &mut Histogram) {
  var i = 0;
  while i < h.counts.len() {
    h.counts[i] = 0;
    i = i + 1;
  }
  h.count = 0;
  h.sum = 0;
  h.min = 0;
  h.max = 0;
}
