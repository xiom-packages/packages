// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.durability.wal_file

// File-backed WAL using the stdlib's whole-file APIs (write_file_bytes /
// read_file_bytes / file_exists / rename) plus, since stdlib wave 115/117,
// the fd fsync + dir-fsync primitives (wal_persist_sync). The format is text:
// a header line plus one line per record (lsn op key value timestamp
// payload_len [w1,w2,..]). Persist is a whole-file CHECKPOINT (rewrite); the
// D5 delta segment (wal_segment) carries append+fsync for live acks, and
// `wal_persist_sync` (M-D6) makes the checkpoint swap crash-safe
// (write tmp -> fsync tmp -> rename -> fsync dir). The write is ATOMIC: the
// checkpoint lands in `<path>.tmp` first and is swapped over the target with
// io.rename, so a crash at any point leaves either the previous or the new
// complete file -- never a torn one. Load is torn-tail tolerant: a missing,
// corrupt, or byte-truncated file yields the longest prefix of COMPLETE
// valid records (prefix exactness).
//
// The loader parses BYTES directly (no Str::from_utf8 / str_split): the
// original mislowering (XVC-C-11, C-08 family) is fixed in compiler v0.64.2,
// but the byte parser stays as defense in depth with exact framing control;
// the reader never handles Str content and operates on the raw Vec[UInt8].

use xiom.io;
use xiom.convert;
use xiom.string.slice;
use xiom.os.fs_ffi;
use xiom.os.sync_io;
use xiom.string.slice;
use xiom.vector.durability.wal;

fn op_code(op: WalOpKind) -> Int {
  if op == WalOpKind.Insert { return 1; }
  if op == WalOpKind.Update { return 2; }
  if op == WalOpKind.Delete { return 3; }
  if op == WalOpKind.SegmentSeal { return 4; }
  if op == WalOpKind.ManifestUpdate { return 5; }
  if op == WalOpKind.Checkpoint { return 6; }
  return 7;
}

fn code_op(c: Int) -> WalOpKind {
  if c == 2 { return WalOpKind.Update; }
  if c == 3 { return WalOpKind.Delete; }
  if c == 4 { return WalOpKind.SegmentSeal; }
  if c == 5 { return WalOpKind.ManifestUpdate; }
  if c == 6 { return WalOpKind.Checkpoint; }
  if c == 7 { return WalOpKind.SnapshotMarker; }
  return WalOpKind.Insert;
}

// One parsed integer: value plus the position after it; ok=false when no
// digits were present at `start` (strict: optional '-', then digits).
// Shared with the manifest-file codec (D2): both parse byte-level text.
pub type ParsedInt = {
  value: Int;
  pos: Int;
  ok: Bool;
}

pub fn parse_int_at(b: &Vec[UInt8], start: Int) -> ParsedInt {
  var p: Int = start;
  var neg: Bool = false;
  if p < b.len() && b[p] == 45 {
    neg = true;
    p = p + 1;
  }
  var v: Int = 0;
  var digits: Int = 0;
  while p < b.len() && b[p] >= 48 && b[p] <= 57 {
    v = v * 10 + ((b[p] as Int) - 48);
    p = p + 1;
    digits = digits + 1;
  }
  if digits == 0 {
    return ParsedInt{ value: 0, pos: start, ok: false };
  }
  if neg { v = 0 - v; }
  return ParsedInt{ value: v, pos: p, ok: true };
}

// Append the UTF-8 bytes of `s` to `out`. Building the checkpoint this way is
// LINEAR: the previous `text = text + ...` builder was O(L^2) in allocations
// (each intermediate string survives in the runtime's allocator long enough
// to thrash a large persist; found by the M-G bench at ~150 KB logs).
// Shared with the manifest-file codec (D2).
pub fn append_bytes(out: &mut Vec[UInt8], s: Str) {
  var b = slice.str_bytes(s);
  var i: Int = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
}

// Whole-file checkpoint write, atomically: the text lands in `<path>.tmp`
// and is swapped over the target with io.rename (platform rename replaces an
// existing destination; verified on Windows + WSL by the probe). A crash
// before the rename leaves the previous checkpoint untouched; the temp is
// never part of the readable state. If the rename fails the temp remains and
// is simply overwritten by the next persist. False on any IO error.
// Render the whole checkpoint log as bytes (shared by both persist paths).
fn wal_render_bytes(w: &WalWriter) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  append_bytes(&mut out, "xvector-wal 1\n");
  var i: Int = 0;
  while i < w.records.len() {
    var r = w.records[i];
    var line = convert.int_to_string(r.lsn) + " "
      + convert.int_to_string(op_code(r.op)) + " "
      + convert.int_to_string(r.key) + " "
      + convert.int_to_string(r.value) + " "
      + convert.int_to_string(r.timestamp) + " "
      + convert.int_to_string(r.payload.len());
    if r.payload.len() > 0 {
      line = line + " ";
      var j: Int = 0;
      while j < r.payload.len() {
        if j > 0 { line = line + ","; }
        line = line + convert.int_to_string(r.payload[j]);
        j = j + 1;
      }
    }
    line = line + "\n";
    append_bytes(&mut out, line);
    i = i + 1;
  }
  return out;
}

