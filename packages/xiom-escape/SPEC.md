# xiom.escape -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.escape` (`src/escape.xi`). Pure XIOM, no FFI.

## 1. Scope

Seven free functions over `Str`:

```xi
pub fn escape_json_string(s: Str) -> Str
pub fn unescape_json_string(s: Str) -> Result[Str, Str]
pub fn escape_html(s: Str) -> Str
pub fn unescape_html(s: Str) -> Str
pub fn escape_url_component(s: Str) -> Str
pub fn unescape_url_component(s: Str) -> Result[Str, Str]
pub fn escape_shell_double(s: Str) -> Str
```

All scanning is byte-wise over the UTF-8 representation; multi-byte sequences
are never split or rewritten by the escaper, so non-ASCII input passes through
byte-exact wherever the rule set does not target it. Complexity is O(n) over
the input length for every function.

## 2. Non-goals

- Full JSON parsing/serialization (only string bodies).
- A complete HTML entity table (only the five named entities plus numeric
  references).
- Whole-URL encoding, IRI handling, or form (`+`-as-space) semantics.
- Shell quoting for single quotes, newlines or `!` history expansion.
- UTF-8 validation of arbitrary input bytes.
- Any FFI, file I/O, or registry integration.

## 3. JSON

### 3.1 `escape_json_string` mapping (exact)

| Input byte | Output |
|---|---|
| `"` (0x22) | `\"` |
| `\` (0x5C) | `\\` |
| 0x08 | `\b` |
| 0x0C | `\f` |
| 0x0A | `\n` |
| 0x0D | `\r` |
| 0x09 | `\t` |
| any other byte `< 0x20` | `\u00XX` with **uppercase** hex (e.g. 0x01 -> `\u0001`, 0x1F -> `\u001F`) |
| any other byte | copied verbatim |

`/` (0x2F) and DEL (0x7F) are **not** escaped: both are legal raw in JSON
string literals (RFC 8259). The function cannot fail and always returns a
single-quoted-agnostic JSON string body (no surrounding `"` are added).

### 3.2 `unescape_json_string` mapping (exact)

| Input | Output |
|---|---|
| `\"` | `"` (0x22) |
| `\\` | `\` (0x5C) |
| `\/` | `/` (0x2F) |
| `\b` | 0x08 |
| `\f` | 0x0C |
| `\n` | 0x0A |
| `\r` | 0x0D |
| `\t` | 0x09 |
| `\uXXXX` | UTF-8 encoding of code point `0xXXXX` (exactly 4 hex digits, case-insensitive; BMP only) |
| any other byte | copied verbatim |

Rules:

1. **BMP only.** `\uXXXX` decodes code points 0x0001..0xFFFF. Surrogate code
   points (0xD800..0xDFFF) are rejected; surrogate pairs are therefore not
   supported.
2. **NUL rejected.** `\u0000` is rejected (`Str` is a NUL-terminated buffer;
   an embedded NUL would corrupt length semantics).
3. **Single pass.** Unescaping never re-interprets produced characters, so
   `\\u0041` -> `\u0041` (verbatim text), not `A`.

### 3.3 JSON error catalog

`unescape_json_string` returns `Err(m)` on the **first** violation:

| Message | Trigger |
|---|---|
| `escape: trailing backslash` | input ends with an unpaired `\` |
| `escape: invalid escape sequence` | `\` followed by a byte outside `" \ / b f n r t u` |
| `escape: truncated unicode escape` | `\u` with fewer than four bytes remaining |
| `escape: invalid unicode escape` | four bytes present after `\u`, at least one is not a hex digit |
| `escape: null escape not supported` | `\u0000` |
| `escape: lone surrogate` | `\uD800`..`\uDFFF` |

`escape_json_string` has no error case.

## 4. HTML

### 4.1 `escape_html` mapping (exact)

| Input byte | Output |
|---|---|
| `&` | `&amp;` |
| `<` | `&lt;` |
| `>` | `&gt;` |
| `"` | `&quot;` |
| `'` | `&apos;` |
| any other byte | copied verbatim |

Escaping is single-pass: `&` is always written as the entity, so output can
never contain a raw metacharacter. `&apos;` (HTML5/XML named entity) is the
output form for `'`; the decoder accepts the numeric forms too.

### 4.2 `unescape_html` mapping (exact)

Recognized (`;`-terminated, searched within a 10-byte window after `&`, which
covers the longest reference `&#x10FFFF;`):

| Input | Output |
|---|---|
| `&amp;` | `&` |
| `&lt;` | `<` |
| `&gt;` | `>` |
| `&quot;` | `"` |
| `&apos;` | `'` |
| `&#NN;` | UTF-8 code point of the decimal value |
| `&#xHH;` / `&#XHH;` | UTF-8 code point of the hex value (digits and `x` case-insensitive) |

Rules:

1. **Single pass.** `&amp;lt;` -> `&lt;` (not `<`).
2. **Lenient.** Unknown names, bare `&`, missing `;`, empty digit runs
   (`&#;`, `&#x;`) and non-hex digits (`&#xZZ;`) pass through the `&`
   verbatim and scanning resumes at the next byte.
3. **Range.** Numeric values 0, surrogates (0xD800..0xDFFF) and values above
   0x10FFFF are not decoded (pass through verbatim); values above 0xFFFF
   encode to four UTF-8 bytes.
4. No HTML5 replacement-character behavior; no semicolon-less legacy
   references.
