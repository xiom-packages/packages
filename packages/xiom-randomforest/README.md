# xiom.randomforest

> **Status:** `incubating` -- conformance-tested (24/24); not yet published on the XIOM registry.
> **Scope:** deterministic CART-style decision-tree ensemble over integer
> features and labels: integer-threshold Gini splits, caller-seeded bootstrap
> resampling, configurable tree count / depth / min-samples, majority voting,
> feature-importance counts and a text tree dump.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.convert`
> for decimal rendering; tests additionally use `xiom.test`, `xiom.io`,
> `xiom.string` and `xiom.string.compare`).

## What it is

`xiom.randomforest` trains and applies a random forest **without floating
point**. Every tree is a CART-style binary tree over an integer feature
matrix; every split tests one feature against an integer threshold; every
decision (which split, which label, which class wins) is an integer
comparison with an explicitly documented tie-break, so results are
deterministic and reproducible across machines. The module covers:

- **training** (`randomforest_train`): bootstrap-sampled trees with
  configurable count, depth bound and minimum leaf size; each tree is built
  from a caller-seeded MINSTD LCG stream;
- **single-tree training** (`randomforest_build_tree`): the same builder on
  an explicit row-index list (no bootstrap), exposed for pinned subsamples
  and cross-checking;
- **bootstrap** (`randomforest_bootstrap_indices`,
  `randomforest_lcg_step`): the seeded MINSTD LCG (multiplier `48271`,
  modulus `2^31 - 1`) draws sample indices with replacement;
- **prediction** (`randomforest_predict`,
  `randomforest_predict_tree_row`): per-row majority vote over the trees,
  ties to the lowest first-occurrence class;
- **feature importance** (`randomforest_feature_importance`,
  `randomforest_feature_importance_weighted`): raw split counts and
  sample-weighted split credits per feature;
- **tree dump** (`randomforest_dump_tree`): a deterministic text rendering
  of one tree.

No `Float64`, no FFI, no threads, no I/O, no global state, no allocation
beyond the returned values. All traversals are iterative with explicit
stacks and visit budgets. See `SPEC.md` for the exact split rule, impurity
math, validation order, tie-breaks and envelope.

## API

| Function | Returns | Description |
|---|---|---|
| `randomforest_lcg_multiplier()` / `randomforest_lcg_modulus()` | `Int` | Bootstrap LCG constants (48271 / 2147483647). |
| `randomforest_max_depth_limit()` / `randomforest_max_rows()` / `randomforest_max_trees()` | `Int` | Configuration envelope (64 / 1000000 / 100000). |
| `randomforest_node_stride()` | `Int` | Slots per node in the flat node vector (8). |
| `randomforest_lcg_step(state)` | `Int` | One normalized MINSTD step (KAT-friendly). |
| `randomforest_bootstrap_indices(seed, dataset_size, n_samples)` | `Result[Vec[Int], Str]` | Deterministic sample indices with replacement. |
| `randomforest_train(&features, n_rows, n_features, &labels, n_trees, max_depth, min_samples, seed)` | `Result[Forest, Str]` | Train a forest of `n_trees` bootstrap trees. |
| `randomforest_build_tree(&features, n_rows, n_features, &labels, &indices, max_depth, min_samples)` | `Result[Forest, Str]` | Train one tree on an explicit row-index list. |
| `randomforest_n_trees(&f)` / `randomforest_n_features(&f)` / `randomforest_n_classes(&f)` / `randomforest_n_nodes(&f)` | `Int` | Forest shape accessors. |
| `randomforest_class(&f, k)` | `Int` | Class label at first-occurrence index `k` (0 out of range). |
| `randomforest_class_index(&f, label)` | `Int` | First-occurrence index of a label, or `-1`. |
| `randomforest_tree_root(&f, t)` | `Int` | Root node index of tree `t`, or `-1`. |
| `randomforest_tree_n_nodes(&f, t)` / `randomforest_tree_depth(&f, t)` | `Int` | Tree size and depth (`0` / `-1` out of range). |
| `randomforest_is_leaf(&f, k)` | `Bool` | True when node `k` is a leaf. |
| `randomforest_node_feature(&f, k)` | `Int` | Split feature (`-1` leaf, `-2` out of range). |
| `randomforest_node_threshold(&f, k)` | `Int` | Split threshold. |
| `randomforest_node_left(&f, k)` / `randomforest_node_right(&f, k)` | `Int` | Child node index, or `-1`. |
| `randomforest_node_label(&f, k)` / `randomforest_node_count(&f, k)` / `randomforest_node_depth(&f, k)` | `Int` | Majority label, sample count, depth. |
| `randomforest_predict_tree_row(&f, t, &row_features)` | `Result[Int, Str]` | One tree's prediction for one row. |
| `randomforest_predict(&f, &features, n_rows)` | `Result[Vec[Int], Str]` | Majority-vote predictions for `n_rows` rows. |
| `randomforest_feature_importance(&f)` / `randomforest_feature_importance_weighted(&f)` | `Vec[Int]` | Split counts / sample-weighted split credits per feature. |
| `randomforest_dump_tree(&f, t)` | `Result[Str, Str]` | Deterministic text dump of tree `t`. |

The complete error catalog is in `SPEC.md`.

## Usage

```xi
use xiom.randomforest;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // 8 rows, 2 features, row-major; labels 0 for the first four rows, 1 after.
  var features = Vec[Int].new();
  features.push(0); features.push(7);
  features.push(1); features.push(6);
  features.push(2); features.push(5);
  features.push(3); features.push(4);
  features.push(4); features.push(3);
  features.push(5); features.push(2);
  features.push(6); features.push(1);
  features.push(7); features.push(0);
  var labels = Vec[Int].new();
  labels.push(0); labels.push(0); labels.push(0); labels.push(0);
  labels.push(1); labels.push(1); labels.push(1); labels.push(1);

  let trained = randomforest_train(&features, 8, 2, &labels, 8, 4, 1, 42);
  if !trained.is_ok { return 1; }
  let forest = trained.value;

  let pred = randomforest_predict(&forest, &features, 8);
  if pred.is_ok {
    let p = pred.value;
    io.println(convert.int_to_string(p[0]));   // 0
    io.println(convert.int_to_string(p[7]));   // 1
  }
  let imp = randomforest_feature_importance(&forest);
  io.println(convert.int_to_string(imp[0]));   // feature 0 carries the splits
  io.println(randomforest_dump_tree(&forest, 0).value);
  return 0;
}
```

## Install / publish

```
xiom pkg install xiom.randomforest@0.1.0     # consumer, from the XIOM registry
xiom pkg publish                             # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Until `v0.1.0` is published, build from this repository:

```
.\scripts\port.ps1 -Package xiom.randomforest
```

Expected tail: 24 `[PASS]` lines, `xiom.randomforest: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Integer features and labels only.** Thresholds are feature values; for
  real-valued inputs the caller must quantize first and document the
  rounding. The module never sees a float.
- **Split scoring is scaled integer arithmetic** (millionths, truncating
  division); see `SPEC.md` for the exact formula, the derivation, and the
  documented tie-break (lowest feature index, then lowest threshold).
- **Training is fixture-scale by design**: the split search rescans the node
  sample per candidate threshold (no sort-based incremental scan), so cost
  grows with rows, features and distinct values. The documented envelope is
  1,000,000 rows / 100,000 trees / depth 64.
- **No out-of-bag error, no probability estimates, no regression mode, no
  feature subsampling** in v0.1.0 (non-goals in `SPEC.md`).
- **The bootstrap LCG is MINSTD, not cryptographic.** It is chosen for
  reproducibility; a seed and its negation produce the same stream
  (documented normalization), so prefer non-negative seeds when that
  matters.
- **Ties are resolved by first-occurrence order**, never by lexicographic or
  dictionary order: leaf labels use the lowest class index, forest votes use
  the lowest class index.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
