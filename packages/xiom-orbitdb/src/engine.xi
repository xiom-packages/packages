// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.engine


// ============================================================================
// XIOM-DB engine facade: DBFile + file-backed API. The B-tree, the in-memory
// query/WAL core, snapshot/pins and durable transactions live in sibling
// modules (re-exported here so `use xiom.db.engine` keeps the 0.2.x surface).
// ============================================================================

use xiom.io;
use xiom.db.wal_file;
use xiom.db.storage.page;
use xiom.db.storage.page_file;
use xiom.db.storage.block;
use xiom.db.storage.block_store;
use xiom.db.storage.byte_io;
use xiom.db.index.node_page;
use xiom.db.storage.tuple;
use xiom.db.error;
use xiom.db.contracts;
use xiom.db.secondary_index;
use xiom.db.catalog.schema;
use xiom.os.lock;

pub use xiom.db.index.btree;
pub use xiom.db.engine.core;
pub use xiom.db.engine.snapshot;
pub use xiom.db.engine.txn;

// M3 shard ownership: at most one held whole-file advisory lock per process
// (the Station opens one DB per shard). FileLock is non-Clone and owns its
// fd, so the registry is a one-element Vec that pop() moves into release.
var g_lock: Vec[FileLock] = Vec[FileLock].new();
var g_lock_path: Str = "";




// In-order walk collecting (key, payload) pairs of payload-bearing entries.
fn collect_typed_inorder(tree: &BTree, node_idx: Int,
                         keys: &mut Vec[Int], pays: &mut Vec[Vec[Int]]) {
  var node = ns_get(&tree.store, node_idx);
  if node.is_leaf {
    var i = 0;
    while i < node.keys.len() {
      let p = node_payload(&node, i);
      if p.len() > 0 {
        keys.push(node.keys[i]);
        pays.push(p);
      }
      i = i + 1;
    }
    return;
  }
  var i = 0;
  while i < node.keys.len() {
    if i < node.children.len() {
      collect_typed_inorder(tree, node.children[i], keys, pays);
    }
    let p = node_payload(&node, i);
    if p.len() > 0 {
      keys.push(node.keys[i]);
      pays.push(p);
    }
    i = i + 1;
  }
  if i < node.children.len() {
    collect_typed_inorder(tree, node.children[i], keys, pays);
  }
}

// Matching primary keys in key order (conditions ANDed; offset/limit apply
// to the matches). Plain int rows and undecodable payloads never match:
// typed predicates apply to typed rows.
pub fn db_file_query_typed(db: &DBFile, q: &TypedQuery) -> Vec[Int] {
  var keys = Vec[Int].new();
  var pays = Vec[Vec[Int]].new();
  collect_typed_inorder(&db.tree, db.tree.root, &mut keys, &mut pays);

  var hits = Vec[Int].new();
  var i = 0;
  while i < keys.len() {
    let p = pays[i];
    match tuple2_decode_row(&p) {
      Err(_) => {}
      Ok(row) => {
        let r: TypedRow = row;
        if typed_row_matches(&r, q.conditions) { hits.push(keys[i]); }
      }
    }
    i = i + 1;
  }

  var out = Vec[Int].new();
  var start = q.offset;
  var end = hits.len();
  if q.limit > 0 && start + q.limit < end {
    end = start + q.limit;
  }
  var k = start;
  while k < end {
    out.push(hits[k]);
    k = k + 1;
  }
  return out;
}

pub fn query_reset(q: &mut Query) {
  var empty = Vec[QueryCondition].new();
  q.conditions = empty;
  q.limit = 0;
  q.offset = 0;
  q.has_bounds = false;
  q.low = 0;
  q.high = 0;
  q.order = 0;
}

// Result ordering (M4.2): 0 = key ascending (default), 1 = value ascending,
// 2 = value descending. Ties keep key order; offset/limit apply after.
pub fn query_order(q: &mut Query, order: Int)
  requires: order == 0 || order == 1 || order == 2
{
  q.order = order;
}

pub fn query_order_kind(q: &Query) -> Int {
  return q.order;
}



// ============================================================================
// DATABASE API (from xiom.db.api.database)
// ============================================================================

