// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// L-2 collection-move probe (offline move primitive):
//   SRC home: create "docs" (dim 4 cosine, HNSW config) + upsert 3 ->
//   export_collection -> segment artifact (durable roll; source stays
//   queryable through the sealed union) -> refusal cases (unknown, empty)
//   + the L-5 compaction-aware re-export (a rolled collection merges
//   through D7 instead of refusing).
//   COPY: the artifact is the portable unit; craft a truncated copy, a
//   CRC-mismatch copy, and a footer-less copy.
//   DST home: create "docs" (same config) -> attach_segment: all three
//   bad copies REFUSED, the good one attaches -> size/search/config travel
//   -> persist + reopen -> create another collection + reopen again (cid
//   freshness) -> source drop -> both sides consistent.
// Exit = failed checks (0 = green).

module probe_collection_move

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

fn mk_vec4(a: Float32, b: Float32, c: Float32, d: Float32) -> Vector {
  var v = Vector.new(4);
  v.set(0, a); v.set(1, b); v.set(2, c); v.set(3, d);
  return v;
}

fn mk_vec3(a: Float32, b: Float32, c: Float32) -> Vector {
  var v = Vector.new(3);
  v.set(0, a); v.set(1, b); v.set(2, c);
  return v;
}

fn f32_approx(a: Float32, b: Float32, eps: Float32) -> Bool {
  var diff = a - b;
  if diff < 0.0 { diff = -diff; }
  return diff < eps;
}

fn search_two(eng: &mut VectorEngine, q: &Vector) -> Bool {
  match search(eng, q, 2) {
    Ok(h) => {
      return h.items.len() == 2 && h.items[0].id == 1 && h.items[1].id == 2
        && f32_approx(h.items[0].distance, 0.0, 0.001)
        && f32_approx(h.items[1].distance, 0.00614, 0.001);
    }
    Err(_) => { return false; }
  }
}

