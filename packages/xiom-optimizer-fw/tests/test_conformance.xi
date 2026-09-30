// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.optimizer-fw conformance tests (25 checks).
//
// Fixture-driven and fully deterministic: every objective is built from a
// pinned integer sample table, every search uses explicit bounds, seeds and
// stopping records, and every string comparison goes through str_compare
// (trap 1). All dispatch is by direct calls: there are no fn tables, no
// fn-pointer objectives and no indexed Vec[fn] calls (trap 5).
//
// Fixtures: unimodal (peak 1000 at x=3), twin (equal maxima 100 at x=2 and
// x=4), trap (a tempting left improvement 20 versus a better right peak 50),
// linear (10*i on 0..10), well (plateau 100 on [-1,1], valley at +-12, wall,
// global 500 for |x| >= 33) and spiky (local peaks at 7 and 34, global 500 at
// x=23).

module optimizer_fw_tests
use xiom.io; use xiom.test; use xiom.optimizer_fw;
use xiom.string.compare;

// --- helpers ---------------------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn report(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  return 1;
}

fn test_abs(v: Int) -> Int {
  if v < 0 { return 0 - v; }
  return v;
}

fn traces_equal(a: &OptTrace, b: &OptTrace) -> Bool {
  if optfw_trace_len(a) != optfw_trace_len(b) { return false; }
  var i = 0;
  while i < optfw_trace_len(a) {
    if optfw_trace_iter(a, i) != optfw_trace_iter(b, i) { return false; }
    if optfw_trace_best(a, i) != optfw_trace_best(b, i) { return false; }
    if optfw_trace_current(a, i) != optfw_trace_current(b, i) { return false; }
    i = i + 1;
  }
  return true;
}

fn trace_best_nondecreasing(t: &OptTrace) -> Bool {
  var i = 1;
  while i < optfw_trace_len(t) {
    if optfw_trace_best(t, i) < optfw_trace_best(t, i - 1) { return false; }
    i = i + 1;
  }
  return true;
}

// --- fixtures ---------------------------------------------------------------

fn unimodal() -> OptObjective {
  var vals: Vec[Int] = Vec[Int].new();
  vals.push(991);
  vals.push(996);
  vals.push(999);
  vals.push(1000);
  vals.push(999);
  vals.push(996);
  vals.push(991);
  return optfw_table_new(&vals, 0, 1);
}

fn twin() -> OptObjective {
  var vals: Vec[Int] = Vec[Int].new();
  vals.push(96);
  vals.push(99);
  vals.push(100);
  vals.push(99);
  vals.push(100);
  vals.push(99);
  vals.push(96);
  vals.push(93);
  vals.push(90);
  return optfw_table_new(&vals, 0, 1);
}

fn trap() -> OptObjective {
  var vals: Vec[Int] = Vec[Int].new();
  vals.push(5);
  vals.push(20);
  vals.push(4);
  vals.push(4);
  vals.push(10);
  vals.push(4);
  vals.push(4);
  vals.push(50);
  vals.push(4);
  vals.push(4);
  return optfw_table_new(&vals, 0, 1);
}

fn linear() -> OptObjective {
  var vals: Vec[Int] = Vec[Int].new();
  var i = 0;
  while i <= 10 {
    vals.push(i * 10);
    i = i + 1;
  }
  return optfw_table_new(&vals, 0, 1);
}

fn well_value(x: Int) -> Int {
  let ax = test_abs(x);
  if ax <= 1 { return 100; }
  if ax <= 12 { return 50 - 50 * (ax - 2); }
  if ax <= 32 { return 100 + 20 * (ax - 12); }
  return 500;
}

fn well_table() -> OptObjective {
  var vals: Vec[Int] = Vec[Int].new();
  var x = -40;
  while x <= 40 {
    vals.push(well_value(x));
    x = x + 1;
  }
  return optfw_table_new(&vals, -40, 1);
}