pub type DatabaseConfig = {
  page_size: Int;
  buffer_pool_capacity: Int;
  wal_enabled: Bool;
  btree_order: Int;
}

pub type Database = {
  engine: Engine;
  open: Bool;
}

pub fn db_open(order: Int) -> Database
  requires: order >= 3
{
  var engine = engine_new(order);
  return Database{ engine: engine, open: true };
}

pub fn db_open_with(config: &DatabaseConfig) -> Database
  requires: config.btree_order >= 3
{
  var engine = engine_new(config.btree_order);
  return Database{ engine: engine, open: true };
}

pub fn db_insert(db: &mut Database, key: Int, value: Int) -> Bool {
  if !db.open { return false; }
  return engine_insert(&mut db.engine, key, value);
}

pub fn db_get(db: &Database, key: Int) -> Option[Int] {
  if !db.open { return None; }
  return engine_get(&db.engine, key);
}

pub fn db_update(db: &mut Database, key: Int, value: Int) -> Bool {
  if !db.open { return false; }
  return engine_update(&mut db.engine, key, value);
}

pub fn db_delete(db: &mut Database, key: Int) -> Bool {
  if !db.open { return false; }
  return engine_delete(&mut db.engine, key);
}

pub fn db_query(db: &Database, query: &Query) -> Vec[Int] {
  if !db.open { return Vec[Int].new(); }
  return engine_query(&db.engine, query);
}

pub fn db_range(db: &Database, low: Int, high: Int) -> Vec[Int]
  requires: low <= high
{
  if !db.open { return Vec[Int].new(); }
  return engine_range_query(&db.engine, low, high);
}

pub fn db_size(db: &Database) -> Int {
  if !db.open { return 0; }
  return engine_size(&db.engine);
}

pub fn db_recover(db: &mut Database) -> Bool {
  if !db.open { return false; }
  return engine_recover(&mut db.engine);
}

pub fn db_close(db: &mut Database) {
  if !db.open { return; }
  engine_flush_wal(&mut db.engine);
  db.open = false;
}

// ===========================================================================
// File-backed database facade (Phase 1/B4): WAL-before-ack on a real segment
// ===========================================================================

// A database whose log is the durable WAL segment (src/wal_file.xi). Every
// mutating call appends the record FIRST and only then applies it to the
// in-memory B-tree; `db_file_open` rebuilds the tree by replaying the segment
// (torn tail skipped). Data pages still rebuild from the log on open; the
// durable page file (storage/page_file.xi) takes over persistence next.
//
// Durability honesty (M2.1 second half, M1.2 S4 2026-10-13): `db_file_flush`
// is the wal_file flush seam and is now a REAL fsync (sync_io.sync_fd). With
// durability mode 1 (default) + two_phase, commits and checkpoint publishes
// are power-loss honest up to the synced seams. Until the next compiler pin
// re-vendors stdlib/runtime, run with XIOM_RUNTIME_DIR=<stdlib>/runtime
// (scripts/dev-env.* sets it).

pub type DBFile = {
  path: Str;
  order: Int;
  tree: BTree;
  wal: WALFile;
  records_since_ckpt: Int;
  txn_active: Bool;
  txn_ops: Vec[TxOp];
  wal_bytes: Int;
  page_format: Int;
  // Secondary indexes over VALUES (M4.2); handle-scoped, rebuilt on open via
  // `db_file_create_index`. Maintained by put/delete/txn-commit.
  indexes: Vec[SecondaryIndex];
  // Durability (M2.1): 0 = normal (ack without a flush; sync at
  // checkpoint only), 1 = immediate (REAL fsync at every commit ack since
  // M1.2 S4; stdlib wave 115). `two_phase` (immediate only) flushes the WAL
  // before a checkpoint publishes its snapshot. A failed flush latches
  // `failed`: writers refuse until the handle is reopened.
  durability: Int;
  two_phase: Bool;
  failed: Bool;
  // Last committed snapshot generation (0 = none), for `DBSnapshot`.
  snap_generation: Int;
  // M3 savepoint (single level): active marker + buffer length at capture.
  sp_active: Bool;
  sp_marker: Int;
  // Held append handle for the transaction window (BENCH-1 perf slice
  // 2026-10-16): one open per TRANSACTION instead of one per record; -1 when
  // no transaction holds it. Owned here, closed by commit/abort; a leaked fd
  // at process exit is harmless (segment appends are appended atomically).
  // Held append fd for the txn window AND auto-commit writes (one open per
  // handle); -1 = closed. Closed before any WAL truncate/checkpoint.
  wal_fd: Int;
}



