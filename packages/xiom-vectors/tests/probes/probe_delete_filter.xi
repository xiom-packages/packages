// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: delete-by-filter (M-Q4). Verifies planner-driven selective
// deletion -- index-answerable shapes (Eq/Range/Exists/And-of-those) and
// scan shapes (In/Or/Not) -- with per-point WAL records (lsn delta),
// graph tombstones (size retained, live count drops, compaction reclaims),
// payload/index cleanup, idempotence, match-nothing -> Ok(0), match-all,
// recovery durability (incl. chained), and multi-collection isolation.
// Exit = failed checks.

module probe_delete_filter

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.core.shim;
use xiom.vector.index.ann_index;
use xiom.vector.index.hnsw;
use xiom.vector.query.filter_plan;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vectors;
use xiom.io;
use xiom.convert;

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

// Independent reference: count live points matching the filter by scanning.
fn match_count(eng: &VectorEngine, f: &FilterExpr) -> Int {
  var n: Int = 0;
  var i: Int = 0;
  while i < eng.store.ids.len() {
    if payload_store_matches(&eng.payloads, eng.store.ids[i], f) { n = n + 1; }
    i = i + 1;
  }
  return n;
}

fn del_count(r: Result[Int, CoreError]) -> Int {
  match r {
    Ok(n) => { return n; }
    Err(_) => { return -1; }
  }
}

fn has_point(eng: &VectorEngine, id: Int) -> Bool {
  match get_point(eng, id) {
    Some(_) => { return true; }
    None => { return false; }
  }
}

// n points with payloads: category = id % 3, score = id, color for id % 5 == 0.
fn make_engine(dim: Int, n: Int, seed: Int) -> VectorEngine {
  var eng = engine_new();
  create_collection(&mut eng, dim, DistanceMetric.Euclidean);
  var s = seed;
  var i: Int = 1;
  while i <= n {
    var c = Vec<Float32>.new();
    s = rand_coords(s, dim, &mut c);
    upsert(&mut eng, i, vec_from_coords(&c));
    var p = payload_new();
    payload_set(&mut p, "category", FieldValue.IntVal(i % 3));
    payload_set(&mut p, "score", FieldValue.IntVal(i));
    if i % 5 == 0 {
      if i % 10 == 0 {
        payload_set(&mut p, "color", FieldValue.TextVal("red"));
      } else {
        payload_set(&mut p, "color", FieldValue.TextVal("blue"));
      }
    }
    set_payload(&mut eng, i, p);
    i = i + 1;
  }
  return eng;
}

