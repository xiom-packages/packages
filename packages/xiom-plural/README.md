# xiom.plural

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** English pluralization and singularization for lowercase ASCII
> words, with irregular/invariant tables and ordered suffix rules.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
> `xiom.string.lowercase`, `xiom.string.uppercase`, `xiom.convert`).

## What it is

`xiom.plural` turns English words between singular and plural forms. Words
are matched against an irregular table (person/people, child/children, ...),
an invariant list (sheep, deer, fish, series, species) and then a short set
of ordered suffix rules (`-es`, `-ies`, `-ves`, `-oes`, default `-s`). The
rules are documented in full in [SPEC.md](SPEC.md).

The input contract is lowercase ASCII English words; an initial uppercase
ASCII letter is preserved on the output (`City` -> `Cities`,
`Person` -> `People`). All functions are total -- unknown words get a
best-effort rule-table result instead of an error.

## API

| Function | Returns | Description |
|---|---|---|
| `plural_pluralize(word)` | `Str` | Plural form: `city` -> `cities`, `person` -> `people`. |
| `plural_singularize(word)` | `Str` | Singular form: `cities` -> `city`, `people` -> `person`. |
| `plural_is_irregular(word)` | `Bool` | True for table words in either direction plus invariants. |
| `plural_count(n, singular)` | `Str` | `"1 item"`, `"2 items"`, `"0 items"`, `"2 people"`. |
| `plural_pluralize_all(words)` | `Vec[Str]` | Element-wise pluralizer over `&Vec[Str]`. |

## Usage

```xi
use xiom.plural;
use xiom.io;

io.println(plural_pluralize("city"));        // "cities"
io.println(plural_pluralize("Person"));      // "People"
io.println(plural_singularize("leaves"));    // "leaf"
io.println(plural_count(2, "person"));       // "2 people"
io.println(plural_is_irregular("children")); // true
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.plural
```

Expected: the namespaced module passes the section-4 namespace rule, 35
`[PASS]` lines, and a final `port: PASS (passed=35 failed=0 exit=0)`.

## Limitations

- English-only; lowercase ASCII input is assumed (only the initial letter's
  case is preserved; the rest is case-folded).
- Rule-table approach, not a dictionary: out-of-table words use the generic
  suffix rules and can be wrong (`buses` -> `buse`, `safe` -> `saves`,
  `movies` -> `movy`). See "Known limitations" in SPEC.md.
- `plural_count` handles only the `1` vs "everything else" distinction; it is
  not a full plural-rules (CLDR) implementation.
- No Result/error type: every function is total and returns the best-effort
  inflection.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
