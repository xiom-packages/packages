# xiom.stemming -- specification

Version: 0.1.2 (stable; published on the XIOM registry).

## Scope

`xiom.stemming` implements the classic Porter stemming algorithm for
lowercase ASCII English words, entirely in XIOM (no FFI). It exposes the
stemmer itself, a vector mapper, and Porter's `m` measure for tests and
diagnostics.

In scope:

- steps 1a, 1b, 1c, 2, 3, 4, 5a and 5b of Porter's 1980 paper,
- the reference-implementation rule spellings (`BLI -> BLE`, `LOGI -> LOG`),
- deterministic, allocation-only, side-effect-free functions.

Out of scope:

- case folding, Unicode normalisation, tokenisation,
- Porter2/Snowball, language-specific stemmers, dictionaries,
- stemming of multi-word strings or punctuation.

## Input contract

| Input | Result |
|---|---|
| `""` | `""` |
| length < 3 bytes | returned unchanged |
| all bytes in `a-z` | stemmed |
| any byte outside `a-z` (uppercase, digit, punctuation, non-ASCII) | returned unchanged |

The check is byte-based: a UTF-8 word such as `café` contains bytes above
`122` and is therefore returned unchanged rather than stemmed around them.

## Algorithm

The word is copied into a `Vec[UInt8]`; every predicate and every suffix
match works on bytes. The steps run once, in order. `m` is Porter's measure:
the number of vowel-run to consonant-run (`VC`) sequences in a word; `*v*`
means "the stem contains a vowel"; `*d` means "ends in a double consonant";
`*o` means "ends consonant-vowel-consonant where the final consonant is not
`w`, `x` or `y`". `y` is a consonant at the start of a word and after a
consonant, and a vowel otherwise.

- **Step 1a** `SSES -> SS`, `IES -> I`, `SS -> SS`, `S -> ""`.
- **Step 1b** `(m>0) EED -> EE`; `(*v*) ED -> ""`; `(*v*) ING -> ""`. After a
  non-EED cut: `AT -> ATE`, `BL -> BLE`, `IZ -> IZE`; else a final double
  consonant loses one letter unless it is `l`, `s` or `z`; else if `m == 1`
  and `*o`, append `E`.
- **Step 1c** `(*v*) Y -> I`.
- **Step 2** `(m>0)` table, first match wins:
  `ATIONAL -> ATE`, `TIONAL -> TION`, `ENCI -> ENCE`, `ANCI -> ANCE`,
  `IZER -> IZE`, `BLI -> BLE`, `ALLI -> AL`, `ENTLI -> ENT`, `ELI -> E`,
  `OUSLI -> OUS`, `IZATION -> IZE`, `ATION -> ATE`, `ATOR -> ATE`,
  `ALISM -> AL`, `IVENESS -> IVE`, `FULNESS -> FUL`, `OUSNESS -> OUS`,
  `ALITI -> AL`, `IVITI -> IVE`, `BILITI -> BLE`, `LOGI -> LOG`.
- **Step 3** `(m>0)` table, first match wins: `ICATE -> IC`, `ATIVE -> ""`,
  `ALIZE -> AL`, `ICITI -> IC`, `ICAL -> IC`, `FUL -> ""`, `NESS -> ""`.
- **Step 4** `(m>1)` table, first match wins: `AL`, `ANCE`, `ENCE`, `ER`,
  `IC`, `ABLE`, `IBLE`, `ANT`, `EMENT`, `MENT`, `ENT`, `ION` (only when the
  stem ends in `S` or `T`), `OU`, `ISM`, `ATE`, `ITI`, `OUS`, `IVE`, `IZE`
  all removed.
- **Step 5a** `(m>1) E -> ""`; `(m==1 and not *o) E -> ""` (the `*o` test is
  applied to the word without its final `E`).
- **Step 5b** `(m>1 and *d and *L) -> single letter`.

A matched suffix whose stem fails the measure requirement stops that step
(matching the first-match-wins structure of the reference implementation)
and no replacement is made.

## Test plan

`tests/test_conformance.xi` contains 34 named checks:

1. **Step 1a** -- `caresses -> caress`, `possesses -> possess`,
   `ponies -> poni`, `ties -> ti`, `caress -> caress`, `press -> press`,
   `cats -> cat`, `dogs -> dog`.
