// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: exact range search (M-Q1). Builds a deterministic Flat collection,
// then for several queries computes the expected result with a LOCAL
// brute-force scan (same distance kernel, direct store walk, own bounded
// insertion sort) and asserts `engine_search_range` / facade `search_range`
// match bit-for-bit across radius x limit combinations. Also checks the
// inclusive boundary, radius-0 semantics, error paths (dim mismatch, limit 0,
// negative radius), the Hnsw routing (exact scan path), and reopen equality.
// Exit = failed checks.

module probe_range_search

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.storage.vector_store;
use xiom.vector.query.search_service;
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

// Local brute-force reference: scan the store, keep every distance <= radius
// with a bounded insertion sort (same semantics as the engine kernel).
fn brute_range(eng: &VectorEngine, query: &Vector, radius: Float32, limit: Int, metric: DistanceMetric) -> Vec[SearchResult] {
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = eng.store.ids.len();
  while i < total {
    var dist = vector_distance(&eng.store.vectors[i], query, metric);
    if dist <= radius {
      var result = SearchResult{ id: eng.store.ids[i], distance: dist };
      results.push(result);
      var pos: Int = results.len() - 1;
      while pos > 0 && results[pos - 1].distance > results[pos].distance {
        var tmp = results[pos];
        results[pos] = results[pos - 1];
        results[pos - 1] = tmp;
        pos = pos - 1;
      }
      while results.len() > limit {
        results.pop();
      }
    }
    i = i + 1;
  }
  return results;
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
  io.println("=== xvector probe: exact range search ===");
  var fails: Int = 0;
  var dim: Int = 4;
  var n: Int = 300;
  var s: Int = 24680;

  var eng = engine_new();
  create_collection(&mut eng, dim, DistanceMetric.Cosine);
  var i: Int = 1;
  while i <= n {
    var c = Vec[Float32].new();
    s = rand_coords(s, dim, &mut c);
    upsert(&mut eng, i, vec_from_coords(&c));
    i = i + 1;
  }

  var radii = Vec[Float32].new();
  radii.push(0.0);
  radii.push(0.1);
  radii.push(0.3);
  radii.push(0.6);
  radii.push(1.0);
  radii.push(2.5);
  var limits = Vec[Int].new();
  limits.push(1);
  limits.push(5);
  limits.push(25);
  limits.push(1000);

  var queries = 3;
  var mismatches: Int = 0;
  var qn: Int = 0;
  while qn < queries {
    var qc = Vec[Float32].new();
    s = rand_coords(s, dim, &mut qc);
    var q = vec_from_coords(&qc);
    var ri: Int = 0;
    while ri < radii.len() {
      var li: Int = 0;
      while li < limits.len() {
        var expected = brute_range(&eng, &q, radii[ri], limits[li], DistanceMetric.Cosine);
        var got = search_range(&eng, &q, radii[ri], limits[li]);
        match got {
          Ok(h) => {
            if !same_results(&expected, &h.items) { mismatches = mismatches + 1; }
          }
          Err(_) => { mismatches = mismatches + 1; }
        }
        li = li + 1;
      }
      ri = ri + 1;
    }
    qn = qn + 1;
  }
  fails = check(mismatches == 0, "range: 72 radius x limit combos match the brute-force scan", fails);

  // Facade path equals the engine path (query from a fresh draw).
  var fc = Vec[Float32].new();
  s = rand_coords(s, dim, &mut fc);
  var fq = vec_from_coords(&fc);
  var fr = search_range(&eng, &fq, 0.6, 5);
  var er = engine_search_range(&eng, &fq, 0.6, 5);
  var facade_ok: Bool = false;
  match fr {
    Ok(a) => {
      match er {
        Ok(b) => { facade_ok = same_results(&a.items, &b.items); }
        Err(_) => {}
      }
    }
    Err(_) => {}
  }
  fails = check(facade_ok, "range: facade equals engine_search_range", fails);

  // Inclusive boundary: radius exactly equal to a point's distance includes it.
  var bc = Vec[Float32].new();
  s = rand_coords(s, dim, &mut bc);
  var bq = vec_from_coords(&bc);
  match index_get(&eng.store, 7) {
    Some(p7) => {
      var d7 = vector_distance(&p7, &bq, DistanceMetric.Cosine);
      var br = search_range(&eng, &bq, d7, 1000);
      match br {
        Ok(h) => {
          var found: Bool = false;
          var j: Int = 0;
          while j < h.items.len() {
            if h.items[j].id == 7 { found = true; }
            j = j + 1;
          }
          fails = check(found, "range: radius == exact distance is inclusive", fails);
        }
        Err(_) => { fails = fails + 1; }
      }
    }
    None => { fails = fails + 1; }
  }

  // Radius 0 keeps only exact matches (random query: none of the points).
  var zr = search_range(&eng, &bq, 0.0, 1000);
  var zero_len: Int = -1;
  match zr { Ok(h) => { zero_len = h.items.len(); } Err(_) => {} }
  fails = check(zero_len == 0, "range: radius 0 -> only exact matches (none here)", fails);

  // Huge radius + limit k equals KNN k.
  var kn = search(&eng, &bq, 5);
  var rg = search_range(&eng, &bq, 2.5, 5);
  var knn_ok: Bool = false;
  match kn {
    Ok(a) => {
      match rg {
        Ok(b) => { knn_ok = same_results(&a.items, &b.items); }
        Err(_) => {}
      }
    }
    Err(_) => {}
  }
  fails = check(knn_ok, "range: radius-all with limit k equals KNN k", fails);

  // Error paths.
  var short = Vector.new(3);
  var e1 = search_range(&eng, &short, 1.0, 5);
  var e1_err: Bool = false;
  match e1 { Ok(_) => {} Err(_) => { e1_err = true; } }
  fails = check(e1_err, "range: dimension mismatch rejected", fails);
  var e2 = search_range(&eng, &bq, 1.0, 0);
  var e2_err: Bool = false;
  match e2 { Ok(_) => {} Err(_) => { e2_err = true; } }
  fails = check(e2_err, "range: limit 0 rejected", fails);
  var e3 = search_range(&eng, &bq, 0.0 - 1.0, 5);
  var e3_err: Bool = false;
  match e3 { Ok(_) => {} Err(_) => { e3_err = true; } }
  fails = check(e3_err, "range: negative radius rejected", fails);

  // Hnsw routing: the range path is exact on both index kinds.
  let _ = set_index(&mut eng, AnnIndexKind.Hnsw, ann_params_default());
  var hm: Int = 0;
  var hi: Int = 0;
  while hi < radii.len() {
    var expected = brute_range(&eng, &bq, radii[hi], 25, DistanceMetric.Cosine);
    match search_range(&eng, &bq, radii[hi], 25) {
      Ok(h) => {
        if !same_results(&expected, &h.items) { hm = hm + 1; }
      }
      Err(_) => { hm = hm + 1; }
    }
    hi = hi + 1;
  }
  fails = check(hm == 0, "range: Hnsw collection stays exact (store scan)", fails);

  // Reopen: range results identical after checkpoint + recover.
  var pa = "out/range_probe.wal";
  fails = check(wal_persist(&eng.wal, pa), "range: persist checkpoint", fails);
  var rec = engine_recover(&wal_load(pa), dim, DistanceMetric.Cosine);
  var ro: Int = 0;
  var ri2: Int = 0;
  while ri2 < radii.len() {
    var expected = brute_range(&rec, &bq, radii[ri2], 25, DistanceMetric.Cosine);
    match search_range(&rec, &bq, radii[ri2], 25) {
      Ok(h) => {
        if !same_results(&expected, &h.items) { ro = ro + 1; }
      }
      Err(_) => { ro = ro + 1; }
    }
    ri2 = ri2 + 1;
  }
  fails = check(ro == 0, "range: recovered engine matches brute force", fails);

  io.remove_file(pa);
  io.println("");
  io.println("probe_range_search: " + int_to_str(fails) + " failed checks");
  return fails;
}
