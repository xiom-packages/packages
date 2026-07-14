# Future Modules

A file-by-file design catalogue for modules that are **not yet implemented**, so
the vision is preserved next to the code. Each entry names the planned module and
its intended responsibility. Phases refer to [`../ROADMAP.md`](../ROADMAP.md).

The two largest future areas — the scale tier and the distributed layer — have
their own deep-dives: [`ivf-roadmap.md`](ivf-roadmap.md) and
[`sharding-and-replication.md`](sharding-and-replication.md). This document covers
everything else.

## `ingest/` — write path (Phase 2–3)

| Module | Purpose |
|--------|---------|
| `batch.xi` | Batch ingest container: input validation and normalization of mixed write ops into one coherent batch. |
| `upsert.xi` | Upsert semantics for new and existing IDs — replacement visibility, tombstone behavior, and idempotency of repeated writes. |
| `delete.xi` | Delete semantics + tombstone creation: logical removal now, physical cleanup/rebuild later. |
| `dedupe.xi` | Dedup rules for repeated IDs within a single batch (last-write-wins / conflict resolution before the batch is applied). |
| `write_path.xi` | The full write path: validate → append WAL → write mutable segment → update payload → schedule background index work. |
| `flush_coordinator.xi` | Thresholds and timers that turn mutable buffered state into sealed segments. |

## `hybrid/` — lexical + vector search (Phase 7)

| Module | Purpose |
|--------|---------|
| `lexical_index.xi` | Lexical posting index enabling keyword-aware search alongside dense vectors. |
| `bm25.xi` | BM25 scoring — the sparse side of hybrid ranking. |
| `hybrid_query.xi` | Typed hybrid request combining lexical and vector constraints in one query. |
| `reciprocal_rank_fusion.xi` | RRF (or other score/rank fusion) for combining lexical and vector rankings; RRF is robust and simple. |

## `embed/` — embedding integration

| Module | Purpose |
|--------|---------|
| `embedding_provider.xi` | Integration layer for external embedding providers and local models. |
| `embedding_job.xi` | Background embedding pipeline job run during ingestion. |
| `embedding_cache.xi` | Cache for repeated embeddings, enabling deterministic reprocessing. |
| `chunker.xi` | Document chunking for RAG use cases. |
| `model_registry.xi` | Tracks embedding model metadata (version, dimension, normalization expectations, collection compatibility) to prevent dimension/metric mismatches. |

## `storage/` — advanced storage (Phase 5+)

| Module | Purpose |
|--------|---------|
| `vector_block.xi` | Physical storage unit for raw or compressed vectors. |
| `payload_store.xi` | Persistent payload storage kept separate from vector bytes. |
| `doc_store.xi` | Optional document/chunk text storage for RAG deployments. |
| `posting_list.xi` | Posting-list storage for payload field indexes and hybrid lexical search. |
| `quantized_store.xi` | Persistent storage for quantized / PQ codes. |
| `cache.xi` | Read cache for vectors, payloads, payload indexes, and codebooks. |

## `distance/` — SIMD acceleration

| Module | Purpose |
|--------|---------|
| `simd_distance.xi` | SIMD-accelerated distance kernels for hot loops, isolated so correctness and optimization paths are separately testable. |
| `normalization.xi` | Vector normalization helpers with contract enforcement. |

## `durability/` — advanced recovery (Phase 5+)

| Module | Purpose |
|--------|---------|
| `snapshot_manifest.xi` | Snapshot metadata tying together collection manifests, segment files, and index artifacts. |
| `restore.xi` | Restore workflow from snapshots plus the WAL tail. |
| `consistency_checks.xi` | Post-recovery and periodic verification: manifest integrity, segment/index alignment, payload cardinality, and tombstone correctness. |

## `api/` — service surface (Phase 6)

| Module | Purpose |
|--------|---------|
| `rest_like.xi` | HTTP/JSON API surface — the first public interface. |
| `grpc_like.xi` | Binary/framed RPC transport for low-overhead clients and cluster traffic. |
| `collection_api.xi` | Collection lifecycle endpoint group (create/configure/drop). |
| `point_api.xi` | Point lifecycle endpoint group (upsert/get/delete). |
| `search_api.xi` | Search endpoint group (KNN / range / hybrid / filtered). |
| `admin_api.xi` | Administrative endpoint group (status, snapshots, rebalance, metrics). |

## Related

- [`engine-overview.md`](engine-overview.md) — how today's implemented layers fit together.
- [`ivf-roadmap.md`](ivf-roadmap.md) — the IVF/PQ scale tier (Phase 9).
- [`sharding-and-replication.md`](sharding-and-replication.md) — the distributed layer (Phase 8).
- [`../ROADMAP.md`](../ROADMAP.md) — phase status for every area above.
