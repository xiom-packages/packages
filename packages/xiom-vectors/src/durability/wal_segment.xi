// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.durability.wal_segment

// Append-only DELTA WAL segment (M-D5): one record per line in the
// `xiom.wal` codec v1 framing (`lsn|op|key|value|timestamp[|p0,p1,...]`),
// written through the stdlib wave-115 durable-IO primitives:
//   sync_io.open_append -> sync_io.write_all -> fs_ffi.fsync -> close_fd.
// The whole-file `wal_persist` checkpoint (durability.wal_file) stays as the
// COMPACTION output; this segment carries only the delta since the last
// checkpoint and is reset (rotated) after a successful checkpoint persist.
//
// Crash contract:
//   - append writes one fully rendered byte buffer per commit and fsyncs it
//     before the engine acknowledges (WAL-before-ack);
//   - a torn tail (crash mid-write, no trailing newline) is healed on the
//     next open by appending a single newline, so the partial line stays its
//     own SKIPPED line and never merges with the next record;
//   - replay keeps the longest prefix of complete, strictly consecutive
//     records (first record may start at any LSN >= 1; a gap or malformed
//     byte stops the prefix) -- the same prefix-exact contract as the
//     checkpoint loader.
//
// Framing is byte-equal to `xiom.wal`'s `wal_render_record` (cross-checked
// by probe_wal_segment against the installed package), so a future swap to
// the package's file API is a framing no-op. Format note: our writer emits
// '\n' only; the parser tolerates a '\r' before '\n' (files written through
// Str/line APIs on Windows).

use xiom.io;
use xiom.convert;
use xiom.os.fs_ffi;
use xiom.os.sync_io;
use xiom.vector.durability.wal;
use xiom.vector.durability.wal_file;

fn seg_op_code(op: WalOpKind) -> Int {
  if op == WalOpKind.Insert { return 1; }
  if op == WalOpKind.Update { return 2; }
  if op == WalOpKind.Delete { return 3; }
  if op == WalOpKind.SegmentSeal { return 4; }
  if op == WalOpKind.ManifestUpdate { return 5; }
  if op == WalOpKind.Checkpoint { return 6; }
  return 7;
}

fn seg_op_from_code(c: Int) -> WalOpKind {
  if c == 2 { return WalOpKind.Update; }
  if c == 3 { return WalOpKind.Delete; }
  if c == 4 { return WalOpKind.SegmentSeal; }
  if c == 5 { return WalOpKind.ManifestUpdate; }
  if c == 6 { return WalOpKind.Checkpoint; }
  if c == 7 { return WalOpKind.SnapshotMarker; }
  return WalOpKind.Insert;
}

// Render one record as its codec v1 line (WITH the trailing newline).
// Byte-linear: no Str concatenation in the builder (the M-G O(L^2) lesson).
pub fn segment_render(out: &mut Vec[UInt8], r: &WalRecord) {
  append_bytes(out, convert.int_to_string(r.lsn));
  out.push(124u8); // '|'
  append_bytes(out, convert.int_to_string(seg_op_code(r.op)));
  out.push(124u8);
  append_bytes(out, convert.int_to_string(r.key));
  out.push(124u8);
  append_bytes(out, convert.int_to_string(r.value));
  out.push(124u8);
  append_bytes(out, convert.int_to_string(r.timestamp));
  if r.payload.len() > 0 {
    out.push(124u8);
    var i: Int = 0;
    while i < r.payload.len() {
      if i > 0 { out.push(44u8); } // ','
      append_bytes(out, convert.int_to_string(r.payload[i]));
      i = i + 1;
    }
  }
  out.push(10u8); // '\n'
}

// One record's full line bytes (test/debug convenience).
pub fn segment_line(r: &WalRecord) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  segment_render(&mut out, r);
  return out;
}

