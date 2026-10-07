# xiom.metrics -- Specification

Status: `stable` (published; v0.64.0 fleet sweep green; contract hardening
in 0.1.2; 0.2.0 labels/registry/exposition layer under the same module).
Module: `xiom.metrics` (`src/metrics.xi`). Manifest: `package.xi` (name
`xiom.metrics`, version `0.1.2` -- the 0.2.0 additions are staged for a
coordinator version bump). Depends on `xiom.std`; the library imports
`xiom.string` and `xiom.string.builder`.

## Scope

In-process integer instrumentation over three plain value types, plus a
labeled registry and a Prometheus text exposition:

- `Counter`: an accumulating running total with increment, add (including
  negative deltas), and reset;
- `Gauge`: a point-in-time value with set and add;
- `Histogram`: cumulative integer buckets over caller-supplied bounds plus
  count, sum, min, max and mean statistics;
- `MetricLabels` / `MetricEntry` / `Registry`: label pairs stored as two
  parallel `Vec[Str]` vectors (insertion order preserved), get-or-create
  lookup by exact name + label multiset, and whole-registry reset;
- `metric_exposition`: Prometheus text exposition format version 0.0.4
  (counters, gauges, cumulative histogram buckets, `_sum`, `_count`).

Pure and deterministic: no clock access, no I/O, no FFI, no global state, no
locking. Allocation is limited to the metric value vectors (buckets, label
pairs, registry entries) and the exposition string being built.

## Non-goals

- Collector loop, background scraping, or push gateways.
- Export formats other than Prometheus text 0.0.4: no JSON, OTLP, StatsD,
  or OpenMetrics content negotiation.
- Floats, timers, rate computation, reservoir sampling, or percentile
  estimation (the histogram exposes raw bucket counts).
- Metric-name/label-name validation, aggregation across instances, or
  per-entry deletion (only whole-registry reset).
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

pub type MetricLabels = { names: Vec[Str]; values: Vec[Str]; }
pub fn metric_labels_new() -> MetricLabels
pub fn metric_labels_add(l: &mut MetricLabels, name: Str, value: Str)
pub fn metric_labels_len(l: &MetricLabels) -> Int
pub fn metric_labels_name(l: &MetricLabels, i: Int) -> Result[Str, Str]
pub fn metric_labels_value(l: &MetricLabels, i: Int) -> Result[Str, Str]
pub fn metric_labels_equal(a: &MetricLabels, b: &MetricLabels) -> Bool

pub type MetricEntry = {
  name: Str;
  labels: MetricLabels;
  kind: Int;
  c: Counter;
  g: Gauge;
  h: Histogram;
}
pub type Registry = { entries: Vec[MetricEntry]; }
pub fn metric_registry_new() -> Registry
pub fn metric_registry_count(r: &Registry) -> Int
pub fn metric_registry_find(r: &Registry, name: Str, labels: &MetricLabels) -> Int
pub fn metric_counter_inc_labeled(r: &mut Registry, name: Str, labels: MetricLabels, delta: Int) -> Int
pub fn metric_gauge_set_labeled(r: &mut Registry, name: Str, labels: MetricLabels, value: Int) -> Int
pub fn metric_histogram_observe_labeled(r: &mut Registry, name: Str, labels: MetricLabels, bounds: &Vec[Int], v: Int) -> Int
pub fn metric_registry_reset(r: &mut Registry)

pub fn metric_exposition(r: &Registry) -> Str
pub fn metric_content_type() -> Str
pub fn metric_latency_bounds_ms() -> Vec[Int]
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
- `MetricLabels.names` / `values` are two parallel `Vec[Str]` vectors of
  equal length; index i pairs `names[i]` with `values[i]`. Insertion order
  is preserved and is the order used by the exposition.
- `MetricEntry.kind` is 0 (counter), 1 (gauge) or 2 (histogram); only the
  matching `c` / `g` / `h` field is meaningful. The other value fields are
  still initialized (a zeroed counter/gauge and an empty one-bucket
  histogram) so every entry is fully formed.
- `Registry.entries` is a `Vec[MetricEntry]` in insertion order: one entry
  per distinct (name, label-multiset) pair.

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

## Labels

`MetricLabels` is an ordered list of name/value pairs stored as two
parallel vectors (never tuples; see the compiler notes). The API is:

- `metric_labels_new()`: empty label set.
- `metric_labels_add(l, name, value)`: appends one pair; duplicates are
  allowed and kept verbatim (no validation, no de-duplication).
- `metric_labels_len(l)`: pair count.
- `metric_labels_name(l, i)` / `metric_labels_value(l, i)`: `Ok` at
  `0 <= i < metric_labels_len(l)`, otherwise
  `Err("metrics: label index out of range")`.
- `metric_labels_equal(a, b)`: order-insensitive multiset equality. Two
  label sets are equal when every pair of `a` occurs exactly as many times
  in `b` as in `a`; duplicate pairs are compared as counts, so
  `[x=A, x=A]` equals another `[x=A, x=A]` but not `[x=A]`. String
  equality goes through `xiom.string.str_compare`, never `==`.

## Registry

