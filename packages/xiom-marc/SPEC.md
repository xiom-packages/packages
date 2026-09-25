# xiom.marc -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.marc`, version `0.1.0`).
Module: `src/marc.xi` (`module xiom.marc`).
Depends on `xiom.std` (`xiom.string`: `byte_at`, `str_compare`; `Str::from_utf8`
is a compiler builtin). Tests additionally use `xiom.test`, `xiom.io` and
`xiom.string.str_repeat`.

## 1. Scope

A pure-XIOM (no FFI) structural codec for MARC21 records in the ISO 2709
exchange format:

- `marc_parse` validates one record buffer and returns a `MarcRecord` of flat
  parallel vectors: leader scalars, one element per variable field for
  tags/field data/offsets/spans/subfield offsets/counts, and one element per
  subfield for codes/values;
- O(1) leader readers (`marc_record_length`, `marc_record_status`,
  `marc_record_type`, `marc_bib_level`, `marc_type_of_control`,
  `marc_char_coding`, `marc_indicator_count`, `marc_subfield_code_count`,
  `marc_base_address`, `marc_encoding_level`, `marc_cataloging_form`,
  `marc_multipart_level`, `marc_entry_map`);
- O(1) field readers (`marc_field_count`, `marc_tag`, `marc_field_data`,
  `marc_field_offset`, `marc_field_span`) and subfield readers
  (`marc_subfield_count`, `marc_subfield_code`, `marc_subfield_value`,
  `marc_subfield_value_by_code`);
- `marc_build` writes a canonical record from a leader template plus flat
  field and subfield columns, recomputing every length and position.

The bytes after the first 0x1F of a field are the field data (for a MARC data
field the first two of them are the indicator positions); each 0x1F starts a
one-byte subfield code followed by the value bytes up to the next 0x1F or the
field terminator. No tag-specific meaning is attached to any of it.

## 2. Non-goals

- **No MARCXML conversion** in either direction.
- **No authority or tag semantics**: tags, indicators, leader codes and
  subfield codes are stored and returned verbatim; nothing is validated
  against tag lists (no 001-009 control-field rules, no 245 indicator rules,
  no field ordering rules).
- **No character-set conversion**: bytes are never recoded. Non-ASCII bytes
  (MARC-8, UTF-8 or anything else) pass through unchanged; the codec does not
  validate that a field is well-formed UTF-8.
- **No holdings-specific rules** (852/856), no linked-record 880 handling, no
  deduplication, no record merging.
- **No multi-record files / streaming**: the API is one buffer in, values
  out. A caller reading an `.mrc` file splits it by record length itself; a
  buffer longer than `record_length` is accepted and the trailing bytes are
  ignored.
- **No file I/O, no FFI, no registry integration, no thread safety.**

## 3. Byte layout

All numeric fields are right-aligned zero-padded ASCII decimal digits, one
digit per byte, as required by ISO 2709.

### 3.1 Leader (24 bytes)

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 5 | record length | ASCII digits; `>= 26`; `<= data.len()`; recomputed by `marc_build`. |
| 5 | 1 | record status | Stored verbatim (0..255). |
| 6 | 1 | type of record | Stored verbatim. |
| 7 | 1 | bibliographic level | Stored verbatim. |
| 8 | 1 | type of control | Stored verbatim. |
| 9 | 1 | character coding scheme | Stored verbatim; never used to recode bytes. |
| 10 | 1 | indicator count | Must be `'2'` (50). |
| 11 | 1 | subfield code count | Must be `'2'` (50). |
| 12 | 5 | base address of data | ASCII digits; `25 <= b <= record_length - 1`; `(b - 25) % 12 == 0`; recomputed by `marc_build`. |
| 17 | 1 | encoding level | Stored verbatim. |
| 18 | 1 | descriptive cataloging form | Stored verbatim. |
| 19 | 1 | multipart resource record level | Stored verbatim. |
| 20 | 4 | entry map | Must be `"4500"` (field length part 4, starting-position part 5, no implementation-defined or undefined parts); `marc_build` always writes `"4500"`. |

### 3.2 Directory (12 bytes per field, terminated by 0x1E)

