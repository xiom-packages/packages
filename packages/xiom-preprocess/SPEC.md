# xiom.preprocess -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.preprocess` (`src/preprocess.xi`). Pure XIOM, no FFI.

## 1. Scope

A configurable, infallible text-normalization pipeline over UTF-8 `Str`
values, ASCII-oriented and byte-wise:

- case folding: `pp_fold_ascii`,
- punctuation stripping: `pp_strip_punct`,
- whitespace collapsing: `pp_collapse_ws`,
- stopword removal: `pp_remove_stopwords`,
- word counting: `pp_word_count`,
- composition: `pp_pipeline`, `pp_normalize_default`.

Every function returns `Str` (or `Int`) and never reports an error; no output
is validated.

## 2. Non-goals

- Unicode case folding or normalization (no NFC/NFD/NFKC, no `ß -> ss`); only
  ASCII `A-Z -> a-z`.
- Linguistic tokenization (sentence boundaries, hyphenation, contraction
  handling); whitespace splitting only -- see `xiom.tokenizer`.
- Stemming / lemmatization -- see `xiom.stemming` / `xiom.lemmatization` for
  those concerns.
- Language-specific stopword lists, corpus statistics, TF-IDF.
- Validation, error reporting, or presence of `Result`.
- Any FFI, file I/O, or registry integration.

## 3. Shared model

1. **Encoding.** `Str` is treated as a UTF-8 byte buffer; all scanning is
   byte-wise via `xiom.string.byte_at`. Bytes are passed, dropped or shifted;
   no multi-byte sequence is rewritten, so non-ASCII bytes survive intact
   except where a dropping rule removes them.
2. **Byte classes.**
   - ASCII letter: `0x41-0x5A` (upper) or `0x61-0x7A` (lower).
   - ASCII digit: `0x30-0x39`.
   - Whitespace (this module): space (`0x20`), TAB (`0x09`), LF (`0x0A`),
     CR (`0x0D`) -- the four bytes the pipeline treats as word separators.
3. **Non-ASCII.** Folding and collapsing pass bytes >= `0x80` through
   unchanged; `pp_strip_punct` and `pp_remove_stopwords`-driven splits treat
   them as non-space bytes (kept or part of tokens).
4. **Infallible.** The empty string is valid input everywhere; empty output
   is always a legal result.
5. **Str comparison rule.** Stopword matching is done with
   `xiom.string.compare.str_compare` on folded copies; `==` is never used on
   `Str` read from `Vec[Str]` (BUG 17: it lowers to a pointer comparison).

## 4. Step semantics

### 4.1 `pp_fold_ascii(s) -> Str` (step "fold")

| Input byte | Output |
|---|---|
| `0x41-0x5A` | the byte plus `0x20` (lowercase) |
| every other byte, incl. `>= 0x80` | the byte itself |

Length-preserving and idempotent. No locale rules: `"Ä"` stays `"Ä"`.

Worked examples: `"HELLO World 123"` -> `"hello world 123"`;
`"café ÄÖÜ"` -> `"café ÄÖÜ"`.

### 4.2 `pp_strip_punct(s) -> Str` (step "punct")

| Input byte | Output |
|---|---|
| `0x41-0x5A`, `0x61-0x7A`, `0x30-0x39`, `0x20` | the byte itself |
| everything else (marks, `_`, TAB, LF, CR, `>= 0x80`) | dropped |

Dropping is deletion, not replacement: `"a-b"` -> `"ab"`;
`"Order #42: $19.99!"` -> `"Order 42 1999"`; `"a\tb\nc"` -> `"abc"`.

### 4.3 `pp_collapse_ws(s) -> Str` (step "ws")

Single left-to-right pass with a pending-run flag; whitespace = space, TAB,
LF or CR.

| Situation | Output |
|---|---|
| maximal whitespace run between two kept bytes | one space (`0x20`) |
| whitespace run at the start or end | dropped (trim) |
| every other byte (incl. `>= 0x80`) | emitted unchanged |

The result is `""` or a string that starts and ends with a non-whitespace
byte and has no two adjacent whitespace bytes, so `pp_collapse_ws` is
idempotent. `"  a   b\t\tc \r\n d  "` -> `"a b c d"`.

### 4.4 `pp_remove_stopwords(s, stop) -> Str` (step "stopwords")

1. **Pre-fold the stop list.** For every element of `stop` (read into a typed
   local), the folded copy is computed with `pp_fold_ascii`.
2. **Split.** Tokens are maximal runs of non-whitespace bytes (the 4-byte
   whitespace class of 3.2). Tokens are never empty.
3. **Match.** A token is dropped when `str_compare(fold(token), fold(stop_k))
   == 0` for some `k` -- case-insensitive, exact, never substring. Kept
   tokens retain their original bytes.
4. **Join.** Kept tokens are joined with a single space and nothing else, so
   the output is also whitespace-normalized.

Empty input, an empty stop list and empty entries in the stop list remove
nothing (`""` never equals a non-empty token). `"the"` does not remove
`"theater"`; `"The"` and `"THE"` do match `"the"`; non-ASCII stopwords match
byte-exact (`"Ä"` matches `"Ä"`, not `"ä"`).

### 4.5 `pp_word_count(s) -> Int`

