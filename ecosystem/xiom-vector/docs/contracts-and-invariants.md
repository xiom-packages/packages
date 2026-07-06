# Contracts and Invariants

XIOM lets us encode correctness rules directly in the code via `requires:` /
`ensures:` clauses and exhaustive `match`. This document is the canonical list of
the engine's invariants, where each is enforced, and why it matters.

## 1. Dimension is constant after collection creation

A collection's dimension is fixed at `create_collection` and every vector it
stores or is queried with must match it exactly.

**Enforced in code:**
- `collection.schema.schema_new` — `requires: is_valid_dimension(dimension)`, `ensures: result.dimension == dimension`.
- `collection.validator.validate_vector` — returns `VectorError.DimensionMismatch(expected, got)` when `v.dimension != schema.dimension`.
- `engine_upsert` / `engine_search` — reject with `CoreError.InvalidInput` on mismatch **before** any state change or distance computation.
- `storage.index_add` — `requires: idx.dim == vec.dimension`.

**Why:** distances between vectors of different dimensions are meaningless;
catching this at the boundary keeps every downstream kernel total.

## 2. `vector_distance` requires equal dimensions

Every distance kernel and the dispatcher carry the contract.

**Enforced in code:**
- `metric.vector_distance`, `metric.cosine_distance`, `metric.dot_product_distance`, `metric.euclidean_distance` — all `requires: a.dimension == b.dimension`.
- `distance.{cosine_kernel, dot_distance, l2_distance, l2_squared}` — same.
- `dense_vector.{vector_dot, vector_add, vector_sub}` — same.

**Why:** the kernels index both vectors up to a shared `dimension`; the contract
makes out-of-bounds access impossible.

## 3. `search_knn` (and every search) ensures `result.len() <= k`

A top-k query never returns more than `k` hits.

**Enforced in code:**
- `query.search_service.search_knn` — `requires: k > 0`, `ensures: result.len() <= k`.
- `query.search_service.search_execute` — `ensures: result.len() <= k`.
- `index.flat_index.flat_index_search` — `ensures: result.len() <= k`.
- `index.hnsw.hnsw_search` — `requires: k > 0`, `ensures: result.len() <= k`.
- `engine_search` — additionally `requires: is_valid_top_k(k)` bounds `k ≤ max_top_k()`.

**Why:** callers size buffers on `k`; exceeding it is a memory-safety and
contract violation.

## 4. The top-K heap never exceeds its capacity

The reranking primitive that makes invariant #3 compose across sources.

**Enforced in code:**
- `query.topk_heap.topk_new` — `requires: capacity > 0`, `ensures: items.len() == 0`.
- `query.topk_heap.topk_push` — `ensures: items.len() <= capacity` (overflow drops the worst element).

**Why:** whether one index or many segments feed the heap, the bound holds after
every push, so the final result is bounded regardless of fan-out.

## 5. HNSW node degree ≤ `max_neighbors`

Each node's adjacency list is bounded per layer.

**Enforced in code:**
- `index.hnsw.select_neighbors` — collects at most `max_n` (`= graph.max_neighbors`) ids.
- `index.hnsw.hnsw_new` — `requires: max_neighbors > 0`.
- `index.ann_index.ann_params_valid` — `m ≤ core.limits.max_graph_degree()` (512).

**Why:** unbounded degree destroys HNSW's sub-linear guarantees and memory
predictability.

## 6. WAL-before-ack (durability)

No write is acknowledged before its WAL record exists.

**Enforced in code:**
- `engine_upsert` — calls `durability.log_upsert` (→ `core wal_writer_append`) *before* `index_add`.
- `engine_delete` — calls `durability.log_delete` before `index_remove`.
- `durability.write_ahead_events` — maps events to core `WalOpKind` so recovery parses one format.

**Why:** a crash after ack but before persistence would lose an acknowledged
write; ordering the WAL append first makes writes recoverable.

## 7. Segment transitions follow the lifecycle table

A segment can only move along legal edges of its state machine.

**Enforced in code:**
- `segment.segment_state.segment_state_can_transition` — the single source of truth.
- `segment.segment.segment_transition` — consults it and no-ops (returns `false`) on illegal moves.
- Writability: `segment_state_is_writable` is true only for `Mutable`.

**Why:** prevents writing to sealed data, double-sealing, or resurrecting dropped
segments.

## 8. `top_k`, dimension, and degree respect shared limits

The engine and core agree on ceilings.

**Enforced in code:**
- Dimension ≤ `core.limits.max_dimensions()` via `types.dimension.dimension_within_limit` and `core.contracts.is_valid_dimension`.
- `top_k` ≤ `core.limits.max_top_k()` via `core.contracts.is_valid_top_k` (checked in `engine_search`).
- HNSW `m` ≤ `core.limits.max_graph_degree()` (see #5).

**Why:** limits live in one place (`xiom-core`) so vector and non-vector
subsystems can't drift.

## 9. Errors are values, always handled

There are no exceptions or hidden failure channels.

**Enforced in code:**
- Every fallible API returns `Result[T, CoreError]` (`engine_*`, `api.*`,
  `validator.*`) or `Option[T]` (`get_point`, lookups).
- `error.VectorError` maps to `CoreError` via `vector_error_to_core` so a single
  error type crosses layer boundaries.

**Why:** the compiler forces every caller to handle failure explicitly.

---

### Invariant → enforcement quick index

| # | Invariant | Primary enforcement site |
|---|-----------|--------------------------|
| 1 | Dimension constant | `validator.validate_vector`, `engine_upsert/search`, `index_add` |
| 2 | Equal-dim distance | `metric.*`, `distance.*`, `dense_vector.*` `requires:` |
| 3 | `result.len() <= k` | `search_knn`, `search_execute`, `flat_index_search`, `hnsw_search` |
| 4 | Heap ≤ capacity | `topk_heap.topk_push` `ensures:` |
| 5 | Degree ≤ max | `hnsw.select_neighbors`, `ann_params_valid` |
| 6 | WAL-before-ack | `engine_upsert/delete` ordering |
| 7 | Legal seg transitions | `segment_state_can_transition` |
| 8 | Shared limits | `core.limits` + `core.contracts` |
| 9 | Errors as values | `Result`/`Option` on every fallible API |
