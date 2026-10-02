// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.training conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.training module against its documented
// fixed-point contract (scaled integers only, no floats, no I/O, callbacks
// are named top-level functions, state is threaded through returns).
//
// Coverage: scales/model accessors, all five schedules (pinned values plus
// validation), prediction/loss/gradient/SGD/epoch/run drivers, callback
// envelope errors, early stopping (min/max, patience, traces), metric logs
// (threading, drift safety, summaries), checkpoint accessors, the text codec
// (pinned serialization, round-trip, every parse-error class), a restore
// into a model, and one cross-library composition.
//
// All Str equality goes through str_compare: `==` on Str values read from
// Vec[Str] elements mis-lowers to a pointer comparison, so every text check
// below routes through streq.

module training_tests
use xiom.io; use xiom.test; use xiom.training;
use xiom.training.schedules; use xiom.training.earlystop;
use xiom.training.logger; use xiom.training.checkpoint;
use xiom.string.compare;

// ---------------------------------------------------------------------------
// Named callbacks (concrete fn(&Int, &Int) -> Int; no inline lambdas)
// ---------------------------------------------------------------------------

fn cb_loss_sq(p: &Int, t: &Int) -> Int {
  let d = *p - *t;
  return d * d / 1000;
}

fn cb_grad_sq(p: &Int, t: &Int) -> Int {
  let d = *p - *t;
  return d + d;
}

