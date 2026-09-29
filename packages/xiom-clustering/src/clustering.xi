// XIOM -- xiom.clustering: fixed-point clustering on scaled integers
// Port task: replace the xiom.clustering placeholder with a pure-XIOM module
// (scaled integers only: no floats, no FFI, no I/O, no Vec[Float64]).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: every real number is a scaled integer. A raw value `r` with `d`
// fraction digits denotes the real number r / 10^d. Clustering works at one
// data scale of 3 fraction digits (raw = value * 1000):
//
//   coordinates, centroids, epsilon   3 fraction digits (raw = value * 1000)
//   squared distances                 exact sum of squared raw differences,
//                                     no division (raw = value^2 * 1e6)
//   inertia                           squared-data scale 3: every per-point
//                                     term is dist2 truncated by /1000, then
//                                     accumulated (raw = sum of value^2 * 1000)
//
// Rounding: XIOM lowers `/` to truncation toward zero. The only rounded
// quantity is the centroid recompute, which uses _div_round (half away from
// zero). Squared distances, assignment and epsilon comparisons are exact
// integer arithmetic, so tie-breaking is fully deterministic.
//
// k-means: caller-supplied initial centroids (clustering_kmeans_with_init) or
// the deterministic farthest-point seed (clustering_kmeans_init and
// clustering_kmeans_fit). Assignment picks the smallest exact squared distance
// with ties going to the lowest centroid index (strict `<`). Centroids are
// recomputed as the rounded mean of their assigned points; a cluster that
// receives no points in a recompute pass keeps its previous centroid and
// increments the empty-cluster warning count. Convergence is assignment
// stability (a pass in which no assignment changed); otherwise the loop stops
// after max_iter passes. Inertia is computed once against the final centroids
// and final assignments.
//
// DBSCAN: epsilon is in scaled units (raw = value * 1000), min_pts counts the
// point itself, neighborhoods are found by an exact linear scan over all
// points, and clusters are expanded with an explicit FIFO queue. Final labels
// are cluster ids 0..n_clusters-1, or the documented noise sentinel -1.
//
// Arithmetic envelope (no overflow detection; see SPEC.md): |coordinate raw|
// <= 1e6 (value 1000), dims <= 32, count <= 100000, |eps raw| <= 1e9. Worst
// intermediates: dist2 <= 32 * (2e6)^2 = 1.28e14, eps^2 <= 1e18, centroid
// sums <= 1e5 * 1e6 = 1e11, inertia <= 1e5 * 1.28e11 = 1.28e16.
//
// Free functions only (XIOM v0.62.1 has no methods); every public function is
// `clustering_*`. Result constructors live in the leaf helpers at the bottom
// (constructing Ok/Err inline miscompiles in some v0.62.1 code shapes).

module xiom.clustering

use xiom.string;
use xiom.convert;

const _CLU_DATA_DEC: Int = 3;
const _CLU_DATA_ONE: Int = 1000;
const _CLU_INT_MAX: Int = 9223372036854775807;
const _CLU_EPS_MAX: Int = 1000000000;
const _CLU_NOISE: Int = -1;

/// Dense point set of scaled integers, parallel fields.
///
/// `count` points of `dims` dimensions each, stored row-major in `coords`
/// (`coords[i * dims + j]`, data scale 3). Fields are internal implementation
/// detail; construct through clustering_point_set_new and read through the
/// accessors.
pub type PointSet = {
  count: Int;
  dims: Int;
  coords: Vec[Int];
}

/// Fitted k-means model.
///
/// All vectors are parallel to the fit: `centroids` holds `k` rows of `dims`
/// data-scale entries (row-major) and `assignments` holds one centroid index
/// per point; `inertia` is the scaled within-cluster sum of squares for those
/// final centroids and assignments, `iterations` the number of full
/// assignment/recompute passes performed, `empty_clusters` the number of
/// empty-cluster events during recompute passes and `converged` whether a pass
/// observed unchanged assignments.
pub type KMeansModel = {
  centroids: Vec[Int];
  assignments: Vec[Int];
  inertia: Int;
  iterations: Int;
  empty_clusters: Int;
  k: Int;
  dims: Int;
  n_points: Int;
  converged: Bool;
}

