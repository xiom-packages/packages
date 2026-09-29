# xiom.ensemble -- Specification

Status: `incubating` (implemented, harness-green on compiler 0.62.1, not
published).
Module: `xiom.ensemble` (`src/ensemble.xi`). Manifest: `package.xi` (name
`xiom.ensemble`, version `0.1.0`). Depends on `xiom.std` for the manifest;
the library imports `xiom.string` and `xiom.convert` and uses no other
module. Tests: `tests/test_conformance.xi` (24 checks).

## 1. Scope

Integer-only ensemble combination:

- hard voting over per-model class labels (`Str`) with a deterministic
  lowest-index tie rule and per-class vote counts;
- soft voting over per-model per-class probability vectors (row-major
  `Vec[Int]`), unweighted and weighted, with explicit rounding;
- deterministic bootstrap resampling with a seeded MINSTD LCG;
- bagging combine (entry-wise mean of parallel result vectors);
- pairwise disagreement / diversity in basis points, per pair and pooled;
- non-negative weight normalization to an exact target sum.

Pure and deterministic: no floats, no FFI, no I/O, no clock access, no
global state, no allocation beyond the returned vectors.

## 2. Non-goals (v0.1.0)

- stacking (stacked generalization) and holdout blending / meta-learners;
- random forests, boosting, out-of-bag error estimation, feature sampling;
- accuracy-weighted or learned model weights (weights are caller-supplied);
- probability calibration, normalization or clamping;
- floating-point probabilities of any kind;
- secure or high-quality randomness: the LCG is a reproducibility device;
- model persistence, training loops, dataset assembly, parallelism;
- overflow detection on the signed bagging and weight-sum paths
  (the envelope below is a caller contract).

## 3. Data model

`VoteResult` is a flat struct with parallel vectors:

| Field | Type | Meaning |
|---|---|---|
| `winner` | `Str` | winning class label |
| `winner_count` | `Int` | votes for the winner |
| `classes` | `Vec[Str]` | distinct labels, first-occurrence order |
| `counts` | `Vec[Int]` | parallel to `classes`: votes per class |
| `n_models` | `Int` | number of ballots |
| `n_classes` | `Int` | `classes.len()` |

Fields are implementation detail; use the `ensemble_vote_*` accessors.
Range-safe accessors return `""` / `0` / `-1` for out-of-range queries
instead of failing: `ensemble_vote_class`, `ensemble_vote_count`,
`ensemble_vote_class_index`.

## 4. Hard voting

`ensemble_hard_vote(labels)`:

1. Reject an empty input: `ensemble: labels must not be empty`.
2. Walk the ballots left to right. For each label, find the first distinct
   class whose label satisfies `string.str_compare(known, label) == 0`
   (never `==`; see section 11); if none, append a new class with count 1,
   otherwise increment that class's count.
3. The winner is the class with the maximum count. **Tie rule (lowest
   index):** when several classes share the maximum, the class with the
   lowest index in `classes` wins, i.e. the class whose first occurrence in
   `labels` is earliest. The result is deterministic and independent of any
   dictionary order.

`classes` is in first-occurrence order and `counts` is built in the same
loop (parallel pushes), so `counts[k]` always belongs to `classes[k]`.
Complexity: O(n^2) compares in the number of ballots.

## 5. Soft voting

Layout: `probs[i * n_classes + j]` is model `i`'s probability for class
`j`. Probabilities must be non-negative; the scale is the caller's (basis
points, i.e. 10000 = 1.0, are recommended and used by the examples).

- **Unweighted** (`ensemble_soft_vote`):
  `out[j] = round_half_away(sum_i probs[i, j] / n_models)`.
- **Weighted** (`ensemble_soft_vote_weighted`):
  `out[j] = round_half_away(sum_i (probs[i, j] * weights[i]) / sum_i
  weights[i])`. Weights must be non-negative, at least one positive; a zero
  weight drops the model, and a positive weight scales it. The divisor is
  the exact integer weight total.

