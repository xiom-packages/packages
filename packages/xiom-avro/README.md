# xiom.avro

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM Avro 1.11 binary primitives (zig-zag varints,
> null/boolean/float/double/bytes/string), the length-delimited compound
> helpers (fixed, enum/union indices, array/map blocks, records) and the
> Object Container File header. No schema resolution and no data blocks.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`,
> `xiom.convert`; tests add `xiom.test`, `xiom.io`, `xiom.string.compare`,
> `xiom.encoding.hex`).
> No FFI.

## What it is

`xiom.avro` is a small, strict codec for the binary layer of the Apache Avro
1.11 specification. It implements exactly what the wire format needs before
a schema enters the picture:

- **Primitive codecs**: `null`, `boolean`, `int`/`long` (variable-length
  zig-zag varints), `float`/`double` (raw 4/8 little-endian IEEE-754 octets),
  `bytes` and `string` (zig-zag length + payload).
- **Compound helpers**: `fixed(n)`, `enum` index, `union` index, `array`
  and `map` block framing (positive count = entries, `0` = end of
  sequence, negative count = byte size of the block, skipped verbatim),
  and `record` = plain concatenation of encoded fields.
- **Object Container File header**: magic `Obj\x01`, the
  `map<string,bytes>` metadata section (with `avro.schema` and
  `avro.codec` surfaced as accessors) and the 16-byte sync marker. The
  parser validates the magic and reports the exact header length so callers
  can continue at the first data block.

Every reader is bounds-checked and returns `Err(Str)` with a deterministic
message that names the byte offset of the anomaly (`truncated input`,
negative lengths, overlong varints, invalid booleans, bad magic). Varints
are capped at 10 bytes; a 10-byte final group above 1 (the 64-bit overflow)
is rejected. Non-minimal encodings that still fit 10 bytes are accepted,
because the Avro spec does not require the shortest form on read.

Because XIOM v0.61.3 has no `Int <-> Float64` bitcast and `Vec[Float64]` is
not allowed, `float`/`double` are exposed as raw little-endian octets on
both the encode and decode side. Nothing is guessed about their meaning.

## Install / use

```
xiom pkg install xiom.avro@0.1.0     # consumer
xiom pkg publish                     # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xi
use xiom.avro;
use xiom.io;
use xiom.convert;
use xiom.string.builder;

