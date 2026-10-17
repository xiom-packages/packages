// XIOM ORBITDB -- fault-injector probe for the durability API (M2.1 first
// half). Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Exercises the env-armed fault layer (src/storage/fault.xi + the byte_io
// gates) end to end. All scenarios run in ONE process: each arms via
// `env.set_var` + `fault_reset`, then disarms with `remove_var` +
// `fault_reset`, so the scenarios are independent.
//
//   A. put-latch: syncfail on a put ack -> false + latched handle; every
//      writer refuses; reopen recovers the record (WAL-before-ack).
//   B. delete-latch: same shape for delete; reopen applies the recorded
//      delete (the key is gone; the other key stays).
//   E. typed-latch (M5.3): syncfail on a typed put ack -> the tagged WAL
//      record stays, reopen recovers the payload + int mirror.
//   C. checkpoint 2PC pre-sync failure: two_phase flushes the WAL BEFORE the
//      snapshot publishes; a failing pre-sync latches the handle with the
//      snapshot file untouched and the WAL untruncated; reopen replays the
//      tail and a later 2PC checkpoint succeeds.
//   D. block store partial writes: torn page append is invisible after
//      reopen (no commit); a full rewrite repairs it; a torn update keeps
//      the previous committed version; a torn header slot falls back to the
//      previous generation; a later commit republishes.
//
// Env (paths only): ORBITDB_FAULT_DB (engine WAL, default
// probe-logs/fault-sync.wal), ORBITDB_FAULT_CKPT_DB (checkpoint scenario),
// ORBITDB_FAULT_BLOCK (block store). Exit: 0 = all checks passed, 1 = failed.
//
// Naming: the helper below is `arm` (reverted from the C-ORBIT-07 workaround
// name `probe_arm` on 2026-10-12). A consumer-defined `arm` used to silently
// hijack `fault.xi`'s private `arm()`; m261/m262 fixed module-local call
// precedence in v0.64.4, the bundle printed `svc: private arm() ran` on both
// platforms, and this probe runs the original collision shape as the
// real-world validation. Also: never pass an empty value to `env.set_var`
// (the stdlib cstr contract rejects it).

module orbitdb_probe_fault_sync

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.db.engine;
use xiom.db.storage.block;
use xiom.db.storage.block_store;
use xiom.db.storage.byte_io;
use xiom.db.storage.fault;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name);
  return fails + 1;
}

fn vec_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

// Arm the injector: the `at`-th op of the mode's kind fires (kind 1 = sync
// for syncfail, kind 0 = write-ish otherwise); `fault_reset` re-virgins.
// An empty `tail` UNSETS the variable (env.set_var with "" trips the stdlib
// cstr contract -- empty values cannot form a C string).
fn arm(at: Str, mode: Str, tail: Str) {
  env.set_var("ORBITDB_FAULT_AT", at);
  env.set_var("ORBITDB_FAULT_MODE", mode);
  if tail.len() > 0 {
    env.set_var("ORBITDB_FAULT_TAIL", tail);
  } else {
    env.remove_var("ORBITDB_FAULT_TAIL");
  }
  fault_reset();
}

fn disarm() {
  env.remove_var("ORBITDB_FAULT_AT");
  env.remove_var("ORBITDB_FAULT_MODE");
  env.remove_var("ORBITDB_FAULT_TAIL");
  fault_reset();
}

fn payload3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn header_for(generation: Int) -> BlockHeader {
  return BlockHeader{
    root: 1,
    order: 4,
    node_count: 1,
    checkpoint_lsn: 0,
    committed_generation: generation,
    block_count: 0,
    next_page_id: 64,
  };
}

// ===========================================================================
// A + B: engine latch on put / delete
// ===========================================================================

