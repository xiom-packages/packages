// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: batch ops (M-Q2) -- upsert_many / delete_many / search_many on the
// real modules. Checks happy paths, all-or-nothing validation (bad dimension
// leaves the engine untouched), batch-delete semantics (missing ids skipped,
// count = actual removals), search_many vs per-query search bit-equality,
// WAL durability across checkpoint+recover, and the Hnsw batch path.
// Exit = failed checks.

module probe_batch_ops

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.durability.wal;
use xiom.vector.durability.wal_file;
use xiom.vectors;
use xiom.io;
use xiom.convert;

fn int_to_str(n: Int) -> Str {
  return convert.int_to_string(n);
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

fn same_results(a: &Vec[SearchResult], b: &Vec[SearchResult]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i].id != b[i].id { return false; }
    if a[i].distance != b[i].distance { return false; }
    i = i + 1;
  }
  return true;
}

fn main() -> Int {
  io.println("=== xvector probe: batch ops ===");
  var fails: Int = 0;
  var dim: Int = 4;
  var n: Int = 200;
  var s: Int = 13579;

  var eng = engine_new();
  create_collection(&mut eng, dim, DistanceMetric.Cosine);

  // Batch upsert 200 points.
  var ids = Vec[Int].new();
  var vecs = Vec[Vector].new();
  var i: Int = 1;
  while i <= n {
    var c = Vec[Float32].new();
    s = rand_coords(s, dim, &mut c);
    ids.push(i);
    vecs.push(vec_from_coords(&c));
    i = i + 1;
  }
  match upsert_many(&mut eng, &ids, &vecs) {
    Ok(n2) => { fails = check(n2 == n, "batch upsert: returns the batch size", fails); }
    Err(_) => { fails = check(false, "batch upsert: Ok expected", fails); }
  }
  fails = check(engine_size(&eng) == n, "batch upsert: all points in the store", fails);

  // Search_many equals per-query search, set by set.
  var qs = Vec[Vector].new();
  var q1c = Vec[Float32].new();
  s = rand_coords(s, dim, &mut q1c);
  qs.push(vec_from_coords(&q1c));
  var q2c = Vec[Float32].new();
  s = rand_coords(s, dim, &mut q2c);
  qs.push(vec_from_coords(&q2c));
  var q3c = Vec[Float32].new();
  s = rand_coords(s, dim, &mut q3c);
  qs.push(vec_from_coords(&q3c));
  var batch_ok: Bool = false;
  match search_many(&eng, &qs, 5) {
    Ok(b) => {
      batch_ok = b.sets.len() == 3;
      var qi: Int = 0;
      while qi < 3 {
        match search(&eng, &qs[qi], 5) {
          Ok(single) => {
            if !same_results(&b.sets[qi].items, &single.items) { batch_ok = false; }
          }
          Err(_) => { batch_ok = false; }
        }
        qi = qi + 1;
      }
    }
    Err(_) => {}
  }
  fails = check(batch_ok, "batch search: 3 sets equal per-query search", fails);

  // All-or-nothing: one bad dimension -> nothing applied.
  var badids = Vec[Int].new();
  badids.push(9001); badids.push(9002);
  var badvecs = Vec[Vector].new();
  var bc = Vec[Float32].new();
  s = rand_coords(s, dim, &mut bc);
  badvecs.push(vec_from_coords(&bc));
  badvecs.push(Vector.new(dim - 1));
  var bad_rejected: Bool = false;
  match upsert_many(&mut eng, &badids, &badvecs) {
    Ok(_) => {}
    Err(_) => { bad_rejected = true; }
  }
  fails = check(bad_rejected && engine_size(&eng) == n,
    "batch upsert: bad dimension rejected, nothing applied", fails);

  // Length mismatch + empty batch rejected.
  var short = Vec[Vector].new();
  short.push(Vector.new(dim));
  var mid_rejected: Bool = false;
  match upsert_many(&mut eng, &badids, &short) {
    Ok(_) => {}
    Err(_) => { mid_rejected = true; }
  }
  fails = check(mid_rejected, "batch upsert: length mismatch rejected", fails);
  var empty_i = Vec[Int].new();
  var empty_v = Vec[Vector].new();
  var e1: Bool = false;
  match upsert_many(&mut eng, &empty_i, &empty_v) { Ok(_) => {} Err(_) => { e1 = true; } }
  fails = check(e1, "batch upsert: empty rejected", fails);
  var e2: Bool = false;
  match delete_many(&mut eng, &empty_i) { Ok(_) => {} Err(_) => { e2 = true; } }
  fails = check(e2, "batch delete: empty rejected", fails);

  // Batch delete: missing ids are skipped; count = actual removals.
  var del = Vec[Int].new();
  var d: Int = 1;
  while d <= 50 {
    del.push(d);
    d = d + 1;
  }
  del.push(9001);
  del.push(9002);
  match delete_many(&mut eng, &del) {
    Ok(n2) => { fails = check(n2 == 50, "batch delete: 50 removed (2 missing skipped)", fails); }
    Err(_) => { fails = check(false, "batch delete: Ok expected", fails); }
  }
  fails = check(engine_size(&eng) == n - 50, "batch delete: store shrank by 50", fails);

  // Durability: checkpoint + recover preserves counts and search results.
  var pa = "out/batch_probe.wal";
  fails = check(wal_persist(&eng.wal, pa), "batch: persist checkpoint", fails);
  var rec = engine_recover(&wal_load(pa), dim, DistanceMetric.Cosine);
  fails = check(engine_size(&rec) == engine_size(&eng), "batch: recovered size equal", fails);
  var rec_ok: Bool = false;
  match search_many(&rec, &qs, 5) {
    Ok(b) => {
      rec_ok = true;
      var qi: Int = 0;
      while qi < 3 {
        match search(&eng, &qs[qi], 5) {
          Ok(live) => {
            if !same_results(&b.sets[qi].items, &live.items) { rec_ok = false; }
          }
          Err(_) => { rec_ok = false; }
        }
        qi = qi + 1;
      }
    }
    Err(_) => {}
  }
  fails = check(rec_ok, "batch: recovered engine searches identically", fails);

  // Duplicate ids inside one batch collapse in the store (count = batch size).
  var dupi = Vec[Int].new();
  dupi.push(500); dupi.push(500);
  var dupv = Vec[Vector].new();
  var dc = Vec[Float32].new();
  s = rand_coords(s, dim, &mut dc);
  dupv.push(vec_from_coords(&dc));
  var dc2 = Vec[Float32].new();
  s = rand_coords(s, dim, &mut dc2);
  dupv.push(vec_from_coords(&dc2));
  var size_before: Int = engine_size(&eng);
  match upsert_many(&mut eng, &dupi, &dupv) {
    Ok(n2) => { fails = check(n2 == 2 && engine_size(&eng) == size_before + 1,
      "batch upsert: duplicate ids collapse in the store", fails); }
    Err(_) => { fails = check(false, "batch upsert: duplicate ids Ok expected", fails); }
  }

  // Hnsw batch path: set_index then batch upsert + batch search.
  let _ = set_index(&mut eng, AnnIndexKind.Hnsw, ann_params_default());
  var hids = Vec[Int].new();
  var hvecs = Vec[Vector].new();
  var h: Int = 1;
  while h <= 20 {
    var hc = Vec[Float32].new();
    s = rand_coords(s, dim, &mut hc);
    hids.push(1000 + h);
    hvecs.push(vec_from_coords(&hc));
    h = h + 1;
  }
  var hnsw_ok: Bool = false;
  match upsert_many(&mut eng, &hids, &hvecs) {
    Ok(n2) => {
      match search_many(&eng, &qs, 5) {
        Ok(b) => { hnsw_ok = n2 == 20 && b.sets.len() == 3 && b.sets[0].items.len() == 5; }
        Err(_) => {}
      }
    }
    Err(_) => {}
  }
  fails = check(hnsw_ok, "batch: Hnsw upsert_many + search_many work", fails);

  io.remove_file(pa);
  io.println("");
  io.println("probe_batch_ops: " + int_to_str(fails) + " failed checks");
  return fails;
}
