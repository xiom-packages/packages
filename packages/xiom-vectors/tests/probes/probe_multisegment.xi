// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// probe_multisegment -- M-D7 acceptance: roll/union search (Flat exact),
// deletes-after-seal + resurrection, payload filters across sources,
// restart recovery of sealed sources, compaction bit-exactness, the opt-in
// policy, HNSW union recall, and the missing-file counter. Prints a warm
// union-query timing diag. Exit = number of failed checks.

module probe_multisegment

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.query.search_service;
use xiom.vector.storage.vector_store;
use xiom.vector.index.ann_index;
use xiom.vectors;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vector.durability.wal_file;
use xiom.num.float;
use xiom.io;
use xiom.convert;
use xiom.time;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn lcg_next(s: Int) -> Int {
  return (s * 1103515245 + 12345) % 2147483648;
}

fn vec_next(state: Int, dim: Int) -> Vector {
  var s = state;
  var v = Vector.new(dim);
  var i: Int = 0;
  while i < dim {
    s = lcg_next(s);
    var c = (s % 2001) as Float32;
    v.set(i, c / 1000.0 - 1.0);
    i = i + 1;
  }
  return v;
}

fn mk_payload(color: Str, grp: Int) -> Payload {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal(color));
  payload_set(&mut p, "grp", FieldValue.IntVal(grp));
  return p;
}

// Brute-force top-k oracle over an (ids, vecs) mirror (Cosine).
fn oracle_topk(ids: &Vec[Int], vecs: &Vec[Vector], q: &Vector, k: Int) -> Vec[SearchResult] {
  var out = Vec[SearchResult].new();
  var i: Int = 0;
  while i < ids.len() {
    var d = vector_distance(&vecs[i], q, DistanceMetric.Cosine);
    results_push_bounded(&mut out, SearchResult{ id: ids[i], distance: d }, k);
    i = i + 1;
  }
  return out;
}