`Registry` owns the labeled entries; entries are created on first use and
are never removed individually:

- `metric_counter_inc_labeled(r, name, labels, delta)`: finds the entry
  with exactly `name` and an equal label multiset; on a hit it calls
  `metric_counter_add` on the stored counter, otherwise it pushes a new
  kind-0 entry at zero and adds `delta` to it. Returns the entry index.
- `metric_gauge_set_labeled(r, name, labels, value)`: same lookup; on a
  hit it sets the stored gauge to `value`, otherwise it pushes a new
  kind-1 entry already holding `value`. Returns the entry index.
- `metric_histogram_observe_labeled(r, name, labels, bounds, v)`: same
  lookup; on a hit it records `v` into the stored histogram with the
  bounds captured on first creation and ignores the `bounds` argument,
  otherwise it pushes a new kind-2 entry over a copy of `bounds` and
  records `v` into it. Returns the entry index.
- `metric_registry_count(r)`: number of entries.
- `metric_registry_find(r, name, labels)`: index of the first matching
  entry in insertion order, or -1 when absent.
- `metric_registry_reset(r)`: drops every entry (O(1)); the registry is
  immediately reusable.

Lookup is one linear scan; `metric_registry_find` is also exported for
callers that want the index before mutating.

## Prometheus text exposition

`metric_exposition(r)` renders the registry in Prometheus text exposition
format version 0.0.4, in insertion order, one entry at a time. An empty
registry renders as `""`.

- Counter: `# TYPE <name> counter\n` then `<name>{labels} <value>\n`.
- Gauge: `# TYPE <name> gauge\n` then `<name>{labels} <value>\n`.
- Histogram: `# TYPE <name> histogram\n`, then one cumulative bucket line
  per stored bound `<name>_bucket{labels,le="<bound>"} <cum>` where `cum`
  is the running sum of the stored bucket counts, then the
  `<name>_bucket{labels,le="+Inf"} <count>` line, then
  `<name>_sum{labels} <sum>` and `<name>_count{labels} <count>`.

Braces and label pairs are omitted when an entry has no metric labels
(histogram bucket lines always keep braces because `le` is present).
Metric labels come first, then `le`. Label values are escaped per the text
format: `\` becomes `\\`, `"` becomes `\"`, and LF becomes `\n`; label
names and metric names are emitted verbatim. Values are integers.

Example -- a registry with one labeled counter, one gauge and one
3-bound histogram (two observations of 15 and 45):

```
# TYPE http_requests_total counter
http_requests_total{method="GET",code="200"} 3
# TYPE inflight gauge
inflight{svc="api"} 2
# TYPE latency_ms histogram
latency_ms_bucket{route="/a",le="10"} 0
latency_ms_bucket{route="/a",le="25"} 1
latency_ms_bucket{route="/a",le="50"} 2
latency_ms_bucket{route="/a",le="+Inf"} 2
latency_ms_sum{route="/a"} 60
latency_ms_count{route="/a"} 2
```

`metric_content_type()` returns the matching MIME type,
`text/plain; version=0.0.4; charset=utf-8`. `metric_latency_bounds_ms()`
returns the shared PULSE latency preset
`[1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]` as a fresh Vec; pass
it to `metric_histogram_new` / `metric_histogram_observe_labeled` so
services agree on one bucket layout.

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
| `metric_labels_new` / `add` / `len` / `name` / `value` | O(1) |
| `metric_labels_equal` | O(n^2) in the pair count |
| `metric_registry_new` / `count` / `reset` | O(1) |
| `metric_registry_find` | O(n*m) for n entries with m labels |
| `metric_counter_inc_labeled` / `metric_gauge_set_labeled` | O(n*m) find + O(1) update |
| `metric_histogram_observe_labeled` | O(n*m) find + O(k) observe (k bounds) |
| `metric_exposition` | O(total rendered size) |
| `metric_content_type` / `metric_latency_bounds_ms` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module metrics_tests`, 40 named checks, a
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
23. `metric_histogram_new` copies the caller's bounds;
24. `metric_labels_new` is empty and `metric_labels_add` extends both vectors;
25. label accessors return Ok in insertion order and Err out of range;
26. `metric_labels_equal` is order-insensitive and compares duplicates as counts;
27. `metric_registry_find` returns -1 on an empty/absent lookup and the index on a match (label order ignored);
28. `metric_counter_inc_labeled` accumulates on one (name, labels) entry and separates different label sets;
29. `metric_gauge_set_labeled` creates on first call and overwrites after;
30. `metric_histogram_observe_labeled` aggregates into one entry and keeps the first call's bounds (second call's bounds ignored);
31. exposition: counter with 0/1/2 labels (braces and comma placement);
32. exposition: gauge without and with one label;
33. exposition: histogram cumulative buckets, +Inf, sum and count;
34. exposition: histogram metric labels precede `le`;
35. exposition: label values escape `\`, `"` and LF;
36. exposition: empty registry renders `""`;
37. `metric_content_type` is the 0.0.4 MIME type;
38. `metric_registry_reset` drops every entry and the registry is reusable;
39. `metric_latency_bounds_ms` has the exact PULSE preset;
40. a histogram over the preset exposes 11 finite buckets + `+Inf` via the exposition.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.metrics
```

Last verified: compiler 0.64.0, `port: PASS (passed=40 failed=0
program_exit=0 exit=0)`, twice consecutively (2026-10-07).

## Known limitations

- In-process only: no collector loop, no background scraping, and no
  export format other than the Prometheus text 0.0.4 body produced by
  `metric_exposition` (the caller owns the HTTP endpoint and headers).
- Bounds must be sorted ascending by the caller; unsorted input is not an
  error but yields first-fit assignment over the given order.
- `Int` observations only: no floats, no units, no timers. Label names and
  values are opaque `Str` and are not validated on input.
- Labels are compared as an order-insensitive multiset, so two entries
  whose label sets differ only by order are the same series and cannot be
  kept apart.
- `min`/`max` read as 0 when empty; that is indistinguishable from a lone 0
  observation without also reading `count`.
- `metric_registry_find` and the labeled get-or-create calls are linear
  scans; a hot path with thousands of distinct (name, labels) pairs should
  keep the registry small or shard it.
- `metric_exposition` rebuilds the whole string on every call: fine for a
  scrape endpoint, not for a per-observation hot path.
- Each entry emits its own `# TYPE` line; when one metric name is used by
  several entries the TYPE line repeats (output is per entry, in insertion
  order), which strict Prometheus parsers may reject.
