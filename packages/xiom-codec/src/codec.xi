// XIOM -- xiom.codec: base64, base64url, base32 and hex encoding/decoding
// Port task: replace the xiom.codec placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for alphabets, padding rules, the error
// catalog and the test plan):
//   * base64 (RFC 4648 section 4): standard alphabet, '=' padding on encode;
//     decode ignores ASCII whitespace and accepts well-formed or absent
//     padding.
//   * base64url (RFC 4648 section 5): '-' and '_', no padding on encode;
//     decode additionally accepts the standard '+' and '/' characters and
//     optional '=' padding.
//   * base32 (RFC 4648 section 6): A-Z and 2-7, '=' padding on encode;
//     decode is case-insensitive and accepts optional padding.
//   * hex: lowercase on encode; decode is case-insensitive and rejects
//     odd-length input.
//   * Str <-> UTF-8 byte conversion with strict RFC 3629 validation.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise via
//     xiom.string.byte_at. Every raw byte is widened as
//     `(byte_at(s, i) as Int) & 0xFF` (or the Vec equivalent) before any
//     comparison or arithmetic: comparing a raw UInt8 against a constant
//     >= 128 miscompiles.
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str (one allocation per result Str).
//   * Ok/Err for the Result-returning decode functions are constructed only
//     in the tiny leaf helpers (_ok_str/_err_str/_ok_bytes/_err_bytes);
//     constructing Results directly inside larger functions miscompiles.
//   * UTF-8 validation is implemented locally instead of delegating to
//     xiom.utf8.utf8_validate: in the pinned v0.61.3 stdlib that helper
//     accepts stray bytes >= 0x80 (e.g. 0xFF) as 1-byte "ASCII" sequences,
//     which would make codec_bytes_to_str accept malformed input.
//
// This module never compares Str values (no `==` on Str); callers/tests use
// xiom.string.compare.str_compare.

module xiom.codec

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

// --------------------------------------------------
//  Shared byte helpers
// --------------------------------------------------

// True for the ASCII whitespace bytes ignored by the base64 decoders:
// TAB (9), LF (10), VT (11), FF (12), CR (13) and space (32).
fn _is_ascii_ws(b: Int) -> Bool {
  if b == 9 || b == 10 || b == 11 || b == 12 || b == 13 || b == 32 {
    return true;
  }
  return false;
}

// Base64 value of one standard-alphabet byte ('+', '/' included); -1 when
// the byte is not a base64 character.
fn _b64_value(b: Int) -> Int {
  if b >= 65 && b <= 90 { return b - 65; }
  if b >= 97 && b <= 122 { return b - 71; }
  if b >= 48 && b <= 57 { return b + 4; }
  if b == 43 { return 62; }
  if b == 47 { return 63; }
  return -1;
}

// Base64 value of one byte accepting BOTH alphabets ('-'/'_' and '+'/'/');
// -1 when the byte is not a base64/base64url character.
fn _b64u_value(b: Int) -> Int {
  if b >= 65 && b <= 90 { return b - 65; }
  if b >= 97 && b <= 122 { return b - 71; }
  if b >= 48 && b <= 57 { return b + 4; }
  if b == 45 { return 62; }
  if b == 95 { return 63; }
  if b == 43 { return 62; }
  if b == 47 { return 63; }
  return -1;
}

// Base64 alphabet byte for a 6-bit value (0..63).
fn _b64_char(v: Int, url: Bool) -> UInt8 {
  if url {
    return string.byte_at("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_", v);
  }
  return string.byte_at("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", v);
}

// Base32 value of one byte (A-Z/a-z => 0..25, '2'..'7' => 26..31); -1 when
// the byte is not a base32 character.
fn _b32_value(b: Int) -> Int {
  if b >= 65 && b <= 90 { return b - 65; }
  if b >= 97 && b <= 122 { return b - 97; }
  if b >= 50 && b <= 55 { return b - 24; }
  return -1;
}

// Base32 alphabet byte for a 5-bit value (0..31).
fn _b32_char(v: Int) -> UInt8 {
  return string.byte_at("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567", v);
}

// True when (core data characters, pad '=' characters) cannot decode:
// a base64 data length of 1 (mod 4) is impossible, and explicit padding must
// complete the final quantum (3+1 or 2+2 data/pad split).
fn _b64_bad_count(core: Int, pad: Int) -> Bool {
  let m = core % 4;
  if pad == 0 {
    if m == 1 { return true; }
    return false;
  }
  if (core + pad) % 4 != 0 { return true; }
  if pad == 1 { return m != 3; }
  if pad == 2 { return m != 2; }
  return true;
}

