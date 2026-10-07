// XIOM -- xiom.kv: embedded log-structured key-value store
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: a small embedded key-value store over append-only segment files.
// Values are opaque bytes (Str and Vec[UInt8] APIs); deletes are tombstones;
// reopen replays segments with last-write-wins. There is no fsync/truncate in
// this toolchain, so durability is CRASH-CONSISTENT only (a torn final record
// is repaired away on the next open) and the single-writer rule is an
// unenforced contract. See SPEC.md for the full on-disk format.
//
// On-disk layout (little-endian), see SPEC.md section "On-disk format":
//   * segment file `<prefix>seg-<10-digit-id>.kv`, temp `<prefix>seg-<id>.tmp`,
//     optional `<prefix>snapshot.kv`.
//   * 28-byte segment header: magic u32 0x4B565831, version u16 = 1,
//     flags u16 (bit0 snapshot, bit1 compacted), segment_id u64,
//     created_unix u64, header_crc u32 = crc32c(first 24 bytes).
//   * record: crc u32, flags u32 (bit0 tombstone), key_len u32, value_len u32,
//     key, value; crc = crc32c(flags||key_len||value_len||key||value).
//
// Reopen: the segment set is DISCOVERED BY PROBING `<prefix>seg-<id>.kv` for
// ids 1.. up to a run of 32 consecutive misses (io.list_dir returns corrupted
// entry names on the pinned v0.64.0 Windows runtime, so directory listing is
// unusable; see SPEC.md "toolchain deviations"). Ids ascending: the newest
// segment is the tail; a bad header there is abandoned (renamed to .bad) and a
// fresh id+1 is created; a torn/corrupt record tail there is repaired by
// rewriting the file to its last valid record boundary and a fresh id+1 is
// created so later bytes cannot fuse with the torn record. The same damage in
// an OLDER segment is `kv: corrupt segment header` / `kv: corrupt record`.
//
// Compaction rewrites all live entries into `<id+1>.tmp` (compacted header
// flag), atomically renames it to `<id+1>.kv`, then removes older segments and
// the stale snapshot. Snapshot (optional in 0.1.0, shipped): a snapshot-flagged
// header stores base_seg in the header segment_id field and base_off in the
// created_unix field; reopen loads a valid snapshot first and replays records
// after base_off in the base segment plus all newer segments.
//
// v0.64.0 notes that shaped this module:
//   * free functions only; no lambdas; Vec[KvEntry] (Vec[StructType]) is used,
//     NEVER Vec[(Str, Str)] (m192 live crash).
//   * every byte read out of a Vec[UInt8] that enters Int arithmetic is
//     widened with `(data[i] as Int) & 0xFF`; all Str comparisons go through
//     str_compare (no `==` on Str).
//   * locals are initialized at their declaration.
//   * whole-file reads use fs_size + fs_read_range; fs_read/read_file_bytes
//     trip a false `ensures` violation (io.xi:943) in mixed-module programs on
//     this runtime (see SPEC.md).

module xiom.kv

use xiom.io;
use xiom.io.fs;
use xiom.hash.crc;
use xiom.serialize.endian;
use xiom.collect.stringmap;
use xiom.string;
use xiom.convert.int;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

// Segment header magic, little-endian bytes "1XVK" (u32 0x4B565831).
pub const KV_MAGIC: Int = 1263949873;

// Segment header version.
pub const KV_VERSION: Int = 1;

// Segment header size in bytes.
pub const KV_HEADER_SIZE: Int = 28;

// Record fixed part in bytes (crc, flags, key_len, value_len).
pub const KV_RECORD_FIXED: Int = 16;

// Maximum key length in bytes (minimum is 1).
pub const KV_KEY_MAX: Int = 4096;

// Maximum value length in bytes (64 MiB).
pub const KV_VALUE_MAX: Int = 67108864;

// Header flag bit0: this file is a snapshot.
pub const KV_FLAG_SNAPSHOT: Int = 1;

// Header flag bit1: this segment is a compaction output.
pub const KV_FLAG_COMPACTED: Int = 2;

// Record flag bit0: tombstone (value bytes are absent).
pub const KV_RECORD_TOMBSTONE: Int = 1;

