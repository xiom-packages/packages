<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# xiom-vector

> Production-grade vector database engine for XIOM -- dense vectors, distance metrics, flat + HNSW ANN search, collections, segments, and a WAL-backed durable write path, built on the shared `xiom-core` durable-systems substrate.

## Status

- **MOTE artifact** `xiom.vectors` 0.2.0, stage `incubating` (embedded, in-process tier).
- **Source pin:** xvector `c858ec1` (frozen handoff; lattice-only `api/router.xi`, `api/replica.xi`, `api/httpd.xi` excluded by standing order).
- **Conformance:** `tests/test_conformance.xi` PASS **177/177 x2** on compiler v0.64.7; 45-module library type-check GREEN (carve deviations documented in the carve commit: primitives split `xiom.vector.primitives` for internal imports with the public `xiom.vectors` kept, dangling `xiom.core.ids` import removed, `core.shim` import in schema, `xiom.http 0.1.9` dep, shipped `xiom.toml`).
- **Published:** `0.2.0` in `eco-v0.1.198` (sha256 `130427a5...`, 2026-10-18; owner greenlight received).

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/XIOM-lang/XIOM.git )
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-vector is organized as a **layered engine** rather than a flat set of files. It reuses `xiom-core` (errors, ids, config, limits, contracts, WAL, metrics) as its durable-systems substrate and adds the vector-specific layers on top: types, storage, indexes, query, collections, payload/filtering, segments, durability, and a public API facade.

The engine's working core -- dense-vector math, the three distance metrics, exact flat search + HNSW ANN (multi-layer, tombstone deletes, codec), payload filtering with a sorted key index and a pre/post planner, WAL-backed recovery (vectors + metadata), durable homes (delta segment + fsync-on-ack + atomic checkpoint swap), the multi-collection registry, sealed segment files with roll/union reads and bit-exact compaction, snapshots, and opt-in SQ8 quantization -- is implemented today. The **served tier** (`xvectord`, HTTP wire + sockets) and the **collection-move primitive** are live; the stateless cluster router, replicas, and rebalancing are the current scale-out work (`docs/checklists/lattice-v1.md`). Progress is measured in [`docs/PRODUCTION-READINESS.md`](docs/PRODUCTION-READINESS.md).

See:
- [`ARCHITECTURE.md`](ARCHITECTURE.md) -- the shared-core + vector-layer model, module tree, write/search paths, failure domains.
- [`ROADMAP.md`](ROADMAP.md) -- the Phase 0-10 plan and honest status of every capability.
- [`COLLECTIONS.md`](COLLECTIONS.md) -- the user-facing collection schema model.
- [`SPEC.md`](SPEC.md) -- module-by-module reference.
- [`docs/`](docs/) -- deep dives (engine, core-vs-vector, metrics, HNSW, segments, filtering, query execution, contracts, errors).

## Product tiers (codenames)

Two tiers of the same engine -- **one engine, one on-disk format, two deployment shapes**. A lattice shard serves the exact files a mote writes (same WAL, manifest, segments, identical results): develop embedded, deploy served, no migration. Naming decision: [`docs/PRODUCT-LAYERS.md`](docs/PRODUCT-LAYERS.md); architecture: [`docs/PRODUCT-ARCHITECTURE.md`](docs/PRODUCT-ARCHITECTURE.md).

| Tier | Codename | Shape | Usage | Highlights |
|---|---|---|---|---|
| 1 -- embedded | **xvector-mote** | library, in-process -- no socket, no daemon | link the engine (`xiom.vector.engine` facade) or the registry package `xiom.vectors`; optional in-process HTTP handler (`http_service_handle_cfg`) when an embedded service surface is wanted; quickstart in [`docs/MOTE-QUICKSTART.md`](docs/MOTE-QUICKSTART.md) | exact flat search + HNSW ANN, filters + payload index + planner, range/pagination/batch/delete-by-filter, multi-collection registry, WAL durability + recovery, sealed segments + roll/union reads, snapshots, opt-in SQ8 quantization |
| 2 -- scale-out | **xvector-lattice** | served daemon `xvectord` + stateless router (L-3 router + L-4 replicas + L-5 move/drain landed) + intra-collection scatter-gather (L-6, phase B) | run `xvectord` on the wire (HTTP/1.1 over sockets), shard by collection across single-writer homes, route through the stateless router; ops runbook in [`docs/OPERATIONS.md`](docs/OPERATIONS.md) | everything mote has, plus: wire service, API keys (read/write/admin scopes), request limits, token-bucket rate limiting, `/metrics` + log ring, durable modes (`XVECTORD_WAL` delta segment + checkpoint/seal policies), the collection move primitive (`export_collection`/`attach_segment`), per-collection routing (router v1: versioned mapping file + retry-on-404 stale-mapping recovery; L-4 async replicas: file-ship catch-up + manual promotion, `/stats` replica_lag; L-5: online move + drain, compaction-aware, move-under-load gated; the socket transport follows the `xiom.http` client half) |

