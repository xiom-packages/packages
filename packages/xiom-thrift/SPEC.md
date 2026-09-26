# xiom.thrift -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.thrift`, version `0.1.0`).
Module: `src/thrift.xi` (`module xiom.thrift`).
Depends on `xiom.std`. The library module imports `xiom.string`,
`xiom.string.builder` and `xiom.convert`; the tests add `xiom.test`,
`xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`. No FFI.

## Scope

A pure-XIOM implementation of the Apache Thrift **binary protocol** wire
format (the classic `TBinaryProtocol`, THRIFT-0.20 spec):

- message headers in both forms -- strict (`0x80010000 | type`) and legacy
  (name first) -- with the four message types CALL 1, REPLY 2,
  EXCEPTION 3, ONEWAY 4;
- field headers (type byte + int16 id) and the STOP terminator;
- every primitive type: BOOL, BYTE (i8), DOUBLE, I16, I32, I64, STRING
  (u32 length + bytes), with big-endian fixed-width integers;
- list/set/map headers and their element/pair values (the caller drives
  the loops with the primitive readers);
- `thrift_skip`, which structurally consumes a value of any supported
  type, recursively for struct/map/list/set, and returns the number of
  bytes consumed;
- a flat struct model (`ThriftStruct`, four parallel vectors) with
  `thrift_encode_struct` / `thrift_read_struct` / `thrift_decode_struct`
  round-trips for primitive and STRING fields;
- deterministic `Err(Str)` diagnostics for every malformed input, with
  bounds checks on every read, collection-size guards and a nesting-depth
  cap for skip.

## Non-goals

- Transports: sockets, files, streams, framing (unframed only), HTTP and
  `THeader`; the codec operates on complete in-memory byte buffers.
- RPC and services: no dispatch, no message routing, no processors, no
  sequence-id correlation logic, no exception payload schema.
- The compact protocol (type-nibble/zigzag) and the JSON protocol.
- Versioned structs (the `0x8001` message version is handled, the field
  version header is not) and union/exception semantics.
- An IDL parser or code generator: schemas are read/written explicitly.
- A `Float64` convenience layer: doubles are carried as raw 64-bit IEEE-754
  bit patterns because v0.61.3 cannot bitcast `Int <-> Float64`, so an
  exact round-trip through a `Float64` cannot be produced.
- Streaming/incremental encode or decode, and arbitrary-precision or
  unsigned 64-bit integers (values must fit the signed 64-bit platform
  `Int`).

## Byte-level format

All multi-byte integers are big-endian. Byte offsets below are relative
to the start of the value.

### Message header

Strict header (the form this codec writes):

| Part | Width | Value |
|---|---|---|
| version word | 4 bytes | `0x80010000 | msg_type` (`80 01 00 0t`) |
| name | variable | u32 byte length, then that many UTF-8/ASCII bytes |
| seqid | 4 bytes | int32 sequence id, two's complement |

Legacy header (versionless, read-only except for
`thrift_write_message_begin_legacy`):

| Part | Width | Value |
|---|---|---|
| name length | 4 bytes | u32 byte length (high bit clear) |
| name | variable | that many bytes |
| msg_type | 1 byte | 1..4 |
| seqid | 4 bytes | int32 sequence id |

Detection on read: the first 4 bytes are read as a big-endian u32; if the
high bit is set the header is strict, otherwise the word is the legacy
name length. Consequently a legacy name length of 2^31 or more is not
representable (it would be read as a strict version word) and a strict
version word with the high 16 bits other than `0x8001` is rejected.

Message type codes (valid in both forms):

| Code | Meaning |
|---|---|
| 1 | CALL |
| 2 | REPLY |
| 3 | EXCEPTION |
| 4 | ONEWAY |

The decoded name must consist of printable ASCII bytes `0x20..0x7E`
(empty names are allowed); any other byte is
`thrift: invalid message name`. The name is validated after the whole
header has been consumed, so a truncated header reports truncation first.

### Field header

| Part | Width | Value |
|---|---|---|
| type | 1 byte | value type id (table below) |
| id | 2 bytes | int16 field id, two's complement |

