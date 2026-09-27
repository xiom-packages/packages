# xiom.nlp -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.nlp` (`src/nlp.xi`). Pure XIOM, no FFI.
References:

- Porter, M.F., "An algorithm for suffix stripping", *Program*, 14(3),
  pp. 130-137, July 1980, as republished at
  `https://tartarus.org/martin/PorterStemmer/def.txt`.
- Porter's ANSI C reference implementation
  (`https://tartarus.org/martin/PorterStemmer/c.txt`) for the
  machine-checkable step ordering.

## 1. Scope

Four deterministic, byte-oriented facilities over `Str` / `Vec[UInt8]`:

1. **Tokenizer** -- `nlp_tokenize` splits text into word tokens with byte
   offsets; `nlp_token_*` accessors read them safely.
2. **ASCII case** -- `nlp_lower_byte`, `nlp_lower_bytes`, `nlp_lower_str`,
   `nlp_ci_equals`, `nlp_token_equals_ci`.
3. **Sentence splitting** -- `nlp_sentences` + `nlp_sentence_*` accessors.
4. **Porter stemming** -- `nlp_stem` (lax) / `nlp_stem_checked` (strict) plus
   the public predicates `nlp_measure`, `nlp_contains_vowel`,
   `nlp_ends_with`, `nlp_ends_double_consonant`, `nlp_ends_cvc`.

Plus three statistics helpers: `nlp_total_token_length`,
`nlp_avg_token_length`, `nlp_distinct_stem_count`.

Every definition below is exactly what the code does; the 27-check
conformance suite (section 10) pins each claim.

## 2. Non-goals

- Unicode: no tables, no normalization, no case folding beyond ASCII A-Z.
  Bytes >= 128 are opaque. `nlp_lower_str` preserves them and keeps valid
  UTF-8 valid.
- Corpus linguistics features: no POS tagging, NER, lang detection,
  lemmatization, stop words, or probabilistic segmentation.
- The sentence splitter is not a grammar: no quote/parenthesis balancing,
  no ellipsis analysis, no `$`-aware abbreviation learning.
- The stemmer keeps Porter's 1980 behavior, not later "improved" variants
  (section 7.7).
- Threading, caching, and incremental/streaming APIs.

## 3. Data model

```
pub type NlpError = { code: Int; offset: Int; }

pub type NlpTokens = {
  text: Str;
  starts: Vec[Int];
  ends: Vec[Int];
}

pub type NlpSentences = {
  text: Str;
  starts: Vec[Int];
  ends: Vec[Int];
}
```

For `NlpTokens`, token `i` is `text[starts[i] .. ends[i]]` (end exclusive);
the three fields are parallel. For `NlpSentences`, sentence `i` is
`text[starts[i] .. ends[i]]`, again exclusive and parallel. Structs are
assembled only by the leaf constructors `_make_tokens` / `_make_sentences`
(XIOM v0.61.3 construction constraint, section 11).

Accessor conventions (uniform across tokens and sentences):

| accessor | out-of-range result |
|---|---|
| `*_count` | total number of entries (>= 0) |
| `*_start`, `*_end` | `-1` for `i < 0` or `i >= count` |
| `*_text` | `""` for `i < 0` or `i >= count` |
| `nlp_token_bytes` | empty vector for out-of-range `i` |
| `nlp_token_equals`, `nlp_token_equals_ci` | `false` for out-of-range `i` |

## 4. Tokenizer

Word byte: `A-Z`, `a-z`, `0-9`, or apostrophe `'` (0x27). Any other byte
(whitespace, punctuation, `_`, bytes >= 128) is a separator.

`nlp_tokenize(text)` scans left to right and emits one token per maximal run
of word bytes, recording `start` and `end` (exclusive). Consequences:

- Tokens are never empty; a lone `'` or a run like `a'b''c` is one token.
- Digits are word bytes, so `42x` is one token.
- Bytes >= 128 separate words on both sides (`a<e-acute>b` yields `a` and
  `b`), because they are not word bytes.
- The input `Str` is stored in the result; `nlp_token_text` slices it, so
  no per-token allocation happens during tokenization.

## 5. ASCII case helpers

`nlp_lower_byte(b)`: `A-Z` (0x41..0x5A) map to `a-z` by adding 32;
everything else, including bytes >= 128, is returned unchanged.

`nlp_lower_bytes(word)` returns a fresh vector of lowered bytes.
`nlp_lower_str(s)` returns a fresh `Str` built from lowered bytes; because
only A-Z change and no byte is added or removed, valid UTF-8 input stays
valid UTF-8, and no NUL byte is ever introduced.

