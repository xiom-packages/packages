// XIOM -- xiom.metrics: counters, gauges, and histograms for in-process metrics
// Port task: replace the xiom.metrics placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure deterministic value types: no clock access, no I/O, no FFI. The 0.2.0
// layer adds labeled metrics (MetricLabels -- parallel Vec[Str] name/value
// pairs, never tuples), an insertion-ordered Registry of labeled entries,
// and Prometheus text exposition version 0.0.4. Free functions only.
// Histograms use the classic cumulative-bucket shape:
// `counts` has bounds.len() + 1 entries, bucket i counts observations
// v <= bounds[i] that no earlier bucket took, and the final bucket counts
// everything above the last bound (the +Inf bucket). The caller is
// responsible for passing ascending bounds (see README Limitations).

module xiom.metrics

use xiom.string;
use xiom.string.builder;

/// Monotonic process-local counter.
///
/// `value` is an internal implementation detail; construct through
/// metric_counter_new and read through metric_counter_value.
pub type Counter = {
  value: Int;
}

/// Create a counter at zero. No error path. Complexity: O(1).
pub fn metric_counter_new() -> Counter {
  return Counter{ value: 0; };
}

/// Current counter value. Complexity: O(1).
pub fn metric_counter_value(c: &Counter) -> Int {
  return c.value;
}

/// Increment the counter by 1. Complexity: O(1).
pub fn metric_counter_inc(c: &mut Counter)
  ensures: c.value == c.value@pre + 1;
{
  c.value = c.value + 1;
}

/// Add `delta` to the counter; negative deltas subtract.
/// Complexity: O(1).
pub fn metric_counter_add(c: &mut Counter, delta: Int)
  ensures: c.value == c.value@pre + delta;
{
  c.value = c.value + delta;
}

/// Reset the counter to zero. Complexity: O(1).
pub fn metric_counter_reset(c: &mut Counter)
  ensures: c.value == 0;
{
  c.value = 0;
}

/// Point-in-time integer gauge.
///
/// `value` is an internal implementation detail; construct through
/// metric_gauge_new and read through metric_gauge_value.
pub type Gauge = {
  value: Int;
}

/// Create a gauge holding `initial`. No clamping, no error path.
/// Complexity: O(1).
pub fn metric_gauge_new(initial: Int) -> Gauge {
  return Gauge{ value: initial; };
}

/// Current gauge value. Complexity: O(1).
pub fn metric_gauge_value(g: &Gauge) -> Int {
  return g.value;
}

/// Set the gauge to `v`. Complexity: O(1).
pub fn metric_gauge_set(g: &mut Gauge, v: Int)
  ensures: g.value == v;
{
  g.value = v;
}

/// Add `delta` to the gauge; negative deltas subtract.
/// Complexity: O(1).
pub fn metric_gauge_add(g: &mut Gauge, delta: Int)
  ensures: g.value == g.value@pre + delta;
{
  g.value = g.value + delta;
}

/// Integer histogram with caller-supplied cumulative bucket bounds.
///
/// Every field is an internal implementation detail; callers must go through
/// the free functions below. `bounds` is a private copy of the bounds passed
/// to metric_histogram_new (used as given, ascending assumed); `counts` has
/// bounds.len() + 1 entries: bucket i counts observations v <= bounds[i] that
/// no earlier bucket took, and the last bucket counts v > last bound (the
/// +Inf bucket). `count` is the total observations, `sum` their arithmetic
/// sum, and `min`/`max` the extremes (both 0 while `count` is 0).
pub type Histogram = {
  bounds: Vec[Int];
  counts: Vec[Int];
  count: Int;
  sum: Int;
  min: Int;
  max: Int;
}

