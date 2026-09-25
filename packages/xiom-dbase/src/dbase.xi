// XIOM -- xiom.dbase: dBASE III/IV table header codec (parse and build)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of a dBASE table header
// codec. Scope: the 32-byte table header, the 32-byte field descriptors
// terminated by 0x0D, and the fixed-size record area of dBASE III / III+
// (.dbf) tables; the Visual FoxPro 0x30 header shape is accepted and
// documented in SPEC.md.
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - A parse validates the header, the descriptor terminator, the descriptor
//   count implied by the header size, every field name/type and the
//   record-size equation `record_size == 1 + sum(field lengths)`, then the
//   record area `header_size + record_count * record_size`.
// - The result is a DbaseTable of flat parallel vectors: one element per
//   field for names/types/lengths/decimals/addresses/offsets and one element
//   per record for record_offsets/record_spans. No Vec of structs is used.
// - Record bytes never leave the caller's buffer: record_offsets are
//   absolute indices into the data passed to dbase_parse, and the field
//   accessors copy bytes out of that buffer.
// - The first byte of every record is the deletion flag (0x20 active,
//   0x2A deleted); it is preserved in the record span and not interpreted.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the leaf helpers below
//     (constructing Result payloads inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * Str values read from Vec[Str] fields are bound to typed locals; the
//     module performs no `==` on Str values at all.
//   * accessors verify the parallel vectors are intact before indexing them,
//     so a hand-built DbaseTable with drifted vectors cannot read out of
//     bounds.

module xiom.dbase

use xiom.string;

const _DBASE_VERSION_III: Int = 3;
const _DBASE_VERSION_III_MEMO: Int = 131;
const _DBASE_VERSION_VFP: Int = 48;
const _DBASE_TERMINATOR: Int = 13;
const _DBASE_RECORD_ACTIVE: Int = 32;
const _DBASE_TYPE_C: Int = 67;
const _DBASE_TYPE_N: Int = 78;
const _DBASE_TYPE_D: Int = 68;
const _DBASE_TYPE_L: Int = 76;
const _DBASE_TYPE_M: Int = 77;
const _DBASE_TYPE_F: Int = 70;

