// XIOM -- xiom.thrift: Apache Thrift binary protocol codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI, no dependencies beyond xiom.std) codec for the
// Apache Thrift *binary* protocol (the classic TBinaryProtocol wire format,
// THRIFT-0.20 spec), without any transport or RPC layer. See SPEC.md for the
// byte-level layout and the exact error catalog.
//
// Implemented:
//   * message headers: strict format `0x80010000 | type`, then the method
//     name as a string, then the int32 sequence id; legacy format (no
//     version word) detected on read when the high bit of the first word is
//     clear -- there the first word is the name length, followed by the
//     name, one type byte and the sequence id. Message types CALL 1,
//     REPLY 2, EXCEPTION 3, ONEWAY 4.
//   * field headers: one type byte plus an int16 field id; STOP 0 ends a
//     struct. Type ids BOOL 2, BYTE 3, DOUBLE 4, I16 6, I32 8, I64 10,
//     STRING 11, STRUCT 12, MAP 13, SET 14, LIST 15; everything else
//     (VOID 1, 5, 7, 9, above 15) is rejected.
//   * primitives: big-endian fixed-width integers (i8/i16/i32/i64), one
//     bool byte (1 = true, 0 = false), a double as its raw 64-bit IEEE-754
//     bit pattern, and strings as a u32 byte length plus UTF-8 bytes;
//     `_binary` variants read/write the same wire form without UTF-8
//     validation, so arbitrary byte payloads are addressable.
//   * containers: list/set = element type byte + i32 size + items; map =
//     key type byte + value type byte + i32 size + pairs.
//   * `thrift_skip` consumes any value of any supported type, recursively
//     for struct/map/list/set, and returns the number of bytes skipped.
//   * a flat struct model (`ThriftStruct`) with parallel vectors -- never
//     `Vec[StructType]` -- plus `thrift_encode_struct` /
//     `thrift_decode_struct` round-trips for BOOL, BYTE, DOUBLE, I16, I32,
//     I64 and STRING fields.
//
// Documented boundaries:
//   * every reader is bounds-checked; truncated input is rejected with
//     "thrift: truncated input";
//   * collection sizes must be non-negative and are bounded by the bytes
//     remaining (1 byte per list/set element, 2 per map pair), so hostile
//     "absurd count" headers fail fast instead of driving a huge loop;
//   * `thrift_skip` refuses container nesting deeper than
//     `thrift_max_depth()` (64) with a documented message;
//   * `thrift_read_bool` accepts only 0 and 1; `thrift_read_string`
//     requires valid UTF-8 and no 0x00 byte (xiom v0.61.3's
//     `sb_to_str` aborts on a NUL); `thrift_read_binary` performs no
//     content validation;
//   * doubles travel as the 64-bit IEEE-754 bit pattern carried in an
//     `Int` (v0.61.3 has no `Int <-> Float64` bitcast, so an exact
//     round-trip cannot be produced from a `Float64`).
//
// Non-goals: no compact protocol, no JSON protocol, no THeader/framed
// transports, no sockets/files/streaming, no IDL parser or code
// generator, no service dispatch or RPC layer, no versioned-struct
// metadata, no float convenience layer (only the raw bit pattern).
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods, no lambdas, no Vec[fn]
//     dispatch, no Vec[StructType], no Vec[Float64];
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results for struct payloads inside other functions
//     miscompiles);
//   * every byte read is widened once with `(b as Int) & 0xFF` before
//     entering Int arithmetic or comparisons;
//   * every Vec element read is bound to an explicitly typed local first;
//   * struct fields are never passed as `&struct.field` where a
//     `&Vec[UInt8]` parameter is expected (that yields an empty vector);
//     the writer/reader helpers take `&ThriftWriter` / `&ThriftReader`
//     and touch `w.data` / `r.data` directly;
//   * big-endian encoding uses arithmetic byte extraction, and decoding
//     accumulates at most 63 bits before applying the sign, so no 64-bit
//     intermediate can overflow;
//   * Str output is collected in a `Vec[UInt8]` and materialized with
//     `xiom.string.builder.sb_to_str` only after the bytes were validated
//     as NUL-free UTF-8 (or printable ASCII for names).

module xiom.thrift

use xiom.string;
use xiom.string.builder;
use xiom.convert;

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

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[ThriftMessage, Str].
fn _ok_msg(v: ThriftMessage) -> Result[ThriftMessage, Str] {
  return Ok(v);
}

// Err(m) for Result[ThriftMessage, Str].
fn _err_msg(m: Str) -> Result[ThriftMessage, Str] {
  return Err(m);
}

// Ok(v) for Result[ThriftField, Str].
fn _ok_field(v: ThriftField) -> Result[ThriftField, Str] {
  return Ok(v);
}

// Err(m) for Result[ThriftField, Str].
fn _err_field(m: Str) -> Result[ThriftField, Str] {
  return Err(m);
}

