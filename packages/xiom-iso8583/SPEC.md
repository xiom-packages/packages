# xiom.iso8583 -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.iso8583`, version `0.1.0`).
Module: `src/iso8583.xi` (`module xiom.iso8583`).
Depends on `xiom.std`. The library module imports `xiom.string` and
`xiom.string.builder`; the tests add `xiom.test`, `xiom.io` and
`xiom.string.compare`. No FFI.

## Scope

A pure-XIOM (no FFI, no dependencies beyond `xiom.std`) codec for the ASCII
form of an ISO 8583 message:

- `iso8583_parse` decodes one message: 4-digit MTI, 16/32-digit hex bitmap,
  fixed and LLVAR/LLLVAR fields for the documented subset, with full
  bitmap/field presence validation;
- `iso8583_build` / `iso8583_build_message` construct a message from field
  numbers and parallel values (bitmap derived), and
  `iso8583_build_with_bitmap` additionally checks a caller-supplied bitmap
  (hex or binary) against the fields;
- `iso8583_bitmap_parse` / `iso8583_bitmap_of` convert standalone bitmap
  text in both directions;
- `iso8583_format` re-validates and serializes a message;
- accessors (`iso8583_mti`, `iso8583_has_secondary`,
  `iso8583_field_count`, `iso8583_field_number`, `iso8583_field_value`,
  `iso8583_field_index`, `iso8583_has_field`, `iso8583_get`) and field
  dictionary metadata (`iso8583_is_known_field`,
  `iso8583_is_variable_field`, `iso8583_field_max_length`);
- deterministic `Err(Str)` messages for every malformed input.

## Non-goals

- EBCDIC, packed BCD and binary field encodings; the wire form here is the
  ASCII dialect, and the bitmap is hex text, not raw bytes.
- The full ISO 8583 field dictionary; only the eleven documented fields
  exist, and any other set bit is an error.
- Tertiary and higher bitmaps (bit 65 set is rejected).
- MAC/PIN/security fields (52, 53, 64, ...), key management and
  message-level authentication.
- Framing, sockets, length headers, TCP/serial transport and retry logic.
- Semantic validation of field content beyond shape (no Luhn check, no
  currency table, no calendar validation, no amount arithmetic).
- Streaming/incremental parsing; a message is one in-memory `Str`.

## Wire layout

An ISO 8583 ASCII message is a flat, unpadded sequence of:

| Part | Width | Encoding |
|---|---|---|
| MTI | 4 chars | ASCII digits |
| primary bitmap | 16 chars | uppercase or lowercase hex digits |
| secondary bitmap | 16 chars | present only when bit 1 of the primary is set |
| fields | variable | ascending field number, no separators |

Bitmap bits are MSB-first and 1-based: bit 1 is the most significant bit of
the first hex digit, bit 4 is the least significant bit of the first hex
digit, bit 5 is the most significant bit of the second hex digit, and so
on. Bit `n` corresponds to field `n`; the primary bitmap covers bits
1..64, the secondary bitmap bits 65..128. Bit 1 is a marker for the
secondary bitmap and is never a field. Bit 65 set means a tertiary bitmap,
which this codec does not support.

Each field is encoded per its type:

| Type | On the wire |
|---|---|
| numeric fixed | exactly the fixed number of ASCII digits |
| alphanumeric fixed | exactly the fixed number of printable ASCII bytes (0x20..0x7E) |
| LLVAR numeric | 2 decimal digits of value length, then that many ASCII digits |
| LLLVAR alphanumeric | 3 decimal digits of value length, then that many printable ASCII bytes |

An LLVAR/LLLVAR length prefix of `00`/`000` is a present but empty value;
the field bit decides presence, not the value length.

## Field dictionary

