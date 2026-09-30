// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.stats-tests conformance tests (25 checks)
// Port task: prove the pure-XIOM xiom.stats-tests module against its
// documented fixed-point contract (scaled integers only, no floats, no FFI,
// no I/O in the library). All Str equality goes through str_compare
// (BUG 17 lowers `==` on Str values read from Vec elements to a pointer
// comparison); every Vec element read binds a typed local first.

module stats_tests_conformance
use xiom.io; use xiom.test; use xiom.stats_tests;
use xiom.string; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

fn empty_ints() -> Vec[Int] {
  return Vec[Int].new();
}

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

fn v4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn v5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

fn v6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

// ---------------------------------------------------------------------------
// Result extractors with graceful fallbacks: a construction failure makes
// the value checks fail instead of aborting the whole suite.
// ---------------------------------------------------------------------------

fn ints_of(r: Result[Vec[Int], Str]) -> Vec[Int] {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_ints(); },
  }
  return empty_ints();
}

fn wilcoxon_of(r: Result[WilcoxonResult, Str]) -> WilcoxonResult {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return WilcoxonResult{ u_a: -1; u_b: -1; rank_sum_a: -1; rank_sum_b: -1; n_a: -1; n_b: -1; p_bucket: -1; }; },
  }
  return WilcoxonResult{ u_a: -1; u_b: -1; rank_sum_a: -1; rank_sum_b: -1; n_a: -1; n_b: -1; p_bucket: -1; };
}

fn chi2_of(r: Result[ChiSquareResult, Str]) -> ChiSquareResult {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return ChiSquareResult{ num: -1; den: -1; scaled: -1; df: -1; p_bucket: -1; }; },
  }
  return ChiSquareResult{ num: -1; den: -1; scaled: -1; df: -1; p_bucket: -1; };
}

fn sign_of(r: Result[SignTestResult, Str]) -> SignTestResult {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return SignTestResult{ n_plus: -1; n_minus: -1; n_zero: -1; stat: -1; p_bucket: -1; }; },
  }
  return SignTestResult{ n_plus: -1; n_minus: -1; n_zero: -1; stat: -1; p_bucket: -1; };
}

fn perm_of(r: Result[PermutationResult, Str]) -> PermutationResult {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return PermutationResult{ observed_diff: 0; extreme: -1; n_perm: -1; p_bucket: -1; }; },
  }
  return PermutationResult{ observed_diff: 0; extreme: -1; n_perm: -1; p_bucket: -1; };
}

// ---------------------------------------------------------------------------
// Error-message predicates
// ---------------------------------------------------------------------------

