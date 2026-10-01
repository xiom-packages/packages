# xiom.svm -- Specification

Version 0.1.0. Conformance suite: `tests/test_conformance.xi` (23 checks).
Pinned toolchain: compiler `v0.62.2`, `xiom.std >=0.60.0 <1.0.0`.

`xiom.svm` is a deterministic, fixed-point **binary linear** support vector
machine. It performs hinge-loss sub-gradient training over scaled integers,
predicts `+1` / `-1`, counts support vectors in a margin band, scores
accuracy and dumps the model as text. There is no floating point, no FFI and
no I/O in the library.

## 1. Fixed-point arithmetic

### 1.1 Scale

Every real quantity is an `Int` at scale `1e-4`:

```
stored = real * 10000        (real = stored / 10000)
```

`svm_scale()` returns `10000`. Features, weights, the bias, decision scores
and margins share that scale. The caller scales features before calling and
unscales weights / scores afterwards. Scaling is exact only when the real
value has at most four decimal places; this module does not detect lossy
scaling.

### 1.2 Rounding rules

Two division forms are used; both are written in explicit q/r form so the
result does not depend on the compiler's floor-vs-truncate convention for
`/` and `%`.

- **Truncation toward zero** (`_svm_div_trunc`): if the remainder has the
  sign of the dividend, the quotient from `/` is already truncated; if the
  remainder has the sign of the divisor (floor convention), the quotient is
  moved one step back toward zero. Used by:
  - the decision score: `trunc(w . x / 10000)`,
  - every weight update: `trunc(eta_t * y * x_j / 10000)`,
  - the learning-rate schedule: `trunc(eta0 * 10000 / (10000 + decay*t))`.
- **Half away from zero** (`_svm_div_round`): truncate, then move one step
  away from zero when `2 * |remainder| >= divisor`. Used only by
  `svm_accuracy`, whose numerator is small (`correct * 10000 <= 10^10`), so
  the doubling cannot overflow.

All other arithmetic is exact `Int` arithmetic.

### 1.3 Overflow guards

- Every multiply-before-divide is bounded by validation:
  `eta0 * |x_j| <= 1e9 * 1e9 = 1e18 < 2^63 - 1`, and
  `decay * step <= 1e9 * 1e9 = 1e18`.
- `_svm_add_ok(a, b)` keeps every accumulator in the symmetric envelope
  `[-INT_MAX, INT_MAX]` (`INT_MAX = 9223372036854775807`): the value
  `INT_MIN` is never produced. It guards the dot-product accumulator,
  score + bias, and every weight / bias update.
- `_svm_dot_weights` additionally checks each product before multiplying:
  the term is rejected when `|w_j| > INT_MAX / |x_j|` (`x_j != 0`).
- A rejected operation returns `Err("svm: dot product overflows")`,
  `Err("svm: score overflows")`, `Err("svm: weight update overflows")` or
  `Err("svm: bias update overflows")`. Nothing wraps silently.

No division by zero is reachable: `_SVM_SCALE > 0` and the eta denominator
`10000 + decay*step >= 10000`.

## 2. Data model

`SvmModel` is a flat struct; fields are implementation detail, use the
accessors.

| Field | Type | Meaning |
|---|---|---|
| `n_features` | `Int` | features per row (`>= 1`) |
| `n_rows` | `Int` | training rows (`>= 1`) |
| `epochs` | `Int` | training epochs (`1 .. svm_max_epochs()`) |
| `learning_rate` | `Int` | `eta0` at scale |
| `decay` | `Int` | decay coefficient |
| `seed` | `Int` | the raw seed passed to `svm_train` |
| `weights` | `Vec[Int]` | one scale-`1e-4` weight per feature; weight `j` pairs with feature column `j` |
| `bias` | `Int` | scale-`1e-4` bias added to every score |

Weight `j` and feature column `j` are a mirrored pair: every function that
walks rows (`svm_predict`, `svm_margins`, `svm_accuracy`,
`svm_support_vector_count`) reads feature `r * n_features + j` against
weight `j`.

## 3. Shuffling LCG

MINSTD (Park-Miller), constants exposed by `svm_lcg_multiplier()` (`48271`)
and `svm_lcg_modulus()` (`2147483647 = 2^31 - 1`).

- **Normalization** (`_svm_norm_lcg_state`): any `Int` seed becomes
  `|seed mod 2147483646| + 1`, in `[1, 2147483646]`. Seeds `s` and `-s`
  produce the same stream; `0` maps to `1` before the first step.
- **Step**: `state' = (state * 48271) mod 2147483647`, always landing back
  in `[1, 2147483646]` (the modulus is prime and 48271 is a primitive
  root).
- `svm_lcg_step(state)` first normalizes its argument, then steps, so
  `svm_lcg_step(0) = 48271` and `svm_lcg_step(1) = 96542`.
- **Fisher-Yates** (`_svm_shuffle`): for `i = n-1` down to `1`, advance the
  state once and set `j = (state - 1) mod (i + 1)`, then swap
  `order[i]` and `order[j]`. Starting from the identity order this yields a
  permutation of `0 .. n-1`; the loop strictly decreases `i`, so it always
  terminates after exactly `n - 1` swaps.
