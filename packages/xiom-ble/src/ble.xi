// XIOM -- xiom.ble: Bluetooth LE advertising-data codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) codec for the legacy Bluetooth Low Energy advertising
// payload: a flat sequence of AD structures, each one length byte, one AD
// type byte and `length - 1` data bytes. ble_parse walks the buffer and
// returns an AdList index (types plus absolute data offsets/lengths); the
// builders (ble_ad, ble_ad_flags, ble_ad_name_*, ...) produce one complete
// AD structure with the length byte recomputed; ble_append_ad and
// ble_build_from concatenate structures; ble_validate additionally enforces
// the 31-byte legacy advertising limit. See SPEC.md for the exact layout,
// helper set, error catalog and documented limitations (no HCI, no extended
// advertising, no GATT, no scanning).
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic, and no
//     UInt8 is ever compared against a literal >= 128.
//   * multi-byte fields are little-endian on the air; extraction and packing
//     are arithmetic (modulo/division), never shifts.

module xiom.ble

use xiom.string;

/// Parsed advertising-data index. One entry per AD structure, in wire order.
/// The data bytes stay in the source buffer and are located by
/// `data_offsets` (absolute index of the first data byte) and
/// `data_lengths`. Fields are implementation details; callers should go
/// through the free functions below.
pub type AdList = {
  ad_types: Vec[Int];
  data_offsets: Vec[Int];
  data_lengths: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[AdList, Str].
fn _ok_list(v: AdList) -> Result[AdList, Str] {
  return Ok(v);
}

// Err(m) for Result[AdList, Str].
fn _err_list(m: Str) -> Result[AdList, Str] {
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
fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_ints(m: Str) -> Result[Vec[Int], Str] {
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

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers (little-endian, arithmetic only)
// --------------------------------------------------

// The low byte of the raw two's-complement bit pattern of `v`.
fn _low_byte(v: Int) -> UInt8 {
  var r = v % 256;
  if r < 0 { r = r + 256; }
  return r as UInt8;
}

// `v` shifted right by `k` bytes (arithmetic, two's-complement aware).
fn _byte_shift(v: Int, k: Int) -> Int {
  var q = v;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    i = i + 1;
  }
  return q;
}

// Append the low 2 bytes of `v`, least significant byte first (BLE wire
// order). Callers validate the range; the cast masks to 16 bits.
fn _push_u16_le(out: &mut Vec[UInt8], v: Int) {
  out.push(_low_byte(v));
  out.push(_low_byte(_byte_shift(v, 1)));
}

// Append every byte of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Byte at `pos` widened to an Int in 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned 16-bit little-endian value of the 2 bytes at `off`.
fn _u16_le(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + 256 * _byte(data, off + 1);
}

// Unsigned 32-bit little-endian value of the 4 bytes at `off`.
fn _u32_le(data: &Vec[UInt8], off: Int) -> Int {
  return _u16_le(data, off) + 65536 * _u16_le(data, off + 2);
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse a legacy advertising payload (a flat sequence of AD structures).
///
/// Each structure is one length byte `L`, one AD type byte and `L - 1` data
/// bytes; entries are walked until the buffer ends, so a declared length that
/// does not fit is an error, never a silent stop. Unknown AD types are
/// preserved verbatim in the returned AdList.
///
/// Err("ble: zero-length AD structure") when a length byte is 0;
/// Err("ble: truncated AD structure") when a length byte is present but the
/// buffer ends before the mandatory type byte; Err("ble: AD length overruns
/// buffer") when the type byte is present but fewer than `L - 1` data bytes
/// remain. An empty buffer yields Ok with zero entries.
/// Complexity: O(data.len()).
pub fn ble_parse(data: &Vec[UInt8]) -> Result[AdList, Str] {
  var types = Vec[Int].new();
  var offsets = Vec[Int].new();
  var lengths = Vec[Int].new();
  let total = data.len();
  var pos = 0;
  while pos < total {
    let len = _byte(data, pos);
    pos = pos + 1;
    if len == 0 {
      return _err_list("ble: zero-length AD structure");
    }
    let remaining = total - pos;
    if remaining < len {
      if remaining == 0 {
        return _err_list("ble: truncated AD structure");
      }
      return _err_list("ble: AD length overruns buffer");
    }
    types.push(_byte(data, pos));
    offsets.push(pos + 1);
    lengths.push(len - 1);
    pos = pos + len;
  }
  return _ok_list(AdList{ ad_types: types; data_offsets: offsets; data_lengths: lengths; });
}

/// Number of parsed AD structures.
/// Complexity: O(1).
pub fn ble_count(l: &AdList) -> Int {
  return l.ad_types.len();
}

/// AD type byte of entry `i`, or -1 when i is negative or >= ble_count(l).
/// Complexity: O(1).
pub fn ble_type(l: &AdList, i: Int) -> Int {
  if i < 0 || i >= l.ad_types.len() {
    return -1;
  }
  return l.ad_types[i];
}

/// First entry index whose AD type equals `ad_type`, or -1 when absent.
/// Complexity: O(entries).
pub fn ble_find(l: &AdList, ad_type: Int) -> Int {
  var i = 0;
  while i < l.ad_types.len() {
    let t: Int = l.ad_types[i];
    if t == ad_type {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// True when at least one parsed entry has AD type `ad_type`.
/// Complexity: O(entries).
pub fn ble_has(l: &AdList, ad_type: Int) -> Bool {
  return ble_find(l, ad_type) >= 0;
}

/// Copy the data bytes of entry `i` out of `data`.
///
/// `data` must be the buffer the list was parsed from (or one holding at
/// least the recorded span). Err("ble: index out of range") when i is
/// negative or >= ble_count(l); Err("ble: data out of bounds") when the
/// recorded span does not fit `data`.
/// Complexity: O(data length).
pub fn ble_data(data: &Vec[UInt8], l: &AdList, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= l.ad_types.len() {
    return _err_bytes("ble: index out of range");
  }
  let off: Int = l.data_offsets[i];
  let len: Int = l.data_lengths[i];
  if off < 0 || len < 0 {
    return _err_bytes("ble: data out of bounds");
  }
  if off + len > data.len() {
    return _err_bytes("ble: data out of bounds");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Total encoded size of entry `i`: 1 length byte + 1 type byte + data
/// length. Returns -1 when i is negative or >= ble_count(l).
/// Complexity: O(1).
pub fn ble_ad_size(l: &AdList, i: Int) -> Int {
  if i < 0 || i >= l.ad_types.len() {
    return -1;
  }
  let n: Int = l.data_lengths[i];
  return n + 2;
}

/// Total encoded size of every parsed entry (the byte length the buffer
/// would have if rebuilt with ble_build_from).
/// Complexity: O(entries).
pub fn ble_total_length(l: &AdList) -> Int {
  var total: Int = 0;
  var i = 0;
  while i < l.data_lengths.len() {
    let n: Int = l.data_lengths[i];
    total = total + n + 2;
    i = i + 1;
  }
  return total;
}

// --------------------------------------------------
//  Typed data decoders
// --------------------------------------------------

/// Flags value (AD type 0x01): exactly 1 data byte, 0..255.
/// Err("ble: wrong data length") when payload.len() != 1.
/// Complexity: O(1).
pub fn ble_decode_flags(payload: &Vec[UInt8]) -> Result[Int, Str] {
  if payload.len() != 1 {
    return _err_int("ble: wrong data length");
  }
  return _ok_int(_byte(payload, 0));
}

/// TX Power Level in dBm (AD type 0x0A): exactly 1 data byte, sign-extended
/// to -128..127.
/// Err("ble: wrong data length") when payload.len() != 1.
/// Complexity: O(1).
pub fn ble_decode_tx_power(payload: &Vec[UInt8]) -> Result[Int, Str] {
  if payload.len() != 1 {
    return _err_int("ble: wrong data length");
  }
  let b = _byte(payload, 0);
  if b >= 128 {
    return _ok_int(b - 256);
  }
  return _ok_int(b);
}

/// 16-bit service UUID (AD types 0x02/0x03): exactly 2 little-endian bytes,
/// 0..65535. Err("ble: wrong data length") when payload.len() != 2.
/// Complexity: O(1).
pub fn ble_decode_uuid16(payload: &Vec[UInt8]) -> Result[Int, Str] {
  if payload.len() != 2 {
    return _err_int("ble: wrong data length");
  }
  return _ok_int(_u16_le(payload, 0));
}

/// 32-bit service UUID (AD types 0x04/0x05): exactly 4 little-endian bytes,
/// 0..4294967295. Err("ble: wrong data length") when payload.len() != 4.
/// Complexity: O(1).
pub fn ble_decode_uuid32(payload: &Vec[UInt8]) -> Result[Int, Str] {
  if payload.len() != 4 {
    return _err_int("ble: wrong data length");
  }
  return _ok_int(_u32_le(payload, 0));
}

/// Manufacturer company identifier (AD type 0xFF): at least 2 little-endian
/// bytes; the identifier is the first 2 bytes, 0..65535. Err("ble: wrong
/// data length") when payload.len() < 2.
/// Complexity: O(1).
pub fn ble_decode_manufacturer_id(payload: &Vec[UInt8]) -> Result[Int, Str] {
  if payload.len() < 2 {
    return _err_int("ble: wrong data length");
  }
  return _ok_int(_u16_le(payload, 0));
}

/// Slave Connection Interval Range (AD type 0x12): exactly 4 little-endian
/// bytes, two 16-bit units of 1.25 ms, returned as [min, max].
/// Err("ble: wrong data length") when payload.len() != 4; Err("ble:
/// connection interval min above max") when min > max.
/// Complexity: O(1).
pub fn ble_decode_slave_interval(payload: &Vec[UInt8]) -> Result[Vec[Int], Str] {
  if payload.len() != 4 {
    return _err_ints("ble: wrong data length");
  }
  let lo = _u16_le(payload, 0);
  let hi = _u16_le(payload, 2);
  if lo > hi {
    return _err_ints("ble: connection interval min above max");
  }
  var out = Vec[Int].new();
  out.push(lo);
  out.push(hi);
  return _ok_ints(out);
}

// --------------------------------------------------
//  Structure builders
// --------------------------------------------------

/// Build one AD structure from an arbitrary type byte and data payload:
/// 1 length byte (`payload.len() + 1`), the type byte, then the payload
/// verbatim.
/// Err("ble: AD type out of range") when ad_type is outside 0..255;
/// Err("ble: payload too large") when payload.len() > 254 (the length byte
/// counts the type byte, so 254 data bytes is the maximum).
/// Complexity: O(payload length).
pub fn ble_ad(ad_type: Int, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if ad_type < 0 || ad_type > 255 {
    return _err_bytes("ble: AD type out of range");
  }
  let n = payload.len();
  if n > 254 {
    return _err_bytes("ble: payload too large");
  }
  var out = Vec[UInt8].new();
  out.push((n + 1) as UInt8);
  out.push(ad_type as UInt8);
  _push_bytes(&mut out, payload);
  return _ok_bytes(out);
}

/// Flags (AD type 0x01) with one flags byte, 0..255.
/// Err("ble: flags out of range") when flags is outside 0..255.
/// Complexity: O(1).
pub fn ble_ad_flags(flags: Int) -> Result[Vec[UInt8], Str] {
  if flags < 0 || flags > 255 {
    return _err_bytes("ble: flags out of range");
  }
  var payload = Vec[UInt8].new();
  payload.push(flags as UInt8);
  return ble_ad(1, &payload);
}

// Shared implementation of the short/full local-name builders.
fn _name_ad(ad_type: Int, name: Str) -> Result[Vec[UInt8], Str] {
  let n = name.len();
  if n == 0 {
    return _err_bytes("ble: empty local name");
  }
  if n > 254 {
    return _err_bytes("ble: name too long");
  }
  var payload = Vec[UInt8].new();
  var i = 0;
  while i < n {
    payload.push(string.byte_at(name, i));
    i = i + 1;
  }
  return ble_ad(ad_type, &payload);
}

/// Shortened Local Name (AD type 0x08). The name bytes are copied verbatim
/// (no UTF-8 validation).
/// Err("ble: empty local name") when name is empty; Err("ble: name too
/// long") when the name exceeds 254 bytes.
/// Complexity: O(name length).
pub fn ble_ad_name_short(name: Str) -> Result[Vec[UInt8], Str] {
  return _name_ad(8, name);
}

/// Complete Local Name (AD type 0x09). The name bytes are copied verbatim
/// (no UTF-8 validation).
/// Err("ble: empty local name") when name is empty; Err("ble: name too
/// long") when the name exceeds 254 bytes.
/// Complexity: O(name length).
pub fn ble_ad_name_complete(name: Str) -> Result[Vec[UInt8], Str] {
  return _name_ad(9, name);
}

/// TX Power Level (AD type 0x0A) in dBm, -128..127.
/// Err("ble: TX power out of range") when dbm is outside -128..127.
/// Complexity: O(1).
pub fn ble_ad_tx_power(dbm: Int) -> Result[Vec[UInt8], Str] {
  if dbm < -128 || dbm > 127 {
    return _err_bytes("ble: TX power out of range");
  }
  var payload = Vec[UInt8].new();
  payload.push(_low_byte(dbm));
  return ble_ad(10, &payload);
}

/// 16-bit Service Class UUID (AD type 0x03 when `complete`, 0x02 otherwise),
/// little-endian on the wire.
/// Err("ble: UUID out of range") when uuid is outside 0..65535.
/// Complexity: O(1).
pub fn ble_ad_service_uuid16(uuid: Int, complete: Bool) -> Result[Vec[UInt8], Str] {
  if uuid < 0 || uuid > 65535 {
    return _err_bytes("ble: UUID out of range");
  }
  var payload = Vec[UInt8].new();
  _push_u16_le(&mut payload, uuid);
  if complete {
    return ble_ad(3, &payload);
  }
  return ble_ad(2, &payload);
}

/// 32-bit Service Class UUID (AD type 0x05 when `complete`, 0x04 otherwise),
/// little-endian on the wire.
/// Err("ble: UUID out of range") when uuid is outside 0..4294967295.
/// Complexity: O(1).
pub fn ble_ad_service_uuid32(uuid: Int, complete: Bool) -> Result[Vec[UInt8], Str] {
  if uuid < 0 || uuid > 4294967295 {
    return _err_bytes("ble: UUID out of range");
  }
  var payload = Vec[UInt8].new();
  _push_u16_le(&mut payload, uuid);
  _push_u16_le(&mut payload, _byte_shift(uuid, 2));
  if complete {
    return ble_ad(5, &payload);
  }
  return ble_ad(4, &payload);
}

/// 128-bit Service Class UUID (AD type 0x07 when `complete`, 0x06
/// otherwise). `uuid` must hold the 16 UUID bytes in on-air order (LE) and
/// is copied verbatim.
/// Err("ble: 128-bit UUID must be 16 bytes") when uuid.len() != 16.
/// Complexity: O(1).
pub fn ble_ad_service_uuid128(uuid: &Vec[UInt8], complete: Bool) -> Result[Vec[UInt8], Str] {
  if uuid.len() != 16 {
    return _err_bytes("ble: 128-bit UUID must be 16 bytes");
  }
  if complete {
    return ble_ad(7, uuid);
  }
  return ble_ad(6, uuid);
}

/// Slave Connection Interval Range (AD type 0x12): two 16-bit units of
/// 1.25 ms, little-endian, written as [min_units, max_units].
/// Err("ble: connection interval out of range") when either unit is outside
/// 6..3200 (7.5 ms..4 s, the spec range); Err("ble: connection interval min
/// above max") when min_units > max_units.
/// Complexity: O(1).
pub fn ble_ad_slave_interval(min_units: Int, max_units: Int) -> Result[Vec[UInt8], Str] {
  if min_units < 6 || min_units > 3200 {
    return _err_bytes("ble: connection interval out of range");
  }
  if max_units < 6 || max_units > 3200 {
    return _err_bytes("ble: connection interval out of range");
  }
  if min_units > max_units {
    return _err_bytes("ble: connection interval min above max");
  }
  var payload = Vec[UInt8].new();
  _push_u16_le(&mut payload, min_units);
  _push_u16_le(&mut payload, max_units);
  return ble_ad(18, &payload);
}

/// Service Data with a 16-bit UUID (AD type 0x16): the UUID little-endian,
/// then `payload` verbatim.
/// Err("ble: UUID out of range") when uuid is outside 0..65535;
/// Err("ble: payload too large") when payload.len() > 252 (so the length
/// byte stays <= 255).
/// Complexity: O(payload length).
pub fn ble_ad_service_data16(uuid: Int, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if uuid < 0 || uuid > 65535 {
    return _err_bytes("ble: UUID out of range");
  }
  if payload.len() > 252 {
    return _err_bytes("ble: payload too large");
  }
  var data = Vec[UInt8].new();
  _push_u16_le(&mut data, uuid);
  _push_bytes(&mut data, payload);
  return ble_ad(22, &data);
}

/// Manufacturer Specific Data (AD type 0xFF): the 16-bit company identifier
/// little-endian, then `payload` verbatim.
/// Err("ble: manufacturer ID out of range") when id is outside 0..65535;
/// Err("ble: payload too large") when payload.len() > 252 (so the length
/// byte stays <= 255).
/// Complexity: O(payload length).
pub fn ble_ad_manufacturer(id: Int, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if id < 0 || id > 65535 {
    return _err_bytes("ble: manufacturer ID out of range");
  }
  if payload.len() > 252 {
    return _err_bytes("ble: payload too large");
  }
  var data = Vec[UInt8].new();
  _push_u16_le(&mut data, id);
  _push_bytes(&mut data, payload);
  return ble_ad(255, &data);
}

// --------------------------------------------------
//  Concatenation and validation
// --------------------------------------------------

/// Append the bytes of one complete AD structure (as returned by the
/// builders above) to `out` verbatim. No validation is performed: the input
/// is copied as-is, so a malformed structure stays malformed (use
/// ble_validate on the assembled payload to check it).
/// Complexity: O(ad length).
pub fn ble_append_structure(out: &mut Vec[UInt8], ad: &Vec[UInt8]) {
  _push_bytes(out, ad);
}

/// Append one complete AD structure to `out` (the generic ble_ad structure
/// with the length byte recomputed).
///
/// Validation happens before any byte is copied, so `out` is unchanged on
/// Err. Error cases are exactly those of ble_ad: Err("ble: AD type out of
/// range") / Err("ble: payload too large").
/// Complexity: O(payload length).
pub fn ble_append_ad(out: &mut Vec[UInt8], ad_type: Int, payload: &Vec[UInt8]) -> Result[Unit, Str] {
  let built = ble_ad(ad_type, payload);
  if !built.is_ok {
    return _err_unit(built.error);
  }
  let b: Vec[UInt8] = built.value;
  _push_bytes(out, &b);
  return _ok_unit();
}

/// Build a whole advertising payload from parallel type/payload vectors,
/// using ble_append_ad for every entry.
///
/// Err("ble: types/payloads length mismatch") when the vectors differ in
/// length; otherwise the first per-entry failure of ble_append_ad (same
/// messages). An empty pair of vectors yields Ok(empty). The 31-byte legacy
/// limit is not enforced here; use ble_validate on the result.
/// Complexity: O(total payload bytes).
pub fn ble_build_from(types: &Vec[Int], payloads: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  if types.len() != payloads.len() {
    return _err_bytes("ble: types/payloads length mismatch");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < types.len() {
    let t: Int = types[i];
    let p: Vec[UInt8] = payloads[i];
    let ar = ble_append_ad(&mut out, t, &p);
    if !ar.is_ok {
      return _err_bytes(ar.error);
    }
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// The maximum payload size of legacy BLE advertising data, in bytes (31).
/// Complexity: O(1).
pub fn ble_legacy_limit() -> Int {
  return 31;
}

/// Validate a buffer as a legacy advertising payload: it must parse as AD
/// structures (ble_parse) and be at most ble_legacy_limit() bytes long.
///
/// Structural errors from ble_parse are reported first; a structurally valid
/// payload longer than 31 bytes is Err("ble: payload exceeds 31-byte legacy
/// limit"). An empty buffer is Ok.
/// Complexity: O(data.len()).
pub fn ble_validate(data: &Vec[UInt8]) -> Result[Unit, Str] {
  let r = ble_parse(data);
  if !r.is_ok {
    return _err_unit(r.error);
  }
  if data.len() > ble_legacy_limit() {
    return _err_unit("ble: payload exceeds 31-byte legacy limit");
  }
  return _ok_unit();
}
