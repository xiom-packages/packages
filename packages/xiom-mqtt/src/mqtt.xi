// XIOM -- xiom.mqtt: MQTT 3.1.1 packet codec for a documented subset
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no session state) encoder/parser for the
// MQTT 3.1.1 control packets in scope: CONNECT, CONNACK, PUBLISH, PUBACK,
// SUBSCRIBE, SUBACK, PINGREQ and DISCONNECT, plus the fixed header (packet
// type 1..14, type flags and the remaining-length varint). Parsers consume
// a whole in-memory packet, copy the payload fields into fresh Vec[UInt8]
// values and reject malformed input with deterministic Err(Str) messages.
// All string fields (client id, will topic/message, username, password,
// topic and filters) are raw bytes: the codec performs no UTF-8 validation.
// See SPEC.md for the byte layout tables, the remaining-length rules, the
// error catalog and the documented limitations.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] widens with `(data[pos] as Int) &
//     0xFF` before it enters Int arithmetic or comparisons.
//   * struct fields that are Vec[UInt8] are bound to typed locals before
//     they are passed by reference (`&struct.field` misbehaves).
//   * flag extraction uses division/modulo only; no bit shifts are relied
//     on.
//   * Vec reads are bound to typed locals; no `==` is applied to a Str read
//     from a Vec (BUG 17).