fn spiky_value(i: Int) -> Int {
  var best = 100 - test_abs(i - 7);
  let b2 = 500 - test_abs(i - 23);
  let b3 = 200 - test_abs(i - 34);
  if b2 > best { best = b2; }
  if b3 > best { best = b3; }
  return best;
}

fn spiky_table() -> OptObjective {
  var vals: Vec[Int] = Vec[Int].new();
  var i = 0;
  while i <= 40 {
    vals.push(spiky_value(i));
    i = i + 1;
  }
  return optfw_table_new(&vals, 0, 1);
}

// --- objective records ------------------------------------------------------

fn t1() -> TestResult {
  let o = unimodal();
  var ok = optfw_obj_len(&o) == 7;
  if !optfw_obj_is_consistent(&o) { ok = false; }
  if optfw_obj_first(&o) != 0 { ok = false; }
  if optfw_obj_last(&o) != 6 { ok = false; }
  if optfw_obj_x(&o, 2) != 2 { ok = false; }
  if optfw_obj_v(&o, 2) != 999 { ok = false; }
  if optfw_eval(&o, 3) != 1000 { ok = false; }
  if optfw_eval(&o, 6) != 991 { ok = false; }
  if optfw_eval(&o, 0) != 991 { ok = false; }
  return assert(ok, "table objective: geometry, consistency, exact on-grid eval");
}

fn t2() -> TestResult {
  var vals: Vec[Int] = Vec[Int].new();
  vals.push(10);
  vals.push(20);
  vals.push(30);
  let o = optfw_table_new(&vals, 100, 5);
  var ok = optfw_obj_len(&o) == 3;
  if optfw_obj_x(&o, 0) != 100 { ok = false; }
  if optfw_obj_x(&o, 2) != 110 { ok = false; }
  if optfw_eval(&o, 100) != 10 { ok = false; }
  if optfw_eval(&o, 102) != 10 { ok = false; }
  if optfw_eval(&o, 103) != 20 { ok = false; }
  if optfw_eval(&o, 107) != 20 { ok = false; }
  if optfw_eval(&o, 113) != 30 { ok = false; }
  if optfw_eval(&o, 90) != 10 { ok = false; }
  return assert(ok, "sample table: stride geometry and nearest-sample evaluation");
}

fn t3() -> TestResult {
  var xs: Vec[Int] = Vec[Int].new();
  xs.push(0);
  xs.push(10);
  xs.push(25);
  var vs: Vec[Int] = Vec[Int].new();
  vs.push(5);
  vs.push(9);
  vs.push(3);
  let o = optfw_list_new(&xs, &vs);
  var ok = optfw_obj_len(&o) == 3;
  if optfw_eval(&o, 0) != 5 { ok = false; }
  if optfw_eval(&o, 8) != 9 { ok = false; }
  if optfw_eval(&o, 12) != 9 { ok = false; }
  if optfw_eval(&o, 20) != 3 { ok = false; }
  if optfw_eval(&o, 25) != 3 { ok = false; }
  if optfw_eval(&o, 5) != 5 { ok = false; }
  var xs2: Vec[Int] = Vec[Int].new();
  xs2.push(1);
  xs2.push(2);
  xs2.push(3);
  var vs2: Vec[Int] = Vec[Int].new();
  vs2.push(9);
  let o2 = optfw_list_new(&xs2, &vs2);
  var ok2 = optfw_obj_len(&o2) == 1;
  if !optfw_obj_is_consistent(&o2) { ok2 = false; }
  if optfw_eval(&o2, 100) != 9 { ok2 = false; }
  return assert(ok && ok2, "value list: nearest sample, tie keeps the earliest, short side bounds the record");
}

fn t4() -> TestResult {
  var empty: Vec[Int] = Vec[Int].new();
  let o = optfw_list_new(&empty, &empty);
  var ok = optfw_obj_len(&o) == 0;
  if !optfw_obj_is_consistent(&o) { ok = false; }
  if optfw_eval(&o, 7) != OPT_NONE { ok = false; }
  if optfw_obj_v(&o, 0) != OPT_NONE { ok = false; }
  if optfw_obj_x(&o, 0) != 0 { ok = false; }
  if optfw_obj_first(&o) != 0 { ok = false; }
  if optfw_obj_last(&o) != 0 { ok = false; }
  if OPT_NONE >= 0 { ok = false; }
  return assert(ok, "empty objective: no value (OPT_NONE), range-safe accessors");
}

