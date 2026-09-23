# xiom.sentiment

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** lexicon-based sentiment scoring with negation handling: a fixed
> English positive/negative word lexicon, a signed-sum score, a three-word
> negation window, and positive/negative/neutral labels.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_lower` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.sentiment` is a small, dependency-free sentiment scorer with zero I/O.
It carries its own English lexicon (38 positive words, 54 negative words,
8 negators) and turns text into a signed score: `+1` per positive word,
`-1` per negative word. A negator in the three words immediately before a
polarity word flips that word's contribution exactly once -- multiple
negators do not stack, so `not never no good` scores `-1`, not `+1`.

Text is scanned byte-wise over its UTF-8 representation: a word is a maximal
run of `[A-Za-z0-9]` bytes folded to lowercase, and every other byte --
punctuation, whitespace, apostrophes, underscores, and each byte of a
multi-byte UTF-8 sequence -- is a separator. Every entry point is infallible
(no `Result` channel). All comparisons of `Str` values read from `Vec`
elements go through `xiom.string.compare.str_compare` (the compiler lowers
`==` on such values to a pointer comparison, BUG 17).

## API

| Function | Returns | Description |
|---|---|---|
| `sentiment_positive_words()` | `Vec[Str]` | Built-in positive lexicon: 38 lowercase, sorted, unique words. |
| `sentiment_negative_words()` | `Vec[Str]` | Built-in negative lexicon: 54 lowercase, sorted, unique words. |
| `sentiment_negators()` | `Vec[Str]` | Built-in negators: `barely hardly neither never no nor not without` (sorted). |
| `sentiment_words(text)` | `Vec[Str]` | Lowercase `[A-Za-z0-9]` word scan; every other byte, including non-ASCII bytes, separates. |
| `sentiment_score(text)` | `Int` | Signed sum: `+1`/`-1` per polarity word, flipped once by a negator in the 3 preceding words. |
| `sentiment_label(score)` | `Str` | `"negative"` (`< 0`), `"neutral"` (`0`), `"positive"` (`> 0`). |
| `sentiment_label_text(text)` | `Str` | `sentiment_label(sentiment_score(text))`. |
| `sentiment_counts(text)` | `(Int, Int, Int)` | `(positive_hits, negative_hits, negations_applied)`, hits counted before flipping. |

## Usage

```xi
use xiom.sentiment;
use xiom.convert.int;
use xiom.io;

fn main() -> Int {
  io.println(int_to_string(sentiment_score("I love this great book")));  // 3
  io.println(int_to_string(sentiment_score("not good")));                // -1, flipped
  io.println(sentiment_label_text("this is not bad"));                   // positive
  let (pos_hits, neg_hits, negations) = sentiment_counts("not good");
  io.println(int_to_string(pos_hits) + "/" + int_to_string(neg_hits) + "/" + int_to_string(negations));
  // 1/0/1
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.sentiment
```

Expected: the namespaced module passes the section-4 namespace rule, 24
`[PASS]` lines, `xiom.sentiment: all tests passed`, and a final
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- Fixed English lexicon bundled in the module: 38 positive and 54 negative
  words plus 8 negators. There is no file loading, no caller-supplied
  dictionary, no language selection and no training/learning.
- Exact word matching only: no stemming or lemmatization, so `loves`,
  `loved`, `loving` do not match `love`, and `terribly` does not match
  `terrible`.
- Negation is a fixed three-word lookback window: it flips each polarity
  word in the window exactly once (no stacking, no double-negative
  cancellation), and it does not respect clause, comma or sentence
  boundaries.
- Every lexicon word carries the same weight: no intensity scores
  (`great` and `good` both count `+1`), no emphasis handling.
- ASCII byte semantics: non-ASCII bytes are separators, so `café` scans as
  `caf` and accented/CJK words are never matched.
- The scorer is a single pass with a linear lexicon scan
  (`O(words * |lexicon|)`); no index, no set, no thread-safety and no
  `async` API.

See `SPEC.md` for the lexicons, the exact scoring and negation algorithm,
and the full test plan. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
