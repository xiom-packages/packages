# xiom.feature -- Specification

Status: `incubating` (implemented, harness-green on compiler 0.62.1, not
published).
Module: `xiom.feature` (`src/feature.xi`). Manifest: `package.xi` (name
`xiom.feature`, version `0.1.0`). Depends on `xiom.std` for the manifest; the
library imports `xiom.string` (byte access) and `xiom.convert`.

## Scope

Feature engineering over scalar `Int` arithmetic:

- (a) degree-2 polynomial expansion (`feature_poly2_count`,
  `feature_poly2_expand`);
- (b) feature hashing ("hashing trick") with an in-module 32-bit FNV-1a
  (`feature_hash32`, `feature_hash_bucket`, `feature_hash_bucket_signed`);
- (c) extraction over one scaled vector (`feature_mean`,
  `feature_variance`, `feature_min`, `feature_max`, `feature_stats`);
- (d) min-max and z-score scaling (`feature_minmax_scale`,
  `feature_zscore_scale`);
- (e) variance-threshold selection over a row-major matrix
  (`feature_variance_selector`) returning selected indices and variances as
  parallel vectors;
- a small row-major `FeatureMatrix` with `feature_matrix_*` accessors.

Pure and deterministic: no floats, no FFI, no I/O, no clock access, no global
state, no allocation beyond the returned vectors and matrices.

## Non-goals

- degree > 2, configurable interaction sets, bias columns, feature names;
- cryptographic hashing, murmur/xxhash variants, hash seeding by the caller,
  collision resolution;
- categorical/one-hot/ordinal/target encoders;
- missing-value handling, robust/quantile scaling, whitening;
- correlation-, mutual-information- or model-based feature selection;
- overflow detection or dynamic rescaling.

## Scaled arithmetic rules

A raw integer `r` with 3 fraction digits denotes the real number `r / 1000`.
This single data scale is used for inputs, polynomial terms, extracted
statistics, scaled outputs, matrix entries and selector variances
(`feature_data_decimals()` is 3, `feature_data_one()` is 1000).

Division (`/`) in XIOM v0.62.x truncates toward zero; `%` is the matching
truncating remainder. Every rounding step is implemented explicitly:

- **Mean**: `_div_round(sum, n)` rounds half away from zero.
- **Variance**: each squared deviation is truncated to data scale
  (`d * d / 1000` with `d = x[i] - mean`), accumulated in `Int`, then
  divided by `n - 1` with `_div_round`. The result is the sample variance in
  data scale (a real variance of 2.0 is raw 2000).
- **Polynomial terms**: `x[i] * x[j] / 1000` with a single truncating
  division; the result is the data-scale product of two data-scale inputs.
- **Min-max scaling**: `lo + (x[i] - min) * (hi - lo) / (max - min)`, with
  the product before the truncating division.
- **Z-score scaling**: `sigma_raw = isqrt(variance * 1000)` floors the
  standard deviation; `out[i] = (x[i] - mean) * 1000 / sigma_raw` truncates
  toward zero. For `[1000, 2000, 3000]`: mean 2000, variance 1000,
  `sigma_raw = isqrt(1000000) = 1000`, output `[-1000, 0, 1000]`.
- **Integer square root**: `_isqrt(n)` for `n >= 0` is the floor of the real
  square root, computed by Newton iteration with the initial guess `x = n`.

### Safe magnitude envelope

The implementation does not detect overflow; the caller must stay inside the
envelope below (`Int` max `2^63 - 1 ~ 9.22e18`). A conservative envelope that
covers every operation, including z-score:

| Constraint | Bound | Worst intermediate |
|---|---|---|
| `|value|` (raw) | `<= 1000000` (real 1000) | poly product `<= 1e12` |
| vector length `n` | `<= 1000000000` | variance sum `<= 4e18` |
| target span `|hi - lo|` (raw) | `<= 1000000000000` | min-max product `<= 2e18` |
| derived variance | `<= 9.2e15` raw | `variance * 1000` for `_isqrt` |
| matrix shape | `rows * cols <= Int::MAX` | checked in `feature_matrix_new` |
| hash | `h < 2^32` | `h * 16777619 < 7.2e16` |

Outside this envelope (in particular for raw values near `3e9` in
polynomial products, or `variance * 1000` near `Int::MAX`) intermediate
products can silently overflow.

## (a) Polynomial expansion

For `n` inputs `x[0..n-1]`:

- count: `n * (n + 1) / 2` (n squares plus `n*(n-1)/2` pairwise products);
- ordering (fixed and documented): for `i = 0..n-1`, for `j = i..n-1`, the
  next term is `x[i] * x[j] / 1000`. For `n = 3` the terms are `(0,0)`,
  `(0,1)`, `(0,2)`, `(1,1)`, `(1,2)`, `(2,2)`; for `[1000, 2000, 3000]`
  the output is `[1000, 2000, 3000, 4000, 6000, 9000]`;
