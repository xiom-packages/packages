// XIOM -- xiom.fletcher: Fletcher-16 and Fletcher-32 checksums
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI), Int-only implementation of Fletcher's checksum in the
// classic ones'-complement form over fully materialized Vec[UInt8] buffers:
//
//   * one-shot functions fletcher16 and fletcher32;
//   * incremental triples fletcher16_init/update/finalize and
//     fletcher32_init/update/finalize over a single packed Int state;
//   * strict variants fletcher16_update_checked, fletcher16_finalize_checked
//     and the 32-bit pair that reject non-canonical states;
//   * total predicates fletcher16_state_valid and fletcher32_state_valid;
//   * unsigned display helpers fletcher16_hex (4 digits) and fletcher32_hex
//     (8 digits).
//
// Reduction cadence (pinned): both running sums are reduced after EVERY
// input byte.
//
//   Fletcher-16:  sum1 = (sum1 + b) % 255    sum2 = (sum2 + sum1) % 255
//   Fletcher-32:  sum1 = (sum1 + b) % 65535  sum2 = (sum2 + sum1) % 65535
//
// so sum1 and sum2 are always canonical residues in [0, 254] and [0, 65534]
// respectively. Reducing per byte is equivalent to the classic deferred form
// (addition is congruent modulo the modulus, so any later reduction reaches
// the same residues) and keeps every intermediate small: the largest values
// before reduction are 509 and 508 for the 16-bit sums, 65789 and 131068 for
// the 32-bit sums, all exact Int values with no shift, bitwise AND or
// overflow concern anywhere.
//
// Output order (pinned, the common convention): the checksum is the packed
// Int
//
//   Fletcher-16:  sum2 * 256 + sum1       (sum1 in the low byte)
//   Fletcher-32:  sum2 * 65536 + sum1     (sum1 in the low word)
//
// so a Fletcher-16 checksum lies in [0, 65278] (0x0000..0xFEFE) and a
// Fletcher-32 checksum in [0, 4294901758] (0x00000000..0xFFFEFFFE). Every
// input byte is widened with `(b as Int) & 255` before it enters the sums.
//
// Incremental state is exactly the checksum encoding above: init() is the
// empty sum 0, update() continues the running sums and finalize()
// canonicalizes (a no-op on states produced by init/update). The unchecked
// update and finalize accept any Int and canonicalize it deterministically
// (low 16/32 bits first, then each component modulo the modulus); the
// *_checked variants enforce the canonical-state contract and return
// Err("fletcher: invalid state") otherwise. That single message is the
// entire error catalog.
//
// Fletcher's checksum is an error-detection code, not a cryptographic hash:
// it is not collision-resistant, not a MAC and trivially forgeable.
// Adler-32 is a different checksum (modulus 65521, init 1, a different
// output fold) and is a documented non-goal, not a variant of this package.
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
//   * every sum stays a non-negative Int below 2^17, so `%` is the only
//     reduction operator used -- no `&`, `<<` or `>>` ever sees a high bit;
//   * the module never compares Str values; the hex helpers build Str from
//     lowercase hex digits only (no NUL byte can reach the string builder).

module xiom.fletcher

use xiom.string;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Fletcher-16 modulus: one 8-bit ones'-complement word (2^8 - 1).
const _F16_MOD: Int = 255;

// Fletcher-16 state radix: sum2 sits one 8-bit word above sum1.
const _F16_RADIX: Int = 256;

// The 16-bit window an arbitrary state is reduced to before canonicalizing.
const _F16_STATE_RANGE: Int = 65536;

// Largest canonical Fletcher-16 checksum: 254 * 256 + 254 (0xFEFE).
const _F16_MAX_STATE: Int = 65278;

// Fletcher-32 modulus: one 16-bit ones'-complement word (2^16 - 1).
const _F32_MOD: Int = 65535;

// Fletcher-32 state radix: sum2 sits one 16-bit word above sum1.
const _F32_RADIX: Int = 65536;

// The 32-bit window an arbitrary state is reduced to before canonicalizing.
const _F32_STATE_RANGE: Int = 4294967296;

// Largest canonical Fletcher-32 checksum: 65534 * 65536 + 65534.
const _F32_MAX_STATE: Int = 4294901758;

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

