// XIOM -- xiom.maidenhead: integer-only Maidenhead grid locator codec
// Port task: greenfield pure-XIOM Maidenhead (QTH) locator encoder/decoder
// over integer microdegrees (no FFI, no Float64).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - Coordinates are carried as integer microdegrees (ud): 1 degree = 1,000,000
//   ud. Latitude runs over [-90_000_000, 90_000_000] and longitude over
//   [-180_000_000, 180_000_000], both inclusive. No Float64 is used anywhere,
//   so every result is exact and platform-independent.
// - A locator is a sequence of one to four (longitude, latitude) level pairs
//   following the standard alternating lon-first Maidenhead scheme:
//     level 0 field:           18 letters A-R, 20 deg lon x 10 deg lat;
//     level 1 square:          10 digits 0-9,  2 deg lon x  1 deg lat;
//     level 2 subsquare:       24 letters A-X,  5' lon x 2.5' lat;
//     level 3 extended square: 10 digits 0-9, 0.5' lon x 0.25' lat.
//   Accepted lengths are therefore 2, 4, 6 or 8 characters; canonical output
//   is uppercase, and input is case-insensitive (ASCII A-Z folded to upper).
// - Encoding is exact integer arithmetic on the common 1/240-degree grid: the
//   longitude cell index over the whole sphere is
//   floor((lon_ud + 180_000_000) * 3 / 25_000) and the latitude index is
//   floor((lat_ud + 90_000_000) * 6 / 25_000), each over 43_200 cells
//   (18 * 10 * 24 * 10). The four locator parts are the base-2400, 240, 10
//   and 1 digits of those indices. A point exactly on a cell edge selects the
//   upper (east/north) cell, and the inclusive upper bounds lat = 90_000_000
//   and lon = 180_000_000 fold into the northernmost/easternmost cell.
// - Decoding returns the inclusive integer-microdegree box whose points all
//   re-encode to the source locator, plus its center. Every valid locator
//   decodes to a non-empty box: the smallest cell (extended square) is
//   83_333.33 ud x 41_666.67 ud, wider than one ud on both axes.
//
// v0.61.3 notes that shaped this module: free functions only; no Vec at all;
// Ok/Err payloads are constructed only in the leaf helpers
// _ok_str/_err_str/_ok_box/_err_box/_ok_int/_err_int; every byte from
// xiom.string.byte_at is widened as `(x as Int) & 0xFF`; no string equality is
// performed here (callers compare via xiom.string.compare); Int division
// truncates toward zero (LLVM sdiv), which is why _div_ceil inspects the sign
// of the truncated remainder.

module xiom.maidenhead

use xiom.string;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Letters used by the field (A-R) and subsquare (A-X) levels.
const _MH_LETTERS: Str = "ABCDEFGHIJKLMNOPQRSTUVWX";
// Digits used by the square and extended-square levels.
const _MH_DIGITS: Str = "0123456789";

const _MH_LAT_MIN_UD: Int = -90000000;
const _MH_LAT_MAX_UD: Int = 90000000;
const _MH_LON_MIN_UD: Int = -180000000;
const _MH_LON_MAX_UD: Int = 180000000;

// Offset that moves the coordinate range onto the non-negative 1/240-degree
// grid: lon_ud + 180_000_000 and lat_ud + 90_000_000.
const _MH_LON_BASE_UD: Int = 180000000;
const _MH_LAT_BASE_UD: Int = 90000000;

// Full-grid cell index numerators: one microdegree advances the longitude
// index by 3/25_000 of a cell and the latitude index by 6/25_000 of a cell
// (a longitude cell is 1/120 degree = 25_000/3 ud, a latitude cell is
// 1/240 degree = 25_000/6 ud).
const _MH_LON_AXIS_NUM: Int = 3;
const _MH_LAT_AXIS_NUM: Int = 6;
const _MH_AXIS_DEN: Int = 25000;

// Cells per axis over the whole sphere: 18 * 10 * 24 * 10 = 43_200.
const _MH_AXIS_CELLS: Int = 43200;
// Digits-of-the-index steps for the field, square and subsquare levels; the
// extended square is the raw last digit (step 1).
const _MH_FIELD_STEP: Int = 2400;
const _MH_SQUARE_STEP: Int = 240;
const _MH_SUBSQUARE_STEP: Int = 10;
const _MH_EXT_STEP: Int = 1;

