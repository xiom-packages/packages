// XIOM -- xiom.geo: geohash encoding/decoding and latitude/longitude helpers
// Port task: replace the xiom.geo placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (see SPEC.md for the algorithm, the error catalog and the test plan):
//   * geohash encode/decode on the standard base32 alphabet
//     "0123456789bcdefghjkmnpqrstuvwxyz" (no a, i, l, o), precision 1..12;
//   * the 8-neighborhood of a geohash cell (N, NE, E, SE, S, SW, W, NW order)
//     derived with interval math;
//   * inclusive bounding-box containment, supporting antimeridian-crossing
//     boxes (min_lon > max_lon);
//   * latitude/longitude clamping.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Ok/Err for Result payloads are constructed only in the tiny leaf
//     helpers _ok_str/_err_str/_ok_point/_err_point (constructing Results
//     directly inside other functions miscompiles in this compiler).
//   * Decoding bisects the WGS84 lat/lon intervals with Float64 scalars only;
//     no Vec[Float64] is used (unsupported in this build).
//   * The base32 lookup scans a Str constant with xiom.string.byte_at; every
//     alphabet byte is ASCII < 128, so the UInt8 comparison is safe.

module xiom.geo

use xiom.string;

/// Geographic coordinate on the WGS84 datum (decimal degrees).
pub type GeoPoint = {
  lat: Float64;
  lon: Float64;
}

// Standard geohash base32 alphabet: 0-9 then b-z with a, i, l, o removed.
const _GEO_BASE32: Str = "0123456789bcdefghjkmnpqrstuvwxyz";
const _GEO_PRECISION_MIN: Int = 1;
const _GEO_PRECISION_MAX: Int = 12;
const _GEO_LAT_MIN: Float64 = -90.0;
const _GEO_LAT_MAX: Float64 = 90.0;
const _GEO_LON_MIN: Float64 = -180.0;
const _GEO_LON_MAX: Float64 = 180.0;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(p) for Result[GeoPoint, Str].
fn _ok_point(p: GeoPoint) -> Result[GeoPoint, Str] {
  return Ok(p);
}

