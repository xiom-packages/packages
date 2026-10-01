// XIOM -- xiom.neural: deterministic fixed-point MLP inference
// Port task: replace the xiom.neural placeholder with a pure-XIOM module
// (scaled integers only: no floats, no FFI, no I/O, no Vec[Float64], no
// training).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   - fixed point: every weight, bias, activation and probability is an Int
//     in units of 1e-4 (_NN_SCALE = 10000 == 1.0); products are requantized
//     by dividing by the scale with half-away-from-zero rounding;
//   - network: a flat container of layer widths, one activation code per
//     layer, one concatenated row-major weight matrix per layer and one
//     concatenated bias vector per layer (no Vec[StructType]);
//   - forward pass: dense layers with guarded dot products (product and
//     running-sum overflow checks), requantization after each dot product,
//     then the layer bias and activation; the input width and the whole
//     structure are validated before any arithmetic;
//   - activations: relu, leaky relu (slope 1/10), sigmoid and tanh from a
//     documented rational fixed-point approximation, and linear; all local,
//     no stdlib math;
//   - softmax: max-shifted logits, a piecewise-linear exp approximation with
//     breakpoints at multiples of ln 2, exact integer normalization;
//   - argmax prediction: highest value, ties go to the lowest index;
//   - parameter counting: per-layer and total weight / bias counts;
//   - canonical text dump: a one-line-per-record grammar of keywords and
//     decimal integers, with a parser that round-trips it.
//
// Out of scope for v0.1.0: training, backpropagation, convolution, dropout,
// batch norm, weight initialization, persistence formats other than the dump.
//
// v0.62.2 notes that shaped this module:
//   * every Vec[Int] element read binds the element to a typed local before
//     it is used; struct fields are read the same way;
//   * Str values are never compared with `==`; the dump lexer classifies a
//     token byte by byte and compares keywords with string.str_compare where
//     a Str comparison is needed at all;
//   * Ok/Err construction is confined to the leaf helpers at the bottom
//     (_ok_net/_err_net/_ok_str/_err_str/_ok_ints/_err_ints/_ok_int/_err_int);
//   * free functions only: no methods, generics, callbacks, self or indexed
//     function-table dispatch; the network holds parallel Vecs;
//   * Vec parameters are read-only `&Vec[Int]` (or `&mut Vec[Int]` when a
//     helper appends), scalars are threaded through return values;
//   * every loop either advances its index or exits, so parsing an arbitrary
//     text always terminates.

module xiom.neural

use xiom.string;
use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Fixed-point scale: 10000 units = 1.0 (resolution 1e-4).
const _NN_SCALE: Int = 10000;
// Signed 64-bit envelope (Int). The minimum is built by _nn_int_min() because
// the literal -2^63 does not parse (repo-wide convention).
const _NN_INT_MAX: Int = 9223372036854775807;

// Activation kind codes (documented in SPEC.md).
const _NN_ACT_RELU: Int = 0;
const _NN_ACT_LEAKY: Int = 1;
const _NN_ACT_SIGMOID: Int = 2;
const _NN_ACT_TANH: Int = 3;
const _NN_ACT_LINEAR: Int = 4;
const _NN_ACT_MAX: Int = 4;

// Leaky relu slope is exactly 1/10: negative values are divided by this.
const _NN_LEAKY_DIV: Int = 10;

// Piecewise-linear exp breakpoints, negated (all values are <= 0). The
// breakpoints are the integer renderings of -k*ln2 at scale 1e-4:
// ln2 = 0.6931, 2*ln2 = 1.3863, 3*ln2 = 2.0794, 4*ln2 = 2.7726.
const _NN_EXP_1: Int = -6931;
const _NN_EXP_2: Int = -13863;
const _NN_EXP_3: Int = -20794;
const _NN_EXP_4: Int = -27726;

// Dump lexer token kinds.
const _NN_TOK_MAGIC: Int = 1;
const _NN_TOK_VERSION: Int = 2;
const _NN_TOK_LAYERS: Int = 3;
const _NN_TOK_WIDTHS: Int = 4;
const _NN_TOK_ACTS: Int = 5;
const _NN_TOK_WEIGHTS: Int = 6;
const _NN_TOK_BIASES: Int = 7;
const _NN_TOK_END: Int = 8;
const _NN_TOK_INT: Int = 9;
const _NN_TOK_EOF: Int = 10;
const _NN_TOK_BAD: Int = 11;

