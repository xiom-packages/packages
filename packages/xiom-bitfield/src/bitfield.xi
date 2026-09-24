// XIOM -- xiom.bitfield: bit manipulation helpers for 64-bit Ints
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Sign model: values are treated as 64-bit two's-complement bit patterns
// stored in the signed platform `Int`. Bit 63 is the sign bit, so helpers
// that return a full 64-bit pattern (bit_get with offset+width == 64,
// bit_reverse with width 64, bit_rotate_* with width 64) can return a
// negative Int; all other helpers return a non-negative Int. INT64_MIN is
// always constructed as `0 - 9223372036854775807 - 1`, never as -2^63.
//
// v0.61.3 notes that shaped this module:
//   * no `&`, `|`, `^` or shift operators are used. The compiler
//     miscompiles bitwise AND on operands with bit 31 set (documented in
//     xiom.convert.base58 and xiom.bits.bitwise), so every extraction is
//     arithmetic: divide-by-two with an exact non-negative remainder, and
//     masks are built by doubling-and-adding so 2^63-1 never overflows.
//   * all functions are free functions; no methods, no lambdas, no structs.
//
// See SPEC.md for the bit model, masking rules and the full test plan.

module xiom.bitfield

// --------------------------------------------------
//  Internal arithmetic primitives
// --------------------------------------------------

// INT64_MIN as a two's-complement bit pattern; never computed as -2^63.
fn _i64_min() -> Int {
  return 0 - 9223372036854775807 - 1;
}

// 2^k for 0 <= k <= 63, built by doubling: `k >= 63` yields the INT64_MIN
// pattern directly because 2^63 is not representable as a positive Int.
fn _pow2(k: Int) -> Int {
  if k <= 0 {
    return 1;
  }
  if k >= 63 {
    return _i64_min();
  }
  var p: Int = 1;
  var i: Int = 0;
  while i < k {
    p = p * 2;
    i = i + 1;
  }
  return p;
}

// floor(x / 2) for the full signed range: the remainder is forced into
// {0, 1} before the subtraction, so this is exact under either truncating
// or flooring `%`/`/` semantics.
fn _floor_div2(x: Int) -> Int {
  var r = x % 2;
  if r < 0 {
    r = r + 2;
  }
  return (x - r) / 2;
}

// Bit k (0-based from the LSB) of the 64-bit two's-complement pattern of
// `value`, as 0 or 1. k must satisfy 0 <= k < 64; division is used instead
// of `>>` so the extraction stays exact for negative values.
fn _bit_at(value: Int, k: Int) -> Int {
  var x = value;
  var i = 0;
  while i < k {
    x = _floor_div2(x);
    i = i + 1;
  }
  var b = x % 2;
  if b < 0 {
    b = b + 2;
  }
  return b;
}

// Byte k (0 = least significant) of the 64-bit two's-complement pattern of
// `value`, widened to 0..255. k must satisfy 0 <= k < 8.
fn _byte(value: Int, k: Int) -> Int {
  var q = value;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 {
      r = r + 256;
    }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 {
    b = b + 256;
  }
  return b;
}

