// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.query.search_service

// Exact top-k search: the k-bounded distance-sorted scan (unfiltered and
// filtered). Extracted from the consolidated engine (post-AUDIT module
// tree).

use xiom.vector.primitives;
use xiom.vector.storage.vector_store;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vector.payload.filter_eval;
use xiom.vector.query.filter_plan;

pub type SearchResult = {
  id: Int;
  distance: Float32;
} derive[Clone]

// Ok-payload wrapper for search results. Rationale: on compiler v0.64.0 a
// Result/Option whose payload is DIRECTLY a Vec[T] with non-scalar T loses
// element field data for the caller (len survives, fields read as zero /
// address-like; XVC-C-04, repro docs/repro/xv-result-vec-struct/).
// Wrapping the Vec in a struct preserves the payload. Unwrap this type when
// the compiler finding is fixed.
pub type SearchHits = {
  items: Vec[SearchResult];
}

// Batch-search wrapper (M-Q2): one SearchHits per query, order preserved.
// A struct wrapper because a Result whose payload is a Vec of Vec-bearing
// structs is the XVC-C-04/C-08 shape family (fixed, but the wrapper is the
// proven, gated public shape -- mirrors SearchHits).
pub type BatchHits = {
  sets: Vec[SearchHits];
}

// Push a hit into a distance-sorted bounded list (shared by the exact and
// filtered scans, and by the M-D7 union merge): insert sorted, then trim.
pub fn results_push_bounded(results: &mut Vec[SearchResult], item: SearchResult, k: Int) {
  results.push(item);
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
}

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
    results_push_bounded(&mut results, SearchResult{ id: idx.ids[i], distance: dist }, k);
    i = i + 1;
  }
  return results;
}

// Exact range scan: every live point whose distance to the query is <= radius
// (inclusive), distance-sorted ascending and bounded by `limit` (the closest
// `limit` points). Runs on the raw store for BOTH index kinds -- exact by
// construction; an ANN-widened variant is a performance follow-up (M-P), not
// a correctness change. A NaN radius compares false and yields an empty
// result.
pub fn search_range_scan(idx: &VectorIndex, query: &Vector, radius: Float32, limit: Int, metric: DistanceMetric) -> Vec[SearchResult]
  requires: limit > 0
  requires: radius >= 0.0
  requires: idx.dim == query.dimension
  ensures: result.len() <= limit
{
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    var dist = vector_distance(&idx.vectors[i], query, metric);
    if dist <= radius {
      results_push_bounded(&mut results, SearchResult{ id: idx.ids[i], distance: dist }, limit);
    }
    i = i + 1;
  }
  return results;
}

// Pre-filter exact scan: evaluate the filter per candidate BEFORE the
// distance compute. This is the fallback plan and the default for
// un-estimable or low-selectivity filters.
fn search_knn_filtered_scan(idx: &VectorIndex, payloads: &PayloadStore, query: &Vector, k: Int, metric: DistanceMetric, filter: &FilterExpr) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.dim == query.dimension
  ensures: result.len() <= k
{
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    if payload_store_matches(payloads, idx.ids[i], filter) {
      var dist = vector_distance(&idx.vectors[i], query, metric);
      results_push_bounded(&mut results, SearchResult{ id: idx.ids[i], distance: dist }, k);
    }
    i = i + 1;
  }
  return results;
}

// Matching subset of a result list, order preserved (shared by the flat
// post-filter plan and the engine's HNSW+filter path).
pub fn filter_results_by_payload(items: &Vec[SearchResult], payloads: &PayloadStore, filter: &FilterExpr) -> Vec[SearchResult] {
  var out = Vec[SearchResult].new();
  var i: Int = 0;
  while i < items.len() {
    if payload_store_matches(payloads, items[i].id, filter) {
      out.push(SearchResult{ id: items[i].id, distance: items[i].distance });
    }
    i = i + 1;
  }
  return out;
}

// Index-driven filtered scan: enumerate the exact candidate ids from the
// sorted payload index (Eq/Range), resolve each through the store's O(log n)
// id -> slot map and compute distances only for matches.
fn search_knn_filtered_index(idx: &VectorIndex, payloads: &PayloadStore, query: &Vector, k: Int, metric: DistanceMetric, filter: &FilterExpr) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.dim == query.dimension
  ensures: result.len() <= k
{
  var ids = filter_plan_candidates(payloads, filter);
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  while i < ids.len() {
    match index_get(idx, ids[i]) {
      Some(v) => {
        var dist = vector_distance(&v, query, metric);
        results_push_bounded(&mut results, SearchResult{ id: ids[i], distance: dist }, k);
      }
      None => {}
    }
    i = i + 1;
  }
  return results;
}

// Selectivity-planned filtered exact top-k. Post-filter plan (chosen by
// filter_plan.choose_filter_plan only for index-answerable filters whose
// exact match count is >= k and a majority of the store): rank the whole
// store (top-k), keep the matching subset. When that subset fills k it is
// provably exact -- any matching point outside the global top-k is farther
// than every point in it -- otherwise (uneven distance ties, or estimates
// that overstate the boundary situation) fall back to the pre-filter scan.
// The index plan enumerates the exact candidate ids instead. Equal-distance
// ties may select different ids across plans; distances and the k-bound are
// unaffected.
pub fn search_knn_filtered(idx: &VectorIndex, payloads: &PayloadStore, query: &Vector, k: Int, metric: DistanceMetric, filter: &FilterExpr) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.dim == query.dimension
  ensures: result.len() <= k
{
  var plan: Int = choose_filter_plan(payloads, filter, idx.ids.len(), k);
  if plan == filter_plan_post() {
    var raw = search_knn(idx, query, k, metric);
    var out = filter_results_by_payload(&raw, payloads, filter);
    if out.len() == k { return out; }
  } else {
    if plan == filter_plan_index() {
      return search_knn_filtered_index(idx, payloads, query, k, metric, filter);
    }
  }
  return search_knn_filtered_scan(idx, payloads, query, k, metric, filter);
}

// ---- Payload hydration (SearchRequest.with_payload) ----
// A hydrated hit: the plain result plus its metadata. `has_payload` is false
// when hydration was not requested OR the point has no payload (`payload` is
// then an empty Payload). Kept separate from SearchResult so the plain search
// path and its XVC-C-04 wrapper stay untouched.
pub type SearchHit = {
  id: Int;
  distance: Float32;
  payload: Payload;
  has_payload: Bool;
}

// C-04 wrapper for hydrated hits (same rationale as SearchHits): a
// Result/Option whose payload is directly a Vec[non-scalar] loses element
// fields at the caller.
pub type HydratedHits = {
  items: Vec[SearchHit];
}

// Batch-request wrapper (M-Q6): one HydratedHits per request, order
// preserved (same C-04 family rationale as BatchHits).
pub type HydratedBatch = {
  sets: Vec[HydratedHits];
}

// Attach payloads to a result list when `with_payload`; otherwise every hit
// carries the empty payload and has_payload=false. Payloads are copied out
// of the store into the hit (no borrowed references escape).
pub fn hydrate_hits(items: &Vec[SearchResult], payloads: &PayloadStore, with_payload: Bool) -> Vec[SearchHit] {
  var out = Vec[SearchHit].new();
  var i: Int = 0;
  while i < items.len() {
    var pl = payload_new();
    var have: Bool = false;
    if with_payload {
      match payload_store_get(payloads, items[i].id) {
        Some(found) => { pl = found; have = true; }
        None => {}
      }
    }
    out.push(SearchHit{ id: items[i].id, distance: items[i].distance, payload: pl, has_payload: have });
    i = i + 1;
  }
  return out;
}
