<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# xiom-vector -- Roadmap

A phased plan from the working in-memory engine to a durable, filterable,
distributed vector database. Each phase lists its Goal, Deliverables, Exit
criteria, and why it matters -- with an honest status on every deliverable.

Legend: [OK] **Done** - [YELLOW] **In progress** - [ORANGE] **Scaffold** (types + stub bodies) - [STOP] **Not started**

> **Progress tracking:** `docs/PRODUCTION-READINESS.md` holds the weighted
> percentage-to-production scorecard (updated every wrap). This file is the
> phase plan; that file is the measurement.
>
> **Production programme (2026-10-09):** `docs/PRODUCTION-PLAN.md` is the
> v1.0 flagship execution plan (milestones M-G truth/benchmark, M-D on-disk
> durability, M-Q query surface, M-S server/security, M-O observability,
> M-P performance/scale, M-R release + owner handoff) with the ordered
> slice backlog; `docs/requirements/production-v1.md` is the intake and
> `docs/checklists/production-v1.md` the execution checklist. Phase
> statuses below were refreshed 2026-10-09; sequencing follows the plan.

---

## Phase 0 -- Exact engine (in-memory) [OK] Done

**Goal:** The correctness foundation everything else is measured against.

**Deliverables:**
- [OK] Dense `Vector` type + math (dot, magnitude, normalize, add, sub, scale).
- [OK] Three distance metrics (cosine, dot-product, euclidean) + `vector_distance` dispatch.
- [OK] Flat columnar `VectorIndex` store (add/remove/get/size).
- [OK] Exact brute-force `search_knn` / `search_range` (the truth oracle).
- [OK] Bounded top-K heap with the `len() <= k` invariant.
- [OK] `VectorEngine` orchestrator wiring create/upsert/search/delete.

**Exit criteria:** exact KNN/range results are correct by construction and serve
as the oracle every later index is validated against.

**Why this phase matters:** without a trusted exact baseline there is nothing to
measure approximate recall against; this phase is the source of truth.

## Phase 1 -- Approximate index: HNSW (in-memory) [OK] Done

**Goal:** Sub-linear approximate nearest-neighbour search over the in-memory store.

**Deliverables:**
- [OK] Hierarchical layer graph (`HNSWGraph`, `HNSWLayer`, `HNSWNode`).
- [OK] Randomized level assignment (LCG-based) parameterized by `ml`.
- [OK] `ef`-parameterized greedy descent + layer-0 beam search (multi-layer).
- [OK] Bidirectional edge maintenance bounded by `max_neighbors`.
- [OK] Beam construction honouring `ef_construction` + diversified pruning (`select_diverse`); metric-agnostic traversal.

**Exit criteria:** HNSW returns high-recall results with `result.len() <= k`, with
the structural gaps tracked into Phase 4.

**Why this phase matters:** exact search does not scale to large collections;
HNSW is the general-purpose ANN the rest of the engine is built around. See
[`docs/hnsw-design.md`](docs/hnsw-design.md).

## Phase 2 -- Durability & recovery [YELLOW] In progress

**Goal:** Crash-safe writes -- no acknowledged write is ever lost.

**Deliverables:**
- [YELLOW] WAL-before-ack write path wired through the in-memory WAL (LSNs assigned).
- [OK] `durability.write_ahead_events` maps upsert/delete/seal onto `WalOpKind`
  (record layout: key = point id, value = collection id).
- [OK] Serialize dense vector bytes into `WalRecord.payload`
  (`vector_encode`/`vector_decode`: `[dim, Float64-bits...]`, exact via
  `xiom.num.float`; malformed payloads -> None).
- [STOP] `fsync`/`fdatasync` on commit -- **blocked on the stdlib fd-syscall
  gap** (`xiom.os.fs_ffi.fsync` is a documented-Err stub; see
  `docs/STDLIB-WISHLIST-XVECTOR.md`). `wal_writer_flush` remains an
  in-memory LSN marker.
- [OK] Recovery: replay the WAL into a fresh store, rebuild indexes
  (`recover_store`), then write a compacted checkpoint log so the recovered
  engine is itself recoverable (`wal_writer_checkpoint_from`, `engine_recover`).
  Torn/malformed payloads are skipped; LSNs stay monotonic.