// --- grid search ------------------------------------------------------------

fn t5() -> TestResult {
  let o = unimodal();
  let s = optfw_stop_new(100, 0, OPT_NONE);
  let r = optfw_grid_search(&o, 0, 6, 1, &s);
  var ok = r.x == 3;
  if r.value != 1000 { ok = false; }
  if r.iters != 7 { ok = false; }
  if r.reason != OPT_REASON_EXHAUSTED { ok = false; }
  if !r.improved { ok = false; }
  if optfw_stop_max_iters(&s) != 100 { ok = false; }
  if optfw_stop_no_improve(&s) != 0 { ok = false; }
  if optfw_stop_floor(&s) != OPT_NONE { ok = false; }
  return assert(ok, "grid: exhaustive scan finds the unimodal peak at 3");
}

fn t6() -> TestResult {
  let o = twin();
  let r = optfw_grid_search(&o, 0, 8, 1, &optfw_stop_new(100, 0, OPT_NONE));
  var ok = r.x == 2;
  if r.value != 100 { ok = false; }
  if r.iters != 9 { ok = false; }
  if optfw_eval(&o, 4) != 100 { ok = false; }
  return assert(ok, "grid: ties keep the smallest x (2 of {2, 4})");
}

fn t7() -> TestResult {
  let o = linear();
  let s = optfw_stop_new(100, 0, OPT_NONE);
  let r3 = optfw_grid_search(&o, 0, 10, 3, &s);
  let r1 = optfw_grid_search(&o, 0, 10, 1, &s);
  let r0 = optfw_grid_search(&o, 0, 10, 0, &s);
  let rbig = optfw_grid_search(&o, 0, 10, 20, &s);
  var ok = r3.x == 9;
  if r3.value != 90 { ok = false; }
  if r3.iters != 4 { ok = false; }
  if r1.x != 10 { ok = false; }
  if r1.iters != 11 { ok = false; }
  if r0.x != 10 { ok = false; }
  if r0.iters != 11 { ok = false; }
  if rbig.x != 0 { ok = false; }
  if rbig.iters != 1 { ok = false; }
  return assert(ok, "grid: honours the stride, clamps step < 1 to 1, handles a stride beyond hi");
}

fn t8() -> TestResult {
  let o = unimodal();
  let r = optfw_grid_search(&o, 0, 6, 1, &optfw_stop_new(100, 0, 1000));
  var ok = r.reason == OPT_REASON_FLOOR;
  if r.x != 3 { ok = false; }
  if r.value != 1000 { ok = false; }
  if r.iters != 4 { ok = false; }
  return assert(ok, "grid: the value floor stops the scan at the peak");
}

fn t9() -> TestResult {
  let o = unimodal();
  let r = optfw_grid_search(&o, 0, 6, 1, &optfw_stop_new(2, 0, OPT_NONE));
  var ok = r.reason == OPT_REASON_MAX_ITERS;
  if r.x != 1 { ok = false; }
  if r.value != 996 { ok = false; }
  if r.iters != 2 { ok = false; }
  return assert(ok, "grid: max_iters caps the scan and returns the best so far");
}

fn t10() -> TestResult {
  let o = unimodal();
  var tr = optfw_trace_new();
  let r = optfw_grid_search_trace(&o, 0, 6, 1, &optfw_stop_new(100, 2, OPT_NONE), &mut tr);
  var ok = r.reason == OPT_REASON_NO_IMPROVE;
  if r.x != 3 { ok = false; }
  if r.iters != 6 { ok = false; }
  if optfw_trace_len(&tr) != 6 { ok = false; }
  if !optfw_trace_is_consistent(&tr) { ok = false; }
  if optfw_trace_iter(&tr, 0) != 1 { ok = false; }
  if optfw_trace_iter(&tr, 5) != 6 { ok = false; }
  if optfw_trace_best(&tr, 5) != 1000 { ok = false; }
  if optfw_trace_current(&tr, 5) != 996 { ok = false; }
  return assert(ok, "grid: no-improvement window stops after two flat samples");
}

