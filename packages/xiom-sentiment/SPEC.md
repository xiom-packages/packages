# xiom.sentiment -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.sentiment` (`src/sentiment.xi`). Manifest: `package.xi` (name
`xiom.sentiment`, version `0.1.0`). Depends on `xiom.std` (`xiom.string`,
`xiom.string.compare`). Pure XIOM, no FFI.

## Scope

Lexicon-based sentiment scoring over a `Str`:

- three built-in lexicons: positive words, negative words, negators;
- a lowercase ASCII word scan (`sentiment_words`);
- a signed-sum score with a three-word negation window (`sentiment_score`);
- a label mapping (`sentiment_label`, `sentiment_label_text`);
- hit/negation counts (`sentiment_counts`).

## Non-goals

- No FFI, no file/network I/O, no model weights: everything is pure XIOM and
  in-memory.
- No caller-supplied or loadable lexicon; the lists are fixed and bundled.
- No stemming, lemmatization, morphology or language detection.
- No intensity weights, no emphasis, no punctuation weighting.
- No Unicode-aware segmentation: scanning operates on the UTF-8 bytes of
  `Str`, and non-ASCII bytes separate words.
- No generics in XIOM v0.61.x: every signature is concrete.
- Not thread-safe and not `async`.

## Lexicons

All entries are lowercase ASCII, sorted ascending under byte-wise
`xiom.string.compare.str_compare` order, free of duplicates, and the three
lists are pairwise disjoint.

### Positive (`sentiment_positive_words`) -- 38 words

```
able awesome best brave bright calm cheerful clever confident delighted
eager easy excellent fantastic friendly generous glad good great happy
honest incredible joyful kind love lovely lucky nice perfect pleasant
polite proud smart strong successful superb terrific wonderful
```

### Negative (`sentiment_negative_words`) -- 54 words

```
afraid angry awful bad boring broken corrupt cruel damaged dangerous
dead defect difficult dirty disappointing disaster evil failure fake
fear filthy foolish greedy grief hate horrible hurt jealous liar lonely
loss lost mad messy miserable nasty negative painful poor problem rage
reject rotten rude sad sick stupid terrible ugly useless violent weak
worst wrong
```

### Negators (`sentiment_negators`) -- 8 words

```
barely hardly neither never no nor not without
```

## Tokenization rules

`sentiment_words(text)` scans the UTF-8 bytes of `text`:

- A word is a maximal run of ASCII word bytes `[A-Za-z0-9]` (bytes `0-9`,
  `A-Z`, `a-z`).
- Every other byte is a separator: punctuation, whitespace, apostrophe,
  underscore, and each byte of a multi-byte UTF-8 sequence. So `"don't"` ->
  `don`, `t`; `"stop_now"` -> `stop`, `now`; `"café"` -> `caf`; `"中文"` ->
  `[]`; `"a—b"` -> `a`, `b`.
- Each token is folded to lowercase with ASCII `str_lower`, so `"Good"` ->
  `good` and `"GREAT"` -> `great`.
- Empty or separator-only text yields `[]`.

## Scoring algorithm

`sentiment_score(text)` and `sentiment_counts(text)` share one pass over
`sentiment_words(text)`; both rebuild the three lexicons locally (they are
pure constant functions) and use a linear membership test that compares with
`str_compare` (never `==` on Vec-sourced `Str`, BUG 17).

For each word `w` at index `i`:

```
score = 0; pos_hits = 0; neg_hits = 0; negations = 0
negated = any of words[max(0, i-3) .. i-1] is in the negator lexicon

if w in positive lexicon:
    pos_hits += 1
    if negated: score -= 1; negations += 1
    else:       score += 1
elif w in negative lexicon:
    neg_hits += 1
    if negated: score += 1; negations += 1
    else:       score -= 1
```

### Negation semantics (normative)

- The lookback window is the **three words immediately preceding** the
  polarity word: indices `max(0, i - 3)` through `i - 1`. A negator at
  distance 1, 2 or 3 applies; at distance 4 or more it does not.
- The window contains **at least one** negator -> the polarity word flips
  **exactly once**. Multiple negators in the window do not stack and do not
  cancel: `not never no good` -> `-1`.
- Flipping applies to **every polarity word whose own window contains a
  negator**, not only to the first polarity word after the negator. Example:
  `not good bad` -> `good` is flipped (`-1`) and `bad` is also flipped (its
  window holds `not`), so the score is `0` with counts `(1, 1, 2)`.
- Negators themselves are never polarity words; the three lexicons are
  disjoint.
- Windows do not respect punctuation, commas, clauses or sentence
  boundaries: `not, good` flips just like `not good`.

### Counts triple (normative)

`sentiment_counts(text)` returns `(positive_hits, negative_hits,
negations_applied)`:

- `positive_hits` -- number of positive lexicon words found (counted before
  any flip);
- `negative_hits` -- number of negative lexicon words found (counted before
  any flip);
- `negations_applied` -- number of polarity words whose contribution was
  flipped.

The score is the signed sum over the hits after applying the flips:
`score == (positive_hits - flips_of_positives) - (negative_hits -
flips_of_negatives)`, where `negations_applied` is the sum of the two flip
counts.

## Label thresholds

`sentiment_label(score)`:

| Condition | Label |
|---|---|
| `score < 0` | `"negative"` |
| `score == 0` | `"neutral"` |
| `score > 0` | `"positive"` |

`sentiment_label_text(text)` is exactly
`sentiment_label(sentiment_score(text))`.

## API signatures

All functions are free functions in module `xiom.sentiment`:

