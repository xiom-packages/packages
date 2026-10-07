# xiom.metrics

> **Status:** `stable` -- conformance-tested (40/40); published at `v0.1.2` on the XIOM registry
> (the 0.2.0 labels/registry/exposition layer is staged for release).
> **Scope:** in-process counters, gauges, and integer histograms as plain
> value types, plus a labeled registry and Prometheus text exposition.
> **Deps:** `xiom.std` (the library imports `xiom.string` and
> `xiom.string.builder`; tests also use `xiom.test` and `xiom.io`).

## What it is

`xiom.metrics` is a small, pure-XIOM instrumentation toolkit. A `Counter` is
a monotonic-in-practice running total, a `Gauge` is a point-in-time value,
and a `Histogram` is the classic cumulative-bucket distribution over
caller-supplied bounds (the shape behind Prometheus-style bucket series).
The 0.2.0 layer adds labeled metrics (`MetricLabels`), an insertion-ordered
`Registry` with get-or-create lookup by name + labels, and
`metric_exposition`, which renders the registry as Prometheus text format
0.0.4 for a scrape endpoint. All types are plain values that the caller
owns: create them locally, mutate through `&mut`, read through `&`. There
is no clock access, no I/O, no FFI, and no global state.

## API

| Function | Returns | Description |
|---|---|---|
| `metric_counter_new()` | `Counter` | New counter at zero. |
| `metric_counter_value(c)` | `Int` | Current value. |
| `metric_counter_inc(&mut c)` | `Unit` | Adds 1. |
| `metric_counter_add(&mut c, delta)` | `Unit` | Adds `delta` (negative subtracts). |
| `metric_counter_reset(&mut c)` | `Unit` | Sets the value to 0. |
| `metric_gauge_new(initial)` | `Gauge` | New gauge holding `initial`. |
| `metric_gauge_value(g)` | `Int` | Current value. |
| `metric_gauge_set(&mut g, v)` | `Unit` | Replaces the value. |
| `metric_gauge_add(&mut g, delta)` | `Unit` | Adds `delta` (negative subtracts). |
| `metric_histogram_new(&bounds)` | `Histogram` | Empty histogram; copies `bounds`; `bucket_len == bounds.len() + 1`. |
| `metric_histogram_observe(&mut h, v)` | `Unit` | Records `v`; updates count/sum/min/max and one bucket. |
| `metric_histogram_bucket_count(h, index)` | `Int` | Observations in `index`; 0 when out of range. |
| `metric_histogram_bucket_len(h)` | `Int` | Number of buckets (`bounds.len() + 1`). |
| `metric_histogram_count(h)` | `Int` | Total observations. |
| `metric_histogram_sum(h)` | `Int` | Sum of observed values. |
| `metric_histogram_min(h)` | `Int` | Smallest observation, 0 when empty. |
| `metric_histogram_max(h)` | `Int` | Largest observation, 0 when empty. |
| `metric_histogram_mean(h)` | `Int` | `sum / count` integer floor, 0 when empty. |
| `metric_histogram_reset(&mut h)` | `Unit` | Zeroes observations; keeps bounds. |
| `metric_labels_new()` | `MetricLabels` | Empty label set. |
| `metric_labels_add(&mut l, name, value)` | `Unit` | Appends one pair (order preserved, duplicates kept). |
| `metric_labels_len(l)` | `Int` | Number of pairs. |
| `metric_labels_name(l, i)` | `Result[Str, Str]` | `Ok(name)` / `Err` out of range. |
| `metric_labels_value(l, i)` | `Result[Str, Str]` | `Ok(value)` / `Err` out of range. |
| `metric_labels_equal(a, b)` | `Bool` | Order-insensitive multiset equality (duplicates count). |
| `metric_registry_new()` | `Registry` | Empty registry. |
| `metric_registry_count(r)` | `Int` | Number of entries. |
| `metric_registry_find(r, name, &labels)` | `Int` | Entry index, or -1 when absent. |
| `metric_counter_inc_labeled(&mut r, name, labels, delta)` | `Int` | Get-or-create counter, add `delta`, return index. |
| `metric_gauge_set_labeled(&mut r, name, labels, value)` | `Int` | Get-or-create gauge, set `value`, return index. |
| `metric_histogram_observe_labeled(&mut r, name, labels, &bounds, v)` | `Int` | Get-or-create histogram (first-call bounds), observe `v`, return index. |
| `metric_registry_reset(&mut r)` | `Unit` | Drops every entry; registry stays usable. |
| `metric_exposition(r)` | `Str` | Prometheus text exposition 0.0.4 (`""` when empty). |
| `metric_content_type()` | `Str` | `text/plain; version=0.0.4; charset=utf-8`. |
| `metric_latency_bounds_ms()` | `Vec[Int]` | PULSE latency preset `[1,5,10,25,50,100,250,500,1000,2500,5000]`. |

Bucket rule: bucket `i` counts observations `v <= bounds[i]` that no earlier
bucket took, and the final bucket (`index == bounds.len()`, the `+Inf`
bucket) counts every `v` above the last bound.

## Usage

```xi
use xiom.metrics;
use xiom.io;

var requests = metric_counter_new();
metric_counter_inc(&mut requests);
metric_counter_add(&mut requests, 41);        // 42

var inflight = metric_gauge_new(0);
metric_gauge_add(&mut inflight, 3);
metric_gauge_set(&mut inflight, 1);

var bounds = Vec[Int].new();
bounds.push(10);
bounds.push(100);
var latency = metric_histogram_new(&bounds);
metric_histogram_observe(&mut latency, 7);    // bucket 0 (<= 10)
metric_histogram_observe(&mut latency, 50);   // bucket 1 (<= 100)
metric_histogram_observe(&mut latency, 900);  // bucket 2 (+Inf)
io.println(metric_histogram_mean(&latency));  // 319
```

### Status snapshot (0.2.0 layer)

```xi
use xiom.metrics;
use xiom.io;

var labels = metric_labels_new();
metric_labels_add(&mut labels, "route", "/health");
var reg = metric_registry_new();
metric_counter_inc_labeled(&mut reg, "http_requests_total", labels, 1);
io.println(metric_exposition(&reg));  // Prometheus text 0.0.4 scrape body
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.metrics
```

Expected: the namespaced module passes the section-4 namespace rule, 40
`[PASS]` lines, and a final `port: PASS (passed=40 failed=0 program_exit=0
exit=0)`.

## Limitations

- In-process only: values live in the caller's registry or variables.
  There is no collector loop, no background scraping, and no export format
  other than the Prometheus text 0.0.4 body from `metric_exposition`; the
  caller owns the HTTP endpoint, headers and content type.
- Bounds must be sorted ascending by the caller; `metric_histogram_new`
  copies and uses them as given, so an unsorted Vec yields first-fit
  bucket assignment over that order rather than an error. Labeled
  histograms keep the bounds captured on first observation (later bounds
  arguments are ignored for that series).
- `Int` observations and statistics only; no floats, no units, no timers.
  Label values are opaque `Str` (no validation, no escaping on input).
- Labels compare as an order-insensitive multiset, so two entries whose
  labels differ only by order are the same series.
- Registry lookup is a linear scan with an O(n^2) label multiset compare;
  a hot path with thousands of series should shard the registry.
- `metric_exposition` rebuilds the whole string per call -- fine per
  scrape, not per observation. When one metric name spans several entries,
  its `# TYPE` line repeats (output is per entry in insertion order).
- `min` and `max` are 0 when the histogram is empty (0 is also a legitimate
  observation, so read `metric_histogram_count` first when it matters).
- Not thread-safe; the types are plain values with no internal locking.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
