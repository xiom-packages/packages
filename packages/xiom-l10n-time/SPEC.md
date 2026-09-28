# xiom.l10n.time -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.l10n.time` (`src/l10n_time.xi`). Pure XIOM, no FFI, no clock.

## 1. Scope

Locale-style time-of-day and timezone-offset logic with caller-supplied
labels. The module provides:

- a validated `TimeOfDay` model (`hour` 0..23, `minute` 0..59, `second` 0..59)
  and `TimeOffset` model (`sign`, `hours` 0..14, `minutes` 0..59);
- 24h -> 12h and 12h -> 24h hour conversion with the midnight/noon edge rules
  (12 AM = 00, 12 PM = 12) and caller-supplied AM/PM labels;
- pattern formatting and parsing of `HH:MM[:SS]`-style text;
- day-period classification (morning / afternoon / evening / night) against
  caller-supplied boundaries;
- timezone-offset parse (`+HH:MM`, `-HH:MM`, `Z`), format, minute-value
  conversion, and application to a `TimeOfDay` (UTC <-> offset) with wrapping
  past midnight.

All inputs are in-memory `Str` values; failures are `Err("l10n.time: ...")`
strings (section 8). The module contains no `Vec`, no floating point, no
allocation beyond string concatenation, and never reads a clock.

## 2. Non-goals

- **No timezone database and no DST rules.** An offset is a fixed signed
  minute count; named zones (`Europe/Athens`), DST transitions, historical
  offsets and `tzdata`/TZif parsing are out of scope.
- **No clock.** The module never reads the current time, epoch seconds or any
  OS timer; every value comes from the caller.
- **No calendar arithmetic.** No dates, no day/month/year fields, no leap
  seconds (`second` is 0..59), no weekday logic.
- **No locale database.** Labels, day-period boundaries and pattern text are
  caller-supplied; there is no CLDR and no built-in AM/PM table.
- **No floating point** and no `Vec` anywhere in the library module.
- No FFI, file I/O or registry integration.

## 3. Data model

```xiom
pub type TimeOfDay = {
  hour: Int;
  minute: Int;
  second: Int;
}

pub type TimeOffset = {
  sign: Int;
  hours: Int;
  minutes: Int;
}
```

`TimeOfDay` fields are validated on construction (`l10n_time_of_day`) and
re-validated by every function that consumes a `TimeOfDay` value
(`l10n_time_format`, `l10n_time_apply_offset`, `l10n_time_remove_offset`).

`TimeOffset` denotes `sign * (hours*60 + minutes)` minutes from UTC. A valid
offset lies in `-720..840` minutes, i.e. **-12:00 .. +14:00**. The canonical
zero offset is `sign = 1, hours = 0, minutes = 0`; it formats as `Z` and every
zero form compares equal (`l10n_offset_equals` compares minute values).

## 4. 12h/24h conversion rules

| input | output |
|---|---|
| 24h hour 0 | 12h hour 12 (midnight) |
| 24h hours 1..11 | same value |
| 24h hour 12 | 12h hour 12 (noon) |
| 24h hours 13..23 | hour - 12 |
| 12h hour 12, AM | 24h hour 0 |
| 12h hour 12, PM | 24h hour 12 |
| 12h hours 1..11, AM | same value |
| 12h hours 1..11, PM | hour + 12 |

`l10n_hour_period` returns the caller's `am_label` for 24h hours 0..11 and
`pm_label` for 12..23. `l10n_hour_12_label` joins the 12h face hour, one
ASCII space and the label ("12 AM", "1 PM", "11 PM").

## 5. Formatting tokens

`l10n_time_format(t, pattern, am_label, pm_label)` scans `pattern` left to
right and matches the longest token first. Any byte that does not start a
token is copied literally; there is no escape syntax (pattern letters are
always tokens).

| token | expansion | example |
|---|---|---|
| `HH` | zero-padded 24h hour (00..23) | `09` |
| `H` | bare 24h hour (0..23) | `9` |
| `hh` | zero-padded 12h face hour (01..12) | `12` |
| `h` | bare 12h face hour (1..12) | `12` |
| `MM` / `mm` | zero-padded minute | `05` |
| `M` / `m` | bare minute | `5` |
| `SS` / `ss` | zero-padded second | `09` |
| `S` / `s` | bare second | `9` |
| `A` | the periodic label for the time | `PM` |

