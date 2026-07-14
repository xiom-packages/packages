module xiom.vector.durability.write_ahead_events

use xiom.core.wal.wal_writer;
use xiom.core.wal.wal_record;

// Vector-layer semantics on top of the shared core WAL. Rather than inventing a
// new log format, each vector event maps onto a core WalRecord (WAL-before-ack):
//   UpsertEvent  -> WalOpKind.Insert
//   DeleteEvent  -> WalOpKind.Delete
//   SegmentSeal  -> WalOpKind.SegmentSeal
// The returned LSN is the durability handle the engine acks to the caller.
// SCAFFOLD: the dense vector bytes are not yet serialized into the record
// payload (Phase 2).

pub enum VectorWalEvent {
  UpsertEvent(collection: Int, point: Int),
  DeleteEvent(collection: Int, point: Int),
  SegmentSeal(collection: Int, segment: Int),
}

pub fn log_upsert(w: &mut WalWriter, collection: Int, point: Int) -> Int {
  // TODO(Phase 2): serialize the dense vector into WalRecord.payload so the
  // point can be reconstructed on recovery.
  return wal_writer_append(w, WalOpKind.Insert, collection, point);
}

pub fn log_delete(w: &mut WalWriter, collection: Int, point: Int) -> Int {
  return wal_writer_append(w, WalOpKind.Delete, collection, point);
}

pub fn log_segment_seal(w: &mut WalWriter, collection: Int, segment: Int) -> Int {
  return wal_writer_append(w, WalOpKind.SegmentSeal, collection, segment);
}

pub fn event_op(e: &VectorWalEvent) -> WalOpKind {
  match e {
    UpsertEvent(_, _) => WalOpKind.Insert,
    DeleteEvent(_, _) => WalOpKind.Delete,
    SegmentSeal(_, _) => WalOpKind.SegmentSeal,
  }
}
