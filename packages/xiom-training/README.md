# xiom.training

> **Status:** `incubating` -- conformance-tested (26/26); not yet published on the XIOM registry.
> **Scope:** a pure-XIOM, fixed-point training toolkit: an epoch/step
> training-loop driver over a flat row-major dataset (concrete named
> callbacks, state threaded through returns), checkpoint capture/restore with
> a strict text codec, learning-rate schedules with warmup, patience-based
> early stopping and a training metric log.
> **Deps:** `xiom.std >=0.60.0 <1.0.0`. The library modules import
> `xiom.string`, `xiom.string.compare`, `xiom.string.split` and
> `xiom.convert`; the tests add `xiom.test` and `xiom.io`.

## What it is

`xiom.training` is the training-loop layer of the fixed-point ML stack
(`xiom.loss`, `xiom.optimizer-fw`, ...). Everything is 64-bit signed `Int`
at scale 1e3 (raw = value * 1000): learning rates, weights, features,
targets, metrics and gradients. There are no floats, no FFI, no I/O, no
`Vec[Float64]`, no `Vec[StructType]` and no `&mut` scalar state: every
function that advances state returns the new state, and every callback is a
named top-level function of the concrete type `fn(&Int, &Int) -> Int`.

Package layout (five modules):

| Module | Library | What it does |
|---|---|---|
| `xiom.training` | trainer | Model record, prediction, loss/gradient rows, SGD step, epoch and multi-epoch drivers; shared helpers and `Result` leaf constructors. |
| `xiom.training.schedules` | scheduler | Constant, linear warmup, step decay, inverse-time decay, quadratic (cosine-shaped) decay and warmup-then-decay. |
| `xiom.training.earlystop` | earlystop | Min/max early stopping with `patience` and a strict `min_delta`. |
| `xiom.training.logger` | logger | Parallel step/loss metric log with mean/min/best-step accessors and a one-line summary. |
| `xiom.training.checkpoint` | checkpoint | Model + optimizer capture, restore and the `xtr1` text codec. |

## Example

```xi
use xiom.training;
use xiom.training.schedules;
use xiom.io;

fn loss_sq(p: &Int, t: &Int) -> Int {
  let d = *p - *t;
  return d * d / 1000;
}

fn grad_sq(p: &Int, t: &Int) -> Int {
  let d = *p - *t;
  return d + d;
}

fn main() -> Int {
  // Two rows, one feature: (x, y) = (1.0, 0.5), (2.0, 1.0).
  var w: Vec[Int] = Vec[Int].new();
  w.push(0);
  var xs: Vec[Int] = Vec[Int].new();
  xs.push(1000);
  xs.push(2000);
  var ys: Vec[Int] = Vec[Int].new();
  ys.push(500);
  ys.push(1000);

  var m = train_model_new(&w, 0);
  var epoch = 0;
  while epoch < 3 {
    let next = train_epoch_sgd(&m, &xs, &ys, 2, 1, 100, grad_sq);
    match next {
      Ok(nm) => { m = nm; },
      Err(e) => { io.println(e); return 1; },
    }
    epoch = epoch + 1;
  }

  io.println("bias after 3 epochs");      // 221
  return train_model_bias(&m);             // 221
}
```

## Trainer API

Callbacks are named top-level functions `fn(&Int, &Int) -> Int`:
`loss_fn(prediction, target) -> loss` and
`grad_fn(prediction, target) -> d(loss)/d(prediction)`. The module ships two
ready-made pairs (`train_loss_squared`/`train_grad_squared`,
`train_loss_abs`/`train_grad_abs`) and callers may pass their own.

| Function | Returns | Description |
|---|---|---|
| `train_decimals()` / `train_one()` | `Int` | Scale accessors: 3 and 1000. |
| `train_model_new(w, b)` | `TrainModel` | Copies `w`; bias `b`. |
| `train_model_len/weight/bias(m, ...)` | `Int` | Range-safe reads (`weight` -> `TRAIN_NONE`). |
| `train_predict(m, xs, row, nfeat)` | `Result[Int, Str]` | Dot product / 1000 + bias, rounded half away from zero. |
| `train_loss_row(..., target, loss_fn)` | `Result[Int, Str]` | `loss_fn(prediction, target)`. |
| `train_grad_row(..., target, grad_fn)` | `Result[Vec[Int], Str]` | `nfeat + 1` entries: `round(g * x_j / 1000)` then `g`. |
| `train_sgd_step(..., lr, grad_fn)` | `Result[TrainModel, Str]` | `w_j' = w_j - round(lr * g_j / 1000)`, `b' = b - round(lr * g / 1000)`. |
| `train_epoch_sgd(m, xs, ys, nrows, nfeat, lr, grad_fn)` | `Result[TrainModel, Str]` | One epoch over rows `[0, nrows)`. |
| `train_epoch_loss(m, xs, ys, nrows, nfeat, loss_fn)` | `Result[Int, Str]` | Mean per-row loss (rounded). |
| `train_run(..., epochs, grad_fn)` | `Result[TrainModel, Str]` | `epochs` full epochs; input model never modified. |

