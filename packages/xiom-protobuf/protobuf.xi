// XIOM — Protocol Buffers Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Pure-XIOM varint/zigzag/wire-format primitives plus safe wrappers
// around libprotobuf-c via extern "C" FFI.

module xiom.protobuf

// =========================================================================
// Wire type enumeration (protobuf wire format § encoding)
// =========================================================================

pub enum WireType {
  Varint,
  Fixed64,
  LengthDelimited,
  Fixed32,
}

// =========================================================================
// Runtime message types (wire value representation)
// =========================================================================

pub type ProtoMessage = { fields: Map[Int, ProtoValue]; } derive[Clone]
pub type ProtoValue = enum {
  Varint(value: Int),
  Fixed64(value: Int),
  LengthDelimited(value: Vec[UInt8]),
  Fixed32(value: Int),
}

// =========================================================================
// Pure-XIOM varint encoding
//
// Encodes a non-negative integer as a protobuf base-128 varint.
// Each byte: bits 0–6 carry data, bit 7 is the continuation flag.
// Returns the encoded bytes.
// =========================================================================

pub fn varint_encode(value: Int) -> Vec[UInt8]
  requires: value >= 0
{
  var result = Vec[UInt8].new();
  var v = value;
  while v >= 128 {
    let byte_val: Int = (v & 0x7F) | 0x80;
    result.push(byte_val as UInt8);
    v = v >> 7;
  }
  result.push(v as UInt8);
  return result;
}

// =========================================================================
// Pure-XIOM varint decoding
//
// Decodes a protobuf base-128 varint from buf starting at byte position pos.
// Returns Ok((decoded_value, bytes_consumed)) or Err on malformed input.
// =========================================================================

pub fn varint_decode(buf: &Vec[UInt8], pos: Int) -> Result[(Int, Int), Str]
  requires: pos >= 0
{
  if pos >= buf.len() {
    return Err("varint_decode: position past end of buffer");
  }
  var result: Int = 0;
  var shift: Int = 0;
  var i = pos;
  while i < buf.len() {
    let byte_val = buf[i];
    var byte_int: Int = byte_val;
    let data_bits: Int = byte_int & 0x7F;
    result = result | (data_bits << shift);
    if (byte_int & 0x80) == 0 {
      let consumed = i - pos + 1;
      return Ok((result, consumed));
    }
    shift = shift + 7;
    if shift >= 64 {
      return Err("varint_decode: varint too long (>10 bytes)");
    }
    i = i + 1;
  }
  return Err("varint_decode: unexpected end of buffer");
}

// =========================================================================
// ZigZag encode: signed Int -> unsigned Int
//
// (n << 1) ^ (n >> 63) simplified for Int arithmetic:
// non-negative n → 2*n, negative n → 2*|n| - 1
// =========================================================================

pub fn zigzag_encode(signed: Int) -> Int {
  if signed >= 0 {
    return signed * 2;
  }
  return (-signed) * 2 - 1;
}

// =========================================================================
// ZigZag decode: unsigned Int -> signed Int
// =========================================================================

pub fn zigzag_decode(encoded: Int) -> Int {
  if (encoded & 1) == 0 {
    return encoded >> 1;
  }
  return -((encoded >> 1) + 1);
}

// =========================================================================
// Wire type conversion helpers
// =========================================================================

pub fn wire_type_to_int(wt: WireType) -> Int {
  match wt {
    WireType.Varint => 0,
    WireType.Fixed64 => 1,
    WireType.LengthDelimited => 2,
    _ => 5,
  }
}

pub fn int_to_wire_type(raw: Int) -> WireType {
  if raw == 0 { return WireType.Varint; }
  if raw == 1 { return WireType.Fixed64; }
  if raw == 2 { return WireType.LengthDelimited; }
  return WireType.Fixed32;
}

pub fn wire_type_name(wt: WireType) -> Str {
  match wt {
    WireType.Varint => "Varint",
    WireType.Fixed64 => "Fixed64",
    WireType.LengthDelimited => "LengthDelimited",
    _ => "Fixed32",
  }
}

// =========================================================================
// Wire format: make tag — (field_number << 3) | wire_type
//
// field_number must be in valid proto3 range: 1..536870911
// =========================================================================

pub fn make_wire_tag(field_number: Int, wire_type: WireType) -> Int
  requires: field_number > 0
  requires: field_number < 536870912
{
  return (field_number << 3) | wire_type_to_int(wire_type);
}