5. The function is infallible by design; there is no error channel.

## 5. URL

### 5.1 `escape_url_component` mapping (exact)

Byte-wise percent-encoding (RFC 3986 component semantics):

- **Unreserved** `A-Z a-z 0-9 - _ . ~` pass through unchanged.
- Every other byte is written as `%XX` with **uppercase** hex.
- Space (0x20) therefore becomes `%20` (never `+`).
- Non-ASCII bytes are encoded individually: `é` (UTF-8 `C3 A9`) ->
  `%C3%A9`; `✓` (`E2 9C 93`) -> `%E2%9C%93`.

The function cannot fail.

### 5.2 `unescape_url_component` mapping (exact)

- `%XX` is replaced by the byte `0xXX`; hex digits are case-insensitive
  (`%2f` = `%2F` = `/`).
- `+` is **not** a space; it passes through literally.
- All other bytes pass through.

Error catalog (first violation wins):

| Message | Trigger |
|---|---|
| `escape: truncated percent escape` | `%` with fewer than two bytes remaining |
| `escape: invalid percent escape` | `%` followed by two bytes, at least one not a hex digit |

No UTF-8 validation is performed on the decoded bytes.

## 6. Shell

### 6.1 `escape_shell_double` mapping (exact)

| Input byte | Output |
|---|---|
| `\` (0x5C) | `\\` |
| `"` (0x22) | `\"` |
| `$` (0x24) | `\$` |
| `` ` `` (0x60) | `` \` `` |
| any other byte | copied verbatim |

The result is safe for embedding inside a POSIX shell double-quoted string.
Newlines, `!` (history expansion) and single-quote contexts are out of scope;
the function cannot fail.

## 7. Test plan

`tests/test_conformance.xi` (module `escape_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | JSON quote/backslash | `"` -> `\"`, `\` -> `\\` |
| t2 | JSON short escapes | `\b \f \n \r \t` for 0x08/0x0C/0x0A/0x0D/0x09 |
| t3 | JSON control bytes | 0x01 -> `\u0001`, 0x1F -> `\u001F`; mixed with ASCII |
| t4 | JSON unescape | short escapes and full escape/unescape round trip |
| t5 | JSON `\u0041`, lowercase hex, `\/` | `A`, `a`, `/`, 5-byte short-escape run |
| t6 | JSON UTF-8 output | `\u2713` -> 3-byte `✓`; `\u00e9` -> `é` |
| t7 | JSON bad `\u` | truncated (`\u12`, `\u123`) and non-hex (`\uZZZZ`) => Err text |
| t8 | JSON error catalog | trailing backslash, `\q`, `\u0000`, `\ud800` |
| t9 | HTML escape | all five entities, plain text unchanged |
| t10 | HTML named unescape | five names; `&amp;lt;` single pass |
| t11 | HTML numeric | decimal, hex (both cases), 4-byte `&#128512;` |
| t12 | HTML round trip | mixed ASCII, quotes and UTF-8 |
| t13 | HTML leniency | bare `&`, unknown/malformed references verbatim |
| t14 | URL reserved | space, `/ ? = &` and the reserved set to `%XX` |
| t15 | URL unreserved/unicode | `Az09-_.~` passthrough; `é`, `✓` per UTF-8 byte |
| t16 | URL round trip | mixed string; lowercase hex; `+` literal |
| t17 | URL bad percent | truncated (`%2`, `abc%`) and invalid (`%GG`, `%2G`) |
| t18 | Shell escaping | `\ " $` + backtick; plain text unchanged |
| t19 | JSON control round trip | bytes 0x01..0x1F escape to `\u00XX`/short forms and round-trip |
| t20 | JSON passthrough | `/` and non-ASCII byte-exact, then round trip |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 8. Known limitations

- **BMP-only `\u`.** No surrogate-pair decoding; `\uD83D\uDE00` is rejected
  (`escape: lone surrogate`) rather than combined into U+1F600.
- **`\u0000` rejected** because `Str` is NUL-terminated.
- **JSON escape does not defend against `</script>`** (no `/` escaping) and
  leaves DEL raw; both are legal JSON.
- **HTML entity subset** is exactly `amp lt gt quot apos`, `&#NN;` and
  `&#xHH;`; no other named entities, no semicolon-less references, no
  replacement-character behavior. Decoding is lenient (infallible).
- **URL functions are component-level**: no whole-URL parsing, no `+`-as-space
  (form) mode, no UTF-8 validation of decoded bytes, no IRI/Unicode
  normalization.
- **Shell function is double-quote-only**: no single-quote escaping, no
  newline handling, no `!` history-expansion handling.
- Escape functions never validate their input; they transform bytes.

## 9. Compiler / stdlib notes

The implementation follows the proven v0.61.3 idioms:

- Free functions only; no methods, no lambdas, no `Vec[StructType]`,
  no `Vec[fn]` dispatch.
- Output bytes are accumulated in `Vec[UInt8]` and materialized with
  `xiom.string.builder.sb_to_str` (one allocation per result `Str`).
- `Ok`/`Err` for `Result[Str, Str]` are constructed only inside the leaf
  helpers `_ok_str`/`_err_str`; constructing Results directly inside other
  functions miscompiles in this compiler.
- `Str` equality uses `xiom.string.compare.str_compare` (BUG 17).
- Byte scanning uses `xiom.string.byte_at`, which returns raw bytes
  (round-14 semantics), so UTF-8 sequences are handled without decoding.
