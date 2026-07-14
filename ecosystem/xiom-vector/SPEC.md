# xiom-vector — SPEC

Module-by-module reference for the layered vector engine. For the design
rationale see [`ARCHITECTURE.md`](ARCHITECTURE.md); for status see
[`ROADMAP.md`](ROADMAP.md).

## Layout

```
ecosystem/xiom-vector/
├── package.xi                  Manifest (deps: xiom-std, xiom.math, xiom-core)
├── README.md · ARCHITECTURE.md · ROADMAP.md · COLLECTIONS.md · SPEC.md
├── docs/                       Deep-dive design docs
└── src/
    ├── error.xi · ids.xi · engine.xi
    ├── types/{dense_vector,metric,neighbor,dimension}.xi
    ├── collection/{schema,collection,validator}.xi
    ├── payload/{payload,filter_ast,filter_eval}.xi
    ├── storage/{vector_store,id_map}.xi
    ├── segment/{segment_state,segment,manifest}.xi
    ├── index/{ann_index,flat_index,hnsw}.xi
    ├── distance/{cosine,dot,l2}.xi
    ├── query/{search_request,topk_heap,search_service}.xi
    ├── durability/write_ahead_events.xi
    └── api/vector_api.xi
```

---

## `xiom.vector.types.dense_vector`
`Vector { data: Vec[Float32]; dimension: UInt }` — the fundamental value type.
- `Vector.new(dimension)` `requires: dimension > 0` `ensures: result.data.len() == dimension`
- `Vector.set(index, value)` / `Vector.get(index)` `requires: index < dimension`
- `vector_dot`, `vector_magnitude`, `vector_normalize`, `vector_add`, `vector_sub`, `vector_scale`, `vector_dimension`
- Binary ops `requires: a.dimension == b.dimension`.

## `xiom.vector.types.metric`
`enum DistanceMetric { Cosine, DotProduct, Euclidean }`.
- `dot_product_distance` → `−Σ(aᵢbᵢ)`; `cosine_distance` → `1 − cosθ` (zero vectors → 1.0); `euclidean_distance` → `√Σ(aᵢ−bᵢ)²`.
- `vector_distance(a, b, metric)` dispatches (`requires: a.dimension == b.dimension`).
- `metric_name(m) -> Str`.

## `xiom.vector.types.neighbor`
`Neighbor { id: UInt64; distance: Float32 }` — low-level result edge used inside indexes/graph adjacency. `neighbor_new`, `neighbor_closer`.

## `xiom.vector.types.dimension`
`Dimension { value: Int }` wrapper. `dimension(v)`, `dimension_value`, `dimension_eq`, `dimension_is_valid` (delegates to `core.contracts.is_valid_dimension`), `dimension_within_limit` (uses `core.limits.max_dimensions`).

## `xiom.vector.error`
`enum VectorError { DimensionMismatch(expected, got), UnsupportedMetric(name), CollectionNotFound(id), InvalidVector(msg), SegmentSealed(id), TopKExceeded(requested, max) }`.
- `vector_error_to_str`, `vector_error_to_core` (→ `CoreError`), `vector_error_code` (stable numeric codes).

## `xiom.vector.ids`
Reuses `CollectionId`/`VectorId`/`SegmentId` from `xiom.core.ids`. Adds `PointId { value: Int }` (user id) with `point_id`, `point_id_value`, `point_id_eq`, and `point_to_vector_id` / `vector_to_point_id` bridges.

## `xiom.vector.storage.vector_store`
`VectorIndex { vectors: Vec[Vector]; ids: Vec[Int]; dim: UInt }` — flat columnar store.
- `index_new(dim)` `requires: dim > 0`
- `index_add(idx, id, vec)` `requires: idx.dim == vec.dimension` (returns false on duplicate id)
- `index_remove` (O(1) swap-with-last), `index_get -> Option[Vector]`, `index_size`.

## `xiom.vector.storage.id_map`
`IdMap` of `IdMapEntry { vector_id; segment; offset }`. `id_map_new/put/lookup/remove/len`. Maps logical id → physical location for compaction stability.

## `xiom.vector.index.ann_index`
`enum AnnIndexKind { Flat, Hnsw, Ivf }`; `AnnParams { m; ef_construction; ef_search }`. `ann_params_default` (`m=16, efC=200, efS=64`), `ann_params_valid` (bounds `m` by `core.limits.max_graph_degree`), `ann_index_kind_name`.

## `xiom.vector.index.flat_index`
`FlatIndex { store: VectorIndex }` — exact brute-force baseline / correctness oracle. `flat_index_new/add/remove/size`; `flat_index_search(idx, query, k, metric)` `ensures: result.len() <= k` (delegates to `search_service.search_knn`).

## `xiom.vector.index.hnsw`
`HNSWNode { id: UInt64; neighbors: Vec[Neighbor] }`, `HNSWLayer`, `HNSWGraph { layers; max_neighbors; ml }`.
- `hnsw_new(max_neighbors, ml)` `requires: max_neighbors > 0`, `ml > 0.0`.
- `hnsw_insert(graph, id, vec)` — level assignment, greedy descent, in-layer neighbour selection, bidirectional edges bounded by `max_neighbors`.
- `hnsw_search(graph, query, k)` `requires: k > 0` `ensures: result.len() <= k` — returns `Vec[Neighbor]`.
- `hnsw_layer_count`, `hnsw_node_count`.

