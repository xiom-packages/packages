// XIOM -- xiom.fnv: FNV-1 and FNV-1a non-cryptographic hashes (32/64-bit)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM implementation of the Fowler/Noll/Vo hash family as published
// at https://www.isthe.com/chongo/tech/comp/fnv/ (CC0 public domain):
//
//   fnv1_32    fnv1a_32    fnv1_64    fnv1a_64
//
// each available as a one-shot byte-input function and as an incremental
// init/update/finalize triple over an explicit state Int, plus the
// specification constants and fnv_hex32/fnv_hex64 for unsigned display.
//
// Numeric model (no FFI, no BigInt, Int only):
//   * A 32-bit state is always a non-negative Int in [0, 2^32); the
//     one-shot functions and every update step return values in that
//     range.
//   * A 64-bit state is the 64-bit unsigned value interpreted as a
//     signed two's-complement Int: values >= 2^63 are negative. The
//     64-bit offset basis 0xCBF29CE484222325 is therefore the Int
//     -3750763034362895579, and fnv_hex64 renders the pattern unsigned.
//   * The 32-bit multiply wraps with `% 2^32` and is exact in Int because
//     (2^32 - 1) * 16777619 < 2^63.
//   * The 64-bit multiply wraps mod 2^64 with the limb split in _mul64:
//     the state is decomposed into four 16-bit limbs, the prime
//     1099511628211 = 256 * 2^32 + 435 is distributed over them, and the
//     carries are propagated column by column. Every intermediate stays
//     below 2^27 (before the final assembly, which stays in Int64 range
//     by construction), so the result is exact for every Int state; no
//     compiler wrapping semantics are relied upon. Full proof sketch in
//     SPEC.md.
//   * The per-byte XOR touches only the low octet and is computed
//     arithmetically in _xor_low_byte: `^` is applied to values below 256
//     only. No `&`, `<<` or `>>` is ever applied to a value that can have
//     bit 31 (or 63) set, which keeps this module clear of the v0.61.3
//     high-bit bitwise codegen bugs.
//
// The module has no state, no struct types, no Result/Option and no FFI:
// every public function is total and returns a value directly. There are
// no error paths, so there is no error catalog (SPEC.md records this).

module xiom.fnv

use xiom.string;

// --------------------------------------------------
//  FNV specification constants
// --------------------------------------------------

/// The 32-bit FNV offset basis: 2166136261 (0x811C9DC5). Complexity: O(1).
pub fn fnv_offset_basis32() -> Int {
  return 2166136261;
}

/// The 32-bit FNV prime: 16777619 = 2^24 + 2^8 + 0x93. Complexity: O(1).
pub fn fnv_prime32() -> Int {
  return 16777619;
}

/// The 64-bit FNV offset basis as a signed Int: the unsigned
/// specification value 14695981039346656037 (0xCBF29CE484222325) minus
/// 2^64. Complexity: O(1).
pub fn fnv_offset_basis64() -> Int {
  return 0 - 3750763034362895579;
}

/// The 64-bit FNV prime: 1099511628211 = 2^40 + 2^8 + 0xB3.
/// Complexity: O(1).
pub fn fnv_prime64() -> Int {
  return 1099511628211;
}

// --------------------------------------------------
//  Internal arithmetic
// --------------------------------------------------

// Limb `k` (0 = least significant, in [0, 65535]) of the 64-bit
// two's-complement pattern of `state`. Division/modulo only, exact for
// negative states; every intermediate is a non-negative residue.
fn _limb64(state: Int, k: Int) -> Int {
  var q = state;
  var i = 0;
  while i < k {
    var r = q % 65536;
    if r < 0 {
      r = r + 65536;
    }
    q = (q - r) / 65536;
    i = i + 1;
  }
  var r = q % 65536;
  if r < 0 {
    r = r + 65536;
  }
  return r;
}

// Replace the low octet of `state` with (low octet XOR b) for b in
// [0, 255]; every other bit of `state` is preserved. The `^` operates on
// the two low bytes only, so no high bit ever reaches a bitwise operator.
fn _xor_low_byte(state: Int, b: Int) -> Int {
  var low = state % 256;
  if low < 0 {
    low = low + 256;
  }
  return state - low + (low ^ b);
}

// state * 16777619 mod 2^32 as a non-negative Int. The incoming state is
// reduced modulo 2^32 first, so the result is in [0, 2^32) for every Int
// state. Exact: (2^32 - 1) * 16777619 < 2^63.
fn _mul32(state: Int) -> Int {
  var v = state % 4294967296;
  if v < 0 {
    v = v + 4294967296;
  }
  return (v * 16777619) % 4294967296;
}

