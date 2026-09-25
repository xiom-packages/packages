// XIOM -- xiom.stun: RFC 5389 STUN message codec (documented subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI) codec for the wire format of Session Traversal
// Utilities for NAT (STUN), RFC 5389, restricted to the documented subset:
//
//   * one 20-byte header: 14-bit message type (12-bit method plus 2-bit
//     class, bit-packed as in RFC 5389 section 6), 16-bit declared message
//     length, the magic cookie 0x2112A442 and a 96-bit transaction ID;
//   * attribute TLVs (16-bit type, 16-bit length, value) padded to a
//     4-byte boundary; padding bytes may carry any value on the wire and
//     are skipped on decode, zeroes are written on build;
//   * MAPPED-ADDRESS (0x0001), USERNAME (0x0006), ERROR-CODE (0x0009),
//     XOR-MAPPED-ADDRESS (0x0020) and SOFTWARE (0x8022) get dedicated
//     helpers; every other attribute is preserved as a raw TLV through
//     stun_attr_type / stun_attr_value / stun_build, so MESSAGE-INTEGRITY
//     and FINGERPRINT pass through as opaque bytes and are never verified.
//
// XOR rules: the port is XORed with the high 16 bits of the magic cookie
// (0x2112); an IPv4 address is XORed with the 32-bit cookie; an IPv6
// address is XORed with the 128-bit (cookie || transaction ID) mask.
//
// Non-goals (see SPEC.md): sockets and transport, TURN, RFC 3489 legacy
// messages without the magic cookie, MESSAGE-INTEGRITY / FINGERPRINT
// cryptography, the full method registry, and streaming parsing.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType] and
//     no struct fields of struct type -- StunMessage and StunAddress are
//     deliberately flat.
//   * Ok/Err are constructed only in the tiny leaf helpers below
//     (constructing Results directly inside larger functions
//     miscompiles).
//   * All integer packing/unpacking is arithmetic (modulo/division); no
//     bitwise operator is used at all, and _xor_byte rebuilds each byte
//     from its bits so no operand carries a high bit into a mask.
//   * Every byte read from a Vec[UInt8] is widened with
//     `(b as Int) & 0xFF`; a `&struct.field` reference is never passed as
//     a `&Vec[UInt8]` parameter (bind a local first).
//   * Vec[Int] element reads are bound to typed locals before use, and
//     Str values are never compared with `==` (BUG 17 discipline).

module xiom.stun

use xiom.string;

// --------------------------------------------------
//  Protocol constants
// --------------------------------------------------

/// The fixed magic cookie 0x2112A442 required by RFC 5389 (554869826).
pub const STUN_MAGIC_COOKIE: Int = 554869826;

/// Size of the STUN message header in bytes.
pub const STUN_HEADER_SIZE: Int = 20;

/// Size of an attribute header (type + length) in bytes.
pub const STUN_ATTR_HEADER_SIZE: Int = 4;

/// Message class 0b00: request.
pub const STUN_CLASS_REQUEST: Int = 0;

/// Message class 0b01: indication.
pub const STUN_CLASS_INDICATION: Int = 1;

/// Message class 0b10: success response.
pub const STUN_CLASS_SUCCESS: Int = 2;

/// Message class 0b11: error response.
pub const STUN_CLASS_ERROR: Int = 3;

/// The only method named by this package: Binding (0x001).
pub const STUN_METHOD_BINDING: Int = 1;

/// MAPPED-ADDRESS attribute type (0x0001).
pub const STUN_ATTR_MAPPED_ADDRESS: Int = 1;

/// USERNAME attribute type (0x0006).
pub const STUN_ATTR_USERNAME: Int = 6;

/// ERROR-CODE attribute type (0x0009).
pub const STUN_ATTR_ERROR_CODE: Int = 9;

/// XOR-MAPPED-ADDRESS attribute type (0x0020).
pub const STUN_ATTR_XOR_MAPPED_ADDRESS: Int = 32;

/// SOFTWARE attribute type (0x8022).
pub const STUN_ATTR_SOFTWARE: Int = 32802;

/// Address family value for IPv4 (4-byte addresses).
pub const STUN_FAMILY_IPV4: Int = 1;

/// Address family value for IPv6 (16-byte addresses).
pub const STUN_FAMILY_IPV6: Int = 2;

