# xiom.translate -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.translate` (`src/translate.xi`). Pure XIOM, no FFI, no network.
Everything below is exactly what the code does; the 28-check conformance
suite (`tests/test_conformance.xi`) pins each claim.

## 1. Scope

Four deterministic offline facilities over `Str`:

1. **Phrasebook** -- `translate_term`, `translate_term_checked`,
   `translate_apply` over a fixed in-package concept table (4 languages,
   22 concepts). `translate_pair_supported`, `translate_languages`,
   `translate_terms`, `translate_concept_count` describe the table.
2. **Source language detection** -- `detect_language`,
   `detect_language_score`, `detect_language_supported`,
   `detect_language_count` over six languages.
3. **Script transliteration** -- `translit_cyrillic_to_latin`,
   `translit_latin_to_cyrillic`, `translit_greek_to_latin`,
   `translit_latin_to_greek` for the documented Cyrillic and Greek subsets.
4. **Domain glossary** -- an immutable `Glossary` value with
   `glossary_new`, `glossary_add`, `glossary_lookup`, `glossary_has`,
   `glossary_len`, `glossary_apply`.

Purity: no network, services, locale, clock or randomness. Identical input
yields identical output.

## 2. Non-goals

- No machine translation, corpora or statistical models; the phrasebook is
  a closed term list and out-of-list terms return `""` / are left unchanged.
- No Unicode normalization, case folding beyond ASCII A-Z, or segmentation
  beyond maximal ASCII-letter runs. Bytes >= 128 are opaque (except where a
  transliteration table explicitly covers the code point).
- No encoding conversion (UTF-8 in, UTF-8 out); no file or stream I/O.
- No locale-dependent rules, no external tables, no mutable global state.

## 3. Phrasebook

### 3.1 Languages and pairs

Language codes: `en`, `fr`, `de`, `es` (ids 0..3). A pair code has the form
`src-tgt` with exactly one hyphen; valid pairs are the 12 directed pairs in
which both sides are known and different. `translate_pair_supported`
returns `false` for malformed codes (`""`, `"en"`, `"en-fr-x"`), unknown
codes and equal languages (`"en-en"`).

### 3.2 Concepts

| # | en | fr | de | es |
|---|---|---|---|---|
| 0 | hello | bonjour | hallo | hola |
| 1 | goodbye | aurevoir | tschuess | adios |
| 2 | please | silvousplait | bitte | porfavor |
| 3 | thanks | merci | danke | gracias |
| 4 | yes | oui | ja | si |
| 5 | no | non | nein | no |
| 6 | good | bon | gut | bueno |
| 7 | morning | matin | morgen | manana |
| 8 | night | nuit | nacht | noche |
| 9 | water | eau | wasser | agua |
| 10 | bread | pain | brot | pan |
| 11 | friend | ami | freund | amigo |
| 12 | house | maison | haus | casa |
| 13 | book | livre | buch | libro |
| 14 | city | ville | stadt | ciudad |
| 15 | name | nom | name | nombre |
| 16 | love | amour | liebe | amor |
| 17 | welcome | bienvenue | willkommen | bienvenido |
| 18 | sorry | desole | entschuldigung | perdona |
| 19 | one | un | eins | uno |
| 20 | two | deux | zwei | dos |
| 21 | three | trois | drei | tres |

Spellings are ASCII-folded; every entry is lowercase. The table is shared,
so any pair (including `fr-es`, `de-es`) pivots through the concept id.

### 3.3 Semantics

- `translate_term(pair, term)`: term lookup is case-insensitive (ASCII).
  The case shape of `term` is re-applied to the stored target: all-uppercase
  input yields an all-uppercase result, a leading uppercase yields a
  capitalized result, otherwise the stored lowercase form is returned.
  `"Hello" -> "Bonjour"`, `"HELLO" -> "BONJOUR"`, `"hELLO" -> "bonjour"`.
  Returns `""` for unknown pair or unknown term.
- `translate_term_checked(pair, term)`: `Ok(translation)` on success;
  `Err(1)` unknown/malformed pair or equal languages; `Err(2)` term not in
  the phrasebook. Payload is `Result[Str, Int]` (scalar).