fn ints_err(r: Result[Vec[Int], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn wilcoxon_err(r: Result[WilcoxonResult, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn chi2_err(r: Result[ChiSquareResult, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn sign_err(r: Result[SignTestResult, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn perm_err(r: Result[PermutationResult, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Vector predicates
// ---------------------------------------------------------------------------

fn ints_equal(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = stats_tests_scale() == 10000;
  if stats_tests_lcg_multiplier() != 48271 { ok = false; }
  if stats_tests_lcg_modulus() != 2147483647 { ok = false; }
  if stats_tests_p_bucket_not_significant() != 0 { ok = false; }
  if stats_tests_p_bucket_05() != 1 { ok = false; }
  if stats_tests_p_bucket_01() != 2 { ok = false; }
  if stats_tests_p_bucket_001() != 3 { ok = false; }
  if stats_tests_p_bucket_unknown() != -1 { ok = false; }
  if stats_tests_is_significant(0) { ok = false; }
  if !stats_tests_is_significant(1) { ok = false; }
  if stats_tests_lcg_step(0) != 48271 { ok = false; }
  if stats_tests_lcg_step(1) != 96542 { ok = false; }
  if stats_tests_lcg_step(-1) != 96542 { ok = false; }
  return assert(ok, "scale, bucket codes and MINSTD LCG constants");
}

fn t2() -> TestResult {
  let r = ints_of(stats_tests_ranks(&v4(10, 20, 30, 40)));
  var ok = ints_equal(&r, &v4(10000, 20000, 30000, 40000));
  let empty = empty_ints();
  let re = ints_of(stats_tests_ranks(&empty));
  if re.len() != 0 { ok = false; }
  let one = ints_of(stats_tests_ranks(&v1(7)));
  if one.len() != 1 { ok = false; }
  if one.len() == 1 {
    let o0: Int = one[0];
    if o0 != 10000 { ok = false; }
  }
  return assert(ok, "ranks: distinct values, empty input and a singleton");
}

fn t3() -> TestResult {
  let tied = ints_of(stats_tests_ranks(&v4(10, 20, 20, 30)));
  var ok = ints_equal(&tied, &v4(10000, 25000, 25000, 40000));
  let all = ints_of(stats_tests_ranks(&v3(5, 5, 5)));
  if !ints_equal(&all, &v3(20000, 20000, 20000)) { ok = false; }
  let unsorted = ints_of(stats_tests_ranks(&v4(40, 10, 30, 20)));
  if !ints_equal(&unsorted, &v4(40000, 10000, 30000, 20000)) { ok = false; }
  return assert(ok, "ranks: average ties and input-order output");
}

fn t4() -> TestResult {
  let neg = ints_of(stats_tests_ranks(&v3(-10, 0, 10)));
  var ok = ints_equal(&neg, &v3(10000, 20000, 30000));
  let pairs = ints_of(stats_tests_ranks(&v4(1, 1, 2, 2)));
  if !ints_equal(&pairs, &v4(15000, 15000, 35000, 35000)) { ok = false; }
  return assert(ok, "ranks: negative values and two tied pairs");
}

fn t5() -> TestResult {
  let r = wilcoxon_of(stats_tests_wilcoxon_u(&v2(1, 3), &v2(2, 4)));
  var ok = stats_tests_wilcoxon_n_a(&r) == 2;
  if stats_tests_wilcoxon_n_b(&r) != 2 { ok = false; }
  if stats_tests_wilcoxon_rank_sum_a(&r) != 40000 { ok = false; }
  if stats_tests_wilcoxon_rank_sum_b(&r) != 60000 { ok = false; }
  if stats_tests_wilcoxon_u_a(&r) != 10000 { ok = false; }
  if stats_tests_wilcoxon_u_b(&r) != 30000 { ok = false; }
  if stats_tests_wilcoxon_p_bucket_of(&r) != 0 { ok = false; }
  let ua: Int = stats_tests_wilcoxon_u_a(&r);
  let ub: Int = stats_tests_wilcoxon_u_b(&r);
  if ua + ub != 40000 { ok = false; }
  return assert(ok, "wilcoxon: known 2x2 example and the U identity");
}

fn t6() -> TestResult {
  let r = wilcoxon_of(stats_tests_wilcoxon_u(&v3(1, 1, 2), &v3(3, 4, 5)));
  var ok = stats_tests_wilcoxon_rank_sum_a(&r) == 60000;
  if stats_tests_wilcoxon_rank_sum_b(&r) != 150000 { ok = false; }
  if stats_tests_wilcoxon_u_a(&r) != 0 { ok = false; }
  if stats_tests_wilcoxon_u_b(&r) != 90000 { ok = false; }
  if stats_tests_wilcoxon_p_bucket_of(&r) != 0 { ok = false; }
  let ua: Int = stats_tests_wilcoxon_u_a(&r);
  let ub: Int = stats_tests_wilcoxon_u_b(&r);
  if ua + ub != 90000 { ok = false; }
  return assert(ok, "wilcoxon: average-tie ranks keep the U identity");
}

fn t7() -> TestResult {
  let r = wilcoxon_of(stats_tests_wilcoxon_u(&v4(1, 2, 3, 4), &v4(5, 6, 7, 8)));
  var ok = stats_tests_wilcoxon_u_a(&r) == 0;
  if stats_tests_wilcoxon_u_b(&r) != 160000 { ok = false; }
  if stats_tests_wilcoxon_p_bucket_of(&r) != 1 { ok = false; }
  let rev = wilcoxon_of(stats_tests_wilcoxon_u(&v4(5, 6, 7, 8), &v4(1, 2, 3, 4)));
  if stats_tests_wilcoxon_u_a(&rev) != 160000 { ok = false; }
  if stats_tests_wilcoxon_u_b(&rev) != 0 { ok = false; }
  if stats_tests_wilcoxon_p_bucket_of(&rev) != 1 { ok = false; }
  return assert(ok, "wilcoxon: separated samples are significant both ways");
}

fn t8() -> TestResult {
  var ok = stats_tests_wilcoxon_p_bucket(0, 4, 4) == 1;
  if stats_tests_wilcoxon_p_bucket(0, 4, 5) != 1 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(1, 4, 5) != 1 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(2, 4, 5) != 0 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(13, 8, 8) != 1 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(7, 8, 8) != 2 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(3, 8, 8) != 2 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(2, 8, 8) != 3 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(0, 2, 8) != 1 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(0, 3, 5) != 1 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(1, 3, 5) != 0 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(0, 5, 3) != 1 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(90000, 3, 3) != 0 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(90001, 3, 3) != -1 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(-1, 3, 3) != -1 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(0, 9, 9) != -1 { ok = false; }
  if stats_tests_wilcoxon_p_bucket(0, 1, 5) != -1 { ok = false; }
  return assert(ok, "wilcoxon: bucket boundaries, symmetry and range guards");
}

fn t9() -> TestResult {
  let empty = empty_ints();
  var ok = wilcoxon_err(stats_tests_wilcoxon_u(&empty, &v2(1, 2)), "stats-tests: group A must not be empty");
  if !wilcoxon_err(stats_tests_wilcoxon_u(&v2(1, 2), &empty), "stats-tests: group B must not be empty") { ok = false; }
  return assert(ok, "wilcoxon: empty groups are rejected");
}

fn t10() -> TestResult {
  let r = chi2_of(stats_tests_chi_square_gof(&v3(10, 20, 30), &v3(20, 20, 20)));
  var ok = stats_tests_chi_square_num(&r) == 10;
  if stats_tests_chi_square_den(&r) != 1 { ok = false; }
  if stats_tests_chi_square_scaled(&r) != 100000 { ok = false; }
  if stats_tests_chi_square_df(&r) != 2 { ok = false; }
  if stats_tests_chi_square_p_bucket_of(&r) != 2 { ok = false; }
  return assert(ok, "gof: exact 10.0 against equal expectations, df 2");
}

fn t11() -> TestResult {
  let r = chi2_of(stats_tests_chi_square_gof(&v2(50, 50), &v2(50, 50)));
  var ok = stats_tests_chi_square_num(&r) == 0;
  if stats_tests_chi_square_den(&r) != 1 { ok = false; }
  if stats_tests_chi_square_scaled(&r) != 0 { ok = false; }
  if stats_tests_chi_square_df(&r) != 1 { ok = false; }
  if stats_tests_chi_square_p_bucket_of(&r) != 0 { ok = false; }
  return assert(ok, "gof: a perfect fit is exactly zero");
}

fn t12() -> TestResult {
  var ok = chi2_err(stats_tests_chi_square_gof(&v2(1, 2), &v3(1, 1, 1)), "stats-tests: observed and expected lengths differ");
  if !chi2_err(stats_tests_chi_square_gof(&v1(1), &v1(1)), "stats-tests: need at least two categories") { ok = false; }
  if !chi2_err(stats_tests_chi_square_gof(&v2(1, 2), &v2(1, 0)), "stats-tests: expected counts must be positive") { ok = false; }
  if !chi2_err(stats_tests_chi_square_gof(&v2(1, -2), &v2(1, 2)), "stats-tests: observed counts must not be negative") { ok = false; }
  return assert(ok, "gof: length, category, expectation and sign validation");
}

fn t13() -> TestResult {
  var ok = chi2_err(stats_tests_chi_square_gof(&v2(1, 1), &v2(9223372036854775807, 2)), "stats-tests: expected-count lcm overflows");
  if !chi2_err(stats_tests_chi_square_gof(&v2(9223372036854775807, 0), &v2(1, 1)), "stats-tests: chi-square term overflows") { ok = false; }
  if !chi2_err(stats_tests_chi_square_gof(&v2(3037000499, 3037000499), &v2(1, 1)), "stats-tests: chi-square sum overflows") { ok = false; }
  return assert(ok, "gof: exact-accumulation overflow guards");
}

fn t14() -> TestResult {
  var ok = stats_tests_chi_square_p_bucket(38414, 1) == 0;
  if stats_tests_chi_square_p_bucket(38415, 1) != 1 { ok = false; }
  if stats_tests_chi_square_p_bucket(66348, 1) != 1 { ok = false; }
  if stats_tests_chi_square_p_bucket(66349, 1) != 2 { ok = false; }
  if stats_tests_chi_square_p_bucket(108275, 1) != 2 { ok = false; }
  if stats_tests_chi_square_p_bucket(108276, 1) != 3 { ok = false; }
  if stats_tests_chi_square_p_bucket(59914, 2) != 0 { ok = false; }
  if stats_tests_chi_square_p_bucket(59915, 2) != 1 { ok = false; }
  if stats_tests_chi_square_p_bucket(92102, 2) != 1 { ok = false; }
  if stats_tests_chi_square_p_bucket(92103, 2) != 2 { ok = false; }
  if stats_tests_chi_square_p_bucket(138154, 2) != 2 { ok = false; }
  if stats_tests_chi_square_p_bucket(138155, 2) != 3 { ok = false; }
  if stats_tests_chi_square_p_bucket(0, 0) != -1 { ok = false; }
  if stats_tests_chi_square_p_bucket(100, 11) != -1 { ok = false; }
  if stats_tests_chi_square_p_bucket(-1, 1) != -1 { ok = false; }
  return assert(ok, "chi-square: critical-value boundaries for df 1 and 2");
}

fn t15() -> TestResult {
  let r = chi2_of(stats_tests_chi_square_independence(&v4(10, 20, 30, 40), 2, 2));
  var ok = stats_tests_chi_square_num(&r) == 50;
  if stats_tests_chi_square_den(&r) != 63 { ok = false; }
  if stats_tests_chi_square_scaled(&r) != 7937 { ok = false; }
  if stats_tests_chi_square_df(&r) != 1 { ok = false; }
  if stats_tests_chi_square_p_bucket_of(&r) != 0 { ok = false; }
  return assert(ok, "independence: exact 50/63 on a 2x2 table");
}

fn t16() -> TestResult {
  let r = chi2_of(stats_tests_chi_square_independence(&v6(10, 20, 30, 20, 10, 30), 2, 3));
  var ok = stats_tests_chi_square_num(&r) == 20;
  if stats_tests_chi_square_den(&r) != 3 { ok = false; }
  if stats_tests_chi_square_scaled(&r) != 66667 { ok = false; }
  if stats_tests_chi_square_df(&r) != 2 { ok = false; }
  if stats_tests_chi_square_p_bucket_of(&r) != 1 { ok = false; }
  return assert(ok, "independence: exact 20/3 on a 2x3 table, df 2");
}

fn t17() -> TestResult {
  let r = chi2_of(stats_tests_chi_square_independence(&v4(5, 5, 5, 5), 2, 2));
  var ok = stats_tests_chi_square_num(&r) == 0;
  if stats_tests_chi_square_den(&r) != 1 { ok = false; }
  if stats_tests_chi_square_scaled(&r) != 0 { ok = false; }
  if stats_tests_chi_square_df(&r) != 1 { ok = false; }
  if stats_tests_chi_square_p_bucket_of(&r) != 0 { ok = false; }
  return assert(ok, "independence: a proportional table is exactly zero");
}

fn t18() -> TestResult {
  var ok = chi2_err(stats_tests_chi_square_independence(&v2(1, 2), 1, 2), "stats-tests: need at least two rows");
  if !chi2_err(stats_tests_chi_square_independence(&v2(1, 2), 2, 1), "stats-tests: need at least two columns") { ok = false; }
  if !chi2_err(stats_tests_chi_square_independence(&v3(1, 2, 3), 2, 2), "stats-tests: table length does not match the shape") { ok = false; }
  if !chi2_err(stats_tests_chi_square_independence(&v4(1, -1, 2, 3), 2, 2), "stats-tests: table counts must not be negative") { ok = false; }
  if !chi2_err(stats_tests_chi_square_independence(&v4(0, 0, 1, 1), 2, 2), "stats-tests: row totals must be positive") { ok = false; }
  if !chi2_err(stats_tests_chi_square_independence(&v4(1, 0, 1, 0), 2, 2), "stats-tests: column totals must be positive") { ok = false; }
  if !chi2_err(stats_tests_chi_square_independence(&v2(1, 2), 9223372036854775807, 2), "stats-tests: dimensions overflow") { ok = false; }
  return assert(ok, "independence: shape, totals, sign and dimension guards");
}

fn t19() -> TestResult {
  let r = sign_of(stats_tests_sign_test(&v5(1, -1, 2, -3, 5)));
  var ok = stats_tests_sign_n_plus(&r) == 3;
  if stats_tests_sign_n_minus(&r) != 2 { ok = false; }
  if stats_tests_sign_n_zero(&r) != 0 { ok = false; }
  if stats_tests_sign_stat(&r) != 2 { ok = false; }
  if stats_tests_sign_p_bucket_of(&r) != 0 { ok = false; }
  return assert(ok, "sign: 3 plus vs 2 minus is not significant");
}

fn t20() -> TestResult {
  let r = sign_of(stats_tests_sign_test(&v5(1, 0, -1, 2, 0)));
  var ok = stats_tests_sign_n_plus(&r) == 2;
  if stats_tests_sign_n_minus(&r) != 1 { ok = false; }
  if stats_tests_sign_n_zero(&r) != 2 { ok = false; }
  if stats_tests_sign_stat(&r) != 1 { ok = false; }
  if stats_tests_sign_p_bucket_of(&r) != 0 { ok = false; }
  return assert(ok, "sign: zeros are dropped before the test");
}

fn t21() -> TestResult {
  var ok = stats_tests_sign_p_bucket(0, 5) == 0;
  if stats_tests_sign_p_bucket(0, 6) != 1 { ok = false; }
  if stats_tests_sign_p_bucket(1, 6) != 0 { ok = false; }
  if stats_tests_sign_p_bucket(0, 7) != 1 { ok = false; }
  if stats_tests_sign_p_bucket(0, 8) != 2 { ok = false; }
  if stats_tests_sign_p_bucket(0, 10) != 2 { ok = false; }
  if stats_tests_sign_p_bucket(0, 11) != 3 { ok = false; }
  if stats_tests_sign_p_bucket(5, 20) != 1 { ok = false; }
  if stats_tests_sign_p_bucket(3, 20) != 2 { ok = false; }
  if stats_tests_sign_p_bucket(2, 20) != 3 { ok = false; }
  if stats_tests_sign_p_bucket(6, 20) != 0 { ok = false; }
  if stats_tests_sign_p_bucket(-1, 5) != -1 { ok = false; }
  if stats_tests_sign_p_bucket(0, 0) != -1 { ok = false; }
  if stats_tests_sign_p_bucket(0, 21) != -1 { ok = false; }
  if stats_tests_sign_p_bucket(6, 5) != -1 { ok = false; }
  return assert(ok, "sign: binomial bucket boundaries and range guards");
}

fn t22() -> TestResult {
  let empty = empty_ints();
  var ok = sign_err(stats_tests_sign_test(&empty), "stats-tests: differences must not be empty");
  if !sign_err(stats_tests_sign_test(&v3(0, 0, 0)), "stats-tests: sign test needs at least one nonzero difference") { ok = false; }
  return assert(ok, "sign: empty input and all-zero differences are rejected");
}

fn t23() -> TestResult {
  let r1 = perm_of(stats_tests_permutation_test(&v3(1, 2, 3), &v3(4, 5, 6), 1, 20));
  var ok = stats_tests_permutation_observed_diff(&r1) == -30000;
  if stats_tests_permutation_extreme(&r1) != 1 { ok = false; }
  if stats_tests_permutation_n_perm(&r1) != 20 { ok = false; }
  if stats_tests_permutation_p_bucket_of(&r1) != 1 { ok = false; }
  let r1b = perm_of(stats_tests_permutation_test(&v3(1, 2, 3), &v3(4, 5, 6), 1, 20));
  if stats_tests_permutation_extreme(&r1b) != stats_tests_permutation_extreme(&r1) { ok = false; }
  let r2 = perm_of(stats_tests_permutation_test(&v3(1, 2, 3), &v3(4, 5, 6), 1, 200));
  if stats_tests_permutation_observed_diff(&r2) != -30000 { ok = false; }
  if stats_tests_permutation_extreme(&r2) != 18 { ok = false; }
  if stats_tests_permutation_p_bucket_of(&r2) != 0 { ok = false; }
  return assert(ok, "permutation: fixed-seed KAT and determinism");
}

fn t24() -> TestResult {
  let r = perm_of(stats_tests_permutation_test(&v3(1, 1, 2), &v3(2, 3, 3), 7, 50));
  var ok = stats_tests_permutation_observed_diff(&r) == -13334;
  if stats_tests_permutation_extreme(&r) != 9 { ok = false; }
  if stats_tests_permutation_p_bucket_of(&r) != 0 { ok = false; }
  let tied = perm_of(stats_tests_permutation_test(&v3(5, 5, 5), &v3(5, 5, 5), 3, 10));
  if stats_tests_permutation_observed_diff(&tied) != 0 { ok = false; }
  if stats_tests_permutation_extreme(&tied) != 10 { ok = false; }
  if stats_tests_permutation_p_bucket_of(&tied) != 0 { ok = false; }
  return assert(ok, "permutation: tie handling and an all-tied sample");
}

fn t25() -> TestResult {
  let empty = empty_ints();
  var ok = perm_err(stats_tests_permutation_test(&empty, &v1(1), 1, 10), "stats-tests: group A must not be empty");
  if !perm_err(stats_tests_permutation_test(&v1(1), &empty, 1, 10), "stats-tests: group B must not be empty") { ok = false; }
  if !perm_err(stats_tests_permutation_test(&v1(1), &v1(2), 1, 0), "stats-tests: permutation count must be positive") { ok = false; }
  if !perm_err(stats_tests_permutation_test(&v1(1), &v1(2), 1, 9223372036854776), "stats-tests: permutation count too large for the bucket scale") { ok = false; }
  if stats_tests_permutation_p_bucket(1, 20) != 1 { ok = false; }
  if stats_tests_permutation_p_bucket(2, 20) != 0 { ok = false; }
  if stats_tests_permutation_p_bucket(1, 5) != 0 { ok = false; }
  if stats_tests_permutation_p_bucket(1, 100) != 2 { ok = false; }
  if stats_tests_permutation_p_bucket(1, 1000) != 3 { ok = false; }
  if stats_tests_permutation_p_bucket(0, 7) != 3 { ok = false; }
  if stats_tests_permutation_p_bucket(-1, 10) != -1 { ok = false; }
  if stats_tests_permutation_p_bucket(5, 4) != -1 { ok = false; }
  if stats_tests_permutation_p_bucket(1, 0) != -1 { ok = false; }
  return assert(ok, "permutation: validation and exact ratio buckets");
}

fn main() -> Int {
  io.println("=== xiom.stats-tests conformance tests ===");
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
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.stats-tests: all tests passed");
  } else {
    io.println("xiom.stats-tests: tests failed");
  }
  return failed;
}
