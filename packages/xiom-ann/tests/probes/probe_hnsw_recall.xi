// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: HNSW recall harness vs the LOCAL FLAT ORACLE.
// Adapted from XVECTOR's tests/probes/probe_hnsw_recall.xi: the original used
// the flat `vector_store` VectorIndex + `search_service` for the oracle; this
// package-local version replaces both with `flat_search` over the probe's own
// parallel arrays (SPEC.md section 3). Builds a deterministic dataset (LCG,
// no RNG dependency), indexes it into the flat oracle and the HNSW graph,
// then measures recall@10 over queries for ef=64 and ef=8 (beam width effect)
// plus a cosine-metric sanity run. Also checks structural invariants
// (len <= k, ascending, unique ids, empty graph, dimension mismatch).
// Exit = failed checks.

module probe_hnsw_recall

use xiom.ann.hnsw;
use xiom.ann;
use xiom.vectors;
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

// Deterministic LCG (state threaded by value).
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

// Flat-oracle maintenance over parallel arrays (replaces the reference
// store's index_add/index_remove upsert/remove-by-id semantics).
fn flat_upsert(vecs: &mut Vec[Vector], ids: &mut Vec[UInt64], id: UInt64, v: Vector) {
  var slot: Int = -1;
  var i: Int = 0;
  while i < ids.len() {
    if ids[i] == id { slot = i; i = ids.len(); } else { i = i + 1; }
  }
  var dest: Int = slot;
  if slot < 0 {
    dest = vecs.len();
    vecs.push(Vector.new(v.dimension));
    ids.push(id);
  }
  vecs[dest] = v;
}

fn flat_remove(vecs: &mut Vec[Vector], ids: &mut Vec[UInt64], id: UInt64) {
  var i: Int = 0;
  while i < ids.len() {
    if ids[i] == id {
      var j: Int = i;
      while j + 1 < ids.len() {
        ids[j] = ids[j + 1];
        vecs[j] = vecs[j + 1];
        j = j + 1;
      }
      ids.pop();
      vecs.pop();
      return;
    }
    i = i + 1;
  }
}

