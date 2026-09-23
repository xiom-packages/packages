# xiom.tokenizer -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.tokenizer` (`src/tokenizer.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free text tokenizer for in-memory `Str` documents:

- word tokenization (`tokenize_words`, `tokenize_count_words`),
- sentence splitting (`tokenize_sentences`),
- line splitting (`tokenize_lines`),
- word n-gram construction (`tokenize_ngrams`).

`Str` is treated as a UTF-8 byte buffer; all scanning is byte-wise. Word
tokens are always ASCII (non-ASCII bytes separate); sentence and line tokens
are slices of the input and pass UTF-8 through byte-exact.

## 2. Non-goals

- Unicode word/sentence segmentation (no UAX #29, no `wordbreak`/
  `sentencebreak` tables, no locale rules).
- Language-aware sentence splitting (abbreviation lists, quoted speech).
- Stemming, lemmatization, case folding, stop-word removal.
- Subword tokenization (BPE, WordPiece) and byte offset bookkeeping.
- Streaming / incremental tokenization; no FFI or file I/O.

## 3. Grammar and semantics

Informal grammar:

```
word_bytes  = "A".."Z" | "a".."z" | "0".."9" | "_"
word        = word_bytes 1*( (word_bytes | "'" word_bytes) )
line        = *UTF8-byte except LF
document    = line *( LF line ) [ LF ]
sentence    = *UTF8-byte terminator
terminator  = "." | "!" | "?"
```

Decisions (each one is covered by the conformance suite):

1. **Word alphabet.** A word token is a maximal run of `[A-Za-z0-9_]` bytes.
   Every other byte is a separator: ASCII punctuation, ASCII whitespace, and
   every byte of a multi-byte UTF-8 sequence. Non-ASCII text therefore yields
   ASCII-only tokens: `"café"` => `["caf"]`, `"naïve"` => `["na","ve"]`,
   `"中文"` => `[]`, `"a—b"` => `["a","b"]`.
2. **Apostrophes.** `'` is kept only strictly between two word bytes:
   `"don't"` => `["don't"]`. At a token edge it separates: `"'tis"` =>
   `["tis"]`, `"cats'"` => `["cats"]`. A doubled apostrophe separates:
   `"don''t"` => `["don","t"]`.
3. **Separator runs.** Leading, trailing and repeated separators produce no
   empty tokens: `"  ...one,,,two---  "` => `["one","two"]`. Empty or
   separator-only text yields `[]`; `tokenize_count_words("")` is `0`.
4. **Sentences.** Split after a `.` `!` or `?` byte when the next byte is
   ASCII whitespace (space, tab, LF, CR) or the terminator is the last byte.
   The terminator is included in the sentence. A terminator followed by any
   other byte does not split: `"a.b c"` stays one sentence.
5. **Sentence trimming.** Each piece is trimmed of outer ASCII whitespace;
   interior punctuation and interior whitespace are preserved verbatim:
   `"Hello, world. Bye."` => `["Hello, world.","Bye."]`. Pieces that are
   empty after trimming (leading whitespace, the whitespace run after a
   split, trailing whitespace) are dropped, so `"  Hello.  "` => `["Hello."]`
   and whitespace-only text yields `[]`. Text with no terminator is one
   sentence (`"just some words"` => `["just some words"]`).
6. **Lines.** Lines split on LF. A CR immediately before the LF is stripped
   (CRLF normalization); a lone CR inside a line is kept. A single trailing
   LF ends the last line and adds no empty line: `"a\nb\n"` => `["a","b"]`,
   `"a\n"` => `["a"]`. An interior empty line is a line: `"a\n\nb"` =>
   `["a","","b"]`; `"\n"` => `[""]`. Empty text yields `[]`. No trimming.
7. **N-grams.** `tokenize_ngrams(words, n)` joins each contiguous window of
   `n` words with single spaces, in order; there are
   `words.len() - n + 1` results when `n >= 1` and `words.len() >= n`.
   Otherwise (including `n < 1`) it returns `[]`. Windows are not compared or
   deduplicated.
