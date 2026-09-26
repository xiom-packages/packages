# xiom.thrift

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM Apache Thrift **binary protocol** codec (the classic
> `TBinaryProtocol` wire format): message headers (strict and legacy),
> field headers, all primitive types, list/set/map headers, recursive
> skip, and a flat struct model. No transport, no RPC, no compact/JSON
> protocols, no IDL parser.
> **Deps:** `xiom.std` only. The library module uses `xiom.string`,
> `xiom.string.builder` and `xiom.convert`; the tests add `xiom.test`,
> `xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`. No FFI.

## What it is

`xiom.thrift` encodes and decodes the Thrift binary protocol wire format
(THRIFT-0.20 spec), without any transport or service layer:

```
message header   strict: 0x80010000 | type, name string, int32 seqid
                 legacy: name string, type byte, int32 seqid (read only)
field header     type byte + int16 field id; STOP 0 ends a struct
primitives       i8/i16/i32/i64 big-endian, bool byte, double bits,
                 string = u32 length + bytes
containers       list/set: element type + i32 size + items
                 map: key type + value type + i32 size + pairs
```

Every type has an encoder and a bounds-checked decoder, plus
`thrift_skip` to structurally consume any value (recursively for
struct/map/list/set). Doubles travel as their raw 64-bit IEEE-754 bit
pattern because XIOM v0.61.3 has no `Int <-> Float64` bitcast, so an
exact round-trip is only possible from the bit pattern.

## API

| Function | Returns | Description |
|---|---|---|
| `thrift_writer_new()` | `ThriftWriter` | Fresh encoder buffer. |
| `thrift_writer_len(w)` | `Int` | Bytes written so far. |
| `thrift_writer_bytes(w)` | `Vec[UInt8]` | Copy of the written bytes. |
| `thrift_reader_new(data)` | `ThriftReader` | Bounds-checked cursor reader. |
| `thrift_reader_pos(r)` / `thrift_reader_remaining(r)` | `Int` | Cursor position / bytes left. |
| `thrift_write_message_begin(w, name, msg_type, seqid)` | `Unit` | Strict message header. |
| `thrift_write_message_begin_legacy(w, name, msg_type, seqid)` | `Unit` | Legacy (versionless) header. |
| `thrift_read_message_begin(r)` | `Result[ThriftMessage, Str]` | Decode strict or legacy header. |
| `thrift_write_field_begin(w, ftype, fid)` | `Unit` | Field type byte + int16 id. |
| `thrift_write_field_stop(w)` | `Unit` | Struct terminator (STOP 0). |
| `thrift_read_field_begin(r)` | `Result[ThriftField, Str]` | Decode field header (`ftype` 0 = STOP). |
| `thrift_write_bool(w, v)` / `thrift_read_bool(r)` | `Unit` / `Result[Bool, Str]` | BOOL byte, 1 = true. |
| `thrift_write_byte(w, v)` / `thrift_read_byte(r)` | `Unit` / `Result[Int, Str]` | int8. |
| `thrift_write_i16(w, v)` / `thrift_read_i16(r)` | `Unit` / `Result[Int, Str]` | int16. |
| `thrift_write_i32(w, v)` / `thrift_read_i32(r)` | `Unit` / `Result[Int, Str]` | int32. |
| `thrift_write_i64(w, v)` / `thrift_read_i64(r)` | `Unit` / `Result[Int, Str]` | int64. |
| `thrift_write_double_bits(w, bits)` / `thrift_read_double_bits(r)` | `Unit` / `Result[Int, Str]` | Raw IEEE-754 bit pattern. |
| `thrift_write_binary(w, data)` / `thrift_read_binary(r)` | `Unit` / `Result[Vec[UInt8], Str]` | STRING bytes, unvalidated. |
| `thrift_write_string(w, s)` / `thrift_read_string(r)` | `Unit` / `Result[Str, Str]` | STRING as UTF-8 `Str`. |
| `thrift_write_list_begin(w, etype, size)` / `thrift_read_list_header(r)` | `Unit` / `Result[ThriftListHeader, Str]` | LIST header. |
| `thrift_write_set_begin(w, etype, size)` / `thrift_read_set_header(r)` | `Unit` / `Result[ThriftListHeader, Str]` | SET header (list layout). |
| `thrift_write_map_begin(w, ktype, vtype, size)` / `thrift_read_map_header(r)` | `Unit` / `Result[ThriftMapHeader, Str]` | MAP header. |
| `thrift_skip(r, ftype)` | `Result[Int, Str]` | Skip a value, returns bytes consumed. |
| `thrift_encode_struct(s)` | `Result[Vec[UInt8], Str]` | Encode a flat struct. |
| `thrift_read_struct(r)` / `thrift_decode_struct(data)` | `Result[ThriftStruct, Str]` | Decode a flat struct (the latter requires all bytes consumed). |
| `thrift_struct_count/id/type/int/bytes/field_index` | accessors | Read the parallel vectors back. |
| `thrift_t_*`, `thrift_msg_*`, `thrift_protocol_version()`, `thrift_max_depth()`, `thrift_type_known(t)` | `Int` / `Bool` | Codec metadata. |

