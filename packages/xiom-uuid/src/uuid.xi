// XIOM -- xiom.uuid: UUID formatting, parsing, validation and v4 construction
// Port task: create the pure-XIOM xiom.uuid package (no FFI, no RNG inside).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for the grammar, the bit rules, the error
// catalog and the test plan):
//   * uuid_format: exactly 16 bytes -> canonical lowercase 8-4-4-4-12 text;
//   * uuid_parse: canonical hyphenated text -> 16 bytes; hex case is not
//     significant; braces ({...}) and the URN form (urn:uuid:...) are NOT
//     accepted;
//   * uuid_is_valid: infallible Bool wrapper around the parser;
//   * uuid_v4_from: 16 caller-supplied random bytes -> canonical v4 text,
//     with the version nibble (byte 6 high nibble = 4) and the RFC 4122
//     variant bits (byte 8 top two bits = 10) forced;
//   * uuid_version and uuid_variant_ok: inspect a parsed UUID.
//
// There is deliberately no randomness source in this package: callers own
// the RNG and pass the 16 bytes in, so every function is deterministic and
// testable. Time-based versions (v1/v6/v7) are out of scope.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType].
//   * Every raw byte is widened as `(byte_at(...) as Int) & 0xFF` before any
//     comparison or arithmetic, so no UInt8 value is compared against an
//     integer literal (including literals >= 128).
//   * Ok/Err for the Result-returning functions are constructed only in the
//     tiny leaf helpers (_ok_*/_err_*); constructing Results directly inside
//     larger functions miscompiles.
//   * This module never compares Str values; callers/tests use
//     xiom.string.compare.str_compare.

module xiom.uuid