/// Create an empty histogram over `bounds`.
/// Params: bounds - cumulative bucket upper bounds, used as given (the caller
///         must pass them sorted ascending for meaningful buckets).
/// Returns: a histogram with bounds.len() + 1 zeroed buckets and zeroed
/// statistics. The bounds are copied, so later changes to the caller's Vec
/// do not affect the histogram. No error path. Complexity: O(n) in bounds.
pub fn metric_histogram_new(bounds: &Vec[Int]) -> Histogram {
  var copied = Vec[Int].new();
  var i = 0;
  while i < bounds.len() {
    let b: Int = bounds[i];
    copied.push(b);
    i = i + 1;
  }
  var counts = Vec[Int].new();
  var j = 0;
  while j <= copied.len() {
    counts.push(0);
    j = j + 1;
  }
  return Histogram{ bounds: copied; counts: counts; count: 0; sum: 0; min: 0; max: 0; };
}

/// Record one observation `v`.
/// Updates count, sum, min and max (min and max start at the first observed
/// value) and increments exactly one bucket: the first bucket i with
/// v <= bounds[i], or the final bucket when v exceeds every bound.
/// Complexity: O(n) in bounds (first-fit scan).
pub fn metric_histogram_observe(h: &mut Histogram, v: Int)
  ensures: h.count == h.count@pre + 1;
  ensures: h.sum == h.sum@pre + v;
  ensures: h.min <= h.max;
{
  if h.count == 0 {
    h.min = v;
    h.max = v;
  } else {
    if v < h.min { h.min = v; }
    if v > h.max { h.max = v; }
  }
  h.count = h.count + 1;
  h.sum = h.sum + v;
  var idx = h.bounds.len();
  var i = 0;
  while i < h.bounds.len() {
    let b: Int = h.bounds[i];
    if v <= b {
      idx = i;
      break;
    }
    i = i + 1;
  }
  h.counts[idx] = h.counts[idx] + 1;
}

/// Observation count in bucket `index`.
/// Params: h - the histogram; index - bucket index.
/// Returns: the bucket count, or 0 when `index` is negative or beyond the
/// last bucket. No error path. Complexity: O(1).
pub fn metric_histogram_bucket_count(h: &Histogram, index: Int) -> Int
  ensures: result >= 0;
{
  if index < 0 { return 0; }
  if index >= h.counts.len() { return 0; }
  let got: Int = h.counts[index];
  return got;
}

/// Number of buckets (always bounds.len() + 1, at least 1).
/// Complexity: O(1).
pub fn metric_histogram_bucket_len(h: &Histogram) -> Int
  ensures: result >= 1;
{
  return h.counts.len();
}

/// Total observations recorded. Complexity: O(1).
pub fn metric_histogram_count(h: &Histogram) -> Int
  ensures: result >= 0;
{
  return h.count;
}

/// Arithmetic sum of all observed values. Complexity: O(1).
pub fn metric_histogram_sum(h: &Histogram) -> Int {
  return h.sum;
}

/// Smallest observed value, or 0 when the histogram is empty.
/// Complexity: O(1).
pub fn metric_histogram_min(h: &Histogram) -> Int {
  return h.min;
}

/// Largest observed value, or 0 when the histogram is empty.
/// Complexity: O(1).
pub fn metric_histogram_max(h: &Histogram) -> Int {
  return h.max;
}

/// Integer mean sum/count (floor), or 0 when the histogram is empty.
/// Complexity: O(1).
pub fn metric_histogram_mean(h: &Histogram) -> Int {
  if h.count == 0 { return 0; }
  return h.sum / h.count;
}

/// Drop every observation: zeroes all buckets and count/sum/min/max, and
/// keeps the bounds (bucket layout is unchanged, so the histogram can be
/// reused). Complexity: O(n) in buckets.
pub fn metric_histogram_reset(h: &mut Histogram)
  ensures: h.count == 0 && h.sum == 0 && h.min == 0 && h.max == 0;
{
  var i = 0;
  while i < h.counts.len() {
    h.counts[i] = 0;
    i = i + 1;
  }
  h.count = 0;
  h.sum = 0;
  h.min = 0;
  h.max = 0;
}

// ---------------------------------------------------------------------------
// 0.2.0: labels, registry, Prometheus text exposition
// ---------------------------------------------------------------------------

