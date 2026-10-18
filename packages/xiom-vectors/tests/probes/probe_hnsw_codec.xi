// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: HNSW graph codec (persistence) on the REAL modules. Roundtrips a
// 100-node graph (structure, vectors, levels, tombstones) and verifies
// search parity bit-for-bit; rejects malformed/truncated/tampered words;
// decodes the empty graph; and shows a decoded graph stays mutable. Exit =
// failed checks.

module probe_hnsw_codec

use xiom.vector.index.hnsw;
use xiom.vectors;
use xiom.io;
use xiom.num.float;

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

fn graphs_equal(a: &HNSWGraph, b: &HNSWGraph) -> Bool {
  if a.m != b.m { return false; }
  if a.m0 != b.m0 { return false; }
  if float.float_bits(a.ml as Float64) != float.float_bits(b.ml as Float64) { return false; }
  if a.ef_construction != b.ef_construction { return false; }
  if a.entry != b.entry { return false; }
  if a.ids.len() != b.ids.len() { return false; }
  var i: Int = 0;
  while i < a.ids.len() {
    if a.ids[i] != b.ids[i] { return false; }
    if a.levels[i] != b.levels[i] { return false; }
    if a.deleted[i] != b.deleted[i] { return false; }
    if a.vectors[i].dimension != b.vectors[i].dimension { return false; }
    var d: Int = 0;
    while d < a.vectors[i].dimension {
      if float.float_bits(a.vectors[i].data[d] as Float64) != float.float_bits(b.vectors[i].data[d] as Float64) { return false; }
      d = d + 1;
    }
    var l: Int = 0;
    while l < hnsw_layer_capacity() {
      var row = i * hnsw_layer_capacity() + l;
      if a.deg[row] != b.deg[row] { return false; }
      var s: Int = 0;
      while s < a.deg[row] {
        if a.adj[row * a.m0 + s] != b.adj[row * b.m0 + s] { return false; }
        s = s + 1;
      }
      l = l + 1;
    }
    i = i + 1;
  }
  return true;
}

fn search_equal(a: &Vec[Neighbor], b: &Vec[Neighbor]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i].id != b[i].id { return false; }
    if float.float_bits(a[i].distance as Float64) != float.float_bits(b[i].distance as Float64) { return false; }
    i = i + 1;
  }
  return true;
}