// Upper bound on the layer count accepted by neural_parse; a parse of a
// hostile "layers 999999999" cannot spin allocating widths.
const _NN_MAX_LAYERS: Int = 1024;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A fully-connected fixed-point network.
///
/// `widths` has `n_layers + 1` positive entries: widths[0] is the input
/// width and widths[k+1] is the output width of layer k. `activations` has
/// one code per layer (`_NN_ACT_*`). `weights` concatenates every layer's
/// row-major matrix (layer k, output j, input i at the running offset plus
/// j * widths[k] + i) and `biases` concatenates every layer's bias vector.
/// All values are in units of 1e-4 (_NN_SCALE).
///
/// Fields are internal implementation detail; build a network with
/// neural_network (or neural_parse) and query it with the neural_* helpers.
pub type Network = {
  n_layers: Int;
  n_inputs: Int;
  n_outputs: Int;
  widths: Vec[Int];
  activations: Vec[Int];
  weights: Vec[Int];
  biases: Vec[Int];
}

// Dump lexer token: position just past the token, its kind and its integer
// value (0 for keywords and EOF). Returned by value so the parser threads the
// scan position through returns, never through a &mut Int.
type _NnTok = {
  pos: Int;
  kind: Int;
  value: Int;
}

// ---------------------------------------------------------------------------
// Scale and activation codes
// ---------------------------------------------------------------------------

/// Fixed-point scale (10000; one unit is 1e-4). Complexity: O(1).
pub fn neural_scale() -> Int {
  return _NN_SCALE;
}

/// Activation code for relu (0). Complexity: O(1).
pub fn neural_act_relu() -> Int {
  return _NN_ACT_RELU;
}

/// Activation code for leaky relu, slope 1/10 (1). Complexity: O(1).
pub fn neural_act_leaky() -> Int {
  return _NN_ACT_LEAKY;
}

/// Activation code for sigmoid (2). Complexity: O(1).
pub fn neural_act_sigmoid() -> Int {
  return _NN_ACT_SIGMOID;
}

/// Activation code for tanh (3). Complexity: O(1).
pub fn neural_act_tanh() -> Int {
  return _NN_ACT_TANH;
}

/// Activation code for linear / identity (4). Complexity: O(1).
pub fn neural_act_linear() -> Int {
  return _NN_ACT_LINEAR;
}

// ---------------------------------------------------------------------------
// Network construction
// ---------------------------------------------------------------------------

/// Build a network from flat, validated parts (all values 1e-4 units).
///
/// Params: widths - positive layer widths, n_layers + 1 entries (>= 2);
///         activations - one code in [0, 4] per layer (n_layers entries);
///         weights - concatenated row-major matrices; exact length is the sum
///         of widths[k] * widths[k+1];
///         biases - concatenated bias vectors; exact length is the sum of
///         widths[k+1].
/// Returns: Ok(Network) with the parts copied in; the caller may keep and
/// reuse its vectors.
/// Validation order: widths count, activation count, widths positivity,
/// activation range, dimensions, weights length, biases length.
/// Error case: Err("neural: ...") for any shape violation or a dimensions
/// overflow.
/// Complexity: O(widths + weights + biases).
pub fn neural_network(widths: &Vec[Int], activations: &Vec[Int], weights: &Vec[Int], biases: &Vec[Int]) -> Result[Network, Str] {
  let nw = widths.len();
  if nw < 2 {
    return _err_net("neural: need at least one layer");
  }
  let n_layers = nw - 1;
  if activations.len() != n_layers {
    return _err_net("neural: activation count does not match layer count");
  }
  var i = 0;
  while i < nw {
    let w: Int = widths[i];
    if w <= 0 {
      return _err_net("neural: widths must be positive");
    }
    i = i + 1;
  }
  i = 0;
  while i < n_layers {
    let a: Int = activations[i];
    if a < 0 || a > _NN_ACT_MAX {
      return _err_net("neural: unknown activation code");
    }
    i = i + 1;
  }
  var w_total: Int = 0;
  var b_total: Int = 0;
  var k = 0;
  while k < n_layers {
    let ni: Int = widths[k];
    let no: Int = widths[k + 1];
    if ni > _NN_INT_MAX / no {
      return _err_net("neural: dimensions overflow");
    }
    let wc = ni * no;
    if wc > _NN_INT_MAX - w_total {
      return _err_net("neural: dimensions overflow");
    }
    w_total = w_total + wc;
    if no > _NN_INT_MAX - b_total {
      return _err_net("neural: dimensions overflow");
    }
    b_total = b_total + no;
    k = k + 1;
  }
  if weights.len() != w_total {
    return _err_net("neural: weights length does not match the shape");
  }
  if biases.len() != b_total {
    return _err_net("neural: biases length does not match the shape");
  }
  let n_inputs: Int = widths[0];
  let n_outputs: Int = widths[n_layers];
  return _ok_net(Network{ n_layers: n_layers; n_inputs: n_inputs; n_outputs: n_outputs; widths: _nn_copy_ints(widths); activations: _nn_copy_ints(activations); weights: _nn_copy_ints(weights); biases: _nn_copy_ints(biases); });
}