Rounding: `round_half_away(a / b)` for `b > 0` is truncating division `q =
a / b`, remainder `r = a % b`; if `2 * |r| >= b` the result moves one unit
away from zero (`q + 1` for `a >= 0`, `q - 1` for `a < 0`), else `q`. This
is the exact documented rounding for every division in the module.

## 6. Bootstrap resampling (LCG)

MINSTD (Park-Miller) linear congruential generator, constants **pinned**:

| Constant | Value | Exposed by |
|---|---|---|
| multiplier | 48271 | `ensemble_lcg_multiplier()` |
| modulus | 2147483647 = `2^31 - 1` (prime) | `ensemble_lcg_modulus()` |
| normalization range | 2147483646 = modulus - 1 | internal |

Normalization (`ensemble_lcg_step`, `ensemble_bootstrap_indices`):

1. `s0 = |seed mod 2147483646| + 1`, so `s0` is always in
   `[1, 2147483646]` for any `Int` seed (including 0 and negatives). A seed
   and its negation produce the same stream; prefer non-negative seeds.
2. Step: `s_{k+1} = (s_k * 48271) mod 2147483647`. The result is never 0
   (the modulus is prime and the multiplier is a primitive root), so the
   state stays in `[1, 2147483646]` forever.
3. Bootstrap index `k` (1-based): `idx_k = (s_k - 1) mod dataset_size`, in
   `[0, dataset_size - 1]`.

Fixed vectors (asserted by the conformance suite):

| Call | Result |
|---|---|
| `ensemble_lcg_step(0)` | `48271` |
| `ensemble_lcg_step(1)` | `96542` |
| `ensemble_lcg_step(-1)` | `96542` (same normalized state) |
| `ensemble_lcg_step(2)` | `144813` |
| `ensemble_bootstrap_indices(1, 10, 2)` | `[1, 7]` |
| `ensemble_bootstrap_indices(0, 10, 1)` | `[0]` |
| `ensemble_bootstrap_indices(1, 1000, 8)` | first index `541` |
| `ensemble_bootstrap_indices(2, 1000, 8)` | first index `812` |

`n_samples = 0` is a valid request and yields an empty vector; a negative
count is an error. The generator is deterministic across runs and
platforms and is **not** cryptographic.

## 7. Bagging combine

`ensemble_bagging_combine(vectors, n_vectors, per_vector)`:
`out[j] = round_half_away(sum_i vectors[i * per_vector + j] / n_vectors)`.
Entries are signed; the combine is the entry-wise mean in order. No
overflow detection: the caller keeps the running sum inside `Int` (see
section 10).

## 8. Disagreement / diversity

Predictions are integer class ids: `predictions[i * n_samples + s]`.

- `ensemble_pair_disagreement_bps(preds, n_models, n_samples, i, j)`:
  count `c` = number of positions where models `i` and `j` differ;
  `Ok(round_half_away(c * 10000 / n_samples))`. `0` = identical,
  `10000` = fully different. Symmetric in `i` and `j`; `i == j` is
  rejected.
- `ensemble_disagreement_bps(preds, n_models, n_samples)`: with `P =
  n_models * (n_models - 1) / 2` pairs and `D` = total disagreeing counts
  over all unordered pairs, `Ok(round_half_away(D * 10000 / (P *
  n_samples)))`. **Pooled before rounding**: this is not the mean of the
  per-pair rounded values. Requires `n_models >= 2`.

Worked example (3 models x 4 samples, used by the tests): model A
`[1,1,1,1]`, model B `[1,1,0,0]`, model C `[0,0,0,0]` yields pair values
5000 (A,B), 10000 (A,C), 5000 (B,C) and pooled mean 6667.

## 9. Weight normalization

`ensemble_normalize_weights(weights, scale)` returns non-negative entries
that sum **exactly** to `scale` (largest-remainder / Hamilton
apportionment):

1. Reject empty input, non-positive `scale`, negative weights, a weight-sum
   overflow or a zero sum.
