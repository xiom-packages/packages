// XIOM -- xiom.ntp: NTPv4 packet codec (RFC 5905 subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) encode/decode for the fixed 48-byte NTPv4 packet
// defined by RFC 5905: the packed LI/VN/Mode byte, stratum, poll,
// precision, root delay and root dispersion (16.16 fixed point), reference
// id, and the reference/origin/receive/transmit timestamps (32.32 fixed
// point, seconds since 1900-01-01). See SPEC.md for the byte layout, the
// fixed-point conventions, the error catalog and the documented limits.
//
// Scope: the packet codec, version/mode validation, integer-only timestamp
// conversion (fraction <-> microseconds/nanoseconds) and the RFC 5905
// offset/delay formulas in whole microseconds. A zero timestamp means
// "unsynchronized" and the offset/delay helpers reject it. Non-goals: no
// sockets, no clock discipline, no NTS/authentication extensions, no
// leap-second tables.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[StructType]. A
//     packet is a plain value type with four nested NtpTimestamp values
//     (nested plain structs are supported; vectors of structs are not).
//   * Ok/Err construction is confined to the tiny leaf helpers below;
//     constructing Results directly inside other functions miscompiles.
//   * all byte extraction/packing is arithmetic (modulo/division with a
//     negative-remainder correction): `& 0xFF`/shifts on operands with bit
//     31 set miscompile in v0.61.3, so the 32-bit fields (the negative
//     root delay and every 32.32 timestamp half) stay exact.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * a 32.32 timestamp never exists as one Int (seconds and fraction are
//     carried separately), so no intermediate exceeds INT64_MAX and no
//     Float64 is involved anywhere.

module xiom.ntp

// One NTP timestamp: `seconds` whole seconds since 1900-01-01 (0..2^32-1,
// the 32-bit NTP era field) and `fraction` in units of 2^-32 s
// (0..2^32-1). The all-zero timestamp is the "unsynchronized" marker.
pub type NtpTimestamp = {
  seconds: Int;
  fraction: Int;
}

// A decoded NTPv4 packet. Scalar fields are the raw wire values: `li` is
// 0..3, `vn` is 3..4 for a valid packet, `mode` is 1..6, `stratum` is
// 0..255, `poll` and `precision` are signed 8-bit log2 values, and
// `root_delay` (signed) / `root_dispersion` (unsigned) are raw 16.16
// fixed-point units (1 unit = 2^-16 s). The four timestamps are nested
// 32.32 values.
pub type NtpPacket = {
  li: Int;
  vn: Int;
  mode: Int;
  stratum: Int;
  poll: Int;
  precision: Int;
  root_delay: Int;
  root_dispersion: Int;
  reference_id: Int;
  reference: NtpTimestamp;
  origin: NtpTimestamp;
  receive: NtpTimestamp;
  transmit: NtpTimestamp;
}

// Wire size of an NTPv4 packet in bytes.
pub const NTP_PACKET_SIZE: Int = 48;

// Number of fraction units in one second: 2^32.
pub const NTP_FRACTION_UNITS: Int = 4294967296;

// Largest 32-bit wire value: 2^32-1. Used for the unsigned 32-bit fields
// (fraction, seconds, root dispersion, reference id).
pub const NTP_FRACTION_MAX: Int = 4294967295;

// Largest NTP seconds value: 2^32-1.
pub const NTP_SECONDS_MAX: Int = 4294967295;

// NTP protocol versions accepted by this codec (RFC 5905).
pub const NTP_VERSION_3: Int = 3;
pub const NTP_VERSION_4: Int = 4;

// Mode values defined by RFC 5905. Mode 0 (reserved) and mode 7
// (reserved/private) are rejected; 1..6 are accepted.
pub const NTP_MODE_SYMMETRIC_ACTIVE: Int = 1;
pub const NTP_MODE_SYMMETRIC_PASSIVE: Int = 2;
pub const NTP_MODE_CLIENT: Int = 3;
pub const NTP_MODE_SERVER: Int = 4;
pub const NTP_MODE_BROADCAST: Int = 5;
pub const NTP_MODE_CONTROL: Int = 6;