- `n = 0` gives an empty vector and count 0;
- **count errors**: `n < 0` or `n > 4294967295` (`n*(n+1)/2` no longer fits
  in `Int`); `feature_poly2_count` splits the even factor before multiplying
  so the maximum count `9223372034707292160` is computed without overflow.
  The same length guard exists in `feature_poly2_expand` (unreachable for
  real vectors).

## (b) Hash construction

`feature_hash32(token)` is standard 32-bit FNV-1a over the UTF-8 bytes of
`token`:

1. `h = 2166136261` (`0x811C9DC5`);
2. for each byte `b`: `h = ((h XOR b) * 16777619) mod 2^32`
   (`0x01000193` prime).

Byte reads follow the pin-safe pattern `(byte_at(token, i) as Int) & 255`:
the `UInt8` is widened and masked, because values `>= 128` are miscompiled
without the mask. Known vectors: `"" -> 2166136261`, `"a" -> 3826002220`,
`"hello" -> 1335831723`, `"foobar" -> 3214735720`, `"\u00e9" -> 513665217`,
`"\u03b1" -> 44730528` (the last two exercise bytes `>= 128`).

- bucket: `feature_hash_bucket(token, buckets) = feature_hash32(token) %
  buckets`, in `[0, buckets)`; `Err("feature: buckets must be positive")`
  when `buckets <= 0`.
- signed: `feature_hash_bucket_signed` takes **one extra hash bit** from the
  same 32-bit hash, extracted with divisor/modulo arithmetic (sign-bit tests
  are unreliable on the pin): `bit = (h / 65536) % 2` (bit 16). The result is
  `bucket + 1` when `bit == 0` and `-(bucket + 1)` when `bit == 1`, so the
  sign survives even for bucket 0 and the value is never 0. Magnitude is
  one-based: `|result| - 1` is the bucket.

Hashing is deterministic across runs and machines; collisions and modulo
bias (non-power-of-two bucket counts) are expected properties of the trick,
not errors.

## (c) Extraction

For `v` with `n = v.len()`:

- `feature_mean`: requires `n >= 1`; `Err("feature: empty vector")`
  otherwise.
- `feature_variance`: requires `n >= 2` (sample variance);
  `Err("feature: variance needs at least 2 samples")` otherwise. Small real
  variances can truncate to 0 (e.g. `[0, 1, 2, 3]` raw gives mean 2 and
  variance 0).
- `feature_min` / `feature_max`: require `n >= 1`; first-seen on ties.
- `feature_stats`: requires `n >= 2`; returns `FeatureStats{ mean;
  variance; min; max; }` with the same values as the four functions above.

## (d) Scaling

**Min-max**: `out[i] = lo + (x[i] - min) * (hi - lo) / (max - min)`.

- Requires `n >= 1` and `max != min`; errors are
  `feature: empty vector` and
  `feature: min-max scaling requires a non-constant feature`.
- `lo` and `hi` are raw target endpoints in the caller's chosen fixed-point
  scale. Reversed targets (`hi < lo`) invert the mapping; `lo == hi` maps
  everything to `lo`. For `[1000, 2000, 3000]`: target `[0, 1000]` gives
  `[0, 500, 1000]`; target `[-1000, 1000]` gives `[-1000, 0, 1000]`;
  target `[1000, 0]` gives `[1000, 500, 0]`. Truncation example:
  `[1000, 2000, 4000]` onto `[0, 1000]` gives `[0, 333, 1000]`.

**Z-score**: `out[i] = (x[i] - mean) * 1000 / isqrt(variance * 1000)`.

- Requires `n >= 2` and a positive truncated variance; errors are
  `feature: z-score scaling needs at least 2 samples` and
  `feature: z-score scaling requires a non-constant feature`.
- The output is data scale (`z * 1000`); outputs are unbounded (a value far
  from the mean can exceed the input span). Example: `[1000, 2000, 4000]`
  gives `[-872, -218, 1091]` (sigma `isqrt(2332000) = 1527`).

## (e) Variance-threshold selection

`feature_variance_selector(m, threshold)` scans columns left to right and
selects column `j` when `feature_variance(column j) > threshold`
(sklearn `VarianceThreshold` semantics: `threshold` is the largest variance
that is still discarded). With the default `threshold = 0` exactly the
non-constant columns remain.

- Returns `FeatureSelection{ indices; variances; }` with **parallel
  vectors**: one `indices` entry and one `variances` entry per selected
  column, at the same position, so both have equal length and `indices` is
  strictly ascending.