The single byte `0x00` is STOP and terminates a struct (no id follows).
Any type byte that is not a value type id is
`thrift: unknown type id N` (this includes VOID 1, the unused ids 5, 7
and 9, and everything above 15).

### Type ids

| Id | Type | Wire value |
|---|---|---|
| 0 | STOP | struct terminator |
| 1 | (VOID) | rejected |
| 2 | BOOL | 1 byte: 1 true, 0 false |
| 3 | BYTE | 1 byte, int8 |
| 4 | DOUBLE | 8 bytes, raw IEEE-754 binary64 bit pattern |
| 5 | -- | rejected |
| 6 | I16 | 2 bytes, int16 |
| 7 | -- | rejected |
| 8 | I32 | 4 bytes, int32 |
| 9 | -- | rejected |
| 10 | I64 | 8 bytes, int64 |
| 11 | STRING | 4-byte u32 length + bytes |
| 12 | STRUCT | field headers until STOP |
| 13 | MAP | key type + value type + 4-byte i32 size + pairs |
| 14 | SET | element type + 4-byte i32 size + items |
| 15 | LIST | element type + 4-byte i32 size + items |

Primitive integer widths are exact two's-complement patterns: BYTE
covers -128..127, I16 -32768..32767, I32 and I64 the full signed ranges.
The encoders take the low 8/16/32/64 bits of the `Int` argument, so a
writer never fails; the decoders sign-extend and always return a value in
range.

### DOUBLE

A double occupies 8 bytes and is treated as an opaque 64-bit word in both
directions (`thrift_write_double_bits` / `thrift_read_double_bits`). The
sign bit is part of the pattern, so patterns with bit 63 set come back as
the corresponding negative `Int`: `1.0` is `3ff0000000000000`, `-2.0` is
`c000000000000000` and reads back as `-4611686018427387904`, `-1.5` is
`bff8000000000000` and reads back as `-4613937818241073152`. The codec
performs no NaN/infinity/subnormal classification.

### STRING

A STRING is a 4-byte unsigned length (0..4294967295) followed by exactly
that many payload bytes. Two readers exist:

- `thrift_read_binary` returns the raw bytes without any content
  validation (any byte value, including 0x00, is accepted);
- `thrift_read_string` additionally requires the payload to be valid
  UTF-8 with no 0x00 byte and materializes a `Str`.

UTF-8 validation is strict RFC 3629: ASCII `00..7F` (0x00 reported
separately as NUL), two-byte leads `C2..DF` + one continuation, three-byte
leads `E0` (next `A0..BF`), `E1..EC` (any continuation), `ED` (next
`80..9F`, surrogates rejected), `EE..EF` (any), four-byte leads `F0`
(next `90..BF`), `F1..F3` (any), `F4` (next `80..8F`); `C0`/`C1` overlong
leads and `F5..FF` are rejected. Any violation is
`thrift: invalid utf-8`; a 0x00 byte is `thrift: string contains nul`
(a NUL would abort the v0.61.3 string builder). A length that exceeds the
bytes remaining is `thrift: truncated input`.

### LIST, SET, MAP

| Container | Header |
|---|---|
| LIST | element type byte + i32 element count |
| SET | element type byte + i32 element count (identical to LIST) |
| MAP | key type byte + value type byte + i32 pair count |

Element/key/value types must be value type ids (`2,3,4,6,8,10..15`);
STOP and the rejected ids produce `thrift: unknown type id N`. The
count is signed: a negative count is `thrift: bad collection size N`.
Because every value occupies at least one byte and every map pair at
least two, a count above the bytes remaining (list/set) or above half the
bytes remaining (map) is rejected at header time as
`thrift: oversized collection`. The bound is a lower bound only: a header
within the bound can still fail later, element by element, with
`thrift: truncated input`.

The codec reads and writes headers and values; the caller owns the loops
(one primitive read per element, `thrift_skip` may be used for unknown
values).

### Skip

`thrift_skip(r, ftype)` consumes one value at the cursor and returns its
byte length:

| ftype | Consumed |
|---|---|
| BOOL / BYTE | 1 |
| I16 | 2 |
| I32 | 4 |
| I64 / DOUBLE | 8 |
| STRING | 4 + length |
| STRUCT | field headers and values until STOP |
| SET / LIST | header + every element (recursively) |
| MAP | header + every key and value (recursively) |

