// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: memory accounting estimate (M-P P2). Validates the per-collection
// estimate (store + graph + payloads + the engine-wide WAL) against an
// INDEPENDENT recomputation of the documented model from live structure
// state, plus structural invariants:
//   - flat collections report zero graph bytes;
//   - the per-insert HNSW graph delta is level-independent (rows are
//     uniformly allocated) and exact;
//   - deletes leave graph bytes unchanged (tombstones) while
//     compact_index reclaims to the live-node model;
//   - payload text bytes are counted exactly (entry + field + key + text
//     + index rows);
//   - parked collections report from their registry entry;
//   - unknown names -> Err.
// Exit = failed checks.

module probe_memory_estimate

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.hnsw;
use xiom.vector.index.ann_index;
use xiom.vector.payload.payload;
use xiom.vector.storage.vector_store;
use xiom.vector.durability.wal;
use xiom.vectors;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn vec_from_coords(coords: &Vec[Float32]) -> Vector {
  var v = Vector.new(coords.len());
  var i: Int = 0;
  while i < coords.len() {
    v.set(i, coords[i]);
    i = i + 1;
  }
  return v;
}

// ---- independent recomputations of the documented model ----

fn graph_bytes_expected(eng: &VectorEngine) -> Int {
  var n = eng.graph.ids.len();
  var rows = n * 8;
  var slots = rows * eng.graph.m0;
  var vec_bytes: Int = 24;
  var i: Int = 0;
  while i < n {
    vec_bytes = vec_bytes + 32 + 4 * eng.graph.vectors[i].dimension;
    i = i + 1;
  }
  var bytes: Int = 56;
  bytes = bytes + 24 + n * 8;
  bytes = bytes + vec_bytes;
  bytes = bytes + 24 + n * 8;
  bytes = bytes + 24 + n * 1;
  bytes = bytes + 24 + n * 8;
  bytes = bytes + 24 + n * 8;
  bytes = bytes + 24 + rows * 8;
  bytes = bytes + 24 + slots * 8;
  return bytes;
}

fn store_bytes_expected(eng: &VectorEngine) -> Int {
  var n = eng.store.vectors.len();
  var bytes: Int = 24 + n * 8;
  bytes = bytes + 24 + n * 8;
  bytes = bytes + 24 + n * 8;
  var vec_bytes: Int = 24;
  var i: Int = 0;
  while i < n {
    vec_bytes = vec_bytes + 32 + 4 * eng.store.vectors[i].dimension;
    i = i + 1;
  }
  return bytes + vec_bytes;
}

fn payload_bytes_expected(eng: &VectorEngine) -> Int {
  var s = eng.payloads;
  var bytes: Int = 24;
  var i: Int = 0;
  while i < s.entries.len() {
    var p = s.entries[i].payload;
    bytes = bytes + 8 + 24 + 24;
    var f: Int = 0;
    while f < p.fields.len() {
      var k = p.fields[f].key;
      bytes = bytes + 56 + k.len();
      var fv = p.fields[f].value;
      match fv {
        TextVal(t) => { bytes = bytes + t.len(); }
        _ => {}
      }
      f = f + 1;
    }
    i = i + 1;
  }
  bytes = bytes + (24 + s.index_field.len() * 24);
  bytes = bytes + (24 + s.index_kind.len() * 8);
  bytes = bytes + (24 + s.index_num.len() * 8);
  bytes = bytes + (24 + s.index_text.len() * 24);
  bytes = bytes + (24 + s.index_id.len() * 8);
  return bytes;
}

fn wal_bytes_expected(eng: &VectorEngine) -> Int {
  var bytes: Int = 24;
  var i: Int = 0;
  while i < eng.wal.records.len() {
    bytes = bytes + 64 + eng.wal.records[i].payload.len() * 8;
    i = i + 1;
  }
  return bytes;
}

fn default_est() -> MemoryEstimate {
  return MemoryEstimate{
    name: "",
    dim: 0,
    points: 0,
    index_kind: AnnIndexKind.Flat,
    store_bytes: 0,
    graph_bytes: 0,
    payload_bytes: 0,
    total_bytes: 0,
    wal_bytes: 0,
  };
}

fn est_of(eng: &VectorEngine, name: Str) -> MemoryEstimate {
  var out = default_est();
  match memory_estimate(eng, name) {
    Ok(m) => { out = m; }
    Err(_) => {}
  }
  return out;
}

