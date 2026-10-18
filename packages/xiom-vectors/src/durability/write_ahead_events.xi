// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.durability.write_ahead_events

// Vector-specific WAL event constructors. Record layout for vectors:
// key = point id, value = collection id, payload = encoded vector
// ([dim, bits...]); metadata updates carry the encoded Payload.
// Extracted from the consolidated engine.

use xiom.vector.durability.wal;

pub fn log_upsert(w: &mut WalWriter, collection: Int, point: Int, payload: Vec[Int]) -> Int {
  return wal_writer_append_payload(w, WalOpKind.Insert, point, collection, payload);
}

pub fn log_delete(w: &mut WalWriter, collection: Int, point: Int) -> Int {
  return wal_writer_append(w, WalOpKind.Delete, point, collection);
}

// Metadata update record: key = point id, payload = encoded Payload
// (payload_encode). WalOpKind.Update is the metadata record kind.
pub fn log_payload_set(w: &mut WalWriter, collection: Int, point: Int, words: Vec[Int]) -> Int {
  return wal_writer_append_payload(w, WalOpKind.Update, point, collection, words);
}
