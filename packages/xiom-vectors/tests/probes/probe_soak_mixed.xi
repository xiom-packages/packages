// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Soak probe: a sustained deterministic mixed workload against the real
// engine on an Hnsw collection -- upserts (incl. updates), plain and
// filtered searches, payload sets, deletes, periodic graph compaction, and
// a final recovery (plus chained recovery). Every operation is checked
// against independent bookkeeping, so silent divergence (stale store
// entries, tombstone leaks, payload orphans, lost records) fails the probe.
// Exit = failed checks.

module probe_soak_mixed

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.index.hnsw;
use xiom.vector.storage.vector_store;
use xiom.vector.query.search_service;
use xiom.vectors;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.io;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = ""; var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  if neg { out = "-" + out; }
  return out;
}

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn lcg_next(s: Int) -> Int {
  return (s * 1103515245 + 12345) % 2147483648;
}

fn rand_coords(state: Int, dim: Int, coords: &mut Vec[Float32]) -> Int {
  var s = state;
  var i: Int = 0;
  while i < dim {
    s = lcg_next(s);
    var c = (s % 4001) as Float32;
    coords.push(c / 1000.0 - 2.0);
    i = i + 1;
  }
  return s;
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

fn sorted_ok(items: &Vec[SearchResult]) -> Bool {
  var i: Int = 1;
  while i < items.len() {
    if items[i - 1].distance > items[i].distance { return false; }
    i = i + 1;
  }
  return true;
}

fn unique_ok(items: &Vec[SearchResult]) -> Bool {
  var i: Int = 0;
  while i < items.len() {
    var j: Int = i + 1;
    while j < items.len() {
      if items[i].id == items[j].id { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

fn main() -> Int {
  io.println("=== xvector probe: mixed-workload soak ===");
  var fails: Int = 0;

  var dim: Int = 8;
  var max_id: Int = 500;
  var initial: Int = 400;
  var rounds: Int = 600;

  // bookkeeping: index by point id
  var present = Vec[Bool].new();
  var ever = Vec[Bool].new();
  var has_payload = Vec[Bool].new();
  var i: Int = 0;
  while i <= max_id {
    present.push(false);
    ever.push(false);
    has_payload.push(false);
    i = i + 1;
  }
  var live: Int = 0;
  var positions: Int = 0;
  var payload_count: Int = 0;

  var eng = engine_new();
  create_collection(&mut eng, dim, DistanceMetric.Euclidean);
  var s: Int = 424242;

  var id: Int = 1;
  while id <= initial {
    var c = Vec[Float32].new();
    s = rand_coords(s, dim, &mut c);
    var v = vec_from_coords(&c);
    upsert(&mut eng, id, v);
    present[id] = true;
    ever[id] = true;
    live = live + 1;
    positions = positions + 1;
    id = id + 1;
  }
  fails = check(engine_size(&eng) == initial, "setup: 400 points inserted", fails);

  // Hnsw collection for the soak (graph upkeep + compaction + filtered ANN).
  match set_index(&mut eng, AnnIndexKind.Hnsw, ann_params_default()) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  fails = check(hnsw_size(&eng.graph) == initial, "setup: Hnsw graph built (400 nodes)", fails);

  // invariant failure counters
  var bad_search: Int = 0;
  var bad_filtered: Int = 0;
  var bad_payload_flag: Int = 0;
  var bad_delete_flag: Int = 0;
  var c_upsert: Int = 0;
  var c_search: Int = 0;
  var c_filtered: Int = 0;
  var c_payload: Int = 0;
  var c_delete: Int = 0;

  var op: Int = 0;
  while op < rounds {
    s = lcg_next(s);
    var kind = (s / 4096) % 10;         // high bits: LCG low bits are degenerate
    s = lcg_next(s);
    var pid = 1 + ((s / 8192) % max_id);

    if kind < 5 {
      // upsert (new or update)
      c_upsert = c_upsert + 1;
      var c = Vec[Float32].new();
      s = rand_coords(s, dim, &mut c);
      var v = vec_from_coords(&c);
      match upsert(&mut eng, pid, v) {
        Ok(_) => {}
        Err(_) => { fails = fails + 1; }
      }
      if !present[pid] {
        present[pid] = true;
        live = live + 1;
      }
      if !ever[pid] {
        ever[pid] = true;
        positions = positions + 1;
      }
    } elif kind < 7 {
      // plain search: bounded, sorted, unique, all ids live in the store
      c_search = c_search + 1;
      var c = Vec[Float32].new();
      s = rand_coords(s, dim, &mut c);
      var q = vec_from_coords(&c);
      match search(&eng, &q, 10) {
        Ok(h) => {
          if h.items.len() > 10 { bad_search = bad_search + 1; }
          if !sorted_ok(&h.items) { bad_search = bad_search + 1; }
          if !unique_ok(&h.items) { bad_search = bad_search + 1; }
          var r: Int = 0;
          while r < h.items.len() {
            match index_get(&eng.store, h.items[r].id) {
              Some(_) => {}
              None => { bad_search = bad_search + 1; }
            }
            r = r + 1;
          }
        }
        Err(_) => { bad_search = bad_search + 1; }
      }
    } elif kind == 7 {
      // filtered search: bounded, every hit carries the matching bucket
      c_filtered = c_filtered + 1;
      var c = Vec[Float32].new();
      s = rand_coords(s, dim, &mut c);
      var q = vec_from_coords(&c);
      var bucket = (s / 16384) % 5;
      var flt = filter_eq("bucket", FieldValue.IntVal(bucket));
      match search_filtered(&eng, &q, 5, &flt) {
        Ok(h) => {
          if h.items.len() > 5 { bad_filtered = bad_filtered + 1; }
          var r: Int = 0;
          while r < h.items.len() {
            var matched: Bool = false;
            match payload_store_get(&eng.payloads, h.items[r].id) {
              Some(p) => {
                var pp = p;
                match payload_get(&pp, "bucket") {
                  Some(v) => {
                    var want = FieldValue.IntVal(bucket);
                    if field_value_eq(&v, &want) { matched = true; }
                  }
                  None => {}
                }
              }
              None => {}
            }
            if !matched { bad_filtered = bad_filtered + 1; }
            r = r + 1;
          }
        }
        Err(_) => { bad_filtered = bad_filtered + 1; }
      }
    } elif kind == 8 {
      // payload set: Ok flag must equal presence
      c_payload = c_payload + 1;
      var p = payload_new();
      payload_set(&mut p, "bucket", FieldValue.IntVal(pid % 5));
      payload_set(&mut p, "tag", FieldValue.IntVal(pid));
      match set_payload(&mut eng, pid, p) {
        Ok(ok) => {
          if ok != present[pid] { bad_payload_flag = bad_payload_flag + 1; }
          if present[pid] && !has_payload[pid] {
            has_payload[pid] = true;
            payload_count = payload_count + 1;
          }
        }
        Err(_) => { bad_payload_flag = bad_payload_flag + 1; }
      }
    } else {
      // delete: Ok flag must equal presence; payload count follows
      c_delete = c_delete + 1;
      match delete_point(&mut eng, pid) {
        Ok(ok) => {
          if ok != present[pid] { bad_delete_flag = bad_delete_flag + 1; }
          if present[pid] {
            present[pid] = false;
            live = live - 1;
            if has_payload[pid] {
              has_payload[pid] = false;
              payload_count = payload_count - 1;
            }
          }
        }
        Err(_) => { bad_delete_flag = bad_delete_flag + 1; }
      }
    }

    // periodic consistency + compaction
    if op % 150 == 149 {
      if engine_size(&eng) != live { fails = fails + 1; }
      if payload_store_len(&eng.payloads) != payload_count { fails = fails + 1; }
      if hnsw_live_count(&eng.graph) != live { fails = fails + 1; }
      match compact_index(&mut eng) {
        Ok(_) => {}
        Err(_) => { fails = fails + 1; }
      }
      positions = live;
      if hnsw_size(&eng.graph) != live { fails = fails + 1; }
      if hnsw_live_count(&eng.graph) != live { fails = fails + 1; }
    }
    op = op + 1;
  }
  io.println("    diag soak: rounds=" + int_to_str(rounds) + " live=" + int_to_str(live)
    + " payloads=" + int_to_str(payload_count) + " graph=" + int_to_str(hnsw_size(&eng.graph)));
  io.println("    diag ops: upsert=" + int_to_str(c_upsert) + " search=" + int_to_str(c_search)
    + " filtered=" + int_to_str(c_filtered) + " payload=" + int_to_str(c_payload)
    + " delete=" + int_to_str(c_delete));
  fails = check(bad_search == 0, "soak: search invariants held every op", fails);
  fails = check(bad_filtered == 0, "soak: filtered hits always carry the matching bucket", fails);
  fails = check(bad_payload_flag == 0, "soak: set_payload Ok flag == presence", fails);
  fails = check(bad_delete_flag == 0, "soak: delete Ok flag == presence", fails);
  fails = check(engine_size(&eng) == live && payload_store_len(&eng.payloads) == payload_count
    && hnsw_live_count(&eng.graph) == live && hnsw_size(&eng.graph) == live
    && positions == live,
    "soak end: store/graph/payload bookkeeping all agree", fails);

  // final recovery + chained recovery
  var rec = engine_recover(&eng.wal, dim, DistanceMetric.Euclidean);
  fails = check(engine_size(&rec) == live && payload_store_len(&rec.payloads) == payload_count,
    "recovery: store + payloads rebuilt from the WAL", fails);
  match set_index(&mut rec, AnnIndexKind.Hnsw, ann_params_default()) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  var cq = Vector.new(dim);
  cq.set(0, 0.5);
  cq.set(1, 0.25);
  var bad_rec: Int = 0;
  match search(&rec, &cq, 10) {
    Ok(h) => {
      if h.items.len() > 10 || !sorted_ok(&h.items) { bad_rec = bad_rec + 1; }
      var r: Int = 0;
      while r < h.items.len() {
        match index_get(&rec.store, h.items[r].id) {
          Some(_) => {}
          None => { bad_rec = bad_rec + 1; }
        }
        r = r + 1;
      }
    }
    Err(_) => { bad_rec = bad_rec + 1; }
  }
  fails = check(bad_rec == 0, "recovered Hnsw engine: search invariants hold", fails);
  var rec2 = engine_recover(&rec.wal, dim, DistanceMetric.Euclidean);
  // diag: how many tombstone ids are inside the store / how many Delete
  // records in the checkpoint log name live ids?
  var cross: Int = 0;
  var ti2: Int = 0;
  while ti2 < rec.tombstones.len() {
    match index_get(&rec.store, rec.tombstones[ti2]) {
      Some(_) => { cross = cross + 1; }
      None => {}
    }
    ti2 = ti2 + 1;
  }
  var del_live: Int = 0;
  var wr_i: Int = 0;
  while wr_i < rec.wal.records.len() {
    if rec.wal.records[wr_i].op == WalOpKind.Delete {
      match index_get(&rec.store, rec.wal.records[wr_i].key) {
        Some(_) => { del_live = del_live + 1; }
        None => {}
      }
    }
    wr_i = wr_i + 1;
  }
  io.println("    diag chained: rec size=" + int_to_str(engine_size(&rec))
    + " payloads=" + int_to_str(payload_store_len(&rec.payloads))
    + " wal_records=" + int_to_str(rec.wal.records.len())
    + " tombstones=" + int_to_str(rec.tombstones.len())
    + " cross=" + int_to_str(cross)
    + " del_live=" + int_to_str(del_live)
    + " | rec2 size=" + int_to_str(engine_size(&rec2))
    + " payloads=" + int_to_str(payload_store_len(&rec2.payloads)));
  fails = check(engine_size(&rec2) == engine_size(&rec)
    && payload_store_len(&rec2.payloads) == payload_store_len(&rec.payloads),
    "chained recovery: store + payloads preserved", fails);

  io.println("");
  io.println("probe_soak_mixed: " + int_to_str(fails) + " failed checks");
  return fails;
}
