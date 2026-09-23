// XIOM -- xiom.msgpack: pure-XIOM MessagePack encoding and decoding
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Minimal MessagePack codec for the supported subset: nil, bool, Int
// (fixint / uint8..uint64 / int8..int64), Str (fixstr / str8 / str16 /
// str32) and array/map headers (fixarray / array16 / array32 / fixmap /
// map16 / map32). No FFI: encoded bytes are built with Vec[UInt8].push and
// decoded through the MsgpackReader cursor. See SPEC.md for the byte-level
// format table, error catalog and documented limitations.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * `& 0xFF` on values with bit 31 set miscompiles, so all big-endian
//     byte extraction here is arithmetic (modulo/division), which is exact
//     for negative two's-complement values.
//   * msgpack_encode_float64 is intentionally absent: there is no
//     i64<->f64 bitcast intrinsic in the compiler (xiom.num.float is a
//     documented zero-returning stub), so the exact 0xcb payload cannot be
//     produced without FFI.

module xiom.msgpack

use xiom.string;
use xiom.string.builder;

/// Mutable cursor over an encoded MessagePack buffer.
/// `data` holds the encoded bytes; `pos` is the next byte to read
/// (0 <= pos <= data.len()). Fields are implementation details; callers must
/// go through the free functions below.
pub type MsgpackReader = {
  data: Vec[UInt8];
  pos: Int;
}

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

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
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
//  Internal byte helpers
// --------------------------------------------------

// Two lowercase hex digits for a byte value (0..255).
fn _hex2(b: Int) -> Str {
  let digits = "0123456789abcdef";
  let hi = b / 16;
  let lo = b % 16;
  return string.str_slice(digits, hi, hi + 1) + string.str_slice(digits, lo, lo + 1);
}

// "msgpack: unexpected type 0xNN" for a raw format byte.
fn _unexpected(t: Int) -> Str {
  return "msgpack: unexpected type 0x" + _hex2(t);
}

// Big-endian byte `shift_bytes` of `v` (0 = least significant byte).
// Arithmetic only: `& 0xFF` on values with bit 31 set miscompiles in
// v0.61.3 (see xiom.convert.base58), and this form is exact for negative
// two's-complement values.
fn _be_byte(v: Int, shift_bytes: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift_bytes {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low `size` bytes of `v` in big-endian order.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_be_byte(v, i));
    i = i - 1;
  }
}

// Raw format byte at the cursor without advancing; Err when exhausted.
fn _peek_byte(r: &MsgpackReader) -> Result[Int, Str] {
  if r.pos >= r.data.len() {
    return _err_int("msgpack: truncated buffer");
  }
  return _ok_int((r.data[r.pos] as Int) & 0xFF);
}

// Same as _peek_byte but takes &mut, so the read_* bodies never mix a `&`
// call before a `&mut` call on the same local (advisory E001).
fn _peek_byte_mut(r: &mut MsgpackReader) -> Result[Int, Str] {
  return _peek_byte(r);
}

// 2^k for small k (used for sign extension of int8/16/32).
fn _pow2(k: Int) -> Int {
  var v: Int = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Read `size` bytes at the cursor as an UNSIGNED big-endian Int and advance.
// Values above 2^63-1 wrap to the same two's-complement bit pattern (Int is
// signed 64-bit; documented in SPEC.md).
fn _read_uint(r: &mut MsgpackReader, size: Int) -> Result[Int, Str] {
  let remaining = r.data.len() - r.pos;
  if remaining < size {
    return _err_int("msgpack: truncated buffer");
  }
  var result: Int = 0;
  var i = 0;
  while i < size {
    let b = (r.data[r.pos + i] as Int) & 0xFF;
    result = result * 256 + b;
    i = i + 1;
  }
  r.pos = r.pos + size;
  return _ok_int(result);
}

// Read `size` bytes at the cursor as a SIGNED big-endian Int and advance.
fn _read_sint(r: &mut MsgpackReader, size: Int) -> Result[Int, Str] {
  let remaining = r.data.len() - r.pos;
  if remaining < size {
    return _err_int("msgpack: truncated buffer");
  }
  let first = (r.data[r.pos] as Int) & 0xFF;
  let negative = first >= 128;
  var acc: Int = 0;
  if negative && size == 8 {
    acc = -1;
  }
  var i = 0;
  while i < size {
    let b = (r.data[r.pos + i] as Int) & 0xFF;
    acc = acc * 256 + b;
    i = i + 1;
  }
  if negative && size < 8 {
    acc = acc - _pow2(size * 8);
  }
  r.pos = r.pos + size;
  return _ok_int(acc);
}

// Copy `len` payload bytes into a fresh Str (bytes verbatim, no UTF-8
// validation) and advance the cursor.
fn _read_str_payload(r: &mut MsgpackReader, len: Int) -> Result[Str, Str] {
  let remaining = r.data.len() - r.pos;
  if remaining < len {
    return _err_str("msgpack: truncated buffer");
  }
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < len {
    sb.push(r.data[r.pos + i]);
    i = i + 1;
  }
  r.pos = r.pos + len;
  return _ok_str(builder.sb_to_str(&sb));
}

// --------------------------------------------------
//  Encoders (each returns the exact minimal encoding)
// --------------------------------------------------

/// Encode nil (0xc0).
pub fn msgpack_encode_nil() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(0xC0 as UInt8);
  return out;
}