// Open (or create) a file-backed database. Recovery: load the checkpoint
// snapshot when present, then replay ONLY records newer than its
// checkpoint_lsn; without a snapshot, replay the whole segment (Phase 1/B
// behavior). The torn tail is healed once by `wal_file_open`. **The v2
// byte-block container is the DEFAULT since M1.2 S4** (2026-10-13); v1
// (text page log) stays fully supported for reads (auto-detected on the
// on-disk format) and for writes via `db_file_open_cfg(path, order, 1)`.
// The handle's format decides how the next checkpoint writes, migrating a
// v1 file to v2 on its first write (migration-on-write).
pub fn db_file_open(path: Str, order: Int) -> DBFile {
  return db_file_open_cfg(path, order, 2);
}

pub fn db_file_open_cfg(path: Str, order: Int, page_format: Int) -> DBFile {
  var tree = btree_new(order);
  var snap_lsn = 0;
  var snap_gen = 0;
  let snap_path = path + ".snap";
  // Snapshot reads auto-detect the on-disk format: 'O' (0x4F) first byte =
  // v2 block store; anything else = v1 text page log (healed on open).
  let loaded = snap_load_auto(snap_path);
  match loaded {
    None => {}
    Some(s) => {
      let snap: Snapshot = s;
      tree = snap.tree;
      snap_lsn = snap.checkpoint_lsn;
      snap_gen = snap.generation;
    }
  }

  // Transaction-aware replay: writes between BeginTxn and CommitTxn are
  // buffered and applied only at the commit record; an unterminated trailing
  // transaction (crash before commit) is discarded -- committed/uncommitted
  // classification without a physical undo pass.
  let records = wal_file_replay(path);
  var pending = Vec[TxOp].new();
  var in_txn = false;
  var i = 0;
  while i < records.len() {
    let rec = records[i];
    if rec.lsn > snap_lsn {
      let code = wal_op_code(rec.op);
      if code == TXN_BEGIN_CODE {
        in_txn = true;
        pending = Vec[TxOp].new();
      } else if code == TXN_COMMIT_CODE {
        if in_txn {
          var p = 0;
          while p < pending.len() {
            let op = pending[p];
            db_file_apply_txop(&mut tree, op);
            p = p + 1;
          }
        }
        in_txn = false;
        pending = Vec[TxOp].new();
      } else if code == TXN_ABORT_CODE {
        in_txn = false;
        pending = Vec[TxOp].new();
      } else if code == 1 || code == 2 || code == 3 {
        if in_txn {
          pending.push(TxOp{ code: code, key: rec.key, value: rec.value,
                             payload: rec.payload });
        } else {
          db_file_apply_record(&mut tree, rec);
        }
      }
    }
    i = i + 1;
  }
  var wal = wal_file_open(path);
  if in_txn {
    // A dangling transaction window (crash before Commit/Abort) is finalized
    // with an explicit Abort record: without it, writes made after this open
    // would be replayed inside the stale window and silently discarded.
    let _ = wal_file_append(&mut wal, WALOpKind.AbortTxn, 0, 0);
  }
  var ops = Vec[TxOp].new();
  let wal_bytes = db_wal_size(path);
  var indexes = Vec[SecondaryIndex].new();
  return DBFile{ path: path, order: tree.order, tree: tree, wal: wal,
                 records_since_ckpt: 0, txn_active: false, txn_ops: ops,
                 wal_bytes: wal_bytes, page_format: page_format,
                 indexes: indexes, durability: 1, two_phase: false,
                 failed: false, snap_generation: snap_gen, sp_active: false,
                 sp_marker: 0, wal_fd: -1 };
}

// ---------------------------------------------------------------------------
// Input validation (H2): a path is a filename, not data -- reject empty,
// overlong, and line-terminator-carrying paths before creating a handle (the
// codecs are line-oriented, so CR/LF would corrupt diagnostics and tooling).
// ---------------------------------------------------------------------------