/// Fitted DBSCAN model.
///
/// `labels` has one entry per point: a cluster id in 0..n_clusters-1, or the
/// noise sentinel -1. `core` holds 0/1 core-point flags (a core point is one
/// whose epsilon-neighborhood -- the point included -- has at least min_pts
/// members). `n_noise` is the number of points labeled -1.
pub type DbscanModel = {
  labels: Vec[Int];
  core: Vec[Int];
  n_clusters: Int;
  n_noise: Int;
  n_points: Int;
}

// ---------------------------------------------------------------------------
// Scale accessor
// ---------------------------------------------------------------------------

/// Fraction digits of point coordinates, centroids and epsilon (3).
pub fn clustering_data_decimals() -> Int {
  return _CLU_DATA_DEC;
}

// ---------------------------------------------------------------------------
// Point sets
// ---------------------------------------------------------------------------

/// Build a point set from flat row-major coordinates.
/// Params: count - number of points (> 0); dims - dimensions per point (> 0);
///         coords - count*dims scaled values, row-major.
/// Returns: Ok(point set) with a private copy of coords.
/// Error case: Err("clustering: ...") when count or dims is not positive,
/// count*dims overflows, or coords.len() != count*dims.
/// Complexity: O(count*dims).
pub fn clustering_point_set_new(count: Int, dims: Int, coords: &Vec[Int]) -> Result[PointSet, Str] {
  if count <= 0 {
    return _err_ps("clustering: count must be positive");
  }
  if dims <= 0 {
    return _err_ps("clustering: dims must be positive");
  }
  if count > _CLU_INT_MAX / dims {
    return _err_ps("clustering: count*dims overflows");
  }
  let want = count * dims;
  if coords.len() != want {
    return _err_ps("clustering: coords length does not match count*dims");
  }
  var copied = Vec[Int].new();
  var i = 0;
  while i < want {
    let v: Int = coords[i];
    copied.push(v);
    i = i + 1;
  }
  return _ok_ps(PointSet{ count: count; dims: dims; coords: copied; });
}

/// Point count. Complexity: O(1).
pub fn clustering_point_set_count(ps: &PointSet) -> Int {
  return ps.count;
}

/// Dimension count. Complexity: O(1).
pub fn clustering_point_set_dims(ps: &PointSet) -> Int {
  return ps.dims;
}

/// Coordinate `(i, j)`, or 0 when an index is out of range.
/// Complexity: O(1).
pub fn clustering_point_set_get(ps: &PointSet, i: Int, j: Int) -> Int {
  if i < 0 {
    return 0;
  }
  if j < 0 {
    return 0;
  }
  if i >= ps.count {
    return 0;
  }
  if j >= ps.dims {
    return 0;
  }
  let idx = i * ps.dims + j;
  if idx >= ps.coords.len() {
    return 0;
  }
  let got: Int = ps.coords[idx];
  return got;
}

/// Copy of the flat row-major coordinates. Complexity: O(count*dims).
pub fn clustering_point_set_coords(ps: &PointSet) -> Vec[Int] {
  return _copy_ints(&ps.coords);
}

/// Validate the internal consistency of a point set value.
/// Returns: Ok(true) when count > 0, dims > 0, count*dims does not overflow
/// and coords.len() == count*dims.
/// Error case: Err("clustering: ...") naming the first inconsistency.
/// Complexity: O(1).
pub fn clustering_point_set_validate(ps: &PointSet) -> Result[Bool, Str] {
  let e = _ps_check(ps);
  if e.len() > 0 {
    return _err_bool(e);
  }
  return _ok_bool(true);
}

// ---------------------------------------------------------------------------
// Squared distances
// ---------------------------------------------------------------------------

/// Exact squared Euclidean distance between points i and j, in raw units of
/// the squared data scale: sum over dimensions of (coord_i - coord_j)^2 with
/// no division and no rounding.
/// Params: ps - consistent point set; i, j - point indices in 0..count-1.
/// Returns: Ok(dist2) with dist2 >= 0.
/// Error case: Err("clustering: ...") for an inconsistent point set or an
/// index out of range.
/// Complexity: O(dims).
pub fn clustering_point_dist2(ps: &PointSet, i: Int, j: Int) -> Result[Int, Str] {
  let e = _ps_check(ps);
  if e.len() > 0 {
    return _err_int(e);
  }
  if i < 0 {
    return _err_int("clustering: point index out of range");
  }
  if j < 0 {
    return _err_int("clustering: point index out of range");
  }
  if i >= ps.count {
    return _err_int("clustering: point index out of range");
  }
  if j >= ps.count {
    return _err_int("clustering: point index out of range");
  }
  return _ok_int(_ps_dist2_at(ps, i, j));
}

