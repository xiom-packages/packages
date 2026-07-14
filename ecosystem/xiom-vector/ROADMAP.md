# xiom-vector — Roadmap

A phased plan from the working in-memory engine to a durable, filterable,
distributed vector database. Each phase lists its Goal, Deliverables, Exit
criteria, and why it matters — with an honest status on every deliverable.

Legend: ✅ **Done** · 🟡 **In progress** · 🟠 **Scaffold** (types + stub bodies) · ⛔ **Not started**

---

## Phase 0 — Exact engine (in-memory) ✅ Done

**Goal:** The correctness foundation everything else is measured against.

**Deliverables:**
- ✅ Dense `Vector` type + math (dot, magnitude, normalize, add, sub, scale).
- ✅ Three distance metrics (cosine, dot-product, euclidean) + `vector_distance` dispatch.
- ✅ Flat columnar `VectorIndex` store (add/remove/get/size).
- ✅ Exact brute-force `search_knn` / `search_range` (the truth oracle).
- ✅ Bounded top-K heap with the `len() <= k` invariant.
- ✅ `VectorEngine` orchestrator wiring create/upsert/search/delete.

**Exit criteria:** exact KNN/range results are correct by construction and serve
as the oracle every later index is validated against.

**Why this phase matters:** without a trusted exact baseline there is nothing to
measure approximate recall against; this phase is the source of truth.

## Phase 1 — Approximate index: HNSW (in-memory) ✅ Done

**Goal:** Sub-linear approximate nearest-neighbour search over the in-memory store.

**Deliverables:**
- ✅ Hierarchical layer graph (`HNSWGraph`, `HNSWLayer`, `HNSWNode`).
- ✅ Randomized level assignment (LCG-based) parameterized by `ml`.
- ✅ Greedy descent search + brute-force in-layer neighbour selection.
- ✅ Bidirectional edge maintenance bounded by `max_neighbors`.
- 🟡 Remaining: heuristic neighbour pruning, `ef`-parameterized beam search,
  metric-agnostic traversal (currently euclidean internally).

**Exit criteria:** HNSW returns high-recall results with `result.len() <= k`, with
the structural gaps tracked into Phase 4.

**Why this phase matters:** exact search does not scale to large collections;
HNSW is the general-purpose ANN the rest of the engine is built around. See
[`docs/hnsw-design.md`](docs/hnsw-design.md).

## Phase 2 — Durability & recovery 🟡 In progress

**Goal:** Crash-safe writes — no acknowledged write is ever lost.

**Deliverables:**
- 🟡 WAL-before-ack write path wired through `core.wal.wal_writer` (LSNs assigned).
- 🟠 `durability.write_ahead_events` maps upsert/delete/seal onto core `WalOpKind`.
- ⛔ Serialize dense vector bytes into `WalRecord.payload`.
- ⛔ `fsync`/`fdatasync` on commit (blocked on core FFI, Phase 2 of xiom-core).
- ⛔ Recovery: replay WAL to `manifest.last_lsn`, rebuild in-memory indexes.
- 🟠 Durable `manifest` (`ManifestUpdate` records) — types exist, not persisted.

**Exit criteria:** a process kill mid-write loses no acknowledged data; recovery
replays the WAL to `manifest.last_lsn` and reconstructs identical indexes.

**Why this phase matters:** a database that can lose acknowledged writes is not a
database; durability is the line between a cache and a store of record.

## Phase 3 — Payload & metadata filtering 🟠 Scaffold

**Goal:** Filtered search (`search WHERE color = 'red' AND price IN [..]`).

**Deliverables:**
- 🟠 `Payload` container + `FieldValue` tagged union.
- 🟠 `FilterExpr` AST (Eq/Range/Exists/In/And/Or/Not) + constructors.
- 🟠 `filter_eval`: And/Or/Not/Exists implemented; Eq/Range/In are fail-open stubs.
- ⛔ Typed value comparison + sorted key index for O(log n) field lookup.
- ⛔ Pre-filter vs post-filter planner (filter before/after ANN by selectivity).

**Exit criteria:** filtered KNN returns only matching points, and the planner
chooses pre- vs post-filter by selectivity without changing results.

**Why this phase matters:** real workloads combine similarity with structured
constraints; vector search without metadata filtering is only half a query engine.
See [`docs/metadata-filtering.md`](docs/metadata-filtering.md).

## Phase 4 — HNSW hardening ⛔ Not started

**Goal:** Turn the simplified HNSW into a production-grade, tunable index.

**Deliverables:**
- ⛔ Heuristic neighbour selection (RNG pruning) for better recall.
- ⛔ `ef_construction` / `ef_search` beam widths honoured from `AnnParams`.
- ⛔ Delete + tombstone handling in the graph.
- ⛔ Recall/latency benchmarks vs the flat oracle.

**Exit criteria:** recall@k meets targets against the flat oracle across the
tuning ranges, and `ef`/`M` parameters measurably move recall and latency.

**Why this phase matters:** the Phase 1 graph is correct but simplified; this
phase is where recall, tunability, and deletes become production-ready.

## Phase 5 — Segments & compaction 🟠 Scaffold

**Goal:** Bounded-memory, LSM-style vector storage.

**Deliverables:**
- 🟠 `SegmentStateKind` state machine (Mutable→Sealing→Sealed→Indexing→Immutable→Compacting→Dropped).
- 🟠 `Segment` wrapping a store + state; `Manifest` of live segments.
- ⛔ Seal-on-threshold → build an immutable HNSW for the sealed segment.
- ⛔ Multi-segment search fan-out + merge into one top-K heap.
- ⛔ Background compaction of small/immutable segments.
- 🟠 `id_map` for stable ids across compaction (present, linear scan).