- Errors: `m.rows < 2` -> `feature: selector needs at least 2 samples`;
  `m.cols <= 0` -> `feature: matrix has no columns`; `threshold < 0` ->
  `feature: variance threshold must not be negative`.
- Fixture used in the tests (4 samples x 3 columns): column 0 is constant,
  column 1 is `[1000, 2000, 3000, 4000]` (variance 1667), column 2 is
  `[1000, 3000, 5000, 7000]` (variance 6667). Threshold 0 selects
  `[1, 2]` with variances `[1667, 6667]`; threshold 1667 selects `[2]`;
  threshold 6667 selects nothing.

## Representation

`FeatureMatrix` is row-major: `data[r * cols + c]`; `rows` and `cols` are
positive for any matrix produced by `feature_matrix_new`, and the data is a
private copy. `FeatureStats` carries four data-scale integers.
`FeatureSelection` carries the parallel `indices` / `variances` vectors. All
struct fields are public but internal implementation detail; prefer the
accessors where they exist.

## API signatures

```xi
pub type FeatureMatrix = { rows: Int; cols: Int; data: Vec[Int]; }
pub type FeatureStats = { mean: Int; variance: Int; min: Int; max: Int; }
pub type FeatureSelection = { indices: Vec[Int]; variances: Vec[Int]; }

pub fn feature_data_decimals() -> Int
pub fn feature_data_one() -> Int
pub fn feature_poly2_count(n: Int) -> Result[Int, Str]
pub fn feature_poly2_expand(v: &Vec[Int]) -> Result[Vec[Int], Str]
pub fn feature_hash32(token: Str) -> Int
pub fn feature_hash_bucket(token: Str, buckets: Int) -> Result[Int, Str]
pub fn feature_hash_bucket_signed(token: Str, buckets: Int) -> Result[Int, Str]
pub fn feature_mean(v: &Vec[Int]) -> Result[Int, Str]
pub fn feature_variance(v: &Vec[Int]) -> Result[Int, Str]
pub fn feature_min(v: &Vec[Int]) -> Result[Int, Str]
pub fn feature_max(v: &Vec[Int]) -> Result[Int, Str]
pub fn feature_stats(v: &Vec[Int]) -> Result[FeatureStats, Str]
pub fn feature_minmax_scale(v: &Vec[Int], lo: Int, hi: Int) -> Result[Vec[Int], Str]
pub fn feature_zscore_scale(v: &Vec[Int]) -> Result[Vec[Int], Str]
pub fn feature_matrix_new(rows: Int, cols: Int, values: &Vec[Int]) -> Result[FeatureMatrix, Str]
pub fn feature_matrix_rows(m: &FeatureMatrix) -> Int
pub fn feature_matrix_cols(m: &FeatureMatrix) -> Int
pub fn feature_matrix_get(m: &FeatureMatrix, row: Int, col: Int) -> Int
pub fn feature_matrix_data(m: &FeatureMatrix) -> Vec[Int]
pub fn feature_matrix_column(m: &FeatureMatrix, col: Int) -> Vec[Int]
pub fn feature_variance_selector(m: &FeatureMatrix, threshold: Int) -> Result[FeatureSelection, Str]
```

## Error catalog

Every `Err` payload has the exact prefix `feature: `.

| Message | Raised by | Condition |
|---|---|---|
| `feature: input length must not be negative` | `feature_poly2_count` | `n < 0` |
| `feature: polynomial expansion count overflows` | `feature_poly2_count`, `feature_poly2_expand` | `n > 4294967295` |
| `feature: buckets must be positive` | `feature_hash_bucket`, `feature_hash_bucket_signed` | `buckets <= 0` |
| `feature: empty vector` | `feature_mean`, `feature_min`, `feature_max`, `feature_minmax_scale` | `v.len() == 0` |
| `feature: variance needs at least 2 samples` | `feature_variance` | `v.len() < 2` |
| `feature: stats need at least 2 samples` | `feature_stats` | `v.len() < 2` |
| `feature: min-max scaling requires a non-constant feature` | `feature_minmax_scale` | `max == min` |
| `feature: z-score scaling needs at least 2 samples` | `feature_zscore_scale` | `v.len() < 2` |
| `feature: z-score scaling requires a non-constant feature` | `feature_zscore_scale` | truncated variance 0 |
| `feature: matrix rows must be positive` | `feature_matrix_new` | `rows <= 0` |
| `feature: matrix cols must be positive` | `feature_matrix_new` | `cols <= 0` |
| `feature: matrix rows*cols overflows` | `feature_matrix_new` | `rows > Int::MAX / cols` |
| `feature: matrix values length does not match rows*cols` | `feature_matrix_new` | length mismatch |
| `feature: selector needs at least 2 samples` | `feature_variance_selector` | `rows < 2` |
| `feature: matrix has no columns` | `feature_variance_selector` | `cols <= 0` |
| `feature: variance threshold must not be negative` | `feature_variance_selector` | `threshold < 0` |

