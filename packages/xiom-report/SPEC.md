# xiom.report -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.report` (`src/report.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free set of plain-text layout helpers for in-memory
reports:

- `report_table` -- fixed-width tables with an optional header and a `-`
  separator,
- `report_kv` -- aligned key/value blocks,
- `report_bullets` -- bulleted item lists with continuation indentation,
- `report_wrap` -- greedy word wrap with an indent prefix,
- `report_rule` -- repeated-character rule lines.

The module is infallible (no `Result` channel) and treats every `Str` as a
UTF-8 byte buffer; all widths are byte lengths (see section 7).

## 2. Non-goals

- Unicode display widths, CJK double-width handling, grapheme clusters.
- ANSI color/styling (output is plain text; escapes would break widths).
- Right/center alignment, borders, per-cell padding control, truncation.
- CSV/TSV/Markdown/HTML table dialects (see `xiom.csv`, `xiom.tsv`).
- Escaping, trimming or validating cell content.
- Any FFI, file I/O, or registry integration.

## 3. Layout rules

### 3.1 report_table

1. **Columns.** `ncols = max(headers.len(), max row cell count)`.
   A zero-width table (`ncols == 0`) renders as `""`.
2. **Widths.** For column `c`, let `h = len(headers[c])` when
   `c < headers.len()` else `0`, and let `m` be the longest cell in column
   `c` (0 when no row has that column). Then
   `width(c) = max(h, m) + max(pad, 0)`. A negative `pad` is clamped to 0,
   so cells never shrink below their content.
3. **Lines.** Every line is the concatenation of its cells, each
   left-justified and padded with spaces to exactly `width(c)`. Missing
   cells (short rows, or columns beyond `headers.len()`) are treated as `""`
   and padded, so **all lines of one table have the same byte length** and
   the last column is padded too (trailing spaces are part of the format).
4. **Header and separator.** When `headers` is non-empty, the first line is
   the header line (columns without a header contribute spaces, keeping the
   line length uniform) and the second line is the separator: `width(c)`
   copies of `-` for each column, concatenated (with `pad = 0` this is one
   continuous run). When `headers` is empty both lines are omitted.
5. **Data rows.** One line per row, in input order; cells beyond
   `headers.len()` use data-only widths, and cells beyond `ncols` cannot
   exist by construction. No trailing newline; an empty row list with
   non-empty headers yields exactly the header and separator lines.
6. **Content.** Cells are emitted verbatim: no trimming, no quoting, no
   escaping. A cell containing LF breaks the uniform-line-length invariant
   (callers strip or replace newlines first).

Example (`headers = ["name", "age"]`, `rows = [["Ada","36"],["Bob","7"]]`,
`pad = 1`; `|` marks the byte length):

```
name age | 9
---------| 9
Ada  36  | 9
Bob  7   | 9
```

### 3.2 report_kv

1. **Pairs.** `count = min(keys.len(), values.len())`; rendering stops at the
   shorter length. `count == 0` renders as `""`.
2. **Alignment.** `key_width` is the longest **rendered** key (keys beyond
   `count` are ignored), and every key is left-justified to `key_width` with
   spaces before the separator is appended.
3. **Lines.** `pad_right(key, key_width) + separator + value`, one line per
   pair, joined with LF and no trailing newline. The separator is used
   verbatim (`": "` supplies the customary colon and gap); an empty value is
   kept (`"k : "`), and an empty separator concatenates directly
   (`"ab"` for key `"a"`, value `"b"`).

Example (`keys = ["name", "id"]`, `values = ["Ada", "42"]`, `": "`):

```
name: Ada
id  : 42
```

### 3.3 report_bullets

1. **Item lines.** Each item is split on LF (`xiom.string.lines`). The first
   part becomes `marker + part`; every later part becomes
   `spaces(marker.len()) + part`, so multi-line items stay nested under the
   marker. An empty item renders the marker alone.
2. **Output.** All item lines (across all items) are joined with LF and no
   trailing newline. An empty item list renders as `""`; an empty marker
   renders plain item lines.

### 3.4 report_wrap

1. **Short circuit.** `width < 1` returns `text` unchanged (no indent);
   empty `text` returns `""`.
2. **Logical lines.** `text` is split on LF; each logical line is wrapped
   independently and yields **at least one** output piece (an empty or
   all-space logical line yields one empty piece, so a trailing LF produces
   a final indent-only line).
3. **Tokens and spacing.** A logical line is split on ASCII spaces; empty
   tokens are skipped, so space runs collapse to one space and leading or
   trailing spaces are dropped. There is no other whitespace handling
   (a TAB is an ordinary byte).
4. **Greedy fill.** A word joins the current line with one space when
   `width >= current.len() + 1 + word.len()`; otherwise the current line is
   emitted and the word starts a new line. The first word starts a line
   unconditionally.
5. **Hard break.** A word longer than `width` is broken into chunks of
   exactly `width` bytes (the final chunk may be shorter) with each full
   chunk ending a line; the final chunk becomes the current line, so a
   following word may still join it when it fits.
