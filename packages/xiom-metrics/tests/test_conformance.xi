// XIOM -- xiom.metrics conformance tests (23 checks)
// Port task: prove the pure-XIOM xiom.metrics module against its documented API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module metrics_tests
use xiom.io; use xiom.test; use xiom.metrics;

// Read-only operations are wrapped in small helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001). Each helper calls the real `&`-based API.

fn counter_of(c: &mut Counter) -> Int {
  return metric_counter_value(c);
}

fn gauge_of(g: &mut Gauge) -> Int {
  return metric_gauge_value(g);
}

fn bucket_of(h: &mut Histogram, index: Int) -> Int {
  return metric_histogram_bucket_count(h, index);
}

fn bucket_len_of(h: &mut Histogram) -> Int {
  return metric_histogram_bucket_len(h);
}

fn count_of(h: &mut Histogram) -> Int {
  return metric_histogram_count(h);
}

fn sum_of(h: &mut Histogram) -> Int {
  return metric_histogram_sum(h);
}

fn min_of(h: &mut Histogram) -> Int {
  return metric_histogram_min(h);
}

fn max_of(h: &mut Histogram) -> Int {
  return metric_histogram_max(h);
}

fn mean_of(h: &mut Histogram) -> Int {
  return metric_histogram_mean(h);
}

// Builders keep every bound Vec construction local to one function body.

fn hist_empty() -> Histogram {
  var bounds = Vec[Int].new();
  return metric_histogram_new(&bounds);
}

fn hist_of1(b0: Int) -> Histogram {
  var bounds = Vec[Int].new();
  bounds.push(b0);
  return metric_histogram_new(&bounds);
}

fn hist_of(b0: Int, b1: Int, b2: Int) -> Histogram {
  var bounds = Vec[Int].new();
  bounds.push(b0);
  bounds.push(b1);
  bounds.push(b2);
  return metric_histogram_new(&bounds);
}

fn hist_copies(b: &mut Vec[Int]) -> Histogram {
  return metric_histogram_new(b);
}

fn t1() -> TestResult {
  var c = metric_counter_new();
  return assert(counter_of(&mut c) == 0, "counter starts at zero");
}

fn t2() -> TestResult {
  var c = metric_counter_new();
  metric_counter_inc(&mut c);
  metric_counter_inc(&mut c);
  metric_counter_inc(&mut c);
  return assert(counter_of(&mut c) == 3, "counter_inc adds one per call");
}

fn t3() -> TestResult {
  var c = metric_counter_new();
  metric_counter_add(&mut c, 5);
  var ok = counter_of(&mut c) == 5;
  metric_counter_add(&mut c, 37);
  if counter_of(&mut c) != 42 { ok = false; }
  return assert(ok, "counter_add accumulates positive deltas");
}

fn t4() -> TestResult {
  var c = metric_counter_new();
  metric_counter_add(&mut c, 10);
  metric_counter_add(&mut c, -3);
  var ok = counter_of(&mut c) == 7;
  metric_counter_add(&mut c, -7);
  if counter_of(&mut c) != 0 { ok = false; }
  metric_counter_add(&mut c, -4);
  if counter_of(&mut c) != -4 { ok = false; }
  return assert(ok, "counter_add accepts negative deltas");
}

fn t5() -> TestResult {
  var c = metric_counter_new();
  metric_counter_add(&mut c, 9);
  metric_counter_reset(&mut c);
  var ok = counter_of(&mut c) == 0;
  metric_counter_add(&mut c, 2);
  if counter_of(&mut c) != 2 { ok = false; }
  return assert(ok, "counter_reset zeroes the counter");
}

fn t6() -> TestResult {
  var zero = metric_gauge_new(0);
  var seven = metric_gauge_new(7);
  var neg = metric_gauge_new(-12);
  var ok = gauge_of(&mut zero) == 0;
  if gauge_of(&mut seven) != 7 { ok = false; }
  if gauge_of(&mut neg) != -12 { ok = false; }
  return assert(ok, "gauge_new holds the initial value");
}

fn t7() -> TestResult {
  var g = metric_gauge_new(3);
  metric_gauge_set(&mut g, 42);
  var ok = gauge_of(&mut g) == 42;
  metric_gauge_set(&mut g, -1);
  if gauge_of(&mut g) != -1 { ok = false; }
  metric_gauge_set(&mut g, 0);
  if gauge_of(&mut g) != 0 { ok = false; }
  return assert(ok, "gauge_set replaces the value");
}

