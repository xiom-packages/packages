// XIOM ORBITDB -- conformance suite split: dbfile (R2, 2026-10-18).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom_db_conformance_dbfile

use xiom.io;
use xiom.convert;
use xiom.os.env;
use xiom.test;
use xiom.db.engine;
use xiom.db.wal_file;
use xiom.db.error;
use xiom.db.ids;
use xiom.db.config;
use xiom.db.contracts;
use xiom.db.storage.page;
use xiom.db.storage.page_file;
use xiom.db.storage.block;
use xiom.db.storage.fault;
use xiom.db.storage.tuple;
use xiom.db.storage.free_space_map;
use xiom.db.catalog.schema;
use xiom.db.catalog.schema_row;
use xiom.db.catalog.schema_validator;
use xiom.db.txn.transaction;
use xiom_db_suite_common;

fn run_db_file_default_v2_flip() -> Int {
  let path = "orbitdb-suite-db-flip.wal";
  let snap = "orbitdb-suite-db-flip.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  // 1. Default open + checkpoint writes a v2 container (first byte 'O').
  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 10 {
    if !db_file_put(&mut db, i, i * 7) { return 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return 2; }
  match io.read_at(snap, 0, 1) {
    Err(_) => { return 3; }
    Ok(b) => {
      if b.len() != 1 { return 4; }
      if ((b[0] as Int) & 0xFF) != 0x4F { return 5; }
    }
  }

  // 2. Default reopen: v2 loads, data intact, further writes + checkpoint.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 10 { return 6; }
  if !db_file_put(&mut db2, 11, 77) { return 7; }
  if db_file_checkpoint(&mut db2) < 0 { return 8; }

  // 3. Migration-on-write via the DEFAULT open: a v1 file flips to v2 at its
  //    next checkpoint and stays readable.
  let path1 = "orbitdb-suite-db-flip1.wal";
  let snap1 = "orbitdb-suite-db-flip1.wal.snap";
  let _ = io.remove_file(path1);
  let _ = io.remove_file(snap1);
  var v1 = db_file_open_cfg(path1, 4, 1);
  i = 1;
  while i <= 6 {
    if !db_file_put(&mut v1, i, i * 3) { return 9; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut v1) < 0 { return 10; }
  match io.read_at(snap1, 0, 1) {
    Err(_) => { return 11; }
    Ok(b) => {
      if b.len() == 1 && ((b[0] as Int) & 0xFF) == 0x4F { return 12; }
    }
  }
  var m = db_file_open(path1, 4); // default = v2 handle on a v1 file
  if db_file_size(&m) != 6 { return 13; }
  if !db_file_put(&mut m, 7, 21) { return 14; }
  if db_file_checkpoint(&mut m) < 0 { return 15; } // migrates to v2
  match io.read_at(snap1, 0, 1) {
    Err(_) => { return 16; }
    Ok(b) => {
      if b.len() != 1 { return 17; }
      if ((b[0] as Int) & 0xFF) != 0x4F { return 18; }
    }
  }
  let v = db_file_open(path1, 4);
  if db_file_size(&v) != 7 { return 19; }
  match db_file_get(&v, 7) {
    None => { return 20; }
    Some(x) => { if x != 21 { return 21; } }
  }
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  let _ = io.remove_file(path1);
  let _ = io.remove_file(snap1);
  return 0;
}

fn test_db_file_default_v2_flip() -> TestResult {
  let rc = run_db_file_default_v2_flip();
  if rc == 0 { return assert(true, "db_file: v2 is the default container; v1 migrates on default write"); }
  return assert(false, "db_file: default v2 flip failed rc=" + int_to_str(rc));
}

// ===========================================================================
// Durable page file (text v1, CRC32C verified, atomic rewrite)
// ===========================================================================

fn run_page_file_roundtrip() -> Int {
  let path = "orbitdb-suite-pages.tmp";
  let _ = io.remove_file(path);
  let pf = page_file_open(path);
  var d1 = Vec[Int].new();
  d1.push(1);
  d1.push(2);
  d1.push(3);
  let p1 = Page.new(10, d1, page_compute_checksum(&d1));
  if !page_file_write(&pf, p1) { return 1; }
  var d2 = Vec[Int].new();
  d2.push(200);
  let p2 = Page.new(11, d2, page_compute_checksum(&d2));
  if !page_file_write(&pf, p2) { return 1; }
  if page_file_count(&pf) != 2 { return 1; }
  let r1 = page_file_read(&pf, 10);
  match r1 {
    None => { return 1; }
    Some(p) => {
      let pg: Page = p;
      if !pg.is_valid() { return 1; }
      if pg.data.len() != 3 { return 1; }
    }
  }
  // Upsert the same id: count unchanged, new bytes.
  var d3 = Vec[Int].new();
  d3.push(9);
  let p3 = Page.new(10, d3, page_compute_checksum(&d3));
  if !page_file_write(&pf, p3) { return 1; }
  if page_file_count(&pf) != 2 { return 1; }
  let r3 = page_file_read(&pf, 10);
  match r3 {
    None => { return 1; }
    Some(p) => {
      let pg: Page = p;
      if !pg.is_valid() { return 1; }
      if pg.data.len() != 1 { return 1; }
      if pg.data[0] != 9 { return 1; }
    }
  }
  let _ = io.remove_file(path);
  return 0;
}

fn test_page_file_roundtrip() -> TestResult {
  let rc = run_page_file_roundtrip();
  if rc == 0 { return assert(true, "page_file: write/read/upsert/verify roundtrip"); }
  return assert(false, "page_file: roundtrip failed");
}

fn run_page_file_corruption() -> Int {
  let path = "orbitdb-suite-pages2.tmp";
  let _ = io.remove_file(path);
  let pf = page_file_open(path);
  var d = Vec[Int].new();
  d.push(5);
  d.push(6);
  let p = Page.new(1, d, page_compute_checksum(&d));
  if !page_file_write(&pf, p) { return 1; }
  // Malformed torn tail (no newline) must be skipped by count/read.
  let app = io.append_file(path, "88|5|");
  match app { Ok(_) => {}, Err(_) => { return 1; } }
  if page_file_count(&pf) != 1 { return 1; }
  let r = page_file_read(&pf, 1);
  match r {
    None => { return 1; }
    Some(g) => {
      let pg: Page = g;
      if !pg.is_valid() { return 1; }
    }
  }
  // Structurally valid but checksum-invalid line: not a page.
  let app2 = io.append_file(path, "\n99|1|123|7\n");
  match app2 { Ok(_) => {}, Err(_) => { return 1; } }
  let r99 = page_file_read(&pf, 99);
  match r99 { Some(_) => { return 1; }, None => {} }
  if page_file_count(&pf) != 1 { return 1; }
  let _ = io.remove_file(path);
  return 0;
}

fn test_page_file_corruption() -> TestResult {
  let rc = run_page_file_corruption();
  if rc == 0 { return assert(true, "page_file: torn tail + bad checksum rejected"); }
  return assert(false, "page_file: corruption handling failed");
}

fn run_page_log() -> Int {
  let path = "orbitdb-suite-pagelog.tmp";
  let _ = io.remove_file(path);
  let pf = page_file_open(path);

  // Two pages; id 5 gets a newer version afterwards.
  var d1 = Vec[Int].new();
  d1.push(1);
  d1.push(2);
  if !page_log_append(&pf, Page.new(5, d1, page_compute_checksum(&d1))) { return 1; }
  var d2 = Vec[Int].new();
  d2.push(9);
  if !page_log_append(&pf, Page.new(6, d2, page_compute_checksum(&d2))) { return 1; }
  var d3 = Vec[Int].new();
  d3.push(7);
  d3.push(8);
  if !page_log_append(&pf, Page.new(5, d3, page_compute_checksum(&d3))) { return 1; }
  if page_log_len(&pf) != 3 { return 1; }

  let latest = page_log_read_all(&pf);
  if latest.len() != 2 { return 1; }
  var found5 = false;
  var found6 = false;
  var i = 0;
  while i < latest.len() {
    let pg = latest[i];
    if pg.id == 5 {
      if pg.data.len() != 2 { return 1; }
      if pg.data[0] != 7 { return 1; }
      if pg.data[1] != 8 { return 1; }
      found5 = true;
    }
    if pg.id == 6 { found6 = true; }
    i = i + 1;
  }
  if !found5 { return 1; }
  if !found6 { return 1; }

  // Torn trailing line: skipped by readers, healed before the next append so
  // the partial line cannot merge with the new entry.
  let app = io.append_file(path, "77|3|");
  match app { Ok(_) => {}, Err(_) => { return 1; } }
  var d4 = Vec[Int].new();
  d4.push(42);
  if !page_log_heal_tail(&pf) { return 1; }
  if !page_log_append(&pf, Page.new(7, d4, page_compute_checksum(&d4))) { return 1; }
  if page_log_len(&pf) != 4 { return 1; }
  let after = page_log_read_all(&pf);
  if after.len() != 3 { return 1; }
  var found7 = false;
  var j = 0;
  while j < after.len() {
    let pg = after[j];
    if pg.id == 7 {
      if pg.data.len() != 1 { return 1; }
      if pg.data[0] != 42 { return 1; }
      found7 = true;
    }
    j = j + 1;
  }
  if !found7 { return 1; }

  let _ = io.remove_file(path);
  return 0;
}

fn test_page_log() -> TestResult {
  let rc = run_page_log();
  if rc == 0 { return assert(true, "page_log: append/latest-wins/torn-tail heal"); }
  return assert(false, "page_log: append/latest/torn failed");
}

// ===========================================================================
// File-backed database (WAL-before-ack + replay recovery)
// ===========================================================================

fn run_db_file_roundtrip() -> Int {
  let path = "orbitdb-suite-db.wal";
  let _ = io.remove_file(path);
  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 10) { return 1; }
  if !db_file_put(&mut db, 2, 20) { return 1; }
  if !db_file_put(&mut db, 2, 99) { return 1; }   // update
  if !db_file_delete(&mut db, 1) { return 1; }
  if db_file_size(&db) != 1 { return 1; }
  if db_file_last_lsn(&db) != 4 { return 1; }
  if !db_file_flush(&mut db) { return 1; }

  // Reopen: replay must reproduce the final state exactly.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 1 { return 1; }
  let v = db_file_get(&db2, 2);
  match v {
    None => { return 1; }
    Some(x) => { if x != 99 { return 1; } }
  }
  let gone = db_file_get(&db2, 1);
  match gone { Some(_) => { return 1; }, None => {} }
  let _ = io.remove_file(path);
  return 0;
}

fn test_db_file_roundtrip() -> TestResult {
  let rc = run_db_file_roundtrip();
  if rc == 0 { return assert(true, "db_file: put/update/delete survive reopen (WAL replay)"); }
  return assert(false, "db_file: roundtrip failed");
}

// ===========================================================================
// File-backed database: checkpoint/snapshot (node page codec + tail replay)
// ===========================================================================

fn run_db_file_checkpoint() -> Int {
  let path = "orbitdb-suite-db-ckpt.wal";
  let snap = "orbitdb-suite-db-ckpt.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 12 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  let ckpt = db_file_checkpoint(&mut db);
  if ckpt < 12 { return 1; }

  // Truncation kept exactly the Checkpoint anchor: no write records remain,
  // and the anchor's payload [generation, node_count, order] survived.
  if wal_file_len(path) != 1 { return 1; }
  let records = wal_file_replay(path);
  let r0 = records[0];
  if r0.lsn != ckpt { return 1; }
  if wal_op_code(r0.op) != 6 { return 1; }
  if r0.payload.len() != 3 { return 1; }

  // The 12 keys can only come from the snapshot now (the log has no write
  // records); LastLSN resumes from the anchor.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 12 { return 1; }
  if db_file_last_lsn(&db2) != ckpt { return 1; }
  let v7 = db_file_get(&db2, 7);
  match v7 {
    None => { return 1; }
    Some(x) => { if x != 70 { return 1; } }
  }

  // A write after the checkpoint replays from the tail on the next open.
  if !db_file_put(&mut db2, 13, 130) { return 1; }
  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 13 { return 1; }
  let v13 = db_file_get(&db3, 13);
  match v13 {
    None => { return 1; }
    Some(x) => { if x != 130 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_checkpoint() -> TestResult {
  let rc = run_db_file_checkpoint();
  if rc == 0 { return assert(true, "db_file: checkpoint snapshot + tail replay + WAL truncate"); }
  return assert(false, "db_file: checkpoint roundtrip failed");
}

fn run_db_file_checkpoint_churn() -> Int {
  let path = "orbitdb-suite-db-ckpt2.wal";
  let snap = "orbitdb-suite-db-ckpt2.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 20 {
    if !db_file_put(&mut db, i, i) { return 1; }
    i = i + 1;
  }
  // Churn before the snapshot: delete evens, update odds (exercises internal
  // split/merge node shapes in the node page codec).
  var k = 2;
  while k <= 20 {
    if !db_file_delete(&mut db, k) { return 1; }
    k = k + 2;
  }
  k = 1;
  while k <= 19 {
    if !db_file_put(&mut db, k, k * 100) { return 1; }
    k = k + 2;
  }
  if db_file_size(&db) != 10 { return 1; }

  let ckpt = db_file_checkpoint(&mut db);
  if ckpt < 0 { return 1; }
  // A second checkpoint must advance the generation and re-install atomically.
  let ckpt2 = db_file_checkpoint(&mut db);
  if ckpt2 <= ckpt { return 1; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 10 { return 1; }
  let gone = db_file_get(&db2, 2);
  match gone { Some(_) => { return 1; }, None => {} }
  let v19 = db_file_get(&db2, 19);
  match v19 {
    None => { return 1; }
    Some(x) => { if x != 1900 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_checkpoint_churn() -> TestResult {
  let rc = run_db_file_checkpoint_churn();
  if rc == 0 { return assert(true, "db_file: checkpoint survives churn + re-checkpoint (generation)"); }
  return assert(false, "db_file: checkpoint churn failed");
}

fn run_db_file_v2_snapshot() -> Int {
  let path = "orbitdb-suite-db-v2.wal";
  let snap = "orbitdb-suite-db-v2.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open_cfg(path, 4, 2);
  if db.page_format != 2 { return 1; }
  var i = 1;
  while i <= 40 {
    if !db_file_put(&mut db, i, i * 3) { return 1; }
    i = i + 1;
  }
  let ckpt = db_file_checkpoint(&mut db);
  if ckpt < 0 { return 1; }
  // Dirty-only append path: a second checkpoint must advance the generation.
  i = 1;
  while i <= 10 {
    if !db_file_put(&mut db, i, i * 7) { return 1; }
    i = i + 1;
  }
  let ckpt2 = db_file_checkpoint(&mut db);
  if ckpt2 <= ckpt { return 1; }

  // Reopen with the DEFAULT v1 handle: reads auto-detect the v2 file.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 40 { return 1; }
  let v5 = db_file_get(&db2, 5);
  match v5 {
    None => { return 1; }
    Some(x) => { if x != 35 { return 1; } }
  }
  let v30 = db_file_get(&db2, 30);
  match v30 {
    None => { return 1; }
    Some(x) => { if x != 90 { return 1; } }
  }
  // A v1-handle checkpoint on a v2 file rewrites it whole as v1 (the
  // on-disk format stays authoritative), and reads keep working.
  if !db_file_put(&mut db2, 41, 410) { return 1; }
  let ckpt3 = db_file_checkpoint(&mut db2);
  if ckpt3 < 0 { return 1; }
  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 41 { return 1; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_v2_snapshot() -> TestResult {
  let rc = run_db_file_v2_snapshot();
  if rc == 0 { return assert(true, "db_file v2: byte-snapshot append + auto-detect + format flip"); }
  return assert(false, "db_file v2: snapshot roundtrip failed");
}

fn run_db_file_v2_migrate() -> Int {
  let path = "orbitdb-suite-db-v2m.wal";
  let snap = "orbitdb-suite-db-v2m.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  // Build a v1 snapshot, then migrate it in place (twice: idempotent).
  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 25 {
    if !db_file_put(&mut db, i, i + 100) { return 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return 1; }
  let _ = io.remove_file(path);

  if !db_file_migrate_snapshot(path) { return 1; }
  if !db_file_migrate_snapshot(path) { return 1; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 25 { return 1; }
  let v13 = db_file_get(&db2, 13);
  match v13 {
    None => { return 1; }
    Some(x) => { if x != 113 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_v2_migrate() -> TestResult {
  let rc = run_db_file_v2_migrate();
  if rc == 0 { return assert(true, "db_file v2: v1 snapshot migrated in place (idempotent)"); }
  return assert(false, "db_file v2: migration failed");
}

fn run_db_file_query_range() -> Int {
  let path = "orbitdb-suite-db-q.wal";
  let snap = "orbitdb-suite-db-q.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 12 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }

  // Live handle: key range in order, then a value-filter query with
  // offset/limit (conditions filter VALUES -- pinned semantics).
  let r = db_file_range(&db, 3, 6);
  if r.len() != 4 { return 1; }
  if r[0] != 30 { return 1; }
  if r[1] != 40 { return 1; }
  if r[2] != 50 { return 1; }
  if r[3] != 60 { return 1; }

  var q = query_new();
  query_where(&mut q, QueryOp.Gte, 10);
  query_offset(&mut q, 2);
  query_limit(&mut q, 3);
  let filtered = db_file_query(&db, &q);
  if filtered.len() != 3 { return 1; }
  if filtered[0] != 30 { return 1; }
  if filtered[1] != 40 { return 1; }
  if filtered[2] != 50 { return 1; }

  var q2 = query_new();
  query_where(&mut q2, QueryOp.Lt, 30);
  let small = db_file_query(&db, &q2);
  if small.len() != 2 { return 1; }
  if small[0] != 10 { return 1; }
  if small[1] != 20 { return 1; }

  // Checkpoint, then a tail write: the reopened handle must answer queries
  // from the snapshot + tail replay (not from a fresh empty tree).
  if db_file_checkpoint(&mut db) < 0 { return 1; }
  if !db_file_put(&mut db, 13, 130) { return 1; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 13 { return 1; }
  let r2 = db_file_range(&db2, 12, 13);
  if r2.len() != 2 { return 1; }
  if r2[0] != 120 { return 1; }
  if r2[1] != 130 { return 1; }
  var q3 = query_new();
  query_where(&mut q3, QueryOp.Eq, 130);
  let eq = db_file_query(&db2, &q3);
  if eq.len() != 1 { return 1; }
  if eq[0] != 130 { return 1; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_query_range() -> TestResult {
  let rc = run_db_file_query_range();
  if rc == 0 { return assert(true, "db_file: range + filtered query (live, snapshot + tail recovery)"); }
  return assert(false, "db_file: query/range failed");
}

fn run_db_file_incremental_checkpoint() -> Int {
  let path = "orbitdb-suite-db-inc.wal";
  let snap = "orbitdb-suite-db-inc.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  // v1 page-log mechanics test: keep an explicit v1 handle after the M1.2 S4
  // default flip (db_file_open now defaults to the v2 byte container).
  var db = db_file_open_cfg(path, 4, 1);
  var i = 1;
  while i <= 12 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  let c1 = db_file_checkpoint(&mut db);
  if c1 < 12 { return 1; }
  let pf = page_file_open(snap);
  let entries1 = page_log_len(&pf);

  // No mutation -> the second checkpoint commits a header entry only.
  let c2 = db_file_checkpoint(&mut db);
  if c2 <= c1 { return 1; }
  let entries2 = page_log_len(&pf);
  if entries2 != entries1 + 1 { return 1; }

  // A torn trailing append must be healed before the next checkpoint appends,
  // or the first new entry would merge with it and be lost.
  let app = io.append_file(snap, "12|3|");
  match app { Ok(_) => {}, Err(_) => { return 1; } }
  if !db_file_put(&mut db, 13, 130) { return 1; }
  let c3 = db_file_checkpoint(&mut db);
  if c3 <= c2 { return 1; }

  var db2 = db_file_open_cfg(path, 4, 1);
  if db_file_size(&db2) != 13 { return 1; }
  let v13 = db_file_get(&db2, 13);
  match v13 {
    None => { return 1; }
    Some(x) => { if x != 130 { return 1; } }
  }
  let v1 = db_file_get(&db2, 1);
  match v1 {
    None => { return 1; }
    Some(x) => { if x != 10 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_incremental_checkpoint() -> TestResult {
  let rc = run_db_file_incremental_checkpoint();
  if rc == 0 { return assert(true, "db_file: incremental checkpoint (no-op delta + torn-tail heal)"); }
  return assert(false, "db_file: incremental checkpoint failed");
}

// Node page bytes for the bogus uncommitted-generation page (codec v1).
fn snap_test_leaf_bytes(keys: Vec[Int], values: Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(0x4F);
  out.push(1);
  out.push(0x4E);
  out.push(1);
  tuple_push_int_le(&mut out, keys.len());
  tuple_push_int_le(&mut out, 0);
  tuple_push_int_le(&mut out, 0);
  var i = 0;
  while i < keys.len() {
    tuple_push_int_le(&mut out, keys[i]);
    i = i + 1;
  }
  i = 0;
  while i < values.len() {
    tuple_push_int_le(&mut out, values[i]);
    i = i + 1;
  }
  return out;
}

fn run_db_file_uncommitted_generation() -> Int {
  let path = "orbitdb-suite-db-uncommitted.wal";
  let snap = "orbitdb-suite-db-uncommitted.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 12 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return 1; }

  // Crash window simulation: a node page from the NEXT generation was
  // appended, but its header never was. It must be ignored on load.
  let pf = page_file_open(snap);
  var keys = Vec[Int].new();
  keys.push(999);
  var values = Vec[Int].new();
  values.push(9990);
  let bytes = snap_test_leaf_bytes(keys, values);
  let bogus_id = 2 * SNAP_PAGE_STRIDE + 1; // generation 2, node 0
  if !page_log_append(&pf, Page.new(bogus_id, bytes, page_compute_checksum(&bytes))) { return 1; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 12 { return 1; }
  let phantom = db_file_get(&db2, 999);
  match phantom { Some(_) => { return 1; }, None => {} }

  // The next checkpoint must not let the stale generation-2 page leak into
  // the committed generation: it forces a full write of generation 2.
  if !db_file_put(&mut db2, 5, 55) { return 1; }
  if db_file_checkpoint(&mut db2) < 0 { return 1; }

  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 12 { return 1; }
  let v5 = db_file_get(&db3, 5);
  match v5 {
    None => { return 1; }
    Some(x) => { if x != 55 { return 1; } }
  }
  let still = db_file_get(&db3, 999);
  match still { Some(_) => { return 1; }, None => {} }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_uncommitted_generation() -> TestResult {
  let rc = run_db_file_uncommitted_generation();
  if rc == 0 { return assert(true, "db_file: uncommitted generation ignored + stale flush handled"); }
  return assert(false, "db_file: uncommitted generation failed");
}

fn run_db_file_checkpoint_policy() -> Int {
  let path = "orbitdb-suite-db-policy.wal";
  let snap = "orbitdb-suite-db-policy.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 3 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  if db_file_maybe_checkpoint(&mut db, 5) != -1 { return 1; }

  var j = 4;
  while j <= 6 {
    if !db_file_put(&mut db, j, j * 10) { return 1; }
    j = j + 1;
  }
  let anchor = db_file_maybe_checkpoint(&mut db, 5);
  if anchor < 6 { return 1; }
  // The counter reset: below threshold again, and the WAL holds the anchor.
  if db_file_maybe_checkpoint(&mut db, 5) != -1 { return 1; }
  if wal_file_len(path) != 1 { return 1; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 6 { return 1; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_checkpoint_policy() -> TestResult {
  let rc = run_db_file_checkpoint_policy();
  if rc == 0 { return assert(true, "db_file: maybe_checkpoint threshold + counter reset"); }
  return assert(false, "db_file: checkpoint policy failed");
}

fn run_db_file_compaction() -> Int {
  let path = "orbitdb-suite-db-compact.wal";
  let snap = "orbitdb-suite-db-compact.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 8 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return 1; }

  // Repeated no-op checkpoints grow the log by one header each; once it
  // passes node_count + 64, the next checkpoint must compact (atomic batch
  // rewrite to one page per node).
  var c = 0;
  while c < 70 {
    if db_file_checkpoint(&mut db) < 0 { return 1; }
    c = c + 1;
  }

  let pf = page_file_open(snap);
  let entries = page_log_len(&pf);
  // Without compaction the log would hold ~78 entries; after compaction it is
  // one page per node + a header plus the post-compaction headers (< 20).
  if entries > 25 { return 1; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 8 { return 1; }
  let v8 = db_file_get(&db2, 8);
  match v8 {
    None => { return 1; }
    Some(x) => { if x != 80 { return 1; } }
  }
  // The compacted snapshot must keep accepting writes + checkpoints.
  if !db_file_put(&mut db2, 9, 90) { return 1; }
  if db_file_checkpoint(&mut db2) < 0 { return 1; }
  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 9 { return 1; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_compaction() -> TestResult {
  let rc = run_db_file_compaction();
  if rc == 0 { return assert(true, "db_file: log compaction at node_count + 64"); }
  return assert(false, "db_file: compaction failed");
}

fn run_db_file_txn_commit() -> Int {
  let path = "orbitdb-suite-db-txn.wal";
  let snap = "orbitdb-suite-db-txn.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 3 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }

  if !db_file_txn_begin(&mut db) { return 1; }
  if !db_file_txn_active(&db) { return 1; }
  // Buffered ops are NOT visible before the commit.
  if !db_file_txn_put(&mut db, 10, 100) { return 1; }
  if !db_file_txn_put(&mut db, 11, 110) { return 1; }
  if !db_file_txn_delete(&mut db, 2) { return 1; }
  let hidden = db_file_get(&db, 10);
  match hidden { Some(_) => { return 1; }, None => {} }
  if db_file_size(&db) != 3 { return 1; }

  if !db_file_txn_commit(&mut db) { return 1; }
  if db_file_txn_active(&db) { return 1; }
  if db_file_size(&db) != 4 { return 1; } // 1, 3, 10, 11
  let v10 = db_file_get(&db, 10);
  match v10 {
    None => { return 1; }
    Some(x) => { if x != 100 { return 1; } }
  }
  let gone = db_file_get(&db, 2);
  match gone { Some(_) => { return 1; }, None => {} }

  // Reopen: the committed transaction replays as applied (durable path).
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 4 { return 1; }
  let v11 = db_file_get(&db2, 11);
  match v11 {
    None => { return 1; }
    Some(x) => { if x != 110 { return 1; } }
  }
  let v1 = db_file_get(&db2, 1);
  match v1 {
    None => { return 1; }
    Some(x) => { if x != 10 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_txn_commit() -> TestResult {
  let rc = run_db_file_txn_commit();
  if rc == 0 { return assert(true, "db_file: txn commit buffered -> applied -> replayed"); }
  return assert(false, "db_file: txn commit failed");
}

fn run_db_file_txn_abort_guards() -> Int {
  let path = "orbitdb-suite-db-txn2.wal";
  let snap = "orbitdb-suite-db-txn2.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 3 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  let c0 = db_file_checkpoint(&mut db);
  if c0 < 0 { return 1; }

  if !db_file_txn_begin(&mut db) { return 1; }
  // Guards: checkpoint (explicit + threshold-reached) and auto-commit writes
  // are all rejected while the transaction is active.
  if db_file_checkpoint(&mut db) != -1 { return 1; }
  if db_file_maybe_checkpoint(&mut db, 1) != -1 { return 1; }
  if db_file_put(&mut db, 99, 990) { return 1; }
  if db_file_delete(&mut db, 1) { return 1; }

  if !db_file_txn_put(&mut db, 20, 200) { return 1; }
  if !db_file_txn_abort(&mut db) { return 1; }
  if db_file_txn_active(&db) { return 1; }
  let v20 = db_file_get(&db, 20);
  match v20 { Some(_) => { return 1; }, None => {} }
  if db_file_size(&db) != 3 { return 1; }

  // Reopen: the aborted transaction leaves no trace.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 3 { return 1; }

  // Double begin/commit/abort misuse is rejected; checkpoint works again.
  if !db_file_txn_begin(&mut db2) { return 1; }
  if db_file_txn_begin(&mut db2) { return 1; }
  if !db_file_txn_commit(&mut db2) { return 1; }
  if db_file_txn_commit(&mut db2) { return 1; }
  if db_file_txn_abort(&mut db2) { return 1; }
  if db_file_checkpoint(&mut db2) < 0 { return 1; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_txn_abort_guards() -> TestResult {
  let rc = run_db_file_txn_abort_guards();
  if rc == 0 { return assert(true, "db_file: txn abort discards + checkpoint/auto-commit guards"); }
  return assert(false, "db_file: txn abort/guards failed");
}

fn run_db_file_dangling_txn_abort() -> Int {
  let path = "orbitdb-suite-db-txn3.wal";
  let snap = "orbitdb-suite-db-txn3.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  // A segment that looks like a crash mid-transaction: base write, BeginTxn,
  // two ops, no Commit.
  var w = wal_file_open(path);
  // This compilation unit imports BOTH wal_file's WALOpKind and txn's WALOp,
  // which share variant names -- qualification here is disambiguation, not the
  // C-ORBIT-04 workaround (that one is reverted in src/).
  let _ = wal_file_append(&mut w, WALOpKind.Insert, 1, 10);
  let _ = wal_file_append(&mut w, WALOpKind.BeginTxn, 0, 0);
  let _ = wal_file_append(&mut w, WALOpKind.Update, 2, 20);
  let _ = wal_file_append(&mut w, WALOpKind.Update, 3, 30);

  var db = db_file_open(path, 4);
  if db_file_size(&db) != 1 { return 1; } // txn ops discarded
  let v2 = db_file_get(&db, 2);
  match v2 { Some(_) => { return 1; }, None => {} }

  // Opening finalizes the dangling txn with an Abort record, so the next
  // auto-commit write is NOT attributed to the stale window on replay.
  if !db_file_put(&mut db, 4, 40) { return 1; }
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 2 { return 1; } // 1 and 4; txn ops stay out
  let v4 = db_file_get(&db2, 4);
  match v4 {
    None => { return 1; }
    Some(x) => { if x != 40 { return 1; } }
  }
  let v3 = db_file_get(&db2, 3);
  match v3 { Some(_) => { return 1; }, None => {} }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_dangling_txn_abort() -> TestResult {
  let rc = run_db_file_dangling_txn_abort();
  if rc == 0 { return assert(true, "db_file: dangling txn finalized with Abort on open"); }
  return assert(false, "db_file: dangling txn finalize failed");
}

fn run_db_path_validation() -> Int {
  if db_path_valid("") { return 1; }
  if !db_path_valid("orbitdb-suite-path.wal") { return 1; }
  if !db_path_valid("sub/dir/db.wal") { return 1; }
  if db_path_valid("bad\nname.wal") { return 1; }
  if db_path_valid("bad\rname.wal") { return 1; }

  var long = "";
  var i = 0;
  while i < 4100 {
    long = long + "a";
    i = i + 1;
  }
  if db_path_valid(long) { return 1; }
  return 0;
}

fn test_db_path_validation() -> TestResult {
  let rc = run_db_path_validation();
  if rc == 0 { return assert(true, "db_file: path validation (empty/CR/LF/overlong)"); }
  return assert(false, "db_file: path validation failed");
}

fn run_db_file_open_checked() -> Int {
  let path = "orbitdb-suite-db-checked.wal";
  let snap = "orbitdb-suite-db-checked.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  let bad_path = db_file_open_checked("", 4);
  match bad_path {
    Ok(_) => { return 1; }
    Err(_) => {}
  }
  let bad_order = db_file_open_checked(path, 2);
  match bad_order {
    Ok(_) => { return 1; }
    Err(_) => {}
  }
  let bad_newline = db_file_open_checked("bad\nname.wal", 4);
  match bad_newline {
    Ok(_) => { return 1; }
    Err(_) => {}
  }

  // Valid input: the Ok payload (cross-module generic -- C-ORBIT-01 rebind)
  // really is a usable handle.
  let good = db_file_open_checked(path, 4);
  var usable = false;
  match good {
    Err(_) => {}
    Ok(d) => {
      let handle: DBFile = d;
      if db_file_size(&handle) == 0 { usable = true; }
    }
  }
  if !usable { return 1; }

  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 10) { return 1; }
  if db_file_checkpoint(&mut db) < 0 { return 1; }
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 1 { return 1; }
  let v = db_file_get(&db2, 1);
  match v {
    None => { return 1; }
    Some(x) => { if x != 10 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_open_checked() -> TestResult {
  let rc = run_db_file_open_checked();
  if rc == 0 { return assert(true, "db_file: checked open rejects bad path/order, accepts valid"); }
  return assert(false, "db_file: checked open failed");
}

fn run_db_file_stale_handle() -> Int {
  let path = "orbitdb-suite-db-stale.wal";
  let snap = "orbitdb-suite-db-stale.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db1 = db_file_open(path, 4);
  var db2 = db_file_open(path, 4);

  // db1 writes; db2 is now stale and must refuse every write path.
  if !db_file_put(&mut db1, 1, 10) { return 1; }
  if db_file_put(&mut db2, 2, 20) { return 1; }
  if db_file_delete(&mut db2, 1) { return 1; }
  if db_file_txn_begin(&mut db2) { return 1; }
  if db_file_checkpoint(&mut db2) != -1 { return 1; }

  // db1 continues to work (it is the only writer).
  if !db_file_put(&mut db1, 3, 30) { return 1; }
  if !db_file_txn_begin(&mut db1) { return 1; }
  if !db_file_txn_put(&mut db1, 4, 40) { return 1; }
  if !db_file_txn_commit(&mut db1) { return 1; }
  if db_file_size(&db1) != 3 { return 1; } // 1, 3, 4

  // A fresh handle opens, then the established writer writes first: the fresh
  // handle is stale before it ever writes (first writer wins).
  var db3 = db_file_open(path, 4);
  if !db_file_put(&mut db1, 5, 50) { return 1; }
  if db_file_put(&mut db3, 6, 60) { return 1; }
  if db_file_txn_begin(&mut db3) { return 1; }

  // The established writer can checkpoint; the stale handle cannot.
  if db_file_checkpoint(&mut db1) < 0 { return 1; }
  if db_file_checkpoint(&mut db3) != -1 { return 1; }

  var db4 = db_file_open(path, 4);
  if db_file_size(&db4) != 4 { return 1; } // 1, 3, 4, 5
  let v5 = db_file_get(&db4, 5);
  match v5 {
    None => { return 1; }
    Some(x) => { if x != 50 { return 1; } }
  }
  let v6 = db_file_get(&db4, 6);
  match v6 { Some(_) => { return 1; }, None => {} }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_stale_handle() -> TestResult {
  let rc = run_db_file_stale_handle();
  if rc == 0 { return assert(true, "db_file: stale handle refuses writes + checkpoint"); }
  return assert(false, "db_file: stale-handle guard failed");
}

fn run_db_file_dirty_flush() -> Int {
  let path = "orbitdb-suite-db-dirty.wal";
  let snap = "orbitdb-suite-db-dirty.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  // v1 page-log mechanics test: explicit v1 handle after the M1.2 S4 flip.
  var db = db_file_open_cfg(path, 4, 1);
  var i = 1;
  while i <= 12 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  let c1 = db_file_checkpoint(&mut db);
  if c1 < 0 { return 1; }
  let pf = page_file_open(snap);
  let entries1 = page_log_len(&pf);
  if entries1 < 5 { return 1; } // several nodes + header

  // One key update (delete+insert) must flush only the touched path nodes.
  if !db_file_put(&mut db, 5, 55) { return 1; }
  let c2 = db_file_checkpoint(&mut db);
  if c2 <= c1 { return 1; }
  let entries2 = page_log_len(&pf);
  let delta = entries2 - entries1;
  if delta < 2 { return 1; }      // header + at least one node
  if delta > 4 { return 1; }      // a few path nodes, never a full rewrite
  if delta >= entries1 { return 1; }

  // A no-op checkpoint still appends the header only.
  let c3 = db_file_checkpoint(&mut db);
  if c3 <= c2 { return 1; }
  let entries3 = page_log_len(&pf);
  if entries3 - entries2 != 1 { return 1; }

  var db2 = db_file_open_cfg(path, 4, 1);
  if db_file_size(&db2) != 12 { return 1; }
  let v5 = db_file_get(&db2, 5);
  match v5 {
    None => { return 1; }
    Some(x) => { if x != 55 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_dirty_flush() -> TestResult {
  let rc = run_db_file_dirty_flush();
  if rc == 0 { return assert(true, "db_file: checkpoint flushes only dirty nodes (bounded delta)"); }
  return assert(false, "db_file: dirty-flush failed");
}

// ===========================================================================
// Durability API + fault injector (M2.1 first half). The env-armed injector
// is test-only (src/storage/fault.xi); `syncfail` makes the next sync report
// failure, which must latch the handle and refuse writers until reopen.
// ===========================================================================

fn run_db_file_durability_api() -> Int {
  let path = "orbitdb-suite-db-dura.wal";
  let snap = "orbitdb-suite-db-dura.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  if db_file_durability(&db) != 1 { return 1; }  // immediate is the default
  if db_file_two_phase(&db) { return 2; }
  if db_file_failed(&db) { return 3; }

  // Invalid modes are rejected; a valid set sticks to the handle.
  if db_file_set_durability(&mut db, 2) { return 4; }
  if db_file_set_durability(&mut db, -1) { return 5; }
  if !db_file_set_durability(&mut db, 0) { return 6; }
  if db_file_durability(&db) != 0 { return 7; }

  // Two-phase is immediate-only.
  if db_file_set_two_phase(&mut db, true) { return 8; }
  if !db_file_set_durability(&mut db, 1) { return 9; }
  if !db_file_set_two_phase(&mut db, true) { return 10; }
  if !db_file_two_phase(&db) { return 11; }
  if !db_file_set_two_phase(&mut db, false) { return 12; }
  if db_file_two_phase(&db) { return 13; }

  // Writes work in both modes; flush is the seam call and reports success.
  if !db_file_put(&mut db, 1, 100) { return 14; }
  if !db_file_set_durability(&mut db, 0) { return 15; }
  if !db_file_put(&mut db, 2, 200) { return 16; }
  if !db_file_flush(&mut db) { return 17; }
  if db_file_failed(&db) { return 18; }

  // Reopen resets to defaults; data survives.
  var db2 = db_file_open(path, 4);
  if db_file_durability(&db2) != 1 { return 19; }
  if db_file_two_phase(&db2) { return 20; }
  if db_file_size(&db2) != 2 { return 21; }
  match db_file_get(&db2, 1) {
    None => { return 22; }
    Some(v) => { if v != 100 { return 23; } }
  }
  match db_file_get(&db2, 2) {
    None => { return 24; }
    Some(v) => { if v != 200 { return 25; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_durability_api() -> TestResult {
  let rc = run_db_file_durability_api();
  if rc == 0 { return assert(true, "db_file: durability API defaults/setters + reopen reset"); }
  return assert(false, "db_file: durability API failed rc=" + int_to_str(rc));
}

fn run_db_file_syncfail_latch() -> Int {
  let path = "orbitdb-suite-db-syncfail.wal";
  let snap = "orbitdb-suite-db-syncfail.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 10) { return 1; }

  // The next sync fails: the put's WAL record lands but the ack flush does
  // not, so the commit reports false and the handle latches.
  env.set_var("ORBITDB_FAULT_AT", "1");
  env.set_var("ORBITDB_FAULT_MODE", "syncfail");
  fault_reset();
  if db_file_put(&mut db, 2, 20) { return 2; }
  if !db_file_failed(&db) { return 3; }

  // Latched writers refuse until reopen.
  if db_file_put(&mut db, 3, 30) { return 4; }
  if db_file_delete(&mut db, 1) { return 5; }
  if db_file_txn_begin(&mut db) { return 6; }
  if db_file_checkpoint(&mut db) >= 0 { return 7; }
  if db_file_flush(&mut db) { return 8; }

  // Disarm, reopen: the WAL record for key 2 was written before the failed
  // sync (WAL-before-ack), so recovery must produce it.
  env.remove_var("ORBITDB_FAULT_AT");
  env.remove_var("ORBITDB_FAULT_MODE");
  fault_reset();

  var db2 = db_file_open(path, 4);
  if db_file_failed(&db2) { return 9; }
  if db_file_size(&db2) != 2 { return 10; }
  match db_file_get(&db2, 2) {
    None => { return 11; }
    Some(v) => { if v != 20 { return 12; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_syncfail_latch() -> TestResult {
  let rc = run_db_file_syncfail_latch();
  if rc == 0 { return assert(true, "db_file: syncfail latches the handle; reopen recovers the record"); }
  return assert(false, "db_file: syncfail latch failed rc=" + int_to_str(rc));
}

// Range pairs: the admin/Station range view needs keys, not only values.
fn run_db_file_range_pairs() -> Int {
  let path = "orbitdb-suite-range-pairs.wal";
  let snap = "orbitdb-suite-range-pairs.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 5 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  let pairs = db_file_range_pairs(&db, 2, 4);
  if pairs.len() != 3 { return 2; }
  if pairs[0].0 != 2 || pairs[0].1 != 20 { return 3; }
  if pairs[1].0 != 3 || pairs[1].1 != 30 { return 4; }
  if pairs[2].0 != 4 || pairs[2].1 != 40 { return 5; }
  let empty = db_file_range_pairs(&db, 10, 20);
  if empty.len() != 0 { return 6; }
  if db_file_checkpoint(&mut db) < 0 { return 7; }
  var db2 = db_file_open(path, 4);
  let reopened = db_file_range_pairs(&db2, 1, 5);
  if reopened.len() != 5 { return 8; }
  if reopened[4].0 != 5 || reopened[4].1 != 50 { return 9; }
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_range_pairs() -> TestResult {
  let rc = run_db_file_range_pairs();
  if rc == 0 { return assert(true, "db_file: range_pairs returns (key,value) in order, live + paged reopen"); }
  return assert(false, "db_file: range_pairs failed rc=" + int_to_str(rc));
}

// M3 shard ownership: exclusive locked open is single-holder per process and
// releases on db_file_unlock (the cross-process half is tests/probes/probe_lock).
fn run_db_file_locked_open() -> Int {
  let path = "orbitdb-suite-locked.wal";
  let snap = "orbitdb-suite-locked.wal.snap";
  let lck = "orbitdb-suite-locked.wal.lock";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  let _ = io.remove_file(lck);
  match db_file_open_locked_checked(path, 4) {
    Err(_) => { return 1; }
    Ok(db) => {
      var d = db;
      if !db_file_put(&mut d, 1, 10) { return 2; }
    }
  }
  if !db_file_is_locked(path) { return 3; }
  match db_file_open_locked_checked(path, 4) {
    Ok(_) => { return 4; }
    Err(_) => {}
  }
  if !db_file_unlock(path) { return 5; }
  if db_file_is_locked(path) { return 6; }
  match db_file_open_locked_checked(path, 4) {
    Err(_) => { return 7; }
    Ok(db) => {
      match db_file_get(&db, 1) {
        Some(v) => { if v != 10 { return 8; } }
        None => { return 9; }
      }
    }
  }
  let _ = db_file_unlock(path);
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  let _ = io.remove_file(lck);
  return 0;
}

fn test_db_file_locked_open() -> TestResult {
  let rc = run_db_file_locked_open();
  if rc == 0 { return assert(true, "db_file: locked open is exclusive + release/reacquire (M3 shard lock)"); }
  return assert(false, "db_file: locked open failed rc=" + int_to_str(rc));
}

fn main() -> Int {
  io.println("=== XIOM DB Conformance: dbfile ===");
  var failed: Int = 0;
  var total: Int = 0;
  let r93a = test_page_file_roundtrip();
  total = total + 1; failed = failed + report(r93a.passed, r93a.name);
  let r93b = test_page_file_corruption();
  total = total + 1; failed = failed + report(r93b.passed, r93b.name);
  let r93c = test_page_log();
  total = total + 1; failed = failed + report(r93c.passed, r93c.name);
  let r94 = test_db_file_roundtrip();
  total = total + 1; failed = failed + report(r94.passed, r94.name);
  let r95a = test_db_file_checkpoint();
  total = total + 1; failed = failed + report(r95a.passed, r95a.name);
  let r95b = test_db_file_checkpoint_churn();
  total = total + 1; failed = failed + report(r95b.passed, r95b.name);
  let r96 = test_db_file_query_range();
  total = total + 1; failed = failed + report(r96.passed, r96.name);
  let r96b = test_db_file_range_pairs();
  total = total + 1; failed = failed + report(r96b.passed, r96b.name);
  let r96c = test_db_file_locked_open();
  total = total + 1; failed = failed + report(r96c.passed, r96c.name);
  let r97a = test_db_file_incremental_checkpoint();
  total = total + 1; failed = failed + report(r97a.passed, r97a.name);
  let r97b = test_db_file_uncommitted_generation();
  total = total + 1; failed = failed + report(r97b.passed, r97b.name);
  let r97c = test_db_file_checkpoint_policy();
  total = total + 1; failed = failed + report(r97c.passed, r97c.name);
  let r97d = test_db_file_compaction();
  total = total + 1; failed = failed + report(r97d.passed, r97d.name);
  let r98a = test_db_file_txn_commit();
  total = total + 1; failed = failed + report(r98a.passed, r98a.name);
  let r98b = test_db_file_txn_abort_guards();
  total = total + 1; failed = failed + report(r98b.passed, r98b.name);
  let r98c = test_db_file_dangling_txn_abort();
  total = total + 1; failed = failed + report(r98c.passed, r98c.name);
  let r99a = test_db_path_validation();
  total = total + 1; failed = failed + report(r99a.passed, r99a.name);
  let r99b = test_db_file_open_checked();
  total = total + 1; failed = failed + report(r99b.passed, r99b.name);
  let r99c = test_db_file_stale_handle();
  total = total + 1; failed = failed + report(r99c.passed, r99c.name);
  let r100 = test_db_file_dirty_flush();
  total = total + 1; failed = failed + report(r100.passed, r100.name);
  let r100a = test_db_file_durability_api();
  total = total + 1; failed = failed + report(r100a.passed, r100a.name);
  let r100b = test_db_file_syncfail_latch();
  total = total + 1; failed = failed + report(r100b.passed, r100b.name);
  let r105 = test_db_file_v2_snapshot();
  total = total + 1; failed = failed + report(r105.passed, r105.name);
  let r106 = test_db_file_v2_migrate();
  total = total + 1; failed = failed + report(r106.passed, r106.name);
  let r134 = test_db_file_default_v2_flip();
  total = total + 1; failed = failed + report(r134.passed, r134.name);
  let passed = total - failed;
  io.println("XIOM DB Conformance [dbfile]: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}