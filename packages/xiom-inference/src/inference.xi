// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.inference: deterministic fixed-point model inference
// Port task: replace the xiom.inference placeholder with a pure-XIOM module
// (scaled integers only: no floats, no FFI, no I/O, no Vec[Float64], no
// training).
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   - fixed point: every weight, bias, activation, logit and probability is an
//     Int in units of 1e-4 (_INF_SCALE = 10000 == 1.0); products are
//     requantized by dividing by the scale with half-away-from-zero rounding;
//   - descriptor: parallel vectors only (no Vec[StructType]) -- widths, layer
//     kinds, per-layer activation codes, one concatenated weight tensor and
//     one concatenated bias tensor. Two layer kinds: DENSE (weights + bias +
//     activation) and ACT (elementwise activation, widths preserved);
//   - optimized forward: per-layer weight and bias offsets are precomputed at
//     build time and validated on every entry point, so the forward pass never
//     recomputes or searches an offset;
//   - forward pass: dense layers with guarded dot products (product, dot-sum
//     and bias-add overflow checks), requantization after each dot product,
//     then a local activation; the whole structure and the input width are
//     validated before any arithmetic;
//   - activations: relu, leaky relu (slope 1/10), sigmoid and tanh from a
//     documented rational fixed-point approximation, and linear; all local,
//     no stdlib math;
//   - softmax: max-shifted logits, a piecewise-linear exp approximation with
//     breakpoints at multiples of ln 2, exact integer normalization;
//   - argmax prediction: highest value, ties go to the lowest index;
//   - batch: a flat row-major input tensor is validated to be a positive
//     multiple of the input width and every row is forwarded independently;
//   - streaming: a sliding window (window == input width, stride >= 1) over a
//     flat signal, with a closed-form window count helper;
//   - quantization: per-tensor arithmetic shift q = round_half_away(x / 2^s),
//     dequantization x' = q * 2^s, documented bound |x - x'| <= 2^(s-1) for
//     s >= 1 (0 for s = 0), an automatic shift chooser for a target peak
//     magnitude, and a weight-trained model quantizer; the bound is pinned in
//     SPEC.md and proven by the tests;
//   - export/import: a canonical text dump and a little-endian binary dump,
//     both lossless and strictly validated (wrong magic/version, truncation,
//     trailing bytes and every structural violation are rejected).
//
// Out of scope for v0.1.0: training, backpropagation, convolution, dropout,
// batch norm, weight initialization, GPU kernels, float paths, foreign
// exchange formats other than the two documented dumps.
//
// v0.62.2 notes that shaped this module:
//   * every Vec element read binds the element to a typed local before use;
//     struct fields are read the same way;
//   * Str values are never compared with `==`; the text lexer classifies a
//     token byte by byte (masked widenings) and keyword comparison is bytewise;
//   * Ok/Err construction is confined to the leaf helpers at the bottom;
//   * free functions only: no methods, generics, callbacks, self or indexed
//     function-table dispatch; the model holds parallel Vecs;
//   * Vec parameters are read-only `&Vec[Int]` (or `&mut Vec[Int]` for the
//     private assembly helpers), scalars are threaded through return values;
//   * every loop either advances its index or exits, so hostile text and binary
//     inputs always terminate; binary tensor counts are also bounded.

module xiom.inference

use xiom.string;
use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Fixed-point scale: 10000 units = 1.0 (resolution 1e-4).
const _INF_SCALE: Int = 10000;
// Signed 64-bit envelope (Int). The minimum is built by _inf_int_min().
const _INF_INT_MAX: Int = 9223372036854775807;

// Layer kind codes (documented in SPEC.md section 3).
const _INF_KIND_DENSE: Int = 0;
const _INF_KIND_ACT: Int = 1;
const _INF_KIND_MAX: Int = 1;

// Activation codes (documented in SPEC.md section 4).
const _INF_ACT_RELU: Int = 0;
const _INF_ACT_LEAKY: Int = 1;
const _INF_ACT_SIGMOID: Int = 2;
const _INF_ACT_TANH: Int = 3;
const _INF_ACT_LINEAR: Int = 4;
const _INF_ACT_MAX: Int = 4;

// Leaky relu slope is exactly 1/10.
const _INF_LEAKY_DIV: Int = 10;

// Piecewise-linear exp breakpoints, negated; integer renderings of
// -k*ln2 at scale 1e-4 (ln2 = 0.6931).
const _INF_EXP_1: Int = -6931;
const _INF_EXP_2: Int = -13863;
const _INF_EXP_3: Int = -20794;
const _INF_EXP_4: Int = -27726;

// Caps that make hostile inputs fail closed.
const _INF_MAX_LAYERS: Int = 1024;
const _INF_MAX_PARAMS: Int = 16777216;
const _INF_MAX_SHIFT: Int = 62;

// Text lexer token kinds.
const _INF_TOK_MAGIC: Int = 1;
const _INF_TOK_VERSION: Int = 2;
const _INF_TOK_LAYERS: Int = 3;
const _INF_TOK_WIDTHS: Int = 4;
const _INF_TOK_KINDS: Int = 5;
const _INF_TOK_ACTS: Int = 6;
const _INF_TOK_WEIGHTS: Int = 7;
const _INF_TOK_BIASES: Int = 8;
const _INF_TOK_END: Int = 9;
const _INF_TOK_INT: Int = 10;
const _INF_TOK_EOF: Int = 11;
const _INF_TOK_BAD: Int = 12;

// Binary dump magic ('X', 'I', 'N', 'F') and format version.
const _INF_MAGIC_0: Int = 88;
const _INF_MAGIC_1: Int = 73;
const _INF_MAGIC_2: Int = 78;
const _INF_MAGIC_3: Int = 70;
const _INF_BIN_VERSION: Int = 1;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A sequential fixed-point inference model.
///
/// `widths` has `n_layers + 1` positive entries: widths[0] is the input width
/// and widths[k+1] is the output width of layer k. `kinds` has one kind code
/// per layer (_INF_KIND_DENSE or _INF_KIND_ACT). `activations` has one code in
/// [0, 4] per layer: for DENSE it is applied after requantization and the
/// bias, for ACT it is the layer operation itself. `weights` concatenates the
/// row-major dense matrices (dense layer k, output j, input i at
/// w_offsets[k] + j * widths[k] + i) and `biases` concatenates the dense bias
/// vectors. `w_offsets` / `b_offsets` are prefix sums of the per-layer counts,
/// precomputed at build time and re-validated by every entry point.
///
/// Fields are internal implementation detail; build a model with
/// inference_model (or inference_import_text / inference_import_bin) and
/// query it with the inference_* helpers.
pub type Model = {
  n_layers: Int;
  n_inputs: Int;
  n_outputs: Int;
  widths: Vec[Int];
  kinds: Vec[Int];
  activations: Vec[Int];
  weights: Vec[Int];
  biases: Vec[Int];
  w_offsets: Vec[Int];
  b_offsets: Vec[Int];
}

// Text lexer token: position just past the token, its kind and its integer
// value (0 for keywords and EOF). Returned by value so the parser threads the
// scan position through returns, never through a &mut Int.
type _InfTok = {
  pos: Int;
  kind: Int;
  value: Int;
}

// Binary reader result: position just past the decoded integer, ok == 1 on
// success, and the decoded two's-complement Int value.
type _InfRead = {
  pos: Int;
  ok: Int;
  value: Int;
}

// ---------------------------------------------------------------------------
// Scale, kind and activation codes
// ---------------------------------------------------------------------------

/// Fixed-point scale (10000; one unit is 1e-4). Complexity: O(1).
pub fn inference_scale() -> Int {
  return _INF_SCALE;
}

/// Layer kind code for a dense layer (0). Complexity: O(1).
pub fn inference_kind_dense() -> Int {
  return _INF_KIND_DENSE;
}

/// Layer kind code for an elementwise activation layer (1). Complexity: O(1).
pub fn inference_kind_activation() -> Int {
  return _INF_KIND_ACT;
}

/// Activation code for relu (0). Complexity: O(1).
pub fn inference_act_relu() -> Int {
  return _INF_ACT_RELU;
}

