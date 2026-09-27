// XIOM -- xiom.aviation: Mode S / ADS-B extended-squitter frame codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: bit-oriented decoding of Mode S downlink frames (56-bit / 7-byte
// short frames and 112-bit / 14-byte long frames) and of the 56-bit ME
// extended-squitter payload carried by DF17/DF18. No RF/PHY handling, no
// serial line handling, no demodulation: bytes in, values out.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside larger functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`.
//   * bit extraction is pure arithmetic (`q / 2^k % 2`); `&` masks are not
//     used on data whose high bit may be set.
//   * free functions only, scalar struct fields and parallel Vec[Int]
//     pools; no Vec[Struct], no Vec[Float64], no generic callbacks.
//   * Str values read from a Vec are never compared with `==`; all string
//     decisions in the tests go through xiom.string.compare.
// See SPEC.md for the bit-level layouts, tables and error catalog.

module xiom.aviation

use xiom.string;

// --------------------------------------------------
//  Parsed frame
// --------------------------------------------------

/// A parsed Mode S downlink frame. `frame_bytes` is 7 (short) or 14 (long)
/// and `bits` is 56 or 112. `df` is the 5-bit downlink format (bits 1-5,
/// MSB-first). `ca` is the 3-bit field that follows DF (capability for
/// DF11/17/18, flight status for DF4/5/20/21, vertical status for DF0/16).
/// `icao` is the 24-bit address field (bits 9-32). `payload` is the 56-bit
/// ME/MB/MV field (bits 33-88) for long frames, or -1 for short frames.
/// `parity` is the last 24 bits exactly as transmitted (AP/PI for DF17/18
/// and DF4/5, DP for DF11); parity verification is caller-side because DF11
/// overlays the interrogator code. `tc` is the ME type code (payload bits
/// 1-5) for DF17/DF18, else -1. `consumed` is the number of input bytes the
/// frame occupies (equal to `frame_bytes`). Fields are implementation
/// details; callers should go through the free functions below.
pub type AviationFrame = {
  frame_bytes: Int;
  bits: Int;
  df: Int;
  ca: Int;
  icao: Int;
  payload: Int;
  parity: Int;
  tc: Int;
  consumed: Int;
}

// --------------------------------------------------
//  Bit-level helpers
// --------------------------------------------------

