// XIOM ORBITDB -- durable WAL segment (reference implementation).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The disk half of the future `xiom.wal` package (packages-lane decision
// 2026-10-08: xiom.wal ships standalone; durable's `src/wal/*` reconciles
// into it). This module keeps `xiom.durable.wal.wal_record`'s vocabulary
// (LSN, full op-kind set, tagged payload) and adds the crash-proven disk
// segment from `tests/probes/probe_wal_file.xi`:
//
//   * append heals a missing trailing newline first (a torn tail must not
//     merge with the next record);
//   * malformed / torn tail lines are skipped on replay (record healing);
//   * LSNs are strictly monotonic; `wal_file_open` resumes from the log.
//
// Durability honesty (M2.1 second half, M1.2 S4 2026-10-13): `wal_file_flush`
// is a REAL fsync (sync_io.sync_fd) since stdlib wave 115; with the engine's
// durability mode 1 + two_phase, commits and checkpoint publishes are
// power-loss honest up to the synced seams. Until the next compiler pin
// re-vendors stdlib/runtime, run with XIOM_RUNTIME_DIR=<stdlib>/runtime
// (scripts/dev-env.* sets it).
//
// Codec v1 (one record per line, UTF-8 text):
//   lsn|op|key|value|timestamp[|p0,p1,...]
// op codes: 1 Insert, 2 Update, 3 Delete, 4 SegmentSeal, 5 ManifestUpdate,
//           6 Checkpoint, 7 SnapshotMarker.

module xiom.db.wal_file

use xiom.io;
use xiom.os.sync_io;
use xiom.db.storage.byte_io;
use xiom.convert;
use xiom.convert.parse;
use xiom.string;
use xiom.string.split;
use xiom.string.trim;

