// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// probe_snapshot -- M-D6 acceptance: checkpoint compact+swap (bounded
// recovery, crash-safe ordering), the auto-checkpoint policy, and
// snapshot export/import (bit-exact multi-collection restore). Also prints
// a measured recovery time for a 4000-point snapshot as diag evidence.
// Exit = number of failed checks.

module probe_snapshot

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.durability.wal;
use xiom.vector.durability.wal_file;
use xiom.vector.durability.wal_segment;
use xiom.vector.durability.snapshot;
use xiom.vector.storage.vector_store;
use xiom.vectors;
use xiom.vector.payload.payload;
use xiom.num.float;
use xiom.io;
use xiom.convert;
use xiom.string.slice;
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

fn mk_payload() -> Payload {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  payload_set(&mut p, "stock", FieldValue.IntVal(7));
  return p;
}

// Bit-exact equality of the two engines' ACTIVE collection (ids, vector
// bits, payload shapes, config).
fn active_state_eq(a: &VectorEngine, b: &VectorEngine) -> Bool {
  if a.dimension != b.dimension { return false; }
  if a.metric != b.metric { return false; }
  if a.index_kind != b.index_kind { return false; }
  if payload_store_len(&a.payloads) != payload_store_len(&b.payloads) { return false; }
  var i: Int = 0;
  while i < a.store.ids.len() {
    var id = a.store.ids[i];
    match index_get(&b.store, id) {
      Some(bv) => {
        var av = a.store.vectors[i];
        if av.dimension != bv.dimension { return false; }
        var d: Int = 0;
        while d < av.dimension {
          if float.float_bits(av.data[d] as Float64) != float.float_bits(bv.data[d] as Float64) { return false; }
          d = d + 1;
        }
      }
      None => { return false; }
    }
    match payload_store_get(&a.payloads, id) {
      Some(pa) => {
        match payload_store_get(&b.payloads, id) {
          Some(pb) => { if payload_len(&pa) != payload_len(&pb) { return false; } }
          None => { return false; }
        }
      }
      None => {
        match payload_store_get(&b.payloads, id) {
          Some(_) => { return false; }
          None => {}
        }
      }
    }
    i = i + 1;
  }
  return true;
}

// Every collection (names, order, per-collection bit-exact state) matches.
fn collections_match(a: &mut VectorEngine, b: &mut VectorEngine) -> Bool {
  let la = engine_list_collections(a);
  let lb = engine_list_collections(b);
  if la.names.len() != lb.names.len() { return false; }
  var i: Int = 0;
  while i < la.names.len() {
    if la.names[i] != lb.names[i] { return false; }
    let _s1 = engine_select(a, la.names[i]);
    let _s2 = engine_select(b, lb.names[i]);
    if engine_size(a) != engine_size(b) { return false; }
    if !active_state_eq(a, b) { return false; }
    i = i + 1;
  }
  return true;
}

