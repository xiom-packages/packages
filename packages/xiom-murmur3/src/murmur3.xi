// XIOM -- xiom.murmur3: MurmurHash3 x86_32, a non-cryptographic hash
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI), Int-only implementation of the MurmurHash3 x86_32
// variant by Austin Appleby, following the canonical smhasher reference
// implementation (https://github.com/aappleby/smhasher; the algorithm is
// public domain, the smhasher code is MIT). The full specification, the
// numeric proofs and the test-vector tables live in SPEC.md; the headline
// surface is:
//
//   * one-shot:        murmur3_x86_32(data, seed)
//   * streaming:       murmur3_x86_32_init / _update / _finalize over an
//                      explicit Murmur3State{h1, length, tail}
//   * display:         murmur3_x86_32_hex(value) -> 8 lowercase hex digits
//   * constants:       _c1/_c2, _fmix_c1/_fmix_c2, _default_seed,
//                      _smhasher_seed, _smhasher_value
//   * rotation helper: murmur3_x86_32_rotl32(x, r)
//
// Numeric model (no BigInt, no wrapping `*`, no bitwise operator on large
// values -- all three are v0.61.3 hazards):
//   * A 32-bit word is always a non-negative Int in [0, 2^32).
//   * _mul32 is a 16-bit limb split multiply with the classic
//     (a1*2^16 + a0) * (b1*2^16 + b0) columns reduced modulo 2^32. Every
//     intermediate stays below 2^33, so the wrapped product is exact in Int
//     with no reliance on compiler overflow semantics.
//   * Rotations are arithmetic only:
//       rotl32(x, r) = (x * 2^r mod 2^32) + floor(x / 2^(32-r))
//     The two terms are the low and high halves of the rotated word: their
//     set bits are disjoint by construction, so the sum is in [0, 2^32).
//     No `<<` or `>>` appears anywhere in this module.
//   * Logical right shifts are floor divisions by powers of two.
//   * XOR is applied to 16-bit halves and recombined arithmetically, so no
//     bitwise operator ever sees a value with bit 31 set.
//   * Every byte read from a Vec[UInt8] is widened with `(b as Int) & 255`;
//     byte constants are written the same way.
//
// Only the x86_32 variant is implemented. x86_128 and x64_128 are explicit
// non-goals (SPEC.md): they need 128-bit output words and, for x64_128, a
// 64-bit block word. MurmurHash3 is not a cryptographic hash and this
// package makes no collision or authentication claim.

module xiom.murmur3

use xiom.string;

// --------------------------------------------------
//  Specification constants
// --------------------------------------------------

/// Body multiplier c1: 0xCC9E2D51 (3432918353). Complexity: O(1).
pub fn murmur3_x86_32_c1() -> Int {
  return 3432918353;
}

/// Body multiplier c2: 0x1B873593 (461845907). Complexity: O(1).
pub fn murmur3_x86_32_c2() -> Int {
  return 461845907;
}

/// First finalization (fmix32) multiplier: 0x85EBCA6B (2246822507).
/// Complexity: O(1).
pub fn murmur3_x86_32_fmix_c1() -> Int {
  return 2246822507;
}

/// Second finalization (fmix32) multiplier: 0xC2B2AE35 (3266489909).
/// Complexity: O(1).
pub fn murmur3_x86_32_fmix_c2() -> Int {
  return 3266489909;
}

/// The canonical default seed: 0. Complexity: O(1).
pub fn murmur3_x86_32_default_seed() -> Int {
  return 0;
}

/// The seed used by the smhasher VerificationTest harness: 256.
/// Complexity: O(1).
pub fn murmur3_x86_32_smhasher_seed() -> Int {
  return 256;
}

/// The canonical smhasher verification value for this variant: 0xB0F57EE3
/// (2968878819). It is the digest, with seed 0, of the 1024-byte
/// little-endian concatenation of the digests of the 256 prefixes
/// {0}, {0,1}, ... of the byte ramp 0x00..0xFF, each hashed with seed
/// 256 - length (the smhasher VerificationTest protocol). Complexity: O(1).
pub fn murmur3_x86_32_smhasher_value() -> Int {
  return 2968878819;
}

// --------------------------------------------------
//  Result constructors (v0.61.3: Ok/Err only in leaf helpers)
// --------------------------------------------------

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
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