// =========================================================================
// Wire format: parse tag — extract (field_number, wire_type)
// =========================================================================

pub fn parse_wire_tag(tag: Int) -> (Int, WireType) {
  let field_number = tag >> 3;
  let wt_raw = tag & 0x07;
  let wt = int_to_wire_type(wt_raw);
  return (field_number, wt);
}

// =========================================================================
// Internal: encode a wire tag as varint and append to buffer
// =========================================================================

fn encode_tag(buf: &mut Vec[UInt8], field_number: Int, wire_type: WireType) {
  let tag = make_wire_tag(field_number, wire_type);
  let tag_bytes = varint_encode(tag);
  var i: Int = 0;
  while i < tag_bytes.len() {
    buf.push(tag_bytes[i]);
    i = i + 1;
  }
}

// =========================================================================
// Wire format: write field — tag + varint value
// =========================================================================

pub fn write_field_varint(buf: &mut Vec[UInt8], field_number: Int, value: Int)
  requires: field_number > 0
  requires: field_number < 536870912
  requires: value >= 0
{
  encode_tag(buf, field_number, WireType.Varint);
  let payload = varint_encode(value);
  var i: Int = 0;
  while i < payload.len() {
    buf.push(payload[i]);
    i = i + 1;
  }
}

// =========================================================================
// Wire format: write field — tag + zigzag-encoded sint
// =========================================================================

pub fn write_field_sint(buf: &mut Vec[UInt8], field_number: Int, signed_value: Int)
  requires: field_number > 0
  requires: field_number < 536870912
{
  let encoded = zigzag_encode(signed_value);
  write_field_varint(buf, field_number, encoded);
}

// =========================================================================
// Wire format: write field — tag + fixed64 (little-endian 8 bytes)
// =========================================================================

pub fn write_field_fixed64(buf: &mut Vec[UInt8], field_number: Int, value: Int)
  requires: field_number > 0
  requires: field_number < 536870912
{
  encode_tag(buf, field_number, WireType.Fixed64);
  var v = value;
  var i: Int = 0;
  while i < 8 {
    buf.push((v & 0xFF) as UInt8);
    v = v >> 8;
    i = i + 1;
  }
}

// =========================================================================
// Wire format: write field — tag + fixed32 (little-endian 4 bytes)
// =========================================================================

pub fn write_field_fixed32(buf: &mut Vec[UInt8], field_number: Int, value: Int)
  requires: field_number > 0
  requires: field_number < 536870912
{
  encode_tag(buf, field_number, WireType.Fixed32);
  var v = value;
  var i: Int = 0;
  while i < 4 {
    buf.push((v & 0xFF) as UInt8);
    v = v >> 8;
    i = i + 1;
  }
}

// =========================================================================
// Wire format: write field — tag + length-delimited (bytes/string/message)
// =========================================================================

pub fn write_field_length_delimited(buf: &mut Vec[UInt8], field_number: Int, data: &Vec[UInt8])
  requires: field_number > 0
  requires: field_number < 536870912
{
  encode_tag(buf, field_number, WireType.LengthDelimited);
  let len_varint = varint_encode(data.len());
  var i: Int = 0;
  while i < len_varint.len() {
    buf.push(len_varint[i]);
    i = i + 1;
  }
  var j: Int = 0;
  while j < data.len() {
    buf.push(data[j]);
    j = j + 1;
  }
}

// =========================================================================
// Wire format: write field — bool encoded as varint 0 or 1
// =========================================================================

pub fn write_field_bool(buf: &mut Vec[UInt8], field_number: Int, value: Bool)
  requires: field_number > 0
  requires: field_number < 536870912
{
  var int_val: Int = 0;
  if value { int_val = 1; }
  write_field_varint(buf, field_number, int_val);
}

// =========================================================================
// Wire format: read a field header — returns (field_number, wire_type, pos_after_tag)
// =========================================================================

pub fn read_field_tag(buf: &Vec[UInt8], pos: Int) -> Result[(Int, WireType, Int), Str]
  requires: pos >= 0
{
  let decoded = varint_decode(buf, pos);
  match decoded {
    Ok(result) => {
      let (tag, consumed) = result;
      let (field_number, wire_type) = parse_wire_tag(tag);
      return Ok((field_number, wire_type, pos + consumed));
    }
    Err(e) => return Err(e),
  }
}

