// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.observability.metrics

// In-repo observability surface (M-O / O1), now backed by the registry
// package `xiom.metrics` 0.2.0 (adoption slice 2026-10-10; see
// docs/XIOM-METRICS-ADOPTION.md). The exported surface is unchanged for
// consumers: fixed-bucket latency histograms + a percentile view, the
// ServiceMetrics bundle, and the bounded structured-log ring. The value
// types and the bucket mechanics come from the package; percentiles, the
// Prometheus histogram block, and the log ring stay lane-owned (the
// package deliberately excludes percentile estimation and log storage --
// see its SPEC Non-goals).
//
// This module is pure (no engine/no io): everything is probe-able with
// plain function calls, and the numbers are deterministic.

use xiom.convert;
use xiom.string.slice;
use xiom.metrics;

// ---- Histogram (fixed upper bounds in ms; last bucket is +Inf) ----

// The lane's fixed latency bounds; passed to the package histogram so the
// bucket layout stays a lane decision (same 7 bounds as pre-adoption).
fn histogram_lane_bounds() -> Vec[Int] {
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

pub fn histogram_new() -> Histogram {
  var bounds = histogram_lane_bounds();
  return metric_histogram_new(&bounds);
}

// Record one observation; negative values clamp to 0 (lane contract; the
// package records the given value verbatim).
pub fn histogram_observe(h: &mut Histogram, ms: Int) {
  var v: Int = ms;
  if v < 0 { v = 0; }
  metric_histogram_observe(h, v);
}

// ---- Lane accessors over the package histogram. Consumers (http_service,
// probes) read through these so the module stays the only seam that names
// the package value types. ----

pub fn histogram_count(h: &Histogram) -> Int {
  return metric_histogram_count(h);
}

pub fn histogram_sum(h: &Histogram) -> Int {
  return metric_histogram_sum(h);
}

pub fn histogram_min(h: &Histogram) -> Int {
  return metric_histogram_min(h);
}

pub fn histogram_max(h: &Histogram) -> Int {
  return metric_histogram_max(h);
}

pub fn histogram_mean(h: &Histogram) -> Int {
  return metric_histogram_mean(h);
}

pub fn histogram_bucket_len(h: &Histogram) -> Int {
  return metric_histogram_bucket_len(h);
}

pub fn histogram_bucket_count(h: &Histogram, index: Int) -> Int {
  return metric_histogram_bucket_count(h, index);
}

pub fn histogram_bounds_len(h: &Histogram) -> Int {
  return h.bounds.len();
}

// Upper bound of bucket window `i`; callers pass a valid index
// (0 <= i < histogram_bounds_len).
pub fn histogram_bound(h: &Histogram, i: Int) -> Int {
  return h.bounds[i];
}

// Percentile as the upper bound of the bucket where the rank falls
// (rank = ceil(p/100 * observations)); 0 when empty. The +Inf bucket
// reports as `last bound + 1` (documented sentinel). Lane-owned: the
// package exposes raw bucket counts only (SPEC Non-goals).
pub fn histogram_percentile(h: &Histogram, p: Int) -> Int {
  var n: Int = histogram_count(h);
  if n == 0 { return 0; }
  var rank: Int = (p * n + 99) / 100;
  if rank < 1 { rank = 1; }
  var nbounds: Int = histogram_bounds_len(h);
  var cum: Int = 0;
  var b: Int = 0;
  while b < histogram_bucket_len(h) {
    cum = cum + histogram_bucket_count(h, b);
    if cum >= rank {
      if b < nbounds { return histogram_bound(h, b); }
      return histogram_bound(h, nbounds - 1) + 1;
    }
    b = b + 1;
  }
  return histogram_bound(h, nbounds - 1) + 1;
}

// Prometheus histogram block (moved here from http_service in the adoption
// slice so consumers never name the package types): # TYPE, cumulative
// bucket lines incl. the +Inf bucket, _sum/_count, and the lane's
// p50/p95/p99 percentile lines. Byte-identical to the pre-adoption render.
pub fn histogram_render_lines(name: Str, h: &Histogram) -> Str {
  var out = "# TYPE " + name + " histogram\n";
  var cum: Int = 0;
  var b: Int = 0;
  while b < histogram_bucket_len(h) {
    cum = cum + histogram_bucket_count(h, b);
    if b < histogram_bounds_len(h) {
      out = out + name + "_bucket{le=\"" + convert.int_to_string(histogram_bound(h, b)) + "\"} " + convert.int_to_string(cum) + "\n";
    } else {
      out = out + name + "_bucket{le=\"+Inf\"} " + convert.int_to_string(cum) + "\n";
    }
    b = b + 1;
  }
  out = out + name + "_sum " + convert.int_to_string(histogram_sum(h)) + "\n";
  out = out + name + "_count " + convert.int_to_string(histogram_count(h)) + "\n";
  out = out + name + "_p50 " + convert.int_to_string(histogram_percentile(h, 50)) + "\n";
  out = out + name + "_p95 " + convert.int_to_string(histogram_percentile(h, 95)) + "\n";
  out = out + name + "_p99 " + convert.int_to_string(histogram_percentile(h, 99)) + "\n";
  return out;
}

// ---- Service metrics bundle (package value types behind the seam) ----

pub type ServiceMetrics = {
  requests_total: Counter;
  errors_total: Counter;
  search_ops: Counter;
  upsert_ops: Counter;
  auth_failures: Counter;
  rate_limited: Counter;
  latency_ms: Histogram;
  search_latency_ms: Histogram;
}

pub fn service_metrics_new() -> ServiceMetrics {
  return ServiceMetrics{
    requests_total: metric_counter_new(),
    errors_total: metric_counter_new(),
    search_ops: metric_counter_new(),
    upsert_ops: metric_counter_new(),
    auth_failures: metric_counter_new(),
    rate_limited: metric_counter_new(),
    latency_ms: histogram_new(),
    search_latency_ms: histogram_new(),
  };
}

// Counter seam. The names cannot be the package's own (`metric_counter_*`:
// a module-level definition would shadow the import) and cannot be the
// core shim's `counter_inc` (http_service imports the shim for CoreError
// alongside this module), hence the service_* spelling.
pub fn service_counter_inc(c: &mut Counter) {
  metric_counter_inc(c);
}

pub fn service_counter_value(c: &Counter) -> Int {
  return metric_counter_value(c);
}

// ---- Bounded structured-log ring (JSON lines) ----

pub type LogRing = {
  lines: Vec[Str];
  capacity: Int;
  slow_ms: Int;
  dropped: Int;
}

pub fn log_ring_new(capacity: Int, slow_ms: Int) -> LogRing {
  var cap: Int = capacity;
  if cap < 1 { cap = 1; }
  return LogRing{ lines: Vec[Str].new(), capacity: cap, slow_ms: slow_ms, dropped: 0 };
}

// Sanitize a string for a JSON line (requests can carry arbitrary bytes):
// quote, backslash, and control characters become '_'.
fn log_safe(s: Str) -> Str {
  var b = slice.str_bytes(s);
  var out = Vec[UInt8].new();
  var i: Int = 0;
  while i < b.len() {
    var c = b[i];
    if c == 34 || c == 92 || c < 32 {
      out.push(95);
    } else {
      out.push(c);
    }
    i = i + 1;
  }
  return Str::from_utf8(&out);
}

pub fn log_ring_push(r: &mut LogRing, method: Str, path: Str, status: Int, ms: Int) {
  var slow: Bool = ms >= r.slow_ms;
  var line = "{\"method\":\"" + log_safe(method)
    + "\",\"path\":\"" + log_safe(path)
    + "\",\"status\":" + convert.int_to_string(status)
    + ",\"ms\":" + convert.int_to_string(ms)
    + ",\"slow\":" + (if slow { "true" } else { "false" }) + "}";
  r.lines.push(line);
  while r.lines.len() > r.capacity {
    var i: Int = 0;
    while i < r.lines.len() - 1 {
      r.lines[i] = r.lines[i + 1];
      i = i + 1;
    }
    r.lines.pop();
    r.dropped = r.dropped + 1;
  }
}
