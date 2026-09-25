// XIOM -- xiom.gpt: GUID Partition Table (GPT) codec (parse and build)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of a GPT codec. Scope:
// protective-MBR detection, the LBA-1 GPT header, the partition entry array
// and a canonical builder for the primary GPT. Backup-GPT consistency,
// filesystem detection and MBR partition semantics are documented non-goals.
// See SPEC.md for the byte layout, validation order, error catalog, CRC
// policy and test plan.
//
// Fixed geometry: the logical block size is 512 bytes; the protective MBR
// lives at LBA 0, the header at LBA 1 and the partition entries wherever the
// header's PartitionEntryLBA points (the builder writes them at LBA 2).
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - `gpt_parse` validates signature, header size, the 64-bit LBA fields, the
//   usable range, entry size/count and the entry-array bounds, then returns
//   a GptTable of flat parallel vectors: one element per entry slot for
//   type GUIDs/unique GUIDs/first LBAs/last LBAs/attributes/names. All-zero
//   type-GUID slots are legal and stay in the index; `gpt_entry_in_use`
//   reports them as unused. No Vec of structs is used.
// - GUIDs are exposed as the 32 lowercase hex characters of the 16 raw
//   on-disk bytes (no byte-order rewriting).
// - Entry names are UTF-16LE: scanning stops at the first 0x0000 code unit
//   and every code unit outside printable ASCII (0x20..0x7E) is replaced
//   with '?' (0x3F).
// - CRC-32 values are stored raw by `gpt_parse`; it never rejects a CRC
//   mismatch. Callers verify with `gpt_header_crc_ok` /
//   `gpt_entries_crc_ok`, or compute spans with `gpt_crc32_range`.
// - `gpt_build` writes a canonical primary GPT (MBR + 92-byte header +
//   zero-padded entry array) with recomputed header and entry-array CRCs.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the leaf helpers below
//     (constructing Result payloads in larger functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * 64-bit fields are accumulated little-endian into a signed Int (the
//     xiom.bson precedent); values with bit 63 set come out negative and
//     LBA fields with the top bit set are rejected (documented in SPEC.md).
//   * CRC-32 is a local, table-free, bitwise implementation of the standard
//     reflected polynomial (0xEDB88320); `&` is only used with the small
//     masks 1 and 0xFF, so the large-mask AND bug does not apply.
//   * Str values read from Vec elements are bound to typed locals; the
//     module performs no `==` on Str values at all.
//   * nested helpers receive the existing `&mut` reference (tar/aiff
//     precedent); only top-level builders take `&mut` locals.

module xiom.gpt

use xiom.string;

const _GPT_LBA_BYTES: Int = 512;
const _GPT_HEADER_OFF: Int = 512;
const _GPT_HEADER_MIN: Int = 92;
const _GPT_HEADER_MAX: Int = 512;
const _GPT_ENTRY_MIN: Int = 128;
const _GPT_ENTRY_MAX_COUNT: Int = 4096;
const _GPT_ENTRY_FIXED: Int = 56;
const _GPT_GUID_CHARS: Int = 32;
const _GPT_MBR_TYPE_EE: Int = 238;
const _GPT_MBR_SIG_A: Int = 85;
const _GPT_MBR_SIG_B: Int = 170;
const _GPT_U32_MAX: Int = 4294967295;

/// Parsed GPT. The scalar fields are the LBA-1 header values; the vectors
/// are the flat parallel entry columns, one element per entry slot in array
/// order (`type_guids`, `unique_guids`, `first_lbas`, `last_lbas`,
/// `attributes`, `names`). A parsed table has exactly `entry_count`
/// elements in every vector; all-zero type-GUID slots are kept (see
/// `gpt_entry_in_use`). Fields are implementation details; callers should
/// go through the free functions below.
pub type GptTable = {
  revision: Int;
  header_size: Int;
  header_crc: Int;
  reserved: Int;
  current_lba: Int;
  backup_lba: Int;
  first_usable_lba: Int;
  last_usable_lba: Int;
  disk_guid: Str;
  entries_lba: Int;
  entry_count: Int;
  entry_size: Int;
  entries_crc: Int;
  type_guids: Vec[Str];
  unique_guids: Vec[Str];
  first_lbas: Vec[Int];
  last_lbas: Vec[Int];
  attributes: Vec[Int];
  names: Vec[Str];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[GptTable, Str].
fn _ok_table(v: GptTable) -> Result[GptTable, Str] {
  return Ok(v);
}

// Err(m) for Result[GptTable, Str].
fn _err_table(m: Str) -> Result[GptTable, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Little-endian UInt32 at `off` as an Int (0..2^32-1); callers guarantee the
// bounds. Accumulated byte by byte (the xiom.bson `_read_le_int64` shape).
fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  var v: Int = 0;
  var i = 3;
  while i >= 0 {
    v = v * 256 + _byte(data, off + i);
    i = i - 1;
  }
  return v;
}

// Little-endian 64-bit field at `off` as a signed Int; callers guarantee the
// bounds. The accumulator wraps to the two's-complement bit pattern when bit
// 63 is set (Int is signed 64-bit), so such values come out negative and the
// LBA checks reject them (SPEC.md documents this).
fn _le64(data: &Vec[UInt8], off: Int) -> Int {
  var v: Int = 0;
  var i = 7;
  while i >= 0 {
    v = v * 256 + _byte(data, off + i);
    i = i - 1;
  }
  return v;
}

// Byte number `k` of `v` (0 = least significant). Arithmetic only: `& 0xFF`
// on values with bit 31 set miscompiles in v0.61.3, and this form is exact
// for negative two's-complement values too (xiom.bson precedent).
fn _byte_at(v: Int, k: Int) -> UInt8 {
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

// Append the low `size` bytes of `v` in little-endian order.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_byte_at(v, i));
    i = i + 1;
  }
}

