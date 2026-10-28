// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.engine.txn

// Durable single-active-transaction API (buffered ops, WAL-before-ack, held
// append fd) and txn-scoped savepoints, extracted move-only from engine.xi
// (R1 split). DBFile stays in xiom.db.engine (cyclic import, by design).

use xiom.db.wal_file;
use xiom.db.index.btree;
use xiom.db.storage.byte_io;
use xiom.db.engine.core;
use xiom.db.engine;

// Transaction record codes (wal_file WALOpKind BeginTxn/CommitTxn/AbortTxn);
// Int codes keep replay dispatch aligned with `db_file_apply_record`.
pub const TXN_BEGIN_CODE: Int = 8;
pub const TXN_COMMIT_CODE: Int = 9;
pub const TXN_ABORT_CODE: Int = 10;

// One buffered transaction operation: code 2 = upsert (delete+insert, the
// same code the WAL uses for writes), code 3 = delete. `payload` carries the
// tagged WAL payload verbatim (empty for plain int ops); M5.3 buffer them so
// a typed record inside a txn window replays with its row bytes.
pub type TxOp = {
  code: Int;
  key: Int;
  value: Int;
  payload: Vec[Int];
}

// Apply one buffered transaction op (see TxOp).
pub fn db_file_apply_txop(tree: &mut BTree, op: TxOp) {
  if op.code == 3 {
    let _ = btree_delete(tree, op.key);
    return;
  }
  let _ = btree_delete(tree, op.key);
  if op.payload.len() > 0 {
    if op.payload[0] != 1 { return; }
    var row = Vec[Int].new();
    var i = 1;
    while i < op.payload.len() {
      if op.payload[i] < 0 { return; }
      if op.payload[i] > 255 { return; }
      row.push(op.payload[i]);
      i = i + 1;
    }
    let _ = btree_insert_payload(tree, op.key, op.value, row);
    return;
  }
  let _ = btree_insert(tree, op.key, op.value);
}
// ===========================================================================
// DURABLE TRANSACTIONS (D2): single-active-transaction API. Operations are
// logged as they happen (WAL-before-ack) but applied to the tree only at
// commit; abort -- or a crash before the commit record -- discards them.
// Recovery classifies committed vs uncommitted at the Begin/Commit records
// (see db_file_open), so no physical undo pass is needed.
// ===========================================================================

pub fn db_file_txn_active(db: &DBFile) -> Bool {
  return db.txn_active;
}

// Lazy held append handle for the transaction window (BENCH-1 perf slice
// 2026-10-16): opened on first use, reused by every txn append, closed by
// commit/abort. One open/close pair per TRANSACTION instead of one per
// record (docs/BENCH-1.md finding #1). WAL appends stay ungated; the sync
// seam still fires the kind-1 gate exactly once per durable commit.
fn db_txn_fd(db: &mut DBFile) -> Int {
  if db.wal_fd >= 0 { return db.wal_fd; }
  match byteio_open_append(db.path) {
    None => { return -1; }
    Some(fd) => {
      db.wal_fd = fd;
      return fd;
    }
  }
}

// Close the held transaction handle (if any). Best-effort; the fd owner is
// the handle itself, so commit/abort must call this on every exit path.
fn db_txn_close_fd(db: &mut DBFile) {
  if db.wal_fd >= 0 {
    let _ = byteio_close_append(db.wal_fd);
    db.wal_fd = -1;
  }
}

// Public held-fd helpers shared by the txn window and auto-commit writes: one
// open append fd per handle (BENCH-1 finding #1 shape extended to puts). The
// owner closes it before any WAL truncate and on failure paths.
pub fn db_append_fd(db: &mut DBFile) -> Int {
  return db_txn_fd(db);
}

pub fn db_close_append_fd(db: &mut DBFile) {
  db_txn_close_fd(db);
}

pub fn db_file_txn_begin(db: &mut DBFile) -> Bool {
  if db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  wal_file_prepare(&mut db.wal);
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.BeginTxn, 0, 0);
  if lsn < 0 {
    db_txn_close_fd(db);
    return false;
  }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  db.txn_active = true;
  db.txn_ops = Vec[TxOp].new();
  db.sp_active = false;
  db.sp_marker = 0;
  return true;
}

