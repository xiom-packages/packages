// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: sealed segment files (M-D4). Verifies the segment codec (meta +
// vectors + payloads + Hnsw graph; atomic temp+rename; torn-tail-safe
// prefix; malformed lines stop the prefix; size guards; the lifecycle
// transition Mutable -> Sealing -> Sealed) and the engine integration
// (seal the active collection; restore into a matching collection with
// bit-exact search; WAL re-checkpointed so a reopen replays the restored
// state; cid/dim/metric mismatch refused). Exit = failed checks.

module probe_segment_file

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.index.hnsw;
use xiom.vector.segment.segment_file;
use xiom.vector.segment.segment_state;
use xiom.vectors;
use xiom.vector.payload.payload;
use xiom.string.slice;
use xiom.io;
use xiom.convert;
use xiom.num.float;

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

fn hnsw_params() -> AnnParams {
  return AnnParams{ m: 8, ef_construction: 50, ef_search: 20 };
}

fn vec_equal(a: &Vector, b: &Vector) -> Bool {
  if a.dimension != b.dimension { return false; }
  var i: Int = 0;
  while i < a.dimension {
    if float.float_bits(a.data[i] as Float64) != float.float_bits(b.data[i] as Float64) { return false; }
    i = i + 1;
  }
  return true;
}

fn hits_equal(a: &VectorEngine, b: &VectorEngine, q: &Vector, k: Int) -> Bool {
  var ha = search(a, q, k);
  var hb = search(b, q, k);
  var oka: Bool = false;
  var okb: Bool = false;
  var ia = Vec[Int].new();
  var da = Vec[Int].new();
  var ib = Vec[Int].new();
  var db = Vec[Int].new();
  match ha {
    Ok(h) => {
      oka = true;
      var i: Int = 0;
      while i < h.items.len() {
        ia.push(h.items[i].id);
        da.push(float.float_bits(h.items[i].distance as Float64));
        i = i + 1;
      }
    }
    Err(_) => {}
  }
  match hb {
    Ok(h) => {
      okb = true;
      var i: Int = 0;
      while i < h.items.len() {
        ib.push(h.items[i].id);
        db.push(float.float_bits(h.items[i].distance as Float64));
        i = i + 1;
      }
    }
    Err(_) => {}
  }
  if !oka || !okb { return false; }
  if ia.len() != ib.len() { return false; }
  var j: Int = 0;
  while j < ia.len() {
    if ia[j] != ib[j] || da[j] != db[j] { return false; }
    j = j + 1;
  }
  return true;
}

fn has_payload(eng: &VectorEngine, id: Int) -> Bool {
  match get_payload(eng, id) {
    Some(_) => { return true; }
    None => { return false; }
  }
}

// Byte offset just after the n-th newline (1-based); length if fewer.
fn byte_after_nth_newline(b: &Vec[UInt8], n: Int) -> Int {
  var seen: Int = 0;
  var i: Int = 0;
  while i < b.len() {
    if b[i] == 10 {
      seen = seen + 1;
      if seen == n { return i + 1; }
    }
    i = i + 1;
  }
  return b.len();
}

// Count complete (newline-terminated) lines within the first `count` bytes
// whose first byte equals `tag`.
fn count_complete_lines(b: &Vec[UInt8], count: Int, tag: Int) -> Int {
  var seen: Int = 0;
  var line_start: Int = 0;
  var i: Int = 0;
  var n: Int = count;
  if n > b.len() { n = b.len(); }
  while i < n {
    if b[i] == 10 {
      if i > line_start && (b[line_start] as Int) == tag { seen = seen + 1; }
      line_start = i + 1;
    }
    i = i + 1;
  }
  return seen;
}

