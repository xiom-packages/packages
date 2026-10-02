# xiom.l10n-unicode

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.
> **Scope:** self-contained Unicode subset for l10n: category / script / block
> lookup, full case mapping and case folding (incl. Turkic), NFD/NFC/NFKD/NFKC
> normalization, and grapheme / word / sentence boundary segmentation.
> **Deps:** `xiom.std` only (`xiom.string.builder`, `xiom.string.compare`;
> tests also use `xiom.io`, `xiom.test`, `xiom.convert`).

## What it is

`xiom.l10n-unicode` implements pure-XIOM Unicode text utilities over a
**documented, testable subset** of Unicode (see SPEC.md for the exact covered
ranges): `is_covered` is the explicit coverage probe. All tables are built at
run time into local `Vec[Int]`s by explicit push loops -- no module-level
table initializers and no FFI.

- **`unicode_data`.** Two-letter general category (`Lu`, `Ll`, `Mn`, `Zs`,
  ...), canonical combining class, coarse script, Unicode block, and the
  usual predicate helpers (`is_letter`, `is_digit`, `is_punct`,
  `is_whitespace`, `is_cased`, ...). Code points inside the covered ranges
  are always classified (`Cn` for unassigned ones); outside they return `""`.
- **`unicode_case`.** Full case mapping: `upper`/`lower` expand correctly
  (`ß` -> `SS`, `İ` -> `i` + U+0307), `title` is word-aware, `fold` is the
  Unicode default full case fold (`Straße` -> `strasse`), and
  `fold_turkic` implements the Turkic I/dotted-I rules.
- **`unicode_norm`.** NFD/NFC/NFKD/NFKC with recursive decomposition,
  canonical combining-class reordering, blocking-aware composition, the
  covered composition exclusions (e.g. U+0344), plus `is_normalized` and a
  `Result`-returning `normalize`.
- **`unicode_seg`.** Grapheme cluster boundaries (UAX #29 core rules:
  CRLF, control, Extend/ZWJ, RI flags, emoji ZWJ sequences), UAX #29-subset
  word boundaries (apostrophes, numerics, extend-numlet), and a documented
  deterministic sentence segmenter. All boundary functions return byte
  offsets into the original `Str`.

The tables module `xiom.l10n.unicode.tables` is generated (Unicode 11.0.0
character data via CPython `unicodedata`, plus hand-written UAX #29/UTS #51
class ranges) and is an implementation detail; the public API is
`xiom.l10n.unicode`.

## Install / use

```
xiom pkg install xiom.l10n-unicode@0.1.0
```

Note on names: the package manifest name is `xiom.l10n-unicode`, but the
importable module is `xiom.l10n.unicode` (`-` is not a valid module-name
character).

```xi
use xiom.l10n.unicode;
use xiom.io;

io.println(l10n_unicode_nfd("é"));                 // e + U+0301
io.println(l10n_unicode_upper("straße"));          // STRASSE
io.println(l10n_unicode_fold("Straße"));           // strasse
io.println(l10n_unicode_nfkc("ﬁ"));                // fi
io.println(l10n_unicode_grapheme_count("e\u{0301}"));  // 1
io.println(l10n_unicode_category(0x00E9));         // Ll
io.println(l10n_unicode_word_count("don't stop")); // 2

match l10n_unicode_normalize("e\u{0301}", "NFC") {
  Ok(s) => { io.println(s); },                     // é
  Err(e) => { io.println(e); },                    // unknown/invalid input
}
```

## API

All public functions live in module `xiom.l10n.unicode`.

