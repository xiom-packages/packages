// XIOM -- xiom.wal: standalone write-ahead log
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// One format = xiom.durable's record shape + ORBITDB's disk contract
// (packages-lane decision 2026-10-08/09; see SPEC.md sections 2 and 4).
// Extraction 2026-10-09 from:
//   * packages/xiom-durable/src/wal/{wal_record,wal_writer,wal_reader,
//     recovery,checkpoint,lsn}.xi -- vocabulary, names kept as-is;
//   * E:\xiom-projects\xiom-orbitdb\src\wal_file.xi -- the landed,
//     crash-proven disk layer (ORBITDB commit 12405f5).
//
// Codec v1 (one record per line, UTF-8 text):
//   lsn|op|key|value|timestamp[|p0,p1,...]
// op codes: 1 Insert, 2 Update, 3 Delete, 4 SegmentSeal, 5 ManifestUpdate,
//           6 Checkpoint, 7 SnapshotMarker, 8 BeginTxn, 9 CommitTxn,
//           10 AbortTxn. Codes 1-10 round-trip so existing ORBITDB segments
// replay unchanged.
//
// Crash contract: append heals a missing trailing newline first (a torn tail
// must not merge with the next record); malformed / torn tail lines are
// skipped on replay; open resumes next_lsn from the last valid record.
//
// Durability honesty: wal_flush is a documented no-op success until the
// stdlib fsync row lands (STDLIB-WISHLIST); "durable" today means OS
// write-back + torn-tail healing, not power-loss durability.
//
// Payload convention: payload[0] = subtype tag (xvector / xiom.db), the rest
// per-subtype; wal_append_tagged carries payload + timestamp.
//
// In-memory vocabulary (WalLsn, Checkpoint, WalWriter, wal_read_all,
// wal_read_from, recovery_scan) is exported unchanged from durable; wiring
// it to disk is Phase 2 and deliberately NOT done here (SPEC.md section 4).

module xiom.wal

use xiom.io;
use xiom.convert;
use xiom.convert.parse;
use xiom.string;
use xiom.string.split;
use xiom.string.trim;

// --------------------------------------------------
//  Vocabulary (from xiom.durable.wal.*, names unchanged)
// --------------------------------------------------