/// Ordered set of name/value label pairs.
///
/// Pairs are stored as two parallel vectors of equal length: index i pairs
/// names[i] with values[i]. Insertion order is preserved and is the order
/// used by the text exposition. Every field is an internal implementation
/// detail; build through metric_labels_new / metric_labels_add and read
/// through the accessors below.
pub type MetricLabels = {
  names: Vec[Str];
  values: Vec[Str];
}

/// Create an empty label set. No error path. Complexity: O(1).
pub fn metric_labels_new() -> MetricLabels {
  return MetricLabels{ names: Vec[Str].new(); values: Vec[Str].new(); };
}

/// Append the pair (`name`, `value`) to the label set, preserving order.
/// Names and values are stored verbatim: no validation and no
/// de-duplication. Complexity: O(1) amortized.
pub fn metric_labels_add(l: &mut MetricLabels, name: Str, value: Str) {
  l.names.push(name);
  l.values.push(value);
}

/// Number of label pairs. Complexity: O(1).
pub fn metric_labels_len(l: &MetricLabels) -> Int {
  return l.names.len();
}

/// Label name at index `i`.
/// Returns: Ok(name) for 0 <= i < metric_labels_len(l), else
/// Err("metrics: label index out of range"). Complexity: O(1).
pub fn metric_labels_name(l: &MetricLabels, i: Int) -> Result[Str, Str] {
  if i < 0 { return Err("metrics: label index out of range"); }
  if i >= l.names.len() { return Err("metrics: label index out of range"); }
  return Ok(l.names[i]);
}

/// Label value at index `i`.
/// Returns: Ok(value) for 0 <= i < metric_labels_len(l), else
/// Err("metrics: label index out of range"). Complexity: O(1).
pub fn metric_labels_value(l: &MetricLabels, i: Int) -> Result[Str, Str] {
  if i < 0 { return Err("metrics: label index out of range"); }
  if i >= l.values.len() { return Err("metrics: label index out of range"); }
  return Ok(l.values[i]);
}

// Occurrences of the exact pair (`name`, `value`) in `l`. Complexity: O(n).
fn _metric_label_pair_count(l: &MetricLabels, name: Str, value: Str) -> Int {
  var count = 0;
  var i = 0;
  while i < l.names.len() {
    let ln: Str = l.names[i];
    if string.str_compare(ln, name) == 0 {
      let lv: Str = l.values[i];
      if string.str_compare(lv, value) == 0 {
        count = count + 1;
      }
    }
    i = i + 1;
  }
  return count;
}

/// True when `a` and `b` hold the same multiset of pairs, ignoring order.
/// Duplicates are compared as counts: a pair repeated twice in `a` needs
/// two copies in `b`. Str equality goes through xiom.string.str_compare,
/// never `==`. Complexity: O(n^2) in the pair count.
pub fn metric_labels_equal(a: &MetricLabels, b: &MetricLabels) -> Bool {
  if a.names.len() != b.names.len() { return false; }
  var i = 0;
  while i < a.names.len() {
    let n: Str = a.names[i];
    let v: Str = a.values[i];
    let ca = _metric_label_pair_count(a, n, v);
    let cb = _metric_label_pair_count(b, n, v);
    if ca != cb { return false; }
    i = i + 1;
  }
  return true;
}

/// One registry slot: a metric identified by `name` + `labels`.
///
/// `kind` selects which value field is meaningful: 0 = counter (`c`),
/// 1 = gauge (`g`), 2 = histogram (`h`). The other value fields are still
/// initialized (zeroed) so every entry is fully formed, but only the field
/// matching `kind` may be read through the labeled functions. Every field
/// is an internal implementation detail.
pub type MetricEntry = {
  name: Str;
  labels: MetricLabels;
  kind: Int;
  c: Counter;
  g: Gauge;
  h: Histogram;
}

/// Insertion-ordered collection of labeled entries. One entry per distinct
/// (name, labels) pair; `entries` is an internal implementation detail.
pub type Registry = {
  entries: Vec[MetricEntry];
}

