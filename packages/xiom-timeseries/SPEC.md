# xiom.timeseries SPEC

## Package Overview

`xiom.timeseries` is a pure-XIOM, FFI-free toolkit for integer time series:
moving averages, fixed-point EMA, first differences, and range statistics.
One module: `xiom.timeseries` (`src/timeseries.xi`). A "series" is a flat
`Vec[Int]` in observation order; the module never allocates nested vectors
and never stores timestamps.

## Scope

- Trailing moving average with a partial prefix (`ts_moving_average`).
- Exponentially weighted moving average in permille fixed point (`ts_ema`).
- First differences (`ts_delta`).
- Scalar statistics: sum, mean, min, max, bounds, argmin, argmax.
- Min-max normalization to permille integers (`ts_normalize_permille`).
- Upward threshold crossing counts (`ts_threshold_crossings`).

## Non-Goals

- No timestamps, calendars, or time zones; no resampling, interpolation,
  alignment, or gap handling.
- No floating point; `Vec[Float64]` is never used (v0.61.3 trap).
- No volatility, correlation, regression, or seasonality functions.
- No streaming/incremental state; every call is a pure transform of a
  caller-owned slice.
- No mutation: all parameters are `&Vec[Int]` and every result is a fresh
  value (or a scalar).

## Data Model

The only data type crossing the API is `Vec[Int]` (and `Int` / `(Int, Int)`
scalars). There are no structs, no `Vec[Vec[Int]]`, no `Vec[StructType]`,
and therefore no `Vec[fn]` dispatch and no match statements in this module.

## API Signatures

```
pub fn ts_moving_average(values: &Vec[Int], window: Int) -> Vec[Int]
pub fn ts_ema(values: &Vec[Int], alpha_permille: Int) -> Vec[Int]
pub fn ts_delta(values: &Vec[Int]) -> Vec[Int]
pub fn ts_sum(values: &Vec[Int]) -> Int
pub fn ts_mean(values: &Vec[Int]) -> Int
pub fn ts_min(values: &Vec[Int]) -> Int
pub fn ts_max(values: &Vec[Int]) -> Int
pub fn ts_argmin(values: &Vec[Int]) -> Int
pub fn ts_argmax(values: &Vec[Int]) -> Int
pub fn ts_bounds(values: &Vec[Int]) -> (Int, Int)
pub fn ts_normalize_permille(values: &Vec[Int]) -> Vec[Int]
pub fn ts_threshold_crossings(values: &Vec[Int], threshold: Int) -> Int
```

## Semantics

Let `v` be the input series, `n = v.len()`.

- **`ts_moving_average(v, window)`** -- `window < 1` returns an empty
  vector. Otherwise the result has length `n` and, for every `i` in
  `[0, n)`:
  `k = min(i + 1, window)`,
  `out[i] = floor((v[i-k+1] + ... + v[i]) / k)`.
  The average uses only values that exist before `i` (partial prefix); the
  implementation keeps a single running sum and subtracts `v[i-window]`
  once `i >= window` (O(n) time, no per-position re-summing).
- **`ts_ema(v, alpha_permille)`** -- empty input returns empty. `alpha` is
  clamped to `[0, 1000]`. With `beta = 1000 - alpha`:
  `out[0] = v[0]`;
  `out[i] = floor((alpha*v[i] + beta*out[i-1]) / 1000)`.
  `alpha == 1000` reproduces `v` exactly and `alpha == 0` returns `v[0]`
  repeated `n` times (both are exact because the products are multiples of
  1000).
- **`ts_delta(v)`** -- empty input returns empty; otherwise `out[0] = 0`
  and `out[i] = v[i] - v[i-1]` for `i >= 1`.
- **`ts_sum(v)`** -- `0` for empty, otherwise the ordinary integer sum in
  observation order.
- **`ts_mean(v)`** -- `0` for empty, otherwise
  `floor(ts_sum(v) / n)`.
- **`ts_min(v)` / `ts_max(v)`** -- `0` for empty, otherwise the smallest /
  largest element.