/// Activation code for leaky relu, slope 1/10 (1). Complexity: O(1).
pub fn inference_act_leaky() -> Int {
  return _INF_ACT_LEAKY;
}

/// Activation code for sigmoid (2). Complexity: O(1).
pub fn inference_act_sigmoid() -> Int {
  return _INF_ACT_SIGMOID;
}

/// Activation code for tanh (3). Complexity: O(1).
pub fn inference_act_tanh() -> Int {
  return _INF_ACT_TANH;
}

/// Activation code for linear / identity (4). Complexity: O(1).
pub fn inference_act_linear() -> Int {
  return _INF_ACT_LINEAR;
}

// ---------------------------------------------------------------------------
// Model construction
// ---------------------------------------------------------------------------

/// Build a model from flat, validated parts (all values 1e-4 units).
///
/// Params: widths - positive layer widths, n_layers + 1 entries (>= 2);
///         kinds - one kind code per layer (n_layers entries);
///         activations - one code in [0, 4] per layer (n_layers entries);
///         weights - concatenated row-major dense matrices; the exact length
///         is the sum of widths[k] * widths[k+1] over dense layers;
///         biases - concatenated dense bias vectors; the exact length is the
///         sum of widths[k+1] over dense layers.
/// Returns: Ok(Model) with the parts copied in and the weight / bias offsets
/// precomputed; the caller may keep and reuse its vectors.
/// Validation order: layer count, kind count, activation count, widths
/// positivity, kind range, activation-layer width, activation range,
/// dimensions overflow, weights length, biases length.
/// Error case: Err("inference: ...") for any shape violation.
/// Complexity: O(parts).
pub fn inference_model(widths: &Vec[Int], kinds: &Vec[Int], activations: &Vec[Int], weights: &Vec[Int], biases: &Vec[Int]) -> Result[Model, Str] {
  let nw = widths.len();
  if nw < 2 {
    return _err_model("inference: need at least one layer");
  }
  let n_layers = nw - 1;
  if kinds.len() != n_layers {
    return _err_model("inference: kind count does not match layer count");
  }
  if activations.len() != n_layers {
    return _err_model("inference: activation count does not match layer count");
  }
  var i = 0;
  while i < nw {
    let w: Int = widths[i];
    if w <= 0 {
      return _err_model("inference: widths must be positive");
    }
    i = i + 1;
  }
  i = 0;
  while i < n_layers {
    let kd: Int = kinds[i];
    if kd < 0 || kd > _INF_KIND_MAX {
      return _err_model("inference: unknown layer kind");
    }
    if kd == _INF_KIND_ACT {
      let wi: Int = widths[i];
      let wo: Int = widths[i + 1];
      if wi != wo {
        return _err_model("inference: activation layer changes width");
      }
    }
    let a: Int = activations[i];
    if a < 0 || a > _INF_ACT_MAX {
      return _err_model("inference: unknown activation code");
    }
    i = i + 1;
  }
  var w_total: Int = 0;
  var b_total: Int = 0;
  var k = 0;
  while k < n_layers {
    let kd: Int = kinds[k];
    if kd == _INF_KIND_DENSE {
      let ni: Int = widths[k];
      let no: Int = widths[k + 1];
      if ni > _INF_INT_MAX / no {
        return _err_model("inference: dimensions overflow");
      }
      let wc = ni * no;
      if wc > _INF_INT_MAX - w_total {
        return _err_model("inference: dimensions overflow");
      }
      w_total = w_total + wc;
      if no > _INF_INT_MAX - b_total {
        return _err_model("inference: dimensions overflow");
      }
      b_total = b_total + no;
    }
    k = k + 1;
  }
  if weights.len() != w_total {
    return _err_model("inference: weights length does not match the shape");
  }
  if biases.len() != b_total {
    return _err_model("inference: biases length does not match the shape");
  }
  let n_inputs: Int = widths[0];
  let n_outputs: Int = widths[n_layers];
  var w_offsets = Vec[Int].new();
  var b_offsets = Vec[Int].new();
  w_offsets.push(0);
  b_offsets.push(0);
  var wt: Int = 0;
  var bt: Int = 0;
  k = 0;
  while k < n_layers {
    let kd: Int = kinds[k];
    if kd == _INF_KIND_DENSE {
      let ni: Int = widths[k];
      let no: Int = widths[k + 1];
      wt = wt + ni * no;
      bt = bt + no;
    }
    w_offsets.push(wt);
    b_offsets.push(bt);
    k = k + 1;
  }
  return _ok_model(Model{ n_layers: n_layers; n_inputs: n_inputs; n_outputs: n_outputs; widths: _inf_copy_ints(widths); kinds: _inf_copy_ints(kinds); activations: _inf_copy_ints(activations); weights: _inf_copy_ints(weights); biases: _inf_copy_ints(biases); w_offsets: w_offsets; b_offsets: b_offsets; });
}

/// Number of layers. Complexity: O(1).
pub fn inference_n_layers(model: &Model) -> Int {
  return model.n_layers;
}

/// Input width (widths[0]). Complexity: O(1).
pub fn inference_n_inputs(model: &Model) -> Int {
  return model.n_inputs;
}

/// Output width (widths[n_layers]). Complexity: O(1).
pub fn inference_n_outputs(model: &Model) -> Int {
  return model.n_outputs;
}

/// Width before layer `k` (widths[k]), or 0 when `k` is out of range.
/// Complexity: O(1).
pub fn inference_layer_width(model: &Model, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= model.widths.len() {
    return 0;
  }
  let w: Int = model.widths[k];
  return w;
}

/// Kind of layer `k`, or -1 when `k` is out of range. Complexity: O(1).
pub fn inference_layer_kind(model: &Model, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  if k >= model.kinds.len() {
    return -1;
  }
  let kd: Int = model.kinds[k];
  return kd;
}

/// Total parameter count: weights + biases. Complexity: O(1).
pub fn inference_parameter_count(model: &Model) -> Int {
  return model.weights.len() + model.biases.len();
}

/// Total dense weight count. Complexity: O(1).
pub fn inference_weight_count(model: &Model) -> Int {
  return model.weights.len();
}

/// Total dense bias count. Complexity: O(1).
pub fn inference_bias_count(model: &Model) -> Int {
  return model.biases.len();
}

/// Dense weight count of layer `k` (widths[k] * widths[k+1]); 0 for an
/// activation layer or an out-of-range index. Complexity: O(1).
pub fn inference_layer_weight_count(model: &Model, k: Int) -> Int {
  if k < 0 || k >= model.n_layers {
    return 0;
  }
  let kd: Int = model.kinds[k];
  if kd != _INF_KIND_DENSE {
    return 0;
  }
  let ni: Int = model.widths[k];
  let no: Int = model.widths[k + 1];
  return ni * no;
}

/// Dense bias count of layer `k` (widths[k+1]); 0 for an activation layer or
/// an out-of-range index. Complexity: O(1).
pub fn inference_layer_bias_count(model: &Model, k: Int) -> Int {
  if k < 0 || k >= model.n_layers {
    return 0;
  }
  let kd: Int = model.kinds[k];
  if kd != _INF_KIND_DENSE {
    return 0;
  }
  let no: Int = model.widths[k + 1];
  return no;
}

// ---------------------------------------------------------------------------
// Forward pass
// ---------------------------------------------------------------------------

