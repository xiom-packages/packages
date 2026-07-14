module xiom.core.wal.checkpoint

// A checkpoint marks an LSN up to which all effects are known durable. WAL
// records strictly below the checkpoint LSN can be truncated because replay
// will never need them again.

pub type Checkpoint = {
  lsn: Int;
  timestamp: Int;
}

pub fn checkpoint_new(lsn: Int, timestamp: Int) -> Checkpoint {
  return Checkpoint{ lsn: lsn, timestamp: timestamp };
}

// A record is safe to truncate only if it precedes the checkpoint boundary.
pub fn checkpoint_can_truncate(cp: &Checkpoint, record_lsn: Int) -> Bool {
  return record_lsn < cp.lsn;
}
