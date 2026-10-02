# xiom.ensemble

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.1` on the XIOM registry.
> **Scope:** fixed-point ensemble combination models (hard and soft voting,
> deterministic bootstrap resampling, bagging, pairwise disagreement,
> weight normalization) over scaled integers.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.string`
> and `xiom.convert`; tests additionally use `xiom.test`, `xiom.io`,
> `xiom.string` and `xiom.string.compare`).

## What it is

`xiom.ensemble` combines the outputs of several models **without floating
point**. Every combination rule is an integer algorithm with an explicitly
documented rounding step, so results are deterministic and reproducible
across machines. The module covers:

- **hard voting** (`ensemble_hard_vote`): one class label (`Str`) per model;
  the class with the most votes wins; ties go to the class whose first
  occurrence in the input has the lowest index (documented lowest-index
  rule); per-class vote counts are reported in first-occurrence order;
- **soft voting** (`ensemble_soft_vote`, `ensemble_soft_vote_weighted`):
  one per-class probability vector per model (parallel `Vec[Int]`,
  row-major), combined by the unweighted or weighted mean; every division
  rounds half away from zero;
- **bootstrap resampling** (`ensemble_bootstrap_indices`,
  `ensemble_lcg_step`): a seeded MINSTD LCG (multiplier `48271`, modulus
  `2^31 - 1`) draws N sample indices with replacement over a dataset size;
  the same seed always yields the same vector, on every run;
- **bagging combine** (`ensemble_bagging_combine`): entry-wise mean of
  parallel result vectors, in order;
- **disagreement / diversity** (`ensemble_pair_disagreement_bps`,
  `ensemble_disagreement_bps`): pairwise prediction disagreement in basis
  points (`10000` = fully different), for one model pair or pooled over all
  unordered pairs;
- **weight normalization** (`ensemble_normalize_weights`,
  `ensemble_weight_sum`): rescales non-negative weights so they sum exactly
  to a caller scale (largest-remainder apportionment).

No `Float64`, no FFI, no I/O, no global state, no allocation beyond the
returned vectors. See `SPEC.md` for the exact combination, rounding,
validation-order and overflow rules.

## Units

| Quantity | Unit | Notes |
|---|---|---|
| class labels | `Str` | compared with `string.str_compare`, never `==` |
| probabilities | basis points (`10000` = 1.0) recommended | any common non-negative integer scale |
| disagreement | basis points | `0` = identical, `10000` = fully different |
| weights | arbitrary non-negative `Int` | normalized to an exact sum |
| predictions | `Int` class ids | equality by value |
| result vectors | `Vec[Int]`, row-major | vector `i`, entry `j` at `i * width + j` |

## API

| Function | Returns | Description |
|---|---|---|
| `ensemble_bps()` | `Int` | Basis-point scale (10000). |
| `ensemble_lcg_multiplier()` / `ensemble_lcg_modulus()` | `Int` | Bootstrap LCG constants (48271 / 2147483647). |
| `ensemble_hard_vote(&labels)` | `Result[VoteResult, Str]` | Majority tally with the lowest-index tie rule. |
| `ensemble_vote_winner(&r)` | `Str` | Winning class label. |
| `ensemble_vote_winner_count(&r)` | `Int` | Winner vote count. |
| `ensemble_vote_n_models(&r)` / `ensemble_vote_n_classes(&r)` | `Int` | Ballot and distinct-class counts. |
| `ensemble_vote_class(&r, k)` | `Str` | Class label at first-occurrence index `k`, or `""`. |
| `ensemble_vote_count(&r, k)` | `Int` | Votes for class `k`, or `0`. |
| `ensemble_vote_class_index(&r, &label)` | `Int` | First-occurrence index of a label, or `-1`. |
| `ensemble_soft_vote(&probs, n_models, n_classes)` | `Result[Vec[Int], Str]` | Per-class unweighted mean of the probability rows. |
| `ensemble_soft_vote_weighted(&probs, &weights, n_models, n_classes)` | `Result[Vec[Int], Str]` | Per-class weighted mean; divides by the weight sum. |
| `ensemble_lcg_step(state)` | `Int` | One normalized MINSTD step (KAT-friendly). |
| `ensemble_bootstrap_indices(seed, dataset_size, n_samples)` | `Result[Vec[Int], Str]` | Deterministic sample indices with replacement. |
| `ensemble_bagging_combine(&vectors, n_vectors, per_vector)` | `Result[Vec[Int], Str]` | Entry-wise mean of parallel vectors. |
| `ensemble_pair_disagreement_bps(&preds, n_models, n_samples, i, j)` | `Result[Int, Str]` | Disagreement of models `i` and `j` in basis points. |
| `ensemble_disagreement_bps(&preds, n_models, n_samples)` | `Result[Int, Str]` | Pooled mean pairwise disagreement in basis points. |
| `ensemble_weight_sum(&weights)` | `Int` | Plain arithmetic sum (no validation). |
| `ensemble_normalize_weights(&weights, scale)` | `Result[Vec[Int], Str]` | Non-negative weights summing exactly to `scale`. |

The complete error catalog is in `SPEC.md`.

## Usage

```xi
use xiom.ensemble;
use xiom.io;
use xiom.convert;
use xiom.string;
use xiom.string.compare;

fn main() -> Int {
  // Hard vote: two models say "cat", one says "dog".
  var labels = Vec[Str].new();
  labels.push("cat"); labels.push("cat"); labels.push("dog");
  let res = ensemble_hard_vote(&labels);
  if !res.is_ok { return 1; }
  let vote = res.value;
  io.println("winner: " + ensemble_vote_winner(&vote));          // cat
  io.println(convert.int_to_string(ensemble_vote_winner_count(&vote))); // 2

  // Soft vote: basis points, two models, two classes.
  var probs = Vec[Int].new();
  probs.push(9000); probs.push(1000);   // model 0
  probs.push(7000); probs.push(3000);   // model 1
  let avg = ensemble_soft_vote(&probs, 2, 2);
  if avg.is_ok {
    let a = avg.value;
    io.println(convert.int_to_string(a[0])); // 8000
  }

  // Bootstrap: the same seed gives the same indices every run.
  let idx = ensemble_bootstrap_indices(42, 100, 8);
  if idx.is_ok {
    io.println(convert.int_to_string(idx.value[0]));
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.ensemble
```

Expected tail: 24 `[PASS]` lines, `xiom.ensemble: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`. Verified with the
pinned compiler 0.62.1 (installed) and the repo stdlib.

## Limitations

- **Stacking and blending are out of scope for v0.1.0.** The registry
  placeholder reserved them, but a meta-learner API needs a training loop
  and a split protocol that this first version does not define. See the
  non-goals in `SPEC.md`.
- **Fixed-point only.** Probabilities must be scaled by the caller
  (basis points recommended); the module never sees a float.
- **No overflow detection in `ensemble_bagging_combine` and
  `ensemble_weight_sum`** (signed paths); keep the running sum inside
  `Int`. The other multiply-before-divide paths are guarded and documented.
- **Hard voting is O(n^2)** in the number of ballots (linear scan over the
  distinct classes), which is fine for the usual small ensembles.
- **The bootstrap LCG is MINSTD, not cryptographic.** It is chosen for
  reproducibility; seed and its negation produce the same stream (documented
  normalization), so prefer non-negative seeds when that matters.
- **The tie rule is first-occurrence order**, not lexicographic order; it is
  deterministic and independent of any dictionary implementation.
- **Bootstrapped dataset assembly is the caller's job**: the module returns
  the index vector only.