- [OK] Durable metadata (Phase 3 crossover): payloads are WAL-encoded
  (`payload_encode`/`payload_decode`, `WalOpKind.Update` records) and replayed
  by `recover_state`; the checkpoint log carries them, so chained reopen keeps
  metadata.
- [OK] Whole-file WAL checkpoint on disk (`durability.wal_file`:
  `wal_persist` + torn-tail-safe `wal_load`; gate `probe_wal_file`) --
  atomic temp+rename hardening landed (M-D1).
- [OK] In-WAL collection manifest (`ManifestUpdate` records) -- dim/metric/
  index kind/params survive `engine_recover` and checkpoints.
- [OK] Durable collection registry file (`durability.manifest_file`, M-D2):
  `xvector-manifest 1` text registry (name/dim/metric/index/params per
  entry), whole-file persist with atomic temp+rename, torn-tail-safe load;
  `engine_manifest_save` + `engine_recover_file`/`open_engine` prefer the
  file registry and fall back to the in-WAL manifest (migration). Gate
  `probe_manifest_file` (38 checks).
- [OK] Multi-collection registry (M-D3): named collections with
  create/select/drop/list, per-collection isolation (stores, payloads,
  index configs) and routed WAL recovery (v2 config / v3 drop records;
  data records carry the collection id); whole-registry manifest save +
  file-wins open by name. Gate `probe_collections` (41 checks).
- [OK] Sealed segment files (M-D4): `segment.segment_file` codec (vectors +
  payloads + Hnsw graph codec; atomic whole-file persist; torn-tail-safe
  complete-record prefix load; lifecycle Mutable -> Sealing -> Sealed) plus
  engine `seal_segment`/`restore_segment` (cid/dim/metric validated; WAL
  re-checkpoint after restore). Gate `probe_segment_file` (38 checks).
  Multi-segment read path + retention stay D5/D6.
- [STOP] Delta append + `fsync` on commit -- **blocked on the stdlib
  fd-syscall gap** (re-checked 2026-10-09 on 0.64.3; see
  `docs/STDLIB-WISHLIST-XVECTOR.md`). `wal_writer_flush` remains an
  in-memory LSN marker. Gated slice D5.

**Exit criteria:** a process kill mid-write loses no acknowledged data; recovery
replays the WAL to `manifest.last_lsn` and reconstructs identical indexes.

**Why this phase matters:** a database that can lose acknowledged writes is not a
database; durability is the line between a cache and a store of record.

**Session evidence (2026-10-08):** 8 codec/recovery conformance tests
(`test_codec_*`, `test_recover_*`) + the critical-primitive probe
`tests/probes/probe_vector_store.xi` (create -> upsert -> search -> reopen ->
search-identical -> delete -> reopen-again -> LSN continuity) green x2 on
Windows and WSL. The WAL is still in-memory; file-backed segments wait on the
stdlib fsync/append primitives.

## Phase 3 -- Payload & metadata filtering [OK] Done

**Goal:** Filtered search (`search WHERE color = 'red' AND price IN [..]`).

**Deliverables:**
- [OK] `Payload` container + `FieldValue` tagged union (+ `payload_get`, overwrite semantics on `payload_set`).
- [OK] `FilterExpr` AST (Eq/Range/Exists/In/And/Or/Not) + constructors.
- [OK] `filter_eval`: full typed evaluation (Eq within-type exact; Range inclusive with Int->Float32 promotion; In membership; Exists) + no-payload semantics (value predicates false; `Not` true).
- [OK] Engine integration: `PayloadStore` (id -> payload, swap-remove), `engine_set_payload` / `engine_get_payload`, `search_filtered` / `engine_search_filtered` (pre-filter exact scan, `k`-bounded), delete removes metadata.
- [OK] Sorted key index for O(log n) field lookup (exists/count/Eq/Range windows).
- [OK] Pre/post-filter planner by selectivity + index-driven candidates + compound And-of-indexable intersections.

**Exit criteria:** filtered KNN returns only matching points, and the planner
chooses pre- vs post-filter by selectivity without changing results.

