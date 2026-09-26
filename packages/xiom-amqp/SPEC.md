# xiom.amqp byte-level specification

This document describes exactly what `xiom.amqp` (version 0.1.0) parses and
serializes. It is the implemented subset of AMQP 0-9-1 framing, written
against the wire format rather than the full protocol grammar. Everything
not described here is either rejected with a deterministic error (see the
error catalog) or explicitly out of scope (see Limitations).

All multi-byte integers are unsigned big-endian unless stated otherwise.
`u8`/`u16`/`u32`/`u64` are the wire widths; `Int` is the XIOM 64-bit signed
integer used internally.

## 1. Protocol header (8 bytes)

```
offset  size  field
0       4     magic: 0x41 0x4D 0x51 0x50 ("AMQP")
4       1     0x00
5       1     protocol major: 0x00
6       1     protocol minor: 0x09
7       1     revision: 0x01 (0-9-1) or 0x00 (0-9)
```

* `amqp_encode_protocol_header()` emits the canonical 0-9-1 header.
* `amqp_encode_protocol_header_rev(rev)` accepts revision 0 or 1 only.
* `amqp_parse_protocol_header(data)` requires at least 8 bytes, validates
  every fixed byte, accepts revision 0 or 1 and returns the revision as an
  `Int`. Trailing bytes after offset 7 are ignored so a stream position can
  advance past the header.

## 2. Generic frame header

```
offset  size  field
0       1     frame type: 1 = method, 2 = content header, 3 = body,
                        8 = heartbeat
1       2     channel (u16)
3       4     payload size (u32)
7       n     payload (n = payload size)
7+n     1     frame end: 0xCE
```

`amqp_parse_frame_header(data, frame_max)` parses exactly one complete
frame and requires the whole buffer to be consumed; `frame_max` bounds the
payload size (`frame_max < 8` is rejected outright). It returns an
`AmqpFrameHeader { frame_type, channel, payload_size, payload_start (always
7), frame_len (8 + payload_size) }`.

Rejections: unknown frame type octet; `frame_max < 8`; payload size above
`frame_max`; missing header/payload/frame-end; frame-end octet other than
0xCE (compared only after widening, so 0xCE is handled correctly); extra
bytes after the frame.

## 3. Method frames

Frame type 1 payload:

```
offset  size  field
0       2     class-id (u16)
2       2     method-id (u16)
4       ...   arguments, per the schema for (class-id, method-id)
```

`amqp_parse_method_frame` must consume the payload exactly.
`amqp_encode_method_frame` validates the argument nodes against the schema
(count, order and kind), then serializes.

### 3.1 Implemented methods and argument schemas

Argument type codes: `o` octet, `s` short, `l` long, `L` long-long,
`a` shortstr, `S` longstr, `F` table, `A` array, `b` bit.

| class (id) | method (id) | schema |
|---|---|---|
| connection (10) | start (10) | o o F S S |
| connection (10) | start-ok (11) | F a S a |
| connection (10) | tune (30) | s l s |
| connection (10) | tune-ok (31) | s l s |
| connection (10) | open (40) | a a b |
| connection (10) | open-ok (41) | a |
| connection (10) | close (50) | s a s s |
| connection (10) | close-ok (51) | (none) |
| channel (20) | open (10) | a |
| channel (20) | open-ok (11) | S |
| channel (20) | close (40) | s a s s |
| channel (20) | close-ok (41) | (none) |
| exchange (40) | declare (10) | s a a b b b b b F |
| exchange (40) | delete (20) | s a b b |
| exchange (40) | bind (30) | s a a a b F |
| exchange (40) | unbind (40) | s a a a b F |
| queue (50) | declare (10) | s a b b b b b F |
| queue (50) | declare-ok (11) | a l l |
| queue (50) | bind (20) | s a a a b F |
| queue (50) | unbind (50) | s a a a F |
| queue (50) | purge (30) | s a b |
| queue (50) | purge-ok (31) | l |
| queue (50) | delete (40) | s a b b b |
| queue (50) | delete-ok (41) | l |
| basic (60) | qos (10) | l s b |
| basic (60) | qos-ok (11) | (none) |
| basic (60) | publish (40) | s a a b b |
| basic (60) | return (50) | s a a a |
| basic (60) | deliver (60) | a L b a a |
| basic (60) | ack (80) | L b |
| basic (60) | nack (120) | L b b |

Any other (class-id, method-id) pair returns `amqp: unknown method`.

