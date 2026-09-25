# xiom.fits -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.fits`, version `0.1.0`).
Module: `src/fits.xi` (`module xiom.fits`).
Depends on `xiom.std`; the library module imports `xiom.string` and
`xiom.string.compare` from it (tests add `xiom.test`, `xiom.io`,
`xiom.convert`).

## Scope

A pure-XIOM (no FFI) codec for the header part of FITS files, following the
IAU FITS Standard 4.0 card/block layout for a documented subset:

- `fits_parse` decodes whole 2880-byte blocks into a validated `FitsHeader`
  (a flat card list in five parallel vectors);
- `fits_encode` emits the stored raw cards, appends the `END` card and pads
  with ASCII spaces to a 2880-byte multiple;
- `fits_card_format` formats one canonical fixed-width 80-character card,
  and `fits_push_card` / `fits_push_*` validate and append cards while a
  header is built;
- accessors (`fits_card`, `fits_keyword`, `fits_kind`, `fits_value`,
  `fits_comment`) and first-match lookup (`fits_find` plus typed helpers)
  read the header back;
- deterministic `Err(Str)` messages for malformed blocks/cards.

## Non-goals

- Data-unit decoding: no image arrays, no other extensions, no BINTABLE
  column/table decoding, no WCS math.
- The long-string `CONTINUE` convention: a string must be closed inside its
  own card.
- Complex values `(real, real)`, HIERARCH / long-keyword cards, nested or
  recursive structures of any kind.
- Numeric conversion: integer/real tokens are never parsed into `Int` or
  `Float64`; callers do that explicitly.
- UTF-8 validation of card bytes, character-set conversion or locale
  handling (FITS headers are an ASCII protocol).
- Random access / streaming: the whole header is an in-memory
  `Vec[UInt8]`.
- Canonical ordering or uniqueness of keywords: duplicates are preserved
  and lookup is a document-order first-match scan.

## Block and card layout

A header is `N >= 1` 2880-byte blocks, i.e. 36 cards per block, read
sequentially across block boundaries. Cards are 80 bytes:

| Columns (1-based) | Content |
|---|---|
| 1-8 | keyword, left-justified, space-padded (blank = continuation card) |
| 9 | `=` for value cards |
| 10 | space (canonical; any spaces are skipped when decoding) |
| 11-30 | value field: numbers/logicals right-justified, strings left-justified |
| 31-80 | ` / comment` when a comment is present, else spaces |

The final card is `END` (keyword `END`, rest of the card spaces). Every byte
after the END card, up to the end of the last block, must be an ASCII space.
A header may therefore carry trailing all-space blocks.

Value forms recognized while decoding:

| Form | Kind | Stored value |
|---|---|---|
| `'text'` with `''` meaning one `'` | `FITK_STR` | decoded text (no quotes) |
| `T` or `F` (uppercase only) | `FITK_LOGICAL` | `"T"` / `"F"` |
| optional sign + digits | `FITK_INT` | exact raw token |
| optional sign, digits with `.` and/or `E`/`e`/`D`/`d` exponent | `FITK_REAL` | exact raw token |
| value field empty | `FITK_UNDEFINED` | `""`, `fits_value` returns None |
| `COMMENT` / `HISTORY` keyword | `FITK_COMMENT` / `FITK_HISTORY` | text in `fits_comment` |
| blank keyword field | `FITK_BLANK` | text in `fits_comment` |

A real token must contain a `.` or an exponent so that decoding gives it
kind `FITK_REAL` (a bare digit run is always `FITK_INT`); this keeps the kind
stable across a format/parse round-trip.

Canonical `fits_card_format` output:

- value card: keyword in columns 1-8, `=` in column 9, one space in column
  10; the value field fills columns 11-30 (numbers/logicals right-justified
  with spaces; strings left-justified, keeping the closing quote at or
  before column 30 when it fits); a longer value extends past column 30;
  then a non-empty comment is appended as ` / comment`; the card is padded
  with spaces to 80 characters;
- `COMMENT` / `HISTORY`: the keyword left-justified in columns 1-8 and the
  text from column 9;
- blank card: eight spaces, then the text from column 9.

Canonical examples (columns 1-8, `=` in 9, one space in 10; the numeric and
logical tokens end in column 30, the string field starts in column 11, and
trailing space padding to column 80 is not shown):

```
SIMPLE  =                    T / file does conform to FITS standard
BITPIX  =                   16 / number of bits per data pixel
OBJECT  = 'M31'                / object name
COMMENT   built by xiom.fits
END
```

## API signatures

All functions are free functions in module `xiom.fits` (no self methods):

