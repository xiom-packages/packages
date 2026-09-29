# xiom.l10n-time

> **Naming:** registry package `xiom.l10n-time`; module namespace `xiom.l10n.time`.

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.
> **Scope:** Locale-style time-of-day formatting and parsing, 12h/24h
> conversion, day-period classification and timezone-offset handling with
> caller-supplied labels and boundaries.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

A locale here is exactly the strings the caller passes: AM/PM labels, day
period boundaries and format patterns. There is no locale database, no global
state, no clock and no DST rules; the caller owns every policy decision.

The time model is a validated `TimeOfDay` (`hour` 0..23, `minute` 0..59,
`second` 0..59). A `TimeOffset` is `sign * (hours*60 + minutes)` minutes from
UTC, constrained to -12:00..+14:00. Nothing in the module uses floating
point, vectors, allocation-heavy builders or FFI, so every operation is exact
and reproducible.

Covered:

- 24h <-> 12h conversion with the midnight/noon edge rules (12 AM = 00,
  12 PM = 12) and caller-supplied AM/PM labels;
- `HH:MM:SS`-style pattern formatting with separate 24h (`HH`/`H`) and 12h
  (`hh`/`h`/`A`) token sets;
- parsing `HH:MM[:SS]` with an optional label matched case-sensitively;
- day-period classification (morning / afternoon / evening / night) against
  four caller-supplied boundaries, with night wrapping past midnight;
- timezone offsets: parse `+HH:MM`, `-HH:MM`, `Z`; format canonically;
  convert to and from signed minutes; apply to and strip from a `TimeOfDay`
  with wrapping past midnight.

## API

| Function | Returns | Description |
|---|---|---|
| `l10n_time_is_valid(hour, minute, second)` | `Bool` | Range check for hour 0..23, minute 0..59, second 0..59. |
| `l10n_time_of_day(hour, minute, second)` | `Result[TimeOfDay, Str]` | Validating constructor; each out-of-range field has its own error. |
| `l10n_time_equals(a, b)` | `Bool` | Field-wise equality of two times. |
| `l10n_time_total_seconds(t)` | `Int` | Seconds since midnight (0..86399 for a valid time). |
| `l10n_time_from_total_seconds(total)` | `Result[TimeOfDay, Str]` | Inverse of `l10n_time_total_seconds`; 0..86399 only. |
| `l10n_hour_24_to_12(hour24)` | `Result[Int, Str]` | 0 and 12 -> 12, 13..23 -> hour - 12, 1..11 unchanged. |
| `l10n_hour_12_to_24(hour12, is_pm)` | `Result[Int, Str]` | 12 AM -> 0, 12 PM -> 12, 1..11 PM -> +12. |
| `l10n_hour_period(hour24, am_label, pm_label)` | `Result[Str, Str]` | AM label for 0..11, PM label for 12..23. |
| `l10n_hour_12_label(hour24, am_label, pm_label)` | `Result[Str, Str]` | Face hour + " " + label ("12 AM", "1 PM"). |
| `l10n_time_format(t, pattern, am_label, pm_label)` | `Result[Str, Str]` | Expand `HH`/`H`/`hh`/`h`/`MM`/`M`/`mm`/`m`/`SS`/`S`/`ss`/`s`/`A`; other bytes are literal. |
| `l10n_time_parse(text, am_label, pm_label)` | `Result[TimeOfDay, Str]` | Parse `HH:MM[:SS]` plus an optional exact label; labeled hours must be 1..12. |
| `l10n_day_period(hour, morning_start, afternoon_start, evening_start, night_start)` | `Result[Str, Str]` | Classify into `"morning"`, `"afternoon"`, `"evening"`, `"night"`; night wraps. |
| `l10n_offset_new(sign, hours, minutes)` | `Result[TimeOffset, Str]` | Validating constructor; total range -12:00..+14:00; zero normalizes to sign +1. |
| `l10n_offset_parse(text)` | `Result[TimeOffset, Str]` | Parse `Z` or `+HH:MM`/`-HH:MM`; `-00:00`/`+00:00` normalize to canonical zero. |
| `l10n_offset_format(off)` | `Str` | `Z` for zero, else two-digit `+HH:MM` / `-HH:MM`. |
| `l10n_offset_total_minutes(off)` | `Int` | Signed minute value of the offset. |
| `l10n_offset_from_minutes(total)` | `Result[TimeOffset, Str]` | Inverse; total must be in -720..840. |
| `l10n_offset_is_zero(off)` | `Bool` | True for every zero form. |
| `l10n_offset_equals(a, b)` | `Bool` | Minute-value equality (all zero forms equal). |
| `l10n_time_apply_offset(t, off)` | `Result[TimeOfDay, Str]` | UTC -> local: `(t + off) mod 24h`, wrapping past midnight. |
| `l10n_time_remove_offset(t, off)` | `Result[TimeOfDay, Str]` | Local -> UTC: `(t - off) mod 24h`, wrapping past midnight. |

The full error catalog, token semantics, conversion table and test plan are
in `SPEC.md`.

## Usage

```xi
use xiom.l10n.time;
use xiom.io;

fn main() -> Int {
  match l10n_time_parse("11:59:59 PM", "AM", "PM") {
    Ok(t) => {
      match l10n_time_format(t, "HH:MM:SS", "AM", "PM") {
        Ok(s) => { io.println(s); },                          // 23:59:59
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  match l10n_offset_parse("+05:30") {
    Ok(off) => {
      io.println(l10n_offset_format(off));                    // +05:30
      let utc = TimeOfDay{ hour: 23; minute: 30; second: 0 };
      match l10n_time_apply_offset(utc, off) {
        Ok(local) => {
          match l10n_time_format(local, "HH:MM", "AM", "PM") {
            Ok(s) => { io.println(s); },                      // 05:00
            Err(e) => { io.println(e); },
          }
        },
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
.\scripts\port.ps1 -Package xiom.l10n-time
```

Expected tail: 24 `[PASS]` lines, `xiom.l10n.time: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No timezone database, no DST.** Offsets are fixed signed minute counts
  in -12:00..+14:00. Named zones, DST transitions, historical rules and
  TZif/tzdata parsing are out of scope; the caller picks the offset.
- **No clock.** The module never reads the current time or epoch seconds;
  every input is caller-supplied.
- **No calendar.** Times are wall-clock-only: no dates, no weekday logic, no
  leap seconds (`second` is 0..59), no day rollover information from the
  offset application (only the wrapped time of day is returned).
- **No locale database.** AM/PM labels, day-period boundaries and patterns
  are caller-supplied strings; there is no CLDR data and no built-in
  English table.
- **ASCII only, no escapes.** Patterns expand the documented tokens and copy
  every other byte literally; there is no way to escape a literal `H`/`h`/
  `M`/`m`/`S`/`s`/`A`.
- **Parsing is strict.** `HH:MM[:SS]` with 1..2 digit fields and an exact,
  case-sensitive label; hour-only labeled text such as `"1 PM"` is *not*
  parseable (use `l10n_hour_12_label` for display, `"1:00 PM"` for input).
  Unknown leftover text reports `unknown label`.
- **Single offset application.** Applying or removing an offset returns a
  time only; the caller must track which day the wrap crossed.
- Compiler note: `Ok`/`Err` are constructed only in leaf helpers, every
  `byte_at` read is widened and masked, and all `Str` equality goes through
  `xiom.string.compare.str_compare` (v0.62.0 workarounds).

See `SPEC.md` for the exact semantics, error catalog and test plan. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
