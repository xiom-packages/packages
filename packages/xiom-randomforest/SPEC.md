# xiom.randomforest -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.randomforest` (`src/randomforest.xi`). Manifest: `package.xi`
(name `xiom.randomforest`, version `0.1.0`). Depends on `xiom.std` for the
manifest; the library imports `xiom.convert` only. Tests:
`tests/test_conformance.xi` (24 checks).

## 1. Scope

Integer-only, deterministic random forest classification:

- CART-style binary decision trees over an integer feature matrix;
- integer-threshold splits selected by Gini impurity in integer arithmetic;
- bootstrap sampling with a caller-seeded MINSTD LCG;
- configurable tree count, depth bound and minimum leaf size;
- majority voting for classification;
- raw and sample-weighted feature-importance counts;
- a deterministic text dump of a tree.

Pure and deterministic: no floats, no FFI, no threads, no I/O, no clock
access, no global state, no allocation beyond the returned values. All tree
traversals are iterative (explicit stacks with visit budgets); the module
contains no recursion.

## 2. Non-goals (v0.1.0)

- regression trees and leaf-value averaging;
- probability estimates / calibrated votes;
- out-of-bag error, cross-validation, holdout protocols;
- per-split feature subsampling (the `mtry` of Breiman forests);
- missing-value handling, sample weights, class weights;
- pruning, surrogate splits, multi-way splits;
- model persistence and concurrent/parallel training;
- floating-point thresholds of any kind.

## 3. Data model

`Forest` is a flat struct:

| Field | Type | Meaning |
|---|---|---|
| `n_features` | `Int` | features per row |
| `n_classes` | `Int` | number of distinct training labels |
| `classes` | `Vec[Int]` | distinct labels, first-occurrence order |
| `n_trees` | `Int` | number of trees |
| `tree_root` | `Vec[Int]` | root node index per tree |
| `nodes` | `Vec[Int]` | all nodes of all trees, flat |

Trees are appended in creation order, so tree `t` owns the node range
`tree_root[t] .. tree_root[t] + tree_n_nodes(t) - 1` (the last tree ends at
`nodes.len() / 8 - 1`). Node `k` occupies slots
`k * randomforest_node_stride() + field` with the fixed stride 8:

| Offset | Constant (private) | Meaning |
|---|---|---|
| +0 | feature | split feature, `-1` for a leaf |
| +1 | threshold | left branch when value <= threshold |
| +2 | left | left child node index, `-1` for a leaf |
| +3 | right | right child node index, `-1` for a leaf |
| +4 | label | majority label of the node |
| +5 | count | training samples at the node |
| +6 | leaf | `1` for a leaf, `0` for a split node |
| +7 | depth | root depth is 0 |

Fields are implementation detail; use the `randomforest_*` accessors. All
accessors are range-safe and return documented sentinels (`-1`, `-2`, `0`,
`false`) instead of failing.

## 4. Split rule and impurity math

### 4.1 Impurity

For a node holding `n` samples with class counts `c_k` over the forest's
class list, the Gini impurity is `1 - sum_k (c_k / n)^2`. The integer
numerator form used internally is `n^2 - sum_k c_k^2` (non-negative; `0`
exactly for a pure node).

For a candidate split into a left part with `nL` samples and squared-count
sum `A = sum_k l_k^2`, and a right part with `nR` samples and
`B = sum_k r_k^2`, the sample-weighted child impurity is

    (nL/n) * Gini(L) + (nR/n) * Gini(R)  =  1 - (A / (nL * n)) - (B / (nR * n))

Minimizing it is equivalent to maximizing `A / nL + B / nR` (`n` is fixed
for the node). The implementation scores a candidate in millionths with
truncating integer arithmetic:

    S = (A * 1000000) / nL + (B * 1000000) / nR

Larger `S` is better. Truncation can only merge near-equal scores; the
tie-break below makes the choice deterministic regardless.

### 4.2 Candidate enumeration

For each split search at a node:

1. features are enumerated in ascending index `f = 0 .. n_features - 1`;
2. for feature `f`, the node's distinct feature values are collected and
   sorted ascending with insertion sort; each value `v` is a candidate
   threshold;
3. the split `value <= v` goes left, `value > v` goes right;
4. a candidate is admissible only when `nL >= min_samples` and
   `nR >= min_samples` (so a threshold equal to the maximum value, leaving
   the right side empty, is never admissible);
