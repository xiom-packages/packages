// XIOM -- xiom.avro: pure-XIOM Avro 1.11 binary primitives and OCF header
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Avro (spec 1.11) writes primitive values without framing beyond the value
// itself: null is zero bytes, boolean is one octet 0/1, int and long are
// variable-length zig-zag varints, float/double are 4/8 little-endian
// IEEE-754 octets, and bytes/string are a zig-zag length followed by the raw
// payload. This module implements those primitives plus the length-delimited
// compound helpers and the Object Container File (OCF) header, in pure XIOM:
//
//   * `avro_encode_*` producers for every primitive, exact for the full
//     signed 64-bit range (INT64_MIN included) and for the int32 range of
//     `int`;
//   * `avro_read_*` cursor readers for every primitive, with bounds checks
//     and deterministic Err(Str) messages that name the byte offset where
//     the failure was detected;
//   * varint decoding accepts at most 10 bytes, rejects an 11th byte, a
//     10-byte final group above 1 (the 64-bit overflow) and any truncation;
//     non-minimal encodings that still fit 10 bytes are accepted (the Avro
//     spec does not require the shortest form on read);
//   * negative lengths (for example a zig-zag 1 decoding to -1 where a
//     length is expected) are rejected as anomalies with their offset;
//   * compound helpers: fixed(n), enum index, union index, array/map block
//     framing (positive count = entry count, 0 = end of sequence, negative
//     count = byte size of the block, skipped verbatim), record = plain
//     concatenation of encoded fields;
//   * Object Container File header: magic `Obj\x01`, a map<string,bytes>
//     metadata section (keys `avro.schema` and `avro.codec` are surfaced
//     through accessors) and the 16-byte sync marker; the parser validates
//     the magic and reports the exact header length so callers can continue
//     at the first data block;
//   * whole-buffer round-trip helpers (`avro_decode_long`, ...,
//     `avro_decode_array_long`, `avro_decode_map_bytes_long`) that reject
//     trailing bytes.
//
// Non-goals: schema parsing/resolution, the Avro JSON encoding, reading or
// writing data blocks inside an OCF, deflate/snappy codecs, and any FFI.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; all state travels by cursor
//     reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results in other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before arithmetic or comparison, and every
//     Vec[Int] element read is bound to a typed local first.
//   * zig-zag decoding avoids `>>` completely: the varint is accumulated as
//     a non-negative 63-bit part plus a separate bit-63 flag, and the
//     signed value is derived with division and subtraction only.
//   * varint encoding uses division and modulo on non-negative halves
//     (`m >= 0`), so no shift, mask or sign-extension trick is needed.
//   * recursion-free: every reader is a loop or a flat helper.
//   * `&struct.field` is never passed where a `&Vec[UInt8]` parameter is
//     expected (that yields an empty vector); fields are copied into typed
//     locals first.

module xiom.avro

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