Skip is structural: type ids, bounds and container headers (including the
oversized guard) are validated, but scalar payloads are not (a skipped
BOOL may hold any byte). Unknown `ftype` -- including STOP -- is
`thrift: unknown type id N`. Containers count against a nesting limit:
the value passed in has depth 0, its children depth 1, and a container at
depth 64 is `thrift: nesting depth exceeds limit of 64`
(`thrift_max_depth()` is 64, so 64 nested containers are accepted and 65
are rejected).

### Flat struct model

`ThriftStruct` represents one struct as four parallel vectors, all of the
same length (no `Vec[StructType]` is possible in v0.61.3):

| Vector | Meaning |
|---|---|
| `ids` | int16 field id |
| `types` | type code |
| `ints` | value of a BOOL (0/1), BYTE, DOUBLE (bit pattern), I16, I32 or I64 field; 0 for STRING |
| `bytes` | payload of a STRING field; empty for every other type |

Encoding writes each field header followed by its value and ends with
STOP. Decoding (`thrift_read_struct`) reads field headers until STOP and
fills the four vectors in parallel; only primitive and STRING fields are
supported, so a STRUCT/MAP/SET/LIST field is
`thrift: struct field type not supported` (use the collection readers or
`thrift_skip` for those). `thrift_decode_struct` wraps the reader and
requires every byte of the buffer to be consumed
(`thrift: trailing data` otherwise).

`thrift_encode_struct` validates in this order: the four vector lengths
must match (`thrift: struct vectors length mismatch`), then per field in
wire order the id must fit int16 (`thrift: field id out of range`), the
type must be a known value type (`thrift: unknown type id N`), the type
must not be a container (`thrift: struct field type not supported`), and
a BOOL value must be 0 or 1 (`thrift: invalid bool value`). The first
failure aborts; no partial output is returned.

## API signatures

All functions are free functions in module `xiom.thrift` (no self
methods):

