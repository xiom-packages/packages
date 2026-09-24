// Port task: pure-XIOM xiom.signal -- integer-friendly window functions,
// convolution, and moving extrema over flat Vec[Int] signals; fixed-point
// permille math with scalar Float64 trig, no FFI.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Units: every window coefficient is a permille integer on a fixed 1000
// scale (1000 == 1.0). Windows are generated with scalar Float64 math and
// stdlib cos, then rounded to nearest with halves away from zero
// (xiom.math.round). signal_apply_permille instead truncates its product
// quotient toward zero. Convolution and extrema are exact integer
// arithmetic. Vec[Int] element reads are copied into typed let bindings
// (`let x: Int = values[i];`) because untyped indexed reads mis-lower in
// v0.61.3.

module xiom.signal

use xiom.convert; use xiom.math;

// --- internal helpers -------------------------------------------------------

// Raised-cosine window in permille:
//   out[i] = round(1000 * (a - b * cos(2*pi*i/(n-1))))
// with halves rounded away from zero. Hann is (a, b) = (0.5, 0.5), Hamming
// is (0.54, 0.46). n < 1 yields an empty vector; n == 1 is the degenerate
// single-point window [1000]. `denom` and the phase index are converted
// with xiom.convert.int_to_float because the compiler has no implicit
// Int -> Float64 coercion.
fn _raised_cosine_permille(n: Int, a: Float64, b: Float64) -> Vec[Int] {
  var out = Vec[Int].new();
  if n < 1 {
    return out;
  }
  if n == 1 {
    out.push(1000);
    return out;
  }
  let denom: Float64 = xiom.convert.int_to_float(n - 1);
  let two_pi: Float64 = 2.0 * xiom.math.PI;
  var i = 0;
  while i < n {
    let phase: Float64 = two_pi * xiom.convert.int_to_float(i) / denom;
    let w: Float64 = 1000.0 * (a - b * xiom.math.cos(phase));
    out.push(xiom.math.round(w));
    i = i + 1;
  }
  return out;
}

// --- public API -------------------------------------------------------------

/// Rectangular window: every coefficient is 1000 permille.
/// Params: n - the requested window length.
/// Returns: a fresh Vec[Int] holding 1000 exactly n times; n < 1 yields an
/// empty vector.
/// Errors: none.
/// Complexity: O(n) time, O(n) memory.
pub fn signal_rect_permille(n: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    out.push(1000);
    i = i + 1;
  }
  return out;
}

/// Hann window in permille.
/// Params: n - the requested window length.
/// Returns: a fresh Vec[Int]; for n >= 2, position i is
/// round(1000 * (0.5 - 0.5*cos(2*pi*i/(n-1)))) with halves rounded away
/// from zero, so the endpoints are 0 and the centre of an odd-length window
/// is 1000; n == 1 yields [1000]; n < 1 yields an empty vector.
/// Errors: none.
/// Complexity: O(n) time, O(n) memory.
pub fn signal_hann_permille(n: Int) -> Vec[Int] {
  return _raised_cosine_permille(n, 0.5, 0.5);
}

/// Hamming window in permille.
/// Params: n - the requested window length.
/// Returns: a fresh Vec[Int]; for n >= 2, position i is
/// round(1000 * (0.54 - 0.46*cos(2*pi*i/(n-1)))) with halves rounded away
/// from zero, so the endpoints are 80 (0.54 - 0.46 = 0.08) and the centre
/// of an odd-length window is 1000; n == 1 yields [1000]; n < 1 yields an
/// empty vector.
/// Errors: none.
/// Complexity: O(n) time, O(n) memory.
pub fn signal_hamming_permille(n: Int) -> Vec[Int] {
  return _raised_cosine_permille(n, 0.54, 0.46);
}

/// Elementwise permille weighting of two series.
/// Params: values - the signal; weights - the permille coefficients.
/// Returns: a fresh Vec[Int] of length min(values.len(), weights.len());
/// out[i] = trunc(values[i] * weights[i] / 1000), where trunc rounds toward
/// zero (so 1 * -1 / 1000 == 0 and -1500 * 1 / 1000 == -1). Empty when
/// either input is empty.
/// Errors: none.
/// Complexity: O(min(n, m)) time, O(min(n, m)) memory.
pub fn signal_apply_permille(values: &Vec[Int], weights: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = values.len();
  let m = weights.len();
  var len = n;
  if m < len {
    len = m;
  }
  var i = 0;
  while i < len {
    let v: Int = values[i];
    let w: Int = weights[i];
    out.push(v * w / 1000);
    i = i + 1;
  }
  return out;
}

