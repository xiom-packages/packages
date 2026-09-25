# xiom.marc

> **Status:** IMPLEMENTED -- harness-green with compiler v0.61.3 (22/22 checks).
> **Scope:** a pure-XIOM MARC21 ISO 2709 record codec: parse a record buffer
> into flat field/subfield storage, and build a canonical record back.
> **Deps:** `xiom.std` (uses `xiom.string`; tests also use `xiom.test`,
> `xiom.io`).

## What it is

`xiom.marc` reads and writes MARC21 bibliographic records in the ISO 2709
exchange format (`.mrc` records): the 24-byte leader, the 12-byte directory
entries, the `0x1E`-terminated variable fields, the `0x1D` record terminator
and the `0x1F` subfield markers.

- `marc_parse` validates a record -- leader numerics, entry map, base address
  vs directory size, every terminator byte, directory digit fields, field
  spans and subfield markers -- and returns a `MarcRecord` of flat parallel
  vectors. There is no `Vec` of structs and no hidden state: field data and
  subfield values are copied to strings at parse time, and field offsets point
  into the caller's buffer.
- `marc_build` writes a record from a leader template plus flat field and
  subfield columns, recomputing the record length, base address and every
  directory entry, so lengths can never drift from the payload.

The codec is structural only: tags, leader codes, indicators and subfield
codes are stored and returned verbatim. There is no MARCXML conversion, no
tag semantics, no authority validation, no character-set conversion (bytes
pass through untouched) and no holdings rules.

## Install

```
xiom pkg install xiom.marc@0.1.0
```

In a manifest:

```xi
deps: { "xiom.marc": "^0.1.0", "xiom.std": ">=0.60.0 <1.0.0" };
```

## Quick start

Parsing one record (the buffer may hold more bytes than `record_length`;
trailing bytes are ignored):

```xi
use xiom.io;
use xiom.marc;
use xiom.string;

// bytes: Vec[UInt8] holding one ISO 2709 record
let parsed = marc_parse(&bytes);
if parsed.is_ok {
  let rec: MarcRecord = parsed.value;
  io.println(int_to_string(marc_field_count(&rec)) + " fields");
  io.println(marc_tag(&rec, 0));                          // e.g. "001"
  io.println(marc_field_data(&rec, 1));                   // e.g. "10"
  io.println(marc_subfield_value_by_code(&rec, 1, 97));   // e.g. the 245 $a text
}
```

Building a canonical record (leader status 'n', type 'a', bib level 'm'):

```xi
use xiom.marc;

let template = ...;              // any parsed MarcRecord; pass-through leader
                                 // bytes 5..9 and 17..19 are reused
// tags, field_data, sub_counts, sub_codes, sub_values are flat parallel
// columns: field i has sub_counts[i] subfields taken in order.
let built = marc_build(&template, &tags, &field_data, &sub_counts, &sub_codes, &sub_values);
if built.is_ok {
  let bytes: Vec[UInt8] = built.value;
  // bytes is one complete record ending in 0x1D
}
```

## API summary

