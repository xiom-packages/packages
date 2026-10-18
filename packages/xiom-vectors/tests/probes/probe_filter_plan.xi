// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: selectivity-based pre/post-filter planner on the REAL modules.
// Verifies (a) exact estimates from the payload index, (b) plan choice for
// known/unknown/low/high selectivity, (c) result equivalence with a local
// pre-filter scan reference across filter shapes, including the post-plan
// fallback when the nearest points do not match. Exit = failed checks.

module probe_filter_plan

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.query.filter_plan;
use xiom.vector.query.search_service;
use xiom.vector.storage.vector_store;
use xiom.vectors;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vector.payload.filter_eval;
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

fn mk_vec2(a: Float32, b: Float32) -> Vector {
  var v = Vector.new(2);
  v.set(0, a); v.set(1, b);
  return v;
}

// Local pre-filter scan reference (same semantics as the engine's fallback).
fn results_push_bounded(results: &mut Vec[SearchResult], item: SearchResult, k: Int) {
  results.push(item);
  var pos: Int = results.len() - 1;
  while pos > 0 && results[pos - 1].distance > results[pos].distance {
    var tmp = results[pos];
    results[pos] = results[pos - 1];
    results[pos - 1] = tmp;
    pos = pos - 1;
  }
  if results.len() > k {
    results.pop();
  }
}

fn reference_filtered(idx: &VectorIndex, payloads: &PayloadStore, query: &Vector, k: Int, metric: DistanceMetric, filter: &FilterExpr) -> Vec[SearchResult] {
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  while i < idx.ids.len() {
    if payload_store_matches(payloads, idx.ids[i], filter) {
      var dist = vector_distance(&idx.vectors[i], query, metric);
      results_push_bounded(&mut results, SearchResult{ id: idx.ids[i], distance: dist }, k);
    }
    i = i + 1;
  }
  return results;
}

