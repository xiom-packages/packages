# xiom.protobuf Specification

## Overview
Protocol Buffers serialization bindings for XIOM. Provides proto3-compatible schema definitions, pure-XIOM wire-format primitives (varint, zigzag, field encoding), and runtime encode/decode via libprotobuf-c.

## Architecture

### Layers
```
+--------------------------------------------------+
|  src/schema.xi   (Proto3 types)                  |
|  ProtoType, ProtoField, ProtoMessage             |
|--------------------------------------------------|
|  protobuf.xi     (Pure-XIOM Wire Primitives)     |
|  varint, zigzag, wire_tag, write_field_*,        |
|  read_field_*                                     |
|--------------------------------------------------|
|  protobuf.xi     (Runtime FFI)                   |
|  encode, decode, ProtoValue, extern "C" block    |
|--------------------------------------------------|
|  protobuf.xiom-bind (C ABI)                      |
|  protobuf_c_message_serialize/parse              |
`--------------------------------------------------+
```

### Design Decisions
- **Schema types** (`ProtoType`, `ProtoField`, `ProtoMessage`) are pure XIOM -- they describe the proto3 schema without runtime dependencies.
- **Wire primitives** (varint, zigzag, wire format field write/read) are pure XIOM -- no FFI dependency, usable without libprotobuf.
- **Runtime serialization** (`encode`, `decode`) delegates to the C library for wire-format compliance at the message level.
- `ProtoValue` is an algebraic type covering all proto3 wire types: varint, fixed64, length-delimited, fixed32.

## Wire Types

### WireType Enum (protobuf.xi)
```
pub enum WireType {
  Varint = 0,
  Fixed64 = 1,
  LengthDelimited = 2,
  Fixed32 = 5,
}
```

### ProtoType to Wire Type Mapping
| ProtoType | Wire Type | Encoding |
|-----------|-----------|----------|
| Int32, Int64, UInt32, UInt64, Bool, Enum, Sint32, Sint64 | Varint (0) | Base-128 variable-length integer |
| Fixed64, Double, SFixed64 | 64-bit (1) | Fixed 8 bytes, little-endian |
| String, Bytes, Message, packed repeated | Length-delimited (2) | Varint length prefix + data |
| Fixed32, Float, SFixed32 | 32-bit (5) | Fixed 4 bytes, little-endian |

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

### Wire Primitives -- Varint (protobuf.xi)
| Function | Signature | Description |
|----------|-----------|-------------|
| `varint_encode` | `(value: Int) -> Vec[UInt8]` | Encode unsigned integer as base-128 varint |
| `varint_decode` | `(buf: &Vec[UInt8], pos: Int) -> Result[(Int, Int), Str]` | Decode varint, returns (value, bytes_consumed) |

### Wire Primitives -- ZigZag (protobuf.xi)
| Function | Signature | Description |
|----------|-----------|-------------|
| `zigzag_encode` | `(signed: Int) -> Int` | ZigZag encode signed->unsigned |
| `zigzag_decode` | `(encoded: Int) -> Int` | ZigZag decode unsigned->signed |

### Wire Primitives -- Wire Tags (protobuf.xi)
| Function | Signature | Description |
|----------|-----------|-------------|
| `make_wire_tag` | `(field_number: Int, wire_type: WireType) -> Int` | Build tag: `(fn << 3) \| wt` |
| `parse_wire_tag` | `(tag: Int) -> (Int, WireType)` | Extract field_number and wire_type |
| `wire_type_to_int` | `(wt: WireType) -> Int` | WireType enum -> wire type value |
| `int_to_wire_type` | `(raw: Int) -> WireType` | Wire type value -> WireType enum |
| `wire_type_name` | `(wt: WireType) -> Str` | Human-readable wire type name |

### Wire Primitives -- Field Writers (protobuf.xi)
| Function | Signature | Description |
|----------|-----------|-------------|
| `write_field_varint` | `(buf: &mut Vec[UInt8], fn: Int, value: Int)` | Write tag + varint value |
| `write_field_sint` | `(buf: &mut Vec[UInt8], fn: Int, signed: Int)` | Write tag + zigzag-encoded sint |
| `write_field_fixed64` | `(buf: &mut Vec[UInt8], fn: Int, value: Int)` | Write tag + 8 bytes LE |
| `write_field_fixed32` | `(buf: &mut Vec[UInt8], fn: Int, value: Int)` | Write tag + 4 bytes LE |
| `write_field_length_delimited` | `(buf: &mut Vec[UInt8], fn: Int, data: &Vec[UInt8])` | Write tag + length + data |
| `write_field_bool` | `(buf: &mut Vec[UInt8], fn: Int, value: Bool)` | Write tag + varint 0/1 |

### Wire Primitives -- Field Readers (protobuf.xi)
| Function | Signature | Description |
|----------|-----------|-------------|
| `read_field_tag` | `(buf: &Vec[UInt8], pos: Int) -> Result[(Int, WireType, Int), Str]` | Read field header: (fn, wt, next_pos) |
| `read_field_varint` | `(buf: &Vec[UInt8], pos: Int) -> Result[(Int, Int), Str]` | Read varint value: (value, next_pos) |
| `read_field_fixed64` | `(buf: &Vec[UInt8], pos: Int) -> Result[(Int, Int), Str]` | Read fixed64 LE: (value, next_pos) |
| `read_field_fixed32` | `(buf: &Vec[UInt8], pos: Int) -> Result[(Int, Int), Str]` | Read fixed32 LE: (value, next_pos) |
| `read_field_length_delimited` | `(buf: &Vec[UInt8], pos: Int) -> Result[(Vec[UInt8], Int), Str]` | Read L-D data: (data, next_pos) |

### Runtime Serialization (protobuf.xi)
| Function | Signature | Description |
|----------|-----------|-------------|
| `version()` | `() -> Str` | libprotobuf-c version string |
| `encode(message)` | `(&ProtoMessage) -> Result[Vec[UInt8], Str]` | Serialize runtime message to bytes |
| `decode(data)` | `(&Vec[UInt8]) -> Result[ProtoMessage, Str]` | Parse bytes into runtime message |

### Schema Definition (src/schema.xi)
| Function | Description |
|----------|-------------|
| `proto_message_new(name)` | Create empty message schema |
| `proto_add_field(msg, name, number, ftype)` | Add field definition |
| `proto_set_repeated(msg, field_index)` | Mark field as repeated |
| `proto_get_field(msg, name)` | Lookup field by name |
| `proto_message_to_proto3(msg)` | Serialize schema to `.proto` text |

## Varint Encoding Specification

### Algorithm
```
while value >= 0x80:
    emit (value & 0x7F) | 0x80
    value >>= 7