/// Create an empty registry. No error path. Complexity: O(1).
pub fn metric_registry_new() -> Registry {
  return Registry{ entries: Vec[MetricEntry].new(); };
}

/// Number of registered entries. Complexity: O(1).
pub fn metric_registry_count(r: &Registry) -> Int {
  return r.entries.len();
}

/// Index of the entry with exactly `name` and a label set equal to `labels`
/// (order-insensitive, see metric_labels_equal), or -1 when absent. The
/// first matching entry in insertion order wins. Complexity: O(n*m) for n
/// entries with m labels each.
pub fn metric_registry_find(r: &Registry, name: Str, labels: &MetricLabels) -> Int {
  var i = 0;
  while i < r.entries.len() {
    if string.str_compare(r.entries[i].name, name) == 0 {
      if metric_labels_equal(&r.entries[i].labels, labels) {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// Fresh empty histogram over no bounds (one +Inf bucket), used to fill the
// value fields that do not match an entry's kind. Complexity: O(1).
fn _metric_empty_histogram() -> Histogram {
  var bounds = Vec[Int].new();
  return metric_histogram_new(&bounds);
}

/// Get-or-create the counter entry (`name`, `labels`) and add `delta`.
/// A new entry is created at the end of the registry (kind 0, at zero) and
/// then incremented; an existing entry is updated in place. Negative deltas
/// subtract, as in metric_counter_add.
/// Returns: the entry index, >= 0. Complexity: O(n*m) find + O(1) update.
pub fn metric_counter_inc_labeled(r: &mut Registry, name: Str, labels: MetricLabels, delta: Int) -> Int {
  let at = metric_registry_find(r, name, &labels);
  if at >= 0 {
    var c = r.entries[at].c;
    metric_counter_add(&mut c, delta);
    r.entries[at].c = c;
    return at;
  }
  var fresh = metric_counter_new();
  metric_counter_add(&mut fresh, delta);
  r.entries.push(MetricEntry{ name: name; labels: labels; kind: 0; c: fresh; g: metric_gauge_new(0); h: _metric_empty_histogram(); });
  return r.entries.len() - 1;
}

/// Get-or-create the gauge entry (`name`, `labels`) and set it to `value`.
/// A new entry is created at the end of the registry holding `value`
/// (kind 1); an existing entry is overwritten in place.
/// Returns: the entry index, >= 0. Complexity: O(n*m) find + O(1) update.
pub fn metric_gauge_set_labeled(r: &mut Registry, name: Str, labels: MetricLabels, value: Int) -> Int {
  let at = metric_registry_find(r, name, &labels);
  if at >= 0 {
    var g = r.entries[at].g;
    metric_gauge_set(&mut g, value);
    r.entries[at].g = g;
    return at;
  }
  r.entries.push(MetricEntry{ name: name; labels: labels; kind: 1; c: metric_counter_new(); g: metric_gauge_new(value); h: _metric_empty_histogram(); });
  return r.entries.len() - 1;
}

/// Get-or-create the histogram entry (`name`, `labels`) and record one
/// observation `v`. A new entry is created at the end of the registry over
/// a copy of `bounds` (kind 2); an existing entry observes with the bounds
/// it stored on creation, ignoring the `bounds` argument (so every sample
/// of one series shares the first call's bucket layout).
/// Returns: the entry index, >= 0. Complexity: O(n*m) find + O(k) observe.
pub fn metric_histogram_observe_labeled(r: &mut Registry, name: Str, labels: MetricLabels, bounds: &Vec[Int], v: Int) -> Int {
  let at = metric_registry_find(r, name, &labels);
  if at >= 0 {
    var h = r.entries[at].h;
    metric_histogram_observe(&mut h, v);
    r.entries[at].h = h;
    return at;
  }
  var fresh = metric_histogram_new(bounds);
  metric_histogram_observe(&mut fresh, v);
  r.entries.push(MetricEntry{ name: name; labels: labels; kind: 2; c: metric_counter_new(); g: metric_gauge_new(0); h: fresh; });
  return r.entries.len() - 1;
}

/// Drop every entry; the registry becomes empty and immediately reusable.
/// Complexity: O(1) (drops the backing vector).
pub fn metric_registry_reset(r: &mut Registry) {
  r.entries = Vec[MetricEntry].new();
}

// Append one metric label pair `name="escaped value"` (no braces, no
// separator). Complexity: O(name + value).
fn _metric_exposition_label_pair(sb: &mut Vec[UInt8], l: &MetricLabels, i: Int) {
  let n: Str = l.names[i];
  let v: Str = l.values[i];
  builder.sb_push_str(sb, n);
  builder.sb_push_str(sb, "=\"");
  _metric_exposition_escape(sb, v);
  builder.sb_push_str(sb, "\"");
}

// Append `{...}` for the metric labels; nothing when there are none.
// Complexity: O(labels).
fn _metric_exposition_labels(sb: &mut Vec[UInt8], l: &MetricLabels) {
  if l.names.len() == 0 { return; }
  builder.sb_push_str(sb, "{");
  var i = 0;
  while i < l.names.len() {
    if i > 0 { builder.sb_push_str(sb, ","); }
    _metric_exposition_label_pair(sb, l, i);
    i = i + 1;
  }
  builder.sb_push_str(sb, "}");
}

// Append `{` plus every metric label pair plus a trailing comma, leaving
// the bucket line ready for `le="..."}`. Complexity: O(labels).
fn _metric_exposition_bucket_open(sb: &mut Vec[UInt8], l: &MetricLabels) {
  builder.sb_push_str(sb, "{");
  var i = 0;
  while i < l.names.len() {
    _metric_exposition_label_pair(sb, l, i);
    builder.sb_push_str(sb, ",");
    i = i + 1;
  }
}

// Append `v` to `sb`, escaping for the Prometheus text format: backslash ->
// `\\`, double quote -> `\"`, LF -> `\n` (other bytes are copied verbatim).
// Complexity: O(v.len()).
fn _metric_exposition_escape(sb: &mut Vec[UInt8], v: Str) {
  var i = 0;
  while i < v.len() {
    let b: Int = (string.byte_at(v, i) as Int) & 0xFF;
    if b == 92 {
      builder.sb_push_str(sb, "\\\\");
    } else if b == 34 {
      builder.sb_push_str(sb, "\\\"");
    } else if b == 10 {
      builder.sb_push_str(sb, "\\n");
    } else {
      builder.sb_push_byte(sb, b as UInt8);
    }
    i = i + 1;
  }
}

// Append `# TYPE <name> counter` and the counter sample line.
// Complexity: O(name + labels).
fn _metric_exposition_counter(sb: &mut Vec[UInt8], e: &MetricEntry) {
  builder.sb_push_str(sb, "# TYPE ");
  builder.sb_push_str(sb, e.name);
  builder.sb_push_str(sb, " counter\n");
  builder.sb_push_str(sb, e.name);
  _metric_exposition_labels(sb, &e.labels);
  builder.sb_push_str(sb, " ");
  builder.sb_push_int(sb, metric_counter_value(&e.c));
  builder.sb_push_str(sb, "\n");
}

// Append `# TYPE <name> gauge` and the gauge sample line.
// Complexity: O(name + labels).
fn _metric_exposition_gauge(sb: &mut Vec[UInt8], e: &MetricEntry) {
  builder.sb_push_str(sb, "# TYPE ");
  builder.sb_push_str(sb, e.name);
  builder.sb_push_str(sb, " gauge\n");
  builder.sb_push_str(sb, e.name);
  _metric_exposition_labels(sb, &e.labels);
  builder.sb_push_str(sb, " ");
  builder.sb_push_int(sb, metric_gauge_value(&e.g));
  builder.sb_push_str(sb, "\n");
}

// Append `# TYPE <name> histogram`, the cumulative bucket lines (one per
// stored bound, plus the +Inf bucket holding the total count), and the
// `_sum` / `_count` lines. Metric labels come first, then `le`.
// Complexity: O(name + labels * bounds).
fn _metric_exposition_histogram(sb: &mut Vec[UInt8], e: &MetricEntry) {
  builder.sb_push_str(sb, "# TYPE ");
  builder.sb_push_str(sb, e.name);
  builder.sb_push_str(sb, " histogram\n");
  var cum = 0;
  var b = 0;
  while b < e.h.bounds.len() {
    let bound: Int = e.h.bounds[b];
    cum = cum + metric_histogram_bucket_count(&e.h, b);
    builder.sb_push_str(sb, e.name);
    builder.sb_push_str(sb, "_bucket");
    _metric_exposition_bucket_open(sb, &e.labels);
    builder.sb_push_str(sb, "le=\"");
    builder.sb_push_int(sb, bound);
    builder.sb_push_str(sb, "\"} ");
    builder.sb_push_int(sb, cum);
    builder.sb_push_str(sb, "\n");
    b = b + 1;
  }
  builder.sb_push_str(sb, e.name);
  builder.sb_push_str(sb, "_bucket");
  _metric_exposition_bucket_open(sb, &e.labels);
  builder.sb_push_str(sb, "le=\"+Inf\"} ");
  builder.sb_push_int(sb, metric_histogram_count(&e.h));
  builder.sb_push_str(sb, "\n");
  builder.sb_push_str(sb, e.name);
  builder.sb_push_str(sb, "_sum");
  _metric_exposition_labels(sb, &e.labels);
  builder.sb_push_str(sb, " ");
  builder.sb_push_int(sb, metric_histogram_sum(&e.h));
  builder.sb_push_str(sb, "\n");
  builder.sb_push_str(sb, e.name);
  builder.sb_push_str(sb, "_count");
  _metric_exposition_labels(sb, &e.labels);
  builder.sb_push_str(sb, " ");
  builder.sb_push_int(sb, metric_histogram_count(&e.h));
  builder.sb_push_str(sb, "\n");
}

// Dispatch one registry entry to its kind-specific renderer.
fn _metric_exposition_entry(sb: &mut Vec[UInt8], e: &MetricEntry) {
  if e.kind == 0 {
    _metric_exposition_counter(sb, e);
  } else if e.kind == 1 {
    _metric_exposition_gauge(sb, e);
  } else {
    _metric_exposition_histogram(sb, e);
  }
}

/// Render the registry as Prometheus text exposition format 0.0.4.
///
/// Entries are emitted in insertion order, each as its `# TYPE` line
/// followed by its samples:
/// - counter / gauge: `<name>` with the current value;
/// - histogram: cumulative `<name>_bucket{le="<bound>"}` lines for every
///   stored bound (bucket `le` counts observations <= that bound), a final
///   `le="+Inf"` line holding the total count, then `<name>_sum` and
///   `<name>_count`.
/// Metric labels precede `le` inside the braces; braces are omitted when an
/// entry has no labels (bucket lines always show `le`). Label values are
/// escaped per the text format: `\` -> `\\`, `"` -> `\"`, LF -> `\n`.
/// Returns: the exposition text, "" for an empty registry.
/// Complexity: O(total rendered size).
pub fn metric_exposition(r: &Registry) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  while i < r.entries.len() {
    _metric_exposition_entry(&mut sb, &r.entries[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

/// MIME content type of metric_exposition output.
/// Complexity: O(1).
pub fn metric_content_type() -> Str {
  return "text/plain; version=0.0.4; charset=utf-8";
}

/// Recommended PULSE latency histogram bounds in milliseconds:
/// [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]. A fresh Vec per
/// call; pass it to metric_histogram_new or
/// metric_histogram_observe_labeled so services agree on one bucket layout.
/// Complexity: O(1) (11 pushes).
pub fn metric_latency_bounds_ms() -> Vec[Int] {
  var bounds = Vec[Int].new();
  bounds.push(1);
  bounds.push(5);
  bounds.push(10);
  bounds.push(25);
  bounds.push(50);
  bounds.push(100);
  bounds.push(250);
  bounds.push(500);
  bounds.push(1000);
  bounds.push(2500);
  bounds.push(5000);
  return bounds;
}
