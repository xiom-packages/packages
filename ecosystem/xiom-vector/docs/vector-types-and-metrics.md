# Vector Types and Metrics

Covers the value types in `types/` and the distance math in `types/metric.xi`
and `distance/`.

## The dense vector

```
Vector { data: Vec[Float32]; dimension: UInt }
```

- Constructed zero-filled with `Vector.new(dimension)` (`requires: dimension > 0`).
- `Vector.set(i, v)` / `Vector.get(i)` are bounds-checked by contract
  (`requires: index < dimension`).
- `dimension` is fixed for the vector's life; every binary operation requires
  matching dimensions (`requires: a.dimension == b.dimension`).

### Vector math (`dense_vector.xi`)

| Function | Result |
|----------|--------|
| `vector_dot(a, b)` | `Σ aᵢbᵢ` (raw similarity) |
| `vector_magnitude(v)` | `√Σ vᵢ²` (uses `xiom.math.sqrt`) |
| `vector_normalize(v)` | unit vector (`requires: magnitude > 0`; zero → zero) |
| `vector_add / sub / scale` | element-wise arithmetic, new `Vector` |
| `vector_dimension(v)` | `v.dimension` |

## Distance metrics (`metric.xi`)

```
enum DistanceMetric { Cosine, DotProduct, Euclidean }
```

| Metric | Formula | Range | Zero-vector behaviour |
|--------|---------|-------|-----------------------|
| Euclidean | `√Σ(aᵢ−bᵢ)²` | `[0, ∞)` | well-defined |
| DotProduct | `−Σ aᵢbᵢ` | `(−∞, ∞)` | 0 |
| Cosine | `1 − (a·b)/(‖a‖‖b‖)` | `[0, 2]` | returns `1.0` when either magnitude is 0 |

Key convention: **all metrics are distances where smaller means closer.**
DotProduct is negated for exactly this reason, so the same ascending top-K
logic works for every metric.

### Dispatch

```
vector_distance(a, b, metric)
  requires: a.dimension == b.dimension
{
  match metric {
    Cosine     => cosine_distance(a, b),
    DotProduct => dot_product_distance(a, b),
    Euclidean  => euclidean_distance(a, b),
  }
}
```

`vector_distance` is the single dispatch point. Every search path calls it, so
adding a metric is a one-variant, one-arm change — and the `match` is
exhaustive, so the compiler flags any path that forgets the new metric.

## The distance kernel layer (`distance/`)

`distance/{cosine,dot,l2}` are thin wrappers over the canonical `metric.xi`
implementations:

- `cosine_kernel` / `cosine_similarity`
- `dot_distance` / `dot_raw`
- `l2_distance` / `l2_squared` (the squared form skips the sqrt for
  ordering-only comparisons)

They exist as a **seam**: Phase 10 replaces these bodies with SIMD/FMA kernels
without touching a single call site, because callers already depend on the
kernel module rather than on the scalar loop.

## The `Neighbor` edge

```
Neighbor { id: UInt64; distance: Float32 }
```

The low-level `(id, distance)` pair. It is what HNSW stores in adjacency lists
and returns from `hnsw_search`, and what the top-K heap holds. The query layer
lowers `Neighbor` (UInt64 id) to the public `SearchResult` (Int id). Keeping this
type below the index layer is what lets `index.hnsw` avoid depending on the
query layer.

## `Dimension` wrapper

```
Dimension { value: Int } derive[Clone, Eq]
```

A typed dimension so a raw count can't be mistaken for a dimensionality.
`dimension_is_valid` delegates to `core.contracts.is_valid_dimension`;
`dimension_within_limit` uses `core.limits.max_dimensions()`. This is the vector
layer's single source of truth for "what is a valid dimension," kept in lockstep
with core.