// Leap indicator values: 0 = no warning, 1 = last minute has 61 s,
// 2 = last minute has 59 s, 3 = unsynchronized/unknown.
pub const NTP_LI_NONE: Int = 0;
pub const NTP_LI_LAST_MINUTE_61: Int = 1;
pub const NTP_LI_LAST_MINUTE_59: Int = 2;
pub const NTP_LI_UNSYNCHRONIZED: Int = 3;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[NtpPacket, Str].
fn _ok_packet(v: NtpPacket) -> Result[NtpPacket, Str] {
  return Ok(v);
}

// Err(m) for Result[NtpPacket, Str].
fn _err_packet(m: Str) -> Result[NtpPacket, Str] {
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

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte primitives (arithmetic only; see module header)
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); the caller bounds it.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Big-endian byte `shift_bytes` of the raw two's-complement pattern of `v`
// (0 = least significant byte). Exact for negative values.
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

// Unsigned big-endian Int of the `size` bytes at `pos` (0..2^(8*size)-1).
fn _read_be(data: &Vec[UInt8], pos: Int, size: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < size {
    v = v * 256 + _byte(data, pos + i);
    i = i + 1;
  }
  return v;
}

// Append one 32.32 timestamp as eight big-endian bytes.
fn _push_ts(out: &mut Vec[UInt8], t: &NtpTimestamp) {
  _push_be(out, t.seconds, 4);
  _push_be(out, t.fraction, 4);
}

// --------------------------------------------------
//  Range helpers
// --------------------------------------------------

// True when 0 <= v <= 255.
fn _u8_ok(v: Int) -> Bool {
  return v >= 0 && v <= 255;
}

// True when -128 <= v <= 127.
fn _i8_ok(v: Int) -> Bool {
  return v >= -128 && v <= 127;
}

// True when 0 <= v <= 2^32-1.
fn _u32_ok(v: Int) -> Bool {
  return v >= 0 && v <= NTP_FRACTION_MAX;
}

// True when -2^31 <= v <= 2^31-1.
fn _i32_ok(v: Int) -> Bool {
  return v >= -2147483648 && v <= 2147483647;
}

// True when 0 <= v <= 3 (leap indicator).
fn _li_ok(v: Int) -> Bool {
  return v >= 0 && v <= 3;
}

// Wire byte 0..255 as a signed 8-bit Int.
fn _to_i8(v: Int) -> Int {
  if v >= 128 {
    return v - 256;
  }
  return v;
}

// Wire 32-bit unsigned Int as a signed 32-bit Int (two's complement).
fn _to_i32(v: Int) -> Int {
  if v >= 2147483648 {
    return v - NTP_FRACTION_UNITS;
  }
  return v;
}

// --------------------------------------------------
//  Timestamps
// --------------------------------------------------

/// Construct a timestamp from raw field values, without validation.
/// `seconds` and `fraction` must each be 0..2^32-1 for a valid timestamp;
/// see ntp_timestamp_is_valid.
/// Complexity: O(1).
pub fn ntp_timestamp_new(seconds: Int, fraction: Int) -> NtpTimestamp {
  return NtpTimestamp{ seconds: seconds; fraction: fraction; };
}

/// The all-zero ("unsynchronized") timestamp.
/// Complexity: O(1).
pub fn ntp_timestamp_zero() -> NtpTimestamp {
  return NtpTimestamp{ seconds: 0; fraction: 0; };
}

/// True when `t` is the all-zero unsynchronized timestamp. A timestamp with
/// `seconds == 0` but a nonzero fraction is NOT zero.
/// Complexity: O(1).
pub fn ntp_timestamp_is_zero(t: &NtpTimestamp) -> Bool {
  return t.seconds == 0 && t.fraction == 0;
}

/// True when both halves of `t` are in 0..2^32-1.
/// Complexity: O(1).
pub fn ntp_timestamp_is_valid(t: &NtpTimestamp) -> Bool {
  if !_u32_ok(t.seconds) {
    return false;
  }
  if !_u32_ok(t.fraction) {
    return false;
  }
  return true;
}

