# xiom.eml -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.eml` (`src/eml.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free parser for the *structure* of an RFC 5322/MIME
message held in memory as a `Str`:

- `eml_parse` -- message -> `Result[Email, Str]`,
- `eml_header` / `eml_headers_all` / `eml_header_count` -- header lookup,
- `eml_is_multipart` / `eml_content_type_boundary` -- MIME content-type
  inspection,
- `eml_split_parts` -- multipart body -> raw part payloads.

The module decodes no transfer encoding (base64, quoted-printable), parses
no addresses, dates or MIME parameters beyond `boundary`, and does not
recurse into nested multiparts. It answers "what is the structure?" and
nothing more.

## 2. Data model

```xi
pub type Email = {
  names: Vec[Str];   // header field names, lowercased, document order
  values: Vec[Str];  // unfolded field values, index-aligned with names
  body: Str;         // verbatim text after the first blank line
}
```

Invariants: `names.len() == values.len()`; field names are stored lowercased
and are not unique (duplicates are preserved in order); `body` is the exact
byte range that followed the blank line, or `""` when the message has no
blank line.

`Vec[StructType]` is not usable in this compiler, so the header list is
deliberately flat (two homogeneous vectors) instead of a list of field
structs.

## 3. Message grammar

```
message     = *( field ) blank body
field       = name ":" *WSP value *( line-break WSP value )
name        = 1* ( byte except ":" / CR / LF )
value       = *( byte except CR / LF )
blank       = line-break line-break          ; i.e. a zero-length line
body        = *( byte )                      ; verbatim, may be empty
line-break  = LF / CRLF / CR
```

Parsing decisions (each is covered by the conformance suite):

1. **Physical lines.** A line ends at LF, CRLF or a lone CR; a final line
   without a terminator is still a line. All three terminator shapes are
   accepted in the same message.
2. **End of headers.** The first *zero-length* line ends the header block;
   the rest of the message is the body, byte-for-byte. A line holding only
   whitespace is **not** a separator (see 4).
3. **No blank line.** When the message contains no zero-length line, every
   line belongs to the header block and the body is `""` (documented
   decision; a headers-only message is valid).
4. **Folding.** A physical line whose first byte is space or tab is a
   continuation of the previous field. Its leading whitespace is stripped,
   the previous value is right-trimmed of spaces/tabs, and the two are
   joined with exactly one space. Any number of continuations may follow.
   A continuation line before any header is malformed (see 9).
5. **Field split.** The first `:` on the line separates name and value.
   Everything before it is the name (lowercased byte-wise, ASCII only);
   everything after it has leading spaces/tabs stripped and trailing
   spaces/tabs stripped. Later colons stay in the value.
6. **Duplicates.** Repeated field names are not an error and are not merged:
   each occurrence appends a new `(name, value)` pair in document order.
7. **Empty names and values.** `X:` stores the pair `("x", "")`; `: v`
   stores `("", "v")` (the grammar requires only the colon). Empty names are
   legal by this rule.
8. **Body verbatim.** No trimming, newline normalization or decoding is
   applied to `body`; the byte range after the separator is returned as-is.
9. **Malformed lines.** A non-continuation line without `:` is
   `Err("eml: malformed header line: <line>")`; so is a continuation line
   that appears before any header. Body text is never parsed, so a "bad"
   line after the blank separator is not an error.
10. **Empty input.** `eml_parse("")` is `Ok` with zero headers and an empty
    body.
11. **Encoding.** `Str` is treated as a UTF-8 byte buffer; scanning is
    byte-wise and never rewrites multi-byte sequences. Only ASCII letters
    `A`..`Z` are lowercased in names.

## 4. Header lookup semantics

```xi
pub fn eml_header(e: &Email, name: Str) -> Option[Str]
pub fn eml_headers_all(e: &Email, name: Str) -> Vec[Str]
pub fn eml_header_count(e: &Email) -> Int
```

- Lookups lowercase `name` with the same ASCII rule as stored names, so
  `eml_header(&e, "Subject")` and `eml_header(&e, "subject")` are
  equivalent; matching is byte-exact afterwards (no trimming of the query,
  no locale rules).
- `eml_header` returns the **first** matching value; `None` when absent.
- `eml_headers_all` returns a fresh `Vec[Str]` with every matching value in
  document order; an empty vector when absent. Mutating the result does not
  affect the message.
- `eml_header_count` counts fields, duplicates included.

## 5. Multipart detection and the boundary parameter

```xi
pub fn eml_is_multipart(e: &Email) -> Bool
pub fn eml_content_type_boundary(e: &Email) -> Option[Str]
```

- `eml_is_multipart` takes the first `content-type` header (case-insensitive
  lookup) and tests whether its value starts with `multipart/`,
  case-insensitively. Missing header -> `false`.
- `eml_content_type_boundary` scans the first `content-type` value for the
  `boundary` attribute:
  - Attributes are separated by `;`; spaces/tabs around names, `=` and
    values are skipped. The attribute name is matched case-insensitively.
  - `boundary="quoted value"` returns the bytes between the quotes; a quoted
    value may contain spaces. A missing closing quote takes the rest of the
    value.
  - `boundary=bare` returns bytes up to the next `;` or whitespace.
  - `boundary=` with nothing after it returns `Some("")`; an empty boundary
    yields no parts (section 6).
  - Missing Content-Type header, missing attribute, or a value that is not a
    `name=value` attribute -> `None`.
  - Only the first `boundary` parameter is returned; duplicate or
    RFC 2231-continued parameters are not merged.

## 6. Multipart splitting rules

```xi
pub fn eml_split_parts(e: &Email, boundary: Str) -> Vec[Str]
```

