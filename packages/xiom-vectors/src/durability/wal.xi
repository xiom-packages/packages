// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.durability.wal

// In-memory write-ahead log primitives: record kinds, LSN assignment, append
// and resume. File-backed segments + fsync are a later Phase 2 step (blocked
// on the stdlib fd/fsync gap). Extracted from the consolidated engine.

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

pub type WalWriter = {
  records: Vec[WalRecord];
  next_lsn: Int;
  synced_lsn: Int;
}

pub fn wal_writer_new() -> WalWriter {
  var records = Vec[WalRecord].new();
  return WalWriter{ records: records, next_lsn: 1, synced_lsn: 0 };
}

pub fn wal_writer_append(w: &mut WalWriter, op: WalOpKind, key: Int, value: Int) -> Int {
  var assigned = w.next_lsn;
  var payload = Vec[Int].new();
  var rec = WalRecord{
    lsn: assigned, op: op, key: key, value: value, payload: payload, timestamp: 0,
  };
  w.records.push(rec);
  w.next_lsn = w.next_lsn + 1;
  return assigned;
}

pub fn wal_writer_current_lsn(w: &WalWriter) -> Int {
  return w.next_lsn - 1;
}

pub fn wal_writer_flush(w: &mut WalWriter) -> Bool {
  w.synced_lsn = w.next_lsn - 1;
  return true;
}

// Append a record carrying an opaque payload (encoded vectors / payloads).
// key = point id, value = collection id (recovery replays by key).
pub fn wal_writer_append_payload(w: &mut WalWriter, op: WalOpKind, key: Int, value: Int, payload: Vec[Int]) -> Int {
  var assigned = w.next_lsn;
  var rec = WalRecord{
    lsn: assigned, op: op, key: key, value: value, payload: payload, timestamp: 0,
  };
  w.records.push(rec);
  w.next_lsn = w.next_lsn + 1;
  return assigned;
}

// Resume a WAL after recovery: empty record buffer, LSN continuity preserved
// so post-recovery appends never reuse an LSN.
pub fn wal_writer_resume(next_lsn: Int) -> WalWriter {
  var records = Vec[WalRecord].new();
  return WalWriter{ records: records, next_lsn: next_lsn, synced_lsn: next_lsn - 1 };
}

// Memory accounting estimate (model constants: see the
// `hnsw_memory_estimate` header). WalRecord struct = 64 B (lsn, op tag,
// key, value, payload Vec header, timestamp); payload heap = 8 B/word.
pub fn wal_memory_estimate(w: &WalWriter) -> Int
  ensures: result >= 0
{
  var bytes: Int = 24; // records Vec header
  var i: Int = 0;
  while i < w.records.len() {
    bytes = bytes + 64 + w.records[i].payload.len() * 8;
    i = i + 1;
  }
  return bytes;
}