### 3.2 Argument encodings

| type | encoding |
|---|---|
| octet | 1 byte |
| short | 2 bytes |
| long | 4 bytes |
| long-long | 8 bytes (values >= 2^63 rejected) |
| shortstr | u8 length + bytes (encoder rejects > 255 bytes) |
| longstr | u32 length + bytes |
| table | u32 byte-length + entries (see 3.3) |
| array | u32 byte-length + values (see 3.3) |
| bit | packed (see 3.4) |

### 3.3 Field tables and field arrays

A table is `u32 byte-length` followed by that many bytes of entries. Each
entry is a `shortstr` key followed by a tagged field value:

| tag | byte | value encoding |
|---|---|---|
| t | 0x74 | 1 byte bool, must be 0 or 1 |
| f | 0x66 | 4 bytes (raw IEEE-754 single bits) |
| s | 0x73 | 2 bytes, signed 16-bit |
| I | 0x49 | 4 bytes, signed 32-bit |
| l | 0x6C | 8 bytes, signed 64-bit |
| D | 0x44 | 1 byte scale + 4 bytes signed 32-bit value |
| b | 0x62 | 1 byte, signed 8-bit |
| A | 0x41 | u32 byte-length + field values (no keys) |
| T | 0x54 | 8 bytes, u64 seconds (>= 2^63 rejected) |
| F | 0x46 | u32 byte-length + table entries |
| V | 0x56 | no payload |
| x | 0x78 | u32 length + bytes |

No other field tag is accepted (`amqp: bad field tag`); in particular the
AMQP 'S' long-string tag is outside this codec's subset.

Tables and arrays nest freely up to 32 open containers; deeper input is
rejected with `amqp: table nesting too deep`. Container byte lengths must
fit inside their parent exactly; mismatches are `amqp: bad table` or
`amqp: bad array`.

### 3.4 Bits

Consecutive `bit` arguments in one schema are packed LSB-first into
octets: the first bit is bit 0, the eighth bit is bit 7 of the first octet,
the ninth starts the next octet. A partial octet is flushed before any
non-bit argument and at the end of the payload; consumers discard the
remaining padding bits. Decoders read the same way, so canonical encodings
round-trip byte-for-byte.

## 4. Content header frames

Frame type 2 payload (class 60 only):

```
offset  size  field
0       2     class-id: must be 60 (basic)
2       2     weight: must be 0
4       8     body-size (u64, values >= 2^63 rejected)
12      2     property flags (one u16 word)
14      ...   property values, in flag-bit order
```

The property flag word:

| bit | value | property | encoding |
|---|---|---|---|
| 15 | 0x8000 | content-type | shortstr |
| 14 | 0x4000 | content-encoding | shortstr |
| 13 | 0x2000 | headers | table (u32 length + entries, **no tag**) |
| 12 | 0x1000 | delivery-mode | octet |
| 11 | 0x0800 | priority | octet |
| 10 | 0x0400 | correlation-id | shortstr |
| 9  | 0x0200 | reply-to | shortstr |
| 8  | 0x0100 | expiration | shortstr |
| 7  | 0x0080 | message-id | shortstr |
| 6  | 0x0040 | timestamp | 8 bytes u64 |
| 5  | 0x0020 | type | shortstr |
| 4  | 0x0010 | user-id | shortstr |
| 3  | 0x0008 | app-id | shortstr |

Bits 2 (cluster-id), 1 and 0 are not supported: bit 0 (continuation)
yields `amqp: bad property flags`, bits 1..2 yield
`amqp: unsupported property`. `amqp_basic_flag(index)` returns the flag
value for property `index` 0..12 (0 = content-type).

`headers` decodes into an `AmqpTree`; when the headers bit is clear the
tree is empty, and a non-empty tree with the bit clear is rejected on
encode (`amqp: headers not flagged`). An empty tree with the bit set
encodes as a zero-length table.

## 5. Body frames

Frame type 3, payload is an opaque body chunk of any size (including zero)
up to `frame_max` on parse. No interpretation is performed.

## 6. Heartbeat frames

Frame type 8. The payload must be empty and the channel must be 0
(`amqp: bad heartbeat` otherwise). `amqp_encode_heartbeat_frame(channel)`
accepts channel 0 only.

## 7. Decoded value tree

Field tables/arrays and method arguments decode into `AmqpTree`, five
index-aligned vectors in document order (pre-order, with explicit
end-of-container nodes):