fn t8() -> TestResult {
  var g = metric_gauge_new(10);
  metric_gauge_add(&mut g, 5);
  var ok = gauge_of(&mut g) == 15;
  metric_gauge_add(&mut g, -20);
  if gauge_of(&mut g) != -5 { ok = false; }
  return assert(ok, "gauge_add accumulates positive and negative deltas");
}

fn t9() -> TestResult {
  var h = hist_of(10, 20, 30);
  var one = hist_of1(5);
  var e = hist_empty();
  var ok = bucket_len_of(&mut h) == 4;
  if bucket_len_of(&mut one) != 2 { ok = false; }
  if bucket_len_of(&mut e) != 1 { ok = false; }
  return assert(ok, "bucket_len is bounds.len() + 1");
}

fn t10() -> TestResult {
  var h = hist_of(10, 20, 30);
  metric_histogram_observe(&mut h, 10);
  metric_histogram_observe(&mut h, 20);
  metric_histogram_observe(&mut h, 30);
  var ok = bucket_of(&mut h, 0) == 1;
  if bucket_of(&mut h, 1) != 1 { ok = false; }
  if bucket_of(&mut h, 2) != 1 { ok = false; }
  if bucket_of(&mut h, 3) != 0 { ok = false; }
  return assert(ok, "observations exactly at a bound land in that bucket");
}

fn t11() -> TestResult {
  var h = hist_of(10, 20, 30);
  metric_histogram_observe(&mut h, 5);
  metric_histogram_observe(&mut h, 11);
  metric_histogram_observe(&mut h, 21);
  var ok = bucket_of(&mut h, 0) == 1;
  if bucket_of(&mut h, 1) != 1 { ok = false; }
  if bucket_of(&mut h, 2) != 1 { ok = false; }
  if bucket_of(&mut h, 3) != 0 { ok = false; }
  return assert(ok, "values between bounds land in the first fitting bucket");
}

fn t12() -> TestResult {
  var h = hist_of(10, 20, 30);
  metric_histogram_observe(&mut h, 31);
  metric_histogram_observe(&mut h, 1000);
  var ok = bucket_of(&mut h, 3) == 2;
  if bucket_of(&mut h, 0) != 0 { ok = false; }
  if bucket_of(&mut h, 1) != 0 { ok = false; }
  if bucket_of(&mut h, 2) != 0 { ok = false; }
  return assert(ok, "values above the last bound fill the overflow bucket");
}

fn t13() -> TestResult {
  var h = hist_of(10, 20, 30);
  metric_histogram_observe(&mut h, 10);
  metric_histogram_observe(&mut h, 10);
  metric_histogram_observe(&mut h, 10);
  metric_histogram_observe(&mut h, 20);
  var ok = bucket_of(&mut h, 0) == 3;
  if bucket_of(&mut h, 1) != 1 { ok = false; }
  if bucket_of(&mut h, 2) != 0 { ok = false; }
  if bucket_of(&mut h, 3) != 0 { ok = false; }
  return assert(ok, "repeated values accumulate in one bucket");
}

fn t14() -> TestResult {
  var h = hist_of(10, 20, 30);
  metric_histogram_observe(&mut h, -5);
  metric_histogram_observe(&mut h, -100);
  var ok = min_of(&mut h) == -100;
  if max_of(&mut h) != -5 { ok = false; }
  if sum_of(&mut h) != -105 { ok = false; }
  if bucket_of(&mut h, 0) != 2 { ok = false; }
  return assert(ok, "negative observations count and track extremes");
}

fn t15() -> TestResult {
  var h = hist_of(100, 200, 300);
  metric_histogram_observe(&mut h, 1);
  metric_histogram_observe(&mut h, 2);
  metric_histogram_observe(&mut h, 3);
  metric_histogram_observe(&mut h, 400);
  var ok = count_of(&mut h) == 4;
  if sum_of(&mut h) != 406 { ok = false; }
  return assert(ok, "count and sum track every observation");
}

fn t16() -> TestResult {
  var h = hist_of(10, 20, 30);
  metric_histogram_observe(&mut h, 7);
  metric_histogram_observe(&mut h, 99);
  metric_histogram_observe(&mut h, 15);
  var ok = min_of(&mut h) == 7;
  if max_of(&mut h) != 99 { ok = false; }
  metric_histogram_observe(&mut h, 3);
  if min_of(&mut h) != 3 { ok = false; }
  if max_of(&mut h) != 99 { ok = false; }
  return assert(ok, "min and max track the observed extremes");
}

