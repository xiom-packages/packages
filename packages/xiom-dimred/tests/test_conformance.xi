// XIOM -- xiom.dimred conformance tests (28 checks)
// Port task: prove the pure-XIOM xiom.dimred module against its documented
// fixed-point PCA contract (scaled integers only, no floats).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module dimred_tests
use xiom.io; use xiom.test; use xiom.dimred;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every error-message
// check below is routed through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixtures (all values are data-scale raw integers: value * 1000)
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

fn empty_vec() -> Vec[Int] {
  return Vec[Int].new();
}

fn ones(n: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < n {
    v.push(1000000);
    i = i + 1;
  }
  return v;
}

fn m2x1(a: Int, b: Int) -> DimredMatrix {
  return DimredMatrix{ rows: 2; cols: 1; data: v2(a, b); };
}

fn m3x1(a: Int, b: Int, c: Int) -> DimredMatrix {
  var d = Vec[Int].new();
  d.push(a);
  d.push(b);
  d.push(c);
  return DimredMatrix{ rows: 3; cols: 1; data: d; };
}

fn m1x2(a: Int, b: Int) -> DimredMatrix {
  return DimredMatrix{ rows: 1; cols: 2; data: v2(a, b); };
}

fn m2x2(a: Int, b: Int, c: Int, d: Int) -> DimredMatrix {
  return DimredMatrix{ rows: 2; cols: 2; data: v4(a, b, c, d); };
}

fn m3x2(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> DimredMatrix {
  return DimredMatrix{ rows: 3; cols: 2; data: v6(a, b, c, d, e, f); };
}

fn m2x3zero() -> DimredMatrix {
  return DimredMatrix{ rows: 2; cols: 3; data: v6(0, 0, 0, 0, 0, 0); };
}

fn empty_m() -> DimredMatrix {
  return DimredMatrix{ rows: 0; cols: 0; data: empty_vec(); };
}

// Six samples in two clusters along x (cluster A near x=1, cluster B near
// x=9, y noise only), data scale: value * 1000.
fn cluster_data() -> DimredMatrix {
  var d = Vec[Int].new();
  d.push(1000); d.push(0);
  d.push(1200); d.push(100);
  d.push(800); d.push(-100);
  d.push(9000); d.push(0);
  d.push(9200); d.push(100);
  d.push(8800); d.push(-100);
  return DimredMatrix{ rows: 6; cols: 2; data: d; };
}

// M1: 3x2 with rows (1,2), (3,4), (5,6) at data scale.
fn m1() -> DimredMatrix {
  return m3x2(1000, 2000, 3000, 4000, 5000, 6000);
}

// C1: diag(4.000, 1.000) in covariance scale.
fn c1() -> DimredMatrix {
  return m2x2(4000, 0, 0, 1000);
}

// C2: [[4, 1], [1, 1]] in covariance scale (lambda ~ 4.303 and 0.697).
fn c2() -> DimredMatrix {
  return m2x2(4000, 1000, 1000, 1000);
}

// ---------------------------------------------------------------------------
// Result extractors with graceful fallbacks: a construction failure makes
// the value checks fail instead of aborting the whole suite.
// ---------------------------------------------------------------------------

fn mat_of(r: Result[DimredMatrix, Str]) -> DimredMatrix {
  match r {
    Ok(m) => { return m; },
    Err(_) => { return DimredMatrix{ rows: 1; cols: 1; data: v1(0) }; },
  }
  return DimredMatrix{ rows: 1; cols: 1; data: v1(0) };
}

fn ints_of(r: Result[Vec[Int], Str]) -> Vec[Int] {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_vec(); },
  }
  return empty_vec();
}

