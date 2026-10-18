// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Kill-recovery acceptance (in-memory WAL model): for every prefix of a
// scripted write log, recovering the prefix and then applying the next
// record must equal recovering the prefix including that record. This is
// the crash guarantee at the model level: whatever prefix survives a kill,
// recovery lands exactly on the state after that prefix. Also checks the
// property on a compacted checkpoint log, full-recovery equality with the
// live engine, an empty log, and a corrupt (torn) record. Exit = failed
// checks.

module probe_kill_recovery

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.durability.wal;
use xiom.vector.storage.vector_store;
use xiom.vectors;
use xiom.vector.payload.payload;
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

// Rebuild a WAL with only the first `count` records (order preserved).
fn prefix_writer(w: &WalWriter, count: Int) -> WalWriter {
  var pw = wal_writer_new();
  var i: Int = 0;
  while i < count && i < w.records.len() {
    wal_writer_append_payload(&mut pw, w.records[i].op, w.records[i].key, w.records[i].value, w.records[i].payload);
    i = i + 1;
  }
  return pw;
}

// Store/payload equality; config compared only when `cfg` (manifest records
// change config by design and are verified by the engine probe).
fn same_state(a: &VectorEngine, b: &VectorEngine, cfg: Bool) -> Bool {
  if engine_size(a) != engine_size(b) { return false; }
  if payload_store_len(&a.payloads) != payload_store_len(&b.payloads) { return false; }
  if cfg {
    if a.dimension != b.dimension { return false; }
    if a.metric != b.metric { return false; }
    if a.index_kind != b.index_kind { return false; }
  }
  var i: Int = 0;
  while i < engine_size(a) {
    var aid = a.store.ids[i];
    match index_get(&b.store, aid) {
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
    i = i + 1;
  }
  var p: Int = 0;
  while p < a.payloads.entries.len() {
    match payload_store_get(&b.payloads, a.payloads.entries[p].id) {
      Some(bp) => { if payload_len(&bp) != payload_len(&a.payloads.entries[p].payload) { return false; } }
      None => { return false; }
    }
    p = p + 1;
  }
  return true;
}

// Apply one record's effect to an already recovered engine (best effort;
// malformed payloads are a no-op, matching replay semantics).
fn apply_record(e: &mut VectorEngine, rec: WalRecord) {
  if rec.op == WalOpKind.Insert {
    match vector_decode(&rec.payload) {
      Some(v) => { upsert(e, rec.key, v); }
      None => {}
    }
  } elif rec.op == WalOpKind.Delete {
    delete_point(e, rec.key);
  } elif rec.op == WalOpKind.Update {
    match payload_decode(&rec.payload) {
      Some(p) => { set_payload(e, rec.key, p); }
      None => {}
    }
  }
}

// Prefix-exactness: for each t, apply(recover(records[0..t]), record[t])
// must equal recover(records[0..t+1]). Returns the mismatch count.
fn prefix_exactness(w: &WalWriter, dim: Int, metric: DistanceMetric) -> Int {
  var mism: Int = 0;
  var t: Int = 0;
  while t < w.records.len() - 1 {
    var p1 = prefix_writer(w, t);
    var p2 = prefix_writer(w, t + 1);
    var e1 = engine_recover(&p1, dim, metric);
    var rec = w.records[t];
    apply_record(&mut e1, rec);
    var e2 = engine_recover(&p2, dim, metric);
    var cfg: Bool = rec.op != WalOpKind.ManifestUpdate;
    if !same_state(&e1, &e2, cfg) { mism = mism + 1; }
    t = t + 1;
  }
  return mism;
}

fn main() -> Int {
  io.println("=== xvector probe: kill-recovery acceptance (prefix exactness) ===");
  var fails: Int = 0;
  var dim: Int = 4;

  // Scripted write log: create, 20 upserts, 5 payload sets, 3 deletes,
  // set_index(Hnsw), 10 upserts (some updates), 3 payload sets, 2 deletes,
  // one final upsert (for the torn-tail check).
  var eng = engine_new();
  var s: Int = 918273;
  create_collection(&mut eng, dim, DistanceMetric.Cosine);
  var i: Int = 1;
  while i <= 20 {
    var c = Vec[Float32].new();
    s = rand_coords(s, dim, &mut c);
    upsert(&mut eng, i, vec_from_coords(&c));
    i = i + 1;
  }
  i = 1;
  while i <= 5 {
    var p = payload_new();
    payload_set(&mut p, "bucket", FieldValue.IntVal(i % 3));
    set_payload(&mut eng, i, p);
    i = i + 1;
  }
  delete_point(&mut eng, 2);
  delete_point(&mut eng, 5);
  delete_point(&mut eng, 9);
  set_index(&mut eng, AnnIndexKind.Hnsw, ann_params_default());
  i = 1;
  while i <= 10 {
    var c = Vec[Float32].new();
    s = rand_coords(s, dim, &mut c);
    upsert(&mut eng, i, vec_from_coords(&c));
    i = i + 1;
  }
  i = 11;
  while i <= 13 {
    var p = payload_new();
    payload_set(&mut p, "bucket", FieldValue.IntVal(1));
    set_payload(&mut eng, i, p);
    i = i + 1;
  }
  delete_point(&mut eng, 21);
  delete_point(&mut eng, 22);
  var cf = Vec[Float32].new();
  s = rand_coords(s, dim, &mut cf);
  upsert(&mut eng, 99, vec_from_coords(&cf));

  var nrec: Int = eng.wal.records.len();
  io.println("    diag scripted log records=" + int_to_str(nrec));
  var mism = prefix_exactness(&eng.wal, dim, DistanceMetric.Cosine);
  fails = check(mism == 0, "scripted WAL: every prefix recovers exactly (mismatches=0)", fails);

  // Full recovery equals the live engine (store/payloads/config).
  var rec = engine_recover(&eng.wal, dim, DistanceMetric.Cosine);
  fails = check(same_state(&eng, &rec, true)
    && rec.index_kind == AnnIndexKind.Hnsw,
    "full recovery equals the live engine (state + Hnsw config)", fails);

  // The compacted checkpoint log keeps the same property.
  var cmism = prefix_exactness(&rec.wal, dim, DistanceMetric.Cosine);
  io.println("    diag checkpoint log records=" + int_to_str(rec.wal.records.len()));
  fails = check(cmism == 0, "checkpoint WAL: every prefix recovers exactly (mismatches=0)", fails);

  // Empty log: caller config, Flat, empty state.
  var empty = wal_writer_new();
  var erec = engine_recover(&empty, dim, DistanceMetric.Cosine);
  fails = check(engine_size(&erec) == 0 && erec.index_kind == AnnIndexKind.Flat
    && erec.dimension == dim,
    "empty log -> empty Flat engine with caller config", fails);

  // Torn tail: a corrupt final record must recover as the prefix without it.
  var tcopy = prefix_writer(&eng.wal, nrec);
  tcopy.records[nrec - 1].payload = Vec[Int].new();
  var trec = engine_recover(&tcopy, dim, DistanceMetric.Cosine);
  var pfull = prefix_writer(&eng.wal, nrec - 1);
  var pexp = engine_recover(&pfull, dim, DistanceMetric.Cosine);
  fails = check(same_state(&trec, &pexp, true),
    "corrupt last record recovers as the surviving prefix", fails);

  io.println("");
  io.println("probe_kill_recovery: " + int_to_str(fails) + " failed checks");
  return fails;
}
