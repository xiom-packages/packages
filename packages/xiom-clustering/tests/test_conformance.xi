// XIOM -- xiom.clustering conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.clustering module against its documented
// fixed-point contract (scaled integers only, no floats).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module clustering_tests
use xiom.io; use xiom.test; use xiom.clustering;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison on the pinned compiler, so
// every error-message check below is routed through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Builders (all values are data-scale raw integers: value * 1000)
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

fn v10(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int, i: Int, j: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  v.push(i);
  v.push(j);
  return v;
}

fn empty_vec() -> Vec[Int] {
  return Vec[Int].new();
}

fn push2(v: &mut Vec[Int], a: Int, b: Int) {
  v.push(a);
  v.push(b);
}

// Four points on the x axis: two around 0, two around 10000.
fn ps_line4() -> PointSet {
  var d = Vec[Int].new();
  push2(&mut d, 0, 0);
  push2(&mut d, 1000, 0);
  push2(&mut d, 9000, 0);
  push2(&mut d, 10000, 0);
  return PointSet{ count: 4; dims: 2; coords: d; };
}

// Three points on the x axis: two tight at 0, one at 10000/10200.
fn ps_line3() -> PointSet {
  var d = Vec[Int].new();
  push2(&mut d, 0, 0);
  push2(&mut d, 10000, 0);
  push2(&mut d, 10200, 0);
  return PointSet{ count: 3; dims: 2; coords: d; };
}

// Two well-separated 3-point clusters: means (1000, 0) and (10000, 0).
fn ps_two_clusters() -> PointSet {
  var d = Vec[Int].new();
  push2(&mut d, 0, 0);
  push2(&mut d, 1000, 0);
  push2(&mut d, 2000, 0);
  push2(&mut d, 9000, 0);
  push2(&mut d, 10000, 0);
  push2(&mut d, 11000, 0);
  return PointSet{ count: 6; dims: 2; coords: d; };
}

// Symmetric four-point blob around (1000, 0).
fn ps_blob() -> PointSet {
  var d = Vec[Int].new();
  push2(&mut d, 0, 0);
  push2(&mut d, 2000, 0);
  push2(&mut d, 1000, 1000);
  push2(&mut d, 1000, -1000);
  return PointSet{ count: 4; dims: 2; coords: d; };
}

// Two points: (0, 0) and (3000, 4000) -- the 3-4-5 triangle scaled by 1000.
fn ps_triangle() -> PointSet {
  var d = Vec[Int].new();
  push2(&mut d, 0, 0);
  push2(&mut d, 3000, 4000);
  return PointSet{ count: 2; dims: 2; coords: d; };
}

// Points (0, 0), (0, 0), (1000, 0) -- an exact duplicate pair.
fn ps_dup3() -> PointSet {
  var d = Vec[Int].new();
  push2(&mut d, 0, 0);
  push2(&mut d, 0, 0);
  push2(&mut d, 1000, 0);
  return PointSet{ count: 3; dims: 2; coords: d; };
}

// Points (0, 0), (1, 0), (2, 0) -- unit raw spacing for the eps boundary.
fn ps_three() -> PointSet {
  var d = Vec[Int].new();
  push2(&mut d, 0, 0);
  push2(&mut d, 1, 0);
  push2(&mut d, 2, 0);
  return PointSet{ count: 3; dims: 2; coords: d; };
}

// DBSCAN classic example, eps raw 1500, min_pts 3:
// cluster 0 = points 0..3 (square of side 1000, all core),
// point 4 = (2400, 1000) border of cluster 0,
// cluster 1 = points 5..7 (dense line),
// points 8, 9 = noise.
fn ps_classic() -> PointSet {
  var d = Vec[Int].new();
  push2(&mut d, 0, 0);
  push2(&mut d, 1000, 0);
  push2(&mut d, 0, 1000);
  push2(&mut d, 1000, 1000);
  push2(&mut d, 2400, 1000);
  push2(&mut d, 5000, 5000);
  push2(&mut d, 5100, 5000);
  push2(&mut d, 6000, 5000);
  push2(&mut d, 9000, 9000);
  push2(&mut d, 0, 9000);
  return PointSet{ count: 10; dims: 2; coords: d; };
}