// Overwrite the `size` bytes at `pos` with the little-endian image of `v`.
// Callers guarantee 0 <= pos and pos + size <= out.len().
fn _set_le(out: &mut Vec[UInt8], pos: Int, v: Int, size: Int) {
  var i = 0;
  while i < size {
    out[pos + i] = _byte_at(v, i);
    i = i + 1;
  }
}

// Append `count` zero bytes.
fn _push_zero(out: &mut Vec[UInt8], count: Int) {
  var i = 0;
  while i < count {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// Append the bytes of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// --------------------------------------------------
//  Internal CRC-32, GUID and name helpers
// --------------------------------------------------

// Standard CRC-32 (IEEE 802.3 / zlib / PKZIP): reflected polynomial
// 0xEDB88320, init 0xFFFFFFFF, reflected input and output, final xor
// 0xFFFFFFFF. Table-free and bitwise; `& 1` is the only AND mask. Every
// byte whose position falls in [zero_from, zero_to) is fed as zero instead
// of its stored value, which implements the UEFI rule that the HeaderCRC32
// field is not part of its own computation. The caller guarantees
// 0 <= start and start + count <= data.len().
fn _crc32_span(data: &Vec[UInt8], start: Int, count: Int, zero_from: Int, zero_to: Int) -> Int {
  var crc = 4294967295;
  var i = 0;
  while i < count {
    var b: Int = 0;
    let pos: Int = start + i;
    if pos < zero_from || pos >= zero_to {
      b = _byte(data, pos);
    }
    var reg = crc ^ b;
    var j = 0;
    while j < 8 {
      if (reg & 1) == 1 {
        reg = (reg >> 1) ^ 3988292384;
      } else {
        reg = reg >> 1;
      }
      j = j + 1;
    }
    crc = reg;
    i = i + 1;
  }
  return crc ^ 4294967295;
}

// Standard CRC-32 of the `count` bytes at `start` (no zeroing).
fn _crc32_range(data: &Vec[UInt8], start: Int, count: Int) -> Int {
  return _crc32_span(data, start, count, start, start);
}

// Standard CRC-32 of the `count` header bytes at `start`, with the 4
// HeaderCRC32 bytes (header offset 16..19) treated as zero.
fn _crc32_header(data: &Vec[UInt8], start: Int, count: Int) -> Int {
  return _crc32_span(data, start, count, start + 16, start + 20);
}

// Overwrite the 4 CRC-32 bytes at `pos` with the standard CRC-32 of the
// `count` bytes at `start` (no zeroing; used for the entry-array CRC). A
// single helper computes and patches, so the mutable reference is never held
// across two borrows of the same buffer (avoids the advisory E001 warning in
// the builder).
fn _seal_crc(out: &mut Vec[UInt8], pos: Int, start: Int, count: Int) {
  let v: Int = _crc32_range(out, start, count);
  _set_le(out, pos, v, 4);
}

// Overwrite the 4 HeaderCRC32 bytes at `pos` with the standard CRC-32 of the
// `count` header bytes at `start`, zeroing the CRC field itself (the UEFI
// rule).
fn _seal_header_crc(out: &mut Vec[UInt8], pos: Int, start: Int, count: Int) {
  let v: Int = _crc32_header(out, start, count);
  _set_le(out, pos, v, 4);
}

// Numeric value of a hex digit byte (0-9, a-f, A-F); -1 otherwise.
fn _hex_value(c: Int) -> Int {
  if c >= 48 && c <= 57 { return c - 48; }
  if c >= 97 && c <= 102 { return c - 87; }
  if c >= 65 && c <= 70 { return c - 55; }
  return -1;
}

// Lowercase hex digit byte for a 0..15 value.
fn _hex_nibble(n: Int) -> UInt8 {
  if n < 10 { return (48 + n) as UInt8; }
  return (87 + n) as UInt8;
}

// True when `s` is exactly 32 hexadecimal characters (either case).
fn _guid_ok(s: Str) -> Bool {
  if s.len() != _GPT_GUID_CHARS { return false; }
  var i = 0;
  while i < _GPT_GUID_CHARS {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if _hex_value(c) < 0 { return false; }
    i = i + 1;
  }
  return true;
}

// Append the 16 raw bytes encoded by `s` (32 hex characters). Callers
// guarantee `_guid_ok(s)`.
fn _guid_push(s: Str, out: &mut Vec[UInt8]) {
  var i = 0;
  while i < _GPT_GUID_CHARS {
    let hi: Int = _hex_value((string.byte_at(s, i) as Int) & 0xFF);
    let lo: Int = _hex_value((string.byte_at(s, i + 1) as Int) & 0xFF);
    out.push((hi * 16 + lo) as UInt8);
    i = i + 2;
  }
}

// The 16 bytes at `off` as 32 lowercase hex characters (raw on-disk order,
// no byte swapping). Callers guarantee the bounds.
fn _hex_at(data: &Vec[UInt8], off: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < 16 {
    let b: Int = _byte(data, off + i);
    bytes.push(_hex_nibble(b / 16));
    bytes.push(_hex_nibble(b % 16));
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

// Decode the UTF-16LE name field in [off, end) to printable ASCII. Scanning
// stops at the first 0x0000 code unit; every code unit outside 0x20..0x7E is
// replaced with '?'. `end - off` is even (entry_size is a multiple of 8).
fn _name_at(data: &Vec[UInt8], off: Int, end: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var pos = off;
  var done = false;
  while pos + 1 < end && !done {
    let unit: Int = _byte(data, pos) + _byte(data, pos + 1) * 256;
    if unit == 0 {
      done = true;
    } elif unit >= 32 && unit <= 126 {
      bytes.push(unit as UInt8);
    } else {
      bytes.push(63 as UInt8);
    }
    pos = pos + 2;
  }
  return Str::from_utf8(bytes);
}

// True when `s` is encodable as an entry name in an entry of `entry_size`
// bytes: every byte is printable ASCII (0x20..0x7E) and the name plus a
// terminating 0x0000 code unit fit in the (entry_size - 56)-byte name field.
fn _name_ok(s: Str, entry_size: Int) -> Bool {
  let width: Int = entry_size - _GPT_ENTRY_FIXED;
  let max_chars: Int = (width - 2) / 2;
  if s.len() > max_chars { return false; }
  var i = 0;
  while i < s.len() {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if c < 32 { return false; }
    if c > 126 { return false; }
    i = i + 1;
  }
  return true;
}

// True when the eight bytes at `off` are "EFI PART".
fn _sig_ok(data: &Vec[UInt8], off: Int) -> Bool {
  if _byte(data, off) != 69 { return false; }
  if _byte(data, off + 1) != 70 { return false; }
  if _byte(data, off + 2) != 73 { return false; }
  if _byte(data, off + 3) != 32 { return false; }
  if _byte(data, off + 4) != 80 { return false; }
  if _byte(data, off + 5) != 65 { return false; }
  if _byte(data, off + 6) != 82 { return false; }
  if _byte(data, off + 7) != 84 { return false; }
  return true;
}

// Minimum length of the six parallel entry vectors (the safe maximum for
// indexing a hand-built table).
fn _entry_vec_min(t: &GptTable) -> Int {
  var n = t.type_guids.len();
  if t.unique_guids.len() < n { n = t.unique_guids.len(); }
  if t.first_lbas.len() < n { n = t.first_lbas.len(); }
  if t.last_lbas.len() < n { n = t.last_lbas.len(); }
  if t.attributes.len() < n { n = t.attributes.len(); }
  if t.names.len() < n { n = t.names.len(); }
  return n;
}

// True when all six parallel entry vectors have the same length.
fn _entry_vec_equal(t: &GptTable) -> Bool {
  let n = t.type_guids.len();
  if t.unique_guids.len() != n { return false; }
  if t.first_lbas.len() != n { return false; }
  if t.last_lbas.len() != n { return false; }
  if t.attributes.len() != n { return false; }
  if t.names.len() != n { return false; }
  return true;
}

// --------------------------------------------------
//  Public API -- protective MBR
// --------------------------------------------------

/// True when `data` starts with the documented protective MBR: the 0x55AA
/// signature at bytes 510..511, a 0xEE partition entry in slot 0 (bytes
/// 446..461) and all-zero bytes in slots 1..3. Bytes after byte 511 are not
/// inspected, so the check also succeeds on a buffer that only holds LBA 0.
/// A false result means "not the documented protective MBR shape"; it is not
/// an error channel. `gpt_parse` does not require a protective MBR.
/// Complexity: O(1).
pub fn gpt_has_protective_mbr(data: &Vec[UInt8]) -> Bool {
  if data.len() < _GPT_LBA_BYTES { return false; }
  if _byte(data, 510) != _GPT_MBR_SIG_A { return false; }
  if _byte(data, 511) != _GPT_MBR_SIG_B { return false; }
  if _byte(data, 446 + 4) != _GPT_MBR_TYPE_EE { return false; }
  var i = 1;
  while i < 4 {
    var j = 0;
    while j < 16 {
      if _byte(data, 446 + i * 16 + j) != 0 { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Public API -- CRC-32 helpers
// --------------------------------------------------

/// Standard CRC-32 of the whole buffer (reflected polynomial 0xEDB88320,
/// init 0xFFFFFFFF, final xor 0xFFFFFFFF; the xiom.crc check value for
/// "123456789" is 3421780262 and the empty buffer is 0). Complexity:
/// O(data.len()).
pub fn gpt_crc32(data: &Vec[UInt8]) -> Int {
  return _crc32_range(data, 0, data.len());
}

/// Standard CRC-32 of the `count` bytes at `start`; -1 when `start` is
/// negative, `count` is negative, or the span does not fit in `data`.
/// Complexity: O(count).
pub fn gpt_crc32_range(data: &Vec[UInt8], start: Int, count: Int) -> Int {
  if start < 0 || count < 0 { return -1; }
  if start > data.len() { return -1; }
  if count > data.len() - start { return -1; }
  return _crc32_range(data, start, count);
}

/// True when the 92..512-byte header at LBA 1 still matches its stored
/// CRC-32. The stored HeaderCRC32 field is treated as zero while the CRC is
/// recomputed (the UEFI rule: the field is not part of its own
/// computation), so this is the correct way to detect a corrupt header.
/// `gpt_parse` never computes this; call it explicitly. False when the
/// recorded header_size is outside 92..512 or the span does not fit in
/// `data`. Complexity: O(header_size).
pub fn gpt_header_crc_ok(data: &Vec[UInt8], t: &GptTable) -> Bool {
  if t.header_size < _GPT_HEADER_MIN { return false; }
  if t.header_size > _GPT_HEADER_MAX { return false; }
  if _GPT_HEADER_OFF + t.header_size > data.len() { return false; }
  return _crc32_header(data, _GPT_HEADER_OFF, t.header_size) == t.header_crc;
}

/// True when the entry array still matches its stored CRC-32. False when the
/// recorded entry count/size/LBA fields are outside the documented ranges or
/// the array does not fit in `data`. Complexity: O(entry_count *
/// entry_size).
pub fn gpt_entries_crc_ok(data: &Vec[UInt8], t: &GptTable) -> Bool {
  if t.entry_count < 1 { return false; }
  if t.entry_count > _GPT_ENTRY_MAX_COUNT { return false; }
  if t.entry_size < _GPT_ENTRY_MIN { return false; }
  if t.entry_size % 8 != 0 { return false; }
  if t.entries_lba < 1 { return false; }
  if t.entries_lba > data.len() / _GPT_LBA_BYTES { return false; }
  let off: Int = t.entries_lba * _GPT_LBA_BYTES;
  if t.entry_count > (data.len() - off) / t.entry_size { return false; }
  return _crc32_range(data, off, t.entry_count * t.entry_size) == t.entries_crc;
}

// --------------------------------------------------
//  Public API -- parsing
// --------------------------------------------------

/// Parse a GPT image.
///
/// Validation order (first failure wins): a buffer shorter than 1024 bytes
/// is Err("gpt: truncated header"); bytes 512..519 must be "EFI PART" ->
/// Err("gpt: bad signature"); header_size must be 92..512 ->
/// Err("gpt: bad header size"); the header LBA fields (current, backup,
/// first usable, last usable, entries) must be non-zero and non-negative ->
/// Err("gpt: bad LBA"); first usable must not exceed last usable ->
/// Err("gpt: bad usable range"); entry_size must be at least 128 and a
/// multiple of 8 -> Err("gpt: bad entry size"); entry_count must be 1..4096
/// -> Err("gpt: bad entry count"); the entry array must fit in the buffer ->
/// Err("gpt: truncated entries"); a negative per-entry LBA field ->
/// Err("gpt: bad LBA").
///
/// CRC-32 values are copied into the table exactly as stored: a mismatch is
/// never reported here (use `gpt_header_crc_ok` / `gpt_entries_crc_ok`).
/// All-zero type-GUID slots are parsed and kept; `gpt_entry_in_use`
/// distinguishes them. An entry array with extra buffered bytes after it is
/// accepted; bytes after the array are ignored.
///
/// Params: data - the whole disk image prefix, read only (LBA 0 onward; the
/// logical block size is 512 bytes).
/// Returns: Ok(GptTable) with one element per entry slot in each parallel
/// vector.
/// Error case: see the catalog above and SPEC.md.
/// Complexity: O(entries) plus the header.
pub fn gpt_parse(data: &Vec[UInt8]) -> Result[GptTable, Str] {
  let n = data.len();
  if n < 1024 { return _err_table("gpt: truncated header"); }
  if !_sig_ok(data, _GPT_HEADER_OFF) { return _err_table("gpt: bad signature"); }
  let revision: Int = _le32(data, _GPT_HEADER_OFF + 8);
  let header_size: Int = _le32(data, _GPT_HEADER_OFF + 12);
  if header_size < _GPT_HEADER_MIN { return _err_table("gpt: bad header size"); }
  if header_size > _GPT_HEADER_MAX { return _err_table("gpt: bad header size"); }
  // Defensive: after the 1024-byte precondition and the 92..512 range above
  // this bound always holds (it can never fire on a real call).
  if _GPT_HEADER_OFF + header_size > n { return _err_table("gpt: truncated header"); }
  let header_crc: Int = _le32(data, _GPT_HEADER_OFF + 16);
  let reserved: Int = _le32(data, _GPT_HEADER_OFF + 20);
  let current_lba: Int = _le64(data, _GPT_HEADER_OFF + 24);
  let backup_lba: Int = _le64(data, _GPT_HEADER_OFF + 32);
  let first_usable: Int = _le64(data, _GPT_HEADER_OFF + 40);
  let last_usable: Int = _le64(data, _GPT_HEADER_OFF + 48);
  let disk_guid: Str = _hex_at(data, _GPT_HEADER_OFF + 56);
  let entries_lba: Int = _le64(data, _GPT_HEADER_OFF + 72);
  let entry_count: Int = _le32(data, _GPT_HEADER_OFF + 80);
  let entry_size: Int = _le32(data, _GPT_HEADER_OFF + 84);
  let entries_crc: Int = _le32(data, _GPT_HEADER_OFF + 88);
  if current_lba <= 0 { return _err_table("gpt: bad LBA"); }
  if backup_lba <= 0 { return _err_table("gpt: bad LBA"); }
  if first_usable <= 0 { return _err_table("gpt: bad LBA"); }
  if last_usable <= 0 { return _err_table("gpt: bad LBA"); }
  if entries_lba <= 0 { return _err_table("gpt: bad LBA"); }
  if first_usable > last_usable { return _err_table("gpt: bad usable range"); }
  if entry_size < _GPT_ENTRY_MIN { return _err_table("gpt: bad entry size"); }
  if entry_size % 8 != 0 { return _err_table("gpt: bad entry size"); }
  if entry_count < 1 { return _err_table("gpt: bad entry count"); }
  if entry_count > _GPT_ENTRY_MAX_COUNT { return _err_table("gpt: bad entry count"); }
  if entries_lba > n / _GPT_LBA_BYTES { return _err_table("gpt: truncated entries"); }
  let entries_off: Int = entries_lba * _GPT_LBA_BYTES;
  let entries_bytes: Int = entry_count * entry_size;
  if entries_bytes > n - entries_off { return _err_table("gpt: truncated entries"); }
  var type_guids = Vec[Str].new();
  var unique_guids = Vec[Str].new();
  var first_lbas = Vec[Int].new();
  var last_lbas = Vec[Int].new();
  var attributes = Vec[Int].new();
  var names = Vec[Str].new();
  var e = 0;
  while e < entry_count {
    let off: Int = entries_off + e * entry_size;
    let tg: Str = _hex_at(data, off);
    let ug: Str = _hex_at(data, off + 16);
    let fl: Int = _le64(data, off + 32);
    let ll: Int = _le64(data, off + 40);
    let at: Int = _le64(data, off + 48);
    if fl < 0 { return _err_table("gpt: bad LBA"); }
    if ll < 0 { return _err_table("gpt: bad LBA"); }
    let nm: Str = _name_at(data, off + _GPT_ENTRY_FIXED, off + entry_size);
    type_guids.push(tg);
    unique_guids.push(ug);
    first_lbas.push(fl);
    last_lbas.push(ll);
    attributes.push(at);
    names.push(nm);
    e = e + 1;
  }
  let table = GptTable{
    revision: revision;
    header_size: header_size;
    header_crc: header_crc;
    reserved: reserved;
    current_lba: current_lba;
    backup_lba: backup_lba;
    first_usable_lba: first_usable;
    last_usable_lba: last_usable;
    disk_guid: disk_guid;
    entries_lba: entries_lba;
    entry_count: entry_count;
    entry_size: entry_size;
    entries_crc: entries_crc;
    type_guids: type_guids;
    unique_guids: unique_guids;
    first_lbas: first_lbas;
    last_lbas: last_lbas;
    attributes: attributes;
    names: names;
  };
  return _ok_table(table);
}

// --------------------------------------------------
//  Public API -- accessors
// --------------------------------------------------

/// Header revision field (LE32); stored raw, never validated.
/// Complexity: O(1).
pub fn gpt_revision(t: &GptTable) -> Int {
  return t.revision;
}

/// Header size field in bytes (LE32), 92..512 after a successful parse.
/// Complexity: O(1).
pub fn gpt_header_size(t: &GptTable) -> Int {
  return t.header_size;
}

/// Stored header CRC-32, raw. Complexity: O(1).
pub fn gpt_header_crc(t: &GptTable) -> Int {
  return t.header_crc;
}

/// Header reserved field (LE32), preserved as parsed. Complexity: O(1).
pub fn gpt_reserved(t: &GptTable) -> Int {
  return t.reserved;
}

/// MyLBA field: the LBA the header was read from (1 for a primary GPT).
/// Complexity: O(1).
pub fn gpt_current_lba(t: &GptTable) -> Int {
  return t.current_lba;
}

/// AlternateLBA field: the backup header LBA. No backup consistency check is
/// performed. Complexity: O(1).
pub fn gpt_backup_lba(t: &GptTable) -> Int {
  return t.backup_lba;
}

/// FirstUsableLBA field. Complexity: O(1).
pub fn gpt_first_usable_lba(t: &GptTable) -> Int {
  return t.first_usable_lba;
}

/// LastUsableLBA field. Complexity: O(1).
pub fn gpt_last_usable_lba(t: &GptTable) -> Int {
  return t.last_usable_lba;
}

/// Disk GUID as the 32 lowercase hex characters of the 16 raw bytes.
/// Complexity: O(1).
pub fn gpt_disk_guid(t: &GptTable) -> Str {
  let g: Str = t.disk_guid;
  return g;
}

/// PartitionEntryLBA field. Complexity: O(1).
pub fn gpt_entries_lba(t: &GptTable) -> Int {
  return t.entries_lba;
}

/// SizeOfPartitionEntry field in bytes (>= 128, a multiple of 8 after a
/// successful parse). Complexity: O(1).
pub fn gpt_entry_size(t: &GptTable) -> Int {
  return t.entry_size;
}

/// Stored entry-array CRC-32, raw. Complexity: O(1).
pub fn gpt_entries_crc(t: &GptTable) -> Int {
  return t.entries_crc;
}

/// Safe entry count: the minimum of the declared header count and the six
/// parallel entry vector lengths, so a hand-built table with drifted vectors
/// reports the indexing maximum. A parsed table reports the header count.
/// Complexity: O(1).
pub fn gpt_entry_count(t: &GptTable) -> Int {
  var n = t.entry_count;
  if t.type_guids.len() < n { n = t.type_guids.len(); }
  if t.unique_guids.len() < n { n = t.unique_guids.len(); }
  if t.first_lbas.len() < n { n = t.first_lbas.len(); }
  if t.last_lbas.len() < n { n = t.last_lbas.len(); }
  if t.attributes.len() < n { n = t.attributes.len(); }
  if t.names.len() < n { n = t.names.len(); }
  return n;
}

/// Type GUID of entry `i` as 32 lowercase hex characters; "" when `i` is
/// negative or out of range. The all-zero GUID marks an unused slot.
/// Complexity: O(1).
pub fn gpt_type_guid(t: &GptTable, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= t.type_guids.len() { return ""; }
  let g: Str = t.type_guids[i];
  return g;
}

/// Unique GUID of entry `i` as 32 lowercase hex characters; "" when `i` is
/// negative or out of range. Complexity: O(1).
pub fn gpt_unique_guid(t: &GptTable, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= t.unique_guids.len() { return ""; }
  let g: Str = t.unique_guids[i];
  return g;
}

/// FirstLBA of entry `i`; -1 when `i` is negative or out of range.
/// Complexity: O(1).
pub fn gpt_entry_first_lba(t: &GptTable, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= t.first_lbas.len() { return -1; }
  let v: Int = t.first_lbas[i];
  return v;
}

/// LastLBA of entry `i`; -1 when `i` is negative or out of range.
/// Complexity: O(1).
pub fn gpt_entry_last_lba(t: &GptTable, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= t.last_lbas.len() { return -1; }
  let v: Int = t.last_lbas[i];
  return v;
}

/// Attributes of entry `i` (raw 64-bit flags); 0 when `i` is negative or out
/// of range. Bit 63 set makes the value negative (documented limitation).
/// Complexity: O(1).
pub fn gpt_entry_attributes(t: &GptTable, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= t.attributes.len() { return 0; }
  let v: Int = t.attributes[i];
  return v;
}

/// Name of entry `i` decoded to printable ASCII (UTF-16LE, stop at the first
/// 0x0000, non-ASCII code units replaced with '?'); "" when `i` is negative
/// or out of range. Complexity: O(1).
pub fn gpt_entry_name(t: &GptTable, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= t.names.len() { return ""; }
  let s: Str = t.names[i];
  return s;
}

/// True when entry `i` is in use: the stored type GUID is exactly 32
/// characters and not the all-zero GUID. False when `i` is negative, out of
/// range, or the stored type GUID is malformed (not 32 characters).
/// Complexity: O(1).
pub fn gpt_entry_in_use(t: &GptTable, i: Int) -> Bool {
  if i < 0 { return false; }
  if i >= t.type_guids.len() { return false; }
  let g: Str = t.type_guids[i];
  if g.len() != _GPT_GUID_CHARS { return false; }
  var k = 0;
  while k < _GPT_GUID_CHARS {
    let c: Int = (string.byte_at(g, k) as Int) & 0xFF;
    if c != 48 { return true; }
    k = k + 1;
  }
  return false;
}

// --------------------------------------------------
//  Public API -- building
// --------------------------------------------------

/// Build a canonical primary GPT image from `t` and a disk size.
///
/// Written layout, in order: the protective MBR at LBA 0 (signature 0x55AA,
/// one 0xEE entry covering the whole disk from LBA 1), a 92-byte header at
/// LBA 1, and the entry array at LBA 2. The header's revision and disk GUID
/// are taken from `t`; header_size is 92, reserved is 0, current LBA is 1,
/// the entry LBA is 2, the entry count is `t.entry_count`, the entry size is
/// `t.entry_size`, the first usable LBA is `2 + ceil(entry_count *
/// entry_size / 512)`, the backup LBA is `total_sectors - 1` and the last
/// usable LBA is `backup_lba - 1 - ceil(entry_count * entry_size / 512)`.
/// Both CRC-32 fields are recomputed; the header CRC is computed with its
/// own 4 bytes still zero (the UEFI rule), then patched. The first `n` slots come from the six
/// parallel entry vectors (`n` is their common length); the remaining slots
/// `t.entry_count - n` are written as all-zero 128-byte-shaped slots.
/// The image contains only the primary GPT: `backup_lba` is written into the
/// header but no backup header/array is emitted, and the result is not
/// padded to `total_sectors` (non-goal).
///
/// Params: t - header and entry source, read only; total_sectors - the disk
/// size in 512-byte sectors, used for the backup and last-usable LBAs.
/// Returns: Ok(bytes) of length 1024 + entry_count * entry_size.
/// Error case: Err("gpt: bad revision") when revision is outside 0..2^32-1;
/// Err("gpt: bad entry size") when entry_size is outside 128..2^32-1 or not
/// a multiple of 8; Err("gpt: bad entry count") when entry_count is outside
/// 1..4096; Err("gpt: entry vector mismatch") when the six entry vectors
/// differ in length; Err("gpt: entry count too small") when entry_count is
/// smaller than the common vector length; Err("gpt: bad guid") for a GUID
/// that is not exactly 32 hex characters; Err("gpt: bad entry LBA") for a
/// negative entry LBA or first > last; Err("gpt: bad entry name") for a name
/// outside printable ASCII or without room for its NUL; Err("gpt: disk too
/// small") when total_sectors cannot hold the primary array plus the backup
/// region.
/// Complexity: O(entry_count * entry_size).
pub fn gpt_build(t: &GptTable, total_sectors: Int) -> Result[Vec[UInt8], Str] {
  if t.revision < 0 { return _err_bytes("gpt: bad revision"); }
  if t.revision > _GPT_U32_MAX { return _err_bytes("gpt: bad revision"); }
  if t.entry_size < _GPT_ENTRY_MIN { return _err_bytes("gpt: bad entry size"); }
  if t.entry_size > _GPT_U32_MAX { return _err_bytes("gpt: bad entry size"); }
  if t.entry_size % 8 != 0 { return _err_bytes("gpt: bad entry size"); }
  if t.entry_count < 1 { return _err_bytes("gpt: bad entry count"); }
  if t.entry_count > _GPT_ENTRY_MAX_COUNT { return _err_bytes("gpt: bad entry count"); }
  if !_entry_vec_equal(t) { return _err_bytes("gpt: entry vector mismatch"); }
  let used: Int = _entry_vec_min(t);
  if t.entry_count < used { return _err_bytes("gpt: entry count too small"); }
  if !_guid_ok(t.disk_guid) { return _err_bytes("gpt: bad guid"); }
  var i = 0;
  while i < used {
    let tg: Str = t.type_guids[i];
    if !_guid_ok(tg) { return _err_bytes("gpt: bad guid"); }
    let ug: Str = t.unique_guids[i];
    if !_guid_ok(ug) { return _err_bytes("gpt: bad guid"); }
    let fl: Int = t.first_lbas[i];
    let ll: Int = t.last_lbas[i];
    if fl < 0 { return _err_bytes("gpt: bad entry LBA"); }
    if ll < 0 { return _err_bytes("gpt: bad entry LBA"); }
    if fl > ll { return _err_bytes("gpt: bad entry LBA"); }
    let nm: Str = t.names[i];
    if !_name_ok(nm, t.entry_size) { return _err_bytes("gpt: bad entry name"); }
    i = i + 1;
  }
  if total_sectors <= 0 { return _err_bytes("gpt: disk too small"); }
  let entry_bytes: Int = t.entry_count * t.entry_size;
  var entry_sectors: Int = entry_bytes / _GPT_LBA_BYTES;
  if entry_bytes % _GPT_LBA_BYTES != 0 { entry_sectors = entry_sectors + 1; }
  let first_usable: Int = 2 + entry_sectors;
  let backup_lba: Int = total_sectors - 1;
  let last_usable: Int = backup_lba - 1 - entry_sectors;
  if last_usable < first_usable { return _err_bytes("gpt: disk too small"); }
  var guid = Vec[UInt8].new();
  _guid_push(t.disk_guid, &mut guid);
  var out = Vec[UInt8].new();
  _push_zero(&mut out, 446);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(2 as UInt8);
  out.push(0 as UInt8);
  out.push(_GPT_MBR_TYPE_EE as UInt8);
  out.push(255 as UInt8);
  out.push(255 as UInt8);
  out.push(255 as UInt8);
  _push_le(&mut out, 1, 4);
  var mbr_sectors: Int = backup_lba;
  if mbr_sectors > _GPT_U32_MAX { mbr_sectors = _GPT_U32_MAX; }
  _push_le(&mut out, mbr_sectors, 4);
  _push_zero(&mut out, 48);
  out.push(_GPT_MBR_SIG_A as UInt8);
  out.push(_GPT_MBR_SIG_B as UInt8);
  out.push(69 as UInt8);
  out.push(70 as UInt8);
  out.push(73 as UInt8);
  out.push(32 as UInt8);
  out.push(80 as UInt8);
  out.push(65 as UInt8);
  out.push(82 as UInt8);
  out.push(84 as UInt8);
  _push_le(&mut out, t.revision, 4);
  _push_le(&mut out, _GPT_HEADER_MIN, 4);
  _push_le(&mut out, 0, 4);
  _push_le(&mut out, 0, 4);
  _push_le(&mut out, 1, 8);
  _push_le(&mut out, backup_lba, 8);
  _push_le(&mut out, first_usable, 8);
  _push_le(&mut out, last_usable, 8);
  _push_bytes(&mut out, &guid);
  _push_le(&mut out, 2, 8);
  _push_le(&mut out, t.entry_count, 4);
  _push_le(&mut out, t.entry_size, 4);
  _push_le(&mut out, 0, 4);
  _push_zero(&mut out, 1024 - out.len());
  var e = 0;
  while e < t.entry_count {
    let slot_start: Int = out.len();
    if e < used {
      let tg2: Str = t.type_guids[e];
      _guid_push(tg2, &mut out);
      let ug2: Str = t.unique_guids[e];
      _guid_push(ug2, &mut out);
      let fl2: Int = t.first_lbas[e];
      let ll2: Int = t.last_lbas[e];
      _push_le(&mut out, fl2, 8);
      _push_le(&mut out, ll2, 8);
      let at2: Int = t.attributes[e];
      _push_le(&mut out, at2, 8);
      let nm2: Str = t.names[e];
      var k = 0;
      while k < nm2.len() {
        out.push(string.byte_at(nm2, k));
        out.push(0 as UInt8);
        k = k + 1;
      }
    }
    let filled: Int = out.len() - slot_start;
    _push_zero(&mut out, t.entry_size - filled);
    e = e + 1;
  }
  _seal_crc(&mut out, _GPT_HEADER_OFF + 88, 1024, entry_bytes);
  _seal_header_crc(&mut out, _GPT_HEADER_OFF + 16, _GPT_HEADER_OFF, _GPT_HEADER_MIN);
  return _ok_bytes(out);
}
