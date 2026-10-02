# xiom.l10n-unicode -- specification

Behavior, data model, coverage and error cases for module
`xiom.l10n.unicode` (package `xiom.l10n-unicode`, version `0.1.0`).

The implementation is entirely pure XIOM and builds only on `xiom.std`
(`xiom.string.builder`, `xiom.string.compare`). There is no FFI and no unsafe
code.

## 1. Modules

| Module | File | Role |
|---|---|---|
| `xiom.l10n.unicode` | `src/l10n_unicode.xi` | Public API: codec, data lookup, case, normalization, segmentation. |
| `xiom.l10n.unicode.tables` | `src/l10n_unicode_tables.xi` | GENERATED character tables; implementation detail. |

All tables are materialized at run time into local `Vec[Int]`s by explicit
push loops. There are no module-level table initializers (a known
materialization hazard on older compilers; the sibling `xiom.l10n-currency`
documents the same workaround) and no `Vec[Str]` / `Vec[StructType]`
anywhere.

## 2. Coverage subset

`l10n_unicode_is_covered(cp)` is true exactly for the following ranges
(3302 code points), and `tables.tbl_covered()` is the machine-readable list:

```
U+0000..U+036F   Basic Latin, Latin-1 Supplement, Latin Extended-A/B,
                 IPA Extensions, Spacing Modifier Letters, Combining
                 Diacritical Marks
U+0370..U+03FF   Greek and Coptic
U+0400..U+04FF   Cyrillic
U+1E00..U+1EFF   Latin Extended Additional
U+2000..U+206F   General Punctuation
U+2070..U+209F   Superscripts and Subscripts
U+20A0..U+20BF   Currency Symbols
U+20D0..U+20FF   Combining Diacritical Marks for Symbols
U+FB00..U+FB06   Latin ligatures (ff, fi, fl, ffi, ffl, st)
U+FE00..U+FE0F   Variation Selectors 1..16
U+FF01..U+FF5E   Fullwidth ASCII variants
U+FFE0..U+FFE6   Fullwidth signs
U+1F1E6..U+1F1FF Regional Indicator Symbols
U+1F300..U+1F5FF Miscellaneous Symbols and Pictographs
U+1F600..U+1F64F Emoticons
U+1F680..U+1F6FF Transport and Map Symbols
U+1F900..U+1F9FF Supplemental Symbols and Pictographs
U+1FA70..U+1FAFF Symbols and Pictographs Extended-A
```

Outside coverage the engines behave as follows: general category is unknown
(`category()` returns `""`, `category_id()` returns `-1`, every category
predicate is false), combining class is 0, script and block are `""`,
grapheme/word classes are `Other`, Extended_Pictographic is false, and case
mapping / decomposition is identity. Inside coverage an unassigned code
point has category `Cn` (e.g. U+0378).

Character data version: **Unicode 11.0.0** (`l10n_unicode_version()`
returns `"11.0.0"`). Category, combining class, full case maps and
single-step decompositions were generated from CPython 3.7 `unicodedata`
(`unicodedata.unidata_version == "11.0.0"`); the UAX #29 class ranges and
the Extended_Pictographic ranges are hand-written subsets, listed below.

## 3. Data model

### 3.1 Table encodings

| Table | Stride | Row | Notes |
|---|---|---|---|
| `tbl_covered` | 2 | `lo, hi` | Covered ranges, sorted, disjoint. |
| `tbl_cat` | 3 | `lo, hi, cat_id` | General category ranges. |
| `tbl_ccc` | 3 | `lo, hi, ccc` | Only non-zero combining classes. |
| `tbl_script` | 3 | `lo, hi, script_id` | Coarse block-level script. |
| `tbl_block` | 3 | `lo, hi, block_id` | Covered intersections of Unicode blocks. |
| `tbl_gcb` | 3 | `lo, hi, gcb_id` | Grapheme_Cluster_Break classes. |
| `tbl_wb` | 3 | `lo, hi, wb_id` | Word_Break classes. |
| `tbl_extpic` | 3 | `lo, hi, 1` | Extended_Pictographic membership. |
| `tbl_upper_simple` | 2 | `cp, mapped` | Single-code-point full uppercase. |
| `tbl_lower_simple` | 2 | `cp, mapped` | Single-code-point full lowercase. |
| `tbl_title_simple` | 2 | `cp, mapped` | Single-code-point titlecase. |
| `tbl_fold_simple` | 2 | `cp, mapped` | Single-code-point case fold. |
| `tbl_multi` | 6 | `kind, cp, n, v0, v1, v2` | Multi-code-point mappings, `n <= 3`; kind `0=upper, 1=lower, 2=title, 3=fold`. |
| `tbl_canon` | 6 | `cp, n, d0, d1, d2, d3` | Canonical single-step decompositions, `n <= 4`. |
| `tbl_compat` | 6 | `cp, n, d0, d1, d2, d3` | Compatibility single-step decompositions, `n <= 4`. |

