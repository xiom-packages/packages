// Port task: pure-XIOM xiom.timeseries -- moving averages, deltas and range
// statistics over integer series; fixed-point math only, no FFI.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Module xiom.timeseries works on flat Vec[Int] series. There are no
// timestamps, no resampling and no floating point: every result is an
// integer, and every division that is not exact rounds toward negative
// infinity (integer floor). Vec[Int] element reads are copied into typed
// let bindings (`let x: Int = values[i];`) because untyped indexed reads
// mis-lower in v0.61.3.

module xiom.timeseries

// --- internal helpers -------------------------------------------------------

// Largest Int <= a / b for b > 0. The native Int operator truncates toward
// zero, so a negative remainder is corrected down by one. b <= 0 returns 0
// (never reached from the public API: every divisor is a positive count or
// span).
fn _floor_div(a: Int, b: Int) -> Int {
  if b <= 0 {
    return 0;
  }
  var q = a / b;
  let r = a % b;
  if r < 0 {
    q = q - 1;
  }
  return q;
}

// --- public API -------------------------------------------------------------

/// Trailing moving average with a partial prefix.
/// Params: values - the input series; window - the averaging width.
/// Returns: a fresh Vec[Int] of the same length as `values`; position i is
/// floor((sum of the min(i+1, window) values ending at i) / min(i+1, window)).
/// A window below 1 yields an empty vector (no positions are averaged).
/// Errors: none.
/// Complexity: O(n) time, O(n) memory (single running sum).
pub fn ts_moving_average(values: &Vec[Int], window: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if window < 1 {
    return out;
  }
  let n = values.len();
  var total: Int = 0;
  var i = 0;
  while i < n {
    let x: Int = values[i];
    total = total + x;
    if i >= window {
      let old: Int = values[i - window];
      total = total - old;
    }
    var count = i + 1;
    if count > window {
      count = window;
    }
    let avg = _floor_div(total, count);
    out.push(avg);
    i = i + 1;
  }
  return out;
}

/// Exponentially weighted moving average in permille fixed point.
/// Params: values - the input series; alpha_permille - the smoothing weight,
/// clamped to [0, 1000].
/// Returns: a fresh Vec[Int] the same length as `values`; out[0] = values[0]
/// and out[i] = floor((alpha*values[i] + (1000-alpha)*out[i-1]) / 1000).
/// alpha == 1000 reproduces the input exactly; alpha == 0 holds values[0]
/// constant for every position.
/// Errors: none.
/// Complexity: O(n) time, O(n) memory.
pub fn ts_ema(values: &Vec[Int], alpha_permille: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = values.len();
  if n == 0 {
    return out;
  }
  var alpha = alpha_permille;
  if alpha < 0 {
    alpha = 0;
  }
  if alpha > 1000 {
    alpha = 1000;
  }
  let beta = 1000 - alpha;
  let first: Int = values[0];
  out.push(first);
  var prev: Int = first;
  var i = 1;
  while i < n {
    let x: Int = values[i];
    let weighted = alpha * x + beta * prev;
    let next = _floor_div(weighted, 1000);
    out.push(next);
    prev = next;
    i = i + 1;
  }
  return out;
}

/// First differences of the series.
/// Params: values - the input series.
/// Returns: a fresh Vec[Int] the same length as `values`; out[0] = 0 and
/// out[i] = values[i] - values[i-1]. An empty series maps to empty.
/// Errors: none.
/// Complexity: O(n) time, O(n) memory.
pub fn ts_delta(values: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = values.len();
  if n == 0 {
    return out;
  }
  out.push(0);
  var i = 1;
  while i < n {
    let now: Int = values[i];
    let prev: Int = values[i - 1];
    let d = now - prev;
    out.push(d);
    i = i + 1;
  }
  return out;
}

/// Sum of every element.
/// Params: values - the input series.
/// Returns: the total, 0 for an empty series.
/// Errors: none.
/// Complexity: O(n) time, O(1) extra memory.
pub fn ts_sum(values: &Vec[Int]) -> Int {
  var total: Int = 0;
  let n = values.len();
  var i = 0;
  while i < n {
    let x: Int = values[i];
    total = total + x;
    i = i + 1;
  }
  return total;
}

/// Arithmetic mean with an integer floor.
/// Params: values - the input series.
/// Returns: floor(ts_sum(values) / values.len()), 0 for an empty series.
/// Errors: none.
/// Complexity: O(n) time, O(1) extra memory.
pub fn ts_mean(values: &Vec[Int]) -> Int {
  let n = values.len();
  if n == 0 {
    return 0;
  }
  let total: Int = ts_sum(values);
  return _floor_div(total, n);
}