```xi
pub const FITK_STR: Int = 0;
pub const FITK_LOGICAL: Int = 1;
pub const FITK_INT: Int = 2;
pub const FITK_REAL: Int = 3;
pub const FITK_UNDEFINED: Int = 4;
pub const FITK_COMMENT: Int = 5;
pub const FITK_HISTORY: Int = 6;
pub const FITK_BLANK: Int = 7;

pub type FitsHeader = {
  cards: Vec[Str];      // raw 80-character card text, verbatim
  keywords: Vec[Str];   // trimmed keyword ("" for blank-keyword cards)
  kinds: Vec[Int];      // FITK_* constant
  values: Vec[Str];     // STR: decoded text; LOGICAL: "T"/"F"; INT/REAL: raw token; else ""
  comments: Vec[Str];   // comment text; for COMMENT/HISTORY/BLANK the card text
}

pub fn fits_parse(data: &Vec[UInt8]) -> Result[FitsHeader, Str]
pub fn fits_encode(h: &FitsHeader) -> Vec[UInt8]
pub fn fits_card_format(keyword: Str, kind: Int, value: Str, comment: Str) -> Result[Str, Str]
pub fn fits_new() -> FitsHeader
pub fn fits_push_card(h: &mut FitsHeader, card: Str) -> Result[Unit, Str]
pub fn fits_push_str(h: &mut FitsHeader, keyword: Str, value: Str, comment: Str) -> Result[Unit, Str]
pub fn fits_push_logical(h: &mut FitsHeader, keyword: Str, value: Bool, comment: Str) -> Result[Unit, Str]
pub fn fits_push_int(h: &mut FitsHeader, keyword: Str, token: Str, comment: Str) -> Result[Unit, Str]
pub fn fits_push_float(h: &mut FitsHeader, keyword: Str, token: Str, comment: Str) -> Result[Unit, Str]
pub fn fits_push_undefined(h: &mut FitsHeader, keyword: Str, comment: Str) -> Result[Unit, Str]
pub fn fits_push_comment(h: &mut FitsHeader, text: Str) -> Result[Unit, Str]
pub fn fits_push_history(h: &mut FitsHeader, text: Str) -> Result[Unit, Str]
pub fn fits_push_blank(h: &mut FitsHeader, text: Str) -> Result[Unit, Str]
pub fn fits_card_count(h: &FitsHeader) -> Int
pub fn fits_card(h: &FitsHeader, i: Int) -> Str
pub fn fits_keyword(h: &FitsHeader, i: Int) -> Str
pub fn fits_kind(h: &FitsHeader, i: Int) -> Int
pub fn fits_value(h: &FitsHeader, i: Int) -> Option[Str]
pub fn fits_comment(h: &FitsHeader, i: Int) -> Str
pub fn fits_find(h: &FitsHeader, keyword: Str) -> Int
pub fn fits_str_value(h: &FitsHeader, keyword: Str) -> Option[Str]
pub fn fits_bool_value(h: &FitsHeader, keyword: Str) -> Option[Bool]
pub fn fits_int_token(h: &FitsHeader, keyword: Str) -> Option[Str]
pub fn fits_float_token(h: &FitsHeader, keyword: Str) -> Option[Str]
pub fn fits_comment_of(h: &FitsHeader, keyword: Str) -> Str
```

## Semantics

`fits_parse(data)`
: `data.len()` must be non-zero and a multiple of 2880. Cards are read 80
  bytes at a time across block boundaries; the END card terminates the
  header and is not stored. Every byte after END must be a space. On `Err`
  no partial header is returned.

`fits_encode(h)`
: Emits the stored cards verbatim (so a parsed header re-encodes
  byte-for-byte, including non-canonical spacing, when the source ends in
  the block that holds `END`), appends `END`, pads to 80, then pads with
  spaces to the next multiple of 2880. Output length is always a positive
  multiple of 2880 and always uses the minimal number of blocks, so accepted
  trailing all-space blocks are not reproduced. Cannot fail because cards
  are validated on push.

`fits_card_format(keyword, kind, value, comment)`
: Formats one canonical card. The keyword is trimmed of trailing spaces and
  must be 1-8 bytes of `A-Z 0-9 - _` and not one of `END`, `COMMENT`,
  `HISTORY`. For `FITK_COMMENT`/`FITK_HISTORY`/`FITK_BLANK` the `value`
  parameter is the card text (≤ 72 bytes) and `keyword`/`comment` are
  ignored. For `FITK_UNDEFINED`, `value` must be empty. The returned string
  is always exactly 80 characters on `Ok`.

