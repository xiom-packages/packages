// XIOM — Protocol Buffers Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.protobuf

pub fn version() -> Str;
pub fn encode(message: &ProtoMessage) -> Result[Vec[UInt8], Str];
pub fn decode(data: &Vec[UInt8]) -> Result[ProtoMessage, Str];

pub type ProtoMessage = { fields: Map[Int, ProtoValue]; } derive[Clone]
pub type ProtoValue = enum {
  Varint(value: Int),
  Fixed64(value: Int),
  LengthDelimited(value: Vec[UInt8]),
  Fixed32(value: Int),
}
