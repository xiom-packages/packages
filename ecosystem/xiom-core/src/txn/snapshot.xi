module xiom.core.txn.snapshot

// A read snapshot pins a consistent view of the log for the duration of a
// query so that segment fan-out sees a stable set of records. A record is
// visible to the snapshot when its LSN is at or below the snapshot LSN.

pub type Snapshot = {
  lsn: Int;
  active_txns: Vec[Int];
}

pub fn snapshot_new(lsn: Int) -> Snapshot {
  var active = Vec[Int].new();
  return Snapshot{ lsn: lsn, active_txns: active };
}

pub fn snapshot_is_visible(snap: &Snapshot, record_lsn: Int) -> Bool {
  return record_lsn <= snap.lsn;
}
