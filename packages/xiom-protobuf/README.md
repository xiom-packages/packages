# xiom-protobuf — Protocol Buffers

Protocol Buffers serialization for XIOM. Proto3 schema definitions, wire-format encode/decode via libprotobuf.

## Install

```powershell
xiom pkg install xiom-protobuf
```

## Requirements

- **libprotobuf** (Protocol Buffers C++ runtime)
  - Linux: `apt install libprotobuf-dev`
  - macOS: `brew install protobuf`
  - Windows: vcpkg (`vcpkg install protobuf`)

## Link Flags

```
-l protobuf
```

## Quick Start

```xiom
use xiom.protobuf;

fn main() -> Result[Unit, Str] {
  let msg = ProtoMessage{ fields: Map[Int, ProtoValue].new() };
  msg.fields.insert(1, ProtoValue::String("hello"));
  msg.fields.insert(2, ProtoValue::Varint(42));

  let data = encode(&msg)?;
  let decoded = decode(&data)?;

  return Ok(());
}
```

## API Overview

| Module | File | Purpose |
|--------|------|---------|
| `xiom.protobuf` | `protobuf.xi` | Runtime encode/decode via libprotobuf |
| `xiom.protobuf.schema` | `src/schema.xi` | Proto3 schema types (pure XIOM) |

### Schema Definition

```xiom
use xiom.protobuf.schema;

let schema = proto_message_new("User");
proto_add_field(&mut schema, "id", 1, ProtoType::Int32);
proto_add_field(&mut schema, "name", 2, ProtoType::String);
proto_add_field(&mut schema, "email", 3, ProtoType::String);
proto_add_field(&mut schema, "active", 4, ProtoType::Bool);
```

### Proto Types

```xiom
pub enum ProtoType {
  Int32, Int64, UInt32, UInt64,
  Float, Double,
  Bool,
  String, Bytes,
  Message, Enum,
}
```

### Wire Values

```xiom
pub enum ProtoValue {
  Varint(value: Int),              // Int32, Int64, UInt32, UInt64, Bool, Enum
  Fixed64(value: Int),             // Fixed64, Double
  LengthDelimited(value: Vec[UInt8]), // String, Bytes, nested Message
  Fixed32(value: Int),             // Fixed32, Float
}
```

## Contracts

- Field numbers must be within valid proto3 range (1..536870911)
- Field names must be non-empty
- Duplicate field numbers within a message are rejected

## License

MIT or Apache-2.0, at your option.
