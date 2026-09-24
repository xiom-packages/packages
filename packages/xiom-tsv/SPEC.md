# xiom.tsv -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.tsv` (`src/tsv.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free TSV reader/writer for in-memory `Str` documents:

- escape or unescape one field (`tsv_escape_field`, `tsv_unescape_field`),
- parse one line (`tsv_parse_line`) or a whole document (`tsv_parse`) into
  `Vec[Str]` / `Vec[Vec[Str]]`,
- serialize one record (`tsv_write_row`) or a document (`tsv_write`),
- inspect parsed tables (`tsv_is_rectangular`, `tsv_field_count`).

The tab/record layout follows the IANA `text/tab-separated-values` conventions:
raw TAB bytes separate fields, LF terminates records, CRLF is accepted with the
CR stripped, and the backslash is the field-escape introducer. The escape
subset implemented here is `\\`, `\t`, `\n`, `\r` only (see section 3).

## 2. Non-goals

- Streaming / incremental parsing (whole `Str` in memory only).
- Configurable dialects (delimiter, escape char are fixed).
- `\uXXXX` or any escape beyond `\\ \t \n \r`.
- Typed decoding of numbers, dates, booleans.
- Header rows, comment lines, BOM handling, trailing-space policies.
- Any FFI, file I/O, or registry integration.

## 3. Escape table

`tsv_escape_field` maps exactly these bytes to two-byte sequences and passes
everything else (including all UTF-8 continuation bytes) through unchanged:

