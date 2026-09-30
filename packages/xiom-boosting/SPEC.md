# xiom.boosting -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.boosting` (`src/boosting.xi`). Manifest: `package.xi`
(name `xiom.boosting`, version `0.1.0`). Depends on `xiom.std` for the
manifest; the library imports `xiom.convert` only. Tests:
`tests/test_conformance.xi` (20 checks).

## 1. Scope

Integer fixed-point, deterministic gradient boosting for regression:

- a fixed-point scale of `10000` units = `1.0` (one unit is `1e-4`);
- depth-limited regression trees (depth 0..2) over an integer feature
  matrix, with integer-threshold splits;
- residual updates with a basis-point learning rate (`10000 == 1.0`);
- optional caller-seeded row subsampling (with replacement) and feature
  subsampling (without replacement);
- staged predictions and a per-stage mean-squared-error trace;
- split-node feature-importance counts;
- a deterministic text dump of the additive model.

Pure and deterministic: no floats, no FFI, no threads, no I/O, no clock
access, no global state, no allocation beyond the returned values. All tree
traversals are iterative (explicit stacks with node budgets); the module
contains no recursion.

## 2. Non-goals (v0.1.0)

- classification, logistic/multiclass objectives, ranking;
- regression trees deeper than depth 2;
- second-order gradients, regularized leaf values (XGBoost-style `lambda`);
- column/row weights, sample weights, monotonic constraints;
- early stopping, cross-validation, holdout protocols;
- learning-rate schedules or momentum;
- model persistence and concurrent/parallel training;
- floating-point arithmetic of any kind.

## 3. Fixed point and rounding

All values are `Int` in fixed-point units of `1e-4` (`boosting_scale()` is
`10000`). Rounding rule, applied everywhere: **integer division truncates
toward zero** (v0.62.x semantics). Specifically:

- the intercept is `floor(mean(targets))` toward zero:
  `base = sum(targets) / n_rows`;
- a leaf value is the truncated mean residual: `sum / n` toward zero;
- the split score uses truncated means: `floor(SL/nL)` and `floor(SR/nR)`;
- a stage contribution is `floor(lr_bp * leaf_value / 10000)`;
- a loss value is `floor(sum_i (pred_i - target_i)^2 / n_rows)`.

## 4. Data model

`Model` is a flat struct:

| Field | Type | Meaning |
|---|---|---|
| `n_features` | `Int` | features per row |
| `n_stages` | `Int` | number of boosting stages (trees) |
| `lr_bp` | `Int` | learning rate in basis points |
| `base` | `Int` | fixed-point intercept |
| `tree_root` | `Vec[Int]` | root node index per stage |
| `nodes` | `Vec[Int]` | all nodes of all stages, flat |

Trees are appended in stage order, so stage `t` owns the node range
`tree_root[t] .. tree_root[t] + tree_n_nodes(t) - 1` (the last stage ends at
`nodes.len() / 8 - 1`). Node `k` occupies slots
`k * boosting_node_stride() + field` with the fixed stride 8:

| Offset | Constant (private) | Meaning |
|---|---|---|
| +0 | feature | split feature, `-1` for a leaf |
| +1 | threshold | left branch when value <= threshold |
| +2 | left | left child node index, `-1` for a leaf |
| +3 | right | right child node index, `-1` for a leaf |
| +4 | value | leaf value; node mean residual for a split node |
| +5 | count | training samples at the node |
| +6 | leaf | `1` for a leaf, `0` for a split node |
| +7 | depth | root depth is 0 |

Fields are implementation detail; use the `boosting_*` accessors. All
accessors are range-safe and return documented sentinels (`-1`, `-2`, `0`,
`false`) instead of failing.

## 5. Base learner (regression tree)

### 5.1 Stopping

A node becomes a leaf when either holds:

1. `depth >= max_depth` (the root is depth 0, so `max_depth = 0` yields a
   single-leaf tree);
2. the node holds fewer than two samples.

The minimum leaf size is fixed at 1: a candidate split is admissible only
when both sides are non-empty.

### 5.2 Split search and score

At a splittable node:

1. features are enumerated in the stage's selected-feature order (all
   features in ascending index order when `feature_subsample == 0`);
2. for feature `f`, the node's distinct feature values are collected and
   sorted ascending with insertion sort; each value `v` is a candidate
   threshold;
