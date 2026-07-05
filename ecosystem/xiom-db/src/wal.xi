module xiom.db.wal

pub enum WALOpType {
  InsertOp,
  UpdateOp,
  DeleteOp,
}

pub type WALEntry = {
  op: WALOpType;
  key: Int;
  value: Int;
  timestamp: Int;
}

pub type WAL = {
  entries: Vec[WALEntry];
}

pub fn wal_new() -> WAL {
  var entries = Vec[WALEntry].new();
  return WAL{ entries: entries };
}

pub fn wal_append(wal: &mut WAL, entry: WALEntry) {
  wal.entries.push(entry);
}

pub fn wal_replay(wal: &WAL, target: &mut BTree) -> Bool {
  var i = 0;
  var success = true;
  while i < wal.entries.len() {
    var entry = wal.entries[i];
    match entry.op {
      InsertOp => {
        var result = btree_insert(target, entry.key, entry.value);
        if !result { success = false; }
      }
      UpdateOp => {
        var found = btree_search(target, entry.key);
        match found {
          Some(_) => {
            var del = btree_delete(target, entry.key);
            if del {
              var ins = btree_insert(target, entry.key, entry.value);
              if !ins { success = false; }
            } else {
              success = false;
            }
          }
          None => { success = false; }
        }
      }
      DeleteOp => {
        var result = btree_delete(target, entry.key);
        if !result { success = false; }
      }
    }
    i = i + 1;
  }
  return success;
}

pub fn wal_clear(wal: &mut WAL) {
  var empty = Vec[WALEntry].new();
  wal.entries = empty;
}

pub fn wal_truncate(wal: &mut WAL, before_timestamp: Int)
  requires: before_timestamp >= 0
{
  var kept = Vec[WALEntry].new();
  var i = 0;
  while i < wal.entries.len() {
    if wal.entries[i].timestamp >= before_timestamp {
      kept.push(wal.entries[i]);
    }
    i = i + 1;
  }
  wal.entries = kept;
}

pub fn wal_len(wal: &WAL) -> Int {
  return wal.entries.len();
}

pub fn wal_is_empty(wal: &WAL) -> Bool {
  return wal.entries.len() == 0;
}

pub fn wal_entry_count(wal: &WAL, op_filter: WALOpType) -> Int {
  var count = 0;
  var i = 0;
  while i < wal.entries.len() {
    if wal.entries[i].op == op_filter {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}
