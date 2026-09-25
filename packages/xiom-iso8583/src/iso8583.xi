// XIOM -- xiom.iso8583: ISO 8583 ASCII message codec (documented subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (see SPEC.md for the exact tables and error catalog): a pure-XIOM
// (no FFI, no dependencies beyond xiom.std) codec for the ASCII form of an
// ISO 8583 message -- a 4-digit MTI, then the primary bitmap as 16 hex
// digits (plus a second 16-digit secondary bitmap when bit 1 of the primary
// is set, i.e. MSB-first indexing with bit 1 = index 0), then the present
// fields in ascending field-number order. Fixed-length fields are written
// verbatim; LLVAR/LLLVAR fields carry a 2- or 3-digit length prefix. Only a
// documented subset of fields is modeled (2, 3, 4, 7, 11, 32, 39, 41, 48,
// 49, 70); a bitmap bit for any other field number is an error, never
// silently skipped. Binary/BCD/EBCDIC encodings, tertiary bitmaps, the rest
// of the field dictionary, sockets and MAC/PIN blocks are out of scope.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no self methods, no lambdas, no Vec[fn]
//     dispatch, no Vec[StructType], no Vec[Float64];
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles);
//   * every byte read from a Str or a Vec[UInt8] is widened once with
//     (`byte_at(...)` as Int) & 0xFF before entering Int arithmetic;
//   * no `==` is ever applied to a Str value and no Str value is stored in
//     a Vec[Str] (field values travel as Vec[Vec[UInt8]], the xiom.tlv
//     precedent), so the BUG-17 pointer-comparison trap cannot apply;
//   * every Vec read is bound to an explicitly typed local first;
//   * Str output is collected in a Vec[UInt8] and materialized once with
//     xiom.string.builder.sb_to_str, after the bytes have been validated as
//     printable ASCII (0x20..0x7E) so no 0x00 ever reaches the builder.

module xiom.iso8583

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Dimensions and byte constants
// --------------------------------------------------

const _MTI_LEN: Int = 4;
const _HEX_BITMAP_LEN: Int = 16;        // primary bitmap, hex digits
const _HEX_FULL_LEN: Int = 32;          // primary + secondary, hex digits
const _BIN_BITMAP_LEN: Int = 64;        // primary bitmap, '0'/'1' chars
const _BIN_FULL_LEN: Int = 128;         // primary + secondary, '0'/'1' chars
const _MAX_FIELD: Int = 128;            // highest bit of a secondary bitmap
const _NIBBLES_FULL: Int = 32;          // nibbles in a full (secondary) bitmap

const _AN_LO: Int = 32;                 // ' ', first printable ASCII byte
const _AN_HI: Int = 126;                // '~', last printable ASCII byte

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(m) for Result[Iso8583Message, Str].
fn _ok_msg(m: Iso8583Message) -> Result[Iso8583Message, Str] {
  return Ok(m);
}

// Err(s) for Result[Iso8583Message, Str].
fn _err_msg(s: Str) -> Result[Iso8583Message, Str] {
  return Err(s);
}

// Ok(b) for Result[Iso8583Bitmap, Str].
fn _ok_bitmap(b: Iso8583Bitmap) -> Result[Iso8583Bitmap, Str] {
  return Ok(b);
}

// Err(s) for Result[Iso8583Bitmap, Str].
fn _err_bitmap(s: Str) -> Result[Iso8583Bitmap, Str] {
  return Err(s);
}