`fits_push_card(h, card)`
: `card.len()` must be 80. The card is classified exactly as `fits_parse`
  classifies cards; an `END` card is rejected because `fits_encode` appends
  `END` itself. `h` is unchanged on `Err` (atomic failure).

`fits_push_str` / `fits_push_logical` / `fits_push_int` / `fits_push_float`
/ `fits_push_undefined` / `fits_push_comment` / `fits_push_history` /
`fits_push_blank`
: Format via `fits_card_format` and append; `h` is unchanged when
  formatting fails. `fits_push_logical` maps `true` to `T` and `false` to
  `F`, so it cannot produce a bad logical.

`fits_card_count(h)` / `fits_card(h, i)` / `fits_keyword(h, i)` /
`fits_kind(h, i)` / `fits_comment(h, i)`
: Out-of-range `i` yields `-1` (`fits_kind`) or `""` (all Str accessors).
  `fits_keyword` is `""` for blank-keyword cards; `fits_comment` returns the
  card text for `COMMENT`/`HISTORY`/`BLANK` cards and the trimmed bytes after
  `/` for value cards (`""` when there is no comment).

`fits_value(h, i)`
: `Some` for `FITK_STR` (decoded), `FITK_LOGICAL` (`"T"`/`"F"`), `FITK_INT`
  and `FITK_REAL` (raw token); `None` for `FITK_UNDEFINED`,
  `FITK_COMMENT`, `FITK_HISTORY`, `FITK_BLANK` and out-of-range `i`.

`fits_find(h, keyword)`
: Trailing spaces are stripped from the query; matching is ASCII
  case-insensitive and a linear scan in file order, so the first of several
  identical keywords wins. An empty query and blank-keyword cards never
  match. `-1` when absent.

`fits_str_value` / `fits_bool_value` / `fits_int_token` / `fits_float_token`
/ `fits_comment_of`
: Look up the first match and enforce the expected kind; `None` (or `""` for
  the comment) when the keyword is absent or the card has another kind.

Duplicate keywords, duplicate `COMMENT`/`HISTORY` cards and non-standard
spacing are accepted and preserved.

## Error catalog

| Condition | Error text |
|---|---|
| `fits_parse`: `data.len() == 0` or not a multiple of 2880 | `fits: bad block padding` |
| `fits_parse`: non-space byte after the END card | `fits: bad block padding` |
| `fits_parse`: END card with non-space bytes after column 3 | `fits: bad block padding` |
| `fits_parse`: no END card before the buffer ends | `fits: missing END` |
| `fits_push_card`: `card.len() != 80` | `fits: card not 80 chars` |
| `fits_push_card`: END card appended directly | `fits: unexpected END` |
| `fits_push_card`/`fits_parse`: value card without `=` in column 9 | `fits: missing '='` |
| `fits_push_card`/`fits_parse`: keyword not 1-8 bytes of `A-Z 0-9 - _` | `fits: bad keyword` |
| `fits_push_card`/`fits_parse`: string whose closing quote is missing | `fits: quote not closed` |
| `fits_push_card`/`fits_parse`: non-space, non-`/` bytes after a value | `fits: junk after value` |
| `fits_push_card`/`fits_parse`: unquoted token that is not `T`/`F`, an integer or a real | `fits: bad logical` |
| `fits_card_format`/`_value_field`: `FITK_LOGICAL` with value other than `T`/`F` | `fits: bad logical` |
| `fits_card_format`/`_value_field`: `FITK_INT` token not `[+-]?digits` | `fits: invalid integer` |
| `fits_card_format`/`_value_field`: `FITK_REAL` token without `.`/exponent or malformed | `fits: invalid real` |
| `fits_card_format`/`_value_field`: `FITK_UNDEFINED` with a non-empty value | `fits: invalid value` |
| `fits_card_format`: `kind` outside `FITK_STR..FITK_UNDEFINED` | `fits: bad kind` |
| `fits_card_format`: keyword invalid or reserved (`END`/`COMMENT`/`HISTORY`) with a value kind | `fits: bad keyword` |
| `fits_card_format`: card would exceed 80 characters (also quoted string > 70, card text > 72) | `fits: card too long` |

Check order in `fits_parse`/`fits_push_card`: block length, then per card:
blank keyword, `END`, `COMMENT`, `HISTORY`, `=` in column 9, keyword
charset, then the value (string / logical / integer / real / undefined).
Messages are deterministic and prefixed with `fits: `.

## Complexity