| # | Meaning | Type | Length rule |
|---|---|---|---|
| 2 | Primary account number (PAN) | numeric | LLVAR, 0..19 |
| 3 | Processing code | numeric | fixed 6 |
| 4 | Amount, transaction | numeric | fixed 12 |
| 7 | Transmission date & time (MMDDhhmmss) | numeric | fixed 10 |
| 11 | System trace audit number (STAN) | numeric | fixed 6 |
| 32 | Acquiring institution id | numeric | LLVAR, 0..11 |
| 39 | Response code | alphanumeric | fixed 2 |
| 41 | Card acceptor terminal id | alphanumeric | fixed 8 |
| 48 | Additional data (private) | alphanumeric | LLLVAR, 0..999 |
| 49 | Currency code | alphanumeric | fixed 3 |
| 70 | Network management code | numeric | fixed 3 |

Fields 2, 3, 4, 7, 11, 32, 39, 41, 48, 49 live in the primary bitmap; field
70 lives in the secondary bitmap, so a message carrying field 70 always has
bit 1 set. Field 1 is not a field. Any other number is
`iso8583: unknown field number`. Field values are kept as byte vectors;
the caller interprets amounts (minor units), dates and codes.

## API signatures

All functions are free functions in module `xiom.iso8583` (no self methods):

```xi
pub type Iso8583Message = {
  mti: Str;
  has_secondary: Bool;
  field_numbers: Vec[Int];
  field_values: Vec[Vec[UInt8]];
}

pub type Iso8583Bitmap = {
  has_secondary: Bool;
  numbers: Vec[Int];
}

pub fn iso8583_parse(text: Str) -> Result[Iso8583Message, Str]
pub fn iso8583_format(m: &Iso8583Message) -> Result[Str, Str]
pub fn iso8583_build_message(mti: Str, numbers: &Vec[Int], values: &Vec[Vec[UInt8]]) -> Result[Iso8583Message, Str]
pub fn iso8583_build(mti: Str, numbers: &Vec[Int], values: &Vec[Vec[UInt8]]) -> Result[Str, Str]
pub fn iso8583_build_with_bitmap(mti: Str, bitmap: Str, numbers: &Vec[Int], values: &Vec[Vec[UInt8]]) -> Result[Str, Str]
pub fn iso8583_bitmap_parse(bitmap: Str) -> Result[Iso8583Bitmap, Str]
pub fn iso8583_bitmap_of(numbers: &Vec[Int]) -> Result[Str, Str]
pub fn iso8583_bitmap_hex(m: &Iso8583Message) -> Str

pub fn iso8583_mti(m: &Iso8583Message) -> Str
pub fn iso8583_has_secondary(m: &Iso8583Message) -> Bool
pub fn iso8583_field_count(m: &Iso8583Message) -> Int
pub fn iso8583_field_number(m: &Iso8583Message, i: Int) -> Int
pub fn iso8583_field_value(m: &Iso8583Message, i: Int) -> Str
pub fn iso8583_field_index(m: &Iso8583Message, number: Int) -> Int
pub fn iso8583_has_field(m: &Iso8583Message, number: Int) -> Bool
pub fn iso8583_get(m: &Iso8583Message, number: Int) -> Result[Str, Str]

pub fn iso8583_is_known_field(number: Int) -> Bool
pub fn iso8583_is_variable_field(number: Int) -> Bool
pub fn iso8583_field_max_length(number: Int) -> Int
```

## Semantics and check order

`iso8583_parse(text)`
: Checks in this order: `text.len() < 4` or a non-digit MTI is
  `bad mti`; fewer than 16 characters after the MTI, or a non-hex
  character in the primary bitmap, is `bad bitmap hex`; when bit 1 of the
  primary is set, fewer than 16 further characters is `bad bitmap length`;
  the bitmap parser then also rejects a bad hex character
  (`bad bitmap hex`) and a set bit 65 (`tertiary bitmap not supported`);
  a set bit outside the dictionary is `unknown field number`. Fields are
  decoded in ascending order: a declared field with zero characters left
  is `declared field missing`; a length prefix or a required field length
  that exceeds the remaining characters is `length overrun`; a non-decimal
  prefix or a declared variable length above the field maximum is
  `bad field length`; a character outside the field's character set is
  `bad field value`. Characters left after the last declared field are
  `trailing data`. An all-zero bitmap is a valid empty message. The first
  error aborts the call; no partial message is returned.

