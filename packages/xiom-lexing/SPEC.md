# xiom.lexing -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.lexing` (`src/lexing.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, configuration-driven lexer for source-like text held in a `Str`:

- a `Lexer` value holding registered keywords and operators,
- `lexer_scan` producing a `TokenList` of tokens in source order,
- read-only accessors for token count, kind, text and byte offset.

`Str` is treated as a UTF-8 byte buffer; all scanning is byte-wise. A token's
text is always a slice of the input except for `"str"` tokens, whose escapes
are decoded (decoding only produces ASCII bytes, so the result stays valid
UTF-8).

## 2. Non-goals

- Regex or a rule DSL; the keyword and operator sets are the whole
  configuration.
- Float, character, bool or comment literals; no `\uXXXX`/numeric escapes.
- Unicode identifiers, Unicode escape/identifier normalization, or
  case-insensitive matching.
- Error recovery: the first bad byte or bad escape aborts the scan with an
  `Err` that carries the byte position.
- Streaming/incremental scanning, token re-scanning, or AST construction.

## 3. Token grammar and semantics

Informal grammar (whitespace is skipped between tokens):

```
document   = *token
token      = keyword | ident | int | string | operator
keyword    = ident-text registered with lexer_add_keyword
ident      = ident-start *ident-byte
ident-start= "A".."Z" | "a".."z" | "_"
ident-byte = ident-start | "0".."9"
int        = 1*("0".."9")
string     = '"' *( escape | any-byte-except-QUOTE-and-BACKSLASH ) '"'
escape     = "\" QUOTE | "\\" | "\n" | "\t"        (source spellings)
operator   = longest registered operator matching at the position
```

Decisions (each one is covered by the conformance suite):

1. **Priority.** At each position the scanner tries, in order: whitespace,
   identifier/keyword, integer, string, operator. A `"` always starts a
   string (registering `"` as an operator does not change that), and `\` or
   `"` may not be identifiers/operators through configuration.
2. **Identifiers.** A maximal run of `[A-Za-z_][A-Za-z0-9_]*`. The run is
   classified `"kw"` when its exact text equals a registered keyword
   (case-sensitive, first match wins), else `"ident"`. `"letx"` and `"Let"`
   are idents when only `"let"` is registered.
3. **Integers.** A maximal run of `[0-9]+`, kept verbatim (leading zeros
   preserved, no sign, no decimal point). Digits may follow an identifier:
   `"a1b2"` is one ident; `"1a"` is int `1` then ident `a`.
4. **Strings.** Open with `"`, close with the next unescaped `"`; every byte
   between is kept verbatim except backslash escapes (table in section 4).
   Raw bytes may include spaces, operator characters, tabs and LF. The text
   of an empty literal `""` is `""` with kind `"str"`.
5. **Operators.** For each operator registered with `lexer_add_operator`, the
   longest one whose text matches at the position wins; ties are won by the
   earliest registered operator. An empty operator string never matches, and
   only registered operators match: an unregistered operator byte is an
   "unexpected byte" error.
6. **Whitespace.** Space, tab, LF and CR are skipped; they produce no tokens.
   Empty or whitespace-only input yields an empty token list.
7. **Offsets.** `starts[i]` is the byte offset of token `i`'s first byte in
   the scanned input (`0`-based). Offsets are byte offsets, not character
   offsets.
8. **Out-of-range accessors.** `lexer_kind` and `lexer_text` return `""` and
   `lexer_start` returns `-1` for any `i < 0` or `i >= token_count`.
9. **Errors.** The scanner stops at the first error and returns `Err` with
   one of the section-5 messages (which always include the offending byte
   position). Tokens scanned before the error are discarded.
10. **Determinism.** Scanning the same text with the same configuration
    yields the same tokens, positions and errors; the input is never mutated.

## 4. Escape table

Inside a `"..."` string, a backslash starts an escape. Only these four are
defined:

| Source | Decoded byte | Notes |
|---|---|---|
| `\"` | `"` (0x22) | quote does not close the string |
| `\\` | `\` (0x5C) | literal backslash |
| `\n` | LF (0x0A) | line feed |
| `\t` | TAB (0x09) | tab |

Any other backslash sequence is `Err("lexing: invalid escape at <pos>")`
where `<pos>` is the offset of the backslash. A backslash as the last byte of
the input is the unterminated-string error. A raw LF inside a string is
allowed and kept verbatim (only `\n` is the documented line-feed spelling, but
raw bytes pass through).

## 5. Error catalog

| Message | Condition | Position reported |
|---|---|---|
| `lexing: unexpected byte at <pos>` | the byte at `<pos>` starts no token (an unregistered operator, punctuation, a stray backslash outside a string, ...) | the byte itself |
| `lexing: unterminated string at <pos>` | no closing unescaped `"` before end of input (including a trailing backslash) | the opening quote |
| `lexing: invalid escape at <pos>` | a backslash followed by a byte other than `"`, `\`, `n`, `t` inside a string | the backslash |

Messages are fixed: `lexing: ` + text + ` at ` + decimal position, built with
`xiom.convert.int_to_string`.

## 6. API signatures

```xi
pub type TokenList = { kinds: Vec[Str]; texts: Vec[Str]; starts: Vec[Int]; }
pub type Lexer = { keywords: Vec[Str]; operators: Vec[Str]; }