- `translate_apply(pair, text)`: scans `text` left to right; a **word** is a
  maximal run of ASCII letters (`A-Z`, `a-z`). Each word is looked up
  case-insensitively and, when found, replaced with the case-adjusted
  target; unknown words and every non-letter byte (digits, punctuation,
  bytes >= 128, whitespace) are copied through unchanged. An unsupported
  pair returns `text` unchanged. Empty text returns `""`.
- `translate_terms()` returns the 22 English terms comma-separated in
  concept order; `translate_languages()` returns `"en,fr,de,es"`;
  `translate_concept_count()` returns 22.

## 4. Source language detection

### 4.1 Languages and API

Supported codes, in fixed order: `en`, `de`, `fr`, `es`, `it`, `nl` (ids
0..5). `detect_language_count()` returns 6;
`detect_language_supported()` returns `"en,de,fr,es,it,nl"`.

`detect_language(text)` returns the best-scoring code, or `""` when the
best score is 0 (empty input, digits/punctuation only, no feature match).
Ties are resolved by the fixed order above (the first language with the
strictly highest score wins). `detect_language_score(text, lang)` returns
the integer score for one code (0 for an unknown code).

### 4.2 Scoring

```
score(lang) = 8 * stopword_hits
            + sum(weight * ngram_occurrences)
            + distinctive_character_score
```

- **stopword_hits**: the number of maximal ASCII-letter tokens whose
  lowercase form exactly equals one of the language's stopwords. A byte
  >= 128 splits tokens, so it never glues a token together. Single-letter
  stopwords are deliberately absent (token splitting would make them
  noise). Weight 8 per hit.
- **ngram_occurrences**: case-insensitive, overlapping substring counts
  over the raw bytes (`_count_ci`); a feature may be counted inside a
  longer word. Weights as listed.

| lang | stopwords | n-gram weights |
|---|---|---|
| en | the, and, of, in, is, it, for, with, this, that, on, as, at, be, to | the 4, and 4, ing 3, ion 2, th 2, he 2, of 2 |
| de | der, die, das, und, ein, eine, ist, mit, von, den, zu, im, in, auf, nicht, sich | sch 4, der 4, die 4, und 4, ein 3, ich 3, ch 2, ei 2, ie 2, st 1 |
| fr | le, la, les, de, des, un, une, et, est, dans, avec, pour, que, qui, pas, sur | qu 3, le 3, la 3, de 3, un 3, ent 3, es 2, ai 2, oi 2, on 2 |
| es | el, la, los, las, de, un, una, es, en, con, por, que, para, no, se | acion 4, el 3, la 3, os 3, as 3, de 2, en 2, qu 2, ll 2, ue 2 |
| it | il, lo, la, gli, le, di, un, una, che, con, per, in, non, si | gli 4, zione 4, che 3, gh 3, il 3, la 3, di 3, ch 2, tt 2, ss 2 |
| nl | de, het, een, van, en, is, in, op, dat, met, voor, niet, zijn, er | ij 4, het 4, een 4, van 3, de 3, sch 3, ui 3, aa 2, ee 2, oo 2 |

- **distinctive_character_score** (`_count_exact`, byte-exact UTF-8
  markers): de: `ß` 6, `ä` 3, `ö` 3, `ü` 3; fr: `ç` 5, `é` 3, `è` 3,
  `ê` 2, `à` 2, `ù` 1; es: `ñ` 6, `¿` 4, `¡` 4; it: `ì` 3, `ò` 3, `ù` 3;
  en and nl: none.

The suite pins sample sentences for all six languages plus the
no-signal, distinctive-character (`Straße`, `señor`, `München`) and
score-ordering cases. Detection is best-effort feature scoring, not a
classifier guarantee; documented ties resolve deterministically as above.

## 5. Script transliteration

