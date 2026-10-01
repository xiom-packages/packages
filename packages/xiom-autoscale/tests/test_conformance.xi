// XIOM -- xiom.autoscale conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixture-driven conformance suite for the pure-XIOM autoscaling policy
// model: ring-buffer windows and aggregates, policy invariants, fixed and
// proportional steps, hysteresis, consecutive breaches, per-direction
// cooldowns, replica bounds, decision records with reasons, window-driven
// ticks, invalid-policy refusal, determinism and the text catalogs. No
// external fixture files.
//
// Read-only accessors are wrapped in helpers that take `&mut`, so a `&local`
// read call is never followed by a `&mut local` call in the same function
// body (advisory E001). Each helper calls the real `&`-based API. All Str
// equality goes through compare.str_compare (BUG 17).

module autoscale_tests
use xiom.io; use xiom.test; use xiom.autoscale;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

fn policy_fixture(metric: Str, lo: Int, hi: Int, up: Int, down: Int, hyst: Int) -> AutoscalePolicy {
  return autoscale_policy_new(metric, lo, hi, up, down, hyst);
}

fn policy_fixture_step1(metric: Str, lo: Int, hi: Int, up: Int, down: Int) -> AutoscalePolicy {
  return autoscale_policy_with_step_fixed(policy_fixture(metric, lo, hi, up, down, 1), 1);
}

// Deterministic controller pair fixture for the determinism test.
fn det_policy() -> AutoscalePolicy {
  return autoscale_policy_with_cooldowns(
    autoscale_policy_with_breach(policy_fixture_step1("cpu", 1, 30, 8000, 3000), 2),
    4, 4
  );
}

// --------------------------------------------------
//  Read-only wrappers (advisory E001 discipline)
// --------------------------------------------------

fn ser_cap(s: &mut AutoscaleSeries) -> Int { return autoscale_series_capacity(s); }
fn ser_count(s: &mut AutoscaleSeries) -> Int { return autoscale_series_count(s); }
fn ser_len(s: &mut AutoscaleSeries) -> Int { return autoscale_series_len(s); }
fn ser_at(s: &mut AutoscaleSeries, i: Int) -> Int { return autoscale_series_at(s, i); }
fn ser_sum(s: &mut AutoscaleSeries, w: Int) -> Int { return autoscale_series_sum(s, w); }
fn ser_min(s: &mut AutoscaleSeries, w: Int) -> Int { return autoscale_series_min(s, w); }
fn ser_max(s: &mut AutoscaleSeries, w: Int) -> Int { return autoscale_series_max(s, w); }
fn ser_avg(s: &mut AutoscaleSeries, w: Int) -> Int { return autoscale_series_avg(s, w); }

fn ctl_replicas(c: &mut AutoscaleController) -> Int { return autoscale_controller_replicas(c); }
fn ctl_ticks(c: &mut AutoscaleController) -> Int { return autoscale_controller_ticks(c); }
fn ctl_up_streak(c: &mut AutoscaleController) -> Int { return autoscale_controller_up_streak(c); }
fn ctl_down_streak(c: &mut AutoscaleController) -> Int { return autoscale_controller_down_streak(c); }
fn ctl_up_tick(c: &mut AutoscaleController) -> Int { return autoscale_controller_last_up_tick(c); }
fn ctl_down_tick(c: &mut AutoscaleController) -> Int { return autoscale_controller_last_down_tick(c); }
fn ctl_series_len(c: &mut AutoscaleController) -> Int { return autoscale_controller_series_len(c); }
fn ctl_series_at(c: &mut AutoscaleController, i: Int) -> Int { return autoscale_controller_series_at(c, i); }
fn ctl_series_avg(c: &mut AutoscaleController, w: Int) -> Int { return autoscale_controller_series_avg(c, w); }
fn ctl_rec_count(c: &mut AutoscaleController) -> Int { return autoscale_controller_record_count(c); }
fn ctl_rec_tick(c: &mut AutoscaleController, i: Int) -> Int { return autoscale_controller_record_tick(c, i); }
fn ctl_rec_action(c: &mut AutoscaleController, i: Int) -> Int { return autoscale_controller_record_action(c, i); }
fn ctl_rec_from(c: &mut AutoscaleController, i: Int) -> Int { return autoscale_controller_record_from(c, i); }
fn ctl_rec_to(c: &mut AutoscaleController, i: Int) -> Int { return autoscale_controller_record_to(c, i); }
fn ctl_rec_reason(c: &mut AutoscaleController, i: Int) -> Int { return autoscale_controller_record_reason(c, i); }
fn ctl_rec_detail(c: &mut AutoscaleController, i: Int) -> Int { return autoscale_controller_record_detail(c, i); }
fn ctl_last_reason(c: &mut AutoscaleController) -> Int { return autoscale_controller_last_reason(c); }
fn ctl_policy(c: &mut AutoscaleController) -> AutoscalePolicy { return autoscale_controller_policy(c); }

