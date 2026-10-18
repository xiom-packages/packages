// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: multi-collection registry (M-D3). Verifies named collections
// (create/select/drop/list), per-collection isolation of stores, payloads
// and index config, WAL recovery of every collection (v2 manifest records +
// routed data records), drop persistence across reopen, the legacy
// "default" path, and the manifest-file registry (whole-registry save +
// open with file-wins overrides). Exit = failed checks.

module probe_collections

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.durability.manifest_file;
use xiom.vectors;
use xiom.vector.payload.payload;
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

fn hnsw_params() -> AnnParams {
  return AnnParams{ m: 8, ef_construction: 50, ef_search: 20 };
}

fn search_ids(eng: &VectorEngine, q: &Vector, k: Int) -> Vec[Int] {
  var ids = Vec[Int].new();
  match search(eng, q, k) {
    Ok(h) => {
      var i: Int = 0;
      while i < h.items.len() {
        ids.push(h.items[i].id);
        i = i + 1;
      }
    }
    Err(_) => {}
  }
  return ids;
}

fn has_payload(eng: &VectorEngine, id: Int) -> Bool {
  match get_payload(eng, id) {
    Some(_) => { return true; }
    None => { return false; }
  }
}

fn names_eq(names: &Vec[Str], want: Str, want2: Str) -> Bool {
  if names.len() != 2 { return false; }
  if !(names[0] == want) { return false; }
  if !(names[1] == want2) { return false; }
  return true;
}