fn main() -> Int {
  io.println("=== xvector probe: HNSW graph codec ===");
  var fails: Int = 0;

  var dim: Int = 8;
  var n: Int = 100;
  var k: Int = 10;

  var state: Int = 424242;
  var g = hnsw_new(16, 4.0);
  var i: Int = 0;
  while i < n {
    var c = Vec[Float32].new();
    state = rand_coords(state, dim, &mut c);
    var v = vec_from_coords(&c);
    hnsw_insert(&mut g, i + 1, v, DistanceMetric.Euclidean);
    i = i + 1;
  }
  fails = check(hnsw_size(&g) == n, "built 100-node graph", fails);
  hnsw_set_ef_construction(&mut g, 77);

  // --- clean roundtrip: structure identical + search parity ---
  var words = hnsw_encode(&g);
  fails = check(words.len() > 0 && words[0] == 3 && words[2] == g.m0 && words[4] == 77,
    "encode: version-3 word stream carrying m0 + ef_construction=77", fails);
  match hnsw_decode(&words) {
    Some(g2) => {
      fails = check(graphs_equal(&g, &g2) && hnsw_find_node_pos(&g2, 100) == 99
        && hnsw_find_node_pos(&g2, 7) == 6,
        "roundtrip: ids/levels/deleted/vectors/adjacency identical + id map rebuilt", fails);
      var parity: Bool = true;
      var q: Int = 0;
      while q < 10 {
        var qc = Vec[Float32].new();
        state = rand_coords(state, dim, &mut qc);
        var qv = vec_from_coords(&qc);
        var r1 = hnsw_search(&g, &qv, k, 64, DistanceMetric.Euclidean);
        var r2 = hnsw_search(&g2, &qv, k, 64, DistanceMetric.Euclidean);
        if !search_equal(&r1, &r2) { parity = false; }
        q = q + 1;
      }
      fails = check(parity, "roundtrip: search results bit-identical (10 queries)", fails);
    }
    None => { fails = check(false, "decode(encode(g)) -> Some", fails); }
  }

  // --- version-2 backward compatibility: a legacy (m0 = m) graph encodes
  // as v3; stripping the m0 word and lowering the version decodes to the
  // same structure (the pre-P-a on-disk format). ---
  var gc = hnsw_new_full(16, 4.0, 16);
  var cj: Int = 0;
  while cj < 40 {
    var cc = Vec[Float32].new();
    state = rand_coords(state, dim, &mut cc);
    var cv = vec_from_coords(&cc);
    hnsw_insert(&mut gc, cj + 1, cv, DistanceMetric.Euclidean);
    cj = cj + 1;
  }
  var v3w = hnsw_encode(&gc);
  var v2w = Vec[Int].new();
  v2w.push(2);
  v2w.push(v3w[1]);
  var ri: Int = 3;
  while ri < v3w.len() {
    v2w.push(v3w[ri]);
    ri = ri + 1;
  }
  var v2ok: Bool = false;
  match hnsw_decode(&v2w) {
    Some(gv2) => {
      v2ok = graphs_equal(&gc, &gv2) && gv2.m0 == 16;
    }
    None => {}
  }
  fails = check(gc.m0 == 16 && v2ok,
    "v2 compat: legacy control (m0 = m) strips to v2 and decodes identically", fails);

  // --- tombstones survive the roundtrip ---
  hnsw_delete(&mut g, 10);
  hnsw_delete(&mut g, 20);
  hnsw_delete(&mut g, 30);
  var words_d = hnsw_encode(&g);
  match hnsw_decode(&words_d) {
    Some(gd) => {
      fails = check(graphs_equal(&g, &gd) && hnsw_live_count(&gd) == n - 3,
        "tombstones roundtrip: deleted flags + live 97", fails);
    }
    None => { fails = check(false, "decode(encode(deleted g)) -> Some", fails); }
  }

  // --- empty graph roundtrip ---
  var eg = hnsw_new(8, 4.0);
  var ew = hnsw_encode(&eg);
  match hnsw_decode(&ew) {
    Some(ed) => {
      var q1 = Vector.new(2);
      q1.set(0, 1.0); q1.set(1, 0.0);
      var er = hnsw_search(&ed, &q1, 3, 8, DistanceMetric.Euclidean);
      fails = check(hnsw_size(&ed) == 0 && ed.entry == -1 && er.len() == 0,
        "empty graph roundtrip: size 0, entry -1, empty search", fails);
    }
    None => { fails = check(false, "decode(encode(empty)) -> Some", fails); }
  }

  // --- malformed / tampered inputs are rejected ---
  var short = Vec[Int].new();
  var n1 = hnsw_decode(&short);
  var bad_ver = hnsw_encode(&eg);
  bad_ver[0] = 4;
  var n2 = hnsw_decode(&bad_ver);
  var trunc = hnsw_encode(&g);
  trunc.pop();
  var n3 = hnsw_decode(&trunc);
  var bad_cap = hnsw_encode(&eg);
  bad_cap[5] = 99;
  var n4 = hnsw_decode(&bad_cap);
  var bad_ml = hnsw_encode(&eg);
  bad_ml[3] = 0;
  var n5 = hnsw_decode(&bad_ml);
  var bad_ef = hnsw_encode(&eg);
  bad_ef[4] = 0;
  var n5b = hnsw_decode(&bad_ef);
  var bad_m0 = hnsw_encode(&eg);
  bad_m0[2] = 7;
  var n5c = hnsw_decode(&bad_m0);
  var junk = hnsw_encode(&eg);
  junk.push(7);
  var n6 = hnsw_decode(&junk);
  var no1: Bool = true;
  match n1 { Some(_) => { no1 = false; } None => {} }
  var no2: Bool = true;
  match n2 { Some(_) => { no2 = false; } None => {} }
  var no3: Bool = true;
  match n3 { Some(_) => { no3 = false; } None => {} }
  var no4: Bool = true;
  match n4 { Some(_) => { no4 = false; } None => {} }
  var no5: Bool = true;
  match n5 { Some(_) => { no5 = false; } None => {} }
  var no5b: Bool = true;
  match n5b { Some(_) => { no5b = false; } None => {} }
  var no5c: Bool = true;
  match n5c { Some(_) => { no5c = false; } None => {} }
  var no6: Bool = true;
  match n6 { Some(_) => { no6 = false; } None => {} }
  fails = check(no1 && no2 && no3 && no4 && no5 && no5b && no5c && no6,
    "reject: short, bad version, truncated, bad capacity, ml=0, ef=0, m0<m, trailing junk", fails);

  // out-of-range neighbor position: node 0's first layer-0 edge.
  var tam = hnsw_encode(&g);
  var vw0: Int = tam[11];
  var deg_pos: Int = 12 + vw0;
  var deg0: Int = tam[deg_pos];
  var no7: Bool = false;
  if deg0 > 0 {
    tam[deg_pos + 1] = n + 5;
    var nbr = hnsw_decode(&tam);
    match nbr { Some(_) => {} None => { no7 = true; } }
  }
  fails = check(no7, "reject: out-of-range neighbor position", fails);

  // duplicate ids are rejected (the id map is unique).
  var sg = hnsw_new(4, 4.0);
  var s1 = Vector.new(2);
  s1.set(0, 1.0); s1.set(1, 0.0);
  var s2 = Vector.new(2);
  s2.set(0, 0.0); s2.set(1, 1.0);
  hnsw_insert(&mut sg, 1, s1, DistanceMetric.Euclidean);
  hnsw_insert(&mut sg, 2, s2, DistanceMetric.Euclidean);
  var dupw = hnsw_encode(&sg);
  var pw: Int = 8;
  var vw1: Int = dupw[pw + 3];
  pw = pw + 4 + vw1;
  var rr: Int = 0;
  while rr < hnsw_layer_capacity() {
    var dgw: Int = dupw[pw];
    pw = pw + 1 + dgw;
    rr = rr + 1;
  }
  dupw[pw] = dupw[8];
  var ndup = hnsw_decode(&dupw);
  var no_dup: Bool = true;
  match ndup { Some(_) => { no_dup = false; } None => {} }
  fails = check(no_dup, "reject: duplicate ids", fails);

  // --- a decoded graph stays mutable ---
  match hnsw_decode(&hnsw_encode(&g)) {
    Some(gm) => {
      var c = Vec[Float32].new();
      state = rand_coords(state, dim, &mut c);
      var nv = vec_from_coords(&c);
      hnsw_insert(&mut gm, 999, nv, DistanceMetric.Euclidean);
      var found_pos = hnsw_find_node_pos(&gm, 999);
      var qc2 = Vec[Float32].new();
      state = rand_coords(state, dim, &mut qc2);
      var qv2 = vec_from_coords(&qc2);
      hnsw_insert(&mut gm, 998, vec_from_coords(&qc2), DistanceMetric.Euclidean);
      var r = hnsw_search(&gm, &qv2, 5, 64, DistanceMetric.Euclidean);
      var has_998: Bool = false;
      var ids = "";
      var t: Int = 0;
      while t < r.len() {
        if r[t].id == 998 { has_998 = true; }
        ids = ids + int_to_str(r[t].id as Int) + ",";
        t = t + 1;
      }
      io.println("    diag mut: size=" + int_to_str(hnsw_size(&gm))
        + " found_pos=" + int_to_str(found_pos)
        + " has_998=" + int_to_str(if has_998 { 1 } else { 0 })
        + " results=" + ids);
      fails = check(hnsw_size(&gm) == n + 2 && found_pos == n && has_998,
        "decoded graph mutable: insert 999 + 998 (size 102), search finds 998", fails);
    }
    None => { fails = check(false, "decode for mutation -> Some", fails); }
  }

  io.println("");
  io.println("probe_hnsw_codec: " + int_to_str(fails) + " failed checks");
  return fails;
}