// --------------------------------------------------
//  Series tests
// --------------------------------------------------

fn t1() -> TestResult {
  let a = autoscale_series_new(0);
  let b = autoscale_series_new(-5);
  let c = autoscale_series_new(2000000);
  let d = autoscale_series_new(4);
  var ok = autoscale_series_capacity(&a) == 1;
  if autoscale_series_capacity(&b) != 1 { ok = false; }
  if autoscale_series_capacity(&c) != 1000000 { ok = false; }
  if autoscale_series_len(&d) != 0 { ok = false; }
  if autoscale_series_count(&d) != 0 { ok = false; }
  if autoscale_series_sum(&d, 2) != 0 { ok = false; }
  if autoscale_series_min(&d, 2) != 0 { ok = false; }
  if autoscale_series_max(&d, 2) != 0 { ok = false; }
  if autoscale_series_avg(&d, 2) != 0 { ok = false; }
  if autoscale_series_at(&d, 0) != 0 { ok = false; }
  return assert(ok, "series capacity clamps and empty aggregates are zero");
}

fn t2() -> TestResult {
  var s = autoscale_series_new(3);
  autoscale_series_push(&mut s, 10);
  autoscale_series_push(&mut s, 20);
  autoscale_series_push(&mut s, 30);
  var ok = ser_len(&mut s) == 3;
  if ser_count(&mut s) != 3 { ok = false; }
  if ser_at(&mut s, 0) != 10 { ok = false; }
  if ser_at(&mut s, 1) != 20 { ok = false; }
  if ser_at(&mut s, 2) != 30 { ok = false; }
  autoscale_series_push(&mut s, 40);
  if ser_at(&mut s, 0) != 20 { ok = false; }
  if ser_at(&mut s, 1) != 30 { ok = false; }
  if ser_at(&mut s, 2) != 40 { ok = false; }
  if ser_count(&mut s) != 4 { ok = false; }
  autoscale_series_push(&mut s, 50);
  autoscale_series_push(&mut s, 60);
  if ser_at(&mut s, 0) != 40 { ok = false; }
  if ser_at(&mut s, 1) != 50 { ok = false; }
  if ser_at(&mut s, 2) != 60 { ok = false; }
  if ser_at(&mut s, 3) != 0 { ok = false; }
  if ser_at(&mut s, -1) != 0 { ok = false; }
  if ser_len(&mut s) != 3 { ok = false; }
  return assert(ok, "ring buffer keeps the newest samples in chronological order");
}

fn t3() -> TestResult {
  var s = autoscale_series_new(8);
  autoscale_series_push(&mut s, 5);
  autoscale_series_push(&mut s, 10);
  autoscale_series_push(&mut s, 15);
  autoscale_series_push(&mut s, 20);
  autoscale_series_push(&mut s, 25);
  var ok = ser_sum(&mut s, 2) == 45;
  if ser_sum(&mut s, 5) != 75 { ok = false; }
  if ser_sum(&mut s, 9) != 75 { ok = false; }
  if ser_sum(&mut s, 0) != 0 { ok = false; }
  if ser_sum(&mut s, -1) != 0 { ok = false; }
  if ser_min(&mut s, 2) != 20 { ok = false; }
  if ser_max(&mut s, 2) != 25 { ok = false; }
  if ser_avg(&mut s, 2) != 22 { ok = false; }
  if ser_avg(&mut s, 5) != 15 { ok = false; }
  if ser_min(&mut s, 0) != 0 { ok = false; }
  if ser_max(&mut s, 0) != 0 { ok = false; }
  if ser_avg(&mut s, 0) != 0 { ok = false; }
  return assert(ok, "rolling window aggregates use the last N samples");
}