5. a candidate replaces the incumbent only when its score is **strictly**
   greater. Therefore score ties (including truncation ties) keep the
   earliest candidate: lowest feature index first, then lowest threshold.

A split is accepted only if at least one admissible candidate exists;
otherwise the node becomes a leaf.

## 5. Stopping rules and labels

A node becomes a leaf when any of the following holds:

1. `depth >= max_depth` (the root is depth 0, so `max_depth = 0` yields a
   single-leaf tree);
2. the node is pure (exactly one class present);
3. `n < 2 * min_samples` (no admissible two-sided split can exist);
4. no admissible candidate split was found (section 4.2).

The node's label is the most frequent class; ties go to the class with the
lowest index in the first-occurrence class list (section 3). The same rule
labels leaves and internal nodes (the internal label is informative only and
appears in the dump).

`count` is the number of training samples at the node, bootstrap duplicates
included. The bootstrap root count of tree `t` is always `n_rows`.

A binary tree in which every split has non-empty children has at most `n`
leaves and `2n - 1` nodes for `n` root samples; the iterative builder uses
that bound as an explicit node budget (`2n + 2`) and fails closed with
`randomforest: node budget exceeded` if it is ever exceeded.

## 6. Bootstrap LCG

MINSTD (Park-Miller) linear congruential generator, constants **pinned**
(same family as `xiom.ensemble`):

| Constant | Value | Exposed by |
|---|---|---|
| multiplier | 48271 | `randomforest_lcg_multiplier()` |
| modulus | 2147483647 = 2^31 - 1 (prime) | `randomforest_lcg_modulus()` |
| normalization range | 2147483646 = modulus - 1 | internal |

Normalization (`randomforest_lcg_step`,
`randomforest_bootstrap_indices`):

1. `s0 = |seed mod 2147483646| + 1`, so `s0` is always in
   `[1, 2147483646]` for any `Int` seed (including 0 and negatives). A seed
   and its negation produce the same stream; prefer non-negative seeds.
2. Step: `s_{k+1} = (s_k * 48271) mod 2147483647`. The result is never 0
   (the modulus is prime and the multiplier is a primitive root), so the
   state stays in `[1, 2147483646]` forever.
3. Sample index `k` (1-based): `idx_k = (s_k - 1) mod dataset_size`, in
   `[0, dataset_size - 1]`.

Fixed vectors (asserted by the conformance suite):

| Call | Result |
|---|---|
| `randomforest_lcg_step(0)` | `48271` |
| `randomforest_lcg_step(1)` | `96542` |
| `randomforest_lcg_step(-1)` | `96542` (same normalized state) |
| `randomforest_lcg_step(2)` | `144813` |
| `randomforest_bootstrap_indices(1, 10, 2)` | `[1, 7]` |
| `randomforest_bootstrap_indices(0, 10, 1)` | `[0]` |
| `randomforest_bootstrap_indices(1, 1000, 8)` | first index `541` |
| `randomforest_bootstrap_indices(2, 1000, 8)` | first index `812` |

`randomforest_train` uses **one continuous stream across trees**: tree `t`
is trained on entries `t * n_rows .. (t + 1) * n_rows - 1` of
`randomforest_bootstrap_indices(seed, n_rows, n_trees * n_rows)`. With
`n_trees = 1` this is exactly `randomforest_build_tree` on
`randomforest_bootstrap_indices(seed, n_rows, n_rows)` (asserted by the
conformance suite).

## 7. Training API

`randomforest_train(features, n_rows, n_features, labels, n_trees,
max_depth, min_samples, seed)`:

1. validate the data shape (section 10);
2. validate the tree count, then the depth, then `min_samples`;
3. derive the class list in first-occurrence order;
4. for every tree, draw `n_rows` bootstrap indices from the continuous
   stream and build the tree iteratively.

`randomforest_build_tree(features, n_rows, n_features, labels, indices,
max_depth, min_samples)` builds exactly one tree on the supplied row-index
list (entries may repeat; `Ok(Forest)` has `n_trees == 1` and
`tree_root[0] == 0`). Validation order: data shape, indices (emptiness,
then range), depth, `min_samples`.

Both share one internal builder. A node is created (appended and linked to
its parent) when its frame is consumed; a frame holds
`[depth, parent, side, row indices...]` and is pushed only for an accepted
split, so the loop makes bounded progress.