// The module version.
pub const KV_MODULE_VERSION: Str = "0.1.0";

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// One key slot in the in-memory index.
///
/// `seg` is the segment id holding the newest record for the key, `off` the
/// record's byte offset in that file, `vlen` the value length and `tomb`
/// whether the newest record is a tombstone. Entries loaded from a snapshot
/// file carry the internal marker seg == -1 (treat `seg` as opaque).
pub type KvEntry = {
  key: Str;
  seg: Int;
  off: Int;
  vlen: Int;
  tomb: Bool;
}

/// An open store handle (single-writer).
///
/// All fields are implementation details; use the kv_* functions. `entries`
/// holds one slot per key ever seen (collapsed and renumbered by compaction),
/// `live_map` maps key -> entry index, `order` lists entry indices in
/// first-write order, `count` is the number of live (non-tombstone) keys,
/// `seg_id`/`seg_len` are the active segment and its append offset, and
/// `seg_max` is the rotation threshold.
pub type KvStore = {
  dir: Str;
  prefix: Str;
  entries: Vec[KvEntry];
  live_map: StringMap;
  order: Vec[Int];
  count: Int;
  seg_id: Int;
  seg_len: Int;
  seg_max: Int;
}

// Internal marker: entry value lives in the snapshot file.
const _KV_SNAP_SEG: Int = -1;

// Discovery stops after this many consecutive missing segment ids.
const _KV_GAP_LIMIT: Int = 32;

// Hard cap on segment-id probing.
const _KV_SCAN_CAP: Int = 1000000;

// --------------------------------------------------
//  Internal result types
// --------------------------------------------------

type _SnapInfo = {
  valid: Bool;
  seg: Int;
  off: Int;
}

type _ScanResult = {
  damaged: Bool;
  valid_end: Int;
  damage_off: Int;
  size: Int;
}

// --------------------------------------------------
//  Naming helpers
// --------------------------------------------------

// Decimal digits of a non-negative Int (no sign, no padding).
fn _digits(n: Int) -> Str {
  var v = n;
  if v <= 0 { return "0"; }
  var tmp = Vec[UInt8].new();
  while v > 0 {
    let d = v % 10;
    tmp.push((48 + d) as UInt8);
    v = v / 10;
  }
  var out = Vec[UInt8].new();
  var i = tmp.len() - 1;
  while i >= 0 {
    out.push(tmp[i]);
    i = i - 1;
  }
  return Str::from_utf8(out);
}

// Zero-pads a non-negative Int to 10 decimal digits.
fn _pad10(n: Int) -> Str {
  let s = _digits(n);
  if s.len() >= 10 { return s; }
  var pad = "";
  var k = 10 - s.len();
  var i = 0;
  while i < k {
    pad = pad + "0";
    i = i + 1;
  }
  return pad + s;
}

fn _seg_name(prefix: Str, id: Int) -> Str {
  return prefix + "seg-" + _pad10(id) + ".kv";
}

fn _seg_tmp_name(prefix: Str, id: Int) -> Str {
  return prefix + "seg-" + _pad10(id) + ".tmp";
}

fn _snap_name(prefix: Str) -> Str {
  return prefix + "snapshot.kv";
}

fn _snap_tmp_name(prefix: Str) -> Str {
  return prefix + "snapshot.tmp";
}

