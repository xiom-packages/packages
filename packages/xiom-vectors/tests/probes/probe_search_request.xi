// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: SearchRequest-driven search + with_payload hydration on the REAL
// modules (facade `search_with_request` -> engine.core.engine_search_request
// -> search_service.search_knn/filtered + hydrate_hits). Separate compilation
// unit from the conformance suite. Exit code = number of failed checks.

module probe_search_request

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.query.search_request;
use xiom.vector.query.search_service;
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

fn f32_approx(a: Float32, b: Float32, eps: Float32) -> Bool {
  var diff = a - b;
  if diff < 0.0 { diff = -diff; }
  return diff < eps;
}

// Field-value comparators take the value BY VALUE (XVC-GEP note: copy out of
// Option/match bindings before taking references).
fn val_is_text(v: FieldValue, want: Str) -> Bool {
  var w = FieldValue.TextVal(want);
  return field_value_eq(&v, &w);
}

fn val_is_int(v: FieldValue, want: Int) -> Bool {
  var w = FieldValue.IntVal(want);
  return field_value_eq(&v, &w);
}

fn hit_index(items: &Vec[SearchHit], id: Int) -> Int {
  var i: Int = 0;
  while i < items.len() {
    if items[i].id == id { return i; }
    i = i + 1;
  }
  return -1;
}

