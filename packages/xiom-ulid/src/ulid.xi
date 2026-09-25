// XIOM -- xiom.ulid: ULID codec (Crockford base32, caller-supplied inputs)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) codec for the ULID layout: a 128-bit value made of a
// 48-bit Unix millisecond timestamp (most significant) followed by 80 bits of
// randomness, rendered as 26 Crockford base32 characters. Output is uppercase
// canonical; decoding is case-insensitive, and the ambiguous letters
// I, L, O and U are rejected rather than folded. See SPEC.md for the alphabet
// table, bit layout, API contract, error catalog and test plan.
//
// What is covered:
//   * ulid_alphabet: the 32-character Crockford base32 alphabet;
//   * ulid_encode: timestamp plus two caller-supplied 40-bit randomness
//     halves -> canonical 26-character text;
//   * ulid_timestamp / ulid_random_hi / ulid_random_lo: component-wise
//     decoding (the 80-bit randomness is returned as two 40-bit halves so
//     every value stays inside Int);
//   * ulid_is_valid: infallible Bool validation wrapper;
//   * ulid_canonical: re-emit any accepted ULID in canonical uppercase;
//   * ulid_compare / ulid_equal: ordering and equality over the decoded
//     (timestamp, rand_hi, rand_lo) tuple;
//   * ulid_monotonic_ok: strict progression check for caller-generated
//     ULIDs -- within one millisecond the 80-bit randomness must be
//     strictly greater.
//
// There is deliberately no randomness generation and no clock access in this
// package: the caller owns both and passes the millisecond timestamp and the
// two 40-bit randomness halves in, so every function is deterministic and
// testable.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no structs, no
//     Vec[StructType].
//   * Every raw byte read via xiom.string.byte_at is widened with
//     `(x as Int) & 0xFF` before comparison or arithmetic.
//   * No bitwise shifts: the 130-bit padded text is split with powers of two
//     (division and modulo) and folded back with `acc * 32 + digit`.
//   * Ok/Err for the Result-returning functions are constructed only in the
//     tiny leaf helpers _ok_*/_err_* below.
//
// This module never compares Str values (no `==` on Str); callers/tests use
// xiom.string.compare.str_compare.

module xiom.ulid

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Alphabet
// --------------------------------------------------

/// The Crockford base32 alphabet used by ULID (32 characters, value order).
/// Returns: "0123456789ABCDEFGHJKMNPQRSTVWXYZ". The letters I, L, O and U
/// are absent, so no character is ambiguous.
/// Error case: none.
/// Complexity: O(1).
pub fn ulid_alphabet() -> Str {
  return "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
}

