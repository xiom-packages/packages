# xiom.tlv -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.tlv`, version `0.1.0`).
Module: `src/tlv.xi` (`module xiom.tlv`).
Depends on `xiom.std`; the library module imports nothing from it (tests add
`xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare`,
`xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) codec for flat, big-endian TLV streams:

- `tlv_parse` walks a buffer of concatenated entries until it ends and
  returns a `TlvList` index (tags plus absolute value offsets/lengths);
- `tlv_append` / `tlv_build_from` write the same layout with caller-chosen
  widths;
- `tlv_count` / `tlv_tag` / `tlv_value` / `tlv_find` read the index back;
- `tlv_size` computes one entry's encoded size;
- deterministic `Err(Str)` messages for malformed input and invalid
  widths/sizes.

## Non-goals

- Nested TLVs / recursive trees: a value that is itself a TLV stream is the
  caller's responsibility to re-parse.
- Length-includes-header variants (the length counts value bytes only).
- Width negotiation/serialization: `tag_size`/`length_size` are out-of-band
  parameters and must match between build and parse.
- Signed tags, BER/DER indefinite lengths, end-of-stream padding rules.
- Text decoding/UTF-8 validation of values.
- Streaming/incremental parsing: the whole stream is an in-memory
  `Vec[UInt8]`.

## Byte-level layout

One entry, with caller widths `tag_size` (`T`) and `length_size` (`L`),
both in `1..4`:

| Field | Width | Encoding |
|---|---|---|
| tag | `T` bytes | unsigned big-endian |
| length | `L` bytes | unsigned big-endian, counts value bytes only |
| value | `length` bytes | raw bytes, verbatim |

A stream is entries concatenated with no padding, terminator or count
field. `tlv_parse` walks from offset 0: it reads a header, bounds-checks the
declared value against the remaining bytes, records
`value_offsets[i] = pos` and `value_lengths[i] = length`, then continues
after the value. Parsing stops exactly when the buffer ends; because a
nonzero tail shorter than `T + L` cannot be a header, it is an error rather
than an implicitly truncated entry.

Width ranges:

| `tag_size` / `length_size` | Maximum unsigned field value |
|---|---|
| 1 | 255 |
| 2 | 65535 |
| 3 | 16777215 |
| 4 | 4294967295 |

## API signatures

All functions are free functions in module `xiom.tlv` (no self methods):

```xi
pub type TlvList = {
  tags: Vec[Int];
  value_offsets: Vec[Int];
  value_lengths: Vec[Int];
}

pub fn tlv_parse(data: &Vec[UInt8], tag_size: Int, length_size: Int) -> Result[TlvList, Str]
pub fn tlv_count(l: &TlvList) -> Int
pub fn tlv_tag(l: &TlvList, i: Int) -> Int
pub fn tlv_value(data: &Vec[UInt8], l: &TlvList, i: Int) -> Result[Vec[UInt8], Str]
pub fn tlv_find(l: &TlvList, tag: Int) -> Int
pub fn tlv_append(out: &mut Vec[UInt8], tag: Int, value: &Vec[UInt8], tag_size: Int, length_size: Int) -> Result[Unit, Str]
pub fn tlv_build_from(tags: &Vec[Int], values: &Vec[Vec[UInt8]], tag_size: Int, length_size: Int) -> Result[Vec[UInt8], Str]
pub fn tlv_size(tag_size: Int, length_size: Int, value_len: Int) -> Int
```

## Semantics

`tlv_parse(data, tag_size, length_size)`
: Widths are validated first. An empty buffer yields `Ok` with zero entries.
  Offsets are absolute indices into `data`; an entry with a zero length is
  valid and has an offset pointing at its (empty) value span. On `Err`,
  nothing is returned (no partial list).

`tlv_tag(l, i)`
: Returns `-1` when `i < 0` or `i >= tlv_count(l)`; no error channel.

`tlv_find(l, tag)`
: Linear scan in stream order; the first matching index wins. Returns `-1`
  when no entry matches (including on an empty list).

`tlv_value(data, l, i)`
: `Err("tlv: index out of range")` for a bad `i`; otherwise the recorded
  span is bounds-checked against `data` and the bytes are copied into a
  fresh vector.

`tlv_append(out, tag, value, tag_size, length_size)`
: Validates widths, then `tag >= 0`, then the tag width, then the value
  width, in that order. Nothing is appended unless every check passes, so
  `out` is byte-for-byte unchanged on `Err` (atomic failure).

`tlv_build_from(tags, values, tag_size, length_size)`
: Validates widths, then `tags.len() == values.len()`, then appends each
  entry with `tlv_append`; the first failing entry surfaces its error
  unchanged. An empty pair of vectors yields `Ok(empty)`.

`tlv_size(tag_size, length_size, value_len)`
: `tag_size + length_size + value_len` for valid widths and
  `value_len >= 0`; `-1` otherwise.

## Error string catalog

| Condition | Error text |
|---|---|
| `tlv_parse`/`tlv_append`/`tlv_build_from`: `tag_size` outside `1..4` | `tlv: invalid tag size` |
| `tlv_parse`/`tlv_append`/`tlv_build_from`: `length_size` outside `1..4` | `tlv: invalid length size` |
| `tlv_append`: `tag < 0` | `tlv: negative tag` |
| `tlv_append`: `tag > 256^tag_size - 1` | `tlv: tag too large for tag_size` |
| `tlv_append`: `value.len() > 256^length_size - 1` | `tlv: value too large for length_size` |
| `tlv_build_from`: `tags.len() != values.len()` | `tlv: tags/values length mismatch` |
| `tlv_parse`: `0 < remaining < tag_size + length_size` | `tlv: truncated header` |
| `tlv_parse`: declared value length exceeds the remaining bytes | `tlv: value overruns buffer` |
| `tlv_value`: `i < 0` or `i >= tlv_count(l)` | `tlv: index out of range` |
| `tlv_value`: recorded span negative or beyond `data.len()` | `tlv: value out of bounds` |

Width errors are reported tag-first: when both widths are invalid, the
message is `tlv: invalid tag size`. In `tlv_append`, the check order is
widths, negative tag, tag width, value width. `tlv_size` has no error
channel and reports invalid inputs as `-1` instead.

## Complexity

| Operation | Complexity |
|---|---|
| `tlv_parse` | O(data.len()) |
| `tlv_count` / `tlv_tag` / `tlv_size` | O(1) |
| `tlv_find` | O(entries) |
| `tlv_value` | O(value length) |
| `tlv_append` | O(value length) |
| `tlv_build_from` | O(total value bytes) |

## Test plan

`tests/test_conformance.xi` (`module tlv_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. 1/1 three-entry hand-built stream: pinned tags, offsets, lengths and
   exact value slices (including an empty value);
2. 2/2 three-entry hand-built stream: pinned tags/offsets/lengths and exact
   slices;
3. mixed 1/2 widths: pinned offsets plus an unsigned `0xff` tag;
4. `tlv_find` first-match at a duplicate tag and `-1` for missing tags and
   an empty list;
5. exact value slices; bad index and a short source buffer are the two
   documented `tlv_value` errors;
6. `tlv_append` at 1/1: exact bytes (`01 03 61 62 63 fe 00`);
7. `tlv_append` at 2/2: exact big-endian fields, including tag `65535`;
8. append errors (tag overflow, negative tag, value too large, widths
   0/5/-2) are `Err` and leave `out` empty;
9. `tlv_build_from` equals per-entry `tlv_append` byte-for-byte and parses
   back (tags 1, 2, 300 at 2/1);
10. empty buffer parses to zero entries; a lone zero-length header
    (`01 00`) is one entry with an empty value; empty `build_from` is
    `Ok(empty)`;
11. trailing partial headers are `Err("tlv: truncated header")` at 1/1 and
    2/2; a complete lone header is not an error;
12. declared values that exceed the buffer are
    `Err("tlv: value overruns buffer")`, including after a valid entry;
13. widths `0/5/-1` and length widths `0/5` are the documented width errors
    in both `tlv_parse` and `tlv_build_from`;
14. `tlv_count` and tag/value accessors report `-1` / `Err` out of range;
15. 3/2 round-trip: tags `0xFFFFFF`, `1`, `0x010203` and a 300-byte value
    survive build -> parse (length 316);
16. `tlv_size` is header + value length; `-1` for invalid widths/negative
    length; agrees with a real `build_from` length;
17. parse -> rebuild reproduces the original mixed-width bytes exactly;
18. 4/4 round-trip of high-bit tags/values (`0xFFFFFFFF`, `0x80000000`,
    `0xff`, `00 80`) and unsigned tag reads at 1 and 2 bytes.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.tlv
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Flat streams only (no nesting); no length-includes-header variants.
- Widths must be supplied by the caller and match between build and parse;
  a mismatch is not detected.
- Tags are unsigned; `tlv_append` rejects negative tags.
- `tlv_size` is the only API that reports invalid input without a `Result`
  (`-1`).
- Values are raw bytes with no UTF-8 validation.
- `TlvList` stores offsets into the parse buffer; `tlv_value` requires a
  buffer that still holds the recorded spans.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_list`/`_err_list`/`_ok_bytes`/`_err_bytes`/`_ok_unit`/`_err_unit`
  (constructing Results directly in other functions miscompiles in this
  compiler).
- All big-endian extraction/packing is arithmetic (modulo/division) because
  `& 0xFF` on operands with bit 31 set miscompiles (same bug documented in
  `xiom.convert.base58` and `xiom.msgpack`).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic.
- Advisory E001 ("cannot borrow as mutable while immutably borrowed") is
  avoided: `tlv_append` only takes `&mut out`, and all other entry points
  take immutable references.
- Str values in the tests are compared through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a Str read from a
  `Vec` lowers to a pointer comparison).
- The package declares no `extern "C"` blocks (no FFI).