// Err(m) for Result[GeoPoint, Str].
fn _err_point(m: Str) -> Result[GeoPoint, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Base32 alphabet helpers
// --------------------------------------------------

// The one-character string for digit value v (0..31). Caller guarantees range.
fn _base32_char(v: Int) -> Str {
  return string.str_slice(_GEO_BASE32, v, v + 1);
}

// Numeric value of an alphabet byte; -1 when the byte is not in the alphabet.
fn _base32_value(b: UInt8) -> Int {
  var i = 0;
  while i < 32 {
    if string.byte_at(_GEO_BASE32, i) == b {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Clamping / wrapping
// --------------------------------------------------

// Clamp a latitude to [-90, 90].
fn _clamp_lat(lat: Float64) -> Float64 {
  if lat < _GEO_LAT_MIN {
    return _GEO_LAT_MIN;
  }
  if lat > _GEO_LAT_MAX {
    return _GEO_LAT_MAX;
  }
  return lat;
}

// Clamp a longitude to [-180, 180].
fn _clamp_lon(lon: Float64) -> Float64 {
  if lon < _GEO_LON_MIN {
    return _GEO_LON_MIN;
  }
  if lon > _GEO_LON_MAX {
    return _GEO_LON_MAX;
  }
  return lon;
}

// Wrap a longitude into [-180, 180] (used by neighbors at the antimeridian).
fn _wrap_lon(lon: Float64) -> Float64 {
  var v = lon;
  while v > _GEO_LON_MAX {
    v = v - 360.0;
  }
  while v < _GEO_LON_MIN {
    v = v + 360.0;
  }
  return v;
}

/// Clamp a latitude to the WGS84 range [-90, 90].
/// Params: lat - latitude in decimal degrees.
/// Returns: lat clamped into [-90, 90]; values already in range pass through
/// unchanged (including the bounds themselves).
/// Error case: none.
/// Complexity: O(1).
pub fn geo_clamp_lat(lat: Float64) -> Float64 {
  return _clamp_lat(lat);
}

/// Clamp a longitude to the WGS84 range [-180, 180].
/// Params: lon - longitude in decimal degrees.
/// Returns: lon clamped into [-180, 180]; values already in range pass
/// through unchanged (including the bounds themselves). No wrapping occurs:
/// 200 becomes 180, not -160.
/// Error case: none.
/// Complexity: O(1).
pub fn geo_clamp_lon(lon: Float64) -> Float64 {
  return _clamp_lon(lon);
}

// --------------------------------------------------
//  Geohash encoding
// --------------------------------------------------

// Bisect the WGS84 latitude/longitude intervals for `precision` characters
// and emit the base32 geohash. The caller guarantees a validated range and
// precision. Longitude bits and latitude bits alternate, longitude first
// (bit 0 of a character is a longitude bit).
fn _encode_raw(lat: Float64, lon: Float64, precision: Int) -> Str {
  var lat_lo: Float64 = _GEO_LAT_MIN;
  var lat_hi: Float64 = _GEO_LAT_MAX;
  var lon_lo: Float64 = _GEO_LON_MIN;
  var lon_hi: Float64 = _GEO_LON_MAX;
  var out = "";
  var ch: Int = 0;
  var even = true;
  var bit = 0;
  while bit < precision * 5 {
    var mid: Float64 = 0.0;
    if even {
      mid = (lon_lo + lon_hi) / 2.0;
      if lon >= mid {
        ch = ch * 2 + 1;
        lon_lo = mid;
      } else {
        ch = ch * 2;
        lon_hi = mid;
      }
    } else {
      mid = (lat_lo + lat_hi) / 2.0;
      if lat >= mid {
        ch = ch * 2 + 1;
        lat_lo = mid;
      } else {
        ch = ch * 2;
        lat_hi = mid;
      }
    }
    even = !even;
    if bit % 5 == 4 {
      out = out + _base32_char(ch);
      ch = 0;
    }
    bit = bit + 1;
  }
  return out;
}

/// Encode a coordinate as a base32 geohash string.
/// Params: lat - latitude in decimal degrees, must be within [-90, 90];
/// lon - longitude in decimal degrees, must be within [-180, 180];
/// precision - number of geohash characters, must be within [1, 12].
/// Returns: Ok(hash) with exactly `precision` lowercase alphabet characters.
/// Error case: Err("geo: invalid precision") when precision is outside
/// [1, 12]; Err("geo: latitude out of range") or
/// Err("geo: longitude out of range") when the coordinate is outside its
/// inclusive range.
/// Complexity: O(precision).
pub fn geo_geohash_encode(lat: Float64, lon: Float64, precision: Int) -> Result[Str, Str] {
  if precision < _GEO_PRECISION_MIN || precision > _GEO_PRECISION_MAX {
    return _err_str("geo: invalid precision");
  }
  if lat < _GEO_LAT_MIN || lat > _GEO_LAT_MAX {
    return _err_str("geo: latitude out of range");
  }
  if lon < _GEO_LON_MIN || lon > _GEO_LON_MAX {
    return _err_str("geo: longitude out of range");
  }
  return _ok_str(_encode_raw(lat, lon, precision));
}

// --------------------------------------------------
//  Geohash decoding
// --------------------------------------------------

/// Decode a geohash string to the center of its cell.
/// Params: hash - 1 to 12 characters from the base32 alphabet
/// "0123456789bcdefghjkmnpqrstuvwxyz" (lowercase; a, i, l, o are invalid).
/// Returns: Ok(GeoPoint) with the latitude/longitude of the cell center.
/// Error case: Err("geo: empty geohash") for ""; Err("geo: geohash too
/// long") for more than 12 characters; Err("geo: invalid geohash
/// character") for any byte outside the alphabet.
/// Complexity: O(len(hash)).
pub fn geo_geohash_decode(hash: Str) -> Result[GeoPoint, Str] {
  let len = hash.len();
  if len == 0 {
    return _err_point("geo: empty geohash");
  }
  if len > _GEO_PRECISION_MAX {
    return _err_point("geo: geohash too long");
  }
  var lat_lo: Float64 = _GEO_LAT_MIN;
  var lat_hi: Float64 = _GEO_LAT_MAX;
  var lon_lo: Float64 = _GEO_LON_MIN;
  var lon_hi: Float64 = _GEO_LON_MAX;
  var even = true;
  var i = 0;
  while i < len {
    var acc: Int = _base32_value(string.byte_at(hash, i));
    if acc < 0 {
      return _err_point("geo: invalid geohash character");
    }
    var mask: Int = 16;
    while mask > 0 {
      var bit_is_one = false;
      if acc >= mask {
        bit_is_one = true;
        acc = acc - mask;
      }
      var mid: Float64 = 0.0;
      if even {
        mid = (lon_lo + lon_hi) / 2.0;
        if bit_is_one {
          lon_lo = mid;
        } else {
          lon_hi = mid;
        }
      } else {
        mid = (lat_lo + lat_hi) / 2.0;
        if bit_is_one {
          lat_lo = mid;
        } else {
          lat_hi = mid;
        }
      }
      even = !even;
      mask = mask / 2;
    }
    i = i + 1;
  }
  return _ok_point(GeoPoint{
    lat: (lat_lo + lat_hi) / 2.0,
    lon: (lon_lo + lon_hi) / 2.0,
  });
}

// --------------------------------------------------
//  Neighborhood
// --------------------------------------------------

// Height (latitude) and width (longitude) in degrees of a geohash cell for a
// hash of `precision` characters. Longitude consumes one more bit than
// latitude when the total bit count is odd.
fn _cell_span(precision: Int) -> (Float64, Float64) {
  let total_bits = precision * 5;
  let lon_bits = (total_bits + 1) / 2;
  let lat_bits = total_bits / 2;
  var divisions: Float64 = 1.0;
  var k = 0;
  while k < lat_bits {
    divisions = divisions * 2.0;
    k = k + 1;
  }
  let height = 180.0 / divisions;
  divisions = 1.0;
  k = 0;
  while k < lon_bits {
    divisions = divisions * 2.0;
    k = k + 1;
  }
  let width = 360.0 / divisions;
  return (height, width);
}

/// The 8 neighboring geohash cells of `hash`, in N, NE, E, SE, S, SW, W, NW
/// order, each with the same number of characters.
/// Params: hash - a geohash accepted by geo_geohash_decode.
/// Returns: a Vec[Str] of the 8 neighbor hashes, computed by moving half a
/// cell height/width from the cell center (interval math). Latitude is
/// clamped to [-90, 90] and longitude wraps at the antimeridian, so a polar
/// or antimeridian cell may repeat a neighbor; the 8 entries are otherwise
/// distinct.
/// Error case: an invalid hash yields an empty Vec[Str].
/// Complexity: O(len(hash)) per neighbor.
pub fn geo_geohash_neighbors(hash: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let decoded = geo_geohash_decode(hash);
  if !decoded.is_ok {
    return out;
  }
  let center = decoded.value;
  let len = hash.len();
  let (height, width) = _cell_span(len);
  let north_lat = _clamp_lat(center.lat + height);
  let south_lat = _clamp_lat(center.lat - height);
  let east_lon = _wrap_lon(center.lon + width);
  let west_lon = _wrap_lon(center.lon - width);
  out.push(_encode_raw(north_lat, center.lon, len));
  out.push(_encode_raw(north_lat, east_lon, len));
  out.push(_encode_raw(center.lat, east_lon, len));
  out.push(_encode_raw(south_lat, east_lon, len));
  out.push(_encode_raw(south_lat, center.lon, len));
  out.push(_encode_raw(south_lat, west_lon, len));
  out.push(_encode_raw(center.lat, west_lon, len));
  out.push(_encode_raw(north_lat, west_lon, len));
  return out;
}

// --------------------------------------------------
//  Bounding boxes
// --------------------------------------------------

/// Inclusive bounding-box containment.
/// Params: min_lat, min_lon, max_lat, max_lon - the box corners (min_lat <=
/// max_lat is required; when min_lon > max_lon the box crosses the
/// antimeridian and covers [min_lon, 180] together with [-180, max_lon]);
/// lat, lon - the query point.
/// Returns: true when the point lies inside the box, bounds included.
/// Error case: none.
/// Complexity: O(1).
pub fn geo_geo_bbox_contains(min_lat: Float64, min_lon: Float64, max_lat: Float64, max_lon: Float64, lat: Float64, lon: Float64) -> Bool {
  if lat < min_lat || lat > max_lat {
    return false;
  }
  if min_lon <= max_lon {
    return lon >= min_lon && lon <= max_lon;
  }
  return lon >= min_lon || lon <= max_lon;
}