// --- hill climbing ----------------------------------------------------------

fn t11() -> TestResult {
  let o = trap();
  var tr = optfw_trace_new();
  let r = optfw_hill_first_trace(&o, 4, 0, 9, 3, &optfw_stop_new(64, 0, OPT_NONE), &mut tr);
  var ok = r.x == 1;
  if r.value != 20 { ok = false; }
  if r.iters != 3 { ok = false; }
  if r.reason != OPT_REASON_STEP_ZERO { ok = false; }
  if !r.improved { ok = false; }
  if optfw_trace_len(&tr) != 3 { ok = false; }
  if !optfw_trace_is_consistent(&tr) { ok = false; }
  if optfw_trace_iter(&tr, 0) != 1 { ok = false; }
  if optfw_trace_iter(&tr, 2) != 3 { ok = false; }
  if optfw_trace_current(&tr, 0) != 20 { ok = false; }
  if optfw_trace_best(&tr, 2) != 20 { ok = false; }
  return assert(ok, "hill first: takes the tempting left improvement and stalls there");
}

fn t12() -> TestResult {
  let o = trap();
  let s = optfw_stop_new(64, 0, OPT_NONE);
  let rf = optfw_hill_first(&o, 4, 0, 9, 3, &s);
  let rb = optfw_hill_best(&o, 4, 0, 9, 3, &s);
  var ok = rb.x == 7;
  if rb.value != 50 { ok = false; }
  if rb.iters != 3 { ok = false; }
  if rb.reason != OPT_REASON_STEP_ZERO { ok = false; }
  if rf.x != 1 { ok = false; }
  if rf.value != 20 { ok = false; }
  if rb.value <= rf.value { ok = false; }
  if rb.x == rf.x { ok = false; }
  return assert(ok, "hill best: compares both neighbours and reaches the better peak");
}

fn t13() -> TestResult {
  let o = linear();
  let capped = optfw_hill_first(&o, 0, 0, 10, 3, &optfw_stop_new(2, 0, OPT_NONE));
  let full = optfw_hill_first(&o, 0, 0, 10, 3, &optfw_stop_new(64, 0, OPT_NONE));
  var ok = capped.reason == OPT_REASON_MAX_ITERS;
  if capped.x != 6 { ok = false; }
  if capped.value != 60 { ok = false; }
  if capped.iters != 2 { ok = false; }
  if full.x != 10 { ok = false; }
  if full.value != 100 { ok = false; }
  if full.iters != 6 { ok = false; }
  if full.reason != OPT_REASON_STEP_ZERO { ok = false; }
  return assert(ok, "hill: max_iters bounds the walk; step halving terminates at the top");
}

fn t14() -> TestResult {
  let o = trap();
  let r = optfw_hill_best(&o, 4, 0, 9, 3, &optfw_stop_new(64, 0, 50));
  var ok = r.reason == OPT_REASON_FLOOR;
  if r.x != 7 { ok = false; }
  if r.value != 50 { ok = false; }
  if r.iters != 1 { ok = false; }
  return assert(ok, "hill: the value floor stops as soon as the best reaches 50");
}

fn t15() -> TestResult {
  let o = trap();
  let s2 = optfw_hill_first(&o, 1, 0, 9, 3, &optfw_stop_new(64, 2, OPT_NONE));
  let s1 = optfw_hill_first(&o, 1, 0, 9, 3, &optfw_stop_new(64, 1, OPT_NONE));
  var ok = s2.reason == OPT_REASON_NO_IMPROVE;
  if s2.x != 1 { ok = false; }
  if s2.value != 20 { ok = false; }
  if s2.iters != 2 { ok = false; }
  if s1.reason != OPT_REASON_NO_IMPROVE { ok = false; }
  if s1.iters != 1 { ok = false; }
  return assert(ok, "hill: the no-improvement window counts stalled iterations");
}

