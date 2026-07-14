module xiom.vector.index.ann_index

use xiom.core.limits;

// Common vocabulary shared by every ANN index implementation. Collections pick
// a kind and carry its params; the query planner dispatches on the kind.

pub enum AnnIndexKind {
  Flat,
  Hnsw,
  Ivf,
}

pub type AnnParams = {
  m: Int;
  ef_construction: Int;
  ef_search: Int;
} derive[Clone]

pub fn ann_params_default() -> AnnParams {
  return AnnParams{ m: 16, ef_construction: 200, ef_search: 64 };
}

// m must be a legal graph degree (bounded by the shared core ceiling); the ef_*
// beam widths must be positive. See docs/hnsw-design.md.
pub fn ann_params_valid(p: &AnnParams) -> Bool {
  if p.m <= 0 { return false; }
  if p.m > max_graph_degree() { return false; }
  if p.ef_construction <= 0 { return false; }
  if p.ef_search <= 0 { return false; }
  return true;
}

pub fn ann_index_kind_name(k: &AnnIndexKind) -> Str {
  match k {
    Flat => "flat",
    Hnsw => "hnsw",
    Ivf => "ivf",
  }
}