fn t4() -> TestResult {
  var a = autoscale_series_new(4);
  autoscale_series_push(&mut a, 10);
  autoscale_series_push(&mut a, 15);
  var b = autoscale_series_new(4);
  autoscale_series_push(&mut b, -10);
  autoscale_series_push(&mut b, -15);
  var ok = ser_sum(&mut a, 2) == 25;
  if ser_avg(&mut a, 2) != 12 { ok = false; }
  if ser_sum(&mut b, 2) != -25 { ok = false; }
  if ser_avg(&mut b, 2) != -12 { ok = false; }
  if ser_min(&mut b, 2) != -15 { ok = false; }
  if ser_max(&mut b, 2) != -10 { ok = false; }
  return assert(ok, "integer average truncates toward zero for both signs");
}

// --------------------------------------------------
//  Policy tests
// --------------------------------------------------

fn t5() -> TestResult {
  let p = policy_fixture("cpu", 1, 10, 8000, 3000, 1000);
  var ok = p.up_cooldown == 0 && p.down_cooldown == 0 && p.breach_threshold == 1;
  if p.step_mode != 0 || p.step_fixed != 1 || p.step_bps != 0 { ok = false; }
  if p.series_capacity != 16 { ok = false; }
  let q = autoscale_policy_with_cooldowns(p, 3, 5);
  if q.up_cooldown != 3 || q.down_cooldown != 5 { ok = false; }
  if q.up_threshold != 8000 || q.min_replicas != 1 { ok = false; }
  let r = autoscale_policy_with_breach(q, 2);
  if r.breach_threshold != 2 || r.up_cooldown != 3 { ok = false; }
  let f = autoscale_policy_with_step_fixed(r, 4);
  if f.step_mode != 0 || f.step_fixed != 4 || f.step_bps != 0 { ok = false; }
  let b = autoscale_policy_with_step_bps(f, 2500);
  if b.step_mode != 1 || b.step_bps != 2500 { ok = false; }
  let c = autoscale_policy_with_series_capacity(b, 32);
  if c.series_capacity != 32 { ok = false; }
  if c.metric.len() != 3 { ok = false; }
  return assert(ok, "policy constructor defaults and builders derive copies");
}

fn t6() -> TestResult {
  let p = policy_fixture("cpu", 0, 10, 8000, 3000, 1000);
  let q = autoscale_policy_with_step_bps(policy_fixture("m", 1, 1, 5001, 5000, 1), 1);
  let r = policy_fixture("m", 5, 5, 10, 9, 1);
  var ok = autoscale_policy_check(&p) == 0;
  if autoscale_policy_check(&q) != 0 { ok = false; }
  if autoscale_policy_check(&r) != 0 { ok = false; }
  if !autoscale_policy_check_ok(&p) { ok = false; }
  if !streq(autoscale_policy_error_text(0), "ok") { ok = false; }
  return assert(ok, "well-formed policies pass the invariant checker");
}

