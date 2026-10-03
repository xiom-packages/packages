// XIOM -- xiom.oracle conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM xiom.oracle model against the
// documented fixed-point aggregation, freshness, quorum and deviation rules
// in SPEC.md.
//
// Coverage: round construction and validation, observation recording and
// duplicate/range errors, quorum, age/staleness boundaries, plain and
// weighted medians (including even-count ties and the overflow guard),
// deviation filtering, the full aggregate pipeline and reset. All expected
// values are hand-computed integers; Str comparisons go through str_compare.

module oracle_tests
use xiom.io; use xiom.test; use xiom.oracle;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when an int result fails with exactly `want`.
fn err_is(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when an int result succeeds with exactly `want`.
fn ok_is(r: Result[Int, Str], want: Int) -> Bool {
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

// True when a round result fails with exactly `want`.
fn round_err_is(r: Result[OracleRound, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// A valid round, or an empty stand-in when construction fails.
fn round_ok(feed: Str, min_sources: Int, max_age: Int, deviation: Int) -> OracleRound {
  let r = oracle_round_new(feed, min_sources, max_age, deviation);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return OracleRound{
    feed: "";
    min_sources: 0;
    max_age_ticks: 0;
    max_deviation_bps: 0;
    sources: Vec[Str].new();
    prices: Vec[Int].new();
    ticks: Vec[Int].new();
    weights: Vec[Int].new();
  };
}

// Record one observation, ignoring the result (tests assert separately).
fn feed_obs(r: &mut OracleRound, source: Str, price: Int, tick: Int, weight: Int) {
  let x = oracle_observe(r, source, price, tick, weight);
  match x {
    Ok(_) => {},
    Err(_) => {},
  }
}

fn t1() -> TestResult {
  let r = oracle_round_new("ETH/USD", 3, 10, 500);
  var ok = false;
  match r {
    Ok(v) => {
      ok = streq(oracle_feed(&v), "ETH/USD");
      if oracle_min_sources(&v) != 3 { ok = false; }
      if oracle_max_age_ticks(&v) != 10 { ok = false; }
      if oracle_max_deviation_bps(&v) != 500 { ok = false; }
      if oracle_observation_count(&v) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a round carries its feed, quorum, age and deviation config");
}

fn t2() -> TestResult {
  var ok = round_err_is(oracle_round_new("", 1, 0, 0), "oracle: empty feed");
  if !round_err_is(oracle_round_new("x", 0, 0, 0), "oracle: bad min sources 0") { ok = false; }
  if !round_err_is(oracle_round_new("x", 1, -1, 0), "oracle: bad max age -1") { ok = false; }
  if !round_err_is(oracle_round_new("x", 1, 0, 10001), "oracle: bad deviation 10001") { ok = false; }
  let edge = oracle_round_new("x", 1, 0, 10000);
  match edge {
    Ok(_) => {},
    Err(_) => { ok = false; },
  }
  return assert(ok, "round validation rejects bad configuration");
}

fn t3() -> TestResult {
  var r = round_ok("x", 1, 0, 0);
  var ok = ok_is(oracle_observe(&mut r, "alpha", 100, 5, 2), 1);
  if !ok_is(oracle_observe(&mut r, "beta", 104, 7, 1), 2) { ok = false; }
  if oracle_observation_count(&r) != 2 { ok = false; }
  if !streq(oracle_source(&r, 0), "alpha") { ok = false; }
  if oracle_price(&r, 0) != 100 { ok = false; }
  if oracle_tick(&r, 1) != 7 { ok = false; }
  if oracle_weight(&r, 1) != 1 { ok = false; }
  return assert(ok, "observations are recorded in arrival order");
}

fn t4() -> TestResult {
  var r = round_ok("x", 1, 0, 0);
  var ok = err_is(oracle_observe(&mut r, "", 100, 0, 1), "oracle: empty source");
  if !err_is(oracle_observe(&mut r, "a", 0, 0, 1), "oracle: bad price 0") { ok = false; }
  if !err_is(oracle_observe(&mut r, "a", 1000000000001, 0, 1), "oracle: bad price 1000000000001") { ok = false; }
  if !err_is(oracle_observe(&mut r, "a", 100, -1, 1), "oracle: bad tick -1") { ok = false; }
  if !err_is(oracle_observe(&mut r, "a", 100, 0, 0), "oracle: bad weight 0") { ok = false; }
  if !err_is(oracle_observe(&mut r, "a", 100, 0, 1000001), "oracle: bad weight 1000001") { ok = false; }
  if oracle_observation_count(&r) != 0 { ok = false; }
  feed_obs(&mut r, "a", 100, 0, 1);
  if !err_is(oracle_observe(&mut r, "a", 100, 0, 1), "oracle: duplicate source 'a'") { ok = false; }
  if oracle_observation_count(&r) != 1 { ok = false; }
  return assert(ok, "observation validation rejects bad input without mutating");
}

fn t5() -> TestResult {
  var r = round_ok("x", 2, 100, 0);
  var ok = !oracle_quorum_met(&r);
  feed_obs(&mut r, "a", 100, 0, 1);
  if oracle_quorum_met(&r) { ok = false; }
  feed_obs(&mut r, "b", 100, 0, 1);
  if !oracle_quorum_met(&r) { ok = false; }
  return assert(ok, "quorum needs exactly min_sources observations");
}

fn t6() -> TestResult {
  var r = round_ok("x", 1, 5, 0);
  var ok = oracle_latest_tick(&r) == -1;
  if oracle_age_ticks(&r, 99) != -1 { ok = false; }
  if !oracle_is_stale(&r, 99) { ok = false; }
  feed_obs(&mut r, "a", 100, 10, 1);
  if oracle_latest_tick(&r) != 10 { ok = false; }
  if oracle_is_stale(&r, 15) { ok = false; }
  if !oracle_is_stale(&r, 16) { ok = false; }
  if oracle_is_stale(&r, 5) { ok = false; }
  return assert(ok, "freshness is age <= max_age_ticks with a negative-age allowance");
}

fn t7() -> TestResult {
  var r = round_ok("x", 1, 0, 0);
  feed_obs(&mut r, "a", 10, 0, 1);
  feed_obs(&mut r, "b", 20, 0, 1);
  feed_obs(&mut r, "c", 30, 0, 1);
  var ok = ok_is(oracle_weighted_median(&r), 20);
  if !ok_is(oracle_median(&r), 20) { ok = false; }
  return assert(ok, "an odd count medians to the middle price");
}

fn t8() -> TestResult {
  var r = round_ok("x", 1, 0, 0);
  feed_obs(&mut r, "a", 10, 0, 1);
  feed_obs(&mut r, "b", 20, 0, 1);
  feed_obs(&mut r, "c", 30, 0, 1);
  feed_obs(&mut r, "d", 40, 0, 1);
  var ok = ok_is(oracle_weighted_median(&r), 20);
  if !ok_is(oracle_median(&r), 25) { ok = false; }
  return assert(ok, "even counts pin the tie rule and the floored average");
}

fn t9() -> TestResult {
  var r = round_ok("x", 1, 0, 0);
  feed_obs(&mut r, "a", 10, 0, 1);
  feed_obs(&mut r, "b", 20, 0, 3);
  feed_obs(&mut r, "c", 30, 0, 1);
  var ok = ok_is(oracle_weighted_median(&r), 20);
  if !ok_is(oracle_median(&r), 20) { ok = false; }
  return assert(ok, "weights pull the weighted median without moving the plain median");
}

fn t10() -> TestResult {
  var r = round_ok("x", 1, 0, 0);
  r.sources.push("a");
  r.prices.push(1);
  r.ticks.push(0);
  r.weights.push(600000000000);
  r.sources.push("b");
  r.prices.push(2);
  r.ticks.push(0);
  r.weights.push(600000000000);
  var ok = err_is(oracle_weighted_median(&r), "oracle: weight overflow");
  var empty = round_ok("x", 1, 0, 0);
  if !err_is(oracle_weighted_median(&empty), "oracle: no observations") { ok = false; }
  if !err_is(oracle_median(&empty), "oracle: no observations") { ok = false; }
  return assert(ok, "huge total weights are rejected and empty rounds error");
}

fn t11() -> TestResult {
  var one = round_ok("x", 1, 0, 0);
  feed_obs(&mut one, "a", 7, 0, 1);
  var ok = ok_is(oracle_median(&one), 7);
  var two = round_ok("x", 1, 0, 0);
  feed_obs(&mut two, "a", 10, 0, 1);
  feed_obs(&mut two, "b", 11, 0, 1);
  if !ok_is(oracle_median(&two), 10) { ok = false; }
  return assert(ok, "single and even two-price medians floor correctly");
}

fn t12() -> TestResult {
  var r = round_ok("x", 1, 100, 500);
  feed_obs(&mut r, "a", 100, 0, 1);
  feed_obs(&mut r, "b", 104, 0, 1);
  feed_obs(&mut r, "c", 500, 0, 1);
  var ok = ok_is(oracle_deviation_rejects(&r), 1);
  return assert(ok, "deviation filtering counts outliers beyond the basis points");
}

fn t13() -> TestResult {
  var r = round_ok("x", 1, 100, 400);
  feed_obs(&mut r, "a", 100, 0, 1);
  feed_obs(&mut r, "b", 104, 0, 1);
  var ok = ok_is(oracle_deviation_rejects(&r), 0);
  return assert(ok, "a deviation exactly at the threshold is accepted");
}

fn t14() -> TestResult {
  var r = round_ok("ETH/USD", 2, 10, 500);
  feed_obs(&mut r, "a", 100, 0, 1);
  feed_obs(&mut r, "b", 104, 0, 1);
  feed_obs(&mut r, "c", 500, 0, 1);
  var ok = ok_is(oracle_aggregate(&r, 5), 100);
  var stale = oracle_aggregate(&r, 11);
  if !err_is(stale, "oracle: stale feed") { ok = false; }
  if !ok_is(oracle_aggregate(&r, 10), 100) { ok = false; }
  return assert(ok, "the aggregate pipeline filters outliers and enforces freshness");
}

fn t15() -> TestResult {
  var r = round_ok("x", 3, 10, 0);
  feed_obs(&mut r, "a", 100, 0, 1);
  feed_obs(&mut r, "b", 104, 0, 1);
  var ok = err_is(oracle_aggregate(&r, 0), "oracle: quorum not met");
  var empty = round_ok("x", 3, 10, 0);
  if !err_is(oracle_aggregate(&empty, 0), "oracle: no observations") { ok = false; }
  return assert(ok, "aggregation requires a quorum and at least one observation");
}

fn t16() -> TestResult {
  var r = round_ok("x", 2, 10, 100);
  feed_obs(&mut r, "a", 100, 0, 1);
  feed_obs(&mut r, "b", 200, 0, 1);
  feed_obs(&mut r, "c", 300, 0, 1);
  var ok = err_is(oracle_aggregate(&r, 0), "oracle: quorum lost after deviation filter");
  return assert(ok, "a filter that breaks the quorum fails the aggregate");
}

fn t17() -> TestResult {
  var r = round_ok("x", 2, 10, 500);
  feed_obs(&mut r, "a", 100, 0, 1);
  feed_obs(&mut r, "b", 104, 0, 3);
  feed_obs(&mut r, "c", 500, 0, 1);
  var ok = ok_is(oracle_aggregate(&r, 0), 104);
  if !ok_is(oracle_weighted_median(&r), 104) { ok = false; }
  return assert(ok, "the filtered weighted median uses the surviving weights");
}

fn t18() -> TestResult {
  var r = round_ok("x", 2, 5, 500);
  feed_obs(&mut r, "a", 100, 0, 1);
  feed_obs(&mut r, "b", 100, 0, 1);
  var ok = !oracle_is_stale(&r, 5);
  feed_obs(&mut r, "c", 100, 2, 1);
  if oracle_age_ticks(&r, 5) != 3 { ok = false; }
  if oracle_is_stale(&r, 7) { ok = false; }
  if !oracle_is_stale(&r, 8) { ok = false; }
  return assert(ok, "age uses the newest observation only");
}

fn t19() -> TestResult {
  var r = round_ok("x", 1, 0, 0);
  feed_obs(&mut r, "Binance", 100, 0, 1);
  feed_obs(&mut r, "binance", 104, 0, 1);
  var ok = oracle_observation_count(&r) == 2;
  feed_obs(&mut r, "cap", 1000000000000, 0, 1000000);
  if oracle_price(&r, 2) != 1000000000000 { ok = false; }
  if oracle_weight(&r, 2) != 1000000 { ok = false; }
  return assert(ok, "source ids are case-sensitive and range limits are inclusive");
}

fn t20() -> TestResult {
  var r = round_ok("x", 2, 5, 500);
  feed_obs(&mut r, "a", 100, 0, 1);
  feed_obs(&mut r, "b", 100, 0, 1);
  oracle_reset(&mut r);
  var ok = oracle_observation_count(&r) == 0;
  if oracle_quorum_met(&r) { ok = false; }
  if !streq(oracle_feed(&r), "x") { ok = false; }
  if oracle_min_sources(&r) != 2 { ok = false; }
  if !err_is(oracle_aggregate(&r, 0), "oracle: no observations") { ok = false; }
  return assert(ok, "reset clears observations and keeps the configuration");
}

fn t21() -> TestResult {
  var r = round_ok("x", 1, 0, 0);
  feed_obs(&mut r, "a", 100, 4, 2);
  var ok = streq(oracle_source(&r, -1), "");
  if !streq(oracle_source(&r, 9), "") { ok = false; }
  if oracle_price(&r, 9) != -1 { ok = false; }
  if oracle_tick(&r, -1) != -1 { ok = false; }
  if oracle_weight(&r, 9) != -1 { ok = false; }
  if oracle_latest_tick(&r) != 4 { ok = false; }
  return assert(ok, "observation accessors are bounds-safe");
}

fn t22() -> TestResult {
  var r = round_ok("x", 1, 0, 0);
  var ok = ok_is(oracle_observe(&mut r, "a", 10, 0, 1), 1);
  if oracle_observation_count(&r) != 1 { ok = false; }
  if !err_is(oracle_observe(&mut r, "a", 10, 0, 1), "oracle: duplicate source 'a'") { ok = false; }
  if !ok_is(oracle_observe(&mut r, "b", 10, 0, 1), 2) { ok = false; }
  return assert(ok, "a successful observe advances the count exactly once");
}

fn main() -> Int {
  io.println("=== xiom.oracle conformance tests ===");
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
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.oracle: all tests passed");
  } else {
    io.println("xiom.oracle: tests failed");
  }
  return failed;
}
