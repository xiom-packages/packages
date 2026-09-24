# xiom.varint -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.varint`, version `0.1.0`).
Module: `src/varint.xi` (`module xiom.varint`).
Depends on `xiom.std` only (platform dependency; the module itself imports
nothing).

## Scope

A pure-XIOM (no FFI) codec for LEB128 varints over in-memory `Vec[UInt8]`:

- unsigned LEB128 encoding and decoding for the 64-bit domain;
- zigzag signed varint encoding and decoding;
- encoded-size and canonicality predicates.

## Non-goals

- Signed LEB128 (the sign-extended encoding defined by DWARF/WebAssembly);
  signed values are handled with zigzag only.
- Arbitrary precision: the value domain is 64 bits.
- Streaming over sockets/files; the API works on byte vectors.
- Decoder-side canonicality enforcement: `varint_decode_u` /
  `varint_decode_zigzag` accept any valid encoding; canonical form is an
  explicit predicate (`varint_is_canonical_u`).
- Buffer building/append helpers: encoders return a fresh vector.

## Encoding rules

Unsigned LEB128 (`varint_encode_u`):

- The value is split into 7-bit groups, least significant group first.
- Bit 7 of each byte is the continuation flag; the final byte has it clear.
- Only `n >= 0` is encodable. `n < 0` returns an **empty** `Vec[UInt8]`
  (caller error; the API cannot return `Err`).
- The encoding is minimal: `0` is the single byte `0x00`; a value uses the
  fewest groups that can represent it.
- Encodable range: `0 .. 2^63-1` (the positive domain of the platform
  `Int`), i.e. at most 9 encoded bytes.

| Value | Group decomposition | Bytes |
|---|---|---|
| `0` | `0` | `00` |
| `1` | `1` | `01` |
| `127` | `127` | `7f` |
| `128` | `0`, `1` | `80 01` |
| `300` | `44`, `2` | `ac 02` |
| `624485` | `101`, `14`, `38` | `e5 8e 26` |
| `4294967295` | `127,127,127,127,15` | `ff ff ff ff 0f` |
| `2^63-1` | `127 x9` | `ff x8 7f` |

`varint_size_u(n)` returns the number of bytes the minimal encoding of `n`
uses (`0` for `n < 0`), so for every encodable `n`:
`varint_size_u(n) == varint_encode_u(n).len()`.

## Decoding rules

`varint_decode_u(data, off)` walks at most 10 bytes starting at `off`:

- `off < 0` -> `Err("varint: negative offset")`.
- The buffer ending before the terminating byte -> `Err("varint: truncated")`.
- The 10th byte may carry only bit 63 (payload `0x00` or `0x01`) and must
  clear the continuation flag; a set continuation bit at the 10th byte
  (an 11th byte would be required) or payload bits above bit 63 ->
  `Err("varint: overflow")`.
- On success it returns `Ok((value, next))` where `next` is the offset just
  past the last consumed byte and `1 <= next - off <= 10`.

Bit 63 semantics: the platform `Int` is signed 64-bit, so a decoded value
with bit 63 set is returned as the same two's-complement bit pattern
interpreted as a signed `Int`. Concretely, `ff*9 01` decodes to `-1`,
`80*9 01` decodes to `INT64_MIN`, and `2^63-1` (`ff*8 7f`) is the largest
value that decodes non-negative. No error is raised for this case.

Non-minimal encodings (e.g. `80 00` for `0`) are accepted by the decoder;
see Canonicality.

`varint_decode_zigzag(data, off)` first decodes the unsigned value `z`
exactly like `varint_decode_u` (all of its errors propagate unchanged) and
then un-maps it into the signed domain:

- `z` even -> `z / 2`;
- `z` odd -> `-(z / 2) - 1`.

The un-mapping is computed from the raw 7-bit groups, so `INT64_MIN`
decodes correctly from `ff*9 01`.

## Zigzag

Zigzag maps signed values to the unsigned domain so that small-magnitude
negative numbers stay short:

```
zigzag(n) = 2n        for n >= 0
zigzag(n) = -2n - 1   for n < 0
```

| Signed value | Zigzag value | Encoded bytes |
|---|---|---|
| `0` | `0` | `00` |
| `-1` | `1` | `01` |
| `1` | `2` | `02` |
| `-2` | `3` | `03` |
| `2` | `4` | `04` |
| `63` | `126` | `7e` |
| `64` | `128` | `80 01` |
| `-64` | `127` | `7f` |
| `-65` | `129` | `81 01` |
| `INT64_MAX` | `2^64-2` | `fe ff ff ff ff ff ff ff ff 01` |
| `INT64_MIN` | `2^64-1` | `ff ff ff ff ff ff ff ff ff 01` |

`varint_encode_zigzag` computes the mapping arithmetically without relying
on two's-complement shifts: for `n >= 0` it encodes `2k` with `k = n`, and
for `n < 0` it encodes `2k + 1` with `k = |n| - 1`, folding the `+1` into a
base-128 digit carry. `INT64_MIN` therefore never evaluates `-n` (which
would overflow) and encodes as the maximal 10-byte form.

