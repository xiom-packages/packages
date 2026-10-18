// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.query.pagination

// Cursor pagination over exact search results (M-Q3). The paginated total
// order is **(distance ascending, id ascending)**: pages are stable within a
// fixed engine state -- page N + page N+1 + ... reconstructs the full
// ordered result set with no gaps or duplicates -- and equal-distance ties
// are ordered by id ascending. (The plain `search` path sorts by distance
// only; its tie order is unspecified. Paginated results satisfy the
// documented total order on Flat AND Hnsw engines: both kernels scan the raw
// store, exact by construction; an ANN-widened variant is M-P tuning.)
//
// - `search_page_scan(..., k, offset)` = ranks [offset, offset+k) of the
//   ordered result set.
// - `search_after_scan(..., k, after_id)` = the next k ranks strictly after
//   the CURRENT position of `after_id` (None when that id does not exist,
//   e.g. deleted between pages; restarting is the caller's policy).

use xiom.vector.primitives;
use xiom.vector.storage.vector_store;
use xiom.vector.query.search_service;

// True when `a` must come after `b` in the paginated total order.
fn page_after(a: &SearchResult, b: &SearchResult) -> Bool {
  if a.distance > b.distance { return true; }
  if a.distance < b.distance { return false; }
  return a.id > b.id;
}

// Insert-sorted bounded push under the total order (the shape of
// search_service.results_push_bounded plus the id tie-break).
fn page_push_bounded(results: &mut Vec[SearchResult], item: SearchResult, cap: Int) {
  results.push(item);
  var pos: Int = results.len() - 1;
  while pos > 0 && page_after(&results[pos - 1], &results[pos]) {
    var tmp = results[pos];
    results[pos] = results[pos - 1];
    results[pos - 1] = tmp;
    pos = pos - 1;
  }
  if results.len() > cap {
    results.pop();
  }
}

pub fn search_page_scan(idx: &VectorIndex, query: &Vector, k: Int, offset: Int, metric: DistanceMetric) -> SearchHits
  requires: k > 0
  requires: offset >= 0
  requires: idx.dim == query.dimension
  ensures: result.items.len() <= k
{
  var cap: Int = offset + k;
  var ranked = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    var dist = vector_distance(&idx.vectors[i], query, metric);
    page_push_bounded(&mut ranked, SearchResult{ id: idx.ids[i], distance: dist }, cap);
    i = i + 1;
  }
  var out = Vec[SearchResult].new();
  var j: Int = offset;
  while j < ranked.len() {
    out.push(SearchResult{ id: ranked[j].id, distance: ranked[j].distance });
    j = j + 1;
  }
  return SearchHits{ items: out };
}

pub fn search_after_scan(idx: &VectorIndex, query: &Vector, k: Int, after_id: Int, metric: DistanceMetric) -> Option[SearchHits]
  requires: k > 0
  requires: idx.dim == query.dimension
{
  var cursor_v = index_get(idx, after_id);
  var d0: Float32 = 0.0;
  var found: Bool = false;
  match cursor_v {
    Some(v) => {
      d0 = vector_distance(&v, query, metric);
      found = true;
    }
    None => {}
  }
  if !found {
    return None;
  }
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    var dist = vector_distance(&idx.vectors[i], query, metric);
    var after: Bool = dist > d0 || (dist == d0 && idx.ids[i] > after_id);
    if after {
      page_push_bounded(&mut results, SearchResult{ id: idx.ids[i], distance: dist }, k);
    }
    i = i + 1;
  }
  return Some(SearchHits{ items: results });
}
