// XIOM -- xiom.bech32: Bech32 and Bech32m encoding/decoding (BIP-173, BIP-350)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) codec for the Bech32 and Bech32m checksummed base32
// formats:
//   * bech32_encode: HRP + "1" + 5-bit data symbols + 6-symbol checksum,
//     emitted in canonical all-lowercase form. The caller supplies the data
//     part as 5-bit values (use bech32_bytes_to_symbols to convert 8-bit
//     input).
//   * bech32_decode: splits a string into HRP / separator / data part,
//     case-folds an all-uppercase string to lowercase, verifies the data
//     alphabet and the 6-symbol checksum, and returns a Bech32 value (hrp,
//     variant, data without the checksum symbols). The variant is selected
//     by the checksum constant: 1 = Bech32 (BIP-173), 0x2bc830a3 = Bech32m
//     (BIP-350).
//   * bech32_decode_variant: same, but requires a specific variant and
//     reports "bech32: wrong variant" when the string is valid only under
//     the other constant.
//   * bech32_convertbits: BIP-173 bit-group conversion; the 8->5 direction
//     pads a partial trailing group with zero bits, the 5->8 direction
//     (pad=false) rejects oversized leftovers and non-zero trailing bits.
//
// Format rules (BIP-173 / BIP-350):
//   * A Bech32 string is at most 90 characters long.
//   * HRP: 1..83 US-ASCII characters in [33,126]; the last '1' in the
//     string is the separator.
//   * Data part: at least 6 characters from the 32-character alphabet
//     "qpzry9x8gf2tvdw0s3jn54khce6mua7l" ("1", "b", "i" and "o" are not in
//     it); its last 6 characters are the checksum.
//   * Checksum: polymod over hrp-expand(hrp) + data symbols, compared with
//     the variant constant (1 or 0x2bc830a3).
//   * Decoding rejects mixed-case strings; an all-uppercase string is
//     accepted and folded to the canonical lowercase form. The encoder
//     refuses an uppercase HRP because it would emit a mixed-case string.
//
// Ambiguity (BIP-350, test-vector notes): no string can be simultaneously
// valid Bech32 and Bech32m, because validity is the single comparison
// polymod(...) == constant and 1 != 0x2bc830a3. bech32_decode therefore
// always resolves a valid string to exactly one variant, and
// bech32_decode_variant distinguishes "bech32: wrong variant" (valid under
// the other constant) from "bech32: bad checksum" (valid under neither).
// There is no "verifies against both constants" outcome to report.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType].
//   * No bitwise shifts anywhere: the polymod loop uses division and modulo
//     by 2^25 / 2^30 and the checksum is extracted by dividing by
//     2^(5*(5-i)) (shifts on values with the high bit set miscompile).
//   * Every byte read via xiom.string.byte_at or from a Vec[UInt8] is
//     widened with `(x as Int) & 0xFF` before comparison or arithmetic.
//   * Ok/Err are constructed only in the tiny leaf helpers below;
//     constructing them inside larger functions miscompiles, and a struct
//     payload needs its own leaf (_ok_bech32/_err_bech32).
//   * Callers should bind the Ok payload of a Result to a local before
//     passing `&value` to a function (v0.61.3 reads an empty Vec through a
//     direct Result-payload field reference); the tests follow this.
//
// This module never compares Str values; use xiom.string.compare.str_compare.

module xiom.bech32

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Constants and charset
// --------------------------------------------------

/// Checksum variant selector for the Bech32 encoding (BIP-173, constant 1).
/// Passed to bech32_encode and bech32_decode_variant; returned by
/// bech32_variant.
pub const BECH32_VARIANT_BECH32: Int = 0;

/// Checksum variant selector for the Bech32m encoding (BIP-350, constant
/// 0x2bc830a3).
pub const BECH32_VARIANT_BECH32M: Int = 1;

// BIP-173 checksum constant (also the initial polymod value).
const _BECH32_CONST_BECH32: Int = 1;

// BIP-350 checksum constant.
const _BECH32_CONST_BECH32M: Int = 0x2bc830a3;

// Longest Bech32 string, in characters (BIP-173).
const _BECH32_MAX_LEN: Int = 90;

// Longest HRP, in characters (BIP-173).
const _BECH32_MAX_HRP: Int = 83;

// 5-bit group mask as a value bound (v0.61.3: no shifts).
const _BECH32_MAX_SYMBOL: Int = 31;

