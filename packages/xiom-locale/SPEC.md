# xiom.locale -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.locale` (`src/locale.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free codec for in-memory `Str` language tags:

- `locale_parse` / `locale_to_string` -- BCP-47 language tag <-> `Locale`,
- `locale_canonical` -- casing canonicalization of a tag string,
- `locale_is_valid` -- well-formedness predicate,
- `locale_lookup` -- RFC 4647 Lookup over a language priority list,
- `locale_fallback_chain` -- ordered resolution candidates for default data,
- `locale_registry_get` / `locale_registry_count` -- curated language registry.

Normalization beyond casing (Preferred-Value replacements, likely-subtags,
IANA registry validation), filtering matching, and default-data semantics are
non-goals (see section 11).

## 2. Data model

```xi
pub type Locale = {
  language: Str;       // lowercased, "" for a private-use-only tag
  script: Str;         // Titlecase, "" when absent
  region: Str;         // UPPERCASE, "" when absent
  variants: Vec[Str];  // lowercased, tag order, empty when absent
  extensions: Vec[Str];// singleton first ("u-ca-gregory"), empty when absent
  private_use: Str;    // without the "x-" prefix ("abc-def"), "" when absent
}

pub type LangInfo = {
  subtag: Str;         // canonical lowercase ISO 639 subtag
  name: Str;           // English name
  default_script: Str; // curated default ISO 15924 script
}
```

There is no field recording presence-versus-absence of an empty component
beyond the shapes above: an absent script/region is `""` (neither can be
legitimately empty), and absent variants/extensions are empty vectors.
`private_use` stores the subtags after `x-` so a canonical re-emission
re-adds the prefix exactly once.

## 3. Grammar accepted

```
tag        = langtag / privateuse
langtag    = language ["-" script] ["-" region] *("-" variant)
             *("-" extension) ["-" privateuse]
privateuse = "x" 1*("-" 1*8alphanum)
language   = 2*8ALPHA
script     = 4ALPHA
region     = 2ALPHA / 3DIGIT
variant    = 5*8alphanum / (DIGIT 3alphanum)
extension  = singleton 1*("-" 2*8alphanum)
singleton  = alphanum except "x" / "X"
alphanum   = ALPHA / DIGIT
```

This is the RFC 5646 2.1 `langtag` production with `extlang` dropped and the
grandfathered/irregular productions rejected. Subtags are ASCII-only;
`byte_at` over the UTF-8 bytes accepts any non-ASCII byte nowhere.

Not accepted (documented limitations): extlang subtags (`zh-cmn-Hans`),
grandfathered tags (`i-klingon`, `en-GB-oed` and the irregular forms with a
digit, which are not 2-8 alpha), tags with a leading/trailing/double hyphen
(empty subtag), and any tag where a subtag matches no positional shape.

## 4. Parsing semantics

1. Empty input is `Err("locale: empty tag")`.
2. The tag is split on `-`; any empty part is `Err("locale: empty subtag")`
   (this also covers `"en-"`, `"-en"` and `"en--US"`).
3. If the first subtag is `x`/`X`, the tag is private-use-only: every
   following subtag must be `1*8alphanum`, the lowercased rest is stored in
   `private_use`, and all other fields stay empty. `"x"` alone and any
   invalid subtag after `x` are errors (sections 6).
4. Otherwise the first subtag must be `2*8ALPHA` and is lowercased into
   `language`. Everything else follows the fixed order:
   - script: accepted only while script, region and variants are all empty;
   - region: accepted only while region and variants are empty;
   - variant: accepted while no extension is open; duplicates rejected;
   - singleton: opens an extension; the previous extension (if any) must have
     at least one subtag and is committed; duplicate singletons rejected;
   - once an extension is open, every non-singleton subtag with `2*8alphanum`
     belongs to it (a further singleton starts the next one);
   - `x` switches to private use and consumes the rest.
5. At the end, an open extension without subtags is an error.
6. The subtag-order check is positional, so a late script
   (`en-US-Latn`), a region after a variant (`en-abcde-US`) or a variant
   after an extension are rejected as invalid subtags rather than reordered.

Casing is normalized during parsing (language lower, script Titlecase,
region upper, variant/extension/private-use lower), so the stored `Locale` is
already canonical and `locale_to_string(locale_parse(tag))` is the canonical
tag. Variants keep their tag order (no sorting); the RFC 5646 canonical form
does not reorder them either.

## 5. Canonicalization

`locale_canonical(tag)` = `locale_parse` then `locale_to_string`.

| Subtag | Canonical case | Example |
|---|---|---|
| language | lowercase | `EN` -> `en` |
| script | Titlecase | `hant` -> `Hant`, `HANT` -> `Hant` |
| region | UPPERCASE | `tw` -> `TW` |
| variant | lowercase | `ROZAJ` -> `rozaj` |
| extension singleton | lowercase | `U` -> `u` |
| extension subtags | lowercase | `CA-GREGORY` -> `ca-gregory` |
| private-use subtags | lowercase | `X-PHONEBK` -> `x-phonebk` |