fn t7() -> TestResult {
  let bad1 = policy_fixture("", 0, 10, 8000, 3000, 1000);
  let bad2 = policy_fixture("cpu", -1, 10, 8000, 3000, 1000);
  let bad3 = policy_fixture("cpu", 5, 4, 8000, 3000, 1000);
  let bad4 = policy_fixture("cpu", 0, 1000000001, 8000, 3000, 1000);
  let bad5 = policy_fixture("cpu", 0, 10, 3000, 3000, 0);
  let bad6 = policy_fixture("cpu", 0, 10, 8000, 3000, -1);
  let bad7 = policy_fixture("cpu", 0, 10, 8000, 3000, 6000);
  let bad8 = autoscale_policy_with_cooldowns(policy_fixture("cpu", 0, 10, 8000, 3000, 1000), -1, 0);
  let bad9 = autoscale_policy_with_breach(policy_fixture("cpu", 0, 10, 8000, 3000, 1000), 0);
  var bad10 = policy_fixture("cpu", 0, 10, 8000, 3000, 1000);
  bad10.step_mode = 7;
  let bad11 = autoscale_policy_with_step_fixed(policy_fixture("cpu", 0, 10, 8000, 3000, 1000), 0);
  let bad12 = autoscale_policy_with_step_bps(policy_fixture("cpu", 0, 10, 8000, 3000, 1000), 0);
  let bad13 = autoscale_policy_with_step_bps(policy_fixture("cpu", 0, 10, 8000, 3000, 1000), 10001);
  let bad14 = autoscale_policy_with_series_capacity(policy_fixture("cpu", 0, 10, 8000, 3000, 1000), 0);
  var ok = autoscale_policy_check(&bad1) == 1;
  if autoscale_policy_check(&bad2) != 2 { ok = false; }
  if autoscale_policy_check(&bad3) != 3 { ok = false; }
  if autoscale_policy_check(&bad4) != 4 { ok = false; }
  if autoscale_policy_check(&bad5) != 5 { ok = false; }
  if autoscale_policy_check(&bad6) != 6 { ok = false; }
  if autoscale_policy_check(&bad7) != 6 { ok = false; }
  if autoscale_policy_check(&bad8) != 7 { ok = false; }
  if autoscale_policy_check(&bad9) != 8 { ok = false; }
  if autoscale_policy_check(&bad10) != 9 { ok = false; }
  if autoscale_policy_check(&bad11) != 10 { ok = false; }
  if autoscale_policy_check(&bad12) != 11 { ok = false; }
  if autoscale_policy_check(&bad13) != 11 { ok = false; }
  if autoscale_policy_check(&bad14) != 12 { ok = false; }
  if !streq(autoscale_policy_error_text(5), "up_threshold must exceed down_threshold") { ok = false; }
  if !streq(autoscale_policy_error_text(99), "unknown policy code") { ok = false; }
  return assert(ok, "policy checker reports the first violated invariant");
}

fn t8() -> TestResult {
  let p = autoscale_policy_with_step_fixed(policy_fixture("cpu", 0, 1000, 8000, 3000, 1000), 3);
  let p0 = autoscale_policy_with_step_fixed(policy_fixture("cpu", 0, 1000, 8000, 3000, 1000), 0);
  let pb = autoscale_policy_with_step_bps(policy_fixture("cpu", 0, 1000, 8000, 3000, 1000), 2500);
  let pb2 = autoscale_policy_with_step_bps(policy_fixture("cpu", 0, 1000, 8000, 3000, 1000), 9999);
  let pb3 = autoscale_policy_with_step_bps(policy_fixture("cpu", 0, 1000, 8000, 3000, 1000), 10000);
  var ok = autoscale_step(&p, 10) == 3;
  if autoscale_step(&p0, 10) != 1 { ok = false; }
  if autoscale_step(&pb, 10) != 2 { ok = false; }
  if autoscale_step(&pb, 3) != 1 { ok = false; }
  if autoscale_step(&pb, 100) != 25 { ok = false; }
  if autoscale_step(&pb, 10000) != 2500 { ok = false; }
  if autoscale_step(&pb2, 9) != 8 { ok = false; }
  if autoscale_step(&pb3, 7) != 7 { ok = false; }
  if autoscale_step(&pb3, -5) != 1 { ok = false; }
  return assert(ok, "fixed and proportional (bps) steps clamp to at least one");
}

// --------------------------------------------------
//  Controller tests
// --------------------------------------------------

