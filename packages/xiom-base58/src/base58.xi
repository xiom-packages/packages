// XIOM -- xiom.base58: Base58 (Bitcoin alphabet) encoding and decoding
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) Base58 codec over the Bitcoin alphabet
// (123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz):
//   * base58_encode: big-integer base-256 -> base-58 conversion via repeated
//     division of a working byte array; each leading 0x00 byte becomes one
//     leading '1' character (Bitcoin convention).
//   * base58_decode: big-integer base-58 -> base-256 conversion via repeated
//     multiply-add over a little-endian accumulator; each leading '1' becomes
//     one leading 0x00 byte.
//   * Str helpers (encode_str/decode_str) cross the UTF-8 boundary;
//     base58_decode_str validates the decoded bytes as RFC 3629 UTF-8 before
//     returning a Str.
//
// Base58Check is intentionally NOT implemented: it requires a 4-byte
// double-SHA-256 checksum, and SHA-256 is not available in the pinned
// v0.61.3 compiler (32-bit bitwise ops with the high bit set miscompile, and
// there is no bitcast intrinsic). See SPEC.md section 3.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType].
//   * Every raw byte read via xiom.string.byte_at or from a Vec[UInt8] is
//     widened with `(x as Int) & 0xFF` before comparison or arithmetic:
//     comparing a raw UInt8 against a constant >= 128 miscompiles.
//   * Ok/Err for Result-returning functions are constructed only in the tiny
//     leaf helpers (_ok_bytes/_err_bytes/_ok_str/_err_str); constructing
//     Results directly inside larger functions miscompiles.
//   * Passing `&result.value` (a reference to a Result field) directly into a
//     `&Vec[UInt8]` parameter makes the callee see an empty vector in
//     v0.61.3; bind the field to a local before taking its reference (see
//     base58_decode_str).
//   * UTF-8 validation is implemented locally instead of delegating to
//     xiom.utf8.utf8_validate: in the pinned v0.61.3 stdlib that helper
//     accepts stray bytes >= 0x80 (e.g. 0xFF) as 1-byte "ASCII" sequences,
//     which would make base58_decode_str accept malformed input.
//
// This module never compares Str values (no `==` on Str); callers/tests use
// xiom.string.compare.str_compare.

module xiom.base58

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Alphabet
// --------------------------------------------------