```xi
pub fn sentiment_positive_words() -> Vec[Str]
pub fn sentiment_negative_words() -> Vec[Str]
pub fn sentiment_negators() -> Vec[Str]
pub fn sentiment_words(text: Str) -> Vec[Str]
pub fn sentiment_score(text: Str) -> Int
pub fn sentiment_label(score: Int) -> Str
pub fn sentiment_label_text(text: Str) -> Str
pub fn sentiment_counts(text: Str) -> (Int, Int, Int)
```

No function has an error path: every input (including empty text) is
accepted.

## Complexity

| Function | Time | Memory |
|---|---|---|
| `sentiment_positive_words` / `sentiment_negative_words` / `sentiment_negators` | O(1) (constant-size) | O(1) |
| `sentiment_words` | O(n) | O(words) |
| `sentiment_score` | O(n + words * (\|pos\| + \|neg\| + \|negators\|)) | O(words + lexicons) |
| `sentiment_label` | O(1) | O(1) |
| `sentiment_label_text` | O(score path) | O(score path) |
| `sentiment_counts` | O(score path) | O(score path) |

`n` is the byte length of the text; each polarity/negator test is a linear
scan of a fixed-size lexicon (38 + 54 + 8 entries), so the lexicon scan is a
constant factor.

## Test plan

`tests/test_conformance.xi` (`module sentiment_tests`, 24 named checks, a
csv-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line and
returns the failure count):

1. positive lexicon: `>= 30` entries, lowercase, sorted ascending, unique,
   contains `good/great/love/wonderful`;
2. negative lexicon: `>= 30` entries, lowercase, sorted, unique, contains
   `bad/terrible/awful/worst`;
3. negators: exactly the 8 documented entries, lowercase, sorted, unique;
4. the three lexicons are pairwise disjoint (and sized `>= 30/30/8`);
5. word scan folds ASCII case to lowercase;
6. word scan separates on punctuation and keeps digits (`Well, this is
   10/10 -- nice!`);
7. word scan treats non-ASCII bytes, apostrophes and underscores as
   separators (`naïve café` -> `na ve caf`, `中文` -> `[]`, `don't
   stop_now`);
8. empty and separator-only text: no words, score 0, counts `(0, 0, 0)`,
   label `neutral`;
9. positive-only text scores `+1` per positive word (`I love this great and
   wonderful book` -> `3`);
10. negative-only text scores `-1` per negative word (`This awful terrible
    movie is boring` -> `-3`);
11. text without lexicon words scores 0 and labels `neutral` (`the cat sat
    on the mat`);
12. mixed text sums signed contributions (`good good bad` -> `+1`, counts
    `(2, 1, 0)`; `good bad` -> 0);
13. mixed sentence: `love + great - terrible == +1`;
14. label thresholds across `-3, -1, 0, 1, 7`;
15. `label_text` maps scores of texts (`great`/`terrible`/neutral/mixed);
16. `not good` flips to `-1`, counts `(1, 0, 1)`, `label_text` of
    `this is not good` is `negative`;
17. `not bad` flips to `+1`, counts `(0, 1, 1)`, `label_text` of
    `this is not bad` is `positive`;
18. negator at distance 1, 2 and exactly 3 applies (`not good`,
    `not very good`, `no the cat good` -> `-1`);
19. negator at distance 4+ does not apply (`not a very very good`,
    `no the cat sat good`, `without any serious doubt terrible` -> unflipped
    scores);
20. multiple negators do not stack (`not never no good` -> `-1`, counts
    `(1, 0, 1)`; `not never bad` -> `+1`);
21. scoring and scanning are case-insensitive (`NOT GOOD` -> `-1`,
    `Great` -> `+1`, `No Bad` -> `+1`);
22. punctuation separates words but not negators (`good, bad!` -> 0,
    `good-bad` -> 0, `not, good` -> `-1`);
23. counts triple semantics: `good not terrible` -> `(1, 1, 1)` and score
    `+2`; documented window effect `not good bad` -> `(1, 1, 2)` and score
    `0`;
24. determinism: repeated calls give identical score, counts, word scan and
    label.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.sentiment
```

Last verified: compiler 0.61.3, `port: PASS (passed=24 failed=0
program_exit=0 exit=0)`.

## Compiler / stdlib notes for v0.61.3

- `str_compare` is imported from `xiom.string.compare`; flat `str_lower`,
  `str_slice` and `byte_at` come from `xiom.string`.
- Vec-sourced `Str` elements are compared only via `str_compare` (BUG 17:
  `==` lowers to a pointer compare); `Str` element reads are pinned with
  explicit types (`let w: Str = words[i];`).
- `byte_at` results are compared only against `UInt8` constants below 128
  (`48u8`, `57u8`, `65u8`, `90u8`, `97u8`, `122u8`).
- Free functions and `while` loops only: no `self` methods, no inline
  lambdas, no `Vec[fn]` test dispatch, no `mut` patterns, no
  `Vec[StructType]` and no `Vec[Float64]`.
- `sentiment_counts` returns a tuple `(Int, Int, Int)`; tuple destructuring
  with `_` or unused bindings type-checks cleanly (unused destructured
  bindings are accepted by the compiler).

## Known limitations

- The lexicon is fixed and English-only; coverage is intentionally small and
  not a model.
- No morphology: inflected forms (`loves`, `loved`, `terribly`) are not
  matched.
- Negation handling is a fixed 3-word window with a single flip; it does not
  model scope, double negatives, or clause structure.
- Equal weight per hit; no intensity, emphasis or punctuation signals.
- ASCII byte semantics: non-ASCII bytes split words and are never matched.
- Linear lexicon scans per token; no hash set, index or caching.
