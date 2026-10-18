<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

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
| **API** | `engine` (facade) | Stable public surface: create/upsert/search/delete/get + payloads + filtered search (`src/engine.xi`). |
| **Orchestration** | `engine/core` + `core/shim` | Wire the write path, query path, WAL, and metrics; own the active collection (`src/engine/core.xi`; the xiom-core stand-ins live in `src/core/shim.xi` until the porter flow maps them). |
| **Query** | `query/{search_request, topk_heap, search_service}` | Request modelling, bounded top-K, exact scan, index dispatch. |
| **Index** | `index/{ann_index, flat_index, hnsw}` | Physical search structures: exact flat baseline + approximate HNSW. |
| **Distance** | `distance/{cosine, dot, l2}` | Distance kernels (SIMD seam). |
| **Collection** | `collection/{schema, collection, validator}` | Schema, index config, validation. |
| **Payload** | `payload/{payload, filter_ast, filter_eval}` | Metadata + filter expressions. |
| **Segment** | `segment/{segment_state, segment, manifest}` | Storage lifecycle, sealing, compaction, manifest. |
| **Storage** | `storage/{vector_store, id_map}` | In-memory columnar store + id -> location mapping. |
| **Types** | `types/{dense_vector, metric, neighbor, dimension}` | Value types shared by all layers. |
| **Durability** | `durability/write_ahead_events` | Vector events on the shared core WAL. |
| **Errors/Ids** | `error`, `ids` | Typed failures + identity (bridged to `xiom-core`). |

The **substrate** below all of this is `xiom-core` (see
[`core-vs-vector.md`](core-vs-vector.md)).

## Two hot paths

- **Write path** (`upsert`): validate -> WAL-before-ack -> store -> metric -> ack.
- **Search path** (`search`): validate -> route to index -> (filter) -> top-K rerank -> (hydrate) -> return.

Both are described end to end in [`query-execution.md`](query-execution.md) and
[`ARCHITECTURE.md`](../ARCHITECTURE.md).

## What runs today

The working core is fully functional in memory: vector math, all three
metrics, exact KNN search (filtered and unfiltered), the HNSW graph, the
bounded top-K heap, and the engine orchestrator with real
create/upsert/search/delete dispatch. The write path appends to the WAL
before acking, and the WAL carries vectors + metadata, so `engine_recover`
rebuilds both. The module tree is final (four extraction waves):
`engine` (facade) <- `engine/core` <- `core/shim`.

Still typed/scaffolded (see [`../ROADMAP.md`](../ROADMAP.md)): multiple
collections, segments, file-backed WAL + durable manifest (stdlib fsync gap),
sorted payload index + pre/post planner, HNSW hardening + recall harness,
IVF/PQ.

## Deep dives

- [core-vs-vector.md](core-vs-vector.md) -- what is reused from `xiom-core` and why.
- [vector-types-and-metrics.md](vector-types-and-metrics.md) -- the value types and distance math.
- [hnsw-design.md](hnsw-design.md) -- the approximate index.
- [segment-lifecycle.md](segment-lifecycle.md) -- storage states and compaction.
- [metadata-filtering.md](metadata-filtering.md) -- payloads and the filter AST.
- [query-execution.md](query-execution.md) -- the full search pipeline.
- [contracts-and-invariants.md](contracts-and-invariants.md) -- the guarantees, in code.
- [error-catalog.md](error-catalog.md) -- every error and its meaning.