```xi
pub type ThriftWriter = { data: Vec[UInt8]; }
pub type ThriftReader = { data: Vec[UInt8]; pos: Int; }
pub type ThriftMessage = { name: Str; msg_type: Int; seqid: Int; strict: Bool; }
pub type ThriftField = { ftype: Int; fid: Int; }
pub type ThriftListHeader = { etype: Int; size: Int; }
pub type ThriftMapHeader = { ktype: Int; vtype: Int; size: Int; }
pub type ThriftStruct = { ids: Vec[Int]; types: Vec[Int]; ints: Vec[Int]; bytes: Vec[Vec[UInt8]]; }

pub fn thrift_protocol_version() -> Int
pub fn thrift_max_depth() -> Int
pub fn thrift_t_stop() -> Int
pub fn thrift_t_bool() -> Int
pub fn thrift_t_byte() -> Int
pub fn thrift_t_double() -> Int
pub fn thrift_t_i16() -> Int
pub fn thrift_t_i32() -> Int
pub fn thrift_t_i64() -> Int
pub fn thrift_t_string() -> Int
pub fn thrift_t_struct() -> Int
pub fn thrift_t_map() -> Int
pub fn thrift_t_set() -> Int
pub fn thrift_t_list() -> Int
pub fn thrift_msg_call() -> Int
pub fn thrift_msg_reply() -> Int
pub fn thrift_msg_exception() -> Int
pub fn thrift_msg_oneway() -> Int
pub fn thrift_type_known(t: Int) -> Bool

pub fn thrift_writer_new() -> ThriftWriter
pub fn thrift_writer_len(w: &ThriftWriter) -> Int
pub fn thrift_writer_bytes(w: &ThriftWriter) -> Vec[UInt8]
pub fn thrift_reader_new(data: Vec[UInt8]) -> ThriftReader
pub fn thrift_reader_pos(r: &ThriftReader) -> Int
pub fn thrift_reader_remaining(r: &ThriftReader) -> Int

pub fn thrift_write_message_begin(w: &mut ThriftWriter, name: Str, msg_type: Int, seqid: Int)
pub fn thrift_write_message_begin_legacy(w: &mut ThriftWriter, name: Str, msg_type: Int, seqid: Int)
pub fn thrift_read_message_begin(r: &mut ThriftReader) -> Result[ThriftMessage, Str]

pub fn thrift_write_field_begin(w: &mut ThriftWriter, ftype: Int, fid: Int)
pub fn thrift_write_field_stop(w: &mut ThriftWriter)
pub fn thrift_read_field_begin(r: &mut ThriftReader) -> Result[ThriftField, Str]

pub fn thrift_write_bool(w: &mut ThriftWriter, v: Bool)
pub fn thrift_read_bool(r: &mut ThriftReader) -> Result[Bool, Str]
pub fn thrift_write_byte(w: &mut ThriftWriter, v: Int)
pub fn thrift_read_byte(r: &mut ThriftReader) -> Result[Int, Str]
pub fn thrift_write_i16(w: &mut ThriftWriter, v: Int)
pub fn thrift_read_i16(r: &mut ThriftReader) -> Result[Int, Str]
pub fn thrift_write_i32(w: &mut ThriftWriter, v: Int)
pub fn thrift_read_i32(r: &mut ThriftReader) -> Result[Int, Str]
pub fn thrift_write_i64(w: &mut ThriftWriter, v: Int)
pub fn thrift_read_i64(r: &mut ThriftReader) -> Result[Int, Str]
pub fn thrift_write_double_bits(w: &mut ThriftWriter, bits: Int)
pub fn thrift_read_double_bits(r: &mut ThriftReader) -> Result[Int, Str]
pub fn thrift_write_binary(w: &mut ThriftWriter, data: &Vec[UInt8])
pub fn thrift_read_binary(r: &mut ThriftReader) -> Result[Vec[UInt8], Str]
pub fn thrift_write_string(w: &mut ThriftWriter, s: Str)
pub fn thrift_read_string(r: &mut ThriftReader) -> Result[Str, Str]

pub fn thrift_write_list_begin(w: &mut ThriftWriter, etype: Int, size: Int)
pub fn thrift_write_set_begin(w: &mut ThriftWriter, etype: Int, size: Int)
pub fn thrift_write_map_begin(w: &mut ThriftWriter, ktype: Int, vtype: Int, size: Int)
pub fn thrift_read_list_header(r: &mut ThriftReader) -> Result[ThriftListHeader, Str]
pub fn thrift_read_set_header(r: &mut ThriftReader) -> Result[ThriftListHeader, Str]
pub fn thrift_read_map_header(r: &mut ThriftReader) -> Result[ThriftMapHeader, Str]
pub fn thrift_skip(r: &mut ThriftReader, ftype: Int) -> Result[Int, Str]

pub fn thrift_read_struct(r: &mut ThriftReader) -> Result[ThriftStruct, Str]
pub fn thrift_encode_struct(s: &ThriftStruct) -> Result[Vec[UInt8], Str]
pub fn thrift_decode_struct(data: Vec[UInt8]) -> Result[ThriftStruct, Str]
pub fn thrift_struct_count(s: &ThriftStruct) -> Int
pub fn thrift_struct_id(s: &ThriftStruct, i: Int) -> Int
pub fn thrift_struct_type(s: &ThriftStruct, i: Int) -> Int
pub fn thrift_struct_int(s: &ThriftStruct, i: Int) -> Int
pub fn thrift_struct_bytes(s: &ThriftStruct, i: Int) -> Vec[UInt8]
pub fn thrift_struct_field_index(s: &ThriftStruct, id: Int) -> Int

pub fn thrift_message_name(m: &ThriftMessage) -> Str
pub fn thrift_message_type(m: &ThriftMessage) -> Int
pub fn thrift_message_seqid(m: &ThriftMessage) -> Int
pub fn thrift_message_strict(m: &ThriftMessage) -> Bool
pub fn thrift_field_type(f: &ThriftField) -> Int
pub fn thrift_field_id(f: &ThriftField) -> Int
pub fn thrift_list_header_type(h: &ThriftListHeader) -> Int
pub fn thrift_list_header_size(h: &ThriftListHeader) -> Int
pub fn thrift_map_header_key_type(h: &ThriftMapHeader) -> Int
pub fn thrift_map_header_value_type(h: &ThriftMapHeader) -> Int
pub fn thrift_map_header_size(h: &ThriftMapHeader) -> Int
```

