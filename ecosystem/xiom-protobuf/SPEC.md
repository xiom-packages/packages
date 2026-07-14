# xiom-protobuf Specification

## Overview
Protocol Buffers serialization bindings for XIOM. Provides proto3-compatible schema definitions and wire-format encode/decode via libprotobuf.

## Architecture

### Layers
```
┌──────────────────────────────────────┐
│  src/schema.xi   (Proto3 types)      │
│  ProtoType, ProtoField, ProtoMessage │
├──────────────────────────────────────┤
│  protobuf.xi     (Runtime FFI)       │
│  encode, decode, ProtoValue          │
├──────────────────────────────────────┤
│  protobuf.xiom-bind (C ABI)          │
│  protobuf_message_serialize/parse    │
└──────────────────────────────────────┘
```

### Design Decisions
- Schema types (`ProtoType`, `ProtoField`, `ProtoMessage`) are pure XIOM — they describe the proto3 schema without runtime dependencies.
- Runtime serialization (`encode`, `decode`) delegates to the C library for wire-format compliance.
- `ProtoValue` is an algebraic type covering all proto3 wire types: varint, fixed64, length-delimited, fixed32.

## Type System

### ProtoType (proto3 scalar + composite)
```
pub enum ProtoType {
  Int32, Int64, UInt32, UInt64,
  Float, Double,
  Bool,
  String, Bytes,
  Message, Enum,
}
```

### ProtoField
```
pub type ProtoField = { name: Str; number: Int; field_type: ProtoType; repeated: Bool; }
```
- `number` is the proto field tag number (1-based, must be unique within message).
- `repeated` indicates a repeated (list) field.

### ProtoMessage (schema definition)
```
pub type ProtoMessage = { name: Str; fields: Vec[ProtoField]; }
```

### ProtoValue (runtime wire value)
```
pub enum ProtoValue {
  Varint(value: Int),
  Fixed64(value: Int),
  LengthDelimited(value: Vec[UInt8]),
  Fixed32(value: Int),
}
```

### Runtime ProtoMessage (serialized representation)
```
pub type ProtoMessage = { fields: Map[Int, ProtoValue]; } derive[Clone]
```
- Keyed by field number.

## API Surface

### Schema Definition (`src/schema.xi`)
| Function | Description |
|----------|-------------|
| `proto_message_new(name)` | Create empty message schema |
| `proto_add_field(msg, name, number, ftype)` | Add field definition |
| `proto_set_repeated(msg, field_index)` | Mark field as repeated |
| `proto_get_field(msg, name)` | Lookup field by name |
| `proto_message_to_proto3(msg)` | Serialize schema to `.proto` text |

### Runtime Serialization (`protobuf.xi`)
| Function | Description |
|----------|-------------|
| `version()` | libprotobuf version string |
| `encode(message)` | Serialize runtime message to bytes |
| `decode(data)` | Parse bytes into runtime message |

## Wire Types
| ProtoType | Wire Type | Encoding |
|-----------|-----------|----------|
| Int32, Int64, UInt32, UInt64, Bool, Enum | Varint (0) | Variable-length integer |
| Fixed64, Double | 64-bit (1) | Fixed 8 bytes |
| String, Bytes, Message | Length-delimited (2) | Length prefix + data |
| Fixed32, Float | 32-bit (5) | Fixed 4 bytes |

## Safety Contracts
1. Field numbers must be in range `1..536870911` (proto3 valid range).
2. Field names must be non-empty and follow proto3 identifier rules.
3. `encode` validates that all `ProtoMessage` fields map to valid wire types.
4. `decode` validates the wire format before constructing the runtime message.
5. Duplicate field numbers within a message are rejected at schema build time.

## External Dependencies
- **Runtime:** libprotobuf — `libprotobuf.dll` / `libprotobuf.so`
- **Install:** `apt install libprotobuf-dev` (Linux), `brew install protobuf` (macOS), vcpkg (Windows)
- **Link flags:** `-l protobuf`
- **Compatibility:** protobuf >= 3.0 (proto3 syntax)

## Error Handling
1. Schema validation errors at build time (duplicate numbers, invalid types).
2. Encode errors for type/size mismatches return `Err(description)`.
3. Decode errors for malformed wire format return `Err(description)`.
4. Unknown field numbers during decode are preserved (proto3 forward compatibility).
