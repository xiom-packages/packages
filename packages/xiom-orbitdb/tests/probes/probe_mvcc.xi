// XIOM ORBITDB -- M3 minimal-subset probe: snapshot pins + savepoints.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scenarios (all in one process; docs/MVCC.md is the design):
//   A. Three pins over 600 seeded churn ops and two mid-flight checkpoints
//      (order 3: heavy split/merge traffic); every pin must read its exact
//      model after the churn, survives another pin's release, and the live
//      tree/reopen must match the live model.
//   B. Compaction deferral: a pin held across 80 checkpoints drives the page
//      log past node_count + 64; the compaction branch must defer (counter)
//      while the log grows, the pinned view must stay intact, and one
//      checkpoint after the release must compact (log shrinks).
//   C. Savepoint matrix across reopen "crashes": pre-marker keep, empty
//      marker, double restore, abort with a marker open, and an abandoned
//      (uncommitted) window after a restore.
//   D. Typed payload pins across an overwrite, a delete, and a checkpoint.
//
// Env: ORBITDB_MVCC_DIR (default probe-logs). Exit: 0 = GREEN, 1 = checks
// failed (count printed).

module orbitdb_probe_mvcc

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.db.engine;
use xiom.db.storage.page_file;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name);
  return fails + 1;
}

