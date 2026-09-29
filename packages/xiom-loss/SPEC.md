# xiom.loss -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.loss` (`src/loss.xi`). Manifest: `package.xi` (name
`xiom.loss`, version `0.1.0`). Depends on `xiom.std` for the manifest only;
the library module imports `xiom.string` and `xiom.convert`.

## Scope

Fixed-point supervised loss functions over scaled integers:

- `loss_mse` / `loss_mse_grad`: mean squared error;
- `loss_mae` / `loss_mae_grad`: mean absolute error (sign-based gradient);
- `loss_hinge` / `loss_hinge_grad`: margin hinge loss over +1/-1 targets;
- `loss_binary_cross_entropy` / `loss_binary_cross_entropy_grad`;
- `loss_categorical_cross_entropy` / `loss_categorical_cross_entropy_grad`;
- `loss_natural_log`: the fixed-point `ln` the cross-entropies use, exposed;
- `loss_clip`: probability clamping with error reporting;
- scale accessors.

Pure and deterministic: no floats, no FFI, no I/O, no clock, no global
state, no allocator use beyond the returned/gradient vectors.

## Non-goals

- Softmax / logits-based cross-entropy, log-sum-exp, numerical-stability
  variants.
- Huber, NLL, focal, triplet, contrastive or ranking losses (the placeholder
  README mentioned HuBLE/NLL; they are explicitly out of scope for 0.1.0).
- Optimizers, learning-rate schedules or backpropagation graphs.
- Batch/epoch aggregation across invocations, class weights, reduction
  options other than the documented mean/sum.
- Floats of any kind (`Vec[Float64]` is unavailable on the pin and unused).

## Scales and rounding

| Quantity | Fraction digits | Raw representation |
|---|---|---|
| Predictions, targets, probabilities, margins, gradients | 3 | `value * 1000` |
| Every returned loss | 6 | `loss * 1000000` |

`loss_value_one()` = 1000, `loss_loss_one()` = 1000000,
`loss_probability_epsilon()` = 1.

Rounding rules:

- XIOM integer division truncates toward zero.
- `_div_round(a, b)` (b > 0) returns `a / b` rounded to nearest, ties away
  from zero.
- `_mul_div_round(a, m, b)` (b > 0) computes `round(a * m / b)` without
  overflowing the intermediate product (`a = q*b + r`, then
  `q*m + round(r*m/b)`), and is used for the MAE loss.
- Means are rounded after accumulation: `round(sum / n)` for MSE, hinge,
  BCE and CE; `round(sum * 1000 / n)` for MAE.
- Gradients are rounded per entry after the `1/n` (or `1/p`) division.

## Definitions and gradients

Let `n` be the vector length, `p_i`/`t_i` value-scale raws, `d_i = p_i - t_i`,
`m` the value-scale margin, and `ln6(x) = round(ln(x/1000) * 1e6)` the loss
scale `ln`.

`loss_mse`
: loss raw = `round(sum d_i^2 / n)`. A raw difference of 1000 (1.0) squares
  to 1000000 (1.0) in loss scale.
  Gradient raw (value scale) = `round(2*d_i / n)`.

`loss_mae`
: loss raw = `round(1000 * sum |d_i| / n)`.
  Gradient raw (value scale) = `sign(d_i) * round(1000 / n)`; exactly 0 when
  `d_i = 0`.

`loss_hinge`
: targets must be exactly +1000 or -1000, so `z_i = t_i * p_i / 1000` is the
  exact value-scale product.
  loss raw = `round(sum max(0, (m - z_i) * 1000) / n)`.
  Gradient raw (value scale) = `round(-t_i / n)` when `m > z_i`, else 0.

`loss_binary_cross_entropy`
: targets must be exactly 0 or 1000. With `p_hat = clip(p, 1, 999)`:
  per-sample term = `-ln6(p_hat)` for `t = 1000` and `-ln6(1000 - p_hat)`
  for `t = 0`; loss raw = `round(sum terms / n)`.
  Gradient raw (value scale) per sample =
  `round(round(-1000000 / p_hat) / n)` for `t = 1000` and
  `round(round(1000000 / (1000 - p_hat)) / n)` for `t = 0`
  (the value-scale form of `(1/n)(-y/p + (1-y)/(1-p))`).

`loss_categorical_cross_entropy`
: targets are a value-scale distribution: every entry in `[0, 1000]` and the
  entries sum to exactly 1000. With `p_hat = clip(p_i, 1, 999)`:
  `acc = sum t_i * ln6(p_hat_i)`;
  loss raw = `round(-acc / 1000)` = `round(-sum y_i ln6(p_hat_i) / 1000)`.
  Gradient raw (value scale) = `round(-1000 * t_i / p_hat_i)`, the
  value-scale form of `-y/p`.
