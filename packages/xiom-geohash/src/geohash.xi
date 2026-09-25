// XIOM -- xiom.geohash: integer-only geohash codec over integer microdegrees
// Port task: greenfield pure-XIOM geohash encoder/decoder (no FFI, no Float64).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - Coordinates are carried as integer microdegrees (ud): 1 degree = 1,000,000
//   ud. Latitude runs over [-90_000_000, 90_000_000] and longitude over
//   [-180_000_000, 180_000_000], both inclusive. No Float64 is used anywhere,
//   so every result is exact and platform-independent.
// - Encoding is exact integer bisection over those ranges, computed as a
//   bit-by-bit long division: for `n` axis bits the cell index is
//   floor((x - lo) * 2^n / span), so a point on a cell boundary selects the
//   upper cell (the classic `x >= mid` rule) and the inclusive upper bound
//   (lat 90, lon 180) selects the northernmost/easternmost cell.
// - The base32 alphabet is "0123456789bcdefghjkmnpqrstuvwxyz" (lowercase; the
//   letters a, i, l, o are not used). Bits alternate longitude first and the
//   first bit of a character is its most significant bit. Precision is 1..12
//   characters (5..60 bits).
// - geohash_encode emits canonical lowercase. geohash_decode and
//   geohash_normalize accept uppercase ASCII input and normalize it (folding
//   covers A-Z; "U4PRUYDQQVJ" is valid, while "I" is not because 'i' is not
//   in the alphabet).
// - A decoded GeoBox is the inclusive integer-microdegree range whose points
//   all re-encode to the hash: min = ceil(cell lower bound) and max =
//   ceil(cell upper bound) - 1 (the range maximum for the top cell). At
//   precision 12 an axis cell is thinner than 1 ud, so a hash whose cell
//   contains no integer point has an empty box (min > max); such hashes are
//   never produced by geohash_encode. All precisions 1..11 always yield
//   non-empty boxes.
//
// v0.61.3 notes that shaped this module: free functions only; no Vec[Float64]
// and no Vec at all; Result payloads are constructed only in the leaf helpers
// _ok_str/_err_str/_ok_box/_err_box; every byte from xiom.string.byte_at is
// widened as `(x as Int) & 0xFF`; no string equality is performed here.

module xiom.geohash

use xiom.string;

// Standard geohash base32 alphabet: digits 0-9 then lowercase consonants
// b-z with a, i, l, o removed.
const _GEOHASH_ALPHABET: Str = "0123456789bcdefghjkmnpqrstuvwxyz";
const _GEOHASH_MIN_PRECISION: Int = 1;
const _GEOHASH_MAX_PRECISION: Int = 12;
const _GEOHASH_LAT_MIN_UD: Int = -90000000;
const _GEOHASH_LAT_MAX_UD: Int = 90000000;
const _GEOHASH_LON_MIN_UD: Int = -180000000;
const _GEOHASH_LON_MAX_UD: Int = 180000000;
const _GEOHASH_LAT_SPAN_UD: Int = 180000000;
const _GEOHASH_LON_SPAN_UD: Int = 360000000;