`nlp_ci_equals(a, b)`: lengths must be equal, then each widened byte pair is
compared after `nlp_lower_byte`. `nlp_token_equals_ci(t, i, word)` is the
same comparison between token `i` and the bytes of `word`.

`nlp_token_equals(t, i, word)` is the case-sensitive comparison, done with
`compare.str_compare` (never `==` on `Str`; see section 11).

## 6. Sentence splitter

### 6.1 Terminators

Byte `i` is a **terminator** when `text[i]` is `.`, `!` or `?` and:

- `i + 1 == len`, or
- `text[i+1]` is whitespace: space, tab, LF, or CR.

### 6.2 Guards (apply to `.` only)

A terminator `.` is **suppressed** when either holds:

1. **Abbreviation guard.** `text[0 .. i+1)` ends, case-insensitively, with
   one of: `mr.`, `mrs.`, `dr.`, `ms.`, `prof.`, `st.`, `vs.`, `etc.`,
   `e.g.`, `i.e.` (the trailing dot is part of each entry). Matching is
   byte-wise after lowering, so it also covers `Mr.`, `MR.`, `e.G.`, etc.
2. **Decimal guard.** `text[i-1]` is an ASCII digit and the first
   non-whitespace byte after `i` is an ASCII digit. This keeps `3.14`
   intact (the next byte is a digit, so it is not even a terminator) and
   also keeps the malformed `3. 14` in one sentence (whitespace-skipping
   digit lookahead).

`!` and `?` have no guards: `Hi!! Really?!` ends at the last `!` that is
followed by whitespace/end, so it yields `Hi!!` and `Really?!`.

### 6.3 Spans

`nlp_sentences(text)`:

- A sentence starts at the first non-whitespace byte after the previous
  terminator (or at the first non-whitespace byte of the text). A run of
  terminators like `...` is part of the current sentence; if such a run
  starts the text, it forms a punctuation-only sentence.
- A sentence ends **after** the last terminator byte (`i + 1`), so spans
  never include the whitespace that follows a terminator.
- A final chunk with no terminator is also a sentence; trailing whitespace
  is trimmed from its span.
- Whitespace-only and empty inputs yield zero sentences, `|starts| ==
  |ends|`, and no empty spans are ever emitted.

Examples (all in the suite):

| input | sentences (text) |
|---|---|
| `One. Two! Three?` | `One.` / `Two!` / `Three?` |
| `Mr. Smith went home. He slept.` | `Mr. Smith went home.` / `He slept.` |
| `Dr. X vs. Y went to St. Louis.` | one sentence |
| `e.g. apples, i.e. pears; etc. all fruit.` | one sentence |
| `Pi is 3.14 exactly. Really.` | `Pi is 3.14 exactly.` / `Really.` |
| `It is 3. 14 percent.` | one sentence (decimal guard) |
| `Wait... What?` | `Wait...` / `What?` |
| `  Hello!  ` | `Hello!` (span `[2, 8)`) |
| `No terminator here` | one sentence `[0, 18)` |

## 7. Porter stemmer (1980)

### 7.1 Input contract

`nlp_stem` / `nlp_stem_checked` operate on `Vec[UInt8]`; the intended input
is a lowercase ASCII word (normalize with `nlp_lower_bytes` first). All byte
comparisons are exact, so no suffix containing an uppercase letter ever
matches; uppercase bytes are effectively inert. A mixed-case word can still
change when its tail is lowercase (`Cats` -> `Cat`, because the final `s` is
the rule `S -> (delete)`).

`nlp_stem` (lax) returns a copy of the input when the input is empty or
contains a byte >= 128. `nlp_stem_checked` reports those cases as errors
(section 8). Words shorter than 3 bytes are returned unchanged by both
(documented departure from the paper, section 7.7).

### 7.2 Definitions

A **consonant** is any letter other than `a`, `e`, `i`, `o`, `u`, and other
than `y` preceded by a consonant; the first byte `y` is a consonant. Runs of
`y` are resolved by parity in `_porter_cons`.

- `m` (**measure**): the number of vowel-run -> consonant-run boundaries in
  `[C](VC)^m[V]`. `nlp_measure` of `tr`, `tree`, `by` is 0; of `trouble`,
  `trees`, `ivy` is 1; of `troubles`, `private`, `orrery` is 2.
- `*v*` (**contains vowel**): some byte of the word is a vowel.
- `*d` (**ends double consonant**): the last two bytes are equal and
  consonants.
