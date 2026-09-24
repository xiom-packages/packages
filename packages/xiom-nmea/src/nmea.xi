// XIOM -- xiom.nmea: NMEA 0183 sentence parsing
// Port task: replace the xiom.nmea placeholder with a real, tested, pure-XIOM
// package (checksum, sentence type, comma fields, GGA/RMC accessors).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a sentence is "$<type>,<field>,<field>,...*HH" (or '!' instead of
// '$' for encapsulated/AIS sentences). Parsing is byte-oriented and
// stateless: every entry point rescans its input and returns plain values, so
// no sentence object is allocated and there is no partially initialized
// state. See SPEC.md for the grammar, conversions and error catalog.
//
// Language notes (XIOM v0.61.3):
//   * free functions only: no self methods, no lambdas, no Vec[StructType];
//   * Str values are never compared with `==` (BUG 17: `==` on a Str read from
//     a Vec[Str] element lowers to a pointer comparison); every decision below
//     is made on single bytes instead;
//   * Vec[Str] element reads are bound with a typed `let` before use;
//   * string.byte_at results are widened with `as Int` before arithmetic;
//   * all arithmetic is scaled 64-bit integer math; no Vec[Float64];
//   * Ok/Err are constructed only in the tiny leaf helpers below
//     (constructing a Result inside a larger function miscompiles).

module xiom.nmea

use xiom.string;
use xiom.math;

const _NMEA_BANG: UInt8 = 33u8;
const _NMEA_DOLLAR: UInt8 = 36u8;
const _NMEA_STAR: UInt8 = 42u8;
const _NMEA_PLUS: UInt8 = 43u8;
const _NMEA_COMMA: UInt8 = 44u8;
const _NMEA_MINUS: UInt8 = 45u8;
const _NMEA_DOT: UInt8 = 46u8;
const _NMEA_ZERO: UInt8 = 48u8;
const _NMEA_NINE: UInt8 = 57u8;
const _NMEA_A: UInt8 = 65u8;
const _NMEA_C: UInt8 = 67u8;
const _NMEA_E: UInt8 = 69u8;
const _NMEA_F: UInt8 = 70u8;
const _NMEA_G: UInt8 = 71u8;
const _NMEA_M: UInt8 = 77u8;
const _NMEA_N: UInt8 = 78u8;
const _NMEA_R: UInt8 = 82u8;
const _NMEA_S: UInt8 = 83u8;
const _NMEA_V: UInt8 = 86u8;
const _NMEA_W: UInt8 = 87u8;
const _NMEA_LOWER_A: UInt8 = 97u8;
const _NMEA_LOWER_E: UInt8 = 101u8;
const _NMEA_LOWER_F: UInt8 = 102u8;
const _NMEA_LOWER_N: UInt8 = 110u8;
const _NMEA_LOWER_S: UInt8 = 115u8;
const _NMEA_LOWER_V: UInt8 = 118u8;
const _NMEA_LOWER_W: UInt8 = 119u8;
const _NMEA_INT_MAX_DIV10: Int = 922337203685477580;
const _NMEA_INT_MAX_LAST_DIGIT: Int = 7;
const _NMEA_INT_MAX_DIV100: Int = 92233720368547757;

// ---------------------------------------------------------------------------
// Byte helpers
// ---------------------------------------------------------------------------

// Index of the first '!' or '$' (the sentence start delimiter), or -1.
fn _start_index(s: Str) -> Int {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _NMEA_DOLLAR || b == _NMEA_BANG { return i; }
    i = i + 1;
  }
  return -1;
}

// Index of the first occurrence of target at or after `from`, or -1.
fn _find_byte(s: Str, from: Int, target: UInt8) -> Int {
  var i = from;
  while i < s.len() {
    if string.byte_at(s, i) == target { return i; }
    i = i + 1;
  }
  return -1;
}

// Decimal value of s[start, end); -1 when the run is empty or not all digits.
fn _digits_value(s: Str, start: Int, end: Int) -> Int {
  if start >= end { return -1; }
  var acc = 0;
  var i = start;
  while i < end {
    let b = string.byte_at(s, i);
    if b < _NMEA_ZERO || b > _NMEA_NINE { return -1; }
    acc = acc * 10 + ((b as Int) - 48);
    i = i + 1;
  }
  return acc;
}

