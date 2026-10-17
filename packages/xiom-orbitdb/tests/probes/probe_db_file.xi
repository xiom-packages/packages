// XIOM ORBITDB -- file-backed database probe (WAL-before-ack + recovery).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Acceptance for the DBFile facade in src/engine.xi, driven by
// scripts/db_crash_test.ps1/.sh: writer puts N keys through the durable WAL,
// the harness hard-kills it, leaves a torn tail, then reopens (replay) and
// verifies the recovered state, then upserts one more key.
//
// Env:
//   ORBITDB_DB_FILE      WAL segment path (required)
//   ORBITDB_DB_MODE      write | verify | put1 | ckpt | qverify | soak | txn
//                        (default: verify)
//   ORBITDB_DB_N         key count for write / verify / ckpt   (default: 20)
//   ORBITDB_DB_TAIL      ckpt mode: keys appended AFTER the checkpoint (default 0)
//   ORBITDB_DB_CKPT_EVERY soak mode: maybe_checkpoint record limit (default 250)
//   ORBITDB_DB_TXN_COUNT  txn mode: keys written inside the transaction (default 5)
//   ORBITDB_DB_TXN_COMMIT txn mode: "0" leaves the txn pending, "1" commits (default 1)
//   ORBITDB_DB_LAST_KEY  optional: key to assert after recovery
//   ORBITDB_DB_LAST_VAL  optional: expected value for LAST_KEY
//   ORBITDB_DB_FORMAT    snapshot container for WRITES: "v1" (default) |
//                        "v2" (byte blocks, M1.2 S3); reads always
//                        auto-detect the on-disk format.
//
// Exit: 0 = succeeded, 1 = check failed, 2 = bad env.

module orbitdb_probe_db_file

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.db.engine;

// Open honoring ORBITDB_DB_FORMAT (writes only; reads auto-detect). Both
// branches are explicit since the M1.2 S4 flip: db_file_open now defaults to
// v2, while this probe keeps v1 as its default scenario for crash-matrix
// continuity (the engine's own default is v2).
fn open_db(path: Str, order: Int) -> DBFile {
  if env.var_or("ORBITDB_DB_FORMAT", "v1") == "v2" {
    return db_file_open_cfg(path, order, 2);
  }
  return db_file_open_cfg(path, order, 1);
}

fn run_write(path: Str, n: Int) -> Int {
  var db = open_db(path, 4);
  var i = 1;
  while i <= n {
    if !db_file_put(&mut db, i, i * 10) {
      io.println("writer: put failed at " + convert.int_to_string(i));
      return 1;
    }
    i = i + 1;
  }
  let flushed = db_file_flush(&mut db);
  if !flushed { io.println("writer: flush failed"); return 1; }
  io.println("writer: put " + convert.int_to_string(n));
  // Hang until the harness hard-kills us (crash simulation).
  var alive = true;
  while alive {
    io.sleep(1000);
  }
  return 0;
}

fn run_verify(path: Str, n: Int) -> Int {
  var db = open_db(path, 4);
  let size = db_file_size(&db);
  io.println("verify: recovered=" + convert.int_to_string(size) + " lsn=" + convert.int_to_string(db_file_last_lsn(&db)));
  if size != n {
    io.println("verify: expected " + convert.int_to_string(n) + " got " + convert.int_to_string(size));
    return 1;
  }
  let v1 = db_file_get(&db, 1);
  match v1 {
    None => { io.println("verify: key 1 missing"); return 1; }
    Some(x) => { if x != 10 { io.println("verify: key 1 wrong"); return 1; } }
  }
  let lk = env.var_or("ORBITDB_DB_LAST_KEY", "");
  if lk == "" {
    // Sequential phase (keys 1..N): the Nth key must be N*10.
    let vn = db_file_get(&db, n);
    match vn {
      None => { io.println("verify: key N missing"); return 1; }
      Some(x) => { if x != n * 10 { io.println("verify: key N wrong"); return 1; } }
    }
  }
  if lk != "" {
    match parse.parse_int(lk) {
      Ok(k) => {
        match parse.parse_int(env.var_or("ORBITDB_DB_LAST_VAL", "0")) {
          Ok(want) => {
            let got = db_file_get(&db, k);
            match got {
              None => { io.println("verify: last key missing"); return 1; }
              Some(v) => { if v != want { io.println("verify: last value wrong"); return 1; } }
            }
          }
          Err(_) => { return 2; }
        }
      }
      Err(_) => { return 2; }
    }
  }
  io.println("verify: OK n=" + convert.int_to_string(n));
  return 0;
}