3. the split `value <= v` goes left, `value > v` goes right;
4. a candidate is admissible only when `nL >= 1` and `nR >= 1`;
5. the score is `S = floor(SL/nL) * SL + floor(SR/nR) * SR`, where `SL`
   (resp. `SR`) is the residual sum on the left (resp. right) side. This is
   the truncated-mean form of the between-group squared sum; larger `S` is
   better and it approximates the within-node SSE reduction
   `SL^2/nL + SR^2/nR`;
6. a candidate replaces the incumbent only when it is the first admissible
   candidate or its score is **strictly** greater. Therefore score ties
   keep the earliest candidate: earliest feature in the selected order,
   then lowest threshold.

A split is accepted only if at least one admissible candidate exists;
otherwise the node becomes a leaf. The node's `value` field is the
truncated mean residual of its sample (used directly as a leaf value, and
kept as an informational mean on split nodes).

A binary tree in which every split has non-empty children has at most `n`
leaves and `2n - 1` nodes for `n` root samples; the iterative builder uses
that bound as an explicit node budget (`2n + 2`) and fails closed with
`boosting: node budget exceeded` if it is ever exceeded.

## 6. Boosting

1. The intercept is the truncated global mean `base = sum(targets)/n_rows`.
2. Predictions start at `base` and residuals at `targets - base`.
3. For every stage `s = 0 .. n_stages - 1`:
   1. draw the row subsample (section 7) and select the feature subset
      (section 7);
   2. build one regression tree on the selected rows and features against
      the current residuals (section 5);
   3. for every row, compute the reached leaf value on that tree and update
      `pred += floor(lr_bp * leaf_value / 10000)`; refresh the residual
      `residual = target - pred`.
4. `lr_bp` is validated to `1..=10000`, so the shrinkage factor is in
   `(0, 1]` and the total squared error never increases: the staged loss
   trace is non-increasing.

The working residual is checked against a documented envelope
(section 12); a breach fails closed with `boosting: residual overflow`.

## 7. Subsampling and seeds

One MINSTD (Park-Miller) LCG drives both subsamples, with constants
**pinned** (same family as `xiom.ensemble` and `xiom.randomforest`):

| Constant | Value | Exposed by |
|---|---|---|
| multiplier | 48271 | `boosting_lcg_multiplier()` |
| modulus | 2147483647 = 2^31 - 1 (prime) | `boosting_lcg_modulus()` |
| normalization range | 2147483646 = modulus - 1 | internal |

Normalization (`boosting_lcg_step`, `boosting_subsample_indices`):

1. `s0 = |seed mod 2147483646| + 1`, so `s0` is always in
   `[1, 2147483646]` for any `Int` seed (including 0 and negatives). A seed
   and its negation produce the same stream; prefer non-negative seeds.
2. Step: `s_{k+1} = (s_k * 48271) mod 2147483647`. The result is never 0,
   so the state stays in `[1, 2147483646]` forever.
3. Sample index `k` (1-based): `idx_k = (s_k - 1) mod dataset_size`.

Per stage the stream is consumed in this fixed order:

1. **rows** (only when `row_subsample > 0`): draw `row_subsample` indices
   with replacement via `(state - 1) mod n_rows`, one LCG step each, in
   draw order;
2. **features** (only when `feature_subsample > 0`): choose
   `feature_subsample` distinct features without replacement by a partial
   Fisher-Yates: for `k = 0 .. feature_subsample - 1`, step the LCG and
   swap `pool[k]` with `pool[k + (state mod (n_features - k))]`; the
   selected subset is `pool[0 .. feature_subsample - 1]`.

Subsample counts: `0` means "use all" (rows in natural order, features in
ascending index order) and consumes no LCG steps; otherwise the count must
be in `1..=n_rows` (resp. `1..=n_features`). When both counts are `0` the
LCG is never consulted, so the model is identical for every seed
(asserted by the conformance suite).

Fixed vectors (asserted by the suite, shared with `xiom.randomforest`):

| Call | Result |
|---|---|
| `boosting_lcg_step(0)` | `48271` |
| `boosting_lcg_step(1)` | `96542` |
| `boosting_lcg_step(-1)` | `96542` (same normalized state) |
| `boosting_lcg_step(2)` | `144813` |
| `boosting_subsample_indices(1, 10, 2)` | `[1, 7]` |
| `boosting_subsample_indices(0, 10, 1)` | `[0]` |

## 8. Prediction and loss

Walking a tree from its root: at a split node with feature `fd` and
threshold `th`, go left when `row_features[fd] <= th` and right otherwise;
stop at the first leaf and return its value. The walk is bounded by the node
count, so a corrupt model cannot loop.

- `boosting_predict_row(m, row)`: `base + sum_t floor(lr_bp *
  leaf_value(t, row) / 10000)`.
