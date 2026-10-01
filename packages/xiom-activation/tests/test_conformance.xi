// XIOM -- xiom.activation conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.activation module against its
// documented fixed-point contract (no floats, no FFI, no I/O in the library).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare, and every Vec[Int] element read
// binds a typed local first. Test functions are called directly from main:
// indexed function-table dispatch is avoided.

module activation_tests
use xiom.io; use xiom.test; use xiom.activation;
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

fn v5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

// ---------------------------------------------------------------------------
// Result / vector predicates
// ---------------------------------------------------------------------------

fn ints_of(r: Result[Vec[Int], Str]) -> Vec[Int] {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_ints(); },
  }
  return empty_ints();
}

fn ints_err(r: Result[Vec[Int], Str], want: Str) -> Bool {
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

fn ints_in_range(v: &Vec[Int], lo: Int, hi: Int) -> Bool {
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    if x < lo {
      return false;
    }
    if x > hi {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn ints_sum(v: &Vec[Int]) -> Int {
  var total: Int = 0;
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    total = total + x;
    i = i + 1;
  }
  return total;
}

fn abs_int(x: Int) -> Int {
  if x < 0 {
    return 0 - x;
  }
  return x;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = activation_scale() == 10000;
  if activation_saturation() != 10000 { ok = false; }
  if activation_x_limit() != 1000000000 { ok = false; }
  if activation_exp_floor() != -150000 { ok = false; }
  if activation_exp_steps() != 10 { ok = false; }
  if activation_softmax_x_limit() != 1000000 { ok = false; }
  return assert(ok, "constants and accessors match the documented scale");
}

fn t2() -> TestResult {
  var ok = activation_relu(-5000) == 0;
  if activation_relu(-1) != 0 { ok = false; }
  if activation_relu(0) != 0 { ok = false; }
  if activation_relu(1) != 1 { ok = false; }
  if activation_relu(3000) != 3000 { ok = false; }
  if activation_relu(9999) != 9999 { ok = false; }
  if activation_relu(10000) != 10000 { ok = false; }
  if activation_relu(25000) != 10000 { ok = false; }
  if activation_relu(1000000000) != 10000 { ok = false; }
  if activation_relu(-1000000000) != 0 { ok = false; }
  return assert(ok, "relu endpoints, identity region and saturation");
}

fn t3() -> TestResult {
  var ok = true;
  var prev: Int = -1;
  var x = -20000;
  while x <= 20000 {
    let v = activation_relu(x);
    if v < prev { ok = false; }
    if v < 0 || v > 10000 { ok = false; }
    prev = v;
    x = x + 500;
  }
  return assert(ok, "relu is monotone on a grid and stays in [0, 10000]");
}

fn t4() -> TestResult {
  var ok = activation_leaky_relu(-10000, 1000) == -1000;
  if activation_leaky_relu(-5000, 1000) != -500 { ok = false; }
  if activation_leaky_relu(-10, 1000) != -1 { ok = false; }
  if activation_leaky_relu(-1, 1000) != 0 { ok = false; }
  if activation_leaky_relu(0, 1000) != 0 { ok = false; }
  if activation_leaky_relu(5000, 1000) != 5000 { ok = false; }
  if activation_leaky_relu(20000, 1000) != 10000 { ok = false; }
  if activation_leaky_relu(-10000, 0) != 0 { ok = false; }
  if activation_leaky_relu(-10000, 10000) != -10000 { ok = false; }
  if activation_leaky_relu(-10000, 20000) != -10000 { ok = false; }
  if activation_leaky_relu(-10000, -5) != 0 { ok = false; }
  if activation_leaky_relu(-2000000000, 10000) != -10000 { ok = false; }
  return assert(ok, "leaky relu slope branches, clamps and saturation");
}

fn t5() -> TestResult {
  var ok = true;
  var prev: Int = -20000;
  var x = -20000;
  while x <= 20000 {
    let v = activation_leaky_relu(x, 1000);
    if v < prev { ok = false; }
    if v < -10000 || v > 10000 { ok = false; }
    prev = v;
    x = x + 500;
  }
  return assert(ok, "leaky relu is monotone on a grid for slope 1000");
}

fn t6() -> TestResult {
  var ok = activation_elu(0, 10000) == 0;
  if activation_elu(5000, 10000) != 5000 { ok = false; }
  if activation_elu(20000, 10000) != 10000 { ok = false; }
  if activation_elu(-10000, 10000) != -6322 { ok = false; }
  if activation_elu(-20000, 10000) != -8644 { ok = false; }
  if activation_elu(-100000, 10000) != -10000 { ok = false; }
  if activation_elu(-2000000000, 10000) != -10000 { ok = false; }
  if activation_elu(-10000, 5000) != -3161 { ok = false; }
  if activation_elu(-10000, 20000) != -6322 { ok = false; }
  if activation_elu(-10000, 0) != 0 { ok = false; }
  return assert(ok, "elu piecewise branches, alpha scale and saturation");
}

fn t7() -> TestResult {
  var ok = true;
  var prev: Int = -20000;
  var x = -20000;
  while x <= 20000 {
    let v = activation_elu(x, 10000);
    if v < prev { ok = false; }
    if v < -10000 || v > 10000 { ok = false; }
    prev = v;
    x = x + 500;
  }
  return assert(ok, "elu is monotone on a grid and stays in [-10000, 10000]");
}

fn t8() -> TestResult {
  var ok = activation_exp(0) == 10000;
  if activation_exp(-5000) != 6068 { ok = false; }
  if activation_exp(-10000) != 3678 { ok = false; }
  if activation_exp(-20000) != 1356 { ok = false; }
  if activation_exp(-30000) != 499 { ok = false; }
  if activation_exp(-60000) != 25 { ok = false; }
  if activation_exp(-100000) != 0 { ok = false; }
  if activation_exp(-150000) != 0 { ok = false; }
  if activation_exp(-200000) != 0 { ok = false; }
  if activation_exp(5000) != 10000 { ok = false; }
  if abs_int(activation_exp(-5000) - 6065) > 8 { ok = false; }
  if abs_int(activation_exp(-10000) - 3679) > 8 { ok = false; }
  if abs_int(activation_exp(-20000) - 1353) > 8 { ok = false; }
  if abs_int(activation_exp(-30000) - 498) > 8 { ok = false; }
  return assert(ok, "exp fixtures and the documented 8-unit accuracy bound");
}

fn t9() -> TestResult {
  var ok = true;
  var prev: Int = 0;
  var x = -200000;
  while x <= 0 {
    let v = activation_exp(x);
    if v < prev { ok = false; }
    if v < 0 || v > 10000 { ok = false; }
    prev = v;
    x = x + 2500;
  }
  return assert(ok, "exp is monotone non-decreasing on a grid");
}

fn t10() -> TestResult {
  var ok = activation_sigmoid(0) == 5000;
  if activation_sigmoid(10000) != 7311 { ok = false; }
  if activation_sigmoid(20000) != 8805 { ok = false; }
  if activation_sigmoid(30000) != 9524 { ok = false; }
  if activation_sigmoid(60000) != 9975 { ok = false; }
  if activation_sigmoid(100000) != 10000 { ok = false; }
  if activation_sigmoid(1000000000) != 10000 { ok = false; }
  if activation_sigmoid(-10000) != 2688 { ok = false; }
  if activation_sigmoid(-20000) != 1194 { ok = false; }
  if activation_sigmoid(-30000) != 475 { ok = false; }
  if activation_sigmoid(-100000) != 0 { ok = false; }
  if abs_int(activation_sigmoid(10000) - 7311) > 5 { ok = false; }
  if abs_int(activation_sigmoid(20000) - 8808) > 5 { ok = false; }
  if abs_int(activation_sigmoid(30000) - 9526) > 5 { ok = false; }
  if abs_int(activation_sigmoid(-10000) - 2689) > 5 { ok = false; }
  return assert(ok, "sigmoid fixtures and the documented 5-unit accuracy bound");
}

fn t11() -> TestResult {
  var ok = true;
  var prev: Int = -1;
  var x = -60000;
  while x <= 60000 {
    let v = activation_sigmoid(x);
    if v < prev { ok = false; }
    if v < 0 || v > 10000 { ok = false; }
    prev = v;
    x = x + 1000;
  }
  return assert(ok, "sigmoid is monotone on a grid and stays in [0, 10000]");
}

fn t12() -> TestResult {
  var ok = activation_tanh(0) == 0;
  if activation_tanh(10000) != 7611 { ok = false; }
  if activation_tanh(20000) != 9638 { ok = false; }
  if activation_tanh(30000) != 9950 { ok = false; }
  if activation_tanh(40000) != 9994 { ok = false; }
  if activation_tanh(75000) != 10000 { ok = false; }
  if activation_tanh(1000000000) != 10000 { ok = false; }
  if activation_tanh(-10000) != -7611 { ok = false; }
  if activation_tanh(-100000) != -10000 { ok = false; }
  if activation_tanh(-1000000000) != -10000 { ok = false; }
  if abs_int(activation_tanh(10000) - 7616) > 8 { ok = false; }
  if abs_int(activation_tanh(20000) - 9640) > 8 { ok = false; }
  if abs_int(activation_tanh(30000) - 9951) > 8 { ok = false; }
  if abs_int(activation_tanh(40000) - 9993) > 8 { ok = false; }
  if activation_tanh(-10000) != 0 - activation_tanh(10000) { ok = false; }
  return assert(ok, "tanh fixtures, odd symmetry and the 8-unit accuracy bound");
}

fn t13() -> TestResult {
  var ok = true;
  var prev: Int = -10001;
  var x = -80000;
  while x <= 80000 {
    let v = activation_tanh(x);
    if v < prev { ok = false; }
    if v < -10000 || v > 10000 { ok = false; }
    prev = v;
    x = x + 1000;
  }
  return assert(ok, "tanh is monotone on a grid and stays in [-10000, 10000]");
}

fn t14() -> TestResult {
  var ok = activation_relu_derivative(10000) == 10000;
  if activation_relu_derivative(1) != 10000 { ok = false; }
  if activation_relu_derivative(0) != 0 { ok = false; }
  if activation_relu_derivative(-1) != 0 { ok = false; }
  if activation_leaky_relu_derivative(5000, 3000) != 10000 { ok = false; }
  if activation_leaky_relu_derivative(-5000, 3000) != 3000 { ok = false; }
  if activation_leaky_relu_derivative(0, 3000) != 0 { ok = false; }
  if activation_leaky_relu_derivative(-5000, 20000) != 10000 { ok = false; }
  if activation_leaky_relu_derivative(-5000, -3) != 0 { ok = false; }
  return assert(ok, "relu and leaky relu derivative signs and clamps");
}

fn t15() -> TestResult {
  var ok = activation_elu_derivative(5000, 10000) == 10000;
  if activation_elu_derivative(0, 10000) != 10000 { ok = false; }
  if activation_elu_derivative(-10000, 10000) != 3678 { ok = false; }
  if activation_elu_derivative(-20000, 10000) != 1356 { ok = false; }
  if activation_elu_derivative(-100000, 10000) != 0 { ok = false; }
  if activation_elu_derivative(-10000, 5000) != 1839 { ok = false; }
  if activation_elu_derivative(-10000, 20000) != 3678 { ok = false; }
  if activation_elu_derivative(-10000, -1) != 0 { ok = false; }
  return assert(ok, "elu derivative matches the exp-based negative branch");
}

fn t16() -> TestResult {
  var ok = activation_sigmoid_derivative(0) == 2500;
  if activation_sigmoid_derivative(10000) != 1965 { ok = false; }
  if activation_sigmoid_derivative(20000) != 1052 { ok = false; }
  if activation_sigmoid_derivative(60000) != 24 { ok = false; }
  if activation_sigmoid_derivative(100000) != 0 { ok = false; }
  if activation_sigmoid_derivative(-100000) != 0 { ok = false; }
  var prev_ok = true;
  var x = -60000;
  while x <= 60000 {
    let d = activation_sigmoid_derivative(x);
    if d < 0 || d > 2500 { prev_ok = false; }
    x = x + 5000;
  }
  if !prev_ok { ok = false; }
  return assert(ok, "sigmoid derivative peaks at 2500 and stays non-negative");
}

fn t17() -> TestResult {
  var ok = activation_tanh_derivative(0) == 10000;
  if activation_tanh_derivative(10000) != 4208 { ok = false; }
  if activation_tanh_derivative(20000) != 711 { ok = false; }
  if activation_tanh_derivative(100000) != 0 { ok = false; }
  if activation_tanh_derivative(-10000) != 4208 { ok = false; }
  if abs_int(activation_tanh_derivative(10000) - 4200) > 12 { ok = false; }
  if abs_int(activation_tanh_derivative(20000) - 707) > 12 { ok = false; }
  return assert(ok, "tanh derivative matches 10000 - t*t/10000 within 12 bps");
}

fn t18() -> TestResult {
  let l0 = v2(0, 0);
  let l1 = v2(0, -10000);
  let l2 = v2(0, -20000);
  let l3 = v2(5000, 4000);
  let a = ints_of(activation_softmax(&l0));
  let b = ints_of(activation_softmax(&l1));
  let c = ints_of(activation_softmax(&l2));
  let d = ints_of(activation_softmax(&l3));
  let want_a = v2(5000, 5000);
  let want_b = v2(7312, 2688);
  let want_c = v2(8806, 1194);
  let want_d = v2(5251, 4749);
  var ok = ints_equal(&a, &want_a);
  if !ints_equal(&b, &want_b) { ok = false; }
  if !ints_equal(&c, &want_c) { ok = false; }
  if !ints_equal(&d, &want_d) { ok = false; }
  if ints_sum(&a) != 10000 { ok = false; }
  if ints_sum(&b) != 10000 { ok = false; }
  if ints_sum(&c) != 10000 { ok = false; }
  if ints_sum(&d) != 10000 { ok = false; }
  return assert(ok, "softmax two-element fixtures sum to exactly 10000");
}

fn t19() -> TestResult {
  let l0 = v3(4000, 2000, 1000);
  let l1 = v5(1000, 2000, 3000, 4000, 5000);
  let a = ints_of(activation_softmax(&l0));
  let b = ints_of(activation_softmax(&l1));
  let want_a = v3(3907, 3199, 2894);
  let want_b = v5(1620, 1791, 1980, 2187, 2422);
  var ok = ints_equal(&a, &want_a);
  if !ints_equal(&b, &want_b) { ok = false; }
  if ints_sum(&a) != 10000 { ok = false; }
  if ints_sum(&b) != 10000 { ok = false; }
  if !ints_in_range(&a, 0, 10000) { ok = false; }
  if !ints_in_range(&b, 0, 10000) { ok = false; }
  var prev: Int = -1;
  var i = 0;
  while i < b.len() {
    let x: Int = b[i];
    if x < prev { ok = false; }
    prev = x;
    i = i + 1;
  }
  return assert(ok, "softmax three/five-element fixtures stay ordered");
}

fn t20() -> TestResult {
  let l0 = v3(2000, 2000, 2000);
  let a = ints_of(activation_softmax(&l0));
  let want_a = v3(3334, 3333, 3333);
  var ok = ints_equal(&a, &want_a);
  if ints_sum(&a) != 10000 { ok = false; }
  let l1 = v3(0, -100000, 5000);
  let b = ints_of(activation_softmax(&l1));
  if ints_sum(&b) != 10000 { ok = false; }
  if !ints_in_range(&b, 0, 10000) { ok = false; }
  if b.len() != 3 { ok = false; }
  if b.len() == 3 {
    let x0: Int = b[0];
    let x1: Int = b[1];
    let x2: Int = b[2];
    if x2 <= x0 { ok = false; }
    if x0 <= x1 { ok = false; }
    if x1 != 0 { ok = false; }
  }
  return assert(ok, "softmax ties and a strictly ordered three-way split");
}

fn t21() -> TestResult {
  let none = empty_ints();
  let hi = v2(1000001, 0);
  let lo = v2(0, -1000001);
  var ok = ints_err(activation_softmax(&none), "activation: softmax requires a non-empty vector");
  if !ints_err(activation_softmax(&hi), "activation: softmax logit out of range") { ok = false; }
  if !ints_err(activation_softmax(&lo), "activation: softmax logit out of range") { ok = false; }
  return assert(ok, "softmax validates emptiness and the logit envelope");
}

fn t22() -> TestResult {
  var ok = activation_softmax_diag_derivative(5000) == 2500;
  if activation_softmax_diag_derivative(10000) != 0 { ok = false; }
  if activation_softmax_diag_derivative(0) != 0 { ok = false; }
  if activation_softmax_diag_derivative(20000) != 0 { ok = false; }
  if activation_softmax_cross_derivative(5000, 5000) != -2500 { ok = false; }
  if activation_softmax_cross_derivative(10000, 10000) != -10000 { ok = false; }
  if activation_softmax_cross_derivative(0, 5000) != 0 { ok = false; }
  if activation_softmax_cross_derivative(5000, -3) != 0 { ok = false; }
  return assert(ok, "softmax Jacobian helpers and their clamps");
}

fn t23() -> TestResult {
  var ok = activation_relu(1000000000) == 10000;
  if activation_leaky_relu(-1000000000, 10000) != -10000 { ok = false; }
  if activation_elu(-1000000000, 10000) != -10000 { ok = false; }
  if activation_sigmoid(1000000000) != 10000 { ok = false; }
  if activation_sigmoid(-1000000000) != 0 { ok = false; }
  if activation_tanh(1000000000) != 10000 { ok = false; }
  if activation_tanh(-1000000000) != -10000 { ok = false; }
  if activation_exp(-1000000000) != 0 { ok = false; }
  return assert(ok, "extreme inputs saturate instead of overflowing");
}

fn t24() -> TestResult {
  var ok = true;
  var x = -100000;
  while x <= 100000 {
    let r = activation_relu(x);
    let lr = activation_leaky_relu(x, 1000);
    let el = activation_elu(x, 10000);
    let sg = activation_sigmoid(x);
    let th = activation_tanh(x);
    if r < 0 || r > 10000 { ok = false; }
    if lr < -10000 || lr > 10000 { ok = false; }
    if el < -10000 || el > 10000 { ok = false; }
    if sg < 0 || sg > 10000 { ok = false; }
    if th < -10000 || th > 10000 { ok = false; }
    x = x + 10000;
  }
  return assert(ok, "every scalar activation respects the +-10000 saturation");
}

fn main() -> Int {
  io.println("=== xiom.activation conformance tests ===");
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
    io.println("xiom.activation: all tests passed");
  } else {
    io.println("xiom.activation: tests failed");
  }
  return failed;
}
