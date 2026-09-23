# xiom.bson

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM BSON document encoding and decoding for the supported
> subset: int32, int64, UTF-8 string, embedded document, array, bool and null.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`,
> `xiom.convert`; tests add `xiom.test`, `xiom.io`, `xiom.string.compare`,
> `xiom.encoding.hex`).
> No FFI.

## What it is

`xiom.bson` is a minimal, dependency-light BSON codec. The encoder is a
stack-based `BsonWriter` that reserves each document's 4-byte little-endian
length and patches it on close; the decoder is a set of flat accessors over a
complete document (`Vec[UInt8]`) returning `Result` values with deterministic
error strings. Doubles, ObjectId/Date/regex/binary and the other extended BSON
types are out of scope (see Limitations).

## API

| Function | Returns | Description |
|---|---|---|
| `bson_writer_new()` | `BsonWriter` | Empty document builder. |
| `bson_doc_start(&mut w)` | -- | Reserve the 4-byte document length. |
| `bson_element_int32(&mut w, name, v)` | -- | int32 element (`0x10`, 4 LE bytes). |
| `bson_element_int64(&mut w, name, v)` | -- | int64 element (`0x12`, 8 LE bytes). |
| `bson_element_str(&mut w, name, v)` | -- | string element (`0x02`, UTF-8 + NUL). |
| `bson_element_bool(&mut w, name, v)` | -- | bool element (`0x08`). |
| `bson_element_null(&mut w, name)` | -- | null element (`0x0A`). |
| `bson_element_doc_start(&mut w, name)` | -- | embedded document element (`0x03`). |
| `bson_element_doc_end(&mut w)` | -- | Close the embedded document. |
| `bson_element_array_start(&mut w, name)` | -- | array element (`0x04`); entries use keys `"0"`, `"1"`, ... |
| `bson_element_array_end(&mut w)` | -- | Close the array. |
| `bson_doc_end(&mut w)` | -- | Patch the length and emit the `0x00` terminator. |
| `bson_to_bytes(&w)` | `Vec[UInt8]` | Copy of the encoded bytes. |
| `bson_is_valid(data)` | `Bool` | Structural walk: lengths, terminators, bounds, nesting. |
| `bson_keys(data)` | `Vec[Str]` | Top-level names in order; `[""]` on malformed. |
| `bson_type_of(data, name)` | `Option[Int]` | BSON type byte of a field. |
| `bson_has(data, name)` | `Bool` | Field presence. |
| `bson_get_int32(data, name)` | `Result[Int, Str]` | int32 (`0x10`) value. |
| `bson_get_int64(data, name)` | `Result[Int, Str]` | int64 (`0x12`) value. |
| `bson_get_str(data, name)` | `Result[Str, Str]` | string (`0x02`) value (bytes verbatim). |
| `bson_get_bool(data, name)` | `Result[Bool, Str]` | bool (`0x08`) value. |
| `bson_get_document(data, name)` | `Result[Vec[UInt8], Str]` | Embedded document bytes (copy). |
| `bson_get_array_len(data, name)` | `Result[Int, Str]` | Array element count. |
| `bson_get_array_str(data, name, index)` | `Result[Str, Str]` | String array element. |
| `bson_get_array_int32(data, name, index)` | `Result[Int, Str]` | int32 array element. |

Errors: `Err("bson: truncated document")`,
`Err("bson: unexpected type 0xNN")`,
`Err("bson: field not found: <name>")`,
`Err("bson: malformed length")` (full catalog in SPEC.md).

## Usage

```xi
use xiom.bson;
use xiom.io;
use xiom.convert;

var w = bson_writer_new();
bson_doc_start(&mut w);
bson_element_int32(&mut w, "answer", 42);
bson_element_str(&mut w, "greeting", "hello");
bson_doc_end(&mut w);
let doc = bson_to_bytes(&w);          // 37 bytes, little-endian BSON

let v = bson_get_int32(&doc, "answer");
match v {
  Ok(n) => { io.println("answer: " + convert.int_to_string(n)); },
  Err(e) => { io.println("decode error: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.bson
```

Expected: 22 `[PASS]` lines and a final
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No doubles (`0x01`).** XIOM v0.61.3 has no `Int <-> Float64` bitcast
  intrinsic (`xiom.num.float` is a documented zero-returning stub), so the
  exact IEEE-754 payload can neither be encoded nor decoded without FFI.
  Documents containing a double fail `bson_is_valid` and reads stop with
  `bson: unexpected type 0x01`.
- **No ObjectId (`0x07`), Date (`0x09`), regex (`0x0B`), binary (`0x05`),
  DBPointer/code/symbol/timestamp/decimal128 or min/max keys.** Only the
  types listed in the API table are supported; anything else is rejected.
- **Little-endian only** (BSON's wire order); all length prefixes are signed
  int32 little-endian.
- The decoder is a **flat accessor** set over an in-memory complete document:
  the leading length must equal the buffer length, and accessors read
  top-level fields (array entries by index).
- `bson_get_str` copies payload bytes verbatim and does not validate UTF-8;
  the caller-supplied **string length includes the trailing NUL** in the
  encoded form.
- Array entries are written with the caller-supplied numeric key
  (`bson_element_array_start` documents the convention; the writer does not
  auto-number). An out-of-range index reads as
  `Err("bson: field not found: <index>")`.
- `bson_keys` returns `[""]` (one empty name) for malformed input.
- `int64` payloads above 2^63-1 wrap to the same two's-complement `Int`
  pattern (the platform `Int` is signed 64-bit).
- Nesting is capped at 100 levels by `bson_is_valid`.
- Not thread-safe; the writer is a plain value type.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