fn t9() -> TestResult {
  let p = policy_fixture("cpu", 2, 8, 8000, 3000, 1000);
  var a = autoscale_controller_new(p, 0);
  var b = autoscale_controller_new(p, 100);
  var c = autoscale_controller_new(p, 5);
  var ok = ctl_replicas(&mut a) == 2;
  if ctl_replicas(&mut b) != 8 { ok = false; }
  if ctl_replicas(&mut c) != 5 { ok = false; }
  if ctl_ticks(&mut c) != 0 { ok = false; }
  if ctl_rec_count(&mut c) != 0 { ok = false; }
  if ctl_last_reason(&mut c) != -1 { ok = false; }
  var d = autoscale_controller_new(autoscale_policy_with_cooldowns(p, 3, 3), 5);
  if ctl_up_tick(&mut d) != -3 { ok = false; }
  if ctl_down_tick(&mut d) != -3 { ok = false; }
  return assert(ok, "controller initial replicas clamp to the min/max bounds");
}

fn t10() -> TestResult {
  var c = autoscale_controller_new(policy_fixture_step1("cpu", 1, 10, 8000, 3000), 5);
  var ok = autoscale_controller_tick(&mut c, 5000) == 0;
  if ctl_replicas(&mut c) != 5 { ok = false; }
  if ctl_last_reason(&mut c) != 3 { ok = false; }
  if ctl_up_streak(&mut c) != 0 { ok = false; }
  if ctl_down_streak(&mut c) != 0 { ok = false; }
  if autoscale_controller_tick(&mut c, 7999) != 0 { ok = false; }
  if autoscale_controller_tick(&mut c, 3001) != 0 { ok = false; }
  if ctl_ticks(&mut c) != 3 { ok = false; }
  if ctl_rec_count(&mut c) != 3 { ok = false; }
  return assert(ok, "the hysteresis band holds and resets both streaks");
}

fn t11() -> TestResult {
  var c = autoscale_controller_new(policy_fixture_step1("cpu", 1, 10, 8000, 3000), 5);
  var ok = autoscale_controller_tick(&mut c, 8000) == 1;
  if ctl_replicas(&mut c) != 6 { ok = false; }
  if ctl_last_reason(&mut c) != 1 { ok = false; }
  if ctl_up_tick(&mut c) != 1 { ok = false; }
  if ctl_up_streak(&mut c) != 1 { ok = false; }
  if !streq(autoscale_reason_text(ctl_last_reason(&mut c)), "scale-up: up threshold breached") { ok = false; }
  if autoscale_controller_tick(&mut c, 8500) != 1 { ok = false; }
  if ctl_replicas(&mut c) != 7 { ok = false; }
  return assert(ok, "an inclusive up breach scales up by the fixed step");
}

fn t12() -> TestResult {
  var c = autoscale_controller_new(autoscale_policy_with_breach(policy_fixture_step1("cpu", 1, 10, 8000, 3000), 2), 5);
  var ok = autoscale_controller_tick(&mut c, 9000) == 0;
  if ctl_last_reason(&mut c) != 4 { ok = false; }
  if ctl_up_streak(&mut c) != 1 { ok = false; }
  if ctl_replicas(&mut c) != 5 { ok = false; }
  if autoscale_controller_tick(&mut c, 4500) != 0 { ok = false; }
  if ctl_up_streak(&mut c) != 0 { ok = false; }
  if ctl_last_reason(&mut c) != 3 { ok = false; }
  if autoscale_controller_tick(&mut c, 9000) != 0 { ok = false; }
  if ctl_up_streak(&mut c) != 1 { ok = false; }
  if autoscale_controller_tick(&mut c, 9000) != 1 { ok = false; }
  if ctl_replicas(&mut c) != 6 { ok = false; }
  if ctl_up_streak(&mut c) != 2 { ok = false; }
  return assert(ok, "consecutive-breach requirement counts and resets");
}

