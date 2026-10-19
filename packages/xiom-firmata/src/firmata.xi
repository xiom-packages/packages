// XIOM -- xiom.firmata: Firmata 2.x host-side protocol bindings
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no C) host-side codec and session loop for the Firmata
// protocol. Firmata frames its messages with the MIDI wire format: a status
// byte (0x80..0xFF), one or two 7-bit data bytes, and a sysex frame for
// extended commands (0xF0 ... 0xF7). This package implements the subset
// declared in SPEC.md:
//
//   * handshake: version-report decode, version query, firmware-report
//     decode, firmware query;
//   * SET_PIN_MODE, SET_DIGITAL_PIN_VALUE, DIGITAL_MESSAGE (port write),
//     ANALOG_MESSAGE (PWM write), REPORT_ANALOG and REPORT_DIGITAL writes;
//   * decode of protocol version, firmware, digital port, analog channel,
//     string (2 x 7-bit chars), report enable, set-mode and set-pin frames;
//   * SYSTEM_RESET;
//   * a transport-agnostic session: the caller injects received bytes with
//     firmata_session_feed and drains queued host bytes with
//     firmata_session_take_output. The session tracks the digital port
//     shadow and the handshake state; it performs no I/O itself.
//
// Everything fallible returns Result[..., FirmataError] with a typed kind, an
// integer code (offending byte, value, or length) and a message. Public
// entry points never panic on caller input: argument validation runs before
// any state change and returns FIRMATA_ERR_OUT_OF_RANGE /
// FIRMATA_ERR_INVALID_ARG. There are no input-condition `requires` clauses.
//
// Compiler notes (v0.64.7):
//   * free functions only; no methods, no lambdas, no callback bridging.
//   * wire values are widened with `(b as Int) & 0xFF` before Int
//     arithmetic; frame fields stay 7-bit so no bit-31 shift is involved.
//   * all multi-byte wire values are little-endian 7-bit groups and are
//     assembled with multiplication/addition (value = lsb + msb * 128),
//     never with byte-order tricks.
//   * string data is decoded through xiom.string.builder and xiom.utf8;
//     a NUL codepoint terminates the string (C-string transport semantics,
//     matching xiom.string.builder.sb_to_str).
//   * the session resolves field references (`&s.rx`, `&mut s.out`) through
//     locals at call sites; the v0.64.7 checker handles those shapes.
//
// See SPEC.md for the byte tables and the exact declared subset, PROVENANCE
// for the upstream references, and docs/COVERAGE.md for the per-function
// test map.

module xiom.firmata

use xiom.string.builder;
use xiom.utf8;

// =========================================================================
// Protocol constants (Firmata protocol 2.8.0; SPEC.md sec. 2)
// =========================================================================

/// Analog I/O / PWM message status base (0xE0 | channel).
pub const FIRMATA_ANALOG_MESSAGE: Int = 0xE0;

/// Digital I/O message status base (0x90 | port).
pub const FIRMATA_DIGITAL_MESSAGE: Int = 0x90;

/// Report-analog enable status base (0xC0 | analog channel).
pub const FIRMATA_REPORT_ANALOG: Int = 0xC0;

/// Report-digital-port enable status base (0xD0 | port).
pub const FIRMATA_REPORT_DIGITAL: Int = 0xD0;

/// Set-pin-mode command (0xF4 pin mode).
pub const FIRMATA_SET_PIN_MODE: Int = 0xF4;

/// Set-digital-pin-value command (0xF5 pin value; Firmata 2.5+).
pub const FIRMATA_SET_DIGITAL_PIN_VALUE: Int = 0xF5;

/// Sysex start byte.
pub const FIRMATA_START_SYSEX: Int = 0xF0;

/// Sysex end byte.
pub const FIRMATA_END_SYSEX: Int = 0xF7;

/// Protocol-version report/query (0xF9 major minor).
pub const FIRMATA_REPORT_VERSION: Int = 0xF9;

/// System reset (0xFF).
pub const FIRMATA_SYSTEM_RESET: Int = 0xFF;

/// Sysex STRING_DATA sub-command (2 x 7-bit bytes per character).
pub const FIRMATA_STRING_DATA: Int = 0x71;

/// Sysex REPORT_FIRMWARE sub-command (major, minor, 2 x 7-bit name chars).
pub const FIRMATA_REPORT_FIRMWARE: Int = 0x79;

/// Largest pin number accepted by SET_PIN_MODE / SET_DIGITAL_PIN_VALUE.
pub const FIRMATA_MAX_PIN: Int = 127;

/// Largest digital port number accepted by the port messages.
pub const FIRMATA_MAX_PORT: Int = 15;

/// Largest analog channel number accepted by REPORT_ANALOG.
pub const FIRMATA_MAX_ANALOG_CHANNEL: Int = 15;

/// Largest 7-bit data byte.
pub const FIRMATA_MAX_7BIT: Int = 127;

/// Largest 14-bit wire value (two 7-bit groups).
pub const FIRMATA_MAX_14BIT: Int = 16383;

/// Number of digital ports tracked by a session (16 x 8 pins = 128 pins).
pub const FIRMATA_SESSION_PORTS: Int = 16;

/// Default session receive-buffer limit, in bytes.
pub const FIRMATA_RX_LIMIT_DEFAULT: Int = 4096;

/// Pin mode: digital input (0x00).
pub const FIRMATA_MODE_INPUT: Int = 0x00;