Errors are deterministic `thrift: ...` strings; the exact catalog and
check order are in SPEC.md.

## Usage

```xi
use xiom.thrift;
use xiom.io;
use xiom.string.compare;

fn main() -> Int {
  // Encode: CALL "add" seqid 7 with fields { 1: I32 3, 2: I32 4 }.
  var w = thrift_writer_new();
  thrift_write_message_begin(&mut w, "add", thrift_msg_call(), 7);
  thrift_write_field_begin(&mut w, thrift_t_i32(), 1);
  thrift_write_i32(&mut w, 3);
  thrift_write_field_begin(&mut w, thrift_t_i32(), 2);
  thrift_write_i32(&mut w, 4);
  thrift_write_field_stop(&mut w);

  // Decode it back.
  var r = thrift_reader_new(thrift_writer_bytes(&w));
  let mr = thrift_read_message_begin(&mut r);
  if !mr.is_ok {
    io.println("header error: " + mr.error);
    return 1;
  }
  let m: ThriftMessage = mr.value;
  if str_compare(m.name, "add") != 0 { return 1; }
  io.println("seqid: " + convert.int_to_string(thrift_message_seqid(&m)));

  var total = 0;
  var go = true;
  while go {
    let fr = thrift_read_field_begin(&mut r);
    if !fr.is_ok { return 1; }
    let f: ThriftField = fr.value;
    if f.ftype == thrift_t_stop() {
      go = false;
    } else {
      let vr = thrift_read_i32(&mut r);
      if !vr.is_ok { return 1; }
      total = total + vr.value;
    }
  }
  io.println("sum: " + convert.int_to_string(total));   // sum: 7
  return 0;
}
```

For a fixed schema, the flat struct model is shorter:

```xi
// One struct: { 1: I32 3, 2: I32 4 } via parallel vectors.
var ids = Vec[Int].new();
var types = Vec[Int].new();
var ints = Vec[Int].new();
var bytes = Vec[Vec[UInt8]].new();
ids.push(1); types.push(thrift_t_i32()); ints.push(3); bytes.push(Vec[UInt8].new());
ids.push(2); types.push(thrift_t_i32()); ints.push(4); bytes.push(Vec[UInt8].new());
let s = ThriftStruct{ ids: ids; types: types; ints: ints; bytes: bytes; };
let enc = thrift_encode_struct(&s);                    // fields + STOP
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.thrift
```

Expected: the section-4 namespace check passes, 24 `[PASS]` lines, and a
final `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Binary protocol only.** Compact and JSON protocols are not
  implemented, and neither are `THeader`/framed/HTTP transports.
- **No transport or RPC layer.** The codec works on in-memory byte
  buffers; sockets, files, framing, streaming, service dispatch and
  versioned structs are out of scope.
- **No IDL parser or code generator.** Schemas are encoded and decoded
  explicitly through the writer/reader functions.
- **Doubles are raw bit patterns.** There is no `Float64` API because
  v0.61.3 cannot bitcast; the caller passes/reads the 64-bit word.
- **STRICT bool decoding.** Only 0 and 1 are accepted on read; any other
  byte is `thrift: invalid bool value`.
- **Strings are validated on read.** `thrift_read_string` requires valid
  UTF-8 and rejects 0x00 (`thrift: string contains nul`) because the
  v0.61.3 string builder aborts on NUL; use `thrift_read_binary` for
  arbitrary bytes.
- **Collection sizes are bounded by the remaining bytes** (1 byte per
  list/set element, 2 per map pair). A size that exceeds that bound is
  `thrift: oversized collection`; a header within the bound may still
  fail element-by-element with `thrift: truncated input`.
- **Skip nesting is capped** at 64 container levels; deeper skip returns
  `thrift: nesting depth exceeds limit of 64`.
- **Flat struct model only.** `ThriftStruct` holds primitive and STRING
  fields in parallel vectors; a STRUCT/MAP/SET/LIST field is rejected by
  the struct functions (use the collection APIs and `thrift_skip`).
- Writers do not validate their arguments (they cannot return errors);
  the reader validates everything it consumes, and `thrift_encode_struct`
  validates its input.
- Plain value types; not thread-safe.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
