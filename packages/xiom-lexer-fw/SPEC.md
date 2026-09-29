# xiom.lexer-fw -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.lexer` (`src/lexer.xi`). Pure XIOM, no FFI, no IO, no
`Vec[Float64]`, no `Vec[StructType]`.

## 1. Scope

A framework for building lexical analyzers over source-like text held in a
`Str`:

- token kinds as `Int` constants and a `Token` record;
- `ScanState` (`source`, `pos`, `line`, `col`) with peek/advance/expect
  helpers and 1-based line/column tracking across newlines;
- regex-free, byte-wise matchers: identifier, integer, float-style, string,
  line comment, block comment;
- `KeywordTable`: parallel `Vec[Str]` words + `Vec[Int]` kinds, exact
  case-sensitive lookup;
- `lex_next` (single token) and `lex_scan` (whole stream as parallel `Vec`
  fields) with exact first-error reporting;
- token text reconstruction (`token_text`, `lex_span_text`, `lex_kind_name`).

`Str` is treated as a UTF-8 byte buffer; all scanning is byte-wise and every
byte read is widened with `(b as Int) & 0xFF` before comparison (pinned
v0.62.1 trap: direct `UInt8` comparisons at >= 128 are miscompiled).

## 2. Non-goals

- Regex, rule DSLs or code generation; custom token classes require a custom
  `lex_next`-style loop over `ScanState`.
- Unicode identifiers, Unicode normalization, case-insensitive matching,
  `\uXXXX`/numeric escapes, character literals.
- Error recovery: the first bad byte aborts with an `Err`; no partial stream.
- Streaming/incremental scanning and AST construction.
- Sign folding: `-3` is punctuation `-` followed by integer `3` (see 4.3).

Complementarity: `xiom.lexing` offers a fixed configurable lexer that
*decodes* string escapes but has no comments, floats or line/col tracking;
`xiom.tokenizer` splits natural-language text without token kinds. This
package is the lower-level scanner framework and is the only one with
line/column tracking, `lex_next`, comment tokens and float literals.

## 3. Token kinds

| Constant | Value | Meaning |
|---|---|---|
| `LEX_KIND_NONE` | 0 | No token / lookup miss; never stored by `lex_scan`. |
| `LEX_KIND_IDENTIFIER` | 1 | Identifier not in the table. |
| `LEX_KIND_INTEGER` | 2 | Integer literal, text verbatim. |
| `LEX_KIND_FLOAT` | 3 | Float-style literal, text verbatim. |
| `LEX_KIND_STRING` | 4 | String literal, quotes included, raw text. |
| `LEX_KIND_PUNCT` | 5 | Table-resolved punctuation/operator. |
| `LEX_KIND_KEYWORD` | 6 | Identifier whose exact text is registered as a keyword. |
| `LEX_KIND_COMMENT` | 7 | Line or block comment, delimiters included. |
| `LEX_KIND_EOF` | 8 | End of input; zero-width `lex_next` token, never stored by `lex_scan`. |

`lex_kind_name` maps 1..8 to `"identifier"`, `"integer"`, `"float-literal"`,
`"string-literal"`, `"punctuation"`, `"keyword"`, `"comment"`, `"EOF"` and
anything else to `"none"`.

`Token` = `{ kind: Int; start: Int; end: Int; line: Int; col: Int; }`.
`start` is inclusive and `end` exclusive; `line`/`col` are 1-based and refer
to the first byte.

## 4. Scan state

`ScanState` = `{ source: Str; pos: Int; line: Int; col: Int; }`.

1. **pos.** Byte offset, 0-based, in `0..source.len()`. `lex_state_new`
   starts at `(0, 1, 1)`.
2. **peek.** `lex_peek`/`lex_peek_at` return the byte as `0..255`, or `-1`
   for any out-of-bounds offset (negative or at/after the end). They never
   trap.
3. **advance.** `lex_advance` consumes one byte: an LF (`10`) sets
   `line + 1`, `col = 1`; every other byte sets `col + 1`. At end of input it
   is a no-op. `lex_advance_n(s, n)` consumes `n <= 0` as a no-op and stops
   at end of input, applying the same tracking per byte.
4. **newlines.** CRLF counts as one newline (the LF); a lone CR is an ordinary
   byte for the tracker (and whitespace for `lex_skip_spaces`, so it adds one
   column).
5. **expect.** `lex_expect(s, byte)` consumes the byte when it equals the
   current byte (an `Int` in `0..255`); `lex_expect_str(s, text)` consumes the
   literal when it is the next exact prefix (`str_compare`), an empty text
   matches trivially. Both return `Bool` and never move on mismatch.
