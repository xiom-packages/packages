// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.ann

// ANN index surface extracted from XVECTOR
// (E:\xiom-projects\xiom-xvector @ 8a8b0ff; see SPEC.md section 2 for the
// per-file SHA256 pins): the AnnIndexKind dispatch type with its stable
// on-disk codes, AnnParams + validation, and the exact flat-scan oracle used
// by the package's recall harness. The HNSW graph lives in `xiom.ann.hnsw`.
// No engine, no payload/segment/query services (those stay XVECTOR /
// xiom.db territory). No contracts and no unsafe by policy.

use xiom.vectors;

// ==== ANN index kind + params (xvector src/index/ann_index.xi) ====

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
    AnnIndexKind.Flat => "flat",
    AnnIndexKind.Hnsw => "hnsw",
    AnnIndexKind.Ivf => "ivf",
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

// ==== Exact flat scan (the local oracle surface; SPEC.md section 3) ====

// Ascending (distance, id) order: closer first, id ascending on ties.
fn flat_before(prev: Neighbor, cur: Neighbor) -> Bool {
  if cur.distance < prev.distance { return true; }
  if cur.distance > prev.distance { return false; }
  return cur.id < prev.id;
}

// Sorted bounded insert of a Neighbor (ascending by (distance, id), capacity
// `cap`); the reference push-then-truncate shape.
fn flat_push_bounded(list: &mut Vec[Neighbor], id: UInt64, distance: Float32, cap: Int) {
  list.push(Neighbor{ id: id, distance: distance });
  var pos: Int = list.len() - 1;
  while pos > 0 && flat_before(list[pos - 1], list[pos]) {
    var tmp = list[pos];
    list[pos] = list[pos - 1];
    list[pos - 1] = tmp;
    pos = pos - 1;
  }
  if list.len() > cap {
    list.pop();
  }
}

// Brute-force exact k-nearest scan over parallel arrays: `ids[i]` is the user
// id of `vectors[i]`. Entries whose dimension differs from the query are
// skipped; results are distance-ascending with id-ascending tie-breaks,
// capped at k (fewer when the dataset is smaller or dims mismatch).
pub fn flat_search(vectors: &Vec[Vector], ids: &Vec[UInt64], q: &Vector, k: Int, metric: DistanceMetric) -> Vec[Neighbor] {
  var out = Vec[Neighbor].new();
  var i: Int = 0;
  while i < vectors.len() {
    if vectors[i].dimension == q.dimension {
      let d = vector_distance(&vectors[i], q, metric);
      flat_push_bounded(&mut out, ids[i], d, k);
    }
    i = i + 1;
  }
  return out;
}
