// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: xiom.metrics 0.2.0 package gate (adoption 2026-10-10; see
// docs/XIOM-METRICS-ADOPTION.md). Direct consumption checks, independent
// of the lane seam:
//   - Counter inc/add/reset; Gauge set/add;
//   - Histogram over the LANE's latency bounds: bucket count, first-fit
//     placement (same corpus as probe_metrics), sum/min/max/mean stats,
//     reset keeps the layout;
//   - labeled registry: get-or-create collapse, distinct label sets are
//     distinct series;
//   - Prometheus text exposition: labeled counter line, cumulative
//     histogram buckets (+Inf), _sum/_count, content type.
// The lane-side alignment lives in probe_metrics (same expected constants
// through the observability.metrics surface).
// Exit = failed checks.

module probe_package_metrics

use xiom.metrics;
use xiom.string.slice;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

// Substring search over a Str body (Str BY VALUE: &Str params mislower,
// XVC-C-13).
fn body_has(body: Str, needle: Str) -> Bool {
  var b = slice.str_bytes(body);
  var n = slice.str_bytes(needle);
  if n.len() == 0 || n.len() > b.len() { return false; }
  var i: Int = 0;
  while i + n.len() <= b.len() {
    var j: Int = 0;
    var ok: Bool = true;
    while j < n.len() {
      if b[i + j] != n[j] {
        ok = false;
        j = n.len();
      } else {
        j = j + 1;
      }
    }
    if ok { return true; }
    i = i + 1;
  }
  return false;
}

// The lane's fixed latency bounds (same layout as observability.metrics).
fn lane_bounds() -> Vec[Int] {
  var bounds = Vec[Int].new();
  bounds.push(1);
  bounds.push(5);
  bounds.push(10);
  bounds.push(50);
  bounds.push(100);
  bounds.push(500);
  bounds.push(1000);
  return bounds;
}

fn main() -> Int {
  io.println("=== xvector probe: xiom.metrics package adoption ===");
  var fails: Int = 0;

  // ---- counters ----
  var c = metric_counter_new();
  metric_counter_inc(&mut c);
  metric_counter_add(&mut c, 4);
  fails = check(metric_counter_value(&c) == 5, "counter: inc + add(4) -> 5", fails);
  metric_counter_reset(&mut c);
  fails = check(metric_counter_value(&c) == 0, "counter: reset -> 0", fails);

  // ---- gauge ----
  var g = metric_gauge_new(10);
  metric_gauge_set(&mut g, 7);
  metric_gauge_add(&mut g, -2);
  fails = check(metric_gauge_value(&g) == 5, "gauge: new(10) set(7) add(-2) -> 5", fails);

  // ---- histogram over the lane's latency bounds ----
  var bounds = lane_bounds();
  var h = metric_histogram_new(&bounds);
  metric_histogram_observe(&mut h, 0);
  metric_histogram_observe(&mut h, 1);
  metric_histogram_observe(&mut h, 5);
  metric_histogram_observe(&mut h, 12);
  metric_histogram_observe(&mut h, 60);
  metric_histogram_observe(&mut h, 120);
  metric_histogram_observe(&mut h, 600);
  metric_histogram_observe(&mut h, 1200);
  fails = check(metric_histogram_bucket_len(&h) == 8 && metric_histogram_count(&h) == 8,
    "histogram: 7 bounds -> 8 buckets, 8 observations", fails);
  fails = check(metric_histogram_bucket_count(&h, 0) == 2 && metric_histogram_bucket_count(&h, 1) == 1
    && metric_histogram_bucket_count(&h, 2) == 0 && metric_histogram_bucket_count(&h, 3) == 1
    && metric_histogram_bucket_count(&h, 4) == 1 && metric_histogram_bucket_count(&h, 5) == 1
    && metric_histogram_bucket_count(&h, 6) == 1 && metric_histogram_bucket_count(&h, 7) == 1,
    "histogram: first-fit bucket placement (lane corpus)", fails);
  fails = check(metric_histogram_sum(&h) == 1998 && metric_histogram_min(&h) == 0
    && metric_histogram_max(&h) == 1200 && metric_histogram_mean(&h) == 249,
    "histogram: sum/min/max/mean stats", fails);
  metric_histogram_reset(&mut h);
  fails = check(metric_histogram_count(&h) == 0 && metric_histogram_bucket_len(&h) == 8,
    "histogram: reset zeroes stats, keeps the bucket layout", fails);

  // ---- labeled registry (get-or-create) ----
  var reg = metric_registry_new();
  var l1 = metric_labels_new();
  metric_labels_add(&mut l1, "route", "/search");
  metric_counter_inc_labeled(&mut reg, "xvector_probe_requests_total", l1, 2);
  var l2 = metric_labels_new();
  metric_labels_add(&mut l2, "route", "/search");
  fails = check(metric_registry_count(&reg) == 1
    && metric_registry_find(&reg, "xvector_probe_requests_total", &l2) == 0,
    "registry: same name+labels collapses into one series", fails);
  var l3 = metric_labels_new();
  metric_labels_add(&mut l3, "route", "/stats");
  fails = check(metric_registry_find(&reg, "xvector_probe_requests_total", &l3) == -1,
    "registry: distinct labels are a distinct series", fails);
  var lb = lane_bounds();
  var lh = metric_labels_new();
  metric_labels_add(&mut lh, "route", "/search");
  metric_histogram_observe_labeled(&mut reg, "xvector_probe_latency_ms", lh, &lb, 5);
  var lh2 = metric_labels_new();
  metric_labels_add(&mut lh2, "route", "/search");
  metric_histogram_observe_labeled(&mut reg, "xvector_probe_latency_ms", lh2, &lb, 60);

  // ---- Prometheus text exposition ----
  var text = metric_exposition(&reg);
  fails = check(body_has(text, "# TYPE xvector_probe_requests_total counter")
    && body_has(text, "xvector_probe_requests_total{route=\"/search\"} 2"),
    "exposition: labeled counter line", fails);
  fails = check(body_has(text, "xvector_probe_latency_ms_bucket{route=\"/search\",le=\"10\"} 1")
    && body_has(text, "xvector_probe_latency_ms_bucket{route=\"/search\",le=\"+Inf\"} 2")
    && body_has(text, "xvector_probe_latency_ms_sum{route=\"/search\"} 65")
    && body_has(text, "xvector_probe_latency_ms_count{route=\"/search\"} 2"),
    "exposition: cumulative buckets + _sum/_count", fails);
  fails = check(metric_content_type() == "text/plain; version=0.0.4; charset=utf-8",
    "exposition: content type", fails);

  io.println("");
  io.println("probe_package_metrics: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
