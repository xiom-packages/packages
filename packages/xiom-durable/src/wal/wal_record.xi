module xiom.durable.wal.wal_record

// The canonical serialized form of a durable event. Both xiom-db and
// xiom-vector extend the operation set through tagged payloads rather than
// forking the record layout, so recovery only ever parses one shape.

pub enum WalOpKind {
  Insert,
  Update,
  Delete,
  SegmentSeal,
  ManifestUpdate,
  Checkpoint,
  SnapshotMarker,
}

pub type WalRecord = {
  lsn: Int;
  op: WalOpKind;
  key: Int;
  value: Int;
  payload: Vec[Int];
  timestamp: Int;
}

pub fn wal_record_new(lsn: Int, op: WalOpKind, key: Int, value: Int) -> WalRecord {
  var payload = Vec[Int].new();
  return WalRecord{
    lsn: lsn,
    op: op,
    key: key,
    value: value,
    payload: payload,
    timestamp: 0,
  };
}
