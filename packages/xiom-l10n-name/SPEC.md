# xiom.l10n-name -- specification

Version: 0.1.0 (incubating). Pure XIOM, no FFI, no I/O, no `Float64`. All
functions are free functions; the module header imports `xiom.string`,
`xiom.convert` and `xiom.string.compare` from `xiom.std`.

## 1. Model

A personal name is five independent `Str` fields, carried by
`PersonName`:

| Field | Role |
|---|---|
| `prefix` | honorific or pre-name particle (`"Dr."`, `"Mr."`) |
| `given` | given name(s) |
| `middle` | middle name(s) |
| `family` | family name |
| `suffix` | post-name marker (`"Jr."`, `"III"`) |

`""` is the documented **absent** sentinel: an empty field contributes
nothing to any output. Parts are used verbatim (never trimmed, never
case-folded), so a caller who wants `"Dr."` normalized must do it before
calling. There are no locale databases, no global state and no name parsing:
the caller splits the name into fields.

`NameList` carries a list of names as five parallel `Vec[Str]` vectors
(`prefixes`, `givens`, `middles`, `families`, `suffixes`). Invariant:
element `i` of all five vectors describes the i-th name, so the vectors
always have equal length; `name_list_new`/`name_list_push` maintain the
invariant by pushing in lockstep. `name_list_len` returns the `givens`
length. Reads are always bounds-checked, so a ragged list degrades to `""`
parts instead of trapping.

`HonorificTable` carries a caller-supplied `(key, title)` mapping as two
parallel `Vec[Str]` vectors (`keys`, `titles`) with the same lockstep
invariant.

## 2. Locale matching

A locale is classified by its **primary subtag**: the text before the first
`'-'` (45) or `'_'` (95), or the whole tag when neither byte occurs. The
subtag is lowercased with `xiom.string.str_lower` (ASCII case-insensitive in
practice).

- Family-first set: `zh`, `ja`, `ko`, `hu`.
- Every other tag, including `""`, unknown tags and tags with other primary
  subtags, selects the given-first default.

Examples: `"zh"`, `"zh-Hans"`, `"zh_CN"`, `"ZH"` -> family-first;
`"ja-JP"`, `"ko_KR"`, `"hu-HU"` -> family-first; `"en"`, `"en-US"`, `"xx"`,
`"unknown-locale"`, `""` -> default.

## 3. `name_display(locale: Str, name: &PersonName) -> Str`

Selects the part order, keeps only non-empty parts, and joins them with
single spaces (`_join2`-fold; an absent part never leaves a doubled or
dangling space):

- **Family-first** (`zh`, `ja`, `ko`, `hu`): `prefix family given suffix`.
  The `middle` part is **not placed** in this order (v0.1.0 rule; put a
  second given name into `given` when ordering family-first).
- **Given-first** (default and fallback): `prefix given middle family
  suffix`.

Some name uses all five fields: `("en", Dr. John Paul Smith Jr.)` ->
`"Dr. John Paul Smith Jr."`; `("zh", Dr. John Paul Smith Jr.)` ->
`"Dr. Smith John Jr."`. Empty-field examples: `("en", "", John, "", "",
"")` -> `"John"`; `("en", "", "", "", "Smith", "Jr.")` -> `"Smith Jr."`;
all-empty -> `""`.

Complexity: O(total part length). Never fails.

## 4. `name_display_list(locale: Str, names: &NameList, max_items: Int) -> Str`

1. `count = name_list_len(names)`. The considered window is the first
   `limit` names where `limit = count`, unless `max_items > 0 &&
   max_items < count`, in which case `limit = max_items` and the result is
   **truncated**.
2. Every name in the window is rendered with `name_display`; names that
   render `""` are skipped and do not consume a join position. `shown` is
   the number of non-empty renders; if `shown == 0` the result is `""`
   (even when truncated).
3. Joining, left to right over the non-empty renders:
   - Default style (`en`, `hu`, unknown, `""`, ..., i.e. every locale that
     is not `zh`, `ja` or `ko`): between two shown items `", "`; before the
     **last** shown item, `" and "` -- but only when the result is **not
     truncated**, so `"A, B and C"` normally and `"A, B"` inside a
     truncated window.
   - `zh`: `"、"` between items, no last-item word.
   - `ja`, `ko`: `"・"` between items, no last-item word.
4. When truncated, `"…"` (U+2026) is appended to the joined text.

