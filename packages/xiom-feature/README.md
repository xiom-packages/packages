# xiom.feature

> **Status:** `incubating` -- implemented, pure XIOM (no FFI, no floats), and
> green under the repo harness. **NOT published** to the XIOM registry.
> **Scope:** feature engineering on scaled integers: degree-2 polynomial
> expansion, feature hashing (the "hashing trick"), extraction
> (mean/variance/min/max), scaling (min-max, z-score) and variance-threshold
> selection.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.string`
> and `xiom.convert`; tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`).

## What it is

`xiom.feature` prepares numeric features **without floating point**. Every
real number is carried as a 64-bit scaled integer (raw value / 10^3), so
results are deterministic and reproducible across machines. The module
covers the classical feature-engineering operations in miniature:

- degree-2 polynomial expansion of `n` inputs into `n*(n+1)/2` terms
  (squares plus pairwise products) with a fixed, documented order;
- feature hashing: tokens map to buckets via an in-module 32-bit FNV-1a over
  the UTF-8 bytes, plus a signed variant that spends one extra hash bit on
  the sign;
- extraction of mean, sample variance, minimum and maximum over one scaled
  vector;
- min-max scaling onto a caller-chosen raw target range and z-score scaling
  with an integer square root for the standard deviation;
- a variance-threshold selector over a row-major feature matrix, returning
  the selected column indices and their variances as parallel vectors.

There is no `Float64`, no FFI, no I/O and no global state. See `SPEC.md` for
the exact scaling, rounding, hashing and overflow rules.

## Scale

One scale is used everywhere in this module: 3 fraction digits
(`feature_data_decimals()`), raw = `value * 1000` (`feature_data_one()`).
Inputs, expansion terms, extracted statistics, scaled outputs and selector
variances are all data scale.

## API

| Function | Returns | Description |
|---|---|---|
| `feature_data_decimals()` | `Int` | Data scale (3). |
| `feature_data_one()` | `Int` | Raw value of 1.0 (1000). |
| `feature_poly2_count(n)` | `Result[Int, Str]` | Degree-2 term count `n*(n+1)/2`; guards the domain. |
| `feature_poly2_expand(&v)` | `Result[Vec[Int], Str]` | Terms `x[i]*x[j]/1000` for `i <= j`, lexicographic order. |
| `feature_hash32(token)` | `Int` | 32-bit FNV-1a of the UTF-8 bytes, in `[0, 2^32)`. |
| `feature_hash_bucket(token, buckets)` | `Result[Int, Str]` | Bucket in `[0, buckets)`; `Err` when `buckets <= 0`. |
| `feature_hash_bucket_signed(token, buckets)` | `Result[Int, Str]` | Nonzero signed index: sign from one extra hash bit, magnitude `bucket + 1`. |
| `feature_mean(&v)` | `Result[Int, Str]` | Mean, rounded half away from zero. |
| `feature_variance(&v)` | `Result[Int, Str]` | Sample variance (`n - 1`), data scale. |
| `feature_min(&v)` / `feature_max(&v)` | `Result[Int, Str]` | Extremes. |
| `feature_stats(&v)` | `Result[FeatureStats, Str]` | Mean, variance, min, max in one struct. |
| `feature_minmax_scale(&v, lo, hi)` | `Result[Vec[Int], Str]` | Affine map onto `[lo, hi]`; reversed targets invert; constant features error. |
| `feature_zscore_scale(&v)` | `Result[Vec[Int], Str]` | `(x - mean) / stddev` in data scale; constant features error. |
| `feature_matrix_new(rows, cols, &values)` | `Result[FeatureMatrix, Str]` | Row-major matrix; copies `values`; validates shape. |
| `feature_matrix_rows(m)` / `feature_matrix_cols(m)` | `Int` | Shape. |
| `feature_matrix_get(m, row, col)` | `Int` | Entry, or 0 when out of range. |
| `feature_matrix_data(m)` | `Vec[Int]` | Copy of the flat row-major data. |
| `feature_matrix_column(m, col)` | `Vec[Int]` | Copy of one column; empty when out of range. |
| `feature_variance_selector(&m, threshold)` | `Result[FeatureSelection, Str]` | Columns with variance `> threshold` (sklearn semantics), ascending. |

The complete error catalog is in `SPEC.md`.

## Usage

```xi
use xiom.feature;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // One feature, three samples in data scale (raw = value * 1000).
  var v = Vec[Int].new();
  v.push(1000);
  v.push(2000);
  v.push(4000);

  match feature_stats(&v) {
    Ok(s) => {
      io.println(convert.int_to_string(s.mean));      // 2333
      io.println(convert.int_to_string(s.variance));  // 2332
    },
    Err(e) => { io.println(e); },
  }

  io.println(convert.int_to_string(feature_hash32("hello"))); // 1335831723

  var pair = Vec[Int].new();
  pair.push(1000);
  pair.push(2000);
  match feature_poly2_expand(&pair) {
    Ok(t) => { io.println(convert.int_to_string(t.len())); }, // 3
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.feature
```

Expected tail: 22 `[PASS]` lines, `xiom.feature: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`. Verified with the
pinned compiler 0.62.1 (installed); 0.62.0 has not been re-run since these
tests were written.

## Limitations

- **Fixed scale, fixed envelope:** everything is 3 fraction digits. The
  recommended envelope is `|value| <= 1000000` raw (real 1000), vectors up to
  `1e9` entries and target spans up to `1e12`; outside it intermediate `Int`
  products can silently overflow (see `SPEC.md`). There is no dynamic
  rescaling and no overflow detection.
- **Polynomial expansion is degree 2 only,** has no bias term and no feature
  names; products are truncated to data scale (`x[i]*x[j]/1000`), so pairs
  with tiny real products can truncate to 0.
- **Hashing is not cryptographic:** FNV-1a is a fast non-cryptographic hash;
  bucket collisions are expected (by the birthday bound) and modulo bias
  appears for bucket counts that are not powers of two. The signed variant
  derives its sign from bit 16 of the same hash, so bucket and sign are not
  independent.
- **Extraction truncates:** the sample variance truncates every squared
  deviation to data scale, so small real variances can read as 0; the mean
  rounds half away from zero.
- **Scaling truncates:** min-max divisions truncate toward zero; z-score
  divides by `isqrt(variance * 1000)`, which floors the standard deviation.
  Features whose truncated variance is 0 are rejected as constant, even if
  their exact real variance is a small positive number.
- **Selector is variance-only:** no correlation, mutual-information or
  model-based selection; it scans every column and allocates a fresh column
  vector per column.
- **Out of scope (future work):** degree > 2 and configurable interaction
  sets, categorical/one-hot/target encoders, missing-value handling, robust
  or quantile scaling, incremental/streaming transforms.
- Not thread-safe; the types are plain values with no internal locking.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