**Why this phase matters:** real workloads combine similarity with structured
constraints; vector search without metadata filtering is only half a query engine.
See [`docs/metadata-filtering.md`](docs/metadata-filtering.md).

**Session evidence (2026-10-08):** 30 new conformance tests (SECTION 14/15)
-> **166/166 x2** on Windows and WSL; `tests/probes/probe_filtered_search.xi`
and `tests/probes/probe_payload_recovery.xi` green x2 (engine-import units:
Range/Eq/In/And/Not/Exists, delete cleanup, k bound; WAL-before-ack for
metadata, payload replay, chained reopen, torn record skip). Payloads are
WAL-durable, FloatVal included (float gates restored after the v0.64.1 fix
of XVC-C-06; the FloatVal roundtrip pin probe guards it).

## Phase 4 -- HNSW hardening [OK] Done

**Goal:** Turn the simplified HNSW into a production-grade, tunable index.

**Deliverables:**
- [OK] Diversified neighbour selection/pruning (`select_diverse`).
- [OK] `ef_construction` / `ef_search` beam widths honoured from `AnnParams`.
- [OK] Delete + tombstone handling in the graph (routers kept, revive on re-insert, `hnsw_compact`).
- [OK] Recall/latency benchmarks vs the flat oracle (per-ef visited/recall table, build-work proxy).
- [OK] Engine wiring, strict graph codec (`hnsw_encode/decode`), sorted id map, update re-linking.
- [OK] Reference study 01 (FAISS): generous level-0 degree (`m0 = 2*m` + FAISS `prune_headroom` 0.2), codec v3, hard-corpus control gate (`probe_hnsw_recall`).

**Exit criteria:** recall@k meets targets against the flat oracle across the
tuning ranges, and `ef`/`M` parameters measurably move recall and latency.
**Met** (n=200: 300/300 at ef=64; n=800: 200/200; P-a hard corpus
285/300 vs 275/300 legacy control; after delete/compaction
and 60 in-place updates 200/200; gates `probe_hnsw_recall`,
`probe_engine_hnsw`, `probe_hnsw_codec`).

**Why this phase matters:** the Phase 1 graph is correct but simplified; this
phase is where recall, tunability, and deletes become production-ready.

## Phase 5 -- Segments & compaction [YELLOW] In progress

**Goal:** Bounded-memory, LSM-style vector storage.

**Deliverables:**
- [ORANGE] `SegmentStateKind` state machine (Mutable->Sealing->Sealed->Indexing->Immutable->Compacting->Dropped).
- [ORANGE] `Segment` wrapping a store + state; `Manifest` of live segments.
- [STOP] Seal-on-threshold -> build an immutable HNSW for the sealed segment.
- [STOP] Multi-segment search fan-out + merge into one top-K heap.
- [STOP] Background compaction of small/immutable segments.
- [ORANGE] `id_map` for stable ids across compaction (present, linear scan).

**Exit criteria:** writes seal into immutable indexed segments, search fans out
and merges correctly, and compaction reclaims space without losing data.

**Why this phase matters:** a single unbounded mutable store cannot be immutably
indexed while being written; segments make memory bounded and indexing possible.
See [`docs/segment-lifecycle.md`](docs/segment-lifecycle.md).

## Phase 6 -- Public API surface [OK] Done (v1 shape)

**Goal:** A stable public interface over the engine.

**Deliverables:**
- [OK] `vector_api` facade: `create_collection`, `upsert`, `search`, `delete_point`, `get_point`.
- [OK] `search` returns `Result[SearchHits, CoreError]` where
  `SearchHits { items: Vec[SearchResult] }` -- the struct wrapper is
  retained deliberately (XVC-C-04 fixed in v0.64.1; zero-cost public API
  shape); unwrapping is a future API decision, not a compiler need.
- [OK] Batch upsert / batch search (`upsert_many` / `search_many` /
  `delete_many` + `BatchHits`, M-Q2).
- [OK] Pagination (M-Q3): `search_page` (offset) + `search_after` (after-id
  cursor) over the (distance asc, id asc) total order; exact on Flat and
  Hnsw; gate `probe_pagination` (22 checks).