## `xiom.vector.distance.{cosine,dot,l2}`
Kernel seam (SIMD drop-in point, Phase 10). `cosine_kernel`/`cosine_similarity`, `dot_distance`/`dot_raw`, `l2_distance`/`l2_squared`. Delegate to `types.metric` today.

## `xiom.vector.query.search_request`
`SearchRequest { query: Vector; top_k: Int; metric: DistanceMetric; filter: Vec[FilterExpr]; with_payload: Bool }`. `search_request_new` `requires: top_k > 0`, `search_request_set_filter`, `search_request_has_filter`, `search_request_top_k`.

## `xiom.vector.query.topk_heap`
`TopKHeap { capacity; items: Vec[Neighbor] }`. `topk_new(capacity)` `requires: capacity > 0` `ensures: items.len() == 0`; `topk_push` `ensures: items.len() <= capacity`; `topk_len`, `topk_is_full`, `topk_worst`.

## `xiom.vector.query.search_service`
`SearchResult { id: Int; distance: Float32 }`.
- `search_knn(idx, query, k, metric)` `requires: k > 0, idx.dim == query.dimension` `ensures: result.len() <= k`.
- `search_range(idx, query, radius, metric)` `requires: radius > 0.0, idx.dim == query.dimension`.
- `search_execute(idx, graph, query, k, metric, kind)` — routes by `AnnIndexKind` (Flat/Ivf → exact scan, Hnsw → graph), lowers `Neighbor → SearchResult`, `ensures: result.len() <= k`.

## `xiom.vector.collection.schema`
`enum NormalizationMode { Raw, L2Normalized }`; `PayloadFieldSpec { name; indexed }`; `CollectionSchema { dimension; metric; normalization; payload_fields }`. `schema_new(dim, metric)` `requires: is_valid_dimension(dim)` `ensures: result.dimension == dim`; `schema_set_normalization`, `schema_add_field`, `schema_dimension`.

## `xiom.vector.collection.collection`
`Collection { id: CollectionId; schema; segments: Vec[SegmentId]; index_kind; index_params }`. `collection_new`, `collection_register_segment`, `collection_segment_count`, `collection_dimension`.

## `xiom.vector.collection.validator`
`validate_dimension(schema, dim) -> Bool`; `validate_vector(schema, v) -> Result[Bool, VectorError]` (enforces dimension constancy); `validate_metric(schema, metric) -> Result[Bool, VectorError]`.

## `xiom.vector.payload.{payload,filter_ast,filter_eval}`
`enum FieldValue { IntVal, FloatVal, TextVal, BoolVal }`; `Payload` + `payload_new/set/has/len`, `field_value_kind`.
`enum FilterExpr { Eq, Range, Exists, In, And, Or, Not }` + constructors.
`filter_matches(expr, payload) -> Bool` — combinators + Exists implemented; value predicates fail-open (Phase 3).

## `xiom.vector.segment.{segment_state,segment,manifest}`
`enum SegmentStateKind { Mutable, Sealing, Sealed, Indexing, Immutable, Compacting, Dropped }` + `segment_state_is_writable/is_terminal/code/can_transition`.
`Segment { id; state; store }` + `segment_new/insert/transition/size/is_writable`.
`Manifest { collection; active_segments; last_lsn }` + `manifest_new/add_segment/remove_segment/set_lsn/segment_count`.

## `xiom.vector.durability.write_ahead_events`
`enum VectorWalEvent { UpsertEvent, DeleteEvent, SegmentSeal }`. `log_upsert/log_delete/log_segment_seal(w, ...)` map to `core.wal.wal_writer.wal_writer_append` with the matching `WalOpKind`; `event_op`.

## `xiom.vector.engine`
`VectorEngine { store; metric; dimension; created; wal; upserts; deletes; next_collection }`.
- `engine_new()`; `engine_create_collection(eng, dim, metric) -> Result[CollectionId, CoreError]` `requires: dim >= 1`.
- `engine_upsert(eng, point, vec) -> Result[Bool, CoreError]` `requires: eng.created` — WAL-before-ack + store apply + metric.
- `engine_search(eng, query, k) -> Result[Vec[SearchResult], CoreError]` `requires: eng.created, k > 0`.
- `engine_delete`, `engine_size`, `engine_durable_lsn`.

## `xiom.vector.api.vector_api`
Public facade: `create_collection`, `upsert`, `search`, `delete_point`, `get_point`. All fallible calls return `Result[T, CoreError]`.

---

## Distance formulas

| Metric | Formula | Range | Notes |
|--------|---------|-------|-------|
| Euclidean (L2) | `√Σ(aᵢ−bᵢ)²` | `[0, ∞)` | magnitude-sensitive; `l2_squared` skips the sqrt |
| Dot product | `−Σ(aᵢbᵢ)` | `(−∞, ∞)` | negated so closer = smaller |
| Cosine | `1 − (a·b)/(‖a‖‖b‖)` | `[0, 2]` | angular; zero vectors → 1.0 |