`iso8583_build_message(mti, numbers, values)`
: Validates the MTI, then `numbers` (each in 2..128, strictly ascending,
  known) and then `values` (parallel length, fixed length or variable
  maximum, character set), in that order. `has_secondary` is derived:
  true exactly when some number is 65 or above. The returned message owns
  copies of both vectors.

`iso8583_build(mti, numbers, values)`
: `iso8583_build_message` followed by `iso8583_format`; the bitmap is
  computed from `numbers` (16 digits when all are below 65, otherwise 32).

`iso8583_build_with_bitmap(mti, bitmap, numbers, values)`
: Parses `bitmap` (all `iso8583_bitmap_parse` errors apply), then requires
  the declared numbers to equal `numbers` element by element and the
  bitmap's secondary-bitmap presence to equal `_any_secondary(numbers)`;
  any mismatch is `bitmap/fields mismatch`. Then builds as
  `iso8583_build`.

`iso8583_bitmap_parse(bitmap)`
: Accepted lengths: 16 or 32 hex digits, or 64 or 128 binary digits.
  Any other length is `bad bitmap length`; a non-hex character (16/32
  form) is `bad bitmap hex`; a non-`0`/`1` character (64/128 form) is
  `bad bitmap binary`. In the 16/64 form, bit 1 set is
  `bad bitmap length` (a secondary bitmap must then be present). In the
  32/128 form, bit 1 clear with any secondary bit set is
  `unexpected secondary bitmap` (the secondary bits are ignored only when
  they are all clear), and bit 65 set is
  `tertiary bitmap not supported`. Set bits are resolved through the
  dictionary in ascending order; bit 1 is skipped. The returned
  `Iso8583Bitmap.numbers` is ascending.

`iso8583_bitmap_of(numbers)`
: Validates `numbers` like the builder and emits canonical uppercase hex:
  16 digits, or 32 when any number is 65 or above. An empty vector yields
  the all-zero 16-digit bitmap.

`iso8583_format(m)`
: Validates `mti`, `field_numbers`, `field_values` and the consistency of
  `has_secondary` with the numbers (same checks as the builder, plus
  `bitmap/fields mismatch` when `has_secondary` is false while some number
  is 65 or above; a true value with no secondary field is preserved, as
  `iso8583_parse` can produce it from a secondary bitmap with no set
  bits). Emits the MTI, the canonical uppercase bitmap, then each value
  with its LLVAR/LLLVAR length prefix. For every message produced by
  `iso8583_parse` or `iso8583_build_message` the call cannot fail.

Accessors
: `iso8583_field_number` returns `-1` out of range;
  `iso8583_field_value` returns `""` out of range;
  `iso8583_field_index` returns `-1` when the field is absent;
  `iso8583_get` returns `Err("iso8583: field not present")` when absent.
  `iso8583_bitmap_hex` assumes a well-formed message and does not fail.
  `iso8583_field_max_length` returns the fixed length for fixed fields,
  the variable maximum for LLVAR/LLLVAR fields and `-1` for unknown
  numbers.

## Error string catalog