6. **whitespace.** `lex_skip_spaces` skips space, tab, CR and LF (tracking
   lines/columns), nothing else.

## 5. Matcher grammars

Every matcher takes `(source: Str, at: Int)` and returns the matched length
(`0` = no match at `at`), except the two fallible matchers, which return
`Result[Int, Str]` (`Ok(0)` = no match). Matching never reads out of bounds
(`_peek` returns -1 there, which fails every test).

| Matcher | Grammar (`at` must start it) | Notes |
|---|---|---|
| `lex_match_identifier` | `[A-Za-z_][A-Za-z0-9_]*` maximal run | ASCII only. |
| `lex_match_integer` | `[0-9](_?[0-9])*` maximal run | Single underscores between digits; `1__0` -> `1` then `__0`; `1_` -> `1`. |
| `lex_match_float` | `digits '.' digits [ ('e'\|'E') ['+'\|'-'] digits ]` | `digits` are the integer digit runs (underscores allowed). Both sides of `.` need a digit: `1.` and `.5` do not match. A bare exponent marker is not consumed: `1.5e` matches `1.5`. |
| `lex_match_string` | `'"' *( escape | any-byte-except-'"' ) '"'` | `escape` in `\"` `\\` `\n` `\t` only; a raw LF inside is kept; length includes both quotes. |
| `lex_match_line_comment` | `'//' *any-byte-except-LF` | Length >= 2; excludes the LF; `//` at end matches length 2. |
| `lex_match_block_comment` | `'/*' ( *any-byte-except-"*/" ) '*/'` | Non-nesting; length includes both delimiters; `/*/` is unterminated. |

## 6. Engine resolution order

`lex_next` (and therefore `lex_scan`) resolves a position as follows:

1. skip whitespace (space, tab, CR, LF);
2. at end of input: `Ok(Token{ kind: EOF, start == end == pos })`;
3. `//` -> line comment token; `/*` -> block comment token (built-ins win over
   the table);
4. `[A-Za-z_]` -> maximal identifier run classified through
   `lex_table_classify`: the registered kind (e.g. `LEX_KIND_KEYWORD`,
   `LEX_KIND_PUNCT`) when the exact text is registered, else
   `LEX_KIND_IDENTIFIER`;
5. digit -> float when `lex_match_float` matches, else integer;
6. `"` -> string token (the raw span, escapes recognized but not decoded);
7. otherwise the longest registered table word matching at the position (any
   registered kind, ties to the earliest registered entry, empty words never
   match);
8. otherwise `Err("lexer: unexpected byte at <pos>")`.

Comments are part of the stream: `lex_scan` does not filter them, and it does
not append an EOF sentinel (loop until `lex_next` reports EOF to get one).
Whitespace never produces tokens.

## 7. Keyword table

`KeywordTable` = `{ words: Vec[Str]; kinds: Vec[Int]; }`, maintained as
parallel arrays by `lex_table_add` (one push each, never out of sync).

- `lex_table_lookup` compares the exact text (`str_compare`, case-sensitive,
  first match wins) and returns the registered kind or `LEX_KIND_NONE`.
- `lex_table_classify` is `lookup` with a fallback to `LEX_KIND_IDENTIFIER`,
  so identifiers can classify to keyword *or* punct kinds (a word registered
  with `LEX_KIND_PUNCT` scans as punctuation even though it reads as an
  identifier).
- An empty word is registrable but never matches.
- Accessors are range-safe: `lex_table_word` -> `""`, `lex_table_kind` ->
  `LEX_KIND_NONE`.

## 8. Token stream layout

`TokenStream` = `{ kinds: Vec[Int]; starts: Vec[Int]; ends: Vec[Int];
lines: Vec[Int]; cols: Vec[Int]; }` -- five parallel Vecs (no
`Vec[StructType]`), all pushed together per token. Token `i` is fully
described by index `i` in each Vec: kind, inclusive start, exclusive end,
1-based line, 1-based column.

Accessors: `lex_token_count`; `lex_token_kind` (`LEX_KIND_NONE` out of
range); `lex_token_start`/`lex_token_end`/`lex_token_line`/`lex_token_col`
(`-1` out of range). `token_text(source, t, i)` returns the raw source slice
`[starts[i], ends[i])` and `""` out of range; `lex_span_text(source, start,
end)` is the shared slice primitive. `str_slice` clamps inverted and
out-of-range spans, so neither traps.

