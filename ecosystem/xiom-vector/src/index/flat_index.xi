module xiom.vector.index.flat_index

use xiom.vector.storage.vector_store;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.query.search_service;

// Exact brute-force index. It scans every stored vector, so it is O(n) per
// query but always returns the true nearest neighbours. It is the correctness
// oracle that approximate indexes (HNSW, IVF) are validated against, and the
// default index for small collections.

pub type FlatIndex = {
  store: VectorIndex;
}

pub fn flat_index_new(dim: UInt) -> FlatIndex
  requires: dim > 0
{
  return FlatIndex{ store: index_new(dim) };
}

pub fn flat_index_add(idx: &mut FlatIndex, id: Int, vec: Vector) -> Bool
  requires: idx.store.dim == vec.dimension
{
  return index_add(&mut idx.store, id, vec);
}

pub fn flat_index_remove(idx: &mut FlatIndex, id: Int) -> Bool {
  return index_remove(&mut idx.store, id);
}

pub fn flat_index_size(idx: &FlatIndex) -> Int {
  return index_size(&idx.store);
}

// Exact top-k. Delegates to the shared brute-force scan so the ranking and
// tie-break logic lives in exactly one place (DRY).
pub fn flat_index_search(idx: &FlatIndex, query: &Vector, k: Int, metric: DistanceMetric) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.store.dim == query.dimension
  ensures: result.len() <= k
{
  return search_knn(&idx.store, query, k, metric);
}
