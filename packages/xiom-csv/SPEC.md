# xiom.csv -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.csv` (`src/csv.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free CSV reader/writer for in-memory `Str` documents:

- parse one record (`csv_parse_line`) or a whole document (`csv_parse`) into
  `Vec[Str]` / `Vec[Vec[Str]]`,
- decide whether a field needs quoting (`csv_needs_quoting`),
- serialize one record (`csv_write_row`) or a document (`csv_write`),
- inspect parsed tables (`csv_is_rectangular`, `csv_get`, `csv_field_count`).

The reader/writer model intentionally matches the standard library's
`xiom.serialize.csv` (RFC 4180-style quoting, LF/CR/CRLF boundaries, doubled
quotes) with two deliberate differences: the entry points are infallible
(no `Result` error channel) and the writer uses LF + no trailing terminator.

## 2. Non-goals

- Streaming / incremental parsing (whole `Str` in memory only).
- Configurable dialects (delimiter, quote char, escape char are fixed).
- Typed decoding of numbers, dates, booleans.
- Header rows, comment lines, BOM handling, trailing-space policies.
- RFC 4180 strict-mode validation (no error on malformed quoting).
- Any FFI, file I/O, or registry integration.

## 3. Grammar and semantics

Informal grammar (RFC 4180 subset):

```
document = record *( TERM record ) [ TERM ]
record   = field *( "," field )
field    = unquoted | quoted
quoted   = '"' *( UTF8 | ',' | CR | LF | '""' ) '"'
unquoted = *( UTF8 except ',' CR LF '"' )
TERM     = LF | CR | CRLF
```

Decisions (each one is covered by the conformance suite):

1. **Terminators.** LF, CR and CRLF all end a record. A CR immediately
   followed by LF consumes both bytes as one boundary.
2. **Trailing newline.** A single terminator at end of input ends the last
   record and does **not** produce an extra empty record. Example:
   `"a,b\n"` => `[[a,b]]`.
3. **Empty input.** `csv_parse("")` => `[]` (zero records). But an empty
   *line* is a record: `"a\n\nb"` => `[[a],[""],[b]]`, and `csv_parse("\n")`
   => `[[""]]`. This matches the RFC grammar where a record has at least one
   field.
4. **Empty fields.** Empty fields are preserved: `"a,,c"` => `[[a,"",c]]`;
   `","` => `[["",""]]`; `"\"\""` => `[[""]]` (a quoted empty field is still
   one empty field).
5. **Quoted fields.** A field may be wrapped in double quotes; inside, commas
   and CR/LF are literal and `""` decodes to one `"`. UTF-8 passes through
   byte-exact.
6. **Unquoted fields.** Whitespace is preserved verbatim: `" a , b "` =>
   `[[" a "," b "]]`. No trimming ever occurs.
7. **Quotes outside a quoted field.** A `"` seen outside quotes opens a
   quoted section even mid-field (lenient, same as `xiom.serialize.csv`);
   text after the closing quote continues the same field.
8. **Unterminated quoted field.** At EOF the field is closed implicitly and
   its accumulated content is kept (no error channel; documented deviation
   from the stdlib, which returns `Err`).
9. **`csv_parse_line`.** Parses the first record of `text` and returns it.
   `csv_parse_line("")` => `[""]` (one empty field). Input containing several
   records yields only the first.
10. **Writing.** A field is quoted iff `csv_needs_quoting` is true:
    it contains `,`, `"`, LF or CR, or starts/ends with an ASCII space.
    Embedded `"` is doubled. Rows are joined with `"\n"` and there is **no**
    trailing newline. `csv_write(0 rows)` => `""`.
11. **Round trip.** For any `rows`, `csv_parse(csv_write(rows))` returns the
    same records and field values (checked element-wise with
    `str_compare`).
12. **Rectangularity.** True when all records have equal field count; true
    for 0 or 1 records, and for several zero-width records.
13. **Indexing.** `csv_get` uses zero-based `(r, c)`; negative or out-of-range
    indices return `None`. `csv_field_count` is the width of the first record,
    `0` when there are no records.
14. **Encoding.** `Str` is treated as a UTF-8 byte buffer; all scanning is
    byte-wise but never splits or rewrites multi-byte sequences, so non-ASCII
    text round-trips byte-exact.

## 4. API signatures

```xi
pub fn csv_parse_line(text: Str) -> Vec[Str]
pub fn csv_parse(text: Str) -> Vec[Vec[Str]]
pub fn csv_needs_quoting(field: Str) -> Bool
pub fn csv_write_row(fields: &Vec[Str]) -> Str
pub fn csv_write(rows: &Vec[Vec[Str]]) -> Str
pub fn csv_is_rectangular(rows: &Vec[Vec[Str]]) -> Bool
pub fn csv_get(rows: &Vec[Vec[Str]], r: Int, c: Int) -> Option[Str]
pub fn csv_field_count(rows: &Vec[Vec[Str]]) -> Int
```

Complexity: parsing and writing are O(n) over the input characters; all other
functions are O(1) or O(rows).

## 5. Test plan

`tests/test_conformance.xi` (module `csv_tests`) runs 20 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | simple fields | basic record split |
| t2 | quoted comma | comma inside quotes is literal |
| t3 | doubled quotes | `""` => `"` |
| t4 | quoted newline | multiline field in one record |
| t5 | CRLF | one record boundary per CRLF |
| t6 | trailing newline | LF and CRLF add no record |
| t7 | empty text / empty line | `[]` vs `[""]` (rule 3) |
| t8 | empty fields | unquoted, bare, quoted empty (rule 4) |
| t9 | unquoted whitespace | verbatim preservation (rule 6) |
| t10 | needs_quoting specials | comma, quote, LF, CR |
| t11 | needs_quoting spaces | leading/trailing only |
| t12 | write_row | quoting + `""` escaping |
| t13 | csv_write | LF join, no terminator |
| t14 | round trip, single row | element-wise with `str_compare` |
| t15 | round trip, document | multi-row, specials, rectangularity |
| t16 | rectangular true | 0, 1, square, zero-width rows |
| t17 | rectangular false | ragged rows |
| t18 | csv_get | valid cells + all out-of-range shapes |
| t19 | field_count | first row width, 0 on empty |
| t20 | blank line | one empty field record (rule 3) |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 6. Known limitations

- No streaming API; everything is in memory.
- No error reporting: malformed quoting is handled leniently, never rejected.
- Fixed dialect: comma delimiter, `"` quote, LF output.
- A leading UTF-8 BOM is not stripped.
- Writer output is not RFC-strict CRLF; it is the round-trip form of the
  reader.
- No typed value conversion.

## 7. Compiler / stdlib notes

No compiler workarounds were required. The implementation deliberately uses
the proven stdlib idioms from `xiom.serialize.csv`: byte-wise scanning via
`xiom.string.byte_at`, `Vec[UInt8]` field accumulation with `Str::from_utf8`,
and `csv_write_row(&rows[i])` for element access through a `&Vec[Vec[Str]]`.
The test suite routes every string comparison through `str_compare` to avoid
BUG 17, and only `&` (never `&mut`) is taken of locals in call sites, so the
E001 aliasing warning does not fire.
