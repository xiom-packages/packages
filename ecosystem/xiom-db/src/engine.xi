module xiom.db.engine

pub type Engine = {
  tree: BTree;
  wal: WAL;
  timestamp_counter: Int;
}

pub fn engine_new(order: Int) -> Engine {
  var tree = btree_new(order);
  var wal = wal_new();
  return Engine{ tree: tree, wal: wal, timestamp_counter: 0 };
}

fn next_timestamp(eng: &mut Engine) -> Int {
  eng.timestamp_counter = eng.timestamp_counter + 1;
  return eng.timestamp_counter;
}

pub fn engine_insert(eng: &mut Engine, key: Int, value: Int) -> Bool {
  var ts = next_timestamp(eng);
  var entry = WALEntry{
    op: WALOpType.InsertOp, key: key, value: value, timestamp: ts,
  };
  wal_append(&mut eng.wal, entry);

  return btree_insert(&mut eng.tree, key, value);
}

pub fn engine_get(eng: &Engine, key: Int) -> Option[Int] {
  return btree_search(&eng.tree, key);
}

pub fn engine_delete(eng: &mut Engine, key: Int) -> Bool {
  var found = btree_search(&eng.tree, key);
  match found {
    None => return false;
    Some(v) => {}
  }

  var ts = next_timestamp(eng);
  var entry = WALEntry{
    op: WALOpType.DeleteOp, key: key, value: 0, timestamp: ts,
  };
  wal_append(&mut eng.wal, entry);

  return btree_delete(&mut eng.tree, key);
}

pub fn engine_update(eng: &mut Engine, key: Int, value: Int) -> Bool {
  var found = btree_search(&eng.tree, key);
  match found {
    None => return false;
    Some(_) => {}
  }

  var ts = next_timestamp(eng);
  var entry = WALEntry{
    op: WALOpType.UpdateOp, key: key, value: value, timestamp: ts,
  };
  wal_append(&mut eng.wal, entry);

  var del = btree_delete(&mut eng.tree, key);
  if !del { return false; }
  return btree_insert(&mut eng.tree, key, value);
}

pub fn engine_query(eng: &Engine, query: &Query) -> Vec[Int] {
  return query_execute(query, &eng.tree);
}

pub fn engine_recover(eng: &mut Engine) -> Bool {
  var fresh = btree_new(eng.tree.order);
  eng.tree = fresh;
  eng.timestamp_counter = 0;
  return wal_replay(&eng.wal, &mut eng.tree);
}

pub fn engine_range_query(eng: &Engine, low: Int, high: Int) -> Vec[Int] {
  return btree_range_query(&eng.tree, low, high);
}

pub fn engine_size(eng: &Engine) -> Int {
  return btree_size(&eng.tree);
}

pub fn engine_wal_size(eng: &Engine) -> Int {
  return wal_len(&eng.wal);
}

pub fn engine_flush_wal(eng: &mut Engine) {
  wal_clear(&mut eng.wal);
}

pub fn engine_truncate_wal(eng: &mut Engine, before_timestamp: Int) {
  wal_truncate(&mut eng.wal, before_timestamp);
}