// True when (core data characters, pad '=' characters) cannot decode:
// base32 quanta are 8 characters for 5 bytes, so the only valid data tails
// are 7/5/4/2 characters and padding must complete the quantum to 8.
fn _b32_bad_count(core: Int, pad: Int) -> Bool {
  let m = core % 8;
  if pad == 0 {
    if m == 1 || m == 3 || m == 6 { return true; }
    return false;
  }
  if (core + pad) % 8 != 0 { return true; }
  if pad == 1 { return m != 7; }
  if pad == 3 { return m != 5; }
  if pad == 4 { return m != 4; }
  if pad == 6 { return m != 2; }
  return true;
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
//  Str <-> bytes
// --------------------------------------------------

/// Copy the UTF-8 bytes of `s` into a fresh byte vector.
/// Params: s - any Str.
/// Returns: the bytes verbatim, one push per byte.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn codec_str_to_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

/// Decode a byte vector as UTF-8 text, rejecting malformed sequences.
/// Params: data - the candidate UTF-8 bytes.
/// Returns: Ok(text) when `data` is well-formed UTF-8 (RFC 3629; overlong
/// forms, surrogates and code points above U+10FFFF are rejected).
/// Error case: Err("codec: invalid UTF-8").
/// Complexity: O(data.len()).
pub fn codec_bytes_to_str(data: &Vec[UInt8]) -> Result[Str, Str] {
  if !_utf8_valid(data) {
    return _err_str("codec: invalid UTF-8");
  }
  var copy = Vec[UInt8].new();
  let n = data.len();
  var i = 0;
  while i < n {
    copy.push(data[i]);
    i = i + 1;
  }
  return _ok_str(Str::from_utf8(copy));
}

// --------------------------------------------------
//  Base64 (RFC 4648 section 4)
// --------------------------------------------------

// Shared encoder: standard (url = false, '=' padded) or URL-safe
// (url = true, unpadded).
fn _b64_encode(data: &Vec[UInt8], url: Bool) -> Str {
  var out = Vec[UInt8].new();
  let n = data.len();
  var i = 0;
  while i < n {
    let b0 = (data[i] as Int) & 0xFF;
    let have1 = i + 1 < n;
    let have2 = i + 2 < n;
    var b1 = 0;
    var b2 = 0;
    if have1 { b1 = (data[i + 1] as Int) & 0xFF; }
    if have2 { b2 = (data[i + 2] as Int) & 0xFF; }
    out.push(_b64_char(b0 >> 2, url));
    out.push(_b64_char(((b0 & 3) << 4) | (b1 >> 4), url));
    if have1 {
      out.push(_b64_char(((b1 & 15) << 2) | (b2 >> 6), url));
    } elif !url {
      out.push(61u8);
    }
    if have2 {
      out.push(_b64_char(b2 & 63, url));
    } elif !url {
      out.push(61u8);
    }
    i = i + 3;
  }
  return builder.sb_to_str(&out);
}

/// Encode bytes as standard base64 with mandatory '=' padding.
/// Params: data - the bytes to encode.
/// Returns: the RFC 4648 section 4 encoding (alphabet A-Z a-z 0-9 + /);
/// empty input yields "". Two '=' pad a 1-byte tail, one '=' a 2-byte tail.
/// Error case: none.
/// Complexity: O(data.len()).
pub fn codec_b64_encode(data: &Vec[UInt8]) -> Str {
  return _b64_encode(data, false);
}

/// Encode bytes as URL-safe base64 WITHOUT '=' padding.
/// Params: data - the bytes to encode.
/// Returns: the RFC 4648 section 5 encoding (alphabet A-Z a-z 0-9 - _);
/// empty input yields "". Output length is 4*floor(n/3) plus 2 or 3 for a
/// 1- or 2-byte tail.
/// Error case: none.
/// Complexity: O(data.len()).
pub fn codec_b64url_encode(data: &Vec[UInt8]) -> Str {
  return _b64_encode(data, true);
}

// Shared decoder: standard alphabet when url = false, both alphabets when
// url = true. ASCII whitespace is ignored anywhere.
fn _b64_decode(s: Str, url: Bool) -> Result[Vec[UInt8], Str] {
  var vals = Vec[Int].new();
  let n = s.len();
  var pad = 0;
  var seen_pad = false;
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if _is_ascii_ws(b) {
      i = i + 1;
    } elif b == 61 {
      pad = pad + 1;
      seen_pad = true;
      i = i + 1;
    } else {
      if seen_pad {
        return _err_bytes("codec: invalid base64 padding");
      }
      var v = 0;
      if url {
        v = _b64u_value(b);
      } else {
        v = _b64_value(b);
      }
      if v < 0 {
        return _err_bytes("codec: invalid base64 character");
      }
      vals.push(v);
      i = i + 1;
    }
  }
  if pad > 2 || _b64_bad_count(vals.len(), pad) {
    return _err_bytes("codec: invalid base64 padding");
  }
  var out = Vec[UInt8].new();
  let core = vals.len();
  var k = 0;
  while k + 4 <= core {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    let v2: Int = vals[k + 2];
    let v3: Int = vals[k + 3];
    out.push(((v0 << 2) | (v1 >> 4)) as UInt8);
    out.push(((v1 << 4) | (v2 >> 2)) as UInt8);
    out.push(((v2 << 6) | v3) as UInt8);
    k = k + 4;
  }
  let rem = core - k;
  if rem == 2 {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    out.push(((v0 << 2) | (v1 >> 4)) as UInt8);
  } elif rem == 3 {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    let v2: Int = vals[k + 2];
    out.push(((v0 << 2) | (v1 >> 4)) as UInt8);
    out.push(((v1 << 4) | (v2 >> 2)) as UInt8);
  }
  return _ok_bytes(out);
}

