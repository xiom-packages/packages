# xiom.avro -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.avro`, version `0.1.0`).
Module: `src/avro.xi` (`module xiom.avro`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.convert`).
No FFI.

## Scope

A pure-XIOM implementation of the Avro 1.11 binary encoding primitives and
the Object Container File header:

- zig-zag variable-length `int`/`long` codecs (encode + decode, exact for
  the full signed 64-bit range), with a 10-byte cap, overflow rejection and
  byte offsets in every error;
- `null`, `boolean`, `float`/`double` (raw little-endian octets),
  `bytes`/`string` (zig-zag length + payload);
- compound helpers: `fixed(n)`, `enum` index, `union` index, `array`/`map`
  block framing (positive count, zero terminator, negative count = byte
  size to skip) and `record` concatenation;
- an Object Container File header parser: magic `Obj\x01`,
  `map<string,bytes>` metadata (with `avro.schema`/`avro.codec`
  accessors) and the 16-byte sync marker, reporting the exact header
  length;
- whole-buffer round-trip helpers that reject trailing bytes.

## Non-goals

- Schema parsing, validation, resolution and the `avro.schema` JSON itself
  (the metadata value is surfaced as opaque bytes).
- Reading or writing OCF data blocks (block counts, compressed payloads,
  per-block sync checks); only the header is parsed.
- `deflate`/`snappy` compression; the codec value is surfaced, never
  applied.
- The Avro JSON encoding and any protocol/RPC layer.
- UTF-8 validation of strings and NUL-safe `Str` construction from
  arbitrary bytes.
- A recursive `Value` tree, schema-driven generic decoding, streaming, or
  an incremental builder.
- Unsigned or arbitrary-precision integers: values must fit the signed
  64-bit platform `Int`.

## Byte-level format (as implemented)

### Representable values

An Avro value maps to the following octets. There is no framing, tag or
type byte anywhere: the writer and reader must agree on the schema.

| Type | Encoding |
|---|---|
| `null` | zero octets |
| `boolean` | one octet: `0x00` false, `0x01` true; nothing else is accepted |
| `int`, `long` | zig-zag varint, 1..10 bytes (see below) |
| `float` | 4 octets, IEEE-754 binary32, little-endian |
| `double` | 8 octets, IEEE-754 binary64, little-endian |
| `bytes` | zig-zag length `n >= 0`, then `n` raw octets |
| `string` | zig-zag UTF-8 byte length `n >= 0`, then `n` UTF-8 octets |
| `fixed(n)` | exactly `n` raw octets |
| `enum` | zig-zag int symbol index `>= 0` |
| `union` | zig-zag long branch index `>= 0` |
| `record` | concatenation of its fields' encodings, in schema order |
| `array` | sequence of blocks terminated by a zero count |
| `map` | sequence of entry blocks terminated by a zero count |

### Variable-length zig-zag integers

An integer is mapped to an unsigned 64-bit value `U`:

- `U = 2 * n` for `n >= 0`;
- `U = -2 * n - 1` for `n < 0`.

`U` is then written as a base-128 varint, least-significant group first:
each octet carries 7 payload bits in the low bits and a continuation bit
in bit 7 (`0x80`); the last octet has the continuation bit clear. Byte `i`
(0-based) contributes `payload_i * 128^i`, so the value is the
little-endian concatenation of 7-bit groups. The example values below are
the exact test vectors.

| `n` | Bytes (hex) | `n` | Bytes (hex) |
|---|---|---|---|
| `0` | `00` | `-1` | `01` |
| `1` | `02` | `-2` | `03` |
| `63` | `7e` | `-64` | `7f` |
| `64` | `8001` | `-65` | `8101` |
| `2^31 - 1` | `feffffff0f` | `-2^31` | `ffffffff0f` |
| `2^31` | `8080808010` | `-2^31 - 1` | `8180808010` |
| `INT64_MAX` | `feffffffffffffffff01` | `INT64_MIN` | `ffffffffffffffffff01` |

Decoding enforces:

1. the varint ends within the buffer (`avro: truncated input` at the
   failing byte);
2. at most 10 octets: a continuation bit on the 10th octet means an 11th
   would follow (`avro: varint longer than 10 bytes` at the varint start);
3. the 10th octet's payload is 0 or 1 because only bit 63 of `U` remains
   (`avro: varint overflow` for anything larger); lower-group accumulation
   cannot overflow because after 9 octets the sum is at most `INT64_MAX`
   exactly (`127 * 128^0 + ... + 127 * 128^8 = 2^63 - 1`);
4. non-minimal encodings of at most 10 octets are accepted (the spec does
   not require the shortest form on read).

The signed value is then `U / 2` when `U` is even and `-(U / 2) - 1` when
`U` is odd (integer division; `U = 2^64 - 1` yields `INT64_MIN` exactly).
The implementation never uses arithmetic right shift on negative values
(trap 18), so the sign behaviour is explicit.

`int` uses the same wire form; `avro_read_int`/`avro_decode_int` reject a
decoded value outside `[-2^31, 2^31 - 1]` with `avro: int out of range`.
`avro_encode_int` writes the value unchanged (the caller owns the range).

### Lengths

`bytes`, `string`, `fixed` (via argument) and block counts are zig-zag
values. A length that decodes negative is an anomaly:
`avro: negative length N at offset M`; the offset is the first byte of the
length, not of the payload. A length larger than the remaining buffer is
`avro: truncated input at offset M` with `M` at the payload start.

### Arrays and maps (block framing)

Both are a sequence of blocks followed by a zero count. Each block starts
with a zig-zag count:

- `count > 0`: `count` items follow (arrays) or `count` key/value pairs
  (maps);
- `count == 0`: end of the sequence;
- `count < 0`: the next `-count` bytes are the payload of one block. Decoders
  may skip them without knowing the item schema; this module skips them
  verbatim (their contents are not validated), and they contribute no
  entries to a decoded result.

A positive array count above the remaining byte count (each varint item
needs at least one byte), a positive map count above half the remaining
byte count (each entry needs at least a zero key length and a zero value
varint), and a negative block size above the remaining byte count are all
`avro: truncated input at offset M`. A count equal to `INT64_MIN` is
`avro: invalid block count at offset M` (its negation is not representable).

Encoding emits a single positive block; for an empty array/map the zero
terminator alone is emitted (a zero-count block **is** the terminator, so
no second zero is appended).

### Object Container File header

The header is three concatenated parts:

```
offset 0       4 octets   magic: 4f 62 6a 01   ("Obj" + version 1)
offset 4       ...        metadata: map<string,bytes> using the block
                          framing above (values are length-prefixed raw
                          bytes, keys are length-prefixed UTF-8)
then          16 octets   sync marker (raw, not length-prefixed)
```

Example (54-byte header used by the tests; hex):

```
4f626a01                      magic
04                            metadata block count 2
16 6176726f2e736368656d61     key "avro.schema"
06 696e74                     value "int"
14 617672726f2e636f646563     key "avro.codec" (0x14 = zig-zag 20)
08 6e756c6c                   value "null"
00                            end of metadata
000102030405060708090a0b0c0d0e0f   sync marker
```

`avro_parse_ocf_header` returns `avro_ocf_header_len` = 4 + metadata bytes
+ 16, the offset where the first data block begins. Any of the four magic
octets wrong (including version != 1) is `avro: bad magic at offset 0`; a
buffer shorter than 4 bytes is `avro: truncated input at offset 0`.
Metadata keys and values are opaque bytes; `avro.schema` and `avro.codec`
are additionally recorded by offset (last occurrence wins for duplicates),
and `avro_ocf_codec_or_null` returns the bytes `null` when the codec key is
absent. Entries inside negative metadata blocks are skipped and therefore
invisible to the metadata accessors.

## Types

```xi
pub type AvroCursor = {
  data: Vec[UInt8];   // buffer (readers never copy the whole buffer)
  pos: Int;           // next unread byte; readers advance only on success
}

pub type AvroOcfHeader = {
  meta: Vec[UInt8];   // all metadata keys and values concatenated
  key_start: Vec[Int];  key_end: Vec[Int];    // entry i key range in meta
  val_start: Vec[Int];  val_end: Vec[Int];    // entry i value range
  schema_start: Int; schema_end: Int;         // avro.schema value, or -1
  codec_start: Int;  codec_end: Int;          // avro.codec value, or -1
  sync: Vec[UInt8];                           // 16-byte sync marker
  header_len: Int;                            // first data block offset
}
```

No `Vec[StructType]`: all sequence state lives in parallel `Vec` fields
(the map reader fills two caller-owned parallel vectors, always by the same
amount so they cannot drift).

## API contract

All functions are free functions in module `xiom.avro`.

```xi
pub type AvroCursor = { ... }
pub type AvroOcfHeader = { ... }

pub fn avro_spec_version() -> Str                      // "1.11"
pub fn avro_max_varint_bytes() -> Int                  // 10
pub fn avro_ocf_magic() -> Vec[UInt8]                  // 4f 62 6a 01
pub fn avro_ocf_sync_size() -> Int                     // 16

pub fn avro_cursor(data: Vec[UInt8]) -> AvroCursor
pub fn avro_cursor_pos(cur: &AvroCursor) -> Int
pub fn avro_cursor_len(cur: &AvroCursor) -> Int
pub fn avro_cursor_remaining(cur: &AvroCursor) -> Int
pub fn avro_cursor_done(cur: &AvroCursor) -> Bool
pub fn avro_cursor_skip(cur: &mut AvroCursor, n: Int) -> Result[Int, Str]

pub fn avro_read_null(cur: &mut AvroCursor) -> Result[Int, Str]
pub fn avro_read_boolean(cur: &mut AvroCursor) -> Result[Bool, Str]
pub fn avro_read_long(cur: &mut AvroCursor) -> Result[Int, Str]
pub fn avro_read_int(cur: &mut AvroCursor) -> Result[Int, Str]
pub fn avro_read_bytes(cur: &mut AvroCursor) -> Result[Vec[UInt8], Str]
pub fn avro_read_string_bytes(cur: &mut AvroCursor) -> Result[Vec[UInt8], Str]
pub fn avro_read_string(cur: &mut AvroCursor) -> Result[Str, Str]
pub fn avro_read_fixed(cur: &mut AvroCursor, n: Int) -> Result[Vec[UInt8], Str]
pub fn avro_read_float(cur: &mut AvroCursor) -> Result[Vec[UInt8], Str]
pub fn avro_read_double(cur: &mut AvroCursor) -> Result[Vec[UInt8], Str]
pub fn avro_read_enum_index(cur: &mut AvroCursor) -> Result[Int, Str]
pub fn avro_read_union_index(cur: &mut AvroCursor) -> Result[Int, Str]
pub fn avro_read_array_long(cur: &mut AvroCursor) -> Result[Vec[Int], Str]
pub fn avro_read_map_bytes_long(cur: &mut AvroCursor, keys_out: &mut Vec[Vec[UInt8]], vals_out: &mut Vec[Int]) -> Result[Int, Str]

pub fn avro_decode_long(data: Vec[UInt8]) -> Result[Int, Str]
pub fn avro_decode_int(data: Vec[UInt8]) -> Result[Int, Str]
pub fn avro_decode_boolean(data: Vec[UInt8]) -> Result[Bool, Str]
pub fn avro_decode_bytes(data: Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn avro_decode_string(data: Vec[UInt8]) -> Result[Str, Str]
pub fn avro_decode_fixed(data: Vec[UInt8], n: Int) -> Result[Vec[UInt8], Str]
pub fn avro_decode_float(data: Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn avro_decode_double(data: Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn avro_decode_array_long(data: Vec[UInt8]) -> Result[Vec[Int], Str]
pub fn avro_decode_map_bytes_long(data: Vec[UInt8], keys_out: &mut Vec[Vec[UInt8]], vals_out: &mut Vec[Int]) -> Result[Int, Str]

pub fn avro_encode_null() -> Vec[UInt8]
pub fn avro_encode_boolean(b: Bool) -> Vec[UInt8]
pub fn avro_encode_long(n: Int) -> Vec[UInt8]
pub fn avro_encode_int(n: Int) -> Vec[UInt8]
pub fn avro_encode_bytes(bytes: &Vec[UInt8]) -> Vec[UInt8]
pub fn avro_encode_string(s: Str) -> Vec[UInt8]
pub fn avro_encode_fixed(bytes: &Vec[UInt8]) -> Vec[UInt8]
pub fn avro_encode_float_le(bytes: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn avro_encode_double_le(bytes: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn avro_encode_enum_index(i: Int) -> Result[Vec[UInt8], Str]
pub fn avro_encode_union_index(i: Int) -> Result[Vec[UInt8], Str]
pub fn avro_encode_record(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8]
pub fn avro_encode_array_block(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8]
pub fn avro_encode_array(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8]
pub fn avro_encode_map_block(keys: &Vec[Vec[UInt8]], values: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str]
pub fn avro_encode_map(keys: &Vec[Vec[UInt8]], values: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str]
pub fn avro_encode_array_long(items: &Vec[Int]) -> Vec[UInt8]
pub fn avro_encode_map_of_longs(keys: &Vec[Str], values: &Vec[Int]) -> Result[Vec[UInt8], Str]

pub fn avro_parse_ocf_header(data: Vec[UInt8]) -> Result[AvroOcfHeader, Str]
pub fn avro_ocf_header_len(hdr: &AvroOcfHeader) -> Int
pub fn avro_ocf_metadata_count(hdr: &AvroOcfHeader) -> Int
pub fn avro_ocf_metadata_key(hdr: &AvroOcfHeader, i: Int) -> Vec[UInt8]
pub fn avro_ocf_metadata_value(hdr: &AvroOcfHeader, i: Int) -> Vec[UInt8]
pub fn avro_ocf_metadata_find(hdr: &AvroOcfHeader, key: &Vec[UInt8]) -> Int
pub fn avro_ocf_schema(hdr: &AvroOcfHeader) -> Vec[UInt8]
pub fn avro_ocf_codec(hdr: &AvroOcfHeader) -> Vec[UInt8]
pub fn avro_ocf_codec_or_null(hdr: &AvroOcfHeader) -> Vec[UInt8]
pub fn avro_ocf_sync(hdr: &AvroOcfHeader) -> Vec[UInt8]
pub fn avro_ocf_sync_byte(hdr: &AvroOcfHeader, i: Int) -> Int
```

Semantics:

`avro_read_*`
: Read one value from the cursor. On success the cursor's position moves
  past the value; on `Err` the position is unchanged since the last
  success, so the offset in the message identifies the anomaly. `float`
  and `double` return the raw little-endian octets (4/8).

`avro_read_string`
: Length + payload decoded to `Str`. A 0x00 octet anywhere in the payload is
  rejected (`avro: string contains NUL` at that exact byte) because a NUL
  would truncate a XIOM `Str` at runtime; UTF-8 is otherwise not validated.
  `avro_read_string_bytes` returns the opaque payload instead.

`avro_read_array_long` / `avro_read_map_bytes_long`
: Consume the whole block sequence including the zero terminator. Positive
  blocks are decoded; negative blocks are skipped verbatim; the map reader
  appends to both output vectors for every decoded entry, so they never
  drift. On error, entries decoded before the failure remain appended.

`avro_decode_*`
: Whole-buffer variants of the readers that additionally require the buffer
  to end exactly after the value (`avro: trailing data at offset M`).

`avro_encode_long`
: Zig-zag varint via non-negative arithmetic: for `n < 0` the magnitude
  part is `-1 - n` and the parity bit is 1, so `INT64_MIN` needs no
  negation and emits the 10-byte all-ones form.

`avro_encode_float_le` / `avro_encode_double_le`
: Emit the input verbatim after checking its length is exactly 4/8.

`avro_encode_map*`
: Preserve insertion order (Avro maps are unordered on the wire); no
  sorting and no duplicate-key validation. Length mismatches are
  `avro: map keys/values length mismatch`.

`avro_parse_ocf_header`
: Parses only the header; bytes after it are ignored (they belong to the
  first data block). The result carries the metadata in flattened ranges
  and the exact `header_len`.

Accessor bounds behavior:

| Accessor | Out-of-range behavior |
|---|---|
| `avro_ocf_metadata_count` | actual entry count |
| `avro_ocf_metadata_key`, `avro_ocf_metadata_value`, `avro_ocf_schema`, `avro_ocf_codec`, `avro_ocf_sync` | empty vector |
| `avro_ocf_metadata_find` | -1 |
| `avro_ocf_sync_byte` | -1 |

## Error string catalog

| Condition | Message |
|---|---|
| Buffer ends inside a varint, length, payload, `fixed`, metadata or sync | `avro: truncated input at offset M` |
| More than 10 varint bytes | `avro: varint longer than 10 bytes at offset M` |
| 10-byte varint with a final group above 1 | `avro: varint overflow at offset M` |
| Zig-zag length decodes negative | `avro: negative length N at offset M` |
| Decoded `int` outside `[-2^31, 2^31-1]` | `avro: int out of range at offset M` |
| Boolean octet not 0/1 | `avro: invalid boolean 0xNN at offset M` |
| `Str` payload contains 0x00 | `avro: string contains NUL at offset M` |
| `fixed(n)` with `n < 0` | `avro: negative fixed size N at offset M` |
| Negative value read as enum index | `avro: negative enum index N at offset M` |
| Negative value read as union index | `avro: negative union index N at offset M` |
| Block count is `INT64_MIN` | `avro: invalid block count at offset M` |
| Bytes remain after a whole-buffer decode | `avro: trailing data at offset M` |
| OCF magic != `4f 62 6a 01` | `avro: bad magic at offset 0` |

Encoder errors:

| Condition | Message |
|---|---|
| `keys.len() != values.len()` in `avro_encode_map*` | `avro: map keys/values length mismatch` |
| `avro_encode_enum_index(i)` with `i < 0` | `avro: negative enum index N` |
| `avro_encode_union_index(i)` with `i < 0` | `avro: negative union index N` |
| `avro_encode_float_le` with `len != 4` | `avro: float requires 4 bytes, got N` |
| `avro_encode_double_le` with `len != 8` | `avro: double requires 8 bytes, got N` |

## Complexity

| Operation | Complexity |
|---|---|
| varint read/encode, boolean, null, float, double | O(1) |
| `avro_read_bytes` / `avro_read_string` / `avro_read_fixed` | O(payload) |
| `avro_read_array_long` | O(decoded items) |
| `avro_read_map_bytes_long` | O(decoded entries) |
| `avro_decode_*` wrappers | as the reader they wrap |
| `avro_encode_bytes` / `avro_encode_string` / `avro_encode_fixed` / `avro_encode_record` | O(payload bytes) |
| `avro_encode_array*` / `avro_encode_map*` | O(total entry bytes) |
| `avro_parse_ocf_header` | O(header bytes) |
| all cursor getters, `avro_ocf_*` accessors (`find` excepted) | O(1) |
| `avro_ocf_metadata_find` | O(entries * key length) |

## Test plan

`tests/test_conformance.xi` (`module avro_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). All buffers are synthetic, built in-test from
hex literals and small helpers (no external data files). Coverage:

1. canonical zig-zag varints at every width boundary (0, -1, 1, -2, 2,
   -3, 63/64, -64/-65, 2^31-1, -2^31, 2^31, -2^31-1, INT64_MAX,
   INT64_MIN) against exact bytes;
2. decode round-trips across the same list;
3. 10-byte cap: 11-byte overlong rejected, 10 continuation bytes rejected,
   10th-byte overflow rejected, truncation/trailing rejected, non-minimal
   ≤ 10-byte forms accepted;
4. int32 range enforcement with 2^31 / -2^31-1 rejected as `int` but valid
   as `long`, cursor advancement checked;
5. boolean octets 0/1, invalid 0x02/0x80, truncation, trailing data;
6. null is zero bytes; record concatenation and field-by-field decode;
7. bytes encoding, empty payload, 300-byte payload with `d804` prefix and
   round-trip;
8. negative-length anomalies at offsets 0 and 1, truncated length/payload;
9. string UTF-8 byte length (`0c` for "héllo"), empty string, NUL payload
   rejected at exact offsets, `string_bytes` accepted;
10. float/double raw LE round-trips, 4/8-byte validation, truncation,
    trailing data, `fixed(n)` copy, negative/oversized fixed, decode
    trailing;
11. enum/union encode and non-negative read, int32 overflow for enum,
    full-range union index;
12. `array<long>` encode/decode, empty array, block API bytes;
13. multi-block arrays, negative-size skip, truncated count/skip/missing
    terminator, `INT64_MIN` block count;
14. `map<bytes,long>` round-trip, negative-size skip, empty map, mismatch
    error, truncated block guard, map block bytes;
15. OCF header golden path: magic, two metadata entries, codec and schema
    accessors, find, sync bytes, header_len = 54, data block after the
    header ignored;
16. OCF malformed inputs: bad magic (3 variants), short magic, truncated
    metadata count/key, negative metadata block skip with default codec,
    truncated sync;
17. whole-buffer trailing-data rejection and cursor bounds
    (`len`/`pos`/`remaining`/`done`, skip negative/oversized/zero);
18. record of long + int + string + boolean, decoded in order;
19. length boundaries 0/1/63/64/127/128/255/256 with exact prefix bytes;
20. error offsets measured from the buffer start for truncation, overlong
    varints, overflow and negative lengths.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.avro
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- **No schema layer.** Nothing validates that a byte sequence matches a
  schema; readers are typed by hand.
- **Header-only OCF support.** Data blocks, their counts, codecs and
  sync re-checks are out of scope.
- **No compression.** `deflate`/`snappy` are surfaced, not implemented.
- **Floats are opaque octets.** No bitcast exists in v0.61.3, so no
  numeric interpretation or arithmetic is provided.
- **Strings are not UTF-8 validated.** NUL-containing payloads are
  rejected when decoding to `Str` (runtime truncation hazard); use the
  bytes reader otherwise.
- **Non-minimal varints ≤ 10 bytes are accepted**, matching common Avro
  readers; only >10-byte encodings and 64-bit overflow are rejected.
- **Signed 64-bit only.** No unsigned/arbitrary-precision integers.
- **Negative blocks are skipped, not decoded**; their entries are
  invisible.
- **Last duplicate wins** for `avro.schema`/`avro.codec`; the ordered list
  remains available.
- **O(entries) metadata find**; no hashing, no incremental builder, no
  streaming, no thread-safety promises.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_int`/`_err_int`, `_ok_bool`/`_err_bool`, `_ok_bytes`/`_err_bytes`,
  `_ok_longs`/`_err_longs`, `_ok_str`/`_err_str`, `_ok_hdr`/`_err_hdr`
  (constructing Results elsewhere miscompiles).
- Every byte read from a `Vec[UInt8]` is widened with
  `(data[pos] as Int) & 0xFF` before arithmetic or comparison, and every
  `Vec[Int]` element read is bound to a typed local first.
- Zig-zag decode avoids `>>` entirely: the varint's low 63 bits are
  accumulated as a non-negative Int plus a separate bit-63 flag, then the
  signed value is formed with division and subtraction only.
- Zig-zag encode uses division and modulo on a non-negative magnitude
  (`m = n` or `m = -1 - n`), never shifts or masks, so `INT64_MIN` needs
  no negation.
- `&struct.field` is never passed where a `&Vec[UInt8]` parameter is
  expected (that yields an empty vector); ranges are copied through typed
  locals first.
- The header struct is assembled by `_finish_hdr` so the parser function
  only calls the `_ok_hdr` leaf constructor; all readers are
  recursion-free loops.
- No FFI: the package declares no `extern "C"` blocks.