## Semantics and check order

`thrift_read_message_begin(r)`
: Requires 4 bytes (`truncated` otherwise). Reads the first word as an
  unsigned 32-bit big-endian value. High bit set: the high 16 bits must
  equal `0x8001` (`bad strict version`) and the low 16 bits must encode a
  message type 1..4 (`unknown message type N`); then the name string and
  the int32 seqid are read with the string rules below, and finally the
  name bytes are validated (`invalid message name`). High bit clear: the
  word is the name length; `length + 5` must fit the bytes remaining
  (`truncated`), then the name bytes, one type byte 1..4, and the int32
  seqid are read, and the name is validated. The returned message records
  `strict` accordingly. A malformed name is reported only after the whole
  header parses, so truncation wins over name validation.

`thrift_read_field_begin(r)`
: One byte must remain (`truncated`). Byte 0 is STOP and yields
  `ftype = 0, fid = 0`; any other byte must be a value type id
  (`unknown type id N`), then a 2-byte int16 id is read (`truncated` if
  cut short).

`thrift_read_bool(r)`
: One byte; 0 -> false, 1 -> true, anything else is `invalid bool value`.

`thrift_read_byte` / `thrift_read_i16` / `thrift_read_i32` / `thrift_read_i64`
: Read 1/2/4/8 bytes big-endian (`truncated` if short) and sign-extend to
  the signed range. The I64 reader accumulates the low 63 bits first and
  applies the sign bit afterwards, so every 64-bit pattern (including
  `INT64_MIN`) round-trips exactly.

`thrift_read_double_bits(r)`
: The I64 read; the bits are returned verbatim (the sign bit makes most
  non-positive patterns negative `Int` values).

`thrift_read_binary(r)`
: A 4-byte unsigned length (`truncated` if the length word itself is
  short), then the payload (`truncated` if `length` exceeds the bytes
  remaining). No content validation.

`thrift_read_string(r)`
: `thrift_read_binary`, then NUL detection
  (`string contains nul`) and strict UTF-8 validation
  (`invalid utf-8`), then materialization. The first offending byte wins;
  the message does not carry a position.

`thrift_read_list_header` / `thrift_read_set_header(r)`
: One element-type byte must remain (`truncated`); it must be a value
  type (`unknown type id N`), then a 4-byte signed count (`truncated`),
  then `count < 0` is `bad collection size N` and
  `count > bytes remaining` is `oversized collection`. Both headers are
  identical on the wire.

`thrift_read_map_header(r)`
: Key type byte, value type byte, then a 4-byte signed count, each
  validated as above; the oversized bound is `count > (bytes remaining) / 2`.

`thrift_skip(r, ftype)`
: Dispatches by type. Scalar sizes are consumed with bounds checks
  (`truncated`); STRING reads a length and skips the payload
  (`truncated` when short); STRUCT loops on field headers until STOP;
  MAP loops over `size` pairs; SET/LIST loop over `size` elements.
  Containers at depth 64 are `nesting depth exceeds limit of 64`. Any
  unknown type id (STOP included) is `unknown type id N`. The function
  returns the number of bytes consumed; on error the cursor position is
  unspecified (it has advanced by the successfully skipped prefix).

`thrift_read_struct(r)`
: Field headers until STOP; BOOL -> `thrift_read_bool`, STRING ->
  `thrift_read_binary` (raw), DOUBLE -> `thrift_read_double_bits`,
  BYTE/I16/I32/I64 -> `thrift_read_*`; everything else (including
  STRUCT/MAP/SET/LIST) is `struct field type not supported`. Errors from
  the value readers propagate unchanged. All four vectors receive exactly
  one entry per field, so they stay parallel.

`thrift_encode_struct(s)`
: Validates the parallel lengths, then per field in order: id in
  `-32768..32767`, known value type, not a container, BOOL value 0/1;
  writes field header + value; appends STOP. A STRING field writes
  `bytes[i]` verbatim, a BOOL field writes 1 when `ints[i] == 1`.