// ---------------------------------------------------------------------------
// k-means
// ---------------------------------------------------------------------------

/// Deterministic seeded initialization: farthest-point seeding.
/// Params: ps - consistent point set; k - number of clusters, 1..count.
/// Returns: Ok(k * dims coordinates) starting with point 0, then repeatedly
/// the point whose minimum exact squared distance to the already chosen
/// points is largest (first index wins ties). The seed is deterministic: no
/// clock, no RNG.
/// Error case: Err("clustering: ...") for an inconsistent point set, k < 1 or
/// k > count.
/// Complexity: O(k^2 * count * dims).
pub fn clustering_kmeans_init(ps: &PointSet, k: Int) -> Result[Vec[Int], Str] {
  let e = _ps_check(ps);
  if e.len() > 0 {
    return _err_ints(e);
  }
  if k < 1 {
    return _err_ints("clustering: k must be at least 1");
  }
  if k > ps.count {
    return _err_ints("clustering: k exceeds point count");
  }
  return _ok_ints(_farthest_init(ps, k));
}

/// Run Lloyd k-means with caller-supplied initial centroids.
/// Params: ps - consistent point set; init - exactly k * dims data-scale
///         coordinates of the k initial centroids, row-major (k is derived as
///         init.len() / dims); max_iter - maximum assignment/recompute passes
///         (>= 1).
/// Returns: Ok(KMeansModel). Each pass assigns every point to the nearest
/// centroid (exact squared distance, ties to the lowest centroid index) and
/// recomputes every non-empty centroid as its points' rounded mean; an empty
/// cluster keeps its previous centroid and increments empty_clusters. A pass
/// with unchanged assignments is a fixed point: it is counted, no recompute
/// follows, and converged is true. Inertia is computed after the loop against
/// the final centroids and assignments.
/// Error case: Err("clustering: ...") for an inconsistent point set,
/// max_iter < 1, an init length that is not a positive multiple of dims, or a
/// derived k greater than count.
/// Complexity: O(max_iter * count * k * dims).
pub fn clustering_kmeans_with_init(ps: &PointSet, init: &Vec[Int], max_iter: Int) -> Result[KMeansModel, Str] {
  let e = _ps_check(ps);
  if e.len() > 0 {
    return _err_kmeans(e);
  }
  if max_iter < 1 {
    return _err_kmeans("clustering: max_iter must be at least 1");
  }
  if init.len() < ps.dims {
    return _err_kmeans("clustering: initial centroids length mismatch");
  }
  let rem = init.len() % ps.dims;
  if rem != 0 {
    return _err_kmeans("clustering: initial centroids length mismatch");
  }
  let k = init.len() / ps.dims;
  if k > ps.count {
    return _err_kmeans("clustering: k exceeds point count");
  }
  return _ok_kmeans(_kmeans_run(ps, init, max_iter));
}

/// Fit k-means with the deterministic farthest-point seed.
/// Params: ps - consistent point set; k - number of clusters, 1..count;
///         max_iter - maximum Lloyd passes (>= 1).
/// Returns: Ok(KMeansModel), identical to calling clustering_kmeans_with_init
/// with the centroids from clustering_kmeans_init.
/// Error case: Err("clustering: ...") for an inconsistent point set, k < 1,
/// k > count or max_iter < 1.
/// Complexity: O(count * k * dims * (k + max_iter)).
pub fn clustering_kmeans_fit(ps: &PointSet, k: Int, max_iter: Int) -> Result[KMeansModel, Str] {
  let e = _ps_check(ps);
  if e.len() > 0 {
    return _err_kmeans(e);
  }
  if k < 1 {
    return _err_kmeans("clustering: k must be at least 1");
  }
  if k > ps.count {
    return _err_kmeans("clustering: k exceeds point count");
  }
  if max_iter < 1 {
    return _err_kmeans("clustering: max_iter must be at least 1");
  }
  let init = _farthest_init(ps, k);
  return _ok_kmeans(_kmeans_run(ps, &init, max_iter));
}