fn int_of(r: Result[Int, Str]) -> Int {
  match r {
    Ok(x) => { return x; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn eigen_of(r: Result[Eigenpair, Str]) -> Eigenpair {
  match r {
    Ok(ep) => { return ep; },
    Err(_) => { return Eigenpair{ value: 0; vector: empty_vec(); iterations: 0; }; },
  }
  return Eigenpair{ value: 0; vector: empty_vec(); iterations: 0; };
}

fn model_of(r: Result[PcaModel, Str]) -> PcaModel {
  match r {
    Ok(m) => { return m; },
    Err(_) => { return PcaModel{ means: empty_vec(); components: empty_vec(); eigenvalues: empty_vec(); explained_bps: empty_vec(); iterations: empty_vec(); n_features: 0; n_components: 0; }; },
  }
  return PcaModel{ means: empty_vec(); components: empty_vec(); eigenvalues: empty_vec(); explained_bps: empty_vec(); iterations: empty_vec(); n_features: 0; n_components: 0; };
}

// ---------------------------------------------------------------------------
// Error-message predicates
// ---------------------------------------------------------------------------

fn matrix_err(r: Result[DimredMatrix, Str], want: Str) -> Bool {
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

fn int_err(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn eigen_err(r: Result[Eigenpair, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn model_err(r: Result[PcaModel, Str], want: Str) -> Bool {
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
  var ok = dimred_data_decimals() == 3;
  if dimred_covariance_decimals() != 3 { ok = false; }
  if dimred_vector_decimals() != 6 { ok = false; }
  return assert(ok, "dimred scale accessors are 3/3/6");
}

fn t2() -> TestResult {
  var vals = v4(1000, 2000, 3000, 4000);
  let m = mat_of(dimred_matrix_new(2, 2, &mut vals));
  var ok = dimred_matrix_rows(&m) == 2;
  if dimred_matrix_cols(&m) != 2 { ok = false; }
  if dimred_matrix_get(&m, 0, 0) != 1000 { ok = false; }
  if dimred_matrix_get(&m, 1, 1) != 4000 { ok = false; }
  if dimred_matrix_get(&m, 5, 0) != 0 { ok = false; }
  if dimred_matrix_get(&m, 0, -1) != 0 { ok = false; }
  if dimred_matrix_get(&m, -1, 0) != 0 { ok = false; }
  return assert(ok, "matrix_new builds a row-major matrix");
}

fn t3() -> TestResult {
  var short = v4(1, 2, 3, 4);
  var ok = matrix_err(dimred_matrix_new(0, 2, &mut short), "dimred: rows must be positive");
  if !matrix_err(dimred_matrix_new(-1, 2, &mut short), "dimred: rows must be positive") { ok = false; }
  if !matrix_err(dimred_matrix_new(2, 0, &mut short), "dimred: cols must be positive") { ok = false; }
  var three = v1(7);
  if !matrix_err(dimred_matrix_new(2, 2, &mut three), "dimred: values length does not match rows*cols") { ok = false; }
  return assert(ok, "matrix_new rejects bad dimensions and lengths");
}

fn t4() -> TestResult {
  var vals = v4(1000, 2000, 3000, 4000);
  let m = mat_of(dimred_matrix_new(2, 2, &mut vals));
  vals.push(9999);
  vals.push(8888);
  let d = dimred_matrix_data(&m);
  var ok = d.len() == 4;
  if d.len() == 4 {
    let d0: Int = d[0];
    let d3: Int = d[3];
    if d0 != 1000 { ok = false; }
    if d3 != 4000 { ok = false; }
  }
  return assert(ok, "matrix_new copies the caller values");
}

fn t5() -> TestResult {
  let m = m1();
  let means = ints_of(dimred_column_means(&m));
  var ok = means.len() == 2;
  if means.len() == 2 {
    let a: Int = means[0];
    let b: Int = means[1];
    if a != 3000 { ok = false; }
    if b != 4000 { ok = false; }
  }
  return assert(ok, "column_means computes exact means");
}

fn t6() -> TestResult {
  let half = m2x2(1000, -1000, 1001, -1001);
  let means = ints_of(dimred_column_means(&half));
  var ok = means.len() == 2;
  if means.len() == 2 {
    let a: Int = means[0];
    let b: Int = means[1];
    if a != 1001 { ok = false; }
    if b != -1001 { ok = false; }
  }
  let exact = m3x1(1000, 1001, 1002);
  let means2 = ints_of(dimred_column_means(&exact));
  if means2.len() != 1 { ok = false; }
  if means2.len() == 1 {
    let c: Int = means2[0];
    if c != 1001 { ok = false; }
  }
  return assert(ok, "column_means rounds halves away from zero");
}

fn t7() -> TestResult {
  let e = empty_m();
  let r = dimred_column_means(&e);
  return assert(ints_err(r, "dimred: matrix has no rows"), "column_means rejects an empty matrix");
}

fn t8() -> TestResult {
  let m = m1();
  let means = v2(3000, 4000);
  let c = mat_of(dimred_center(&m, &means));
  var ok = dimred_matrix_rows(&c) == 3;
  if dimred_matrix_cols(&c) != 2 { ok = false; }
  var vals = Vec[Int].new();
  vals.push(dimred_matrix_get(&c, 0, 0));
  vals.push(dimred_matrix_get(&c, 0, 1));
  vals.push(dimred_matrix_get(&c, 1, 0));
  vals.push(dimred_matrix_get(&c, 1, 1));
  vals.push(dimred_matrix_get(&c, 2, 0));
  vals.push(dimred_matrix_get(&c, 2, 1));
  let c00: Int = vals[0];
  let c01: Int = vals[1];
  let c10: Int = vals[2];
  let c11: Int = vals[3];
  let c20: Int = vals[4];
  let c21: Int = vals[5];
  if c00 != -2000 { ok = false; }
  if c01 != -2000 { ok = false; }
  if c10 != 0 { ok = false; }
  if c11 != 0 { ok = false; }
  if c20 != 2000 { ok = false; }
  if c21 != 2000 { ok = false; }
  return assert(ok, "center subtracts the means");
}

fn t9() -> TestResult {
  let m = m1();
  let bad = v1(3000);
  return assert(matrix_err(dimred_center(&m, &bad), "dimred: means length mismatch"), "center rejects a means length mismatch");
}

fn t10() -> TestResult {
  let centered = m3x2(-2000, -2000, 0, 0, 2000, 2000);
  let cov = mat_of(dimred_covariance(&centered));
  var ok = dimred_matrix_rows(&cov) == 2;
  if dimred_matrix_cols(&cov) != 2 { ok = false; }
  if dimred_matrix_get(&cov, 0, 0) != 4000 { ok = false; }
  if dimred_matrix_get(&cov, 0, 1) != 4000 { ok = false; }
  if dimred_matrix_get(&cov, 1, 0) != 4000 { ok = false; }
  if dimred_matrix_get(&cov, 1, 1) != 4000 { ok = false; }
  return assert(ok, "covariance of a rank-1 centered cloud");
}

fn t11() -> TestResult {
  let data = cluster_data();
  let means = v2(5000, 0);
  let centered = mat_of(dimred_center(&data, &means));
  let cov = mat_of(dimred_covariance(&centered));
  var ok = dimred_matrix_rows(&cov) == 2;
  if dimred_matrix_cols(&cov) != 2 { ok = false; }
  if dimred_matrix_get(&cov, 0, 0) != 19232 { ok = false; }
  if dimred_matrix_get(&cov, 0, 1) != 16 { ok = false; }
  if dimred_matrix_get(&cov, 1, 0) != 16 { ok = false; }
  if dimred_matrix_get(&cov, 1, 1) != 8 { ok = false; }
  return assert(ok, "covariance of 2-cluster data is exact");
}

fn t12() -> TestResult {
  let one = m1x2(1000, 2000);
  return assert(matrix_err(dimred_covariance(&one), "dimred: covariance needs at least 2 samples"), "covariance needs at least 2 samples");
}

fn t13() -> TestResult {
  let cov = c1();
  var init = ones(2);
  let ep = eigen_of(dimred_power_iteration(&cov, &mut init, 64, 100));
  var ok = ep.value == 4000;
  if ep.vector.len() != 2 { ok = false; }
  if ep.vector.len() == 2 {
    let a: Int = ep.vector[0];
    let b: Int = ep.vector[1];
    if a != 1000000 { ok = false; }
    if b != 0 { ok = false; }
  }
  if ep.iterations < 1 { ok = false; }
  if ep.iterations > 64 { ok = false; }
  return assert(ok, "power iteration on a diagonal covariance");
}

fn t14() -> TestResult {
  let cov = c2();
  var init = ones(2);
  let ep = eigen_of(dimred_power_iteration(&cov, &mut init, 500, 5));
  var ok = ep.value >= 4290;
  if ep.value > 4315 { ok = false; }
  if ep.vector.len() != 2 { ok = false; }
  if ep.vector.len() == 2 {
    let a: Int = ep.vector[0];
    let b: Int = ep.vector[1];
    if a != 1000000 { ok = false; }
    if b < 295000 { ok = false; }
    if b > 310000 { ok = false; }
  }
  if ep.iterations < 1 { ok = false; }
  if ep.iterations > 500 { ok = false; }
  return assert(ok, "power iteration on a general 2x2 covariance");
}

fn t15() -> TestResult {
  let zero = m2x2(0, 0, 0, 0);
  var init = ones(2);
  var ok = eigen_err(dimred_power_iteration(&zero, &mut init, 64, 10), "dimred: covariance matrix is zero");
  let cov = c1();
  var zi = v2(0, 0);
  if !eigen_err(dimred_power_iteration(&cov, &mut zi, 64, 10), "dimred: initial vector must not be all zeros") { ok = false; }
  return assert(ok, "power iteration rejects zero covariance and zero init");
}

fn t16() -> TestResult {
  let cov = c1();
  var init = ones(3);
  var ok = eigen_err(dimred_power_iteration(&cov, &mut init, 64, 10), "dimred: initial vector length mismatch");
  var init2 = ones(2);
  if !eigen_err(dimred_power_iteration(&cov, &mut init2, 0, 10), "dimred: max_iter must be at least 1") { ok = false; }
  var init3 = ones(2);
  if !eigen_err(dimred_power_iteration(&cov, &mut init3, 64, -1), "dimred: tolerance must not be negative") { ok = false; }
  let rect = m2x3zero();
  var init4 = ones(2);
  if !eigen_err(dimred_power_iteration(&rect, &mut init4, 64, 10), "dimred: covariance matrix must be square") { ok = false; }
  return assert(ok, "power iteration validates its parameters");
}

fn t17() -> TestResult {
  let slow = m2x2(4000, 0, 0, 3999);
  var init = ones(2);
  let r = dimred_power_iteration(&slow, &mut init, 3, 0);
  return assert(eigen_err(r, "dimred: power iteration did not converge"), "power iteration reports non-convergence");
}

fn t18() -> TestResult {
  let cov = c1();
  var init = ones(2);
  let ep = eigen_of(dimred_power_iteration(&cov, &mut init, 64, 100));
  let defl = mat_of(dimred_deflate(&cov, &ep));
  var ok = dimred_matrix_get(&defl, 0, 0) == 0;
  if dimred_matrix_get(&defl, 0, 1) != 0 { ok = false; }
  if dimred_matrix_get(&defl, 1, 0) != 0 { ok = false; }
  if dimred_matrix_get(&defl, 1, 1) != 1000 { ok = false; }
  var init2 = ones(2);
  let ep2 = eigen_of(dimred_power_iteration(&defl, &mut init2, 64, 100));
  if ep2.value != 1000 { ok = false; }
  if ep2.vector.len() != 2 { ok = false; }
  if ep2.vector.len() == 2 {
    let a: Int = ep2.vector[0];
    let b: Int = ep2.vector[1];
    if a != 0 { ok = false; }
    if b != 1000000 { ok = false; }
  }
  return assert(ok, "deflation removes the dominant eigenpair");
}

fn t19() -> TestResult {
  let cov = c2();
  var init = ones(2);
  let ep1 = eigen_of(dimred_power_iteration(&cov, &mut init, 500, 5));
  let defl = mat_of(dimred_deflate(&cov, &ep1));
  let t00 = dimred_matrix_get(&defl, 0, 0);
  let t11 = dimred_matrix_get(&defl, 1, 1);
  let tr = t00 + t11;
  var ok = tr >= 670;
  if tr > 720 { ok = false; }
  var init2 = ones(2);
  let ep2 = eigen_of(dimred_power_iteration(&defl, &mut init2, 500, 5));
  if ep2.value < 670 { ok = false; }
  if ep2.value > 720 { ok = false; }
  if ep2.vector.len() != 2 { ok = false; }
  if ep2.vector.len() == 2 {
    let a: Int = ep2.vector[0];
    let b: Int = ep2.vector[1];
    if a > -295000 { ok = false; }
    if a < -310000 { ok = false; }
    if b != 1000000 { ok = false; }
  }
  return assert(ok, "deflation preserves the remaining eigenvalue");
}

fn t20() -> TestResult {
  let cov = c1();
  let bad = Eigenpair{ value: 4000; vector: v1(1000000); iterations: 1; };
  var ok = matrix_err(dimred_deflate(&cov, &bad), "dimred: eigenvector length mismatch");
  let zero = Eigenpair{ value: 4000; vector: v2(0, 0); iterations: 1; };
  if !matrix_err(dimred_deflate(&cov, &zero), "dimred: eigenvector must not be all zeros") { ok = false; }
  return assert(ok, "deflation validates the eigenvector");
}

fn t21() -> TestResult {
  let centered = m3x2(-2000, -2000, 0, 0, 2000, 2000);
  let comp = v2(1000000, 1000000);
  let scores = ints_of(dimred_project(&centered, &comp));
  var ok = scores.len() == 3;
  var sum: Int = 0;
  if scores.len() == 3 {
    let s0: Int = scores[0];
    let s1: Int = scores[1];
    let s2: Int = scores[2];
    sum = s0 + s1 + s2;
    if s0 != -4000 { ok = false; }
    if s1 != 0 { ok = false; }
    if s2 != 4000 { ok = false; }
  }
  let axis = v2(1000000, 0);
  let col0 = ints_of(dimred_project(&centered, &axis));
  if col0.len() != 3 { ok = false; }
  if col0.len() == 3 {
    let c0: Int = col0[0];
    let c2: Int = col0[2];
    if c0 != -2000 { ok = false; }
    if c2 != 2000 { ok = false; }
  }
  if sum != 0 { ok = false; }
  return assert(ok, "project returns exact scores and zero sum");
}

fn t22() -> TestResult {
  let centered = m3x2(-2000, -2000, 0, 0, 2000, 2000);
  let bad = v1(5);
  var ok = ints_err(dimred_project(&centered, &bad), "dimred: component length mismatch");
  let e = empty_m();
  let comp = v2(1000000, 0);
  if !ints_err(dimred_project(&e, &comp), "dimred: matrix has no rows") { ok = false; }
  return assert(ok, "project validates the component length");
}

fn t23() -> TestResult {
  let cov = c1();
  var ok = int_of(dimred_explained_variance_bps(4000, &cov)) == 8000;
  if int_of(dimred_explained_variance_bps(1000, &cov)) != 2000 { ok = false; }
  if int_of(dimred_explained_variance_bps(6000, &cov)) != 10000 { ok = false; }
  if int_of(dimred_explained_variance_bps(0, &cov)) != 0 { ok = false; }
  let zero = m2x2(0, 0, 0, 0);
  if !int_err(dimred_explained_variance_bps(1, &zero), "dimred: covariance trace must be positive") { ok = false; }
  return assert(ok, "explained variance is bps of the trace");
}

fn t24() -> TestResult {
  let data = cluster_data();
  let model = model_of(dimred_pca_fit(&data, 2, 500, 5));
  var ok = dimred_pca_n_features(&model) == 2;
  if dimred_pca_n_components(&model) != 2 { ok = false; }
  if dimred_pca_mean(&model, 0) != 5000 { ok = false; }
  if dimred_pca_mean(&model, 1) != 0 { ok = false; }
  let comp0 = dimred_pca_component(&model, 0);
  if comp0.len() != 2 { ok = false; }
  if comp0.len() == 2 {
    let c0: Int = comp0[0];
    let c1: Int = comp0[1];
    if c0 != 1000000 { ok = false; }
    if c1 < 0 { ok = false; }
    if c1 > 5000 { ok = false; }
  }
  let e0 = dimred_pca_eigenvalue(&model, 0);
  if e0 < 19000 { ok = false; }
  if e0 > 19400 { ok = false; }
  let bps0 = dimred_pca_explained_bps(&model, 0);
  if bps0 < 9900 { ok = false; }
  if bps0 > 10000 { ok = false; }
  let bps1 = dimred_pca_explained_bps(&model, 1);
  if bps1 < 0 { ok = false; }
  if bps1 > 200 { ok = false; }
  let it0 = dimred_pca_iterations(&model, 0);
  if it0 < 1 { ok = false; }
  if it0 > 500 { ok = false; }
  return assert(ok, "pca_fit recovers the 2-cluster direction");
}

fn t25() -> TestResult {
  let data = cluster_data();
  let model = model_of(dimred_pca_fit(&data, 2, 500, 5));
  let scores = mat_of(dimred_pca_transform(&model, &data));
  var ok = dimred_matrix_rows(&scores) == 6;
  if dimred_matrix_cols(&scores) != 2 { ok = false; }
  let s0 = dimred_matrix_get(&scores, 0, 0);
  let s1 = dimred_matrix_get(&scores, 1, 0);
  let s3 = dimred_matrix_get(&scores, 3, 0);
  if s0 > -3000 { ok = false; }
  if s3 < 3000 { ok = false; }
  if s0 == s1 { ok = false; }
  let q0 = dimred_matrix_get(&scores, 0, 1);
  if q0 > 2000 { ok = false; }
  if q0 < -2000 { ok = false; }
  return assert(ok, "pca_transform separates the clusters");
}

fn t26() -> TestResult {
  let one = m1x2(1000, 2000);
  var ok = model_err(dimred_pca_fit(&one, 1, 64, 10), "dimred: pca needs at least 2 samples");
  let data = cluster_data();
  if !model_err(dimred_pca_fit(&data, 0, 64, 10), "dimred: number of components must be at least 1") { ok = false; }
  if !model_err(dimred_pca_fit(&data, 3, 64, 10), "dimred: number of components exceeds feature count") { ok = false; }
  if !model_err(dimred_pca_fit(&data, 1, 0, 10), "dimred: max_iter must be at least 1") { ok = false; }
  if !model_err(dimred_pca_fit(&data, 1, 64, -5), "dimred: tolerance must not be negative") { ok = false; }
  return assert(ok, "pca_fit validates its parameters");
}

fn t27() -> TestResult {
  let data = cluster_data();
  let model = model_of(dimred_pca_fit(&data, 2, 500, 5));
  var ok = dimred_pca_mean(&model, 9) == 0;
  if dimred_pca_mean(&model, -1) != 0 { ok = false; }
  if dimred_pca_component(&model, 2).len() != 0 { ok = false; }
  if dimred_pca_component(&model, -1).len() != 0 { ok = false; }
  if dimred_pca_eigenvalue(&model, 5) != 0 { ok = false; }
  if dimred_pca_explained_bps(&model, -3) != 0 { ok = false; }
  if dimred_pca_iterations(&model, 7) != 0 { ok = false; }
  let model2 = model_of(dimred_pca_fit(&data, 1, 500, 5));
  let comp = dimred_pca_component(&model2, 0);
  if comp.len() != 2 { ok = false; }
  let m3 = m2x3zero();
  if !matrix_err(dimred_pca_transform(&model2, &m3), "dimred: feature count does not match the model") { ok = false; }
  return assert(ok, "pca accessors are range-safe");
}

fn t28() -> TestResult {
  let flat = m3x2(1000, 2000, 1000, 2000, 1000, 2000);
  return assert(model_err(dimred_pca_fit(&flat, 1, 64, 10), "dimred: covariance trace must be positive"), "pca_fit rejects a constant dataset");
}

fn main() -> Int {
  io.println("=== xiom.dimred conformance tests ===");
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
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.dimred: all tests passed");
  } else {
    io.println("xiom.dimred: tests failed");
  }
  return failed;
}
