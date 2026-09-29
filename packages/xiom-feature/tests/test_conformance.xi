// XIOM -- xiom.feature conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.feature module against its documented
// fixed-point contract (scaled integers only, no floats, no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module feature_tests
use xiom.io; use xiom.test; use xiom.feature;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// error-message check below is routed through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixtures (all values are data-scale raw integers: value * 1000)
// ---------------------------------------------------------------------------

fn empty_vec() -> Vec[Int] {
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

fn tokens() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("");
  v.push("a");
  v.push("hello");
  v.push("foobar");
  v.push("é");
  v.push("α");
  return v;
}

fn m1x2(a: Int, b: Int) -> FeatureMatrix {
  return FeatureMatrix{ rows: 1; cols: 2; data: v2(a, b); };
}

fn sel_matrix() -> FeatureMatrix {
  // 4 samples x 3 features: column 0 is constant, column 1 is a 1k step
  // ramp, column 2 a 2k step ramp. Sample variances: 0, 1667, 6667.
  var d = Vec[Int].new();
  d.push(1000); d.push(1000); d.push(1000);
  d.push(1000); d.push(2000); d.push(3000);
  d.push(1000); d.push(3000); d.push(5000);
  d.push(1000); d.push(4000); d.push(7000);
  return FeatureMatrix{ rows: 4; cols: 3; data: d; };
}

fn const_matrix() -> FeatureMatrix {
  return FeatureMatrix{ rows: 4; cols: 1; data: v4(1000, 1000, 1000, 1000) };
}

// ---------------------------------------------------------------------------
// Result extractors with graceful fallbacks: a construction failure makes
// the value checks fail instead of aborting the whole suite.
// ---------------------------------------------------------------------------