// state * 1099511628211 mod 2^64, returned as the signed two's-complement
// Int. Split multiply with 16-bit limbs:
//
//   state = x3*2^48 + x2*2^32 + x1*2^16 + x0,   prime = 256*2^32 + 435
//
// Products by 2^16 column (columns 4 and above vanish mod 2^64):
//
//   col 0: x0*435
//   col 1: x1*435
//   col 2: x2*435 + x0*256
//   col 3: x3*435 + x1*256
//
// Each column sum is at most 2*65535*435 + carry < 2^26, so the running
// carries are exact and no intermediate overflows. The final assembly
// maps the top limb into the signed range: r3 >= 2^15 means the unsigned
// result is >= 2^63, so the top 16 bits are taken as r3 - 2^16. Every
// intermediate and the result stay within Int64 bounds.
fn _mul64(state: Int) -> Int {
  let x0 = _limb64(state, 0);
  let x1 = _limb64(state, 1);
  let x2 = _limb64(state, 2);
  let x3 = _limb64(state, 3);
  let t0 = x0 * 435;
  let r0 = t0 % 65536;
  let c0 = t0 / 65536;
  let t1 = x1 * 435 + c0;
  let r1 = t1 % 65536;
  let c1 = t1 / 65536;
  let t2 = x2 * 435 + x0 * 256 + c1;
  let r2 = t2 % 65536;
  let c2 = t2 / 65536;
  let t3 = x3 * 435 + x1 * 256 + c2;
  let r3 = t3 % 65536;
  var top = r3;
  if r3 >= 32768 {
    top = r3 - 65536;
  }
  return top * 281474976710656 + r2 * 4294967296 + r1 * 65536 + r0;
}

// --------------------------------------------------
//  Internal byte loops (shared by one-shot and incremental)
// --------------------------------------------------

// FNV-1 32-bit core: multiply, then XOR the octet, per byte.
fn _fnv1_32_bytes(state: Int, data: &Vec[UInt8]) -> Int {
  var h = state;
  var i = 0;
  while i < data.len() {
    h = _mul32(h);
    h = _xor_low_byte(h, (data[i] as Int) & 255);
    i = i + 1;
  }
  return h;
}

// FNV-1a 32-bit core: XOR the octet, then multiply, per byte.
fn _fnv1a_32_bytes(state: Int, data: &Vec[UInt8]) -> Int {
  var h = state;
  var i = 0;
  while i < data.len() {
    h = _xor_low_byte(h, (data[i] as Int) & 255);
    h = _mul32(h);
    i = i + 1;
  }
  return h;
}

// FNV-1 64-bit core: multiply, then XOR the octet, per byte.
fn _fnv1_64_bytes(state: Int, data: &Vec[UInt8]) -> Int {
  var h = state;
  var i = 0;
  while i < data.len() {
    h = _mul64(h);
    h = _xor_low_byte(h, (data[i] as Int) & 255);
    i = i + 1;
  }
  return h;
}

// FNV-1a 64-bit core: XOR the octet, then multiply, per byte.
fn _fnv1a_64_bytes(state: Int, data: &Vec[UInt8]) -> Int {
  var h = state;
  var i = 0;
  while i < data.len() {
    h = _xor_low_byte(h, (data[i] as Int) & 255);
    h = _mul64(h);
    i = i + 1;
  }
  return h;
}

// --------------------------------------------------
//  One-shot functions
// --------------------------------------------------

/// FNV-1 32-bit over `data`. Starts from the 32-bit offset basis, applies
/// multiply-then-XOR per byte and wraps modulo 2^32; the result is a
/// non-negative Int in [0, 2^32 - 1]. The empty input yields the offset
/// basis 2166136261 (0x811C9DC5). Complexity: O(data.len()).
pub fn fnv1_32(data: &Vec[UInt8]) -> Int {
  return _fnv1_32_bytes(fnv_offset_basis32(), data);
}

/// FNV-1a 32-bit over `data`. Same parameters and range as fnv1_32, with
/// XOR-before-multiply per byte. The empty input yields the offset basis
/// 2166136261 (0x811C9DC5). Complexity: O(data.len()).
pub fn fnv1a_32(data: &Vec[UInt8]) -> Int {
  return _fnv1a_32_bytes(fnv_offset_basis32(), data);
}

/// FNV-1 64-bit over `data`, returned as the signed two's-complement Int
/// of the unsigned 64-bit result (use fnv_hex64 for unsigned display).
/// The empty input yields fnv_offset_basis64(). Complexity: O(data.len()).
pub fn fnv1_64(data: &Vec[UInt8]) -> Int {
  return _fnv1_64_bytes(fnv_offset_basis64(), data);
}

/// FNV-1a 64-bit over `data`, returned as the signed two's-complement Int
/// of the unsigned 64-bit result (use fnv_hex64 for unsigned display).
/// The empty input yields fnv_offset_basis64(). Complexity: O(data.len()).
pub fn fnv1a_64(data: &Vec[UInt8]) -> Int {
  return _fnv1a_64_bytes(fnv_offset_basis64(), data);
}