/// Cluster count of a fitted model. Complexity: O(1).
pub fn clustering_kmeans_k(m: &KMeansModel) -> Int {
  return m.k;
}

/// Dimension count of a fitted model. Complexity: O(1).
pub fn clustering_kmeans_dims(m: &KMeansModel) -> Int {
  return m.dims;
}

/// Point count of a fitted model. Complexity: O(1).
pub fn clustering_kmeans_n_points(m: &KMeansModel) -> Int {
  return m.n_points;
}

/// Lloyd passes performed (>= 1; the final pass may be the stability check).
/// Complexity: O(1).
pub fn clustering_kmeans_iterations(m: &KMeansModel) -> Int {
  return m.iterations;
}

/// Whether a pass observed unchanged assignments. Complexity: O(1).
pub fn clustering_kmeans_converged(m: &KMeansModel) -> Bool {
  return m.converged;
}

/// Scaled within-cluster sum of squares against the final centroids and
/// assignments: sum over points of floor(dist2 / 1000), truncated toward
/// zero per term (raw = value^2 * 1000). Complexity: O(1).
pub fn clustering_kmeans_inertia(m: &KMeansModel) -> Int {
  return m.inertia;
}

/// Number of empty-cluster events observed during recompute passes: one per
/// cluster that received no points in a pass that recomputed centroids. The
/// affected centroid keeps its previous value. Complexity: O(1).
pub fn clustering_kmeans_empty_clusters(m: &KMeansModel) -> Int {
  return m.empty_clusters;
}

/// Copy of centroid row `c` (dims data-scale entries); empty when `c` is out
/// of range. Complexity: O(dims).
pub fn clustering_kmeans_centroid(m: &KMeansModel, c: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if c < 0 {
    return out;
  }
  if c >= m.k {
    return out;
  }
  let base = c * m.dims;
  var q = 0;
  while q < m.dims {
    let idx = base + q;
    if idx >= m.centroids.len() {
      return out;
    }
    let x: Int = m.centroids[idx];
    out.push(x);
    q = q + 1;
  }
  return out;
}

/// Copy of the flat row-major centroids (k * dims entries).
/// Complexity: O(k * dims).
pub fn clustering_kmeans_centroids(m: &KMeansModel) -> Vec[Int] {
  return _copy_ints(&m.centroids);
}

/// Centroid index assigned to point `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn clustering_kmeans_assignment(m: &KMeansModel, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.assignments.len() {
    return -1;
  }
  let got: Int = m.assignments[i];
  return got;
}

/// Copy of the per-point assignment vector (n_points entries, each in
/// 0..k-1). Complexity: O(n_points).
pub fn clustering_kmeans_assignments(m: &KMeansModel) -> Vec[Int] {
  return _copy_ints(&m.assignments);
}

// ---------------------------------------------------------------------------
// DBSCAN
// ---------------------------------------------------------------------------

/// Epsilon-neighborhood of point `i` by exact linear scan.
/// Params: ps - consistent point set; i - point index; eps - radius in data
///         scale (raw = value * 1000, 0 <= eps <= 1e9).
/// Returns: Ok(ascending point indices j with dist2(i, j) <= eps*eps); the
/// point itself is included (its distance is 0).
/// Error case: Err("clustering: ...") for an inconsistent point set, an index
/// out of range, eps < 0, or eps beyond the supported magnitude.
/// Complexity: O(count * dims).
pub fn clustering_dbscan_neighbors(ps: &PointSet, i: Int, eps: Int) -> Result[Vec[Int], Str] {
  let e = _ps_check(ps);
  if e.len() > 0 {
    return _err_ints(e);
  }
  if eps < 0 {
    return _err_ints("clustering: epsilon must not be negative");
  }
  if eps > _CLU_EPS_MAX {
    return _err_ints("clustering: epsilon exceeds the supported magnitude");
  }
  if i < 0 {
    return _err_ints("clustering: point index out of range");
  }
  if i >= ps.count {
    return _err_ints("clustering: point index out of range");
  }
  return _ok_ints(_neighborhood(ps, i, eps));
}