pub fn db_path_valid(path: Str) -> Bool {
  if str_len(path) == 0 { return false; }
  if str_len(path) > 4096 { return false; }
  if str_contains(path, "\n") { return false; }
  if str_contains(path, "\r") { return false; }
  return true;
}

// Validated open: Err(ConstraintViolation) for an invalid path or a btree
// order below 3; otherwise Ok with a handle from `db_file_open` (which is kept
// unchanged for existing callers).
pub fn db_file_open_checked(path: Str, order: Int) -> Result[DBFile, DbError] {
  if !db_path_valid(path) {
    return Err(DbError.ConstraintViolation);
  }
  if !valid_btree_order(order) {
    return Err(DbError.ConstraintViolation);
  }
  return Ok(db_file_open(path, order));
}

// Validated open with an explicit snapshot container format (1 = v1 text
// page log, 2 = v2 byte blocks). Reads always auto-detect the on-disk
// format; page_format only steers the next checkpoint's write.
pub fn db_file_open_checked_cfg(path: Str, order: Int, page_format: Int) -> Result[DBFile, DbError] {
  if !db_path_valid(path) {
    return Err(DbError.ConstraintViolation);
  }
  if !valid_btree_order(order) {
    return Err(DbError.ConstraintViolation);
  }
  if page_format != 1 && page_format != 2 {
    return Err(DbError.ConstraintViolation);
  }
  return Ok(db_file_open_cfg(path, order, page_format));
}

// ---------------------------------------------------------------------------
// M3 shard ownership: exclusive cross-process open.
//
// The Station opens one DB per shard; `file_lock` (xiom.os.lock, stdlib wave
// 152) gives cooperating processes a whole-file advisory lock. We lock a
// dedicated `<path>.lock` sentinel, never the DB/WAL/snapshot: checkpoints
// rename the snapshot, and a lock attached to an inode detaches on rename.
// The sentinel is created once and kept (never deleted while a lock may be
// held). Advisory only: a process that does not cooperate can still open the
// file; the embedded `db_file_open` keeps the optimistic stale-handle guard.
//
// One lock per process (the shard model); a second locked open while held
// returns Err(StorageError), including on POSIX where same-process fds do
// not contend. Release with `db_file_unlock(path)` or by exiting the process.
// ---------------------------------------------------------------------------

fn db_lock_sentinel(path: Str) -> Str {
  return path + ".lock";
}

fn db_lock_ensure_sentinel(lp: Str) -> Bool {
  match io.file_size(lp) {
    Some(_) => { return true; }
    None => {
      match io.write_file(lp, "") {
        Ok(_) => { return true; }
        Err(_) => { return false; }
      }
    }
  }
}

pub fn db_file_open_locked_checked(path: Str, order: Int) -> Result[DBFile, DbError] {
  return db_file_open_locked_checked_cfg(path, order, 2);
}

// Exclusive shard open. Err(StorageError) means the lock is held elsewhere,
// this process already holds one, or the sentinel could not be created.
pub fn db_file_open_locked_checked_cfg(path: Str, order: Int,
                                        page_format: Int) -> Result[DBFile, DbError] {
  if !db_path_valid(path) { return Err(DbError.ConstraintViolation); }
  if !valid_btree_order(order) { return Err(DbError.ConstraintViolation); }
  if page_format != 1 && page_format != 2 { return Err(DbError.ConstraintViolation); }
  if g_lock.len() > 0 { return Err(DbError.StorageError); }
  let lp = db_lock_sentinel(path);
  if !db_lock_ensure_sentinel(lp) { return Err(DbError.StorageError); }
  match lock.file_lock_try(lp) {
    Ok(held) => {
      g_lock.push(held);
      g_lock_path = lp;
    }
    Err(_) => { return Err(DbError.StorageError); }
  }
  match db_file_open_checked_cfg(path, order, page_format) {
    Ok(db) => { return Ok(db); }
    Err(e) => {
      let _ = db_file_unlock(path);
      return Err(e);
    }
  }
}