| Operation | Complexity |
|---|---|
| `fits_parse` | O(data bytes) |
| `fits_encode` | O(cards) |
| `fits_card_format` / `fits_push_*` | O(keyword + value + comment) |
| `fits_card_count` / `fits_kind` | O(1) |
| `fits_card` / `fits_keyword` / `fits_value` / `fits_comment` | O(field) |
| `fits_find` | O(cards * keyword) |
| `fits_*_value` / `fits_*_token` / `fits_comment_of` | O(cards * keyword) |

## Test plan

`tests/test_conformance.xi` (`module fits_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. minimal one-card header: pinned keyword, `FITK_LOGICAL` kind, value `T`,
   `fits_bool_value` lookup;
2. classic `SIMPLE`/`BITPIX`/`NAXIS`/`EXTEND` header: kinds, raw token,
   comments, `fits_find`, typed lookups;
3. quoted strings: decode, `''` escaping, empty string, comment;
4. integer/real raw-token preservation: `+0042`, `-1.50E+02`, `.5`, `-0`,
   `2.5D-3`;
5. `COMMENT`/`HISTORY`/blank continuation cards: kinds, texts, `None`
   values, keyword `""`, lookup of `COMMENT`/`HISTORY`, empty query;
6. `fits_push_card`: lengths 79/81/short and `END` are `Err`, header
   unchanged, a good card appends;
7. missing `END` is `Err(fits: missing END)` for a carded block and an
   all-space block;
8. bad block padding: empty input, 1440-byte truncation, 2881 bytes, junk
   after END, junk inside the END card;
9. unclosed quotes (`'unterminated`, trailing `''`) are
   `Err(fits: quote not closed)`;
10. non-`T`/`F` bare tokens (`Y`, `TRUE`) are `Err(fits: bad logical)` in
    parse and in `fits_card_format` (`Maybe`, lowercase `t`);
11. junk between a value and `/` is `Err(fits: junk after value)`; a
    `42 /ok` card parses with comment `ok`;
12. missing `=` in column 9 and keyword charset/lowercase violations are
    the documented errors;
13. `fits_card_format` rejects bad keywords, bad kinds, invalid integer/real
    tokens, non-empty undefined values, 69-character strings, over-long
    comments and 73-character card text;
14. pinned exact 80-character output for logical, string, integer, real,
    `COMMENT`, blank and escaped-string cards;
15. undefined values parse (bare and with comment) and round-trip through
    `fits_push_undefined`;
16. builder round-trip: 9 cards of every kind -> `fits_encode` ->
    `fits_parse` preserves count, values, comments and kinds, and a second
    encode is byte-identical;
17. parse -> encode reproduces a non-canonical header byte-for-byte;
18. 40 cards span two blocks (5760 bytes); cards 0, 35, 36 and 39 are
    intact across the block boundary;
19. out-of-range accessors (`-1`, `count`) and empty-header lookups are
    safe;
20. duplicate-keyword lookup is first-match and case-insensitive; typed
    accessors enforce the stored kind.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.fits
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Header only: no data unit, no tables, no WCS; the codec ends at `END`.
- No `CONTINUE` long strings, no complex values, no HIERARCH.
- Numeric tokens are text; no conversion, range or precision policy is
  applied here.
- Raw card bytes are treated as ASCII; no UTF-8 validation or transcoding.
- Accessors trim comment/text whitespace; exact bytes remain available via
  `fits_card` and `fits_encode`.
- Duplicates and non-standard spacing are preserved; lookup is first-match.
- All-space blocks after the block holding `END` are accepted but dropped by
  `fits_encode` (it always emits the minimal block count).
- `FitsHeader` is a plain value type: no interior mutability, not
  thread-safe, and each header owns its strings.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_header`/`_err_header`/`_ok_str`/`_err_str`/`_ok_bytes`/`_err_bytes`/
  `_ok_unit`/`_err_unit` (constructing Results directly in other functions
  miscompiles in this compiler).
- Str values read from `Vec[Str]` elements are bound to typed locals and
  compared with `xiom.string.compare.str_compare` (BUG 17: `==` on such
  values lowers to a pointer comparison).
- No `Vec[StructType]` and no `Vec[Float64]`: the header is five flat
  parallel vectors and numeric values stay text tokens.
- Free functions only (no self methods); mutable state travels through
  `&mut FitsHeader` parameters.
- Byte reads go through `xiom.string.byte_at` and are only compared against
  ASCII constants below 128; raw card bytes are copied into a `Vec[UInt8]`
  and materialized with `Str::from_utf8`, the same pattern as `xiom.toml`.
- The package declares no `extern "C"` blocks (no FFI), and the compile is
  warning-free on the pinned compiler.
