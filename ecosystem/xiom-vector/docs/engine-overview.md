# Engine Overview

`xiom-vector` is a layered vector database engine. This document is the
10,000-foot map; each layer has its own deep-dive linked below.

## What the engine does

Store dense float vectors (with optional metadata payloads), then answer
"which stored vectors are most similar to this query vector?" quickly and
durably.

## The layers, top to bottom

| Layer | Modules | Responsibility |
|-------|---------|----------------|
| **API** | `api/vector_api` | Stable public surface: create/upsert/search/delete/get. |
| **Orchestration** | `engine` | Wire the write path, query path, WAL, and metrics; own the active collection. |
| **Query** | `query/{search_request, topk_heap, search_service}` | Request modelling, bounded top-K, exact scan, index dispatch. |
| **Index** | `index/{ann_index, flat_index, hnsw}` | Physical search structures: exact flat baseline + approximate HNSW. |
| **Distance** | `distance/{cosine, dot, l2}` | Distance kernels (SIMD seam). |
| **Collection** | `collection/{schema, collection, validator}` | Schema, index config, validation. |
| **Payload** | `payload/{payload, filter_ast, filter_eval}` | Metadata + filter expressions. |
| **Segment** | `segment/{segment_state, segment, manifest}` | Storage lifecycle, sealing, compaction, manifest. |
| **Storage** | `storage/{vector_store, id_map}` | In-memory columnar store + id → location mapping. |
| **Types** | `types/{dense_vector, metric, neighbor, dimension}` | Value types shared by all layers. |
| **Durability** | `durability/write_ahead_events` | Vector events on the shared core WAL. |
| **Errors/Ids** | `error`, `ids` | Typed failures + identity (bridged to `xiom-core`). |

The **substrate** below all of this is `xiom-core` (see
[`core-vs-vector.md`](core-vs-vector.md)).

## Two hot paths

- **Write path** (`upsert`): validate → WAL-before-ack → store → metric → ack.
- **Search path** (`search`): validate → route to index → (filter) → top-K rerank → (hydrate) → return.

Both are described end to end in [`query-execution.md`](query-execution.md) and
[`ARCHITECTURE.md`](../ARCHITECTURE.md).

## What runs today

The Phase 0–1 core is fully functional in memory: vector math, all three
metrics, exact KNN/range search, the HNSW graph, the bounded top-K heap, and the
engine orchestrator with real create/upsert/search/delete dispatch. The write
path already appends to the shared core WAL before acking.

Everything above storage/index — collections beyond one, segments, payload
filtering, durable recovery, IVF/PQ — is typed and scaffolded with
`// TODO(Phase N):` markers pointing at [`../ROADMAP.md`](../ROADMAP.md).

## Deep dives

- [core-vs-vector.md](core-vs-vector.md) — what is reused from `xiom-core` and why.
- [vector-types-and-metrics.md](vector-types-and-metrics.md) — the value types and distance math.
- [hnsw-design.md](hnsw-design.md) — the approximate index.
- [segment-lifecycle.md](segment-lifecycle.md) — storage states and compaction.
- [metadata-filtering.md](metadata-filtering.md) — payloads and the filter AST.
- [query-execution.md](query-execution.md) — the full search pipeline.
- [contracts-and-invariants.md](contracts-and-invariants.md) — the guarantees, in code.
- [error-catalog.md](error-catalog.md) — every error and its meaning.