/// Pin mode: digital output (0x01).
pub const FIRMATA_MODE_OUTPUT: Int = 0x01;

/// Pin mode: analog input (0x02).
pub const FIRMATA_MODE_ANALOG: Int = 0x02;

/// Pin mode: PWM output (0x03).
pub const FIRMATA_MODE_PWM: Int = 0x03;

/// Pin mode: servo output (0x04).
pub const FIRMATA_MODE_SERVO: Int = 0x04;

/// Pin mode: shift register (0x05).
pub const FIRMATA_MODE_SHIFT: Int = 0x05;

/// Pin mode: I2C (0x06).
pub const FIRMATA_MODE_I2C: Int = 0x06;

/// Pin mode: OneWire (0x07).
pub const FIRMATA_MODE_ONEWIRE: Int = 0x07;

/// Pin mode: stepper (0x08).
pub const FIRMATA_MODE_STEPPER: Int = 0x08;

/// Pin mode: encoder (0x09).
pub const FIRMATA_MODE_ENCODER: Int = 0x09;

/// Pin mode: serial (0x0A).
pub const FIRMATA_MODE_SERIAL: Int = 0x0A;

/// Pin mode: input with pull-up (0x0B).
pub const FIRMATA_MODE_PULLUP: Int = 0x0B;

/// Error kind: a caller argument is malformed for the call.
pub const FIRMATA_ERR_INVALID_ARG: Int = 1;

/// Error kind: a caller value or wire value is outside its declared range.
pub const FIRMATA_ERR_OUT_OF_RANGE: Int = 2;

/// Error kind: a frame is incomplete (no complete message is available).
pub const FIRMATA_ERR_TRUNCATED: Int = 3;

/// Error kind: a status byte is not a declared Firmata/MIDI-realtime status.
pub const FIRMATA_ERR_BAD_STATUS: Int = 4;

/// Error kind: a sysex frame is malformed or interrupted.
pub const FIRMATA_ERR_BAD_SYSEX: Int = 5;

/// Error kind: a 2 x 7-bit string payload is malformed.
pub const FIRMATA_ERR_BAD_STRING: Int = 6;

/// Error kind: a well-formed frame of a different message type was supplied.
pub const FIRMATA_ERR_UNSUPPORTED: Int = 7;

/// Error kind: the session receive buffer would exceed its limit.
pub const FIRMATA_ERR_BUFFER_FULL: Int = 8;

// =========================================================================
// Public types
// =========================================================================

/// Typed error carried by every fallible API.
///
/// `kind` is one of the FIRMATA_ERR_* constants; `code` is the offending
/// byte/value/length (0 when there is no natural code); `message` is a
/// stable, human-readable description.
pub type FirmataError = {
  kind: Int;
  code: Int;
  message: Str;
}

/// Protocol version report: `major.minor` (each 0..127).
pub type FirmataVersion = {
  major: Int;
  minor: Int;
}

/// Firmware report: protocol version plus the firmware name decoded from
/// the 2 x 7-bit character stream.
pub type FirmataFirmware = {
  major: Int;
  minor: Int;
  name: Str;
}

/// Digital port report: `port` (0..15) and the 14-bit wire `mask`
/// (bits 0..7 are the eight pins of the port; bits 8..13 are preserved
/// as received).
pub type FirmataDigital = {
  port: Int;
  mask: Int;
}

/// Analog report: `channel` (0..15) and `value` (0..16383).
pub type FirmataAnalog = {
  channel: Int;
  value: Int;
}

/// REPORT_ANALOG / REPORT_DIGITAL decode: `channel` is the analog channel
/// or digital port; `enabled` is true for any non-zero wire value.
pub type FirmataReport = {
  channel: Int;
  enabled: Bool;
}

/// SET_PIN_MODE decode.
pub type FirmataPinMode = {
  pin: Int;
  mode: Int;
}

/// SET_DIGITAL_PIN_VALUE decode (`value` is 0 or 1 on the wire).
pub type FirmataPinValue = {
  pin: Int;
  value: Int;
}

/// A well-framed message outside the declared decode subset: `command` is
/// the status byte or sysex sub-command id, `length` is the payload length
/// in bytes (excluding framing).
pub type FirmataOther = {
  command: Int;
  length: Int;
}

/// One decoded Firmata/MIDI wire message.
///
/// `Version` and `Firmware` come from the board during the handshake.
/// `Digital` and `Analog` are input reports. `StringData` is a sysex debug
/// string. `ReportAnalog`, `ReportDigital`, `SetPinMode`, `SetDigitalPin`
/// and `SystemReset` are host-to-board frames decoded for completeness and
/// loopback tests. `Other` covers every well-framed message outside the
/// declared subset (unknown sysex id or MIDI realtime byte).
pub type FirmataMessage = enum {
  Version(v: FirmataVersion),
  Firmware(v: FirmataFirmware),
  Digital(v: FirmataDigital),
  Analog(v: FirmataAnalog),
  StringData(v: Str),
  ReportAnalog(v: FirmataReport),
  ReportDigital(v: FirmataReport),
  SetPinMode(v: FirmataPinMode),
  SetDigitalPin(v: FirmataPinValue),
  SystemReset,
  Other(v: FirmataOther),
}