2. **Step 1b** -- `feed -> feed`, `agreed -> agre`, `plastered -> plaster`,
   `bled -> bled`, `conflated -> conflat`, `troubled -> troubl`,
   `sized -> size`, `motoring -> motor`, `sing -> sing`, `hopping -> hop`,
   `tanned -> tan`, `falling -> fall`, `hissing -> hiss`, `fizzed -> fizz`,
   `filing -> file`, `failing -> fail`.
3. **Step 1c** -- `happy -> happi`, `sky -> sky`.
4. **Steps 2-4** -- `relational -> relat`, `conditional -> condit`,
   `rational -> ration`, `valency -> valenc`, `electrical -> electr`,
   `electricity -> electr`, `operative -> oper`, `equalize -> equal`,
   `formalize -> formal`, `goodness -> good`, `allowance -> allow`,
   `dependent -> depend`, `adoption -> adopt`, `effective -> effect`,
   `marvelous -> marvel`.
5. **Step 5** -- `probate -> probat`, `rate -> rate`,
   `controlling -> control`, `roll -> roll`.
6. **Measure** -- `tr = 0`, `tree = 0`, `trouble = 1`, `oats = 1`,
   `trees = 1`, `troubles = 2`, `private = 2`, `by = 0`, plus empty and
   short words.
7. **API behaviour** -- `stem_all` preserves order and length; empty input
   yields empty output; words shorter than three bytes are unchanged;
   uppercase, punctuation and non-ASCII words are unchanged; stemming is
   idempotent on the classic fixtures.

Every `Str` comparison in the suite goes through
`xiom.string.compare.str_compare`, and vector elements are only read through
bounds-checked helpers. The suite exits non-zero on any failure.

Run it with:

```
.\scripts\port.ps1 -Package xiom.stemming
```

## Contracts

Runtime-checkable `ensures:` clauses on `src/stemming.xi` (hardening pass
2026-10-07, compiler v0.64.0; no manifest change in this pass). 7 clauses
across the 3 public entry points. Two consecutive
`& .\scripts\port.ps1 -Package xiom.stemming -TimeoutSec 60` runs ended
`port: PASS (passed=34 failed=0 program_exit=0 exit=0)` in 9.3 s and 9.4 s
with the clauses active; no clause was dropped.

All 7 clauses are runtime-checked: each reads a `Str`/`Vec` length
(`word.len()`, `words.len()`, `result.len()`) or a scalar bound over
`result`, enforced by the v0.64.0 runtime evaluator on every return. A
direct `xiom-verify src\stemming.xi --check` run classified every clause
axiom as unknown (0 proven, 0 violated, 7 unknown; the emitter cannot
resolve `Str`-length operand sorts and reported 3 SMT errors), so no
clause is claimed Z3-provable. No clause calls a function: the per-step
suffix formulas are private and stay outside the contract surface.

| Entry point | Contract | Class |
|---|---|---|
| `stem` | `ensures: word.len() < 3 => result.len() == word.len()` | runtime-checked (identity on the short-word early return) |
| `stem` | `ensures: result.len() <= word.len()` | runtime-checked (length bound) |
| `stem` | `ensures: word.len() >= 3 => result.len() >= 1` | runtime-checked (non-empty output for non-short words) |
| `stem_all` | `ensures: result.len() == words.len()` | runtime-checked (output count) |
| `stem_measure` | `ensures: result >= 0` | runtime-checked (scalar bound; no Z3 evidence emitted) |
| `stem_measure` | `ensures: word.len() == 0 => result == 0` | runtime-checked (empty-input identity) |
| `stem_measure` | `ensures: result <= word.len()` | runtime-checked (length bound) |

## Limitations

- Lowercase ASCII `a-z` only; other input is returned unchanged.
- One language, one algorithm: the original Porter stemmer, not Snowball.
- `stem_measure` treats any byte outside `a-z` as a consonant; it is a
  diagnostic over the raw bytes.
- The algorithm is heuristic and inherits Porter's known over- and
  under-stemming behaviour.

## References

- M. F. Porter, *An algorithm for suffix stripping*, Program 14(3), 1980.
- M. F. Porter's reference implementation (porter.c) for the `BLI`/`LOGI`
  rule spellings and the first-match-wins step structure.