: For a one-hot target at class k the loss reduces to `-ln6(p_k)` and the
  gradient to `-1000 * 1000 / p_k` at k, 0 elsewhere; this equals the BCE
  result for the same probability (checked in test t27).

`loss_clip`
: `Ok(p)` when `lo <= p <= hi`, else `Ok(lo)` / `Ok(hi)`. Bounds are
  validated: `0 <= lo <= hi <= 1000`, otherwise `Err`.

## Fixed-point natural logarithm

`loss_natural_log(x)` accepts a value-scale raw `x` with
`0 < x <= 9223372036854` (`INT_MAX / 1e6`, so `x * 1e6` cannot overflow) and
returns `Ok(ln(x/1000) * 1e6 rounded half away from zero)`.

Method (all steps on `Int`):

1. `X = x * 1000000` (1e9 working scale).
2. Normalize `X` into `[1e9, 2e9)`: while `X >= 2e9`,
   `X = X/2 + X%2`, `k = k + 1` (rounded halving); while `X < 1e9`,
   `X = 2X`, `k = k - 1` (exact doubling).
3. `t = (X - 1e9) * 1e9 / (X + 1e9)`, truncated; `t in [0, 1/3]`.
4. Powers in the 1e9 scale: `t2 = t*t/1e9`, `t3 = t2*t/1e9`,
   `t5 = t3*t2/1e9`, `t7 = t5*t2/1e9`, `t9 = t7*t2/1e9`,
   `t11 = t9*t2/1e9`, `t13 = t11*t2/1e9`.
5. `ln_m = 2*(t + t3/3 + t5/5 + t7/7 + t9/9 + t11/11 + t13/13)`, truncating
   divisions.
6. `total = ln_m + k * 693147181` (`693147181 = round(ln 2 * 1e9)`).
7. Return `_div_round(total, 1000)`.

Error bound: the atanh series remainder after `t^13/13` is below
`2*(1/3)^15/15/(1-1/9) ~ 1.1e-8`; the reduction loses at most ~1e-9 real per
rounded halving; truncating `t` costs below 2.3e-9; the `ln 2` constant adds
`1.8e-10 * |k|` (below 1.2e-8 for `|k| <= 62`); the final result rounding is
at most 5e-7. Documented bound: **at most one unit of the 1e-6 output
scale** (1e-6 real). Measured maximum over `x in [1, 999]`: 0.504 units
(`x = 308`); over the wide sweep up to `9223372036854`: 0.462 units.

Domain guards: `x <= 0` returns
`Err("loss: logarithm argument must be positive")`; `x > 9223372036854`
returns `Err("loss: logarithm argument exceeds the supported envelope")`.
The cross-entropy functions never call it out of domain: they clamp first.

## Envelope and overflow behavior

- Every prediction/target/margin is checked against
  `|x| <= 4000000000` raw; larger magnitudes return an envelope error.
- MSE additionally requires `|p - t| <= 3037000499` so `d^2 <= INT64_MAX`;
  violating inputs return `"loss: squared difference overflows"`.
- MSE and hinge accumulations are checked against `INT64_MAX`;
  overflowing sums return `"loss: accumulation overflows"`. MAE, BCE and CE
  accumulations are structurally bounded (MAE by the envelope and the
  `Vec` element cap, cross-entropies by `sum(targets) = 1000` and
  `|ln6| <= ~7e6`), so no check is required there.
- Inputs are never wrapped: every out-of-range condition has an error path.

## Error catalog

| Message | Raised by |
|---|---|
| `loss: predictions and targets must not be empty` | every pair function |
| `loss: predictions and targets length mismatch` | every pair function |
| `loss: prediction magnitude exceeds the supported envelope` | MSE/MAE/hinge (loss and grad) |
| `loss: target magnitude exceeds the supported envelope` | MSE/MAE (loss and grad) |
| `loss: margin magnitude exceeds the supported envelope` | hinge (loss and grad) |
| `loss: squared difference overflows` | MSE (loss and grad) |
| `loss: accumulation overflows` | MSE, hinge loss, BCE loss |
| `loss: hinge target must be +1000 or -1000` | hinge (loss and grad) |
| `loss: margin must not be negative` | hinge (loss and grad) |
| `loss: binary target must be 0 or 1000` | BCE (loss and grad) |
| `loss: categorical target must be in [0, 1000]` | CE (loss and grad) |
| `loss: categorical targets must sum to 1000` | CE (loss and grad) |
| `loss: logarithm argument must be positive` | `loss_natural_log` |
| `loss: logarithm argument exceeds the supported envelope` | `loss_natural_log` |
| `loss: clip bounds must satisfy 0 <= lo <= hi <= 1000` | `loss_clip` |