emit value & 0x7F
```

### Examples
| Value | Encoded Bytes (hex) |
|-------|---------------------|
| 0 | `00` |
| 1 | `01` |
| 127 | `7F` |
| 128 | `80 01` |
| 300 | `AC 02` |
| 1000000 | `C0 84 3D` |

## ZigZag Encoding Specification

Signed integers are mapped to unsigned integers for efficient varint encoding:
- Positive n -> 2n
- Negative n -> 2|n| - 1

| Signed | Unsigned |
|--------|----------|
| 0 | 0 |
| -1 | 1 |
| 1 | 2 |
| -2 | 3 |
| 2 | 4 |
| 2147483647 | 4294967294 |
| -2147483648 | 4294967295 |

## Wire Tag Format

```
tag = (field_number << 3) | wire_type
```

- Bits 0-2: wire type (3 bits)
- Bits 3+: field number (shifted left by 3)

### Valid Wire Types
| Value | Name | Used For |
|-------|------|----------|
| 0 | Varint | int32, int64, uint32, uint64, sint32, sint64, bool, enum |
| 1 | Fixed64 | fixed64, sfixed64, double |
| 2 | LengthDelimited | string, bytes, embedded messages, packed repeated fields |
| 3 | StartGroup | Deprecated (proto2 groups) |
| 4 | EndGroup | Deprecated (proto2 groups) |
| 5 | Fixed32 | fixed32, sfixed32, float |

## Safety Contracts
1. Field numbers must be in range `1..536870911` (proto3 valid range).
2. Field names must be non-empty and follow proto3 identifier rules.
3. `varint_encode` requires non-negative input (unsigned values).
4. `varint_decode` validates continuation bit chain length (< 10 bytes).
5. Fixed-size readers check buffer bounds before reading.
6. `encode` validates that all `ProtoMessage` fields map to valid wire types.
7. `decode` validates the wire format before constructing the runtime message.
8. Duplicate field numbers within a message are rejected at schema build time.

## External Dependencies
- **Runtime:** libprotobuf-c -- optional; core wire primitives are pure-XIOM
- **Install:** `apt install libprotobuf-c-dev` (Linux), `brew install protobuf-c` (macOS), vcpkg (Windows)
- **Link flags:** `-l protobuf-c`
- **Compatibility:** protobuf >= 3.0 (proto3 syntax)

## Error Handling
1. Schema validation errors at build time (duplicate numbers, invalid types).
2. Encode errors for type/size mismatches return `Err(description)`.
3. Decode errors for malformed wire format return `Err(description)`.
4. Unknown field numbers during decode are preserved (proto3 forward compatibility).
5. Varint decode errors for truncated/malformed input return `Err(description)`.
6. Fixed-size readers return `Err(description)` when buffer is too short.

## Test Coverage
- `tests/test_conformance.xi` -- 56 tests, 18 sections
- `tests/test_protobuf.xi` -- 3 integration tests (version, encode/decode roundtrip)
- Covers: varint encode/decode/roundtrip, zigzag encode/decode/roundtrip, wire tag construction/parsing, all 4 wire type field writers/readers, bool fields, sint fields, multi-field buffers, error conditions (OOB, truncated), API presence for FFI stubs
