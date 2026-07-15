module xiom.vector.query.search_request
// Local inline types.

pub type Vector = { data: Vec[Float32]; dimension: Int; }
pub enum DistanceMetric { Cosine, DotProduct, Euclidean }
pub enum FilterExpr {
  Eq(field: Str, value: Str),
  Range(field: Str, lo: Str, hi: Str),
  Exists(field: Str),
  In(field: Str, values: Vec[Str]),
  And(terms: Vec[FilterExpr]),
  Or(terms: Vec[FilterExpr]),
  Not(terms: Vec[FilterExpr]),
}

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