# xiom.l10n-date

> **Naming:** registry package `xiom.l10n-date`; module namespace `xiom.l10n.date`.

> **Status:** `incubating` -- conformance-tested (18/18); published at `v0.1.0` on the XIOM registry.
> **Scope:** Locale-aware civil-date formatting and parsing with
> caller-supplied month-name tables, plus exact civil-date arithmetic
> (validation, epoch days, weekdays, day-of-year, Julian day numbers and
> Gregorian <-> Julian calendar conversion).
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice` and `xiom.convert.int_to_string`; string comparisons
> go through `xiom.string.compare`). Tests additionally use `xiom.test`,
> `xiom.io`, `xiom.string` and `xiom.string.compare`.

## Scope

A locale here is exactly two caller-supplied vectors: `month_names` (full
names) and `month_abbrs` (abbreviations), each with 12 `Str` entries. There
is no locale database, no global state, no clock and no floating point; every
function is deterministic and pure. Date storage is three `Int` fields
(`CivilDate{ year, month, day }`).

The module covers:

- **Validation** with the Gregorian leap rule: `date_make` returns the exact
  errors `date: invalid month: <m>` / `date: invalid day: <d>`, and February 29
  is accepted only in leap years (2000 yes, 1900 no).
- **Epoch days** since 1970-01-01 (proleptic Gregorian) including correct
  negative values before the epoch (`1969-12-31 -> -1`, `1582-10-15 ->
  -141427`), and the inverse `date_from_epoch_day`.
- **Weekday** (0=Sunday) and **day of year** (1..365/366), correct for
  pre-1970 dates.
- **Julian day numbers** for both calendars and **Gregorian <-> Julian
  calendar conversion** through the shared JDN (Gregorian 1582-10-15 = Julian
  1582-10-05; Gregorian 1900-01-13 = Julian 1900-01-01).
- **Pattern formatting** with tokens `YYYY YY MMMM MMM MM M DD D` over the
  caller's tables; every other pattern byte is a literal.
- **Pattern parsing** back to a validated `CivilDate`, with a precise,
  byte-offset error catalog for bad patterns and bad values.
- **`date_iso_format` / `date_iso_parse`**, a strict `YYYY-MM-DD` pair.

## API

| Function | Returns | Description |
|---|---|---|
| `date_is_leap_year(year)` | `Bool` | Gregorian leap rule: divisible by 4, except centuries not divisible by 400. |
| `date_days_in_month(year, month)` | `Int` | 28..31 for valid months, **0** for months outside 1..12. |
| `date_make(year, month, day)` | `Result[CivilDate, Str]` | Validate and build. `Err("date: invalid month: <m>")` (checked first) or `Err("date: invalid day: <d>")`. |
| `date_is_valid(year, month, day)` | `Bool` | Non-failing validation predicate. |
| `date_year(d)` / `date_month(d)` / `date_day(d)` | `Int` | Field accessors. |
| `date_jdn_from_gregorian(d)` | `Int` | JDN of a proleptic Gregorian date (`1970-01-01` -> 2440588). |
| `date_jdn_from_julian(d)` | `Int` | JDN of a proleptic Julian-calendar date. |
| `date_gregorian_from_jdn(jdn)` | `CivilDate` | Inverse of `date_jdn_from_gregorian`. |
| `date_julian_from_jdn(jdn)` | `CivilDate` | Inverse of `date_jdn_from_julian`. |
| `date_gregorian_to_julian(d)` | `CivilDate` | Same physical day in the Julian calendar. |
| `date_julian_to_gregorian(d)` | `CivilDate` | Same physical day in the Gregorian calendar. |
| `date_to_epoch_day(d)` | `Int` | Days since 1970-01-01; negative before the epoch. |
| `date_from_epoch_day(z)` | `CivilDate` | Inverse of `date_to_epoch_day`. |
| `date_weekday(d)` | `Int` | 0=Sunday .. 6=Saturday. |
| `date_day_of_year(d)` | `Int` | 1..365, or 366 in leap years. |
| `date_format(d, pattern, month_names, month_abbrs)` | `Result[Str, Str]` | Expand `YYYY YY MMMM MMM MM M DD D`; literals copied verbatim; tables must have 12 entries. |
| `date_parse(text, pattern, month_names, month_abbrs)` | `Result[CivilDate, Str]` | Strict pattern parse; fields absent from the pattern default to 1970-01-01 and the assembled date is validated. |
| `date_iso_format(d)` | `Result[Str, Str]` | `"YYYY-MM-DD"` (year 0..9999). |
| `date_iso_parse(text)` | `Result[CivilDate, Str]` | Strict 10-byte `"YYYY-MM-DD"` parse. |

Arithmetic functions assume a valid `CivilDate` (build one with `date_make`);
`date_format` and both ISO functions validate first and fail with the
validation message. The full token table, calendar formulas, error catalog and
test plan are in `SPEC.md`.

## Usage

```xi
use xiom.l10n.date;
use xiom.io;

