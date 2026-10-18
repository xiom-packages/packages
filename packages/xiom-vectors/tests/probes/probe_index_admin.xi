// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: index admin (M-Q5). Verifies per-collection statistics (config,
// points, payloads, graph occupancy incl. tombstones, lsn) for the active
// and parked collections, the admin rebuild (`rebuild_index`: Hnsw
// tombstone reclamation with before/after stats; Flat no-op), search
// equality after a rebuild, idempotence, set_index transitions, recovery
// consistency, and the compact_index compatibility wrapper. Exit = failed
// checks.

module probe_index_admin

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.payload.payload;
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

fn default_stats() -> CollectionStats {
  return CollectionStats{
    name: "",
    cid: 0,
    dimension: 0,
    metric: DistanceMetric.Euclidean,
    index_kind: AnnIndexKind.Flat,
    m: 0,
    ef_construction: 0,
    ef_search: 0,
    points: 0,
    payloads: 0,
    nodes: 0,
    tombstones: 0,
    wal_lsn: 0,
  };
}

fn search_ids(eng: &VectorEngine, q: &Vector, k: Int) -> Vec[Int] {
  var ids = Vec[Int].new();
  match search(eng, q, k) {
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

fn stats_of(eng: &VectorEngine, name: Str) -> CollectionStats {
  var out = default_stats();
  match collection_stats(eng, name) {
    Ok(s) => { out = s; }
    Err(_) => {}
  }
  return out;
}

fn stats_found(eng: &VectorEngine, name: Str) -> Bool {
  match collection_stats(eng, name) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// n points with payloads; optionally switched to Hnsw (m=8, efc=50, efs=20).
fn make_engine(dim: Int, n: Int, seed: Int, hnsw: Bool) -> VectorEngine {
  var eng = engine_new();
  create_collection(&mut eng, dim, DistanceMetric.Euclidean);
  var s = seed;
  var i: Int = 1;
  while i <= n {
    var c = Vec<Float32>.new();
    s = rand_coords(s, dim, &mut c);
    upsert(&mut eng, i, vec_from_coords(&c));
    var p = payload_new();
    payload_set(&mut p, "tag", FieldValue.IntVal(i % 4));
    set_payload(&mut eng, i, p);
    i = i + 1;
  }
  if hnsw {
    match set_index(&mut eng, AnnIndexKind.Hnsw, AnnParams{ m: 8, ef_construction: 50, ef_search: 20 }) {
      Ok(_) => {}
      Err(_) => {}
    }
  }
  return eng;
}

fn main() -> Int {
  io.println("=== xvector probe: index admin ===");
  var fails: Int = 0;
  var dim: Int = 3;

  // --- live stats on an Hnsw collection ---
  var eng = make_engine(dim, 30, 418822, true);
  var s1 = stats_of(&eng, "default");
  fails = check(stats_found(&eng, "default") && s1.name == "default" && s1.cid == eng.active_cid,
    "stats: found by name, cid matches the active collection", fails);
  fails = check(s1.dimension == 3 && s1.metric == DistanceMetric.Euclidean && s1.index_kind == AnnIndexKind.Hnsw
    && s1.m == 8 && s1.ef_construction == 50 && s1.ef_search == 20,
    "stats: config fields exact", fails);
  fails = check(s1.points == 30 && s1.payloads == 30 && s1.nodes == 30 && s1.tombstones == 0 && s1.wal_lsn > 0,
    "stats: counts exact (30/30/30, 0 tombstones, lsn > 0)", fails);

  var del_ids = Vec[Int].new();
  var i: Int = 1;
  while i <= 5 { del_ids.push(i); i = i + 1; }
  match delete_many(&mut eng, &del_ids) { Ok(_) => {} Err(_) => {} }
  var s2 = stats_of(&eng, "default");
  fails = check(s2.points == 25 && s2.payloads == 25 && s2.nodes == 30 && s2.tombstones == 5,
    "stats: after 5 deletes -> 25 points, 5 tombstones", fails);

  // --- admin rebuild ---
  var rb = rebuild_index(&mut eng);
  var rb_ok: Bool = false;
  var rb_kind: AnnIndexKind = AnnIndexKind.Flat;
  var rb_points: Int = 0;
  var rb_before: Int = 0;
  var rb_after: Int = 0;
  var rb_reclaimed: Int = 0;
  match rb {
    Ok(st) => {
      rb_ok = true;
      rb_kind = st.kind;
      rb_points = st.points;
      rb_before = st.nodes_before;
      rb_after = st.nodes_after;
      rb_reclaimed = st.reclaimed;
    }
    Err(_) => {}
  }
  fails = check(rb_ok && rb_kind == AnnIndexKind.Hnsw && rb_points == 25 && rb_before == 30
    && rb_after == 25 && rb_reclaimed == 5,
    "rebuild: Hnsw stats (30 -> 25, 5 reclaimed)", fails);
  var s3 = stats_of(&eng, "default");
  fails = check(s3.nodes == 25 && s3.tombstones == 0 && s3.points == 25,
    "rebuild: stats show tombstones reclaimed", fails);

  // search equality against a flat twin of the surviving points
  var eng2 = engine_new();
  create_collection(&mut eng2, dim, DistanceMetric.Euclidean);
  i = 0;
  while i < engine_size(&eng) {
    upsert(&mut eng2, eng.store.ids[i], dup_vec(&eng.store.vectors[i]));
    i = i + 1;
  }
  var q = Vector.new(dim);
  match get_point(&eng, 10) { Some(v) => { q = v; } None => {} }
  var ids_a = search_ids(&eng, &q, 5);
  var ids_b = search_ids(&eng2, &q, 5);
  var equal_ids: Bool = ids_a.len() == ids_b.len() && ids_a.len() == 5;
  if equal_ids {
    i = 0;
    while i < ids_a.len() {
      if ids_a[i] != ids_b[i] { equal_ids = false; }
      i = i + 1;
    }
  }
  fails = check(equal_ids, "rebuild: search results bit-equal to the flat reference", fails);

  var rb2 = rebuild_index(&mut eng);
  var rb2_ok: Bool = false;
  var rb2_reclaimed: Int = -1;
  match rb2 { Ok(st) => { rb2_ok = true; rb2_reclaimed = st.reclaimed; } Err(_) => {} }
  fails = check(rb2_ok && rb2_reclaimed == 0, "rebuild: idempotent (nothing to reclaim)", fails);

  // --- Flat collection: stats + no-op rebuild ---
  var sf = stats_of(&eng2, "default");
  fails = check(sf.index_kind == AnnIndexKind.Flat && sf.nodes == 0 && sf.tombstones == 0 && sf.points == 25,
    "flat stats: nodes/tombstones 0", fails);
  var rbf = rebuild_index(&mut eng2);
  var rbf_ok: Bool = false;
  var rbf_kind: AnnIndexKind = AnnIndexKind.Hnsw;
  var rbf_reclaimed: Int = -1;
  var rbf_points: Int = 0;
  match rbf { Ok(st) => { rbf_ok = true; rbf_kind = st.kind; rbf_reclaimed = st.reclaimed; rbf_points = st.points; } Err(_) => {} }
  fails = check(rbf_ok && rbf_kind == AnnIndexKind.Flat && rbf_reclaimed == 0 && rbf_points == 25,
    "flat rebuild: no-op with zeroed graph stats", fails);

  fails = check(!stats_found(&eng, "nope"), "stats: unknown collection -> Err(NotFound)", fails);

  // --- empty collection ---
  var eng3 = engine_new();
  create_collection(&mut eng3, dim, DistanceMetric.Euclidean);
  var s3e = stats_of(&eng3, "default");
  var rbe = rebuild_index(&mut eng3);
  var rbe_ok: Bool = false;
  match rbe { Ok(_) => { rbe_ok = true; } Err(_) => {} }
  fails = check(s3e.points == 0 && s3e.payloads == 0 && s3e.nodes == 0 && s3e.wal_lsn > 0 && rbe_ok,
    "empty: zeroed stats, rebuild Ok", fails);

  // --- multi-collection: parked entry stats vs live stats ---
  var eng4 = engine_new();
  create_named_collection(&mut eng4, "a", dim, DistanceMetric.Euclidean);
  var sa: Int = 771;
  var ca = Vec<Float32>.new();
  sa = rand_coords(sa, dim, &mut ca);
  var va = vec_from_coords(&ca);
  i = 1;
  while i <= 12 {
    upsert(&mut eng4, i, va);
    i = i + 1;
  }
  match set_index(&mut eng4, AnnIndexKind.Hnsw, AnnParams{ m: 8, ef_construction: 50, ef_search: 20 }) { Ok(_) => {} Err(_) => {} }
  var da = Vec[Int].new();
  da.push(1);
  da.push(2);
  da.push(3);
  match delete_many(&mut eng4, &da) { Ok(_) => {} Err(_) => {} }
  create_named_collection(&mut eng4, "b", dim, DistanceMetric.Euclidean);
  i = 21;
  while i <= 25 {
    upsert(&mut eng4, i, va);
    i = i + 1;
  }
  var parked = stats_of(&eng4, "a");
  var live_b = stats_of(&eng4, "b");
  fails = check(parked.points == 9 && parked.nodes == 12 && parked.tombstones == 3
    && parked.index_kind == AnnIndexKind.Hnsw && parked.name == "a",
    "multi: parked collection stats from its entry (9 points, 3 tombstones)", fails);
  fails = check(live_b.points == 5 && live_b.index_kind == AnnIndexKind.Flat && live_b.name == "b",
    "multi: active collection stats from the live fields", fails);
  match select_collection(&mut eng4, "a") { Ok(_) => {} Err(_) => {} }
  var live_a = stats_of(&eng4, "a");
  fails = check(live_a.points == parked.points && live_a.nodes == parked.nodes
    && live_a.tombstones == parked.tombstones && live_a.cid == parked.cid,
    "multi: stats agree across park/materialize", fails);

  // --- set_index transitions + rebuild after re-tombstoning ---
  match set_index(&mut eng4, AnnIndexKind.Flat, AnnParams{ m: 8, ef_construction: 50, ef_search: 20 }) { Ok(_) => {} Err(_) => {} }
  var flat_a = stats_of(&eng4, "a");
  fails = check(flat_a.index_kind == AnnIndexKind.Flat && flat_a.nodes == 0 && flat_a.tombstones == 0,
    "set_index flat: stats follow the new kind", fails);
  match set_index(&mut eng4, AnnIndexKind.Hnsw, AnnParams{ m: 8, ef_construction: 50, ef_search: 20 }) { Ok(_) => {} Err(_) => {} }
  var hnsw_a = stats_of(&eng4, "a");
  fails = check(hnsw_a.index_kind == AnnIndexKind.Hnsw && hnsw_a.nodes == 9 && hnsw_a.tombstones == 0,
    "set_index hnsw: fresh graph (9 nodes, 0 tombstones)", fails);

  var d2 = Vec[Int].new();
  d2.push(4);
  d2.push(5);
  match delete_many(&mut eng4, &d2) { Ok(_) => {} Err(_) => {} }
  var comp = compact_index(&mut eng4);
  var comp_n: Int = -1;
  match comp { Ok(n) => { comp_n = n; } Err(_) => {} }
  var after_comp = stats_of(&eng4, "a");
  fails = check(comp_n == 2 && after_comp.tombstones == 0 && after_comp.nodes == 7,
    "compact_index: compatibility wrapper still reclaims (2)", fails);

  // --- lsn/points move together; recovery consistency ---
  var lsn_before = stats_of(&eng, "default").wal_lsn;
  upsert(&mut eng, 99, q);
  var s_after = stats_of(&eng, "default");
  fails = check(s_after.points == 26 && s_after.wal_lsn > lsn_before, "stats: upsert -> points+1 and lsn grows", fails);
  var rec = engine_recover(&eng.wal, dim, DistanceMetric.Euclidean);
  var rec_stats = stats_of(&rec, "default");
  fails = check(rec_stats.points == 26 && rec_stats.index_kind == AnnIndexKind.Hnsw && rec_stats.tombstones == 0
    && rec_stats.nodes == 26,
    "recovery: rebuilt graph -> consistent stats (0 tombstones)", fails);

  io.println("");
  io.println("probe_index_admin: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
