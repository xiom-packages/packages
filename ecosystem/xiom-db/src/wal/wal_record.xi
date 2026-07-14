module xiom.db.wal.wal_record

// The durable log record. A `WALEntry` captures one logical mutation
// (op, key, value) tagged with a monotonic `timestamp` that establishes replay
// order. This is deliberately the smallest self-describing unit the recovery
// path re-parses, so its shape must stay stable across versions.

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

pub fn wal_entry_new(op: WALOpType, key: Int, value: Int, timestamp: Int) -> WALEntry {
  return WALEntry{ op: op, key: key, value: value, timestamp: timestamp };
}