// Hex value of one byte (either case), or -1.
fn _hex_val(b: UInt8) -> Int {
  if b >= _NMEA_ZERO && b <= _NMEA_NINE { return (b as Int) - 48; }
  if b >= _NMEA_A && b <= _NMEA_F { return (b as Int) - 55; }
  if b >= _NMEA_LOWER_A && b <= _NMEA_LOWER_F { return (b as Int) - 87; }
  return -1;
}

// Case-insensitive ASCII letter equality.
fn _byte_eq_ci(a: UInt8, b: UInt8) -> Bool {
  if a == b { return true; }
  let d = (a as Int) - (b as Int);
  if d == 32 || d == -32 { return true; }
  return false;
}

// True when the sentence type (e.g. GPGGA) ends with the three letters c0 c1
// c2, ignoring case.
fn _type_ends(s: Str, c0: UInt8, c1: UInt8, c2: UInt8) -> Bool {
  let t = nmea_sentence_type(s);
  let n = t.len();
  if n < 3 { return false; }
  if !_byte_eq_ci(string.byte_at(t, n - 3), c0) { return false; }
  if !_byte_eq_ci(string.byte_at(t, n - 2), c1) { return false; }
  return _byte_eq_ci(string.byte_at(t, n - 1), c2);
}

fn _is_gga(s: Str) -> Bool {
  return _type_ends(s, _NMEA_G, _NMEA_G, _NMEA_A);
}

fn _is_rmc(s: Str) -> Bool {
  return _type_ends(s, _NMEA_R, _NMEA_M, _NMEA_C);
}

// +1 for N/E, -1 for S/W, 0 for anything else.
fn _hemi_sign(hemi: Str) -> Int {
  if hemi.len() != 1 { return 0; }
  let b = string.byte_at(hemi, 0);
  if b == _NMEA_N || b == _NMEA_LOWER_N { return 1; }
  if b == _NMEA_E || b == _NMEA_LOWER_E { return 1; }
  if b == _NMEA_S || b == _NMEA_LOWER_S { return -1; }
  if b == _NMEA_W || b == _NMEA_LOWER_W { return -1; }
  return 0;
}

// Result constructors live in these leaves: constructing a Result inside a
// larger function miscompiles on XIOM v0.61.3 (see the module header).
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// XOR checksum of a sentence payload.
/// Params: s - any text; the payload is the byte run after the first '$' or
/// '!' up to the first '*' that follows it (or up to the end of the string
/// when there is no '*').
/// Returns: the XOR of every payload byte widened to Int, 0-255. Returns 0
/// when the string contains no '$' or '!' at all (the checksum is "absent");
/// note that a payload whose XOR genuinely is 0 also returns 0.
/// Examples: the standard GPGGA fixture -> 0x47 (71); "$GPGGA,1,2*55" -> 85.
/// Error case: none.
/// Complexity: O(len(s)).
pub fn nmea_compute_checksum(s: Str) -> Int {
  let start = _start_index(s);
  if start < 0 { return 0; }
  var end = s.len();
  let star = _find_byte(s, start + 1, _NMEA_STAR);
  if star >= 0 { end = star; }
  var acc = 0;
  var i = start + 1;
  while i < end {
    acc = math.bit_xor(acc, (string.byte_at(s, i) as Int));
    i = i + 1;
  }
  return acc;
}

/// Verify the checksum suffix of a sentence.
/// Params: s - the sentence text.
/// Grammar: the suffix is the two hex digits immediately after the first '*'
/// that follows the start delimiter; anything after them (e.g. CR LF) is
/// ignored. Hex digits may be either case. The checksum is recomputed with
/// nmea_compute_checksum and compared as an integer.
/// Returns: true only when a start delimiter, a '*' and two hex digits are
/// present and the recomputed checksum matches.
/// Error case: none -- missing start, missing '*', a short or non-hex suffix
/// and a mismatch all return false.
/// Complexity: O(len(s)).
pub fn nmea_checksum_ok(s: Str) -> Bool {
  let start = _start_index(s);
  if start < 0 { return false; }
  let star = _find_byte(s, start + 1, _NMEA_STAR);
  if star < 0 { return false; }
  if star + 2 >= s.len() { return false; }
  let hi = _hex_val(string.byte_at(s, star + 1));
  let lo = _hex_val(string.byte_at(s, star + 2));
  if hi < 0 || lo < 0 { return false; }
  return nmea_compute_checksum(s) == hi * 16 + lo;
}

