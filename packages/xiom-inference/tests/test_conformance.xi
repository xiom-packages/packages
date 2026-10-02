// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.inference conformance tests (28 checks)
// Port task: prove the pure-XIOM xiom.inference module against its documented
// contract (scaled integers only, parallel-vector descriptor, precomputed
// offsets, batch/stream semantics, per-tensor shift quantization with its
// error bound, and lossless text/binary dumps) with hand-computed fixtures.
//
// All Str equality goes through compare.str_compare: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison (BUG 17), so every
// dump and error-message check is routed through streq. Binary dumps are
// compared byte by byte with the widen+mask idiom, and every model fixture is
// byte-level round-tripped through both codecs.

module inference_tests
use xiom.io; use xiom.test; use xiom.inference;
use xiom.string; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

fn empty_ints() -> Vec[Int] {
  return Vec[Int].new();
}

fn v1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn v2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn v3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn v4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn v6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

fn ub4(a: Int, b: Int, c: Int, d: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  v.push(d as UInt8);
  return v;
}

fn ub5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  v.push(d as UInt8);
  v.push(e as UInt8);
  return v;
}

fn full_width() -> Int {
  return 9223372036854775807;
}

fn full_min() -> Int {
  return 0 - 9223372036854775807 - 1;
}

// Hand-computed 2-2-1 fixture (dense relu -> dense linear): weights
// 0.5/1.0 row 0, -1.0/0.25 row 1, biases 0.5/-0.1, 0.2/0.3 output row,
// output bias 0.1; input (1.0, 2.0) gives 0.7.
fn m221_widths() -> Vec[Int] {
  return v3(2, 2, 1);
}

fn m221_kinds() -> Vec[Int] {
  return v2(0, 0);
}

fn m221_acts() -> Vec[Int] {
  return v2(0, 4);
}

fn m221_weights() -> Vec[Int] {
  return v6(5000, 10000, -10000, 2500, 2000, 3000);
}

fn m221_biases() -> Vec[Int] {
  return v3(5000, -1000, 1000);
}

fn model221() -> Result[Model, Str] {
  return inference_model(&m221_widths(), &m221_kinds(), &m221_acts(), &m221_weights(), &m221_biases());
}

fn m221_text() -> Str {
  return "xiom.inference v1\nlayers 2\nwidths 2 2 1\nkinds 0 0\nacts 0 4\nweights 5000 10000 -10000 2500 2000 3000\nbiases 5000 -1000 1000\nend\n";
}

// Shared offsets of model221: weights 4 + 2, biases 2 + 1.
fn m221_wo() -> Vec[Int] {
  return v3(0, 4, 6);
}

fn m221_bo() -> Vec[Int] {
  return v3(0, 2, 3);
}

// Mixed 2-2-2 fixture: dense identity layer (linear) followed by a standalone
// relu activation layer. Input (-1.0, 0.5) gives (0, 0.5).
fn mixed_model() -> Result[Model, Str] {
  let widths = v3(2, 2, 2);
  let kinds = v2(0, 1);
  let acts = v2(4, 0);
  let weights = v4(10000, 0, 0, 10000);
  let biases = v2(0, 0);
  return inference_model(&widths, &kinds, &acts, &weights, &biases);
}

fn mixed_text() -> Str {
  return "xiom.inference v1\nlayers 2\nwidths 2 2 2\nkinds 0 1\nacts 4 0\nweights 10000 0 0 10000\nbiases 0 0\nend\n";
}

// One dense 2->2 linear layer scaling input 1 by 1.0 and input 2 by 2.0;
// input (1.0, 2.0) gives (1.0, 4.0) after requantization.
fn requant_model() -> Result[Model, Str] {
  let widths = v2(2, 2);
  let kinds = v1(0);
  let acts = v1(4);
  let weights = v4(10000, 0, 0, 20000);
  let biases = v2(0, 0);
  return inference_model(&widths, &kinds, &acts, &weights, &biases);
}

fn product_overflow_model() -> Result[Model, Str] {
  let widths = v2(1, 1);
  let kinds = v1(0);
  let acts = v1(4);
  let weights = v1(full_width());
  let biases = v1(0);
  return inference_model(&widths, &kinds, &acts, &weights, &biases);
}