fn int_of(r: Result[Int, Str]) -> Int {
  match r {
    Ok(x) => { return x; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn ints_of(r: Result[Vec[Int], Str]) -> Vec[Int] {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_vec(); },
  }
  return empty_vec();
}

fn matrix_of(r: Result[FeatureMatrix, Str]) -> FeatureMatrix {
  match r {
    Ok(m) => { return m; },
    Err(_) => { return FeatureMatrix{ rows: 1; cols: 1; data: v1(0) }; },
  }
  return FeatureMatrix{ rows: 1; cols: 1; data: v1(0) };
}

fn stats_of(r: Result[FeatureStats, Str]) -> FeatureStats {
  match r {
    Ok(s) => { return s; },
    Err(_) => { return FeatureStats{ mean: 0; variance: 0; min: 0; max: 0; }; },
  }
  return FeatureStats{ mean: 0; variance: 0; min: 0; max: 0; };
}

fn selection_of(r: Result[FeatureSelection, Str]) -> FeatureSelection {
  match r {
    Ok(s) => { return s; },
    Err(_) => { return FeatureSelection{ indices: empty_vec(); variances: empty_vec(); }; },
  }
  return FeatureSelection{ indices: empty_vec(); variances: empty_vec(); };
}

// ---------------------------------------------------------------------------
// Error-message predicates
// ---------------------------------------------------------------------------

fn int_err(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn ints_err(r: Result[Vec[Int], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn matrix_err(r: Result[FeatureMatrix, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn selection_err(r: Result[FeatureSelection, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn stats_err(r: Result[FeatureStats, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = feature_data_decimals() == 3;
  if feature_data_one() != 1000 { ok = false; }
  return assert(ok, "scale accessors are 3 and 1000");
}

fn t2() -> TestResult {
  var ok = int_of(feature_poly2_count(0)) == 0;
  if int_of(feature_poly2_count(1)) != 1 { ok = false; }
  if int_of(feature_poly2_count(2)) != 3 { ok = false; }
  if int_of(feature_poly2_count(3)) != 6 { ok = false; }
  if int_of(feature_poly2_count(4)) != 10 { ok = false; }
  if int_of(feature_poly2_count(4294967295)) != 9223372034707292160 { ok = false; }
  if !int_err(feature_poly2_count(-1), "feature: input length must not be negative") { ok = false; }
  if !int_err(feature_poly2_count(4294967296), "feature: polynomial expansion count overflows") { ok = false; }
  return assert(ok, "poly2_count counts n*(n+1)/2 and guards its domain");
}

fn t3() -> TestResult {
  let e = empty_vec();
  let re = ints_of(feature_poly2_expand(&e));
  var ok = re.len() == 0;
  let one = v1(1000);
  let r1 = ints_of(feature_poly2_expand(&one));
  if r1.len() != 1 { ok = false; }
  if r1.len() == 1 {
    let a: Int = r1[0];
    if a != 1000 { ok = false; }
  }
  let sq = v1(2500);
  let r2 = ints_of(feature_poly2_expand(&sq));
  if r2.len() != 1 { ok = false; }
  if r2.len() == 1 {
    let b: Int = r2[0];
    if b != 6250 { ok = false; }
  }
  return assert(ok, "poly2_expand handles empty and single inputs");
}

fn t4() -> TestResult {
  let v = v2(1000, 2000);
  let r = ints_of(feature_poly2_expand(&v));
  var ok = r.len() == 3;
  if r.len() == 3 {
    let a: Int = r[0];
    let b: Int = r[1];
    let c: Int = r[2];
    if a != 1000 { ok = false; }
    if b != 2000 { ok = false; }
    if c != 4000 { ok = false; }
  }
  return assert(ok, "poly2_expand of two inputs is (0,0), (0,1), (1,1)");
}

fn t5() -> TestResult {
  let v = v3(1000, 2000, 3000);
  let r = ints_of(feature_poly2_expand(&v));
  var ok = r.len() == 6;
  if r.len() == 6 {
    let a0: Int = r[0];
    let a1: Int = r[1];
    let a2: Int = r[2];
    let a3: Int = r[3];
    let a4: Int = r[4];
    let a5: Int = r[5];
    if a0 != 1000 { ok = false; }
    if a1 != 2000 { ok = false; }
    if a2 != 3000 { ok = false; }
    if a3 != 4000 { ok = false; }
    if a4 != 6000 { ok = false; }
    if a5 != 9000 { ok = false; }
  }
  return assert(ok, "poly2_expand ordering for three inputs is lexicographic i <= j");
}

fn t6() -> TestResult {
  let p = v2(1001, 1001);
  let rp = ints_of(feature_poly2_expand(&p));
  var ok = rp.len() == 3;
  if rp.len() == 3 {
    let a0: Int = rp[0];
    let a1: Int = rp[1];
    let a2: Int = rp[2];
    if a0 != 1002 { ok = false; }
    if a1 != 1002 { ok = false; }
    if a2 != 1002 { ok = false; }
  }
  let n = v2(-1001, 1001);
  let rn = ints_of(feature_poly2_expand(&n));
  if rn.len() != 3 { ok = false; }
  if rn.len() == 3 {
    let b0: Int = rn[0];
    let b1: Int = rn[1];
    let b2: Int = rn[2];
    if b0 != 1002 { ok = false; }
    if b1 != -1002 { ok = false; }
    if b2 != 1002 { ok = false; }
  }
  return assert(ok, "poly2_expand truncates toward zero, including negatives");
}

fn t7() -> TestResult {
  var ok = feature_hash32("") == 2166136261;
  if feature_hash32("a") != 3826002220 { ok = false; }
  if feature_hash32("hello") != 1335831723 { ok = false; }
  if feature_hash32("foobar") != 3214735720 { ok = false; }
  return assert(ok, "hash32 matches FNV-1a vectors for ASCII tokens");
}

fn t8() -> TestResult {
  var ok = feature_hash32("é") == 513665217;
  if feature_hash32("α") != 44730528 { ok = false; }
  if feature_hash32("feature") != 3837424445 { ok = false; }
  if feature_hash32("user@example.com") != 3718907387 { ok = false; }
  return assert(ok, "hash32 widens and masks bytes >= 128 correctly");
}

fn t9() -> TestResult {
  let toks = tokens();
  var ok = true;
  var k = 0;
  while k < toks.len() {
    let s: Str = toks[k];
    let h1 = feature_hash32(s);
    let h2 = feature_hash32(s);
    if h1 != h2 { ok = false; }
    if h1 < 0 { ok = false; }
    if h1 >= 4294967296 { ok = false; }
    let b8 = int_of(feature_hash_bucket(s, 8));
    if b8 < 0 { ok = false; }
    if b8 > 7 { ok = false; }
    let b100 = int_of(feature_hash_bucket(s, 100));
    if b100 < 0 { ok = false; }
    if b100 > 99 { ok = false; }
    k = k + 1;
  }
  return assert(ok, "hashing is deterministic and buckets stay in range");
}

fn t10() -> TestResult {
  var ok = int_of(feature_hash_bucket("a", 8)) == 4;
  if int_of(feature_hash_bucket("hello", 8)) != 3 { ok = false; }
  if int_of(feature_hash_bucket("foobar", 8)) != 0 { ok = false; }
  if int_of(feature_hash_bucket("é", 8)) != 1 { ok = false; }
  if int_of(feature_hash_bucket("α", 8)) != 0 { ok = false; }
  if int_of(feature_hash_bucket("", 8)) != 5 { ok = false; }
  return assert(ok, "hash buckets match hand-computed FNV-1a values mod 8");
}

fn t11() -> TestResult {
  var ok = int_err(feature_hash_bucket("x", 0), "feature: buckets must be positive");
  if !int_err(feature_hash_bucket("x", -5), "feature: buckets must be positive") { ok = false; }
  if !int_err(feature_hash_bucket_signed("x", 0), "feature: buckets must be positive") { ok = false; }
  if !int_err(feature_hash_bucket_signed("x", -1), "feature: buckets must be positive") { ok = false; }
  return assert(ok, "hashing rejects non-positive bucket counts");
}

fn t12() -> TestResult {
  var ok = int_of(feature_hash_bucket_signed("a", 8)) == 5;
  if int_of(feature_hash_bucket_signed("hello", 8)) != -4 { ok = false; }
  if int_of(feature_hash_bucket_signed("foobar", 8)) != 1 { ok = false; }
  if int_of(feature_hash_bucket_signed("é", 8)) != -2 { ok = false; }
  if int_of(feature_hash_bucket_signed("α", 8)) != 1 { ok = false; }
  let toks = tokens();
  var k = 0;
  while k < toks.len() {
    let s: Str = toks[k];
    let b = int_of(feature_hash_bucket(s, 8));
    let sg = int_of(feature_hash_bucket_signed(s, 8));
    if sg == 0 { ok = false; }
    var mag = sg;
    if mag < 0 { mag = 0 - mag; }
    if mag != b + 1 { ok = false; }
    k = k + 1;
  }
  return assert(ok, "signed hashing uses one extra bit and stays nonzero");
}

fn t13() -> TestResult {
  let a = v3(1000, 2000, 3000);
  var ok = int_of(feature_mean(&a)) == 2000;
  let h = v2(1000, 1001);
  if int_of(feature_mean(&h)) != 1001 { ok = false; }
  let n = v2(-1000, -1001);
  if int_of(feature_mean(&n)) != -1001 { ok = false; }
  let one = v1(777);
  if int_of(feature_mean(&one)) != 777 { ok = false; }
  let e = empty_vec();
  if !int_err(feature_mean(&e), "feature: empty vector") { ok = false; }
  return assert(ok, "mean rounds halves away from zero and guards empty input");
}

fn t14() -> TestResult {
  let a = v3(1000, 2000, 3000);
  var ok = int_of(feature_variance(&a)) == 1000;
  let b = v3(1000, 2000, 4000);
  if int_of(feature_variance(&b)) != 2332 { ok = false; }
  let c = v2(8000, 12000);
  if int_of(feature_variance(&c)) != 8000 { ok = false; }
  let k = v3(7000, 7000, 7000);
  if int_of(feature_variance(&k)) != 0 { ok = false; }
  let one = v1(5);
  if !int_err(feature_variance(&one), "feature: variance needs at least 2 samples") { ok = false; }
  let e = empty_vec();
  if !int_err(feature_variance(&e), "feature: variance needs at least 2 samples") { ok = false; }
  return assert(ok, "variance is the n-1 sample variance in data scale");
}

fn t15() -> TestResult {
  let a = v3(3000, -1000, 2000);
  var ok = int_of(feature_min(&a)) == -1000;
  if int_of(feature_max(&a)) != 3000 { ok = false; }
  let one = v1(42);
  if int_of(feature_min(&one)) != 42 { ok = false; }
  if int_of(feature_max(&one)) != 42 { ok = false; }
  let e = empty_vec();
  if !int_err(feature_min(&e), "feature: empty vector") { ok = false; }
  if !int_err(feature_max(&e), "feature: empty vector") { ok = false; }
  return assert(ok, "min and max scan the whole vector");
}

fn t16() -> TestResult {
  let a = v3(1000, 2000, 3000);
  let s = stats_of(feature_stats(&a));
  var ok = s.mean == 2000;
  if s.variance != 1000 { ok = false; }
  if s.min != 1000 { ok = false; }
  if s.max != 3000 { ok = false; }
  let b = v2(3000, -1000);
  let t = stats_of(feature_stats(&b));
  if t.mean != 1000 { ok = false; }
  if t.variance != 8000 { ok = false; }
  if t.min != -1000 { ok = false; }
  if t.max != 3000 { ok = false; }
  let one = v1(1);
  if !stats_err(feature_stats(&one), "feature: stats need at least 2 samples") { ok = false; }
  return assert(ok, "stats aggregates mean, variance, min and max");
}

fn t17() -> TestResult {
  let a = v3(1000, 2000, 3000);
  let r1 = ints_of(feature_minmax_scale(&a, 0, 1000));
  var ok = r1.len() == 3;
  if r1.len() == 3 {
    let a0: Int = r1[0];
    let a1: Int = r1[1];
    let a2: Int = r1[2];
    if a0 != 0 { ok = false; }
    if a1 != 500 { ok = false; }
    if a2 != 1000 { ok = false; }
  }
  let r2 = ints_of(feature_minmax_scale(&a, -1000, 1000));
  if r2.len() == 3 {
    let b0: Int = r2[0];
    let b1: Int = r2[1];
    let b2: Int = r2[2];
    if b0 != -1000 { ok = false; }
    if b1 != 0 { ok = false; }
    if b2 != 1000 { ok = false; }
  }
  let r3 = ints_of(feature_minmax_scale(&a, 1000, 0));
  if r3.len() == 3 {
    let c0: Int = r3[0];
    let c1: Int = r3[1];
    let c2: Int = r3[2];
    if c0 != 1000 { ok = false; }
    if c1 != 500 { ok = false; }
    if c2 != 0 { ok = false; }
  }
  let b = v3(1000, 2000, 4000);
  let r4 = ints_of(feature_minmax_scale(&b, 0, 1000));
  if r4.len() == 3 {
    let d0: Int = r4[0];
    let d1: Int = r4[1];
    let d2: Int = r4[2];
    if d0 != 0 { ok = false; }
    if d1 != 333 { ok = false; }
    if d2 != 1000 { ok = false; }
  }
  return assert(ok, "min-max scaling maps onto the target range, reversed included");
}

fn t18() -> TestResult {
  let k = v2(500, 500);
  var ok = ints_err(feature_minmax_scale(&k, 0, 1000), "feature: min-max scaling requires a non-constant feature");
  let one = v1(500);
  if !ints_err(feature_minmax_scale(&one, 0, 1000), "feature: min-max scaling requires a non-constant feature") { ok = false; }
  let e = empty_vec();
  if !ints_err(feature_minmax_scale(&e, 0, 1000), "feature: empty vector") { ok = false; }
  return assert(ok, "min-max scaling rejects constant and empty features");
}

fn t19() -> TestResult {
  let a = v3(1000, 2000, 3000);
  let r1 = ints_of(feature_zscore_scale(&a));
  var ok = r1.len() == 3;
  if r1.len() == 3 {
    let a0: Int = r1[0];
    let a1: Int = r1[1];
    let a2: Int = r1[2];
    if a0 != -1000 { ok = false; }
    if a1 != 0 { ok = false; }
    if a2 != 1000 { ok = false; }
  }
  let b = v3(1000, 2000, 4000);
  let r2 = ints_of(feature_zscore_scale(&b));
  if r2.len() != 3 { ok = false; }
  if r2.len() == 3 {
    let b0: Int = r2[0];
    let b1: Int = r2[1];
    let b2: Int = r2[2];
    if b0 != -872 { ok = false; }
    if b1 != -218 { ok = false; }
    if b2 != 1091 { ok = false; }
  }
  return assert(ok, "z-score scaling divides by the truncated integer sigma");
}

fn t20() -> TestResult {
  let k = v2(7000, 7000);
  var ok = ints_err(feature_zscore_scale(&k), "feature: z-score scaling requires a non-constant feature");
  let one = v1(1234);
  if !ints_err(feature_zscore_scale(&one), "feature: z-score scaling needs at least 2 samples") { ok = false; }
  let e = empty_vec();
  if !ints_err(feature_zscore_scale(&e), "feature: z-score scaling needs at least 2 samples") { ok = false; }
  return assert(ok, "z-score scaling rejects constant and too-short features");
}

fn t21() -> TestResult {
  var vals = v6(1000, 2000, 3000, 4000, 5000, 6000);
  let m = matrix_of(feature_matrix_new(2, 3, &vals));
  var ok = feature_matrix_rows(&m) == 2;
  if feature_matrix_cols(&m) != 3 { ok = false; }
  if feature_matrix_get(&m, 0, 0) != 1000 { ok = false; }
  if feature_matrix_get(&m, 1, 2) != 6000 { ok = false; }
  if feature_matrix_get(&m, 2, 0) != 0 { ok = false; }
  if feature_matrix_get(&m, 0, 3) != 0 { ok = false; }
  if feature_matrix_get(&m, -1, 0) != 0 { ok = false; }
  if feature_matrix_get(&m, 0, -1) != 0 { ok = false; }
  let col = feature_matrix_column(&m, 1);
  if col.len() != 2 { ok = false; }
  if col.len() == 2 {
    let c0: Int = col[0];
    let c1: Int = col[1];
    if c0 != 2000 { ok = false; }
    if c1 != 5000 { ok = false; }
  }
  if feature_matrix_column(&m, 3).len() != 0 { ok = false; }
  if feature_matrix_column(&m, -1).len() != 0 { ok = false; }
  vals.push(9999);
  let flat = feature_matrix_data(&m);
  if flat.len() != 6 { ok = false; }
  if flat.len() == 6 {
    let f5: Int = flat[5];
    if f5 != 6000 { ok = false; }
  }
  let short = v2(1, 2);
  if !matrix_err(feature_matrix_new(0, 3, &short), "feature: matrix rows must be positive") { ok = false; }
  if !matrix_err(feature_matrix_new(-2, 3, &short), "feature: matrix rows must be positive") { ok = false; }
  if !matrix_err(feature_matrix_new(2, 0, &short), "feature: matrix cols must be positive") { ok = false; }
  if !matrix_err(feature_matrix_new(2, 3, &short), "feature: matrix values length does not match rows*cols") { ok = false; }
  return assert(ok, "matrix_new validates shape and accessors are range-safe");
}

fn t22() -> TestResult {
  let m = sel_matrix();
  let all = selection_of(feature_variance_selector(&m, 0));
  var ok = all.indices.len() == 2;
  if all.variances.len() != 2 { ok = false; }
  if all.indices.len() == 2 {
    let i0: Int = all.indices[0];
    let i1: Int = all.indices[1];
    let w0: Int = all.variances[0];
    let w1: Int = all.variances[1];
    if i0 != 1 { ok = false; }
    if i1 != 2 { ok = false; }
    if w0 != 1667 { ok = false; }
    if w1 != 6667 { ok = false; }
  }
  let one = selection_of(feature_variance_selector(&m, 1667));
  if one.indices.len() != 1 { ok = false; }
  if one.indices.len() == 1 {
    let i: Int = one.indices[0];
    let w: Int = one.variances[0];
    if i != 2 { ok = false; }
    if w != 6667 { ok = false; }
  }
  let none = selection_of(feature_variance_selector(&m, 6667));
  if none.indices.len() != 0 { ok = false; }
  if none.variances.len() != 0 { ok = false; }
  if !selection_err(feature_variance_selector(&m, -1), "feature: variance threshold must not be negative") { ok = false; }
  let flat = m1x2(1000, 2000);
  if !selection_err(feature_variance_selector(&flat, 0), "feature: selector needs at least 2 samples") { ok = false; }
  let c = const_matrix();
  let ce = selection_of(feature_variance_selector(&c, 0));
  if ce.indices.len() != 0 { ok = false; }
  if ce.variances.len() != 0 { ok = false; }
  return assert(ok, "variance selector returns ascending parallel indices");
}

fn main() -> Int {
  io.println("=== xiom.feature conformance tests ===");
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
    io.println("xiom.feature: all tests passed");
  } else {
    io.println("xiom.feature: tests failed");
  }
  return failed;
}