Entry `i` (`0 <= i < N`) starts at `24 + i * 12`; the directory terminator
`0x1E` is at `base_address - 1`, so `N = (base_address - 25) / 12`.

| Entry offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 3 | tag | ASCII digits (000-999). |
| 3 | 4 | field length | ASCII digits; `>= 1`; includes the trailing `0x1E`. |
| 7 | 5 | starting position | ASCII digits; relative to `base_address`; `start + length <= record_length - 1 - base_address`. |

### 3.3 Variable fields and subfields

- The data area runs from `base_address` to `record_length - 2`; the record
  terminator `0x1D` is the byte at `record_length - 1`.
- Field `i` occupies `[base_address + start, base_address + start + length)`
  and its last byte must be `0x1E`.
- Field payload (length minus the terminator) is split at `0x1F`:
  - the bytes before the first `0x1F` are the **field data** (for a data field
    the first two bytes are the indicator positions; for a control field the
    whole payload is field data);
  - each `0x1F` is followed by exactly one **code** byte and then the **value**
    bytes up to the next `0x1F` or the field terminator. A value may be empty
    (0 bytes); a `0x1F` with no following code byte is an error.
- Directory positions are authoritative: fields may appear in any order and
  need not tile the data area. `marc_build` always writes them contiguously
  in directory order.

### 3.4 Worked example (the test fixture)

```
leader      "00098nam  2200061   4500"      (24 bytes)
directory   "001001100000"                  tag 001, length 11, start 0
            "245001500011"                  tag 245, length 15, start 11
            "650001000026"                  tag 650, length 10, start 26
            0x1E                            directory terminator at byte 60
data        "FIXTURE001" 0x1E               field 001, bytes 61..71
            "10" 0x1F "aTitle" 0x1F "bSub" 0x1E   field 245, bytes 72..86
            " 0" 0x1F "aTopic" 0x1E         field 650, bytes 87..96
            0x1D                            record terminator at byte 97
```

`record_length = 98`, `base_address = 61`, `N = 3`. Field accessors report
offsets 61/72/87 and spans 11/15/10; field 245 has field data `"10"` and
subfields (`a`, `"Title"`) and (`b`, `"Sub"`).

## 4. Validation order

`marc_parse` (first failure wins):

1. `data.len() < 24` -> `marc: truncated leader`.
2. leader 0..4 not five ASCII digits, or the value `< 26` ->
   `marc: bad record length`.
3. value `> data.len()` -> `marc: truncated record` (trailing bytes beyond
   `record_length` are ignored).
4. leader 10 != `'2'` -> `marc: unsupported indicator count`.
5. leader 11 != `'2'` -> `marc: unsupported subfield code count`.
6. leader 12..16 not five ASCII digits, value `< 25`, or value
   `> record_length - 1` -> `marc: bad base address`.
7. `(base_address - 25) % 12 != 0` -> `marc: bad directory size`.
8. leader 20..23 != `"4500"` -> `marc: unsupported entry map`.
9. byte at `base_address - 1` != `0x1E` ->
   `marc: missing directory terminator`.
10. byte at `record_length - 1` != `0x1D` ->
    `marc: missing record terminator`.
11. per directory entry, in order:
    - tag/length/start not ASCII digits -> `marc: bad directory entry`;
    - field length `< 1` -> `marc: bad field length`;
    - `start + length > record_length - 1 - base_address` ->
      `marc: field out of range`;
    - last field byte != `0x1E` -> `marc: missing field terminator`;
    - while splitting subfields: `0x1F` as the last payload byte ->
      `marc: missing subfield code`.

`marc_build` (first failure wins):

1. any pass-through leader byte (5..9, 17..19) outside `0..255` ->
   `marc: bad leader byte`.
2. `tags.len() != field_data.len() != sub_counts.len()`, or a negative
   count -> `marc: field count mismatch`.
3. `sum(sub_counts) != sub_codes.len()` or `!= sub_values.len()` ->
   `marc: subfield count mismatch`.