use xiom.string;
use xiom.string.builder;

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

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte and hex helpers
// --------------------------------------------------

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so comparisons never touch raw UInt8 values.
fn _byte_at_i(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Lowercase hex digit byte for a nibble value 0..15.
fn _hex_digit(v: Int) -> UInt8 {
  if v < 10 {
    return (48 + v) as UInt8;
  }
  return (87 + v) as UInt8;
}

// Numeric value of a hex digit byte (0-9, a-f, A-F); -1 for any other byte.
fn _hex_value(b: Int) -> Int {
  if b >= 48 && b <= 57 { return b - 48; }
  if b >= 97 && b <= 102 { return b - 87; }
  if b >= 65 && b <= 70 { return b - 55; }
  return -1;
}

// True when position i in the canonical 36-character text is a hyphen
// (zero-based 8, 13, 18, 23).
fn _is_dash_pos(i: Int) -> Bool {
  if i == 8 || i == 13 || i == 18 || i == 23 {
    return true;
  }
  return false;
}

// True when byte i of the 16-byte vector starts a hyphenated group (4, 6, 8
// or 10): a hyphen is emitted before that byte's two hex digits.
fn _is_group_start(i: Int) -> Bool {
  if i == 4 || i == 6 || i == 8 || i == 10 {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Format, parse, validate
// --------------------------------------------------

/// Format exactly 16 bytes as a canonical lowercase UUID.
/// Params: bytes - the 16 bytes, most significant first.
/// Returns: Ok(text) with the 8-4-4-4-12 hyphenated lowercase form
/// (e.g. "00010203-0405-0607-0809-0a0b0c0d0e0f").
/// Error case: Err("uuid: expected 16 bytes") when bytes.len() != 16.
/// Complexity: O(1) (fixed 16 bytes).
pub fn uuid_format(bytes: &Vec[UInt8]) -> Result[Str, Str] {
  if bytes.len() != 16 {
    return _err_str("uuid: expected 16 bytes");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 16 {
    if _is_group_start(i) {
      out.push(45u8);
    }
    let b = (bytes[i] as Int) & 0xFF;
    out.push(_hex_digit(b >> 4));
    out.push(_hex_digit(b & 15));
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

/// Parse a canonical hyphenated UUID into its 16 bytes.
/// Params: s - candidate text. Braces and the URN form are not accepted.
/// Returns: Ok(bytes) when s is exactly 36 bytes in the 8-4-4-4-12 shape
/// with hyphens at zero-based positions 8, 13, 18 and 23 and hex digits
/// elsewhere; hex case is not significant.
/// Error case: Err("uuid: expected 36 characters") for a wrong length,
/// Err("uuid: invalid hyphen placement") for a non-hyphen at a hyphen
/// position, Err("uuid: invalid hex digit") for a non-hex byte elsewhere.
/// Complexity: O(s.len()).
pub fn uuid_parse(s: Str) -> Result[Vec[UInt8], Str] {
  if s.len() != 36 {
    return _err_bytes("uuid: expected 36 characters");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 36 {
    if _is_dash_pos(i) {
      if _byte_at_i(s, i) != 45 {
        return _err_bytes("uuid: invalid hyphen placement");
      }
      i = i + 1;
    } else {
      let hi = _hex_value(_byte_at_i(s, i));
      let lo = _hex_value(_byte_at_i(s, i + 1));
      if hi < 0 || lo < 0 {
        return _err_bytes("uuid: invalid hex digit");
      }
      out.push(((hi << 4) | lo) as UInt8);
      i = i + 2;
    }
  }
  return _ok_bytes(out);
}

/// True when `s` is a canonical hyphenated UUID.
/// Params: s - candidate text.
/// Returns: true exactly when uuid_parse(s) succeeds; false for wrong
/// lengths, misplaced hyphens, non-hex bytes, braces and the URN form.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn uuid_is_valid(s: Str) -> Bool {
  let parsed = uuid_parse(s);
  if parsed.is_ok {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  v4 construction and inspection
// --------------------------------------------------

/// Build a canonical v4 UUID from 16 caller-supplied random bytes.
/// Params: rand - the caller's 16 random bytes.
/// Returns: Ok(text) with the canonical lowercase form after forcing the
/// version nibble (byte 6 high nibble) to 4 and the variant bits (byte 8 top
/// two bits) to 10, per the RFC 4122 v4 layout.
/// Error case: Err("uuid: expected 16 bytes") when rand.len() != 16.
/// Complexity: O(1) (fixed 16 bytes).
pub fn uuid_v4_from(rand: &Vec[UInt8]) -> Result[Str, Str] {
  if rand.len() != 16 {
    return _err_str("uuid: expected 16 bytes");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 16 {
    var v = 0;
    v = (rand[i] as Int) & 0xFF;
    if i == 6 {
      v = (v & 0x0F) | 0x40;
    }
    if i == 8 {
      v = (v & 0x3F) | 0x80;
    }
    out.push(v as UInt8);
    i = i + 1;
  }
  return uuid_format(&out);
}

/// Version number of a canonical UUID.
/// Params: s - candidate UUID text.
/// Returns: Ok(v) where v = (byte 6 >> 4) & 0x0F of the parsed UUID
/// (4 for uuid_v4_from output; any nibble 0..15 is accepted).
/// Error case: Err("uuid: invalid UUID") when s does not parse.
/// Complexity: O(s.len()).
pub fn uuid_version(s: Str) -> Result[Int, Str] {
  let parsed = uuid_parse(s);
  if !parsed.is_ok {
    return _err_int("uuid: invalid UUID");
  }
  let bytes: Vec[UInt8] = parsed.value;
  let b6 = (bytes[6] as Int) & 0xFF;
  return _ok_int((b6 >> 4) & 15);
}

/// True when a canonical UUID carries the RFC 4122 variant bits.
/// Params: s - candidate UUID text.
/// Returns: Ok(true) when byte 8 has its top two bits set to 10 (the
/// RFC 4122 layout, so uuid_v4_from output is always Ok(true)); Ok(false)
/// for the other three variant layouts.
/// Error case: Err("uuid: invalid UUID") when s does not parse.
/// Complexity: O(s.len()).
pub fn uuid_variant_ok(s: Str) -> Result[Bool, Str] {
  let parsed = uuid_parse(s);
  if !parsed.is_ok {
    return _err_bool("uuid: invalid UUID");
  }
  let bytes: Vec[UInt8] = parsed.value;
  let b8 = (bytes[8] as Int) & 0xFF;
  return _ok_bool((b8 & 0xC0) == 0x80);
}