fn hits_match(a: &Vec[SearchResult], b: &Vec[SearchResult]) -> Bool {
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
  var fails = 0;
  let pa = "out/probe_ms_a.seg";
  let pb = "out/probe_ms_b.seg";
  let pc = "out/probe_ms_c.seg";
  let _r0 = io.remove_file(pa);
  let _r1 = io.remove_file(pb);
  let _r2 = io.remove_file(pc);
  let _d1 = io.remove_file("out/sealed-1-1.seg");

  // ---- (1) roll + union, Flat exactness ----
  var eng = engine_new();
  let _c = engine_create_collection(&mut eng, 4, DistanceMetric.Cosine);
  var oids = Vec[Int].new();
  var ovecs = Vec[Vector].new();
  var s = 11;
  var i: Int = 1;
  while i <= 40 {
    var v = vec_next(s, 4);
    s = lcg_next(s);
    let _u = engine_upsert(&mut eng, i, v);
    let _p = engine_set_payload(&mut eng, i, mk_payload("old", i % 3));
    oids.push(i);
    ovecs.push(v);
    i = i + 1;
  }
  var seg1: Int = -1;
  var r1 = false;
  match engine_roll_segment(&mut eng, pa) {
    Ok(sid) => { seg1 = sid; r1 = true; }
    Err(_) => {}
  }
  fails = check(r1 && seg1 == 1, "roll: assigns segment id 1", fails);
  fails = check(engine_size(&eng) == 0 && engine_sealed_count(&eng) == 1 && io.file_exists(pa),
    "roll: active cleared, entry registered, file written", fails);

  i = 41;
  while i <= 60 {
    var v = vec_next(s, 4);
    s = lcg_next(s);
    let _u = engine_upsert(&mut eng, i, v);
    oids.push(i);
    ovecs.push(v);
    i = i + 1;
  }
  var q = vec_next(s, 4);
  s = lcg_next(s);
  var expect = oracle_topk(&oids, &ovecs, &q, 10);
  var got = Vec[SearchResult].new();
  var search_ok = false;
  match engine_search(&eng, &q, 10) {
    Ok(h) => { got = h.items; search_ok = true; }
    Err(_) => {}
  }
  fails = check(search_ok && hits_match(&got, &expect), "union: Flat search bit-exact vs brute force (roll + active)", fails);

  // warm timing diag
  var t0 = time.monotonic_ms();
  var it: Int = 0;
  while it < 50 {
    let _s = engine_search(&eng, &q, 10);
    it = it + 1;
  }
  var t1 = time.monotonic_ms();
  io.println("  diag: 50 warm union searches over 60 pts = " + convert.int_to_string(t1 - t0) + " ms");

  // ---- (2) second roll + more active ----
  var seg2: Int = -1;
  match engine_roll_segment(&mut eng, pb) {
    Ok(sid) => { seg2 = sid; }
    Err(_) => {}
  }
  fails = check(seg2 == 2 && engine_sealed_count(&eng) == 2, "roll: second segment registered", fails);
  i = 61;
  while i <= 70 {
    var v = vec_next(s, 4);
    s = lcg_next(s);
    let _u = engine_upsert(&mut eng, i, v);
    oids.push(i);
    ovecs.push(v);
    i = i + 1;
  }
  var expect2 = oracle_topk(&oids, &ovecs, &q, 15);
  var got2 = Vec[SearchResult].new();
  match engine_search(&eng, &q, 15) {
    Ok(h) => { got2 = h.items; }
    Err(_) => {}
  }
  fails = check(hits_match(&got2, &expect2), "union: exact with 2 sealed + active", fails);

  // range across sources
  var expect_r = Vec[SearchResult].new();
  var ri: Int = 0;
  while ri < oids.len() {
    var d = vector_distance(&ovecs[ri], &q, DistanceMetric.Cosine);
    if d <= 0.30 {
      results_push_bounded(&mut expect_r, SearchResult{ id: oids[ri], distance: d }, 20);
    }
    ri = ri + 1;
  }
  var range_ok = false;
  match engine_search_range(&eng, &q, 0.30, 20) {
    Ok(h) => { range_ok = hits_match(&h.items, &expect_r); }
    Err(_) => {}
  }
  fails = check(range_ok, "union: range scan spans sealed + active", fails);

  // page consistency with the union order
  var page_ok = false;
  var got3 = Vec[SearchResult].new();
  match engine_search(&eng, &q, 8) {
    Ok(h) => { got3 = h.items; }
    Err(_) => {}
  }
  match engine_search_page(&eng, &q, 5, 3) {
    Ok(h) => {
      var j: Int = 0;
      var okp = h.items.len() == 5;
      while j < h.items.len() {
        if j + 3 < got3.len() {
          if h.items[j].id != got3[j + 3].id { okp = false; }
        }
        j = j + 1;
      }
      page_ok = okp;
    }
    Err(_) => {}
  }
  fails = check(page_ok, "union: page ranks match the union order", fails);

  // ---- (3) deletes after seal + resurrection ----
  let _del = engine_delete(&mut eng, 5);
  fails = check(engine_size(&eng) == 10, "tombstone: sealed-only delete leaves active untouched", fails);
  var no5 = true;
  match engine_search(&eng, &q, 70) {
    Ok(h) => {
      var j: Int = 0;
      while j < h.items.len() {
        if h.items[j].id == 5 { no5 = false; }
        j = j + 1;
      }
    }
    Err(_) => {}
  }
  fails = check(no5, "tombstone: deleted sealed id never returned", fails);

  // delete_by_filter over sealed payloads (grp=0 -> ids 3, 6, ..., 39)
  var f_grp0 = filter_eq("grp", FieldValue.IntVal(0));
  var df_ok = false;
  match engine_delete_filter(&mut eng, &f_grp0) {
    Ok(n) => { df_ok = n > 0; }
    Err(_) => {}
  }
  fails = check(df_ok, "tombstone: delete_by_filter removes sealed matches", fails);
  var f_grp0_hits = 0;
  match engine_search_filtered(&eng, &q, 70, &f_grp0) {
    Ok(h) => { f_grp0_hits = h.items.len(); }
    Err(_) => {}
  }
  fails = check(f_grp0_hits == 0, "tombstone: filtered search sees no grp=0 points", fails);

  // resurrection: re-upsert id 5 with a fresh vector (mirror rebuilt below)
  var v5 = vec_next(4242, 4);
  let _u5 = engine_upsert(&mut eng, 5, v5);
  // Rebuild the live mirror: grp0 ids (3,6,..,39) are deleted; id 5 is live
  // with v5.
  var oidsA = Vec[Int].new();
  var ovecsA = Vec[Vector].new();
  var mi: Int = 0;
  while mi < oids.len() {
    var mid = oids[mi];
    var keep_pt = true;
    if mid <= 40 && mid % 3 == 0 { keep_pt = false; }
    if keep_pt {
      if mid == 5 {
        oidsA.push(5);
        ovecsA.push(v5);
      } else {
        oidsA.push(mid);
        ovecsA.push(ovecs[mi]);
      }
    }
    mi = mi + 1;
  }
  var expect3 = oracle_topk(&oidsA, &ovecsA, &q, 12);
  var got4 = Vec[SearchResult].new();
  match engine_search(&eng, &q, 12) {
    Ok(h) => { got4 = h.items; }
    Err(_) => {}
  }
  fails = check(hits_match(&got4, &expect3), "resurrection: re-upsert revives the id (active wins, no dup)", fails);

  // ---- (4) filtered search across sources ----
  var f_red = filter_eq("color", FieldValue.TextVal("old"));
  var exp_f = Vec[SearchResult].new();
  var fi: Int = 0;
  while fi < oids.len() {
    var d2 = vector_distance(&ovecs[fi], &q, DistanceMetric.Cosine);
    results_push_bounded(&mut exp_f, SearchResult{ id: oids[fi], distance: d2 }, 10);
    fi = fi + 1;
  }
  // All mirror points carry color=old except the resurrected 5 (no payload).
  var got5 = Vec[SearchResult].new();
  var filtered_ok = false;
  match engine_search_filtered(&eng, &q, 10, &f_red) {
    Ok(h) => {
      got5 = h.items;
      filtered_ok = got5.len() == 10;
    }
    Err(_) => {}
  }
  fails = check(filtered_ok, "filtered: union filter fills k across sources", fails);

  // ---- (5) restart recovery keeps sealed sources ----
  var ck = "out/probe_ms.ckpt";
  let _rc = io.remove_file(ck);
  fails = check(wal_persist(&eng.wal, ck), "recovery: checkpoint persist", fails);
  var wr = wal_load(ck);
  var rec = engine_recover_file(&wr, "", 4, DistanceMetric.Cosine);
  fails = check(engine_sealed_count(&rec) == 2 && engine_sealed_missing(&rec) == 0,
    "recovery: both sealed sources restored + loaded", fails);
  var got6 = Vec[SearchResult].new();
  match engine_search(&rec, &q, 12) {
    Ok(h) => { got6 = h.items; }
    Err(_) => {}
  }
  fails = check(hits_match(&got6, &expect3), "recovery: union bit-exact after restart", fails);

  // ---- (6) compaction ----
  var segc: Int = -1;
  var comp_ok = false;
  match engine_compact_sealed(&mut eng, pc) {
    Ok(sid) => { segc = sid; comp_ok = true; }
    Err(_) => {}
  }
  fails = check(comp_ok && segc == 3 && engine_sealed_count(&eng) == 1 && engine_size(&eng) == 0,
    "compaction: one merged segment, active cleared", fails);
  // The live set is identical to the pre-compaction union (tombstones
  // applied, active-wins), so `expect3` is the reference.
  var got7 = Vec[SearchResult].new();
  match engine_search(&eng, &q, 12) {
    Ok(h) => { got7 = h.items; }
    Err(_) => {}
  }
  fails = check(hits_match(&got7, &expect3), "compaction: union bit-exact after merge", fails);
  var got8 = Vec[SearchResult].new();
  let _cap = wal_persist(&eng.wal, ck);
  var wr2 = wal_load(ck);
  var rec2 = engine_recover_file(&wr2, "", 4, DistanceMetric.Cosine);
  match engine_search(&rec2, &q, 12) {
    Ok(h) => { got8 = h.items; }
    Err(_) => {}
  }
  fails = check(hits_match(&got8, &expect3), "compaction: survives restart bit-exact", fails);

  // ---- (7) missing-file counter ----
  let _rm = io.remove_file(pc);
  var rec3 = engine_recover_file(&wr2, "", 4, DistanceMetric.Cosine);
  fails = check(engine_sealed_missing(&rec3) == 1 && engine_sealed_count(&rec3) == 1,
    "missing file: counted (never silent)", fails);
  var missing_hits = 99;
  match engine_search(&rec3, &q, 12) {
    Ok(h) => { missing_hits = h.items.len(); }
    Err(_) => {}
  }
  // The active remainder (61..70 + the resurrected 5) still serves; the
  // missing sealed source is excluded, never silent.
  fails = check(missing_hits == 11, "missing file: union degrades to the active store (11 pts)", fails);

  // ---- (8) policy ----
  let pe = "out/probe_ms_policy.seg";
  let _rp = io.remove_file(pe);
  var peng = engine_new();
  let _pc = engine_create_collection(&mut peng, 3, DistanceMetric.Euclidean);
  var pol_set = false;
  match engine_set_seal_policy(&mut peng, 10, "out") {
    Ok(_) => { pol_set = true; }
    Err(_) => {}
  }
  fails = check(pol_set, "policy: interval 10 armed", fails);
  var sp: Int = 1;
  var kc: Int = 1;
  while kc <= 10 {
    var v = vec_next(sp, 3);
    sp = lcg_next(sp);
    let _u = engine_upsert(&mut peng, kc, v);
    kc = kc + 1;
  }
  fails = check(engine_sealed_count(&peng) == 1 && engine_size(&peng) == 0,
    "policy: auto-roll at the threshold", fails);
  var bad_dir = engine_set_seal_policy(&mut peng, 5, "out/does-not-exist-zzz");
  fails = check(!bad_dir.is_ok, "policy: missing dir rejected", fails);
  // note: auto-roll writes <dir>/sealed-<cid>-<seg_id>.seg (cid 1)
  fails = check(io.file_exists("out/sealed-1-1.seg"), "policy: auto-roll file on disk", fails);

  // ---- (9) HNSW union recall ----
  let ph = "out/probe_ms_hnsw_a.seg";
  let _rh = io.remove_file(ph);
  var heng = engine_new();
  let _hc = engine_create_collection(&mut heng, 8, DistanceMetric.Cosine);
  var hp = ann_params_default();
  let _hi = engine_set_index(&mut heng, AnnIndexKind.Hnsw, hp);
  var hids = Vec[Int].new();
  var hvecs = Vec[Vector].new();
  var hs = 77;
  var hj: Int = 1;
  while hj <= 120 {
    var v = vec_next(hs, 8);
    hs = lcg_next(hs);
    let _u = engine_upsert(&mut heng, hj, v);
    hids.push(hj);
    hvecs.push(v);
    hj = hj + 1;
  }
  let _hr = engine_roll_segment(&mut heng, ph);
  hj = 121;
  while hj <= 200 {
    var v = vec_next(hs, 8);
    hs = lcg_next(hs);
    let _u = engine_upsert(&mut heng, hj, v);
    hids.push(hj);
    hvecs.push(v);
    hj = hj + 1;
  }
  var hrecall: Int = 0;
  var hq_total: Int = 20;
  var hqi: Int = 0;
  while hqi < hq_total {
    var hq = vec_next(hs, 8);
    hs = lcg_next(hs);
    var truth = oracle_topk(&hids, &hvecs, &hq, 10);
    match engine_search(&heng, &hq, 10) {
      Ok(h) => {
        var a: Int = 0;
        while a < h.items.len() && a < truth.len() {
          var b: Int = 0;
          var found = false;
          while b < truth.len() {
            if truth[b].id == h.items[a].id { found = true; }
            b = b + 1;
          }
          if found { hrecall = hrecall + 1; }
          a = a + 1;
        }
      }
      Err(_) => {}
    }
    hqi = hqi + 1;
  }
  var hneed = (hq_total * 10 * 80) / 100;
  fails = check(hrecall >= hneed, "HNSW: union recall@10 >= 0.80 over sealed + active", fails);

  io.println("probe_multisegment: " + convert.int_to_string(fails) + " failures");
  return fails;
}
