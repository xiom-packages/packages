// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// probe_wal_segment -- M-D5 delta WAL segment acceptance.
// Part A: codec v1 framing bytes + tolerant replay semantics.
// Part B: append/fsync path, heal, merge dedupe, rotation.
// Part C: engine durability wiring (enable -> upsert -> fsync frontier ->
//         reopen from checkpoint+segment -> state intact) -- added with the
//         engine slice; see the bottom of this file.
// Exit = number of failed checks.

module probe_wal_segment

use xiom.vector.durability.wal;
use xiom.vector.durability.wal_file;
use xiom.vector.durability.wal_segment;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.storage.vector_store;
use xiom.vectors;
use xiom.io;
use xiom.convert;
use xiom.string.slice;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn pay3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn rec(lsn: Int, op: WalOpKind, key: Int, value: Int, ts: Int, payload: Vec[Int]) -> WalRecord {
  return WalRecord{ lsn: lsn, op: op, key: key, value: value, payload: payload, timestamp: ts };
}

fn empty_rec(lsn: Int, op: WalOpKind, key: Int, value: Int) -> WalRecord {
  var p = Vec[Int].new();
  return rec(lsn, op, key, value, 0, p);
}

fn bytes_eq(a: &Vec[UInt8], c: &Vec[UInt8]) -> Bool {
  if a.len() != c.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != c[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn write_bytes(path: Str, data: &Vec[UInt8]) -> Bool {
  match io.write_file_bytes(path, data) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

fn read_or_empty(path: Str) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  match io.read_file_bytes(path) {
    Ok(x) => { b = x; }
    Err(_) => {}
  }
  return b;
}

fn append_raw(path: Str, s: Str) -> Bool {
  var b = slice.str_bytes(s);
  match io.append_file_bytes(path, &b) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Build a writer whose records are the given (lsn, op, key, value, payload)
// quints in order, starting from `start_lsn`.
fn writer_with(start_lsn: Int, ops: &Vec[Int], keys: &Vec[Int], vals: &Vec[Int], pays: &Vec[Vec[Int]]) -> WalWriter {
  var w = wal_writer_resume(start_lsn);
  var i = 0;
  while i < ops.len() {
    var op = WalOpKind.Insert;
    if ops[i] == 2 { op = WalOpKind.Update; }
    if ops[i] == 3 { op = WalOpKind.Delete; }
    if ops[i] == 5 { op = WalOpKind.ManifestUpdate; }
    let _lsn = wal_writer_append_payload(&mut w, op, keys[i], vals[i], pays[i]);
    i = i + 1;
  }
  return w;
}

fn main() -> Int {
  var fails = 0;
  let p = "out/probe_wal_segment.seg";
  let p2 = "out/probe_wal_segment2.seg";

  // ---- Part A: codec v1 framing ----
  var l1 = segment_line(&rec(1, WalOpKind.Insert, 7, 42, 0, pay3(1, 2, 3)));
  var e1 = slice.str_bytes("1|1|7|42|0|1,2,3\n");
  fails = check(bytes_eq(&l1, &e1), "render: payload line is codec v1 bytes", fails);

  var l2 = segment_line(&empty_rec(2, WalOpKind.Delete, 9, 0));
  var e2 = slice.str_bytes("2|3|9|0|0\n");
  fails = check(bytes_eq(&l2, &e2), "render: no-payload line is codec v1 bytes", fails);

  // Negative lsn / big payload shape.
  var big = Vec[Int].new();
  var bi = 0;
  while bi < 12 {
    big.push(bi * 1000 - 7);
    bi = bi + 1;
  }
  var l3 = segment_line(&rec(1042, WalOpKind.ManifestUpdate, -3, 5, 77, big));
  var probe0 = wal_writer_new();
  var tmpf = "out/probe_wal_segment_exact.seg";
  let _w0 = write_bytes(tmpf, &l3);
  let _n0 = segment_parse_into(tmpf, &mut probe0);
  fails = check(probe0.records.len() == 1 && probe0.records[0].payload.len() == 12
    && probe0.records[0].payload[0] == -7 && probe0.records[0].payload[11] == 10993
    && probe0.records[0].lsn == 1042 && probe0.records[0].key == -3,
    "render: negative fields + 12-word payload round-trip", fails);

  // ---- Part B: append/sync/parse ----
  let _rm0 = io.remove_file(p);
  var ops = Vec[Int].new();
  ops.push(1); ops.push(2);
  var keys = Vec[Int].new();
  keys.push(7); keys.push(8);
  var vals = Vec[Int].new();
  vals.push(42); vals.push(43);
  var pays = Vec[Vec[Int]].new();
  pays.push(pay3(1, 2, 3));
  pays.push(Vec[Int].new());
  var w = writer_with(1, &ops, &keys, &vals, &pays);

  var ar = segment_append_sync(p, &w, 0);
  var appended: Int = -1;
  match ar {
    Ok(n) => { appended = n; }
    Err(_) => {}
  }
  fails = check(appended == 2, "append_sync: writes pending records + fsync", fails);
  fails = check(segment_last_lsn(p) == 2, "last_lsn: 2 after two appends", fails);

  var rd0 = read_or_empty(p);
  var exp0 = Vec[UInt8].new();
  var r0a = rec(1, WalOpKind.Insert, 7, 42, 0, pay3(1, 2, 3));
  var r0b = empty_rec(2, WalOpKind.Update, 8, 43);
  segment_render(&mut exp0, &r0a);
  segment_render(&mut exp0, &r0b);
  fails = check(bytes_eq(&rd0, &exp0), "append_sync: file bytes are the two lines", fails);

  var pa = wal_writer_new();
  let npa = segment_parse_into(p, &mut pa);
  fails = check(npa == 2 && pa.records[0].lsn == 1 && pa.records[0].op == WalOpKind.Insert
    && pa.records[0].key == 7 && pa.records[0].value == 42 && pa.records[0].payload.len() == 3
    && pa.records[1].lsn == 2 && pa.records[1].op == WalOpKind.Update && pa.records[1].key == 8,
    "parse_into: fields round-trip", fails);

  // Incremental append from a frontier.
  let _a3 = wal_writer_append_payload(&mut w, WalOpKind.Delete, 9, 0, Vec[Int].new());
  var ar2 = segment_append_sync(p, &w, 2);
  var n2: Int = -1;
  match ar2 { Ok(n) => { n2 = n; } Err(_) => {} }
  fails = check(n2 == 1 && segment_last_lsn(p) == 3, "append_sync: from_lsn frontier writes only the delta", fails);

  // ---- torn tails ----
  // (a) invalid partial line: skipped by replay; heal separates it; the next
  // append continues with a contiguous LSN.
  let _t1 = append_raw(p, "4|1|5|0|");
  var pt = wal_writer_new();
  let nt = segment_parse_into(p, &mut pt);
  fails = check(nt == 3 && segment_last_lsn(p) == 3, "torn (invalid tail): replay keeps the valid prefix", fails);
  fails = check(segment_heal(p), "heal: appends the missing newline", fails);
  let _a4 = wal_writer_append_payload(&mut w, WalOpKind.Insert, 10, 0, Vec[Int].new());
  var ar3 = segment_append_sync(p, &w, 3);
  var n3: Int = -1;
  match ar3 { Ok(n) => { n3 = n; } Err(_) => {} }
  fails = check(n3 == 1 && segment_last_lsn(p) == 4, "torn+heal: next append lands as a fresh valid line", fails);
  var pt2 = wal_writer_new();
  let nt2 = segment_parse_into(p, &mut pt2);
  fails = check(nt2 == 4 && pt2.records[3].lsn == 4 && pt2.records[3].key == 10,
    "torn+heal: replay reads 1..4 with the real record 4", fails);

  // (b) valid line without trailing newline: parsed as a record (it was fully
  // written); the next append continues after it. The continuation writer is
  // the PARSED frontier (the in-file record 5 must advance next_lsn to 6).
  let _t2 = append_raw(p, "5|2|11|0|0");
  var pt3 = wal_writer_new();
  let nt3 = segment_parse_into(p, &mut pt3);
  fails = check(nt3 == 5 && segment_last_lsn(p) == 5, "torn (complete tail): parsed as a valid record", fails);
  fails = check(segment_heal(p), "heal (complete tail): newline appended", fails);
  let _a5 = wal_writer_append_payload(&mut pt3, WalOpKind.Insert, 12, 0, Vec[Int].new());
  var ar4 = segment_append_sync(p, &pt3, 5);
  var n4: Int = -1;
  match ar4 { Ok(n) => { n4 = n; } Err(_) => {} }
  fails = check(n4 == 1 && segment_last_lsn(p) == 6, "complete tail: append continues at 6", fails);

  // ---- tolerant middle + gap ----
  let pg = "out/probe_wal_segment_gap.seg";
  let _rg = io.remove_file(pg);
  let _g1 = append_raw(pg, "1|1|1|0|0\n");
  let _g2 = append_raw(pg, "not a record at all\n");
  let _g3 = append_raw(pg, "2|1|2|0|0\n");
  let _g4 = append_raw(pg, "3|1|3|0|0\r\n");
  var pgg = wal_writer_new();
  let ng = segment_parse_into(pg, &mut pgg);
  fails = check(ng == 3, "tolerant: malformed middle line skipped; CRLF line parsed", fails);

  let ph = "out/probe_wal_segment_hole.seg";
  let _rh = io.remove_file(ph);
  let _h1 = append_raw(ph, "1|1|1|0|0\n");
  let _h2 = append_raw(ph, "2|1|2|0|0\n");
  let _h3 = append_raw(ph, "4|1|4|0|0\n");
  var phh = wal_writer_new();
  let nh = segment_parse_into(ph, &mut phh);
  fails = check(nh == 2, "gap: valid line with lsn hole stops replay (no silent skip)", fails);

  // ---- merge dedupe ----
  let pm = "out/probe_wal_segment_merge.seg";
  let _rm = io.remove_file(pm);
  var seg_ops = Vec[Int].new();
  seg_ops.push(1); seg_ops.push(2); seg_ops.push(3);
  var seg_keys = Vec[Int].new();
  seg_keys.push(20); seg_keys.push(21); seg_keys.push(22);
  var seg_vals = Vec[Int].new();
  seg_vals.push(0); seg_vals.push(0); seg_vals.push(0);
  var seg_pays = Vec[Vec[Int]].new();
  seg_pays.push(Vec[Int].new()); seg_pays.push(Vec[Int].new()); seg_pays.push(Vec[Int].new());
  var segw = writer_with(3, &seg_ops, &seg_keys, &seg_vals, &seg_pays);
  var mwr = segment_append_sync(pm, &segw, 0);
  match mwr { Ok(_) => {} Err(_) => {} }
  var base_ops = Vec[Int].new();
  base_ops.push(1); base_ops.push(2); base_ops.push(3);
  var base_keys = Vec[Int].new();
  base_keys.push(1); base_keys.push(2); base_keys.push(3);
  var base_vals = Vec[Int].new();
  base_vals.push(0); base_vals.push(0); base_vals.push(0);
  var base_pays = Vec[Vec[Int]].new();
  base_pays.push(Vec[Int].new()); base_pays.push(Vec[Int].new()); base_pays.push(Vec[Int].new());
  var base = writer_with(1, &base_ops, &base_keys, &base_vals, &base_pays);
  let nadd = segment_merge_into(pm, &mut base);
  fails = check(nadd == 2 && wal_writer_current_lsn(&base) == 5 && base.records[3].lsn == 4 && base.records[4].lsn == 5,
    "merge: dedupes lsn<=checkpoint, appends the delta", fails);

  let ph2 = "out/probe_wal_segment_merge2.seg";
  let _rh2 = io.remove_file(ph2);
  var gw = write_bytes(ph2, &slice.str_bytes("6|1|6|0|0\n7|1|7|0|0\n"));
  var base2 = writer_with(1, &base_ops, &base_keys, &base_vals, &base_pays);
  let nadd2 = segment_merge_into(ph2, &mut base2);
  fails = check(nadd2 == 0 && wal_writer_current_lsn(&base2) == 3, "merge: lsn gap stops (nothing appended)", fails);

  // ---- reset / missing ----
  fails = check(segment_reset(p) && segment_last_lsn(p) == 0, "reset: empties the segment", fails);
  fails = check(segment_last_lsn("out/probe_wal_segment_missing.seg") == 0, "missing file: last_lsn 0", fails);
  var pmiss = wal_writer_new();
  let nmiss = segment_parse_into("out/probe_wal_segment_missing.seg", &mut pmiss);
  fails = check(nmiss == 0, "missing file: parse 0", fails);

  // merge with no segment file at all
  var base3 = writer_with(1, &base_ops, &base_keys, &base_vals, &base_pays);
  let nadd3 = segment_merge_into("out/probe_wal_segment_missing2.seg", &mut base3);
  fails = check(nadd3 == 0, "merge: missing segment is a no-op", fails);

  // ---- Part C: engine durable mode (M-D5) ----
  let ck = "out/probe_wal_segment_eng.ckpt";
  let sg = "out/probe_wal_segment_eng.seg";
  let mf = "out/probe_wal_segment_eng.manifest";
  let _c1 = io.remove_file(ck);
  let _c2 = io.remove_file(sg);
  let _c3 = io.remove_file(mf);

  var eng = engine_new();
  var en_ok = false;
  match engine_enable_durable(&mut eng, sg) {
    Ok(_) => { en_ok = true; }
    Err(_) => {}
  }
  fails = check(en_ok, "engine: enable_durable creates the segment", fails);

  var cr = engine_create_collection(&mut eng, 4, DistanceMetric.Cosine);
  var created_ok = false;
  match cr { Ok(_) => { created_ok = true; } Err(_) => {} }
  fails = check(created_ok, "engine: create collection (durable)", fails);

  var v1 = Vector.new(4);
  v1.set(0, 1.0); v1.set(1, 0.0); v1.set(2, 0.0); v1.set(3, 0.0);
  var u1_ok = false;
  match engine_upsert(&mut eng, 1, v1) { Ok(_) => { u1_ok = true; } Err(_) => {} }
  fails = check(u1_ok, "engine: durable upsert ok", fails);
  fails = check(engine_synced_lsn(&eng) == engine_durable_lsn(&eng) && engine_synced_lsn(&eng) >= 2,
    "engine: commit advances the fsynced frontier", fails);
  fails = check(segment_last_lsn(sg) == engine_synced_lsn(&eng),
    "engine: segment holds every committed record", fails);

  var v2 = Vector.new(4);
  v2.set(0, 0.0); v2.set(1, 1.0); v2.set(2, 0.0); v2.set(3, 0.0);
  let _u2 = engine_upsert(&mut eng, 2, v2);
  fails = check(engine_synced_lsn(&eng) == engine_durable_lsn(&eng),
    "engine: frontier tracks each ack", fails);

  // Clean shutdown sequence: checkpoint persist + segment rotation.
  fails = check(wal_persist(&eng.wal, ck), "engine: checkpoint persist", fails);
  fails = check(segment_reset(sg), "engine: rotate segment after checkpoint", fails);

  var eng2 = engine_open_durable(ck, sg, mf, 4, DistanceMetric.Cosine);
  fails = check(engine_size(&eng2) == 2, "engine: reopen keeps the checkpointed points", fails);
  // Frontier semantics (fixed during L-4, probe_reopen_write): enable/reopen
  // adopts the SEGMENT FILE as the durable frontier -- the recovered log is
  // renumbered, so "aligned to the log" is not a valid relation; the truthful
  // one is frontier == the segment's last durable record (0 for a rotated
  // segment). The first commit re-serializes the renumbered block into the
  // segment, which the post-commit check below pins.
  fails = check(engine_synced_lsn(&eng2) == segment_last_lsn(sg),
    "engine: reopened frontier aligned to the segment file (durable truth)", fails);

  var v3 = Vector.new(4);
  v3.set(0, 0.0); v3.set(1, 0.0); v3.set(2, 1.0); v3.set(3, 0.0);
  let _u3 = engine_upsert(&mut eng2, 3, v3);
  fails = check(segment_last_lsn(sg) == engine_synced_lsn(&eng2) && engine_size(&eng2) == 3,
    "engine: post-reopen commit lands in the rotated segment", fails);

  // Crash before any checkpoint: segment-only recovery keeps every acked point.
  let ck2 = "out/probe_wal_segment_eng2.ckpt";
  let sg2 = "out/probe_wal_segment_eng2.seg";
  let _c4 = io.remove_file(ck2);
  let _c5 = io.remove_file(sg2);
  var eng3 = engine_new();
  match engine_enable_durable(&mut eng3, sg2) { Ok(_) => {} Err(_) => {} }
  let _cc = engine_create_collection(&mut eng3, 4, DistanceMetric.Cosine);
  let _a = engine_upsert(&mut eng3, 11, v1);
  let _b = engine_upsert(&mut eng3, 12, v2);
  let _d = engine_upsert(&mut eng3, 13, v3);
  var eng4 = engine_open_durable(ck2, sg2, "", 4, DistanceMetric.Cosine);
  fails = check(engine_size(&eng4) == 3,
    "engine: segment-only recovery (no checkpoint) keeps every acked point", fails);

  // Checkpoint + delta mix: point 4 is acked AFTER the persist, so only the
  // segment carries it; reopening with the segment yields all 4, without it
  // only the checkpointed 3 (the segment is load-bearing).
  fails = check(wal_persist(&eng3.wal, ck2), "engine: second checkpoint persist", fails);
  var v4 = Vector.new(4);
  v4.set(0, 0.5); v4.set(1, 0.5); v4.set(2, 0.5); v4.set(3, 0.5);
  let _e = engine_upsert(&mut eng3, 14, v4);
  var eng5 = engine_open_durable(ck2, sg2, "", 4, DistanceMetric.Cosine);
  fails = check(engine_size(&eng5) == 4, "engine: checkpoint + delta merge keeps all points", fails);
  var eng6 = engine_open_durable(ck2, "out/probe_wal_segment_eng2_none.seg", "", 4, DistanceMetric.Cosine);
  fails = check(engine_size(&eng6) == 3, "engine: checkpoint alone lacks the una-checkpointed delta (segment is load-bearing)", fails);

  io.println("probe_wal_segment: " + convert.int_to_string(fails) + " failures");
  return fails;
}