pub enum WALOpKind {
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

pub type WALRecord = {
  lsn: Int;
  op: WALOpKind;
  key: Int;
  value: Int;
  payload: Vec[Int];
  timestamp: Int;
}

pub type WALFile = {
  path: Str;
  next_lsn: Int;
  heal_needed: Bool;
  // Reused record buffer for the hot append paths (m375 write-path fallback:
  // no per-append Vec). Owned by the handle; copies share the buffer.
  scratch: Vec[Int];
}

pub fn wal_op_code(op: WALOpKind) -> Int {
  match op {
    WALOpKind.Insert => { return 1; }
    WALOpKind.Update => { return 2; }
    WALOpKind.Delete => { return 3; }
    WALOpKind.SegmentSeal => { return 4; }
    WALOpKind.ManifestUpdate => { return 5; }
    WALOpKind.Checkpoint => { return 6; }
    WALOpKind.SnapshotMarker => { return 7; }
    WALOpKind.BeginTxn => { return 8; }
    WALOpKind.CommitTxn => { return 9; }
    WALOpKind.AbortTxn => { return 10; }
  }
}

// C-ORBIT-04 (fixed in v0.64.2/m225 for same-catalog twins): variants stay
// qualified here because a same-named twin from ANOTHER package in the
// program (`xiom.wal`'s `WalOpKind` -- the registry extraction of this very
// module) resolves cross-package bare variants to the wrong enum on v0.64.2
// (see the xiom.wal consumer pass in docs/PACKAGE-WISHLIST-ORBITDB.md).
// History: COMPILER-FINDINGS-ORBITDB.md.
pub fn wal_op_from_code(code: Int) -> WALOpKind {
  if code == 2 { return WALOpKind.Update; }
  if code == 3 { return WALOpKind.Delete; }
  if code == 4 { return WALOpKind.SegmentSeal; }
  if code == 5 { return WALOpKind.ManifestUpdate; }
  if code == 6 { return WALOpKind.Checkpoint; }
  if code == 7 { return WALOpKind.SnapshotMarker; }
  if code == 8 { return WALOpKind.BeginTxn; }
  if code == 9 { return WALOpKind.CommitTxn; }
  if code == 10 { return WALOpKind.AbortTxn; }
  return WALOpKind.Insert;
}

// True for record kinds that mutate an index (replay applies these).
pub fn wal_op_is_write(op: WALOpKind) -> Bool {
  match op {
    WALOpKind.Insert => { return true; }
    WALOpKind.Update => { return true; }
    WALOpKind.Delete => { return true; }
    WALOpKind.SegmentSeal => { return false; }
    WALOpKind.ManifestUpdate => { return false; }
    WALOpKind.Checkpoint => { return false; }
    WALOpKind.SnapshotMarker => { return false; }
    WALOpKind.BeginTxn => { return false; }
    WALOpKind.CommitTxn => { return false; }
    WALOpKind.AbortTxn => { return false; }
  }
}

// Torn-tail healing: if the segment does not end with a newline (crash
// mid-record), append one before the next record so the partial tail stays
// its own skipped line instead of merging with the new record. Since M1.2 S4
// this is O(1): file_last_byte + append_line_sync (stdlib wave 117) instead
// of read-the-whole-segment.
pub fn wal_file_heal_tail(path: Str) -> Bool {
  if !io.file_exists(path) { return true; } // missing file: nothing to heal
  match io.file_last_byte(path) {
    None => { return true; } // empty file
    Some(b) => {
      if b == (10 as UInt8) { return true; }
      match io.append_line_sync(path, "") {
        Ok(_) => { return true; }
        Err(_) => { return false; }
      }
    }
  }
}

// Append the decimal ASCII form of v (elements 0..255). Never negates the
// value: XIOM's % keeps the dividend's sign and / truncates toward zero
// (verified 2026-10-16), so i64 min converts correctly.
fn wal_push_int_ascii(out: &mut Vec[Int], v: Int) {
  if v == 0 { out.push(48); return; }
  if v < 0 { out.push(45); } // '-'
  var n = v;
  var buf = Vec[Int].new();
  while n <= -10 || n >= 10 {
    var d = n % 10;
    if d < 0 { d = 0 - d; }
    buf.push(48 + d);
    n = n / 10;
  }
  var d = n % 10;
  if d < 0 { d = 0 - d; }
  buf.push(48 + d);
  var i = buf.len() - 1;
  while i >= 0 {
    out.push(buf[i]);
    i = i - 1;
  }
}

// The exact record line bytes (codec v1) + trailing newline, byte-for-byte
// equal to what `wal_file_append_line` writes via io.append_line (decimal
// ints joined by '|', payload comma-separated). Fast path for the held-fd
// writers (BENCH-1 perf slice): no Str round-trip per record.
fn wal_file_record_bytes(out: &mut Vec[Int], lsn: Int, op: WALOpKind, key: Int,
                         value: Int, payload: &Vec[Int], timestamp: Int) {
  wal_push_int_ascii(out, lsn);
  out.push(124); // '|'
  wal_push_int_ascii(out, wal_op_code(op));
  out.push(124);
  wal_push_int_ascii(out, key);
  out.push(124);
  wal_push_int_ascii(out, value);
  out.push(124);
  wal_push_int_ascii(out, timestamp);
  if payload.len() > 0 {
    out.push(124);
    var i = 0;
    while i < payload.len() {
      if i > 0 { out.push(44); } // ','
      wal_push_int_ascii(out, payload[i]);
      i = i + 1;
    }
  }
  out.push(10); // '\n'
}

// Public prepare: settle a torn tail BEFORE a caller-held append fd is
// opened, so the fd offset cannot precede a truncate (held-fd writers).
pub fn wal_file_prepare(w: &mut WALFile) {
  wal_file_heal_if_needed(w);
}

fn wal_file_heal_if_needed(w: &mut WALFile) {
  if w.heal_needed {
    let _ = wal_file_heal_tail(w.path);
    w.heal_needed = false;
  }
}

fn wal_file_append_line(w: &mut WALFile, op: WALOpKind, key: Int, value: Int,
                        payload: &Vec[Int], timestamp: Int) -> Int {
  // Torn-tail heal only when the handle knows the previous write left one
  // (bench: unconditional heal read the whole segment per append -> 626 ops/s;
  // state-tracked heal removes the O(n) rescan).
  if w.heal_needed {
    let _ = wal_file_heal_tail(w.path);
    w.heal_needed = false;
  }
  var line = convert.int_to_string(w.next_lsn) + "|" + convert.int_to_string(wal_op_code(op))
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

// Append a record and return its LSN (-1 on write failure).
pub fn wal_file_append(w: &mut WALFile, op: WALOpKind, key: Int, value: Int) -> Int {
  var empty = Vec[Int].new();
  return wal_file_append_line(w, op, key, value, &empty, 0);
}

// Append with an explicit payload (tagged extension; payload[0] = subtype).
pub fn wal_file_append_tagged(w: &mut WALFile, op: WALOpKind, key: Int, value: Int,
                              payload: Vec[Int], timestamp: Int) -> Int {
  return wal_file_append_line(w, op, key, value, &payload, timestamp);
}

// Combined durable append (BENCH-1 perf slice 2026-10-16): heal + write the
// record + (when `sync`) fsync through ONE held append handle -- one
// open/close pair per record instead of two (append + later byteio_sync).
// WAL appends were never fault-gated and stay ungated; the sync seam fires
// the kind-1 gate exactly once when `sync` is true (durability 1), so the
// fault probe's arming counts are unchanged.
// Returns the assigned LSN; -1 = write failed (state NOT advanced);
// -2 = written but the sync failed (state advanced; caller latches).
pub fn wal_file_append_sync(w: &mut WALFile, op: WALOpKind, key: Int, value: Int,
                            sync: Bool) -> Int {
  var empty = Vec[Int].new();
  return wal_file_append_sync_line(w, op, key, value, &empty, 0, sync);
}

// Tagged form of `wal_file_append_sync` (payload = subtype + bytes).
pub fn wal_file_append_tagged_sync(w: &mut WALFile, op: WALOpKind, key: Int, value: Int,
                                   payload: Vec[Int], timestamp: Int, sync: Bool) -> Int {
  return wal_file_append_sync_line(w, op, key, value, &payload, timestamp, sync);
}

fn wal_file_append_sync_line(w: &mut WALFile, op: WALOpKind, key: Int, value: Int,
                             payload: &Vec[Int], timestamp: Int, sync: Bool) -> Int {
  wal_file_heal_if_needed(w);
  let lsn = w.next_lsn;
  while w.scratch.len() > 0 { let _ = w.scratch.pop(); }
  wal_file_record_bytes(&mut w.scratch, lsn, op, key, value, payload, timestamp);
  match byteio_open_append(w.path) {
    None => { return -1; }
    Some(fd) => {
      if !byteio_append_fd(fd, &w.scratch) {
        let _ = byteio_close_append(fd);
        return -1;
      }
      w.next_lsn = w.next_lsn + 1;
      if sync {
        let ok = byteio_sync_fd(fd);
        let _ = byteio_close_append(fd);
        if !ok { return -2; }
      } else {
        let _ = byteio_close_append(fd);
      }
      return lsn;
    }
  }
}

// Append through a caller-held append handle (transaction path: ONE open per
// transaction instead of one per record). UNGATED, like every WAL append;
// the fd owner closes it and drives the gated sync (byteio_sync_fd).
// Returns the assigned LSN; -1 = write failed (state NOT advanced).
pub fn wal_file_append_fd(w: &mut WALFile, fd: Int, op: WALOpKind, key: Int, value: Int) -> Int {
  var empty = Vec[Int].new();
  return wal_file_append_fd_line(w, fd, op, key, value, &empty, 0);
}

pub fn wal_file_append_tagged_fd(w: &mut WALFile, fd: Int, op: WALOpKind, key: Int, value: Int,
                                 payload: Vec[Int], timestamp: Int) -> Int {
  return wal_file_append_fd_line(w, fd, op, key, value, &payload, timestamp);
}

fn wal_file_append_fd_line(w: &mut WALFile, fd: Int, op: WALOpKind, key: Int, value: Int,
                           payload: &Vec[Int], timestamp: Int) -> Int {
  wal_file_heal_if_needed(w);
  let lsn = w.next_lsn;
  while w.scratch.len() > 0 { let _ = w.scratch.pop(); }
  wal_file_record_bytes(&mut w.scratch, lsn, op, key, value, payload, timestamp);
  if !byteio_append_fd(fd, &w.scratch) { return -1; }
  w.next_lsn = w.next_lsn + 1;
  return lsn;
}

// Durability seam (M2.1 second half, real since M1.2 S4): fsync the segment
// via a held append handle (sync_io.sync_fd). The engine's commit path calls
// byteio_sync directly (fault-gated); this helper is the library-level form
// for probes/callers that hold a WALFile.
pub fn wal_file_flush(w: &mut WALFile) -> Bool {
  if !io.file_exists(w.path) { return true; }
  match sync_io.open_append(w.path) {
    Err(_) => { return false; }
    Ok(fd) => {
      var ok = false;
      match sync_io.sync_fd(fd) {
        Ok(_) => { ok = true; }
        Err(_) => {}
      }
      let _ = sync_io.close_fd(fd);
      return ok;
    }
  }
}

pub fn wal_file_next_lsn(w: &WALFile) -> Int {
  return w.next_lsn;
}

// Open (or create) a segment, resuming next_lsn from the last valid record.
// Any torn tail from a previous crash is healed here, once.
pub fn wal_file_open(path: Str) -> WALFile {
  var next = 1;
  let records = wal_file_replay(path);
  if records.len() > 0 {
    next = records[records.len() - 1].lsn + 1;
  }
  let _ = wal_file_heal_tail(path);
  return WALFile{ path: path, next_lsn: next, heal_needed: false,
                  scratch: Vec[Int].new() };
}

fn parse_payload(s: Str) -> Vec[Int] {
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
// callers compare counts (see scripts/crash_test.*).
pub fn wal_file_replay(path: Str) -> Vec[WALRecord] {
  var out = Vec[WALRecord].new();
  let lines_r = io.read_file_lines(path);
  match lines_r {
    Err(_) => { return out; }
    Ok(lines) => {
      var i = 0;
      while i < lines.len() {
        let line = trim.str_trim(lines[i]);
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
              if parts.len() >= 6 { payload = parse_payload(parts[5]); }
              out.push(WALRecord{
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

pub fn wal_file_len(path: Str) -> Int {
  return wal_file_replay(path).len();
}

pub fn wal_file_last_lsn(path: Str) -> Int {
  let records = wal_file_replay(path);
  if records.len() == 0 { return 0; }
  return records[records.len() - 1].lsn;
}

// Checkpoint/truncate seam: rewrite the segment keeping every record with
// lsn >= from_lsn. Uses temp + rename so a crash mid-rewrite never destroys
// the old segment (io.rename maps to MoveFileEx REPLACE_EXISTING / rename(2)).
pub fn wal_file_truncate(path: Str, from_lsn: Int) -> Bool {
  let records = wal_file_replay(path);
  var tmp = path + ".tmp";
  let removed = io.remove_file(tmp);
  // best-effort remove (ignore result)
  var body = "";
  var i = 0;
  while i < records.len() {
    let rec = records[i];
    if rec.lsn >= from_lsn {
      body = body + convert.int_to_string(rec.lsn) + "|" + convert.int_to_string(wal_op_code(rec.op))
           + "|" + convert.int_to_string(rec.key) + "|" + convert.int_to_string(rec.value)
           + "|" + convert.int_to_string(rec.timestamp);
      // Payload must survive the rewrite (the Checkpoint record kept by a
      // checkpoint truncation carries [generation, node_count, order]; dropping
      // it would silently mutate a kept record).
      if rec.payload.len() > 0 {
        body = body + "|";
        var j = 0;
        while j < rec.payload.len() {
          if j > 0 { body = body + ","; }
          body = body + convert.int_to_string(rec.payload[j]);
          j = j + 1;
        }
      }
      body = body + "\n";
    }
    i = i + 1;
  }
  let wrote = io.write_file(tmp, body);
  match wrote {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  // Rename durability (P3, M1.2 S4): sync the temp before publishing, then
  // sync the directory that received the rename.
  let _ = byteio_sync(tmp);
  let moved = io.rename(tmp, path);
  match moved {
    Ok(_) => {
      let _ = byteio_sync_dir(path);
      return true;
    }
    Err(_) => { return false; }
  }
}
