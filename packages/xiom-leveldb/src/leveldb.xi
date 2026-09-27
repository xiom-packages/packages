// XIOM -- xiom.leveldb: LevelDB log/SSTable structural parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: pure structural parsing of the LevelDB on-disk formats. No
// filesystem access, no compression beyond the 1-byte compression-type flag
// of a block trailer, no key-value store behaviour.
//
//   * LEB128 varints (32-bit and 64-bit) with overflow rejection and
//     consumed-byte counts;
//   * internal keys: user key bytes + 8-byte little-endian tag
//     (sequence << 8 | type), type VALUE = 1 / DELETION = 0;
//   * log records: 7-byte physical header (masked CRC32C u32 LE, length u16
//     LE, record type), the 32 KiB block-boundary rule, a feed-based
//     reassembler for FIRST/MIDDLE/LAST fragments and masked CRC32C
//     verification (Castagnoli reflected polynomial 0x82F63B78 with the
//     LevelDB rotation mask);
//   * block format: prefix-compressed entries (shared / non-shared /
//     value-length varints), the restart array at the block end, the 5-byte
//     block trailer (compression byte 0/1 + masked CRC32C u32 LE) and an
//     iterator over entries that checks restart-point alignment;
//   * table footer (48 bytes), fixed-width and LEB128 BlockHandle
//     encode/decode and index-block entries whose value is a bounded
//     BlockHandle.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; bit
//     fields are extracted with division and modulo, never with shifts or
//     `&` on values whose sign could be set.
//   * Vec reads go through typed locals; `&struct.field` is bound to a
//     local before being passed as a `&Vec[UInt8]` argument.
//   * parallel Vec fields replace Vec[StructType]; every push is mirrored
//     on its sibling vectors.
//   * errors carry the byte offset where the problem was detected.
// See SPEC.md for the byte-level layout tables, the error catalog and the
// scope limits.

module xiom.leveldb

use xiom.convert;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// A decoded LEB128 varint plus the number of bytes it consumed.
///
/// `value` is always in [0, 2^32) for leveldb_parse_varint32 and in
/// [0, 2^63) for leveldb_parse_varint64 (values above Int max are rejected
/// as "value exceeds Int range").
pub type LevelDbVarint = {
  value: Int;
  size: Int;
}

/// A decoded SSTable BlockHandle: a byte offset and a byte length.
///
/// `encoded_len` is the number of bytes the handle occupied where it was
/// decoded (16 in the fixed-width footer layout, otherwise the LEB128
/// varint pair length).
pub type LevelDbBlockHandle = {
  offset: Int;
  size: Int;
  encoded_len: Int;
}

/// A decoded internal key.
///
/// `tag` is the raw 8-byte little-endian value `sequence << 8 | ktype`;
/// `ktype` is 1 (VALUE) or 0 (DELETION); `user_key` excludes the tag. Tags
/// with bit 63 set (sequence >= 2^55) are rejected as out of Int range.
pub type LevelDbInternalKey = {
  user_key: Vec[UInt8];
  tag: Int;
  sequence: Int;
  ktype: Int;
}

/// One parsed 7-byte physical log record header.
///
/// `crc` is the stored masked CRC32C (u32) of the payload; `length` is the
/// u16 payload length; `rtype` is 1 FULL, 2 FIRST, 3 MIDDLE or 4 LAST.
pub type LevelDbLogHeader = {
  crc: Int;
  length: Int;
  rtype: Int;
}

/// Reassembly state carried between leveldb_log_feed calls.
///
/// `have_partial` says whether a FIRST/MIDDLE fragment is open;
/// `partial` is the accumulated payload of that open record; `start` is the
/// absolute byte offset of its FIRST fragment header (-1 when none).
pub type LevelDbLogState = {
  have_partial: Bool;
  partial: Vec[UInt8];
  start: Int;
}

/// The complete records produced while feeding one log block.
///
/// `payloads` holds one byte vector per completed record; `rtypes` the type
/// of its final fragment (1 FULL or 4 LAST); `starts`/`ends` the absolute
/// byte offsets of the first fragment header and one past the last
/// fragment. `next_have`/`next_partial`/`next_start` are the state to pass
/// to the following leveldb_log_feed call.
pub type LevelDbLogBatch = {
  payloads: Vec[Vec[UInt8]];
  rtypes: Vec[Int];
  starts: Vec[Int];
  ends: Vec[Int];
  next_have: Bool;
  next_partial: Vec[UInt8];
  next_start: Int;
}

/// One decoded block entry.
///
/// `key` is the fully reconstructed key (shared prefix bytes followed by
/// the unshared bytes stored in the block); `value_offset` is the offset of
/// the value inside the block body; `entry_bytes` is the total number of
/// bytes consumed by the entry (varint header + key bytes + value bytes).
pub type LevelDbBlockEntry = {
  shared_len: Int;
  non_shared_len: Int;
  value_len: Int;
  key: Vec[UInt8];
  value_offset: Int;
  entry_bytes: Int;
}

/// The restart array of a block.
///
/// `entries_end` is the offset where entries stop and the restart array
/// begins; `offsets` holds `count` u32 LE entry offsets.
pub type LevelDbBlockRestarts = {
  count: Int;
  offsets: Vec[Int];
  entries_end: Int;
}

/// A whole block body walked entry by entry, in parallel vectors.
///
/// `key_data` is the concatenation of all reconstructed keys;
/// `key_offsets[i]`/`key_sizes[i]` slice it for entry `i`;
/// `value_offsets[i]`/`value_sizes[i]` locate the value inside the block
/// body; `shared_lens[i]` is the stored shared-prefix length;
/// `entry_offsets[i]` is where the entry starts; `restart_indices[j]` is
/// the entry index of restart point `j`.
pub type LevelDbBlockEntries = {
  count: Int;
  key_data: Vec[UInt8];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  shared_lens: Vec[Int];
  value_offsets: Vec[Int];
  value_sizes: Vec[Int];
  entry_offsets: Vec[Int];
  restart_indices: Vec[Int];
}

/// The 5-byte block trailer that follows a block body.
///
/// `compression` is the flag byte (0 = none, 1 = snappy; the payload is not
/// decompressed); `crc` is the stored masked CRC32C (u32) of the body.
pub type LevelDbBlockTrailer = {
  compression: Int;
  crc: Int;
}

/// A table footer, reduced to its two BlockHandles.
///
/// The fixed-width footer layout stores each field as a u64 LE; the
/// LEB128 footer layout stores each handle as two varint64 values.
pub type LevelDbFooter = {
  metaindex_offset: Int;
  metaindex_size: Int;
  index_offset: Int;
  index_size: Int;
}