/// Fit DBSCAN.
/// Params: ps - consistent point set; eps - radius in data scale
///         (0 <= eps <= 1e9); min_pts - minimum neighborhood size for a core
///         point, counting the point itself (>= 1).
/// Returns: Ok(DbscanModel). Points are scanned in index order; every
/// unvisited point opens a neighborhood query, and a core point starts a new
/// cluster expanded with a FIFO queue: each queued point is visited once,
/// core points enqueue their unvisited neighbors, and every point reached
/// with a negative label is claimed by the current cluster. Labels are
/// cluster ids 0..n_clusters-1 in first-core order, or the noise sentinel -1.
/// Error case: Err("clustering: ...") for an inconsistent point set,
/// eps < 0, eps beyond the supported magnitude, or min_pts < 1.
/// Complexity: O(count^2 * dims) worst case (linear-scan neighborhoods).
pub fn clustering_dbscan_fit(ps: &PointSet, eps: Int, min_pts: Int) -> Result[DbscanModel, Str] {
  let e = _ps_check(ps);
  if e.len() > 0 {
    return _err_dbscan(e);
  }
  if eps < 0 {
    return _err_dbscan("clustering: epsilon must not be negative");
  }
  if eps > _CLU_EPS_MAX {
    return _err_dbscan("clustering: epsilon exceeds the supported magnitude");
  }
  if min_pts < 1 {
    return _err_dbscan("clustering: min_pts must be at least 1");
  }
  return _ok_dbscan(_dbscan_run(ps, eps, min_pts));
}

/// Number of clusters found. Complexity: O(1).
pub fn clustering_dbscan_n_clusters(m: &DbscanModel) -> Int {
  return m.n_clusters;
}

/// Number of points labeled noise (-1). Complexity: O(1).
pub fn clustering_dbscan_n_noise(m: &DbscanModel) -> Int {
  return m.n_noise;
}

/// Point count the model was fitted on. Complexity: O(1).
pub fn clustering_dbscan_n_points(m: &DbscanModel) -> Int {
  return m.n_points;
}

/// Label of point `i` (cluster id >= 0, or the noise sentinel -1), or -1 when
/// `i` is out of range. Complexity: O(1).
pub fn clustering_dbscan_label(m: &DbscanModel, i: Int) -> Int {
  if i < 0 {
    return _CLU_NOISE;
  }
  if i >= m.labels.len() {
    return _CLU_NOISE;
  }
  let got: Int = m.labels[i];
  return got;
}

/// Copy of the per-point labels (n_points entries, -1 or a cluster id).
/// Complexity: O(n_points).
pub fn clustering_dbscan_labels(m: &DbscanModel) -> Vec[Int] {
  return _copy_ints(&m.labels);
}

/// Whether point `i` is a core point (neighborhood size >= min_pts), or false
/// when `i` is out of range. Complexity: O(1).
pub fn clustering_dbscan_is_core(m: &DbscanModel, i: Int) -> Bool {
  if i < 0 {
    return false;
  }
  if i >= m.core.len() {
    return false;
  }
  let got: Int = m.core[i];
  return got == 1;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Consistency check used by every operation: "" when the point set is usable,
// otherwise the error message (Str equality is never used; callers test len).
fn _ps_check(ps: &PointSet) -> Str {
  if ps.count <= 0 {
    return "clustering: point set has no points";
  }
  if ps.dims <= 0 {
    return "clustering: point set has no dimensions";
  }
  if ps.count > _CLU_INT_MAX / ps.dims {
    return "clustering: count*dims overflows";
  }
  let want = ps.count * ps.dims;
  if ps.coords.len() != want {
    return "clustering: point set coords length mismatch";
  }
  return "";
}

// Truncating division helper: a / b with halves rounded away from zero.
// b > 0; a and b are small enough that 2*|a % b| cannot overflow.
fn _div_round(a: Int, b: Int) -> Int {
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

fn _copy_ints(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    out.push(x);
    i = i + 1;
  }
  return out;
}

fn _fill(n: Int, value: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    out.push(value);
    i = i + 1;
  }
  return out;
}

