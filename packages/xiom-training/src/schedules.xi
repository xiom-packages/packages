// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.training.schedules: learning-rate schedules at scale 1e3
// Part of the xiom.training package.
//
// Constant, linear warmup, step decay, inverse-time decay and quadratic
// decay (the fixed-point stand-in for a cosine schedule), plus warmup
// followed by quadratic decay. All results are Int raws at scale 1e3;
// non-exact divisions round to nearest with ties away from zero. Every
// function validates its inputs and reports violations as Err.

module xiom.training.schedules

use xiom.training;

/// Fraction digits of every learning rate: 3, so raw r denotes r/1000.
pub fn sched_decimals() -> Int {
  return _TR_DEC;
}

/// Learning-rate unit: raw 1000 denotes the real learning rate 1.0.
pub fn sched_one() -> Int {
  return _TR_ONE;
}

fn _sched_base_error(step: Int, base_lr: Int) -> Str {
  if step < 0 {
    return "training: schedule step must be non-negative";
  }
  if step > _TR_MAX_STEPS {
    return "training: schedule step exceeds the supported envelope";
  }
  if base_lr < 0 {
    return "training: base learning rate must be non-negative";
  }
  if base_lr > _TR_MAX_LR {
    return "training: base learning rate exceeds the supported envelope";
  }
  return "";
}

/// Constant schedule.
/// Params: step - non-negative step index; base_lr - base learning rate.
/// Returns: Ok(base_lr) for every step.
/// Error case: Err("training: ...") for step < 0 or base_lr outside
/// [0, 1000000]. Complexity: O(1).
pub fn sched_constant(step: Int, base_lr: Int) -> Result[Int, Str] {
  let err = _sched_base_error(step, base_lr);
  if err.len() != 0 {
    return _err_int(err);
  }
  return _ok_int(base_lr);
}

/// Linear warmup: base_lr * (step + 1) / warmup_steps, truncated, for
/// step < warmup_steps; base_lr afterwards.
/// Params: step - step index; warmup_steps - warmup length >= 1;
///         base_lr - base learning rate.
/// Returns: Ok(learning rate). At the last warmup step the rate is exactly
/// base_lr.
/// Error case: Err("training: ...") for negative step/base_lr or
/// warmup_steps outside [1, 1e9]. Complexity: O(1).
pub fn sched_linear_warmup(step: Int, warmup_steps: Int, base_lr: Int) -> Result[Int, Str] {
  let err = _sched_base_error(step, base_lr);
  if err.len() != 0 {
    return _err_int(err);
  }
  if warmup_steps < 1 {
    return _err_int("training: warmup_steps must be >= 1");
  }
  if warmup_steps > _TR_MAX_STEPS {
    return _err_int("training: warmup_steps exceeds the supported envelope");
  }
  if step >= warmup_steps {
    return _ok_int(base_lr);
  }
  return _ok_int(base_lr * (step + 1) / warmup_steps);
}

/// Step decay: base_lr * gamma^(step / drop_every), truncated after every
/// drop; gamma is a value-scale factor (500 is a halving).
/// Params: step - step index; base_lr - base rate; drop_every - steps per
///         drop >= 1; gamma - per-drop factor in [0, 1000].
/// Returns: Ok(learning rate). At most 64 drops are applied: after 64
/// multiplications any gamma < 1000 has already reached 0, and gamma == 1000
/// keeps base_lr, so the cap is lossless.
/// Error case: Err("training: ...") for bad step/base_lr, drop_every < 1 or
/// gamma outside [0, 1000]. Complexity: O(1) (<= 64 iterations).
pub fn sched_step_decay(step: Int, base_lr: Int, drop_every: Int, gamma: Int) -> Result[Int, Str] {
  let err = _sched_base_error(step, base_lr);
  if err.len() != 0 {
    return _err_int(err);
  }
  if drop_every < 1 {
    return _err_int("training: drop_every must be >= 1");
  }
  if gamma < 0 {
    return _err_int("training: gamma must be in [0, 1000]");
  }
  if gamma > _TR_ONE {
    return _err_int("training: gamma must be in [0, 1000]");
  }
  var drops = step / drop_every;
  if drops > _TR_DECAY_DROPS {
    drops = _TR_DECAY_DROPS;
  }
  var lr = base_lr;
  while drops > 0 {
    lr = lr * gamma / _TR_ONE;
    drops = drops - 1;
  }
  return _ok_int(lr);
}