- **Continuity**: `svm_train` seeds one stream once
  (`state = _svm_norm_lcg_state(seed)`) and threads the advanced state from
  one epoch's shuffle into the next; the epoch-`e` order therefore depends
  on `seed` and all previous epochs. `svm_shuffle_indices(seed, n)` is the
  one-shuffle special case.
- The state is threaded through return values, never through a `&mut Int`
  parameter: on v0.62.2 a `&mut Int` argument was observed to be passed as
  a value, silently ignoring the seed (see section 11).

## 4. Training (`svm_train`)

```
svm_train(features, n_rows, n_features, labels,
          epochs, eta0, decay, seed) -> Result[SvmModel, Str]
```

### 4.1 Validation order

1. `n_rows > 0` -> `"svm: row count must be positive"`
2. `n_features > 0` -> `"svm: feature count must be positive"`
3. `n_rows <= svm_max_rows()` -> `"svm: dataset too large"`
4. `n_features <= svm_max_features()` ->
   `"svm: feature count exceeds the limit"`
5. `n_rows <= INT_MAX / n_features` -> `"svm: dimensions overflow"`
6. `features.len() == n_rows * n_features` ->
   `"svm: features length does not match the shape"`
7. every `|features[k]| <= svm_max_feature()` ->
   `"svm: feature magnitude exceeds the limit"`
8. `labels.len() == n_rows` ->
   `"svm: label count does not match row count"`
9. every label is exactly `+1` or `-1` ->
   `"svm: labels must be +1 or -1"`
10. `epochs > 0` -> `"svm: epoch count must be positive"`
11. `epochs <= svm_max_epochs()` -> `"svm: epoch count exceeds the limit"`
12. `eta0 > 0` -> `"svm: initial learning rate must be positive"`
13. `eta0 <= svm_max_eta()` ->
    `"svm: initial learning rate exceeds the limit"`
14. `decay >= 0` -> `"svm: decay must not be negative"`
15. `decay <= svm_max_decay()` -> `"svm: decay exceeds the limit"`

### 4.2 Initialization

```
w_j = 0 for every feature j;  b = 0;  t = 0
state = _svm_norm_lcg_state(seed)
order = [0, 1, ..., n_rows - 1]
```

### 4.3 Epoch loop

For `e = 0 .. epochs - 1`:

1. Re-shuffle `order` in place with `_svm_shuffle`, threading `state`.
2. For `r = 0 .. n_rows - 1`, let `i = order[r]`, `x = row i`,
   `y = labels[i]`:

   ```
   score  = trunc(dot(w, x) / 10000) + b          (guarded)
   margin = y * score                              (y is +1 or -1)
   if margin < 10000:
     eta_t = trunc(eta0 * 10000 / (10000 + decay * t))
     w_j   = w_j + trunc(eta_t * y * x_j / 10000)  for every j  (guarded)
     b     = b + eta_t * y                                      (guarded)
     t     = t + 1
   ```

