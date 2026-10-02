// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.training: a fixed-point training toolkit
// Port task: replace the xiom.training placeholder with a pure-XIOM package
// (scaled integers only: no floats, no FFI, no I/O, no Vec[Float64]).
//
// Package layout (five libraries over parallel Vec[Int] state):
//
//   xiom.training            trainer: model + epoch/step loop driver, with
//                            CONCRETE named callbacks `fn(&Int, &Int) -> Int`
//                            (loss and gradient of one sample; no generic
//                            [T,U] callbacks, no inline lambdas) and state
//                            threaded through returns (no &mut Int/Vec).
//                            This root module also owns the shared fixed-point
//                            helpers and Result leaf constructors.
//   xiom.training.schedules  learning-rate schedules and warmup.
//   xiom.training.earlystop  min/max early stopping with patience.
//   xiom.training.logger     training metric log and summaries.
//   xiom.training.checkpoint model/optimizer capture, restore and text codec.
//
// Fixed-point conventions: learning rates, weights, features, targets,
// metrics and gradients are Int raws at scale 1e3 (raw = value * 1000);
// train_one() is 1000. Non-exact divisions round to nearest with ties away
// from zero through _tr_div_round.
//
// Envelopes (violations are reported, not computed): |weight|, |feature|,
// |target|, |bias| <= 1000000; nfeat in [1, 1024]; row and schedule steps in
// [0, 1e9]; learning rates in [0, 1000000]; |gradient callback value| <=
// 100000000; checkpoint entries <= 4096. Every loop is bounded by one of
// these caps. Ok/Err construction lives in the leaf helpers at the bottom.

module xiom.training

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Reserved "no value" sentinel (Int min + 1): returned by accessors when an
/// index is out of range or a record is empty. Not a real training value.
pub const TRAIN_NONE: Int = 0 - 0x7FFFFFFFFFFFFFFF;

/// Early-stop mode: lower metric is better (loss-like).
pub const ES_MODE_MIN: Int = 0;

/// Early-stop mode: higher metric is better (accuracy-like).
pub const ES_MODE_MAX: Int = 1;

/// Checkpoint text-codec magic prefix.
pub const CKPT_MAGIC: Str = "xtr1";

// Shared internals, exported for the sibling modules of this package only.
pub const _TR_DEC: Int = 3;
pub const _TR_ONE: Int = 1000;
pub const _TR_MICRO: Int = 1000000;
pub const _TR_MAX_COORD: Int = 1000000;
pub const _TR_MAX_LR: Int = 1000000;
pub const _TR_MAX_GRAD: Int = 100000000;
pub const _TR_MAX_STEPS: Int = 1000000000;
pub const _TR_MAX_FEAT: Int = 1024;
pub const _TR_MAX_EPOCHS: Int = 100000;
pub const _TR_MAX_TAG: Int = 32;
pub const _TR_MAX_ENTRIES: Int = 4096;
pub const _TR_DECAY_DROPS: Int = 64;
pub const _TR_INT_HI: Int = 0x7FFFFFFFFFFFFFFF;

// ---------------------------------------------------------------------------
// Shared fixed-point helpers
// ---------------------------------------------------------------------------

/// Absolute value; wraps on the extreme Int min instead of trapping.
pub fn _tr_abs(v: Int) -> Int {
  if v < 0 {
    return 0 - v;
  }
  return v;
}

/// a / b for b > 0, rounded to nearest with ties away from zero. b is small
/// enough that 2*|a % b| cannot overflow.
pub fn _tr_div_round(a: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  var mag = r;
  if mag < 0 {
    mag = 0 - mag;
  }
  if mag * 2 >= b {
    if a < 0 {
      return q - 1;
    }
    return q + 1;
  }
  return q;
}