/// Number of layers. Complexity: O(1).
pub fn neural_n_layers(net: &Network) -> Int {
  return net.n_layers;
}

/// Input width (widths[0]). Complexity: O(1).
pub fn neural_n_inputs(net: &Network) -> Int {
  return net.n_inputs;
}

/// Output width (widths[n_layers]). Complexity: O(1).
pub fn neural_n_outputs(net: &Network) -> Int {
  return net.n_outputs;
}

/// Width before layer `k` (widths[k]), or 0 when `k` is out of range.
/// Complexity: O(1).
pub fn neural_layer_width(net: &Network, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= net.widths.len() {
    return 0;
  }
  let w: Int = net.widths[k];
  return w;
}

// ---------------------------------------------------------------------------
// Forward pass
// ---------------------------------------------------------------------------

/// Dense forward pass over a fixed-point input vector.
///
/// Params: net - a network built by neural_network / neural_parse;
///         input - net.n_inputs values in 1e-4 units.
/// Returns: Ok(activations) of length net.n_outputs, the last layer's
/// pre-softmax values in 1e-4 units.
/// Layer math: pre[j] = round_half_away(sum_i w[j,i] * x[i] / 10000) + b[j];
/// out[j] = activation(pre[j]). Products and the running dot sum are guarded
/// against Int overflow; the structure and the input width are validated
/// before any arithmetic.
/// Error case: Err("neural: ...") for an inconsistent network, an input
/// length mismatch, a product / dot-sum / bias-add overflow.
/// Complexity: O(sum of layer weight counts).
pub fn neural_forward(net: &Network, input: &Vec[Int]) -> Result[Vec[Int], Str] {
  let v = _nn_validate(net);
  match v {
    Ok(_) => {},
    Err(e) => { return _err_ints(e); },
  }
  let n_in0: Int = net.widths[0];
  if input.len() != n_in0 {
    return _err_ints("neural: input length does not match the input width");
  }
  var cur = Vec[Int].new();
  var i = 0;
  while i < input.len() {
    let x: Int = input[i];
    cur.push(x);
    i = i + 1;
  }
  var w_off: Int = 0;
  var b_off: Int = 0;
  var k = 0;
  while k < net.n_layers {
    let ni: Int = net.widths[k];
    let no: Int = net.widths[k + 1];
    let act: Int = net.activations[k];
    var next = Vec[Int].new();
    var j = 0;
    while j < no {
      var s: Int = 0;
      var ii = 0;
      while ii < ni {
        let w: Int = net.weights[w_off + j * ni + ii];
        let x: Int = cur[ii];
        if _nn_mul_overflows(w, x) {
          return _err_ints("neural: weight input product overflows");
        }
        let term = w * x;
        if term > 0 {
          if s > _NN_INT_MAX - term {
            return _err_ints("neural: dot product overflows");
          }
        } elif term < 0 {
          if s < _nn_int_min() - term {
            return _err_ints("neural: dot product overflows");
          }
        }
        s = s + term;
        ii = ii + 1;
      }
      let pre = _nn_div_round(s, _NN_SCALE);
      let b: Int = net.biases[b_off + j];
      if _nn_add_overflows(pre, b) {
        return _err_ints("neural: bias addition overflows");
      }
      let z = pre + b;
      next.push(_nn_activate(act, z));
      j = j + 1;
    }
    w_off = w_off + ni * no;
    b_off = b_off + no;
    cur = next;
    k = k + 1;
  }
  return _ok_ints(cur);
}

/// Apply one activation to a fixed-point value.
///
/// Params: kind - one of the neural_act_* codes; x - a 1e-4 unit value.
/// Returns: Ok(y) where relu is max(0, x); leaky relu is x for x >= 0 and
/// round_half_away(x / 10) otherwise; sigmoid and tanh use the documented
/// fixed-point rational approximations (SPEC.md section 4); linear is x.
/// Error case: Err("neural: unknown activation code") outside [0, 4].
/// Complexity: O(1).
pub fn neural_activation(kind: Int, x: Int) -> Result[Int, Str] {
  if kind < 0 || kind > _NN_ACT_MAX {
    return _err_int("neural: unknown activation code");
  }
  return _ok_int(_nn_activate(kind, x));
}

