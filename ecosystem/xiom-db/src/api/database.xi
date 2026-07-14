module xiom.db.api.database
use xiom.db.engine;
use xiom.db.query.query;
use xiom.db.config;

// The public database facade. This is the ONLY surface most callers need: it
// wraps the internal `Engine` behind a small, stable, verb-first API
// (open / insert / get / delete / query / close) and never leaks the index,
// WAL, or storage internals. Every method delegates to an engine function so
// there is exactly one implementation of each operation.

pub type Database = {
  engine: Engine;
  open: Bool;
}

// Open a database with an explicit B-tree order.
pub fn db_open(order: Int) -> Database
  requires: order >= 3
{
  var engine = engine_new(order);
  return Database{ engine: engine, open: true };
}

// Open using a validated DatabaseConfig profile.
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

// Recover the in-memory state by replaying the WAL. Returns false if any record
// failed to apply during replay.
pub fn db_recover(db: &mut Database) -> Bool {
  if !db.open { return false; }
  return engine_recover(&mut db.engine);
}

// Close the database. Flushes the WAL (checkpoint) and marks the handle closed;
// subsequent operations are rejected.
// TODO(Phase 2): fsync the durable WAL and page files before marking closed.
pub fn db_close(db: &mut Database) {
  if !db.open { return; }
  engine_flush_wal(&mut db.engine);
  db.open = false;
}
