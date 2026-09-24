// XIOM -- xiom.varint: LEB128 unsigned varints and zigzag signed varints
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) unsigned LEB128 and zigzag varint helpers for
// in-memory Vec[UInt8] buffers. See SPEC.md for the byte-level rules, the
// zigzag mapping, the canonicality contract, the error catalog and the
// documented limitations.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the two tiny leaf helpers below
//     (_ok_pair/_err_pair); constructing Results directly inside other
//     functions miscompiles.
//   * every raw byte widens through `(x as Int) & 0xFF` before it is used.
//   * no `<<` shift is used: decode accumulates groups with a `place`
//     factor (multiply by 128), and encode uses modulo/division only.
//   * the zigzag encoder folds the +1 into a base-128 digit carry, so
//     INT64_MIN never needs `-n` (which would overflow).
//   * the zigzag decoder rebuilds floor(z / 2) from the raw 7-bit groups,
//     so it never divides a negative Int bit pattern by two.

module xiom.varint

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[(Int, Int), Str].
fn _ok_pair(v: (Int, Int)) -> Result[(Int, Int), Str] {
  return Ok(v);
}

// Err(m) for Result[(Int, Int), Str].
fn _err_pair(m: Str) -> Result[(Int, Int), Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helper
// --------------------------------------------------

// Byte `off` widened to 0..255. The caller must guarantee 0 <= off < len.
fn _byte(data: &Vec[UInt8], off: Int) -> Int {
  return (data[off] as Int) & 0xFF;
}

// --------------------------------------------------
//  Encoders and size helper
// --------------------------------------------------

/// Encode `n` as an unsigned LEB128 varint: 7 payload bits per byte, least
/// significant group first, bit 7 is the continuation flag. Only
/// non-negative values are encodable; `n < 0` yields an empty Vec[UInt8]
/// (caller error; the API cannot return Err). 0 encodes as the single byte
/// 0x00 and 2^63-1 as nine bytes.
pub fn varint_encode_u(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if n < 0 {
    return out;
  }
  var v = n;
  var more = true;
  while more {
    let d = v % 128;
    v = v / 128;
    if v > 0 {
      out.push((d + 128) as UInt8);
    } else {
      out.push(d as UInt8);
      more = false;
    }
  }
  return out;
}

/// Encoded byte count of the unsigned LEB128 varint for `n`, so that
/// `varint_size_u(n) == varint_encode_u(n).len()` for every encodable `n`.
/// `n < 0` yields 0 (there is no encoding).
pub fn varint_size_u(n: Int) -> Int {
  if n < 0 {
    return 0;
  }
  var v = n;
  var count = 1;
  while v >= 128 {
    v = v / 128;
    count = count + 1;
  }
  return count;
}

/// Encode `n` as a zigzag varint: zigzag maps signed values to the unsigned
/// domain (`0, -1, 1, -2, 2, ...` -> `0, 1, 2, 3, 4, ...`) and the result is
/// LEB128-encoded. The mapping is computed arithmetically: for `n >= 0`
/// `z = 2n`, for `n < 0` `z = 2*(|n|-1) + 1`, with the +1 folded into a
/// base-128 digit carry so INT64_MIN never overflows. INT64_MIN and
/// INT64_MAX each encode as 10 bytes.
pub fn varint_encode_zigzag(n: Int) -> Vec[UInt8] {
  var k = n;
  var carry: Int = 0;
  if n < 0 {
    k = (0 - n) - 1;
    carry = 1;
  }
  var digits = Vec[Int].new();
  digits.push(k % 128);
  var t = k / 128;
  while t > 0 {
    digits.push(t % 128);
    t = t / 128;
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < digits.len() {
    let d: Int = digits[i];
    var g = 2 * d + carry;
    carry = g / 128;
    g = g % 128;
    let last = i + 1 >= digits.len();
    if !last {
      out.push((g + 128) as UInt8);
    } elif carry > 0 {
      out.push((g + 128) as UInt8);
      out.push(carry as UInt8);
    } else {
      out.push(g as UInt8);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Decoders
// --------------------------------------------------

/// Decode an unsigned LEB128 varint at `off`. Returns Ok((value, next))
/// where `next` is the offset just past the last consumed byte. At most 10
/// bytes are consumed; a value with bit 63 set is returned as the same
/// two's-complement bit pattern interpreted as a signed Int (the platform
/// Int is signed 64-bit; documented in SPEC.md). Non-minimal encodings are
/// accepted; use varint_is_canonical_u to reject them.
///
/// Err("varint: negative offset") for `off < 0`;
/// Err("varint: truncated") when the buffer ends before the varint does;
/// Err("varint: overflow") when the encoding would need more than 10 bytes
/// or carries payload bits above bit 63.
pub fn varint_decode_u(data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str] {
  if off < 0 {
    return _err_pair("varint: negative offset");
  }
  let total = data.len();
  var result: Int = 0;
  var place: Int = 1;
  var pos = off;
  var i = 0;
  while i < 10 {
    if pos >= total {
      return _err_pair("varint: truncated");
    }
    let b = _byte(data, pos);
    if i == 9 {
      // The 10th group may only carry bit 63 (payload 0 or 1) and must
      // terminate the sequence; anything else exceeds the 64-bit domain.
      if (b & 0xFE) != 0 {
        return _err_pair("varint: overflow");
      }
      if b == 1 {
        result = result + (0 - 9223372036854775807 - 1);
      }
      pos = pos + 1;
      return _ok_pair((result, pos));
    }
    let d = b & 0x7F;
    result = result + d * place;
    if i < 8 {
      place = place * 128;
    }
    pos = pos + 1;
    if (b & 0x80) == 0 {
      return _ok_pair((result, pos));
    }
    i = i + 1;
  }
  return _err_pair("varint: overflow");
}

/// Decode a zigzag varint at `off`. The unsigned value is decoded exactly
/// like varint_decode_u and then un-mapped into the signed domain: an even
/// `z` decodes to `z / 2`, an odd `z` to `-(z / 2) - 1` (computed from the
/// raw 7-bit groups, so INT64_MIN decodes correctly from `ff*9 01`).
/// Errors are the varint_decode_u errors.
pub fn varint_decode_zigzag(data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str] {
  let ur = varint_decode_u(data, off);
  if !ur.is_ok {
    return _err_pair(ur.error);
  }
  let pair = ur.value;
  let next: Int = pair.1;
  var groups = Vec[Int].new();
  var pos = off;
  while pos < next {
    let b = _byte(data, pos);
    groups.push(b & 0x7F);
    pos = pos + 1;
  }
  // floor(z / 2) from the groups: group i contributes floor(g_i / 2) plus
  // 64 when group i+1 is odd, at place 128^i. The top group of a 10-byte
  // encoding (payload 0 or 1) contributes 0.
  var acc: Int = 0;
  var place: Int = 1;
  var i = 0;
  while i < groups.len() {
    let g: Int = groups[i];
    var c = g / 2;
    if i + 1 < groups.len() {
      let gn: Int = groups[i + 1];
      if gn % 2 == 1 {
        c = c + 64;
      }
    }
    acc = acc + c * place;
    if i < 8 {
      place = place * 128;
    }
    i = i + 1;
  }
  let sign: Int = groups[0] % 2;
  if sign == 1 {
    return _ok_pair((0 - acc - 1, next));
  }
  return _ok_pair((acc, next));
}

/// True when the unsigned LEB128 encoding at `off` is canonical (minimal):
/// decoding succeeds and the consumed byte count equals the canonical byte
/// count for the decoded bit pattern (varint_size_u(value) for bit 63 clear,
/// 10 bytes for bit 63 set). Overlong forms such as 0x80 0x00 are rejected.
pub fn varint_is_canonical_u(data: &Vec[UInt8], off: Int) -> Bool {
  let r = varint_decode_u(data, off);
  if !r.is_ok {
    return false;
  }
  let pair = r.value;
  let value: Int = pair.0;
  let next: Int = pair.1;
  let consumed: Int = next - off;
  if value < 0 {
    return consumed == 10;
  }
  return consumed == varint_size_u(value);
}