// Canonical Fletcher-16 state of any Int: the low 16 bits are taken, split
// into sum1 (low byte) and sum2 (high byte), and each component is reduced
// modulo 255. The result is in [0, 65278], and a canonical state maps to
// itself.
fn _f16_canon(state: Int) -> Int {
  let w = _residue(state, _F16_STATE_RANGE);
  let s1 = _residue(w % _F16_RADIX, _F16_MOD);
  let s2 = _residue(w / _F16_RADIX, _F16_MOD);
  return s2 * _F16_RADIX + s1;
}

// Canonical Fletcher-32 state of any Int: the low 32 bits are taken, split
// into sum1 (low word) and sum2 (high word), and each component is reduced
// modulo 65535. The result is in [0, 4294901758], and a canonical state maps
// to itself.
fn _f32_canon(state: Int) -> Int {
  let w = _residue(state, _F32_STATE_RANGE);
  let s1 = _residue(w % _F32_RADIX, _F32_MOD);
  let s2 = _residue(w / _F32_RADIX, _F32_MOD);
  return s2 * _F32_RADIX + s1;
}

// Continue a Fletcher-16 state over `data`, one byte at a time, with the
// per-byte reduction cadence pinned in the module header. `state` is
// canonicalized first, so any Int is accepted; the result is canonical.
fn _f16_bytes(state: Int, data: &Vec[UInt8]) -> Int {
  let c = _f16_canon(state);
  var s1 = c % _F16_RADIX;
  var s2 = c / _F16_RADIX;
  var i = 0;
  while i < data.len() {
    let b = (data[i] as Int) & 255;
    s1 = (s1 + b) % _F16_MOD;
    s2 = (s2 + s1) % _F16_MOD;
    i = i + 1;
  }
  return s2 * _F16_RADIX + s1;
}

// Continue a Fletcher-32 state over `data`, one byte at a time, with the
// per-byte reduction cadence pinned in the module header. `state` is
// canonicalized first, so any Int is accepted; the result is canonical.
fn _f32_bytes(state: Int, data: &Vec[UInt8]) -> Int {
  let c = _f32_canon(state);
  var s1 = c % _F32_RADIX;
  var s2 = c / _F32_RADIX;
  var i = 0;
  while i < data.len() {
    let b = (data[i] as Int) & 255;
    s1 = (s1 + b) % _F32_MOD;
    s2 = (s2 + s1) % _F32_MOD;
    i = i + 1;
  }
  return s2 * _F32_RADIX + s1;
}

// --------------------------------------------------
//  Fletcher-16
// --------------------------------------------------

/// Fletcher-16 initial state: the packed empty sum, 0 (sum1 = sum2 = 0).
/// Returns: 0, the Fletcher-16 checksum of the empty input.
/// Error case: none (total).
/// Complexity: O(1).
pub fn fletcher16_init() -> Int {
  return 0;
}

/// One-shot Fletcher-16 checksum of a whole byte buffer.
/// Params: data - the bytes to checksum, in order (any length, including 0).
/// Returns: the canonical Fletcher-16 checksum sum2 * 256 + sum1 as an Int
/// in [0, 65278]; the empty input yields 0.
/// Error case: none (total).
/// Complexity: O(data.len()) time, O(1) space.
pub fn fletcher16(data: &Vec[UInt8]) -> Int {
  return _f16_bytes(0, data);
}

/// Continue a Fletcher-16 checksum with the next chunk of bytes.
/// Params: state - the packed running state (init() or a previous update
/// result); any Int is accepted and canonicalized first; data - the next
/// bytes in stream order (any length, including 0).
/// Returns: the new canonical state, equal to fletcher16(state || data) for
/// the concatenated stream; sum1/sum2 are reduced after every byte.
/// Error case: none (total; use fletcher16_update_checked for strict state
/// validation).
/// Complexity: O(data.len()) time, O(1) space.
pub fn fletcher16_update(state: Int, data: &Vec[UInt8]) -> Int {
  return _f16_bytes(state, data);
}

/// Finish a Fletcher-16 checksum.
/// Params: state - the packed running state; any Int is accepted and
/// canonicalized first.
/// Returns: the canonical checksum sum2 * 256 + sum1 in [0, 65278]. Fletcher
/// applies no output transformation, so finalize is the identity on states
/// produced by init/update; it exists so the incremental API has the classic
/// init/update/finalize shape.
/// Error case: none (total; use fletcher16_finalize_checked for strict state
/// validation).
/// Complexity: O(1).
pub fn fletcher16_finalize(state: Int) -> Int {
  return _f16_canon(state);
}

