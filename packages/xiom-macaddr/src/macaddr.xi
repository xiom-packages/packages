// XIOM -- xiom.macaddr: MAC-48 parsing, formatting and flag helpers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A MAC-48 address is carried as a non-negative Int in the low 48 bits:
// octet 0 occupies bits 47..40 and octet 5 occupies bits 7..0. Every helper
// first masks the input with 0xFFFFFFFFFFFF, so bits above bit 47 are
// ignored; mac_format documents this masking explicitly.
//
// Accepted notations (see SPEC.md for the grammar):
//   * colon-separated pairs:  "aa:bb:cc:dd:ee:ff"  (case-insensitive)
//   * dash-separated pairs:   "AA-BB-CC-DD-EE-FF"
//   * Cisco dotted triplets:  "aabb.ccdd.eeff"
//   * bare 12 hex digits:     "AABBCCDDEEFF"
// Separators must be uniform: mixing ':' and '-' is rejected, as are '.'
// separators in the pair form and any other byte.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; every byte read via xiom.string.byte_at is
//     widened with `(byte_at(s, i) as Int) & 0xFF` before comparison;
//   * Ok/Err for the Result[Int, Str] parsers are constructed only in the
//     tiny leaf helpers _ok_int/_err_int;
//   * formatted output is collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str (one allocation per result Str);
//   * the module never compares Str values (no `==` on Str); there is no
//     `use` of xiom.string.compare here.
//
// No FFI, no structs, no lambdas.

module xiom.macaddr

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Result constructors (leaf helpers only, v0.61.3)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Numeric value of a hex digit byte (0-9, a-f, A-F); -1 for any other byte.
fn _hex_value(b: Int) -> Int {
  if b >= 48 && b <= 57 { return b - 48; }
  if b >= 97 && b <= 102 { return b - 87; }
  if b >= 65 && b <= 70 { return b - 55; }
  return -1;
}

// Lowercase hex digit byte for a nibble value (0..15).
fn _hex_lower(v: Int) -> UInt8 {
  if v < 10 {
    return (48 + v) as UInt8;
  }
  return (87 + v) as UInt8;
}

// Uppercase hex digit byte for a nibble value (0..15).
fn _hex_upper(v: Int) -> UInt8 {
  if v < 10 {
    return (48 + v) as UInt8;
  }
  return (55 + v) as UInt8;
}

// --------------------------------------------------
//  Parsers (one per accepted notation)
// --------------------------------------------------

// 12 bare hex digits -> the 48-bit value.
fn _parse_bare(s: Str) -> Result[Int, Str] {
  var v = 0;
  var i = 0;
  while i < 12 {
    let d = _hex_value((string.byte_at(s, i) as Int) & 0xFF);
    if d < 0 {
      return _err_int("mac: invalid character");
    }
    v = (v << 4) | d;
    i = i + 1;
  }
  return _ok_int(v);
}

// 17 characters of colon- or dash-separated hex pairs; the separator byte at
// position 2 must be ':' or '-', and every later separator must match it.
fn _parse_pairs(s: Str) -> Result[Int, Str] {
  let sep = (string.byte_at(s, 2) as Int) & 0xFF;
  if sep != 58 && sep != 45 {
    return _err_int("mac: invalid separator");
  }
  var v = 0;
  var i = 0;
  while i < 6 {
    let p = i * 3;
    if i > 0 {
      let sp = (string.byte_at(s, p - 1) as Int) & 0xFF;
      if sp != sep {
        return _err_int("mac: invalid separator");
      }
    }
    let hi = _hex_value((string.byte_at(s, p) as Int) & 0xFF);
    let lo = _hex_value((string.byte_at(s, p + 1) as Int) & 0xFF);
    if hi < 0 || lo < 0 {
      return _err_int("mac: invalid character");
    }
    v = (v << 8) | ((hi << 4) | lo);
    i = i + 1;
  }
  return _ok_int(v);
}