/// The Bitcoin base58 alphabet (58 characters, no '0', 'O', 'I' or 'l').
/// Returns: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".
/// Error case: none.
/// Complexity: O(1).
pub fn base58_alphabet() -> Str {
  return "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Base58 value (0..57) of one alphabet byte; -1 when the byte is not in the
// Bitcoin alphabet. Linear scan over the 58-character alphabet.
fn _b58_value(b: Int) -> Int {
  let alpha = base58_alphabet();
  var i = 0;
  while i < 58 {
    let a = (string.byte_at(alpha, i) as Int) & 0xFF;
    if a == b {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when the byte is a UTF-8 continuation byte (10xxxxxx).
fn _is_cont(b: Int) -> Bool {
  return (b & 0xC0) == 0x80;
}

// True when `data` is well-formed UTF-8 per RFC 3629. Rejects stray
// continuation bytes, truncated sequences, overlong forms, UTF-16 surrogate
// code points (U+D800..U+DFFF) and code points above U+10FFFF.
fn _utf8_valid(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  var i = 0;
  while i < n {
    let b0 = (data[i] as Int) & 0xFF;
    if b0 <= 0x7F {
      i = i + 1;
    } elif b0 >= 0xC2 && b0 <= 0xDF {
      if i + 1 >= n { return false; }
      let b1 = (data[i + 1] as Int) & 0xFF;
      if !_is_cont(b1) { return false; }
      i = i + 2;
    } elif b0 >= 0xE0 && b0 <= 0xEF {
      if i + 2 >= n { return false; }
      let b1 = (data[i + 1] as Int) & 0xFF;
      let b2 = (data[i + 2] as Int) & 0xFF;
      if !_is_cont(b1) || !_is_cont(b2) { return false; }
      if b0 == 0xE0 && b1 < 0xA0 { return false; }
      if b0 == 0xED && b1 >= 0xA0 { return false; }
      i = i + 3;
    } elif b0 >= 0xF0 && b0 <= 0xF4 {
      if i + 3 >= n { return false; }
      let b1 = (data[i + 1] as Int) & 0xFF;
      let b2 = (data[i + 2] as Int) & 0xFF;
      let b3 = (data[i + 3] as Int) & 0xFF;
      if !_is_cont(b1) || !_is_cont(b2) || !_is_cont(b3) { return false; }
      if b0 == 0xF0 && b1 < 0x90 { return false; }
      if b0 == 0xF4 && b1 > 0x8F { return false; }
      i = i + 4;
    } else {
      return false;
    }
  }
  return true;
}

// --------------------------------------------------
//  Bytes -> base58
// --------------------------------------------------

/// Encode bytes as base58 (Bitcoin alphabet).
/// Params: data - the bytes to encode.
/// Returns: the base58 text. Each leading 0x00 byte becomes one leading '1';
/// the numeric value of the remaining bytes is written in base 58 with the
/// minimal number of digits. Empty input yields "".
/// Error case: none (total).
/// Complexity: O(n^2) worst case (repeated long division of the working
/// array), n = data.len().
pub fn base58_encode(data: &Vec[UInt8]) -> Str {
  let n = data.len();
  if n == 0 {
    return "";
  }
  var zeros = 0;
  while zeros < n {
    let b = (data[zeros] as Int) & 0xFF;
    if b != 0 {
      break;
    }
    zeros = zeros + 1;
  }
  var work = Vec[Int].new();
  var i = 0;
  while i < n {
    work.push((data[i] as Int) & 0xFF);
    i = i + 1;
  }
  var digits = Vec[Int].new();
  var start = zeros;
  while start < n {
    var remainder = 0;
    var j = start;
    while j < n {
      let w: Int = work[j];
      let acc = remainder * 256 + w;
      work[j] = acc / 58;
      remainder = acc % 58;
      j = j + 1;
    }
    digits.push(remainder);
    while start < n && work[start] == 0 {
      start = start + 1;
    }
  }
  var out = Vec[UInt8].new();
  var z = 0;
  while z < zeros {
    out.push(49u8);
    z = z + 1;
  }
  let alpha = base58_alphabet();
  var k = digits.len() - 1;
  while k >= 0 {
    let d: Int = digits[k];
    out.push(string.byte_at(alpha, d));
    k = k - 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Base58 -> bytes
// --------------------------------------------------

/// Decode base58 text (Bitcoin alphabet) to bytes.
/// Params: s - the base58 text; only the 58 Bitcoin alphabet characters are
/// accepted (no whitespace, sign, padding or aliases).
/// Returns: Ok(bytes). Each leading '1' becomes one leading 0x00 byte; the
/// value of the remaining characters is written big-endian in base 256 with
/// no leading zero bytes. Empty input yields Ok(empty).
/// Error case: Err("base58: invalid character") for any byte outside the
/// alphabet.
/// Complexity: O(n^2) worst case (repeated multiply-add), n = s.len().
pub fn base58_decode(s: Str) -> Result[Vec[UInt8], Str] {
  let n = s.len();
  var zeros = 0;
  while zeros < n {
    let b = (string.byte_at(s, zeros) as Int) & 0xFF;
    if b != 49 {
      break;
    }
    zeros = zeros + 1;
  }
  var bytes = Vec[Int].new();
  var i = zeros;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    let v = _b58_value(b);
    if v < 0 {
      return _err_bytes("base58: invalid character");
    }
    var carry = v;
    var k = 0;
    while k < bytes.len() {
      let cur: Int = bytes[k];
      let acc = cur * 58 + carry;
      bytes[k] = acc % 256;
      carry = acc / 256;
      k = k + 1;
    }
    while carry > 0 {
      bytes.push(carry % 256);
      carry = carry / 256;
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  var z = 0;
  while z < zeros {
    out.push(0u8);
    z = z + 1;
  }
  var bi = bytes.len() - 1;
  while bi >= 0 {
    let v: Int = bytes[bi];
    out.push(v as UInt8);
    bi = bi - 1;
  }
  return _ok_bytes(out);
}

/// True when `s` is valid base58 text.
/// Params: s - the candidate text.
/// Returns: true when every byte is a Bitcoin-alphabet character; true for
/// empty input (which decodes to an empty byte vector).
/// Error case: none.
/// Complexity: O(s.len() * 58) worst case (alphabet scan per byte).
pub fn base58_is_valid(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if _b58_value(b) < 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Str <-> base58
// --------------------------------------------------

/// Encode the UTF-8 bytes of a Str as base58.
/// Params: s - any Str.
/// Returns: base58 of the raw UTF-8 bytes of `s`; empty input yields "".
/// Error case: none (total; every Str has a UTF-8 byte representation).
/// Complexity: O(s.len()^2) worst case.
pub fn base58_encode_str(s: Str) -> Str {
  var bytes = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    bytes.push(string.byte_at(s, i));
    i = i + 1;
  }
  return base58_encode(&bytes);
}

/// Decode base58 text to a Str, validating the decoded bytes as UTF-8.
/// Params: s - the base58 text.
/// Returns: Ok(text) when `s` is valid base58 and its decoded bytes are
/// well-formed RFC 3629 UTF-8; empty input yields Ok("").
/// Error case: Err("base58: invalid character") for a byte outside the
/// alphabet; Err("base58: invalid UTF-8") when the decoded bytes are not
/// well-formed UTF-8 (overlong forms, surrogates and code points above
/// U+10FFFF are rejected).
/// Complexity: O(s.len()^2) worst case.
pub fn base58_decode_str(s: Str) -> Result[Str, Str] {
  let dec = base58_decode(s);
  if !dec.is_ok {
    return _err_str(dec.error);
  }
  // v0.61.3 quirk: passing `&dec.value` (a reference to a Result field)
  // straight into a `&Vec[UInt8]` parameter makes the callee see an EMPTY
  // vector, so the field is bound to a local first.
  let bytes = dec.value;
  if !_utf8_valid(&bytes) {
    return _err_str("base58: invalid UTF-8");
  }
  var copy = Vec[UInt8].new();
  let n = bytes.len();
  var i = 0;
  while i < n {
    copy.push(bytes[i]);
    i = i + 1;
  }
  return _ok_str(Str::from_utf8(copy));
}
