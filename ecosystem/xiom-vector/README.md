# xiom-vector

> Production-grade vector database engine for XIOM — dense vectors, distance metrics, flat + HNSW ANN search, collections, segments, and a WAL-backed durable write path, built on the shared `xiom-core` durable-systems substrate.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-vector is organized as a **layered engine** rather than a flat set of files. It reuses `xiom-core` (errors, ids, config, limits, contracts, WAL, metrics) as its durable-systems substrate and adds the vector-specific layers on top: types, storage, indexes, query, collections, payload/filtering, segments, durability, and a public API facade.

The engine's working core — dense-vector math, the three distance metrics, the exact flat/brute-force search, and the in-memory HNSW graph — is fully implemented today. Higher layers (collections, segments, payload filtering, durable recovery) are typed and scaffolded against the roadmap.

See:
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — the shared-core + vector-layer model, module tree, write/search paths, failure domains.
- [`ROADMAP.md`](ROADMAP.md) — the Phase 0–10 plan and honest status of every capability.
- [`COLLECTIONS.md`](COLLECTIONS.md) — the user-facing collection schema model.
- [`SPEC.md`](SPEC.md) — module-by-module reference.
- [`docs/`](docs/) — deep dives (engine, core-vs-vector, metrics, HNSW, segments, filtering, query execution, contracts, errors).

## Installation
```bash
xiom install xiom-vector
```

## Quick Start
```xiom
use xiom.vector.engine;
use xiom.vector.api.vector_api;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;

fn main() -> Int {
  var eng = engine_new();
  create_collection(&mut eng, 3, DistanceMetric.Cosine);

  var v = Vector.new(3);
  v.set(0, 1.0); v.set(1, 0.0); v.set(2, 0.0);
  upsert(&mut eng, 1, v);

  var q = Vector.new(3);
  q.set(0, 0.9); q.set(1, 0.1); q.set(2, 0.0);
  var hits = search(&eng, &q, 5);
  return 0;
}
```

## Module Tree

```
src/
├── error.xi                  VectorError taxonomy (-> CoreError)
├── ids.xi                    PointId + reuse of core Collection/Vector/SegmentId
├── engine.xi                 VectorEngine orchestrator (real dispatch)
├── types/                    dense_vector · metric · neighbor · dimension
├── collection/               schema · collection · validator
├── payload/                  payload · filter_ast · filter_eval
├── storage/                  vector_store · id_map
├── segment/                  segment_state · segment · manifest
├── index/                    ann_index · flat_index · hnsw
├── distance/                 cosine · dot · l2
├── query/                    search_request · topk_heap · search_service
├── durability/               write_ahead_events
└── api/                      vector_api (public facade)
```

## Public API (`xiom.vector.api.vector_api`)
| Function | Description |
|----------|-------------|
| `create_collection(eng, dim, metric)` | Create the active collection; fixes dimension + metric |
| `upsert(eng, point, vec)` | WAL-durable insert/update of a point |
| `search(eng, query, k)` | Exact top-k nearest neighbours |
| `delete_point(eng, point)` | Remove a point |
| `get_point(eng, point)` | Fetch a stored vector by id |

All fallible calls return `Result[T, CoreError]`.

## Production Readiness
| Capability | Status |
|-----------|--------|
| Dense vector math (dot/cosine/euclidean/normalize/…) | ✅ Done |
| Distance metrics + dispatch | ✅ Done |
| Flat exact KNN + range search | ✅ Done |
| In-memory HNSW graph (insert + greedy search) | ✅ Done |
| Bounded top-K heap | ✅ Done |
| Engine orchestration (create/upsert/search/delete) | ✅ Done |
| WAL-before-ack write path | 🟡 In progress (in-memory core WAL; fsync + payload = Phase 2) |
| Collections / schema / validator | 🟡 In progress (single active collection) |
| Segments + lifecycle state machine | 🟠 Scaffold (types + transitions) |
| Payload + metadata filtering | 🟠 Scaffold (AST + fail-open eval) |
| Durable recovery / manifest | 🟠 Scaffold |
| IVF / PQ / disk-backed / SIMD | ⛔ Not started |

Full detail in [`ROADMAP.md`](ROADMAP.md).

## Dependencies
- `xiom-std` — standard library
- `xiom.math` — `sqrt` for magnitude/euclidean/cosine
- `xiom-core` — shared errors, ids, config, limits, contracts, WAL, metrics

## Links: [github.com/xiom-lang](https://github.com/xiom-lang) | [XIOM](https://github.com/xiom-lang/XIOM)
## License: MIT OR Apache-2.0