Both tiers run the same `src/` tree -- a lattice node IS a mote plus transport, cluster wiring, and ops (no forked format, no divergent numeric behavior; the shared suite + gates cover both). Shards stay single-writer per home; consistency is the engine's (WAL-before-ack, atomic manifest switch, tombstone shadowing); routing is stateless (any router instance can serve any request). Codenames label the tiers in docs, release notes, and owner-facing material; technical identifiers stay stable (`xiom.vectors`, `xvectord`, the home format). Registry-tier naming follows the ecosystem convention (mote = registry tier; lattice = standalone).

**Release ownership:** mote publishes as a registry package through the packages lane (relay-coordinated, owner-gated); lattice releases ship as an ops-owned GitHub Actions release set.

**Try the served tier:**

```bash
.\scripts\build.ps1 src\api\httpd.xi -Name xvectord     # Windows
bash scripts/build.sh src/api/httpd.xi xvectord         # WSL
./out/xvectord --port 7707                              # in-memory; XVECTORD_WAL=<path> for a durable home
curl http://127.0.0.1:7707/health
curl -X POST http://127.0.0.1:7707/collections -d '{"name":"docs","dim":4,"metric":"cosine"}'
curl -X POST http://127.0.0.1:7707/search -d '{"collection":"docs","vector":[1,0,0,0],"top_k":1}'
```

## Installation
```bash
xiom install xiom-vector
```

## Quick Start
```xiom
use xiom.vector.engine;
use xiom.vector.engine.core;
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
  var hits = search(&eng, &q, 5);   // Result[SearchHits, CoreError]
  return 0;
}
```

## Module Tree

```
src/
|-- core/shim.xi              xiom-core stand-ins (CoreError/ids/metrics/predicates)
|-- error.xi                  VectorError taxonomy (-> CoreError)
|-- ids.xi                    PointId + reuse of core Collection/Vector/SegmentId
|-- engine.xi                 public facade (create/upsert/search/delete/payloads)
|-- engine/core.xi            VectorEngine orchestrator (real dispatch)
|-- types/                    dense_vector - metric - neighbor - dimension
|-- collection/               schema - collection - validator
|-- payload/                  payload (+ sorted key index) - filter_ast - filter_eval
|-- storage/                  vector_store - id_map
|-- segment/                  segment_state - segment - manifest - segment_file (sealed codec)
|-- index/                    ann_index - flat_index - hnsw (+ codec, recall harness)
|-- distance/                 cosine - dot - l2
|-- query/                    search_request - filter_plan - topk_heap - search_service - pagination
|-- durability/               wal - recovery - write_ahead_events - wal_file - manifest_file
`-- api/                      vector_api (merged stub) - http_service (HTTP/1.1 byte pipeline) - router (L-3 stateless router)
`-- observability/            metrics (histogram - counters - log ring)
```

## Public API (`xiom.vector.engine` facade; `engine_*` internals in `xiom.vector.engine.core`)