// Ok(v) for Result[Vec[Int], Str].
fn _ok_longs(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_longs(m: Str) -> Result[Vec[Int], Str] {
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

// Ok(v) for Result[AvroOcfHeader, Str].
fn _ok_hdr(v: AvroOcfHeader) -> Result[AvroOcfHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[AvroOcfHeader, Str].
fn _err_hdr(m: Str) -> Result[AvroOcfHeader, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Decode cursor over a byte buffer: `pos` is the next unread byte.
///
/// Readers take `&mut AvroCursor` and advance `pos` only on success; on an
/// error `pos` stays where the failure was detected, so the byte offset in
/// the error message is the anomalous position. A cursor never owns data
/// beyond the buffer it was created from.
pub type AvroCursor = {
  data: Vec[UInt8];
  pos: Int;
}

/// Parsed Object Container File header.
///
/// `meta` holds every metadata key and value concatenated; entry `i`'s key
/// is `meta[key_start[i]..key_end[i])` and its value is
/// `meta[val_start[i]..val_end[i])`. `schema_start`/`schema_end` and
/// `codec_start`/`codec_end` are ranges into `meta` for the values of the
/// `avro.schema` and `avro.codec` keys, or -1/-1 when the key is absent (a
/// duplicate key keeps its last occurrence). `sync` is the 16-byte sync
/// marker, and `header_len` is the number of bytes consumed from the start
/// of the buffer (the first data block starts there). Fields are
/// implementation details; use the `avro_ocf_*` accessors.
pub type AvroOcfHeader = {
  meta: Vec[UInt8];
  key_start: Vec[Int];
  key_end: Vec[Int];
  val_start: Vec[Int];
  val_end: Vec[Int];
  schema_start: Int;
  schema_end: Int;
  codec_start: Int;
  codec_end: Int;
  sync: Vec[UInt8];
  header_len: Int;
}

// --------------------------------------------------
//  Constants and metadata
// --------------------------------------------------

/// Version of the Avro specification implemented by this module.
pub fn avro_spec_version() -> Str {
  return "1.11";
}

/// Maximum number of bytes a single long varint may occupy (10, per spec).
pub fn avro_max_varint_bytes() -> Int {
  return 10;
}

/// The four OCF magic bytes: 'O', 'b', 'j' and version 1.
pub fn avro_ocf_magic() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(79 as UInt8);
  out.push(98 as UInt8);
  out.push(106 as UInt8);
  out.push(1 as UInt8);
  return out;
}

/// Size of the OCF sync marker in bytes (16).
pub fn avro_ocf_sync_size() -> Int {
  return 16;
}

// --------------------------------------------------
//  Byte, message and literal helpers
// --------------------------------------------------

// Byte at `pos` of the cursor buffer widened to an Int (0..255). Callers
// guarantee the bounds.
fn _cbyte(cur: &AvroCursor, pos: Int) -> Int {
  return (cur.data[pos] as Int) & 0xFF;
}

// Same as _cbyte but takes &mut, so parser bodies never mix a `&` call
// before a `&mut` access on the same local (advisory E001).
fn _cbyte_mut(cur: &mut AvroCursor, pos: Int) -> Int {
  return _cbyte(cur, pos);
}

// Two lowercase hex digits for a byte value (0..255).
fn _hex2(b: Int) -> Str {
  let digits = "0123456789abcdef";
  let hi = b / 16;
  let lo = b % 16;
  return string.str_slice(digits, hi, hi + 1) + string.str_slice(digits, lo, lo + 1);
}

// The " at offset N" suffix shared by every error message.
fn _at(pos: Int) -> Str {
  return " at offset " + convert.int_to_string(pos);
}

// The documented truncation error.
fn _trunc_msg(pos: Int) -> Str {
  return "avro: truncated input" + _at(pos);
}

// The documented overlong-varint error (more than 10 bytes).
fn _varint_len_msg(start: Int) -> Str {
  return "avro: varint longer than 10 bytes" + _at(start);
}

// The documented 64-bit varint overflow error.
fn _varint_ovf_msg(start: Int) -> Str {
  return "avro: varint overflow" + _at(start);
}

// The documented negative-length anomaly error.
fn _neg_len_msg(n: Int, pos: Int) -> Str {
  return "avro: negative length " + convert.int_to_string(n) + _at(pos);
}

// The documented invalid-boolean error.
fn _bad_bool_msg(b: Int, pos: Int) -> Str {
  return "avro: invalid boolean 0x" + _hex2(b) + _at(pos);
}

// Append every byte of `v` to `out`.
fn _push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Bytes of an ASCII `Str` literal (byte_at indexes bytes).
fn _lit_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    out.push(b);
    i = i + 1;
  }
  return out;
}

// True when the byte vector equals an ASCII `Str` literal, byte for byte.
fn _eq_lit(v: &Vec[UInt8], s: Str) -> Bool {
  if v.len() != string.str_len(s) {
    return false;
  }
  var i = 0;
  while i < v.len() {
    let b: UInt8 = v[i];
    let c: UInt8 = string.byte_at(s, i);
    if ((b as Int) & 0xFF) != ((c as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Cursor
// --------------------------------------------------

/// Create a cursor at offset 0 over `data` (the cursor takes ownership).
pub fn avro_cursor(data: Vec[UInt8]) -> AvroCursor {
  return AvroCursor{
    data: data;
    pos: 0;
  };
}

/// Current cursor position (the next unread byte offset).
pub fn avro_cursor_pos(cur: &AvroCursor) -> Int {
  return cur.pos;
}

/// Total length of the underlying buffer.
pub fn avro_cursor_len(cur: &AvroCursor) -> Int {
  return cur.data.len();
}

/// Number of unread bytes (never negative).
pub fn avro_cursor_remaining(cur: &AvroCursor) -> Int {
  return cur.data.len() - cur.pos;
}

/// True when every byte has been consumed.
pub fn avro_cursor_done(cur: &AvroCursor) -> Bool {
  return cur.pos >= cur.data.len();
}

/// Advance the cursor by `n` bytes.
///
/// Err("avro: negative skip N at offset M") when `n < 0`;
/// Err("avro: truncated input at offset M") when the buffer ends inside the
/// skipped range. On success returns the new position.
pub fn avro_cursor_skip(cur: &mut AvroCursor, n: Int) -> Result[Int, Str] {
  if n < 0 {
    return _err_int("avro: negative skip " + convert.int_to_string(n) + _at(cur.pos));
  }
  if n > cur.data.len() - cur.pos {
    return _err_int(_trunc_msg(cur.pos));
  }
  cur.pos = cur.pos + n;
  return _ok_int(cur.pos);
}

// --------------------------------------------------
//  Varint / zig-zag core
// --------------------------------------------------

// Read one zig-zag varint and return its signed value.
//
// The unsigned 64-bit value U is accumulated as `v` (bits 0..62, always a
// non-negative Int) plus `hi` (bit 63, 0 or 1), so no signed overflow can
// occur. The signed value is then `-((U / 2) + 1)` for odd U (which yields
// INT64_MIN exactly when U = 2^64 - 1) and `U / 2` for even U, computed
// with division and subtraction only (trap 18: `>>` semantics for negative
// Int are not relied upon).
//
// Rejects buffers that end inside the varint ("avro: truncated input" at
// the failing byte), an 11th byte ("avro: varint longer than 10 bytes" at
// the varint start) and a 10-byte group above 1 ("avro: varint overflow").
// Non-minimal encodings of at most 10 bytes are accepted, as the Avro spec
// does not require the shortest form on read.
fn _read_zigzag(cur: &mut AvroCursor) -> Result[Int, Str] {
  let start = cur.pos;
  let total = cur.data.len();
  var v: Int = 0;
  var hi: Int = 0;
  var place: Int = 1;
  var i = 0;
  var done = false;
  while !done {
    if cur.pos >= total {
      return _err_int(_trunc_msg(cur.pos));
    }
    let b = _cbyte_mut(cur, cur.pos);
    cur.pos = cur.pos + 1;
    let payload = b % 128;
    if i < 9 {
      // Little-endian 7-bit groups: byte i contributes payload * 128^i.
      // For i <= 8 the sum cannot exceed 2^63 - 1 (127 * 128^8 plus the
      // lower groups is exactly INT64_MAX), so no overflow check is needed.
      v = v + payload * place;
      if i < 8 {
        place = place * 128;
      }
    } else {
      // 10th byte: a continuation bit means an 11th byte would follow, so
      // the encoding is overlong; otherwise only bit 63 may be set.
      if b >= 128 {
        return _err_int(_varint_len_msg(start));
      }
      if payload > 1 {
        return _err_int(_varint_ovf_msg(start));
      }
      hi = payload;
    }
    i = i + 1;
    if b < 128 {
      done = true;
    } else {
      if i >= 10 {
        return _err_int(_varint_len_msg(start));
      }
    }
  }
  let half = hi * 4611686018427387904 + v / 2;
  if v % 2 == 0 {
    return _ok_int(half);
  }
  return _ok_int(0 - half - 1);
}

// Read a non-negative Int length (zig-zag). `where_pos` is reported in the
// negative-length anomaly.
fn _read_length(cur: &mut AvroCursor) -> Result[Int, Str] {
  let start = cur.pos;
  let r = _read_zigzag(cur);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let n: Int = r.value;
  if n < 0 {
    return _err_int(_neg_len_msg(n, start));
  }
  return _ok_int(n);
}

// --------------------------------------------------
//  Primitive readers
// --------------------------------------------------

/// Read an Avro `null`: consumes zero bytes and always succeeds.
/// Complexity: O(1).
pub fn avro_read_null(cur: &mut AvroCursor) -> Result[Int, Str] {
  return _ok_int(0);
}

/// Read an Avro `boolean`: one octet, 0 for false and 1 for true.
///
/// Err("avro: invalid boolean 0xNN at offset M") for any other octet;
/// Err("avro: truncated input at offset M") on an empty buffer.
/// Complexity: O(1).
pub fn avro_read_boolean(cur: &mut AvroCursor) -> Result[Bool, Str] {
  if cur.pos >= cur.data.len() {
    return _err_bool(_trunc_msg(cur.pos));
  }
  let b = _cbyte_mut(cur, cur.pos);
  if b > 1 {
    return _err_bool(_bad_bool_msg(b, cur.pos));
  }
  cur.pos = cur.pos + 1;
  if b == 0 {
    return _ok_bool(false);
  }
  return _ok_bool(true);
}

/// Read an Avro `long`: a zig-zag varint over the full signed 64-bit range.
/// Errors as documented for `_read_zigzag`.
/// Complexity: O(1).
pub fn avro_read_long(cur: &mut AvroCursor) -> Result[Int, Str] {
  return _read_zigzag(cur);
}

/// Read an Avro `int`: a zig-zag varint that must fit the int32 range.
///
/// Err("avro: int out of range at offset M") when the decoded value is
/// outside [-2^31, 2^31-1], plus the varint errors of `avro_read_long`.
/// Complexity: O(1).
pub fn avro_read_int(cur: &mut AvroCursor) -> Result[Int, Str] {
  let start = cur.pos;
  let r = _read_zigzag(cur);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let n: Int = r.value;
  if n > 2147483647 || n < -2147483648 {
    return _err_int("avro: int out of range" + _at(start));
  }
  return _ok_int(n);
}

/// Read an Avro `bytes` value: zig-zag byte length, then the raw payload.
///
/// Err("avro: negative length N at offset M") when the length decodes
/// negative; Err("avro: truncated input at offset M") when the payload
/// extends past the buffer. The payload is opaque (no UTF-8 validation).
/// Complexity: O(payload length).
pub fn avro_read_bytes(cur: &mut AvroCursor) -> Result[Vec[UInt8], Str] {
  let lr = _read_length(cur);
  if !lr.is_ok {
    return _err_bytes(lr.error);
  }
  let n: Int = lr.value;
  if n > cur.data.len() - cur.pos {
    return _err_bytes(_trunc_msg(cur.pos));
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(cur.data[cur.pos + i]);
    i = i + 1;
  }
  cur.pos = cur.pos + n;
  return _ok_bytes(out);
}

/// Read an Avro `string` payload without decoding it: identical to
/// `avro_read_bytes` (strings are length-prefixed byte sequences).
/// Complexity: O(payload length).
pub fn avro_read_string_bytes(cur: &mut AvroCursor) -> Result[Vec[UInt8], Str] {
  return avro_read_bytes(cur);
}

/// Read an Avro `string` and decode it to `Str`.
///
/// The payload must not contain a 0x00 octet: a NUL byte would truncate the
/// resulting `Str` at runtime, so it is rejected with
/// Err("avro: string contains NUL at offset M") at the payload start. UTF-8
/// is not validated (the caller asserts text semantics); the same errors as
/// `avro_read_bytes` apply first.
/// Complexity: O(payload length).
pub fn avro_read_string(cur: &mut AvroCursor) -> Result[Str, Str] {
  let br = avro_read_bytes(cur);
  if !br.is_ok {
    return _err_str(br.error);
  }
  let bytes: Vec[UInt8] = br.value;
  let payload_start = cur.pos - bytes.len();
  var i = 0;
  while i < bytes.len() {
    let b: UInt8 = bytes[i];
    if ((b as Int) & 0xFF) == 0 {
      return _err_str("avro: string contains NUL" + _at(payload_start + i));
    }
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&bytes));
}

/// Read a `fixed(n)` value: exactly `n` raw octets, no length prefix.
///
/// Err("avro: negative fixed size N at offset M") when `n < 0`;
/// Err("avro: truncated input at offset M") when fewer than `n` bytes
/// remain. `n = 0` succeeds with an empty vector.
/// Complexity: O(n).
pub fn avro_read_fixed(cur: &mut AvroCursor, n: Int) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  if n < 0 {
    return _err_bytes("avro: negative fixed size " + convert.int_to_string(n) + _at(cur.pos));
  }
  if n > cur.data.len() - cur.pos {
    return _err_bytes(_trunc_msg(cur.pos));
  }
  var i = 0;
  while i < n {
    out.push(cur.data[cur.pos + i]);
    i = i + 1;
  }
  cur.pos = cur.pos + n;
  return _ok_bytes(out);
}

/// Read an Avro `float`: 4 little-endian IEEE-754 octets, returned as raw
/// bytes (XIOM v0.61.3 has no Int <-> Float64 bitcast and Vec[Float64] is
/// not allowed, so the caller interprets them).
/// Complexity: O(1).
pub fn avro_read_float(cur: &mut AvroCursor) -> Result[Vec[UInt8], Str] {
  return avro_read_fixed(cur, 4);
}

/// Read an Avro `double`: 8 little-endian IEEE-754 octets, returned as raw
/// bytes (see `avro_read_float`).
/// Complexity: O(1).
pub fn avro_read_double(cur: &mut AvroCursor) -> Result[Vec[UInt8], Str] {
  return avro_read_fixed(cur, 8);
}

/// Read an Avro `enum` index: a zig-zag int that must not be negative.
///
/// Err("avro: negative enum index N at offset M") for a negative value,
/// plus the varint and int32-range errors of `avro_read_int`.
/// Complexity: O(1).
pub fn avro_read_enum_index(cur: &mut AvroCursor) -> Result[Int, Str] {
  let start = cur.pos;
  let r = avro_read_int(cur);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let n: Int = r.value;
  if n < 0 {
    return _err_int("avro: negative enum index " + convert.int_to_string(n) + _at(start));
  }
  return _ok_int(n);
}

/// Read an Avro `union` branch index: a zig-zag long that must not be
/// negative.
///
/// Err("avro: negative union index N at offset M") for a negative value,
/// plus the varint errors of `avro_read_long`.
/// Complexity: O(1).
pub fn avro_read_union_index(cur: &mut AvroCursor) -> Result[Int, Str] {
  let start = cur.pos;
  let r = _read_zigzag(cur);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let n: Int = r.value;
  if n < 0 {
    return _err_int("avro: negative union index " + convert.int_to_string(n) + _at(start));
  }
  return _ok_int(n);
}

// --------------------------------------------------
//  Compound readers
// --------------------------------------------------

/// Read an `array<long>`: a sequence of blocks terminated by a zero count.
///
/// Each block starts with a zig-zag count: positive means that many long
/// items follow; zero ends the sequence; negative means the following
/// `-count` bytes form one block of items that are skipped verbatim (their
/// contents are not validated). The returned vector holds the items of
/// every positive block, in order.
///
/// Err("avro: truncated input at offset M") when a count exceeds the bytes
/// that remain (each item needs at least one byte), when a negative block
/// size exceeds the remaining bytes, or when the buffer ends before the
/// terminating zero; Err("avro: invalid block count at offset M") for the
/// INT64_MIN count anomaly.
/// Complexity: O(decoded items).
pub fn avro_read_array_long(cur: &mut AvroCursor) -> Result[Vec[Int], Str] {
  var out = Vec[Int].new();
  var done = false;
  while !done {
    let bstart = cur.pos;
    let cr = _read_zigzag(cur);
    if !cr.is_ok {
      return _err_longs(cr.error);
    }
    let count: Int = cr.value;
    if count == 0 {
      done = true;
    } elif count > 0 {
      if count > cur.data.len() - cur.pos {
        return _err_longs(_trunc_msg(cur.pos));
      }
      var i = 0;
      while i < count {
        let vr = _read_zigzag(cur);
        if !vr.is_ok {
          return _err_longs(vr.error);
        }
        let v: Int = vr.value;
        out.push(v);
        i = i + 1;
      }
    } else {
      let size = 0 - count;
      if size < 0 {
        return _err_longs("avro: invalid block count" + _at(bstart));
      }
      if size > cur.data.len() - cur.pos {
        return _err_longs(_trunc_msg(cur.pos));
      }
      cur.pos = cur.pos + size;
    }
  }
  return _ok_longs(out);
}

/// Read a `map<bytes, long>` into the two parallel output vectors.
///
/// Blocks follow the same framing as `avro_read_array_long`: positive count
/// = that many key/value pairs, zero = end, negative = `-count` bytes to
/// skip verbatim. Keys are raw bytes (never decoded to `Str`, so NUL bytes
/// are safe) and values are longs. Entries decoded from positive blocks are
/// appended in order; skipped negative blocks contribute no entries, so the
/// returned Int is the number of entries actually decoded. `keys_out` and
/// `values_out` are always extended by the same amount (no drift), and on
/// error they keep the entries decoded before the failure.
///
/// Errors as for `avro_read_array_long`, except that each entry needs at
/// least two bytes (empty key length + empty value varint).
/// Complexity: O(decoded entries).
pub fn avro_read_map_bytes_long(cur: &mut AvroCursor, keys_out: &mut Vec[Vec[UInt8]], vals_out: &mut Vec[Int]) -> Result[Int, Str] {
  var entries: Int = 0;
  var done = false;
  while !done {
    let bstart = cur.pos;
    let cr = _read_zigzag(cur);
    if !cr.is_ok {
      return _err_int(cr.error);
    }
    let count: Int = cr.value;
    if count == 0 {
      done = true;
    } elif count > 0 {
      if count > (cur.data.len() - cur.pos) / 2 {
        return _err_int(_trunc_msg(cur.pos));
      }
      var i = 0;
      while i < count {
        let kr = avro_read_bytes(cur);
        if !kr.is_ok {
          return _err_int(kr.error);
        }
        let vr = _read_zigzag(cur);
        if !vr.is_ok {
          return _err_int(vr.error);
        }
        let kb: Vec[UInt8] = kr.value;
        let v: Int = vr.value;
        keys_out.push(kb);
        vals_out.push(v);
        entries = entries + 1;
        i = i + 1;
      }
    } else {
      let size = 0 - count;
      if size < 0 {
        return _err_int("avro: invalid block count" + _at(bstart));
      }
      if size > cur.data.len() - cur.pos {
        return _err_int(_trunc_msg(cur.pos));
      }
      cur.pos = cur.pos + size;
    }
  }
  return _ok_int(entries);
}

// --------------------------------------------------
//  Whole-buffer decode helpers (no trailing data)
// --------------------------------------------------

// Reject bytes after the value just decoded.
fn _ensure_consumed(cur: &AvroCursor) -> Result[Int, Str] {
  if cur.pos != cur.data.len() {
    return _err_int("avro: trailing data" + _at(cur.pos));
  }
  return _ok_int(cur.pos);
}

/// Decode exactly one `long` and reject trailing bytes.
/// Complexity: O(1).
pub fn avro_decode_long(data: Vec[UInt8]) -> Result[Int, Str] {
  var cur = avro_cursor(data);
  let r = _read_zigzag(&mut cur);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let t = _ensure_consumed(&cur);
  if !t.is_ok {
    return _err_int(t.error);
  }
  return _ok_int(r.value);
}

/// Decode exactly one `int` and reject trailing bytes.
/// Complexity: O(1).
pub fn avro_decode_int(data: Vec[UInt8]) -> Result[Int, Str] {
  var cur = avro_cursor(data);
  let r = avro_read_int(&mut cur);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let t = _ensure_consumed(&cur);
  if !t.is_ok {
    return _err_int(t.error);
  }
  return _ok_int(r.value);
}

/// Decode exactly one `boolean` and reject trailing bytes.
/// Complexity: O(1).
pub fn avro_decode_boolean(data: Vec[UInt8]) -> Result[Bool, Str] {
  var cur = avro_cursor(data);
  let r = avro_read_boolean(&mut cur);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let t = _ensure_consumed(&cur);
  if !t.is_ok {
    return _err_bool(t.error);
  }
  return _ok_bool(r.value);
}

/// Decode exactly one `bytes` value and reject trailing bytes.
/// Complexity: O(payload length).
pub fn avro_decode_bytes(data: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  var cur = avro_cursor(data);
  let r = avro_read_bytes(&mut cur);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  let t = _ensure_consumed(&cur);
  if !t.is_ok {
    return _err_bytes(t.error);
  }
  return _ok_bytes(r.value);
}

/// Decode exactly one `string` (to `Str`) and reject trailing bytes.
/// Complexity: O(payload length).
pub fn avro_decode_string(data: Vec[UInt8]) -> Result[Str, Str] {
  var cur = avro_cursor(data);
  let r = avro_read_string(&mut cur);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let t = _ensure_consumed(&cur);
  if !t.is_ok {
    return _err_str(t.error);
  }
  return _ok_str(r.value);
}

/// Decode exactly one `fixed(n)` value and reject trailing bytes.
/// Complexity: O(n).
pub fn avro_decode_fixed(data: Vec[UInt8], n: Int) -> Result[Vec[UInt8], Str] {
  var cur = avro_cursor(data);
  let r = avro_read_fixed(&mut cur, n);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  let t = _ensure_consumed(&cur);
  if !t.is_ok {
    return _err_bytes(t.error);
  }
  return _ok_bytes(r.value);
}

/// Decode exactly one `float` (4 raw LE octets) and reject trailing bytes.
/// Complexity: O(1).
pub fn avro_decode_float(data: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return avro_decode_fixed(data, 4);
}

/// Decode exactly one `double` (8 raw LE octets) and reject trailing bytes.
/// Complexity: O(1).
pub fn avro_decode_double(data: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return avro_decode_fixed(data, 8);
}

/// Decode exactly one `array<long>` and reject trailing bytes.
/// Complexity: O(decoded items).
pub fn avro_decode_array_long(data: Vec[UInt8]) -> Result[Vec[Int], Str] {
  var cur = avro_cursor(data);
  let r = avro_read_array_long(&mut cur);
  if !r.is_ok {
    return _err_longs(r.error);
  }
  let t = _ensure_consumed(&cur);
  if !t.is_ok {
    return _err_longs(t.error);
  }
  return _ok_longs(r.value);
}

/// Decode exactly one `map<bytes, long>` into the output vectors and reject
/// trailing bytes. See `avro_read_map_bytes_long` for the append semantics.
/// Complexity: O(decoded entries).
pub fn avro_decode_map_bytes_long(data: Vec[UInt8], keys_out: &mut Vec[Vec[UInt8]], vals_out: &mut Vec[Int]) -> Result[Int, Str] {
  var cur = avro_cursor(data);
  let r = avro_read_map_bytes_long(&mut cur, keys_out, vals_out);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let t = _ensure_consumed(&cur);
  if !t.is_ok {
    return _err_int(t.error);
  }
  return _ok_int(r.value);
}

// --------------------------------------------------
//  Primitive encoders
// --------------------------------------------------

/// Encode an Avro `null` as zero bytes.
/// Complexity: O(1).
pub fn avro_encode_null() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  return out;
}

/// Encode an Avro `boolean` as one octet: 0 false / 1 true.
/// Complexity: O(1).
pub fn avro_encode_boolean(b: Bool) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if b {
    out.push(1 as UInt8);
  } else {
    out.push(0 as UInt8);
  }
  return out;
}

/// Encode an Avro `long` as a zig-zag varint, exact for the full signed
/// 64-bit range (INT64_MIN included, which emits the 10-byte all-ones
/// prefix).
///
/// The zig-zag unsigned value is `U = 2*n` for `n >= 0` and `U = -2*n - 1`
/// for `n < 0`; it is emitted as `m = U / 2` (a non-negative Int) plus a
/// parity bit, first group `2*(m % 64) + parity` then 7-bit groups of
/// `m / 64`, all with division and modulo only.
/// Complexity: O(1).
pub fn avro_encode_long(n: Int) -> Vec[UInt8] {
  var m: Int = n;
  var p: Int = 0;
  if n < 0 {
    m = -1 - n;
    p = 1;
  }
  let low6 = m % 64;
  var q = m / 64;
  var g: Int = low6 * 2 + p;
  var out = Vec[UInt8].new();
  if q == 0 {
    out.push(g as UInt8);
    return out;
  }
  out.push((g + 128) as UInt8);
  while q > 0 {
    let low = q % 128;
    q = q / 128;
    if q > 0 {
      out.push((low + 128) as UInt8);
    } else {
      out.push(low as UInt8);
    }
  }
  return out;
}

/// Encode an Avro `int` as a zig-zag varint. The wire form is identical to
/// `avro_encode_long`; the caller is responsible for the int32 range (the
/// reader enforces it with `avro_read_int`).
/// Complexity: O(1).
pub fn avro_encode_int(n: Int) -> Vec[UInt8] {
  return avro_encode_long(n);
}

/// Encode raw bytes as an Avro `bytes` value: zig-zag length + payload.
/// Complexity: O(payload length).
pub fn avro_encode_bytes(bytes: &Vec[UInt8]) -> Vec[UInt8] {
  var out = avro_encode_long(bytes.len());
  _push_vec(&mut out, bytes);
  return out;
}

/// Encode a `Str` as an Avro `string`: zig-zag UTF-8 byte length + the
/// UTF-8 bytes verbatim (`string.str_len` is the byte length). No UTF-8
/// validation is needed for a `Str`.
/// Complexity: O(byte length).
pub fn avro_encode_string(s: Str) -> Vec[UInt8] {
  var out = avro_encode_long(string.str_len(s));
  builder.sb_push_str(&mut out, s);
  return out;
}

/// Encode a `fixed` value: a verbatim copy of its `bytes` (no prefix).
/// Complexity: O(n).
pub fn avro_encode_fixed(bytes: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_vec(&mut out, bytes);
  return out;
}

/// Encode a `float` from its 4 raw little-endian octets.
///
/// Err("avro: float requires 4 bytes, got N") when `bytes.len() != 4`.
/// Complexity: O(1).
pub fn avro_encode_float_le(bytes: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if bytes.len() != 4 {
    return _err_bytes("avro: float requires 4 bytes, got " + convert.int_to_string(bytes.len()));
  }
  return _ok_bytes(avro_encode_fixed(bytes));
}

/// Encode a `double` from its 8 raw little-endian octets.
///
/// Err("avro: double requires 8 bytes, got N") when `bytes.len() != 8`.
/// Complexity: O(1).
pub fn avro_encode_double_le(bytes: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if bytes.len() != 8 {
    return _err_bytes("avro: double requires 8 bytes, got " + convert.int_to_string(bytes.len()));
  }
  return _ok_bytes(avro_encode_fixed(bytes));
}

/// Encode an `enum` symbol index as a zig-zag int.
///
/// Err("avro: negative enum index N") when `i < 0`.
/// Complexity: O(1).
pub fn avro_encode_enum_index(i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 {
    return _err_bytes("avro: negative enum index " + convert.int_to_string(i));
  }
  return _ok_bytes(avro_encode_int(i));
}

/// Encode a `union` branch index as a zig-zag long.
///
/// Err("avro: negative union index N") when `i < 0`.
/// Complexity: O(1).
pub fn avro_encode_union_index(i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 {
    return _err_bytes("avro: negative union index " + convert.int_to_string(i));
  }
  return _ok_bytes(avro_encode_long(i));
}

/// Encode a `record` as the concatenation of its already-encoded field
/// chunks, in order. No validation is performed (the caller composes the
/// record).
/// Complexity: O(total field bytes).
pub fn avro_encode_record(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < parts.len() {
    let part: Vec[UInt8] = parts[i];
    _push_vec(&mut out, &part);
    i = i + 1;
  }
  return out;
}

/// Encode one `array` block: zig-zag item count + each already-encoded
/// item, in order. No terminator is emitted (use `avro_encode_array`).
/// Complexity: O(total item bytes).
pub fn avro_encode_array_block(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var out = avro_encode_long(parts.len());
  var i = 0;
  while i < parts.len() {
    let part: Vec[UInt8] = parts[i];
    _push_vec(&mut out, &part);
    i = i + 1;
  }
  return out;
}

/// Encode a complete `array` as one positive block plus the zero
/// terminator. Chunks are already-encoded items; no validation is
/// performed. An empty array is the zero terminator alone (a zero-count
/// block *is* the terminator, so no second zero is emitted).
/// Complexity: O(total item bytes).
pub fn avro_encode_array(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var out = avro_encode_array_block(parts);
  if parts.len() == 0 {
    return out;
  }
  out.push(0 as UInt8);
  return out;
}

/// Encode one `map` block: zig-zag pair count + each already-encoded key
/// and value, in order. No terminator is emitted (use
/// `avro_encode_map`).
///
/// Err("avro: map keys/values length mismatch") when the two vectors
/// differ in length.
/// Complexity: O(total entry bytes).
pub fn avro_encode_map_block(keys: &Vec[Vec[UInt8]], values: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  if keys.len() != values.len() {
    return _err_bytes("avro: map keys/values length mismatch");
  }
  var out = avro_encode_long(keys.len());
  var i = 0;
  while i < keys.len() {
    let key: Vec[UInt8] = keys[i];
    _push_vec(&mut out, &key);
    let val: Vec[UInt8] = values[i];
    _push_vec(&mut out, &val);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Encode a complete `map` as one positive block plus the zero terminator.
/// An empty map is the zero terminator alone.
///
/// Err("avro: map keys/values length mismatch") when the two vectors
/// differ in length.
/// Complexity: O(total entry bytes).
pub fn avro_encode_map(keys: &Vec[Vec[UInt8]], values: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  let br = avro_encode_map_block(keys, values);
  if !br.is_ok {
    return _err_bytes(br.error);
  }
  let bytes: Vec[UInt8] = br.value;
  if keys.len() == 0 {
    return _ok_bytes(bytes);
  }
  var out = bytes;
  out.push(0 as UInt8);
  return _ok_bytes(out);
}

/// Encode an `array<long>` as a single positive block plus terminator.
/// Complexity: O(items).
pub fn avro_encode_array_long(items: &Vec[Int]) -> Vec[UInt8] {
  var parts = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < items.len() {
    let n: Int = items[i];
    parts.push(avro_encode_long(n));
    i = i + 1;
  }
  return avro_encode_array(&parts);
}

/// Encode a `map<string, long>` as a single positive block plus
/// terminator, preserving insertion order (Avro maps are unordered on the
/// wire, so no sorting is applied). An empty map is the zero terminator
/// alone.
///
/// Err("avro: map keys/values length mismatch") when the two vectors
/// differ in length.
/// Complexity: O(entries).
pub fn avro_encode_map_of_longs(keys: &Vec[Str], values: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  if keys.len() != values.len() {
    return _err_bytes("avro: map keys/values length mismatch");
  }
  var out = avro_encode_long(keys.len());
  if keys.len() == 0 {
    return _ok_bytes(out);
  }
  var i = 0;
  while i < keys.len() {
    let k: Str = keys[i];
    let ekey = avro_encode_string(k);
    _push_vec(&mut out, &ekey);
    let v: Int = values[i];
    let eval = avro_encode_long(v);
    _push_vec(&mut out, &eval);
    i = i + 1;
  }
  out.push(0 as UInt8);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Object Container File header
// --------------------------------------------------

// Assemble the parsed header struct (kept separate so the parser function
// only ever calls the _ok_hdr leaf constructor).
fn _finish_hdr(meta: Vec[UInt8], key_start: Vec[Int], key_end: Vec[Int], val_start: Vec[Int], val_end: Vec[Int], schema_start: Int, schema_end: Int, codec_start: Int, codec_end: Int, sync: Vec[UInt8], header_len: Int) -> AvroOcfHeader {
  return AvroOcfHeader{
    meta: meta;
    key_start: key_start;
    key_end: key_end;
    val_start: val_start;
    val_end: val_end;
    schema_start: schema_start;
    schema_end: schema_end;
    codec_start: codec_start;
    codec_end: codec_end;
    sync: sync;
    header_len: header_len;
  };
}

/// Parse an Object Container File header from the start of `data`.
///
/// Layout: magic 'O' 'b' 'j' 0x01, then the file metadata as a
/// map<string,bytes> using the same block framing as every Avro map
/// (positive count = pairs, zero = end, negative = bytes to skip), then the
/// 16-byte sync marker. `avro.schema` and `avro.codec` values are recorded
/// by offset (last occurrence wins for duplicates) and exposed through the
/// `avro_ocf_*` accessors; all other keys stay available through
/// `avro_ocf_metadata_key`/`avro_ocf_metadata_value`. Keys and values are
/// raw bytes (no UTF-8 validation).
///
/// Err("avro: bad magic at offset 0") when any of the four magic bytes is
/// wrong (including a version other than 1); Err("avro: truncated input at
/// offset M") when the buffer ends inside the magic, the metadata or the
/// sync marker; metadata block and entry errors as for
/// `avro_read_map_bytes_long` (negative lengths, overlong varints, ...).
/// Complexity: O(header bytes).
pub fn avro_parse_ocf_header(data: Vec[UInt8]) -> Result[AvroOcfHeader, Str] {
  var cur = avro_cursor(data);
  if cur.data.len() < 4 {
    return _err_hdr(_trunc_msg(0));
  }
  let b0 = _cbyte_mut(&mut cur, 0);
  let b1 = _cbyte_mut(&mut cur, 1);
  let b2 = _cbyte_mut(&mut cur, 2);
  let b3 = _cbyte_mut(&mut cur, 3);
  if b0 != 79 || b1 != 98 || b2 != 106 || b3 != 1 {
    return _err_hdr("avro: bad magic at offset 0");
  }
  cur.pos = 4;
  var meta = Vec[UInt8].new();
  var ks = Vec[Int].new();
  var ke = Vec[Int].new();
  var vs = Vec[Int].new();
  var ve = Vec[Int].new();
  var schema_start = -1;
  var schema_end = -1;
  var codec_start = -1;
  var codec_end = -1;
  var done = false;
  while !done {
    let bstart = cur.pos;
    let cr = _read_zigzag(&mut cur);
    if !cr.is_ok {
      return _err_hdr(cr.error);
    }
    let count: Int = cr.value;
    if count == 0 {
      done = true;
    } elif count > 0 {
      if count > (cur.data.len() - cur.pos) / 2 {
        return _err_hdr(_trunc_msg(cur.pos));
      }
      var i = 0;
      while i < count {
        let kr = avro_read_bytes(&mut cur);
        if !kr.is_ok {
          return _err_hdr(kr.error);
        }
        let kb: Vec[UInt8] = kr.value;
        let vr = avro_read_bytes(&mut cur);
        if !vr.is_ok {
          return _err_hdr(vr.error);
        }
        let vb: Vec[UInt8] = vr.value;
        let kfrom = meta.len();
        _push_vec(&mut meta, &kb);
        let kto = meta.len();
        ks.push(kfrom);
        ke.push(kto);
        let vfrom = meta.len();
        _push_vec(&mut meta, &vb);
        let vto = meta.len();
        vs.push(vfrom);
        ve.push(vto);
        if _eq_lit(&kb, "avro.schema") {
          schema_start = vfrom;
          schema_end = vto;
        }
        if _eq_lit(&kb, "avro.codec") {
          codec_start = vfrom;
          codec_end = vto;
        }
        i = i + 1;
      }
    } else {
      let size = 0 - count;
      if size < 0 {
        return _err_hdr("avro: invalid block count" + _at(bstart));
      }
      if size > cur.data.len() - cur.pos {
        return _err_hdr(_trunc_msg(cur.pos));
      }
      cur.pos = cur.pos + size;
    }
  }
  let sr = avro_read_fixed(&mut cur, 16);
  if !sr.is_ok {
    return _err_hdr(sr.error);
  }
  let sync: Vec[UInt8] = sr.value;
  return _ok_hdr(_finish_hdr(meta, ks, ke, vs, ve, schema_start, schema_end, codec_start, codec_end, sync, cur.pos));
}

/// Number of bytes the header occupies; the first data block starts at this
/// offset.
/// Complexity: O(1).
pub fn avro_ocf_header_len(hdr: &AvroOcfHeader) -> Int {
  return hdr.header_len;
}

/// Number of metadata entries decoded from positive blocks (entries in
/// negative skipped blocks are not visible).
/// Complexity: O(1).
pub fn avro_ocf_metadata_count(hdr: &AvroOcfHeader) -> Int {
  return hdr.key_start.len();
}

/// Copy of metadata entry `i`'s key bytes, or an empty vector when `i` is
/// out of range (a valid empty key is indistinguishable; check the count
/// first).
/// Complexity: O(key length).
pub fn avro_ocf_metadata_key(hdr: &AvroOcfHeader, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= hdr.key_start.len() {
    return out;
  }
  let from: Int = hdr.key_start[i];
  let to: Int = hdr.key_end[i];
  let meta: Vec[UInt8] = hdr.meta;
  var k = from;
  while k < to {
    out.push(meta[k]);
    k = k + 1;
  }
  return out;
}

/// Copy of metadata entry `i`'s value bytes, or an empty vector when `i` is
/// out of range (a valid empty value is indistinguishable; check the count
/// first).
/// Complexity: O(value length).
pub fn avro_ocf_metadata_value(hdr: &AvroOcfHeader, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= hdr.val_start.len() {
    return out;
  }
  let from: Int = hdr.val_start[i];
  let to: Int = hdr.val_end[i];
  let meta: Vec[UInt8] = hdr.meta;
  var k = from;
  while k < to {
    out.push(meta[k]);
    k = k + 1;
  }
  return out;
}

/// Index of the metadata entry whose key equals `key` byte for byte, or -1
/// when absent. Linear scan in decode order; keys are compared as unsigned
/// bytes.
/// Complexity: O(entries * key length).
pub fn avro_ocf_metadata_find(hdr: &AvroOcfHeader, key: &Vec[UInt8]) -> Int {
  let meta: Vec[UInt8] = hdr.meta;
  let klen = key.len();
  var i = 0;
  while i < hdr.key_start.len() {
    let from: Int = hdr.key_start[i];
    let to: Int = hdr.key_end[i];
    if to - from == klen {
      var same = true;
      var j = 0;
      while j < klen {
        let a: UInt8 = meta[from + j];
        let b: UInt8 = key[j];
        if ((a as Int) & 0xFF) != ((b as Int) & 0xFF) {
          same = false;
        }
        j = j + 1;
      }
      if same {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Copy of the `avro.schema` metadata value, or an empty vector when the
/// key is absent.
/// Complexity: O(value length).
pub fn avro_ocf_schema(hdr: &AvroOcfHeader) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if hdr.schema_start < 0 {
    return out;
  }
  let from: Int = hdr.schema_start;
  let to: Int = hdr.schema_end;
  let meta: Vec[UInt8] = hdr.meta;
  var k = from;
  while k < to {
    out.push(meta[k]);
    k = k + 1;
  }
  return out;
}

/// Copy of the `avro.codec` metadata value (for example the bytes "null" or
/// "deflate"), or an empty vector when the key is absent.
/// Complexity: O(value length).
pub fn avro_ocf_codec(hdr: &AvroOcfHeader) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if hdr.codec_start < 0 {
    return out;
  }
  let from: Int = hdr.codec_start;
  let to: Int = hdr.codec_end;
  let meta: Vec[UInt8] = hdr.meta;
  var k = from;
  while k < to {
    out.push(meta[k]);
    k = k + 1;
  }
  return out;
}

/// The `avro.codec` metadata value, defaulting to the bytes "null" when the
/// key is absent (the spec treats a missing codec as the null codec).
/// Complexity: O(value length).
pub fn avro_ocf_codec_or_null(hdr: &AvroOcfHeader) -> Vec[UInt8] {
  if hdr.codec_start < 0 {
    return _lit_bytes("null");
  }
  return avro_ocf_codec(hdr);
}

/// Copy of the 16-byte sync marker.
/// Complexity: O(1).
pub fn avro_ocf_sync(hdr: &AvroOcfHeader) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let sync: Vec[UInt8] = hdr.sync;
  var i = 0;
  while i < sync.len() {
    out.push(sync[i]);
    i = i + 1;
  }
  return out;
}

/// Sync marker byte `i` widened to an Int, or -1 when out of range.
/// Complexity: O(1).
pub fn avro_ocf_sync_byte(hdr: &AvroOcfHeader, i: Int) -> Int {
  let sync: Vec[UInt8] = hdr.sync;
  if i < 0 || i >= sync.len() {
    return -1;
  }
  let b: UInt8 = sync[i];
  return (b as Int) & 0xFF;
}