* `kinds[i]`: 1 octet, 2 short, 3 long, 4 long-long, 5 shortstr,
  6 longstr, 7 table, 8 array, 9 bit, 20..31 field values (matches the
  `amqp_kind_f_*` accessors), 99 end marker.
* `keys[i]`: shortstr key when the node is a table entry (empty for
  array elements and top-level arguments).
* `ints[i]`: integer value (raw IEEE-754 bits for `f`, decimal value for
  `D`); `aux[i]`: decimal scale.
* `strs[i]`: shortstr/longstr/byte-array payload.

A container node's direct children follow it immediately and stop at the
matching `kind == 99`. Navigation helpers: `amqp_tree_arg_count`,
`amqp_tree_arg_node`, `amqp_tree_kid_count`, `amqp_tree_kid_node`,
`amqp_tree_find_key`, plus per-node accessors.

## 8. Error catalog

Every error message starts with `amqp: ` and is deterministic.

| message | produced by |
|---|---|
| `amqp: truncated protocol header` | protocol header shorter than 8 bytes |
| `amqp: bad protocol header` | wrong magic, major, minor or reserved byte |
| `amqp: bad protocol revision` | revision other than 0 or 1 |
| `amqp: bad frame max` | `frame_max < 8` |
| `amqp: truncated frame` | header, payload or frame end missing |
| `amqp: bad frame type` | type octet outside 1/2/3/8, or typed parser mismatch |
| `amqp: frame too large` | payload size above `frame_max` |
| `amqp: bad frame end` | closing octet is not 0xCE |
| `amqp: trailing bytes` | buffer extends past the frame/payload |
| `amqp: bad channel` | channel outside 0..65535 on encode |
| `amqp: bad class id` / `amqp: bad method id` | u16 range violation on encode |
| `amqp: unknown method` | (class, method) outside the subset |
| `amqp: truncated method` | method payload shorter than 4 bytes |
| `amqp: truncated arguments` | schema args do not fit the payload |
| `amqp: bad argument count` | node count differs from the schema |
| `amqp: bad argument kind` | node kind differs from the schema |
| `amqp: bad bit` | bit value other than 0/1 on encode |
| `amqp: value out of range` | numeric value outside its wire width |
| `amqp: string too long` | shortstr > 255, longstr/bytes > 2^31-1 |
| `amqp: truncated string` | shortstr/longstr length overruns its bound |
| `amqp: truncated field` | field value bytes missing |
| `amqp: bad table` / `amqp: bad array` | container length/framing mismatch |
| `amqp: bad bool` | field bool octet other than 0/1 |
| `amqp: bad field tag` | unsupported field-value tag |
| `amqp: table nesting too deep` | more than 32 open containers |
| `amqp: integer out of range` | 64-bit value >= 2^63 |
| `amqp: bad content class` | content header class other than 60 |
| `amqp: bad weight` | content header weight other than 0 |
| `amqp: bad property flags` | bit 0 set or bits outside 15..3 |
| `amqp: unsupported property` | cluster-id bit (2) set |
| `amqp: truncated content header` | fixed part shorter than 14 bytes |
| `amqp: truncated property` | property value bytes missing |
| `amqp: headers not flagged` | headers tree non-empty with bit 13 clear |
| `amqp: bad heartbeat` | heartbeat with payload or non-zero channel |
| `amqp: bad value kind` | tree node kind not valid in its space |

## 9. Limitations

* One frame per buffer: parsers require the buffer to end exactly at the
  frame end. Callers with concatenated frames must slice them first.
* Only the methods in section 3.1 decode; other AMQP 0-9-1 methods (for
  example `basic.consume`, `basic.reject`, `confirm.*`) are rejected.
* Only the field tags in section 3.3 are supported; `S` long strings and
  the remaining AMQP field tags are rejected.
* `Int` is signed 64-bit: unsigned values >= 2^63 (body sizes, timestamps,
  `long-long` arguments and `T`/`l` fields with bit 63 set) are rejected as
  out of range.
* The content header supports a single property-flag word; the
  continuation bit and property bits below 3 are rejected.
* `frame_max` bounds the payload size, not the total frame size; callers
  may pass the negotiated `frame-max - 8`. Encoders do not enforce
  `frame_max`.
* Heartbeat frames are accepted on channel 0 only.
* Floats in field tables are transported as raw 32-bit patterns; no
  Float64 conversion is performed.
* Decoded method frames keep arguments as a generic value tree; there are
  no per-method struct views.