/// Sequential forward pass over a fixed-point input vector.
///
/// Params: model - a model built by inference_model or imported from a dump;
///         input - model.n_inputs values in 1e-4 units.
/// Returns: Ok(activations) of length model.n_outputs.
/// Layer math (dense): pre[j] = round_half_away(sum_i w[j,i] * x[i] / 10000)
/// + b[j]; out[j] = activation(pre[j]). Activation layers apply the layer
/// activation elementwise with no arithmetic. Products, the running dot sum
/// and the bias addition are guarded against Int overflow; the structure and
/// the input width are validated before any arithmetic.
/// Error case: Err("inference: ...") for an inconsistent model, an input
/// length mismatch, or a product / dot-sum / bias-add overflow.
/// Complexity: O(sum of dense weight counts).
pub fn inference_forward(model: &Model, input: &Vec[Int]) -> Result[Vec[Int], Str] {
  let v = _inf_validate(model);
  match v {
    Ok(_) => {},
    Err(e) => { return _err_ints(e); },
  }
  let n_in0: Int = model.widths[0];
  if input.len() != n_in0 {
    return _err_ints("inference: input length does not match the input width");
  }
  var cur = Vec[Int].new();
  var i = 0;
  while i < input.len() {
    let x: Int = input[i];
    cur.push(x);
    i = i + 1;
  }
  var k = 0;
  while k < model.n_layers {
    let kind: Int = model.kinds[k];
    let ni: Int = model.widths[k];
    let no: Int = model.widths[k + 1];
    let act: Int = model.activations[k];
    var next = Vec[Int].new();
    if kind == _INF_KIND_ACT {
      var j = 0;
      while j < no {
        let x: Int = cur[j];
        next.push(_inf_activate(act, x));
        j = j + 1;
      }
    } else {
      let w_off: Int = model.w_offsets[k];
      let b_off: Int = model.b_offsets[k];
      var j = 0;
      while j < no {
        var s: Int = 0;
        var ii = 0;
        while ii < ni {
          let w: Int = model.weights[w_off + j * ni + ii];
          let x: Int = cur[ii];
          if _inf_mul_overflows(w, x) {
            return _err_ints("inference: weight input product overflows");
          }
          let term = w * x;
          if term > 0 {
            if s > _INF_INT_MAX - term {
              return _err_ints("inference: dot product overflows");
            }
          } elif term < 0 {
            if s < _inf_int_min() - term {
              return _err_ints("inference: dot product overflows");
            }
          }
          s = s + term;
          ii = ii + 1;
        }
        let pre = _inf_div_round(s, _INF_SCALE);
        let b: Int = model.biases[b_off + j];
        if _inf_add_overflows(pre, b) {
          return _err_ints("inference: bias addition overflows");
        }
        let z = pre + b;
        next.push(_inf_activate(act, z));
        j = j + 1;
      }
    }
    cur = next;
    k = k + 1;
  }
  return _ok_ints(cur);
}

/// Apply one activation to a fixed-point value.
///
/// Params: kind - one of the inference_act_* codes; x - a 1e-4 unit value.
/// Returns: Ok(y) where relu is max(0, x); leaky relu is x for x >= 0 and
/// round_half_away(x / 10) otherwise; sigmoid and tanh use the documented
/// fixed-point rational approximations (SPEC.md section 4); linear is x.
/// Error case: Err("inference: unknown activation code") outside [0, 4].
/// Complexity: O(1).
pub fn inference_activation(kind: Int, x: Int) -> Result[Int, Str] {
  if kind < 0 || kind > _INF_ACT_MAX {
    return _err_int("inference: unknown activation code");
  }
  return _ok_int(_inf_activate(kind, x));
}

// ---------------------------------------------------------------------------
// Softmax and prediction
// ---------------------------------------------------------------------------

/// Softmax over fixed-point logits.
///
/// Params: logits - one 1e-4 unit value per class; must not be empty.
/// Returns: Ok(probs) of the same length; every entry is in [0, 10000]. The
/// maximum logit is subtracted first (shifted values are <= 0); each shifted
/// value goes through the piecewise-linear exp approximation (_inf_exp) and
/// the exponentials are normalized with round_half_away(e_i * 10000 / sum).
/// The entries sum to 10000 up to per-entry rounding (documented in SPEC.md).
/// Error case: Err("inference: ...") for an empty input, a shift underflow, a
/// sum or product overflow.
/// Complexity: O(n).
pub fn inference_softmax(logits: &Vec[Int]) -> Result[Vec[Int], Str] {
  let n = logits.len();
  if n <= 0 {
    return _err_ints("inference: logits must not be empty");
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
    if maxv > 0 && x < _inf_int_min() + maxv {
      return _err_ints("inference: logit shift underflows");
    }
    let shifted = x - maxv;
    let e = _inf_exp(shifted);
    if e > _INF_INT_MAX - total {
      return _err_ints("inference: softmax sum overflows");
    }
    total = total + e;
    exps.push(e);
    i = i + 1;
  }
  if total <= 0 {
    return _err_ints("inference: softmax sum must be positive");
  }
  var out = Vec[Int].new();
  i = 0;
  while i < n {
    let e: Int = exps[i];
    if e > 0 {
      if e > _INF_INT_MAX / _INF_SCALE {
        return _err_ints("inference: softmax product overflows");
      }
    }
    let num = e * _INF_SCALE;
    out.push(_inf_div_round(num, total));
    i = i + 1;
  }
  return _ok_ints(out);
}

/// Index of the highest value; ties go to the lowest index.
///
/// Params: values - any non-empty Int vector.
/// Returns: Ok(index) of the first occurrence of the maximum.
/// Error case: Err("inference: values must not be empty").
/// Complexity: O(n).
pub fn inference_argmax(values: &Vec[Int]) -> Result[Int, Str] {
  let n = values.len();
  if n <= 0 {
    return _err_int("inference: values must not be empty");
  }
  var best = 0;
  var bestv: Int = values[0];
  var i = 1;
  while i < n {
    let x: Int = values[i];
    if x > bestv {
      bestv = x;
      best = i;
    }
    i = i + 1;
  }
  return _ok_int(best);
}

/// Argmax prediction over a forward pass: the class id of the largest raw
/// output value. Params: model, input as in inference_forward. Returns:
/// Ok(class) with ties going to the lowest output index. Error case: the
/// inference_forward errors plus the empty-output argmax error. Complexity:
/// O(forward).
pub fn inference_predict(model: &Model, input: &Vec[Int]) -> Result[Int, Str] {
  let out = inference_forward(model, input);
  match out {
    Ok(v) => { return inference_argmax(&v); },
    Err(e) => { return _err_int(e); },
  }
  return _err_int("inference: prediction failed");
}

/// Softmax probabilities over a forward pass. Params: model, input as in
/// inference_forward. Returns: Ok(probs) of length model.n_outputs, as in
/// inference_softmax. Error case: the inference_forward and inference_softmax
/// errors. Complexity: O(forward).
pub fn inference_predict_probs(model: &Model, input: &Vec[Int]) -> Result[Vec[Int], Str] {
  let out = inference_forward(model, input);
  match out {
    Ok(v) => { return inference_softmax(&v); },
    Err(e) => { return _err_ints(e); },
  }
  return _err_ints("inference: prediction failed");
}

// ---------------------------------------------------------------------------
// Batched and streaming inference
// ---------------------------------------------------------------------------

/// Batched inference over a flat row-major input tensor.
///
/// Params: model - a valid model; inputs - `rows * model.n_inputs` values,
/// rows >= 1, row r occupying [r * n_inputs, (r+1) * n_inputs).
/// Returns: Ok(outputs), a flat row-major tensor of `rows * n_outputs`
/// values; each row is an independent inference_forward result.
/// Error case: Err("inference: batch input length must be a positive multiple
/// of the input width") and the forward errors.
/// Complexity: O(rows * forward).
pub fn inference_batch(model: &Model, inputs: &Vec[Int]) -> Result[Vec[Int], Str] {
  let v = _inf_validate(model);
  match v {
    Ok(_) => {},
    Err(e) => { return _err_ints(e); },
  }
  let n_in: Int = model.n_inputs;
  let total = inputs.len();
  if total <= 0 || n_in <= 0 || total % n_in != 0 {
    return _err_ints("inference: batch input length must be a positive multiple of the input width");
  }
  let rows = total / n_in;
  var out = Vec[Int].new();
  var r = 0;
  while r < rows {
    var row = Vec[Int].new();
    var i = 0;
    while i < n_in {
      let x: Int = inputs[r * n_in + i];
      row.push(x);
      i = i + 1;
    }
    let f = inference_forward(model, &row);
    match f {
      Ok(o) => {
        var j = 0;
        while j < o.len() {
          let y: Int = o[j];
          out.push(y);
          j = j + 1;
        }
      },
      Err(e) => { return _err_ints(e); },
    }
    r = r + 1;
  }
  return _ok_ints(out);
}

