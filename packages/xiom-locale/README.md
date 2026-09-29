# xiom.locale

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.
> **Scope:** BCP-47 language tag parsing, canonicalization, RFC 4647 Lookup
> matching and fallback chains, plus a small curated language registry.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare` and `xiom.convert`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.locale` is a small, dependency-free language-tag codec over in-memory
`Str` values. It parses a BCP-47 (RFC 5646) language tag into its positional
components, rejects malformed tags with a precise reason, re-emits the
canonical casing form, performs RFC 4647 **Lookup** matching of a language
priority list against available tags, builds ordered fallback chains for
default-data resolution and exposes a curated registry of 50 common
languages. There is no FFI, no file I/O, no floating point and no global
state. `SPEC.md` has the full grammar, canonicalization table, error catalog,
lookup/truncation algorithm and test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `locale_parse(tag)` | `Result[Locale, Str]` | Split a tag into language/script/region/variants/extensions/private_use and normalize casing. `Err("locale: ...")` with a precise syntax reason on the first problem. |
| `locale_to_string(loc)` | `Str` | Re-emit a parsed `Locale` as canonical text (inverse of `locale_parse` for every accepted tag). |
| `locale_canonical(tag)` | `Result[Str, Str]` | `locale_parse` + `locale_to_string`: `"EN-us"` -> `"en-US"`, `"zh-hant-tw"` -> `"zh-Hant-TW"`. Errors pass through from `locale_parse`. |
| `locale_is_valid(tag)` | `Bool` | `true` when `locale_parse(tag)` succeeds. |
| `locale_lookup(requested, available)` | `Option[Str]` | RFC 4647 Lookup: exact match first, then progressive right-to-left truncation; `"*"` ranges are skipped; case-insensitive; returns the first matching available tag (preserving its casing). |
| `locale_fallback_chain(tag)` | `Vec[Str]` | Ordered resolution candidates: canonical tag, then extensions/private use dropped, then right-to-left truncations of that base. Empty for an invalid tag. |
| `locale_registry_get(subtag)` | `Option[LangInfo]` | Curated registry row for a language subtag (case-insensitive), else `None`. |
| `locale_registry_count()` | `Int` | Number of registry rows (50). |

### Locale

| Field | Type | Meaning |
|---|---|---|
| `language` | `Str` | Lowercased primary language subtag, `""` for a private-use-only tag. |
| `script` | `Str` | Titlecased script subtag, `""` when absent. |
| `region` | `Str` | Uppercased region subtag, `""` when absent. |
| `variants` | `Vec[Str]` | Lowercased variant subtags in tag order; empty when absent. |
| `extensions` | `Vec[Str]` | Extensions with the singleton first (`"u-ca-gregory"`); empty when absent. |
| `private_use` | `Str` | Private-use subtags without the `x-` prefix (`"abc-def"`); `""` when absent. |

### LangInfo

| Field | Type | Meaning |
|---|---|---|
| `subtag` | `Str` | Canonical (lowercase) ISO 639 subtag, e.g. `"en"`. |
| `name` | `Str` | English name, e.g. `"English"`. |
| `default_script` | `Str` | Curated default script (ISO 15924), e.g. `"Latn"`, `"Hans"`, `"Jpan"`. |

## Grammar notes

- Accepted: `language ["-" script] ["-" region] *("-" variant) *("-" extension)
  ["-" privateuse]`, plus private-use-only tags (`"x-abc-def"`).
- Subtag shapes: language `2*8ALPHA`, script `4ALPHA`, region `2ALPHA / 3DIGIT`,
  variant `5*8alphanum / (DIGIT 3alphanum)`, extension `singleton 1*("-" 2*8alphanum)`
  with singleton `alphanum` except `x`, private use `"x" 1*("-" 1*8alphanum)`.
- Order is strict: script before region before variants before extensions
  before private use. Duplicate variants and duplicate singletons are
  rejected.
- Casing is normalized during parsing (language lower, script Titlecase,
  region upper, everything else lower), so the stored `Locale` fields and
  `locale_to_string` are always canonical.

## Usage

```xi
use xiom.locale;
use xiom.io;

fn main() -> Int {
  let r = locale_parse("zh-hant-tw-u-ca-chinese-x-priv");
  match r {
    Ok(loc) => {
      io.println(loc.language);              // "zh"
      io.println(loc.script);                // "Hant"
      io.println(loc.region);                // "TW"
      io.println(loc.private_use);           // "priv"
    },
    Err(e) => { io.println(e); },
  }
  match locale_canonical("EN-us") {
    Ok(c) => { io.println(c); },             // "en-US"
    Err(e) => { io.println(e); },
  }

  var avail = Vec[Str].new();
  avail.push("de-DE");
  avail.push("de");
  var req = Vec[Str].new();
  req.push("de-AT");                         // RFC 4647 lookup example
  match locale_lookup(&req, &avail) {
    Some(tag) => { io.println(tag); },       // "de"
    None => { io.println("(default)"); },
  }

  let chain = locale_fallback_chain("de-AT"); // ["de-AT", "de"]
  match locale_registry_get("zh") {
    Some(info) => { io.println(info.name); }, // "Chinese"
    None => { io.println("unknown"); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.locale
```

Expected tail: 24 `[PASS]` lines, `xiom.locale: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Lookup only:** RFC 4647 Basic and Extended Filtering are not implemented,
  and `locale_lookup` never returns more than one tag.
- **No likely-subtags:** no `zh-TW` -> `zh-Hant` style matching, no
  Preferred-Value mapping (`iw` -> `he`, `sh` -> `sr-Latn`, `no` -> `nb`), no
  Suppress-Script and no truncation into default scripts. Canonicalization is
  casing-only.
- **No IANA subtag validation:** any `2-8ALPHA` first subtag is accepted as a
  language (so `"zz"` is "valid"); script/region/variant subtags are not
  checked against the registry.
- **No extlang, no grandfathered tags:** `zh-cmn-Hans` and `i-klingon` are
  rejected; only the RFC 5646 `langtag` production (minus extlang) and
  private-use-only tags parse.
- **ASCII only:** every subtag must be ASCII alphanumeric; non-ASCII input is
  always an error.
- **Strict ordering:** subtags are classified by position, so tags that
  violate RFC 5646 order (e.g. `en-US-Latn`) are rejected rather than
  reordered.
- **Registry is curated:** 50 common languages with a hand-picked default
  script; it is not the full IANA Language Subtag Registry nor CLDR data.
- **Fallback chain drops extensions and private use before truncating**
  (RFC 4647 3.4.1 permits this for lookup); it does not apply default-data
  semantics itself -- it returns the ordered candidates and the caller picks.

See `SPEC.md` for the full grammar, canonicalization table, error catalog,
algorithm description and test plan. License: MIT OR Apache-2.0 (see the
repository root `LICENSE`).