// Ok(s) for Result[Str, Str].
fn _ok_str(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

// Err(s) for Result[Str, Str].
fn _err_str(s: Str) -> Result[Str, Str] {
  return Err(s);
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed ISO 8583 ASCII message or one built by `iso8583_build_message`.
/// `mti` is the 4-digit message type indicator. `has_secondary` records
/// whether bit 1 of the primary bitmap is set, i.e. whether a secondary
/// bitmap (fields 65..128) is part of the message. Fields are stored flat
/// and parallel: `field_numbers[i]` is an ascending field number and
/// `field_values[i]` holds its raw ASCII bytes (validated at the boundary:
/// digits for numeric fields, printable ASCII for alphanumeric fields). The
/// bitmap itself is derived from `field_numbers` plus `has_secondary`, so
/// there is exactly one source of truth. `Vec[StructType]` is unsupported,
/// hence the two parallel vectors instead of a `Vec[Field]`.
pub type Iso8583Message = {
  mti: Str;
  has_secondary: Bool;
  field_numbers: Vec[Int];
  field_values: Vec[Vec[UInt8]];
}

/// The field numbers declared present by one bitmap (`iso8583_bitmap_parse`).
/// `numbers` is ascending; `has_secondary` is true when bit 1 of the primary
/// bitmap is set (the bitmap text carried a secondary bitmap). Field 1 is
/// the secondary-bitmap marker and is never reported as a field number.
pub type Iso8583Bitmap = {
  has_secondary: Bool;
  numbers: Vec[Int];
}

// --------------------------------------------------
//  Byte and Str helpers
// --------------------------------------------------

// Byte `i` of `s` widened to 0..255. Every byte read in this module goes
// through here; callers guarantee the index is in bounds.
fn _byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Copy bytes [start, end) of `s` into a fresh vector. The caller guarantees
// 0 <= start <= end <= s.len().
fn _bytes_of_range(s: Str, start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// Append every byte of `v` to `out`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// The bytes of `v` as a Str. Only called on vectors that were validated as
// printable ASCII at the API boundary, so no 0x00 is ever pushed and
// sb_to_str cannot abort.
fn _bytes_to_str(v: &Vec[UInt8]) -> Str {
  var sb = Vec[UInt8].new();
  _push_bytes(&mut sb, v);
  return builder.sb_to_str(&sb);
}

// A fresh copy of `src` (structs store owned vectors, not references).
fn _copy_ints(src: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < src.len() {
    let v: Int = src[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

// A fresh copy of the value vectors.
fn _copy_values(src: &Vec[Vec[UInt8]]) -> Vec[Vec[UInt8]] {
  var out = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < src.len() {
    let v: Vec[UInt8] = src[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

// True when `mti` is exactly four ASCII digits.
fn _mti_ok(mti: Str) -> Bool {
  if mti.len() != _MTI_LEN {
    return false;
  }
  var i = 0;
  while i < _MTI_LEN {
    let b: Int = _byte_at(mti, i);
    if b < 48 || b > 57 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// The `count`-digit unsigned decimal number starting at `start` of `s`, or
// -1 when any of those characters is not an ASCII digit. The caller
// guarantees the range is in bounds.
fn _digits_int(s: Str, start: Int, count: Int) -> Int {
  var v = 0;
  var i = 0;
  while i < count {
    let b: Int = _byte_at(s, start + i);
    if b < 48 || b > 57 {
      return -1;
    }
    v = v * 10 + (b - 48);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Field dictionary (documented subset only)
// --------------------------------------------------

// Field kind of field number `n`:
//   0 = unknown, 1 = fixed numeric, 2 = fixed alphanumeric,
//   3 = LLVAR numeric (2-digit prefix), 4 = LLLVAR alphanumeric (3-digit
//   prefix). This is the whole field dictionary of this package; every
//   other ISO 8583 field number is rejected as unknown.
fn _field_kind(n: Int) -> Int {
  if n == 2 { return 3; }
  if n == 3 { return 1; }
  if n == 4 { return 1; }
  if n == 7 { return 1; }
  if n == 11 { return 1; }
  if n == 32 { return 3; }
  if n == 39 { return 2; }
  if n == 41 { return 2; }
  if n == 48 { return 4; }
  if n == 49 { return 2; }
  if n == 70 { return 1; }
  return 0;
}

// Fixed encoded length of field `n`, or 0 when `n` is variable-length or
// unknown. Only called after _field_kind confirmed a fixed kind.
fn _field_fixed_len(n: Int) -> Int {
  if n == 3 { return 6; }
  if n == 4 { return 12; }
  if n == 7 { return 10; }
  if n == 11 { return 6; }
  if n == 39 { return 2; }
  if n == 41 { return 8; }
  if n == 49 { return 3; }
  if n == 70 { return 3; }
  return 0;
}

// Maximum value length of the variable-length field `n`, or 0 when `n` is
// fixed-length or unknown.
fn _field_max_len(n: Int) -> Int {
  if n == 2 { return 19; }
  if n == 32 { return 11; }
  if n == 48 { return 999; }
  return 0;
}

// True for the variable-length kinds 3 (LLVAR) and 4 (LLLVAR).
fn _is_variable_kind(kind: Int) -> Bool {
  if kind == 3 || kind == 4 {
    return true;
  }
  return false;
}

// True when every byte of `v` is an ASCII digit.
fn _all_numeric(v: &Vec[UInt8]) -> Bool {
  var i = 0;
  while i < v.len() {
    let b: Int = (v[i] as Int) & 0xFF;
    if b < 48 || b > 57 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when every byte of `v` is printable ASCII (0x20..0x7E).
fn _all_ans(v: &Vec[UInt8]) -> Bool {
  var i = 0;
  while i < v.len() {
    let b: Int = (v[i] as Int) & 0xFF;
    if b < _AN_LO || b > _AN_HI {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `v` is a legal value for a field of the given kind. The final
// branch is a defensive invariant guard: `_field_kind` can only return
// 0..4 and 0 is rejected before any value is checked.
fn _value_ok(kind: Int, v: &Vec[UInt8]) -> Bool {
  if kind == 1 || kind == 3 {
    return _all_numeric(v);
  }
  if kind == 2 || kind == 4 {
    return _all_ans(v);
  }
  return false;
}

// Validate field numbers: strictly ascending, in 2..128, all known.
// Returns "" on success or the deterministic "iso8583: ..." error.
fn _numbers_ok(numbers: &Vec[Int]) -> Str {
  var prev = 1;
  var i = 0;
  while i < numbers.len() {
    let num: Int = numbers[i];
    if num <= 1 || num > _MAX_FIELD {
      return "iso8583: unknown field number";
    }
    if num <= prev {
      return "iso8583: field numbers out of order";
    }
    if _field_kind(num) == 0 {
      return "iso8583: unknown field number";
    }
    prev = num;
    i = i + 1;
  }
  return "";
}

// Validate that `values` is parallel to `numbers` and that every value
// matches its field's length rule and character set. Returns "" on success
// or the deterministic "iso8583: ..." error.
fn _values_ok(numbers: &Vec[Int], values: &Vec[Vec[UInt8]]) -> Str {
  if numbers.len() != values.len() {
    return "iso8583: field numbers/values length mismatch";
  }
  var i = 0;
  while i < numbers.len() {
    let num: Int = numbers[i];
    let kind = _field_kind(num);
    if kind == 0 {
      return "iso8583: unknown field number";
    }
    if kind < 1 || kind > 4 {
      return "iso8583: unknown field type";
    }
    let v: Vec[UInt8] = values[i];
    let len = v.len();
    if _is_variable_kind(kind) {
      if len > _field_max_len(num) {
        return "iso8583: bad field length";
      }
    } else {
      if len != _field_fixed_len(num) {
        return "iso8583: bad field length";
      }
    }
    if !_value_ok(kind, &v) {
      return "iso8583: bad field value";
    }
    i = i + 1;
  }
  return "";
}

// True when any number in `numbers` lives in the secondary bitmap range
// (fields 65..128), i.e. the message needs a secondary bitmap.
fn _any_secondary(numbers: &Vec[Int]) -> Bool {
  var i = 0;
  while i < numbers.len() {
    let num: Int = numbers[i];
    if num >= 65 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Bitmap helpers
// --------------------------------------------------

// The nibble value of bit position `r` (0 = most significant) inside a
// 4-bit nibble: 8, 4, 2, 1.
fn _mask(r: Int) -> Int {
  if r == 0 { return 8; }
  if r == 1 { return 4; }
  if r == 2 { return 2; }
  return 1;
}

// True when 1-based bitmap bit `bit` is set in `nibbles` (MSB-first: bit 1
// is index 0 of the first nibble). The caller guarantees the bit is in the
// range covered by `nibbles`.
fn _bit_set(nibbles: &Vec[Int], bit: Int) -> Bool {
  let q = (bit - 1) / 4;
  let r = (bit - 1) % 4;
  let nib: Int = nibbles[q];
  return (nib / _mask(r)) % 2 == 1;
}

// Set 1-based bit `bit` of `nibbles`. Bits are only ever set once per
// nibble (field numbers are strictly ascending), so adding the mask is
// equivalent to a bitwise OR and avoids bit operators entirely.
fn _set_bit(nibbles: &mut Vec[Int], bit: Int) {
  let q = (bit - 1) / 4;
  let r = (bit - 1) % 4;
  let have: Int = nibbles[q];
  nibbles[q] = have + _mask(r);
}

// Hex value 0..15 of byte `b`, or -1 when `b` is not a hex digit. Both
// cases are accepted on input; output is always uppercase.
fn _hex_val(b: Int) -> Int {
  if b >= 48 && b <= 57 {
    return b - 48;
  }
  if b >= 65 && b <= 70 {
    return b - 55;
  }
  if b >= 97 && b <= 102 {
    return b - 87;
  }
  return -1;
}

// Uppercase hex digit for a nibble value 0..15.
fn _hex_char(n: Int) -> UInt8 {
  if n < 10 {
    return (48 + n) as UInt8;
  }
  return (55 + n) as UInt8;
}

// Append one nibble per hex digit of `text` to `out`; false when a
// character is not a hex digit (in which case `out` may hold a prefix).
fn _hex_nibbles(text: Str, out: &mut Vec[Int]) -> Bool {
  var i = 0;
  while i < text.len() {
    let v = _hex_val(_byte_at(text, i));
    if v < 0 {
      return false;
    }
    out.push(v);
    i = i + 1;
  }
  return true;
}

// Append one nibble per group of four '0'/'1' characters of `text` to
// `out`; false when a character is not '0' or '1'. `text` length is a
// multiple of four (the caller dispatched on 64/128).
fn _binary_nibbles(text: Str, out: &mut Vec[Int]) -> Bool {
  var i = 0;
  while i < text.len() {
    var nib = 0;
    var k = 0;
    while k < 4 {
      let b: Int = _byte_at(text, i + k);
      if b == 48 {
        nib = nib * 2;
      } elif b == 49 {
        nib = nib * 2 + 1;
      } else {
        return false;
      }
      k = k + 1;
    }
    out.push(nib);
    i = i + 4;
  }
  return true;
}

// Append zero nibbles until the vector holds a full 32-nibble bitmap, so
// that bit 65..128 are always addressable.
fn _pad_bits(nibbles: &mut Vec[Int]) {
  while nibbles.len() < _NIBBLES_FULL {
    nibbles.push(0);
  }
}

// True when any bit in [first, last] is set in `nibbles`.
fn _any_set(nibbles: &Vec[Int], first: Int, last: Int) -> Bool {
  var bit = first;
  while bit <= last {
    if _bit_set(nibbles, bit) {
      return true;
    }
    bit = bit + 1;
  }
  return false;
}

// Parse a whole bitmap text: 16/32 hex digits or 64/128 binary digits, with
// the same bit-1 rule as the wire (bit 1 = secondary bitmap present).
// `nibbles` receives exactly 32 nibbles on success. Returns "" on success
// or the deterministic "iso8583: ..." error.
fn _bitmap_parse_text(text: Str, nibbles: &mut Vec[Int]) -> Str {
  let n = text.len();
  if n == _HEX_BITMAP_LEN || n == _HEX_FULL_LEN {
    if !_hex_nibbles(text, nibbles) {
      return "iso8583: bad bitmap hex";
    }
  } elif n == _BIN_BITMAP_LEN || n == _BIN_FULL_LEN {
    if !_binary_nibbles(text, nibbles) {
      return "iso8583: bad bitmap binary";
    }
  } else {
    return "iso8583: bad bitmap length";
  }
  if n == _HEX_BITMAP_LEN || n == _BIN_BITMAP_LEN {
    if _bit_set(nibbles, 1) {
      return "iso8583: bad bitmap length";
    }
  } else {
    if !_bit_set(nibbles, 1) {
      if _any_set(nibbles, 65, _MAX_FIELD) {
        return "iso8583: unexpected secondary bitmap";
      }
    } else {
      if _bit_set(nibbles, 65) {
        return "iso8583: tertiary bitmap not supported";
      }
    }
  }
  _pad_bits(nibbles);
  return "";
}

// Collect the field numbers declared by `nibbles` (already padded to 32
// nibbles) in ascending order. Bit 1 (the secondary marker) is skipped; a
// set bit for any field outside the documented dictionary is an error.
// Returns "" on success or the deterministic "iso8583: ..." error.
fn _declared_numbers(nibbles: &Vec[Int], numbers: &mut Vec[Int]) -> Str {
  var bit = 2;
  while bit <= _MAX_FIELD {
    if _bit_set(nibbles, bit) {
      if _field_kind(bit) == 0 {
        return "iso8583: unknown field number";
      }
      numbers.push(bit);
    }
    bit = bit + 1;
  }
  return "";
}

// Canonical uppercase hex text of the bitmap for `numbers`: 16 digits, or
// 32 when `has_secondary`. `numbers` must already be validated
// (ascending, known, distinct). Bit 1 is set exactly when has_secondary.
fn _bitmap_hex(numbers: &Vec[Int], has_secondary: Bool) -> Str {
  var nibbles = Vec[Int].new();
  var i = 0;
  while i < _NIBBLES_FULL {
    nibbles.push(0);
    i = i + 1;
  }
  if has_secondary {
    nibbles[0] = 8;
  }
  i = 0;
  while i < numbers.len() {
    let num: Int = numbers[i];
    _set_bit(&mut nibbles, num);
    i = i + 1;
  }
  var count = _HEX_BITMAP_LEN;
  if has_secondary {
    count = _HEX_FULL_LEN;
  }
  var sb = Vec[UInt8].new();
  i = 0;
  while i < count {
    let q: Int = nibbles[i];
    builder.sb_push_byte(&mut sb, _hex_char(q));
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Append the decimal digits of `v` zero-padded to `width` (v < 10^width).
// The caller guarantees the width is 2 (LLVAR) or 3 (LLLVAR) and that `v`
// fits.
fn _push_prefix(out: &mut Vec[UInt8], v: Int, width: Int) {
  var div = 1;
  var i = 1;
  while i < width {
    div = div * 10;
    i = i + 1;
  }
  var q = v;
  while div > 0 {
    let d = q / div;
    out.push((48 + d) as UInt8);
    q = q - d * div;
    div = div / 10;
  }
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse one ISO 8583 ASCII message.
///
/// The layout is MTI (4 ASCII digits), the primary bitmap (16 hex digits),
/// an optional secondary bitmap (16 more hex digits when bit 1 of the
/// primary is set) and then the fields whose bits are set, in ascending
/// field-number order. Fixed fields are `_field_fixed_len` characters;
/// LLVAR/LLLVAR fields are a 2- or 3-digit decimal length prefix followed
/// by that many characters. Every character of every field is checked
/// against its field's character set (digits for numeric fields, printable
/// ASCII 0x20..0x7E for alphanumeric fields).
///
/// Err messages: "iso8583: bad mti" (fewer than four characters or a
/// non-digit MTI); "iso8583: bad bitmap hex" (bitmap characters missing or
/// not hex); "iso8583: bad bitmap length" (bit 1 set but the secondary
/// bitmap is absent); "iso8583: tertiary bitmap not supported" (bit 65
/// set); "iso8583: unknown field number" (a set bit outside the
/// documented dictionary); "iso8583: declared field missing" (a declared
/// field has no characters at all); "iso8583: length overrun" (a declared
/// field or length prefix runs past the end); "iso8583: bad field length"
/// (a length prefix is not a decimal number or exceeds the field maximum);
/// "iso8583: bad field value" (a character outside the field's character
/// set); "iso8583: trailing data" (characters left after the last field).
/// Complexity: O(message length).
pub fn iso8583_parse(text: Str) -> Result[Iso8583Message, Str] {
  let n = text.len();
  if n < _MTI_LEN {
    return _err_msg("iso8583: bad mti");
  }
  let mti = string.str_slice(text, 0, _MTI_LEN);
  if !_mti_ok(mti) {
    return _err_msg("iso8583: bad mti");
  }
  var pos = _MTI_LEN;
  if n - pos < _HEX_BITMAP_LEN {
    return _err_msg("iso8583: bad bitmap hex");
  }
  let b0 = _hex_val(_byte_at(text, pos));
  if b0 < 0 {
    return _err_msg("iso8583: bad bitmap hex");
  }
  var want = _HEX_BITMAP_LEN;
  if (b0 / 8) % 2 == 1 {
    want = _HEX_FULL_LEN;
  }
  if n - pos < want {
    return _err_msg("iso8583: bad bitmap length");
  }
  let bitmap_text = string.str_slice(text, pos, pos + want);
  var nibbles = Vec[Int].new();
  let be = _bitmap_parse_text(bitmap_text, &mut nibbles);
  if be.len() > 0 {
    return _err_msg(be);
  }
  pos = pos + want;
  var numbers = Vec[Int].new();
  let de = _declared_numbers(&nibbles, &mut numbers);
  if de.len() > 0 {
    return _err_msg(de);
  }
  var values = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < numbers.len() {
    let num: Int = numbers[i];
    let kind = _field_kind(num);
    var length = 0;
    if _is_variable_kind(kind) {
      var plen = 2;
      if kind == 4 {
        plen = 3;
      }
      if pos >= n {
        return _err_msg("iso8583: declared field missing");
      }
      if n - pos < plen {
        return _err_msg("iso8583: length overrun");
      }
      length = _digits_int(text, pos, plen);
      if length < 0 {
        return _err_msg("iso8583: bad field length");
      }
      pos = pos + plen;
      if length > _field_max_len(num) {
        return _err_msg("iso8583: bad field length");
      }
    } else {
      if pos >= n {
        return _err_msg("iso8583: declared field missing");
      }
      length = _field_fixed_len(num);
    }
    if n - pos < length {
      return _err_msg("iso8583: length overrun");
    }
    let v = _bytes_of_range(text, pos, pos + length);
    if !_value_ok(kind, &v) {
      return _err_msg("iso8583: bad field value");
    }
    values.push(v);
    pos = pos + length;
    i = i + 1;
  }
  if pos < n {
    return _err_msg("iso8583: trailing data");
  }
  let msg = Iso8583Message{
    mti: mti;
    has_secondary: _bit_set(&nibbles, 1);
    field_numbers: numbers;
    field_values: values;
  };
  return _ok_msg(msg);
}

// --------------------------------------------------
//  Bitmap API
// --------------------------------------------------

/// Parse standalone bitmap text into the field numbers it declares.
///
/// Accepted forms: 16 or 32 hex digits (upper- or lowercase), or 64 or 128
/// characters of '0'/'1'. Bit 1 is MSB-first and marks the presence of the
/// secondary bitmap: 16/64-digit text may not set it
/// ("iso8583: bad bitmap length"); in 32/128-digit text, bit 1 clear with
/// any secondary bit set is "iso8583: unexpected secondary bitmap", and
/// setting bit 65 (a tertiary bitmap) is
/// "iso8583: tertiary bitmap not supported". Every other set bit is
/// resolved through the field dictionary; unknown numbers are
/// "iso8583: unknown field number". Bitmap text of any other length is
/// "iso8583: bad bitmap length"; a bad character is
/// "iso8583: bad bitmap hex" or "iso8583: bad bitmap binary".
/// Complexity: O(1) (at most 128 bits).
pub fn iso8583_bitmap_parse(bitmap: Str) -> Result[Iso8583Bitmap, Str] {
  var nibbles = Vec[Int].new();
  let be = _bitmap_parse_text(bitmap, &mut nibbles);
  if be.len() > 0 {
    return _err_bitmap(be);
  }
  var numbers = Vec[Int].new();
  let de = _declared_numbers(&nibbles, &mut numbers);
  if de.len() > 0 {
    return _err_bitmap(de);
  }
  let b = Iso8583Bitmap{
    has_secondary: _bit_set(&nibbles, 1);
    numbers: numbers;
  };
  return _ok_bitmap(b);
}

/// Canonical hex bitmap for `numbers`: 16 uppercase hex digits, or 32 when
/// any number is 65 or above (a secondary bitmap is then required).
///
/// Err("iso8583: unknown field number") when a number is below 2, above
/// 128 or outside the documented dictionary;
/// Err("iso8583: field numbers out of order") when the vector is not
/// strictly ascending. An empty vector yields the all-zero primary bitmap.
/// Complexity: O(numbers + 128 bits).
pub fn iso8583_bitmap_of(numbers: &Vec[Int]) -> Result[Str, Str] {
  let ne = _numbers_ok(numbers);
  if ne.len() > 0 {
    return _err_str(ne);
  }
  return _ok_str(_bitmap_hex(numbers, _any_secondary(numbers)));
}

/// The canonical bitmap hex of a message (derived from its field numbers
/// and `has_secondary`; uppercase, 16 or 32 digits). Assumes a well-formed
/// message, which is the only kind `iso8583_parse` and
/// `iso8583_build_message` produce. Complexity: O(fields).
pub fn iso8583_bitmap_hex(m: &Iso8583Message) -> Str {
  let numbers: Vec[Int] = m.field_numbers;
  return _bitmap_hex(&numbers, m.has_secondary);
}

// --------------------------------------------------
//  Building
// --------------------------------------------------

/// Build a message value from field numbers and parallel field values.
///
/// `numbers` must be strictly ascending, in 2..128 and inside the
/// documented dictionary; `values[i]` must match `numbers[i]`'s length rule
/// and character set. `has_secondary` is derived: true exactly when some
/// number is 65 or above.
///
/// Err("iso8583: bad mti"), Err("iso8583: unknown field number"),
/// Err("iso8583: field numbers out of order"),
/// Err("iso8583: field numbers/values length mismatch"),
/// Err("iso8583: bad field length"), Err("iso8583: bad field value") --
/// all deterministic and documented in SPEC.md.
/// Complexity: O(total value bytes).
pub fn iso8583_build_message(mti: Str, numbers: &Vec[Int], values: &Vec[Vec[UInt8]]) -> Result[Iso8583Message, Str] {
  if !_mti_ok(mti) {
    return _err_msg("iso8583: bad mti");
  }
  let ne = _numbers_ok(numbers);
  if ne.len() > 0 {
    return _err_msg(ne);
  }
  let ve = _values_ok(numbers, values);
  if ve.len() > 0 {
    return _err_msg(ve);
  }
  let nums = _copy_ints(numbers);
  let vals = _copy_values(values);
  let msg = Iso8583Message{
    mti: mti;
    has_secondary: _any_secondary(&nums);
    field_numbers: nums;
    field_values: vals;
  };
  return _ok_msg(msg);
}

/// Build one ISO 8583 ASCII message from field numbers and parallel field
/// values, computing the bitmap from the numbers.
///
/// Err messages are those of `iso8583_build_message` plus
/// `iso8583_format` (which cannot fail on a freshly built message).
/// Complexity: O(total value bytes).
pub fn iso8583_build(mti: Str, numbers: &Vec[Int], values: &Vec[Vec[UInt8]]) -> Result[Str, Str] {
  let mr = iso8583_build_message(mti, numbers, values);
  if !mr.is_ok {
    return _err_str(mr.error);
  }
  let m: Iso8583Message = mr.value;
  return iso8583_format(&m);
}

/// Build one ISO 8583 ASCII message while checking a caller-supplied
/// bitmap (16/32 hex digits or 64/128 binary digits) against the fields.
///
/// The bitmap must declare exactly the same field numbers, in the same
/// order, and its secondary-bitmap presence must equal "some number is 65
/// or above"; otherwise Err("iso8583: bitmap/fields mismatch"). Bitmap
/// syntax errors are those of `iso8583_bitmap_parse`; field/value errors
/// are those of `iso8583_build`.
/// Complexity: O(total value bytes + 128 bits).
pub fn iso8583_build_with_bitmap(mti: Str, bitmap: Str, numbers: &Vec[Int], values: &Vec[Vec[UInt8]]) -> Result[Str, Str] {
  let br = iso8583_bitmap_parse(bitmap);
  if !br.is_ok {
    return _err_str(br.error);
  }
  let b: Iso8583Bitmap = br.value;
  if b.numbers.len() != numbers.len() {
    return _err_str("iso8583: bitmap/fields mismatch");
  }
  var i = 0;
  while i < b.numbers.len() {
    let bn: Int = b.numbers[i];
    let mn: Int = numbers[i];
    if bn != mn {
      return _err_str("iso8583: bitmap/fields mismatch");
    }
    i = i + 1;
  }
  if b.has_secondary != _any_secondary(numbers) {
    return _err_str("iso8583: bitmap/fields mismatch");
  }
  return iso8583_build(mti, numbers, values);
}

/// Serialize a message back to ISO 8583 ASCII text.
///
/// The MTI and every field value are re-validated, the numbers must still
/// be strictly ascending and known, the field/value vectors must stay
/// parallel, and `has_secondary` may not be false while a number is 65 or
/// above (a true value with no secondary field is preserved, as parsed).
/// For a message returned by `iso8583_parse` or
/// `iso8583_build_message` the call cannot fail and
/// `iso8583_parse(iso8583_format(m))` reproduces the same field set; the
/// bitmap is emitted in canonical uppercase.
/// Err messages: "iso8583: bad mti",
/// "iso8583: field numbers/values length mismatch",
/// "iso8583: unknown field number",
/// "iso8583: field numbers out of order",
/// "iso8583: bad field length", "iso8583: bad field value",
/// "iso8583: bitmap/fields mismatch".
/// Complexity: O(total value bytes).
pub fn iso8583_format(m: &Iso8583Message) -> Result[Str, Str] {
  if !_mti_ok(m.mti) {
    return _err_str("iso8583: bad mti");
  }
  let numbers: Vec[Int] = m.field_numbers;
  let values: Vec[Vec[UInt8]] = m.field_values;
  let ne = _numbers_ok(&numbers);
  if ne.len() > 0 {
    return _err_str(ne);
  }
  let ve = _values_ok(&numbers, &values);
  if ve.len() > 0 {
    return _err_str(ve);
  }
  if _any_secondary(&numbers) && !m.has_secondary {
    return _err_str("iso8583: bitmap/fields mismatch");
  }
  let bh = _bitmap_hex(&numbers, m.has_secondary);
  var sb = Vec[UInt8].new();
  builder.sb_push_str(&mut sb, m.mti);
  builder.sb_push_str(&mut sb, bh);
  var i = 0;
  while i < values.len() {
    let num: Int = numbers[i];
    let kind = _field_kind(num);
    let v: Vec[UInt8] = values[i];
    if _is_variable_kind(kind) {
      var width = 2;
      if kind == 4 {
        width = 3;
      }
      _push_prefix(&mut sb, v.len(), width);
    }
    _push_bytes(&mut sb, &v);
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&sb));
}

// --------------------------------------------------
//  Message accessors
// --------------------------------------------------

/// The message type indicator (4 ASCII digits). Complexity: O(1).
pub fn iso8583_mti(m: &Iso8583Message) -> Str {
  return m.mti;
}

/// True when a secondary bitmap is part of the message (bit 1 set).
/// Complexity: O(1).
pub fn iso8583_has_secondary(m: &Iso8583Message) -> Bool {
  return m.has_secondary;
}

/// Number of present fields. Complexity: O(1).
pub fn iso8583_field_count(m: &Iso8583Message) -> Int {
  return m.field_numbers.len();
}

/// Field number at position `i` (0-based, ascending order); -1 when `i` is
/// negative or beyond the last field. Complexity: O(1).
pub fn iso8583_field_number(m: &Iso8583Message, i: Int) -> Int {
  if i < 0 || i >= m.field_numbers.len() {
    return -1;
  }
  let n: Int = m.field_numbers[i];
  return n;
}

/// Field value at position `i` as a Str ("" when `i` is out of range).
/// Values are guaranteed printable by construction. Complexity: O(value
/// length).
pub fn iso8583_field_value(m: &Iso8583Message, i: Int) -> Str {
  if i < 0 || i >= m.field_values.len() {
    return "";
  }
  let v: Vec[UInt8] = m.field_values[i];
  return _bytes_to_str(&v);
}

/// Position of field `number` in the message; -1 when the field is absent.
/// Complexity: O(fields).
pub fn iso8583_field_index(m: &Iso8583Message, number: Int) -> Int {
  var i = 0;
  while i < m.field_numbers.len() {
    let n: Int = m.field_numbers[i];
    if n == number {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// True when field `number` is present. Complexity: O(fields).
pub fn iso8583_has_field(m: &Iso8583Message, number: Int) -> Bool {
  return iso8583_field_index(m, number) >= 0;
}

/// Value of field `number` as a Str.
///
/// Err("iso8583: field not present") when the field is absent; no other
/// error is possible on a well-formed message. Complexity: O(fields +
/// value length).
pub fn iso8583_get(m: &Iso8583Message, number: Int) -> Result[Str, Str] {
  let idx = iso8583_field_index(m, number);
  if idx < 0 {
    return _err_str("iso8583: field not present");
  }
  let v: Vec[UInt8] = m.field_values[idx];
  return _ok_str(_bytes_to_str(&v));
}

// --------------------------------------------------
//  Field dictionary accessors
// --------------------------------------------------

/// True when `number` is one of the documented fields. Complexity: O(1).
pub fn iso8583_is_known_field(number: Int) -> Bool {
  return _field_kind(number) != 0;
}

/// True when `number` is a documented variable-length field (LLVAR or
/// LLLVAR). Unknown and fixed-length fields return false. Complexity: O(1).
pub fn iso8583_is_variable_field(number: Int) -> Bool {
  return _is_variable_kind(_field_kind(number));
}

/// Maximum value length of field `number`: the fixed length for
/// fixed-length fields, the maximum for LLVAR/LLLVAR fields, and -1 for
/// unknown numbers. Complexity: O(1).
pub fn iso8583_field_max_length(number: Int) -> Int {
  let kind = _field_kind(number);
  if kind == 0 {
    return -1;
  }
  if _is_variable_kind(kind) {
    return _field_max_len(number);
  }
  return _field_fixed_len(number);
}
