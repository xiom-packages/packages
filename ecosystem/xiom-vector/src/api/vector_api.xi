module xiom.vector.api.vector_api

use xiom.core.error;
use xiom.core.ids;
use xiom.vector.engine;
use xiom.vector.storage.vector_store;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.query.search_service;

// Public, stable facade over VectorEngine. External callers should depend only
// on these functions; the engine internals (segments, WAL, manifest) may evolve
// without breaking this surface. Every fallible call returns Result so failures
// are explicit at the call site.

pub fn create_collection(eng: &mut VectorEngine, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError] {
  return engine_create_collection(eng, dim, metric);
}

pub fn upsert(eng: &mut VectorEngine, point: Int, vec: Vector) -> Result[Bool, CoreError] {
  return engine_upsert(eng, point, vec);
}

pub fn search(eng: &VectorEngine, query: &Vector, k: Int) -> Result[Vec[SearchResult], CoreError] {
  return engine_search(eng, query, k);
}

pub fn delete_point(eng: &mut VectorEngine, point: Int) -> Result[Bool, CoreError] {
  return engine_delete(eng, point);
}

pub fn get_point(eng: &VectorEngine, point: Int) -> Option[Vector] {
  // TODO(Phase 6): route through id_map + segment manifest once multiple
  // segments exist; today the single flat store answers directly.
  return index_get(&eng.store, point);
}
