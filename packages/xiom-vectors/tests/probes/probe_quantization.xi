// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Probe: SQ8 quantization + the two-tier quantized scan (reference study
// 02, Q-a; study 03 record-layout input). Deterministic LCG corpus, no
// RNG dependency. Checks: training determinism (repeat + reversed order),
// the per-component round-trip bound (<= vstep + float slack), clamping,
// constant dimensions, malformed-input rejection, table distances vs the
// exact distance on decoded vectors, the documented coarse deviation
// bound, bit-identical `sq8_scan_rescore` vs `search_knn` for all three
// metrics, scan determinism, empty-store behavior, and the byte
// accounting (f32 vs int8 per vector). Exit = failed checks.

use xiom.io;
use xiom.num.float;
use xiom.convert;
use xiom.vectors;
use xiom.vector.storage.vector_store;
use xiom.vector.query.search_service;
use xiom.vector.index.quantize;
use xiom.vector.index.ann_index;
use xiom.vector.segment.segment_file;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  if num < 0 { return "-" + int_to_str(0 - num); }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

fn check(passed: Bool, name: Str, fails: Int) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return fails;
  }
  io.println("  [FAIL] " + name);
  return fails + 1;
}

fn lcg_next(state: Int) -> Int {
  var hi = state / 65536;
  var lo = state % 65536;
  var a = 36969 * (hi % 65536) + state / 2147483648;
  var b = 18000 * lo + state % 65536;
  return ((a % 65536) * 65536 + b % 65536) % 2147483648;
}

fn rand_coords(state: Int, dim: Int, out: &mut Vec[Float32]) -> Int {
  var s = state;
  var i: Int = 0;
  while i < dim {
    s = lcg_next(s);
    var v = ((s % 4001) as Float32) / 1000.0 - 2.0;
    out.push(v);
    i = i + 1;
  }
  return s;
}

fn vec_from_coords(coords: &Vec[Float32]) -> Vector {
  var v = Vector.new(coords.len());
  var i: Int = 0;
  while i < coords.len() {
    v.data[i] = coords[i];
    i = i + 1;
  }
  return v;
}

fn results_equal(a: &Vec[SearchResult], b: &Vec[QuantHit]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i].id != b[i].id { return false; }
    if float.float_bits(a[i].distance as Float64) != float.float_bits(b[i].distance as Float64) { return false; }
    i = i + 1;
  }
  return true;
}

fn sq_equal(a: &SQ8, b: &SQ8) -> Bool {
  if a.dim != b.dim { return false; }
  var d: Int = 0;
  while d < a.dim {
    if float.float_bits(a.vmin[d] as Float64) != float.float_bits(b.vmin[d] as Float64) { return false; }
    if float.float_bits(a.vstep[d] as Float64) != float.float_bits(b.vstep[d] as Float64) { return false; }
    d = d + 1;
  }
  return true;
}