/// Same-length causal convolution with zero padding.
/// Params: values - the input signal; kernel - the impulse response.
/// Returns: a fresh Vec[Int] the same length as `values`. Convention:
/// out[i] = sum over j in [0, kernel.len()) of kernel[j] * values[i - j],
/// where values[t] is taken as 0 when t < 0. Equivalently the kernel slides
/// flipped across the signal: out[i] = sum_j values[j] * kernel[i - j],
/// truncated to the input length (the first len(kernel) samples are the
/// zero-padded edge). An empty kernel yields an all-zero vector of input
/// length; empty input yields an empty vector.
/// Errors: none.
/// Complexity: O(n * k) time, O(n) memory.
pub fn signal_convolve(values: &Vec[Int], kernel: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = values.len();
  let k = kernel.len();
  if k == 0 {
    var z = 0;
    while z < n {
      out.push(0);
      z = z + 1;
    }
    return out;
  }
  var i = 0;
  while i < n {
    var acc: Int = 0;
    var j = 0;
    while j < k {
      if j <= i {
        let v: Int = values[i - j];
        let w: Int = kernel[j];
        acc = acc + v * w;
      }
      j = j + 1;
    }
    out.push(acc);
    i = i + 1;
  }
  return out;
}

/// Trailing moving maximum.
/// Params: values - the input signal; window - the window width in samples.
/// Returns: a fresh Vec[Int] the same length as `values`; out[i] is the
/// maximum of the min(i+1, window) values ending at i, so a window wider
/// than the input simply uses every value available so far (partial
/// windows). window == 1 is the identity; window < 1 yields an empty
/// vector; empty input yields an empty vector.
/// Errors: none.
/// Complexity: O(n * window) time, O(n) memory.
pub fn signal_moving_max(values: &Vec[Int], window: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if window < 1 {
    return out;
  }
  let n = values.len();
  var i = 0;
  while i < n {
    var start = i - window + 1;
    if start < 0 {
      start = 0;
    }
    let first: Int = values[start];
    var best: Int = first;
    var j = start + 1;
    while j <= i {
      let x: Int = values[j];
      if x > best {
        best = x;
      }
      j = j + 1;
    }
    out.push(best);
    i = i + 1;
  }
  return out;
}

/// Trailing moving minimum.
/// Params: values - the input signal; window - the window width in samples.
/// Returns: a fresh Vec[Int] the same length as `values`; out[i] is the
/// minimum of the min(i+1, window) values ending at i, so a window wider
/// than the input simply uses every value available so far (partial
/// windows). window == 1 is the identity; window < 1 yields an empty
/// vector; empty input yields an empty vector.
/// Errors: none.
/// Complexity: O(n * window) time, O(n) memory.
pub fn signal_moving_min(values: &Vec[Int], window: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if window < 1 {
    return out;
  }
  let n = values.len();
  var i = 0;
  while i < n {
    var start = i - window + 1;
    if start < 0 {
      start = 0;
    }
    let first: Int = values[start];
    var best: Int = first;
    var j = start + 1;
    while j <= i {
      let x: Int = values[j];
      if x < best {
        best = x;
      }
      j = j + 1;
    }
    out.push(best);
    i = i + 1;
  }
  return out;
}

/// Count of sign changes in the non-zero subsequence.
/// Params: values - the input signal.
/// Returns: the number of adjacent pairs (a, b) of consecutive non-zero
/// values with opposite signs. Zeros are skipped entirely: they neither
/// create nor absorb a crossing, and leading/trailing zeros are ignored.
/// 0 for an empty, constant-sign, or all-zero signal.
/// Errors: none.
/// Complexity: O(n) time, O(1) extra memory.
pub fn signal_zero_crossings(values: &Vec[Int]) -> Int {
  var count = 0;
  var have_prev = false;
  var prev_neg = false;
  let n = values.len();
  var i = 0;
  while i < n {
    let x: Int = values[i];
    if x != 0 {
      let neg = x < 0;
      if have_prev {
        if neg != prev_neg {
          count = count + 1;
        }
      }
      have_prev = true;
      prev_neg = neg;
    }
    i = i + 1;
  }
  return count;
}
