# xiom.plural -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.plural` (`src/plural.xi`). Manifest: `package.xi` (name
`xiom.plural`, version `0.1.0`). Depends on `xiom.std` (`xiom.string`,
`xiom.string.compare`, `xiom.string.lowercase`, `xiom.string.uppercase`,
`xiom.convert`).

## Scope

English singular <-> plural inflection for lowercase ASCII words:

- irregular pairs in both directions (person/people, child/children, ...);
- invariant nouns (sheep, deer, fish, series, species);
- ordered suffix rules for pluralization and singularization, including the
  `-f`/`-fe` -> `-ves` and `-o` -> `-oes` lists with their exceptions;
- initial-capitalization preservation (`City` -> `Cities`);
- count-aware noun phrases (`plural_count`);
- element-wise pluralization of a word vector (`plural_pluralize_all`).

## Non-goals

- Full English morphology or a dictionary: unknown words get a best-effort
  suffix-rule result.
- Non-ASCII input, multi-word phrases, proper-noun dictionaries, or
  hyphenated compounds.
- Verb conjugation, adjective comparison, or any inflection other than noun
  number.
- CLDR plural categories / locale-aware count rules.
- Error reporting: every function is total, with no `Result`/`Option` and no
  panicking inputs.
- Runtime-extensible rule tables or pluggable languages.

## Input contract

- Input is a lowercase ASCII English word. Uppercase input is accepted and
  case-folded for matching.
- If the input starts with an uppercase ASCII letter (byte 65..90), the first
  character of the result is uppercased; the remaining characters are
  lowercase (only initial capitalization is preserved).
- The empty string maps to the empty string in every function.

## API signatures

All functions are free functions in module `xiom.plural`:

```xi
pub fn plural_pluralize(word: Str) -> Str
pub fn plural_singularize(word: Str) -> Str
pub fn plural_is_irregular(word: Str) -> Bool
pub fn plural_count(n: Int, singular: Str) -> Str
pub fn plural_pluralize_all(words: &Vec[Str]) -> Vec[Str]
```

## Rule tables

### Irregular pairs (both directions)

| Singular | Plural | | Singular | Plural |
|---|---|---|---|---|
| person | people | | basis | bases |
| man | men | | crisis | crises |
| woman | women | | thesis | theses |
| child | children | | index | indices |
| tooth | teeth | | matrix | matrices |
| foot | feet | | vertex | vertices |
| mouse | mice | | appendix | appendices |
| goose | geese | | datum | data |
| ox | oxen | | medium | media |
| analysis | analyses | | | |

`plural_is_irregular` returns true when the lowercase word is any key or
value above, or an invariant noun.

### Invariant nouns

`sheep`, `deer`, `fish`, `series`, `species` -- returned unchanged by both
`plural_pluralize` and `plural_singularize`.

### Pluralization rules (in order)

1. irregular table hit -> table value;
2. invariant word -> unchanged;
3. ends `ch`, `sh`, `ss`, `x`, `z`, or `s` -> append `es`
   (church -> churches, box -> boxes, buzz -> buzzes, bus -> buses);
4. consonant + `y` (at least 2 characters) -> replace `y` with `ies`
   (city -> cities); vowel + `y` falls through to the default
   (boy -> boys);
5. ends `fe` -> replace with `ves` (knife -> knives, wife -> wives,
   life -> lives);
6. ends `f`: if the stem is in the `-ves` list -> stem + `ves`; otherwise
   append `s` (this covers the exception list);
7. ends `o`: if the word is in the `-oes` list -> append `es`; otherwise
   append `s` (this covers the exception list);
8. default -> append `s`.

`-ves` stem list: `lea` (leaf), `wol` (wolf), `hal` (half), `shel` (shelf),
`cal` (calf), `loa` (loaf), `thie` (thief), `scar` (scarf), `sel` (self).
`f` exceptions (append `s`): `roof`, `chief`, `belief`, `chef`, `proof`.
`-oes` list: `hero`, `potato`, `tomato`, `echo`, `veto`, `volcano`.
`o` exceptions (append `s`): `photo`, `piano`, `halo`, `solo`, `memo`,
`kilo`.

### Singularization rules (in order)

1. irregular table hit -> table value;
2. invariant word -> unchanged;
3. ends `ies` -> replace with `y` (cities -> city);
4. ends `ves`: exact match in the known list -> that singular
   (knives -> knife, leaves -> leaf, wolves -> wolf, wives -> wife,
   lives -> life, halves -> half, shelves -> shelf, calves -> calf,
   loaves -> loaf, thieves -> thief, scarves -> scarf); otherwise replace
   `ves` with `f`;
