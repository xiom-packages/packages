// XIOM -- xiom.deep conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.deep module against its documented
// fixed-point contract (scaled integers only, no floats, no FFI, no I/O in the
// library) with hand-computed fixtures.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module deep_tests
use xiom.io; use xiom.test; use xiom.deep;
use xiom.string.compare;

// All Str equality goes through str_compare (BUG 17: `==` on Str lowers to a
// pointer comparison); every error-message check is routed through streq.
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

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

fn full_width() -> Int {
  return 9223372036854775807;
}

// ---------------------------------------------------------------------------
// Result extractors and predicates
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

fn lstm_of(r: Result[LstmState, Str]) -> LstmState {
  match r {
    Ok(s) => { return s; },
    Err(_) => { return LstmState{ h: empty_ints(); c: empty_ints(); }; },
  }
  return LstmState{ h: empty_ints(); c: empty_ints(); };
}

fn ints_err(r: Result[Vec[Int], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn lstm_err(r: Result[LstmState, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

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

fn vec_eq(a: Vec[Int], b: Vec[Int]) -> Bool {
  return ints_equal(&a, &b);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  return assert(deep_scale() == 10000, "fixed-point scale is 10000 (1e-4)");
}

fn t2() -> TestResult {
  var ok = deep_div_round(5, 2) == 3;
  if deep_div_round(-5, 2) != -3 { ok = false; }
  if deep_div_round(4, 2) != 2 { ok = false; }
  if deep_div_round(1, 2) != 1 { ok = false; }
  if deep_div_round(-1, 2) != -1 { ok = false; }
  if deep_div_round(7, 3) != 2 { ok = false; }
  if deep_div_round(8, 3) != 3 { ok = false; }
  if deep_div_round(9, 3) != 3 { ok = false; }
  return assert(ok, "rounding division is half away from zero");
}

fn t3() -> TestResult {
  var ok = deep_int_sqrt(0) == 0;
  if deep_int_sqrt(1) != 1 { ok = false; }
  if deep_int_sqrt(4) != 2 { ok = false; }
  if deep_int_sqrt(8) != 2 { ok = false; }
  if deep_int_sqrt(9) != 3 { ok = false; }
  if deep_int_sqrt(99) != 9 { ok = false; }
  if deep_int_sqrt(1000000) != 1000 { ok = false; }
  if deep_int_sqrt(full_width()) != 3037000499 { ok = false; }
  return assert(ok, "integer square root floor matches hand values");
}

fn t4() -> TestResult {
  let r = deep_relu(&v3(-5, 0, 7));
  var ok = vec_eq(r, v3(0, 0, 7));
  if !vec_eq(deep_relu(&empty_ints()), empty_ints()) { ok = false; }
  return assert(ok, "relu clamps negatives and tolerates empty input");
}

fn t5() -> TestResult {
  var ok = deep_sigmoid(0) == 5000;
  if deep_sigmoid(10000) != 7500 { ok = false; }
  if deep_sigmoid(-10000) != 2500 { ok = false; }
  if deep_sigmoid(30000) != 8750 { ok = false; }
  if deep_sigmoid(full_width()) != 10000 { ok = false; }
  if deep_sigmoid(0 - full_width()) != 0 { ok = false; }
  return assert(ok, "fast sigmoid matches the documented rational values");
}

fn t6() -> TestResult {
  var ok = deep_tanh(0) == 0;
  if deep_tanh(10000) != 6668 { ok = false; }
  if deep_tanh(-10000) != -6666 { ok = false; }
  if deep_tanh(full_width()) != 10000 { ok = false; }
  if deep_tanh(0 - full_width()) != -10000 { ok = false; }
  return assert(ok, "tanh follows 2*sigmoid(2x)-1 with saturation");
}

fn t7() -> TestResult {
  var ok = vec_eq(ints_of(deep_softmax(&v2(0, 0))), v2(5000, 5000));
  if !vec_eq(ints_of(deep_softmax(&v3(0, 0, 0))), v3(3333, 3333, 3333)) { ok = false; }
  if !vec_eq(ints_of(deep_softmax(&v2(0, 6931))), v2(3333, 6667)) { ok = false; }
  if !ints_err(deep_softmax(&empty_ints()), "deep: logits must not be empty") { ok = false; }
  return assert(ok, "softmax is uniform on equal logits and rejects empty input");
}

fn t8() -> TestResult {
  let s0 = 12345;
  let a1 = deep_lcg_next(s0);
  let b1 = deep_lcg_next(s0);
  var ok = a1 == b1;
  if a1 == s0 { ok = false; }
  let step1 = deep_init_next(s0, 10);
  let step2 = deep_init_next(s0, 10);
  if step1.value != step2.value { ok = false; }
  if step1.state != step2.state { ok = false; }
  if step1.value < 0 || step1.value >= 10 { ok = false; }
  return assert(ok, "LCG is deterministic and stays inside the bound");
}

fn t9() -> TestResult {
  let a = deep_init_uniform(8, -5, 5, 7);
  let b = deep_init_uniform(8, -5, 5, 7);
  let av = deep_init_values(&a);
  let bv = deep_init_values(&b);
  var ok = av.len() == 8;
  if !vec_eq(av, bv) { ok = false; }
  if deep_init_state(&a) != deep_init_state(&b) { ok = false; }
  var i = 0;
  while i < av.len() {
    let x: Int = av[i];
    if x < -5 || x > 5 { ok = false; }
    i = i + 1;
  }
  let e = deep_init_uniform(0, 0, 1, 3);
  if deep_init_values(&e).len() != 0 { ok = false; }
  return assert(ok, "uniform init is reproducible and stays in range");
}

fn t10() -> TestResult {
  let a = deep_init_dense(4, 2, 99);
  let b = deep_init_dense(4, 2, 99);
  let av = deep_init_values(&a);
  var ok = av.len() == 8;
  if !vec_eq(av, deep_init_values(&b)) { ok = false; }
  var i = 0;
  while i < av.len() {
    let x: Int = av[i];
    if x < -10000 || x > 10000 { ok = false; }
    i = i + 1;
  }
  if deep_init_values(&deep_init_dense(0, 2, 1)).len() != 0 { ok = false; }
  if !vec_eq(deep_init_zeros(3), v3(0, 0, 0)) { ok = false; }
  if !vec_eq(deep_init_ones(2), v2(10000, 10000)) { ok = false; }
  return assert(ok, "Xavier init is bounded/reproducible; zeros and ones are exact");
}

fn t11() -> TestResult {
  var ok = false;
  let x = v2(10000, 20000);
  let w = v4(5000, 10000, -10000, 2500);
  let b = v2(1000, 2000);
  let r = deep_linear(&x, &w, &b, 2);
  if vec_eq(ints_of(r), v2(26000, -3000)) { ok = true; }
  if !ints_err(deep_linear(&empty_ints(), &empty_ints(), &empty_ints(), 1), "deep: linear input must not be empty") { ok = false; }
  if !ints_err(deep_linear(&x, &w, &b, 0), "deep: linear output must be positive") { ok = false; }
  if !ints_err(deep_linear(&x, &v1(1), &v2(0, 0), 2), "deep: linear weight length does not match the shape") { ok = false; }
  if !ints_err(deep_linear(&x, &w, &empty_ints(), 2), "deep: linear bias length does not match the output") { ok = false; }
  return assert(ok, "dense layer matches hand math and validates shapes");
}

fn t12() -> TestResult {
  var ok = false;
  let x = v1(10000);
  let w1 = v1(10000);
  let b1 = v1(0);
  let w2 = v1(10000);
  let b2 = v1(0);
  let r = deep_mlp2(&x, &w1, &b1, 1, &w2, &b2, 1);
  if vec_eq(ints_of(r), v1(10000)) { ok = true; }
  if !ints_err(deep_mlp2(&x, &v2(1, 1), &b1, 1, &w2, &b2, 1), "deep: linear weight length does not match the shape") { ok = false; }
  return assert(ok, "two-layer relu MLP forward is exact and shape-checked");
}

fn t13() -> TestResult {
  var ok = vec_eq(ints_of(deep_add(&v2(1, 2), &v2(3, 4))), v2(4, 6));
  if !ints_err(deep_add(&v2(1, 2), &v1(3)), "deep: add length mismatch") { ok = false; }
  return assert(ok, "elementwise add is correct and length-checked");
}

fn t14() -> TestResult {
  var ok = deep_dense_params(3, 4) == 16;
  if deep_conv1d_params(2, 3, 5) != 33 { ok = false; }
  if deep_rnn_params(4, 5) != 50 { ok = false; }
  if deep_lstm_params(4, 5) != 200 { ok = false; }
  if deep_gru_params(4, 5) != 150 { ok = false; }
  if deep_dense_params(0, 4) != 0 { ok = false; }
  return assert(ok, "parameter counts match the documented formulas");
}

fn t15() -> TestResult {
  let x = v2(10000, -3000);
  let z4 = deep_init_zeros(4);
  let z2 = deep_init_zeros(2);
  var ok = vec_eq(ints_of(deep_res_identity(&x, &z4, &z2, 2, &z4, &z2)), v2(10000, 0));
  if !ints_err(deep_res_identity(&v1(1), &z4, &z2, 2, &z4, &z2), "deep: residual identity requires matching width") { ok = false; }
  return assert(ok, "identity-skip residual with zero F is relu(x)");
}

fn t16() -> TestResult {
  let x = v2(10000, -3000);
  let z4 = deep_init_zeros(4);
  let z2 = deep_init_zeros(2);
  let ws = v4(10000, 0, 0, 10000);
  var ok = vec_eq(ints_of(deep_res_projection(&x, &z4, &z2, 2, &z4, &z2, 2, &ws, &z2)), v2(10000, 0));
  let bad = v1(1);
  if !ints_err(deep_res_projection(&x, &bad, &z2, 2, &z4, &z2, 2, &ws, &z2), "deep: linear weight length does not match the shape") { ok = false; }
  return assert(ok, "projection-skip residual applies the 1x1 shortcut");
}

fn t17() -> TestResult {
  let x = v3(10000, 20000, 30000);
  let k = v2(10000, 10000);
  var ok = vec_eq(ints_of(deep_conv1d_valid(&x, &k, 0)), v2(30000, 50000));
  if !vec_eq(ints_of(deep_conv1d_valid(&x, &k, 1000)), v2(31000, 51000)) { ok = false; }
  let kr = v2(0, -10000);
  if !vec_eq(ints_of(deep_conv1d_relu_valid(&v2(10000, 20000), &kr, 0)), v1(0)) { ok = false; }
  if !ints_err(deep_conv1d_valid(&x, &empty_ints(), 0), "deep: conv kernel must not be empty") { ok = false; }
  if !ints_err(deep_conv1d_valid(&v1(1), &k, 0), "deep: conv input shorter than kernel") { ok = false; }
  return assert(ok, "valid 1D convolution and its relu variant match hand math");
}

fn t18() -> TestResult {
  let x = v4(1000, 5000, 2000, 9000);
  var ok = vec_eq(ints_of(deep_max_pool1d(&x, 2, 2)), v2(5000, 9000));
  if !vec_eq(ints_of(deep_max_pool1d(&x, 2, 1)), v3(5000, 5000, 9000)) { ok = false; }
  if !ints_err(deep_max_pool1d(&x, 0, 1), "deep: pool size must be positive") { ok = false; }
  if !ints_err(deep_max_pool1d(&x, 2, 0), "deep: pool stride must be positive") { ok = false; }
  if !ints_err(deep_max_pool1d(&v1(1), 2, 1), "deep: pool input shorter than window") { ok = false; }
  return assert(ok, "max pooling honors window and stride and is range-safe");
}

fn t19() -> TestResult {
  let x = v1(10000);
  let h = v1(10000);
  let wx = v1(5000);
  let wh = v1(10000);
  let b = v1(0);
  var ok = vec_eq(ints_of(deep_rnn_cell(&x, &h, &wx, &wh, &b)), v1(7500));
  if !ints_err(deep_rnn_cell(&x, &h, &v2(1, 1), &wh, &b), "deep: rnn wx length does not match the shape") { ok = false; }
  if !ints_err(deep_rnn_cell(&empty_ints(), &h, &wx, &wh, &b), "deep: rnn input must not be empty") { ok = false; }
  return assert(ok, "vanilla RNN cell matches tanh(Wx x + Wh h)");
}

fn t20() -> TestResult {
  let x = v1(10000);
  let h = v1(0);
  let c = v1(0);
  let w0 = deep_init_zeros(8);
  let b0 = v4(0, 0, 0, 0);
  let s0 = lstm_of(deep_lstm_cell(&x, &h, &c, &w0, &b0, 1));
  var ok = vec_eq(deep_lstm_h(&s0), v1(0));
  if !vec_eq(deep_lstm_c(&s0), v1(0)) { ok = false; }
  let b1 = v4(0, 0, 10000, 0);
  let s1 = lstm_of(deep_lstm_cell(&x, &h, &c, &w0, &b1, 1));
  if !vec_eq(deep_lstm_h(&s1), v1(2000)) { ok = false; }
  if !vec_eq(deep_lstm_c(&s1), v1(3334)) { ok = false; }
  if !lstm_err(deep_lstm_cell(&x, &h, &c, &v1(1), &b0, 1), "deep: lstm weight length does not match the shape") { ok = false; }
  return assert(ok, "LSTM cell zero and tanh-gated cases match hand math");
}

fn t21() -> TestResult {
  let x = v1(0);
  let h = v1(10000);
  let wz = deep_init_zeros(2);
  let wr = deep_init_zeros(2);
  let wh = deep_init_zeros(2);
  let bz = v1(0);
  let br = v1(0);
  let bh = v1(0);
  var ok = vec_eq(ints_of(deep_gru_cell(&x, &h, &wz, &wr, &wh, &bz, &br, &bh, 1)), v1(5000));
  if !ints_err(deep_gru_cell(&x, &h, &v1(1), &wr, &wh, &bz, &br, &bh, 1), "deep: gru wz length does not match the shape") { ok = false; }
  if !ints_err(deep_gru_cell(&empty_ints(), &h, &wz, &wr, &wh, &bz, &br, &bh, 1), "deep: gru input must not be empty") { ok = false; }
  return assert(ok, "GRU cell update with zero gates is h/2 and shape-checked");
}

fn t22() -> TestResult {
  let q = v1(10000);
  let keys = v2(10000, 0);
  var ok = vec_eq(ints_of(deep_attention_scores(&q, &keys, 1)), v2(10000, 0));
  let vals = v1(7000);
  let onekey = v1(10000);
  if !vec_eq(ints_of(deep_attention_head(&q, &onekey, &vals, 1, 1)), v1(7000)) { ok = false; }
  let q2 = v2(1, 2);
  if !ints_err(deep_attention_scores(&q2, &v3(1, 2, 3), 2), "deep: attention key matrix is ragged") { ok = false; }
  if !ints_err(deep_attention_head(&q, &onekey, &vals, 1, 0), "deep: attention value dimension must be positive") { ok = false; }
  return assert(ok, "scaled attention scores and head output match hand math");
}

fn t23() -> TestResult {
  let x = v2(10000, 30000);
  var ok = vec_eq(ints_of(deep_layer_norm(&x)), v2(-10000, 10000));
  if !vec_eq(ints_of(deep_layer_norm(&v2(5000, 5000))), v2(0, 0)) { ok = false; }
  if !ints_err(deep_layer_norm(&empty_ints()), "deep: layer norm input must not be empty") { ok = false; }
  let f = deep_ffn(&v2(10000, 20000), &deep_init_zeros(4), &v2(0, 0), 2, &deep_init_zeros(4), &v2(0, 0), 2);
  if !vec_eq(ints_of(f), v2(0, 0)) { ok = false; }
  return assert(ok, "layer norm normalizes to unit scale and FFN zero weights give zeros");
}

fn t24() -> TestResult {
  var ok = ints_err(deep_linear(&v1(1), &v1(1), &v1(0), 2), "deep: linear weight length does not match the shape");
  if !ints_err(deep_conv1d_valid(&v2(1, 2), &v3(1, 2, 3), 0), "deep: conv input shorter than kernel") { ok = false; }
  if deep_int_sqrt(-5) != 0 { ok = false; }
  if !vec_eq(ints_of(deep_softmax(&v2(0, 6931))), v2(3333, 6667)) { ok = false; }
  return assert(ok, "misc guards: negative sqrt, short conv and softmax are stable");
}

fn main() -> Int {
  io.println("=== xiom.deep conformance tests ===");
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
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.deep: all tests passed");
  } else {
    io.println("xiom.deep: tests failed");
  }
  return failed;
}
