// XIOM -- xiom.deep: deep network building blocks over fixed-point integers
// Port task: replace the xiom.deep placeholder with a pure-XIOM module
// (scaled integers only: no floats, no FFI, no I/O, no Vec[Float64], no
// training). Residual / convolutional / attention / recurrent assembly,
// architecture-specific deterministic initialization, tiny forward passes and
// parameter-count verification.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixed point: every weight, bias, activation and probability is an Int in
// units of 1e-4 (_DP_SCALE == 10000 == 1.0); products are requantized by
// dividing by the scale with half-away-from-zero rounding (_dp_div_round),
// the same convention as xiom.neural. Int division truncates toward zero, so
// the rounding helper adds/subtracts one only when the remaining magnitude is
// at least half the divisor.
//
// Model assembly is flat: functions take parallel Int vectors (row-major
// weight matrices, bias vectors, hidden/cell state vectors) and return owned
// results; there is no Vec[StructType] and no global mutable state. Random
// initialization threads an LCG state through return values (never a &mut
// scalar), so a stream is reproducible: the same seed yields the same weights.
//
// v0.62.2 conventions in force: free functions only; every Vec element read
// binds a typed local; Ok/Err construction is confined to leaf helpers at the
// bottom; Vec parameters are read-only &Vec[Int] (or &mut only in helpers that
// append); every loop advances or exits.

module xiom.deep

use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Fixed-point scale: 10000 units = 1.0 (resolution 1e-4).
const _DP_SCALE: Int = 10000;
// Signed 64-bit envelope (Int); the minimum is built by _dp_int_min().
const _DP_INT_MAX: Int = 9223372036854775807;
// Floor of sqrt(Int_max), used to bound the integer square-root search.
const _DP_SQRT_MAX: Int = 3037000500;
// 6 * _DP_SCALE * _DP_SCALE, the Xavier numerator before the fan sum.
const _DP_XAVIER_NUM: Int = 600000000;

// Deterministic LCG (glibc-style numeric recipes constants).
const _LCG_A: Int = 1103515245;
const _LCG_C: Int = 12345;
const _LCG_M: Int = 2147483648;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// One step of the deterministic LCG: the drawn value and the next state.
pub type InitStep = {
  value: Int;
  state: Int;
}

/// A drawn weight vector together with the LCG state that follows it, so a
/// stream is threaded through returns (never through a &mut Int).
pub type InitVec = {
  values: Vec[Int];
  state: Int;
}

/// LSTM cell state: the hidden vector and the cell vector.
pub type LstmState = {
  h: Vec[Int];
  c: Vec[Int];
}

// Internal gate pre-activation bundle for one LSTM unit.
type _DpGates = {
  pi: Int;
  pf: Int;
  pg: Int;
  po: Int;
}

// ---------------------------------------------------------------------------
// Fixed-point primitives (public utilities)
// ---------------------------------------------------------------------------

/// Fixed-point scale (10000; one unit is 1e-4). Complexity: O(1).
pub fn deep_scale() -> Int {
  return _DP_SCALE;
}

/// Rounding division by a positive divisor: half away from zero.
///
/// Params: a - numerator; b - positive denominator.
/// Returns: round(a / b); when b <= 0 the result is 0 (callers validate b).
/// Complexity: O(1).
pub fn deep_div_round(a: Int, b: Int) -> Int {
  if b <= 0 {
    return 0;
  }
  let q = a / b;
  let r = a % b;
  var mag = r;
  if mag < 0 {
    mag = 0 - mag;
  }
  var up = false;
  if mag > _DP_INT_MAX / 2 {
    up = true;
  } elif mag * 2 >= b {
    up = true;
  }
  if up {
    if a < 0 {
      return q - 1;
    }
    return q + 1;
  }
  return q;
}