- [OK] Delete-by-filter (M-Q4): `delete_filter` -- planner-driven selective
  delete (index candidates or scan), WAL-durable per point with tombstones
  and payload/index cleanup; gate `probe_delete_filter` (26 checks).
- [OK] Index admin (M-Q5): `collection_stats` (per-collection config +
  counts + graph occupancy + lsn) and `rebuild_index` (admin rebuild with
  before/after/reclaimed stats); gate `probe_index_admin` (20 checks).
- [OK] Request extensions (M-Q6): `SearchRequest` carries mode (knn/range),
  radius, and offset/after-id pagination; `SearchBatchRequest` +
  `search_batch_with_request` (ordered, all-or-nothing); gate extended
  `probe_search_request` (24 checks).
- [OK] Reference-oracle cross-check (M-G1): independent Float64 oracle vs
  the three kernels (pairwise deviations at Float32-ulp scale), metric
  axioms, and the ranked/paged/cursor/range/Hnsw search paths on seeded
  vectors; gate `probe_reference_oracle` (22 checks).
- [OK] HTTP service skeleton (M-S1): `api.http_service` -- transport-
  agnostic HTTP/1.1 byte pipeline (strict parse, router, stdlib-JSON wire,
  honest statuses); `/health`, `/collections`, points CRUD, `/search`
  (knn/range/page/batch), `/stats`. Socket adapter gated on the stdlib
  `xiom.net` proof (C-PULSE-02). Gate `probe_http_service` (40 checks).
- [OK] Service config/limits/errors (M-S2): `ServiceConfig` (defaults +
  env `XVECTOR_MAX_*` + key=value file), enforced limits (413 size/batch,
  400 named top_k/dim), the `{error,kind,status}` model over the full
  `CoreError` enum, and `http_service_shutdown` (drain + WAL checkpoint).
  Gate `probe_service_limits` (27 checks).
- [OK] Service auth + rate limiting (M-S3): API keys via `x-api-key`
  (constant-time compare, scopes read/write/admin, env
  `XVECTOR_API_KEYS`), 401/403 kinds, `/health` public, token-bucket
  `RateLimiter` with 429; `ServiceState` + `http_service_handle_state`.
  Gate `probe_service_auth` (24 checks).
- [OK] Security pass (M-S4): `docs/SECURITY.md` (threat model + secure
  defaults + no-unsafe audit); fuzz + resource-exhaustion gate
  (`probe_http_fuzz`, 2500 deterministic inputs) with the JSON depth
  guard fixing a found stack-overflow DoS; SBOM + unsafe gate
  (`scripts/sbom.ps1`/`sbom.sh`) wired into both batteries.
- [OK] Observability surfaces (M-O): `observability.metrics` (counters +
  fixed-bucket latency histograms + bounded JSON log ring), public
  `GET /metrics` (prometheus text + live gauges), `/health` readiness,
  per-request instrumentation; `docs/OPERATIONS.md` runbook; gate
  `probe_metrics` (23 checks).
- [OK] First registry-package adoption (2026-10-10): `xiom.wal` 0.1.0
  consumed from the registry (`xiom.toml [dependencies]`; C-PULSE-02
  resolved in v0.64.2; sha256/ed25519 verified + `xiom pkg trust` pin);
  op codes 1..7 byte-identical; gate `probe_package_wal` (9 checks);
  migration plan `docs/XIOM-WAL-ADOPTION.md`. Next adoptions queued:
  `xiom.metrics` 0.2.0 -> `xiom.rate` 0.2.0 -> `xiom.router`/`xiom.http`.
- [STOP] `get_point` via id_map + manifest once multi-segment lands.

**Exit criteria:** the v1 facade covers the full single-collection lifecycle;
batch and multi-segment paths are wired as later layers land.

**Why this phase matters:** a clean, stable surface decouples callers from
internal churn and is the contract external clients depend on.

## Phase 7 -- Hybrid search [STOP] Not started

**Goal:** Combine dense vector similarity with sparse/lexical scoring.

**Deliverables:**
- [STOP] Sparse/keyword scoring alongside dense ANN.
- [STOP] Score fusion (RRF / weighted) between dense and sparse hits.

