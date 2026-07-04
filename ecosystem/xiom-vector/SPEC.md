# xiom-vector SPEC

## Architecture

xiom-vector is a pure-XIOM vector database library organized into four modules:

```
ecosystem/xiom-vector/
├── package.xi          Package manifest
├── SPEC.md             This document
└── src/
    ├── types.xi          Core types and distance functions
    ├── index.xi          Brute-force flat vector index
    ├── search.xi         Similarity search algorithms
    └── hnsw.xi           Hierarchical Navigable Small World graph
```

### Module Dependency Graph

```
types.xi  (base: Vector, DistanceMetric, HNSWNode, Neighbor)
    ↓
index.xi  (VectorIndex: flat storage, depends on types)
    ↓
search.xi (SearchResult, search_knn, search_range: depends on types + index)
    ↓
hnsw.xi   (HNSWGraph: approximate NN search, depends on types + search)
```

---

## Module: `xiom.vector.types` — Core Types

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `Vector` | `data: Vec[Float32]`, `dimension: UInt` | Dense float vector |
| `HNSWNode` | `id: UInt64`, `neighbors: Vec[Neighbor]` | Graph node for HNSW |
| `Neighbor` | `id: UInt64`, `distance: Float32` | Edge in HNSW graph |

### Enum: `DistanceMetric`

| Variant | Description |
|---------|-------------|
| `Cosine` | 1 - cosine similarity |
| `DotProduct` | Negative dot product (inner product distance) |
| `Euclidean` | L2 norm distance |

### Vector Constructors & Accessors

```
fn Vector.new(dimension: UInt) -> Vector
  requires: dimension > 0
```
Creates a zero-initialized vector of the given dimension.

```
fn Vector.set(index: UInt, value: Float32)
  requires: index < dimension
```
Sets element at `index` to `value`.

```
fn Vector.get(index: UInt) -> Float32
  requires: index < dimension
```
Returns element at `index`.

### Distance Functions

```
fn dot_product_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
```
Returns `-Σ(a[i] * b[i])`. Negative so that closer vectors have smaller distances.

```
fn cosine_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
```
Returns `1 - cos(θ) = 1 - (a·b) / (|a| * |b|)`. Zero vectors return 1.0.

```
fn euclidean_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
```
Returns `sqrt(Σ(a[i] - b[i])²)`. Uses Newton's method (20 iterations) for sqrt.

### Vector Utility Functions

```
fn vector_dot(a: &Vector, b: &Vector) -> Float32
```
Positive dot product `Σ(a[i] * b[i])`. Raw similarity score.

```
fn vector_magnitude(v: &Vector) -> Float32
```
Euclidean norm `sqrt(Σ v[i]²)`.

```
fn vector_normalize(v: &Vector) -> Vector
```
Unit vector in direction of `v`. Zero vector returns zero vector.

```
fn vector_add(a: &Vector, b: &Vector) -> Vector
fn vector_sub(a: &Vector, b: &Vector) -> Vector
fn vector_scale(v: &Vector, scalar: Float32) -> Vector
```
Element-wise arithmetic. All return new `Vector` instances.

```
fn vector_distance(a: &Vector, b: &Vector, metric: DistanceMetric) -> Float32
```
Dispatcher that delegates to `cosine_distance`, `dot_product_distance`, or `euclidean_distance` based on the `metric` variant.

```
fn vector_dimension(v: &Vector) -> UInt
```
Returns `v.dimension`.

---

## Module: `xiom.vector.index` — Flat Vector Index

### Type: `VectorIndex`

```
pub type VectorIndex = {
  vectors: Vec[Vector];
  ids: Vec[Int];
  dim: UInt;
}
```

Parallel arrays storing vectors and their integer IDs. All vectors must have the same dimension `dim`.

### API

```
fn index_new(dim: UInt) -> VectorIndex
  requires: dim > 0
```
Creates an empty index for vectors of dimension `dim`.

```
fn index_add(idx: &mut VectorIndex, id: Int, vec: Vector) -> Bool
  requires: idx.dim == vec.dimension
```
Adds a vector with the given ID. Returns `true` on success, `false` if ID already exists.

```
fn index_remove(idx: &mut VectorIndex, id: Int) -> Bool
```
Removes the vector with the given ID. Uses swap-with-last + pop for O(1) removal. Returns `true` if found and removed.

```
fn index_get(idx: &VectorIndex, id: Int) -> Option[Vector]
```
Returns `Some(vector)` if the ID exists, `None` otherwise.

```
fn index_size(idx: &VectorIndex) -> Int
```
Returns the number of vectors currently stored.

---

## Module: `xiom.vector.search` — Similarity Search

### Type: `SearchResult`

```
pub type SearchResult = {
  id: Int;
  distance: Float32;
} derive[Clone]
```

Represents a single search hit: the vector's ID and its distance from the query.

### API

```
fn search_knn(idx: &VectorIndex, query: &Vector, k: Int, metric: DistanceMetric) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.dim == query.dimension
```
Brute-force k-nearest neighbors search. Returns up to `k` results sorted by distance ascending.

**Algorithm**: For each stored vector, compute distance to query. Insert into a sorted result buffer using insertion sort (bubble leftwards). Truncate to `k` elements. Time: O(n·k) where n = index size.