/// Transport-agnostic protocol session.
///
/// `rx` holds received bytes not yet consumed; `out` holds host bytes not
/// yet drained. `ports` is the 16-port digital output shadow used by
/// `firmata_session_digital_write`. `version_received` and
/// `firmware_received` record the handshake. `rx_limit` bounds `rx` and is
/// public so a constrained transport can lower it. The caller owns the
/// transport: read bytes into `firmata_session_feed`, poll messages with
/// `firmata_session_poll`, and write `firmata_session_take_output` to the
/// device. No hardware or serial backend is required by this module.
pub type FirmataSession = {
  rx: Vec[UInt8];
  out: Vec[UInt8];
  ports: Vec[Int];
  rx_limit: Int;
  version_received: Bool;
  version_major: Int;
  version_minor: Int;
  firmware_received: Bool;
  firmware_name: Str;
}

// =========================================================================
// Internal helpers
// =========================================================================

fn _err(kind: Int, code: Int, message: Str) -> FirmataError {
  return FirmataError{ kind: kind; code: code; message: message };
}

fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

fn _flag(enabled: Bool) -> Int {
  if enabled {
    return 1;
  }
  return 0;
}

// Push a 7-bit group pair (value 0..16383) onto a byte vector.
fn _push14(out: &mut Vec[UInt8], value: Int) {
  out.push((value % 128) as UInt8);
  out.push(((value / 128) % 128) as UInt8);
}

// Fixed-length prefix result: 0 while the buffer is short, `n` once complete.
fn _fixed_len(data: &Vec[UInt8], n: Int) -> Result[Int, FirmataError] {
  if data.len() < n {
    return Ok(0);
  }
  return Ok(n);
}

// Index of the first data byte >= 0x80 in [from, to), or -1 when all data
// bytes are 7-bit. Used to reject a status byte embedded in a fixed frame.
fn _bad_data_index(data: &Vec[UInt8], from: Int, to: Int) -> Int {
  var i = from;
  while i < to {
    if _byte(data, i) >= 128 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Decode pairs of 7-bit bytes in [start, end) as 14-bit character codes.
// Each code point is encoded as UTF-8. A zero code point terminates the
// string (the C-string transport semantics of xiom.string.builder).
fn _decode_7bit_pairs(data: &Vec[UInt8], start: Int, end: Int) -> Result[Str, FirmataError] {
  let width = end - start;
  if width < 0 {
    return Err(_err(FIRMATA_ERR_BAD_STRING, width, "string: inverted payload range"));
  }
  if width % 2 != 0 {
    return Err(_err(FIRMATA_ERR_BAD_STRING, width, "string: odd number of 7-bit bytes"));
  }
  var sb = builder.sb_new();
  var i = start;
  var stopped = false;
  while i + 1 < end && !stopped {
    let lo = _byte(data, i);
    let hi = _byte(data, i + 1);
    if lo >= 128 || hi >= 128 {
      return Err(_err(FIRMATA_ERR_BAD_STRING, lo, "string: non-7-bit character group"));
    }
    let cp = lo + hi * 128;
    i = i + 2;
    if cp == 0 {
      stopped = true;
    } else {
      let enc = utf8.utf8_encode(cp);
      if !enc.is_ok {
        return Err(_err(FIRMATA_ERR_BAD_STRING, cp, "string: codepoint is not valid Unicode"));
      }
      let bytes: Vec[UInt8] = enc.value;
      var j = 0;
      while j < bytes.len() {
        builder.sb_push_byte(&mut sb, bytes[j]);
        j = j + 1;
      }
    }
  }
  return Ok(builder.sb_to_str(&sb));
}

// Copy [start, start+len) into a fresh byte vector.
fn _slice(data: &Vec[UInt8], start: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    out.push(data[start + i]);
    i = i + 1;
  }
  return out;
}

// Drop the first `n` bytes of `v` (used by the session after consuming a
// frame, and by the resync path after a malformed status byte).
fn _drop_front(v: &mut Vec[UInt8], n: Int) {
  if n <= 0 {
    return;
  }
  if n >= v.len() {
    v.clear();
    return;
  }
  var rest = Vec[UInt8].new();
  var i = n;
  while i < v.len() {
    rest.push(v[i]);
    i = i + 1;
  }
  v.clear();
  v.extend(&rest);
}

// =========================================================================
// Host encoders (pure)
// =========================================================================

/// Protocol-version query: `[0xF9]` (the board replies with a three-byte
/// version report).
pub fn firmata_encode_version_query() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(FIRMATA_REPORT_VERSION as UInt8);
  return out;
}

/// Firmware query: `[0xF0, 0x79, 0xF7]`. The board replies with a
/// REPORT_FIRMWARE sysex frame.
pub fn firmata_encode_firmware_query() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(FIRMATA_START_SYSEX as UInt8);
  out.push(FIRMATA_REPORT_FIRMWARE as UInt8);
  out.push(FIRMATA_END_SYSEX as UInt8);
  return out;
}

/// SET_PIN_MODE: `[0xF4, pin, mode]`. `pin` is 0..127 and `mode` is the raw
/// protocol mode byte (0..127; the named modes are FIRMATA_MODE_*).
pub fn firmata_encode_set_pin_mode(pin: Int, mode: Int) -> Result[Vec[UInt8], FirmataError] {
  if pin < 0 || pin > FIRMATA_MAX_PIN {
    return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, pin, "set_pin_mode: pin must be 0..127"));
  }
  if mode < 0 || mode > FIRMATA_MAX_7BIT {
    return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, mode, "set_pin_mode: mode must be 0..127"));
  }
  var out = Vec[UInt8].new();
  out.push(FIRMATA_SET_PIN_MODE as UInt8);
  out.push(pin as UInt8);
  out.push(mode as UInt8);
  return Ok(out);
}