pub fn lexer_new() -> Lexer
pub fn lexer_add_keyword(l: &mut Lexer, word: Str)
pub fn lexer_add_operator(l: &mut Lexer, op: Str)
pub fn lexer_scan(l: &Lexer, text: Str) -> Result[TokenList, Str]
pub fn lexer_token_count(t: &TokenList) -> Int
pub fn lexer_kind(t: &TokenList, i: Int) -> Str
pub fn lexer_text(t: &TokenList, i: Int) -> Str
pub fn lexer_start(t: &TokenList, i: Int) -> Int
```

`TokenList` uses three parallel arrays because the compiler cannot hold
`Vec[StructType]`. Complexity: `lexer_scan` is O(n) over the input bytes plus
one keyword lookup and one operator match attempt per token position
(O(n * (|keywords| + |operators|)) worst case, with each operator match
bounded by the longest operator length); the accessors are O(1).

## 7. Test plan

`tests/test_conformance.xi` (module `lexing_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | identifiers | basic `[A-Za-z_][A-Za-z0-9_]*` runs (rule 2) |
| t2 | keywords vs idents | exact text is kw, other words are idents (rule 2) |
| t3 | two keywords | `let if letx Let`: order, case-sensitivity, prefixes (rule 2) |
| t4 | integers | `0 42 007 1234567890` verbatim (rule 3) |
| t5 | strings: escaped quotes | `\"` decodes to `"` (section 4) |
| t6 | strings: `\\`, `\n`, `\t` | backslash, LF and TAB decoding (section 4) |
| t7 | strings: empty/whitespace-only | `""` and `"  "` (rule 4) |
| t8 | operators: `==` vs `=` | longest match wins (rule 5) |
| t9 | operators: `->` vs `-` | longest match wins (rule 5) |
| t10 | operator-only input | `==->-+*` splits by longest match (rule 5) |
| t11 | mixed expression | kinds, texts and byte starts for 6 tokens (rules 1-3, 7) |
| t12 | whitespace | space, tab, LF, CR skipped (rule 6) |
| t13 | unexpected byte | `a @b` and `$` error with position (rule 9, section 5) |
| t14 | empty input | `""`, `"   "`, `"\n\t\r "` yield no tokens (rule 6) |
| t15 | out-of-range accessors | `""` / `-1` for negative and beyond-end indices (rule 8) |
| t16 | underscores | `_x __ _9 x_` are idents (rule 2) |
| t17 | digits | `a1b2 1a x9`: interior digits stay in idents (rule 3) |
| t18 | repeated scans | identical tokens and errors on re-scan (rule 10) |
| t19 | unterminated string | open-quote position for `"abc` and `a "b` (section 5) |
| t20 | invalid escape | `\q` reports the backslash offset (section 4-5) |
| t21 | operator chars in strings | `"= +"` is one `"str"`, quotes win over ops (rule 1) |
| t22 | accessors on valid tokens | kind/text/start for all 4 tokens of `let x = 7` |
| t23 | unregistered operator | `=` with no operators registered errors (rule 5) |
| t24 | keyword exactness | `lets letter let` only classifies the last as kw (rule 2) |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison); the helpers `scan_is`, `scan_err_is` and
`scan_starts_is` compare whole results field by field.

## 8. Known limitations

- Fixed token classes and a fixed priority order; the only configuration is
  the keyword and operator sets.
- No regex, no comment syntax, no float/char/bool literals, no `\uXXXX` or
  numeric escapes.
- Identifiers are ASCII-only; a non-ASCII byte outside a string is an
  "unexpected byte" error.
- Errors are first-failure only: no panic-free recovery and no partial token
  streams on `Err`.
- Byte offsets only (no line/column tracking); no streaming or resumable
  scanning.
- Operator matching compares slices, so registering many long operators
  costs O(|operators| * longest-operator-length) per position.

## 9. Compiler / stdlib notes

XIOM v0.61.3 workarounds used (same shape as the other ported packages):

- Free functions only; no methods on `TokenList`/`Lexer`.
- No `Vec[StructType]`: `TokenList` is three parallel `Vec`s.
- `Ok`/`Err` construction lives only in the leaf helpers `_ok_tokens` /
  `_err_tokens` (direct construction in other shapes miscompiles).
- `Str` values read from `Vec[Str]` elements are compared with
  `xiom.string.compare.str_compare` (BUG 17).
- `Vec[Int]` reads use a typed `let s: Int = t.starts[i];`.
- Strings are materialized from a `Vec[UInt8]` buffer with `Str::from_utf8`
  (the `xiom.serialize.csv` idiom).
- No `Ok`/`Err`-returning fn takes or returns a struct by value other than
  through the leaf helpers; `lexer_scan` builds the `TokenList` and passes it
  to `_ok_tokens`.