4. `25 + 12 * tags.len() > 99999` -> `marc: too many fields`.
5. per field, in order: tag not exactly three ASCII digits ->
   `marc: bad tag`; field data containing `0x1D`/`0x1E`/`0x1F` ->
   `marc: bad field data`; per subfield: code outside `1..255` or equal to
   `0x1D`/`0x1E`/`0x1F` -> `marc: bad subfield code`; value containing
   `0x1D`/`0x1E`/`0x1F` -> `marc: bad subfield value`; computed field length
   `> 9999` -> `marc: field too long`.
6. `base_address + sum(field lengths) + 1 > 99999` ->
   `marc: record too long`.

## 5. API signatures

```xi
pub type MarcRecord = {
  record_length: Int; record_status: Int; record_type: Int; bib_level: Int;
  type_of_control: Int; char_coding: Int; indicator_count: Int;
  subfield_code_count: Int; base_address: Int; encoding_level: Int;
  cataloging_form: Int; multipart_level: Int; entry_map: Str;
  tags: Vec[Str]; field_data: Vec[Str]; field_offsets: Vec[Int];
  field_spans: Vec[Int]; sub_offsets: Vec[Int]; sub_counts: Vec[Int];
  sub_codes: Vec[Int]; sub_values: Vec[Str];
}

pub fn marc_parse(data: &Vec[UInt8]) -> Result[MarcRecord, Str]
pub fn marc_record_length(t: &MarcRecord) -> Int
pub fn marc_record_status(t: &MarcRecord) -> Int
pub fn marc_record_type(t: &MarcRecord) -> Int
pub fn marc_bib_level(t: &MarcRecord) -> Int
pub fn marc_type_of_control(t: &MarcRecord) -> Int
pub fn marc_char_coding(t: &MarcRecord) -> Int
pub fn marc_indicator_count(t: &MarcRecord) -> Int
pub fn marc_subfield_code_count(t: &MarcRecord) -> Int
pub fn marc_base_address(t: &MarcRecord) -> Int
pub fn marc_encoding_level(t: &MarcRecord) -> Int
pub fn marc_cataloging_form(t: &MarcRecord) -> Int
pub fn marc_multipart_level(t: &MarcRecord) -> Int
pub fn marc_entry_map(t: &MarcRecord) -> Str
pub fn marc_field_count(t: &MarcRecord) -> Int
pub fn marc_tag(t: &MarcRecord, i: Int) -> Str
pub fn marc_field_data(t: &MarcRecord, i: Int) -> Str
pub fn marc_field_offset(t: &MarcRecord, i: Int) -> Int
pub fn marc_field_span(t: &MarcRecord, i: Int) -> Int
pub fn marc_subfield_count(t: &MarcRecord, i: Int) -> Int
pub fn marc_subfield_code(t: &MarcRecord, i: Int, j: Int) -> Int
pub fn marc_subfield_value(t: &MarcRecord, i: Int, j: Int) -> Str
pub fn marc_subfield_value_by_code(t: &MarcRecord, i: Int, code: Int) -> Str
pub fn marc_build(template: &MarcRecord, tags: &Vec[Str], field_data: &Vec[Str], sub_counts: &Vec[Int], sub_codes: &Vec[Int], sub_values: &Vec[Str]) -> Result[Vec[UInt8], Str]
```

## 6. Semantics

- **Leader readers** are O(1) and infallible: byte values 0..255, except
  `marc_entry_map`, which returns the 4-byte text (`"4500"` for every parsed
  record).
- **`marc_field_count`** is the minimum length of the six parallel field
  vectors, so index-based field access is safe even for a hand-built record
  whose parallel vectors drifted.
- **Field readers** guard their own index: `marc_tag` and `marc_field_data`
  return `""`, `marc_field_offset` returns `-1`, and `marc_field_span`
  returns `0` for `i < 0` or `i >= marc_field_count(t)`.
  `marc_field_offset` is an absolute index into the buffer passed to
  `marc_parse`; `marc_field_span` includes the trailing `0x1E`.
- **`marc_subfield_count(t, i)`** returns 0 out of range and otherwise clamps
  `sub_counts[i]` to what `sub_codes`/`sub_values` actually hold starting at
  `sub_offsets[i]`, so a drifted hand-built record stays in bounds.