fn main() -> Int {
  var fails = 0;
  let ck = "out/probe_snapshot.ckpt";
  let sg = "out/probe_snapshot.seg";
  let _r0 = io.remove_file(ck);
  let _r1 = io.remove_file(sg);
  let _r2 = io.remove_file(ck + ".tmp");

  // ---- (1) compact + durable swap ----
  var eng = engine_new();
  var en_ok = false;
  match engine_enable_durable(&mut eng, sg) {
    Ok(_) => { en_ok = true; }
    Err(_) => {}
  }
  fails = check(en_ok, "swap: durable mode enabled", fails);
  var cp_ok = false;
  match engine_set_checkpoint_path(&mut eng, ck) {
    Ok(_) => { cp_ok = true; }
    Err(_) => {}
  }
  fails = check(cp_ok, "swap: checkpoint path set", fails);
  let _c = engine_create_collection(&mut eng, 4, DistanceMetric.Cosine);

  var s = 7;
  var i: Int = 1;
  while i <= 300 {
    var v = vec_next(s, 4);
    s = lcg_next(s);
    let _u = engine_upsert(&mut eng, i, v);
    i = i + 1;
  }
  // Churn so compaction has something to reclaim: 100 updates (re-upsert)
  // + 50 deletes -> live = 250 points.
  i = 1;
  while i <= 100 {
    var v = vec_next(s, 4);
    s = lcg_next(s);
    let _u = engine_upsert(&mut eng, i, v);
    i = i + 1;
  }
  i = 201;
  while i <= 250 {
    let _d = engine_delete(&mut eng, i);
    i = i + 1;
  }
  fails = check(engine_size(&eng) == 250, "swap: churn leaves 250 live points", fails);
  var log_before = eng.wal.records.len();
  var fr_before = engine_synced_lsn(&eng);
  var sw_lsn: Int = -1;
  var sw_ok = false;
  match engine_checkpoint_swap(&mut eng) {
    Ok(l) => { sw_ok = true; sw_lsn = l; }
    Err(_) => {}
  }
  // Compaction REBASES LSNs (live records get fresh, higher LSNs; old LSNs
  // are abandoned, never reused), so the returned frontier is >= the old
  // one and must equal the compacted log's current LSN.
  fails = check(sw_ok && sw_lsn >= fr_before && sw_lsn == wal_writer_current_lsn(&eng.wal),
    "swap: returned frontier covers the checkpoint", fails);
  fails = check(eng.wal.records.len() < log_before, "swap: in-memory log compacted to live state", fails);
  fails = check(segment_last_lsn(sg) == 0, "swap: delta segment rotated", fails);
  fails = check(engine_synced_lsn(&eng) == wal_writer_current_lsn(&eng.wal), "swap: frontier covers the checkpoint", fails);
  fails = check(engine_checkpoint_countdown(&eng) == 0, "swap: commit counter reset", fails);
  var rec = engine_open_durable(ck, sg, "", 4, DistanceMetric.Cosine);
  fails = check(engine_size(&rec) == 250, "swap: recovery keeps every live point", fails);
  fails = check(active_state_eq(&eng, &rec), "swap: recovered state bit-exact", fails);

  var v301 = vec_next(s, 4);
  s = lcg_next(s);
  let _u301 = engine_upsert(&mut eng, 301, v301);
  fails = check(segment_last_lsn(sg) >= 1, "swap: post-swap acks append to the fresh segment", fails);
  var rec2 = engine_open_durable(ck, sg, "", 4, DistanceMetric.Cosine);
  fails = check(engine_size(&rec2) == 251, "swap: checkpoint + post-swap delta merge", fails);
  fails = check(active_state_eq(&eng, &rec2), "swap: post-swap recovery bit-exact", fails);

  // ---- (2) auto-checkpoint policy ----
  let ck2 = "out/probe_snapshot2.ckpt";
  let sg2 = "out/probe_snapshot2.seg";
  let _r3 = io.remove_file(ck2);
  let _r4 = io.remove_file(sg2);
  var pe = engine_new();
  let _pe_en = engine_enable_durable(&mut pe, sg2);
  let _pe_cp = engine_set_checkpoint_path(&mut pe, ck2);
  var pol_ok = false;
  match engine_set_checkpoint_policy(&mut pe, 5) {
    Ok(_) => { pol_ok = true; }
    Err(_) => {}
  }
  fails = check(pol_ok, "policy: interval set", fails);
  let _pc = engine_create_collection(&mut pe, 4, DistanceMetric.Cosine);
  var k: Int = 1;
  while k <= 5 {
    var pv = vec_next(s, 4);
    s = lcg_next(s);
    let _pu = engine_upsert(&mut pe, k, pv);
    k = k + 1;
  }
  // commits: create(1) + 5 upserts = 6; the swap fired at commit 5.
  fails = check(io.file_exists(ck2), "policy: checkpoint written at the threshold", fails);
  fails = check(engine_checkpoint_countdown(&pe) == 1, "policy: counter restarts after the auto swap", fails);
  var prec = engine_open_durable(ck2, sg2, "", 4, DistanceMetric.Cosine);
  fails = check(engine_size(&prec) == 5, "policy: no loss across the auto swap", fails);

  // ---- (3) snapshot export/import (multi-collection) ----
  var src = engine_new();
  let _sa = engine_create_named(&mut src, "vecs", 4, DistanceMetric.Cosine);
  var t: Int = 1;
  while t <= 5 {
    var v = vec_next(s, 4);
    s = lcg_next(s);
    let _u = engine_upsert(&mut src, t, v);
    t = t + 1;
  }
  let _sp = engine_set_payload(&mut src, 1, mk_payload());
  let _sb = engine_create_named(&mut src, "imgs", 3, DistanceMetric.Euclidean);
  var z: Int = 1;
  while z <= 4 {
    var v = vec_next(s, 3);
    s = lcg_next(s);
    let _u = engine_upsert(&mut src, z, v);
    z = z + 1;
  }
  let _sp2 = engine_set_payload(&mut src, 2, mk_payload());

  let base = "out/probe_snap";
  let _rs = io.remove_file(base + ".ckpt");
  let _rm = io.remove_file(base + ".manifest");
  let _rt = io.remove_file(base + ".meta");
  var sc_ok = false;
  match snapshot_create(&mut src, "out", "probe_snap") {
    Ok(_b) => { sc_ok = true; }
    Err(_) => {}
  }
  fails = check(sc_ok, "snapshot: create (multi-collection)", fails);
  fails = check(snapshot_valid(base), "snapshot: meta valid", fails);
  var meta = snapshot_meta_read(base);
  fails = check(meta.valid && meta.version == 1 && meta.collections == 2, "snapshot: meta version + collection count", fails);

  var ld_ok = false;
  var loaded = engine_new();
  match snapshot_load(base, "out/probe_snap_restore.seg", 4, DistanceMetric.Cosine) {
    Ok(e) => { loaded = e; ld_ok = true; }
    Err(_) => {}
  }
  fails = check(ld_ok, "snapshot: load", fails);
  fails = check(collections_match(&mut src, &mut loaded), "snapshot: multi-collection bit-exact restore", fails);

  // Build the expected search on the restored engine's active collection.
  var q = vec_next(424242, 3);
  var hits_ok = true;
  if engine_size(&loaded) > 0 {
    match engine_search(&loaded, &q, 2) {
      Ok(h) => { hits_ok = h.items.len() == 2; }
      Err(_) => { hits_ok = false; }
    }
  }
  fails = check(hits_ok, "snapshot: restored engine searches", fails);

  // Corrupt meta refused.
  let _cw = io.write_file_bytes(base + ".meta", &slice.str_bytes("garbage\n"));
  fails = check(!snapshot_valid(base), "snapshot: corrupt meta refused", fails);
  let dl2 = snapshot_load(base, "out/probe_snap_restore2.seg", 4, DistanceMetric.Cosine);
  fails = check(!dl2.is_ok, "snapshot: load refuses corrupt meta", fails);

  // ---- (4) recovery-time diag (4000 points, in-memory source) ----
  var big = engine_new();
  let _bc = engine_create_collection(&mut big, 4, DistanceMetric.Cosine);
  var s2 = 99;
  var bi: Int = 1;
  while bi <= 4000 {
    var v = vec_next(s2, 4);
    s2 = lcg_next(s2);
    let _u = engine_upsert(&mut big, bi, v);
    bi = bi + 1;
  }
  let big_base = "out/probe_snap_big";
  let _rb1 = io.remove_file(big_base + ".ckpt");
  let _rb2 = io.remove_file(big_base + ".manifest");
  let _rb3 = io.remove_file(big_base + ".meta");
  var big_ok = false;
  match snapshot_create(&mut big, "out", "probe_snap_big") {
    Ok(_b) => { big_ok = true; }
    Err(_) => {}
  }
  fails = check(big_ok, "snapshot: 4000-point create", fails);
  var t0 = time.monotonic_ms();
  var big2 = engine_new();
  var big_ld = false;
  match snapshot_load(big_base, "out/probe_snap_big_restore.seg", 4, DistanceMetric.Cosine) {
    Ok(e) => { big2 = e; big_ld = true; }
    Err(_) => {}
  }
  var t1 = time.monotonic_ms();
  io.println("  diag: snapshot_load(4000 pts) = " + convert.int_to_string(t1 - t0) + " ms");
  fails = check(big_ld && engine_size(&big2) == 4000, "snapshot: 4000-point restore complete", fails);

  io.println("probe_snapshot: " + convert.int_to_string(fails) + " failures");
  return fails;
}