// The single streaming-state error message. The catalog in SPEC.md pins it.
fn _state_error() -> Str {
  return "murmur3: invalid streaming state";
}

// --------------------------------------------------
//  32-bit arithmetic (wrapping multiply, rotation, XOR, shift)
// --------------------------------------------------

// The 32-bit pattern of `v` as a non-negative Int in [0, 2^32). Exact for
// negative inputs under both truncating and flooring `%` semantics (the
// negative residue is shifted into range before the division).
fn _u32(v: Int) -> Int {
  var r = v % 4294967296;
  if r < 0 {
    r = r + 4294967296;
  }
  return r;
}

// 2^k for 0 <= k <= 32, built by multiplication (no shift operators).
fn _pow2(k: Int) -> Int {
  var p = 1;
  var i = 0;
  while i < k {
    p = p * 2;
    i = i + 1;
  }
  return p;
}

// state * b mod 2^32 for state, b in [0, 2^32). Split multiply:
//
//   state = x1*2^16 + x0        b = m1*2^16 + m0
//   t0 = x0*m0                  r0 = t0 mod 2^16, c0 = t0 / 2^16
//   t1 = x1*m0 + x0*m1 + c0     r1 = t1 mod 2^16
//   result = r1*2^16 + r0
//
// Column-1 products are at most 65535*65535 and t1 is below 2^33, so every
// intermediate is exact in Int. Columns at 2^32 and above vanish modulo
// 2^32. Both operands must already be reduced to [0, 2^32).
fn _mul32(state: Int, b: Int) -> Int {
  let x0 = state % 65536;
  let x1 = state / 65536;
  let m0 = b % 65536;
  let m1 = b / 65536;
  let t0 = x0 * m0;
  let r0 = t0 % 65536;
  let c0 = t0 / 65536;
  let t1 = x1 * m0 + x0 * m1 + c0;
  let r1 = t1 % 65536;
  return r1 * 65536 + r0;
}

// a XOR b for a, b in [0, 2^32): each 16-bit half is XORed separately and
// the halves are recombined arithmetically. `^` therefore only ever sees
// values below 65536, so the v0.61.3 high-bit bitwise bugs are unreachable.
fn _xor32(a: Int, b: Int) -> Int {
  let a0 = a % 65536;
  let a1 = a / 65536;
  let b0 = b % 65536;
  let b1 = b / 65536;
  return (a1 ^ b1) * 65536 + (a0 ^ b0);
}

// x >> k (logical) for x in [0, 2^32) and 0 <= k <= 32: floor division by
// 2^k. No shift operator is used.
fn _rshift32(x: Int, k: Int) -> Int {
  return x / _pow2(k);
}

// rotl32(x, r) for x reduced to [0, 2^32) and 0 <= r <= 31, by the
// arithmetic identity in the module header:
//   (x * 2^r mod 2^32) + floor(x / 2^(32-r))
// The first term holds bits 0..31-r of x in positions r..31, the second
// holds bits 32-r..31 in positions 0..r-1; the bit ranges are disjoint, so
// the sum is exactly the rotated word and stays below 2^32. For r = 0 the
// second term is 0 and the first is x. The product x * 2^r is at most
// (2^32 - 1) * 2^31 < 2^63, so it is exact in Int.
fn _rotl32(x: Int, r: Int) -> Int {
  var p = 1;
  var i = 0;
  while i < r {
    p = p * 2;
    i = i + 1;
  }
  var q = 1;
  var j = 0;
  while j < 32 - r {
    q = q * 2;
    j = j + 1;
  }
  return ((x * p) % 4294967296) + (x / q);
}

// --------------------------------------------------
//  MurmurHash3 x86_32 core steps
// --------------------------------------------------

// Mix one little-endian 4-byte block word k1 into the running word h1:
//   k1 *= c1; k1 = rotl32(k1, 15); k1 *= c2; h1 ^= k1;
//   h1 = rotl32(h1, 13); h1 = h1 * 5 + 0xE6546B64;
// h1, k1 must be in [0, 2^32); the result is in [0, 2^32).
fn _mix_block(h1: Int, k1: Int) -> Int {
  var k = _mul32(k1, 3432918353);
  k = _rotl32(k, 15);
  k = _mul32(k, 461845907);
  var h = _xor32(h1, k);
  h = _rotl32(h, 13);
  return (h * 5 + 3864292196) % 4294967296;
}