- **`ts_argmin(v)` / `ts_argmax(v)`** -- `-1` for empty, otherwise the
  0-based index of the first occurrence of the extremum (strict `<` / `>`
  comparison keeps the earliest index on ties).
- **`ts_bounds(v)`** -- `(ts_min(v), ts_max(v))`; `(0, 0)` for empty.
- **`ts_normalize_permille(v)`** -- empty input returns empty. Let
  `lo = ts_min(v)`, `hi = ts_max(v)`, `span = hi - lo`. When `span == 0`
  (constant series) every position is `0`. Otherwise, for every `i`:
  `out[i] = clamp(floor((v[i] - lo) * 1000 / span), 0, 1000)`.
  Since `lo <= v[i] <= hi` and `span > 0`, the quotient is already within
  `[0, 1000]`; the clamp is defensive only.
- **`ts_threshold_crossings(v, threshold)`** -- `0` for empty. The first
  element counts as one crossing when `v[0] >= threshold`. For every
  `i >= 1`, a crossing is counted exactly when `v[i-1] < threshold` and
  `v[i] >= threshold` (a downward move never counts, and equal neighbours
  never count).

## Rounding Rules

- Every division in this module that is not exact rounds toward negative
  infinity (integer floor), including the EMA recurrence and the normalized
  scaling. This is the module's single, uniform rounding convention.
- The helper `_floor_div(a, b)` implements it for `b > 0` on top of the
  native `/` operator, which truncates toward zero: when `a % b < 0` it
  subtracts one from the truncated quotient. Example: `floor(-3/2) = -2`
  (native truncation would give `-1`).
- `ts_normalize_permille` needs no adjustment because its numerator is
  non-negative (`v[i] >= lo`), so floor equals truncation there.

## Edge Cases

| Input | Result |
|---|---|
| Empty series into any function | `ts_moving_average` / `ts_ema` / `ts_delta` / `ts_normalize_permille` -> empty; `ts_sum` / `ts_mean` / `ts_min` / `ts_max` -> `0`; `ts_argmin` / `ts_argmax` -> `-1`; `ts_bounds` -> `(0, 0)`; `ts_threshold_crossings` -> `0`. |
| `window == 0` or `window < 0` | `ts_moving_average` -> empty vector. |
| `window >= n` | Every position averages the full prefix ending at it; the last position is the average of the whole series. |
| `alpha_permille < 0` | Clamped to `0` (constant first value). |
| `alpha_permille > 1000` | Clamped to `1000` (identity). |
| Constant series in `ts_normalize_permille` | All zeros (no division by zero). |
| All-negative or mixed-sign series | Defined for every function; means and EMA floor toward `-inf`. |
| `threshold` below every element | `ts_threshold_crossings` returns `1` (first element at or above). |
| `threshold` above every element | `0` crossings. |

## Error Paths

The API is total: no `Result` returns, no contracts, no panics. Every
function is defined for every `Vec[Int]` and every `Int` argument, including
empty series, non-positive windows, out-of-range `alpha_permille`, and
constant ranges.

## Complexity

| Function | Time | Extra memory |
|---|---|---|
| `ts_moving_average` | O(n) | O(n) output (running sum) |
| `ts_ema` | O(n) | O(n) output |
| `ts_delta` | O(n) | O(n) output |
| `ts_sum` / `ts_mean` | O(n) | O(1) |
| `ts_min` / `ts_max` | O(n) | O(1) |
| `ts_argmin` / `ts_argmax` | O(n) | O(1) |
| `ts_bounds` | O(n) | O(1) |
| `ts_normalize_permille` | O(n) | O(n) output |
| `ts_threshold_crossings` | O(n) | O(1) |

## Test Plan

`tests/test_conformance.xi` (29 deterministic named tests, no I/O beyond
the pass/fail lines; expected series are built with `ivN` helpers and
compared through an element-wise `ints_eq`; every `Vec[Int]` read uses a
typed `let` binding per the v0.61.3 trap).