| Function | Description |
|----------|-------------|
| `create_collection(eng, dim, metric)` | Create the active collection; fixes dimension + metric |
| `create_named_collection(eng, name, dim, metric)` | Create a named collection (1..64 chars of `[A-Za-z0-9_.-]`) with its own store/payloads/index config; makes it active (M-D3) |
| `select_collection` / `drop_collection` / `list_collections` / `collection_count` | Registry ops: switch the active collection, WAL-durable drop, names in creation order, count (M-D3) |
| `set_index(eng, kind, params)` | Select the ANN index: `Flat` (default) or `Hnsw` (validates params, builds the graph from the store) |
| `compact_index(eng)` | Rebuild the ANN graph from live nodes (reclaims tombstones; returns the reclaimed count) |
| `upsert(eng, point, vec)` | WAL-durable insert/update of a point (payload-encoded vector in the record) |
| `upsert_many(eng, ids, vecs)` | Batch upsert: all-or-nothing validation, then WAL-durable per point; returns records applied |
| `search(eng, query, k)` | Exact top-k nearest neighbours; returns `Result[SearchHits, CoreError]` (`SearchHits { items: Vec[SearchResult] }`) |
| `search_many(eng, queries, k)` | Batch search: one result set per query in order (`BatchHits`); validates all queries first |
| `delete_point(eng, point)` | Remove a point |
| `delete_many(eng, ids)` | Batch delete: missing ids skipped; returns the number actually removed |
| `get_point(eng, point)` | Fetch a stored vector by id |
| `set_payload` / `get_payload` | WAL-durable metadata attach/replace and read |
| `search_filtered(eng, query, k, filter)` | Filtered top-k: exact planner scan (Flat) or ANN + matching subset with exact fallback (Hnsw) |
| `search_range(eng, query, radius, limit)` | Exact range search: every point with `distance <= radius` (inclusive), distance-sorted, at most `limit` items (M-Q1) |
| `search_page(eng, query, k, offset)` | Offset pagination: ranks [offset, offset+k) of the (distance asc, id asc) total order; exact on Flat and Hnsw (M-Q3) |
| `search_after(eng, query, k, after_id)` | Cursor pagination: the next k ranks strictly after `after_id` (live vector as cursor; `Err(NotFound)` when it no longer exists) (M-Q3) |
| `delete_filter(eng, filter)` | Selective delete: remove every point matching a typed filter (planner-driven index candidates or scan; WAL-durable per point, tombstones + payload/index cleanup); nothing matching -> Ok(0) (M-Q4) |
| `collection_stats(eng, name)` | Per-collection statistics: config, live points, payloads, Hnsw nodes/tombstones, WAL lsn (parked collections report from their entry; M-Q5) |
| `rebuild_index(eng)` | Admin rebuild of the active collection's index with build/compact stats (Hnsw: tombstones reclaimed; Flat: no-op; M-Q5) |
| `search_with_request(eng, req)` | Request-driven search: top_k/filter/with_payload from a `SearchRequest`; M-Q6 adds `mode` (knn/range), `offset`/`after_id` pagination; returns `Result[HydratedHits, CoreError]` |
| `search_batch_with_request(eng, batch)` | Batch requests (`SearchBatchRequest`): one hydrated result set per request, order preserved, all-or-nothing (M-Q6) |
| `save_manifest(eng, path)` | Persist the whole collection registry (one entry per collection: name/dim/metric/index/params) to a manifest file (whole-file, atomic rename; M-D2/D3) |
| `open_engine(wal, path, dim, metric)` | Open from disk: the manifest file's registry entries override per-collection configs by name; the in-WAL manifests are the migration fallback (M-D2/D3) |
| `seal_segment(eng, seg_id, path)` | Seal the active collection as an immutable segment file (vectors + payloads + Hnsw graph codec; atomic rename; M-D4) |
| `restore_segment(eng, path)` | Restore the active collection from a sealed segment file (cid/dim/metric must match); the WAL is re-checkpointed so a reopen replays it (M-D4) |
| `engine_recover(wal, dim, metric)` (engine.core) | Recovery/reopen: replay a WAL, rebuild the store, continue the log (compacted checkpoint) |

All fallible calls return `Result[T, CoreError]`. The `SearchHits` struct
wrapper is retained deliberately (XVC-C-04 was fixed in v0.64.1; the shape
is zero-cost and stable as public API).