module xiom.mqtt

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Decoded MQTT fixed header: the first byte split into `packet_type` (high
/// nibble) and `flags` (low nibble), the `remaining_length` varint value and
/// `header_len`, the total encoded header size (1 + 1..4 varint bytes). A
/// packet's body occupies exactly `remaining_length` bytes after
/// `header_len`.
pub type MqttFixedHeader = {
  packet_type: Int;
  flags: Int;
  remaining_length: Int;
  header_len: Int;
}

/// Decoded CONNECT packet. The presence flags select which payload fields
/// are on the wire; when a flag is false the matching field is empty.
/// `will_qos` is in 0..2 and is 0 when `will_present` is false.
pub type MqttConnect = {
  client_id: Vec[UInt8];
  keepalive: Int;
  clean_session: Bool;
  will_present: Bool;
  will_qos: Int;
  will_retain: Bool;
  will_topic: Vec[UInt8];
  will_message: Vec[UInt8];
  username_present: Bool;
  password_present: Bool;
  username: Vec[UInt8];
  password: Vec[UInt8];
}

/// Decoded CONNACK packet: `session_present` and a return code in 0..5
/// (0 = accepted; 1..5 = refusals, see SPEC.md).
pub type MqttConnack = {
  session_present: Bool;
  return_code: Int;
}

/// Decoded PUBLISH packet. `qos` is 0..2; `packet_id` is 0 for QoS 0 and
/// 1..65535 otherwise; `payload` is the raw application payload.
pub type MqttPublish = {
  dup: Bool;
  qos: Int;
  retain: Bool;
  topic: Vec[UInt8];
  packet_id: Int;
  payload: Vec[UInt8];
}

/// Decoded SUBSCRIBE packet: one topic filter and its requested QoS (0/1/2)
/// per entry, index-aligned (`filters[i]` pairs with `qoss[i]`).
pub type MqttSubscribe = {
  packet_id: Int;
  filters: Vec[Vec[UInt8]];
  qoss: Vec[Int];
}

/// Decoded SUBACK packet: one return code per requested subscription, each
/// 0, 1, 2 or 0x80 (128, failure).
pub type MqttSuback = {
  packet_id: Int;
  codes: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[MqttFixedHeader, Str].
fn _ok_fh(v: MqttFixedHeader) -> Result[MqttFixedHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[MqttFixedHeader, Str].
fn _err_fh(m: Str) -> Result[MqttFixedHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[MqttConnect, Str].
fn _ok_connect(v: MqttConnect) -> Result[MqttConnect, Str] {
  return Ok(v);
}

// Err(m) for Result[MqttConnect, Str].
fn _err_connect(m: Str) -> Result[MqttConnect, Str] {
  return Err(m);
}

// Ok(v) for Result[MqttConnack, Str].
fn _ok_connack(v: MqttConnack) -> Result[MqttConnack, Str] {
  return Ok(v);
}

// Err(m) for Result[MqttConnack, Str].
fn _err_connack(m: Str) -> Result[MqttConnack, Str] {
  return Err(m);
}

// Ok(v) for Result[MqttPublish, Str].
fn _ok_publish(v: MqttPublish) -> Result[MqttPublish, Str] {
  return Ok(v);
}

// Err(m) for Result[MqttPublish, Str].
fn _err_publish(m: Str) -> Result[MqttPublish, Str] {
  return Err(m);
}

// Ok(v) for Result[MqttSubscribe, Str].
fn _ok_subscribe(v: MqttSubscribe) -> Result[MqttSubscribe, Str] {
  return Ok(v);
}

// Err(m) for Result[MqttSubscribe, Str].
fn _err_subscribe(m: Str) -> Result[MqttSubscribe, Str] {
  return Err(m);
}

// Ok(v) for Result[MqttSuback, Str].
fn _ok_suback(v: MqttSuback) -> Result[MqttSuback, Str] {
  return Ok(v);
}

// Err(m) for Result[MqttSuback, Str].
fn _err_suback(m: Str) -> Result[MqttSuback, Str] {
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

// Ok(v) for Result[(Int, Int), Str].
fn _ok_pair(v: (Int, Int)) -> Result[(Int, Int), Str] {
  return Ok(v);
}

// Err(m) for Result[(Int, Int), Str].
fn _err_pair(m: Str) -> Result[(Int, Int), Str] {
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
//  Internal byte helpers
// --------------------------------------------------

// Largest value a 4-byte MQTT remaining-length varint can carry (2^28 - 1).
fn _max_remaining_length() -> Int {
  return 268435455;
}

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian u16 at [pos, pos+2); callers guarantee the bounds.
fn _read_u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Append `v` (0..65535) as two big-endian bytes.
fn _push_u16(out: &mut Vec[UInt8], v: Int) {
  out.push((v / 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Append every byte of `v` to `out`.
fn _push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Append an MQTT binary string: two big-endian length bytes then the bytes.
// The caller guarantees s.len() <= 65535.
fn _push_string(out: &mut Vec[UInt8], s: &Vec[UInt8]) {
  _push_u16(out, s.len());
  _push_vec(out, s);
}

// Read a 2-byte-length-prefixed binary string from `data` at `pos`, bounded
// by `end` (the end of the packet body). The bytes are appended to `out` and
// Ok(next) carries the offset just after the string.
// Err("mqtt: truncated packet") when the length prefix or the declared
// bytes do not fit [pos, end).
fn _read_string(data: &Vec[UInt8], pos: Int, end: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  if pos + 2 > end {
    return _err_int("mqtt: truncated packet");
  }
  let len = _read_u16(data, pos);
  let start = pos + 2;
  if start + len > end {
    return _err_int("mqtt: truncated packet");
  }
  var i = 0;
  while i < len {
    out.push(data[start + i]);
    i = i + 1;
  }
  return _ok_int(start + len);
}

// "" when `id` is a legal packet identifier (1..65535); otherwise the
// matching stable error text. Used to validate packet ids on encode.
fn _packet_id_err(id: Int) -> Str {
  if id == 0 {
    return "mqtt: packet id zero";
  }
  if id < 0 || id > 65535 {
    return "mqtt: packet id out of range";
  }
  return "";
}

// True when `s` contains a '#' (0x23) or '+' (0x2B) byte.
fn _has_wildcard(s: &Vec[UInt8]) -> Bool {
  var i = 0;
  while i < s.len() {
    let b = (s[i] as Int) & 0xFF;
    if b == 35 || b == 43 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Remaining-length varint
// --------------------------------------------------

/// Encoded byte count of the MQTT remaining-length varint for `n`: 1..4 for
/// `0..268435455`, and 0 when `n` is outside that range (there is no
/// encoding; callers can treat 0 as "invalid"). Complexity: O(bytes).
pub fn mqtt_remaining_length_size(n: Int) -> Int {
  if n < 0 {
    return 0;
  }
  if n > _max_remaining_length() {
    return 0;
  }
  var v = n;
  var count = 1;
  while v >= 128 {
    v = v / 128;
    count = count + 1;
  }
  return count;
}

/// Encode `n` as an MQTT remaining length: 7 payload bits per byte, least
/// significant group first, bit 7 is the continuation flag, at most four
/// bytes and at most 268435455. The encoding is minimal, so
/// `mqtt_remaining_length_size(n)` equals the returned length.
/// Err("mqtt: remaining length out of range") when `n` is negative or above
/// 268435455. Complexity: O(bytes).
pub fn mqtt_encode_remaining_length(n: Int) -> Result[Vec[UInt8], Str] {
  if n < 0 || n > _max_remaining_length() {
    return _err_bytes("mqtt: remaining length out of range");
  }
  var out = Vec[UInt8].new();
  var v = n;
  var more = true;
  while more {
    let d = v % 128;
    v = v / 128;
    if v > 0 {
      out.push((d + 128) as UInt8);
    } else {
      out.push(d as UInt8);
      more = false;
    }
  }
  return _ok_bytes(out);
}

/// Decode an MQTT remaining length at `off`. Returns Ok((value, next)) where
/// `next` is the offset just past the last consumed byte. At most four bytes
/// are consumed and the encoding must be canonical (minimal); the value is
/// in 0..268435455.
///
/// Err("mqtt: negative offset") for `off < 0`;
/// Err("mqtt: truncated packet") when the buffer ends before the
/// terminating byte;
/// Err("mqtt: bad remaining length") when a 5th byte would be required
/// (continuation bit set on the 4th byte) or the encoding is overlong
/// (non-minimal), e.g. `80 00` for 0.
/// Complexity: O(bytes).
pub fn mqtt_decode_remaining_length(data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str] {
  if off < 0 {
    return _err_pair("mqtt: negative offset");
  }
  let total = data.len();
  var value: Int = 0;
  var place: Int = 1;
  var pos = off;
  var i = 0;
  while i < 4 {
    if pos >= total {
      return _err_pair("mqtt: truncated packet");
    }
    let b = _byte(data, pos);
    value = value + (b % 128) * place;
    pos = pos + 1;
    if b / 128 == 0 {
      if i + 1 != mqtt_remaining_length_size(value) {
        return _err_pair("mqtt: bad remaining length");
      }
      return _ok_pair((value, pos));
    }
    place = place * 128;
    i = i + 1;
  }
  return _err_pair("mqtt: bad remaining length");
}

// --------------------------------------------------
//  Fixed header
// --------------------------------------------------

// True when `t` is a defined MQTT 3.1.1 control packet type (1..14).
fn _valid_type(t: Int) -> Bool {
  return t >= 1 && t <= 14;
}

// Required fixed-header flags for a packet type: 2 for PUBREL (6), SUBSCRIBE
// (8) and UNSUBSCRIBE (10); 0 for the other types. PUBLISH (3) carries
// DUP/QoS/RETAIN and is validated separately.
fn _required_flags(t: Int) -> Int {
  if t == 6 || t == 8 || t == 10 {
    return 2;
  }
  return 0;
}

// True when `flags` is a legal fixed-header flag nibble for packet type `t`
// (`t` already validated). For PUBLISH every nibble is accepted except
// QoS 3; the other types must match their reserved flag value exactly.
fn _flags_ok(t: Int, flags: Int) -> Bool {
  if flags < 0 || flags > 15 {
    return false;
  }
  if t == 3 {
    if (flags / 2) % 4 == 3 {
      return false;
    }
    return true;
  }
  return flags == _required_flags(t);
}

// Append a fixed header: the packet-type/flags byte plus the
// remaining-length varint. The caller guarantees a valid type/flags pair
// and remaining_length in 0..268435455.
fn _push_fixed(out: &mut Vec[UInt8], packet_type: Int, flags: Int, remaining_length: Int) {
  out.push((packet_type * 16 + flags) as UInt8);
  var v = remaining_length;
  var more = true;
  while more {
    let d = v % 128;
    v = v / 128;
    if v > 0 {
      out.push((d + 128) as UInt8);
    } else {
      out.push(d as UInt8);
      more = false;
    }
  }
}

/// Encode an MQTT fixed header for packet type 1..14 with the given flags
/// nibble and remaining length. PUBLISH (3) accepts DUP/QoS/RETAIN flags
/// but not QoS 3; PUBREL/SUBSCRIBE/UNSUBSCRIBE (6/8/10) require flags 2; all
/// other types require flags 0.
///
/// Err("mqtt: bad packet type") for type 0 or 15;
/// Err("mqtt: bad qos") for a PUBLISH with QoS bits 3;
/// Err("mqtt: bad fixed header flags") for any other illegal nibble;
/// Err("mqtt: remaining length out of range") when `remaining_length` is
/// negative or above 268435455.
/// Complexity: O(bytes).
pub fn mqtt_encode_fixed_header(packet_type: Int, flags: Int, remaining_length: Int) -> Result[Vec[UInt8], Str] {
  if !_valid_type(packet_type) {
    return _err_bytes("mqtt: bad packet type");
  }
  if !_flags_ok(packet_type, flags) {
    if packet_type == 3 && flags >= 0 && flags <= 15 {
      return _err_bytes("mqtt: bad qos");
    }
    return _err_bytes("mqtt: bad fixed header flags");
  }
  if remaining_length < 0 || remaining_length > _max_remaining_length() {
    return _err_bytes("mqtt: remaining length out of range");
  }
  var out = Vec[UInt8].new();
  _push_fixed(&mut out, packet_type, flags, remaining_length);
  return _ok_bytes(out);
}

/// Parse an MQTT fixed header from the start of `data`: the first byte split
/// into packet type (high nibble) and flags (low nibble), then the
/// remaining-length varint. Only the header is consumed; the body length is
/// reported in `remaining_length`.
///
/// Err("mqtt: truncated packet") when the type byte or the varint is
/// missing; Err("mqtt: bad packet type") for type 0 or 15;
/// Err("mqtt: bad fixed header flags") when the flag nibble is not the
/// reserved value for the type; Err("mqtt: bad qos") for a PUBLISH with
/// QoS 3; Err("mqtt: bad remaining length") for a malformed varint.
/// Complexity: O(bytes).
pub fn mqtt_parse_fixed_header(data: &Vec[UInt8]) -> Result[MqttFixedHeader, Str] {
  if data.len() < 1 {
    return _err_fh("mqtt: truncated packet");
  }
  let b0 = _byte(data, 0);
  let t = b0 / 16;
  let fl = b0 % 16;
  if !_valid_type(t) {
    return _err_fh("mqtt: bad packet type");
  }
  if !_flags_ok(t, fl) {
    if t == 3 {
      return _err_fh("mqtt: bad qos");
    }
    return _err_fh("mqtt: bad fixed header flags");
  }
  let rr = mqtt_decode_remaining_length(data, 1);
  if !rr.is_ok {
    return _err_fh(rr.error);
  }
  let pair = rr.value;
  let rem: Int = pair.0;
  let next: Int = pair.1;
  return _ok_fh(MqttFixedHeader{ packet_type: t; flags: fl; remaining_length: rem; header_len: next; });
}

// Shared envelope check for a typed parser: parse the fixed header, require
// packet type `want_type`, and require the whole packet to occupy exactly
// the buffer. Returns Ok((body_start, body_end)) with body_end always equal
// to data.len(). Errors: the fixed-header errors, "mqtt: bad packet type"
// for a mismatched type, "mqtt: truncated packet" when the body is short,
// "mqtt: trailing bytes" when the buffer extends past the packet.
fn _body_bounds(data: &Vec[UInt8], want_type: Int) -> Result[(Int, Int), Str] {
  let hr = mqtt_parse_fixed_header(data);
  if !hr.is_ok {
    return _err_pair(hr.error);
  }
  let h: MqttFixedHeader = hr.value;
  if h.packet_type != want_type {
    return _err_pair("mqtt: bad packet type");
  }
  let end = h.header_len + h.remaining_length;
  if data.len() < end {
    return _err_pair("mqtt: truncated packet");
  }
  if data.len() > end {
    return _err_pair("mqtt: trailing bytes");
  }
  return _ok_pair((h.header_len, end));
}

// --------------------------------------------------
//  Topic predicates
// --------------------------------------------------

/// True when `topic` is a valid PUBLISH topic name for this codec: 1..65535
/// bytes with no '#' (0x23) or '+' (0x2B) wildcard byte. Empty topics are
/// rejected (an MQTT topic name has at least one byte).
/// Complexity: O(topic length).
pub fn mqtt_topic_is_valid(topic: &Vec[UInt8]) -> Bool {
  if topic.len() == 0 || topic.len() > 65535 {
    return false;
  }
  if _has_wildcard(topic) {
    return false;
  }
  return true;
}

/// True when `filter` is a structurally valid SUBSCRIBE topic filter for
/// this codec: 1..65535 bytes with at most one '#' (0x23), allowed only as
/// the final byte. '+' (0x2B) may appear anywhere. This is a light
/// structural check, not full MQTT wildcard-level validation (see SPEC.md).
/// Complexity: O(filter length).
pub fn mqtt_topic_filter_is_valid(filter: &Vec[UInt8]) -> Bool {
  if filter.len() == 0 || filter.len() > 65535 {
    return false;
  }
  var i = 0;
  while i < filter.len() {
    let b = (filter[i] as Int) & 0xFF;
    if b == 35 {
      if i != filter.len() - 1 {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  CONNECT
// --------------------------------------------------

/// Encode a CONNECT packet (type 1, flags 0). The wire connect flags are
/// derived from the presence booleans; a non-empty `client_id`, `username`,
/// `password`, `will_topic` or `will_message` whose presence flag is false
/// is rejected rather than silently dropped.
///
/// Err("mqtt: bad keepalive") when `keepalive` is outside 0..65535;
/// Err("mqtt: bad qos") when a present will uses a QoS other than 0/1/2;
/// Err("mqtt: bad topic") when a present will has an empty topic;
/// Err("mqtt: bad connect flags") when the flags and payload disagree;
/// Err("mqtt: string too long") when any binary string exceeds 65535 bytes.
/// Complexity: O(packet size).
pub fn mqtt_encode_connect(c: &MqttConnect) -> Result[Vec[UInt8], Str] {
  if c.keepalive < 0 || c.keepalive > 65535 {
    return _err_bytes("mqtt: bad keepalive");
  }
  let cid: Vec[UInt8] = c.client_id;
  let wt: Vec[UInt8] = c.will_topic;
  let wm: Vec[UInt8] = c.will_message;
  let un: Vec[UInt8] = c.username;
  let pw: Vec[UInt8] = c.password;
  if cid.len() > 65535 || wt.len() > 65535 || wm.len() > 65535 || un.len() > 65535 || pw.len() > 65535 {
    return _err_bytes("mqtt: string too long");
  }
  if c.will_present {
    if c.will_qos < 0 || c.will_qos > 2 {
      return _err_bytes("mqtt: bad qos");
    }
    if wt.len() == 0 {
      return _err_bytes("mqtt: bad topic");
    }
  } else {
    if wt.len() != 0 || wm.len() != 0 {
      return _err_bytes("mqtt: bad connect flags");
    }
  }
  if !c.username_present && un.len() != 0 {
    return _err_bytes("mqtt: bad connect flags");
  }
  if !c.password_present && pw.len() != 0 {
    return _err_bytes("mqtt: bad connect flags");
  }
  var flags: Int = 0;
  if c.clean_session {
    flags = flags + 2;
  }
  if c.will_present {
    flags = flags + 4 + c.will_qos * 8;
  }
  if c.will_retain {
    flags = flags + 32;
  }
  if c.password_present {
    flags = flags + 64;
  }
  if c.username_present {
    flags = flags + 128;
  }
  var body = Vec[UInt8].new();
  body.push(0 as UInt8);
  body.push(4 as UInt8);
  body.push(77 as UInt8);
  body.push(81 as UInt8);
  body.push(84 as UInt8);
  body.push(84 as UInt8);
  body.push(4 as UInt8);
  body.push(flags as UInt8);
  _push_u16(&mut body, c.keepalive);
  _push_string(&mut body, &cid);
  if c.will_present {
    _push_string(&mut body, &wt);
    _push_string(&mut body, &wm);
  }
  if c.username_present {
    _push_string(&mut body, &un);
  }
  if c.password_present {
    _push_string(&mut body, &pw);
  }
  var out = Vec[UInt8].new();
  _push_fixed(&mut out, 1, 0, body.len());
  _push_vec(&mut out, &body);
  return _ok_bytes(out);
}

/// Parse a whole CONNECT packet (type 1). The protocol name must be the
/// four bytes "MQTT", the level must be 4, the reserved connect-flag bit
/// must be 0 and the payload must contain exactly the fields selected by
/// the connect flags; the body must occupy the whole buffer.
///
/// Errors: the fixed-header and envelope errors, plus
/// Err("mqtt: bad protocol name"), Err("mqtt: bad protocol level"),
/// Err("mqtt: bad connect flags"), Err("mqtt: bad qos") for will QoS 3 and
/// Err("mqtt: bad topic") for an empty will topic.
/// Complexity: O(packet size).
pub fn mqtt_parse_connect(data: &Vec[UInt8]) -> Result[MqttConnect, Str] {
  let br = _body_bounds(data, 1);
  if !br.is_ok {
    return _err_connect(br.error);
  }
  let bounds = br.value;
  let start: Int = bounds.0;
  let end: Int = bounds.1;
  var pos = start;
  if pos + 2 > end {
    return _err_connect("mqtt: truncated packet");
  }
  let name_len = _read_u16(data, pos);
  pos = pos + 2;
  if name_len != 4 {
    return _err_connect("mqtt: bad protocol name");
  }
  if pos + 4 > end {
    return _err_connect("mqtt: bad protocol name");
  }
  if _byte(data, pos) != 77 || _byte(data, pos + 1) != 81 || _byte(data, pos + 2) != 84 || _byte(data, pos + 3) != 84 {
    return _err_connect("mqtt: bad protocol name");
  }
  pos = pos + 4;
  if pos + 2 > end {
    return _err_connect("mqtt: truncated packet");
  }
  let level = _byte(data, pos);
  pos = pos + 1;
  if level != 4 {
    return _err_connect("mqtt: bad protocol level");
  }
  let flags = _byte(data, pos);
  pos = pos + 1;
  if flags % 2 != 0 {
    return _err_connect("mqtt: bad connect flags");
  }
  let clean = (flags / 2) % 2 == 1;
  let will = (flags / 4) % 2 == 1;
  let will_qos = (flags / 8) % 4;
  let will_retain = (flags / 32) % 2 == 1;
  let has_pass = (flags / 64) % 2 == 1;
  let has_user = (flags / 128) % 2 == 1;
  if will {
    if will_qos == 3 {
      return _err_connect("mqtt: bad qos");
    }
  } else {
    if will_qos != 0 || will_retain {
      return _err_connect("mqtt: bad connect flags");
    }
  }
  if pos + 2 > end {
    return _err_connect("mqtt: truncated packet");
  }
  let keepalive = _read_u16(data, pos);
  pos = pos + 2;
  var client_id = Vec[UInt8].new();
  let r1 = _read_string(data, pos, end, &mut client_id);
  if !r1.is_ok {
    return _err_connect(r1.error);
  }
  pos = r1.value;
  var will_topic = Vec[UInt8].new();
  var will_message = Vec[UInt8].new();
  if will {
    let r2 = _read_string(data, pos, end, &mut will_topic);
    if !r2.is_ok {
      return _err_connect(r2.error);
    }
    pos = r2.value;
    if will_topic.len() == 0 {
      return _err_connect("mqtt: bad topic");
    }
    let r3 = _read_string(data, pos, end, &mut will_message);
    if !r3.is_ok {
      return _err_connect(r3.error);
    }
    pos = r3.value;
  }
  var username = Vec[UInt8].new();
  var password = Vec[UInt8].new();
  if has_user {
    let r4 = _read_string(data, pos, end, &mut username);
    if !r4.is_ok {
      return _err_connect(r4.error);
    }
    pos = r4.value;
  }
  if has_pass {
    let r5 = _read_string(data, pos, end, &mut password);
    if !r5.is_ok {
      return _err_connect(r5.error);
    }
    pos = r5.value;
  }
  if pos != end {
    return _err_connect("mqtt: trailing bytes");
  }
  return _ok_connect(MqttConnect{
    client_id: client_id;
    keepalive: keepalive;
    clean_session: clean;
    will_present: will;
    will_qos: will_qos;
    will_retain: will_retain;
    will_topic: will_topic;
    will_message: will_message;
    username_present: has_user;
    password_present: has_pass;
    username: username;
    password: password;
  });
}

// --------------------------------------------------
//  CONNACK
// --------------------------------------------------

/// Encode a CONNACK packet (type 2, flags 0): one acknowledge-flags byte
/// (bit 0 = session present) and one return code byte.
/// Err("mqtt: bad return code") when `return_code` is outside 0..5;
/// Err("mqtt: bad connack flags") when `session_present` is true with a
/// non-zero return code (MQTT-3.2.2-4).
/// Complexity: O(1).
pub fn mqtt_encode_connack(session_present: Bool, return_code: Int) -> Result[Vec[UInt8], Str] {
  if return_code < 0 || return_code > 5 {
    return _err_bytes("mqtt: bad return code");
  }
  if return_code != 0 && session_present {
    return _err_bytes("mqtt: bad connack flags");
  }
  var out = Vec[UInt8].new();
  _push_fixed(&mut out, 2, 0, 2);
  if session_present {
    out.push(1 as UInt8);
  } else {
    out.push(0 as UInt8);
  }
  out.push(return_code as UInt8);
  return _ok_bytes(out);
}

/// Parse a whole CONNACK packet (type 2). The acknowledge flags may only
/// carry bit 0 (session present), the return code must be 0..5 and a
/// non-zero return code must have session present clear (MQTT-3.2.2-4).
/// Err("mqtt: bad payload") when the body is not exactly two bytes.
/// Complexity: O(1).
pub fn mqtt_parse_connack(data: &Vec<UInt8>) -> Result[MqttConnack, Str] {
  let br = _body_bounds(data, 2);
  if !br.is_ok {
    return _err_connack(br.error);
  }
  let bounds = br.value;
  let start: Int = bounds.0;
  let end: Int = bounds.1;
  if end - start != 2 {
    return _err_connack("mqtt: bad payload");
  }
  let ack_flags = _byte(data, start);
  if ack_flags > 1 {
    return _err_connack("mqtt: bad connack flags");
  }
  let rc = _byte(data, start + 1);
  if rc > 5 {
    return _err_connack("mqtt: bad return code");
  }
  let sp = ack_flags == 1;
  if rc != 0 && sp {
    return _err_connack("mqtt: bad connack flags");
  }
  return _ok_connack(MqttConnack{ session_present: sp; return_code: rc; });
}

// --------------------------------------------------
//  PUBLISH / PUBACK
// --------------------------------------------------

/// Encode a PUBLISH packet (type 3). The fixed-header flags carry DUP, QoS
/// and RETAIN; the variable header is the topic name followed by a packet
/// identifier when `qos > 0`, then the payload bytes verbatim.
///
/// Err("mqtt: bad qos") when `qos` is outside 0..2;
/// Err("mqtt: bad topic") when `topic` is empty or contains a wildcard;
/// Err("mqtt: string too long") when `topic` exceeds 65535 bytes;
/// Err("mqtt: packet id zero") / Err("mqtt: packet id out of range") when
/// `qos > 0` and `packet_id` is not 1..65535;
/// Err("mqtt: unexpected packet id") when `qos == 0` and `packet_id != 0`.
/// Complexity: O(packet size).
pub fn mqtt_encode_publish(topic: &Vec[UInt8], payload: &Vec[UInt8], qos: Int, retain: Bool, dup: Bool, packet_id: Int) -> Result[Vec[UInt8], Str] {
  if qos < 0 || qos > 2 {
    return _err_bytes("mqtt: bad qos");
  }
  if topic.len() > 65535 {
    return _err_bytes("mqtt: string too long");
  }
  if !mqtt_topic_is_valid(topic) {
    return _err_bytes("mqtt: bad topic");
  }
  if qos == 0 {
    if packet_id != 0 {
      return _err_bytes("mqtt: unexpected packet id");
    }
  } else {
    let e = _packet_id_err(packet_id);
    if e.len() > 0 {
      return _err_bytes(e);
    }
  }
  var flags: Int = 0;
  if dup {
    flags = flags + 8;
  }
  flags = flags + qos * 2;
  if retain {
    flags = flags + 1;
  }
  var body = Vec[UInt8].new();
  _push_string(&mut body, topic);
  if qos > 0 {
    _push_u16(&mut body, packet_id);
  }
  _push_vec(&mut body, payload);
  var out = Vec[UInt8].new();
  _push_fixed(&mut out, 3, flags, body.len());
  _push_vec(&mut out, &body);
  return _ok_bytes(out);
}

/// Parse a whole PUBLISH packet (type 3): DUP/QoS/RETAIN from the fixed
/// header, the topic name, the packet identifier when QoS > 0 (0 otherwise)
/// and the remaining bytes as the payload.
///
/// Err("mqtt: bad qos") for QoS 3 (fixed header);
/// Err("mqtt: bad topic") for an empty topic or a topic containing '+'/'#';
/// Err("mqtt: packet id zero") for a QoS > 0 packet whose identifier is 0.
/// Complexity: O(packet size).
pub fn mqtt_parse_publish(data: &Vec<UInt8>) -> Result[MqttPublish, Str] {
  let hr = mqtt_parse_fixed_header(data);
  if !hr.is_ok {
    return _err_publish(hr.error);
  }
  let h: MqttFixedHeader = hr.value;
  if h.packet_type != 3 {
    return _err_publish("mqtt: bad packet type");
  }
  let end = h.header_len + h.remaining_length;
  if data.len() < end {
    return _err_publish("mqtt: truncated packet");
  }
  if data.len() > end {
    return _err_publish("mqtt: trailing bytes");
  }
  let dup = (h.flags / 8) % 2 == 1;
  let qos = (h.flags / 2) % 4;
  let retain = h.flags % 2 == 1;
  var pos = h.header_len;
  var topic = Vec[UInt8].new();
  let r1 = _read_string(data, pos, end, &mut topic);
  if !r1.is_ok {
    return _err_publish(r1.error);
  }
  pos = r1.value;
  if topic.len() == 0 {
    return _err_publish("mqtt: bad topic");
  }
  if _has_wildcard(&topic) {
    return _err_publish("mqtt: bad topic");
  }
  var pid: Int = 0;
  if qos > 0 {
    if pos + 2 > end {
      return _err_publish("mqtt: truncated packet");
    }
    pid = _read_u16(data, pos);
    pos = pos + 2;
    if pid == 0 {
      return _err_publish("mqtt: packet id zero");
    }
  }
  var payload = Vec[UInt8].new();
  while pos < end {
    payload.push(data[pos]);
    pos = pos + 1;
  }
  return _ok_publish(MqttPublish{ dup: dup; qos: qos; retain: retain; topic: topic; packet_id: pid; payload: payload; });
}

/// Encode a PUBACK packet (type 4, flags 0): the two-byte packet identifier
/// of the PUBLISH being acknowledged.
/// Err("mqtt: packet id zero") / Err("mqtt: packet id out of range") when
/// `packet_id` is not 1..65535.
/// Complexity: O(1).
pub fn mqtt_encode_puback(packet_id: Int) -> Result[Vec[UInt8], Str] {
  let e = _packet_id_err(packet_id);
  if e.len() > 0 {
    return _err_bytes(e);
  }
  var out = Vec[UInt8].new();
  _push_fixed(&mut out, 4, 0, 2);
  _push_u16(&mut out, packet_id);
  return _ok_bytes(out);
}

/// Parse a whole PUBACK packet (type 4) and return its packet identifier.
/// Err("mqtt: bad payload") when the body is not exactly two bytes;
/// Err("mqtt: packet id zero") when the identifier is 0.
/// Complexity: O(1).
pub fn mqtt_parse_puback(data: &Vec[UInt8]) -> Result[Int, Str] {
  let br = _body_bounds(data, 4);
  if !br.is_ok {
    return _err_int(br.error);
  }
  let bounds = br.value;
  let start: Int = bounds.0;
  let end: Int = bounds.1;
  if end - start != 2 {
    return _err_int("mqtt: bad payload");
  }
  let pid = _read_u16(data, start);
  if pid == 0 {
    return _err_int("mqtt: packet id zero");
  }
  return _ok_int(pid);
}

// --------------------------------------------------
//  SUBSCRIBE / SUBACK
// --------------------------------------------------

/// Encode a SUBSCRIBE packet (type 8, flags 2): the packet identifier
/// followed by one (topic filter, requested QoS) entry per subscription.
/// The two vectors are index-aligned and must have the same non-zero
/// length.
///
/// Err("mqtt: packet id zero") / Err("mqtt: packet id out of range") for an
/// invalid identifier;
/// Err("mqtt: filters/qos length mismatch") when the vectors differ in
/// length; Err("mqtt: bad payload") when there are no filters;
/// Err("mqtt: bad topic filter") for an invalid filter;
/// Err("mqtt: bad qos") for a requested QoS outside 0..2.
/// Complexity: O(packet size).
pub fn mqtt_encode_subscribe(packet_id: Int, filters: &Vec[Vec[UInt8]], qoss: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  let e = _packet_id_err(packet_id);
  if e.len() > 0 {
    return _err_bytes(e);
  }
  if filters.len() != qoss.len() {
    return _err_bytes("mqtt: filters/qos length mismatch");
  }
  if filters.len() == 0 {
    return _err_bytes("mqtt: bad payload");
  }
  var body = Vec[UInt8].new();
  _push_u16(&mut body, packet_id);
  var i = 0;
  while i < filters.len() {
    let f: Vec[UInt8] = filters[i];
    let q: Int = qoss[i];
    if !mqtt_topic_filter_is_valid(&f) {
      return _err_bytes("mqtt: bad topic filter");
    }
    if q < 0 || q > 2 {
      return _err_bytes("mqtt: bad qos");
    }
    _push_string(&mut body, &f);
    body.push(q as UInt8);
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _push_fixed(&mut out, 8, 2, body.len());
  _push_vec(&mut out, &body);
  return _ok_bytes(out);
}

/// Parse a whole SUBSCRIBE packet (type 8): the packet identifier followed
/// by one or more (topic filter, requested QoS) entries that must consume
/// the whole body.
///
/// Err("mqtt: packet id zero") for identifier 0;
/// Err("mqtt: bad topic filter") for an invalid filter;
/// Err("mqtt: bad qos") for a requested QoS outside 0..2;
/// Err("mqtt: bad payload") when there are no filter entries.
/// Complexity: O(packet size).
pub fn mqtt_parse_subscribe(data: &Vec[UInt8]) -> Result[MqttSubscribe, Str] {
  let br = _body_bounds(data, 8);
  if !br.is_ok {
    return _err_subscribe(br.error);
  }
  let bounds = br.value;
  let start: Int = bounds.0;
  let end: Int = bounds.1;
  var pos = start;
  if pos + 2 > end {
    return _err_subscribe("mqtt: truncated packet");
  }
  let pid = _read_u16(data, pos);
  pos = pos + 2;
  if pid == 0 {
    return _err_subscribe("mqtt: packet id zero");
  }
  var filters = Vec[Vec[UInt8]].new();
  var qoss = Vec[Int].new();
  while pos < end {
    var f = Vec[UInt8].new();
    let r1 = _read_string(data, pos, end, &mut f);
    if !r1.is_ok {
      return _err_subscribe(r1.error);
    }
    pos = r1.value;
    if !mqtt_topic_filter_is_valid(&f) {
      return _err_subscribe("mqtt: bad topic filter");
    }
    if pos + 1 > end {
      return _err_subscribe("mqtt: truncated packet");
    }
    let q = _byte(data, pos);
    pos = pos + 1;
    if q > 2 {
      return _err_subscribe("mqtt: bad qos");
    }
    filters.push(f);
    qoss.push(q);
  }
  if filters.len() == 0 {
    return _err_subscribe("mqtt: bad payload");
  }
  return _ok_subscribe(MqttSubscribe{ packet_id: pid; filters: filters; qoss: qoss; });
}

/// Encode a SUBACK packet (type 9, flags 0): the SUBSCRIBE packet
/// identifier followed by one return code per requested subscription. Codes
/// are 0 (QoS 0 granted), 1 (QoS 1 granted), 2 (QoS 2 granted) or 128
/// (0x80, failure).
///
/// Err("mqtt: packet id zero") / Err("mqtt: packet id out of range") for an
/// invalid identifier; Err("mqtt: bad payload") when there are no codes;
/// Err("mqtt: bad suback code") for a code outside 0/1/2/128.
/// Complexity: O(packet size).
pub fn mqtt_encode_suback(packet_id: Int, codes: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  let e = _packet_id_err(packet_id);
  if e.len() > 0 {
    return _err_bytes(e);
  }
  if codes.len() == 0 {
    return _err_bytes("mqtt: bad payload");
  }
  var body = Vec[UInt8].new();
  _push_u16(&mut body, packet_id);
  var i = 0;
  while i < codes.len() {
    let c: Int = codes[i];
    if c != 0 && c != 1 && c != 2 && c != 128 {
      return _err_bytes("mqtt: bad suback code");
    }
    body.push(c as UInt8);
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _push_fixed(&mut out, 9, 0, body.len());
  _push_vec(&mut out, &body);
  return _ok_bytes(out);
}

/// Parse a whole SUBACK packet (type 9): the SUBSCRIBE packet identifier
/// followed by one or more return codes, each 0, 1, 2 or 0x80 (128).
///
/// Err("mqtt: packet id zero") for identifier 0;
/// Err("mqtt: bad suback code") for a code outside 0/1/2/128;
/// Err("mqtt: bad payload") when there are no return codes.
/// Complexity: O(packet size).
pub fn mqtt_parse_suback(data: &Vec[UInt8]) -> Result[MqttSuback, Str] {
  let br = _body_bounds(data, 9);
  if !br.is_ok {
    return _err_suback(br.error);
  }
  let bounds = br.value;
  let start: Int = bounds.0;
  let end: Int = bounds.1;
  var pos = start;
  if pos + 2 > end {
    return _err_suback("mqtt: truncated packet");
  }
  let pid = _read_u16(data, pos);
  pos = pos + 2;
  if pid == 0 {
    return _err_suback("mqtt: packet id zero");
  }
  var codes = Vec[Int].new();
  while pos < end {
    let c = _byte(data, pos);
    pos = pos + 1;
    if c != 0 && c != 1 && c != 2 && c != 128 {
      return _err_suback("mqtt: bad suback code");
    }
    codes.push(c);
  }
  if codes.len() == 0 {
    return _err_suback("mqtt: bad payload");
  }
  return _ok_suback(MqttSuback{ packet_id: pid; codes: codes; });
}

// --------------------------------------------------
//  PINGREQ / DISCONNECT
// --------------------------------------------------

/// Encode a PINGREQ packet: type 12, flags 0, remaining length 0 (`C0 00`).
/// Complexity: O(1).
pub fn mqtt_encode_pingreq() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(192 as UInt8);
  out.push(0 as UInt8);
  return out;
}

/// Parse a whole PINGREQ packet (type 12, flags 0, empty body).
/// Errors: the fixed-header and envelope errors, "mqtt: bad packet type"
/// for any other type, and "mqtt: bad payload" when the body is not empty.
/// Complexity: O(1).
pub fn mqtt_parse_pingreq(data: &Vec[UInt8]) -> Result[Unit, Str] {
  let br = _body_bounds(data, 12);
  if !br.is_ok {
    return _err_unit(br.error);
  }
  let bounds = br.value;
  let start: Int = bounds.0;
  let end: Int = bounds.1;
  if end - start != 0 {
    return _err_unit("mqtt: bad payload");
  }
  return _ok_unit();
}

/// Encode a DISCONNECT packet: type 14, flags 0, remaining length 0
/// (`E0 00`). Complexity: O(1).
pub fn mqtt_encode_disconnect() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(224 as UInt8);
  out.push(0 as UInt8);
  return out;
}

/// Parse a whole DISCONNECT packet (type 14, flags 0, empty body).
/// Errors: the fixed-header and envelope errors, "mqtt: bad packet type"
/// for any other type, and "mqtt: bad payload" when the body is not empty.
/// Complexity: O(1).
pub fn mqtt_parse_disconnect(data: &Vec<UInt8>) -> Result[Unit, Str] {
  let br = _body_bounds(data, 14);
  if !br.is_ok {
    return _err_unit(br.error);
  }
  let bounds = br.value;
  let start: Int = bounds.0;
  let end: Int = bounds.1;
  if end - start != 0 {
    return _err_unit("mqtt: bad payload");
  }
  return _ok_unit();
}
  return _ok_unit();
}
