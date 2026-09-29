// XIOM -- xiom.loss conformance tests (27 checks)
// Port task: prove the pure-XIOM xiom.loss module against its documented
// fixed-point contract (scaled integers only, no floats).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module loss_tests
use xiom.io; use xiom.test; use xiom.loss;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on Str values read from
// Vec[Str] elements mis-lowers to a pointer comparison, so every error-message
// check below routes through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixtures (value scale: raw = value * 1000)
// ---------------------------------------------------------------------------

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

fn empty_vec() -> Vec[Int] {
  return Vec[Int].new();
}

// ---------------------------------------------------------------------------
// Result extractors with graceful fallbacks: a construction failure makes the
// value checks fail instead of aborting the whole suite.
// ---------------------------------------------------------------------------

fn int_of(r: Result[Int, Str]) -> Int {
  match r {
    Ok(x) => { return x; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn ints_of(r: Result[Vec[Int], Str]) -> Vec[Int] {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_vec(); },
  }
  return empty_vec();
}

fn int_err(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn ints_err(r: Result[Vec[Int], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn absd(a: Int, b: Int) -> Int {
  var d = a - b;
  if d < 0 {
    d = 0 - d;
  }
  return d;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = loss_value_decimals() == 3;
  if loss_loss_decimals() != 6 { ok = false; }
  if loss_value_one() != 1000 { ok = false; }
  if loss_loss_one() != 1000000 { ok = false; }
  if loss_probability_epsilon() != 1 { ok = false; }
  return assert(ok, "scale accessors are 3/6 with unit 1000/1000000 and epsilon 1");
}

fn t2() -> TestResult {
  var ok = int_of(loss_natural_log(1000)) == 0;
  if int_of(loss_natural_log(500)) != -693147 { ok = false; }
  if int_of(loss_natural_log(1500)) != 405465 { ok = false; }
  if int_of(loss_natural_log(1000000)) != 6907755 { ok = false; }
  return assert(ok, "natural_log matches pinned exact values");
}

fn t3() -> TestResult {
  var ok = absd(int_of(loss_natural_log(1)), -6907755) <= 1;
  if absd(int_of(loss_natural_log(100)), -2302585) > 1 { ok = false; }
  if absd(int_of(loss_natural_log(900)), -105361) > 1 { ok = false; }
  if absd(int_of(loss_natural_log(999)), -1001) > 1 { ok = false; }
  return assert(ok, "natural_log tracks true ln within one loss unit");
}

fn t4() -> TestResult {
  var ok = int_err(loss_natural_log(0), "loss: logarithm argument must be positive");
  if !int_err(loss_natural_log(-5), "loss: logarithm argument must be positive") { ok = false; }
  if !int_err(loss_natural_log(9223372036855), "loss: logarithm argument exceeds the supported envelope") { ok = false; }
  return assert(ok, "natural_log rejects non-positive and oversized arguments");
}

fn t5() -> TestResult {
  var ok = int_of(loss_clip(1500, 0, 1000)) == 1000;
  if int_of(loss_clip(-7, 0, 1000)) != 0 { ok = false; }
  if int_of(loss_clip(500, 0, 1000)) != 500 { ok = false; }
  if int_of(loss_clip(1000, 1, 999)) != 999 { ok = false; }
  if int_of(loss_clip(0, 1, 999)) != 1 { ok = false; }
  if int_of(loss_clip(500, 0, 0)) != 0 { ok = false; }
  return assert(ok, "clip clamps into the requested interval");
}

fn t6() -> TestResult {
  let msg: Str = "loss: clip bounds must satisfy 0 <= lo <= hi <= 1000";
  var ok = int_err(loss_clip(500, 800, 600), msg);
  if !int_err(loss_clip(500, -1, 1000), msg) { ok = false; }
  if !int_err(loss_clip(500, 0, 1001), msg) { ok = false; }
  if !int_err(loss_clip(500, 2, 1), msg) { ok = false; }
  return assert(ok, "clip rejects invalid bounds");
}

fn t7() -> TestResult {
  var preds = v2(1000, 2000);
  var targets = v2(1000, 1000);
  var ok = int_of(loss_mse(&preds, &targets)) == 500000;
  var same = v2(250, 250);
  if int_of(loss_mse(&same, &same)) != 0 { ok = false; }
  var one = v1(1000);
  var one_t = v1(250);
  if int_of(loss_mse(&one, &one_t)) != 562500 { ok = false; }
  return assert(ok, "mse is exact on hand-computed fixtures");
}

fn t8() -> TestResult {
  var preds = v2(1001, 1000);
  var targets = v2(1000, 1000);
  var ok = int_of(loss_mse(&preds, &targets)) == 1;
  var e = empty_vec();
  if !int_err(loss_mse(&e, &e), "loss: predictions and targets must not be empty") { ok = false; }
  var a = v2(1, 2);
  var b = v1(1);
  if !int_err(loss_mse(&a, &b), "loss: predictions and targets length mismatch") { ok = false; }
  return assert(ok, "mse rounds halves away from zero and validates inputs");
}

fn t9() -> TestResult {
  var p1 = v2(1000, 2000);
  var t1v = v2(1000, 1000);
  let g1 = ints_of(loss_mse_grad(&p1, &t1v));
  var ok = g1.len() == 2;
  if g1.len() == 2 {
    let a: Int = g1[0];
    let b: Int = g1[1];
    if a != 0 { ok = false; }
    if b != 1000 { ok = false; }
  }
  var p2 = v2(1000, 3000);
  var t2v = v2(2000, 2000);
  let g2 = ints_of(loss_mse_grad(&p2, &t2v));
  if g2.len() != 2 { ok = false; }
  if g2.len() == 2 {
    let a: Int = g2[0];
    let b: Int = g2[1];
    if a != -1000 { ok = false; }
    if b != 1000 { ok = false; }
  }
  return assert(ok, "mse_grad returns 2*(prediction-target)/n");
}

fn t10() -> TestResult {
  var p = v1(2000);
  var t = v1(1000);
  let g = ints_of(loss_mse_grad(&p, &t));
  var ok = g.len() == 1;
  if g.len() == 1 {
    let a: Int = g[0];
    if a != 2000 { ok = false; }
  }
  var e = empty_vec();
  if !ints_err(loss_mse_grad(&e, &e), "loss: predictions and targets must not be empty") { ok = false; }
  var a2 = v2(1, 2);
  var b2 = v1(1);
  if !ints_err(loss_mse_grad(&a2, &b2), "loss: predictions and targets length mismatch") { ok = false; }
  return assert(ok, "mse_grad signs the error and validates inputs");
}

fn t11() -> TestResult {
  var preds = v2(1000, 3000);
  var targets = v2(2000, 2000);
  var ok = int_of(loss_mae(&preds, &targets)) == 1000000;
  var same = v2(250, 250);
  if int_of(loss_mae(&same, &same)) != 0 { ok = false; }
  var one = v1(1500);
  var half = v1(1000);
  if int_of(loss_mae(&one, &half)) != 500000 { ok = false; }
  return assert(ok, "mae is the mean absolute value-scale error");
}

fn t12() -> TestResult {
  var preds = v2(2000, 1000);
  var targets = v2(1000, 2000);
  let g = ints_of(loss_mae_grad(&preds, &targets));
  var ok = g.len() == 2;
  if g.len() == 2 {
    let a: Int = g[0];
    let b: Int = g[1];
    if a != 500 { ok = false; }
    if b != -500 { ok = false; }
  }
  var p1 = v1(1000);
  var t1v = v1(2000);
  let g2 = ints_of(loss_mae_grad(&p1, &t1v));
  if g2.len() != 1 { ok = false; }
  if g2.len() == 1 {
    let a: Int = g2[0];
    if a != -1000 { ok = false; }
  }
  var eq = v2(700, 700);
  let g3 = ints_of(loss_mae_grad(&eq, &eq));
  if g3.len() != 2 { ok = false; }
  if g3.len() == 2 {
    let a: Int = g3[0];
    if a != 0 { ok = false; }
  }
  return assert(ok, "mae_grad is sign-based with 1/n magnitude");
}

fn t13() -> TestResult {
  var e = empty_vec();
  var ok = int_err(loss_mae(&e, &e), "loss: predictions and targets must not be empty");
  var a = v2(1, 2);
  var b = v1(1);
  if !int_err(loss_mae(&a, &b), "loss: predictions and targets length mismatch") { ok = false; }
  return assert(ok, "mae validates inputs");
}

fn t14() -> TestResult {
  var preds = v2(2000, -2000);
  var targets = v2(1000, -1000);
  var ok = int_of(loss_hinge(&preds, &targets, 1000)) == 0;
  let g = ints_of(loss_hinge_grad(&preds, &targets, 1000));
  if g.len() != 2 { ok = false; }
  if g.len() == 2 {
    let a: Int = g[0];
    let b: Int = g[1];
    if a != 0 { ok = false; }
    if b != 0 { ok = false; }
  }
  return assert(ok, "hinge is zero on correctly classified margins");
}

fn t15() -> TestResult {
  var preds = v2(500, 0);
  var targets = v2(1000, -1000);
  var ok = int_of(loss_hinge(&preds, &targets, 1000)) == 750000;
  let g = ints_of(loss_hinge_grad(&preds, &targets, 1000));
  if g.len() != 2 { ok = false; }
  if g.len() == 2 {
    let a: Int = g[0];
    let b: Int = g[1];
    if a != -500 { ok = false; }
    if b != 500 { ok = false; }
  }
  return assert(ok, "hinge loss and gradient are exact at margin 1.0");
}

fn t16() -> TestResult {
  var preds = v2(0, 0);
  var targets = v2(1000, -1000);
  var ok = int_of(loss_hinge(&preds, &targets, 2000)) == 2000000;
  var p2 = v2(2000, 0);
  var t2v = v2(1000, -1000);
  if int_of(loss_hinge(&p2, &t2v, 1000)) != 500000 { ok = false; }
  let g = ints_of(loss_hinge_grad(&p2, &t2v, 1000));
  if g.len() != 2 { ok = false; }
  if g.len() == 2 {
    let a: Int = g[0];
    let b: Int = g[1];
    if a != 0 { ok = false; }
    if b != 500 { ok = false; }
  }
  return assert(ok, "hinge scales with margin and zeroes inactive gradients");
}

fn t17() -> TestResult {
  var preds = v2(0, 0);
  var bad = v2(1000, 0);
  var ok = int_err(loss_hinge(&preds, &bad, 1000), "loss: hinge target must be +1000 or -1000");
  var bad2 = v2(500, -1000);
  if !int_err(loss_hinge(&preds, &bad2, 1000), "loss: hinge target must be +1000 or -1000") { ok = false; }
  var good = v2(1000, -1000);
  if !int_err(loss_hinge(&preds, &good, -1), "loss: margin must not be negative") { ok = false; }
  var e = empty_vec();
  if !int_err(loss_hinge(&e, &e, 1000), "loss: predictions and targets must not be empty") { ok = false; }
  var a = v2(1, 2);
  var b = v1(1);
  if !int_err(loss_hinge(&a, &b, 1000), "loss: predictions and targets length mismatch") { ok = false; }
  return assert(ok, "hinge validates targets, margin and shapes");
}

fn t18() -> TestResult {
  var p1 = v1(500);
  var t1v = v1(1000);
  var ok = int_of(loss_binary_cross_entropy(&p1, &t1v)) == 693147;
  var p2 = v1(100);
  var t2v = v1(0);
  if int_of(loss_binary_cross_entropy(&p2, &t2v)) != 105361 { ok = false; }
  return assert(ok, "bce matches pinned ln(0.5) and ln(0.9) values");
}

fn t19() -> TestResult {
  var preds = v2(100, 500);
  var targets = v2(1000, 0);
  var ok = int_of(loss_binary_cross_entropy(&preds, &targets)) == 1497866;
  var p1 = v1(999);
  var t1v = v1(1000);
  if int_of(loss_binary_cross_entropy(&p1, &t1v)) != 1001 { ok = false; }
  return assert(ok, "bce averages samples and matches ln(0.999)");
}

fn t20() -> TestResult {
  var z = v1(0);
  var one = v1(1000);
  var ok = int_of(loss_binary_cross_entropy(&z, &one)) == 6907755;
  var one2 = v1(1000);
  var z2 = v1(0);
  if int_of(loss_binary_cross_entropy(&one2, &z2)) != 6907755 { ok = false; }
  var z3 = v1(0);
  var z4 = v1(0);
  if int_of(loss_binary_cross_entropy(&z3, &z4)) != 1001 { ok = false; }
  var one3 = v1(1000);
  var one4 = v1(1000);
  if int_of(loss_binary_cross_entropy(&one3, &one4)) != 1001 { ok = false; }
  return assert(ok, "bce clamps p=0 and p=1 into [1, 999]");
}

fn t21() -> TestResult {
  var p = v2(500, 500);
  var bad = v2(1000, 500);
  var ok = int_err(loss_binary_cross_entropy(&p, &bad), "loss: binary target must be 0 or 1000");
  var e = empty_vec();
  if !int_err(loss_binary_cross_entropy(&e, &e), "loss: predictions and targets must not be empty") { ok = false; }
  var a = v2(1, 2);
  var b = v1(1);
  if !int_err(loss_binary_cross_entropy(&a, &b), "loss: predictions and targets length mismatch") { ok = false; }
  return assert(ok, "bce validates targets and shapes");
}

fn t22() -> TestResult {
  var p1 = v1(500);
  var t1v = v1(1000);
  let g1 = ints_of(loss_binary_cross_entropy_grad(&p1, &t1v));
  var ok = g1.len() == 1;
  if g1.len() == 1 {
    let a: Int = g1[0];
    if a != -2000 { ok = false; }
  }
  var p2 = v1(500);
  var t2v = v1(0);
  let g2 = ints_of(loss_binary_cross_entropy_grad(&p2, &t2v));
  if g2.len() != 1 { ok = false; }
  if g2.len() == 1 {
    let a: Int = g2[0];
    if a != 2000 { ok = false; }
  }
  var p3 = v2(100, 500);
  var t3v = v2(1000, 0);
  let g3 = ints_of(loss_binary_cross_entropy_grad(&p3, &t3v));
  if g3.len() != 2 { ok = false; }
  if g3.len() == 2 {
    let a: Int = g3[0];
    let b: Int = g3[1];
    if a != -5000 { ok = false; }
    if b != 1000 { ok = false; }
  }
  return assert(ok, "bce_grad is (1/n)(-y/p + (1-y)/(1-p))");
}

fn t23() -> TestResult {
  var probs = v2(500, 500);
  var onehot = v2(1000, 0);
  var ok = int_of(loss_categorical_cross_entropy(&probs, &onehot)) == 693147;
  var soft = v2(500, 500);
  if int_of(loss_categorical_cross_entropy(&probs, &soft)) != 693147 { ok = false; }
  var probs3 = v3(100, 400, 500);
  var onehot3 = v3(0, 0, 1000);
  if int_of(loss_categorical_cross_entropy(&probs3, &onehot3)) != 693147 { ok = false; }
  return assert(ok, "categorical cross-entropy is exact on pinned vectors");
}

fn t24() -> TestResult {
  var probs = v2(500, 500);
  var onehot = v2(1000, 0);
  let g1 = ints_of(loss_categorical_cross_entropy_grad(&probs, &onehot));
  var ok = g1.len() == 2;
  if g1.len() == 2 {
    let a: Int = g1[0];
    let b: Int = g1[1];
    if a != -2000 { ok = false; }
    if b != 0 { ok = false; }
  }
  var soft = v2(500, 500);
  let g2 = ints_of(loss_categorical_cross_entropy_grad(&probs, &soft));
  if g2.len() != 2 { ok = false; }
  if g2.len() == 2 {
    let a: Int = g2[0];
    let b: Int = g2[1];
    if a != -1000 { ok = false; }
    if b != -1000 { ok = false; }
  }
  return assert(ok, "categorical gradient is -y/p in value scale");
}

fn t25() -> TestResult {
  var probs = v2(0, 500);
  var onehot = v2(1000, 0);
  var ok = int_of(loss_categorical_cross_entropy(&probs, &onehot)) == 6907755;
  var probs2 = v2(500, 1000);
  var onehot2 = v2(0, 1000);
  if int_of(loss_categorical_cross_entropy(&probs2, &onehot2)) != 1001 { ok = false; }
  return assert(ok, "categorical clamps p=0 and p=1 into [1, 999]");
}

fn t26() -> TestResult {
  var probs = v2(500, 500);
  var bad_sum = v2(600, 600);
  var ok = int_err(loss_categorical_cross_entropy(&probs, &bad_sum), "loss: categorical targets must sum to 1000");
  var bad_hi = v2(1500, -500);
  if !int_err(loss_categorical_cross_entropy(&probs, &bad_hi), "loss: categorical target must be in [0, 1000]") { ok = false; }
  var e = empty_vec();
  if !int_err(loss_categorical_cross_entropy(&e, &e), "loss: predictions and targets must not be empty") { ok = false; }
  var a = v2(1, 2);
  var b = v1(1);
  if !int_err(loss_categorical_cross_entropy(&a, &b), "loss: predictions and targets length mismatch") { ok = false; }
  return assert(ok, "categorical validates targets and shapes");
}

fn t27() -> TestResult {
  var p1 = v1(500);
  var y1 = v1(1000);
  var probs1 = v2(500, 500);
  var onehot1 = v2(1000, 0);
  var ok = int_of(loss_binary_cross_entropy(&p1, &y1)) == int_of(loss_categorical_cross_entropy(&probs1, &onehot1));
  var p2 = v1(999);
  var y2 = v1(1000);
  var probs2 = v2(999, 1);
  var onehot2 = v2(1000, 0);
  if int_of(loss_binary_cross_entropy(&p2, &y2)) != int_of(loss_categorical_cross_entropy(&probs2, &onehot2)) { ok = false; }
  return assert(ok, "bce equals the 2-class categorical cross-entropy");
}

fn main() -> Int {
  io.println("=== xiom.loss conformance tests ===");
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.loss: all tests passed");
  } else {
    io.println("xiom.loss: tests failed");
  }
  return failed;
}
