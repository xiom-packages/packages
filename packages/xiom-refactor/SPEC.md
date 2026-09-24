# xiom.refactor -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.refactor` (`src/refactor.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free, text-level renamer for in-memory `Str` documents:

- word-character membership (`refactor_is_word_char`,
  `refactor_word_chars_default`),
- whole-word counting (`refactor_count`),
- whole-word replacement (`refactor_rename`),
- ordered pair application with per-pair reports
  (`refactor_rename_dry_run`, `refactor_rename_batch`),
- line reporting (`refactor_occurrence_lines`).

`Str` is treated as a UTF-8 byte buffer; all scanning is byte-wise and bytes
outside a match pass through byte-exact. The module never parses the input: it
is explicitly text-level, so string literals, comments and prose are treated
exactly like code.

## 2. Non-goals

- Parse awareness: no lexer, parser, scope or symbol table; no protection of
  strings/comments.
- Unicode identifier rules (UAX #31), case folding, or locale-aware casing.
- Word-boundary rules beyond the caller-supplied byte set.
- Edit scripting, conflict resolution, undo, or multi-file orchestration.
- Streaming / incremental processing; no FFI, file I/O or network.

## 3. Boundary rules

Definitions, in order of precedence:

1. **Word set.** `word_chars` is an arbitrary `Str` interpreted as a set of
   bytes; `refactor_is_word_char(byte, word_chars)` is true iff
   `0 <= byte <= 255` and the byte occurs in `word_chars`. The default set is
   `refactor_word_chars_default()` = `[A-Za-z0-9_]` (63 bytes). An empty
   `word_chars` contains no byte, so no byte is a word character.
2. **Literal match.** `old_name` matches at byte offset `i` of `text` when
   `i + |old_name| <= |text|` and `text[i .. i+|old_name|)` compares byte-equal
   to `old_name` (`str_compare == 0`). Matching is case-sensitive and never
   crosses bytes that differ; UTF-8 sequences only match their exact bytes.
3. **Whole-word boundary.** A literal match at `i` is a *whole-word
   occurrence* iff:
   - `i == 0` or the byte at `i-1` is not a word character, and
   - `i + |old_name| == |text|` or the byte at `i + |old_name|` is not a word
     character.
   The boundary bytes are tested against the same `word_chars` set. A byte of
   a multi-byte UTF-8 sequence is an ordinary byte: with the default set it is
   never a word character, so `caf\u{e9}foo\u{e9}` contains the whole-word
   occurrence `foo`.
4. **Non-overlap.** Scans run left to right; after a whole-word occurrence the
   scan resumes at `i + |old_name|`. `aaaa` with `aa` is therefore one
   occurrence (`Xa` after renaming), not two.
5. **Empty old name.** An empty `old_name` never matches:
   `refactor_count` returns 0, `refactor_rename` returns `text` unchanged, and
   a pair with an empty old name (pair text starting with `=`) reports
   `0 replacement(s)`.
6. **Empty text.** `refactor_count("", ...)` is 0, `refactor_rename("", ...)`
   is `""`, `refactor_rename_batch("", renames, ...)` is `""`, and
   `refactor_occurrence_lines("", ...)` is `[]`. No function panics on any
   byte sequence; bytes are never decoded.

## 4. Pair grammar

A rename pair is a `Str` of the form:

```
pair        = old "=" new
old         = *byte                 (everything before the first '=')
new         = *byte                 (everything after the first '=')
malformed   = pair with no '=' byte
```

- The split is at the **first** `=`; `new` may contain `=` (`a=b=c` renames
  `a` to `b=c`).
- A pair with no `=` is malformed: in `refactor_rename_dry_run` it produces
  exactly `old -> ?: invalid` (with `old` being the whole pair text) and is
  skipped; in `refactor_rename_batch` it is skipped silently. Malformed input
  never errors.
- A pair with an empty `old` (`=new`) is well-formed but matches nothing
  (rule 3.5).
- Pairs are applied **in order** to a working copy, so a later pair sees
  earlier replacements: `a=b` then `b=c` turns `a b` into `c c`.
- Dry-run lines are `old -> new: N replacement(s)` where `N` is the
  whole-word count of `old` in the working text as produced by the preceding
  pairs, and the pair is then applied to the working copy. The count is
  exactly the number of replacements `refactor_rename` performs for that
  pair, so `a=b` then `b=c` on `a b` reports `1` then `2`.

## 5. Line reporting

`refactor_occurrence_lines(text, name, word_chars)` splits `text` into lines
on `LF`. A `CR` immediately before an `LF` is an ordinary non-word byte
(unless listed in `word_chars`), so CRLF text reports the same line numbers as
LF text. One trailing `LF` adds no empty line, matching the usual
line-splitting convention. A line is reported when `refactor_count(line,
name, word_chars) > 0`; numbers are 1-based and increasing. Empty text or an
empty name yields `[]`. Matching is per line, so a `name` containing an `LF`
byte cannot span lines.

## 6. API signatures

```xi
pub fn refactor_word_chars_default() -> Str
pub fn refactor_is_word_char(byte: Int, word_chars: Str) -> Bool
pub fn refactor_count(text: Str, old_name: Str, word_chars: Str) -> Int
pub fn refactor_rename(text: Str, old_name: Str, new_name: Str, word_chars: Str) -> Str
pub fn refactor_rename_dry_run(text: Str, renames: &Vec[Str], word_chars: Str) -> Vec[Str]
pub fn refactor_rename_batch(text: Str, renames: &Vec[Str], word_chars: Str) -> Str
pub fn refactor_occurrence_lines(text: Str, name: Str, word_chars: Str) -> Vec[Int]
```

Complexity: all scanners are O(n * |old_name|) over the input; the pair
functions multiply that by the number of pairs. No function allocates a
`Result` and none can fail.

## 7. Test plan

`tests/test_conformance.xi` (module `refactor_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | word_chars_default | exact 63-byte `[A-Za-z0-9_]` string (rule 3.1) |
| t2 | is_word_char | membership, `0..255` range, empty set (rule 3.1) |
| t3 | count standalone | basic whole-word counts (rules 3.2, 3.3) |
| t4 | count prefix/suffix | `foobar`, `barfoo`, `foofoo`, too-long name are 0 (rule 3.3) |
| t5 | underscore boundary | `foo_bar` counts `foo` only when `_` not in the set (rule 3.1) |
| t6 | empty old name | count 0, rename unchanged, dry-run `0 replacement(s)` (rule 3.5) |
| t7 | rename boundaries | punctuation and `_` boundaries with the default set (rule 3.3) |
| t8 | rename alnum set | `_foo_` and `foo_bar` with `_` excluded from the set (rule 3.1) |
| t9 | old == new | identity rename (rule 3.2) |
| t10 | absent/empty/case | absent name, empty text, case sensitivity (rules 3.2, 3.6) |
| t11 | batch order | `a=b` then `b=c` gives `c c` (rule 4) |
| t12 | batch reversed | `b=c` then `a=b` gives `b c` (rule 4, order sensitivity) |
| t13 | batch malformed | no-`=` pair skipped, never errors (rule 4) |
| t14 | dry-run lines | running-text counts `1` then `2` (rule 4) |
| t15 | dry-run invalid | `old -> ?: invalid`, never errors (rule 4) |
| t16 | occurrence_lines | multi-line, no match, empty text, single line (rule 5) |
| t17 | occurrence_lines CRLF | CRLF keeps 1-based line numbers (rule 5) |
| t18 | occurrence_lines boundaries | `foobar`/`foo_bar` filtering and trailing LF (rules 3.3, 5) |
| t19 | unicode | non-ASCII bytes are not word chars; UTF-8 passes through (rule 3.3) |
| t20 | empty text / empty set | empty inputs and empty `word_chars` (rules 3.1, 3.6) |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison); `vec_eq`/`ivec_eq` compare whole vectors element-wise.

## 8. Known limitations

- No parse awareness: strings, comments and prose are renamed like code.
- Word characters are single bytes; the default alphabet is ASCII-only, and
  no Unicode identifier semantics exist.
- Case-sensitive only; no case-insensitive or smart-case mode.
- Non-overlapping scans; no overlapping or regex matching.
- Occurs only as a library API; no CLI, no file I/O, no multi-file planning.
- `refactor_occurrence_lines` reports line numbers only (no columns or byte
  offsets) and cannot match across line boundaries.

## 9. Compiler / stdlib notes

No compiler workarounds were required. The implementation reuses the proven
byte-scanning idioms from `xiom.tokenizer` / `xiom.lexing`: byte-wise scanning
via `xiom.string.byte_at`, slice extraction via `xiom.string.str_slice`, and
`str_compare` for every string comparison. Helpers are plain free functions;
no methods are declared on foreign types and no `Vec[StructType]` is needed.
`UInt8` bytes are widened with an explicit `as Int` before being compared
against the `Int` argument of `refactor_is_word_char`; `int_to_string` comes
from `xiom.convert`. Only `&` (never `&mut`) is taken of locals in call
sites.
