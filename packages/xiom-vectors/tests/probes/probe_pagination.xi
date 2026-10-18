// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: pagination (M-Q3). Verifies the paginated total order (distance
// ascending, id ascending) on both offset and after-id paging: pages are
// gap-free and duplicate-free within a fixed engine state and reconstruct
// the reference order; exact equal-distance ties come back ordered by id
// ascending (direct cluster checks); cursor continuation across a tie
// boundary; validation refusals; unknown/deleted cursors; bit-exact parity
// between Flat and Hnsw engines; pagination after recovery. Exit = failed
// checks.

module probe_pagination

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vectors;
use xiom.io;
use xiom.convert;

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

fn dup_vec(v: &Vector) -> Vector {
  var out = Vector.new(v.dimension);
  var i: Int = 0;
  while i < v.dimension {
    out.set(i, v.data[i]);
    i = i + 1;
  }
  return out;
}

// Independent reference order: (distance ascending, id ascending) over the
// live store.
fn reference_ids(eng: &VectorEngine, q: &Vector) -> Vec[Int] {
  var ids = Vec[Int].new();
  var ds = Vec[Float32].new();
  var i: Int = 0;
  while i < engine_size(eng) {
    var d = vector_distance(&eng.store.vectors[i], q, eng.metric);
    ids.push(eng.store.ids[i]);
    ds.push(d);
    var p: Int = ids.len() - 1;
    while p > 0 && (ds[p - 1] > ds[p] || (ds[p - 1] == ds[p] && ids[p - 1] > ids[p])) {
      var td = ds[p];
      ds[p] = ds[p - 1];
      ds[p - 1] = td;
      var ti = ids[p];
      ids[p] = ids[p - 1];
      ids[p - 1] = ti;
      p = p - 1;
    }
    i = i + 1;
  }
  return ids;
}

fn search_page_ids(eng: &VectorEngine, q: &Vector, k: Int, offset: Int) -> Vec[Int] {
  var ids = Vec[Int].new();
  match search_page(eng, q, k, offset) {
    Ok(h) => {
      var i: Int = 0;
      while i < h.items.len() {
        ids.push(h.items[i].id);
        i = i + 1;
      }
    }
    Err(_) => {}
  }
  return ids;
}

fn search_after_ids(eng: &VectorEngine, q: &Vector, k: Int, after_id: Int) -> Vec[Int] {
  var ids = Vec[Int].new();
  match search_after(eng, q, k, after_id) {
    Ok(h) => {
      var i: Int = 0;
      while i < h.items.len() {
        ids.push(h.items[i].id);
        i = i + 1;
      }
    }
    Err(_) => {}
  }
  return ids;
}

fn slice_match(a: &Vec[Int], ref: &Vec[Int], from: Int, count: Int) -> Bool {
  if a.len() != count { return false; }
  var i: Int = 0;
  while i < count {
    if a[i] != ref[from + i] { return false; }
    i = i + 1;
  }
  return true;
}