// ---------------------------------------------------------------------------
// Softmax and prediction
// ---------------------------------------------------------------------------

/// Softmax over fixed-point logits (the output-layer variant).
///
/// Params: logits - one 1e-4 unit value per class; must not be empty.
/// Returns: Ok(probs) of the same length; every entry is in [0, 10000]. The
/// maximum logit is subtracted first (shifted values are <= 0); each shifted
/// value goes through the piecewise-linear exp approximation (_nn_exp) and
/// the exponentials are normalized with round_half_away(e_i * 10000 / sum).
/// The entries sum to 10000 up to per-entry rounding (documented in SPEC.md).
/// Error case: Err("neural: ...") for an empty input, a shift underflow, a
/// sum or product overflow.
/// Complexity: O(n).
pub fn neural_softmax(logits: &Vec[Int]) -> Result[Vec[Int], Str] {
  let n = logits.len();
  if n <= 0 {
    return _err_ints("neural: logits must not be empty");
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
    if maxv > 0 && x < _nn_int_min() + maxv {
      return _err_ints("neural: logit shift underflows");
    }
    let shifted = x - maxv;
    let e = _nn_exp(shifted);
    if e > _NN_INT_MAX - total {
      return _err_ints("neural: softmax sum overflows");
    }
    total = total + e;
    exps.push(e);
    i = i + 1;
  }
  if total <= 0 {
    return _err_ints("neural: softmax sum must be positive");
  }
  var out = Vec[Int].new();
  i = 0;
  while i < n {
    let e: Int = exps[i];
    if e > 0 {
      if e > _NN_INT_MAX / _NN_SCALE {
        return _err_ints("neural: softmax product overflows");
      }
    }
    let num = e * _NN_SCALE;
    out.push(_nn_div_round(num, total));
    i = i + 1;
  }
  return _ok_ints(out);
}