- `boosting_predict(m, features, n_rows)`: the same, once per row.
- `boosting_predict_staged(m, features, n_rows, n_stages)`: a vector of
  length `n_rows * n_stages`, laid out **stage-major**: entry
  `s * n_rows + r` is row `r`'s running prediction after `s + 1` stages
  (stage 0's block already includes the base). The last block equals
  `boosting_predict` restricted to `n_stages` stages.
- `boosting_loss_trace(m, features, n_rows, targets)`: a vector of length
  `m.n_stages + 1`; `trace[0]` is the MSE of the intercept alone, `trace[s]`
  the MSE after `s` stages, each computed as
  `floor(sum_i (pred_i - target_i)^2 / n_rows)` in squared fixed-point units
  (`1e-8`).

## 9. Feature importance

`boosting_feature_importance(m)` returns a vector of length `m.n_features`;
entry `j` is the number of split nodes (across all stages) whose split
feature is `j`. Leaves contribute nothing. The entries sum to the total
number of split nodes. It is a deterministic function of the trained model.

## 10. Dump format

`boosting_dump(m)` returns a string, one trailing newline per line:

    model: stages=S features=F lr_bp=L base=B
    tree T: nodes=N depth=D
    [k] fF <= TH (n=C, value=V)
      [k] leaf value=V (n=C)

- the header line renders the model shape and the intercept;
- each stage emits a `tree T: ...` line followed by its node lines;
- node lines are emitted in pre-order, left child first, with two spaces of
  indentation per depth level;
- a split line is `[k] fF <= TH (n=C, value=V)`; a leaf line is
  `[k] leaf value=V (n=C)`;
- integers are rendered by `xiom.convert.int_to_string`;
- each walk uses an explicit stack with an `N + 1` visit budget and fails
  closed (`boosting: dump budget exceeded`) rather than looping.

## 11. Validation order and error catalog

First failure wins.

| Function | Order |
|---|---|
| `boosting_subsample_indices` | dataset size, sample count |
| `boosting_train` | data shape (row count, feature count, dataset envelope, dimensions, features length, targets length, target range), stage count, depth, learning rate, row subsample, feature subsample |
| `boosting_predict` | row count, model feature count, dimensions, length |
| `boosting_predict_row` | row width |
| `boosting_predict_staged` | row count, model feature count, stage count (`> 0`), stage count (`<= n_stages`), dimensions, length |
| `boosting_loss_trace` | row count, model feature count, dimensions, length, target count, target range |

| Message | Trigger |
|---|---|
| `boosting: dataset size must be positive` | subsample with `dataset_size <= 0` |
| `boosting: sample count must not be negative` | subsample with `n_samples < 0` |
| `boosting: row count must be positive` | `n_rows <= 0` |
| `boosting: feature count must be positive` | `n_features <= 0` |
| `boosting: dataset too large` | `n_rows > 4096` |
| `boosting: dimensions overflow` | `n_rows * n_features` would overflow `Int` |
| `boosting: features length does not match the shape` | `features.len() != n_rows * n_features` |
| `boosting: target count does not match row count` | `targets.len() != n_rows` |
| `boosting: target out of range` | `\|target\| > 100000` |
| `boosting: stage count must be positive` | `n_stages <= 0` |
| `boosting: stage count exceeds the limit` | `n_stages > 64` |
| `boosting: max depth must not be negative` | `max_depth < 0` |
| `boosting: max depth exceeds the limit` | `max_depth > 2` |
| `boosting: learning rate must be positive` | `lr_bp < 1` |
| `boosting: learning rate exceeds the limit` | `lr_bp > 10000` |
| `boosting: row subsample must not be negative` | `row_subsample < 0` |
| `boosting: row subsample exceeds the row count` | `row_subsample > n_rows` |
| `boosting: feature subsample must not be negative` | `feature_subsample < 0` |
| `boosting: feature subsample exceeds the feature count` | `feature_subsample > n_features` |
| `boosting: model has no features` | defensive: `m.n_features <= 0` |
| `boosting: stage count exceeds the model` | `n_stages > m.n_stages` in `predict_staged` |
| `boosting: feature count does not match the model` | row width `!= m.n_features` |
| `boosting: residual overflow` | defensive: working residual envelope |
| `boosting: loss overflow` | squared-error difference or sum envelope |
| `boosting: node budget exceeded` | defensive: builder bound violated |
| `boosting: internal stack underflow` | defensive: iterative walk invariant |
| `boosting: dump budget exceeded` | defensive: dump visit bound violated |

## 12. Envelope, complexity and overflow

Envelope (enforced by validation):

| Quantity | Range |
|---|---|
| `n_rows` | 1 .. 4096 |
| `n_features` | >= 1, with `n_rows * n_features` fitting `Int` |
| `n_stages` | 1 .. 64 |
| `max_depth` | 0 .. 2 |
| `lr_bp` | 1 .. 10000 |
| `row_subsample` | 0 or 1 .. `n_rows` |
| `feature_subsample` | 0 or 1 .. `n_features` |
| targets | `\|target\| <= 100000` |
| feature values | any `Int` |

Overflow safety. With `|target| <= M = 100000` and `lr_bp <= 10000`, the
squared error never increases, so every working residual stays within
`sqrt(n_rows) * 2M <= 64 * 200000 = 1.28e7` (far inside the documented
`_BST_RESIDUAL_MAX = 3e7`, which is the fail-closed guard). For a node
sample of `nL <= 4096` rows, the score terms satisfy
`floor(SL/nL) * SL <= 4096 * (3e7)^2 = 3.7e18 < Int_max`, and the leaf
`lr_bp * value <= 10000 * 3e7 = 3e11`. The loss helper additionally guards
each squared difference (`<= 3e9`) and the accumulated sum. The bootstrap
multiply `s * 48271 < 2^31 * 48271` is far below `Int_max`. No silent
overflow path exists inside the envelope.

Complexity:

| Function | Cost |
|---|---|
| `boosting_subsample_indices` | O(k) |
| build (per node) | O(selected_features * distinct_values * n) |
| `boosting_train` | n_stages * build |
| `boosting_predict` | O(n_rows * n_stages * tree depth) |
| `boosting_predict_staged` | O(n_stages * n_rows * tree depth) |
| `boosting_loss_trace` | O(n_stages * n_rows * tree depth) |
| importance | O(n_nodes) |
| dump | O(n_nodes + text size) |

The split search is a simple rescan per candidate threshold (no sort-based
incremental histograms); this is deliberate for v0.1.0 and documented as the
main scaling limitation.

## 13. Compatibility notes (toolchain v0.62.2)

- **No recursion anywhere.** Every traversal is iterative with an explicit
  stack and a visit budget.
- **No `Str` comparisons** are performed in the library; the test suite
  routes every string equality through `string.str_compare`.
- **Every `Vec[Int]` element read binds a typed local first.**
- **No `&struct.field` is passed to a reference parameter**; node reads use
  direct indexing, and helpers that need a model take `&Model`.
- **`Ok` / `Err` construction is confined to leaf helpers**
  (`_ok_model` / `_err_model` / `_ok_ints` / `_err_ints` / `_ok_int` /
  `_err_int` / `_ok_str` / `_err_str`).
- **Free functions only**: no methods, generics, callbacks or indexed
  function dispatch; `Model` carries one flat `Vec[Int]` instead of parallel
  vectors or `Vec[StructType]`.
- One frame stack (`Vec[Vec[Int]]`) is used by the builder; the dump uses
  two mirrored `Vec[Int]` stacks pushed and popped in lockstep.

## 14. Test plan

`tests/test_conformance.xi` (20 checks, all passing):

| # | Check |
|---|---|
| 1 | constant accessors; LCG step KAT (48271 / 96542 / 96542 / 144813) |
| 2 | subsample determinism and index range |
| 3 | subsample fixed vectors `[1,7]` / `[0]`; seed normalization |
| 4 | subsample validation (size 0, negative count, empty draw) |
| 5 | perfect fit: base 5000, predictions equal targets, loss `[25000000, 0]` |
| 6 | stump structure: 3 nodes, `f0 <= 3`, pure children, importance |
| 7 | exact dump text |
| 8 | learning-rate effect: `lr=5000` gives `2500/7500` and a larger loss |
| 9 | staged loss: `[25000000, 6250000, 1562500]`, strictly decreasing |
| 10 | staged predictions end at the full prediction |
| 11 | prediction validation (row count, length, stage bounds, row width) |
| 12 | `train` validates stages, depth and learning rate |
| 13 | `train` validates the subsample counts |
| 14 | `train` validates the data shape and target range |
| 15 | row subsampling is deterministic for one seed |
| 16 | full-data training is independent of the seed |
| 17 | `max_depth` 0 yields one leaf; `max_depth` 2 recurses once |
| 18 | accessor range safety (all sentinels) |
| 19 | feature importance counts exactly the split nodes |
| 20 | loss-trace validation; `predict_row` matches `predict` |
