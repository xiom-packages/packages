# xiom.fixed -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.fixed` (`src/fixed.xi`). Pure XIOM, no FFI.

## 1. Scope

A small fixed-width ("column") text reader/writer for in-memory `Str`
documents:

- compute layout totals (`fixed_total_width`, `fixed_column_count`),
- parse a document into `Vec[Vec[Str]]` rows (`fixed_parse`,
  `fixed_parse_trimmed`),
- write rows back into a fixed-width document (`fixed_write`),
- index a parsed cell (`fixed_field`).

A layout is a `Vec[Int]` of column widths in bytes. Every row produced or
consumed by this module has exactly `widths.len()` fields.

## 2. Non-goals

- No multi-byte-aware widths: columns are byte counts, not characters.
- No right/center alignment, borders, headers, or separators.
- No escaping or quoting: cells are raw text.
- No typed decoding of numbers, dates, booleans.
- No streaming/incremental parsing; whole `Str` in memory.
- No FFI, file I/O, or registry integration.

## 3. Layout model

1. **Column c** occupies `widths[c]` bytes. Cumulative offsets start at 0 and
   advance by `max(widths[c], 0)` per column.
2. **Width <= 0** defines an empty column: parsing yields `""` for it and
   consumes no input; writing emits no bytes for it, even when a cell exists.
   (Documented behavior; `fixed_total_width` ignores such widths.)
3. **Total width** is the sum of the non-negative widths
   (`fixed_total_width`), i.e. the byte length of every written row.
4. **Column count** is `widths.len()` (`fixed_column_count`); an empty layout
   has 0 columns, and every parsed row then has 0 fields.

## 4. Slice rules (parsing)

1. **Line boundaries.** A line ends at LF. The CR of a CRLF pair is dropped
   and is **not** field data. A bare CR (no following LF) is ordinary data.
2. **Trailing terminator.** One terminator at end of input ends the last line
   and adds no row: `"AABB\n"` and `"AABB\r\n"` each have one line. Two
   terminators leave one blank line: `"AABB\n\n"` has two lines.
3. **Empty text.** `fixed_parse("")` => `[]` (no rows at all, not even one
   empty row).
4. **Blank line.** A blank line is one row whose fields are all `""`, so
   `"\n"` parses to one row of `widths.len()` empty fields.
5. **Field slicing.** For column `c` with `widths[c] > 0`, the field is
   `str_slice(line, start, start + widths[c])`, where `start` is the sum of
   the preceding non-negative widths; `start` then advances by `widths[c]`.
   For `widths[c] <= 0` the field is `""` and `start` does not advance.
6. **Short lines.** `str_slice` clamps to the line end, so starting at or past
   the line end (or ending past it) yields `""` for the missing fields.
   Example: widths `[4,4,4]`, line `"abcdefgh"` => `["abcd","efgh",""]`.
7. **Raw fields.** `fixed_parse` returns the sliced bytes verbatim, untrimmed.
   `fixed_parse_trimmed` applies `xiom.string.str_trim` (leading and trailing
   ASCII whitespace) to each field after slicing; internal whitespace is
   preserved by both.
8. **Row width.** Every row has exactly `widths.len()` fields; a line yields a
   field per column even when the line is shorter than the layout.
9. **Encoding.** `Str` is treated as a UTF-8 byte buffer; slicing is byte-wise
   and may split a multi-byte sequence (see section 9).

## 5. Truncation and padding rules (writing)

1. **Row count and join.** Rows are emitted in input order, joined with LF and
   with no trailing newline. An empty `rows` input yields `""`.
2. **Row width.** Each row emits exactly `widths.len()` columns; cells beyond
   `widths.len()` are ignored; missing cells are treated as `""`.
3. **Column c.** For `widths[c] <= 0` nothing is emitted. Otherwise the cell
   is copied and then:
   - **truncated** to `widths[c]` bytes when longer
     (`str_slice(cell, 0, widths[c])`), or
   - **padded** to `widths[c]` bytes when shorter.
   After truncation or padding the cell is exactly `widths[c]` bytes, so every
   written row is `fixed_total_width(widths)` bytes long.
4. **Padding unit.** The first byte of `pad`
   (`str_slice(pad, 0, 1)`); an empty `pad` means the ASCII space `" "`.
   Multi-byte `pad` text degenerates to its first byte (ASCII limitation).