2. `total = sum_i weights[i]`; for each `i` with a non-zero weight, guard
   `scale <= Int_max / weights[i]` (product overflow).
3. `base_i = floor(weights[i] * scale / total)`,
   `rem_i = (weights[i] * scale) mod total`.
4. `need = scale - sum_i base_i`, an integer in `[0, n - 1]` because the
   remainders are the fractional parts of `scale * total / total`. Give one
   unit each to the `need` entries with the largest remainders; equal
   remainders favor the lowest index. Zero weights stay zero.

`ensemble_weight_sum(weights)` is the plain arithmetic sum: no validation,
no overflow detection, `0` for an empty vector.

## 10. Rounding, validation order and overflow

Division in XIOM v0.62.x truncates toward zero; `%` follows the dividend's
sign. Every rounding step is explicit (`_div_round`, section 5). Only
`_div_round` uses the doubling `2 * |r|`; its denominators (`n_models`,
`n_vectors`, weight totals, `n_samples`) are small counts, so the doubling
cannot overflow in this module.

Validation order (first failure wins):

| Function | Order |
|---|---|
| `ensemble_hard_vote` | emptiness |
| `ensemble_soft_vote` | model count, class count, dimensions, length, per-entry non-negativity / sum overflow (row scan) |
| `ensemble_soft_vote_weighted` | model count, class count, dimensions, probability length, weight length, weights (non-negative / sum), probabilities and weighted products / sums |
| `ensemble_bootstrap_indices` | dataset size, sample count |
| `ensemble_bagging_combine` | vector count, vector length, dimensions, length |
| `ensemble_pair_disagreement_bps` | model count, sample count, dimensions, length, index range (i then j), distinctness, scale |
| `ensemble_disagreement_bps` | model count (>= 2), sample count, dimensions, length, pair-count overflow, count / scale overflow |
| `ensemble_normalize_weights` | emptiness, scale, per-weight non-negativity / sum overflow, zero sum, product overflow |

Overflow handling:

| Path | Guarded? | Contract |
|---|---|---|
| uniform soft-vote class sum | yes (`probability sum overflows`) | non-negative entries, sum <= `Int_max` |
| weighted product `p * w` | yes (`weighted product overflows`) | each product <= `Int_max` |
| weighted sum | yes (`weighted sum overflows`) | total <= `Int_max` |
| weight total | yes (`weight sum overflows`) | total <= `Int_max` |
| weight `w * scale` | yes (`weight scale overflows`) | product <= `Int_max` |
| disagreement count / bps / pairs | yes (`disagreement ... overflows`) | counts fit; guarded |
| bagging entry sum | **no** | `|sum_i v[i, j]|` must fit `Int` |
| `ensemble_weight_sum` | **no** | running total must fit `Int` |
| `_div_round` doubling | **no** | denominators small by construction |

## 11. Compatibility notes (compiler 0.62.1)

- `==` on `Str` values read from `Vec` elements is a pointer comparison
  (BUG 17). Every class-label comparison and every error-message check uses
  `string.str_compare` / `compare.str_compare`, with both sides bound to
  typed locals first.
- Every `Vec[Int]` / `Vec[Str]` element read binds the element to a typed
  local before use.
- `Ok` / `Err` are only constructed in the leaf helpers
  (`_ok_vote` / `_err_vote` / `_ok_ints` / `_err_ints` / `_ok_int` /
  `_err_int`).
- Free functions only: no methods, generics, callbacks or indexed function
  dispatch; `VoteResult` carries parallel `Vec` fields.
- Parallel vectors (`classes` / `counts`) are pushed in the same loop.

## 12. Error catalog