/// SET_DIGITAL_PIN_VALUE (Firmata 2.5+): `[0xF5, pin, 0|1]`. This is the
/// pin-addressed digital write; the session's `firmata_session_digital_write`
/// uses the classic port message instead.
pub fn firmata_encode_digital_write(pin: Int, high: Bool) -> Result[Vec[UInt8], FirmataError] {
  if pin < 0 || pin > FIRMATA_MAX_PIN {
    return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, pin, "digital_write: pin must be 0..127"));
  }
  var out = Vec[UInt8].new();
  out.push(FIRMATA_SET_DIGITAL_PIN_VALUE as UInt8);
  out.push(pin as UInt8);
  out.push(_flag(high) as UInt8);
  return Ok(out);
}

/// DIGITAL_MESSAGE port write: `[0x90|port, mask lsb, mask msb]`.
/// `port` is 0..15 and `mask` is 0..16383 (bits 0..7 are the port's pins).
pub fn firmata_encode_digital_port_write(port: Int, mask: Int) -> Result[Vec[UInt8], FirmataError] {
  if port < 0 || port > FIRMATA_MAX_PORT {
    return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, port, "digital_port_write: port must be 0..15"));
  }
  if mask < 0 || mask > FIRMATA_MAX_14BIT {
    return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, mask, "digital_port_write: mask must be 0..16383"));
  }
  var out = Vec[UInt8].new();
  out.push((FIRMATA_DIGITAL_MESSAGE + port) as UInt8);
  _push14(&mut out, mask);
  return Ok(out);
}

/// ANALOG_MESSAGE PWM write: `[0xE0|pin, value lsb, value msb]`.
/// `pin` is 0..15 and `value` is 0..16383. Pins above 15 need the optional
/// EXTENDED_ANALOG sysex frame, which is out of scope (ROADMAP.md).
pub fn firmata_encode_pwm_write(pin: Int, value: Int) -> Result[Vec[UInt8], FirmataError] {
  if pin < 0 || pin > FIRMATA_MAX_ANALOG_CHANNEL {
    return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, pin, "pwm_write: pin must be 0..15"));
  }
  if value < 0 || value > FIRMATA_MAX_14BIT {
    return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, value, "pwm_write: value must be 0..16383"));
  }
  var out = Vec[UInt8].new();
  out.push((FIRMATA_ANALOG_MESSAGE + pin) as UInt8);
  _push14(&mut out, value);
  return Ok(out);
}

/// REPORT_ANALOG enable/disable: `[0xC0|channel, 0|1]`. `channel` is the
/// analog channel number (0..15), not the physical pin number.
pub fn firmata_encode_analog_report(channel: Int, enable: Bool) -> Result[Vec[UInt8], FirmataError] {
  if channel < 0 || channel > FIRMATA_MAX_ANALOG_CHANNEL {
    return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, channel, "analog_report: channel must be 0..15"));
  }
  var out = Vec[UInt8].new();
  out.push((FIRMATA_REPORT_ANALOG + channel) as UInt8);
  out.push(_flag(enable) as UInt8);
  return Ok(out);
}

/// REPORT_DIGITAL enable/disable: `[0xD0|port, 0|1]`. `port` is 0..15
/// (pins 8*port .. 8*port+7).
pub fn firmata_encode_digital_report(port: Int, enable: Bool) -> Result[Vec[UInt8], FirmataError] {
  if port < 0 || port > FIRMATA_MAX_PORT {
    return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, port, "digital_report: port must be 0..15"));
  }
  var out = Vec[UInt8].new();
  out.push((FIRMATA_REPORT_DIGITAL + port) as UInt8);
  out.push(_flag(enable) as UInt8);
  return Ok(out);
}

/// SYSTEM_RESET: `[0xFF]`.
pub fn firmata_encode_system_reset() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(FIRMATA_SYSTEM_RESET as UInt8);
  return out;
}

// =========================================================================
// Framing and decode
// =========================================================================