// Query-after-recovery: the recovered handle must answer key-range and
// value-filter queries correctly. The checks hold for every scenario shape
// (WAL-only, snapshot-only, snapshot+tail) and are independent of the
// optional 9999/99990 probe key (it sorts last, past every checked window).
fn run_qverify(path: Str, n: Int) -> Int {
  var db = open_db(path, 4);

  // Key range [3, 6] -> values 30..60 in key order.
  let r = db_file_range(&db, 3, 6);
  if r.len() != 4 { io.println("qverify: range len"); return 1; }
  if r[0] != 30 { io.println("qverify: range 0"); return 1; }
  if r[1] != 40 { io.println("qverify: range 1"); return 1; }
  if r[2] != 50 { io.println("qverify: range 2"); return 1; }
  if r[3] != 60 { io.println("qverify: range 3"); return 1; }

  // Last sequential key: range [n, n] -> n*10.
  let rn = db_file_range(&db, n, n);
  if rn.len() != 1 { io.println("qverify: range n len"); return 1; }
  if rn[0] != n * 10 { io.println("qverify: range n value"); return 1; }

  // Value filter: >= 10, offset 2, limit 3 -> [30, 40, 50].
  var q = query_new();
  query_where(&mut q, QueryOp.Gte, 10);
  query_offset(&mut q, 2);
  query_limit(&mut q, 3);
  let f = db_file_query(&db, &q);
  if f.len() != 3 { io.println("qverify: filter len"); return 1; }
  if f[0] != 30 { io.println("qverify: filter 0"); return 1; }
  if f[1] != 40 { io.println("qverify: filter 1"); return 1; }
  if f[2] != 50 { io.println("qverify: filter 2"); return 1; }

  // Value filter: < 30 -> [10, 20].
  var q2 = query_new();
  query_where(&mut q2, QueryOp.Lt, 30);
  let s = db_file_query(&db, &q2);
  if s.len() != 2 { io.println("qverify: lt len"); return 1; }
  if s[0] != 10 { io.println("qverify: lt 0"); return 1; }
  if s[1] != 20 { io.println("qverify: lt 1"); return 1; }

  io.println("qverify: OK n=" + convert.int_to_string(n));
  return 0;
}

// Transaction scenario: put N base keys, checkpoint (clean baseline), then
// begin a transaction, write `txn_count` keys, optionally commit, and hang for
// a hard kill. Harness polls WAL line count + snapshot file, not stdout.
fn run_txn(path: Str, n: Int) -> Int {
  var txn_count = 5;
  match parse.parse_int(env.var_or("ORBITDB_DB_TXN_COUNT", "5")) {
    Ok(v) => { txn_count = v; }
    Err(_) => { txn_count = 5; }
  }
  var do_commit = true;
  if env.var_or("ORBITDB_DB_TXN_COMMIT", "1") == "0" { do_commit = false; }

  var db = open_db(path, 4);
  var i = 1;
  while i <= n {
    if !db_file_put(&mut db, i, i * 10) {
      io.println("txn: base put failed at " + convert.int_to_string(i));
      return 1;
    }
    i = i + 1;
  }
  let base = db_file_checkpoint(&mut db);
  if base < 0 { io.println("txn: baseline checkpoint failed"); return 1; }
  io.println("txn: baseline done lsn=" + convert.int_to_string(base));

  if !db_file_txn_begin(&mut db) { io.println("txn: begin failed"); return 1; }
  var j = n + 1;
  while j <= n + txn_count {
    if !db_file_txn_put(&mut db, j, j * 10) {
      io.println("txn: put failed at " + convert.int_to_string(j));
      return 1;
    }
    j = j + 1;
  }
  if do_commit {
    if !db_file_txn_commit(&mut db) { io.println("txn: commit failed"); return 1; }
    io.println("txn: committed");
  } else {
    io.println("txn: pending (uncommitted)");
  }
  let flushed = db_file_flush(&mut db);
  if !flushed { io.println("txn: flush failed"); return 1; }

  // Hang until the harness hard-kills us (crash simulation).
  var alive = true;
  while alive {
    io.sleep(1000);
  }
  return 0;
}