// --------------------------------------------------
//  Incremental API (init / update / finalize)
// --------------------------------------------------

/// FNV-1 32-bit initial state: the 32-bit offset basis.
/// Complexity: O(1).
pub fn fnv1_32_init() -> Int {
  return fnv_offset_basis32();
}

/// Continue an FNV-1 32-bit hash with `data`, returning the new state.
/// Equivalent to hashing state || data in one shot; the state must come
/// from fnv1_32_init or a previous fnv1_32_update (any Int is accepted and
/// reduced modulo 2^32 by the multiply). Complexity: O(data.len()).
pub fn fnv1_32_update(state: Int, data: &Vec[UInt8]) -> Int {
  return _fnv1_32_bytes(state, data);
}

/// Finish an FNV-1 32-bit hash. FNV applies no output transformation, so
/// finalize is the identity on a well-formed state; it exists so the
/// incremental API mirrors the classic init/update/finalize shape.
/// Complexity: O(1).
pub fn fnv1_32_finalize(state: Int) -> Int {
  return state;
}

/// FNV-1a 32-bit initial state: the 32-bit offset basis.
/// Complexity: O(1).
pub fn fnv1a_32_init() -> Int {
  return fnv_offset_basis32();
}

/// Continue an FNV-1a 32-bit hash with `data`, returning the new state.
/// Equivalent to hashing state || data in one shot. Complexity:
/// O(data.len()).
pub fn fnv1a_32_update(state: Int, data: &Vec[UInt8]) -> Int {
  return _fnv1a_32_bytes(state, data);
}

/// Finish an FNV-1a 32-bit hash; the identity, as for fnv1_32_finalize.
/// Complexity: O(1).
pub fn fnv1a_32_finalize(state: Int) -> Int {
  return state;
}

/// FNV-1 64-bit initial state: fnv_offset_basis64() (the unsigned
/// 0xCBF29CE484222325 as a signed Int). Complexity: O(1).
pub fn fnv1_64_init() -> Int {
  return fnv_offset_basis64();
}

/// Continue an FNV-1 64-bit hash with `data`, returning the new signed
/// state. Equivalent to hashing state || data in one shot.
/// Complexity: O(data.len()).
pub fn fnv1_64_update(state: Int, data: &Vec[UInt8]) -> Int {
  return _fnv1_64_bytes(state, data);
}

/// Finish an FNV-1 64-bit hash; the identity, as for fnv1_32_finalize.
/// Complexity: O(1).
pub fn fnv1_64_finalize(state: Int) -> Int {
  return state;
}

/// FNV-1a 64-bit initial state: fnv_offset_basis64(). Complexity: O(1).
pub fn fnv1a_64_init() -> Int {
  return fnv_offset_basis64();
}

/// Continue an FNV-1a 64-bit hash with `data`, returning the new signed
/// state. Equivalent to hashing state || data in one shot.
/// Complexity: O(data.len()).
pub fn fnv1a_64_update(state: Int, data: &Vec[UInt8]) -> Int {
  return _fnv1a_64_bytes(state, data);
}

/// Finish an FNV-1a 64-bit hash; the identity, as for fnv1_32_finalize.
/// Complexity: O(1).
pub fn fnv1a_64_finalize(state: Int) -> Int {
  return state;
}

// --------------------------------------------------
//  Unsigned hex display
// --------------------------------------------------

// One lowercase hex digit for 0 <= n <= 15.
fn _hex_digit(n: Int) -> Str {
  let digits = "0123456789abcdef";
  return string.str_slice(digits, n, n + 1);
}

/// Lowercase hexadecimal, exactly 8 digits, of the low 32 bits of
/// `value` interpreted as an unsigned 32-bit number. Any Int is accepted:
/// the value is reduced modulo 2^32 first (so -1 renders as
/// "ffffffff"). Complexity: O(1).
pub fn fnv_hex32(value: Int) -> Str {
  var v = value % 4294967296;
  if v < 0 {
    v = v + 4294967296;
  }
  var out = "";
  var i = 0;
  while i < 8 {
    out = _hex_digit(v % 16) + out;
    v = v / 16;
    i = i + 1;
  }
  return out;
}

/// Lowercase hexadecimal, exactly 16 digits, of the 64-bit
/// two's-complement pattern of `value` (the form the 64-bit hashes
/// return), i.e. the unsigned 64-bit value. Any Int is accepted
/// (so -1 renders as "ffffffffffffffff"). Complexity: O(1).
pub fn fnv_hex64(value: Int) -> Str {
  var v = value;
  var out = "";
  var i = 0;
  while i < 16 {
    var nib = v % 16;
    if nib < 0 {
      nib = nib + 16;
    }
    out = _hex_digit(nib) + out;
    v = (v - nib) / 16;
    i = i + 1;
  }
  return out;
}
