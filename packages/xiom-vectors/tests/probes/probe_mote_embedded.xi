// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// L-1 mote quickstart probe: the EMBEDDED round trip a `xvector-mote`
// consumer does -- no sockets, no daemon:
//   open an engine -> create a named collection -> upsert -> search ->
//   persist (manifest + WAL) -> reopen the same home -> identical search;
//   then a second collection (routing check) -> persist/reopen again.
// Exit = failed checks (0 = green). Quickstart: docs/MOTE-QUICKSTART.md.

module probe_mote_embedded

use xiom.vector.engine;
use xiom.vector.engine.core;
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

fn has_name(cl: &CollectionList, name: Str) -> Bool {
  var i: Int = 0;
  while i < cl.names.len() {
    if cl.names[i] == name { return true; }
    i = i + 1;
  }
  return false;
}

fn main() -> Int {
  io.println("=== xvector probe: mote embedded round trip (L-1) ===");
  var fails: Int = 0;

  var p_manifest = "out/mote_home_manifest.txt";
  var p_wal = "out/mote_home_wal.ckpt";
  let _c0 = io.remove_file(p_manifest);
  let _c1 = io.remove_file(p_wal);

  // 1. open + create (the embedded entry point).
  var eng = engine_new();
  match create_named_collection(&mut eng, "docs", 4, DistanceMetric.Cosine) {
    Ok(_) => { fails = check(true, "create_named_collection(docs, 4, cosine)", fails); }
    Err(_) => { fails = check(false, "create_named_collection(docs, 4, cosine)", fails); }
  }

  // 2. upsert three points into the active collection.
  var w = true;
  match upsert(&mut eng, 1, mk_vec4(1.0, 0.0, 0.0, 0.0)) { Ok(_) => {} Err(_) => { w = false; } }
  match upsert(&mut eng, 2, mk_vec4(0.9, 0.1, 0.0, 0.0)) { Ok(_) => {} Err(_) => { w = false; } }
  match upsert(&mut eng, 3, mk_vec4(0.0, 1.0, 0.0, 0.0)) { Ok(_) => {} Err(_) => { w = false; } }
  fails = check(w && engine_size(&eng) == 3, "upsert x3 (size=3)", fails);

  // 3. search in-process.
  var q = mk_vec4(1.0, 0.0, 0.0, 0.0);
  fails = check(search_two(&mut eng, &q), "search top-2 -> {1, 2} with distances", fails);

  // 4. persist the home (manifest + WAL checkpoint).
  var sm = save_manifest(&mut eng, p_manifest);
  var wp = wal_persist(&eng.wal, p_wal);
  fails = check(sm && wp, "persist: manifest + WAL checkpoint written", fails);

  // 5. reopen the same home embedded and re-check.
  var rec = open_engine(&wal_load(p_wal), p_manifest, 4, DistanceMetric.Cosine);
  fails = check(engine_size(&rec) == 3 && rec.metric == DistanceMetric.Cosine,
    "reopen: same home, 3 points, cosine", fails);
  fails = check(search_two(&mut rec, &q), "reopen: search identical {1, 2}", fails);

  // 6. second collection in the same home (routing check).
  match create_named_collection(&mut rec, "other", 3, DistanceMetric.Euclidean) {
    Ok(_) => { fails = check(true, "create_named_collection(other, 3, euclidean)", fails); }
    Err(_) => { fails = check(false, "create_named_collection(other, 3, euclidean)", fails); }
  }
  match upsert(&mut rec, 7, mk_vec3(1.0, 0.0, 0.0)) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  var cl = list_collections(&rec);
  fails = check(cl.names.len() == 2 && has_name(&cl, "docs") && has_name(&cl, "other"),
    "registry: two collections listed", fails);
  match select_collection(&mut rec, "docs") {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  fails = check(search_two(&mut rec, &q), "routing: docs search intact after adding other", fails);

  // 7. persist + reopen once more: both collections survive. (This leg
  // gates the gate-caught cid-collision fix: creating a collection after
  // a reopen must not reuse a recovered cid, or the next recovery's
  // last-wins manifest merge silently drops the earlier collection.)
  var sm2 = save_manifest(&mut rec, p_manifest);
  var wp2 = wal_persist(&rec.wal, p_wal);
  fails = check(sm2 && wp2, "persist #2: manifest + WAL checkpoint rewritten", fails);
  var rec2 = open_engine(&wal_load(p_wal), p_manifest, 4, DistanceMetric.Cosine);
  var cl2 = list_collections(&rec2);
  fails = check(cl2.names.len() == 2 && has_name(&cl2, "docs") && has_name(&cl2, "other"),
    "reopen #2: both collections survive", fails);
  match select_collection(&mut rec2, "docs") {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  fails = check(search_two(&mut rec2, &q), "reopen #2: docs search identical {1, 2}", fails);

  // cleanup (best effort)
  let _r0 = io.remove_file(p_manifest);
  let _r1 = io.remove_file(p_wal);

  io.println("");
  io.println("probe_mote_embedded: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
