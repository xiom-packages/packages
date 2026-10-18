// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.storage.vector_store

// Flat columnar vector store (insert/search/delete by id) + the durable
// vector WAL codec. Extracted from the consolidated engine (post-AUDIT
// module tree).

use xiom.num.float;
use xiom.vector.primitives;

pub type VectorIndex = {
  vectors: Vec[Vector];
  ids: Vec[Int];
  id_keys: Vec[Int];
  id_vals: Vec[Int];
  dim: Int;
}

pub fn index_new(dim: Int) -> VectorIndex
  requires: dim > 0
{
  return VectorIndex{
    vectors: Vec[Vector].new(),
    ids: Vec[Int].new(),
    id_keys: Vec[Int].new(),
    id_vals: Vec[Int].new(),
    dim: dim,
  };
}

// Memory accounting estimate (model constants: see the
// `hnsw_memory_estimate` header). ids/id_keys/id_vals are Vec[Int];
// vectors is Vec[Vector] (each 32 B struct + 4*dim B data heap).
pub fn index_memory_estimate(idx: &VectorIndex) -> Int
  ensures: result >= 0
{
  var n = idx.vectors.len();
  var bytes: Int = 24 + n * 8;  // ids
  bytes = bytes + 24 + n * 8;   // id_keys
  bytes = bytes + 24 + n * 8;   // id_vals
  var vec_bytes: Int = 24;      // Vec[Vector] header
  var i: Int = 0;
  while i < n {
    vec_bytes = vec_bytes + 32 + 4 * idx.vectors[i].dimension;
    i = i + 1;
  }
  return bytes + vec_bytes;
}

// ---- Sorted id -> slot map (binary search; ids are unique) ----
fn idmap_find(idx: &VectorIndex, id: Int) -> Int {
  var lo: Int = 0;
  var hi: Int = idx.id_keys.len();
  while lo < hi {
    var mid: Int = (lo + hi) / 2;
    if idx.id_keys[mid] < id {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if lo < idx.id_keys.len() && idx.id_keys[lo] == id {
    return idx.id_vals[lo];
  }
  return -1;
}

fn idmap_insert(idx: &mut VectorIndex, id: Int, slot: Int) {
  var lo: Int = 0;
  var hi: Int = idx.id_keys.len();
  while lo < hi {
    var mid: Int = (lo + hi) / 2;
    if idx.id_keys[mid] < id { lo = mid + 1; } else { hi = mid; }
  }
  idx.id_keys.push(id);
  idx.id_vals.push(slot);
  var j: Int = idx.id_keys.len() - 1;
  while j > lo {
    idx.id_keys[j] = idx.id_keys[j - 1];
    idx.id_vals[j] = idx.id_vals[j - 1];
    j = j - 1;
  }
  idx.id_keys[lo] = id;
  idx.id_vals[lo] = slot;
}

fn idmap_set(idx: &mut VectorIndex, id: Int, slot: Int) {
  var lo: Int = 0;
  var hi: Int = idx.id_keys.len();
  while lo < hi {
    var mid: Int = (lo + hi) / 2;
    if idx.id_keys[mid] < id { lo = mid + 1; } else { hi = mid; }
  }
  if lo < idx.id_keys.len() && idx.id_keys[lo] == id {
    idx.id_vals[lo] = slot;
  }
}

fn idmap_remove(idx: &mut VectorIndex, id: Int) {
  var lo: Int = 0;
  var hi: Int = idx.id_keys.len();
  while lo < hi {
    var mid: Int = (lo + hi) / 2;
    if idx.id_keys[mid] < id { lo = mid + 1; } else { hi = mid; }
  }
  if lo >= idx.id_keys.len() || idx.id_keys[lo] != id { return; }
  var last: Int = idx.id_keys.len() - 1;
  var j: Int = lo;
  while j < last {
    idx.id_keys[j] = idx.id_keys[j + 1];
    idx.id_vals[j] = idx.id_vals[j + 1];
    j = j + 1;
  }
  idx.id_keys.pop();
  idx.id_vals.pop();
}

// Insert a point, or UPDATE it in place when the id already exists (upsert
// semantics -- the engine's `upsert` documents insert/update, and the HNSW
// graph updates in place, so the store must match). Returns true when the
// store holds the id afterwards. (Earlier revisions rejected duplicates and
// silently kept the old vector, diverging from the graph.)
pub fn index_add(idx: &mut VectorIndex, id: Int, vec: Vector) -> Bool
  requires: idx.dim == vec.dimension
{
  var slot = idmap_find(idx, id);
  if slot >= 0 {
    idx.vectors[slot] = vec;
    return true;
  }
  var pos: Int = idx.ids.len();
  idx.vectors.push(vec);
  idx.ids.push(id);
  idmap_insert(idx, id, pos);
  return true;
}

pub fn index_remove(idx: &mut VectorIndex, id: Int) -> Bool {
  var pos = idmap_find(idx, id);
  if pos < 0 {
    return false;
  }
  var last: Int = idx.ids.len() - 1;
  var moved: Int = idx.ids[last];
  idmap_remove(idx, id);
  if pos != last {
    idx.vectors[pos] = idx.vectors[last];
    idx.ids[pos] = moved;
    idmap_set(idx, moved, pos);
  }
  idx.vectors.pop();
  idx.ids.pop();
  return true;
}

pub fn index_get(idx: &VectorIndex, id: Int) -> Option[Vector] {
  var pos = idmap_find(idx, id);
  if pos >= 0 {
    return Some(idx.vectors[pos]);
  }
  return None;
}

pub fn index_size(idx: &VectorIndex) -> Int {
  return idx.ids.len();
}

// ---- Durable vector codec ----
// The WAL payload codec ([dim, bits0, ...] + strict decode) lives in the
// `xiom.vectors` registry package since the 2026-10-10 adoption; this
// module imports it and `vector_encode`/`vector_decode` resolve through
// that import (extraction pins verified byte-identical source; see
// docs/XIOM-VECTORS-EVAL.md).
