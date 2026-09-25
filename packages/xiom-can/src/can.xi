// XIOM -- xiom.can: classic CAN 2.0A/2.0B frame codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) codec for classic CAN 2.0 frames. A frame is the plain
// CanFrame struct (identifier, extended flag, RTR flag, DLC, payload).
// can_encode maps a frame to a fixed 16-byte container and can_decode maps a
// container back; can_validate and the constructors apply the same frame
// invariants before a frame is used.
//
// Container layout (16 bytes; field order follows the classic SocketCAN
// can_frame, multi-byte fields big-endian):
//
//   bytes 0..3  CAN ID word, big-endian unsigned 32-bit:
//                 bit 31 EFF (extended identifier), bit 30 RTR,
//                 bit 29 error-frame flag (rejected), bits 28..0 identifier
//   byte  4     DLC, 0..8
//   bytes 5..7  reserved, must be 0
//   bytes 8..15 data, bytes beyond the DLC must be 0
//
// Canonical form: a data frame carries exactly `dlc` payload bytes
// (data.len() == dlc, dlc <= 8) and a remote frame carries none
// (data.len() == 0; dlc is the requested length). can_decode accepts only
// the canonical form -- a nonzero reserved byte, an unused high identifier
// bit on a standard frame, nonzero padding beyond the DLC and nonzero data
// bytes on an RTR frame are all errors -- so every accepted container
// round-trips byte-for-byte.
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no methods, no lambdas, no Vec[StructType].
//   * Ok/Err construction is confined to the tiny leaf helpers `_ok_*` /
//     `_err_*` below (constructing Results directly inside other functions
//     miscompiles).
//   * the 32-bit ID word is assembled with multiplication and split with
//     arithmetic (modulo/division with a negative-remainder correction): no
//     shift and no bitwise operator is used, because bitwise AND on operands
//     with bit 31 set miscompiles in this compiler (see xiom.bitfield).
//   * every byte read from a Vec[UInt8] is widened with `(x as Int) & 0xFF`
//     before entering Int arithmetic.
//   * `&struct.field` is never passed directly to a `&Vec[UInt8]` parameter
//     (it lowers to an empty vector); the field is bound to a local first.

module xiom.can