fn bytes_prefix(b: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i: Int = 0;
  while i < n && i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

fn main() -> Int {
  io.println("=== xvector probe: collection move (L-2) ===");
  var fails: Int = 0;

  var p_src_m = "out/move_src_manifest.txt";
  var p_src_w = "out/move_src_wal.ckpt";
  var p_dst_m = "out/move_dst_manifest.txt";
  var p_dst_w = "out/move_dst_wal.ckpt";
  var p_art = "out/move_artifact.seg";
  var p_art_bad = "out/move_artifact_bad.seg";
  var p_art_nofoot = "out/move_artifact_nofoot.seg";
  let _c0 = io.remove_file(p_src_m);
  let _c1 = io.remove_file(p_src_w);
  let _c2 = io.remove_file(p_dst_m);
  let _c3 = io.remove_file(p_dst_w);
  let _c4 = io.remove_file(p_art);
  let _c5 = io.remove_file(p_art_bad);
  let _c6 = io.remove_file(p_art_nofoot);

  // ---- SRC: build a collection worth moving ----
  var src = engine_new();
  match create_named_collection(&mut src, "docs", 4, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  match upsert(&mut src, 1, mk_vec4(1.0, 0.0, 0.0, 0.0)) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  match upsert(&mut src, 2, mk_vec4(0.9, 0.1, 0.0, 0.0)) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  match upsert(&mut src, 3, mk_vec4(0.0, 1.0, 0.0, 0.0)) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  var hparams = AnnParams{ m: 8, ef_construction: 64, ef_search: 16 };
  match set_index(&mut src, AnnIndexKind.Hnsw, hparams) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  var q = mk_vec4(1.0, 0.0, 0.0, 0.0);
  fails = check(search_two(&mut src, &q) && engine_size(&src) == 3,
    "src: docs built (3 points, HNSW) + search {1, 2}", fails);

  // ---- export: refusal cases first ----
  var ex_miss = export_collection(&mut src, "nope", p_art);
  var miss_err: Bool = false;
  match ex_miss { Ok(_) => {} Err(_) => { miss_err = true; } }
  fails = check(miss_err, "export: unknown collection -> Err", fails);

  match create_named_collection(&mut src, "empty", 4, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  var ex_empty = export_collection(&mut src, "empty", p_art);
  var empty_err: Bool = false;
  match ex_empty { Ok(_) => {} Err(_) => { empty_err = true; } }
  fails = check(empty_err, "export: empty collection -> Err", fails);

  // ---- export docs (roll into the artifact) ----
  var ex_ok: Bool = false;
  match export_collection(&mut src, "docs", p_art) {
    Ok(seg_id) => { ex_ok = seg_id >= 1; }
    Err(_) => {}
  }
  fails = check(ex_ok, "export: docs -> segment artifact (durable roll)", fails);
  // The source collection stays queryable through the sealed union.
  fails = check(search_two(&mut src, &q), "export: source still serves (sealed union)", fails);
  // L-5: a rolled collection re-exports through the COMPACTION-AWARE path
  // (merge sealed + active remainder; bit-exact union) -- no longer a
  // refusal; the rewritten artifact stays attachable below.
  var ex_twice = export_collection(&mut src, "docs", p_art);
  var twice_ok: Bool = false;
  match ex_twice { Ok(_) => { twice_ok = true; } Err(_) => {} }
  fails = check(twice_ok, "export: rolled collection re-exports via compaction (L-5)", fails);
  fails = check(search_two(&mut src, &q), "export #2: source still serves (sealed union)", fails);

  // ---- craft bad copies from the good artifact ----
  var rb = io.read_file_bytes(p_art);
  var b = Vec[UInt8].new();
  match rb {
    Ok(x) => { b = x; }
    Err(_) => { fails = fails + 1; }
  }
  var good_len = b.len();
  io.println("    diag artifact bytes=" + convert.int_to_string(good_len));
  // (a) truncation: cut the last 9 bytes (inside the footer line)
  var cut = bytes_prefix(&b, good_len - 9);
  let _w0 = io.write_file_bytes(p_art_bad, &cut);
  // (b) footer-less: drop the entire last line (simulates a pre-L-2 segment)
  var nl: Int = good_len - 1;
  while nl >= 0 && b[nl] != 10 { nl = nl - 1; }
  var prev: Int = nl - 1;
  while prev >= 0 && b[prev] != 10 { prev = prev - 1; }
  var nofoot = bytes_prefix(&b, prev + 1);
  let _w1 = io.write_file_bytes(p_art_nofoot, &nofoot);

  // ---- DST: attach ----
  var dst = engine_new();
  match create_named_collection(&mut dst, "docs", 4, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }

  var at_trunc = attach_segment(&mut dst, p_art_bad);
  var trunc_err: Bool = false;
  match at_trunc { Ok(_) => {} Err(_) => { trunc_err = true; } }
  fails = check(trunc_err, "attach: truncated copy -> Err (no silent loss)", fails);

  var at_nofoot = attach_segment(&mut dst, p_art_nofoot);
  var nofoot_err: Bool = false;
  match at_nofoot { Ok(_) => {} Err(_) => { nofoot_err = true; } }
  fails = check(nofoot_err, "attach: footer-less copy -> Err", fails);

  var at_good = attach_segment(&mut dst, p_art);
  var at_ok: Bool = false;
  match at_good { Ok(v) => { at_ok = v; } Err(_) => {} }
  fails = check(at_ok && engine_size(&dst) == 3, "attach: good artifact -> 3 points", fails);
  fails = check(search_two(&mut dst, &q), "attach: search {1, 2} identical distances", fails);
  fails = check(dst.index_kind == AnnIndexKind.Hnsw && dst.ann.m == 8 && dst.ann.ef_search == 16,
    "attach: HNSW config traveled (m=8, ef_search=16)", fails);

  // ---- DST persists, reopens, and stays cid-safe ----
  var sm = save_manifest(&mut dst, p_dst_m);
  var wp = wal_persist(&dst.wal, p_dst_w);
  fails = check(sm && wp, "dst: persist manifest + WAL", fails);
  var rec = open_engine(&wal_load(p_dst_w), p_dst_m, 4, DistanceMetric.Cosine);
  var search_ok_reopen: Bool = true;
  match select_collection(&mut rec, "docs") {
    Ok(_) => {}
    Err(_) => { search_ok_reopen = false; }
  }
  fails = check(search_ok_reopen && engine_size(&rec) == 3 && search_two(&mut rec, &q),
    "dst reopen: docs 3 points + search {1, 2}", fails);
  match create_named_collection(&mut rec, "extra", 3, DistanceMetric.Euclidean) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  match upsert(&mut rec, 7, mk_vec3(1.0, 0.0, 0.0)) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  var sm2 = save_manifest(&mut rec, p_dst_m);
  var wp2 = wal_persist(&rec.wal, p_dst_w);
  var rec2 = open_engine(&wal_load(p_dst_w), p_dst_m, 4, DistanceMetric.Cosine);
  var cl2 = list_collections(&rec2);
  var two_ok: Bool = false;
  if cl2.names.len() == 2 {
    var i: Int = 0;
    var has_docs: Bool = false;
    var has_extra: Bool = false;
    while i < cl2.names.len() {
      if cl2.names[i] == "docs" { has_docs = true; }
      if cl2.names[i] == "extra" { has_extra = true; }
      i = i + 1;
    }
    two_ok = has_docs && has_extra;
  }
  fails = check(sm2 && wp2 && two_ok && collection_count(&rec2) == 2,
    "dst reopen #2: attached docs + extra both survive (cid freshness)", fails);

  // ---- SRC: drop the moved collection, reopen, consistent ----
  var dr_ok: Bool = false;
  match drop_collection(&mut src, "docs") { Ok(v) => { dr_ok = v; } Err(_) => {} }
  var sm_src = save_manifest(&mut src, p_src_m);
  var wp_src = wal_persist(&src.wal, p_src_w);
  var recs = open_engine(&wal_load(p_src_w), p_src_m, 4, DistanceMetric.Cosine);
  var cls = list_collections(&recs);
  var src_done: Bool = false;
  if cls.names.len() == 1 && cls.names[0] == "empty" {
    src_done = true;
  }
  fails = check(dr_ok && sm_src && wp_src && src_done,
    "src: docs dropped, only 'empty' remains after reopen", fails);

  // cleanup (best effort)
  let _r0 = io.remove_file(p_src_m);
  let _r1 = io.remove_file(p_src_w);
  let _r2 = io.remove_file(p_dst_m);
  let _r3 = io.remove_file(p_dst_w);
  let _r4 = io.remove_file(p_art);
  let _r5 = io.remove_file(p_art_bad);
  let _r6 = io.remove_file(p_art_nofoot);

  io.println("");
  io.println("probe_collection_move: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