/// Sentence type (talker + formatter), e.g. "GPGGA" or "AIVDM".
/// Params: s - the sentence text.
/// Grammar: the bytes between the start delimiter (first '$' or '!') and the
/// first ',' after it. The type is returned verbatim, including its case.
/// Returns: the type text; "" when there is no '$'/'!', when there is no ','
/// after it, or when a '*' appears before the first ','
/// (e.g. "$GPGGA*47").
/// Error case: none.
/// Complexity: O(len(s)).
pub fn nmea_sentence_type(s: Str) -> Str {
  let start = _start_index(s);
  if start < 0 { return ""; }
  let comma = _find_byte(s, start + 1, _NMEA_COMMA);
  if comma < 0 { return ""; }
  let star = _find_byte(s, start + 1, _NMEA_STAR);
  if star >= 0 && star < comma { return ""; }
  return string.str_slice(s, start + 1, comma);
}

/// Comma-split payload fields, checksum suffix removed.
/// Params: s - the sentence text.
/// Grammar: the fields are the bytes after the first ',' (the one that ends
/// the sentence type) up to the first '*' after that ',' (or up to the end of
/// the string when there is no '*'). Splitting is on single ',' bytes and is
/// exhaustive: empty fields are kept, so "a,,b," yields four fields, the last
/// two empty.
/// Returns: the fields in order as a fresh Vec[Str]; an empty Vec when there
/// is no '$'/'!' or no ',' (a sentence with no payload at all).
/// Error case: none.
/// Complexity: O(len(s)).
pub fn nmea_fields(s: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let start = _start_index(s);
  if start < 0 { return out; }
  let comma = _find_byte(s, start + 1, _NMEA_COMMA);
  if comma < 0 { return out; }
  var end = s.len();
  let star = _find_byte(s, comma + 1, _NMEA_STAR);
  if star >= 0 { end = star; }
  var field_start = comma + 1;
  var i = comma + 1;
  while i < end {
    if string.byte_at(s, i) == _NMEA_COMMA {
      out.push(string.str_slice(s, field_start, i));
      field_start = i + 1;
    }
    i = i + 1;
  }
  out.push(string.str_slice(s, field_start, end));
  return out;
}

/// One payload field by index, counted from 0 after the sentence type.
/// Params: s - the sentence text; i - the field index.
/// Returns: the field text; "" when i is negative or past the last field (so
/// a one-past-the-end probe is indistinguishable from a present empty field).
/// Error case: none.
/// Complexity: O(len(s)).
pub fn nmea_field(s: Str, i: Int) -> Str {
  if i < 0 { return ""; }
  let fields = nmea_fields(s);
  if i >= fields.len() { return ""; }
  let v: Str = fields[i];
  return v;
}

/// Number of payload fields, counted after the sentence type.
/// Params: s - the sentence text.
/// Returns: nmea_fields(s).len(); 0 when the sentence is malformed (no
/// '$'/'!' or no ',').
/// Error case: none.
/// Complexity: O(len(s)).
pub fn nmea_field_count(s: Str) -> Int {
  let fields = nmea_fields(s);
  return fields.len();
}