// 1 when x occurs in v, else 0.
fn _contains_int(v: &Vec[Int], x: Int) -> Int {
  var found: Int = 0;
  var i = 0;
  while i < v.len() {
    let y: Int = v[i];
    if y == x {
      found = 1;
      break;
    }
    i = i + 1;
  }
  return found;
}

// Exact squared distance between point i and a coordinate row starting at
// `base` in `row` (row has at least base + dims entries by construction).
fn _dist2_row(ps: &PointSet, i: Int, row: &Vec[Int], base: Int) -> Int {
  var s: Int = 0;
  var q = 0;
  while q < ps.dims {
    let a: Int = ps.coords[i * ps.dims + q];
    let b: Int = row[base + q];
    let delta = a - b;
    s = s + delta * delta;
    q = q + 1;
  }
  return s;
}

// Exact squared distance between points i and j (validated by callers).
fn _ps_dist2_at(ps: &PointSet, i: Int, j: Int) -> Int {
  let base = j * ps.dims;
  return _dist2_row(ps, i, &ps.coords, base);
}

// Farthest-point seeding, k validated to 1..count by the caller.
fn _farthest_init(ps: &PointSet, k: Int) -> Vec[Int] {
  var cents = Vec[Int].new();
  var chosen = Vec[Int].new();
  var d = 0;
  while d < ps.dims {
    let x: Int = ps.coords[d];
    cents.push(x);
    d = d + 1;
  }
  chosen.push(0);
  while chosen.len() < k {
    var best_i: Int = -1;
    var best_d: Int = -1;
    var i = 0;
    while i < ps.count {
      if _contains_int(&chosen, i) == 0 {
        let dm = _min_dist_to_chosen(ps, &chosen, i);
        if dm > best_d {
          best_d = dm;
          best_i = i;
        }
      }
      i = i + 1;
    }
    if best_i < 0 {
      break;
    }
    chosen.push(best_i);
    var q = 0;
    while q < ps.dims {
      let x: Int = ps.coords[best_i * ps.dims + q];
      cents.push(x);
      q = q + 1;
    }
  }
  return cents;
}

// Minimum exact squared distance from point i to the chosen points.
fn _min_dist_to_chosen(ps: &PointSet, chosen: &Vec[Int], i: Int) -> Int {
  var best: Int = -1;
  var t = 0;
  while t < chosen.len() {
    let c: Int = chosen[t];
    let d2 = _ps_dist2_at(ps, i, c);
    if best < 0 {
      best = d2;
    } else {
      if d2 < best {
        best = d2;
      }
    }
    t = t + 1;
  }
  return best;
}

// Lloyd iterations, validated by the callers.
fn _kmeans_run(ps: &PointSet, init: &Vec[Int], max_iter: Int) -> KMeansModel {
  let md = ps.dims;
  let n = ps.count;
  let k = init.len() / md;
  var cents = _copy_ints(init);
  var asg = _fill(n, -1);
  var iters: Int = 0;
  var empty_events: Int = 0;
  var converged = false;
  while iters < max_iter {
    iters = iters + 1;
    var sums = _fill(k * md, 0);
    var counts = _fill(k, 0);
    var changed = false;
    var i = 0;
    while i < n {
      var best: Int = -1;
      var best_d: Int = 0;
      var c = 0;
      while c < k {
        let d = _dist2_row(ps, i, &cents, c * md);
        if best < 0 {
          best = c;
          best_d = d;
        } else {
          if d < best_d {
            best = c;
            best_d = d;
          }
        }
        c = c + 1;
      }
      let prev: Int = asg[i];
      if prev != best {
        changed = true;
      }
      asg[i] = best;
      counts[best] = counts[best] + 1;
      var q = 0;
      while q < md {
        let x: Int = ps.coords[i * md + q];
        sums[best * md + q] = sums[best * md + q] + x;
        q = q + 1;
      }
      i = i + 1;
    }
    if !changed {
      converged = true;
      break;
    }
    var c2 = 0;
    while c2 < k {
      let cnt: Int = counts[c2];
      if cnt == 0 {
        empty_events = empty_events + 1;
      } else {
        var q2 = 0;
        while q2 < md {
          let s: Int = sums[c2 * md + q2];
          cents[c2 * md + q2] = _div_round(s, cnt);
          q2 = q2 + 1;
        }
      }
      c2 = c2 + 1;
    }
  }
  var inertia: Int = 0;
  var p = 0;
  while p < n {
    let cnum: Int = asg[p];
    let d2 = _dist2_row(ps, p, &cents, cnum * md);
    inertia = inertia + d2 / _CLU_DATA_ONE;
    p = p + 1;
  }
  return KMeansModel{ centroids: cents; assignments: asg; inertia: inertia; iterations: iters; empty_clusters: empty_events; k: k; dims: md; n_points: n; converged: converged; };
}