// The magic cookie bytes, used by the XOR address codec.
const _COOKIE_B0: Int = 33;   // 0x21
const _COOKIE_B1: Int = 18;   // 0x12
const _COOKIE_B2: Int = 164;  // 0xA4
const _COOKIE_B3: Int = 66;   // 0x42

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed STUN message index.
///
/// `msg_type` is the raw 14-bit type; `method` and `msg_class` are its
/// decoded fields. `message_length` is the declared attribute byte count,
/// `magic_cookie` is the 32-bit cookie read from the wire (always
/// STUN_MAGIC_COOKIE on a successful parse) and `transaction_id` holds the
/// 12 transaction ID bytes. The three attribute vectors are parallel, one
/// entry per attribute in wire order: type codes, absolute offsets of the
/// first value byte in the source buffer, and unpadded value lengths.
/// Fields are implementation details; callers should go through the free
/// functions below.
pub type StunMessage = {
  msg_type: Int;
  method: Int;
  msg_class: Int;
  message_length: Int;
  magic_cookie: Int;
  transaction_id: Vec[UInt8];
  attr_types: Vec[Int];
  value_offsets: Vec[Int];
  value_lengths: Vec[Int];
}

/// A decoded address attribute (MAPPED-ADDRESS or XOR-MAPPED-ADDRESS).
/// `family` is STUN_FAMILY_IPV4 or STUN_FAMILY_IPV6; `address` holds 4 or
/// 16 bytes; `port` is the decoded port in 0..65535 (un-XORed when it came
/// from XOR-MAPPED-ADDRESS).
pub type StunAddress = {
  family: Int;
  port: Int;
  address: Vec[UInt8];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[StunMessage, Str].
fn _ok_msg(v: StunMessage) -> Result[StunMessage, Str] {
  return Ok(v);
}

// Err(m) for Result[StunMessage, Str].
fn _err_msg(m: Str) -> Result[StunMessage, Str] {
  return Err(m);
}

// Ok(v) for Result[StunAddress, Str].
fn _ok_addr(v: StunAddress) -> Result[StunAddress, Str] {
  return Ok(v);
}

// Err(m) for Result[StunAddress, Str].
fn _err_addr(m: Str) -> Result[StunAddress, Str] {
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

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
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
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned 16-bit big-endian integer at [pos, pos+2); the caller
// guarantees both bytes are in bounds.
fn _u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Unsigned 32-bit big-endian integer at [pos, pos+4) returned in an Int;
// the caller guarantees the four bytes are in bounds.
fn _u32(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  let b2: Int = _byte(data, pos + 2);
  let b3: Int = _byte(data, pos + 3);
  return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
}

// Byte `shift_bytes` of `v` (0 = least significant byte), arithmetic
// only: `& 0xFF` on values with bit 31 set miscompiles in v0.61.3 and this
// form is exact for the cookie constant.
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

// Append the bytes of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// XOR of two byte values (each 0..255), rebuilt bit by bit so that no
// bitwise operator is used at all (see the module header).
fn _xor_byte(a: Int, b: Int) -> Int {
  var out = 0;
  var place = 1;
  var x = a;
  var y = b;
  var i = 0;
  while i < 8 {
    if x % 2 != y % 2 {
      out = out + place;
    }
    x = x / 2;
    y = y / 2;
    place = place * 2;
    i = i + 1;
  }
  return out;
}

// Byte `i` of the XOR mask: the magic cookie for i in 0..3, transaction ID
// bytes after that (IPv6 only). The caller guarantees `tid.len() == 12`
// whenever i >= 4.
fn _mask_byte(i: Int, tid: &Vec[UInt8]) -> Int {
  if i == 0 { return _COOKIE_B0; }
  if i == 1 { return _COOKIE_B1; }
  if i == 2 { return _COOKIE_B2; }
  if i == 3 { return _COOKIE_B3; }
  return (tid[i - 4] as Int) & 0xFF;
}

// Number of address bytes for a family: 4 for IPv4, 16 otherwise. Callers
// validate the family first.
fn _address_bytes(family: Int) -> Int {
  if family == STUN_FAMILY_IPV4 {
    return 4;
  }
  return 16;
}

// UTF-8 bytes of a Str (one byte per string byte; no re-encoding).
fn _str_bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// Decode an address attribute value of 8 (IPv4) or 20 (IPv6) bytes. When
// `xor` is true the port and address bytes are un-XORed with the cookie /
// transaction ID mask; `tid` must then hold exactly 12 bytes. The fixed
// first value byte is ignored on decode (RFC 5389 says it is ignored).
fn _decode_address(v: &Vec[UInt8], xor: Bool, tid: &Vec[UInt8]) -> Result[StunAddress, Str] {
  if v.len() < 4 {
    return _err_addr("stun: truncated address");
  }
  let family: Int = (v[1] as Int) & 0xFF;
  if family != STUN_FAMILY_IPV4 && family != STUN_FAMILY_IPV6 {
    return _err_addr("stun: bad address family");
  }
  if xor && tid.len() != 12 {
    return _err_addr("stun: bad transaction id");
  }
  let need = 4 + _address_bytes(family);
  if v.len() != need {
    return _err_addr("stun: bad address length");
  }
  var port = ((v[2] as Int) & 0xFF) * 256 + ((v[3] as Int) & 0xFF);
  var addr = Vec[UInt8].new();
  var i = 0;
  var pos = 4;
  while pos < v.len() {
    let b: Int = (v[pos] as Int) & 0xFF;
    if xor {
      let mask: Int = _mask_byte(i, tid);
      addr.push(_xor_byte(b, mask) as UInt8);
    } else {
      addr.push(v[pos]);
    }
    i = i + 1;
    pos = pos + 1;
  }
  if xor {
    port = _xor_byte(port / 256, _COOKIE_B0) * 256 + _xor_byte(port % 256, _COOKIE_B1);
  }
  return _ok_addr(StunAddress{ family: family; port: port; address: addr; });
}

// --------------------------------------------------
//  Type / name helpers
// --------------------------------------------------

/// Encoded length of an attribute value of `n` bytes after 4-byte padding:
/// `(n + 3) / 4 * 4`. Returns -1 when `n` is negative.
/// Complexity: O(1).
pub fn stun_padded_len(n: Int) -> Int {
  if n < 0 {
    return -1;
  }
  return ((n + 3) / 4) * 4;
}

/// Pack a method and class into the 14-bit wire message type, or -1 when
/// `method` is outside 0..4095 or `msg_class` outside 0..3. The class
/// occupies bit 4 (C0) and bit 8 (C1) between the method nibbles, exactly
/// as in RFC 5389 section 6. Complexity: O(1).
pub fn stun_message_type(method: Int, msg_class: Int) -> Int {
  if method < 0 || method > 4095 {
    return -1;
  }
  if msg_class < 0 || msg_class > 3 {
    return -1;
  }
  let m0 = method % 16;
  let m1 = (method / 16) % 16;
  let m2 = method / 256;
  return m0 + (m1 % 8) * 32 + (m1 / 8) * 512 + m2 * 1024 + (msg_class % 2) * 16 + (msg_class / 2) * 256;
}

/// Decode the 12-bit method from a message type; -1 when `msg_type` is
/// outside 0..16383 (the two most significant bits of a STUN type are
/// always zero). Complexity: O(1).
pub fn stun_type_method(msg_type: Int) -> Int {
  if msg_type < 0 || msg_type > 16383 {
    return -1;
  }
  let m0 = msg_type % 16;
  let m1low = (msg_type / 32) % 8;
  let m1high = (msg_type / 512) % 2;
  let m2 = (msg_type / 1024) % 16;
  return m0 + 16 * (m1low + 8 * m1high) + 256 * m2;
}

/// Decode the 2-bit class (0 request, 1 indication, 2 success response,
/// 3 error response) from a message type; -1 when `msg_type` is outside
/// 0..16383. Complexity: O(1).
pub fn stun_type_class(msg_type: Int) -> Int {
  if msg_type < 0 || msg_type > 16383 {
    return -1;
  }
  let c0 = (msg_type / 16) % 2;
  let c1 = (msg_type / 256) % 2;
  return c0 + 2 * c1;
}

/// Short name of a message class: "request", "indication",
/// "success response" or "error response"; "unknown" otherwise.
/// Complexity: O(1).
pub fn stun_class_name(msg_class: Int) -> Str {
  if msg_class == STUN_CLASS_REQUEST { return "request"; }
  if msg_class == STUN_CLASS_INDICATION { return "indication"; }
  if msg_class == STUN_CLASS_SUCCESS { return "success response"; }
  if msg_class == STUN_CLASS_ERROR { return "error response"; }
  return "unknown";
}

/// Name of a method from the documented set of this package: "binding"
/// for 0x001 and "unknown" for everything else (there is no method
/// registry beyond Binding). Complexity: O(1).
pub fn stun_method_name(method: Int) -> Str {
  if method == STUN_METHOD_BINDING { return "binding"; }
  return "unknown";
}

/// Name of an attribute from the documented set of this package:
/// "MAPPED-ADDRESS", "USERNAME", "ERROR-CODE", "XOR-MAPPED-ADDRESS" or
/// "SOFTWARE"; "unknown" for every other type (which is not an error --
/// unknown attributes are preserved as raw TLVs). Complexity: O(1).
pub fn stun_attr_name(attr_type: Int) -> Str {
  if attr_type == STUN_ATTR_MAPPED_ADDRESS { return "MAPPED-ADDRESS"; }
  if attr_type == STUN_ATTR_USERNAME { return "USERNAME"; }
  if attr_type == STUN_ATTR_ERROR_CODE { return "ERROR-CODE"; }
  if attr_type == STUN_ATTR_XOR_MAPPED_ADDRESS { return "XOR-MAPPED-ADDRESS"; }
  if attr_type == STUN_ATTR_SOFTWARE { return "SOFTWARE"; }
  return "unknown";
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Cheap sniff: `data.len() >= 20`, the two most significant bits of the
/// message type are zero and the magic cookie matches. Attribute bytes are
/// not inspected. Complexity: O(1).
pub fn stun_is_message(data: &Vec[UInt8]) -> Bool {
  if data.len() < 20 {
    return false;
  }
  if _u16(data, 0) > 16383 {
    return false;
  }
  return _u32(data, 4) == STUN_MAGIC_COOKIE;
}

/// Parse a STUN message.
///
/// Checks, in order: at least 20 bytes; the message type fits 14 bits; the
/// declared message length fits the buffer; the magic cookie matches; then
/// the attribute walk inside the declared message span. Attribute values
/// stay in `data` and are located by `value_offsets`/`value_lengths`
/// (unpadded lengths); padding bytes are skipped and may hold any value.
/// Bytes after the declared span are ignored, so a datagram carrying
/// trailing junk still parses.
///
/// Errors (all stable):
///   * `stun: truncated header` -- fewer than 20 bytes;
///   * `stun: bad message type` -- nonzero top two type bits;
///   * `stun: truncated message` -- declared length runs past the buffer;
///   * `stun: bad magic cookie` -- cookie is not 0x2112A442;
///   * `stun: truncated attribute` -- 1..3 bytes left where an attribute
///     header was required (possible when the message length is not a
///     multiple of 4);
///   * `stun: attribute overruns message` -- declared value length exceeds
///     the bytes left in the message;
///   * `stun: bad padding` -- the padded value span does not fit the bytes
///     left (only possible when the message length is not a multiple
///     of 4).
/// The whole call is Err on the first malformed attribute; no partial
/// index is returned. Complexity: O(message length).
pub fn stun_parse(data: &Vec[UInt8]) -> Result[StunMessage, Str] {
  if data.len() < 20 {
    return _err_msg("stun: truncated header");
  }
  let raw_type = _u16(data, 0);
  if raw_type > 16383 {
    return _err_msg("stun: bad message type");
  }
  let declared = _u16(data, 2);
  let end = 20 + declared;
  if end > data.len() {
    return _err_msg("stun: truncated message");
  }
  let cookie = _u32(data, 4);
  if cookie != STUN_MAGIC_COOKIE {
    return _err_msg("stun: bad magic cookie");
  }
  var tid = Vec[UInt8].new();
  var t = 8;
  while t < 20 {
    tid.push(data[t]);
    t = t + 1;
  }
  var types = Vec[Int].new();
  var offsets = Vec[Int].new();
  var lengths = Vec[Int].new();
  var pos = 20;
  while pos < end {
    let remaining = end - pos;
    if remaining < STUN_ATTR_HEADER_SIZE {
      return _err_msg("stun: truncated attribute");
    }
    let atype = _u16(data, pos);
    let alen = _u16(data, pos + 2);
    if alen > remaining - STUN_ATTR_HEADER_SIZE {
      return _err_msg("stun: attribute overruns message");
    }
    let padded = stun_padded_len(alen);
    if padded > remaining - STUN_ATTR_HEADER_SIZE {
      return _err_msg("stun: bad padding");
    }
    types.push(atype);
    offsets.push(pos + STUN_ATTR_HEADER_SIZE);
    lengths.push(alen);
    pos = pos + STUN_ATTR_HEADER_SIZE + padded;
  }
  let m = StunMessage{
    msg_type: raw_type;
    method: stun_type_method(raw_type);
    msg_class: stun_type_class(raw_type);
    message_length: declared;
    magic_cookie: cookie;
    transaction_id: tid;
    attr_types: types;
    value_offsets: offsets;
    value_lengths: lengths;
  };
  return _ok_msg(m);
}

// --------------------------------------------------
//  Attribute access
// --------------------------------------------------

/// Number of attributes in the index. Complexity: O(1).
pub fn stun_attr_count(m: &StunMessage) -> Int {
  return m.attr_types.len();
}

/// Type of attribute `i`, or -1 when `i` is negative or beyond the count.
/// Complexity: O(1).
pub fn stun_attr_type(m: &StunMessage, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.attr_types.len() {
    return -1;
  }
  let t: Int = m.attr_types[i];
  return t;
}

/// First attribute index whose type equals `attr_type`, or -1 when absent
/// (including on an empty index). Complexity: O(attributes).
pub fn stun_find_attr(m: &StunMessage, attr_type: Int) -> Int {
  var i = 0;
  while i < m.attr_types.len() {
    let t: Int = m.attr_types[i];
    if t == attr_type {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Copy the raw value bytes of attribute `i` (padding excluded) out of
/// `data`, which must be the buffer the index was parsed from.
///
/// Err("stun: attribute out of range") when `i` is negative or beyond the
/// count; Err("stun: attribute out of bounds") when the recorded span does
/// not fit `data` (for example a shorter buffer). A zero-length value
/// yields an empty Ok. Complexity: O(value length).
pub fn stun_attr_value(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= m.attr_types.len() {
    return _err_bytes("stun: attribute out of range");
  }
  if i >= m.value_offsets.len() || i >= m.value_lengths.len() {
    return _err_bytes("stun: attribute out of range");
  }
  let off: Int = m.value_offsets[i];
  let len: Int = m.value_lengths[i];
  if off < 0 || len < 0 {
    return _err_bytes("stun: attribute out of bounds");
  }
  if off + len > data.len() {
    return _err_bytes("stun: attribute out of bounds");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Attribute `i` reinterpreted as a UTF-8 string (USERNAME, SOFTWARE,
/// reason phrases and any other text attribute).
///
/// The bytes are handed to Str::from_utf8 without further validation (the
/// pinned stdlib is lenient); use stun_attr_value when the raw bytes
/// matter. Err("stun: attribute out of range") /
/// Err("stun: attribute out of bounds") as in stun_attr_value.
/// Complexity: O(value length).
pub fn stun_attr_text(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Result[Str, Str] {
  let vr = stun_attr_value(data, m, i);
  if !vr.is_ok {
    return _err_str(vr.error);
  }
  let v: Vec[UInt8] = vr.value;
  return _ok_str(Str::from_utf8(v));
}

// --------------------------------------------------
//  Address attributes
// --------------------------------------------------

/// Decode attribute `i` as MAPPED-ADDRESS: 0 byte, family, 16-bit port and
/// a 4- or 16-byte address.
///
/// Errors: the stun_attr_value errors, plus Err("stun: truncated address")
/// when the value is shorter than 4 bytes, Err("stun: bad address family")
/// for a family other than 1/2, and Err("stun: bad address length") when
/// the value length does not match the family (8 or 20 bytes).
/// Complexity: O(value length).
pub fn stun_attr_mapped_address(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Result[StunAddress, Str] {
  let vr = stun_attr_value(data, m, i);
  if !vr.is_ok {
    return _err_addr(vr.error);
  }
  let v: Vec[UInt8] = vr.value;
  var no_tid = Vec[UInt8].new();
  return _decode_address(&v, false, &no_tid);
}

/// Decode attribute `i` as XOR-MAPPED-ADDRESS: the same structure as
/// MAPPED-ADDRESS with the port and address un-XORed against the message
/// cookie and transaction ID.
///
/// Errors: the stun_attr_mapped_address errors plus
/// Err("stun: bad transaction id") when the index does not carry a 12-byte
/// transaction ID. Complexity: O(value length).
pub fn stun_attr_xor_mapped_address(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Result[StunAddress, Str] {
  let vr = stun_attr_value(data, m, i);
  if !vr.is_ok {
    return _err_addr(vr.error);
  }
  let v: Vec[UInt8] = vr.value;
  let tid: Vec[UInt8] = m.transaction_id;
  return _decode_address(&v, true, &tid);
}

/// Decode attribute `i` as ERROR-CODE and return `class * 100 + number`
/// (for example 420). The five reserved bits of the class byte are
/// ignored and the reason phrase is not included.
///
/// Err("stun: truncated error code") when the value is shorter than the
/// 4-byte prefix; otherwise the stun_attr_value errors.
/// Complexity: O(1) after the value copy.
pub fn stun_attr_error_code(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Result[Int, Str] {
  let vr = stun_attr_value(data, m, i);
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  let v: Vec[UInt8] = vr.value;
  if v.len() < 4 {
    return _err_int("stun: truncated error code");
  }
  let cls: Int = (v[2] as Int) & 0xFF;
  let num: Int = (v[3] as Int) & 0xFF;
  return _ok_int(cls * 100 + num);
}

/// Reason phrase of the ERROR-CODE attribute `i`: the value bytes after
/// the 4-byte prefix, handed to Str::from_utf8 without further
/// validation.
///
/// Err("stun: truncated error code") when the value is shorter than the
/// 4-byte prefix; otherwise the stun_attr_value errors.
/// Complexity: O(value length).
pub fn stun_attr_error_reason(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Result[Str, Str] {
  let vr = stun_attr_value(data, m, i);
  if !vr.is_ok {
    return _err_str(vr.error);
  }
  let v: Vec[UInt8] = vr.value;
  if v.len() < 4 {
    return _err_str("stun: truncated error code");
  }
  var out = Vec[UInt8].new();
  var k = 4;
  while k < v.len() {
    out.push(v[k]);
    k = k + 1;
  }
  return _ok_str(Str::from_utf8(out));
}

// --------------------------------------------------
//  Building
// --------------------------------------------------

/// Build a whole message from a raw 14-bit type, a 12-byte transaction ID
/// and parallel attribute type/value vectors.
///
/// The header carries the magic cookie and the declared message length is
/// the sum of `4 + stun_padded_len(value.len())` over the attributes;
/// values are written verbatim and padded with zero bytes. All validation
/// happens before a byte is written, so no partial buffer escapes: errors
/// are Err("stun: bad message type") when the type is outside 0..16383,
/// Err("stun: bad transaction id") when the ID is not 12 bytes,
/// Err("stun: attribute count mismatch") when the vectors differ,
/// Err("stun: bad attribute type") for a type outside 0..65535,
/// Err("stun: attribute too large") for a value over 65535 bytes and
/// Err("stun: message too large") when the padded total exceeds 65535.
/// Complexity: O(total value bytes).
pub fn stun_build(msg_type: Int, transaction_id: &Vec[UInt8], attr_types: &Vec[Int], attr_values: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  if msg_type < 0 || msg_type > 16383 {
    return _err_bytes("stun: bad message type");
  }
  if transaction_id.len() != 12 {
    return _err_bytes("stun: bad transaction id");
  }
  if attr_types.len() != attr_values.len() {
    return _err_bytes("stun: attribute count mismatch");
  }
  var total = 0;
  var i = 0;
  while i < attr_types.len() {
    let t: Int = attr_types[i];
    let v: Vec[UInt8] = attr_values[i];
    if t < 0 || t > 65535 {
      return _err_bytes("stun: bad attribute type");
    }
    if v.len() > 65535 {
      return _err_bytes("stun: attribute too large");
    }
    total = total + STUN_ATTR_HEADER_SIZE + stun_padded_len(v.len());
    if total > 65535 {
      return _err_bytes("stun: message too large");
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _push_be(&mut out, msg_type, 2);
  _push_be(&mut out, total, 2);
  _push_be(&mut out, STUN_MAGIC_COOKIE, 4);
  _push_bytes(&mut out, transaction_id);
  var k = 0;
  while k < attr_types.len() {
    let t2: Int = attr_types[k];
    let v2: Vec[UInt8] = attr_values[k];
    _push_be(&mut out, t2, 2);
    _push_be(&mut out, v2.len(), 2);
    _push_bytes(&mut out, &v2);
    var pad = stun_padded_len(v2.len()) - v2.len();
    var p = 0;
    while p < pad {
      out.push(0);
      p = p + 1;
    }
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Encode a MAPPED-ADDRESS value: 0 byte, family, big-endian port and the
/// address bytes. `family` is STUN_FAMILY_IPV4 (4-byte address) or
/// STUN_FAMILY_IPV6 (16-byte address).
///
/// Errors: Err("stun: bad address family"), Err("stun: bad address
/// length") when the address bytes do not match the family, and
/// Err("stun: bad port") when the port is outside 0..65535.
/// Complexity: O(address length).
pub fn stun_encode_mapped_address(family: Int, port: Int, address: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if family != STUN_FAMILY_IPV4 && family != STUN_FAMILY_IPV6 {
    return _err_bytes("stun: bad address family");
  }
  if address.len() != _address_bytes(family) {
    return _err_bytes("stun: bad address length");
  }
  if port < 0 || port > 65535 {
    return _err_bytes("stun: bad port");
  }
  var out = Vec[UInt8].new();
  out.push(0);
  out.push(family as UInt8);
  _push_be(&mut out, port, 2);
  _push_bytes(&mut out, address);
  return _ok_bytes(out);
}

/// Encode an XOR-MAPPED-ADDRESS value: like stun_encode_mapped_address,
/// but the port is XORed with 0x2112 (the high half of the cookie) and the
/// address is XORed with the 32-bit cookie (IPv4) or the 128-bit
/// cookie || transaction ID mask (IPv6). `transaction_id` must be exactly
/// 12 bytes.
///
/// Errors: as stun_encode_mapped_address, plus
/// Err("stun: bad transaction id") for an ID that is not 12 bytes.
/// Complexity: O(address length).
pub fn stun_encode_xor_mapped_address(family: Int, port: Int, address: &Vec[UInt8], transaction_id: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if family != STUN_FAMILY_IPV4 && family != STUN_FAMILY_IPV6 {
    return _err_bytes("stun: bad address family");
  }
  if address.len() != _address_bytes(family) {
    return _err_bytes("stun: bad address length");
  }
  if port < 0 || port > 65535 {
    return _err_bytes("stun: bad port");
  }
  if transaction_id.len() != 12 {
    return _err_bytes("stun: bad transaction id");
  }
  var out = Vec[UInt8].new();
  out.push(0);
  out.push(family as UInt8);
  let xport = _xor_byte(port / 256, _COOKIE_B0) * 256 + _xor_byte(port % 256, _COOKIE_B1);
  _push_be(&mut out, xport, 2);
  var i = 0;
  while i < address.len() {
    let b: Int = (address[i] as Int) & 0xFF;
    let mask: Int = _mask_byte(i, transaction_id);
    out.push(_xor_byte(b, mask) as UInt8);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Encode an ERROR-CODE value: two reserved zero bytes, the code split as
/// `code / 100` (class) and `code % 100` (number), then the reason phrase
/// bytes.
///
/// Err("stun: bad error code") when `code` is outside 300..699.
/// Complexity: O(reason length).
pub fn stun_encode_error_code(code: Int, reason: Str) -> Result[Vec[UInt8], Str] {
  if code < 300 || code > 699 {
    return _err_bytes("stun: bad error code");
  }
  var out = Vec[UInt8].new();
  out.push(0);
  out.push(0);
  out.push((code / 100) as UInt8);
  out.push((code % 100) as UInt8);
  let rb: Vec[UInt8] = _str_bytes(reason);
  _push_bytes(&mut out, &rb);
  return _ok_bytes(out);
}

/// UTF-8 bytes of a USERNAME value. The name is not validated (STUN
/// leaves its length and normalization rules to the application).
/// Complexity: O(name length).
pub fn stun_encode_username(name: Str) -> Vec[UInt8] {
  return _str_bytes(name);
}

/// UTF-8 bytes of a SOFTWARE value. The text is not validated.
/// Complexity: O(text length).
pub fn stun_encode_software(text: Str) -> Vec[UInt8] {
  return _str_bytes(text);
}