fn dot_overflow_model() -> Result[Model, Str] {
  let widths = v2(2, 1);
  let kinds = v1(0);
  let acts = v1(4);
  let big = full_width() / 2 + 1;
  let weights = v2(big, big);
  let biases = v1(0);
  return inference_model(&widths, &kinds, &acts, &weights, &biases);
}

fn bias_overflow_model() -> Result[Model, Str] {
  let widths = v2(1, 1);
  let kinds = v1(0);
  let acts = v1(4);
  let weights = v1(10000);
  let biases = v1(full_width());
  return inference_model(&widths, &kinds, &acts, &weights, &biases);
}

// A minimal hand-built valid model (1->1 identity) used as a fallback so a
// fixture construction failure fails value checks instead of aborting.
fn fallback_model() -> Model {
  return Model{ n_layers: 1; n_inputs: 1; n_outputs: 1; widths: v2(1, 1); kinds: v1(0); activations: v1(4); weights: v1(0); biases: v1(0); w_offsets: v2(0, 1); b_offsets: v2(0, 1); };
}

// ---------------------------------------------------------------------------
// Result extractors with graceful fallbacks
// ---------------------------------------------------------------------------

fn ints_of(r: Result[Vec[Int], Str]) -> Vec[Int] {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_ints(); },
  }
  return empty_ints();
}