Accessors never fail: `feature_matrix_get` returns 0 out of range;
`feature_matrix_column` returns an empty vector out of range.

## Complexity

| Operation | Complexity |
|---|---|
| `feature_poly2_count` | O(1) |
| `feature_poly2_expand` | O(n^2) |
| `feature_hash32` / `feature_hash_bucket` / `feature_hash_bucket_signed` | O(token length) |
| mean / variance / min / max / stats | O(n) |
| `feature_minmax_scale` / `feature_zscore_scale` | O(n) |
| `feature_matrix_new` / `feature_matrix_data` | O(rows*cols) |
| `feature_matrix_get` / rows / cols | O(1) |
| `feature_matrix_column` | O(rows) |
| `feature_variance_selector` | O(rows*cols) |

## Test plan

`tests/test_conformance.xi` (`module feature_tests`, 22 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count). Fixtures are built in-test (no files, no
I/O); hashing expectations are hand-computed FNV-1a vectors:

1. scale accessors are 3 / 1000;
2. `poly2_count` values 0/1/3/6/10, the `n = 4294967295` maximum, the
   negative-length error and the overflow error;
3. `poly2_expand` of empty and single inputs;
4. `poly2_expand` of two inputs is `(0,0), (0,1), (1,1)`;
5. `poly2_expand` ordering for three inputs is lexicographic `i <= j`;
6. `poly2_expand` truncates toward zero, including negative products;
7. `hash32` FNV-1a vectors for ASCII tokens (`""`, `a`, `hello`, `foobar`);
8. `hash32` widens and masks bytes `>= 128` (`\u00e9`, `\u03b1`, plus two
   ASCII controls);
9. hashing is deterministic and buckets stay in range for two bucket counts;
10. buckets match the hand-computed FNV-1a values mod 8;
11. hashing rejects non-positive bucket counts;
12. signed hashing uses the extra bit, matches known signs, stays nonzero
    and satisfies `|result| == bucket + 1`;
13. mean rounds halves away from zero and guards empty input;
14. variance is the `n - 1` sample variance in data scale (2332 fixture);
15. min and max scan the whole vector;
16. stats aggregates mean, variance, min and max (and rejects `n = 1`);
17. min-max scaling maps onto the target range, reversed targets included,
    and truncates (`333` fixture);
18. min-max scaling rejects constant and empty features;
19. z-score scaling divides by the truncated integer sigma
    (`[-872, -218, 1091]` fixture);
20. z-score scaling rejects constant and too-short features;
21. `matrix_new` validates shape, copies the caller values, and accessors
    are range-safe;
22. the variance selector returns ascending parallel indices and variances.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.feature
```

Last verified: compiler 0.62.1 (installed),
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Fixed scale (3) and the envelope above; no overflow detection and no
  dynamic rescaling.
- FNV-1a is not cryptographic; collisions are expected and modulo bias
  appears for non-power-of-two bucket counts. Bucket and signed-variant sign
  come from the same 32-bit hash (bit 16), so they are not independent.
- Integer rounding is lossy by construction: variance truncates each squared
  deviation, z-score sigma is floored, and scaled outputs truncate. Features
  whose truncated variance is 0 are treated as constant.
- The selector is variance-only and allocates one column copy per column
  while scanning; it is O(rows*cols) time and O(rows) extra space.
- No missing-value handling, no encoders, no incremental/streaming APIs.
- Not thread-safe; no global state.

## Compiler notes (pinned v0.62.1)

- Free functions only; explicit `&`/`&mut`; no methods.
- `Ok`/`Err` are constructed only in the leaf helpers `_ok_int`/`_err_int`,
  `_ok_ints`/`_err_ints`, `_ok_matrix`/`_err_matrix`, `_ok_stats`/`_err_stats`
  and `_ok_selection`/`_err_selection` (the documented v0.62.x code-shape
  hazard).
- Every `Str` value read from a `Vec[Str]` is compared only through
  `xiom.string.compare.str_compare` in the tests (BUG 17 family), never `==`.
- Every byte read via `xiom.string.byte_at` is widened to `Int` and masked
  with `255` (the documented `>= 128` miscompile); the signed hash bit is
  extracted with divisor/modulo arithmetic, never a sign-bit test.
- All Vec element reads go through typed `let`; every type uses canonical
  `Vec[Int]` / `Result[T, Str]` brackets; no `Vec[Float64]`, no FFI, no I/O.