| Condition | Error text |
|---|---|
| `parse`: text shorter than 4 chars, or MTI has a non-digit | `iso8583: bad mti` |
| `parse`: fewer than 16 chars after the MTI, or a non-hex bitmap character | `iso8583: bad bitmap hex` |
| `parse`/`bitmap_parse`: bitmap text length not 16/32/64/128, or 16/64 form with bit 1 set | `iso8583: bad bitmap length` |
| `bitmap_parse`: 64/128 form with a character other than `0`/`1` | `iso8583: bad bitmap binary` |
| `bitmap_parse`: 32/128 form, bit 1 clear, secondary bits set | `iso8583: unexpected secondary bitmap` |
| `parse`/`bitmap_parse`: bit 65 set | `iso8583: tertiary bitmap not supported` |
| `parse`/`bitmap_parse`/`build*`/`format`: a set bit or number outside the dictionary (below 2 or above 128 included) | `iso8583: unknown field number` |
| internal invariant guard (unreachable through the public API) | `iso8583: unknown field type` |
| `parse`: a declared field has zero characters left | `iso8583: declared field missing` |
| `parse`: required prefix/fixed/declared characters exceed the remaining characters | `iso8583: length overrun` |
| `parse`/`build*`/`format`: non-decimal prefix, fixed length mismatch, or variable length above the maximum | `iso8583: bad field length` |
| `parse`/`build*`/`format`: a character outside the field's character set | `iso8583: bad field value` |
| `parse`: characters remain after the last declared field | `iso8583: trailing data` |
| `build*`/`format`: numbers not strictly ascending (duplicates included) | `iso8583: field numbers out of order` |
| `build*`/`format`: `numbers.len() != values.len()` | `iso8583: field numbers/values length mismatch` |
| `build_with_bitmap`: bitmap numbers differ from `numbers`, or the bitmap's secondary presence differs from the derived one | `iso8583: bitmap/fields mismatch` |
| `format`: `has_secondary` false while a number is 65 or above | `iso8583: bitmap/fields mismatch` |
| `get`: the field is absent | `iso8583: field not present` |

Error precedence is the check order above. `parse` reports the first
failure; `build_message` reports MTI, then number, then value errors, with
the first failing number winning; `bitmap_parse` reports syntax before
bit 1 handling before dictionary lookup; `format` reports MTI, then
numbers, then values, then `has_secondary` consistency.

## Complexity

| Operation | Complexity |
|---|---|
| `iso8583_parse` / `iso8583_format` / `iso8583_build` | O(message length) |
| `iso8583_build_message` | O(total value bytes) |
| `iso8583_build_with_bitmap` | O(total value bytes + 128 bits) |
| `iso8583_bitmap_parse` / `iso8583_bitmap_of` / `iso8583_bitmap_hex` | O(1) (at most 128 bits) |
| `iso8583_field_count` / `iso8583_field_number` / `iso8583_field_value` | O(1) plus O(value length) for the value copy |
| `iso8583_field_index` / `iso8583_has_field` / `iso8583_get` | O(fields) plus O(value length) |

## Test plan