- `*o` (**ends cvc**): the last three bytes are consonant-vowel-consonant
  and the final byte is not `w`, `x` or `y`.

Each rule has the form `(condition) S1 -> S2`: if the word ends with `S1`
and the stem before `S1` satisfies the condition, replace with `S2`. Within
a step the rules are tried in the order listed, and the first matching `S1`
decides: if its condition fails, the step ends (no later rule is tried on
a shorter suffix). This matters for `rational` (matches `ational` with
`m(r)=0`, so it stays `rational` in step 2 and later loses `al` in step 4).

### 7.3 Step 1a -- plurals

| rule | example |
|---|---|
| `SSES -> SS` | `caresses -> caress` |
| `IES -> I` | `ponies -> poni`, `ties -> ti` |
| `SS -> SS` | `caress -> caress` |
| `S -> ` (delete) | `cats -> cat` |

### 7.4 Step 1b -- past tense and gerunds

| rule | condition | example |
|---|---|---|
| `EED -> EE` | `m(stem) > 0` | `agreed -> agree`; `feed -> feed` (m=0) |
| `ED -> ` (delete) | stem contains a vowel | `plastered -> plaster`; `bled -> bled` |
| `ING -> ` (delete) | stem contains a vowel | `motoring -> motor`; `sing -> sing` |

`EED` is tested first and terminates the step when it matches, so `feed`
never falls through to `ED`. After a successful `ED`/`ING` cut, exactly one
cleanup applies, in this order:

| cleanup | condition | example |
|---|---|---|
| append `E` | stem ends `AT`, `BL` or `IZ` | `conflated -> conflate` |
| drop the last byte | stem ends double consonant other than `L`, `S`, `Z` | `hopping -> hop`, `tanned -> tan`; `falling -> fall`, `hissing -> hiss`, `fizzed -> fizz` keep it |
| append `E` | `m(stem) == 1` and stem ends `*o` | `filing -> file`; `failing -> fail` |

### 7.5 Step 1c -- final y

| rule | condition | example |
|---|---|---|
| `Y -> I` | stem contains a vowel | `happy -> happi`; `sky -> sky` |

### 7.6 Steps 2-5

Step 2 (`m > 0`, first match wins): `ATIONAL -> ATE`, `TIONAL -> TION`,
`ENCI -> ENCE`, `ANCI -> ANCE`, `IZER -> IZE`, `ABLI -> ABLE`,
`ALLI -> AL`, `ENTLI -> ENT`, `ELI -> E`, `OUSLI -> OUS`,
`IZATION -> IZE`, `ATION -> ATE`, `ATOR -> ATE`, `ALISM -> AL`,
`IVENESS -> IVE`, `FULNESS -> FUL`, `OUSNESS -> OUS`, `ALITI -> AL`,
`IVITI -> IVE`, `BILITI -> BLE`.

Step 3 (`m > 0`): `ICATE -> IC`, `ATIVE -> ` (delete), `ALIZE -> AL`,
`ICITI -> IC`, `ICAL -> IC`, `FUL -> ` (delete), `NESS -> ` (delete).

Step 4 (`m > 1`, except where noted): delete `AL`, `ANCE`, `ENCE`, `ER`,
`IC`, `ABLE`, `IBLE`, `ANT`, `EMENT`, `MENT`, `ENT`; delete `ION` only when
the stem ends `S` or `T` (`m > 1`); delete `OU`, `ISM`, `ATE`, `ITI`,
`OUS`, `IVE`, `IZE`.

Step 5a: delete final `E` when `m > 1`, or when `m == 1` and the stem does
not end `*o` (`probate -> probat`, `rate -> rate`, `cease -> ceas`).

Step 5b: delete one final `L` when `m > 1` and the word ends `*d` and `L`
(`controll -> control`, `roll -> roll`).

The suite exercises every step with the paper's own examples; the final
outputs after all steps are asserted (e.g. `relational -> relat`,
`conditional -> condit`, `valenci -> valenc`, `vietnamization -> vietnam`,
`predication -> predic`, `decisiveness -> decis`, `sensibiliti -> sensibl`,
`electriciti -> electr`, `gyroscopic -> gyroscop`, `adoption -> adopt`).

### 7.7 Documented decisions and departures