fn empty_ps() -> PointSet {
  return PointSet{ count: 0; dims: 2; coords: empty_vec() };
}

fn bad_ps() -> PointSet {
  return PointSet{ count: 2; dims: 2; coords: v3(1, 2, 3) };
}

// ---------------------------------------------------------------------------
// Result extractors with graceful fallbacks: a construction failure makes
// the value checks fail instead of aborting the whole suite.
// ---------------------------------------------------------------------------

fn ps_of(r: Result[PointSet, Str]) -> PointSet {
  match r {
    Ok(p) => { return p; },
    Err(_) => { return PointSet{ count: 1; dims: 1; coords: v1(0) }; },
  }
  return PointSet{ count: 1; dims: 1; coords: v1(0) };
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

fn bool_of(r: Result[Bool, Str]) -> Bool {
  match r {
    Ok(b) => { return b; },
    Err(_) => { return false; },
  }
  return false;
}

fn kmeans_of(r: Result[KMeansModel, Str]) -> KMeansModel {
  match r {
    Ok(m) => { return m; },
    Err(_) => { return KMeansModel{ centroids: empty_vec(); assignments: empty_vec(); inertia: 0; iterations: 0; empty_clusters: 0; k: 0; dims: 0; n_points: 0; converged: false; }; },
  }
  return KMeansModel{ centroids: empty_vec(); assignments: empty_vec(); inertia: 0; iterations: 0; empty_clusters: 0; k: 0; dims: 0; n_points: 0; converged: false; };
}

fn dbscan_of(r: Result[DbscanModel, Str]) -> DbscanModel {
  match r {
    Ok(m) => { return m; },
    Err(_) => { return DbscanModel{ labels: empty_vec(); core: empty_vec(); n_clusters: 0; n_noise: 0; n_points: 0; }; },
  }
  return DbscanModel{ labels: empty_vec(); core: empty_vec(); n_clusters: 0; n_noise: 0; n_points: 0; };
}

// ---------------------------------------------------------------------------
// Error-message predicates (streq, never `==` on Str)
// ---------------------------------------------------------------------------

fn ps_err(r: Result[PointSet, Str], want: Str) -> Bool {
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

fn bool_err(r: Result[Bool, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn kmeans_err(r: Result[KMeansModel, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn dbscan_err(r: Result[DbscanModel, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Value predicates
// ---------------------------------------------------------------------------

fn ints_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var ok = true;
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      ok = false;
    }
    i = i + 1;
  }
  return ok;
}

fn centroid_is(m: &KMeansModel, c: Int, a: Int, b: Int) -> Bool {
  let got = clustering_kmeans_centroid(m, c);
  var ok = got.len() == 2;
  if got.len() == 2 {
    let x: Int = got[0];
    let y: Int = got[1];
    if x != a { ok = false; }
    if y != b { ok = false; }
  }
  return ok;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var src = v4(1000, 2000, 3000, 4000);
  let ps = ps_of(clustering_point_set_new(2, 2, &mut src));
  var ok = clustering_data_decimals() == 3;
  if clustering_point_set_count(&ps) != 2 { ok = false; }
  if clustering_point_set_dims(&ps) != 2 { ok = false; }
  if clustering_point_set_get(&ps, 0, 0) != 1000 { ok = false; }
  if clustering_point_set_get(&ps, 1, 1) != 4000 { ok = false; }
  src.push(9999);
  let copied = clustering_point_set_coords(&ps);
  if copied.len() != 4 { ok = false; }
  return assert(ok, "point_set_new builds a point set and copies coordinates");
}

fn t2() -> TestResult {
  var short = v1(7);
  var ok = ps_err(clustering_point_set_new(0, 2, &mut short), "clustering: count must be positive");
  if !ps_err(clustering_point_set_new(-1, 2, &mut short), "clustering: count must be positive") { ok = false; }
  if !ps_err(clustering_point_set_new(2, 0, &mut short), "clustering: dims must be positive") { ok = false; }
  if !ps_err(clustering_point_set_new(2, 2, &mut short), "clustering: coords length does not match count*dims") { ok = false; }
  return assert(ok, "point_set_new rejects bad dimensions and lengths");
}

fn t3() -> TestResult {
  let good = ps_line4();
  var ok = bool_of(clustering_point_set_validate(&good));
  let bad = bad_ps();
  if !bool_err(clustering_point_set_validate(&bad), "clustering: point set coords length mismatch") { ok = false; }
  let none = empty_ps();
  if !bool_err(clustering_point_set_validate(&none), "clustering: point set has no points") { ok = false; }
  return assert(ok, "point_set_validate accepts consistent sets and names inconsistencies");
}

fn t4() -> TestResult {
  let ps = ps_line4();
  var ok = clustering_point_set_get(&ps, 0, 0) == 0;
  if clustering_point_set_get(&ps, 3, 1) != 0 { ok = false; }
  if clustering_point_set_get(&ps, 4, 0) != 0 { ok = false; }
  if clustering_point_set_get(&ps, 0, 4) != 0 { ok = false; }
  if clustering_point_set_get(&ps, -1, 0) != 0 { ok = false; }
  if clustering_point_set_get(&ps, 0, -1) != 0 { ok = false; }
  let copied = clustering_point_set_coords(&ps);
  var ok2 = copied.len() == 8;
  if copied.len() == 8 {
    let c0: Int = copied[0];
    let c6: Int = copied[6];
    if c0 != 0 { ok2 = false; }
    if c6 != 10000 { ok2 = false; }
  }
  if !ok2 { ok = false; }
  return assert(ok, "point_set accessors are range-safe and coords copies the data");
}

fn t5() -> TestResult {
  let ps = ps_triangle();
  var ok = int_of(clustering_point_dist2(&ps, 0, 1)) == 25000000;
  if int_of(clustering_point_dist2(&ps, 0, 0)) != 0 { ok = false; }
  if int_of(clustering_point_dist2(&ps, 1, 0)) != 25000000 { ok = false; }
  if !int_err(clustering_point_dist2(&ps, 0, 2), "clustering: point index out of range") { ok = false; }
  if !int_err(clustering_point_dist2(&ps, -1, 0), "clustering: point index out of range") { ok = false; }
  let none = empty_ps();
  if !int_err(clustering_point_dist2(&none, 0, 0), "clustering: point set has no points") { ok = false; }
  return assert(ok, "point_dist2 is exact and validates indices");
}

fn t6() -> TestResult {
  let ps = ps_line4();
  let want2 = v4(0, 0, 10000, 0);
  let init2 = ints_of(clustering_kmeans_init(&ps, 2));
  var ok = ints_eq(&init2, &want2);
  let want3 = v6(0, 0, 10000, 0, 1000, 0);
  let init3 = ints_of(clustering_kmeans_init(&ps, 3));
  if !ints_eq(&init3, &want3) { ok = false; }
  return assert(ok, "kmeans_init is deterministic farthest-point seeding with lowest-index ties");
}

fn t7() -> TestResult {
  let ps = ps_line4();
  var ok = ints_err(clustering_kmeans_init(&ps, 0), "clustering: k must be at least 1");
  if !ints_err(clustering_kmeans_init(&ps, 5), "clustering: k exceeds point count") { ok = false; }
  let none = empty_ps();
  if !ints_err(clustering_kmeans_init(&none, 1), "clustering: point set has no points") { ok = false; }
  return assert(ok, "kmeans_init validates k and the point set");
}

fn t8() -> TestResult {
  let ps = ps_two_clusters();
  var init = v4(0, 0, 9000, 0);
  let m = kmeans_of(clustering_kmeans_with_init(&ps, &mut init, 10));
  let want = v6(0, 0, 0, 1, 1, 1);
  var ok = clustering_kmeans_converged(&m);
  if clustering_kmeans_iterations(&m) != 2 { ok = false; }
  if clustering_kmeans_empty_clusters(&m) != 0 { ok = false; }
  if clustering_kmeans_inertia(&m) != 4000 { ok = false; }
  if !centroid_is(&m, 0, 1000, 0) { ok = false; }
  if !centroid_is(&m, 1, 10000, 0) { ok = false; }
  let asg = clustering_kmeans_assignments(&m);
  if !ints_eq(&asg, &want) { ok = false; }
  return assert(ok, "kmeans_with_init converges to the expected two-cluster solution");
}

fn t9() -> TestResult {
  let ps = ps_two_clusters();
  let m = kmeans_of(clustering_kmeans_fit(&ps, 2, 10));
  let want = v6(0, 0, 0, 1, 1, 1);
  var ok = clustering_kmeans_converged(&m);
  if clustering_kmeans_iterations(&m) != 2 { ok = false; }
  if !centroid_is(&m, 0, 1000, 0) { ok = false; }
  if !centroid_is(&m, 1, 10000, 0) { ok = false; }
  let asg = clustering_kmeans_assignments(&m);
  if !ints_eq(&asg, &want) { ok = false; }
  return assert(ok, "kmeans_fit with the seeded init matches the caller-init run");
}

fn t10() -> TestResult {
  let ps = ps_blob();
  let m = kmeans_of(clustering_kmeans_fit(&ps, 1, 10));
  let want = v4(0, 0, 0, 0);
  var ok = clustering_kmeans_converged(&m);
  if clustering_kmeans_k(&m) != 1 { ok = false; }
  if clustering_kmeans_iterations(&m) != 2 { ok = false; }
  if clustering_kmeans_inertia(&m) != 4000 { ok = false; }
  if !centroid_is(&m, 0, 1000, 0) { ok = false; }
  let asg = clustering_kmeans_assignments(&m);
  if !ints_eq(&asg, &want) { ok = false; }
  return assert(ok, "single-cluster data collapses to its mean");
}

fn t11() -> TestResult {
  let ps = ps_line4();
  let m2 = kmeans_of(clustering_kmeans_fit(&ps, 2, 10));
  var ok = clustering_kmeans_inertia(&m2) == 1000;
  let m1 = kmeans_of(clustering_kmeans_fit(&ps, 1, 10));
  if clustering_kmeans_inertia(&m1) != 82000 { ok = false; }
  return assert(ok, "inertia matches the hand-computed scaled values");
}

fn t12() -> TestResult {
  let ps = ps_line3();
  var init = v6(0, 0, 10000, 0, 7000, 0);
  let m = kmeans_of(clustering_kmeans_with_init(&ps, &mut init, 10));
  let want = v3(0, 1, 1);
  var ok = clustering_kmeans_converged(&m);
  if clustering_kmeans_empty_clusters(&m) != 1 { ok = false; }
  if clustering_kmeans_iterations(&m) != 2 { ok = false; }
  if !centroid_is(&m, 2, 7000, 0) { ok = false; }
  let asg = clustering_kmeans_assignments(&m);
  if !ints_eq(&asg, &want) { ok = false; }
  return assert(ok, "empty clusters keep their previous centroid and are counted");
}

fn t13() -> TestResult {
  let ps = ps_line4();
  let m1 = kmeans_of(clustering_kmeans_fit(&ps, 2, 1));
  var ok = !clustering_kmeans_converged(&m1);
  if clustering_kmeans_iterations(&m1) != 1 { ok = false; }
  if clustering_kmeans_inertia(&m1) != 1000 { ok = false; }
  let m2 = kmeans_of(clustering_kmeans_fit(&ps, 2, 2));
  if !clustering_kmeans_converged(&m2) { ok = false; }
  if clustering_kmeans_iterations(&m2) != 2 { ok = false; }
  return assert(ok, "convergence is assignment stability within max_iter");
}

fn t14() -> TestResult {
  let ps = ps_two_clusters();
  let m = kmeans_of(clustering_kmeans_fit(&ps, 2, 10));
  var ok = clustering_kmeans_k(&m) == 2;
  if clustering_kmeans_dims(&m) != 2 { ok = false; }
  if clustering_kmeans_n_points(&m) != 6 { ok = false; }
  let neg = clustering_kmeans_centroid(&m, -1);
  let over = clustering_kmeans_centroid(&m, 2);
  if neg.len() != 0 { ok = false; }
  if over.len() != 0 { ok = false; }
  let cents = clustering_kmeans_centroids(&m);
  if cents.len() != 4 { ok = false; }
  if clustering_kmeans_assignment(&m, -1) != -1 { ok = false; }
  if clustering_kmeans_assignment(&m, 6) != -1 { ok = false; }
  if clustering_kmeans_assignment(&m, 5) != 1 { ok = false; }
  return assert(ok, "kmeans accessors are range-safe");
}

fn t15() -> TestResult {
  let ps = ps_two_clusters();
  var empty_init = empty_vec();
  var ok = kmeans_err(clustering_kmeans_with_init(&ps, &mut empty_init, 10), "clustering: initial centroids length mismatch");
  var short = v3(0, 0, 0);
  if !kmeans_err(clustering_kmeans_with_init(&ps, &mut short, 10), "clustering: initial centroids length mismatch") { ok = false; }
  var init = v4(0, 0, 9000, 0);
  if !kmeans_err(clustering_kmeans_with_init(&ps, &mut init, 0), "clustering: max_iter must be at least 1") { ok = false; }
  if !kmeans_err(clustering_kmeans_fit(&ps, 0, 10), "clustering: k must be at least 1") { ok = false; }
  if !kmeans_err(clustering_kmeans_fit(&ps, 9, 10), "clustering: k exceeds point count") { ok = false; }
  if !kmeans_err(clustering_kmeans_fit(&ps, 2, 0), "clustering: max_iter must be at least 1") { ok = false; }
  return assert(ok, "kmeans validates init shape, k and max_iter");
}

fn t16() -> TestResult {
  let ps = ps_classic();
  let m = dbscan_of(clustering_dbscan_fit(&ps, 1500, 3));
  let want = v10(0, 0, 0, 0, 0, 1, 1, 1, -1, -1);
  let want_core = v10(1, 1, 1, 1, 0, 1, 1, 1, 0, 0);
  var ok = clustering_dbscan_n_clusters(&m) == 2;
  if clustering_dbscan_n_noise(&m) != 2 { ok = false; }
  if clustering_dbscan_n_points(&m) != 10 { ok = false; }
  let labels = clustering_dbscan_labels(&m);
  if !ints_eq(&labels, &want) { ok = false; }
  var i = 0;
  while i < 10 {
    let expected_core: Int = want_core[i];
    var is_core = false;
    if expected_core == 1 { is_core = true; }
    if clustering_dbscan_is_core(&m, i) != is_core { ok = false; }
    i = i + 1;
  }
  if clustering_dbscan_label(&m, 99) != -1 { ok = false; }
  if clustering_dbscan_is_core(&m, -1) { ok = false; }
  return assert(ok, "dbscan classic example finds two clusters, one border and two noise points");
}

fn t17() -> TestResult {
  let ps = ps_dup3();
  let m1 = dbscan_of(clustering_dbscan_fit(&ps, 0, 1));
  let want1 = v3(0, 0, 1);
  var ok = clustering_dbscan_n_clusters(&m1) == 2;
  if clustering_dbscan_n_noise(&m1) != 0 { ok = false; }
  let labels1 = clustering_dbscan_labels(&m1);
  if !ints_eq(&labels1, &want1) { ok = false; }
  let m2 = dbscan_of(clustering_dbscan_fit(&ps, 0, 2));
  let want2 = v3(0, 0, -1);
  if clustering_dbscan_n_clusters(&m2) != 1 { ok = false; }
  if clustering_dbscan_n_noise(&m2) != 1 { ok = false; }
  let labels2 = clustering_dbscan_labels(&m2);
  if !ints_eq(&labels2, &want2) { ok = false; }
  let unit = ps_three();
  let m3 = dbscan_of(clustering_dbscan_fit(&unit, 1, 2));
  let want3 = v3(0, 0, 0);
  if clustering_dbscan_n_clusters(&m3) != 1 { ok = false; }
  let labels3 = clustering_dbscan_labels(&m3);
  if !ints_eq(&labels3, &want3) { ok = false; }
  return assert(ok, "dbscan epsilon edges: zero radius and exact-boundary neighbors");
}

fn t18() -> TestResult {
  let ps = ps_classic();
  let nb4 = ints_of(clustering_dbscan_neighbors(&ps, 4, 1500));
  let want4 = v2(3, 4);
  var ok = ints_eq(&nb4, &want4);
  let nb0 = ints_of(clustering_dbscan_neighbors(&ps, 0, 1500));
  let want0 = v4(0, 1, 2, 3);
  if !ints_eq(&nb0, &want0) { ok = false; }
  if !ints_err(clustering_dbscan_neighbors(&ps, 10, 1500), "clustering: point index out of range") { ok = false; }
  if !ints_err(clustering_dbscan_neighbors(&ps, -1, 1500), "clustering: point index out of range") { ok = false; }
  return assert(ok, "dbscan_neighbors returns the exact linear-scan neighborhood");
}

fn t19() -> TestResult {
  let ps = ps_classic();
  var ok = dbscan_err(clustering_dbscan_fit(&ps, -1, 3), "clustering: epsilon must not be negative");
  if !dbscan_err(clustering_dbscan_fit(&ps, 1000000001, 3), "clustering: epsilon exceeds the supported magnitude") { ok = false; }
  if !dbscan_err(clustering_dbscan_fit(&ps, 1500, 0), "clustering: min_pts must be at least 1") { ok = false; }
  if !ints_err(clustering_dbscan_neighbors(&ps, 0, -5), "clustering: epsilon must not be negative") { ok = false; }
  let none = empty_ps();
  if !dbscan_err(clustering_dbscan_fit(&none, 1500, 3), "clustering: point set has no points") { ok = false; }
  return assert(ok, "dbscan validates epsilon, min_pts and the point set");
}

fn t20() -> TestResult {
  let ps = ps_classic();
  let m = dbscan_of(clustering_dbscan_fit(&ps, 1500, 3));
  var ok = clustering_dbscan_n_clusters(&m) == 2;
  if clustering_dbscan_label(&m, 0) != 0 { ok = false; }
  if clustering_dbscan_label(&m, 8) != -1 { ok = false; }
  if clustering_dbscan_label(&m, -1) != -1 { ok = false; }
  if clustering_dbscan_label(&m, 10) != -1 { ok = false; }
  if clustering_dbscan_is_core(&m, 10) { ok = false; }
  if !clustering_dbscan_is_core(&m, 5) { ok = false; }
  let labels = clustering_dbscan_labels(&m);
  if labels.len() != 10 { ok = false; }
  return assert(ok, "dbscan accessors are range-safe");
}

fn t21() -> TestResult {
  let none = empty_ps();
  var ok = kmeans_err(clustering_kmeans_fit(&none, 1, 10), "clustering: point set has no points");
  var init = v2(0, 0);
  if !kmeans_err(clustering_kmeans_with_init(&none, &mut init, 10), "clustering: point set has no points") { ok = false; }
  if !dbscan_err(clustering_dbscan_fit(&none, 1000, 2), "clustering: point set has no points") { ok = false; }
  let bad = bad_ps();
  if !dbscan_err(clustering_dbscan_fit(&bad, 1000, 2), "clustering: point set coords length mismatch") { ok = false; }
  if !kmeans_err(clustering_kmeans_fit(&bad, 1, 10), "clustering: point set coords length mismatch") { ok = false; }
  return assert(ok, "every operation validates the point set it is given");
}

fn t22() -> TestResult {
  let ps = ps_blob();
  let m = kmeans_of(clustering_kmeans_fit(&ps, 2, 10));
  let want = v4(0, 1, 0, 0);
  var ok = clustering_kmeans_converged(&m);
  if clustering_kmeans_iterations(&m) != 2 { ok = false; }
  if !centroid_is(&m, 0, 667, 0) { ok = false; }
  if !centroid_is(&m, 1, 2000, 0) { ok = false; }
  if clustering_kmeans_inertia(&m) != 2664 { ok = false; }
  let asg = clustering_kmeans_assignments(&m);
  if !ints_eq(&asg, &want) { ok = false; }
  return assert(ok, "seeded init partitions the symmetric blob deterministically");
}

fn main() -> Int {
  io.println("=== xiom.clustering conformance tests ===");
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
    io.println("xiom.clustering: all tests passed");
  } else {
    io.println("xiom.clustering: tests failed");
  }
  return failed;
}
