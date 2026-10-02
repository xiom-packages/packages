# xiom.stats-ml

> **Status:** `incubating` -- conformance-tested (22/22); published at `v0.1.0` on the XIOM registry.
> **Scope:** fixed-point ML evaluation metrics over integers (multi-class
> confusion matrix, precision/recall/F1, accuracy, Cohen's kappa, ROC/AUC,
> calibration bins, class balance) with a deterministic text report.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.string` and
> `xiom.convert`; tests additionally use `xiom.test`, `xiom.io`,
> `xiom.string` and `xiom.string.compare`).

## What it is

`xiom.stats-ml` evaluates classifiers **without floating point**. Every metric
is an integer algorithm with an explicitly documented rounding step, so results
are deterministic and reproducible across machines. The module covers:

- **confusion matrix** (`stats_ml_confusion_matrix`): multi-class, built from
  parallel label vectors; distinct labels keep first-occurrence order; cells
  are a flat row-major integer matrix (true class `i`, predicted class `j`);
- **precision / recall / F1** (`stats_ml_precision_bps`,
  `stats_ml_recall_bps`, `stats_ml_f1_bps`) per class and as macro averages
  (`stats_ml_macro_*_bps`), in basis points (`10000` = 1.0);
- **accuracy** (`stats_ml_accuracy_bps`) in basis points;
- **Cohen's kappa** (`stats_ml_kappa_bps`) from the exact integer ratio
  `(D*N - S) / (N^2 - S)`, rounded once at the end;
- **ROC threshold sweep and AUC** (`stats_ml_roc_curve`): one point per
  distinct integer score (descending), TPR/FPR in basis points, AUC by the
  trapezoid rule including the implicit `(0,0)` and `(1,1)` endpoints;
- **calibration bins** (`stats_ml_calibration_bins`): per-bin count, positive
  count, mean score and empirical positive rate in basis points, plus the
  expected calibration error (`stats_ml_calibration_ece_bps`);
- **class balance** (`stats_ml_class_balance`): first-occurrence per-class
  counts, majority/minority counts and their ratio in basis points;
- **classification report** (`stats_ml_classification_report`): a deterministic
  ASCII text renderer.

No `Float64`, no FFI, no I/O, no global state. See `SPEC.md` for the exact
formulas, fixed-point scales, rounding and validation order.

## Units

| Quantity | Unit | Notes |
|---|---|---|
| all rates and metrics | basis points (`10000` = 1.0) | round half away from zero |
| class labels | `Str` | compared with `string.str_compare`, never `==` |
| ROC scores | arbitrary `Int` | ties supported; descending sweep |
| calibration scores | `Int` in `[0, 10000]` | predicted-probability basis points |
| labels (ROC/calibration) | `Int` | `0` negative, `1` positive |

## API

| Function | Returns | Description |
|---|---|---|
| `stats_ml_bps()` | `Int` | Basis-point scale (10000). |
| `stats_ml_confusion_matrix(&y_true, &y_pred)` | `Result[ConfusionMatrix, Str]` | Build the `k x k` matrix and class list. |
| `stats_ml_cm_k(&cm)` / `stats_ml_cm_total(&cm)` | `Int` | Class and sample counts. |
| `stats_ml_cm_class(&cm, i)` | `Str` | Label at index `i`, or `""`. |
| `stats_ml_cm_class_index(&cm, label)` | `Int` | First-occurrence index, or `-1`. |
| `stats_ml_cm_cell(&cm, i, j)` | `Int` | Cell count, or `0` out of range. |
| `stats_ml_cm_row_sum(&cm, i)` / `stats_ml_cm_col_sum(&cm, j)` | `Int` | Support / predicted count. |
| `stats_ml_precision_bps(&cm, i)` | `Int` | Per-class precision in basis points. |
| `stats_ml_recall_bps(&cm, i)` | `Int` | Per-class recall in basis points. |
| `stats_ml_f1_bps(&cm, i)` | `Int` | Per-class F1 in basis points. |
| `stats_ml_macro_precision_bps(&cm)` / `_recall_` / `_f1_` | `Int` | Macro averages in basis points. |
| `stats_ml_accuracy_bps(&cm)` | `Int` | Accuracy in basis points. |
| `stats_ml_kappa_bps(&cm)` | `Result[Int, Str]` | Cohen's kappa in basis points. |
| `stats_ml_roc_curve(&scores, &labels)` | `Result[RocCurve, Str]` | ROC sweep and trapezoid AUC. |
| `stats_ml_roc_auc_bps(&curve)` | `Int` | AUC in basis points. |
| `stats_ml_roc_n_points(&curve)` | `Int` | Number of sweep points. |
| `stats_ml_roc_threshold/fpr_bps/tpr_bps/tp/fp(&curve, k)` | `Int` | Range-safe point accessors. |
| `stats_ml_roc_positives(&curve)` / `stats_ml_roc_negatives(&curve)` | `Int` | Class counts. |
| `stats_ml_bin_index(score, n_bins)` | `Int` | Bin of a basis-point score, or `-1`. |
| `stats_ml_calibration_bins(&scores, &labels, n_bins)` | `Result[CalibrationBins, Str]` | Calibration histogram. |
| `stats_ml_bins_count(&bins)` | `Int` | Number of bins. |
| `stats_ml_bin_count/positives/mean_score_bps/positive_rate_bps(&bins, j)` | `Int` | Range-safe bin accessors. |
| `stats_ml_calibration_ece_bps(&bins)` | `Int` | Expected calibration error in basis points. |
| `stats_ml_class_balance(&labels)` | `Result[ClassBalance, Str]` | Class-balance summary. |
| `stats_ml_balance_k/total/majority/minority/ratio_bps(&bal)` | `Int` | Scalar balance fields. |
| `stats_ml_balance_class(&bal, i)` / `stats_ml_balance_count(&bal, i)` | `Str` / `Int` | Range-safe per-class accessors. |
| `stats_ml_classification_report(&cm)` | `Str` | Deterministic ASCII report. |

The complete error catalog and formulas are in `SPEC.md`.

## Usage

```xi
use xiom.stats_ml;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // y_true / y_pred are parallel label vectors (see the conformance suite for
  // complete fixtures); here they describe confusion [[8,2],[2,8]].
  var y_true = Vec[Str].new();
  var y_pred = Vec[Str].new();
  // ... push 10 "cat" and 10 "dog" truths, and the matching predictions ...
  let cm = stats_ml_confusion_matrix(&y_true, &y_pred);
  if cm.is_ok {
    let m = cm.value;
    io.println(convert.int_to_string(stats_ml_accuracy_bps(&m))); // 8000
    io.println(stats_ml_classification_report(&m));
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.stats-ml
```

Expected tail: 22 `[PASS]` lines, `xiom.stats_ml: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`. Verified with the
pinned compiler 0.62.1 and the repo stdlib.

## Install / publish

This package is not on the registry yet. Once published:

```
xiom pkg install xiom.stats-ml@0.1.0   # consumer
xiom pkg publish                       # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Limitations

- **Fixed-point only.** Every metric is scaled to basis points (`10000` = 1.0)
  and rounded half away from zero; there is no floating-point path.
- **Macro averages** are the arithmetic mean of the per-class basis-point
  values (each already rounded), not a single rounding of exact fractions.
- **Kappa** is computed from the exact integer ratio in one rounding; when
  chance agreement is 1 (the denominator is 0) it is defined as 0.
- **AUC** uses the trapezoid rule over the observed operating points plus the
  implicit `(0,0)` and `(1,1)` endpoints (the standard `sklearn.metrics.auc`
  convention); ties contribute half through the trapezoid.
- **Calibration bins** require scores already in `[0, 10000]`; the module does
  not calibrate or rescale raw scores.
- **Overflow envelopes** for the guarded multiply-before-divide paths are
  documented in `SPEC.md`; the report renderer assumes ordinary sample counts.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
