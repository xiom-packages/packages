# xiom.boosting

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.0` on the XIOM registry.
> **Scope:** deterministic gradient boosting over integer data: depth-1/2
> regression stumps, fixed-point residual updates, a basis-point learning
> rate, caller-seeded row/feature subsampling, staged predictions and a
> per-stage loss trace, feature-importance counts and a text model dump.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.convert`
> for decimal rendering; tests additionally use `xiom.test`, `xiom.io`,
> `xiom.string` and `xiom.string.compare`).

## What it is

`xiom.boosting` trains and applies an additive gradient-boosted model
**without floating point**. Every target, residual, prediction and leaf value
is an `Int` in fixed-point units of `1e-4` (`boosting_scale() == 10000`), and
every division truncates toward zero (documented per step in `SPEC.md`).
Each stage fits a small regression tree (depth 0..2) to the current residuals
and updates every row by `floor(lr_bp * leaf_value / 10000)`, where `lr_bp`
is the learning rate in basis points (`10000 == 1.0`, capped at `10000`).
Because the shrinkage never exceeds `1.0`, the total squared error never
increases, so the staged loss trace is monotone. The module covers:

- **training** (`boosting_train`): base intercept + `n_stages` shrunk trees,
  optional row subsampling (with replacement) and feature subsampling
  (partial Fisher-Yates, without replacement) from one caller-seeded MINSTD
  LCG stream;
- **subsampling** (`boosting_subsample_indices`, `boosting_lcg_step`): the
  seeded MINSTD LCG (multiplier `48271`, modulus `2^31 - 1`);
- **prediction** (`boosting_predict`, `boosting_predict_row`,
  `boosting_predict_staged`): full, single-row and per-stage predictions;
- **loss** (`boosting_loss_trace`): mean squared error after `0..n_stages`
  stages, in squared fixed-point units;
- **feature importance** (`boosting_feature_importance`): split-node counts
  per feature;
- **model dump** (`boosting_dump`): a deterministic text rendering of the
  additive model.

No `Float64`, no FFI, no threads, no I/O, no global state, no allocation
beyond the returned values. All traversals are iterative with explicit
stacks and node budgets. See `SPEC.md` for the exact split rule, residual
math, seed use, validation order, tie-breaks, dump rules and envelope.

## API

| Function | Returns | Description |
|---|---|---|
| `boosting_scale()` / `boosting_bps()` | `Int` | Fixed-point / basis-point scale (10000). |
| `boosting_lcg_multiplier()` / `boosting_lcg_modulus()` | `Int` | Subsampling LCG constants (48271 / 2147483647). |
| `boosting_max_depth_limit()` / `boosting_max_rows()` / `boosting_max_stages()` | `Int` | Configuration envelope (2 / 4096 / 64). |
| `boosting_lr_max()` / `boosting_value_max()` | `Int` | Learning-rate cap (10000 bps) / target bound (100000). |
| `boosting_node_stride()` | `Int` | Slots per node in the flat node vector (8). |
| `boosting_lcg_step(state)` | `Int` | One normalized MINSTD step (KAT-friendly). |
| `boosting_subsample_indices(seed, dataset_size, n_samples)` | `Result[Vec[Int], Str]` | Deterministic sample indices with replacement. |
| `boosting_train(&features, n_rows, n_features, &targets, n_stages, max_depth, lr_bp, row_subsample, feature_subsample, seed)` | `Result[Model, Str]` | Train the additive model. |
| `boosting_n_stages(&m)` / `boosting_n_features(&m)` / `boosting_lr_bp(&m)` / `boosting_base(&m)` / `boosting_n_nodes(&m)` | `Int` | Model shape accessors. |
| `boosting_tree_root(&m, t)` | `Int` | Root node index of stage `t`, or `-1`. |
| `boosting_tree_n_nodes(&m, t)` / `boosting_tree_depth(&m, t)` | `Int` | Stage tree size and depth (`0` / `-1` out of range). |
| `boosting_is_leaf(&m, k)` | `Bool` | True when node `k` is a leaf. |
| `boosting_node_feature(&m, k)` | `Int` | Split feature (`-1` leaf, `-2` out of range). |
| `boosting_node_threshold(&m, k)` | `Int` | Split threshold. |
| `boosting_node_left(&m, k)` / `boosting_node_right(&m, k)` | `Int` | Child node index, or `-1`. |
| `boosting_node_value(&m, k)` / `boosting_node_count(&m, k)` / `boosting_node_depth(&m, k)` | `Int` | Leaf value / node mean, sample count, depth. |
| `boosting_predict_row(&m, &row_features)` | `Result[Int, Str]` | Full-model prediction for one row. |
| `boosting_predict(&m, &features, n_rows)` | `Result[Vec[Int], Str]` | Full-model predictions for `n_rows` rows. |
| `boosting_predict_staged(&m, &features, n_rows, n_stages)` | `Result[Vec[Int], Str]` | Stage-major running predictions after each stage. |
| `boosting_loss_trace(&m, &features, n_rows, &targets)` | `Result[Vec[Int], Str]` | MSE after `0..n_stages` stages. |
| `boosting_feature_importance(&m)` | `Vec[Int]` | Split-node counts per feature. |
| `boosting_dump(&m)` | `Result[Str, Str]` | Deterministic text dump of the model. |

