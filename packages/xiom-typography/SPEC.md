# xiom.typography -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.typography` (`src/typography.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free text prettifier for in-memory `Str` values:

- convert straight ASCII quotes to typographic curly quotes
  (`typography_smart_quotes`),
- convert hyphen runs to en/em dashes (`typography_smart_dashes`),
- convert `...` to an ellipsis (`typography_ellipsis`),
- collapse runs of spaces/tabs (`typography_collapse_spaces`),
- apply all four in a fixed order (`typography_smart`).

## 2. Non-goals

- Locale-aware quoting or dash selection (no `xiom.locale` dependency).
- Language detection, grammar or sentence analysis.
- Markup awareness (code spans, URLs, HTML/XML attributes).
- Unicode normalization, validation or width handling.
- Streaming or incremental APIs; each function consumes a whole `Str`.
- Any FFI, file I/O, or registry integration.

## 3. Byte sequences

Every output character is a three-byte UTF-8 sequence beginning `E2 80`. The
implementation pushes these bytes explicitly through `xiom.string.builder`
(`sb_push_byte`), so the source does not depend on multi-byte string literals.

| Character | Code point | UTF-8 bytes |
|---|---|---|
| left single quotation mark | U+2018 | `E2 80 98` |
| right single quotation mark (apostrophe) | U+2019 | `E2 80 99` |
| left double quotation mark | U+201C | `E2 80 9C` |
| right double quotation mark | U+201D | `E2 80 9D` |
| en dash | U+2013 | `E2 80 93` |
| em dash | U+2014 | `E2 80 94` |
| horizontal ellipsis | U+2026 | `E2 80 A6` |

ASCII triggers (`0x00`-`0x7F`) can never occur as a byte inside a multi-byte
UTF-8 sequence (continuation bytes are `>= 0x80`), so scanning is byte-wise
and all non-trigger bytes are copied verbatim.

## 4. Rules

### 4.1 `typography_smart_quotes(s) -> Str`

Each ASCII `'` (0x27) and `"` (0x22) is replaced; every other byte is copied.

Quote direction context (checked on the byte(s) that precede the quote):

| Context preceding the quote | Direction | Emitted |
|---|---|---|
| start of string | opening | U+2018 / U+201C |
| space, tab, LF, CR | opening | U+2018 / U+201C |
| `(` `[` `{` `<` | opening | U+2018 / U+201C |
| ASCII hyphen `-` | opening | U+2018 / U+201C |
| converted en/em dash (`E2 80 93`/`E2 80 94`) | opening | U+2018 / U+201C |
| anything else (letters, digits, `)` `]` `}` `>` ...) | closing | U+2019 / U+201D |

The converted-dash context makes quote direction stable under
`typography_smart`, which runs dashes before quotes. There is **no pairing
state**: two quotes in a row like `""` both close (the second quote follows a
closing quote).

Consequences:

- `"don't"` => `don’t` (the apostrophe follows a letter, so it closes).
- `'twas` => `‘twas` (quote at start of string opens).
- `("x")` => `(“x”)`.

### 4.2 `typography_smart_dashes(s) -> Str`

Leftmost-longest scan over ASCII hyphens (0x2D):

1. if the next three bytes are `---`, emit em dash U+2014 and advance 3;
2. else if the next two bytes are `--`, emit en dash U+2013 and advance 2;
3. else copy the byte.

Examples: `a--b` => `a–b`; `a---b` => `a—b`; `a---b--c` => `a—b–c`;
`a----b` => `a—-b` (em dash followed by the leftover hyphen); a single `-` is
untouched.

### 4.3 `typography_ellipsis(s) -> Str`

Leftmost-first scan over ASCII dots (0x2E): three consecutive dots emit
U+2026 and consume 3; otherwise the dot is copied. `wait...` => `wait…`;
`a...b...c` => `a…b…c`; `a....` => `a….` (ellipsis + one literal dot).

### 4.4 `typography_collapse_spaces(s) -> Str`

Every maximal run of bytes in {space (0x20), tab (0x09)} is replaced by one
space (0x20). LF (0x0A) and CR (0x0D) are not consumed by a run and are
preserved verbatim, so line structure survives. Nothing is trimmed:
`"  x  "` => `" x "`. Examples: `"a   b"` => `"a b"`; `"a\t\tb"` => `"a b"`;
`"a  \n \t b"` => `"a \n b"`.

