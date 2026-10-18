// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.durability.recovery

// WAL replay + checkpoint compaction: rebuild the vector store and payload
// store from a log, and re-encode live state as a compacted checkpoint log
// so a recovered engine is itself recoverable. Extracted from the
// consolidated engine.

use xiom.vector.durability.wal;
use xiom.vector.storage.vector_store;
use xiom.vector.payload.payload;

// ---- Recovery: replay a WAL into a fresh store + payload store ----
// Replay in LSN order: Insert -> store, Delete -> store+payload removal,
// Update -> payload set/overwrite. Malformed record payloads are skipped
// (torn-tail tolerance). Records of any other kind are ignored for now.
pub type RecoveredState = {
  store: VectorIndex;
  payloads: PayloadStore;
}

pub fn recover_state(w: &WalWriter, dim: Int) -> RecoveredState
  requires: dim > 0
{
  var idx = index_new(dim);
  var pls = payload_store_new();
  var i: Int = 0;
  while i < w.records.len() {
    var op = w.records[i].op;
    var key = w.records[i].key;
    match op {
      Insert => {
        match vector_decode(&w.records[i].payload) {
          Some(v) => {
            if v.dimension == dim { index_add(&mut idx, key, v); }
          }
          None => {}
        }
      }
      Delete => {
        index_remove(&mut idx, key);
        payload_store_remove(&mut pls, key);
      }
      Update => {
        match payload_decode(&w.records[i].payload) {
          Some(p) => { payload_store_put(&mut pls, key, p); }
          None => {}
        }
      }
      _ => {}
    }
    i = i + 1;
  }
  return RecoveredState{ store: idx, payloads: pls };
}

pub fn recover_store(w: &WalWriter, dim: Int) -> VectorIndex
  requires: dim > 0
{
  var st = recover_state(w, dim);
  return st.store;
}

// Compacted checkpoint log: re-encode every live point of `idx` as an Insert
// record and every payload as an Update record, with fresh LSNs continuing
// after `w`. The returned log alone reconstructs the store + metadata, so a
// reopened engine can itself be reopened. This is the recovery-time
// compaction step; a durable manifest (Phase 2) will later persist it
// instead of rebuilding on every open.
pub fn wal_writer_checkpoint_from(w: &WalWriter, idx: &VectorIndex, payloads: &PayloadStore) -> WalWriter {
  var out = wal_writer_resume(w.next_lsn);
  var i: Int = 0;
  while i < idx.ids.len() {
    wal_writer_append_payload(&mut out, WalOpKind.Insert, idx.ids[i], 1, vector_encode(&idx.vectors[i]));
    i = i + 1;
  }
  var j: Int = 0;
  while j < payloads.entries.len() {
    wal_writer_append_payload(&mut out, WalOpKind.Update, payloads.entries[j].id, 1, payload_encode(&payloads.entries[j].payload));
    j = j + 1;
  }
  // Carry the latest collection manifest forward so chained recovery
  // preserves the collection configuration (dim/metric/index kind/params).
  var mi: Int = w.records.len() - 1;
  var found: Bool = false;
  while mi >= 0 && !found {
    if w.records[mi].op == WalOpKind.ManifestUpdate {
      wal_writer_append_payload(&mut out, WalOpKind.ManifestUpdate, w.records[mi].key, w.records[mi].value, w.records[mi].payload);
      found = true;
    }
    mi = mi - 1;
  }
  return out;
}
