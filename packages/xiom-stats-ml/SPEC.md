# xiom.stats-ml -- Specification

Status: `incubating` (implemented, conformance-tested on compiler 0.62.1, not
published).
Module: `xiom.stats_ml` (`src/stats_ml.xi`). Manifest: `package.xi` (name
`xiom.stats-ml`, version `0.1.0`). Depends on `xiom.std` for the manifest; the
library imports `xiom.string` and `xiom.convert` only. Tests:
`tests/test_conformance.xi` (22 checks).

## 1. Scope

Integer-only classifier evaluation:

- multi-class confusion matrix from parallel label vectors;
- per-class and macro precision / recall / F1 in basis points;
- accuracy in basis points;
- Cohen's kappa in basis points (exact integer ratio, one rounding);
- ROC threshold sweep for binary integer scores with trapezoid AUC;
- calibration bins over basis-point scores plus expected calibration error;
- class-balance statistics;
- a deterministic classification-report text renderer.

Pure and deterministic: no floats, no FFI, no I/O, no clock access, no global
state, no allocation beyond the returned vectors.

## 2. Fixed point and rounding

Basis-point scale: **`BPS = 10000`**, so `10000` represents `1.0`. Every
division that produces a metric is rounded **half away from zero** by
`_div_round(a, b)` (`b > 0`):

```
q = a / b ; r = a % b            // Int division truncates toward zero
if 2 * |r| >= b: q + 1 if a >= 0, else q - 1
else: q
```

`Int` division truncates toward zero and `%` follows the dividend's sign, so
`_div_round` is correct for the negative kappa numerator too. The doubling
`2 * |r|` cannot overflow for the denominators used here (sample counts,
class counts, `N^2`, `20000`; see section 8).

## 3. Data model

`ConfusionMatrix` (parallel vectors):

| Field | Type | Meaning |
|---|---|---|
| `classes` | `Vec[Str]` | distinct labels, first-occurrence order |
| `counts` | `Vec[Int]` | flat `k*k` row-major: true `i`, predicted `j` at `i*k + j` |
| `k` | `Int` | number of distinct classes |
| `total` | `Int` | number of samples |

`ClassBalance`:

| Field | Type | Meaning |
|---|---|---|
| `classes` / `counts` | `Vec[Str]` / `Vec[Int]` | parallel, first-occurrence order |
| `total` / `k` | `Int` | sample and class counts |
| `majority` / `minority` | `Int` | largest / smallest per-class count |
| `ratio_bps` | `Int` | `round(10000 * minority / majority)` |

`RocCurve` (all vectors of length `n_points`, points in descending-score
order):

| Field | Type | Meaning |
|---|---|---|
| `thresholds` | `Vec[Int]` | distinct scores, descending |
| `fpr_bps` / `tpr_bps` | `Vec[Int]` | per-point FPR / TPR in basis points |
| `tp` / `fp` | `Vec[Int]` | cumulative true / false positives |
| `positives` / `negatives` | `Int` | class counts |
| `auc_bps` | `Int` | trapezoid AUC in basis points |
| `n_points` | `Int` | number of points (`thresholds.len()`) |

`CalibrationBins` (parallel vectors of length `n_bins`):

| Field | Type | Meaning |
|---|---|---|
| `n_bins` | `Int` | number of bins |
| `counts` / `positives` | `Vec[Int]` | samples / positive samples per bin |
| `score_sum` | `Vec[Int]` | raw sum of scores per bin |
| `mean_score_bps` | `Vec[Int]` | `round(score_sum / count)`, 0 for empty bins |
| `positive_rate_bps` | `Vec[Int]` | `round(10000 * positives / count)`, 0 for empty bins |

Fields are implementation detail; use the `stats_ml_*` accessors, which are
range-safe (`""`, `0` or `-1` for out-of-range queries).

## 4. Confusion matrix

`stats_ml_confusion_matrix(y_true, y_pred)`:

1. Reject unequal lengths (`label vectors must have equal length`) and an empty
   input (`label vectors must not be empty`).
2. Collect distinct labels in first-occurrence order: scan all of `y_true`
   first, then `y_pred`, appending each unseen label. Comparisons use
   `string.str_compare`, never `==` (section 10).
3. Allocate `k*k` zero cells and count each `(true i, predicted j)` pair into
   `i*k + j`.
4. Reject `k > floor(sqrt(INT_MAX))` (`class count too large`).

Complexity: O(n*k) comparisons.

## 5. Per-class and macro metrics

With `TP_i = counts[i,i]`, `row_i = sum_j counts[i,j]` (support) and
`col_i = sum_j counts[j,i]` (predicted count):