/// Inverse-time decay: round(base_lr * decay / (decay + step)).
/// Params: step - step index; base_lr - base rate; decay - half-life-ish
///         constant >= 1. At step == decay the rate is half of base_lr.
/// Returns: Ok(learning rate), rounded to nearest with ties away from zero.
/// Error case: Err("training: ...") for bad step/base_lr or decay outside
/// [1, 1e9]. Complexity: O(1).
pub fn sched_inverse_time(step: Int, base_lr: Int, decay: Int) -> Result[Int, Str] {
  let err = _sched_base_error(step, base_lr);
  if err.len() != 0 {
    return _err_int(err);
  }
  if decay < 1 {
    return _err_int("training: decay must be >= 1");
  }
  if decay > _TR_MAX_STEPS {
    return _err_int("training: decay exceeds the supported envelope");
  }
  return _ok_int(_tr_div_round(base_lr * decay, decay + step));
}

/// Quadratic decay from base_lr to min_lr over total_steps: the fixed-point
/// stand-in for a cosine schedule. The ratio is computed at scale 1e6 and
/// squared, so the result is accurate to about one raw unit.
/// Params: step - step index; total_steps - schedule length >= 1;
///         base_lr - starting rate; min_lr - floor rate in [0, base_lr].
/// Returns: Ok(base_lr) at step 0, Ok(min_lr) at step >= total_steps, and a
/// quadratic-in-remaining-time interpolation between.
/// Error case: Err("training: ...") for bad step/base_lr, total_steps
/// outside [1, 1e9], or min_lr outside [0, base_lr]. Complexity: O(1).
pub fn sched_poly_decay(step: Int, total_steps: Int, base_lr: Int, min_lr: Int) -> Result[Int, Str] {
  let err = _sched_base_error(step, base_lr);
  if err.len() != 0 {
    return _err_int(err);
  }
  if total_steps < 1 {
    return _err_int("training: total_steps must be >= 1");
  }
  if total_steps > _TR_MAX_STEPS {
    return _err_int("training: total_steps exceeds the supported envelope");
  }
  if min_lr < 0 {
    return _err_int("training: min_lr must be non-negative");
  }
  if min_lr > base_lr {
    return _err_int("training: min_lr must not exceed base_lr");
  }
  if step >= total_steps {
    return _ok_int(min_lr);
  }
  return _ok_int(_poly_lr(step, total_steps, base_lr, min_lr));
}

/// Warmup followed by quadratic decay: linear warmup for step < warmup_steps,
/// then sched_poly_decay over the full total_steps horizon.
/// Params: step - step index; warmup_steps - warmup length >= 1;
///         total_steps - schedule length >= warmup_steps; base_lr - peak
///         rate; min_lr - floor rate in [0, base_lr].
/// Returns: Ok(learning rate). The peak base_lr is not forced exactly: the
/// first post-warmup step already starts the decay ratio formula.
/// Error case: Err("training: ...") for bad step/base_lr, warmup/total
/// outside the envelope, total_steps < warmup_steps, or min_lr outside
/// [0, base_lr]. Complexity: O(1).
pub fn sched_warmup_poly(step: Int, warmup_steps: Int, total_steps: Int, base_lr: Int, min_lr: Int) -> Result[Int, Str] {
  let err = _sched_base_error(step, base_lr);
  if err.len() != 0 {
    return _err_int(err);
  }
  if warmup_steps < 1 {
    return _err_int("training: warmup_steps must be >= 1");
  }
  if warmup_steps > _TR_MAX_STEPS {
    return _err_int("training: warmup_steps exceeds the supported envelope");
  }
  if total_steps < warmup_steps {
    return _err_int("training: total_steps must be >= warmup_steps");
  }
  if total_steps > _TR_MAX_STEPS {
    return _err_int("training: total_steps exceeds the supported envelope");
  }
  if min_lr < 0 {
    return _err_int("training: min_lr must be non-negative");
  }
  if min_lr > base_lr {
    return _err_int("training: min_lr must not exceed base_lr");
  }
  if step < warmup_steps {
    return _ok_int(base_lr * (step + 1) / warmup_steps);
  }
  if step >= total_steps {
    return _ok_int(min_lr);
  }
  return _ok_int(_poly_lr(step, total_steps, base_lr, min_lr));
}

// Quadratic interpolation shared by the two decay schedules: ratio r at
// scale 1e6, f = r*r/1e6, lr = min + (base - min)*f/1e6. Callers guarantee
// 0 <= step < total_steps and 0 <= min <= base.
fn _poly_lr(step: Int, total_steps: Int, base_lr: Int, min_lr: Int) -> Int {
  let rem = total_steps - step;
  let r = rem * _TR_MICRO / total_steps;
  let f = r * r / _TR_MICRO;
  return min_lr + (base_lr - min_lr) * f / _TR_MICRO;
}
