// XIOM -- xiom.adler32: Adler-32 checksum with deferred reduction
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI), Int-only implementation of Adler-32 (RFC 1950,
// section 9) over fully materialized Vec[UInt8] buffers:
//
//   * one-shot adler32;
//   * incremental triple adler32_init/update/finalize over a single packed
//     Int state;
//   * strict variants adler32_update_checked and adler32_finalize_checked
//     plus the total predicate adler32_state_valid;
//   * unsigned display helper adler32_hex (8 lowercase hex digits).
//
// Algorithm: two running sums modulo 65521 (the largest prime below 2^16),
// initialized to s1 = 1 and s2 = 0:
//
//   for each byte b in order:
//     s1 = (s1 + b) mod 65521
//     s2 = (s2 + s1) mod 65521
//   checksum = s2 * 65536 + s1
//
// The packed checksum is zlib-compatible: s1 occupies the low 16 bits and s2
// the high 16 bits ((s2 << 16) | s1). The empty input is 1 (s1 = 1, s2 = 0)
// and a canonical checksum lies in [0, 4293984240] (0x00000000..0xFFF0FFF0).
//
// Reduction cadence (pinned, deferred): inside one update call the sums are
// accumulated without reduction for at most 5552 bytes -- the classic zlib
// NMAX -- and are then reduced modulo 65521; every update call and every
// finalize reduces the state again, so the state handed back is always
// canonical. Within one 5552-byte block the largest values reached are
//
//   s1 <= 65520 + 5552 * 255                           = 1481280
//   s2 <= 65520 + 65520 * 5552 + 255 * 5552 * 5553 / 2 = 4294690200
//
// and 4294690200 < 2^32, the standard Adler-32 argument for the 5552 block
// size. Deferring is exact, not an approximation: addition is congruent
// modulo 65521, so reducing once per block -- or only at finalize -- reaches
// exactly the same residues as reducing after every byte. The conformance
// suite proves the agreement on inputs longer than 5552 bytes with a
// test-local per-byte reference and a fully deferred one.
//
// Byte handling: every input byte is masked into range with `(b as Int) & 255`
// before it enters the sums, so bytes with bit 7 set (0x80..0xFF) enter as
// 128..255; no raw UInt8 is ever compared against a constant >= 128. Inputs
// may have any length, including zero.
//
// Incremental state is the packed encoding above. adler32_init() is 1, the
// empty state; update() continues the running sums and finalize() applies the
// final modulo. The unchecked update and finalize accept any Int and
// canonicalize it deterministically (low 32 bits first, then each component
// modulo 65521); the *_checked variants enforce the canonical-state contract
// and return Err("adler32: invalid state") otherwise. That single message is
// the entire error catalog.
//
// Adler-32 is an error-detection checksum (used by zlib, gzip and PNG), not a
// cryptographic hash: it is not collision-resistant, not a MAC and trivially
// forgeable. This package computes checksum values only; it does not read or
// write zlib/gzip containers and implements no other checksum.
//
// See SPEC.md for the formal model, the pinned vector tables, the API
// contract and the test plan.
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no methods, no lambdas, no Vec[fn] dispatch, no
//     struct types and no Vec[StructType];
//   * Ok/Err for the Result-returning checked variants are constructed only
//     in the tiny leaf helpers _ok_int/_err_int;
//   * bytes read from Vec[UInt8] are widened with `(b as Int) & 255`; no raw
//     UInt8 is ever compared against a constant >= 128;
//   * every sum stays a non-negative Int below 2^32, so `%` is the only
//     reduction operator used -- no `&`, `<<` or `>>` ever sees a high bit;
//   * the module never compares Str values; the hex helper builds Str from
//     lowercase hex digits only (no NUL byte can reach the string builder).

module xiom.adler32

use xiom.string;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Adler-32 modulus: the largest prime below 2^16.
const _ADLER_MOD: Int = 65521;

// State radix: s2 sits one 16-bit word above s1 ((s2 << 16) | s1).
const _ADLER_RADIX: Int = 65536;

// The 32-bit window an arbitrary state is reduced to before canonicalizing.
const _ADLER_STATE_RANGE: Int = 4294967296;

// Largest canonical checksum: 65520 * 65536 + 65520 (0xFFF0FFF0).
const _ADLER_MAX_STATE: Int = 4293984240;

// Deferred-reduction block size: the classic zlib NMAX for 32-bit sums.
const _ADLER_NMAX: Int = 5552;

// --------------------------------------------------
//  Result constructors (v0.61.3: Ok/Err only in leaf helpers)
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
//  Internal arithmetic
// --------------------------------------------------

// Non-negative residue of `v` modulo `m` (m > 0), in [0, m). Exact for any
// Int and under both truncating and flooring `%` semantics: a negative
// remainder is shifted into range by a single addition.
fn _residue(v: Int, m: Int) -> Int {
  var r = v % m;
  if r < 0 {
    r = r + m;
  }
  return r;
}

// Canonical Adler-32 state of any Int: the low 32 bits are taken, split into
// s1 (low word) and s2 (high word), and each component is reduced modulo
// 65521. The result is in [0, 4293984240], and a canonical state maps to
// itself.
fn _adler_canon(state: Int) -> Int {
  let w = _residue(state, _ADLER_STATE_RANGE);
  let s1 = _residue(w % _ADLER_RADIX, _ADLER_MOD);
  let s2 = _residue(w / _ADLER_RADIX, _ADLER_MOD);
  return s2 * _ADLER_RADIX + s1;
}

// Continue an Adler-32 state over `data` with the deferred cadence pinned in
// the module header: up to 5552 bytes are accumulated without reduction, then
// both sums are reduced modulo 65521; the final block of the call is reduced
// as well, so the result is canonical. `state` is canonicalized first, so any
// Int is accepted.
fn _adler_bytes(state: Int, data: &Vec[UInt8]) -> Int {
  let c = _adler_canon(state);
  var s1 = c % _ADLER_RADIX;
  var s2 = c / _ADLER_RADIX;
  var i = 0;
  while i < data.len() {
    var n = data.len() - i;
    if n > _ADLER_NMAX {
      n = _ADLER_NMAX;
    }
    var j = 0;
    while j < n {
      let b = (data[i] as Int) & 255;
      s1 = s1 + b;
      s2 = s2 + s1;
      j = j + 1;
      i = i + 1;
    }
    s1 = s1 % _ADLER_MOD;
    s2 = s2 % _ADLER_MOD;
  }
  return s2 * _ADLER_RADIX + s1;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Adler-32 initial state: the packed empty sum, 1 (s1 = 1, s2 = 0).
/// Returns: 1, the Adler-32 checksum of the empty input.
/// Error case: none (total).
/// Complexity: O(1).
pub fn adler32_init() -> Int {
  return 1;
}

/// One-shot Adler-32 checksum of a whole byte buffer.
/// Params: data - the bytes to checksum, in order (any length, including 0).
/// Returns: the zlib-compatible checksum s2 * 65536 + s1 as an Int in
/// [0, 4293984240]; the empty input yields 1.
/// Error case: none (total).
/// Complexity: O(data.len()) time, O(1) space.
pub fn adler32(data: &Vec[UInt8]) -> Int {
  return _adler_bytes(1, data);
}

/// Continue an Adler-32 checksum with the next chunk of bytes.
/// Params: state - the packed running state (init() or a previous update
/// result); any Int is accepted and canonicalized first; data - the next
/// bytes in stream order (any length, including 0).
/// Returns: the new canonical state, equal to adler32(state || data) for the
/// concatenated stream. Inside the call the sums defer reduction for at most
/// 5552 bytes and are then reduced modulo 65521, which is exactly equivalent
/// to reducing after every byte.
/// Error case: none (total; use adler32_update_checked for strict state
/// validation).
/// Complexity: O(data.len()) time, O(1) space.
pub fn adler32_update(state: Int, data: &Vec[UInt8]) -> Int {
  return _adler_bytes(state, data);
}

/// Finish an Adler-32 checksum.
/// Params: state - the packed running state; any Int is accepted and
/// canonicalized first.
/// Returns: the canonical checksum s2 * 65536 + s1 in [0, 4293984240].
/// Adler-32 applies no output transformation, so finalize is the identity on
/// states produced by init/update; it exists so the incremental API has the
/// classic init/update/finalize shape and so a state can be reduced after a
/// deferred run.
/// Error case: none (total; use adler32_finalize_checked for strict state
/// validation).
/// Complexity: O(1).
pub fn adler32_finalize(state: Int) -> Int {
  return _adler_canon(state);
}

/// True when `state` is a canonical Adler-32 state: an Int in
/// [0, 4293984240] whose low word (s1) is at most 65520 (range and low word
/// together also bound s2 by 65520). States produced by adler32_init and
/// adler32_update always satisfy this; anything else is out of contract for
/// the checked variants.
/// Params: state - the candidate state, any Int.
/// Returns: true for the canonical range [0, 4293984240] with s1 <= 65520.
/// Error case: none (total predicate).
/// Complexity: O(1).
pub fn adler32_state_valid(state: Int) -> Bool {
  if state < 0 {
    return false;
  }
  if state > _ADLER_MAX_STATE {
    return false;
  }
  if state % _ADLER_RADIX > 65520 {
    return false;
  }
  return true;
}

/// Strict Adler-32 update: like adler32_update but rejects a state outside
/// the canonical contract instead of canonicalizing it.
/// Params: state - the packed running state, which must be canonical
/// (adler32_state_valid is true); data - the next bytes in stream order.
/// Returns: Ok(new canonical state), equal to adler32_update(state, data) for
/// canonical states.
/// Error case: Err("adler32: invalid state") when the state is not canonical;
/// `data` is not read in that case.
/// Complexity: O(data.len()) time, O(1) space.
pub fn adler32_update_checked(state: Int, data: &Vec[UInt8]) -> Result[Int, Str] {
  if !adler32_state_valid(state) {
    return _err_int("adler32: invalid state");
  }
  return _ok_int(_adler_bytes(state, data));
}

/// Strict Adler-32 finalize: like adler32_finalize but rejects a state
/// outside the canonical contract instead of canonicalizing it.
/// Params: state - the packed running state, which must be canonical
/// (adler32_state_valid is true).
/// Returns: Ok(checksum), equal to adler32_finalize(state) and to `state`
/// itself for canonical states.
/// Error case: Err("adler32: invalid state") when the state is not canonical.
/// Complexity: O(1).
pub fn adler32_finalize_checked(state: Int) -> Result[Int, Str] {
  if !adler32_state_valid(state) {
    return _err_int("adler32: invalid state");
  }
  return _ok_int(_adler_canon(state));
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
/// "ffffffff" and 2^32 renders as "00000000".
/// Returns: the 8-digit lowercase hex string (for a canonical Adler-32
/// checksum this is the fixed-width rendering of (s2 << 16) | s1).
/// Error case: none (total); the output contains only hex digits, so no NUL
/// byte can reach the string builder.
/// Complexity: O(1).
pub fn adler32_hex(value: Int) -> Str {
  var v = _residue(value, _ADLER_STATE_RANGE);
  var out = "";
  var i = 0;
  while i < 8 {
    out = _hex_digit(v % 16) + out;
    v = v / 16;
    i = i + 1;
  }
  return out;
}
