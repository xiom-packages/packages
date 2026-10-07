// XIOM -- xiom.metrics conformance tests (40 checks)
// Port task: prove the pure-XIOM xiom.metrics module against its documented API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module metrics_tests
use xiom.io; use xiom.test; use xiom.metrics;
use xiom.string.compare; use xiom.string.search;

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

// --- 0.2.0 helpers: labels, registry, exposition ---------------------------
// Same E001 discipline: read-only calls are routed through `&mut` wrappers,
// and every Vec element read is bound to a typed `let`.

fn labels_len_of(l: &mut MetricLabels) -> Int {
  return metric_labels_len(l);
}

fn labels_name_of(l: &mut MetricLabels, i: Int) -> Result[Str, Str] {
  return metric_labels_name(l, i);
}

fn labels_value_of(l: &mut MetricLabels, i: Int) -> Result[Str, Str] {
  return metric_labels_value(l, i);
}

fn labels_equal_of(a: &mut MetricLabels, b: &mut MetricLabels) -> Bool {
  return metric_labels_equal(a, b);
}

fn registry_count_of(r: &mut Registry) -> Int {
  return metric_registry_count(r);
}

fn registry_find_of(r: &mut Registry, name: Str, l: &MetricLabels) -> Int {
  return metric_registry_find(r, name, l);
}

fn entry_counter_of(r: &mut Registry, i: Int) -> Int {
  let v: Int = r.entries[i].c.value;
  return v;
}

fn entry_gauge_of(r: &mut Registry, i: Int) -> Int {
  let v: Int = r.entries[i].g.value;
  return v;
}

fn entry_hist_count_of(r: &mut Registry, i: Int) -> Int {
  return metric_histogram_count(&r.entries[i].h);
}

fn entry_hist_sum_of(r: &mut Registry, i: Int) -> Int {
  return metric_histogram_sum(&r.entries[i].h);
}

fn entry_hist_bucket_of(r: &mut Registry, i: Int, index: Int) -> Int {
  return metric_histogram_bucket_count(&r.entries[i].h, index);
}

fn entry_hist_bounds_len_of(r: &mut Registry, i: Int) -> Int {
  let n: Int = r.entries[i].h.bounds.len();
  return n;
}

fn entry_hist_bound_of(r: &mut Registry, i: Int, index: Int) -> Int {
  let b: Int = r.entries[i].h.bounds[index];
  return b;
}

