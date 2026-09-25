# xiom.bencode -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.bencode`, version `0.1.0`).
Module: `src/bencode.xi` (`module xiom.bencode`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`, `xiom.convert`).
No FFI.

## Scope

A pure-XIOM bencode codec for a documented subset:

- strict decoding of exactly one top-level value with deterministic
  `Err(Str)` diagnostics and a documented nesting-depth cap;
- canonical encoding of integers, byte strings, lists and dictionaries
  (dictionary keys sorted byte-wise ascending, duplicates rejected);
- a flat token representation (parallel `Vec` fields; no
  `Vec[StructType]`) with parent/child/sibling links and source-offset
  ranges for payloads;
- token accessors, dictionary lookup by binary search, and
  `bencode_reserialize`: rebuild the exact canonical bytes from the token
  stream;
- encode/decode/reserialize round-trips for the whole supported subset.

## Non-goals

- `.torrent` metadata semantics (announce/info/piece hashes and any other
  BitTorrent application-layer meaning).
- UTF-8 validation or decoding: byte strings are opaque; `encode_str` copies
  the `Str` bytes verbatim with their byte length.
- Streaming/incremental decode or encode over sockets/files.
- Arbitrary-precision integers (bencode has no range limit; this subset
  requires the signed 64-bit platform `Int`).
- A recursive `Value` tree, a builder API that appends tokens, or a
  pretty-printer.
- A JSON/YAML-style dynamic API; only the token/offset representation is
  exposed.

## Grammar

Byte-level grammar of the accepted language (all bytes not listed are
rejected):

```
document   = value
value      = integer / string / list / dictionary
integer    = %x69 [ "-" ] int-digits %x65            ; "i" ... "e"
int-digits = "0" / ( nonzero *digit )
string     = length ":" *OCTET
length     = "0" / ( nonzero *digit )
list       = %x6C *value %x65                        ; "l" ... "e"
dictionary = %x64 *( string value ) %x65             ; "d" ... "e"
nonzero    = %x31-39
digit      = %x30-39
```

Validation rules enforced by `bencode_decode`:

1. `document` is exactly one `value`; any byte after it is
   `bencode: trailing data after top-level value`.
2. Integer digits are required; leading zeros (`i03e`) and negative zero
   (`i-0e`) are rejected. The magnitude must fit the signed 64-bit `Int`;
   `INT64_MIN` (`i-9223372036854775808e`) is accepted exactly.
3. String lengths are required and have no leading zeros (`05:` is
   rejected). A length that does not fit `Int` is a length overflow; a
   length that exceeds the remaining bytes is truncation.
4. Dictionary keys must be byte strings. Each key is compared with its
   predecessor unsigned byte-wise: equal keys are a duplicate-key error,
   descending keys an order violation. Consequently keys are strictly
   ascending in every accepted document.
5. Containers are nested at most 64 levels deep (`bencode_max_depth()`),
   counted with the top-level container at depth 0; a container at depth 64
   is rejected with the depth message.
6. Every read is bounds-checked; a buffer that ends inside a value, header
   or payload is truncation.

Note that real-world bencode in the wild is often lax about rules 2, 3 and
4 and about trailing bytes. This codec is deliberately strict: every
document it produces with `bencode_encode_*` re-decodes cleanly, and every
document it accepts is canonical.

## Types

```xi
pub type BencodeDoc = {
  data: Vec[UInt8];          // source bytes (payloads are offset ranges)
  kind: Vec[Int];            // bencode_kind_* code per token
  parent: Vec[Int];          // parent token, -1 for the root
  first_child: Vec[Int];     // first direct child, -1 for leaves
  child_count: Vec[Int];     // number of direct children
  next_sibling: Vec[Int];    // next direct sibling, -1 for the last child
  start: Vec[Int];           // first byte of the token
  end: Vec[Int];             // one past the last byte of the token
  payload_start: Vec[Int];   // int: first digit; str: first payload byte
  payload_end: Vec[Int];     // int: one past last digit; str: one past payload
  value: Vec[Int];           // int: parsed value; str: payload length
}
```

Tokens are appended in depth-first pre-order, so a token's whole subtree
occupies the contiguous index range that follows it. A container's direct
children are *not* generally adjacent (a child's subtree sits between it and
its next sibling); iterate them with `bencode_first_child` +
`bencode_next_sibling` or `bencode_child`.

`payload_start`/`payload_end` are meaningful for `kind` 0 (integer digit
text between `i` and `e`) and `kind` 1 (payload bytes after `:`). `value` is
meaningful for `kind` 0 (the integer) and `kind` 1 (the byte length).

Kind codes (`bencode_kind_*`):

| Code | Kind | Meaning |
|---|---|---|
| 0 | `bencode_kind_int()` | `i<n>e` |
| 1 | `bencode_kind_str()` | `<len>:<bytes>` |
| 2 | `bencode_kind_list()` | `l...e` |
| 3 | `bencode_kind_dict()` | `d...e` |

Dictionary children alternate key, value: pair `k` is child `2*k` (a
byte-string token) and child `2*k + 1` (its value token).

## API contract

All functions are free functions in module `xiom.bencode`.

```xi
pub type BencodeDoc = { ... }

pub fn bencode_decode(data: Vec[UInt8]) -> Result[BencodeDoc, Str]
pub fn bencode_reserialize(doc: &BencodeDoc) -> Vec[UInt8]

pub fn bencode_kind_int() -> Int
pub fn bencode_kind_str() -> Int
pub fn bencode_kind_list() -> Int
pub fn bencode_kind_dict() -> Int
pub fn bencode_max_depth() -> Int

pub fn bencode_token_count(doc: &BencodeDoc) -> Int
pub fn bencode_root(doc: &BencodeDoc) -> Int
pub fn bencode_kind(doc: &BencodeDoc, i: Int) -> Int
pub fn bencode_parent(doc: &BencodeDoc, i: Int) -> Int
pub fn bencode_first_child(doc: &BencodeDoc, i: Int) -> Int
pub fn bencode_child_count(doc: &BencodeDoc, i: Int) -> Int
pub fn bencode_next_sibling(doc: &BencodeDoc, i: Int) -> Int
pub fn bencode_child(doc: &BencodeDoc, i: Int, n: Int) -> Int
pub fn bencode_token_start(doc: &BencodeDoc, i: Int) -> Int
pub fn bencode_token_end(doc: &BencodeDoc, i: Int) -> Int
pub fn bencode_int_value(doc: &BencodeDoc, i: Int) -> Int
pub fn bencode_str_len(doc: &BencodeDoc, i: Int) -> Int
pub fn bencode_str_bytes(doc: &BencodeDoc, i: Int) -> Vec[UInt8]
pub fn bencode_token_bytes(doc: &BencodeDoc, i: Int) -> Vec[UInt8]
pub fn bencode_dict_get(doc: &BencodeDoc, i: Int, key: &Vec[UInt8]) -> Int

pub fn bencode_encode_int(n: Int) -> Vec[UInt8]
pub fn bencode_encode_bytes(bytes: &Vec[UInt8]) -> Vec[UInt8]
pub fn bencode_encode_str(s: Str) -> Vec[UInt8]
pub fn bencode_encode_list(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8]
pub fn bencode_encode_dict(keys: &Vec[Vec[UInt8]], values: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str]
```

Semantics:

`bencode_decode(data)`
: Decodes exactly one value from `data` (taken by value; the document owns
  the bytes). Returns `Ok(BencodeDoc)` with at least one token, or `Err` from
  the catalog below. The token stream is never partially returned.

`bencode_reserialize(doc)`
: Rebuilds canonical bytes from the token stream: integers via decimal
  formatting of `value`, strings via `len` + payload bytes, containers via
  recursively reserializing the sibling chain between the delimiters. It
  does not copy `data`, so it is a genuine reconstruction check. For a
  document returned by `bencode_decode` the result equals the original
  input; an empty document yields an empty vector.

`bencode_encode_int(n)`
: `i` + `convert.int_to_string(n)` + `e`; exact for `INT64_MIN..INT64_MAX`.

`bencode_encode_bytes(bytes)`
: `convert.int_to_string(bytes.len())` + `:` + the bytes verbatim.

`bencode_encode_str(s)`
: Same as `bencode_encode_bytes` over the UTF-8 bytes of `s`; the length is
  `string.str_len(s)` (byte length). No validation is performed.

`bencode_encode_list(parts)`
: `l` + each chunk in order + `e`. Chunks are already-encoded bencode
  values; no validation is performed (the caller composes the value).

`bencode_encode_dict(keys, values)`
: Pairs `keys[i]` (raw key bytes) with `values[i]` (an already-encoded
  bencode value). The output emits keys as bencode byte strings in unsigned
  byte-wise ascending order, so it re-decodes canonically.
  `Err("bencode: dict keys/values length mismatch")` when the vectors differ
  in length; `Err("bencode: duplicate dict key")` when any two keys are
  equal. O(pairs^2) key comparisons (selection sort).

`bencode_dict_get(doc, i, key)`
: Returns the value token index for raw `key` bytes in the dict token `i`,
  or -1 when `i` is not a dict token, the key is absent, or `i` is out of
  range. Binary search over the strictly ascending keys with unsigned
  byte-wise comparison.

Accessor bounds behavior:

| Accessor | Out-of-range / wrong kind behavior |
|---|---|
| `bencode_kind`, `bencode_parent`, `bencode_first_child`, `bencode_token_start`, `bencode_token_end`, `bencode_next_sibling`, `bencode_child` | return -1 |
| `bencode_child_count` | returns 0 |
| `bencode_int_value` | returns 0 (check the kind first) |
| `bencode_str_len` | returns -1 |
| `bencode_str_bytes`, `bencode_token_bytes` | return an empty vector |
| `bencode_dict_get` | returns -1 |

## Error string catalog

All decoding errors:

| Condition | Error text |
|---|---|
| Buffer ends inside a value, header or payload | `bencode: truncated input` |
| First byte is not `i`, `l`, `d` or a length digit | `bencode: bad type byte 0xNN` (`NN` = two lowercase hex digits) |
| Integer digit run empty or containing a non-digit; leading zero | `bencode: bad integer digits` |
| Negative zero (`i-0e`) | `bencode: negative zero in integer` |
| Integer magnitude outside the signed 64-bit range | `bencode: integer overflow` |
| Integer not terminated by `e`; string length not terminated by `:` | `bencode: bad delimiter` |
| String length with a leading zero | `bencode: bad length digits` |
| String length outside the signed 64-bit range | `bencode: string length overflow` |
| Dictionary key not starting with a length digit | `bencode: dict key must be a byte string` |
| Key strictly less than the previous key (byte-wise) | `bencode: dict key order violation` |
| Key equal to the previous key (byte-wise) | `bencode: duplicate dict key` |
| Bytes remain after the top-level value | `bencode: trailing data after top-level value` |
| Container at depth >= 64 | `bencode: nesting depth exceeds limit of 64` |

Encoder errors (`bencode_encode_dict`):

| Condition | Error text |
|---|---|
| `keys.len() != values.len()` | `bencode: dict keys/values length mismatch` |
| Two keys are equal | `bencode: duplicate dict key` |

`bencode: bad length digits` for an empty length run is unreachable through
`bencode_decode`: a `:` as the first byte of a value is reported as
`bad type byte 0x3a` instead.

## Complexity

| Operation | Complexity |
|---|---|
| `bencode_decode` | O(data.len()) |
| `bencode_reserialize` | O(input bytes) |
| all `bencode_encode_*` | O(payload bytes); `encode_dict` adds O(pairs^2 * key length) comparisons |
| `bencode_token_count` / `root` / `kind` / `parent` / `first_child` / `child_count` / `next_sibling` / `token_start` / `token_end` / `int_value` / `str_len` | O(1) |
| `bencode_child` | O(n) sibling steps |
| `bencode_str_bytes` / `bencode_token_bytes` | O(copied bytes) |
| `bencode_dict_get` | O(log pairs * key length) |

## Test plan

`tests/test_conformance.xi` (`module bencode_tests`, 19 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. integer encodings match canonical bytes (0, 1, 42, -1, -42, 127,
   `INT64_MAX`, `INT64_MIN`);
2. integer decode across the Int range;
3. malformed integers are rejected with catalog messages (truncation,
   empty/non-digit digits, leading zero, `-0`, bad delimiter, `INT64_MAX+1`,
   `INT64_MIN-1`, long overflow);
4. byte-string encodings (`encode_bytes`, `encode_str`, empty payload);
5. byte-string decode and payload access (length, bytes, offsets, token
   bytes, reserialize, empty string);
6. malformed byte strings are rejected (truncation, missing colon, bad
   delimiter, leading zero, length overflow, `0x3a`/`0x81` type bytes);
7. list decode and child ranges (empty, flat, nested; parent/child links);
8. list encodings and round-trip (empty, flat, nested with sibling walk);
9. dictionary decode, lookup and structure (children, dict_get hit/miss,
   non-dict lookup);
10. dictionary ordering and duplicate errors (order violation, duplicate,
    non-string key, truncations);
11. dictionary encoder sorts keys and rejects duplicates and length
    mismatch; empty dict;
12. trailing data and unrecognized type bytes (`0x00`, `0x78`, `0xff`);
13. nesting depth cap: 64 nested lists/dicts accepted, 65 rejected;
14. reserialize rebuilds canonical compound bytes from a dict/list tree;
15. accessors are bounds-safe and report source offsets;
16. UTF-8 payload byte length and round-trip (rebuilt Str compares equal);
17. encode/decode/reserialize round-trips every int boundary;
18. dictionary keys compare as unsigned bytes (0xC3-prefixed key ordering,
    descending and duplicate high-byte keys);
19. compound encode/decode/reserialize round-trip (nested list inside a
    sorted dict inside a list).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.bencode
```

Last verified: compiler 0.61.3,
`port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Known limitations

- **Integer range.** Values outside `INT64_MIN..INT64_MAX` are an overflow
  error. Bencode itself allows arbitrary-precision integers; a document
  containing one is rejected rather than wrapped or truncated.
- **No `.torrent` semantics**: no announce/info parsing, piece hashing or
  info-hash computation.
- **No UTF-8 validation or decoding.** Byte strings are opaque. `Str`
  payloads are copied verbatim.
- **No streaming.** The whole buffer must be in memory, and `BencodeDoc`
  retains it (payloads are offsets into `data`).
- **Strict canonicality on decode.** Non-canonical integers, unordered or
  duplicate dictionary keys and trailing bytes are rejected even though
  other bencode implementations may accept them.
- **Depth cap 64** for both containers; deeper documents must be handled by
  another tool.
- **Flat encoder input.** `bencode_encode_list`/`bencode_encode_dict` take
  already-encoded chunks; the caller is responsible for composing valid
  element encodings (the encoders do not re-validate chunks).
- **O(pairs^2) dict encoding** (selection sort) and no incremental dict
  builder.
- Not thread-safe; documents are plain value types.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_int`/`_err_int`/`_ok_doc`/`_err_doc`/`_ok_bytes`/`_err_bytes`
  (constructing Results in other functions miscompiles in this compiler).
- Every byte read from a `Vec[UInt8]` is widened with
  `(data[pos] as Int) & 0xFF` before arithmetic or comparison, and every
  `Vec[Int]` element read is bound to a typed local first (BUG-17 family).
- `&struct.field` is never passed where a `&Vec[UInt8]` parameter is
  expected (that yields an empty vector); payload comparisons go through
  helpers that take the owning struct reference.
- Integer parsing accumulates the magnitude positively with an explicit
  overflow check and recognizes `INT64_MIN` structurally, because negating
  `INT64_MIN` overflows.
- Recursive descent is used for decode and for reserialize; the depth cap
  bounds both.
- `int_to_string` is `xiom.convert.int_to_string` (exact for `INT64_MIN`).
- No FFI: the package declares no `extern "C"` blocks.