Minute and second tokens are accepted in either case convention so that both
`HH:MM:SS` and `hh:mm:ss A` read naturally; the hour tokens select 24h vs 12h
face. Examples: `13:05:09` -> `"HH:MM:SS"`; 00:00:00 -> `"hh:mm:ss A"` gives
`"12:00:00 AM"`; 13:05:09 -> `"h:mm:ss A"` gives `"1:05:09 PM"`. An invalid
`TimeOfDay` yields `Err("l10n.time: invalid time")`.

## 6. Parsing grammar

```
time   := spaces hh ":" mm [ ":" ss ] spaces [ label ] spaces
hh     := 1*2digit              ; 0..23 unlabeled, 1..12 labeled
mm     := 1*2digit              ; 0..59
ss     := 1*2digit              ; 0..59
label  := am_label | pm_label   ; exact, case-sensitive
```

Rules:

1. Surrounding ASCII spaces (0x20) are allowed and stripped; an input that is
   empty or all spaces is `empty input`.
2. Hour and minute are required; seconds are optional after a second `:`.
   Each field is 1..2 digits; a third digit in a field is `too many digits`.
3. The colon after the hour is required (`expected ':'`); the colon before
   the seconds is optional.
4. A trailing label is matched against `am_label` and then `pm_label` with
   byte-wise, case-sensitive comparison (`xiom.string.compare.str_compare`).
   Spaces between the numeric part and the label are optional. Anything that
   matches neither label — including mistyped labels and junk — is
   `unknown label`.
5. Without a label the hour must be 0..23 (24h reading). With a label the
   hour must be 1..12 and is converted with the section 4 midnight/noon
   rules, so `"12:30 AM"` is 00:30 and `"12:30 PM"` is 12:30.
6. Range checks are reported by field: `hour out of range`,
   `minute out of range`, `second out of range`.

`l10n_hour_12_label` produces `"12 AM"`-style text without minutes; that text
is a *label string*, not a parseable time. Use `l10n_time_parse` on
`"12:00 AM"`-style text (the round-trip test builds such text).

## 7. Day periods and offsets

**Day periods.** `l10n_day_period(hour, morning_start, afternoon_start,
evening_start, night_start)` requires four boundaries in 0..23, strictly
increasing; the ranges are `[morning_start, afternoon_start)` -> `"morning"`,
`[afternoon_start, evening_start)` -> `"afternoon"`, `[evening_start,
night_start)` -> `"evening"`, and night is the wrap-around remainder
`[night_start, 24)` plus `[0, morning_start)`. Errors: `hour out of range`,
`boundary out of range`, `boundaries out of order`.

**Offsets.** `l10n_offset_parse` accepts exactly `Z` (zero) or a six-byte
`+HH:MM` / `-HH:MM` with two digits for hours and minutes. `+00:00` and
`-00:00` normalize to the canonical zero. Range: total minutes in
`-720..840` (-12:00..+14:00), so `+14:00` and `-12:00` are the extremes;
`+14:01`, `-12:30` and `+00:60` are rejected. `l10n_offset_new` additionally
requires `sign` to be `+1`/`-1`; hours 0..14; minutes 0..59; then applies the
same total check. `l10n_offset_format` emits `Z` for zero, else two-digit
`+HH:MM` / `-HH:MM`.

**Application.** `l10n_time_apply_offset(t_utc, off)` returns
`(t_utc + off) modulo 24h`; `l10n_time_remove_offset(t_local, off)` returns
`(t_local - off) modulo 24h`. The modulo is the mathematical one: a negative
shift wraps to the previous day (00:30 minus +01:00 is 23:30). Both validate
the time fields (`invalid time`) and the offset minute total
(`offset out of range`). There is no date, so only the time of day is
returned.

## 8. Error catalog