| Function | Returns | Description |
|---|---|---|
| `l10n_unicode_version()` | `Str` | Character-data version of the tables (`"11.0.0"`). |
| `l10n_unicode_is_covered(cp)` | `Bool` | Coverage probe for the documented subset. |
| `l10n_unicode_category(cp)` / `_id(cp)` | `Str` / `Int` | General category code / id; `""` / `-1` outside coverage. |
| `l10n_unicode_combining_class(cp)` | `Int` | Canonical combining class (0 when none). |
| `l10n_unicode_script(cp)` / `l10n_unicode_block(cp)` | `Str` | Coarse script / Unicode block name. |
| `l10n_unicode_is_letter/mark/digit/number/punct/symbol/separator/control/format/uppercase/lowercase/cased/whitespace/combining_mark(cp)` | `Bool` | Property predicates over the covered subset. |
| `l10n_unicode_grapheme_class(cp)` / `l10n_unicode_word_class(cp)` | `Str` | UAX #29 class name ("Other" outside coverage). |
| `l10n_unicode_is_extended_pictographic(cp)` | `Bool` | UTS #51 Extended_Pictographic subset. |
| `l10n_unicode_upper_cp/lower_cp/title_cp/fold_cp(cp)` | `Vec[Int]` | Full case mapping of one code point (1..3 cps). |
| `l10n_unicode_upper/lower/title/fold/fold_turkic(s)` | `Str` | String-level case conversion / folding. |
| `l10n_unicode_nfd/nfc/nfkd/nfkc(s)` | `Str` | Normalization; malformed input is returned unchanged. |
| `l10n_unicode_normalize(s, form)` | `Result[Str, Str]` | `"NFD"/"NFC"/"NFKD"/"NFKC"`; unknown form and invalid UTF-8 are errors. |
| `l10n_unicode_is_normalized(s, form)` | `Bool` | Quick check against the named form. |
| `l10n_unicode_grapheme_boundaries(s)` / `_count(s)` | `Vec[Int]` / `Int` | Grapheme cluster byte offsets (0..len) / count. |
| `l10n_unicode_word_boundaries(s)` / `_count(s)` | `Vec[Int]` / `Int` | UAX #29-subset word boundaries / word count. |
| `l10n_unicode_sentence_boundaries(s)` / `_count(s)` | `Vec[Int]` / `Int` | Sentence starts / sentence count. |

Boundary vectors are empty for empty or malformed input; otherwise they
start at 0, end at `s.len()`, are strictly ascending, and `count == len - 1`.

## Error model

- `l10n_unicode_normalize` returns
  `Err("l10n-unicode: unknown normalization form: <form>")` for a form other
  than the four canonical names (case-sensitive), and
  `Err("l10n-unicode: invalid UTF-8 input")` for malformed UTF-8 or a 0x00
  byte.
- The `Str`-returning functions (case and normalization) pass malformed
  UTF-8 / NUL-bearing input through unchanged; the boundary/count functions
  return empty / 0 for it.
- Uncovered code points are treated as `Other` / `ccc = 0` / identity by the
  engines; `category()` and `script()`/`block()` return `""`, and
  `category_id()` returns `-1`. Nothing throws.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom-l10n-unicode -TimeoutSec 60
```

Expected: 24 `[PASS]` lines and
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

Coverage: category/ccc/script/block fixtures, every predicate, single-cp and
string case maps (including `ß`/`İ`/`ŉ` expansions), folding incl. Turkic,
NFD/NFC/NFKD/NFKC fixtures with canonical reordering and the U+0344
exclusion, normalize `Result`/error paths, `is_normalized`,
grapheme clusters (CRLF, RI flags, ZWJ emoji, skin tone, extend chains),
word boundaries/counts (apostrophes, decimals, punctuation), sentence
boundaries/counts, control-character pass-through, coverage/table-shape
integrity sweeps, and normalization idempotence.

## Limitations

- **Documented subset.** Only the code point ranges listed in SPEC.md are
  covered; outside them, lookups return the documented defaults. This is not
  the full Unicode Character Database.
- **Unicode 11.0.0 data.** Tables were generated from CPython 3.7
  `unicodedata`; later amendments are not picked up automatically.
- **Coarse script assignment** is block-level (e.g. all combining marks are
  `Inherited`), not the full `Scripts.txt` per-code-point data.
- **Normalization does not compose Hangul syllables**, does not apply
  case-ignorable or Turkic special decompositions, and excludes only the
  covered composition exclusions.
- **Simplified sentence segmentation.** Deterministic rule set, no
  abbreviation dictionary ("Mr. Smith" splits) and no Unicode sentence-break
  property tables.
- **Grapheme/word classes are a UAX #29 subset.** No Hangul jamo
  (L/V/T/LV/LVT), no Prepend/SpacingMark classes, and
  Extended_Pictographic is approximated by the covered pictographic blocks.
- **No FFI, no `extern "C"`, no unsafe code, no `Vec[Str]`/`Vec[Struct]`
  tables.**
- API and coverage may change before `1.0.0`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
