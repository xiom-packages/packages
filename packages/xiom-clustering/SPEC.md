# xiom.clustering -- Specification

Status: `incubating` (implemented, harness-green on compiler 0.62.1, not
published).
Module: `xiom.clustering` (`src/clustering.xi`). Manifest: `package.xi` (name
`xiom.clustering`, version `0.1.0`). Depends on `xiom.std` for the manifest;
the library imports `xiom.string` and `xiom.convert` and uses no other module.

## Scope

Fixed-point clustering primitives over scalar `Int` arithmetic:

- dense point sets (`PointSet`) with parallel `count` / `dims` / `coords`
  fields and explicit data scale 3;
- exact squared Euclidean distances (no division, no rounding);
- k-means (Lloyd) with caller-supplied initial centroids or a deterministic
  farthest-point seed, assignment-stability convergence, a keep-previous
  empty-cluster policy with a warning count, and a scaled inertia output;
- DBSCAN with epsilon in scaled units, `min_pts` core threshold, exact
  linear-scan neighborhoods and FIFO queue expansion, exposing labels,
  core flags and cluster/noise counts.

Pure and deterministic: no floats, no FFI, no I/O, no clock access, no RNG,
no global state, no allocation beyond the vectors involved.

## Non-goals

- Gaussian mixture models / EM, hierarchical or agglomerative clustering,
  spectral or fuzzy clustering;
- silhouette scores and cluster-validity metrics;
- approximate nearest-neighbor structures (grid, kd-tree, LSH) -- DBSCAN
  neighborhoods are exact linear scans;
- streaming/mini-batch variants, weighted points, categorical data, missing
  values;
- automatic `k` / `eps` / `min_pts` selection, restarts or ensembling;
- overflow detection or dynamic rescaling.

## Scaled arithmetic rules

A raw integer `r` with `d` fraction digits denotes `r / 10^d`.

| Quantity | `d` | Notes |
|---|---|---|
| coordinates, centroids, epsilon | 3 | caller supplies raw `value * 1000` |
| squared distances | -- | exact sum of squared raw differences, no division |
| inertia | 3 (of the squared value) | per-point `dist2 / 1000`, truncated per term |

Division (`/`) in XIOM v0.62.1 truncates toward zero; every rounding step is
implemented explicitly:

- **Squared distance**: `dist2(i, j) = sum_j (coord_i - coord_j)^2`, exact
  integer arithmetic, never negative.
- **Epsilon comparison**: neighbor iff `dist2 <= eps * eps`, both exact; the
  boundary is inclusive (`dist2 == eps^2` is a neighbor).
- **Assignment**: nearest centroid by exact squared distance; on a tie the
  lowest centroid index wins (`d < best_d` is strict, so the first candidate
  is kept on equality).
- **Centroid recompute**: `_div_round(sum, count)` rounds half away from
  zero and is exact on the data scale.
- **Inertia**: after the loop, `inertia = sum_i (dist2(i, assignment[i]) /
  1000)`, each term truncated toward zero before accumulation.
- **No sign-bit tests and no bitfield tricks**: all arithmetic is
  multiplication, addition, division and modulo.

### Safe magnitude envelope

The implementation does not detect overflow; the caller must stay inside the
envelope below (`Int` max `2^63 - 1 ~ 9.22e18`):

| Constraint | Bound | Worst intermediate |
|---|---|---|
| `|coordinate raw|` | `<= 1e6` (value 1000) | difference `<= 2e6` |
| dims | `<= 32` | dist2 `<= 32 * 4e12 = 1.28e14` |
| count | `<= 100000` | centroid sum `<= 1e5 * 1e6 = 1e11` |
| `|eps raw|` | `<= 1e9` | `eps * eps <= 1e18` |
| derived | -- | inertia `<= 1e5 * 1.28e11 = 1.28e16` |

## Representation

`PointSet` is row-major: `coords[i * dims + j]`; `count` and `dims` are
positive for any set produced by `clustering_point_set_new`. `KMeansModel`
keeps parallel vectors: `centroids` (`k` rows of `dims` data-scale entries,
row-major), `assignments` (one index `0..k-1` per point), plus `inertia`,
`iterations`, `empty_clusters`, `k`, `dims`, `n_points` and `converged`.
`DbscanModel` keeps `labels` (one entry per point: a cluster id `>= 0` or the
noise sentinel `-1`), `core` (`0`/`1` core flags), `n_clusters`, `n_noise`
and `n_points`. All struct fields are public but internal implementation
detail; use the accessors.

## k-means semantics