// Ensure the segment exists and its tail is not torn. A missing file is
// created empty; a tail without a trailing newline gets one appended (the
// torn line stays skipped on replay and cannot merge with the next write).
pub fn segment_heal(path: Str) -> Bool {
  if !io.file_exists(path) {
    var empty0 = Vec[UInt8].new();
    match io.write_file_bytes(path, &empty0) {
      Ok(_) => { return true; }
      Err(_) => { return false; }
    }
  }
  var size: Int = 0;
  match io.file_size(path) {
    Some(n) => { size = n; }
    None => { return false; }
  }
  if size == 0 { return true; }
  var rb = io.read_file_bytes(path);
  var b = Vec[UInt8].new();
  match rb {
    Ok(x) => { b = x; }
    Err(_) => { return false; }
  }
  if b.len() == 0 { return true; }
  if b[b.len() - 1] == 10u8 { return true; }
  var nl = Vec[UInt8].new();
  nl.push(10u8);
  match io.append_file_bytes(path, &nl) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Rotate: delete and re-create empty (called after a successful checkpoint
// persist -- the checkpoint now carries every record).
pub fn segment_reset(path: Str) -> Bool {
  if io.file_exists(path) {
    match io.remove_file(path) {
      Ok(_) => {}
      Err(_) => { return false; }
    }
  }
  var empty0 = Vec[UInt8].new();
  match io.write_file_bytes(path, &empty0) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

fn read_segment_bytes(path: Str) -> Option[Vec[UInt8]] {
  if !io.file_exists(path) { return None; }
  var sz: Int = 0;
  match io.file_size(path) {
    Some(n) => { sz = n; }
    None => { return None; }
  }
  if sz == 0 { return None; }
  var b = Vec[UInt8].new();
  match io.read_file_bytes(path) {
    Ok(x) => { b = x; }
    Err(_) => { return None; }
  }
  if b.len() == 0 { return None; }
  return Some(b);
}

// One parsed codec v1 line.
pub type SegLine = {
  ok: Bool;
  lsn: Int;
  op: Int;
  key: Int;
  value: Int;
  ts: Int;
  payload: Vec[Int];
}

// Parse one line within [start, end) (newline/\r excluded). Strict within
// the line: five `|`-separated ints, then an optional `|` payload CSV.
fn parse_seg_line(b: &Vec[UInt8], start: Int, end: Int) -> SegLine {
  var empty = Vec[Int].new();
  var pos = start;
  var fields = Vec[Int].new();
  var fi: Int = 0;
  var failed: Bool = false;
  while fi < 5 && !failed {
    if pos >= end { failed = true; } else {
      var r = parse_int_at(b, pos);
      if !r.ok || r.pos > end {
        failed = true;
      } else {
        fields.push(r.value);
        pos = r.pos;
        if fi < 4 {
          if pos < end && b[pos] == 124u8 {
            pos = pos + 1;
          } else {
            failed = true;
          }
        }
        fi = fi + 1;
      }
    }
  }
  var payload = Vec[Int].new();
  if !failed {
    if pos < end {
      if b[pos] == 124u8 {
        pos = pos + 1;
        var word: Int = 0;
        var have: Bool = false;
        var neg: Bool = false;
        while pos < end && !failed {
          if b[pos] == 44u8 {
            if have {
              if neg { payload.push(0 - word); } else { payload.push(word); }
              word = 0;
              have = false;
              neg = false;
            } else {
              failed = true;
            }
          } else if b[pos] == 45u8 {
            if have || neg {
              failed = true;
            } else {
              neg = true;
            }
          } else if b[pos] >= 48u8 && b[pos] <= 57u8 {
            word = word * 10 + ((b[pos] as Int) - 48);
            have = true;
          } else {
            failed = true;
          }
          pos = pos + 1;
        }
        if !failed && have {
          if neg { payload.push(0 - word); } else { payload.push(word); }
        }
      } else {
        failed = true;
      }
    }
  }
  if failed {
    return SegLine{ ok: false, lsn: 0, op: 0, key: 0, value: 0, ts: 0, payload: empty };
  }
  return SegLine{
    ok: true,
    lsn: fields[0],
    op: fields[1],
    key: fields[2],
    value: fields[3],
    ts: fields[4],
    payload: payload,
  };
}

// Parse the whole segment into `w`. Replay is tolerant at the LINE level
// (malformed / torn lines are skipped, matching `xiom.wal`'s replay), but a
// VALID line with a non-continuous LSN stops the parse: a gap is corruption,
// never silently skipped. The first valid record may start at any LSN >= 1.
// Returns the number of records parsed (0 for a missing/empty segment).
pub fn segment_parse_into(path: Str, w: &mut WalWriter) -> Int {
  let maybe = read_segment_bytes(path);
  var b = Vec[UInt8].new();
  match maybe {
    Some(x) => { b = x; }
    None => { return 0; }
  }
  var pos: Int = 0;
  var last: Int = 0;
  var count: Int = 0;
  var stop: Bool = false;
  while pos <= b.len() && !stop {
    if pos == b.len() { stop = true; } else {
      var le = pos;
      while le < b.len() && b[le] != 10u8 { le = le + 1; }
      var lend = le;
      if lend > pos && b[lend - 1] == 13u8 { lend = lend - 1; }
      var ln = parse_seg_line(b, pos, lend);
      if ln.ok {
        var lsn_ok: Bool = false;
        if last == 0 {
          if ln.lsn >= 1 { lsn_ok = true; }
        } elif ln.lsn == last + 1 {
          lsn_ok = true;
        }
        if !lsn_ok || ln.op < 1 || ln.op > 7 {
          stop = true;
        } else {
          w.records.push(WalRecord{
            lsn: ln.lsn,
            op: seg_op_from_code(ln.op),
            key: ln.key,
            value: ln.value,
            payload: ln.payload,
            timestamp: ln.ts,
          });
          w.next_lsn = ln.lsn + 1;
          w.synced_lsn = ln.lsn;
          last = ln.lsn;
          count = count + 1;
        }
      }
      // invalid line: tolerated (skipped), continue with the next line
      if le >= b.len() {
        stop = true;
      } else {
        pos = le + 1;
      }
    }
  }
  return count;
}

// Last valid LSN in the segment (0 when missing/empty/corrupt-head).
pub fn segment_last_lsn(path: Str) -> Int {
  var probe = wal_writer_new();
  let _n = segment_parse_into(path, &mut probe);
  return wal_writer_current_lsn(&probe);
}

// Merge the segment's records into `w` with checkpoint dedupe:
//   - records with lsn <= w's current LSN are already covered (skip);
//   - the next record must continue exactly at w.next_lsn (+1 stepping); a
//     gap stops the merge (prefix exactness).
// Returns the number of appended records.
pub fn segment_merge_into(path: Str, w: &mut WalWriter) -> Int {
  var tmp = wal_writer_new();
  let _n = segment_parse_into(path, &mut tmp);
  var appended: Int = 0;
  var i: Int = 0;
  while i < tmp.records.len() {
    var r = tmp.records[i];
    var cur = wal_writer_current_lsn(w);
    if r.lsn <= cur {
      i = i + 1;
    } elif r.lsn == cur + 1 {
      w.records.push(r);
      w.next_lsn = r.lsn + 1;
      w.synced_lsn = r.lsn;
      appended = appended + 1;
      i = i + 1;
    } else {
      return appended;
    }
  }
  return appended;
}

// Append every record of `w` with lsn > `from_lsn` as ONE byte buffer, then
// fsync before returning: open_append -> write_all -> fsync -> close.
// Returns the number of records written; Err on any IO failure (the caller
// must treat the write as unacknowledged and heal before the next attempt).
pub fn segment_append_sync(path: Str, w: &WalWriter, from_lsn: Int) -> Result[Int, Str] {
  var buf = Vec[UInt8].new();
  var n: Int = 0;
  var i: Int = 0;
  while i < w.records.len() {
    if w.records[i].lsn > from_lsn {
      segment_render(&mut buf, &w.records[i]);
      n = n + 1;
    }
    i = i + 1;
  }
  if n == 0 { return Ok(0); }
  var fr = sync_io.open_append(path);
  var fd: Int = -1;
  match fr {
    Ok(f) => { fd = f; }
    Err(e) => { return Err(e); }
  }
  var wr = sync_io.write_all(fd, &buf);
  match wr {
    Ok(_) => {}
    Err(e) => {
      let _c0 = sync_io.close_fd(fd);
      return Err(e);
    }
  }
  var sr = fs_ffi.fsync(fd);
  match sr {
    Ok(_) => {}
    Err(e) => {
      let _c1 = sync_io.close_fd(fd);
      return Err(e);
    }
  }
  var cr = sync_io.close_fd(fd);
  match cr {
    Ok(_) => { return Ok(n); }
    Err(e) => { return Err(e); }
  }
}