fn _at(dir: Str, name: Str) -> Str {
  return io.join_paths(dir, name);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

fn _crc_range(data: &Vec[UInt8], start: Int, size: Int) -> Int {
  var body = Vec[UInt8].new();
  var i = 0;
  while i < size {
    body.push(data[start + i]);
    i = i + 1;
  }
  return crc.crc32c(&body) as Int;
}

fn _push_str_bytes(dst: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    dst.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn _append_vec(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

// Reads the whole file with fs_size + fs_read_range (fs_read is avoided, see
// the module header) and requires the exact length.
fn _read_all(path: Str) -> Result[Vec[UInt8], Str] {
  let sz = fs.fs_size(path);
  if !sz.is_ok { return Err("kv: cannot stat: " + path); }
  let r = fs.fs_read_range(path, 0, sz.value);
  if !r.is_ok { return Err("kv: cannot read: " + path); }
  let b = r.value;
  if b.len() != sz.value { return Err("kv: short read"); }
  return Ok(b);
}

// --------------------------------------------------
//  Header + record encoding
// --------------------------------------------------

// 28-byte header; aux is created_unix for segments and base_off for snapshots.
fn _header_bytes(flags: Int, seg_id: Int, aux: Int) -> Vec[UInt8] {
  var h = Vec[UInt8].new();
  endian.write_u32_le(h, KV_MAGIC as UInt32);
  endian.write_u16_le(h, KV_VERSION as UInt16);
  endian.write_u16_le(h, flags as UInt16);
  endian.write_u64_le(h, seg_id as UInt64);
  endian.write_u64_le(h, aux as UInt64);
  let calc = _crc_range(&h, 0, 24);
  endian.write_u32_le(h, calc as UInt32);
  return h;
}

// Flags of a valid segment header claiming `want_id`, or -1 when invalid.
fn _header_flags(data: &Vec[UInt8], want_id: Int) -> Int {
  if data.len() < KV_HEADER_SIZE { return -1; }
  if (endian.read_u32_le(data, 0) as Int) != KV_MAGIC { return -1; }
  if (endian.read_u16_le(data, 4) as Int) != KV_VERSION { return -1; }
  let flags = endian.read_u16_le(data, 6) as Int;
  if (endian.read_u64_le(data, 8) as Int) != want_id { return -1; }
  let stored = endian.read_u32_le(data, 24) as Int;
  if _crc_range(data, 0, 24) != stored { return -1; }
  return flags;
}

// Encodes one record: crc | flags | key_len | value_len | key | value.
fn _record_bytes(key: Str, value: &Vec[UInt8], tomb: Bool) -> Vec[UInt8] {
  var rflags = 0;
  if tomb { rflags = KV_RECORD_TOMBSTONE; }
  var body = Vec[UInt8].new();
  endian.write_u32_le(body, rflags as UInt32);
  endian.write_u32_le(body, key.len() as UInt32);
  endian.write_u32_le(body, value.len() as UInt32);
  _push_str_bytes(&mut body, key);
  _append_vec(&mut body, value);
  var out = Vec[UInt8].new();
  endian.write_u32_le(out, crc.crc32c(&body) as UInt32);
  _append_vec(&mut out, &body);
  return out;
}

fn _read_key(data: &Vec[UInt8], pos: Int, klen: Int) -> Str {
  var kb = Vec[UInt8].new();
  var i = 0;
  while i < klen {
    kb.push(data[pos + KV_RECORD_FIXED + i]);
    i = i + 1;
  }
  return Str::from_utf8(kb);
}

// --------------------------------------------------
//  Index maintenance
// --------------------------------------------------

// Last-write-wins apply of one record into the in-memory index.
fn _apply(s: &mut KvStore, key: Str, seg: Int, off: Int, vlen: Int, tomb: Bool) {
  let found = string_map_get(&s.live_map, key);
  match found {
    Some(idx) => {
      let was_tomb = s.entries[idx].tomb;
      s.entries[idx].seg = seg;
      s.entries[idx].off = off;
      s.entries[idx].vlen = vlen;
      s.entries[idx].tomb = tomb;
      if was_tomb && !tomb { s.count = s.count + 1; }
      if !was_tomb && tomb { s.count = s.count - 1; }
      return;
    },
    None => {},
  }
  let stored = key.clone();
  s.entries.push(KvEntry{ key: stored; seg: seg; off: off; vlen: vlen; tomb: tomb; });
  string_map_put(&mut s.live_map, key, s.entries.len() - 1);
  s.order.push(s.entries.len() - 1);
  if !tomb { s.count = s.count + 1; }
}

fn _entry_index(s: &KvStore, key: Str) -> Int {
  let found = string_map_get(&s.live_map, key);
  match found {
    Some(idx) => { return idx; },
    None => {},
  }
  return -1;
}

fn _entry_path(s: &KvStore, seg: Int) -> Str {
  if seg == _KV_SNAP_SEG { return _at(s.dir, _snap_name(s.prefix)); }
  return _at(s.dir, _seg_name(s.prefix, seg));
}

// Reads `vlen` value bytes at record `off` with an exact length check.
fn _read_value(s: &KvStore, seg: Int, off: Int, klen: Int, vlen: Int) -> Result[Vec[UInt8], Str] {
  let r = fs.fs_read_range(_entry_path(s, seg), off + KV_RECORD_FIXED + klen, vlen);
  if !r.is_ok { return Err("kv: short read"); }
  let b = r.value;
  if b.len() != vlen { return Err("kv: short read"); }
  return Ok(b);
}

fn _key_err(key: Str) -> Str {
  if key.len() == 0 { return "kv: empty key"; }
  if key.len() > KV_KEY_MAX { return "kv: key too large"; }
  return "";
}

// --------------------------------------------------
//  Segment discovery + load
// --------------------------------------------------

// Existing segment ids discovered by probing <prefix>seg-<id>.kv for
// id = 1.., stopping after _KV_GAP_LIMIT consecutive misses. io.list_dir is
// unusable on the pinned runtime (corrupted names), see the module header.
fn _discover_ids(s: &KvStore) -> Vec[Int] {
  var ids = Vec[Int].new();
  var i = 1;
  var missing = 0;
  while i <= _KV_SCAN_CAP && missing < _KV_GAP_LIMIT {
    if io.file_exists(_at(s.dir, _seg_name(s.prefix, i))) {
      ids.push(i);
      missing = 0;
    } else {
      missing = missing + 1;
    }
    i = i + 1;
  }
  return ids;
}

// Framing validation of a snapshot body (records only, no apply).
fn _snapshot_ok(data: &Vec[UInt8]) -> Bool {
  if data.len() < KV_HEADER_SIZE { return false; }
  if (endian.read_u32_le(data, 0) as Int) != KV_MAGIC { return false; }
  if (endian.read_u16_le(data, 4) as Int) != KV_VERSION { return false; }
  let flags = endian.read_u16_le(data, 6) as Int;
  if (flags % 2) != 1 { return false; }
  if _crc_range(data, 0, 24) != (endian.read_u32_le(data, 24) as Int) { return false; }
  var pos = KV_HEADER_SIZE;
  while pos < data.len() {
    if data.len() - pos < KV_RECORD_FIXED { return false; }
    let crc_stored = endian.read_u32_le(data, pos) as Int;
    let kl = endian.read_u32_le(data, pos + 8) as Int;
    let vl = endian.read_u32_le(data, pos + 12) as Int;
    if kl < 1 { return false; }
    if kl > KV_KEY_MAX { return false; }
    if vl > KV_VALUE_MAX { return false; }
    let total = KV_RECORD_FIXED + kl + vl;
    if total > data.len() - pos { return false; }
    if _crc_range(data, pos + 4, total - 4) != crc_stored { return false; }
    pos = pos + total;
  }
  return true;
}

// Loads <prefix>snapshot.kv when present and fully valid; applies its records
// with seg = -1 and returns base_seg/base_off. An invalid snapshot is ignored
// entirely (segments are authoritative and are never removed by snapshot).
fn _load_snapshot(s: &mut KvStore) -> _SnapInfo {
  var info = _SnapInfo{ valid: false; seg: 0; off: 0; };
  let path = _at(s.dir, _snap_name(s.prefix));
  if !io.file_exists(path) { return info; }
  let rr = _read_all(path);
  if !rr.is_ok { return info; }
  let data = rr.value;
  if !_snapshot_ok(&data) { return info; }
  let base_seg = endian.read_u64_le(&data, 8) as Int;
  let base_off = endian.read_u64_le(&data, 16) as Int;
  if base_seg < 1 { return info; }
  if base_off < 0 { return info; }
  var pos = KV_HEADER_SIZE;
  while pos < data.len() {
    let flags = endian.read_u32_le(&data, pos + 4) as Int;
    let kl = endian.read_u32_le(&data, pos + 8) as Int;
    let vl = endian.read_u32_le(&data, pos + 12) as Int;
    let key = _read_key(&data, pos, kl);
    let tomb = (flags % 2) == 1;
    _apply(s, key, _KV_SNAP_SEG, pos, vl, tomb);
    pos = pos + KV_RECORD_FIXED + kl + vl;
  }
  info.valid = true;
  info.seg = base_seg;
  info.off = base_off;
  return info;
}

// Parses records from `from` (>= 28) and applies them. Stops at the first
// structurally invalid or CRC-failing record and reports it as damage.
fn _scan_records(s: &mut KvStore, data: &Vec[UInt8], seg: Int, from: Int) -> _ScanResult {
  var pos = from;
  if pos < KV_HEADER_SIZE { pos = KV_HEADER_SIZE; }
  if pos > data.len() { pos = data.len(); }
  var valid_end = pos;
  var damaged = false;
  var damage_off = pos;
  let dlen = data.len();
  while pos < dlen {
    let remaining = dlen - pos;
    if remaining < KV_RECORD_FIXED { damaged = true; damage_off = pos; break; }
    let crc_stored = endian.read_u32_le(data, pos) as Int;
    let rflags = endian.read_u32_le(data, pos + 4) as Int;
    let kl = endian.read_u32_le(data, pos + 8) as Int;
    let vl = endian.read_u32_le(data, pos + 12) as Int;
    if kl < 1 || kl > KV_KEY_MAX || vl > KV_VALUE_MAX {
      damaged = true;
      damage_off = pos;
      break;
    }
    let total = KV_RECORD_FIXED + kl + vl;
    if total > remaining { damaged = true; damage_off = pos; break; }
    if _crc_range(data, pos + 4, total - 4) != crc_stored {
      damaged = true;
      damage_off = pos;
      break;
    }
    let key = _read_key(data, pos, kl);
    let tomb = (rflags % 2) == 1;
    _apply(s, key, seg, pos, vl, tomb);
    pos = pos + total;
    valid_end = pos;
  }
  return _ScanResult{ damaged: damaged; valid_end: valid_end; damage_off: damage_off; size: dlen; };
}

// Renames a damaged segment out of the .kv namespace (manual recovery keeps
// the bytes in <name>.bad) so later reopens do not fail on it.
fn _abandon_segment(s: &KvStore, id: Int) -> Result[Unit, Str] {
  let name = _seg_name(s.prefix, id);
  let r = io.rename(_at(s.dir, name), _at(s.dir, name + ".bad"));
  if !r.is_ok { return Err("kv: cannot abandon segment: " + name); }
  return Ok(());
}

// Rewrites the file with only its valid prefix (fs_write truncates), so the
// torn tail bytes are gone and cannot fuse with future records.
fn _repair_segment(s: &KvStore, id: Int, data: &Vec[UInt8], valid_end: Int) -> Result[Unit, Str] {
  var keep = Vec[UInt8].new();
  var i = 0;
  while i < valid_end {
    keep.push(data[i]);
    i = i + 1;
  }
  let name = _seg_name(s.prefix, id);
  let r = fs.fs_write(_at(s.dir, name), &keep);
  if !r.is_ok { return Err("kv: cannot repair segment: " + name); }
  return Ok(());
}

fn _create_segment(s: &mut KvStore, id: Int) -> Result[Unit, Str] {
  let h = _header_bytes(0, id, io.time_now());
  let name = _seg_name(s.prefix, id);
  let w = fs.fs_write(_at(s.dir, name), &h);
  if !w.is_ok { return Err("kv: cannot create segment: " + name); }
  s.seg_id = id;
  s.seg_len = KV_HEADER_SIZE;
  return Ok(());
}

// Builds the whole in-memory index from disk (also used by kv_reopen after a
// caller-side state reset). See the module header for the exact rules.
fn _load(s: &mut KvStore) -> Result[Unit, Str] {
  let snap = _load_snapshot(s);
  let ids = _discover_ids(s);
  var newest_id = 0;
  if ids.len() > 0 { newest_id = ids[ids.len() - 1]; }
  var need_new = false;
  var active_id = 0;
  var active_len = 0;
  var scanned = false;
  var i = 0;
  while i < ids.len() {
    let id = ids[i];
    if snap.valid && id < snap.seg {
      i = i + 1;
      continue;
    }
    var from = KV_HEADER_SIZE;
    if snap.valid && id == snap.seg { from = snap.off; }
    let rr = _read_all(_at(s.dir, _seg_name(s.prefix, id)));
    if !rr.is_ok { return Err(rr.error); }
    let data = rr.value;
    let is_newest = id == newest_id;
    let flags = _header_flags(&data, id);
    if flags < 0 {
      if is_newest {
        let ar = _abandon_segment(s, id);
        if !ar.is_ok { return Err(ar.error); }
        need_new = true;
        i = i + 1;
        continue;
      }
      return Err("kv: corrupt segment header: " + _seg_name(s.prefix, id));
    }
    let sr = _scan_records(s, &data, id, from);
    scanned = true;
    if sr.damaged {
      if is_newest {
        let tr = _repair_segment(s, id, &data, sr.valid_end);
        if !tr.is_ok { return Err(tr.error); }
        need_new = true;
      } else {
        return Err("kv: corrupt record: " + _seg_name(s.prefix, id) + " at " + _digits(sr.damage_off));
      }
    } else {
      if is_newest {
        active_id = id;
        active_len = data.len();
      }
    }
    i = i + 1;
  }
  if need_new {
    return _create_segment(s, newest_id + 1);
  }
  if !scanned {
    var nid = 1;
    if snap.valid && snap.seg + 1 > nid { nid = snap.seg + 1; }
    if newest_id + 1 > nid { nid = newest_id + 1; }
    return _create_segment(s, nid);
  }
  s.seg_id = active_id;
  s.seg_len = active_len;
  return Ok(());
}

// --------------------------------------------------
//  Public API: lifecycle
// --------------------------------------------------

/// Opens (or creates) the store in `dir` under the file-name `prefix`.
///
/// Discovers `<prefix>seg-<10-digit-id>.kv` segments, loads an optional valid
/// snapshot, replays records with last-write-wins and creates `<prefix>seg-1`
/// when the store is empty. `seg_max` (>= 64) is the rotation threshold for
/// the active segment.
///
/// Errors (all start "kv: "): "kv: empty directory", "kv: directory not
/// found: <dir>", "kv: seg_max too small", "kv: corrupt segment header:
/// <name>", "kv: corrupt record: <name> at <off>", plus I/O errors.
/// Complexity: O(probed ids + total segment bytes read).
pub fn kv_open(dir: Str, prefix: Str, seg_max: Int) -> Result[KvStore, Str] {
  if dir.len() == 0 { return Err("kv: empty directory"); }
  if !io.is_dir(dir) { return Err("kv: directory not found: " + dir); }
  if seg_max < 64 { return Err("kv: seg_max too small"); }
  var s = KvStore{
    dir: dir;
    prefix: prefix;
    entries: Vec[KvEntry].new();
    live_map: string_map_new();
    order: Vec[Int].new();
    count: 0;
    seg_id: 0;
    seg_len: 0;
    seg_max: seg_max;
  };
  let r = _load(&mut s);
  if !r.is_ok { return Err(r.error); }
  return Ok(s);
}

/// Rebuilds the in-memory index from disk, discarding the current one.
///
/// The store must have been opened by kv_open. On Err the in-memory state has
/// already been reset and partially rebuilt; open a fresh store instead of
/// using it further.
/// Complexity: as kv_open.
pub fn kv_reopen(s: &mut KvStore) -> Result[Unit, Str] {
  s.entries = Vec[KvEntry].new();
  s.live_map = string_map_new();
  s.order = Vec[Int].new();
  s.count = 0;
  s.seg_id = 0;
  s.seg_len = 0;
  return _load(s);
}

/// Closes the store. A no-op: every operation opens and closes its own file
/// handle (there is no buffered handle to flush). Present for lifecycle
/// symmetry; the store stays usable afterwards.
/// Complexity: O(1).
pub fn kv_close(s: &mut KvStore) {
  let _ = s.seg_id;
}

// --------------------------------------------------
//  Public API: writes
// --------------------------------------------------

// Encodes, appends and applies one record; rotates when seg_len >= seg_max.
fn _append_record(s: &mut KvStore, key: Str, rec: &Vec[UInt8], vlen: Int, tomb: Bool) -> Result[Unit, Str] {
  let off = s.seg_len;
  let name = _seg_name(s.prefix, s.seg_id);
  let ar = fs.fs_append(_at(s.dir, name), rec);
  if !ar.is_ok { return Err("kv: append failed: " + name); }
  s.seg_len = s.seg_len + rec.len();
  _apply(s, key, s.seg_id, off, vlen, tomb);
  if s.seg_len >= s.seg_max {
    return _create_segment(s, s.seg_id + 1);
  }
  return Ok(());
}

/// Stores `value` (UTF-8 bytes) for `key`, overwriting any previous value.
///
/// Errors: "kv: empty key", "kv: key too large" (key > 4096 bytes),
/// "kv: value too large" (value > 64 MiB), "kv: append failed: <name>",
/// "kv: cannot create segment: <name>".
/// Complexity: O(key + value) plus one append.
pub fn kv_put(s: &mut KvStore, key: Str, value: Str) -> Result[Unit, Str] {
  var vb = Vec[UInt8].new();
  _push_str_bytes(&mut vb, value);
  return kv_put_bytes(s, key, &vb);
}

/// Stores raw `value` bytes for `key` (same rules as kv_put).
/// Complexity: O(key + value).
pub fn kv_put_bytes(s: &mut KvStore, key: Str, value: &Vec[UInt8]) -> Result[Unit, Str] {
  let ke = _key_err(key);
  if ke.len() > 0 { return Err(ke); }
  if value.len() > KV_VALUE_MAX { return Err("kv: value too large"); }
  let rec = _record_bytes(key, value, false);
  return _append_record(s, key, &rec, value.len(), false);
}

/// Deletes `key` by appending a tombstone; idempotent.
///
/// Returns Ok(true) when the key was live before the call, Ok(false) when it
/// was absent or already deleted. The tombstone is appended in both cases so
/// the delete survives a crash even when the key currently exists.
/// Errors mirror kv_put.
/// Complexity: O(key).
pub fn kv_delete(s: &mut KvStore, key: Str) -> Result[Bool, Str] {
  let ke = _key_err(key);
  if ke.len() > 0 { return Err(ke); }
  var existed = false;
  let idx = _entry_index(s, key);
  if idx >= 0 {
    if !s.entries[idx].tomb { existed = true; }
  }
  var empty = Vec[UInt8].new();
  let rec = _record_bytes(key, &empty, true);
  let ar = _append_record(s, key, &rec, 0, true);
  if !ar.is_ok { return Err(ar.error); }
  return Ok(existed);
}

// --------------------------------------------------
//  Public API: reads
// --------------------------------------------------

/// Reads the value bytes for `key`.
///
/// Ok(Some(bytes)) when live, Ok(None) when absent or tombstoned. Err
/// "kv: short read" when the recorded position cannot supply the exact
/// length (e.g. the file was truncated externally).
/// Complexity: O(value).
pub fn kv_get_bytes(s: &KvStore, key: Str) -> Result[Option[Vec[UInt8]], Str] {
  let idx = _entry_index(s, key);
  if idx < 0 { return Ok(None); }
  let e = s.entries[idx];
  if e.tomb { return Ok(None); }
  let r = _read_value(s, e.seg, e.off, e.key.len(), e.vlen);
  if !r.is_ok { return Err(r.error); }
  let b = r.value;
  return Ok(Some(b));
}

/// Reads the value as a Str; same semantics as kv_get_bytes.
/// Complexity: O(value).
pub fn kv_get(s: &KvStore, key: Str) -> Result[Option[Str], Str] {
  let r = kv_get_bytes(s, key);
  if !r.is_ok { return Err(r.error); }
  let o = r.value;
  match o {
    Some(b) => { return Ok(Some(Str::from_utf8(b))); },
    None => {},
  }
  return Ok(None);
}

/// True when `key` has a live (non-tombstone) value.
/// Complexity: O(1) amortized.
pub fn kv_contains(s: &KvStore, key: Str) -> Bool {
  let idx = _entry_index(s, key);
  if idx < 0 { return false; }
  if s.entries[idx].tomb { return false; }
  return true;
}

/// Number of live keys.
/// Complexity: O(1).
pub fn kv_count(s: &KvStore) -> Int {
  return s.count;
}

/// Live keys in first-write order (a key keeps its original position across
/// overwrites, deletes and re-insertion; tombstoned keys are skipped).
/// Complexity: O(entries).
pub fn kv_keys(s: &KvStore) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < s.order.len() {
    let idx = s.order[i];
    if !s.entries[idx].tomb {
      out.push(s.entries[idx].key);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Public API: maintenance
// --------------------------------------------------

/// Compacts all live entries into a fresh segment <seg_id+1>.
///
/// Removes stale `<prefix>seg-*.tmp` files first, writes the compacted
/// segment (compacted header flag) to `<id+1>.tmp`, atomically renames it to
/// `<id+1>.kv`, then removes older segments and the stale snapshot. Live
/// values are re-read from their current locations; tombstones are dropped
/// and the in-memory index is renumbered. On Err the store may be in a mixed
/// state that a kv_reopen resolves (the compacted segment wins by id).
/// Complexity: O(live bytes).
pub fn kv_compact(s: &mut KvStore) -> Result[Unit, Str] {
  let ids = _discover_ids(s);
  let new_id = s.seg_id + 1;
  var t = 0;
  while t < ids.len() {
    let _ = io.remove_file(_at(s.dir, _seg_tmp_name(s.prefix, ids[t])));
    t = t + 1;
  }
  let _ = io.remove_file(_at(s.dir, _seg_tmp_name(s.prefix, new_id)));
  let _ = io.remove_file(_at(s.dir, _snap_tmp_name(s.prefix)));
  var buf = _header_bytes(KV_FLAG_COMPACTED, new_id, io.time_now());
  var new_entries = Vec[KvEntry].new();
  var j = 0;
  while j < s.order.len() {
    let idx = s.order[j];
    let e = s.entries[idx];
    if !e.tomb {
      let vr = _read_value(s, e.seg, e.off, e.key.len(), e.vlen);
      if !vr.is_ok { return Err(vr.error); }
      let val = vr.value;
      let rec = _record_bytes(e.key, &val, false);
      let noff = buf.len();
      _append_vec(&mut buf, &rec);
      new_entries.push(KvEntry{ key: e.key; seg: new_id; off: noff; vlen: val.len(); tomb: false; });
    }
    j = j + 1;
  }
  let tmp_path = _at(s.dir, _seg_tmp_name(s.prefix, new_id));
  let w = fs.fs_write(tmp_path, &buf);
  if !w.is_ok { return Err("kv: compact write failed: " + _seg_tmp_name(s.prefix, new_id)); }
  let final_name = _seg_name(s.prefix, new_id);
  let rn = io.rename(tmp_path, _at(s.dir, final_name));
  if !rn.is_ok { return Err("kv: compact rename failed: " + final_name); }
  var k = 0;
  while k < ids.len() {
    if ids[k] != new_id {
      let _ = io.remove_file(_at(s.dir, _seg_name(s.prefix, ids[k])));
    }
    k = k + 1;
  }
  let _ = io.remove_file(_at(s.dir, _snap_name(s.prefix)));
  let _ = io.remove_file(_at(s.dir, _snap_tmp_name(s.prefix)));
  s.entries = new_entries;
  s.live_map = string_map_new();
  s.order = Vec[Int].new();
  s.count = 0;
  var q = 0;
  while q < s.entries.len() {
    let kk = s.entries[q].key;
    string_map_put(&mut s.live_map, kk, q);
    s.order.push(q);
    s.count = s.count + 1;
    q = q + 1;
  }
  s.seg_id = new_id;
  s.seg_len = buf.len();
  return Ok(());
}

/// Writes an optional snapshot of all live entries to `<prefix>snapshot.kv`.
///
/// The snapshot-flagged header records the current segment as base_seg and
/// its append offset as base_off; reopen loads the snapshot and replays the
/// base segment from base_off plus every newer segment. Snapshot does not
/// touch the segments, so a lost or invalid snapshot is harmless.
/// Complexity: O(live bytes).
pub fn kv_snapshot(s: &mut KvStore) -> Result[Unit, Str] {
  var buf = _header_bytes(KV_FLAG_SNAPSHOT, s.seg_id, s.seg_len);
  var j = 0;
  while j < s.order.len() {
    let idx = s.order[j];
    let e = s.entries[idx];
    if !e.tomb {
      let vr = _read_value(s, e.seg, e.off, e.key.len(), e.vlen);
      if !vr.is_ok { return Err(vr.error); }
      let val = vr.value;
      let rec = _record_bytes(e.key, &val, false);
      _append_vec(&mut buf, &rec);
    }
    j = j + 1;
  }
  let tmp_path = _at(s.dir, _snap_tmp_name(s.prefix));
  let w = fs.fs_write(tmp_path, &buf);
  if !w.is_ok { return Err("kv: snapshot write failed"); }
  let rn = io.rename(tmp_path, _at(s.dir, _snap_name(s.prefix)));
  if !rn.is_ok { return Err("kv: snapshot rename failed"); }
  return Ok(());
}