## Canonicality

`varint_is_canonical_u(data, off)` returns true when the encoding at `off`
is the minimal encoding of its decoded value:

- it decodes successfully, and
- the consumed byte count equals `varint_size_u(value)` when bit 63 is
  clear, or 10 when bit 63 is set.

Since a fixed byte length and value determine the bytes uniquely in
LEB128, this is equivalent to "the decoded value re-encodes to the same
bytes". Examples:

| Bytes at `off` | Result | Reason |
|---|---|---|
| `00` | true | minimal zero |
| `7f` | true | minimal |
| `80 01` | true | minimal 128 |
| `80 00` | false | overlong zero (2 bytes) |
| `81 00` | false | overlong 1 (2 bytes) |
| `ac 82 00` | false | overlong 300 (3 bytes) |
| `80*9 00` | false | overlong zero (10 bytes) |
| `ff*8 7f` | true | minimal `2^63-1` |
| `ff*9 01` | true | minimal bit pattern `2^64-1` |

## Error catalog

| Condition | Error text |
|---|---|
| `off < 0` | `varint: negative offset` |
| Buffer ends before the terminating byte | `varint: truncated` |
| 10th byte has the continuation flag set (an 11th byte would be required) | `varint: overflow` |
| 10th byte carries payload bits above bit 63 | `varint: overflow` |

`varint_decode_zigzag` returns the same four errors (propagated from
`varint_decode_u`).

## API signatures

All functions are free functions in module `xiom.varint`:

```xi
pub fn varint_encode_u(n: Int) -> Vec[UInt8]
pub fn varint_encode_zigzag(n: Int) -> Vec[UInt8]
pub fn varint_decode_u(data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str]
pub fn varint_decode_zigzag(data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str]
pub fn varint_size_u(n: Int) -> Int
pub fn varint_is_canonical_u(data: &Vec[UInt8], off: Int) -> Bool
```

## Complexity

| Operation | Complexity |
|---|---|
| `varint_encode_u` / `varint_encode_zigzag` | O(bytes) <= O(10) |
| `varint_decode_u` | O(bytes) <= O(10) |
| `varint_decode_zigzag` | O(bytes) <= O(10) |
| `varint_size_u` | O(bytes) <= O(10) |
| `varint_is_canonical_u` | O(bytes) <= O(10) |

## Test plan

`tests/test_conformance.xi` (`module varint_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. `varint_encode_u` pinned at 0, 1, 127, 128, 300, 624485;
2. `varint_encode_u` pinned at 2^32-1 and 2^63-1;
3. negative `n` encodes to an empty vector, `varint_size_u` is 0;
4. `varint_size_u` equals the encoded length across a boundary table;
5. `varint_decode_u` pinned single/two-byte (0, 1, 42, 127, 128, 129, 300);
6. `varint_decode_u` pinned multi-byte (624485, 2^32-1, 2^63-1);
7. decoding honours non-zero offsets in a stream;
8. empty and truncated buffers and negative offsets are `Err`;
9. 11-byte and >64-bit encodings are `Err(varint: overflow)`;
10. 10-byte encodings decode (2^64-1 -> -1, 2^63 -> INT64_MIN);
11. encode/decode round-trips including a non-zero offset in a stream;
12. zigzag pinned: 0, -1, 1, -2, 2;
13. zigzag extremes: INT64_MIN, INT64_MAX, -(2^63-1);
14. `varint_decode_zigzag` pinned incl. 10-byte INT64_MIN/INT64_MAX;
15. zigzag round-trips across the signed range;
16. canonical minimal forms (incl. 10-byte `2^63-1` and `2^64-1`);
17. overlong forms (`80 00`, `81 00`, `ac 82 00`, `80*9 00`) are not
    canonical, while the 10-byte `2^63` form is;
18. empty buffer and out-of-range offsets are `Err` for both decoders;
19. decoders and canonicality honour a non-zero offset;
20. size/decode consistency across two-group boundaries.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.varint
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- 64-bit domain only; bit-63 values decode as the signed bit pattern and
  >10-byte encodings are rejected.
- No signed LEB128 (sign-extended) variant.
- Encoders have no error channel: `varint_encode_u(n < 0)` is an empty
  vector.
- The decoders accept non-canonical encodings; canonical form is a
  separate predicate.
- Plain value functions; no thread-safety concerns beyond the underlying
  `Vec` ownership model.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_pair` /
  `_err_pair` (constructing Results directly in other functions
  miscompiles in this compiler).
- Raw bytes widen through `(x as Int) & 0xFF` before use.
- No `<<` shift is relied on: decode accumulates groups with a `place`
  factor (multiply by 128), and encode uses modulo/division only.
- The zigzag encoder folds the `+1` into a base-128 digit carry so
  `INT64_MIN` never evaluates `-n`; the zigzag decoder rebuilds
  `floor(z / 2)` from the raw groups instead of dividing a negative
  bit pattern.
- Tests compare `Str` errors with `str_compare`
  (`xiom.string.compare`), never with `==`.