fn int_of(r: Result[Int, Str]) -> Int {
  match r {
    Ok(x) => { return x; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn str_of(r: Result[Str, Str]) -> Str {
  match r {
    Ok(s) => { return s; },
    Err(_) => { return ""; },
  }
  return "";
}

fn model_of(r: Result[Model, Str]) -> Model {
  match r {
    Ok(m) => { return m; },
    Err(_) => { return fallback_model(); },
  }
  return fallback_model();
}

fn bytes_of(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  match r {
    Ok(b) => { return b; },
    Err(_) => { return Vec[UInt8].new(); },
  }
  return Vec[UInt8].new();
}

// ---------------------------------------------------------------------------
// Error-message predicates
// ---------------------------------------------------------------------------

fn ints_err(r: Result[Vec[Int], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn int_err(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn str_err(r: Result[Str, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn model_err(r: Result[Model, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn bytes_err(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Vector predicates
// ---------------------------------------------------------------------------

fn ints_equal(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn bytes_set(v: &Vec[UInt8], idx: Int, val: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    let b: Int = (v[i] as Int) & 0xFF;
    if i == idx {
      out.push(val as UInt8);
    } else {
      out.push(b as UInt8);
    }
    i = i + 1;
  }
  return out;
}

fn bytes_append(v: &Vec[UInt8], val: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    let b: Int = (v[i] as Int) & 0xFF;
    out.push(b as UInt8);
    i = i + 1;
  }
  out.push(val as UInt8);
  return out;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = inference_scale() == 10000;
  if inference_kind_dense() != 0 { ok = false; }
  if inference_kind_activation() != 1 { ok = false; }
  if inference_act_relu() != 0 { ok = false; }
  if inference_act_leaky() != 1 { ok = false; }
  if inference_act_sigmoid() != 2 { ok = false; }
  if inference_act_tanh() != 3 { ok = false; }
  if inference_act_linear() != 4 { ok = false; }
  return assert(ok, "scale, kind and activation codes are pinned");
}

fn t2() -> TestResult {
  var ok = false;
  let r = model221();
  match r {
    Ok(m) => {
      ok = true;
      if inference_n_layers(&m) != 2 { ok = false; }
      if inference_n_inputs(&m) != 2 { ok = false; }
      if inference_n_outputs(&m) != 1 { ok = false; }
      if inference_layer_width(&m, 0) != 2 { ok = false; }
      if inference_layer_width(&m, 1) != 2 { ok = false; }
      if inference_layer_width(&m, 2) != 1 { ok = false; }
      if inference_layer_kind(&m, 0) != 0 { ok = false; }
      if inference_layer_kind(&m, 1) != 0 { ok = false; }
      if inference_parameter_count(&m) != 9 { ok = false; }
      if inference_weight_count(&m) != 6 { ok = false; }
      if inference_bias_count(&m) != 3 { ok = false; }
      if inference_layer_weight_count(&m, 0) != 4 { ok = false; }
      if inference_layer_weight_count(&m, 1) != 2 { ok = false; }
      if inference_layer_bias_count(&m, 0) != 2 { ok = false; }
      if inference_layer_bias_count(&m, 1) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "builder reports the 2-2-1 shape and 9 parameters");
}

fn t3() -> TestResult {
  let empty = empty_ints();
  var ok = model_err(inference_model(&empty, &empty, &empty, &empty, &empty), "inference: need at least one layer");
  if !model_err(inference_model(&v1(2), &v1(0), &v1(0), &empty, &empty), "inference: need at least one layer") { ok = false; }
  if !model_err(inference_model(&v2(2, 0), &v1(0), &v1(0), &empty, &empty), "inference: widths must be positive") { ok = false; }
  if !model_err(inference_model(&v2(2, 2), &v2(0, 0), &v1(0), &empty, &empty), "inference: kind count does not match layer count") { ok = false; }
  if !model_err(inference_model(&v2(2, 2), &v1(0), &v2(0, 0), &empty, &empty), "inference: activation count does not match layer count") { ok = false; }
  if !model_err(inference_model(&v2(2, 2), &v1(5), &v1(0), &empty, &empty), "inference: unknown layer kind") { ok = false; }
  if !model_err(inference_model(&v2(2, 3), &v1(1), &v1(0), &empty, &empty), "inference: activation layer changes width") { ok = false; }
  if !model_err(inference_model(&v2(2, 2), &v1(0), &v1(9), &empty, &empty), "inference: unknown activation code") { ok = false; }
  let huge = v3(2, full_width(), 2);
  if !model_err(inference_model(&huge, &v2(0, 0), &v2(4, 4), &empty, &empty), "inference: dimensions overflow") { ok = false; }
  return assert(ok, "builder validates kinds, activations, widths and dimensions");
}

fn t4() -> TestResult {
  let empty = empty_ints();
  var ok = model_err(inference_model(&v2(2, 2), &v1(0), &v1(4), &v1(1), &empty), "inference: weights length does not match the shape");
  if !model_err(inference_model(&v2(2, 2), &v1(0), &v1(4), &v4(1, 2, 3, 4), &v1(0)), "inference: biases length does not match the shape") { ok = false; }
  let good = inference_model(&v2(2, 2), &v1(0), &v1(4), &v4(1, 2, 3, 4), &v2(0, 0));
  match good {
    Ok(_) => {},
    Err(_) => { ok = false; },
  }
  return assert(ok, "builder requires the exact weight and bias lengths");
}

fn t5() -> TestResult {
  var ok = false;
  let r = mixed_model();
  match r {
    Ok(m) => {
      ok = true;
      if inference_layer_kind(&m, 0) != 0 { ok = false; }
      if inference_layer_kind(&m, 1) != 1 { ok = false; }
      if inference_layer_weight_count(&m, 1) != 0 { ok = false; }
      if inference_layer_bias_count(&m, 1) != 0 { ok = false; }
      if inference_weight_count(&m) != 4 { ok = false; }
      if inference_bias_count(&m) != 2 { ok = false; }
      let input = v2(-10000, 5000);
      let out = ints_of(inference_forward(&m, &input));
      if out.len() != 2 { ok = false; }
      if out.len() == 2 {
        let a: Int = out[0];
        let b: Int = out[1];
        if a != 0 || b != 5000 { ok = false; }
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "activation layers apply elementwise and carry no weights");
}

fn t6() -> TestResult {
  var ok = false;
  let r = model221();
  match r {
    Ok(m) => {
      let input = v2(10000, 20000);
      let out = ints_of(inference_forward(&m, &input));
      if out.len() == 1 {
        let y: Int = out[0];
        if y == 7000 { ok = true; }
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "hand-computed 2-2-1 forward pass returns 7000");
}

fn t7() -> TestResult {
  var ok = false;
  let r = requant_model();
  match r {
    Ok(m) => {
      let input = v2(10000, 20000);
      let out = ints_of(inference_forward(&m, &input));
      if out.len() == 2 {
        let a: Int = out[0];
        let b: Int = out[1];
        if a == 10000 && b == 40000 { ok = true; }
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "requantization keeps the 1e-4 scale");
}

fn t8() -> TestResult {
  var ok = false;
  let r = model221();
  match r {
    Ok(m) => {
      if ints_err(inference_forward(&m, &v1(10000)), "inference: input length does not match the input width") {
        ok = true;
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "forward validates the input width");
}

fn t9() -> TestResult {
  var ok = true;
  let p = product_overflow_model();
  match p {
    Ok(m) => {
      if !ints_err(inference_forward(&m, &v1(full_width())), "inference: weight input product overflows") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let d = dot_overflow_model();
  match d {
    Ok(m) => {
      if !ints_err(inference_forward(&m, &v2(1, 1)), "inference: dot product overflows") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let b = bias_overflow_model();
  match b {
    Ok(m) => {
      if !ints_err(inference_forward(&m, &v1(10000)), "inference: bias addition overflows") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "forward guards product, dot-sum and bias overflow");
}

fn t10() -> TestResult {
  var ok = int_of(inference_activation(0, -6000)) == 0;
  if int_of(inference_activation(0, 30000)) != 30000 { ok = false; }
  if int_of(inference_activation(0, 0)) != 0 { ok = false; }
  if int_of(inference_activation(1, -6000)) != -600 { ok = false; }
  if int_of(inference_activation(1, 30000)) != 30000 { ok = false; }
  if int_of(inference_activation(1, 5)) != 5 { ok = false; }
  if int_of(inference_activation(1, -5)) != -1 { ok = false; }
  if int_of(inference_activation(1, -15)) != -2 { ok = false; }
  if !int_err(inference_activation(5, 1), "inference: unknown activation code") { ok = false; }
  if !int_err(inference_activation(-1, 1), "inference: unknown activation code") { ok = false; }
  return assert(ok, "relu clamps negatives and leaky relu divides by 10");
}

fn t11() -> TestResult {
  var ok = int_of(inference_activation(2, 0)) == 5000;
  if int_of(inference_activation(2, 10000)) != 7500 { ok = false; }
  if int_of(inference_activation(2, -10000)) != 2500 { ok = false; }
  if int_of(inference_activation(2, 30000)) != 8750 { ok = false; }
  if int_of(inference_activation(2, full_width())) != 10000 { ok = false; }
  if int_of(inference_activation(2, 0 - full_width())) != 0 { ok = false; }
  return assert(ok, "fast sigmoid matches the documented rational values");
}

fn t12() -> TestResult {
  var ok = int_of(inference_activation(3, 0)) == 0;
  if int_of(inference_activation(3, 10000)) != 6668 { ok = false; }
  if int_of(inference_activation(3, -10000)) != -6666 { ok = false; }
  if int_of(inference_activation(3, full_width())) != 10000 { ok = false; }
  if int_of(inference_activation(3, 0 - full_width())) != -10000 { ok = false; }
  if int_of(inference_activation(4, -6000)) != -6000 { ok = false; }
  if int_of(inference_activation(4, 12345)) != 12345 { ok = false; }
  return assert(ok, "tanh follows 2*sigmoid(2x)-1 and linear is the identity");
}

fn t13() -> TestResult {
  var ok = false;
  let a = ints_of(inference_softmax(&v2(0, 0)));
  if a.len() == 2 {
    let x: Int = a[0];
    let y: Int = a[1];
    if x == 5000 && y == 5000 { ok = true; }
  }
  let b = ints_of(inference_softmax(&v3(0, 0, 0)));
  if b.len() == 3 {
    let x: Int = b[0];
    let y: Int = b[1];
    let z: Int = b[2];
    if x != 3333 || y != 3333 || z != 3333 { ok = false; }
  } else {
    ok = false;
  }
  let c = ints_of(inference_softmax(&v2(0, 6931)));
  if c.len() == 2 {
    let x: Int = c[0];
    let y: Int = c[1];
    if x != 3333 || y != 6667 { ok = false; }
  } else {
    ok = false;
  }
  let d = ints_of(inference_softmax(&v2(0, 10000)));
  if d.len() == 2 {
    let x: Int = d[0];
    let y: Int = d[1];
    if x != 2802 || y != 7198 { ok = false; }
  } else {
    ok = false;
  }
  return assert(ok, "softmax is uniform on ties and matches hand-computed rows");
}

fn t14() -> TestResult {
  let empty = empty_ints();
  var ok = ints_err(inference_softmax(&empty), "inference: logits must not be empty");
  let extreme = v2(full_width(), 0 - full_width());
  if !ints_err(inference_softmax(&extreme), "inference: logit shift underflows") { ok = false; }
  let low = v2(full_min(), 0);
  let out = ints_of(inference_softmax(&low));
  if out.len() != 2 { ok = false; }
  if out.len() == 2 {
    let x: Int = out[0];
    let y: Int = out[1];
    if x != 0 || y != 10000 { ok = false; }
  }
  return assert(ok, "softmax rejects empty input and guards the max shift");
}

fn t15() -> TestResult {
  var ok = int_of(inference_argmax(&v3(1, 3, 2))) == 1;
  if int_of(inference_argmax(&v3(5, 5, 1))) != 0 { ok = false; }
  if int_of(inference_argmax(&v3(-2, -2, -3))) != 0 { ok = false; }
  if !int_err(inference_argmax(&empty_ints()), "inference: values must not be empty") { ok = false; }
  return assert(ok, "argmax picks the first maximum and rejects empty input");
}

fn t16() -> TestResult {
  var pred_ok = false;
  var probs_ok = false;
  let r = model221();
  match r {
    Ok(m) => {
      let input = v2(10000, 20000);
      if int_of(inference_predict(&m, &input)) == 0 { pred_ok = true; }
      let probs = ints_of(inference_predict_probs(&m, &input));
      if probs.len() == 1 {
        let p: Int = probs[0];
        if p == 10000 { probs_ok = true; }
      }
    },
    Err(_) => {
      pred_ok = false;
      probs_ok = false;
    },
  }
  return assert(pred_ok && probs_ok, "predict returns the argmax and predict_probs the softmax");
}

fn t17() -> TestResult {
  var ok = false;
  let r = model221();
  match r {
    Ok(m) => {
      if str_eq_expected(inference_export_text(&m), m221_text()) { ok = true; }
    },
    Err(_) => { ok = false; },
  }
  let rm = mixed_model();
  match rm {
    Ok(m) => {
      if !str_eq_expected(inference_export_text(&m), mixed_text()) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "text dump emits both fixture grammars byte for byte");
}

fn str_eq_expected(r: Result[Str, Str], want: Str) -> Bool {
  let got = str_of(r);
  return streq(got, want);
}

fn t18() -> TestResult {
  var ok = false;
  let r = inference_import_text(m221_text());
  match r {
    Ok(m) => {
      if str_eq_expected(inference_export_text(&m), m221_text()) {
        if inference_parameter_count(&m) == 9 {
          let input = v2(10000, 20000);
          let out = ints_of(inference_forward(&m, &input));
          if out.len() == 1 {
            let y: Int = out[0];
            if y == 7000 { ok = true; }
          }
        }
      }
    },
    Err(_) => { ok = false; },
  }
  let rm = inference_import_text(mixed_text());
  match rm {
    Ok(m) => {
      if !str_eq_expected(inference_export_text(&m), mixed_text()) { ok = false; }
      let input = v2(-10000, 5000);
      let out = ints_of(inference_forward(&m, &input));
      if out.len() != 2 { ok = false; }
      if out.len() == 2 {
        let a: Int = out[0];
        let b: Int = out[1];
        if a != 0 || b != 5000 { ok = false; }
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "text import round-trips both fixtures and their forward pass");
}

fn t19() -> TestResult {
  var ok = model_err(inference_import_text(""), "inference: dump must start with xiom.inference");
  if !model_err(inference_import_text("hello"), "inference: dump must start with xiom.inference") { ok = false; }
  if !model_err(inference_import_text("xiom.inference v2\nlayers 1\n"), "inference: dump version must be v1") { ok = false; }
  if !model_err(inference_import_text("xiom.inference v1\nlayers 0\n"), "inference: layer count must be positive") { ok = false; }
  if !model_err(inference_import_text("xiom.inference v1\nlayers 2000\n"), "inference: layer count exceeds the limit") { ok = false; }
  if !model_err(inference_import_text("xiom.inference v1\nlayers 1\nwidths 2 abc\n"), "inference: widths list is truncated or malformed") { ok = false; }
  if !model_err(inference_import_text("xiom.inference v1\nlayers 1\nwidths 2 9223372036854775807\nkinds 0\nacts 4\n"), "inference: dimensions overflow") { ok = false; }
  if !model_err(inference_import_text("xiom.inference v1\nlayers 1\nwidths 2 2\nkinds x\n"), "inference: kind list is truncated or malformed") { ok = false; }
  if !model_err(inference_import_text("xiom.inference v1\nlayers 1\nwidths 2 2\nkinds 7\nacts 0\n"), "inference: unknown layer kind") { ok = false; }
  if !model_err(inference_import_text("xiom.inference v1\nlayers 1\nwidths 2 2\nkinds 0\nacts 9\n"), "inference: unknown activation code") { ok = false; }
  if !model_err(inference_import_text("xiom.inference v1\nlayers 1\nwidths 2 2\nkinds 0\nacts 4\nweights 1 2 3 4\nbiases 0 0\n"), "inference: expected end") { ok = false; }
  if !model_err(inference_import_text(m221_text() + "x"), "inference: unexpected trailing tokens") { ok = false; }
  return assert(ok, "text import rejects bad magic, shapes, tokens and truncation");
}

fn t20() -> TestResult {
  var ok = false;
  let r = model221();
  match r {
    Ok(m) => {
      let inputs = v4(10000, 20000, 20000, 10000);
      let out = ints_of(inference_batch(&m, &inputs));
      if out.len() == 2 {
        let a: Int = out[0];
        let b: Int = out[1];
        if a == 7000 && b == 6000 { ok = true; }
      }
      if !ints_err(inference_batch(&m, &empty_ints()), "inference: batch input length must be a positive multiple of the input width") { ok = false; }
      if !ints_err(inference_batch(&m, &v3(1, 2, 3)), "inference: batch input length must be a positive multiple of the input width") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "batch forwards each row and validates the flat length");
}

fn t21() -> TestResult {
  var ok = false;
  let r = model221();
  match r {
    Ok(m) => {
      let d1 = v3(10000, 20000, 10000);
      let o1 = ints_of(inference_stream(&m, &d1, 2, 1));
      if o1.len() == 2 {
        let a: Int = o1[0];
        let b: Int = o1[1];
        if a == 7000 && b == 6000 { ok = true; }
      }
      let d2 = v4(10000, 20000, 20000, 10000);
      let o2 = ints_of(inference_stream(&m, &d2, 2, 2));
      if o2.len() == 2 {
        let a: Int = o2[0];
        let b: Int = o2[1];
        if a != 7000 || b != 6000 { ok = false; }
      } else {
        ok = false;
      }
      if !ints_err(inference_stream(&m, &d1, 3, 1), "inference: stream window must equal the input width") { ok = false; }
      if !ints_err(inference_stream(&m, &d1, 2, 0), "inference: stream stride must be positive") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  var counts = inference_stream_count(3, 2, 1) == 2;
  if inference_stream_count(1, 2, 1) != 0 { counts = false; }
  if inference_stream_count(0, 0, 0) != 0 { counts = false; }
  if inference_stream_count(5, 2, 2) != 2 { counts = false; }
  return assert(ok && counts, "stream slides by stride and the count is closed-form");
}

fn t22() -> TestResult {
  var ok = false;
  let q = ints_of(inference_quantize(&v4(5000, -5000, 15000, -15001), 1));
  let want_q = v4(2500, -2500, 7500, -7501);
  if ints_equal(&q, &want_q) { ok = true; }
  let d = ints_of(inference_dequantize(&q, 1));
  let want_d = v4(5000, -5000, 15000, -15002);
  if !ints_equal(&d, &want_d) { ok = false; }
  if int_of(inference_quantize_error_bound(0)) != 0 { ok = false; }
  if int_of(inference_quantize_error_bound(1)) != 1 { ok = false; }
  if int_of(inference_quantize_error_bound(2)) != 2 { ok = false; }
  if !int_err(inference_quantize_error_bound(63), "inference: quantization shift out of range") { ok = false; }
  if !ints_err(inference_quantize(&v1(1), -1), "inference: quantization shift out of range") { ok = false; }
  if !ints_err(inference_dequantize(&v1(full_width()), 1), "inference: dequantized value overflows") { ok = false; }
  return assert(ok, "quantize/dequantize round with the documented half-away rounding");
}

fn t23() -> TestResult {
  var ok = false;
  let s = int_of(inference_quantize_shift(&v2(30000, -10), 10000));
  if s == 2 { ok = true; }
  let q = ints_of(inference_quantize(&v2(30000, -10), s));
  let d = ints_of(inference_dequantize(&q, s));
  let bound = int_of(inference_quantize_error_bound(s));
  if d.len() != 2 || bound != 2 { ok = false; }
  if d.len() == 2 {
    let x0: Int = d[0];
    let x1: Int = d[1];
    var e0 = 30000 - x0;
    if e0 < 0 { e0 = 0 - e0; }
    var e1 = -10 - x1;
    if e1 < 0 { e1 = 0 - e1; }
    if e0 > bound || e1 > bound { ok = false; }
  }
  if !int_err(inference_quantize_shift(&v1(1), 0), "inference: quantization max magnitude must be positive") { ok = false; }
  if !int_err(inference_quantize_shift(&v1(full_width()), 1), "inference: no quantization shift in range fits the tensor") { ok = false; }
  return assert(ok, "auto shift picks the finest step and respects the error bound");
}

fn t24() -> TestResult {
  var ok = false;
  let r = model221();
  match r {
    Ok(m) => {
      ok = true;
      if int_of(inference_model_weight_absmax(&m)) != 10000 { ok = false; }
      let qm = model_of(inference_quantize_model(&m, 3));
      let qwv: Vec[Int] = qm.weights;
      let qw = ints_of(inference_dequantize(&qwv, 0));
      if !ints_equal(&qw, &v6(625, 1250, -1250, 313, 250, 375)) { ok = false; }
      let qwv2: Vec[Int] = qm.weights;
      let dw = ints_of(inference_dequantize(&qwv2, 3));
      let orig = v6(5000, 10000, -10000, 2500, 2000, 3000);
      if dw.len() == 6 {
        var i = 0;
        while i < 6 {
          let a: Int = dw[i];
          let b: Int = orig[i];
          var e = a - b;
          if e < 0 { e = 0 - e; }
          if e > 4 { ok = false; }
          i = i + 1;
        }
        let input = v2(10000, 20000);
        let out = ints_of(inference_forward(&qm, &input));
        if out.len() == 1 {
          let y: Int = out[0];
          if y != 1203 { ok = false; }
        } else {
          ok = false;
        }
      } else {
        ok = false;
      }
      if !model_err(inference_quantize_model(&m, 63), "inference: quantization shift out of range") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "model quantization pins weights within the shift error bound");
}

fn t25() -> TestResult {
  var ok = false;
  let r = model221();
  match r {
    Ok(m) => {
      let b1 = bytes_of(inference_export_bin(&m));
      if b1.len() >= 5 {
        let m0: Int = (b1[0] as Int) & 0xFF;
        let m1: Int = (b1[1] as Int) & 0xFF;
        let m2: Int = (b1[2] as Int) & 0xFF;
        let m3: Int = (b1[3] as Int) & 0xFF;
        let ver: Int = (b1[4] as Int) & 0xFF;
        if m0 == 88 && m1 == 73 && m2 == 78 && m3 == 70 && ver == 1 { ok = true; }
      }
      let rm = inference_import_bin(&b1);
      match rm {
        Ok(m2x) => {
          if !str_eq_expected(inference_export_text(&m2x), m221_text()) { ok = false; }
          let b2 = bytes_of(inference_export_bin(&m2x));
          if !bytes_equal(&b1, &b2) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  let rx = mixed_model();
  match rx {
    Ok(m) => {
      let bx = bytes_of(inference_export_bin(&m));
      let rxb = inference_import_bin(&bx);
      match rxb {
        Ok(m2x) => {
          if !str_eq_expected(inference_export_text(&m2x), mixed_text()) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "binary dump round-trips both fixtures byte for byte");
}

fn t26() -> TestResult {
  var ok = bytes_err(inference_import_bin(&ub4(88, 73, 78, 70)), "inference: binary dump is truncated");
  if !bytes_err(inference_import_bin(&ub5(0, 73, 78, 70, 1)), "inference: binary dump must start with XINF") { ok = false; }
  if !bytes_err(inference_import_bin(&ub5(88, 73, 78, 70, 2)), "inference: binary dump version must be v1") { ok = false; }
  if !bytes_err(inference_import_bin(&ub5(88, 73, 78, 70, 1)), "inference: binary dump is truncated") { ok = false; }
  let r = model221();
  match r {
    Ok(m) => {
      let b = bytes_of(inference_export_bin(&m));
      let trailing = bytes_append(&b, 7);
      if !bytes_err(inference_import_bin(&trailing), "inference: binary dump has trailing bytes") { ok = false; }
      let corrupt = bytes_set(&b, 13, 4);
      if !bytes_err(inference_import_bin(&corrupt), "inference: widths list is truncated or malformed") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "binary import rejects truncation, bad magic/version and corruption");
}

fn t27() -> TestResult {
  let bad_off = Model{ n_layers: 2; n_inputs: 2; n_outputs: 1; widths: m221_widths(); kinds: m221_kinds(); activations: m221_acts(); weights: m221_weights(); biases: m221_biases(); w_offsets: v3(0, 0, 0); b_offsets: m221_bo(); };
  let input = v2(10000, 20000);
  var ok = ints_err(inference_forward(&bad_off, &input), "inference: network offsets are inconsistent");
  let bad_kinds = Model{ n_layers: 2; n_inputs: 2; n_outputs: 1; widths: m221_widths(); kinds: v1(0); activations: m221_acts(); weights: m221_weights(); biases: m221_biases(); w_offsets: m221_wo(); b_offsets: m221_bo(); };
  if !ints_err(inference_forward(&bad_kinds, &input), "inference: network kinds are inconsistent") { ok = false; }
  let bad_act = Model{ n_layers: 1; n_inputs: 2; n_outputs: 3; widths: v2(2, 3); kinds: v1(1); activations: v1(0); weights: empty_ints(); biases: empty_ints(); w_offsets: v2(0, 0); b_offsets: v2(0, 0); };
  if !ints_err(inference_forward(&bad_act, &input), "inference: activation layer changes width") { ok = false; }
  return assert(ok, "hand-built descriptors are re-validated on every entry point");
}

fn t28() -> TestResult {
  var ok = false;
  let r = model221();
  match r {
    Ok(m) => {
      ok = inference_layer_width(&m, -1) == 0;
      if inference_layer_width(&m, 9) != 0 { ok = false; }
      if inference_layer_kind(&m, -1) != -1 { ok = false; }
      if inference_layer_kind(&m, 9) != -1 { ok = false; }
      if inference_layer_weight_count(&m, -1) != 0 { ok = false; }
      if inference_layer_weight_count(&m, 9) != 0 { ok = false; }
      if inference_layer_bias_count(&m, -1) != 0 { ok = false; }
      if inference_layer_bias_count(&m, 9) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if inference_stream_count(4, 2, 3) != 1 { ok = false; }
  if inference_stream_count(-1, 2, 1) != 0 { ok = false; }
  return assert(ok, "layer accessors and the stream count are range-safe");
}

fn tally(r: TestResult, failed: Int) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return failed;
  }
  io.println("  [FAIL] " + r.name);
  return failed + 1;
}

fn main() -> Int {
  io.println("=== xiom.inference conformance tests ===");
  var failed: Int = 0;
  failed = tally(t1(), failed);
  failed = tally(t2(), failed);
  failed = tally(t3(), failed);
  failed = tally(t4(), failed);
  failed = tally(t5(), failed);
  failed = tally(t6(), failed);
  failed = tally(t7(), failed);
  failed = tally(t8(), failed);
  failed = tally(t9(), failed);
  failed = tally(t10(), failed);
  failed = tally(t11(), failed);
  failed = tally(t12(), failed);
  failed = tally(t13(), failed);
  failed = tally(t14(), failed);
  failed = tally(t15(), failed);
  failed = tally(t16(), failed);
  failed = tally(t17(), failed);
  failed = tally(t18(), failed);
  failed = tally(t19(), failed);
  failed = tally(t20(), failed);
  failed = tally(t21(), failed);
  failed = tally(t22(), failed);
  failed = tally(t23(), failed);
  failed = tally(t24(), failed);
  failed = tally(t25(), failed);
  failed = tally(t26(), failed);
  failed = tally(t27(), failed);
  failed = tally(t28(), failed);
  if failed == 0 {
    io.println("xiom.inference: all tests passed");
  } else {
    io.println("xiom.inference: tests failed");
  }
  return failed;
}
