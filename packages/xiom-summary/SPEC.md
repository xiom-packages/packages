# xiom.summary -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.summary` (`src/summary.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free extractive summarizer for in-memory `Str`
documents:

- sentence splitting (`summary_sentences`),
- word tokenization with ASCII lowercasing (`summary_words`),
- a built-in English stopword list (`summary_stopwords`,
  `summary_is_stopword`),
- unique non-stopword words and their frequencies (`summary_unique_words`,
  `summary_word_frequencies`),
- frequency-based sentence scoring (`summary_sentence_score`),
- top-sentence extraction and joining (`summary_extract`,
  `summary_extract_text`).

`Str` is treated as a UTF-8 byte buffer; all scanning is byte-wise. Sentence
results are trimmed slices of the input and pass UTF-8 through byte-exact;
word results are ASCII-only (`[a-z0-9]`).

## 2. Non-goals

- Abstractive summarization (generation, rewriting, compression).
- TF-IDF, position bias, sentence-length normalization, TextRank/PageRank,
  MMR redundancy control, or centroid/embedding scoring.
- Stemming, lemmatization, and non-English stopword lists (callers may pass
  a custom stopword vector to the helpers).
- Unicode word/sentence segmentation (no UAX #29, no locale rules); no
  Unicode-aware case folding.
- Streaming / incremental processing; no FFI or file I/O.

## 3. Algorithms

### 3.1 Sentence splitting

`summary_sentences` scans the input bytes left to right. A byte that is one
of `.` `!` `?` ends a sentence when the next byte is ASCII whitespace
(space, tab, LF, CR) or the terminator is the last byte. Each piece runs
from the previous split point up to and including the terminator; it is
trimmed of outer ASCII whitespace and pushed when non-empty. A terminator
followed by any other byte does not split (`"a.b c"` stays whole). Text with
no terminator is one sentence. Empty and whitespace-only text yield `[]`.

This is the same byte-wise rule as `xiom.tokenizer.tokenize_sentences` (no
abbreviation, ellipsis, decimal, or quote handling).

### 3.2 Word scanning and ASCII folding

`summary_words` takes maximal runs of ASCII letters and digits
(`[A-Za-z0-9]`) as words. Every other byte -- punctuation, whitespace,
underscore, and each byte of a multi-byte UTF-8 sequence -- is a separator,
so `"café"` -> `["caf"]` and `"中文"` -> `[]`. Each word is lowercased with
the module's own fold: bytes `A`-`Z` become `a`-`z`, every other byte is
copied verbatim. A run is extracted with `xiom.string.str_slice` and folded
into a fresh `Vec[UInt8]`, converted with `Str::from_utf8`. Empty or
separator-only text yields `[]`.

### 3.3 Stopword list

`summary_stopwords()` returns 30 lowercase English stopwords in strictly
ascending `str_compare` order:

```
a, an, and, are, as, at, be, but, by, for, from, had, has, have, he, in,
is, it, its, not, of, on, or, that, the, this, to, was, were, with
```

`summary_is_stopword(w, stop)` lowercases `w` with the same ASCII fold and
tests membership with `xiom.string.compare.str_compare`. The comparison is
case-insensitive for ASCII; a non-lowercase list entry never matches its
uppercase input.

### 3.4 Unique words and frequencies

`summary_unique_words(words, stop)` walks `words` once and appends each
non-stopword element that is not already present (checked with
`str_compare`), so the result is deduplicated and in first-seen order.
`summary_word_frequencies(words, stop)` computes the same unique list and
returns, for each unique word, the number of occurrences of that word in
`words` (stopwords are never counted). The two vectors are parallel by
construction: `freqs.len() == unique.len()`, and every count is `>= 1`.

### 3.5 Sentence scoring

`summary_sentence_score(sentence, unique, freqs, stop)` tokenizes the
sentence with `summary_words`, skips stopwords, looks each remaining word
up in `unique` with `str_compare`, and sums the parallel `freqs` entries.
A word missing from `unique` contributes 0; when `freqs` is shorter than
`unique`, out-of-range entries contribute 0. A sentence with no
non-stopword word (empty, punctuation-only, or all-stopword) scores 0.

### 3.6 Extraction and deterministic tie-breaking

`summary_extract(text, max_sentences)`:

1. returns `[]` when `max_sentences <= 0` or the text has no sentences;
2. otherwise tokenizes the whole `text`, builds `unique`/`freqs` from the
   built-in stopword list, and scores every sentence;
3. selects up to `max_sentences` sentences: repeatedly scan the sentences
   in order and take the first not-yet-selected index, then replace the
   current best only when a later sentence has a **strictly greater**
   score. This makes selection stable: equal scores keep the earlier
   sentence, and zero-score sentences are selected only when all
   higher-scoring sentences are already taken;
4. emits the selected sentences in original document order.

The result is fully deterministic for a given input: no randomness, no
hash-map iteration order, no time or environment dependence.

### 3.7 Joining

`summary_extract_text` joins the extracted sentences with a single space
(`" "`) between consecutive entries and returns `""` when the extraction is
empty.

## 4. API signatures

```xi
pub fn summary_sentences(text: Str) -> Vec[Str]
pub fn summary_words(text: Str) -> Vec[Str]
pub fn summary_stopwords() -> Vec[Str]
pub fn summary_is_stopword(w: Str, stop: &Vec[Str]) -> Bool
pub fn summary_unique_words(words: &Vec[Str], stop: &Vec[Str]) -> Vec[Str]
pub fn summary_word_frequencies(words: &Vec[Str], stop: &Vec[Str]) -> Vec[Int]
pub fn summary_sentence_score(sentence: Str, unique: &Vec[Str], freqs: &Vec[Int], stop: &Vec[Str]) -> Int
pub fn summary_extract(text: Str, max_sentences: Int) -> Vec[Str]
pub fn summary_extract_text(text: Str, max_sentences: Int) -> Str
```

Complexity: sentence/word scanning is O(n) over the input bytes;
`summary_unique_words` and `summary_word_frequencies` are O(n * u) with u
the number of unique words; `summary_sentence_score` is O(|sentence| * u);
`summary_extract` is O(n * u + s^2) with s the sentence count.

## 5. Edge cases

- Empty text: every function returns `[]` / `0` / `""` / `false`; no
  function panics on any input, including non-UTF-8 byte sequences (bytes
  are never decoded).
- `max_sentences <= 0`: `summary_extract` and `summary_extract_text`
  return `[]` / `""`.
- `max_sentences` larger than the sentence count: all sentences are
  returned in original order.
- Punctuation-only text: `summary_words` yields `[]`;
  `summary_sentences` yields the punctuation run as one sentence (it ends
  with a terminator); `summary_extract` may return that zero-score
  sentence when `max_sentences >= 1`.
- Ties: strictly-greater comparison during selection keeps the earlier
  sentence.

## 6. Test plan

`tests/test_conformance.xi` (module `summary_tests`) runs 23 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | sentences: terminators | `.` `!` `?` all split (rule 3.1) |
| t2 | sentences: trim + no-split | outer trim, interior punctuation, `"a.b c"` (rule 3.1) |
| t3 | sentences: empty/whitespace | `[]` for `""` and blanks |
| t4 | words: lowercase | `Hello WORLD MixEd` -> `hello world mixed` (rule 3.2) |
| t5 | words: digits, underscore | `[0-9]` kept, `_` splits |
| t6 | words: non-ASCII | `café`, `naïve`, em dash, CJK (rule 3.2) |
| t7 | words: empty/separator-only | `[]` for `""`, punctuation, whitespace |
| t8 | stopwords: accessor | 30 entries, strictly ascending, `a` .. `with` (rule 3.3) |
| t9 | is_stopword | case-insensitive true/false cases (rule 3.3) |
| t10 | unique: order | first-seen dedup order (rule 3.4) |
| t11 | unique: stopwords dropped | `The cat and the dog` -> `cat dog` |
| t12 | frequencies: parallel | `[3,2,1]` for `b a b c a b` (rule 3.4) |
| t13 | frequencies: stopwords not counted | `[1,1]` for `the cat the dog the` |
| t14 | score: manual vectors | sums 3+2=5, singles, missing word, `""` (rule 3.5) |
| t15 | score: stopwords/non-words | repeated word counts twice, zero cases (rule 3.5) |
| t16 | extract: best sentence | picks the unique highest score (rule 3.6) |
| t17 | extract: original order | two picks emitted document-order (rule 3.6) |
| t18 | extract: ties | earlier sentence wins ties (rule 3.6) |
| t19 | extract: max > count | all sentences, in order |
| t20 | extract: max <= 0 / empty | `[]` in all four cases (rule 3.6) |
| t21 | extract_text: joining | single-space join, `""` case (rule 3.7) |
| t22 | determinism | two runs agree on extraction, words, text |
| t23 | punctuation-only | no words; sentence kept; `max 0` empty |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison); `vec_eq`/`ints_eq` compare whole vectors element-wise.