| message | raised by |
|---|---|
| `l10n.time: empty input` | time parse / offset parse on `""` (or spaces-only for time) |
| `l10n.time: bad digit` | time parse where a digit run is required but empty |
| `l10n.time: too many digits` | time parse field longer than two digits |
| `l10n.time: expected ':'` | time parse: byte after the hour is not `:` |
| `l10n.time: unknown label` | time parse: leftover text matches neither label |
| `l10n.time: hour out of range` | constructor, parse (24h > 23 or labeled outside 1..12), 12/24h conversion, day period |
| `l10n.time: minute out of range` | constructor, parse |
| `l10n.time: second out of range` | constructor, parse |
| `l10n.time: invalid time` | format / apply / remove given out-of-range TimeOfDay fields |
| `l10n.time: time out of range` | `l10n_time_from_total_seconds` outside 0..86399 |
| `l10n.time: boundary out of range` | day period boundary outside 0..23 |
| `l10n.time: boundaries out of order` | day period boundaries not strictly increasing |
| `l10n.time: bad offset` | offset parse: shape other than `Z` or `+/-HH:MM` |
| `l10n.time: offset digit` | offset parse: non-digit in a numeric slot |
| `l10n.time: offset out of range` | offset parse/new/from_minutes/apply/remove range violation |
| `l10n.time: bad offset sign` | `l10n_offset_new` sign not +1/-1 |
| `l10n.time: offset hour out of range` | `l10n_offset_new` hours outside 0..14 |
| `l10n.time: offset minute out of range` | `l10n_offset_new` minutes outside 0..59 |

Diagnostics are left-to-right and first-error-wins.

## 9. Test plan

`tests/test_conformance.xi` runs 24 checks, one `[PASS]` line each, and exits
with the failure count:

| # | check |
|---|---|
| 1 | validation bounds: 00:00:00 / 23:59:59 valid, 24h/60m/60s rejected |
| 2 | constructor: valid builds a TimeOfDay, each range error by name |
| 3 | 24h -> 12h: 0/12 -> 12, 13 -> 1, 23 -> 11, invalid hour |
| 4 | 12h -> 24h: 12 AM = 0, 12 PM = 12, 1 PM = 13, invalid hours |
| 5 | period labels: caller strings emitted verbatim, hour validated |
| 6 | every hour 0..23 round-trips face + label back to 24h |
| 7 | 24h patterns: padded/bare tokens and literals, empty pattern |
| 8 | 12h patterns: padded/bare face, label token, custom labels |
| 9 | token case flexibility, literals, invalid-time error |
| 10 | parse 24h: 1..2 digit fields, optional seconds, spaces |
| 11 | parse 12h: midnight/noon rules, attached label, custom labels |
| 12 | parse labels: case-sensitive, labeled hour range, label-less 24h |
| 13 | parse shape errors: empty, missing digits, missing colon, >2 digits |
| 14 | parse range errors: hour > 23, minute > 59, second > 59 |
| 15 | day-period boundaries (5, 12, 17, 21) including wrap to night |
| 16 | custom day-period bounds and boundary/order errors |
| 17 | offset parse: Z, signed forms, canonical zero |
| 18 | offset parse errors: shape, digit, range diagnostics |
| 19 | offset format: Z for zero forms, two-digit output |
| 20 | offset minute values and from_minutes at the -12:00/+14:00 edges |
| 21 | offset constructor: range and zero normalization |
| 22 | apply offset: UTC -> local with forward midnight wrap |
| 23 | remove offset: local -> UTC with backward wrap |
| 24 | round-trips: 12h face over all hours, apply/remove, parse/format |

Expected harness tail: 24 `[PASS]` lines, `xiom.l10n.time: all tests passed`,
then `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## 10. Compiler notes (v0.62.0)

- `Ok`/`Err` are constructed only in the leaf helpers (`_time_ok`,
  `_off_err`, ...); inline construction in functions returning struct
  payloads miscompiles.
- Every `xiom.string.byte_at` read goes through `_b`, which widens with
  `as Int` and masks with `& 0xFF` before comparison.
- All string equality uses `xiom.string.compare.str_compare`; no `Str`
  `==` anywhere.
- No `Vec`, no `Vec[Float64]`, no indexed function dispatch, no `[T, U]`
  callbacks; free functions only.
- The midnight wrap uses `((v % 86400) + 86400) % 86400`, correct under both
  truncating and floor division.