fn main() {
  // Zig-zag varints: 1 -> 0x02, -1 -> 0x01, INT64_MIN -> 10 bytes.
  let enc = avro_encode_long(-1);       // [0x01]
  let dec = avro_decode_long(enc);      // Ok(-1)
  match dec {
    Ok(v) => { io.println(convert.int_to_string(v)); },
    Err(e) => { io.println("decode error: " + e); },
  }

  // A record is the concatenation of its already-encoded fields.
  var parts = Vec[Vec[UInt8]].new();
  parts.push(avro_encode_string("xiom"));
  parts.push(avro_encode_long(42));
  let record = avro_encode_record(&parts);

  // Decode them back, in order, with a cursor.
  var cur = avro_cursor(record);
  let name = avro_read_string(&mut cur);   // Ok("xiom")
  match name {
    Ok(s) => { io.println(s); },
    Err(e) => { io.println("decode error: " + e); },
  }
  let n = avro_read_long(&mut cur);        // Ok(42)

  // Object Container File header (magic + metadata + sync marker).
  // `header_bytes` is a complete header assembled by the writer.
  let parsed = avro_parse_ocf_header(header_bytes);
  match parsed {
    Ok(hdr) => {
      let codec = avro_ocf_codec_or_null(&hdr);   // "null" when absent
      io.println(builder.sb_to_str(&codec));
      io.println(convert.int_to_string(avro_ocf_header_len(&hdr)));
    }
    Err(e) => { io.println("bad header: " + e); },
  }
}
```

## API

All functions are free functions in module `xiom.avro`.

| Function | Returns | Description |
|---|---|---|
| `avro_cursor(data)` | `AvroCursor` | Cursor at offset 0 over `data`. |
| `avro_cursor_pos(cur)` / `avro_cursor_len(cur)` | `Int` | Read position / buffer length. |
| `avro_cursor_remaining(cur)` / `avro_cursor_done(cur)` | `Int` / `Bool` | Unread bytes / exhausted. |
| `avro_cursor_skip(cur, n)` | `Result[Int, Str]` | Advance `n` bytes, bounds-checked. |
| `avro_read_null(cur)` | `Result[Int, Str]` | Consume zero bytes. |
| `avro_read_boolean(cur)` | `Result[Bool, Str]` | One octet, 0/1. |
| `avro_read_long(cur)` / `avro_read_int(cur)` | `Result[Int, Str]` | Zig-zag varint (int checks int32 range). |
| `avro_read_bytes(cur)` / `avro_read_string_bytes(cur)` | `Result[Vec[UInt8], Str]` | Length + opaque payload. |
| `avro_read_string(cur)` | `Result[Str, Str]` | Length + UTF-8 payload; NUL rejected. |
| `avro_read_fixed(cur, n)` | `Result[Vec[UInt8], Str]` | `n` raw octets. |
| `avro_read_float(cur)` / `avro_read_double(cur)` | `Result[Vec[UInt8], Str]` | 4/8 raw LE octets. |
| `avro_read_enum_index(cur)` / `avro_read_union_index(cur)` | `Result[Int, Str]` | Non-negative zig-zag index. |
| `avro_read_array_long(cur)` | `Result[Vec[Int], Str]` | Full `array<long>` incl. block skips. |
| `avro_read_map_bytes_long(cur, keys_out, vals_out)` | `Result[Int, Str]` | `map<bytes,long>` into parallel vectors. |
| `avro_decode_long/int/boolean/bytes/string/fixed/float/double/array_long/map_bytes_long` | per type | Whole-buffer wrappers that reject trailing bytes. |
| `avro_encode_null()` | `Vec[UInt8]` | Zero bytes. |
| `avro_encode_boolean(b)` | `Vec[UInt8]` | 0x00 / 0x01. |
| `avro_encode_long(n)` / `avro_encode_int(n)` | `Vec[UInt8]` | Zig-zag varint (full Int64 range). |
| `avro_encode_bytes(bytes)` / `avro_encode_string(s)` | `Vec[UInt8]` | Length + payload. |
| `avro_encode_fixed(bytes)` | `Vec[UInt8]` | Verbatim copy. |
| `avro_encode_float_le(bytes)` / `avro_encode_double_le(bytes)` | `Result[Vec[UInt8], Str]` | Validate 4/8 octets, emit verbatim. |
| `avro_encode_enum_index(i)` / `avro_encode_union_index(i)` | `Result[Vec[UInt8], Str]` | Reject negative indices. |
| `avro_encode_record(parts)` | `Vec[UInt8]` | Concatenate encoded fields. |
| `avro_encode_array_block(parts)` / `avro_encode_array(parts)` | `Vec[UInt8]` | Block without / with zero terminator. |
| `avro_encode_map_block(keys, values)` / `avro_encode_map(keys, values)` | `Result[Vec[UInt8], Str]` | Block without / with terminator. |
| `avro_encode_array_long(items)` | `Vec[UInt8]` | Convenience single-block `array<long>`. |
| `avro_encode_map_of_longs(keys, values)` | `Result[Vec[UInt8], Str]` | Convenience `map<string,long>` (insertion order). |
| `avro_parse_ocf_header(data)` | `Result[AvroOcfHeader, Str]` | Validate magic and parse header. |
| `avro_ocf_header_len(hdr)` | `Int` | Offset of the first data block. |
| `avro_ocf_metadata_count(hdr)` | `Int` | Decoded metadata entries. |
| `avro_ocf_metadata_key(hdr, i)` / `avro_ocf_metadata_value(hdr, i)` | `Vec[UInt8]` | Copy of entry `i`'s key/value. |
| `avro_ocf_metadata_find(hdr, key)` | `Int` | Entry index for raw `key` bytes, or -1. |
| `avro_ocf_schema(hdr)` / `avro_ocf_codec(hdr)` | `Vec[UInt8]` | `avro.schema` / `avro.codec` value (empty if absent). |
| `avro_ocf_codec_or_null(hdr)` | `Vec[UInt8]` | Codec value, defaulting to `"null"`. |
| `avro_ocf_sync(hdr)` / `avro_ocf_sync_byte(hdr, i)` | `Vec[UInt8]` / `Int` | 16-byte sync marker. |
| `avro_spec_version()` / `avro_max_varint_bytes()` | `Str` / `Int` | `"1.11"` / `10`. |
| `avro_ocf_magic()` / `avro_ocf_sync_size()` | `Vec[UInt8]` / `Int` | `Obj\x01` / `16`. |

Properties that hold across the API: cursor readers advance only on
success, so on `Err` the position is the anomaly and the message offset
matches it; `keys_out` and `values_out` are always extended by the same
amount, so the parallel vectors cannot drift; every accessor is
bounds-safe (out-of-range returns -1 or an empty vector).

## Error model

| Condition | Message |
|---|---|
| Buffer ends inside a varint, length, payload, `fixed` or the OCF header/sync | `avro: truncated input at offset M` |
| Varint needs more than 10 bytes | `avro: varint longer than 10 bytes at offset M` |
| 10-byte varint whose final group is above 1 | `avro: varint overflow at offset M` |
| Zig-zag length decodes negative | `avro: negative length N at offset M` |
| `int` outside [-2^31, 2^31-1] | `avro: int out of range at offset M` |
| Boolean octet other than 0/1 | `avro: invalid boolean 0xNN at offset M` |
| `Str` payload contains a 0x00 octet | `avro: string contains NUL at offset M` |
| `fixed(n)` with `n < 0` | `avro: negative fixed size N at offset M` |
| Negative enum/union index on read | `avro: negative enum index N at offset M` / `avro: negative union index N at offset M` |
| Array/map block count is `INT64_MIN` | `avro: invalid block count at offset M` |
| Bytes remain after a whole-buffer decode | `avro: trailing data at offset M` |
| Any of the four OCF magic bytes wrong | `avro: bad magic at offset 0` |

Encoder errors: `avro: map keys/values length mismatch`,
`avro: negative enum index N`, `avro: negative union index N`,
`avro: float requires 4 bytes, got N`, `avro: double requires 8 bytes,
got N`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.avro
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No schema handling.** Schema parsing, validation and resolution are out
  of scope; this package is the binary layer only.
- **Header only for OCF.** Data blocks, their counts, compression and the
  per-block sync checks are not read. `header_len` tells you where they
  start.
- **No compression codecs.** `deflate`/`snappy` metadata is surfaced as
  bytes but never applied.
- **Floats are raw octets.** No `Int <-> Float64` bitcast exists in
  v0.61.3 and `Vec[Float64]` is banned, so float/double round-trips are
  byte-for-byte, not numeric.
- **Strings are not UTF-8 validated.** A decoded `Str` is rejected when its
  payload contains NUL (a runtime hazard); otherwise bytes are trusted.
  Use `avro_read_string_bytes` for opaque data.
- **Non-minimal varints ≤ 10 bytes are accepted** on read, matching common
  Avro readers; only >10-byte encodings and 64-bit overflow are rejected.
- **Ints are signed 64-bit.** There is no unsigned or arbitrary-precision
  fallback; Avro `int` is range-checked to int32 on decode.
- **Negative map blocks are skipped, not decoded**, so their keys are
  invisible to the metadata accessors. Encoders never emit negative
  blocks.
- **Duplicate `avro.schema`/`avro.codec` keys keep the last occurrence**;
  the full ordered list stays available through the metadata accessors.
- **Linear metadata lookup** (`avro_ocf_metadata_find`) and O(n) copies;
  no hashing, no builder API, no streaming.
- Not thread-safe; plain value types throughout.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