// Crockford base32 digit value (0..31) of one encoded byte; -1 when the byte
// is not an accepted character. Digits '0'..'9' map to 0..9; 'A'..'Z' map to
// 10..31 in alphabet order with the ambiguous letters I (73), L (76), O (79)
// and U (85) rejected. Lowercase a..z is folded to uppercase first, so
// i, l, o and u are rejected as well.
fn _crockford_value(b: Int) -> Int {
  var x = b;
  if x >= 97 && x <= 122 {
    x = x - 32;
  }
  if x >= 48 && x <= 57 {
    return x - 48;
  }
  if x >= 65 && x <= 72 {
    return x - 55;
  }
  if x == 73 || x == 76 || x == 79 || x == 85 {
    return -1;
  }
  if x >= 74 && x <= 75 {
    return x - 56;
  }
  if x >= 77 && x <= 78 {
    return x - 57;
  }
  if x >= 80 && x <= 84 {
    return x - 58;
  }
  if x >= 86 && x <= 90 {
    return x - 59;
  }
  return -1;
}

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so comparisons never touch raw UInt8 values.
fn _byte_at_i(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// 2^k for 0 <= k <= 45, the only exponents this codec needs.
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
//  Validation and decoding helpers
// --------------------------------------------------

// Error message for a candidate ULID: "" when valid, otherwise the first
// applicable message, in this order: wrong length, first invalid character
// (scanned left to right over the 26 bytes), then 130-bit overflow. The
// overflow test is `timestamp field > 2^48 - 1`: 26 characters carry 130
// bits, so a value whose top two bits are set cannot fit the 128-bit ULID
// space and the first character must be one of '0'..'7'.
fn _error_of(s: Str) -> Str {
  if s.len() != 26 {
    return "ulid: expected 26 characters";
  }
  var ts = 0;
  var i = 0;
  while i < 10 {
    let v = _crockford_value(_byte_at_i(s, i));
    if v < 0 {
      return "ulid: invalid character";
    }
    ts = ts * 32 + v;
    i = i + 1;
  }
  while i < 26 {
    let v = _crockford_value(_byte_at_i(s, i));
    if v < 0 {
      return "ulid: invalid character";
    }
    i = i + 1;
  }
  if ts > 281474976710655 {
    return "ulid: overflow";
  }
  return "";
}

// Timestamp of an already-validated ULID: characters 0..9, most significant
// first (50 bits accumulated; the top 2 are zero for a valid value).
fn _ts_of(s: Str) -> Int {
  var v = 0;
  var i = 0;
  while i < 10 {
    v = v * 32 + _crockford_value(_byte_at_i(s, i));
    i = i + 1;
  }
  return v;
}

// High 40 bits of the randomness of an already-validated ULID:
// characters 10..17, most significant first.
fn _hi_of(s: Str) -> Int {
  var v = 0;
  var i = 10;
  while i < 18 {
    v = v * 32 + _crockford_value(_byte_at_i(s, i));
    i = i + 1;
  }
  return v;
}

// Low 40 bits of the randomness of an already-validated ULID:
// characters 18..25, most significant first.
fn _lo_of(s: Str) -> Int {
  var v = 0;
  var i = 18;
  while i < 26 {
    v = v * 32 + _crockford_value(_byte_at_i(s, i));
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Encode
// --------------------------------------------------

/// Encode a ULID from its components: a 48-bit timestamp and 80 bits of
/// randomness supplied as two 40-bit halves.
/// Params: timestamp - milliseconds since the Unix epoch, 0..281474976710655
/// (2^48 - 1); rand_hi - high 40 bits of the randomness, 0..1099511627775
/// (2^40 - 1); rand_lo - low 40 bits of the randomness, 0..1099511627775.
/// Returns: Ok(text) with the canonical 26-character uppercase Crockford
/// base32 form. Characters 0..9 carry the timestamp, 10..17 carry rand_hi
/// and 18..25 carry rand_lo; the top two bits of the 130-bit padded value
/// are zero, so the first character is always '0'..'7'.
/// Error case: Err("ulid: timestamp out of range") when timestamp is outside
/// 0..2^48 - 1; Err("ulid: randomness out of range") when either half is
/// outside 0..2^40 - 1.
/// Complexity: O(1) (fixed 26 characters).
pub fn ulid_encode(timestamp: Int, rand_hi: Int, rand_lo: Int) -> Result[Str, Str] {
  if timestamp < 0 || timestamp > 281474976710655 {
    return _err_str("ulid: timestamp out of range");
  }
  if rand_hi < 0 || rand_hi > 1099511627775 {
    return _err_str("ulid: randomness out of range");
  }
  if rand_lo < 0 || rand_lo > 1099511627775 {
    return _err_str("ulid: randomness out of range");
  }
  let alpha = ulid_alphabet();
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 10 {
    let p = _pow2(45 - i * 5);
    out.push(string.byte_at(alpha, (timestamp / p) % 32));
    i = i + 1;
  }
  var j = 0;
  while j < 8 {
    let p = _pow2(35 - j * 5);
    out.push(string.byte_at(alpha, (rand_hi / p) % 32));
    j = j + 1;
  }
  var k = 0;
  while k < 8 {
    let p = _pow2(35 - k * 5);
    out.push(string.byte_at(alpha, (rand_lo / p) % 32));
    k = k + 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Decode (component-wise; see SPEC.md section 6)
// --------------------------------------------------

/// Millisecond timestamp of a ULID.
/// Params: s - candidate text; case-insensitive, I/L/O/U rejected.
/// Returns: Ok(t) with the 48-bit timestamp (characters 0..9, most
/// significant first).
/// Error case: Err with the validation message when s is not a valid ULID:
/// "ulid: expected 26 characters", "ulid: invalid character" or
/// "ulid: overflow".
/// Complexity: O(s.len()).
pub fn ulid_timestamp(s: Str) -> Result[Int, Str] {
  let e: Str = _error_of(s);
  if e.len() != 0 {
    return _err_int(e);
  }
  return _ok_int(_ts_of(s));
}

/// High 40 bits of the randomness of a ULID.
/// Params: s - candidate text; case-insensitive, I/L/O/U rejected.
/// Returns: Ok(r) with the high 40 bits of the 80-bit randomness
/// (characters 10..17, most significant first).
/// Error case: Err with the validation message when s is not a valid ULID.
/// Complexity: O(s.len()).
pub fn ulid_random_hi(s: Str) -> Result[Int, Str] {
  let e: Str = _error_of(s);
  if e.len() != 0 {
    return _err_int(e);
  }
  return _ok_int(_hi_of(s));
}

/// Low 40 bits of the randomness of a ULID.
/// Params: s - candidate text; case-insensitive, I/L/O/U rejected.
/// Returns: Ok(r) with the low 40 bits of the 80-bit randomness
/// (characters 18..25, most significant first).
/// Error case: Err with the validation message when s is not a valid ULID.
/// Complexity: O(s.len()).
pub fn ulid_random_lo(s: Str) -> Result[Int, Str] {
  let e: Str = _error_of(s);
  if e.len() != 0 {
    return _err_int(e);
  }
  return _ok_int(_lo_of(s));
}

// --------------------------------------------------
//  Validation and canonical form
// --------------------------------------------------

/// True when `s` is a valid ULID.
/// Params: s - candidate text; uppercase and lowercase are accepted (case is
/// not significant) and the ambiguous letters I, L, O and U are rejected.
/// Returns: true exactly when the byte length is 26, every character is in
/// the Crockford alphabet and the decoded value fits 128 bits (first
/// character '0'..'7'); false otherwise.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn ulid_is_valid(s: Str) -> Bool {
  let e: Str = _error_of(s);
  if e.len() != 0 {
    return false;
  }
  return true;
}

/// Re-emit a ULID in canonical form: 26 uppercase Crockford characters.
/// Params: s - candidate text; any accepted case.
/// Returns: Ok(text) with the canonical uppercase spelling of the same
/// 128-bit value. Valid input is already canonical, so this is the identity
/// on canonical text and an uppercase fold on lowercase input.
/// Error case: Err with the validation message when s is not a valid ULID.
/// Complexity: O(s.len()).
pub fn ulid_canonical(s: Str) -> Result[Str, Str] {
  let e: Str = _error_of(s);
  if e.len() != 0 {
    return _err_str(e);
  }
  let alpha = ulid_alphabet();
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 26 {
    out.push(string.byte_at(alpha, _crockford_value(_byte_at_i(s, i))));
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Comparison, equality and monotonicity
// --------------------------------------------------

/// Compare two ULIDs by decoded value: timestamp first, then rand_hi, then
/// rand_lo.
/// Params: a, b - candidate ULIDs; any accepted case.
/// Returns: Ok(-1) when a < b, Ok(0) when a and b carry the same 128-bit
/// value, Ok(1) when a > b. For canonical uppercase text this is the same
/// order as byte-wise lexicographic comparison.
/// Error case: Err with the validation message of the first invalid
/// argument (a is checked before b).
/// Complexity: O(a.len() + b.len()).
pub fn ulid_compare(a: Str, b: Str) -> Result[Int, Str] {
  let ea: Str = _error_of(a);
  if ea.len() != 0 {
    return _err_int(ea);
  }
  let eb: Str = _error_of(b);
  if eb.len() != 0 {
    return _err_int(eb);
  }
  let ta = _ts_of(a);
  let tb = _ts_of(b);
  if ta < tb {
    return _ok_int(-1);
  }
  if ta > tb {
    return _ok_int(1);
  }
  let ha = _hi_of(a);
  let hb = _hi_of(b);
  if ha < hb {
    return _ok_int(-1);
  }
  if ha > hb {
    return _ok_int(1);
  }
  let la = _lo_of(a);
  let lb = _lo_of(b);
  if la < lb {
    return _ok_int(-1);
  }
  if la > lb {
    return _ok_int(1);
  }
  return _ok_int(0);
}

/// True when two ULIDs carry the same 128-bit value.
/// Params: a, b - candidate ULIDs; case is not significant, so a lowercase
/// spelling equals its canonical uppercase form.
/// Returns: Ok(true) when the decoded (timestamp, rand_hi, rand_lo) tuples
/// are equal, Ok(false) otherwise.
/// Error case: Err with the validation message of the first invalid
/// argument (a is checked before b).
/// Complexity: O(a.len() + b.len()).
pub fn ulid_equal(a: Str, b: Str) -> Result[Bool, Str] {
  let r = ulid_compare(a, b);
  if !r.is_ok {
    let m: Str = r.error;
    return _err_bool(m);
  }
  let c: Int = r.value;
  if c == 0 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// True when `next` is strictly greater than `prev`: the monotonicity check
/// for caller-generated ULIDs.
/// Params: prev - the previously emitted ULID; next - the candidate next
/// ULID; any accepted case.
/// Returns: Ok(true) when next > prev in decoded order. Within the same
/// millisecond this requires strictly greater 80-bit randomness (an equal or
/// smaller randomness is not monotonic); a greater timestamp is always
/// accepted and a smaller timestamp never is.
/// Error case: Err with the validation message of the first invalid
/// argument (prev is checked before next).
/// Complexity: O(prev.len() + next.len()).
pub fn ulid_monotonic_ok(prev: Str, next: Str) -> Result[Bool, Str] {
  let r = ulid_compare(prev, next);
  if !r.is_ok {
    let m: Str = r.error;
    return _err_bool(m);
  }
  let c: Int = r.value;
  if c < 0 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}
