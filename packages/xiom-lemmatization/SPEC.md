# xiom.lemmatization -- specification

## Scope

`xiom.lemmatization` is a deterministic, rule-based lemmatizer for ASCII
English tokens, implemented entirely in XIOM (no FFI, no data files). It
exposes a POS-tagged single-word entry point, a batch entry point over token
vectors, and an irregular-membership predicate.

In scope:

- ASCII-letter tokens, case-normalised for matching,
- a curated irregular-form map (noun / verb / adjective),
- a small exception dictionary for forms the suffix rules miss,
- ordered, longest-suffix-first suffix rules selected by POS (`n`, `v`, `a`),
- casing restoration for lowercase, `Capitalized` and ALL-CAPS input.

Out of scope:

- tokenisation, sentence segmentation, POS tagging, parsing,
- Unicode normalisation, non-ASCII scripts, stemming (see `xiom.stemming`),
- probabilistic / corpus-trained lemmatization or a full lexicon.

## Input contract

| Input | Result |
|---|---|
| `""` | `""` |
| any byte outside ASCII letters (digit, punctuation, non-ASCII) | returned unchanged |
| all lowercase letters | processed, lowercase result |
| `Capitalized` (one uppercase + lowercase rest) | processed, first letter uppercased |
| ALL-CAPS letters | processed, whole result uppercased |
| mixed case (`iPhone`) | returned unchanged |

## Pipeline

1. **Guard.** Empty input returns `""`. A token containing any byte outside
   `A-Z`/`a-z` is returned unchanged. Mixed-case tokens are returned
   unchanged. Otherwise the token is lowercased for matching.
2. **Irregular map.** The POS-specific irregular table is consulted first.
3. **Exception dictionary.** If the irregular map misses, the shared
   exception dictionary is consulted.
4. **Suffix rules.** If both miss, the POS rule set is applied.
5. **Casing.** The result is re-cased to match the input class.

An exact table hit stops the pipeline at step 2 or 3: no suffix rule runs
afterwards.

## POS selection

`lemmatize(word, pos)` selects one table set:

| `pos` | Irregular table | Rule set |
|---|---|---|
| `"v"` | verb | verb rules |
| `"a"` | adjective | adjective rules |
| `"n"` or anything else | noun | noun rules |

`lemmatize_is_irregular(word)` checks all three tables regardless of POS.

## Noun rules (applied in this order)

For an already-lowercased ASCII word, the first matching rule wins:

| # | Condition | Action |
|---|---|---|
| 1 | length >= 4 and ends `ies` | replace `ies` with `y` (`stories -> story`) |
| 2 | ends `ves` | drop final `s` (`curves -> curve`); the true `-f`/`-fe` plurals are in the irregular map |
| 3 | ends `ches` or `shes` (length >= 4) | remove `es` (`churches -> church`) |
| 4 | ends `sses`, `xes` or `zes` (length >= 4) | remove `es` (`boxes -> box`) |
| 5 | ends `oes` and is a known `-o` plural | return the table singular (`heroes -> hero`) |
| 6 | ends `oes` otherwise | drop final `s` (`shoes -> shoe`) |
| 7 | ends `ss` | unchanged (`glass`) |
| 8 | ends `us` | unchanged (`bus`, `status`) |
| 9 | ends `is` | unchanged (`analysis`) |
| 10 | length >= 3 and ends `s` | drop final `s` (`cats -> cat`, `houses -> house`) |
| 11 | otherwise | unchanged |

## Verb rules (applied in this order)

| # | Condition | Action |
|---|---|---|
| 1 | length >= 4 and ends `ies` | replace `ies` with `y` (`studies -> study`) |
| 2 | length >= 5, ends `ing`, stem length >= 2 and stem has a vowel | restore base from the stem |
| 3 | length >= 4 and ends `ied` | replace `ied` with `y` (`tried -> try`) |
| 4 | length >= 4, ends `ed`, stem length >= 2 and stem has a vowel | restore base from the stem |
| 5 | ends `ches` or `shes` (length >= 4) | remove `es` (`watches -> watch`) |
| 6 | ends `sses`, `xes` or `zes` (length >= 4) | remove `es` (`fixes -> fix`) |
| 7 | ends `ss` | unchanged (`pass`) |
| 8 | ends `us` | unchanged (`focus`) |
| 9 | ends `is` | unchanged |
| 10 | length >= 3 and ends `s` | drop final `s` (`runs -> run`) |
| 11 | otherwise | unchanged |

`-ing`/`-ed` base restoration, in order:

1. a final double consonant loses one letter unless it is `l`, `s` or `z`
   (`running -> run`, `falling -> fall`, `passing -> pass`),
2. else a `consonant-vowel-consonant` stem with exactly one vowel gains a
   final `e` (`hoping -> hope`, `making -> make`; `opening -> open` because it
   has two vowels),
3. else a stem ending in `v` preceded by a consonant gains `e`
   (`solving -> solve`),
4. else a stem ending in `c` gains `e` (`danced -> dance`).

## Adjective rules (applied in this order)

| # | Condition | Action |
|---|---|---|
| 1 | length >= 5 and ends `iest` | replace `iest` with `y` (`happiest -> happy`) |
| 2 | length >= 4 and ends `ier` | replace `ier` with `y` (`happier -> happy`) |
| 3 | length >= 4 and ends `est` | base from stem (`biggest -> big`) |
| 4 | length >= 3 and ends `er` | base from stem (`bigger -> big`) |
| 5 | otherwise | unchanged |

Adjective base restoration, in order:

1. a final double consonant loses one letter unless it is `l`, `s` or `z`
   (`bigger -> big`, `taller -> tall`),
