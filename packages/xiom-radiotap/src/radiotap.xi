// XIOM -- xiom.radiotap: IEEE 802.11 radiotap capture header codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the radiotap capture header that precedes an 802.11 frame in
// monitor-mode captures -- the 8-byte base header (version, pad, little-
// endian length, present bitmap word 0), an optional second present word
// when bit 31 of word 0 chains to it, and the fixed-size data fields
// selected by bits 0..19 of the documented table in SPEC.md. Field parsing
// walks the present bits in ascending order, aligns each field to its
// natural boundary relative to the start of the radiotap header (8 bytes
// for TSFT, 4 for XCHANNEL, 2 for the u16 fields, 1 otherwise), and stops
// with Err("radiotap: unsupported field") at the first set bit outside the
// table instead of guessing a size. The 802.11 frame bytes after the
// header stay in the source buffer and are located by frame_off/frame_len;
// radiotap_emit re-encodes a parsed header byte-for-byte.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * present-word bit tests never use `&` masks: `& 0xFF`-style masking
//     miscompiles on operands with bit 31 set, and word 0 of a two-word
//     header has bit 31 set by definition. Bits are tested by repeated
//     division (`v / 2^k % 2`, and a halving `q = q / 2` scan).
//   * 16/32/64-bit reads and writes are pure arithmetic (+ - * / %), exact
//     for unsigned values with the high bit set.
//   * RadiotapHeader is constructed inside radiotap_parse and crosses
//     function boundaries only by reference or through _ok_header,
//     following the xiom.pcap PcapFile precedent.
// See SPEC.md for the layout tables, alignment rules, error catalog and
// test plan.

module xiom.radiotap