### 4.5 `typography_smart(s) -> Str`

Fixed pipeline, in this order:

```
s -> typography_ellipsis
  -> typography_smart_dashes
  -> typography_smart_quotes
  -> typography_collapse_spaces
```

Order rationale: dashes before quotes so a quote after a converted dash still
opens; collapsing last so quote decisions see the original spacing; ellipsis
first because it only looks at dots. Example:

```
"\"Well...\"  --  it's  \"fine\"  now"
  => "“Well…” – it’s “fine” now"
```

## 5. API signatures

```xi
pub fn typography_smart_quotes(s: Str) -> Str
pub fn typography_smart_dashes(s: Str) -> Str
pub fn typography_ellipsis(s: Str) -> Str
pub fn typography_collapse_spaces(s: Str) -> Str
pub fn typography_smart(s: Str) -> Str
```

All functions are total (no `Result`), allocate once for the output, and are
O(n) over the input bytes.

## 6. Test plan

`tests/test_conformance.xi` (module `typography_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Every string comparison goes through
`xiom.string.compare`'s `str_compare`, and the expected literals contain the
actual UTF-8 punctuation characters.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | double quotes around a word | open at start + close at end |
| t2 | double quote at string start | start-of-string opens |
| t3 | double quote at string end | closes after a letter |
| t4 | `don't` | single quote inside a word is an apostrophe |
| t5 | `say 'hi'` | opens after whitespace, closes after a word |
| t6 | `("x")` | opens after an opening bracket |
| t7 | `-'hi'` | opens after an ASCII dash |
| t8 | dash then quote | opens after a converted en dash |
| t9 | mixed quotes | single and double resolved independently |
| t10 | `a---b` | triple hyphen => em dash |
| t11 | `a--b` | double hyphen => en dash |
| t12 | `a---b--c` | longest match first (rule 4.2) |
| t13 | `wait...` | ellipsis conversion |
| t14 | `a...b...c`, `a....` | multiple ellipses; extra dot stays (rule 4.3) |
| t15 | spaces and tabs | mixed runs collapse to one space (rule 4.4) |
| t16 | newline preservation | LF/CR are not part of a run (rule 4.4) |
| t17 | leading/trailing runs | collapse trims nothing (rule 4.4) |
| t18 | full pipeline | typography_smart order and combined output (rule 4.5) |
| t19 | plain text | no triggers => byte-identical output |
| t20 | start/end single quotes | direction by context (rule 4.1) |

## 7. Known limitations

- The quote heuristic is a preceding-byte rule with no pairing state; see
  README.md "Limitations" (ASCII quote detection heuristics, no locale
  awareness).
- No Unicode normalization: input bytes that are not ASCII triggers are
  untouched, including pre-existing curly quotes and invalid UTF-8.
- No markup awareness: URLs, code spans and HTML attributes are converted
  like prose.
- `typography_collapse_spaces` collapses alignment whitespace as well.

## 8. Compiler / stdlib notes

One compiler workaround is required on v0.61.3: a direct `UInt8` comparison of
a `xiom.string.byte_at` result misses bytes `>= 128` (e.g.
`string.byte_at(s, 0) == 226u8` is false for a leading `0xE2`). The module
therefore normalizes every byte read with
`(string.byte_at(s, i) as Int) & 0xFF` and compares `Int` values -- the idiom
proven throughout the stdlib (e.g. `xiom.encoding.punycode`). Output is
pushed as `UInt8` via `as UInt8` casts, which is byte-exact (verified by t8
and t18). The rest is plain stdlib usage: byte scanning with
`xiom.string.byte_at`, single-allocation output through `xiom.string.builder`
(`sb_new` / `sb_push_byte` / `sb_to_str`), and typed constants.

The suite routes every string comparison through `str_compare` (BUG 17: `==`
on `Str` values read from `Vec[Str]` elements is a pointer comparison), and it
avoids the non-exhaustive-`match` and inline-lambda restrictions by using
explicit per-test functions and `if`/`elif` dispatch.