5. **No escaping.** A cell containing LF is written verbatim and breaks the
   line structure; cells are never quoted or escaped.
6. **Examples.** widths `[4,4]`, rows `[["ab","c"],["d","ef"]]`, empty pad:
   `"ab  c   \nd   ef  "`. widths `[3,3]`, row `[["abcdef","x"]]`, empty pad:
   `"abcx  "`. widths `[2,0]`, row `[["ab","zzz"]]`: `"ab"`.

## 6. API signatures

```xi
pub fn fixed_total_width(widths: &Vec[Int]) -> Int
pub fn fixed_column_count(widths: &Vec[Int]) -> Int
pub fn fixed_parse(text: Str, widths: &Vec[Int]) -> Vec[Vec[Str]]
pub fn fixed_parse_trimmed(text: Str, widths: &Vec[Int]) -> Vec[Vec[Str]]
pub fn fixed_write(rows: &Vec[Vec[Str]], widths: &Vec[Int], pad: Str) -> Str
pub fn fixed_field(rows: &Vec[Vec[Str]], r: Int, c: Int) -> Option[Str]
```

Parsing and writing are O(text bytes + rows * widths); `fixed_total_width` is
O(widths); `fixed_column_count` and `fixed_field` are O(1).

## 7. Indexing

`fixed_field` uses zero-based `(r, c)`. Negative indices or an index at/after
`rows.len()` / `rows[r].len()` return `None`; every in-range lookup returns
`Some`. Because parsed rows always have `widths.len()` fields, a parsed cell
is always `Some` (possibly `Some("")`) and never `None`.

## 8. Test plan

`tests/test_conformance.xi` (module `fixed_tests`) runs 18 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | cumulative slicing | 2- and 3-column exact fields (rule 5) |
| t2 | short line | `""` for every missing field (rule 6) |
| t3 | empty text | `[]` for empty, zero-width and empty layouts (rule 3) |
| t4 | blank line | one row of empty fields, `"\n"` => one row (rule 4) |
| t5 | CRLF | CR dropped, not field data (rule 1) |
| t6 | trailing newline | LF/CRLF add no row; two terminators add a blank (rule 2) |
| t7 | raw vs trimmed | untrimmed slices vs `str_trim` per field (rule 7) |
| t8 | zero/negative width | `""` field, no input consumed (rule 2 of section 3) |
| t9 | write exact output | pinned padded text, LF join, no terminator (rules 1-3) |
| t10 | padding char | first byte of `pad`; space when empty (rule 4) |
| t11 | truncation | long cells cut to width; zero width emits nothing (rule 3) |
| t12 | missing cells | empty cells padded; extra cells ignored (rule 2) |
| t13 | round trip trimmed | `fixed_parse_trimmed(fixed_write(rows))` fits-size data |
| t14 | fixed_field | valid cells plus all out-of-range shapes (section 7) |
| t15 | total_width | sums non-negative widths only (section 3) |
| t16 | column_count | `widths.len()` matches parsed row width (section 3) |
| t17 | round trip raw | `fixed_parse(fixed_write(rows))` on exact-width rows |
| t18 | layout integration | dot pad is data; space pad trims; extra cell ignored |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 9. Known limitations

- **Byte widths.** Widths count bytes; a multi-byte UTF-8 character occupies
  several columns, and a truncating write can split a multi-byte sequence.
- **ASCII padding.** Only the first byte of `pad` is used.
- **No escaping.** Cells containing LF cannot round-trip.
- **LF output.** The writer emits LF only; the reader accepts LF and CRLF.
- **Bare CR.** A CR not followed by LF is field data.
- No typed value conversion, no alignment modes, no headers.

## 10. Compiler / stdlib notes

No compiler workarounds were required. The module uses the proven idioms from
`xiom.csv` and `xiom.report`: byte-wise line handling through
`xiom.string.lines` and explicit widening of `xiom.string.byte_at` (`UInt8`)
to `Int` for comparisons; every `Vec` element read is bound to an explicitly
typed local; no string equality is performed at all. The test suite routes
every string comparison through `str_compare` to avoid BUG 17 and takes only
`&` (never `&mut`) of locals in call sites.