### Seeding (`clustering_kmeans_init`, used by `clustering_kmeans_fit`)

1. Validate `1 <= k <= count`.
2. Centroid 0 is point 0.
3. While fewer than `k` centroids are chosen: pick the unselected point whose
   minimum exact squared distance to the chosen points is largest; ties go to
   the lowest point index. The seed is fully deterministic (no RNG, no clock).

### Lloyd loop (`clustering_kmeans_with_init`, `clustering_kmeans_fit`)

Let `k = init.len() / dims` and `n = count`. Repeat while
`iterations < max_iter`:

1. `iterations += 1`.
2. Assign every point to the nearest centroid by exact squared distance
   (ties to lowest index); accumulate per-cluster coordinate sums and counts;
   record whether any assignment changed relative to the previous pass.
3. If no assignment changed, the state is a fixed point: set
   `converged = true` and stop (no recompute -- recomputing would reproduce
   the same centroids). The first pass can never be stable because
   assignments start at the sentinel `-1`.
4. Otherwise recompute every non-empty centroid as `_div_round(sum, count)`
   (half away from zero) and continue.

After the loop, `inertia` is computed against the final centroids and final
assignments (also when `max_iter` was exhausted without convergence).

- **Empty-cluster policy**: if a cluster receives no points in a recompute
  pass, its previous centroid is kept unchanged (never reseeded) and
  `empty_clusters` is incremented once for that cluster and pass. A cluster
  that later receives points is recomputed normally.
- `iterations` counts full assignment/recompute passes, including the
  stability-check pass; `iterations >= 1` for any successful fit and
  `iterations <= max_iter`.
- `converged` is true exactly when a pass observed unchanged assignments.
- Assignment and centroid accessors echo the final state; with `max_iter = 1`
  the assignments refer to the initial centroids while the centroids were
  recomputed once, and `converged` is false.

## DBSCAN semantics

Parameters: `eps` (data scale 3, `0 <= eps <= 1e9`) and `min_pts` (`>= 1`).

1. The epsilon-neighborhood of point `i` is the ascending list of points `j`
   with `dist2(i, j) <= eps * eps`; `i` itself is always a member (distance
   0), so `min_pts` includes the point itself.
2. A point is a **core point** iff its neighborhood has at least `min_pts`
   members. `min_pts = 1` makes every point core.
3. Points are scanned in index order. An unvisited point is visited and its
   neighborhood is computed; a non-core point is left with the default label
   `-1` (noise) for now (it can still be claimed later as a border point).
4. A core point opens a new cluster `c` (ids issued in first-core scan
   order). Its neighbors are enqueued in ascending index order and the
   cluster is expanded with an explicit FIFO queue: each queued point is
   processed once, core points enqueue their unvisited, not-yet-queued
   neighbors, and every processed point with a negative label is set to `c`.
   Each point enters the queue at most once, so memory is O(count).
5. After the scan, `labels` holds cluster ids `0..n_clusters-1` or the noise
   sentinel `-1`; `n_noise` counts the `-1` entries; `core` holds the flags.

- A **border point** is a non-core point inside the neighborhood of a core
  point; it joins the first cluster that reaches it in scan/queue order.
- `clustering_dbscan_label` returns `-1` both for noise and for an
  out-of-range index; use `clustering_dbscan_n_points` to distinguish.
- The scan is deterministic; no RNG, no hashing.

## API signatures