// Mix the final 1..3 tail bytes packed as k1 into h1 (the tail arm of the
// reference implementation: the same key mixing as _mix_block, without the
// h1 rotation / multiply-add). k1 must be in [0, 2^24].
fn _tail_mix(h1: Int, k1: Int) -> Int {
  var k = _mul32(k1, 3432918353);
  k = _rotl32(k, 15);
  k = _mul32(k, 461845907);
  return _xor32(h1, k);
}

// Pack four non-negative bytes (each <= 255) little-endian:
// b0 + b1*2^8 + b2*2^16 + b3*2^24.
fn _pack4(b0: Int, b1: Int, b2: Int, b3: Int) -> Int {
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Finalization mix fmix32:
//   h ^= h >> 16; h *= 0x85EBCA6B; h ^= h >> 13; h *= 0xC2B2AE35;
//   h ^= h >> 16;
// h must be in [0, 2^32); the result is in [0, 2^32).
fn _fmix32(h: Int) -> Int {
  var x = _xor32(h, _rshift32(h, 16));
  x = _mul32(x, 2246822507);
  x = _xor32(x, _rshift32(x, 13));
  x = _mul32(x, 3266489909);
  return _xor32(x, _rshift32(x, 16));
}

// Little-endian 4-byte block word at `i` of `data`. The caller guarantees
// i + 4 <= data.len(). Bytes are widened with `& 255` (trap: raw UInt8
// comparisons / constants >= 128).
fn _block_at(data: &Vec[UInt8], i: Int) -> Int {
  let b0 = (data[i] as Int) & 255;
  let b1 = (data[i + 1] as Int) & 255;
  let b2 = (data[i + 2] as Int) & 255;
  let b3 = (data[i + 3] as Int) & 255;
  return _pack4(b0, b1, b2, b3);
}

// Body + tail of the one-shot algorithm over the bytes of `data` in
// [i, n): every complete 4-byte block is mixed, then a 1..3 byte tail is
// packed little-endian and mixed. `h1` and the result are in [0, 2^32).
fn _hash_tail(h1: Int, data: &Vec[UInt8], n: Int) -> Int {
  let whole = n - (n % 4);
  var h = h1;
  var i = 0;
  while i < whole {
    h = _mix_block(h, _block_at(data, i));
    i = i + 4;
  }
  let rem = n - whole;
  if rem == 1 {
    h = _tail_mix(h, (data[i] as Int) & 255);
  } elif rem == 2 {
    let b0 = (data[i] as Int) & 255;
    let b1 = (data[i + 1] as Int) & 255;
    h = _tail_mix(h, _pack4(b0, b1, 0, 0));
  } elif rem == 3 {
    let b0 = (data[i] as Int) & 255;
    let b1 = (data[i + 1] as Int) & 255;
    let b2 = (data[i + 2] as Int) & 255;
    h = _tail_mix(h, _pack4(b0, b1, b2, 0));
  }
  return h;
}

// Length fold and fmix32 of the one-shot algorithm: h1 ^= len; fmix32.
fn _finish(h1: Int, length: Int) -> Int {
  return _fmix32(_xor32(h1, length % 4294967296));
}

// --------------------------------------------------
//  One-shot API
// --------------------------------------------------

/// One-shot MurmurHash3 x86_32 over a whole byte buffer.
/// Params: data - the bytes to hash; seed - the 32-bit seed, reduced modulo
///         2^32, so any Int is accepted (-1 means 0xFFFFFFFF).
/// Returns: the 32-bit digest as a non-negative Int in [0, 2^32); the empty
///         buffer with seed 0 yields 0 (fmix32(0) = 0).
/// Error case: none (total).
/// Complexity: O(data.len()) time, O(1) space.
pub fn murmur3_x86_32(data: &Vec[UInt8], seed: Int) -> Int {
  let body = _hash_tail(_u32(seed), data, data.len());
  return _finish(body, data.len());
}

// --------------------------------------------------
//  Streaming API (init / update / finalize)
// --------------------------------------------------

/// Streaming MurmurHash3 x86_32 state.
///
/// Fields: `h1` is the running 32-bit word (non-negative, below 2^32);
/// `length` is the total number of bytes fed so far; `tail` holds the 0..3
/// bytes that have not yet completed a 4-byte block, in stream order. Build
/// the state with murmur3_x86_32_init, advance it with
/// murmur3_x86_32_update and read the digest with
/// murmur3_x86_32_finalize. The fields are readable directly; direct
/// mutation is not required by the API and must preserve the invariants
/// checked by murmur3_x86_32_state_is_valid (h1 in [0, 2^32),
/// length >= 0, 0 <= tail.len() <= 3).
pub type Murmur3State = {
  h1: Int;
  length: Int;
  tail: Vec[UInt8];
}

/// True when a streaming state satisfies the invariants: h1 in [0, 2^32),
/// length >= 0 and 0 <= tail.len() <= 3. A state built by
/// murmur3_x86_32_init and advanced only by murmur3_x86_32_update always
/// satisfies them.
/// Error case: none (total predicate).
/// Complexity: O(1).
pub fn murmur3_x86_32_state_is_valid(state: &Murmur3State) -> Bool {
  if state.h1 < 0 {
    return false;
  }
  if state.h1 >= 4294967296 {
    return false;
  }
  if state.length < 0 {
    return false;
  }
  let t = state.tail;
  if t.len() > 3 {
    return false;
  }
  return true;
}

/// Fresh streaming state for `seed` (reduced modulo 2^32): h1 = seed,
/// length = 0, empty tail.
/// Error case: none (total).
/// Complexity: O(1).
pub fn murmur3_x86_32_init(seed: Int) -> Murmur3State {
  return Murmur3State{
    h1: _u32(seed);
    length: 0;
    tail: Vec[UInt8].new();
  };
}

/// Feed the next chunk of bytes to a streaming hash.
/// Params: state - the mutable state (built by murmur3_x86_32_init and
///         advanced only by this function); data - the next bytes in stream
///         order; any length is accepted, including 0.
/// Returns: Ok(()) with `state` advanced. Complete 4-byte blocks are mixed
///         in stream order; a chunk that completes a previously buffered
///         block joins the buffered tail bytes first, so block order is
///         exactly the concatenated stream order. The trailing 0..3 bytes
///         are buffered in `state.tail` for the next call or for finalize.
/// Error case: Err("murmur3: invalid streaming state") when the state
///         invariants are violated (h1 outside [0, 2^32), negative length,
///         or more than 3 tail bytes); the state is left untouched in that
///         case. An empty chunk is a no-op that returns Ok(()).
/// Complexity: O(data.len()) time, O(1) extra space beyond the tail buffer.
pub fn murmur3_x86_32_update(state: &mut Murmur3State, data: &Vec[UInt8]) -> Result[Unit, Str] {
  if !murmur3_x86_32_state_is_valid(state) {
    return _err_unit("murmur3: invalid streaming state");
  }
  let buffered = state.tail;
  let tl = buffered.len();
  let n = data.len();
  var h = state.h1;
  var i = 0;
  if tl > 0 {
    let need = 4 - tl;
    if n < need {
      var grown = Vec[UInt8].new();
      var j = 0;
      while j < tl {
        grown.push(buffered[j]);
        j = j + 1;
      }
      j = 0;
      while j < n {
        grown.push(data[j]);
        j = j + 1;
      }
      state.tail = grown;
      state.length = state.length + n;
      return _ok_unit();
    }
    var b0 = 0;
    var b1 = 0;
    var b2 = 0;
    var b3 = 0;
    if tl == 1 {
      b0 = (buffered[0] as Int) & 255;
      b1 = (data[0] as Int) & 255;
      b2 = (data[1] as Int) & 255;
      b3 = (data[2] as Int) & 255;
    } elif tl == 2 {
      b0 = (buffered[0] as Int) & 255;
      b1 = (buffered[1] as Int) & 255;
      b2 = (data[0] as Int) & 255;
      b3 = (data[1] as Int) & 255;
    } else {
      b0 = (buffered[0] as Int) & 255;
      b1 = (buffered[1] as Int) & 255;
      b2 = (buffered[2] as Int) & 255;
      b3 = (data[0] as Int) & 255;
    }
    h = _mix_block(h, _pack4(b0, b1, b2, b3));
    i = need;
  }
  while i + 4 <= n {
    h = _mix_block(h, _block_at(data, i));
    i = i + 4;
  }
  var rest = Vec[UInt8].new();
  while i < n {
    rest.push(data[i]);
    i = i + 1;
  }
  state.tail = rest;
  state.h1 = h;
  state.length = state.length + n;
  return _ok_unit();
}

/// Finish a streaming hash and return the digest.
/// Params: state - the state to finish; it is read, not consumed, and is
///         left unchanged, so finalize may be called again for the same
///         digest, but update must not be called after finalize (the tail
///         bytes have already been mixed).
/// Returns: Ok(digest) equal to murmur3_x86_32 over the concatenation of
///         every chunk fed since init, with the same seed.
/// Error case: Err("murmur3: invalid streaming state") when the state
///         invariants are violated.
/// Complexity: O(1).
pub fn murmur3_x86_32_finalize(state: &Murmur3State) -> Result[Int, Str] {
  if !murmur3_x86_32_state_is_valid(state) {
    return _err_int("murmur3: invalid streaming state");
  }
  let buffered = state.tail;
  let tl = buffered.len();
  var h = state.h1;
  if tl == 1 {
    h = _tail_mix(h, (buffered[0] as Int) & 255);
  } elif tl == 2 {
    let b0 = (buffered[0] as Int) & 255;
    let b1 = (buffered[1] as Int) & 255;
    h = _tail_mix(h, _pack4(b0, b1, 0, 0));
  } elif tl == 3 {
    let b0 = (buffered[0] as Int) & 255;
    let b1 = (buffered[1] as Int) & 255;
    let b2 = (buffered[2] as Int) & 255;
    h = _tail_mix(h, _pack4(b0, b1, b2, 0));
  }
  return _ok_int(_finish(h, state.length));
}

/// The running 32-bit word h1 of a streaming state. Complexity: O(1).
pub fn murmur3_x86_32_state_h1(state: &Murmur3State) -> Int {
  return state.h1;
}

/// The total number of bytes fed into a streaming state so far.
/// Complexity: O(1).
pub fn murmur3_x86_32_state_length(state: &Murmur3State) -> Int {
  return state.length;
}

/// The number of bytes currently buffered in the streaming tail (0..3).
/// Complexity: O(1).
pub fn murmur3_x86_32_state_tail_len(state: &Murmur3State) -> Int {
  let t = state.tail;
  return t.len();
}

/// The streaming tail buffered so far (0..3 bytes, in stream order), as a
/// fresh Vec[UInt8] the caller owns. Complexity: O(1) (at most 3 bytes).
pub fn murmur3_x86_32_state_tail(state: &Murmur3State) -> Vec[UInt8] {
  let t = state.tail;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < t.len() {
    out.push(t[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  32-bit rotation helper (public, pinned scheme)
// --------------------------------------------------

/// 32-bit left rotation by `r` bits, computed with multiplication and
/// division only (the scheme the module uses internally).
/// Params: x - the word; reduced modulo 2^32 first, so any Int is accepted;
///         r - the rotation count; reduced modulo 32 first, so any Int is
///         accepted (negative counts rotate the other way).
/// Returns: (x mod 2^32) rotated left by (r mod 32) bits, as a non-negative
///         Int in [0, 2^32).
/// Error case: none (total).
/// Complexity: O(1) (two small power-of-two loops).
pub fn murmur3_x86_32_rotl32(x: Int, r: Int) -> Int {
  let v = _u32(x);
  var rr = r % 32;
  if rr < 0 {
    rr = rr + 32;
  }
  return _rotl32(v, rr);
}

// --------------------------------------------------
//  Unsigned hex display
// --------------------------------------------------

// One lowercase hex digit for 0 <= n <= 15.
fn _hex_digit(n: Int) -> Str {
  let digits = "0123456789abcdef";
  return string.str_slice(digits, n, n + 1);
}

/// Lowercase hexadecimal, exactly 8 digits, of the low 32 bits of `value`
/// interpreted as an unsigned 32-bit number.
/// Params: value - any Int; reduced modulo 2^32 first, so -1 renders as
///         "ffffffff" and 2^32 + 5 renders as "00000005".
/// Returns: the 8-digit lowercase hex string.
/// Error case: none (total). The output contains only hex digits, so no NUL
///         byte can reach the string builder.
/// Complexity: O(1).
pub fn murmur3_x86_32_hex(value: Int) -> Str {
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
