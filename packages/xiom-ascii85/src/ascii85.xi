// XIOM -- xiom.ascii85: Adobe ASCII85 (Base85) encoding and decoding
// Port task: greenfield pure-XIOM (no FFI) ASCII85 package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// ASCII85 is Adobe's Base85, the text encoding used by PostScript and PDF
// streams:
//   * Alphabet: '!' (33) through 'u' (117) -- 85 characters, up to 85^5 - 1
//     values, which covers a full 32-bit word.
//   * a85_encode: each 4-byte big-endian group becomes 5 characters (most
//     significant digit first); an all-zero group becomes 'z'; a final
//     partial group of n bytes (1..3) becomes n+1 characters (the group is
//     zero-padded internally and the output truncated); empty input yields
//     "". No "<~"/"~>" delimiters and no line wrapping are emitted.
//   * a85_decode: ASCII whitespace is skipped anywhere; one optional leading
//     "<~" and one optional trailing "~>" are accepted; 'z' is legal only at
//     a group boundary and decodes to four zero bytes; a final partial group
//     of 2..4 characters decodes to 1..3 bytes; a single leftover character
//     is an error; a group whose value exceeds 32 bits is an error.
//
// See SPEC.md for the alphabet, the group rules, the error catalog and the
// test plan.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType].
//   * Every raw byte read via xiom.string.byte_at or from a Vec[UInt8] is
//     widened with `(x as Int) & 0xFF` before comparison or arithmetic:
//     comparing a raw UInt8 against a constant >= 128 miscompiles.
//   * Ok/Err for the Result-returning a85_decode are constructed only in the
//     tiny leaf helpers (_ok_bytes/_err_bytes); constructing Results directly
//     inside larger functions miscompiles.
//   * 32-bit words are built and split with multiplication/division
//     (b0 * 16777216 + b1 * 65536 + b2 * 256 + b3) rather than shifts on a
//     value with the high bit set.
//   * Int values read from a Vec[Int] are bound with an explicit
//     `let v: Int = ...` before use.
//
// This module never compares Str values (no `==` on Str); callers/tests use
// xiom.string.compare.str_compare.

module xiom.ascii85

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// First byte of the ASCII85 alphabet ('!').
const _A85_LOW: Int = 33;

// 'z' -- the four-zero-byte group shorthand.
const _A85_Z: Int = 122;

// Last byte of the ASCII85 alphabet ('u' = 117).
const _A85_HIGH: Int = 117;

// 2^32 - 1: the largest value a 4-byte group can hold.
const _A85_MAX32: Int = 4294967295;

// The largest ASCII85 digit ('u' = 84), used to pad a final partial group.
const _A85_MAX_DIGIT: Int = 84;

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

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// True for the ASCII whitespace bytes skipped by a85_decode: TAB (9), LF
// (10), VT (11), FF (12), CR (13) and space (32).
fn _is_ascii_ws(b: Int) -> Bool {
  if b == 9 || b == 10 || b == 11 || b == 12 || b == 13 || b == 32 {
    return true;
  }
  return false;
}

// ASCII85 digit value (0..84) of one alphabet byte; -1 when the byte is not
// an ASCII85 digit. 'z' (122) is handled by the caller, not here.
fn _a85_value(b: Int) -> Int {
  if b >= _A85_LOW && b <= _A85_HIGH {
    return b - _A85_LOW;
  }
  return -1;
}

// --------------------------------------------------
//  Bytes -> ASCII85
// --------------------------------------------------