```
fn search_range(idx: &VectorIndex, query: &Vector, radius: Float32, metric: DistanceMetric) -> Vec[SearchResult]
  requires: radius >= 0.0
  requires: idx.dim == query.dimension
```
Returns all vectors whose distance to the query is ≤ `radius`, sorted by distance ascending.

**Algorithm**: For each stored vector, if distance ≤ radius, insert into sorted results buffer. Time: O(n·m) where m = result count.

---

## Module: `xiom.vector.hnsw` — HNSW Graph

### Types

```
pub type HNSWLayer = {
  nodes: Vec[HNSWNode];
  vectors: Vec[Vector];
}

pub type HNSWGraph = {
  layers: Vec[HNSWLayer];
  max_neighbors: Int;
  ml: Float32;
}
```

An HNSW graph consists of a hierarchy of layers. Layer 0 (base) contains all nodes. Higher layers contain progressively fewer nodes (exponentially decaying with `ml`). Each layer is a navigable small world graph where nodes are connected to their `max_neighbors` nearest neighbors.

`ml` (level multiplier) controls the layer distribution: probability of a node reaching level `ℓ` is `ml^(-ℓ)`.

### API

```
fn hnsw_new(max_neighbors: Int, ml: Float32) -> HNSWGraph
  requires: max_neighbors > 0
  requires: ml > 0.0
```
Creates an empty HNSW graph. `max_neighbors` is the maximum edges per node per layer. Typical values: `max_neighbors=16`, `ml=4.0`.

```
fn hnsw_insert(graph: &mut HNSWGraph, id: Int, vec: Vector) -> Bool
```
Inserts a vector into the HNSW graph.

**Algorithm** (simplified greedy):
1. Assign a random level `L` to the node using exponential distribution parameterized by `ml`.
2. If graph is empty: add node to all layers 0..L as the sole entry point.
3. Otherwise:
   - From the top layer down to L+1: perform greedy descent to find the closest node to the new vector. Map the entry point to the next layer by node ID.
   - For layers L down to 0: perform greedy descent, select `max_neighbors` nearest neighbors via brute-force within the layer, add the node, and establish bidirectional connections.

```
fn hnsw_search(graph: &HNSWGraph, query: &Vector, k: Int) -> Vec[SearchResult]
  requires: k > 0
```
Approximate k-nearest neighbors using HNSW graph traversal.

**Algorithm** (simplified greedy, Euclidean distance):
1. Start from the top layer's first node.
2. For each layer down to 1: perform greedy descent (check neighbors, move to closer node, repeat until local minimum). Map result to next layer by ID.
3. In layer 0: perform beam search from the entry point. Expand candidates by exploring neighbors. Collect all visited candidates, sort by distance, return top-k.

```
fn hnsw_layer_count(graph: &HNSWGraph) -> Int
```
Returns the number of layers in the graph.

```
fn hnsw_node_count(graph: &HNSWGraph) -> Int
```
Returns the total number of node entries across all layers (a single vector may appear in multiple layers).

---

## Distance Metric Formulas

### Euclidean (L2)
```
d(a, b) = sqrt( Σ (a[i] - b[i])² )
```
Range: [0, ∞). Sensitive to magnitude.

### Dot Product (Inner Product)
```
d(a, b) = - Σ (a[i] * b[i])
```
Range: (-∞, ∞). Negative so that closer = smaller. Equivalent to negative inner product. Use when vectors are normalized and magnitude matters.

### Cosine
```
d(a, b) = 1 - (a·b) / (|a| * |b|)
```
Range: [0, 2]. Measures angular difference, invariant to magnitude. Zero vectors return 1.0 (maximum distance).

---

## Design Decisions

### Why parallel arrays in VectorIndex?
`Vec[Vector]` and `Vec[Int]` are kept in sync (same index = same entry). This enables O(1) access by position and simple swap-pop removal. A `HashMap[Int, Vector]` would require XIOM hash map support which isn't guaranteed.

### Why insertion sort for KNN results?
Pure XIOM has no built-in sort function or priority queue. Insertion sort via bubble-leftwards is straightforward with `while` loops and requires no external dependencies. For small `k` (typical: 5-100), the O(n·k) cost is acceptable.

### Why simplified greedy HNSW?
Full HNSW requires:
- Heuristic neighbor selection (pruning)
- Shrink-down edge maintenance
- Bidirectional edge count enforcement
- Random level generation with precise float precision

The simplified version demonstrates the structural concepts (hierarchical layers, greedy descent, node ID-based cross-layer mapping) without requiring these complex operations. The brute-force neighbor selection within layers compensates for the lack of pruning.

### Why Euclidean-only search in HNSW?
The greedy descent uses `Euclidean` distance internally for layer traversal. The search result distances are also Euclidean. Supporting all metrics within HNSW traversal would require passing `DistanceMetric` through all internal functions, which adds complexity without structural benefit.

### Why LCG-based level assignment?
XIOM has no built-in random number generator. The `assign_level` function uses a linear congruential generator seeded from the node count to produce deterministic but well-distributed level assignments following the HNSW exponential decay model.

### Why `ml` controls layer probability?
In standard HNSW, `mL = 1 / ln(M)` where M is the neighbor count. Here `ml` is exposed directly. Higher `ml` → more nodes in lower layers → flatter hierarchy. Lower `ml` → more nodes in higher layers → deeper hierarchy with faster traversal but higher memory.