Map and decomposition tables are sorted by `cp` ascending; range tables are
in code point order. Multi-code-point mappings take precedence over simple
ones; absent entries mean identity.

### 3.2 Category ids

`0 Lu, 1 Ll, 2 Lt, 3 Lm, 4 Lo, 5 Mn, 6 Mc, 7 Me, 8 Nd, 9 Nl, 10 No,
11 Pc, 12 Pd, 13 Ps, 14 Pe, 15 Pi, 16 Pf, 17 Po, 18 Sm, 19 Sc, 20 Sk,
21 So, 22 Zs, 23 Zl, 24 Zp, 25 Cc, 26 Cf, 27 Co, 28 Cs, 29 Cn`.

`l10n_unicode_is_letter` = 0..4, `is_mark` = `is_combining_mark` = 5..7,
`is_digit` = 8, `is_number` = 8..10, `is_punct` = 11..18,
`is_symbol` = 18..21, `is_separator` = 22..24, `is_control` = 25,
`is_format` = 26, `is_uppercase` = 0, `is_lowercase` = 1,
`is_cased` = 0..2.

`is_whitespace` is the Unicode `White_Space` property restricted to the
covered set: U+0009..U+000D, U+0020, U+0085, U+00A0, U+2000..U+200A,
U+2028, U+2029, U+202F, U+205F.

### 3.3 Script ids

`0 Latin, 1 Greek, 2 Cyrillic, 3 Common, 4 Inherited`. Assignment is
block-level and coarse: U+0300..U+036F, U+20D0..U+20FF and U+FE00..U+FE0F
are `Inherited`; U+0370..U+03FF is `Greek` (including the few Common
punctuation code points inside); U+0400..U+04FF is `Cyrillic`; letters in
the Latin blocks (Latin-1 Supplement letter ranges, Latin Extended-A/B, IPA
Extensions, Latin Extended Additional, U+FB00..U+FB06) are `Latin`;
everything else covered is `Common`.

### 3.4 Grapheme_Cluster_Break subset

| Class (id) | Covered assignment |
|---|---|
| CR (1) | U+000D |
| LF (2) | U+000A |
| Control (3) | U+0000..U+0009, U+000B..U+000C, U+000E..U+001F, U+007F..U+009F, U+00AD, U+200B, U+200E..U+200F, U+2028..U+202E, U+2060..U+2064, U+2066..U+206F |
| Extend (4) | U+0300..U+036F, U+0483..U+0489, U+200C, U+20D0..U+20F0, U+FE00..U+FE0F, U+1F3FB..U+1F3FF |
| ZWJ (5) | U+200D |
| Regional_Indicator (6) | U+1F1E6..U+1F1FF |
| Other (0) | everything else |

Not represented (documented deviation): Hangul jamo, Prepend, SpacingMark,
emoji-zero-width-joiner specifics beyond rule GB11.

### 3.5 Word_Break subset