**Exit criteria:** a hybrid query returns a single fused ranking that beats
either dense-only or lexical-only on the target workload.

**Why this phase matters:** dense vectors miss exact-keyword intent and lexical
misses semantics; hybrid ranking is what production search actually needs. See
[`docs/future-modules.md`](docs/future-modules.md).

## Phase 8 -- Distribution [STOP] Not started

**Goal:** Scale beyond a single node with explicit consistency and failure behavior.

**Deliverables:**
- [STOP] Sharding by `ShardId` (already in `core.ids`).
- [STOP] Replication + read routing.
- [STOP] Distributed manifest / consensus for segment visibility.

**Exit criteria:** searches fan out across shards and merge globally-ranked top-K
correctly; replica lag and consistency mode are visible and testable; rebalance
never corrupts manifests or loses acknowledged data.

**Why this phase matters:** past a single node's capacity, scaling requires
distribution that never blurs what a result means. See
[`docs/sharding-and-replication.md`](docs/sharding-and-replication.md).

## Phase 9 -- IVF / PQ (billion-scale) [STOP] Not started

**Goal:** Memory-efficient serving for very large collections.

**Deliverables:**
- [STOP] IVF (inverted file) index behind `AnnIndexKind.Ivf` (dispatch seam already exists).
- [STOP] Product Quantization for memory-efficient vectors.
- [STOP] Disk/mmap-backed segments.

**Exit criteria:** IVF/PQ serves far more vectors per node than HNSW at an
acceptable recall/latency tradeoff, with parameters validated against collection
size.

**Why this phase matters:** past a certain scale HNSW's graph memory dominates;
IVF/PQ is the tier that makes billion-scale serving economical. See
[`docs/ivf-roadmap.md`](docs/ivf-roadmap.md).

## Phase 10 -- Hardening & performance [STOP] Not started

**Goal:** Production-grade performance, correctness verification, and observability.

**Deliverables:**
- [STOP] SIMD/FMA distance kernels in `distance/` (call-site seam already in place).
- [STOP] Fuzz + property tests (ANN recall bounds, WAL replay determinism).
- [STOP] Observability: histograms for latency/recall via `core.metrics`.

**Exit criteria:** hot-loop distance is SIMD-accelerated, invariants hold under
fuzzing, and latency/recall are observable in production via metrics.

**Why this phase matters:** correctness and speed must be provable and visible,
not assumed; this phase turns a working engine into an operable one.

---

## Status summary

| Layer | Status |
|-------|--------|
| Vector math + metrics | [OK] Done |
| Flat exact search + top-K | [OK] Done |
| In-memory HNSW | [OK] Done |
| Engine orchestration + API facade | [OK] Done |
| WAL write path | [YELLOW] In progress -- whole-file checkpoint + torn-tail load done; delta/fsync gated on stdlib |
| Collections / schema / validator | [YELLOW] In progress -- multi-collection registry (M-D3: create/select/drop/list, routed recovery, whole-registry manifest); schema/validator scaffold |
| Payload + filtering | [OK] Done |
| Segments + manifest + recovery | [YELLOW] In progress -- sealed-segment codec + engine seal/restore done (M-D4); multi-segment read path + retention are D5/D6 |
| IVF / PQ / disk / SIMD / distributed | [STOP] v1.1/v2 per the production plan |

## Milestone summary

| Phase | Theme | Primary outcome |
|-------|-------|-----------------|
| 0 | Exact engine | Trusted exact KNN/range oracle in memory. |
| 1 | HNSW ANN | Sub-linear approximate search. |
| 2 | Durability | Crash-safe, no acknowledged write lost. |
| 3 | Filtering | Similarity + structured metadata constraints. |
| 4 | HNSW hardening | Tunable, production-grade recall + deletes. |
| 5 | Segments | Bounded-memory LSM storage + compaction. |
| 6 | Public API | Stable external surface over the engine. |
| 7 | Hybrid search | Fused dense + lexical ranking. |
| 8 | Distribution | Multi-node fan-out with explicit consistency. |
| 9 | IVF / PQ | Memory-efficient billion-scale serving. |
| 10 | Hardening | SIMD, fuzz/property tests, observability. |

