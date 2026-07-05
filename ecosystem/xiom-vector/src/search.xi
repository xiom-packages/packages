module xiom.vector.search

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
    var result = SearchResult{ id: idx.ids[i]; distance: dist; };
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
      var result = SearchResult{ id: idx.ids[i]; distance: dist; };
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
