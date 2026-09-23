# xiom.metrics -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.metrics` (`src/metrics.xi`). Manifest: `package.xi` (name
`xiom.metrics`, version `0.1.0`). Depends on `xiom.std` for the manifest only;
the library module imports nothing.

## Scope

In-process integer instrumentation over three plain value types:

- `Counter`: an accumulating running total with increment, add (including
  negative deltas), and reset;
- `Gauge`: a point-in-time value with set and add;
- `Histogram`: cumulative integer buckets over caller-supplied bounds plus
  count, sum, min, max and mean statistics.

Pure and deterministic: no clock access, no I/O, no allocator use beyond the
two bucket vectors, no FFI, no global state, no locking.

## Non-goals

- Metrics registry, collector loop, or scrape/export formats (text, JSON,
  OTLP, StatsD).
- Labels/dimensions, metric names, or aggregation across instances.
- Floats, timers, rate computation, reservoir sampling, or percentile
  estimation (the histogram exposes raw bucket counts).
- Thread safety or atomic operations.

## API signatures

All functions are free functions in module `xiom.metrics`:

```xi
pub type Counter = { value: Int; }
pub fn metric_counter_new() -> Counter
pub fn metric_counter_value(c: &Counter) -> Int
pub fn metric_counter_inc(c: &mut Counter)
pub fn metric_counter_add(c: &mut Counter, delta: Int)
pub fn metric_counter_reset(c: &mut Counter)

pub type Gauge = { value: Int; }
pub fn metric_gauge_new(initial: Int) -> Gauge
pub fn metric_gauge_value(g: &Gauge) -> Int
pub fn metric_gauge_set(g: &mut Gauge, v: Int)
pub fn metric_gauge_add(g: &mut Gauge, delta: Int)

pub type Histogram = {
  bounds: Vec[Int];
  counts: Vec[Int];
  count: Int;
  sum: Int;
  min: Int;
  max: Int;
}
pub fn metric_histogram_new(bounds: &Vec[Int]) -> Histogram
pub fn metric_histogram_observe(h: &mut Histogram, v: Int)
pub fn metric_histogram_bucket_count(h: &Histogram, index: Int) -> Int
pub fn metric_histogram_bucket_len(h: &Histogram) -> Int
pub fn metric_histogram_count(h: &Histogram) -> Int
pub fn metric_histogram_sum(h: &Histogram) -> Int
pub fn metric_histogram_min(h: &Histogram) -> Int
pub fn metric_histogram_max(h: &Histogram) -> Int
pub fn metric_histogram_mean(h: &Histogram) -> Int
pub fn metric_histogram_reset(h: &mut Histogram)
```

Every struct field is an internal implementation detail; callers must go
through the free functions.

## Representation

- `Counter` and `Gauge` hold one `Int`.
- `Histogram.bounds` is a private copy of the bounds passed to
  `metric_histogram_new`, used as given.
- `Histogram.counts` has `bounds.len() + 1` entries, all zero at
  construction. `counts.len() >= 1` always.
- `Histogram.count` / `sum` are totals; `min` / `max` hold the observed
  extremes and are 0 exactly while `count == 0`.

## Bucket rules

Let `bounds = [b0, b1, ..., b(n-1)]` (ascending as required of the caller)
and `counts = [c0, ..., c(n-1), cInf]`.

- Observation `v` goes to the first bucket `i` with `v <= b(i)`.
- If `v > b(n-1)` (or the bound list is empty) it goes to the final bucket
  `index n` (`counts.len() - 1`), the `+Inf` bucket.
- With reference Prometheus semantics this is a cumulative `le` layout:
  bucket `i` counts observations that are `<= b(i)` and were not counted by
  an earlier bucket.
- Bounds are not validated or sorted: duplicates make an earlier bucket
  win, unsorted bounds produce first-fit assignment in the given order.
  The caller owns ascending order.
- `metric_histogram_bucket_count` returns 0 for `index < 0` or
  `index >= counts.len()`; no error channel.

## Semantics

`metric_counter_new()` / `metric_gauge_new(initial)`
: Fresh value type; no clamping, no error path.

`metric_counter_inc(c)`, `metric_counter_add(c, delta)`
: `value += 1` / `value += delta`. Negative deltas are allowed, so the
  counter can go negative despite its monotonic intent.