fn t16() -> TestResult {
  let o = trap();
  let s = optfw_stop_new(64, 0, OPT_NONE);
  let r = optfw_hill_first(&o, 100, 0, 9, 3, &s);
  let e = optfw_hill_first(&o, 5, 9, 0, 3, &s);
  var ok = r.x == 9;
  if r.value != 4 { ok = false; }
  if r.iters != 2 { ok = false; }
  if r.reason != OPT_REASON_STEP_ZERO { ok = false; }
  if e.reason != OPT_REASON_EMPTY { ok = false; }
  if e.x != 5 { ok = false; }
  if e.iters != 0 { ok = false; }
  return assert(ok, "hill: start clamps into bounds; an empty range is EMPTY");
}

// --- simulated annealing ----------------------------------------------------

fn t17() -> TestResult {
  let o = unimodal();
  let cfg = optfw_anneal_cfg_new(1, 42, 64, 1, 2);
  let s = optfw_stop_new(60, 0, OPT_NONE);
  var t1 = optfw_trace_new();
  var t2 = optfw_trace_new();
  let a = optfw_anneal_trace(&o, 0, 0, 6, &cfg, &s, &mut t1);
  let b = optfw_anneal_trace(&o, 0, 0, 6, &cfg, &s, &mut t2);
  var ok = a.x == b.x;
  if optfw_cfg_step(&cfg) != 1 { ok = false; }
  if optfw_cfg_seed(&cfg) != 42 { ok = false; }
  if optfw_cfg_temp_start(&cfg) != 64 { ok = false; }
  if optfw_cfg_cool_num(&cfg) != 1 { ok = false; }
  if optfw_cfg_cool_den(&cfg) != 2 { ok = false; }
  if a.value != b.value { ok = false; }
  if a.iters != b.iters { ok = false; }
  if a.reason != b.reason { ok = false; }
  if !traces_equal(&t1, &t2) { ok = false; }
  if a.value != 1000 { ok = false; }
  if a.x != 3 { ok = false; }
  if !a.improved { ok = false; }
  return assert(ok, "annealing: same seed, same walk; finds the unimodal peak");
}

fn t18() -> TestResult {
  let o = well_table();
  let cold = optfw_anneal_cfg_new(8, 7, 1, 1, 1);
  let hot = optfw_anneal_cfg_new(8, 2026, 100000, 999, 1000);
  let rc = optfw_anneal(&o, 0, -40, 40, &cold, &optfw_stop_new(120, 0, OPT_NONE));
  let rh = optfw_anneal(&o, 0, -40, 40, &hot, &optfw_stop_new(400, 0, OPT_NONE));
  var ok = rc.value == 100;
  if rc.x < -1 { ok = false; }
  if rc.x > 1 { ok = false; }
  if rc.improved { ok = false; }
  if rh.value != 500 { ok = false; }
  if rh.x < -40 { ok = false; }
  if rh.x > 40 { ok = false; }
  if !rh.improved { ok = false; }
  return assert(ok, "annealing: greedy temp stays on the plateau, hot temp escapes to 500");
}

fn t19() -> TestResult {
  let o = unimodal();
  let cfg = optfw_anneal_cfg_new(1, 42, 8, 1, 2);
  let rf = optfw_anneal(&o, 0, 0, 6, &cfg, &optfw_stop_new(60, 0, 1000));
  let rb = optfw_anneal(&o, 500, 0, 6, &cfg, &optfw_stop_new(20, 0, OPT_NONE));
  var ok = rf.reason == OPT_REASON_FLOOR;
  if rf.x != 3 { ok = false; }
  if rf.value != 1000 { ok = false; }
  if rb.x < 0 { ok = false; }
  if rb.x > 6 { ok = false; }
  if rb.value < 991 { ok = false; }
  if rb.value > 1000 { ok = false; }
  return assert(ok, "annealing: value floor fires; an out-of-range start clamps into bounds");
}