## 8. Prediction and voting

Walking a tree from its root: at a split node with feature `fd` and
threshold `th`, go left when `row_features[fd] <= th` and right otherwise;
stop at the first leaf and return its label. The walk is bounded by the
node count (`guard`), so a corrupt forest cannot loop.

`randomforest_predict` tallies, for each row, one vote per tree (the tree's
leaf label mapped to its class index). The class with the most votes wins;
ties go to the lowest class index (earliest first occurrence in the
training labels). The returned value is the class label, not the index. The
per-row tally is repeated independently per row; no state carries across
rows.

## 9. Feature importance

- `randomforest_feature_importance(f)`: `out[j]` = number of split nodes
  (across all trees) whose split feature is `j`; leaves contribute nothing.
- `randomforest_feature_importance_weighted(f)`: `out[j]` = sum of
  `randomforest_node_count` over the split nodes that use feature `j`.

Both vectors have length `f.n_features`. Because an accepted split keeps at
least `min_samples >= 1` samples, the weighted count is always `>=` the raw
count. Both are deterministic functions of the trained forest.

## 10. Dump format

`randomforest_dump_tree(f, t)` returns a string, one trailing newline per
line:

    tree T: nodes=N depth=D
    [k] fF <= TH (n=C, label=L)
      [k] leaf label=L (n=C)

- the header has the tree index, its node count and its maximum depth;
- node lines are emitted in pre-order, left child first, with two spaces of
  indentation per depth level;
- a split line is `[k] fF <= TH (n=C, label=L)`; a leaf line is
  `[k] leaf label=L (n=C)`;
- integers are rendered by `xiom.convert.int_to_string`;
- the walk uses an explicit stack with a `N + 1` visit budget and fails
  closed (`randomforest: dump budget exceeded`) rather than looping.

## 11. Validation order and error catalog

First failure wins.

| Function | Order |
|---|---|
| `randomforest_bootstrap_indices` | dataset size, sample count |
| `randomforest_build_tree` | data shape, index emptiness, index range, depth, min samples |
| `randomforest_train` | data shape, tree count, depth, min samples |
| `randomforest_predict` | row count, forest feature count, dimensions, length |
| `randomforest_predict_tree_row` | tree index, row width |
| `randomforest_dump_tree` | tree index |

Data-shape order inside the common check: row count (`> 0`), feature count
(`> 0`), dataset envelope, dimensions overflow, features length, labels
length.

| Message | Trigger |
|---|---|
| `randomforest: dataset size must be positive` | bootstrap with `dataset_size <= 0` |
| `randomforest: sample count must not be negative` | bootstrap with `n_samples < 0` |
| `randomforest: row count must be positive` | `n_rows <= 0` |
| `randomforest: feature count must be positive` | `n_features <= 0` |
| `randomforest: dataset too large` | `n_rows > 1000000` |
| `randomforest: dimensions overflow` | `n_rows * n_features` would overflow `Int` |
| `randomforest: features length does not match the shape` | `features.len() != n_rows * n_features` |
| `randomforest: label count does not match row count` | `labels.len() != n_rows` |
| `randomforest: tree count must be positive` | `n_trees <= 0` |
| `randomforest: tree count exceeds the limit` | `n_trees > 100000` |
| `randomforest: max depth must not be negative` | `max_depth < 0` |
| `randomforest: max depth exceeds the limit` | `max_depth > 64` |
| `randomforest: min samples must be positive` | `min_samples < 1` |
| `randomforest: sample indices must not be empty` | `build_tree` with no indices |
| `randomforest: sample index out of range` | an index outside `[0, n_rows)` |
| `randomforest: tree index out of range` | `t` outside `[0, n_trees)` |
| `randomforest: feature count does not match the forest` | row width `!= f.n_features` |
| `randomforest: forest has no features` | defensive: `f.n_features <= 0` |
| `randomforest: leaf label missing from the class list` | defensive: corrupt forest |
| `randomforest: label missing from the class list` | defensive: corrupt input |
| `randomforest: node budget exceeded` | defensive: builder bound violated |
| `randomforest: internal stack underflow` | defensive: iterative walk invariant |
| `randomforest: dump budget exceeded` | defensive: dump visit bound violated |

## 12. Envelope, complexity and overflow

Envelope (enforced by validation):