Re-emission order: language, script, region, variants, extensions, private
use, each joined with `-`; `x-` is re-added before the private-use subtags.

Examples: `"EN-us"` -> `"en-US"`, `"zh-hant-tw"` -> `"zh-Hant-TW"`,
`"DE-de-1996"` -> `"de-DE-1996"`, `"x-ABC-DEF"` -> `"x-abc-def"`.

NOT applied: Preferred-Value substitution (`iw` -> `he`, `in` -> `id`,
`ji` -> `yi`, `no` -> `nb`, `sh` -> `sr-Latn`, ...), likely-subtags
inference, deduplication of redundant subtags, IANA validity. Canonicalization
here is casing plus structural re-emission only.

## 6. Error catalog

All errors are `Err` payloads beginning with `"locale: "`; the first problem
in parse order wins. Messages are byte-exact and pinned by the suite.

| Message | Trigger |
|---|---|
| `locale: empty tag` | input is `""`. |
| `locale: empty subtag` | any `-`-separated part is empty (`"en-"`, `"-en"`, `"en--US"`). |
| `locale: invalid language: X` | first subtag (not `x`) is not `2*8ALPHA` (`"e"`, `"1n"`, `"en_"`). |
| `locale: empty private use` | `x` is the last subtag or the whole tag (`"x"`, `"en-x"`, `"en-u-ca-x"`). |
| `locale: invalid private-use subtag: X` | a subtag after `x` is not `1*8alphanum` (`"en-x-abcdefghi"`). |
| `locale: invalid subtag: X` | a subtag matches no positional shape (`"en-12"`, `"en-abc"`, `"en-Latn-US-ABCD"`, `"en-abcdefghi"`), including a length-1 non-alphanumeric subtag outside an extension, and any out-of-order script/region/variant. |
| `locale: invalid extension subtag: X` | inside an open extension, a subtag is not `2*8alphanum` (`"en-a-b_c"`), or a length-1 non-alphanumeric subtag appears (`"en-a-_"`). |
| `locale: extension without subtags: S` | a singleton is never followed by an extension subtag (`"en-u"`, `"en-a-b"` where `b` starts a new singleton, `"en-a-1"`). |
| `locale: duplicate singleton: S` | the same extension singleton appears twice (`"en-u-ca-gregory-u-nu-latn"`). |
| `locale: duplicate variant: V` | the same variant subtag appears twice (`"de-1901-1901"`). |

## 7. RFC 4647 Lookup as implemented

`locale_lookup(requested, available)`:

1. An empty `available` list returns `None`.
2. For each range in `requested`, in priority order:
   - a range exactly equal to `"*"` is skipped (RFC 4647 3.4: it matches
     everything and conveys no preference);
   - otherwise the range is matched against the available tags from the most
     specific form down:
     a. byte-exact match is tried first, then ASCII case-insensitive match
        (per range candidate); the **available** tag is returned with its own
        casing;
     b. if no tag matches, the range is truncated one step and (a) repeats;
     c. when the range becomes empty, the next requested range is tried.
3. `None` when no requested range matches (the caller applies its default).

Truncation step (RFC 4647 3.4): remove the rightmost subtag; then, while the
new rightmost subtag is a single letter or digit (an extension singleton or
the private-use `x`), remove it as well, since such a subtag cannot end a
valid range.

Worked examples (from the RFC and the suite):

```
range zh-Hant-CN-x-private1-private2
  1. zh-Hant-CN-x-private1-private2   (exact)
  2. zh-Hant-CN-x-private1
  3. zh-Hant-CN
  4. zh-Hant
  5. zh
  6. (default)

de-AT  with available [de-DE, de]  -> de
zh-Hant-CN with available [zh-Hant, zh] -> zh-Hant
zh-Hans-CN with available [zh-Hant, zh] -> zh
en-US-u-ca-gregory with available [en-US, en] -> en-US
```

A range needs no validation: ill-formed ranges simply fail to match (RFC 4647
2.1 notes ranges need not be well-formed). Extended language ranges are not
supported; a `"*"` in a non-first position is treated as a literal subtag
that can never match.

## 8. Fallback chains as implemented

`locale_fallback_chain(tag)` returns the ordered candidates for resolving a
request against default data:

1. the canonical tag itself (`locale_to_string` of the parse);
2. the same tag with extensions and private use dropped (language, script,
   region, variants only), pushed only if different from (1) and non-empty;
3. repeated truncation of (2) with the section 7 truncation rule, until
   nothing is left.

Duplicates are collapsed implicitly: step (2) is skipped when equal to (1),
and truncation is strictly shorter each step. An invalid tag (including `""`)
yields an empty vector -- there is nothing to resolve.

Examples:

```
de-AT                             -> [de-AT, de]
sr-latn-rs                        -> [sr-Latn-RS, sr-Latn, sr]
en-u-ca-gregory                   -> [en-u-ca-gregory, en]
zh-Hant-CN-u-ca-chinese-x-priv    -> [zh-Hant-CN-u-ca-chinese-x-priv, zh-Hant-CN, zh-Hant, zh]
x-priv                            -> [x-priv]
??                                -> []
```