Dataset convention: `xs` is flat and row-major (`nfeat` entries per row),
`ys` holds one target per row. Outputs that fit in `Int`/`Vec[Int]` are
supplied directly; records travel as `TrainModel`.

## Scheduler API

All rates are scale 1e3 (`sched_one()` = 1000). Non-exact results round to
nearest with ties away from zero (step decay truncates after each drop,
which is documented and pinned by tests).

| Function | Behavior |
|---|---|
| `sched_constant(step, base_lr)` | `base_lr`. |
| `sched_linear_warmup(step, warmup_steps, base_lr)` | `base_lr * (step + 1) / warmup_steps` (truncated) then `base_lr`. |
| `sched_step_decay(step, base_lr, drop_every, gamma)` | `base_lr * gamma^(step/drop_every)` (truncated per drop; at most 64 drops). |
| `sched_inverse_time(step, base_lr, decay)` | `round(base_lr * decay / (decay + step))`; half rate at `step == decay`. |
| `sched_poly_decay(step, total_steps, base_lr, min_lr)` | Quadratic from `base_lr` to `min_lr` over the horizon. |
| `sched_warmup_poly(step, warmup_steps, total_steps, base_lr, min_lr)` | Warmup then the quadratic decay. |

## Early stopping API

`EsState` is threaded through returns: `es_update(state, metric)` produces
the next state; a stopped state passes through unchanged.

| Function | Behavior |
|---|---|
| `es_new_min(best, patience, min_delta)` / `es_new_max(...)` | Mode-specific constructors. |
| `es_best/bad/patience/min_delta/mode/stopped(s)` | Accessors. |
| `es_is_improvement(s, metric)` | Min: `metric < best - min_delta`; max: `metric > best + min_delta`. |
| `es_update(s, metric)` | Improve -> new best, `bad = 0`; else `bad + 1`; stop when `bad >= patience`. |
| `es_run(metrics, patience, min_delta, mode)` | Scans a trace until the stop fires; later metrics are not consumed. |

## Logger API

`TrainLog` holds parallel `steps`/`losses` vectors fed by one push site.
`tlog_record(log, step, loss)` returns a new log; the input is unchanged.
Empty/out-of-range results return the `TRAIN_NONE` sentinel; mean rounds to
nearest, ties away from zero.

`tlog_new`, `tlog_record`, `tlog_len`, `tlog_is_consistent`, `tlog_step`,
`tlog_loss`, `tlog_last_loss`, `tlog_min_loss` (first tie wins),
`tlog_best_step`, `tlog_mean_loss`, `tlog_summary`
(`"n=<n> last=<l> mean=<m> best_step=<s>"`, `"n=0 last=none mean=none
best_step=none"` when empty, `"drift"` when inconsistent).

## Checkpoint API and format

`Ckpt` holds `step`, an ASCII `tag`, parallel `weights` and `momenta`.
`ckpt_new` is the only constructor (it copies both vectors through one push
site). `ckpt_weights`/`ckpt_momenta` return fresh restore copies;
`ckpt_stamp` is a deterministic 64-bit wrapping checksum.

Text format (one ASCII line, no NUL bytes possible):

```
xtr1|<step>|<tag>|<n>|<w0>,<w1>,...|<m0>,<m1>,...
```

`<tag>` is 1-32 chars of `[A-Za-z0-9_-]`; `<n>` is the exact entry count
(both lists must have exactly `<n>` comma-separated integers; `n = 0`
requires two empty fields, `"xtr1|3|em|0||"`). `ckpt_parse` validates the
magic, step >= 0, tag alphabet, count (<= 4096), every integer field
(manual parser with an overflow guard) and the absence of trailing fields.

## Tests

From the repository root:

```
.\scripts\port.ps1 -Package xiom-training -TimeoutSec 60
```

Expected tail: 26 `[PASS]` lines, `xiom.training: all tests passed`, then
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Install / usage

The package is **not yet published** on the XIOM registry; when it is:

```
xiom pkg install xiom.training@0.1.0
```

Until then, use it from this repository (pure XIOM, no FFI):

```
use xiom.training;
use xiom.training.schedules;
use xiom.training.earlystop;
use xiom.training.logger;
use xiom.training.checkpoint;
```

## Limitations

- **Fixed-point only.** Scale 1e3 everywhere; no `Float64`, no mixed
  precision, no dynamic scaling.
- **Linear models only.** Prediction is a dot product plus bias; there are
  no layers, activations or backpropagation graphs (this layer drives
  linear/batch models only).
- **Concrete callbacks.** Function-pointer parameters are the concrete
  `fn(&Int, &Int) -> Int`; there are no generic `[T, U]` callbacks, no
  closures and no lambdas on the installed compiler.
- **Copies, not mutation.** `TrainModel`, `TrainLog` and `EsState` are
  threaded through returns (`tlog_record` is O(n) per append by design);
  `&mut Int`/`&mut Vec` never appear in the public API.
- **Deterministic.** No clock, no randomness, no threads, no I/O in the
  library. The early-stopping delta and schedule errors are reported as
  `Err("training: ...")` strings.
- **Wraparound arithmetic.** Values are 64-bit signed `Int` and wrap at the
  extremes; stay inside the documented envelopes (SPEC.md).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