/// Decode a standard base64 string to bytes.
/// Params: s - the encoded text; ASCII whitespace (TAB, LF, VT, FF, CR,
/// space) is ignored anywhere.
/// Returns: Ok(bytes) for well-formed standard base64. Explicit '=' padding
/// is optional but, when present, must complete the final quantum; a data
/// length of 1 (mod 4) with or without padding is rejected. Trailing bits of
/// a partial tail are ignored (non-canonical encodings are accepted).
/// Error case: Err("codec: invalid base64 character") for a byte outside the
/// standard alphabet, Err("codec: invalid base64 padding") for misplaced or
/// inconsistent '='.
/// Complexity: O(s.len()).
pub fn codec_b64_decode(s: Str) -> Result[Vec[UInt8], Str] {
  return _b64_decode(s, false);
}

/// Decode a base64url string to bytes.
/// Params: s - the encoded text; ASCII whitespace is ignored anywhere.
/// Returns: Ok(bytes). Both the URL-safe alphabet ('-', '_') and the
/// standard one ('+', '/') are accepted, and '=' padding is optional.
/// Error case: Err("codec: invalid base64 character") and
/// Err("codec: invalid base64 padding"), same rules as codec_b64_decode.
/// Complexity: O(s.len()).
pub fn codec_b64url_decode(s: Str) -> Result[Vec[UInt8], Str] {
  return _b64_decode(s, true);
}

// --------------------------------------------------
//  Base32 (RFC 4648 section 6)
// --------------------------------------------------

/// Encode bytes as base32 with mandatory '=' padding.
/// Params: data - the bytes to encode.
/// Returns: the RFC 4648 section 6 encoding (alphabet A-Z 2-7); empty input
/// yields "". The output is always padded to a multiple of 8 characters.
/// Error case: none.
/// Complexity: O(data.len()).
pub fn codec_base32_encode(data: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  let n = data.len();
  var acc = 0;
  var bits = 0;
  var i = 0;
  while i < n {
    acc = (acc << 8) | ((data[i] as Int) & 0xFF);
    bits = bits + 8;
    while bits >= 5 {
      bits = bits - 5;
      out.push(_b32_char((acc >> bits) & 31));
    }
    acc = acc & 0xFF;
    i = i + 1;
  }
  if bits > 0 {
    out.push(_b32_char((acc << (5 - bits)) & 31));
  }
  while (out.len() % 8) != 0 {
    out.push(61u8);
  }
  return builder.sb_to_str(&out);
}

