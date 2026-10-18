// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.engine

// Public facade over the vector engine. Consumers call these functions; the
// engine_* orchestration lives in xiom.vector.engine.core and the xiom-core
// stand-ins in xiom.vector.core.shim. Dependency order is acyclic:
// core.shim <- engine.core <- engine (this file). Consumers that call
// engine_* symbols (engine_new/engine_size/engine_recover/...) import
// xiom.vector.engine.core in addition to this module.

use xiom.vector.engine.core;
use xiom.vector.core.shim;
use xiom.vector.primitives;
use xiom.vector.index.ann_index;
use xiom.vector.durability.wal;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vector.query.search_service;
use xiom.vector.query.search_request;

pub fn create_collection(eng: &mut VectorEngine, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError] {
  return engine_create_collection(eng, dim, metric);
}

// Select the ANN index (Flat default; Hnsw validates params and rebuilds the
// graph from the flat store). In-memory only -- re-apply after engine_recover.
pub fn set_index(eng: &mut VectorEngine, kind: AnnIndexKind, params: AnnParams) -> Result[Bool, CoreError] {
  return engine_set_index(eng, kind, params);
}

// Compact the ANN graph (rebuild from live nodes; reclaims tombstones).
// Returns the number of reclaimed nodes; 0 on a Flat collection.
pub fn compact_index(eng: &mut VectorEngine) -> Result[Int, CoreError] {
  return engine_compact_index(eng);
}

pub fn upsert(eng: &mut VectorEngine, point: Int, vec: Vector) -> Result[Bool, CoreError] {
  return engine_upsert(eng, point, vec);
}

// Batch ops (M-Q2): all-or-nothing validation per call; see engine.core for
// the exact semantics (upsert returns records applied; delete returns points
// actually removed; search returns one result set per query in order).
pub fn upsert_many(eng: &mut VectorEngine, ids: &Vec[Int], vecs: &Vec[Vector]) -> Result[Int, CoreError] {
  return engine_upsert_many(eng, ids, vecs);
}

pub fn delete_many(eng: &mut VectorEngine, ids: &Vec[Int]) -> Result[Int, CoreError] {
  return engine_delete_many(eng, ids);
}

pub fn search_many(eng: &VectorEngine, queries: &Vec[Vector], k: Int) -> Result[BatchHits, CoreError] {
  return engine_search_many(eng, queries, k);
}

pub fn search(eng: &VectorEngine, query: &Vector, k: Int) -> Result[SearchHits, CoreError] {
  return engine_search(eng, query, k);
}

pub fn delete_point(eng: &mut VectorEngine, point: Int) -> Result[Bool, CoreError] {
  return engine_delete(eng, point);
}

pub fn get_point(eng: &VectorEngine, point: Int) -> Option[Vector] {
  return engine_get_point(eng, point);
}

pub fn set_payload(eng: &mut VectorEngine, point: Int, payload: Payload) -> Result[Bool, CoreError] {
  return engine_set_payload(eng, point, payload);
}

pub fn get_payload(eng: &VectorEngine, point: Int) -> Option[Payload] {
  return engine_get_payload(eng, point);
}

pub fn search_filtered(eng: &VectorEngine, query: &Vector, k: Int, filter: &FilterExpr) -> Result[SearchHits, CoreError] {
  return engine_search_filtered(eng, query, k, filter);
}

// Selective delete (M-Q4): remove every point matching `filter` (planner-
// driven: index candidates or scan; WAL-durable per point, tombstones +
// payload/index cleanup). Returns the number of points removed; nothing
// matching -> Ok(0).
pub fn delete_filter(eng: &mut VectorEngine, filter: &FilterExpr) -> Result[Int, CoreError] {
  return engine_delete_filter(eng, filter);
}

// Exact range search: every point within `radius` (inclusive), distance-
// sorted ascending, at most `limit` items (the closest ones).
pub fn search_range(eng: &VectorEngine, query: &Vector, radius: Float32, limit: Int) -> Result[SearchHits, CoreError] {
  return engine_search_range(eng, query, radius, limit);
}

// Offset pagination (M-Q3): ranks [offset, offset+k) of the paginated total
// order (distance ascending, id ascending; exact on Flat AND Hnsw).
pub fn search_page(eng: &VectorEngine, query: &Vector, k: Int, offset: Int) -> Result[SearchHits, CoreError] {
  return engine_search_page(eng, query, k, offset);
}