```xi
pub type PointSet = { count: Int; dims: Int; coords: Vec[Int]; }
pub type KMeansModel = {
  centroids: Vec[Int]; assignments: Vec[Int]; inertia: Int; iterations: Int;
  empty_clusters: Int; k: Int; dims: Int; n_points: Int; converged: Bool;
}
pub type DbscanModel = {
  labels: Vec[Int]; core: Vec[Int]; n_clusters: Int; n_noise: Int;
  n_points: Int;
}

pub fn clustering_data_decimals() -> Int
pub fn clustering_point_set_new(count: Int, dims: Int, coords: &Vec[Int]) -> Result[PointSet, Str]
pub fn clustering_point_set_count(ps: &PointSet) -> Int
pub fn clustering_point_set_dims(ps: &PointSet) -> Int
pub fn clustering_point_set_get(ps: &PointSet, i: Int, j: Int) -> Int
pub fn clustering_point_set_coords(ps: &PointSet) -> Vec[Int]
pub fn clustering_point_set_validate(ps: &PointSet) -> Result[Bool, Str]
pub fn clustering_point_dist2(ps: &PointSet, i: Int, j: Int) -> Result[Int, Str]
pub fn clustering_kmeans_init(ps: &PointSet, k: Int) -> Result[Vec[Int], Str]
pub fn clustering_kmeans_with_init(ps: &PointSet, init: &Vec[Int], max_iter: Int) -> Result[KMeansModel, Str]
pub fn clustering_kmeans_fit(ps: &PointSet, k: Int, max_iter: Int) -> Result[KMeansModel, Str]
pub fn clustering_kmeans_k(m: &KMeansModel) -> Int
pub fn clustering_kmeans_dims(m: &KMeansModel) -> Int
pub fn clustering_kmeans_n_points(m: &KMeansModel) -> Int
pub fn clustering_kmeans_iterations(m: &KMeansModel) -> Int
pub fn clustering_kmeans_converged(m: &KMeansModel) -> Bool
pub fn clustering_kmeans_inertia(m: &KMeansModel) -> Int
pub fn clustering_kmeans_empty_clusters(m: &KMeansModel) -> Int
pub fn clustering_kmeans_centroid(m: &KMeansModel, c: Int) -> Vec[Int]
pub fn clustering_kmeans_centroids(m: &KMeansModel) -> Vec[Int]
pub fn clustering_kmeans_assignment(m: &KMeansModel, i: Int) -> Int
pub fn clustering_kmeans_assignments(m: &KMeansModel) -> Vec[Int]
pub fn clustering_dbscan_neighbors(ps: &PointSet, i: Int, eps: Int) -> Result[Vec[Int], Str]
pub fn clustering_dbscan_fit(ps: &PointSet, eps: Int, min_pts: Int) -> Result[DbscanModel, Str]
pub fn clustering_dbscan_n_clusters(m: &DbscanModel) -> Int
pub fn clustering_dbscan_n_noise(m: &DbscanModel) -> Int
pub fn clustering_dbscan_n_points(m: &DbscanModel) -> Int
pub fn clustering_dbscan_label(m: &DbscanModel, i: Int) -> Int
pub fn clustering_dbscan_labels(m: &DbscanModel) -> Vec[Int]
pub fn clustering_dbscan_is_core(m: &DbscanModel, i: Int) -> Bool
```

## Error catalog

Every `Err` payload has the exact prefix `clustering: `. The point-set
consistency check runs first in every operation and reports one of the three
"point set" messages.

| Message | Raised by | Condition |
|---|---|---|
| `clustering: count must be positive` | `clustering_point_set_new` | `count <= 0` |
| `clustering: dims must be positive` | `clustering_point_set_new` | `dims <= 0` |
| `clustering: count*dims overflows` | `clustering_point_set_new` | `count > Int::MAX / dims` |
| `clustering: coords length does not match count*dims` | `clustering_point_set_new` | length mismatch |
| `clustering: point set has no points` | all operations via the consistency check | `count <= 0` |
| `clustering: point set has no dimensions` | all operations via the consistency check | `dims <= 0` |
| `clustering: point set coords length mismatch` | all operations via the consistency check | `coords.len() != count*dims` |
| `clustering: point index out of range` | `clustering_point_dist2`, `clustering_dbscan_neighbors` | index `< 0` or `>= count` |
| `clustering: k must be at least 1` | `clustering_kmeans_init`, `clustering_kmeans_fit` | `k < 1` |
| `clustering: k exceeds point count` | `clustering_kmeans_init`, `clustering_kmeans_fit`, `clustering_kmeans_with_init` | `k > count` (derived `k` for with_init) |
| `clustering: max_iter must be at least 1` | `clustering_kmeans_with_init`, `clustering_kmeans_fit` | `max_iter < 1` |
| `clustering: initial centroids length mismatch` | `clustering_kmeans_with_init` | `init.len() < dims` or `init.len() % dims != 0` |
| `clustering: epsilon must not be negative` | `clustering_dbscan_neighbors`, `clustering_dbscan_fit` | `eps < 0` |
| `clustering: epsilon exceeds the supported magnitude` | `clustering_dbscan_neighbors`, `clustering_dbscan_fit` | `eps > 1000000000` |
| `clustering: min_pts must be at least 1` | `clustering_dbscan_fit` | `min_pts < 1` |

Validation order: `kmeans_with_init` checks the point set, then `max_iter`,
then the init shape, then `k`. `kmeans_fit` checks the point set, then `k`,
then `max_iter`.

Accessors never fail: `clustering_point_set_get`, `clustering_kmeans_k`,
`clustering_kmeans_dims`, `clustering_kmeans_n_points`,
`clustering_kmeans_iterations`, `clustering_kmeans_inertia`,
`clustering_kmeans_empty_clusters` and `clustering_dbscan_n_*` return stored
values; `clustering_kmeans_assignment` and `clustering_dbscan_label` return
`-1` out of range; `clustering_kmeans_centroid` returns an empty vector and
`clustering_dbscan_is_core` returns `false` out of range.

