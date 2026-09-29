# xiom.lexer-fw

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a framework for building lexical analyzers: scan state with
> 1-based line/column tracking, regex-free byte matchers, a keyword/
> punctuation table and a parallel-Vec token stream with exact errors.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test`,
> `xiom.io` and `xiom.convert`.

## Scope

`xiom.lexer-fw` packages the reusable machinery of a hand-written scanner over
UTF-8 `Str` input. It deliberately stops before any language grammar: it
gives you the state machine, the byte matchers, the classification table and
the token stream, and you assemble those into a lexer for your language.

Five pieces, all in `xiom.lexer`:

1. **Token kinds** as `Int` constants (`LEX_KIND_IDENTIFIER` .. `LEX_KIND_EOF`)
   plus the `Token` record.
2. **`ScanState`** (`source`, `pos`, `line`, `col`) with
   `lex_peek`/`lex_peek_at`/`lex_advance`/`lex_advance_n`/`lex_expect`/
   `lex_expect_str`/`lex_skip_spaces`; `line`/`col` are 1-based and LF-aware.
3. **Matchers** (regex-free, byte-wise): identifier, integer (single
   underscores between digits), float-style (`digits '.' digits [exponent]`),
   string (with `\"` `\\` `\n` `\t` recognized), line comments and block
   comments.
4. **`KeywordTable`**: parallel `Vec[Str]` words + `Vec[Int]` kinds, exact
   case-sensitive lookup via `str_compare`; identifiers classify to the
   registered keyword/punct kind or stay identifiers.
5. **Scanner**: `lex_next` returns one `Token` per call (whitespace skipped,
   `LEX_KIND_EOF` at end); `lex_scan` returns the whole stream as the parallel
   `Vec` fields `kinds`, `starts`, `ends`, `lines`, `cols`, with exact
   first-error messages.

Token text is always the **raw source slice** (escapes are recognized while
scanning but never decoded); `token_text` reconstructs it. See `SPEC.md` for
the full semantics, error catalog and test plan.

### Relationship to the other text packages

| Package | What it does | Where the overlap ends |
|---|---|---|
| `xiom.lexing` | configurable lexer; identifiers/keywords/integers/strings/operators; decodes the four string escapes; no comments, no floats, no line/col. | `xiom.lexer-fw` adds comments, float literals, line/column tracking, a single-token `lex_next` engine and a state/expect API for custom scanners; it keeps text raw instead of decoding. |
| `xiom.tokenizer` | natural-language splitting into words/sentences/lines/n-grams; infallible `Vec[Str]` returns. | No token kinds, tables or errors there; this package is for source-like text. |

## API

Kinds, state and values:

| Function | Returns | Description |
|---|---|---|
| `lex_state_new(source)` | `ScanState` | Fresh state at byte 0, line 1, column 1. |
| `lex_state_source(s)` / `lex_pos(s)` / `lex_line(s)` / `lex_col(s)` | `Str` / `Int` | Read the state fields (`pos` 0-based, line/col 1-based). |
| `lex_at_end(s)` | `Bool` | True when all bytes are consumed. |
| `lex_peek(s)` / `lex_peek_at(s, ahead)` | `Int` | Byte (0..255) at the position, or `-1` out of bounds. |
| `lex_advance(s)` / `lex_advance_n(s, n)` | nothing | Consume 1 / n bytes, tracking lines and columns. |
| `lex_expect(s, byte)` / `lex_expect_str(s, text)` | `Bool` | Consume the expected byte / literal; `false` and no movement on mismatch. |
| `lex_skip_spaces(s)` | nothing | Skip space, tab, CR and LF. |
| `lex_kind_name(kind)` | `Str` | `"identifier"`, ..., `"EOF"`, `"none"`. |

Matchers (each returns the matched length, `0` = no match; string/block
comment return `Result[Int, Str]` for exact errors):

