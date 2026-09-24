# xiom.lexing

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a configurable lexer for source-like text: identifiers, keywords,
> integers, strings and operators.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.lexing` is a byte-wise, configuration-driven lexer over UTF-8 `Str`
input. A `Lexer` holds the registered keywords and operators; `lexer_scan`
produces a `TokenList` of parallel arrays (`kinds`, `texts`, `starts`).
Identifiers are `[A-Za-z_][A-Za-z0-9_]*` runs, classified `"kw"` when their
exact text is a registered keyword and `"ident"` otherwise. Integers are
`[0-9]+` runs, `"str"` tokens decode the `\"` `\\` `\n` `\t` escapes, and any
registered operator is matched longest-first. Whitespace is skipped; a byte
that starts no token is reported as
`Err("lexing: unexpected byte at <pos>")`. See `SPEC.md` for the full
grammar, escape table, error catalog and test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `lexer_new()` | `Lexer` | A lexer with no keywords and no operators. |
| `lexer_add_keyword(l, word)` | nothing | Register an exact-text keyword; matching is case-sensitive. |
| `lexer_add_operator(l, op)` | nothing | Register an operator; during scanning the longest match at a position wins (ties: earliest registered). An empty string never matches. |
| `lexer_scan(l, text)` | `Result[TokenList, Str]` | Scan `text`: whitespace skipped, `[A-Za-z_][A-Za-z0-9_]*` => `"kw"`/`"ident"`, `[0-9]+` => `"int"`, `"..."` => `"str"`, registered operator => `"op"`; errors carry the byte offset. |
| `lexer_token_count(t)` | `Int` | Number of tokens; 0 for an empty list. |
| `lexer_kind(t, i)` | `Str` | `"ident"`, `"kw"`, `"int"`, `"str"` or `"op"`; `""` out of range. |
| `lexer_text(t, i)` | `Str` | Token text (escapes decoded for `"str"`); `""` out of range. |
| `lexer_start(t, i)` | `Int` | Byte offset of the token's first byte; `-1` out of range. |

Because an out-of-range `lexer_kind`/`lexer_text` also returns `""`, use
`lexer_token_count` or the kind to distinguish an empty string literal
(`"str"` with text `""`) from a missing token.

## Usage

```xi
use xiom.lexing;
use xiom.io;

fn main() -> Int {
  var lx = lexer_new();
  lexer_add_keyword(&mut lx, "let");
  lexer_add_operator(&mut lx, "=");
  lexer_add_operator(&mut lx, "==");
  let r = lexer_scan(&lx, "let x == 42");
  match r {
    Ok(t) => {
      io.println(lexer_token_count(&t));   // 4
      io.println(lexer_kind(&t, 0));       // kw
      io.println(lexer_text(&t, 2));       // ==
      io.println(lexer_start(&t, 3));      // 9
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.lexing
```

Expected tail: 24 `[PASS]` lines, `xiom.lexing: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- Fixed token classes: identifiers, keywords, integers, strings and
  operators. There is no way to declare a new class.
- No regex and no rule DSL: keywords and operators are the only
  configuration; everything else is built in.
- No float literals: `3.14` scans as int `3`, then `.` errors unless it was
  registered as an operator.
- No comments: neither `//` nor `/* */` is recognized; comment markers are
  just operator candidates or errors.
- ASCII-only identifiers: every non-ASCII byte is outside the identifier
  alphabet.
- No character literals, no string interpolation, and only the four escapes
  `\"` `\\` `\n` `\t`; there is no `\uXXXX` or other numeric escape.
- In-memory, single-pass scanning: no streaming API, no token-level
  resumption and no comments/whitespace tokens.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
