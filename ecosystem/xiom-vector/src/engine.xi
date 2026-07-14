module xiom.vector.engine

use xiom.core.error;
use xiom.core.ids;
use xiom.core.contracts;
use xiom.core.wal.wal_writer;
use xiom.core.metrics;
use xiom.vector.storage.vector_store;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.query.search_service;
use xiom.vector.durability.write_ahead_events;

// Top-level orchestrator — the single entry point the api facade drives. It
// wires together the durable write path (WAL-before-ack), the in-memory store,
// the query path, and metrics.
//
// SCAFFOLD boundary: this build manages ONE active collection backed by ONE
// in-memory flat store. Phase 5 promotes `store` to a per-collection registry
// of segments routed through a manifest; the public engine_* signatures are
// designed to stay stable across that change.

pub type VectorEngine = {
  store: VectorIndex;
  metric: DistanceMetric;
  dimension: Int;
  created: Bool;
  wal: WalWriter;
  upserts: Counter;
  deletes: Counter;
  next_collection: Int;
}

pub fn engine_new() -> VectorEngine {
  return VectorEngine{
    store: index_new(1),
    metric: DistanceMetric.Euclidean,
    dimension: 0,
    created: false,
    wal: wal_writer_new(),
    upserts: counter_new("vector.upserts"),
    deletes: counter_new("vector.deletes"),
    next_collection: 1,
  };
}

// Create the (single) active collection. Fixes dimension and metric for the
// engine's lifetime — the root of the "dimension is constant" invariant.
pub fn engine_create_collection(eng: &mut VectorEngine, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError]
  requires: dim >= 1
{
  if !is_valid_dimension(dim) {
    return Err(CoreError.InvalidInput("dimension out of range"));
  }
  eng.store = index_new(dim as UInt);
  eng.dimension = dim;
  eng.metric = metric;
  eng.created = true;
  var id = collection_id(eng.next_collection);
  eng.next_collection = eng.next_collection + 1;
  return Ok(id);
}

// Durable upsert: append to the WAL first (WAL-before-ack), then apply to the
// in-memory store. Rejects a dimension mismatch before touching the log.
pub fn engine_upsert(eng: &mut VectorEngine, point: Int, vec: Vector) -> Result[Bool, CoreError]
  requires: eng.created
{
  if (vec.dimension as Int) != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  log_upsert(&mut eng.wal, 1, point);
  var ok = index_add(&mut eng.store, point, vec);
  counter_inc(&mut eng.upserts);
  return Ok(ok);
}

// Exact top-k search over the active collection using its configured metric.
// Dispatches to the migrated brute-force scan (the correctness oracle).
pub fn engine_search(eng: &VectorEngine, query: &Vector, k: Int) -> Result[Vec[SearchResult], CoreError]
  requires: eng.created
  requires: k > 0
{
  if (query.dimension as Int) != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  if !is_valid_top_k(k) {
    return Err(CoreError.InvalidInput("top_k out of range"));
  }
  var hits = search_knn(&eng.store, query, k, eng.metric);
  return Ok(hits);
}

pub fn engine_delete(eng: &mut VectorEngine, point: Int) -> Result[Bool, CoreError]
  requires: eng.created
{
  log_delete(&mut eng.wal, 1, point);
  var ok = index_remove(&mut eng.store, point);
  counter_inc(&mut eng.deletes);
  return Ok(ok);
}

pub fn engine_size(eng: &VectorEngine) -> Int {
  return index_size(&eng.store);
}

pub fn engine_durable_lsn(eng: &VectorEngine) -> Int {
  return wal_writer_current_lsn(&eng.wal);
}
