// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: reference oracle (M-G1). An INDEPENDENT Float64 oracle (own loops,
// no vector_distance calls) cross-checks the engine kernels and search
// paths: pairwise distance agreement per metric (with max-deviation
// reporting), metric identities/axioms (symmetry, self-distance, triangle
// inequality, cosine bounds + scale invariance, zero-vector guard), ranked
// search/page/cursor/range results vs the oracle ranking on deterministic
// seeded vectors, and Hnsw recall + distance fidelity vs the oracle. Exit =
// failed checks.

module probe_reference_oracle

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vectors;
use xiom.io;
use xiom.convert;
use xiom.math;

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

fn f64_abs(x: Float64) -> Float64 {
  if x < 0.0 { return 0.0 - x; }
  return x;
}

// ---- Independent Float64 oracle math (no engine calls) ----
fn o_dot(a: &Vector, b: &Vector) -> Float64 {
  var s: Float64 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    s = s + (a.data[i] as Float64) * (b.data[i] as Float64);
    i = i + 1;
  }
  return s;
}

fn o_l2(a: &Vector, b: &Vector) -> Float64 {
  var s: Float64 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    var d = (a.data[i] as Float64) - (b.data[i] as Float64);
    s = s + d * d;
    i = i + 1;
  }
  return math.sqrt(s);
}

fn o_cos(a: &Vector, b: &Vector) -> Float64 {
  var dot: Float64 = 0.0;
  var ma: Float64 = 0.0;
  var mb: Float64 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    var ai = a.data[i] as Float64;
    var bi = b.data[i] as Float64;
    dot = dot + ai * bi;
    ma = ma + ai * ai;
    mb = mb + bi * bi;
    i = i + 1;
  }
  if ma == 0.0 || mb == 0.0 { return 1.0; }
  return 1.0 - dot / (math.sqrt(ma) * math.sqrt(mb));
}

fn o_dist(a: &Vector, b: &Vector, metric: DistanceMetric) -> Float64 {
  match metric {
    Cosine => { return o_cos(a, b); }
    DotProduct => { return 0.0 - o_dot(a, b); }
    Euclidean => { return o_l2(a, b); }
  }
}

fn tol_for(metric: DistanceMetric, val: Float64) -> Float64 {
  if metric == DistanceMetric.Cosine {
    return 1.0e-4;
  }
  return 1.0e-3 * (1.0 + f64_abs(val));
}