/// A whole index (or metaindex) block walked entry by entry.
///
/// Keys are in `key_data`/`key_offsets`/`key_sizes`; every value is a
/// bounded BlockHandle, split into `handle_offsets`, `handle_sizes` and
/// `handle_lens` (the handle's encoded length).
pub type LevelDbIndex = {
  count: Int;
  key_data: Vec[UInt8];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  handle_offsets: Vec[Int];
  handle_sizes: Vec[Int];
  handle_lens: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[LevelDbVarint, Str].
fn _ok_varint(v: LevelDbVarint) -> Result[LevelDbVarint, Str] { return Ok(v); }
// Err(m) for Result[LevelDbVarint, Str].
fn _err_varint(m: Str) -> Result[LevelDbVarint, Str] { return Err(m); }
// Ok(v) for Result[LevelDbVarint, Int] (the Int is a _varint_core status).
fn _ok_vint(v: LevelDbVarint) -> Result[LevelDbVarint, Int] { return Ok(v); }
// Err(c) for Result[LevelDbVarint, Int].
fn _err_vint(c: Int) -> Result[LevelDbVarint, Int] { return Err(c); }
// Ok(v) for Result[LevelDbBlockHandle, Str].
fn _ok_bhandle(v: LevelDbBlockHandle) -> Result[LevelDbBlockHandle, Str] { return Ok(v); }
// Err(m) for Result[LevelDbBlockHandle, Str].
fn _err_bhandle(m: Str) -> Result[LevelDbBlockHandle, Str] { return Err(m); }
// Ok(v) for Result[LevelDbInternalKey, Str].
fn _ok_ikey(v: LevelDbInternalKey) -> Result[LevelDbInternalKey, Str] { return Ok(v); }
// Err(m) for Result[LevelDbInternalKey, Str].
fn _err_ikey(m: Str) -> Result[LevelDbInternalKey, Str] { return Err(m); }
// Ok(v) for Result[LevelDbLogHeader, Str].
fn _ok_lh(v: LevelDbLogHeader) -> Result[LevelDbLogHeader, Str] { return Ok(v); }
// Err(m) for Result[LevelDbLogHeader, Str].
fn _err_lh(m: Str) -> Result[LevelDbLogHeader, Str] { return Err(m); }
// Ok(v) for Result[LevelDbLogBatch, Str].
fn _ok_batch(v: LevelDbLogBatch) -> Result[LevelDbLogBatch, Str] { return Ok(v); }
// Err(m) for Result[LevelDbLogBatch, Str].
fn _err_batch(m: Str) -> Result[LevelDbLogBatch, Str] { return Err(m); }
// Ok(v) for Result[LevelDbBlockEntry, Str].
fn _ok_entry(v: LevelDbBlockEntry) -> Result[LevelDbBlockEntry, Str] { return Ok(v); }
// Err(m) for Result[LevelDbBlockEntry, Str].
fn _err_entry(m: Str) -> Result[LevelDbBlockEntry, Str] { return Err(m); }
// Ok(v) for Result[LevelDbBlockRestarts, Str].
fn _ok_restarts(v: LevelDbBlockRestarts) -> Result[LevelDbBlockRestarts, Str] { return Ok(v); }
// Err(m) for Result[LevelDbBlockRestarts, Str].
fn _err_restarts(m: Str) -> Result[LevelDbBlockRestarts, Str] { return Err(m); }
// Ok(v) for Result[LevelDbBlockEntries, Str].
fn _ok_bentries(v: LevelDbBlockEntries) -> Result[LevelDbBlockEntries, Str] { return Ok(v); }
// Err(m) for Result[LevelDbBlockEntries, Str].
fn _err_bentries(m: Str) -> Result[LevelDbBlockEntries, Str] { return Err(m); }
// Ok(v) for Result[LevelDbBlockTrailer, Str].
fn _ok_trailer(v: LevelDbBlockTrailer) -> Result[LevelDbBlockTrailer, Str] { return Ok(v); }
// Err(m) for Result[LevelDbBlockTrailer, Str].
fn _err_trailer(m: Str) -> Result[LevelDbBlockTrailer, Str] { return Err(m); }
// Ok(v) for Result[LevelDbFooter, Str].
fn _ok_footer(v: LevelDbFooter) -> Result[LevelDbFooter, Str] { return Ok(v); }
// Err(m) for Result[LevelDbFooter, Str].
fn _err_footer(m: Str) -> Result[LevelDbFooter, Str] { return Err(m); }
// Ok(v) for Result[LevelDbIndex, Str].
fn _ok_index(v: LevelDbIndex) -> Result[LevelDbIndex, Str] { return Ok(v); }
// Err(m) for Result[LevelDbIndex, Str].
fn _err_index(m: Str) -> Result[LevelDbIndex, Str] { return Err(m); }
// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }
// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned little-endian u16 at `pos`; callers guarantee the bounds.
fn _le_u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) + _byte(data, pos + 1) * 256;
}

// Unsigned little-endian u32 at `pos`; callers guarantee the bounds.
fn _le_u32(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) + _byte(data, pos + 1) * 256 + _byte(data, pos + 2) * 65536 + _byte(data, pos + 3) * 16777216;
}

// Unsigned little-endian u64 at `pos`; callers guarantee the bounds and
// that byte 7 is < 128 (so the value fits a positive Int).
fn _le_u64(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var mult: Int = 1;
  var i = 0;
  while i < 8 {
    v = v + _byte(data, pos + i) * mult;
    mult = mult * 256;
    i = i + 1;
  }
  return v;
}