/// Convert a raw 2^-32 fraction to whole microseconds, truncating toward
/// zero (floor for the non-negative domain). fraction 2^32-1 maps to
/// 999999 us (the exact value is 999999.999...).
/// Returns: Ok(microseconds in 0..999999).
/// Error case: Err("ntp: invalid timestamp") when fraction is outside
/// 0..2^32-1.
/// Complexity: O(1).
pub fn ntp_fraction_to_micros(fraction: Int) -> Result[Int, Str] {
  if !_u32_ok(fraction) {
    return _err_int("ntp: invalid timestamp");
  }
  return _ok_int((fraction * 1000000) / NTP_FRACTION_UNITS);
}

/// Convert a raw 2^-32 fraction to whole nanoseconds, truncating toward
/// zero. fraction 2^32-1 maps to 999999999 ns.
/// Returns: Ok(nanoseconds in 0..999999999).
/// Error case: Err("ntp: invalid timestamp") when fraction is outside
/// 0..2^32-1.
/// Complexity: O(1).
pub fn ntp_fraction_to_nanos(fraction: Int) -> Result[Int, Str] {
  if !_u32_ok(fraction) {
    return _err_int("ntp: invalid timestamp");
  }
  return _ok_int((fraction * 1000000000) / NTP_FRACTION_UNITS);
}

/// Convert whole microseconds in a second to the nearest raw 2^-32
/// fraction. The exact fraction is `micros * 2^32 / 10^6`; halfway cases
/// round up (toward +infinity). No result ever reaches 2^32: micros is
/// capped at 999999.
/// Returns: Ok(fraction in 0..2^32-1).
/// Error case: Err("ntp: micros out of range") when micros is outside
/// 0..999999.
/// Complexity: O(1).
pub fn ntp_micros_to_fraction(micros: Int) -> Result[Int, Str] {
  if micros < 0 || micros > 999999 {
    return _err_int("ntp: micros out of range");
  }
  return _ok_int((micros * NTP_FRACTION_UNITS + 500000) / 1000000);
}

/// Convert whole nanoseconds in a second to the nearest raw 2^-32
/// fraction (`nanos * 2^32 / 10^9`, halfway cases round up).
/// Returns: Ok(fraction in 0..2^32-1).
/// Error case: Err("ntp: nanos out of range") when nanos is outside
/// 0..999999999.
/// Complexity: O(1).
pub fn ntp_nanos_to_fraction(nanos: Int) -> Result[Int, Str] {
  if nanos < 0 || nanos > 999999999 {
    return _err_int("ntp: nanos out of range");
  }
  return _ok_int((nanos * NTP_FRACTION_UNITS + 500000000) / 1000000000);
}

/// Convert a whole 32.32 timestamp to microseconds since the NTP epoch:
/// `seconds * 10^6 + truncate(fraction)`. The all-zero timestamp converts
/// to 0 (it is not an error here; use ntp_timestamp_is_zero to detect the
/// unsynchronized marker).
/// Returns: Ok(microseconds in 0..2^32*10^6-1).
/// Error case: Err("ntp: invalid timestamp") when either half is outside
/// 0..2^32-1.
/// Complexity: O(1).
pub fn ntp_timestamp_to_micros(t: &NtpTimestamp) -> Result[Int, Str] {
  if !ntp_timestamp_is_valid(t) {
    return _err_int("ntp: invalid timestamp");
  }
  return _ok_int(t.seconds * 1000000 + (t.fraction * 1000000) / NTP_FRACTION_UNITS);
}

// --------------------------------------------------
//  Validation
// --------------------------------------------------

/// True when `vn` is an NTP version this codec accepts (3 or 4).
/// Complexity: O(1).
pub fn ntp_version_valid(vn: Int) -> Bool {
  return vn == NTP_VERSION_3 || vn == NTP_VERSION_4;
}