/// Length in bytes of the complete frame at the front of `data`.
///
/// Returns `Ok(0)` when more bytes are needed (including for an empty
/// buffer, a short fixed frame, or an unterminated sysex frame), `Ok(n)`
/// for a complete frame of `n` bytes, and an error for a framing violation:
/// `FIRMATA_ERR_BAD_STATUS` for a status byte outside the declared set,
/// `FIRMATA_ERR_BAD_SYSEX` when a status byte interrupts a sysex frame.
/// Recognized single-byte MIDI realtime statuses (0xF8/0xFA/0xFB/0xFC/0xFE)
/// are framed as one-byte messages and decoded as `Other`.
pub fn firmata_frame_len(data: &Vec[UInt8]) -> Result[Int, FirmataError] {
  if data.len() == 0 {
    return Ok(0);
  }
  let status = _byte(data, 0);
  if status < 128 {
    return Err(_err(FIRMATA_ERR_BAD_STATUS, status, "frame_len: status byte is below 0x80"));
  }
  if status == FIRMATA_START_SYSEX {
    var i = 1;
    while i < data.len() {
      let b = _byte(data, i);
      if b == FIRMATA_END_SYSEX {
        return Ok(i + 1);
      }
      if b >= 128 {
        return Err(_err(FIRMATA_ERR_BAD_SYSEX, b, "frame_len: sysex interrupted by a status byte"));
      }
      i = i + 1;
    }
    return Ok(0);
  }
  if status == FIRMATA_REPORT_VERSION {
    return _fixed_len(data, 3);
  }
  if status >= FIRMATA_DIGITAL_MESSAGE && status <= FIRMATA_DIGITAL_MESSAGE + 15 {
    return _fixed_len(data, 3);
  }
  if status >= FIRMATA_ANALOG_MESSAGE && status <= FIRMATA_ANALOG_MESSAGE + 15 {
    return _fixed_len(data, 3);
  }
  if status >= FIRMATA_REPORT_ANALOG && status <= FIRMATA_REPORT_ANALOG + 15 {
    return _fixed_len(data, 2);
  }
  if status >= FIRMATA_REPORT_DIGITAL && status <= FIRMATA_REPORT_DIGITAL + 15 {
    return _fixed_len(data, 2);
  }
  if status == FIRMATA_SET_PIN_MODE || status == FIRMATA_SET_DIGITAL_PIN_VALUE {
    return _fixed_len(data, 3);
  }
  if status == FIRMATA_SYSTEM_RESET {
    return Ok(1);
  }
  if status == 0xF8 || status == 0xFA || status == 0xFB || status == 0xFC || status == 0xFE {
    return Ok(1);
  }
  return Err(_err(FIRMATA_ERR_BAD_STATUS, status, "frame_len: unrecognized status byte"));
}

/// Decode exactly one complete frame. `data` must contain one whole frame
/// (its length must equal `firmata_frame_len`); trailing bytes are an
/// `FIRMATA_ERR_INVALID_ARG` rather than being silently ignored.
///
/// Errors: framing errors from `firmata_frame_len`; `FIRMATA_ERR_TRUNCATED`
/// for an incomplete frame; `FIRMATA_ERR_BAD_STATUS` when a status byte
/// appears inside a fixed frame; `FIRMATA_ERR_BAD_SYSEX` for a malformed
/// sysex frame; `FIRMATA_ERR_BAD_STRING` for a bad 2 x 7-bit string payload;
/// `FIRMATA_ERR_OUT_OF_RANGE` for a SET_DIGITAL_PIN_VALUE value other than
/// 0/1.
pub fn firmata_decode_frame(data: &Vec[UInt8]) -> Result[FirmataMessage, FirmataError] {
  let lr = firmata_frame_len(data);
  if !lr.is_ok {
    return Err(lr.error);
  }
  let n: Int = lr.value;
  if n == 0 {
    return Err(_err(FIRMATA_ERR_TRUNCATED, data.len(), "decode: incomplete frame"));
  }
  if data.len() != n {
    return Err(_err(FIRMATA_ERR_INVALID_ARG, data.len(), "decode: expected exactly one complete frame"));
  }
  let status = _byte(data, 0);
  if status == FIRMATA_START_SYSEX {
    let inner: Int = n - 2;
    if inner < 1 {
      return Err(_err(FIRMATA_ERR_BAD_SYSEX, 0, "decode: sysex frame has no command id"));
    }
    let id = _byte(data, 1);
    let payload_len: Int = n - 3;
    if id == FIRMATA_STRING_DATA {
      let dr = _decode_7bit_pairs(data, 2, n - 1);
      if !dr.is_ok {
        return Err(dr.error);
      }
      return Ok(StringData(dr.value));
    }
    if id == FIRMATA_REPORT_FIRMWARE {
      if payload_len == 0 {
        let other = FirmataOther{ command: id; length: 0 };
        return Ok(Other(other));
      }
      if payload_len < 2 {
        return Err(_err(FIRMATA_ERR_BAD_SYSEX, payload_len, "decode: firmware report has no version bytes"));
      }
      let major = _byte(data, 2);
      let minor = _byte(data, 3);
      let nr = _decode_7bit_pairs(data, 4, n - 1);
      if !nr.is_ok {
        return Err(nr.error);
      }
      let fw = FirmataFirmware{ major: major; minor: minor; name: nr.value };
      return Ok(Firmware(fw));
    }
    let other = FirmataOther{ command: id; length: payload_len };
    return Ok(Other(other));
  }
  let bad = _bad_data_index(data, 1, n);
  if bad >= 0 {
    return Err(_err(FIRMATA_ERR_BAD_STATUS, _byte(data, bad), "decode: status byte inside a fixed frame"));
  }
  if status == FIRMATA_REPORT_VERSION {
    let version = FirmataVersion{ major: _byte(data, 1); minor: _byte(data, 2) };
    return Ok(Version(version));
  }
  if status >= FIRMATA_DIGITAL_MESSAGE && status <= FIRMATA_DIGITAL_MESSAGE + 15 {
    let port: Int = status - FIRMATA_DIGITAL_MESSAGE;
    let mask: Int = _byte(data, 1) + _byte(data, 2) * 128;
    let digital = FirmataDigital{ port: port; mask: mask };
    return Ok(Digital(digital));
  }
  if status >= FIRMATA_ANALOG_MESSAGE && status <= FIRMATA_ANALOG_MESSAGE + 15 {
    let channel: Int = status - FIRMATA_ANALOG_MESSAGE;
    let value: Int = _byte(data, 1) + _byte(data, 2) * 128;
    let analog = FirmataAnalog{ channel: channel; value: value };
    return Ok(Analog(analog));
  }
  if status >= FIRMATA_REPORT_ANALOG && status <= FIRMATA_REPORT_ANALOG + 15 {
    let channel: Int = status - FIRMATA_REPORT_ANALOG;
    let report = FirmataReport{ channel: channel; enabled: _byte(data, 1) != 0 };
    return Ok(ReportAnalog(report));
  }
  if status >= FIRMATA_REPORT_DIGITAL && status <= FIRMATA_REPORT_DIGITAL + 15 {
    let port: Int = status - FIRMATA_REPORT_DIGITAL;
    let report = FirmataReport{ channel: port; enabled: _byte(data, 1) != 0 };
    return Ok(ReportDigital(report));
  }
  if status == FIRMATA_SET_PIN_MODE {
    let pm = FirmataPinMode{ pin: _byte(data, 1); mode: _byte(data, 2) };
    return Ok(SetPinMode(pm));
  }
  if status == FIRMATA_SET_DIGITAL_PIN_VALUE {
    let pin = _byte(data, 1);
    let value = _byte(data, 2);
    if value > 1 {
      return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, value, "decode: set_digital_pin value must be 0 or 1"));
    }
    let pv = FirmataPinValue{ pin: pin; value: value };
    return Ok(SetDigitalPin(pv));
  }
  if status == FIRMATA_SYSTEM_RESET {
    return Ok(SystemReset);
  }
  let other = FirmataOther{ command: status; length: 1 };
  return Ok(Other(other));
}