Every loop bound is explicit and monotone (`e` increases, `r` increases,
the swap loop's `i` decreases); each inner pass is exactly `n_rows` visits
and each shuffle exactly `n - 1` swaps, so training always terminates.

### 4.4 Schedule

`eta_t = trunc(eta0 * 10000 / (10000 + decay * t))`, with `t` counting
**applied updates** (updates where `margin < 10000`), not visited samples.
`t = 0` gives `eta0` exactly; `decay = 0` keeps `eta0` forever. The public
`svm_eta(eta0, decay, step)` exposes the same function with validation
(`step` in `[0, 1000000000]`).

### 4.5 Result

`Ok(SvmModel)` with the trained weights and bias. Mid-training guard
failures return `Err` and no partial model. Complexity:
`O(epochs * n_rows * n_features)`.

### 4.6 Model accessors

| Function | Returns |
|---|---|
| `svm_n_features(m)` | feature count |
| `svm_n_rows(m)` | training row count |
| `svm_epochs(m)` | epoch count |
| `svm_initial_rate(m)` | `eta0` |
| `svm_decay(m)` | decay |
| `svm_seed(m)` | raw seed |
| `svm_bias(m)` | bias |
| `svm_weight(m, j)` | weight `j`, or `0` when `j` is out of range |
| `svm_weights(m)` | copy of the weight vector |

## 5. Scoring and margins

```
svm_score(m, row_features) -> Result[Int, Str]
  = trunc(sum_j w_j * x_j / 10000) + b
```

- `row_features.len()` must equal `svm_n_features(m)` ->
  `"svm: feature count does not match the model"`.
- every `|row_features[j]| <= svm_max_feature()` ->
  `"svm: feature magnitude exceeds the limit"`.
- dot-product and score sums are guarded (section 1.3).

```
svm_margin(m, row_features, label) -> Result[Int, Str] = label * score
```

`label` must be `+1` or `-1` -> `"svm: label must be +1 or -1"`. A positive
margin means the row is on the correct side; the canonical hyperplane has
margin `10000`.

```
svm_margins(m, features, n_rows, labels) -> Result[Vec[Int], Str]
```

Validates the matrix (row/feature counts, limits, length, magnitudes) and
the labels, then returns one signed margin per row in input order.
Complexity: `O(n_rows * n_features)`.

## 6. Prediction (`svm_predict`)

Validates the matrix against `svm_n_features(m)`. Per row:

```
+1  when score >= 0
-1  otherwise
```

The score-`0` tie goes to `+1` (documented, deterministic). Returns one
label per row in input order. Complexity: `O(n_rows * n_features)`.

## 7. Accuracy (`svm_accuracy`)

Validates the matrix and the labels. Counts rows where the predicted sign
(section 6) equals the label, then returns

```
round_half_away_from_zero(correct * 10000 / n_rows)
```

in basis points (`10000` = all correct, `6667` = two of three). Complexity:
`O(n_rows * n_features)`.

## 8. Support-vector counting (`svm_support_vector_count`)

Validates the matrix and the labels, then `band`:

- `band >= 0` -> `"svm: band must not be negative"`
- `band <= INT_MAX - 10000` -> `"svm: band exceeds the limit"`

A row is counted when its margin lies in the band around the canonical
margin:

```
10000 - band <= margin <= 10000 + band
```

`band = 0` counts only rows exactly on the canonical hyperplane; a large
band counts every row (including negative margins). Complexity:
`O(n_rows * n_features)`.

## 9. Model dump (`svm_dump`)

Deterministic text, one trailing newline per line:

```
svm model: scale=10000 features=F epochs=E lr=L decay=D seed=Z rows=R
w0=<weight 0>
w1=<weight 1>
...
bias=<bias>
```

Pinned example (one row `x = 1.0`, `y = +1`, one epoch, `eta0 = 1.0`,
`decay = 0`, seed `1`):

```
svm model: scale=10000 features=1 epochs=1 lr=10000 decay=0 seed=1 rows=1
w0=10000
bias=10000
```

Two models trained with the same `(data, epochs, eta0, decay, seed)` dump
identical text.

## 10. Envelope

| Quantity | Range | Failure |
|---|---|---|
| feature magnitude | `<= 1000000000` (`100000.0`) | `"svm: feature magnitude exceeds the limit"` |
| `n_rows` | `1 .. 1000000` | `"svm: row count must be positive"` / `"svm: dataset too large"` |
| `n_features` | `1 .. 4096` | `"svm: feature count must be positive"` / `"svm: feature count exceeds the limit"` |
| `epochs` | `1 .. 1000` | `"svm: epoch count must be positive"` / `"... exceeds the limit"` |
| `eta0` | `1 .. 1000000000` | `"svm: initial learning rate must be positive"` / `"... exceeds the limit"` |
| `decay` | `0 .. 1000000000` | `"svm: decay must not be negative"` / `"svm: decay exceeds the limit"` |
| `svm_eta` step | `0 .. 1000000000` | `"svm: step must not be negative"` / `"svm: step exceeds the limit"` |
| support band | `0 .. INT_MAX - 10000` | `"svm: band must not be negative"` / `"svm: band exceeds the limit"` |
| shuffle size | `1 .. 1000000` | `"svm: shuffle size must be positive"` / `"... exceeds the limit"` |
| dot/score accumulators | `[-INT_MAX, INT_MAX]` | `"svm: dot product overflows"` / `"svm: score overflows"` |
| weight/bias updates | `[-INT_MAX, INT_MAX]` | `"svm: weight update overflows"` / `"svm: bias update overflows"` |

## 11. Determinism and implementation notes

- For fixed inputs, `svm_train` is a pure function: same
  `(data, epochs, eta0, decay, seed)` -> identical `SvmModel`, weights,
  bias, margins, predictions, accuracy and dump text. Tests pin two
  dumps, four shuffles and the MINSTD KATs.
- Different seeds generally produce different shuffles and models; the
  suite checks that seed 9 yields a different pinned model from seed 7.
- Because the LCG stream is continuous across epochs, changing `epochs`
  changes all orders after the first shuffle, not just the number of
  passes.
- Compiler v0.62.2 workarounds used by this module:
  - **no `&mut Int` parameters** (state is returned instead; a `&mut Int`
    argument was observed to arrive as a value, ignoring seed changes);
  - **no `&struct.field` passed to a reference parameter** (the weights are
    copied to a local via `svm_weights` before a dataset pass);
  - **no `Vec[Str]`** (the dump concatenates `Str` values; `Vec[Str].push`
    mis-lowers on this toolchain);
  - every `Vec[Int]` element read binds a typed local first;
  - `Ok` / `Err` construction is confined to the leaf helpers at the end of
    the module;
  - no methods, generics, lambdas, `self`, or function tables; the model is
    a flat struct with a plain `Vec[Int]`.

## 12. Non-goals for v0.1.0

Kernels (polynomial, RBF), multi-class decomposition (one-vs-rest,
one-vs-one), SMO, support vector regression, regularization (`L1`/`L2`),
model serialization, and multi-threaded training are out of scope. The
registry placeholder reserved these APIs; this version deliberately keeps
one binary linear model with a fully pinned integer contract.
