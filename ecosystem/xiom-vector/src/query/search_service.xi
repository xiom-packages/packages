module xiom.vector.query.search_service

use xiom.vector.storage.vector_store;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.types.neighbor;
use xiom.vector.index.hnsw;
use xiom.vector.index.ann_index;

// Query-layer entry points. `SearchResult` is the public hit record (stable
// integer id + distance). `search_knn` / `search_range` are the exact
// brute-force scans migrated from the original engine and remain the
// correctness oracle. `search_execute` is the planner seam that routes a query
// to the appropriate index (Flat scan or HNSW) and normalises to SearchResult.

pub type SearchResult = {
  id: Int;
  distance: Float32;
} derive[Clone]

pub fn search_knn(idx: &VectorIndex, query: &Vector, k: Int, metric: DistanceMetric) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.dim == query.dimension
  ensures: result.len() <= k
{
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    var dist = vector_distance(&idx.vectors[i], query, metric);
    var result = SearchResult{ id: idx.ids[i], distance: dist };
    results.push(result);
    var pos: Int = results.len() - 1;
    while pos > 0 && results[pos - 1].distance > results[pos].distance {
      var tmp = results[pos];
      results[pos] = results[pos - 1];
      results[pos - 1] = tmp;
      pos = pos - 1;
    }
    if results.len() > k {
      results.pop();
    }
    i = i + 1;
  }
  return results;
}

pub fn search_range(idx: &VectorIndex, query: &Vector, radius: Float32, metric: DistanceMetric) -> Vec[SearchResult]
  requires: radius > 0.0
  requires: idx.dim == query.dimension
{
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    var dist = vector_distance(&idx.vectors[i], query, metric);
    if dist <= radius {
      var result = SearchResult{ id: idx.ids[i], distance: dist };
      results.push(result);
      var pos: Int = results.len() - 1;
      while pos > 0 && results[pos - 1].distance > results[pos].distance {
        var tmp = results[pos];
        results[pos] = results[pos - 1];
        results[pos - 1] = tmp;
        pos = pos - 1;
      }
    }
    i = i + 1;
  }
  return results;
}

// Lower a Vec[Neighbor] (index-layer, UInt64 ids) to Vec[SearchResult]
// (query-layer, Int ids).
fn neighbors_to_results(ns: &Vec[Neighbor]) -> Vec[SearchResult] {
  var out = Vec[SearchResult].new();
  var i: Int = 0;
  while i < ns.len() {
    out.push(SearchResult{ id: ns[i].id as Int, distance: ns[i].distance });
    i = i + 1;
  }
  return out;
}

// Planner dispatch: choose the physical index for a query. Flat/Ivf currently
// fall back to the exact scan; Hnsw uses the graph. All paths honour
// result.len() <= k.
pub fn search_execute(idx: &VectorIndex, graph: &HNSWGraph, query: &Vector, k: Int, metric: DistanceMetric, kind: AnnIndexKind) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.dim == query.dimension
  ensures: result.len() <= k
{
  match kind {
    Flat => { return search_knn(idx, query, k, metric); }
    Hnsw => {
      var hits = hnsw_search(graph, query, k);
      return neighbors_to_results(&hits);
    }
    Ivf => {
      // TODO(Phase 9): route to the IVF index once it exists.
      return search_knn(idx, query, k, metric);
    }
  }
}