Text is never decoded: a string token's text includes its quotes and its
backslash sequences exactly as written, and no NUL byte is ever synthesized
(so `Str::from_utf8`/NUL issues cannot arise here).

## 9. Error catalog

Messages are fixed: `"lexer: " + text + " at " + decimal position`
(`xiom.convert.int_to_string`).

| Message | Condition | Position |
|---|---|---|
| `lexer: unexpected byte at <pos>` | the byte starts no built-in token and matches no registered table word | the byte itself |
| `lexer: unterminated string at <pos>` | no closing unescaped `"` before end of input (including a trailing backslash) | the opening quote |
| `lexer: invalid escape at <pos>` | backslash followed by a byte other than `"`, `\`, `n`, `t` | the backslash |
| `lexer: unterminated block comment at <pos>` | no closing `*/` before end of input | the opening `/` of `/*` |

`lex_match_string` / `lex_match_block_comment` return the same messages when
used standalone. `lex_scan` stops at the first error and discards everything
scanned so far; `lex_next` stops at the error and leaves the state on the
offending token start (the caller decides whether to resynchronize).

## 10. API signatures

```xi
pub const LEX_KIND_NONE: Int = 0;
pub const LEX_KIND_IDENTIFIER: Int = 1;
pub const LEX_KIND_INTEGER: Int = 2;
pub const LEX_KIND_FLOAT: Int = 3;
pub const LEX_KIND_STRING: Int = 4;
pub const LEX_KIND_PUNCT: Int = 5;
pub const LEX_KIND_KEYWORD: Int = 6;
pub const LEX_KIND_COMMENT: Int = 7;
pub const LEX_KIND_EOF: Int = 8;

pub type Token = { kind: Int; start: Int; end: Int; line: Int; col: Int; }
pub type ScanState = { source: Str; pos: Int; line: Int; col: Int; }
pub type KeywordTable = { words: Vec[Str]; kinds: Vec[Int]; }
pub type TokenStream = { kinds: Vec[Int]; starts: Vec[Int]; ends: Vec[Int]; lines: Vec[Int]; cols: Vec[Int]; }

pub fn lex_state_new(source: Str) -> ScanState
pub fn lex_state_source(s: &ScanState) -> Str
pub fn lex_pos(s: &ScanState) -> Int
pub fn lex_line(s: &ScanState) -> Int
pub fn lex_col(s: &ScanState) -> Int
pub fn lex_at_end(s: &ScanState) -> Bool
pub fn lex_peek(s: &ScanState) -> Int
pub fn lex_peek_at(s: &ScanState, ahead: Int) -> Int
pub fn lex_advance(s: &mut ScanState)
pub fn lex_advance_n(s: &mut ScanState, n: Int)
pub fn lex_expect(s: &mut ScanState, expected: Int) -> Bool
pub fn lex_expect_str(s: &mut ScanState, text: Str) -> Bool
pub fn lex_skip_spaces(s: &mut ScanState)

pub fn lex_match_identifier(source: Str, at: Int) -> Int
pub fn lex_match_integer(source: Str, at: Int) -> Int
pub fn lex_match_float(source: Str, at: Int) -> Int
pub fn lex_match_string(source: Str, at: Int) -> Result[Int, Str]
pub fn lex_match_line_comment(source: Str, at: Int) -> Int
pub fn lex_match_block_comment(source: Str, at: Int) -> Result[Int, Str]

pub fn lex_kind_name(kind: Int) -> Str

pub fn lex_table_new() -> KeywordTable
pub fn lex_table_add(t: &mut KeywordTable, word: Str, kind: Int)
pub fn lex_table_len(t: &KeywordTable) -> Int
pub fn lex_table_word(t: &KeywordTable, i: Int) -> Str
pub fn lex_table_kind(t: &KeywordTable, i: Int) -> Int
pub fn lex_table_lookup(t: &KeywordTable, word: Str) -> Int
pub fn lex_table_classify(t: &KeywordTable, word: Str) -> Int

pub fn lex_next(s: &mut ScanState, table: &KeywordTable) -> Result[Token, Str]
pub fn lex_scan(source: Str, table: &KeywordTable) -> Result[TokenStream, Str]

pub fn lex_token_count(t: &TokenStream) -> Int
pub fn lex_token_kind(t: &TokenStream, i: Int) -> Int
pub fn lex_token_start(t: &TokenStream, i: Int) -> Int
pub fn lex_token_end(t: &TokenStream, i: Int) -> Int
pub fn lex_token_line(t: &TokenStream, i: Int) -> Int
pub fn lex_token_col(t: &TokenStream, i: Int) -> Int
pub fn lex_span_text(source: Str, start: Int, end: Int) -> Str
pub fn token_text(source: Str, t: &TokenStream, i: Int) -> Str
```

Complexity: matchers and `lex_next` are O(token length) except the table
step, which scans the registered words (`O(|table| * longest word)` per
position); `lex_scan` is O(input bytes * per-token table cost); all state and
stream accessors are O(1); `token_text`/`lex_span_text` are O(slice length).

## 11. Test plan

`tests/test_conformance.xi` (module `lexer_tests`) runs 28 named checks via
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Fixtures are built in-test: a 16-word table and a
21-token XIOM-like snippet.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | identifiers | maximal `[A-Za-z_][A-Za-z0-9_]*` runs and raw texts (section 5) |
| t2 | keywords vs identifiers | exact table text classifies, prefixes stay identifiers (6.4) |
| t3 | integers | digits with single underscores kept verbatim (5) |
| t4 | integer underscore edges | `1__0` -> int + ident, `1_` -> int + ident (5) |
| t5 | floats | exponent forms, `E+`, negative exponent, underscored runs (5) |
| t6 | float maximal munch | `1.5e` splits, `1.` is int + dot, `-3` is punct + int (5, 6.5) |
| t7 | strings | quotes included in raw text; empty literal (8) |
| t8 | string escapes | `\"` `\\` `\n` kept raw, one token, no decoding (5, 8) |
| t9 | string raw LF | literal spans the LF; following token line/col exact (4.3) |
| t10 | line comments | text excludes LF; EOF `//` token; positions (5, 6.3) |
| t11 | block comments | delimiters inclusive, one token, next position exact (5) |
| t12 | snippet kinds | 21 tokens covering every kind except EOF (6, 8) |
| t13 | snippet positions | exact 1-based line:col for all 21 tokens (4) |
| t14 | line/col tracking | LF, CRLF and lone CR semantics (4.4) |
| t15 | unterminated string | opening-quote position, trailing backslash case (9) |
| t16 | invalid escape | backslash position, standalone matcher (9) |
| t17 | unterminated block comment | opening-slash position, `/*/` case (9) |
| t18 | unexpected byte | exact position; >= 128 byte widening; table-driven punctuation (3, 6.7-8) |
| t19 | empty input | empty and whitespace-only input yield no tokens (6.1) |
| t20 | stream accessors | exact fields and `NONE`/`-1` out-of-range values (8) |
| t21 | lex_next engine | one token per call, EOF sentinel, state advance (6) |
| t22 | scan state helpers | peek/peek_at/expect/expect_str/advance_n, lines (4) |
| t23 | matcher lengths | standalone matchers incl. no-match cases (5) |
| t24 | matcher errors | public string matcher returns the catalog message (9) |
| t25 | keyword table | parallel accessors, exact first-match lookup, ranges (7) |
| t26 | punct classification | identifier word registered as punct classifies as punct (7) |
| t27 | text API | raw reconstruction, span clamping, kind names (3, 8, 9) |
| t28 | determinism | repeated scans identical in kinds/spans/texts (12) |

Determinism: scanning the same text with the same table yields the same
tokens, positions and errors; the input is never mutated.

## 12. Compiler / stdlib notes (pinned v0.62.1)

- Every byte read goes through `(b as Int) & 0xFF` before comparison: direct
  `UInt8` comparisons at >= 128 are still miscompiled, and the >= 128 path is
  covered by the t18 non-ASCII case.
- `Str` values read from `Vec[Str]` elements are compared with `str_compare`
  (BUG 17); `Vec[Int]`/`Vec[Str]` element reads use typed locals.
- `Ok`/`Err` literals exist only in the leaf constructors `_ok_int`,
  `_err_str`, `_ok_token`, `_err_token`, `_ok_stream`, `_err_stream`.
- No `Vec[StructType]`: `TokenStream` is five parallel Vecs, and every push
  site pushes to all five.
- Free functions only; no indexed `Vec[fn]` dispatch; no `[T,U]` callbacks.
- `lex_next`/`lex_scan` bodies touch the state only through `&mut`-taking
  helpers (`_peek_mut`, `_peek_at_mut`, `lex_advance*`, `lex_skip_spaces`) to
  avoid mixing a `&` call with a `&mut` access on the same local (advisory
  E001); `match` appears only in test helpers.
- Bitwise/additive mixes are parenthesized (`(b as Int) & 0xFF`); no
  sign-bit tests, no shifts of negative values and no division tricks are
  used (all byte values are 0..255 and all arithmetic is additive).