fn main() -> Int {
  io.println("=== xvector probe: SearchRequest + with_payload hydration ===");
  var fails: Int = 0;

  var eng = engine_new();
  create_collection(&mut eng, 3, DistanceMetric.Cosine);
  upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  upsert(&mut eng, 2, mk_vec3(0.9, 0.1, 0.0));
  upsert(&mut eng, 3, mk_vec3(0.0, 0.0, 1.0));
  upsert(&mut eng, 4, mk_vec3(0.0, 1.0, 0.0));

  var p1 = payload_new();
  payload_set(&mut p1, "color", FieldValue.TextVal("red"));
  payload_set(&mut p1, "stock", FieldValue.IntVal(7));
  payload_set(&mut p1, "active", FieldValue.BoolVal(true));
  var p2 = payload_new();
  payload_set(&mut p2, "color", FieldValue.TextVal("blue"));
  var p3 = payload_new();
  payload_set(&mut p3, "color", FieldValue.TextVal("red"));
  payload_set(&mut p3, "stock", FieldValue.IntVal(9));
  var sets_ok: Bool = true;
  match set_payload(&mut eng, 1, p1) { Ok(a) => { sets_ok = sets_ok && a; } Err(_) => { sets_ok = false; } }
  match set_payload(&mut eng, 2, p2) { Ok(b) => { sets_ok = sets_ok && b; } Err(_) => { sets_ok = false; } }
  match set_payload(&mut eng, 3, p3) { Ok(c) => { sets_ok = sets_ok && c; } Err(_) => { sets_ok = false; } }
  fails = check(sets_ok, "setup: payloads on points 1-3", fails);

  // 1. Plain request, hydration ON: every hit carries its payload (point 4
  //    has none -> has_payload=false).
  var req1 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 10, DistanceMetric.Cosine);
  search_request_set_with_payload(&mut req1, true);
  match search_with_request(&eng, &req1) {
    Ok(h) => {
      var shape_ok: Bool = h.items.len() == 4 && h.items[0].id == 1
        && f32_approx(h.items[0].distance, 0.0, 0.001);
      fails = check(shape_ok, "request(no filter, k=10, hydrate): 4 hits, top=1 d~0", fails);

      var i1 = hit_index(&h.items, 1);
      var hp1 = payload_new();
      if i1 >= 0 && h.items[i1].has_payload { hp1 = h.items[i1].payload; }
      var c_ok: Bool = false; var s_ok: Bool = false; var a_ok: Bool = false;
      match payload_get(&hp1, "color") { Some(v) => { c_ok = val_is_text(v, "red"); } None => {} }
      match payload_get(&hp1, "stock") { Some(v) => { s_ok = val_is_int(v, 7); } None => {} }
      match payload_get(&hp1, "active") {
        Some(v) => { var w = FieldValue.BoolVal(true); a_ok = field_value_eq(&v, &w); }
        None => {}
      }
      fails = check(c_ok && s_ok && a_ok, "hydrated hit 1 carries color/stock/active", fails);

      var i2 = hit_index(&h.items, 2);
      var hp2 = payload_new();
      if i2 >= 0 && h.items[i2].has_payload { hp2 = h.items[i2].payload; }
      var blue_ok: Bool = false;
      match payload_get(&hp2, "color") { Some(v) => { blue_ok = val_is_text(v, "blue"); } None => {} }
      fails = check(blue_ok, "hydrated hit 2 carries color=blue", fails);

      var i4 = hit_index(&h.items, 4);
      var i4_ok: Bool = i4 >= 0 && !h.items[i4].has_payload;
      fails = check(i4_ok, "hit 4 (no payload): has_payload=false", fails);
    }
    Err(_) => { fails = check(false, "request(no filter, hydrate) -> Ok", fails); }
  }

  // 2. Filtered request, hydration OFF: payloads exist but are not attached.
  var req2 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 10, DistanceMetric.Cosine);
  search_request_set_filter(&mut req2, filter_eq("color", FieldValue.TextVal("red")));
  match search_with_request(&eng, &req2) {
    Ok(h) => {
      var red_ok: Bool = h.items.len() == 2 && h.items[0].id == 1 && h.items[1].id == 3
        && !h.items[0].has_payload;
      fails = check(red_ok, "request(Eq color=red, no hydrate) -> {1,3}, payload detached", fails);
    }
    Err(_) => { fails = check(false, "request(Eq color=red) -> Ok", fails); }
  }

  // 3. Range filter request with hydration: stock 8..10 -> {3} with stock=9.
  var req3 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 10, DistanceMetric.Cosine);
  search_request_set_filter(&mut req3, filter_range("stock", 8.0, 10.0));
  search_request_set_with_payload(&mut req3, true);
  match search_with_request(&eng, &req3) {
    Ok(h) => {
      var r_ok: Bool = h.items.len() == 1 && h.items[0].id == 3 && h.items[0].has_payload;
      var stock_ok: Bool = false;
      if h.items.len() == 1 && h.items[0].has_payload {
        var hp = h.items[0].payload;
        match payload_get(&hp, "stock") { Some(v) => { stock_ok = val_is_int(v, 9); } None => {} }
      }
      fails = check(r_ok && stock_ok, "request(Range stock 8..10, hydrate) -> {3} stock=9", fails);
    }
    Err(_) => { fails = check(false, "request(Range stock 8..10) -> Ok", fails); }
  }

  // 4. top_k bound through the request.
  var req4 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 1, DistanceMetric.Cosine);
  match search_with_request(&eng, &req4) {
    Ok(h) => {
      fails = check(h.items.len() == 1 && h.items[0].id == 1, "request(k=1) -> exactly {1}", fails);
    }
    Err(_) => { fails = check(false, "request(k=1) -> Ok", fails); }
  }

  // 5. Request metric must match the active collection.
  var req5 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 5, DistanceMetric.Euclidean);
  match search_with_request(&eng, &req5) {
    Ok(_) => { fails = check(false, "request(metric=Euclidean on Cosine) -> Err", fails); }
    Err(_) => { fails = check(true, "request(metric=Euclidean on Cosine) -> Err", fails); }
  }

  // 6. Dimension mismatch rejected before any search.
  var q2 = Vector.new(2);
  q2.set(0, 1.0); q2.set(1, 0.0);
  var req6 = search_request_new(q2, 5, DistanceMetric.Cosine);
  match search_with_request(&eng, &req6) {
    Ok(_) => { fails = check(false, "request(dim=2 on dim=3) -> Err", fails); }
    Err(_) => { fails = check(true, "request(dim=2 on dim=3) -> Err", fails); }
  }

  // ---- M-Q6 extensions: mode / pagination / batch ----

  // 7. Range mode: d1=0, d2~0.006, d3=d4=1.0 (orthogonal).
  var rq1 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 10, DistanceMetric.Cosine);
  search_request_set_range(&mut rq1, 0.5);
  match search_with_request(&eng, &rq1) {
    Ok(h) => { fails = check(h.items.len() == 2 && h.items[0].id == 1 && h.items[1].id == 2,
      "range mode: radius 0.5 -> {1,2}", fails); }
    Err(_) => { fails = check(false, "range mode(0.5) -> Ok", fails); }
  }
  var rq2 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 10, DistanceMetric.Cosine);
  search_request_set_range(&mut rq2, 1.0);
  search_request_set_with_payload(&mut rq2, true);
  match search_with_request(&eng, &rq2) {
    Ok(h) => {
      var i1r = hit_index(&h.items, 1);
      fails = check(h.items.len() == 4 && i1r >= 0 && h.items[i1r].has_payload,
        "range mode: radius 1.0 inclusive -> 4 hits, hydrated", fails);
    }
    Err(_) => { fails = check(false, "range mode(1.0) -> Ok", fails); }
  }
  var rq3 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 5, DistanceMetric.Cosine);
  search_request_set_range(&mut rq3, -1.0);
  match search_with_request(&eng, &rq3) {
    Ok(_) => { fails = check(false, "range mode: negative radius -> Err", fails); }
    Err(_) => { fails = check(true, "range mode: negative radius -> Err", fails); }
  }
  var rq4 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 5, DistanceMetric.Cosine);
  search_request_set_range(&mut rq4, 1.0);
  search_request_set_filter(&mut rq4, filter_eq("color", FieldValue.TextVal("red")));
  match search_with_request(&eng, &rq4) {
    Ok(_) => { fails = check(false, "range mode + filter -> Err", fails); }
    Err(_) => { fails = check(true, "range mode + filter -> Err", fails); }
  }
  var rq5 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 5, DistanceMetric.Cosine);
  search_request_set_range(&mut rq5, 1.0);
  search_request_set_page(&mut rq5, 1);
  match search_with_request(&eng, &rq5) {
    Ok(_) => { fails = check(false, "range mode + pagination -> Err", fails); }
    Err(_) => { fails = check(true, "range mode + pagination -> Err", fails); }
  }

  // 8. Offset pagination through the request matches the page kernel.
  var pref = Vec[Int].new();
  match search_page(&eng, &mk_vec3(1.0, 0.0, 0.0), 2, 1) {
    Ok(h) => { var i = 0; while i < h.items.len() { pref.push(h.items[i].id); i = i + 1; } }
    Err(_) => {}
  }
  var pq1 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 2, DistanceMetric.Cosine);
  search_request_set_page(&mut pq1, 1);
  var pq_ids = Vec[Int].new();
  match search_with_request(&eng, &pq1) {
    Ok(h) => { var i = 0; while i < h.items.len() { pq_ids.push(h.items[i].id); i = i + 1; } }
    Err(_) => {}
  }
  var pq_ok: Bool = pq_ids.len() == pref.len() && pq_ids.len() == 2;
  if pq_ok {
    var i = 0;
    while i < pq_ids.len() {
      if pq_ids[i] != pref[i] { pq_ok = false; }
      i = i + 1;
    }
  }
  fails = check(pq_ok, "page mode: request offset matches search_page ranks", fails);

  // 9. After-id cursor through the request matches the cursor kernel.
  var aref = Vec[Int].new();
  match search_after(&eng, &mk_vec3(1.0, 0.0, 0.0), 3, 1) {
    Ok(h) => { var i = 0; while i < h.items.len() { aref.push(h.items[i].id); i = i + 1; } }
    Err(_) => {}
  }
  var aq1 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 3, DistanceMetric.Cosine);
  search_request_set_after(&mut aq1, 1);
  var aq_ids = Vec[Int].new();
  match search_with_request(&eng, &aq1) {
    Ok(h) => { var i = 0; while i < h.items.len() { aq_ids.push(h.items[i].id); i = i + 1; } }
    Err(_) => {}
  }
  var aq_ok: Bool = aq_ids.len() == aref.len() && aq_ids.len() == 3;
  if aq_ok {
    var i = 0;
    while i < aq_ids.len() {
      if aq_ids[i] != aref[i] { aq_ok = false; }
      i = i + 1;
    }
  }
  fails = check(aq_ok, "cursor mode: request after_id matches search_after", fails);

  var aq2 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 3, DistanceMetric.Cosine);
  search_request_set_after(&mut aq2, 999);
  match search_with_request(&eng, &aq2) {
    Ok(_) => { fails = check(false, "cursor mode: unknown after_id -> Err", fails); }
    Err(_) => { fails = check(true, "cursor mode: unknown after_id -> Err", fails); }
  }
  var xq1 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 3, DistanceMetric.Cosine);
  search_request_set_page(&mut xq1, 1);
  search_request_set_after(&mut xq1, 1);
  match search_with_request(&eng, &xq1) {
    Ok(_) => { fails = check(false, "page + after_id -> Err (mutually exclusive)", fails); }
    Err(_) => { fails = check(true, "page + after_id -> Err (mutually exclusive)", fails); }
  }
  var xq2 = search_request_new(mk_vec3(1.0, 0.0, 0.0), 3, DistanceMetric.Cosine);
  search_request_set_page(&mut xq2, 1);
  search_request_set_filter(&mut xq2, filter_eq("color", FieldValue.TextVal("red")));
  match search_with_request(&eng, &xq2) {
    Ok(_) => { fails = check(false, "pagination + filter -> Err", fails); }
    Err(_) => { fails = check(true, "pagination + filter -> Err", fails); }
  }

  // 10. Batch requests: one set per request, order preserved.
  var batch1 = search_batch_request_new();
  search_batch_request_add(&mut batch1, search_request_new(mk_vec3(1.0, 0.0, 0.0), 1, DistanceMetric.Cosine));
  var bred = search_request_new(mk_vec3(1.0, 0.0, 0.0), 10, DistanceMetric.Cosine);
  search_request_set_filter(&mut bred, filter_eq("color", FieldValue.TextVal("red")));
  search_batch_request_add(&mut batch1, bred);
  fails = check(search_batch_request_len(&batch1) == 2, "batch: two requests registered", fails);
  match search_batch_with_request(&eng, &batch1) {
    Ok(b) => {
      var ok0: Bool = b.sets.len() == 2 && b.sets[0].items.len() == 1 && b.sets[0].items[0].id == 1;
      var ok1: Bool = b.sets.len() == 2 && b.sets[1].items.len() == 2
        && b.sets[1].items[0].id == 1 && b.sets[1].items[1].id == 3;
      fails = check(ok0 && ok1, "batch: sets (plain k=1 {1}, red {1,3}) in order", fails);
    }
    Err(_) => { fails = check(false, "batch(2 requests) -> Ok", fails); }
  }
  var bempty = search_batch_request_new();
  match search_batch_with_request(&eng, &bempty) {
    Ok(_) => { fails = check(false, "batch: empty -> Err", fails); }
    Err(_) => { fails = check(true, "batch: empty -> Err", fails); }
  }
  var bbad = search_batch_request_new();
  search_batch_request_add(&mut bbad, search_request_new(mk_vec3(1.0, 0.0, 0.0), 1, DistanceMetric.Euclidean));
  match search_batch_with_request(&eng, &bbad) {
    Ok(_) => { fails = check(false, "batch: failing request aborts (metric mismatch)", fails); }
    Err(_) => { fails = check(true, "batch: failing request aborts (metric mismatch)", fails); }
  }

  io.println("");
  io.println("probe_search_request: " + int_to_str(fails) + " failed checks");
  return fails;
}