fn t17() -> TestResult {
  var h = hist_of(10, 20, 30);
  metric_histogram_observe(&mut h, 1);
  metric_histogram_observe(&mut h, 2);
  metric_histogram_observe(&mut h, 3);
  metric_histogram_observe(&mut h, 4);
  var ok = mean_of(&mut h) == 2;
  metric_histogram_observe(&mut h, 7);
  if mean_of(&mut h) != 3 { ok = false; }
  return assert(ok, "mean is integer sum/count (floor)");
}

fn t18() -> TestResult {
  var h = hist_of(10, 20, 30);
  var ok = count_of(&mut h) == 0;
  if sum_of(&mut h) != 0 { ok = false; }
  if min_of(&mut h) != 0 { ok = false; }
  if max_of(&mut h) != 0 { ok = false; }
  if mean_of(&mut h) != 0 { ok = false; }
  if bucket_len_of(&mut h) != 4 { ok = false; }
  if bucket_of(&mut h, 0) != 0 { ok = false; }
  if bucket_of(&mut h, 3) != 0 { ok = false; }
  return assert(ok, "empty histogram reports zeroed statistics");
}

fn t19() -> TestResult {
  var h = hist_empty();
  metric_histogram_observe(&mut h, -3);
  metric_histogram_observe(&mut h, 42);
  metric_histogram_observe(&mut h, 0);
  var ok = bucket_len_of(&mut h) == 1;
  if bucket_of(&mut h, 0) != 3 { ok = false; }
  if count_of(&mut h) != 3 { ok = false; }
  return assert(ok, "empty bounds give one all-catching bucket");
}

fn t20() -> TestResult {
  var h = hist_of(10, 20, 30);
  metric_histogram_observe(&mut h, 5);
  metric_histogram_observe(&mut h, 25);
  metric_histogram_reset(&mut h);
  var ok = bucket_len_of(&mut h) == 4;
  if count_of(&mut h) != 0 { ok = false; }
  if sum_of(&mut h) != 0 { ok = false; }
  if min_of(&mut h) != 0 { ok = false; }
  if max_of(&mut h) != 0 { ok = false; }
  if bucket_of(&mut h, 0) != 0 { ok = false; }
  if bucket_of(&mut h, 2) != 0 { ok = false; }
  metric_histogram_observe(&mut h, 25);
  if bucket_of(&mut h, 2) != 1 { ok = false; }
  if count_of(&mut h) != 1 { ok = false; }
  if sum_of(&mut h) != 25 { ok = false; }
  if min_of(&mut h) != 25 { ok = false; }
  if max_of(&mut h) != 25 { ok = false; }
  return assert(ok, "reset zeroes observations and keeps bounds");
}

fn t21() -> TestResult {
  var h = hist_of(10, 20, 30);
  metric_histogram_observe(&mut h, 1);
  var ok = bucket_of(&mut h, -1) == 0;
  if bucket_of(&mut h, 4) != 0 { ok = false; }
  if bucket_of(&mut h, 99) != 0 { ok = false; }
  return assert(ok, "out-of-range bucket index returns 0");
}

fn t22() -> TestResult {
  var h = hist_of(10, 20, 30);
  var i = 0;
  var expected_sum = 0;
  while i < 1000 {
    let v: Int = i % 50;
    metric_histogram_observe(&mut h, v);
    expected_sum = expected_sum + v;
    i = i + 1;
  }
  var ok = count_of(&mut h) == 1000;
  if sum_of(&mut h) != expected_sum { ok = false; }
  let total = bucket_of(&mut h, 0) + bucket_of(&mut h, 1) + bucket_of(&mut h, 2) + bucket_of(&mut h, 3);
  if total != 1000 { ok = false; }
  if min_of(&mut h) != 0 { ok = false; }
  if max_of(&mut h) != 49 { ok = false; }
  return assert(ok, "1000 observations stay consistent across buckets");
}

fn t23() -> TestResult {
  var bounds = Vec[Int].new();
  bounds.push(10);
  bounds.push(20);
  bounds.push(30);
  var h = hist_copies(&mut bounds);
  bounds.push(40);
  bounds.push(50);
  metric_histogram_observe(&mut h, 35);
  var ok = bucket_len_of(&mut h) == 4;
  if bucket_of(&mut h, 3) != 1 { ok = false; }
  return assert(ok, "histogram_new copies the bounds");
}

fn main() -> Int {
  io.println("=== xiom.metrics conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.metrics: all tests passed");
  } else {
    io.println("xiom.metrics: tests failed");
  }
  return failed;
}