/// Decode a version report frame (`0xF9 major minor`). Any other well-formed
/// message type is `FIRMATA_ERR_UNSUPPORTED`.
pub fn firmata_decode_version_message(data: &Vec[UInt8]) -> Result[FirmataVersion, FirmataError] {
  let r = firmata_decode_frame(data);
  if !r.is_ok {
    return Err(r.error);
  }
  match r.value {
    Version(v) => { return Ok(v); }
    _ => { return Err(_err(FIRMATA_ERR_UNSUPPORTED, 0, "decode_version: frame is not a version report")); }
  }
}

/// Decode a REPORT_FIRMWARE sysex frame. Any other message type is
/// `FIRMATA_ERR_UNSUPPORTED`.
pub fn firmata_decode_firmware_message(data: &Vec<UInt8>) -> Result[FirmataFirmware, FirmataError] {
  let r = firmata_decode_frame(data);
  if !r.is_ok {
    return Err(r.error);
  }
  match r.value {
    Firmware(v) => { return Ok(v); }
    _ => { return Err(_err(FIRMATA_ERR_UNSUPPORTED, 0, "decode_firmware: frame is not a firmware report")); }
  }
}

/// Decode a DIGITAL_MESSAGE frame. Any other message type is
/// `FIRMATA_ERR_UNSUPPORTED`.
pub fn firmata_decode_digital_message(data: &Vec<UInt8>) -> Result[FirmataDigital, FirmataError] {
  let r = firmata_decode_frame(data);
  if !r.is_ok {
    return Err(r.error);
  }
  match r.value {
    Digital(v) => { return Ok(v); }
    _ => { return Err(_err(FIRMATA_ERR_UNSUPPORTED, 0, "decode_digital: frame is not a digital report")); }
  }
}

/// Decode an ANALOG_MESSAGE frame. Any other message type is
/// `FIRMATA_ERR_UNSUPPORTED`.
pub fn firmata_decode_analog_message(data: &Vec<UInt8>) -> Result[FirmataAnalog, FirmataError] {
  let r = firmata_decode_frame(data);
  if !r.is_ok {
    return Err(r.error);
  }
  match r.value {
    Analog(v) => { return Ok(v); }
    _ => { return Err(_err(FIRMATA_ERR_UNSUPPORTED, 0, "decode_analog: frame is not an analog report")); }
  }
}

/// Decode a STRING_DATA sysex frame. Any other message type is
/// `FIRMATA_ERR_UNSUPPORTED`.
pub fn firmata_decode_string_message(data: &Vec<UInt8>) -> Result[Str, FirmataError] {
  let r = firmata_decode_frame(data);
  if !r.is_ok {
    return Err(r.error);
  }
  match r.value {
    StringData(v) => { return Ok(v); }
    _ => { return Err(_err(FIRMATA_ERR_UNSUPPORTED, 0, "decode_string: frame is not a string report")); }
  }
}

/// Read one bit of a digital port mask. `mask` is 0..16383 and `bit` is
/// 0..13 (bits 0..7 are the defined pins; 8..13 are preserved group bits).
pub fn firmata_digital_mask_pin(mask: Int, bit: Int) -> Result[Bool, FirmataError] {
  if mask < 0 || mask > FIRMATA_MAX_14BIT {
    return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, mask, "digital_mask_pin: mask must be 0..16383"));
  }
  if bit < 0 || bit > 13 {
    return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, bit, "digital_mask_pin: bit must be 0..13"));
  }
  var scale = 1;
  var i = 0;
  while i < bit {
    scale = scale * 2;
    i = i + 1;
  }
  let set = (mask / scale) % 2;
  if set == 1 {
    return Ok(true);
  }
  return Ok(false);
}

