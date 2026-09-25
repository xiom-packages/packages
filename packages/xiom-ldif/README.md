# xiom.ldif

> **Status:** IMPLEMENTED -- new package, incubating (not published).
> **Scope:** a pure-XIOM LDIF (RFC 2849) content-entry codec: records
> separated by blank lines, `attr: value` lines, folded continuation lines,
> comments, CRLF/LF, three value forms (plain, base64 with a strict
> self-contained decoder, URL as a raw token), canonical emitting with
> 76-character base64 wrapping, and a flat parallel-vector data model.
> **Deps:** `xiom.std` only (library imports `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare`).

## What it is

`xiom.ldif` parses in-memory LDIF documents into a flat `Ldif` value and
emits the canonical form again. It is deliberately narrow:

- **Content entries only.** `dn` is required as the first attribute of every
  entry; `changetype` (change/modify records) is rejected as a non-goal.
- **No LDAP semantics.** DNs are opaque strings (no parsing, validation or
  normalization), attribute names/options are not resolved, and there is no
  schema checking.
- **No URL fetching.** The `name:< url` form is preserved as a raw token with
  an `ldif_attr_is_url` predicate.
- **Binary-safe base64.** `name:: base64` is decoded by a strict
  self-contained decoder (alphabet `A-Z a-z 0-9 + /`, length a positive
  multiple of 4, `=` only as final padding); decoded bytes live in a byte
  pool so payloads containing NUL survive, and `ldif_attr_bytes` returns them
  binary-exact.

## API

| Function | Returns | Description |
|---|---|---|
| `ldif_parse(text)` | `Result[Ldif, Str]` | Parse an LDIF document (LF or CRLF). |
| `ldif_entry_count(l)` | `Int` | Number of entries. |
| `ldif_entry_attr_count(l, e)` | `Int` | Attribute count of entry `e`. |
| `ldif_dn(l, e)` | `Str` | DN value of entry `e` (its first attribute). |
| `ldif_attr_name(l, e, i)` | `Str` | Attribute description, exactly as written. |
| `ldif_attr_value(l, e, i)` | `Str` | Text value (base64 decoded, truncated at NUL). |
| `ldif_attr_bytes(l, e, i)` | `Vec[UInt8]` | Binary-safe value bytes. |
| `ldif_attr_kind(l, e, i)` | `Int` | `LDIF_KIND_PLAIN` / `_BASE64` / `_URL`. |
| `ldif_attr_is_url(l, e, i)` | `Bool` | True for the `name:< url` form. |
| `ldif_first_value(l, e, name)` | `Option[Str]` | First value of a name (case-insensitive). |
| `ldif_kind_label(kind)` | `Str` | `"plain"` / `"base64"` / `"url"` / `"unknown"`. |
| `ldif_emit(l)` | `Str` | Canonical LDIF text (LF, no trailing LF). |

Accessors are total: out-of-range indices yield `""`, `0`,
`LDIF_KIND_PLAIN`, `false`, `None` or an empty vector.

```xi
use xiom.ldif;

let r = ldif_parse("dn: cn=Ada,dc=example,dc=org\ncn: Ada\ndescription:: aGVsbG8=\nseeAlso:< https://example.org/ada\n");
match r {
  Ok(l) => {
    io.println(ldif_dn(&l, 0));                    // "cn=Ada,dc=example,dc=org"
    io.println(ldif_attr_value(&l, 0, 2));         // "hello"
    io.println(ldif_kind_label(ldif_attr_kind(&l, 0, 2)));  // "base64"
    io.println(ldif_emit(&l));
  },
  Err(e) => { io.println(e); },
}
```

## Canonical form

`ldif_emit` writes entries in document order with LF endings and exactly one
blank line between entries. Plain values are `name: value`, URL values
`name:< url`; base64 values are re-encoded canonically as `name:: <base64>`
with 76 base64 characters per line and continuation lines starting with one
space. A parsed document round-trips through emit/parse unchanged (entries,
attribute names, kinds and values).

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 22 `[PASS]` lines, then `xiom.ldif: all tests passed`, exit 0.

## Errors

Parse failures are `Err("ldif: ...")`: control bytes, a fold without a
previous line, a line without `:`, a malformed attribute description,
`changetype`, a missing/duplicate/misplaced `dn`, and bad base64. See
`SPEC.md` for the full catalog and its precedence rules.

## Limitations

Content entries only (`changetype` rejected); DNs are opaque; URLs are never
fetched; no lone-CR line endings and no BOM stripping; a plain value's
leading spaces are absorbed by the form's FILL; `ldif_attr_value` truncates
decoded base64 at the first NUL (use `ldif_attr_bytes`); comments are not
preserved on emit and base64 is canonicalized.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