fn t13() -> TestResult {
  var c = autoscale_controller_new(autoscale_policy_with_cooldowns(policy_fixture_step1("cpu", 1, 20, 8000, 3000), 3, 2), 10);
  var ok = autoscale_controller_tick(&mut c, 9000) == 1;
  if ctl_up_tick(&mut c) != 1 { ok = false; }
  if ctl_replicas(&mut c) != 11 { ok = false; }
  if autoscale_controller_tick(&mut c, 9000) != 0 { ok = false; }
  if ctl_last_reason(&mut c) != 6 { ok = false; }
  if autoscale_controller_tick(&mut c, 9000) != 0 { ok = false; }
  if ctl_last_reason(&mut c) != 6 { ok = false; }
  if autoscale_controller_tick(&mut c, 9000) != 1 { ok = false; }
  if ctl_replicas(&mut c) != 12 { ok = false; }
  if autoscale_controller_tick(&mut c, 1000) != 2 { ok = false; }
  if ctl_down_tick(&mut c) != 5 { ok = false; }
  if ctl_replicas(&mut c) != 11 { ok = false; }
  if autoscale_controller_tick(&mut c, 1000) != 0 { ok = false; }
  if ctl_last_reason(&mut c) != 7 { ok = false; }
  if autoscale_controller_tick(&mut c, 9000) != 1 { ok = false; }
  if ctl_replicas(&mut c) != 12 { ok = false; }
  return assert(ok, "per-direction cooldowns gate each action independently");
}

fn t14() -> TestResult {
  let p = autoscale_policy_with_step_fixed(policy_fixture("cpu", 2, 12, 8000, 3000, 1000), 5);
  var c = autoscale_controller_new(p, 10);
  var ok = autoscale_controller_tick(&mut c, 9000) == 1;
  if ctl_replicas(&mut c) != 12 { ok = false; }
  if autoscale_controller_tick(&mut c, 9000) != 0 { ok = false; }
  if ctl_last_reason(&mut c) != 8 { ok = false; }
  var d = autoscale_controller_new(p, 4);
  if autoscale_controller_tick(&mut d, 1000) != 2 { ok = false; }
  if ctl_replicas(&mut d) != 2 { ok = false; }
  if autoscale_controller_tick(&mut d, 1000) != 0 { ok = false; }
  if ctl_last_reason(&mut d) != 9 { ok = false; }
  return assert(ok, "max/min bounds clamp targets and hold at the edge");
}

fn t15() -> TestResult {
  var c = autoscale_controller_new(autoscale_policy_with_step_bps(policy_fixture("cpu", 1, 100, 8000, 3000, 1000), 2500), 10);
  var ok = autoscale_controller_tick(&mut c, 9000) == 1;
  if ctl_replicas(&mut c) != 12 { ok = false; }
  if autoscale_controller_tick(&mut c, 9000) != 1 { ok = false; }
  if ctl_replicas(&mut c) != 15 { ok = false; }
  if autoscale_controller_tick(&mut c, 1000) != 2 { ok = false; }
  if ctl_replicas(&mut c) != 12 { ok = false; }
  return assert(ok, "proportional steps scale the current replica count");
}

fn t16() -> TestResult {
  let p = autoscale_policy_with_cooldowns(autoscale_policy_with_step_fixed(policy_fixture("cpu", 1, 20, 8000, 3000, 1000), 2), 5, 5);
  var c = autoscale_controller_new(p, 10);
  var ok = autoscale_controller_tick(&mut c, 9000) == 1;
  if autoscale_controller_tick(&mut c, 4500) != 0 { ok = false; }
  if autoscale_controller_tick(&mut c, 9000) != 0 { ok = false; }
  if ctl_rec_count(&mut c) != 3 { ok = false; }
  if ctl_rec_tick(&mut c, 0) != 1 { ok = false; }
  if ctl_rec_action(&mut c, 0) != 1 { ok = false; }
  if ctl_rec_from(&mut c, 0) != 10 { ok = false; }
  if ctl_rec_to(&mut c, 0) != 12 { ok = false; }
  if ctl_rec_reason(&mut c, 0) != 1 { ok = false; }
  if ctl_rec_detail(&mut c, 0) != 9000 { ok = false; }
  if ctl_rec_tick(&mut c, 1) != 2 { ok = false; }
  if ctl_rec_action(&mut c, 1) != 0 { ok = false; }
  if ctl_rec_from(&mut c, 1) != 12 { ok = false; }
  if ctl_rec_to(&mut c, 1) != 12 { ok = false; }
  if ctl_rec_reason(&mut c, 1) != 3 { ok = false; }
  if ctl_rec_detail(&mut c, 1) != 4500 { ok = false; }
  if ctl_rec_tick(&mut c, 2) != 3 { ok = false; }
  if ctl_rec_action(&mut c, 2) != 0 { ok = false; }
  if ctl_rec_reason(&mut c, 2) != 6 { ok = false; }
  if ctl_rec_detail(&mut c, 2) != 9000 { ok = false; }
  if ctl_rec_tick(&mut c, 9) != -1 { ok = false; }
  if ctl_rec_from(&mut c, -1) != -1 { ok = false; }
  if ctl_last_reason(&mut c) != 6 { ok = false; }
  return assert(ok, "decision records mirror tick/action/from/to/reason/detail");
}