/// Number of windows of `window` samples with `stride` over `data_len`
/// samples: 0 when window <= 0, stride <= 0 or data_len < window; otherwise
/// 1 + (data_len - window) / stride. Complexity: O(1).
pub fn inference_stream_count(data_len: Int, window: Int, stride: Int) -> Int {
  if data_len < 0 || window <= 0 || stride <= 0 {
    return 0;
  }
  if data_len < window {
    return 0;
  }
  return 1 + (data_len - window) / stride;
}

/// Streaming (sliding-window) inference over a flat signal.
///
/// Params: model - a valid model; data - a flat signal; window - the window
/// size; must equal model.n_inputs; stride - the hop, >= 1.
/// Returns: Ok(outputs), a flat row-major tensor with one model.n_outputs row
/// per window start p = 0, stride, 2*stride, ... while p + window <=
/// data.len(). The count is inference_stream_count(data.len(), window,
/// stride). Every loop step advances p by stride >= 1, so the scan always
/// terminates.
/// Error case: Err("inference: stream window must equal the input width"),
/// Err("inference: stream stride must be positive") and the forward errors.
/// Complexity: O(windows * forward).
pub fn inference_stream(model: &Model, data: &Vec[Int], window: Int, stride: Int) -> Result[Vec[Int], Str] {
  let v = _inf_validate(model);
  match v {
    Ok(_) => {},
    Err(e) => { return _err_ints(e); },
  }
  let n_in: Int = model.n_inputs;
  if window != n_in {
    return _err_ints("inference: stream window must equal the input width");
  }
  if stride <= 0 {
    return _err_ints("inference: stream stride must be positive");
  }
  let total = data.len();
  var out = Vec[Int].new();
  var pos = 0;
  while pos + window <= total {
    var row = Vec[Int].new();
    var i = 0;
    while i < window {
      let x: Int = data[pos + i];
      row.push(x);
      i = i + 1;
    }
    let f = inference_forward(model, &row);
    match f {
      Ok(o) => {
        var j = 0;
        while j < o.len() {
          let y: Int = o[j];
          out.push(y);
          j = j + 1;
        }
      },
      Err(e) => { return _err_ints(e); },
    }
    pos = pos + stride;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Integer quantization (per-tensor shift)
// ---------------------------------------------------------------------------

/// Smallest per-tensor shift s in [0, 62] with max|x_i| <= max_abs_q * 2^s.
///
/// Params: values - any Int vector (empty means shift 0); max_abs_q - the
/// target peak quantized magnitude, > 0.
/// Returns: Ok(shift), the smallest s that fits the tensor peak; the caller
/// quantizes with inference_quantize(values, shift). Because q = round(x /
/// 2^s) satisfies |q| <= max_abs_q when the peak fits, this picks the finest
/// step (smallest error bound 2^(s-1)) that respects the target magnitude.
/// Error case: Err("inference: quantization max magnitude must be positive")
/// or Err("inference: no quantization shift in range fits the tensor").
/// Complexity: O(n + 63).
pub fn inference_quantize_shift(values: &Vec[Int], max_abs_q: Int) -> Result[Int, Str] {
  if max_abs_q <= 0 {
    return _err_int("inference: quantization max magnitude must be positive");
  }
  var amax: Int = 0;
  var i = 0;
  while i < values.len() {
    let x: Int = values[i];
    let a: Int = _inf_abs_sat(x);
    if a > amax {
      amax = a;
    }
    i = i + 1;
  }
  var s = 0;
  while s <= _INF_MAX_SHIFT {
    let step = 1 << s;
    if max_abs_q > _INF_INT_MAX / step {
      return _ok_int(s);
    }
    if amax <= max_abs_q * step {
      return _ok_int(s);
    }
    s = s + 1;
  }
  return _err_int("inference: no quantization shift in range fits the tensor");
}

/// Rounding error bound 2^(s-1) of inference_quantize / inference_dequantize
/// for shift s: for every x, |x - inference_dequantize(quantize(x))[i]| <=
/// bound. The bound is 0 for s = 0 and 2^(s-1) for 1 <= s <= 62.
/// Error case: Err("inference: quantization shift out of range").
/// Complexity: O(1).
pub fn inference_quantize_error_bound(shift: Int) -> Result[Int, Str] {
  if shift < 0 || shift > _INF_MAX_SHIFT {
    return _err_int("inference: quantization shift out of range");
  }
  if shift == 0 {
    return _ok_int(0);
  }
  return _ok_int(1 << (shift - 1));
}

/// Quantize a tensor with one per-tensor step 2^shift:
/// q_i = round_half_away(x_i / 2^shift). Round-trip error is bounded by
/// inference_quantize_error_bound(shift) after inference_dequantize; values
/// already multiples of 2^shift round-trip exactly.
/// Error case: Err("inference: quantization shift out of range") outside
/// [0, 62]. Complexity: O(n).
pub fn inference_quantize(values: &Vec[Int], shift: Int) -> Result[Vec[Int], Str] {
  if shift < 0 || shift > _INF_MAX_SHIFT {
    return _err_ints("inference: quantization shift out of range");
  }
  let step = 1 << shift;
  var out = Vec[Int].new();
  var i = 0;
  while i < values.len() {
    let x: Int = values[i];
    out.push(_inf_div_round(x, step));
    i = i + 1;
  }
  return _ok_ints(out);
}

/// Dequantize a tensor with one per-tensor step 2^shift: x_i = q_i * 2^shift.
/// Error case: Err("inference: quantization shift out of range") or
/// Err("inference: dequantized value overflows"). Complexity: O(n).
pub fn inference_dequantize(values: &Vec[Int], shift: Int) -> Result[Vec[Int], Str] {
  if shift < 0 || shift > _INF_MAX_SHIFT {
    return _err_ints("inference: quantization shift out of range");
  }
  let step = 1 << shift;
  var out = Vec[Int].new();
  var i = 0;
  while i < values.len() {
    let x: Int = values[i];
    if _inf_mul_overflows(x, step) {
      return _err_ints("inference: dequantized value overflows");
    }
    out.push(x * step);
    i = i + 1;
  }
  return _ok_ints(out);
}

/// Largest magnitude of the dense weight tensor (saturated at Int max for the
/// Int-min element). Feed it to inference_quantize_shift to choose a shift.
/// Error case: the model validation errors. Complexity: O(weights).
pub fn inference_model_weight_absmax(model: &Model) -> Result[Int, Str] {
  let v = _inf_validate(model);
  match v {
    Ok(_) => {},
    Err(e) => { return _err_int(e); },
  }
  var amax: Int = 0;
  var i = 0;
  while i < model.weights.len() {
    let x: Int = model.weights[i];
    let a: Int = _inf_abs_sat(x);
    if a > amax {
      amax = a;
    }
    i = i + 1;
  }
  return _ok_int(amax);
}

/// Quantize every dense weight of a model with one per-tensor shift; widths,
/// kinds, activations, biases and offsets are preserved, so the result is a
/// same-shaped model whose integer weights are round_half_away(w / 2^shift).
/// Dequantizing the new weight tensor with inference_dequantize bounds each
/// weight error by inference_quantize_error_bound(shift). Biases stay exact.
/// Error case: the model validation errors or Err("inference: quantization
/// shift out of range"). Complexity: O(parameters).
pub fn inference_quantize_model(model: &Model, shift: Int) -> Result[Model, Str] {
  let v = _inf_validate(model);
  match v {
    Ok(_) => {},
    Err(e) => { return _err_model(e); },
  }
  if shift < 0 || shift > _INF_MAX_SHIFT {
    return _err_model("inference: quantization shift out of range");
  }
  let step = 1 << shift;
  var qw = Vec[Int].new();
  var i = 0;
  while i < model.weights.len() {
    let w: Int = model.weights[i];
    qw.push(_inf_div_round(w, step));
    i = i + 1;
  }
  let n_layers: Int = model.n_layers;
  let n_inputs: Int = model.n_inputs;
  let n_outputs: Int = model.n_outputs;
  let m_widths: Vec[Int] = model.widths;
  let m_kinds: Vec[Int] = model.kinds;
  let m_acts: Vec[Int] = model.activations;
  let m_biases: Vec[Int] = model.biases;
  let m_wo: Vec[Int] = model.w_offsets;
  let m_bo: Vec[Int] = model.b_offsets;
  return _ok_model(Model{ n_layers: n_layers; n_inputs: n_inputs; n_outputs: n_outputs; widths: _inf_copy_ints(&m_widths); kinds: _inf_copy_ints(&m_kinds); activations: _inf_copy_ints(&m_acts); weights: qw; biases: _inf_copy_ints(&m_biases); w_offsets: _inf_copy_ints(&m_wo); b_offsets: _inf_copy_ints(&m_bo); });
}

// ---------------------------------------------------------------------------
// Canonical text dump
// ---------------------------------------------------------------------------

/// Render the model as deterministic text (the canonical dump).
///
/// Grammar (one record per `\n`-terminated line, tokens separated by ASCII
/// whitespace; all numbers are decimal integers):
///
///   xiom.inference v1
///   layers <n>
///   widths <w0> ... <wn>
///   kinds <k0> ... <k_{n-1}>
///   acts <a0> ... <a_{n-1}>
///   weights <...>          exact dense weight tensor in row-major order
///   biases <...>           exact dense bias vectors in order
///   end
///
/// Returns: Ok(text). The output is stable, so
/// inference_export_text(import_text(dump)) is the same string and
/// inference_import_text accepts exactly this grammar.
/// Error case: the model validation errors. Complexity: O(parameters).
pub fn inference_export_text(model: &Model) -> Result[Str, Str] {
  let v = _inf_validate(model);
  match v {
    Ok(_) => {},
    Err(e) => { return _err_str(e); },
  }
  var out = "xiom.inference v1\nlayers " + convert.int_to_string(model.n_layers) + "\nwidths";
  var i = 0;
  while i < model.widths.len() {
    let w: Int = model.widths[i];
    out = out + " " + convert.int_to_string(w);
    i = i + 1;
  }
  out = out + "\nkinds";
  i = 0;
  while i < model.kinds.len() {
    let kd: Int = model.kinds[i];
    out = out + " " + convert.int_to_string(kd);
    i = i + 1;
  }
  out = out + "\nacts";
  i = 0;
  while i < model.activations.len() {
    let a: Int = model.activations[i];
    out = out + " " + convert.int_to_string(a);
    i = i + 1;
  }
  out = out + "\nweights";
  i = 0;
  while i < model.weights.len() {
    let w: Int = model.weights[i];
    out = out + " " + convert.int_to_string(w);
    i = i + 1;
  }
  out = out + "\nbiases";
  i = 0;
  while i < model.biases.len() {
    let b: Int = model.biases[i];
    out = out + " " + convert.int_to_string(b);
    i = i + 1;
  }
  out = out + "\nend\n";
  return _ok_str(out);
}

/// Parse the canonical text dump back into a model.
///
/// Params: text - the inference_export_text grammar above, with any ASCII
/// whitespace between tokens.
/// Returns: Ok(Model) equivalent to the dumped model; the parser validates
/// the shape exactly like inference_model.
/// Error case: Err("inference: ...") for a wrong magic or version, a
/// non-positive or oversized layer count, a missing or malformed list, and
/// every structural violation inference_model reports, or trailing tokens
/// after `end`.
/// Complexity: O(tokens) with every scan step advancing.
pub fn inference_import_text(text: Str) -> Result[Model, Str] {
  var p = _inf_expect(text, 0, _INF_TOK_MAGIC);
  if p < 0 {
    return _err_model("inference: dump must start with xiom.inference");
  }
  p = _inf_expect(text, p, _INF_TOK_VERSION);
  if p < 0 {
    return _err_model("inference: dump version must be v1");
  }
  p = _inf_expect(text, p, _INF_TOK_LAYERS);
  if p < 0 {
    return _err_model("inference: expected layers");
  }
  let tl = _inf_lex(text, p);
  let tk: Int = tl.kind;
  if tk != _INF_TOK_INT {
    return _err_model("inference: layer count must be an integer");
  }
  let n: Int = tl.value;
  if n <= 0 {
    return _err_model("inference: layer count must be positive");
  }
  if n > _INF_MAX_LAYERS {
    return _err_model("inference: layer count exceeds the limit");
  }
  p = tl.pos;
  p = _inf_expect(text, p, _INF_TOK_WIDTHS);
  if p < 0 {
    return _err_model("inference: expected widths");
  }
  var widths = Vec[Int].new();
  p = _inf_read_ints(text, p, n + 1, &mut widths);
  if p < 0 {
    return _err_model("inference: widths list is truncated or malformed");
  }
  var i = 0;
  while i < widths.len() {
    let w: Int = widths[i];
    if w <= 0 {
      return _err_model("inference: widths must be positive");
    }
    i = i + 1;
  }
  p = _inf_expect(text, p, _INF_TOK_KINDS);
  if p < 0 {
    return _err_model("inference: expected kinds");
  }
  var kinds = Vec[Int].new();
  p = _inf_read_ints(text, p, n, &mut kinds);
  if p < 0 {
    return _err_model("inference: kind list is truncated or malformed");
  }
  p = _inf_expect(text, p, _INF_TOK_ACTS);
  if p < 0 {
    return _err_model("inference: expected acts");
  }
  var acts = Vec[Int].new();
  p = _inf_read_ints(text, p, n, &mut acts);
  if p < 0 {
    return _err_model("inference: activation list is truncated or malformed");
  }
  var w_total: Int = 0;
  var b_total: Int = 0;
  var k = 0;
  while k < n {
    let kd: Int = kinds[k];
    if kd < 0 || kd > _INF_KIND_MAX {
      return _err_model("inference: unknown layer kind");
    }
    if kd == _INF_KIND_ACT {
      let wi: Int = widths[k];
      let wo: Int = widths[k + 1];
      if wi != wo {
        return _err_model("inference: activation layer changes width");
      }
    }
    let a: Int = acts[k];
    if a < 0 || a > _INF_ACT_MAX {
      return _err_model("inference: unknown activation code");
    }
    if kd == _INF_KIND_DENSE {
      let ni: Int = widths[k];
      let no: Int = widths[k + 1];
      if ni > _INF_INT_MAX / no {
        return _err_model("inference: dimensions overflow");
      }
      let wc = ni * no;
      if wc > _INF_INT_MAX - w_total {
        return _err_model("inference: dimensions overflow");
      }
      w_total = w_total + wc;
      if no > _INF_INT_MAX - b_total {
        return _err_model("inference: dimensions overflow");
      }
      b_total = b_total + no;
    }
    k = k + 1;
  }
  p = _inf_expect(text, p, _INF_TOK_WEIGHTS);
  if p < 0 {
    return _err_model("inference: expected weights");
  }
  var weights = Vec[Int].new();
  p = _inf_read_ints(text, p, w_total, &mut weights);
  if p < 0 {
    return _err_model("inference: weights list is truncated or malformed");
  }
  p = _inf_expect(text, p, _INF_TOK_BIASES);
  if p < 0 {
    return _err_model("inference: expected biases");
  }
  var biases = Vec[Int].new();
  p = _inf_read_ints(text, p, b_total, &mut biases);
  if p < 0 {
    return _err_model("inference: biases list is truncated or malformed");
  }
  p = _inf_expect(text, p, _INF_TOK_END);
  if p < 0 {
    return _err_model("inference: expected end");
  }
  let te = _inf_lex(text, p);
  let ek: Int = te.kind;
  if ek != _INF_TOK_EOF {
    return _err_model("inference: unexpected trailing tokens");
  }
  return inference_model(&widths, &kinds, &acts, &weights, &biases);
}

// ---------------------------------------------------------------------------
// Binary dump
// ---------------------------------------------------------------------------

/// Render the model as a deterministic little-endian binary dump.
///
/// Layout: magic 'X','I','N','F' (4 bytes); format version 1 (1 byte); then
/// five self-describing lists in order widths, kinds, acts, weights, biases,
/// each an Int64 count followed by that many little-endian two's-complement
/// Int64 values. The dump is lossless: import(export(m)) has the same text
/// dump as m. Imports reject wrong magic/version, truncation, count
/// mismatches, trailing bytes, tensor counts above 16777216 and every
/// structural violation.
/// Error case: the model validation errors. Complexity: O(parameters).
pub fn inference_export_bin(model: &Model) -> Result[Vec[UInt8], Str] {
  let v = _inf_validate(model);
  match v {
    Ok(_) => {},
    Err(e) => { return _err_bytes(e); },
  }
  var out = Vec[UInt8].new();
  out.push(_INF_MAGIC_0 as UInt8);
  out.push(_INF_MAGIC_1 as UInt8);
  out.push(_INF_MAGIC_2 as UInt8);
  out.push(_INF_MAGIC_3 as UInt8);
  out.push(_INF_BIN_VERSION as UInt8);
  let m_widths: Vec[Int] = model.widths;
  let m_kinds: Vec[Int] = model.kinds;
  let m_acts: Vec[Int] = model.activations;
  let m_weights: Vec[Int] = model.weights;
  let m_biases: Vec[Int] = model.biases;
  _inf_push_int(&mut out, model.n_layers);
  _inf_push_list(&mut out, &m_widths);
  _inf_push_list(&mut out, &m_kinds);
  _inf_push_list(&mut out, &m_acts);
  _inf_push_list(&mut out, &m_weights);
  _inf_push_list(&mut out, &m_biases);
  return _ok_bytes(out);
}

/// Parse the little-endian binary dump back into a model.
///
/// Params: bytes - the inference_export_bin layout.
/// Returns: Ok(Model) equivalent to the dumped model; the parser validates
/// the shape exactly like inference_model.
/// Error case: Err("inference: ...") for a wrong magic or version, a
/// truncated stream, a count that does not match the structure, a tensor
/// count above 16777216, trailing bytes, and every structural violation.
/// Complexity: O(parameters) with every scan step advancing.
pub fn inference_import_bin(bytes: &Vec[UInt8]) -> Result[Model, Str] {
  let n = bytes.len();
  if n < 5 {
    return _err_model("inference: binary dump is truncated");
  }
  if !_inf_magic(bytes) {
    return _err_model("inference: binary dump must start with XINF");
  }
  let ver: Int = (bytes[4] as Int) & 0xFF;
  if ver != _INF_BIN_VERSION {
    return _err_model("inference: binary dump version must be v1");
  }
  let rn = _inf_read_int(bytes, 5);
  let rok: Int = rn.ok;
  if rok != 1 {
    return _err_model("inference: binary dump is truncated");
  }
  let nl: Int = rn.value;
  if nl <= 0 {
    return _err_model("inference: layer count must be positive");
  }
  if nl > _INF_MAX_LAYERS {
    return _err_model("inference: layer count exceeds the limit");
  }
  var p: Int = rn.pos;
  var widths = Vec[Int].new();
  p = _inf_read_list(bytes, p, nl + 1, &mut widths);
  if p < 0 {
    return _err_model("inference: widths list is truncated or malformed");
  }
  var i = 0;
  while i < widths.len() {
    let w: Int = widths[i];
    if w <= 0 {
      return _err_model("inference: widths must be positive");
    }
    i = i + 1;
  }
  var kinds = Vec[Int].new();
  p = _inf_read_list(bytes, p, nl, &mut kinds);
  if p < 0 {
    return _err_model("inference: kind list is truncated or malformed");
  }
  var acts = Vec[Int].new();
  p = _inf_read_list(bytes, p, nl, &mut acts);
  if p < 0 {
    return _err_model("inference: activation list is truncated or malformed");
  }
  var w_total: Int = 0;
  var b_total: Int = 0;
  var k = 0;
  while k < nl {
    let kd: Int = kinds[k];
    if kd < 0 || kd > _INF_KIND_MAX {
      return _err_model("inference: unknown layer kind");
    }
    if kd == _INF_KIND_ACT {
      let wi: Int = widths[k];
      let wo: Int = widths[k + 1];
      if wi != wo {
        return _err_model("inference: activation layer changes width");
      }
    }
    let a: Int = acts[k];
    if a < 0 || a > _INF_ACT_MAX {
      return _err_model("inference: unknown activation code");
    }
    if kd == _INF_KIND_DENSE {
      let ni: Int = widths[k];
      let no: Int = widths[k + 1];
      if ni > _INF_INT_MAX / no {
        return _err_model("inference: dimensions overflow");
      }
      let wc = ni * no;
      if wc > _INF_INT_MAX - w_total {
        return _err_model("inference: dimensions overflow");
      }
      w_total = w_total + wc;
      if no > _INF_INT_MAX - b_total {
        return _err_model("inference: dimensions overflow");
      }
      b_total = b_total + no;
    }
    k = k + 1;
  }
  if w_total > _INF_MAX_PARAMS || b_total > _INF_MAX_PARAMS {
    return _err_model("inference: tensor size exceeds the limit");
  }
  var weights = Vec[Int].new();
  p = _inf_read_list(bytes, p, w_total, &mut weights);
  if p < 0 {
    return _err_model("inference: weights list is truncated or malformed");
  }
  var biases = Vec[Int].new();
  p = _inf_read_list(bytes, p, b_total, &mut biases);
  if p < 0 {
    return _err_model("inference: biases list is truncated or malformed");
  }
  if p != n {
    return _err_model("inference: binary dump has trailing bytes");
  }
  return inference_model(&widths, &kinds, &acts, &weights, &biases);
}

// ---------------------------------------------------------------------------
// Private helpers: fixed-point arithmetic
// ---------------------------------------------------------------------------

// Int minimum (-2^63), expressed as an expression because the literal does
// not parse (repo-wide convention). Complexity: O(1).
fn _inf_int_min() -> Int {
  return 0 - _INF_INT_MAX - 1;
}

// Absolute value, saturated at Int max for the Int-min element (whose
// magnitude is not representable). Complexity: O(1).
fn _inf_abs_sat(v: Int) -> Int {
  if v == _inf_int_min() {
    return _INF_INT_MAX;
  }
  if v < 0 {
    return 0 - v;
  }
  return v;
}

// True when a * b would leave the signed Int range. All four sign cases are
// handled with truncating division, which is exact for this test.
// Complexity: O(1).
fn _inf_mul_overflows(a: Int, b: Int) -> Bool {
  if a == 0 || b == 0 {
    return false;
  }
  if a > 0 {
    if b > 0 {
      return a > _INF_INT_MAX / b;
    }
    return b < _inf_int_min() / a;
  }
  if b > 0 {
    return a < _inf_int_min() / b;
  }
  return a < _INF_INT_MAX / b;
}

// True when a + b would leave the signed Int range. Complexity: O(1).
fn _inf_add_overflows(a: Int, b: Int) -> Bool {
  if b > 0 {
    return a > _INF_INT_MAX - b;
  }
  if b < 0 {
    return a < _inf_int_min() - b;
  }
  return false;
}

// Truncating division with halves rounded away from zero (b > 0). The
// doubled magnitude is guarded, so no denominator can overflow it. Used for
// every division in the module. Complexity: O(1).
fn _inf_div_round(a: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  var mag = r;
  if mag < 0 {
    mag = 0 - mag;
  }
  var round_away = false;
  if mag > _INF_INT_MAX / 2 {
    round_away = true;
  } elif mag * 2 >= b {
    round_away = true;
  }
  if round_away {
    if a < 0 {
      return q - 1;
    }
    return q + 1;
  }
  return q;
}

// Apply an already-validated activation code (0..4). Complexity: O(1).
fn _inf_activate(kind: Int, x: Int) -> Int {
  if kind == _INF_ACT_RELU {
    if x < 0 {
      return 0;
    }
    return x;
  }
  if kind == _INF_ACT_LEAKY {
    if x >= 0 {
      return x;
    }
    return _inf_div_round(x, _INF_LEAKY_DIV);
  }
  if kind == _INF_ACT_SIGMOID {
    return _inf_sigmoid(x);
  }
  if kind == _INF_ACT_TANH {
    return _inf_tanh(x);
  }
  return x;
}

// Fast sigmoid: s(x) = 1/2 + (x / (1 + |x|)) / 2, evaluated in 1e-4 units:
// t = round(x * 10000 / (10000 + |x|)), s = round((10000 + t) / 2). The
// result is in [0, 10000], s(0) = 5000 and s(-x) = 10000 - s(x). Very large
// |x| saturates to 0 / 10000. Complexity: O(1).
fn _inf_sigmoid(x: Int) -> Int {
  if x == 0 {
    return _INF_SCALE / 2;
  }
  if x > 0 {
    if x > _INF_INT_MAX / _INF_SCALE {
      return _INF_SCALE;
    }
    let t = _inf_div_round(x * _INF_SCALE, _INF_SCALE + x);
    return _inf_div_round(_INF_SCALE + t, 2);
  }
  let ax = 0 - x;
  if ax > _INF_INT_MAX / _INF_SCALE {
    return 0;
  }
  let t = _inf_div_round(x * _INF_SCALE, _INF_SCALE + ax);
  return _inf_div_round(_INF_SCALE + t, 2);
}

// Tanh from the sigmoid above: tanh(x) = 2 * s(2x) - 1. 2x saturates to
// +10000 / -10000 for |x| beyond half the Int range. Complexity: O(1).
fn _inf_tanh(x: Int) -> Int {
  if x == 0 {
    return 0;
  }
  if x > 0 {
    if x > _INF_INT_MAX / 2 {
      return _INF_SCALE;
    }
    let s = _inf_sigmoid(x * 2);
    return 2 * s - _INF_SCALE;
  }
  if x < _inf_int_min() / 2 {
    return 0 - _INF_SCALE;
  }
  let s = _inf_sigmoid(x * 2);
  return 2 * s - _INF_SCALE;
}

// Piecewise-linear exp approximation for x <= 0, in 1e-4 units: exp(x) is
// interpolated between the breakpoints (0, 10000), (-6931, 5000),
// (-13863, 2500), (-20794, 1250), (-27726, 625); below -27726 the result is
// 0 (truncation, documented). Every segment interpolates with
// round_half_away(dx * drop / 6931), so the values are hand-computable and
// monotone. Complexity: O(1).
fn _inf_exp(x: Int) -> Int {
  if x >= 0 {
    return _INF_SCALE;
  }
  if x >= _INF_EXP_1 {
    let dx = 0 - x;
    return _INF_SCALE - _inf_div_round(dx * 5000, 6931);
  }
  if x >= _INF_EXP_2 {
    let dx = (0 - x) + _INF_EXP_1;
    return 5000 - _inf_div_round(dx * 2500, 6931);
  }
  if x >= _INF_EXP_3 {
    let dx = (0 - x) + _INF_EXP_2;
    return 2500 - _inf_div_round(dx * 1250, 6931);
  }
  if x >= _INF_EXP_4 {
    let dx = (0 - x) + _INF_EXP_3;
    return 1250 - _inf_div_round(dx * 625, 6931);
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Private helpers: model structure
// ---------------------------------------------------------------------------

// Validate a Model value field by field (the fields of a pub type can be
// assembled by hand, so every public entry point re-checks, including the
// parallel-vector lengths and the precomputed offsets). Returns Ok(0) for a
// valid model, Err(message) for the first violation. Complexity: O(parts).
fn _inf_validate(model: &Model) -> Result[Int, Str] {
  let n_layers = model.n_layers;
  if n_layers <= 0 {
    return _err_int("inference: need at least one layer");
  }
  if model.widths.len() != n_layers + 1 {
    return _err_int("inference: network widths are inconsistent");
  }
  if model.kinds.len() != n_layers {
    return _err_int("inference: network kinds are inconsistent");
  }
  if model.activations.len() != n_layers {
    return _err_int("inference: network activations are inconsistent");
  }
  if model.w_offsets.len() != n_layers + 1 {
    return _err_int("inference: network offsets are inconsistent");
  }
  if model.b_offsets.len() != n_layers + 1 {
    return _err_int("inference: network offsets are inconsistent");
  }
  if model.n_inputs != model.widths[0] {
    return _err_int("inference: network widths are inconsistent");
  }
  var i = 0;
  while i < model.widths.len() {
    let w: Int = model.widths[i];
    if w <= 0 {
      return _err_int("inference: widths must be positive");
    }
    i = i + 1;
  }
  var w_total: Int = 0;
  var b_total: Int = 0;
  i = 0;
  while i < n_layers {
    let kd: Int = model.kinds[i];
    if kd < 0 || kd > _INF_KIND_MAX {
      return _err_int("inference: unknown layer kind");
    }
    if kd == _INF_KIND_ACT {
      let wi: Int = model.widths[i];
      let wo: Int = model.widths[i + 1];
      if wi != wo {
        return _err_int("inference: activation layer changes width");
      }
    }
    let a: Int = model.activations[i];
    if a < 0 || a > _INF_ACT_MAX {
      return _err_int("inference: unknown activation code");
    }
    let w_off: Int = model.w_offsets[i];
    let b_off: Int = model.b_offsets[i];
    if w_off != w_total {
      return _err_int("inference: network offsets are inconsistent");
    }
    if b_off != b_total {
      return _err_int("inference: network offsets are inconsistent");
    }
    if kd == _INF_KIND_DENSE {
      let ni: Int = model.widths[i];
      let wo2: Int = model.widths[i + 1];
      if ni > _INF_INT_MAX / wo2 {
        return _err_int("inference: dimensions overflow");
      }
      let wc = ni * wo2;
      if wc > _INF_INT_MAX - w_total {
        return _err_int("inference: dimensions overflow");
      }
      w_total = w_total + wc;
      if wo2 > _INF_INT_MAX - b_total {
        return _err_int("inference: dimensions overflow");
      }
      b_total = b_total + wo2;
    }
    i = i + 1;
  }
  if model.n_outputs != model.widths[n_layers] {
    return _err_int("inference: network widths are inconsistent");
  }
  let last_wo: Int = model.w_offsets[n_layers];
  if last_wo != w_total {
    return _err_int("inference: network offsets are inconsistent");
  }
  let last_bo: Int = model.b_offsets[n_layers];
  if last_bo != b_total {
    return _err_int("inference: network offsets are inconsistent");
  }
  if model.weights.len() != w_total {
    return _err_int("inference: network weights are inconsistent");
  }
  if model.biases.len() != b_total {
    return _err_int("inference: network biases are inconsistent");
  }
  return _ok_int(0);
}

// Copy an Int vector (model parts are owned by the model, so the caller keeps
// its input vectors). Complexity: O(n).
fn _inf_copy_ints(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    out.push(x);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Private helpers: text lexer and parser
// ---------------------------------------------------------------------------

// ASCII whitespace: space, LF, CR, tab. Complexity: O(1).
fn _inf_is_ws(b: Int) -> Bool {
  if b == 32 {
    return true;
  }
  if b == 10 {
    return true;
  }
  if b == 13 {
    return true;
  }
  if b == 9 {
    return true;
  }
  return false;
}

// Read one byte as a masked Int (0..255). Complexity: O(1).
fn _inf_byte(text: Str, pos: Int) -> Int {
  return (string.byte_at(text, pos) as Int) & 0xFF;
}

// True when the token text[start, end) equals the ASCII of `kw`. Compares
// byte by byte; no Str equality is used. Complexity: O(|kw|).
fn _inf_match_kw(text: Str, start: Int, end: Int, kw: Str) -> Bool {
  if end - start != kw.len() {
    return false;
  }
  var i = 0;
  while i < kw.len() {
    let tb: Int = _inf_byte(text, start + i);
    let kb: Int = _inf_byte(kw, i);
    if tb != kb {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Lex one token starting at `pos`: skip ASCII whitespace, then classify the
// [start, end) run. Keywords get their _INF_TOK_* kind; a signed decimal run
// (optional '-', at least one digit, magnitude <= Int max) gets _INF_TOK_INT
// with the value; end of text gets _INF_TOK_EOF; anything else gets
// _INF_TOK_BAD. Every scan step advances or exits. Complexity: O(token).
fn _inf_lex(text: Str, pos: Int) -> _InfTok {
  let n = text.len();
  var p = pos;
  var scanning = true;
  while scanning {
    if p >= n {
      scanning = false;
    } else {
      let b: Int = _inf_byte(text, p);
      if _inf_is_ws(b) {
        p = p + 1;
      } else {
        scanning = false;
      }
    }
  }
  if p >= n {
    return _InfTok{ pos: p; kind: _INF_TOK_EOF; value: 0; };
  }
  var e = p;
  var scanning2 = true;
  while scanning2 {
    if e >= n {
      scanning2 = false;
    } else {
      let b: Int = _inf_byte(text, e);
      if _inf_is_ws(b) {
        scanning2 = false;
      } else {
        e = e + 1;
      }
    }
  }
  if _inf_match_kw(text, p, e, "xiom.inference") {
    return _InfTok{ pos: e; kind: _INF_TOK_MAGIC; value: 0; };
  }
  if _inf_match_kw(text, p, e, "v1") {
    return _InfTok{ pos: e; kind: _INF_TOK_VERSION; value: 0; };
  }
  if _inf_match_kw(text, p, e, "layers") {
    return _InfTok{ pos: e; kind: _INF_TOK_LAYERS; value: 0; };
  }
  if _inf_match_kw(text, p, e, "widths") {
    return _InfTok{ pos: e; kind: _INF_TOK_WIDTHS; value: 0; };
  }
  if _inf_match_kw(text, p, e, "kinds") {
    return _InfTok{ pos: e; kind: _INF_TOK_KINDS; value: 0; };
  }
  if _inf_match_kw(text, p, e, "acts") {
    return _InfTok{ pos: e; kind: _INF_TOK_ACTS; value: 0; };
  }
  if _inf_match_kw(text, p, e, "weights") {
    return _InfTok{ pos: e; kind: _INF_TOK_WEIGHTS; value: 0; };
  }
  if _inf_match_kw(text, p, e, "biases") {
    return _InfTok{ pos: e; kind: _INF_TOK_BIASES; value: 0; };
  }
  if _inf_match_kw(text, p, e, "end") {
    return _InfTok{ pos: e; kind: _INF_TOK_END; value: 0; };
  }
  let b0: Int = _inf_byte(text, p);
  if b0 == 45 || (b0 >= 48 && b0 <= 57) {
    var i = p;
    var neg = false;
    if b0 == 45 {
      neg = true;
      i = p + 1;
    }
    var v: Int = 0;
    var digits = 0;
    var good = true;
    while good && i < e {
      let d: Int = _inf_byte(text, i) - 48;
      if d < 0 || d > 9 {
        good = false;
      } elif v > (_INF_INT_MAX - d) / 10 {
        good = false;
      } else {
        v = v * 10 + d;
        digits = digits + 1;
        i = i + 1;
      }
    }
    if good && digits > 0 {
      if neg {
        v = 0 - v;
      }
      return _InfTok{ pos: e; kind: _INF_TOK_INT; value: v; };
    }
    return _InfTok{ pos: e; kind: _INF_TOK_BAD; value: 0; };
  }
  return _InfTok{ pos: e; kind: _INF_TOK_BAD; value: 0; };
}

// Lex the next token and require the given kind; returns the position past it
// or -1 on mismatch. Complexity: O(token).
fn _inf_expect(text: Str, pos: Int, kind: Int) -> Int {
  let t = _inf_lex(text, pos);
  let tk: Int = t.kind;
  if tk != kind {
    return -1;
  }
  return t.pos;
}

// Append exactly `count` decimal integer tokens from `pos`, returning the
// position past the last one, or -1 when a token is missing or is not an
// integer. `out` is appended in place (a &mut Vec parameter, per the module
// conventions). Complexity: O(count * token).
fn _inf_read_ints(text: Str, pos: Int, count: Int, out: &mut Vec[Int]) -> Int {
  var p = pos;
  var i = 0;
  while i < count {
    let t = _inf_lex(text, p);
    let tk: Int = t.kind;
    if tk != _INF_TOK_INT {
      return -1;
    }
    out.push(t.value);
    p = t.pos;
    i = i + 1;
  }
  return p;
}

// ---------------------------------------------------------------------------
// Private helpers: binary codec
// ---------------------------------------------------------------------------

// True when bytes starts with the XINF magic. Complexity: O(1).
fn _inf_magic(bytes: &Vec[UInt8]) -> Bool {
  if bytes.len() < 4 {
    return false;
  }
  let b0: Int = (bytes[0] as Int) & 0xFF;
  let b1: Int = (bytes[1] as Int) & 0xFF;
  let b2: Int = (bytes[2] as Int) & 0xFF;
  let b3: Int = (bytes[3] as Int) & 0xFF;
  if b0 != _INF_MAGIC_0 {
    return false;
  }
  if b1 != _INF_MAGIC_1 {
    return false;
  }
  if b2 != _INF_MAGIC_2 {
    return false;
  }
  if b3 != _INF_MAGIC_3 {
    return false;
  }
  return true;
}

// Append one Int as eight little-endian two's-complement bytes. Complexity:
// O(1).
fn _inf_push_int(out: &mut Vec[UInt8], v: Int) {
  var s = 0;
  while s < 64 {
    let b: Int = (v >> s) & 255;
    out.push(b as UInt8);
    s = s + 8;
  }
}

// Append a count followed by the vector's values. Complexity: O(n).
fn _inf_push_list(out: &mut Vec[UInt8], v: &Vec[Int]) {
  _inf_push_int(out, v.len());
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    _inf_push_int(out, x);
    i = i + 1;
  }
}

// Decode eight little-endian two's-complement bytes into an Int. The high
// byte is split so no intermediate shift can overflow; ok == 0 marks a
// truncated stream. Complexity: O(1).
fn _inf_read_int(bytes: &Vec[UInt8], pos: Int) -> _InfRead {
  if pos < 0 {
    return _InfRead{ pos: pos; ok: 0; value: 0; };
  }
  if pos + 8 > bytes.len() {
    return _InfRead{ pos: pos; ok: 0; value: 0; };
  }
  var v: Int = 0;
  var i = 0;
  while i < 8 {
    let b: Int = (bytes[pos + i] as Int) & 0xFF;
    if i == 7 {
      let hi: Int = b & 127;
      v = v | (hi << 56);
      if b >= 128 {
        v = v + _inf_int_min();
      }
    } else {
      v = v | (b << (8 * i));
    }
    i = i + 1;
  }
  return _InfRead{ pos: pos + 8; ok: 1; value: v; };
}

// Decode a count and require it to equal `expected`, then append exactly that
// many integers; returns the position past the list or -1. The expected count
// is checked against the parameter cap before any allocation. Complexity:
// O(count).
fn _inf_read_list(bytes: &Vec[UInt8], pos: Int, expected: Int, out: &mut Vec[Int]) -> Int {
  let r = _inf_read_int(bytes, pos);
  let rok: Int = r.ok;
  if rok != 1 {
    return -1;
  }
  let c: Int = r.value;
  if c != expected {
    return -1;
  }
  return _inf_read_i64s(bytes, r.pos, c, out);
}

// Append exactly `count` little-endian integers from `pos`; returns the
// position past the last one, or -1 when the stream is truncated or the count
// is negative / above the parameter cap. Complexity: O(count).
fn _inf_read_i64s(bytes: &Vec[UInt8], pos: Int, count: Int, out: &mut Vec[Int]) -> Int {
  if count < 0 || count > _INF_MAX_PARAMS {
    return -1;
  }
  if pos < 0 || pos > bytes.len() {
    return -1;
  }
  if count > (bytes.len() - pos) / 8 {
    return -1;
  }
  var p = pos;
  var i = 0;
  while i < count {
    let r = _inf_read_int(bytes, p);
    let rok: Int = r.ok;
    if rok != 1 {
      return -1;
    }
    out.push(r.value);
    p = r.pos;
    i = i + 1;
  }
  return p;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_model(v: Model) -> Result[Model, Str] {
  return Ok(v);
}

fn _err_model(msg: Str) -> Result[Model, Str] {
  return Err(msg);
}

fn _ok_str(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

fn _err_str(msg: Str) -> Result[Str, Str] {
  return Err(msg);
}

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

fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

fn _err_bytes(msg: Str) -> Result[Vec[UInt8], Str] {
  return Err(msg);
}
