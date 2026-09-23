module xiom.durable.wal.wal_writer

use xiom.durable.wal.wal_record;

// The single most important durability component: every acknowledged write
// must be appended here first (WAL-before-ack). This phase buffers records in
// memory and assigns LSNs; `synced_lsn` records how far durability has been
// confirmed. `flush` becomes a real fsync in Phase 2.

pub type WalWriter = {
  records: Vec[WalRecord];
  next_lsn: Int;
  synced_lsn: Int;
}

pub fn wal_writer_new() -> WalWriter {
  var records = Vec[WalRecord].new();
  return WalWriter{ records: records, next_lsn: 1, synced_lsn: 0 };
}

// Append a record, assign the next LSN, and return it. The LSN is guaranteed
// to be strictly greater than every previously assigned LSN.
pub fn wal_writer_append(w: &mut WalWriter, op: WalOpKind, key: Int, value: Int) -> Int {
  var assigned = w.next_lsn;
  var rec = wal_record_new(assigned, op, key, value);
  w.records.push(rec);
  w.next_lsn = w.next_lsn + 1;
  return assigned;
}

pub fn wal_writer_flush(w: &mut WalWriter) -> Bool {
  // TODO(Phase 2): fsync/fdatasync via FFI (core/ffi/os_file). Until then the
  // in-memory buffer is trivially durable, so we advance synced_lsn to the
  // last assigned LSN and report success.
  w.synced_lsn = w.next_lsn - 1;
  return true;
}

pub fn wal_writer_current_lsn(w: &WalWriter) -> Int {
  return w.next_lsn - 1;
}

pub fn wal_writer_synced_lsn(w: &WalWriter) -> Int {
  return w.synced_lsn;
}
