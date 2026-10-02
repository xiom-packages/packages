# xiom.translate

> **Status:** `incubating` -- conformance-tested (28/28); published at `v0.1.0` on the XIOM registry.

Pure-XIOM, offline translation core: an in-package phrasebook, source
language detection, script transliteration and domain glossaries. No
network, no translation services, no locale, no clocks, no randomness --
every function is deterministic and every table lives in `src/translate.xi`.

- **Manifest name:** `xiom.translate` (version 0.1.0, category `l10n`)
- **Module:** `xiom.translate` (`src/translate.xi`)
- **Deps:** `xiom.std` only
- **Tests:** `tests/test_conformance.xi` (28 deterministic checks, no
  external files)

## What is covered (precise subsets)

| Area | Coverage |
|---|---|
| Phrasebook | 22 everyday concepts in `en`, `fr`, `de`, `es`; all 12 directed cross-language pairs |
| Detection | 6 languages: `en`, `de`, `fr`, `es`, `it`, `nl` |
| Transliteration | Cyrillic `U+0401`, `U+0410..U+044F`, `U+0451` <-> Latin; Greek letters + tonos vowels <-> Latin |
| Glossary | In-value term map: add / length / case-insensitive lookup / has / whole-word apply |

The exact tables, weights, error codes and edge-case rules are in
[SPEC.md](SPEC.md). Nothing outside those subsets is claimed: unmapped
characters pass through, unknown terms are returned unchanged, and
`detect_language` returns `""` when no feature matches.

## Quick start

```xi
use xiom.translate;

// Phrasebook
translate_term("en-fr", "hello")        // "bonjour"
translate_term("en-fr", "Hello")        // "Bonjour"  (case re-applied)
translate_apply("en-fr", "hello friend!") // "bonjour ami!"

// Checked variant: Err(1) unknown pair, Err(2) term not found
match translate_term_checked("en-de", "water") {
  Ok(v) => { /* "wasser" */ },
  Err(c) => { /* 1 or 2 */ },
};

// Detection
detect_language("The quick brown fox and the lazy dog")  // "en"
detect_language_score("Straße", "de")                    // > 0

// Script conversion
translit_cyrillic_to_latin("Привет")   // "Privet"
translit_latin_to_cyrillic("Yuriy")    // "Юрий"
translit_greek_to_latin("Ελλάδα")      // "Ellada"
translit_latin_to_greek("thema")       // "θεμα"

// Glossary
var g = glossary_new();
g = glossary_add(&g, "network", "reseau");
glossary_lookup(&g, "NETWORK")                 // "reseau"
glossary_apply(&g, "The network is up.")       // "The reseau is up."
```

## Limitations

- The phrasebook is a small fixed term list, not machine translation; it
  answers only the 22 concepts and returns `""` otherwise.
- Detection is feature scoring over a documented vocabulary and n-gram set,
  not a statistical model; short or ambiguous text can tie, in which case
  the fixed order `en, de, fr, es, it, nl` decides.
- Transliteration maps a documented subset; Latin-to-Cyrillic/Greek
  recognizes only the listed digraphs (e.g. `shch`, `zh`, `th`, `ph`) and
  is not reversible in every case (accents, final sigma, hard/soft signs).
- Glossary entries containing `\t` or `\n`, and empty sources, are rejected
  by leaving the glossary unchanged.

## Test

```
.\scripts\port.ps1 -Package xiom-translate
```

Expected: `port: PASS (passed=28 failed=0 program_exit=0)`.

## License

MIT OR Apache-2.0 (see the repository root licenses).