## Production Readiness
| Capability | Status |
|-----------|--------|
| Dense vector math (dot/cosine/euclidean/normalize/...) | [OK] Done |
| Distance metrics + dispatch | [OK] Done |
| Flat exact KNN + exact range search (M-Q1) | [OK] Done |
| In-memory HNSW graph (insert + greedy search) | [OK] Done |
| Bounded top-K heap | [OK] Done |
| Engine orchestration (create/upsert/search/delete) | [OK] Done |
| WAL-before-ack write path | [YELLOW] In progress (WAL-before-ack for upserts + metadata; payload-encoded vectors; recovery replay; whole-file checkpoint with torn-tail-safe load, `durability.wal_file`; durable mode in `xvectord`: delta segment append + fsync-on-ack + atomic checkpoint swap, kill-matrix gated; power-loss fault injection pending) |
| Collections / schema / validator | [YELLOW] In progress (multi-collection registry: create/select/drop/list, per-collection isolation + routed recovery, whole-registry manifest; schema/validator scaffold) |
| Segments + lifecycle state machine | [YELLOW] In progress (sealed-segment codec `segment.segment_file`: vectors + payloads + Hnsw graph + optional SQ section + integrity footer, atomic whole-file persist, torn-tail-safe load, lifecycle Mutable -> Sealing -> Sealed; engine `seal_segment`/`restore_segment` with WAL re-checkpoint; D5-D7 landed: roll/union reads over active + sealed (tombstone shadowing, bit-exact compaction), snapshots, collection move; retention + power-loss injection pending) |
| Payload + metadata filtering | [OK] Done (typed Eq/Range/In/Exists/And/Or/Not + no-payload semantics; sorted key index; pre/post-filter planner with index-driven candidates and multi-key intersections; filtered/ANN integration with exact fallback; delete-by-filter; payload durability + recovery) |
| Durable recovery / manifest | [YELLOW] In progress (WAL replay + compacted checkpoint + in-WAL collection manifest; whole-file WAL persistence via `wal_file`; durable collection registry via `manifest_file` -- atomic rename, torn-tail-safe load, file-wins open with in-WAL fallback; sealed segment files via `segment_file` with engine seal/restore; **`xiom.wal` 0.1.0 registry adoption landed** (alignment gate `probe_package_wal`; migration plan in `docs/XIOM-WAL-ADOPTION.md`); fsync + delta segment + snapshots + multi-segment read path landed; power-loss injection pending) |
| Service surface (HTTP) | [YELLOW] In progress (`api.http_service` -- HTTP/1.1 byte-level pipeline: parse/route/JSON/reply; `/health`, `/version`, `/collections`, points get/upsert/delete, `/search` (knn/range/page/batch), `/stats`, `/metrics`; S2: ServiceConfig limits (request size/top_k/batch/dim; env + key=value file), `{error,kind,status}` model over the full CoreError enum, `http_service_shutdown` checkpoint; S3: API-key auth (constant-time, scopes read/write/admin, `XVECTOR_API_KEYS`) + token-bucket rate limiting (429); S4: fuzz gate + JSON depth guard + SBOM/unsafe gate + `docs/SECURITY.md`; **socket adapter `xvectord` live** on the stdlib `xiom.net` layer (`src/api/httpd.xi`; real-socket gate `probe_http_server` + curl end-to-end; `XVECTORD_*` durable mode + checkpoint/seal policies); gates `probe_http_service` + `probe_service_limits` + `probe_service_auth` + `probe_http_fuzz` + `probe_http_server`; the stateless cluster router (L-3) v1 landed: versioned mapping file + forwarding + retry-on-404 (`src/api/router.xi`; `probe_router_2shards`); cluster admin landed with L-5: `POST /cluster/move` + `POST /cluster/drain` (compaction-aware export + mapping flip; `probe_move_under_load`); L-4 replicas: file-ship catch-up + manual promotion (`src/api/replica.xi`; `probe_replica`), and a durable reopen-then-write loss was found + fixed in-lane (`probe_reopen_write`); the socket transport follows the `xiom.http` client half) |
| Quantization (SQ8) | [OK] Done (Q-a1/Q-a2a: trained per-dim ranges, truncation codec, FAISS-pattern query tables, two-tier rescore; documented error bounds; opt-in SQ section in segment codec v2) |
| IVF / PQ / disk-backed / SIMD | [STOP] Not started (reference studies 01-03 landed; P4 IVF-PQ + P5 disk-resident planned) |

Full detail in [`ROADMAP.md`](ROADMAP.md). The v1.0 production programme
(milestones, ordered slice backlog, benchmark/security/release plans, owner
handoff) is in [`docs/PRODUCTION-PLAN.md`](docs/PRODUCTION-PLAN.md) with the
requirements intake in
[`docs/requirements/production-v1.md`](docs/requirements/production-v1.md).
Measured baseline: [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md) (run
`.\scripts\bench.ps1` / `bash scripts/bench.sh`).

## Dependencies
- `xiom-std` -- standard library
- `xiom.math` -- `sqrt` for magnitude/euclidean/cosine
- `xiom-core` -- shared errors, ids, config, limits, contracts, WAL, metrics

## Links: [github.com/xiom-lang](https://github.com/xiom-lang) | [XIOM](https://github.com/XIOM-lang/XIOM.git )
## License: MIT OR Apache-2.0
