// XIOM -- xiom.zkp: zero-knowledge proof serialization structures (BLS12-381)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, nothing beyond xiom.std) byte-level codec for the proof
// blobs of the two dominant BLS12-381 proof systems, Groth16 and PLONK:
//   * field elements: Fp as 48-byte big-endian with the BLS12-381 modulus
//     embedded; canonicality is a bytewise compare against the modulus, so a
//     48-byte value >= p is rejected. Helpers reverse the 48 bytes for the
//     little-endian variants used by arkworks-style toolchains; Fp2 is
//     c0 || c1.
//   * points: G1 compressed (48 bytes), G1 uncompressed (96), G2 compressed
//     (96), G2 uncompressed (192). The top byte of a compressed point carries
//     the compression (0x80), infinity (0x40) and sort/sign (0x20) flags,
//     extracted with divisor/modulo arithmetic (no shifts). Infinity requires
//     the flag plus a zero x field and rejects the sign flag; uncompressed
//     forms must have the flags cleared and encode infinity as all zeros.
//   * Groth16: proof A || B || C = 192 bytes; verification key
//     alpha || beta || gamma || delta || IC with the IC count supplied by the
//     caller (context), not by a count prefix.
//   * PLONK (snarkjs-shaped binary profile): proof = 9 compressed G1 points
//     (A, B, C, Z, T1, T2, T3, W1, W2) || 3 evaluations (a, b, c) = 528
//     bytes; verification key = n8 (4-byte little-endian u32) || omega || k1
//     || k2 (48-byte Fp slots) || X_2 (96-byte compressed G2) || 7 compressed
//     G1 points = 580 bytes. See SPEC.md for the exact profile.
//   * structural helpers: expected length per scheme, total length
//     validation, per-point flag consistency, scheme detection by length, and
//     point summary strings (compression/infinity/sign).
//
// Hard scope limits: no curve arithmetic, no subgroup checks, no pairings, no
// hashing and no proof verification. A blob accepted here is only
// structurally well-formed: canonical field coordinates and flag rules hold,
// but nothing checks that a point is on the curve, in the right subgroup, or
// that the proof is valid for anything.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[fn] dispatch, no
//     `match` in the library;
//   * Ok/Err are constructed only in the tiny leaf helpers below;
//   * every UInt8 read is widened and masked: (x as Int) & 0xFF;
//   * no bitwise shifts: flags are extracted with division and modulo by
//     128/64/32 and the top byte is cleared with `% 32`;
//   * 48-byte big-number comparisons are bytewise, most significant byte
//     first, and return -1/0/1;
//   * Vec[UInt8] struct fields are read element-wise (never moved out), so no
//     accessor hands `&struct.field` to a `&Vec[UInt8]` parameter (trap 4);
//   * every Result-returning public function documents its Err cases and the
//     messages carry byte offsets.

module xiom.zkp

use xiom.string;
use xiom.convert;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Fp element length in bytes (BLS12-381 base field, big-endian).
pub const ZKP_FP_LEN: Int = 48;

/// Fp2 element length in bytes (c0 || c1).
pub const ZKP_FP2_LEN: Int = 96;

/// Compressed G1 point length in bytes.
pub const ZKP_G1_COMPRESSED_LEN: Int = 48;

/// Uncompressed G1 point length in bytes (x || y).
pub const ZKP_G1_UNCOMPRESSED_LEN: Int = 96;

/// Compressed G2 point length in bytes (x = c0 || c1, flags in byte 0).
pub const ZKP_G2_COMPRESSED_LEN: Int = 96;

/// Uncompressed G2 point length in bytes (x || y, 96 bytes each).
pub const ZKP_G2_UNCOMPRESSED_LEN: Int = 192;

/// Groth16 proof length in bytes: A (G1) || B (G2) || C (G1).
pub const ZKP_GROTH16_PROOF_LEN: Int = 192;

/// Fixed part of a Groth16 verification key in bytes:
/// alpha || beta || gamma || delta.
pub const ZKP_GROTH16_VK_FIXED_LEN: Int = 336;

/// PLONK proof length in bytes: 9 compressed G1 points plus 3 evaluations.
pub const ZKP_PLONK_PROOF_LEN: Int = 528;

/// Number of compressed G1 points in a PLONK proof.
pub const ZKP_PLONK_G1_COUNT: Int = 9;

/// PLONK evaluation length in bytes (Fr, 32-byte big-endian).
pub const ZKP_PLONK_EVAL_LEN: Int = 32;

/// Number of Fr evaluations in a PLONK proof.
pub const ZKP_PLONK_EVAL_COUNT: Int = 3;

/// PLONK verification key length in bytes (this package's binary profile).
pub const ZKP_PLONK_VK_LEN: Int = 580;

/// Number of compressed G1 points in the PLONK verification key.
pub const ZKP_PLONK_VK_G1_COUNT: Int = 7;

// Point kind tags, used with zkp_point_length and the point helpers.
pub const ZKP_POINT_G1_COMPRESSED: Int = 0;
pub const ZKP_POINT_G1_UNCOMPRESSED: Int = 1;
pub const ZKP_POINT_G2_COMPRESSED: Int = 2;
pub const ZKP_POINT_G2_UNCOMPRESSED: Int = 3;

// Scheme tags, returned by zkp_scheme_detect.
pub const ZKP_SCHEME_UNKNOWN: Int = 0;
pub const ZKP_SCHEME_GROTH16: Int = 1;
pub const ZKP_SCHEME_PLONK: Int = 2;

// Flag bit values in the top byte of a compressed point.
pub const ZKP_FLAG_COMPRESSION: Int = 128;
pub const ZKP_FLAG_INFINITY: Int = 64;
pub const ZKP_FLAG_SIGN: Int = 32;

// --------------------------------------------------
//  Decoded structures
// --------------------------------------------------

/// A decoded Groth16 proof: each field is a copy of one compressed point
/// encoding (a and c are 48-byte compressed G1, b is 96-byte compressed G2).
/// Fields are implementation details; use the accessors.
pub type Groth16Proof = {
  a: Vec[UInt8];
  b: Vec[UInt8];
  c: Vec[UInt8];
}

/// A decoded Groth16 verification key. `ic` is a flat buffer of
/// `ic_count * 48` bytes: IC point i occupies bytes [i * 48, (i + 1) * 48).
/// Fields are implementation details; use the accessors.
pub type Groth16Vk = {
  alpha: Vec[UInt8];
  beta: Vec[UInt8];
  gamma: Vec[UInt8];
  delta: Vec[UInt8];
  ic_count: Int;
  ic: Vec[UInt8];
}

/// A decoded PLONK proof. `points` is a flat buffer of 9 compressed G1
/// encodings (432 bytes); `evals` is a flat buffer of 3 evaluations (96
/// bytes, 32 each). Fields are implementation details; use the accessors.
pub type PlonkProof = {
  points: Vec[UInt8];
  evals: Vec[UInt8];
}

/// A decoded PLONK verification key in this package's binary profile.
/// `points` is a flat buffer of 7 compressed G1 encodings (336 bytes).
/// Fields are implementation details; use the accessors.
pub type PlonkVk = {
  n8: Int;
  omega: Vec[UInt8];
  k1: Vec[UInt8];
  k2: Vec[UInt8];
  x2: Vec[UInt8];
  points: Vec[UInt8];
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

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
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

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Groth16Proof, Str].
fn _ok_g16p(v: Groth16Proof) -> Result[Groth16Proof, Str] {
  return Ok(v);
}

// Err(m) for Result[Groth16Proof, Str].
fn _err_g16p(m: Str) -> Result[Groth16Proof, Str] {
  return Err(m);
}

// Ok(v) for Result[Groth16Vk, Str].
fn _ok_g16vk(v: Groth16Vk) -> Result[Groth16Vk, Str] {
  return Ok(v);
}

// Err(m) for Result[Groth16Vk, Str].
fn _err_g16vk(m: Str) -> Result[Groth16Vk, Str] {
  return Err(m);
}

