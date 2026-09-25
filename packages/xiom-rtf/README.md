# xiom.rtf

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** parse an RTF subset into a flat token stream, extract plain text,
> and emit a canonical form. No rendering, no font/color/stylesheet table
> interpretation, no RTF 1.9+ destination semantics.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare` and `xiom.convert`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.rtf` is a small, strict, in-memory codec for a documented RTF subset.
It tokenizes a whole RTF document into a flat stream (groups, control words,
control symbols, `\'hh` byte escapes, `\uNNNN` unicode escapes and text
runs), extracts the visible plain text, and writes the stream back as
canonical RTF. Everything is byte-wise over a `Str`; the module never
interprets fonts, colors, stylesheets or destinations -- those control words
pass through as ordinary tokens.

The token stream is stored as four parallel `Vec`s (`kinds`, `texts`,
`params`, `depth`) because XIOM v0.61.3 cannot hold `Vec[StructType]`. The
exact grammar, the error catalog and every deliberate limit are in `SPEC.md`.

## API

| Function | Returns | Description |
|---|---|---|
| `rtf_parse(text)` | `Result[RtfTokens, Str]` | Parse a whole document; strict document start, brace balance and error catalog. |
| `rtf_emit(tokens)` | `Str` | Canonical RTF: single space after every control word, lowercase hex, `\uN ?` fallback. |
| `rtf_plain_text(tokens)` | `Str` | Visible text: text runs, control symbols, `\'hh` bytes (except `\'00`), `\uNNNN` code units with surrogate-pair joining. |
| `rtf_token_count(tokens)` | `Int` | Number of tokens. |
| `rtf_kind(tokens, i)` | `Str` | Kind of token `i`; `""` out of range. |
| `rtf_text(tokens, i)` | `Str` | Text of token `i` (see the kinds table); `""` out of range. |
| `rtf_param(tokens, i)` | `Int` | Numeric parameter; `rtf_no_param()` when absent. |
| `rtf_has_param(tokens, i)` | `Bool` | True for `control` tokens with a parameter and for all `unicode` tokens. |
| `rtf_depth(tokens, i)` | `Int` | Group depth of token `i`; `-1` out of range. |
| `rtf_hex_value(tokens, i)` | `Int` | Raw byte value of a `hex` token (0..255); `-1` otherwise. |
| `rtf_no_param()` | `Int` | The no-parameter sentinel, `-2147483649`. |

## Token kinds

| Kind | Text | Param | Example |
|---|---|---|---|
| `group_open` | `""` | sentinel | `{` |
| `group_close` | `""` | sentinel | `}` |
| `control` | word name | parameter or sentinel | `\li-360` |
| `symbol` | `\`, `{` or `}` | sentinel | `\\` |
| `hex` | two lowercase hex digits | byte value 0..255 | `\'41` |
| `unicode` | UTF-8 of the code unit (`""` for 0) | code unit 0..65535 | `\u65?` |
| `text` | run bytes (CRLF normalized to LF) | sentinel | `hello` |

## Usage

```xi
use xiom.rtf;
use xiom.io;

fn main() -> Int {
  let r = rtf_parse("{\\rtf1\\ansi Hello \\u65?\\'21}");
  match r {
    Ok(t) => {
      io.println(rtf_plain_text(&t));   // "Hello A!"
      io.println(rtf_emit(&t));         // "{\rtf1 \ansi Hello \u65 ?\'21}"
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.rtf
```

Expected tail: 26 `[PASS]` lines, `xiom.rtf: all tests passed`, then
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Limitations

- Strict subset: a document must start with `{\rtf1` and be exactly one
  outermost group; bytes before it or after its closing brace are errors.
- Only `\\`, `\{`, `\}` are accepted as control symbols; other control
  symbols (`\*`, `\~`, `\-`, ...) are bad-control-word errors.
- `\'hh` bytes are kept raw (no code page interpretation) and `\uN` accepts
  a signed 16-bit RTF value; surrogate code units are not combined into
  characters in the token stream (only `rtf_plain_text` joins pairs).
- Font, color and stylesheet tables, destinations and RTF 1.9+ semantics
  are pass-through control words, never interpreted or skipped.
- `\'00` and `\u0` contribute no plain-text byte (XIOM `Str` is
  NUL-terminated); their values remain visible through `rtf_hex_value` and
  `rtf_param`.
- In-memory only: the whole document is one `Str`; no streaming API.

See `SPEC.md` for the grammar, the error catalog and the test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