// Release this process's shard lock (false when it does not hold one).
pub fn db_file_unlock(path: Str) -> Bool {
  let lp = db_lock_sentinel(path);
  if g_lock_path != lp { return false; }
  let held = g_lock.pop();
  match held {
    Some(l) => {
      lock.file_lock_release(l);
      // Vec.pop may leave the element in the type-level vector (copy-without-
      // remove for a non-Clone element); reset it so it cannot block the next
      // locked open. The released FileLock's fd is already closed.
      g_lock = Vec[FileLock].new();
      g_lock_path = "";
      return true;
    }
    None => {
      g_lock = Vec[FileLock].new();
      g_lock_path = "";
      return false;
    }
  }
}

pub fn db_file_is_locked(path: Str) -> Bool {
  return g_lock_path == db_lock_sentinel(path);
}

// Release the held append fd (the handle stays usable; the next write
// reopens lazily). Call this before deleting/renaming a DB file from the
// same process: a held fd keeps the WAL open and blocks the delete on
// Windows.
pub fn db_file_close(db: &mut DBFile) {
  db_close_append_fd(db);
}


// Upsert with WAL-before-ack: append (Insert for new keys, Update for
// existing), then apply. Returns false when the log write fails.
pub fn db_file_put(db: &mut DBFile, key: Int, value: Int) -> Bool {
  // Auto-commit writes are rejected while a transaction is open.
  if db.txn_active { return false; }
  // Stale handle: another writer appended since our last write.
  if !db_file_guard(db) { db_close_append_fd(db); return false; }
  // Latched after a failed flush/commit: refuse until reopen.
  if db.failed { return false; }
  // Qualified: this module imports wal_file but a program may also contain
  // txn's same-named WALOp variants; m225 scopes UNQUALIFIED resolution to the
  // declaring module, not to the importing consumer (see COMPILER-FINDINGS).
  var op = WALOpKind.Insert;
  var is_update = false;
  let existing = btree_search(&db.tree, key);
  match existing {
    None => {}
    Some(_) => {
      op = WALOpKind.Update;
      is_update = true;
    }
  }
  // Held append fd (one open per handle, reused across puts): the same shape
  // the txn window uses. -1 write failure; a failed gated sync latches.
  wal_file_prepare(&mut db.wal);
  let fd = db_append_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, op, key, value);
  if lsn < 0 { db_close_append_fd(db); return false; }
  var sync_failed = false;
  if db.durability == 1 {
    if !byteio_sync_fd(fd) { sync_failed = true; }
  }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  if is_update { let _ = btree_delete(&mut db.tree, key); }
  let inserted = btree_insert(&mut db.tree, key, value);
  if inserted { db_file_note_value_change(db, key, existing, value, true); }
  if !inserted { return false; }
  if sync_failed { db_close_append_fd(db); db.failed = true; return false; }
  return true;
}

// Max typed-row payload bytes for a btree order: the largest node page
// (order-1 entries, order children; 28-byte node header + 16 bytes per
// key/value + 8 bytes payload framing + the payload itself) must fit the
// smaller snapshot container budget (v2 block payload capacity). A
// `db_file_put_typed` above this is refused up front -- a checkpoint could
// otherwise fail only at snapshot time.
pub fn db_file_typed_payload_max(order: Int) -> Int {
  if order < 3 { return 0; }
  let keys = order - 1;
  let overhead = NODE_PAGE_HEADER_BYTES + 24 * keys + 8 * order;
  let room = block.block_payload_capacity() - overhead;
  if room <= 0 { return 0; }
  let per = room / keys;
  if per <= 0 { return 0; }
  return per;
}