## 9. Language registry

`_registry_data()` is a single `Vec[Str]` of 50 packed rows
`"subtag|name|script"`, rebuilt per call (no global state, no parallel
vectors). `locale_registry_count()` returns 50.
`locale_registry_get(subtag)` lowercases the argument and returns
`Some(LangInfo)` for the first byte-equal row, else `None`; names and default
scripts are curated English names and hand-picked default scripts (not IANA or
CLDR data). Representative rows: `en|English|Latn`, `zh|Chinese|Hans`,
`ja|Japanese|Jpan`, `ko|Korean|Kore`, `ru|Russian|Cyrl`, `ar|Arabic|Arab`,
`el|Greek|Grek`, `th|Thai|Thai`, `he|Hebrew|Hebr`, `hy|Armenian|Armn`.
Unknown subtags (`"xx"`, `"zzz"`, `""`) return `None`.

## 10. API signatures

```xi
pub fn locale_parse(tag: Str) -> Result[Locale, Str]
pub fn locale_to_string(loc: &Locale) -> Str
pub fn locale_canonical(tag: Str) -> Result[Str, Str]
pub fn locale_is_valid(tag: Str) -> Bool
pub fn locale_lookup(requested: &Vec[Str], available: &Vec[Str]) -> Option[Str]
pub fn locale_fallback_chain(tag: Str) -> Vec[Str]
pub fn locale_registry_get(subtag: Str) -> Option[LangInfo]
pub fn locale_registry_count() -> Int
```

All functions are free functions; there is no global mutable state. Only
`locale_parse`, `locale_to_string`, `locale_canonical`, `locale_lookup` and
`locale_fallback_chain` are O(tag length)-ish; the registry build is O(50)
per call.

## 11. Non-goals

- Basic/Extended Filtering (RFC 4647 3.3), language priority weights,
  `Accept-Language` parsing.
- Likely-subtags matching, Preferred-Value canonicalization, Suppress-Script,
  IANA Language Subtag Registry validation.
- Extlang, grandfathered/irregular and non-ASCII tags.
- Locale data formatting (dates, numbers, currency) -- see the `xiom.l10n.*`
  family.
- Default-data semantics: `locale_fallback_chain` returns candidates; it does
  not read or return any content.

## 12. Test plan

`tests/test_conformance.xi` runs 24 checks, one `[PASS]`/`[FAIL]` line each,
with all fixtures built in-test:

| # | Check |
|---|---|
| 1 | canonical casing: `EN-us` -> `en-US`, `zh-hant-tw` -> `zh-Hant-TW`, `FR` -> `fr`, `sr-latn-rs` -> `sr-Latn-RS` |
| 2 | canonical casing of variants/extensions/private use, incl. `x-ABC-DEF` -> `x-abc-def` |
| 3 | parse fields: language/script/region, absent script/region stay `""` |
| 4 | variants by shape: `sl-rozaj-biske-1994`, `de-1901`, `en-US-ABCD1` -> `abcd1` |
| 5 | extensions: `en-a-bbb-c-ddd`, `en-US-u-ca-gregory-t-en-latn` |
| 6 | private use: after `x-`, private-use-only `x-abc-def`, single-subtag `en-x-a` |
| 7 | invalid: `""`, `en-`, `-en`, `en--US`, `e`, `1n` with exact messages |
| 8 | invalid positions: `en-12`, `en-abc`, `en-Latn-US-ABCD`, `en-US-Latn`, `en-abcdefghi` |
| 9 | invalid extension/private use: `en-u`, `en-a-b`, `en-a-b_c`, `en-x`, `en-x-abcdefghi` |
| 10 | duplicates: `de-1901-1901`, `en-u-ca-gregory-u-nu-latn` |
| 11 | `locale_is_valid` true set (incl. `x-a`, `abcd`) |
| 12 | `locale_is_valid` false set |
| 13 | registry hits, case-insensitive (`en`, `zh`, `JA`, `Cy`) |
| 14 | registry count in 30..50 and misses return `None` |
| 15 | lookup exact, then `de-AT` -> `de` (RFC example) |
| 16 | lookup `zh-Hant-CN` -> `zh-Hant`, `zh-Hans-CN` -> `zh` (RFC example) |
| 17 | lookup requested priority order |
| 18 | lookup skips `"*"`; `"*"` alone yields `None` |
| 19 | lookup case-insensitive, returns available casing |
| 20 | lookup extension/private-use truncation, RFC `x-private1-private2` trace |
| 21 | lookup no-match and empty `available` -> `None` |
| 22 | fallback chain: `de-AT`, `en`, `sr-latn-rs` |
| 23 | fallback chain drops extensions/private use first |
| 24 | fallback chain: invalid tags -> `[]`, `x-priv` -> one step |

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.locale
```

Expected: `passed=24 failed=0 program_exit=0 exit=0`.

License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