**Exit criteria:** writes seal into immutable indexed segments, search fans out
and merges correctly, and compaction reclaims space without losing data.

**Why this phase matters:** a single unbounded mutable store cannot be immutably
indexed while being written; segments make memory bounded and indexing possible.
See [`docs/segment-lifecycle.md`](docs/segment-lifecycle.md).

## Phase 6 — Public API surface ✅ Done (v1 shape)

**Goal:** A stable public interface over the engine.

**Deliverables:**
- ✅ `vector_api` facade: `create_collection`, `upsert`, `search`, `delete_point`, `get_point`.
- ⛔ Batch upsert / batch search.
- ⛔ `get_point` via id_map + manifest once multi-segment lands.

**Exit criteria:** the v1 facade covers the full single-collection lifecycle;
batch and multi-segment paths are wired as later layers land.

**Why this phase matters:** a clean, stable surface decouples callers from
internal churn and is the contract external clients depend on.

## Phase 7 — Hybrid search ⛔ Not started

**Goal:** Combine dense vector similarity with sparse/lexical scoring.

**Deliverables:**
- ⛔ Sparse/keyword scoring alongside dense ANN.
- ⛔ Score fusion (RRF / weighted) between dense and sparse hits.

**Exit criteria:** a hybrid query returns a single fused ranking that beats
either dense-only or lexical-only on the target workload.

**Why this phase matters:** dense vectors miss exact-keyword intent and lexical
misses semantics; hybrid ranking is what production search actually needs. See
[`docs/future-modules.md`](docs/future-modules.md).

## Phase 8 — Distribution ⛔ Not started

**Goal:** Scale beyond a single node with explicit consistency and failure behavior.

**Deliverables:**
- ⛔ Sharding by `ShardId` (already in `core.ids`).
- ⛔ Replication + read routing.
- ⛔ Distributed manifest / consensus for segment visibility.

**Exit criteria:** searches fan out across shards and merge globally-ranked top-K
correctly; replica lag and consistency mode are visible and testable; rebalance
never corrupts manifests or loses acknowledged data.

**Why this phase matters:** past a single node's capacity, scaling requires
distribution that never blurs what a result means. See
[`docs/sharding-and-replication.md`](docs/sharding-and-replication.md).

## Phase 9 — IVF / PQ (billion-scale) ⛔ Not started

**Goal:** Memory-efficient serving for very large collections.

**Deliverables:**
- ⛔ IVF (inverted file) index behind `AnnIndexKind.Ivf` (dispatch seam already exists).
- ⛔ Product Quantization for memory-efficient vectors.
- ⛔ Disk/mmap-backed segments.

**Exit criteria:** IVF/PQ serves far more vectors per node than HNSW at an
acceptable recall/latency tradeoff, with parameters validated against collection
size.

**Why this phase matters:** past a certain scale HNSW's graph memory dominates;
IVF/PQ is the tier that makes billion-scale serving economical. See
[`docs/ivf-roadmap.md`](docs/ivf-roadmap.md).

## Phase 10 — Hardening & performance ⛔ Not started

**Goal:** Production-grade performance, correctness verification, and observability.

**Deliverables:**
- ⛔ SIMD/FMA distance kernels in `distance/` (call-site seam already in place).
- ⛔ Fuzz + property tests (ANN recall bounds, WAL replay determinism).
- ⛔ Observability: histograms for latency/recall via `core.metrics`.

**Exit criteria:** hot-loop distance is SIMD-accelerated, invariants hold under
fuzzing, and latency/recall are observable in production via metrics.

**Why this phase matters:** correctness and speed must be provable and visible,
not assumed; this phase turns a working engine into an operable one.

---

## Status summary

| Layer | Status |
|-------|--------|
| Vector math + metrics | ✅ Done |
| Flat exact search + top-K | ✅ Done |
| In-memory HNSW | ✅ Done |
| Engine orchestration + API facade | ✅ Done |
| WAL write path | 🟡 In progress |
| Collections / schema / validator | 🟡 In progress |
| Payload + filtering | 🟠 Scaffold |
| Segments + manifest + recovery | 🟠 Scaffold |
| IVF / PQ / disk / SIMD / distributed | ⛔ Not started |

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

- **Alpha** — Phases 0–2: exact engine, HNSW, durability. The engine is correct
  and crash-safe in memory.
- **Beta** — Phases 3–5: filtering, HNSW hardening, segments. The engine is
  feature-complete for single-node production shape.
- **Production candidate** — Phases 6–8: public API, hybrid search, distribution.
  The engine is externally usable and horizontally scalable.
- **Scale / harden** — Phases 9–10: IVF/PQ and performance hardening. The engine
  serves billion-scale workloads and is fully observable.

## Success metrics

- **Correctness** — approximate results validated against the exact flat oracle;
  invariants (`len() <= k`, WAL replay determinism) hold under fuzzing.
- **Recall@k** — approximate recall meets targets across the tuning ranges for
  each index.
- **Latency** — p50 / p95 / p99 query latency measured against target workloads.
- **Memory per vector** — bytes per stored vector, the key economic lever for the
  IVF/PQ scale tier.
- **Operability** — recovery time, rebalance safety, and metrics/observability
  coverage in production.