fn results_equal(a: &Vec[SearchResult], b: &Vec[SearchResult]) -> Bool {
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
  io.println("=== xvector probe: pre/post filter planner ===");
  var fails: Int = 0;

  var eng = engine_new();
  create_collection(&mut eng, 2, DistanceMetric.Euclidean);
  var i: Int = 1;
  while i <= 12 {
    upsert(&mut eng, i, mk_vec2(i as Float32, 0.0));
    i = i + 1;
  }
  i = 1;
  while i <= 10 {
    var p = payload_new();
    payload_set(&mut p, "common", FieldValue.BoolVal(true));
    payload_set(&mut p, "bucket", FieldValue.TextVal("a"));
    payload_set(&mut p, "rank", FieldValue.IntVal(i));
    set_payload(&mut eng, i, p);
    i = i + 1;
  }
  var p11 = payload_new();
  payload_set(&mut p11, "bucket", FieldValue.TextVal("b"));
  payload_set(&mut p11, "rank", FieldValue.IntVal(11));
  set_payload(&mut eng, 11, p11);
  // id 12 stays without payload.

  var query = mk_vec2(0.0, 0.0);

  // --- estimates (index counts) ---
  var f_exists = filter_exists("common");
  var f_a = filter_eq("bucket", FieldValue.TextVal("a"));
  var f_b = filter_eq("bucket", FieldValue.TextVal("b"));
  var f_range = filter_range("rank", 3.0, 5.0);
  var f_and = filter_and(Vec[FilterExpr].new());
  var vals = Vec[FieldValue].new();
  vals.push(FieldValue.IntVal(1));
  var f_in = filter_in("rank", vals);
  fails = check(filter_matching_count(&eng.payloads, &f_exists) == 10
    && filter_matching_count(&eng.payloads, &f_a) == 10
    && filter_matching_count(&eng.payloads, &f_b) == 1
    && filter_matching_count(&eng.payloads, &f_range) == 3,
    "estimates exact: exists=10 eq-a=10 eq-b=1 range=3", fails);
  fails = check(filter_matching_count(&eng.payloads, &f_and) == -1
    && filter_matching_count(&eng.payloads, &f_in) == -1,
    "estimates unknown for And/In (-1)", fails);

  // --- plan choice ---
  fails = check(choose_filter_plan(&eng.payloads, &f_exists, 12, 3) == filter_plan_post()
    && choose_filter_plan(&eng.payloads, &f_a, 12, 3) == filter_plan_post(),
    "plan: majority exists/eq-a -> post", fails);
  fails = check(choose_filter_plan(&eng.payloads, &f_b, 12, 3) == filter_plan_index()
    && choose_filter_plan(&eng.payloads, &f_a, 12, 20) == filter_plan_scan(),
    "plan: eq-b (1/12) -> index; eq-a k20 -> scan", fails);
  fails = check(choose_filter_plan(&eng.payloads, &f_range, 12, 3) == filter_plan_scan()
    && choose_filter_plan(&eng.payloads, &f_in, 12, 3) == filter_plan_scan(),
    "plan: range minority / In unknown -> scan", fails);
  fails = check(choose_filter_plan(&eng.payloads, &f_and, 12, 3) == filter_plan_post(),
    "plan: And([]) match-all (upper=total) -> post", fails);

  // --- equivalence with the scan reference (facade path) ---
  var k: Int = 3;
  match search_filtered(&eng, &query, k, &f_exists) {
    Ok(h) => {
      var ref = reference_filtered(&eng.store, &eng.payloads, &query, k, DistanceMetric.Euclidean, &f_exists);
      fails = check(results_equal(&h.items, &ref), "post path: Exists majority == scan", fails);
      fails = check(h.items.len() == 3 && h.items[0].id == 1, "post path fills k (=3), nearest match 1", fails);
    }
    Err(_) => { fails = check(false, "search Exists -> Ok", fails); }
  }
  match search_filtered(&eng, &query, k, &f_a) {
    Ok(h) => {
      var ref = reference_filtered(&eng.store, &eng.payloads, &query, k, DistanceMetric.Euclidean, &f_a);
      fails = check(results_equal(&h.items, &ref), "post path: Eq majority == scan", fails);
    }
    Err(_) => { fails = check(false, "search Eq-a -> Ok", fails); }
  }
  match search_filtered(&eng, &query, k, &f_b) {
    Ok(h) => {
      var ref = reference_filtered(&eng.store, &eng.payloads, &query, k, DistanceMetric.Euclidean, &f_b);
      fails = check(results_equal(&h.items, &ref) && h.items.len() == 1 && h.items[0].id == 11,
        "index plan: Eq minority (bucket b) -> {11}", fails);
    }
    Err(_) => { fails = check(false, "search Eq-b -> Ok", fails); }
  }
  match search_filtered(&eng, &query, k, &f_range) {
    Ok(h) => {
      var ref = reference_filtered(&eng.store, &eng.payloads, &query, k, DistanceMetric.Euclidean, &f_range);
      fails = check(results_equal(&h.items, &ref) && h.items[0].id == 3 && h.items[1].id == 4 && h.items[2].id == 5,
        "scan path: Range == scan -> {3,4,5}", fails);
    }
    Err(_) => { fails = check(false, "search Range -> Ok", fails); }
  }

  // Boolean/no-payload shapes (unknown selectivity -> scan) still match.
  var and_clauses = Vec[FilterExpr].new();
  and_clauses.push(filter_eq("common", FieldValue.BoolVal(true)));
  and_clauses.push(filter_range("rank", 8.0, 10.0));
  var f_and3 = filter_and(and_clauses);
  match search_filtered(&eng, &query, k, &f_and3) {
    Ok(h) => {
      var ref = reference_filtered(&eng.store, &eng.payloads, &query, k, DistanceMetric.Euclidean, &f_and3);
      fails = check(results_equal(&h.items, &ref) && h.items[0].id == 8, "And(common,rank 8..10) == scan", fails);
    }
    Err(_) => { fails = check(false, "search And -> Ok", fails); }
  }
  var or_clauses = Vec[FilterExpr].new();
  or_clauses.push(filter_eq("bucket", FieldValue.TextVal("b")));
  or_clauses.push(filter_eq("bucket", FieldValue.TextVal("c")));
  var f_or = filter_or(or_clauses);
  match search_filtered(&eng, &query, k, &f_or) {
    Ok(h) => {
      var ref = reference_filtered(&eng.store, &eng.payloads, &query, k, DistanceMetric.Euclidean, &f_or);
      fails = check(results_equal(&h.items, &ref) && h.items.len() == 1 && h.items[0].id == 11, "Or(b,c) == scan -> {11}", fails);
    }
    Err(_) => { fails = check(false, "search Or -> Ok", fails); }
  }
  var f_not = filter_not(filter_eq("bucket", FieldValue.TextVal("a")));
  match search_filtered(&eng, &query, k, &f_not) {
    Ok(h) => {
      var ref = reference_filtered(&eng.store, &eng.payloads, &query, k, DistanceMetric.Euclidean, &f_not);
      fails = check(results_equal(&h.items, &ref) && h.items.len() == 2 && h.items[0].id == 11 && h.items[1].id == 12,
        "Not(a) == scan -> {11,12} (no-payload matches)", fails);
    }
    Err(_) => { fails = check(false, "search Not -> Ok", fails); }
  }
  var f_zero = filter_eq("bucket", FieldValue.TextVal("zzz"));
  match search_filtered(&eng, &query, k, &f_zero) {
    Ok(h) => {
      fails = check(h.items.len() == 0 && filter_matching_count(&eng.payloads, &f_zero) == 0,
        "Eq no match: count 0, empty result", fails);
    }
    Err(_) => { fails = check(false, "search zero -> Ok", fails); }
  }

  // --- upper bounds for compound shapes ---
  fails = check(filter_matching_upper(&eng.payloads, &f_and3, 12) == 3
    && filter_matching_upper(&eng.payloads, &f_or, 12) == 1
    && filter_matching_upper(&eng.payloads, &f_not, 12) == 2
    && filter_matching_upper(&eng.payloads, &f_in, 12) == -1,
    "upper bounds: And(common,rank)=3 Or(b,c)=1 Not=2 In=-1", fails);

  // --- index plan: exact candidates, bit-identical to the scan reference ---
  var p2r = payload_new();
  payload_set(&mut p2r, "rare", FieldValue.BoolVal(true));
  set_payload(&mut eng, 2, p2r);
  var p5r = payload_new();
  payload_set(&mut p5r, "rare", FieldValue.BoolVal(true));
  set_payload(&mut eng, 5, p5r);
  var f_rare = filter_exists("rare");
  fails = check(filter_matching_count(&eng.payloads, &f_rare) == 2
    && choose_filter_plan(&eng.payloads, &f_rare, 12, 3) == filter_plan_index(),
    "index plan: Exists rare (2/12) -> index", fails);
  match search_filtered(&eng, &query, k, &f_rare) {
    Ok(h) => {
      var ref = reference_filtered(&eng.store, &eng.payloads, &query, k, DistanceMetric.Euclidean, &f_rare);
      fails = check(results_equal(&h.items, &ref) && h.items.len() == 2
        && h.items[0].id == 2 && h.items[1].id == 5,
        "index plan: candidates {2,5} bit-identical to reference", fails);
    }
    Err(_) => { fails = check(false, "index-plan search -> Ok", fails); }
  }

  // --- multi-key intersection (And of index-answerable clauses) ---
  i = 1;
  while i <= 8 {
    var pm = payload_new();
    payload_set(&mut pm, "grp", FieldValue.IntVal(i % 2));
    payload_set(&mut pm, "tier", FieldValue.IntVal(i % 4));
    set_payload(&mut eng, i, pm);
    i = i + 1;
  }
  var an_cl = Vec[FilterExpr].new();
  an_cl.push(filter_eq("grp", FieldValue.IntVal(1)));
  an_cl.push(filter_eq("tier", FieldValue.IntVal(1)));
  var f_an = filter_and(an_cl);
  fails = check(filter_matching_upper(&eng.payloads, &f_an, 12) == 2
    && filter_index_answerable(&f_an)
    && choose_filter_plan(&eng.payloads, &f_an, 12, 3) == filter_plan_index(),
    "multi-key: And(grp=1, tier=1) upper=2 -> index plan", fails);
  match search_filtered(&eng, &query, k, &f_an) {
    Ok(h) => {
      var ref = reference_filtered(&eng.store, &eng.payloads, &query, k, DistanceMetric.Euclidean, &f_an);
      fails = check(results_equal(&h.items, &ref) && h.items.len() == 2
        && h.items[0].id == 1 && h.items[1].id == 5,
        "multi-key: intersection {1,5} bit-identical to reference", fails);
    }
    Err(_) => { fails = check(false, "multi-key search -> Ok", fails); }
  }
  var an_cl2 = Vec[FilterExpr].new();
  an_cl2.push(filter_eq("grp", FieldValue.IntVal(1)));
  an_cl2.push(filter_eq("tier", FieldValue.IntVal(0)));
  var f_an2 = filter_and(an_cl2);
  match search_filtered(&eng, &query, k, &f_an2) {
    Ok(h) => {
      fails = check(h.items.len() == 0
        && choose_filter_plan(&eng.payloads, &f_an2, 12, 3) == filter_plan_index(),
        "multi-key: disjoint And -> index plan, empty result", fails);
    }
    Err(_) => { fails = check(false, "multi-key disjoint -> Ok", fails); }
  }

  // --- post plan fallback: majority matches, but the nearest k do not ---
  i = 4;
  while i <= 12 {
    var pf = payload_new();
    payload_set(&mut pf, "far", FieldValue.BoolVal(true));
    set_payload(&mut eng, i, pf);
    i = i + 1;
  }
  var f_far = filter_exists("far");
  fails = check(filter_matching_count(&eng.payloads, &f_far) == 9
    && choose_filter_plan(&eng.payloads, &f_far, 12, 3) == filter_plan_post(),
    "fallback setup: far est 9 -> post plan", fails);
  match search_filtered(&eng, &query, k, &f_far) {
    Ok(h) => {
      var ref = reference_filtered(&eng.store, &eng.payloads, &query, k, DistanceMetric.Euclidean, &f_far);
      fails = check(results_equal(&h.items, &ref) && h.items[0].id == 4 && h.items[1].id == 5 && h.items[2].id == 6,
        "fallback: nearest 1-3 unmatched -> scan {4,5,6}", fails);
    }
    Err(_) => { fails = check(false, "search far -> Ok", fails); }
  }

  io.println("");
  io.println("probe_filter_plan: " + int_to_str(fails) + " failed checks");
  return fails;
}