fn t17() -> TestResult {
  var p = policy_fixture_step1("cpu", 1, 10, 8000, 3000);
  p.step_mode = 9;
  var c = autoscale_controller_new(p, 5);
  var ok = autoscale_controller_tick(&mut c, 9000) == -1;
  if ctl_ticks(&mut c) != 0 { ok = false; }
  if ctl_replicas(&mut c) != 5 { ok = false; }
  if ctl_rec_count(&mut c) != 1 { ok = false; }
  if ctl_rec_reason(&mut c, 0) != 10 { ok = false; }
  if ctl_rec_detail(&mut c, 0) != 9 { ok = false; }
  if ctl_series_len(&mut c) != 0 { ok = false; }
  if !streq(autoscale_reason_text(10), "refused: invalid policy") { ok = false; }
  return assert(ok, "an invalid policy is refused without advancing state");
}

fn t18() -> TestResult {
  var c = autoscale_controller_new(autoscale_policy_with_series_capacity(policy_fixture_step1("cpu", 1, 10, 5000, 2000), 4), 5);
  var ok = autoscale_controller_tick(&mut c, 4000) == 0;
  if ctl_series_len(&mut c) != 1 { ok = false; }
  if ctl_series_at(&mut c, 0) != 4000 { ok = false; }
  if autoscale_controller_tick_avg(&mut c, 6000, 2) != 1 { ok = false; }
  if ctl_replicas(&mut c) != 6 { ok = false; }
  if ctl_series_avg(&mut c, 2) != 5000 { ok = false; }
  if ctl_rec_detail(&mut c, 1) != 5000 { ok = false; }
  if ctl_series_at(&mut c, 1) != 6000 { ok = false; }
  if autoscale_controller_tick(&mut c, 2500) != 0 { ok = false; }
  if autoscale_controller_tick(&mut c, 2600) != 0 { ok = false; }
  if autoscale_controller_tick(&mut c, 2700) != 0 { ok = false; }
  if ctl_series_len(&mut c) != 4 { ok = false; }
  if ctl_series_at(&mut c, 0) != 6000 { ok = false; }
  if ctl_series_at(&mut c, 3) != 2700 { ok = false; }
  return assert(ok, "window averages can drive ticks and the ring stays bounded");
}