## 7. Known limitations

- Purely frequency-based scoring; no TF-IDF, position bias, length
  normalization, graph ranking, or redundancy control.
- The stopword list is English and fixed; callers with other languages (or
  other domains) must pass their own list and skip `summary_stopwords`.
- No stemming: `"cats"` and `"cat"` are distinct keys, which can split a
  keyword's frequency.
- ASCII-only words and folding: accented letters and CJK are separators.
- Sentence splitting is terminator + whitespace only; abbreviation and
  ellipsis handling is out of scope (see `xiom.tokenizer` for the same
  contract).
- Zero-score sentences can be extracted to fill `max_sentences`; callers
  wanting keyword-bearing summaries should cap `max_sentences` at the
  number of informative sentences or filter the result.
- Everything is in memory; no streaming API and no character offsets.

## 8. Compiler / stdlib notes

No compiler workarounds were required beyond the documented idioms: masked
byte reads (`(string.byte_at(s, i) as Int) & 0xFF`, BUG 22),
`let`-typed reads of `Vec[Int]` elements, and `str_compare` instead of `==`
for every `Str` read from a vector (BUG 17). All helpers are plain free
functions; no methods are declared on foreign types, no lambdas, no
`Vec[StructType]`, and only `&` (never `&mut`) is taken of locals, so the
E001 aliasing warning does not fire. The implementation follows the proven
byte-scanning style of `xiom.tokenizer` and `xiom.stemming`.