Examples with the fixture `Alice Smith`, `Bob Jones`, `Carol Lee`
(given-first fields, so family-first locales render `"Smith Alice"`):

| Call | Result |
|---|---|
| `("en", list, 0)` | `"Alice Smith, Bob Jones and Carol Lee"` |
| `("en", list, 2)` | `"Alice Smith, Bob Jones…"` |
| `("en", list, 1)` | `"Alice Smith…"` |
| `("en", list, 3)` / `(..., 5)` / `(..., -1)` | full join, no marker |
| `("zh", list, 0)` | `"Smith Alice、Jones Bob、Lee Carol"` |
| `("zh", list, 2)` | `"Smith Alice、Jones Bob…"` |
| `("ja", list, 0)` / `("ko", list, 0)` | `"Smith Alice・Jones Bob・Lee Carol"` |
| `("hu", list, 0)` | `"Smith Alice, Jones Bob and Lee Carol"` |
| 1 item | that item alone, no separator |
| 2 items (default) | `"A and B"` |
| all renders empty | `""` |

Complexity: O(names * part length). Never fails.

## 5. Initials

### 5.1 `name_initials_of(given: Str, middle: Str) -> Str`

Each non-empty part contributes one initial: its **first Unicode
character**, passed through `xiom.string.str_upper` (uppercased when the
character has an uppercase form) and followed by `"."`; the two initials are
joined with a single space, in the order given then middle. Non-letter first
characters (digits, punctuation, CJK ideographs, ...) are used as-is -- no
transliteration, no script conversion, no multi-letter initials:
`("John", "Paul")` -> `"J. P."`; `("john", "")` -> `"J."`;
`("", "paul")` -> `"P."`; `("", "")` -> `""`; `("Jean-Luc", "Marie")` ->
`"J. M."`; `("李", "明")` -> `"李. 明."`; `("3", "")` -> `"3."`.

### 5.2 First-character extraction

The first character is sliced by its UTF-8 leading byte, widened to `Int`
with `% 256` before any `>= 128` test (v0.62.0 miscompiles direct `UInt8`
comparisons at or above 128):

| Leading byte after `% 256` | Byte length |
|---|---|
| 0x00..0x7F | 1 |
| 0x80..0xBF (malformed as a leading byte) | 1 |
| 0xC0..0xDF | 2 |
| 0xE0..0xEF | 3 |
| 0xF0..0xFF | 4 |

The length is clamped to the remaining byte length, so a truncated final
character keeps its available bytes.

### 5.3 `name_initials(name: &PersonName) -> Str`

Delegates to `name_initials_of(given, middle)`; `prefix`, `family` and
`suffix` are ignored.

## 6. `name_honorific(table: &HonorificTable, key: Str) -> Str`

Scans `keys` in order; the first `keys[i]` that compares equal to `key`
byte-wise (`compare.str_compare`) yields `titles[i]`. An empty `key` returns
`""` without scanning. A missing key returns `""`. A ragged table is bounded
by `min(keys.len(), titles.len())`. No built-in titles exist and no locale
parameter is taken: the caller chooses locale-appropriate pairs (for example
`("dr", "Dr.")` for English, `("博士", "博士")` for Japanese).

Complexity: O(pairs * key length). Never fails.

## 7. `name_sort_key(locale: Str, name: &PersonName) -> Str`

Returns the non-empty parts joined with single spaces in the order
**`family given middle prefix suffix`**, independent of `locale` (accepted
for interface symmetry and reserved for future locale collation in v0.1.0).
An absent family yields a key starting with the next present part. Sorting
names with byte-wise `compare.str_compare` on these keys orders by family
name first: `("en", Dr. John Paul Smith Jr.)` -> `"Smith John Paul Dr.
Jr."`; `("en", "", John, "", "", "")` -> `"John"`. The key is not a locale
collation key: no accent, case or width folding; equal keys mean
byte-identical part sequences.

## 8. Error and fallback catalog

Every function is total -- there is no `Result` and no error string in this
module. The complete fallback catalog:

