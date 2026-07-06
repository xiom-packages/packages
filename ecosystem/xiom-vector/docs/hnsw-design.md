# HNSW Design

`src/index/hnsw.xi` — the approximate nearest-neighbour (ANN) index. This
documents the current (working, simplified) implementation and the production
TODOs from [`../ROADMAP.md`](../ROADMAP.md) (Phases 1 and 4).

## What HNSW is

Hierarchical Navigable Small World is a multi-layer proximity graph. Layer 0
holds every node; each higher layer holds an exponentially thinning random
subset. Search enters at the top, greedily descends to the closest node on each
layer, then does a wider search on layer 0. This yields sub-linear query time
with high recall.

## Node layout

```
HNSWNode  { id: UInt64; neighbors: Vec[Neighbor] }
HNSWLayer { nodes: Vec[HNSWNode]; vectors: Vec[Vector] }
HNSWGraph { layers: Vec[HNSWLayer]; max_neighbors: Int; ml: Float32 }
```

- `nodes` and `vectors` are index-aligned within a layer (`nodes[i]` ↔ `vectors[i]`).
- Adjacency is stored as `Neighbor(id, distance)`; cross-layer identity is by
  `id` (`find_node_pos` resolves an id to a per-layer position).
- Results are `Vec[Neighbor]` — the index layer never references the query layer.

## Parameters

| Param | Meaning | Typical | Enforced by |
|-------|---------|---------|-------------|
| `max_neighbors` (M) | Max edges per node per layer. | 16 | `hnsw_new requires: > 0`; ≤ `core.limits.max_graph_degree()` (512) |
| `ml` | Level multiplier; P(level ≥ ℓ) ≈ `ml^(−ℓ)`. | 4.0 | `hnsw_new requires: > 0.0` |
| `ef_construction` | Build-time beam width. | 200 | `AnnParams` (not yet honoured — Phase 4) |
| `ef_search` | Query-time beam width. | 64 | `AnnParams` (not yet honoured — Phase 4) |

`AnnParams` (in `index/ann_index.xi`) carries `m`, `ef_construction`, and
`ef_search`; `ann_params_valid` bounds `m` by the shared core graph-degree limit.

## Parameter Tuning Ranges

The table above lists point defaults; production tuning moves within these
ranges. Each parameter trades off memory, construction cost, and runtime
recall/latency.

| Param | Range | Default | Effect of increasing |
|-------|-------|---------|----------------------|
| `M` (graph degree) | 16–32 | 16 | Better recall, more memory. |
| `ef_construction` | ≈ 2×M, up to ~200 | 200 | Better graph quality, slower build. |
| `ef_search` (query breadth) | 64–128 | 64 | Better recall, higher latency. |

- **`M` (graph degree)** — 16–32. Higher `M` means more edges per node, so
  better recall at the cost of more memory per vector.
- **`ef_construction`** — heuristic is ≈ 2×M, up to roughly 200. Higher values
  build a higher-quality graph but make construction slower.
- **`ef_search` (query breadth)** — 64–128. Higher values widen the query-time
  beam for better recall at the cost of higher latency.

**How to tune:** benchmark **recall@k** and **p99 latency** against your target
workloads and adjust within these ranges. HNSW tuning is fundamentally a balance
among **memory, construction cost, and runtime recall/latency** — there is no
single best point, only the best point for a given workload and budget.

## Build path (`hnsw_insert`)

1. **Level assignment** — `assign_level(node_count, ml)` uses a linear
   congruential generator seeded from the node count to draw a level from the
   exponential distribution (XIOM has no built-in RNG; this is deterministic and
   well-distributed).
2. **Ensure layers** — grow `layers` up to the new node's level.
3. **First node** — if the graph is empty, insert into every layer as the sole
   entry point.
4. **Descend** — from the top layer down to `level+1`, greedily move to the
   closest node, remapping the entry point across layers by id.
5. **Connect** — from `level` down to 0: greedy-descend, select up to
   `max_neighbors` nearest nodes in the layer (brute force), insert the node, and
   add **bidirectional** edges.

## Search path (`hnsw_search`)

1. Start at layer-0-projected top entry point.
2. For each layer above 0: `greedy_search_layer` walks to a local minimum, then
   remaps to the next layer by id.
3. On layer 0: a beam-style expansion from the entry — pop the closest frontier
   candidate, visit unvisited neighbours, push them as candidates.
4. Sort candidates by distance; return the first `k` as `Vec[Neighbor]`.
5. `ensures: result.len() <= k`.

## Contracts

- `hnsw_new` — `max_neighbors > 0`, `ml > 0.0`.
- `hnsw_search` — `k > 0`, and `result.len() <= k`.
- Neighbour selection caps adjacency at `max_neighbors` (the graph-degree
  invariant; see [`contracts-and-invariants.md`](contracts-and-invariants.md)).
- Cold/empty graph returns an empty result — never panics.

## Current simplifications (and the production TODOs)

| Area | Now (simplified) | Production (Phase 4) |
|------|------------------|----------------------|
| Neighbour selection | brute-force nearest within the layer | heuristic RNG pruning for diversity/recall |
| Beam width | implicit (visit-all frontier) | honour `ef_construction` / `ef_search` |
| Metric | euclidean internally for traversal | metric-agnostic via `vector_distance` |
| Node position lookup | linear `find_node_pos` | id → position hash map |
| Deletes | not supported | tombstones + edge repair |
| Persistence | in-memory only | serialized into sealed segments |

These are structural, not correctness, gaps: the flat index remains the truth
oracle, and HNSW recall is validated against it in Phase 4.