/// Parsed dBASE table header, descriptors and record spans.
///
/// The scalar fields are the header values; the vectors are the flat
/// parallel descriptor columns (`names`, `types`, `lengths`, `decimals`,
/// `addresses`) plus the derived per-field `offsets` (byte offset of the
/// field within a record, including the 1-byte deletion flag) and the
/// per-record `record_offsets` / `record_spans` (absolute start and length
/// inside the buffer passed to `dbase_parse`). Vectors are one push per
/// iteration, so a parsed table always has intact parallel vectors.
pub type DbaseTable = {
  version: Int;
  last_update_y: Int;
  last_update_m: Int;
  last_update_d: Int;
  record_count: Int;
  header_size: Int;
  record_size: Int;
  names: Vec[Str];
  types: Vec[Int];
  lengths: Vec[Int];
  decimals: Vec[Int];
  addresses: Vec[Int];
  offsets: Vec[Int];
  record_offsets: Vec[Int];
  record_spans: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[DbaseTable, Str].
fn _ok_table(v: DbaseTable) -> Result[DbaseTable, Str] {
  return Ok(v);
}

// Err(m) for Result[DbaseTable, Str].
fn _err_table(m: Str) -> Result[DbaseTable, Str] {
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

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Little-endian UInt16 at `off` as an Int (0..65535).
fn _le16(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256;
}

// Little-endian UInt32 at `off` as an Int (0..2^32-1).
fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256 + _byte(data, off + 2) * 65536 + _byte(data, off + 3) * 16777216;
}

// Append `v` (0..65535) as two little-endian bytes.
fn _push_le16(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

// Append `v` (0..2^32-1) as four little-endian bytes.
fn _push_le32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// Append `count` zero bytes.
fn _push_zero(out: &mut Vec[UInt8], count: Int) {
  var i = 0;
  while i < count {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// True when `v` is a supported table version byte (0x03, 0x83, 0x30).
fn _version_supported(v: Int) -> Bool {
  if v == _DBASE_VERSION_III { return true; }
  if v == _DBASE_VERSION_III_MEMO { return true; }
  if v == _DBASE_VERSION_VFP { return true; }
  return false;
}

// True when `t` is a supported field type byte (C, N, D, L, M, F).
fn _type_supported(t: Int) -> Bool {
  if t == _DBASE_TYPE_C { return true; }
  if t == _DBASE_TYPE_N { return true; }
  if t == _DBASE_TYPE_D { return true; }
  if t == _DBASE_TYPE_L { return true; }
  if t == _DBASE_TYPE_M { return true; }
  if t == _DBASE_TYPE_F { return true; }
  return false;
}

// True when `c` is allowed in a field name at this position: A-Z always;
// digits and '_' only after the first character (`first` is true for the
// first character). The ASCII byte value is 0..255.
fn _name_char_ok(c: Int, first: Bool) -> Bool {
  if c >= 65 && c <= 90 { return true; }
  if first { return false; }
  if c >= 48 && c <= 57 { return true; }
  if c == 95 { return true; }
  return false;
}

// True when `s` is a valid descriptor name: 1..11 bytes, first byte A-Z,
// following bytes A-Z, 0-9 or '_'. No other byte value is accepted.
fn _name_str_ok(s: Str) -> Bool {
  let n = s.len();
  if n == 0 { return false; }
  if n > 11 { return false; }
  var i = 0;
  while i < n {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if i == 0 {
      if !_name_char_ok(c, true) { return false; }
    } else {
      if !_name_char_ok(c, false) { return false; }
    }
    i = i + 1;
  }
  return true;
}

// The 11-byte name field at `off` as a Str: bytes up to the first NUL (or
// the field end); the NUL and any following bytes are dropped.
fn _name_at(data: &Vec[UInt8], off: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  var done = false;
  while i < 11 && !done {
    let c: Int = _byte(data, off + i);
    if c == 0 {
      done = true;
    } else {
      bytes.push(c as UInt8);
    }
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

// True when the trimmed numeric text `s` is well formed: optional '+'/'-',
// one or more digits, optionally a '.' followed by one or more digits. The
// empty string, a bare sign, ".5", "5.", "1.2.3", "1e3" and any other byte
// are rejected.
fn _numeric_ok(s: Str) -> Bool {
  let n = s.len();
  var start = 0;
  if n > 0 {
    let c0: Int = (string.byte_at(s, 0) as Int) & 0xFF;
    if c0 == 45 || c0 == 43 { start = 1; }
  }
  if start >= n { return false; }
  var i = start;
  var digits = 0;
  var dots = 0;
  var dot_pos = -1;
  while i < n {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if c >= 48 && c <= 57 {
      digits = digits + 1;
    } elif c == 46 {
      dots = dots + 1;
      dot_pos = i;
    } else {
      return false;
    }
    i = i + 1;
  }
  if digits == 0 { return false; }
  if dots > 1 { return false; }
  if dots == 1 {
    if dot_pos <= start { return false; }
    if dot_pos >= n - 1 { return false; }
  }
  return true;
}

// --------------------------------------------------
//  Public API -- parsing and accessors
// --------------------------------------------------

/// Parse a dBASE table (header + descriptors + record spans).
///
/// Validation order (first failure wins): a buffer shorter than 32 bytes or
/// a header that extends past it is Err("dbase: truncated header"); the
/// version byte must be 0x03, 0x83 or 0x30 -> Err("dbase: unsupported
/// version"); header_size must be at least 33 and
/// (header_size - 33) % 32 == 0 -> Err("dbase: bad header size"); the byte
/// at header_size - 1 must be 0x0D -> Err("dbase: missing terminator");
/// every descriptor name must be 1..11 bytes with the documented charset ->
/// Err("dbase: bad field name"); every type must be C, N, D, L, M or F ->
/// Err("dbase: bad field type"); record_size must equal
/// 1 + sum(field lengths) -> Err("dbase: bad record size"); the record area
/// must hold record_count * record_size bytes -> Err("dbase: truncated
/// records"). Bytes after the record area (for example the legacy 0x1A EOF
/// mark) are ignored.
///
/// Params: data - the whole table buffer, read only.
/// Returns: Ok(DbaseTable) whose record_offsets are absolute indices into
/// `data`; the field address words are preserved as parsed.
/// Error case: see the catalog above and SPEC.md.
/// Complexity: O(data bytes + fields + records).
pub fn dbase_parse(data: &Vec[UInt8]) -> Result[DbaseTable, Str] {
  let n = data.len();
  if n < 32 { return _err_table("dbase: truncated header"); }
  let version: Int = _byte(data, 0);
  if !_version_supported(version) { return _err_table("dbase: unsupported version"); }
  let last_y: Int = _byte(data, 1);
  let last_m: Int = _byte(data, 2);
  let last_d: Int = _byte(data, 3);
  let record_count: Int = _le32(data, 4);
  let header_size: Int = _le16(data, 8);
  let record_size: Int = _le16(data, 10);
  if header_size < 33 { return _err_table("dbase: bad header size"); }
  if header_size > n { return _err_table("dbase: truncated header"); }
  let term: Int = _byte(data, header_size - 1);
  if term != _DBASE_TERMINATOR { return _err_table("dbase: missing terminator"); }
  let desc_bytes = header_size - 33;
  if desc_bytes % 32 != 0 { return _err_table("dbase: bad header size"); }
  let count = desc_bytes / 32;
  var names = Vec[Str].new();
  var types = Vec[Int].new();
  var lengths = Vec[Int].new();
  var decimals = Vec[Int].new();
  var addresses = Vec[Int].new();
  var offsets = Vec[Int].new();
  var sum = 0;
  var i = 0;
  while i < count {
    let off: Int = 32 + i * 32;
    let nm: Str = _name_at(data, off);
    if !_name_str_ok(nm) { return _err_table("dbase: bad field name"); }
    let ty: Int = _byte(data, off + 11);
    if !_type_supported(ty) { return _err_table("dbase: bad field type"); }
    let ln: Int = _byte(data, off + 16);
    let dec: Int = _byte(data, off + 17);
    names.push(nm);
    types.push(ty);
    lengths.push(ln);
    decimals.push(dec);
    addresses.push(_le32(data, off + 12));
    offsets.push(1 + sum);
    sum = sum + ln;
    i = i + 1;
  }
  if record_size != 1 + sum { return _err_table("dbase: bad record size"); }
  let need = header_size + record_count * record_size;
  if need > n { return _err_table("dbase: truncated records"); }
  var record_offsets = Vec[Int].new();
  var record_spans = Vec[Int].new();
  var r = 0;
  while r < record_count {
    record_offsets.push(header_size + r * record_size);
    record_spans.push(record_size);
    r = r + 1;
  }
  let table = DbaseTable{
    version: version;
    last_update_y: last_y;
    last_update_m: last_m;
    last_update_d: last_d;
    record_count: record_count;
    header_size: header_size;
    record_size: record_size;
    names: names;
    types: types;
    lengths: lengths;
    decimals: decimals;
    addresses: addresses;
    offsets: offsets;
    record_offsets: record_offsets;
    record_spans: record_spans;
  };
  return _ok_table(table);
}

/// Version byte of the table (0x03, 0x83 or 0x30). Complexity: O(1).
pub fn dbase_version(t: &DbaseTable) -> Int {
  return t.version;
}

/// Last-update date packed as y * 10000 + m * 100 + d, for example 260925
/// for the bytes 26 09 25 (2026-09-25). The bytes are stored, not
/// interpreted. Complexity: O(1).
pub fn dbase_last_update(t: &DbaseTable) -> Int {
  return t.last_update_y * 10000 + t.last_update_m * 100 + t.last_update_d;
}

/// Header record count field (LE32). Complexity: O(1).
pub fn dbase_record_count(t: &DbaseTable) -> Int {
  return t.record_count;
}

/// Header size field in bytes (LE16), including the 0x0D terminator.
/// Complexity: O(1).
pub fn dbase_header_size(t: &DbaseTable) -> Int {
  return t.header_size;
}

/// Record size field in bytes (LE16), including the 1-byte deletion flag.
/// Complexity: O(1).
pub fn dbase_record_size(t: &DbaseTable) -> Int {
  return t.record_size;
}

/// Number of fields, computed as the minimum length of the parallel
/// descriptor vectors so a hand-built table with drifted vectors reports the
/// safe maximum. Complexity: O(1).
pub fn dbase_field_count(t: &DbaseTable) -> Int {
  var n = t.names.len();
  if t.types.len() < n { n = t.types.len(); }
  if t.lengths.len() < n { n = t.lengths.len(); }
  if t.decimals.len() < n { n = t.decimals.len(); }
  if t.addresses.len() < n { n = t.addresses.len(); }
  if t.offsets.len() < n { n = t.offsets.len(); }
  return n;
}

/// Name of field `i`; "" when `i` is negative or out of range.
/// Complexity: O(1).
pub fn dbase_field_name(t: &DbaseTable, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= t.names.len() { return ""; }
  let name: Str = t.names[i];
  return name;
}

/// ASCII type byte of field `i` (C 67, N 78, D 68, L 76, M 77, F 70);
/// 0 when `i` is negative or out of range. Complexity: O(1).
pub fn dbase_field_type(t: &DbaseTable, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= t.types.len() { return 0; }
  let ty: Int = t.types[i];
  return ty;
}

/// Length in bytes of field `i`; 0 when `i` is negative or out of range.
/// Complexity: O(1).
pub fn dbase_field_length(t: &DbaseTable, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= t.lengths.len() { return 0; }
  let len: Int = t.lengths[i];
  return len;
}

/// Declared decimal count of field `i`; 0 when `i` is negative or out of
/// range. Complexity: O(1).
pub fn dbase_field_decimals(t: &DbaseTable, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= t.decimals.len() { return 0; }
  let dec: Int = t.decimals[i];
  return dec;
}

/// Field address word from descriptor `i` (LE32), preserved as parsed;
/// 0 when `i` is negative or out of range. dBASE III writes memory
/// addresses here, typically 0 in files. Complexity: O(1).
pub fn dbase_field_address(t: &DbaseTable, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= t.addresses.len() { return 0; }
  let addr: Int = t.addresses[i];
  return addr;
}

/// Byte offset of field `i` within a record, including the 1-byte deletion
/// flag (so the first field is at 1); 0 when `i` is negative or out of
/// range. Complexity: O(1).
pub fn dbase_field_offset(t: &DbaseTable, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= t.offsets.len() { return 0; }
  let off: Int = t.offsets[i];
  return off;
}

/// Absolute offset of record `r` in the buffer passed to `dbase_parse`;
/// -1 when `r` is negative or >= dbase_record_count. When the parsed
/// record_offsets vector is intact it is used; a hand-built table without
/// record spans falls back to header_size + r * record_size.
/// Complexity: O(1).
pub fn dbase_record_offset(t: &DbaseTable, r: Int) -> Int {
  if r < 0 { return -1; }
  if r >= t.record_count { return -1; }
  if t.record_offsets.len() == t.record_count {
    let off: Int = t.record_offsets[r];
    return off;
  }
  return t.header_size + r * t.record_size;
}

/// Byte span of record `r` (the whole record, deletion flag included);
/// 0 when `r` is negative or >= dbase_record_count. A parsed table reports
/// record_size; a hand-built table without record spans falls back to
/// record_size as well. Complexity: O(1).
pub fn dbase_record_span(t: &DbaseTable, r: Int) -> Int {
  if r < 0 { return 0; }
  if r >= t.record_count { return 0; }
  if t.record_spans.len() == t.record_count {
    let span: Int = t.record_spans[r];
    return span;
  }
  return t.record_size;
}

/// Copy the raw bytes of record `r` out of `data` (the deletion flag
/// included). Err("dbase: record out of range") when `r` is negative or
/// >= dbase_record_count; Err("dbase: truncated data") when the recorded
/// span does not fit in `data`. Complexity: O(record_size).
pub fn dbase_record_bytes(data: &Vec[UInt8], t: &DbaseTable, r: Int) -> Result[Vec[UInt8], Str] {
  let off = dbase_record_offset(t, r);
  if off < 0 { return _err_bytes("dbase: record out of range"); }
  let span = dbase_record_span(t, r);
  if span < 0 { return _err_bytes("dbase: record out of range"); }
  if off + span > data.len() {
    return _err_bytes("dbase: truncated data");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < span {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Copy the raw bytes of field `f` of record `r` out of `data`. The bytes
/// are returned verbatim (C fields keep their trailing pad spaces, N fields
/// keep their alignment spaces).
/// Err("dbase: field out of range") when `f` is negative or >=
/// dbase_field_count; Err("dbase: record out of range") when `r` is
/// negative or >= dbase_record_count; Err("dbase: truncated data") when the
/// field range does not fit in `data`. A zero-length field yields an empty
/// Ok. Complexity: O(field length).
pub fn dbase_field_bytes(data: &Vec[UInt8], t: &DbaseTable, r: Int, f: Int) -> Result[Vec[UInt8], Str] {
  if f < 0 { return _err_bytes("dbase: field out of range"); }
  if f >= dbase_field_count(t) { return _err_bytes("dbase: field out of range"); }
  let off = dbase_record_offset(t, r);
  if off < 0 { return _err_bytes("dbase: record out of range"); }
  let foff: Int = t.offsets[f];
  let flen: Int = t.lengths[f];
  if foff < 0 || flen < 0 { return _err_bytes("dbase: truncated data"); }
  if off + foff + flen > data.len() {
    return _err_bytes("dbase: truncated data");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < flen {
    out.push(data[off + foff + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Raw text of a C (character) field as a Str, padding included. The bytes
/// are not validated or trimmed; the field must exist and be of type C.
/// Params: data - the parse buffer; t - the parsed table; r - zero-based
/// record index; f - zero-based field index.
/// Returns: Ok(text) with the field bytes verbatim.
/// Error case: the dbase_field_bytes errors, plus
/// Err("dbase: field type mismatch") when field `f` is not type C.
/// Complexity: O(field length).
pub fn dbase_field_text(data: &Vec[UInt8], t: &DbaseTable, r: Int, f: Int) -> Result[Str, Str] {
  let raw = dbase_field_bytes(data, t, r, f);
  if !raw.is_ok {
    let msg: Str = raw.error;
    return _err_str(msg);
  }
  let ty = dbase_field_type(t, f);
  if ty != _DBASE_TYPE_C {
    return _err_str("dbase: field type mismatch");
  }
  let buf: Vec[UInt8] = raw.value;
  return _ok_str(Str::from_utf8(buf));
}

/// Validated numeric text of an N (numeric) field. The field bytes are
/// trimmed with xiom.string.str_trim (leading/trailing ASCII whitespace)
/// and validated as: optional '+'/'-', one or more digits, optionally a
/// '.' followed by one or more digits. The text is returned, never a
/// number, so no precision is lost or invented.
/// Params: data - the parse buffer; t - the parsed table; r - zero-based
/// record index; f - zero-based field index.
/// Returns: Ok(trimmed text) for well-formed numeric text.
/// Error case: the dbase_field_bytes errors, plus
/// Err("dbase: field type mismatch") when field `f` is not type N, plus
/// Err("dbase: bad numeric text") when the trimmed text is not well formed.
/// Complexity: O(field length).
pub fn dbase_field_number(data: &Vec[UInt8], t: &DbaseTable, r: Int, f: Int) -> Result[Str, Str] {
  let raw = dbase_field_bytes(data, t, r, f);
  if !raw.is_ok {
    let msg: Str = raw.error;
    return _err_str(msg);
  }
  let ty = dbase_field_type(t, f);
  if ty != _DBASE_TYPE_N {
    return _err_str("dbase: field type mismatch");
  }
  let buf: Vec[UInt8] = raw.value;
  let trimmed = string.str_trim(Str::from_utf8(buf));
  if !_numeric_ok(trimmed) {
    return _err_str("dbase: bad numeric text");
  }
  return _ok_str(trimmed);
}

// --------------------------------------------------
//  Public API -- building
// --------------------------------------------------

/// Build a dBASE table from descriptors and records.
///
/// The descriptors come from `t`: names/types/lengths/decimals are written
/// in order, last-update bytes as stored, and the version byte must be
/// 0x03, 0x83 or 0x30. Descriptor address words are written as 0 (the
/// canonical file form); header size, record size and record count are
/// recomputed from the descriptors and `records`, so those header fields of
/// `t` are ignored. Every record is written as active (deletion flag 0x20):
/// each cell value is emitted verbatim and space-padded to its field length;
/// cells longer than their field are rejected. No 0x1A EOF mark is emitted.
///
/// Params: t - the descriptor source, read only; records - one Vec[Str] per
/// record, each with exactly dbase_field_count(t) cells, read only.
/// Returns: Ok(bytes) of the complete table, header + descriptors + 0x0D +
/// record area.
/// Error case: Err("dbase: unsupported version"); Err("dbase: bad date")
/// when a last-update byte is outside 0..255; Err("dbase: descriptor count
/// mismatch") when the descriptor vectors have different lengths;
/// Err("dbase: bad field name"), Err("dbase: bad field type"),
/// Err("dbase: bad field length") (outside 0..255), Err("dbase: bad field
/// decimals") (outside 0..255); Err("dbase: bad header size") when
/// 32 + 32 * fields + 1 exceeds 65535; Err("dbase: bad record size") when
/// 1 + sum(lengths) exceeds 65535; Err("dbase: field count mismatch") when
/// a record has the wrong number of cells; Err("dbase: field too long")
/// when a cell exceeds its field length.
/// Complexity: O(fields + records * record_size).
pub fn dbase_build(t: &DbaseTable, records: &Vec[Vec[Str]]) -> Result[Vec[UInt8], Str] {
  if !_version_supported(t.version) { return _err_bytes("dbase: unsupported version"); }
  let y: Int = t.last_update_y;
  let m: Int = t.last_update_m;
  let d: Int = t.last_update_d;
  if y < 0 || y > 255 { return _err_bytes("dbase: bad date"); }
  if m < 0 || m > 255 { return _err_bytes("dbase: bad date"); }
  if d < 0 || d > 255 { return _err_bytes("dbase: bad date"); }
  let n = t.names.len();
  if t.types.len() != n { return _err_bytes("dbase: descriptor count mismatch"); }
  if t.lengths.len() != n { return _err_bytes("dbase: descriptor count mismatch"); }
  if t.decimals.len() != n { return _err_bytes("dbase: descriptor count mismatch"); }
  let header_size = 32 + n * 32 + 1;
  if header_size > 65535 { return _err_bytes("dbase: bad header size"); }
  var sum = 0;
  var i = 0;
  while i < n {
    let nm: Str = t.names[i];
    if !_name_str_ok(nm) { return _err_bytes("dbase: bad field name"); }
    let ty: Int = t.types[i];
    if !_type_supported(ty) { return _err_bytes("dbase: bad field type"); }
    let ln: Int = t.lengths[i];
    if ln < 0 || ln > 255 { return _err_bytes("dbase: bad field length"); }
    let dec: Int = t.decimals[i];
    if dec < 0 || dec > 255 { return _err_bytes("dbase: bad field decimals"); }
    sum = sum + ln;
    i = i + 1;
  }
  let record_size = 1 + sum;
  if record_size > 65535 { return _err_bytes("dbase: bad record size"); }
  var r = 0;
  while r < records.len() {
    let rec: Vec[Str] = records[r];
    if rec.len() != n { return _err_bytes("dbase: field count mismatch"); }
    var c = 0;
    while c < n {
      let cell: Str = rec[c];
      let flen: Int = t.lengths[c];
      if cell.len() > flen { return _err_bytes("dbase: field too long"); }
      c = c + 1;
    }
    r = r + 1;
  }
  var out = Vec[UInt8].new();
  out.push(t.version as UInt8);
  out.push(y as UInt8);
  out.push(m as UInt8);
  out.push(d as UInt8);
  _push_le32(&mut out, records.len());
  _push_le16(&mut out, header_size);
  _push_le16(&mut out, record_size);
  _push_zero(&mut out, 20);
  i = 0;
  while i < n {
    let nm2: Str = t.names[i];
    var k = 0;
    while k < 11 {
      if k < nm2.len() {
        out.push(string.byte_at(nm2, k));
      } else {
        out.push(0 as UInt8);
      }
      k = k + 1;
    }
    let ty2: Int = t.types[i];
    let ln2: Int = t.lengths[i];
    let dec2: Int = t.decimals[i];
    out.push(ty2 as UInt8);
    _push_le32(&mut out, 0);
    out.push(ln2 as UInt8);
    out.push(dec2 as UInt8);
    _push_zero(&mut out, 14);
    i = i + 1;
  }
  out.push(_DBASE_TERMINATOR as UInt8);
  r = 0;
  while r < records.len() {
    out.push(_DBASE_RECORD_ACTIVE as UInt8);
    var c2 = 0;
    while c2 < n {
      let cell2: Str = records[r][c2];
      let flen2: Int = t.lengths[c2];
      var k2 = 0;
      while k2 < cell2.len() {
        out.push(string.byte_at(cell2, k2));
        k2 = k2 + 1;
      }
      var pad = flen2 - cell2.len();
      while pad > 0 {
        out.push(32 as UInt8);
        pad = pad - 1;
      }
      c2 = c2 + 1;
    }
    r = r + 1;
  }
  return _ok_bytes(out);
}
