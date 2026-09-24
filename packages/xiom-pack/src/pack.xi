// XIOM -- xiom.pack: format-string binary packing and unpacking
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) pack/unpack codec for fixed-width integer fields over
// in-memory Vec[UInt8] buffers. A format string is a sequence of
// space-separated tokens (u8, s8, b8, u16le/be, s16le/be, u32le/be,
// s32le/be, u64le/be, s64le/be): pack_format writes the fields in order,
// unpack_format reads them back at an explicit offset, pack_size and
// pack_token_size pre-size buffers, and the pack_u*/pack_s* appenders push
// individual fields onto an existing buffer. See SPEC.md for the token
// grammar, the per-token ranges, the error catalog and the documented
// limitations.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (_ok_int/_err_int/_ok_ints/_err_ints/_ok_bytes/_err_bytes);
//     constructing Results directly inside other functions miscompiles.
//   * every raw byte widens through `(x as Int) & 0xFF` before use.
//   * no `<<` shift is used: byte extraction is arithmetic (modulo/division
//     with a negative-remainder correction), which is exact for negative
//     two's-complement values (`& 0xFF` on values with bit 31 set
//     miscompiles in v0.61.3, see xiom.convert.base58).
//   * decoding an 8-byte field never overflows: the low seven bytes are
//     accumulated with a `place` factor (max 2^56-1) and the top byte is
//     applied as an explicit +2^56 term, with bit 63 folded into INT64_MIN.
//   * free functions only: no methods, no lambdas, no Vec[StructType].
//   * Str comparisons go through string.str_compare; `==` on Str values read
//     from a Vec[Str] lowers to a pointer comparison (BUG 17).

module xiom.pack

use xiom.string;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
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

// --------------------------------------------------
//  Token parsing
// --------------------------------------------------

