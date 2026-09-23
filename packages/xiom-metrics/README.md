# xiom.metrics

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** in-process counters, gauges, and integer histograms as plain
> value types with no registry, exporter, or background collection.
> **Deps:** none (the library imports nothing; tests use `xiom.std` modules).

## What it is

`xiom.metrics` is a small, pure-XIOM instrumentation toolkit. A `Counter` is
a monotonic-in-practice running total, a `Gauge` is a point-in-time value,
and a `Histogram` is the classic cumulative-bucket distribution over
caller-supplied bounds (the shape behind Prometheus-style bucket series,
without the registry or text format). All three are plain value types that
the caller owns: create them locally, mutate through `&mut`, read through
`&`. There is no clock access, no I/O, no FFI, and no global state.

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

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.metrics
```

Expected: the namespaced module passes the section-4 namespace rule, 23
`[PASS]` lines, and a final `port: PASS (passed=23 failed=0 program_exit=0
exit=0)`.

## Limitations

- In-process only: values live in the caller's variables. There is no
  registry, no global collector, and no export format (no text/JSON/OTLP
  encoding).
- Bounds must be sorted ascending by the caller; `metric_histogram_new`
  copies and uses them as given, so an unsorted Vec yields first-fit
  bucket assignment over that order rather than an error.
- `Int` observations and statistics only; no floats, no labels/dimensions,
  no timers, no percentile estimation.
- `min` and `max` are 0 when the histogram is empty (0 is also a legitimate
  observation, so read `metric_histogram_count` first when it matters).
- Not thread-safe; the types are plain values with no internal locking.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