fn main() -> Int {
  io.println("=== xvector probe: memory accounting estimate (M-P P2) ===");
  var fails: Int = 0;
  var dim: Int = 4;

  // --- flat baseline: 7 points, no payloads ---
  var eng = engine_new();
  create_collection(&mut eng, dim, DistanceMetric.Euclidean);
  var i: Int = 1;
  while i <= 7 {
    var c = Vec[Float32].new();
    var j: Int = 0;
    while j < dim {
      c.push((i + j) as Float32);
      j = j + 1;
    }
    upsert(&mut eng, i, vec_from_coords(&c));
    i = i + 1;
  }
  var m1 = est_of(&eng, "default");
  fails = check(m1.points == 7 && m1.dim == 4 && m1.index_kind == AnnIndexKind.Flat,
    "flat: identity fields (7 points, dim 4, flat)", fails);
  fails = check(m1.graph_bytes == 0, "flat: graph bytes are zero", fails);
  fails = check(m1.store_bytes == store_bytes_expected(&eng),
    "flat: store bytes == independent model", fails);
  fails = check(m1.payload_bytes == payload_bytes_expected(&eng),
    "flat: payload bytes == model (empty store)", fails);
  fails = check(m1.total_bytes == m1.store_bytes + m1.graph_bytes + m1.payload_bytes,
    "flat: total = store + graph + payloads", fails);
  fails = check(m1.wal_bytes == wal_bytes_expected(&eng) && m1.wal_bytes > 0,
    "flat: engine WAL bytes == model", fails);

  // --- hnsw: full recompute + exact level-independent per-insert delta ---
  match set_index(&mut eng, AnnIndexKind.Hnsw, AnnParams{ m: 8, ef_construction: 50, ef_search: 20 }) {
    Ok(_) => {}
    Err(_) => {}
  }
  var m2 = est_of(&eng, "default");
  fails = check(m2.graph_bytes == graph_bytes_expected(&eng) && m2.graph_bytes > 0,
    "hnsw: graph bytes == independent model (full recompute)", fails);

  var c8 = Vec[Float32].new();
  var j8: Int = 0;
  while j8 < dim {
    c8.push(1.5 as Float32);
    j8 = j8 + 1;
  }
  upsert(&mut eng, 8, vec_from_coords(&c8));
  var m3 = est_of(&eng, "default");
  var expect_delta: Int = 129 + 4 * dim + 64 * eng.graph.m0;
  fails = check(m3.graph_bytes - m2.graph_bytes == expect_delta,
    "hnsw: per-insert graph delta exact and level-independent", fails);
  fails = check(m3.wal_bytes > m2.wal_bytes, "wal: grows with the new record", fails);

  // --- delete (tombstone) + compact (reclaim) ---
  var del = Vec[Int].new();
  del.push(1);
  del.push(2);
  match delete_many(&mut eng, &del) {
    Ok(_) => {}
    Err(_) => {}
  }
  var m4 = est_of(&eng, "default");
  fails = check(m4.points == 6 && m4.graph_bytes == m3.graph_bytes,
    "delete: points drop, graph bytes unchanged (tombstones)", fails);
  match compact_index(&mut eng) {
    Ok(_) => {}
    Err(_) => {}
  }
  var m5 = est_of(&eng, "default");
  fails = check(m5.graph_bytes == graph_bytes_expected(&eng) && m5.graph_bytes < m4.graph_bytes,
    "compact: graph bytes == model for live nodes (reclaimed)", fails);

  // --- payload text accounting ---
  var p = payload_new();
  payload_set(&mut p, "note", FieldValue.TextVal("hello world"));
  set_payload(&mut eng, 3, p);
  var m6 = est_of(&eng, "default");
  var expect_pdelta: Int = 8 + 24 + 24 + 56 + 4 + 11 + 24 + 8 + 8 + 24 + 8;
  fails = check(m6.payload_bytes - m5.payload_bytes == expect_pdelta,
    "payload: entry + field + key + text + index rows counted exactly", fails);
  fails = check(m6.payload_bytes == payload_bytes_expected(&eng),
    "payload: full recompute matches", fails);

  // --- parked collection reports from its registry entry ---
  match create_named_collection(&mut eng, "mem2", 3, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => {}
  }
  match select_collection(&mut eng, "mem2") {
    Ok(_) => {}
    Err(_) => {}
  }
  var k: Int = 1;
  while k <= 3 {
    var c2 = Vec[Float32].new();
    c2.push(1.0 as Float32);
    c2.push(2.0 as Float32);
    c2.push(3.0 as Float32);
    upsert(&mut eng, k, vec_from_coords(&c2));
    k = k + 1;
  }
  match select_collection(&mut eng, "default") {
    Ok(_) => {}
    Err(_) => {}
  }
  var mem2 = est_of(&eng, "mem2");
  fails = check(mem2.name == "mem2" && mem2.points == 3 && mem2.dim == 3
    && mem2.index_kind == AnnIndexKind.Flat,
    "parked: entry-backed estimate (name/dim/points/kind)", fails);
  fails = check(mem2.total_bytes == mem2.store_bytes + mem2.graph_bytes + mem2.payload_bytes,
    "parked: total invariant", fails);
  fails = check(mem2.wal_bytes == wal_bytes_expected(&eng),
    "wal: engine-wide (matches the live model)", fails);

  // --- unknown collection ---
  var not_found: Bool = false;
  match memory_estimate(&eng, "nope") {
    Ok(_) => {}
    Err(_) => { not_found = true; }
  }
  fails = check(not_found, "unknown collection -> Err", fails);

  io.println("");
  io.println("probe_memory_estimate: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