## Implementation cadence

- **Alpha** -- Phases 0-2: exact engine, HNSW, durability. The engine is correct
  and crash-safe in memory.
- **Beta** -- Phases 3-5: filtering, HNSW hardening, segments. The engine is
  feature-complete for single-node production shape.
- **Production candidate** -- Phases 6-8: public API, hybrid search, distribution.
  The engine is externally usable and horizontally scalable.
- **Scale / harden** -- Phases 9-10: IVF/PQ and performance hardening. The engine
  serves billion-scale workloads and is fully observable.

## Success metrics

- **Correctness** -- approximate results validated against the exact flat oracle;
  invariants (`len() <= k`, WAL replay determinism) hold under fuzzing.
- **Recall@k** -- approximate recall meets targets across the tuning ranges for
  each index.
- **Latency** -- p50 / p95 / p99 query latency measured against target workloads.
- **Memory per vector** -- bytes per stored vector, the key economic lever for the
  IVF/PQ scale tier.
- **Operability** -- recovery time, rebalance safety, and metrics/observability
  coverage in production.

---

## Test coverage (`tests/test_conformance.xi`)

> **Historical snapshot** (the table below counts 136 tests as of
> 2026-10-08). Current: **169 checks** (the v0.64.2 re-test restored the
> hydration mirror test) + **18 probes** x2 on Windows + WSL. See
> `tests/test_conformance.xi` and `tests/probes/`.

| # | Category | Tests | Coverage |
|---|----------|-------|----------|
| 1 | Types (VectorId, CollectionId, SegmentId, Dimension) | 7 | construction, eq, validation |
| 2 | Distance metrics (L2, cosine, dot product) | 15 | identical, orthogonal, opposite, magnitude, dispatch |
| 3 | Vector store (insert, search, delete) | 8 | CRUD, duplicates, misses, multi-add |
| 4 | HNSW index (AnnParams) | 6 | validation bounds, default values (graph has T001 errors per AUDIT.md) |
| 5 | Flat index (brute-force KNN) | 4 | top-1, bounded k, ordering, all 3 metrics |
| 6 | Segment management (state machine, manifest) | 13 | full lifecycle transitions, illegal moves, writable, terminal, manifest CRUD |
| 7 | Collection (schema, validation, CRUD) | 9 | creation, normalization, fields, registration, dimension/metric validation |
| 8 | Payload (filter AST, evaluation) | 14 | set/has/len, FieldValue kinds, Eq/Exists/And/Or/Not combinators |
| 9 | Search (top-K heap, engine orchestration) | 15 | bounded push, sorted invariant, is_full, worst, upsert/search/delete lifecycle, SearchHits payload shape (XVC-C-04 guard) |
| 10 | ANN index (type dispatch) | 3 | AnnIndexKind names, variant discrimination, params on Collection |
| 11 | Error types (VectorError) | 8 | all 6 variants: codes (1001-1006), to_str, uniqueness |
| 12 | Durability (WAL, Counter, IdMap) | 16 | append, LSN tracking, flush, before-ack contract, counter increment, id_map CRUD |
| 13 | Durable codec + recovery replay (Phase 2) | 10 | encode/decode roundtrip + bit exactness + malformed rejection; WAL insert/delete replay; post-reopen search identical; LSN monotonicity; chained reopen; torn payload tolerated |
| -- | Boundary / validation | 7 | is_valid_dimension, is_valid_top_k, empty search, Float32 approx, SearchRequest fields |

### Contract status

**22 contracts (requires/ensures)** applied to helper functions in the test file.
These mirror the contracts in `engine/core.xi` and the standalone modules.
Note the contract style: a runtime `requires` violation aborts the process
(exit 1 since the v0.64.1 fix; it exited 0 on v0.64.0), so the suite must
never call a contracted function out of contract (the invalid-dimension test
exercises the `is_valid_dimension` predicate instead).