// 2^k for the bit widths used by Mode S frames (k <= 56).
fn _pow2(k: Int) -> Int {
  var v: Int = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
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

// Ok(v) for Result[AviationFrame, Str].
fn _ok_frame(v: AviationFrame) -> Result[AviationFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[AviationFrame, Str].
fn _err_frame(m: Str) -> Result[AviationFrame, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Bit reader (MSB-first, absolute bit offsets)
// --------------------------------------------------

// Bit `bit_off` of `data`, counting from the most significant bit of byte 0.
// The caller guarantees the byte index is in bounds.
fn _bit(data: &Vec[UInt8], bit_off: Int) -> Int {
  let byte_idx = bit_off / 8;
  let bit_idx = bit_off % 8;
  let b: Int = (data[byte_idx] as Int) & 0xFF;
  var q = b;
  var i = 0;
  while i < 7 - bit_idx {
    q = q / 2;
    i = i + 1;
  }
  return q % 2;
}

/// Bit at absolute MSB-first offset `bit_off` (bit 0 is the most significant
/// bit of `data[0]`). Returns 0 or 1.
/// Err("aviation: bit offset out of range") when `bit_off` is negative or
/// beyond the last bit of `data`.
/// Complexity: O(1).
pub fn aviation_bit(data: &Vec[UInt8], bit_off: Int) -> Result[Int, Str] {
  if bit_off < 0 {
    return _err_int("aviation: bit offset out of range");
  }
  if bit_off >= data.len() * 8 {
    return _err_int("aviation: bit offset out of range");
  }
  let v: Int = _bit(data, bit_off);
  return _ok_int(v);
}

/// Unsigned integer made of `len` bits starting at MSB-first offset `start`
/// (bit `start` is the most significant bit of the result). `len` may be
/// 0..56; a zero-length read returns 0.
/// Err("aviation: bit width out of range") when `len` is negative or above
/// 56. Err("aviation: bit offset out of range") when the span does not fit
/// in `data`.
/// Complexity: O(len).
pub fn aviation_bits(data: &Vec[UInt8], start: Int, len: Int) -> Result[Int, Str] {
  if len < 0 {
    return _err_int("aviation: bit width out of range");
  }
  if len > 56 {
    return _err_int("aviation: bit width out of range");
  }
  if start < 0 {
    return _err_int("aviation: bit offset out of range");
  }
  if start + len > data.len() * 8 {
    return _err_int("aviation: bit offset out of range");
  }
  var acc: Int = 0;
  var i = 0;
  while i < len {
    acc = acc * 2 + _bit(data, start + i);
    i = i + 1;
  }
  return _ok_int(acc);
}

// --------------------------------------------------
//  Downlink format table
// --------------------------------------------------

/// Encoded frame length in bytes for downlink format `df`: 7 for the short
/// formats 0, 4, 5 and 11; 14 for the long formats 16, 17, 18, 19, 20, 21
/// and 24. Every other 5-bit value (1-3, 6-10, 12-15, 22-23, 25-31) is
/// reserved and returns -1.
/// Complexity: O(1).
pub fn aviation_df_length(df: Int) -> Int {
  if df == 0 || df == 4 || df == 5 || df == 11 {
    return 7;
  }
  if df == 16 || df == 17 || df == 18 || df == 19 {
    return 14;
  }
  if df == 20 || df == 21 || df == 24 {
    return 14;
  }
  return -1;
}

/// Short human-readable name of downlink format `df`. Reserved values return
/// "DF? reserved" and values outside 0..31 return "DF? out of range".
/// Complexity: O(1).
pub fn aviation_df_name(df: Int) -> Str {
  if df < 0 || df > 31 {
    return "DF? out of range";
  }
  if df == 0 {
    return "DF0 short air-air surveillance (ACAS)";
  }
  if df == 4 {
    return "DF4 surveillance altitude reply";
  }
  if df == 5 {
    return "DF5 surveillance identity reply";
  }
  if df == 11 {
    return "DF11 all-call reply";
  }
  if df == 16 {
    return "DF16 long air-air surveillance (ACAS)";
  }
  if df == 17 {
    return "DF17 extended squitter (ADS-B)";
  }
  if df == 18 {
    return "DF18 extended squitter (TIS-B / non-transponder)";
  }
  if df == 19 {
    return "DF19 military extended squitter";
  }
  if df == 20 {
    return "DF20 Comm-B altitude reply";
  }
  if df == 21 {
    return "DF21 Comm-B identity reply";
  }
  if df == 24 {
    return "DF24 Comm-D extended length message";
  }
  return "DF? reserved";
}

// --------------------------------------------------
//  Frame intake
// --------------------------------------------------

/// Parse one Mode S downlink frame from the start of `data`.
///
/// The frame length is derived from the 5-bit DF field (bits 1-5): short
/// formats occupy 7 bytes, long formats 14 bytes. `data` may hold more bytes
/// than the frame (a stream); only the frame bytes are consumed and
/// `consumed` reports how many. Layouts (bit 1 is the MSB of byte 0):
///
///   * bits 1-5   DF   (downlink format)
///   * bits 6-8   CA / FS / CF (format-dependent, returned raw)
///   * bits 9-32  ICAO 24-bit address (AA / other, returned raw)
///   * bits 33-88 ME / MB / MV 56-bit payload (long formats only)
///   * last 24    parity / interrogator overlay / address parity, raw
///
/// Errors (all stable):
///   * `aviation: truncated frame` -- fewer than 7 bytes, or fewer bytes
///     than the length the DF requires;
///   * `aviation: unknown df` -- the 5-bit DF is reserved.
/// Complexity: O(frame bits).
pub fn aviation_parse_frame(data: &Vec[UInt8]) -> Result[AviationFrame, Str] {
  if data.len() < 7 {
    return _err_frame("aviation: truncated frame");
  }
  let df: Int = _bit(data, 0) * 16 + _bit(data, 1) * 8 + _bit(data, 2) * 4 + _bit(data, 3) * 2 + _bit(data, 4);
  let need: Int = aviation_df_length(df);
  if need < 0 {
    return _err_frame("aviation: unknown df");
  }
  if data.len() < need {
    return _err_frame("aviation: truncated frame");
  }
  let ca: Int = _bit(data, 5) * 4 + _bit(data, 6) * 2 + _bit(data, 7);
  var icao: Int = 0;
  var i = 8;
  while i < 32 {
    icao = icao * 2 + _bit(data, i);
    i = i + 1;
  }
  var payload: Int = -1;
  var tc: Int = -1;
  if need == 14 {
    payload = 0;
    i = 32;
    while i < 88 {
      payload = payload * 2 + _bit(data, i);
      i = i + 1;
    }
    if df == 17 || df == 18 {
      tc = payload / _pow2(51);
    }
  }
  var parity: Int = 0;
  i = (need - 3) * 8;
  while i < need * 8 {
    parity = parity * 2 + _bit(data, i);
    i = i + 1;
  }
  let f = AviationFrame{
    frame_bytes: need;
    bits: need * 8;
    df: df;
    ca: ca;
    icao: icao;
    payload: payload;
    parity: parity;
    tc: tc;
    consumed: need;
  };
  return _ok_frame(f);
}

/// Encoded frame length in bytes of a parsed frame (7 or 14).
/// Complexity: O(1).
pub fn aviation_frame_bytes(f: &AviationFrame) -> Int {
  return f.frame_bytes;
}

/// Encoded frame length in bits of a parsed frame (56 or 112).
/// Complexity: O(1).
pub fn aviation_frame_bits(f: &AviationFrame) -> Int {
  return f.bits;
}

/// Downlink format (5-bit DF, 0..31) of a parsed frame.
/// Complexity: O(1).
pub fn aviation_frame_df(f: &AviationFrame) -> Int {
  return f.df;
}

/// The 3-bit field after DF: capability (DF11/17/18), flight status
/// (DF4/5/20/21) or vertical status (DF0/16), returned raw.
/// Complexity: O(1).
pub fn aviation_frame_ca(f: &AviationFrame) -> Int {
  return f.ca;
}

/// 24-bit ICAO address field (bits 9-32) as transmitted, returned raw.
/// Complexity: O(1).
pub fn aviation_frame_icao(f: &AviationFrame) -> Int {
  return f.icao;
}

/// 56-bit ME/MB/MV payload (bits 33-88) of a long frame, or -1 for a short
/// frame (DF0/4/5/11).
/// Complexity: O(1).
pub fn aviation_frame_payload(f: &AviationFrame) -> Int {
  return f.payload;
}

/// Last 24 bits of the frame exactly as transmitted (AP/PI/DP). No parity
/// verification is attempted; DF11 overlays the interrogator code, so
/// verification is caller-side.
/// Complexity: O(1).
pub fn aviation_frame_parity(f: &AviationFrame) -> Int {
  return f.parity;
}

/// ME type code (payload bits 1-5) for DF17/DF18 frames, else -1. The raw
/// value is 0..31; see aviation_tc_name for the meaning of each code.
/// Complexity: O(1).
pub fn aviation_frame_tc(f: &AviationFrame) -> Int {
  return f.tc;
}

/// Number of input bytes consumed by the frame (equal to the frame length).
/// Complexity: O(1).
pub fn aviation_frame_consumed(f: &AviationFrame) -> Int {
  return f.consumed;
}

// --------------------------------------------------
//  Shared ME helpers
// --------------------------------------------------

// True when `f` is a 112-bit extended-squitter frame (DF17/DF18) carrying a
// 56-bit ME payload. Every ME decoder requires this.
fn _is_squitter(f: &AviationFrame) -> Bool {
  if f.payload < 0 {
    return false;
  }
  if f.df != 17 && f.df != 18 {
    return false;
  }
  return true;
}

// ME bit field [first, first+len) as an Int, 1-based and MSB-first inside
// the 56-bit ME payload. The caller guarantees the span is inside ME
// (1 <= first, first+len <= 57).
fn _me_bits(f: &AviationFrame, first: Int, len: Int) -> Int {
  if len == 0 {
    return 0;
  }
  let shift = 57 - first - len;
  return (f.payload / _pow2(shift)) % _pow2(len);
}

// --------------------------------------------------
//  Type code table
// --------------------------------------------------

/// Human-readable name of an extended-squitter type code `tc` (ME bits 1-5,
/// 0..31). Values outside 0..31 return "TC? out of range".
/// Complexity: O(1).
pub fn aviation_tc_name(tc: Int) -> Str {
  if tc < 0 || tc > 31 {
    return "TC? out of range";
  }
  if tc == 0 {
    return "TC0 no position information";
  }
  if tc <= 4 {
    return "TC1-4 aircraft identification and category";
  }
  if tc <= 8 {
    return "TC5-8 surface position";
  }
  if tc <= 18 {
    return "TC9-18 airborne position (barometric altitude)";
  }
  if tc == 19 {
    return "TC19 airborne velocity";
  }
  if tc <= 22 {
    return "TC20-22 airborne position (GNSS height)";
  }
  if tc <= 27 {
    return "TC23-27 reserved";
  }
  if tc == 28 {
    return "TC28 aircraft status (emergency / TCAS RA)";
  }
  if tc == 29 {
    return "TC29 target state and status";
  }
  if tc == 30 {
    return "TC30 reserved";
  }
  return "TC31 aircraft operational status";
}

// --------------------------------------------------
//  Aircraft identification (TC 1-4)
// --------------------------------------------------
//
// ME bits 1-5   TC (1-4)
// ME bits 6-8   category (CA)
// ME bits 9-56  eight 6-bit characters
//
// The 6-bit charset is 1-26 = A..Z, 32 = space, 48-57 = 0..9; code 0 and
// every other code decode to '#'. The callsign keeps all eight characters.

/// Character of the ADS-B identification charset for 6-bit `code`:
/// 1-26 -> A..Z, 32 -> space, 48-57 -> 0..9, anything else (including 0)
/// -> "#".
/// Complexity: O(1).
pub fn aviation_callsign_char(code: Int) -> Str {
  if code >= 1 && code <= 26 {
    return string.str_slice("ABCDEFGHIJKLMNOPQRSTUVWXYZ", code - 1, code);
  }
  if code == 32 {
    return " ";
  }
  if code >= 48 && code <= 57 {
    return string.str_slice("0123456789", code - 48, code - 47);
  }
  return "#";
}

/// Decoded aircraft identification message (TC 1-4). `tc` is the type code,
/// `category` the 3-bit CA field (ME bits 6-8) and `callsign` the eight
/// characters decoded from ME bits 9-56.
pub type AviationIdent = {
  tc: Int;
  category: Int;
  callsign: Str;
}

// Ok(v) for Result[AviationIdent, Str].
fn _ok_ident(v: AviationIdent) -> Result[AviationIdent, Str] {
  return Ok(v);
}

// Err(m) for Result[AviationIdent, Str].
fn _err_ident(m: Str) -> Result[AviationIdent, Str] {
  return Err(m);
}

/// Decode a DF17/DF18 identification message (TC 1-4).
/// Errors (all stable):
///   * `aviation: not an extended squitter frame` -- short frame or DF not
///     17/18;
///   * `aviation: not an identification message` -- TC outside 1..4.
/// Complexity: O(1).
pub fn aviation_ident_decode(f: &AviationFrame) -> Result[AviationIdent, Str] {
  if !_is_squitter(f) {
    return _err_ident("aviation: not an extended squitter frame");
  }
  let tc = _me_bits(f, 1, 5);
  if tc < 1 || tc > 4 {
    return _err_ident("aviation: not an identification message");
  }
  let category = _me_bits(f, 6, 3);
  var callsign = "";
  var k = 0;
  while k < 8 {
    let code = _me_bits(f, 9 + 6 * k, 6);
    callsign = callsign + aviation_callsign_char(code);
    k = k + 1;
  }
  let id = AviationIdent{ tc: tc; category: category; callsign: callsign; };
  return _ok_ident(id);
}

/// Type code of a decoded identification message (1-4).
/// Complexity: O(1).
pub fn aviation_ident_tc(id: &AviationIdent) -> Int {
  return id.tc;
}

/// Category (ME bits 6-8) of a decoded identification message.
/// Complexity: O(1).
pub fn aviation_ident_category(id: &AviationIdent) -> Int {
  return id.category;
}

/// The eight callsign characters exactly as decoded (padding spaces and
/// invalid code '#' are preserved).
/// Complexity: O(1).
pub fn aviation_ident_callsign(id: &AviationIdent) -> Str {
  return id.callsign;
}

/// The callsign with trailing spaces and trailing '#' removed.
/// Complexity: O(callsign length).
pub fn aviation_ident_callsign_trim(id: &AviationIdent) -> Str {
  let s = id.callsign;
  var end = s.len();
  var done = false;
  while end > 0 && !done {
    let b: Int = (string.byte_at(s, end - 1) as Int) & 0xFF;
    if b == 32 || b == 35 {
      end = end - 1;
    } else {
      done = true;
    }
  }
  return string.str_slice(s, 0, end);
}

// --------------------------------------------------
//  Altitude decoders
// --------------------------------------------------
//
// The 12-bit ADS-B altitude field (airborne position, ME bits 9-20) and the
// 13-bit Mode S AC field (DF4/DF20, bits 20-32) share the same layout:
//   MSB ... LSB: C1 A1 C2 A2 C4 A4 [M] B1 Q B2 D2 B4 D4
// with M only present in AC13. Q=1 selects the binary 25 ft encoding
// implemented here. Q=0 selects a Gillham/Gray-coded altitude (the C/A/B/D
// bits are a reflected-binary code); that subset is documented but NOT
// decoded, see SPEC.md.

/// Q bit of a 12-bit ADS-B altitude field (ME bit 20-4 = field bit 4).
/// 1 = 25 ft binary encoding; 0 = Gillham code (unsupported).
/// Complexity: O(1).
pub fn aviation_ac12_qbit(ac12: Int) -> Int {
  return (ac12 / 16) % 2;
}

/// Decode a 12-bit ADS-B altitude field to whole feet.
/// Q=1: N is the 11 bits with Q removed (bits above Q, then bits below Q);
/// the altitude is `N * 25 - 1000` feet, so the field covers -1000..50175.
/// Err("aviation: altitude field out of range") when `ac12` is outside
/// 0..4095. Err("aviation: gillham altitude code unsupported") when Q=0.
/// Complexity: O(1).
pub fn aviation_ac12_altitude_ft(ac12: Int) -> Result[Int, Str] {
  if ac12 < 0 || ac12 > 4095 {
    return _err_int("aviation: altitude field out of range");
  }
  if aviation_ac12_qbit(ac12) == 0 {
    return _err_int("aviation: gillham altitude code unsupported");
  }
  let n = (ac12 / 32) * 16 + ac12 % 16;
  return _ok_int(n * 25 - 1000);
}

/// M bit of a 13-bit Mode S AC altitude field: 1 = metric encoding.
/// Complexity: O(1).
pub fn aviation_ac13_metric_flag(ac13: Int) -> Int {
  return (ac13 / 64) % 2;
}

/// Q bit of a 13-bit Mode S AC altitude field: 1 = 25 ft binary encoding.
/// Complexity: O(1).
pub fn aviation_ac13_qbit(ac13: Int) -> Int {
  return (ac13 / 16) % 2;
}

/// Decode a 13-bit Mode S AC altitude field (DF4/DF20 position, bits 20-32)
/// to whole feet.
/// M=0, Q=1: N is the 11 bits with M and Q removed; the altitude is
/// `N * 25 - 1000` feet.
/// Errors (all stable):
///   * `aviation: altitude field out of range` -- `ac13` outside 0..8191;
///   * `aviation: metric altitude unsupported` -- M=1 (metric encoding is
///     documented but not decoded);
///   * `aviation: gillham altitude code unsupported` -- M=0, Q=0.
/// Complexity: O(1).
pub fn aviation_ac13_altitude_ft(ac13: Int) -> Result[Int, Str] {
  if ac13 < 0 || ac13 > 8191 {
    return _err_int("aviation: altitude field out of range");
  }
  if aviation_ac13_metric_flag(ac13) == 1 {
    return _err_int("aviation: metric altitude unsupported");
  }
  if aviation_ac13_qbit(ac13) == 0 {
    return _err_int("aviation: gillham altitude code unsupported");
  }
  let n = (ac13 / 128) * 32 + ((ac13 / 32) % 2) * 16 + ac13 % 16;
  return _ok_int(n * 25 - 1000);
}

/// GNSS height above ellipsoid from the 12-bit altitude field of TC 20-22,
/// in whole metres (the field is the height in metres, 0..4095). No scaling
/// and no "no data" special case: 0 is returned as 0, caller-side.
/// Complexity: O(1).
pub fn aviation_gnss_altitude_m(raw12: Int) -> Int {
  return raw12;
}

/// GNSS height above ellipsoid from the TC 20-22 field, converted to whole
/// feet with a fixed 3.28084 m/ft factor (rounded half away from zero).
/// Complexity: O(1).
pub fn aviation_gnss_altitude_ft(raw12: Int) -> Int {
  return (raw12 * 328084 + 50000) / 100000;
}

// --------------------------------------------------
//  Aircraft status: emergency (TC 28)
// --------------------------------------------------
//
// ME bits 1-5   TC = 28
// ME bits 6-8   subtype (1 = emergency/priority, 2 = TCAS RA)
// ME bits 9-11  emergency state (subtype 1 only)

/// Decoded aircraft status message (TC 28). `subtype` is ME bits 6-8;
/// `state` is ME bits 9-11 for subtype 1 (emergency/priority status) and
/// -1 for every other subtype.
pub type AviationEmergency = {
  tc: Int;
  subtype: Int;
  state: Int;
}

// Ok(v) for Result[AviationEmergency, Str].
fn _ok_emergency(v: AviationEmergency) -> Result[AviationEmergency, Str] {
  return Ok(v);
}

// Err(m) for Result[AviationEmergency, Str].
fn _err_emergency(m: Str) -> Result[AviationEmergency, Str] {
  return Err(m);
}

/// Name of the 3-bit emergency state (ME bits 9-11 of a TC28 subtype-1
/// message). States 6 and 7 are reserved; values outside 0..7 return
/// "unknown".
/// Complexity: O(1).
pub fn aviation_emergency_state_name(state: Int) -> Str {
  if state == 0 {
    return "no emergency";
  }
  if state == 1 {
    return "general emergency";
  }
  if state == 2 {
    return "lifeguard / medical emergency";
  }
  if state == 3 {
    return "minimum fuel";
  }
  if state == 4 {
    return "no communications";
  }
  if state == 5 {
    return "unlawful interference";
  }
  if state == 6 {
    return "reserved 6";
  }
  if state == 7 {
    return "reserved 7";
  }
  return "unknown";
}

/// Decode a DF17/DF18 aircraft status message (TC 28).
/// Errors (all stable):
///   * `aviation: not an extended squitter frame` -- short frame or DF not
///     17/18;
///   * `aviation: not an aircraft status message` -- TC not 28.
/// Complexity: O(1).
pub fn aviation_emergency_decode(f: &AviationFrame) -> Result[AviationEmergency, Str] {
  if !_is_squitter(f) {
    return _err_emergency("aviation: not an extended squitter frame");
  }
  if _me_bits(f, 1, 5) != 28 {
    return _err_emergency("aviation: not an aircraft status message");
  }
  let st = _me_bits(f, 6, 3);
  var state = -1;
  if st == 1 {
    state = _me_bits(f, 9, 3);
  }
  let e = AviationEmergency{ tc: 28; subtype: st; state: state; };
  return _ok_emergency(e);
}

/// Subtype (ME bits 6-8) of a decoded aircraft status message.
/// Complexity: O(1).
pub fn aviation_emergency_subtype(e: &AviationEmergency) -> Int {
  return e.subtype;
}

/// Emergency state (ME bits 9-11) of a decoded TC28 subtype-1 message, or
/// -1 when the subtype carries no emergency state.
/// Complexity: O(1).
pub fn aviation_emergency_state(e: &AviationEmergency) -> Int {
  return e.state;
}

// --------------------------------------------------
//  Surface position (TC 5-8)
// --------------------------------------------------
//
// ME bits 1-5   TC (5-8)
// ME bits 6-12  MOV (7-bit movement code)
// ME bit  13    track status (1 = valid)
// ME bits 14-20 TRK (7-bit ground track)
// ME bit  21    T time flag (0 = UTC synchronised)
// ME bit  22    F CPR odd/even frame flag
// ME bits 23-39 CPR latitude (17 bits)
// ME bits 40-56 CPR longitude (17 bits)

/// Decoded surface position message (TC 5-8). `speed_k8` is the movement
/// speed in eighths of a knot (-1 = no information, -2 = reserved code);
/// `track_deg100` is the ground track in hundredths of a degree (rounded)
/// and `track_status` says whether the track is valid. `time_flag` is 0
/// when the position is UTC-synchronised. `cpr_lat`/`cpr_lon` are the raw
/// 17-bit CPR fields to feed to the aviation_cpr_* helpers.
pub type AviationSurface = {
  tc: Int;
  movement: Int;
  speed_k8: Int;
  track_status: Int;
  track_raw: Int;
  track_deg100: Int;
  time_flag: Int;
  odd: Int;
  cpr_lat: Int;
  cpr_lon: Int;
}

// Ok(v) for Result[AviationSurface, Str].
fn _ok_surface(v: AviationSurface) -> Result[AviationSurface, Str] {
  return Ok(v);
}

// Err(m) for Result[AviationSurface, Str].
fn _err_surface(m: Str) -> Result[AviationSurface, Str] {
  return Err(m);
}

/// Movement code (7 bits) to speed in eighths of a knot.
/// 0 = no information (-1); 1 = stopped (0); 2-8 = 0.125 kt steps; 9-12 =
/// 1.0 kt + 0.25 kt steps; 13-38 = 2 kt + 0.5 kt steps; 39-93 = 15 kt +
/// 1 kt steps; 94-108 = 70 kt + 2 kt steps; 109-123 = 100 kt + 5 kt steps;
/// 124 = 175 kt; 125-127 = reserved (-2).
/// Complexity: O(1).
pub fn aviation_movement_k8(mov: Int) -> Int {
  if mov < 0 || mov > 127 {
    return -2;
  }
  if mov == 0 {
    return -1;
  }
  if mov == 1 {
    return 0;
  }
  if mov <= 8 {
    return mov - 1;
  }
  if mov <= 12 {
    return (mov - 9) * 2 + 8;
  }
  if mov <= 38 {
    return (mov - 13) * 4 + 16;
  }
  if mov <= 93 {
    return (mov - 39) * 8 + 120;
  }
  if mov <= 108 {
    return (mov - 94) * 16 + 560;
  }
  if mov <= 123 {
    return (mov - 109) * 40 + 800;
  }
  if mov == 124 {
    return 1400;
  }
  return -2;
}

/// Ground track (7-bit TRK) in hundredths of a degree, rounded to nearest.
/// The exact scale is TRK * 360 / 128 degrees.
/// Complexity: O(1).
pub fn aviation_track_deg100(trk: Int) -> Int {
  return (trk * 28125 + 50) / 100;
}

/// Decode a DF17/DF18 surface position message (TC 5-8).
/// Errors (all stable):
///   * `aviation: not an extended squitter frame` -- short frame or DF not
///     17/18;
///   * `aviation: not a surface position message` -- TC outside 5..8.
/// Complexity: O(1).
pub fn aviation_surface_decode(f: &AviationFrame) -> Result[AviationSurface, Str] {
  if !_is_squitter(f) {
    return _err_surface("aviation: not an extended squitter frame");
  }
  let tc = _me_bits(f, 1, 5);
  if tc < 5 || tc > 8 {
    return _err_surface("aviation: not a surface position message");
  }
  let mov = _me_bits(f, 6, 7);
  let s = AviationSurface{
    tc: tc;
    movement: mov;
    speed_k8: aviation_movement_k8(mov);
    track_status: _me_bits(f, 13, 1);
    track_raw: _me_bits(f, 14, 7);
    track_deg100: aviation_track_deg100(_me_bits(f, 14, 7));
    time_flag: _me_bits(f, 21, 1);
    odd: _me_bits(f, 22, 1);
    cpr_lat: _me_bits(f, 23, 17);
    cpr_lon: _me_bits(f, 40, 17);
  };
  return _ok_surface(s);
}

/// Type code of a decoded surface position message (5-8).
/// Complexity: O(1).
pub fn aviation_surface_tc(s: &AviationSurface) -> Int {
  return s.tc;
}

/// Raw 7-bit movement code of a decoded surface position message.
/// Complexity: O(1).
pub fn aviation_surface_movement(s: &AviationSurface) -> Int {
  return s.movement;
}

/// Movement speed in eighths of a knot (-1 no information, -2 reserved).
/// Complexity: O(1).
pub fn aviation_surface_speed_k8(s: &AviationSurface) -> Int {
  return s.speed_k8;
}

/// Track status bit (1 = ground track valid).
/// Complexity: O(1).
pub fn aviation_surface_track_status(s: &AviationSurface) -> Int {
  return s.track_status;
}

/// Raw 7-bit ground track code.
/// Complexity: O(1).
pub fn aviation_surface_track_raw(s: &AviationSurface) -> Int {
  return s.track_raw;
}

/// Ground track in hundredths of a degree (rounded).
/// Complexity: O(1).
pub fn aviation_surface_track_deg100(s: &AviationSurface) -> Int {
  return s.track_deg100;
}

/// Time flag (0 = UTC synchronised).
/// Complexity: O(1).
pub fn aviation_surface_time_flag(s: &AviationSurface) -> Int {
  return s.time_flag;
}

/// CPR odd/even frame flag.
/// Complexity: O(1).
pub fn aviation_surface_odd(s: &AviationSurface) -> Int {
  return s.odd;
}

/// Raw 17-bit CPR latitude field.
/// Complexity: O(1).
pub fn aviation_surface_cpr_lat(s: &AviationSurface) -> Int {
  return s.cpr_lat;
}

/// Raw 17-bit CPR longitude field.
/// Complexity: O(1).
pub fn aviation_surface_cpr_lon(s: &AviationSurface) -> Int {
  return s.cpr_lon;
}

// --------------------------------------------------
//  Airborne position (TC 9-18 barometric, TC 20-22 GNSS)
// --------------------------------------------------
//
// ME bits 1-5   TC
// ME bits 6-7   SS surveillance status (TC 9-18; reserved in TC 20-22)
// ME bit  8     SAF single antenna flag (NIC supplement B)
// ME bits 9-20  altitude (12-bit AC: barometric for TC 9-18, GNSS height
//               above ellipsoid in metres for TC 20-22)
// ME bit  21    T time flag
// ME bit  22    F CPR odd/even frame flag
// ME bits 23-39 CPR latitude (17 bits)
// ME bits 40-56 CPR longitude (17 bits)

/// Decoded airborne position message (TC 9-18 and TC 20-22). `alt_ft` is
/// the decoded barometric altitude in feet for TC 9-18 (-1 when the field
/// is not a Q=1 code, or for TC 20-22). `gnss_m` is the GNSS height above
/// ellipsoid in metres for TC 20-22 (-1 otherwise). `cpr_lat`/`cpr_lon` are
/// the raw 17-bit CPR fields to feed to the aviation_cpr_* helpers.
pub type AviationPosition = {
  tc: Int;
  ss: Int;
  saf: Int;
  alt_raw: Int;
  alt_ft: Int;
  gnss_m: Int;
  time_flag: Int;
  odd: Int;
  cpr_lat: Int;
  cpr_lon: Int;
}

// Ok(v) for Result[AviationPosition, Str].
fn _ok_position(v: AviationPosition) -> Result[AviationPosition, Str] {
  return Ok(v);
}

// Err(m) for Result[AviationPosition, Str].
fn _err_position(m: Str) -> Result[AviationPosition, Str] {
  return Err(m);
}

/// Decode a DF17/DF18 airborne position message (TC 9-18 barometric or
/// TC 20-22 GNSS height).
/// Errors (all stable):
///   * `aviation: not an extended squitter frame` -- short frame or DF not
///     17/18;
///   * `aviation: not an airborne position message` -- TC outside 9..18 and
///     20..22.
/// Complexity: O(1).
pub fn aviation_position_decode(f: &AviationFrame) -> Result[AviationPosition, Str] {
  if !_is_squitter(f) {
    return _err_position("aviation: not an extended squitter frame");
  }
  let tc = _me_bits(f, 1, 5);
  if tc < 9 || tc == 19 {
    return _err_position("aviation: not an airborne position message");
  }
  if tc > 22 {
    return _err_position("aviation: not an airborne position message");
  }
  let alt_raw = _me_bits(f, 9, 12);
  var alt_ft = -1;
  var gnss_m = -1;
  if tc <= 18 {
    let a = aviation_ac12_altitude_ft(alt_raw);
    if a.is_ok {
      alt_ft = a.value;
    }
  } else {
    gnss_m = aviation_gnss_altitude_m(alt_raw);
  }
  let p = AviationPosition{
    tc: tc;
    ss: _me_bits(f, 6, 2);
    saf: _me_bits(f, 8, 1);
    alt_raw: alt_raw;
    alt_ft: alt_ft;
    gnss_m: gnss_m;
    time_flag: _me_bits(f, 21, 1);
    odd: _me_bits(f, 22, 1);
    cpr_lat: _me_bits(f, 23, 17);
    cpr_lon: _me_bits(f, 40, 17);
  };
  return _ok_position(p);
}

/// Type code of a decoded airborne position message.
/// Complexity: O(1).
pub fn aviation_position_tc(p: &AviationPosition) -> Int {
  return p.tc;
}

/// Surveillance status (ME bits 6-7), returned raw.
/// Complexity: O(1).
pub fn aviation_position_ss(p: &AviationPosition) -> Int {
  return p.ss;
}

/// SAF / NIC supplement B bit (ME bit 8), returned raw.
/// Complexity: O(1).
pub fn aviation_position_saf(p: &AviationPosition) -> Int {
  return p.saf;
}

/// Raw 12-bit altitude field.
/// Complexity: O(1).
pub fn aviation_position_alt_raw(p: &AviationPosition) -> Int {
  return p.alt_raw;
}

/// Barometric altitude in feet for TC 9-18 (-1 when the AC12 field is not
/// a Q=1 code), or -1 for TC 20-22.
/// Complexity: O(1).
pub fn aviation_position_alt_ft(p: &AviationPosition) -> Int {
  return p.alt_ft;
}

/// GNSS height above ellipsoid in metres for TC 20-22, or -1 otherwise.
/// Complexity: O(1).
pub fn aviation_position_gnss_m(p: &AviationPosition) -> Int {
  return p.gnss_m;
}

/// Time flag (0 = UTC synchronised).
/// Complexity: O(1).
pub fn aviation_position_time_flag(p: &AviationPosition) -> Int {
  return p.time_flag;
}

/// CPR odd/even frame flag.
/// Complexity: O(1).
pub fn aviation_position_odd(p: &AviationPosition) -> Int {
  return p.odd;
}

/// Raw 17-bit CPR latitude field.
/// Complexity: O(1).
pub fn aviation_position_cpr_lat(p: &AviationPosition) -> Int {
  return p.cpr_lat;
}

/// Raw 17-bit CPR longitude field.
/// Complexity: O(1).
pub fn aviation_position_cpr_lon(p: &AviationPosition) -> Int {
  return p.cpr_lon;
}

// --------------------------------------------------
//  Airborne velocity (TC 19)
// --------------------------------------------------
//
// ME bits 1-5   TC = 19
// ME bits 6-8   subtype (1/2 ground speed, 3/4 airspeed)
// ME bit  9     intent change
// ME bit  10    IFR capability
// ME bits 11-13 NACv
// subtype 1/2: bit 14 EW sign, bits 15-24 EW velocity,
//              bit 25 NS sign, bits 26-35 NS velocity
// subtype 3/4: bit 14 heading status, bits 15-24 heading,
//              bit 25 airspeed type, bits 26-35 airspeed
// ME bit  36    vertical rate source (0 = GNSS, 1 = barometric)
// ME bit  37    vertical rate sign (1 = down)
// ME bits 38-46 vertical rate (9 bits)
// ME bits 47-48 reserved
// ME bit  49    GNSS/barometric difference sign (1 = below)
// ME bits 50-56 GNSS/barometric difference (7 bits)

/// Decoded airborne velocity message (TC 19). Speeds are whole knots
/// (`raw - 1`, so raw 0 means no information and is reported as -1);
/// `vr_fpm` is the vertical rate in feet per minute with the sign applied
/// (-1 = no information); `dif_ft` is the GNSS minus barometric altitude
/// difference in feet with the sign applied (-1 = no information).
/// `gs_kt` is the integer magnitude of the (EW, NS) ground vector, -1 when
/// either component is unknown or the message is the airspeed subtype.
pub type AviationVelocity = {
  tc: Int;
  subtype: Int;
  intent_change: Int;
  ifr_capability: Int;
  nac_v: Int;
  ew_sign: Int;
  ew_raw: Int;
  ew_kt: Int;
  ns_sign: Int;
  ns_raw: Int;
  ns_kt: Int;
  gs_kt: Int;
  heading_status: Int;
  heading_raw: Int;
  heading_deg100: Int;
  airspeed_type: Int;
  airspeed_raw: Int;
  airspeed_kt: Int;
  vr_source: Int;
  vr_sign: Int;
  vr_raw: Int;
  vr_fpm: Int;
  dif_sign: Int;
  dif_raw: Int;
  dif_ft: Int;
}

// Ok(v) for Result[AviationVelocity, Str].
fn _ok_velocity(v: AviationVelocity) -> Result[AviationVelocity, Str] {
  return Ok(v);
}

// Err(m) for Result[AviationVelocity, Str].
fn _err_velocity(m: Str) -> Result[AviationVelocity, Str] {
  return Err(m);
}

// Integer square root of a non-negative Int (Newton iteration on integers;
// for n < 0 the result is 0). Used for the ground-speed magnitude.
fn _isqrt(n: Int) -> Int {
  if n <= 0 {
    return 0;
  }
  var x = n;
  var y = (x + 1) / 2;
  while y < x {
    x = y;
    y = (x + n / x) / 2;
  }
  return x;
}

// A velocity component: raw 0 means no information (-1); otherwise the
// value is raw - 1 knots.
fn _vel_kt(raw: Int) -> Int {
  if raw == 0 {
    return -1;
  }
  return raw - 1;
}

// Vertical rate / altitude difference: raw 0 means no information (-1);
// otherwise (raw - 1) * step, with the sign bit (1 = down / below).
fn _signed_delta(raw: Int, sign: Int, step: Int) -> Int {
  if raw == 0 {
    return -1;
  }
  let v = (raw - 1) * step;
  if sign == 1 {
    return 0 - v;
  }
  return v;
}

/// Decode a DF17/DF18 airborne velocity message (TC 19).
/// Errors (all stable):
///   * `aviation: not an extended squitter frame` -- short frame or DF not
///     17/18;
///   * `aviation: not an airborne velocity message` -- TC not 19.
/// Complexity: O(1).
pub fn aviation_velocity_decode(f: &AviationFrame) -> Result[AviationVelocity, Str] {
  if !_is_squitter(f) {
    return _err_velocity("aviation: not an extended squitter frame");
  }
  if _me_bits(f, 1, 5) != 19 {
    return _err_velocity("aviation: not an airborne velocity message");
  }
  let st = _me_bits(f, 6, 3);
  var ew_sign = -1;
  var ew_raw = -1;
  var ew_kt = -1;
  var ns_sign = -1;
  var ns_raw = -1;
  var ns_kt = -1;
  var heading_status = -1;
  var heading_raw = -1;
  var heading_deg100 = -1;
  var airspeed_type = -1;
  var airspeed_raw = -1;
  var airspeed_kt = -1;
  if st == 1 || st == 2 {
    ew_sign = _me_bits(f, 14, 1);
    ew_raw = _me_bits(f, 15, 10);
    ew_kt = _vel_kt(ew_raw);
    ns_sign = _me_bits(f, 25, 1);
    ns_raw = _me_bits(f, 26, 10);
    ns_kt = _vel_kt(ns_raw);
  }
  if st == 3 || st == 4 {
    heading_status = _me_bits(f, 14, 1);
    heading_raw = _me_bits(f, 15, 10);
    heading_deg100 = (heading_raw * 1125 + 16) / 32;
    airspeed_type = _me_bits(f, 25, 1);
    airspeed_raw = _me_bits(f, 26, 10);
    airspeed_kt = _vel_kt(airspeed_raw);
  }
  var gs_kt = -1;
  if st == 1 || st == 2 {
    if ew_kt >= 0 && ns_kt >= 0 {
      gs_kt = _isqrt(ew_kt * ew_kt + ns_kt * ns_kt);
    }
  }
  let vr_source = _me_bits(f, 36, 1);
  let vr_sign = _me_bits(f, 37, 1);
  let vr_raw = _me_bits(f, 38, 9);
  let dif_sign = _me_bits(f, 49, 1);
  let dif_raw = _me_bits(f, 50, 7);
  let v = AviationVelocity{
    tc: 19;
    subtype: st;
    intent_change: _me_bits(f, 9, 1);
    ifr_capability: _me_bits(f, 10, 1);
    nac_v: _me_bits(f, 11, 3);
    ew_sign: ew_sign;
    ew_raw: ew_raw;
    ew_kt: ew_kt;
    ns_sign: ns_sign;
    ns_raw: ns_raw;
    ns_kt: ns_kt;
    gs_kt: gs_kt;
    heading_status: heading_status;
    heading_raw: heading_raw;
    heading_deg100: heading_deg100;
    airspeed_type: airspeed_type;
    airspeed_raw: airspeed_raw;
    airspeed_kt: airspeed_kt;
    vr_source: vr_source;
    vr_sign: vr_sign;
    vr_raw: vr_raw;
    vr_fpm: _signed_delta(vr_raw, vr_sign, 64);
    dif_sign: dif_sign;
    dif_raw: dif_raw;
    dif_ft: _signed_delta(dif_raw, dif_sign, 25);
  };
  return _ok_velocity(v);
}

/// Type code of a decoded airborne velocity message (always 19).
/// Complexity: O(1).
pub fn aviation_velocity_tc(v: &AviationVelocity) -> Int {
  return v.tc;
}

/// Subtype (ME bits 6-8): 1/2 ground speed, 3/4 airspeed.
/// Complexity: O(1).
pub fn aviation_velocity_subtype(v: &AviationVelocity) -> Int {
  return v.subtype;
}

/// NUCv / NACv (ME bits 11-13), returned raw.
/// Complexity: O(1).
pub fn aviation_velocity_nac_v(v: &AviationVelocity) -> Int {
  return v.nac_v;
}

/// East-west velocity sign: 1 = west, 0 = east; -1 for airspeed subtypes.
/// Complexity: O(1).
pub fn aviation_velocity_ew_sign(v: &AviationVelocity) -> Int {
  return v.ew_sign;
}

/// East-west velocity in knots (-1 = no information, -1 = not applicable).
/// Complexity: O(1).
pub fn aviation_velocity_ew_kt(v: &AviationVelocity) -> Int {
  return v.ew_kt;
}

/// North-south velocity sign: 1 = south, 0 = north; -1 for airspeed
/// subtypes.
/// Complexity: O(1).
pub fn aviation_velocity_ns_sign(v: &AviationVelocity) -> Int {
  return v.ns_sign;
}

/// North-south velocity in knots (-1 = no information or not applicable).
/// Complexity: O(1).
pub fn aviation_velocity_ns_kt(v: &AviationVelocity) -> Int {
  return v.ns_kt;
}

/// Ground speed magnitude in whole knots (integer sqrt of EW^2 + NS^2), or
/// -1 when a component is unknown or the message carries airspeed.
/// Complexity: O(1).
pub fn aviation_velocity_gs_kt(v: &AviationVelocity) -> Int {
  return v.gs_kt;
}

/// Heading status bit for subtypes 3/4 (1 = valid), -1 otherwise.
/// Complexity: O(1).
pub fn aviation_velocity_heading_status(v: &AviationVelocity) -> Int {
  return v.heading_status;
}

/// Heading in hundredths of a degree (rounded) for subtypes 3/4, -1
/// otherwise. The exact scale is raw * 360 / 1024 degrees.
/// Complexity: O(1).
pub fn aviation_velocity_heading_deg100(v: &AviationVelocity) -> Int {
  return v.heading_deg100;
}

/// Airspeed type for subtypes 3/4: 0 = IAS, 1 = TAS; -1 otherwise.
/// Complexity: O(1).
pub fn aviation_velocity_airspeed_type(v: &AviationVelocity) -> Int {
  return v.airspeed_type;
}

/// Airspeed in knots for subtypes 3/4 (-1 = no information or not
/// applicable).
/// Complexity: O(1).
pub fn aviation_velocity_airspeed_kt(v: &AviationVelocity) -> Int {
  return v.airspeed_kt;
}

/// Vertical rate source: 0 = GNSS, 1 = barometric.
/// Complexity: O(1).
pub fn aviation_velocity_vr_source(v: &AviationVelocity) -> Int {
  return v.vr_source;
}

/// Vertical rate in feet per minute, signed (1 = down), -1 = no
/// information.
/// Complexity: O(1).
pub fn aviation_velocity_vr_fpm(v: &AviationVelocity) -> Int {
  return v.vr_fpm;
}

/// GNSS minus barometric altitude difference in feet, signed (1 = below),
/// -1 = no information.
/// Complexity: O(1).
pub fn aviation_velocity_dif_ft(v: &AviationVelocity) -> Int {
  return v.dif_ft;
}

// --------------------------------------------------
//  Compact Position Reporting (CPR)
// --------------------------------------------------
//
// All public positions are scaled integers in units of 10^-5 degrees
// (degrees x 100000), so 52.25720 deg = 5225720 and 3.91937 deg = 391937.
// Internally the decode uses 10^-7 degree units (SC7 = 10000000) and pure
// integer rational arithmetic: no floating point and no trigonometry are
// used anywhere. The final 10^-5 value is the 10^-7 value rounded half away
// from zero, i.e. about 1.1 m of quantisation, well below the CPR grid
// (~5 m per zone step).
//
// A CPR pair (the 17-bit latitude and 17-bit longitude fields of one frame)
// is packed into one Int as `lat * 131072 + lon` so the decoders take plain
// Ints. `aviation_cpr_pack` / `aviation_cpr_pack_lat` / `aviation_cpr_pack_lon`
// convert between the two representations.

const _AV_SC7: Int = 10000000;
const _AV_CPR_SCALE: Int = 131072;
const _AV_DEG360: Int = 3600000000;
const _AV_LATUNIT: Int = 471859200000000;
const _AV_LATHALF: Int = 235929600000000;

// floor(a / b) for b > 0 (division in XIOM truncates toward zero, so
// negative numerators need a correction).
fn _floor_div(a: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  if r != 0 && r < 0 {
    return q - 1;
  }
  return q;
}

// a - floor(a / b) * b for b > 0; always in [0, b).
fn _floor_mod(a: Int, b: Int) -> Int {
  return a - _floor_div(a, b) * b;
}

// Rounded division by 100 (half away from zero), used to return 10^-5
// scaled values from the 10^-7 internal scale.
fn _round100(v: Int) -> Int {
  if v >= 0 {
    return (v + 50) / 100;
  }
  return 0 - ((0 - v + 50) / 100);
}

// NL(lat) for a latitude in 10^-7 degree units: the number of longitude
// zones of the CPR grid at that latitude, 1..59. The comparison table holds
// the 58 documented zone-boundary latitudes (degrees x 10^7, from DO-260 /
// the standard CPR table); |lat| below boundary i has NL = 59 - i.
fn _nl7(lat7: Int) -> Int {
  var a = lat7;
  if a < 0 {
    a = 0 - a;
  }
  var i = 0;
  while i < 58 {
    var th = 0;
    if i == 0 { th = 104704713; }
    if i == 1 { th = 148281744; }
    if i == 2 { th = 181862636; }
    if i == 3 { th = 210293949; }
    if i == 4 { th = 235450449; }
    if i == 5 { th = 258292471; }
    if i == 6 { th = 279389871; }
    if i == 7 { th = 299113569; }
    if i == 8 { th = 317720971; }
    if i == 9 { th = 335399344; }
    if i == 10 { th = 352289960; }
    if i == 11 { th = 368502511; }
    if i == 12 { th = 384124189; }
    if i == 13 { th = 399225668; }
    if i == 14 { th = 413865183; }
    if i == 15 { th = 428091401; }
    if i == 16 { th = 441945495; }
    if i == 17 { th = 455462672; }
    if i == 18 { th = 468673325; }
    if i == 19 { th = 481603913; }
    if i == 20 { th = 494277644; }
    if i == 21 { th = 506715017; }
    if i == 22 { th = 518934247; }
    if i == 23 { th = 530951615; }
    if i == 24 { th = 542781747; }
    if i == 25 { th = 554437844; }
    if i == 26 { th = 565931876; }
    if i == 27 { th = 577274735; }
    if i == 28 { th = 588476378; }
    if i == 29 { th = 599545928; }
    if i == 30 { th = 610491777; }
    if i == 31 { th = 621321666; }
    if i == 32 { th = 632042748; }
    if i == 33 { th = 642661652; }
    if i == 34 { th = 653184531; }
    if i == 35 { th = 663617101; }
    if i == 36 { th = 673964677; }
    if i == 37 { th = 684232202; }
    if i == 38 { th = 694424263; }
    if i == 39 { th = 704545108; }
    if i == 40 { th = 714598647; }
    if i == 41 { th = 724588455; }
    if i == 42 { th = 734517744; }
    if i == 43 { th = 744389342; }
    if i == 44 { th = 754205626; }
    if i == 45 { th = 763968439; }
    if i == 46 { th = 773678946; }
    if i == 47 { th = 783337408; }
    if i == 48 { th = 792942823; }
    if i == 49 { th = 802492321; }
    if i == 50 { th = 811980135; }
    if i == 51 { th = 821395698; }
    if i == 52 { th = 830719945; }
    if i == 53 { th = 839917356; }
    if i == 54 { th = 848916619; }
    if i == 55 { th = 857554162; }
    if i == 56 { th = 865353700; }
    if i == 57 { th = 870000000; }
    if a < th {
      return 59 - i;
    }
    i = i + 1;
  }
  return 1;
}

/// NL(lat): number of CPR longitude zones at latitude `lat_scaled`
/// (degrees x 100000, so 52.5 deg = 5250000). The sign is ignored. The
/// result is 1..59: 59 at the equator, 1 at |lat| >= 87.
/// The boundary table is the standard 58-entry CPR table at 10^-7 degree
/// resolution; because the input is exact at 10^-5 degrees there is no
/// additional rounding error below 10^-7 deg (about 1 cm on the ground).
/// Complexity: O(1).
pub fn aviation_cpr_nl(lat_scaled: Int) -> Int {
  return _nl7(lat_scaled * 100);
}

/// Pack a CPR pair: `lat_cpr * 131072 + lon_cpr` (both fields are 17-bit
/// values, 0..131071).
/// Complexity: O(1).
pub fn aviation_cpr_pack(lat_cpr: Int, lon_cpr: Int) -> Int {
  return lat_cpr * _AV_CPR_SCALE + lon_cpr;
}

/// Latitude field (17 bits) of a packed CPR pair.
/// Complexity: O(1).
pub fn aviation_cpr_pack_lat(packed: Int) -> Int {
  return packed / _AV_CPR_SCALE;
}

/// Longitude field (17 bits) of a packed CPR pair.
/// Complexity: O(1).
pub fn aviation_cpr_pack_lon(packed: Int) -> Int {
  return packed % _AV_CPR_SCALE;
}

/// A decoded position. `lat_scaled` and `lon_scaled` are in degrees x
/// 100000 (rounded half away from zero from the internal 10^-7 scale),
/// `nl` is the CPR longitude-zone count at the decoded latitude and `odd`
/// is 1 when the position came from the odd frame, 0 for the even frame.
pub type AviationFix = {
  lat_scaled: Int;
  lon_scaled: Int;
  nl: Int;
  odd: Int;
}

// Ok(v) for Result[AviationFix, Str].
fn _ok_fix(v: AviationFix) -> Result[AviationFix, Str] {
  return Ok(v);
}

// Err(m) for Result[AviationFix, Str].
fn _err_fix(m: Str) -> Result[AviationFix, Str] {
  return Err(m);
}

// Normalise a 10^-7 degree longitude into (-180, 180].
fn _norm_lon7(lon7: Int) -> Int {
  var v = lon7;
  if v > 180 * _AV_SC7 {
    v = v - 360 * _AV_SC7;
  }
  if v <= 0 - 180 * _AV_SC7 {
    v = v + 360 * _AV_SC7;
  }
  return v;
}

/// Global (frame-pair) CPR decode from the even and the odd frame of the
/// same pair, both packed with aviation_cpr_pack. `latest_odd` selects
/// which frame is the most recent one (nonzero = odd); the returned fix
/// describes that frame's solution. Both frames must be within 10 s of each
/// other for the underlying model to hold -- that ordering and freshness
/// check is caller-side.
///
/// The latitude is computed from the pair; if it comes out above 270 deg it
/// is taken as southern hemisphere (360 subtracted), which is the standard
/// single-solution rule. That rule and the choice of the newest frame are
/// the documented ambiguity boundary: a caller tracking a real aircraft
/// should reject fixes that jump implausibly and prefer the newest frame,
/// as dump1090 and pyModeS do.
///
/// Errors (all stable):
///   * `aviation: cpr nl mismatch` -- the even and odd frames imply
///     different NL values (the pair is inconsistent, e.g. different
///     latitudes or too far apart in time);
///   * `aviation: cpr field out of range` -- a packed pair is outside
///     0..2^34-1.
/// Complexity: O(1).
pub fn aviation_cpr_decode_global(even: Int, odd: Int, latest_odd: Int) -> Result[AviationFix, Str] {
  if even < 0 || odd < 0 {
    return _err_fix("aviation: cpr field out of range");
  }
  if even >= 17179869184 || odd >= 17179869184 {
    return _err_fix("aviation: cpr field out of range");
  }
  let yz_e = even / _AV_CPR_SCALE;
  let xz_e = even % _AV_CPR_SCALE;
  let yz_o = odd / _AV_CPR_SCALE;
  let xz_o = odd % _AV_CPR_SCALE;
  let j = _floor_div(2 * (59 * yz_e - 60 * yz_o) + _AV_CPR_SCALE, 2 * _AV_CPR_SCALE);
  var lat_e7 = _floor_div(_AV_DEG360 * (_floor_mod(j, 60) * _AV_CPR_SCALE + yz_e), 60 * _AV_CPR_SCALE);
  var lat_o7 = _floor_div(_AV_DEG360 * (_floor_mod(j, 59) * _AV_CPR_SCALE + yz_o), 59 * _AV_CPR_SCALE);
  if lat_e7 > 270 * _AV_SC7 {
    lat_e7 = lat_e7 - 360 * _AV_SC7;
  }
  if lat_o7 > 270 * _AV_SC7 {
    lat_o7 = lat_o7 - 360 * _AV_SC7;
  }
  let nl_e = _nl7(lat_e7);
  let nl_o = _nl7(lat_o7);
  if nl_e != nl_o {
    return _err_fix("aviation: cpr nl mismatch");
  }
  var i = 0;
  var lat7 = lat_e7;
  var xz = xz_e;
  if latest_odd != 0 {
    i = 1;
    lat7 = lat_o7;
    xz = xz_o;
  }
  var ni = nl_e - i;
  if ni < 1 {
    ni = 1;
  }
  let m = _floor_div(2 * (xz_e * (nl_e - 1) - xz_o * nl_e) + _AV_CPR_SCALE, 2 * _AV_CPR_SCALE);
  let lon7 = _norm_lon7(_floor_div(_AV_DEG360 * (_floor_mod(m, ni) * _AV_CPR_SCALE + xz), ni * _AV_CPR_SCALE));
  let fix = AviationFix{
    lat_scaled: _round100(lat7);
    lon_scaled: _round100(lon7);
    nl: nl_e;
    odd: i;
  };
  return _ok_fix(fix);
}

/// Local CPR decode relative to a reference position. `odd` and `even` are
/// packed CPR pairs (see aviation_cpr_pack); `latest_odd` (nonzero = odd)
/// selects which frame is decoded. `ref_lat_scaled` / `ref_lon_scaled` are
/// the reference position in degrees x 100000 and must be within half a
/// zone of the true position (~3 deg of latitude for the even zone, ~3.05
/// for the odd one), which is the caller's responsibility (this is what
/// "local" CPR means: the reference removes the ambiguity).
///
/// Errors (all stable):
///   * `aviation: cpr field out of range` -- a packed pair is outside
///     0..2^34-1.
/// Complexity: O(1).
pub fn aviation_cpr_decode_local(odd: Int, even: Int, latest_odd: Int, ref_lat_scaled: Int, ref_lon_scaled: Int) -> Result[AviationFix, Str] {
  if odd < 0 || even < 0 {
    return _err_fix("aviation: cpr field out of range");
  }
  if odd >= 17179869184 || even >= 17179869184 {
    return _err_fix("aviation: cpr field out of range");
  }
  var i = 0;
  var p = even;
  if latest_odd != 0 {
    i = 1;
    p = odd;
  }
  let yz = p / _AV_CPR_SCALE;
  let xz = p % _AV_CPR_SCALE;
  let ref_lat7 = ref_lat_scaled * 100;
  let ref_lon7 = ref_lon_scaled * 100;
  let span = 60 - i;
  let j_lat = _floor_div(ref_lat7 * span, _AV_DEG360) + _floor_div(_floor_mod(ref_lat7 * span, _AV_DEG360) * _AV_CPR_SCALE + _AV_LATHALF - yz * _AV_DEG360, _AV_LATUNIT);
  let lat7 = _floor_div(_AV_DEG360 * (j_lat * _AV_CPR_SCALE + yz), span * _AV_CPR_SCALE);
  let nl = _nl7(lat7);
  var ni = nl - i;
  if ni < 1 {
    ni = 1;
  }
  let m_lon = _floor_div(ref_lon7 * ni, _AV_DEG360) + _floor_div(_floor_mod(ref_lon7 * ni, _AV_DEG360) * _AV_CPR_SCALE + _AV_LATHALF - xz * _AV_DEG360, _AV_LATUNIT);
  let lon7 = _norm_lon7(_floor_div(_AV_DEG360 * (m_lon * _AV_CPR_SCALE + xz), ni * _AV_CPR_SCALE));
  let fix = AviationFix{
    lat_scaled: _round100(lat7);
    lon_scaled: _round100(lon7);
    nl: nl;
    odd: i;
  };
  return _ok_fix(fix);
}

/// Latitude of a decoded fix, in degrees x 100000.
/// Complexity: O(1).
pub fn aviation_fix_lat(f: &AviationFix) -> Int {
  return f.lat_scaled;
}

/// Longitude of a decoded fix, in degrees x 100000 (normalised to
/// (-180, 180]).
/// Complexity: O(1).
pub fn aviation_fix_lon(f: &AviationFix) -> Int {
  return f.lon_scaled;
}

/// NL value at the decoded latitude (1..59).
/// Complexity: O(1).
pub fn aviation_fix_nl(f: &AviationFix) -> Int {
  return f.nl;
}

/// 1 when the fix came from the odd frame, 0 for the even frame.
/// Complexity: O(1).
pub fn aviation_fix_odd(f: &AviationFix) -> Int {
  return f.odd;
}

// --------------------------------------------------
//  Target state and status (TC 29)
// --------------------------------------------------
//
// ME bits 1-5   TC = 29
// ME bits 6-7   subtype (1 = selected altitude / heading)
// ME bit  8     SIL supplement
// ME bits 9-19  selected altitude, 11 bits, returned raw (the M/Q
//               sub-encoding is not interpreted here)
// ME bits 20-28 barometric pressure setting, 9 bits
// ME bit  29    selected heading status
// ME bits 30-38 selected heading, 9 bits
// ME bits 39-42 NACp
// ME bit  43    NICbaro
// ME bits 44-45 SIL
// ME bits 46-47 mode-bits status
// ME bit  48    autopilot engaged
// ME bit  49    VNAV mode
// ME bit  50    altitude hold mode
// ME bit  51    approach mode
// ME bit  52    TCAS operational
// ME bit  53    LNAV mode

/// Decoded target state and status message (TC 29, subtype 1).
/// `baro_hpa10` is the selected barometric pressure in tenths of a hPa
/// (8000 + 8 * raw = 800.0 hPa at raw 0). `heading_deg100` is hundredths of
/// a degree (rounded). `selected_alt_raw` is the raw 11-bit field: its M/Q
/// sub-encoding is intentionally not interpreted (see SPEC.md).
pub type AviationTargetState = {
  tc: Int;
  subtype: Int;
  selected_alt_raw: Int;
  baro_hpa10: Int;
  heading_status: Int;
  heading_raw: Int;
  heading_deg100: Int;
  nacp: Int;
  nic_baro: Int;
  sil: Int;
  autopilot: Int;
  vnav: Int;
  alt_hold: Int;
  approach: Int;
  tcas: Int;
  lnav: Int;
}

// Ok(v) for Result[AviationTargetState, Str].
fn _ok_target(v: AviationTargetState) -> Result[AviationTargetState, Str] {
  return Ok(v);
}

// Err(m) for Result[AviationTargetState, Str].
fn _err_target(m: Str) -> Result[AviationTargetState, Str] {
  return Err(m);
}

/// Barometric pressure setting from the 9-bit TC29 field, in tenths of a
/// hPa: value * 0.8 + 800.0 hPa, so `aviation_baro_hpa10(0) = 8000`
/// (800.0 hPa) and `aviation_baro_hpa10(511) = 12088` (1208.8 hPa).
/// Complexity: O(1).
pub fn aviation_baro_hpa10(raw9: Int) -> Int {
  return 8000 + 8 * raw9;
}

/// Selected heading from the 9-bit TC29 field, in hundredths of a degree
/// (rounded); the exact scale is raw * 360 / 512 degrees.
/// Complexity: O(1).
pub fn aviation_selected_heading_deg100(raw9: Int) -> Int {
  return (raw9 * 1125 + 8) / 16;
}

/// Decode a DF17/DF18 target state and status message (TC 29).
/// Subtype 1 is implemented; other subtypes have a different payload.
/// Errors (all stable):
///   * `aviation: not an extended squitter frame` -- short frame or DF not
///     17/18;
///   * `aviation: not a target state message` -- TC not 29;
///   * `aviation: unsupported target state subtype` -- subtype not 1.
/// Complexity: O(1).
pub fn aviation_target_state_decode(f: &AviationFrame) -> Result[AviationTargetState, Str] {
  if !_is_squitter(f) {
    return _err_target("aviation: not an extended squitter frame");
  }
  if _me_bits(f, 1, 5) != 29 {
    return _err_target("aviation: not a target state message");
  }
  let st = _me_bits(f, 6, 2);
  if st != 1 {
    return _err_target("aviation: unsupported target state subtype");
  }
  let hdg = _me_bits(f, 30, 9);
  let t = AviationTargetState{
    tc: 29;
    subtype: st;
    selected_alt_raw: _me_bits(f, 9, 11);
    baro_hpa10: aviation_baro_hpa10(_me_bits(f, 20, 9));
    heading_status: _me_bits(f, 29, 1);
    heading_raw: hdg;
    heading_deg100: aviation_selected_heading_deg100(hdg);
    nacp: _me_bits(f, 39, 4);
    nic_baro: _me_bits(f, 43, 1);
    sil: _me_bits(f, 44, 2);
    autopilot: _me_bits(f, 48, 1);
    vnav: _me_bits(f, 49, 1);
    alt_hold: _me_bits(f, 50, 1);
    approach: _me_bits(f, 51, 1);
    tcas: _me_bits(f, 52, 1);
    lnav: _me_bits(f, 53, 1);
  };
  return _ok_target(t);
}

/// Subtype of a decoded target state message (1).
/// Complexity: O(1).
pub fn aviation_target_state_subtype(t: &AviationTargetState) -> Int {
  return t.subtype;
}

/// Raw 11-bit selected altitude field.
/// Complexity: O(1).
pub fn aviation_target_state_alt_raw(t: &AviationTargetState) -> Int {
  return t.selected_alt_raw;
}

/// Selected barometric pressure in tenths of a hPa.
/// Complexity: O(1).
pub fn aviation_target_state_baro_hpa10(t: &AviationTargetState) -> Int {
  return t.baro_hpa10;
}

/// Selected heading status bit (1 = valid).
/// Complexity: O(1).
pub fn aviation_target_state_heading_status(t: &AviationTargetState) -> Int {
  return t.heading_status;
}

/// Selected heading in hundredths of a degree (rounded).
/// Complexity: O(1).
pub fn aviation_target_state_heading_deg100(t: &AviationTargetState) -> Int {
  return t.heading_deg100;
}

/// NACp (4 bits).
/// Complexity: O(1).
pub fn aviation_target_state_nacp(t: &AviationTargetState) -> Int {
  return t.nacp;
}

/// Autopilot engaged bit.
/// Complexity: O(1).
pub fn aviation_target_state_autopilot(t: &AviationTargetState) -> Int {
  return t.autopilot;
}

/// Vertical navigation mode bit.
/// Complexity: O(1).
pub fn aviation_target_state_vnav(t: &AviationTargetState) -> Int {
  return t.vnav;
}

/// Altitude hold mode bit.
/// Complexity: O(1).
pub fn aviation_target_state_alt_hold(t: &AviationTargetState) -> Int {
  return t.alt_hold;
}

/// Approach mode bit.
/// Complexity: O(1).
pub fn aviation_target_state_approach(t: &AviationTargetState) -> Int {
  return t.approach;
}

/// TCAS operational bit.
/// Complexity: O(1).
pub fn aviation_target_state_tcas(t: &AviationTargetState) -> Int {
  return t.tcas;
}

/// Lateral navigation mode bit.
/// Complexity: O(1).
pub fn aviation_target_state_lnav(t: &AviationTargetState) -> Int {
  return t.lnav;
}

// --------------------------------------------------
//  Operational status (TC 31)
// --------------------------------------------------
//
// ME bits 1-5   TC = 31
// ME bits 6-8   subtype (0 = airborne, 1 = surface)
// ME bits 9-24  airborne capability class (16 bits), returned raw
// ME bits 25-40 operational mode (16 bits), returned raw
// ME bits 41-43 ADS-B version number
// ME bit  44    NIC supplement A
// ME bits 45-48 NACp
// ME bits 49-50 GVA (version 2)
// ME bits 51-52 SIL
//
// The bit positions above follow the version-2 (DO-260B) airborne layout.
// Version 0/1 messages share the version/NIC/NACp positions but use the
// tail bits differently; only the version-2 tail is documented here.

/// Decoded operational status message (TC 31, subtype 0).
/// `cc` and `om` are the raw 16-bit capability-class and operational-mode
/// codes. `version` is the 3-bit ADS-B version (0..7); `nic_a` the NIC
/// supplement A bit; `nacp` the 4-bit NACp; `sil` the 2-bit SIL.
pub type AviationOpStatus = {
  tc: Int;
  subtype: Int;
  cc: Int;
  om: Int;
  version: Int;
  nic_a: Int;
  nacp: Int;
  sil: Int;
}

// Ok(v) for Result[AviationOpStatus, Str].
fn _ok_opstatus(v: AviationOpStatus) -> Result[AviationOpStatus, Str] {
  return Ok(v);
}

// Err(m) for Result[AviationOpStatus, Str].
fn _err_opstatus(m: Str) -> Result[AviationOpStatus, Str] {
  return Err(m);
}

/// Decode a DF17/DF18 operational status message (TC 31).
/// Subtype 0 (airborne) is implemented with the version-2 tail layout;
/// subtype 1 (surface) has a different payload and is rejected.
/// Errors (all stable):
///   * `aviation: not an extended squitter frame` -- short frame or DF not
///     17/18;
///   * `aviation: not an operational status message` -- TC not 31;
///   * `aviation: unsupported operational status subtype` -- subtype not 0.
/// Complexity: O(1).
pub fn aviation_op_status_decode(f: &AviationFrame) -> Result[AviationOpStatus, Str] {
  if !_is_squitter(f) {
    return _err_opstatus("aviation: not an extended squitter frame");
  }
  if _me_bits(f, 1, 5) != 31 {
    return _err_opstatus("aviation: not an operational status message");
  }
  let st = _me_bits(f, 6, 3);
  if st != 0 {
    return _err_opstatus("aviation: unsupported operational status subtype");
  }
  let o = AviationOpStatus{
    tc: 31;
    subtype: st;
    cc: _me_bits(f, 9, 16);
    om: _me_bits(f, 25, 16);
    version: _me_bits(f, 41, 3);
    nic_a: _me_bits(f, 44, 1);
    nacp: _me_bits(f, 45, 4);
    sil: _me_bits(f, 51, 2);
  };
  return _ok_opstatus(o);
}

/// Subtype of a decoded operational status message (0 = airborne).
/// Complexity: O(1).
pub fn aviation_op_status_subtype(o: &AviationOpStatus) -> Int {
  return o.subtype;
}

/// Raw 16-bit capability class code (ME bits 9-24), not further decoded.
/// Complexity: O(1).
pub fn aviation_op_status_cc(o: &AviationOpStatus) -> Int {
  return o.cc;
}

/// Raw 16-bit operational mode code (ME bits 25-40), not further decoded.
/// Complexity: O(1).
pub fn aviation_op_status_om(o: &AviationOpStatus) -> Int {
  return o.om;
}

/// ADS-B version number (ME bits 41-43), 0..7.
/// Complexity: O(1).
pub fn aviation_op_status_version(o: &AviationOpStatus) -> Int {
  return o.version;
}

/// NIC supplement A bit (ME bit 44).
/// Complexity: O(1).
pub fn aviation_op_status_nic_a(o: &AviationOpStatus) -> Int {
  return o.nic_a;
}

/// NACp (ME bits 45-48).
/// Complexity: O(1).
pub fn aviation_op_status_nacp(o: &AviationOpStatus) -> Int {
  return o.nacp;
}

/// SIL (ME bits 51-52).
/// Complexity: O(1).
pub fn aviation_op_status_sil(o: &AviationOpStatus) -> Int {
  return o.sil;
}

/// Library version string.
pub fn aviation_version() -> Str {
  return "0.1.0";
}