1. **`ties -> ti`.** The 1980 paper's step-1a example list contains
   `ties -> ti` (unconditional `IES -> I`), and the reference C
   implementation agrees. Some later vocabularies (notably the Porter data
   shipped with NLTK, and Snowball's English stemmer) instead produce
   `ties -> tie` via an extra "stem longer than one letter" condition. This
   package implements the 1980 paper: **`ties -> ti`**; the conformance test
   says so explicitly.
2. **No `BLI`/`LOGI` rules.** The 1980 paper has `ABLI -> ABLE` (used
   here). `BLI -> BLE` and `OGI/LOGI -> OG/LOG` are later departures in
   Porter's reference C code and are intentionally absent.
3. **Words shorter than 3 bytes are unchanged.** A deliberate leniency
   (matching `xiom.stemming`, the sibling package): shorter words cannot
   carry the suffixes above, and this keeps `nlp_distinct_stem_count`
   stable on fragments.
4. **Measure uses VC transitions directly.** `_measure_to` counts
   vowel-run -> consonant-run boundaries, which equals `m` in
   `[C](VC)^m[V]` (verified against the paper's own m examples).
5. **Determinism.** No locale, no dictionary, no random component.

## 8. Errors

`NlpError { code, offset }`, read with `nlp_error_code` /
`nlp_error_offset`. `nlp_stem_checked` is the only error-producing entry
point:

| code | meaning | offset |
|---|---|---|
| 1 | input contains a byte >= 128 | index of the first such byte |
| 2 | input is empty | 0 |

`nlp_stem` never errors: it returns a copy of the input for both cases.
`nlp_tokenize` and `nlp_sentences` cannot fail; every input `Str` is valid.

## 9. Statistics

- `nlp_total_token_length(t)`: sum of `ends[i] - starts[i]` (bytes).
- `nlp_avg_token_length(t)`: `total / count` with truncating integer
  division (e.g. 14 bytes over 4 tokens -> 3); `0` when `count == 0`.
- `nlp_distinct_stem_count(t)`: lowercases and stems every token once
  (O(total bytes)), appends the stems to one flat buffer with parallel
  offset/length vectors, then compares every pair of earlier stems
  byte-wise. Comparison count is `n*(n-1)/2`, so the helper is bounded
  **O(n^2)** byte comparisons; it is a convenience, not an index.
  Tokens that stem to the same bytes count once (`Dogs dog cat cats` -> 2;
  `Run running RUNS` -> 1).

## 10. Conformance suite (`tests/test_conformance.xi`, 27 checks)

| # | area | check |
|---|---|---|
| 1-3 | tokenizer | offsets/text; apostrophes+digits; empty/separator-only |
| 4-5 | tokenizer | bytes >= 128 separate; out-of-range accessors |
| 6-7 | case | token equality (ci/cs); lower + non-ASCII passthrough + ci_equals |
| 8 | sentences | terminators, offsets, texts |
| 9-10 | sentences | `Mr./Mrs./Dr./Ms./Prof./St./vs.`; `e.g./i.e./etc.` |
| 11-14 | sentences | decimals (`3.14`, `3. 14`); tail/whitespace/trim; repeated terminators; out-of-range |
| 15-18 | porter 1a-1c | paper examples incl. `ties -> ti`, `feed -> feed`, `filing -> file` |
| 19-21 | porter 2 | every `m>0` rule (incl. downstream steps' effects) |
| 22-24 | porter 3-5b | every step-3/4 rule and 5a/5b behavior |
| 25 | predicates | measure, contains-vowel, ends-with, *d, *o, empty input |
| 26 | stemmer | error codes/offsets, lax passthrough, mixed-case |
| 27 | statistics | count, total/avg length, distinct stems |

Run: `xiom --run tests/test_conformance.xi` (or `.\scripts\port.ps1
-Package xiom.nlp`). Expected: 27 `[PASS]`, exit 0.

## 11. XIOM v0.61.3 implementation notes

- Free functions only; no methods on user types, no lambdas, no function
  values (so `Vec[fn]` dispatch and generic callbacks are avoided by
  design).
- `Str` values are compared with `xiom.string.compare.str_compare`, never
  `==` (BUG 17 mis-lowers `==` on `Str` read from `Vec[Str]` elements).
- `Ok`/`Err` for `Result[Vec[UInt8], NlpError]` are constructed only in
  the leaf helpers `_ok_stem` / `_err_stem`.
- Struct values are assembled only in `_make_tokens` / `_make_sentences`.
- Vec elements are read through typed locals; bytes widened to `Int` are
  masked with `0xFF` before comparisons involving values >= 128.
- `&mut` out-parameters miscompile in this toolchain, so every word
  transformation returns a fresh `Vec[UInt8]`.
- No `Vec[Float64]` (average token length is an `Int`), no struct-typed
  `Vec` fields (documents are parallel `Vec`s), and no function named
  `log`.

## 12. License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
