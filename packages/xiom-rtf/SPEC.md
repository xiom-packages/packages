# xiom.rtf -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.rtf`, version `0.1.0`).
Module: `src/rtf.xi` (`module xiom.rtf`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.string.compare`, `xiom.convert`).

## 1. Scope

A pure-XIOM (no FFI) codec for a documented RTF subset:

- `rtf_parse(text)` -- strict tokenizer producing a flat token stream;
- `rtf_plain_text(tokens)` -- visible-text extraction;
- `rtf_emit(tokens)` -- canonical RTF writer (single-space normalization,
  lowercase hex, `\uN ?` canonical fallback);
- accessors over the parallel token vectors (`rtf_token_count`, `rtf_kind`,
  `rtf_text`, `rtf_param`, `rtf_has_param`, `rtf_depth`, `rtf_hex_value`,
  `rtf_no_param`).

The token stream is flat: four parallel `Vec`s (`kinds`, `texts`, `params`,
`depth`) because XIOM v0.61.3 cannot hold `Vec[StructType]`. There is no
renderer, no DOM and no group tree.

## 2. Non-goals

- Font, color and stylesheet tables: `\fonttbl`, `\colortbl`, `\stylesheet`
  and friends are ordinary control-word tokens; they are never interpreted,
  rewritten or skipped. No default-font/color resolution.
- Rendering, layout, character-set or code-page interpretation: `\'hh` is a
  raw byte, never converted to a Unicode character.
- RTF 1.9+ destination semantics: `\*` destinations are not recognized; a
  `\*` control symbol is a bad-control-word error.
- Control symbols outside `\\`, `\{`, `\}` (`\~`, `\-`, `\_`, `\|`, `\:`,
  ...) are errors, not pass-through tokens.
- Images, objects, fields, bookmarks, footnotes and other destinations are
  not interpreted (their control words remain ordinary tokens).
- Malformed-document recovery: the parser stops at the first error.
- Streaming/incremental parsing: the whole document is one `Str`.

## 3. Token model

`RtfTokens` has four parallel vectors of equal length (a stream produced by
`rtf_parse`). Token `i`:

| Field | Meaning |
|---|---|
| `kinds[i]` | one of the seven kind strings below |
| `texts[i]` | per-kind text (table below) |
| `params[i]` | numeric value; the sentinel `-2147483649` when absent |
| `depth[i]` | number of groups enclosing the token |

Kinds and fields:

| Kind | `texts[i]` | `params[i]` |
|---|---|---|
| `group_open` | `""` | sentinel |
| `group_close` | `""` | sentinel |
| `control` | control word name, no backslash | signed 32-bit parameter, or sentinel |
| `symbol` | `\`, `{` or `}` | sentinel |
| `hex` | the two hex digits, lowercase | raw byte value 0..255 |
| `unicode` | UTF-8 encoding of the code unit; `""` for code unit 0 | code unit 0..65535 (after negative adjustment) |
| `text` | run bytes, CRLF already normalized | sentinel |

Depth rule: a token's depth is the number of groups enclosing it. A
`group_open` carries the depth *before* it opens (the outermost `{` has
depth 0), a `group_close` carries the depth *of the group it closes*, and
every other token carries its group's depth. Example for `{\rtf1{a}}`:

```
0 group_open  ""      d0
1 control     "rtf"   d1  p1
2 group_open  ""      d1
3 text        "a"     d2
4 group_close ""      d2
5 group_close ""      d1
```

The sentinel `rtf_no_param()` = `-2147483649` is one below the smallest
legal parameter, so no parsed parameter can collide with it.

## 4. Grammar

### 4.1 Document

Input is exactly one outermost group whose first six bytes are the literal
`{\rtf1`:

```
document = "{\rtf1" inner "}"
```

The byte prefix is checked first; then the stream is tokenized; then
tokens[1] must be `control "rtf"` with parameter exactly `1`. Nothing may
precede the prefix and nothing may follow the outer `}`.

### 4.2 Groups

`{` opens a group, `}` closes it; groups nest. Braces are only structural:
they are `group_open`/`group_close` tokens and contribute nothing to plain
text. Literal braces require `\{` or `\}`.

### 4.3 Control words

```
control-word = "\" letter{1,32} [ number ] [ " " ]
number       = [ "-" ] digit{1,10}
```

- The name is a maximal run of ASCII letters; at most 32 letters.
- A parameter must immediately follow the name: `\li-360`, `\sb120`.
- One optional single space after the control word is a delimiter and is
  consumed: `\b x` is control `b` then text `x`.
- A parameter must fit the signed 32-bit range
  `[-2147483648, 2147483647]`; otherwise the parse fails with a numeric
  overflow error.
- `\u` is special (section 4.5); any other name, including `\rtf`, is an
  ordinary `control` token.
- A backslash at end of input, a backslash followed by a non-letter that is
  not one of `\\`, `\{`, `\}`, `\'` or a letter, and a name longer than 32
  letters are bad-control-word errors.

### 4.4 Control symbols and hex escapes

| Source | Token | Meaning |
|---|---|---|
| `\\` | `symbol` text `\` | a literal backslash |
| `\{` | `symbol` text `{` | a literal left brace |
| `\}` | `symbol` text `}` | a literal right brace |
| `\'hh` | `hex`, text `hh` lowercase, param the byte value | one raw byte |

`hh` must be exactly two hex digits (either case, stored lowercase);
anything else is a bad-hex-escape error.

### 4.5 Unicode escapes

```
unicode-escape = "\u" number [ fallback ]
```

- The parameter is a signed 16-bit RTF value; after parsing it must be in
  `[-32768, 32767]`, otherwise it is out of range. A value outside
  `[-32768, 32767]` but inside the signed 32-bit range is a unicode
  value-out-of-range error, not a numeric overflow.
- A negative value `N` denotes the code unit `N + 65536`; `params[i]`
  stores the adjusted code unit in `0..65535`.
- `texts[i]` is the UTF-8 encoding of that code unit: 1..3 bytes. Code units
  in `0xD800..0xDFFF` (surrogates) keep their 3-byte form (CESU-8); the
  token stream never combines pairs.
- **Fallback rule.** After the control word and its optional one-space
  delimiter, one fallback byte is consumed and discarded when the next byte
  exists and is not `\`, `{` or `}`. The fallback is optional: `\u65}`,
  `\u65\b` and end-of-input all parse without one. When present it is one
  byte (commonly `?`), so `\u65?` and `\u65 ?` both yield one `unicode`
  token; `\u65  x` consumes the second space as the fallback and then reads
  text `x`.
- A `\u` with no numeric parameter is a truncated-unicode-escape error.

### 4.6 Text runs

Everything that is not `{`, `}`, `\` or a control escape is a `text` token.
Runs are maximal. CRLF (`\r\n`) and lone CR (`\r`) are normalized to LF
(`\n`) inside text; plain LF passes through. Text bytes other than CR are
kept raw (no decoding).

## 5. Error catalog

Errors are `Err(Str)` messages of the form `"rtf: <what> at <pos>"`. The
parser reports the first error in scan order. For control-level errors,
`<pos>` is the offset of the introducing backslash.

| Message | Cause |
|---|---|
| `rtf: text before document start at <pos>` | the input does not start with the six bytes `{\rtf1`; `<pos>` is the first differing offset (0 for empty input, 5 for `{\rtf2`) |
| `rtf: bad document start at 1` | the prefix matches but the `\rtf` token is not `rtf` with parameter exactly 1 (e.g. `{\rtf12`) |
| `rtf: unbalanced braces at <pos>` | `}` with no open group (`<pos>` = that `}`) or end of input with open groups (`<pos>` = outermost still-open `{`) |
| `rtf: trailing bytes after document end at <pos>` | any byte after the closing brace of the outermost group |
| `rtf: bad control word at <pos>` | lone trailing backslash, backslash + non-letter outside `\\ \{ \} \'`, or a name over 32 letters |
| `rtf: bad hex escape at <pos>` | `\'` not followed by exactly two hex digits |
| `rtf: numeric overflow at <pos>` | parameter outside the signed 32-bit range (or more than 10 digits) |
| `rtf: truncated unicode escape at <pos>` | `\u` with no numeric parameter |
| `rtf: unicode value out of range at <pos>` | `\u` parameter outside `[-32768, 32767]` |

Precedence: the six-byte prefix check runs first, then tokenization (whose
errors are reported in scan order), then the `\rtf1` token check. So
`x{\rtf1}y` reports text-before-start at 0, and a bad control word inside
the body is reported before any document-start token check.

## 6. Canonical emitter

`rtf_emit(tokens)` writes a deterministic canonical form:

1. `{` and `}` for group tokens.
2. A control word writes `\` + name, then its parameter when present
   (decimal, sign included), then exactly one space. The trailing space is
   always written, so a following text/digit run cannot merge with the
   control word.
3. A symbol writes `\\`, `\{` or `\}` according to its text.
4. A hex token writes `\'` + its text (already lowercase).
5. A unicode token writes `\u` + the signed form of the code unit + ` ?`.
   The signed form is `cu` when `cu < 32768`, else `cu - 65536`.
6. A text token is written byte-exact except that `\`, `{` and `}` are
   backslash-escaped, so arbitrary text re-parses to the same `text` token.

Properties (for any stream produced by `rtf_parse`):

- **Round-trip:** `rtf_parse(rtf_emit(t))` yields a token stream equal to
  `t` in count, kind, text, parameter and depth for every token.
- **Idempotence:** `rtf_emit(rtf_parse(rtf_emit(t))) == rtf_emit(t)`.

The emitter assumes well-formed parallel vectors (as produced by
`rtf_parse`); hand-built mismatched vectors are unsupported.

## 7. Plain-text extraction

`rtf_plain_text(tokens)` concatenates, in token order: every `text` token,
every `symbol` token (its `\`, `{` or `}`), every `hex` token with value
`1..255` (value 0 is skipped: a NUL cannot live in a `Str`), and every
`unicode` token. Control words and group tokens contribute nothing.

Surrogate handling: an adjacent `unicode` high surrogate
(`0xD800..0xDBFF`) followed immediately (no intervening token) by a
`unicode` low surrogate (`0xDC00..0xDFFF`) is combined into one 4-byte
UTF-8 character; any other surrogate code unit is written as its 3-byte
form. Code unit 0 contributes nothing.

## 8. API signatures

```xi
pub type RtfTokens = {
  kinds: Vec[Str];
  texts: Vec[Str];
  params: Vec[Int];
  depth: Vec[Int];
}

pub fn rtf_parse(text: Str) -> Result[RtfTokens, Str]
pub fn rtf_emit(tokens: &RtfTokens) -> Str
pub fn rtf_plain_text(tokens: &RtfTokens) -> Str

pub fn rtf_no_param() -> Int
pub fn rtf_token_count(tokens: &RtfTokens) -> Int
pub fn rtf_kind(tokens: &RtfTokens, i: Int) -> Str
pub fn rtf_text(tokens: &RtfTokens, i: Int) -> Str
pub fn rtf_param(tokens: &RtfTokens, i: Int) -> Int
pub fn rtf_has_param(tokens: &RtfTokens, i: Int) -> Bool
pub fn rtf_depth(tokens: &RtfTokens, i: Int) -> Int
pub fn rtf_hex_value(tokens: &RtfTokens, i: Int) -> Int
```

Complexity: `rtf_parse` is O(n) over the input; `rtf_emit` and
`rtf_plain_text` are O(total stored text); all accessors are O(1).

## 9. Examples

| Source | Tokens (kind text param depth) | Plain text |
|---|---|---|
| `{\rtf1}` | `group_open d0`, `control rtf p1 d1`, `group_close d1` | `""` |
| `{\rtf1\ansi\deff0}` | + `control ansi d1`, `control deff p0 d1` | `""` |
| `{\rtf1 a\\b}` | + `text "a" d1`, `symbol "\" d1`, `text "b" d1` | `a\b` |
| `{\rtf1\'41\'2e}` | + `hex 41 p65`, `hex 2e p46` | `A.` |
| `{\rtf1\u65?}` | + `unicode "A" p65` | `A` |
| `{\rtf1\u8364?}` | + `unicode` text `E2 82 AC` p8364 | `€` |
| `{\rtf1\u-10179\u-8704?}` | + two `unicode` tokens, p55357 and p56832 | one 4-byte `U+1F600` |
| `{\rtf1 a\r\nb}` | + `text "a\nb"` | `a\nb` |
| `{\rtf1\li-360}` | + `control li p-360` | `""` |

Canonical emission of the second row is `{\rtf1 \ansi \deff0 }`; of
`{\rtf1\u65? Hi}` it is `{\rtf1 \u65 ? Hi}`.

## 10. Test plan

`tests/test_conformance.xi` (`module rtf_tests`, 26 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | document start | `{\rtf1}` token kinds, texts, param and depths |
| t2 | control words | optional parameters and `rtf_has_param` |
| t3 | parameters | signed and multi-digit values |
| t4 | control symbols | `\\`, `\{`, `\}` as literal text |
| t5 | nesting | depth of opens, contents and closes |
| t6 | hex escapes | byte tokens, `rtf_hex_value`, plain text |
| t7 | hex case | both cases accepted, stored lowercase |
| t8 | unicode | `\u65?` is `A`; `\u8364?` is 3-byte UTF-8 |
| t9 | surrogates | negatives add 65536; plain text joins a pair |
| t10 | fallback | absent, control-adjacent and one-byte fallbacks |
| t11 | text runs | CRLF and lone CR become LF |
| t12 | start errors | text before start, wrong version, wrong `\rtf` param |
| t13 | brace errors | unclosed and trailing bytes |
| t14 | control-word errors | non-letters, EOF, 33-letter names (32 ok) |
| t15 | numeric bounds | 32-bit limits and overflow |
| t16 | truncated `\u` | missing parameter is an error |
| t17 | bad hex | non-hex and short pairs |
| t18 | unicode range | `32768`, `99999`, `-32769` rejected; `-32768` ok |
| t19 | accessors | out-of-range results and the sentinel |
| t20 | emitter | spaces, lowercase hex, signed `\u` + `?` |
| t21 | round-trip | parse -> emit -> parse token-identical, emit idempotent |
| t22 | plain text | text + hex + unicode + symbols, controls excluded |
| t23 | empty groups | empty document and nested empty group depths |
| t24 | code unit 0 | empty text, skipped plain text, `\u0 ?` round-trips |
| t25 | `\'00` | byte value 0 kept, plain text skips the NUL |
| t26 | fallback braces | `{`/`}` after `\u` are not fallback bytes |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.rtf
```

Last verified: compiler 0.61.3,
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## 11. Compiler / stdlib notes for v0.61.3

- Free functions only; no methods, lambdas or generics; no
  `Vec[StructType]` (the four parallel vectors stand in for a token list).
- `Ok`/`Err` are constructed only in the leaf helpers `_ok_rtf`, `_err_rtf`,
  `_ok_int` and `_err_int`.
- All `Str` equality goes through `xiom.string.compare.str_compare`, never
  `==` (BUG 17), and values read from `Vec[Str]` elements are first bound to
  typed locals.
- Bytes are read as `Int` through `_byte()` with a `0xFF` mask, so no
  `UInt8` widening participates in a comparison.
- Builders are `Vec[UInt8]` materialized with
  `xiom.string.builder.sb_to_str`; no `0x00` byte is ever pushed (the
  resulting `Str` is NUL-terminated).
- The package declares no `extern "C"` blocks (no FFI) and no extra
  dependencies.

## 12. Known limitations

- The subset is fixed: anything outside it is an error, never a lenient
  pass-through, with the two documented exceptions (`\'00` and `\u0` keep
  their value but contribute no plain-text byte).
- No code-page or charset interpretation of `\'hh`; no `\ansicpg` handling.
- No destination skipping: a `{\*\generator ...}` group would be tokenized,
  but `\*` itself is currently a bad-control-word error.
- Tables (`\fonttbl`, `\colortbl`, ...) are tokens only; nothing is
  validated about their contents.
- No RTF 1.9+ semantics (no `\upr`, no math zones, no theme data).
- `rtf_parse` consumes a whole `Str`; no streaming API.
- Surrogate pairs are only combined by `rtf_plain_text`; the token stream
  keeps code units, and `rtf_text` of a surrogate is its 3-byte form.
