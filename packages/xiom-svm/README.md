# xiom.svm

> **Status:** `incubating` -- conformance-tested (23/23); not yet published on the XIOM registry.
> **Scope:** a deterministic, fixed-point linear support vector machine
> (hinge-loss sub-gradient training, seeded LCG shuffling, decaying learning
> rate, decision scores, margin-band support-vector counting, accuracy) over
> scaled integers.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.convert`;
> tests additionally use `xiom.test`, `xiom.io`, `xiom.string` and
> `xiom.string.compare`).

## What it is

`xiom.svm` trains a binary linear SVM **without floating point**. Every real
quantity is an `Int` at a fixed scale of `1e-4` (`10000` = `1.0`): feature
values, weights, the bias and decision scores. Training is online hinge-loss
sub-gradient descent over a per-epoch Fisher-Yates shuffle drawn from one
caller-seeded MINSTD LCG stream, with a decaying learning rate. Results are
bit-for-bit reproducible for a given `(data, epochs, eta0, decay, seed)`, on
every run and platform. The module covers:

- **training** (`svm_train`): zero-initialised weights and bias, shuffled
  online updates, learning-rate decay per applied update, labels exactly
  `+1` / `-1`;
- **shuffling** (`svm_shuffle_indices`, `svm_lcg_step`): a seeded MINSTD LCG
  (multiplier `48271`, modulus `2^31 - 1`) drives a Fisher-Yates shuffle that
  is continuous across epochs inside training;
- **learning-rate schedule** (`svm_eta`): `eta_t = trunc(eta0 * 10000 /
  (10000 + decay * t))`, `t` counting applied updates;
- **scoring and margins** (`svm_score`, `svm_margin`, `svm_margins`):
  `score = trunc(w . x / 10000) + b`, `margin = y * score`;
- **prediction** (`svm_predict`): `+1` when the score is `>= 0`, else `-1`;
- **accuracy** (`svm_accuracy`): correct fraction in basis points,
  rounded half away from zero;
- **support-vector counting** (`svm_support_vector_count`): rows whose
  margin lies in the band `|margin - 10000| <= band`;
- **model dump** (`svm_dump`): deterministic text rendering of the model.

No `Float64`, no `Vec[Float64]`, no FFI, no I/O, no global state. See
`SPEC.md` for the exact update rule, rounding, validation-order and overflow
rules.

## Units

| Quantity | Unit | Notes |
|---|---|---|
| features `x` | fixed-point scale `1e-4` | `15000` = `1.5`; `\|x\| <= 1000000000` |
| weights `w`, bias `b` | fixed-point scale `1e-4` | same scale as features |
| decision score | fixed-point scale `1e-4` | `trunc(w . x / 10000) + b` |
| margin | fixed-point scale `1e-4` | `label * score`; canonical margin `10000` |
| labels | `Int` | exactly `+1` or `-1` |
| learning rate `eta0`, decay | fixed-point scale `1e-4` / raw | `eta0` in `[1, 1e9]`, decay in `[0, 1e9]` |
| accuracy | basis points (`10000` = 1.0) | rounded half away from zero |
| support band | fixed-point scale `1e-4` | non-negative |

## API

| Function | Returns | Description |
|---|---|---|
| `svm_scale()` | `Int` | Fixed-point scale (10000). |
| `svm_lcg_multiplier()` / `svm_lcg_modulus()` | `Int` | Shuffle LCG constants (48271 / 2147483647). |
| `svm_max_feature()` / `svm_max_rows()` / `svm_max_features()` | `Int` | Documented envelope limits. |
| `svm_max_epochs()` / `svm_max_eta()` / `svm_max_decay()` | `Int` | Documented envelope limits. |
| `svm_lcg_step(state)` | `Int` | One normalized MINSTD step (KAT-friendly). |
| `svm_shuffle_indices(seed, n)` | `Result[Vec[Int], Str]` | Deterministic permutation of `0 .. n-1`. |
| `svm_eta(eta0, decay, step)` | `Result[Int, Str]` | Learning rate at applied update `step`. |
| `svm_train(&features, n_rows, n_features, &labels, epochs, eta0, decay, seed)` | `Result[SvmModel, Str]` | Train a linear SVM. |
| `svm_n_features(&m)` / `svm_n_rows(&m)` / `svm_epochs(&m)` | `Int` | Model shape. |
| `svm_initial_rate(&m)` / `svm_decay(&m)` / `svm_seed(&m)` | `Int` | Training hyperparameters. |
| `svm_weight(&m, j)` | `Int` | Weight `j`, or `0` out of range. |
| `svm_weights(&m)` | `Vec[Int]` | Copy of the weight vector. |
| `svm_bias(&m)` | `Int` | Bias term. |
| `svm_score(&m, &row)` | `Result[Int, Str]` | Decision score of one row. |
| `svm_margin(&m, &row, label)` | `Result[Int, Str]` | Signed margin of one labeled row. |
| `svm_predict(&m, &features, n_rows)` | `Result[Vec[Int], Str]` | One `+1` / `-1` label per row. |
| `svm_margins(&m, &features, n_rows, &labels)` | `Result[Vec[Int], Str]` | Signed margin per row. |
| `svm_accuracy(&m, &features, n_rows, &labels)` | `Result[Int, Str]` | Accuracy in basis points. |
| `svm_support_vector_count(&m, &features, n_rows, &labels, band)` | `Result[Int, Str]` | Rows inside the margin band. |
| `svm_dump(&m)` | `Str` | Deterministic model text. |

The complete error catalog is in `SPEC.md`.

## Usage

```xi
use xiom.svm;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // One labeled row at scale 1e-4: x = 1.0, y = +1.
  var x = Vec[Int].new();
  x.push(10000);
  var y = Vec[Int].new();
  y.push(1);

  // One epoch, eta0 = 1.0, no decay, seed 1.
  let trained = svm_train(&x, 1, 1, &y, 1, 10000, 0, 1);
  if !trained.is_ok { return 1; }
  let m = trained.value;

  io.println(convert.int_to_string(svm_weight(&m, 0)));  // 10000
  io.println(convert.int_to_string(svm_bias(&m)));       // 10000
  io.println(svm_dump(&m));
  // svm model: scale=10000 features=1 epochs=1 lr=10000 decay=0 seed=1 rows=1
  // w0=10000
  // bias=10000

  // The same seed reproduces the same model byte for byte.
  let again = svm_train(&x, 1, 1, &y, 1, 10000, 0, 1);
  if again.is_ok {
    io.println(svm_dump(&again.value));
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.svm -TimeoutSec 60
```

Expected tail: 23 `[PASS]` lines, `xiom.svm: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`. Verified with the
pinned compiler 0.62.2 (installed) and the repo stdlib.

## Limitations

- **Fixed-point only.** The caller scales every feature by `1e-4`; the
  module never sees a float. Feature magnitudes above `svm_max_feature()`
  (`100000.0`) are rejected.
- **Binary linear classification only.** Kernels, multi-class
  decomposition (one-vs-rest / one-vs-one), SMO, SVR and model
  serialization are out of scope for v0.1.0 (the registry placeholder
  reserved them).
- **No regularization term.** The update is the plain hinge-loss
  sub-gradient; weights can grow while a row stays inside the margin, and
  a score outside the documented envelope fails closed with
  `svm: dot product overflows` rather than wrapping.
- **The LCG is MINSTD, not cryptographic.** It is chosen for
  reproducibility; a seed and its negation produce the same shuffle
  (documented normalization), so prefer non-negative seeds when that
  matters.
- **Scoring copies the weight vector** into a local before each dataset
  pass (a v0.62.2 `&struct.field` lowering workaround), so a full pass is
  `O(n_features)` extra memory once per call, not per row.
- **Scores tie at `0`.** The prediction rule is `score >= 0 -> +1`; a row
  exactly on the hyperplane is classified `+1` (documented, deterministic).