8. **Empty input.** `tokenize_words("")`, `tokenize_sentences("")`,
   `tokenize_lines("")` and `tokenize_ngrams(empty, n)` all return an empty
   `Vec[Str]`; no function panics on any input, including non-UTF-8 byte
   sequences (bytes are never decoded).

## 4. API signatures

```xi
pub fn tokenize_words(text: Str) -> Vec[Str]
pub fn tokenize_sentences(text: Str) -> Vec[Str]
pub fn tokenize_lines(text: Str) -> Vec[Str]
pub fn tokenize_ngrams(words: &Vec[Str], n: Int) -> Vec[Str]
pub fn tokenize_count_words(text: Str) -> Int
```

Complexity: word, sentence and line tokenization are O(n) over the input
bytes. `tokenize_ngrams` is O(n * m) over the joined output length.
`tokenize_count_words` is O(n) time with O(words) temporary memory (it
delegates to `tokenize_words`).

## 5. Test plan

`tests/test_conformance.xi` (module `tokenizer_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | words: punctuation split | basic word/separator split |
| t2 | words: all separators | every non-word byte separates (rule 1) |
| t3 | words: digits/underscores | `[0-9_]` are word bytes |
| t4 | words: inner apostrophes | `don't`, `isn't`, `it's` (rule 2) |
| t5 | words: edge apostrophes | `'tis`, `cats'`, `''`, `don''t` (rule 2) |
| t6 | words: separator runs | leading/trailing/repeated (rule 3) |
| t7 | words: empty text | `[]` and count 0 (rule 8) |
| t8 | words: non-word-only text | whitespace/punctuation only |
| t9 | words: non-ASCII separators | `café`, `naïve`, CJK, em dash (rule 1) |
| t10 | lines: LF split | basic line split |
| t11 | lines: CRLF + lone CR | CR stripped before LF, lone CR kept (rule 6) |
| t12 | lines: trailing newline | `"a\nb\n"`, `"a\n"` (rule 6) |
| t13 | lines: empty/blank | `""`, `"\n"`, `"a\n\nb"`, `"a\n\n"` (rules 6, 8) |
| t14 | sentences: terminators | `.` `!` `?` all split (rule 4) |
| t15 | sentences: whitespace | outer trim, multi-space split (rule 5) |
| t16 | sentences: no terminator | one sentence; `.` and `"End."` |
| t17 | sentences: no split cases | `"a.b c"`, `"Wait... what?"` (rule 4) |
| t18 | sentences: interior + CRLF | interior punctuation kept, CRLF splits |
| t19 | sentences: empty/whitespace | `[]` for `""` and blanks (rules 5, 8) |
| t20 | ngrams: n = 2 | sliding bigrams (rule 7) |
| t21 | ngrams: n = 1, n = 3 | identity and trigrams |
| t22 | ngrams: too short / n < 1 | all empty (rule 7) |
| t23 | count_words | matches `tokenize_words` on five inputs |
| t24 | ngrams pipeline | `tokenize_ngrams(tokenize_words(...), 2)` |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison); `vec_eq` compares whole vectors element-wise.

## 6. Known limitations

- ASCII-only word alphabet; accented letters and CJK are separators, so no
  Unicode tokens are ever produced.
- No abbreviation/ellipsis/decimal awareness in sentence splitting; a
  terminator must be followed by whitespace or end of text.
- Sentence and line tokens are byte slices with outer whitespace trimmed;
  they are not normalized in any other way (no NFC, no case folding).
- N-grams join with a literal space; tokens that themselves contain spaces
  make the join ambiguous.
- Everything is in memory; no streaming API and no character offsets.
- Apostrophe handling is U+0027 only (not the typographic U+2019).

## 7. Compiler / stdlib notes

No compiler workarounds were required. The implementation uses the proven
byte-scanning idioms from `xiom.serialize.csv`/`xiom.string`: byte-wise
scanning via `xiom.string.byte_at`, token extraction via
`xiom.string.str_slice`, and trimming via `xiom.string.str_trim`. Helpers are
plain free functions; no methods are declared on foreign types. The test
suite routes every string comparison through `str_compare`, and only `&`
(never `&mut`) is taken of locals in call sites, so the E001 aliasing warning
does not fire.
