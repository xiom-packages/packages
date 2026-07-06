module xiom.vector.query.search_request

use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.payload.filter_ast;

// A fully-specified query. `filter` is a Vec used as an optional single clause
// (empty = no filter) since the engine has no Option-of-recursive-enum yet;
// `with_payload` asks the engine to hydrate payloads on the returned hits.

pub type SearchRequest = {
  query: Vector;
  top_k: Int;
  metric: DistanceMetric;
  filter: Vec[FilterExpr];
  with_payload: Bool;
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
  };
}

pub fn search_request_set_filter(req: &mut SearchRequest, expr: FilterExpr) {
  // Single-clause slot for now; Phase 3 accepts a full FilterExpr tree.
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