fn ids_all_equal(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn main() -> Int {
  io.println("=== xvector probe: pagination ===");
  var fails: Int = 0;
  var dim: Int = 3;
  var eng = engine_new();
  create_collection(&mut eng, dim, DistanceMetric.Euclidean);
  var s: Int = 660217;
  var c1 = Vec[Float32].new();
  var c2 = Vec[Float32].new();
  var c20 = Vec[Float32].new();
  var i: Int = 1;
  while i <= 30 {
    var c = Vec<Float32>.new();
    s = rand_coords(s, dim, &mut c);
    if i == 1 {
      var kk: Int = 0;
      while kk < c.len() { c1.push(c[kk]); kk = kk + 1; }
    }
    if i == 2 {
      var kk: Int = 0;
      while kk < c.len() { c2.push(c[kk]); kk = kk + 1; }
    }
    if i == 20 {
      var kk: Int = 0;
      while kk < c.len() { c20.push(c[kk]); kk = kk + 1; }
    }
    upsert(&mut eng, i, vec_from_coords(&c));
    i = i + 1;
  }
  // Exact tie clusters: {1,7,8} share id-1's vector; {2,15,16,17} share id-2's.
  upsert(&mut eng, 7, vec_from_coords(&c1));
  upsert(&mut eng, 8, vec_from_coords(&c1));
  upsert(&mut eng, 15, vec_from_coords(&c2));
  upsert(&mut eng, 16, vec_from_coords(&c2));
  upsert(&mut eng, 17, vec_from_coords(&c2));

  var q20 = vec_from_coords(&c20);
  var qa = vec_from_coords(&c1);
  var ref20 = reference_ids(&eng, &q20);
  var refA = reference_ids(&eng, &qa);

  // --- offset paging reconstructs the reference order ---
  var p0 = search_page_ids(&eng, &q20, 10, 0);
  var p1 = search_page_ids(&eng, &q20, 10, 10);
  var p2 = search_page_ids(&eng, &q20, 10, 20);
  fails = check(slice_match(&p0, &ref20, 0, 10), "offset: page 0 == ranks 0..10", fails);
  fails = check(slice_match(&p1, &ref20, 10, 10), "offset: page 1 == ranks 10..20", fails);
  fails = check(slice_match(&p2, &ref20, 20, 10), "offset: page 2 == ranks 20..30", fails);
  var concat = Vec[Int].new();
  i = 0;
  while i < p0.len() { concat.push(p0[i]); i = i + 1; }
  i = 0;
  while i < p1.len() { concat.push(p1[i]); i = i + 1; }
  i = 0;
  while i < p2.len() { concat.push(p2[i]); i = i + 1; }
  var concat_unique: Bool = concat.len() == ref20.len();
  if concat_unique {
    i = 0;
    while i < concat.len() {
      var j: Int = i + 1;
      while j < concat.len() {
        if concat[i] == concat[j] { concat_unique = false; }
        j = j + 1;
      }
      i = i + 1;
    }
  }
  fails = check(concat_unique && ids_all_equal(&concat, &ref20),
    "offset: three pages concatenate to the full order (no gaps/dupes)", fails);
  fails = check(search_page_ids(&eng, &q20, 10, 30).len() == 0, "offset: beyond the end -> empty", fails);
  fails = check(slice_match(&search_page_ids(&eng, &q20, 100, 25), &ref20, 25, 5),
    "offset: tail page (k=100, offset=25) -> ranks 25..30", fails);

  // --- tie order: id ascending on exact equal distances ---
  var tieA = search_page_ids(&eng, &qa, 3, 0);
  fails = check(tieA.len() == 3 && tieA[0] == 1 && tieA[1] == 7 && tieA[2] == 8,
    "ties: distance-0 cluster {1,7,8} ordered by id ascending", fails);
  var startB: Int = -1;
  i = 0;
  while i < refA.len() {
    if refA[i] == 2 || refA[i] == 15 || refA[i] == 16 || refA[i] == 17 {
      startB = i;
      i = refA.len();
    } else {
      i = i + 1;
    }
  }
  var tieB = search_page_ids(&eng, &qa, 4, startB);
  fails = check(startB >= 3 && tieB.len() == 4 && tieB[0] == 2 && tieB[1] == 15 && tieB[2] == 16 && tieB[3] == 17,
    "ties: cluster {2,15,16,17} ordered by id ascending (at its rank)", fails);

  // --- after-id cursor paging ---
  fails = check(slice_match(&search_after_ids(&eng, &q20, 7, ref20[6]), &ref20, 7, 7),
    "cursor: after rank 6 -> ranks 7..14", fails);
  fails = check(search_after_ids(&eng, &q20, 5, ref20[29]).len() == 0,
    "cursor: after the last rank -> empty", fails);
  var tie_after = search_after_ids(&eng, &qa, 2, 7);
  fails = check(tie_after.len() == 2 && tie_after[0] == 8 && tie_after[1] == refA[3],
    "cursor: tie boundary (after 7 -> 8 at the same distance, then next)", fails);
  var tie_after2 = search_after_ids(&eng, &qa, 3, 1);
  fails = check(tie_after2.len() == 3 && tie_after2[0] == 7 && tie_after2[1] == 8 && tie_after2[2] == refA[3],
    "cursor: after 1 -> {7,8} then next", fails);

  // Full cursor walk (page size 6) reconstructs the reference order.
  var walk = Vec[Int].new();
  var first = search_page_ids(&eng, &q20, 1, 0);
  if first.len() == 1 { walk.push(first[0]); }
  var guard: Int = 0;
  while walk.len() < ref20.len() && guard < 12 {
    var page = search_after_ids(&eng, &q20, 6, walk[walk.len() - 1]);
    if page.len() == 0 {
      guard = 12;
    } else {
      var pi: Int = 0;
      while pi < page.len() {
        walk.push(page[pi]);
        pi = pi + 1;
      }
    }
    guard = guard + 1;
  }
  fails = check(ids_all_equal(&walk, &ref20), "cursor: chained walk of 6 reconstructs the order", fails);

  // --- validation ---
  var e1 = search_page(&eng, &q20, 5, -1);
  var e1_err: Bool = false;
  match e1 { Ok(_) => {} Err(_) => { e1_err = true; } }
  fails = check(e1_err, "validation: negative offset -> Err", fails);
  var e2 = search_page(&eng, &q20, 0, 0);
  var e2_err: Bool = false;
  match e2 { Ok(_) => {} Err(_) => { e2_err = true; } }
  fails = check(e2_err, "validation: k=0 -> Err", fails);
  var e3 = search_page(&eng, &q20, 10001, 0);
  var e3_err: Bool = false;
  match e3 { Ok(_) => {} Err(_) => { e3_err = true; } }
  fails = check(e3_err, "validation: k out of range -> Err", fails);
  var wrong = Vector.new(dim - 1);
  var e4 = search_page(&eng, &wrong, 5, 0);
  var e4_err: Bool = false;
  match e4 { Ok(_) => {} Err(_) => { e4_err = true; } }
  fails = check(e4_err, "validation: dim mismatch -> Err", fails);
  var e5 = search_after(&eng, &q20, 5, 999);
  var e5_err: Bool = false;
  match e5 { Ok(_) => {} Err(_) => { e5_err = true; } }
  fails = check(e5_err, "validation: unknown cursor id -> Err(NotFound)", fails);

  // --- Flat vs Hnsw: bit-identical pagination ---
  var eng2 = engine_new();
  create_collection(&mut eng2, dim, DistanceMetric.Euclidean);
  i = 0;
  while i < engine_size(&eng) {
    upsert(&mut eng2, eng.store.ids[i], dup_vec(&eng.store.vectors[i]));
    i = i + 1;
  }
  var si = set_index(&mut eng2, AnnIndexKind.Hnsw, AnnParams{ m: 8, ef_construction: 50, ef_search: 20 });
  var si_ok: Bool = false;
  match si { Ok(_) => { si_ok = true; } Err(_) => {} }
  fails = check(si_ok && ids_all_equal(&search_page_ids(&eng2, &q20, 10, 0), &p0)
    && ids_all_equal(&search_page_ids(&eng2, &q20, 10, 10), &p1)
    && ids_all_equal(&search_after_ids(&eng2, &q20, 7, ref20[6]), &search_after_ids(&eng, &q20, 7, ref20[6])),
    "index kinds: Hnsw pagination bit-identical to Flat (pages + cursor)", fails);

  // --- pagination after recovery ---
  var rec = engine_recover(&eng.wal, dim, DistanceMetric.Euclidean);
  fails = check(ids_all_equal(&search_page_ids(&rec, &q20, 10, 0), &p0)
    && slice_match(&search_page_ids(&rec, &q20, 10, 10), &ref20, 10, 10),
    "recovery: pages identical after reopen", fails);

  // --- deleted cursor ---
  delete_point(&mut eng, 8);
  var d1 = search_after(&eng, &qa, 2, 8);
  var d1_err: Bool = false;
  match d1 { Ok(_) => {} Err(_) => { d1_err = true; } }
  fails = check(d1_err, "cursor: deleted id -> Err", fails);
  var d2 = search_after_ids(&eng, &qa, 1, 7);
  fails = check(d2.len() == 1 && d2[0] == refA[3], "cursor: after 7 skips the deleted 8", fails);

  io.println("");
  io.println("probe_pagination: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
