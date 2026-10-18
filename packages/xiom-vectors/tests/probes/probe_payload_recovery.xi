// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: durable metadata (payloads) through WAL replay + compacted
// checkpoint (separate compilation unit; IntVal/TextVal/BoolVal gating per
// XVC-C-06, FloatVal diagnostic-only). Exit code = failed checks.

module probe_payload_recovery

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vectors;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
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

fn mk_vec3(a: Float32, b: Float32, c: Float32) -> Vector {
  var v = Vector.new(3);
  v.set(0, a); v.set(1, b); v.set(2, c);
  return v;
}

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

// Field-value comparators take the value BY VALUE (no `&Payload` helper
// parameters -- see the XVC-GEP note in main).
fn val_is_text(v: FieldValue, want: Str) -> Bool {
  var w = FieldValue.TextVal(want);
  return field_value_eq(&v, &w);
}

fn val_is_int(v: FieldValue, want: Int) -> Bool {
  var w = FieldValue.IntVal(want);
  return field_value_eq(&v, &w);
}

fn val_is_bool(v: FieldValue, want: Bool) -> Bool {
  var w = FieldValue.BoolVal(want);
  return field_value_eq(&v, &w);
}


fn main() -> Int {
  io.println("=== xvector probe: durable payloads (recovery + checkpoint) ===");
  var fails: Int = 0;

  var eng = engine_new();
  create_collection(&mut eng, 3, DistanceMetric.Cosine);
  let lsn_after_create = engine_durable_lsn(&eng);
  upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  upsert(&mut eng, 2, mk_vec3(0.9, 0.1, 0.0));
  upsert(&mut eng, 3, mk_vec3(0.0, 0.0, 1.0));

  var p1 = payload_new();
  payload_set(&mut p1, "color", FieldValue.TextVal("red"));
  payload_set(&mut p1, "stock", FieldValue.IntVal(7));
  payload_set(&mut p1, "active", FieldValue.BoolVal(true));
  set_payload(&mut eng, 1, p1);
  var p2 = payload_new();
  payload_set(&mut p2, "color", FieldValue.TextVal("blue"));
  payload_set(&mut p2, "note", FieldValue.TextVal("hello world"));
  set_payload(&mut eng, 2, p2);
  let lsn_after_sets = engine_durable_lsn(&eng);
  // create_collection also logs the collection manifest, so count relative
  // to the post-create LSN captured above (manifest + 3 upserts + 2 sets).
  fails = check(lsn_after_sets == lsn_after_create + 5,
    "WAL-before-ack: manifest + 3 upserts + 2 payload records (lsn=create+5)", fails);

  // First reopen: payloads restored from the WAL.
  // NOTE: payloads are copied out of the Option into plain locals before any
  // `&Payload` helper call -- passing a match-bound payload reference hit a
  // v0.64.0 codegen bug (invalid getelementptr; docs/repro/xv-gep-vec-doubleptr).
  var r1 = engine_recover(&eng.wal, 3, DistanceMetric.Cosine);
  var pl1 = payload_new();
  var have1: Bool = false;
  match get_payload(&r1, 1) {
    Some(p) => { pl1 = p; have1 = true; }
    None => {}
  }
  var ok1: Bool = false;
  if have1 {
    var c_ok: Bool = false;
    var s_ok: Bool = false;
    var a_ok: Bool = false;
    match payload_get(&pl1, "color") { Some(v) => { c_ok = val_is_text(v, "red"); } None => {} }
    match payload_get(&pl1, "stock") { Some(v) => { s_ok = val_is_int(v, 7); } None => {} }
    match payload_get(&pl1, "active") { Some(v) => { a_ok = val_is_bool(v, true); } None => {} }
    ok1 = c_ok && s_ok && a_ok;
  }
  fails = check(ok1, "reopen: point 1 payload (text/int/bool) restored", fails);

  var pl2 = payload_new();
  var have2: Bool = false;
  match get_payload(&r1, 2) {
    Some(p) => { pl2 = p; have2 = true; }
    None => {}
  }
  var ok2: Bool = false;
  if have2 {
    match payload_get(&pl2, "note") { Some(v) => { ok2 = val_is_text(v, "hello world"); } None => {} }
  }
  fails = check(ok2, "reopen: point 2 text payload restored", fails);
  var ok3: Bool = false;
  match get_payload(&r1, 3) { Some(_) => {} None => { ok3 = true; } }
  fails = check(ok3, "reopen: point 3 (no payload) stays empty", fails);

  // Overwrite metadata, then a chained reopen (checkpoint log carries it).
  var p1b = payload_new();
  payload_set(&mut p1b, "color", FieldValue.TextVal("green"));
  payload_set(&mut p1b, "stock", FieldValue.IntVal(9));
  set_payload(&mut r1, 1, p1b);
  var r2 = engine_recover(&r1.wal, 3, DistanceMetric.Cosine);
  var pl3 = payload_new();
  var have3: Bool = false;
  match get_payload(&r2, 1) {
    Some(p) => { pl3 = p; have3 = true; }
    None => {}
  }
  var ok4: Bool = false;
  if have3 {
    var c_ok2: Bool = false;
    var s_ok2: Bool = false;
    match payload_get(&pl3, "color") { Some(v) => { c_ok2 = val_is_text(v, "green"); } None => {} }
    match payload_get(&pl3, "stock") { Some(v) => { s_ok2 = val_is_int(v, 9); } None => {} }
    ok4 = c_ok2 && s_ok2;
  }
  fails = check(ok4, "chained reopen: overwritten payload is the latest", fails);

  // Delete clears metadata through recovery.
  delete_point(&mut r2, 2);
  var r3 = engine_recover(&r2.wal, 3, DistanceMetric.Cosine);
  var gone: Bool = true;
  match get_payload(&r3, 2) { Some(_) => { gone = false; } None => {} }
  fails = check(gone, "chained reopen: delete cleared point 2 payload", fails);

  // Filtered search on the recovered engine.
  var q = mk_vec3(1.0, 0.0, 0.0);
  var f = filter_eq("color", FieldValue.TextVal("green"));
  var hits_ok: Bool = false;
  match search_filtered(&r3, &q, 5, &f) {
    Ok(h) => { hits_ok = h.items.len() == 1 && h.items[0].id == 1; }
    Err(_) => {}
  }
  fails = check(hits_ok, "recovered engine: filtered search -> {1}", fails);

  // FloatVal roundtrip diagnostic (non-gating, XVC-C-06).
  var pf = payload_new();
  payload_set(&mut pf, "price", FieldValue.FloatVal(2.5));
  set_payload(&mut r3, 3, pf);
  var r4 = engine_recover(&r3.wal, 3, DistanceMetric.Cosine);
  var pl4 = payload_new();
  var have4: Bool = false;
  match get_payload(&r4, 3) {
    Some(p) => { pl4 = p; have4 = true; }
    None => {}
  }
  var f_bits: Int = -1;
  if have4 {
    match payload_get(&pl4, "price") {
      Some(v) => {
        match v {
          FloatVal(x) => { f_bits = float.float_bits(x as Float64); }
          _ => {}
        }
      }
      None => {}
    }
  }
  io.println("    diag durable FloatVal(2.5) bits=" + int_to_str(f_bits) +
             " (expected " + int_to_str(float.float_bits(2.5)) + ")");
  fails = check(f_bits == float.float_bits(2.5), "durable FloatVal bit-exact through reopen", fails);

  io.println("");
  io.println("probe_payload_recovery: " + int_to_str(fails) + " failed checks");
  return fails;
}