// Denominators that convert a full-grid cell index back to microdegrees:
// longitude cells are 1/120 degree = 25_000/3 ud, latitude cells 1/240 degree
// = 25_000/6 ud. _MH_CELL_OFFSET is 180_000_000 * 3 = 90_000_000 * 6.
const _MH_LON_CELL_DEN: Int = 3;
const _MH_LAT_CELL_DEN: Int = 6;
const _MH_CELL_OFFSET: Int = 540000000;

const _MH_FIELD_MAX: Int = 17;
const _MH_SUBSQUARE_MAX: Int = 23;

/// A decoded Maidenhead cell: the inclusive integer-microdegree box whose
/// points all re-encode to the source locator, plus the box center.
/// `length` is the character count of the source locator (2, 4, 6 or 8).
pub type MaidenheadBox = {
  length: Int;
  min_lat_ud: Int;
  min_lon_ud: Int;
  max_lat_ud: Int;
  max_lon_ud: Int;
  center_lat_ud: Int;
  center_lon_ud: Int;
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers; see the module header)
// ---------------------------------------------------------------------------

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(b) for Result[MaidenheadBox, Str].
fn _ok_box(b: MaidenheadBox) -> Result[MaidenheadBox, Str] {
  return Ok(b);
}

// Err(m) for Result[MaidenheadBox, Str].
fn _err_box(m: Str) -> Result[MaidenheadBox, Str] {
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

// ---------------------------------------------------------------------------
// Integer and byte helpers
// ---------------------------------------------------------------------------

// ceil(a / b) for b > 0, using truncating integer division (LLVM sdiv).
// a = q*b + r with q truncating toward zero and r signed like a; the result is
// q + 1 exactly when r > 0.
fn _div_ceil(a: Int, b: Int) -> Int {
  let q: Int = a / b;
  let r: Int = a % b;
  if r > 0 {
    return q + 1;
  }
  return q;
}

// The one-character string for alphabet value v (0..23). Caller guarantees
// the range.
fn _letter_char(v: Int) -> Str {
  return string.str_slice(_MH_LETTERS, v, v + 1);
}

// The one-character string for digit value v (0..9). Caller guarantees range.
fn _digit_char(v: Int) -> Str {
  return string.str_slice(_MH_DIGITS, v, v + 1);
}

// Byte value of s[i] as an Int in [0, 255].
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Value of an uppercase ASCII letter byte (A-Z -> 0..25); -1 otherwise.
fn _letter_value(b: Int) -> Int {
  if b >= 65 && b <= 90 {
    return b - 65;
  }
  return -1;
}

// Value of an ASCII digit byte (0-9 -> 0..9); -1 otherwise.
fn _digit_value(b: Int) -> Int {
  if b >= 48 && b <= 57 {
    return b - 48;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Locator validation
// ---------------------------------------------------------------------------

// First error message for an uppercased locator, or "" when it is valid.
// Length is checked before any character; positions are checked in locator
// order: field pair (letters A-R), square pair (digits 0-9), subsquare pair
// (letters A-X), extended square pair (digits 0-9). Callers fold ASCII case
// to uppercase first, so only uppercase ranges are accepted here.
fn _validate_err(up: Str) -> Str {
  let len: Int = up.len();
  if len == 0 {
    return "maidenhead: empty locator";
  }
  if len != 2 && len != 4 && len != 6 && len != 8 {
    return "maidenhead: invalid locator length";
  }
  let f0: Int = _letter_value(_byte(up, 0));
  if f0 < 0 || f0 > _MH_FIELD_MAX {
    return "maidenhead: invalid field letter";
  }
  let f1: Int = _letter_value(_byte(up, 1));
  if f1 < 0 || f1 > _MH_FIELD_MAX {
    return "maidenhead: invalid field letter";
  }
  if len >= 4 {
    let d2: Int = _digit_value(_byte(up, 2));
    if d2 < 0 {
      return "maidenhead: invalid square digit";
    }
    let d3: Int = _digit_value(_byte(up, 3));
    if d3 < 0 {
      return "maidenhead: invalid square digit";
    }
  }
  if len >= 6 {
    let s4: Int = _letter_value(_byte(up, 4));
    if s4 < 0 || s4 > _MH_SUBSQUARE_MAX {
      return "maidenhead: invalid subsquare letter";
    }
    let s5: Int = _letter_value(_byte(up, 5));
    if s5 < 0 || s5 > _MH_SUBSQUARE_MAX {
      return "maidenhead: invalid subsquare letter";
    }
  }
  if len >= 8 {
    let e6: Int = _digit_value(_byte(up, 6));
    if e6 < 0 {
      return "maidenhead: invalid extended square digit";
    }
    let e7: Int = _digit_value(_byte(up, 7));
    if e7 < 0 {
      return "maidenhead: invalid extended square digit";
    }
  }
  return "";
}

// Uppercase a locator and validate it; Ok(uppercase) or Err(message).
fn _checked_upper(locator: Str) -> Result[Str, Str] {
  let up: Str = string.str_upper(locator);
  let msg: Str = _validate_err(up);
  if msg.len() != 0 {
    return _err_str(msg);
  }
  return _ok_str(up);
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

// Raw encoder for a validated coordinate and length (2, 4, 6 or 8).
// The full-grid longitude index nl and latitude index ml select the field,
// square, subsquare and extended-square digits by division and modulo.
fn _encode_raw(lat_ud: Int, lon_ud: Int, length: Int) -> Str {
  var nl: Int = ((lon_ud + _MH_LON_BASE_UD) * _MH_LON_AXIS_NUM) / _MH_AXIS_DEN;
  if nl >= _MH_AXIS_CELLS {
    nl = _MH_AXIS_CELLS - 1;
  }
  var ml: Int = ((lat_ud + _MH_LAT_BASE_UD) * _MH_LAT_AXIS_NUM) / _MH_AXIS_DEN;
  if ml >= _MH_AXIS_CELLS {
    ml = _MH_AXIS_CELLS - 1;
  }
  var out: Str = _letter_char(nl / _MH_FIELD_STEP) + _letter_char(ml / _MH_FIELD_STEP);
  if length >= 4 {
    out = out + _digit_char((nl / _MH_SQUARE_STEP) % 10);
    out = out + _digit_char((ml / _MH_SQUARE_STEP) % 10);
  }
  if length >= 6 {
    out = out + _letter_char((nl / _MH_SUBSQUARE_STEP) % 24);
    out = out + _letter_char((ml / _MH_SUBSQUARE_STEP) % 24);
  }
  if length >= 8 {
    out = out + _digit_char((nl / _MH_EXT_STEP) % 10);
    out = out + _digit_char((ml / _MH_EXT_STEP) % 10);
  }
  return out;
}

/// Encode an integer-microdegree coordinate as an uppercase Maidenhead
/// locator.
/// Params: lat_ud - latitude in microdegrees, [-90_000_000, 90_000_000]
/// inclusive; lon_ud - longitude in microdegrees, [-180_000_000,
/// 180_000_000] inclusive; length - locator length in characters, one of 2,
/// 4, 6 or 8.
/// Returns: Ok(locator) with exactly `length` uppercase characters: field
/// letters at 0-1, square digits at 2-3, subsquare letters at 4-5 and
/// extended square digits at 6-7, with the longitude part first at every
/// level. The output is canonical: uppercase, integer-exact and independent
/// of platform arithmetic (no Float64 is used). A point exactly on a cell
/// edge selects the upper (east/north) cell, and the inclusive upper bounds
/// lat = 90_000_000 and lon = 180_000_000 fold into the northernmost /
/// easternmost cell, so "RR99XX99" is the maximum locator and "AA00AA00" the
/// minimum.
/// Error case: Err("maidenhead: invalid length") when length is not one of
/// 2, 4, 6, 8; Err("maidenhead: latitude out of range") or
/// Err("maidenhead: longitude out of range") when the coordinate is outside
/// its inclusive range. Validation order is length, latitude, longitude.
/// Complexity: O(1).
pub fn maidenhead_encode(lat_ud: Int, lon_ud: Int, length: Int) -> Result[Str, Str] {
  if length != 2 && length != 4 && length != 6 && length != 8 {
    return _err_str("maidenhead: invalid length");
  }
  if lat_ud < _MH_LAT_MIN_UD || lat_ud > _MH_LAT_MAX_UD {
    return _err_str("maidenhead: latitude out of range");
  }
  if lon_ud < _MH_LON_MIN_UD || lon_ud > _MH_LON_MAX_UD {
    return _err_str("maidenhead: longitude out of range");
  }
  return _ok_str(_encode_raw(lat_ud, lon_ud, length));
}

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

// Number of full-grid cells covered by one locator character pair at `length`:
// 2400 (field), 240 (square), 10 (subsquare) or 1 (extended square).
fn _level_width(length: Int) -> Int {
  if length == 2 {
    return _MH_FIELD_STEP;
  }
  if length == 4 {
    return _MH_SQUARE_STEP;
  }
  if length == 6 {
    return _MH_SUBSQUARE_STEP;
  }
  return _MH_EXT_STEP;
}

// Smallest microdegree on an axis that encodes to full-grid cell index k.
// The cell is [k, k+width) on the non-negative 1/240-degree grid, so the cell
// start in microdegrees is (k * 25_000 - 540_000_000) / den.
fn _axis_min_ud(k: Int, den: Int) -> Int {
  return _div_ceil(k * _MH_AXIS_DEN - _MH_CELL_OFFSET, den);
}

// Largest microdegree on an axis that encodes to full-grid cell index k of the
// given width. For the top cell (k + width = 43_200) the inclusive domain
// maximum is kept, because encoding folds lat = 90_000_000 / lon =
// 180_000_000 into that cell; otherwise it is one below the exclusive upper
// bound.
fn _axis_max_ud(k: Int, width: Int, den: Int, axis_max_ud: Int) -> Int {
  if k + width >= _MH_AXIS_CELLS {
    return axis_max_ud;
  }
  return _axis_min_ud(k + width, den) - 1;
}

// Full-grid longitude index (0..43_199) of a validated uppercase locator.
fn _parse_lon_axis(up: Str, length: Int) -> Int {
  var k: Int = _letter_value(_byte(up, 0)) * _MH_FIELD_STEP;
  if length >= 4 {
    k = k + _digit_value(_byte(up, 2)) * _MH_SQUARE_STEP;
  }
  if length >= 6 {
    k = k + _letter_value(_byte(up, 4)) * _MH_SUBSQUARE_STEP;
  }
  if length >= 8 {
    k = k + _digit_value(_byte(up, 6)) * _MH_EXT_STEP;
  }
  return k;
}

// Full-grid latitude index (0..43_199) of a validated uppercase locator.
fn _parse_lat_axis(up: Str, length: Int) -> Int {
  var k: Int = _letter_value(_byte(up, 1)) * _MH_FIELD_STEP;
  if length >= 4 {
    k = k + _digit_value(_byte(up, 3)) * _MH_SQUARE_STEP;
  }
  if length >= 6 {
    k = k + _letter_value(_byte(up, 5)) * _MH_SUBSQUARE_STEP;
  }
  if length >= 8 {
    k = k + _digit_value(_byte(up, 7)) * _MH_EXT_STEP;
  }
  return k;
}

// Raw decoder for a validated uppercase locator.
fn _decode_raw(up: Str, length: Int) -> MaidenheadBox {
  let nl: Int = _parse_lon_axis(up, length);
  let ml: Int = _parse_lat_axis(up, length);
  let width: Int = _level_width(length);
  let min_lon: Int = _axis_min_ud(nl, _MH_LON_CELL_DEN);
  let max_lon: Int = _axis_max_ud(nl, width, _MH_LON_CELL_DEN, _MH_LON_MAX_UD);
  let min_lat: Int = _axis_min_ud(ml, _MH_LAT_CELL_DEN);
  let max_lat: Int = _axis_max_ud(ml, width, _MH_LAT_CELL_DEN, _MH_LAT_MAX_UD);
  return MaidenheadBox{
    length: length;
    min_lat_ud: min_lat;
    min_lon_ud: min_lon;
    max_lat_ud: max_lat;
    max_lon_ud: max_lon;
    center_lat_ud: (min_lat + max_lat) / 2;
    center_lon_ud: (min_lon + max_lon) / 2;
  };
}

/// Decode a Maidenhead locator to its cell box and center.
/// Params: locator - 2, 4, 6 or 8 characters; ASCII letters are
/// case-insensitive and are folded to uppercase before validation, so
/// "jo22ki" decodes exactly like "JO22KI".
/// Returns: Ok(MaidenheadBox) with the inclusive integer-microdegree box whose
/// points all re-encode to `locator` (min = ceil of the cell lower bound,
/// max = ceil of the cell upper bound minus one, with the range maximum kept
/// for the top cell) and the box center. The center is the truncating integer
/// division (min + max) / 2, so it always lies inside the box and re-encodes
/// to the same locator, as do all four box corners. Every valid locator
/// decodes to a non-empty box, because the smallest cell (extended square) is
/// wider than one microdegree on both axes.
/// Error case: Err("maidenhead: empty locator") for ""; Err("maidenhead:
/// invalid locator length") for any other length than 2, 4, 6 or 8 (including
/// odd lengths); otherwise the message of the first offending position:
/// Err("maidenhead: invalid field letter"), Err("maidenhead: invalid square
/// digit"), Err("maidenhead: invalid subsquare letter") or Err("maidenhead:
/// invalid extended square digit"). Length is checked before characters and
/// positions are checked in locator order.
/// Complexity: O(len(locator)).
pub fn maidenhead_decode(locator: Str) -> Result[MaidenheadBox, Str] {
  let checked: Result[Str, Str] = _checked_upper(locator);
  if !checked.is_ok {
    return _err_box(checked.error);
  }
  let up: Str = checked.value;
  let length: Int = up.len();
  return _ok_box(_decode_raw(up, length));
}

/// Normalize a Maidenhead locator to its canonical uppercase spelling.
/// Params: locator - 2, 4, 6 or 8 characters, ASCII letters case-insensitive.
/// Returns: Ok(canonical) where `canonical` is `locator` with ASCII a-z folded
/// to A-Z; it equals the maidenhead_encode output for every point of the
/// decoded cell and is idempotent.
/// Error case: the same catalog as maidenhead_decode: empty, invalid length
/// (checked before characters) or an invalid character at the first offending
/// position.
/// Complexity: O(len(locator)).
pub fn maidenhead_normalize(locator: Str) -> Result[Str, Str] {
  return _checked_upper(locator);
}

// ---------------------------------------------------------------------------
// Locator part accessors
// ---------------------------------------------------------------------------

/// Validated length of a locator.
/// Params: locator - 2, 4, 6 or 8 characters, ASCII letters case-insensitive.
/// Returns: Ok(2), Ok(4), Ok(6) or Ok(8), the number of characters.
/// Error case: the same catalog as maidenhead_decode.
/// Complexity: O(len(locator)).
pub fn maidenhead_locator_length(locator: Str) -> Result[Int, Str] {
  let checked: Result[Str, Str] = _checked_upper(locator);
  if !checked.is_ok {
    return _err_int(checked.error);
  }
  let up: Str = checked.value;
  return _ok_int(up.len());
}

/// Field part (level 0) of a locator: the two uppercase letters A-R.
/// Params: locator - a locator accepted by maidenhead_decode.
/// Returns: Ok(field), the first two characters uppercased.
/// Error case: the same catalog as maidenhead_decode.
/// Complexity: O(len(locator)).
pub fn maidenhead_field(locator: Str) -> Result[Str, Str] {
  let checked: Result[Str, Str] = _checked_upper(locator);
  if !checked.is_ok {
    return _err_str(checked.error);
  }
  let up: Str = checked.value;
  return _ok_str(string.str_slice(up, 0, 2));
}

/// Square part (level 1) of a locator: the two digits 0-9.
/// Params: locator - a locator of length 4, 6 or 8 accepted by
/// maidenhead_decode.
/// Returns: Ok(square), characters 2-3 uppercased (digits are unchanged).
/// Error case: the same catalog as maidenhead_decode; additionally
/// Err("maidenhead: square part missing") for a length-2 locator, which has no
/// square level.
/// Complexity: O(len(locator)).
pub fn maidenhead_square(locator: Str) -> Result[Str, Str] {
  let checked: Result[Str, Str] = _checked_upper(locator);
  if !checked.is_ok {
    return _err_str(checked.error);
  }
  let up: Str = checked.value;
  if up.len() < 4 {
    return _err_str("maidenhead: square part missing");
  }
  return _ok_str(string.str_slice(up, 2, 4));
}

/// Subsquare part (level 2) of a locator: the two uppercase letters A-X.
/// Params: locator - a locator of length 6 or 8 accepted by
/// maidenhead_decode.
/// Returns: Ok(subsquare), characters 4-5 uppercased.
/// Error case: the same catalog as maidenhead_decode; additionally
/// Err("maidenhead: subsquare part missing") for a length-2 or length-4
/// locator, which has no subsquare level.
/// Complexity: O(len(locator)).
pub fn maidenhead_subsquare(locator: Str) -> Result[Str, Str] {
  let checked: Result[Str, Str] = _checked_upper(locator);
  if !checked.is_ok {
    return _err_str(checked.error);
  }
  let up: Str = checked.value;
  if up.len() < 6 {
    return _err_str("maidenhead: subsquare part missing");
  }
  return _ok_str(string.str_slice(up, 4, 6));
}

/// Extended square part (level 3) of a locator: the two digits 0-9.
/// Params: locator - a length-8 locator accepted by maidenhead_decode.
/// Returns: Ok(ext_square), characters 6-7 (digits are unchanged by case
/// folding).
/// Error case: the same catalog as maidenhead_decode; additionally
/// Err("maidenhead: extended square part missing") for a locator shorter than
/// 8 characters, which has no extended square level.
/// Complexity: O(len(locator)).
pub fn maidenhead_ext_square(locator: Str) -> Result[Str, Str] {
  let checked: Result[Str, Str] = _checked_upper(locator);
  if !checked.is_ok {
    return _err_str(checked.error);
  }
  let up: Str = checked.value;
  if up.len() < 8 {
    return _err_str("maidenhead: extended square part missing");
  }
  return _ok_str(string.str_slice(up, 6, 8));
}

// ---------------------------------------------------------------------------
// Box accessors
// ---------------------------------------------------------------------------

/// Length (character count) of the locator a box was decoded from.
/// Params: b - a decoded box, read only.
/// Returns: b.length, one of 2, 4, 6, 8.
/// Error case: none.
/// Complexity: O(1).
pub fn maidenhead_box_length(b: MaidenheadBox) -> Int {
  return b.length;
}

/// Lower latitude bound of a box, in integer microdegrees.
/// Params: b - a decoded box, read only.
/// Returns: b.min_lat_ud, at least -90_000_000.
/// Error case: none.
/// Complexity: O(1).
pub fn maidenhead_box_min_lat(b: MaidenheadBox) -> Int {
  return b.min_lat_ud;
}

/// Lower longitude bound of a box, in integer microdegrees.
/// Params: b - a decoded box, read only.
/// Returns: b.min_lon_ud, at least -180_000_000.
/// Error case: none.
/// Complexity: O(1).
pub fn maidenhead_box_min_lon(b: MaidenheadBox) -> Int {
  return b.min_lon_ud;
}

/// Upper latitude bound of a box, in integer microdegrees.
/// Params: b - a decoded box, read only.
/// Returns: b.max_lat_ud, at most 90_000_000.
/// Error case: none.
/// Complexity: O(1).
pub fn maidenhead_box_max_lat(b: MaidenheadBox) -> Int {
  return b.max_lat_ud;
}

/// Upper longitude bound of a box, in integer microdegrees.
/// Params: b - a decoded box, read only.
/// Returns: b.max_lon_ud, at most 180_000_000.
/// Error case: none.
/// Complexity: O(1).
pub fn maidenhead_box_max_lon(b: MaidenheadBox) -> Int {
  return b.max_lon_ud;
}

/// Inclusive containment of an integer-microdegree point in a box.
/// Params: b - a decoded box, read only; lat_ud, lon_ud - the query point in
/// microdegrees (no range validation is needed; out-of-range points simply
/// fail containment).
/// Returns: true when min_lat_ud <= lat_ud <= max_lat_ud and
/// min_lon_ud <= lon_ud <= max_lon_ud. Every point of a box re-encodes to the
/// box's locator at the box's length (all boxes are non-empty).
/// Error case: none.
/// Complexity: O(1).
pub fn maidenhead_box_contains(b: MaidenheadBox, lat_ud: Int, lon_ud: Int) -> Bool {
  if lat_ud < b.min_lat_ud || lat_ud > b.max_lat_ud {
    return false;
  }
  if lon_ud < b.min_lon_ud || lon_ud > b.max_lon_ud {
    return false;
  }
  return true;
}
