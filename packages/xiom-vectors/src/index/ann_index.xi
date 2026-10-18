// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

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

// Stable wire/on-disk codes for the index kind: 1 = Flat, 2 = Hnsw,
// 3 = Ivf. Shared by the WAL collection-manifest record and the durable
// manifest file (D2); the codes are part of the on-disk format.
pub fn ann_kind_code(k: AnnIndexKind) -> Int {
  if k == AnnIndexKind.Flat { return 1; }
  if k == AnnIndexKind.Hnsw { return 2; }
  return 3;
}

pub fn ann_kind_from_code(c: Int) -> AnnIndexKind {
  if c == 1 { return AnnIndexKind.Flat; }
  if c == 2 { return AnnIndexKind.Hnsw; }
  return AnnIndexKind.Ivf;
}