`thrift_decode_struct(data)`
: `thrift_read_struct` on a fresh reader plus a trailing-data check.

Writer functions
: Never fail and never validate; they write the low bits of their
  arguments (BYTE/I16/I32/I64 sign-extend, so out-of-range values are
  truncated silently) and the exact bytes of a `Str`/`&Vec[UInt8]`
  payload. `thrift_write_bool` writes 1 or 0.

Accessors
: `thrift_struct_id`/`type` return -1 out of range, `thrift_struct_int`
  returns 0, `thrift_struct_bytes` returns an empty vector, and
  `thrift_struct_field_index` returns -1 when the id is absent (the first
  match when ids repeat). `thrift_reader_remaining` returns 0 when the
  cursor is at or past the end.

## Error string catalog

| Condition | Error text |
|---|---|
| Any read past the end of the buffer, including a short length prefix or payload | `thrift: truncated input` |
| Strict version word whose high 16 bits are not `0x8001` | `thrift: bad strict version` |
| Message type (strict low bits or legacy byte) not in 1..4 | `thrift: unknown message type N` |
| Message name byte outside printable ASCII `0x20..0x7E` | `thrift: invalid message name` |
| Type byte / element type / key or value type that is not a value type id (STOP, VOID, 5, 7, 9, 16+) | `thrift: unknown type id N` |
| Negative map/list/set count | `thrift: bad collection size N` |
| List/set count above the bytes remaining, or map count above half the bytes remaining | `thrift: oversized collection` |
| BOOL byte other than 0 or 1 | `thrift: invalid bool value` |
| STRING payload that is not valid UTF-8 (overlong, surrogate, truncated, out of range) | `thrift: invalid utf-8` |
| STRING payload containing a 0x00 byte (read as `Str` only) | `thrift: string contains nul` |
| Container nested at depth 64 or more in `thrift_skip` | `thrift: nesting depth exceeds limit of 64` |
| Bytes left after the STOP in `thrift_decode_struct` | `thrift: trailing data` |
| `ThriftStruct` parallel vector lengths differ | `thrift: struct vectors length mismatch` |
| Struct field of type STRUCT/MAP/SET/LIST in the flat model | `thrift: struct field type not supported` |
| Struct field id outside int16 in `thrift_encode_struct` | `thrift: field id out of range` |

Error precedence is the check order above. Reads report the first failure
and leave the cursor advanced by whatever was consumed successfully;
`Err` never carries a partial value.

## Complexity

| Operation | Complexity |
|---|---|
| Writer lifecycle (`new`/`len`/`bytes`) | O(1) / O(written bytes) |
| Reader lifecycle (`new`/`pos`/`remaining`) | O(1) |
| Message header, field header, every primitive by value | O(1) |
| Message header by name length | O(name bytes) |
| `thrift_read_string` / `thrift_write_string` / `thrift_read_binary` / `thrift_write_binary` | O(payload bytes) |
| `thrift_read_list_header` / `thrift_read_set_header` / `thrift_read_map_header` | O(1) |
| `thrift_skip` | O(skipped bytes) |
| `thrift_read_struct` / `thrift_encode_struct` / `thrift_decode_struct` | O(fields + string bytes) |
| Struct accessors | O(1); `thrift_struct_field_index` is O(fields) |
| `thrift_struct_bytes` | O(payload length) |

## Test plan

`tests/test_conformance.xi` (`module thrift_tests`, 24 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). All buffers are synthetic hex literals
decoded in-test; no external data files. Coverage:

1. strict message header bytes for all four message types (including an
   empty name) plus `thrift_protocol_version`;
2. strict message decode: name via `str_compare`, type, seqid, strict
   flag, cursor exhaustion;
3. legacy message decode and `thrift_write_message_begin_legacy`;
4. message header errors: bad version, unknown type (strict and legacy),
   truncated at every prefix length, invalid name byte;
5. field headers: encode/decode, negative id, STOP semantics, cursor;
6. field header errors: unknown ids 1/5/7, truncated byte and short id,
   `thrift_type_known` boundaries;
