# xiom.loss

> **Status:** `incubating` -- conformance-tested (27/27); published at `v0.1.0` on the XIOM registry.
> **Scope:** fixed-point supervised loss functions (MSE, MAE, hinge, binary
> and categorical cross-entropy) with matching gradients, on scaled integers.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.string` and
> `xiom.convert`; tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`).

## What it is

`xiom.loss` computes supervised training losses **without floating point**.
Every real number is a 64-bit scaled integer (raw / 10^decimals), so results
are deterministic and reproducible across machines:

- mean squared error and its gradient (`2*(pred-target)/n`);
- mean absolute error and its sign-based gradient;
- hinge loss with a margin parameter and its active-margin gradient;
- binary cross-entropy and its gradient, with a fixed-point natural
  logarithm and a documented probability clamp;
- categorical cross-entropy over a class-probability vector and the
  per-class gradient vector;
- `loss_clip` for probability clamping with error reporting;
- `loss_natural_log`, the fixed-point `ln` the cross-entropies build on.

There is no `Float64`, no FFI, no I/O and no global state. See `SPEC.md` for
the exact scaling, rounding, logarithm error bounds and overflow rules.

## Scales

| Quantity | Fraction digits | Raw representation |
|---|---|---|
| Predictions, targets, probabilities, gradients | 3 | `value * 1000` |
| Every returned loss | 6 | `loss * 1000000` |

`loss_value_one()` is 1000 and `loss_loss_one()` is 1000000. Results that are
not exact are rounded to nearest with ties away from zero; XIOM's raw integer
division truncates toward zero and every rounding step is explicit in the
implementation.

## API

| Function | Returns | Description |
|---|---|---|
| `loss_value_decimals()` / `loss_loss_decimals()` | `Int` | 3 and 6 fraction digits. |
| `loss_value_one()` / `loss_loss_one()` | `Int` | 1000 and 1000000. |
| `loss_probability_epsilon()` | `Int` | 1 (0.001); cross-entropy clamp step. |
| `loss_natural_log(x)` | `Result[Int, Str]` | `ln(x/1000)` in loss scale; `x > 0`. |
| `loss_clip(p, lo, hi)` | `Result[Int, Str]` | Clamp `p` into `[lo, hi]`. |
| `loss_mse(&preds, &targets)` | `Result[Int, Str]` | `mean((pred-target)^2)`, loss scale. |
| `loss_mse_grad(&preds, &targets)` | `Result[Vec[Int], Str]` | `2*(pred-target)/n`, value scale. |
| `loss_mae(&preds, &targets)` | `Result[Int, Str]` | `mean(|pred-target|)`, loss scale. |
| `loss_mae_grad(&preds, &targets)` | `Result[Vec[Int], Str]` | `sign(pred-target)/n`, value scale. |
| `loss_hinge(&preds, &targets, margin)` | `Result[Int, Str]` | `mean(max(0, margin - target*pred))`. |
| `loss_hinge_grad(&preds, &targets, margin)` | `Result[Vec[Int], Str]` | `-target/n` on active margins, else 0. |
| `loss_binary_cross_entropy(&preds, &targets)` | `Result[Int, Str]` | `mean(-[y*ln(p) + (1-y)*ln(1-p)])`. |
| `loss_binary_cross_entropy_grad(&preds, &targets)` | `Result[Vec[Int], Str]` | `(1/n)*(-y/p + (1-y)/(1-p))`. |
| `loss_categorical_cross_entropy(&probs, &targets)` | `Result[Int, Str]` | `-sum(y*ln(p))`. |
| `loss_categorical_cross_entropy_grad(&probs, &targets)` | `Result[Vec[Int], Str]` | `-y/p` per class. |

Targets: MSE/MAE accept any value-scale values; hinge requires exactly
`+1000`/`-1000`; BCE requires `0`/`1000`; categorical requires a value-scale
distribution that sums to exactly `1000` (one-hot is the common case).
Probabilities are clamped into `[1, 999]` before any logarithm.

The complete error catalog is in `SPEC.md`.

## Usage

```xi
use xiom.loss;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // Predictions and targets are value-scale raw integers: 0.800 is raw 800.
  var preds = Vec[Int].new();
  preds.push(800);
  preds.push(300);
  var targets = Vec[Int].new();
  targets.push(1000);
  targets.push(0);
  match loss_binary_cross_entropy(&preds, &targets) {
    Ok(loss) => {
      io.println(convert.int_to_string(loss));   // 289910 (0.289910)
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.loss
```

Expected tail: 27 `[PASS]` lines, `xiom.loss: all tests passed`, then
`port: PASS (passed=27 failed=0 program_exit=0 exit=0)`. Verified twice with
the pinned compiler 0.62.1.

## Limitations

- **Fixed scales, fixed envelope.** Values use 3 fraction digits and losses
  6; precision below 0.001 (value) or 0.000001 (loss) is not representable.
  Entries are capped at `+-4000000000` raw and MSE additionally requires
  `|pred-target| <= 3037000499`; larger inputs return an error, never a
  wrapped result.
- **The logarithm is an approximation.** `loss_natural_log` is atanh-series
  based; the measured absolute error over the whole probability domain is
  below one unit of the 1e-6 loss scale (worst observed 0.51). It is not a
  platform libm replacement.
- **Boundary clamping biases cross-entropy.** `p = 0` evaluates as
  `p = 0.001` and `p = 1` as `p = 0.999`, so the reported loss is finite but
  clipped near the boundaries (6907755 and 1001 raw for the matching
  target). Use `loss_clip` if a different epsilon is wanted.
- **Gradients are quantized to 0.001.** MAE and hinge gradients are
  `round(1000/n)`; for `n > 2000` they round to 0, and BCE/CE gradients can
  round similarly for large `n`. They are consistent with the same rounded
  loss definition but are not exact real-valued derivatives.
- **No batch reductions across samples beyond the documented means**, no
  softmax/logits variants, no Huber, NLL, focal or triplet losses.
- Not thread-safe-free of shared state by construction (all functions are
  pure over their arguments) but there is no locking or registry either.

## Stdlib gaps observed

- Integer/fixed-point `ln`/`exp`/`pow`: the stdlib `xiom.math` family is
  `Float64`-only and returns `Float64`, so the logarithm is hand-rolled here.
- Round-half-away integer division and scaled `(a*m)/b` helpers: absent from
  the stdlib; re-implemented locally (also done by `xiom.dimred`).
- `Vec[Int]` conveniences (zeros/filled constructor, sum/reduce) and an
  integer approximate-equality test assertion are missing; tests hand-roll
  tiny helpers.