5. ends `oes`: exact match in the known list -> that singular
   (heroes -> hero, potatoes -> potato, tomatoes -> tomato, echoes -> echo,
   vetoes -> veto, volcanoes -> volcano); otherwise strip the final `s`
   (the documented fallback, chosen so shoes -> shoe and toes -> toe);
6. ends `ches`, `shes`, `sses`, `xes`, or `zes` -> strip `es`
   (boxes -> box, churches -> church, dishes -> dish, classes -> class);
7. ends `s` but not `ss` -> strip `s` (cats -> cat, buses -> buse);
8. otherwise unchanged.

## Semantics

`plural_pluralize(word)`
: Case-fold, apply the tables and rules above, restore initial
  capitalization. `""` -> `""`.

`plural_singularize(word)`
: Case-fold, apply the tables and rules above, restore initial
  capitalization. `""` -> `""`.

`plural_is_irregular(word)`
: True for irregular keys/values in either direction and for invariant
  nouns; false for rule-driven words (cat, city, box). `""` -> false.

`plural_count(n, singular)`
: `n == 1` -> `"1 <singular>"` (singular used verbatim); otherwise
  `"<n> <plural_pluralize(singular)>"`, so `(0, "item")` -> `"0 items"`,
  `(2, "person")` -> `"2 people"`, `(1, "person")` -> `"1 person"`.
  Negative counts pluralize (`-1 items`).

`plural_pluralize_all(words)`
: Returns a fresh `Vec[Str]` of the same length, each element passed through
  `plural_pluralize`; an empty vector returns an empty vector. Elements are
  never compared with `==` (BUG 17); tests compare via `str_compare`.

Error paths: none. Every function is total; the empty string and unknown
words are handled by returning a best-effort result.

## Complexity

| Operation | Complexity |
|---|---|
| `plural_pluralize` / `plural_singularize` / `plural_is_irregular` | O(table size x comparisons) = O(1), each comparison O(|word|) |
| `plural_count` | O(|singular|) plus one pluralization |
| `plural_pluralize_all` | O(n x |word|) over n elements |

## Test plan

`tests/test_conformance.xi` (`module plural_tests`, 35 named checks,
hello/lru-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary
line, and returns the failure count):

1-2. irregular plurals (regular nouns; Latin/Greek forms);
3-4. irregular singulars (regular nouns; Latin/Greek forms);
5-6. invariant nouns pluralized and singularized;
7-11. suffix plural rules: `ch`/`sh`, `ss`/`x`/`z`, `s`, consonant + `y`,
  vowel + `y`;
12-16. `fe`, `f` list, `f` exceptions, `o` list, `o` exceptions;
17-18. default `-s` and single-letter words;
19-20. initial capitalization on pluralize and singularize;
21-24. count forms 0/1/2 and irregular count forms;
25-26. `plural_pluralize_all` with three words (element-wise `str_compare`),
  including per-word capitalization;
27. round trip `pluralize(singularize(x))` for cats/cities/leaves;
28-32. singularization: regular `+s`, `-es` groups, `-ies`, known `-ves`,
  known `-oes`;
33-34. `plural_is_irregular` true and false cases;
35. empty string / empty vector.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.plural
```

## Known limitations

- Rule-table approach: words outside the tables take the generic suffix
  rules and can be wrong. Documented examples: `buses` -> `buse` (the
  fallback strips only the final `s`; `-ses` is not in the strip list),
  `gases` -> `gase`, `safe` -> `saves` (generic `-fe` rule),
  `movies` -> `movy` and `ties` -> `ty` (generic `-ies` rule), `curves` ->
  `curvf` (generic `ves` -> `f` fallback).
- Table decisions win over valid alternatives: `bases` always maps to
  `basis` (not `base`), `index` -> `indices` (not `indexes`), `media` ->
  `medium`.
- Only the initial letter's case is preserved; the rest of the output is
  lowercase.
- English-only, lowercase ASCII contract; no Unicode case folding.
- `plural_count` does not implement CLDR cardinal categories (e.g. it has no
  separate "few"/"many" forms).
- The tables are compile-time constants; there is no API to add entries.

## Compiler / stdlib notes for v0.61.3

- `str_compare` lives in `xiom.string.compare`, not `xiom.string`; this
  module and its tests import `xiom.string.compare` explicitly.
- Int -> Str uses `xiom.convert.int_to_string` (`xiom.convert` public API);
  the bare `to_string` intrinsic is module-internal to
  `xiom.convert.tostring` in the current stdlib.
- String equality against literals and Vec-sourced values goes through
  `str_compare` (BUG 17: `==` on `Str` values read from a `Vec[Str]` lowers
  to a pointer comparison).
- No `Result` is used anywhere, avoiding the v0.61.3 `Ok`/`Err` construction
  miscompile for struct-returning functions.

Last verified: compiler 0.61.3, `port: PASS (passed=35 failed=0 exit=0)`.