All four functions return a fresh `Str`; they never fail. ASCII bytes
pass through unchanged in the two `*_to_latin` functions; non-letters pass
through unchanged in the two `latin_to_*` functions. Invalid UTF-8 is
copied one byte at a time. A valid but uncovered code point is copied
verbatim. Output is built in a local byte buffer and materialized with the
string builder (no NUL byte can occur).

### 5.1 Cyrillic -> Latin

Coverage: `U+0401` (Ё), `U+0410..U+044F` (А..я), `U+0451` (ё).

| | | | | | |
|---|---|---|---|---|---|
| А A | Б B | В V | Г G | Д D | Е E |
| Ж Zh | З Z | И I | Й Y | К K | Л L |
| М M | Н N | О O | П P | Р R | С S |
| Т T | У U | Ф F | Х Kh | Ц Ts | Ч Ch |
| Ш Sh | Щ Shch | Ъ (nothing) | Ы Y | Ь (nothing) | Э E |
| Ю Yu | Я Ya | Ё E | | | |

Lowercase letters map to the lowercase forms (`ж -> zh`, `щ -> shch`,
`ъ`/`ь` -> nothing, `ё -> e`, ...). Example: `Привет -> Privet`,
`Щука -> Shchuka`, `объект -> obekt`, `мягкий -> myagkiy`.

### 5.2 Latin -> Cyrillic

Longest match first, case-insensitive; the case of the first input letter
is applied to the first output letter (`Shchuka -> Щука`), the remaining
output letters stay lowercase.

Digraphs: `shch -> щ`, `sh -> ш`, `ch -> ч`, `zh -> ж`, `kh -> х`,
`ts -> ц`, `yu -> ю`, `ya -> я`, `yo -> ё`, `ye -> е`.

Single letters: `a а`, `b б`, `c ц`, `d д`, `e е`, `f ф`, `g г`, `h х`,
`i и`, `j й`, `k к`, `l л`, `m м`, `n н`, `o о`, `p п`, `q к`, `r р`,
`s с`, `t т`, `u у`, `v в`, `w в`, `x кс`, `y й`, `z з`; apostrophe `'`
maps to the soft sign `ь`.

Documented consequences: `x` expands to two letters (`Кс` when
capitalized); `ye` wins over `y`+`e` (`obyekt -> обект`); only the listed
digraphs are recognized (`schule -> сцуле`).

### 5.3 Greek -> Latin

Coverage: `U+0391..U+03A9` (letters; unassigned `U+03A2` excluded),
`U+03B1..U+03C9` (letters, including final sigma `U+03C2`), and the tonos
vowels `U+03AC`, `U+03AD`, `U+03AE`, `U+03AF`, `U+03CC`, `U+03CD`,
`U+03CE`.

Mapping: Α A, Β B, Γ G, Δ D, Ε E, Ζ Z, Η I, Θ Th, Ι I, Κ K, Λ L, Μ M,
Ν N, Ξ X, Ο O, Π P, Ρ R, Σ S, Τ T, Υ Y, Φ F, Χ Ch, Ψ Ps, Ω O; lowercase
counterparts (`θ th`, `φ f`, `χ ch`, `ψ ps`, `η i`, `υ u`, `ω o`); final
sigma `ς -> s`; tonos vowels map to the base vowel (`ά a`, `ή i`,
`ύ u`, ...). Examples: `Ελλάδα -> Ellada`, `θάλασσα -> thalassa`,
`λόγος -> logos`, `Ξάνθη -> Xanthi`, `ψυχή -> psuchi`.

### 5.4 Latin -> Greek

Longest match first, case-insensitive; first-letter case rule as above.

Digraphs: `th -> θ`, `ph -> φ`, `ch -> χ`, `ps -> ψ`, `ks -> ξ`,
`kh -> χ`, `ou -> ου`.

Single letters: `a α`, `b β`, `c κ`, `d δ`, `e ε`, `f φ`, `g γ`, `h η`,
`i ι`, `j ι`, `k κ`, `l λ`, `m μ`, `n ν`, `o ο`, `p π`, `q κ`, `r ρ`,
`s σ`, `t τ`, `u υ`, `v β`, `w ω`, `x ξ`, `y υ`, `z ζ`.