The complete error catalog is in `SPEC.md`.

## Usage

```xi
use xiom.boosting;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // 8 rows, 1 feature, fixed-point targets: 0.0 for the first four rows,
  // 1.0 (10000 units) for the last four.
  var features = Vec[Int].new();
  features.push(0); features.push(1); features.push(2); features.push(3);
  features.push(4); features.push(5); features.push(6); features.push(7);
  var targets = Vec[Int].new();
  targets.push(0); targets.push(0); targets.push(0); targets.push(0);
  targets.push(10000); targets.push(10000); targets.push(10000); targets.push(10000);

  let trained = boosting_train(&features, 8, 1, &targets, 4, 1, 10000, 0, 0, 42);
  if !trained.is_ok { return 1; }
  let model = trained.value;

  let pred = boosting_predict(&model, &features, 8);
  if pred.is_ok {
    let p = pred.value;
    io.println(convert.int_to_string(p[0]));   // 0
    io.println(convert.int_to_string(p[7]));   // 10000
  }
  let trace = boosting_loss_trace(&model, &features, 8, &targets);
  io.println(boosting_dump(&model).value);
  return 0;
}
```

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: twenty `[PASS]` lines, then `xiom.boosting: all tests passed`, exit 0.

## Install / publish

```
xiom pkg install xiom.boosting@0.1.0     # consumer, from the XIOM registry
xiom pkg publish                         # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Until `v0.1.0` is published, build from this repository:

```
.\scripts\port.ps1 -Package xiom.boosting
```

Expected tail: 20 `[PASS]` lines, `xiom.boosting: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Integer fixed-point only.** Targets, residuals and predictions are
  `Int` in units of `1e-4`; every division truncates toward zero. Callers
  must quantize real-valued data first and document the rounding.
- **Depth-1/2 stumps only.** `max_depth` is capped at `2`; deeper additive
  interactions are out of scope for `v0.1.0`.
- **Fixture-scale by design**: the split search rescans the node sample per
  candidate threshold (no sort-based incremental scan). The documented
  envelope is 4096 rows / 64 stages / depth 2 / |target| <= 100000.
- **The subsampling LCG is MINSTD, not cryptographic.** A seed and its
  negation produce the same stream (documented normalization), so prefer
  non-negative seeds when that matters. With both subsamples disabled the
  seed is not consulted at all.
- **Single continuous LCG stream** feeds both subsamples across all stages;
  the draw order (rows, then features, per stage) is pinned in `SPEC.md`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