// Byte `k` of `v` (0 = least significant) as UInt8.
fn _byte_of(v: Int, k: Int) -> UInt8 {
  var q = v;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the little-endian u32 encoding of `v`.
fn _push_le32(dst: &mut Vec[UInt8], v: Int) {
  dst.push(_byte_of(v, 0));
  dst.push(_byte_of(v, 1));
  dst.push(_byte_of(v, 2));
  dst.push(_byte_of(v, 3));
}

// Append the little-endian u64 encoding of `v` (v >= 0).
fn _push_le64(dst: &mut Vec[UInt8], v: Int) {
  dst.push(_byte_of(v, 0));
  dst.push(_byte_of(v, 1));
  dst.push(_byte_of(v, 2));
  dst.push(_byte_of(v, 3));
  dst.push(_byte_of(v, 4));
  dst.push(_byte_of(v, 5));
  dst.push(_byte_of(v, 6));
  dst.push(_byte_of(v, 7));
}

// Append the 8 magic bytes 57 FB 80 8B 24 75 47 DB (the LevelDB table magic
// 0xdb4775248b80fb57 as little-endian u64).
fn _push_table_magic(dst: &mut Vec[UInt8]) {
  dst.push(87 as UInt8);
  dst.push(251 as UInt8);
  dst.push(128 as UInt8);
  dst.push(139 as UInt8);
  dst.push(36 as UInt8);
  dst.push(117 as UInt8);
  dst.push(71 as UInt8);
  dst.push(219 as UInt8);
}

// Copy [start, start + size) of `data` into a fresh Vec; callers guarantee
// the bounds.
fn _copy_range(data: &Vec[UInt8], start: Int, size: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < size {
    let b: UInt8 = data[start + i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

// Append all bytes of `src` to `dst`.
fn _append(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    dst.push(b);
    i = i + 1;
  }
}

// Error text with the byte offset appended: "<msg> at <off>".
fn _at(msg: Str, off: Int) -> Str {
  return msg + " at " + convert.int_to_string(off);
}

// Turn a _varint_core status code into "<label>: <reason> at <pos>".
// Codes: 1 = truncated, 2 = overflow, 3 = value exceeds Int range.
fn _vmsg(label: Str, code: Int, pos: Int) -> Str {
  if code == 1 { return _at(label + ": truncated", pos); }
  if code == 2 { return _at(label + ": overflow", pos); }
  if code == 3 { return _at(label + ": value exceeds Int range", pos); }
  return _at(label + ": bad input", pos);
}

// --------------------------------------------------
//  LEB128 varints
// --------------------------------------------------

// Shared base-128 reader. `bits` is 32 or 64; `limit` is an exclusive byte
// bound (must be <= data.len()). Err codes: 1 truncated, 2 overflow,
// 3 value exceeds Int range (64-bit only).
fn _varint_core(data: &Vec[UInt8], pos: Int, limit: Int, bits: Int) -> Result[LevelDbVarint, Int] {
  if pos < 0 { return _err_vint(1); }
  var value: Int = 0;
  var mult: Int = 1;
  var i = 0;
  while i < 10 {
    if pos + i >= limit { return _err_vint(1); }
    let b = _byte(data, pos + i);
    let cont = b / 128;
    let payload = b % 128;
    if bits == 32 {
      if i == 4 {
        if cont == 1 { return _err_vint(2); }
        if payload > 15 { return _err_vint(2); }
        return _ok_vint(LevelDbVarint{ value: value + payload * mult; size: 5; });
      }
      value = value + payload * mult;
      if cont == 0 {
        return _ok_vint(LevelDbVarint{ value: value; size: i + 1; });
      }
      mult = mult * 128;
      i = i + 1;
    } else {
      if i == 9 {
        if cont == 1 { return _err_vint(2); }
        if payload > 1 { return _err_vint(2); }
        if payload == 1 { return _err_vint(3); }
        return _ok_vint(LevelDbVarint{ value: value; size: 10; });
      }
      value = value + payload * mult;
      if cont == 0 {
        return _ok_vint(LevelDbVarint{ value: value; size: i + 1; });
      }
      mult = mult * 128;
      i = i + 1;
    }
  }
  return _err_vint(1);
}

/// Decode one unsigned 32-bit LEB128 varint at `pos`.
///
/// Accepts at most 5 bytes; the 5th byte must be a terminator with payload
/// <= 15. Errors: "varint32: truncated at <pos>", "varint32: overflow at
/// <pos>". Non-canonical (over-long) encodings of small values are
/// accepted, as in LevelDB. Complexity: O(1).
pub fn leveldb_parse_varint32(data: &Vec[UInt8], pos: Int) -> Result[LevelDbVarint, Str] {
  let r = _varint_core(data, pos, data.len(), 32);
  if !r.is_ok {
    let code: Int = r.error;
    return _err_varint(_vmsg("varint32", code, pos));
  }
  return _ok_varint(r.value);
}

/// Decode one unsigned 64-bit LEB128 varint at `pos`.
///
/// Accepts at most 10 bytes; the 10th byte must be a terminator with
/// payload <= 1. Values >= 2^63 are rejected because XIOM Int is signed:
/// "varint64: value exceeds Int range at <pos>" (sequences and lengths in
/// real LevelDB files are far below that). "varint64: truncated at <pos>"
/// and "varint64: overflow at <pos>" cover the rest. Complexity: O(1).
pub fn leveldb_parse_varint64(data: &Vec[UInt8], pos: Int) -> Result[LevelDbVarint, Str] {
  let r = _varint_core(data, pos, data.len(), 64);
  if !r.is_ok {
    let code: Int = r.error;
    return _err_varint(_vmsg("varint64", code, pos));
  }
  return _ok_varint(r.value);
}

/// Number of bytes leveldb_push_varint32 would write for `value`, or -1
/// when `value` is negative or above 4294967295. Complexity: O(1).
pub fn leveldb_varint32_size(value: Int) -> Int {
  if value < 0 { return -1; }
  if value > 4294967295 { return -1; }
  var n = 1;
  var v = value;
  while v >= 128 {
    v = v / 128;
    n = n + 1;
  }
  return n;
}

/// Number of bytes leveldb_push_varint64 would write for `value`, or -1
/// when `value` is negative (the Int max bound is implicit).
/// Complexity: O(1).
pub fn leveldb_varint64_size(value: Int) -> Int {
  if value < 0 { return -1; }
  var n = 1;
  var v = value;
  while v >= 128 {
    v = v / 128;
    n = n + 1;
  }
  return n;
}

/// Append the LEB128 encoding of a non-negative 32-bit value.
///
/// Returns false (and writes nothing) when `value` is negative or above
/// 4294967295. Complexity: O(bytes written).
pub fn leveldb_push_varint32(dst: &mut Vec[UInt8], value: Int) -> Bool {
  if value < 0 { return false; }
  if value > 4294967295 { return false; }
  var v = value;
  while v >= 128 {
    let b: Int = (v % 128) + 128;
    dst.push(b as UInt8);
    v = v / 128;
  }
  dst.push(v as UInt8);
  return true;
}

/// Append the LEB128 encoding of a non-negative Int value (up to 2^63-1).
///
/// Returns false (and writes nothing) when `value` is negative.
/// Complexity: O(bytes written).
pub fn leveldb_push_varint64(dst: &mut Vec[UInt8], value: Int) -> Bool {
  if value < 0 { return false; }
  var v = value;
  while v >= 128 {
    let b: Int = (v % 128) + 128;
    dst.push(b as UInt8);
    v = v / 128;
  }
  dst.push(v as UInt8);
  return true;
}

// --------------------------------------------------
//  CRC32C (Castagnoli) with the LevelDB mask
// --------------------------------------------------

// One reflected CRC32C step for byte `b`: xor into the register, then eight
// right shifts with the reversed polynomial 0x82F63B78 (2197175160) fed
// back on every set low bit. The register stays in [0, 2^32).
fn _crc32c_step(crc_in: Int, b: Int) -> Int {
  var crc = crc_in ^ b;
  var k = 0;
  while k < 8 {
    let lsb = crc % 2;
    crc = crc / 2;
    if lsb == 1 {
      crc = crc ^ 2197175160;
    }
    k = k + 1;
  }
  return crc;
}

/// Raw CRC32C (Castagnoli, reflected polynomial 0x82F63B78, init
/// 0xFFFFFFFF, final xor 0xFFFFFFFF) over [start, start + size) of `data`.
///
/// Returns a u32 as an Int, or -1 when `start`/`size` are negative or the
/// range falls outside `data`. Complexity: O(size).
pub fn leveldb_crc32c(data: &Vec[UInt8], start: Int, size: Int) -> Int {
  if start < 0 { return -1; }
  if size < 0 { return -1; }
  if start + size > data.len() { return -1; }
  var crc = 4294967295;
  var i = 0;
  while i < size {
    crc = _crc32c_step(crc, _byte(data, start + i));
    i = i + 1;
  }
  return (crc ^ 4294967295) & 4294967295;
}

/// The LevelDB CRC mask: rotate the u32 right by 15 bits (equivalently left
/// by 17) and add the constant delta 0xA282EAD8 (2726488792) modulo 2^32.
///
/// Returns -1 when `crc` is negative or above 4294967295. Complexity: O(1).
pub fn leveldb_mask_crc32c(crc: Int) -> Int {
  if crc < 0 { return -1; }
  if crc > 4294967295 { return -1; }
  // (crc >> 15) is crc / 32768; (crc << 17) is (crc % 32768) * 131072.
  let rot = ((crc / 32768) + (crc % 32768) * 131072) & 4294967295;
  return (rot + 2726488792) & 4294967295;
}

/// Inverse of leveldb_mask_crc32c: subtract the delta modulo 2^32 and
/// rotate left by 15 bits (right by 17).
///
/// Returns -1 when `masked` is negative or above 4294967295. Complexity:
/// O(1).
pub fn leveldb_unmask_crc32c(masked: Int) -> Int {
  if masked < 0 { return -1; }
  if masked > 4294967295 { return -1; }
  // 2^32 - 2726488792 = 1568478504.
  let rot = (masked + 1568478504) & 4294967295;
  return ((rot / 131072) + (rot % 131072) * 32768) & 4294967295;
}

/// Masked CRC32C of [start, start + size) of `data`, i.e. the value stored
/// in log headers and block trailers. Returns -1 for out-of-range input.
/// Complexity: O(size).
pub fn leveldb_crc32c_masked(data: &Vec[UInt8], start: Int, size: Int) -> Int {
  let raw = leveldb_crc32c(data, start, size);
  if raw < 0 { return -1; }
  return leveldb_mask_crc32c(raw);
}

// --------------------------------------------------
//  Internal keys
// --------------------------------------------------

/// Bytewise (lexicographic, then shorter-first) comparison of two byte
/// vectors. Returns -1, 0 or 1 like str_compare. Complexity: O(min len).
pub fn leveldb_bytewise_compare(a: &Vec[UInt8], b: &Vec[UInt8]) -> Int {
  var n = a.len();
  if b.len() < n { n = b.len(); }
  var i = 0;
  while i < n {
    let av = _byte(a, i);
    let bv = _byte(b, i);
    if av < bv { return -1; }
    if av > bv { return 1; }
    i = i + 1;
  }
  if a.len() < b.len() { return -1; }
  if a.len() > b.len() { return 1; }
  return 0;
}

/// True when `t` is a known internal-key value type (0 DELETION, 1 VALUE).
/// Complexity: O(1).
pub fn leveldb_internal_key_valid_type(t: Int) -> Bool {
  if t == 0 { return true; }
  if t == 1 { return true; }
  return false;
}

/// Name of an internal-key value type: "DELETION" (0), "VALUE" (1) or ""
/// for anything else. Complexity: O(1).
pub fn leveldb_internal_key_type_name(t: Int) -> Str {
  if t == 0 { return "DELETION"; }
  if t == 1 { return "VALUE"; }
  return "";
}

/// The 8-byte tag value `sequence << 8 | ktype`, or -1 when `sequence` is
/// outside [0, 2^56-1] or `ktype` is not 0/1. Complexity: O(1).
pub fn leveldb_internal_key_tag(sequence: Int, ktype: Int) -> Int {
  if sequence < 0 { return -1; }
  if sequence > 72057594037927935 { return -1; }
  if !leveldb_internal_key_valid_type(ktype) { return -1; }
  return sequence * 256 + ktype;
}

/// Build the stored form of an internal key: user key bytes followed by the
/// 8-byte little-endian tag.
///
/// Errors: "internal key: bad sequence at 0" (outside [0, 2^56-1]),
/// "internal key: bad type at 0" (not 0/1), "internal key: empty user key
/// at 0". Complexity: O(user_key).
pub fn leveldb_internal_key_encode(user_key: &Vec[UInt8], sequence: Int, ktype: Int) -> Result[Vec[UInt8], Str] {
  if user_key.len() == 0 {
    return _err_bytes(_at("internal key: empty user key", 0));
  }
  let tag = leveldb_internal_key_tag(sequence, ktype);
  if tag < 0 {
    if !leveldb_internal_key_valid_type(ktype) {
      return _err_bytes(_at("internal key: bad type", 0));
    }
    return _err_bytes(_at("internal key: bad sequence", 0));
  }
  var out = Vec[UInt8].new();
  _append(&mut out, user_key);
  _push_le64(&mut out, tag);
  return _ok_bytes(out);
}

/// Decode an internal key: the last 8 bytes are the little-endian tag, the
/// rest is the user key.
///
/// Errors: "internal key: too short at 0" (fewer than 8 bytes), "internal
/// key: tag exceeds Int range at <n-8>" (bit 63 of the tag set, i.e.
/// sequence >= 2^55). Complexity: O(key.len()).
pub fn leveldb_parse_internal_key(key: &Vec[UInt8]) -> Result[LevelDbInternalKey, Str] {
  let n = key.len();
  if n < 8 {
    return _err_ikey(_at("internal key: too short", 0));
  }
  if _byte(key, n - 1) >= 128 {
    return _err_ikey(_at("internal key: tag exceeds Int range", n - 8));
  }
  var tag: Int = 0;
  var mult: Int = 1;
  var i = 0;
  while i < 8 {
    tag = tag + _byte(key, n - 8 + i) * mult;
    mult = mult * 256;
    i = i + 1;
  }
  var user = Vec[UInt8].new();
  var j = 0;
  while j < n - 8 {
    let b: UInt8 = key[j];
    user.push(b);
    j = j + 1;
  }
  return _ok_ikey(LevelDbInternalKey{ user_key: user; tag: tag; sequence: tag / 256; ktype: tag % 256; });
}

/// Copy of the user-key bytes of a decoded internal key. Complexity:
/// O(user_key).
pub fn leveldb_internal_key_user_key(k: &LevelDbInternalKey) -> Vec[UInt8] {
  let uk: Vec[UInt8] = k.user_key;
  var out = Vec[UInt8].new();
  _append(&mut out, &uk);
  return out;
}

/// Sequence number of a decoded internal key. Complexity: O(1).
pub fn leveldb_internal_key_sequence(k: &LevelDbInternalKey) -> Int {
  return k.sequence;
}

/// Value type of a decoded internal key (0 DELETION, 1 VALUE). Complexity:
/// O(1).
pub fn leveldb_internal_key_type(k: &LevelDbInternalKey) -> Int {
  return k.ktype;
}

/// The LevelDB InternalKeyComparator: user keys bytewise ascending, then
/// the tag descending (higher sequence first, VALUE before DELETION at the
/// same sequence). Returns -1 when `a` sorts first, 1 when `b` does, 0 when
/// equal. Complexity: O(min user-key length).
pub fn leveldb_internal_key_compare(a: &LevelDbInternalKey, b: &LevelDbInternalKey) -> Int {
  let ak: Vec[UInt8] = a.user_key;
  let bk: Vec[UInt8] = b.user_key;
  let c = leveldb_bytewise_compare(&ak, &bk);
  if c != 0 { return c; }
  let at: Int = a.tag;
  let bt: Int = b.tag;
  if at > bt { return -1; }
  if at < bt { return 1; }
  return 0;
}

// --------------------------------------------------
//  Log records
// --------------------------------------------------

/// LevelDB log block size in bytes (32768). Complexity: O(1).
pub fn leveldb_log_block_size() -> Int {
  return 32768;
}

/// Bytes remaining in the 32 KiB block that contains byte offset `pos`,
/// i.e. 32768 - (pos % 32768). Returns -1 when `pos` is negative.
/// Complexity: O(1).
pub fn leveldb_log_block_remainder(pos: Int) -> Int {
  if pos < 0 { return -1; }
  let within = pos % 32768;
  return 32768 - within;
}

/// True when a fragment of `payload_len` payload bytes starting at block
/// offset `pos` fits entirely inside the 32 KiB block that contains `pos`
/// (7-byte header + payload <= remaining bytes). Complexity: O(1).
pub fn leveldb_log_fits_in_block(pos: Int, payload_len: Int) -> Bool {
  if pos < 0 { return false; }
  if payload_len < 0 { return false; }
  let rem = leveldb_log_block_remainder(pos);
  if 7 + payload_len <= rem { return true; }
  return false;
}

/// Name of a log record type: "FULL" (1), "FIRST" (2), "MIDDLE" (3),
/// "LAST" (4) or "" for anything else. Complexity: O(1).
pub fn leveldb_log_record_type_name(t: Int) -> Str {
  if t == 1 { return "FULL"; }
  if t == 2 { return "FIRST"; }
  if t == 3 { return "MIDDLE"; }
  if t == 4 { return "LAST"; }
  return "";
}

/// Parse the 7-byte physical header at `pos`: masked CRC32C u32 LE,
/// payload length u16 LE, record type byte.
///
/// Errors: "log header: truncated at <pos>", "log header: bad record type
/// at <pos>" (not 1..4, so the all-zero trailer header is rejected here),
/// "log record: length overruns block at <pos>". Complexity: O(1).
pub fn leveldb_parse_log_header(block: &Vec[UInt8], pos: Int) -> Result[LevelDbLogHeader, Str] {
  if pos < 0 {
    return _err_lh(_at("log header: truncated", 0));
  }
  if pos + 7 > block.len() {
    return _err_lh(_at("log header: truncated", pos));
  }
  let crc = _le_u32(block, pos);
  let len = _le_u16(block, pos + 4);
  let t = _byte(block, pos + 6);
  if t < 1 || t > 4 {
    return _err_lh(_at("log header: bad record type", pos));
  }
  if pos + 7 + len > block.len() {
    return _err_lh(_at("log record: length overruns block", pos));
  }
  return _ok_lh(LevelDbLogHeader{ crc: crc; length: len; rtype: t; });
}

/// True when the masked CRC32C stored in the header at `pos` matches the
/// masked CRC32C of the fragment payload that follows it. Returns false for
/// any structural problem (short header, payload overrun). Complexity:
/// O(length).
pub fn leveldb_log_fragment_crc_ok(block: &Vec[UInt8], pos: Int) -> Bool {
  if pos < 0 { return false; }
  if pos + 7 > block.len() { return false; }
  let want = _le_u32(block, pos);
  let len = _le_u16(block, pos + 4);
  if pos + 7 + len > block.len() { return false; }
  let actual = leveldb_crc32c_masked(block, pos + 7, len);
  return actual == want;
}

/// A fresh reassembly state: no open partial record. Complexity: O(1).
pub fn leveldb_log_state_new() -> LevelDbLogState {
  return LevelDbLogState{ have_partial: false; partial: Vec[UInt8].new(); start: -1; };
}

/// Feed one 32 KiB log block through the reassembler and return the records
/// completed inside it.
///
/// `block_base` is the absolute byte offset of the block inside the log
/// (0, 32768, ...) and is used for the offsets in the batch and in errors.
/// `check_crc` enables masked CRC32C verification of every fragment
/// (\"log: crc mismatch at <abs>\"). Fragment sequencing is enforced: a
/// FIRST while a record is open, a MIDDLE/LAST with none open, a FULL while
/// one is open, an unknown type, or a payload overrunning the block are
/// errors carrying the absolute offset of the offending header. A 7-byte
/// all-zero header stops the walk (trailer). When fewer than 7 bytes remain,
/// every remaining byte must be zero (\"log: nonzero trailer at <abs>\").
/// Complexity: O(block length).
pub fn leveldb_log_feed(block: &Vec[UInt8], block_base: Int, state: &LevelDbLogState, check_crc: Bool) -> Result[LevelDbLogBatch, Str] {
  let carry_partial: Vec[UInt8] = state.partial;
  let carry_have: Bool = state.have_partial;
  let carry_start: Int = state.start;
  var have = carry_have;
  var nstart = carry_start;
  var partial = Vec[UInt8].new();
  _append(&mut partial, &carry_partial);
  var payloads = Vec[Vec[UInt8]].new();
  var rtypes = Vec[Int].new();
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  let n = block.len();
  var pos = 0;
  var stopped = false;
  while pos + 7 <= n && !stopped {
    var all_zero = true;
    var z = 0;
    while z < 7 {
      if _byte(block, pos + z) != 0 { all_zero = false; }
      z = z + 1;
    }
    if all_zero {
      stopped = true;
    } else {
      let hr = leveldb_parse_log_header(block, pos);
      if !hr.is_ok {
        return _err_batch(hr.error);
      }
      let h = hr.value;
      let hlen: Int = h.length;
      let htype: Int = h.rtype;
      let abs = block_base + pos;
      if check_crc {
        if !leveldb_log_fragment_crc_ok(block, pos) {
          return _err_batch(_at("log: crc mismatch", abs));
        }
      }
      var frag = Vec[UInt8].new();
      _append_range(&mut frag, block, pos + 7, hlen);
      if htype == 1 {
        if have {
          return _err_batch(_at("log: unexpected FULL in fragmented record", abs));
        }
        payloads.push(frag);
        rtypes.push(1);
        starts.push(abs);
        ends.push(abs + 7 + hlen);
      } elif htype == 2 {
        if have {
          return _err_batch(_at("log: FIRST while fragment open", abs));
        }
        have = true;
        nstart = abs;
        partial = Vec[UInt8].new();
        _append(&mut partial, &frag);
      } elif htype == 3 {
        if !have {
          return _err_batch(_at("log: MIDDLE without FIRST", abs));
        }
        _append(&mut partial, &frag);
      } else {
        if !have {
          return _err_batch(_at("log: LAST without FIRST", abs));
        }
        _append(&mut partial, &frag);
        payloads.push(partial);
        rtypes.push(4);
        starts.push(nstart);
        ends.push(abs + 7 + hlen);
        have = false;
        partial = Vec[UInt8].new();
        nstart = -1;
      }
      pos = pos + 7 + hlen;
    }
  }
  if !stopped && pos < n {
    var i = pos;
    while i < n {
      if _byte(block, i) != 0 {
        return _err_batch(_at("log: nonzero trailer", block_base + i));
      }
      i = i + 1;
    }
  }
  if !have {
    nstart = -1;
  }
  return _ok_batch(LevelDbLogBatch{
    payloads: payloads;
    rtypes: rtypes;
    starts: starts;
    ends: ends;
    next_have: have;
    next_partial: partial;
    next_start: nstart;
  });
}

/// Finish a reassembly run: Ok(0) when no FIRST/MIDDLE fragment is still
/// open, otherwise Err("log: incomplete fragmented record at <start>").
/// Complexity: O(1).
pub fn leveldb_log_finish(state: &LevelDbLogState) -> Result[Int, Str] {
  let have: Bool = state.have_partial;
  if have {
    let start: Int = state.start;
    return _err_int(_at("log: incomplete fragmented record", start));
  }
  return _ok_int(0);
}

// --------------------------------------------------
//  Block entries and restart array
// --------------------------------------------------

// Append [start, start + size) of `data` to `dst`; callers guarantee the
// bounds.
fn _append_range(dst: &mut Vec[UInt8], data: &Vec[UInt8], start: Int, size: Int) {
  var i = 0;
  while i < size {
    let b: UInt8 = data[start + i];
    dst.push(b);
    i = i + 1;
  }
}

/// Parse one prefix-compressed block entry at `pos` inside [pos, limit).
///
/// Layout: varint32 shared length, varint32 non-shared length, varint32
/// value length, the non-shared key bytes, the value bytes. The key is
/// reconstructed from `prev_key` (pass an empty Vec at a restart point; a
/// shared length beyond prev_key is an error). `entry_bytes` in the result
/// is the total consumed byte count.
///
/// Errors: "block entry: truncated at <pos>", "block entry: overflow at
/// <pos>", "block entry: shared beyond previous key at <pos>", "block
/// entry: key overrun at <pos>", "block entry: value overrun at <pos>".
/// Complexity: O(entry bytes).
pub fn leveldb_parse_block_entry(body: &Vec[UInt8], pos: Int, limit: Int, prev_key: &Vec[UInt8]) -> Result[LevelDbBlockEntry, Str] {
  var lim = limit;
  if lim > body.len() { lim = body.len(); }
  let r1 = _varint_core(body, pos, lim, 32);
  if !r1.is_ok {
    let code: Int = r1.error;
    return _err_entry(_vmsg("block entry", code, pos));
  }
  let v1 = r1.value;
  let shared: Int = v1.value;
  let n1: Int = v1.size;
  let p2 = pos + n1;
  let r2 = _varint_core(body, p2, lim, 32);
  if !r2.is_ok {
    let code: Int = r2.error;
    return _err_entry(_vmsg("block entry", code, p2));
  }
  let v2 = r2.value;
  let nshared: Int = v2.value;
  let n2: Int = v2.size;
  let p3 = p2 + n2;
  let r3 = _varint_core(body, p3, lim, 32);
  if !r3.is_ok {
    let code: Int = r3.error;
    return _err_entry(_vmsg("block entry", code, p3));
  }
  let v3 = r3.value;
  let vlen: Int = v3.value;
  let n3: Int = v3.size;
  let hdr = n1 + n2 + n3;
  let key_start = pos + hdr;
  if shared > prev_key.len() {
    return _err_entry(_at("block entry: shared beyond previous key", pos));
  }
  if key_start + nshared > lim {
    return _err_entry(_at("block entry: key overrun", pos));
  }
  if key_start + nshared + vlen > lim {
    return _err_entry(_at("block entry: value overrun", pos));
  }
  var key = Vec[UInt8].new();
  var i = 0;
  while i < shared {
    let b: UInt8 = prev_key[i];
    key.push(b);
    i = i + 1;
  }
  i = 0;
  while i < nshared {
    let b: UInt8 = body[key_start + i];
    key.push(b);
    i = i + 1;
  }
  return _ok_entry(LevelDbBlockEntry{
    shared_len: shared;
    non_shared_len: nshared;
    value_len: vlen;
    key: key;
    value_offset: key_start + nshared;
    entry_bytes: hdr + nshared + vlen;
  });
}

/// Parse the restart array stored at the end of a block body: u32 LE
/// restart count, then that many u32 LE entry offsets.
///
/// The array must fit: `entries_end` (returned) is where entries stop.
/// Errors: "block restarts: truncated at <pos>", "block restarts: zero
/// count at <pos>", "block restarts: bad count at <pos>", "block restarts:
/// offset out of range at <pos>", "block restarts: first offset is not zero
/// at <pos>", "block restarts: offsets not increasing at <pos>".
/// Complexity: O(count).
pub fn leveldb_parse_block_restarts(body: &Vec[UInt8]) -> Result[LevelDbBlockRestarts, Str] {
  let n = body.len();
  if n < 4 {
    return _err_restarts(_at("block restarts: truncated", 0));
  }
  let cpos = n - 4;
  let count = _le_u32(body, cpos);
  if count == 0 {
    return _err_restarts(_at("block restarts: zero count", cpos));
  }
  let tail = n - 4 - count * 4;
  if tail < 0 {
    return _err_restarts(_at("block restarts: bad count", cpos));
  }
  var offsets = Vec[Int].new();
  var prev = -1;
  var i = 0;
  while i < count {
    let opos = tail + i * 4;
    let off = _le_u32(body, opos);
    if off > tail {
      return _err_restarts(_at("block restarts: offset out of range", opos));
    }
    if i == 0 && off != 0 {
      return _err_restarts(_at("block restarts: first offset is not zero", opos));
    }
    if off <= prev {
      return _err_restarts(_at("block restarts: offsets not increasing", opos));
    }
    offsets.push(off);
    prev = off;
    i = i + 1;
  }
  return _ok_restarts(LevelDbBlockRestarts{ count: count; offsets: offsets; entries_end: tail; });
}

/// Walk every entry of a block body and return all of them in parallel
/// vectors.
///
/// Restart points are checked while walking: each restart offset must land
/// on an entry boundary and the entry there must have a zero shared length.
/// Errors: any leveldb_parse_block_entry error, "block: restart offset
/// misses entry boundary at <pos>", "block: restart entry with shared bytes
/// at <pos>". Complexity: O(block length).
pub fn leveldb_parse_block_entries(body: &Vec[UInt8]) -> Result[LevelDbBlockEntries, Str] {
  let rr = leveldb_parse_block_restarts(body);
  if !rr.is_ok {
    return _err_bentries(rr.error);
  }
  let rst = rr.value;
  let rcount: Int = rst.count;
  let entries_end: Int = rst.entries_end;
  var key_data = Vec[UInt8].new();
  var key_offsets = Vec[Int].new();
  var key_sizes = Vec[Int].new();
  var shared_lens = Vec[Int].new();
  var value_offsets = Vec[Int].new();
  var value_sizes = Vec[Int].new();
  var entry_offsets = Vec[Int].new();
  var restart_indices = Vec[Int].new();
  if entries_end == 0 {
    if rcount == 1 {
      return _ok_bentries(LevelDbBlockEntries{
        count: 0;
        key_data: key_data;
        key_offsets: key_offsets;
        key_sizes: key_sizes;
        shared_lens: shared_lens;
        value_offsets: value_offsets;
        value_sizes: value_sizes;
        entry_offsets: entry_offsets;
        restart_indices: restart_indices;
      });
    }
    let ro: Int = rst.offsets[0];
    return _err_bentries(_at("block: restart offset misses entry boundary", ro));
  }
  var prev = Vec[UInt8].new();
  var pos = 0;
  var rj = 0;
  while pos < entries_end {
    var at_restart = false;
    if rj < rcount {
      let roff: Int = rst.offsets[rj];
      if roff < pos {
        return _err_bentries(_at("block: restart offset misses entry boundary", roff));
      }
      if roff == pos {
        at_restart = true;
      }
    }
    let er = leveldb_parse_block_entry(body, pos, entries_end, &prev);
    if !er.is_ok {
      return _err_bentries(er.error);
    }
    let e = er.value;
    let eshared: Int = e.shared_len;
    let evlen: Int = e.value_len;
    let evoff: Int = e.value_offset;
    let ebytes: Int = e.entry_bytes;
    let ekey: Vec[UInt8] = e.key;
    if at_restart {
      if eshared != 0 {
        return _err_bentries(_at("block: restart entry with shared bytes", pos));
      }
      restart_indices.push(key_offsets.len());
      rj = rj + 1;
    }
    entry_offsets.push(pos);
    shared_lens.push(eshared);
    key_offsets.push(key_data.len());
    key_sizes.push(ekey.len());
    var ki = 0;
    while ki < ekey.len() {
      let kb: UInt8 = ekey[ki];
      key_data.push(kb);
      ki = ki + 1;
    }
    value_offsets.push(evoff);
    value_sizes.push(evlen);
    prev = Vec[UInt8].new();
    _append(&mut prev, &ekey);
    pos = pos + ebytes;
  }
  if rj != rcount {
    let ro: Int = rst.offsets[rj];
    return _err_bentries(_at("block: restart offset misses entry boundary", ro));
  }
  return _ok_bentries(LevelDbBlockEntries{
    count: entry_offsets.len();
    key_data: key_data;
    key_offsets: key_offsets;
    key_sizes: key_sizes;
    shared_lens: shared_lens;
    value_offsets: value_offsets;
    value_sizes: value_sizes;
    entry_offsets: entry_offsets;
    restart_indices: restart_indices;
  });
}

/// Parse the entry that a restart point refers to; `restart_index` indexes
/// leveldb_parse_block_restarts offsets.
///
/// Errors: restart-array errors, "block: restart index out of range at
/// <restart_index>", "block: restart entry with shared bytes at <offset>"
/// and any entry-parse error. Complexity: O(block length) for the restart
/// array plus O(entry bytes).
pub fn leveldb_block_entry_at_restart(body: &Vec[UInt8], restart_index: Int) -> Result[LevelDbBlockEntry, Str] {
  let rr = leveldb_parse_block_restarts(body);
  if !rr.is_ok {
    return _err_entry(rr.error);
  }
  let rst = rr.value;
  let rcount: Int = rst.count;
  let entries_end: Int = rst.entries_end;
  if restart_index < 0 || restart_index >= rcount {
    return _err_entry(_at("block: restart index out of range", restart_index));
  }
  let roff: Int = rst.offsets[restart_index];
  let empty = Vec[UInt8].new();
  let er = leveldb_parse_block_entry(body, roff, entries_end, &empty);
  if !er.is_ok {
    return _err_entry(er.error);
  }
  let e = er.value;
  let eshared: Int = e.shared_len;
  if eshared != 0 {
    return _err_entry(_at("block: restart entry with shared bytes", roff));
  }
  return _ok_entry(e);
}

/// Number of entries in a walked block. Complexity: O(1).
pub fn leveldb_block_entries_count(e: &LevelDbBlockEntries) -> Int {
  return e.count;
}

/// Reconstructed key of entry `i`, or an empty Vec when out of range.
/// Complexity: O(key length).
pub fn leveldb_block_entries_key(e: &LevelDbBlockEntries, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= e.count { return Vec[UInt8].new(); }
  let kd: Vec[UInt8] = e.key_data;
  let ko: Int = e.key_offsets[i];
  let ks: Int = e.key_sizes[i];
  return _copy_range(&kd, ko, ks);
}

/// Stored shared-prefix length of entry `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn leveldb_block_entries_shared(e: &LevelDbBlockEntries, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= e.count { return -1; }
  let v: Int = e.shared_lens[i];
  return v;
}

/// Value bytes of entry `i` taken from the original block body, or an empty
/// Vec when out of range. Complexity: O(value length).
pub fn leveldb_block_entries_value(body: &Vec[UInt8], e: &LevelDbBlockEntries, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= e.count { return Vec[UInt8].new(); }
  let vo: Int = e.value_offsets[i];
  let vs: Int = e.value_sizes[i];
  return _copy_range(body, vo, vs);
}

/// Byte offset of entry `i` inside the block body, or -1 when out of range.
/// Complexity: O(1).
pub fn leveldb_block_entries_entry_offset(e: &LevelDbBlockEntries, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= e.count { return -1; }
  let v: Int = e.entry_offsets[i];
  return v;
}

/// Entry index of restart point `j`, or -1 when out of range. Complexity:
/// O(1).
pub fn leveldb_block_entries_restart_index(e: &LevelDbBlockEntries, j: Int) -> Int {
  if j < 0 { return -1; }
  if j >= e.restart_indices.len() { return -1; }
  let v: Int = e.restart_indices[j];
  return v;
}

/// Value bytes of a single decoded entry taken from the block body.
/// Complexity: O(value length).
pub fn leveldb_block_entry_value(body: &Vec[UInt8], e: &LevelDbBlockEntry) -> Vec[UInt8] {
  let vo: Int = e.value_offset;
  let vl: Int = e.value_len;
  return _copy_range(body, vo, vl);
}

// --------------------------------------------------
//  Block trailer
// --------------------------------------------------

/// Parse the 5-byte block trailer at `trailer[pos]`: compression-type byte
/// (0 = none, 1 = snappy) followed by the masked CRC32C of the block body
/// as u32 LE.
///
/// Errors: "block trailer: truncated at <pos>", "block trailer: unknown
/// compression at <pos>". Complexity: O(1).
pub fn leveldb_parse_block_trailer(trailer: &Vec[UInt8], pos: Int) -> Result[LevelDbBlockTrailer, Str] {
  if pos < 0 {
    return _err_trailer(_at("block trailer: truncated", 0));
  }
  if pos + 5 > trailer.len() {
    return _err_trailer(_at("block trailer: truncated", pos));
  }
  let comp = _byte(trailer, pos);
  if comp != 0 && comp != 1 {
    return _err_trailer(_at("block trailer: unknown compression", pos));
  }
  return _ok_trailer(LevelDbBlockTrailer{ compression: comp; crc: _le_u32(trailer, pos + 1); });
}

/// True when the trailer CRC matches the masked CRC32C of `body`.
/// The compression flag is not consulted: snappy blocks are not
/// decompressed, so the CRC of a compressed block cannot be recomputed from
/// the body alone. Complexity: O(body length).
pub fn leveldb_block_trailer_crc_ok(body: &Vec[UInt8], t: &LevelDbBlockTrailer) -> Bool {
  let comp: Int = t.compression;
  if comp != 0 { return false; }
  let want: Int = t.crc;
  let actual = leveldb_crc32c_masked(body, 0, body.len());
  return actual == want;
}

// --------------------------------------------------
//  BlockHandle encode/decode
// --------------------------------------------------

/// Append the LEB128 BlockHandle encoding: varint64 offset, varint64 size.
///
/// Returns false (writes nothing) when `offset` or `size` is negative.
/// Complexity: O(bytes written).
pub fn leveldb_block_handle_encode(dst: &mut Vec[UInt8], offset: Int, size: Int) -> Bool {
  if offset < 0 { return false; }
  if size < 0 { return false; }
  leveldb_push_varint64(dst, offset);
  leveldb_push_varint64(dst, size);
  return true;
}

/// Decode a bounded LEB128 BlockHandle inside [pos, limit).
///
/// Both varints must terminate at or before `limit`; the value region of an
/// index entry is the natural bound. `encoded_len` in the result is the
/// number of bytes consumed. Errors: "block handle offset: truncated/
/// overflow/value exceeds Int range at <pos>" and the same for "block handle
/// size". Complexity: O(1).
pub fn leveldb_block_handle_decode(data: &Vec[UInt8], pos: Int, limit: Int) -> Result[LevelDbBlockHandle, Str] {
  var lim = limit;
  if lim > data.len() { lim = data.len(); }
  let r1 = _varint_core(data, pos, lim, 64);
  if !r1.is_ok {
    let code: Int = r1.error;
    return _err_bhandle(_vmsg("block handle offset", code, pos));
  }
  let v1 = r1.value;
  let off: Int = v1.value;
  let n1: Int = v1.size;
  let p2 = pos + n1;
  let r2 = _varint_core(data, p2, lim, 64);
  if !r2.is_ok {
    let code: Int = r2.error;
    return _err_bhandle(_vmsg("block handle size", code, p2));
  }
  let v2 = r2.value;
  let sz: Int = v2.value;
  let n2: Int = v2.size;
  return _ok_bhandle(LevelDbBlockHandle{ offset: off; size: sz; encoded_len: n1 + n2; });
}

// --------------------------------------------------
//  Table footer
// --------------------------------------------------

/// True when the 8 bytes at `data[pos]` are the little-endian LevelDB table
/// magic 0xdb4775248b80fb57 (bytes 57 FB 80 8B 24 75 47 DB). Returns false
/// when out of range. Complexity: O(1).
pub fn leveldb_table_magic_ok(data: &Vec[UInt8], pos: Int) -> Bool {
  if pos < 0 { return false; }
  if pos + 8 > data.len() { return false; }
  if _le_u32(data, pos) != 2340485975 { return false; }
  if _le_u32(data, pos + 4) != 3678893348 { return false; }
  return true;
}

/// Parse a 48-byte footer in the fixed-width layout: metaindex handle at 0
/// (offset u64 LE + size u64 LE), index handle at 16, 8 zero padding bytes
/// at 32, magic at 40.
///
/// Errors: "footer: truncated at 0" (fewer than 48 bytes), "footer: bad
/// magic at 40", "footer: nonzero padding at <pos>", and "footer:
/// metaindex/index offset/size exceeds Int range at <pos>" for u64 fields
/// with bit 63 set. Complexity: O(1).
pub fn leveldb_parse_footer(data: &Vec[UInt8]) -> Result[LevelDbFooter, Str] {
  if data.len() < 48 {
    return _err_footer(_at("footer: truncated", 0));
  }
  if !leveldb_table_magic_ok(data, 40) {
    return _err_footer(_at("footer: bad magic", 40));
  }
  var i = 32;
  while i < 40 {
    if _byte(data, i) != 0 {
      return _err_footer(_at("footer: nonzero padding", i));
    }
    i = i + 1;
  }
  if _byte(data, 7) >= 128 {
    return _err_footer(_at("footer: metaindex offset exceeds Int range", 0));
  }
  if _byte(data, 15) >= 128 {
    return _err_footer(_at("footer: metaindex size exceeds Int range", 8));
  }
  if _byte(data, 23) >= 128 {
    return _err_footer(_at("footer: index offset exceeds Int range", 16));
  }
  if _byte(data, 31) >= 128 {
    return _err_footer(_at("footer: index size exceeds Int range", 24));
  }
  return _ok_footer(LevelDbFooter{
    metaindex_offset: _le_u64(data, 0);
    metaindex_size: _le_u64(data, 8);
    index_offset: _le_u64(data, 16);
    index_size: _le_u64(data, 24);
  });
}

/// Build a 48-byte footer in the fixed-width layout, the inverse of
/// leveldb_parse_footer. Complexity: O(1).
pub fn leveldb_build_footer(meta_offset: Int, meta_size: Int, index_offset: Int, index_size: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_le64(&mut out, meta_offset);
  _push_le64(&mut out, meta_size);
  _push_le64(&mut out, index_offset);
  _push_le64(&mut out, index_size);
  var i = 0;
  while i < 8 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  _push_table_magic(&mut out);
  return out;
}

/// Parse a 48-byte footer in the LEB128 layout used by modern LevelDB:
/// BlockHandle (varint64 offset, varint64 size) at 0, the index BlockHandle
/// directly after it, zero padding up to offset 40, then the magic.
///
/// Errors: "footer: truncated at 0", "footer: bad magic at 40", "footer:
/// bad metaindex handle at 0", "footer: bad index handle at <pos>",
/// "footer: nonzero padding at <pos>". Complexity: O(1).
pub fn leveldb_parse_footer_varint(data: &Vec[UInt8]) -> Result[LevelDbFooter, Str] {
  if data.len() < 48 {
    return _err_footer(_at("footer: truncated", 0));
  }
  if !leveldb_table_magic_ok(data, 40) {
    return _err_footer(_at("footer: bad magic", 40));
  }
  let mh = leveldb_block_handle_decode(data, 0, 40);
  if !mh.is_ok {
    return _err_footer(_at("footer: bad metaindex handle", 0));
  }
  let m = mh.value;
  let mlen: Int = m.encoded_len;
  let hpos = mlen;
  let ih = leveldb_block_handle_decode(data, hpos, 40);
  if !ih.is_ok {
    return _err_footer(_at("footer: bad index handle", hpos));
  }
  let ix = ih.value;
  let ilen: Int = ix.encoded_len;
  var i = hpos + ilen;
  while i < 40 {
    if _byte(data, i) != 0 {
      return _err_footer(_at("footer: nonzero padding", i));
    }
    i = i + 1;
  }
  return _ok_footer(LevelDbFooter{
    metaindex_offset: m.offset;
    metaindex_size: m.size;
    index_offset: ix.offset;
    index_size: ix.size;
  });
}

/// Build a 48-byte footer in the LEB128 layout, the inverse of
/// leveldb_parse_footer_varint. Complexity: O(1).
pub fn leveldb_build_footer_varint(meta_offset: Int, meta_size: Int, index_offset: Int, index_size: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  leveldb_block_handle_encode(&mut out, meta_offset, meta_size);
  leveldb_block_handle_encode(&mut out, index_offset, index_size);
  while out.len() < 40 {
    out.push(0 as UInt8);
  }
  _push_table_magic(&mut out);
  return out;
}

/// Check both footer handles against a table file size: each handle must be
/// non-negative and its [offset, offset + size) range must lie inside
/// [0, file_size].
///
/// Errors: "footer: negative file size at 0", "footer: metaindex handle out
/// of range at <offset>", "footer: index handle out of range at <offset>".
/// Ok(0) otherwise. Complexity: O(1).
pub fn leveldb_footer_check(f: &LevelDbFooter, file_size: Int) -> Result[Int, Str] {
  if file_size < 0 {
    return _err_int(_at("footer: negative file size", 0));
  }
  let mo: Int = f.metaindex_offset;
  let ms: Int = f.metaindex_size;
  let io2: Int = f.index_offset;
  let isz: Int = f.index_size;
  if mo < 0 || ms < 0 || mo > file_size || ms > file_size - mo {
    return _err_int(_at("footer: metaindex handle out of range", mo));
  }
  if io2 < 0 || isz < 0 || io2 > file_size || isz > file_size - io2 {
    return _err_int(_at("footer: index handle out of range", io2));
  }
  return _ok_int(0);
}

// --------------------------------------------------
//  Index block
// --------------------------------------------------

/// Walk an index (or metaindex) block: same prefix-compressed entry layout
/// as a data block, but every value must be exactly one bounded BlockHandle.
///
/// Errors: restart-array/entry errors, "index: empty block handle at <pos>",
/// "index: bad block handle at <pos>", "index: block handle overrun at
/// <pos>" (the value is longer than the handle it contains). Complexity:
/// O(block length).
pub fn leveldb_parse_index_block(body: &Vec[UInt8]) -> Result[LevelDbIndex, Str] {
  let rr = leveldb_parse_block_restarts(body);
  if !rr.is_ok {
    return _err_index(rr.error);
  }
  let rst = rr.value;
  let entries_end: Int = rst.entries_end;
  var key_data = Vec[UInt8].new();
  var key_offsets = Vec[Int].new();
  var key_sizes = Vec[Int].new();
  var handle_offsets = Vec[Int].new();
  var handle_sizes = Vec[Int].new();
  var handle_lens = Vec[Int].new();
  var prev = Vec[UInt8].new();
  var pos = 0;
  while pos < entries_end {
    let er = leveldb_parse_block_entry(body, pos, entries_end, &prev);
    if !er.is_ok {
      return _err_index(er.error);
    }
    let e = er.value;
    let evlen: Int = e.value_len;
    let evoff: Int = e.value_offset;
    let ebytes: Int = e.entry_bytes;
    let ekey: Vec[UInt8] = e.key;
    if evlen == 0 {
      return _err_index(_at("index: empty block handle", pos));
    }
    let hd = leveldb_block_handle_decode(body, evoff, evoff + evlen);
    if !hd.is_ok {
      return _err_index(_at("index: bad block handle", pos));
    }
    let hv = hd.value;
    let hoff: Int = hv.offset;
    let hsz: Int = hv.size;
    let hlen: Int = hv.encoded_len;
    if hlen != evlen {
      return _err_index(_at("index: block handle overrun", pos));
    }
    key_offsets.push(key_data.len());
    key_sizes.push(ekey.len());
    var ki = 0;
    while ki < ekey.len() {
      let kb: UInt8 = ekey[ki];
      key_data.push(kb);
      ki = ki + 1;
    }
    handle_offsets.push(hoff);
    handle_sizes.push(hsz);
    handle_lens.push(hlen);
    prev = Vec[UInt8].new();
    _append(&mut prev, &ekey);
    pos = pos + ebytes;
  }
  return _ok_index(LevelDbIndex{
    count: handle_offsets.len();
    key_data: key_data;
    key_offsets: key_offsets;
    key_sizes: key_sizes;
    handle_offsets: handle_offsets;
    handle_sizes: handle_sizes;
    handle_lens: handle_lens;
  });
}

/// Number of index entries. Complexity: O(1).
pub fn leveldb_index_count(e: &LevelDbIndex) -> Int {
  return e.count;
}

/// Separator key of index entry `i`, or an empty Vec when out of range.
/// Complexity: O(key length).
pub fn leveldb_index_key(e: &LevelDbIndex, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= e.count { return Vec[UInt8].new(); }
  let kd: Vec[UInt8] = e.key_data;
  let ko: Int = e.key_offsets[i];
  let ks: Int = e.key_sizes[i];
  return _copy_range(&kd, ko, ks);
}

/// BlockHandle stored in index entry `i` (encoded_len is the handle's own
/// length); all fields are -1 when `i` is out of range. Complexity: O(1).
pub fn leveldb_index_handle(e: &LevelDbIndex, i: Int) -> LevelDbBlockHandle {
  if i < 0 {
    return LevelDbBlockHandle{ offset: -1; size: -1; encoded_len: -1; };
  }
  if i >= e.count {
    return LevelDbBlockHandle{ offset: -1; size: -1; encoded_len: -1; };
  }
  let ho: Int = e.handle_offsets[i];
  let hs: Int = e.handle_sizes[i];
  let hl: Int = e.handle_lens[i];
  return LevelDbBlockHandle{ offset: ho; size: hs; encoded_len: hl; };
}

/// A short version marker for the module (a constant). Complexity: O(1).
pub fn leveldb_version() -> Str {
  return "0.1.0";
}

