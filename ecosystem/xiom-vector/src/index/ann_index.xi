module xiom.vector.index.ann_index

fn max_graph_degree() -> Int {
  return 512;
}

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