/// True when `mode` is a defined non-reserved NTP mode (1..6).
/// Complexity: O(1).
pub fn ntp_mode_valid(mode: Int) -> Bool {
  return mode >= NTP_MODE_SYMMETRIC_ACTIVE && mode <= NTP_MODE_CONTROL;
}

/// True when every field of `p` is in range: li 0..3, vn 3..4, mode 1..6,
/// stratum 0..255, poll/precision -128..127, root delay -2^31..2^31-1,
/// root dispersion and reference id 0..2^32-1, and all four timestamps
/// valid. Timestamps may be zero (unsynchronized); this predicate only
/// checks ranges.
/// Complexity: O(1).
pub fn ntp_packet_valid(p: &NtpPacket) -> Bool {
  if !_li_ok(p.li) {
    return false;
  }
  if !ntp_version_valid(p.vn) {
    return false;
  }
  if !ntp_mode_valid(p.mode) {
    return false;
  }
  if !_u8_ok(p.stratum) {
    return false;
  }
  if !_i8_ok(p.poll) {
    return false;
  }
  if !_i8_ok(p.precision) {
    return false;
  }
  if !_i32_ok(p.root_delay) {
    return false;
  }
  if !_u32_ok(p.root_dispersion) {
    return false;
  }
  if !_u32_ok(p.reference_id) {
    return false;
  }
  let reference: NtpTimestamp = p.reference;
  if !ntp_timestamp_is_valid(&reference) {
    return false;
  }
  let origin: NtpTimestamp = p.origin;
  if !ntp_timestamp_is_valid(&origin) {
    return false;
  }
  let receive: NtpTimestamp = p.receive;
  if !ntp_timestamp_is_valid(&receive) {
    return false;
  }
  let transmit: NtpTimestamp = p.transmit;
  if !ntp_timestamp_is_valid(&transmit) {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Decode / encode
// --------------------------------------------------

/// Decode the fixed 48-byte NTPv4 packet header from the start of `data`.
///
/// `data` must hold at least NTP_PACKET_SIZE bytes; any trailing bytes
/// (extension fields or a MAC) are ignored, since NTS/authentication
/// extensions are out of scope. `vn` must be 3 or 4 and `mode` must be
/// 1..6; all other fields are read raw, so an unsynchronized packet (all
/// four timestamps zero) decodes successfully and should be checked with
/// ntp_timestamp_is_zero.
///
/// Returns: Ok(packet).
/// Error case: Err("ntp: truncated packet") when data.len() < 48;
/// Err("ntp: unsupported version") when vn is not 3 or 4;
/// Err("ntp: invalid mode") when mode is 0 or 7.
/// Complexity: O(1) (exactly 48 bytes are visited).
pub fn ntp_decode(data: &Vec[UInt8]) -> Result[NtpPacket, Str] {
  if data.len() < NTP_PACKET_SIZE {
    return _err_packet("ntp: truncated packet");
  }
  let b0 = _byte(data, 0);
  let li = b0 / 64;
  let vn = (b0 / 8) % 8;
  let mode = b0 % 8;
  if !ntp_version_valid(vn) {
    return _err_packet("ntp: unsupported version");
  }
  if !ntp_mode_valid(mode) {
    return _err_packet("ntp: invalid mode");
  }
  let reference = NtpTimestamp{ seconds: _read_be(data, 16, 4); fraction: _read_be(data, 20, 4); };
  let origin = NtpTimestamp{ seconds: _read_be(data, 24, 4); fraction: _read_be(data, 28, 4); };
  let receive = NtpTimestamp{ seconds: _read_be(data, 32, 4); fraction: _read_be(data, 36, 4); };
  let transmit = NtpTimestamp{ seconds: _read_be(data, 40, 4); fraction: _read_be(data, 44, 4); };
  let p = NtpPacket{
    li: li;
    vn: vn;
    mode: mode;
    stratum: _byte(data, 1);
    poll: _to_i8(_byte(data, 2));
    precision: _to_i8(_byte(data, 3));
    root_delay: _to_i32(_read_be(data, 4, 4));
    root_dispersion: _read_be(data, 8, 4);
    reference_id: _read_be(data, 12, 4);
    reference: reference;
    origin: origin;
    receive: receive;
    transmit: transmit;
  };
  return _ok_packet(p);
}

/// Encode `p` as exactly NTP_PACKET_SIZE (48) big-endian bytes.
///
/// Every field is range-checked before a single byte is written, in this
/// order: li, vn, mode, stratum, poll, precision, root delay, root
/// dispersion, reference id, then the reference/origin/receive/transmit
/// timestamps. `root_delay` is written as a signed 32-bit 16.16 value
/// (two's complement); `poll` and `precision` as signed bytes.
///
/// Returns: Ok(48 bytes).
/// Error case: the first failing check, with these messages:
/// Err("ntp: invalid leap indicator"), Err("ntp: unsupported version"),
/// Err("ntp: invalid mode"), Err("ntp: invalid stratum"),
/// Err("ntp: invalid poll"), Err("ntp: invalid precision"),
/// Err("ntp: invalid root delay"), Err("ntp: invalid root dispersion"),
/// Err("ntp: invalid reference id") or Err("ntp: invalid timestamp").
/// Complexity: O(1).
pub fn ntp_encode(p: &NtpPacket) -> Result[Vec[UInt8], Str] {
  if !_li_ok(p.li) {
    return _err_bytes("ntp: invalid leap indicator");
  }
  if !ntp_version_valid(p.vn) {
    return _err_bytes("ntp: unsupported version");
  }
  if !ntp_mode_valid(p.mode) {
    return _err_bytes("ntp: invalid mode");
  }
  if !_u8_ok(p.stratum) {
    return _err_bytes("ntp: invalid stratum");
  }
  if !_i8_ok(p.poll) {
    return _err_bytes("ntp: invalid poll");
  }
  if !_i8_ok(p.precision) {
    return _err_bytes("ntp: invalid precision");
  }
  if !_i32_ok(p.root_delay) {
    return _err_bytes("ntp: invalid root delay");
  }
  if !_u32_ok(p.root_dispersion) {
    return _err_bytes("ntp: invalid root dispersion");
  }
  if !_u32_ok(p.reference_id) {
    return _err_bytes("ntp: invalid reference id");
  }
  let reference: NtpTimestamp = p.reference;
  if !ntp_timestamp_is_valid(&reference) {
    return _err_bytes("ntp: invalid timestamp");
  }
  let origin: NtpTimestamp = p.origin;
  if !ntp_timestamp_is_valid(&origin) {
    return _err_bytes("ntp: invalid timestamp");
  }
  let receive: NtpTimestamp = p.receive;
  if !ntp_timestamp_is_valid(&receive) {
    return _err_bytes("ntp: invalid timestamp");
  }
  let transmit: NtpTimestamp = p.transmit;
  if !ntp_timestamp_is_valid(&transmit) {
    return _err_bytes("ntp: invalid timestamp");
  }
  var out = Vec[UInt8].new();
  out.push(_be_byte((p.li * 64) + (p.vn * 8) + p.mode, 0));
  out.push(_be_byte(p.stratum, 0));
  out.push(_be_byte(p.poll, 0));
  out.push(_be_byte(p.precision, 0));
  _push_be(&mut out, p.root_delay, 4);
  _push_be(&mut out, p.root_dispersion, 4);
  _push_be(&mut out, p.reference_id, 4);
  _push_ts(&mut out, &reference);
  _push_ts(&mut out, &origin);
  _push_ts(&mut out, &receive);
  _push_ts(&mut out, &transmit);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Offset / delay
// --------------------------------------------------

// Floor division of `a` by the positive `b` (rounds toward -infinity).
fn _floor_div(a: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  if r < 0 {
    return q - 1;
  }
  return q;
}

// Microseconds since the NTP epoch for a validated timestamp.
fn _timestamp_us(t: &NtpTimestamp) -> Int {
  return t.seconds * 1000000 + (t.fraction * 1000000) / NTP_FRACTION_UNITS;
}

// 0 = all four timestamps usable, 1 = some timestamp out of range,
// 2 = some timestamp is zero. Range checks run first (T1..T4 order), then
// zero checks in the same order.
fn _timestamps_error_code(t1: &NtpTimestamp, t2: &NtpTimestamp, t3: &NtpTimestamp, t4: &NtpTimestamp) -> Int {
  if !ntp_timestamp_is_valid(t1) {
    return 1;
  }
  if !ntp_timestamp_is_valid(t2) {
    return 1;
  }
  if !ntp_timestamp_is_valid(t3) {
    return 1;
  }
  if !ntp_timestamp_is_valid(t4) {
    return 1;
  }
  if ntp_timestamp_is_zero(t1) {
    return 2;
  }
  if ntp_timestamp_is_zero(t2) {
    return 2;
  }
  if ntp_timestamp_is_zero(t3) {
    return 2;
  }
  if ntp_timestamp_is_zero(t4) {
    return 2;
  }
  return 0;
}

/// RFC 5905 clock offset in microseconds:
/// `((T2 - T1) + (T3 - T4)) / 2`, where T1 is the client transmit time
/// (origin), T2 the server receive time, T3 the server transmit time and
/// T4 the client receive time.
///
/// Rounding: each timestamp is first truncated to whole microseconds
/// (fraction * 10^6 / 2^32, floor); the sum is then divided by 2 rounding
/// toward negative infinity. The result is within 1 us of the exact value
/// for µs-granular inputs.
///
/// Returns: Ok(offset in microseconds; positive means the local clock is
/// behind the server).
/// Error case: Err("ntp: invalid timestamp") when any half of T1..T4 is
/// outside 0..2^32-1; Err("ntp: zero timestamp") when any timestamp is the
/// all-zero unsynchronized marker.
/// Complexity: O(1).
pub fn ntp_offset_micros(t1_origin: &NtpTimestamp, t2_receive: &NtpTimestamp, t3_transmit: &NtpTimestamp, t4_dest: &NtpTimestamp) -> Result[Int, Str] {
  let code = _timestamps_error_code(t1_origin, t2_receive, t3_transmit, t4_dest);
  if code == 1 {
    return _err_int("ntp: invalid timestamp");
  }
  if code == 2 {
    return _err_int("ntp: zero timestamp");
  }
  let t1 = _timestamp_us(t1_origin);
  let t2 = _timestamp_us(t2_receive);
  let t3 = _timestamp_us(t3_transmit);
  let t4 = _timestamp_us(t4_dest);
  let sum = (t2 - t1) + (t3 - t4);
  return _ok_int(_floor_div(sum, 2));
}

/// RFC 5905 round-trip delay in microseconds:
/// `(T4 - T1) - (T3 - T2)`, with the same T1..T4 meaning as
/// ntp_offset_micros.
///
/// Rounding: each timestamp is first truncated to whole microseconds
/// (fraction * 10^6 / 2^32, floor); the subtraction is then exact for the
/// truncated values.
///
/// Returns: Ok(delay in microseconds; never negative for a consistent
/// exchange, but a nonsensical ordering yields a negative value rather
/// than an error).
/// Error case: Err("ntp: invalid timestamp") when any half of T1..T4 is
/// outside 0..2^32-1; Err("ntp: zero timestamp") when any timestamp is the
/// all-zero unsynchronized marker.
/// Complexity: O(1).
pub fn ntp_delay_micros(t1_origin: &NtpTimestamp, t2_receive: &NtpTimestamp, t3_transmit: &NtpTimestamp, t4_dest: &NtpTimestamp) -> Result[Int, Str] {
  let code = _timestamps_error_code(t1_origin, t2_receive, t3_transmit, t4_dest);
  if code == 1 {
    return _err_int("ntp: invalid timestamp");
  }
  if code == 2 {
    return _err_int("ntp: zero timestamp");
  }
  let t1 = _timestamp_us(t1_origin);
  let t2 = _timestamp_us(t2_receive);
  let t3 = _timestamp_us(t3_transmit);
  let t4 = _timestamp_us(t4_dest);
  return _ok_int((t4 - t1) - (t3 - t2));
}