/// Convert NMEA degrees/minutes text to micro degrees.
/// Params: value - "ddmm.mmmm" for latitudes or "dddmm.mmmm" for longitudes
/// (the last two integer digits are whole minutes); hemi - one of N, S, E or
/// W (either case). The value text itself must not carry a sign.
/// Grammar: 4 or 5 integer digits, each ASCII 0-9, optionally followed by
/// '.' and one or more fraction digits. Whole minutes must be 00-59. Up to
/// four fraction digits are scaled in; further fraction digits are validated
/// but truncated. Fraction digits may be omitted ("6011" == "6011.000").
/// Returns: Ok(micro) where
/// micro = degrees*1_000_000 + (minutes_scaled * 5) / 3 and minutes_scaled is
/// the minutes text scaled by 10^4; N and E are positive, S and W negative.
/// The division truncates toward zero, so the magnitude never exceeds the
/// exact value. Examples: ("6011.000","N") -> Ok(60183333);
/// ("02431.000","E") -> Ok(24516666); ("4807.038","N") -> Ok(48117300).
/// Error case: Err("nmea: empty coordinate") for an empty value;
/// Err("nmea: invalid coordinate: <value>") for a malformed value (wrong
/// digit count, non-digit byte, second '.', or minutes 60-99);
/// Err("nmea: invalid hemisphere: <hemi>") when hemi is not exactly one of
/// N/S/E/W. Value errors are reported before hemisphere errors.
/// Complexity: O(len(value) + len(hemi)).
pub fn nmea_dm_to_micro_deg(value: Str, hemi: Str) -> Result[Int, Str] {
  let n = value.len();
  if n == 0 {
    return _err_int("nmea: empty coordinate");
  }
  let dot = _find_byte(value, 0, _NMEA_DOT);
  var int_end = n;
  if dot >= 0 { int_end = dot; }
  if dot >= 0 && _find_byte(value, dot + 1, _NMEA_DOT) >= 0 {
    return _err_int("nmea: invalid coordinate: " + value);
  }
  if int_end != 4 && int_end != 5 {
    return _err_int("nmea: invalid coordinate: " + value);
  }
  var i = 0;
  while i < int_end {
    let b = string.byte_at(value, i);
    if b < _NMEA_ZERO || b > _NMEA_NINE {
      return _err_int("nmea: invalid coordinate: " + value);
    }
    i = i + 1;
  }
  let minutes = _digits_value(value, int_end - 2, int_end);
  if minutes < 0 || minutes > 59 {
    return _err_int("nmea: invalid coordinate: " + value);
  }
  let degrees = _digits_value(value, 0, int_end - 2);
  var frac = 0;
  var k = 0;
  var j = n;
  if dot >= 0 { j = dot + 1; }
  while j < n {
    let b = string.byte_at(value, j);
    if b < _NMEA_ZERO || b > _NMEA_NINE {
      return _err_int("nmea: invalid coordinate: " + value);
    }
    if k < 4 {
      frac = frac * 10 + ((b as Int) - 48);
    }
    k = k + 1;
    j = j + 1;
  }
  while k < 4 {
    frac = frac * 10;
    k = k + 1;
  }
  let sign = _hemi_sign(hemi);
  if sign == 0 {
    return _err_int("nmea: invalid hemisphere: " + hemi);
  }
  let minutes_scaled = minutes * 10000 + frac;
  var micro = degrees * 1000000 + (minutes_scaled * 5) / 3;
  if sign < 0 {
    micro = 0 - micro;
  }
  return _ok_int(micro);
}

/// GGA fix quality (field 6 of the sentence: 0 = no fix ... 8 = simulated).
/// Params: s - the sentence text; the type must end with "GGA" (either case),
/// so GPGGA, GNGGA, GLGGA, ... all qualify.
/// Returns: Ok(quality) when the field is a non-empty run of ASCII digits
/// (any width; no range check).
/// Error case: Err("nmea: not a GGA sentence");
/// Err("nmea: missing GGA quality") when the field is empty or absent;
/// Err("nmea: invalid GGA quality: <field>") when it is not all digits.
/// Complexity: O(len(s)).
pub fn nmea_gga_quality(s: Str) -> Result[Int, Str] {
  if !_is_gga(s) { return _err_int("nmea: not a GGA sentence"); }
  let raw: Str = nmea_field(s, 5);
  if raw.len() == 0 { return _err_int("nmea: missing GGA quality"); }
  let v = _digits_value(raw, 0, raw.len());
  if v < 0 { return _err_int("nmea: invalid GGA quality: " + raw); }
  return _ok_int(v);
}

/// GGA satellites used in the fix (field 7 of the sentence).
/// Params: s - the sentence text; the type must end with "GGA" (either case).
/// Returns: Ok(count) when the field is a non-empty run of ASCII digits.
/// Error case: Err("nmea: not a GGA sentence");
/// Err("nmea: missing GGA satellites") when the field is empty or absent;
/// Err("nmea: invalid GGA satellites: <field>") when it is not all digits.
/// Complexity: O(len(s)).
pub fn nmea_gga_satellites(s: Str) -> Result[Int, Str] {
  if !_is_gga(s) { return _err_int("nmea: not a GGA sentence"); }
  let raw: Str = nmea_field(s, 6);
  if raw.len() == 0 { return _err_int("nmea: missing GGA satellites"); }
  let v = _digits_value(raw, 0, raw.len());
  if v < 0 { return _err_int("nmea: invalid GGA satellites: " + raw); }
  return _ok_int(v);
}