Functions with contracts (20 functions, 22 clauses):
- `vector_new` : `requires: dim > 0`
- `vector_set` : `requires: index >= 0 && index < v.dimension`
- `vector_get` : `requires: index >= 0 && index < v.dimension`
- `vector_dot` : `requires: a.dimension == b.dimension`
- `dot_product_distance` : `requires: a.dimension == b.dimension`
- `cosine_distance` : `requires: a.dimension == b.dimension`
- `euclidean_distance` : `requires: a.dimension == b.dimension`
- `vector_distance` : `requires: a.dimension == b.dimension`
- `index_new` : `requires: dim > 0`
- `index_add` : `requires: idx.dim == vec.dimension`
- `search_knn` : `requires: k > 0`, `requires: idx.dim == query.dimension`, `ensures: result.len() <= k`
- `segment_new` : `requires: dim > 0`
- `segment_insert` : `requires: seg.store.dim == vec.dimension`
- `engine_create_collection` : `requires: dim >= 1`
- `schema_new` : `requires: is_valid_dimension(dimension)`
- `topk_new` : `requires: capacity > 0`
- `topk_push` : `requires: h.capacity > 0`
- `dimension` : `requires: v >= 1`
- `recover_store` : `requires: dim > 0`
- `engine_recover` : `requires: dim > 0`

### Contract gap analysis

Functions in source modules that lack `requires`/`ensures` contracts:

| Module | Functions missing contracts |
|--------|---------------------------|
| `engine.xi` (facade) | All 8 facade functions (thin delegations to engine.core) |
| `engine/core.xi` | `engine_new`, `engine_upsert`, `engine_search`, `engine_delete`, `engine_set_payload`, `engine_get_payload`, `engine_search_filtered`, `engine_get_point`, `engine_size`, `engine_durable_lsn` |
| `core/shim.xi` | `counter_new`, `counter_inc`, `collection_id`, `vector_id`, `vector_id_value`, `segment_id`, `segment_id_eq`, `is_valid_dimension`, `is_valid_top_k` |
| `types/dense_vector.xi` | `vector_magnitude` (+ normalize/add/sub/scale when implemented) |
| `types/neighbor.xi` | `neighbor_new` |
| `storage/vector_store.xi` | `index_remove`, `index_get`, `index_size`, `vector_encode`, `vector_decode` |
| `durability/wal.xi` | `wal_writer_new`, `wal_writer_append`, `wal_writer_append_payload`, `wal_writer_resume`, `wal_writer_current_lsn`, `wal_writer_flush` |
| `durability/recovery.xi` | `wal_writer_checkpoint_from` |
| `durability/write_ahead_events.xi` | `log_upsert`, `log_delete`, `log_payload_set` |
| `error.xi` | `vector_error_to_str`, `vector_error_to_core`, `vector_error_code` |
| `ids.xi` | `point_id`, `point_id_value`, `point_id_eq`, `point_to_vector_id`, `vector_to_point_id` |
| `ann_index.xi` | `ann_params_default`, `ann_params_valid`, `ann_index_kind_name` |
| `search_request.xi` | `search_request_set_filter`, `search_request_has_filter`, `search_request_top_k` |
| `topk_heap.xi` | `topk_len`, `topk_is_full`, `topk_worst` |
| `filter_ast.xi` | All 7 filter constructors |
| `filter_eval.xi` | `filter_matches` |
| `payload.xi` | `payload_new`, `payload_set`, `payload_has`, `payload_len`, `field_value_kind` |
| `segment_state.xi` | `segment_state_is_writable`, `segment_state_is_terminal`, `segment_state_code`, `segment_state_can_transition` |
| `segment.xi` | `segment_transition`, `segment_size`, `segment_is_writable` |
| `manifest.xi` | All 5 manifest functions |
| `collection.xi` | All 5 collection functions |
| `validator.xi` | All 3 validator functions |
| `schema.xi` | `schema_set_normalization`, `schema_add_field`, `schema_dimension` |
| `id_map.xi` | All 5 id_map functions |

**Recommendation:** Add `requires` contracts to dimension-validating entry points and `ensures` contracts to result-producing functions. Priority: `segment_state_can_transition` (ensures deterministic transitions), `index_get`/`index_remove` (ensures option/result correctness), `filter_matches` (ensures deterministic evaluation).