fn write_slice(b: &Vec[UInt8], count: Int, path: Str) -> Bool {
  var out = Vec[UInt8].new();
  var i: Int = 0;
  var n: Int = count;
  if n > b.len() { n = b.len(); }
  while i < n {
    out.push(b[i]);
    i = i + 1;
  }
  var res = io.write_file_bytes(path, &out);
  match res {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

fn write_str(s: Str, path: Str) -> Bool {
  var b = slice.str_bytes(s);
  var res = io.write_file_bytes(path, &b);
  match res {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

fn main() -> Int {
  io.println("=== xvector probe: sealed segment files ===");
  var fails: Int = 0;
  var ps = "out/segment_probe.seg";
  var pt = "out/segment_probe_torn.seg";
  var pg = "out/segment_probe_garbage.seg";
  var pmiss = "out/segment_probe_missing.seg";

  // --- load degradation ---
  io.remove_file(pmiss);
  fails = check(!segment_file_load(pmiss).valid, "missing file -> invalid", fails);
  fails = check(write_str("not a segment at all, but long enough to pass the size guard .....\n", pg)
    && !segment_file_load(pg).valid,
    "garbage header -> invalid", fails);
  fails = check(write_str("xvector-segment 1\nmeta 7 1 2 4 1 2 8 50 20 extra\n", pg)
    && !segment_file_load(pg).valid,
    "malformed meta line -> invalid", fails);
  fails = check(write_str("", pg) && !segment_file_load(pg).valid,
    "empty file -> invalid", fails);

  // --- seal a live Hnsw collection through the engine ---
  var dim: Int = 4;
  var eng1 = engine_new();
  create_collection(&mut eng1, dim, DistanceMetric.Cosine);
  var s: Int = 553311;
  var qc = Vec[Float32].new();
  s = rand_coords(s, dim, &mut qc);
  var qv = vec_from_coords(&qc);
  var i: Int = 1;
  while i <= 5 {
    var c = Vec<Float32>.new();
    s = rand_coords(s, dim, &mut c);
    upsert(&mut eng1, i, vec_from_coords(&c));
    i = i + 1;
  }
  set_index(&mut eng1, AnnIndexKind.Hnsw, hnsw_params());
  var p1 = payload_new();
  payload_set(&mut p1, "tag", FieldValue.IntVal(5));
  set_payload(&mut eng1, 1, p1);

  var seal1 = seal_segment(&mut eng1, 7, ps);
  var seal1_ok: Bool = false;
  match seal1 { Ok(_) => { seal1_ok = true; } Err(_) => {} }
  fails = check(seal1_ok, "engine: seal active collection (Hnsw)", fails);

  // --- roundtrip through the codec ---
  var ss = segment_file_load(ps);
  fails = check(ss.valid, "load: valid segment", fails);
  fails = check(ss.seg_id == 7 && ss.cid == eng1.active_cid && ss.state == SegmentStateKind.Sealed,
    "load: seg_id/cid/state exact (Sealed)", fails);
  fails = check(ss.dim == 4 && ss.metric == DistanceMetric.Cosine && ss.kind == AnnIndexKind.Hnsw,
    "load: dim/metric/kind exact", fails);
  fails = check(ss.m == 8 && ss.ef_construction == 50 && ss.ef_search == 20,
    "load: ANN params exact", fails);
  fails = check(ss.store.ids.len() == 5 && ss.payloads.entries.len() == 1,
    "load: 5 vectors + 1 payload", fails);
  fails = check(ss.has_graph && hnsw_size(&ss.graph) == hnsw_size(&eng1.graph),
    "load: Hnsw graph decoded (node count equal)", fails);
  var vecs_ok: Bool = ss.store.ids.len() == 5;
  if vecs_ok {
    i = 0;
    while i < 5 {
      if ss.store.ids[i] != eng1.store.ids[i] { vecs_ok = false; }
      elif !vec_equal(&ss.store.vectors[i], &eng1.store.vectors[i]) { vecs_ok = false; }
      i = i + 1;
    }
  }
  fails = check(vecs_ok, "load: vectors bit-exact vs the live store", fails);
  var pl_ok: Bool = false;
  match payload_store_get(&ss.payloads, 1) {
    Some(pl) => { pl_ok = payload_len(&pl) == 1; }
    None => {}
  }
  fails = check(pl_ok, "load: payload restored", fails);

  // --- atomic swap ---
  fails = check(!io.file_exists(ps + ".tmp"), "atomic: no .tmp remains after a seal", fails);
  var seal2 = seal_segment(&mut eng1, 8, ps + ".tmp");
  var seal2_ok: Bool = false;
  match seal2 { Ok(_) => { seal2_ok = true; } Err(_) => {} }
  fails = check(seal2_ok && segment_file_load(ps).seg_id == 7,
    "atomic: staged-complete temp leaves the target intact", fails);
  var tmpb_res = io.read_file_bytes(ps + ".tmp");
  var tmpb = Vec[UInt8].new();
  match tmpb_res { Ok(b) => { tmpb = b; } Err(_) => { fails = fails + 1; } }
  var part = Vec[UInt8].new();
  var pi: Int = 0;
  var plim = tmpb.len() / 2;
  while pi < plim { part.push(tmpb[pi]); pi = pi + 1; }
  match io.write_file_bytes(ps + ".tmp", &part) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  fails = check(segment_file_load(ps).seg_id == 7 && segment_file_load(ps).store.ids.len() == 5,
    "atomic: partial temp cannot damage the target", fails);
  match io.remove_file(ps + ".tmp") { Ok(_) => {} Err(_) => { fails = fails + 1; } }

  // --- torn-tail sweep over the sealed bytes (5 vectors, 1 payload, graph) ---
  var fbres = io.read_file_bytes(ps);
  var fb = Vec<UInt8>.new();
  match fbres { Ok(b) => { fb = b; } Err(_) => { fails = fails + 1; } }
  var meta_end = byte_after_nth_newline(&fb, 2);
  var cuts = Vec[Int].new();
  cuts.push(0);
  cuts.push(5);
  cuts.push(17);
  cuts.push(18);
  cuts.push(18 + 10);
  cuts.push(meta_end);
  cuts.push(byte_after_nth_newline(&fb, 3));
  cuts.push(byte_after_nth_newline(&fb, 3) + 5);
  cuts.push(byte_after_nth_newline(&fb, 7));
  cuts.push(byte_after_nth_newline(&fb, 7) + 3);
  cuts.push(byte_after_nth_newline(&fb, 8));
  cuts.push(byte_after_nth_newline(&fb, 8) + 4);
  cuts.push(fb.len() - 1);
  cuts.push(fb.len());
  var bad_cuts: Int = 0;
  var ci: Int = 0;
  while ci < cuts.len() {
    var cut: Int = cuts[ci];
    if !write_slice(&fb, cut, pt) { bad_cuts = bad_cuts + 1; }
    var lc = segment_file_load(pt);
    var exp_valid: Bool = cut >= meta_end;
    var exp_v: Int = count_complete_lines(&fb, cut, 118);
    var exp_p: Int = count_complete_lines(&fb, cut, 112);
    var exp_g: Int = count_complete_lines(&fb, cut, 103);
    if lc.valid != exp_valid { bad_cuts = bad_cuts + 1; }
    if lc.store.ids.len() != exp_v { bad_cuts = bad_cuts + 1; }
    if lc.payloads.entries.len() != exp_p { bad_cuts = bad_cuts + 1; }
    if (if lc.has_graph { 1 } else { 0 }) != exp_g { bad_cuts = bad_cuts + 1; }
    var vi: Int = 0;
    while vi < lc.store.ids.len() {
      if vi >= 5 {
        bad_cuts = bad_cuts + 1;
      } elif !vec_equal(&lc.store.vectors[vi], &eng1.store.vectors[vi]) {
        bad_cuts = bad_cuts + 1;
      }
      vi = vi + 1;
    }
    io.println("    diag cut ci=" + convert.int_to_string(ci) + " len=" + convert.int_to_string(cut)
      + " valid=" + convert.int_to_string(if lc.valid { 1 } else { 0 })
      + " v=" + convert.int_to_string(lc.store.ids.len()) + "/" + convert.int_to_string(exp_v)
      + " p=" + convert.int_to_string(lc.payloads.entries.len()) + "/" + convert.int_to_string(exp_p)
      + " g=" + convert.int_to_string(if lc.has_graph { 1 } else { 0 }) + "/" + convert.int_to_string(exp_g));
    ci = ci + 1;
  }
  fails = check(bad_cuts == 0, "torn file: 14 cut points load as complete-record prefixes", fails);
  fails = check(write_slice(&fb, fb.len(), pt)
    && segment_file_load(pt).valid && segment_file_load(pt).store.ids.len() == 5
    && segment_file_load(pt).has_graph,
    "full cut: complete file loads all records + graph", fails);

  // --- malformed vector line stops the prefix ---
  fails = check(write_str("xvector-segment 1\nmeta 7 1 2 4 1 1 16 200 64\nv 1 4 1 2 3 4\nv x 4 0 0 0 0\n", pt),
    "malformed: seed scripted bytes", fails);
  var ml = segment_file_load(pt);
  fails = check(ml.valid && ml.store.ids.len() == 1 && ml.store.ids[0] == 1,
    "malformed vector line: prefix keeps the valid vector", fails);

  // --- engine restore into a matching collection ---
  var eng2 = engine_new();
  create_collection(&mut eng2, dim, DistanceMetric.Cosine);
  var rst = restore_segment(&mut eng2, ps);
  var rst_ok: Bool = false;
  match rst { Ok(_) => { rst_ok = true; } Err(_) => {} }
  fails = check(rst_ok && engine_size(&eng2) == 5, "restore: 5 records into a fresh collection", fails);
  fails = check(eng2.index_kind == AnnIndexKind.Hnsw && eng2.ann.m == 8
    && eng2.ann.ef_construction == 50 && eng2.ann.ef_search == 20,
    "restore: Hnsw config restored from the segment", fails);
  fails = check(hits_equal(&eng1, &eng2, &qv, 3), "restore: search bit-equal to the sealed engine", fails);
  fails = check(has_payload(&eng2, 1), "restore: payload restored", fails);

  // The restore is WAL-durable: reopen replays the restored state.
  upsert(&mut eng2, 99, qv);
  var rec = engine_recover(&eng2.wal, dim, DistanceMetric.Cosine);
  fails = check(engine_size(&rec) == 6 && rec.index_kind == AnnIndexKind.Hnsw,
    "restore: reopen replays restored 5 + 1 new (Hnsw)", fails);

  // Re-seal the restored engine: second roundtrip stays exact.
  var seal3 = seal_segment(&mut eng2, 9, ps);
  var seal3_ok: Bool = false;
  match seal3 { Ok(_) => { seal3_ok = true; } Err(_) => {} }
  var ss3 = segment_file_load(ps);
  fails = check(seal3_ok && ss3.valid && ss3.seg_id == 9 && ss3.store.ids.len() == 6,
    "restore: re-seal roundtrip (6 records)", fails);

  // --- refusals ---
  var eng3 = engine_new();
  create_collection(&mut eng3, 3, DistanceMetric.Euclidean);
  var bad1 = restore_segment(&mut eng3, ps);
  var bad1_err: Bool = false;
  match bad1 { Ok(_) => {} Err(_) => { bad1_err = true; } }
  fails = check(bad1_err && engine_size(&eng3) == 0, "refuse: dim/metric mismatch, engine unchanged", fails);
  var eng4 = engine_new();
  create_named_collection(&mut eng4, "a", 4, DistanceMetric.Cosine);
  create_named_collection(&mut eng4, "b", 4, DistanceMetric.Cosine);
  var bad2 = restore_segment(&mut eng4, ps);
  var bad2_err: Bool = false;
  match bad2 { Ok(_) => {} Err(_) => { bad2_err = true; } }
  fails = check(bad2_err, "refuse: cid mismatch (segment belongs to another collection)", fails);
  var bad4 = seal_segment(&mut eng1, 0, ps);
  var bad4_err: Bool = false;
  match bad4 { Ok(_) => {} Err(_) => { bad4_err = true; } }
  fails = check(bad4_err, "refuse: invalid segment id", fails);
  var bad5 = restore_segment(&mut eng2, pmiss);
  var bad5_err: Bool = false;
  match bad5 { Ok(_) => {} Err(_) => { bad5_err = true; } }
  fails = check(bad5_err, "refuse: missing segment file", fails);

  // --- Flat collection (no graph section) + empty collection ---
  var eng6 = engine_new();
  create_collection(&mut eng6, 2, DistanceMetric.Euclidean);
  i = 11;
  while i <= 13 {
    var c2 = Vec<Float32>.new();
    s = rand_coords(s, 2, &mut c2);
    upsert(&mut eng6, i, vec_from_coords(&c2));
    i = i + 1;
  }
  var seal4 = seal_segment(&mut eng6, 3, pt);
  var seal4_ok: Bool = false;
  match seal4 { Ok(_) => { seal4_ok = true; } Err(_) => {} }
  var sf = segment_file_load(pt);
  fails = check(seal4_ok && sf.valid && sf.kind == AnnIndexKind.Flat && !sf.has_graph
    && sf.store.ids.len() == 3,
    "flat: segment without a graph section round-trips", fails);
  var eng7 = engine_new();
  create_collection(&mut eng7, 2, DistanceMetric.Euclidean);
  var rst2 = restore_segment(&mut eng7, pt);
  var rst2_ok: Bool = false;
  match rst2 { Ok(_) => { rst2_ok = true; } Err(_) => {} }
  fails = check(rst2_ok && engine_size(&eng7) == 3 && eng7.index_kind == AnnIndexKind.Flat,
    "flat: restore into a matching Flat collection", fails);

  var eng8 = engine_new();
  create_collection(&mut eng8, 4, DistanceMetric.Cosine);
  var seal5 = seal_segment(&mut eng8, 4, pt);
  var seal5_ok: Bool = false;
  match seal5 { Ok(_) => { seal5_ok = true; } Err(_) => {} }
  var se = segment_file_load(pt);
  fails = check(seal5_ok && se.valid && se.store.ids.len() == 0 && se.payloads.entries.len() == 0,
    "empty: zero-record segment is valid", fails);
  var eng9 = engine_new();
  create_collection(&mut eng9, 4, DistanceMetric.Cosine);
  var rst3 = restore_segment(&mut eng9, pt);
  var rst3_ok: Bool = false;
  match rst3 { Ok(_) => { rst3_ok = true; } Err(_) => {} }
  fails = check(rst3_ok && engine_size(&eng9) == 0, "empty: restore leaves an empty collection", fails);

  io.remove_file(ps);
  io.remove_file(pt);
  io.remove_file(pg);
  io.println("");
  io.println("probe_segment_file: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
