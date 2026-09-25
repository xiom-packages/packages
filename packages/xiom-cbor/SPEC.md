# xiom.cbor -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.cbor`, version `0.1.0`).
Module: `src/cbor.xi` (`module xiom.cbor`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`).
No FFI.

## Scope

A pure-XIOM CBOR (RFC 8949) codec for a documented deterministic subset:

- strict decoding of exactly one top-level value with deterministic
  `Err(Str)` diagnostics and a documented nesting-depth cap;
- definite lengths only, and the shortest-form argument required on decode
  for additional info 24/25/26/27;
- canonical shortest-form encoding of integers, byte strings, text strings,
  arrays and maps; maps emitted in RFC 8949 core-deterministic key order
  (bytewise lexicographic over the encoded keys) with duplicates rejected;
- a flat token representation (parallel `Vec` fields; no
  `Vec[StructType]`) with parent/child/sibling links and source-offset
  ranges for payloads;
- typed token accessors for integers, booleans, byte strings, text strings,
  arrays and maps;
- `cbor_reserialize`: rebuild the exact accepted bytes from the token
  stream (map pair order included);
- encode/decode/reserialize round-trips for the whole supported subset.

## Non-goals

- Tags (major type 6) and every semantic tag (dates, bignums, decimals,
  self-described CBOR, ...).
- Floats and half-floats (major type 7 additional info 25/26/27). XIOM
  v0.61.3 has no `Int <-> Float64` bitcast, so an exact round-trip cannot be
  produced in pure XIOM.
- Simple values other than 20/21/22/23 (additional info 0..19 and 24).
- Indefinite-length byte/text strings, arrays, maps and the break marker;
  CBOR sequences (multiple top-level items in one buffer).
- UTF-8 validation or decoding: text strings are opaque bytes.
- Streaming/incremental decode or encode over sockets/files.
- Arbitrary-precision or unsigned 64-bit integers: values must fit the
  signed 64-bit platform `Int`.
- A recursive `Value` tree, a builder API that appends tokens, or a
  pretty-printer.

## Byte-level format

Every CBOR item starts with one initial byte `(major_type * 32) +
additional_info`; `additional_info` either carries the argument inline or
selects a big-endian argument of 1, 2, 4 or 8 bytes.

Major types in the supported subset:

| Major | Meaning | Argument |
|---|---|---|
| 0 | unsigned integer | value |
| 1 | negative integer | value = -1 - argument |
| 2 | byte string | definite length in bytes |
| 3 | text string | definite length in bytes |
| 4 | array | definite element count |
| 5 | map | definite pair count |
| 6 | tag | rejected (`cbor: tags not supported`) |
| 7 | simple/float | 20 false, 21 true, 22 null, 23 undefined; other values rejected |

Additional info handling (all major types):

| Additional info | Argument | Accepted |
|---|---|---|
| 0..23 | inline in the initial byte | yes |
| 24 | 1 byte, must be >= 24 | yes |
| 25 | 2 bytes, must be >= 256 | yes |
| 26 | 4 bytes, must be >= 65536 | yes |
| 27 | 8 bytes, must be >= 2^32 | yes, argument <= `INT64_MAX` |
| 28, 29, 30 | -- | `cbor: reserved additional info NN` |
| 31 | -- | major 2..5: `cbor: indefinite length not supported`; major 7 (`0xff`): `cbor: break outside indefinite item`; major 0/1/6: `cbor: reserved additional info 31` |

Major type 7 additional info: 0..19 -> `cbor: simple values not supported`;
20/21/22/23 -> bool/null/undefined tokens; 24 -> 1 simple-value byte, with
byte < 32 rejected as `cbor: non-shortest form` and byte >= 32 rejected as
`cbor: simple values not supported` (a missing byte is
`cbor: truncated input`); 25/26/27 -> `cbor: floats not supported`.

Canonical encoding produced by the encoders (first applicable row):

| Value / length | Initial byte | Argument bytes |
|---|---|---|
| `0..23` | `major*32 + value` | -- |
| `24..255` | `major*32 + 24` | 1 |
| `256..65535` | `major*32 + 25` | 2 |
| `65536..4294967295` | `major*32 + 26` | 4 |
| `4294967296..INT64_MAX` | `major*32 + 27` | 8 |

Negative integers use major 1 with argument `-1 - n`, so `INT64_MIN` is
encoded with the 8-byte argument `INT64_MAX` (`0x3b7fffffffffffffff`).

Validation rules enforced by `cbor_decode`:

1. `document` is exactly one item; any byte after it is
   `cbor: trailing data after top-level value`.
2. Additional info 28..30 is always reserved; 31 is rejected as documented
   above.
3. Arguments use the shortest available form: ai 24/25/26/27 with an
   argument below 24/256/65536/2^32 is `cbor: non-shortest form` (checked
   for major 0..5 and for major 7 ai 24).
4. A major type 0/1 argument above `INT64_MAX` is
   `cbor: integer out of range`; a major 2/3/4/5 argument above `INT64_MAX`
   is `cbor: length overflow`. This is the signed 64-bit subset.
5. A byte/text string whose length exceeds the remaining bytes, and an
   array/map count that exceeds the remaining bytes (1 byte per array
   element, 2 bytes per map pair, both necessary lower bounds), are
   `cbor: truncated input`.
6. Major type 6 is rejected from the initial byte alone, before its
   argument is read; so is major type 7 ai 25/26/27.
7. Containers are nested at most 64 levels deep (`cbor_max_depth()`),
   counted with the top-level container at depth 0; a container at depth 64
   is rejected with the depth message. Arrays and maps share the limit.
8. Every read is bounds-checked; a buffer that ends inside a value, header
   or payload is `cbor: truncated input`.
9. Map key order is **not** validated on decode: any pair order is accepted
   and `cbor_reserialize` preserves it. `cbor_encode_map` is the canonical
   producer.

Note that RFC 8949 well-formedness allows non-preferred (longer) argument
encodings; this codec is deliberately strict. Every document produced with
`cbor_encode_*` re-decodes cleanly, and every document it accepts is in
preferred/self-described form apart from map key order.

## Types

```xi
pub type CborDoc = {
  data: Vec[UInt8];          // source bytes (payloads are offset ranges)
  kind: Vec[Int];            // cbor_kind_* code per token
  parent: Vec[Int];          // parent token, -1 for the root
  first_child: Vec[Int];     // first direct child, -1 for leaves
  child_count: Vec[Int];     // number of direct children (2x pairs for maps)
  next_sibling: Vec[Int];    // next direct sibling, -1 for the last child
  start: Vec[Int];           // first byte of the token
  end: Vec[Int];             // one past the last byte of the token
  payload_start: Vec[Int];   // bytes/text: first payload byte
  payload_end: Vec[Int];     // bytes/text: one past the last payload byte
  value: Vec[Int];           // int: parsed value; bool: 0/1; bytes/text: length
}
```

Tokens are appended in depth-first pre-order, so a token's whole subtree
occupies the contiguous index range that follows it. A container's direct
children are *not* generally adjacent (a child's subtree sits between it and
its next sibling); iterate them with `cbor_first_child` +
`cbor_next_sibling` or `cbor_child`.

`payload_start`/`payload_end` are meaningful for `kind` 2 (byte string) and
`kind` 3 (text string). `value` is meaningful for `kind` 0/1 (the integer),
`kind` 2/3 (the byte length) and `kind` 6 (0 false / 1 true).

Kind codes (`cbor_kind_*`):

| Code | Kind | Meaning |
|---|---|---|
| 0 | `cbor_kind_uint()` | major type 0 unsigned integer |
| 1 | `cbor_kind_negint()` | major type 1 negative integer |
| 2 | `cbor_kind_bytes()` | major type 2 byte string |
| 3 | `cbor_kind_text()` | major type 3 text string |
| 4 | `cbor_kind_array()` | major type 4 array |
| 5 | `cbor_kind_map()` | major type 5 map |
| 6 | `cbor_kind_bool()` | major type 7 false/true (value 0/1) |
| 7 | `cbor_kind_null()` | major type 7 null (`0xf6`) |
| 8 | `cbor_kind_undefined()` | major type 7 undefined (`0xf7`) |

Map children alternate key, value: pair `k` is child `2*k` (a key token) and
child `2*k + 1` (its value token).

## API contract

All functions are free functions in module `xiom.cbor`.

```xi
pub type CborDoc = { ... }

pub fn cbor_decode(data: Vec[UInt8]) -> Result[CborDoc, Str]
pub fn cbor_reserialize(doc: &CborDoc) -> Vec[UInt8]

pub fn cbor_kind_uint() -> Int
pub fn cbor_kind_negint() -> Int
pub fn cbor_kind_bytes() -> Int
pub fn cbor_kind_text() -> Int
pub fn cbor_kind_array() -> Int
pub fn cbor_kind_map() -> Int
pub fn cbor_kind_bool() -> Int
pub fn cbor_kind_null() -> Int
pub fn cbor_kind_undefined() -> Int
pub fn cbor_max_depth() -> Int

pub fn cbor_token_count(doc: &CborDoc) -> Int
pub fn cbor_root(doc: &CborDoc) -> Int
pub fn cbor_kind(doc: &CborDoc, i: Int) -> Int
pub fn cbor_parent(doc: &CborDoc, i: Int) -> Int
pub fn cbor_first_child(doc: &CborDoc, i: Int) -> Int
pub fn cbor_child_count(doc: &CborDoc, i: Int) -> Int
pub fn cbor_next_sibling(doc: &CborDoc, i: Int) -> Int
pub fn cbor_child(doc: &CborDoc, i: Int, n: Int) -> Int
pub fn cbor_token_start(doc: &CborDoc, i: Int) -> Int
pub fn cbor_token_end(doc: &CborDoc, i: Int) -> Int
pub fn cbor_int_value(doc: &CborDoc, i: Int) -> Int
pub fn cbor_bool_value(doc: &CborDoc, i: Int) -> Int
pub fn cbor_bytes_len(doc: &CborDoc, i: Int) -> Int
pub fn cbor_bytes(doc: &CborDoc, i: Int) -> Vec[UInt8]
pub fn cbor_text_len(doc: &CborDoc, i: Int) -> Int
pub fn cbor_text_bytes(doc: &CborDoc, i: Int) -> Vec[UInt8]
pub fn cbor_token_bytes(doc: &CborDoc, i: Int) -> Vec[UInt8]

pub fn cbor_encode_int(n: Int) -> Vec[UInt8]
pub fn cbor_encode_bool(b: Bool) -> Vec[UInt8]
pub fn cbor_encode_null() -> Vec[UInt8]
pub fn cbor_encode_undefined() -> Vec[UInt8]
pub fn cbor_encode_bytes(bytes: &Vec[UInt8]) -> Vec[UInt8]
pub fn cbor_encode_text(s: Str) -> Vec[UInt8]
pub fn cbor_encode_text_bytes(bytes: &Vec[UInt8]) -> Vec[UInt8]
pub fn cbor_encode_array(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8]
pub fn cbor_encode_map(keys: &Vec[Vec[UInt8]], values: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str]
```

Semantics:

`cbor_decode(data)`
: Decodes exactly one item from `data` (taken by value; the document owns
  the bytes). Returns `Ok(CborDoc)` with at least one token, or `Err` from
  the catalog below. The token stream is never partially returned.

`cbor_reserialize(doc)`
: Rebuilds the accepted bytes from the token stream: shortest-form headers
  from `value`, payloads copied through `payload_start`/`payload_end`,
  containers via recursively reserializing the sibling chain. It does not
  copy `data`, so it is a genuine reconstruction check. For a document
  returned by `cbor_decode` the result equals the original input (map pair
  order included); an empty document yields an empty vector.

`cbor_encode_int(n)`
: Major 0 with argument `n` for `n >= 0`, major 1 with argument `-1 - n`
  for `n < 0`, in the shortest form; exact for `INT64_MIN..INT64_MAX`.

`cbor_encode_bytes(bytes)`
: Shortest header for `bytes.len()` (major 2) + the bytes verbatim.

`cbor_encode_text(s)`
: Same as `cbor_encode_bytes` with major 3 over the UTF-8 bytes of `s`; the
  length is `string.str_len(s)` (byte length). No validation is performed.

`cbor_encode_text_bytes(bytes)`
: Major 3 over raw bytes; the caller asserts text semantics. No UTF-8
  validation.

`cbor_encode_array(parts)`
: Shortest major 4 header for `parts.len()` + each chunk in order. Chunks
  are already-encoded CBOR values; no validation is performed (the caller
  composes the value).

`cbor_encode_map(keys, values)`
: Pairs `keys[i]` with `values[i]` (both already-encoded chunks). The output
  emits pairs sorted by the unsigned bytewise lexicographic order of the
  encoded key chunks (RFC 8949 core deterministic encoding), so it
  re-decodes canonically.
  `Err("cbor: map keys/values length mismatch")` when the vectors differ in
  length; `Err("cbor: duplicate map key")` when any two encoded keys are
  byte-identical. O(pairs^2) key comparisons (selection sort).

Accessor bounds behavior:

| Accessor | Out-of-range / wrong kind behavior |
|---|---|
| `cbor_kind`, `cbor_parent`, `cbor_first_child`, `cbor_token_start`, `cbor_token_end`, `cbor_next_sibling`, `cbor_child` | return -1 |
| `cbor_child_count` | returns 0 |
| `cbor_int_value` | returns 0 (check the kind first) |
| `cbor_bool_value` | returns -1 |
| `cbor_bytes_len`, `cbor_text_len` | return -1 |
| `cbor_bytes`, `cbor_text_bytes`, `cbor_token_bytes` | return an empty vector |

## Error string catalog

All decoding errors:

| Condition | Error text |
|---|---|
| Buffer ends inside a value, header or payload | `cbor: truncated input` |
| Additional info 28 / 29 / 30 on any major type, and 31 on major 0/1/6 | `cbor: reserved additional info 28` / `... 29` / `... 30` / `... 31` |
| Additional info 31 on major type 2/3/4/5 | `cbor: indefinite length not supported` |
| `0xff` (major 7 additional info 31) where a value is expected | `cbor: break outside indefinite item` |
| Initial byte with major type 6 | `cbor: tags not supported` |
| Major type 7 additional info 25/26/27 | `cbor: floats not supported` |
| Major type 7 additional info 0..19, or 24 with a value >= 32 | `cbor: simple values not supported` |
| Additional info 24/25/26/27 with an argument that fits a smaller form | `cbor: non-shortest form` |
| Major type 2/3/4/5 argument above `INT64_MAX` | `cbor: length overflow` |
| Major type 0/1 argument above `INT64_MAX` | `cbor: integer out of range` |
| Bytes remain after the top-level value | `cbor: trailing data after top-level value` |
| Container at depth >= 64 | `cbor: nesting depth exceeds limit of 64` |

Encoder errors (`cbor_encode_map`):

| Condition | Error text |
|---|---|
| `keys.len() != values.len()` | `cbor: map keys/values length mismatch` |
| Two encoded keys are byte-identical | `cbor: duplicate map key` |

## Complexity

| Operation | Complexity |
|---|---|
| `cbor_decode` | O(data.len()) |
| `cbor_reserialize` | O(input bytes) |
| all `cbor_encode_*` | O(payload bytes); `encode_map` adds O(pairs^2 * key length) comparisons |
| `cbor_token_count` / `root` / `kind` / `parent` / `first_child` / `child_count` / `next_sibling` / `token_start` / `token_end` / `int_value` / `bool_value` / `bytes_len` / `text_len` | O(1) |
| `cbor_child` | O(n) sibling steps |
| `cbor_bytes` / `cbor_text_bytes` / `cbor_token_bytes` | O(copied bytes) |

## Test plan

`tests/test_conformance.xi` (`module cbor_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. canonical integer encodings across every width boundary (0, 1, 10, 23,
   24, 255, 256, 65535, 65536, 2^32-1, 2^32, `INT64_MAX`, and the negative
   mirrors down to `INT64_MIN`);
2. integer decode and reserialize round-trips across the Int range;
3. non-shortest arguments are rejected (major 0/1/2/3/4/5/7);
4. reserved additional info 28-31 is rejected (each major-type family);
5. indefinite-length items are rejected (`0x5f`, `0x7f`, `0x9f`, `0xbf`);
6. major type 6 tags are rejected from the initial byte (including a
   truncated tag header);
7. floats (`0xf9`/`0xfa`/`0xfb`, complete and truncated) and unsupported
   simple values (0..19, ai 24 >= 32, missing simple byte) are rejected;
8. `0xff` break outside indefinite items and trailing data are rejected;
9. byte-string encodings, decode and payload access (empty, "spam",
   offsets, token bytes, reserialize);
10. text-string encodings, UTF-8 byte length, rebuilt `Str`, negative
    cross-kind lengths;
11. malformed/truncated headers and out-of-range arguments are rejected
    (truncated header arguments, `length overflow`, `integer out of
    range`);
12. array encodings, child ranges and round-trip (empty, flat, nested,
    sibling walk);
13. map decode, pair children and order-preserving reserialize (canonical
    encode, empty map, hand-written unsorted map);
14. map encoder sorts keys bytewise and rejects duplicates and length
    mismatch;
15. false/true/null/undefined encode and decode, including wrong-kind
    accessor values;
16. nesting depth cap: 64 nested arrays and 64 nested maps accepted, 65
    rejected;
17. compound encode/decode/reserialize round-trip (text keys, nested
    array, bool, null, byte string, negative int; key lookup by scan);
18. accessors are bounds-safe and report source offsets;
19. hand-written nested map/array decode reconstructs exact bytes (token
    counts, offsets, token slices);
20. string length boundaries 23/24/255/256/65535/65536 (bytes and text),
    plus the 300-byte text header bytes.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.cbor
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- **Integer range.** Major type 0 values above `INT64_MAX` and major type 1
  values below `INT64_MIN` are rejected (`integer out of range`). This is
  the documented signed 64-bit subset; there is no unsigned or
  arbitrary-precision fallback.
- **No tags**, so semantic content (dates, bignums, decimals, UUIDs) is out
  of scope; a tagged document is rejected rather than skipped.
- **No floats**, so all floating-point payloads are rejected; a lossless
  pure-XIOM float round-trip does not exist in v0.61.3.
- **No indefinite-length items or CBOR sequences.**
- **Strict shortest form on decode**, beyond RFC 8949 well-formedness.
- **No UTF-8 validation.** Text strings are opaque bytes.
- **Map key order is not validated on decode**; only `cbor_encode_map`
  enforces RFC 8949 core-deterministic order.
- **Depth cap 64** for both arrays and maps; deeper documents must be
  handled by another tool.
- **Flat encoder input.** Container encoders take already-encoded chunks
  and do not re-validate them.
- **O(pairs^2) map encoding** (selection sort), no incremental builder.
- Not thread-safe; documents are plain value types.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_int`/`_err_int`/`_ok_doc`/`_err_doc`/`_ok_bytes`/`_err_bytes`
  (constructing Results in other functions miscompiles in this compiler).
- Every byte read from a `Vec[UInt8]` is widened with
  `(data[pos] as Int) & 0xFF` before arithmetic or comparison, and every
  `Vec[Int]` element read is bound to a typed local first (BUG-17 family).
- `&struct.field` is never passed where a `&Vec[UInt8]` parameter is
  expected (that yields an empty vector); payload copies go through helpers
  that take the owning struct reference.
- Big-endian arguments are decoded with an explicit positive-accumulator
  overflow check (`v > (INT64_MAX - b) / 256`), and encoded with arithmetic
  byte extraction rather than shifts or masked-but-sign-extended `UInt8`
  constants.
- Recursive descent is used for decode and for reserialize; the depth cap
  bounds decode recursion, and the encoder is flat (chunks are pre-encoded).
- No `Vec[StructType]`: all token state lives in parallel `Vec` fields.
- `string.str_len` gives the UTF-8 byte length of a `Str`; payload bytes
  are pushed through `xiom.string.builder.sb_push_str`.
- No FFI: the package declares no `extern "C"` blocks.