/// True when `state` is a canonical Fletcher-16 state: an Int in
/// [0, 65278] whose low byte (sum1) is at most 254. States produced by
/// fletcher16_init and fletcher16_update always satisfy this; anything else
/// is out of contract for the checked variants.
/// Params: state - the candidate state, any Int.
/// Returns: true for the canonical range [0, 65278] with sum1 <= 254.
/// Error case: none (total predicate).
/// Complexity: O(1).
pub fn fletcher16_state_valid(state: Int) -> Bool {
  if state < 0 {
    return false;
  }
  if state > _F16_MAX_STATE {
    return false;
  }
  if state % _F16_RADIX > 254 {
    return false;
  }
  return true;
}

/// Strict Fletcher-16 update: like fletcher16_update but rejects a state
/// outside the canonical contract instead of canonicalizing it.
/// Params: state - the packed running state, which must be canonical
/// (fletcher16_state_valid is true); data - the next bytes in stream order.
/// Returns: Ok(new canonical state), equal to fletcher16_update(state, data)
/// for canonical states.
/// Error case: Err("fletcher: invalid state") when the state is not
/// canonical; `data` is not read in that case.
/// Complexity: O(data.len()) time, O(1) space.
pub fn fletcher16_update_checked(state: Int, data: &Vec[UInt8]) -> Result[Int, Str] {
  if !fletcher16_state_valid(state) {
    return _err_int("fletcher: invalid state");
  }
  return _ok_int(_f16_bytes(state, data));
}

/// Strict Fletcher-16 finalize: like fletcher16_finalize but rejects a state
/// outside the canonical contract instead of canonicalizing it.
/// Params: state - the packed running state, which must be canonical
/// (fletcher16_state_valid is true).
/// Returns: Ok(checksum), equal to fletcher16_finalize(state) and to
/// `state` itself for canonical states.
/// Error case: Err("fletcher: invalid state") when the state is not
/// canonical.
/// Complexity: O(1).
pub fn fletcher16_finalize_checked(state: Int) -> Result[Int, Str] {
  if !fletcher16_state_valid(state) {
    return _err_int("fletcher: invalid state");
  }
  return _ok_int(_f16_canon(state));
}

// --------------------------------------------------
//  Fletcher-32
// --------------------------------------------------

/// Fletcher-32 initial state: the packed empty sum, 0 (sum1 = sum2 = 0).
/// Returns: 0, the Fletcher-32 checksum of the empty input.
/// Error case: none (total).
/// Complexity: O(1).
pub fn fletcher32_init() -> Int {
  return 0;
}

/// One-shot Fletcher-32 checksum of a whole byte buffer.
/// Params: data - the bytes to checksum, in order (any length, including 0).
/// Returns: the canonical Fletcher-32 checksum sum2 * 65536 + sum1 as an Int
/// in [0, 4294901758]; the empty input yields 0.
/// Error case: none (total).
/// Complexity: O(data.len()) time, O(1) space.
pub fn fletcher32(data: &Vec[UInt8]) -> Int {
  return _f32_bytes(0, data);
}

/// Continue a Fletcher-32 checksum with the next chunk of bytes.
/// Params: state - the packed running state (init() or a previous update
/// result); any Int is accepted and canonicalized first; data - the next
/// bytes in stream order (any length, including 0).
/// Returns: the new canonical state, equal to fletcher32(state || data) for
/// the concatenated stream; sum1/sum2 are reduced after every byte.
/// Error case: none (total; use fletcher32_update_checked for strict state
/// validation).
/// Complexity: O(data.len()) time, O(1) space.
pub fn fletcher32_update(state: Int, data: &Vec[UInt8]) -> Int {
  return _f32_bytes(state, data);
}

/// Finish a Fletcher-32 checksum.
/// Params: state - the packed running state; any Int is accepted and
/// canonicalized first.
/// Returns: the canonical checksum sum2 * 65536 + sum1 in [0, 4294901758].
/// Fletcher applies no output transformation, so finalize is the identity on
/// states produced by init/update; it exists so the incremental API has the
/// classic init/update/finalize shape.
/// Error case: none (total; use fletcher32_finalize_checked for strict state
/// validation).
/// Complexity: O(1).
pub fn fletcher32_finalize(state: Int) -> Int {
  return _f32_canon(state);
}