// Buffered upsert (applied as delete+insert on commit/replay; idempotent).
pub fn db_file_txn_put(db: &mut DBFile, key: Int, value: Int) -> Bool {
  if !db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  wal_file_prepare(&mut db.wal);
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Update, key, value);
  if lsn < 0 { return false; }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  db.txn_ops.push(TxOp{ code: 2, key: key, value: value,
                        payload: Vec[Int].new() });
  return true;
}

// Buffered delete (idempotent: deleting a missing key is a no-op on apply).
pub fn db_file_txn_delete(db: &mut DBFile, key: Int) -> Bool {
  if !db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  wal_file_prepare(&mut db.wal);
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Delete, key, 0);
  if lsn < 0 { return false; }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  db.txn_ops.push(TxOp{ code: 3, key: key, value: 0,
                        payload: Vec[Int].new() });
  return true;
}

// Commit: append the CommitTxn record FIRST (durability), then apply the
// buffered ops to the in-memory tree. The whole window (Begin + ops +
// Commit) rides ONE held handle; immediate mode fsyncs it once, through the
// same gated sync seam as before, and a failed sync latches the handle.
pub fn db_file_txn_commit(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  wal_file_prepare(&mut db.wal);
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.CommitTxn, 0, 0);
  if lsn < 0 { return false; }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  var k = 0;
  while k < db.txn_ops.len() {
    let op = db.txn_ops[k];
    let old = btree_search(&db.tree, op.key);
    db_file_apply_txop(&mut db.tree, op);
    if op.code == 3 {
      db_file_note_value_change(db, op.key, old, 0, false);
    } else {
      db_file_note_value_change(db, op.key, old, op.value, true);
    }
    k = k + 1;
  }
  db.txn_active = false;
  db.txn_ops = Vec[TxOp].new();
  db.sp_active = false;
  db.sp_marker = 0;
  var sync_failed = false;
  if db.durability == 1 {
    if !byteio_sync_fd(fd) { sync_failed = true; }
  }
  db_txn_close_fd(db);
  if sync_failed { db.failed = true; return false; }
  return true;
}

// Abort: append the AbortTxn marker (audit trail) and discard the buffer.
pub fn db_file_txn_abort(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  wal_file_prepare(&mut db.wal);
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.AbortTxn, 0, 0);
  if lsn < 0 { return false; }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  db.txn_active = false;
  db.txn_ops = Vec[TxOp].new();
  db.sp_active = false;
  db.sp_marker = 0;
  db_txn_close_fd(db);
  return true;
}
// --- savepoints (txn-scoped) ----------------------------------------------

pub fn db_file_txn_savepoint_active(db: &DBFile) -> Bool {
  return db.sp_active;
}

// Record a rollback marker at the current buffer length (single level; false
// without an active transaction or when a savepoint is already active).
pub fn db_file_txn_savepoint(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if db.sp_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  db.sp_marker = db.txn_ops.len();
  db.sp_active = true;
  return true;
}

// Restore to the savepoint: trim the buffered ops, then splice the WAL window
// so recovery agrees with the buffer -- AbortTxn closes the current window
// (replay discards it), BeginTxn opens a fresh one, and the kept ops are
// re-logged verbatim. The savepoint stays active (SQL ROLLBACK TO SAVEPOINT
// semantics); commit/abort release it.
pub fn db_file_txn_savepoint_restore(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if !db.sp_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  while db.txn_ops.len() > db.sp_marker {
    db.txn_ops.pop();
  }
  wal_file_prepare(&mut db.wal);
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  var lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.AbortTxn, 0, 0);
  if lsn < 0 { return false; }
  lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.BeginTxn, 0, 0);
  if lsn < 0 { return false; }
  var appended = 2;
  var i = 0;
  while i < db.txn_ops.len() {
    let op = db.txn_ops[i];
    if op.code == 3 {
      lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Delete, op.key, 0);
    } else {
      lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Update, op.key, op.value);
    }
    if lsn < 0 { return false; }
    appended = appended + 1;
    i = i + 1;
  }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + appended;
  return true;
}

// Drop the savepoint marker (false without an active transaction/marker).
pub fn db_file_txn_savepoint_release(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if !db.sp_active { return false; }
  db.sp_active = false;
  db.sp_marker = 0;
  return true;
}