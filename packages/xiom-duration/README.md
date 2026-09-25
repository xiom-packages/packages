# xiom.duration

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness on compiler v0.61.3 (22/22). NOT published yet.
> **Scope:** strict ISO 8601 duration parsing, canonical formatting, flat
> accessors and a restricted whole-seconds helper.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
> `xiom.convert`).

## What it is

`xiom.duration` implements the ISO 8601 duration form (`PnYnMnWnDTnHnMnS`)
without floating point, calendar arithmetic or FFI. Parsing is strict: an
optional `+`/`-` sign, a required `P`, date components in the order `Y M W D`,
an optional `T` introducing time components in the order `H M S`, at least
one component overall, no duplicates, no reordering. Component integers are
signed 64-bit `Int`s with leading zeros allowed; the seconds fraction is
validated (1..9 digits) and kept as text, so no precision is lost. Formatting
emits the canonical minimal form: zero components are omitted and every zero
duration is `P0D`.

Non-goals: no calendar math (a month has no fixed second count here), no
timestamp conversion, no relaxed/lowercase/comma forms, no `Float64`.

## API

| Function | Returns | Description |
|---|---|---|
| `duration_parse(s)` | `Result[Duration, Str]` | Strict ISO 8601 parse; `Err("duration: ...")` per the SPEC catalog |
| `duration_format(d)` | `Str` | Canonical form: sign, non-zero components, verbatim fraction, `P0D` for zero |
| `duration_sign(d)` | `Int` | `-1` for a `-` duration, else `1` |
| `duration_has_years(d)` .. `duration_has_minutes(d)` | `Bool` | True when that component is non-zero |
| `duration_has_seconds(d)` | `Bool` | True when seconds is non-zero **or** a fraction is present |
| `duration_value(d, name)` | `Result[Int, Str]` | Value by name (`"months"`, `"seconds"`, ...), `Err` for unknown names |
| `duration_fraction(d)` | `Str` | Fraction digit text exactly as written, `""` when absent |
| `duration_total_seconds(d)` | `Result[Int, Str]` | `sign * (h*3600 + m*60 + s)` only for time-only, fraction-free durations |

`pub type Duration = { sign: Int; years: Int; months: Int; weeks: Int; days: Int; hours: Int; minutes: Int; seconds: Int; fraction: Str; }`

```xi
use xiom.duration;
match duration_parse("P1Y2M3W4DT5H6M7S") {
  Ok(d) => {
    duration_sign(&d);              // 1
    duration_has_weeks(&d);         // true
    duration_value(&d, "hours");    // Ok(5)
    duration_format(&d);            // "P1Y2M3W4DT5H6M7S"
  },
  Err(e) => { /* "duration: <catalog message>" */ },
}
match duration_parse("-PT0.50S") {
  Ok(d) => { duration_fraction(&d); },        // "50" (verbatim)
  Err(e) => { },
}
match duration_parse("PT90M") {
  Ok(d) => { duration_total_seconds(&d); },   // Ok(5400)
  Err(e) => { },
}
```

## Canonical form

| Input | `duration_format` output |
|---|---|
| `P1D` | `P1D` |
| `+P1D` | `P1D` |
| `P01D` | `P1D` |
| `P1Y0M0W0DT0H0M0S` | `P1Y` |
| `PT0S` | `P0D` |
| `-P0D` | `-P0D` |
| `PT0.50S` | `PT0.50S` (fraction text is never rewritten) |

`format(parse(s)) == s` for every canonical `s`, and
`parse(format(d)) == d` field-for-field.

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.duration
```

22 conformance tests cover component parsing and defaults, zero forms,
leading zeros and the 64-bit bound, the verbatim seconds fraction, every
error family (missing `P`, empty duration, `T` without components, bad order,
duplicates, bad number, bad fraction, trailing tokens, number too large),
the accessors, canonical formatting and round-trips, and the
total-seconds helper including its exact-`Int`-max boundary and overflow
errors.

## Limitations

- Components are signed 64-bit `Int`s; larger integers are `Err(number too
  large)`. The whole-seconds total is bounded the same way.
- The seconds fraction is text; `duration_total_seconds` refuses fractional
  seconds instead of rounding. No fraction normalization is performed.
- No calendar arithmetic: `P1M`/`P1Y` cannot be expressed in seconds, and
  `duration_total_seconds` returns `Err(has date components)`.
- `duration_has_*` reports non-zero values (there are no presence flags), so
  `P0D` and `PT0S` cannot be distinguished.
- Strict ISO 8601 only: no lowercase designators, comma decimal separator,
  whitespace, negative components or `P1W`-only alternates beyond `P0D`
  (weeks remain a normal component).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