| Function | Grammar |
|---|---|
| `lex_match_identifier(source, at)` | `[A-Za-z_][A-Za-z0-9_]*` |
| `lex_match_integer(source, at)` | `[0-9](_?[0-9])*` (no sign) |
| `lex_match_float(source, at)` | `digits '.' digits [ ('e'\|'E') ['+'\|'-'] digits ]` (underscores allowed in digit runs) |
| `lex_match_string(source, at)` | `"..."` with `\"` `\\` `\n` `\t`; raw LF allowed |
| `lex_match_line_comment(source, at)` | `//` to (not including) LF or end |
| `lex_match_block_comment(source, at)` | `/* ... */`, non-nesting |

Table and scanner:

| Function | Returns | Description |
|---|---|---|
| `lex_table_new()` | `KeywordTable` | Empty table. |
| `lex_table_add(t, word, kind)` | nothing | Register an exact, case-sensitive word with a kind. |
| `lex_table_len(t)` / `lex_table_word(t, i)` / `lex_table_kind(t, i)` | `Int` / `Str` / `Int` | Parallel-array accessors; `""`/`NONE` out of range. |
| `lex_table_lookup(t, word)` / `lex_table_classify(t, word)` | `Int` | Registered kind / else `NONE`; `classify` falls back to `LEX_KIND_IDENTIFIER`. |
| `lex_next(s, table)` | `Result[Token, Str]` | Scan one token, advancing the state; EOF token at end. |
| `lex_scan(source, table)` | `Result[TokenStream, Str]` | Whole stream; comments included, no EOF sentinel. |
| `lex_span_text(source, start, end)` / `token_text(source, t, i)` | `Str` | Raw source slice; `""` when the span is empty/out of range. |
| `lex_token_count(t)` | `Int` | Token count. |
| `lex_token_kind(t, i)` / `lex_token_start(t, i)` / `lex_token_end(t, i)` / `lex_token_line(t, i)` / `lex_token_col(t, i)` | `Int` | Field of token `i`; `NONE`/`-1` out of range. |

## Usage

```xi
use xiom.lexer;
use xiom.io;

fn main() -> Int {
  var t = lex_table_new();
  lex_table_add(&mut t, "let", LEX_KIND_KEYWORD);
  lex_table_add(&mut t, "=", LEX_KIND_PUNCT);
  lex_table_add(&mut t, "==", LEX_KIND_PUNCT);
  let src = "let x == 3.14 // done";
  let r = lex_scan(src, &t);
  match r {
    Ok(st) => {
      io.println(lex_token_count(&st));                       // 5
      io.println(lex_kind_name(lex_token_kind(&st, 0)));      // keyword
      io.println(lex_kind_name(lex_token_kind(&st, 3)));      // float-literal
      io.println(token_text(src, &st, 2));                    // ==
      io.println(lex_token_col(&st, 4));                      // 15
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.lexer-fw
```

Expected tail: 28 `[PASS]` lines, `xiom.lexer-fw: all tests passed`, then
`port: PASS (passed=28 failed=0 program_exit=0 exit=0)`.

## Limitations

- **ASCII-only identifiers.** No Unicode identifiers: any byte >= 128
  outside a string or comment is an `unexpected byte` error (nothing is
  silently dropped). Strings and comments pass non-ASCII bytes through
  byte-exact.
- **Raw token text.** Escapes are recognized for scanning but not decoded;
  consumers that need the decoded value must unescape themselves (contrast
  `xiom.lexing`, which decodes).
- **Signs are caller-level.** `-3` scans as punctuation `-` then integer `3`;
  the framework never folds a sign into a numeric literal.
- **Comments are tokens and do not nest.** `lex_scan` keeps `comment` tokens
  in the stream; block comments end at the first `*/`; line comment text
  excludes the trailing LF.
- **First-error only.** No panic-free recovery and no partial stream on
  `Err`; recovered diagnostics need a custom `lex_next` loop.
- **No rule DSL or regex.** New token classes require writing a matcher and
  driving `ScanState` yourself; the table only classifies exact texts.
- **Line/col are byte columns.** Tab counts as one column, not a tab stop;
  positions are byte offsets, not character offsets.
- **In-memory, single pass.** No streaming/resumable scanning, no token
  re-scanning and no AST construction.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
