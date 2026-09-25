// XIOM -- xiom.base32: RFC 4648 Base32 encoding and decoding
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) RFC 4648 Base32 codec over the standard alphabet
// (A-Z, 2-7):
//   * base32_encode: every 5-byte group becomes 8 characters, most
//     significant group first; a final partial group of 1..4 bytes becomes
//     2/4/5/7 characters followed by 6/4/3/1 '=' pad characters; empty input
//     yields "".
//   * base32_decode: byte-wise and case-insensitive (a-z equals A-Z).
//     Canonical RFC 4648 padding is REQUIRED for a partial final group:
//     unpadded partial groups are rejected with "base32: truncated group".
//     '=' is legal only in the final 6/4/3/1-character pad run, and the
//     unused trailing bits of the final group must be zero.
//
// Deliberately NOT implemented: base32hex (RFC 4648 section 7), any other
// alphabet variant, streaming/incremental APIs, and base64/hex (sibling
// packages own those). See SPEC.md.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType].
//   * Every raw byte read via xiom.string.byte_at is widened with
//     `(x as Int) & 0xFF` before comparison or arithmetic: comparing a raw
//     UInt8 against a constant >= 128 miscompiles.
//   * No bitwise shifts: 40-bit groups are split with multiplication,
//     division and modulo only (shifts on values with the high bit set
//     miscompile in v0.61.3).
//   * Ok/Err for the Result-returning functions are constructed only in the
//     tiny leaf helpers _ok_bytes/_err_bytes; constructing Results directly
//     inside larger functions miscompiles.
//
// This module never compares Str values (no `==` on Str); callers/tests use
// xiom.string.compare.str_compare.

module xiom.base32

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Alphabet
// --------------------------------------------------

