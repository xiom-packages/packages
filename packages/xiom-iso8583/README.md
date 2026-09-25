# xiom.iso8583

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM ISO 8583 **ASCII** message codec for a documented
> field subset: 4-digit MTI, 16/32-digit hex bitmap (bit 1 MSB-first, so the
> secondary bitmap is fields 65..128), fixed and LLVAR/LLLVAR fields.
> **Deps:** `xiom.std` only. The library module uses `xiom.string` and
> `xiom.string.builder`; the tests add `xiom.test`, `xiom.io` and
> `xiom.string.compare`. No FFI.

## What it is

`xiom.iso8583` encodes and decodes the ASCII ("hex bitmap") form of an
ISO 8583 message:

```
MTI         4 ASCII digits, e.g. 0200
bitmap      16 hex digits, plus 16 more when bit 1 is set
fields      the declared fields, in ascending field-number order
```

Bit 1 is the most significant bit of the first hex digit and marks the
presence of the secondary bitmap; bit `n` (MSB-first, 1-based) corresponds
to field `n`. A 16-digit bitmap covers fields 1..64, a 32-digit bitmap
fields 1..128. Bit 1 is a marker, never a field. Bit 65 (a tertiary bitmap)
is rejected. The bitmap may also be supplied to `iso8583_bitmap_parse` and
`iso8583_build_with_bitmap` as 64/128 characters of `'0'`/`'1'`.

`iso8583_parse` returns an `Iso8583Message` with flat parallel vectors:
`field_numbers[i]` (ascending) and `field_values[i]` (raw ASCII bytes).
Accessors read the model back; `iso8583_format` serializes it again, and
`iso8583_build` / `iso8583_build_message` construct messages from field
values with bitmap/field presence validation.

## Field subset

| Field | Meaning | Type | Length |
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

Numeric fields accept only ASCII digits; alphanumeric fields accept
printable ASCII `0x20..0x7E`. LLVAR values carry a 2-digit decimal length
prefix, LLLVAR values a 3-digit prefix. Amounts, dates and codes are kept
as digit strings: the caller interprets minor units and calendar rules.
Any other field number (or a set bit outside the table) is an error.

## API

| Function | Returns | Description |
|---|---|---|
| `iso8583_parse(text)` | `Result[Iso8583Message, Str]` | Decode one ASCII message. |
| `iso8583_format(m)` | `Result[Str, Str]` | Encode a message; re-validates it. |
| `iso8583_build_message(mti, numbers, values)` | `Result[Iso8583Message, Str]` | Build a validated message value; derives `has_secondary`. |
| `iso8583_build(mti, numbers, values)` | `Result[Str, Str]` | Build wire text, computing the bitmap from `numbers`. |
| `iso8583_build_with_bitmap(mti, bitmap, numbers, values)` | `Result[Str, Str]` | Build while checking a caller bitmap (hex or binary) against the fields. |
| `iso8583_bitmap_parse(bitmap)` | `Result[Iso8583Bitmap, Str]` | Decode standalone bitmap text (hex or binary) into field numbers. |
| `iso8583_bitmap_of(numbers)` | `Result[Str, Str]` | Canonical uppercase hex bitmap for ascending field numbers. |
| `iso8583_bitmap_hex(m)` | `Str` | Canonical bitmap hex of a well-formed message. |
| `iso8583_mti(m)` | `Str` | Message type indicator. |
| `iso8583_has_secondary(m)` | `Bool` | Bit 1 set (secondary bitmap present). |
| `iso8583_field_count(m)` | `Int` | Number of present fields. |
| `iso8583_field_number(m, i)` | `Int` | Field number at position `i`; `-1` out of range. |
| `iso8583_field_value(m, i)` | `Str` | Value at position `i`; `""` out of range. |
| `iso8583_field_index(m, number)` | `Int` | Position of a field; `-1` when absent. |
| `iso8583_has_field(m, number)` | `Bool` | Whether the field is present. |
| `iso8583_get(m, number)` | `Result[Str, Str]` | Value of a field; `Err` when absent. |
| `iso8583_is_known_field(number)` | `Bool` | Field is in the subset table. |
| `iso8583_is_variable_field(number)` | `Bool` | Field is LLVAR or LLLVAR. |
| `iso8583_field_max_length(number)` | `Int` | Fixed length or variable maximum; `-1` unknown. |

Errors: `iso8583: bad mti`, `iso8583: bad bitmap hex`,
`iso8583: bad bitmap binary`, `iso8583: bad bitmap length`,
`iso8583: unexpected secondary bitmap`,
`iso8583: tertiary bitmap not supported`,
`iso8583: unknown field number`, `iso8583: unknown field type`,
`iso8583: declared field missing`, `iso8583: length overrun`,
`iso8583: bad field length`, `iso8583: bad field value`,
`iso8583: trailing data`, `iso8583: field numbers out of order`,
`iso8583: field numbers/values length mismatch`,
`iso8583: bitmap/fields mismatch`, `iso8583: field not present`
(see SPEC.md for the exact condition and check order of every message).

## Usage

```xi
use xiom.iso8583;
use xiom.io;
use xiom.string;

// Helper: the ASCII bytes of a Str.
fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn main() -> Int {
  var numbers = Vec[Int].new();
  numbers.push(2);                                  // PAN
  numbers.push(4);                                  // amount
  var values = Vec[Vec[UInt8]].new();
  values.push(bytes_of("4111111111111111"));
  values.push(bytes_of("000000010000"));            // 100.00 in minor units

  let built = iso8583_build("0200", &numbers, &values);
  if !built.is_ok {
    io.println("build error: " + built.error);
    return 1;
  }
  let wire: Str = built.value;
  io.println(wire);                                 // 0200 + bitmap + fields

  let parsed = iso8583_parse(wire);
  if !parsed.is_ok {
    io.println("parse error: " + parsed.error);
    return 1;
  }
  let m: Iso8583Message = parsed.value;
  io.println(iso8583_field_value(&m, 0));           // 4111111111111111
  io.println(iso8583_field_value(&m, 1));           // 000000010000
  io.println(iso8583_bitmap_hex(&m));               // 5000000000000000
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.iso8583
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **ASCII only.** The wire form is MTI + hex bitmap + ASCII field text
  (the ISO 8583 "ASCII" dialect). EBCDIC, packed BCD and binary-field
  variants are not modeled, and the bitmap is text, never raw bytes.
- **A documented subset of fields only.** Only fields 2, 3, 4, 7, 11, 32,
  39, 41, 48, 49 and 70 are understood; a set bit for any other field is
  an error, never a skip. There is no full ISO 8583 field dictionary.
- **No tertiary bitmap.** Bit 65 set is an error; the bitmap chain stops
  at 128 bits.
- **No MAC/PIN fields** (64, 52, 53, ...) and no key management: the
  subset deliberately excludes security-related fields.
- **No network layer.** This is an in-memory codec; framing, sockets,
  length headers, retries and store-and-forward are out of scope.
- **Values are digit/printable strings.** Amounts (field 4), dates
  (field 7) and currency codes are validated for shape only, not for
  range, calendar validity or ISO 4217 membership.
- **LLVAR/LLLVAR values may be empty** (prefix `00`/`000`); the field
  bit, not the value length, decides presence.
- `iso8583_parse` returns the first error and no partial message;
  `iso8583_format` re-validates and is not a raw pretty-printer.
- Value accessors allocate a `Str` per call (field values are stored as
  byte vectors); hot loops should call them once per field.
- Not thread-safe; `Iso8583Message` and `Iso8583Bitmap` are plain value
  types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