/// GGA antenna altitude (field 9 of the sentence) in centimeters.
/// Params: s - the sentence text; the type must end with "GGA" (either case).
/// Grammar: an optional '+' or '-', then ASCII digits, optionally followed by
/// '.' and one or more digits. The value is meters; centimeters = integer
/// meters * 100 + the first two fraction digits (right-padded with zeros);
/// further fraction digits are truncated toward zero. "-" applies to the
/// whole value. Examples: "545.4" -> Ok(54540); "-10.5" -> Ok(-1050);
/// "545.456" -> Ok(54545).
/// Returns: Ok(centimeters).
/// Error case: Err("nmea: not a GGA sentence");
/// Err("nmea: missing GGA altitude") when the field is empty or absent;
/// Err("nmea: invalid GGA altitude: <field>") when the text is malformed
/// (no digit, a second '.', an unexpected byte);
/// Err("nmea: GGA altitude too large") when the magnitude would overflow the
/// 64-bit signed range.
/// Complexity: O(len(s)).
pub fn nmea_gga_altitude_cm(s: Str) -> Result[Int, Str] {
  if !_is_gga(s) { return _err_int("nmea: not a GGA sentence"); }
  let raw: Str = nmea_field(s, 8);
  if raw.len() == 0 { return _err_int("nmea: missing GGA altitude"); }
  var i = 0;
  var neg = false;
  let first = string.byte_at(raw, 0);
  if first == _NMEA_MINUS {
    neg = true;
    i = 1;
  } elif first == _NMEA_PLUS {
    i = 1;
  }
  var int_mag = 0;
  var frac_mag = 0;
  var frac_digits = 0;
  var seen_digit = false;
  var seen_dot = false;
  var bad = false;
  while i < raw.len() {
    let b = string.byte_at(raw, i);
    if b >= _NMEA_ZERO && b <= _NMEA_NINE {
      let d = (b as Int) - 48;
      if seen_dot {
        if frac_digits < 2 {
          frac_mag = frac_mag * 10 + d;
          frac_digits = frac_digits + 1;
        }
      } else {
        if int_mag > _NMEA_INT_MAX_DIV10 {
          return _err_int("nmea: GGA altitude too large");
        }
        if int_mag == _NMEA_INT_MAX_DIV10 && d > _NMEA_INT_MAX_LAST_DIGIT {
          return _err_int("nmea: GGA altitude too large");
        }
        int_mag = int_mag * 10 + d;
      }
      seen_digit = true;
    } elif b == _NMEA_DOT {
      if seen_dot { bad = true; }
      seen_dot = true;
    } else {
      bad = true;
    }
    i = i + 1;
  }
  if bad || !seen_digit {
    return _err_int("nmea: invalid GGA altitude: " + raw);
  }
  while frac_digits < 2 {
    frac_mag = frac_mag * 10;
    frac_digits = frac_digits + 1;
  }
  if int_mag > _NMEA_INT_MAX_DIV100 {
    return _err_int("nmea: GGA altitude too large");
  }
  var cm = int_mag * 100 + frac_mag;
  if neg {
    cm = 0 - cm;
  }
  return _ok_int(cm);
}

/// RMC data validity (field 2 of the sentence: 'A' = valid, 'V' = void).
/// Params: s - the sentence text; the type must end with "RMC" (either case).
/// Returns: Ok(true) for 'A'/'a', Ok(false) for 'V'/'v'.
/// Error case: Err("nmea: not an RMC sentence");
/// Err("nmea: missing RMC status") when the field is empty or absent;
/// Err("nmea: invalid RMC status: <field>") for anything else.
/// Complexity: O(len(s)).
pub fn nmea_rmc_valid(s: Str) -> Result[Bool, Str] {
  if !_is_rmc(s) { return _err_bool("nmea: not an RMC sentence"); }
  let raw: Str = nmea_field(s, 1);
  if raw.len() == 0 { return _err_bool("nmea: missing RMC status"); }
  if raw.len() == 1 {
    let b = string.byte_at(raw, 0);
    if b == _NMEA_A || b == _NMEA_LOWER_A { return _ok_bool(true); }
    if b == _NMEA_V || b == _NMEA_LOWER_V { return _ok_bool(false); }
  }
  return _err_bool("nmea: invalid RMC status: " + raw);
}
