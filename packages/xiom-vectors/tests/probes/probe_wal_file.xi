// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: file-backed WAL (whole-file checkpoint codec). Persists a scripted
// engine log to real files under out/, then verifies: content roundtrip,
// overwrite persistence, kill/reopen equality (file -> wal_load ->
// engine_recover == live), byte-truncation at many cut points recovers the
// longest complete-record prefix (torn-tail tolerance), and missing /
// garbage / empty files degrade to an empty log. Exit = failed checks.

module probe_wal_file

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.durability.wal;
use xiom.vector.durability.wal_file;
use xiom.vectors;
use xiom.vector.payload.payload;
use xiom.string.slice;
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

// Loads `path` and checks it equals `w` record-for-record.
fn wal_matches_file(w: &WalWriter, path: Str) -> Bool {
  var lw = wal_load(path);
  if lw.records.len() != w.records.len() { return false; }
  var i: Int = 0;
  while i < w.records.len() {
    if lw.records[i].lsn != w.records[i].lsn { return false; }
    if lw.records[i].op != w.records[i].op { return false; }
    if lw.records[i].key != w.records[i].key { return false; }
    if lw.records[i].value != w.records[i].value { return false; }
    if lw.records[i].timestamp != w.records[i].timestamp { return false; }
    if lw.records[i].payload.len() != w.records[i].payload.len() { return false; }
    var j: Int = 0;
    while j < w.records[i].payload.len() {
      if lw.records[i].payload[j] != w.records[i].payload[j] { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

// Loads `path` and checks it is a record-for-record prefix of `full`.
fn loaded_is_prefix(path: Str, full: &WalWriter) -> Bool {
  var lw = wal_load(path);
  if lw.records.len() > full.records.len() { return false; }
  var i: Int = 0;
  while i < lw.records.len() {
    if lw.records[i].lsn != full.records[i].lsn { return false; }
    if lw.records[i].op != full.records[i].op { return false; }
    if lw.records[i].key != full.records[i].key { return false; }
    if lw.records[i].value != full.records[i].value { return false; }
    if lw.records[i].payload.len() != full.records[i].payload.len() { return false; }
    var j: Int = 0;
    while j < lw.records[i].payload.len() {
      if lw.records[i].payload[j] != full.records[i].payload[j] { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

// Byte offset just after the n-th newline (1-based); file length if fewer.
fn byte_after_nth_newline(b: &Vec[UInt8], n: Int) -> Int {
  var seen: Int = 0;
  var i: Int = 0;
  while i < b.len() {
    if b[i] == 10 {
      seen = seen + 1;
      if seen == n { return i + 1; }
    }
    i = i + 1;
  }
  return b.len();
}

fn write_slice(b: &Vec[UInt8], count: Int, path: Str) -> Bool {
  var out = Vec[UInt8].new();
  var i: Int = 0;
  var n: Int = count;
  if n > b.len() { n = b.len(); }
  while i < n {
    out.push(b[i]);
    i = i + 1;
  }
  var res = io.write_file_bytes(path, &out);
  match res {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

fn same_state(a: &VectorEngine, b: &VectorEngine) -> Bool {
  if engine_size(a) != engine_size(b) { return false; }
  if payload_store_len(&a.payloads) != payload_store_len(&b.payloads) { return false; }
  if a.dimension != b.dimension { return false; }
  if a.metric != b.metric { return false; }
  if a.index_kind != b.index_kind { return false; }
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
  return true;
}

fn main() -> Int {
  io.println("=== xvector probe: file-backed WAL ===");
  var fails: Int = 0;
  var dim: Int = 4;
  var pa = "out/wal_probe_a.txt";
  var pb = "out/wal_probe_b.txt";
  var pm = "out/wal_probe_missing.txt";
  var pg = "out/wal_probe_garbage.txt";

  // Scripted log: create, 12 upserts, 2 payloads, 2 deletes, set_index Hnsw,
  // 4 more upserts (updates).
  var eng = engine_new();
  var s: Int = 515253;
  create_collection(&mut eng, dim, DistanceMetric.Cosine);
  var i: Int = 1;
  while i <= 12 {
    var c = Vec[Float32].new();
    s = rand_coords(s, dim, &mut c);
    upsert(&mut eng, i, vec_from_coords(&c));
    i = i + 1;
  }
  var p1 = payload_new();
  payload_set(&mut p1, "bucket", FieldValue.IntVal(1));
  set_payload(&mut eng, 1, p1);
  var p2 = payload_new();
  payload_set(&mut p2, "note", FieldValue.TextVal("persisted"));
  set_payload(&mut eng, 2, p2);
  delete_point(&mut eng, 11);
  delete_point(&mut eng, 12);
  set_index(&mut eng, AnnIndexKind.Hnsw, ann_params_default());
  i = 1;
  while i <= 4 {
    var c2 = Vec<Float32>.new();
    s = rand_coords(s, dim, &mut c2);
    upsert(&mut eng, i, vec_from_coords(&c2));
    i = i + 1;
  }

  // Persist + roundtrip.
  fails = check(wal_persist(&eng.wal, pa), "persist: write the WAL file", fails);
  var dres = io.read_file_bytes(pa);
  match dres {
    Ok(b) => {
      io.println("    diag read bytes=" + int_to_str(b.len()));
    }
    Err(_) => { io.println("    diag read error"); }
  }
  var dlw = wal_load(pa);
  io.println("    diag loaded records=" + int_to_str(dlw.records.len())
    + " of live " + int_to_str(eng.wal.records.len()));
  fails = check(wal_matches_file(&eng.wal, pa), "roundtrip: file records equal the live WAL", fails);

  // Kill/reopen: file -> wal_load -> engine_recover equals the live engine.
  var wr = wal_load(pa);
  var rec = engine_recover(&wr, dim, DistanceMetric.Cosine);
  fails = check(same_state(&rec, &eng) && rec.index_kind == AnnIndexKind.Hnsw,
    "kill/reopen: recovered engine equals live (incl. Hnsw config)", fails);

  // Overwrite: more ops -> persist again -> reload matches the new log.
  var c3 = Vec[Float32].new();
  s = rand_coords(s, dim, &mut c3);
  upsert(&mut eng, 99, vec_from_coords(&c3));
  delete_point(&mut eng, 3);
  fails = check(wal_persist(&eng.wal, pa) && wal_matches_file(&eng.wal, pa),
    "overwrite: second persist replaces the file with the new log", fails);
  var rec2 = engine_recover(&wal_load(pa), dim, DistanceMetric.Cosine);
  fails = check(same_state(&rec2, &eng), "overwrite: reopen equals live after the second persist", fails);

  // Chained persist of a RECOVERED log (regression: XV-ORBITDB-01 /
  // REL-20261010-1550-orbitdb-11): the recovered engine's checkpoint
  // resumes LSNs, so its first record is > 1; wal_load must accept any
  // starting LSN and reload the full prefix (it used to reload EMPTY).
  var pchain = "out/wal_file_chain_probe.txt";
  fails = check(wal_persist(&rec2.wal, pchain),
    "chained: persist a recovered engine's checkpoint", fails);
  var lchain = wal_load(pchain);
  fails = check(lchain.records.len() == rec2.wal.records.len() && lchain.records.len() > 0
    && rec2.wal.records[0].lsn > 1
    && lchain.records[0].lsn == rec2.wal.records[0].lsn,
    "chained: recovered log reloads non-empty with resumed first LSN", fails);
  var rec3 = engine_recover(&lchain, dim, DistanceMetric.Cosine);
  fails = check(same_state(&rec3, &eng) && rec3.index_kind == AnnIndexKind.Hnsw,
    "chained: second recovery equals the live engine", fails);
  io.remove_file(pchain);

  // M-D1 atomic checkpoint: persist writes `<path>.tmp` then io.rename.
  fails = check(!io.file_exists(pa + ".tmp"), "atomic: no .tmp remains after a persist", fails);
  var nrec_v2: Int = eng.wal.records.len();
  var c4 = Vec[Float32].new();
  s = rand_coords(s, dim, &mut c4);
  upsert(&mut eng, 123, vec_from_coords(&c4));
  // Simulate a kill between the temp write and the rename: the COMPLETE new
  // checkpoint is staged at the temp path only (a real process would have
  // written it and died before io.rename).
  fails = check(wal_persist(&eng.wal, pa + ".tmp"),
    "atomic: stage complete temp checkpoint (kill before rename)", fails);
  var oldl = wal_load(pa);
  fails = check(oldl.records.len() == nrec_v2,
    "atomic: previous checkpoint intact after interrupted persist", fails);
  var tmpl = wal_load(pa + ".tmp");
  fails = check(tmpl.records.len() == eng.wal.records.len(),
    "atomic: staged temp holds the new log", fails);
  // Simulate a kill DURING the temp write: partial bytes in the temp path are
  // never part of the readable state.
  var fbp = io.read_file_bytes(pa + ".tmp");
  var pbytes = Vec[UInt8].new();
  match fbp {
    Ok(b) => {
      var pi: Int = 0;
      var plim: Int = b.len() / 3;
      while pi < plim { pbytes.push(b[pi]); pi = pi + 1; }
    }
    Err(_) => { fails = fails + 1; }
  }
  var pwr = io.write_file_bytes(pa + ".tmp", &pbytes);
  match pwr { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  var oldl2 = wal_load(pa);
  fails = check(oldl2.records.len() == nrec_v2,
    "atomic: partial temp cannot damage the checkpoint", fails);
  match io.remove_file(pa + ".tmp") { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  fails = check(!io.file_exists(pa + ".tmp"), "atomic: temp cleanup", fails);
  // Complete the checkpoint again (the rename path applies) so the sweep
  // below still compares the file against the live log.
  fails = check(wal_persist(&eng.wal, pa), "atomic: completed persist after injection", fails);
  fails = check(wal_matches_file(&eng.wal, pa), "atomic: file equals live after completed persist", fails);

  // Byte-truncation sweep: every prefix of the file loads as a complete-record
  // prefix of the full log.
  var fbres = io.read_file_bytes(pa);
  var fb = Vec[UInt8].new();
  match fbres {
    Ok(b) => { fb = b; }
    Err(_) => { fails = fails + 1; }
  }
  var nrec_full: Int = eng.wal.records.len();
  var cuts = Vec[Int].new();
  cuts.push(0);
  cuts.push(1);
  cuts.push(3);
  cuts.push(5);
  cuts.push(fb.len() / 4);
  cuts.push(fb.len() / 2);
  cuts.push(fb.len() * 3 / 4);
  cuts.push(fb.len() - 1);
  cuts.push(fb.len());
  var bad_cuts: Int = 0;
  var ci: Int = 0;
  while ci < cuts.len() {
    if !write_slice(&fb, cuts[ci], pb) { bad_cuts = bad_cuts + 1; }
    var pc = wal_load(pb);
    var pok = loaded_is_prefix(pb, &eng.wal);
    var rc = engine_recover(&wal_load(pb), dim, DistanceMetric.Cosine);
    io.println("    diag cut ci=" + int_to_str(ci) + " len=" + int_to_str(cuts[ci])
      + " loaded=" + int_to_str(pc.records.len())
      + " prefixOk=" + int_to_str(if pok { 1 } else { 0 })
      + " recovered=" + int_to_str(engine_size(&rc)));
    if !pok { bad_cuts = bad_cuts + 1; }
    ci = ci + 1;
  }
  fails = check(bad_cuts == 0, "torn file: 9 cut points all load as clean prefixes", fails);
  fails = check(write_slice(&fb, fb.len(), pb) && wal_matches_file(&eng.wal, pb),
    "full cut: truncated-at-length file matches the full log", fails);

  // Exact record-boundary cuts: after n newlines -> header + (n-1) records.
  var b1 = byte_after_nth_newline(&fb, 1);
  fails = check(write_slice(&fb, b1, pb) && wal_load(pb).records.len() == 0,
    "boundary cut (header only): 0 records", fails);
  var b3 = byte_after_nth_newline(&fb, 3);
  fails = check(write_slice(&fb, b3, pb) && wal_load(pb).records.len() == 2
    && loaded_is_prefix(pb, &eng.wal),
    "boundary cut (after 2 records): exactly 2 records", fails);
  var b6 = byte_after_nth_newline(&fb, 6);
  fails = check(write_slice(&fb, b6, pb) && wal_load(pb).records.len() == 5
    && loaded_is_prefix(pb, &eng.wal),
    "boundary cut (after 5 records): exactly 5 records", fails);

  // Missing / garbage / empty files degrade to an empty log.
  io.remove_file(pm);
  fails = check(wal_load(pm).records.len() == 0, "missing file -> empty log", fails);
  var gbytes = slice.str_bytes("not a wal at all\n1 2 3\n");
  io.write_file_bytes(pg, &gbytes);
  fails = check(wal_load(pg).records.len() == 0, "garbage header -> empty log", fails);
  var gbytes2 = slice.str_bytes("xvector-wal 1\ngarbage line here\n");
  io.write_file_bytes(pg, &gbytes2);
  fails = check(wal_load(pg).records.len() == 0, "garbage record -> empty log (no valid prefix)", fails);
  var ebytes = Vec[UInt8].new();
  io.write_file_bytes(pg, &ebytes);
  fails = check(wal_load(pg).records.len() == 0, "empty file -> empty log", fails);

  // Scale guard for the LINEAR byte builder (M-G bench finding): a
  // 1200-record checkpoint must round-trip exactly and quickly -- the old
  // O(L^2) string builder thrashed at this size.
  var bigw = wal_writer_new();
  var bi: Int = 1;
  var last_lsn: Int = 0;
  while bi <= 1200 {
    var bp = Vec[Int].new();
    bp.push(bi); bp.push(bi * 2); bp.push(bi * 3); bp.push(4);
    last_lsn = wal_writer_append_payload(&mut bigw, WalOpKind.Insert, bi, 1, bp);
    bi = bi + 1;
  }
  var pbig = "out/wal_probe_big.txt";
  fails = check(last_lsn == 1200, "scale: 1200 appends keep LSN continuity", fails);
  fails = check(wal_persist(&bigw, pbig), "scale: persist 1200 records", fails);
  var bigl = wal_load(pbig);
  fails = check(bigl.records.len() == 1200, "scale: 1200 records load back", fails);
  fails = check(wal_matches_file(&bigw, pbig), "scale: 1200-record roundtrip exact", fails);
  io.remove_file(pbig);

  io.println("    diag: records=" + int_to_str(nrec_full) + " file_bytes=" + int_to_str(fb.len()));
  io.remove_file(pa);
  io.remove_file(pb);
  io.remove_file(pg);
  io.println("");
  io.println("probe_wal_file: " + int_to_str(fails) + " failed checks");
  return fails;
}
