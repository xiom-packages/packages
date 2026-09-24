// XIOM -- xiom.tftp: pure-XIOM TFTP packet codec (RFC 1350)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Encodes and decodes the five RFC 1350 packet types (RRQ, WRQ, DATA,
// ACK, ERROR) in their classic octet-mode shape: 16-bit big-endian opcodes
// and block numbers, NUL-terminated Str fields for request filenames/modes
// and error messages. See SPEC.md for the byte-level format table,
// validation rules and the error catalog.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * no function builds a Vec inside a match arm over a tuple-Result: the
//     stdlib probe p_result_tuple_vec_loop shows that shape mis-layouts the
//     tuple payload.
//   * all big-endian packing/unpacking is arithmetic (modulo/division), and
//     every byte read is cast to Int before comparison, so no UInt8 value is
//     ever compared against a literal >= 128.
//   * Str fields are assembled with xiom.string.builder (sb_push_str /
//     sb_to_str), the proven one-allocation pattern.

module xiom.tftp

use xiom.string.builder;

// TFTP opcodes (RFC 1350, section 5):
//   1 = RRQ, 2 = WRQ, 3 = DATA, 4 = ACK, 5 = ERROR.
// Block numbers and error codes are unsigned 16-bit values.

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

// Ok((filename, mode)) for Result[(Str, Str), Str].
fn _ok_rq(filename: Str, mode: Str) -> Result[(Str, Str), Str] {
  return Ok((filename, mode));
}

// Err(m) for Result[(Str, Str), Str].
fn _err_rq(m: Str) -> Result[(Str, Str), Str] {
  return Err(m);
}

// Ok((block, payload)) for Result[(Int, Vec[UInt8]), Str].
fn _ok_data(block: Int, payload: Vec[UInt8]) -> Result[(Int, Vec[UInt8]), Str] {
  return Ok((block, payload));
}

// Err(m) for Result[(Int, Vec[UInt8]), Str].
fn _err_data(m: Str) -> Result[(Int, Vec[UInt8]), Str] {
  return Err(m);
}

// Ok((code, message)) for Result[(Int, Str), Str].
fn _ok_error(code: Int, message: Str) -> Result[(Int, Str), Str] {
  return Ok((code, message));
}