/// Encode a Bool (0xc2 false / 0xc3 true).
pub fn msgpack_encode_bool(b: Bool) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if b {
    out.push(0xC3 as UInt8);
  } else {
    out.push(0xC2 as UInt8);
  }
  return out;
}

/// Encode an Int with the minimal MessagePack representation:
/// positive fixint 0..127; negative fixint -32..-1; uint8/uint16/uint32/
/// uint64 for positive values above 127; int8/int16/int32/int64 for
/// negative values below -32.
pub fn msgpack_encode_int(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if n >= 0 && n <= 127 {
    out.push(n as UInt8);
    return out;
  }
  if n >= -32 && n < 0 {
    out.push((256 + n) as UInt8);
    return out;
  }
  if n > 127 {
    if n <= 255 {
      out.push(0xCC as UInt8);
      _push_be(&mut out, n, 1);
      return out;
    }
    if n <= 65535 {
      out.push(0xCD as UInt8);
      _push_be(&mut out, n, 2);
      return out;
    }
    if n <= 4294967295 {
      out.push(0xCE as UInt8);
      _push_be(&mut out, n, 4);
      return out;
    }
    out.push(0xCF as UInt8);
    _push_be(&mut out, n, 8);
    return out;
  }
  if n >= -128 {
    out.push(0xD0 as UInt8);
    _push_be(&mut out, n, 1);
    return out;
  }
  if n >= -32768 {
    out.push(0xD1 as UInt8);
    _push_be(&mut out, n, 2);
    return out;
  }
  if n >= -2147483648 {
    out.push(0xD2 as UInt8);
    _push_be(&mut out, n, 4);
    return out;
  }
  out.push(0xD3 as UInt8);
  _push_be(&mut out, n, 8);
  return out;
}

/// Encode a Str: fixstr (<= 31 bytes); str8/str16/str32 header followed by
/// the UTF-8 bytes of `s` (copied verbatim).
pub fn msgpack_encode_str(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = s.len();
  if n <= 31 {
    out.push((0xA0 + n) as UInt8);
  } elif n <= 255 {
    out.push(0xD9 as UInt8);
    _push_be(&mut out, n, 1);
  } elif n <= 65535 {
    out.push(0xDA as UInt8);
    _push_be(&mut out, n, 2);
  } else {
    out.push(0xDB as UInt8);
    _push_be(&mut out, n, 4);
  }
  builder.sb_push_str(&mut out, s);
  return out;
}

/// Encode an array header: fixarray (<= 15 elements); array16 (<= 65535);
/// array32 (<= 2^32-1). A negative or > 2^32-1 count has no byte encoding
/// and yields an empty Vec (caller error; documented in SPEC.md).
pub fn msgpack_encode_array_header(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if n < 0 {
    return out;
  }
  if n <= 15 {
    out.push((0x90 + n) as UInt8);
    return out;
  }
  if n <= 65535 {
    out.push(0xDC as UInt8);
    _push_be(&mut out, n, 2);
    return out;
  }
  if n <= 4294967295 {
    out.push(0xDD as UInt8);
    _push_be(&mut out, n, 4);
    return out;
  }
  return out;
}

/// Encode a map header: fixmap (<= 15 pairs); map16 (<= 65535); map32
/// (<= 2^32-1). A negative or > 2^32-1 count has no byte encoding and
/// yields an empty Vec (caller error; documented in SPEC.md).
pub fn msgpack_encode_map_header(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if n < 0 {
    return out;
  }
  if n <= 15 {
    out.push((0x80 + n) as UInt8);
    return out;
  }
  if n <= 65535 {
    out.push(0xDE as UInt8);
    _push_be(&mut out, n, 2);
    return out;
  }
  if n <= 4294967295 {
    out.push(0xDF as UInt8);
    _push_be(&mut out, n, 4);
    return out;
  }
  return out;
}

// --------------------------------------------------
//  Decoder
// --------------------------------------------------

/// Create a reader positioned at the start of `data`.
pub fn msgpack_reader_new(data: Vec[UInt8]) -> MsgpackReader {
  return MsgpackReader{ data: data; pos: 0; };
}

/// Current cursor position (bytes consumed).
pub fn msgpack_reader_pos(r: &MsgpackReader) -> Int {
  return r.pos;
}

/// Number of unread bytes (never negative).
pub fn msgpack_reader_remaining(r: &MsgpackReader) -> Int {
  let rem = r.data.len() - r.pos;
  if rem < 0 {
    return 0;
  }
  return rem;
}