`metric_counter_reset(c)`, `metric_gauge_set(g, v)`
: Overwrite to 0 / `v`. `metric_gauge_add(g, delta)` = `value += delta`.

`metric_histogram_new(bounds)`
: Copies `bounds` (later mutations of the caller's Vec do not affect the
  histogram), allocates `bounds.len() + 1` zeroed bucket counters, and
  zeroes count/sum/min/max. O(n) in bounds.

`metric_histogram_observe(h, v)`
: If `count == 0`, `min = max = v`; otherwise `min = min(min, v)` and
  `max = max(max, v)`. Then `count += 1`, `sum += v`, and one bucket is
  incremented per the bucket rules. O(n) in bounds (first-fit scan).

`metric_histogram_bucket_count(h, index)`
: Bucket count, or 0 when out of range.

`metric_histogram_count/sum/min/max`
: Totals and extremes; `min`/`max` are 0 when empty.

`metric_histogram_mean(h)`
: 0 when empty, else `sum / count` as integer division (floor for
  non-negative sums; XIOM integer division truncates).

`metric_histogram_reset(h)`
: Zeroes every bucket and count/sum/min/max; bounds and bucket layout are
  preserved so the histogram is immediately reusable.

Error paths: none. There is no panicking input; out-of-range bucket reads
return 0 and every other operation is total.

## Complexity

| Operation | Complexity |
|---|---|
| `metric_counter_*` / `metric_gauge_*` | O(1) |
| `metric_histogram_new` | O(n) in bounds |
| `metric_histogram_observe` | O(n) in bounds |
| `metric_histogram_bucket_count` / `bucket_len` / `count` / `sum` / `min` / `max` / `mean` | O(1) |
| `metric_histogram_reset` | O(bucket count) |

## Test plan

`tests/test_conformance.xi` (`module metrics_tests`, 23 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count):

1. counter starts at zero;
2. `metric_counter_inc` adds one per call;
3. `metric_counter_add` accumulates positive deltas;
4. `metric_counter_add` accepts negative deltas;
5. `metric_counter_reset` zeroes the counter;
6. `metric_gauge_new` holds the initial value;
7. `metric_gauge_set` replaces the value;
8. `metric_gauge_add` accumulates positive and negative deltas;
9. `bucket_len == bounds.len() + 1` for 3, 1 and 0 bounds;
10. observations exactly at a bound land in that bucket;
11. values between bounds land in the first fitting bucket;
12. values above the last bound fill the overflow bucket;
13. repeated values accumulate in one bucket;
14. negative observations count and track extremes;
15. count and sum track every observation;
16. min and max track the observed extremes;
17. mean is integer `sum / count` (floor);
18. empty histogram reports zeroed statistics;
19. empty bounds give one all-catching bucket;
20. reset zeroes observations and keeps bounds, then reuse works;
21. out-of-range bucket index returns 0;
22. 1000 observations stay consistent across buckets;
23. `metric_histogram_new` copies the caller's bounds.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.metrics
```

Last verified: compiler 0.61.3, `port: PASS (passed=23 failed=0
program_exit=0 exit=0)`.

## Known limitations

- In-process only: no registry, no collector, no export format.
- Bounds must be sorted ascending by the caller; unsorted input is not an
  error but yields first-fit assignment over the given order.
- `Int` observations only: no floats, no units, no labels.
- `min`/`max` read as 0 when empty; that is indistinguishable from a lone 0
  observation without also reading `count`.
- Not thread-safe.
- `metric_histogram_observe` is O(bounds) because it scans for the first
  fitting bound; a hot path should keep the bound list short or widen
  buckets.

## Compiler / stdlib notes for v0.61.3

- Free functions only (no methods) and explicit `&`/`&mut` parameters.
- Read-only calls in the tests are routed through tiny helpers taking
  `&mut` so that a `&local` call is never followed by a `&mut local` call
  in the same function body (advisory E001).
- No `Vec[StructType]` is used: the histogram keeps parallel `Vec[Int]`
  arenas, which the language supports.
- Vec element reads go through typed `let` (`let b: Int = h.bounds[i];`) to
  keep inference unambiguous.
- `use xiom.metrics;` plus `xiom.test.assert` / `xiom.io.println` in the
  suite, matching the sibling packages' test style.