// Ascending (distance, id) oracle ranking over the first `n` vectors
// (ids are 1..n).
fn oracle_rank(vecs: &Vec[Vector], q: &Vector, metric: DistanceMetric, n: Int) -> Vec[Int] {
  var dists = Vec[Float64].new();
  var ids = Vec[Int].new();
  var i: Int = 0;
  while i < n {
    var d = o_dist(q, &vecs[i], metric);
    dists.push(d);
    ids.push(i + 1);
    var p: Int = ids.len() - 1;
    while p > 0 && (dists[p - 1] > dists[p] || (dists[p - 1] == dists[p] && ids[p - 1] > ids[p])) {
      var td = dists[p];
      dists[p] = dists[p - 1];
      dists[p - 1] = td;
      var ti = ids[p];
      ids[p] = ids[p - 1];
      ids[p - 1] = ti;
      p = p - 1;
    }
    i = i + 1;
  }
  return ids;
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

fn page_ids(eng: &VectorEngine, q: &Vector, k: Int, offset: Int) -> Vec[Int] {
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

fn after_ids(eng: &VectorEngine, q: &Vector, k: Int, after_id: Int) -> Vec[Int] {
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

fn ids_slice_match(a: &Vec[Int], ref: &Vec[Int], from: Int, count: Int) -> Bool {
  if a.len() != count { return false; }
  var i: Int = 0;
  while i < count {
    if a[i] != ref[from + i] { return false; }
    i = i + 1;
  }
  return true;
}

// Search distances vs the oracle for every hit.
fn hits_match_oracle(eng: &VectorEngine, q: &Vector, k: Int, vecs: &Vec[Vector], metric: DistanceMetric, n: Int) -> Bool {
  match search(eng, q, k) {
    Ok(h) => {
      var i: Int = 0;
      while i < h.items.len() {
        var oid = h.items[i].id;
        if oid < 1 || oid > n { return false; }
        var dev = f64_abs((h.items[i].distance as Float64) - o_dist(q, &vecs[oid - 1], metric));
        if dev > tol_for(metric, 0.0) + 1.0e-3 { return false; }
        i = i + 1;
      }
      return true;
    }
    Err(_) => { return false; }
  }
}

fn main() -> Int {
  io.println("=== xvector probe: reference oracle (M-G1) ===");
  var fails: Int = 0;
  var dim: Int = 6;
  var n: Int = 40;

  // Deterministic seeded vectors + a query outside the set.
  var vecs = Vec[Vector].new();
  var s: Int = 902107;
  var i: Int = 0;
  while i < n {
    var c = Vec[Float32].new();
    s = rand_coords(s, dim, &mut c);
    vecs.push(vec_from_coords(&c));
    i = i + 1;
  }
  var qc = Vec[Float32].new();
  s = rand_coords(s, dim, &mut qc);
  var q = vec_from_coords(&qc);

  // ---- 1. Pairwise kernels vs the Float64 oracle (per metric) ----
  var metrics = Vec[DistanceMetric].new();
  metrics.push(DistanceMetric.Cosine);
  metrics.push(DistanceMetric.DotProduct);
  metrics.push(DistanceMetric.Euclidean);
  var names = Vec[Str].new();
  names.push("cosine");
  names.push("dot");
  names.push("euclidean");
  var m: Int = 0;
  while m < 3 {
    var mm = metrics[m];
    var maxdev: Float64 = 0.0;
    var bad: Int = 0;
    var pairs: Int = 0;
    i = 0;
    while i < n {
      var j: Int = i + 1;
      while j < n {
        var engv = vector_distance(&vecs[i], &vecs[j], mm) as Float64;
        var orc = o_dist(&vecs[i], &vecs[j], mm);
        var dev = f64_abs(engv - orc);
        if dev > maxdev { maxdev = dev; }
        if dev > tol_for(mm, orc) { bad = bad + 1; }
        pairs = pairs + 1;
        j = j + 1;
      }
      i = i + 1;
    }
    io.println("    diag " + names[m] + ": " + convert.int_to_string(pairs) + " pairs, bad="
      + convert.int_to_string(bad) + ", maxdev=" + convert.float_to_string(maxdev));
    fails = check(bad == 0, "kernels vs oracle: " + names[m] + " pairwise agreement", fails);
    m = m + 1;
  }

  // ---- 2. Metric identities / axioms on the engine kernels ----
  var sym_bad: Int = 0;
  m = 0;
  while m < 3 {
    i = 0;
    while i < n {
      var j2: Int = i + 1;
      while j2 < n {
        if vector_distance(&vecs[i], &vecs[j2], metrics[m]) != vector_distance(&vecs[j2], &vecs[i], metrics[m]) {
          sym_bad = sym_bad + 1;
        }
        j2 = j2 + 1;
      }
      i = i + 1;
    }
    m = m + 1;
  }
  fails = check(sym_bad == 0, "axioms: symmetry exact for all metrics", fails);

  var self_bad: Int = 0;
  var vcos_max: Float64 = 0.0;
  i = 0;
  while i < n {
    var d_l2 = vector_distance(&vecs[i], &vecs[i], DistanceMetric.Euclidean);
    if d_l2 != 0.0 { self_bad = self_bad + 1; }
    var d_cos = vector_distance(&vecs[i], &vecs[i], DistanceMetric.Cosine);
    var dc = f64_abs(d_cos as Float64);
    if dc > 1.0e-5 { self_bad = self_bad + 1; }
    if dc > vcos_max { vcos_max = dc; }
    var d_dot = vector_distance(&vecs[i], &vecs[i], DistanceMetric.DotProduct) as Float64;
    var mag = o_dot(&vecs[i], &vecs[i]);
    if f64_abs(d_dot + mag) > tol_for(DistanceMetric.DotProduct, mag) { self_bad = self_bad + 1; }
    i = i + 1;
  }
  io.println("    diag self-distance: cosine max deviation " + convert.float_to_string(vcos_max));
  fails = check(self_bad == 0, "axioms: self-distance (l2=0, cos~0, dot=-|v|^2)", fails);

  var tri_bad: Int = 0;
  i = 0;
  while i + 2 < n {
    var a = vecs[i];
    var b = vecs[i + 1];
    var c = vecs[i + 2];
    var d_ac = vector_distance(&a, &c, DistanceMetric.Euclidean) as Float64;
    var d_ab = vector_distance(&a, &b, DistanceMetric.Euclidean) as Float64;
    var d_bc = vector_distance(&b, &c, DistanceMetric.Euclidean) as Float64;
    if d_ac > d_ab + d_bc + 1.0e-3 { tri_bad = tri_bad + 1; }
    i = i + 3;
  }
  fails = check(tri_bad == 0, "axioms: euclidean triangle inequality (engine values)", fails);

  var bound_bad: Int = 0;
  var scale_bad: Int = 0;
  i = 0;
  while i < n {
    var j3: Int = i + 1;
    while j3 < n {
      var d = vector_distance(&vecs[i], &vecs[j3], DistanceMetric.Cosine) as Float64;
      if d < -1.0e-5 || d > 2.0 + 1.0e-5 { bound_bad = bound_bad + 1; }
      if j3 == i + 1 {
        var sv = Vector.new(dim);
        var k: Int = 0;
        while k < dim {
          sv.set(k, vecs[i].data[k] * 2.0);
          k = k + 1;
        }
        if vector_distance(&sv, &vecs[j3], DistanceMetric.Cosine) != vector_distance(&vecs[i], &vecs[j3], DistanceMetric.Cosine) {
          scale_bad = scale_bad + 1;
        }
      }
      j3 = j3 + 1;
    }
    i = i + 1;
  }
  fails = check(bound_bad == 0, "axioms: cosine distance within [0,2]", fails);
  fails = check(scale_bad == 0, "axioms: cosine scale invariance (x2 exact)", fails);

  var zv = Vector.new(dim);
  var z_ok: Bool = vector_distance(&zv, &vecs[0], DistanceMetric.Cosine) == 1.0
    && vector_distance(&vecs[0], &zv, DistanceMetric.Cosine) == 1.0;
  fails = check(z_ok, "axioms: zero-vector cosine guard == 1.0", fails);

  // ---- 3. Ranked search paths vs the oracle ranking ----
  m = 0;
  while m < 3 {
    var me = metrics[m];
    var eng = engine_new();
    create_collection(&mut eng, dim, me);
    i = 0;
    while i < n {
      upsert(&mut eng, i + 1, dup_vec(&vecs[i]));
      i = i + 1;
    }
    var ref = oracle_rank(&vecs, &q, me, n);
    var got = search_ids(&eng, &q, 5);
    fails = check(ids_slice_match(&got, &ref, 0, 5),
      "search vs oracle: " + names[m] + " top-5 rank exact", fails);
    fails = check(hits_match_oracle(&eng, &q, 5, &vecs, me, n),
      "search vs oracle: " + names[m] + " hit distances within tolerance", fails);

    // Pagination + cursor vs the same oracle ranking (Euclidean only).
    if me == DistanceMetric.Euclidean {
      fails = check(ids_slice_match(&page_ids(&eng, &q, 7, 5), &ref, 5, 7),
        "page vs oracle: offset 5 k=7 == ranks 5..12", fails);
      fails = check(ids_slice_match(&after_ids(&eng, &q, 7, ref[6]), &ref, 7, 7),
        "cursor vs oracle: after rank 6 == ranks 7..14", fails);

      // Range vs oracle: radius at the midpoint between ranks 20 and 21
      // (maximally far from float32 boundary ambiguity); expectations come
      // from the sorted oracle ranking, so engine order must match.
      var d19 = o_dist(&q, &vecs[ref[19] - 1], me);
      var d20 = o_dist(&q, &vecs[ref[20] - 1], me);
      var radius = (d19 + d20) / 2.0;
      var expected = Vec[Int].new();
      i = 0;
      while i < n {
        var oid2 = ref[i];
        if o_dist(&q, &vecs[oid2 - 1], me) <= radius { expected.push(oid2); }
        i = i + 1;
      }
      var rres = search_range(&eng, &q, radius as Float32, 100);
      var rids = Vec[Int].new();
      match rres {
        Ok(h) => {
          var x: Int = 0;
          while x < h.items.len() {
            rids.push(h.items[x].id);
            x = x + 1;
          }
        }
        Err(_) => {}
      }
      fails = check(rids.len() == expected.len() && ids_slice_match(&rids, &expected, 0, expected.len()),
        "range vs oracle: inclusive radius subset exact", fails);

      var boundary_id = ref[10];
      var bd = vector_distance(&q, &vecs[boundary_id - 1], me);
      var bres = search_range(&eng, &q, bd, 1000);
      var b_found: Bool = false;
      match bres {
        Ok(h) => {
          var x2: Int = 0;
          while x2 < h.items.len() {
            if h.items[x2].id == boundary_id { b_found = true; }
            x2 = x2 + 1;
          }
        }
        Err(_) => {}
      }
      fails = check(b_found, "range boundary: engine radius includes its own point (inclusive)", fails);
    }
    m = m + 1;
  }

  // ---- 4. Hnsw vs the oracle (recall + distance fidelity) ----
  var eheng = engine_new();
  create_collection(&mut eheng, dim, DistanceMetric.Euclidean);
  i = 0;
  while i < n {
    upsert(&mut eheng, i + 1, dup_vec(&vecs[i]));
    i = i + 1;
  }
  match set_index(&mut eheng, AnnIndexKind.Hnsw, AnnParams{ m: 8, ef_construction: 50, ef_search: 64 }) {
    Ok(_) => {}
    Err(_) => {}
  }
  var eref = oracle_rank(&vecs, &q, DistanceMetric.Euclidean, n);
  var ehits = search_ids(&eheng, &q, 5);
  var recall_hits: Int = 0;
  i = 0;
  while i < ehits.len() {
    var jj: Int = 0;
    while jj < 5 {
      if ehits[i] == eref[jj] { recall_hits = recall_hits + 1; }
      jj = jj + 1;
    }
    i = i + 1;
  }
  fails = check(ehits.len() == 5 && recall_hits == 5, "hnsw vs oracle: recall@5 == 5/5", fails);
  fails = check(hits_match_oracle(&eheng, &q, 5, &vecs, DistanceMetric.Euclidean, n),
    "hnsw vs oracle: hit distances within tolerance", fails);

  io.println("");
  io.println("probe_reference_oracle: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