- `precision_bps(i) = round(10000 * TP_i / col_i)`, or `0` when `col_i == 0`;
- `recall_bps(i)    = round(10000 * TP_i / row_i)`, or `0` when `row_i == 0`;
- `f1_bps(i)        = round(2 * P * R / (P + R))` on the rounded per-class
  basis-point `P = precision_bps(i)`, `R = recall_bps(i)`; `0` when `P+R = 0`.

Macro averages (over `k` classes): `round(sum_i metric_bps(i) / k)`, i.e. the
arithmetic mean of the already-rounded per-class basis-point values, then one
final rounding. Accuracy: `round(10000 * D / N)` with `D = sum_i TP_i` and
`N = total`; `0` for an empty matrix. Out-of-range class indices yield `0`.

Worked fixture (used by the tests), `[[3,1],[1,2]]`, `N=7`:

| class | precision | recall | f1 | support |
|---|---|---|---|---|
| 0 | 7500 | 7500 | 7500 | 4 |
| 1 | 6667 | 6667 | 6667 | 3 |
| macro | 7084 | 7084 | 7084 | — |

accuracy `7143`; kappa `4167`.

## 6. Cohen's kappa

```
D = sum_i counts[i,i]                     // diagonal
S = sum_i row_i * col_i                   // chance agreement numerator
kappa = (D*N - S) / (N^2 - S)
kappa_bps = round(10000 * (D*N - S) / (N^2 - S))
```

One rounding at the very end; no intermediate rounding. When `N^2 - S <= 0`
(chance agreement 1) the result is defined as **0**. Guards (first failure
wins): empty matrix (`kappa requires a non-empty matrix`), `N > floor(sqrt
(INT_MAX))` (`kappa sample count too large`), `|D*N - S| > floor(INT_MAX /
10000)` (`kappa scale overflows`). Complexity: O(k).

Fixture `[[8,2],[2,8]]`: `D=16`, `N=20`, `S=200`, kappa `6000`. Fixture
`[[3,1],[1,2]]`: kappa `4167`. Fixture `[[2,1],[1,0]]`: kappa `-3333`.

## 7. ROC and AUC

`stats_ml_roc_curve(scores, labels)`:

1. Validate: equal lengths (`score and label vectors must have equal length`),
   non-empty (`... must not be empty`), every label in `{0,1}` (`labels must be
   0 or 1`), at least one positive (`roc requires at least one positive label`)
   and one negative (`roc requires at least one negative label`).
2. Distinct scores are collected in **strictly descending** order
   (`_insert_unique_sorted_desc`), so FPR is non-decreasing along the points.
3. For each distinct threshold `t`, every sample with `score >= t` is predicted
   positive: `tp`/`fp` are counted, then
   `tpr_bps = round(10000 * tp / positives)` and
   `fpr_bps = round(10000 * fp / negatives)`.
4. AUC by the trapezoid rule over the points in FPR order, including the
   implicit `(0,0)` start and `(1,1)` end. Written as twice the area so every
   term stays integral:

```
area2 = 0 ; prev = (0,0)
for each point (f, t) in FPR order:
  area2 += (f - prev.f) * (t + prev.t)
  prev = (f, t)
area2 += (10000 - prev.f) * (10000 + prev.t)
auc_bps = round(area2 / 20000)
```

This matches `sklearn.metrics.auc` on the same operating points (ties
contribute half via the trapezoid). `area2 <= 20000 * 10000 = 2e8`, so no
overflow. Boundary cases: one distinct score (all ties) gives `auc_bps =
5000`; a perfectly ranked classifier gives `10000`; a perfectly anti-ranked
one gives `0`.

Fixtures: labels `[1,1,0,0]`, scores `[4,3,2,1]` -> `auc 10000`; labels
`[1,0,1,0]`, scores `[1,2,3,4]` -> `auc 2500`; labels `[1,0]`, scores `[5,5]`
-> `auc 5000`.

## 8. Calibration bins

`stats_ml_calibration_bins(scores, labels, n_bins)`:

1. Validate `n_bins` in `[1, 10000]` (`bin count must be positive` / `bin count
   must not exceed 10000`), equal lengths, non-empty, every score in
   `[0, 10000]` (`scores must be in [0, 10000]`) and every label in `{0,1}`
   (`labels must be 0 or 1`).
2. Bin index: `j = score * n_bins / 10000`, clamped to `n_bins - 1` for
   `score == 10000`. Bin `j` covers `[j*10000/n_bins, (j+1)*10000/n_bins)`.
3. Per bin: `count`, `positives`, `score_sum`, then `mean_score_bps =
   round(score_sum / count)` and `positive_rate_bps = round(10000 * positives
   / count)`; both are `0` for an empty bin.