| Quantity | Range |
|---|---|
| `n_rows` | 1 .. 1000000 |
| `n_features` | >= 1, with `n_rows * n_features` fitting `Int` |
| `n_trees` | 1 .. 100000 |
| `max_depth` | 0 .. 64 |
| `min_samples` | >= 1 |
| feature values, labels | any `Int` |

With `n_rows <= 1000000`, `A <= nL^2 <= 10^12` and `A * 1000000 <= 10^18
< Int_max`, so the score computation cannot overflow inside the envelope.
The bootstrap multiply `s * 48271 < 2^31 * 48271` is far below `Int_max`.
No silent overflow path exists; the only unbounded-looking arithmetic
(`n_rows * n_features`) is guarded before use.

Complexity:

| Function | Cost |
|---|---|
| `randomforest_bootstrap_indices` | O(k) |
| build (per node) | O(n_features * distinct_values * n * n_classes) |
| `randomforest_train` | n_trees * build |
| `randomforest_predict` | O(n_rows * n_trees * tree depth) |
| importance | O(n_nodes) |
| dump | O(nodes of tree + text size) |

The split search is a simple rescan per candidate threshold (no
sort-based incremental histograms); this is deliberate for v0.1.0 and
documented as the main scaling limitation.

## 13. Compatibility notes (toolchain v0.62.x)

- **No recursion anywhere.** During the port the toolchain did not
  terminate on a recursive user function (minimal case: a self-calling
  `fn f(n: Int) -> Int`), so every traversal is iterative with an explicit
  stack and a visit budget.
- **No `Str` comparisons** are performed in the library; the test suite
  routes every string equality through `string.str_compare` (BUG 17 lowers
  `==` on `Str` values read from `Vec` elements to a pointer comparison).
- **Every `Vec[Int]` element read binds a typed local first.**
- **No `&struct.field` is passed to a reference parameter**; node reads use
  direct indexing, and `randomforest_predict` copies the class list into a
  local before passing it to a helper.
- **`Ok` / `Err` construction is confined to leaf helpers**
  (`_ok_forest` / `_err_forest` / `_ok_ints` / `_err_ints` / `_ok_int` /
  `_err_int` / `_ok_str` / `_err_str`).
- **Free functions only**: no methods, generics, callbacks or indexed
  function dispatch; `Forest` carries one flat `Vec[Int]` instead of
  parallel vectors or `Vec[StructType]`.
- One frame stack (`Vec[Vec[Int]]`) is used by the builder; the dump uses
  two mirrored `Vec[Int]` stacks pushed and popped in lockstep.

## 14. Test plan

`tests/test_conformance.xi` (24 checks, all passing):

| # | Check |
|---|---|
| 1 | constant accessors; LCG step KAT (48271 / 96542 / 96542 / 144813) |
| 2 | bootstrap determinism and index range |
| 3 | bootstrap fixed vectors `[1,7]` / `[0]` / 541 / 812; seed normalization |
| 4 | bootstrap validation (size 0, negative count, empty draw) |
| 5 | separable fixture: root `f0 <= 3`, pure children, counts, classes |
| 6 | `max_depth` 0 and `min_samples` 5 leaf out; `min_samples` 2 splits |
| 7 | constant feature cannot split; class tie picks the first class |
| 8 | split-score tie keeps the lowest threshold |
| 9 | equal features split on the lowest feature index |
| 10 | first-occurrence class order; majority tie picks the first; `class_index` |
| 11 | perfect predictions on the separable fixture; single tree agrees |
| 12 | predict validation (row count, length, tree index, row width) |
| 13 | accessor range safety (all sentinels) |
| 14 | `build_tree` validation (shape, indices, depth, min samples) |
| 15 | same-seed training determinism and structural consistency |
| 16 | pinned seeds 1 vs 2 produce different trees ({1,1} vs {0,1}) |
| 17 | `train` configuration validation |
| 18 | importance values; constant noise feature ranks last; weighted >= raw |
| 19 | exact dump text; bad tree index errors |
| 20 | vote ties (and a real majority) on hand-built forests |
| 21 | `predict` equals the manually tallied per-tree majority |
| 22 | `build_tree` honors explicit subset indices |
| 23 | one-tree `train` equals `build_tree` on its bootstrap indices |
| 24 | every tree obeys the depth bound and carries valid labels |
