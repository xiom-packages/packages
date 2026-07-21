module xiom.protobuf.schema

pub enum ProtoType {
  Int32,
  Int64,
  UInt32,
  UInt64,
  Float,
  Double,
  Bool,
  String,
  Bytes,
  Message,
  Enum,
}

pub type ProtoField = {
  name: Str;
  number: Int;
  field_type: ProtoType;
  repeated: Bool;
} derive[Clone]

pub type ProtoMessage = {
  name: Str;
  fields: Vec[ProtoField];
} derive[Clone]

fn proto_message_new(name: Str) -> ProtoMessage
  requires: name.len() > 0
{
  ProtoMessage { name: name.clone(), fields: Vec[ProtoField].new() }
}

fn proto_add_field(msg: &mut ProtoMessage, name: Str, number: Int, ftype: ProtoType)
  requires: name.len() > 0
  requires: number > 0
  requires: number < 536870912
{
  let field = ProtoField {
    name: name.clone(),
    number: number,
    field_type: ftype,
    repeated: false,
  };
  msg.fields.push(field);
}

fn proto_set_repeated(msg: &mut ProtoMessage, field_index: Int)
  requires: field_index >= 0
  requires: field_index < msg.fields.len()
{
  msg.fields[field_index].repeated = true;
}

fn proto_get_field(msg: &ProtoMessage, name: Str) -> Option[ProtoField]
  requires: name.len() > 0
{
  var i = 0;
  while i < msg.fields.len() {
    if msg.fields[i].name == name {
      return Some(msg.fields[i].clone());
    };
    i = i + 1;
  };
  None
}

fn proto_has_repeated(msg: &ProtoMessage) -> Bool
{
  var i = 0;
  while i < msg.fields.len() {
    if msg.fields[i].repeated {
      return true;
    };
    i = i + 1;
  };
  false
}

fn proto_field_count(msg: &ProtoMessage) -> Int
{
  msg.fields.len()
}

fn proto_type_to_str(ftype: ProtoType) -> Str
{
  match ftype {
    ProtoType.Int32 => "int32",
    ProtoType.Int64 => "int64",
    ProtoType.UInt32 => "uint32",
    ProtoType.UInt64 => "uint64",
    ProtoType.Float => "float",
    ProtoType.Double => "double",
    ProtoType.Bool => "bool",
    ProtoType.String => "string",
    ProtoType.Bytes => "bytes",
    ProtoType.Message => "message",
    ProtoType.Enum => "enum",
  }
}

fn proto_message_to_proto3(msg: &ProtoMessage) -> Str
{
  var output = "syntax = \"proto3\";\n\nmessage ".clone();
  output = output + msg.name + " {\n";
  var i = 0;
  while i < msg.fields.len() {
    let field = &msg.fields[i];
    let prefix = if field.repeated { "  repeated " } else { "  " };
    let type_str = proto_type_to_str(field.field_type);
    output = output + prefix + type_str + " " + field.name + " = " + field.number.to_str() + ";\n";
    i = i + 1;
  };
  output = output + "}\n";
  output
}
