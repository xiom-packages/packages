// XIOM -- xiom.neural conformance tests (21 checks)
// Port task: prove the pure-XIOM xiom.neural module against its documented
// fixed-point contract (scaled integers only, no floats, no FFI, no I/O in
// the library) with hand-computed fixtures.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module neural_tests
use xiom.io; use xiom.test; use xiom.neural;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every error-message
// and dump check below is routed through streq instead of `==`.

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

fn v8(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  return v;
}

fn full_width() -> Int {
  return 9223372036854775807;
}

fn full_min() -> Int {
  return 0 - 9223372036854775807 - 1;
}

// Hand-computed 2-2-1 fixture (weights 0.5/1.0 row 0, -1.0/0.25 row 1,
// biases 0.5/-0.1, hidden relu, output linear): input (1.0, 2.0) gives 0.7.
fn net221() -> Result[Network, Str] {
  let widths = v3(2, 2, 1);
  let acts = v2(0, 4);
  let weights = v6(5000, 10000, -10000, 2500, 2000, 3000);
  let biases = v3(5000, -1000, 1000);
  return neural_network(&widths, &acts, &weights, &biases);
}

// Identity-ish 2-2-2 fixture for requantization between layers: layer 0 scales
// input 1 by 1.0 and input 2 by 2.0, layer 1 copies both hidden values.
fn net_requant() -> Result[Network, Str] {
  let widths = v3(2, 2, 2);
  let acts = v2(4, 4);
  let weights = v8(10000, 0, 0, 20000, 10000, 0, 0, 10000);
  let biases = v4(0, 0, 0, 0);
  return neural_network(&widths, &acts, &weights, &biases);
}

// Dump of net221(), byte for byte.
fn net221_dump() -> Str {
  return "xiom.neural v1\nlayers 2\nwidths 2 2 1\nacts 0 4\nweights 5000 10000 -10000 2500 2000 3000\nbiases 5000 -1000 1000\nend\n";
}

// ---------------------------------------------------------------------------
// Result extractors with graceful fallbacks: a construction failure makes the
// value checks fail instead of aborting the whole suite.
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