/// A classic CAN 2.0 frame.
///
/// Fields: `id` -- 11-bit (standard) or 29-bit (extended) identifier, always
/// non-negative; `extended` -- `true` selects a 29-bit identifier (CAN
/// 2.0B), `false` an 11-bit one (CAN 2.0A); `rtr` -- `true` marks a remote
/// transmission request, which carries no data; `dlc` -- data length code
/// 0..8, on a remote frame the requested payload length; `data` -- payload
/// bytes, on a data frame exactly `dlc` of them, on a remote frame none.
pub type CanFrame = {
  id: Int;
  extended: Bool;
  rtr: Bool;
  dlc: Int;
  data: Vec[UInt8];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[CanFrame, Str].
fn _ok_frame(v: CanFrame) -> Result[CanFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[CanFrame, Str].
fn _err_frame(m: Str) -> Result[CanFrame, Str] {
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

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal arithmetic
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Byte `k` (0 = least significant) of the low 32 bits of `v`, as 0..255.
// Arithmetic only: no shift and no bitwise AND (see the module header).
fn _low_byte(v: Int, k: Int) -> Int {
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

// --------------------------------------------------
//  Identifier helpers
// --------------------------------------------------

/// Largest identifier accepted for the given type: 2047 (0x7FF) for a
/// standard 11-bit identifier, 536870911 (0x1FFFFFFF) for an extended
/// 29-bit one. Complexity: O(1).
pub fn can_max_id(extended: Bool) -> Int {
  if extended {
    return 536870911;
  }
  return 2047;
}

/// True when `id` is a valid identifier of the given type: 0..2047 for a
/// standard identifier, 0..536870911 for an extended one. Complexity: O(1).
pub fn can_id_ok(id: Int, extended: Bool) -> Bool {
  if id < 0 {
    return false;
  }
  return id <= can_max_id(extended);
}

/// The raw 32-bit CAN ID word of a frame: bit 31 set when `extended`, bit 30
/// set when `rtr`, identifier in bits 28..0. No validation is performed; the
/// result is meaningful for a valid frame. Complexity: O(1).
pub fn can_id_word(f: &CanFrame) -> Int {
  var word = f.id;
  if f.extended {
    word = word + 2147483648;
  }
  if f.rtr {
    word = word + 1073741824;
  }
  return word;
}

// --------------------------------------------------
//  Sizes
// --------------------------------------------------

/// Encoded container size in bytes (16: four ID-word bytes, the DLC byte,
/// three reserved bytes and eight data bytes). Complexity: O(1).
pub fn can_encoded_size() -> Int {
  return 16;
}

// --------------------------------------------------
//  Validation and construction
// --------------------------------------------------

/// Validate every frame invariant, in this order: identifier range by type,
/// payload length at most 8 bytes, DLC in 0..8, then the RTR/data rules (a
/// remote frame carries no data; a data frame carries exactly `dlc` bytes).
///
/// Returns: Ok(()) for a canonical frame.
/// Error case: Err("can: negative identifier"), Err("can: identifier
/// exceeds standard range"), Err("can: identifier exceeds extended range"),
/// Err("can: payload exceeds 8 bytes"), Err("can: invalid dlc"),
/// Err("can: remote frame carries data") or Err("can: data length does not
/// match dlc"). Complexity: O(payload).
pub fn can_validate(f: &CanFrame) -> Result[Unit, Str] {
  if f.id < 0 {
    return _err_unit("can: negative identifier");
  }
  if f.extended {
    if f.id > 536870911 {
      return _err_unit("can: identifier exceeds extended range");
    }
  } else {
    if f.id > 2047 {
      return _err_unit("can: identifier exceeds standard range");
    }
  }
  let d: Vec[UInt8] = f.data;
  if d.len() > 8 {
    return _err_unit("can: payload exceeds 8 bytes");
  }
  if f.dlc < 0 || f.dlc > 8 {
    return _err_unit("can: invalid dlc");
  }
  if f.rtr {
    if d.len() != 0 {
      return _err_unit("can: remote frame carries data");
    }
  } else {
    if d.len() != f.dlc {
      return _err_unit("can: data length does not match dlc");
    }
  }
  return _ok_unit();
}

/// Build a frame from the five fields, copying `data` and validating the
/// result with can_validate (same error catalog and order). For a data
/// frame `dlc` must equal `data.len()`; for a remote frame `data` must be
/// empty. Complexity: O(payload).
pub fn can_new(id: Int, extended: Bool, rtr: Bool, dlc: Int, data: &Vec[UInt8]) -> Result[CanFrame, Str] {
  var d = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    d.push(data[i]);
    i = i + 1;
  }
  let f = CanFrame{ id: id; extended: extended; rtr: rtr; dlc: dlc; data: d; };
  let vr = can_validate(&f);
  if !vr.is_ok {
    return _err_frame(vr.error);
  }
  return _ok_frame(f);
}

/// Build a data frame whose DLC is the payload length.
///
/// Returns: Ok(frame) with `dlc == data.len()` (0..8).
/// Error case: can_validate's catalog -- a payload longer than 8 bytes is
/// Err("can: payload exceeds 8 bytes"), an out-of-range identifier its range
/// error. Complexity: O(payload).
pub fn can_data_frame(id: Int, extended: Bool, data: &Vec[UInt8]) -> Result[CanFrame, Str] {
  return can_new(id, extended, false, data.len(), data);
}

/// Build a remote (RTR) frame that requests `dlc` bytes and carries no data.
///
/// Returns: Ok(frame) with `rtr == true` and an empty payload.
/// Error case: can_validate's catalog -- an out-of-range identifier its
/// range error, a DLC outside 0..8 Err("can: invalid dlc").
/// Complexity: O(1).
pub fn can_remote_frame(id: Int, extended: Bool, dlc: Int) -> Result[CanFrame, Str] {
  var empty = Vec[UInt8].new();
  return can_new(id, extended, true, dlc, &empty);
}

// --------------------------------------------------
//  Encode
// --------------------------------------------------

/// Append the 16-byte container of `f` to `out`.
///
/// The frame is validated first, so an invalid frame is an Err and `out` is
/// byte-for-byte unchanged (atomic failure). The ID word is written
/// big-endian with bit 31 for extended and bit 30 for RTR; a data frame
/// writes exactly `dlc` payload bytes and a remote frame writes `dlc` zero
/// bytes.
/// Returns: Ok(()) on success.
/// Error case: the can_validate catalog. Complexity: O(payload).
pub fn can_encode_into(out: &mut Vec[UInt8], f: &CanFrame) -> Result[Unit, Str] {
  let vr = can_validate(f);
  if !vr.is_ok {
    return _err_unit(vr.error);
  }
  let word = can_id_word(f);
  out.push(_low_byte(word, 3) as UInt8);
  out.push(_low_byte(word, 2) as UInt8);
  out.push(_low_byte(word, 1) as UInt8);
  out.push(_low_byte(word, 0) as UInt8);
  out.push(f.dlc as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  var i = 0;
  while i < 8 {
    if i < f.data.len() {
      out.push(f.data[i]);
    } else {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
  return _ok_unit();
}

/// Encode `f` into a fresh 16-byte container (can_encoded_size()). Same
/// validation and error catalog as can_encode_into.
/// Complexity: O(payload).
pub fn can_encode(f: &CanFrame) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let ar = can_encode_into(&mut out, f);
  if !ar.is_ok {
    return _err_bytes(ar.error);
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Decode
// --------------------------------------------------

/// Decode the first 16 bytes of `bytes` into a frame; bytes beyond the first
/// 16 are ignored, so a buffer may hold several concatenated containers.
///
/// Only the canonical form is accepted, in this check order:
/// Err("can: truncated frame") when `bytes.len() < 16`; Err("can: error
/// frame flag set") when ID-word bit 29 is set; Err("can: identifier exceeds
/// standard range") for a standard frame with a nonzero bit above bit 10;
/// Err("can: invalid dlc") when the DLC byte is outside 0..8; Err("can:
/// nonzero reserved byte") when byte 5, 6 or 7 is nonzero; then Err("can:
/// nonzero rtr data byte") for a remote frame with any nonzero data byte or
/// Err("can: nonzero padding byte") for a data frame with a nonzero byte
/// beyond its DLC. A remote frame decodes with an empty payload and its DLC
/// preserved. Complexity: O(payload).
pub fn can_decode(bytes: &Vec[UInt8]) -> Result[CanFrame, Str] {
  if bytes.len() < 16 {
    return _err_frame("can: truncated frame");
  }
  let b0 = _byte(bytes, 0);
  let b1 = _byte(bytes, 1);
  let b2 = _byte(bytes, 2);
  let b3 = _byte(bytes, 3);
  var rest = b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
  var extended = false;
  if rest >= 2147483648 {
    extended = true;
    rest = rest - 2147483648;
  }
  var rtr = false;
  if rest >= 1073741824 {
    rtr = true;
    rest = rest - 1073741824;
  }
  if rest >= 536870912 {
    return _err_frame("can: error frame flag set");
  }
  let id = rest;
  if !extended && id > 2047 {
    return _err_frame("can: identifier exceeds standard range");
  }
  let dlc = _byte(bytes, 4);
  if dlc > 8 {
    return _err_frame("can: invalid dlc");
  }
  var k = 5;
  while k < 8 {
    if _byte(bytes, k) != 0 {
      return _err_frame("can: nonzero reserved byte");
    }
    k = k + 1;
  }
  var d = Vec[UInt8].new();
  if rtr {
    var j = 8;
    while j < 16 {
      if _byte(bytes, j) != 0 {
        return _err_frame("can: nonzero rtr data byte");
      }
      j = j + 1;
    }
  } else {
    var j = 8;
    while j < 16 {
      if j < 8 + dlc {
        d.push(bytes[j]);
      } elif _byte(bytes, j) != 0 {
        return _err_frame("can: nonzero padding byte");
      }
      j = j + 1;
    }
  }
  let f = CanFrame{ id: id; extended: extended; rtr: rtr; dlc: dlc; data: d; };
  return _ok_frame(f);
}

// --------------------------------------------------
//  Accessors and equality
// --------------------------------------------------

/// True when the frame carries a 29-bit extended identifier (CAN 2.0B).
/// Complexity: O(1).
pub fn can_is_extended(f: &CanFrame) -> Bool {
  return f.extended;
}

/// True when the frame is a remote transmission request (RTR).
/// Complexity: O(1).
pub fn can_is_remote(f: &CanFrame) -> Bool {
  return f.rtr;
}

/// Number of payload bytes carried by the frame: `data.len()`, which is 0
/// for a canonical remote frame. Complexity: O(1).
pub fn can_payload_len(f: &CanFrame) -> Int {
  let d: Vec[UInt8] = f.data;
  return d.len();
}

/// Payload byte `i` widened to 0..255, or -1 when `i` is negative or beyond
/// the payload. Complexity: O(1).
pub fn can_data_get(f: &CanFrame, i: Int) -> Int {
  let d: Vec[UInt8] = f.data;
  if i < 0 || i >= d.len() {
    return -1;
  }
  return (d[i] as Int) & 0xFF;
}

/// Structural equality: same identifier, type, RTR flag, DLC and payload
/// byte sequence. Complexity: O(payload).
pub fn can_equal(a: &CanFrame, b: &CanFrame) -> Bool {
  if a.id != b.id {
    return false;
  }
  if a.extended != b.extended {
    return false;
  }
  if a.rtr != b.rtr {
    return false;
  }
  if a.dlc != b.dlc {
    return false;
  }
  let ad: Vec[UInt8] = a.data;
  let bd: Vec[UInt8] = b.data;
  if ad.len() != bd.len() {
    return false;
  }
  var i = 0;
  while i < ad.len() {
    if ad[i] != bd[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}