fn t20() -> TestResult {
  var ok = optfw_temp_at(1000, 1, 2, 0) == 1000;
  if optfw_temp_at(1000, 1, 2, 1) != 500 { ok = false; }
  if optfw_temp_at(1000, 1, 2, 9) != 1 { ok = false; }
  if optfw_temp_at(5, 1, 1, 7) != 5 { ok = false; }
  if optfw_temp_at(5, 2, 1, 3) != 5 { ok = false; }
  if optfw_temp_at(0, 1, 2, 4) != 1 { ok = false; }
  if optfw_temp_at(10, 1, 0, 3) != 10 { ok = false; }
  if optfw_temp_next(9, 1, 3) != 3 { ok = false; }
  var prev = optfw_temp_at(100, 999, 1000, 0);
  var i = 1;
  while i <= 40 {
    let t = optfw_temp_at(100, 999, 1000, i);
    if t > prev { ok = false; }
    if t < 1 { ok = false; }
    prev = t;
    i = i + 1;
  }
  return assert(ok, "temperature: fixed-point cooling is monotone, clamps at 1, handles degenerate ratios");
}

fn t21() -> TestResult {
  let o = unimodal();
  var tr = optfw_trace_new();
  let r = optfw_grid_search_trace(&o, 0, 6, 1, &optfw_stop_new(2, 0, OPT_NONE), &mut tr);
  var ok = optfw_trace_len(&tr) == r.iters;
  if !optfw_trace_is_consistent(&tr) { ok = false; }
  if !trace_best_nondecreasing(&tr) { ok = false; }
  if optfw_trace_iter(&tr, 0) != 1 { ok = false; }
  if optfw_trace_iter(&tr, 1) != 2 { ok = false; }
  if optfw_trace_best(&tr, 0) != 991 { ok = false; }
  if optfw_trace_best(&tr, 1) != 996 { ok = false; }
  if optfw_trace_current(&tr, 1) != 996 { ok = false; }
  if optfw_trace_iter(&tr, -1) != 0 { ok = false; }
  if optfw_trace_best(&tr, 99) != OPT_NONE { ok = false; }
  if optfw_trace_current(&tr, 99) != OPT_NONE { ok = false; }
  return assert(ok, "trace: rows align with iterations; best-so-far is non-decreasing; accessors are bounded");
}

fn t22() -> TestResult {
  let o = unimodal();
  var tr = optfw_trace_new();
  let cfg = optfw_anneal_cfg_new(1, 42, 8, 1, 2);
  let r = optfw_anneal_trace(&o, 0, 0, 6, &cfg, &optfw_stop_new(30, 0, OPT_NONE), &mut tr);
  var ok = optfw_trace_len(&tr) == r.iters;
  if !optfw_trace_is_consistent(&tr) { ok = false; }
  if !trace_best_nondecreasing(&tr) { ok = false; }
  if r.value != 1000 { ok = false; }
  if !r.improved { ok = false; }
  if r.iters < 4 { ok = false; }
  return assert(ok, "trace: annealing convergence rows are consistent and best-so-far monotone");
}

// --- random restarts --------------------------------------------------------

fn t23() -> TestResult {
  let o = spiky_table();
  let s = optfw_stop_new(100, 0, OPT_NONE);
  var tr = optfw_trace_new();
  let a = optfw_restart_search_trace(&o, 0, 40, 12, 4, 2026, &s, &mut tr);
  let b = optfw_restart_search(&o, 0, 40, 12, 4, 2026, &s);
  var ok = a.x == b.x;
  if a.value != b.value { ok = false; }
  if a.value != 500 { ok = false; }
  if a.x != 23 { ok = false; }
  if a.iters != 12 { ok = false; }
  if a.reason != OPT_REASON_EXHAUSTED { ok = false; }
  if !a.improved { ok = false; }
  if optfw_trace_len(&tr) != 12 { ok = false; }
  if !trace_best_nondecreasing(&tr) { ok = false; }
  if optfw_trace_best(&tr, 11) != 500 { ok = false; }
  return assert(ok, "restarts: deterministic multi-start finds the global 500 at 23");
}

