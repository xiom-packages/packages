# xiom.bson -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.bson`, version `0.1.0`).
Module: `src/bson.xi` (`module xiom.bson`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`, `xiom.convert`).

## Scope

A pure-XIOM (no FFI) BSON document codec for a documented subset:

- a stack-based `BsonWriter` that emits little-endian BSON and patches every
  document/array length in place;
- elements: int32 (`0x10`), int64 (`0x12`), UTF-8 string (`0x02`), embedded
  document (`0x03`), array (`0x04`), bool (`0x08`), null (`0x0A`);
- flat decoder accessors over a complete document: structural validation,
  key listing, type lookup, presence checks and typed getters (including
  nested-document extraction and array element access);
- deterministic error strings for truncation, malformed lengths, wrong types
  and missing fields.

## Non-goals

- **Doubles (`0x01`)**: encoding/decoding requires an IEEE-754 `Int <-> Float64`
  bitcast that does not exist in XIOM v0.61.3 (see Known limitations).
- All other BSON types: binary (`0x05`), undefined (`0x06`), ObjectId
  (`0x07`), UTC datetime (`0x09`), regex (`0x0B`), DBPointer (`0x0C`), code
  (`0x0D`), symbol (`0x0E`), code_w_scope (`0x0F`), timestamp (`0x11`),
  decimal128 (`0x13`), min/max keys (`0xFF`/`0x7F`).
- Top-level arrays: BSON's root is always a document.
- UTF-8 validation of string payloads (bytes are copied verbatim).
- A generic `Value` tree with recursive encode/decode.
- Streaming over sockets/files; this codec works on in-memory `Vec[UInt8]`
  buffers.
- Auto-numbered array keys: array entries are written with the
  caller-supplied numeric key (`"0"`, `"1"`, ...).
- Canonical/round-trip preservation of unsupported fields on re-encode.

## Byte-level format table

All multi-byte integers are LITTLE-endian. Every element is
`type byte + e_name` where `e_name` is a NUL-terminated cstring. A document is
`int32 length + elements + 0x00`, where `length` counts itself, the elements
and the terminator.

| Element | Type byte | Value layout |
|---|---|---|
| double (unsupported) | `0x01` | 8 bytes IEEE-754 -- rejected |
| string | `0x02` | int32 byte-length (INCLUDING the trailing `0x00`), UTF-8 bytes, `0x00` |
| embedded document | `0x03` | int32 total length, elements, `0x00` |
| array | `0x04` | int32 total length, elements keyed `"0"`, `"1"`, ..., `0x00` |
| bool | `0x08` | 1 byte: `0x00` false, `0x01` true (any non-zero reads true) |
| null | `0x0A` | no payload |
| int32 | `0x10` | 4 bytes signed little-endian |
| int64 | `0x12` | 8 bytes signed little-endian |

Minimum document size is 5 bytes (`05 00 00 00 00`).

## API signatures

All functions are free functions in module `xiom.bson`:

```xi
pub type BsonWriter = { buf: Vec[UInt8]; open_docs: Vec[Int]; }

pub fn bson_writer_new() -> BsonWriter
pub fn bson_doc_start(w: &mut BsonWriter)
pub fn bson_element_int32(w: &mut BsonWriter, name: Str, v: Int)
pub fn bson_element_int64(w: &mut BsonWriter, name: Str, v: Int)
pub fn bson_element_str(w: &mut BsonWriter, name: Str, v: Str)
pub fn bson_element_bool(w: &mut BsonWriter, name: Str, v: Bool)
pub fn bson_element_null(w: &mut BsonWriter, name: Str)
pub fn bson_element_doc_start(w: &mut BsonWriter, name: Str)
pub fn bson_element_doc_end(w: &mut BsonWriter)
pub fn bson_element_array_start(w: &mut BsonWriter, name: Str)
pub fn bson_element_array_end(w: &mut BsonWriter)
pub fn bson_doc_end(w: &mut BsonWriter)
pub fn bson_to_bytes(w: &BsonWriter) -> Vec[UInt8]

pub fn bson_is_valid(data: &Vec[UInt8]) -> Bool
pub fn bson_keys(data: &Vec[UInt8]) -> Vec[Str]
pub fn bson_type_of(data: &Vec[UInt8], name: Str) -> Option[Int]
pub fn bson_has(data: &Vec[UInt8], name: Str) -> Bool
pub fn bson_get_int32(data: &Vec[UInt8], name: Str) -> Result[Int, Str]
pub fn bson_get_int64(data: &Vec[UInt8], name: Str) -> Result[Int, Str]
pub fn bson_get_str(data: &Vec[UInt8], name: Str) -> Result[Str, Str]
pub fn bson_get_bool(data: &Vec[UInt8], name: Str) -> Result[Bool, Str]
pub fn bson_get_document(data: &Vec[UInt8], name: Str) -> Result[Vec[UInt8], Str]
pub fn bson_get_array_len(data: &Vec[UInt8], name: Str) -> Result[Int, Str]
pub fn bson_get_array_str(data: &Vec[UInt8], name: Str, index: Int) -> Result[Str, Str]
pub fn bson_get_array_int32(data: &Vec[UInt8], name: Str, index: Int) -> Result[Int, Str]
```

`bson_element_doc_start` / `bson_element_doc_end` are an addition beyond the
minimal API list: without them the encoder could not emit `0x03` elements at
all (only `0x04` arrays), while the decoder and `bson_type_of` handle `0x03`.

## Semantics

`bson_doc_start` / `bson_element_doc_start` / `bson_element_array_start`
: Push the current buffer length and reserve 4 zero length bytes.

`bson_doc_end` / `bson_element_doc_end` / `bson_element_array_end`
: Append the `0x00` terminator, patch the reserved length with the total size
  and pop the stack. Calling an `*_end` with an empty stack is a programming
  error trapped by the `requires: w.open_docs.len() > 0` contract.

`bson_element_str`
: The encoded int32 length is `str_len(v) + 1`: BSON counts the trailing NUL.

`bson_is_valid`
: The leading length must equal `data.len()`, the terminator must be `0x00`,
  and every element (recursively, at most 100 nesting levels) must use a
  supported type with sound lengths, bounds and terminators. Unsupported type
  bytes make the document invalid.

`bson_keys`
: Top-level names in order. A malformed document yields the one-element
  vector `[""]`; a valid empty document yields `[]`.

`bson_type_of`
: The first top-level element's type byte, or `None` when the document is
  malformed or the name is absent.

`bson_get_*`
: The first top-level element with a matching name is located by walking
  preceding elements, then its type byte and value are validated and read.
  `bson_get_document` copies the nested bytes into a fresh `Vec[UInt8]` (the
  copy is itself a complete readable document).

`bson_get_array_len` / `bson_get_array_str` / `bson_get_array_int32`
: Arrays are BSON documents keyed by the decimal index strings, so the
  accessors look up `int_to_string(index)` inside the array document. An
  out-of-range index reports the numeric key as a missing field:
  `Err("bson: field not found: <index>")`.

## Error string catalog

| Condition | Error text |
|---|---|
| Buffer too short; payload/terminator truncated; missing NUL | `bson: truncated document` |
| Element found but its type byte differs from the requested reader | `bson: unexpected type 0xNN` (`NN` = two lowercase hex digits) |
| No element with the requested name (also out-of-range array index) | `bson: field not found: <name>` |
| Declared document length does not match the buffer, is below 5, or a string/array/document length is non-positive (< 1 / < 5) | `bson: malformed length` |
| Unknown/unsupported type byte while walking (also while skipping preceding elements) | `bson: unexpected type 0xNN` |

## Complexity

| Operation | Complexity |
|---|---|
| `bson_element_*` / `bson_doc_start` / `bson_doc_end` | O(name + payload) |
| `bson_to_bytes` | O(buffer) |
| `bson_is_valid` | O(document bytes) |
| `bson_keys` | O(document bytes) |
| `bson_type_of` / `bson_has` | O(walked prefix) |
| `bson_get_*` (top level) | O(walked prefix + value) |
| `bson_get_array_*` | O(walked prefix + array bytes) |

## Test plan

`tests/test_conformance.xi` (`module bson_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. int32 exact bytes (LE, negatives, INT32_MIN, byte-swapped value);
2. int64 exact bytes (LE, -1, 2^32, INT64_MIN);
3. string exact bytes (empty, "abc", UTF-8 "héllo") incl. NUL-counting length;
4. bool (true/false) and null exact bytes;
5. nested document length patching (inner `0x0c`, outer `0x14`);
6. array encoding with numeric keys and patched lengths;
7. `bson_keys` order on an out-of-order field set;
8. `bson_keys` on empty (`[]`) and malformed (`[""]`) documents;
9. int32 accessor round-trips at boundaries;
10. int64 accessor round-trips at boundaries;
11. string accessor round-trips (ASCII, 2-byte and 3-byte UTF-8, newline);
12. bool round-trips; null is present/type-known but not a bool;
13. `bson_get_document` copy is valid and re-readable;
14. array length, indexed int32, out-of-range and wrong-type errors;
15. `bson_type_of` for all seven supported types and a missing field;
16. `bson_has` presence, absence and malformed-document handling;
17. missing-field errors for all typed getters;
18. wrong-type errors with exact `0xNN` messages;
19. truncated documents (short payload, missing terminator, 2-byte buffer);
20. malformed lengths (declared > buffer, declared < buffer, zero string len);
21. empty document validity/readability and malformed shapes;
22. mixed document integration (validity, keys, all accessors, nesting).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.bson
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- **No doubles (`0x01`).** The exact IEEE-754 little-endian payload cannot be
  produced or interpreted in pure XIOM v0.61.3: there is no `Int <-> Float64`
  bitcast intrinsic and `xiom.num.float` is a documented zero-returning stub.
  A document containing a double fails `bson_is_valid` and reading it stops
  with `bson: unexpected type 0x01`.
- No ObjectId, Date, regex, binary, decimal128, timestamp, code, symbol,
  min/max key or undefined support; any of those type bytes is rejected.
- No UTF-8 validation; string bytes are copied verbatim.
- Array keys are caller-supplied numeric strings; no auto-numbering.
- `bson_keys` malformed sentinel is `[""]`.
- `int64` payloads above 2^63-1 wrap to the same two's-complement `Int`
  pattern.
- Nesting depth for `bson_is_valid` is capped at 100.
- The writer is not thread-safe; `bson_doc_end` on an empty stack is trapped
  by a contract (unreachable in release-stripped builds, hence documented as
  a programming error).
- Decoders require a COMPLETE top-level document (`length == buffer length`);
  trailing bytes are treated as `bson: malformed length`.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err`/`Some`/`None` construction is confined to the tiny leaf helpers
  `_ok_int`/`_err_int`/`_ok_str`/`_err_str`/`_ok_bool`/`_err_bool`/
  `_ok_bytes`/`_err_bytes`/`_some_int`/`_none_int`.
- All little-endian byte extraction is arithmetic (modulo/division) because
  `& 0xFF` on operands with bit 31 set miscompiles.
- Str payloads are compared with `str_compare` (BUG 17: `==` between Str
  values read from a `Vec` lowers to a pointer compare).
- Str materialization from bytes uses `xiom.string.builder.sb_to_str` (one
  allocation, ownership transfer); the package declares no `extern "C"`
  blocks (no FFI).
- Array index keys use `xiom.convert.int_to_string`.