/// Parsed radiotap header. `version` is the version byte (always 0 on
/// success) and `length` is the declared header length in bytes, which
/// validation requires to equal the encoded size (base header plus aligned
/// fields). `present_words` is 1 or 2 and `present0`/`present1` hold the
/// present bitmap words as read (`present1` is 0 when there is only one
/// word). `bits` and `values` are parallel pools, one (bit, value) pair per
/// parsed field in ascending bit order; composite fields are stored as one
/// Int (see SPEC.md). `frame_off` is the absolute offset of the first
/// 802.11 frame byte (`length`) and `frame_len` the number of frame bytes
/// remaining in the parsed buffer. Fields are implementation details;
/// callers should go through the free functions below.
pub type RadiotapHeader = {
  version: Int;
  length: Int;
  present_words: Int;
  present0: Int;
  present1: Int;
  bits: Vec[Int];
  values: Vec[Int];
  frame_off: Int;
  frame_len: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[RadiotapHeader, Str].
fn _ok_header(v: RadiotapHeader) -> Result[RadiotapHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[RadiotapHeader, Str].
fn _err_header(m: Str) -> Result[RadiotapHeader, Str] {
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

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers (little-endian, arithmetic only)
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned 16-bit little-endian integer at [pos, pos+2). The caller
// guarantees the two bytes are in bounds.
fn _le_u16(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  return b0 + b1 * 256;
}

// Unsigned 32-bit little-endian integer at [pos, pos+4), returned in an Int
// (0..4294967295). The caller guarantees the four bytes are in bounds.
fn _le_u32(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  let b2: Int = _byte(data, pos + 2);
  let b3: Int = _byte(data, pos + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Unsigned 64-bit little-endian integer at [pos, pos+8), returned in an Int.
// The caller guarantees the eight bytes are in bounds and that byte 7 is
// below 128 (otherwise the value would not fit the signed Int result; the
// parse loop reports Err("radiotap: tsft out of range") before this call).
fn _le_u64(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  let b2: Int = _byte(data, pos + 2);
  let b3: Int = _byte(data, pos + 3);
  let b4: Int = _byte(data, pos + 4);
  let b5: Int = _byte(data, pos + 5);
  let b6: Int = _byte(data, pos + 6);
  let b7: Int = _byte(data, pos + 7);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216 + b4 * 4294967296 + b5 * 1099511627776 + b6 * 281474976710656 + b7 * 72057594037927936;
}

// Append the low byte of `v` (caller guarantees 0..255).
fn _push_le8(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
}

// Append the low two bytes of `v` in little-endian order.
fn _push_le16(out: &mut Vec[UInt8], v: Int) {
  _push_le8(out, v % 256);
  _push_le8(out, (v / 256) % 256);
}

// Append the low four bytes of `v` in little-endian order.
fn _push_le32(out: &mut Vec[UInt8], v: Int) {
  _push_le8(out, v % 256);
  _push_le8(out, (v / 256) % 256);
  _push_le8(out, (v / 65536) % 256);
  _push_le8(out, (v / 16777216) % 256);
}

// Append the eight bytes of `v` in little-endian order.
fn _push_le64(out: &mut Vec[UInt8], v: Int) {
  _push_le8(out, v % 256);
  _push_le8(out, (v / 256) % 256);
  _push_le8(out, (v / 65536) % 256);
  _push_le8(out, (v / 16777216) % 256);
  _push_le8(out, (v / 4294967296) % 256);
  _push_le8(out, (v / 1099511627776) % 256);
  _push_le8(out, (v / 281474976710656) % 256);
  _push_le8(out, (v / 72057594037927936) % 256);
}

// Overwrite the 16-bit little-endian field at [pos, pos+2) of an existing
// buffer. The caller guarantees the two positions exist.
fn _set_le16(v: &mut Vec[UInt8], pos: Int, n: Int) {
  v[pos] = (n % 256) as UInt8;
  v[pos + 1] = ((n / 256) % 256) as UInt8;
}

// --------------------------------------------------
//  Internal bit-table helpers (SPEC.md field table)
// --------------------------------------------------

// True when `v` (a non-negative 32-bit present word) has present bit `bit`
// set. Arithmetic only: bit 31 must not pass through a `&` mask.
fn _bit_set(v: Int, bit: Int) -> Bool {
  var q = v;
  var i = 0;
  while i < bit {
    q = q / 2;
    i = i + 1;
  }
  return q % 2 == 1;
}

// 2^k for k in 0..31 (used to rebuild present words in radiotap_emit).
fn _pow2(k: Int) -> Int {
  var v: Int = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// True when `bit` names a field in the fixed table (0..19). Every other
// present bit -- including 20..30 (bit 30 is the vendor namespace, which
// this codec does not decode) and every field bit of the second present
// word -- is unsupported.
fn _field_known(bit: Int) -> Bool {
  return bit >= 0 && bit <= 19;
}

// Encoded size in bytes: 0 TSFT u64, 3 CHANNEL 2*u16, 19 XCHANNEL u32,
// 4 FHSS 2*u8, 7/8/9/15/16 u16, all others u8/i8.
fn _field_size(bit: Int) -> Int {
  if bit == 0 {
    return 8;
  }
  if bit == 3 {
    return 4;
  }
  if bit == 19 {
    return 4;
  }
  if bit == 4 {
    return 2;
  }
  if bit == 7 {
    return 2;
  }
  if bit == 8 {
    return 2;
  }
  if bit == 9 {
    return 2;
  }
  if bit == 15 {
    return 2;
  }
  if bit == 16 {
    return 2;
  }
  return 1;
}

// Alignment relative to the start of the radiotap header: 8 for TSFT
// (u64), 4 for XCHANNEL (u32), 2 for the u16 fields, 1 otherwise.
fn _field_align(bit: Int) -> Int {
  if bit == 0 {
    return 8;
  }
  if bit == 19 {
    return 4;
  }
  if bit == 3 {
    return 2;
  }
  if bit == 7 {
    return 2;
  }
  if bit == 8 {
    return 2;
  }
  if bit == 9 {
    return 2;
  }
  if bit == 15 {
    return 2;
  }
  if bit == 16 {
    return 2;
  }
  return 1;
}

// True for the three signed i8 fields: 5 DBM_ANTSIGNAL, 6 DBM_ANTNOISE and
// 10 DBM_TX_POWER. The remaining 1-byte fields are unsigned u8.
fn _field_signed(bit: Int) -> Bool {
  return bit == 5 || bit == 6 || bit == 10;
}

// Smallest value representable by the field: -128 for a signed i8, else 0.
fn _field_min(bit: Int) -> Int {
  if _field_signed(bit) {
    return -128;
  }
  return 0;
}

// Largest value representable by the field: 127 for a signed i8, else
// 2^(8*size) - 1 (the u64 field caps at the largest non-negative Int).
fn _field_max(bit: Int) -> Int {
  if _field_signed(bit) {
    return 127;
  }
  let size = _field_size(bit);
  if size == 8 {
    return 9223372036854775807;
  }
  var v: Int = 1;
  var i = 0;
  while i < size {
    v = v * 256;
    i = i + 1;
  }
  return v - 1;
}

// `off` rounded up to the next multiple of `align` (off and align are
// non-negative; align is 1, 2, 4 or 8).
fn _align_up(off: Int, align: Int) -> Int {
  let r = off % align;
  if r == 0 {
    return off;
  }
  return off + (align - r);
}

// --------------------------------------------------
//  Internal field payload conversion
// --------------------------------------------------

// Value of the field encoded at absolute offset `off`. Composite fields are
// combined into one Int: CHANNEL low 16 bits = frequency (MHz), high 16
// bits = channel flags; FHSS low byte = hop set, high byte = hop pattern.
// Signed i8 fields are sign-extended to -128..127. The caller guarantees
// the whole field is in bounds and, for bit 0, that byte 7 is below 128.
fn _read_field(data: &Vec[UInt8], bit: Int, off: Int) -> Int {
  if bit == 0 {
    return _le_u64(data, off);
  }
  if bit == 3 {
    let freq: Int = _le_u16(data, off);
    let flags: Int = _le_u16(data, off + 2);
    return freq + flags * 65536;
  }
  if bit == 4 {
    let set: Int = _byte(data, off);
    let pattern: Int = _byte(data, off + 1);
    return set + pattern * 256;
  }
  let size = _field_size(bit);
  if size == 4 {
    return _le_u32(data, off);
  }
  if size == 2 {
    return _le_u16(data, off);
  }
  let b: Int = _byte(data, off);
  if _field_signed(bit) {
    if b >= 128 {
      return b - 256;
    }
  }
  return b;
}

// Append the encoding of `v` for field `bit`; the caller has already
// validated that `v` is representable (`_field_min`..`_field_max`).
fn _push_field(out: &mut Vec[UInt8], bit: Int, v: Int) {
  if bit == 0 {
    _push_le64(out, v);
    return;
  }
  if bit == 3 {
    _push_le16(out, v % 65536);
    _push_le16(out, v / 65536);
    return;
  }
  if bit == 4 {
    _push_le8(out, v % 256);
    _push_le8(out, v / 256);
    return;
  }
  if bit == 19 {
    _push_le32(out, v);
    return;
  }
  if bit == 7 || bit == 8 || bit == 9 || bit == 15 || bit == 16 {
    _push_le16(out, v);
    return;
  }
  var b = v;
  if _field_signed(bit) && b < 0 {
    b = b + 256;
  }
  _push_le8(out, b);
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse a radiotap header from the start of `data`.
///
/// Layout: version[1] (must be 0), pad[1] (skipped), length[2] little-
/// endian, present word 0[4] little-endian, then present word 1[4] when
/// bit 31 of word 0 is set (a third word is rejected). The declared
/// `length` must be >= 8, must fit in `data`, and must equal the encoded
/// size of the base header plus the aligned fields.
///
/// Set present bits are walked in ascending order. Each bit must be in the
/// fixed 0..19 table; the first unknown bit stops the parse with
/// `radiotap: unsupported field`. Alignment padding before a field must be
/// zero bytes, the aligned field must fit inside `length`, and any set bit
/// of the second present word (absolute bit 32..62 -- the table has no
/// fields there) is unsupported as well.
///
/// Errors (all stable):
///   * `radiotap: truncated header` -- fewer than 8 bytes;
///   * `radiotap: bad version` -- version byte is not 0;
///   * `radiotap: bad length` -- length < 8 or length > data.len();
///   * `radiotap: bad present chain` -- word 0 chains but length < 12;
///   * `radiotap: too many present words` -- a third word is declared;
///   * `radiotap: unsupported field` -- first set bit outside the table
///     (including bit 30, the vendor namespace, and second-word bits);
///   * `radiotap: truncated field` -- a field crosses the declared length;
///   * `radiotap: bad alignment padding` -- nonzero alignment padding;
///   * `radiotap: tsft out of range` -- TSFT has bit 63 set (does not fit
///     the signed Int result);
///   * `radiotap: length mismatch` -- fields end before `length`.
/// Complexity: O(fields + length) time, O(fields) space.
pub fn radiotap_parse(data: &Vec[UInt8]) -> Result[RadiotapHeader, Str] {
  let n = data.len();
  if n < 8 {
    return _err_header("radiotap: truncated header");
  }
  let version: Int = _byte(data, 0);
  if version != 0 {
    return _err_header("radiotap: bad version");
  }
  let length: Int = _le_u16(data, 2);
  if length < 8 {
    return _err_header("radiotap: bad length");
  }
  if length > n {
    return _err_header("radiotap: bad length");
  }
  let present0: Int = _le_u32(data, 4);
  var present1: Int = 0;
  var words = 1;
  var off = 8;
  if _bit_set(present0, 31) {
    if length < 12 {
      return _err_header("radiotap: bad present chain");
    }
    present1 = _le_u32(data, 8);
    if _bit_set(present1, 31) {
      return _err_header("radiotap: too many present words");
    }
    words = 2;
    off = 12;
  }
  if present1 != 0 {
    return _err_header("radiotap: unsupported field");
  }
  var bits = Vec[Int].new();
  var values = Vec[Int].new();
  var q = present0;
  var bit = 0;
  while bit < 31 {
    if q % 2 == 1 {
      if !_field_known(bit) {
        return _err_header("radiotap: unsupported field");
      }
      let a = _align_up(off, _field_align(bit));
      let size = _field_size(bit);
      if a + size > length {
        return _err_header("radiotap: truncated field");
      }
      var p = off;
      while p < a {
        let pad: Int = _byte(data, p);
        if pad != 0 {
          return _err_header("radiotap: bad alignment padding");
        }
        p = p + 1;
      }
      if bit == 0 {
        let top: Int = _byte(data, a + 7);
        if top >= 128 {
          return _err_header("radiotap: tsft out of range");
        }
      }
      let v = _read_field(data, bit, a);
      bits.push(bit);
      values.push(v);
      off = a + size;
    }
    q = q / 2;
    bit = bit + 1;
  }
  if off != length {
    return _err_header("radiotap: length mismatch");
  }
  let h = RadiotapHeader{
    version: version;
    length: length;
    present_words: words;
    present0: present0;
    present1: present1;
    bits: bits;
    values: values;
    frame_off: length;
    frame_len: n - length;
  };
  return _ok_header(h);
}

/// Re-encode a header into its canonical byte form (base header, present
/// words, fields in ascending bit order with zero alignment padding, and a
/// recomputed length field). The pool must be in strictly ascending bit
/// order and every bit/value must be in the documented table and range --
/// as radiotap_parse produces. Nothing is written unless the whole header
/// validates, so the result is either the exact bytes or an Err.
///
/// Errors (all stable):
///   * `radiotap: bad version` -- version byte is not 0;
///   * `radiotap: field pool mismatch` -- bits.len() != values.len();
///   * `radiotap: present words mismatch` -- present_words is not 1 or 2,
///     or the stored present words disagree with the pool;
///   * `radiotap: fields out of order` -- a bit repeats or decreases;
///   * `radiotap: unsupported field` -- a bit outside the 0..19 table;
///   * `radiotap: field value out of range` -- value not representable by
///     the field's width/signedness.
/// Complexity: O(fields + encoded size) time.
pub fn radiotap_emit(h: &RadiotapHeader) -> Result[Vec[UInt8], Str] {
  if h.version != 0 {
    return _err_bytes("radiotap: bad version");
  }
  let n = h.bits.len();
  if n != h.values.len() {
    return _err_bytes("radiotap: field pool mismatch");
  }
  var words = 1;
  if h.present_words == 2 {
    words = 2;
  }
  if h.present_words != words {
    return _err_bytes("radiotap: present words mismatch");
  }
  var p0: Int = 0;
  var prev: Int = -1;
  var i = 0;
  while i < n {
    let bit: Int = h.bits[i];
    let v: Int = h.values[i];
    if bit <= prev {
      return _err_bytes("radiotap: fields out of order");
    }
    if !_field_known(bit) {
      return _err_bytes("radiotap: unsupported field");
    }
    if v < _field_min(bit) {
      return _err_bytes("radiotap: field value out of range");
    }
    if v > _field_max(bit) {
      return _err_bytes("radiotap: field value out of range");
    }
    p0 = p0 + _pow2(bit);
    prev = bit;
    i = i + 1;
  }
  if words == 2 {
    p0 = p0 + _pow2(31);
  }
  if h.present0 != p0 {
    return _err_bytes("radiotap: present words mismatch");
  }
  if h.present1 != 0 {
    return _err_bytes("radiotap: present words mismatch");
  }
  var out = Vec[UInt8].new();
  _push_le8(&mut out, 0);
  _push_le8(&mut out, 0);
  _push_le16(&mut out, 0);
  _push_le32(&mut out, p0);
  if words == 2 {
    _push_le32(&mut out, 0);
  }
  var off = out.len();
  i = 0;
  while i < n {
    let bit: Int = h.bits[i];
    let v: Int = h.values[i];
    let a = _align_up(off, _field_align(bit));
    while off < a {
      _push_le8(&mut out, 0);
      off = off + 1;
    }
    _push_field(&mut out, bit, v);
    off = off + _field_size(bit);
    i = i + 1;
  }
  _set_le16(&mut out, 2, off);
  return _ok_bytes(out);
}

/// Version byte of a parsed header (0 for every accepted header).
/// Complexity: O(1).
pub fn radiotap_version(h: &RadiotapHeader) -> Int {
  return h.version;
}

/// Declared header length in bytes: the offset of the first 802.11 frame
/// byte. Complexity: O(1).
pub fn radiotap_length(h: &RadiotapHeader) -> Int {
  return h.length;
}

/// Number of present bitmap words (1, or 2 when word 0 chained).
/// Complexity: O(1).
pub fn radiotap_present_count(h: &RadiotapHeader) -> Int {
  return h.present_words;
}

/// Present bitmap word `i` (0 or 1), or -1 when `i` is out of range for
/// this header. Word 1 of a two-word header may legitimately be 0, so -1 is
/// the only out-of-range marker. Complexity: O(1).
pub fn radiotap_present_word(h: &RadiotapHeader, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= h.present_words {
    return -1;
  }
  if i == 0 {
    return h.present0;
  }
  return h.present1;
}

/// Number of parsed fields (one per set, supported present bit).
/// Complexity: O(1).
pub fn radiotap_field_count(h: &RadiotapHeader) -> Int {
  return h.bits.len();
}

/// Present bit of field `i` in pool order (ascending), or -1 when `i` is
/// negative or >= radiotap_field_count(h). Complexity: O(1).
pub fn radiotap_field_bit(h: &RadiotapHeader, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= h.bits.len() {
    return -1;
  }
  let bit: Int = h.bits[i];
  return bit;
}

/// Value of field `i` in pool order. Err("radiotap: field index out of
/// range") when `i` is negative or >= radiotap_field_count(h).
/// Complexity: O(1).
pub fn radiotap_field_value_at(h: &RadiotapHeader, i: Int) -> Result[Int, Str] {
  if i < 0 {
    return _err_int("radiotap: field index out of range");
  }
  if i >= h.values.len() {
    return _err_int("radiotap: field index out of range");
  }
  let v: Int = h.values[i];
  return _ok_int(v);
}

/// Index of the first field with present bit `bit`, or -1 when absent.
/// The pool is in ascending bit order and parse never records a bit twice,
/// so the first match is the only match for parsed headers; for a
/// hand-built header with duplicates the lowest index wins.
/// Complexity: O(fields).
pub fn radiotap_find(h: &RadiotapHeader, bit: Int) -> Int {
  var i = 0;
  let n = h.bits.len();
  while i < n {
    let b: Int = h.bits[i];
    if b == bit {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Value recorded for the first field with present bit `bit`.
/// Err("radiotap: field absent") when no parsed field has that bit.
/// Complexity: O(fields).
pub fn radiotap_value(h: &RadiotapHeader, bit: Int) -> Result[Int, Str] {
  let i: Int = radiotap_find(h, bit);
  if i < 0 {
    return _err_int("radiotap: field absent");
  }
  let v: Int = h.values[i];
  return _ok_int(v);
}

/// Frequency in MHz of the CHANNEL field (bit 3, low 16 bits of the stored
/// value), or -1 when the header has no CHANNEL field. Complexity: O(fields).
pub fn radiotap_channel_freq(h: &RadiotapHeader) -> Int {
  let i: Int = radiotap_find(h, 3);
  if i < 0 {
    return -1;
  }
  let v: Int = h.values[i];
  return v % 65536;
}

/// Channel flags of the CHANNEL field (bit 3, high 16 bits of the stored
/// value), or -1 when the header has no CHANNEL field. Complexity: O(fields).
pub fn radiotap_channel_flags(h: &RadiotapHeader) -> Int {
  let i: Int = radiotap_find(h, 3);
  if i < 0 {
    return -1;
  }
  let v: Int = h.values[i];
  return v / 65536;
}

/// Absolute offset of the first 802.11 frame byte in the parsed buffer
/// (equal to the header length). Complexity: O(1).
pub fn radiotap_frame_offset(h: &RadiotapHeader) -> Int {
  return h.frame_off;
}

/// Number of 802.11 frame bytes after the header in the buffer that was
/// parsed. Complexity: O(1).
pub fn radiotap_frame_length(h: &RadiotapHeader) -> Int {
  return h.frame_len;
}

/// Copy the frame bytes out of `data` (the buffer passed to
/// radiotap_parse): `frame_len` bytes starting at `frame_off`.
/// Err("radiotap: frame out of bounds") when the recorded span does not fit
/// in `data` (for example when a shorter buffer is passed). A header with
/// no trailing frame yields an empty Ok. Complexity: O(frame_len).
pub fn radiotap_frame(data: &Vec[UInt8], h: &RadiotapHeader) -> Result[Vec[UInt8], Str] {
  let off: Int = h.frame_off;
  let len: Int = h.frame_len;
  if off < 0 || len < 0 {
    return _err_bytes("radiotap: frame out of bounds");
  }
  if off + len > data.len() {
    return _err_bytes("radiotap: frame out of bounds");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}