| Test | Checks |
|---|---|
| ma window 1 identity | `[3,1,4,1,5]` unchanged |
| ma window 2 partial prefix | `[1,2,6,0,4]` -> `[1,1,4,3,2]` (i=0 uses one value) |
| ma window 3 partial prefix | `[1,2,6,0,4]` -> `[1,1,3,2,3]` |
| ma floors negative sums | `[-1,-2]` -> `[-1,-2]`; `[-3,-4,-4]` -> `[-3,-4,-4]` (floor, not truncation) |
| ma window 0 | empty vector |
| ma negative window | empty vector |
| ma empty input | empty vector |
| ema alpha 1000 | identity on `[3,1,4,1,5]` |
| ema alpha 0 | `[7,9,2,5,1]` -> five times `7` |
| ema smoothing known | `[10,20,30]` @500 -> `[10,15,22]`; `[100,200,300]` @250 -> `[100,125,168]` |
| ema clamps alpha | 5000 acts as 1000 (identity); -7 acts as 0 (constant) |
| ema floors negative terms | `[-5,-10]` @500 -> `[-5,-8]`; `[3,-3,-9]` @250 -> `[3,1,-2]` |
| delta values | `[3,1,4,1,5]` -> `[0,-2,3,-3,4]` |
| delta empty and single | empty -> empty; `[42]` -> `[0]` |
| sum values | `[1,2,3,4,5]` -> 15; `[-5,2]` -> -3 |
| sum/mean empty | both `0` |
| mean floors | `[1,2,4]` -> 2; `[-1,-2]` -> -2; `[9]` -> 9; `[7,7,7,7,8]` -> 7 |
| min/max values | `[-3,5,-3,2,5]` -> min -3, max 5; constant `[7,7,7,7]` -> 7/7 |
| min/max empty | both `0` |
| argmin/argmax ties | `[4,2,9,2,9]` -> 1 / 2 (first occurrences); negatives; single element |
| argmin/argmax empty | both `-1` |
| bounds | `[-3,5,2]` -> `(-3,5)`; empty -> `(0,0)`; `[9]` -> `(9,9)` |
| normalize range | `[0,50,100]` -> `[0,500,1000]`; `[0,1,3]` -> `[0,333,1000]`; `[0,1,2]` -> `[0,500,1000]` |
| normalize all equal | `[7,7,7]` and `[-2,-2,-2,-2]` -> all zeros |
| normalize negative range + empty | `[-10,0,10]` -> `[0,500,1000]`; `[-2,-10,-6]` -> `[1000,0,500]`; empty -> empty |
| threshold start at or above | `[5,6,7]` @5 -> 1; `[5]` @5 -> 1; `[4]` @5 -> 0; empty -> 0 |
| threshold no crossings | flat zeros @1 -> 0; `[9,9,9,9]` @5 -> 1; `[4,3,2]` @5 -> 0 |
| threshold multiple crossings | `[5,1,2,7,3,9]` @5 -> 3; `[0,5,0,5,0]` @5 -> 2; `[4,5,4]` @5 -> 1 |
| large values | `[1e9,2e9,3e9]`: sum 6e9, mean 2e9, bounds exact, delta, window-2 average, normalize `[0,500,1000]`; `[-1e9,0,1e9]` bounds exact |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.timeseries
```

Expected: `port: PASS (passed=29 failed=0 program_exit=0 exit=0)`.

## Known Limitations

- **No overflow protection.** `ts_sum` and the moving-average running total
  can exceed `Int`; `ts_ema` computes `alpha * v[i]` and
  `ts_normalize_permille` computes `(v[i] - lo) * 1000`, both of which can
  overflow for extreme inputs. Results are then whatever two's-complement
  arithmetic yields; callers must scale inputs to the domain they need.
- **Floor-only precision.** All smoothed values are integers; there is no
  fixed-point scale argument beyond EMA's `alpha_permille`, and no rounding
  mode options (no half-up, no banker's rounding).
- **EMA is not seeded with a warm-up average.** `out[0]` is exactly
  `v[0]`, so early values carry the seed's bias (a standard EMA
  trade-off, pinned by tests).
- **No timestamps/resampling.** See Non-Goals; irregular spacing cannot be
  represented, and there is no windowing by time.
- **Differentiable/statistical extras absent.** No variance, standard
  deviation, median, quantiles or rolling min/max-with-window.