| Message | Trigger |
|---|---|
| `ensemble: labels must not be empty` | hard vote with no ballots |
| `ensemble: model count must be positive` | `n_models <= 0` (soft votes, pair disagreement) |
| `ensemble: class count must be positive` | `n_classes <= 0` (soft votes) |
| `ensemble: dimensions overflow` | shape product overflows `Int` (soft votes, bagging, disagreement) |
| `ensemble: probability length does not match the shape` | `probs.len() != n_models * n_classes` |
| `ensemble: probabilities must not be negative` | a negative probability (soft votes) |
| `ensemble: probability sum overflows` | uniform class sum exceeds `Int_max` |
| `ensemble: weight count does not match model count` | `weights.len() != n_models` |
| `ensemble: weights must not be negative` | negative weight (weighted vote, normalization) |
| `ensemble: weight sum overflows` | running weight total exceeds `Int_max` |
| `ensemble: weight sum must be positive` | zero total (weighted vote, normalization) |
| `ensemble: weighted product overflows` | `p * w > Int_max` |
| `ensemble: weighted sum overflows` | weighted class sum exceeds `Int_max` |
| `ensemble: dataset size must be positive` | bootstrap with `dataset_size <= 0` |
| `ensemble: sample count must not be negative` | bootstrap with `n_samples < 0` |
| `ensemble: vector count must be positive` | bagging with `n_vectors <= 0` |
| `ensemble: vector length must be positive` | bagging with `per_vector <= 0` |
| `ensemble: vectors length does not match the shape` | `vectors.len() != n_vectors * per_vector` |
| `ensemble: sample count must be positive` | disagreement with `n_samples <= 0` |
| `ensemble: predictions length does not match the shape` | `preds.len() != n_models * n_samples` |
| `ensemble: model index out of range` | `i` or `j` outside `[0, n_models)` |
| `ensemble: model indices must be distinct` | `i == j` |
| `ensemble: disagreement scale overflows` | `n_samples` or `D` too large for `* 10000` |
| `ensemble: disagreement count overflows` | `D` exceeds `Int_max` while accumulating |
| `ensemble: need at least 2 models` | pooled mean with `n_models < 2` |
| `ensemble: weights must not be empty` | normalization with no weights |
| `ensemble: scale must be positive` | normalization with `scale <= 0` |
| `ensemble: weight scale overflows` | `w * scale > Int_max` |
| `ensemble: weight normalization failed` | defensive invariant break (unreachable) |

## 13. Test plan

`tests/test_conformance.xi` (24 checks, all passing):

| # | Check |
|---|---|
| 1 | constant accessors (10000 / 48271 / 2147483647) |
| 2 | hard-vote majority, first-occurrence classes, counts |
| 3 | tie rule: `[a,b]`, `[b,a]`, `[b,b,a,a]`, `[x,y,x,y,z]` |
| 4 | empty input error; single-ballot success |
| 5 | accessor range safety; label index via `str_compare` |
| 6 | uniform soft vote averages |
| 7 | uniform soft vote half-away rounding (0.5 -> 1, 1.5 -> 2) |
| 8 | uniform soft vote validation errors |
| 9 | weighted soft vote values (25 / 150) |
| 10 | weighted half-away rounding; zero weight drops a model |
| 11 | weighted validation errors (length, negatives, zero sum) |
| 12 | LCG KAT: 48271, 96542, 96542 for -1, 144813, normalization |
| 13 | bootstrap determinism and index range |
| 14 | bootstrap seed difference; fixed vectors `[1,7]`, `[0]`, 541/812 |
| 15 | bootstrap validation (size 0, negative count, empty draw) |
| 16 | bagging mean, half-away rounding, signed mean (-2/3 -> -1) |
| 17 | bagging validation (counts, shape, dimensions overflow) |
| 18 | disagreement values 5000 / 10000 / 5000 and pooled 6667 |
| 19 | disagreement validation (indices, shape, < 2 models) |
| 20 | normalization exact sums (3334/3333/3333, 67/33, 7/0, 1/0) |
| 21 | normalization validation (empty, scale, zero sum, negative) |
| 22 | normalization overflow guards (scale, sum) |
| 23 | `ensemble_weight_sum` plain sums |
| 24 | soft-vote overflow guards (dimensions, sums, product) |