/// Index of the highest value; ties go to the lowest index.
///
/// Params: values - any non-empty Int vector.
/// Returns: Ok(index) of the first occurrence of the maximum.
/// Error case: Err("neural: values must not be empty").
/// Complexity: O(n).
pub fn neural_argmax(values: &Vec[Int]) -> Result[Int, Str] {
  let n = values.len();
  if n <= 0 {
    return _err_int("neural: values must not be empty");
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
/// output value. Params: net, input as in neural_forward. Returns:
/// Ok(class) with ties going to the lowest output index. Error case: the
/// neural_forward errors plus the empty-output argmax error. Complexity:
/// O(forward).
pub fn neural_predict(net: &Network, input: &Vec[Int]) -> Result[Int, Str] {
  let out = neural_forward(net, input);
  match out {
    Ok(v) => { return neural_argmax(&v); },
    Err(e) => { return _err_int(e); },
  }
  return _err_int("neural: prediction failed");
}

/// Softmax probabilities over a forward pass. Params: net, input as in
/// neural_forward. Returns: Ok(probs) of length net.n_outputs, as in
/// neural_softmax. Error case: the neural_forward and neural_softmax errors.
/// Complexity: O(forward).
pub fn neural_predict_probs(net: &Network, input: &Vec[Int]) -> Result[Vec[Int], Str] {
  let out = neural_forward(net, input);
  match out {
    Ok(v) => { return neural_softmax(&v); },
    Err(e) => { return _err_ints(e); },
  }
  return _err_ints("neural: prediction failed");
}

// ---------------------------------------------------------------------------
// Parameter counting
// ---------------------------------------------------------------------------

/// Total parameter count: weights + biases. Complexity: O(1).
pub fn neural_parameter_count(net: &Network) -> Int {
  return net.weights.len() + net.biases.len();
}

/// Total weight count. Complexity: O(1).
pub fn neural_weight_count(net: &Network) -> Int {
  return net.weights.len();
}

/// Total bias count. Complexity: O(1).
pub fn neural_bias_count(net: &Network) -> Int {
  return net.biases.len();
}

/// Weight count of layer `k` (widths[k] * widths[k+1]), or 0 when `k` is out
/// of range. Complexity: O(1).
pub fn neural_layer_weight_count(net: &Network, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= net.n_layers {
    return 0;
  }
  let ni: Int = net.widths[k];
  let no: Int = net.widths[k + 1];
  return ni * no;
}

/// Bias count of layer `k` (widths[k+1]), or 0 when `k` is out of range.
/// Complexity: O(1).
pub fn neural_layer_bias_count(net: &Network, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= net.n_layers {
    return 0;
  }
  let no: Int = net.widths[k + 1];
  return no;
}

// ---------------------------------------------------------------------------
// Canonical dump
// ---------------------------------------------------------------------------

/// Render the network as deterministic text (the canonical dump).
///
/// Grammar (one record per `\n`-terminated line, tokens separated by ASCII
/// whitespace; all numbers are decimal integers in [-Int_max, Int_max]):
///
///   xiom.neural v1
///   layers <n>
///   widths <w0> ... <wn>
///   acts <a0> ... <a_{n-1}>
///   weights <...>          exact n_layers matrices in row-major order
///   biases <...>           exact n_layers bias vectors in order
///   end
///
/// Returns: Ok(text). The output is stable, so neural_dump(parse(dump)) is
/// the same string; neural_parse accepts exactly this grammar.
/// Error case: Err("neural: ...") when the network structure is invalid.
/// Complexity: O(parameters) plus string assembly.
pub fn neural_dump(net: &Network) -> Result[Str, Str] {
  let v = _nn_validate(net);
  match v {
    Ok(_) => {},
    Err(e) => { return _err_str(e); },
  }
  var out = "xiom.neural v1\nlayers " + convert.int_to_string(net.n_layers) + "\nwidths";
  var i = 0;
  while i < net.widths.len() {
    let w: Int = net.widths[i];
    out = out + " " + convert.int_to_string(w);
    i = i + 1;
  }
  out = out + "\nacts";
  i = 0;
  while i < net.activations.len() {
    let a: Int = net.activations[i];
    out = out + " " + convert.int_to_string(a);
    i = i + 1;
  }
  out = out + "\nweights";
  i = 0;
  while i < net.weights.len() {
    let w: Int = net.weights[i];
    out = out + " " + convert.int_to_string(w);
    i = i + 1;
  }
  out = out + "\nbiases";
  i = 0;
  while i < net.biases.len() {
    let b: Int = net.biases[i];
    out = out + " " + convert.int_to_string(b);
    i = i + 1;
  }
  out = out + "\nend\n";
  return _ok_str(out);
}

/// Parse the canonical dump back into a network.
///
/// Params: text - the neural_dump grammar above, with any ASCII whitespace
/// between tokens.
/// Returns: Ok(Network) equivalent to the dumped network; the parser
/// validates the shape exactly like neural_network.
/// Error case: Err("neural: ...") for a wrong magic or version, a
/// non-positive or oversized layer count, a missing or malformed list, a
/// non-positive width, an unknown activation code, a shape overflow, or
/// trailing tokens after `end`.
/// Complexity: O(tokens) with every scan step advancing.
pub fn neural_parse(text: Str) -> Result[Network, Str] {
  var p = _nn_expect(text, 0, _NN_TOK_MAGIC);
  if p < 0 {
    return _err_net("neural: dump must start with xiom.neural");
  }
  p = _nn_expect(text, p, _NN_TOK_VERSION);
  if p < 0 {
    return _err_net("neural: dump version must be v1");
  }
  p = _nn_expect(text, p, _NN_TOK_LAYERS);
  if p < 0 {
    return _err_net("neural: expected layers");
  }
  let tl = _nn_lex(text, p);
  let tk: Int = tl.kind;
  if tk != _NN_TOK_INT {
    return _err_net("neural: layer count must be an integer");
  }
  let n: Int = tl.value;
  if n <= 0 {
    return _err_net("neural: layer count must be positive");
  }
  if n > _NN_MAX_LAYERS {
    return _err_net("neural: layer count exceeds the limit");
  }
  p = tl.pos;
  p = _nn_expect(text, p, _NN_TOK_WIDTHS);
  if p < 0 {
    return _err_net("neural: expected widths");
  }
  var widths = Vec[Int].new();
  p = _nn_read_ints(text, p, n + 1, &mut widths);
  if p < 0 {
    return _err_net("neural: widths list is truncated or malformed");
  }
  var i = 0;
  while i < widths.len() {
    let w: Int = widths[i];
    if w <= 0 {
      return _err_net("neural: widths must be positive");
    }
    i = i + 1;
  }
  var w_total: Int = 0;
  var b_total: Int = 0;
  var k = 0;
  while k < n {
    let wi: Int = widths[k];
    let wo: Int = widths[k + 1];
    if wi > _NN_INT_MAX / wo {
      return _err_net("neural: dimensions overflow");
    }
    let wc = wi * wo;
    if wc > _NN_INT_MAX - w_total {
      return _err_net("neural: dimensions overflow");
    }
    w_total = w_total + wc;
    if wo > _NN_INT_MAX - b_total {
      return _err_net("neural: dimensions overflow");
    }
    b_total = b_total + wo;
    k = k + 1;
  }
  p = _nn_expect(text, p, _NN_TOK_ACTS);
  if p < 0 {
    return _err_net("neural: expected acts");
  }
  var acts = Vec[Int].new();
  p = _nn_read_ints(text, p, n, &mut acts);
  if p < 0 {
    return _err_net("neural: activation list is truncated or malformed");
  }
  i = 0;
  while i < n {
    let a: Int = acts[i];
    if a < 0 || a > _NN_ACT_MAX {
      return _err_net("neural: unknown activation code");
    }
    i = i + 1;
  }
  p = _nn_expect(text, p, _NN_TOK_WEIGHTS);
  if p < 0 {
    return _err_net("neural: expected weights");
  }
  var weights = Vec[Int].new();
  p = _nn_read_ints(text, p, w_total, &mut weights);
  if p < 0 {
    return _err_net("neural: weights list is truncated or malformed");
  }
  p = _nn_expect(text, p, _NN_TOK_BIASES);
  if p < 0 {
    return _err_net("neural: expected biases");
  }
  var biases = Vec[Int].new();
  p = _nn_read_ints(text, p, b_total, &mut biases);
  if p < 0 {
    return _err_net("neural: biases list is truncated or malformed");
  }
  p = _nn_expect(text, p, _NN_TOK_END);
  if p < 0 {
    return _err_net("neural: expected end");
  }
  let te = _nn_lex(text, p);
  let ek: Int = te.kind;
  if ek != _NN_TOK_EOF {
    return _err_net("neural: unexpected trailing tokens");
  }
  return neural_network(&widths, &acts, &weights, &biases);
}

// ---------------------------------------------------------------------------
// Private helpers: fixed-point arithmetic
// ---------------------------------------------------------------------------

// Int minimum (-2^63), expressed as an expression because the literal does
// not parse (repo-wide convention: 0 - Int_max - 1). Complexity: O(1).
fn _nn_int_min() -> Int {
  return 0 - _NN_INT_MAX - 1;
}

// True when a * b would leave the signed Int range. All four sign cases are
// handled with truncating division, which is exact for this test. Complexity:
// O(1).
fn _nn_mul_overflows(a: Int, b: Int) -> Bool {
  if a == 0 || b == 0 {
    return false;
  }
  if a > 0 {
    if b > 0 {
      return a > _NN_INT_MAX / b;
    }
    return b < _nn_int_min() / a;
  }
  if b > 0 {
    return a < _nn_int_min() / b;
  }
  return a < _NN_INT_MAX / b;
}

// True when a + b would leave the signed Int range. Complexity: O(1).
fn _nn_add_overflows(a: Int, b: Int) -> Bool {
  if b > 0 {
    return a > _NN_INT_MAX - b;
  }
  if b < 0 {
    return a < _nn_int_min() - b;
  }
  return false;
}

// Truncating division with halves rounded away from zero (b > 0). The
// doubled magnitude is guarded, so no denominator can overflow it. Used for
// every division in the module. Complexity: O(1).
fn _nn_div_round(a: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  var mag = r;
  if mag < 0 {
    mag = 0 - mag;
  }
  var round_away = false;
  if mag > _NN_INT_MAX / 2 {
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
fn _nn_activate(kind: Int, x: Int) -> Int {
  if kind == _NN_ACT_RELU {
    if x < 0 {
      return 0;
    }
    return x;
  }
  if kind == _NN_ACT_LEAKY {
    if x >= 0 {
      return x;
    }
    return _nn_div_round(x, _NN_LEAKY_DIV);
  }
  if kind == _NN_ACT_SIGMOID {
    return _nn_sigmoid(x);
  }
  if kind == _NN_ACT_TANH {
    return _nn_tanh(x);
  }
  return x;
}

// Fast sigmoid: s(x) = 1/2 + (x / (1 + |x|)) / 2, evaluated in 1e-4 units:
// t = round(x * 10000 / (10000 + |x|)), s = round((10000 + t) / 2). The
// result is in [0, 10000], s(0) = 5000 and s is odd in the sense
// s(-x) = 10000 - s(x). Very large |x| saturates to 0 / 10000 when the
// x * 10000 product would overflow. Complexity: O(1).
fn _nn_sigmoid(x: Int) -> Int {
  if x == 0 {
    return _NN_SCALE / 2;
  }
  if x > 0 {
    if x > _NN_INT_MAX / _NN_SCALE {
      return _NN_SCALE;
    }
    let t = _nn_div_round(x * _NN_SCALE, _NN_SCALE + x);
    return _nn_div_round(_NN_SCALE + t, 2);
  }
  let ax = 0 - x;
  if ax > _NN_INT_MAX / _NN_SCALE {
    return 0;
  }
  let t = _nn_div_round(x * _NN_SCALE, _NN_SCALE + ax);
  return _nn_div_round(_NN_SCALE + t, 2);
}

// Tanh from the sigmoid above: tanh(x) = 2 * s(2x) - 1. 2x saturates to
// +10000 / -10000 for |x| beyond half the Int range. Complexity: O(1).
fn _nn_tanh(x: Int) -> Int {
  if x == 0 {
    return 0;
  }
  if x > 0 {
    if x > _NN_INT_MAX / 2 {
      return _NN_SCALE;
    }
    let s = _nn_sigmoid(x * 2);
    return 2 * s - _NN_SCALE;
  }
  if x < _nn_int_min() / 2 {
    return 0 - _NN_SCALE;
  }
  let s = _nn_sigmoid(x * 2);
  return 2 * s - _NN_SCALE;
}

// Piecewise-linear exp approximation for x <= 0, in 1e-4 units: exp(x) is
// interpolated between the breakpoints (0, 10000), (-6931, 5000),
// (-13863, 2500), (-20794, 1250), (-27726, 625); below -27726 the result is 0
// (truncation, documented). Every segment interpolates with
// round_half_away(dx * drop / 6931), so the values are hand-computable and
// monotone. Complexity: O(1).
fn _nn_exp(x: Int) -> Int {
  if x >= 0 {
    return _NN_SCALE;
  }
  if x >= _NN_EXP_1 {
    let dx = 0 - x;
    return _NN_SCALE - _nn_div_round(dx * 5000, 6931);
  }
  if x >= _NN_EXP_2 {
    let dx = (0 - x) + _NN_EXP_1;
    return 5000 - _nn_div_round(dx * 2500, 6931);
  }
  if x >= _NN_EXP_3 {
    let dx = (0 - x) + _NN_EXP_2;
    return 2500 - _nn_div_round(dx * 1250, 6931);
  }
  if x >= _NN_EXP_4 {
    let dx = (0 - x) + _NN_EXP_3;
    return 1250 - _nn_div_round(dx * 625, 6931);
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Private helpers: network structure
// ---------------------------------------------------------------------------

// Validate a Network value field by field (the public fields of a pub type
// can be assembled by hand, so every public entry point re-checks). Returns
// Ok(0) for a valid network, Err(message) for the first violation.
// Complexity: O(layers + widths).
fn _nn_validate(net: &Network) -> Result[Int, Str] {
  let n_layers = net.n_layers;
  if n_layers <= 0 {
    return _err_int("neural: need at least one layer");
  }
  if net.widths.len() != n_layers + 1 {
    return _err_int("neural: network widths are inconsistent");
  }
  if net.activations.len() != n_layers {
    return _err_int("neural: network activations are inconsistent");
  }
  var i = 0;
  while i < net.widths.len() {
    let w: Int = net.widths[i];
    if w <= 0 {
      return _err_int("neural: widths must be positive");
    }
    i = i + 1;
  }
  i = 0;
  while i < n_layers {
    let a: Int = net.activations[i];
    if a < 0 || a > _NN_ACT_MAX {
      return _err_int("neural: unknown activation code");
    }
    i = i + 1;
  }
  var w_total: Int = 0;
  var b_total: Int = 0;
  var k = 0;
  while k < n_layers {
    let wi: Int = net.widths[k];
    let wo: Int = net.widths[k + 1];
    if wi > _NN_INT_MAX / wo {
      return _err_int("neural: dimensions overflow");
    }
    let wc = wi * wo;
    if wc > _NN_INT_MAX - w_total {
      return _err_int("neural: dimensions overflow");
    }
    w_total = w_total + wc;
    if wo > _NN_INT_MAX - b_total {
      return _err_int("neural: dimensions overflow");
    }
    b_total = b_total + wo;
    k = k + 1;
  }
  if net.weights.len() != w_total {
    return _err_int("neural: network weights are inconsistent");
  }
  if net.biases.len() != b_total {
    return _err_int("neural: network biases are inconsistent");
  }
  return _ok_int(0);
}

// Copy an Int vector (network parts are owned by the network, so the caller
// keeps its input vectors). Complexity: O(n).
fn _nn_copy_ints(v: &Vec[Int]) -> Vec[Int] {
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
// Private helpers: dump lexer and parser
// ---------------------------------------------------------------------------

// ASCII whitespace: space, LF, CR, tab. Complexity: O(1).
fn _nn_is_ws(b: Int) -> Bool {
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

// True when the token text[start, end) equals the ASCII of `kw`. Compares
// byte by byte; no Str equality is used. Complexity: O(|kw|).
fn _nn_match_kw(text: Str, start: Int, end: Int, kw: Str) -> Bool {
  if end - start != kw.len() {
    return false;
  }
  var i = 0;
  while i < kw.len() {
    let tb: Int = string.byte_at(text, start + i) as Int;
    let kb: Int = string.byte_at(kw, i) as Int;
    if tb != kb {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Lex one token starting at `pos`: skip ASCII whitespace, then classify the
// [start, end) run. Keywords get their _NN_TOK_* kind; a signed decimal run
// (optional '-', at least one digit, magnitude <= Int_max) gets
// _NN_TOK_INT with the value; end of text gets _NN_TOK_EOF; anything else
// gets _NN_TOK_BAD. Every scan step advances or exits. Complexity: O(token).
fn _nn_lex(text: Str, pos: Int) -> _NnTok {
  let n = text.len();
  var p = pos;
  var scanning = true;
  while scanning {
    if p >= n {
      scanning = false;
    } else {
      let b: Int = string.byte_at(text, p) as Int;
      if _nn_is_ws(b) {
        p = p + 1;
      } else {
        scanning = false;
      }
    }
  }
  if p >= n {
    return _NnTok{ pos: p; kind: _NN_TOK_EOF; value: 0; };
  }
  var e = p;
  var scanning2 = true;
  while scanning2 {
    if e >= n {
      scanning2 = false;
    } else {
      let b: Int = string.byte_at(text, e) as Int;
      if _nn_is_ws(b) {
        scanning2 = false;
      } else {
        e = e + 1;
      }
    }
  }
  if _nn_match_kw(text, p, e, "xiom.neural") {
    return _NnTok{ pos: e; kind: _NN_TOK_MAGIC; value: 0; };
  }
  if _nn_match_kw(text, p, e, "v1") {
    return _NnTok{ pos: e; kind: _NN_TOK_VERSION; value: 0; };
  }
  if _nn_match_kw(text, p, e, "layers") {
    return _NnTok{ pos: e; kind: _NN_TOK_LAYERS; value: 0; };
  }
  if _nn_match_kw(text, p, e, "widths") {
    return _NnTok{ pos: e; kind: _NN_TOK_WIDTHS; value: 0; };
  }
  if _nn_match_kw(text, p, e, "acts") {
    return _NnTok{ pos: e; kind: _NN_TOK_ACTS; value: 0; };
  }
  if _nn_match_kw(text, p, e, "weights") {
    return _NnTok{ pos: e; kind: _NN_TOK_WEIGHTS; value: 0; };
  }
  if _nn_match_kw(text, p, e, "biases") {
    return _NnTok{ pos: e; kind: _NN_TOK_BIASES; value: 0; };
  }
  if _nn_match_kw(text, p, e, "end") {
    return _NnTok{ pos: e; kind: _NN_TOK_END; value: 0; };
  }
  let b0: Int = string.byte_at(text, p) as Int;
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
      let d: Int = (string.byte_at(text, i) as Int) - 48;
      if d < 0 || d > 9 {
        good = false;
      } elif v > (_NN_INT_MAX - d) / 10 {
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
      return _NnTok{ pos: e; kind: _NN_TOK_INT; value: v; };
    }
    return _NnTok{ pos: e; kind: _NN_TOK_BAD; value: 0; };
  }
  return _NnTok{ pos: e; kind: _NN_TOK_BAD; value: 0; };
}

// Lex the next token and require the given kind; returns the position past it
// or -1 on mismatch. Complexity: O(token).
fn _nn_expect(text: Str, pos: Int, kind: Int) -> Int {
  let t = _nn_lex(text, pos);
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
fn _nn_read_ints(text: Str, pos: Int, count: Int, out: &mut Vec[Int]) -> Int {
  var p = pos;
  var i = 0;
  while i < count {
    let t = _nn_lex(text, p);
    let tk: Int = t.kind;
    if tk != _NN_TOK_INT {
      return -1;
    }
    out.push(t.value);
    p = t.pos;
    i = i + 1;
  }
  return p;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_net(v: Network) -> Result[Network, Str] {
  return Ok(v);
}

fn _err_net(msg: Str) -> Result[Network, Str] {
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