7. BOOL bytes, decode, invalid byte, truncation;
8. BYTE boundaries 0/127/-1/-128 and truncation;
9. I16 boundaries 256/-32768/32767/-1 and truncation;
10. I32 boundaries INT32_MAX/INT32_MIN/-1/65536;
11. I64 boundaries INT64_MAX/INT64_MIN/-1/2^32 and truncation;
12. DOUBLE exact patterns 1.0/-2.0/-1.5/0.0, including negative bit
    patterns reading back as negative Ints;
13. STRING write/read round-trip ("héllo", empty, binary with 0x00 and
    0xFF, valid 4-byte UTF-8 emoji);
14. STRING validation errors: NUL, overlong C0 AF, truncated C3,
    surrogate ED A0 80, F5 lead, length overruns;
15. LIST header, writer bytes, negative size, oversized size, unknown
    element type, truncation;
16. MAP header, writer bytes, negative size, oversized size, unknown key
    and value types, truncation;
17. SET header layout equal to LIST plus a value read after the header;
18. skip of every primitive type with returned byte counts and
    end-of-buffer, truncated and unknown-type ids;
19. recursive skip through a struct nesting a LIST, a MAP, a STRUCT and
    a SET, field by field, with exact consumed counts;
20. skip depth cap: 64 nested structs accepted (63 field headers plus an
    empty innermost struct, 253 bytes), 65 rejected;
21. flat struct model: exact encoded bytes for a 3-field struct and an
    8-field round-trip covering every representable type;
22. struct model errors: vector-length drift, unknown type, unsupported
    container type, invalid BOOL, id out of range, decode trailing data,
    unsupported field, bad BOOL and truncation;
23. composite message (strict header + I32/STRING/LIST/MAP fields)
    decoded twice: once value by value, once entirely with `thrift_skip`;
24. reader/writer lifecycle accessors and every type/message constant.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.thrift
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Binary protocol only: no compact/JSON protocols, no `THeader` or
  framing, no transports and no RPC layer.
- No IDL parser or generated code; schemas are explicit.
- Doubles are opaque bit patterns; there is no `Float64` API.
- Strict BOOL decoding (0/1 only) and strict STRING decoding (UTF-8, no
  NUL) on the string path; `thrift_read_binary` is the raw alternative.
- Collection-size guards are lower bounds (1 byte per element, 2 per
  pair); they bound hostile headers but do not pre-validate element sizes.
- Skip nesting is capped at 64; the struct model is flat and holds no
  container fields. `ThriftStruct` duplicates ids keep their wire order
  and lookup returns the first.
- `thrift_skip` validates structure, not scalar contents.
- Writers cannot report errors; they truncate integer arguments to the
  target width silently. `thrift_encode_struct` is the validating writer.
- Value accessors copy (`thrift_writer_bytes`, `thrift_struct_bytes`);
  plain value types, not thread-safe.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers `_ok_*` /
  `_err_*` (one pair per result type); constructing Results for struct
  payloads inside other functions miscompiles.
- No `==` is applied to a `Str` read from a `Vec[Str]` (no `Vec[Str]` is
  used at all); no `Vec[StructType]`, no `Vec[Float64]`, no `Vec[fn]`
  dispatch, no lambdas, no `self` methods.
- Every byte read from a `Vec[UInt8]` is widened once with
  `(b as Int) & 0xFF` before entering Int arithmetic or comparisons.
- Every `Vec` element read is bound to an explicitly typed local first.
- Struct fields are never passed as `&struct.field` where a
  `&Vec[UInt8]` parameter is expected; the writer/reader helpers take
  `&ThriftWriter` / `&ThriftReader` and touch `w.data` / `r.data`
  directly, and returned vectors are copied element by element.
- Big-endian encoding uses arithmetic byte extraction (`_be_byte`); I64
  decoding accumulates 63 bits and applies the sign afterwards, so no
  intermediate overflows. Bit operators are never used.
- `Str` output is built by `xiom.string.builder.sb_to_str` only after the
  bytes were validated as NUL-free UTF-8 (strings) or printable ASCII
  (message names).
- The package declares no `extern "C"` blocks (no FFI).
