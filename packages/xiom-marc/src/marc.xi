// XIOM -- xiom.marc: MARC21 ISO 2709 record codec (parse and build)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of a MARC21 ISO 2709
// bibliographic record codec. Scope: the 24-byte leader, the 12-byte
// directory entries terminated by 0x1E, the variable fields terminated by
// 0x1E inside the data area, the 0x1D record terminator at
// record_length - 1, and the 0x1F + one-byte-code subfield markers. The
// exact layout, validation order and error catalog are pinned in SPEC.md.
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - A record is leader (24 bytes) + directory (12 bytes per field plus the
//   0x1E terminator) + data area (variable fields, each ending in 0x1E) +
//   the 0x1D record terminator. The base address in the leader is the
//   absolute offset of the first byte of the data area and also marks the
//   directory end.
// - marc_parse validates the leader numerics, the entry map "4500", the
//   indicator/subfield-code counts, the base address against the directory
//   size, every terminator byte, the directory digit fields and the field
//   spans, then returns a MarcRecord of flat parallel vectors: one element
//   per field for tags/field_data/field_offsets/field_spans/sub_offsets/
//   sub_counts and one element per subfield for sub_codes/sub_values. No
//   Vec of structs is used.
// - The bytes before the first 0x1F of a field are the field data (for a
//   MARC data field the first two of those bytes are the indicator
//   positions); every 0x1F starts a one-byte code followed by the value
//   bytes up to the next 0x1F or the field terminator. Tag semantics are
//   not interpreted.
// - marc_build recomputes the record length, the base address and every
//   directory entry (field length and starting position) and always writes
//   "22" and "4500" in the leader; the pass-through leader bytes come from
//   the template.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the leaf helpers below.
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`.
//   * Str values read from Vec[Str] fields are bound to typed locals and
//     compared with string.str_compare, never `==`.
//   * accessors verify the parallel vectors are intact before indexing
//     them, so a hand-built MarcRecord with drifted vectors cannot read out
//     of bounds.

module xiom.marc

use xiom.string;

const _MARC_LEADER_LEN: Int = 24;
const _MARC_DIR_ENTRY_LEN: Int = 12;
const _MARC_RECORD_TERMINATOR: Int = 29;
const _MARC_FIELD_TERMINATOR: Int = 30;
const _MARC_SUBFIELD: Int = 31;
const _MARC_DIGIT_2: Int = 50;
const _MARC_MIN_RECORD_LEN: Int = 26;
const _MARC_MIN_BASE: Int = 25;
const _MARC_MAX_RECORD_LEN: Int = 99999;
const _MARC_MAX_FIELD_LEN: Int = 9999;

/// Parsed MARC21 record.
///
/// The scalar fields are the leader values (byte values 0..255, except
/// `entry_map`, which is the 4-byte entry map text). The vectors are the
/// flat parallel field columns (`tags`, `field_data`, `field_offsets`,
/// `field_spans`, `sub_offsets`, `sub_counts`) plus the flat subfield
/// columns (`sub_codes`, `sub_values`). `field_offsets` are absolute
/// indices into the buffer passed to `marc_parse`; `field_spans` include
/// the trailing 0x1E field terminator; `sub_offsets[i]` is the index of
/// field `i`'s first subfield in `sub_codes`/`sub_values` and
/// `sub_counts[i]` is how many it has. Vectors are one push per iteration,
/// so a parsed record always has intact parallel vectors.
pub type MarcRecord = {
  record_length: Int;
  record_status: Int;
  record_type: Int;
  bib_level: Int;
  type_of_control: Int;
  char_coding: Int;
  indicator_count: Int;
  subfield_code_count: Int;
  base_address: Int;
  encoding_level: Int;
  cataloging_form: Int;
  multipart_level: Int;
  entry_map: Str;
  tags: Vec[Str];
  field_data: Vec[Str];
  field_offsets: Vec[Int];
  field_spans: Vec[Int];
  sub_offsets: Vec[Int];
  sub_counts: Vec[Int];
  sub_codes: Vec[Int];
  sub_values: Vec[Str];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[MarcRecord, Str].
fn _ok_record(v: MarcRecord) -> Result[MarcRecord, Str] {
  return Ok(v);
}

// Err(m) for Result[MarcRecord, Str].
fn _err_record(m: Str) -> Result[MarcRecord, Str] {
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

// True when the `count` bytes at `off` are all ASCII digits (0x30..0x39);
// callers guarantee `off + count <= data.len()`.
fn _digits_ok(data: &Vec[UInt8], off: Int, count: Int) -> Bool {
  var i = 0;
  while i < count {
    let c: Int = _byte(data, off + i);
    if c < 48 || c > 57 { return false; }
    i = i + 1;
  }
  return true;
}

// Value of the `count` ASCII-digit bytes at `off` as an Int; callers
// guarantee the digits are valid.
fn _digits_val(data: &Vec[UInt8], off: Int, count: Int) -> Int {
  var v = 0;
  var i = 0;
  while i < count {
    v = v * 10 + (_byte(data, off + i) - 48);
    i = i + 1;
  }
  return v;
}

// Copy `count` bytes at `off` into a fresh Str.
fn _slice_str(data: &Vec[UInt8], off: Int, count: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < count {
    bytes.push(data[off + i]);
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

// True when `s` is exactly three ASCII digits (a valid MARC tag).
fn _tag_str_ok(s: Str) -> Bool {
  if s.len() != 3 { return false; }
  var i = 0;
  while i < 3 {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if c < 48 || c > 57 { return false; }
    i = i + 1;
  }
  return true;
}

// True when `s` contains a MARC delimiter byte: 0x1D record terminator,
// 0x1E field terminator or 0x1F subfield delimiter. Builders reject these
// in field data and subfield values; subfield codes reject them too.
fn _has_delim(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if c == _MARC_RECORD_TERMINATOR { return true; }
    if c == _MARC_FIELD_TERMINATOR { return true; }
    if c == _MARC_SUBFIELD { return true; }
    i = i + 1;
  }
  return false;
}

// Append `v` as exactly `width` ASCII digits (zero padded); callers
// guarantee 0 <= v < 10^width.
fn _push_uint(out: &mut Vec[UInt8], v: Int, width: Int) {
  var div = 1;
  var i = 1;
  while i < width {
    div = div * 10;
    i = i + 1;
  }
  i = 0;
  while i < width {
    out.push((((v / div) % 10) + 48) as UInt8);
    div = div / 10;
    i = i + 1;
  }
}

// Append the bytes of `s`.
fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// --------------------------------------------------
//  Public API -- parsing and accessors
// --------------------------------------------------

/// Parse one MARC21 record from an ISO 2709 buffer.
///
/// Validation order (first failure wins): a buffer shorter than 24 bytes ->
/// Err("marc: truncated leader"); leader 0..4 must be five ASCII digits and
/// the value at least 26 -> Err("marc: bad record length"); the value must
/// not exceed `data.len()` -> Err("marc: truncated record") (bytes after
/// record_length are ignored); leader 10 must be '2' ->
/// Err("marc: unsupported indicator count"); leader 11 must be '2' ->
/// Err("marc: unsupported subfield code count"); leader 12..16 must be five
/// ASCII digits, at least 25 and at most record_length - 1 ->
/// Err("marc: bad base address"); (base_address - 25) % 12 must be 0 ->
/// Err("marc: bad directory size"); leader 20..23 must be "4500" ->
/// Err("marc: unsupported entry map"); the byte at base_address - 1 must be
/// 0x1E -> Err("marc: missing directory terminator"); the byte at
/// record_length - 1 must be 0x1D -> Err("marc: missing record terminator").
/// Then, per directory entry in order: tag/length/start must be ASCII digits
/// -> Err("marc: bad directory entry"); field length at least 1 ->
/// Err("marc: bad field length"); start + length within the data area ->
/// Err("marc: field out of range"); the last field byte must be 0x1E ->
/// Err("marc: missing field terminator"); a 0x1F with no following code
/// byte -> Err("marc: missing subfield code").
///
/// Params: data - the record buffer, read only.
/// Returns: Ok(MarcRecord) whose field/subfield vectors are flat and
/// parallel; field_offsets are absolute indices into `data`.
/// Error case: see the catalog above and SPEC.md.
/// Complexity: O(data bytes).
pub fn marc_parse(data: &Vec[UInt8]) -> Result[MarcRecord, Str] {
  let n = data.len();
  if n < _MARC_LEADER_LEN { return _err_record("marc: truncated leader"); }
  if !_digits_ok(data, 0, 5) { return _err_record("marc: bad record length"); }
  let record_length: Int = _digits_val(data, 0, 5);
  if record_length < _MARC_MIN_RECORD_LEN { return _err_record("marc: bad record length"); }
  if record_length > n { return _err_record("marc: truncated record"); }
  let indicator_count: Int = _byte(data, 10);
  if indicator_count != _MARC_DIGIT_2 { return _err_record("marc: unsupported indicator count"); }
  let subfield_code_count: Int = _byte(data, 11);
  if subfield_code_count != _MARC_DIGIT_2 { return _err_record("marc: unsupported subfield code count"); }
  if !_digits_ok(data, 12, 5) { return _err_record("marc: bad base address"); }
  let base_address: Int = _digits_val(data, 12, 5);
  if base_address < _MARC_MIN_BASE { return _err_record("marc: bad base address"); }
  if base_address > record_length - 1 { return _err_record("marc: bad base address"); }
  if (base_address - _MARC_MIN_BASE) % _MARC_DIR_ENTRY_LEN != 0 { return _err_record("marc: bad directory size"); }
  let entry_map: Str = _slice_str(data, 20, 4);
  if string.str_compare(entry_map, "4500") != 0 { return _err_record("marc: unsupported entry map"); }
  if _byte(data, base_address - 1) != _MARC_FIELD_TERMINATOR { return _err_record("marc: missing directory terminator"); }
  if _byte(data, record_length - 1) != _MARC_RECORD_TERMINATOR { return _err_record("marc: missing record terminator"); }
  let data_area: Int = record_length - 1 - base_address;
  let count: Int = (base_address - _MARC_MIN_BASE) / _MARC_DIR_ENTRY_LEN;
  var tags = Vec[Str].new();
  var field_data = Vec[Str].new();
  var field_offsets = Vec[Int].new();
  var field_spans = Vec[Int].new();
  var sub_offsets = Vec[Int].new();
  var sub_counts = Vec[Int].new();
  var sub_codes = Vec[Int].new();
  var sub_values = Vec[Str].new();
  var i = 0;
  while i < count {
    let eoff: Int = _MARC_LEADER_LEN + i * _MARC_DIR_ENTRY_LEN;
    if !_digits_ok(data, eoff, 3) { return _err_record("marc: bad directory entry"); }
    if !_digits_ok(data, eoff + 3, 4) { return _err_record("marc: bad directory entry"); }
    if !_digits_ok(data, eoff + 7, 5) { return _err_record("marc: bad directory entry"); }
    let field_len: Int = _digits_val(data, eoff + 3, 4);
    let field_start: Int = _digits_val(data, eoff + 7, 5);
    if field_len < 1 { return _err_record("marc: bad field length"); }
    if field_start + field_len > data_area { return _err_record("marc: field out of range"); }
    let abs: Int = base_address + field_start;
    if _byte(data, abs + field_len - 1) != _MARC_FIELD_TERMINATOR { return _err_record("marc: missing field terminator"); }
    let payload_len: Int = field_len - 1;
    var j = 0;
    var prefix = Vec[UInt8].new();
    var scanning = true;
    while j < payload_len && scanning {
      let b: Int = _byte(data, abs + j);
      if b == _MARC_SUBFIELD {
        scanning = false;
      } else {
        prefix.push(b as UInt8);
        j = j + 1;
      }
    }
    let sub_start: Int = sub_codes.len();
    var sub_count = 0;
    while j < payload_len {
      j = j + 1;
      if j >= payload_len { return _err_record("marc: missing subfield code"); }
      let code: Int = _byte(data, abs + j);
      j = j + 1;
      var value = Vec[UInt8].new();
      var in_value = true;
      while j < payload_len && in_value {
        let vb: Int = _byte(data, abs + j);
        if vb == _MARC_SUBFIELD {
          in_value = false;
        } else {
          value.push(vb as UInt8);
          j = j + 1;
        }
      }
      sub_codes.push(code);
      sub_values.push(Str::from_utf8(value));
      sub_count = sub_count + 1;
    }
    tags.push(_slice_str(data, eoff, 3));
    field_data.push(Str::from_utf8(prefix));
    field_offsets.push(abs);
    field_spans.push(field_len);
    sub_offsets.push(sub_start);
    sub_counts.push(sub_count);
    i = i + 1;
  }
  let rec = MarcRecord{
    record_length: record_length;
    record_status: _byte(data, 5);
    record_type: _byte(data, 6);
    bib_level: _byte(data, 7);
    type_of_control: _byte(data, 8);
    char_coding: _byte(data, 9);
    indicator_count: indicator_count;
    subfield_code_count: subfield_code_count;
    base_address: base_address;
    encoding_level: _byte(data, 17);
    cataloging_form: _byte(data, 18);
    multipart_level: _byte(data, 19);
    entry_map: entry_map;
    tags: tags;
    field_data: field_data;
    field_offsets: field_offsets;
    field_spans: field_spans;
    sub_offsets: sub_offsets;
    sub_counts: sub_counts;
    sub_codes: sub_codes;
    sub_values: sub_values;
  };
  return _ok_record(rec);
}

/// Record length field of the leader (bytes 0..4). Complexity: O(1).
pub fn marc_record_length(t: &MarcRecord) -> Int {
  return t.record_length;
}

/// Record status byte (leader 5), stored verbatim. Complexity: O(1).
pub fn marc_record_status(t: &MarcRecord) -> Int {
  return t.record_status;
}

/// Type of record byte (leader 6), stored verbatim. Complexity: O(1).
pub fn marc_record_type(t: &MarcRecord) -> Int {
  return t.record_type;
}

/// Bibliographic level byte (leader 7), stored verbatim. Complexity: O(1).
pub fn marc_bib_level(t: &MarcRecord) -> Int {
  return t.bib_level;
}

/// Type of control byte (leader 8), stored verbatim. Complexity: O(1).
pub fn marc_type_of_control(t: &MarcRecord) -> Int {
  return t.type_of_control;
}

/// Character coding scheme byte (leader 9), stored verbatim.
/// Complexity: O(1).
pub fn marc_char_coding(t: &MarcRecord) -> Int {
  return t.char_coding;
}

/// Indicator count byte (leader 10); a parsed record pins it to '2' (50).
/// Complexity: O(1).
pub fn marc_indicator_count(t: &MarcRecord) -> Int {
  return t.indicator_count;
}

/// Subfield code count byte (leader 11); a parsed record pins it to '2'
/// (50). Complexity: O(1).
pub fn marc_subfield_code_count(t: &MarcRecord) -> Int {
  return t.subfield_code_count;
}

/// Base address of data (leader 12..16): the absolute offset of the first
/// data-area byte. Complexity: O(1).
pub fn marc_base_address(t: &MarcRecord) -> Int {
  return t.base_address;
}

/// Encoding level byte (leader 17), stored verbatim. Complexity: O(1).
pub fn marc_encoding_level(t: &MarcRecord) -> Int {
  return t.encoding_level;
}

/// Descriptive cataloging form byte (leader 18), stored verbatim.
/// Complexity: O(1).
pub fn marc_cataloging_form(t: &MarcRecord) -> Int {
  return t.cataloging_form;
}

/// Multipart resource record level byte (leader 19), stored verbatim.
/// Complexity: O(1).
pub fn marc_multipart_level(t: &MarcRecord) -> Int {
  return t.multipart_level;
}

/// Entry map text (leader 20..23); a parsed record always reports "4500".
/// Complexity: O(1).
pub fn marc_entry_map(t: &MarcRecord) -> Str {
  let map: Str = t.entry_map;
  return map;
}

/// Number of variable fields, computed as the minimum length of the six
/// parallel field vectors so a hand-built record with drifted vectors
/// reports the safe maximum. Complexity: O(1).
pub fn marc_field_count(t: &MarcRecord) -> Int {
  var n = t.tags.len();
  if t.field_data.len() < n { n = t.field_data.len(); }
  if t.field_offsets.len() < n { n = t.field_offsets.len(); }
  if t.field_spans.len() < n { n = t.field_spans.len(); }
  if t.sub_offsets.len() < n { n = t.sub_offsets.len(); }
  if t.sub_counts.len() < n { n = t.sub_counts.len(); }
  return n;
}

/// Three-digit tag of field `i`; "" when `i` is negative or out of range.
/// Complexity: O(1).
pub fn marc_tag(t: &MarcRecord, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= marc_field_count(t) { return ""; }
  let tag: Str = t.tags[i];
  return tag;
}

/// Field data of field `i`: the bytes before its first 0x1F, with the two
/// indicator bytes first for a MARC data field. "" when `i` is negative or
/// out of range. Complexity: O(1).
pub fn marc_field_data(t: &MarcRecord, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= marc_field_count(t) { return ""; }
  let data: Str = t.field_data[i];
  return data;
}

/// Absolute offset of field `i` in the buffer passed to `marc_parse`; -1
/// when `i` is negative or out of range. Complexity: O(1).
pub fn marc_field_offset(t: &MarcRecord, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= marc_field_count(t) { return -1; }
  let off: Int = t.field_offsets[i];
  return off;
}

/// Byte span of field `i`, including its trailing 0x1E terminator; 0 when
/// `i` is negative or out of range. Complexity: O(1).
pub fn marc_field_span(t: &MarcRecord, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= marc_field_count(t) { return 0; }
  let span: Int = t.field_spans[i];
  return span;
}

/// Number of subfields of field `i`; 0 when `i` is negative or out of
/// range. The count is clamped to what the flat subfield vectors actually
/// hold, so a hand-built record with drifted vectors stays in bounds.
/// Complexity: O(1).
pub fn marc_subfield_count(t: &MarcRecord, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= marc_field_count(t) { return 0; }
  let start: Int = t.sub_offsets[i];
  if start < 0 { return 0; }
  var c: Int = t.sub_counts[i];
  if c < 0 { return 0; }
  if start + c > t.sub_codes.len() { c = t.sub_codes.len() - start; }
  if start + c > t.sub_values.len() { c = t.sub_values.len() - start; }
  if c < 0 { return 0; }
  return c;
}

/// One-byte subfield code of subfield `j` of field `i`, as a byte value
/// 0..255; 0 when `i` or `j` is negative or out of range.
/// Complexity: O(1).
pub fn marc_subfield_code(t: &MarcRecord, i: Int, j: Int) -> Int {
  if j < 0 { return 0; }
  if j >= marc_subfield_count(t, i) { return 0; }
  let start: Int = t.sub_offsets[i];
  let code: Int = t.sub_codes[start + j];
  return code;
}

/// Value text of subfield `j` of field `i` (the bytes between the code byte
/// and the next 0x1F or the field terminator); "" when `i` or `j` is
/// negative or out of range. An empty subfield value yields "".
/// Complexity: O(1) (the value was copied at parse time).
pub fn marc_subfield_value(t: &MarcRecord, i: Int, j: Int) -> Str {
  if j < 0 { return ""; }
  if j >= marc_subfield_count(t, i) { return ""; }
  let start: Int = t.sub_offsets[i];
  let value: Str = t.sub_values[start + j];
  return value;
}

/// Value of the first subfield of field `i` whose code byte equals `code`;
/// "" when the field has no such subfield, or when `i` is negative or out
/// of range. First match wins when a code repeats, and the returned value
/// is the text stored at parse time (empty for an empty subfield).
/// Complexity: O(subfields of field i).
pub fn marc_subfield_value_by_code(t: &MarcRecord, i: Int, code: Int) -> Str {
  let count = marc_subfield_count(t, i);
  var j = 0;
  while j < count {
    if marc_subfield_code(t, i, j) == code {
      return marc_subfield_value(t, i, j);
    }
    j = j + 1;
  }
  return "";
}

// --------------------------------------------------
//  Public API -- building
// --------------------------------------------------

/// Build one MARC21 record from a leader template and flat field/subfield
/// columns.
///
/// The pass-through leader bytes (5..9, 17..19) come from `template` and
/// must each be 0..255; `record_length`, `base_address`,
/// `indicator_count`, `subfield_code_count` and `entry_map` of `template`
/// are ignored and recomputed: the leader always gets "22" at 10/11,
/// "4500" at 20..23 and a recomputed record length and base address. Field
/// `i` gets tag `tags[i]`, field data `field_data[i]` (which must contain
/// no 0x1D/0x1E/0x1F) and `sub_counts[i]` subfields taken in order from the
/// flat `sub_codes`/`sub_values` columns (codes are single bytes 1..255,
/// values must contain no 0x1D/0x1E/0x1F). Every field is written
/// contiguously in directory order, each closed by 0x1E, and the record is
/// closed by 0x1D.
///
/// Params: template - the leader source, read only; tags - three-digit tags,
/// read only; field_data - per-field prefix text, read only; sub_counts -
/// per-field subfield counts, read only; sub_codes - flat code bytes, read
/// only; sub_values - flat value texts, read only.
/// Returns: Ok(bytes) of the complete record.
/// Error case: Err("marc: bad leader byte") when a template leader byte is
/// outside 0..255; Err("marc: field count mismatch") when the field vectors
/// differ in length or a count is negative; Err("marc: subfield count
/// mismatch") when the counts do not sum to the flat columns; Err("marc:
/// too many fields") when 25 + 12 * fields exceeds 99999; Err("marc: bad
/// tag") when a tag is not three ASCII digits; Err("marc: bad field data"),
/// Err("marc: bad subfield code"), Err("marc: bad subfield value"); Err
/// ("marc: field too long") when a field exceeds 9999 bytes; Err("marc:
/// record too long") when the record exceeds 99999 bytes.
/// Complexity: O(fields + subfields + output bytes).
pub fn marc_build(template: &MarcRecord, tags: &Vec[Str], field_data: &Vec[Str], sub_counts: &Vec[Int], sub_codes: &Vec[Int], sub_values: &Vec[Str]) -> Result[Vec[UInt8], Str] {
  if template.record_status < 0 || template.record_status > 255 { return _err_bytes("marc: bad leader byte"); }
  if template.record_type < 0 || template.record_type > 255 { return _err_bytes("marc: bad leader byte"); }
  if template.bib_level < 0 || template.bib_level > 255 { return _err_bytes("marc: bad leader byte"); }
  if template.type_of_control < 0 || template.type_of_control > 255 { return _err_bytes("marc: bad leader byte"); }
  if template.char_coding < 0 || template.char_coding > 255 { return _err_bytes("marc: bad leader byte"); }
  if template.encoding_level < 0 || template.encoding_level > 255 { return _err_bytes("marc: bad leader byte"); }
  if template.cataloging_form < 0 || template.cataloging_form > 255 { return _err_bytes("marc: bad leader byte"); }
  if template.multipart_level < 0 || template.multipart_level > 255 { return _err_bytes("marc: bad leader byte"); }
  let n = tags.len();
  if field_data.len() != n { return _err_bytes("marc: field count mismatch"); }
  if sub_counts.len() != n { return _err_bytes("marc: field count mismatch"); }
  var total_subs = 0;
  var i = 0;
  while i < n {
    let c: Int = sub_counts[i];
    if c < 0 { return _err_bytes("marc: field count mismatch"); }
    total_subs = total_subs + c;
    i = i + 1;
  }
  if sub_codes.len() != total_subs { return _err_bytes("marc: subfield count mismatch"); }
  if sub_values.len() != total_subs { return _err_bytes("marc: subfield count mismatch"); }
  let base_address = _MARC_MIN_BASE + n * _MARC_DIR_ENTRY_LEN;
  if base_address > _MARC_MAX_RECORD_LEN { return _err_bytes("marc: too many fields"); }
  var field_lens = Vec[Int].new();
  var sum_lens = 0;
  var sub_cursor = 0;
  i = 0;
  while i < n {
    let tag: Str = tags[i];
    if !_tag_str_ok(tag) { return _err_bytes("marc: bad tag"); }
    let fdata: Str = field_data[i];
    if _has_delim(fdata) { return _err_bytes("marc: bad field data"); }
    var field_len = fdata.len() + 1;
    let scount: Int = sub_counts[i];
    var j = 0;
    while j < scount {
      let code: Int = sub_codes[sub_cursor + j];
      if code < 1 || code > 255 { return _err_bytes("marc: bad subfield code"); }
      if code == _MARC_RECORD_TERMINATOR { return _err_bytes("marc: bad subfield code"); }
      if code == _MARC_FIELD_TERMINATOR { return _err_bytes("marc: bad subfield code"); }
      if code == _MARC_SUBFIELD { return _err_bytes("marc: bad subfield code"); }
      let value: Str = sub_values[sub_cursor + j];
      if _has_delim(value) { return _err_bytes("marc: bad subfield value"); }
      field_len = field_len + 2 + value.len();
      j = j + 1;
    }
    if field_len > _MARC_MAX_FIELD_LEN { return _err_bytes("marc: field too long"); }
    field_lens.push(field_len);
    sum_lens = sum_lens + field_len;
    sub_cursor = sub_cursor + scount;
    i = i + 1;
  }
  let record_length = base_address + sum_lens + 1;
  if record_length > _MARC_MAX_RECORD_LEN { return _err_bytes("marc: record too long"); }
  var out = Vec[UInt8].new();
  _push_uint(&mut out, record_length, 5);
  out.push(template.record_status as UInt8);
  out.push(template.record_type as UInt8);
  out.push(template.bib_level as UInt8);
  out.push(template.type_of_control as UInt8);
  out.push(template.char_coding as UInt8);
  out.push(_MARC_DIGIT_2 as UInt8);
  out.push(_MARC_DIGIT_2 as UInt8);
  _push_uint(&mut out, base_address, 5);
  out.push(template.encoding_level as UInt8);
  out.push(template.cataloging_form as UInt8);
  out.push(template.multipart_level as UInt8);
  out.push(52 as UInt8);
  out.push(53 as UInt8);
  out.push(48 as UInt8);
  out.push(48 as UInt8);
  var field_start = 0;
  i = 0;
  while i < n {
    let tag2: Str = tags[i];
    _push_str(&mut out, tag2);
    let flen: Int = field_lens[i];
    _push_uint(&mut out, flen, 4);
    _push_uint(&mut out, field_start, 5);
    field_start = field_start + flen;
    i = i + 1;
  }
  out.push(_MARC_FIELD_TERMINATOR as UInt8);
  sub_cursor = 0;
  i = 0;
  while i < n {
    let fdata2: Str = field_data[i];
    _push_str(&mut out, fdata2);
    let scount2: Int = sub_counts[i];
    var k = 0;
    while k < scount2 {
      out.push(_MARC_SUBFIELD as UInt8);
      let code2: Int = sub_codes[sub_cursor + k];
      out.push(code2 as UInt8);
      let value2: Str = sub_values[sub_cursor + k];
      _push_str(&mut out, value2);
      k = k + 1;
    }
    out.push(_MARC_FIELD_TERMINATOR as UInt8);
    sub_cursor = sub_cursor + scount2;
    i = i + 1;
  }
  out.push(_MARC_RECORD_TERMINATOR as UInt8);
  return _ok_bytes(out);
}