// Ok(v) for Result[PlonkProof, Str].
fn _ok_plonkp(v: PlonkProof) -> Result[PlonkProof, Str] {
  return Ok(v);
}

// Err(m) for Result[PlonkProof, Str].
fn _err_plonkp(m: Str) -> Result[PlonkProof, Str] {
  return Err(m);
}

// Ok(v) for Result[PlonkVk, Str].
fn _ok_plonkvk(v: PlonkVk) -> Result[PlonkVk, Str] {
  return Ok(v);
}

// Err(m) for Result[PlonkVk, Str].
fn _err_plonkvk(m: Str) -> Result[PlonkVk, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Byte at `pos` of a byte vector widened to an Int (0..255); callers
// guarantee the bounds.
fn _vb(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Bytes available at `offset` in a buffer of `n` bytes; 0 when the offset is
// negative or at/past the end.
fn _avail(n: Int, offset: Int) -> Int {
  if offset < 0 {
    return 0;
  }
  if offset >= n {
    return 0;
  }
  return n - offset;
}

// Copy `len` bytes at `off` into a fresh vector. Caller guarantees the range.
fn _copy_range(data: &Vec[UInt8], off: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    out.push(data[off + i]);
    i = i + 1;
  }
  return out;
}

// True when the `len` bytes at `off` are all zero. Caller guarantees the
// range.
fn _all_zero(data: &Vec[UInt8], off: Int, len: Int) -> Bool {
  var i = 0;
  while i < len {
    if _vb(data, off + i) != 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `a` and `b` are byte-for-byte equal.
fn _bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if _vb(a, i) != _vb(b, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  BLS12-381 modulus and Fp canonicality
// --------------------------------------------------

/// The BLS12-381 base field modulus p as 48 big-endian bytes:
/// 0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab.
///
/// Error case: none. Complexity: O(48).
pub fn zkp_bls12_381_modulus() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(26 as UInt8);   // 0x1a
  out.push(1 as UInt8);    // 0x01
  out.push(17 as UInt8);   // 0x11
  out.push(234 as UInt8);  // 0xea
  out.push(57 as UInt8);   // 0x39
  out.push(127 as UInt8);  // 0x7f
  out.push(230 as UInt8);  // 0xe6
  out.push(154 as UInt8);  // 0x9a
  out.push(75 as UInt8);   // 0x4b
  out.push(27 as UInt8);   // 0x1b
  out.push(167 as UInt8);  // 0xa7
  out.push(182 as UInt8);  // 0xb6
  out.push(67 as UInt8);   // 0x43
  out.push(75 as UInt8);   // 0x4b
  out.push(172 as UInt8);  // 0xac
  out.push(215 as UInt8);  // 0xd7
  out.push(100 as UInt8);  // 0x64
  out.push(119 as UInt8);  // 0x77
  out.push(75 as UInt8);   // 0x4b
  out.push(132 as UInt8);  // 0x84
  out.push(243 as UInt8);  // 0xf3
  out.push(133 as UInt8);  // 0x85
  out.push(18 as UInt8);   // 0x12
  out.push(191 as UInt8);  // 0xbf
  out.push(103 as UInt8);  // 0x67
  out.push(48 as UInt8);   // 0x30
  out.push(210 as UInt8);  // 0xd2
  out.push(160 as UInt8);  // 0xa0
  out.push(246 as UInt8);  // 0xf6
  out.push(176 as UInt8);  // 0xb0
  out.push(246 as UInt8);  // 0xf6
  out.push(36 as UInt8);   // 0x24
  out.push(30 as UInt8);   // 0x1e
  out.push(171 as UInt8);  // 0xab
  out.push(255 as UInt8);  // 0xff
  out.push(254 as UInt8);  // 0xfe
  out.push(177 as UInt8);  // 0xb1
  out.push(83 as UInt8);   // 0x53
  out.push(255 as UInt8);  // 0xff
  out.push(255 as UInt8);  // 0xff
  out.push(185 as UInt8);  // 0xb9
  out.push(254 as UInt8);  // 0xfe
  out.push(255 as UInt8);  // 0xff
  out.push(255 as UInt8);  // 0xff
  out.push(255 as UInt8);  // 0xff
  out.push(255 as UInt8);  // 0xff
  out.push(170 as UInt8);  // 0xaa
  out.push(171 as UInt8);  // 0xab
  return out;
}

/// Fp element length accessor: 48.
/// Error case: none. Complexity: O(1).
pub fn zkp_fp_len() -> Int {
  return ZKP_FP_LEN;
}

// Compare the 48 bytes at `off` (optionally with the first byte replaced by
// `first`, used to strip the compressed-point flag bits) against the modulus.
// Returns -1 when below p, 0 when exactly p, 1 when above p. Caller
// guarantees the range.
fn _cmp_modulus_first_masked(data: &Vec[UInt8], off: Int, first: Int) -> Int {
  let m = zkp_bls12_381_modulus();
  let mf = _vb(&m, 0);
  if first < mf {
    return -1;
  }
  if first > mf {
    return 1;
  }
  var i = 1;
  while i < ZKP_FP_LEN {
    let a = _vb(data, off + i);
    let b = _vb(&m, i);
    if a < b {
      return -1;
    }
    if a > b {
      return 1;
    }
    i = i + 1;
  }
  return 0;
}

// Bytewise compare of the 48 bytes at `off` against the modulus. Caller
// guarantees the range.
fn _cmp_modulus(data: &Vec[UInt8], off: Int) -> Int {
  return _cmp_modulus_first_masked(data, off, _vb(data, off));
}

/// Bytewise comparison of the 48-byte big-endian value at `offset` against
/// the BLS12-381 modulus p. Bytes are compared most significant first, so no
/// big-number arithmetic is involved.
///
/// Params: data - the buffer; offset - start of the element.
/// Returns: Ok(-1) when the value is below p (canonical), Ok(0) when it is
/// exactly p, Ok(1) when it is above p.
/// Error case: Err("zkp: fp needs 48 bytes at offset O, have H") when fewer
/// than 48 bytes are available at O (H is the number of bytes there).
/// Complexity: O(48).
pub fn zkp_fp_compare_modulus(data: &Vec[UInt8], offset: Int) -> Result[Int, Str] {
  let n = data.len();
  if offset < 0 || offset + ZKP_FP_LEN > n {
    return _err_int("zkp: fp needs 48 bytes at offset " + convert.int_to_string(offset) + ", have " + convert.int_to_string(_avail(n, offset)));
  }
  return _ok_int(_cmp_modulus(data, offset));
}

/// Whether the 48 bytes at `offset` form a canonical Fp element: a value
/// strictly below the BLS12-381 modulus p.
///
/// Params: data - the buffer; offset - start of the element.
/// Returns: Ok(true) when the value is < p; Ok(false) when the 48 bytes are
/// present but the value is >= p (including exactly p).
/// Error case: Err("zkp: fp needs 48 bytes at offset O, have H") when fewer
/// than 48 bytes are available.
/// Complexity: O(48).
pub fn zkp_fp_validate(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str] {
  let c = zkp_fp_compare_modulus(data, offset);
  if !c.is_ok {
    let e: Str = c.error;
    return _err_bool(e);
  }
  let cmp: Int = c.value;
  return _ok_bool(cmp < 0);
}

/// Whether the 48 bytes at `offset` are exactly the BLS12-381 modulus p.
/// Useful for boundary checks around the canonical range.
///
/// Params: data - the buffer; offset - start of the element.
/// Returns: Ok(true) when the value equals p; Ok(false) otherwise.
/// Error case: Err("zkp: fp needs 48 bytes at offset O, have H") when fewer
/// than 48 bytes are available.
/// Complexity: O(48).
pub fn zkp_fp_is_modulus(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str] {
  let c = zkp_fp_compare_modulus(data, offset);
  if !c.is_ok {
    let e: Str = c.error;
    return _err_bool(e);
  }
  let cmp: Int = c.value;
  return _ok_bool(cmp == 0);
}

/// Whether the 96 bytes at `offset` form a canonical Fp2 element
/// (c0 || c1 with both limbs < p).
///
/// Params: data - the buffer; offset - start of the element.
/// Returns: Ok(true) when both limbs are canonical; Ok(false) when the 96
/// bytes are present but at least one limb is >= p.
/// Error case: Err("zkp: fp2 needs 96 bytes at offset O, have H") when fewer
/// than 96 bytes are available.
/// Complexity: O(96).
pub fn zkp_fp2_validate(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str] {
  let n = data.len();
  if offset < 0 || offset + ZKP_FP2_LEN > n {
    return _err_bool("zkp: fp2 needs 96 bytes at offset " + convert.int_to_string(offset) + ", have " + convert.int_to_string(_avail(n, offset)));
  }
  let c0 = zkp_fp_validate(data, offset);
  if !c0.is_ok {
    let e: Str = c0.error;
    return _err_bool(e);
  }
  let c1 = zkp_fp_validate(data, offset + ZKP_FP_LEN);
  if !c1.is_ok {
    let e: Str = c1.error;
    return _err_bool(e);
  }
  let ok0: Bool = c0.value;
  let ok1: Bool = c1.value;
  return _ok_bool(ok0 && ok1);
}

// Reverse the bytes of a flat buffer (copy; never in place).
fn _reverse_bytes(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = v.len();
  var i = 0;
  while i < n {
    out.push(v[n - 1 - i]);
    i = i + 1;
  }
  return out;
}

/// Convert one 48-byte big-endian Fp element to the little-endian layout used
/// by arkworks-style serializers. The conversion is a pure byte reversal: the
/// value (the 384-bit integer mod p) does not change.
///
/// Params: be - exactly 48 bytes, big-endian.
/// Returns: Ok(48 bytes, little-endian).
/// Error case: Err("zkp: fp endian conversion needs 48 bytes, have N") when
/// `be` is not 48 bytes long.
/// Complexity: O(48).
pub fn zkp_fp_be_to_le(be: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let n = be.len();
  if n != ZKP_FP_LEN {
    return _err_bytes("zkp: fp endian conversion needs 48 bytes, have " + convert.int_to_string(n));
  }
  return _ok_bytes(_reverse_bytes(be));
}

/// Convert one 48-byte little-endian Fp element to the big-endian layout used
/// by this package. Byte reversal is its own inverse, so this calls the same
/// primitive as zkp_fp_be_to_le; both directions are provided for readable
/// call sites.
///
/// Params: le - exactly 48 bytes, little-endian.
/// Returns: Ok(48 bytes, big-endian).
/// Error case: Err("zkp: fp endian conversion needs 48 bytes, have N") when
/// `le` is not 48 bytes long.
/// Complexity: O(48).
pub fn zkp_fp_le_to_be(le: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let n = le.len();
  if n != ZKP_FP_LEN {
    return _err_bytes("zkp: fp endian conversion needs 48 bytes, have " + convert.int_to_string(n));
  }
  return _ok_bytes(_reverse_bytes(le));
}

/// Convert a 96-byte Fp2 element (c0 || c1, both big-endian) to the
/// little-endian variant: each limb is reversed in place, the limb order
/// (c0 first) is not changed.
///
/// Params: be - exactly 96 bytes, big-endian.
/// Returns: Ok(96 bytes): reverse(c0) || reverse(c1).
/// Error case: Err("zkp: fp2 endian conversion needs 96 bytes, have N") when
/// `be` is not 96 bytes long.
/// Complexity: O(96).
pub fn zkp_fp2_be_to_le(be: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let n = be.len();
  if n != ZKP_FP2_LEN {
    return _err_bytes("zkp: fp2 endian conversion needs 96 bytes, have " + convert.int_to_string(n));
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < ZKP_FP_LEN {
    out.push(be[ZKP_FP_LEN - 1 - i]);
    i = i + 1;
  }
  i = 0;
  while i < ZKP_FP_LEN {
    out.push(be[ZKP_FP2_LEN - 1 - i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Point flags, lengths and summaries
// --------------------------------------------------

// The three flag bits of a compressed point's top byte, extracted with
// division/modulo only. `b0` is a widened byte (0..255).
fn _flag_compression(b0: Int) -> Int {
  return b0 / ZKP_FLAG_COMPRESSION;
}

fn _flag_infinity(b0: Int) -> Int {
  return (b0 / ZKP_FLAG_INFINITY) % 2;
}

fn _flag_sign(b0: Int) -> Int {
  return (b0 / ZKP_FLAG_SIGN) % 2;
}

/// Encoded length in bytes of a point kind:
/// G1 compressed 48, G1 uncompressed 96, G2 compressed 96, G2 uncompressed
/// 192.
///
/// Params: kind - one of the ZKP_POINT_* tags.
/// Returns: the length, or -1 when `kind` is not a known tag.
/// Error case: none. Complexity: O(1).
pub fn zkp_point_length(kind: Int) -> Int {
  if kind == ZKP_POINT_G1_COMPRESSED {
    return ZKP_G1_COMPRESSED_LEN;
  }
  if kind == ZKP_POINT_G1_UNCOMPRESSED {
    return ZKP_G1_UNCOMPRESSED_LEN;
  }
  if kind == ZKP_POINT_G2_COMPRESSED {
    return ZKP_G2_COMPRESSED_LEN;
  }
  if kind == ZKP_POINT_G2_UNCOMPRESSED {
    return ZKP_G2_UNCOMPRESSED_LEN;
  }
  return -1;
}

/// Human name of a point kind ("G1 compressed", "G1 uncompressed",
/// "G2 compressed", "G2 uncompressed"), or "" for an unknown tag.
/// Error case: none. Complexity: O(1).
pub fn zkp_point_kind_name(kind: Int) -> Str {
  if kind == ZKP_POINT_G1_COMPRESSED {
    return "G1 compressed";
  }
  if kind == ZKP_POINT_G1_UNCOMPRESSED {
    return "G1 uncompressed";
  }
  if kind == ZKP_POINT_G2_COMPRESSED {
    return "G2 compressed";
  }
  if kind == ZKP_POINT_G2_UNCOMPRESSED {
    return "G2 uncompressed";
  }
  return "";
}

/// The raw flag bits of a point's top byte packed as compression * 4 +
/// infinity * 2 + sign. This reports the physical bits; whether they form a
/// legal encoding is decided by the validate functions.
///
/// Params: kind - a ZKP_POINT_* tag; data - the buffer; offset - start of the
/// point (the full point length must be available).
/// Returns: Ok(0..7).
/// Error case: Err("zkp: unknown point kind K") for an unknown tag;
/// Err("zkp: KIND needs N bytes at offset O, have H") when the point does not
/// fit.
/// Complexity: O(1).
pub fn zkp_point_flags(kind: Int, data: &Vec[UInt8], offset: Int) -> Result[Int, Str] {
  let need = zkp_point_length(kind);
  if need < 0 {
    return _err_int("zkp: unknown point kind " + convert.int_to_string(kind));
  }
  let n = data.len();
  if offset < 0 || offset + need > n {
    return _err_int("zkp: " + zkp_point_kind_name(kind) + " needs " + convert.int_to_string(need) + " bytes at offset " + convert.int_to_string(offset) + ", have " + convert.int_to_string(_avail(n, offset)));
  }
  let b0 = _vb(data, offset);
  return _ok_int(_flag_compression(b0) * 4 + _flag_infinity(b0) * 2 + _flag_sign(b0));
}

/// One-line structural summary of a point: its kind name followed by the
/// three flags, e.g. "G1 compressed compression=1 infinity=0 sign=1".
///
/// Params: kind - a ZKP_POINT_* tag; data - the buffer; offset - start of the
/// point.
/// Returns: Ok(summary string).
/// Error case: the same errors as zkp_point_flags (unknown kind, point does
/// not fit).
/// Complexity: O(1).
pub fn zkp_point_summary(kind: Int, data: &Vec[UInt8], offset: Int) -> Result[Str, Str] {
  let f = zkp_point_flags(kind, data, offset);
  if !f.is_ok {
    let e: Str = f.error;
    return _err_str(e);
  }
  let flags: Int = f.value;
  let comp = flags / 4;
  let inf = (flags / 2) % 2;
  let sign = flags % 2;
  return _ok_str(zkp_point_kind_name(kind) + " compression=" + convert.int_to_string(comp) + " infinity=" + convert.int_to_string(inf) + " sign=" + convert.int_to_string(sign));
}

// --------------------------------------------------
//  G1 compressed (48 bytes)
// --------------------------------------------------

/// Validate a 48-byte compressed G1 point encoding.
///
/// Rules: the compression flag (0x80) must be set; the x field (top byte
/// with its three flag bits cleared, then 47 bytes) must be < p; when the
/// infinity flag (0x40) is set the sign flag (0x20) must be clear and the x
/// field must be zero.
///
/// Params: data - the buffer; offset - start of the point.
/// Returns: Ok(true) for a legal encoding; Ok(false) for a structurally
/// complete point that violates a rule (flags or canonical x).
/// Error case: Err("zkp: g1 compressed needs 48 bytes at offset O, have H")
/// when the point does not fit.
/// Complexity: O(48). No curve or subgroup check.
pub fn zkp_g1_compressed_validate(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str] {
  let n = data.len();
  if offset < 0 || offset + ZKP_G1_COMPRESSED_LEN > n {
    return _err_bool("zkp: g1 compressed needs 48 bytes at offset " + convert.int_to_string(offset) + ", have " + convert.int_to_string(_avail(n, offset)));
  }
  let b0 = _vb(data, offset);
  if _flag_compression(b0) != 1 {
    return _ok_bool(false);
  }
  let inf = _flag_infinity(b0);
  let sign = _flag_sign(b0);
  let x_top = b0 % 32;
  if inf == 1 {
    if sign != 0 {
      return _ok_bool(false);
    }
    if x_top != 0 {
      return _ok_bool(false);
    }
    if !_all_zero(data, offset + 1, ZKP_FP_LEN - 1) {
      return _ok_bool(false);
    }
    return _ok_bool(true);
  }
  return _ok_bool(_cmp_modulus_first_masked(data, offset, x_top) < 0);
}

/// Validate a 96-byte uncompressed G1 point encoding (x || y, 48 bytes
/// each). The top three bits of byte 0 must be cleared; the all-zero buffer
/// is the infinity encoding; otherwise x and y must both be < p.
///
/// Params: data - the buffer; offset - start of the point.
/// Returns: Ok(true) for a legal encoding; Ok(false) otherwise.
/// Error case: Err("zkp: g1 uncompressed needs 96 bytes at offset O, have
/// H") when the point does not fit.
/// Complexity: O(96). No curve or subgroup check.
pub fn zkp_g1_uncompressed_validate(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str] {
  let n = data.len();
  if offset < 0 || offset + ZKP_G1_UNCOMPRESSED_LEN > n {
    return _err_bool("zkp: g1 uncompressed needs 96 bytes at offset " + convert.int_to_string(offset) + ", have " + convert.int_to_string(_avail(n, offset)));
  }
  let b0 = _vb(data, offset);
  if b0 / 32 != 0 {
    return _ok_bool(false);
  }
  if _all_zero(data, offset, ZKP_G1_UNCOMPRESSED_LEN) {
    return _ok_bool(true);
  }
  if _cmp_modulus_first_masked(data, offset, b0) >= 0 {
    return _ok_bool(false);
  }
  return _ok_bool(_cmp_modulus(data, offset + ZKP_FP_LEN) < 0);
}

// --------------------------------------------------
//  G2 compressed (96 bytes)
// --------------------------------------------------

/// Validate a 96-byte compressed G2 point encoding (x = c0 || c1, flags in
/// the top byte of c0).
///
/// Rules: the compression flag must be set; c0 (with flags cleared) and c1
/// must both be < p; when the infinity flag is set the sign flag must be
/// clear and both c0 and c1 must be zero.
///
/// Params: data - the buffer; offset - start of the point.
/// Returns: Ok(true) for a legal encoding; Ok(false) otherwise.
/// Error case: Err("zkp: g2 compressed needs 96 bytes at offset O, have H")
/// when the point does not fit.
/// Complexity: O(96). No curve or subgroup check.
pub fn zkp_g2_compressed_validate(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str] {
  let n = data.len();
  if offset < 0 || offset + ZKP_G2_COMPRESSED_LEN > n {
    return _err_bool("zkp: g2 compressed needs 96 bytes at offset " + convert.int_to_string(offset) + ", have " + convert.int_to_string(_avail(n, offset)));
  }
  let b0 = _vb(data, offset);
  if _flag_compression(b0) != 1 {
    return _ok_bool(false);
  }
  let inf = _flag_infinity(b0);
  let sign = _flag_sign(b0);
  let x_top = b0 % 32;
  if inf == 1 {
    if sign != 0 {
      return _ok_bool(false);
    }
    if x_top != 0 {
      return _ok_bool(false);
    }
    if !_all_zero(data, offset + 1, ZKP_FP_LEN - 1) {
      return _ok_bool(false);
    }
    if !_all_zero(data, offset + ZKP_FP_LEN, ZKP_FP_LEN) {
      return _ok_bool(false);
    }
    return _ok_bool(true);
  }
  if _cmp_modulus_first_masked(data, offset, x_top) >= 0 {
    return _ok_bool(false);
  }
  return _ok_bool(_cmp_modulus(data, offset + ZKP_FP_LEN) < 0);
}

/// Validate a 192-byte uncompressed G2 point encoding (x || y, each 96
/// bytes = c0 || c1). The top three bits of byte 0 must be cleared; the
/// all-zero buffer is the infinity encoding; otherwise all four limbs must
/// be < p.
///
/// Params: data - the buffer; offset - start of the point.
/// Returns: Ok(true) for a legal encoding; Ok(false) otherwise.
/// Error case: Err("zkp: g2 uncompressed needs 192 bytes at offset O, have
/// H") when the point does not fit.
/// Complexity: O(192). No curve or subgroup check.
pub fn zkp_g2_uncompressed_validate(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str] {
  let n = data.len();
  if offset < 0 || offset + ZKP_G2_UNCOMPRESSED_LEN > n {
    return _err_bool("zkp: g2 uncompressed needs 192 bytes at offset " + convert.int_to_string(offset) + ", have " + convert.int_to_string(_avail(n, offset)));
  }
  let b0 = _vb(data, offset);
  if b0 / 32 != 0 {
    return _ok_bool(false);
  }
  if _all_zero(data, offset, ZKP_G2_UNCOMPRESSED_LEN) {
    return _ok_bool(true);
  }
  if _cmp_modulus_first_masked(data, offset, b0) >= 0 {
    return _ok_bool(false);
  }
  if _cmp_modulus(data, offset + ZKP_FP_LEN) >= 0 {
    return _ok_bool(false);
  }
  if _cmp_modulus(data, offset + ZKP_FP2_LEN) >= 0 {
    return _ok_bool(false);
  }
  return _ok_bool(_cmp_modulus(data, offset + ZKP_FP_LEN + ZKP_FP2_LEN) < 0);
}

/// Validate a point of any kind (dispatch on the ZKP_POINT_* tag). See the
/// four kind-specific validators for the exact rules.
///
/// Params: kind - a ZKP_POINT_* tag; data - the buffer; offset - start of the
/// point.
/// Returns: Ok(true)/Ok(false) from the kind-specific validator.
/// Error case: Err("zkp: unknown point kind K") for an unknown tag; the
/// truncation Err of the kind otherwise.
/// Complexity: O(length of the point).
pub fn zkp_point_validate(kind: Int, data: &Vec[UInt8], offset: Int) -> Result[Bool, Str] {
  if kind == ZKP_POINT_G1_COMPRESSED {
    return zkp_g1_compressed_validate(data, offset);
  }
  if kind == ZKP_POINT_G1_UNCOMPRESSED {
    return zkp_g1_uncompressed_validate(data, offset);
  }
  if kind == ZKP_POINT_G2_COMPRESSED {
    return zkp_g2_compressed_validate(data, offset);
  }
  if kind == ZKP_POINT_G2_UNCOMPRESSED {
    return zkp_g2_uncompressed_validate(data, offset);
  }
  return _err_bool("zkp: unknown point kind " + convert.int_to_string(kind));
}

// True when the point of `kind` at `offset` validates; any structural
// problem (unknown kind, truncation, rule violation) is false. Used by the
// aggregate blob validators, which check total length separately.
fn _point_ok(kind: Int, data: &Vec[UInt8], offset: Int) -> Bool {
  let r = zkp_point_validate(kind, data, offset);
  if !r.is_ok {
    return false;
  }
  let v: Bool = r.value;
  return v;
}

// True when the Fp element at `offset` is canonical; truncation is false.
fn _fp_ok(data: &Vec[UInt8], offset: Int) -> Bool {
  let r = zkp_fp_validate(data, offset);
  if !r.is_ok {
    return false;
  }
  let v: Bool = r.value;
  return v;
}

// --------------------------------------------------
//  Groth16
// --------------------------------------------------

/// Groth16 proof length accessor: 192.
/// Error case: none. Complexity: O(1).
pub fn zkp_groth16_proof_len() -> Int {
  return ZKP_GROTH16_PROOF_LEN;
}

/// Length in bytes of a Groth16 verification key with `ic_count` IC points:
/// 336 + 48 * ic_count.
///
/// Params: ic_count - number of IC points.
/// Returns: the length, or -1 when `ic_count` is negative.
/// Error case: none. Complexity: O(1).
pub fn zkp_groth16_vk_len(ic_count: Int) -> Int {
  if ic_count < 0 {
    return -1;
  }
  return ZKP_GROTH16_VK_FIXED_LEN + ZKP_FP_LEN * ic_count;
}

/// Decode a 192-byte Groth16 proof into its three point encodings. Only the
/// total length is structural here; use zkp_groth16_proof_validate for the
/// flag/canonicality rules.
///
/// Params: data - exactly 192 bytes: A (48 compressed G1) || B (96
/// compressed G2) || C (48 compressed G1).
/// Returns: Ok(Groth16Proof) with copies of the three parts.
/// Error case: Err("zkp: groth16 proof needs 192 bytes at offset 0, have N")
/// when the buffer length is not exactly 192.
/// Complexity: O(192).
pub fn zkp_groth16_proof_decode(data: &Vec[UInt8]) -> Result[Groth16Proof, Str] {
  let n = data.len();
  if n != ZKP_GROTH16_PROOF_LEN {
    return _err_g16p("zkp: groth16 proof needs 192 bytes at offset 0, have " + convert.int_to_string(n));
  }
  var a = _copy_range(data, 0, ZKP_G1_COMPRESSED_LEN);
  var b = _copy_range(data, ZKP_G1_COMPRESSED_LEN, ZKP_G2_COMPRESSED_LEN);
  var c = _copy_range(data, ZKP_G1_COMPRESSED_LEN + ZKP_G2_COMPRESSED_LEN, ZKP_G1_COMPRESSED_LEN);
  return _ok_g16p(Groth16Proof{ a: a; b: b; c: c });
}

/// Validate a 192-byte Groth16 proof: exact length plus the compressed-point
/// flag/canonicality rules for A (G1), B (G2) and C (G1).
///
/// Params: data - the proof buffer.
/// Returns: Ok(true) when every point is structurally legal; Ok(false) when
/// the length is right but some point violates a rule.
/// Error case: Err("zkp: groth16 proof needs 192 bytes at offset 0, have N")
/// when the buffer length is not exactly 192.
/// Complexity: O(192). No curve or subgroup check.
pub fn zkp_groth16_proof_validate(data: &Vec[UInt8]) -> Result[Bool, Str] {
  let n = data.len();
  if n != ZKP_GROTH16_PROOF_LEN {
    return _err_bool("zkp: groth16 proof needs 192 bytes at offset 0, have " + convert.int_to_string(n));
  }
  let a_ok = _point_ok(ZKP_POINT_G1_COMPRESSED, data, 0);
  let b_ok = _point_ok(ZKP_POINT_G2_COMPRESSED, data, ZKP_G1_COMPRESSED_LEN);
  let c_ok = _point_ok(ZKP_POINT_G1_COMPRESSED, data, ZKP_G1_COMPRESSED_LEN + ZKP_G2_COMPRESSED_LEN);
  return _ok_bool(a_ok && b_ok && c_ok);
}

/// The A point of a decoded Groth16 proof (48-byte compressed G1 copy).
/// Error case: none. Complexity: O(48).
pub fn zkp_groth16_proof_a(p: &Groth16Proof) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < p.a.len() {
    out.push(p.a[i]);
    i = i + 1;
  }
  return out;
}

/// The B point of a decoded Groth16 proof (96-byte compressed G2 copy).
/// Error case: none. Complexity: O(96).
pub fn zkp_groth16_proof_b(p: &Groth16Proof) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < p.b.len() {
    out.push(p.b[i]);
    i = i + 1;
  }
  return out;
}

/// The C point of a decoded Groth16 proof (48-byte compressed G1 copy).
/// Error case: none. Complexity: O(48).
pub fn zkp_groth16_proof_c(p: &Groth16Proof) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < p.c.len() {
    out.push(p.c[i]);
    i = i + 1;
  }
  return out;
}

/// Decode a Groth16 verification key:
/// alpha (48 G1) || beta (96 G2) || gamma (96 G2) || delta (96 G2) ||
/// IC (48 * ic_count G1). The IC count is a caller-supplied context value;
/// this profile has no count prefix on the wire.
///
/// Params: data - exactly zkp_groth16_vk_len(ic_count) bytes; ic_count - the
/// number of IC points (>= 0).
/// Returns: Ok(Groth16Vk) with copies of the fixed part and the flat IC
/// buffer.
/// Error case: Err("zkp: groth16 vk ic count I is negative") for a negative
/// count; Err("zkp: groth16 vk with I ic points needs N bytes at offset 0,
/// have H") for a length mismatch.
/// Complexity: O(length).
pub fn zkp_groth16_vk_decode(data: &Vec[UInt8], ic_count: Int) -> Result[Groth16Vk, Str] {
  if ic_count < 0 {
    return _err_g16vk("zkp: groth16 vk ic count " + convert.int_to_string(ic_count) + " is negative");
  }
  let need = zkp_groth16_vk_len(ic_count);
  let n = data.len();
  if n != need {
    return _err_g16vk("zkp: groth16 vk with " + convert.int_to_string(ic_count) + " ic points needs " + convert.int_to_string(need) + " bytes at offset 0, have " + convert.int_to_string(n));
  }
  var alpha = _copy_range(data, 0, ZKP_G1_COMPRESSED_LEN);
  var beta = _copy_range(data, ZKP_G1_COMPRESSED_LEN, ZKP_G2_COMPRESSED_LEN);
  var gamma = _copy_range(data, ZKP_G1_COMPRESSED_LEN + ZKP_G2_COMPRESSED_LEN, ZKP_G2_COMPRESSED_LEN);
  var delta = _copy_range(data, ZKP_G1_COMPRESSED_LEN + ZKP_G2_COMPRESSED_LEN + ZKP_G2_COMPRESSED_LEN, ZKP_G2_COMPRESSED_LEN);
  var ic = Vec[UInt8].new();
  var i = 0;
  while i < ic_count {
    var k = 0;
    while k < ZKP_FP_LEN {
      ic.push(data[ZKP_GROTH16_VK_FIXED_LEN + i * ZKP_FP_LEN + k]);
      k = k + 1;
    }
    i = i + 1;
  }
  return _ok_g16vk(Groth16Vk{ alpha: alpha; beta: beta; gamma: gamma; delta: delta; ic_count: ic_count; ic: ic });
}

/// Validate a Groth16 verification key blob: exact length for `ic_count`
/// points, then the compressed-point rules for alpha, beta, gamma, delta and
/// every IC point.
///
/// Params: data - the key buffer; ic_count - the number of IC points.
/// Returns: Ok(true) when everything is structurally legal; Ok(false) when
/// the length is right but some point violates a rule.
/// Error case: the same Err cases as zkp_groth16_vk_decode.
/// Complexity: O(length). No curve or subgroup check.
pub fn zkp_groth16_vk_validate(data: &Vec[UInt8], ic_count: Int) -> Result[Bool, Str] {
  if ic_count < 0 {
    return _err_bool("zkp: groth16 vk ic count " + convert.int_to_string(ic_count) + " is negative");
  }
  let need = zkp_groth16_vk_len(ic_count);
  let n = data.len();
  if n != need {
    return _err_bool("zkp: groth16 vk with " + convert.int_to_string(ic_count) + " ic points needs " + convert.int_to_string(need) + " bytes at offset 0, have " + convert.int_to_string(n));
  }
  var ok = _point_ok(ZKP_POINT_G1_COMPRESSED, data, 0);
  if !_point_ok(ZKP_POINT_G2_COMPRESSED, data, ZKP_G1_COMPRESSED_LEN) {
    ok = false;
  }
  if !_point_ok(ZKP_POINT_G2_COMPRESSED, data, ZKP_G1_COMPRESSED_LEN + ZKP_G2_COMPRESSED_LEN) {
    ok = false;
  }
  if !_point_ok(ZKP_POINT_G2_COMPRESSED, data, ZKP_G1_COMPRESSED_LEN + ZKP_G2_COMPRESSED_LEN + ZKP_G2_COMPRESSED_LEN) {
    ok = false;
  }
  var i = 0;
  while i < ic_count {
    if !_point_ok(ZKP_POINT_G1_COMPRESSED, data, ZKP_GROTH16_VK_FIXED_LEN + i * ZKP_FP_LEN) {
      ok = false;
    }
    i = i + 1;
  }
  return _ok_bool(ok);
}

/// The alpha point of a Groth16 verification key (48-byte compressed G1
/// copy). Error case: none. Complexity: O(48).
pub fn zkp_groth16_vk_alpha(vk: &Groth16Vk) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vk.alpha.len() {
    out.push(vk.alpha[i]);
    i = i + 1;
  }
  return out;
}

/// The beta point of a Groth16 verification key (96-byte compressed G2
/// copy). Error case: none. Complexity: O(96).
pub fn zkp_groth16_vk_beta(vk: &Groth16Vk) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vk.beta.len() {
    out.push(vk.beta[i]);
    i = i + 1;
  }
  return out;
}

/// The gamma point of a Groth16 verification key (96-byte compressed G2
/// copy). Error case: none. Complexity: O(96).
pub fn zkp_groth16_vk_gamma(vk: &Groth16Vk) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vk.gamma.len() {
    out.push(vk.gamma[i]);
    i = i + 1;
  }
  return out;
}

/// The delta point of a Groth16 verification key (96-byte compressed G2
/// copy). Error case: none. Complexity: O(96).
pub fn zkp_groth16_vk_delta(vk: &Groth16Vk) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vk.delta.len() {
    out.push(vk.delta[i]);
    i = i + 1;
  }
  return out;
}

/// Number of IC points stored in a Groth16 verification key.
/// Error case: none. Complexity: O(1).
pub fn zkp_groth16_vk_ic_count(vk: &Groth16Vk) -> Int {
  return vk.ic_count;
}

/// IC point `i` of a Groth16 verification key (48-byte compressed G1 copy).
///
/// Params: vk - the key; i - 0..ic_count - 1.
/// Returns: Ok(48 bytes).
/// Error case: Err("zkp: groth16 vk ic index I out of range (count C)") when
/// i is outside 0..count - 1; Err("zkp: groth16 vk ic buffer is shortened")
/// when the flat buffer cannot hold that point.
/// Complexity: O(48).
pub fn zkp_groth16_vk_ic_point(vk: &Groth16Vk, i: Int) -> Result[Vec[UInt8], Str] {
  let count = vk.ic_count;
  if i < 0 || i >= count {
    return _err_bytes("zkp: groth16 vk ic index " + convert.int_to_string(i) + " out of range (count " + convert.int_to_string(count) + ")");
  }
  if (i + 1) * ZKP_FP_LEN > vk.ic.len() {
    return _err_bytes("zkp: groth16 vk ic buffer is shortened");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < ZKP_FP_LEN {
    out.push(vk.ic[i * ZKP_FP_LEN + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  PLONK (snarkjs-shaped binary profile)
// --------------------------------------------------

/// PLONK proof length accessor: 528.
/// Error case: none. Complexity: O(1).
pub fn zkp_plonk_proof_len() -> Int {
  return ZKP_PLONK_PROOF_LEN;
}

/// Name of PLONK proof point `i`: A, B, C, Z, T1, T2, T3, W1, W2 for
/// 0..8, "" beyond.
/// Error case: none. Complexity: O(1).
pub fn zkp_plonk_proof_point_name(i: Int) -> Str {
  if i == 0 {
    return "A";
  }
  if i == 1 {
    return "B";
  }
  if i == 2 {
    return "C";
  }
  if i == 3 {
    return "Z";
  }
  if i == 4 {
    return "T1";
  }
  if i == 5 {
    return "T2";
  }
  if i == 6 {
    return "T3";
  }
  if i == 7 {
    return "W1";
  }
  if i == 8 {
    return "W2";
  }
  return "";
}

/// Name of PLONK proof evaluation `i`: a, b, c for 0..2, "" beyond.
/// Error case: none. Complexity: O(1).
pub fn zkp_plonk_proof_eval_name(i: Int) -> Str {
  if i == 0 {
    return "a";
  }
  if i == 1 {
    return "b";
  }
  if i == 2 {
    return "c";
  }
  return "";
}

/// Decode a 528-byte PLONK proof into its 9 compressed G1 points and 3
/// evaluations. Only the total length is structural here; use
/// zkp_plonk_proof_validate for the point flag rules. Evaluations are kept
/// as opaque 32-byte big-endian Fr limbs (no Fr modulus is embedded).
///
/// Params: data - exactly 528 bytes: 9 compressed G1 points (432) then 3
/// evaluations of 32 bytes each (96).
/// Returns: Ok(PlonkProof) with flat copies.
/// Error case: Err("zkp: plonk proof needs 528 bytes at offset 0, have N")
/// when the buffer length is not exactly 528.
/// Complexity: O(528).
pub fn zkp_plonk_proof_decode(data: &Vec[UInt8]) -> Result[PlonkProof, Str] {
  let n = data.len();
  if n != ZKP_PLONK_PROOF_LEN {
    return _err_plonkp("zkp: plonk proof needs 528 bytes at offset 0, have " + convert.int_to_string(n));
  }
  var points = _copy_range(data, 0, ZKP_PLONK_G1_COUNT * ZKP_G1_COMPRESSED_LEN);
  var evals = _copy_range(data, ZKP_PLONK_G1_COUNT * ZKP_G1_COMPRESSED_LEN, ZKP_PLONK_EVAL_COUNT * ZKP_PLONK_EVAL_LEN);
  return _ok_plonkp(PlonkProof{ points: points; evals: evals });
}

/// Validate a 528-byte PLONK proof: exact length plus the compressed-G1
/// flag/canonicality rules for all 9 points. The 3 evaluations are opaque
/// 32-byte limbs (no Fr modulus is embedded), so they are not inspected.
///
/// Params: data - the proof buffer.
/// Returns: Ok(true) when every point is structurally legal; Ok(false) when
/// the length is right but some point violates a rule.
/// Error case: Err("zkp: plonk proof needs 528 bytes at offset 0, have N")
/// when the buffer length is not exactly 528.
/// Complexity: O(528). No curve or subgroup check.
pub fn zkp_plonk_proof_validate(data: &Vec[UInt8]) -> Result[Bool, Str] {
  let n = data.len();
  if n != ZKP_PLONK_PROOF_LEN {
    return _err_bool("zkp: plonk proof needs 528 bytes at offset 0, have " + convert.int_to_string(n));
  }
  var ok = true;
  var i = 0;
  while i < ZKP_PLONK_G1_COUNT {
    if !_point_ok(ZKP_POINT_G1_COMPRESSED, data, i * ZKP_G1_COMPRESSED_LEN) {
      ok = false;
    }
    i = i + 1;
  }
  return _ok_bool(ok);
}

/// Compressed G1 point `i` (0..8) of a decoded PLONK proof as 48 bytes.
///
/// Params: p - the proof; i - 0..8 (A, B, C, Z, T1, T2, T3, W1, W2).
/// Returns: Ok(48 bytes).
/// Error case: Err("zkp: plonk g1 index I out of range 0..8") when i is
/// outside 0..8; Err("zkp: plonk g1 point I is missing from the buffer") when
/// the flat buffer cannot hold that point.
/// Complexity: O(48).
pub fn zkp_plonk_proof_g1(p: &PlonkProof, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= ZKP_PLONK_G1_COUNT {
    return _err_bytes("zkp: plonk g1 index " + convert.int_to_string(i) + " out of range 0.." + convert.int_to_string(ZKP_PLONK_G1_COUNT - 1));
  }
  if (i + 1) * ZKP_G1_COMPRESSED_LEN > p.points.len() {
    return _err_bytes("zkp: plonk g1 point " + convert.int_to_string(i) + " is missing from the buffer");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < ZKP_G1_COMPRESSED_LEN {
    out.push(p.points[i * ZKP_G1_COMPRESSED_LEN + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Evaluation `i` (0..2: a, b, c) of a decoded PLONK proof as 32 bytes.
///
/// Params: p - the proof; i - 0..2.
/// Returns: Ok(32 bytes).
/// Error case: Err("zkp: plonk eval index I out of range 0..2") when i is
/// outside 0..2; Err("zkp: plonk eval I is missing from the buffer") when the
/// flat buffer cannot hold that evaluation.
/// Complexity: O(32).
pub fn zkp_plonk_proof_eval(p: &PlonkProof, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= ZKP_PLONK_EVAL_COUNT {
    return _err_bytes("zkp: plonk eval index " + convert.int_to_string(i) + " out of range 0.." + convert.int_to_string(ZKP_PLONK_EVAL_COUNT - 1));
  }
  if (i + 1) * ZKP_PLONK_EVAL_LEN > p.evals.len() {
    return _err_bytes("zkp: plonk eval " + convert.int_to_string(i) + " is missing from the buffer");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < ZKP_PLONK_EVAL_LEN {
    out.push(p.evals[i * ZKP_PLONK_EVAL_LEN + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// PLONK verification key length accessor: 580.
/// Error case: none. Complexity: O(1).
pub fn zkp_plonk_vk_len() -> Int {
  return ZKP_PLONK_VK_LEN;
}

/// Name of PLONK verification key G1 point `i`: Qm, Ql, Qr, Qo, Qc, S1,
/// S2 for 0..6, "" beyond.
/// Error case: none. Complexity: O(1).
pub fn zkp_plonk_vk_point_name(i: Int) -> Str {
  if i == 0 {
    return "Qm";
  }
  if i == 1 {
    return "Ql";
  }
  if i == 2 {
    return "Qr";
  }
  if i == 3 {
    return "Qo";
  }
  if i == 4 {
    return "Qc";
  }
  if i == 5 {
    return "S1";
  }
  if i == 6 {
    return "S2";
  }
  return "";
}

/// Decode a 580-byte PLONK verification key:
/// n8 (4-byte little-endian u32) || omega (48) || k1 (48) || k2 (48) ||
/// X_2 (96 compressed G2) || 7 compressed G1 points (336).
///
/// Params: data - exactly 580 bytes.
/// Returns: Ok(PlonkVk) with the n8 decoded to Int and flat copies of the
/// rest.
/// Error case: Err("zkp: plonk vk needs 580 bytes at offset 0, have N") when
/// the buffer length is not exactly 580.
/// Complexity: O(580).
pub fn zkp_plonk_vk_decode(data: &Vec[UInt8]) -> Result[PlonkVk, Str] {
  let n = data.len();
  if n != ZKP_PLONK_VK_LEN {
    return _err_plonkvk("zkp: plonk vk needs 580 bytes at offset 0, have " + convert.int_to_string(n));
  }
  let n8 = _vb(data, 0) + _vb(data, 1) * 256 + _vb(data, 2) * 65536 + _vb(data, 3) * 16777216;
  var omega = _copy_range(data, 4, ZKP_FP_LEN);
  var k1 = _copy_range(data, 4 + ZKP_FP_LEN, ZKP_FP_LEN);
  var k2 = _copy_range(data, 4 + ZKP_FP_LEN + ZKP_FP_LEN, ZKP_FP_LEN);
  var x2 = _copy_range(data, 4 + ZKP_FP_LEN + ZKP_FP_LEN + ZKP_FP_LEN, ZKP_G2_COMPRESSED_LEN);
  var points = _copy_range(data, 4 + ZKP_FP_LEN * 3 + ZKP_G2_COMPRESSED_LEN, ZKP_PLONK_VK_G1_COUNT * ZKP_G1_COMPRESSED_LEN);
  return _ok_plonkvk(PlonkVk{ n8: n8; omega: omega; k1: k1; k2: k2; x2: x2; points: points });
}

/// Validate a 580-byte PLONK verification key: exact length, canonical Fp
/// for omega/k1/k2, compressed-G2 rules for X_2, compressed-G1 rules for the
/// 7 points.
///
/// Params: data - the key buffer.
/// Returns: Ok(true) when everything is structurally legal; Ok(false) when
/// the length is right but some element violates a rule.
/// Error case: Err("zkp: plonk vk needs 580 bytes at offset 0, have N") when
/// the buffer length is not exactly 580.
/// Complexity: O(580). No curve or subgroup check.
pub fn zkp_plonk_vk_validate(data: &Vec[UInt8]) -> Result[Bool, Str] {
  let n = data.len();
  if n != ZKP_PLONK_VK_LEN {
    return _err_bool("zkp: plonk vk needs 580 bytes at offset 0, have " + convert.int_to_string(n));
  }
  var ok = _fp_ok(data, 4);
  if !_fp_ok(data, 4 + ZKP_FP_LEN) {
    ok = false;
  }
  if !_fp_ok(data, 4 + ZKP_FP_LEN + ZKP_FP_LEN) {
    ok = false;
  }
  if !_point_ok(ZKP_POINT_G2_COMPRESSED, data, 4 + ZKP_FP_LEN * 3) {
    ok = false;
  }
  var i = 0;
  while i < ZKP_PLONK_VK_G1_COUNT {
    if !_point_ok(ZKP_POINT_G1_COMPRESSED, data, 4 + ZKP_FP_LEN * 3 + ZKP_G2_COMPRESSED_LEN + i * ZKP_G1_COMPRESSED_LEN) {
      ok = false;
    }
    i = i + 1;
  }
  return _ok_bool(ok);
}

/// The omega element of a PLONK verification key (48-byte Fp copy).
/// Error case: none. Complexity: O(48).
pub fn zkp_plonk_vk_omega(vk: &PlonkVk) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vk.omega.len() {
    out.push(vk.omega[i]);
    i = i + 1;
  }
  return out;
}

/// The k1 element of a PLONK verification key (48-byte Fp copy).
/// Error case: none. Complexity: O(48).
pub fn zkp_plonk_vk_k1(vk: &PlonkVk) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vk.k1.len() {
    out.push(vk.k1[i]);
    i = i + 1;
  }
  return out;
}

/// The k2 element of a PLONK verification key (48-byte Fp copy).
/// Error case: none. Complexity: O(48).
pub fn zkp_plonk_vk_k2(vk: &PlonkVk) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vk.k2.len() {
    out.push(vk.k2[i]);
    i = i + 1;
  }
  return out;
}

/// The X_2 point of a PLONK verification key (96-byte compressed G2 copy).
/// Error case: none. Complexity: O(96).
pub fn zkp_plonk_vk_x2(vk: &PlonkVk) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vk.x2.len() {
    out.push(vk.x2[i]);
    i = i + 1;
  }
  return out;
}

/// The domain size n8 of a PLONK verification key (decoded from the 4-byte
/// little-endian prefix).
/// Error case: none. Complexity: O(1).
pub fn zkp_plonk_vk_n8(vk: &PlonkVk) -> Int {
  return vk.n8;
}

/// Compressed G1 point `i` (0..6) of a PLONK verification key as 48 bytes.
///
/// Params: vk - the key; i - 0..6 (Qm, Ql, Qr, Qo, Qc, S1, S2).
/// Returns: Ok(48 bytes).
/// Error case: Err("zkp: plonk vk g1 index I out of range 0..6") when i is
/// outside 0..6; Err("zkp: plonk vk g1 point I is missing from the buffer")
/// when the flat buffer cannot hold that point.
/// Complexity: O(48).
pub fn zkp_plonk_vk_g1(vk: &PlonkVk, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= ZKP_PLONK_VK_G1_COUNT {
    return _err_bytes("zkp: plonk vk g1 index " + convert.int_to_string(i) + " out of range 0.." + convert.int_to_string(ZKP_PLONK_VK_G1_COUNT - 1));
  }
  if (i + 1) * ZKP_G1_COMPRESSED_LEN > vk.points.len() {
    return _err_bytes("zkp: plonk vk g1 point " + convert.int_to_string(i) + " is missing from the buffer");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < ZKP_G1_COMPRESSED_LEN {
    out.push(vk.points[i * ZKP_G1_COMPRESSED_LEN + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Scheme detection
// --------------------------------------------------

/// Scheme expected length in bytes: 192 for Groth16, 528 for PLONK, -1 for
/// an unknown tag.
///
/// Params: scheme - a ZKP_SCHEME_* tag.
/// Returns: the length, or -1.
/// Error case: none. Complexity: O(1).
pub fn zkp_scheme_expected_len(scheme: Int) -> Int {
  if scheme == ZKP_SCHEME_GROTH16 {
    return ZKP_GROTH16_PROOF_LEN;
  }
  if scheme == ZKP_SCHEME_PLONK {
    return ZKP_PLONK_PROOF_LEN;
  }
  return -1;
}

/// Scheme name: "groth16", "plonk", or "unknown" (also for any tag that is
/// not a ZKP_SCHEME_* value).
/// Error case: none. Complexity: O(1).
pub fn zkp_scheme_name(scheme: Int) -> Str {
  if scheme == ZKP_SCHEME_GROTH16 {
    return "groth16";
  }
  if scheme == ZKP_SCHEME_PLONK {
    return "plonk";
  }
  return "unknown";
}

/// Detect the proof scheme from a blob's total length: exactly 192 bytes is
/// Groth16, exactly 528 is PLONK, anything else is unknown. Detection is by
/// length only and is ambiguous for lengths that also occur elsewhere: 192
/// is also the uncompressed-G2 point length (and 96 is both a compressed G2
/// and an uncompressed G1), so use this only on buffers known to be proof
/// blobs.
///
/// Params: data - the candidate proof buffer.
/// Returns: ZKP_SCHEME_GROTH16, ZKP_SCHEME_PLONK or ZKP_SCHEME_UNKNOWN.
/// Error case: none. Complexity: O(1).
pub fn zkp_scheme_detect(data: &Vec[UInt8]) -> Int {
  let n = data.len();
  if n == ZKP_GROTH16_PROOF_LEN {
    return ZKP_SCHEME_GROTH16;
  }
  if n == ZKP_PLONK_PROOF_LEN {
    return ZKP_SCHEME_PLONK;
  }
  return ZKP_SCHEME_UNKNOWN;
}

/// Detect the scheme by length and validate the blob with the matching
/// structural validator.
///
/// Params: data - the candidate proof buffer.
/// Returns: Ok(true) when the length matches a scheme and that scheme's
/// structural rules hold; Ok(false) when the length matches but a rule is
/// violated.
/// Error case: Err("zkp: unknown scheme for length N (expected 192 groth16
/// or 528 plonk)") when the length is neither 192 nor 528; the validator Err
/// cases otherwise.
/// Complexity: O(length).
pub fn zkp_blob_validate(data: &Vec[UInt8]) -> Result[Bool, Str] {
  let scheme = zkp_scheme_detect(data);
  if scheme == ZKP_SCHEME_UNKNOWN {
    return _err_bool("zkp: unknown scheme for length " + convert.int_to_string(data.len()) + " (expected 192 groth16 or 528 plonk)");
  }
  if scheme == ZKP_SCHEME_GROTH16 {
    return zkp_groth16_proof_validate(data);
  }
  return zkp_plonk_proof_validate(data);
}

// --------------------------------------------------
//  Hex decode
// --------------------------------------------------

// Hex digit value (0..15) of a widened byte, or -1 when it is not [0-9A-Fa-f].
fn _hex_value(b: Int) -> Int {
  if b >= 48 && b <= 57 {
    return b - 48;
  }
  if b >= 97 && b <= 102 {
    return b - 97 + 10;
  }
  if b >= 65 && b <= 70 {
    return b - 65 + 10;
  }
  return -1;
}

/// Decode a 0x-prefixed hex string into bytes: the standard proof-in-hex
/// form. Both `0x` and `0X` prefixes are accepted; digits may be mixed case;
/// an odd number of payload digits is rejected. Offsets in errors are counted
/// from the start of the text (the prefix occupies offsets 0 and 1).
///
/// Params: text - the hex text, e.g. "0x1a01...".
/// Returns: Ok(bytes) for an even-length payload; Ok(empty) for the bare
/// prefix "0x".
/// Error case: Err("zkp: hex text must start with 0x") when the prefix is
/// missing; Err("zkp: hex payload length P is odd") when the payload has an
/// odd number of digits; Err("zkp: hex invalid character at offset O (byte
/// B)") on the first non-hex digit.
/// Complexity: O(text.len()).
pub fn zkp_proof_hex_decode(text: Str) -> Result[Vec[UInt8], Str] {
  let n = text.len();
  if n < 2 {
    return _err_bytes("zkp: hex text must start with 0x");
  }
  let c0 = (string.byte_at(text, 0) as Int) & 0xFF;
  let c1 = (string.byte_at(text, 1) as Int) & 0xFF;
  var has_prefix = false;
  if c0 == 48 {
    if c1 == 120 || c1 == 88 {
      has_prefix = true;
    }
  }
  if !has_prefix {
    return _err_bytes("zkp: hex text must start with 0x");
  }
  let payload = n - 2;
  if payload % 2 != 0 {
    return _err_bytes("zkp: hex payload length " + convert.int_to_string(payload) + " is odd");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < payload {
    let hb = (string.byte_at(text, 2 + i) as Int) & 0xFF;
    let lb = (string.byte_at(text, 2 + i + 1) as Int) & 0xFF;
    let hv = _hex_value(hb);
    if hv < 0 {
      return _err_bytes("zkp: hex invalid character at offset " + convert.int_to_string(2 + i) + " (byte " + convert.int_to_string(hb) + ")");
    }
    let lv = _hex_value(lb);
    if lv < 0 {
      return _err_bytes("zkp: hex invalid character at offset " + convert.int_to_string(2 + i + 1) + " (byte " + convert.int_to_string(lb) + ")");
    }
    out.push((hv * 16 + lv) as UInt8);
    i = i + 2;
  }
  return _ok_bytes(out);
}