- **`marc_subfield_code(t, i, j)`** returns the code as a byte value 0..255,
  and `marc_subfield_value(t, i, j)` returns the value text; both return `0`
  and `""` respectively when `i` or `j` is out of range.
- **`marc_subfield_value_by_code(t, i, code)`** returns the value of the
  **first** subfield of field `i` whose code byte equals `code` (a repeated
  code therefore yields its first occurrence, including an empty value), or
  `""` when the field has no such subfield or `i` is out of range. Code
  comparison is on the byte value, case-sensitive.
- **`marc_build`** derives the record length, base address, directory field
  lengths and starting positions, and the field count from its arguments; the
  matching `template` fields are ignored. It always writes `'2'` at leader
  10/11 and `"4500"` at 20..23, and passes leader 5..9 and 17..19 through from
  the template. Fields are written contiguously in directory order, each
  closed by `0x1E`, and the record is closed by `0x1D`. An empty field set
  produces the 26-byte record `leader("00026...00025...4500") 0x1E 0x1D`.
- **Round trip**: `marc_parse` followed by `marc_build` reproduces the input
  byte-for-byte for any record the parser accepts whose field layout is
  canonical (contiguous in directory order), because the builder emits exactly
  that layout; a record with gaps, overlaps or trailing bytes rebuilds into
  the equivalent canonical record. `marc_build` followed by `marc_parse`
  always reproduces the built leader values, field data and subfield pairs.

## 7. Error string catalog

| Condition | Error text |
|---|---|
| Buffer < 24 bytes | `marc: truncated leader` |
| Leader 0..4 not five digits, or value < 26 | `marc: bad record length` |
| Record length value > buffer length | `marc: truncated record` |
| Leader 10 not `'2'` | `marc: unsupported indicator count` |
| Leader 11 not `'2'` | `marc: unsupported subfield code count` |
| Leader 12..16 not five digits, value < 25, or value > `record_length - 1` | `marc: bad base address` |
| `(base_address - 25) % 12 != 0` | `marc: bad directory size` |
| Leader 20..23 not `"4500"` | `marc: unsupported entry map` |
| Byte `base_address - 1` not `0x1E` | `marc: missing directory terminator` |
| Byte `record_length - 1` not `0x1D` | `marc: missing record terminator` |
| Directory tag/length/start not digits | `marc: bad directory entry` |
| Directory field length < 1 | `marc: bad field length` |
| `start + length` past the data area | `marc: field out of range` |
| Last field byte not `0x1E` | `marc: missing field terminator` |
| `0x1F` as the last field-payload byte | `marc: missing subfield code` |
| Build: pass-through leader byte outside `0..255` | `marc: bad leader byte` |
| Build: field vectors differ in length, or negative count | `marc: field count mismatch` |
| Build: counts do not sum to the flat subfield columns | `marc: subfield count mismatch` |
| Build: `25 + 12 * fields > 99999` | `marc: too many fields` |
| Build: tag not exactly three digits | `marc: bad tag` |
| Build: field data contains `0x1D`/`0x1E`/`0x1F` | `marc: bad field data` |
| Build: subfield code outside `1..255` or a delimiter | `marc: bad subfield code` |
| Build: subfield value contains `0x1D`/`0x1E`/`0x1F` | `marc: bad subfield value` |
| Build: computed field length > 9999 | `marc: field too long` |
| Build: computed record length > 99999 | `marc: record too long` |

## 8. Complexity

| Operation | Complexity |
|---|---|
| `marc_parse` | O(data bytes) |
| Leader readers, `marc_field_count` | O(1) |
| `marc_tag` / `marc_field_data` / `marc_field_offset` / `marc_field_span` | O(1) |
| `marc_subfield_count` / `marc_subfield_code` / `marc_subfield_value` | O(1) |
| `marc_subfield_value_by_code` | O(subfields of that field) |
| `marc_build` | O(fields + subfields + output bytes) |

## 9. Test plan