`s` always yields `σ` (never final sigma); accents are not produced, so
`translit_latin_to_greek(translit_greek_to_latin(s))` is accent-free
(`θάλασσα -> θαλασσα`).

## 6. Glossary

`Glossary` is an immutable value wrapping one record blob:
`"source\ttarget\n"` per entry, fields separated by a tab (0x09), records
terminated by a newline (0x0A). There is no mutable global state.

- `glossary_new()` returns the empty glossary.
- `glossary_add(g, src, tgt)` returns a new glossary with the entry
  appended. An empty `src`, or any `\t`/`\n` inside `src` or `tgt`, leaves
  the glossary unchanged (documented rejection, not an error code). Adding
  a duplicate source appends; lookups return the **most recently added**
  match.
- `glossary_len(g)` counts records.
- `glossary_lookup(g, src)` returns the stored target for `src`
  (case-insensitive ASCII match), or `""` when absent.
- `glossary_has(g, src)` is `true` when an entry exists (even if its
  target is empty).
- `glossary_apply(g, text)` replaces each maximal ASCII-letter word that
  matches a stored source (case-insensitively) by the stored target
  exactly as added; unmatched words and all non-letter bytes are copied
  through.

Example: `network -> reseau`, then
`glossary_apply(g, "The network and the file.")` with
`file -> fichier` yields `"The reseau and the fichier."`.

## 7. Errors

Only `translate_term_checked` reports errors, as `Result[Str, Int]`:

| code | meaning |
|---|---|
| 1 | unknown/malformed pair code, or equal languages (e.g. `en-en`) |
| 2 | term not present in the phrasebook |

Every other entry point is total: empty-string conventions and pass-through
behavior are documented above.

## 8. Conformance suite (`tests/test_conformance.xi`, 28 checks)

| # | area | check |
|---|---|---|
| 1 | phrasebook | pair support: 12 directed pairs; malformed/equal refused |
| 2-4 | phrasebook | en-fr/fr-en, en-de/de-en, pivot pairs (en-es, de-es, fr-es) |
| 5-7 | phrasebook | case re-application; unknown term/pair; checked Err(1)/Err(2) |
| 8-11 | phrasebook | apply: punctuation, unknown words kept, bad pair, newline/empty, listings |
| 12-17 | detection | one full sentence per language (en, de, fr, es, it, nl) |
| 18 | detection | no-signal/empty, unknown code, supported list/count |
| 19-20 | detection | distinctive characters; score ordering + determinism |
| 21-22 | cyrillic | basic words; digraphs, Yo, hard/soft sign dropped |
| 23-24 | cyrillic | Latin->Cyrillic basic + case; longest-match digraphs |
| 25-26 | greek | Greek->Latin; Latin->Greek + accent-free round trip |
| 27 | translit | empty, ASCII passthrough, invalid-byte passthrough |
| 28 | glossary | add/len/ci lookup/has/duplicate/apply/rejected entries |

Run: `xiom --run tests/test_conformance.xi` (or
`.\scripts\port.ps1 -Package xiom-translate`). Expected: 28 `[PASS]`,
exit 0.

## 9. XIOM v0.62.2 implementation notes

- Free functions only; no methods on user types, no lambdas, no function
  values, no `Vec[Str]`, no `Vec[StructType]` (the glossary is a single
  `Str` blob, not a vector of pairs).
- All `Str` equality uses `compare.str_compare`; Vec/Vec[UInt8] elements
  are read through typed locals; `UInt8 -> Int` widening is masked with
  `0xFF`.
- The builder buffer is threaded with an explicit `&mut` at every call
  site; output is materialized with `sb_to_str` (its NUL limitation is
  avoided because a `Str` cannot carry an interior NUL).
- All generic types are written with square brackets (`Vec[UInt8]`,
  `Result[Str, Int]`); the post-write/post-green mixed-bracket grep is
  clean.
- Determinism: tables are if/elif chains over literals; no module-level
  mutable state.

## 10. License

MIT OR Apache-2.0 (see the repository root licenses).