pub fn wal_persist(w: &WalWriter, path: Str) -> Bool {
  var out = wal_render_bytes(w);
  var tmp = path + ".tmp";
  var wres = io.write_file_bytes(tmp, &out);
  match wres {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  var rres = io.rename(tmp, path);
  match rres {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Parent directory of a path ("." when there is no separator). Handles both
// separators; used for the post-rename directory fsync.
pub fn path_parent(path: Str) -> Str {
  var i = path.len() - 1;
  while i >= 0 {
    let c = path.byte_at(i);
    if c == 47u8 || c == 92u8 { return slice.str_slice(path, 0, i); }
    i = i - 1;
  }
  return ".";
}

// fsync a file through a write-capable fd (no write is performed). True on
// success; false when the file cannot be opened or the fsync fails.
pub fn fsync_file(path: Str) -> Bool {
  var fr = sync_io.open_append(path);
  var fd: Int = -1;
  match fr {
    Ok(f) => { fd = f; }
    Err(_) => { return false; }
  }
  var sr = fs_ffi.fsync(fd);
  let _c = sync_io.close_fd(fd);
  match sr {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Durable checkpoint swap (M-D6): write tmp -> fsync tmp -> rename ->
// fsync parent dir (best-effort: an Err from fsync_dir, e.g. on a
// filesystem that does not support directory fds, is ignored -- the
// content fsync before the rename is the load-bearing step). A crash at
// any point leaves either the previous checkpoint (still durable) or the
// new one (content fsynced BEFORE the rename replaced the old), so the
// D6 swap may reset the delta segment without risking acknowledged
// records.
pub fn wal_persist_sync(w: &WalWriter, path: Str) -> Bool {
  var out = wal_render_bytes(w);
  var tmp = path + ".tmp";
  var wres = io.write_file_bytes(tmp, &out);
  match wres {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  if !fsync_file(tmp) { return false; }
  var rres = io.rename(tmp, path);
  match rres {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  let _d = sync_io.fsync_dir(path_parent(path));
  return true;
}

// Load the longest complete-record prefix (missing / corrupt / truncated
// files degrade gracefully; never fails).
pub fn wal_load(path: Str) -> WalWriter {
  var w = wal_writer_new();
  if !io.file_exists(path) { return w; }
  var fs = io.file_size(path);
  var sz: Int = -1;
  match fs {
    Some(n) => { sz = n; }
    None => { return w; }
  }
  // Files shorter than the shortest VALID wal (13-byte header + the shortest
  // record line "1 5 0 0 0 0\n" = 25 bytes) cannot contain a complete
  // record, so they are empty logs -- and this also skips reads of tiny
  // files: read_file_bytes aborts on files of <= 8 bytes on v0.64.1
  // (spurious ensures violation at io.xi:947; XVC-C-12).
  if sz < 25 { return w; }
  var rb = io.read_file_bytes(path);
  var b = Vec[UInt8].new();
  match rb {
    Ok(x) => { b = x; }
    Err(_) => { return w; }
  }
  var hdr = slice.str_bytes("xvector-wal 1");
  if b.len() < hdr.len() + 1 { return w; }
  var hi: Int = 0;
  while hi < hdr.len() {
    if b[hi] != hdr[hi] { return w; }
    hi = hi + 1;
  }
  var pos: Int = hdr.len();
  if pos < b.len() && b[pos] == 13 { pos = pos + 1; }
  if pos >= b.len() || b[pos] != 10 { return w; }
  pos = pos + 1;
  var lsn: Int = 0;
  var stop: Bool = false;
  while pos < b.len() && !stop {
    var fields = Vec[Int].new();
    var fi: Int = 0;
    var bad: Bool = false;
    while fi < 6 && !bad {
      var r = parse_int_at(b, pos);
      if !r.ok {
        bad = true;
      } else {
        fields.push(r.value);
        pos = r.pos;
        if fi < 5 {
          if pos < b.len() && b[pos] == 32 {
            pos = pos + 1;
          } else {
            bad = true;
          }
        }
        fi = fi + 1;
      }
    }
    var payload = Vec[Int].new();
    if !bad {
      var plen: Int = fields[5];
      if plen < 0 {
        bad = true;
      } elif plen == 0 {
        if pos < b.len() && b[pos] == 13 { pos = pos + 1; }
        if pos < b.len() && b[pos] == 10 {
          pos = pos + 1;
        } else {
          bad = true;
        }
      } else {
        if pos < b.len() && b[pos] == 32 {
          pos = pos + 1;
        } else {
          bad = true;
        }
        var wc: Int = 0;
        while wc < plen && !bad {
          var r2 = parse_int_at(b, pos);
          if !r2.ok {
            bad = true;
          } else {
            payload.push(r2.value);
            pos = r2.pos;
            if wc < plen - 1 {
              if pos < b.len() && b[pos] == 44 {
                pos = pos + 1;
              } else {
                bad = true;
              }
            }
            wc = wc + 1;
          }
        }
        if !bad {
          if pos < b.len() && b[pos] == 13 { pos = pos + 1; }
          if pos < b.len() && b[pos] == 10 {
            pos = pos + 1;
          } else {
            bad = true;
          }
        }
      }
    }
    if bad {
      stop = true;
    } else {
      // LSNs must be consecutive, but the FIRST record may start at any
      // LSN >= 1: compacted/checkpointed logs resume LSNs, and requiring
      // 1 made a re-persisted recovered log reload EMPTY (silent data
      // loss; XV-ORBITDB-01 / REL-20261010-1550-orbitdb-11). Strict +1
      // stepping still detects corruption inside the prefix.
      var lsn_ok: Bool = false;
      if lsn == 0 {
        if fields[0] >= 1 { lsn_ok = true; }
      } elif fields[0] == lsn + 1 {
        lsn_ok = true;
      }
      if !lsn_ok || fields[1] < 1 || fields[1] > 7 {
        stop = true;
      } else {
        var rec = WalRecord{
          lsn: fields[0],
          op: code_op(fields[1]),
          key: fields[2],
          value: fields[3],
          payload: payload,
          timestamp: fields[4],
        };
        w.records.push(rec);
        lsn = fields[0];
        w.next_lsn = lsn + 1;
        w.synced_lsn = lsn;
      }
    }
  }
  return w;
}