/// True when `state` is a canonical Fletcher-32 state: an Int in
/// [0, 4294901758] whose low word (sum1) is at most 65534. States produced
/// by fletcher32_init and fletcher32_update always satisfy this; anything
/// else is out of contract for the checked variants.
/// Params: state - the candidate state, any Int.
/// Returns: true for the canonical range [0, 4294901758] with sum1 <= 65534.
/// Error case: none (total predicate).
/// Complexity: O(1).
pub fn fletcher32_state_valid(state: Int) -> Bool {
  if state < 0 {
    return false;
  }
  if state > _F32_MAX_STATE {
    return false;
  }
  if state % _F32_RADIX > 65534 {
    return false;
  }
  return true;
}

/// Strict Fletcher-32 update: like fletcher32_update but rejects a state
/// outside the canonical contract instead of canonicalizing it.
/// Params: state - the packed running state, which must be canonical
/// (fletcher32_state_valid is true); data - the next bytes in stream order.
/// Returns: Ok(new canonical state), equal to fletcher32_update(state, data)
/// for canonical states.
/// Error case: Err("fletcher: invalid state") when the state is not
/// canonical; `data` is not read in that case.
/// Complexity: O(data.len()) time, O(1) space.
pub fn fletcher32_update_checked(state: Int, data: &Vec[UInt8]) -> Result[Int, Str] {
  if !fletcher32_state_valid(state) {
    return _err_int("fletcher: invalid state");
  }
  return _ok_int(_f32_bytes(state, data));
}

/// Strict Fletcher-32 finalize: like fletcher32_finalize but rejects a state
/// outside the canonical contract instead of canonicalizing it.
/// Params: state - the packed running state, which must be canonical
/// (fletcher32_state_valid is true).
/// Returns: Ok(checksum), equal to fletcher32_finalize(state) and to
/// `state` itself for canonical states.
/// Error case: Err("fletcher: invalid state") when the state is not
/// canonical.
/// Complexity: O(1).
pub fn fletcher32_finalize_checked(state: Int) -> Result[Int, Str] {
  if !fletcher32_state_valid(state) {
    return _err_int("fletcher: invalid state");
  }
  return _ok_int(_f32_canon(state));
}

// --------------------------------------------------
//  Unsigned hex display
// --------------------------------------------------

// One lowercase hex digit for 0 <= n <= 15.
fn _hex_digit(n: Int) -> Str {
  let digits = "0123456789abcdef";
  return string.str_slice(digits, n, n + 1);
}

/// Lowercase hexadecimal, exactly 4 digits, of the low 16 bits of `value`
/// interpreted as an unsigned 16-bit number.
/// Params: value - any Int; reduced modulo 2^16 first, so -1 renders as
/// "ffff" and 65536 renders as "0000".
/// Returns: the 4-digit lowercase hex string (for a canonical Fletcher-16
/// checksum this is the fixed-width rendering of sum2 * 256 + sum1).
/// Error case: none (total); the output contains only hex digits, so no NUL
/// byte can reach the string builder.
/// Complexity: O(1).
pub fn fletcher16_hex(value: Int) -> Str {
  var v = _residue(value, _F16_STATE_RANGE);
  var out = "";
  var i = 0;
  while i < 4 {
    out = _hex_digit(v % 16) + out;
    v = v / 16;
    i = i + 1;
  }
  return out;
}

/// Lowercase hexadecimal, exactly 8 digits, of the low 32 bits of `value`
/// interpreted as an unsigned 32-bit number.
/// Params: value - any Int; reduced modulo 2^32 first, so -1 renders as
/// "ffffffff" and 2^32 renders as "00000000".
/// Returns: the 8-digit lowercase hex string (for a canonical Fletcher-32
/// checksum this is the fixed-width rendering of sum2 * 65536 + sum1).
/// Error case: none (total); the output contains only hex digits, so no NUL
/// byte can reach the string builder.
/// Complexity: O(1).
pub fn fletcher32_hex(value: Int) -> Str {
  var v = _residue(value, _F32_STATE_RANGE);
  var out = "";
  var i = 0;
  while i < 8 {
    out = _hex_digit(v % 16) + out;
    v = v / 16;
    i = i + 1;
  }
  return out;
}