2. else a CVC stem with exactly one vowel gains `e` (`nicer -> nice`),
3. else a stem ending in single `l` after a consonant gains `e`
   (`simpler -> simple`),
4. else the stem is returned (`older -> old`).

## Irregular handling as implemented

The irregular map is three explicit tables, scanned in source order with
`str_compare`:

- **Nouns**: suppletive and vowel-changing plurals (`men`, `women`,
  `children`, `teeth`, `feet`, `mice`, `geese`, `oxen`, `people`) and the
  `-f`/`-fe` plurals (`knives`, `wives`, `lives`, `wolves`, `leaves`,
  `halves`, `shelves`, `calves`, `loaves`, `thieves`, `scarves`, `selves`,
  `elves`, `hooves`), plus the irregular Greek/Latin plurals (`analyses`,
  `crises`, `theses`, `hypotheses`, `diagnoses`, `indices`, `matrices`,
  `vertices`, `criteria`, `phenomena`).
- **Verbs**: strong and suppletive forms (`went`/`gone`/`goes -> go`,
  `was`/`were`/`is`/`are`/`am`/`been -> be`, `had`/`has -> have`,
  `did`/`done`/`does -> do`, and the past/participle pairs for
  run, come, see, eat, give, take, make, write, speak, choose, drive, fall,
  feel, fly, forget, freeze, grow, hear, hide, know, ride, ring, sing, sink,
  shoot, show, steal, swim, throw, wake, buy, bring, catch, draw, drink,
  lead, lend, light, mean, say, find, get, hold, keep, leave, lose, meet,
  pay, put, read, rise, sell, send, sit, sleep, spend, stand, teach, tell,
  think, wear, win).
- **Adjectives**: `better`/`best -> good`, `worse`/`worst -> bad`,
  `further`/`furthest`/`farther`/`farthest -> far`, `elder`/`eldest -> old`,
  `more`/`most -> much`, `less`/`least -> little`.

The shared **exception dictionary** supplies forms whose correct lemma the
suffix rules would miss, including: `agreed -> agree`, `freed -> free`,
`guaranteed -> guarantee`, `used`/`using -> use`, `becoming -> become`,
`leaving -> leave`, `believed`/`believing -> believe`,
`received`/`receiving -> receive`, `achieved`/`achieving -> achieve`,
`died`/`dies`/`dying -> die`, `tied`/`ties`/`tying -> tie`,
`lied`/`lies`/`lying -> lie`, `vied`/`vies`/`vying -> vie`,
`changed`/`changing -> change`, `arranged`/`arranging -> arrange`,
`managed`/`managing -> manage`, `judged`/`judging -> judge`,
`imagined`/`imagining -> imagine`, `damaged`/`damaging -> damage`,
`controlled`/`controlling -> control`, `travelled`/`travelling -> travel`,
`cancelled`/`cancelling -> cancel`, `added -> add`, `movies -> movie`,
`cookies -> cookie`, `pies -> pie`, `series -> series`, `species -> species`,
`news -> news`, `gas -> gas`, `yes -> yes`, `physics -> physics`,
`buses -> bus`, `gases -> gas`, `statuses -> status`, `quizzes -> quiz`,
`larger`/`largest -> large`, `stranger`/`strangest -> strange`,
`simpler`/`simplest -> simple`, `gentler`/`gentlest -> gentle`,
`humbler`/`humblest -> humble`, `idler`/`idlest -> idle`.

## API

### `pub fn lemmatize(word: Str, pos: Str) -> Str`

Returns the lemma of `word` under the POS `pos` (`"n"`, `"v"`, `"a"`; any
other value selects noun rules). Non-letter and mixed-case tokens are
returned unchanged. Total: no error paths.

### `pub fn lemmatize_all(words: &Vec[Str], tags: &Vec[Str]) -> Vec[Str]`

Returns a fresh vector of the same length as `words`. Token `i` uses tag
`tags[i]`; if `i >= tags.len()` the tag defaults to `"n"`. Extra tags beyond
`words.len()` are ignored. Order is preserved.

### `pub fn lemmatize_is_irregular(word: Str) -> Bool`

True when the lowercased word hits any of the three irregular tables. False
for the empty string, non-letter tokens, and words handled only by suffix
rules (`cats`, `running`).

## Determinism

All tables are fixed and scanned in source order; all comparisons go through
`xiom.string.compare.str_compare`; no hash maps, randomness, locale or I/O are
involved. The output is a pure function of `(word, pos)`.

## Test plan

`tests/test_conformance.xi` contains 44 named checks covering: irregular
nouns, the `be`/`have`/`do`/`go` verbs and strong-verb pairs, irregular
adjectives, POS-scoped irregulars (`lives`, `leaves`), noun `-ies`/`-ves`/
sibilant `-es`/`-oes`/`-s` rules and guards, irregular `-ses` plurals, verb
`-ies`/`-ing`/`-ed`/`-s` rules including double-consonant, CVC `+e`,
silent-`e` and `-ied` restoration, adjective `-er`/`-ier`/`-est` rules, rule
precedence, unknown words, casing restoration, non-letter pass-through,
default POS selection, the batch API (including tag-vector length mismatch
and empty input), and the irregular predicate.

Run it with:

```
.\scripts\port.ps1 -Package xiom.lemmatization
```

## Limitations

- ASCII English only; non-letter tokens pass through unchanged.
- The tables are curated, not exhaustive; rare irregulars and ambiguous
  forms (`bases`, `axes`, `politer`) may be wrong.
- Rule ordering is heuristic and tuned for the fixtures above; it is not a
  substitute for a POS tagger or a full morphological lexicon.
- No sentence context: POS is always caller-supplied.