`tests/test_conformance.xi` (`module iso8583_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). The two wire fixtures are assembled from
pinned literal pieces whose bitmaps were computed independently:
`7220000002808000` for fields 2,3,4,7,11,39,41,49 and
`F2200001028180000400000000000000` for
2,3,4,7,11,32,39,41,48,49,70. Coverage:

1. primary-bitmap parse: MTI, `has_secondary` false, pinned field numbers,
   values through `iso8583_get` and `iso8583_field_value`, bitmap hex;
2. secondary-bitmap parse: field 70 forces bit 1, field 32 LLVAR, field 48
   LLLVAR, `has_field`/`field_index`, bitmap hex;
3. `iso8583_build` and `iso8583_build_message` + `iso8583_format`
   reproduce both fixtures byte-for-byte;
4. `iso8583_build_with_bitmap` accepts the same bitmap as 16/32 hex or
   64/128 binary digits and rejects count, bit and secondary-bitmap
   mismatches with `bitmap/fields mismatch`;
5. `iso8583_bitmap_parse` and `iso8583_bitmap_of` agree for both fixtures
   and both forms, accept lowercase hex, and handle the empty bitmap;
6. bitmap syntax errors: bad hex, bad binary, bad lengths, bit 1 set in
   16/64 form, secondary without bit 1, tertiary bit;
7. LLVAR field 2: 19-digit maximum, empty value (`00`), over-maximum
   prefix, non-decimal prefix, declared length beyond the buffer;
8. LLLVAR field 48: 300-character value round-trip, non-decimal prefix,
   overrun, non-printable value byte;
9. parse errors: empty/short/non-digit MTI, truncated bitmap, non-hex
   bitmap character, missing secondary bitmap, tertiary bit;
10. unknown field numbers rejected by parse, bitmap parse, build and
    `bitmap_of` (including fields 1, 5 and 129);
11. `declared field missing` for zero remaining characters versus
    `length overrun` for partial prefixes/fixed fields and declared
    lengths beyond the buffer;
12. `bad field value` for a non-digit in a numeric field and control
    bytes (0x1F, 0x7F) in alphanumeric fields;
13. trailing data after a complete message; the all-zero bitmap parses to
    an empty message that formats back exactly;
14. build validation: bad MTI, numbers/values length mismatch, out of
    order and duplicate numbers, fixed length mismatch, LLVAR over
    maximum, numeric and alphanumeric character-set failures, empty
    numbers yielding the all-zero bitmap;
15. accessors and metadata: out-of-range sentinels, `get` error,
    `is_known_field`, `is_variable_field`, `field_max_length` for every
    documented field and for unknown/out-of-range numbers;
16. lowercase bitmap parses, `format` emits the canonical uppercase form;
17. round-trips: `parse` -> `format` for both fixtures, the empty value
    message, a secondary bitmap with no set field bits, and a built
    300-character LLLVAR message;
18. `format` re-validates a hand-built message: `has_secondary` false with
    a field 70 present, a non-digit in a numeric field, a bad MTI, a wrong
    fixed length, a numbers/values length mismatch, and the positive case
    of a preserved secondary bitmap with no secondary field.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.iso8583
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- ASCII dialect only: no EBCDIC/BCD/binary field encodings and no raw-byte
  bitmap input (only hex or `0`/`1` text).
- Eleven documented fields; every other field number is an error. No
  MAC/PIN/security fields, no tertiary bitmap.
- No transport: framing, sockets, length headers and retries are out of
  scope. No semantic validation (Luhn, ISO 4217, calendar, amounts).
- Empty LLVAR/LLLVAR values are legal and indistinguishable, by value,
  from an absent field; the bit is authoritative.
- `iso8583_format` is a validating serializer, not a lenient pretty
  printer; it refuses an inconsistent hand-built `Iso8583Message`.
- `iso8583_bitmap_hex` assumes a well-formed message and has no error
  channel.
- Value accessors allocate a `Str` per call.
- Plain value types, not thread-safe.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers `_ok_msg`,
  `_err_msg`, `_ok_bitmap`, `_err_bitmap`, `_ok_str`, `_err_str`
  (constructing Results directly in other functions miscompiles in this
  compiler).
- No `==` is applied to a Str value anywhere, and no `Vec[Str]` is used:
  field values travel as `Vec[Vec[UInt8]]` (the xiom.tlv precedent), so
  the BUG-17 pointer-comparison trap cannot apply. `.len()` on `Str`
  parameters is only used on slices/parameters, never on Vec elements.
- Every byte read from a `Str` or `Vec[UInt8]` is widened once with
  `(byte_at(...) as Int) & 0xFF` (or `(v[i] as Int) & 0xFF`) before
  entering Int arithmetic.
- Bitmap bits are manipulated with arithmetic (division, modulo and a
  `_mask` helper) instead of bit operators, so no `&`/`|`/`<<` lowering
  issues can apply.
- Output bytes are collected in a `Vec[UInt8]` and materialized once with
  `xiom.string.builder.sb_to_str`, after validation guarantees only
  printable ASCII (0x20..0x7E) reaches it, so the builder can never abort
  on a 0x00 byte.
- Every `&mut Vec` call site passes `&mut` explicitly; struct fields are
  copied into typed locals before being passed by reference (the
  `&struct.field` empty-vector trap).
- The package declares no `extern "C"` blocks (no FFI).