fn net_err(r: Result[Network, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Vector predicate
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = neural_scale() == 10000;
  if neural_act_relu() != 0 { ok = false; }
  if neural_act_leaky() != 1 { ok = false; }
  if neural_act_sigmoid() != 2 { ok = false; }
  if neural_act_tanh() != 3 { ok = false; }
  if neural_act_linear() != 4 { ok = false; }
  return assert(ok, "scale and activation codes are pinned");
}

fn t2() -> TestResult {
  var ok = true;
  let r = net221();
  match r {
    Ok(net) => {
      if neural_n_layers(&net) != 2 { ok = false; }
      if neural_n_inputs(&net) != 2 { ok = false; }
      if neural_n_outputs(&net) != 1 { ok = false; }
      if neural_layer_width(&net, 0) != 2 { ok = false; }
      if neural_layer_width(&net, 1) != 2 { ok = false; }
      if neural_layer_width(&net, 2) != 1 { ok = false; }
      if neural_parameter_count(&net) != 9 { ok = false; }
      if neural_weight_count(&net) != 6 { ok = false; }
      if neural_bias_count(&net) != 3 { ok = false; }
      if neural_layer_weight_count(&net, 0) != 4 { ok = false; }
      if neural_layer_weight_count(&net, 1) != 2 { ok = false; }
      if neural_layer_bias_count(&net, 0) != 2 { ok = false; }
      if neural_layer_bias_count(&net, 1) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "builder reports the 2-2-1 shape and 9 parameters");
}

fn t3() -> TestResult {
  var ok = true;
  let empty = empty_ints();
  let one_w = v1(2);
  let acts0 = v1(0);
  if !net_err(neural_network(&empty, &empty, &empty, &empty), "neural: need at least one layer") { ok = false; }
  if !net_err(neural_network(&one_w, &acts0, &empty, &empty), "neural: need at least one layer") { ok = false; }
  let widths0 = v2(2, 0);
  if !net_err(neural_network(&widths0, &acts0, &empty, &empty), "neural: widths must be positive") { ok = false; }
  let widths2 = v2(2, 2);
  let acts2 = v2(0, 0);
  let acts1 = v1(0);
  if !net_err(neural_network(&widths2, &acts2, &empty, &empty), "neural: activation count does not match layer count") { ok = false; }
  let bad_act = v1(9);
  if !net_err(neural_network(&widths2, &bad_act, &empty, &empty), "neural: unknown activation code") { ok = false; }
  let w1 = v1(1);
  if !net_err(neural_network(&widths2, &acts1, &w1, &empty), "neural: weights length does not match the shape") { ok = false; }
  let w4 = v4(1, 2, 3, 4);
  let b1 = v1(0);
  if !net_err(neural_network(&widths2, &acts1, &w4, &b1), "neural: biases length does not match the shape") { ok = false; }
  let huge = v3(2, full_width(), 2);
  if !net_err(neural_network(&huge, &acts2, &empty, &empty), "neural: dimensions overflow") { ok = false; }
  return assert(ok, "builder validates every shape and guards dimensions");
}

fn t4() -> TestResult {
  var ok = int_of(neural_activation(0, -6000)) == 0;
  if int_of(neural_activation(0, 30000)) != 30000 { ok = false; }
  if int_of(neural_activation(0, 0)) != 0 { ok = false; }
  if !int_err(neural_activation(5, 1), "neural: unknown activation code") { ok = false; }
  if !int_err(neural_activation(-1, 1), "neural: unknown activation code") { ok = false; }
  return assert(ok, "relu clamps negatives and rejects unknown codes");
}

fn t5() -> TestResult {
  var ok = int_of(neural_activation(1, -6000)) == -600;
  if int_of(neural_activation(1, 30000)) != 30000 { ok = false; }
  if int_of(neural_activation(1, 5)) != 5 { ok = false; }
  if int_of(neural_activation(1, -5)) != -1 { ok = false; }
  if int_of(neural_activation(1, -15)) != -2 { ok = false; }
  if int_of(neural_activation(1, 0)) != 0 { ok = false; }
  return assert(ok, "leaky relu divides negatives by 10 with half-away rounding");
}

fn t6() -> TestResult {
  var ok = int_of(neural_activation(2, 0)) == 5000;
  if int_of(neural_activation(2, 10000)) != 7500 { ok = false; }
  if int_of(neural_activation(2, -10000)) != 2500 { ok = false; }
  if int_of(neural_activation(2, 30000)) != 8750 { ok = false; }
  if int_of(neural_activation(2, full_width())) != 10000 { ok = false; }
  if int_of(neural_activation(2, 0 - full_width())) != 0 { ok = false; }
  return assert(ok, "fast sigmoid matches the documented rational values");
}

fn t7() -> TestResult {
  var ok = int_of(neural_activation(3, 0)) == 0;
  if int_of(neural_activation(3, 10000)) != 6668 { ok = false; }
  if int_of(neural_activation(3, -10000)) != -6666 { ok = false; }
  if int_of(neural_activation(3, full_width())) != 10000 { ok = false; }
  if int_of(neural_activation(3, 0 - full_width())) != -10000 { ok = false; }
  return assert(ok, "tanh follows 2*sigmoid(2x)-1 with saturation");
}

fn t8() -> TestResult {
  var ok = int_of(neural_activation(4, -6000)) == -6000;
  if int_of(neural_activation(4, 12345)) != 12345 { ok = false; }
  if int_of(neural_activation(4, 0)) != 0 { ok = false; }
  return assert(ok, "linear activation is the identity");
}

fn t9() -> TestResult {
  var ok = false;
  let input = v2(10000, 20000);
  let r = net221();
  match r {
    Ok(net) => {
      let out = ints_of(neural_forward(&net, &input));
      if out.len() == 1 {
        let y: Int = out[0];
        if y == 7000 { ok = true; }
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "hand-computed 2-2-1 forward pass returns 7000");
}

fn t10() -> TestResult {
  var ok = false;
  let input = v2(10000, 20000);
  let r = net_requant();
  match r {
    Ok(net) => {
      let out = ints_of(neural_forward(&net, &input));
      if out.len() == 2 {
        let a: Int = out[0];
        let b: Int = out[1];
        if a == 10000 && b == 40000 { ok = true; }
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "requantization keeps the 1e-4 scale between layers");
}

fn t11() -> TestResult {
  var ok = false;
  let r = net221();
  match r {
    Ok(net) => {
      if ints_err(neural_forward(&net, &v1(10000)), "neural: input length does not match the input width") {
        ok = true;
      }
    },
    Err(_) => { ok = false; },
  }
  let ow = v2(1, 1);
  let oa = v1(4);
  let big = v1(full_width());
  let zero = v1(0);
  let m1 = neural_network(&ow, &oa, &big, &zero);
  match m1 {
    Ok(net) => {
      if !ints_err(neural_forward(&net, &big), "neural: weight input product overflows") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let w = v1(10000);
  let bias = v1(full_width());
  let m2 = neural_network(&ow, &oa, &w, &bias);
  match m2 {
    Ok(net) => {
      if !ints_err(neural_forward(&net, &w), "neural: bias addition overflows") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "forward validates the input and guards product / bias overflow");
}

fn t12() -> TestResult {
  let a = ints_of(neural_softmax(&v2(0, 0)));
  var ok = a.len() == 2;
  if a.len() == 2 {
    let x: Int = a[0];
    let y: Int = a[1];
    if x != 5000 { ok = false; }
    if y != 5000 { ok = false; }
  }
  let b = ints_of(neural_softmax(&v3(0, 0, 0)));
  if b.len() != 3 { ok = false; }
  if b.len() == 3 {
    let x: Int = b[0];
    let y: Int = b[1];
    let z: Int = b[2];
    if x != 3333 { ok = false; }
    if y != 3333 { ok = false; }
    if z != 3333 { ok = false; }
  }
  let c = ints_of(neural_softmax(&v2(10, 10)));
  if c.len() != 2 { ok = false; }
  if c.len() == 2 {
    let x: Int = c[0];
    let y: Int = c[1];
    if x != 5000 { ok = false; }
    if y != 5000 { ok = false; }
  }
  return assert(ok, "softmax of equal logits is uniform");
}

fn t13() -> TestResult {
  var ok = false;
  let a = ints_of(neural_softmax(&v2(0, 6931)));
  if a.len() == 2 {
    let x: Int = a[0];
    let y: Int = a[1];
    if x == 3333 && y == 6667 { ok = true; }
  }
  var ok2 = false;
  let b = ints_of(neural_softmax(&v2(0, 10000)));
  if b.len() == 2 {
    let x: Int = b[0];
    let y: Int = b[1];
    if x == 2802 && y == 7198 { ok2 = true; }
  }
  return assert(ok && ok2, "softmax matches hand-computed asymmetric rows");
}

fn t14() -> TestResult {
  let empty = empty_ints();
  var ok = ints_err(neural_softmax(&empty), "neural: logits must not be empty");
  let extreme = v2(full_width(), 0 - full_width());
  if !ints_err(neural_softmax(&extreme), "neural: logit shift underflows") { ok = false; }
  let low = v2(full_min(), 0);
  let out = ints_of(neural_softmax(&low));
  if out.len() != 2 { ok = false; }
  if out.len() == 2 {
    let x: Int = out[0];
    let y: Int = out[1];
    if x != 0 { ok = false; }
    if y != 10000 { ok = false; }
  }
  return assert(ok, "softmax rejects empty input and guards the max shift");
}

fn t15() -> TestResult {
  var ok = int_of(neural_argmax(&v3(1, 3, 2))) == 1;
  if int_of(neural_argmax(&v3(5, 5, 1))) != 0 { ok = false; }
  if int_of(neural_argmax(&v3(-2, -2, -3))) != 0 { ok = false; }
  let empty = empty_ints();
  if !int_err(neural_argmax(&empty), "neural: values must not be empty") { ok = false; }
  return assert(ok, "argmax picks the first maximum");
}

fn t16() -> TestResult {
  var ok = false;
  let input = v2(10000, 20000);
  let r = net221();
  match r {
    Ok(net) => {
      if int_of(neural_predict(&net, &input)) == 0 { ok = true; }
    },
    Err(_) => { ok = false; },
  }
  var ok2 = false;
  match r {
    Ok(net) => {
      let probs = ints_of(neural_predict_probs(&net, &input));
      if probs.len() == 1 {
        let p: Int = probs[0];
        if p == 10000 { ok2 = true; }
      }
    },
    Err(_) => { ok2 = false; },
  }
  return assert(ok && ok2, "predict returns the argmax and predict_probs the softmax");
}

fn t17() -> TestResult {
  var ok = false;
  let r = net221();
  match r {
    Ok(net) => {
      let text = str_of(neural_dump(&net));
      if streq(text, net221_dump()) { ok = true; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "dump emits the canonical text byte for byte");
}

fn t18() -> TestResult {
  var ok = false;
  let r = neural_parse(net221_dump());
  match r {
    Ok(net) => {
      let text = str_of(neural_dump(&net));
      let input = v2(10000, 20000);
      let out = ints_of(neural_forward(&net, &input));
      if streq(text, net221_dump()) && neural_parameter_count(&net) == 9 {
        if out.len() == 1 {
          let y: Int = out[0];
          if y == 7000 { ok = true; }
        }
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse + emit round-trips the network and its forward pass");
}

fn t19() -> TestResult {
  var ok = net_err(neural_parse(""), "neural: dump must start with xiom.neural");
  if !net_err(neural_parse("hello"), "neural: dump must start with xiom.neural") { ok = false; }
  if !net_err(neural_parse("xiom.neural v2\nlayers 1\n"), "neural: dump version must be v1") { ok = false; }
  if !net_err(neural_parse("xiom.neural v1\nlayers 0\n"), "neural: layer count must be positive") { ok = false; }
  if !net_err(neural_parse("xiom.neural v1\nlayers 2000\n"), "neural: layer count exceeds the limit") { ok = false; }
  if !net_err(neural_parse("xiom.neural v1\nlayers 1\nwidths 2 abc\n"), "neural: widths list is truncated or malformed") { ok = false; }
  if !net_err(neural_parse("xiom.neural v1\nlayers 1\nwidths 2 9223372036854775807 2\n"), "neural: dimensions overflow") { ok = false; }
  return assert(ok, "parse rejects a bad magic, version, count and widths");
}

fn t20() -> TestResult {
  var ok = net_err(neural_parse("xiom.neural v1\nlayers 1\nwidths 2 2\nacts 9\n"), "neural: unknown activation code");
  if !net_err(neural_parse("xiom.neural v1\nlayers 1\nwidths 2 2\nacts 0\nbiases 0 0\n"), "neural: expected weights") { ok = false; }
  if !net_err(neural_parse("xiom.neural v1\nlayers 1\nwidths 2 2\nacts 4\nweights 10000 0 0 10000\nbiases 0 0\nend\nx"), "neural: unexpected trailing tokens") { ok = false; }
  if !net_err(neural_parse("xiom.neural v1\nlayers 1\nwidths 2 2\nacts 4\nweights 10000 0 0 10000\nbiases 0 0\n"), "neural: expected end") { ok = false; }
  return assert(ok, "parse rejects bad activations, missing lists and trailing tokens");
}

fn t21() -> TestResult {
  var ok = false;
  let r = net221();
  match r {
    Ok(net) => {
      ok = neural_layer_width(&net, -1) == 0;
      if neural_layer_width(&net, 9) != 0 { ok = false; }
      if neural_layer_weight_count(&net, -1) != 0 { ok = false; }
      if neural_layer_weight_count(&net, 9) != 0 { ok = false; }
      if neural_layer_bias_count(&net, -1) != 0 { ok = false; }
      if neural_layer_bias_count(&net, 9) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "per-layer accessors are range-safe");
}

fn main() -> Int {
  io.println("=== xiom.neural conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.neural: all tests passed");
  } else {
    io.println("xiom.neural: tests failed");
  }
  return failed;
}
