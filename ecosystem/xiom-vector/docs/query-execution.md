# Query Execution

The end-to-end pipeline for `search`, plus the write path that feeds it. Modules
involved: `api/vector_api`, `engine`, `query/*`, `index/*`, `storage/*`,
`durability/*`.

## Write path (feeds the query path)

```
api.upsert(eng, point, vec)
  └─> engine_upsert
        1. validate     (vec.dimension as Int) == eng.dimension   else CoreError.InvalidInput
        2. WAL-before-ack   durability.log_upsert(&mut eng.wal, collection, point)
                            → core wal_writer_append → assigns LSN
        3. apply        storage.index_add(&mut eng.store, point, vec)
        4. observe      counter_inc(&mut eng.upserts)
        5. ack          Ok(true)
```

The write is **not** acknowledged until its WAL record exists. Delete follows the
same shape via `log_delete` + `index_remove`.

## Search path

```
api.search(eng, query, k)
  └─> engine_search
        1. validate
             (query.dimension as Int) == eng.dimension     else CoreError.InvalidInput
             is_valid_top_k(k)                              else CoreError.InvalidInput
        2. route (query.search_service.search_execute)
             match AnnIndexKind {
               Flat  -> search_knn(store, query, k, metric)          exact O(n)
               Hnsw  -> hnsw_search(graph, query, k) then lower      approximate
               Ivf   -> search_knn (fallback until Phase 9)
             }
        3. (Phase 3) filter    keep candidates whose payload matches FilterExpr
        4. rerank              bounded top-K heap: ascending distance, len() <= k
        5. (Phase 3) hydrate   attach payloads when SearchRequest.with_payload
        6. return              Ok(Vec[SearchResult]),  result.len() <= k
```

Today `engine_search` calls `search_knn` directly (exact path). `search_execute`
is the planner seam already wired to both flat and HNSW; promoting a collection
to HNSW is a routing choice, not an API change.

## The exact scan (`search_service.search_knn`)

The correctness oracle. For each stored vector:
1. `dist = vector_distance(stored, query, metric)`.
2. Push a `SearchResult`, bubble it left by insertion sort.
3. If the buffer exceeds `k`, pop the worst.

Cost O(n·k); `ensures: result.len() <= k`. `search_range` is the same loop with a
radius test instead of a top-K cap (`requires: radius > 0.0`).

## Bounded top-K (`query/topk_heap`)

```
TopKHeap { capacity; items: Vec[Neighbor] }
topk_push  ensures: items.len() <= capacity
```

Insertion-sorted ascending; on overflow the worst (last) element is dropped.
This is the component that makes the `result.len() <= k` guarantee compose across
multiple contributing indexes/segments — every source pushes into one heap.

## Request modelling (`query/search_request`)

```
SearchRequest { query; top_k; metric; filter: Vec[FilterExpr]; with_payload }
```

Bundles everything a query needs. `filter` is an optional single-clause slot
today (empty = unfiltered); `with_payload` requests payload hydration on hits.

## Result lowering

Index implementations speak `Neighbor` (UInt64 id). The query layer's
`neighbors_to_results` lowers them to the public `SearchResult` (Int id). This
keeps `index.hnsw` free of any dependency on the query layer.

## Multi-segment fan-out (Phase 5)

When a collection has many segments, step 2 becomes:

```
for each live segment in manifest.active_segments:
    hits = search that segment (flat if mutable, HNSW if immutable)
    for h in hits: topk_push(&mut heap, h)
return heap sorted
```

The single shared heap enforces `len() <= k` no matter how many segments
contribute, so the top-level guarantee is unchanged.

## Guarantees at a glance

- Dimension validated before any distance is computed.
- `top_k` bounded by `core.limits.max_top_k()`.
- `result.len() <= k` on every path (`search_knn`, `hnsw_search`, `search_execute`).
- Cold/empty index → empty result, never a panic.
- All failures are explicit `Result[T, CoreError]` values.