// True when (offset, width) selects a well-formed field inside the 64-bit
// word: 1 <= width <= 64, 0 <= offset < 64 and offset + width <= 64.
fn _field_ok(offset: Int, width: Int) -> Bool {
  if width <= 0 {
    return false;
  }
  if width > 64 {
    return false;
  }
  if offset < 0 {
    return false;
  }
  if offset >= 64 {
    return false;
  }
  if offset + width > 64 {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Masks and fields
// --------------------------------------------------

/// Mask with the low `width` bits set. `width <= 0` yields 0; `width >= 64`
/// yields -1 (all 64 bits). Complexity: O(width).
pub fn bit_mask(width: Int) -> Int {
  if width <= 0 {
    return 0;
  }
  if width >= 64 {
    return -1;
  }
  var m: Int = 1;
  var i: Int = 1;
  while i < width {
    m = m * 2 + 1;
    i = i + 1;
  }
  return m;
}

/// Extract `width` bits at `offset` (0-based from the LSB) as an unsigned,
/// right-justified value. Invalid requests (offset < 0, offset >= 64,
/// width <= 0, width > 64, or offset + width > 64) yield 0. The result is
/// non-negative except for the full-width request (offset 0, width 64),
/// which returns the whole two's-complement pattern. Complexity: O(width).
pub fn bit_get(value: Int, offset: Int, width: Int) -> Int {
  if !_field_ok(offset, width) {
    return 0;
  }
  var out: Int = 0;
  var k = 0;
  while k < width {
    if _bit_at(value, offset + k) == 1 {
      out = out + _pow2(k);
    }
    k = k + 1;
  }
  return out;
}

/// Replace the `width` bits at `offset` with `field` (masked to `width`),
/// leaving all other bits unchanged. An invalid field (same rules as
/// bit_get) leaves `value` unchanged. Complexity: O(width).
pub fn bit_set(value: Int, offset: Int, width: Int, field: Int) -> Int {
  if !_field_ok(offset, width) {
    return value;
  }
  var v = value;
  var k = 0;
  while k < width {
    let want = _bit_at(field, k);
    let cur = _bit_at(v, offset + k);
    if want == 1 && cur == 0 {
      v = v + _pow2(offset + k);
    } elif want == 0 && cur == 1 {
      v = v - _pow2(offset + k);
    }
    k = k + 1;
  }
  return v;
}

/// Zero the `width` bits at `offset`, leaving all other bits unchanged. An
/// invalid field (same rules as bit_get) leaves `value` unchanged.
/// Complexity: O(width).
pub fn bit_clear(value: Int, offset: Int, width: Int) -> Int {
  if !_field_ok(offset, width) {
    return value;
  }
  var v = value;
  var k = 0;
  while k < width {
    if _bit_at(v, offset + k) == 1 {
      v = v - _pow2(offset + k);
    }
    k = k + 1;
  }
  return v;
}

/// Flip the single bit at `offset`. An offset outside 0..63 leaves `value`
/// unchanged. Complexity: O(offset).
pub fn bit_toggle(value: Int, offset: Int) -> Int {
  if offset < 0 || offset >= 64 {
    return value;
  }
  if _bit_at(value, offset) == 1 {
    return value - _pow2(offset);
  }
  return value + _pow2(offset);
}

// --------------------------------------------------
//  Counting
// --------------------------------------------------

/// Population count over the 64-bit two's-complement pattern: 64 for -1 and
/// 1 for INT64_MIN. Complexity: O(64^2) worst case (O(64) single bits).
pub fn bit_count_ones(value: Int) -> Int {
  var count = 0;
  var k = 0;
  while k < 64 {
    if _bit_at(value, k) == 1 {
      count = count + 1;
    }
    k = k + 1;
  }
  return count;
}

/// Number of consecutive zero bits from bit 63 downwards, over the full
/// 64-bit pattern; 64 for 0. Negative values have bit 63 set, so they yield
/// 0. Complexity: O(64^2) worst case.
pub fn bit_leading_zeros(value: Int) -> Int {
  if value == 0 {
    return 64;
  }
  var hi = 63;
  while hi >= 0 {
    if _bit_at(value, hi) == 1 {
      return 63 - hi;
    }
    hi = hi - 1;
  }
  return 64;
}

/// Number of consecutive zero bits from bit 0 upwards; 64 for 0.
/// Complexity: O(64^2) worst case.
pub fn bit_trailing_zeros(value: Int) -> Int {
  if value == 0 {
    return 64;
  }
  var lo = 0;
  while lo < 64 {
    if _bit_at(value, lo) == 1 {
      return lo;
    }
    lo = lo + 1;
  }
  return 64;
}

// --------------------------------------------------
//  Reversal, byte swap, rotation
// --------------------------------------------------

/// Reverse the low `width` bits (width 1..64; any other width yields 0) and
/// clear the remaining high bits. The result is non-negative for
/// width <= 63; width 64 returns the reversed full two's-complement pattern
/// (e.g. bit_reverse(1, 64) == INT64_MIN). Complexity: O(width^2).
pub fn bit_reverse(value: Int, width: Int) -> Int {
  if width <= 0 || width > 64 {
    return 0;
  }
  var out: Int = 0;
  var k = 0;
  while k < width {
    if _bit_at(value, k) == 1 {
      out = out + _pow2(width - 1 - k);
    }
    k = k + 1;
  }
  return out;
}

/// Swap the low two bytes, widened to 0..65535. Complexity: O(1).
pub fn bit_byte_swap16(value: Int) -> Int {
  let b0 = _byte(value, 0);
  let b1 = _byte(value, 1);
  return b1 + b0 * 256;
}

/// Swap the low four bytes, widened to 0..2^32-1. Complexity: O(1).
pub fn bit_byte_swap32(value: Int) -> Int {
  let b0 = _byte(value, 0);
  let b1 = _byte(value, 1);
  let b2 = _byte(value, 2);
  let b3 = _byte(value, 3);
  return b3 + b2 * 256 + b1 * 65536 + b0 * 16777216;
}

/// Rotate the low `width` bits left by `n mod width` (width 1..64; any
/// other width yields 0), clearing the high bits outside the field. For
/// width 64 the full two's-complement pattern is rotated, so the result can
/// be negative. Complexity: O(width^2).
pub fn bit_rotate_left(value: Int, width: Int, n: Int) -> Int {
  if width <= 0 || width > 64 {
    return 0;
  }
  var shift = n % width;
  if shift < 0 {
    shift = shift + width;
  }
  var out: Int = 0;
  var k = 0;
  while k < width {
    if _bit_at(value, k) == 1 {
      var dest = k + shift;
      if dest >= width {
        dest = dest - width;
      }
      out = out + _pow2(dest);
    }
    k = k + 1;
  }
  return out;
}

/// Rotate the low `width` bits right by `n mod width` (width 1..64; any
/// other width yields 0), clearing the high bits outside the field. For
/// width 64 the full two's-complement pattern is rotated, so the result can
/// be negative. Complexity: O(width^2).
pub fn bit_rotate_right(value: Int, width: Int, n: Int) -> Int {
  if width <= 0 || width > 64 {
    return 0;
  }
  var shift = n % width;
  if shift < 0 {
    shift = shift + width;
  }
  var out: Int = 0;
  var k = 0;
  while k < width {
    if _bit_at(value, k) == 1 {
      var dest = k - shift;
      if dest < 0 {
        dest = dest + width;
      }
      out = out + _pow2(dest);
    }
    k = k + 1;
  }
  return out;
}