6. **Output.** All pieces are joined with LF, no trailing newline, and every
   line is prefixed with `indent` (which may be empty). Widths are byte
   counts.

Examples:

```
report_wrap("the quick brown fox", 9, "> ") -> "> the quick\n> brown fox"
report_wrap("abcdefgh", 3, "")              -> "abc\ndef\ngh"
report_wrap("ab abcdefgh", 3, "")           -> "ab\nabc\ndef\ngh"
report_wrap("a b", 0, "> ")                 -> "a b"        (unchanged)
```

### 3.5 report_rule

1. `width <= 0` renders as `""`.
2. The unit is the **first byte** of `ch` (`xiom.string.str_slice(ch, 0, 1)`)
   when `ch` is non-empty, otherwise `-`. The result is that unit repeated
   `width` times. A multi-byte `ch` therefore contributes only its first
   byte.

## 4. API signatures

```xi
pub fn report_table(headers: &Vec[Str], rows: &Vec[Vec[Str]], pad: Int) -> Str
pub fn report_kv(keys: &Vec[Str], values: &Vec[Str], separator: Str) -> Str
pub fn report_bullets(items: &Vec[Str], marker: Str) -> Str
pub fn report_wrap(text: Str, width: Int, indent: Str) -> Str
pub fn report_rule(width: Int, ch: Str) -> Str
```

All containers are read-only (`&`); every function returns a fresh `Str` and
never writes to its inputs. No function can fail.

## 5. Test plan

`tests/test_conformance.xi` (module `report_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | table basic | widths, header + separator, uniform line length (pad 1) |
| t2 | table no headers | no separator line |
| t3 | table pad | pad 0, pad 2, negative pad clamped to 0 |
| t4 | table short rows | missing cells padded, uniform widths |
| t5 | table extra cells | data-only widths beyond `headers.len()` |
| t6 | table zero-cell row | renders as one fully padded blank line |
| t7 | table empties | `""` for no headers/cells; headers-only = two lines |
| t8 | table empty cells | empty strings still occupy their columns |
| t9 | kv alignment | keys justified, separators line up |
| t10 | kv shorter side | stops at `min(keys, values)`; empty side = `""` |
| t11 | kv separator/value | separator verbatim, empty value kept |
| t12 | kv rendered keys | alignment ignores keys past `count` |
| t13 | bullets basic | marker + items joined with LF |
| t14 | bullets continuation | LF indent = `marker.len()` spaces |
| t15 | bullets empties | empty list, empty item, empty marker |
| t16 | wrap fits | text that fits stays on one indented line |
| t17 | wrap greedy | fill to width on spaces |
| t18 | wrap long word | hard break at exactly `width` |
| t19 | wrap width < 1 | returns text unchanged, indent ignored |
| t20 | wrap newlines | LF starts a wrapped, indented logical line |
| t21 | wrap trivia | empty text, per-line indent, space-run collapse |
| t22 | wrap boundaries | the joining space counts against the width |
| t23 | rule basics | first byte repeated, empty `ch`, non-positive width |
| t24 | integration | rule length matches the table separator width |

Element and whole-output comparisons use `xiom.string.compare`'s
`str_compare`, never `==` (BUG 17: `==` on `Str` values read from `Vec[Str]`
elements lowers to a pointer comparison).

## 6. Known limitations

- Byte-oriented widths: multi-byte UTF-8 characters count as several
  columns; padding, wrapping and rules can split a multi-byte sequence.
- No ANSI styling, alignment variants, borders, or truncation.
- Table cells are emitted verbatim; an embedded LF breaks the fixed-width
  invariant, and no escaping/quoting is provided.
- LF is the only structural newline; CR is data.
- `report_wrap` normalizes spacing (collapses runs, drops edges) and has no
  hyphenation or word-splitting beyond the hard break.
- Results are built by `Str` concatenation: fine for terminal-sized reports,
  not for very large documents.

## 7. Compiler / stdlib notes

The module follows the v0.61.3 constraints proven across the ecosystem:
free functions only (no self methods, no lambdas, no `Vec[StructType]`, no
`Vec[fn]`); no `match` and therefore no exhaustiveness concern; no
`Ok`/`Err` construction; and no string equality at all (the layout logic
compares lengths only), which sidesteps BUG 17 entirely. Every `Vec` element
read is bound with an explicit type (`let cell: Str = ...`,
`let width: Int = ...`).

All byte work goes through `xiom.string` helpers (`str_split`, `lines`,
`str_slice`, `str_repeat`), the proven `xiom.csv`/`xiom.humanize` idiom, so
raw `byte_at` access (and its `UInt8` widening pitfall) is not needed: `ch`
handling uses `str_slice` to take the first byte, and padding uses
`str_repeat(" ", n)`. Only `&` (never `&mut`) is taken of locals at call
sites, so the E001 aliasing warning does not fire, and no compiler workaround
was required.
