# xiom.clustering

> **Status:** `incubating` -- conformance-tested (22/22); published at `v0.1.0` on the XIOM registry.
> **Scope:** fixed-point clustering primitives (k-means and DBSCAN) on scaled
> integers.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.string` and
> `xiom.convert`; tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`).

## What it is

`xiom.clustering` clusters points **without floating point**. Every real
number is carried as a 64-bit scaled integer (raw value / 10^decimals), so
results are deterministic and reproducible across machines. The module covers
two classical algorithms in miniature:

- **k-means** (Lloyd): caller-supplied initial centroids or a deterministic
  farthest-point seed, exact integer squared-distance assignment, rounded
  centroid recompute, assignment-stability convergence, a documented
  empty-cluster policy and a scaled inertia output;
- **DBSCAN**: epsilon in scaled units, `min_pts` core threshold, exact linear
  scan neighborhoods and FIFO queue-based cluster expansion, with cluster
  labels and the noise sentinel `-1`.

Point sets are dense row-major `Vec[Int]` buffers with parallel `count` and
`dims` fields. There is no `Float64`, no FFI, no I/O and no global state. See
`SPEC.md` for the exact scaling, rounding, tie-breaking and overflow rules.

## Scales

| Quantity | Fraction digits | Raw representation |
|---|---|---|
| Point coordinates, centroids, epsilon | 3 | `value * 1000` |
| Squared distances (exact, no division) | -- | `value^2 * 1000000` |
| Inertia | 3 of the squared value | sum of `dist2 / 1000` (truncated per point) |

Centroids are rounded half away from zero. Assignment and epsilon comparisons
use exact integer arithmetic; ties go to the lowest centroid index, so every
result is deterministic.

## API

| Function | Returns | Description |
|---|---|---|
| `clustering_data_decimals()` | `Int` | Coordinate/centroid/epsilon scale (3). |
| `clustering_point_set_new(count, dims, &coords)` | `Result[PointSet, Str]` | Dense point set; copies `coords`; validates shape. |
| `clustering_point_set_count(ps)` / `clustering_point_set_dims(ps)` | `Int` | Shape accessors. |
| `clustering_point_set_get(ps, i, j)` | `Int` | Coordinate, or 0 when out of range. |
| `clustering_point_set_coords(ps)` | `Vec[Int]` | Copy of the flat row-major coordinates. |
| `clustering_point_set_validate(ps)` | `Result[Bool, Str]` | Internal-consistency check. |
| `clustering_point_dist2(ps, i, j)` | `Result[Int, Str]` | Exact squared distance (no division). |
| `clustering_kmeans_init(ps, k)` | `Result[Vec[Int], Str]` | Deterministic farthest-point seed (`k * dims` coordinates). |
| `clustering_kmeans_with_init(ps, &init, max_iter)` | `Result[KMeansModel, Str]` | Lloyd run from caller-supplied centroids. |
| `clustering_kmeans_fit(ps, k, max_iter)` | `Result[KMeansModel, Str]` | Lloyd run from the farthest-point seed. |
| `clustering_kmeans_k(m)` / `_dims(m)` / `_n_points(m)` | `Int` | Model shape. |
| `clustering_kmeans_iterations(m)` | `Int` | Lloyd passes performed (>= 1). |
| `clustering_kmeans_converged(m)` | `Bool` | A pass observed unchanged assignments. |
| `clustering_kmeans_inertia(m)` | `Int` | Scaled within-cluster sum of squares. |
| `clustering_kmeans_empty_clusters(m)` | `Int` | Empty-cluster warning count. |
| `clustering_kmeans_centroid(m, c)` | `Vec[Int]` | Copy of one centroid row; empty out of range. |
| `clustering_kmeans_centroids(m)` | `Vec[Int]` | Copy of all centroid rows (row-major). |
| `clustering_kmeans_assignment(m, i)` | `Int` | Centroid index of point `i`, or -1 out of range. |
| `clustering_kmeans_assignments(m)` | `Vec[Int]` | Copy of all assignments. |
| `clustering_dbscan_neighbors(ps, i, eps)` | `Result[Vec[Int], Str]` | Ascending neighbor indices (point included). |
| `clustering_dbscan_fit(ps, eps, min_pts)` | `Result[DbscanModel, Str]` | Full DBSCAN run. |
| `clustering_dbscan_n_clusters(m)` / `_n_noise(m)` / `_n_points(m)` | `Int` | Label metadata. |
| `clustering_dbscan_label(m, i)` | `Int` | Label of point `i`, or -1 (noise/out of range). |
| `clustering_dbscan_labels(m)` | `Vec[Int]` | Copy of all labels. |
| `clustering_dbscan_is_core(m, i)` | `Bool` | Core-point flag (false out of range). |

The complete error catalog is in `SPEC.md`.

## Usage

```xi
use xiom.clustering;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // Two dimensions, values in thousandths: 1.000 is raw 1000.
  var coords = Vec[Int].new();
  coords.push(0); coords.push(0);
  coords.push(1000); coords.push(0);
  coords.push(9000); coords.push(0);
  coords.push(10000); coords.push(0);
  match clustering_point_set_new(4, 2, &coords) {
    Ok(ps) => {
      match clustering_kmeans_fit(&ps, 2, 10) {
        Ok(model) => {
          io.println(convert.int_to_string(clustering_kmeans_inertia(&model)));   // 1000
          io.println(convert.int_to_string(clustering_kmeans_iterations(&model))); // 2
        },
        Err(e) => { io.println(e); },
      },
      match clustering_dbscan_fit(&ps, 1500, 3) {
        Ok(db) => {
          io.println(convert.int_to_string(clustering_dbscan_n_clusters(&db))); // 2
          io.println(convert.int_to_string(clustering_dbscan_n_noise(&db)));    // 0
        },
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.clustering
```

Expected tail: 22 `[PASS]` lines, `xiom.clustering: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`. Verified with the
pinned compiler 0.62.1.

## Limitations

- **Fixed scale, fixed envelope:** coordinates/centroids/epsilon use 3
  fraction digits. The safe envelope is `|coordinate value| <= 1000`,
  `dims <= 32`, `count <= 100000` and `|eps raw| <= 1e9`; outside it,
  intermediate `Int` products can silently overflow (see `SPEC.md` for the
  arithmetic bounds). There is no dynamic rescaling and no overflow detection.
- **k-means is spherical and local:** squared Euclidean distance only, a
  single run from one deterministic seed (no k-means++ sampling, no restarts),
  and no automatic `k` selection. `kmeans_with_init` lets the caller supply a
  better seed.
- **Empty-cluster policy:** an empty cluster keeps its previous centroid and
  is counted; it is never reseeded. A cluster can revive later, and a
  permanently empty cluster stays where it was.
- **Inertia rounding:** each per-point squared distance is truncated by
  `/1000` before summing, so inertia is exact up to one unit of the scaled
  term per point.
- **DBSCAN is O(n^2):** neighborhoods use a linear scan (no grid/kd-tree) and
  border points within epsilon of several clusters join the first cluster that
  reaches them in scan order.
- **Out of scope:** Gaussian mixtures/EM, hierarchical/agglomerative
  clustering, silhouette and cluster-validity metrics, fuzzy and spectral
  clustering, streaming/mini-batch variants, weighted or categorical points,
  spatial indexes.
- Not thread-safe; the types are plain values with no internal locking.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
