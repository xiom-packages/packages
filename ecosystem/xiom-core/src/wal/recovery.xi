module xiom.core.wal.recovery

use xiom.core.wal.wal_writer;

// Crash-recovery orchestration. `recovery_scan` replays the tail of the log
// after the last checkpoint and reports how many records would be reapplied
// plus the highest LSN observed. Real disk recovery (torn-page detection,
// checksum verification, redo/undo passes) is Phase 2 work.

pub type RecoveryResult = {
  records_replayed: Int;
  last_lsn: Int;
  corrupted: Bool;
}

pub fn recovery_scan(w: &WalWriter, from_checkpoint: Int) -> RecoveryResult {
  var count = 0;
  var last = from_checkpoint;
  var i = 0;
  while i < w.records.len() {
    if w.records[i].lsn > from_checkpoint {
      count = count + 1;
      if w.records[i].lsn > last {
        last = w.records[i].lsn;
      }
    }
    i = i + 1;
  }
  // TODO(Phase 2): real disk-based recovery with torn-page detection,
  // per-record checksum verification, and redo/undo of uncommitted txns.
  return RecoveryResult{ records_replayed: count, last_lsn: last, corrupted: false };
}