fn t24() -> TestResult {
  let o = spiky_table();
  let rf = optfw_restart_search(&o, 0, 40, 12, 4, 2026, &optfw_stop_new(100, 0, 500));
  let r0 = optfw_restart_search(&o, 0, 40, 0, 4, 2026, &optfw_stop_new(100, 0, OPT_NONE));
  let re = optfw_restart_search(&o, 10, 0, 5, 4, 2026, &optfw_stop_new(100, 0, OPT_NONE));
  var ok = rf.reason == OPT_REASON_FLOOR;
  if rf.value != 500 { ok = false; }
  if rf.iters < 1 { ok = false; }
  if rf.iters > 12 { ok = false; }
  if r0.x != 0 { ok = false; }
  if r0.value != 477 { ok = false; }
  if r0.iters != 0 { ok = false; }
  if re.x != 10 { ok = false; }
  if re.value != spiky_value(10) { ok = false; }
  if re.reason != OPT_REASON_EMPTY { ok = false; }
  return assert(ok, "restarts: floor stops early; zero restarts and an empty range return the seeded lo");
}

// --- stopping records, names, empty objectives ------------------------------

fn t25() -> TestResult {
  let s0 = optfw_stop_new(0, -3, OPT_NONE);
  var ok = optfw_stop_max_iters(&s0) == 1;
  if optfw_stop_no_improve(&s0) != -3 { ok = false; }
  if optfw_stop_floor(&s0) != OPT_NONE { ok = false; }
  if !streq(optfw_reason_name(OPT_REASON_MAX_ITERS), "max-iters") { ok = false; }
  if !streq(optfw_reason_name(OPT_REASON_NO_IMPROVE), "no-improve") { ok = false; }
  if !streq(optfw_reason_name(OPT_REASON_FLOOR), "floor") { ok = false; }
  if !streq(optfw_reason_name(OPT_REASON_EXHAUSTED), "exhausted") { ok = false; }
  if !streq(optfw_reason_name(OPT_REASON_STEP_ZERO), "step-zero") { ok = false; }
  if !streq(optfw_reason_name(OPT_REASON_EMPTY), "empty") { ok = false; }
  if !streq(optfw_reason_name(OPT_REASON_NONE), "none") { ok = false; }
  if !streq(optfw_reason_name(999), "none") { ok = false; }
  var empty: Vec[Int] = Vec[Int].new();
  let eo = optfw_list_new(&empty, &empty);
  let gr = optfw_grid_search(&eo, 3, 9, 1, &s0);
  if gr.reason != OPT_REASON_EMPTY { ok = false; }
  if gr.value != OPT_NONE { ok = false; }
  if gr.x != 3 { ok = false; }
  if gr.iters != 0 { ok = false; }
  let hr = optfw_hill_first(&eo, 5, 0, 9, 1, &s0);
  if hr.x != 5 { ok = false; }
  if hr.value != OPT_NONE { ok = false; }
  if hr.reason != OPT_REASON_EMPTY { ok = false; }
  if optfw_result_x(&hr) != 5 { ok = false; }
  if optfw_result_value(&hr) != OPT_NONE { ok = false; }
  if optfw_result_iters(&hr) != 0 { ok = false; }
  if optfw_result_reason(&hr) != OPT_REASON_EMPTY { ok = false; }
  if optfw_result_improved(&hr) { ok = false; }
  return assert(ok, "stop record clamps, reason names, and empty-objective searches");
}

// --- runner -----------------------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.optimizer-fw conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.optimizer-fw: all tests passed");
  } else {
    io.println("xiom.optimizer-fw: tests failed");
  }
  return failed;
}