// 14 characters of Cisco dotted triplets "xxxx.xxxx.xxxx"; the dots must be
// at positions 4 and 9 and every other byte must be a hex digit.
fn _parse_dotted(s: Str) -> Result[Int, Str] {
  if ((string.byte_at(s, 4) as Int) & 0xFF) != 46 {
    return _err_int("mac: invalid separator");
  }
  if ((string.byte_at(s, 9) as Int) & 0xFF) != 46 {
    return _err_int("mac: invalid separator");
  }
  var v = 0;
  var i = 0;
  while i < 12 {
    let p = i + (i / 4);
    let d = _hex_value((string.byte_at(s, p) as Int) & 0xFF);
    if d < 0 {
      return _err_int("mac: invalid character");
    }
    v = (v << 4) | d;
    i = i + 1;
  }
  return _ok_int(v);
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse a MAC-48 address into its 48-bit value.
/// Params: s - the address text, in one of four notations: colon pairs
/// ("aa:bb:cc:dd:ee:ff"), dash pairs ("AA-BB-CC-DD-EE-FF"), Cisco dotted
/// triplets ("aabb.ccdd.eeff") or 12 bare hex digits ("AABBCCDDEEFF").
/// Hex digits are case-insensitive; pair separators must be uniform.
/// Returns: Ok(value) with value in [0, 2^48).
/// Error case: Err("mac: invalid length") when s.len() is not 12, 14 or 17;
/// Err("mac: invalid separator") for a wrong or mixed separator;
/// Err("mac: invalid character") for a byte outside [0-9a-fA-F].
/// Complexity: O(1).
pub fn mac_parse(s: Str) -> Result[Int, Str] {
  let n = s.len();
  if n == 17 {
    return _parse_pairs(s);
  }
  if n == 14 {
    return _parse_dotted(s);
  }
  if n == 12 {
    return _parse_bare(s);
  }
  return _err_int("mac: invalid length");
}

// Shared formatter: lowercase when upper is false, uppercase otherwise.
fn _format(m: Int, upper: Bool) -> Str {
  let v = m & 0xFFFFFFFFFFFF;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 6 {
    if i > 0 {
      out.push(58u8);
    }
    let shift = 40 - (i * 8);
    let b = (v >> shift) & 0xFF;
    if upper {
      out.push(_hex_upper(b >> 4));
      out.push(_hex_upper(b & 15));
    } else {
      out.push(_hex_lower(b >> 4));
      out.push(_hex_lower(b & 15));
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Format a 48-bit value as lowercase colon-separated hex octets.
/// Params: m - the value; bits above bit 47 are masked off first, so
/// e.g. mac_format(1 << 48) is "00:00:00:00:00:00" and mac_format(-1) is
/// "ff:ff:ff:ff:ff:ff".
/// Returns: "xx:xx:xx:xx:xx:xx" with lowercase digits (always 17 chars).
/// Error case: none.
/// Complexity: O(1).
pub fn mac_format(m: Int) -> Str {
  return _format(m, false);
}

/// Format a 48-bit value as uppercase colon-separated hex octets.
/// Params: m - the value; bits above bit 47 are masked off first.
/// Returns: "XX:XX:XX:XX:XX:XX" with uppercase A-F (always 17 chars).
/// Error case: none.
/// Complexity: O(1).
pub fn mac_format_upper(m: Int) -> Str {
  return _format(m, true);
}

/// The OUI (organizationally unique identifier): the upper 24 bits.
/// Params: m - the value; masked to 48 bits first.
/// Returns: a value in [0, 2^24); mac_nic(m) holds the other 24 bits.
/// Error case: none.
/// Complexity: O(1).
pub fn mac_oui(m: Int) -> Int {
  return (m & 0xFFFFFFFFFFFF) >> 24;
}

/// The NIC-specific part: the lower 24 bits.
/// Params: m - the value; masked to 48 bits first.
/// Returns: a value in [0, 2^24); mac_oui(m) holds the other 24 bits.
/// Error case: none.
/// Complexity: O(1).
pub fn mac_nic(m: Int) -> Int {
  return m & 0xFFFFFF;
}

/// True when the I/G bit is set: bit 0 of octet 0, i.e. bit 40 of the
/// 48-bit value (the least significant bit of the first octet).
/// Params: m - the value; masked to 48 bits first.
/// Returns: true for group/multicast addresses (e.g. 01:00:5e:...).
/// Error case: none.
/// Complexity: O(1).
pub fn mac_is_multicast(m: Int) -> Bool {
  let v = m & 0xFFFFFFFFFFFF;
  return ((v >> 40) & 1) == 1;
}

/// True when the U/L bit is set: bit 1 of octet 0, i.e. bit 41 of the
/// 48-bit value (the second least significant bit of the first octet).
/// Params: m - the value; masked to 48 bits first.
/// Returns: true for locally administered addresses (e.g. 02:...).
/// Error case: none.
/// Complexity: O(1).
pub fn mac_is_local(m: Int) -> Bool {
  let v = m & 0xFFFFFFFFFFFF;
  return ((v >> 41) & 1) == 1;
}

/// True when the I/G bit is clear (the address is not multicast).
/// Params: m - the value; masked to 48 bits first.
/// Returns: the complement of mac_is_multicast(m).
/// Error case: none.
/// Complexity: O(1).
pub fn mac_is_unicast(m: Int) -> Bool {
  return !mac_is_multicast(m);
}

/// The MAC-48 broadcast address: all 48 bits set (ff:ff:ff:ff:ff:ff).
/// Returns: 0xFFFFFFFFFFFF.
/// Error case: none.
/// Complexity: O(1).
pub fn mac_broadcast() -> Int {
  return 0xFFFFFFFFFFFF;
}

/// True when every one of the low 48 bits is set.
/// Params: m - the value; masked to 48 bits first.
/// Returns: true only for ff:ff:ff:ff:ff:ff (equivalently mac_broadcast()).
/// Error case: none.
/// Complexity: O(1).
pub fn mac_is_broadcast(m: Int) -> Bool {
  return (m & 0xFFFFFFFFFFFF) == 0xFFFFFFFFFFFF;
}