/// Stable name of an error kind (`"INVALID_ARG"` .. `"BUFFER_FULL"`);
/// `"UNKNOWN"` for values outside the catalog.
pub fn firmata_error_name(kind: Int) -> Str {
  if kind == FIRMATA_ERR_INVALID_ARG { return "INVALID_ARG"; }
  if kind == FIRMATA_ERR_OUT_OF_RANGE { return "OUT_OF_RANGE"; }
  if kind == FIRMATA_ERR_TRUNCATED { return "TRUNCATED"; }
  if kind == FIRMATA_ERR_BAD_STATUS { return "BAD_STATUS"; }
  if kind == FIRMATA_ERR_BAD_SYSEX { return "BAD_SYSEX"; }
  if kind == FIRMATA_ERR_BAD_STRING { return "BAD_STRING"; }
  if kind == FIRMATA_ERR_UNSUPPORTED { return "UNSUPPORTED"; }
  if kind == FIRMATA_ERR_BUFFER_FULL { return "BUFFER_FULL"; }
  return "UNKNOWN";
}

/// Stable name of a pin mode byte (`"INPUT"` .. `"PULLUP"`); `"UNKNOWN"`
/// for values outside the named set (future modes stay numbers on the wire).
pub fn firmata_mode_name(mode: Int) -> Str {
  if mode == FIRMATA_MODE_INPUT { return "INPUT"; }
  if mode == FIRMATA_MODE_OUTPUT { return "OUTPUT"; }
  if mode == FIRMATA_MODE_ANALOG { return "ANALOG"; }
  if mode == FIRMATA_MODE_PWM { return "PWM"; }
  if mode == FIRMATA_MODE_SERVO { return "SERVO"; }
  if mode == FIRMATA_MODE_SHIFT { return "SHIFT"; }
  if mode == FIRMATA_MODE_I2C { return "I2C"; }
  if mode == FIRMATA_MODE_ONEWIRE { return "ONEWIRE"; }
  if mode == FIRMATA_MODE_STEPPER { return "STEPPER"; }
  if mode == FIRMATA_MODE_ENCODER { return "ENCODER"; }
  if mode == FIRMATA_MODE_SERIAL { return "SERIAL"; }
  if mode == FIRMATA_MODE_PULLUP { return "PULLUP"; }
  return "UNKNOWN";
}

// =========================================================================
// Transport-agnostic session
// =========================================================================

/// Create an empty session with a zeroed 16-port digital shadow and the
/// default receive-buffer limit (4096 bytes).
pub fn firmata_session_new() -> FirmataSession {
  var ports = Vec[Int].new();
  var i = 0;
  while i < FIRMATA_SESSION_PORTS {
    ports.push(0);
    i = i + 1;
  }
  return FirmataSession{
    rx: Vec[UInt8].new();
    out: Vec[UInt8].new();
    ports: ports;
    rx_limit: FIRMATA_RX_LIMIT_DEFAULT;
    version_received: false;
    version_major: 0;
    version_minor: 0;
    firmware_received: false;
    firmware_name: "";
  };
}

/// Clear all session state: receive buffer, output queue, digital shadow and
/// handshake flags. The configured `rx_limit` is preserved.
pub fn firmata_session_reset(s: &mut FirmataSession) {
  s.rx.clear();
  s.out.clear();
  s.ports.clear();
  var i = 0;
  while i < FIRMATA_SESSION_PORTS {
    s.ports.push(0);
    i = i + 1;
  }
  s.version_received = false;
  s.version_major = 0;
  s.version_minor = 0;
  s.firmware_received = false;
  s.firmware_name = "";
}

/// Inject received transport bytes into the session. Returns the number of
/// bytes accepted. An empty input is `Ok(0)`. When the append would exceed
/// `rx_limit`, nothing is appended and `FIRMATA_ERR_BUFFER_FULL` is
/// returned (the caller can poll and feed again).
pub fn firmata_session_feed(s: &mut FirmataSession, data: &Vec[UInt8]) -> Result[Int, FirmataError] {
  if data.len() == 0 {
    return Ok(0);
  }
  if s.rx.len() + data.len() > s.rx_limit {
    return Err(_err(FIRMATA_ERR_BUFFER_FULL, s.rx.len() + data.len(), "session: receive buffer limit exceeded"));
  }
  s.rx.extend(data);
  return Ok(data.len());
}

/// Number of received bytes not yet consumed by `firmata_session_poll`.
pub fn firmata_session_pending(s: &FirmataSession) -> Int {
  return s.rx.len();
}

/// Consume one frame from the receive buffer.
///
/// `Ok(Some(msg))` for a complete message, `Ok(None)` when more bytes are
/// needed, `Err` for a framing/decode violation. On error the offending
/// byte (framing) or the whole malformed frame (decode) is consumed, so a
/// repeated poll advances and the session resynchronizes on the next valid
/// status byte. A successfully decoded Version, Firmware or Digital message
/// updates the handshake flags or the digital port shadow.
pub fn firmata_session_poll(s: &mut FirmataSession) -> Result[Option[FirmataMessage], FirmataError] {
  if s.rx.len() == 0 {
    return Ok(None);
  }
  let rx: &Vec[UInt8] = &s.rx;
  let lr = firmata_frame_len(rx);
  if !lr.is_ok {
    _drop_front(&mut s.rx, 1);
    return Err(lr.error);
  }
  let n: Int = lr.value;
  if n == 0 {
    return Ok(None);
  }
  let frame = _slice(&s.rx, 0, n);
  _drop_front(&mut s.rx, n);
  let dr = firmata_decode_frame(&frame);
  if !dr.is_ok {
    return Err(dr.error);
  }
  let msg = dr.value;
  _session_observe(s, &msg);
  return Ok(Some(msg));
}