// Ok(v) for Result[ThriftListHeader, Str].
fn _ok_lhdr(v: ThriftListHeader) -> Result[ThriftListHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[ThriftListHeader, Str].
fn _err_lhdr(m: Str) -> Result[ThriftListHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[ThriftMapHeader, Str].
fn _ok_mhdr(v: ThriftMapHeader) -> Result[ThriftMapHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[ThriftMapHeader, Str].
fn _err_mhdr(m: Str) -> Result[ThriftMapHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[ThriftStruct, Str].
fn _ok_struct(v: ThriftStruct) -> Result[ThriftStruct, Str] {
  return Ok(v);
}

// Err(m) for Result[ThriftStruct, Str].
fn _err_struct(m: Str) -> Result[ThriftStruct, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// An append-only encoder over a byte buffer. Create with
/// `thrift_writer_new`, write with the `thrift_write_*` functions, then
/// take the bytes with `thrift_writer_bytes` (a copy).
pub type ThriftWriter = {
  data: Vec[UInt8];
}

/// A bounds-checked cursor reader over an immutable byte buffer. Create
/// with `thrift_reader_new`; all `thrift_read_*` / `thrift_skip`
/// functions advance `pos` and reject reads past the end.
pub type ThriftReader = {
  data: Vec[UInt8];
  pos: Int;
}

/// A decoded message header. `name` is the method name (validated as
/// printable ASCII 0x20..0x7E on read), `msg_type` is one of the
/// `thrift_msg_*` codes, `seqid` is the int32 sequence id, and `strict`
/// records which header form was on the wire (true = versioned).
pub type ThriftMessage = {
  name: Str;
  msg_type: Int;
  seqid: Int;
  strict: Bool;
}

/// A decoded field header. `ftype` is one of the `thrift_t_*` codes
/// (`thrift_t_stop()` for the struct terminator); `fid` is the int16
/// field id, and is 0 when `ftype == thrift_t_stop()`.
pub type ThriftField = {
  ftype: Int;
  fid: Int;
}

/// A decoded list or set header: element type code plus element count.
pub type ThriftListHeader = {
  etype: Int;
  size: Int;
}

/// A decoded map header: key type code, value type code and pair count.
pub type ThriftMapHeader = {
  ktype: Int;
  vtype: Int;
  size: Int;
}

/// A flat struct model: four parallel vectors, one entry per field, never
/// a `Vec[StructType]`. `ids[i]` is the field id, `types[i]` the type
/// code, `ints[i]` the value of a BOOL (0/1), BYTE, DOUBLE (raw IEEE-754
/// bit pattern), I16, I32 or I64 field, and `bytes[i]` the payload of a
/// STRING field. The vectors always have the same length; for a STRING
/// field `ints[i]` is 0, and for every other type `bytes[i]` is empty.
/// Only primitive and string fields are representable: a struct field of
/// type STRUCT/MAP/SET/LIST is rejected by `thrift_encode_struct` and
/// `thrift_read_struct` (use `thrift_skip` for those values).
pub type ThriftStruct = {
  ids: Vec[Int];
  types: Vec[Int];
  ints: Vec[Int];
  bytes: Vec[Vec[UInt8]];
}

// --------------------------------------------------
//  Constants
// --------------------------------------------------

const _VERSION: Int = 2147549184;   // 0x80010000 strict-message version word
const _VERSION_HI: Int = 32769;     // 0x8001, high 16 bits of the word above
const _MAX_DEPTH: Int = 64;         // skip nesting cap (containers only)
const _FID_LO: Int = -32768;        // int16 field id range
const _FID_HI: Int = 32767;

const _T_STOP: Int = 0;
const _T_BOOL: Int = 2;
const _T_BYTE: Int = 3;
const _T_DOUBLE: Int = 4;
const _T_I16: Int = 6;
const _T_I32: Int = 8;
const _T_I64: Int = 10;
const _T_STRING: Int = 11;
const _T_STRUCT: Int = 12;
const _T_MAP: Int = 13;
const _T_SET: Int = 14;
const _T_LIST: Int = 15;

// --------------------------------------------------
//  Public constants and codec metadata
// --------------------------------------------------

/// The strict-message version word: `0x80010000`. A strict header word is
/// `thrift_protocol_version() | message_type`.
/// Complexity: O(1).
pub fn thrift_protocol_version() -> Int {
  return 2147549184;
}

/// Maximum container nesting depth accepted by `thrift_skip`: a container
/// at depth 63 is the deepest accepted one, a container at depth 64 is
/// rejected. The struct/map/list/set passed to `thrift_skip` itself has
/// depth 0.
/// Complexity: O(1).
pub fn thrift_max_depth() -> Int {
  return 64;
}

/// Type id of the struct terminator (STOP 0).
/// Complexity: O(1).
pub fn thrift_t_stop() -> Int {
  return 0;
}

/// Type id of BOOL (2).
/// Complexity: O(1).
pub fn thrift_t_bool() -> Int {
  return 2;
}

/// Type id of BYTE (3).
/// Complexity: O(1).
pub fn thrift_t_byte() -> Int {
  return 3;
}

/// Type id of DOUBLE (4).
/// Complexity: O(1).
pub fn thrift_t_double() -> Int {
  return 4;
}

/// Type id of I16 (6).
/// Complexity: O(1).
pub fn thrift_t_i16() -> Int {
  return 6;
}

/// Type id of I32 (8).
/// Complexity: O(1).
pub fn thrift_t_i32() -> Int {
  return 8;
}

/// Type id of I64 (10).
/// Complexity: O(1).
pub fn thrift_t_i64() -> Int {
  return 10;
}

/// Type id of STRING (11).
/// Complexity: O(1).
pub fn thrift_t_string() -> Int {
  return 11;
}

/// Type id of STRUCT (12).
/// Complexity: O(1).
pub fn thrift_t_struct() -> Int {
  return 12;
}

/// Type id of MAP (13).
/// Complexity: O(1).
pub fn thrift_t_map() -> Int {
  return 13;
}

/// Type id of SET (14).
/// Complexity: O(1).
pub fn thrift_t_set() -> Int {
  return 14;
}

/// Type id of LIST (15).
/// Complexity: O(1).
pub fn thrift_t_list() -> Int {
  return 15;
}

/// Message type of CALL (1).
/// Complexity: O(1).
pub fn thrift_msg_call() -> Int {
  return 1;
}

/// Message type of REPLY (2).
/// Complexity: O(1).
pub fn thrift_msg_reply() -> Int {
  return 2;
}

/// Message type of EXCEPTION (3).
/// Complexity: O(1).
pub fn thrift_msg_exception() -> Int {
  return 3;
}

/// Message type of ONEWAY (4).
/// Complexity: O(1).
pub fn thrift_msg_oneway() -> Int {
  return 4;
}

/// True when `t` is a value type this codec can read, skip and write in
/// the flat struct model: BOOL 2, BYTE 3, DOUBLE 4, I16 6, I32 8, I64 10,
/// STRING 11, STRUCT 12, MAP 13, SET 14, LIST 15. STOP 0, VOID 1 and the
/// unused ids 5, 7, 9 and 16+ are not value types; `thrift_t_stop()` is
/// handled separately as a struct terminator.
/// Complexity: O(1).
pub fn thrift_type_known(t: Int) -> Bool {
  return _type_known(t);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// 2^k for 0 <= k <= 32 (the largest value is 2^32).
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Sign-extend the unsigned value `v` (0 <= v < 2^bits) to a signed Int.
// bits is 8, 16 or 32.
fn _sign_extend(v: Int, bits: Int) -> Int {
  let half = _pow2(bits - 1);
  if v >= half {
    let full = _pow2(bits);
    return v - full;
  }
  return v;
}

// Byte `shift_bytes` of `v` in big-endian order (0 = least significant
// byte), as the exact two's-complement bit pattern. Arithmetic only.
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

// Append one byte (low 8 bits of `b`).
fn _w_push_byte(w: &mut ThriftWriter, b: Int) {
  var q = b % 256;
  if q < 0 { q = q + 256; }
  w.data.push(q as UInt8);
}

// Append the low `size` bytes of `v` in big-endian order (size 1..8).
fn _w_push_be(w: &mut ThriftWriter, v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    w.data.push(_be_byte(v, i));
    i = i - 1;
  }
}

// Append every UTF-8 byte of `s`.
fn _w_push_str(w: &mut ThriftWriter, s: Str) {
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    w.data.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Append every byte of `v`.
fn _w_push_bytes(w: &mut ThriftWriter, v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    w.data.push(v[i]);
    i = i + 1;
  }
}

// A fresh copy of `src` (used where a returned vector must not alias).
fn _copy_bytes(src: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
  return out;
}

// Byte at `pos` widened to 0..255. The caller guarantees the index is in
// bounds.
fn _r_byte(r: &ThriftReader, pos: Int) -> Int {
  return (r.data[pos] as Int) & 0xFF;
}

// Same as _r_byte but takes &mut, so reader bodies never mix a `&` call
// before a `&mut` access on the same local (advisory E001).
fn _r_byte_mut(r: &mut ThriftReader, pos: Int) -> Int {
  return _r_byte(r, pos);
}

// Read `size` (1..4) bytes big-endian into an unsigned Int, advancing the
// cursor. Err("thrift: truncated input") when fewer than `size` bytes
// remain.
fn _read_unsigned(r: &mut ThriftReader, size: Int) -> Result[Int, Str] {
  let total: Int = r.data.len();
  if r.pos + size > total {
    return _err_int("thrift: truncated input");
  }
  var v: Int = 0;
  var i = 0;
  while i < size {
    let b = _r_byte_mut(r, r.pos + i);
    v = v * 256 + b;
    i = i + 1;
  }
  r.pos = r.pos + size;
  return _ok_int(v);
}

// Read 8 bytes big-endian as the exact 64-bit two's-complement pattern.
// The low 63 bits are accumulated (never overflowing) and the top bit is
// applied as a sign afterwards, so every Int64 pattern round-trips.
fn _read64(r: &mut ThriftReader) -> Result[Int, Str] {
  let total: Int = r.data.len();
  if r.pos + 8 > total {
    return _err_int("thrift: truncated input");
  }
  let b0 = _r_byte_mut(r, r.pos);
  let neg = b0 >= 128;
  var v: Int = b0 % 128;
  var i = 1;
  while i < 8 {
    let b = _r_byte_mut(r, r.pos + i);
    v = v * 256 + b;
    i = i + 1;
  }
  r.pos = r.pos + 8;
  if neg {
    v = v - 9223372036854775807 - 1;
  }
  return _ok_int(v);
}

// Read a signed 16-bit big-endian integer.
fn _read_i16(r: &mut ThriftReader) -> Result[Int, Str] {
  let ur = _read_unsigned(r, 2);
  if !ur.is_ok {
    return _err_int(ur.error);
  }
  let v: Int = ur.value;
  return _ok_int(_sign_extend(v, 16));
}

// Read a signed 32-bit big-endian integer.
fn _read_i32(r: &mut ThriftReader) -> Result[Int, Str] {
  let ur = _read_unsigned(r, 4);
  if !ur.is_ok {
    return _err_int(ur.error);
  }
  let v: Int = ur.value;
  return _ok_int(_sign_extend(v, 32));
}

// Read the value of a field whose type is BYTE, I16, I32 or I64. The
// caller guarantees a primitive integer type.
fn _read_int_field(r: &mut ThriftReader, t: Int) -> Result[Int, Str] {
  if t == _T_BYTE {
    let ur = _read_unsigned(r, 1);
    if !ur.is_ok {
      return _err_int(ur.error);
    }
    let v: Int = ur.value;
    return _ok_int(_sign_extend(v, 8));
  }
  if t == _T_I16 {
    return _read_i16(r);
  }
  if t == _T_I32 {
    return _read_i32(r);
  }
  return _read64(r);
}

// Read exactly `n` bytes into a fresh vector, advancing the cursor.
// Err("thrift: truncated input") when `n` bytes are not available.
fn _read_bytes_n(r: &mut ThriftReader, n: Int) -> Result[Vec[UInt8], Str] {
  let total: Int = r.data.len();
  if n < 0 || r.pos + n > total {
    return _err_bytes("thrift: truncated input");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(r.data[r.pos + i]);
    i = i + 1;
  }
  r.pos = r.pos + n;
  return _ok_bytes(out);
}

// The bytes of `v` as a Str. Only called on NUL-free byte vectors that
// were validated at the API boundary, so sb_to_str cannot abort.
fn _bytes_to_str(v: &Vec[UInt8]) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    sb.push(v[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Validation helpers
// --------------------------------------------------

// True for the value type ids the codec understands (see
// `thrift_type_known`); STOP 0 is not included.
fn _type_known(t: Int) -> Bool {
  if t == _T_BOOL || t == _T_BYTE || t == _T_DOUBLE {
    return true;
  }
  if t == _T_I16 || t == _T_I32 || t == _T_I64 {
    return true;
  }
  if t == _T_STRING || t == _T_STRUCT || t == _T_MAP {
    return true;
  }
  return t == _T_SET || t == _T_LIST;
}

// Deterministic message for an unknown type id.
fn _type_msg(t: Int) -> Str {
  return "thrift: unknown type id " + convert.int_to_string(t);
}

// Deterministic message for an unknown message type.
fn _msg_type_msg(t: Int) -> Str {
  return "thrift: unknown message type " + convert.int_to_string(t);
}

// Deterministic message for a negative collection size.
fn _size_msg(n: Int) -> Str {
  return "thrift: bad collection size " + convert.int_to_string(n);
}

// The documented nesting-depth error.
fn _depth_msg() -> Str {
  return "thrift: nesting depth exceeds limit of 64";
}

// True when every byte of a message name is printable ASCII (0x20..0x7E).
fn _name_error(bytes: &Vec[UInt8]) -> Str {
  var i = 0;
  while i < bytes.len() {
    let b: Int = (bytes[i] as Int) & 0xFF;
    if b < 32 || b > 126 {
      return "thrift: invalid message name";
    }
    i = i + 1;
  }
  return "";
}

// UTF-8 validation of a string payload (RFC 3629, strict: overlong forms
// and surrogates are rejected). Returns "" when valid, otherwise the
// deterministic error. A 0x00 byte is valid UTF-8 but is reported
// separately because a NUL would abort the v0.61.3 string builder.
fn _utf8_error(bytes: &Vec[UInt8]) -> Str {
  let n = bytes.len();
  var i = 0;
  while i < n {
    let b: Int = (bytes[i] as Int) & 0xFF;
    if b == 0 {
      return "thrift: string contains nul";
    }
    if b < 128 {
      i = i + 1;
    } elif b < 192 {
      return "thrift: invalid utf-8";
    } elif b < 194 {
      return "thrift: invalid utf-8";
    } elif b < 224 {
      if i + 1 >= n {
        return "thrift: invalid utf-8";
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return "thrift: invalid utf-8";
      }
      i = i + 2;
    } elif b < 240 {
      if i + 2 >= n {
        return "thrift: invalid utf-8";
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      let c2: Int = (bytes[i + 2] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return "thrift: invalid utf-8";
      }
      if c2 < 128 || c2 >= 192 {
        return "thrift: invalid utf-8";
      }
      if b == 224 && c1 < 160 {
        return "thrift: invalid utf-8";
      }
      if b == 237 && c1 >= 160 {
        return "thrift: invalid utf-8";
      }
      i = i + 3;
    } else {
      if b >= 245 {
        return "thrift: invalid utf-8";
      }
      if i + 3 >= n {
        return "thrift: invalid utf-8";
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      let c2: Int = (bytes[i + 2] as Int) & 0xFF;
      let c3: Int = (bytes[i + 3] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return "thrift: invalid utf-8";
      }
      if c2 < 128 || c2 >= 192 {
        return "thrift: invalid utf-8";
      }
      if c3 < 128 || c3 >= 192 {
        return "thrift: invalid utf-8";
      }
      if b == 240 && c1 < 144 {
        return "thrift: invalid utf-8";
      }
      if b == 244 && c1 >= 144 {
        return "thrift: invalid utf-8";
      }
      i = i + 4;
    }
  }
  return "";
}

// --------------------------------------------------
//  Writer and reader lifecycle
// --------------------------------------------------

/// A fresh empty writer. Complexity: O(1).
pub fn thrift_writer_new() -> ThriftWriter {
  return ThriftWriter{ data: Vec[UInt8].new() };
}

/// Number of bytes written so far. Complexity: O(1).
pub fn thrift_writer_len(w: &ThriftWriter) -> Int {
  return w.data.len();
}

/// A copy of the bytes written so far. Complexity: O(written bytes).
pub fn thrift_writer_bytes(w: &ThriftWriter) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < w.data.len() {
    out.push(w.data[i]);
    i = i + 1;
  }
  return out;
}

/// A reader positioned at offset 0 of `data`. Complexity: O(1).
pub fn thrift_reader_new(data: Vec[UInt8]) -> ThriftReader {
  return ThriftReader{ data: data; pos: 0; };
}

/// Current cursor offset. Complexity: O(1).
pub fn thrift_reader_pos(r: &ThriftReader) -> Int {
  return r.pos;
}

/// Bytes left after the cursor (0 when the cursor is at or past the end).
/// Complexity: O(1).
pub fn thrift_reader_remaining(r: &ThriftReader) -> Int {
  let total: Int = r.data.len();
  let rem: Int = total - r.pos;
  if rem < 0 {
    return 0;
  }
  return rem;
}

// --------------------------------------------------
//  Message header
// --------------------------------------------------

/// Write a strict message header: the version word
/// `0x80010000 | msg_type`, the method name as a string, then the int32
/// sequence id. `msg_type` must be one of the `thrift_msg_*` codes;
/// `name` should be a short printable method name (the reader validates
/// that on decode). Complexity: O(name bytes).
pub fn thrift_write_message_begin(w: &mut ThriftWriter, name: Str, msg_type: Int, seqid: Int) {
  _w_push_be(w, _VERSION + msg_type, 4);
  thrift_write_string(w, name);
  _w_push_be(w, seqid, 4);
}

/// Write a legacy (versionless) message header: the method name as a
/// string, one message-type byte, then the int32 sequence id. Provided so
/// the legacy form is testable and reproducible; strict is the form to
/// emit for new callers. Complexity: O(name bytes).
pub fn thrift_write_message_begin_legacy(w: &mut ThriftWriter, name: Str, msg_type: Int, seqid: Int) {
  thrift_write_string(w, name);
  _w_push_byte(w, msg_type);
  _w_push_be(w, seqid, 4);
}

// Validate a decoded name and build the message value. `strict` records
// the wire form.
fn _finish_message(name: &Vec[UInt8], msg_type: Int, seqid: Int, strict: Bool) -> Result[ThriftMessage, Str] {
  let ne = _name_error(name);
  if ne.len() > 0 {
    return _err_msg(ne);
  }
  let nm = _bytes_to_str(name);
  return _ok_msg(ThriftMessage{ name: nm; msg_type: msg_type; seqid: seqid; strict: strict; });
}

/// Decode one message header, strict or legacy.
///
/// A first word with the high bit set is strict: the high 16 bits must be
/// `0x8001` (else "thrift: bad strict version") and the low 16 bits encode
/// the message type 1..4 (else "thrift: unknown message type N"), then
/// follow the name string and the int32 sequence id. A first word with the
/// high bit clear is legacy: it is the u32 name length, followed by the
/// name, one message-type byte and the int32 sequence id.
///
/// Err("thrift: invalid message name") when the name contains a byte
/// outside printable ASCII 0x20..0x7E; Err("thrift: truncated input")
/// whenever the buffer ends inside the header. Complexity: O(header
/// bytes).
pub fn thrift_read_message_begin(r: &mut ThriftReader) -> Result[ThriftMessage, Str] {
  let total: Int = r.data.len();
  if r.pos + 4 > total {
    return _err_msg("thrift: truncated input");
  }
  let hr = _read_unsigned(r, 4);
  if !hr.is_ok {
    return _err_msg(hr.error);
  }
  let head: Int = hr.value;
  if head >= 2147483648 {
    let hi = head / 65536;
    if hi != _VERSION_HI {
      return _err_msg("thrift: bad strict version");
    }
    let lo = head % 65536;
    if lo < 1 || lo > 4 {
      return _err_msg(_msg_type_msg(lo));
    }
    let nr = thrift_read_binary(r);
    if !nr.is_ok {
      return _err_msg(nr.error);
    }
    let name: Vec[UInt8] = nr.value;
    let sq = _read_i32(r);
    if !sq.is_ok {
      return _err_msg(sq.error);
    }
    let seqid: Int = sq.value;
    return _finish_message(&name, lo, seqid, true);
  }
  let nlen: Int = head;
  let remaining: Int = total - r.pos;
  if nlen + 5 > remaining {
    return _err_msg("thrift: truncated input");
  }
  let nr2 = _read_bytes_n(r, nlen);
  if !nr2.is_ok {
    return _err_msg(nr2.error);
  }
  let name2: Vec[UInt8] = nr2.value;
  let tb = _r_byte_mut(r, r.pos);
  r.pos = r.pos + 1;
  if tb < 1 || tb > 4 {
    return _err_msg(_msg_type_msg(tb));
  }
  let sq2 = _read_i32(r);
  if !sq2.is_ok {
    return _err_msg(sq2.error);
  }
  let seqid2: Int = sq2.value;
  return _finish_message(&name2, tb, seqid2, false);
}

// --------------------------------------------------
//  Field header
// --------------------------------------------------

/// Write a field header: one type byte plus the int16 field id (big
/// endian, two's complement). `ftype` must be a value type code;
/// `thrift_write_field_stop` is the struct terminator. Complexity: O(1).
pub fn thrift_write_field_begin(w: &mut ThriftWriter, ftype: Int, fid: Int) {
  _w_push_byte(w, ftype);
  _w_push_be(w, fid, 2);
}

/// Write the STOP byte that terminates a struct. Complexity: O(1).
pub fn thrift_write_field_stop(w: &mut ThriftWriter) {
  _w_push_byte(w, _T_STOP);
}

/// Decode one field header. The STOP byte yields a field with
/// `ftype == thrift_t_stop()` and `fid == 0`; otherwise the type byte is
/// validated (unknown ids are Err("thrift: unknown type id N")) and the
/// signed int16 id is read.
/// Err("thrift: truncated input") when the header is cut short.
/// Complexity: O(1).
pub fn thrift_read_field_begin(r: &mut ThriftReader) -> Result[ThriftField, Str] {
  let total: Int = r.data.len();
  if r.pos >= total {
    return _err_field("thrift: truncated input");
  }
  let t = _r_byte_mut(r, r.pos);
  r.pos = r.pos + 1;
  if t == _T_STOP {
    return _ok_field(ThriftField{ ftype: 0; fid: 0; });
  }
  if !_type_known(t) {
    return _err_field(_type_msg(t));
  }
  let ir = _read_i16(r);
  if !ir.is_ok {
    return _err_field(ir.error);
  }
  let id: Int = ir.value;
  return _ok_field(ThriftField{ ftype: t; fid: id; });
}

// --------------------------------------------------
//  Primitive values
// --------------------------------------------------

/// Write a BOOL as one byte: 1 for true, 0 for false. Complexity: O(1).
pub fn thrift_write_bool(w: &mut ThriftWriter, v: Bool) {
  if v {
    _w_push_byte(w, 1);
  } else {
    _w_push_byte(w, 0);
  }
}

/// Decode a BOOL. Only 0 (false) and 1 (true) are accepted;
/// Err("thrift: invalid bool value") for any other byte and
/// Err("thrift: truncated input") at the end of the buffer.
/// Complexity: O(1).
pub fn thrift_read_bool(r: &mut ThriftReader) -> Result[Bool, Str] {
  let total: Int = r.data.len();
  if r.pos >= total {
    return _err_bool("thrift: truncated input");
  }
  let b = _r_byte_mut(r, r.pos);
  r.pos = r.pos + 1;
  if b == 0 {
    return _ok_bool(false);
  }
  if b == 1 {
    return _ok_bool(true);
  }
  return _err_bool("thrift: invalid bool value");
}

/// Write a BYTE (int8): the low 8 bits of `v`, sign-extended.
/// Complexity: O(1).
pub fn thrift_write_byte(w: &mut ThriftWriter, v: Int) {
  _w_push_be(w, v, 1);
}

/// Decode a signed BYTE (int8, -128..127). Complexity: O(1).
pub fn thrift_read_byte(r: &mut ThriftReader) -> Result[Int, Str] {
  let ur = _read_unsigned(r, 1);
  if !ur.is_ok {
    return _err_int(ur.error);
  }
  let v: Int = ur.value;
  return _ok_int(_sign_extend(v, 8));
}

/// Write an I16 as two big-endian bytes. Complexity: O(1).
pub fn thrift_write_i16(w: &mut ThriftWriter, v: Int) {
  _w_push_be(w, v, 2);
}

/// Decode a signed I16 (-32768..32767). Complexity: O(1).
pub fn thrift_read_i16(r: &mut ThriftReader) -> Result[Int, Str] {
  return _read_i16(r);
}

/// Write an I32 as four big-endian bytes. Complexity: O(1).
pub fn thrift_write_i32(w: &mut ThriftWriter, v: Int) {
  _w_push_be(w, v, 4);
}

/// Decode a signed I32. Complexity: O(1).
pub fn thrift_read_i32(r: &mut ThriftReader) -> Result[Int, Str] {
  return _read_i32(r);
}

/// Write an I64 as eight big-endian bytes. Complexity: O(1).
pub fn thrift_write_i64(w: &mut ThriftWriter, v: Int) {
  _w_push_be(w, v, 8);
}

/// Decode a signed I64 (the full Int range). Complexity: O(1).
pub fn thrift_read_i64(r: &mut ThriftReader) -> Result[Int, Str] {
  return _read64(r);
}

/// Write a DOUBLE as its raw 64-bit IEEE-754 bit pattern (`bits`,
/// big-endian). v0.61.3 has no `Int <-> Float64` bitcast, so the caller
/// supplies the pattern; for example 1.0 is 0x3FF0000000000000.
/// Complexity: O(1).
pub fn thrift_write_double_bits(w: &mut ThriftWriter, bits: Int) {
  _w_push_be(w, bits, 8);
}

/// Decode a DOUBLE as its raw 64-bit IEEE-754 bit pattern. The sign bit is
/// part of the pattern, so patterns with the top bit set come back as the
/// corresponding negative Int (e.g. -2.0 is -4611686018427387904).
/// Complexity: O(1).
pub fn thrift_read_double_bits(r: &mut ThriftReader) -> Result[Int, Str] {
  return _read64(r);
}

/// Write `data` as a STRING: a u32 byte length then the bytes verbatim.
/// No validation is performed. Complexity: O(data bytes).
pub fn thrift_write_binary(w: &mut ThriftWriter, data: &Vec[UInt8]) {
  _w_push_be(w, data.len(), 4);
  _w_push_bytes(w, data);
}

/// Decode a STRING as its raw payload bytes (no UTF-8 or NUL validation;
/// any byte value is accepted). Err("thrift: truncated input") when the
/// length or the payload overruns the buffer. Complexity: O(payload).
pub fn thrift_read_binary(r: &mut ThriftReader) -> Result[Vec[UInt8], Str] {
  let lr = _read_unsigned(r, 4);
  if !lr.is_ok {
    return _err_bytes(lr.error);
  }
  let n: Int = lr.value;
  return _read_bytes_n(r, n);
}

/// Write a Str as a STRING: a u32 UTF-8 byte length then the bytes.
/// `Str` is UTF-8 by construction. Complexity: O(byte length).
pub fn thrift_write_string(w: &mut ThriftWriter, s: Str) {
  _w_push_be(w, string.str_len(s), 4);
  _w_push_str(w, s);
}

/// Decode a STRING as a Str. The payload must be valid UTF-8 with no 0x00
/// byte: Err("thrift: invalid utf-8") for malformed UTF-8 (overlong
/// forms, surrogate halves and truncated sequences included) and
/// Err("thrift: string contains nul") for a NUL byte (which would abort
/// the v0.61.3 string builder). Use `thrift_read_binary` for arbitrary
/// bytes. Complexity: O(payload).
pub fn thrift_read_string(r: &mut ThriftReader) -> Result[Str, Str] {
  let br = thrift_read_binary(r);
  if !br.is_ok {
    return _err_str(br.error);
  }
  let bytes: Vec[UInt8] = br.value;
  let ue = _utf8_error(&bytes);
  if ue.len() > 0 {
    return _err_str(ue);
  }
  return _ok_str(_bytes_to_str(&bytes));
}

// --------------------------------------------------
//  Containers
// --------------------------------------------------

/// Write a LIST header: element type byte plus i32 element count.
/// Complexity: O(1).
pub fn thrift_write_list_begin(w: &mut ThriftWriter, etype: Int, size: Int) {
  _w_push_byte(w, etype);
  _w_push_be(w, size, 4);
}

/// Write a SET header: element type byte plus i32 element count (the same
/// wire layout as a list). Complexity: O(1).
pub fn thrift_write_set_begin(w: &mut ThriftWriter, etype: Int, size: Int) {
  _w_push_byte(w, etype);
  _w_push_be(w, size, 4);
}

/// Write a MAP header: key type byte, value type byte, i32 pair count.
/// Complexity: O(1).
pub fn thrift_write_map_begin(w: &mut ThriftWriter, ktype: Int, vtype: Int, size: Int) {
  _w_push_byte(w, ktype);
  _w_push_byte(w, vtype);
  _w_push_be(w, size, 4);
}

/// Decode a LIST or SET header: element type byte plus i32 element count.
///
/// Err("thrift: unknown type id N") for an unknown element type;
/// Err("thrift: bad collection size N") for a negative count;
/// Err("thrift: oversized collection") when the count exceeds the bytes
/// remaining (every element needs at least one byte);
/// Err("thrift: truncated input") when the header is cut short.
/// Complexity: O(1).
pub fn thrift_read_list_header(r: &mut ThriftReader) -> Result[ThriftListHeader, Str] {
  let total: Int = r.data.len();
  if r.pos >= total {
    return _err_lhdr("thrift: truncated input");
  }
  let et = _r_byte_mut(r, r.pos);
  r.pos = r.pos + 1;
  if !_type_known(et) {
    return _err_lhdr(_type_msg(et));
  }
  let sr = _read_i32(r);
  if !sr.is_ok {
    return _err_lhdr(sr.error);
  }
  let size: Int = sr.value;
  if size < 0 {
    return _err_lhdr(_size_msg(size));
  }
  let remaining: Int = r.data.len() - r.pos;
  if size > remaining {
    return _err_lhdr("thrift: oversized collection");
  }
  return _ok_lhdr(ThriftListHeader{ etype: et; size: size; });
}

/// Decode a SET header. Identical wire layout and errors to
/// `thrift_read_list_header` (the two are indistinguishable on the wire).
/// Complexity: O(1).
pub fn thrift_read_set_header(r: &mut ThriftReader) -> Result[ThriftListHeader, Str] {
  return thrift_read_list_header(r);
}

/// Decode a MAP header: key type byte, value type byte, i32 pair count.
///
/// Err("thrift: unknown type id N") for an unknown key or value type;
/// Err("thrift: bad collection size N") for a negative count;
/// Err("thrift: oversized collection") when the count exceeds half the
/// bytes remaining (every pair needs at least two bytes);
/// Err("thrift: truncated input") when the header is cut short.
/// Complexity: O(1).
pub fn thrift_read_map_header(r: &mut ThriftReader) -> Result[ThriftMapHeader, Str] {
  let total: Int = r.data.len();
  if r.pos >= total {
    return _err_mhdr("thrift: truncated input");
  }
  let kt = _r_byte_mut(r, r.pos);
  r.pos = r.pos + 1;
  if !_type_known(kt) {
    return _err_mhdr(_type_msg(kt));
  }
  if r.pos >= r.data.len() {
    return _err_mhdr("thrift: truncated input");
  }
  let vt = _r_byte_mut(r, r.pos);
  r.pos = r.pos + 1;
  if !_type_known(vt) {
    return _err_mhdr(_type_msg(vt));
  }
  let sr = _read_i32(r);
  if !sr.is_ok {
    return _err_mhdr(sr.error);
  }
  let size: Int = sr.value;
  if size < 0 {
    return _err_mhdr(_size_msg(size));
  }
  let remaining: Int = r.data.len() - r.pos;
  if size > remaining / 2 {
    return _err_mhdr("thrift: oversized collection");
  }
  return _ok_mhdr(ThriftMapHeader{ ktype: kt; vtype: vt; size: size; });
}

// --------------------------------------------------
//  Skip
// --------------------------------------------------

// Consume `size` bytes or fail with truncation; returns bytes consumed
// (equal to `size`), given the start offset `start`.
fn _skip_fixed(r: &mut ThriftReader, size: Int, start: Int) -> Result[Int, Str] {
  let total: Int = r.data.len();
  if r.pos + size > total {
    return _err_int("thrift: truncated input");
  }
  r.pos = r.pos + size;
  return _ok_int(r.pos - start);
}

// Recursive skip of one value of type `ftype` at container depth `depth`.
// Containers count against `thrift_max_depth()`; scalars ignore depth.
fn _skip_value(r: &mut ThriftReader, ftype: Int, depth: Int) -> Result[Int, Str] {
  let start: Int = r.pos;
  if ftype == _T_BOOL {
    return _skip_fixed(r, 1, start);
  }
  if ftype == _T_BYTE {
    return _skip_fixed(r, 1, start);
  }
  if ftype == _T_DOUBLE {
    return _skip_fixed(r, 8, start);
  }
  if ftype == _T_I16 {
    return _skip_fixed(r, 2, start);
  }
  if ftype == _T_I32 {
    return _skip_fixed(r, 4, start);
  }
  if ftype == _T_I64 {
    return _skip_fixed(r, 8, start);
  }
  if ftype == _T_STRING {
    let lr = _read_unsigned(r, 4);
    if !lr.is_ok {
      return _err_int(lr.error);
    }
    let n: Int = lr.value;
    let total: Int = r.data.len();
    if r.pos + n > total {
      return _err_int("thrift: truncated input");
    }
    r.pos = r.pos + n;
    return _ok_int(r.pos - start);
  }
  if ftype == _T_STRUCT {
    if depth >= _MAX_DEPTH {
      return _err_int(_depth_msg());
    }
    var go = true;
    while go {
      let fr = thrift_read_field_begin(r);
      if !fr.is_ok {
        return _err_int(fr.error);
      }
      let f: ThriftField = fr.value;
      if f.ftype == _T_STOP {
        go = false;
      } else {
        let sr = _skip_value(r, f.ftype, depth + 1);
        if !sr.is_ok {
          return _err_int(sr.error);
        }
      }
    }
    return _ok_int(r.pos - start);
  }
  if ftype == _T_MAP {
    if depth >= _MAX_DEPTH {
      return _err_int(_depth_msg());
    }
    let mr = thrift_read_map_header(r);
    if !mr.is_ok {
      return _err_int(mr.error);
    }
    let m: ThriftMapHeader = mr.value;
    var i = 0;
    while i < m.size {
      let kt: Int = m.ktype;
      let vt: Int = m.vtype;
      let ks = _skip_value(r, kt, depth + 1);
      if !ks.is_ok {
        return _err_int(ks.error);
      }
      let vs = _skip_value(r, vt, depth + 1);
      if !vs.is_ok {
        return _err_int(vs.error);
      }
      i = i + 1;
    }
    return _ok_int(r.pos - start);
  }
  if ftype == _T_SET || ftype == _T_LIST {
    if depth >= _MAX_DEPTH {
      return _err_int(_depth_msg());
    }
    let lr2 = thrift_read_list_header(r);
    if !lr2.is_ok {
      return _err_int(lr2.error);
    }
    let h: ThriftListHeader = lr2.value;
    var j = 0;
    while j < h.size {
      let et: Int = h.etype;
      let es = _skip_value(r, et, depth + 1);
      if !es.is_ok {
        return _err_int(es.error);
      }
      j = j + 1;
    }
    return _ok_int(r.pos - start);
  }
  return _err_int(_type_msg(ftype));
}

/// Skip one value of type `ftype` at the cursor and return the number of
/// bytes consumed, recursing through struct, map, list and set values.
///
/// The skip is structural: it validates type ids, bounds and container
/// headers (including the oversized-collection guard), but not scalar
/// values (a skipped BOOL may hold any byte). Err("thrift: unknown type
/// id N") for an unknown `ftype` (STOP included), Err("thrift: truncated
/// input") when the value overruns the buffer, and Err("thrift: nesting
/// depth exceeds limit of 64") when a container is nested deeper than
/// `thrift_max_depth()` (the value passed in has depth 0).
/// Complexity: O(skipped bytes).
pub fn thrift_skip(r: &mut ThriftReader, ftype: Int) -> Result[Int, Str] {
  return _skip_value(r, ftype, 0);
}

// --------------------------------------------------
//  Header accessors
// --------------------------------------------------

/// Method name of a decoded message header. Complexity: O(1).
pub fn thrift_message_name(m: &ThriftMessage) -> Str {
  return m.name;
}

/// Message type of a decoded header (one of the `thrift_msg_*` codes).
/// Complexity: O(1).
pub fn thrift_message_type(m: &ThriftMessage) -> Int {
  return m.msg_type;
}

/// Sequence id of a decoded header. Complexity: O(1).
pub fn thrift_message_seqid(m: &ThriftMessage) -> Int {
  return m.seqid;
}

/// True when the header was in the strict (versioned) form.
/// Complexity: O(1).
pub fn thrift_message_strict(m: &ThriftMessage) -> Bool {
  return m.strict;
}

/// Type code of a decoded field header. Complexity: O(1).
pub fn thrift_field_type(f: &ThriftField) -> Int {
  return f.ftype;
}

/// Field id of a decoded field header. Complexity: O(1).
pub fn thrift_field_id(f: &ThriftField) -> Int {
  return f.fid;
}

/// Element type code of a decoded list or set header. Complexity: O(1).
pub fn thrift_list_header_type(h: &ThriftListHeader) -> Int {
  return h.etype;
}

/// Element count of a decoded list or set header. Complexity: O(1).
pub fn thrift_list_header_size(h: &ThriftListHeader) -> Int {
  return h.size;
}

/// Key type code of a decoded map header. Complexity: O(1).
pub fn thrift_map_header_key_type(h: &ThriftMapHeader) -> Int {
  return h.ktype;
}

/// Value type code of a decoded map header. Complexity: O(1).
pub fn thrift_map_header_value_type(h: &ThriftMapHeader) -> Int {
  return h.vtype;
}

/// Pair count of a decoded map header. Complexity: O(1).
pub fn thrift_map_header_size(h: &ThriftMapHeader) -> Int {
  return h.size;
}

// --------------------------------------------------
//  Flat struct model
// --------------------------------------------------

// Append one field to the four parallel vectors. This is the only place
// that pushes into them, so the vectors can never drift apart.
fn _struct_push_field(ids: &mut Vec[Int], types: &mut Vec[Int], ints: &mut Vec[Int], bytes: &mut Vec[Vec[UInt8]], id: Int, t: Int, iv: Int, payload: &Vec[UInt8]) {
  var copy = Vec[UInt8].new();
  var i = 0;
  while i < payload.len() {
    copy.push(payload[i]);
    i = i + 1;
  }
  ids.push(id);
  types.push(t);
  ints.push(iv);
  bytes.push(copy);
}

// Write an integer-family value of type `t` (BYTE, DOUBLE, I16, I32, I64)
// from the Int `v`. The caller guarantees a known non-bool, non-string
// type.
fn _write_int_value(w: &mut ThriftWriter, t: Int, v: Int) {
  if t == _T_BYTE {
    thrift_write_byte(w, v);
    return;
  }
  if t == _T_DOUBLE {
    thrift_write_double_bits(w, v);
    return;
  }
  if t == _T_I16 {
    thrift_write_i16(w, v);
    return;
  }
  if t == _T_I32 {
    thrift_write_i32(w, v);
    return;
  }
  thrift_write_i64(w, v);
}

/// Decode the remaining fields of one struct (up to and including the
/// STOP byte) into the flat parallel-vector model.
///
/// Depth 0 is the struct itself and nested containers inside field values
/// are not recursed into: a field of type STRUCT, MAP, SET or LIST is
/// Err("thrift: struct field type not supported") because the flat model
/// cannot represent it. Primitive and string fields are read with
/// `_read_int_field` / `thrift_read_bool` / `thrift_read_binary`, so a
/// malformed bool or a truncated value reports that reader's error.
/// Complexity: O(fields + string bytes).
pub fn thrift_read_struct(r: &mut ThriftReader) -> Result[ThriftStruct, Str] {
  var ids = Vec[Int].new();
  var types = Vec[Int].new();
  var ints = Vec[Int].new();
  var bytes = Vec[Vec[UInt8]].new();
  var go = true;
  while go {
    let fr = thrift_read_field_begin(r);
    if !fr.is_ok {
      return _err_struct(fr.error);
    }
    let f: ThriftField = fr.value;
    let t: Int = f.ftype;
    let id: Int = f.fid;
    if t == _T_STOP {
      go = false;
    } elif t == _T_BOOL {
      let bv = thrift_read_bool(r);
      if !bv.is_ok {
        return _err_struct(bv.error);
      }
      var iv = 0;
      if bv.value { iv = 1; }
      let empty = Vec[UInt8].new();
      _struct_push_field(&mut ids, &mut types, &mut ints, &mut bytes, id, t, iv, &empty);
    } elif t == _T_STRING {
      let br = thrift_read_binary(r);
      if !br.is_ok {
        return _err_struct(br.error);
      }
      let payload: Vec[UInt8] = br.value;
      _struct_push_field(&mut ids, &mut types, &mut ints, &mut bytes, id, t, 0, &payload);
    } elif t == _T_DOUBLE {
      let dr = thrift_read_double_bits(r);
      if !dr.is_ok {
        return _err_struct(dr.error);
      }
      let bits: Int = dr.value;
      let empty2 = Vec[UInt8].new();
      _struct_push_field(&mut ids, &mut types, &mut ints, &mut bytes, id, t, bits, &empty2);
    } elif t == _T_BYTE || t == _T_I16 || t == _T_I32 || t == _T_I64 {
      let vr = _read_int_field(r, t);
      if !vr.is_ok {
        return _err_struct(vr.error);
      }
      let v: Int = vr.value;
      let empty3 = Vec[UInt8].new();
      _struct_push_field(&mut ids, &mut types, &mut ints, &mut bytes, id, t, v, &empty3);
    } else {
      return _err_struct("thrift: struct field type not supported");
    }
  }
  return _ok_struct(ThriftStruct{ ids: ids; types: types; ints: ints; bytes: bytes; });
}

/// Encode a flat struct: each field header followed by its value, then the
/// STOP byte.
///
/// The four parallel vectors must have equal length, every type must be a
/// primitive or STRING (BOOL/BYTE/DOUBLE/I16/I32/I64/STRING), a BOOL
/// `ints[i]` must be 0 or 1 and field ids must fit int16.
/// Err("thrift: struct vectors length mismatch"),
/// Err("thrift: field id out of range"),
/// Err("thrift: unknown type id N"),
/// Err("thrift: struct field type not supported") and
/// Err("thrift: invalid bool value") are the only failures.
/// Complexity: O(fields + string bytes).
pub fn thrift_encode_struct(s: &ThriftStruct) -> Result[Vec[UInt8], Str] {
  let n = s.ids.len();
  if s.types.len() != n || s.ints.len() != n || s.bytes.len() != n {
    return _err_bytes("thrift: struct vectors length mismatch");
  }
  var w = ThriftWriter{ data: Vec[UInt8].new() };
  var i = 0;
  while i < n {
    let t: Int = s.types[i];
    let id: Int = s.ids[i];
    if id < _FID_LO || id > _FID_HI {
      return _err_bytes("thrift: field id out of range");
    }
    if !_type_known(t) {
      return _err_bytes(_type_msg(t));
    }
    if t == _T_STRUCT || t == _T_MAP || t == _T_SET || t == _T_LIST {
      return _err_bytes("thrift: struct field type not supported");
    }
    if t == _T_BOOL {
      let bv: Int = s.ints[i];
      if bv != 0 && bv != 1 {
        return _err_bytes("thrift: invalid bool value");
      }
      thrift_write_field_begin(&mut w, t, id);
      thrift_write_bool(&mut w, bv == 1);
    } elif t == _T_STRING {
      let payload: Vec[UInt8] = s.bytes[i];
      thrift_write_field_begin(&mut w, t, id);
      thrift_write_binary(&mut w, &payload);
    } else {
      let v: Int = s.ints[i];
      thrift_write_field_begin(&mut w, t, id);
      _write_int_value(&mut w, t, v);
    }
    i = i + 1;
  }
  thrift_write_field_stop(&mut w);
  let src: Vec[UInt8] = w.data;
  let out = _copy_bytes(&src);
  return _ok_bytes(out);
}

/// Decode exactly one complete struct from `data`: `thrift_read_struct`
/// plus a check that no bytes are left over
/// (Err("thrift: trailing data") otherwise). A struct is terminated by its
/// STOP byte, so the whole buffer must be consumed. Complexity:
/// O(data bytes).
pub fn thrift_decode_struct(data: Vec[UInt8]) -> Result[ThriftStruct, Str] {
  var r = thrift_reader_new(data);
  let sr = thrift_read_struct(&mut r);
  if !sr.is_ok {
    return _err_struct(sr.error);
  }
  if r.pos != r.data.len() {
    return _err_struct("thrift: trailing data");
  }
  let st: ThriftStruct = sr.value;
  return _ok_struct(st);
}

// --------------------------------------------------
//  Flat struct accessors
// --------------------------------------------------

/// Number of fields in a flat struct. Complexity: O(1).
pub fn thrift_struct_count(s: &ThriftStruct) -> Int {
  return s.ids.len();
}

/// Field id at position `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn thrift_struct_id(s: &ThriftStruct, i: Int) -> Int {
  if i < 0 || i >= s.ids.len() {
    return -1;
  }
  let v: Int = s.ids[i];
  return v;
}

/// Type code at position `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn thrift_struct_type(s: &ThriftStruct, i: Int) -> Int {
  if i < 0 || i >= s.types.len() {
    return -1;
  }
  let v: Int = s.types[i];
  return v;
}

/// Integer value at position `i` (BOOL 0/1, BYTE, DOUBLE bit pattern,
/// I16, I32 or I64; 0 for a STRING field), or 0 when `i` is out of range.
/// Check the type first. Complexity: O(1).
pub fn thrift_struct_int(s: &ThriftStruct, i: Int) -> Int {
  if i < 0 || i >= s.ints.len() {
    return 0;
  }
  let v: Int = s.ints[i];
  return v;
}

/// STRING payload at position `i` as a copy, or an empty vector when `i`
/// is out of range or the field is not a string (a valid empty string is
/// therefore indistinguishable from a non-string here; check the type
/// first). Complexity: O(payload length).
pub fn thrift_struct_bytes(s: &ThriftStruct, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= s.bytes.len() {
    return out;
  }
  let v: Vec[UInt8] = s.bytes[i];
  var k = 0;
  while k < v.len() {
    out.push(v[k]);
    k = k + 1;
  }
  return out;
}

/// Position of the first field with id `id`, or -1 when absent. A
/// well-formed struct has unique ids; duplicates keep their wire order and
/// this returns the first one. Complexity: O(fields).
pub fn thrift_struct_field_index(s: &ThriftStruct, id: Int) -> Int {
  var i = 0;
  while i < s.ids.len() {
    let v: Int = s.ids[i];
    if v == id {
      return i;
    }
    i = i + 1;
  }
  return -1;
}