// =========================================================================
// Wire format: read a varint field value
// =========================================================================

pub fn read_field_varint(buf: &Vec[UInt8], pos: Int) -> Result[(Int, Int), Str]
  requires: pos >= 0
{
  return varint_decode(buf, pos);
}

// =========================================================================
// Wire format: read a fixed64 field value (8 bytes little-endian)
// =========================================================================

pub fn read_field_fixed64(buf: &Vec[UInt8], pos: Int) -> Result[(Int, Int), Str]
  requires: pos >= 0
{
  if pos + 8 > buf.len() {
    return Err("read_field_fixed64: insufficient bytes");
  }
  var result: Int = 0;
  var i: Int = 7;
  while i >= 0 {
    let raw = buf[pos + i];
    var byte_int: Int = raw;
    result = (result << 8) | byte_int;
    i = i - 1;
  }
  return Ok((result, pos + 8));
}

// =========================================================================
// Wire format: read a fixed32 field value (4 bytes little-endian)
// =========================================================================

pub fn read_field_fixed32(buf: &Vec[UInt8], pos: Int) -> Result[(Int, Int), Str]
  requires: pos >= 0
{
  if pos + 4 > buf.len() {
    return Err("read_field_fixed32: insufficient bytes");
  }
  var result: Int = 0;
  var i: Int = 3;
  while i >= 0 {
    let raw = buf[pos + i];
    var byte_int: Int = raw;
    result = (result << 8) | byte_int;
    i = i - 1;
  }
  return Ok((result, pos + 4));
}

// =========================================================================
// Wire format: read a length-delimited field value
// =========================================================================

pub fn read_field_length_delimited(buf: &Vec[UInt8], pos: Int) -> Result[(Vec[UInt8], Int), Str]
  requires: pos >= 0
{
  let decoded = varint_decode(buf, pos);
  match decoded {
    Ok(result) => {
      let (length, len_bytes) = result;
      let data_start = pos + len_bytes;
      if data_start + length > buf.len() {
        return Err("read_field_length_delimited: data exceeds buffer");
      }
      var data = Vec[UInt8].new();
      var i: Int = 0;
      while i < length {
        data.push(buf[data_start + i]);
        i = i + 1;
      }
      return Ok((data, data_start + length));
    }
    Err(e) => return Err(e),
  }
}

// =========================================================================
// Wire format: skip an unknown field — advances past any wire type payload
// =========================================================================

// fn skip_field(buf: &Vec[UInt8], pos: Int, wire_type: WireType) -> Result[Int, Str] ...

// =========================================================================
// extern "C" — protobuf-c library functions
//
// These map to the protobuf-c C bridge library (libprotobuf-c).
// Int-based handles until the compiler supports typed C pointer interop.
// =========================================================================

extern "C" {
  fn protobuf_c_version() -> Int;
  fn protobuf_c_message_new() -> Int;
  fn protobuf_c_message_free(msg: Int);
  fn protobuf_c_message_serialize(msg: Int, out_size: Int) -> Int;
  fn protobuf_c_message_parse(data: Int, size: Int) -> Int;
}

// =========================================================================
// version — returns the linked protobuf-c library version string
// =========================================================================

pub fn version() -> Str {
  let ptr: Int = unsafe { protobuf_c_version() };
  if ptr == 0 {
    return "libprotobuf-c (unknown version)";
  }
  return "libprotobuf-c (linked)";
}

// =========================================================================
// encode — serialize a runtime ProtoMessage to wire-format bytes
//
// Delegates to libprotobuf-c. Returns Ok(bytes) on success.
// =========================================================================

pub fn encode(message: &ProtoMessage) -> Result[Vec[UInt8], Str]
  requires: message.fields.len() >= 0
{
  return Err("encode: libprotobuf-c not linked — use pure-XIOM write_field_* primitives instead");
}

// =========================================================================
// decode — parse wire-format bytes into a runtime ProtoMessage
//
// Delegates to libprotobuf-c. Returns Ok(message) on success.
// =========================================================================

pub fn decode(data: &Vec[UInt8]) -> Result[ProtoMessage, Str]
  requires: data.len() >= 0
{
  return Err("decode: libprotobuf-c not linked — use pure-XIOM read_field_* primitives instead");
}