4. ECE: `round(sum_j count_j * |positive_rate_bps_j - mean_score_bps_j| /
   total)`, computed on the rounded per-bin values; `0` for an empty histogram.

Worked fixture (4 bins, 25 samples each, scores 1250/3750/6250/8750, positives
1/2/3/4): rates `400/800/1200/1600`, means `1250/3750/6250/8750`, ECE `4000`.

## 9. Class balance

`stats_ml_class_balance(labels)`: reject empty input (`labels must not be
empty`), tally first-occurrence classes and counts (via `str_compare`), then
`majority`/`minority` are the max/min counts and `ratio_bps =
round(10000 * minority / majority)`. `ratio_bps == 10000` means perfectly
balanced. Complexity: O(n*k).

## 10. Compatibility notes (compiler 0.62.1)

- `==` on `Str` values read from `Vec` elements is a pointer comparison
  (BUG 17). Every label comparison and every error-message check uses
  `string.str_compare` / `compare.str_compare`, with both sides bound to typed
  locals first.
- Every `Vec[Int]` / `Vec[Str]` element read binds the element to a typed local
  before use.
- `Ok` / `Err` are only constructed in the leaf helpers (`_ok_cm`/`_err_cm`,
  `_ok_bal`/`_err_bal`, `_ok_roc`/`_err_roc`, `_ok_bins`/`_err_bins`,
  `_ok_int`/`_err_int`).
- Free functions only: no methods, generics, callbacks or indexed function
  dispatch; struct fields are parallel `Vec`s; parallel vectors are pushed in
  the same loop.
- The report renderer formats `Int`s with `xiom.convert.int_to_string`; labels
  are embedded verbatim between double quotes.

## 11. Error catalog

| Message | Trigger |
|---|---|
| `stats_ml: label vectors must have equal length` | confusion build length mismatch |
| `stats_ml: label vectors must not be empty` | confusion build empty input |
| `stats_ml: class count too large` | `k*k` would overflow `Int` |
| `stats_ml: kappa requires a non-empty matrix` | kappa on `total <= 0` |
| `stats_ml: kappa sample count too large` | `N*N` would overflow `Int` |
| `stats_ml: kappa scale overflows` | numerator too large to scale by 10000 |
| `stats_ml: score and label vectors must have equal length` | ROC / calibration length mismatch |
| `stats_ml: score and label vectors must not be empty` | ROC / calibration empty input |
| `stats_ml: labels must be 0 or 1` | ROC / calibration label not in `{0,1}` |
| `stats_ml: roc requires at least one positive label` | no positive samples |
| `stats_ml: roc requires at least one negative label` | no negative samples |
| `stats_ml: bin count must be positive` | calibration `n_bins <= 0` |
| `stats_ml: bin count must not exceed 10000` | calibration `n_bins > 10000` |
| `stats_ml: scores must be in [0, 10000]` | calibration score out of range |
| `stats_ml: labels must not be empty` | class balance on an empty vector |

## 12. Test plan

`tests/test_conformance.xi` (22 checks, all passing):

| # | Check |
|---|---|
| 1 | scale 10000 and bin-index edges/clamps |
| 2 | confusion matrix cells, classes and range-safe accessors |
| 3 | symmetric 2x2 gives 8000 bps on every metric |
| 4 | half-away rounding: 312.5 -> 313 (precision/recall/F1/macro/accuracy) |
| 5 | per-class and macro rounding on `[[3,1],[1,2]]` and `[[2,1],[1,0]]` |
| 6 | kappa exact (6000), perfect diagonal (10000), single-class degenerate (0) |
| 7 | kappa positive (4167), negative (-3333) and chance-level (0) |
| 8 | confusion validation and prediction-only class append |
| 9 | ROC perfect ranking: points and AUC 10000 |
| 10 | ROC interleaved ranking: AUC 2500 with point checks |
| 11 | ROC ties AUC 5000; flat positives rank perfectly (10000) |
| 12 | ROC validation errors and range-safe accessors |
| 13 | calibration counts/means/rates and ECE 4000 |
| 14 | calibration bin edges, validation errors and range safety |
| 15 | empty calibration bins and ECE spanning the extremes (10000) |
| 16 | classification report exact text for `[[3,1],[1,2]]` |
| 17 | classification report exact text for `[[8,2],[2,8]]` and spaced labels |
| 18 | N=1000 confusion matrix fixed-point expectations |
| 19 | N=1000 ROC sweep: monotone, 100 points, AUC 5000 |
| 20 | 3x3 confusion matrix rows, columns and accuracy |
| 21 | class-balance counts, ratio and empty-input error |
| 22 | 4-class diagonal matrix is perfect and renders in the report |