// Typed-row upsert (M5.3): the payload is opaque row bytes (tuple codec v2
// rows or any caller encoding); the WAL record carries subtype 1 + the row
// bytes and its `value` mirrors the key (the pk). Same guards as
// `db_file_put`; typed writes are non-transactional in S3 (txn paths refuse
// while a transaction is active). Indexes hold int values only: any stale
// entry for the key is dropped, none is added (typed-column indexes = S4).
pub fn db_file_put_typed(db: &mut DBFile, key: Int, payload: Vec[Int]) -> Bool {
  if db.txn_active { return false; }
  if !db_file_guard(db) { db_close_append_fd(db); return false; }
  if db.failed { return false; }
  if payload.len() > db_file_typed_payload_max(db.order) { return false; }
  // Payload bytes are 0..255 (the storage byte convention; the snapshot
  // codecs mask to a byte). Refuse anything else instead of losing bits.
  var v = 0;
  while v < payload.len() {
    if payload[v] < 0 { return false; }
    if payload[v] > 255 { return false; }
    v = v + 1;
  }
  var op = WALOpKind.Insert;
  var is_update = false;
  let existing = btree_search(&db.tree, key);
  match existing {
    None => {}
    Some(_) => {
      op = WALOpKind.Update;
      is_update = true;
    }
  }
  var tagged = Vec[Int].new();
  tagged.push(1); // subtype: typed row (tuple v2 bytes)
  var i = 0;
  while i < payload.len() {
    tagged.push(payload[i]);
    i = i + 1;
  }
  wal_file_prepare(&mut db.wal);
  let fd = db_append_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_tagged_fd(&mut db.wal, fd, op, key, key, tagged, 0);
  if lsn < 0 { db_close_append_fd(db); return false; }
  var sync_failed = false;
  if db.durability == 1 {
    if !byteio_sync_fd(fd) { sync_failed = true; }
  }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  if is_update { let _ = btree_delete(&mut db.tree, key); }
  let inserted = btree_insert_payload(&mut db.tree, key, key, payload);
  if inserted { db_file_note_value_change(db, key, existing, 0, false); }
  if !inserted { return false; }
  if sync_failed { db_close_append_fd(db); db.failed = true; return false; }
  return true;
}

pub fn db_file_delete(db: &mut DBFile, key: Int) -> Bool {
  // Auto-commit writes are rejected while a transaction is open.
  if db.txn_active { return false; }
  // Stale handle: another writer appended since our last write.
  if !db_file_guard(db) { db_close_append_fd(db); return false; }
  if db.failed { return false; }
  let existing = btree_search(&db.tree, key);
  match existing {
    None => { return false; }
    Some(_) => {}
  }
  wal_file_prepare(&mut db.wal);
  let fd = db_append_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Delete, key, 0);
  if lsn < 0 { db_close_append_fd(db); return false; }
  var sync_failed = false;
  if db.durability == 1 {
    if !byteio_sync_fd(fd) { sync_failed = true; }
  }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  let removed = btree_delete(&mut db.tree, key);
  if removed { db_file_note_value_change(db, key, existing, 0, false); }
  if !removed { return false; }
  if sync_failed { db.failed = true; return false; }
  return true;
}

pub fn db_file_get(db: &DBFile, key: Int) -> Option[Int] {
  return btree_search(&db.tree, key);
}

// M5.3: read a typed row's payload (None when the key is absent or the entry
// is a plain int row). Int rows keep reading through `db_file_get`.
pub fn db_file_get_typed(db: &DBFile, key: Int) -> Option[Vec[Int]] {
  return btree_search_payload(&db.tree, key);
}

// Key-range access on the live/recovered tree: values for keys in [low, high]
// inclusive, in key order. Mirrors `db_range`; same contract as
// `btree_range_query`.
pub fn db_file_range(db: &DBFile, low: Int, high: Int) -> Vec[Int]
  requires: low <= high
{
  return btree_range_query(&db.tree, low, high);
}

// Key/value pairs in [low, high] (admin/Station range views).
pub fn db_file_range_pairs(db: &DBFile, low: Int, high: Int) -> Vec[(Int, Int)]
  requires: low <= high
{
  return btree_range_pairs(&db.tree, low, high);
}

// Value-filter query on the live/recovered tree, planned and executed:
// conditions filter VALUES (not keys), key bounds (query_key_range) restrict
// the scanned key range first, a secondary index (M4.2) narrows value
// probes when present, `order` (default 0 = key ascending) sorts before
// `offset` skips matching values and `limit` truncates.
pub fn db_file_query(db: &DBFile, query: &Query) -> Vec[Int] {
  let plan = plan_query_with_index(query, &db.tree, db.indexes.len() > 0);
  if plan.kind == PlanKind.IndexValue && db.indexes.len() > 0 {
    let idx = db.indexes[0];
    return execute_index_value(&idx, &plan, query);
  }
  return execute_plan(&plan, query, &db.tree);
}

