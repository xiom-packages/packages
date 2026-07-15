module xiom.core.wal.wal_reader

use xiom.core.wal.wal_writer;
use xiom.core.wal.wal_record;

// Sequential and point-in-time WAL readers used by recovery, repair tooling,
// and snapshot validation. In this phase they read straight from the writer's
// in-memory buffer; the disk reader with checksum verification lands in Phase 2.

pub fn wal_read_all(w: &WalWriter) -> Vec[WalRecord] {
  var out = Vec[WalRecord].new();
  var i = 0;
  while i < w.records.len() {
    out.push(w.records[i]);
    i = i + 1;
  }
  return out;
}

// Return every record with lsn >= from_lsn, preserving append order.
pub fn wal_read_from(w: &WalWriter, from_lsn: Int) -> Vec[WalRecord] {
  var out = Vec[WalRecord].new();
  var i = 0;
  while i < w.records.len() {
    if w.records[i].lsn >= from_lsn {
      out.push(w.records[i]);
    }
    i = i + 1;
  }
  return out;
}