fn main() -> Int {
  io.println("=== xvector probe: delete-by-filter ===");
  var fails: Int = 0;
  var dim: Int = 3;

  // --- planner-driven deletes on a 40-point engine ---
  var eng = make_engine(dim, 40, 881122);
  var f1 = filter_eq("category", FieldValue.IntVal(1));
  var exp1 = match_count(&eng, &f1);
  var got1 = del_count(delete_filter(&mut eng, &f1));
  fails = check(got1 == exp1 && got1 > 10, "eq (index plan): removes every match", fails);
  fails = check(engine_size(&eng) == 40 - exp1, "eq: live count drops by the removed count", fails);
  fails = check(!has_point(&eng, 4), "eq: deleted point gone from the store", fails);
  fails = check(has_point(&eng, 3), "eq: non-matching point kept", fails);
  var gp = get_payload(&eng, 4);
  var gp_none: Bool = false;
  match gp { Some(_) => {} None => { gp_none = true; } }
  fails = check(gp_none, "eq: deleted payload gone", fails);
  var fc1 = filter_matching_count(&eng.payloads, &f1);
  var pc1 = filter_plan_candidates(&eng.payloads, &f1);
  fails = check(fc1 == 0 && pc1.len() == 0, "eq: payload index cleaned (count + candidates empty)", fails);
  fails = check(del_count(delete_filter(&mut eng, &f1)) == 0, "eq: repeated delete is idempotent (0)", fails);

  var f2 = filter_range("score", 10.0, 19.0);
  var exp2 = match_count(&eng, &f2);
  fails = check(del_count(delete_filter(&mut eng, &f2)) == exp2 && match_count(&eng, &f2) == 0,
    "range (index plan): removes every in-range match", fails);

  var f3 = filter_exists("color");
  var exp3 = match_count(&eng, &f3);
  fails = check(del_count(delete_filter(&mut eng, &f3)) == exp3
    && payload_store_index_field_count(&eng.payloads, "color") == 0,
    "exists (index plan): removes points with the field; index field count 0", fails);

  var v02 = Vec[FieldValue].new();
  v02.push(FieldValue.IntVal(0));
  v02.push(FieldValue.IntVal(2));
  var engB = make_engine(dim, 40, 771133);
  var f4 = filter_in("category", v02);
  var exp4 = match_count(&engB, &f4);
  fails = check(del_count(delete_filter(&mut engB, &f4)) == exp4 && exp4 > 10,
    "in (scan plan): removes every match", fails);

  var engC = make_engine(dim, 40, 771199);
  var f5 = filter_not(filter_eq("category", FieldValue.IntVal(0)));
  var exp5 = match_count(&engC, &f5);
  fails = check(del_count(delete_filter(&mut engC, &f5)) == exp5 && exp5 > 10,
    "not (scan plan): removes every match", fails);

  var engD = make_engine(dim, 40, 771221);
  var ors = Vec[FilterExpr].new();
  ors.push(filter_eq("category", FieldValue.IntVal(0)));
  ors.push(filter_eq("score", FieldValue.IntVal(35)));
  var f6 = filter_or(ors);
  var exp6 = match_count(&engD, &f6);
  fails = check(del_count(delete_filter(&mut engD, &f6)) == exp6 && exp6 > 10,
    "or (scan plan): removes every match", fails);

  var engE = make_engine(dim, 40, 771233);
  var ands = Vec[FilterExpr].new();
  ands.push(filter_eq("category", FieldValue.IntVal(2)));
  ands.push(filter_exists("color"));
  var f7 = filter_and(ands);
  var exp7 = match_count(&engE, &f7);
  fails = check(del_count(delete_filter(&mut engE, &f7)) == exp7 && exp7 > 0,
    "and-of-index (index plan): removes every match", fails);

  fails = check(del_count(delete_filter(&mut engE, &filter_eq("category", FieldValue.IntVal(99)))) == 0,
    "match-none: Ok(0), never an error", fails);

  var engF = make_engine(dim, 12, 559973);
  var v012 = Vec[FieldValue].new();
  v012.push(FieldValue.IntVal(0));
  v012.push(FieldValue.IntVal(1));
  v012.push(FieldValue.IntVal(2));
  var f9 = filter_in("category", v012);
  var exp9 = match_count(&engF, &f9);
  var got9 = del_count(delete_filter(&mut engF, &f9));
  var empty_hits: Int = -1;
  var qz = Vector.new(dim);
  match search(&engF, &qz, 5) {
    Ok(h) => { empty_hits = h.items.len(); }
    Err(_) => {}
  }
  io.println("    diag match-all: got9=" + convert.int_to_string(got9) + " exp9=" + convert.int_to_string(exp9)
    + " size=" + convert.int_to_string(engine_size(&engF))
    + " plen=" + convert.int_to_string(payload_store_len(&engF.payloads))
    + " empty_hits=" + convert.int_to_string(empty_hits));
  fails = check(got9 == exp9 && exp9 == 12 && engine_size(&engF) == 0 && payload_store_len(&engF.payloads) == 0
    && empty_hits == 0,
    "match-all: clears the collection; search -> empty", fails);

  // --- per-point WAL records + recovery durability ---
  var eng2 = make_engine(dim, 20, 443311);
  var lsn0 = engine_durable_lsn(&eng2);
  var fg = filter_eq("category", FieldValue.IntVal(0));
  var expg = match_count(&eng2, &fg);
  var gotg = del_count(delete_filter(&mut eng2, &fg));
  fails = check(gotg == expg && engine_durable_lsn(&eng2) == lsn0 + gotg,
    "WAL: one durable record per removed point", fails);
  var rec = engine_recover(&eng2.wal, dim, DistanceMetric.Euclidean);
  fails = check(engine_size(&rec) == 20 - expg && !has_point(&rec, 3) && !has_point(&rec, 6),
    "recovery: filter-deleted points stay deleted after reopen", fails);
  var gpr = get_payload(&rec, 3);
  var gpr_none: Bool = false;
  match gpr { Some(_) => {} None => { gpr_none = true; } }
  fails = check(gpr_none, "recovery: deleted payloads do not resurrect", fails);

  // --- Hnsw: tombstones retained, search excludes, compaction reclaims ---
  var eng3 = make_engine(dim, 30, 227744);
  var si = set_index(&mut eng3, AnnIndexKind.Hnsw, AnnParams{ m: 8, ef_construction: 50, ef_search: 20 });
  var si_ok: Bool = false;
  match si { Ok(_) => { si_ok = true; } Err(_) => {} }
  var graph0 = hnsw_size(&eng3.graph);
  var fh = filter_eq("category", FieldValue.IntVal(2));
  var exph = match_count(&eng3, &fh);
  var goth = del_count(delete_filter(&mut eng3, &fh));
  fails = check(si_ok && goth == exph && engine_size(&eng3) == 30 - exph,
    "hnsw: delete-by-filter removes matching points", fails);
  fails = check(hnsw_size(&eng3.graph) == graph0 && hnsw_live_count(&eng3.graph) == 30 - exph,
    "hnsw: tombstones retained (size same, live count drops)", fails);
  var q3 = Vector.new(dim);
  match get_point(&eng3, 1) { Some(v) => { q3 = v; } None => {} }
  var exclude_ok: Bool = false;
  match search(&eng3, &q3, 6) {
    Ok(h) => {
      exclude_ok = h.items.len() > 0;
      var i: Int = 0;
      while i < h.items.len() {
        if h.items[i].id % 3 == 2 { exclude_ok = false; }
        i = i + 1;
      }
    }
    Err(_) => {}
  }
  fails = check(exclude_ok, "hnsw: search never returns filter-deleted points", fails);
  var comp = compact_index(&mut eng3);
  var comp_ok: Bool = false;
  var comp_n: Int = 0;
  match comp { Ok(n) => { comp_ok = true; comp_n = n; } Err(_) => {} }
  fails = check(comp_ok && comp_n == graph0 - (30 - exph) && hnsw_size(&eng3.graph) == 30 - exph,
    "hnsw: compaction reclaims the tombstones", fails);

  // --- multi-collection isolation ---
  var eng4 = engine_new();
  create_named_collection(&mut eng4, "a", dim, DistanceMetric.Euclidean);
  var c4 = Vec<Float32>.new();
  var s4: Int = 993311;
  s4 = rand_coords(s4, dim, &mut c4);
  var va = vec_from_coords(&c4);
  var i: Int = 1;
  while i <= 3 {
    upsert(&mut eng4, i, va);
    var pa = payload_new();
    payload_set(&mut pa, "category", FieldValue.IntVal(0));
    set_payload(&mut eng4, i, pa);
    i = i + 1;
  }
  create_named_collection(&mut eng4, "b", dim, DistanceMetric.Euclidean);
  i = 11;
  while i <= 14 {
    upsert(&mut eng4, i, va);
    var pb = payload_new();
    payload_set(&mut pb, "category", FieldValue.IntVal(0));
    set_payload(&mut eng4, i, pb);
    i = i + 1;
  }
  var fb = filter_eq("category", FieldValue.IntVal(0));
  var gotb = del_count(delete_filter(&mut eng4, &fb));
  var selA = select_collection(&mut eng4, "a");
  var selA_ok: Bool = false;
  match selA { Ok(_) => { selA_ok = true; } Err(_) => {} }
  fails = check(gotb == 4 && selA_ok && engine_size(&eng4) == 3,
    "multi-collection: only the active collection is affected", fails);

  // --- index cleanup on a crisp slice + chained recovery ---
  var eng5 = make_engine(dim, 6, 117799);
  var fc = filter_eq("category", FieldValue.IntVal(0));
  fails = check(del_count(delete_filter(&mut eng5, &fc)) == 2
    && filter_matching_count(&eng5.payloads, &fc) == 0
    && payload_store_index_field_count(&eng5.payloads, "category") == 4
    && payload_store_len(&eng5.payloads) == 4,
    "index cleanup: counts and lengths exact after 2 removals", fails);
  var rec2 = engine_recover(&eng5.wal, dim, DistanceMetric.Euclidean);
  var f1b = filter_eq("category", FieldValue.IntVal(1));
  var expb = match_count(&rec2, &f1b);
  fails = check(del_count(delete_filter(&mut rec2, &f1b)) == expb, "recovered engine: delete-by-filter works", fails);
  var rec3 = engine_recover(&rec2.wal, dim, DistanceMetric.Euclidean);
  fails = check(engine_size(&rec3) == 2, "chained: later delete-by-filter persists through reopen", fails);

  io.println("");
  io.println("probe_delete_filter: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