// Err(m) for Result[(Int, Str), Str].
fn _err_error(m: Str) -> Result[(Int, Str), Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Clamp a block number or error code to the unsigned 16-bit range.
fn _clamp_u16(v: Int) -> Int {
  if v < 0 {
    return 0;
  }
  if v > 65535 {
    return 65535;
  }
  return v;
}

// Append `v` as two big-endian bytes. `v` must already be in 0..65535.
fn _push_u16_be(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Unsigned big-endian 16-bit value at [pos, pos+2). The caller guarantees
// pos + 2 <= data.len(); every call site checks first.
fn _u16_be_at(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) * 256 + (data[pos + 1] as Int);
}

// Index of the first 0x00 byte in [start, end), or -1 when there is none.
fn _nul_at(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  var i = start;
  while i < end {
    if (data[i] as Int) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Copy bytes [start, end) into a fresh vector. The caller guarantees
// 0 <= start <= end <= data.len().
fn _copy_bytes(data: &Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// Materialize bytes [start, end) as a Str. Bytes are copied verbatim with
// no UTF-8 validation (documented in SPEC.md).
fn _str_between(data: &Vec[UInt8], start: Int, end: Int) -> Str {
  let bytes = _copy_bytes(data, start, end);
  return builder.sb_to_str(&bytes);
}

// Append a NUL-terminated Str field: the bytes of `s`, then one 0x00.
fn _push_cstring(out: &mut Vec[UInt8], s: Str) {
  builder.sb_push_str(out, s);
  out.push(0 as UInt8);
}

// Build a request: opcode (1 RRQ / 2 WRQ), filename, 0x00, mode, 0x00.
fn _build_request(op: Int, filename: Str, mode: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_u16_be(&mut out, op);
  _push_cstring(&mut out, filename);
  _push_cstring(&mut out, mode);
  return out;
}

// --------------------------------------------------
//  Encoders
// --------------------------------------------------

/// Build an RRQ (opcode 1) packet:
/// `[u16 1][filename][0x00][mode][0x00]`. Filename/mode bytes are copied
/// verbatim (no NUL validation; documented in SPEC.md).
pub fn tftp_build_rrq(filename: Str, mode: Str) -> Vec[UInt8] {
  return _build_request(1, filename, mode);
}

/// Build a WRQ (opcode 2) packet:
/// `[u16 2][filename][0x00][mode][0x00]`.
pub fn tftp_build_wrq(filename: Str, mode: Str) -> Vec[UInt8] {
  return _build_request(2, filename, mode);
}

/// Build a DATA packet (opcode 3): `[u16 3][u16 block][payload]`.
/// `block` is clamped to 0..65535; payload bytes are copied verbatim.
pub fn tftp_build_data(block: Int, payload: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_u16_be(&mut out, 3);
  _push_u16_be(&mut out, _clamp_u16(block));
  let n = payload.len();
  var i = 0;
  while i < n {
    out.push(payload[i]);
    i = i + 1;
  }
  return out;
}

/// Build an ACK packet (opcode 4): `[u16 4][u16 block]`.
/// `block` is clamped to 0..65535.
pub fn tftp_build_ack(block: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_u16_be(&mut out, 4);
  _push_u16_be(&mut out, _clamp_u16(block));
  return out;
}

/// Build an ERROR packet (opcode 5):
/// `[u16 5][u16 code][message][0x00]`. `code` is clamped to 0..65535.
pub fn tftp_build_error(code: Int, message: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_u16_be(&mut out, 5);
  _push_u16_be(&mut out, _clamp_u16(code));
  _push_cstring(&mut out, message);
  return out;
}

// --------------------------------------------------
//  Decoders
// --------------------------------------------------

/// Opcode of `data`: 1 (RRQ), 2 (WRQ), 3 (DATA), 4 (ACK) or 5 (ERROR).
/// Err("tftp: truncated header") when fewer than 2 bytes are present;
/// Err("tftp: unknown opcode") when the big-endian value is outside 1..5.
pub fn tftp_op(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() < 2 {
    return _err_int("tftp: truncated header");
  }
  let op = _u16_be_at(data, 0);
  if op < 1 || op > 5 {
    return _err_int("tftp: unknown opcode");
  }
  return _ok_int(op);
}

/// Parse the (filename, mode) pair of an RRQ (opcode 1) or WRQ (opcode 2).
/// Err("tftp: not an RRQ or WRQ") for any other opcode;
/// Err("tftp: missing NUL terminator") when either string is unterminated.
/// Bytes after the mode terminator (RFC 2347 options) are ignored.
pub fn tftp_parse_rq(data: &Vec[UInt8]) -> Result[(Str, Str), Str] {
  let op = tftp_op(data);
  if !op.is_ok {
    return _err_rq(op.error);
  }
  if op.value != 1 && op.value != 2 {
    return _err_rq("tftp: not an RRQ or WRQ");
  }
  let total = data.len();
  let filename_nul = _nul_at(data, 2, total);
  if filename_nul < 0 {
    return _err_rq("tftp: missing NUL terminator");
  }
  let mode_nul = _nul_at(data, filename_nul + 1, total);
  if mode_nul < 0 {
    return _err_rq("tftp: missing NUL terminator");
  }
  let filename = _str_between(data, 2, filename_nul);
  let mode = _str_between(data, filename_nul + 1, mode_nul);
  return _ok_rq(filename, mode);
}

/// Parse a DATA packet (opcode 3): (block, payload). The payload is every
/// byte after the 4-byte header, copied verbatim (0..512 bytes by
/// convention; longer payloads are not rejected -- see SPEC.md).
/// Err("tftp: not a DATA packet") for any other opcode;
/// Err("tftp: truncated packet") when the 4-byte header is incomplete.
pub fn tftp_parse_data(data: &Vec[UInt8]) -> Result[(Int, Vec[UInt8]), Str] {
  let op = tftp_op(data);
  if !op.is_ok {
    return _err_data(op.error);
  }
  if op.value != 3 {
    return _err_data("tftp: not a DATA packet");
  }
  if data.len() < 4 {
    return _err_data("tftp: truncated packet");
  }
  let block = _u16_be_at(data, 2);
  return _ok_data(block, _copy_bytes(data, 4, data.len()));
}

/// Parse an ACK packet (opcode 4): the big-endian block number.
/// An ACK is exactly 4 bytes: Err("tftp: not an ACK") for any other opcode
/// and Err("tftp: bad ACK length") for any other length.
pub fn tftp_parse_ack(data: &Vec[UInt8]) -> Result[Int, Str] {
  let op = tftp_op(data);
  if !op.is_ok {
    return _err_int(op.error);
  }
  if op.value != 4 {
    return _err_int("tftp: not an ACK");
  }
  if data.len() != 4 {
    return _err_int("tftp: bad ACK length");
  }
  return _ok_int(_u16_be_at(data, 2));
}

/// Parse an ERROR packet (opcode 5): (error code, message). The message is
/// the NUL-terminated byte string after the 4-byte header (may be empty).
/// Err("tftp: not an ERROR packet") for any other opcode;
/// Err("tftp: truncated packet") when fewer than 5 bytes are present;
/// Err("tftp: missing NUL terminator") when the message is unterminated.
pub fn tftp_parse_error(data: &Vec[UInt8]) -> Result[(Int, Str), Str] {
  let op = tftp_op(data);
  if !op.is_ok {
    return _err_error(op.error);
  }
  if op.value != 5 {
    return _err_error("tftp: not an ERROR packet");
  }
  if data.len() < 5 {
    return _err_error("tftp: truncated packet");
  }
  let code = _u16_be_at(data, 2);
  let message_nul = _nul_at(data, 4, data.len());
  if message_nul < 0 {
    return _err_error("tftp: missing NUL terminator");
  }
  return _ok_error(code, _str_between(data, 4, message_nul));
}

/// True when `data` is a DATA packet whose payload is shorter than the
/// classic 512-byte block, i.e. the final block of a transfer. A 512-byte
/// payload is never last. Malformed input propagates the parse_data error
/// catalog.
pub fn tftp_is_last_block(data: &Vec[UInt8]) -> Result[Bool, Str] {
  let op = tftp_op(data);
  if !op.is_ok {
    return _err_bool(op.error);
  }
  if op.value != 3 {
    return _err_bool("tftp: not a DATA packet");
  }
  if data.len() < 4 {
    return _err_bool("tftp: truncated packet");
  }
  return _ok_bool(data.len() - 4 < 512);
}