// Update session state from one decoded message.
fn _session_observe(s: &mut FirmataSession, msg: &FirmataMessage) {
  match msg {
    Version(v) => {
      s.version_received = true;
      s.version_major = v.major;
      s.version_minor = v.minor;
    }
    Firmware(f) => {
      s.firmware_received = true;
      s.firmware_name = f.name;
    }
    Digital(d) => {
      if d.port >= 0 && d.port < FIRMATA_SESSION_PORTS {
        s.ports.set(d.port, d.mask);
      }
    }
    _ => { }
  }
}

/// Queue the handshake queries: the version query followed by the firmware
/// query (`[0xF9, 0xF0, 0x79, 0xF7]`). The session is ready once both a
/// version report and a firmware report have been decoded.
pub fn firmata_session_begin_handshake(s: &mut FirmataSession) {
  let vq = firmata_encode_version_query();
  s.out.extend(&vq);
  let fq = firmata_encode_firmware_query();
  s.out.extend(&fq);
}

/// True when both handshake reports (version and firmware) have been seen.
pub fn firmata_session_is_ready(s: &FirmataSession) -> Bool {
  return s.version_received && s.firmware_received;
}

/// Queue a SET_PIN_MODE command. Invalid arguments queue nothing.
pub fn firmata_session_set_pin_mode(s: &mut FirmataSession, pin: Int, mode: Int) -> Result[Unit, FirmataError] {
  let e = firmata_encode_set_pin_mode(pin, mode);
  if !e.is_ok {
    return Err(e.error);
  }
  let bytes: Vec[UInt8] = e.value;
  s.out.extend(&bytes);
  return Ok(());
}

/// Queue a digital write using the classic port message. The session updates
/// its 16-port shadow and emits `[0x90|port, mask lsb, mask msb]`, so
/// consecutive writes to the same port coalesce into the current port state.
/// Pins 0..127 map to port `pin / 8`, bit `pin % 8`. Invalid pins queue
/// nothing.
pub fn firmata_session_digital_write(s: &mut FirmataSession, pin: Int, high: Bool) -> Result[Unit, FirmataError] {
  if pin < 0 || pin > FIRMATA_MAX_PIN {
    return Err(_err(FIRMATA_ERR_OUT_OF_RANGE, pin, "session_digital_write: pin must be 0..127"));
  }
  if s.ports.len() < FIRMATA_SESSION_PORTS {
    return Err(_err(FIRMATA_ERR_INVALID_ARG, s.ports.len(), "session_digital_write: port shadow is not initialized"));
  }
  let port: Int = pin / 8;
  let bit: Int = pin % 8;
  var scale = 1;
  var i = 0;
  while i < bit {
    scale = scale * 2;
    i = i + 1;
  }
  var mask: Int = s.ports[port];
  let set = (mask / scale) % 2;
  if high {
    if set == 0 {
      mask = mask + scale;
    }
  } else {
    if set == 1 {
      mask = mask - scale;
    }
  }
  let e = firmata_encode_digital_port_write(port, mask);
  if !e.is_ok {
    return Err(e.error);
  }
  let bytes: Vec[UInt8] = e.value;
  s.out.extend(&bytes);
  s.ports.set(port, mask);
  return Ok(());
}

/// Queue an ANALOG_MESSAGE PWM write. Invalid arguments queue nothing.
pub fn firmata_session_pwm_write(s: &mut FirmataSession, pin: Int, value: Int) -> Result[Unit, FirmataError] {
  let e = firmata_encode_pwm_write(pin, value);
  if !e.is_ok {
    return Err(e.error);
  }
  let bytes: Vec<UInt8> = e.value;
  s.out.extend(&bytes);
  return Ok(());
}

/// Queue a REPORT_ANALOG enable/disable. Invalid arguments queue nothing.
pub fn firmata_session_enable_analog_report(s: &mut FirmataSession, channel: Int, enable: Bool) -> Result[Unit, FirmataError] {
  let e = firmata_encode_analog_report(channel, enable);
  if !e.is_ok {
    return Err(e.error);
  }
  let bytes: Vec<UInt8> = e.value;
  s.out.extend(&bytes);
  return Ok(());
}

/// Queue a REPORT_DIGITAL enable/disable. Invalid arguments queue nothing.
pub fn firmata_session_enable_digital_report(s: &mut FirmataSession, port: Int, enable: Bool) -> Result[Unit, FirmataError] {
  let e = firmata_encode_digital_report(port, enable);
  if !e.is_ok {
    return Err(e.error);
  }
  let bytes: Vec<UInt8> = e.value;
  s.out.extend(&bytes);
  return Ok(());
}

/// Drain the queued host bytes. The session output buffer is left empty;
/// the caller writes the returned bytes to its transport (for example
/// `xiom.serial`'s `serial_write`; see README.md for the adapter sketch).
pub fn firmata_session_take_output(s: &mut FirmataSession) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.extend(&s.out);
  s.out.clear();
  return out;
}