CR/LF/Newline = U+000D / U+000A / {U+000B, U+000C, U+0085, U+2028, U+2029};
Extend = U+0300..U+036F, U+0483..U+0489, U+200C, U+20D0..U+20F0,
U+FE00..U+FE0F, U+1F3FB..U+1F3FF; ZWJ = U+200D; Format = U+00AD, U+200B,
U+200E..U+200F, U+202A..U+202E, U+2060..U+2064, U+2066..U+206F;
ExtendNumLet = U+005F, U+202F, U+203F..U+2040, U+2054, U+FF3F;
MidLetter = U+003A, U+00B7, U+0387, U+2027, U+FE13, U+FE55, U+FF1A;
MidNum = U+002C, U+003B, U+037E, U+2044, U+FE10, U+FE14, U+FE50, U+FE54,
U+FF0C, U+FF1B; MidNumLet = U+002E, U+2018..U+2019, U+2024, U+FE52, U+FF07,
U+FF0E; SingleQuote = U+0027; DoubleQuote = U+0022; WSegSpace = U+0020,
U+2000..U+200A, U+205F; Regional_Indicator = U+1F1E6..U+1F1FF. Category
`Nd` is Numeric; category `L*` is ALetter; everything else is Other.
Hebrew_Letter and Katakana occur in no covered range.

### 3.6 Extended_Pictographic subset

U+00A9, U+00AE, U+203C, U+2049 and every code point of U+1F300..U+1F5FF,
U+1F600..U+1F64F, U+1F680..U+1F6FF, U+1F900..U+1F9FF and
U+1FA70..U+1FAFF. This is an approximation of UTS #51 (whole covered
pictographic blocks), not the exact property file.

## 4. Public API semantics

### 4.1 Case (`unicode_case`)

- `upper_cp/lower_cp/title_cp/fold_cp(cp)` return the **full** mapping as
  1..3 code points; unmapped code points return themselves. Examples:
  U+00DF -> `S,S` (upper), `s,s` (fold); U+0130 -> `i,U+0307` (lower);
  U+01C6 -> `U+01C5` (title); U+00B5 -> U+03BC (fold).
- `upper(s)`, `lower(s)`, `fold(s)` apply the per-code-point maps over the
  string.
- `title(s)` is word-aware: the first cased code point after a non-cased
  code point gets the title map, subsequent cased code points get the lower
  map; uncased code points pass through.
- `fold_turkic(s)` maps U+0049 -> U+0131 and U+0130 -> U+0069 before the
  default fold; all other code points fold normally.

### 4.2 Normalization (`unicode_norm`)

Pipeline: decode UTF-8 -> recursive decomposition -> canonical ordering by
combining class -> (NFC/NFKC only) blocking-aware composition -> encode.
Decomposition recursion is capped at depth 6 (a malformed/cyclic table
cannot loop; the cap is unreachable for the covered data). NFKD/NFKC use
compatibility decompositions where present, falling back to canonical ones;
NFD/NFC use canonical decompositions only. Composition is attempted only
for starter + non-starter pairs (no Hangul LV/LVT composition), requires
`last_ccc < ccc(c)` (standard blocking), and skips the covered composition
exclusions: U+0340, U+0341, U+0343, U+0344, U+0374, U+037E, U+0385, U+0387
(singleton decompositions are excluded automatically).

- `nfd/nfc/nfkd/nfkc(s)` return the normalized string; malformed UTF-8 or
  NUL-bearing input is returned unchanged.
- `normalize(s, form)` accepts exactly `"NFD"`, `"NFC"`, `"NFKD"`,
  `"NFKC"` (case-sensitive) and returns `Result[Str, Str]`.
- `is_normalized(s, form)` recomputes the form and compares bytes; unknown
  forms and malformed input are `false`.

### 4.3 Segmentation (`unicode_seg`)

All boundary functions return byte offsets into the original `Str`.
Invariants for non-empty, well-formed input: first element 0, last element
`s.len()`, strictly ascending; `count == boundaries.len() - 1`. Empty or
malformed input yields an empty vector / count 0.

**Graphemes.** Implemented UAX #29 rules: GB3 (`CR x LF`), GB4/GB5
(break after/before Control, CR, LF), GB9 (`x Extend`, `x ZWJ`), GB11
(`Extended_Pictographic Extend* ZWJ x Extended_Pictographic`), GB12/GB13
(RI pairs), GB999, plus sot/eot. Not implemented: GB6..GB8 (Hangul), GB9a
(SpacingMark), GB9b (Prepend) -- no covered code points carry those
classes.