fn cb_grad_huge(p: &Int, t: &Int) -> Int {
  return 200000000;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

fn v1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn v2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn v3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn empty_vec() -> Vec[Int] {
  return Vec[Int].new();
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn same_vec(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let av: Int = a[i];
    let bv: Int = b[i];
    if av != bv {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn same_model(a: &TrainModel, b: &TrainModel) -> Bool {
  if train_model_len(a) != train_model_len(b) {
    return false;
  }
  if train_model_bias(a) != train_model_bias(b) {
    return false;
  }
  var i = 0;
  while i < train_model_len(a) {
    if train_model_weight(a, i) != train_model_weight(b, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn model_weights(m: &TrainModel) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < train_model_len(m) {
    out.push(train_model_weight(m, i));
    i = i + 1;
  }
  return out;
}

fn zeros(n: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    out.push(0);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Result extractors with graceful fallbacks: a construction failure makes the
// value checks fail instead of aborting the suite.
// ---------------------------------------------------------------------------

fn int_of(r: Result[Int, Str]) -> Int {
  match r {
    Ok(x) => { return x; },
    Err(_) => { return TRAIN_NONE; },
  }
  return TRAIN_NONE;
}

fn ints_of(r: Result[Vec[Int], Str]) -> Vec[Int] {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_vec(); },
  }
  return empty_vec();
}

fn model_of(r: Result[TrainModel, Str]) -> TrainModel {
  match r {
    Ok(m) => { return m; },
    Err(_) => { return TrainModel{ w: Vec[Int].new(); b: 0; }; },
  }
  return TrainModel{ w: Vec[Int].new(); b: 0; };
}

fn es_of(r: Result[EsState, Str]) -> EsState {
  match r {
    Ok(s) => { return s; },
    Err(_) => { return EsState{ best: 0; bad: 0; patience: 1; min_delta: 0; mode: ES_MODE_MIN; stopped: false; }; },
  }
  return EsState{ best: 0; bad: 0; patience: 1; min_delta: 0; mode: ES_MODE_MIN; stopped: false; };
}

fn ckpt_of(r: Result[Ckpt, Str]) -> Ckpt {
  match r {
    Ok(c) => { return c; },
    Err(_) => { return Ckpt{ step: -1; tag: "err"; weights: Vec[Int].new(); momenta: Vec[Int].new(); }; },
  }
  return Ckpt{ step: -1; tag: "err"; weights: Vec[Int].new(); momenta: Vec[Int].new(); };
}

fn int_err(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn model_err(r: Result[TrainModel, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn es_err(r: Result[EsState, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn ckpt_err(r: Result[Ckpt, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn report(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  return 1;
}

// ---------------------------------------------------------------------------
// Scales, model, schedules
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  let w = v2(500, -250);
  let m = train_model_new(&w, 100);
  var ok = train_decimals() == 3;
  if train_one() != 1000 { ok = false; }
  if sched_decimals() != 3 { ok = false; }
  if sched_one() != 1000 { ok = false; }
  if train_model_len(&m) != 2 { ok = false; }
  if train_model_weight(&m, 0) != 500 { ok = false; }
  if train_model_weight(&m, 1) != -250 { ok = false; }
  if train_model_bias(&m) != 100 { ok = false; }
  if train_model_weight(&m, 2) != TRAIN_NONE { ok = false; }
  if train_model_weight(&m, -1) != TRAIN_NONE { ok = false; }
  return assert(ok, "scale accessors and model copies/reads");
}

fn t2() -> TestResult {
  var ok = int_of(sched_constant(0, 700)) == 700;
  if int_of(sched_constant(500000, 700)) != 700 { ok = false; }
  if int_of(sched_constant(3, 0)) != 0 { ok = false; }
  if !int_err(sched_constant(-1, 700), "training: schedule step must be non-negative") { ok = false; }
  if !int_err(sched_constant(0, 1000001), "training: base learning rate exceeds the supported envelope") { ok = false; }
  return assert(ok, "constant schedule and its validation");
}

fn t3() -> TestResult {
  var ok = int_of(sched_linear_warmup(0, 4, 1000)) == 250;
  if int_of(sched_linear_warmup(1, 4, 1000)) != 500 { ok = false; }
  if int_of(sched_linear_warmup(2, 4, 1000)) != 750 { ok = false; }
  if int_of(sched_linear_warmup(3, 4, 1000)) != 1000 { ok = false; }
  if int_of(sched_linear_warmup(4, 4, 1000)) != 1000 { ok = false; }
  if int_of(sched_linear_warmup(99, 4, 1000)) != 1000 { ok = false; }
  if !int_err(sched_linear_warmup(0, 0, 1000), "training: warmup_steps must be >= 1") { ok = false; }
  return assert(ok, "linear warmup reaches the base rate at the last warmup step");
}

fn t4() -> TestResult {
  var ok = int_of(sched_step_decay(0, 1000, 2, 500)) == 1000;
  if int_of(sched_step_decay(1, 1000, 2, 500)) != 1000 { ok = false; }
  if int_of(sched_step_decay(2, 1000, 2, 500)) != 500 { ok = false; }
  if int_of(sched_step_decay(3, 1000, 2, 500)) != 500 { ok = false; }
  if int_of(sched_step_decay(4, 1000, 2, 500)) != 250 { ok = false; }
  if int_of(sched_step_decay(5, 1000, 2, 500)) != 250 { ok = false; }
  if int_of(sched_step_decay(100000, 1000, 2, 500)) != 0 { ok = false; }
  if int_of(sched_step_decay(100000, 1000, 1, 1000)) != 1000 { ok = false; }
  if !int_err(sched_step_decay(0, 1000, 0, 500), "training: drop_every must be >= 1") { ok = false; }
  if !int_err(sched_step_decay(0, 1000, 1, 1001), "training: gamma must be in [0, 1000]") { ok = false; }
  return assert(ok, "step decay halves on the drop boundaries and saturates at zero");
}

fn t5() -> TestResult {
  var ok = int_of(sched_inverse_time(0, 1000, 10)) == 1000;
  if int_of(sched_inverse_time(10, 1000, 10)) != 500 { ok = false; }
  if int_of(sched_inverse_time(30, 1000, 10)) != 250 { ok = false; }
  if int_of(sched_inverse_time(90, 1000, 10)) != 100 { ok = false; }
  if int_of(sched_inverse_time(9990, 1000, 10)) != 1 { ok = false; }
  if int_of(sched_inverse_time(1, 999, 2)) != 666 { ok = false; }
  if !int_err(sched_inverse_time(0, 1000, 0), "training: decay must be >= 1") { ok = false; }
  return assert(ok, "inverse-time decay pins its half-life and rounds to nearest");
}

fn t6() -> TestResult {
  var ok = int_of(sched_poly_decay(0, 10, 1000, 100)) == 1000;
  if int_of(sched_poly_decay(2, 10, 1000, 100)) != 676 { ok = false; }
  if int_of(sched_poly_decay(5, 10, 1000, 100)) != 325 { ok = false; }
  if int_of(sched_poly_decay(10, 10, 1000, 100)) != 100 { ok = false; }
  if int_of(sched_poly_decay(15, 10, 1000, 100)) != 100 { ok = false; }
  if !int_err(sched_poly_decay(0, 0, 1000, 100), "training: total_steps must be >= 1") { ok = false; }
  if !int_err(sched_poly_decay(0, 10, 1000, 1001), "training: min_lr must not exceed base_lr") { ok = false; }
  return assert(ok, "quadratic decay interpolates from base to min over the horizon");
}

fn t7() -> TestResult {
  var ok = int_of(sched_warmup_poly(0, 2, 10, 1000, 0)) == 500;
  if int_of(sched_warmup_poly(1, 2, 10, 1000, 0)) != 1000 { ok = false; }
  if int_of(sched_warmup_poly(2, 2, 10, 1000, 0)) != 640 { ok = false; }
  if int_of(sched_warmup_poly(9, 2, 10, 1000, 0)) != 10 { ok = false; }
  if int_of(sched_warmup_poly(10, 2, 10, 1000, 0)) != 0 { ok = false; }
  if !int_err(sched_warmup_poly(0, 2, 1, 1000, 0), "training: total_steps must be >= warmup_steps") { ok = false; }
  return assert(ok, "warmup then quadratic decay composes both phases");
}

fn t8() -> TestResult {
  var ok = int_err(sched_constant(0, -5), "training: base learning rate must be non-negative");
  if !int_err(sched_constant(1000000001, 1), "training: schedule step exceeds the supported envelope") { ok = false; }
  if !int_err(sched_step_decay(0, 1000, 1, -1), "training: gamma must be in [0, 1000]") { ok = false; }
  if !int_err(sched_inverse_time(1000000001, 1, 1), "training: schedule step exceeds the supported envelope") { ok = false; }
  if !int_err(sched_poly_decay(0, 10, 1000, -1), "training: min_lr must be non-negative") { ok = false; }
  if !int_err(sched_poly_decay(0, 1000000001, 1000, 0), "training: total_steps exceeds the supported envelope") { ok = false; }
  return assert(ok, "schedule validation rejects every out-of-envelope input");
}

// ---------------------------------------------------------------------------
// Trainer
// ---------------------------------------------------------------------------

fn t9() -> TestResult {
  let w = v2(1000, -500);
  let m = train_model_new(&w, 200);
  let xs = v2(1000, 2000);
  var ok = int_of(train_predict(&m, &xs, 0, 2)) == 200;
  let xs2 = v2(3000, 4000);
  if int_of(train_predict(&m, &xs2, 0, 2)) != 1200 { ok = false; }
  if !int_err(train_predict(&m, &xs, 0, 1), "training: model width does not match nfeat") { ok = false; }
  if !int_err(train_predict(&m, &xs, 1, 2), "training: dataset does not cover the requested row") { ok = false; }
  if !int_err(train_predict(&m, &xs, -1, 2), "training: row index must be non-negative") { ok = false; }
  return assert(ok, "prediction is the fixed-point dot product plus bias");
}

fn t10() -> TestResult {
  let w = v1(1000);
  let m = train_model_new(&w, 0);
  let xs = v1(1000);
  var ok = int_of(train_loss_row(&m, &xs, 0, 1, 500, cb_loss_sq)) == 250;
  if int_of(train_loss_row(&m, &xs, 0, 1, 500, train_loss_squared)) != 250 { ok = false; }
  if int_of(train_loss_row(&m, &xs, 0, 1, 500, train_loss_abs)) != 500 { ok = false; }
  if !int_err(train_loss_row(&m, &xs, 0, 1, 1000001, cb_loss_sq), "training: target magnitude exceeds the supported envelope") { ok = false; }
  return assert(ok, "loss rows run module and caller callbacks over the prediction");
}

fn t11() -> TestResult {
  let w = v2(1000, -500);
  let m = train_model_new(&w, 0);
  let xs = v2(1000, 2000);
  let g = ints_of(train_grad_row(&m, &xs, 0, 2, 500, cb_grad_sq));
  var ok = g.len() == 3;
  if g.len() == 3 {
    let g0: Int = g[0];
    let g1: Int = g[1];
    let g2: Int = g[2];
    if g0 != -1000 { ok = false; }
    if g1 != -2000 { ok = false; }
    if g2 != -1000 { ok = false; }
  }
  let gb = ints_of(train_grad_row(&m, &xs, 0, 2, 500, train_grad_squared));
  if gb.len() != 3 { ok = false; }
  if !ints_err(train_grad_row(&m, &xs, 0, 2, 500, cb_grad_huge), "training: gradient callback value exceeds the supported envelope") { ok = false; }
  return assert(ok, "gradient rows scale the callback value by each feature");
}

fn ints_err(r: Result[Vec[Int], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn t12() -> TestResult {
  let w = v1(1000);
  let m = train_model_new(&w, 0);
  let xs = v1(1000);
  let step = model_of(train_sgd_step(&m, &xs, 0, 1, 500, 100, cb_grad_sq));
  var ok = train_model_weight(&step, 0) == 900;
  if train_model_bias(&step) != -100 { ok = false; }
  if train_model_weight(&m, 0) != 1000 { ok = false; }
  if train_model_bias(&m) != 0 { ok = false; }
  let after = int_of(train_loss_row(&step, &xs, 0, 1, 500, cb_loss_sq));
  if after != 90 { ok = false; }
  if !model_err(train_sgd_step(&m, &xs, 0, 1, 500, -1, cb_grad_sq), "training: learning rate must be non-negative") { ok = false; }
  return assert(ok, "one SGD step descends and leaves the input model untouched");
}

fn t13() -> TestResult {
  let w = v1(0);
  let m = train_model_new(&w, 0);
  let xs = v2(1000, 2000);
  let ys = v2(500, 1000);
  let after = model_of(train_epoch_sgd(&m, &xs, &ys, 2, 1, 100, cb_grad_sq));
  var ok = train_model_weight(&after, 0) == 380;
  if train_model_bias(&after) != 240 { ok = false; }
  if train_model_weight(&m, 0) != 0 { ok = false; }
  let none = model_of(train_epoch_sgd(&m, &xs, &ys, 0, 1, 100, cb_grad_sq));
  if !same_model(&none, &m) { ok = false; }
  return assert(ok, "an epoch threads the model through every row step");
}

fn t14() -> TestResult {
  let w = v1(0);
  let m = train_model_new(&w, 0);
  let xs = v2(1000, 2000);
  let ys = v2(500, 1000);
  var ok = int_of(train_epoch_loss(&m, &xs, &ys, 2, 1, cb_loss_sq)) == 625;
  if !int_err(train_epoch_loss(&m, &xs, &ys, 0, 1, cb_loss_sq), "training: epoch loss needs at least one row") { ok = false; }
  let short = v1(500);
  if !int_err(train_epoch_loss(&m, &xs, &short, 2, 1, cb_loss_sq), "training: labels do not cover nrows") { ok = false; }
  return assert(ok, "epoch loss averages the per-row losses");
}

fn t15() -> TestResult {
  let w = v1(0);
  let m = train_model_new(&w, 0);
  let xs = v2(1000, 2000);
  let ys = v2(500, 1000);
  let run = model_of(train_run(&m, &xs, &ys, 2, 1, 100, 3, cb_grad_sq));
  var manual = train_epoch_sgd(&m, &xs, &ys, 2, 1, 100, cb_grad_sq);
  manual = train_epoch_sgd(&model_of(manual), &xs, &ys, 2, 1, 100, cb_grad_sq);
  manual = train_epoch_sgd(&model_of(manual), &xs, &ys, 2, 1, 100, cb_grad_sq);
  var ok = same_model(&run, &model_of(manual));
  let zero = model_of(train_run(&m, &xs, &ys, 2, 1, 100, 0, cb_grad_sq));
  if !same_model(&zero, &m) { ok = false; }
  if !model_err(train_run(&m, &xs, &ys, 2, 1, 100, 100001, cb_grad_sq), "training: epochs exceed the supported envelope") { ok = false; }
  return assert(ok, "train_run equals the explicit epoch chain");
}

fn t16() -> TestResult {
  let w = v1(1000);
  let m = train_model_new(&w, 0);
  let big = v1(2000000);
  var ok = int_err(train_predict(&m, &big, 0, 1), "training: feature magnitude exceeds the supported envelope");
  let wide = train_model_new(&big, 0);
  let one = v1(1);
  if !int_err(train_predict(&wide, &one, 0, 1), "training: weight magnitude exceeds the supported envelope") { ok = false; }
  let biased = train_model_new(&one, 2000000);
  if !int_err(train_predict(&biased, &v1(1000), 0, 1), "training: bias magnitude exceeds the supported envelope") { ok = false; }
  if !int_err(train_predict(&m, &one, 0, 0), "training: nfeat must be >= 1") { ok = false; }
  return assert(ok, "trainer rejects envelope and shape violations");
}

// ---------------------------------------------------------------------------
// Early stopping
// ---------------------------------------------------------------------------

fn t17() -> TestResult {
  let s = es_of(es_new_min(100, 3, 5));
  var ok = es_best(&s) == 100;
  if es_bad(&s) != 0 { ok = false; }
  if es_patience(&s) != 3 { ok = false; }
  if es_min_delta(&s) != 5 { ok = false; }
  if es_mode(&s) != ES_MODE_MIN { ok = false; }
  if es_stopped(&s) { ok = false; }
  let mx = es_of(es_new_max(50, 2, 1));
  if es_mode(&mx) != ES_MODE_MAX { ok = false; }
  if !es_err(es_new_min(0, 0, 0), "training: early-stop patience must be >= 1") { ok = false; }
  if !es_err(es_new_max(0, 1, -1), "training: early-stop min_delta must be non-negative") { ok = false; }
  return assert(ok, "early-stop constructors and accessors");
}

fn t18() -> TestResult {
  var s = es_of(es_new_min(100, 2, 5));
  s = es_update(s, 102);
  var ok = !es_stopped(&s) && es_bad(&s) == 1 && es_best(&s) == 100;
  s = es_update(s, 96);
  if !es_stopped(&s) { ok = false; }
  if es_bad(&s) != 2 { ok = false; }
  if es_best(&s) != 100 { ok = false; }
  s = es_update(s, 200);
  if !es_stopped(&s) || es_bad(&s) != 2 { ok = false; }
  var i = es_of(es_new_min(100, 3, 5));
  i = es_update(i, 94);
  if es_best(&i) != 94 || es_bad(&i) != 0 { ok = false; }
  i = es_update(i, 89);
  if es_bad(&i) != 1 { ok = false; }
  i = es_update(i, 88);
  if es_best(&i) != 88 || es_bad(&i) != 0 { ok = false; }
  return assert(ok, "min-mode updates require a strict min_delta improvement");
}

fn t19() -> TestResult {
  var s = es_of(es_new_max(50, 2, 1));
  s = es_update(s, 51);
  var ok = es_bad(&s) == 1 && !es_stopped(&s);
  s = es_update(s, 52);
  if es_best(&s) != 52 || es_bad(&s) != 0 { ok = false; }
  s = es_update(s, 51);
  if es_bad(&s) != 1 { ok = false; }
  s = es_update(s, 51);
  if !es_stopped(&s) || es_bad(&s) != 2 { ok = false; }
  return assert(ok, "max-mode updates improve upward by more than min_delta");
}

fn t20() -> TestResult {
  let stale = v3(100, 100, 99);
  var s = es_of(es_run(&stale, 2, 1, ES_MODE_MIN));
  var ok = es_stopped(&s);
  if es_best(&s) != 100 { ok = false; }
  if es_bad(&s) != 2 { ok = false; }
  let improving = v3(100, 90, 80);
  let i = es_of(es_run(&improving, 3, 1, ES_MODE_MIN));
  if es_stopped(&i) { ok = false; }
  if es_best(&i) != 80 { ok = false; }
  if es_bad(&i) != 0 { ok = false; }
  if !es_err(es_run(&improving, 3, 1, 2), "training: early-stop mode must be ES_MODE_MIN or ES_MODE_MAX") { ok = false; }
  if !es_err(es_run(&empty_vec(), 1, 0, ES_MODE_MIN), "training: early-stop run needs at least one metric") { ok = false; }
  return assert(ok, "es_run scans until patience is exhausted");
}

// ---------------------------------------------------------------------------
// Logger
// ---------------------------------------------------------------------------

fn t21() -> TestResult {
  let l0 = tlog_new();
  var ok = tlog_len(&l0) == 0;
  if !tlog_is_consistent(&l0) { ok = false; }
  if tlog_last_loss(&l0) != TRAIN_NONE { ok = false; }
  if tlog_mean_loss(&l0) != TRAIN_NONE { ok = false; }
  if tlog_min_loss(&l0) != TRAIN_NONE { ok = false; }
  if tlog_best_step(&l0) != TRAIN_NONE { ok = false; }
  if !streq(tlog_summary(&l0), "n=0 last=none mean=none best_step=none") { ok = false; }
  let l1 = tlog_record(&l0, 0, 10);
  let l2 = tlog_record(&l1, 1, 20);
  let l3 = tlog_record(&l2, 2, 11);
  if tlog_len(&l3) != 3 { ok = false; }
  if tlog_step(&l3, 0) != 0 || tlog_step(&l3, 2) != 2 { ok = false; }
  if tlog_loss(&l3, 1) != 20 { ok = false; }
  if tlog_last_loss(&l3) != 11 { ok = false; }
  if tlog_min_loss(&l3) != 10 { ok = false; }
  if tlog_best_step(&l3) != 0 { ok = false; }
  if tlog_mean_loss(&l3) != 14 { ok = false; }
  if tlog_step(&l3, 3) != TRAIN_NONE { ok = false; }
  if tlog_loss(&l3, -1) != TRAIN_NONE { ok = false; }
  return assert(ok, "log rows, aggregates and empty-log sentinels");
}

fn t22() -> TestResult {
  let l1 = tlog_record(&tlog_new(), 0, 10);
  let l2 = tlog_record(&l1, 1, 20);
  var ok = tlog_len(&l1) == 1;
  if tlog_last_loss(&l1) != 10 { ok = false; }
  if !streq(tlog_summary(&l2), "n=2 last=20 mean=15 best_step=0") { ok = false; }
  let neg = tlog_record(&tlog_record(&tlog_new(), 0, -1), 1, -2);
  if tlog_mean_loss(&neg) != -2 { ok = false; }
  let drifted = TrainLog{ steps: v2(0, 1); losses: v1(5); };
  if tlog_is_consistent(&drifted) { ok = false; }
  if tlog_min_loss(&drifted) != TRAIN_NONE { ok = false; }
  if !streq(tlog_summary(&drifted), "drift") { ok = false; }
  let repaired = tlog_record(&drifted, 2, 7);
  if tlog_len(&repaired) != 2 { ok = false; }
  if !tlog_is_consistent(&repaired) { ok = false; }
  if tlog_step(&repaired, 1) != 2 || tlog_loss(&repaired, 1) != 7 { ok = false; }
  return assert(ok, "log threads through returns and repairs drifted inputs");
}

// ---------------------------------------------------------------------------
// Checkpoint
// ---------------------------------------------------------------------------

fn t23() -> TestResult {
  let w = v3(1, 2, 3);
  let mm = v3(4, 5, 6);
  let c = ckpt_of(ckpt_new(7, "run-a", &w, &mm));
  var ok = ckpt_step(&c) == 7;
  if !streq(ckpt_tag(&c), "run-a") { ok = false; }
  if ckpt_len(&c) != 3 { ok = false; }
  if !ckpt_is_consistent(&c) { ok = false; }
  if ckpt_weight(&c, 0) != 1 || ckpt_weight(&c, 2) != 3 { ok = false; }
  if ckpt_momentum(&c, 1) != 5 { ok = false; }
  if ckpt_weight(&c, 3) != TRAIN_NONE { ok = false; }
  if ckpt_momentum(&c, -1) != TRAIN_NONE { ok = false; }
  if !same_vec(&ckpt_weights(&c), &w) { ok = false; }
  if !same_vec(&ckpt_momenta(&c), &mm) { ok = false; }
  let e = ckpt_of(ckpt_new(0, "empty", &empty_vec(), &empty_vec()));
  if ckpt_len(&e) != 0 || !ckpt_is_consistent(&e) { ok = false; }
  if ckpt_weight(&e, 0) != TRAIN_NONE { ok = false; }
  if !ckpt_err(ckpt_new(-1, "t", &w, &mm), "training: checkpoint step must be non-negative") { ok = false; }
  if !ckpt_err(ckpt_new(0, "", &w, &mm), "training: checkpoint tag must be 1-32 chars of [A-Za-z0-9_-]") { ok = false; }
  if !ckpt_err(ckpt_new(0, "bad tag", &w, &mm), "training: checkpoint tag must be 1-32 chars of [A-Za-z0-9_-]") { ok = false; }
  if !ckpt_err(ckpt_new(0, "t", &w, &v2(1, 2)), "training: checkpoint weights and momenta must have equal length") { ok = false; }
  return assert(ok, "checkpoint capture copies parallel model and optimizer state");
}

fn t24() -> TestResult {
  let w = v3(1, 2, 3);
  let mm = v3(4, 5, 6);
  let c = ckpt_of(ckpt_new(7, "run-a", &w, &mm));
  let s = ckpt_serialize(&c);
  var ok = streq(s, "xtr1|7|run-a|3|1,2,3|4,5,6");
  let p = ckpt_of(ckpt_parse(s));
  if ckpt_step(&p) != 7 { ok = false; }
  if !streq(ckpt_tag(&p), "run-a") { ok = false; }
  if !same_vec(&ckpt_weights(&p), &w) { ok = false; }
  if !same_vec(&ckpt_momenta(&p), &mm) { ok = false; }
  if ckpt_stamp(&p) != ckpt_stamp(&c) { ok = false; }
  let n = ckpt_of(ckpt_new(0, "neg", &v3(-1, 0, 2), &v3(0, 0, 0)));
  if !streq(ckpt_serialize(&n), "xtr1|0|neg|3|-1,0,2|0,0,0") { ok = false; }
  let np = ckpt_of(ckpt_parse(ckpt_serialize(&n)));
  if ckpt_weight(&np, 0) != -1 || ckpt_weight(&np, 2) != 2 { ok = false; }
  let e = ckpt_of(ckpt_new(3, "em", &empty_vec(), &empty_vec()));
  if !streq(ckpt_serialize(&e), "xtr1|3|em|0||") { ok = false; }
  if ckpt_len(&ckpt_of(ckpt_parse("xtr1|3|em|0||"))) != 0 { ok = false; }
  return assert(ok, "the checkpoint text codec round-trips pinned values");
}

fn t25() -> TestResult {
  var ok = ckpt_err(ckpt_parse(""), "training: checkpoint: bad magic");
  if !ckpt_err(ckpt_parse("atr1|7|run-a|3|1,2,3|4,5,6"), "training: checkpoint: bad magic") { ok = false; }
  if !ckpt_err(ckpt_parse("xtr1|7|run-a"), "training: checkpoint: empty integer field") { ok = false; }
  if !ckpt_err(ckpt_parse("xtr1|-1|run-a|0||"), "training: checkpoint: negative step") { ok = false; }
  if !ckpt_err(ckpt_parse("xtr1|7|bad tag|0||"), "training: checkpoint: bad tag") { ok = false; }
  if !ckpt_err(ckpt_parse("xtr1|7|run-a|5000|1|1"), "training: checkpoint: entry count out of range") { ok = false; }
  if !ckpt_err(ckpt_parse("xtr1|7|run-a|3|1,2|4,5,6"), "training: checkpoint: too few entries") { ok = false; }
  if !ckpt_err(ckpt_parse("xtr1|7|run-a|2|1,2,3|4,5"), "training: checkpoint: too many entries") { ok = false; }
  if !ckpt_err(ckpt_parse("xtr1|7|run-a|3|1,x,3|4,5,6"), "training: checkpoint: non-digit in integer field") { ok = false; }
  if !ckpt_err(ckpt_parse("xtr1|7|run-a|3|1,2,3|4,5,6|9"), "training: checkpoint: trailing fields") { ok = false; }
  return assert(ok, "the checkpoint parser rejects every malformed class");
}

fn t26() -> TestResult {
  let w = v2(300, 700);
  let m = train_model_new(&w, 50);
  let ws = model_weights(&m);
  let c = ckpt_of(ckpt_new(4, "restore", &ws, &zeros(2)));
  let p = ckpt_of(ckpt_parse(ckpt_serialize(&c)));
  let restored = train_model_new(&ckpt_weights(&p), train_model_bias(&m));
  let xs = v2(1000, 2000);
  var ok = same_model(&m, &restored);
  if int_of(train_predict(&m, &xs, 0, 2)) != int_of(train_predict(&restored, &xs, 0, 2)) { ok = false; }
  let l = tlog_record(&tlog_record(&tlog_new(), 0, 250), 1, 90);
  var sched_ok = int_of(sched_step_decay(1, 1000, 1, 500)) == 500;
  if !sched_ok { ok = false; }
  if tlog_best_step(&l) != 1 { ok = false; }
  return assert(ok, "restore rebuilds the model and the five libraries compose");
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.training conformance tests ===");
  var failed: Int = 0;
  failed = failed + report(t1());
  failed = failed + report(t2());
  failed = failed + report(t3());
  failed = failed + report(t4());
  failed = failed + report(t5());
  failed = failed + report(t6());
  failed = failed + report(t7());
  failed = failed + report(t8());
  failed = failed + report(t9());
  failed = failed + report(t10());
  failed = failed + report(t11());
  failed = failed + report(t12());
  failed = failed + report(t13());
  failed = failed + report(t14());
  failed = failed + report(t15());
  failed = failed + report(t16());
  failed = failed + report(t17());
  failed = failed + report(t18());
  failed = failed + report(t19());
  failed = failed + report(t20());
  failed = failed + report(t21());
  failed = failed + report(t22());
  failed = failed + report(t23());
  failed = failed + report(t24());
  failed = failed + report(t25());
  failed = failed + report(t26());
  if failed == 0 {
    io.println("xiom.training: all tests passed");
  } else {
    io.println("xiom.training: tests failed");
  }
  return failed;
}
