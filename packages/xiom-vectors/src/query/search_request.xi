// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.query.search_request

// SearchRequest: the wire shape for request-driven search. Holds the query
// vector, top_k, the request's metric (validated against the active
// collection by engine_search_request), an optional filter clause, the
// with_payload hydration flag, and the M-Q6 extensions: mode (knn/range),
// the range radius, and knn pagination (offset OR after_id cursor).
// Rewritten against the real extracted types (the pre-extraction file
// carried inline mirrors).

use xiom.vector.primitives;
use xiom.vector.payload.filter_ast;

pub enum SearchMode {
  Knn,
  Range,
}

pub type SearchRequest = {
  query: Vector;
  top_k: Int;
  metric: DistanceMetric;
  filter: Vec[FilterExpr];
  with_payload: Bool;
  mode: SearchMode;
  radius: Float32;
  offset: Int;
  after_id: Int;
}

pub fn search_request_new(query: Vector, top_k: Int, metric: DistanceMetric) -> SearchRequest
  requires: top_k > 0
{
  var filter = Vec[FilterExpr].new();
  return SearchRequest{
    query: query,
    top_k: top_k,
    metric: metric,
    filter: filter,
    with_payload: false,
    mode: SearchMode.Knn,
    radius: 0.0,
    offset: 0,
    after_id: -1,
  };
}

// Replace the request's filter with a single clause ([] = no filter).
pub fn search_request_set_filter(req: &mut SearchRequest, expr: FilterExpr) {
  var filter = Vec[FilterExpr].new();
  filter.push(expr);
  req.filter = filter;
}

pub fn search_request_has_filter(req: &SearchRequest) -> Bool {
  return req.filter.len() > 0;
}

pub fn search_request_top_k(req: &SearchRequest) -> Int {
  return req.top_k;
}

// Toggle payload hydration on the request.
pub fn search_request_set_with_payload(req: &mut SearchRequest, on: Bool) {
  req.with_payload = on;
}

// Switch the request mode (Knn | Range). Range mode uses `top_k` as the
// inclusive-radius limit; filters and pagination are Knn-only.
pub fn search_request_set_mode(req: &mut SearchRequest, mode: SearchMode) {
  req.mode = mode;
}

// Range-mode sugar: sets mode = Range and the inclusive radius.
pub fn search_request_set_range(req: &mut SearchRequest, radius: Float32) {
  req.mode = SearchMode.Range;
  req.radius = radius;
}

// Knn offset pagination: ranks [offset, offset+top_k) of the (distance asc,
// id asc) total order (mutually exclusive with the after-id cursor).
pub fn search_request_set_page(req: &mut SearchRequest, offset: Int) {
  req.offset = offset;
}

// Knn cursor pagination: continue strictly after `after_id` (-1 = none).
pub fn search_request_set_after(req: &mut SearchRequest, after_id: Int) {
  req.after_id = after_id;
}

// A batch of requests (M-Q6), executed in order.
pub type SearchBatchRequest = {
  requests: Vec[SearchRequest];
}

pub fn search_batch_request_new() -> SearchBatchRequest {
  return SearchBatchRequest{ requests: Vec[SearchRequest].new() };
}

pub fn search_batch_request_add(b: &mut SearchBatchRequest, req: SearchRequest) {
  b.requests.push(req);
}

pub fn search_batch_request_len(b: &SearchBatchRequest) -> Int {
  return b.requests.len();
}