`Err` payloads are exact strings; tests compare them with
`str_compare` (pointer equality on `Vec[Str]` elements is unreliable on the
pin).

## Complexity

| Operation | Complexity |
|---|---|
| scale accessors, `loss_clip`, `loss_natural_log` | O(1) |
| every loss / gradient over `n` entries | O(n) |
| auxiliary space | O(1) for scalar losses, O(n) for gradients |

## Test plan

`tests/test_conformance.xi` (`module loss_tests`, 27 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count):

1. scale accessors 3/6 with units 1000/1000000 and epsilon 1;
2. `loss_natural_log` pinned exact values (0, -693147, 405465, 6907755);
3. `loss_natural_log` within one unit of true `ln` at 1, 100, 900, 999;
4. `loss_natural_log` rejects 0, negatives and oversized arguments;
5. `loss_clip` clamps up, down, in-range, edge-equal and degenerate bounds;
6. `loss_clip` rejects `lo > hi`, negative `lo` and `hi > 1000`;
7. MSE exact fixtures (0.5, 0, 0.5625) and zero loss on identical vectors;
8. MSE rounds half away from zero (1/2 -> 1) and validates empty/mismatch;
9. MSE gradient exact values for both signs;
10. MSE gradient single-sample sign and empty/mismatch errors;
11. MAE exact fixtures (1.0, 0, 0.5);
12. MAE gradient signs, `1/n` scaling and zero at equal entries;
13. MAE empty/mismatch errors;
14. hinge zero loss and zero gradient on correctly classified margins;
15. hinge loss 0.75 and gradient -0.5/+0.5 at margin 1.0;
16. hinge scales with margin and zeroes inactive gradients;
17. hinge target/margin/shape errors;
18. BCE pinned `ln(0.5)` and `ln(0.9)` values;
19. BCE mean over two samples and `ln(0.999)`;
20. BCE clamps `p = 0` and `p = 1` into `[1, 999]`;
21. BCE target and shape errors;
22. BCE gradient exact values including the `1/n` mean;
23. categorical cross-entropy exact on one-hot and soft targets;
24. categorical gradient exact on one-hot and soft targets;
25. categorical clamps `p = 0` and `p = 1`;
26. categorical target-distribution and shape errors;
27. BCE equals the 2-class categorical cross-entropy (invariant).

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.loss
```

Last verified: compiler 0.62.1, `port: PASS (passed=27 failed=0
program_exit=0 exit=0)`, run twice.

## Known limitations

- Gradients are quantized to the value grid: `round(1000/n)` for MAE and
  hinge can round to 0 for `n > 2000`; BCE/CE gradients round similarly for
  large `n`. This matches the rounded loss definitions but is not exact
  real-valued calculus.
- Cross-entropy inputs at the boundary are clamped, not infinite: the
  reported loss is finite and biased low near `p = 0`/`p = 1`.
- `loss_natural_log` is an approximation bounded to one 1e-6 unit, not the
  platform `ln`.
- Categorical cross-entropy treats the input as a single sample (no class
  averaging); batch means must be taken by the caller.
- The hinge loss requires exactly +1/-1 targets; other label conventions
  must be mapped by the caller.
- MSE/MAE accept arbitrary value-scale targets; there is no implicit
  normalization.

## Compiler / stdlib notes for v0.62.1

- Free functions only (no methods) and explicit `&` parameters; no
  `Vec[StructType]`, no generic callbacks, no `Vec[Float64]`.
- `Ok`/`Err` construction is confined to the leaf helpers `_ok_int`,
  `_err_int`, `_ok_ints`, `_err_ints`.
- `Vec[Int]` element reads always go through typed locals
  (`let x: Int = v[i];`).
- Error-message equality in the tests is routed through
  `xiom.string.compare.str_compare`; the mixed-bracket trap was checked with
  a `Vec<`/`Result<` grep after every write and again after green.
- Stdlib gaps this package had to work around: no integer/fixed-point
  logarithm or exponential (`xiom.math.*` is `Float64`-only), no
  round-half-away integer division or scaled mul-div helper, no
  `Vec[Int]` zeros/fold helpers, no integer approximate-equality test
  assertion.