fn t19() -> TestResult {
  var a = autoscale_controller_new(det_policy(), 10);
  var b = autoscale_controller_new(det_policy(), 10);
  var ok = autoscale_controller_tick(&mut a, 9000) == autoscale_controller_tick(&mut b, 9000);
  if autoscale_controller_tick(&mut a, 9500) != autoscale_controller_tick(&mut b, 9500) { ok = false; }
  if autoscale_controller_tick(&mut a, 4000) != autoscale_controller_tick(&mut b, 4000) { ok = false; }
  if autoscale_controller_tick(&mut a, 9000) != autoscale_controller_tick(&mut b, 9000) { ok = false; }
  if autoscale_controller_tick(&mut a, 9000) != autoscale_controller_tick(&mut b, 9000) { ok = false; }
  if autoscale_controller_tick(&mut a, 1000) != autoscale_controller_tick(&mut b, 1000) { ok = false; }
  if autoscale_controller_tick(&mut a, 1000) != autoscale_controller_tick(&mut b, 1000) { ok = false; }
  if autoscale_controller_tick(&mut a, 9000) != autoscale_controller_tick(&mut b, 9000) { ok = false; }
  if ctl_replicas(&mut a) != ctl_replicas(&mut b) { ok = false; }
  if ctl_replicas(&mut a) != 10 { ok = false; }
  if ctl_ticks(&mut a) != 8 { ok = false; }
  if ctl_up_streak(&mut a) != 1 { ok = false; }
  if ctl_down_streak(&mut a) != 0 { ok = false; }
  if ctl_up_tick(&mut a) != 2 { ok = false; }
  if ctl_down_tick(&mut a) != 7 { ok = false; }
  if ctl_rec_count(&mut a) != ctl_rec_count(&mut b) { ok = false; }
  var i = 0;
  while i < ctl_rec_count(&mut a) {
    if ctl_rec_tick(&mut a, i) != ctl_rec_tick(&mut b, i) { ok = false; }
    if ctl_rec_action(&mut a, i) != ctl_rec_action(&mut b, i) { ok = false; }
    if ctl_rec_from(&mut a, i) != ctl_rec_from(&mut b, i) { ok = false; }
    if ctl_rec_to(&mut a, i) != ctl_rec_to(&mut b, i) { ok = false; }
    if ctl_rec_reason(&mut a, i) != ctl_rec_reason(&mut b, i) { ok = false; }
    if ctl_rec_detail(&mut a, i) != ctl_rec_detail(&mut b, i) { ok = false; }
    i = i + 1;
  }
  if ctl_series_len(&mut a) != ctl_series_len(&mut b) { ok = false; }
  var j = 0;
  while j < ctl_series_len(&mut a) {
    if ctl_series_at(&mut a, j) != ctl_series_at(&mut b, j) { ok = false; }
    j = j + 1;
  }
  return assert(ok, "identical policies and tick sequences stay deterministic");
}

fn t20() -> TestResult {
  var ok = streq(autoscale_action_text(0), "none");
  if !streq(autoscale_action_text(1), "scale-up") { ok = false; }
  if !streq(autoscale_action_text(2), "scale-down") { ok = false; }
  if !streq(autoscale_action_text(7), "none") { ok = false; }
  if !streq(autoscale_reason_text(1), "scale-up: up threshold breached") { ok = false; }
  if !streq(autoscale_reason_text(2), "scale-down: down threshold breached") { ok = false; }
  if !streq(autoscale_reason_text(3), "hold: metric inside hysteresis band") { ok = false; }
  if !streq(autoscale_reason_text(4), "hold: up breach streak below required") { ok = false; }
  if !streq(autoscale_reason_text(5), "hold: down breach streak below required") { ok = false; }
  if !streq(autoscale_reason_text(6), "hold: up cooldown active") { ok = false; }
  if !streq(autoscale_reason_text(7), "hold: down cooldown active") { ok = false; }
  if !streq(autoscale_reason_text(8), "hold: already at max replicas") { ok = false; }
  if !streq(autoscale_reason_text(9), "hold: already at min replicas") { ok = false; }
  if !streq(autoscale_reason_text(11), "refused: tick counter overflow") { ok = false; }
  if !streq(autoscale_reason_text(404), "unknown reason") { ok = false; }
  return assert(ok, "action and reason catalogs cover every code");
}

fn t21() -> TestResult {
  let p = autoscale_policy_with_series_capacity(policy_fixture_step1("cpu", 1, 5, 8000, 3000), 7);
  var c = autoscale_controller_new(p, 3);
  let q = ctl_policy(&mut c);
  var ok = q.series_capacity == 7;
  if q.up_threshold != 8000 || q.down_threshold != 3000 { ok = false; }
  if !streq(q.metric, "cpu") { ok = false; }
  var e = autoscale_controller_new(policy_fixture("cpu", 1, 5, 5000, -1, 1), 3);
  if autoscale_controller_tick_avg(&mut e, 100, 0) != 0 { ok = false; }
  if ctl_last_reason(&mut e) != 3 { ok = false; }
  if ctl_replicas(&mut e) != 3 { ok = false; }
  return assert(ok, "controller exposes its policy and refuses empty windows");
}

fn main() -> Int {
  io.println("=== xiom.autoscale conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.autoscale: all tests passed");
  } else {
    io.println("xiom.autoscale: tests failed");
  }
  return failed;
}