| Condition | Behavior |
|---|---|
| `locale` is `""`, unknown, or has another primary subtag | given-first display; default list style |
| locale tag uses `-` or `_` subtags or mixed case | classified on the lowercased primary subtag |
| all five `PersonName` parts empty | `name_display` -> `""`; `name_sort_key` -> `""` |
| `given` and `middle` both empty | `name_initials` -> `""` |
| first character is not a letter | used as-is plus `"."` (no transliteration) |
| malformed UTF-8 leading byte | treated as a 1-byte character |
| `max_items <= 0` | no truncation (unlimited sentinel) |
| `max_items >= name_list_len` | no truncation, no `"…"` |
| every name in the window renders `""` | `name_display_list` -> `""` (no `"…"`) |
| `key` is `""` or not present in the table | `name_honorific` -> `""` |
| duplicate keys | first matching pair wins |
| ragged `HonorificTable` | search bounded by the shorter vector |
| ragged/empty `NameList` | out-of-range part reads yield `""`; `name_list_len` is the `givens` length |
| list is truncated | prefix of `max_items` names plus `"…"`; the default `" and "` conjunction is dropped |

## 9. Test plan (tests/test_conformance.xi, 21 checks)

| # | Name | Expectation |
|---|---|---|
| t1 | given-first default | full five-field order; `en-US` and `""` behave the same |
| t2 | empty parts | no doubled/dangling spaces for every removed slot |
| t3 | empty name / unknown locale | `""` in both orders; `xx` and `unknown-locale` fall back to given-first |
| t4 | family-first locales | `zh`, `zh-CN`, `ja`, `ko`, `hu` render `family given` |
| t5 | family-first prefix/suffix | prefix first, suffix last, `middle` omitted (v0.1.0) |
| t6 | locale classification | primary subtag, ASCII case-insensitive, default false |
| t7 | list default 3 items | `"A, B and C"`; `name_list_len` = 3 |
| t8 | list default 2 and 1 items | `"A and B"`; single item alone |
| t9 | list skips empty renders | skip holds with and without truncation |
| t10 | list zh/ja/ko joins | `"、"` and `"・"` between items |
| t11 | list hu/unknown joins | default comma + `" and "` style |
| t12 | list truncation | `max_items` 2 and 1 with `"…"`; zh truncation uses `"、"` |
| t13 | truncation no-ops | `max_items` 3, 5, -1 unbounded; all-empty list -> `""` |
| t14 | initials basic | given then middle, uppercased, `"."`, space-joined |
| t15 | initials non-ASCII | CJK, digit and apostrophe first characters verbatim |
| t16 | initials wrapper | `name_initials` uses only given/middle |
| t17 | honorific basic | hit, miss, empty key, exact byte-wise key (`"Dr."` != `"dr"`) |
| t18 | honorific first match | duplicate key keeps the first title; case-sensitive |
| t19 | honorific ragged table | bounded by the shorter vector |
| t20 | sort key composition | `family given middle prefix suffix`; same for `en` and `zh` |
| t21 | sort key ordering | `"Li Wei"` sorts before `"Smith John"`; locale-independent |

Every check folds its sub-checks into one `assert(cond, name)` and `main`
returns the number of failing checks (0 = green). `port.ps1` must end
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## 10. Compiler notes (XIOM v0.62.0)

- Free functions only; no methods, lambdas, `Vec[fn]` dispatch or generic
  callbacks. No `Vec[StructType]`: lists and honorific tables are parallel
  `Vec[Str]` fields pushed in lockstep.
- `Str` equality is never `==`; every string decision uses
  `compare.str_compare` on typed locals (BUG 17 family), including `Vec[Str]`
  elements bound to `let x: Str = v[i];` before comparison.
- `UInt8` bytes from `string.byte_at` are compared only below 128; the
  UTF-8 leading-byte classifier widens with `(b as Int) % 256` first.
- `&struct.field` is bound to a local before being passed to `&Vec[Str]`
  parameters (`_vec_at` call sites).
- `module` has no terminating `;`; `use` statements do.
- No `Result` is constructed at all; `Ok`/`Err` leaf-construction rules do
  not apply.
- The `xiom.convert` import is part of the pinned module header; v0.1.0 calls
  only `xiom.string` and `xiom.string.compare`.

## 11. Known limitations

- No transliteration or script conversion (explicitly out of scope); no
  romanization, no kanji/kana mapping, no Latin fallback.
- No name parsing from free text; fields must be split by the caller.
- No CLDR or any locale data: the family-first set is fixed to
  `{zh, ja, ko, hu}` and list conjunctions to the three documented styles.
  Hungarian uses the default English-style conjunction.
- Family-first display omits `middle` (v0.1.0 rule).
- Honorifics: caller-supplied table only; first-match byte-wise lookup, no
  case folding, no locale validation.
- Sort keys are byte-wise family-first, not collation keys.
- Initials: exactly one character per part; `str_upper` semantics apply.