/// The Bech32 data alphabet, in value order (index = 5-bit value).
/// Returns: "qpzry9x8gf2tvdw0s3jn54khce6mua7l".
/// Error case: none.
/// Complexity: O(1).
pub fn bech32_charset() -> Str {
  return "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
}

// --------------------------------------------------
//  Decoded value and Result constructors
// --------------------------------------------------

/// A decoded Bech32/Bech32m string.
/// * `hrp` is the human-readable part in canonical lowercase form (an
///   all-uppercase input is folded here).
/// * `variant` is BECH32_VARIANT_BECH32 or BECH32_VARIANT_BECH32M.
/// * `data` is the data part as 5-bit values (0..31), checksum symbols
///   removed; it may be empty.
pub type Bech32 = {
  hrp: Str;
  variant: Int;
  data: Vec[Int];
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Int], Str].
fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_ints(m: Str) -> Result[Vec[Int], Str] {
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

// Ok(v) for Result[Bech32, Str].
fn _ok_bech32(v: Bech32) -> Result[Bech32, Str] {
  return Ok(v);
}

// Err(m) for Result[Bech32, Str].
fn _err_bech32(m: Str) -> Result[Bech32, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Bit and byte helpers
// --------------------------------------------------

// 2^k for 0 <= k <= 30. Replaces every shift in this module.
fn _pow2(k: Int) -> Int {
  var r = 1;
  var i = 0;
  while i < k {
    r = r * 2;
    i = i + 1;
  }
  return r;
}

// 5-bit value of an already case-folded data byte; -1 when the byte is not
// in the Bech32 alphabet. Linear scan over the 32-character alphabet.
fn _bech32_value(b: Int) -> Int {
  let cset = bech32_charset();
  var i = 0;
  while i < 32 {
    if (((string.byte_at(cset, i) as Int) & 0xFF) == b) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// hrp-expand from BIP-173: the high 3 bits of every HRP byte, a zero
// separator, then the low 5 bits of every HRP byte. `hrp` must already be
// lowercase (both callers case-fold or validate before calling).
fn _bech32_expand(hrp: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = hrp.len();
  var i = 0;
  while i < n {
    out.push(((string.byte_at(hrp, i) as Int) & 0xFF) / 32);
    i = i + 1;
  }
  out.push(0);
  i = 0;
  while i < n {
    out.push(((string.byte_at(hrp, i) as Int) & 0xFF) % 32);
    i = i + 1;
  }
  return out;
}

// The BIP-173 polymod over a value sequence, without shifts:
//   top = chk >> 25           -> chk / 2^25 (chk < 2^30, top < 32)
//   chk = (chk & 0x1ffffff) << 5 ^ v -> (chk % 2^25) * 32 + v
//   chk ^= GEN[i] when bit i of top is set -> test (top / 2^i) % 2
// Every value must be in 0..31; all callers validate that.
fn _bech32_polymod(values: &Vec[Int]) -> Int {
  var chk = 1;
  let n = values.len();
  var i = 0;
  while i < n {
    let v: Int = values[i];
    let top = chk / 33554432;
    chk = (chk % 33554432) * 32 + v;
    if top % 2 == 1 { chk = chk ^ 0x3b6a57b2; }
    if (top / 2) % 2 == 1 { chk = chk ^ 0x26508e6d; }
    if (top / 4) % 2 == 1 { chk = chk ^ 0x1ea119fa; }
    if (top / 8) % 2 == 1 { chk = chk ^ 0x3d4233dd; }
    if (top / 16) % 2 == 1 { chk = chk ^ 0x2a1462b3; }
    i = i + 1;
  }
  return chk;
}

// The 6 checksum symbols for (hrp, data) under `constant`, most significant
// symbol first. `data` must already be validated 5-bit values and `hrp`
// must be lowercase.
fn _bech32_create_checksum(hrp: Str, data: &Vec[Int], constant: Int) -> Vec[Int] {
  var values = _bech32_expand(hrp);
  let n = data.len();
  var i = 0;
  while i < n {
    let v: Int = data[i];
    values.push(v);
    i = i + 1;
  }
  var z = 0;
  while z < 6 {
    values.push(0);
    z = z + 1;
  }
  let pm = _bech32_polymod(&values) ^ constant;
  var out = Vec[Int].new();
  var k = 0;
  while k < 6 {
    out.push((pm / _pow2(5 * (5 - k))) % 32);
    k = k + 1;
  }
  return out;
}

// --------------------------------------------------
//  Encoding
// --------------------------------------------------

/// Encode `hrp` and 5-bit `data` symbols as Bech32 (variant 0) or Bech32m
/// (variant 1), in canonical all-lowercase form.
/// Params: hrp - human-readable part, 1..83 characters, all lowercase, every
/// byte in [33,126]; data - 5-bit values (0..31), no checksum; variant -
/// BECH32_VARIANT_BECH32 or BECH32_VARIANT_BECH32M.
/// Returns: Ok(text) with the complete string; its length is
/// hrp.len() + 1 + data.len() + 6 and must not exceed 90.
/// Error case: Err("bech32: bad variant") when variant is neither 0 nor 1;
/// Err("bech32: invalid hrp length") when hrp is empty or longer than 83;
/// Err("bech32: invalid hrp character") for a byte outside [33,126];
/// Err("bech32: mixed case") when hrp contains an uppercase letter (it
/// would make the emitted string mixed case);
/// Err("bech32: invalid data value") for a value outside 0..31;
/// Err("bech32: bad length") when the resulting string would exceed 90
/// characters (BIP-173).
/// Complexity: O(hrp.len() + data.len()).
pub fn bech32_encode(hrp: Str, data: &Vec[Int], variant: Int) -> Result[Str, Str] {
  if variant != BECH32_VARIANT_BECH32 && variant != BECH32_VARIANT_BECH32M {
    return _err_str("bech32: bad variant");
  }
  let hl = hrp.len();
  if hl < 1 || hl > _BECH32_MAX_HRP {
    return _err_str("bech32: invalid hrp length");
  }
  var i = 0;
  while i < hl {
    let b = (string.byte_at(hrp, i) as Int) & 0xFF;
    if b < 33 || b > 126 {
      return _err_str("bech32: invalid hrp character");
    }
    if b >= 65 && b <= 90 {
      return _err_str("bech32: mixed case");
    }
    i = i + 1;
  }
  let n = data.len();
  i = 0;
  while i < n {
    let v: Int = data[i];
    if v < 0 || v > _BECH32_MAX_SYMBOL {
      return _err_str("bech32: invalid data value");
    }
    i = i + 1;
  }
  if hl + n + 7 > _BECH32_MAX_LEN {
    return _err_str("bech32: bad length");
  }
  var constant = _BECH32_CONST_BECH32;
  if variant == BECH32_VARIANT_BECH32M {
    constant = _BECH32_CONST_BECH32M;
  }
  let cset = bech32_charset();
  var out = Vec[UInt8].new();
  i = 0;
  while i < hl {
    out.push(string.byte_at(hrp, i));
    i = i + 1;
  }
  out.push(49u8);
  let cs = _bech32_create_checksum(hrp, data, constant);
  i = 0;
  while i < n {
    out.push(string.byte_at(cset, data[i]));
    i = i + 1;
  }
  i = 0;
  while i < 6 {
    out.push(string.byte_at(cset, cs[i]));
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Decoding
// --------------------------------------------------

// Shared decoder. `want` is a BECH32_VARIANT_* value to require that exact
// checksum constant, or -1 to accept either constant and report the one
// that verified. Both paths share the full validation order documented on
// bech32_decode.
fn _bech32_parse(s: Str, want: Int) -> Result[Bech32, Str] {
  let n = s.len();
  if n < 8 || n > _BECH32_MAX_LEN {
    return _err_bech32("bech32: bad length");
  }
  var has_lower = false;
  var has_upper = false;
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b >= 97 && b <= 122 { has_lower = true; }
    if b >= 65 && b <= 90 { has_upper = true; }
    i = i + 1;
  }
  if has_lower && has_upper {
    return _err_bech32("bech32: mixed case");
  }
  var pos = -1;
  i = n - 1;
  while i >= 0 {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 49 {
      pos = i;
      break;
    }
    i = i - 1;
  }
  if pos < 1 {
    return _err_bech32("bech32: missing separator");
  }
  if n - pos - 1 < 6 {
    return _err_bech32("bech32: bad length");
  }
  var hrp_bytes = Vec[UInt8].new();
  i = 0;
  while i < pos {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 33 || b > 126 {
      return _err_bech32("bech32: invalid hrp character");
    }
    if b >= 65 && b <= 90 {
      hrp_bytes.push((b + 32) as UInt8);
    } else {
      hrp_bytes.push(b as UInt8);
    }
    i = i + 1;
  }
  let hrp = builder.sb_to_str(&hrp_bytes);
  var values = Vec[Int].new();
  i = pos + 1;
  while i < n {
    var b = (string.byte_at(s, i) as Int) & 0xFF;
    if b >= 65 && b <= 90 {
      b = b + 32;
    }
    let v = _bech32_value(b);
    if v < 0 {
      return _err_bech32("bech32: invalid data character");
    }
    values.push(v);
    i = i + 1;
  }
  var all = _bech32_expand(hrp);
  i = 0;
  while i < values.len() {
    all.push(values[i]);
    i = i + 1;
  }
  let pm = _bech32_polymod(&all);
  var variant = -1;
  if pm == _BECH32_CONST_BECH32 {
    variant = BECH32_VARIANT_BECH32;
  } elif pm == _BECH32_CONST_BECH32M {
    variant = BECH32_VARIANT_BECH32M;
  }
  if variant < 0 {
    return _err_bech32("bech32: bad checksum");
  }
  if want >= 0 && variant != want {
    return _err_bech32("bech32: wrong variant");
  }
  var payload = Vec[Int].new();
  let plen = values.len() - 6;
  i = 0;
  while i < plen {
    payload.push(values[i]);
    i = i + 1;
  }
  let out = Bech32{ hrp: hrp; variant: variant; data: payload };
  return _ok_bech32(out);
}

/// Decode Bech32 or Bech32m text, detecting the variant from the checksum.
/// Params: s - the candidate string.
/// Returns: Ok(Bech32) for a valid string; the variant is the unique
/// constant that verifies (BIP-350: no string is valid under both), `hrp`
/// is lowercase (an all-uppercase input is folded), and `data` holds the
/// 5-bit data symbols with the 6 checksum symbols removed (possibly empty).
/// Validation order: total length (8..90), mixed case, separator (the last
/// '1', not at position 0), data part of at least 6 characters, HRP bytes,
/// data alphabet, checksum. See SPEC.md section 7 for the exact catalog.
/// Error case: Err("bech32: bad length") for fewer than 8 or more than 90
/// characters, or a data part shorter than 6;
/// Err("bech32: mixed case") when the string mixes uppercase and lowercase;
/// Err("bech32: missing separator") when there is no '1' or it is the first
/// character (empty HRP); Err("bech32: invalid hrp character") for an HRP
/// byte outside [33,126]; Err("bech32: invalid data character") for a
/// non-alphabet data byte; Err("bech32: bad checksum") when neither
/// constant verifies.
/// Complexity: O(s.len()).
pub fn bech32_decode(s: Str) -> Result[Bech32, Str] {
  return _bech32_parse(s, -1);
}

/// Decode text and require a specific checksum variant.
/// Params: s - the candidate string; variant - BECH32_VARIANT_BECH32 or
/// BECH32_VARIANT_BECH32M.
/// Returns: Ok(Bech32) when the string is valid under exactly that
/// constant, with the same fields and validation order as bech32_decode.
/// Error case: everything bech32_decode reports, except that a string valid
/// only under the other constant yields Err("bech32: wrong variant")
/// instead of being accepted. "bech32: bad variant" is reported when the
/// requested variant is neither 0 nor 1.
/// Complexity: O(s.len()).
pub fn bech32_decode_variant(s: Str, variant: Int) -> Result[Bech32, Str] {
  if variant != BECH32_VARIANT_BECH32 && variant != BECH32_VARIANT_BECH32M {
    return _err_bech32("bech32: bad variant");
  }
  return _bech32_parse(s, variant);
}

/// True when bech32_decode accepts `s`.
/// Params: s - the candidate string.
/// Returns: true iff bech32_decode(s) is Ok (either variant), false for
/// every error class; uppercase-only strings are accepted, mixed case is
/// not.
/// Error case: none (errors collapse to false).
/// Complexity: O(s.len()).
pub fn bech32_is_valid(s: Str) -> Bool {
  let r = bech32_decode(s);
  if r.is_ok {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Human-readable part of a decoded string, canonically lowercase.
/// Params: v - a decoded value.
/// Returns: the (folded) HRP.
/// Error case: none.
/// Complexity: O(1).
pub fn bech32_hrp(v: &Bech32) -> Str {
  return v.hrp;
}

/// Variant of a decoded string.
/// Params: v - a decoded value.
/// Returns: BECH32_VARIANT_BECH32 (0) or BECH32_VARIANT_BECH32M (1).
/// Error case: none.
/// Complexity: O(1).
pub fn bech32_variant(v: &Bech32) -> Int {
  return v.variant;
}

/// Payload of a decoded string: the 5-bit data symbols, checksum removed.
/// Params: v - a decoded value.
/// Returns: a Vec[Int] of values in 0..31; may be empty.
/// Error case: none.
/// Complexity: O(1) (the vector is a handle copy).
pub fn bech32_data(v: &Bech32) -> Vec[Int] {
  let d = v.data;
  return d;
}

// --------------------------------------------------
//  convertbits
// --------------------------------------------------

/// BIP-173 `convertbits`: regroup `data` from `frombits`-wide units into
/// `tobits`-wide units, most significant bit first.
/// Params: data - input units, each a value in 0..2^frombits-1; frombits /
/// tobits - 1..8; pad - when true a partial trailing group is zero-padded
/// and emitted as one more output unit, when false it must be an acceptable
/// zero padding (fewer than `frombits` bits, all zero) or the input is
/// rejected.
/// Returns: Ok(units). The canonical uses are bytes -> 5-bit symbols with
/// pad=true (8->5, e.g. 6 bytes become 10 symbols with the last 2 bits
/// zero) and 5-bit symbols -> bytes with pad=false (5->8, strict, for
/// decoding payload data).
/// Error case: Err("bech32: invalid bits") when frombits or tobits is
/// outside 1..8; Err("bech32: convertbits overflow") when an input value is
/// negative or greater than 2^frombits-1; Err("bech32: invalid padding")
/// when pad=false and the trailing group has at least `frombits` bits left
/// or its bits are not all zero.
/// Complexity: O(data.len()).
pub fn bech32_convertbits(data: &Vec[Int], frombits: Int, tobits: Int, pad: Bool) -> Result[Vec[Int], Str] {
  if frombits < 1 || frombits > 8 {
    return _err_ints("bech32: invalid bits");
  }
  if tobits < 1 || tobits > 8 {
    return _err_ints("bech32: invalid bits");
  }
  let fpow = _pow2(frombits);
  let tpow = _pow2(tobits);
  let accmask = _pow2(frombits + tobits - 1);
  var out = Vec[Int].new();
  var acc = 0;
  var bits = 0;
  var i = 0;
  while i < data.len() {
    let value: Int = data[i];
    if value < 0 || value >= fpow {
      return _err_ints("bech32: convertbits overflow");
    }
    acc = (acc * fpow + value) % accmask;
    bits = bits + frombits;
    while bits >= tobits {
      bits = bits - tobits;
      out.push((acc / _pow2(bits)) % tpow);
    }
    i = i + 1;
  }
  if pad {
    if bits > 0 {
      out.push((acc * _pow2(tobits - bits)) % tpow);
    }
  } else {
    if bits >= frombits {
      return _err_ints("bech32: invalid padding");
    }
    if (acc * _pow2(tobits - bits)) % tpow != 0 {
      return _err_ints("bech32: invalid padding");
    }
  }
  return _ok_ints(out);
}

/// Convert 8-bit bytes to 5-bit Bech32 symbols (convertbits 8->5, pad=true).
/// Params: data - the bytes.
/// Returns: the 5-bit symbols, most significant bit first; a partial
/// trailing group is zero-padded. Total: every byte is in 0..255 and padding
/// is always permitted, so this cannot fail; empty input yields empty
/// output.
/// Error case: none.
/// Complexity: O(data.len()).
pub fn bech32_bytes_to_symbols(data: &Vec[UInt8]) -> Vec[Int] {
  var ints = Vec[Int].new();
  var i = 0;
  while i < data.len() {
    ints.push((data[i] as Int) & 0xFF);
    i = i + 1;
  }
  let conv = bech32_convertbits(&ints, 8, 5, true);
  if !conv.is_ok {
    // Unreachable: byte values are < 2^8 and pad=true cannot fail.
    return Vec[Int].new();
  }
  let vals = conv.value;
  return vals;
}

/// Convert 5-bit Bech32 symbols to bytes (convertbits 5->8, pad=false,
/// strict).
/// Params: data - 5-bit values (0..31).
/// Returns: Ok(bytes) with the trailing group required to be at most 4
/// zero bits; empty input yields Ok(empty).
/// Error case: Err("bech32: convertbits overflow") when a symbol is
/// negative or greater than 31; Err("bech32: invalid padding") when the
/// trailing bits do not form a valid zero padding (at least 5 bits left, or
/// non-zero leftovers).
/// Complexity: O(data.len()).
pub fn bech32_symbols_to_bytes(data: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  let conv = bech32_convertbits(data, 5, 8, false);
  if !conv.is_ok {
    return _err_bytes(conv.error);
  }
  let vals = conv.value;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vals.len() {
    let b: Int = vals[i];
    out.push((b & 0xFF) as UInt8);
    i = i + 1;
  }
  return _ok_bytes(out);
}
