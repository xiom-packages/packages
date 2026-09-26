// XIOM -- xiom.amqp: AMQP 0-9-1 frame codec for a documented subset
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no session state) parser and serializer for
// AMQP 0-9-1 wire frames. In scope:
//   * the 8-byte protocol header ("AMQP", 0x00, major 0, minor 9, revision 1;
//     the parser also accepts the 0-9 revision 0 header),
//   * the generic frame header (type octet, channel u16, payload size u32,
//     payload, frame-end 0xCE) with frame-max enforcement,
//   * method frames (class-id u16, method-id u16, schema-driven arguments:
//     octet, short, long, long-long, shortstr, longstr, field-table,
//     field-array and LSB-first packed bits) for the connection, channel,
//     basic, queue and exchange methods listed in SPEC.md,
//   * content header frames (class-id, weight, body-size u64, property flags
//     and the basic properties),
//   * body frames and heartbeat frames,
//   * round-trip serialization of every decoded frame.
// Field tables and arrays decode recursively into a flat token-stream tree
// (see AmqpTree) supporting the field-value tags t/f/s/I/l/D/b/A/T/F/V/x.
// Malformed input is rejected with deterministic Err(Str) messages; see
// SPEC.md for the byte layout tables, the error catalog and the limitations.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] widens with `(data[pos] as Int) &
//     0xFF` before it enters Int arithmetic or comparisons.
//   * struct fields that are Vec[UInt8] are bound to typed locals before
//     they are passed by reference (`&struct.field` misbehaves).
//   * Vec reads are bound to typed locals; no `==` is applied to a Str read
//     from a Vec.
//   * no indexed call tables: method schemas are selected by if/else chains
//     and stored as plain Vec[Int] data.
//   * all numeric widths are split with division/modulo, never bit shifts.

module xiom.amqp

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Decoded generic frame header. `payload_size` is the value from the wire,
/// `payload_start` is the offset of the first payload byte (always 7) and
/// `frame_len` is the total encoded frame size (`8 + payload_size`).
pub type AmqpFrameHeader = {
  frame_type: Int;
  channel: Int;
  payload_size: Int;
  payload_start: Int;
  frame_len: Int;
}

/// Decoded argument / field value stream in document order (pre-order). All
/// five vectors are index-aligned; never push to one without the others.
///
/// `kinds[i]` is one of:
///   1 octet, 2 short, 3 long, 4 long-long, 5 shortstr, 6 longstr, 7 table,
///   8 array, 9 bit,
///   20 field bool (t), 21 field float bits (f), 22 field short (s),
///   23 field long (I), 24 field long-long (l), 25 field decimal (D),
///   26 field byte (b), 28 field timestamp (T), 30 field void (V),
///   31 field byte-array (x),
///   99 end-of-container marker.
///
/// A node's children follow it immediately and end before the matching
/// `kind == 99` marker; `keys[i]` carries the shortstr key when the node is
/// an entry of a field table (empty otherwise, including array elements).
/// `ints[i]` carries the integer value (octet/short/long/long-long/bit/bool/
/// short/long/long-long/byte/timestamp, raw IEEE-754 bits for float,
/// signed 32-bit value for decimal). `aux[i]` carries the decimal scale.
/// `strs[i]` carries the payload of shortstr/longstr/byte-array nodes.
pub type AmqpTree = {
  kinds: Vec[Int];
  keys: Vec[Vec[UInt8]];
  ints: Vec[Int];
  aux: Vec[Int];
  strs: Vec[Vec[UInt8]];
}

/// Decoded method frame: the frame channel plus the method identity and its
/// decoded argument stream. `args` holds one top-level node per schema
/// argument, in schema order (see `amqp_method_schema`).
pub type AmqpMethodFrame = {
  channel: Int;
  class_id: Int;
  method_id: Int;
  args: AmqpTree;
}

/// Decoded content header frame for class 60 (basic). `flags` is the raw
/// 16-bit property flag word (bit 15 = content-type ... bit 3 = app-id);
/// values whose flag bit is clear are decoded as empty/zero.
pub type AmqpContentHeader = {
  channel: Int;
  class_id: Int;
  weight: Int;
  body_size: Int;
  flags: Int;
  content_type: Vec[UInt8];
  content_encoding: Vec[UInt8];
  headers: AmqpTree;
  delivery_mode: Int;
  priority: Int;
  correlation_id: Vec[UInt8];
  reply_to: Vec[UInt8];
  expiration: Vec[UInt8];
  message_id: Vec[UInt8];
  timestamp: Int;
  msg_type: Vec[UInt8];
  user_id: Vec[UInt8];
  app_id: Vec[UInt8];
}

/// Decoded body frame: the frame channel and the opaque body chunk.
pub type AmqpBodyFrame = {
  channel: Int;
  body: Vec[UInt8];
}