// Cursor pagination (M-Q3): the next k ranks strictly after `after_id`
// (Err(NotFound) when the cursor id does not exist).
pub fn search_after(eng: &VectorEngine, query: &Vector, k: Int, after_id: Int) -> Result[SearchHits, CoreError] {
  return engine_search_after(eng, query, k, after_id);
}

// Request-driven search: top_k/filter/with_payload come from the request.
// The active collection's metric governs (mismatching request metric -> Err).
pub fn search_with_request(eng: &VectorEngine, req: &SearchRequest) -> Result[HydratedHits, CoreError] {
  return engine_search_request(eng, req);
}

// Batch request search (M-Q6): one hydrated result set per request, order
// preserved; the first failing request aborts the batch.
pub fn search_batch_with_request(eng: &VectorEngine, batch: &SearchBatchRequest) -> Result[HydratedBatch, CoreError] {
  return engine_search_batch_request(eng, batch);
}

// Persist the whole collection registry to a manifest file (M-D2/D3;
// whole-file + atomic rename). The registry file is the durable collection
// registry: `open_engine` consults it first on the next start.
pub fn save_manifest(eng: &mut VectorEngine, path: Str) -> Bool {
  return engine_manifest_save(eng, path);
}

// Open an engine from a WAL checkpoint + its manifest file (M-D2/D3). The
// file's registry entries override collection configs by name; the in-WAL
// manifests are the migration fallback (pre-D2 logs, missing names); the
// caller's dim/metric the last resort. Load the WAL first (`wal_load(path)`
// then pass the writer).
pub fn open_engine(w: &WalWriter, path: Str, dim: Int, metric: DistanceMetric) -> VectorEngine {
  return engine_recover_file(w, path, dim, metric);
}

// ---- Durability (M-D5) ----

// Enable durable mode: every later mutation is appended to `seg_path`
// (xiom.wal codec v1 delta segment) and fsynced BEFORE its ack (WAL-before-
// ack). The whole-file checkpoint stays the compaction output; call
// `checkpoint_wal` + `rotate_durable_segment` on a clean shutdown.
pub fn enable_durability(eng: &mut VectorEngine, seg_path: Str) -> Result[Bool, CoreError] {
  return engine_enable_durable(eng, seg_path);
}

// The fsync'd frontier (highest LSN committed to the segment; 0 when
// durability is not enabled).
pub fn durable_frontier(eng: &VectorEngine) -> Int {
  return engine_synced_lsn(eng);
}

// Open a durable engine from checkpoint + delta segment + manifest (M-D5):
// merge, recover, and enable durable mode in one call. `manifest_path` may
// be "".
pub fn open_durable(ckpt_path: Str, seg_path: Str, manifest_path: Str, dim: Int, metric: DistanceMetric) -> VectorEngine {
  return engine_open_durable(ckpt_path, seg_path, manifest_path, dim, metric);
}

// ---- Durability (M-D6) ----

// Compact + durable checkpoint swap (bounded recovery): rebase the log to
// the live state, swap a crash-safe checkpoint (fsync before rename before
// segment reset), return the new durable frontier (LSN).
pub fn checkpoint_swap(eng: &mut VectorEngine) -> Result[Int, CoreError] {
  return engine_checkpoint_swap(eng);
}

// Auto-checkpoint policy: swap every `every` successful commits (0 = off).
pub fn set_checkpoint_policy(eng: &mut VectorEngine, every: Int) -> Result[Bool, CoreError] {
  return engine_set_checkpoint_policy(eng, every);
}

// Checkpoint path for embedders that enable durability without
// open_durable (needed by checkpoint_swap).
pub fn set_checkpoint_path(eng: &mut VectorEngine, path: Str) -> Result[Bool, CoreError] {
  return engine_set_checkpoint_path(eng, path);
}

// Commits since the last checkpoint swap (0 after a swap).
pub fn checkpoint_countdown(eng: &VectorEngine) -> Int {
  return engine_checkpoint_countdown(eng);
}

// ---- Multi-segment read path (M-D7) ----

// Roll the active collection's contents into an immutable sealed segment
// (move semantics: register + cache + clear active; fsync-before-ack in
// durable mode). Queries immediately see the data through the union.
// Returns the assigned segment id.
pub fn roll_segment(eng: &mut VectorEngine, path: Str) -> Result[Int, CoreError] {
  return engine_roll_segment(eng, path);
}

