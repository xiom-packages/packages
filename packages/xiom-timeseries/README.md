# xiom.timeseries

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** moving averages, fixed-point EMA, first differences, and range
> statistics over flat `Vec[Int]` integer series.
> **Deps:** `xiom.std` only (`deps` declares the platform dependency; the
> library module itself imports nothing). Pure XIOM, no FFI.

## What it is

`xiom.timeseries` is a small, dependency-free toolkit for integer time
series. A series is a flat `Vec[Int]` in observation order; there are no
timestamps, no resampling, and no floating point. Every returned value is an
integer, and every division that is not exact rounds toward negative
infinity (integer floor) -- including the fixed-point EMA recurrence.

The module exposes twelve free functions: two smoothing primitives
(`ts_moving_average`, `ts_ema`), one first-difference transform
(`ts_delta`), five scalar statistics (`ts_sum`, `ts_mean`, `ts_min`,
`ts_max`, plus the `(min, max)` pair `ts_bounds`), two extremum positions
(`ts_argmin`, `ts_argmax`), one min-max scaling transform
(`ts_normalize_permille`), and one event counter
(`ts_threshold_crossings`). All functions are total: every input --
including empty series, `window < 1`, out-of-range `alpha_permille` and
constant ranges -- has a documented result, and none of them panic.

## API

| Function | Returns | Description |
|---|---|---|
| `ts_moving_average(values, window)` | `Vec[Int]` | Same length as `values`; position `i` is the floored average of the `min(i+1, window)` values ending at `i`. `window < 1` yields an empty vector. |
| `ts_ema(values, alpha_permille)` | `Vec[Int]` | Fixed-point EMA. `out[0] = values[0]`; `out[i] = floor((alpha*values[i] + (1000-alpha)*out[i-1]) / 1000)`. `alpha` is clamped to `0..1000`. |
| `ts_delta(values)` | `Vec[Int]` | `out[0] = 0`; `out[i] = values[i] - values[i-1]`. Empty input yields empty. |
| `ts_sum(values)` | `Int` | Sum of every element; `0` for an empty series. |
| `ts_mean(values)` | `Int` | Floored arithmetic mean; `0` for an empty series. |
| `ts_min(values)` | `Int` | Smallest element; `0` for an empty series. |
| `ts_max(values)` | `Int` | Largest element; `0` for an empty series. |
| `ts_argmin(values)` | `Int` | 0-based index of the first minimum; `-1` for an empty series. |
| `ts_argmax(values)` | `Int` | 0-based index of the first maximum; `-1` for an empty series. |
| `ts_bounds(values)` | `(Int, Int)` | `(min, max)` pair; `(0, 0)` for an empty series. |
| `ts_normalize_permille(values)` | `Vec[Int]` | `(v - min) * 1000 / (max - min)`, clamped to `0..1000`; a constant series maps to all zeros; empty maps to empty. |
| `ts_threshold_crossings(values, threshold)` | `Int` | Number of moves from below `threshold` to `threshold` or above; a first element already at or above it counts as one crossing. |

## Usage

```xi
use xiom.timeseries;

// Build any Vec[Int] series: closes, samples, counters, ...
let v = ...;

let ma3 = ts_moving_average(&v, 3);      // trailing 3-point average
let smooth = ts_ema(&v, 250);            // alpha = 0.25 in permille form
let changes = ts_delta(&v);              // [0, v1-v0, v2-v1, ...]

let total = ts_sum(&v);
let avg = ts_mean(&v);
let (lo, hi) = ts_bounds(&v);
let where_min = ts_argmin(&v);           // first minimum index

let scaled = ts_normalize_permille(&v);  // 0..1000 over [min, max]
let breaks = ts_threshold_crossings(&v, 100); // upward crossings of 100
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.timeseries
```

Expected: the namespaced module passes the section-4 namespace rule, 29
`[PASS]` lines, and a final
`port: PASS (passed=29 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Integer / fixed-point only.** There is no floating-point path
  (`Vec[Float64]` is not used): means, moving averages and EMA values are
  floored integers, so small series lose sub-unit precision by design.
- **No timestamps or resampling.** A series is just ordered integers; there
  is no `DateTime` axis, no regular/irregular grid, no up/down-sampling,
  interpolation or gap handling.
- **No overflow guards.** `ts_sum`, the moving-average running total,
  `ts_ema` products and the `(v - min) * 1000` scaling term can overflow
  `Int` (i64) for extreme magnitudes; values are used as given.
- **Eager materialization.** `ts_moving_average`, `ts_ema`, `ts_delta` and
  `ts_normalize_permille` always allocate a fresh output vector of input
  length; there is no streaming/incremental API and no in-place variant.
- **Single-threaded.** No locks, atomics or async variants; callers
  serialize access.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