The body is scanned line by line (terminators as in section 3). Let
`D = "--" + boundary` and `C = D + "--"`.

1. A line equal to `D` is an opening delimiter; a line equal to `C` is the
   closing delimiter. Equality is byte-exact on the line content (the line
   terminator is not part of the line), so trailing spaces or transport
   padding make a delimiter unrecognized.
2. Everything before the first opening delimiter (the *preamble*) is
   ignored, as is everything after the closing delimiter (the *epilogue*) --
   including any delimiter-looking lines in it.
3. A part starts at the byte after the opening delimiter's line terminator
   and ends at the start of the line terminator immediately preceding the
   next delimiter. That preceding terminator belongs to the delimiter and is
   **not** part of the payload; consequently two adjacent delimiters produce
   an empty part, not a one-newline part.
4. Parts are raw: internal line terminators, headers, blank lines and
   transfer-encoded payloads are returned untouched and are not unfolded.
5. No closing delimiter: after the last opening delimiter the remainder of
   the body (possibly empty after a trailing terminator) is one final part.
   No opening delimiter at all, or `boundary == ""`: the result is an empty
   vector.
6. The return value is a fresh `Vec[Str]` in body order.

Complexity: `eml_parse` and `eml_split_parts` are O(input length); lookups
are O(header count).

## 7. API signatures

```xi
pub fn eml_parse(text: Str) -> Result[Email, Str]
pub fn eml_header(e: &Email, name: Str) -> Option[Str]
pub fn eml_headers_all(e: &Email, name: Str) -> Vec[Str]
pub fn eml_header_count(e: &Email) -> Int
pub fn eml_is_multipart(e: &Email) -> Bool
pub fn eml_content_type_boundary(e: &Email) -> Option[Str]
pub fn eml_split_parts(e: &Email, boundary: Str) -> Vec[Str]
```

## 8. Error catalog

Parse failures are `Err(msg)` where `msg` starts with `"eml: "`. There is
exactly one error class:

| Message | Trigger |
|---|---|
| `eml: malformed header line: <line>` | a header line without `:` (`BADHEADER`, `this is not a header`), or a space/tab continuation line before any header |

Everything after the blank separator is body text and never produces an
error, even when it looks like a malformed header.

## 9. Test plan

`tests/test_conformance.xi` (module `eml_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | simple message | 3 headers, lookups, body verbatim with CRLF |
| t2 | name lowercasing | stored names lowercase; case-insensitive query |
| t3 | folding | space/tab/multi-line folds; trailing space at fold |
| t4 | duplicates | count 3; first value; `headers_all` order |
| t5 | no blank line | headers only, body `""` (with and without newline) |
| t6 | LF vs CRLF | both parse; body keeps `\n` / `\r\n` |
| t7 | no colon | `Err("eml: ")`; body text not parsed |
| t8 | first/all | `x` -> first; `headers_all` order; `y`/`Y`; missing `z` |
| t9 | multipart detection | `multipart/mixed` true; `text/plain`/missing false; uppercase true |
| t10 | bare boundary | `boundary=xyz`; mid-list parameter; missing parameter -> None |
| t11 | quoted boundary | quoted with hyphen and with spaces; no boundary -> None |
| t12 | two parts | parsed boundary feeds `split_parts`; 2 parts |
| t13 | three parts | 3 parts in order |
| t14 | closing marker | excluded; epilogue ignored |
| t15 | preamble/epilogue | only the real part survives |
| t16 | empty text | 0 headers, empty body, no multipart, no parts |
| t17 | colon in value | `a:b:c`, `10:20:30` kept whole |
| t18 | lookalike lines | `------`, `--notb`, inline `--b` are content |
| t19 | empty value | `X:` counts and returns `""` |
| t20 | raw parts | internal `\r\n\r\n` survives |
| t21 | no closing marker | final part runs to end of body |
| t22 | mixed endings | `\r\n\n`, `\n\r\n` and lone `\r` separators |
| t23 | bad continuation | leading fold -> Err; whitespace-only fold is harmless |
| t24 | value whitespace | spaces/tabs after the colon trimmed |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 10. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.dotenv`/`xiom.properties` (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with
`xiom.string.builder.sb_to_str`) and documents these compiler-driven
choices:

- `Vec[StructType]` is unsupported, so the header list is two parallel
  homogeneous vectors (no `Vec[Header]`).
- `Ok`/`Err` for `Result[Email, Str]` are constructed only in the leaf
  helpers `_ok_email`/`_err_email`.
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); values are read into typed
  locals before use.
- Tests dispatch directly (`t1()` ... `t24()`); `Vec[fn]` indexed calls are
  not used, no match pattern binds `mut`, no inline lambdas, and every
  `match` is exhaustive.
- `eml_parse` and `eml_split_parts` own their scanning loops; the read-only
  API borrows `&Email`, and folding mutates the header vectors through
  `_consume_header_line(&mut Email, ...)`.

## 11. Known limitations

- No transfer decoding: base64, quoted-printable, uuencode and yenc payloads
  are returned verbatim.
- No address parsing (RFC 5322 mailboxes/groups), no date parsing, no MIME
  parameter decoding beyond `boundary`, no charset conversion.
- No nested multipart recursion: `eml_split_parts` returns the top level
  only; a `multipart/*` part must be parsed again by the caller.
- Delimiter recognition is exact: transport padding after `--<boundary>` is
  not accepted, and the boundary must be non-empty to produce parts.
- Header whitespace is normalized (leading/trailing OWS stripped; folds
  joined with one space); byte-exact header round-tripping is not preserved.
- Errors carry no line/column position (the offending line text is included).