// Merge every sealed segment of the active collection + the active
// remainder into ONE new segment (tombstones applied; bit-exact with the
// pre-compaction union). Old files remain on disk (caller cleans).
pub fn compact_sealed(eng: &mut VectorEngine, path: Str) -> Result[Int, CoreError] {
  return engine_compact_sealed(eng, path);
}

// Registered sealed sources of the active collection / unreadable count.
pub fn sealed_count(eng: &VectorEngine) -> Int {
  return engine_sealed_count(eng);
}

pub fn sealed_missing(eng: &VectorEngine) -> Int {
  return engine_sealed_missing(eng);
}

// Cached (loaded) sealed sources of the active collection.
pub fn sealed_loaded(eng: &VectorEngine) -> Int {
  return engine_sealed_loaded(eng);
}

// Opt-in auto-roll policy (P2 tuning): roll at `every` active points into
// `dir` (must exist; 0 disables). Off by default.
pub fn set_seal_policy(eng: &mut VectorEngine, every: Int, dir: Str) -> Result[Bool, CoreError] {
  return engine_set_seal_policy(eng, every, dir);
}

// ---- Multi-collection registry (M-D3) ----

// Create a named collection (empty) and make it active. Rejects invalid or
// duplicate names and invalid dimensions.
pub fn create_named_collection(eng: &mut VectorEngine, name: Str, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError] {
  return engine_create_named(eng, name, dim, metric);
}

// Make a named collection active (no-op when it already is).
pub fn select_collection(eng: &mut VectorEngine, name: Str) -> Result[Bool, CoreError] {
  return engine_select(eng, name);
}

// Drop a named collection (WAL-durable; the active view moves to the first
// remaining collection, or the engine is left ready for a fresh create).
pub fn drop_collection(eng: &mut VectorEngine, name: Str) -> Result[Bool, CoreError] {
  return engine_drop(eng, name);
}

// Collection names in creation order.
pub fn list_collections(eng: &VectorEngine) -> CollectionList {
  return engine_list_collections(eng);
}

pub fn collection_count(eng: &VectorEngine) -> Int {
  return engine_collection_count(eng);
}

// ---- Index admin (M-Q5) ----

// Per-collection statistics (config, points, payloads, graph occupancy).
pub fn collection_stats(eng: &VectorEngine, name: Str) -> Result[CollectionStats, CoreError] {
  return engine_collection_stats(eng, name);
}

pub fn memory_estimate(eng: &VectorEngine, name: Str) -> Result[MemoryEstimate, CoreError] {
  return engine_memory_estimate(eng, name);
}

// Rebuild the active collection's index from the flat store (Hnsw:
// tombstones reclaimed; Flat: no-op) with build/compact statistics.
pub fn rebuild_index(eng: &mut VectorEngine) -> Result[IndexStats, CoreError] {
  return engine_rebuild_index(eng);
}

// ---- Segment files (M-D4) ----

// Seal the active collection as an immutable segment file (vectors +
// payloads + Hnsw graph codec; whole-file + atomic rename; lifecycle
// Mutable -> Sealing -> Sealed).
pub fn seal_segment(eng: &mut VectorEngine, seg_id: Int, path: Str) -> Result[Bool, CoreError] {
  return engine_seal_segment(eng, seg_id, path);
}

// Restore the active collection's contents from a sealed segment file; the
// WAL is re-checkpointed so a reopen replays the restored state.
pub fn restore_segment(eng: &mut VectorEngine, path: Str) -> Result[Bool, CoreError] {
  return engine_restore_segment(eng, path);
}

// L-2 collection move: export a named collection's full live state to one
// segment artifact (durable roll; the source stays queryable via its
// sealed entry). L-5: compaction-aware -- pre-existing sealed segments
// are merged (D7 compaction path); empty collections are refused.
pub fn export_collection(eng: &mut VectorEngine, name: Str, path: Str) -> Result[Int, CoreError] {
  return engine_export_collection(eng, name, path);
}

// L-2 collection move: attach a segment artifact to the ACTIVE collection
// (matching dim/metric; no cid requirement; integrity footer REQUIRED).
pub fn attach_segment(eng: &mut VectorEngine, path: Str) -> Result[Bool, CoreError] {
  return engine_attach_segment(eng, path);
}