// Checkpoint scenario: put N keys, checkpoint (snapshot + anchor + truncate),
// then optionally put `tail` more keys and hang for a hard kill. The harness
// waits on the WAL line count / snapshot file, not on stdout.
fn run_ckpt(path: Str, n: Int) -> Int {
  var tail = 0;
  match parse.parse_int(env.var_or("ORBITDB_DB_TAIL", "0")) {
    Ok(v) => { tail = v; }
    Err(_) => { tail = 0; }
  }
  var db = open_db(path, 4);
  var i = 1;
  while i <= n {
    if !db_file_put(&mut db, i, i * 10) {
      io.println("ckpt: put failed at " + convert.int_to_string(i));
      return 1;
    }
    i = i + 1;
  }
  let anchor = db_file_checkpoint(&mut db);
  if anchor < 0 { io.println("ckpt: checkpoint failed"); return 1; }
  io.println("ckpt: snapshot done lsn=" + convert.int_to_string(anchor));

  var j = n + 1;
  while j <= n + tail {
    if !db_file_put(&mut db, j, j * 10) {
      io.println("ckpt: tail put failed at " + convert.int_to_string(j));
      return 1;
    }
    j = j + 1;
  }
  if tail > 0 { io.println("ckpt: tail done"); }
  let flushed = db_file_flush(&mut db);
  if !flushed { io.println("ckpt: flush failed"); return 1; }

  // Hang until the harness hard-kills us (crash simulation).
  var alive = true;
  while alive {
    io.sleep(1000);
  }
  return 0;
}

// Soak scenario: N puts with a checkpoint every `every` writes, then a full
// reopen + verify + one post-recovery write + reopen. Exercises repeated
// snapshot install / truncate across a long run.
fn run_soak(path: Str, n: Int) -> Int {
  var every = 250;
  match parse.parse_int(env.var_or("ORBITDB_DB_CKPT_EVERY", "250")) {
    Ok(v) => { if v >= 1 { every = v; } }
    Err(_) => { every = 250; }
  }
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");

  var db = open_db(path, 4);
  var checkpoints = 0;
  var i = 1;
  while i <= n {
    if !db_file_put(&mut db, i, i * 10) {
      io.println("soak: put failed at " + convert.int_to_string(i));
      return 1;
    }
    // Policy-driven cadence: checkpoint when `every` records accumulated.
    let anchor = db_file_maybe_checkpoint(&mut db, every);
    if anchor > 0 { checkpoints = checkpoints + 1; }
    i = i + 1;
  }
  let final = db_file_checkpoint(&mut db);
  if final < 0 { io.println("soak: final checkpoint failed"); return 1; }
  io.println("soak: loop+final done checkpoints=" + convert.int_to_string(checkpoints + 1));

  var db2 = open_db(path, 4);
  io.println("soak: reopened");
  if db_file_size(&db2) != n {
    io.println("soak: size mismatch got " + convert.int_to_string(db_file_size(&db2)));
    return 1;
  }
  io.println("soak: size ok");
  let mid = n / 2;
  let spot = db_file_get(&db2, mid);
  match spot {
    None => { io.println("soak: mid key missing"); return 1; }
    Some(x) => { if x != mid * 10 { io.println("soak: mid value wrong"); return 1; } }
  }
  let last = db_file_get(&db2, n);
  match last {
    None => { io.println("soak: last key missing"); return 1; }
    Some(x) => { if x != n * 10 { io.println("soak: last value wrong"); return 1; } }
  }

  if !db_file_put(&mut db2, n + 1, (n + 1) * 10) {
    io.println("soak: post-recovery put failed");
    return 1;
  }
  io.println("soak: post put done");
  var db3 = open_db(path, 4);
  io.println("soak: reopened 2");
  if db_file_size(&db3) != n + 1 {
    io.println("soak: final size wrong");
    return 1;
  }

  io.println("soak: OK n=" + convert.int_to_string(n) + " checkpoints="
             + convert.int_to_string(checkpoints + 1));
  return 0;
}

fn main() -> Int {
  let path = env.var_or("ORBITDB_DB_FILE", "");
  if path == "" {
    io.println("probe_db_file: ORBITDB_DB_FILE not set");
    return 2;
  }
  let mode = env.var_or("ORBITDB_DB_MODE", "verify");
  var n = 20;
  match parse.parse_int(env.var_or("ORBITDB_DB_N", "20")) {
    Ok(v) => { n = v; }
    Err(_) => { n = 20; }
  }

  if mode == "write" {
    return run_write(path, n);
  }
  if mode == "ckpt" {
    return run_ckpt(path, n);
  }
  if mode == "soak" {
    return run_soak(path, n);
  }
  if mode == "qverify" {
    return run_qverify(path, n);
  }
  if mode == "txn" {
    return run_txn(path, n);
  }
  if mode == "put1" {
    var db = open_db(path, 4);
    if !db_file_put(&mut db, 9999, 99990) {
      io.println("put1: failed");
      return 1;
    }
    let flushed = db_file_flush(&mut db);
    if !flushed { io.println("put1: flush failed"); return 1; }
    io.println("put1: OK");
    return 0;
  }
  return run_verify(path, n);
}
