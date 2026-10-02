# xiom.training -- Specification

Status: `incubating` (implemented, harness-green, not published).
Manifest: `package.xi` (name `xiom.training`, version `0.1.0`).
Modules: `xiom.training` (`src/training.xi`), `xiom.training.schedules`
(`src/schedules.xi`), `xiom.training.earlystop` (`src/earlystop.xi`),
`xiom.training.logger` (`src/logger.xi`), `xiom.training.checkpoint`
(`src/checkpoint.xi`). Depends on `xiom.std` for the manifest; the library
imports `xiom.string`, `xiom.string.compare`, `xiom.string.split` and
`xiom.convert` from it.

## Scope

Five fixed-point libraries over parallel `Vec[Int]` state:

- **trainer** -- `TrainModel` (weights + bias), prediction, per-sample
  loss/gradient rows through concrete callbacks, one SGD step, epoch and
  multi-epoch drivers;
- **scheduler** -- learning-rate schedules at scale 1e3: constant, linear
  warmup, step decay, inverse-time decay, quadratic decay (the
  fixed-point stand-in for cosine) and warmup-then-quadratic;
- **earlystop** -- min/max early stopping with `patience` and a strict
  `min_delta`, as a record threaded through returns;
- **logger** -- a training metric log (parallel step/loss vectors, one push
  site) with aggregates and a one-line summary;
- **checkpoint** -- model/optimizer capture, restore and the strict `xtr1`
  text codec.

Pure and deterministic: no floats, no FFI, no I/O, no clock, no global
state, no randomness, no threads, no `Vec[StructType]`, no `&mut Int`/`&mut
Vec` parameters.

## Non-goals

- Neural layers, activations, backpropagation graphs, batching/shuffling or
  data loaders; the trainer drives linear models only.
- Generic `[T, U]` callbacks, closures and inline lambdas (the installed
  compiler rejects them); every callback is a named top-level function of
  the concrete type `fn(&Int, &Int) -> Int`.
- Optimizer algorithms (SGD momentum/Adam/...): only a plain SGD step is
  here; `momenta` in a checkpoint is opaque caller state, never interpreted.
- Floating-point schedules, cyclic schedules, per-parameter groups.
- File I/O: `ckpt_serialize`/`ckpt_parse` produce/consume a `Str`; writing
  it to disk is the caller's concern.
- Any cross-package import (`xiom.loss` etc. are not used, by package
  policy).

## Scale and rounding

| Quantity | Fraction digits | Raw representation |
|---|---|---|
| Learning rates, weights, biases, features, targets, metrics, gradients | 3 | `value * 1000` |

`sched_decimals()`/`train_decimals()` = 3; `sched_one()`/`train_one()` =
1000. XIOM integer division truncates toward zero; every non-exact
documented rounding goes through `_tr_div_round(a, b)` (b > 0), which
returns `a / b` rounded to nearest with ties away from zero.

Exceptions (explicitly truncated, pinned by tests):

- linear warmup: `base_lr * (step + 1) / warmup_steps` truncates;
- step decay: each drop `lr * gamma / 1000` truncates;
- quadratic decay: the remaining-time ratio is computed at scale 1e6 with
  truncating divisions, so results are accurate to about one raw unit;
- squared reference loss `train_loss_squared`: `d * d / 1000` truncates.

## Envelopes and termination

| Quantity | Envelope | Error string prefix |
|---|---|---|
| weight, bias, feature, target | abs <= 1000000 | `training: ...` |
| nfeat | [1, 1024] | `training: nfeat ...` |
| row / schedule step | [0, 1e9] | `training: ... step ...` |
| warmup_steps, total_steps, decay | [1, 1e9] | `training: ...` |
| learning rate | [0, 1000000] | `training: learning rate ...` |
| loss/gradient callback value | abs <= 100000000 | `training: ... callback value exceeds ...` |
| epochs | [0, 100000] | `training: epochs ...` |
| checkpoint entries | [0, 4096] | `training: checkpoint ...` |
| early-stop min_delta | [0, 1000000] | `training: early-stop ...` |