/// The RFC 4648 standard base32 alphabet (32 characters).
/// Returns: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".
/// Error case: none.
/// Complexity: O(1).
pub fn base32_alphabet() -> Str {
  return "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
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

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Base32 digit value (0..31) of one encoded byte; -1 when the byte is not an
// alphabet character. Uppercase and lowercase A-Z both map to 0..25
// (RFC 4648 section 6 case-insensitive decoding) and '2'..'7' map to 26..31.
// The pad byte '=' (61) is handled by the caller, not here.
fn _b32_value(b: Int) -> Int {
  if b >= 65 && b <= 90 {
    return b - 65;
  }
  if b >= 97 && b <= 122 {
    return b - 97;
  }
  if b >= 50 && b <= 55 {
    return b - 24;
  }
  return -1;
}

// 2^k for 0 <= k <= 7, the only exponents the decoder needs.
fn _pow2(k: Int) -> Int {
  var r = 1;
  var i = 0;
  while i < k {
    r = r * 2;
    i = i + 1;
  }
  return r;
}

// --------------------------------------------------
//  Bytes -> base32
// --------------------------------------------------

/// Encode bytes as RFC 4648 base32 (standard alphabet, with '=' padding).
/// Params: data - the bytes to encode.
/// Returns: the canonical base32 text. Every full 5-byte group becomes 8
/// characters; a final partial group of 1, 2, 3 or 4 bytes becomes 2, 4, 5 or
/// 7 characters followed by 6, 4, 3 or 1 '=' pad characters so the output
/// length is always a multiple of 8; empty input yields "".
/// Error case: none (total; the encoder never validates its input).
/// Complexity: O(data.len()).
pub fn base32_encode(data: &Vec[UInt8]) -> Str {
  let alpha = base32_alphabet();
  var out = Vec[UInt8].new();
  let n = data.len();
  var i = 0;
  while i + 5 <= n {
    let b0 = (data[i] as Int) & 0xFF;
    let b1 = (data[i + 1] as Int) & 0xFF;
    let b2 = (data[i + 2] as Int) & 0xFF;
    let b3 = (data[i + 3] as Int) & 0xFF;
    let b4 = (data[i + 4] as Int) & 0xFF;
    out.push(string.byte_at(alpha, b0 / 8));
    out.push(string.byte_at(alpha, (b0 % 8) * 4 + b1 / 64));
    out.push(string.byte_at(alpha, (b1 % 64) / 2));
    out.push(string.byte_at(alpha, (b1 % 2) * 16 + b2 / 16));
    out.push(string.byte_at(alpha, (b2 % 16) * 2 + b3 / 128));
    out.push(string.byte_at(alpha, (b3 % 128) / 4));
    out.push(string.byte_at(alpha, (b3 % 4) * 8 + b4 / 32));
    out.push(string.byte_at(alpha, b4 % 32));
    i = i + 5;
  }
  let rem = n - i;
  var pad = 0;
  if rem == 1 {
    let b0 = (data[i] as Int) & 0xFF;
    out.push(string.byte_at(alpha, b0 / 8));
    out.push(string.byte_at(alpha, (b0 % 8) * 4));
    pad = 6;
  } elif rem == 2 {
    let b0 = (data[i] as Int) & 0xFF;
    let b1 = (data[i + 1] as Int) & 0xFF;
    out.push(string.byte_at(alpha, b0 / 8));
    out.push(string.byte_at(alpha, (b0 % 8) * 4 + b1 / 64));
    out.push(string.byte_at(alpha, (b1 % 64) / 2));
    out.push(string.byte_at(alpha, (b1 % 2) * 16));
    pad = 4;
  } elif rem == 3 {
    let b0 = (data[i] as Int) & 0xFF;
    let b1 = (data[i + 1] as Int) & 0xFF;
    let b2 = (data[i + 2] as Int) & 0xFF;
    out.push(string.byte_at(alpha, b0 / 8));
    out.push(string.byte_at(alpha, (b0 % 8) * 4 + b1 / 64));
    out.push(string.byte_at(alpha, (b1 % 64) / 2));
    out.push(string.byte_at(alpha, (b1 % 2) * 16 + b2 / 16));
    out.push(string.byte_at(alpha, (b2 % 16) * 2));
    pad = 3;
  } elif rem == 4 {
    let b0 = (data[i] as Int) & 0xFF;
    let b1 = (data[i + 1] as Int) & 0xFF;
    let b2 = (data[i + 2] as Int) & 0xFF;
    let b3 = (data[i + 3] as Int) & 0xFF;
    out.push(string.byte_at(alpha, b0 / 8));
    out.push(string.byte_at(alpha, (b0 % 8) * 4 + b1 / 64));
    out.push(string.byte_at(alpha, (b1 % 64) / 2));
    out.push(string.byte_at(alpha, (b1 % 2) * 16 + b2 / 16));
    out.push(string.byte_at(alpha, (b2 % 16) * 2 + b3 / 128));
    out.push(string.byte_at(alpha, (b3 % 128) / 4));
    out.push(string.byte_at(alpha, (b3 % 4) * 8));
    pad = 1;
  }
  var k = 0;
  while k < pad {
    out.push(61u8);
    k = k + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Base32 -> bytes
// --------------------------------------------------

/// Decode RFC 4648 base32 text (standard alphabet) to bytes.
/// Params: s - the base32 text. Alphabet characters are A-Z and 2-7;
/// lowercase a-z is accepted as the same digits (case-insensitive decoding);
/// '=' is the pad character; no other byte, including whitespace, is allowed.
/// Returns: Ok(bytes). Canonical padding is required: a final partial group
/// of 2/4/5/7 data characters must be followed by exactly 6/4/3/1 '='
/// characters, and whole 8-character groups carry none. Empty input yields
/// Ok(empty).
/// Error case: Err("base32: invalid character") for any byte outside
/// A-Z/a-z/2-7/'=' (also for such a byte after the first '=');
/// Err("base32: invalid padding position") when an alphabet character
/// follows the first '='; Err("base32: bad padding count") when the '=' run
/// is not the exact count required by the final group, or follows whole
/// groups, or the total length is not a multiple of 8;
/// Err("base32: truncated group") when there is no '=' and the unpadded data
/// length is not a multiple of 8; Err("base32: non-canonical trailing bits")
/// when the unused low bits of the final group are not all zero.
/// Complexity: O(s.len()).
pub fn base32_decode(s: Str) -> Result[Vec[UInt8], Str] {
  let n = s.len();
  if n == 0 {
    return _ok_bytes(Vec[UInt8].new());
  }
  var d = n;
  var p = 0;
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 61 {
      d = i;
      p = n - i;
      break;
    }
    if _b32_value(b) < 0 {
      return _err_bytes("base32: invalid character");
    }
    i = i + 1;
  }
  if p > 0 {
    var j = d;
    while j < n {
      let b = (string.byte_at(s, j) as Int) & 0xFF;
      if b == 61 {
        j = j + 1;
      } elif _b32_value(b) >= 0 {
        return _err_bytes("base32: invalid padding position");
      } else {
        return _err_bytes("base32: invalid character");
      }
    }
  }
  let rem = d % 8;
  if p == 0 {
    if rem != 0 {
      return _err_bytes("base32: truncated group");
    }
  } else {
    var want = -1;
    if rem == 2 {
      want = 6;
    } elif rem == 4 {
      want = 4;
    } elif rem == 5 {
      want = 3;
    } elif rem == 7 {
      want = 1;
    }
    if p != want || n % 8 != 0 {
      return _err_bytes("base32: bad padding count");
    }
  }
  var out = Vec[UInt8].new();
  var acc = 0;
  var bitc = 0;
  var k = 0;
  while k < d {
    let b = (string.byte_at(s, k) as Int) & 0xFF;
    let v = _b32_value(b);
    acc = acc * 32 + v;
    bitc = bitc + 5;
    if bitc >= 8 {
      bitc = bitc - 8;
      let pw = _pow2(bitc);
      out.push(((acc / pw) % 256) as UInt8);
      acc = acc % pw;
    }
    k = k + 1;
  }
  if acc != 0 {
    return _err_bytes("base32: non-canonical trailing bits");
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Validation
// --------------------------------------------------

/// True when `s` is valid canonical RFC 4648 base32 text.
/// Params: s - the candidate text.
/// Returns: true when base32_decode(s) returns Ok (including empty input),
/// false otherwise. Acceptance is exactly the decoder's: padding is
/// required for partial groups, lowercase is accepted, and non-canonical
/// trailing bits are rejected.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn base32_is_valid(s: Str) -> Bool {
  let r = base32_decode(s);
  if r.is_ok {
    return true;
  }
  return false;
}
