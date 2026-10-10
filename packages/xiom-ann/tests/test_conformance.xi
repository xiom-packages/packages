// XIOM -- xiom.ann conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Adapted from XVECTOR's tests/test_conformance.xi (ANN kind/param sections,
// flat KNN correctness sections) plus the HNSW acceptance sections, kept to
// the extracted xiom.ann surface. The flat_search checks cover the small
// local oracle addition over the reference (SPEC.md section 3). No engine,
// no payload/segment/query services here.

module ann_tests

use xiom.io; use xiom.test; use xiom.vectors; use xiom.ann; use xiom.ann.hnsw;

fn f32_approx(a: Float32, b: Float32, eps: Float32) -> Bool {
  var diff = a - b;
  if diff < 0.0 { diff = -diff; }
  return diff < eps;
}

fn f32_eq(a: Float32, b: Float32) -> Bool {
  return f32_approx(a, b, 0.0001);
}

fn mk_vec2(a: Float32, b: Float32) -> Vector {
  var v = Vector.new(2);
  v.set(0, a); v.set(1, b);
  return v;
}

fn mk_vec3(a: Float32, b: Float32, c: Float32) -> Vector {
  var v = Vector.new(3);
  v.set(0, a); v.set(1, b); v.set(2, c);
  return v;
}

// ==== Deterministic dataset helpers (LCG, copied from the recall probe) ====

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

