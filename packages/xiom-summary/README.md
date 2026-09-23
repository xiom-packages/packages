# xiom.summary

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** extractive text summarization with frequency scoring.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_trim`, `xiom.string.compare.str_compare`).
> Tests additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.summary` is a small, dependency-free extractive summarizer for
in-memory `Str` documents. It splits text into sentences, tokenizes
lowercased ASCII alphanumeric words, drops a built-in English stopword list,
counts the remaining word frequencies, scores each sentence by the summed
frequency of its words, and returns the top-scoring sentences in their
original document order. Every entry point is infallible: functions return
`Vec[Str]` / `Vec[Int]` / `Str` / `Bool`, never a `Result`, and empty input
yields empty output. There is no FFI and no dependency beyond `xiom.string`
helpers.

## API

| Function | Returns | Description |
|---|---|---|
| `summary_sentences(text)` | `Vec[Str]` | Split after `.` `!` `?` when followed by whitespace or end; each sentence is trimmed of outer whitespace; interior punctuation is kept; empty/whitespace-only text yields `[]`. |
| `summary_words(text)` | `Vec[Str]` | Maximal runs of ASCII letters/digits, lowercased by the module's own A-Z fold; every other byte, including every non-ASCII byte, is a separator. |
| `summary_stopwords()` | `Vec[Str]` | The built-in 30-word English stopword list, strictly ascending (`str_compare` order); a fresh vector per call. |
| `summary_is_stopword(w, stop)` | `Bool` | Case-insensitive membership test of `w` in `stop` (ASCII fold + `str_compare`). |
| `summary_unique_words(words, stop)` | `Vec[Str]` | Distinct non-stopword words in first-seen order. |
| `summary_word_frequencies(words, stop)` | `Vec[Int]` | Occurrence count of each `summary_unique_words` entry, parallel to it. |
| `summary_sentence_score(sentence, unique, freqs, stop)` | `Int` | Sum of the frequencies of the sentence's non-stopword words; `0` when it has none. |
| `summary_extract(text, max_sentences)` | `Vec[Str]` | Up to `max_sentences` top-scoring sentences in original order; ties keep the earlier sentence; `[]` for empty text or `max_sentences <= 0`. |
| `summary_extract_text(text, max_sentences)` | `Str` | `summary_extract` joined with single spaces. |

## Usage

```xi
use xiom.summary;
use xiom.io;

fn main() -> Int {
  var text = "Cats are great. The cat sat on the mat with cats. Dogs bark.";
  io.println(summary_extract_text(text, 1));   // The cat sat on the mat with cats.
  io.println(summary_words("Hello, World!").len());  // 2
  io.println(summary_stopwords().len());             // 30
  var stop = summary_stopwords();
  var words = summary_words(text);
  var unique = summary_unique_words(&words, &stop);
  var freqs = summary_word_frequencies(&words, &stop);
  io.println(summary_sentence_score("the cat and the cat", &unique, &freqs, &stop));
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.summary
```

Expected tail: 23 `[PASS]` lines, `xiom.summary: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- Frequency scoring only: no TF-IDF, position bias, length normalization,
  TextRank/PageRank, MMR redundancy control, or abstractive rewriting.
- The built-in stopword list is English (30 words); other languages need a
  custom list passed to the helper functions.
- No stemming or lemmatization, so inflected forms count separately
  (`cats` and `cat` are different words).
- ASCII-only words and ASCII-only case folding: every non-ASCII byte is a
  separator (`café` -> `["caf"]`, `中文` -> `[]`).
- Sentence splitting is terminator + whitespace only; abbreviations,
  ellipses, decimals and quoted speech are not special-cased.
- Zero-score sentences (e.g. all-stopword or punctuation-only sentences)
  are still selectable when fewer than `max_sentences` higher-scoring
  sentences exist.
- Whole `Str` in memory only, no streaming API and no character offsets.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