/// Raw format byte at the cursor without advancing it.
/// Err("msgpack: truncated buffer") when the buffer is exhausted.
pub fn msgpack_peek_type(r: &MsgpackReader) -> Result[Int, Str] {
  return _peek_byte(r);
}

/// Read an Int: positive/negative fixint, uint8/16/32/64, int8/16/32/64.
/// Err on truncation or on any other format byte.
pub fn msgpack_read_int(r: &mut MsgpackReader) -> Result[Int, Str] {
  let pk = _peek_byte_mut(r);
  if !pk.is_ok {
    return _err_int(pk.error);
  }
  let t = pk.value;
  if t <= 127 {
    r.pos = r.pos + 1;
    return _ok_int(t);
  }
  if t >= 224 {
    r.pos = r.pos + 1;
    return _ok_int(t - 256);
  }
  r.pos = r.pos + 1;
  if t == 204 {
    return _read_uint(r, 1);
  }
  if t == 205 {
    return _read_uint(r, 2);
  }
  if t == 206 {
    return _read_uint(r, 4);
  }
  if t == 207 {
    return _read_uint(r, 8);
  }
  if t == 208 {
    return _read_sint(r, 1);
  }
  if t == 209 {
    return _read_sint(r, 2);
  }
  if t == 210 {
    return _read_sint(r, 4);
  }
  if t == 211 {
    return _read_sint(r, 8);
  }
  return _err_int(_unexpected(t));
}

/// Read a Str: fixstr, str8, str16 or str32. The payload bytes are copied
/// verbatim into the result (no UTF-8 validation; documented in SPEC.md).
/// Err on truncation or on any other format byte.
pub fn msgpack_read_str(r: &mut MsgpackReader) -> Result[Str, Str] {
  let pk = _peek_byte_mut(r);
  if !pk.is_ok {
    return _err_str(pk.error);
  }
  let t = pk.value;
  if t >= 160 && t <= 191 {
    r.pos = r.pos + 1;
    return _read_str_payload(r, t - 160);
  }
  if t == 217 {
    r.pos = r.pos + 1;
    let lr = _read_uint(r, 1);
    if !lr.is_ok {
      return _err_str(lr.error);
    }
    return _read_str_payload(r, lr.value);
  }
  if t == 218 {
    r.pos = r.pos + 1;
    let lr = _read_uint(r, 2);
    if !lr.is_ok {
      return _err_str(lr.error);
    }
    return _read_str_payload(r, lr.value);
  }
  if t == 219 {
    r.pos = r.pos + 1;
    let lr = _read_uint(r, 4);
    if !lr.is_ok {
      return _err_str(lr.error);
    }
    return _read_str_payload(r, lr.value);
  }
  return _err_str(_unexpected(t));
}

/// Read a Bool (0xc2 / 0xc3). Err on truncation or any other format byte.
pub fn msgpack_read_bool(r: &mut MsgpackReader) -> Result[Bool, Str] {
  let pk = _peek_byte_mut(r);
  if !pk.is_ok {
    return _err_bool(pk.error);
  }
  let t = pk.value;
  if t == 194 {
    r.pos = r.pos + 1;
    return _ok_bool(false);
  }
  if t == 195 {
    r.pos = r.pos + 1;
    return _ok_bool(true);
  }
  return _err_bool(_unexpected(t));
}

/// Read an array header (fixarray / array16 / array32) and return the
/// element count. Only the header is consumed; elements are the caller's
/// responsibility. Err on truncation or any other format byte.
pub fn msgpack_read_array_len(r: &mut MsgpackReader) -> Result[Int, Str] {
  let pk = _peek_byte_mut(r);
  if !pk.is_ok {
    return _err_int(pk.error);
  }
  let t = pk.value;
  if t >= 144 && t <= 159 {
    r.pos = r.pos + 1;
    return _ok_int(t - 144);
  }
  if t == 220 {
    r.pos = r.pos + 1;
    return _read_uint(r, 2);
  }
  if t == 221 {
    r.pos = r.pos + 1;
    return _read_uint(r, 4);
  }
  return _err_int(_unexpected(t));
}

/// Read a map header (fixmap / map16 / map32) and return the pair count.
/// Only the header is consumed; keys/values are the caller's
/// responsibility. Err on truncation or any other format byte.
pub fn msgpack_read_map_len(r: &mut MsgpackReader) -> Result[Int, Str] {
  let pk = _peek_byte_mut(r);
  if !pk.is_ok {
    return _err_int(pk.error);
  }
  let t = pk.value;
  if t >= 128 && t <= 143 {
    r.pos = r.pos + 1;
    return _ok_int(t - 128);
  }
  if t == 222 {
    r.pos = r.pos + 1;
    return _read_uint(r, 2);
  }
  if t == 223 {
    r.pos = r.pos + 1;
    return _read_uint(r, 4);
  }
  return _err_int(_unexpected(t));
}