Number of whitespace-separated tokens of `pp_collapse_ws(s)`: `0` for empty
or whitespace-only input, `1` for a single token, `1 + number of spaces`
otherwise. `" a  b\tc "` -> `3`.

### 4.6 `pp_pipeline(s, stop, fold, punct, ws, stopw) -> Str`

Fixed order, each step applied only when its flag is `true`:

```
fold -> punct -> ws -> stopwords
```

The order is part of the contract. `"A, B"` with stopword `"a"` and all
flags on:

- fold: `"a, b"`,
- punct: `"a b"` (comma dropped),
- ws: `"a b"` (already collapsed),
- stopwords: `"b"`.

With `punct` off the stopwords pass sees the token `"a,"`, which does not
match `"a"`, so the result is `"A, B"` (all subsequent steps also off) or
`"a, b"` with fold on.

### 4.7 `pp_normalize_default(s) -> Str`

The `fold + punct + ws` preset:

```
pp_collapse_ws(pp_strip_punct(pp_fold_ascii(s)))
```

Equivalent to `pp_pipeline(s, stop, true, true, true, false)` for any stop
list; the stopwords step is skipped.

## 5. API signatures

```xi
pub fn pp_fold_ascii(s: Str) -> Str
pub fn pp_strip_punct(s: Str) -> Str
pub fn pp_collapse_ws(s: Str) -> Str
pub fn pp_remove_stopwords(s: Str, stop: &Vec[Str]) -> Str
pub fn pp_word_count(s: Str) -> Int
pub fn pp_pipeline(s: Str, stop: &Vec[Str], fold: Bool, punct: Bool, ws: Bool, stopw: Bool) -> Str
pub fn pp_normalize_default(s: Str) -> Str
```

Complexity: every step is `O(s.len())` except `pp_remove_stopwords`, which is
`O(s.len() + tokens * stop.len() * word length)` because each token is
compared against each pre-folded stopword.

## 6. Test plan

`tests/test_conformance.xi` (module `preprocess_tests`) runs 21 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | fold | `A-Z` folded, non-ASCII bytes kept, length preserved (4.1) |
| t2 | fold idempotent | only letters change; double fold is stable (4.1) |
| t3 | strip keeps digits | digits and spaces survive, marks dropped (4.2) |
| t4 | strip classes | TAB/LF/CR and non-ASCII dropped, letters/space kept (4.2) |
| t5 | collapse trim | runs -> one space, both ends trimmed (4.3) |
| t6 | collapse edge | single token unchanged, whitespace-only -> `""` (4.3) |
| t7 | collapse idempotent | second pass is a no-op (4.3) |
| t8 | long runs | 64 mixed space/tab runs -> one space; run alone -> `""` (4.3) |
| t9 | stopwords case | `The`/`THE` match `the`; all-stopword input -> `""` (4.4) |
| t10 | stopwords order | kept tokens preserve input order (4.4) |
| t11 | no substring | `the` keeps `theater`, `thespian`; `a` keeps `aa`; `he` keeps `the` (4.4) |
| t12 | empty entries | `""` in the list removes nothing; spaces rejoin to single (4.4) |
| t13 | empty input/list | `""` input and empty list are safe (4.4) |
| t14 | non-ASCII stops | `Ä` matches byte-exact, not `ä`; `Ä` keeps `ÄÄ` (4.4) |
| t15 | word_count | `0` empty/whitespace-only, `1`, `2`, `3` across separators (4.5) |
| t16 | pipeline all on | pinned on `"  The QUICK, brown   FOX!!\t"` -> `"quick brown"`; equals manual composition (4.6) |
| t17 | flags off | no flags -> input verbatim; each prefix of the order pinned (4.6) |
| t18 | default vs full | default -> `"the quick brown fox"`, full stops -> `"quick brown"` (4.7) |
| t19 | empty inputs | every entry point on `""` -> `""` / `0` (3.4) |
| t20 | punctuation-only | strip/default empty out; word count 0 after strip; token filter keeps `"!!!"` (4.2, 4.4, 4.5) |
| t21 | order pin | `"A, B"` + `a`: all on -> `"b"`; punct off -> `"a, b"` (token `"a,"` unmatched); stops off -> `"a b"` (4.6) |

Element comparisons use `xiom.string.compare.str_compare`, never `==` (BUG
17). `Vec[Str]` elements are read into typed locals before folding.

## 7. Known limitations

- ASCII-only case folding and character classes; no Unicode normalization or
  locale awareness.
- Whitespace tokenization only; punctuation is not a boundary for
  `pp_remove_stopwords` (the pipeline drops punctuation first).
- Destructive stripping: `pp_strip_punct` deletes rather than replaces, so
  tokens can fuse (`"a-b"` -> `"ab"`) and non-ASCII bytes are lost.
- No stemming / lemmatization: inflected forms are different tokens.
- Stopword lists are caller-supplied; no built-in lists or statistics.
- No streaming variant; each call processes the whole `Str` in memory.

## 8. Compiler / stdlib notes

No compiler workarounds beyond the documented v0.61.3 idioms: free functions
only, byte-wise scanning through `xiom.string.byte_at` with `Int`-space
guards (`(byte as Int) & 0xFF`), output accumulated in `Vec[UInt8]` and
materialized once with `xiom.string.builder.sb_to_str`, and no `==` on `Str`.
The module imports `xiom.string`, `xiom.string.builder` and
`xiom.string.compare`.