fn run_engine_latch(path: Str) -> Int {
  let snap = path + ".snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  var fails: Int = 0;

  var db = db_file_open(path, 4);
  fails = check(db_file_put(&mut db, 1, 10), "A: baseline put acks", fails);

  arm("1", "syncfail", "");
  fails = check(!db_file_put(&mut db, 2, 20), "A: put with failing ack sync reports false", fails);
  fails = check(db_file_failed(&db), "A: handle latched", fails);
  fails = check(!db_file_put(&mut db, 3, 30), "A: latched put refuses", fails);
  fails = check(!db_file_delete(&mut db, 1), "A: latched delete refuses", fails);
  fails = check(!db_file_txn_begin(&mut db), "A: latched txn_begin refuses", fails);
  fails = check(db_file_checkpoint(&mut db) == -1, "A: latched checkpoint refuses (-1)", fails);
  fails = check(!db_file_flush(&mut db), "A: latched flush refuses", fails);
  disarm();

  var db2 = db_file_open(path, 4);
  fails = check(!db_file_failed(&db2), "A: reopen is not latched", fails);
  fails = check(db_file_size(&db2) == 2, "A: reopen recovered both records", fails);
  match db_file_get(&db2, 2) {
    Some(v) => { fails = check(v == 20, "A: recovered value of the latched put", fails); }
    None => { fails = check(false, "A: recovered value of the latched put", fails); }
  }

  // B: the delete record was logged before the failed ack too.
  arm("1", "syncfail", "");
  fails = check(!db_file_delete(&mut db2, 1), "B: delete with failing ack sync reports false", fails);
  fails = check(db_file_failed(&db2), "B: handle latched after delete", fails);
  disarm();

  var db3 = db_file_open(path, 4);
  fails = check(db_file_size(&db3) == 1, "B: reopen applied the recorded delete", fails);
  match db_file_get(&db3, 1) {
    Some(_) => { fails = check(false, "B: deleted key stays gone", fails); }
    None => { fails = check(true, "B: deleted key stays gone", fails); }
  }
  match db_file_get(&db3, 2) {
    Some(v) => { fails = check(v == 20, "B: surviving key intact", fails); }
    None => { fails = check(false, "B: surviving key intact", fails); }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return fails;
}

// ===========================================================================
// C: checkpoint two-phase pre-sync failure
// ===========================================================================

fn run_ckpt_2pc(path_in: Str) -> Int {
  let path = path_in;
  let snap = path + ".snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  var fails: Int = 0;

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 4 {
    if !db_file_put(&mut db, i, i * 10) { return fails + 100; }
    i = i + 1;
  }
  let ck1 = db_file_checkpoint(&mut db);
  fails = check(ck1 >= 0, "C: first checkpoint commits", fails);
  let snap1 = byteio_file_size(snap);
  fails = check(snap1 > 0, "C: snapshot file exists after the first checkpoint", fails);

  i = 5;
  while i <= 8 {
    if !db_file_put(&mut db, i, i * 10) { return fails + 200; }
    i = i + 1;
  }
  let wal1 = byteio_file_size(path);
  fails = check(db_file_set_two_phase(&mut db, true), "C: two_phase enabled", fails);

  // The checkpoint's first sync is the 2PC pre-flush; it fails before any
  // snapshot byte is written and before the WAL truncate.
  arm("1", "syncfail", "");
  let ck2 = db_file_checkpoint(&mut db);
  fails = check(ck2 == -1, "C: checkpoint with failing pre-sync returns -1", fails);
  fails = check(db_file_failed(&db), "C: handle latched", fails);
  fails = check(byteio_file_size(snap) == snap1, "C: snapshot file size unchanged", fails);
  fails = check(byteio_file_size(path) == wal1, "C: WAL not truncated", fails);
  disarm();

  var db2 = db_file_open(path, 4);
  fails = check(!db_file_failed(&db2), "C: reopen is not latched", fails);
  fails = check(db_file_size(&db2) == 8, "C: reopen replays the untruncated tail (8 keys)", fails);
  match db_file_get(&db2, 5) {
    Some(v) => { fails = check(v == 50, "C: tail key 5 recovered", fails); }
    None => { fails = check(false, "C: tail key 5 recovered", fails); }
  }
  match db_file_get(&db2, 8) {
    Some(v) => { fails = check(v == 80, "C: tail key 8 recovered", fails); }
    None => { fails = check(false, "C: tail key 8 recovered", fails); }
  }

  // A later 2PC checkpoint on the recovered handle succeeds.
  fails = check(db_file_set_two_phase(&mut db2, true), "C: two_phase re-enabled on reopen", fails);
  let ck3 = db_file_checkpoint(&mut db2);
  fails = check(ck3 >= 0, "C: recovery checkpoint commits", fails);
  var db3 = db_file_open(path, 4);
  fails = check(db_file_size(&db3) == 8, "C: post-checkpoint reopen still has 8 keys", fails);

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return fails;
}

// ===========================================================================
// E: typed rows (M5.3) -- syncfail on a typed put's ack: the tagged WAL
// record (subtype 1 + row bytes) landed, the ack did not; reopen must
// recover the payload, and the latched handle refuses further typed writes.
// ===========================================================================

fn run_typed_latch(path: Str) -> Int {
  let snap = path + ".snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  var fails: Int = 0;

  var db = db_file_open(path, 4);
  var base = Vec[Int].new();
  base.push(1);
  base.push(2);
  base.push(3);
  fails = check(db_file_put_typed(&mut db, 1, base), "E: baseline typed put acks", fails);

  var row = Vec[Int].new();
  row.push(42);
  row.push(43);
  arm("1", "syncfail", "");
  fails = check(!db_file_put_typed(&mut db, 2, row), "E: typed put with failing ack sync reports false", fails);
  fails = check(db_file_failed(&db), "E: handle latched", fails);
  fails = check(!db_file_put_typed(&mut db, 3, row), "E: latched typed put refuses", fails);
  disarm();

  var db2 = db_file_open(path, 4);
  fails = check(!db_file_failed(&db2), "E: reopen is not latched", fails);
  fails = check(db_file_size(&db2) == 2, "E: reopen recovered both typed records", fails);
  match db_file_get_typed(&db2, 2) {
    Some(p) => {
      fails = check(p.len() == 2 && p[0] == 42 && p[1] == 43,
        "E: recovered payload of the latched typed put", fails);
    }
    None => { fails = check(false, "E: recovered payload of the latched typed put", fails); }
  }
  match db_file_get(&db2, 2) {
    Some(v) => { fails = check(v == 2, "E: recovered int mirror (value == pk)", fails); }
    None => { fails = check(false, "E: recovered int mirror (value == pk)", fails); }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return fails;
}

// ===========================================================================
// D: block store partial writes (torn page append / update / header slot)
// ===========================================================================

fn run_block_partial(path: Str) -> Int {
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".tmp");
  var fails: Int = 0;

  let p1 = payload3(1, 1, 1);
  let p2 = payload3(2, 2, 2);
  let p3 = payload3(3, 3, 3);
  let p9 = payload3(9, 9, 9);

  var bs = block_store_open(path);
  let i1 = block_store_put(&mut bs, 1, 1, &p1);
  let i2 = block_store_put(&mut bs, 1, 2, &p2);
  let h1 = header_for(1);
  fails = check(i1 >= 0 && i2 >= 0 && block_store_commit(&mut bs, &h1),
    "D: seed store committed (gen 1, pages 1-2)", fails);

  // Torn append: the write reports the shrunken byte count as success, but
  // the block never lands whole. No commit follows (crash shape).
  arm("1", "partial", "100");
  let i3 = block_store_put(&mut bs, 2, 3, &p3);
  fails = check(i3 >= 0, "D: torn append reports an index (shrunken write)", fails);
  match block_store_read(&bs, 3) {
    Some(_) => { fails = check(false, "D: torn page unreadable in-process (short file)", fails); }
    None => { fails = check(true, "D: torn page unreadable in-process (short file)", fails); }
  }
  disarm();

  var bs2 = block_store_open(path);
  fails = check(bs2.committed && bs2.header.committed_generation == 1,
    "D: reopen after torn append keeps gen 1", fails);
  fails = check(block_store_count(&bs2) == 2 && !block_store_has(&bs2, 3),
    "D: torn page invisible after reopen", fails);

  // Repair: write page 3 whole + commit gen 2.
  let i3b = block_store_put(&mut bs2, 2, 3, &p3);
  fails = check(i3b >= 0 && block_store_commit(&mut bs2, &header_for(2)),
    "D: repair commit gen 2", fails);
  var bs3 = block_store_open(path);
  fails = check(block_store_count(&bs3) == 3 && block_store_has(&bs3, 3),
    "D: repaired page visible after reopen", fails);

  // Torn update of page 1 at gen 3 (no commit): the committed gen-2 view
  // must keep the old payload.
  arm("1", "partial", "100");
  let i4 = block_store_put(&mut bs3, 3, 1, &p9);
  fails = check(i4 >= 0, "D: torn update reports an index", fails);
  disarm();
  var bs4 = block_store_open(path);
  fails = check(bs4.header.committed_generation == 2, "D: reopen after torn update keeps gen 2", fails);
  match block_store_read(&bs4, 1) {
    Some(p) => {
      fails = check(p.generation == 1 && vec_eq(&p.payload, &p1),
        "D: page 1 keeps the old committed version", fails);
    }
    None => { fails = check(false, "D: page 1 keeps the old committed version", fails); }
  }

  // Repair the update: full write + commit gen 3.
  let i4b = block_store_put(&mut bs4, 3, 1, &p9);
  fails = check(i4b >= 0 && block_store_commit(&mut bs4, &header_for(3)),
    "D: repair commit gen 3", fails);
  var bs5 = block_store_open(path);
  match block_store_read(&bs5, 1) {
    Some(p) => {
      fails = check(p.generation == 3 && vec_eq(&p.payload, &p9),
        "D: repaired update visible after reopen", fails);
    }
    None => { fails = check(false, "D: repaired update visible after reopen", fails); }
  }

  // Torn header slot: the commit's slot write is cut inside the 40-byte
  // block header (the payload region keeps the PREVIOUS header's bytes), so
  // the slot must fail its decode/CRC and the previous slot must win.
  arm("1", "partial", "40");
  let torn_commit = block_store_commit(&mut bs5, &header_for(4));
  fails = check(torn_commit, "D: torn header write reports success", fails);
  disarm();
  var bs6 = block_store_open(path);
  fails = check(bs6.committed && bs6.header.committed_generation == 3,
    "D: reopen falls back to the previous header (gen 3)", fails);
  fails = check(block_store_count(&bs6) == 3, "D: fallback keeps all pages", fails);

  // Recovery commit republishes a full header.
  fails = check(block_store_commit(&mut bs6, &header_for(4)),
    "D: recovery commit gen 4", fails);
  var bs7 = block_store_open(path);
  fails = check(bs7.header.committed_generation == 4 && block_store_count(&bs7) == 3,
    "D: reopen sees gen 4 with all pages", fails);
  match block_store_read(&bs7, 1) {
    Some(p) => { fails = check(vec_eq(&p.payload, &p9), "D: payloads intact under gen 4", fails); }
    None => { fails = check(false, "D: payloads intact under gen 4", fails); }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".tmp");
  return fails;
}

fn main() -> Int {
  let db = env.var_or("ORBITDB_FAULT_DB", "probe-logs/fault-sync.wal");
  let ckpt_db = env.var_or("ORBITDB_FAULT_CKPT_DB", "probe-logs/fault-sync-ckpt.wal");
  let block = env.var_or("ORBITDB_FAULT_BLOCK", "probe-logs/fault-block.bv2");
  disarm(); // never inherit an armed injector
  io.println("fault-sync probe: A/B engine latch, E typed latch, C checkpoint 2PC, D block partial");
  var fails: Int = 0;
  fails = fails + run_engine_latch(db);
  fails = fails + run_typed_latch(db + ".typed");
  fails = fails + run_ckpt_2pc(ckpt_db);
  fails = fails + run_block_partial(block);
  if fails == 0 { io.println("fault-sync: GREEN"); return 0; }
  io.println("fault-sync: RED fails=" + convert.int_to_string(fails));
  return 1;
}