| Input byte | Octal | Output (2 bytes) | Meaning |
|---|---|---|---|
| `\` | 134 | `\\` | backslash |
| TAB | 011 | `\t` | tab |
| LF | 012 | `\n` | line feed |
| CR | 015 | `\r` | carriage return |

`tsv_unescape_field` is the inverse: `\\` -> `\`, `\t` -> TAB, `\n` -> LF,
`\r` -> CR. Any other sequence is an error (section 5).

Round-trip law: for every field `f`, `tsv_unescape_field(tsv_escape_field(f))`
is `Ok(f)`.

## 4. Grammar and semantics

Informal grammar:

```
document = line *( LF line ) [ LF ]
line     = field *( TAB field ) [ CR ]
field    = *( byte | ESC )
ESC      = '\\' | '\t' | '\n' | '\r'
byte     = any byte except the raw delimiters and the backslash that ESC uses
```

Decisions (each one is covered by the conformance suite):

1. **Field delimiter.** A raw TAB byte (0x09) separates fields. Field values
   that must contain a tab use the `\t` escape; the escaped form never
   contains a raw tab, so splitting on raw tabs is unambiguous.
2. **Record terminator.** LF (0x0A) terminates a record. A single trailing CR
   before the LF (CRLF input) is stripped from the line; a CR that is not the
   last byte of a line is data.
3. **Trailing newline.** A single terminator at end of input ends the last
   record and does **not** produce an extra empty record: `"a\tb\n"` =>
   `[[a,b]]`. Two newlines do produce a blank record: `"a\n\n"` =>
   `[[a],[""]]`.
4. **Empty input.** `tsv_parse("")` => `[]` (zero records). But an empty
   *line* is a record: `"\n"` => `[[""]]`, `"\r\n"` => `[[""]]`, and
   `"a\n\nb"` => `[[a],[""],[b]]`.
5. **Empty fields.** Empty fields are preserved: `"a\t\tc"` => `[[a,"",c]]`;
   `"\t"` => `[["",""]]`; `""` (one empty line) => `[[""]]`.
6. **`tsv_parse_line`.** Parses exactly one line: splits on raw tabs, strips
   one trailing CR, unescapes each field. `tsv_parse_line("")` => `Ok([""])`.
   LF bytes are data for this entry point (no record splitting).
7. **Strict decoding.** `tsv_unescape_field` and `tsv_parse_line` reject a
   malformed backslash sequence with `Err("tsv: invalid escape")` (section 5).
8. **Lenient decoding in `tsv_parse`.** `tsv_parse` returns a `Vec`, so it has
   no error channel: a malformed backslash sequence is kept verbatim (the
   backslash and the byte after it are copied unchanged), matching the
   stdlib's `xiom.string.str_unescape` policy. Use `tsv_parse_line` to detect
   malformed input.
9. **Writing.** `tsv_write_row` escapes every field and joins them with a raw
   TAB; zero fields yield the empty string. `tsv_write` joins encoded rows
   with LF and emits **no** trailing newline; zero rows yield the empty
   string.
10. **Round trip.** For any `rows`, `tsv_parse(tsv_write(rows))` returns the
    same records and field values (checked element-wise with `str_compare`).
11. **Rectangularity.** True when all records have equal field count; true
    for 0 or 1 records, and for several zero-width records. `tsv_field_count`
    is the width of the first record, `0` when there are no records.
12. **Encoding.** `Str` is treated as a UTF-8 byte buffer; all scanning is
    byte-wise but never splits or rewrites multi-byte sequences, so non-ASCII
    text round-trips byte-exact.

## 5. Error catalog

| Function | Condition | Result |
|---|---|---|
| `tsv_unescape_field` | backslash followed by a byte other than `\`, `t`, `n`, `r` | `Err("tsv: invalid escape")` |
| `tsv_unescape_field` | trailing backslash at end of input | `Err("tsv: invalid escape")` |
| `tsv_parse_line` | any field with one of the two conditions above | `Err("tsv: invalid escape")` |
| `tsv_parse` | malformed escape | never fails; sequence kept verbatim (rule 8) |

There is exactly one error message in this version. `tsv_escape_field`,
`tsv_write_row`, `tsv_write`, `tsv_is_rectangular` and `tsv_field_count` are
infallible.

## 6. API signatures

```xi
pub fn tsv_escape_field(f: Str) -> Str
pub fn tsv_unescape_field(f: Str) -> Result[Str, Str]
pub fn tsv_parse_line(line: Str) -> Result[Vec[Str], Str]
pub fn tsv_parse(text: Str) -> Vec[Vec[Str]]
pub fn tsv_write_row(fields: &Vec[Str]) -> Str
pub fn tsv_write(rows: &Vec[Vec[Str]]) -> Str
pub fn tsv_is_rectangular(rows: &Vec[Vec[Str]]) -> Bool
pub fn tsv_field_count(rows: &Vec[Vec[Str]]) -> Int
```

Complexity: parsing, escaping and writing are O(n) over the input bytes; the
inspection helpers are O(1) or O(rows).

## 7. Test plan

`tests/test_conformance.xi` (module `tsv_tests`) runs 22 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | simple fields | basic split on raw tabs (rule 1) |
| t2 | empty fields | empty line, bare tab, interior empty (rule 5) |
| t3 | escaped tab | `\t` encode/decode |
| t4 | escaped LF | `\n` encode/decode |
| t5 | escaped CR | `\r` encode/decode |
| t6 | escaped backslash | `\\` encode/decode |
| t7 | unescape round-trip | all escapes + UTF-8 samples (section 3 law) |
| t8 | invalid escapes | error catalog (section 5) |
| t9 | raw tabs delimit | 1/2/4 field lines (rule 1) |
| t10 | escaped tab is data | `a\tb` is one field containing a real tab |
| t11 | CRLF | rows split, trailing CR stripped (rule 2) |
| t12 | trailing newline | one adds no row, two do (rule 3) |
| t13 | empty text | zero rows, writes back empty (rule 4) |
| t14 | single empty line | one row, one empty field (rule 4) |
| t15 | empty field between tabs | interior empties survive (rule 5) |
| t16 | write_row | escaping and raw-tab join (rule 9) |
| t17 | write | LF join, no trailing newline (rule 9) |
| t18 | round trip, single row | element-wise with `str_compare` (rule 10) |
| t19 | round trip, document | multi-row, specials, rectangularity (rule 10) |
| t20 | rectangular true | 0, 1, square, zero-width rows (rule 11) |
| t21 | rectangular false | ragged rows (rule 11) |
| t22 | field_count | first row width, 0 on empty (rule 11) |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 8. Known limitations

- Escape subset only (`\\ \t \n \r`); no `\uXXXX`, no quote doubling.
- No streaming API; everything is in memory.
- `tsv_parse` cannot report malformed escapes (lenient, rule 8).
- Fixed dialect: raw TAB delimiter, LF output.
- No header handling, type conversion, BOM stripping or comment lines.
- A trailing backslash at end of input is an invalid escape for the strict
  entry points, even though some TSV dialects treat it as data.

## 9. Compiler / stdlib notes

No compiler workarounds were required beyond the documented v0.61.3
constraints: free functions only, no methods or lambdas, no `Vec[StructType]`,
byte-wise scanning via `xiom.string.byte_at`, output through
`xiom.string.builder`, and `Ok`/`Err` construction confined to the leaf
helpers `_ok_str`, `_err_str`, `_ok_fields` and `_err_fields`. The test suite
routes every string comparison through `str_compare` to avoid BUG 17 and only
takes `&` (never `&mut`) of locals at call sites.