Every loop is bounded by one of these caps (or by the vector length):
step decay runs at most 64 drops; training loops run at most `epochs`,
`nrows` or `len` iterations; schedule loops are O(1).

## Data model

```
pub type TrainModel = { w: Vec[Int]; b: Int; }
pub type EsState = { best: Int; bad: Int; patience: Int; min_delta: Int;
                     mode: Int; stopped: Bool; }
pub type TrainLog = { steps: Vec[Int]; losses: Vec[Int]; }
pub type Ckpt = { step: Int; tag: Str; weights: Vec[Int]; momenta: Vec[Int]; }
pub const TRAIN_NONE: Int = 0 - 0x7FFFFFFFFFFFFFFF;   // no-value sentinel
pub const ES_MODE_MIN: Int = 0;
pub const ES_MODE_MAX: Int = 1;
pub const CKPT_MAGIC: Str = "xtr1";
```

Parallel-vector invariants: a log is built only through `_tlog_push`
(`tlog_record`), a checkpoint only through `_ckpt_push` (`ckpt_new`), and
`tlog_is_consistent`/`ckpt_is_consistent` report drift. `tlog_record` on a
drifted log copies only the paired prefix and stays consistent. Accessors
never read out of range: they return `TRAIN_NONE`.

## Trainer behavior

A dataset is flat and row-major: row `r` occupies `xs[r*nfeat ..
(r+1)*nfeat]`, with `ys[r]` its target. `train_predict` computes
`round(sum_j(w_j * x_j) / 1000) + b`.

Callbacks are `fn(&Int, &Int) -> Int`:

- `loss_fn(pred, target)` returns the per-sample loss at value scale;
- `grad_fn(pred, target)` returns `d(loss)/d(pred)` at value scale.

`train_grad_row` returns `nfeat + 1` entries: entry `j` is
`round(g * x_j / 1000)` and the last entry is `g` (the bias gradient).
`train_sgd_step` applies `w_j' = w_j - round(lr * g_j / 1000)` and
`b' = b - round(lr * g / 1000)` on a fresh record; the input model is never
modified. `train_epoch_sgd` visits rows `0..nrows` in order, feeding each
step the model returned by the previous step; `train_run` repeats epochs.
`train_epoch_loss` averages per-row losses with `_tr_div_round`.

Reference callbacks (value scale):

| Pair | loss | gradient |
|---|---|---|
| `train_loss_squared` / `train_grad_squared` | `d*d/1000`, `d = p - t` (truncated) | `2*d` |
| `train_loss_abs` / `train_grad_abs` | `abs(d)` | `+1000`, `-1000` or `0` |

Trainer error cases (all `Err("training: ...")`): shape mismatch
(`nfeat` width vs model), negative/oversized row or nrows, dataset/labels
not covering the requested row(s), non-negative-label checks,
`nrows < 1` for epoch loss, entry outside the envelopes, learning rate
outside `[0, 1000000]`, gradient/loss callback outside
`+-100000000`, epoch count outside `[0, 100000]`, and loss accumulation
overflow (`total > INT_MAX - |v|`).

## Scheduler behavior

| Function | Formula | Notes |
|---|---|---|
| `sched_constant(step, base)` | `base` | -- |
| `sched_linear_warmup(step, warmup, base)` | `base*(step+1)/warmup` for `step < warmup`, else `base` | truncated; reaches exactly `base` at `step = warmup - 1` when `warmup` divides `base*warmup` |
| `sched_step_decay(step, base, drop_every, gamma)` | `base * gamma^(step/drop_every)` | per-drop truncated; capped at 64 drops (lossless for `gamma < 1000`; identity for `gamma == 1000`) |
| `sched_inverse_time(step, base, decay)` | `round(base*decay/(decay+step))` | half at `step == decay` |
| `sched_poly_decay(step, total, base, min)` | `min + (base-min) * f(rem/total)` | `f(t) = t^2` at scale 1e6; `step >= total` -> `min` |
| `sched_warmup_poly(step, warmup, total, base, min)` | warmup phase, then the quadratic | `total >= warmup >= 1` |