/// Decoded heartbeat frame. Only channel 0 with an empty payload is valid.
pub type AmqpHeartbeat = {
  channel: Int;
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

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
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
fn _ok_schema(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_schema(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[AmqpFrameHeader, Str].
fn _ok_fh(v: AmqpFrameHeader) -> Result[AmqpFrameHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[AmqpFrameHeader, Str].
fn _err_fh(m: Str) -> Result[AmqpFrameHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[AmqpMethodFrame, Str].
fn _ok_mf(v: AmqpMethodFrame) -> Result[AmqpMethodFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[AmqpMethodFrame, Str].
fn _err_mf(m: Str) -> Result[AmqpMethodFrame, Str] {
  return Err(m);
}

// Ok(v) for Result[AmqpContentHeader, Str].
fn _ok_ch(v: AmqpContentHeader) -> Result[AmqpContentHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[AmqpContentHeader, Str].
fn _err_ch(m: Str) -> Result[AmqpContentHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[AmqpBodyFrame, Str].
fn _ok_bf(v: AmqpBodyFrame) -> Result[AmqpBodyFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[AmqpBodyFrame, Str].
fn _err_bf(m: Str) -> Result[AmqpBodyFrame, Str] {
  return Err(m);
}

// Ok(v) for Result[AmqpHeartbeat, Str].
fn _ok_hb(v: AmqpHeartbeat) -> Result[AmqpHeartbeat, Str] {
  return Ok(v);
}

// Err(m) for Result[AmqpHeartbeat, Str].
fn _err_hb(m: Str) -> Result[AmqpHeartbeat, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Public constants and tag accessors
// --------------------------------------------------

/// Default frame-max applied by callers: 131072 payload bytes (the AMQP
/// 0-9-1 server default). The codec compares it against the payload size,
/// not the total frame size; callers may pass `negotiated - 8`.
pub fn amqp_default_frame_max() -> Int {
  return 131072;
}

/// The frame-end octet every frame closes with (0xCE).
pub fn amqp_frame_end_marker() -> Int {
  return 206;
}

/// Frame type 1: method frame.
pub fn amqp_frame_method() -> Int {
  return 1;
}

/// Frame type 2: content header frame.
pub fn amqp_frame_header() -> Int {
  return 2;
}

/// Frame type 3: body frame.
pub fn amqp_frame_body() -> Int {
  return 3;
}

/// Frame type 8: heartbeat frame.
pub fn amqp_frame_heartbeat() -> Int {
  return 8;
}

/// Method argument type: octet (u8).
pub fn amqp_argtype_octet() -> Int {
  return 1;
}

/// Method argument type: short (u16).
pub fn amqp_argtype_short() -> Int {
  return 2;
}

/// Method argument type: long (u32).
pub fn amqp_argtype_long() -> Int {
  return 3;
}

/// Method argument type: long-long (u64, restricted to 0..2^63-1).
pub fn amqp_argtype_longlong() -> Int {
  return 4;
}

/// Method argument type: shortstr (u8 length + bytes).
pub fn amqp_argtype_shortstr() -> Int {
  return 5;
}

/// Method argument type: longstr (u32 length + bytes).
pub fn amqp_argtype_longstr() -> Int {
  return 6;
}

/// Method argument type: field table (u32 byte length + keyed entries).
pub fn amqp_argtype_table() -> Int {
  return 7;
}

/// Method argument type: field array (u32 byte length + tagged values).
pub fn amqp_argtype_array() -> Int {
  return 8;
}

/// Method argument type: bit (LSB-first packed, one bit per node).
pub fn amqp_argtype_bit() -> Int {
  return 9;
}

/// Tree kind: end-of-container marker.
pub fn amqp_kind_end() -> Int {
  return 99;
}

/// Tree kind: field value bool (tag 't').
pub fn amqp_kind_f_bool() -> Int {
  return 20;
}

/// Tree kind: field value float (tag 'f', raw IEEE-754 bits in `ints`).
pub fn amqp_kind_f_float() -> Int {
  return 21;
}

/// Tree kind: field value short (tag 's', signed 16-bit).
pub fn amqp_kind_f_short() -> Int {
  return 22;
}

/// Tree kind: field value long (tag 'I', signed 32-bit).
pub fn amqp_kind_f_long() -> Int {
  return 23;
}

/// Tree kind: field value long-long (tag 'l', signed 64-bit).
pub fn amqp_kind_f_longlong() -> Int {
  return 24;
}

/// Tree kind: field value decimal (tag 'D', scale in `aux`).
pub fn amqp_kind_f_decimal() -> Int {
  return 25;
}

/// Tree kind: field value byte (tag 'b', signed 8-bit).
pub fn amqp_kind_f_byte() -> Int {
  return 26;
}

/// Tree kind: field value timestamp (tag 'T', u64 seconds).
pub fn amqp_kind_f_timestamp() -> Int {
  return 28;
}

/// Tree kind: field value void (tag 'V').
pub fn amqp_kind_f_void() -> Int {
  return 30;
}

/// Tree kind: field value byte array (tag 'x', u32 length + bytes).
pub fn amqp_kind_f_bytes() -> Int {
  return 31;
}

// --------------------------------------------------
//  Internal scalar helpers
// --------------------------------------------------

// 2^n for 0 <= n <= 62.
fn _pow2(n: Int) -> Int {
  var r = 1;
  var i = 0;
  while i < n {
    r = r * 2;
    i = i + 1;
  }
  return r;
}

// True when bit `bit` (0 = LSB) is set in `flags`.
fn _bit_set(flags: Int, bit: Int) -> Bool {
  return (flags / _pow2(bit)) % 2 == 1;
}

// Largest value this codec transports in a 64-bit unsigned slot (2^63 - 1).
fn _max_i63() -> Int {
  return 9223372036854775807;
}

// Smallest Int (-2^63).
fn _min_i64() -> Int {
  return -9223372036854775807 - 1;
}

/// The property flag word bit for basic property `index`: 0 = content-type
/// (bit 15) through 12 = app-id (bit 3). Out-of-range indices return 0.
pub fn amqp_basic_flag(index: Int) -> Int {
  if index < 0 || index > 15 {
    return 0;
  }
  return _pow2(15 - index);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian u16 at [pos, pos+2); callers guarantee the bounds.
fn _read_u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Unsigned big-endian u32 at [pos, pos+4); callers guarantee the bounds.
fn _read_u32(data: &Vec[UInt8], pos: Int) -> Int {
  return _read_u16(data, pos) * 65536 + _read_u16(data, pos + 2);
}

// Unsigned big-endian u64 at [pos, pos+8) restricted to 0..2^63-1.
fn _read_u64_checked(data: &Vec[UInt8], pos: Int) -> Result[Int, Str] {
  let hi = _read_u32(data, pos);
  if hi >= 2147483648 {
    return _err_int("amqp: integer out of range");
  }
  let lo = _read_u32(data, pos + 4);
  return _ok_int(hi * 4294967296 + lo);
}

// Signed big-endian i64 at [pos, pos+8); the full Int range is supported,
// including -2^63.
fn _read_i64_checked(data: &Vec[UInt8], pos: Int) -> Result[Int, Str] {
  let hi = _read_u32(data, pos);
  let lo = _read_u32(data, pos + 4);
  if hi < 2147483648 {
    return _ok_int(hi * 4294967296 + lo);
  }
  let mag_hi = 4294967296 - hi;
  if mag_hi == 2147483648 && lo == 0 {
    return _ok_int(_min_i64());
  }
  let mag = mag_hi * 4294967296 - lo;
  return _ok_int(0 - mag);
}

// Signed i8 at `pos`; callers guarantee the bounds.
fn _read_i8(data: &Vec[UInt8], pos: Int) -> Int {
  let b = _byte(data, pos);
  if b >= 128 {
    return b - 256;
  }
  return b;
}

// Signed i16 at [pos, pos+2); callers guarantee the bounds.
fn _read_i16(data: &Vec[UInt8], pos: Int) -> Int {
  let v = _read_u16(data, pos);
  if v >= 32768 {
    return v - 65536;
  }
  return v;
}

// Signed i32 at [pos, pos+4); callers guarantee the bounds.
fn _read_i32(data: &Vec[UInt8], pos: Int) -> Int {
  let v = _read_u32(data, pos);
  if v >= 2147483648 {
    return v - 4294967296;
  }
  return v;
}

// Append `v` (0..65535) as two big-endian bytes.
fn _push_u16(out: &mut Vec[UInt8], v: Int) {
  out.push((v / 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Append `v` (0..4294967295) as four big-endian bytes.
fn _push_u32(out: &mut Vec[UInt8], v: Int) {
  _push_u16(out, v / 65536);
  _push_u16(out, v % 65536);
}

// Append `v` (0..2^63-1) as eight big-endian bytes.
fn _push_u64(out: &mut Vec[UInt8], v: Int) {
  _push_u32(out, v / 4294967296);
  _push_u32(out, v % 4294967296);
}

// Append `v` (-128..127) as one byte.
fn _push_i8(out: &mut Vec[UInt8], v: Int) {
  if v < 0 {
    out.push((v + 256) as UInt8);
  } else {
    out.push(v as UInt8);
  }
}

// Append `v` (-32768..32767) as two big-endian bytes.
fn _push_i16(out: &mut Vec[UInt8], v: Int) {
  if v < 0 {
    _push_u16(out, v + 65536);
  } else {
    _push_u16(out, v);
  }
}

// Append `v` (-2^31..2^31-1) as four big-endian bytes.
fn _push_i32(out: &mut Vec[UInt8], v: Int) {
  if v < 0 {
    _push_u32(out, v + 4294967296);
  } else {
    _push_u32(out, v);
  }
}

// Append `v` (full Int range) as eight big-endian bytes (two's complement).
fn _push_i64(out: &mut Vec[UInt8], v: Int) {
  if v >= 0 {
    _push_u64(out, v);
    return;
  }
  if v == _min_i64() {
    _push_u32(out, 2147483648);
    _push_u32(out, 0);
    return;
  }
  let mag = 0 - v;
  let mag_hi = mag / 4294967296;
  let mag_lo = mag % 4294967296;
  if mag_lo == 0 {
    _push_u32(out, 4294967296 - mag_hi);
    _push_u32(out, 0);
  } else {
    _push_u32(out, 4294967296 - mag_hi - 1);
    _push_u32(out, 4294967296 - mag_lo);
  }
}

// Append every byte of `v` to `out`.
fn _push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// A fresh copy of `v`.
fn _vec_copy(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_vec(&mut out, v);
  return out;
}

// Byte-wise equality of two byte vectors.
fn _bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Read a u8-length-prefixed shortstr from [pos, end) into `out`.
// Err("amqp: truncated string") when the prefix or the bytes do not fit.
fn _read_shortstr(data: &Vec[UInt8], pos: Int, end: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  if pos + 1 > end {
    return _err_int("amqp: truncated string");
  }
  let len = _byte(data, pos);
  let start = pos + 1;
  if start + len > end {
    return _err_int("amqp: truncated string");
  }
  var i = 0;
  while i < len {
    out.push(data[start + i]);
    i = i + 1;
  }
  return _ok_int(start + len);
}

// Read a u32-length-prefixed longstr from [pos, end) into `out`.
// Err("amqp: truncated string") when the prefix or the bytes do not fit.
fn _read_longstr(data: &Vec[UInt8], pos: Int, end: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  if pos + 4 > end {
    return _err_int("amqp: truncated string");
  }
  let len = _read_u32(data, pos);
  let start = pos + 4;
  if len > end - start {
    return _err_int("amqp: truncated string");
  }
  var i = 0;
  while i < len {
    out.push(data[start + i]);
    i = i + 1;
  }
  return _ok_int(start + len);
}

// Append a shortstr (u8 length + bytes). Err("amqp: string too long") when
// `s` exceeds 255 bytes.
fn _push_shortstr_checked(out: &mut Vec[UInt8], s: &Vec[UInt8]) -> Result[Unit, Str] {
  if s.len() > 255 {
    return _err_unit("amqp: string too long");
  }
  out.push(s.len() as UInt8);
  _push_vec(out, s);
  return _ok_unit();
}

// Append a longstr (u32 length + bytes). Err("amqp: string too long") when
// `s` exceeds 2^31-1 bytes.
fn _push_longstr_checked(out: &mut Vec[UInt8], s: &Vec[UInt8]) -> Result[Unit, Str] {
  if s.len() > 2147483647 {
    return _err_unit("amqp: string too long");
  }
  _push_u32(out, s.len());
  _push_vec(out, s);
  return _ok_unit();
}

// --------------------------------------------------
//  Protocol header
// --------------------------------------------------

/// Serialize the canonical AMQP 0-9-1 protocol header:
/// "AMQP" 0x00 0x00 0x09 0x01. Complexity: O(1).
pub fn amqp_encode_protocol_header() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(65 as UInt8);
  out.push(77 as UInt8);
  out.push(81 as UInt8);
  out.push(80 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(9 as UInt8);
  out.push(1 as UInt8);
  return out;
}

/// Serialize a "AMQP" 0x00 0x00 0x09 <revision> protocol header for
/// revision 0 (AMQP 0-9) or 1 (AMQP 0-9-1).
/// Err("amqp: bad protocol revision") for any other revision.
/// Complexity: O(1).
pub fn amqp_encode_protocol_header_rev(revision: Int) -> Result[Vec[UInt8], Str] {
  if revision < 0 || revision > 1 {
    return _err_bytes("amqp: bad protocol revision");
  }
  var out = Vec[UInt8].new();
  out.push(65 as UInt8);
  out.push(77 as UInt8);
  out.push(81 as UInt8);
  out.push(80 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(9 as UInt8);
  out.push(revision as UInt8);
  return _ok_bytes(out);
}

/// Parse the 8-byte protocol header at the start of `data` (extra trailing
/// bytes are ignored so a stream position can advance past it). Accepts
/// major 0 / minor 9 with revision 0 (0-9) or 1 (0-9-1).
/// Returns Ok(revision).
/// Err("amqp: truncated protocol header") when fewer than 8 bytes are
/// present; Err("amqp: bad protocol header") for a wrong magic/version;
/// Err("amqp: bad protocol revision") for a revision other than 0 or 1.
/// Complexity: O(1).
pub fn amqp_parse_protocol_header(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() < 8 {
    return _err_int("amqp: truncated protocol header");
  }
  if _byte(data, 0) != 65 || _byte(data, 1) != 77 || _byte(data, 2) != 81 || _byte(data, 3) != 80 {
    return _err_int("amqp: bad protocol header");
  }
  if _byte(data, 4) != 0 || _byte(data, 5) != 0 || _byte(data, 6) != 9 {
    return _err_int("amqp: bad protocol header");
  }
  let rev = _byte(data, 7);
  if rev > 1 {
    return _err_int("amqp: bad protocol revision");
  }
  return _ok_int(rev);
}

// --------------------------------------------------
//  Generic frame header
// --------------------------------------------------

/// Parse a complete frame occupying the whole buffer: type octet (1 method,
/// 2 header, 3 body, 8 heartbeat), channel u16, payload size u32, payload
/// and frame-end 0xCE. `frame_max` bounds the payload size (`frame_max < 8`
/// is rejected); payloads above it yield "amqp: frame too large".
///
/// Err("amqp: bad frame max") for `frame_max < 8`;
/// Err("amqp: truncated frame") when the header, payload or frame end is
/// missing; Err("amqp: bad frame type") for any type other than 1/2/3/8;
/// Err("amqp: bad frame end") when the closing octet is not 0xCE;
/// Err("amqp: trailing bytes") when the buffer extends past the frame.
/// Complexity: O(frame size).
pub fn amqp_parse_frame_header(data: &Vec[UInt8], frame_max: Int) -> Result[AmqpFrameHeader, Str] {
  if frame_max < 8 {
    return _err_fh("amqp: bad frame max");
  }
  if data.len() < 8 {
    return _err_fh("amqp: truncated frame");
  }
  let ft = _byte(data, 0);
  if ft != 1 && ft != 2 && ft != 3 && ft != 8 {
    return _err_fh("amqp: bad frame type");
  }
  let ch = _read_u16(data, 1);
  let size = _read_u32(data, 3);
  if size > frame_max {
    return _err_fh("amqp: frame too large");
  }
  if data.len() < 7 + size + 1 {
    return _err_fh("amqp: truncated frame");
  }
  let fe = _byte(data, 7 + size);
  if fe != 206 {
    return _err_fh("amqp: bad frame end");
  }
  if data.len() > 8 + size {
    return _err_fh("amqp: trailing bytes");
  }
  return _ok_fh(AmqpFrameHeader{ frame_type: ft; channel: ch; payload_size: size; payload_start: 7; frame_len: 8 + size; });
}

// --------------------------------------------------
//  Value tree construction and navigation
// --------------------------------------------------

/// A fresh empty tree. Complexity: O(1).
pub fn amqp_tree_new() -> AmqpTree {
  return AmqpTree{ kinds: Vec[Int].new(); keys: Vec[Vec[UInt8]].new(); ints: Vec[Int].new(); aux: Vec[Int].new(); strs: Vec[Vec[UInt8]].new(); };
}

// Append one node, mirroring every parallel vector (they must never drift).
fn _tree_push(t: &mut AmqpTree, kind: Int, key: Vec[UInt8], ival: Int, auxv: Int, sb: Vec[UInt8]) {
  t.kinds.push(kind);
  t.keys.push(key);
  t.ints.push(ival);
  t.aux.push(auxv);
  t.strs.push(sb);
}

// Append an end-of-container marker.
fn _tree_push_end(t: &mut AmqpTree) {
  _tree_push(t, 99, Vec[UInt8].new(), 0, 0, Vec[UInt8].new());
}

/// Append an octet method argument. The value range is checked on encode.
/// Complexity: O(1).
pub fn amqp_tree_push_octet(t: &mut AmqpTree, v: Int) {
  _tree_push(t, 1, Vec[UInt8].new(), v, 0, Vec[UInt8].new());
}

/// Append a short method argument. The value range is checked on encode.
/// Complexity: O(1).
pub fn amqp_tree_push_short(t: &mut AmqpTree, v: Int) {
  _tree_push(t, 2, Vec[UInt8].new(), v, 0, Vec[UInt8].new());
}

/// Append a long method argument. The value range is checked on encode.
/// Complexity: O(1).
pub fn amqp_tree_push_long(t: &mut AmqpTree, v: Int) {
  _tree_push(t, 3, Vec[UInt8].new(), v, 0, Vec[UInt8].new());
}

/// Append a long-long method argument. The value range is checked on encode.
/// Complexity: O(1).
pub fn amqp_tree_push_longlong(t: &mut AmqpTree, v: Int) {
  _tree_push(t, 4, Vec[UInt8].new(), v, 0, Vec[UInt8].new());
}

/// Append a bit method argument (0 or 1, checked on encode). Consecutive
/// bits pack LSB-first into octets when the frame is serialized.
/// Complexity: O(1).
pub fn amqp_tree_push_bit(t: &mut AmqpTree, v: Int) {
  _tree_push(t, 9, Vec[UInt8].new(), v, 0, Vec[UInt8].new());
}

/// Append a shortstr method argument (<= 255 bytes, checked on encode).
/// Complexity: O(bytes).
pub fn amqp_tree_push_shortstr(t: &mut AmqpTree, s: &Vec[UInt8]) {
  _tree_push(t, 5, Vec[UInt8].new(), 0, 0, _vec_copy(s));
}

/// Append a longstr method argument. Complexity: O(bytes).
pub fn amqp_tree_push_longstr(t: &mut AmqpTree, s: &Vec[UInt8]) {
  _tree_push(t, 6, Vec[UInt8].new(), 0, 0, _vec_copy(s));
}

/// Open a table node; entries follow until the matching `amqp_tree_end`.
/// Complexity: O(1).
pub fn amqp_tree_begin_table(t: &mut AmqpTree) {
  _tree_push(t, 7, Vec[UInt8].new(), 0, 0, Vec[UInt8].new());
}

/// Open a keyed table node as an entry of the enclosing table; entries
/// follow until the matching `amqp_tree_end`. Complexity: O(key bytes).
pub fn amqp_tree_begin_table_keyed(t: &mut AmqpTree, key: &Vec[UInt8]) {
  _tree_push(t, 7, _vec_copy(key), 0, 0, Vec[UInt8].new());
}

/// Open an array node; values follow until the matching `amqp_tree_end`.
/// Complexity: O(1).
pub fn amqp_tree_begin_array(t: &mut AmqpTree) {
  _tree_push(t, 8, Vec[UInt8].new(), 0, 0, Vec[UInt8].new());
}

/// Open a keyed array node as an entry of the enclosing table; values follow
/// until the matching `amqp_tree_end`. Complexity: O(key bytes).
pub fn amqp_tree_begin_array_keyed(t: &mut AmqpTree, key: &Vec[UInt8]) {
  _tree_push(t, 8, _vec_copy(key), 0, 0, Vec[UInt8].new());
}

/// Close the innermost open table/array node. Complexity: O(1).
pub fn amqp_tree_end(t: &mut AmqpTree) {
  _tree_push_end(t);
}

/// Append a keyed field bool (tag 't'). Complexity: O(key bytes).
pub fn amqp_tree_push_field_bool(t: &mut AmqpTree, key: &Vec[UInt8], v: Int) {
  _tree_push(t, 20, _vec_copy(key), v, 0, Vec[UInt8].new());
}

/// Append a keyed field float (tag 'f') from its raw 32-bit IEEE-754
/// pattern. Complexity: O(key bytes).
pub fn amqp_tree_push_field_float(t: &mut AmqpTree, key: &Vec[UInt8], bits: Int) {
  _tree_push(t, 21, _vec_copy(key), bits, 0, Vec[UInt8].new());
}

/// Append a keyed field short (tag 's', signed 16-bit).
/// Complexity: O(key bytes).
pub fn amqp_tree_push_field_short(t: &mut AmqpTree, key: &Vec[UInt8], v: Int) {
  _tree_push(t, 22, _vec_copy(key), v, 0, Vec[UInt8].new());
}

/// Append a keyed field long (tag 'I', signed 32-bit).
/// Complexity: O(key bytes).
pub fn amqp_tree_push_field_long(t: &mut AmqpTree, key: &Vec[UInt8], v: Int) {
  _tree_push(t, 23, _vec_copy(key), v, 0, Vec[UInt8].new());
}

/// Append a keyed field long-long (tag 'l', signed 64-bit).
/// Complexity: O(key bytes).
pub fn amqp_tree_push_field_longlong(t: &mut AmqpTree, key: &Vec[UInt8], v: Int) {
  _tree_push(t, 24, _vec_copy(key), v, 0, Vec[UInt8].new());
}

/// Append a keyed field decimal (tag 'D'): one scale octet plus a signed
/// 32-bit value. Complexity: O(key bytes).
pub fn amqp_tree_push_field_decimal(t: &mut AmqpTree, key: &Vec[UInt8], scale: Int, v: Int) {
  _tree_push(t, 25, _vec_copy(key), v, scale, Vec[UInt8].new());
}

/// Append a keyed field byte (tag 'b', signed 8-bit).
/// Complexity: O(key bytes).
pub fn amqp_tree_push_field_byte(t: &mut AmqpTree, key: &Vec[UInt8], v: Int) {
  _tree_push(t, 26, _vec_copy(key), v, 0, Vec[UInt8].new());
}

/// Append a keyed field timestamp (tag 'T', u64 seconds, restricted to
/// 0..2^63-1). Complexity: O(key bytes).
pub fn amqp_tree_push_field_timestamp(t: &mut AmqpTree, key: &Vec[UInt8], v: Int) {
  _tree_push(t, 28, _vec_copy(key), v, 0, Vec[UInt8].new());
}

/// Append a keyed field void (tag 'V'). Complexity: O(key bytes).
pub fn amqp_tree_push_field_void(t: &mut AmqpTree, key: &Vec[UInt8]) {
  _tree_push(t, 30, _vec_copy(key), 0, 0, Vec[UInt8].new());
}

/// Append a keyed field byte-array (tag 'x', u32 length + bytes).
/// Complexity: O(key bytes + value bytes).
pub fn amqp_tree_push_field_bytes(t: &mut AmqpTree, key: &Vec[UInt8], s: &Vec[UInt8]) {
  _tree_push(t, 31, _vec_copy(key), 0, 0, _vec_copy(s));
}

/// Number of nodes (including end markers). Complexity: O(1).
pub fn amqp_tree_len(t: &AmqpTree) -> Int {
  return t.kinds.len();
}

/// Kind at node `i`, or -1 when out of range. Complexity: O(1).
pub fn amqp_tree_kind_at(t: &AmqpTree, i: Int) -> Int {
  if i < 0 || i >= t.kinds.len() {
    return -1;
  }
  let k: Int = t.kinds[i];
  return k;
}

/// Integer value at node `i` (0 when out of range). Complexity: O(1).
pub fn amqp_tree_int_at(t: &AmqpTree, i: Int) -> Int {
  if i < 0 || i >= t.ints.len() {
    return 0;
  }
  let v: Int = t.ints[i];
  return v;
}

/// Decimal scale at node `i` (0 when out of range). Complexity: O(1).
pub fn amqp_tree_aux_at(t: &AmqpTree, i: Int) -> Int {
  if i < 0 || i >= t.aux.len() {
    return 0;
  }
  let v: Int = t.aux[i];
  return v;
}

/// Byte copy of the key at node `i` (empty when out of range).
/// Complexity: O(key bytes).
pub fn amqp_tree_key_at(t: &AmqpTree, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= t.keys.len() {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = t.keys[i];
  return _vec_copy(&v);
}

/// Byte copy of the string payload at node `i` (empty when out of range).
/// Complexity: O(bytes).
pub fn amqp_tree_bytes_at(t: &AmqpTree, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= t.strs.len() {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = t.strs[i];
  return _vec_copy(&v);
}

// Index just past the subtree rooted at node `i` (pre-order with end
// markers); tree length when the matching end marker is missing.
fn _skip_subtree(t: &AmqpTree, i: Int) -> Int {
  let k: Int = amqp_tree_kind_at(t, i);
  if k != 7 && k != 8 {
    return i + 1;
  }
  var depth = 1;
  var j = i + 1;
  while j < t.kinds.len() {
    let kj: Int = amqp_tree_kind_at(t, j);
    if kj == 99 {
      depth = depth - 1;
      if depth == 0 {
        return j + 1;
      }
    } else if kj == 7 || kj == 8 {
      depth = depth + 1;
    }
    j = j + 1;
  }
  return t.kinds.len();
}

/// Number of top-level nodes in the tree. Complexity: O(nodes).
pub fn amqp_tree_arg_count(t: &AmqpTree) -> Int {
  var i = 0;
  var count = 0;
  while i < t.kinds.len() {
    let k: Int = amqp_tree_kind_at(t, i);
    if k == 99 || k < 0 {
      return count;
    }
    count = count + 1;
    i = _skip_subtree(t, i);
  }
  return count;
}

/// Node index of top-level argument `n`, or -1 when out of range.
/// Complexity: O(nodes).
pub fn amqp_tree_arg_node(t: &AmqpTree, n: Int) -> Int {
  if n < 0 {
    return -1;
  }
  var i = 0;
  var count = 0;
  while i < t.kinds.len() {
    let k: Int = amqp_tree_kind_at(t, i);
    if k == 99 || k < 0 {
      return -1;
    }
    if count == n {
      return i;
    }
    count = count + 1;
    i = _skip_subtree(t, i);
  }
  return -1;
}

/// Number of direct children of the container at node `i`, or -1 when `i`
/// is not a table/array. Complexity: O(children).
pub fn amqp_tree_kid_count(t: &AmqpTree, i: Int) -> Int {
  let k: Int = amqp_tree_kind_at(t, i);
  if k != 7 && k != 8 {
    return -1;
  }
  var j = i + 1;
  var count = 0;
  while j < t.kinds.len() {
    let kj: Int = amqp_tree_kind_at(t, j);
    if kj == 99 {
      return count;
    }
    if kj < 0 {
      return -1;
    }
    count = count + 1;
    j = _skip_subtree(t, j);
  }
  return -1;
}

/// Node index of direct child `k` of the container at node `i`, or -1 when
/// out of range. Complexity: O(children).
pub fn amqp_tree_kid_node(t: &AmqpTree, i: Int, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  let kind: Int = amqp_tree_kind_at(t, i);
  if kind != 7 && kind != 8 {
    return -1;
  }
  var j = i + 1;
  var count = 0;
  while j < t.kinds.len() {
    let kj: Int = amqp_tree_kind_at(t, j);
    if kj == 99 {
      return -1;
    }
    if kj < 0 {
      return -1;
    }
    if count == k {
      return j;
    }
    count = count + 1;
    j = _skip_subtree(t, j);
  }
  return -1;
}

/// Node index of the direct child of container `i` whose key equals `key`
/// (byte-wise), or -1 when absent. Complexity: O(children * key bytes).
pub fn amqp_tree_find_key(t: &AmqpTree, i: Int, key: &Vec[UInt8]) -> Int {
  let kind: Int = amqp_tree_kind_at(t, i);
  if kind != 7 && kind != 8 {
    return -1;
  }
  var j = i + 1;
  while j < t.kinds.len() {
    let kj: Int = amqp_tree_kind_at(t, j);
    if kj == 99 || kj < 0 {
      return -1;
    }
    let k: Vec[UInt8] = amqp_tree_key_at(t, j);
    if _bytes_eq(&k, key) {
      return j;
    }
    j = _skip_subtree(t, j);
  }
  return -1;
}

// --------------------------------------------------
//  Field table / array decoding
// --------------------------------------------------

// "amqp: bad table" / "amqp: bad array" depending on the container kind.
fn _container_err(kind: Int) -> Str {
  if kind == 8 {
    return "amqp: bad array";
  }
  return "amqp: bad table";
}

// Decode a table (root_kind 7) or array (root_kind 8) whose u32 byte length
// starts at `pos0`, bounded by `end`, appending the container node, its
// entries and the end marker to `t`. `root_key` is the key of the container
// node itself (empty for method arguments and content headers). Nesting is
// limited to 32 open containers.
// Err(_container_err(...)) for length/framing mismatches,
// Err("amqp: truncated field") for truncated values,
// Err("amqp: truncated string") for truncated keys,
// Err("amqp: bad bool") for a bool octet other than 0/1,
// Err("amqp: bad field tag") for an unsupported field-value tag,
// Err("amqp: table nesting too deep") beyond 32 open containers and
// Err("amqp: integer out of range") for 64-bit values >= 2^63.
fn _decode_field_container(data: &Vec[UInt8], pos0: Int, end: Int, root_kind: Int, root_key: Vec[UInt8], t: &mut AmqpTree) -> Result[Int, Str] {
  var pos = pos0;
  if pos + 4 > end {
    return _err_int(_container_err(root_kind));
  }
  let root_len = _read_u32(data, pos);
  if root_len > end - pos - 4 {
    return _err_int(_container_err(root_kind));
  }
  let root_end: Int = pos + 4 + root_len;
  _tree_push(t, root_kind, root_key, 0, 0, Vec[UInt8].new());
  pos = pos + 4;
  while pos < root_end {
    var key = Vec[UInt8].new();
    if root_kind == 7 {
      let kr = _read_shortstr(data, pos, root_end, &mut key);
      if !kr.is_ok {
        return _err_int(kr.error);
      }
      pos = kr.value;
    }
    if pos >= root_end {
      return _err_int(_container_err(root_kind));
    }
    let tag = _byte(data, pos);
    pos = pos + 1;
    if tag == 116 {
      if pos + 1 > root_end {
        return _err_int("amqp: truncated field");
      }
      let bv = _byte(data, pos);
      pos = pos + 1;
      if bv != 0 && bv != 1 {
        return _err_int("amqp: bad bool");
      }
      _tree_push(t, 20, key, bv, 0, Vec[UInt8].new());
    } else if tag == 102 {
      if pos + 4 > root_end {
        return _err_int("amqp: truncated field");
      }
      let bits = _read_u32(data, pos);
      pos = pos + 4;
      _tree_push(t, 21, key, bits, 0, Vec[UInt8].new());
    } else if tag == 115 {
      if pos + 2 > root_end {
        return _err_int("amqp: truncated field");
      }
      let v = _read_i16(data, pos);
      pos = pos + 2;
      _tree_push(t, 22, key, v, 0, Vec[UInt8].new());
    } else if tag == 73 {
      if pos + 4 > root_end {
        return _err_int("amqp: truncated field");
      }
      let v = _read_i32(data, pos);
      pos = pos + 4;
      _tree_push(t, 23, key, v, 0, Vec[UInt8].new());
    } else if tag == 108 {
      if pos + 8 > root_end {
        return _err_int("amqp: truncated field");
      }
      let r = _read_i64_checked(data, pos);
      if !r.is_ok {
        return _err_int(r.error);
      }
      pos = pos + 8;
      _tree_push(t, 24, key, r.value, 0, Vec[UInt8].new());
    } else if tag == 68 {
      if pos + 5 > root_end {
        return _err_int("amqp: truncated field");
      }
      let sc = _byte(data, pos);
      let v = _read_i32(data, pos + 1);
      pos = pos + 5;
      _tree_push(t, 25, key, v, sc, Vec[UInt8].new());
    } else if tag == 98 {
      if pos + 1 > root_end {
        return _err_int("amqp: truncated field");
      }
      let v = _read_i8(data, pos);
      pos = pos + 1;
      _tree_push(t, 26, key, v, 0, Vec[UInt8].new());
    } else if tag == 84 {
      if pos + 8 > root_end {
        return _err_int("amqp: truncated field");
      }
      let r = _read_u64_checked(data, pos);
      if !r.is_ok {
        return _err_int(r.error);
      }
      pos = pos + 8;
      _tree_push(t, 28, key, r.value, 0, Vec[UInt8].new());
    } else if tag == 86 {
      _tree_push(t, 30, key, 0, 0, Vec[UInt8].new());
    } else if tag == 120 {
      if pos + 4 > root_end {
        return _err_int("amqp: truncated field");
      }
      let len = _read_u32(data, pos);
      let start = pos + 4;
      if len > root_end - start {
        return _err_int("amqp: truncated field");
      }
      var sb = Vec[UInt8].new();
      var bi = 0;
      while bi < len {
        sb.push(data[start + bi]);
        bi = bi + 1;
      }
      pos = start + len;
      _tree_push(t, 31, key, 0, 0, sb);
    } else if tag == 70 {
      let r = _decode_container_at(data, pos, root_end, 7, key, t, 2);
      if !r.is_ok {
        return _err_int(r.error);
      }
      pos = r.value;
    } else if tag == 65 {
      let r = _decode_container_at(data, pos, root_end, 8, key, t, 2);
      if !r.is_ok {
        return _err_int(r.error);
      }
      pos = r.value;
    } else {
      return _err_int("amqp: bad field tag");
    }
  }
  if pos != root_end {
    return _err_int(_container_err(root_kind));
  }
  _tree_push_end(t);
  return _ok_int(pos);
}

// Decode one nested table/array container starting at its u32 length field
// (`pos`, bounded by the parent's `end`), appending the container node, its
// entries and the end marker to `t`. Returns the offset just past the
// container. `depth` counts open containers; the root of a document is
// depth 1 and the limit is 32. This helper is recursive on purpose: the
// loop-carried stack variant miscompiled under v0.61.3 (a reused
// `pos + 4 + len` expression kept the first iteration's value).
fn _decode_container_at(data: &Vec[UInt8], pos: Int, end: Int, kind: Int, key: Vec[UInt8], t: &mut AmqpTree, depth: Int) -> Result[Int, Str] {
  if depth > 32 {
    return _err_int("amqp: table nesting too deep");
  }
  if pos + 4 > end {
    return _err_int(_container_err(kind));
  }
  let clen = _read_u32(data, pos);
  if clen > end - pos - 4 {
    return _err_int(_container_err(kind));
  }
  let cend: Int = pos + 4 + clen;
  _tree_push(t, kind, key, 0, 0, Vec[UInt8].new());
  var p = pos + 4;
  while p < cend {
    var k = Vec[UInt8].new();
    if kind == 7 {
      let kr = _read_shortstr(data, p, cend, &mut k);
      if !kr.is_ok {
        return _err_int(kr.error);
      }
      p = kr.value;
    }
    if p >= cend {
      return _err_int(_container_err(kind));
    }
    let tag = _byte(data, p);
    p = p + 1;
    if tag == 116 {
      if p + 1 > cend {
        return _err_int("amqp: truncated field");
      }
      let bv = _byte(data, p);
      p = p + 1;
      if bv != 0 && bv != 1 {
        return _err_int("amqp: bad bool");
      }
      _tree_push(t, 20, k, bv, 0, Vec[UInt8].new());
    } else if tag == 102 {
      if p + 4 > cend {
        return _err_int("amqp: truncated field");
      }
      let bits = _read_u32(data, p);
      p = p + 4;
      _tree_push(t, 21, k, bits, 0, Vec[UInt8].new());
    } else if tag == 115 {
      if p + 2 > cend {
        return _err_int("amqp: truncated field");
      }
      let v = _read_i16(data, p);
      p = p + 2;
      _tree_push(t, 22, k, v, 0, Vec[UInt8].new());
    } else if tag == 73 {
      if p + 4 > cend {
        return _err_int("amqp: truncated field");
      }
      let v = _read_i32(data, p);
      p = p + 4;
      _tree_push(t, 23, k, v, 0, Vec[UInt8].new());
    } else if tag == 108 {
      if p + 8 > cend {
        return _err_int("amqp: truncated field");
      }
      let r = _read_i64_checked(data, p);
      if !r.is_ok {
        return _err_int(r.error);
      }
      p = p + 8;
      _tree_push(t, 24, k, r.value, 0, Vec[UInt8].new());
    } else if tag == 68 {
      if p + 5 > cend {
        return _err_int("amqp: truncated field");
      }
      let sc = _byte(data, p);
      let v = _read_i32(data, p + 1);
      p = p + 5;
      _tree_push(t, 25, k, v, sc, Vec[UInt8].new());
    } else if tag == 98 {
      if p + 1 > cend {
        return _err_int("amqp: truncated field");
      }
      let v = _read_i8(data, p);
      p = p + 1;
      _tree_push(t, 26, k, v, 0, Vec[UInt8].new());
    } else if tag == 84 {
      if p + 8 > cend {
        return _err_int("amqp: truncated field");
      }
      let r = _read_u64_checked(data, p);
      if !r.is_ok {
        return _err_int(r.error);
      }
      p = p + 8;
      _tree_push(t, 28, k, r.value, 0, Vec[UInt8].new());
    } else if tag == 86 {
      _tree_push(t, 30, k, 0, 0, Vec[UInt8].new());
    } else if tag == 120 {
      if p + 4 > cend {
        return _err_int("amqp: truncated field");
      }
      let len = _read_u32(data, p);
      let start = p + 4;
      if len > cend - start {
        return _err_int("amqp: truncated field");
      }
      var sb = Vec[UInt8].new();
      var bi = 0;
      while bi < len {
        sb.push(data[start + bi]);
        bi = bi + 1;
      }
      p = start + len;
      _tree_push(t, 31, k, 0, 0, sb);
    } else if tag == 70 {
      let r = _decode_container_at(data, p, cend, 7, k, t, depth + 1);
      if !r.is_ok {
        return _err_int(r.error);
      }
      p = r.value;
    } else if tag == 65 {
      let r = _decode_container_at(data, p, cend, 8, k, t, depth + 1);
      if !r.is_ok {
        return _err_int(r.error);
      }
      p = r.value;
    } else {
      return _err_int("amqp: bad field tag");
    }
  }
  if p != cend {
    return _err_int(_container_err(kind));
  }
  _tree_push_end(t);
  return _ok_int(p);
}

// Decode a method argument list from [pos0, end) according to `schema`
// (argument type codes 1..9), appending one node per argument to `t`.
// Consecutive bits pack LSB-first into octets; the remaining padding bits of
// a partial octet are discarded when a non-bit argument follows.
// Err("amqp: truncated arguments") when the payload is short and
// Err("amqp: unknown method") for a schema code outside 1..9.
fn _decode_method_args(data: &Vec[UInt8], pos0: Int, end: Int, schema: &Vec[Int], t: &mut AmqpTree) -> Result[Int, Str] {
  var pos = pos0;
  var i = 0;
  var bit_buf = 0;
  var bit_idx = 0;
  while i < schema.len() {
    let code: Int = schema[i];
    if code == 9 {
      if bit_idx == 0 {
        if pos + 1 > end {
          return _err_int("amqp: truncated arguments");
        }
        bit_buf = _byte(data, pos);
        pos = pos + 1;
      }
      let bv = (bit_buf / _pow2(bit_idx)) % 2;
      _tree_push(t, 9, Vec[UInt8].new(), bv, 0, Vec[UInt8].new());
      bit_idx = bit_idx + 1;
      if bit_idx == 8 {
        bit_idx = 0;
        bit_buf = 0;
      }
    } else if code == 7 || code == 8 {
      bit_idx = 0;
      let r = _decode_field_container(data, pos, end, code, Vec[UInt8].new(), t);
      if !r.is_ok {
        return _err_int(r.error);
      }
      pos = r.value;
    } else if code == 1 {
      bit_idx = 0;
      if pos + 1 > end {
        return _err_int("amqp: truncated arguments");
      }
      let v = _byte(data, pos);
      pos = pos + 1;
      _tree_push(t, 1, Vec[UInt8].new(), v, 0, Vec[UInt8].new());
    } else if code == 2 {
      bit_idx = 0;
      if pos + 2 > end {
        return _err_int("amqp: truncated arguments");
      }
      let v = _read_u16(data, pos);
      pos = pos + 2;
      _tree_push(t, 2, Vec[UInt8].new(), v, 0, Vec[UInt8].new());
    } else if code == 3 {
      bit_idx = 0;
      if pos + 4 > end {
        return _err_int("amqp: truncated arguments");
      }
      let v = _read_u32(data, pos);
      pos = pos + 4;
      _tree_push(t, 3, Vec[UInt8].new(), v, 0, Vec[UInt8].new());
    } else if code == 4 {
      bit_idx = 0;
      if pos + 8 > end {
        return _err_int("amqp: truncated arguments");
      }
      let r = _read_u64_checked(data, pos);
      if !r.is_ok {
        return _err_int(r.error);
      }
      pos = pos + 8;
      _tree_push(t, 4, Vec[UInt8].new(), r.value, 0, Vec[UInt8].new());
    } else if code == 5 {
      bit_idx = 0;
      var sb = Vec[UInt8].new();
      let r = _read_shortstr(data, pos, end, &mut sb);
      if !r.is_ok {
        return _err_int(r.error);
      }
      pos = r.value;
      _tree_push(t, 5, Vec[UInt8].new(), 0, 0, sb);
    } else if code == 6 {
      bit_idx = 0;
      var sb = Vec[UInt8].new();
      let r = _read_longstr(data, pos, end, &mut sb);
      if !r.is_ok {
        return _err_int(r.error);
      }
      pos = r.value;
      _tree_push(t, 6, Vec[UInt8].new(), 0, 0, sb);
    } else {
      return _err_int("amqp: unknown method");
    }
    i = i + 1;
  }
  return _ok_int(pos);
}

// --------------------------------------------------
//  Method schemas
// --------------------------------------------------

// Schema builders: one Vec[Int] of argument type codes per method, kept in
// schema order so decoded argument nodes line up index-for-index.
fn _sch1(a: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  return s;
}

fn _sch2(a: Int, b: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  s.push(b);
  return s;
}

fn _sch3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  s.push(b);
  s.push(c);
  return s;
}

fn _sch4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  s.push(b);
  s.push(c);
  s.push(d);
  return s;
}

fn _sch5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  s.push(b);
  s.push(c);
  s.push(d);
  s.push(e);
  return s;
}

fn _sch6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  s.push(b);
  s.push(c);
  s.push(d);
  s.push(e);
  s.push(f);
  return s;
}

fn _sch7(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  s.push(b);
  s.push(c);
  s.push(d);
  s.push(e);
  s.push(f);
  s.push(g);
  return s;
}

fn _sch8(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  s.push(b);
  s.push(c);
  s.push(d);
  s.push(e);
  s.push(f);
  s.push(g);
  s.push(h);
  return s;
}

fn _sch9(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int, i: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  s.push(b);
  s.push(c);
  s.push(d);
  s.push(e);
  s.push(f);
  s.push(g);
  s.push(h);
  s.push(i);
  return s;
}

/// Argument type schema for a known method, in wire order. Type codes:
/// 1 octet, 2 short, 3 long, 4 long-long, 5 shortstr, 6 longstr, 7 table,
/// 8 array, 9 bit. The implemented subset is AMQP 0-9-1 connection (10),
/// channel (20), exchange (40), queue (50) and basic (60). Methods outside
/// the subset return Err("amqp: unknown method"). Complexity: O(1).
pub fn amqp_method_schema(class_id: Int, method_id: Int) -> Result[Vec[Int], Str] {
  if class_id == 10 {
    if method_id == 10 {
      return _ok_schema(_sch5(1, 1, 7, 6, 6));
    }
    if method_id == 11 {
      return _ok_schema(_sch4(7, 5, 6, 5));
    }
    if method_id == 30 {
      return _ok_schema(_sch3(2, 3, 2));
    }
    if method_id == 31 {
      return _ok_schema(_sch3(2, 3, 2));
    }
    if method_id == 40 {
      return _ok_schema(_sch3(5, 5, 9));
    }
    if method_id == 41 {
      return _ok_schema(_sch1(5));
    }
    if method_id == 50 {
      return _ok_schema(_sch4(2, 5, 2, 2));
    }
    if method_id == 51 {
      return _ok_schema(Vec[Int].new());
    }
    return _err_schema("amqp: unknown method");
  }
  if class_id == 20 {
    if method_id == 10 {
      return _ok_schema(_sch1(5));
    }
    if method_id == 11 {
      return _ok_schema(_sch1(6));
    }
    if method_id == 40 {
      return _ok_schema(_sch4(2, 5, 2, 2));
    }
    if method_id == 41 {
      return _ok_schema(Vec[Int].new());
    }
    return _err_schema("amqp: unknown method");
  }
  if class_id == 40 {
    if method_id == 10 {
      return _ok_schema(_sch9(2, 5, 5, 9, 9, 9, 9, 9, 7));
    }
    if method_id == 20 {
      return _ok_schema(_sch4(2, 5, 9, 9));
    }
    if method_id == 30 {
      return _ok_schema(_sch6(2, 5, 5, 5, 9, 7));
    }
    if method_id == 40 {
      return _ok_schema(_sch6(2, 5, 5, 5, 9, 7));
    }
    return _err_schema("amqp: unknown method");
  }
  if class_id == 50 {
    if method_id == 10 {
      return _ok_schema(_sch8(2, 5, 9, 9, 9, 9, 9, 7));
    }
    if method_id == 11 {
      return _ok_schema(_sch3(5, 3, 3));
    }
    if method_id == 20 {
      return _ok_schema(_sch6(2, 5, 5, 5, 9, 7));
    }
    if method_id == 30 {
      return _ok_schema(_sch3(2, 5, 9));
    }
    if method_id == 31 {
      return _ok_schema(_sch1(3));
    }
    if method_id == 40 {
      return _ok_schema(_sch5(2, 5, 9, 9, 9));
    }
    if method_id == 41 {
      return _ok_schema(_sch1(3));
    }
    if method_id == 50 {
      return _ok_schema(_sch5(2, 5, 5, 5, 7));
    }
    return _err_schema("amqp: unknown method");
  }
  if class_id == 60 {
    if method_id == 10 {
      return _ok_schema(_sch3(3, 2, 9));
    }
    if method_id == 11 {
      return _ok_schema(Vec[Int].new());
    }
    if method_id == 40 {
      return _ok_schema(_sch5(2, 5, 5, 9, 9));
    }
    if method_id == 50 {
      return _ok_schema(_sch4(2, 5, 5, 5));
    }
    if method_id == 60 {
      return _ok_schema(_sch5(5, 4, 9, 5, 5));
    }
    if method_id == 80 {
      return _ok_schema(_sch2(4, 9));
    }
    if method_id == 120 {
      return _ok_schema(_sch3(4, 9, 9));
    }
    return _err_schema("amqp: unknown method");
  }
  return _err_schema("amqp: unknown method");
}

// --------------------------------------------------
//  Method frame encoding
// --------------------------------------------------

// Encode one method-space scalar node (kinds 1..6; bits are handled by the
// argument walker). Returns the index just past the node.
fn _encode_scalar_method(t: &AmqpTree, i: Int, k: Int, iv: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  if k == 1 {
    if iv < 0 || iv > 255 {
      return _err_int("amqp: value out of range");
    }
    out.push(iv as UInt8);
  } else if k == 2 {
    if iv < 0 || iv > 65535 {
      return _err_int("amqp: value out of range");
    }
    _push_u16(out, iv);
  } else if k == 3 {
    if iv < 0 || iv > 4294967295 {
      return _err_int("amqp: value out of range");
    }
    _push_u32(out, iv);
  } else if k == 4 {
    if iv < 0 || iv > _max_i63() {
      return _err_int("amqp: value out of range");
    }
    _push_u64(out, iv);
  } else if k == 5 {
    let s: Vec[UInt8] = amqp_tree_bytes_at(t, i);
    let r = _push_shortstr_checked(out, &s);
    if !r.is_ok {
      return _err_int(r.error);
    }
  } else if k == 6 {
    let s: Vec[UInt8] = amqp_tree_bytes_at(t, i);
    let r = _push_longstr_checked(out, &s);
    if !r.is_ok {
      return _err_int(r.error);
    }
  } else {
    return _err_int("amqp: bad argument kind");
  }
  return _ok_int(i + 1);
}

// Encode one field-space scalar node (tags t/f/s/I/l/D/b/T/V/x). Containers
// (kinds 7/8) are handled by _encode_node. Returns the index just past the
// node.
fn _encode_scalar_field(t: &AmqpTree, i: Int, k: Int, iv: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  if k == 20 {
    if iv != 0 && iv != 1 {
      return _err_int("amqp: value out of range");
    }
    out.push(116 as UInt8);
    out.push(iv as UInt8);
  } else if k == 21 {
    if iv < 0 || iv > 4294967295 {
      return _err_int("amqp: value out of range");
    }
    out.push(102 as UInt8);
    _push_u32(out, iv);
  } else if k == 22 {
    if iv < -32768 || iv > 32767 {
      return _err_int("amqp: value out of range");
    }
    out.push(115 as UInt8);
    _push_i16(out, iv);
  } else if k == 23 {
    if iv < -2147483648 || iv > 2147483647 {
      return _err_int("amqp: value out of range");
    }
    out.push(73 as UInt8);
    _push_i32(out, iv);
  } else if k == 24 {
    if iv < _min_i64() || iv > _max_i63() {
      return _err_int("amqp: value out of range");
    }
    out.push(108 as UInt8);
    _push_i64(out, iv);
  } else if k == 25 {
    let sc: Int = amqp_tree_aux_at(t, i);
    if sc < 0 || sc > 255 {
      return _err_int("amqp: value out of range");
    }
    if iv < -2147483648 || iv > 2147483647 {
      return _err_int("amqp: value out of range");
    }
    out.push(68 as UInt8);
    out.push(sc as UInt8);
    _push_i32(out, iv);
  } else if k == 26 {
    if iv < -128 || iv > 127 {
      return _err_int("amqp: value out of range");
    }
    out.push(98 as UInt8);
    _push_i8(out, iv);
  } else if k == 28 {
    if iv < 0 || iv > _max_i63() {
      return _err_int("amqp: value out of range");
    }
    out.push(84 as UInt8);
    _push_u64(out, iv);
  } else if k == 30 {
    out.push(86 as UInt8);
  } else if k == 31 {
    let s: Vec[UInt8] = amqp_tree_bytes_at(t, i);
    if s.len() > 2147483647 {
      return _err_int("amqp: string too long");
    }
    out.push(120 as UInt8);
    _push_u32(out, s.len());
    _push_vec(out, &s);
  } else {
    return _err_int("amqp: bad value kind");
  }
  return _ok_int(i + 1);
}

// Encode the node at index `i` into `out`. `space` is 0 for method arguments
// and content-header properties, 7 when the parent is a field table (the
// node key is written first) and 8 when the parent is a field array. In
// method/property space a table/array node encodes as u32 length + entries;
// as a field value it is prefixed with the 'F'/'A' tag. Returns the index
// just past the node (and its subtree).
fn _encode_node(t: &AmqpTree, i: Int, out: &mut Vec[UInt8], space: Int) -> Result[Int, Str] {
  let k: Int = amqp_tree_kind_at(t, i);
  if k < 0 {
    return _err_int("amqp: bad value kind");
  }
  if space == 7 {
    let key: Vec[UInt8] = amqp_tree_key_at(t, i);
    let kr = _push_shortstr_checked(out, &key);
    if !kr.is_ok {
      return _err_int(kr.error);
    }
  }
  if k == 7 || k == 8 {
    var inner = Vec[UInt8].new();
    var child_space = 8;
    if k == 7 {
      child_space = 7;
    }
    var j = i + 1;
    var closed = false;
    while j < amqp_tree_len(t) && !closed {
      let ck: Int = amqp_tree_kind_at(t, j);
      if ck == 99 {
        closed = true;
      } else {
        let r = _encode_node(t, j, &mut inner, child_space);
        if !r.is_ok {
          return _err_int(r.error);
        }
        j = r.value;
      }
    }
    if !closed {
      return _err_int("amqp: bad value kind");
    }
    if space != 0 {
      if k == 7 {
        out.push(70 as UInt8);
      } else {
        out.push(65 as UInt8);
      }
    }
    _push_u32(out, inner.len());
    _push_vec(out, &inner);
    return _ok_int(j + 1);
  }
  let iv: Int = amqp_tree_int_at(t, i);
  if space == 0 {
    return _encode_scalar_method(t, i, k, iv, out);
  }
  return _encode_scalar_field(t, i, k, iv, out);
}

// Encode a method argument stream: consecutive bit nodes pack LSB-first into
// octets (flushed on the 8th bit, before any non-bit node and at the end);
// every other node is delegated to _encode_node.
fn _encode_method_args(t: &AmqpTree, out: &mut Vec[UInt8]) -> Result[Unit, Str] {
  var i = 0;
  var bit_buf = 0;
  var bit_n = 0;
  while i < amqp_tree_len(t) {
    let k: Int = amqp_tree_kind_at(t, i);
    if k == 99 {
      return _err_unit("amqp: bad argument kind");
    }
    if k == 9 {
      let bv: Int = amqp_tree_int_at(t, i);
      if bv != 0 && bv != 1 {
        return _err_unit("amqp: bad bit");
      }
      bit_buf = bit_buf + bv * _pow2(bit_n);
      bit_n = bit_n + 1;
      if bit_n == 8 {
        out.push(bit_buf as UInt8);
        bit_buf = 0;
        bit_n = 0;
      }
      i = i + 1;
    } else {
      if bit_n > 0 {
        out.push(bit_buf as UInt8);
        bit_buf = 0;
        bit_n = 0;
      }
      let r = _encode_node(t, i, out, 0);
      if !r.is_ok {
        return _err_unit(r.error);
      }
      i = r.value;
    }
  }
  if bit_n > 0 {
    out.push(bit_buf as UInt8);
  }
  return _ok_unit();
}

// Frame one payload: type octet, channel u16, payload size u32, payload,
// frame-end 0xCE. The caller guarantees channel 0..65535.
fn _push_frame(out: &mut Vec[UInt8], frame_type: Int, channel: Int, payload: &Vec[UInt8]) {
  out.push(frame_type as UInt8);
  _push_u16(out, channel);
  _push_u32(out, payload.len());
  _push_vec(out, payload);
  out.push(206 as UInt8);
}

/// Serialize a method frame (type 1) from a decoded or hand-built method
/// frame. The argument nodes must match `amqp_method_schema` exactly, in
/// count, order and kind; value ranges are checked here.
///
/// Err("amqp: bad channel") for a channel outside 0..65535;
/// Err("amqp: bad class id") / Err("amqp: bad method id") outside u16;
/// Err("amqp: unknown method") for a method outside the subset;
/// Err("amqp: bad argument count") when the node count differs from the
/// schema; Err("amqp: bad argument kind") for a node kind mismatch;
/// Err("amqp: value out of range"), Err("amqp: bad bit") and
/// Err("amqp: string too long") for invalid values.
/// Complexity: O(frame size).
pub fn amqp_encode_method_frame(f: &AmqpMethodFrame) -> Result[Vec[UInt8], Str] {
  if f.channel < 0 || f.channel > 65535 {
    return _err_bytes("amqp: bad channel");
  }
  if f.class_id < 0 || f.class_id > 65535 {
    return _err_bytes("amqp: bad class id");
  }
  if f.method_id < 0 || f.method_id > 65535 {
    return _err_bytes("amqp: bad method id");
  }
  let sr = amqp_method_schema(f.class_id, f.method_id);
  if !sr.is_ok {
    return _err_bytes(sr.error);
  }
  let schema: Vec[Int] = sr.value;
  let args: AmqpTree = f.args;
  let ac = amqp_tree_arg_count(&args);
  if ac != schema.len() {
    return _err_bytes("amqp: bad argument count");
  }
  var i = 0;
  while i < ac {
    let idx = amqp_tree_arg_node(&args, i);
    let k: Int = amqp_tree_kind_at(&args, idx);
    let want: Int = schema[i];
    if k != want {
      return _err_bytes("amqp: bad argument kind");
    }
    i = i + 1;
  }
  var payload = Vec[UInt8].new();
  _push_u16(&mut payload, f.class_id);
  _push_u16(&mut payload, f.method_id);
  let er = _encode_method_args(&args, &mut payload);
  if !er.is_ok {
    return _err_bytes(er.error);
  }
  var out = Vec[UInt8].new();
  _push_frame(&mut out, 1, f.channel, &payload);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Frame parsers / serializers
// --------------------------------------------------

/// Parse a complete method frame (type 1): class-id u16, method-id u16 and
/// the schema-driven arguments for a method in the implemented subset.
/// The payload must be consumed exactly.
/// Errors: the frame-header errors plus
/// Err("amqp: truncated method") for a payload shorter than 4 bytes,
/// Err("amqp: unknown method") for a method outside the subset,
/// Err("amqp: truncated arguments"), Err("amqp: truncated string"),
/// Err("amqp: bad table") / Err("amqp: bad array") / Err("amqp: bad bool") /
/// Err("amqp: bad field tag") / Err("amqp: table nesting too deep") /
/// Err("amqp: integer out of range") from argument decoding and
/// Err("amqp: trailing bytes") when the payload has leftovers.
/// Complexity: O(frame size).
pub fn amqp_parse_method_frame(data: &Vec[UInt8], frame_max: Int) -> Result[AmqpMethodFrame, Str] {
  let hr = amqp_parse_frame_header(data, frame_max);
  if !hr.is_ok {
    return _err_mf(hr.error);
  }
  let h: AmqpFrameHeader = hr.value;
  if h.frame_type != 1 {
    return _err_mf("amqp: bad frame type");
  }
  let start = h.payload_start;
  let end = start + h.payload_size;
  if end - start < 4 {
    return _err_mf("amqp: truncated method");
  }
  let cid = _read_u16(data, start);
  let mid = _read_u16(data, start + 2);
  let sr = amqp_method_schema(cid, mid);
  if !sr.is_ok {
    return _err_mf(sr.error);
  }
  let schema: Vec[Int] = sr.value;
  var args = amqp_tree_new();
  let dr = _decode_method_args(data, start + 4, end, &schema, &mut args);
  if !dr.is_ok {
    return _err_mf(dr.error);
  }
  let pos: Int = dr.value;
  if pos != end {
    return _err_mf("amqp: trailing bytes");
  }
  return _ok_mf(AmqpMethodFrame{ channel: h.channel; class_id: cid; method_id: mid; args: args; });
}

/// Parse a complete content header frame (type 2) for class 60: class-id,
/// weight (must be 0), body-size u64, the property flag word and the 13
/// basic properties selected by the flags. Only the single flag word with
/// bits 15..3 (content-type .. app-id) is supported.
///
/// Err("amqp: truncated content header") when the fixed part is short;
/// Err("amqp: bad content class") for a class other than 60;
/// Err("amqp: bad weight") for a non-zero weight;
/// Err("amqp: bad property flags") for the continuation bit or bits 1..2;
/// Err("amqp: unsupported property") for the cluster-id bit (2);
/// Err("amqp: truncated property") for a truncated property value;
/// the string/table/64-bit errors from the shared decoders and
/// Err("amqp: trailing bytes") when the payload has leftovers.
/// Complexity: O(frame size).
pub fn amqp_parse_content_header_frame(data: &Vec[UInt8], frame_max: Int) -> Result[AmqpContentHeader, Str] {
  let hr = amqp_parse_frame_header(data, frame_max);
  if !hr.is_ok {
    return _err_ch(hr.error);
  }
  let h: AmqpFrameHeader = hr.value;
  if h.frame_type != 2 {
    return _err_ch("amqp: bad frame type");
  }
  let start = h.payload_start;
  let end = start + h.payload_size;
  if end - start < 14 {
    return _err_ch("amqp: truncated content header");
  }
  let cid = _read_u16(data, start);
  if cid != 60 {
    return _err_ch("amqp: bad content class");
  }
  let weight = _read_u16(data, start + 2);
  if weight != 0 {
    return _err_ch("amqp: bad weight");
  }
  let bsr = _read_u64_checked(data, start + 4);
  if !bsr.is_ok {
    return _err_ch(bsr.error);
  }
  let body_size: Int = bsr.value;
  let fl = _read_u16(data, start + 12);
  if fl % 2 == 1 {
    return _err_ch("amqp: bad property flags");
  }
  if (fl / 2) % 4 != 0 {
    return _err_ch("amqp: unsupported property");
  }
  var pos = start + 14;
  var hdrs = amqp_tree_new();
  var ct = Vec[UInt8].new();
  var ce = Vec[UInt8].new();
  var corr = Vec[UInt8].new();
  var repl = Vec[UInt8].new();
  var expi = Vec[UInt8].new();
  var mida = Vec[UInt8].new();
  var mtype = Vec[UInt8].new();
  var uid = Vec[UInt8].new();
  var aid = Vec[UInt8].new();
  var dmode: Int = 0;
  var prio: Int = 0;
  var ts: Int = 0;
  if _bit_set(fl, 15) {
    let r = _read_shortstr(data, pos, end, &mut ct);
    if !r.is_ok {
      return _err_ch(r.error);
    }
    pos = r.value;
  }
  if _bit_set(fl, 14) {
    let r = _read_shortstr(data, pos, end, &mut ce);
    if !r.is_ok {
      return _err_ch(r.error);
    }
    pos = r.value;
  }
  if _bit_set(fl, 13) {
    let r = _decode_field_container(data, pos, end, 7, Vec[UInt8].new(), &mut hdrs);
    if !r.is_ok {
      return _err_ch(r.error);
    }
    pos = r.value;
  }
  if _bit_set(fl, 12) {
    if pos + 1 > end {
      return _err_ch("amqp: truncated property");
    }
    dmode = _byte(data, pos);
    pos = pos + 1;
  }
  if _bit_set(fl, 11) {
    if pos + 1 > end {
      return _err_ch("amqp: truncated property");
    }
    prio = _byte(data, pos);
    pos = pos + 1;
  }
  if _bit_set(fl, 10) {
    let r = _read_shortstr(data, pos, end, &mut corr);
    if !r.is_ok {
      return _err_ch(r.error);
    }
    pos = r.value;
  }
  if _bit_set(fl, 9) {
    let r = _read_shortstr(data, pos, end, &mut repl);
    if !r.is_ok {
      return _err_ch(r.error);
    }
    pos = r.value;
  }
  if _bit_set(fl, 8) {
    let r = _read_shortstr(data, pos, end, &mut expi);
    if !r.is_ok {
      return _err_ch(r.error);
    }
    pos = r.value;
  }
  if _bit_set(fl, 7) {
    let r = _read_shortstr(data, pos, end, &mut mida);
    if !r.is_ok {
      return _err_ch(r.error);
    }
    pos = r.value;
  }
  if _bit_set(fl, 6) {
    if pos + 8 > end {
      return _err_ch("amqp: truncated property");
    }
    let r = _read_u64_checked(data, pos);
    if !r.is_ok {
      return _err_ch(r.error);
    }
    ts = r.value;
    pos = pos + 8;
  }
  if _bit_set(fl, 5) {
    let r = _read_shortstr(data, pos, end, &mut mtype);
    if !r.is_ok {
      return _err_ch(r.error);
    }
    pos = r.value;
  }
  if _bit_set(fl, 4) {
    let r = _read_shortstr(data, pos, end, &mut uid);
    if !r.is_ok {
      return _err_ch(r.error);
    }
    pos = r.value;
  }
  if _bit_set(fl, 3) {
    let r = _read_shortstr(data, pos, end, &mut aid);
    if !r.is_ok {
      return _err_ch(r.error);
    }
    pos = r.value;
  }
  if pos != end {
    return _err_ch("amqp: trailing bytes");
  }
  return _ok_ch(AmqpContentHeader{
    channel: h.channel;
    class_id: cid;
    weight: weight;
    body_size: body_size;
    flags: fl;
    content_type: ct;
    content_encoding: ce;
    headers: hdrs;
    delivery_mode: dmode;
    priority: prio;
    correlation_id: corr;
    reply_to: repl;
    expiration: expi;
    message_id: mida;
    timestamp: ts;
    msg_type: mtype;
    user_id: uid;
    app_id: aid;
  });
}

/// Serialize a content header frame (type 2) for class 60. The `flags` word
/// selects which properties are written, in AMQP order; property values for
/// clear flag bits are ignored, except that a non-empty `headers` tree with
/// the headers bit clear is rejected.
///
/// Err("amqp: bad channel"), Err("amqp: bad content class") for a class
/// other than 60, Err("amqp: bad weight") for a non-zero weight,
/// Err("amqp: bad property flags") for bits outside 15..3,
/// Err("amqp: headers not flagged") for unflagged headers data,
/// Err("amqp: value out of range") for out-of-range values and
/// Err("amqp: string too long") for a shortstr over 255 bytes.
/// Complexity: O(frame size).
pub fn amqp_encode_content_header_frame(h: &AmqpContentHeader) -> Result[Vec[UInt8], Str] {
  if h.channel < 0 || h.channel > 65535 {
    return _err_bytes("amqp: bad channel");
  }
  if h.class_id != 60 {
    return _err_bytes("amqp: bad content class");
  }
  if h.weight != 0 {
    return _err_bytes("amqp: bad weight");
  }
  if h.body_size < 0 || h.body_size > _max_i63() {
    return _err_bytes("amqp: value out of range");
  }
  let fl: Int = h.flags;
  if fl < 0 || fl > 65535 || fl % 8 != 0 {
    return _err_bytes("amqp: bad property flags");
  }
  let ct: Vec[UInt8] = h.content_type;
  let ce: Vec[UInt8] = h.content_encoding;
  let hdrs: AmqpTree = h.headers;
  if !_bit_set(fl, 13) && amqp_tree_len(&hdrs) > 0 {
    return _err_bytes("amqp: headers not flagged");
  }
  var payload = Vec[UInt8].new();
  _push_u16(&mut payload, h.class_id);
  _push_u16(&mut payload, h.weight);
  _push_u64(&mut payload, h.body_size);
  _push_u16(&mut payload, fl);
  if _bit_set(fl, 15) {
    let r = _push_shortstr_checked(&mut payload, &ct);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
  }
  if _bit_set(fl, 14) {
    let r = _push_shortstr_checked(&mut payload, &ce);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
  }
  if _bit_set(fl, 13) {
    if amqp_tree_len(&hdrs) == 0 {
      _push_u32(&mut payload, 0);
    } else {
      let r = _encode_node(&hdrs, 0, &mut payload, 0);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
    }
  }
  if _bit_set(fl, 12) {
    let v: Int = h.delivery_mode;
    if v < 0 || v > 255 {
      return _err_bytes("amqp: value out of range");
    }
    payload.push(v as UInt8);
  }
  if _bit_set(fl, 11) {
    let v: Int = h.priority;
    if v < 0 || v > 255 {
      return _err_bytes("amqp: value out of range");
    }
    payload.push(v as UInt8);
  }
  let corr: Vec[UInt8] = h.correlation_id;
  if _bit_set(fl, 10) {
    let r = _push_shortstr_checked(&mut payload, &corr);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
  }
  let repl: Vec[UInt8] = h.reply_to;
  if _bit_set(fl, 9) {
    let r = _push_shortstr_checked(&mut payload, &repl);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
  }
  let expi: Vec[UInt8] = h.expiration;
  if _bit_set(fl, 8) {
    let r = _push_shortstr_checked(&mut payload, &expi);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
  }
  let mida: Vec[UInt8] = h.message_id;
  if _bit_set(fl, 7) {
    let r = _push_shortstr_checked(&mut payload, &mida);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
  }
  if _bit_set(fl, 6) {
    let v: Int = h.timestamp;
    if v < 0 || v > _max_i63() {
      return _err_bytes("amqp: value out of range");
    }
    _push_u64(&mut payload, v);
  }
  let mtype: Vec[UInt8] = h.msg_type;
  if _bit_set(fl, 5) {
    let r = _push_shortstr_checked(&mut payload, &mtype);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
  }
  let uid: Vec[UInt8] = h.user_id;
  if _bit_set(fl, 4) {
    let r = _push_shortstr_checked(&mut payload, &uid);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
  }
  let aid: Vec[UInt8] = h.app_id;
  if _bit_set(fl, 3) {
    let r = _push_shortstr_checked(&mut payload, &aid);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
  }
  var out = Vec[UInt8].new();
  _push_frame(&mut out, 2, h.channel, &payload);
  return _ok_bytes(out);
}

/// Parse a complete body frame (type 3): the payload is an opaque body
/// chunk. All payload sizes up to frame_max (including zero) are valid.
/// Errors: the frame-header errors plus Err("amqp: bad frame type").
/// Complexity: O(frame size).
pub fn amqp_parse_body_frame(data: &Vec[UInt8], frame_max: Int) -> Result[AmqpBodyFrame, Str] {
  let hr = amqp_parse_frame_header(data, frame_max);
  if !hr.is_ok {
    return _err_bf(hr.error);
  }
  let h: AmqpFrameHeader = hr.value;
  if h.frame_type != 3 {
    return _err_bf("amqp: bad frame type");
  }
  var body = Vec[UInt8].new();
  var i = h.payload_start;
  let end = i + h.payload_size;
  while i < end {
    body.push(data[i]);
    i = i + 1;
  }
  return _ok_bf(AmqpBodyFrame{ channel: h.channel; body: body; });
}

/// Serialize a body frame (type 3) from the channel and the body chunk.
/// Err("amqp: bad channel") for a channel outside 0..65535.
/// Complexity: O(body size).
pub fn amqp_encode_body_frame(f: &AmqpBodyFrame) -> Result[Vec[UInt8], Str] {
  if f.channel < 0 || f.channel > 65535 {
    return _err_bytes("amqp: bad channel");
  }
  let body: Vec[UInt8] = f.body;
  if body.len() > 2147483647 {
    return _err_bytes("amqp: string too long");
  }
  var out = Vec[UInt8].new();
  _push_frame(&mut out, 3, f.channel, &body);
  return _ok_bytes(out);
}

/// Parse a complete heartbeat frame (type 8). The payload must be empty and
/// the channel must be 0.
/// Err("amqp: bad heartbeat") for a non-zero payload or channel; all other
/// errors come from the frame header.
/// Complexity: O(1).
pub fn amqp_parse_heartbeat_frame(data: &Vec[UInt8], frame_max: Int) -> Result[AmqpHeartbeat, Str] {
  let hr = amqp_parse_frame_header(data, frame_max);
  if !hr.is_ok {
    return _err_hb(hr.error);
  }
  let h: AmqpFrameHeader = hr.value;
  if h.frame_type != 8 {
    return _err_hb("amqp: bad frame type");
  }
  if h.payload_size != 0 {
    return _err_hb("amqp: bad heartbeat");
  }
  if h.channel != 0 {
    return _err_hb("amqp: bad heartbeat");
  }
  return _ok_hb(AmqpHeartbeat{ channel: 0; });
}

/// Serialize a heartbeat frame (type 8) for channel 0: type octet, channel
/// u16, zero payload size and frame-end.
/// Err("amqp: bad heartbeat") for a channel other than 0.
/// Complexity: O(1).
pub fn amqp_encode_heartbeat_frame(channel: Int) -> Result[Vec[UInt8], Str] {
  if channel != 0 {
    return _err_bytes("amqp: bad heartbeat");
  }
  var payload = Vec[UInt8].new();
  var out = Vec[UInt8].new();
  _push_frame(&mut out, 8, channel, &payload);
  return _ok_bytes(out);
}

// AMQP-END-CHUNK-MARKER