fn hit_count(oracle: &Vec[Neighbor], approx: &Vec[Neighbor]) -> Int {
  var hits: Int = 0;
  var i: Int = 0;
  while i < oracle.len() {
    var bid = oracle[i].id;
    var found: Bool = false;
    var j: Int = 0;
    while j < approx.len() && !found {
      if approx[j].id == bid {
        found = true;
        hits = hits + 1;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return hits;
}

fn sorted_ok(items: &Vec[Neighbor]) -> Bool {
  var i: Int = 1;
  while i < items.len() {
    if items[i - 1].distance > items[i].distance { return false; }
    i = i + 1;
  }
  return true;
}

fn unique_ok(items: &Vec[Neighbor]) -> Bool {
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
  io.println("=== xiom.ann probe: HNSW recall vs flat oracle ===");
  var fails: Int = 0;

  var n: Int = 200;
  var dim: Int = 8;
  var k: Int = 10;
  var queries: Int = 30;

  // --- deterministic dataset: N points, then Q query vectors ---
  var state: Int = 987654321;
  var flat_vecs = Vec[Vector].new();
  var flat_ids = Vec[UInt64].new();
  var graph = hnsw_new(16, 4.0);
  var i: Int = 0;
  while i < n {
    var coords = Vec[Float32].new();
    state = rand_coords(state, dim, &mut coords);
    var v1 = vec_from_coords(&coords);
    var v2 = vec_from_coords(&coords);
    flat_upsert(&mut flat_vecs, &mut flat_ids, (i + 1) as UInt64, v1);
    hnsw_insert(&mut graph, i + 1, v2, DistanceMetric.Euclidean);
    i = i + 1;
  }
  fails = check(hnsw_size(&graph) == n && flat_ids.len() == n, "dataset indexed: HNSW + flat oracle both size 200", fails);
  fails = check(hnsw_find_node_pos(&graph, 100) == 99 && hnsw_find_node_pos(&graph, 999) == -1,
    "find_node_pos: 100 -> 99, missing -> -1", fails);
  var bops = hnsw_build_ops(&graph);
  io.println("    diag build work: " + int_to_str(bops) + " distance ops (n^2 = " + int_to_str(n * n) + ")");
  fails = check(bops > 0 && bops <= n * n * 4, "build-work proxy bounded (0 < ops <= 4*n^2)", fails);

  // diag: layer-0 degree stats, level distribution, reachability from entry
  var zero_deg: Int = 0;
  var max_deg: Int = 0;
  i = 0;
  while i < hnsw_size(&graph) {
    var d = graph.deg[i * hnsw_layer_capacity()];
    if d == 0 { zero_deg = zero_deg + 1; }
    if d > max_deg { max_deg = d; }
    i = i + 1;
  }
  var level_hist = Vec[Int].new();
  var lh: Int = 0;
  while lh < hnsw_layer_capacity() { level_hist.push(0); lh = lh + 1; }
  i = 0;
  while i < hnsw_size(&graph) {
    var lv = graph.levels[i];
    level_hist[lv] = level_hist[lv] + 1;
    i = i + 1;
  }
  var lhs = "";
  lh = 0;
  while lh < hnsw_layer_capacity() {
    if level_hist[lh] > 0 { lhs = lhs + "L" + int_to_str(lh) + "=" + int_to_str(level_hist[lh]) + " "; }
    lh = lh + 1;
  }
  var top_level = graph.levels[graph.entry];
  var reach = Vec[Bool].new();
  i = 0;
  while i < hnsw_size(&graph) { reach.push(false); i = i + 1; }
  reach[0] = true;
  var frontier = Vec[Int].new();
  frontier.push(0);
  var reach_count: Int = 1;
  while frontier.len() > 0 {
    var cur = frontier[frontier.len() - 1];
    frontier.pop();
    var crow = cur * hnsw_layer_capacity();
    var j = 0;
    while j < graph.deg[crow] {
      var nb = graph.adj[crow * graph.m + j];
      if !reach[nb] {
        reach[nb] = true;
        reach_count = reach_count + 1;
        frontier.push(nb);
      }
      j = j + 1;
    }
  }
  io.println("    diag graph: reachable(L0)=" + int_to_str(reach_count) + "/" + int_to_str(n)
    + " zero_deg=" + int_to_str(zero_deg) + " max_deg=" + int_to_str(max_deg)
    + " top_level=" + int_to_str(top_level) + " levels: " + lhs);

  // --- recall@10: ef=64 and ef=8 ---
  var hits64: Int = 0;
  var hits8: Int = 0;
  var seen64: Int = 0;
  var qi: Int = 0;
  while qi < queries {
    var qc = Vec[Float32].new();
    state = rand_coords(state, dim, &mut qc);
    var q = vec_from_coords(&qc);
    var oracle = flat_search(&flat_vecs, &flat_ids, &q, k, DistanceMetric.Euclidean);
    var approx64 = hnsw_search(&graph, &q, k, 64, DistanceMetric.Euclidean);
    var approx8 = hnsw_search(&graph, &q, k, 8, DistanceMetric.Euclidean);
    seen64 = seen64 + hnsw_search_visited(&graph, &q, k, 64, DistanceMetric.Euclidean);
    hits64 = hits64 + hit_count(&oracle, &approx64);
    hits8 = hits8 + hit_count(&oracle, &approx8);
    if qi == 0 {
      fails = check(oracle.len() == k, "oracle returns full k", fails);
      fails = check(approx64.len() <= k, "hnsw len <= k", fails);
      fails = check(sorted_ok(&approx64), "hnsw results sorted ascending", fails);
      fails = check(unique_ok(&approx64), "hnsw results unique ids", fails);
    }
    qi = qi + 1;
  }
  var denom: Int = queries * k;
  io.println("    diag recall@10 ef=64: " + int_to_str(hits64) + "/" + int_to_str(denom)
    + "  ef=8: " + int_to_str(hits8) + "/" + int_to_str(denom)
    + "  avg_visited(ef=64)=" + int_to_str(seen64 / queries) + "/" + int_to_str(n));
  // Gate: ef=64 recall must be >= 85% (measured baseline documented in SPEC).
  fails = check(hits64 * 100 >= denom * 85, "recall@10 ef=64 >= 0.85", fails);
  fails = check(hits8 * 100 >= denom * 50, "recall@10 ef=8 >= 0.50", fails);

  // --- latency/recall tradeoff table (10 queries per ef) ---
  var efs = Vec[Int].new();
  efs.push(8);
  efs.push(16);
  efs.push(32);
  efs.push(64);
  efs.push(128);
  var ei: Int = 0;
  while ei < efs.len() {
    var efv = efs[ei];
    var hh: Int = 0;
    var vv: Int = 0;
    var qq: Int = 0;
    while qq < 10 {
      var ce = Vec[Float32].new();
      state = rand_coords(state, dim, &mut ce);
      var qe = vec_from_coords(&ce);
      var oe = flat_search(&flat_vecs, &flat_ids, &qe, k, DistanceMetric.Euclidean);
      var ae = hnsw_search(&graph, &qe, k, efv, DistanceMetric.Euclidean);
      hh = hh + hit_count(&oe, &ae);
      vv = vv + hnsw_search_visited(&graph, &qe, k, efv, DistanceMetric.Euclidean);
      qq = qq + 1;
    }
    io.println("    diag ef=" + int_to_str(efv) + " recall=" + int_to_str(hh) + "/" + int_to_str(10 * k)
      + " avg_visited=" + int_to_str(vv / 10) + "/" + int_to_str(n));
    fails = check(hh * 100 >= 10 * k * 60, "ef=" + int_to_str(efv) + " recall >= 0.60", fails);
    ei = ei + 1;
  }

  // --- update path: 60 in-place vector updates with edge refresh ---
  var u: Int = 1;
  while u <= 60 {
    var uc = Vec[Float32].new();
    state = rand_coords(state, dim, &mut uc);
    var uv1 = vec_from_coords(&uc);
    var uv2 = vec_from_coords(&uc);
    hnsw_insert(&mut graph, u, uv1, DistanceMetric.Euclidean);
    flat_upsert(&mut flat_vecs, &mut flat_ids, u as UInt64, uv2);
    u = u + 1;
  }
  var hits_upd: Int = 0;
  var qup: Int = 0;
  while qup < 20 {
    var qcu = Vec[Float32].new();
    state = rand_coords(state, dim, &mut qcu);
    var qu = vec_from_coords(&qcu);
    var ou = flat_search(&flat_vecs, &flat_ids, &qu, k, DistanceMetric.Euclidean);
    var au = hnsw_search(&graph, &qu, k, 64, DistanceMetric.Euclidean);
    hits_upd = hits_upd + hit_count(&ou, &au);
    qup = qup + 1;
  }
  io.println("    diag after 60 updates: recall@10 ef=64 " + int_to_str(hits_upd) + "/" + int_to_str(20 * k));
  fails = check(hits_upd * 100 >= 20 * k * 80, "update path: recall >= 0.80 after 60 in-place updates", fails);
  fails = check(hnsw_size(&graph) == n && hnsw_live_count(&graph) == n,
    "update path: size/live unchanged (in-place updates)", fails);

  // --- cosine sanity: same shape, separate graph ---
  var state2: Int = 246813579;
  var flat2_vecs = Vec[Vector].new();
  var flat2_ids = Vec[UInt64].new();
  var graph2 = hnsw_new(16, 4.0);
  i = 0;
  while i < n {
    var coords2 = Vec[Float32].new();
    state2 = rand_coords(state2, dim, &mut coords2);
    var w1 = vec_from_coords(&coords2);
    var w2 = vec_from_coords(&coords2);
    flat_upsert(&mut flat2_vecs, &mut flat2_ids, (i + 1) as UInt64, w1);
    hnsw_insert(&mut graph2, i + 1, w2, DistanceMetric.Cosine);
    i = i + 1;
  }
  var hits_cos: Int = 0;
  var qcos: Int = 10;
  qi = 0;
  while qi < qcos {
    var qc2 = Vec[Float32].new();
    state2 = rand_coords(state2, dim, &mut qc2);
    var q2 = vec_from_coords(&qc2);
    var oracle2 = flat_search(&flat2_vecs, &flat2_ids, &q2, k, DistanceMetric.Cosine);
    var approx2 = hnsw_search(&graph2, &q2, k, 64, DistanceMetric.Cosine);
    hits_cos = hits_cos + hit_count(&oracle2, &approx2);
    qi = qi + 1;
  }
  var denom_cos: Int = qcos * k;
  io.println("    diag cosine recall@10 ef=64: " + int_to_str(hits_cos) + "/" + int_to_str(denom_cos));
  fails = check(hits_cos * 100 >= denom_cos * 60, "cosine recall@10 >= 0.60", fails);

  // --- scaling sanity: n=800, 20 queries, Euclidean ---
  var nbig: Int = 800;
  var state3: Int = 135792468;
  var flat3_vecs = Vec[Vector].new();
  var flat3_ids = Vec[UInt64].new();
  var graph3 = hnsw_new(16, 4.0);
  i = 0;
  while i < nbig {
    var coords3 = Vec[Float32].new();
    state3 = rand_coords(state3, dim, &mut coords3);
    var x1 = vec_from_coords(&coords3);
    var x2 = vec_from_coords(&coords3);
    flat_upsert(&mut flat3_vecs, &mut flat3_ids, (i + 1) as UInt64, x1);
    hnsw_insert(&mut graph3, i + 1, x2, DistanceMetric.Euclidean);
    i = i + 1;
  }
  var hits3: Int = 0;
  var seen3: Int = 0;
  var q3n: Int = 20;
  var qbig: Int = 0;
  while qbig < q3n {
    var qc3 = Vec[Float32].new();
    state3 = rand_coords(state3, dim, &mut qc3);
    var qb = vec_from_coords(&qc3);
    var oracle3 = flat_search(&flat3_vecs, &flat3_ids, &qb, k, DistanceMetric.Euclidean);
    var approx3 = hnsw_search(&graph3, &qb, k, 64, DistanceMetric.Euclidean);
    seen3 = seen3 + hnsw_search_visited(&graph3, &qb, k, 64, DistanceMetric.Euclidean);
    hits3 = hits3 + hit_count(&oracle3, &approx3);
    qbig = qbig + 1;
  }
  var denom3: Int = q3n * k;
  io.println("    diag n=800: recall@10 ef=64 " + int_to_str(hits3) + "/" + int_to_str(denom3)
    + "  avg_visited=" + int_to_str(seen3 / q3n) + "/" + int_to_str(nbig)
    + "  top_level=" + int_to_str(graph3.levels[graph3.entry]));
  fails = check(hits3 * 100 >= denom3 * 80, "n=800 recall@10 ef=64 >= 0.80", fails);
  fails = check(hnsw_size(&graph3) == nbig, "n=800 graph size", fails);

  // --- deletes/tombstones (n=200 graph) ---
  var del_ok = hnsw_delete(&mut graph, 42);
  fails = check(del_ok && hnsw_size(&graph) == n && hnsw_live_count(&graph) == n - 1,
    "delete id42: tombstoned, size 200, live 199", fails);
  fails = check(!hnsw_delete(&mut graph, 42) && !hnsw_delete(&mut graph, 99999),
    "delete id42 again / unknown id -> false", fails);
  flat_remove(&mut flat_vecs, &mut flat_ids, 42);
  var hits_del: Int = 0;
  var bad_del: Int = 0;
  qi = 0;
  while qi < queries {
    var qcd = Vec[Float32].new();
    state = rand_coords(state, dim, &mut qcd);
    var qdel = vec_from_coords(&qcd);
    var oracle_d = flat_search(&flat_vecs, &flat_ids, &qdel, k, DistanceMetric.Euclidean);
    var approx_d = hnsw_search(&graph, &qdel, k, 64, DistanceMetric.Euclidean);
    hits_del = hits_del + hit_count(&oracle_d, &approx_d);
    var t42: Int = 0;
    while t42 < approx_d.len() {
      if approx_d[t42].id == 42 { bad_del = bad_del + 1; }
      t42 = t42 + 1;
    }
    qi = qi + 1;
  }
  io.println("    diag after delete: recall@10 ef=64 " + int_to_str(hits_del) + "/" + int_to_str(denom)
    + "  stray42=" + int_to_str(bad_del));
  fails = check(bad_del == 0, "deleted id42 never returned", fails);
  fails = check(hits_del * 100 >= denom * 85, "recall@10 after delete >= 0.85", fails);

  // Re-inserting the id revives the tombstoned node (vector updated in place).
  var coords_r = Vec[Float32].new();
  state = rand_coords(state, dim, &mut coords_r);
  var v42 = vec_from_coords(&coords_r);
  hnsw_insert(&mut graph, 42, v42, DistanceMetric.Euclidean);
  fails = check(hnsw_live_count(&graph) == n, "re-insert id42 revives it (live 200)", fails);
  flat_upsert(&mut flat_vecs, &mut flat_ids, 42, vec_from_coords(&coords_r));

  // --- delete-all on a small graph -> empty results, live 0 ---
  var small = hnsw_new(4, 4.0);
  var sc: Int = 0;
  while sc < 5 {
    var c2 = Vec[Float32].new();
    state = rand_coords(state, 2, &mut c2);
    var sv = vec_from_coords(&c2);
    hnsw_insert(&mut small, sc + 1, sv, DistanceMetric.Euclidean);
    sc = sc + 1;
  }
  sc = 1;
  var all_del: Bool = true;
  while sc <= 5 {
    if !hnsw_delete(&mut small, sc) { all_del = false; }
    sc = sc + 1;
  }
  fails = check(all_del && hnsw_live_count(&small) == 0, "small graph: delete all 5 -> live 0", fails);
  var qd = Vector.new(2);
  qd.set(0, 1.0); qd.set(1, 0.0);
  var after_all = hnsw_search(&small, &qd, 3, 8, DistanceMetric.Euclidean);
  fails = check(after_all.len() == 0, "all tombstoned -> empty search", fails);
  var small_c = hnsw_compact(&small, DistanceMetric.Euclidean);
  fails = check(hnsw_size(&small_c) == 0 && hnsw_live_count(&small_c) == 0,
    "compact(all deleted) -> empty graph", fails);

  // --- compaction: rebuild from live nodes, reclaim tombstones ---
  var delc: Int = 101;
  while delc <= 150 {
    hnsw_delete(&mut graph, delc);
    flat_remove(&mut flat_vecs, &mut flat_ids, delc as UInt64);
    delc = delc + 1;
  }
  fails = check(hnsw_live_count(&graph) == 150 && hnsw_size(&graph) == 200,
    "pre-compact: 50 tombstoned, size 200, live 150", fails);
  fails = check(hnsw_find_node_pos(&graph, 151) == 150 && hnsw_find_node_pos(&graph, 42) == 41,
    "id map pre-compact: 151 -> 150, 42 -> 41", fails);
  var compacted = hnsw_compact(&graph, DistanceMetric.Euclidean);
  fails = check(hnsw_size(&compacted) == 150 && hnsw_live_count(&compacted) == 150,
    "hnsw_compact: size 150, live 150, no tombstones", fails);
  fails = check(hnsw_find_node_pos(&compacted, 151) == 100 && hnsw_find_node_pos(&compacted, 200) == 149
    && hnsw_find_node_pos(&compacted, 101) == -1,
    "id map post-compact: 151 -> 100, 200 -> 149, deleted 101 gone", fails);
  var stray_c: Int = 0;
  var hits_c: Int = 0;
  qi = 0;
  while qi < 20 {
    var qcc = Vec[Float32].new();
    state = rand_coords(state, dim, &mut qcc);
    var qc = vec_from_coords(&qcc);
    var o = flat_search(&flat_vecs, &flat_ids, &qc, k, DistanceMetric.Euclidean);
    var a = hnsw_search(&compacted, &qc, k, 64, DistanceMetric.Euclidean);
    hits_c = hits_c + hit_count(&o, &a);
    var t2: Int = 0;
    while t2 < a.len() {
      if (a[t2].id as Int) >= 101 && (a[t2].id as Int) <= 150 { stray_c = stray_c + 1; }
      t2 = t2 + 1;
    }
    qi = qi + 1;
  }
  io.println("    diag compacted: recall@10 ef=64 " + int_to_str(hits_c) + "/" + int_to_str(20 * k)
    + "  stray_deleted=" + int_to_str(stray_c));
  fails = check(stray_c == 0 && hits_c * 100 >= 20 * k * 80,
    "compacted graph: no deleted ids returned, recall >= 0.80", fails);

  // --- ef_construction setter semantics ---
  var efprobe = hnsw_new(8, 4.0);
  hnsw_set_ef_construction(&mut efprobe, 0);
  var ef_ignored: Bool = efprobe.ef_construction == 200;
  hnsw_set_ef_construction(&mut efprobe, 64);
  fails = check(ef_ignored && efprobe.ef_construction == 64,
    "ef_construction: 0 ignored (stays 200), 64 applied", fails);

  // --- cold graph + dimension mismatch are safe ---
  var cold = hnsw_new(4, 4.0);
  var q1 = Vector.new(1);
  q1.set(0, 1.0);
  var cold_hits = hnsw_search(&cold, &q1, 3, 8, DistanceMetric.Euclidean);
  fails = check(cold_hits.len() == 0, "empty graph -> empty result", fails);
  var q3 = Vector.new(3);
  q3.set(0, 1.0); q3.set(1, 0.0); q3.set(2, 0.0);
  var wrong = hnsw_search(&graph, &q3, 3, 8, DistanceMetric.Euclidean);
  fails = check(wrong.len() == 0, "dimension mismatch -> empty (no contract trap)", fails);

  io.println("");
  io.println("probe_hnsw_recall: " + int_to_str(fails) + " failed checks");
  return fails;
}