/// A decoded geohash cell: the inclusive integer-microdegree box whose points
/// all re-encode to the source hash, plus the box center. `precision` is the
/// character count of the source hash (1..12). The box is empty when
/// `min_lat_ud > max_lat_ud` or `min_lon_ud > max_lon_ud` (possible at
/// precision 12 only; see geohash_box_is_empty).
pub type GeoBox = {
  precision: Int;
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

// Ok(b) for Result[GeoBox, Str].
fn _ok_box(b: GeoBox) -> Result[GeoBox, Str] {
  return Ok(b);
}

// Err(m) for Result[GeoBox, Str].
fn _err_box(m: Str) -> Result[GeoBox, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
// Integer helpers
// ---------------------------------------------------------------------------

// 2^n for n >= 0 (n <= 30 in this module).
fn _pow2(n: Int) -> Int {
  var r: Int = 1;
  var i: Int = 0;
  while i < n {
    r = r * 2;
    i = i + 1;
  }
  return r;
}

// ceil(a / b) for a >= 0 and b > 0, using integer division.
fn _div_ceil(a: Int, b: Int) -> Int {
  return (a + b - 1) / b;
}

// The one-character string for digit value v (0..31). Caller guarantees range.
fn _alphabet_char(v: Int) -> Str {
  return string.str_slice(_GEOHASH_ALPHABET, v, v + 1);
}

// Numeric value of a lowercase alphabet byte; -1 when the byte is not in the
// alphabet. Inputs are lowercased by the callers, so no case folding here.
fn _alphabet_value(b: UInt8) -> Int {
  let x: Int = (b as Int) & 0xFF;
  var i = 0;
  while i < 32 {
    let c: Int = (string.byte_at(_GEOHASH_ALPHABET, i) as Int) & 0xFF;
    if c == x {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Cell index of x over [lo, lo + span] in `nbits` bits, computed exactly:
// the bits of floor((x - lo) * 2^nbits / span), most significant first. x is
// validated into [lo, lo + span] by the callers; x = lo + span (the inclusive
// upper bound) folds to the top cell, matching the classic bisector.
fn _axis_index(x: Int, lo: Int, span: Int, nbits: Int) -> Int {
  var rem: Int = x - lo;
  var idx: Int = 0;
  var i: Int = 0;
  while i < nbits {
    rem = rem * 2;
    idx = idx * 2;
    if rem >= span {
      idx = idx + 1;
      rem = rem - span;
    }
    i = i + 1;
  }
  return idx;
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

// Raw encoder for a validated coordinate and precision.
fn _encode_raw(lat_ud: Int, lon_ud: Int, precision: Int) -> Str {
  let total_bits: Int = precision * 5;
  let lat_bits: Int = total_bits / 2;
  let lon_bits: Int = total_bits - lat_bits;
  var lat_rem: Int = _axis_index(lat_ud, _GEOHASH_LAT_MIN_UD, _GEOHASH_LAT_SPAN_UD, lat_bits);
  var lon_rem: Int = _axis_index(lon_ud, _GEOHASH_LON_MIN_UD, _GEOHASH_LON_SPAN_UD, lon_bits);
  var lat_mask: Int = _pow2(lat_bits - 1);
  var lon_mask: Int = _pow2(lon_bits - 1);
  var even = true;
  var bit = 0;
  var ch: Int = 0;
  var out = "";
  while bit < total_bits {
    if even {
      if lon_rem >= lon_mask {
        ch = ch * 2 + 1;
        lon_rem = lon_rem - lon_mask;
      } else {
        ch = ch * 2;
      }
      lon_mask = lon_mask / 2;
    } else {
      if lat_rem >= lat_mask {
        ch = ch * 2 + 1;
        lat_rem = lat_rem - lat_mask;
      } else {
        ch = ch * 2;
      }
      lat_mask = lat_mask / 2;
    }
    even = !even;
    if bit % 5 == 4 {
      out = out + _alphabet_char(ch);
      ch = 0;
    }
    bit = bit + 1;
  }
  return out;
}

/// Encode an integer-microdegree coordinate as a lowercase base32 geohash.
/// Params: lat_ud - latitude in microdegrees, [-90_000_000, 90_000_000]
/// inclusive; lon_ud - longitude in microdegrees, [-180_000_000,
/// 180_000_000] inclusive; precision - number of characters, [1, 12].
/// Returns: Ok(hash) with exactly `precision` lowercase alphabet characters.
/// The output is canonical: it is always lowercase and independent of
/// platform arithmetic (no Float64 is used).
/// Error case: Err("geohash: invalid precision") when precision is outside
/// [1, 12]; Err("geohash: latitude out of range") or
/// Err("geohash: longitude out of range") when the coordinate is outside its
/// inclusive range. Validation order is precision, latitude, longitude.
/// Complexity: O(precision).
pub fn geohash_encode(lat_ud: Int, lon_ud: Int, precision: Int) -> Result[Str, Str] {
  if precision < _GEOHASH_MIN_PRECISION || precision > _GEOHASH_MAX_PRECISION {
    return _err_str("geohash: invalid precision");
  }
  if lat_ud < _GEOHASH_LAT_MIN_UD || lat_ud > _GEOHASH_LAT_MAX_UD {
    return _err_str("geohash: latitude out of range");
  }
  if lon_ud < _GEOHASH_LON_MIN_UD || lon_ud > _GEOHASH_LON_MAX_UD {
    return _err_str("geohash: longitude out of range");
  }
  return _ok_str(_encode_raw(lat_ud, lon_ud, precision));
}

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

/// Decode a geohash to its cell box and center.
/// Params: hash - 1 to 12 characters from the base32 alphabet. Lowercase and
/// uppercase ASCII are both accepted; uppercase is folded to lowercase before
/// validation, so "U4PRUYDQQVJ" decodes exactly like "u4pruydqqvj".
/// Returns: Ok(GeoBox) with the inclusive integer-microdegree box whose points
/// all re-encode to `hash` (min = ceil of the cell lower bound, max = ceil of
/// the cell upper bound minus one, with the range maximum kept for the top
/// cell) and the box center. The center is the truncating integer division
/// (min + max) / 2, so it always lies inside a non-empty box and re-encodes to
/// the same hash. At precision 12 an axis cell can be thinner than one
/// microdegree, in which case that axis has no integer point and the box is
/// empty; the center then falls up to one microdegree outside the cell.
/// Error case: Err("geohash: empty geohash") for ""; Err("geohash: geohash
/// too long") for more than 12 characters (checked before the characters);
/// Err("geohash: invalid geohash character") for any byte that is not an
/// alphabet letter after case folding (including a, i, l, o).
/// Complexity: O(len(hash)).
pub fn geohash_decode(hash: Str) -> Result[GeoBox, Str] {
  let len = hash.len();
  if len == 0 {
    return _err_box("geohash: empty geohash");
  }
  if len > _GEOHASH_MAX_PRECISION {
    return _err_box("geohash: geohash too long");
  }
  let lowered = string.str_lower(hash);
  let total_bits: Int = len * 5;
  let lat_bits: Int = total_bits / 2;
  let lon_bits: Int = total_bits - lat_bits;
  var lat_idx: Int = 0;
  var lon_idx: Int = 0;
  var even = true;
  var i = 0;
  while i < len {
    let value: Int = _alphabet_value(string.byte_at(lowered, i));
    if value < 0 {
      return _err_box("geohash: invalid geohash character");
    }
    var acc: Int = value;
    var mask: Int = 16;
    while mask > 0 {
      var bit: Int = 0;
      if acc >= mask {
        bit = 1;
        acc = acc - mask;
      }
      if even {
        lon_idx = lon_idx * 2 + bit;
      } else {
        lat_idx = lat_idx * 2 + bit;
      }
      even = !even;
      mask = mask / 2;
    }
    i = i + 1;
  }
  let lat_denom: Int = _pow2(lat_bits);
  let lon_denom: Int = _pow2(lon_bits);
  var min_lat: Int = _GEOHASH_LAT_MIN_UD + _div_ceil(lat_idx * _GEOHASH_LAT_SPAN_UD, lat_denom);
  var max_lat: Int = _GEOHASH_LAT_MIN_UD + _div_ceil((lat_idx + 1) * _GEOHASH_LAT_SPAN_UD, lat_denom) - 1;
  if lat_idx == lat_denom - 1 {
    max_lat = _GEOHASH_LAT_MAX_UD;
  }
  var min_lon: Int = _GEOHASH_LON_MIN_UD + _div_ceil(lon_idx * _GEOHASH_LON_SPAN_UD, lon_denom);
  var max_lon: Int = _GEOHASH_LON_MIN_UD + _div_ceil((lon_idx + 1) * _GEOHASH_LON_SPAN_UD, lon_denom) - 1;
  if lon_idx == lon_denom - 1 {
    max_lon = _GEOHASH_LON_MAX_UD;
  }
  return _ok_box(GeoBox{
    precision: len;
    min_lat_ud: min_lat;
    min_lon_ud: min_lon;
    max_lat_ud: max_lat;
    max_lon_ud: max_lon;
    center_lat_ud: (min_lat + max_lat) / 2;
    center_lon_ud: (min_lon + max_lon) / 2;
  });
}

/// Normalize a geohash to its canonical lowercase spelling.
/// Params: hash - 1 to 12 alphabet characters, lowercase or uppercase ASCII.
/// Returns: Ok(canonical) where `canonical` is `hash` with A-Z folded to
/// lowercase; it equals the geohash_encode output for the decoded cell.
/// Error case: the same catalog as geohash_decode:
/// Err("geohash: empty geohash"), Err("geohash: geohash too long") (length
/// checked before characters) or Err("geohash: invalid geohash character").
/// Complexity: O(len(hash)).
pub fn geohash_normalize(hash: Str) -> Result[Str, Str] {
  let len = hash.len();
  if len == 0 {
    return _err_str("geohash: empty geohash");
  }
  if len > _GEOHASH_MAX_PRECISION {
    return _err_str("geohash: geohash too long");
  }
  let lowered = string.str_lower(hash);
  var i = 0;
  while i < len {
    if _alphabet_value(string.byte_at(lowered, i)) < 0 {
      return _err_str("geohash: invalid geohash character");
    }
    i = i + 1;
  }
  return _ok_str(lowered);
}

// ---------------------------------------------------------------------------
// Box accessors
// ---------------------------------------------------------------------------

/// Precision (character count) of the hash a box was decoded from.
/// Params: b - a decoded box, read only.
/// Returns: b.precision, always within [1, 12].
/// Error case: none.
/// Complexity: O(1).
pub fn geohash_box_precision(b: GeoBox) -> Int {
  return b.precision;
}

/// Lower latitude bound of a box, in integer microdegrees.
/// Params: b - a decoded box, read only.
/// Returns: b.min_lat_ud; when the box is empty this is one greater than
/// b.max_lat_ud.
/// Error case: none.
/// Complexity: O(1).
pub fn geohash_box_min_lat(b: GeoBox) -> Int {
  return b.min_lat_ud;
}

/// Lower longitude bound of a box, in integer microdegrees.
/// Params: b - a decoded box, read only.
/// Returns: b.min_lon_ud; when the box is empty this is one greater than
/// b.max_lon_ud.
/// Error case: none.
/// Complexity: O(1).
pub fn geohash_box_min_lon(b: GeoBox) -> Int {
  return b.min_lon_ud;
}

/// Upper latitude bound of a box, in integer microdegrees.
/// Params: b - a decoded box, read only.
/// Returns: b.max_lat_ud, at most 90_000_000.
/// Error case: none.
/// Complexity: O(1).
pub fn geohash_box_max_lat(b: GeoBox) -> Int {
  return b.max_lat_ud;
}

/// Upper longitude bound of a box, in integer microdegrees.
/// Params: b - a decoded box, read only.
/// Returns: b.max_lon_ud, at most 180_000_000.
/// Error case: none.
/// Complexity: O(1).
pub fn geohash_box_max_lon(b: GeoBox) -> Int {
  return b.max_lon_ud;
}

/// Whether a box contains no integer-microdegree point.
/// Params: b - a decoded box, read only.
/// Returns: true when min_lat_ud > max_lat_ud or min_lon_ud > max_lon_ud.
/// This can only happen at precision 12, for hashes whose cell is thinner
/// than one microdegree on some axis; geohash_encode never produces such a
/// hash from integer input, so every encoded hash decodes to a non-empty box.
/// Error case: none.
/// Complexity: O(1).
pub fn geohash_box_is_empty(b: GeoBox) -> Bool {
  if b.min_lat_ud > b.max_lat_ud {
    return true;
  }
  if b.min_lon_ud > b.max_lon_ud {
    return true;
  }
  return false;
}

/// Inclusive containment of an integer-microdegree point in a box.
/// Params: b - a decoded box, read only; lat_ud, lon_ud - the query point in
/// microdegrees (no range validation is needed; out-of-range points simply
/// fail containment).
/// Returns: true when min_lat_ud <= lat_ud <= max_lat_ud and
/// min_lon_ud <= lon_ud <= max_lon_ud. Every point of a non-empty box
/// re-encodes to the box's hash; an empty box contains nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn geohash_box_contains(b: GeoBox, lat_ud: Int, lon_ud: Int) -> Bool {
  if lat_ud < b.min_lat_ud || lat_ud > b.max_lat_ud {
    return false;
  }
  if lon_ud < b.min_lon_ud || lon_ud > b.max_lon_ud {
    return false;
  }
  return true;
}