// The canonical serialized form of a durable event. Both xiom-db and
// xiom-vector extend the operation set through tagged payloads rather than
// forking the record layout, so recovery only ever parses one shape.
// WalOpKind is the UNION: durable's 7 variants (codes 1-7) plus ORBITDB's
// txn kinds BeginTxn=8, CommitTxn=9, AbortTxn=10.
pub enum WalOpKind {
  Insert,
  Update,
  Delete,
  SegmentSeal,
  ManifestUpdate,
  Checkpoint,
  SnapshotMarker,
  BeginTxn,
  CommitTxn,
  AbortTxn,
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

pub fn wal_op_code(op: WalOpKind) -> Int {
  match op {
    WalOpKind.Insert => { return 1; }
    WalOpKind.Update => { return 2; }
    WalOpKind.Delete => { return 3; }
    WalOpKind.SegmentSeal => { return 4; }
    WalOpKind.ManifestUpdate => { return 5; }
    WalOpKind.Checkpoint => { return 6; }
    WalOpKind.SnapshotMarker => { return 7; }
    WalOpKind.BeginTxn => { return 8; }
    WalOpKind.CommitTxn => { return 9; }
    WalOpKind.AbortTxn => { return 10; }
  }
}

// Module-qualified variant returns (C-ORBIT-04): unqualified `return Update;`
// lowered against a same-named variant of a foreign enum in the ORBITDB
// multi-module build. Keep the qualification.
pub fn wal_op_from_code(code: Int) -> WalOpKind {
  if code == 2 { return WalOpKind.Update; }
  if code == 3 { return WalOpKind.Delete; }
  if code == 4 { return WalOpKind.SegmentSeal; }
  if code == 5 { return WalOpKind.ManifestUpdate; }
  if code == 6 { return WalOpKind.Checkpoint; }
  if code == 7 { return WalOpKind.SnapshotMarker; }
  if code == 8 { return WalOpKind.BeginTxn; }
  if code == 9 { return WalOpKind.CommitTxn; }
  if code == 10 { return WalOpKind.AbortTxn; }
  return WalOpKind.Insert;
}

// True for record kinds that mutate an index (replay applies these).
pub fn wal_op_is_write(op: WalOpKind) -> Bool {
  match op {
    WalOpKind.Insert => { return true; }
    WalOpKind.Update => { return true; }
    WalOpKind.Delete => { return true; }
    WalOpKind.SegmentSeal => { return false; }
    WalOpKind.ManifestUpdate => { return false; }
    WalOpKind.Checkpoint => { return false; }
    WalOpKind.SnapshotMarker => { return false; }
    WalOpKind.BeginTxn => { return false; }
    WalOpKind.CommitTxn => { return false; }
    WalOpKind.AbortTxn => { return false; }
  }
}

// WAL-local log sequence number. LSNs are strictly monotonic and never
// reused.
pub type WalLsn = { value: Int; } derive[Clone]

pub fn wal_lsn(v: Int) -> WalLsn {
  return WalLsn{ value: v };
}

pub fn wal_lsn_value(l: &WalLsn) -> Int {
  return l.value;
}

pub fn wal_lsn_next(l: &WalLsn) -> WalLsn {
  return WalLsn{ value: l.value + 1 };
}

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

// Sequential and point-in-time WAL readers used by recovery, repair tooling,
// and snapshot validation. In this phase they read straight from the writer's
// in-memory buffer; the disk reader is wal_replay below.
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

// Crash-recovery orchestration. `recovery_scan` replays the tail of the log
// after the last checkpoint and reports how many records would be reapplied
// plus the highest LSN observed.
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

// --------------------------------------------------
//  Disk layer (from ORBITDB src/wal_file.xi, names per SPEC section 1)
// --------------------------------------------------

pub type WalFile = {
  path: Str;
  next_lsn: Int;
  heal_needed: Bool;
}

// Torn-tail healing: if the segment does not end with a newline (crash
// mid-record), append one before the next record so the partial tail stays
// its own skipped line instead of merging with the new record.
fn wal_heal_tail(path: Str) -> Bool {
  let r = io.read_file(path);
  match r {
    Ok(content) => {
      if content == "" { return true; }
      if str_ends_with(content, "\n") { return true; }
      let wrote = io.append_line(path, "");
      match wrote {
        Ok(_) => { return true; }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return true; } // missing file: nothing to heal
  }
}

// Render one codec v1 line; shared by append and truncate so the two write
// paths cannot drift.
fn wal_render_record(lsn: Int, op: WalOpKind, key: Int, value: Int,
                     payload: &Vec[Int], timestamp: Int) -> Str {
  var line = convert.int_to_string(lsn) + "|" + convert.int_to_string(wal_op_code(op))
           + "|" + convert.int_to_string(key) + "|" + convert.int_to_string(value)
           + "|" + convert.int_to_string(timestamp);
  if payload.len() > 0 {
    line = line + "|";
    var i = 0;
    while i < payload.len() {
      if i > 0 { line = line + ","; }
      line = line + convert.int_to_string(payload[i]);
      i = i + 1;
    }
  }
  return line;
}

fn wal_append_line(w: &mut WalFile, op: WalOpKind, key: Int, value: Int,
                   payload: &Vec[Int], timestamp: Int) -> Int {
  // Torn-tail heal only when the handle knows the previous write left one
  // (bench: unconditional heal read the whole segment per append -> 626
  // ops/s; state-tracked heal removes the O(n) rescan).
  if w.heal_needed {
    let _ = wal_heal_tail(w.path);
    w.heal_needed = false;
  }
  let line = wal_render_record(w.next_lsn, op, key, value, payload, timestamp);
  let wrote = io.append_line(w.path, line);
  match wrote {
    Ok(_) => {
      let assigned = w.next_lsn;
      w.next_lsn = w.next_lsn + 1;
      return assigned;
    }
    Err(_) => { return -1; }
  }
}

// Open (or create) a segment, resuming next_lsn from the last valid record.
// Any torn tail from a previous crash is healed here, once.
pub fn wal_open(path: Str) -> WalFile {
  var next = 1;
  let records = wal_replay(path);
  if records.len() > 0 {
    next = records[records.len() - 1].lsn + 1;
  }
  let _ = wal_heal_tail(path);
  return WalFile{ path: path, next_lsn: next, heal_needed: false };
}

// Append a record and return its LSN (-1 on write failure).
pub fn wal_append(w: &mut WalFile, op: WalOpKind, key: Int, value: Int) -> Int {
  var empty = Vec[Int].new();
  return wal_append_line(w, op, key, value, &empty, 0);
}

// Append with an explicit payload (tagged extension; payload[0] = subtype).
pub fn wal_append_tagged(w: &mut WalFile, op: WalOpKind, key: Int, value: Int,
                         payload: Vec[Int], timestamp: Int) -> Int {
  return wal_append_line(w, op, key, value, &payload, timestamp);
}

// Durability seam. No-op success until the runtime exposes fsync (stdlib
// durable-write row); keep the call site so the swap is one line when it
// lands.
pub fn wal_flush(w: &mut WalFile) -> Bool {
  return true;
}

fn wal_parse_payload(s: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let parts = split.str_split(s, ",");
  var i = 0;
  while i < parts.len() {
    match parse.parse_int(trim.str_trim(parts[i])) {
      Ok(v) => { out.push(v); }
      Err(_) => {}
    }
    i = i + 1;
  }
  return out;
}

// Replay every well-formed record in file order. Torn/malformed lines
// (including a partial tail) are skipped; no diagnostics from this layer --
// callers compare counts (see tests/crash_test.ps1).
pub fn wal_replay(path: Str) -> Vec[WalRecord] {
  var out = Vec[WalRecord].new();
  let raw = io.read_file(path);
  match raw {
    Err(_) => { return out; }
    Ok(content) => {
      // Empty file: nothing to parse. io.read_file_lines is deliberately not
      // used: its `result is Ok => result.len() >= 1` clause mis-fires on the
      // pinned v0.64.1 runtime when a parsed part is empty (the same
      // false-contract class as the documented fs_read trap), so replay
      // splits lines itself with split.str_split over io.read_file, whose
      // `result.len() >= 0` clause always holds.
      if content == "" { return out; }
      let all: Vec[Str] = split.str_split(content, "\n");
      var i = 0;
      while i < all.len() {
        let line = trim.str_trim(all[i]);
        if line != "" {
          let parts = split.str_split(line, "|");
          if parts.len() >= 5 {
            var lsn = 0;
            var op_code = 0;
            var key = 0;
            var value = 0;
            var ts = 0;
            var ok = true;
            match parse.parse_int(parts[0]) {
              Ok(v) => { lsn = v; }
              Err(_) => { ok = false; }
            }
            match parse.parse_int(parts[1]) {
              Ok(v) => { op_code = v; }
              Err(_) => { ok = false; }
            }
            match parse.parse_int(parts[2]) {
              Ok(v) => { key = v; }
              Err(_) => { ok = false; }
            }
            match parse.parse_int(parts[3]) {
              Ok(v) => { value = v; }
              Err(_) => { ok = false; }
            }
            match parse.parse_int(parts[4]) {
              Ok(v) => { ts = v; }
              Err(_) => { ok = false; }
            }
            if ok {
              var payload = Vec[Int].new();
              if parts.len() >= 6 { payload = wal_parse_payload(parts[5]); }
              out.push(WalRecord{
                lsn: lsn, op: wal_op_from_code(op_code), key: key, value: value,
                payload: payload, timestamp: ts,
              });
            }
          }
        }
        i = i + 1;
      }
      return out;
    }
  }
}

pub fn wal_len(path: Str) -> Int {
  return wal_replay(path).len();
}

pub fn wal_last_lsn(path: Str) -> Int {
  let records = wal_replay(path);
  if records.len() == 0 { return 0; }
  return records[records.len() - 1].lsn;
}

// Checkpoint/truncate seam: rewrite the segment keeping every record with
// lsn >= from_lsn. Uses temp + rename so a crash mid-rewrite never destroys
// the old segment (io.rename maps to MoveFileEx REPLACE_EXISTING).
pub fn wal_truncate(path: Str, from_lsn: Int) -> Bool {
  let records = wal_replay(path);
  let tmp = path + ".tmp";
  let _ = io.remove_file(tmp); // best-effort; stale tmp is ignored on retry
  var body = "";
  var i = 0;
  while i < records.len() {
    let rec = records[i];
    if rec.lsn >= from_lsn {
      // Payload must survive the rewrite (the Checkpoint record kept by a
      // checkpoint truncation carries [generation, node_count, order];
      // dropping it would silently mutate a kept record).
      body = body + wal_render_record(rec.lsn, rec.op, rec.key, rec.value,
                                      &rec.payload, rec.timestamp) + "\n";
    }
    i = i + 1;
  }
  let wrote = io.write_file(tmp, body);
  match wrote {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  let moved = io.rename(tmp, path);
  match moved {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// No-op close seam for the path-handle model (every call re-opens the file
// internally, so there is no descriptor to release yet).
pub fn wal_close(w: &mut WalFile) -> Bool {
  return true;
}