/// True when |v| <= _TR_MAX_COORD.
pub fn _tr_in_envelope(v: Int) -> Bool {
  if v > _TR_MAX_COORD {
    return false;
  }
  if v < (0 - _TR_MAX_COORD) {
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// TrainModel: a linear model at scale 1e3
// ---------------------------------------------------------------------------

/// A linear model: one value-scale weight per feature plus a value-scale
/// bias. Construction copies the weights into a fresh vector.
pub type TrainModel = {
  w: Vec[Int];
  b: Int;
}

/// Fraction digits of model parameters: 3.
pub fn train_decimals() -> Int {
  return _TR_DEC;
}

/// Parameter unit: raw 1000 denotes the real value 1.0.
pub fn train_one() -> Int {
  return _TR_ONE;
}

fn _model_make(w: Vec[Int], b: Int) -> TrainModel {
  return TrainModel{ w: w; b: b; };
}

fn _model_copy(m: &TrainModel) -> TrainModel {
  var out = Vec[Int].new();
  var i = 0;
  while i < m.w.len() {
    let v: Int = m.w[i];
    out.push(v);
    i = i + 1;
  }
  return _model_make(out, m.b);
}

/// Build a model from weights and a bias; the weights are copied.
/// Params: w - value-scale weights; b - value-scale bias.
/// Returns: the model record. Error case: none. Complexity: O(w.len()).
pub fn train_model_new(w: &Vec[Int], b: Int) -> TrainModel {
  var out = Vec[Int].new();
  var i = 0;
  while i < w.len() {
    let v: Int = w[i];
    out.push(v);
    i = i + 1;
  }
  return _model_make(out, b);
}

/// Number of weights (features) of the model. Complexity: O(1).
pub fn train_model_len(m: &TrainModel) -> Int {
  return m.w.len();
}

/// Weight i, or TRAIN_NONE when out of range. Complexity: O(1).
pub fn train_model_weight(m: &TrainModel, i: Int) -> Int {
  if i < 0 || i >= m.w.len() {
    return TRAIN_NONE;
  }
  let v: Int = m.w[i];
  return v;
}

/// Bias of the model. Complexity: O(1).
pub fn train_model_bias(m: &TrainModel) -> Int {
  return m.b;
}

fn _train_shape_error(m: &TrainModel, nfeat: Int) -> Str {
  if nfeat < 1 {
    return "training: nfeat must be >= 1";
  }
  if nfeat > _TR_MAX_FEAT {
    return "training: nfeat exceeds the supported envelope";
  }
  if m.w.len() != nfeat {
    return "training: model width does not match nfeat";
  }
  if !_tr_in_envelope(m.b) {
    return "training: bias magnitude exceeds the supported envelope";
  }
  return "";
}

fn _train_geometry_error(m: &TrainModel, xs: &Vec[Int], row: Int, nfeat: Int) -> Str {
  let se = _train_shape_error(m, nfeat);
  if se.len() != 0 {
    return se;
  }
  if row < 0 {
    return "training: row index must be non-negative";
  }
  if row > _TR_MAX_STEPS {
    return "training: row index exceeds the supported envelope";
  }
  if xs.len() < (row + 1) * nfeat {
    return "training: dataset does not cover the requested row";
  }
  return "";
}

// Prediction without re-validation: callers already ran the geometry check.
fn _train_predict_raw(m: &TrainModel, xs: &Vec[Int], row: Int, nfeat: Int) -> Result[Int, Str] {
  var acc: Int = 0;
  let base = row * nfeat;
  var i = 0;
  while i < nfeat {
    let w: Int = m.w[i];
    let x: Int = xs[base + i];
    if !_tr_in_envelope(w) {
      return _err_int("training: weight magnitude exceeds the supported envelope");
    }
    if !_tr_in_envelope(x) {
      return _err_int("training: feature magnitude exceeds the supported envelope");
    }
    acc = acc + w * x;
    i = i + 1;
  }
  return _ok_int(_tr_div_round(acc, _TR_ONE) + m.b);
}

/// Predict row `row` of a flat row-major dataset: the dot product of the
/// weights with the row features divided by 1000, plus the bias, rounded to
/// nearest with ties away from zero.
/// Params: m - model; xs - flat row-major dataset; row - 0-based row index;
///         nfeat - features per row, matching the model width.
/// Returns: Ok(value-scale prediction).
/// Error case: Err("training: ...") for a shape mismatch, out-of-range row,
/// uncovered dataset or an entry outside the envelope. Complexity: O(nfeat).
pub fn train_predict(m: &TrainModel, xs: &Vec[Int], row: Int, nfeat: Int) -> Result[Int, Str] {
  let err = _train_geometry_error(m, xs, row, nfeat);
  if err.len() != 0 {
    return _err_int(err);
  }
  return _train_predict_raw(m, xs, row, nfeat);
}

/// Per-sample loss of one dataset row through a concrete callback.
/// Params: m, xs, row, nfeat - as for train_predict; target - value-scale
///         target; loss_fn - named callback `(prediction, target) -> loss`.
/// Returns: Ok(loss_fn(prediction, target)) for the row.
/// Error case: Err("training: ...") as for train_predict, plus a target
/// outside the envelope. Complexity: O(nfeat).
pub fn train_loss_row(m: &TrainModel, xs: &Vec[Int], row: Int, nfeat: Int, target: Int, loss_fn: fn(&Int, &Int) -> Int) -> Result[Int, Str] {
  let err = _train_geometry_error(m, xs, row, nfeat);
  if err.len() != 0 {
    return _err_int(err);
  }
  if !_tr_in_envelope(target) {
    return _err_int("training: target magnitude exceeds the supported envelope");
  }
  let pred = _train_predict_raw(m, xs, row, nfeat);
  match pred {
    Ok(p) => { return _ok_int(loss_fn(&p, &target)); },
    Err(e) => { return _err_int(e); },
  }
  return _err_int("training: internal prediction failure");
}

/// Gradient of the per-sample loss with respect to the model, through a
/// concrete callback: d(weight_j) = round(g * x_j / 1000), d(bias) = g,
/// where g = grad_fn(prediction, target).
/// Params: m, xs, row, nfeat, target - as for train_loss_row; grad_fn -
///         named callback `(prediction, target) -> d(loss)/d(prediction)`.
/// Returns: Ok(a Vec[Int] of length nfeat + 1: weights first, bias last),
/// rounded to nearest with ties away from zero.
/// Error case: Err("training: ...") as for train_loss_row, plus a callback
/// value outside +-100000000. Complexity: O(nfeat).
pub fn train_grad_row(m: &TrainModel, xs: &Vec[Int], row: Int, nfeat: Int, target: Int, grad_fn: fn(&Int, &Int) -> Int) -> Result[Vec[Int], Str] {
  let err = _train_geometry_error(m, xs, row, nfeat);
  if err.len() != 0 {
    return _err_ints(err);
  }
  if !_tr_in_envelope(target) {
    return _err_ints("training: target magnitude exceeds the supported envelope");
  }
  let pred = _train_predict_raw(m, xs, row, nfeat);
  match pred {
    Ok(p) => {
      let g = grad_fn(&p, &target);
      if g > _TR_MAX_GRAD || g < (0 - _TR_MAX_GRAD) {
        return _err_ints("training: gradient callback value exceeds the supported envelope");
      }
      var out = Vec[Int].new();
      let base = row * nfeat;
      var i = 0;
      while i < nfeat {
        let x: Int = xs[base + i];
        out.push(_tr_div_round(g * x, _TR_ONE));
        i = i + 1;
      }
      out.push(g);
      return _ok_ints(out);
    },
    Err(e) => { return _err_ints(e); },
  }
  return _err_ints("training: internal prediction failure");
}

/// One SGD step on a dataset row: w_j' = w_j - round(lr * g_j / 1000) and
/// b' = b - round(lr * g / 1000).
/// Params: m, xs, row, nfeat, target, grad_fn - as for train_grad_row;
///         lr - value-scale learning rate in [0, 1000000].
/// Returns: Ok(the updated model in a fresh record; the input is not
/// modified, state is threaded through the return).
/// Error case: Err("training: ...") for a bad rate or anything
/// train_grad_row rejects. Complexity: O(nfeat).
pub fn train_sgd_step(m: &TrainModel, xs: &Vec[Int], row: Int, nfeat: Int, target: Int, lr: Int, grad_fn: fn(&Int, &Int) -> Int) -> Result[TrainModel, Str] {
  if lr < 0 {
    return _err_model("training: learning rate must be non-negative");
  }
  if lr > _TR_MAX_LR {
    return _err_model("training: learning rate exceeds the supported envelope");
  }
  let err = _train_geometry_error(m, xs, row, nfeat);
  if err.len() != 0 {
    return _err_model(err);
  }
  let grad = train_grad_row(m, xs, row, nfeat, target, grad_fn);
  match grad {
    Ok(g) => {
      var nw = Vec[Int].new();
      var i = 0;
      while i < nfeat {
        let wv: Int = m.w[i];
        let gv: Int = g[i];
        nw.push(wv - _tr_div_round(lr * gv, _TR_ONE));
        i = i + 1;
      }
      let gb: Int = g[nfeat];
      let nb = m.b - _tr_div_round(lr * gb, _TR_ONE);
      return _ok_model(_model_make(nw, nb));
    },
    Err(e) => { return _err_model(e); },
  }
  return _err_model("training: internal gradient failure");
}

/// One epoch of SGD over rows [0, nrows): each step consumes the model
/// returned by the previous step.
/// Params: m - starting model; xs - flat row-major dataset; ys - targets,
///         at least nrows entries; nrows - rows to visit (may be 0);
///         nfeat - features per row; lr - rate; grad_fn - callback.
/// Returns: Ok(the model after the epoch); a copy of the input when
/// nrows == 0.
/// Error case: Err("training: ...") for negative nrows, labels not covering
/// nrows, or any per-step error. Complexity: O(nrows * nfeat).
pub fn train_epoch_sgd(m: &TrainModel, xs: &Vec[Int], ys: &Vec[Int], nrows: Int, nfeat: Int, lr: Int, grad_fn: fn(&Int, &Int) -> Int) -> Result[TrainModel, Str] {
  if nrows < 0 {
    return _err_model("training: nrows must be non-negative");
  }
  if nrows > _TR_MAX_STEPS {
    return _err_model("training: nrows exceeds the supported envelope");
  }
  let se = _train_shape_error(m, nfeat);
  if se.len() != 0 {
    return _err_model(se);
  }
  if ys.len() < nrows {
    return _err_model("training: labels do not cover nrows");
  }
  var cur = _model_copy(m);
  var r = 0;
  while r < nrows {
    let t: Int = ys[r];
    let next = train_sgd_step(&cur, xs, r, nfeat, t, lr, grad_fn);
    match next {
      Ok(nm) => { cur = nm; },
      Err(e) => { return _err_model(e); },
    }
    r = r + 1;
  }
  return _ok_model(cur);
}

/// Mean per-row loss of an epoch; per-row losses are averaged with
/// _tr_div_round (nearest, ties away from zero).
/// Params: m, xs, ys, nrows, nfeat - as for train_epoch_sgd; loss_fn - named
///         loss callback.
/// Returns: Ok(mean loss).
/// Error case: Err("training: ...") for nrows < 1, labels not covering
/// nrows, a per-row error, a callback value outside +-100000000, or an
/// overflowing total. Complexity: O(nrows * nfeat).
pub fn train_epoch_loss(m: &TrainModel, xs: &Vec[Int], ys: &Vec[Int], nrows: Int, nfeat: Int, loss_fn: fn(&Int, &Int) -> Int) -> Result[Int, Str] {
  if nrows < 1 {
    return _err_int("training: epoch loss needs at least one row");
  }
  if nrows > _TR_MAX_STEPS {
    return _err_int("training: nrows exceeds the supported envelope");
  }
  let se = _train_shape_error(m, nfeat);
  if se.len() != 0 {
    return _err_int(se);
  }
  if ys.len() < nrows {
    return _err_int("training: labels do not cover nrows");
  }
  var total: Int = 0;
  var r = 0;
  while r < nrows {
    let t: Int = ys[r];
    let lr = train_loss_row(m, xs, r, nfeat, t, loss_fn);
    match lr {
      Ok(v) => {
        if v > _TR_MAX_GRAD || v < (0 - _TR_MAX_GRAD) {
          return _err_int("training: loss callback value exceeds the supported envelope");
        }
        if total > _TR_INT_HI - _tr_abs(v) {
          return _err_int("training: loss accumulation overflows");
        }
        total = total + v;
      },
      Err(e) => { return _err_int(e); },
    }
    r = r + 1;
  }
  return _ok_int(_tr_div_round(total, nrows));
}

/// Run `epochs` full SGD epochs, threading the model through every epoch
/// return.
/// Params: m, xs, ys, nrows, nfeat, lr, grad_fn - as for train_epoch_sgd;
///         epochs - number of epochs in [0, 100000].
/// Returns: Ok(the final model); a copy of the input when epochs == 0.
/// Error case: Err("training: ...") for negative/oversized epochs or any
/// epoch error. Complexity: O(epochs * nrows * nfeat).
pub fn train_run(m: &TrainModel, xs: &Vec[Int], ys: &Vec[Int], nrows: Int, nfeat: Int, lr: Int, epochs: Int, grad_fn: fn(&Int, &Int) -> Int) -> Result[TrainModel, Str] {
  if epochs < 0 {
    return _err_model("training: epochs must be non-negative");
  }
  if epochs > _TR_MAX_EPOCHS {
    return _err_model("training: epochs exceed the supported envelope");
  }
  let se = _train_shape_error(m, nfeat);
  if se.len() != 0 {
    return _err_model(se);
  }
  if nrows < 0 {
    return _err_model("training: nrows must be non-negative");
  }
  if ys.len() < nrows {
    return _err_model("training: labels do not cover nrows");
  }
  var cur = _model_copy(m);
  var e = 0;
  while e < epochs {
    let next = train_epoch_sgd(&cur, xs, ys, nrows, nfeat, lr, grad_fn);
    match next {
      Ok(nm) => { cur = nm; },
      Err(er) => { return _err_model(er); },
    }
    e = e + 1;
  }
  return _ok_model(cur);
}

/// Reference loss callback: squared error at value scale, (p - t)^2 / 1000
/// truncated. Use with train_grad_squared.
pub fn train_loss_squared(pred: &Int, target: &Int) -> Int {
  let d = *pred - *target;
  return d * d / _TR_ONE;
}

/// Reference gradient callback matching train_loss_squared: 2*(p - t).
pub fn train_grad_squared(pred: &Int, target: &Int) -> Int {
  let d = *pred - *target;
  return d + d;
}

/// Reference loss callback: absolute error |p - t| at value scale.
pub fn train_loss_abs(pred: &Int, target: &Int) -> Int {
  return _tr_abs(*pred - *target);
}

/// Reference gradient callback matching train_loss_abs: sign(p - t) in
/// value scale (+1000, -1000 or 0).
pub fn train_grad_abs(pred: &Int, target: &Int) -> Int {
  let d = *pred - *target;
  if d > 0 {
    return _TR_ONE;
  }
  if d < 0 {
    return 0 - _TR_ONE;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors (struct/Vec payloads are only built here)
// ---------------------------------------------------------------------------

/// Leaf constructor shared by the sibling modules.
pub fn _ok_int(x: Int) -> Result[Int, Str] {
  return Ok(x);
}

/// Leaf constructor shared by the sibling modules.
pub fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

/// Leaf constructor shared by the sibling modules.
pub fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

/// Leaf constructor shared by the sibling modules.
pub fn _err_ints(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

fn _ok_model(m: TrainModel) -> Result[TrainModel, Str] {
  return Ok(m);
}

fn _err_model(m: Str) -> Result[TrainModel, Str] {
  return Err(m);
}