fn same(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn labels1(n: Str, v: Str) -> MetricLabels {
  var l = metric_labels_new();
  metric_labels_add(&mut l, n, v);
  return l;
}

fn labels2(n0: Str, v0: Str, n1: Str, v1: Str) -> MetricLabels {
  var l = metric_labels_new();
  metric_labels_add(&mut l, n0, v0);
  metric_labels_add(&mut l, n1, v1);
  return l;
}

fn bounds3(b0: Int, b1: Int, b2: Int) -> Vec[Int] {
  var b = Vec[Int].new();
  b.push(b0);
  b.push(b1);
  b.push(b2);
  return b;
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

fn t24() -> TestResult {
  var l = metric_labels_new();
  var ok = labels_len_of(&mut l) == 0;
  metric_labels_add(&mut l, "method", "GET");
  metric_labels_add(&mut l, "code", "200");
  if labels_len_of(&mut l) != 2 { ok = false; }
  return assert(ok, "labels_new is empty and labels_add extends names and values");
}

fn t25() -> TestResult {
  var l = labels2("method", "GET", "code", "200");
  let n0 = labels_name_of(&mut l, 0);
  let v0 = labels_value_of(&mut l, 0);
  let n1 = labels_name_of(&mut l, 1);
  let v1 = labels_value_of(&mut l, 1);
  var ok = n0.is_ok;
  if !v0.is_ok { ok = false; }
  if !n1.is_ok { ok = false; }
  if !v1.is_ok { ok = false; }
  if ok {
    if !same(n0.value, "method") { ok = false; }
    if !same(v0.value, "GET") { ok = false; }
    if !same(n1.value, "code") { ok = false; }
    if !same(v1.value, "200") { ok = false; }
  }
  let bad_name = labels_name_of(&mut l, 2);
  let bad_value = labels_value_of(&mut l, -1);
  if bad_name.is_ok { ok = false; }
  if bad_value.is_ok { ok = false; }
  return assert(ok, "labels accessors return Ok in order and Err out of range");
}

fn t26() -> TestResult {
  var a = labels2("a", "1", "b", "2");
  var b = labels2("b", "2", "a", "1");
  var c = labels2("a", "1", "b", "3");
  var d0 = labels2("dup", "x", "dup", "x");
  var d1 = labels2("dup", "x", "dup", "x");
  var e = labels1("dup", "x");
  var f = labels2("a", "1", "a", "2");
  var g = labels2("a", "2", "a", "1");
  var ok = labels_equal_of(&mut a, &mut b);
  if labels_equal_of(&mut a, &mut c) { ok = false; }
  if !labels_equal_of(&mut d0, &mut d1) { ok = false; }
  if labels_equal_of(&mut d0, &mut e) { ok = false; }
  if labels_equal_of(&mut a, &mut f) { ok = false; }
  if !labels_equal_of(&mut f, &mut g) { ok = false; }
  return assert(ok, "labels_equal is order-insensitive and compares duplicates as counts");
}

fn t27() -> TestResult {
  var r = metric_registry_new();
  var probe = labels2("a", "1", "b", "2");
  var reordered = labels2("b", "2", "a", "1");
  var other = labels2("a", "1", "b", "3");
  var ok = registry_count_of(&mut r) == 0;
  if registry_find_of(&mut r, "m", &probe) != -1 { ok = false; }
  let i0 = metric_counter_inc_labeled(&mut r, "m", labels2("a", "1", "b", "2"), 1);
  if registry_find_of(&mut r, "m", &probe) != i0 { ok = false; }
  if registry_find_of(&mut r, "m", &reordered) != i0 { ok = false; }
  if registry_find_of(&mut r, "m", &other) != -1 { ok = false; }
  if registry_find_of(&mut r, "nope", &probe) != -1 { ok = false; }
  return assert(ok, "registry_find: -1 on empty/absent, index on present (label order ignored)");
}

fn t28() -> TestResult {
  var r = metric_registry_new();
  let i0 = metric_counter_inc_labeled(&mut r, "http_requests", labels2("method", "GET", "code", "200"), 1);
  let i1 = metric_counter_inc_labeled(&mut r, "http_requests", labels2("method", "GET", "code", "200"), 2);
  let i2 = metric_counter_inc_labeled(&mut r, "http_requests", labels2("method", "POST", "code", "200"), 4);
  var ok = i0 == 0;
  if i1 != i0 { ok = false; }
  if i2 == i0 { ok = false; }
  if registry_count_of(&mut r) != 2 { ok = false; }
  if entry_counter_of(&mut r, i0) != 3 { ok = false; }
  if entry_counter_of(&mut r, i2) != 4 { ok = false; }
  return assert(ok, "counter_inc_labeled accumulates per (name,labels) and separates label sets");
}

fn t29() -> TestResult {
  var r = metric_registry_new();
  let i0 = metric_gauge_set_labeled(&mut r, "inflight", labels1("svc", "api"), 7);
  let i1 = metric_gauge_set_labeled(&mut r, "inflight", labels1("svc", "api"), -2);
  var ok = i0 == i1;
  if registry_count_of(&mut r) != 1 { ok = false; }
  if entry_gauge_of(&mut r, i0) != -2 { ok = false; }
  return assert(ok, "gauge_set_labeled creates on first call and overwrites after");
}

fn t30() -> TestResult {
  var r = metric_registry_new();
  var b1 = bounds3(10, 20, 30);
  var b2 = bounds3(100, 200, 300);
  let i0 = metric_histogram_observe_labeled(&mut r, "latency", labels1("route", "/"), &b1, 5);
  let i1 = metric_histogram_observe_labeled(&mut r, "latency", labels1("route", "/"), &b2, 25);
  var ok = i0 == i1;
  if registry_count_of(&mut r) != 1 { ok = false; }
  if entry_hist_count_of(&mut r, i0) != 2 { ok = false; }
  if entry_hist_sum_of(&mut r, i0) != 30 { ok = false; }
  if entry_hist_bounds_len_of(&mut r, i0) != 3 { ok = false; }
  if entry_hist_bound_of(&mut r, i0, 0) != 10 { ok = false; }
  if entry_hist_bucket_of(&mut r, i0, 0) != 1 { ok = false; }
  if entry_hist_bucket_of(&mut r, i0, 1) != 0 { ok = false; }
  if entry_hist_bucket_of(&mut r, i0, 2) != 1 { ok = false; }
  return assert(ok, "histogram_observe_labeled aggregates and keeps first-call bounds");
}

fn t31() -> TestResult {
  var r0 = metric_registry_new();
  metric_counter_inc_labeled(&mut r0, "requests_total", metric_labels_new(), 7);
  let e0 = metric_exposition(&r0);
  var r1 = metric_registry_new();
  metric_counter_inc_labeled(&mut r1, "requests_total", labels1("method", "GET"), 3);
  let e1 = metric_exposition(&r1);
  var r2 = metric_registry_new();
  metric_counter_inc_labeled(&mut r2, "requests_total", labels2("method", "GET", "code", "200"), 3);
  let e2 = metric_exposition(&r2);
  var ok = same(e0, "# TYPE requests_total counter\nrequests_total 7\n");
  if !same(e1, "# TYPE requests_total counter\nrequests_total{method=\"GET\"} 3\n") { ok = false; }
  if !same(e2, "# TYPE requests_total counter\nrequests_total{method=\"GET\",code=\"200\"} 3\n") { ok = false; }
  return assert(ok, "exposition: counter 0/1/2 labels with braces and comma placement");
}

fn t32() -> TestResult {
  var r0 = metric_registry_new();
  metric_gauge_set_labeled(&mut r0, "inflight", metric_labels_new(), 0);
  let e0 = metric_exposition(&r0);
  var r1 = metric_registry_new();
  metric_gauge_set_labeled(&mut r1, "inflight", labels1("svc", "api"), 5);
  let e1 = metric_exposition(&r1);
  var ok = same(e0, "# TYPE inflight gauge\ninflight 0\n");
  if !same(e1, "# TYPE inflight gauge\ninflight{svc=\"api\"} 5\n") { ok = false; }
  return assert(ok, "exposition: gauge without and with one label");
}

fn t33() -> TestResult {
  var r = metric_registry_new();
  var b = bounds3(10, 20, 30);
  metric_histogram_observe_labeled(&mut r, "latency", metric_labels_new(), &b, 5);
  metric_histogram_observe_labeled(&mut r, "latency", metric_labels_new(), &b, 15);
  metric_histogram_observe_labeled(&mut r, "latency", metric_labels_new(), &b, 25);
  metric_histogram_observe_labeled(&mut r, "latency", metric_labels_new(), &b, 35);
  let e = metric_exposition(&r);
  var want = "# TYPE latency histogram\n";
  want = want + "latency_bucket{le=\"10\"} 1\n";
  want = want + "latency_bucket{le=\"20\"} 2\n";
  want = want + "latency_bucket{le=\"30\"} 3\n";
  want = want + "latency_bucket{le=\"+Inf\"} 4\n";
  want = want + "latency_sum 80\n";
  want = want + "latency_count 4\n";
  return assert(same(e, want), "exposition: histogram cumulative buckets, +Inf, sum and count");
}

fn t34() -> TestResult {
  var r = metric_registry_new();
  var b = bounds3(10, 20, 30);
  metric_histogram_observe_labeled(&mut r, "latency_ms", labels1("route", "/x"), &b, 7);
  let e = metric_exposition(&r);
  var want = "# TYPE latency_ms histogram\n";
  want = want + "latency_ms_bucket{route=\"/x\",le=\"10\"} 1\n";
  want = want + "latency_ms_bucket{route=\"/x\",le=\"20\"} 1\n";
  want = want + "latency_ms_bucket{route=\"/x\",le=\"30\"} 1\n";
  want = want + "latency_ms_bucket{route=\"/x\",le=\"+Inf\"} 1\n";
  want = want + "latency_ms_sum{route=\"/x\"} 7\n";
  want = want + "latency_ms_count{route=\"/x\"} 1\n";
  return assert(same(e, want), "exposition: histogram metric labels precede le");
}

fn t35() -> TestResult {
  var r = metric_registry_new();
  let raw = "a\"b\\c\n";
  metric_counter_inc_labeled(&mut r, "esc", labels1("path", raw), 1);
  let e = metric_exposition(&r);
  var want = "# TYPE esc counter\n";
  want = want + "esc{path=\"a\\\"b\\\\c\\n\"} 1\n";
  return assert(same(e, want), "exposition: label values escape backslash, quote and newline");
}

fn t36() -> TestResult {
  var r = metric_registry_new();
  let e = metric_exposition(&r);
  return assert(e.len() == 0, "exposition: empty registry renders as the empty string");
}

fn t37() -> TestResult {
  return assert(same(metric_content_type(), "text/plain; version=0.0.4; charset=utf-8"), "content type is the 0.0.4 text format");
}

fn t38() -> TestResult {
  var r = metric_registry_new();
  metric_counter_inc_labeled(&mut r, "c", labels1("k", "v"), 5);
  metric_gauge_set_labeled(&mut r, "g", metric_labels_new(), 9);
  metric_registry_reset(&mut r);
  var ok = registry_count_of(&mut r) == 0;
  let i = metric_counter_inc_labeled(&mut r, "c", metric_labels_new(), 2);
  if i != 0 { ok = false; }
  if registry_count_of(&mut r) != 1 { ok = false; }
  let e = metric_exposition(&r);
  if !same(e, "# TYPE c counter\nc 2\n") { ok = false; }
  return assert(ok, "registry_reset drops every entry and the registry is reusable");
}

fn t39() -> TestResult {
  let b = metric_latency_bounds_ms();
  var ok = b.len() == 11;
  let b0: Int = b[0];
  let b1: Int = b[1];
  let b2: Int = b[2];
  let b3: Int = b[3];
  let b4: Int = b[4];
  let b5: Int = b[5];
  let b6: Int = b[6];
  let b7: Int = b[7];
  let b8: Int = b[8];
  let b9: Int = b[9];
  let b10: Int = b[10];
  if b0 != 1 { ok = false; }
  if b1 != 5 { ok = false; }
  if b2 != 10 { ok = false; }
  if b3 != 25 { ok = false; }
  if b4 != 50 { ok = false; }
  if b5 != 100 { ok = false; }
  if b6 != 250 { ok = false; }
  if b7 != 500 { ok = false; }
  if b8 != 1000 { ok = false; }
  if b9 != 2500 { ok = false; }
  if b10 != 5000 { ok = false; }
  return assert(ok, "latency_bounds_ms has the exact PULSE preset");
}

fn t40() -> TestResult {
  var r = metric_registry_new();
  let b = metric_latency_bounds_ms();
  metric_histogram_observe_labeled(&mut r, "latency_ms", metric_labels_new(), &b, 700);
  let e = metric_exposition(&r);
  var ok = search.str_count_occurrences(e, "latency_ms_bucket{le=\"") == 12;
  if search.str_count_occurrences(e, "+Inf") != 1 { ok = false; }
  if search.str_count_occurrences(e, "latency_ms_count 1") != 1 { ok = false; }
  if search.str_count_occurrences(e, "latency_ms_sum 700") != 1 { ok = false; }
  return assert(ok, "latency preset exposes 11 finite buckets + +Inf via the exposition");
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
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  let r31 = t31();
  if r31.passed { io.println("  [PASS] " + r31.name); } else { io.println("  [FAIL] " + r31.name); failed = failed + 1; }
  let r32 = t32();
  if r32.passed { io.println("  [PASS] " + r32.name); } else { io.println("  [FAIL] " + r32.name); failed = failed + 1; }
  let r33 = t33();
  if r33.passed { io.println("  [PASS] " + r33.name); } else { io.println("  [FAIL] " + r33.name); failed = failed + 1; }
  let r34 = t34();
  if r34.passed { io.println("  [PASS] " + r34.name); } else { io.println("  [FAIL] " + r34.name); failed = failed + 1; }
  let r35 = t35();
  if r35.passed { io.println("  [PASS] " + r35.name); } else { io.println("  [FAIL] " + r35.name); failed = failed + 1; }
  let r36 = t36();
  if r36.passed { io.println("  [PASS] " + r36.name); } else { io.println("  [FAIL] " + r36.name); failed = failed + 1; }
  let r37 = t37();
  if r37.passed { io.println("  [PASS] " + r37.name); } else { io.println("  [FAIL] " + r37.name); failed = failed + 1; }
  let r38 = t38();
  if r38.passed { io.println("  [PASS] " + r38.name); } else { io.println("  [FAIL] " + r38.name); failed = failed + 1; }
  let r39 = t39();
  if r39.passed { io.println("  [PASS] " + r39.name); } else { io.println("  [FAIL] " + r39.name); failed = failed + 1; }
  let r40 = t40();
  if r40.passed { io.println("  [PASS] " + r40.name); } else { io.println("  [FAIL] " + r40.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.metrics: all tests passed");
  } else {
    io.println("xiom.metrics: tests failed");
  }
  return failed;
}