// Neighbors of point i within eps (validated by callers); ascending indices,
// i itself included.
fn _neighborhood(ps: &PointSet, i: Int, eps: Int) -> Vec[Int] {
  let eps2 = eps * eps;
  var out = Vec[Int].new();
  var j = 0;
  while j < ps.count {
    let d2 = _ps_dist2_at(ps, i, j);
    if d2 <= eps2 {
      out.push(j);
    }
    j = j + 1;
  }
  return out;
}

// DBSCAN scan and queue expansion, validated by the caller.
fn _dbscan_run(ps: &PointSet, eps: Int, min_pts: Int) -> DbscanModel {
  let n = ps.count;
  var labels = _fill(n, _CLU_NOISE);
  var core = _fill(n, 0);
  var visited = _fill(n, 0);
  var queued = _fill(n, 0);
  var clusters: Int = 0;
  var i = 0;
  while i < n {
    let seen: Int = visited[i];
    if seen == 0 {
      visited[i] = 1;
      let nb = _neighborhood(ps, i, eps);
      if nb.len() >= min_pts {
        core[i] = 1;
        labels[i] = clusters;
        var queue = Vec[Int].new();
        var t = 0;
        while t < nb.len() {
          let p: Int = nb[t];
          if queued[p] == 0 {
            queued[p] = 1;
            queue.push(p);
          }
          t = t + 1;
        }
        var head = 0;
        while head < queue.len() {
          let j: Int = queue[head];
          head = head + 1;
          let jseen: Int = visited[j];
          if jseen == 0 {
            visited[j] = 1;
            let nb2 = _neighborhood(ps, j, eps);
            if nb2.len() >= min_pts {
              core[j] = 1;
              var u = 0;
              while u < nb2.len() {
                let p2: Int = nb2[u];
                let p2seen: Int = visited[p2];
                if p2seen == 0 {
                  let p2queued: Int = queued[p2];
                  if p2queued == 0 {
                    queued[p2] = 1;
                    queue.push(p2);
                  }
                }
                u = u + 1;
              }
            }
          }
          let lab: Int = labels[j];
          if lab < 0 {
            labels[j] = clusters;
          }
        }
        clusters = clusters + 1;
      }
    }
    i = i + 1;
  }
  var noise: Int = 0;
  var k = 0;
  while k < n {
    let lab2: Int = labels[k];
    if lab2 < 0 {
      noise = noise + 1;
    }
    k = k + 1;
  }
  return DbscanModel{ labels: labels; core: core; n_clusters: clusters; n_noise: noise; n_points: n; };
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_ps(p: PointSet) -> Result[PointSet, Str] {
  return Ok(p);
}

fn _err_ps(msg: Str) -> Result[PointSet, Str] {
  return Err(msg);
}

fn _ok_bool(b: Bool) -> Result[Bool, Str] {
  return Ok(b);
}

fn _err_bool(msg: Str) -> Result[Bool, Str] {
  return Err(msg);
}

fn _ok_int(x: Int) -> Result[Int, Str] {
  return Ok(x);
}

fn _err_int(msg: Str) -> Result[Int, Str] {
  return Err(msg);
}

fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

fn _err_ints(msg: Str) -> Result[Vec[Int], Str] {
  return Err(msg);
}

fn _ok_kmeans(m: KMeansModel) -> Result[KMeansModel, Str] {
  return Ok(m);
}

fn _err_kmeans(msg: Str) -> Result[KMeansModel, Str] {
  return Err(msg);
}

fn _ok_dbscan(m: DbscanModel) -> Result[DbscanModel, Str] {
  return Ok(m);
}

fn _err_dbscan(msg: Str) -> Result[DbscanModel, Str] {
  return Err(msg);
}