// Split a format string into space-separated tokens. Only the space byte
// (0x20) separates tokens; runs of spaces and leading/trailing spaces are
// skipped, so "" and "   " yield zero tokens.
fn _split_tokens(fmt: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let n = fmt.len();
  var i = 0;
  var start = 0;
  while i <= n {
    var is_sep = i == n;
    if !is_sep {
      let b = (string.byte_at(fmt, i) as Int) & 0xFF;
      is_sep = b == 32;
    }
    if is_sep {
      if i > start {
        out.push(string.str_slice(fmt, start, i));
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return out;
}

// Token equality via string.str_compare (never `==` on Str).
fn _token_is(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

// True when lo <= v <= hi.
fn _in_range(v: Int, lo: Int, hi: Int) -> Bool {
  return v >= lo && v <= hi;
}

// 2^k for small k (used for 1/2/4-byte sign extension).
fn _pow2(k: Int) -> Int {
  var v: Int = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Byte `k` (0 = least significant) of the raw two's-complement bit pattern
// of `v`, as a value in 0..255. Arithmetic only (see the module header).
fn _byte_low(v: Int, k: Int) -> Int {
  var q = v;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b;
}

// Append the low `size` bytes of `v`, least significant byte first. Masked
// to width: bits above the low `size` bytes are dropped.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_byte_low(v, i) as UInt8);
    i = i + 1;
  }
}

// Append the low `size` bytes of `v`, most significant byte first. Masked
// to width: bits above the low `size` bytes are dropped.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_byte_low(v, i) as UInt8);
    i = i - 1;
  }
}

// --------------------------------------------------
//  Field readers
// --------------------------------------------------

// Value of `size` (1/2/4/8) consecutive bytes at `off` as the raw
// two's-complement bit pattern; `be` selects big-endian byte order. The low
// seven bytes of an 8-byte field are accumulated with a `place` factor and
// the top byte is applied as an explicit +2^56 term, so no intermediate
// exceeds INT64_MAX; a top byte with bit 7 set folds in INT64_MIN.
fn _read_uint(data: &Vec[UInt8], off: Int, size: Int, be: Bool) -> Int {
  var nlow = size;
  if size == 8 { nlow = 7; }
  var low: Int = 0;
  var place: Int = 1;
  var i = 0;
  while i < nlow {
    var src = off + i;
    if be { src = off + size - 1 - i; }
    let b = (data[src] as Int) & 0xFF;
    low = low + b * place;
    place = place * 256;
    i = i + 1;
  }
  if size == 8 {
    var top_src = off + 7;
    if be { top_src = off; }
    let top = (data[top_src] as Int) & 0xFF;
    if top < 128 {
      return low + top * place;
    }
    let t = top - 128;
    let hi = low + t * place;
    return hi + (0 - 9223372036854775807 - 1);
  }
  return low;
}

// Sign-extended value of `size` consecutive bytes at `off`. For size 8 the
// raw pattern already is the signed value (bit 63 is the sign); for 1/2/4
// bytes a set sign bit subtracts 2^(8*size).
fn _read_sint(data: &Vec[UInt8], off: Int, size: Int, be: Bool) -> Int {
  let raw = _read_uint(data, off, size, be);
  if size == 8 {
    return raw;
  }
  var sign_src = off + size - 1;
  if be { sign_src = off; }
  let top = (data[sign_src] as Int) & 0xFF;
  if top < 128 {
    return raw;
  }
  return raw - _pow2(8 * size);
}

// --------------------------------------------------
//  Sizes
// --------------------------------------------------

/// Byte width of one format token: 1 for u8/s8/b8, 2 for u16*/s16*, 4 for
/// u32*/s32*, 8 for u64*/s64*. Returns 0 for an unknown token (including
/// empty strings and case variants such as "U8").
pub fn pack_token_size(token: Str) -> Int {
  if _token_is(token, "u8") { return 1; }
  if _token_is(token, "s8") { return 1; }
  if _token_is(token, "b8") { return 1; }
  if _token_is(token, "u16le") { return 2; }
  if _token_is(token, "u16be") { return 2; }
  if _token_is(token, "s16le") { return 2; }
  if _token_is(token, "s16be") { return 2; }
  if _token_is(token, "u32le") { return 4; }
  if _token_is(token, "u32be") { return 4; }
  if _token_is(token, "s32le") { return 4; }
  if _token_is(token, "s32be") { return 4; }
  if _token_is(token, "u64le") { return 8; }
  if _token_is(token, "u64be") { return 8; }
  if _token_is(token, "s64le") { return 8; }
  if _token_is(token, "s64be") { return 8; }
  return 0;
}

/// Total encoded byte size of `fmt`.
/// Returns: Ok(total) when every token is known (0 for an empty format).
/// Error case: Err("pack: unknown token '<token>'") for the first unknown
/// token.
pub fn pack_size(fmt: Str) -> Result[Int, Str] {
  let tokens = _split_tokens(fmt);
  var total: Int = 0;
  var i = 0;
  while i < tokens.len() {
    let t: Str = tokens[i];
    let w = pack_token_size(t);
    if w == 0 {
      return _err_int("pack: unknown token '" + t + "'");
    }
    total = total + w;
    i = i + 1;
  }
  return _ok_int(total);
}

// --------------------------------------------------
//  Encode
// --------------------------------------------------

/// Encode `values` according to the space-separated `fmt` tokens, field by
/// field and in order (little-endian tokens write the least significant byte
/// first, big-endian tokens the most significant byte first).
/// Params: fmt - format string; values - one Int per token.
/// Returns: Ok(bytes); an empty format with empty values yields Ok(empty).
/// Error case: Err("pack: token count mismatch") when the token count
/// differs from values.len(); Err("pack: unknown token '<token>'") for an
/// unknown token; Err("pack: <token> out of range") when a value is outside
/// the token range (see SPEC.md). u64/s64 accept every Int as a 64-bit
/// two's-complement bit pattern.
pub fn pack_format(fmt: Str, values: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  let tokens = _split_tokens(fmt);
  if tokens.len() != values.len() {
    return _err_bytes("pack: token count mismatch");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < tokens.len() {
    let t: Str = tokens[i];
    let v: Int = values[i];
    if _token_is(t, "u8") {
      if !_in_range(v, 0, 255) { return _err_bytes("pack: u8 out of range"); }
      _push_le(&mut out, v, 1);
    } elif _token_is(t, "s8") {
      if !_in_range(v, -128, 127) { return _err_bytes("pack: s8 out of range"); }
      _push_le(&mut out, v, 1);
    } elif _token_is(t, "b8") {
      if !_in_range(v, 0, 1) { return _err_bytes("pack: b8 out of range"); }
      _push_le(&mut out, v, 1);
    } elif _token_is(t, "u16le") {
      if !_in_range(v, 0, 65535) { return _err_bytes("pack: u16le out of range"); }
      _push_le(&mut out, v, 2);
    } elif _token_is(t, "u16be") {
      if !_in_range(v, 0, 65535) { return _err_bytes("pack: u16be out of range"); }
      _push_be(&mut out, v, 2);
    } elif _token_is(t, "s16le") {
      if !_in_range(v, -32768, 32767) { return _err_bytes("pack: s16le out of range"); }
      _push_le(&mut out, v, 2);
    } elif _token_is(t, "s16be") {
      if !_in_range(v, -32768, 32767) { return _err_bytes("pack: s16be out of range"); }
      _push_be(&mut out, v, 2);
    } elif _token_is(t, "u32le") {
      if !_in_range(v, 0, 4294967295) { return _err_bytes("pack: u32le out of range"); }
      _push_le(&mut out, v, 4);
    } elif _token_is(t, "u32be") {
      if !_in_range(v, 0, 4294967295) { return _err_bytes("pack: u32be out of range"); }
      _push_be(&mut out, v, 4);
    } elif _token_is(t, "s32le") {
      if !_in_range(v, -2147483648, 2147483647) { return _err_bytes("pack: s32le out of range"); }
      _push_le(&mut out, v, 4);
    } elif _token_is(t, "s32be") {
      if !_in_range(v, -2147483648, 2147483647) { return _err_bytes("pack: s32be out of range"); }
      _push_be(&mut out, v, 4);
    } elif _token_is(t, "u64le") {
      _push_le(&mut out, v, 8);
    } elif _token_is(t, "u64be") {
      _push_be(&mut out, v, 8);
    } elif _token_is(t, "s64le") {
      _push_le(&mut out, v, 8);
    } elif _token_is(t, "s64be") {
      _push_be(&mut out, v, 8);
    } else {
      return _err_bytes("pack: unknown token '" + t + "'");
    }
    i = i + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Decode
// --------------------------------------------------

/// Decode the fields described by `fmt` from `data` starting at byte `offset`.
/// Params: fmt - format string; data - source bytes; offset - first byte of
/// the first field (0 <= offset <= data.len()).
/// Returns: Ok(values); one Int per token, in order. u8/u16/u32 decode as
/// non-negative Ints; s8/s16/s32 are sign-extended; s64 is the signed 64-bit
/// value; u64 is the raw bit pattern (bit 63 set decodes as the same
/// negative Int, so 2^64-1 decodes as -1); b8 decodes any nonzero byte as 1.
/// Error case: Err("pack: negative offset") for offset < 0;
/// Err("pack: unknown token '<token>'") for an unknown token;
/// Err("pack: truncated data") when offset + pack_size(fmt) exceeds
/// data.len().
pub fn unpack_format(fmt: Str, data: &Vec[UInt8], offset: Int) -> Result[Vec[Int], Str] {
  if offset < 0 {
    return _err_ints("pack: negative offset");
  }
  let ps = pack_size(fmt);
  if !ps.is_ok {
    return _err_ints(ps.error);
  }
  let total: Int = ps.value;
  let dlen = data.len();
  if offset > dlen {
    return _err_ints("pack: truncated data");
  }
  if dlen - offset < total {
    return _err_ints("pack: truncated data");
  }
  let tokens = _split_tokens(fmt);
  var out = Vec[Int].new();
  var pos = offset;
  var i = 0;
  while i < tokens.len() {
    let t: Str = tokens[i];
    if _token_is(t, "u8") {
      out.push(_read_uint(data, pos, 1, false));
      pos = pos + 1;
    } elif _token_is(t, "s8") {
      out.push(_read_sint(data, pos, 1, false));
      pos = pos + 1;
    } elif _token_is(t, "b8") {
      let b = _read_uint(data, pos, 1, false);
      if b == 0 {
        out.push(0);
      } else {
        out.push(1);
      }
      pos = pos + 1;
    } elif _token_is(t, "u16le") {
      out.push(_read_uint(data, pos, 2, false));
      pos = pos + 2;
    } elif _token_is(t, "u16be") {
      out.push(_read_uint(data, pos, 2, true));
      pos = pos + 2;
    } elif _token_is(t, "s16le") {
      out.push(_read_sint(data, pos, 2, false));
      pos = pos + 2;
    } elif _token_is(t, "s16be") {
      out.push(_read_sint(data, pos, 2, true));
      pos = pos + 2;
    } elif _token_is(t, "u32le") {
      out.push(_read_uint(data, pos, 4, false));
      pos = pos + 4;
    } elif _token_is(t, "u32be") {
      out.push(_read_uint(data, pos, 4, true));
      pos = pos + 4;
    } elif _token_is(t, "s32le") {
      out.push(_read_sint(data, pos, 4, false));
      pos = pos + 4;
    } elif _token_is(t, "s32be") {
      out.push(_read_sint(data, pos, 4, true));
      pos = pos + 4;
    } elif _token_is(t, "u64le") {
      out.push(_read_uint(data, pos, 8, false));
      pos = pos + 8;
    } elif _token_is(t, "u64be") {
      out.push(_read_uint(data, pos, 8, true));
      pos = pos + 8;
    } elif _token_is(t, "s64le") {
      out.push(_read_sint(data, pos, 8, false));
      pos = pos + 8;
    } elif _token_is(t, "s64be") {
      out.push(_read_sint(data, pos, 8, true));
      pos = pos + 8;
    } else {
      return _err_ints("pack: unknown token '" + t + "'");
    }
    i = i + 1;
  }
  return _ok_ints(out);
}

// --------------------------------------------------
//  Convenience appenders (masked to width)
// --------------------------------------------------

/// Append the low 2 bytes of `v` little-endian. Masked to 16 bits: bits
/// above bit 15 (including the sign extension of a negative `v`) are
/// dropped. No range validation; use pack_format for checked encoding.
pub fn pack_u16_le(out: &mut Vec[UInt8], v: Int) {
  _push_le(out, v, 2);
}

/// Append the low 2 bytes of `v` big-endian. Masked to 16 bits.
pub fn pack_u16_be(out: &mut Vec[UInt8], v: Int) {
  _push_be(out, v, 2);
}

/// Append the low 2 bytes of `v` little-endian (two's complement). Masked to
/// 16 bits.
pub fn pack_s16_le(out: &mut Vec[UInt8], v: Int) {
  _push_le(out, v, 2);
}

/// Append the low 2 bytes of `v` big-endian (two's complement). Masked to
/// 16 bits.
pub fn pack_s16_be(out: &mut Vec[UInt8], v: Int) {
  _push_be(out, v, 2);
}

/// Append the low 4 bytes of `v` little-endian. Masked to 32 bits.
pub fn pack_u32_le(out: &mut Vec[UInt8], v: Int) {
  _push_le(out, v, 4);
}

/// Append the low 4 bytes of `v` big-endian. Masked to 32 bits.
pub fn pack_u32_be(out: &mut Vec[UInt8], v: Int) {
  _push_be(out, v, 4);
}

/// Append the low 4 bytes of `v` little-endian (two's complement). Masked to
/// 32 bits.
pub fn pack_s32_le(out: &mut Vec[UInt8], v: Int) {
  _push_le(out, v, 4);
}

/// Append the low 4 bytes of `v` big-endian (two's complement). Masked to
/// 32 bits.
pub fn pack_s32_be(out: &mut Vec[UInt8], v: Int) {
  _push_be(out, v, 4);
}

/// Append the low 8 bytes of `v` little-endian. Masked to 64 bits (the full
/// Int width, so the mask is the identity).
pub fn pack_u64_le(out: &mut Vec[UInt8], v: Int) {
  _push_le(out, v, 8);
}

/// Append the low 8 bytes of `v` big-endian. Masked to 64 bits.
pub fn pack_u64_be(out: &mut Vec[UInt8], v: Int) {
  _push_be(out, v, 8);
}

/// Append the low 8 bytes of `v` little-endian (two's complement). Masked to
/// 64 bits.
pub fn pack_s64_le(out: &mut Vec[UInt8], v: Int) {
  _push_le(out, v, 8);
}

/// Append the low 8 bytes of `v` big-endian (two's complement). Masked to
/// 64 bits.
pub fn pack_s64_be(out: &mut Vec[UInt8], v: Int) {
  _push_be(out, v, 8);
}