/// Encode bytes as Adobe ASCII85.
/// Params: data - the bytes to encode.
/// Returns: the ASCII85 text over the '!'..'u' alphabet. Each full 4-byte
/// group becomes 5 characters, except an all-zero group, which becomes the
/// shorthand 'z'; a final partial group of n bytes (1..3) becomes n+1
/// characters; empty input yields "". No "<~"/"~>" delimiters and no line
/// wrapping are emitted.
/// Error case: none (total).
/// Complexity: O(data.len()).
pub fn a85_encode(data: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  let n = data.len();
  var i = 0;
  while i < n {
    let rem = n - i;
    let b0 = (data[i] as Int) & 0xFF;
    var b1 = 0;
    var b2 = 0;
    var b3 = 0;
    if rem > 1 { b1 = (data[i + 1] as Int) & 0xFF; }
    if rem > 2 { b2 = (data[i + 2] as Int) & 0xFF; }
    if rem > 3 { b3 = (data[i + 3] as Int) & 0xFF; }
    let word = (((b0 * 256) + b1) * 256 + b2) * 256 + b3;
    var used = rem;
    if used > 4 { used = 4; }
    if used == 4 && word == 0 {
      out.push(122u8);
    } else {
      var work = word;
      let d4 = work % 85;
      work = work / 85;
      let d3 = work % 85;
      work = work / 85;
      let d2 = work % 85;
      work = work / 85;
      let d1 = work % 85;
      work = work / 85;
      let d0 = work % 85;
      out.push((_A85_LOW + d0) as UInt8);
      out.push((_A85_LOW + d1) as UInt8);
      if used > 1 { out.push((_A85_LOW + d2) as UInt8); }
      if used > 2 { out.push((_A85_LOW + d3) as UInt8); }
      if used > 3 { out.push((_A85_LOW + d4) as UInt8); }
    }
    i = i + used;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  ASCII85 -> bytes
// --------------------------------------------------

/// Decode Adobe ASCII85 text to bytes.
/// Params: text - the encoded text. ASCII whitespace (TAB, LF, VT, FF, CR,
/// space) is ignored anywhere; one optional leading "<~" and one optional
/// trailing "~>" are accepted after surrounding whitespace.
/// Returns: Ok(bytes) for a well-formed ASCII85 stream. 'z' decodes to four
/// zero bytes and is legal only at a group boundary; a final partial group
/// of 2..4 characters decodes to 1..3 bytes; empty input (or only
/// delimiters/whitespace) yields Ok(empty).
/// Error case: Err("ascii85: invalid character") for a byte outside '!'..'u'
/// (including an interior '~'); Err("ascii85: z inside group") when 'z'
/// follows one or more digits of an unfinished group;
/// Err("ascii85: incomplete group") for a single leftover character;
/// Err("ascii85: value overflows 32 bits") when a group's value exceeds
/// 0xFFFFFFFF (for a partial group, after the implicit 'u' padding).
/// Complexity: O(text.len()).
pub fn a85_decode(text: Str) -> Result[Vec[UInt8], Str] {
  let n = text.len();
  var lo = 0;
  while lo < n {
    let w = (string.byte_at(text, lo) as Int) & 0xFF;
    if !_is_ascii_ws(w) { break; }
    lo = lo + 1;
  }
  var hi = n;
  while hi > lo {
    let w = (string.byte_at(text, hi - 1) as Int) & 0xFF;
    if !_is_ascii_ws(w) { break; }
    hi = hi - 1;
  }
  if hi - lo >= 2 {
    let c0 = (string.byte_at(text, lo) as Int) & 0xFF;
    let c1 = (string.byte_at(text, lo + 1) as Int) & 0xFF;
    if c0 == 60 && c1 == 126 {
      lo = lo + 2;
    }
  }
  if hi - lo >= 2 {
    let c0 = (string.byte_at(text, hi - 2) as Int) & 0xFF;
    let c1 = (string.byte_at(text, hi - 1) as Int) & 0xFF;
    if c0 == 126 && c1 == 62 {
      hi = hi - 2;
    }
  }
  var out = Vec[UInt8].new();
  var group = Vec[Int].new();
  var i = lo;
  while i < hi {
    let b = (string.byte_at(text, i) as Int) & 0xFF;
    if _is_ascii_ws(b) {
      i = i + 1;
    } elif b == _A85_Z {
      if group.len() != 0 {
        return _err_bytes("ascii85: z inside group");
      }
      out.push(0u8);
      out.push(0u8);
      out.push(0u8);
      out.push(0u8);
      i = i + 1;
    } else {
      let d = _a85_value(b);
      if d < 0 {
        return _err_bytes("ascii85: invalid character");
      }
      group.push(d);
      i = i + 1;
      if group.len() == 5 {
        let v0: Int = group[0];
        let v1: Int = group[1];
        let v2: Int = group[2];
        let v3: Int = group[3];
        let v4: Int = group[4];
        let value = ((((v0 * 85 + v1) * 85 + v2) * 85 + v3) * 85 + v4);
        if value > _A85_MAX32 {
          return _err_bytes("ascii85: value overflows 32 bits");
        }
        out.push((value / 16777216) as UInt8);
        out.push(((value / 65536) % 256) as UInt8);
        out.push(((value / 256) % 256) as UInt8);
        out.push((value % 256) as UInt8);
        group = Vec[Int].new();
      }
    }
  }
  let left = group.len();
  if left == 1 {
    return _err_bytes("ascii85: incomplete group");
  }
  if left >= 2 {
    var value = 0;
    var k = 0;
    while k < left {
      let d: Int = group[k];
      value = value * 85 + d;
      k = k + 1;
    }
    var missing = 5 - left;
    while missing > 0 {
      value = value * 85 + _A85_MAX_DIGIT;
      missing = missing - 1;
    }
    if value > _A85_MAX32 {
      return _err_bytes("ascii85: value overflows 32 bits");
    }
    out.push((value / 16777216) as UInt8);
    if left > 2 { out.push(((value / 65536) % 256) as UInt8); }
    if left > 3 { out.push(((value / 256) % 256) as UInt8); }
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Validation and sizing
// --------------------------------------------------

/// True when `text` is valid ASCII85.
/// Params: text - the candidate text (whitespace and the optional "<~"/"~>"
/// delimiters are treated as in a85_decode).
/// Returns: true when a85_decode(text) would return Ok, false otherwise;
/// true for empty input.
/// Error case: none.
/// Complexity: O(text.len()).
pub fn a85_is_valid(text: Str) -> Bool {
  let r = a85_decode(text);
  if r.is_ok {
    return true;
  }
  return false;
}

/// Upper bound on the number of bytes a85_decode can return for `chars`
/// ASCII85 characters (whitespace and delimiters excluded).
/// Params: chars - the encoded character count.
/// Returns: ceil(chars * 4 / 5); 0 when chars <= 0. The 'z' shorthand only
/// makes the bound looser, so it remains valid for any well-formed input.
/// Error case: none.
/// Complexity: O(1).
pub fn a85_max_decoded_len(chars: Int) -> Int {
  if chars <= 0 {
    return 0;
  }
  return (chars * 4 + 4) / 5;
}