## Early stopping behavior

`es_new_min(best, patience, min_delta)` / `es_new_max(...)` validate
`patience >= 1`, `0 <= min_delta <= 1000000` and fix the mode.
`es_is_improvement(s, m)` is strict: min mode requires
`m < best - min_delta`; max mode requires `m > best + min_delta`.
`es_update` on improvement sets `best = m`, `bad = 0`; otherwise
`bad = bad + 1`, and `stopped` becomes true once `bad >= patience`. A
stopped state passes through unchanged. `es_run(metrics, ...)` seeds from
`metrics[0]` and consumes metrics left to right until the stop fires;
metrics after the stop are not read. Errors: empty trace, `patience < 1`,
`min_delta < 0` or `> 1000000`, mode not in `{ES_MODE_MIN, ES_MODE_MAX}`.

## Logger behavior

`tlog_record(l, step, loss)` returns a new log (input unchanged) with the
row appended; on a drifted input only the paired prefix is copied.
Accessors: `tlog_len`, `tlog_is_consistent`, `tlog_step`/`tlog_loss` (row
`i`, `TRAIN_NONE` out of range), `tlog_last_loss`, `tlog_min_loss` and
`tlog_best_step` (`TRAIN_NONE` on empty/drifted; first minimum wins),
`tlog_mean_loss` (rounds half away from zero; `TRAIN_NONE` on
empty/drifted, an entry with `abs > 100000000`, or a would-be overflow),
and `tlog_summary`:

- empty: `n=0 last=none mean=none best_step=none`;
- drifted: `drift`;
- otherwise: `n=<n> last=<l> mean=<m> best_step=<s>`.

## Checkpoint behavior and grammar

`ckpt_new(step, tag, weights, momenta)` validates `step >= 0`, the tag
alphabet, equal vector lengths and `len <= 4096`, and copies both vectors
through one push site. `ckpt_weights`/`ckpt_momenta` return fresh restore
copies. `ckpt_stamp` is a deterministic wrapping polynomial checksum over
step, tag bytes and all entries (not cryptographic).

Serialization (one ASCII line; no NUL bytes can be produced or accepted):

```
"xtr1" "|" step "|" tag "|" n "|" w0 ("," w1)* "|" m0 ("," m1)*
```

- `step`: decimal integer, non-negative on parse.
- `tag`: 1-32 chars of `[A-Za-z0-9_-]`.
- `n`: exact entry count in each list (0 -> both fields empty:
  `xtr1|3|em|0||`).
- entries: optional `-` plus digits; manual parser with an overflow guard.

`ckpt_parse` error cases (all `Err("training: checkpoint: ...")`): bad
magic, empty/lone-sign/non-digit/overflowing integer fields, negative
step, bad tag, entry count outside `[0, 4096]`, too few/too many list
entries, unexpected entries for `n = 0`, and trailing fields.

## Tests

`tests/test_conformance.xi` (`module training_tests`) holds 26
deterministic assertions covering: scale/model accessors; all six schedule
entry points with pinned values plus validation; prediction, loss rows,
gradient rows, one SGD step, epoch and multi-epoch drivers including exact
fixed-point expectations; callback envelope rejection; early
stopping (min/max, patience, delta strictness, traces); logger lifecycle,
threading, drift repair and summaries; checkpoint accessors, pinned
serialization, round-trip, stamp equality, restore into a model and one
cross-library composition. Run:

```
.\scripts\port.ps1 -Package xiom-training -TimeoutSec 60
```

Expected: `port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Rationale for copies instead of mutation

The installed compiler mishandles `&mut` scalar parameters and
`&struct.field` passed to `&Vec` parameters; by-value state threading
(`TrainModel`, `EsState`, `TrainLog` returns) and local-bound vector
copies avoid that class entirely, keep call sites explicit, and make the
conformance suite's assertions independent of shared mutable state. The
cost is O(n) copying in `tlog_record`, acceptable at metric-logging scale.
