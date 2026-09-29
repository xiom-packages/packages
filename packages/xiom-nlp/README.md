# xiom.nlp

> **Status:** `incubating` -- conformance-tested (27/27); published at `v0.1.1` on the XIOM registry.
> **Scope:** deterministic, byte-oriented ASCII text analysis: tokenizer,
> sentence splitter, Porter stemmer, simple statistics.
> **Deps:** `xiom.std` (platform dependency; the library imports
> `xiom.string` and `xiom.string.compare`).

## What it is

`xiom.nlp` is a small, dependency-light natural-language core for programs
that already have text bytes and want predictable structure out of them:

- **Tokenization** -- maximal runs of `[A-Za-z0-9']` are words; every other
  byte (including bytes >= 128) is a separator. Each token carries its exact
  `[start, end)` byte offsets, so callers can slice the source themselves.
- **ASCII case** -- byte lowercasing (`A-Z` -> `a-z`) and case-insensitive
  byte/token comparison. No Unicode case tables: bytes >= 128 pass through
  and compare as themselves.
- **Sentence splitting** -- `.`, `!`, `?` end a sentence when followed by
  whitespace or the end of the text, with an abbreviation guard list
  (`Mr.`, `Mrs.`, `Dr.`, `Ms.`, `Prof.`, `St.`, `vs.`, `etc.`, `e.g.`,
  `i.e.`, case-insensitive) and a decimal-number guard (`3.14`, `3. 14`).
- **Porter stemming** -- Porter's 1980 suffix-stripping algorithm
  (steps 1a, 1b, 1c, 2, 3, 4, 5a, 5b) over byte vectors, plus its
  `measure` / `contains-vowel` / `ends-*` predicates.
- **Statistics** -- token count, total and average token length, and the
  number of distinct stemmed forms (bounded O(n^2), documented).

The library is pure XIOM, byte-oriented, and has no FFI, no allocation
beyond what each call returns, and no global state. Failed stems carry a
byte offset: `NlpError { code, offset }` (code 1 = non-ASCII byte, code 2 =
empty input; see SPEC.md section 8).

## API

| Function | Returns | Description |
|---|---|---|
| `nlp_tokenize(text)` | `NlpTokens` | Tokenize; parallel start/end offset vectors. |
| `nlp_token_count(t)` | `Int` | Number of tokens. |
| `nlp_token_start(t, i)` | `Int` | Start offset of token `i`; -1 when out of range. |
| `nlp_token_end(t, i)` | `Int` | End offset (exclusive); -1 when out of range. |
| `nlp_token_text(t, i)` | `Str` | Token text; "" when out of range. |
| `nlp_token_bytes(t, i)` | `Vec[UInt8]` | Token bytes; empty when out of range. |
| `nlp_token_equals(t, i, word)` | `Bool` | Case-sensitive token equality. |
| `nlp_token_equals_ci(t, i, word)` | `Bool` | ASCII case-insensitive token equality. |
| `nlp_lower_byte(b)` | `UInt8` | Lowercase one ASCII byte. |
| `nlp_lower_bytes(word)` | `Vec[UInt8]` | Lowercased copy of a byte vector. |
| `nlp_lower_str(s)` | `Str` | Lowercased copy of a `Str` (only A-Z change). |
| `nlp_ci_equals(a, b)` | `Bool` | ASCII case-insensitive byte equality. |
| `nlp_sentences(text)` | `NlpSentences` | Sentence spans with byte offsets. |
| `nlp_sentence_count(s)` | `Int` | Number of sentences. |
| `nlp_sentence_start(s, i)` | `Int` | Start offset; -1 when out of range. |
| `nlp_sentence_end(s, i)` | `Int` | End offset (exclusive); -1 when out of range. |
| `nlp_sentence_text(s, i)` | `Str` | Sentence text; "" when out of range. |
| `nlp_stem(word)` | `Vec[UInt8]` | Lax Porter stem; rejected input is returned unchanged. |
| `nlp_stem_checked(word)` | `Result[Vec[UInt8], NlpError]` | Strict Porter stem; errors carry offsets. |
| `nlp_measure(word)` | `Int` | Porter measure m of the whole word. |
| `nlp_contains_vowel(word)` | `Bool` | Word contains a vowel (Porter consonant rules). |
| `nlp_ends_with(word, suffix)` | `Bool` | Word ends with an ASCII suffix. |
| `nlp_ends_double_consonant(word)` | `Bool` | Word ends with a double consonant (*d). |
| `nlp_ends_cvc(word)` | `Bool` | Word ends cvc, final consonant not w/x/y (*o). |
| `nlp_error_code(e)` | `Int` | Code of an `NlpError`. |
| `nlp_error_offset(e)` | `Int` | Byte offset of an `NlpError`. |
| `nlp_total_token_length(t)` | `Int` | Sum of token lengths. |
| `nlp_avg_token_length(t)` | `Int` | Truncated integer average; 0 when no tokens. |
| `nlp_distinct_stem_count(t)` | `Int` | Distinct lowercased stemmed forms (bounded O(n^2)). |

## Usage

```xi
use xiom.nlp;

let t = nlp_tokenize("Don't stop. Really, 3.14!");
// nlp_token_count(&t) == 5; nlp_token_text(&t, 0) == "Don't"
let is_dont = nlp_token_equals_ci(&t, 0, "DON'T");   // true

let s = nlp_sentences("Mr. Smith slept. He dreamed.");
// nlp_sentence_count(&s) == 2; sentence 0 == "Mr. Smith slept."

let tb = nlp_token_bytes(&t, 0);
let w = nlp_lower_bytes(&tb);
let stem = nlp_stem(&w);                             // "don't" (no rule applies)
```

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 27 `[PASS]` lines, then `xiom.nlp: all tests passed`, exit 0.
From the repository root, the porter wrapper runs the same suite:

```
.\scripts\port.ps1 -Package xiom.nlp
```

## Limitations (honest list)

- ASCII/byte semantics only: bytes >= 128 are separators, are not
  case-folded, and make `nlp_stem_checked` fail (offset included).
- Sentences are split by a simple punctuation rule with a fixed guard
  list; there is no grammar, no quote handling, no language model.
- The stemmer follows the 1980 paper exactly, including `ties -> ti`
  (see SPEC.md section 7 for the paper citation and the Snowball
  variant difference).
- Distinct-stem counting is pairwise O(n^2) byte comparisons, by design;
  it is a helper, not an index.

## Install / publish

```
xiom pkg install xiom.nlp@0.1.0     # consumer
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