**Words.** Implemented UAX #29 rules: WB3, WB3a, WB3b, WB3c (ZWJ x
Extended_Pictographic), WB3d (WSegSpace x WSegSpace), WB4 (ignore
Extend/Format/ZWJ), WB5, WB6, WB7, WB8, WB9, WB10, WB11, WB12, WB13a,
WB13b, WB15/WB16, WB999. Hebrew rules (WB7a..WB7c) and Katakana (WB13) are
not applicable to the covered ranges. `word_count` counts maximal spans
between word boundaries that contain at least one ALetter, Numeric or
ExtendNumLet code point.

**Sentences.** Documented simplified rule set (not UAX #29 SB):
a terminator run of `.`, `!`, `?`, `…` (U+2026) or their fullwidth forms
(U+FF0E, U+FF01, U+FF1F) ends a sentence when followed by whitespace and
then a non-closing character, by a closing quote/bracket
(`"`, `'`, `)`, `]`, `»`, `›`, `’`, `”`) and then whitespace, or by end of
input. A `.` with an ASCII digit on both sides is a decimal point. Closing
punctuation directly after a terminator stays in the sentence. There is no
abbreviation dictionary, so `"Mr. Smith"` yields two sentences, and a
terminator followed directly by a letter (`"Hello.World"`) does not split.

## 5. Error cases and edge behavior

| Input | Behavior |
|---|---|
| `cp < 0` or `cp > 0x10FFFF` | `is_covered` false, category `""` / id `-1`, ccc 0, script/block `""`, class `Other`, predicates false. |
| Uncovered covered-range gaps | Category `Cn`; every other property uses the range-table default. |
| Empty string | Case/norm return `""`; boundary vectors empty; counts 0. |
| Malformed UTF-8 in `Str` | Case/norm return the input unchanged; `normalize` returns `Err("l10n-unicode: invalid UTF-8 input")`; boundaries empty / counts 0. |
| `0x00` byte in `Str` | Same as malformed (a built `Str` containing NUL cannot be materialized by `sb_to_str`). |
| Unknown normalization form | `normalize` -> `Err("l10n-unicode: unknown normalization form: <form>")`; `is_normalized` -> `false`. |
| Multi-code-point mapping output | Always 1..3 code points; `ß` -> `SS`/`ss`, `İ` -> `i,U+0307`, `ﬀ`-family ligatures expand. |

Nothing in the public API throws or aborts for any `Str` input, including
raw non-UTF-8 bytes.

## 6. Testing

`tests/test_conformance.xi` is a deterministic, self-contained suite
(no external files) of 24 checks run by `scripts/port.ps1`. It covers:
coverage probes, category/ccc/script/block fixtures, all predicates,
single-code-point and string case maps, default and Turkic folding,
NFD/NFC/NFKD/NFKC fixtures (including canonical reordering and the U+0344
exclusion), `normalize` `Result`/error paths, `is_normalized`, grapheme
clusters (CRLF, RI flags, ZWJ emoji, skin tone, extend chains), word
boundaries/counts, sentence boundaries/counts, control-character
pass-through, coverage/table-shape integrity sweeps, and normalization
idempotence.

Expected harness line: `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## 7. Generation and provenance

`src/l10n_unicode_tables.xi` was generated by a one-off script from
CPython 3.7 `unicodedata` (Unicode 11.0.0) plus hand-written UAX #29
class ranges and the Extended_Pictographic approximation. The generator is
not shipped; the generated file's banner records the source and the
"regenerate rather than hand-edit" rule. Table rows are emitted as decimal
or hexadecimal integer literals only -- no string data, no NUL bytes, no
locale data.

## 8. Non-goals

- Full UCD coverage, full `Scripts.txt`, full UAX #29/#14 property tables.
- Collation, locale tailoring, transliteration, bidi itemization.
- Hangul composition/decomposition, Unicode case-ignorable context rules,
  grapheme/word/sentence properties for scripts outside the covered set.
- Streaming/iterator APIs; every function is pure and total on `Str`.