fn main() -> Int {
  var fails: Int = 0;

  // ---- corpus (n=200 dim=8, LCG, same shape as probe_hnsw_recall) ----
  var n: Int = 200;
  var dim: Int = 8;
  var k: Int = 10;
  var state: Int = 881001;
  var flat = index_new(dim);
  var train_vs = Vec[Vector].new();
  var i: Int = 0;
  while i < n {
    var coords = Vec[Float32].new();
    state = rand_coords(state, dim, &mut coords);
    var v = vec_from_coords(&coords);
    index_add(&mut flat, i + 1, v);
    train_vs.push(v);
    i = i + 1;
  }
  var queries = Vec[Vector].new();
  i = 0;
  while i < 10 {
    var coords = Vec[Float32].new();
    state = rand_coords(state, dim, &mut coords);
    queries.push(vec_from_coords(&coords));
    i = i + 1;
  }

  // ---- training determinism + None cases ----
  var sq_opt = sq8_train(&train_vs);
  var sq = SQ8{ dim: 0, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() };
  var have_sq: Bool = false;
  match sq_opt {
    Some(s) => { sq = s; have_sq = true; }
    None => {}
  }
  fails = check(have_sq && sq.dim == dim, "train: SQ8 from 200 vectors (dim=8)", fails);

  var sq2 = SQ8{ dim: 0, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() };
  match sq8_train(&train_vs) {
    Some(s) => { sq2 = s; }
    None => {}
  }
  fails = check(have_sq && sq_equal(&sq, &sq2), "train: deterministic across runs", fails);

  var reversed = Vec[Vector].new();
  i = train_vs.len() - 1;
  while i >= 0 {
    reversed.push(train_vs[i]);
    i = i - 1;
  }
  var sq3 = SQ8{ dim: 0, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() };
  match sq8_train(&reversed) {
    Some(s) => { sq3 = s; }
    None => {}
  }
  fails = check(have_sq && sq_equal(&sq, &sq3), "train: order-independent (reversed input)", fails);

  var empty = Vec[Vector].new();
  var none1: Bool = true;
  match sq8_train(&empty) { Some(_) => { none1 = false; } None => {} }
  var mism = Vec[Vector].new();
  var m1c = Vec[Float32].new();
  m1c.push(0.5);
  m1c.push(0.5);
  mism.push(vec_from_coords(&m1c));
  var m2c = Vec[Float32].new();
  m2c.push(0.5);
  m2c.push(0.5);
  m2c.push(0.5);
  mism.push(vec_from_coords(&m2c));
  var none2: Bool = true;
  match sq8_train(&mism) { Some(_) => { none2 = false; } None => {} }
  fails = check(none1 && none2, "train: empty -> None, dimension mismatch -> None", fails);

  // ---- round-trip bound + encoding shape ----
  var max_err: Float32 = 0.0;
  var max_ratio: Float32 = 0.0;
  i = 0;
  while i < n {
    var codes = sq8_encode_one(&sq, &train_vs[i]);
    var dec_opt = sq8_decode_one(&sq, &codes);
    match dec_opt {
      Some(dec) => {
        var d: Int = 0;
        while d < dim {
          var e = train_vs[i].data[d] - dec.data[d];
          if e < 0.0 { e = 0.0 - e; }
          if e > max_err { max_err = e; }
          if sq.vstep[d] > 0.0 {
            var r = e / sq.vstep[d];
            if r > max_ratio { max_ratio = r; }
          }
          d = d + 1;
        }
      }
      None => { fails = fails + 1; }
    }
    i = i + 1;
  }
  var bound = sq8_max_error(&sq);
  fails = check(codes_len_ok(&sq, &flat) && max_err <= bound + 0.00001, "roundtrip: max component error <= vstep (+slack)", fails);
  io.println("    diag SQ8: max_err=" + convert.float_to_string(max_err as Float64)
    + " bound(vstep max)=" + convert.float_to_string(bound as Float64)
    + " max_err/vstep=" + convert.float_to_string(max_ratio as Float64));

  // ---- clamping + constant dimension ----
  var lo = Vector.new(dim);
  var hi = Vector.new(dim);
  i = 0;
  while i < dim {
    lo.data[i] = sq.vmin[i] - 1.0;
    hi.data[i] = sq.vmin[i] + 500.0 * sq.vstep[i];
    i = i + 1;
  }
  var clo = sq8_encode_one(&sq, &lo);
  var chi = sq8_encode_one(&sq, &hi);
  var clamp_ok: Bool = true;
  i = 0;
  while i < dim {
    if clo[i] != 0 { clamp_ok = false; }
    if chi[i] != 255 { clamp_ok = false; }
    i = i + 1;
  }
  fails = check(clamp_ok, "encode: out-of-range clamps to 0 / 255", fails);

  var const_vs = Vec[Vector].new();
  i = 0;
  while i < 8 {
    var c = Vec[Float32].new();
    var d: Int = 0;
    while d < 4 {
      c.push((d as Float32) * 0.5);
      d = d + 1;
    }
    c[1] = 7.0; // C-15 regression line: literal stores into Vec[Float32]
    // slots must narrow (fixed on compiler v0.64.4, m271; repro
    // docs/repro/xv-f32-slot-literal-write). The constant-dim assert
    // below fails if this stores raw bits again.
    const_vs.push(vec_from_coords(&c));
    i = i + 1;
  }
  var sqc = SQ8{ dim: 0, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() };
  var have_c: Bool = false;
  match sq8_train(&const_vs) {
    Some(s) => { sqc = s; have_c = true; }
    None => {}
  }
  var const_ok: Bool = false;
  if have_c {
    var cc = sq8_encode_one(&sqc, &const_vs[0]);
    var cd_opt = sq8_decode_one(&sqc, &cc);
    match cd_opt {
      Some(cd) => {
        const_ok = sqc.vstep[1] == 0.0 && cc[1] == 0 && cd.data[1] == 7.0;
      }
      None => { io.println("    diag const: decode None"); }
    }
  } else {
    io.println("    diag const: train returned None");
  }
  fails = check(const_ok, "constant dimension: vstep 0, code 0, exact decode", fails);

  // ---- malformed decode rejection ----
  var shortc = Vec[Int].new();
  shortc.push(1);
  var bidx = Vec[Int].new();
  i = 0;
  while i < dim {
    bidx.push(1);
    i = i + 1;
  }
  bidx[3] = 256;
  var badc = Vec[Int].new();
  i = 0;
  while i < dim {
    badc.push(-1);
    i = i + 1;
  }
  var none3: Bool = true;
  match sq8_decode_one(&sq, &shortc) { Some(_) => { none3 = false; } None => {} }
  var none4: Bool = true;
  match sq8_decode_one(&sq, &bidx) { Some(_) => { none4 = false; } None => {} }
  var none5: Bool = true;
  match sq8_decode_one(&sq, &badc) { Some(_) => { none5 = false; } None => {} }
  fails = check(none3 && none4 && none5, "decode: short / code 256 / negative -> None", fails);

  // ---- table distances vs exact distance on decoded vectors ----
  var codes = sq8_encode_store(&flat, &sq);
  fails = check(codes.len() == n * dim, "encode_store: flattened dim per position", fails);

  var q = queries[0];
  var t_l2 = sq8_table_l2(&sq, &q);
  var t_ip = sq8_table_ip(&sq, &q);
  var t_nr = sq8_table_norm2(&sq);
  var tab_err: Float32 = 0.0;
  i = 0;
  while i < 20 {
    var dc = Vec[Int].new();
    var d: Int = 0;
    while d < dim {
      dc.push(codes[i * dim + d]);
      d = d + 1;
    }
    var dec_opt = sq8_decode_one(&sq, &dc);
    match dec_opt {
      Some(dec) => {
        var l2_err = sq8_l2_distance(&t_l2, &codes, i * dim) - vector_distance(&dec, &q, DistanceMetric.Euclidean);
        if l2_err < 0.0 { l2_err = 0.0 - l2_err; }
        if l2_err > tab_err { tab_err = l2_err; }
        var ip_err = sq8_ip_distance(&t_ip, &codes, i * dim) - vector_distance(&dec, &q, DistanceMetric.DotProduct);
        if ip_err < 0.0 { ip_err = 0.0 - ip_err; }
        if ip_err > tab_err { tab_err = ip_err; }
        var qmag = vector_magnitude(&q);
        var cos_err = sq8_cos_distance(&t_ip, &t_nr, qmag, &codes, i * dim) - vector_distance(&dec, &q, DistanceMetric.Cosine);
        if cos_err < 0.0 { cos_err = 0.0 - cos_err; }
        if cos_err > tab_err { tab_err = cos_err; }
      }
      None => { fails = fails + 1; }
    }
    i = i + 1;
  }
  io.println("    diag tables: max |table - exact(decoded)| = " + convert.float_to_string(tab_err as Float64));
  fails = check(tab_err <= 0.0001, "tables: match exact distances on decoded vectors (1e-4)", fails);

  // ---- documented coarse deviation bound (study 02 error story) ----
  var max_dev: Float32 = 0.0;
  var max_bound: Float32 = 0.0;
  var bound_ok: Bool = true;
  i = 0;
  while i < n {
    var coarse = sq8_l2_distance(&t_l2, &codes, i * dim);
    var exact = vector_distance(&flat.vectors[i], &q, DistanceMetric.Euclidean);
    var dev = coarse - exact;
    if dev < 0.0 { dev = 0.0 - dev; }
    if dev > max_dev { max_dev = dev; }
    // sum_d e_d * (2|x_d| + e_d + 2|q_d|)
    var bnd: Float32 = 0.0;
    var d2: Int = 0;
    while d2 < dim {
      var e = sq.vstep[d2];
      var xd = flat.vectors[i].data[d2];
      if xd < 0.0 { xd = 0.0 - xd; }
      var qd = q.data[d2];
      if qd < 0.0 { qd = 0.0 - qd; }
      bnd = bnd + e * (2.0 * xd + e + 2.0 * qd);
      d2 = d2 + 1;
    }
    if bnd > max_bound { max_bound = bnd; }
    if dev > bnd { bound_ok = false; }
    i = i + 1;
  }
  io.println("    diag deviation: max measured=" + convert.float_to_string(max_dev as Float64)
    + " max bound=" + convert.float_to_string(max_bound as Float64));
  fails = check(bound_ok, "coarse tier: measured deviation <= documented bound", fails);

  // ---- two-tier rescore bit-identical to exact, all metrics ----
  var metrics = Vec[Int].new();
  metrics.push(1);
  metrics.push(2);
  metrics.push(3);
  var all_ok: Bool = true;
  var eq_count: Int = 0;
  var qn: Int = 0;
  while qn < queries.len() {
    var m: Int = 0;
    while m < 3 {
      var metric = DistanceMetric.Euclidean;
      if metrics[m] == 1 { metric = DistanceMetric.Cosine; }
      elif metrics[m] == 2 { metric = DistanceMetric.DotProduct; }
      var exact = search_knn(&flat, &queries[qn], k, metric);
      var resc = sq8_scan_rescore(&flat, &sq, &codes, &queries[qn], k, metric, 8);
      if results_equal(&exact, &resc) { eq_count = eq_count + 1; } else { all_ok = false; }
      m = m + 1;
    }
    qn = qn + 1;
  }
  fails = check(all_ok && eq_count == 30, "rescore: bit-identical to exact for 10 queries x 3 metrics", fails);

  // ---- determinism of the two-tier scan ----
  var r1 = sq8_scan_rescore(&flat, &sq, &codes, &queries[0], k, DistanceMetric.Euclidean, 8);
  var r2 = sq8_scan_rescore(&flat, &sq, &codes, &queries[0], k, DistanceMetric.Euclidean, 8);
  fails = check(results_equal_direct(&r1, &r2), "rescore: deterministic across runs", fails);

  // ---- empty store + k > n bounds ----
  var empty_store = index_new(dim);
  var empty_codes = Vec[Int].new();
  var er0 = sq8_scan_rescore(&empty_store, &sq, &empty_codes, &q, 5, DistanceMetric.Euclidean, 8);
  var er1 = sq8_scan_coarse(&empty_store, &sq, &empty_codes, &q, 5, DistanceMetric.Euclidean);
  var er2 = sq8_scan_rescore(&flat, &sq, &codes, &q, 500, DistanceMetric.Euclidean, 8);
  fails = check(er0.len() == 0 && er1.len() == 0 && er2.len() == n, "bounds: empty store -> empty; k > n -> n hits", fails);

  // ---- coarse scan shape + byte accounting ----
  var coarse_top = sq8_scan_coarse(&flat, &sq, &codes, &q, k, DistanceMetric.Euclidean);
  fails = check(coarse_top.len() == k, "coarse scan: returns k hits", fails);
  var f32_bytes: Int = 4 * dim;
  var sq8_bytes: Int = dim;
  io.println("    diag bytes/vector: f32=" + int_to_str(f32_bytes)
    + "B sq8=" + int_to_str(sq8_bytes) + "B ratio=" + int_to_str(f32_bytes / sq8_bytes) + "x (dim=8)");

  // ---- Q-a2a: segment v2 artifact (SQ section, opt-in) ----
  var sseg = sealed_segment_new(9, 1, dim, DistanceMetric.Euclidean, AnnIndexKind.Flat, AnnParams{ m: 16, ef_construction: 200, ef_search: 64 });
  var sseal_ok = sealed_segment_seal(&mut sseg);
  sseg.store = flat;
  var sq_armed = sealed_segment_enable_sq(&mut sseg);
  fails = check(sseal_ok && sq_armed && sseg.has_sq, "segment: seal + enable_sq arms the codes", fails);

  var pplain = "out/quant_seg_plain.seg";
  var psq = "out/quant_seg_sq.seg";
  sseg.has_sq = false;
  var ok_plain = segment_file_persist(&sseg, pplain);
  sseg.has_sq = true;
  var ok_sq = segment_file_persist(&sseg, psq);
  var sz_plain: Int = -1;
  var sz_sq: Int = -1;
  match io.file_size(pplain) { Some(nn) => { sz_plain = nn; } None => {} }
  match io.file_size(psq) { Some(nn) => { sz_sq = nn; } None => {} }
  io.println("    diag segment: plain=" + int_to_str(sz_plain) + "B with_sq=" + int_to_str(sz_sq)
    + "B delta/vector=" + int_to_str((sz_sq - sz_plain) / n) + "B (text; binary SQ8 would be "
    + int_to_str(sq8_bytes) + "B vs f32 " + int_to_str(f32_bytes) + "B)");
  fails = check(ok_plain && ok_sq && sz_sq > sz_plain, "segment: plain v1 + sq v2 persist; byte delta measured", fails);

  var ld = segment_file_load(psq);
  fails = check(ld.valid && ld.has_sq && ld.store.ids.len() == n && ld.codes.len() == n * dim
    && sq_equal(&ld.sq, &sseg.sq) && codes_equal(&ld.codes, &sseg.codes),
    "segment v2: load roundtrips ranges + codes", fails);
  var ld1 = segment_file_load(pplain);
  fails = check(ld1.valid && !ld1.has_sq && ld1.store.ids.len() == n,
    "segment v1: plain file loads with has_sq false", fails);

  var seg_ok: Bool = true;
  qn = 0;
  while qn < queries.len() {
    var exact2 = search_knn(&ld.store, &queries[qn], k, DistanceMetric.Euclidean);
    var resc2 = sq8_scan_rescore(&ld.store, &ld.sq, &ld.codes, &queries[qn], k, DistanceMetric.Euclidean, 8);
    if !results_equal(&exact2, &resc2) { seg_ok = false; }
    qn = qn + 1;
  }
  fails = check(seg_ok, "segment v2: rescore over the loaded artifact == exact (10 queries)", fails);

  match io.read_file_bytes(psq) {
    Ok(fb) => {
      var cut1 = "out/quant_seg_cut1.seg";
      var cut2 = "out/quant_seg_cut2.seg";
      var w1 = write_slice(&fb, fb.len() - 1, cut1);
      var w2 = write_slice(&fb, fb.len() - 4000, cut2);
      var lc1 = segment_file_load(cut1);
      var lc2 = segment_file_load(cut2);
      // L-2 semantics: the last byte is the integrity footer's newline --
      // cutting it drops ONLY the footer; the q/c sections stay intact
      // (codes kept, footer_seen false). A cut INTO the q/c section still
      // drops the codes and keeps the vectors.
      fails = check(w1 && w2
        && lc1.valid && lc1.has_sq && lc1.store.ids.len() == n
        && lc1.codes.len() == n * dim && !lc1.footer_seen
        && lc2.valid && !lc2.has_sq && lc2.store.ids.len() == n,
        "segment v2: footer-only tear keeps codes; q/c tear drops codes, vectors intact", fails);
    }
    Err(_) => { fails = fails + 1; }
  }

  io.println("");
  io.println("probe_quantization: exit=" + int_to_str(fails));
  return fails;
}

fn codes_len_ok(sq: &SQ8, flat: &VectorIndex) -> Bool {
  var codes = sq8_encode_store(flat, sq);
  return codes.len() == flat.ids.len() * sq.dim;
}

fn results_equal_direct(a: &Vec[QuantHit], b: &Vec[QuantHit]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i].id != b[i].id { return false; }
    if float.float_bits(a[i].distance as Float64) != float.float_bits(b[i].distance as Float64) { return false; }
    i = i + 1;
  }
  return true;
}

fn codes_equal(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn write_slice(b: &Vec[UInt8], count: Int, path: Str) -> Bool {
  var out = Vec[UInt8].new();
  var i: Int = 0;
  var nn: Int = count;
  if nn > b.len() { nn = b.len(); }
  while i < nn {
    out.push(b[i]);
    i = i + 1;
  }
  var res = io.write_file_bytes(path, &out);
  match res {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}