## Complexity

| Operation | Complexity |
|---|---|
| `point_set_new` / `point_set_coords` | O(count*dims) |
| `point_set_count` / `_dims` / `_get` / `_validate` | O(1) |
| `point_dist2` | O(dims) |
| `kmeans_init` | O(k^2 * count * dims) |
| `kmeans_with_init` | O(max_iter * count * k * dims) |
| `kmeans_fit` | O(count * k * dims * (k + max_iter)) |
| k-means accessors | O(1); centroid O(dims); centroids O(k*dims); assignments O(count) |
| `dbscan_neighbors` | O(count * dims) |
| `dbscan_fit` | O(count^2 * dims) worst case (linear-scan neighborhoods) |

## Test plan

`tests/test_conformance.xi` (`module clustering_tests`, 22 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count). Fixtures are built in-test (no files, no
I/O), all values are data-scale raw integers:

1. scale accessor is 3; `point_set_new` shape and coordinate-copy semantics;
2. `point_set_new` rejects bad dimensions and lengths;
3. `point_set_validate` accepts consistent sets and names inconsistencies;
4. point-set accessors are range-safe and `coords` copies the data;
5. `point_dist2` is exact (3-4-5 triangle at scale 1e9) and validates indices;
6. `kmeans_init` is deterministic farthest-point seeding with lowest-index
   ties (k = 2 and k = 3 on a line);
7. `kmeans_init` validates `k` and the point set;
8. `kmeans_with_init` converges to the exact two-cluster solution
   (assignments, centroids, iterations = 2, inertia = 4000);
9. `kmeans_fit` with the seeded init matches the caller-init run;
10. single-cluster data collapses to the exact mean (inertia = 4000);
11. inertia matches hand-computed scaled values (1000 and 82000);
12. empty clusters keep their previous centroid and are counted (a duplicate
    seed keeps (7000, 0) and reports one warning);
13. convergence is assignment stability within `max_iter` (1 pass not
    converged, 2 passes converged);
14. k-means accessors are range-safe;
15. k-means validates init shape, `k` and `max_iter`;
16. DBSCAN classic example (two clusters, one border, two noise points,
    exact labels and core flags);
17. DBSCAN epsilon edges: zero radius with `min_pts` 1 and 2, and exact
    boundary `dist2 == eps^2`;
18. `dbscan_neighbors` returns the exact linear-scan neighborhood;
19. DBSCAN validates epsilon, `min_pts` and the point set;
20. DBSCAN accessors are range-safe;
21. every operation validates the point set it is given;
22. seeded init partitions the symmetric blob deterministically
    (rounded centroid 2000/3 -> 667, inertia 2664).

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.clustering
```

Last verified: compiler 0.62.1,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)` (run twice).

## Known limitations

- Fixed data scale (3) and the envelope in "Safe magnitude envelope"; no
  overflow detection, no dynamic rescaling.
- k-means uses one deterministic seed (farthest point) unless the caller
  supplies centroids; no k-means++ sampling, no restarts, no `k` selection.
- The empty-cluster policy is keep-previous (never reseed), so a permanently
  empty cluster remains at its seed position.
- Inertia truncates each per-point term by `/1000` before summing.
- DBSCAN uses exact linear scans (O(n^2)); border points join the first
  cluster that reaches them in scan order.
- No approximate nearest neighbors, no cluster validity metrics, no GMM or
  hierarchical clustering.
- Not thread-safe; no global state.

## Compiler notes (pinned v0.62.1)

- Free functions only; explicit `&`/`&mut`; no methods.
- `Ok`/`Err` are constructed only in the leaf helpers `_ok_ps`/`_err_ps`,
  `_ok_bool`/`_err_bool`, `_ok_int`/`_err_int`, `_ok_ints`/`_err_ints`,
  `_ok_kmeans`/`_err_kmeans`, `_ok_dbscan`/`_err_dbscan` (the documented
  v0.62.1 code-shape hazard).
- Str equality in the tests goes through
  `xiom.string.compare.str_compare`, never `==`.
- All Vec element reads go through typed `let`; all point sets and vectors
  use canonical `Vec[Int]` / `Result[T, Str]` brackets; no `Vec[Float64]`
  anywhere.
- No sign-bit tests or bitfield tricks: the module uses addition,
  multiplication, truncating division and modulo only.
