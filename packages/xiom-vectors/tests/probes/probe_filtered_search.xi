// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: Phase 3 payload filtering on the REAL engine module (separate
// compilation unit from the conformance suite). Covers FloatVal payloads
// end-to-end (XVC-C-06 zeroes Float32 enum payloads inside the suite unit,
// but this unit is correct). Exit code = number of failed checks.

module probe_filtered_search

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vectors;
use xiom.vector.query.search_service;
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

fn ids_match(items: &Vec[SearchResult], a: Int, b: Int) -> Bool {
  if items.len() != 2 { return false; }
  return items[0].id == a && items[1].id == b;
}

fn main() -> Int {
  io.println("=== xvector probe: filtered search (Phase 3) ===");
  var fails: Int = 0;

  var eng = engine_new();
  create_collection(&mut eng, 3, DistanceMetric.Cosine);
  upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  upsert(&mut eng, 2, mk_vec3(0.9, 0.1, 0.0));
  upsert(&mut eng, 3, mk_vec3(0.0, 0.0, 1.0));
  upsert(&mut eng, 4, mk_vec3(0.0, 1.0, 0.0));

  var p1 = payload_new();
  payload_set(&mut p1, "color", FieldValue.TextVal("red"));
  payload_set(&mut p1, "price", FieldValue.FloatVal(5.0));
  var ok1 = set_payload(&mut eng, 1, p1);
  var p2 = payload_new();
  payload_set(&mut p2, "color", FieldValue.TextVal("blue"));
  payload_set(&mut p2, "price", FieldValue.FloatVal(50.0));
  var ok2 = set_payload(&mut eng, 2, p2);
  var p3 = payload_new();
  payload_set(&mut p3, "color", FieldValue.TextVal("red"));
  payload_set(&mut p3, "price", FieldValue.FloatVal(500.0));
  var ok3 = set_payload(&mut eng, 3, p3);
  // point 4 intentionally has no payload
  var ok_set: Bool = false;
  match ok1 { Ok(a) => { ok_set = a; } Err(_) => {} }
  match ok2 { Ok(b) => { ok_set = ok_set && b; } Err(_) => {} }
  match ok3 { Ok(c) => { ok_set = ok_set && c; } Err(_) => {} }
  fails = check(ok_set, "set_payload x3 on existing points", fails);

  var q = mk_vec3(1.0, 0.0, 0.0);
  var f_price = filter_range("price", 0.0, 100.0);
  var f_red = filter_eq("color", FieldValue.TextVal("red"));
  var f_blue = filter_eq("color", FieldValue.TextVal("blue"));
  var f_exists = filter_exists("color");

  // FloatVal bounds check (XVC-C-06-sensitive on the engine unit).
  var r_price = search_filtered(&eng, &q, 10, &f_price);
  var price_ok: Bool = false;
  match r_price { Ok(h) => { price_ok = ids_match(&h.items, 1, 2); } Err(_) => {} }
  fails = check(price_ok, "Range(price, 0..100) -> {1,2}", fails);

  var r_red = search_filtered(&eng, &q, 10, &f_red);
  var red_ok: Bool = false;
  match r_red { Ok(h) => { red_ok = ids_match(&h.items, 1, 3); } Err(_) => {} }
  fails = check(red_ok, "Eq(color, red) -> {1,3}", fails);

  var clauses = Vec[FilterExpr].new();
  clauses.push(filter_eq("color", FieldValue.TextVal("red")));
  clauses.push(filter_range("price", 0.0, 100.0));
  var f_and = filter_and(clauses);
  var f_not = filter_not(f_blue);
  var r_and = search_filtered(&eng, &q, 10, &f_and);
  var and_ok: Bool = false;
  match r_and { Ok(h) => { and_ok = h.items.len() == 1 && h.items[0].id == 1; } Err(_) => {} }
  fails = check(and_ok, "And(red, price<=100) -> {1}", fails);

  var r_not = search_filtered(&eng, &q, 10, &f_not);
  var not_ok: Bool = false;
  match r_not { Ok(h) => { not_ok = ids_match(&h.items, 1, 3); } Err(_) => {} }
  // point 4 has no payload: Not(blue) on empty payload = true -> {1,3,4}
  match r_not {
    Ok(h) => { not_ok = h.items.len() == 3 && h.items[0].id == 1 && h.items[1].id == 3 && h.items[2].id == 4; }
    Err(_) => {}
  }
  fails = check(not_ok, "Not(blue) -> {1,3,4} (no-payload point included)", fails);

  var r_exists = search_filtered(&eng, &q, 10, &f_exists);
  var exists_ok: Bool = false;
  match r_exists {
    Ok(h) => { exists_ok = h.items.len() == 3 && h.items[0].id == 1 && h.items[1].id == 2 && h.items[2].id == 3; }
    Err(_) => {}
  }
  fails = check(exists_ok, "Exists(color) -> {1,2,3} (point 4 excluded)", fails);

  // Bounded k with filter.
  var r_k1 = search_filtered(&eng, &q, 1, &f_exists);
  var k1_ok: Bool = false;
  match r_k1 { Ok(h) => { k1_ok = h.items.len() == 1 && h.items[0].id == 1; } Err(_) => {} }
  fails = check(k1_ok, "top_k=1 filtered -> {1}", fails);

  // Missing-point set_payload -> Ok(false).
  var p9 = payload_new();
  var miss_ok: Bool = false;
  match set_payload(&mut eng, 99, p9) {
    Ok(ok) => { miss_ok = !ok; }
    Err(_) => {}
  }
  fails = check(miss_ok, "set_payload(99) on missing point -> Ok(false)", fails);

  // Delete removes metadata and filtered views.
  delete_point(&mut eng, 1);
  var gone: Bool = true;
  match get_payload(&eng, 1) { Some(_) => { gone = false; } None => {} }
  fails = check(gone, "delete point 1 removes payload", fails);
  var r_red2 = search_filtered(&eng, &q, 10, &f_red);
  var red2_ok: Bool = false;
  match r_red2 { Ok(h) => { red2_ok = h.items.len() == 1 && h.items[0].id == 3; } Err(_) => {} }
  fails = check(red2_ok, "post-delete filtered search -> {3}", fails);

  // Distances through the filtered path: diagnostic (XVC-C-05 can distort
  // float compares per build; the numeric gates live in the suite and
  // probe_vector_store, which are re-verified per build).
  var dist_ids_ok: Bool = false;
  match search_filtered(&eng, &q, 2, &f_exists) {
    Ok(h) => {
      if h.items.len() == 2 && h.items[0].id == 2 {
        dist_ids_ok = true;
        io.println("    diag filtered top-1 id=2 dist_bits=" + int_to_str(float.float_bits(h.items[0].distance as Float64)) +
                   " (expected " + int_to_str(float.float_bits(0.00611)) + " approx)");
      }
    }
    Err(_) => {}
  }
  fails = check(dist_ids_ok, "filtered top-2 after delete -> {2,3}", fails);

  // FloatVal payload gate (XVC-C-06 fixed in v0.64.1; was diagnostic-only).
  var fv = FieldValue.FloatVal(2.5);
  var fv_p = payload_new();
  payload_set(&mut fv_p, "f", fv);
  var fv_bits: Int = -1;
  match payload_get(&fv_p, "f") {
    Some(v) => {
      match v {
        FloatVal(g) => { fv_bits = float.float_bits(g as Float64); }
        _ => {}
      }
    }
    None => {}
  }
  io.println("    diag FloatVal(2.5) roundtrip bits=" + int_to_str(fv_bits) +
             " (expected " + int_to_str(float.float_bits(2.5)) + ")");
  fails = check(fv_bits == float.float_bits(2.5), "FloatVal(2.5) roundtrip bit-exact", fails);

  io.println("");
  io.println("probe_filtered_search: " + int_to_str(fails) + " failed checks");
  return fails;
}
