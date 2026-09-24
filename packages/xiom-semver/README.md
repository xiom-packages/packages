# xiom.semver

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness on compiler v0.61.3 (32/32). NOT published yet.
> **Scope:** Strict Semantic Versioning 2.0 parsing, canonical formatting,
> precedence comparison, and single-comparator range satisfaction.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
> `xiom.convert`).

## What it is

`xiom.semver` implements SemVer 2.0 without floating point, locale data or
FFI. Versions parse strictly (three numeric components, no leading zeros,
`[0-9A-Za-z-]` identifiers, no empty identifiers); comparison follows
specification section 11 (numeric triple, then pre-release precedence, with
build metadata ignored); ranges are single comparators evaluated on top of the
same comparator.

## API

| Function | Returns | Description |
|---|---|---|
| `semver_parse(s)` | `Result[SemVer, Str]` | Strict SemVer 2.0 parse; `pre`/`build` are the raw dotted lists, `""` when absent |
| `semver_format(v)` | `Str` | Canonical `MAJOR.MINOR.PATCH[-pre][+build]` |
| `semver_compare(a, b)` | `Int` | `-1`/`0`/`1` precedence compare; build ignored |
| `semver_is_prerelease(v)` | `Bool` | True when `pre` is non-empty |
| `semver_satisfies(v, range)` | `Result[Bool, Str]` | Evaluate one range string |
| `semver_satisfies_any(v, ranges)` | `Result[Bool, Str]` | True when any range matches; empty list is `false` |

`pub type SemVer = { major: Int; minor: Int; patch: Int; pre: Str; build: Str; }`

```xi
use xiom.semver;
match semver_parse("1.2.3-beta.2+exp.sha") {
  Ok(v) => { /* v.major == 1, v.pre == "beta.2" */ },
  Err(e) => { /* "semver: ..." */ },
}
let ranges = Vec[Str].new();
ranges.push("^1.2.3");
ranges.push("~3.1");
let ok = semver_satisfies_any(&v, &ranges);   // Ok(true/false)
```

## Range grammar

| Range | Meaning |
|---|---|
| `*` | any version |
| `1.2.3`, `=1.2.3` | exactly `1.2.3` (build metadata ignored) |
| `>1.2.3`, `>=1.2.3`, `<1.2.3`, `<=1.2.3` | ordinary precedence comparison |
| `^1.2.3` | `>=1.2.3 <2.0.0`; `^0.2.3` -> `>=0.2.3 <0.3.0`; `^0.0.3` -> `>=0.0.3 <0.0.4` |
| `~1.2.3` | `>=1.2.3 <1.3.0`; `~1.2` -> `>=1.2.0 <1.3.0`; `~1` -> `>=1.0.0 <2.0.0` |

Operands may be partial for `^`, `~` and the comparison operators; missing
components zero-pad (`>1.2` is `>1.2.0`, `=1` is `=1.0.0`). `^` with a zero
major: `^0.0` -> `>=0.0.0 <0.1.0`, `^0` -> `>=0.0.0 <1.0.0`.

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.semver
```

32 conformance tests cover parsing (basic, pre-release, build, leading zeros,
missing parts, junk), formatting round-trips, precedence (including prefix,
numeric-vs-alphanumeric, and build-ignored cases), `is_prerelease`, every
range operator in both directions, caret/tilde bounds, `satisfies_any`, range
error messages, and 64-bit / arbitrary-length numeric edge cases.

## Limitations

- Exactly one comparator per range string; whitespace-AND lists such as
  `>=1 <2` are malformed, as are OR-lists and hyphen ranges (`1.2.3 - 2.0.0`).
- Range matching is purely comparator-based: a pre-release version matches
  whenever it compares inside the bounds (e.g. `^1.0.0` matches
  `1.5.0-alpha`), with no separate prerelease opt-in.
- `major`/`minor`/`patch` are 64-bit `Int`s; components above
  `9223372036854775807` are `Err("semver: number too large: ...")`.
  Pre-release numeric identifiers have no such limit (compared as digit
  strings).
- Range operands must be well formed versions; wildcards (`1.2.x`) are
  rejected.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