fn main() -> Int {
  io.println("=== xvector probe: multi-collection registry ===");
  var fails: Int = 0;
  var pm = "out/collections_probe.txt";
  var s: Int = 771133;

  // --- create two named collections with distinct dims/metrics ---
  var eng = engine_new();
  var c1 = create_named_collection(&mut eng, "vecs", 4, DistanceMetric.Cosine);
  var c1_ok: Bool = false;
  match c1 { Ok(_) => { c1_ok = true; } Err(_) => {} }
  fails = check(c1_ok, "create: named collection vecs (dim 4 cosine)", fails);
  fails = check(collection_count(&eng) == 1, "create: count 1", fails);
  var cl1 = list_collections(&eng);
  fails = check(cl1.names.len() == 1 && cl1.names[0] == "vecs", "create: list [vecs]", fails);

  var vq = Vec[Float32].new();
  s = rand_coords(s, 4, &mut vq);
  var v1c = Vec<Float32>.new();  var i: Int = 1;
  while i <= 5 {
    var c = Vec<Float32>.new();
    s = rand_coords(s, 4, &mut c);
    if i == 1 {
      var kk: Int = 0;
      while kk < c.len() { v1c.push(c[kk]); kk = kk + 1; }
    }
    upsert(&mut eng, i, vec_from_coords(&c));
    i = i + 1;
  }
  fails = check(engine_size(&eng) == 5, "create: 5 points upserted into vecs", fails);

  var c2 = create_named_collection(&mut eng, "imgs", 3, DistanceMetric.Euclidean);
  var c2_ok: Bool = false;
  match c2 { Ok(_) => { c2_ok = true; } Err(_) => {} }
  fails = check(c2_ok, "create: named collection imgs (dim 3 euclidean)", fails);
  fails = check(collection_count(&eng) == 2, "create: count 2", fails);
  var cl2 = list_collections(&eng);
  fails = check(names_eq(&cl2.names, "vecs", "imgs"), "create: list [vecs, imgs]", fails);
  fails = check(engine_size(&eng) == 0, "isolation: new collection is active and empty", fails);

  var iq = Vec[Float32].new();
  s = rand_coords(s, 3, &mut iq);
  var i11c = Vec[Float32].new();
  i = 11;
  while i <= 14 {
    var c = Vec<Float32>.new();
    s = rand_coords(s, 3, &mut c);
    if i == 11 {
      var kk: Int = 0;
      while kk < c.len() { i11c.push(c[kk]); kk = kk + 1; }
    }
    upsert(&mut eng, i, vec_from_coords(&c));
    i = i + 1;
  }
  var wrong = vec_from_coords(&vq);
  var wrong_res = upsert(&mut eng, 99, wrong);
  var wrong_err: Bool = false;
  match wrong_res { Ok(_) => {} Err(_) => { wrong_err = true; } }
  fails = check(wrong_err, "isolation: dim-4 vector rejected on the dim-3 collection", fails);

  // --- select back to vecs: data + config intact; results stable ---
  var sel1 = select_collection(&mut eng, "vecs");
  var sel1_ok: Bool = false;
  match sel1 { Ok(_) => { sel1_ok = true; } Err(_) => {} }
  fails = check(sel1_ok && engine_size(&eng) == 5, "select: vecs active with its 5 points", fails);
  var vids = search_ids(&eng, &vec_from_coords(&v1c), 3);
  i = 0;
  var stable: Bool = vids.len() == 3 && vids[0] == 1;
  fails = check(stable, "select: vecs search finds its own points (exact self-hit)", fails);

  var p1 = payload_new();
  payload_set(&mut p1, "tag", FieldValue.IntVal(7));
  set_payload(&mut eng, 1, p1);

  var sel2 = select_collection(&mut eng, "imgs");
  var sel2_ok: Bool = false;
  match sel2 { Ok(_) => { sel2_ok = true; } Err(_) => {} }
  fails = check(sel2_ok && engine_size(&eng) == 4, "select: imgs active with its 4 points", fails);
  fails = check(!has_payload(&eng, 1), "isolation: vecs payload invisible in imgs", fails);
  var iids = search_ids(&eng, &vec_from_coords(&i11c), 2);
  fails = check(iids.len() == 2 && iids[0] == 11, "select: imgs search finds its own points", fails);
  var p2 = payload_new();
  payload_set(&mut p2, "tag", FieldValue.IntVal(9));
  set_payload(&mut eng, 11, p2);

  var si = set_index(&mut eng, AnnIndexKind.Hnsw, hnsw_params());
  var si_ok: Bool = false;
  match si { Ok(_) => { si_ok = true; } Err(_) => {} }
  fails = check(si_ok && eng.index_kind == AnnIndexKind.Hnsw, "config: imgs switched to Hnsw", fails);

  var sel3 = select_collection(&mut eng, "vecs");
  var sel3_ok: Bool = false;
  match sel3 { Ok(_) => { sel3_ok = true; } Err(_) => {} }
  var vids2 = search_ids(&eng, &vec_from_coords(&v1c), 3);
  var same_ids: Bool = vids2.len() == vids.len();
  if same_ids {
    i = 0;
    while i < vids.len() {
      if vids2[i] != vids[i] { same_ids = false; }
      i = i + 1;
    }
  }
  fails = check(sel3_ok && eng.index_kind == AnnIndexKind.Flat && same_ids,
    "config: vecs still Flat, search bit-stable across switches", fails);
  fails = check(has_payload(&eng, 1), "isolation: vecs payload survives its switch cycle", fails);

  // --- validation ---
  var dup = create_named_collection(&mut eng, "vecs", 4, DistanceMetric.Cosine);
  var dup_err: Bool = false;
  match dup { Ok(_) => {} Err(_) => { dup_err = true; } }
  fails = check(dup_err, "validation: duplicate name rejected", fails);
  var badname = create_named_collection(&mut eng, "bad name", 4, DistanceMetric.Cosine);
  var badname_err: Bool = false;
  match badname { Ok(_) => {} Err(_) => { badname_err = true; } }
  fails = check(badname_err, "validation: invalid name rejected", fails);
  var baddim = create_named_collection(&mut eng, "fresh", 0, DistanceMetric.Cosine);
  var baddim_err: Bool = false;
  match baddim { Ok(_) => {} Err(_) => { baddim_err = true; } }
  fails = check(baddim_err, "validation: dim 0 rejected", fails);
  var selmiss = select_collection(&mut eng, "nope");
  var selmiss_err: Bool = false;
  match selmiss { Ok(_) => {} Err(_) => { selmiss_err = true; } }
  fails = check(selmiss_err, "validation: select unknown -> Err", fails);
  var dropmiss = drop_collection(&mut eng, "nope");
  var dropmiss_err: Bool = false;
  match dropmiss { Ok(_) => {} Err(_) => { dropmiss_err = true; } }
  fails = check(dropmiss_err, "validation: drop unknown -> Err", fails);

  // --- WAL recovery: every collection comes back ---
  var rec = engine_recover(&eng.wal, 4, DistanceMetric.Cosine);
  fails = check(collection_count(&rec) == 2, "recover: both collections restored", fails);
  var rcl = list_collections(&rec);
  fails = check(names_eq(&rcl.names, "vecs", "imgs"), "recover: names in creation order", fails);
  fails = check(engine_size(&rec) == 5 && rec.index_kind == AnnIndexKind.Flat
    && rec.metric == DistanceMetric.Cosine && rec.dimension == 4,
    "recover: first collection active (vecs: 5, Flat, cosine, dim 4)", fails);
  var rsel = select_collection(&mut rec, "imgs");
  var rsel_ok: Bool = false;
  match rsel { Ok(_) => { rsel_ok = true; } Err(_) => {} }
  fails = check(rsel_ok && engine_size(&rec) == 4 && rec.index_kind == AnnIndexKind.Hnsw
    && rec.metric == DistanceMetric.Euclidean && rec.dimension == 3,
    "recover: imgs restored as Hnsw (dim 3, 4 points)", fails);
  fails = check(has_payload(&rec, 11) && !has_payload(&rec, 1),
    "recover: payloads route to their own collection", fails);

  // --- chained recovery (checkpoint carries the whole registry) ---
  var rec2 = engine_recover(&rec.wal, 4, DistanceMetric.Cosine);
  var rc2 = list_collections(&rec2);
  fails = check(collection_count(&rec2) == 2 && names_eq(&rc2.names, "vecs", "imgs")
    && engine_size(&rec2) == 5,
    "chained: registry + data survive a second recovery", fails);

  // --- drop is WAL-durable ---
  var dr = drop_collection(&mut eng, "imgs");
  var dr_ok: Bool = false;
  match dr { Ok(_) => { dr_ok = true; } Err(_) => {} }
  var cl3 = list_collections(&eng);
  fails = check(collection_count(&eng) == 1 && cl3.names.len() == 1 && cl3.names[0] == "vecs",
    "drop: imgs removed, vecs remains", fails);
  var dr2 = drop_collection(&mut eng, "imgs");
  var dr2_err: Bool = false;
  match dr2 { Ok(_) => {} Err(_) => { dr2_err = true; } }
  fails = check(dr2_err, "drop: second drop rejected", fails);
  var recd = engine_recover(&eng.wal, 4, DistanceMetric.Cosine);
  var rcd = list_collections(&recd);
  fails = check(collection_count(&recd) == 1 && rcd.names.len() == 1 && rcd.names[0] == "vecs"
    && engine_size(&recd) == 5,
    "drop: reopen sees only vecs (dropped data not resurrected)", fails);

  // --- dropping the last collection resets the engine for a fresh start ---
  var dr3 = drop_collection(&mut eng, "vecs");
  var dr3_ok: Bool = false;
  match dr3 { Ok(_) => { dr3_ok = true; } Err(_) => {} }
  fails = check(collection_count(&eng) == 0 && !eng.created, "drop: last collection leaves an empty engine", fails);
  var selempty = select_collection(&mut eng, "vecs");
  var selempty_err: Bool = false;
  match selempty { Ok(_) => {} Err(_) => { selempty_err = true; } }
  fails = check(selempty_err, "drop: select on the emptied engine -> Err", fails);
  var leg = create_collection(&mut eng, 4, DistanceMetric.Cosine);
  var leg_ok: Bool = false;
  match leg { Ok(_) => { leg_ok = true; } Err(_) => {} }
  var cl4 = list_collections(&eng);
  var lq = Vec<Float32>.new();
  s = rand_coords(s, 4, &mut lq);
  var lqv = vec_from_coords(&lq);
  upsert(&mut eng, 1, lqv);
  var lg_ids = search_ids(&eng, &lqv, 1);
  fails = check(leg_ok && cl4.names.len() == 1 && cl4.names[0] == "default"
    && lg_ids.len() == 1 && lg_ids[0] == 1,
    "legacy: create_collection -> 'default' works after empty", fails);

  // --- manifest file: whole-registry save + open with file overrides ---
  var eng2 = engine_new();
  create_named_collection(&mut eng2, "alpha", 4, DistanceMetric.Cosine);
  s = rand_coords(s, 4, &mut lq);
  i = 1;
  while i <= 3 {
    var c = Vec<Float32>.new();
    s = rand_coords(s, 4, &mut c);
    upsert(&mut eng2, i, vec_from_coords(&c));
    i = i + 1;
  }
  create_named_collection(&mut eng2, "beta", 2, DistanceMetric.Euclidean);
  var bq = Vec[Float32].new();
  s = rand_coords(s, 2, &mut bq);
  i = 21;
  while i <= 22 {
    var c2 = Vec[Float32].new();
    s = rand_coords(s, 2, &mut c2);
    upsert(&mut eng2, i, vec_from_coords(&c2));
    i = i + 1;
  }
  set_index(&mut eng2, AnnIndexKind.Hnsw, hnsw_params());
  fails = check(save_manifest(&mut eng2, pm), "manifest: save whole registry", fails);
  var ml = manifest_load(pm);
  var ml_ok: Bool = ml.valid && ml.entries.len() == 2;
  if ml_ok {
    ml_ok = ml.entries[0].name == "alpha" && ml.entries[1].name == "beta"
      && ml.entries[0].dim == 4 && ml.entries[1].dim == 2
      && ml.entries[0].metric == DistanceMetric.Cosine
      && ml.entries[1].metric == DistanceMetric.Euclidean
      && ml.entries[1].kind == AnnIndexKind.Hnsw
      && ml.entries[1].m == 8 && ml.entries[1].ef_construction == 50
      && ml.entries[1].ef_search == 20;
  }
  fails = check(ml_ok, "manifest: both entries with per-collection configs", fails);

  var op = open_engine(&eng2.wal, pm, 4, DistanceMetric.Cosine);
  var ocl = list_collections(&op);
  fails = check(collection_count(&op) == 2 && names_eq(&ocl.names, "alpha", "beta"),
    "open: registry restores both collections", fails);
  var osel = select_collection(&mut op, "beta");
  var osel_ok: Bool = false;
  match osel { Ok(_) => { osel_ok = true; } Err(_) => {} }
  fails = check(osel_ok && engine_size(&op) == 2 && op.index_kind == AnnIndexKind.Hnsw
    && op.dimension == 2,
    "open: beta config + data restored (Hnsw, dim 2)", fails);

  // file-wins: stale file (Flat) vs newer WAL (Hnsw) -> Flat.
  var eng3 = engine_new();
  create_named_collection(&mut eng3, "solo", 2, DistanceMetric.Euclidean);
  fails = check(save_manifest(&mut eng3, pm), "file-wins: save before set_index", fails);
  set_index(&mut eng3, AnnIndexKind.Hnsw, hnsw_params());
  var walonly = engine_recover(&eng3.wal, 2, DistanceMetric.Euclidean);
  fails = check(walonly.index_kind == AnnIndexKind.Hnsw, "file-wins: WAL-only recovery sees Hnsw", fails);
  var fromfile = open_engine(&eng3.wal, pm, 2, DistanceMetric.Euclidean);
  fails = check(fromfile.index_kind == AnnIndexKind.Flat,
    "file-wins: manifest file governs (Flat) over the newer WAL config", fails);

  io.remove_file(pm);
  io.println("");
  io.println("probe_collections: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