// ===========================================================================
// SECONDARY INDEXES (M4.2): value-ordered (value, pk) entries maintained by
// put/delete/txn-commit; handle-scoped, rebuilt on open. See
// src/secondary_index.xi for the structure.
// ===========================================================================


// Build a secondary index over the current tree; false for an empty name or
// a name already present.
pub fn db_file_create_index(db: &mut DBFile, name: Str) -> Bool {
  if str_len(name) == 0 { return false; }
  var i = 0;
  while i < db.indexes.len() {
    if db.indexes[i].name == name { return false; }
    i = i + 1;
  }
  var idx = secidx_new(name);
  var keys = Vec[Int].new();
  var vals = Vec[Int].new();
  btree_collect_pairs(&db.tree, db.tree.root, &mut keys, &mut vals);
  var j = 0;
  while j < keys.len() {
    secidx_add(&mut idx, vals[j], keys[j]);
    j = j + 1;
  }
  db.indexes.push(idx);
  return true;
}

pub fn db_file_drop_index(db: &mut DBFile, name: Str) -> Bool {
  var i = 0;
  while i < db.indexes.len() {
    if db.indexes[i].name == name {
      var j = i;
      while j < db.indexes.len() - 1 {
        db.indexes[j] = db.indexes[j + 1];
        j = j + 1;
      }
      db.indexes.pop();
      return true;
    }
    i = i + 1;
  }
  return false;
}

pub fn db_file_index_count(db: &DBFile) -> Int {
  return db.indexes.len();
}

pub fn db_file_index_name(db: &DBFile, at: Int) -> Str {
  if at < 0 || at >= db.indexes.len() { return ""; }
  return db.indexes[at].name;
}

// Direct probe for tests/tools: primary keys whose values fall in [lo, hi],
// in (value, pk) order.
pub fn db_file_index_range(db: &DBFile, name: Str, lo: Int, hi: Int) -> Vec[Int] {
  var i = 0;
  while i < db.indexes.len() {
    if db.indexes[i].name == name {
      let idx = db.indexes[i];
      return secidx_range_pks(&idx, lo, hi);
    }
    i = i + 1;
  }
  var empty = Vec[Int].new();
  return empty;
}

// Catalog tie-in: a flat-store index is over the value column (0) and
// non-unique; unique enforcement and multi-column indexes are later slices.
pub fn db_file_create_index_from_def(db: &mut DBFile, def: &IndexDef) -> Bool {
  if def.column != 0 { return false; }
  if def.unique { return false; }
  return db_file_create_index(db, def.name);
}

pub fn db_file_size(db: &DBFile) -> Int {
  return btree_size(&db.tree);
}

pub fn db_file_last_lsn(db: &DBFile) -> Int {
  return wal_file_next_lsn(&db.wal) - 1;
}

pub fn db_file_flush(db: &mut DBFile) -> Bool {
  if db.failed { return false; }
  let ok = byteio_sync(db.path);
  if !ok { db.failed = true; }
  return ok;
}

// --- durability API (M2.1 first half) --------------------------------------

// 0 = normal (ack without a flush), 1 = immediate (flush at every commit
// ack); invalid modes are rejected.
pub fn db_file_set_durability(db: &mut DBFile, mode: Int) -> Bool {
  if mode != 0 && mode != 1 { return false; }
  db.durability = mode;
  return true;
}

// Two-phase checkpoints flush the WAL before the snapshot publishes its
// header; only meaningful in immediate mode.
pub fn db_file_set_two_phase(db: &mut DBFile, enabled: Bool) -> Bool {
  if enabled && db.durability != 1 { return false; }
  db.two_phase = enabled;
  return true;
}

pub fn db_file_durability(db: &DBFile) -> Int { return db.durability; }

pub fn db_file_two_phase(db: &DBFile) -> Bool { return db.two_phase; }

pub fn db_file_failed(db: &DBFile) -> Bool { return db.failed; }

// (db_file_commit_sync was retired in the BENCH-1 perf slice 2026-10-16:
// auto-commit paths now sync inside `wal_file_append_sync` and the txn path
// syncs its held fd once at commit -- both through the same fault-gated
// byte_io sync seam, with the same latch-on-failure semantics.)