/// Floor of the integer square root of a non-negative Int.
/// Params: n - a value >= 0. Returns: floor(sqrt(n)); 0 for n <= 0.
/// Complexity: O(log n) (binary search; no overflow because mid <= n / mid).
pub fn deep_int_sqrt(n: Int) -> Int {
  if n <= 0 {
    return 0;
  }
  if n < 4 {
    return 1;
  }
  var lo: Int = 1;
  var hi: Int = n;
  if hi > _DP_SQRT_MAX {
    hi = _DP_SQRT_MAX;
  }
  var ans: Int = 0;
  while lo <= hi {
    let mid = lo + (hi - lo) / 2;
    if mid <= n / mid {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

/// Elementwise relu over a fixed-point vector. Complexity: O(n).
pub fn deep_relu(x: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < x.len() {
    let v: Int = x[i];
    if v < 0 {
      out.push(0);
    } else {
      out.push(v);
    }
    i = i + 1;
  }
  return out;
}

/// Fast sigmoid s(x) = 1/2 + (x / (1 + |x|)) / 2 in 1e-4 units.
/// Returns: a value in [0, 10000]; s(0) = 5000, s(-x) = 10000 - s(x).
/// Complexity: O(1).
pub fn deep_sigmoid(x: Int) -> Int {
  if x == 0 {
    return _DP_SCALE / 2;
  }
  if x > 0 {
    if x > _DP_INT_MAX / _DP_SCALE {
      return _DP_SCALE;
    }
    let t = deep_div_round(x * _DP_SCALE, _DP_SCALE + x);
    return deep_div_round(_DP_SCALE + t, 2);
  }
  let ax = 0 - x;
  if ax > _DP_INT_MAX / _DP_SCALE {
    return 0;
  }
  let t = deep_div_round(x * _DP_SCALE, _DP_SCALE + ax);
  return deep_div_round(_DP_SCALE + t, 2);
}

/// Tanh from the sigmoid: tanh(x) = 2 * s(2x) - 1, in 1e-4 units.
/// Complexity: O(1).
pub fn deep_tanh(x: Int) -> Int {
  if x == 0 {
    return 0;
  }
  if x > 0 {
    if x > _DP_INT_MAX / 2 {
      return _DP_SCALE;
    }
    let s = deep_sigmoid(x * 2);
    return 2 * s - _DP_SCALE;
  }
  if x < _dp_int_min() / 2 {
    return 0 - _DP_SCALE;
  }
  let s = deep_sigmoid(x * 2);
  return 2 * s - _DP_SCALE;
}

/// Softmax over fixed-point logits (max-shifted, piecewise-linear exp).
/// Params: logits - one 1e-4 unit per class; must not be empty.
/// Returns: Ok(probs), every entry in [0, 10000]; entries sum to 10000 up to
/// per-entry rounding. Error case: empty input, logit-shift underflow,
/// softmax-sum or product overflow. Complexity: O(n).
pub fn deep_softmax(logits: &Vec[Int]) -> Result[Vec[Int], Str] {
  let n = logits.len();
  if n <= 0 {
    return _err_ints("deep: logits must not be empty");
  }
  var maxv: Int = logits[0];
  var i = 1;
  while i < n {
    let x: Int = logits[i];
    if x > maxv {
      maxv = x;
    }
    i = i + 1;
  }
  var exps = Vec[Int].new();
  var total: Int = 0;
  i = 0;
  while i < n {
    let x: Int = logits[i];
    if maxv > 0 && x < _dp_int_min() + maxv {
      return _err_ints("deep: softmax shift underflows");
    }
    let shifted = x - maxv;
    let e = _dp_exp(shifted);
    if e > _DP_INT_MAX - total {
      return _err_ints("deep: softmax sum overflows");
    }
    total = total + e;
    exps.push(e);
    i = i + 1;
  }
  if total <= 0 {
    return _err_ints("deep: softmax sum must be positive");
  }
  var out = Vec[Int].new();
  i = 0;
  while i < n {
    let e: Int = exps[i];
    if e > 0 && e > _DP_INT_MAX / _DP_SCALE {
      return _err_ints("deep: softmax product overflows");
    }
    out.push(deep_div_round(e * _DP_SCALE, total));
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Deterministic initialization (in-package LCG)
// ---------------------------------------------------------------------------

/// Advance the LCG one step: (state * 1103515245 + 12345) mod 2^31.
/// Complexity: O(1).
pub fn deep_lcg_next(state: Int) -> Int {
  var s = state % _LCG_M;
  if s < 0 {
    s = s + _LCG_M;
  }
  let prod = s * _LCG_A;
  var v = (prod + _LCG_C) % _LCG_M;
  if v < 0 {
    v = v + _LCG_M;
  }
  return v;
}

/// Draw one value in [0, bound) and return it with the next LCG state.
/// Params: state - any seed; bound - the exclusive upper bound (<= 0 draws 0).
/// Complexity: O(1).
pub fn deep_init_next(state: Int, bound: Int) -> InitStep {
  let s = deep_lcg_next(state);
  if bound <= 0 {
    return InitStep{ value: 0; state: s; };
  }
  return InitStep{ value: s % bound; state: s; };
}

/// Draw `n` values uniformly in [lo, hi] (inclusive) from a seeded stream.
/// Returns: InitVec with the values and the advanced state. When hi < lo or
/// n <= 0 the values are empty. Complexity: O(n).
pub fn deep_init_uniform(n: Int, lo: Int, hi: Int, state0: Int) -> InitVec {
  var out = Vec[Int].new();
  if n <= 0 || hi < lo {
    return InitVec{ values: out; state: state0 };
  }
  let span = hi - lo;
  var bound = span + 1;
  if span < 0 || bound <= 0 {
    bound = 0;
  }
  var st = state0;
  var i = 0;
  while i < n {
    if bound <= 0 {
      out.push(lo);
    } else {
      let step = deep_init_next(st, bound);
      out.push(lo + step.value);
      st = step.state;
    }
    i = i + 1;
  }
  return InitVec{ values: out; state: st; };
}

/// Xavier-style dense initialization: n = fan_in * fan_out weights uniform in
/// [-L, L], L = floor(sqrt(6 * scale^2 / (fan_in + fan_out))) in 1e-4 units.
/// Error case: empty vector when a fan is <= 0 or the count overflows.
/// Complexity: O(fan_in * fan_out).
pub fn deep_init_dense(fan_in: Int, fan_out: Int, state0: Int) -> InitVec {
  var empty = Vec[Int].new();
  if fan_in <= 0 || fan_out <= 0 {
    return InitVec{ values: empty; state: state0 };
  }
  if _dp_mul_overflows(fan_in, fan_out) {
    return InitVec{ values: empty; state: state0 };
  }
  let denom = fan_in + fan_out;
  if denom <= 0 || denom > _DP_XAVIER_NUM {
    return InitVec{ values: empty; state: state0 };
  }
  let limit = deep_int_sqrt(_DP_XAVIER_NUM / denom);
  return deep_init_uniform(fan_in * fan_out, 0 - limit, limit, state0);
}

/// A zero vector of length `n` (0 when n <= 0). Complexity: O(n).
pub fn deep_init_zeros(n: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    out.push(0);
    i = i + 1;
  }
  return out;
}

/// A vector of `n` ones in 1e-4 units (10000 each). Complexity: O(n).
pub fn deep_init_ones(n: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    out.push(_DP_SCALE);
    i = i + 1;
  }
  return out;
}

/// Copy the drawn values out of an InitVec. Complexity: O(n).
pub fn deep_init_values(iv: &InitVec) -> Vec[Int] {
  return _dp_copy_ints(&iv.values);
}

/// The LCG state following a draw (so callers can continue the stream).
/// Complexity: O(1).
pub fn deep_init_state(iv: &InitVec) -> Int {
  return iv.state;
}

// ---------------------------------------------------------------------------
// Assembly helpers
// ---------------------------------------------------------------------------

/// Dense (fully connected) layer: out[j] = round(sum_i w[j,i]*x[i]/scale)+b[j].
/// Params: x - input (length ni); w - row-major [n_out x ni]; b - [n_out].
/// Error case: empty input, non-positive n_out, shape mismatch, dot or bias
/// overflow. Complexity: O(ni * n_out).
pub fn deep_linear(x: &Vec[Int], w: &Vec[Int], b: &Vec[Int], n_out: Int) -> Result[Vec[Int], Str] {
  let ni = x.len();
  if ni <= 0 {
    return _err_ints("deep: linear input must not be empty");
  }
  if n_out <= 0 {
    return _err_ints("deep: linear output must be positive");
  }
  if _dp_mul_overflows(ni, n_out) {
    return _err_ints("deep: linear dimensions overflow");
  }
  if w.len() != ni * n_out {
    return _err_ints("deep: linear weight length does not match the shape");
  }
  if b.len() != n_out {
    return _err_ints("deep: linear bias length does not match the output");
  }
  var out = Vec[Int].new();
  var j = 0;
  while j < n_out {
    let d = _dp_row(w, x, j, ni);
    match d {
      Err(e) => { return _err_ints(e); },
      Ok(s) => {
        let bj: Int = b[j];
        if _dp_add_overflows(s, bj) {
          return _err_ints("deep: linear bias addition overflows");
        }
        out.push(s + bj);
      },
    }
    j = j + 1;
  }
  return _ok_ints(out);
}

/// Two-layer MLP with a relu hidden layer: relu -> linear.
/// Params: x, w1 [h x ni], b1 [h], h hidden width, w2 [n_out x h], b2 [n_out].
/// Complexity: O(ni*h + h*n_out).
pub fn deep_mlp2(x: &Vec[Int], w1: &Vec[Int], b1: &Vec[Int], h: Int, w2: &Vec[Int], b2: &Vec[Int], n_out: Int) -> Result[Vec[Int], Str] {
  let l1 = deep_linear(x, w1, b1, h);
  match l1 {
    Err(e) => { return _err_ints(e); },
    Ok(a) => {
      let r = deep_relu(&a);
      return deep_linear(&r, w2, b2, n_out);
    },
  }
  return _err_ints("deep: mlp2 failed");
}

/// Elementwise sum of two equal-length vectors, with overflow checks.
/// Complexity: O(n).
pub fn deep_add(a: &Vec[Int], b: &Vec[Int]) -> Result[Vec[Int], Str] {
  if a.len() != b.len() {
    return _err_ints("deep: add length mismatch");
  }
  var out = Vec[Int].new();
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if _dp_add_overflows(x, y) {
      return _err_ints("deep: add overflows");
    }
    out.push(x + y);
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Parameter counting
// ---------------------------------------------------------------------------

/// Dense parameter count (weights + biases). Complexity: O(1).
pub fn deep_dense_params(n_in: Int, n_out: Int) -> Int {
  if n_in <= 0 || n_out <= 0 {
    return 0;
  }
  return n_in * n_out + n_out;
}

/// 1D convolution parameter count (kernel + bias). Complexity: O(1).
pub fn deep_conv1d_params(in_ch: Int, out_ch: Int, k: Int) -> Int {
  if in_ch <= 0 || out_ch <= 0 || k <= 0 {
    return 0;
  }
  return out_ch * in_ch * k + out_ch;
}

/// Vanilla RNN parameter count: hidden*(input+hidden) + hidden. O(1).
pub fn deep_rnn_params(input: Int, hidden: Int) -> Int {
  if input <= 0 || hidden <= 0 {
    return 0;
  }
  return hidden * (input + hidden) + hidden;
}

/// LSTM parameter count: 4*hidden*(input+hidden) + 4*hidden. O(1).
pub fn deep_lstm_params(input: Int, hidden: Int) -> Int {
  if input <= 0 || hidden <= 0 {
    return 0;
  }
  return 4 * hidden * (input + hidden) + 4 * hidden;
}

/// GRU parameter count: 3*hidden*(input+hidden) + 3*hidden. O(1).
pub fn deep_gru_params(input: Int, hidden: Int) -> Int {
  if input <= 0 || hidden <= 0 {
    return 0;
  }
  return 3 * hidden * (input + hidden) + 3 * hidden;
}

// ---------------------------------------------------------------------------
// Residual blocks (resnet)
// ---------------------------------------------------------------------------

/// Identity-skip residual block: relu(F(x) + x), F a two-layer relu MLP of
/// input and output width `h`. Params: x length must equal h; w1 [h x h],
/// b1 [h], w2 [h x h], b2 [h]. Error case: width mismatch or any inner error.
/// Complexity: O(h^2).
pub fn deep_res_identity(x: &Vec[Int], w1: &Vec[Int], b1: &Vec[Int], h: Int, w2: &Vec[Int], b2: &Vec[Int]) -> Result[Vec[Int], Str] {
  if x.len() != h {
    return _err_ints("deep: residual identity requires matching width");
  }
  let f = deep_mlp2(x, w1, b1, h, w2, b2, h);
  match f {
    Err(e) => { return _err_ints(e); },
    Ok(fx) => {
      let s = deep_add(x, &fx);
      match s {
        Err(e) => { return _err_ints(e); },
        Ok(sum) => { return _ok_ints(deep_relu(&sum)); },
      }
    },
  }
  return _err_ints("deep: residual identity failed");
}

/// Projection-skip residual block: relu(F(x) + Ws x + bs). F maps input width
/// to `n_out`; ws [n_out x ni], bs [n_out] project the (possibly wider) input.
/// Complexity: O(ni*h + h*n_out + ni*n_out).
pub fn deep_res_projection(x: &Vec[Int], w1: &Vec[Int], b1: &Vec[Int], h: Int, w2: &Vec[Int], b2: &Vec[Int], n_out: Int, ws: &Vec[Int], bs: &Vec[Int]) -> Result[Vec[Int], Str] {
  let f = deep_mlp2(x, w1, b1, h, w2, b2, n_out);
  match f {
    Err(e) => { return _err_ints(e); },
    Ok(fx) => {
      let p = deep_linear(x, ws, bs, n_out);
      match p {
        Err(e) => { return _err_ints(e); },
        Ok(px) => {
          let s = deep_add(&fx, &px);
          match s {
            Err(e) => { return _err_ints(e); },
            Ok(sum) => { return _ok_ints(deep_relu(&sum)); },
          }
        },
      }
    },
  }
  return _err_ints("deep: residual projection failed");
}

// ---------------------------------------------------------------------------
// Convolutional blocks (convnet)
// ---------------------------------------------------------------------------

/// Valid 1D convolution with a scalar bias: out[j] =
/// round(sum_i input[j+i]*kernel[i]/scale) + bias. Params: kernel length k >= 1
/// and input length >= k. Error case: empty kernel, short input, product or
/// sum overflow. Complexity: O((n-k+1) * k).
pub fn deep_conv1d_valid(input: &Vec[Int], kernel: &Vec[Int], bias: Int) -> Result[Vec[Int], Str] {
  let n = input.len();
  let k = kernel.len();
  if k <= 0 {
    return _err_ints("deep: conv kernel must not be empty");
  }
  if n < k {
    return _err_ints("deep: conv input shorter than kernel");
  }
  var out = Vec[Int].new();
  let nout = n - k + 1;
  var j = 0;
  while j < nout {
    var s: Int = 0;
    var i = 0;
    while i < k {
      let a: Int = input[j + i];
      let w: Int = kernel[i];
      if _dp_mul_overflows(a, w) {
        return _err_ints("deep: conv product overflows");
      }
      let t = a * w;
      if _dp_add_overflows(s, t) {
        return _err_ints("deep: conv sum overflows");
      }
      s = s + t;
      i = i + 1;
    }
    let y = deep_div_round(s, _DP_SCALE);
    if _dp_add_overflows(y, bias) {
      return _err_ints("deep: conv bias overflows");
    }
    out.push(y + bias);
    j = j + 1;
  }
  return _ok_ints(out);
}

/// Valid 1D convolution followed by elementwise relu.
/// Complexity: O((n-k+1) * k).
pub fn deep_conv1d_relu_valid(input: &Vec[Int], kernel: &Vec[Int], bias: Int) -> Result[Vec[Int], Str] {
  let c = deep_conv1d_valid(input, kernel, bias);
  match c {
    Err(e) => { return _err_ints(e); },
    Ok(v) => { return _ok_ints(deep_relu(&v)); },
  }
  return _err_ints("deep: conv relu failed");
}

/// Non-overlapping (or strided) 1D max pooling.
/// Params: x length >= k; k window > 0; stride > 0.
/// Error case: non-positive window/stride or short input.
/// Complexity: O(((n-k)/stride + 1) * k).
pub fn deep_max_pool1d(x: &Vec[Int], k: Int, stride: Int) -> Result[Vec[Int], Str] {
  if k <= 0 {
    return _err_ints("deep: pool size must be positive");
  }
  if stride <= 0 {
    return _err_ints("deep: pool stride must be positive");
  }
  let n = x.len();
  if n < k {
    return _err_ints("deep: pool input shorter than window");
  }
  var out = Vec[Int].new();
  var start = 0;
  while start + k <= n {
    let first: Int = x[start];
    var best = first;
    var i = 1;
    while i < k {
      let v: Int = x[start + i];
      if v > best {
        best = v;
      }
      i = i + 1;
    }
    out.push(best);
    start = start + stride;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Recurrent cells
// ---------------------------------------------------------------------------

/// Vanilla RNN cell: h' = tanh(Wx x + Wh h + b).
/// Params: x (length xx), h (length hh); wx [hh x xx], wh [hh x hh], b [hh].
/// Error case: empty x/h, shape mismatch, dot/bias overflow.
/// Complexity: O(hh * (xx + hh)).
pub fn deep_rnn_cell(x: &Vec[Int], h: &Vec[Int], wx: &Vec[Int], wh: &Vec[Int], b: &Vec[Int]) -> Result[Vec[Int], Str] {
  let hh = h.len();
  let xx = x.len();
  if hh <= 0 {
    return _err_ints("deep: rnn hidden must not be empty");
  }
  if xx <= 0 {
    return _err_ints("deep: rnn input must not be empty");
  }
  if _dp_mul_overflows(hh, xx) {
    return _err_ints("deep: rnn shape overflows");
  }
  if _dp_mul_overflows(hh, hh) {
    return _err_ints("deep: rnn shape overflows");
  }
  if wx.len() != hh * xx {
    return _err_ints("deep: rnn wx length does not match the shape");
  }
  if wh.len() != hh * hh {
    return _err_ints("deep: rnn wh length does not match the shape");
  }
  if b.len() != hh {
    return _err_ints("deep: rnn bias length does not match the hidden width");
  }
  var out = Vec[Int].new();
  var i = 0;
  while i < hh {
    let rx = _dp_row(wx, x, i, xx);
    match rx {
      Err(e) => { return _err_ints(e); },
      Ok(vx) => {
        let rh = _dp_row(wh, h, i, hh);
        match rh {
          Err(e) => { return _err_ints(e); },
          Ok(vh) => {
            let bi: Int = b[i];
            if _dp_add_overflows(vx, vh) {
              return _err_ints("deep: rnn accumulation overflows");
            }
            let s0 = vx + vh;
            if _dp_add_overflows(s0, bi) {
              return _err_ints("deep: rnn accumulation overflows");
            }
            out.push(deep_tanh(s0 + bi));
          },
        }
      },
    }
    i = i + 1;
  }
  return _ok_ints(out);
}

/// LSTM cell (gate order i, f, g, o).
///
/// Params: x (length xx), h (length hidden), c (length hidden); w is the
/// row-major [4*hidden x (xx+hidden)] stacked gate matrix (gate g row block
/// starts at g*hidden, column width is xx+hidden); b is [4*hidden].
/// Returns: Ok(LstmState) with the new hidden and cell vectors. Cell math:
/// i,f,o = sigmoid gates, g = tanh gate, c' = round(f*c/scale) +
/// round(i*g/scale), h' = round(o*tanh(c')/scale).
/// Error case: empty/short inputs, shape mismatch, product overflow.
/// Complexity: O(hidden * (xx + hidden)).
pub fn deep_lstm_cell(x: &Vec[Int], h: &Vec[Int], c: &Vec[Int], w: &Vec[Int], b: &Vec[Int], hidden: Int) -> Result[LstmState, Str] {
  let hh = hidden;
  let xx = x.len();
  if hh <= 0 {
    return _err_lstm("deep: lstm hidden must be positive");
  }
  if xx <= 0 {
    return _err_lstm("deep: lstm input must not be empty");
  }
  if h.len() != hh {
    return _err_lstm("deep: lstm hidden state length mismatch");
  }
  if c.len() != hh {
    return _err_lstm("deep: lstm cell state length mismatch");
  }
  if hh > _DP_INT_MAX / 4 {
    return _err_lstm("deep: lstm shape overflows");
  }
  let width = xx + hh;
  if _dp_mul_overflows(4 * hh, width) {
    return _err_lstm("deep: lstm shape overflows");
  }
  if w.len() != 4 * hh * width {
    return _err_lstm("deep: lstm weight length does not match the shape");
  }
  if b.len() != 4 * hh {
    return _err_lstm("deep: lstm bias length does not match the shape");
  }
  let cat = _dp_concat(x, h);
  var new_h = Vec[Int].new();
  var new_c = Vec[Int].new();
  var i = 0;
  while i < hh {
    let gr = _dp_lstm_gates(w, &cat, i, hh, width, b);
    match gr {
      Err(e) => { return _err_lstm(e); },
      Ok(g) => {
        let fv = deep_sigmoid(g.pf);
        let iv = deep_sigmoid(g.pi);
        let gv = deep_tanh(g.pg);
        let ov = deep_sigmoid(g.po);
        let cold: Int = c[i];
        if _dp_mul_overflows(fv, cold) {
          return _err_lstm("deep: lstm cell product overflows");
        }
        let fc = deep_div_round(fv * cold, _DP_SCALE);
        if _dp_mul_overflows(iv, gv) {
          return _err_lstm("deep: lstm cell product overflows");
        }
        let ig = deep_div_round(iv * gv, _DP_SCALE);
        if _dp_add_overflows(fc, ig) {
          return _err_lstm("deep: lstm cell accumulation overflows");
        }
        let cnew = fc + ig;
        let ct = deep_tanh(cnew);
        if _dp_mul_overflows(ov, ct) {
          return _err_lstm("deep: lstm output product overflows");
        }
        new_c.push(cnew);
        new_h.push(deep_div_round(ov * ct, _DP_SCALE));
      },
    }
    i = i + 1;
  }
  return _ok_lstm(LstmState{ h: new_h; c: new_c; });
}

/// Hidden vector of an LSTM state. Complexity: O(n) (copy).
pub fn deep_lstm_h(s: &LstmState) -> Vec[Int] {
  return _dp_copy_ints(&s.h);
}

/// Cell vector of an LSTM state. Complexity: O(n) (copy).
pub fn deep_lstm_c(s: &LstmState) -> Vec[Int] {
  return _dp_copy_ints(&s.c);
}

/// GRU cell: z,r = sigmoid gates, cand = tanh(W_h [x, r*h] + b_h),
/// h' = round(((scale - z)*h + z*cand)/scale).
/// Params: x (xx), h (hidden); wz,wr,wh each [hidden x (xx+hidden)];
/// bz,br,bh each [hidden]. Error case: empty inputs, shape mismatch or
/// overflow. Complexity: O(hidden * (xx + hidden)).
pub fn deep_gru_cell(x: &Vec[Int], h: &Vec[Int], wz: &Vec[Int], wr: &Vec[Int], wh: &Vec[Int], bz: &Vec[Int], br: &Vec[Int], bh: &Vec[Int], hidden: Int) -> Result[Vec[Int], Str] {
  let hh = hidden;
  let xx = x.len();
  if hh <= 0 {
    return _err_ints("deep: gru hidden must be positive");
  }
  if xx <= 0 {
    return _err_ints("deep: gru input must not be empty");
  }
  if h.len() != hh {
    return _err_ints("deep: gru hidden state length mismatch");
  }
  if bz.len() != hh {
    return _err_ints("deep: gru bz length mismatch");
  }
  if br.len() != hh {
    return _err_ints("deep: gru br length mismatch");
  }
  if bh.len() != hh {
    return _err_ints("deep: gru bh length mismatch");
  }
  let width = xx + hh;
  if _dp_mul_overflows(hh, width) {
    return _err_ints("deep: gru shape overflows");
  }
  let wcount = hh * width;
  if wz.len() != wcount {
    return _err_ints("deep: gru wz length does not match the shape");
  }
  if wr.len() != wcount {
    return _err_ints("deep: gru wr length does not match the shape");
  }
  if wh.len() != wcount {
    return _err_ints("deep: gru wh length does not match the shape");
  }
  let cat = _dp_concat(x, h);
  var zvec = Vec[Int].new();
  var rvec = Vec[Int].new();
  var i = 0;
  while i < hh {
    let rz = _dp_gate(wz, &cat, i, width, bz, i);
    match rz {
      Err(e) => { return _err_ints(e); },
      Ok(pz) => {
        let rr = _dp_gate(wr, &cat, i, width, br, i);
        match rr {
          Err(e) => { return _err_ints(e); },
          Ok(pr) => {
            zvec.push(deep_sigmoid(pz));
            rvec.push(deep_sigmoid(pr));
          },
        }
      },
    }
    i = i + 1;
  }
  var rh = Vec[Int].new();
  i = 0;
  while i < hh {
    let ri: Int = rvec[i];
    let hi: Int = h[i];
    if _dp_mul_overflows(ri, hi) {
      return _err_ints("deep: gru reset product overflows");
    }
    rh.push(deep_div_round(ri * hi, _DP_SCALE));
    i = i + 1;
  }
  let cat2 = _dp_concat(x, &rh);
  var out = Vec[Int].new();
  i = 0;
  while i < hh {
    let rc = _dp_gate(wh, &cat2, i, width, bh, i);
    match rc {
      Err(e) => { return _err_ints(e); },
      Ok(pc) => {
        let cand = deep_tanh(pc);
        let zi: Int = zvec[i];
        let hi: Int = h[i];
        let one_minus = _DP_SCALE - zi;
        if _dp_mul_overflows(one_minus, hi) {
          return _err_ints("deep: gru update product overflows");
        }
        let a1 = one_minus * hi;
        if _dp_mul_overflows(zi, cand) {
          return _err_ints("deep: gru update product overflows");
        }
        let a2 = zi * cand;
        if _dp_add_overflows(a1, a2) {
          return _err_ints("deep: gru update accumulation overflows");
        }
        out.push(deep_div_round(a1 + a2, _DP_SCALE));
      },
    }
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Attention / transformer blocks
// ---------------------------------------------------------------------------

/// Scaled dot-product attention scores: score_j = round(q . keys_j / (scale *
/// sqrt(d))). Params: q (length d); keys row-major [n x d]; d = key_dim > 0
/// and keys.len() a multiple of d. Complexity: O(n * d).
pub fn deep_attention_scores(q: &Vec[Int], keys: &Vec[Int], key_dim: Int) -> Result[Vec[Int], Str] {
  let d = key_dim;
  if d <= 0 {
    return _err_ints("deep: attention key dimension must be positive");
  }
  if q.len() != d {
    return _err_ints("deep: attention query dimension mismatch");
  }
  if keys.len() % d != 0 {
    return _err_ints("deep: attention key matrix is ragged");
  }
  let root = deep_int_sqrt(d);
  if root <= 0 {
    return _err_ints("deep: attention dimension too small");
  }
  let n = keys.len() / d;
  var out = Vec[Int].new();
  var j = 0;
  while j < n {
    let r = _dp_dot(keys, q, j, d);
    match r {
      Err(e) => { return _err_ints(e); },
      Ok(raw) => {
        out.push(deep_div_round(deep_div_round(raw, _DP_SCALE), root));
      },
    }
    j = j + 1;
  }
  return _ok_ints(out);
}

/// Single attention head: softmax(scores) weighted sum of `values`.
/// Params: q (key_dim); keys [n x key_dim]; values [n x val_dim]; val_dim > 0.
/// Returns: Ok(out) of length val_dim in 1e-4 units. Error case: shape
/// mismatch, empty softmax, product/sum overflow. Complexity: O(n*(d+val)).
pub fn deep_attention_head(q: &Vec[Int], keys: &Vec[Int], values: &Vec[Int], key_dim: Int, val_dim: Int) -> Result[Vec[Int], Str] {
  if val_dim <= 0 {
    return _err_ints("deep: attention value dimension must be positive");
  }
  let sc = deep_attention_scores(q, keys, key_dim);
  match sc {
    Err(e) => { return _err_ints(e); },
    Ok(scores) => {
      let pr = deep_softmax(&scores);
      match pr {
        Err(e) => { return _err_ints(e); },
        Ok(probs) => {
          let n = scores.len();
          if values.len() != n * val_dim {
            return _err_ints("deep: attention value matrix does not match the score count");
          }
          var out = Vec[Int].new();
          var k = 0;
          while k < val_dim {
            var s: Int = 0;
            var j = 0;
            while j < n {
              let pj: Int = probs[j];
              let vj: Int = values[j * val_dim + k];
              if _dp_mul_overflows(pj, vj) {
                return _err_ints("deep: attention product overflows");
              }
              let t = pj * vj;
              if _dp_add_overflows(s, t) {
                return _err_ints("deep: attention sum overflows");
              }
              s = s + t;
              j = j + 1;
            }
            out.push(deep_div_round(s, _DP_SCALE));
            k = k + 1;
          }
          return _ok_ints(out);
        },
      }
    },
  }
  return _err_ints("deep: attention failed");
}

/// Position-wise feed-forward block: relu -> linear (same as deep_mlp2).
/// Complexity: O(ni*h + h*n_out).
pub fn deep_ffn(x: &Vec[Int], w1: &Vec[Int], b1: &Vec[Int], h: Int, w2: &Vec[Int], b2: &Vec[Int], n_out: Int) -> Result[Vec[Int], Str] {
  return deep_mlp2(x, w1, b1, h, w2, b2, n_out);
}

/// Layer normalization to 1e-4 units: out_i = round((x_i - mean) * scale /
/// sqrt(var)). A constant input yields a zero vector. Error case: empty input
/// or sum/product overflow. Complexity: O(n).
pub fn deep_layer_norm(x: &Vec[Int]) -> Result[Vec[Int], Str] {
  let n = x.len();
  if n <= 0 {
    return _err_ints("deep: layer norm input must not be empty");
  }
  var sum: Int = 0;
  var i = 0;
  while i < n {
    let v: Int = x[i];
    if _dp_add_overflows(sum, v) {
      return _err_ints("deep: layer norm sum overflows");
    }
    sum = sum + v;
    i = i + 1;
  }
  let mean = sum / n;
  var var_sum: Int = 0;
  i = 0;
  while i < n {
    let v: Int = x[i];
    let d = v - mean;
    if _dp_mul_overflows(d, d) {
      return _err_ints("deep: layer norm variance overflows");
    }
    let sq = d * d;
    if _dp_add_overflows(var_sum, sq) {
      return _err_ints("deep: layer norm variance overflows");
    }
    var_sum = var_sum + sq;
    i = i + 1;
  }
  let variance = var_sum / n;
  var out = Vec[Int].new();
  if variance <= 0 {
    return _ok_ints(deep_init_zeros(n));
  }
  let root = deep_int_sqrt(variance);
  if root <= 0 {
    return _ok_ints(deep_init_zeros(n));
  }
  i = 0;
  while i < n {
    let v: Int = x[i];
    let d = v - mean;
    if _dp_mul_overflows(d, _DP_SCALE) {
      return _err_ints("deep: layer norm product overflows");
    }
    out.push(deep_div_round(d * _DP_SCALE, root));
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Private helpers: fixed-point arithmetic
// ---------------------------------------------------------------------------

// Int minimum, expressed as an expression because the literal does not parse.
fn _dp_int_min() -> Int {
  return 0 - _DP_INT_MAX - 1;
}

// True when a * b would leave the signed Int range.
fn _dp_mul_overflows(a: Int, b: Int) -> Bool {
  if a == 0 || b == 0 {
    return false;
  }
  if a > 0 {
    if b > 0 {
      return a > _DP_INT_MAX / b;
    }
    return b < _dp_int_min() / a;
  }
  if b > 0 {
    return a < _dp_int_min() / b;
  }
  return a < _DP_INT_MAX / b;
}

// True when a + b would leave the signed Int range.
fn _dp_add_overflows(a: Int, b: Int) -> Bool {
  if b > 0 {
    return a > _DP_INT_MAX - b;
  }
  if b < 0 {
    return a < _dp_int_min() - b;
  }
  return false;
}

// Piecewise-linear exp approximation for x <= 0 (see xiom.neural SPEC for the
// breakpoint derivation); 0 below -27726 (truncation).
fn _dp_exp(x: Int) -> Int {
  if x >= 0 {
    return _DP_SCALE;
  }
  if x >= -6931 {
    let dx = 0 - x;
    return _DP_SCALE - deep_div_round(dx * 5000, 6931);
  }
  if x >= -13863 {
    let dx = (0 - x) - 6931;
    return 5000 - deep_div_round(dx * 2500, 6931);
  }
  if x >= -20794 {
    let dx = (0 - x) - 13863;
    return 2500 - deep_div_round(dx * 1250, 6931);
  }
  if x >= -27726 {
    let dx = (0 - x) - 20794;
    return 1250 - deep_div_round(dx * 625, 6931);
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Private helpers: vector and matrix primitives
// ---------------------------------------------------------------------------

// Copy an Int vector. Complexity: O(n).
fn _dp_copy_ints(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    out.push(x);
    i = i + 1;
  }
  return out;
}

// Concatenation of two Int vectors. Complexity: O(|a| + |b|).
fn _dp_concat(a: &Vec[Int], b: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < a.len() {
    let v: Int = a[i];
    out.push(v);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    let v: Int = b[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

// Raw dot product of row `row` of `w` (row width ni) with `x`, with overflow
// guards. Returns the un-requantized sum. Complexity: O(ni).
fn _dp_dot(w: &Vec[Int], x: &Vec[Int], row: Int, ni: Int) -> Result[Int, Str] {
  let off = row * ni;
  var s: Int = 0;
  var i = 0;
  while i < ni {
    let wi: Int = w[off + i];
    let xi: Int = x[i];
    if _dp_mul_overflows(wi, xi) {
      return _err_int("deep: dot product overflows");
    }
    let t = wi * xi;
    if _dp_add_overflows(s, t) {
      return _err_int("deep: dot product overflows");
    }
    s = s + t;
    i = i + 1;
  }
  return _ok_int(s);
}

// Requantized linear row: round((row(w) . x) / scale). Complexity: O(ni).
fn _dp_row(w: &Vec[Int], x: &Vec[Int], row: Int, ni: Int) -> Result[Int, Str] {
  let d = _dp_dot(w, x, row, ni);
  match d {
    Err(e) => { return _err_int(e); },
    Ok(raw) => { return _ok_int(deep_div_round(raw, _DP_SCALE)); },
  }
  return _err_int("deep: row failed");
}

// Requantized row plus its bias entry, with an overflow guard.
fn _dp_gate(w: &Vec[Int], x: &Vec[Int], row: Int, ni: Int, b: &Vec[Int], bi: Int) -> Result[Int, Str] {
  let r = _dp_row(w, x, row, ni);
  match r {
    Err(e) => { return _err_int(e); },
    Ok(v) => {
      let bv: Int = b[bi];
      if _dp_add_overflows(v, bv) {
        return _err_int("deep: gate bias addition overflows");
      }
      return _ok_int(v + bv);
    },
  }
  return _err_int("deep: gate failed");
}

// All four LSTM gate pre-activations for unit i, accumulating errors cleanly.
fn _dp_lstm_gates(w: &Vec[Int], cat: &Vec[Int], i: Int, hh: Int, width: Int, b: &Vec[Int]) -> Result[_DpGates, Str] {
  let ri = _dp_gate(w, cat, i, width, b, i);
  match ri {
    Err(e) => { return _err_gates(e); },
    Ok(pi) => {
      let rf = _dp_gate(w, cat, hh + i, width, b, hh + i);
      match rf {
        Err(e) => { return _err_gates(e); },
        Ok(pf) => {
          let rg = _dp_gate(w, cat, 2 * hh + i, width, b, 2 * hh + i);
          match rg {
            Err(e) => { return _err_gates(e); },
            Ok(pg) => {
              let ro = _dp_gate(w, cat, 3 * hh + i, width, b, 3 * hh + i);
              match ro {
                Err(e) => { return _err_gates(e); },
                Ok(po) => { return _ok_gates(_DpGates{ pi: pi; pf: pf; pg: pg; po: po; }); },
              }
            },
          }
        },
      }
    },
  }
  return _err_gates("deep: lstm gates failed");
}

// ---------------------------------------------------------------------------
// Leaf Result constructors (Ok/Err are built only here)
// ---------------------------------------------------------------------------

fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

fn _err_ints(msg: Str) -> Result[Vec[Int], Str] {
  return Err(msg);
}

fn _ok_int(x: Int) -> Result[Int, Str] {
  return Ok(x);
}

fn _err_int(msg: Str) -> Result[Int, Str] {
  return Err(msg);
}

fn _ok_lstm(v: LstmState) -> Result[LstmState, Str] {
  return Ok(v);
}

fn _err_lstm(msg: Str) -> Result[LstmState, Str] {
  return Err(msg);
}

fn _ok_gates(v: _DpGates) -> Result[_DpGates, Str] {
  return Ok(v);
}

fn _err_gates(msg: Str) -> Result[_DpGates, Str] {
  return Err(msg);
}