`tests/test_conformance.xi` (`module marc_tests`, 22 named checks; the
hello-style `main` prints `[PASS]`/`[FAIL]` per check and returns the failure
count). The 98-byte fixture is assembled byte by byte so `marc_parse` is
exercised against bytes the test controls, not only against `marc_build`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | leader accessors | all 13 leader values of the fixture |
| t2 | directory accessors | 3 tags, offsets 61/72/87, spans 11/15/10 |
| t3 | field data | `"FIXTURE001"`, `"10"`, `" 0"` prefixes |
| t4 | subfield pairs | counts 0/2/1, codes 97/98, values `Title`/`Sub`/`Topic` |
| t5 | `value_by_code` | hit per code and empty on a missing code/field |
| t6 | out-of-range accessors | `""`/`-1`/`0` guards on every reader |
| t7 | parse -> build | byte-identical round trip of the fixture |
| t8 | build from scratch | the builder reproduces the exact fixture bytes |
| t9 | zero-field build | exact 26-byte record `leader 0x1E 0x1D`, re-parses |
| t10 | record length | digit check, 26-byte floor, truncation, huge value |
| t11 | leader pins | entry map `"4501"`, indicator count `'1'`, subfield count `'3'` |
| t12 | base address | non-digit, `< 25`, `> record_length - 1`, misaligned 62 |
| t13 | terminators | directory byte 60 and record byte 97 must be `0x1E`/`0x1D` |
| t14 | directory digits | tag/length/start non-digit, field length 0 |
| t15 | field spans | start past the data area, missing field terminator |
| t16 | subfield code | trailing `0x1F` without a code byte |
| t17 | builder shape | bad leader byte, field/subfield count mismatches |
| t18 | builder values | bad tag, field data, code 31/0/256, value with `0x1F`/`0x1E` |
| t19 | builder limits | field 10001 bytes, record 100056 bytes, 8332 fields |
| t20 | repeated codes | first match wins; empty subfield values survive |
| t21 | trailing bytes | bytes after `record_length` are ignored |
| t22 | drifted vectors | `field_count` min, clamps, safe out-of-range reads |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.marc
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## 10. Known limitations

- Leader 10/11 are pinned to `'2'`/`'2'` and the entry map to `"4500"`:
  records using other ISO 2709 directory shapes are rejected rather than
  parsed. This is the MARC21 canonical shape.
- Directory positions are trusted once bounds-checked: overlapping fields or
  gaps in the data area are accepted as long as every span is in range and
  terminated by `0x1E`. The builder always writes canonical contiguous
  fields, so parse -> build is byte-identical only for canonical layouts.
- 16-bit-style directory limits apply: field length `<= 9999`, starting
  position and record length `<= 99999`, therefore at most 8331 fields.
- Field and subfield texts are bytes, not characters: no encoding
  conversion and no UTF-8 validation; values with an empty byte sequence are
  preserved as empty strings.
- A NUL byte (`0x00`) inside field data or a value is stored like any other
  byte; the codec neither rejects nor trims it.
- Tags and codes are not interpreted: no control-field rules, no indicator
  rules, no 880 linkage, no holdings rules, no MARCXML.
- Whole-buffer API: the record and every copied text live in memory. Plain
  value types only; not thread-safe.

## 11. Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_record`,
  `_err_record`, `_ok_bytes`, `_err_bytes`; every other function returns
  through one of them.
- Every byte read is widened with `(data[pos] as Int) & 0xFF`; no `UInt8`
  is compared against an `Int` constant without widening.
- Str values read from `Vec[Str]` fields are bound to typed locals and
  compared with `string.str_compare`, never `==` (BUG 17).
- All `&mut Vec[UInt8]` calls pass `&mut` at the call site.
- Accessors and the builder verify parallel-vector lengths before indexing,
  so a hand-built `MarcRecord` with drifted vectors cannot read out of
  bounds; `marc_field_count` is the safe maximum and
  `marc_subfield_count` clamps to the flat columns.
- The test suite binds every `&` argument to a local (never a struct field
  or a call result), following the `docs/repro/struct-field-vec` findings.
- Tag equality is `string.str_compare`, and fixture bytes are written
  through `string.byte_at`, so no comparison depends on implicit lowering.