/// Decode a base32 string to bytes.
/// Params: s - the encoded text; decoding is case-insensitive.
/// Returns: Ok(bytes) for well-formed base32. '=' padding is optional but,
/// when present, must complete the final 8-character quantum; the only valid
/// data tails are 7/5/4/2 characters plus full 8-character groups. Trailing
/// bits of a partial tail are ignored (non-canonical encodings are accepted).
/// Error case: Err("codec: invalid base32 character") for a byte outside
/// A-Z a-z 2-7, Err("codec: invalid base32 padding") for misplaced or
/// inconsistent '='.
/// Complexity: O(s.len()).
pub fn codec_base32_decode(s: Str) -> Result[Vec[UInt8], Str] {
  var vals = Vec[Int].new();
  let n = s.len();
  var pad = 0;
  var seen_pad = false;
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 61 {
      pad = pad + 1;
      seen_pad = true;
      i = i + 1;
    } else {
      if seen_pad {
        return _err_bytes("codec: invalid base32 padding");
      }
      let v = _b32_value(b);
      if v < 0 {
        return _err_bytes("codec: invalid base32 character");
      }
      vals.push(v);
      i = i + 1;
    }
  }
  let core = vals.len();
  if _b32_bad_count(core, pad) {
    return _err_bytes("codec: invalid base32 padding");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k + 8 <= core {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    let v2: Int = vals[k + 2];
    let v3: Int = vals[k + 3];
    let v4: Int = vals[k + 4];
    let v5: Int = vals[k + 5];
    let v6: Int = vals[k + 6];
    let v7: Int = vals[k + 7];
    out.push(((v0 << 3) | (v1 >> 2)) as UInt8);
    out.push((((v1 & 3) << 6) | (v2 << 1) | (v3 >> 4)) as UInt8);
    out.push((((v3 & 15) << 4) | (v4 >> 1)) as UInt8);
    out.push((((v4 & 1) << 7) | (v5 << 2) | (v6 >> 3)) as UInt8);
    out.push((((v6 & 7) << 5) | v7) as UInt8);
    k = k + 8;
  }
  let rem = core - k;
  if rem == 7 {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    let v2: Int = vals[k + 2];
    let v3: Int = vals[k + 3];
    let v4: Int = vals[k + 4];
    let v5: Int = vals[k + 5];
    let v6: Int = vals[k + 6];
    out.push(((v0 << 3) | (v1 >> 2)) as UInt8);
    out.push((((v1 & 3) << 6) | (v2 << 1) | (v3 >> 4)) as UInt8);
    out.push((((v3 & 15) << 4) | (v4 >> 1)) as UInt8);
    out.push((((v4 & 1) << 7) | (v5 << 2) | (v6 >> 3)) as UInt8);
  } elif rem == 5 {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    let v2: Int = vals[k + 2];
    let v3: Int = vals[k + 3];
    let v4: Int = vals[k + 4];
    out.push(((v0 << 3) | (v1 >> 2)) as UInt8);
    out.push((((v1 & 3) << 6) | (v2 << 1) | (v3 >> 4)) as UInt8);
    out.push((((v3 & 15) << 4) | (v4 >> 1)) as UInt8);
  } elif rem == 4 {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    let v2: Int = vals[k + 2];
    let v3: Int = vals[k + 3];
    out.push(((v0 << 3) | (v1 >> 2)) as UInt8);
    out.push((((v1 & 3) << 6) | (v2 << 1) | (v3 >> 4)) as UInt8);
  } elif rem == 2 {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    out.push(((v0 << 3) | (v1 >> 2)) as UInt8);
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Hex
// --------------------------------------------------

// Lowercase hex digit byte for a nibble value (0..15).
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

/// Encode bytes as lowercase hexadecimal (two digits per byte).
/// Params: data - the bytes to encode.
/// Returns: the lowercase hex text; empty input yields "".
/// Error case: none.
/// Complexity: O(data.len()).
pub fn codec_hex_encode(data: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  let n = data.len();
  var i = 0;
  while i < n {
    let b = (data[i] as Int) & 0xFF;
    out.push(_hex_digit(b >> 4));
    out.push(_hex_digit(b & 15));
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Decode hexadecimal text (upper- or lowercase) to bytes.
/// Params: s - the hex text; no prefixes, separators or whitespace are
/// accepted.
/// Returns: Ok(bytes) for an even-length run of hex digits; empty input
/// yields Ok(empty).
/// Error case: Err("codec: odd-length hex input") when s.len() is odd,
/// Err("codec: invalid hex character") for any byte outside 0-9 a-f A-F.
/// Complexity: O(s.len()).
pub fn codec_hex_decode(s: Str) -> Result[Vec[UInt8], Str] {
  let n = s.len();
  if n % 2 != 0 {
    return _err_bytes("codec: odd-length hex input");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let hi = _hex_value((string.byte_at(s, i) as Int) & 0xFF);
    let lo = _hex_value((string.byte_at(s, i + 1) as Int) & 0xFF);
    if hi < 0 || lo < 0 {
      return _err_bytes("codec: invalid hex character");
    }
    out.push(((hi << 4) | lo) as UInt8);
    i = i + 2;
  }
  return _ok_bytes(out);
}
