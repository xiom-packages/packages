# xiom.semver SPEC

Version: 0.1.0 (incubating, not published).

## Scope

Strict Semantic Versioning 2.0 parsing, canonical formatting, precedence
comparison, and single-comparator range satisfaction, implemented in pure
XIOM on `xiom.std` (`xiom.string`, `xiom.string.compare`, `xiom.convert`).

## Non-goals

Whitespace-AND / OR-list / hyphen range syntax, wildcard operands (`1.2.x`),
npm-style prerelease exclusion from ranges, arbitrary-precision numeric
triples, sorting, and registry operations.

## Data model

```xiom
pub type SemVer = { major: Int; minor: Int; patch: Int; pre: Str; build: Str; }
```

`pre` and `build` hold the raw dotted identifier lists exactly as written and
are `""` when absent.

## Grammar

Version string (strict, `semver_parse`):

```
version  := major "." minor "." patch [ "-" pre ] [ "+" build ]
major    := "0" | non-zero-digit *digit
minor    := major
patch    := major
pre      := pre-id *( "." pre-id )
build    := build-id *( "." build-id )
pre-id   := 1*( alphanum / "-" )        ; all-digit => no leading zero unless "0"
build-id := 1*( alphanum / "-" )        ; leading zeros allowed
alphanum := "0-9" / "A-Z" / "a-z"
```

Range string (`semver_satisfies`): `"*"`, or exactly one comparator:

```
range   := "*" | [ op ] operand
op      := "=" | ">" | ">=" | "<" | "<=" | "^" | "~"
operand := major [ "." minor [ "." patch ] ] [ "-" pre ] [ "+" build ]
```

Missing operand components are `0`. Whitespace is never allowed; a range that
is not exactly one comparator is `Err("semver: malformed range: <range>")`.

## Comparison (SemVer 2.0 section 11)

1. Compare `major`, then `minor`, then `patch` numerically.
2. A version without a pre-release outranks the same version with one.
3. Compare pre-release identifiers left to right: numeric identifiers
   numerically, alphanumeric identifiers byte-wise (ASCII), numeric before
   alphanumeric. If all identifiers so far are equal, the shorter list sorts
   first. (Numeric identifiers have no leading zeros, so length then bytes
   orders arbitrarily large values.)
4. Build metadata is ignored.

`semver_compare` maps the outcome to `-1`, `0` or `1`.

## Range semantics

| Range | Equivalent |
|---|---|
| `*` | any version |
| `X.Y.Z` / `=X.Y.Z` | `compare(v, X.Y.Z) == 0` (build ignored) |
| `>X.Y.Z` / `>=X.Y.Z` / `<X.Y.Z` / `<=X.Y.Z` | ordinary comparison |
| `^X.Y.Z`, `X > 0` | `>=X.Y.Z <(X+1).0.0` |
| `^0.Y.Z`, `Y > 0` | `>=0.Y.Z <0.(Y+1).0` |
| `^0.0.Z`, `Z` specified | `>=0.0.Z <0.0.(Z+1)` |
| `^0.0` | `>=0.0.0 <0.1.0` |
| `^0` | `>=0.0.0 <1.0.0` |
| `~X.Y.Z`, `~X.Y` | `>=bound <X.(Y+1).0` |
| `~X` | `>=X.0.0 <(X+1).0.0` |

The lower bound is always the operand itself (pre-release suffix included).
Matching is purely comparator-based: pre-release versions match whenever they
compare inside the bounds; there is no npm-style opt-in.

`semver_satisfies_any` evaluates every element and returns `Ok(true)` when any
matches, `Ok(false)` for an empty vector, and the first range error otherwise
(a malformed element is an error even when an earlier element already
matched).

## Error catalog

| Condition | Message |
|---|---|
| `semver_parse("")` | `semver: empty input` |
| non-digit first byte / trailing junk | `semver: malformed version: <s>` |
| `"1"` / `"1."` | `semver: missing minor: <s>` |
| `"1.2"` / `"1.2."` | `semver: missing patch: <s>` |
| multi-digit component starting with `0` | `semver: leading zero in major|minor|patch: <s>` |
| component above the 64-bit signed range | `semver: number too large: <s>` |
| `"1.0.0-"`, `"1.0.0-a..b"` | `semver: empty pre-release identifier: <s>` |
| bad byte in a pre-release identifier | `semver: malformed pre-release: <s>` |
| numeric pre-release identifier with leading zero | `semver: leading zero in pre-release identifier: <s>` |
| `"1.0.0+"`, `"1.0.0+a..b"` | `semver: empty build identifier: <s>` |
| bad byte in a build identifier | `semver: malformed build: <s>` |
| `semver_satisfies(v, "")` | `semver: empty range` |
| not exactly one valid comparator | `semver: malformed range: <range>` |

## Test plan

32 checks in `tests/test_conformance.xi`: basic/zero parsing; pre-release and
build retention; combined suffix; leading-zero, missing-part, junk, empty
identifier and empty input errors; format round-trips plus a hand-built
struct; numeric triple ordering; build-ignored; release-outranks-pre;
left-to-right identifier order; numeric-vs-numeric, numeric-vs-alphanumeric
and prefix ordering; `is_prerelease`; `*`; exact/`=`; `>`/`>=`; `<`/`<=`;
caret in-major and zero-major bounds; tilde full/partial; zero-padded partial
comparison operands; pre-release bounds; range error messages;
`satisfies_any` (match, empty list, malformed element); 64-bit components;
huge numeric pre-release identifiers.

## Known limitations

- One comparator per range string; no whitespace-AND (`>=1 <2`), OR-list or
  hyphen-range syntax.
- No wildcard operands (`1.2.x`).
- `major`/`minor`/`patch` are 64-bit `Int`s; larger triples are rejected
  (`semver: number too large`). Pre-release numeric identifiers are unbounded.
- Ranges have no separate prerelease opt-in: they match prereleases by
  comparison.
