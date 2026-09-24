// XIOM -- xiom.tlv: generic big-endian TLV parsing and building
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.tlv placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A TLV stream is a flat sequence of entries: a `tag_size`-byte big-endian
// tag, a `length_size`-byte big-endian value length, then that many value
// bytes. tag_size and length_size are caller-chosen widths in 1..4 and are
// not carried in the stream, so the same widths used to build must be used
// to parse. tlv_parse walks entries until the buffer ends and records the
// absolute value offsets/lengths; tlv_append and tlv_build_from write the
// same layout. See SPEC.md for the layout table, error catalog and
// documented limitations (flat streams only: no nesting, no
// length-includes-header variants).
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * all big-endian byte extraction is arithmetic (modulo/division), which
//     is exact for values with bit 31 set (`& 0xFF` on such values
//     miscompiles in this compiler; see the xiom.msgpack `_be_byte`
//     precedent).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * tlv_append validates widths, tag and value size before writing a
//     single byte, so an Err leaves `out` untouched (atomic failure).

module xiom.tlv

/// Parsed TLV index. One entry per encoded entry, in stream order. The
/// value bytes stay in the source buffer and are located by
/// `value_offsets` (absolute index of the first value byte) and
/// `value_lengths`. Fields are implementation details; callers should go
/// through the free functions below.
pub type TlvList = {
  tags: Vec[Int];
  value_offsets: Vec[Int];
  value_lengths: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[TlvList, Str].
fn _ok_list(v: TlvList) -> Result[TlvList, Str] {
  return Ok(v);
}

// Err(m) for Result[TlvList, Str].
fn _err_list(m: Str) -> Result[TlvList, Str] {
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

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal width/byte helpers
// --------------------------------------------------

// True when both widths are in the supported range 1..4.
fn _widths_ok(tag_size: Int, length_size: Int) -> Bool {
  if tag_size < 1 || tag_size > 4 {
    return false;
  }
  if length_size < 1 || length_size > 4 {
    return false;
  }
  return true;
}

// The documented width error for the first invalid width (tag checked
// first). Only called when _widths_ok is false.
fn _width_err(tag_size: Int, length_size: Int) -> Str {
  if tag_size < 1 || tag_size > 4 {
    return "tlv: invalid tag size";
  }
  return "tlv: invalid length size";
}

// Largest unsigned value representable in `size` bytes (size >= 1).
fn _max_unsigned(size: Int) -> Int {
  var v: Int = 1;
  var i = 0;
  while i < size {
    v = v * 256;
    i = i + 1;
  }
  return v - 1;
}

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Big-endian byte `shift_bytes` of `v` (0 = least significant byte).
// Arithmetic only: `& 0xFF` on values with bit 31 set miscompiles in
// v0.61.3, and this form is exact for negative two's-complement values.
fn _be_byte(v: Int, shift_bytes: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift_bytes {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low `size` bytes of `v` in big-endian order.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_be_byte(v, i));
    i = i - 1;
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

// Unsigned big-endian Int of the `size` bytes at `pos`. The caller
// guarantees pos + size <= data.len().
fn _read_be(data: &Vec[UInt8], pos: Int, size: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < size {
    v = v * 256 + _byte(data, pos + i);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse a flat TLV stream.
///
/// `data` holds the whole stream; `tag_size` and `length_size` are the
/// entry widths in 1..4. Entries are walked until the buffer ends, so a
/// declared value that does not fit is an error, never a silent stop.
/// The returned TlvList stores tags in order and the absolute
/// [value_offsets, value_offsets + value_lengths) span of each value.
///
/// Err("tlv: invalid tag size") / Err("tlv: invalid length size") when a
/// width is outside 1..4; Err("tlv: truncated header") when a nonzero
/// tail is shorter than tag_size + length_size; Err("tlv: value overruns
/// buffer") when a declared value length exceeds the remaining bytes.
/// An empty buffer yields Ok with zero entries.
/// Complexity: O(data.len()).
pub fn tlv_parse(data: &Vec[UInt8], tag_size: Int, length_size: Int) -> Result[TlvList, Str] {
  if !_widths_ok(tag_size, length_size) {
    return _err_list(_width_err(tag_size, length_size));
  }
  var tags = Vec[Int].new();
  var offsets = Vec[Int].new();
  var lengths = Vec[Int].new();
  let total = data.len();
  let header = tag_size + length_size;
  var pos = 0;
  while pos < total {
    let remaining = total - pos;
    if remaining < header {
      return _err_list("tlv: truncated header");
    }
    let tag = _read_be(data, pos, tag_size);
    pos = pos + tag_size;
    let len = _read_be(data, pos, length_size);
    pos = pos + length_size;
    if len > total - pos {
      return _err_list("tlv: value overruns buffer");
    }
    tags.push(tag);
    offsets.push(pos);
    lengths.push(len);
    pos = pos + len;
  }
  return _ok_list(TlvList{ tags: tags; value_offsets: offsets; value_lengths: lengths; });
}

/// Number of parsed entries.
/// Complexity: O(1).
pub fn tlv_count(l: &TlvList) -> Int {
  return l.tags.len();
}

/// Tag of entry `i`, or -1 when i is negative or >= tlv_count(l).
/// Complexity: O(1).
pub fn tlv_tag(l: &TlvList, i: Int) -> Int {
  if i < 0 || i >= l.tags.len() {
    return -1;
  }
  return l.tags[i];
}

/// First entry index whose tag equals `tag`, or -1 when absent.
/// Complexity: O(entries).
pub fn tlv_find(l: &TlvList, tag: Int) -> Int {
  var i = 0;
  while i < l.tags.len() {
    if l.tags[i] == tag {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Copy the value bytes of entry `i` out of `data`.
///
/// `data` must be the buffer the list was parsed from (or one holding at
/// least the recorded span). Err("tlv: index out of range") when i is
/// negative or >= tlv_count(l); Err("tlv: value out of bounds") when the
/// recorded span does not fit `data`.
/// Complexity: O(value length).
pub fn tlv_value(data: &Vec[UInt8], l: &TlvList, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= l.tags.len() {
    return _err_bytes("tlv: index out of range");
  }
  let off: Int = l.value_offsets[i];
  let len: Int = l.value_lengths[i];
  if off < 0 || len < 0 {
    return _err_bytes("tlv: value out of bounds");
  }
  if off + len > data.len() {
    return _err_bytes("tlv: value out of bounds");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Building
// --------------------------------------------------

/// Append one entry to `out`: tag and value length as big-endian
/// `tag_size`/`length_size`-byte fields, then the value bytes verbatim.
///
/// Err("tlv: invalid tag size") / Err("tlv: invalid length size") for
/// widths outside 1..4; Err("tlv: negative tag") for tag < 0;
/// Err("tlv: tag too large for tag_size") when tag does not fit the tag
/// width; Err("tlv: value too large for length_size") when value.len()
/// does not fit the length width. All validation happens before any byte
/// is written, so `out` is unchanged on Err.
/// Complexity: O(value length).
pub fn tlv_append(out: &mut Vec[UInt8], tag: Int, value: &Vec[UInt8], tag_size: Int, length_size: Int) -> Result[Unit, Str] {
  if !_widths_ok(tag_size, length_size) {
    return _err_unit(_width_err(tag_size, length_size));
  }
  if tag < 0 {
    return _err_unit("tlv: negative tag");
  }
  if tag > _max_unsigned(tag_size) {
    return _err_unit("tlv: tag too large for tag_size");
  }
  let n = value.len();
  if n > _max_unsigned(length_size) {
    return _err_unit("tlv: value too large for length_size");
  }
  _push_be(out, tag, tag_size);
  _push_be(out, n, length_size);
  _push_bytes(out, value);
  return _ok_unit();
}

/// Build a whole flat TLV stream from parallel tag/value vectors, using
/// tlv_append for every entry.
///
/// Err("tlv: invalid tag size") / Err("tlv: invalid length size") for
/// widths outside 1..4; Err("tlv: tags/values length mismatch") when the
/// vectors differ in length; otherwise the first per-entry failure of
/// tlv_append (same messages). An empty pair of vectors yields Ok(empty).
/// Complexity: O(total value bytes).
pub fn tlv_build_from(tags: &Vec[Int], values: &Vec[Vec[UInt8]], tag_size: Int, length_size: Int) -> Result[Vec[UInt8], Str] {
  if !_widths_ok(tag_size, length_size) {
    return _err_bytes(_width_err(tag_size, length_size));
  }
  if tags.len() != values.len() {
    return _err_bytes("tlv: tags/values length mismatch");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < tags.len() {
    let tag: Int = tags[i];
    let value: Vec[UInt8] = values[i];
    let ar = tlv_append(&mut out, tag, &value, tag_size, length_size);
    if !ar.is_ok {
      return _err_bytes(ar.error);
    }
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Encoded size of one entry: tag_size + length_size + value_len.
/// Returns -1 when a width is outside 1..4 or value_len is negative.
/// Complexity: O(1).
pub fn tlv_size(tag_size: Int, length_size: Int, value_len: Int) -> Int {
  if !_widths_ok(tag_size, length_size) {
    return -1;
  }
  if value_len < 0 {
    return -1;
  }
  return tag_size + length_size + value_len;
}