/// Smallest element of the series.
/// Params: values - the input series.
/// Returns: the minimum, 0 for an empty series.
/// Errors: none.
/// Complexity: O(n) time, O(1) extra memory.
pub fn ts_min(values: &Vec[Int]) -> Int {
  let n = values.len();
  if n == 0 {
    return 0;
  }
  let first: Int = values[0];
  var best: Int = first;
  var i = 1;
  while i < n {
    let x: Int = values[i];
    if x < best {
      best = x;
    }
    i = i + 1;
  }
  return best;
}

/// Largest element of the series.
/// Params: values - the input series.
/// Returns: the maximum, 0 for an empty series.
/// Errors: none.
/// Complexity: O(n) time, O(1) extra memory.
pub fn ts_max(values: &Vec[Int]) -> Int {
  let n = values.len();
  if n == 0 {
    return 0;
  }
  let first: Int = values[0];
  var best: Int = first;
  var i = 1;
  while i < n {
    let x: Int = values[i];
    if x > best {
      best = x;
    }
    i = i + 1;
  }
  return best;
}

/// Index of the first occurrence of the minimum.
/// Params: values - the input series.
/// Returns: the 0-based index of the first minimum, -1 for an empty series.
/// Errors: none.
/// Complexity: O(n) time, O(1) extra memory.
pub fn ts_argmin(values: &Vec[Int]) -> Int {
  let n = values.len();
  if n == 0 {
    return -1;
  }
  let first: Int = values[0];
  var best: Int = first;
  var arg = 0;
  var i = 1;
  while i < n {
    let x: Int = values[i];
    if x < best {
      best = x;
      arg = i;
    }
    i = i + 1;
  }
  return arg;
}

/// Index of the first occurrence of the maximum.
/// Params: values - the input series.
/// Returns: the 0-based index of the first maximum, -1 for an empty series.
/// Errors: none.
/// Complexity: O(n) time, O(1) extra memory.
pub fn ts_argmax(values: &Vec[Int]) -> Int {
  let n = values.len();
  if n == 0 {
    return -1;
  }
  let first: Int = values[0];
  var best: Int = first;
  var arg = 0;
  var i = 1;
  while i < n {
    let x: Int = values[i];
    if x > best {
      best = x;
      arg = i;
    }
    i = i + 1;
  }
  return arg;
}

/// (minimum, maximum) pair of the series.
/// Params: values - the input series.
/// Returns: (ts_min(values), ts_max(values)); (0, 0) for an empty series.
/// Errors: none.
/// Complexity: O(n) time, O(1) extra memory.
pub fn ts_bounds(values: &Vec[Int]) -> (Int, Int) {
  let lo: Int = ts_min(values);
  let hi: Int = ts_max(values);
  return (lo, hi);
}

/// Min-max normalization to permille integers.
/// Params: values - the input series.
/// Returns: a fresh Vec[Int] the same length as `values`; out[i] =
/// clamp(floor((values[i] - min) * 1000 / (max - min)), 0, 1000). A constant
/// series maps to all zeros; an empty series maps to an empty vector.
/// Errors: none.
/// Complexity: O(n) time, O(n) memory.
pub fn ts_normalize_permille(values: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = values.len();
  if n == 0 {
    return out;
  }
  let lo: Int = ts_min(values);
  let hi: Int = ts_max(values);
  let span = hi - lo;
  var i = 0;
  while i < n {
    let x: Int = values[i];
    if span == 0 {
      out.push(0);
    } else {
      let shifted = x - lo;
      var scaled = _floor_div(shifted * 1000, span);
      if scaled < 0 {
        scaled = 0;
      }
      if scaled > 1000 {
        scaled = 1000;
      }
      out.push(scaled);
    }
    i = i + 1;
  }
  return out;
}

/// Upward threshold crossings.
/// Counts every position where the series moves from below `threshold` to
/// `threshold` or above; a first element already at or above `threshold`
/// counts as one crossing. Equal neighbours never count.
/// Params: values - the input series; threshold - the crossing level.
/// Returns: the crossing count, 0 for an empty series.
/// Errors: none.
/// Complexity: O(n) time, O(1) extra memory.
pub fn ts_threshold_crossings(values: &Vec[Int], threshold: Int) -> Int {
  let n = values.len();
  if n == 0 {
    return 0;
  }
  let first: Int = values[0];
  var count = 0;
  if first >= threshold {
    count = 1;
  }
  var prev: Int = first;
  var i = 1;
  while i < n {
    let x: Int = values[i];
    if prev < threshold {
      if x >= threshold {
        count = count + 1;
      }
    }
    prev = x;
    i = i + 1;
  }
  return count;
}
