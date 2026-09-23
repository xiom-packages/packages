# xiom.escape

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** context-aware string escaping and unescaping for JSON, HTML, URL
> components and POSIX shell double-quoted strings.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## What it is

`xiom.escape` converts raw text to and from the escaped forms expected by four
common contexts:

- **JSON strings** (RFC 8259): `"` `\` and the C0 control bytes; `\uXXXX`
  decoding is BMP-only and encodes the code point to UTF-8.
- **HTML text/attribute values**: the five named entities `&amp; &lt; &gt;
  &quot; &apos;` plus decimal `&#NN;` and hex `&#xHH;` numeric references.
- **URL components** (RFC 3986): percent-encoding of everything outside the
  unreserved set `[A-Za-z0-9-_.~]`, with space as `%20`.
- **POSIX shell double quotes**: backslash-escaping of `\` `"` `$` and
  `` ` ``.

Every function is a free function over `Str`/`Vec[UInt8]`; there is no FFI.
Escaping is always infallible; decoding returns `Result[Str, Str]` where
malformed input must be reported (JSON, URL), and is deliberately lenient and
infallible for HTML (unknown references stay verbatim), matching the
`xiom.xml` entity decoder.

## API

| Function | Returns | Description |
|---|---|---|
| `escape_json_string(s)` | `Str` | Escape `"` `\` `\b \f \n \r \t` and other C0 controls (`\u00XX`, uppercase hex). |
| `unescape_json_string(s)` | `Result[Str, Str]` | Decode `\" \\ \/ \b \f \n \r \t` and `\uXXXX` (BMP to UTF-8); `Err("escape: ...")` on malformed input. |
| `escape_html(s)` | `Str` | Escape `& < > " '` as `&amp; &lt; &gt; &quot; &apos;`. |
| `unescape_html(s)` | `Str` | Decode those five named entities plus `&#NN;` (decimal) and `&#xHH;` (hex); unknown references stay verbatim. |
| `escape_url_component(s)` | `Str` | Percent-encode every byte outside `[A-Za-z0-9-_.~]`; space becomes `%20`. |
| `unescape_url_component(s)` | `Result[Str, Str]` | Decode `%XX` (case-insensitive hex); `Err("escape: ...")` on truncated/invalid escapes; `+` stays literal. |
| `escape_shell_double(s)` | `Str` | Backslash-escape `\`, `"`, `$` and the backtick for a POSIX double-quoted context. |

Error messages are a single catalog of `Err("escape: ...")` strings; see
`SPEC.md` (the common ones are `escape: trailing backslash`,
`escape: invalid escape sequence`, `escape: truncated unicode escape`,
`escape: invalid unicode escape`, `escape: truncated percent escape`,
`escape: invalid percent escape`).

## Usage

```xi
use xiom.escape;
use xiom.io;

fn main() -> Int {
  io.println(escape_json_string("say \"hi\"\n"));   // say \"hi\"\n
  io.println(escape_html("5 < 6 & 7 > 2"));         // 5 &lt; 6 &amp; 7 &gt; 2
  io.println(escape_url_component("a b/c"));        // a%20b%2Fc
  io.println(escape_shell_double("a\"$b"));         // a\"\$b

  let back = unescape_json_string("\\u2713");
  if back.is_ok {
    io.println(back.value);                         // ✓
  }
  let decoded = unescape_url_component("%C3%A9");
  if decoded.is_ok {
    io.println(decoded.value);                      // é
  }
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.escape
```

Expected tail: 20 `[PASS]` lines, `xiom.escape: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **BMP-only `\u` decoding.** `\uXXXX` decodes single code points up to
  U+FFFF; surrogate pairs (`\uD83D\uDE00`) are rejected with
  `Err("escape: lone surrogate")`, not combined. `\u0000` is rejected too
  (`escape: null escape not supported`) because `Str` is NUL-terminated.
- **JSON escape set is intentionally minimal.** `/` and DEL (0x7F) are legal
  raw in JSON and pass through unescaped; only the C0 controls are
  `\u00XX`-escaped.
- **HTML entity subset.** Only `amp lt gt quot apos`, `&#NN;` and `&#xHH;`
  are decoded; no other named entity (`&nbsp;`, `&copy;`, ...), no
  semicolon-less references, no HTML5 replacement-character behavior.
  Malformed references (bare `&`, `&#;`, `&#xZZ;`, unknown names) stay
  verbatim. `&#0;`, surrogates and code points above U+10FFFF also stay
  verbatim.
- **Component-level URL semantics only.** `escape_url_component` encodes a
  component, not a whole URL (no scheme/host awareness); `+` is never
  treated as a space (that is `application/x-www-form-urlencoded`
  behavior), and no UTF-8 validation is performed on decoded bytes.
- **POSIX double quotes only.** `escape_shell_double` produces text safe
  inside `"..."`; it does not handle single-quoted contexts, newlines, or
  `!` history expansion.

See `SPEC.md` for the exact per-function mappings, the error catalog and the
test plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