fn mv_copy(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Model lookup table: slot k holds key k's value, or -1 when absent.
fn mv_model_new(n: Int) -> Vec[Int] {
  var m = Vec[Int].new();
  var i = 0;
  while i <= n {
    m.push(-1);
    i = i + 1;
  }
  return m;
}

// Expected VALUES for keys [1, n] in key order, from a model table.
fn mv_expected(m: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 1;
  while i < m.len() {
    if m[i] >= 0 { out.push(m[i]); }
    i = i + 1;
  }
  return out;
}

fn mv_vec_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn mv_cleanup(path: Str) {
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");
}

fn mv_row(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn run_pin_churn(path: Str) -> Int {
  mv_cleanup(path);
  var fails = 0;
  var db = db_file_open(path, 3);
  var model = mv_model_new(80);
  var i = 1;
  while i <= 40 {
    if !db_file_put(&mut db, i, i * 7) { return fails + 1; }
    model[i] = i * 7;
    i = i + 1;
  }
  let s1 = db_file_snapshot_begin(&mut db);
  var m1 = mv_copy(&model);
  var s2_id = 0;
  var m2 = mv_model_new(80);
  var s3_id = 0;
  var m3 = mv_model_new(80);
  var r = 4242;
  var op = 0;
  while op < 600 {
    r = (r * 1103515245 + 12345) % 2147483648;
    let key = (r % 80) + 1;
    let roll = (r / 80) % 5;
    if roll == 0 {
      let _ = db_file_delete(&mut db, key);
      model[key] = -1;
    } else {
      let v = r % 900;
      if !db_file_put(&mut db, key, v) { return fails + 2; }
      model[key] = v;
    }
    if op == 150 {
      if db_file_checkpoint(&mut db) < 0 { return fails + 3; }
    }
    if op == 200 {
      let s = db_file_snapshot_begin(&mut db);
      s2_id = s.id;
      m2 = mv_copy(&model);
    }
    if op == 400 {
      let s = db_file_snapshot_begin(&mut db);
      s3_id = s.id;
      m3 = mv_copy(&model);
    }
    if op == 450 {
      if db_file_checkpoint(&mut db) < 0 { return fails + 4; }
    }
    op = op + 1;
  }
  fails = check(db_file_snapshot_pins(&db) == 3, "A: three pins live", fails);
  let w1 = mv_expected(&m1);
  let g1 = db_file_snapshot_range(&db, s1.id, 1, 80);
  fails = check(mv_vec_eq(&g1, &w1), "A: pin-1 exact after 600 ops + 2 checkpoints", fails);
  fails = check(db_file_snapshot_count(&db, s1.id) == w1.len(), "A: pin-1 count", fails);
  let w2 = mv_expected(&m2);
  let g2 = db_file_snapshot_range(&db, s2_id, 1, 80);
  fails = check(mv_vec_eq(&g2, &w2), "A: pin-2 exact", fails);
  let w3 = mv_expected(&m3);
  let g3 = db_file_snapshot_range(&db, s3_id, 1, 80);
  fails = check(mv_vec_eq(&g3, &w3), "A: pin-3 exact", fails);
  let wl = mv_expected(&model);
  let gl = db_file_range(&db, 1, 80);
  fails = check(mv_vec_eq(&gl, &wl), "A: live tree == live model", fails);
  fails = check(db_file_snapshot_end(&mut db, s2_id), "A: release pin 2", fails);
  let g1b = db_file_snapshot_range(&db, s1.id, 1, 80);
  fails = check(mv_vec_eq(&g1b, &w1), "A: pin-1 unaffected by release", fails);
  fails = check(db_file_min_pinned_lsn(&db) >= 0, "A: min pinned lsn while pinned", fails);
  if db_file_checkpoint(&mut db) < 0 { return fails + 5; }
  var db2 = db_file_open(path, 3);
  let ga = db_file_range(&db2, 1, 80);
  fails = check(mv_vec_eq(&ga, &wl), "A: reopen == live model", fails);
  fails = check(db_file_snapshot_pins(&db2) == 0, "A: pins vanish on reopen", fails);
  fails = check(db_file_min_pinned_lsn(&db2) == -1, "A: no pins after reopen", fails);
  mv_cleanup(path);
  return fails;
}

fn run_compaction_deferral(path: Str) -> Int {
  mv_cleanup(path);
  var fails = 0;
  // v1 page-log compaction mechanics (entry counting): explicit v1 handle
  // after the M1.2 S4 default flip (db_file_open now defaults to v2).
  var db = db_file_open_cfg(path, 4, 1);
  var i = 1;
  while i <= 24 {
    if !db_file_put(&mut db, i, i * 10) { return fails + 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return fails + 2; }
  let snap_path = path + ".snap";
  let pf0 = page_file_open(snap_path);
  let entries0 = page_log_len(&pf0);
  let s1 = db_file_snapshot_begin(&mut db);
  var loop = 0;
  while loop < 80 {
    if !db_file_put(&mut db, 100 + loop, loop) { return fails + 3; }
    if db_file_checkpoint(&mut db) < 0 { return fails + 4; }
    loop = loop + 1;
  }
  let deferred = db_file_compaction_deferrals(&db);
  fails = check(deferred > 0, "B: compaction deferred while pinned", fails);
  let pf1 = page_file_open(snap_path);
  let entries1 = page_log_len(&pf1);
  fails = check(entries1 > entries0 + 64, "B: page log grew past the slack", fails);
  fails = check(db_file_snapshot_count(&db, s1.id) == 24, "B: pinned count intact", fails);
  match db_file_snapshot_get(&db, s1.id, 1) {
    None => { fails = check(false, "B: pinned key 1 intact", fails); }
    Some(v) => { fails = check(v == 10, "B: pinned key 1 intact", fails); }
  }
  fails = check(db_file_size(&db) == 104, "B: live size 104", fails);
  fails = check(db_file_snap_generation(&db) == 81, "B: 81 checkpoints committed", fails);
  fails = check(db_file_snapshot_end(&mut db, s1.id), "B: release the pin", fails);
  if db_file_checkpoint(&mut db) < 0 { return fails + 5; }
  let pf2 = page_file_open(snap_path);
  let entries2 = page_log_len(&pf2);
  fails = check(entries2 < entries1, "B: log shrank after release (compaction ran)", fails);
  fails = check(db_file_compaction_deferrals(&db) == deferred, "B: deferral count frozen after release", fails);
  var db2 = db_file_open(path, 4);
  fails = check(db_file_size(&db2) == 104, "B: reopen size 104", fails);
  fails = check(db_file_snap_generation(&db2) == 82, "B: reopen generation 82", fails);
  match db_file_get(&db2, 179) {
    None => { fails = check(false, "B: reopen key 179", fails); }
    Some(v) => { fails = check(v == 79, "B: reopen key 179", fails); }
  }
  mv_cleanup(path);
  return fails;
}

fn run_savepoint_matrix(path: Str) -> Int {
  mv_cleanup(path);
  var fails = 0;
  // C1: pre-marker ops survive a restore; post-marker ops are discarded.
  var db = db_file_open(path, 4);
  if !db_file_txn_begin(&mut db) { return fails + 1; }
  if !db_file_txn_put(&mut db, 1, 10) { return fails + 2; }
  if !db_file_txn_savepoint(&mut db) { return fails + 3; }
  if !db_file_txn_put(&mut db, 2, 20) { return fails + 4; }
  if !db_file_txn_savepoint_restore(&mut db) { return fails + 5; }
  if !db_file_txn_commit(&mut db) { return fails + 6; }
  var db1 = db_file_open(path, 4);
  fails = check(db_file_size(&db1) == 1, "C1: only the pre-marker op committed", fails);
  match db_file_get(&db1, 1) {
    None => { fails = check(false, "C1: key 1 present", fails); }
    Some(_) => { fails = check(true, "C1: key 1 present", fails); }
  }
  match db_file_get(&db1, 2) {
    None => { fails = check(true, "C1: key 2 discarded", fails); }
    Some(_) => { fails = check(false, "C1: key 2 discarded", fails); }
  }
  // C2: empty marker -- a restore with nothing kept commits nothing.
  if !db_file_txn_begin(&mut db1) { return fails + 7; }
  if !db_file_txn_savepoint(&mut db1) { return fails + 8; }
  if !db_file_txn_put(&mut db1, 3, 30) { return fails + 9; }
  if !db_file_txn_savepoint_restore(&mut db1) { return fails + 10; }
  if !db_file_txn_commit(&mut db1) { return fails + 11; }
  var db2 = db_file_open(path, 4);
  fails = check(db_file_size(&db2) == 1, "C2: empty-marker restore commits nothing", fails);
  // C3: double restore, then more ops; only the final marker set commits.
  if !db_file_txn_begin(&mut db2) { return fails + 12; }
  if !db_file_txn_put(&mut db2, 4, 40) { return fails + 13; }
  if !db_file_txn_savepoint(&mut db2) { return fails + 14; }
  if !db_file_txn_put(&mut db2, 5, 50) { return fails + 15; }
  if !db_file_txn_savepoint_restore(&mut db2) { return fails + 16; }
  if !db_file_txn_put(&mut db2, 6, 60) { return fails + 17; }
  if !db_file_txn_savepoint_restore(&mut db2) { return fails + 18; }
  if !db_file_txn_put(&mut db2, 7, 70) { return fails + 19; }
  if !db_file_txn_commit(&mut db2) { return fails + 20; }
  var db3 = db_file_open(path, 4);
  fails = check(db_file_size(&db3) == 3, "C3: keys 1 + {4,7} committed", fails);
  // C4: abort with a marker left open; the marker is cleared.
  if !db_file_txn_begin(&mut db3) { return fails + 21; }
  if !db_file_txn_put(&mut db3, 8, 80) { return fails + 22; }
  if !db_file_txn_savepoint(&mut db3) { return fails + 23; }
  if !db_file_txn_put(&mut db3, 9, 90) { return fails + 24; }
  if !db_file_txn_abort(&mut db3) { return fails + 25; }
  fails = check(!db_file_txn_savepoint_active(&db3), "C4: abort clears the marker", fails);
  // C5: crash (abandoned window) after a restore -- nothing applies.
  if !db_file_txn_begin(&mut db3) { return fails + 26; }
  if !db_file_txn_put(&mut db3, 10, 100) { return fails + 27; }
  if !db_file_txn_savepoint(&mut db3) { return fails + 28; }
  if !db_file_txn_put(&mut db3, 11, 110) { return fails + 29; }
  if !db_file_txn_savepoint_restore(&mut db3) { return fails + 30; }
  var db4 = db_file_open(path, 4);
  fails = check(db_file_size(&db4) == 3, "C5: uncommitted window discarded on crash", fails);
  match db_file_get(&db4, 8) {
    None => { fails = check(true, "C5: aborted key 8 gone", fails); }
    Some(_) => { fails = check(false, "C5: aborted key 8 gone", fails); }
  }
  mv_cleanup(path);
  return fails;
}

fn run_typed_pins(path: Str) -> Int {
  mv_cleanup(path);
  var fails = 0;
  var db = db_file_open(path, 4);
  if !db_file_put_typed(&mut db, 7, mv_row(1, 2, 3)) { return fails + 1; }
  let s1 = db_file_snapshot_begin(&mut db);
  if !db_file_put_typed(&mut db, 7, mv_row(9, 9, 9)) { return fails + 2; }
  if !db_file_put_typed(&mut db, 8, mv_row(4, 5, 6)) { return fails + 3; }
  if !db_file_delete(&mut db, 8) { return fails + 4; }
  if db_file_checkpoint(&mut db) < 0 { return fails + 5; }
  match db_file_snapshot_get_typed(&db, s1.id, 7) {
    None => { fails = check(false, "D: pinned payload reads", fails); }
    Some(p) => {
      var ok = p.len() == 3;
      if ok { ok = p[0] == 1; }
      if ok { ok = p[2] == 3; }
      fails = check(ok, "D: pinned payload reads", fails);
    }
  }
  match db_file_snapshot_get_typed(&db, s1.id, 8) {
    None => { fails = check(true, "D: pin predates key 8", fails); }
    Some(_) => { fails = check(false, "D: pin predates key 8", fails); }
  }
  match db_file_get_typed(&db, 7) {
    None => { fails = check(false, "D: live payload updated", fails); }
    Some(p) => {
      var ok = p.len() == 3;
      if ok { ok = p[0] == 9; }
      fails = check(ok, "D: live payload updated", fails);
    }
  }
  fails = check(db_file_size(&db) == 1, "D: live size 1 after delete", fails);
  mv_cleanup(path);
  return fails;
}

fn main() -> Int {
  let dir = env.var_or("ORBITDB_MVCC_DIR", "probe-logs");
  let base = dir + "/mvcc";
  io.println("mvcc probe: A pins vs churn, B compaction deferral, C savepoint matrix, D typed pins");
  var fails: Int = 0;
  fails = fails + run_pin_churn(base + "-a.wal");
  fails = fails + run_compaction_deferral(base + "-b.wal");
  fails = fails + run_savepoint_matrix(base + "-c.wal");
  fails = fails + run_typed_pins(base + "-d.wal");
  if fails == 0 { io.println("mvcc: GREEN"); return 0; }
  io.println("mvcc: RED fails=" + convert.int_to_string(fails));
  return 1;
}