- Not thread-safe.
- `metric_histogram_observe` is O(bounds) because it scans for the first
  fitting bound; a hot path should keep the bound list short or widen
  buckets.

## Compiler / stdlib notes for v0.64.0

- Free functions only (no methods) and explicit `&`/`&mut` parameters.
- Str equality goes through `xiom.string.str_compare`, never `==`
  (BUG 17 discipline); the library imports `xiom.string`.
- Label pairs travel as two parallel `Vec[Str]` vectors, never as tuples
  (`Vec[(Str, Str)]` is the live m192 crash class).
- Byte reads widen as `(string.byte_at(s, i) as Int) & 0xFF`.
- The exposition is built with `xiom.string.builder` (`sb_new` /
  `sb_push_str` / `sb_push_int` / `sb_push_byte` / `sb_to_str`): one
  allocation at materialization, none per push.
- `Registry` is a `Vec[MetricEntry]`; entry mutation copies the value
  struct out (`var c = r.entries[at].c;`), mutates the local through the
  primitive's `&mut` API, and writes it back (the rate.xi precedent).
- Vec element reads go through typed `let` (`let b: Int = h.bounds[i];`)
  to keep inference unambiguous.
- Read-only calls in the tests are routed through tiny helpers taking
  `&mut` so that a `&local` call is never followed by a `&mut local` call
  in the same function body (advisory E001).
- `use xiom.metrics;` plus `xiom.test.assert` / `xiom.io.println` in the
  suite; the 0.2.0 tests add `xiom.string.compare` and
  `xiom.string.search`.

## Contracts (hardening pass, 2026-10-05)

Runtime-checked contracts; `xiom-verify --check` (Z3 4.13.4 on v0.63.0)
result: **0 proven / 0 violated / 19 unknown / 1 error** (no clause is
refuted).

| Entry point | Contract | Solver |
|---|---|---|
| `metric_counter_inc` | `ensures: c.value == c.value@pre + 1` | unproven |
| `metric_counter_add` | `ensures: c.value == c.value@pre + delta` | unproven |
| `metric_counter_reset` | `ensures: c.value == 0` | unproven |
| `metric_gauge_set` | `ensures: g.value == v` | unproven |
| `metric_gauge_add` | `ensures: g.value == g.value@pre + delta` | unproven |
| `metric_histogram_observe` | `ensures: h.count == h.count@pre + 1`; `ensures: h.sum == h.sum@pre + v`; `ensures: h.min <= h.max` | unproven |
| `metric_histogram_bucket_count` | `ensures: result >= 0` | unproven |
| `metric_histogram_bucket_len` | `ensures: result >= 1` | unproven |
| `metric_histogram_count` | `ensures: result >= 0` | unproven |
| `metric_histogram_reset` | `ensures: h.count == 0 && h.sum == 0 && h.min == 0 && h.max == 0` | unproven |
| `metric_counter_new` / `metric_gauge_new` / `metric_histogram_new` | none | unasserted (documented) |
| `metric_counter_value` / `metric_gauge_value` / `metric_histogram_sum` / `_min` / `_max` / `_mean` | none | unasserted (documented) |

Unasserted/documented: constructors (struct-result field access is out
of scope for the runtime evaluator) and pure getters (definitional) are
pinned by the test plan. The histogram bucket-assignment rule (first
bucket with `v <= bounds[i]`, else the +Inf bucket) and the
`bounds.len()+1` bucket-count invariant are test-pinned; the exact
`count`/`sum` accounting is machine-checked.

The 0.2.0 additions (labels, registry, exposition) intentionally carry no
contracts; their behavior is pinned by checks 24-40 of the conformance
suite (exact exposition strings included).