// Build a deterministic n-point dataset into the HNSW graph and the parallel
// flat arrays (ids 1..n). Returns the advanced LCG state.
fn fill_dataset(g: &mut HNSWGraph, fv: &mut Vec[Vector], fi: &mut Vec[UInt64], n: Int, dim: Int, seed: Int, metric: DistanceMetric) -> Int {
  var state = seed;
  var i: Int = 0;
  while i < n {
    var coords = Vec[Float32].new();
    state = rand_coords(state, dim, &mut coords);
    var v1 = vec_from_coords(&coords);
    var v2 = vec_from_coords(&coords);
    fv.push(v1);
    fi.push((i + 1) as UInt64);
    hnsw_insert(g, i + 1, v2, metric);
    i = i + 1;
  }
  return state;
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

// Recall@k of `ef` HNSW searches against the flat oracle over the same
// dataset (deterministic queries continue the dataset LCG).
fn recall_hits(g: &HNSWGraph, fv: &Vec[Vector], fi: &Vec[UInt64], state0: Int, dim: Int, nq: Int, k: Int, ef: Int, metric: DistanceMetric) -> Int {
  var state = state0;
  var hits: Int = 0;
  var qi: Int = 0;
  while qi < nq {
    var qc = Vec[Float32].new();
    state = rand_coords(state, dim, &mut qc);
    var q = vec_from_coords(&qc);
    var oracle = flat_search(fv, fi, &q, k, metric);
    var approx = hnsw_search(g, &q, k, ef, metric);
    hits = hits + hit_count(&oracle, &approx);
    qi = qi + 1;
  }
  return hits;
}

// ==== Section 1: AnnIndexKind + AnnParams ====

fn t_params_default() -> TestResult {
  var p = ann_params_default();
  var ok = p.m == 16 && p.ef_construction == 200 && p.ef_search == 64;
  if !ann_params_valid(&p) { ok = false; }
  return assert(ok, "AnnParams: defaults m=16 efC=200 efS=64, valid");
}

fn t_params_m_bounds() -> TestResult {
  var ok = ann_params_valid(&AnnParams{ m: 1, ef_construction: 1, ef_search: 1 });
  if !ann_params_valid(&AnnParams{ m: 512, ef_construction: 200, ef_search: 64 }) { ok = false; }
  if ann_params_valid(&AnnParams{ m: 513, ef_construction: 200, ef_search: 64 }) { ok = false; }
  if ann_params_valid(&AnnParams{ m: 0, ef_construction: 200, ef_search: 64 }) { ok = false; }
  if ann_params_valid(&AnnParams{ m: -1, ef_construction: 200, ef_search: 64 }) { ok = false; }
  return assert(ok, "AnnParams: m=1/512 valid, 513/0/-1 invalid (max_graph_degree 512)");
}

fn t_params_ef_bounds() -> TestResult {
  var ok = !ann_params_valid(&AnnParams{ m: 16, ef_construction: 0, ef_search: 64 });
  if ann_params_valid(&AnnParams{ m: 16, ef_construction: -1, ef_search: 64 }) { ok = false; }
  if ann_params_valid(&AnnParams{ m: 16, ef_construction: 200, ef_search: 0 }) { ok = false; }
  if ann_params_valid(&AnnParams{ m: 16, ef_construction: 200, ef_search: -5 }) { ok = false; }
  return assert(ok, "AnnParams: ef_construction/ef_search <= 0 invalid");
}

fn t_kind_names() -> TestResult {
  var ok = ann_index_kind_name(&AnnIndexKind.Flat) == "flat";
  if ann_index_kind_name(&AnnIndexKind.Hnsw) != "hnsw" { ok = false; }
  if ann_index_kind_name(&AnnIndexKind.Ivf) != "ivf" { ok = false; }
  return assert(ok, "AnnIndexKind: names flat/hnsw/ivf");
}

fn t_kind_codes() -> TestResult {
  var ok = ann_kind_code(AnnIndexKind.Flat) == 1 && ann_kind_code(AnnIndexKind.Hnsw) == 2
    && ann_kind_code(AnnIndexKind.Ivf) == 3;
  if ann_kind_code(ann_kind_from_code(1)) != 1 { ok = false; }
  if ann_kind_code(ann_kind_from_code(2)) != 2 { ok = false; }
  if ann_kind_code(ann_kind_from_code(3)) != 3 { ok = false; }
  if ann_kind_from_code(0) != AnnIndexKind.Ivf { ok = false; }
  if ann_kind_from_code(99) != AnnIndexKind.Ivf { ok = false; }
  return assert(ok, "AnnIndexKind: on-disk codes 1/2/3 round-trip; unknown -> Ivf");
}

fn t_kind_discriminate() -> TestResult {
  var k1 = AnnIndexKind.Flat;
  var k2 = AnnIndexKind.Hnsw;
  var k3 = AnnIndexKind.Ivf;
  var ok: Bool = true;
  match k1 {
    AnnIndexKind.Flat => {}
    AnnIndexKind.Hnsw => { ok = false; }
    AnnIndexKind.Ivf => { ok = false; }
  }
  match k2 {
    AnnIndexKind.Flat => { ok = false; }
    AnnIndexKind.Hnsw => {}
    AnnIndexKind.Ivf => { ok = false; }
  }
  match k3 {
    AnnIndexKind.Flat => { ok = false; }
    AnnIndexKind.Hnsw => { ok = false; }
    AnnIndexKind.Ivf => {}
  }
  if AnnIndexKind.Flat == AnnIndexKind.Hnsw { ok = false; }
  if AnnIndexKind.Ivf == AnnIndexKind.Flat { ok = false; }
  return assert(ok, "AnnIndexKind: 3 variants discriminate correctly");
}

// ==== Section 2: flat_search (exact oracle) ====

fn t_flat_top1() -> TestResult {
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  fv.push(mk_vec2(1.0, 0.0)); fi.push(10);
  fv.push(mk_vec2(100.0, 100.0)); fi.push(20);
  var q = mk_vec2(1.0, 0.0);
  var r = flat_search(&fv, &fi, &q, 1, DistanceMetric.Euclidean);
  var ok = r.len() == 1 && (r[0].id as Int) == 10 && f32_eq(r[0].distance, 0.0);
  return assert(ok, "Flat: KNN top-1 returns nearest (id=10)");
}

fn t_flat_bounded() -> TestResult {
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  var i: Int = 0;
  while i < 3 {
    var v = Vector.new(1);
    v.set(0, i as Float32);
    fv.push(v); fi.push(i as UInt64);
    i = i + 1;
  }
  var q = Vector.new(1);
  q.set(0, 0.0);
  var r = flat_search(&fv, &fi, &q, 2, DistanceMetric.Euclidean);
  return assert(r.len() == 2, "Flat: KNN k=2 with 3 vectors returns len=2");
}

fn t_flat_ordered_and_ties() -> TestResult {
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  var v0 = Vector.new(1); v0.set(0, 0.0); fv.push(v0); fi.push(0);
  var v1 = Vector.new(1); v1.set(0, 10.0); fv.push(v1); fi.push(1);
  var v2 = Vector.new(1); v2.set(0, 5.0); fv.push(v2); fi.push(2);
  var q = Vector.new(1);
  q.set(0, 0.0);
  var r = flat_search(&fv, &fi, &q, 3, DistanceMetric.Euclidean);
  var ok = r.len() == 3 && (r[0].id as Int) == 0 && (r[1].id as Int) == 2 && (r[2].id as Int) == 1;
  if !sorted_ok(&r) { ok = false; }
  // distance ties break by ascending id: push id 2 first, then id 1.
  var tv = Vec[Vector].new();
  var ti = Vec[UInt64].new();
  var a = Vector.new(1); a.set(0, 7.0); tv.push(a); ti.push(2);
  var b = Vector.new(1); b.set(0, 7.0); tv.push(b); ti.push(1);
  var tr = flat_search(&tv, &ti, &q, 2, DistanceMetric.Euclidean);
  if tr.len() != 2 { ok = false; }
  else {
    if (tr[0].id as Int) != 1 || (tr[1].id as Int) != 2 { ok = false; }
  }
  return assert(ok, "Flat: distance-ascending; id-ascending on ties");
}

fn t_flat_metrics() -> TestResult {
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  fv.push(mk_vec2(1.0, 0.0)); fi.push(1);
  fv.push(mk_vec2(0.0, 2.0)); fi.push(2);
  var q = mk_vec2(1.0, 0.0);
  var r1 = flat_search(&fv, &fi, &q, 2, DistanceMetric.Euclidean);
  var r2 = flat_search(&fv, &fi, &q, 2, DistanceMetric.Cosine);
  var r3 = flat_search(&fv, &fi, &q, 2, DistanceMetric.DotProduct);
  var ok = r1.len() == 2 && r2.len() == 2 && r3.len() == 2;
  if r2.len() == 2 && (r2[0].id as Int) != 1 { ok = false; }
  if r3.len() == 2 && (r3[0].id as Int) != 1 { ok = false; }
  return assert(ok, "Flat: KNN works with all 3 distance metrics");
}

fn t_flat_empty() -> TestResult {
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  var q = mk_vec2(1.0, 0.0);
  var r = flat_search(&fv, &fi, &q, 5, DistanceMetric.Euclidean);
  return assert(r.len() == 0, "Flat: empty dataset -> empty result");
}

fn t_flat_dim_guard() -> TestResult {
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  fv.push(mk_vec3(1.0, 0.0, 0.0)); fi.push(1);
  fv.push(mk_vec2(1.0, 0.0)); fi.push(2);
  var q2 = mk_vec2(1.0, 0.0);
  var r2 = flat_search(&fv, &fi, &q2, 5, DistanceMetric.Euclidean);
  var q5 = Vector.new(5);
  var r5 = flat_search(&fv, &fi, &q5, 5, DistanceMetric.Euclidean);
  var ok = r2.len() == 1 && (r2[0].id as Int) == 2 && r5.len() == 0;
  return assert(ok, "Flat: dimension-mismatched entries skipped");
}

fn t_flat_k_above_n() -> TestResult {
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  fv.push(mk_vec2(1.0, 0.0)); fi.push(1);
  fv.push(mk_vec2(2.0, 0.0)); fi.push(2);
  fv.push(mk_vec2(3.0, 0.0)); fi.push(3);
  var q = mk_vec2(0.0, 0.0);
  var r = flat_search(&fv, &fi, &q, 10, DistanceMetric.Euclidean);
  return assert(r.len() == 3, "Flat: k above dataset size returns all 3");
}

// ==== Section 3: HNSW graph -- build, search, updates, deletes ====

fn t_hnsw_build_and_lookup() -> TestResult {
  var g = hnsw_new(16, 4.0);
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  let state = fill_dataset(&mut g, &mut fv, &mut fi, 100, 8, 123456789, DistanceMetric.Euclidean);
  var ok = hnsw_size(&g) == 100 && fv.len() == 100;
  if hnsw_find_node_pos(&g, 50) != 49 { ok = false; }
  if hnsw_find_node_pos(&g, 999) != -1 { ok = false; }
  if hnsw_build_ops(&g) <= 0 { ok = false; }
  if state == 123456789 { ok = false; }
  return assert(ok, "HNSW: 100 inserts, size 100, id map 50->49/missing->-1, build ops > 0");
}

fn t_hnsw_search_shape() -> TestResult {
  var g = hnsw_new(16, 4.0);
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  let state = fill_dataset(&mut g, &mut fv, &mut fi, 100, 8, 111111, DistanceMetric.Euclidean);
  var s = state;
  var ok: Bool = true;
  var qi: Int = 0;
  while qi < 12 {
    var qc = Vec[Float32].new();
    s = rand_coords(s, 8, &mut qc);
    var q = vec_from_coords(&qc);
    var r = hnsw_search(&g, &q, 10, 64, DistanceMetric.Euclidean);
    if r.len() > 10 { ok = false; }
    if !sorted_ok(&r) { ok = false; }
    if !unique_ok(&r) { ok = false; }
    qi = qi + 1;
  }
  return assert(ok, "HNSW: len<=k, ascending, unique over 12 queries");
}

fn t_hnsw_empty_and_dim() -> TestResult {
  var cold = hnsw_new(4, 4.0);
  var q1 = Vector.new(1);
  q1.set(0, 1.0);
  var cold_hits = hnsw_search(&cold, &q1, 3, 8, DistanceMetric.Euclidean);
  var g = hnsw_new(16, 4.0);
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  let state = fill_dataset(&mut g, &mut fv, &mut fi, 40, 3, 222222, DistanceMetric.Euclidean);
  var q3 = Vector.new(5);
  var wrong = hnsw_search(&g, &q3, 3, 8, DistanceMetric.Euclidean);
  var ok = cold_hits.len() == 0 && wrong.len() == 0;
  if state == 222222 { ok = false; }
  return assert(ok, "HNSW: empty graph + dimension mismatch -> empty");
}

fn t_hnsw_update_in_place() -> TestResult {
  var g = hnsw_new(16, 4.0);
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  var state = fill_dataset(&mut g, &mut fv, &mut fi, 80, 8, 333333, DistanceMetric.Euclidean);
  var u: Int = 1;
  while u <= 20 {
    var uc = Vec[Float32].new();
    state = rand_coords(state, 8, &mut uc);
    var uv1 = vec_from_coords(&uc);
    var uv2 = vec_from_coords(&uc);
    hnsw_insert(&mut g, u, uv1, DistanceMetric.Euclidean);
    fv[u - 1] = uv2;
    u = u + 1;
  }
  var ok = hnsw_size(&g) == 80 && hnsw_live_count(&g) == 80;
  var hits = recall_hits(&g, &fv, &fi, state, 8, 20, 10, 64, DistanceMetric.Euclidean);
  if hits * 100 < 20 * 10 * 80 { ok = false; }
  return assert(ok, "HNSW: 20 in-place updates, size/live 80, recall@10 >= 0.80");
}

fn t_hnsw_delete_and_revive() -> TestResult {
  var g = hnsw_new(16, 4.0);
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  var state = fill_dataset(&mut g, &mut fv, &mut fi, 60, 8, 444444, DistanceMetric.Euclidean);
  var del_ok = hnsw_delete(&mut g, 7);
  var ok = del_ok && hnsw_size(&g) == 60 && hnsw_live_count(&g) == 59;
  if hnsw_delete(&mut g, 7) { ok = false; }
  if hnsw_delete(&mut g, 9999) { ok = false; }
  var stray: Int = 0;
  var qi: Int = 0;
  while qi < 8 {
    var qc = Vec[Float32].new();
    state = rand_coords(state, 8, &mut qc);
    var q = vec_from_coords(&qc);
    var r = hnsw_search(&g, &q, 10, 64, DistanceMetric.Euclidean);
    var t: Int = 0;
    while t < r.len() {
      if r[t].id == 7 { stray = stray + 1; }
      t = t + 1;
    }
    qi = qi + 1;
  }
  if stray != 0 { ok = false; }
  var rc = Vec[Float32].new();
  state = rand_coords(state, 8, &mut rc);
  var rv = vec_from_coords(&rc);
  hnsw_insert(&mut g, 7, rv, DistanceMetric.Euclidean);
  if hnsw_live_count(&g) != 60 { ok = false; }
  return assert(ok, "HNSW: delete id7 -> live 59, never returned; re-insert revives (live 60)");
}

fn t_hnsw_compact() -> TestResult {
  var g = hnsw_new(16, 4.0);
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  var state = fill_dataset(&mut g, &mut fv, &mut fi, 100, 8, 555555, DistanceMetric.Euclidean);
  var d: Int = 1;
  while d <= 20 {
    hnsw_delete(&mut g, d);
    d = d + 1;
  }
  var compacted = hnsw_compact(&g, DistanceMetric.Euclidean);
  var ok = hnsw_size(&compacted) == 80 && hnsw_live_count(&compacted) == 80;
  if hnsw_find_node_pos(&compacted, 1) != -1 { ok = false; }
  if hnsw_find_node_pos(&compacted, 21) != 0 { ok = false; }
  var stray: Int = 0;
  var qi: Int = 0;
  while qi < 8 {
    var qc = Vec[Float32].new();
    state = rand_coords(state, 8, &mut qc);
    var q = vec_from_coords(&qc);
    var r = hnsw_search(&compacted, &q, 10, 64, DistanceMetric.Euclidean);
    var t: Int = 0;
    while t < r.len() {
      if (r[t].id as Int) <= 20 { stray = stray + 1; }
      t = t + 1;
    }
    qi = qi + 1;
  }
  if stray != 0 { ok = false; }
  return assert(ok, "HNSW: compact 100/20-deleted -> size 80, deleted ids gone/never returned");
}

fn t_hnsw_ef_construction() -> TestResult {
  var g = hnsw_new(8, 4.0);
  hnsw_set_ef_construction(&mut g, 0);
  var ignored: Bool = g.ef_construction == 200;
  hnsw_set_ef_construction(&mut g, 64);
  var ok = ignored && g.ef_construction == 64;
  return assert(ok, "HNSW: ef_construction 0 ignored (stays 200), 64 applied");
}

fn t_hnsw_recall_gate() -> TestResult {
  var g = hnsw_new(16, 4.0);
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  let state = fill_dataset(&mut g, &mut fv, &mut fi, 120, 8, 666666, DistanceMetric.Euclidean);
  var hits64 = recall_hits(&g, &fv, &fi, state, 8, 15, 10, 64, DistanceMetric.Euclidean);
  var hits8 = recall_hits(&g, &fv, &fi, state, 8, 15, 10, 8, DistanceMetric.Euclidean);
  var denom: Int = 15 * 10;
  var ok = hits64 * 100 >= denom * 85 && hits8 * 100 >= denom * 50;
  return assert(ok, "HNSW: recall@10 gate ef=64 >= 0.85, ef=8 >= 0.50");
}

// ==== Section 4: HNSW graph codec ====

fn t_codec_roundtrip() -> TestResult {
  var g = hnsw_new(16, 4.0);
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  let state = fill_dataset(&mut g, &mut fv, &mut fi, 40, 8, 777777, DistanceMetric.Euclidean);
  var words = hnsw_encode(&g);
  match hnsw_decode(&words) {
    Some(g2) => {
      var ok = hnsw_size(&g2) == hnsw_size(&g) && hnsw_live_count(&g2) == hnsw_live_count(&g);
      if hnsw_find_node_pos(&g2, 40) != 39 { ok = false; }
      var s = state;
      var hits: Int = 0;
      var qi: Int = 0;
      while qi < 5 {
        var qc = Vec[Float32].new();
        s = rand_coords(s, 8, &mut qc);
        var q = vec_from_coords(&qc);
        var oracle = flat_search(&fv, &fi, &q, 10, DistanceMetric.Euclidean);
        var approx = hnsw_search(&g2, &q, 10, 64, DistanceMetric.Euclidean);
        hits = hits + hit_count(&oracle, &approx);
        qi = qi + 1;
      }
      if hits != 5 * 10 { ok = false; }
      return assert(ok, "Codec: encode/decode round-trip preserves size, id map and search results");
    }
    None => { return assert(false, "Codec: decode returned None"); }
  }
}

fn t_codec_malformed_rejected() -> TestResult {
  var g = hnsw_new(8, 4.0);
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  let state = fill_dataset(&mut g, &mut fv, &mut fi, 10, 4, 888888, DistanceMetric.Euclidean);
  var ok: Bool = true;
  var empty = Vec[Int].new();
  match hnsw_decode(&empty) { Some(_) => { ok = false; } None => {} }
  var words = hnsw_encode(&g);
  var bad_version = Vec[Int].new();
  bad_version.push(3);
  var i: Int = 1;
  while i < words.len() {
    bad_version.push(words[i]);
    i = i + 1;
  }
  match hnsw_decode(&bad_version) { Some(_) => { ok = false; } None => {} }
  var truncated = Vec[Int].new();
  i = 0;
  while i < words.len() - 1 {
    truncated.push(words[i]);
    i = i + 1;
  }
  match hnsw_decode(&truncated) { Some(_) => { ok = false; } None => {} }
  var bad_m = Vec[Int].new();
  bad_m.push(2); bad_m.push(0);
  i = 2;
  while i < words.len() {
    bad_m.push(words[i]);
    i = i + 1;
  }
  match hnsw_decode(&bad_m) { Some(_) => { ok = false; } None => {} }
  if state == 888888 { ok = false; }
  return assert(ok, "Codec: empty/version/truncated/bad-m -> None");
}

fn t_codec_determinism() -> TestResult {
  var g = hnsw_new(16, 4.0);
  var fv = Vec[Vector].new();
  var fi = Vec[UInt64].new();
  let state = fill_dataset(&mut g, &mut fv, &mut fi, 25, 4, 999999, DistanceMetric.Euclidean);
  var w1 = hnsw_encode(&g);
  var w2 = hnsw_encode(&g);
  var ok = w1.len() == w2.len() && w1.len() > 0;
  var i: Int = 0;
  while i < w1.len() {
    if w1[i] != w2[i] { ok = false; }
    i = i + 1;
  }
  if state == 999999 { ok = false; }
  return assert(ok, "Codec: encode deterministic bit-for-bit");
}

fn run_one(r: TestResult) -> Int {
  if r.passed { io.println("  [PASS] " + r.name); return 0; }
  io.println("  [FAIL] " + r.name); return 1;
}

fn main() -> Int {
  io.println("=== xiom.ann conformance tests ===");
  var failed: Int = 0;
  var total: Int = 0;
  let r1 = t_params_default();
  failed = failed + run_one(r1); total = total + 1;
  let r2 = t_params_m_bounds();
  failed = failed + run_one(r2); total = total + 1;
  let r3 = t_params_ef_bounds();
  failed = failed + run_one(r3); total = total + 1;
  let r4 = t_kind_names();
  failed = failed + run_one(r4); total = total + 1;
  let r5 = t_kind_codes();
  failed = failed + run_one(r5); total = total + 1;
  let r6 = t_kind_discriminate();
  failed = failed + run_one(r6); total = total + 1;
  let r7 = t_flat_top1();
  failed = failed + run_one(r7); total = total + 1;
  let r8 = t_flat_bounded();
  failed = failed + run_one(r8); total = total + 1;
  let r9 = t_flat_ordered_and_ties();
  failed = failed + run_one(r9); total = total + 1;
  let r10 = t_flat_metrics();
  failed = failed + run_one(r10); total = total + 1;
  let r11 = t_flat_empty();
  failed = failed + run_one(r11); total = total + 1;
  let r12 = t_flat_dim_guard();
  failed = failed + run_one(r12); total = total + 1;
  let r13 = t_flat_k_above_n();
  failed = failed + run_one(r13); total = total + 1;
  let r14 = t_hnsw_build_and_lookup();
  failed = failed + run_one(r14); total = total + 1;
  let r15 = t_hnsw_search_shape();
  failed = failed + run_one(r15); total = total + 1;
  let r16 = t_hnsw_empty_and_dim();
  failed = failed + run_one(r16); total = total + 1;
  let r17 = t_hnsw_update_in_place();
  failed = failed + run_one(r17); total = total + 1;
  let r18 = t_hnsw_delete_and_revive();
  failed = failed + run_one(r18); total = total + 1;
  let r19 = t_hnsw_compact();
  failed = failed + run_one(r19); total = total + 1;
  let r20 = t_hnsw_ef_construction();
  failed = failed + run_one(r20); total = total + 1;
  let r21 = t_hnsw_recall_gate();
  failed = failed + run_one(r21); total = total + 1;
  let r22 = t_codec_roundtrip();
  failed = failed + run_one(r22); total = total + 1;
  let r23 = t_codec_malformed_rejected();
  failed = failed + run_one(r23); total = total + 1;
  let r24 = t_codec_determinism();
  failed = failed + run_one(r24); total = total + 1;
  if failed == 0 {
    io.println("xiom.ann: all 24 checks passed");
  } else {
    io.println("xiom.ann: checks failed");
  }
  return failed;
}