| Function | Returns | Description |
|---|---|---|
| `marc_parse(data)` | `Result[MarcRecord, Str]` | Validate and parse one record. |
| `marc_record_length(t)` | `Int` | Leader 0..4. |
| `marc_record_status(t)` | `Int` | Leader 5, verbatim. |
| `marc_record_type(t)` | `Int` | Leader 6, verbatim. |
| `marc_bib_level(t)` | `Int` | Leader 7, verbatim. |
| `marc_type_of_control(t)` | `Int` | Leader 8, verbatim. |
| `marc_char_coding(t)` | `Int` | Leader 9, verbatim. |
| `marc_indicator_count(t)` | `Int` | Leader 10 (`'2'` = 50 for parsed records). |
| `marc_subfield_code_count(t)` | `Int` | Leader 11 (`'2'` = 50 for parsed records). |
| `marc_base_address(t)` | `Int` | Leader 12..16. |
| `marc_encoding_level(t)` | `Int` | Leader 17, verbatim. |
| `marc_cataloging_form(t)` | `Int` | Leader 18, verbatim. |
| `marc_multipart_level(t)` | `Int` | Leader 19, verbatim. |
| `marc_entry_map(t)` | `Str` | Leader 20..23 (`"4500"`). |
| `marc_field_count(t)` | `Int` | Number of variable fields. |
| `marc_tag(t, i)` | `Str` | Three-digit tag of field `i`. |
| `marc_field_data(t, i)` | `Str` | Bytes before the first `0x1F` (indicators first). |
| `marc_field_offset(t, i)` | `Int` | Absolute buffer offset of field `i`, or `-1`. |
| `marc_field_span(t, i)` | `Int` | Field length including the `0x1E`, or `0`. |
| `marc_subfield_count(t, i)` | `Int` | Number of subfields of field `i`. |
| `marc_subfield_code(t, i, j)` | `Int` | Code byte of subfield `j` (0..255). |
| `marc_subfield_value(t, i, j)` | `Str` | Value text of subfield `j` (may be empty). |
| `marc_subfield_value_by_code(t, i, code)` | `Str` | First value whose code matches, else `""`. |
| `marc_build(template, tags, field_data, sub_counts, sub_codes, sub_values)` | `Result[Vec[UInt8], Str]` | Build a canonical record. |

Guards: out-of-range field readers return `""`/`-1`/`0`; out-of-range
subfield readers return `""`/`0`; `marc_subfield_count` clamps to the flat
columns, so hand-built records with drifted vectors stay in bounds.

## Error model

Every fallible call returns `Result[_, Str]` with deterministic
`"marc: ..."` messages. Parse errors (first failure wins):

| Error | Meaning |
|---|---|
| `marc: truncated leader` | Buffer shorter than 24 bytes. |
| `marc: bad record length` | Leader 0..4 not five digits, or length < 26. |
| `marc: truncated record` | Record length exceeds the buffer. |
| `marc: unsupported indicator count` | Leader 10 is not `'2'`. |
| `marc: unsupported subfield code count` | Leader 11 is not `'2'`. |
| `marc: bad base address` | Leader 12..16 not five digits, < 25, or past the record. |
| `marc: bad directory size` | `(base_address - 25) % 12 != 0`. |
| `marc: unsupported entry map` | Leader 20..23 is not `"4500"`. |
| `marc: missing directory terminator` | Byte `base_address - 1` is not `0x1E`. |
| `marc: missing record terminator` | Byte `record_length - 1` is not `0x1D`. |
| `marc: bad directory entry` | Directory tag/length/start not ASCII digits. |
| `marc: bad field length` | Directory field length is 0. |
| `marc: field out of range` | `start + length` leaves the data area. |
| `marc: missing field terminator` | A field does not end in `0x1E`. |
| `marc: missing subfield code` | A `0x1F` is the last payload byte. |

Build errors: `marc: bad leader byte`, `marc: field count mismatch`,
`marc: subfield count mismatch`, `marc: too many fields`, `marc: bad tag`,
`marc: bad field data`, `marc: bad subfield code`, `marc: bad subfield value`,
`marc: field too long`, `marc: record too long`. See `SPEC.md` section 7 for
the exact condition behind each message.

## Round trips

- `parse -> build` is byte-identical for any accepted record whose fields are
  stored contiguously in directory order (the MARC21 canonical layout).
- For a record with gaps, overlaps or trailing bytes, `build` writes the
  equivalent canonical record.
- `build -> parse` always reproduces the leader pass-through bytes, field
  data and every subfield code/value pair.

## Limitations

- MARC21/ISO 2709 only (leader 10/11 = `'2'`, entry map `"4500"`); no
  MARCXML, no authority files, no tag/indicator semantics, no holdings rules.
- No character-set conversion or UTF-8 validation: bytes pass through
  unchanged.
- Directory limits: field length `<= 9999`, record length `<= 99999`, at most
  8331 fields.
- One record per buffer; the caller splits multi-record files.
- Owned strings are copied at parse time; whole-buffer API, not thread-safe.

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 22 `[PASS]` lines, then `xiom.marc: all tests passed`, exit 0.
From the repository root the same run is wrapped by
`& .\scripts\port.ps1 -Package xiom.marc`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