fn main() -> Int {
  var names = Vec[Str].new();
  names.push("January"); names.push("February"); names.push("March");
  // ... 12 entries in calendar order ...
  var abbrs = Vec[Str].new();
  abbrs.push("Jan"); abbrs.push("Feb"); abbrs.push("Mar");
  // ... 12 entries, pushed month by month alongside names ...

  match date_make(2024, 2, 29) {
    Ok(d) => {
      match date_format(&d, "D MMMM YYYY", &names, &abbrs) {
        Ok(s) => { io.println(s); },   // 29 February 2024
        Err(e) => { io.println(e); },
      }
      match date_iso_format(&d) {
        Ok(s) => { io.println(s); },   // 2024-02-29
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.l10n-date
```

Expected tail: 18 `[PASS]` lines, `xiom.l10n.date: all tests passed`, then
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No locale database:** no CLDR, no bundled month names, no day names
  (weekday is numeric), no eras, no time zones, no time of day. The caller
  supplies both month tables; their content is not inspected (any `Str`,
  including multi-byte UTF-8, is matched byte-wise, longest entry first within
  a table).
- **Pure calendar arithmetic:** no clock, no IO, no FFI -- "today" is the
  caller's job.
- **Year range:** formatting/parsing `YYYY`/`YY` supports years 0..9999
  (`Err("date: year out of range: <y>")` otherwise). The JDN / epoch-day path
  supports any year >= -4700, where the division operands stay non-negative.
- **Strict parsing:** exact digit widths per token (`YYYY`=4, `YY`=2, `MM`=2,
  `DD`=2, `M`/`D`=1..2), byte-wise literal match, no lenient separators, and
  no surrounding text. Fields absent from the pattern default to 1970-01-01,
  so `"02-29"` with `"MM-DD"` is `date: invalid day: 29` (1970 is not a leap
  year).
- **Patterns are ASCII-letter tokens:** letters cannot be used as literals and
  there is no quoting/escaping; adjacent tokens split greedily
  (`"YYYYMMDD"` scans as `YYYY MM DD`, and `"YYYYY"` is an unknown-token
  error). `MMMM` searches only `month_names`, `MMM` only `month_abbrs`.
- **`YY` window:** parsing maps 00..68 -> 2000..2068 and 69..99 ->
  1969..1999, so `YY` round-trips only inside 1969..2068.
- Compiler notes: `Ok`/`Err` are constructed only in leaf helpers
  (`_date_ok`, `_date_err`, `_str_ok`, `_str_err`); `Str` equality always goes
  through `xiom.string.compare.str_compare`; byte reads are widened and masked;
  values read from `Vec[Str]` are bound to typed locals first.

See `SPEC.md` for the exact semantics, calendar conversion rules, error
catalog and test plan. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
