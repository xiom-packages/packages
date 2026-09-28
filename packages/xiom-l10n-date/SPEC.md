# xiom.l10n-date -- specification

Version: 0.1.0 (incubating). Pure XIOM, no FFI, no clock, no IO, no floating
point. All functions are free functions; the module depends on `xiom.string`,
`xiom.string.compare` and `xiom.convert` from `xiom.std` only.

## 1. Model

A civil date is a `CivilDate` struct with three `Int` fields (`year`, `month`,
`day`). The fields are not validated on construction; `date_make`,
`date_parse` and `date_iso_parse` are the only functions that create validated
values, and every arithmetic function assumes a valid input (documented per
function). Formatting and the ISO pair validate first and fail with the
validation message.

A locale is exactly two caller-supplied `Vec[Str]` tables: `month_names`
(full month names) and `month_abbrs` (abbreviations), each with exactly 12
entries in calendar order. There is no locale database, no global state and no
inspection of table content: entries may be any `Str`, including multi-byte
UTF-8, and are matched byte-wise.

All text processing is byte-oriented. Digits are ASCII `0`-`9`; every byte read
is widened with `as Int` and masked with `255`. String equality in the module
never uses `==`; it goes through `xiom.string.compare.str_compare`.

## 2. Validation and construction

`date_is_leap_year(year)` is the Gregorian rule: `year % 4 == 0` and
(`year % 100 != 0` or `year % 400 == 0`). The `%` operator truncates toward
zero, which is exact for divisibility tests on negative years too.

`date_days_in_month(year, month)` returns 31 for January/March/May/July/
August/October/December, 30 for April/June/September/November, 28 or 29 for
February per the leap rule, and **0** when `month` is outside 1..12 (invalid
months are never silently treated as 31 days).

`_date_invalid_reason(year, month, day)` returns `""` or the first exact
error:

| Condition | Message |
|---|---|
| `month < 1 || month > 12` | `date: invalid month: <m>` |
| `day < 1 || day > days_in_month(year, month)` | `date: invalid day: <d>` |

Month is checked before day, so `(2024, 13, 99)` reports the month.
`date_make` returns `Ok(CivilDate)` or `Err(<reason>)`; `date_is_valid` is the
non-failing predicate. February 29 is accepted only in leap years
(`2024-02-29` and `2000-02-29` valid; `2023-02-29` and `1900-02-29` ->
`date: invalid day: 29`).

## 3. Julian day numbers and calendar conversion

The JDN is the common astronomical day count; 1970-01-01 (Gregorian) is JDN
2440588 and 2000-01-01 is JDN 2451545. All divisions below are truncating
`Int` division and every operand is non-negative for years >= -4700.

Gregorian civil date -> JDN (`date_jdn_from_gregorian`):

```
a = (14 - month) / 12 ; y = year + 4800 - a ; m = month + 12*a - 3
jdn = day + (153*m + 2)/5 + 365*y + y/4 - y/100 + y/400 - 32045
```

Julian-calendar date -> JDN (`date_jdn_from_julian`): the same formula
without the `y/100` and `y/400` terms and with the constant `-32083`.

JDN -> Gregorian (`date_gregorian_from_jdn`):

```
a = jdn + 32044 ; b = (4*a + 3)/146097 ; c = a - (146097*b)/4
d = (4*c + 3)/1461 ; e = c - (1461*d)/4 ; m = (5*e + 2)/153
day   = e - (153*m + 2)/5 + 1
month = m + 3 - 12*(m/10)
year  = 100*b + d - 4800 + m/10
```

JDN -> Julian (`date_julian_from_jdn`) is the same with `c = jdn + 32082` and
`year = d - 4800 + m/10`.

`date_gregorian_to_julian` and `date_julian_to_gregorian` convert the same
physical day between the calendars: they compute the JDN in the source
calendar and decode it in the target calendar. Both calendars are proleptic
(the rules are extrapolated beyond their historical adoption).

**Offset rule.** The same physical day has an earlier Julian-calendar date.
The offset is 10 days at the 1582-10-15 reform and grows by one day at each
Gregorian century that is not a leap year, measured on the Gregorian date:

| Gregorian date range | Julian date is behind by |
|---|---|
| 1582-10-15 .. 1700-02-28 | 10 days (Gregorian 1582-10-15 = Julian 1582-10-05) |
| 1700-03-01 .. 1800-02-28 | 11 days (1700-03-01 = 1700-02-19) |
| 1800-03-01 .. 1900-02-28 | 12 days (1800-03-01 = 1800-02-18) |
| 1900-03-01 .. 2100-02-28 | 13 days (1900-01-13 = 1900-01-01) |
| 2100-03-01 .. | 14 days (2100-03-01 = 2100-02-16) |

Before 1582-10-15 the proleptic offset shrinks by one day at each earlier
Gregorian century boundary (1500-03-01 -> 9 days, 1400-03-01 -> 8 days, ...).
The JDN formulas implement this automatically, so no offset constant appears
in the code.

## 4. Epoch days, weekday, day of year

`date_to_epoch_day(d) = JDN_gregorian(d) - 2440588`; negative before the
epoch. Examples: `1970-01-01 -> 0`, `1969-12-31 -> -1`, `1969-12-30 -> -2`,
`1969-01-01 -> -365`, `1900-01-01 -> -25567`, `1582-10-15 -> -141427`,
`2000-03-01 -> 11017`, `2024-02-29 -> 19782`. `date_from_epoch_day(z)`
decodes `z + 2440588` and inverts the mapping exactly.

`date_weekday(d)` returns 0=Sunday .. 6=Saturday:
`w = ((epoch_day % 7) + 4)` with `+7` applied once when `w < 0` and `-7` once
when `w >= 7`, so pre-1970 dates floor correctly. Known anchors:
`1970-01-01 -> 4` (Thursday), `2000-01-01 -> 6`, `2024-02-29 -> 4`,
`1969-12-31 -> 3`, `1900-01-01 -> 1`, `1582-10-15 -> 5`.

`date_day_of_year(d)` sums the month lengths before `d.month` and adds
`d.day`: `2024-01-01 -> 1`, `2024-02-29 -> 60`, `2024-03-01 -> 61`,
`2023-12-31 -> 365`, `2024-12-31 -> 366`, `1900-03-01 -> 60`.

## 5. Pattern tokens

| Token | Format emits | Parse reads |
|---|---|---|
| `YYYY` | 4-digit zero-padded year (0..9999) | exactly 4 digits -> year |
| `YY` | last two digits of the year | exactly 2 digits; 00..68 -> 2000..2068, 69..99 -> 1969..1999 |
| `MMMM` | full name `month_names[month-1]` | longest entry of `month_names` matching at the cursor |
| `MMM` | abbreviation `month_abbrs[month-1]` | longest entry of `month_abbrs` matching at the cursor |
| `MM` | 2-digit zero-padded month | exactly 2 digits |
| `M` | plain month number | 1..2 digits (greedy) |
| `DD` | 2-digit zero-padded day | exactly 2 digits |
| `D` | plain day number | 1..2 digits (greedy) |

**Tokenizer.** The pattern is scanned left to right. A byte that is not an
ASCII letter (`A-Z`, `a-z`) is a literal copied/compared verbatim. At an
ASCII letter, the longest known token is matched in the order `YYYY`,
`MMMM`, `YY`, `MMM`, `MM`, `DD`, `M`, `D`; so `YYYYMMDD` scans as
`YYYY MM DD` and `MMMM` wins over `MM`. If no token starts at that byte, the
maximal ASCII letter run is reported: `date: unknown pattern token: <run>`
(e.g. `YYYYY` -> `YYYY` then unknown `Y`; `QQ` -> unknown `QQ`). There is no
quoting or escaping, so letters can never be literals.

## 6. `date_format(d, pattern, month_names, month_abbrs) -> Result[Str, Str]`

Checking order:

1. both tables must have exactly 12 entries, else
   `Err("date: month table must have 12 entries")`;
2. the date is validated (`_date_invalid_reason`), else `Err(<reason>)`;
3. scanning left to right, literals are copied byte-for-byte and tokens are
   expanded per section 5. `YYYY`/`YY` require the year to be 0..9999, else
   `Err("date: year out of range: <y>")`; `MMMM`/`MMM` index the validated
   month, so no bounds error is possible;
4. an unknown token fails with `Err("date: unknown pattern token: <run>")`.

An empty pattern yields `Ok("")`. `YY` renders `year % 100` (zero-padded), so
`1969 -> "69"` and `2068 -> "68"`. Examples: `"YYYY-MM-DD"` on 2024-02-29 ->
`"2024-02-29"`; `"D MMMM YYYY"` -> `"29 February 2024"`; `"MMMM D, YYYY"` ->
`"February 29, 2024"`; `"M/D/YY"` -> `"2/29/24"`.

## 7. `date_parse(text, pattern, month_names, month_abbrs) -> Result[CivilDate, Str]`

State: `year = 1970`, `month = 1`, `day = 1`, pattern cursor `i`, text cursor
`p`. Scanning mirrors the tokenizer:

1. both tables must have 12 entries, else
   `date: month table must have 12 entries`; an empty pattern is
   `date: empty pattern`;
2. literals: the text byte at `p` must exist and equal the pattern byte, else
   `date: literal mismatch at byte <p>`;
3. numeric tokens read exactly/at most the digits of section 5, else
   `date: expected 4 digits for YYYY at byte <p>`, `... 2 digits for YY ...`,
   `... 2 digits for MM ...`, `... 2 digits for DD ...`,
   `date: expected digits for M at byte <p>` / `... for D at byte <p>`;
4. `MMMM`/`MMM` match the longest table entry at `p` (byte-wise), else
   `date: bad month name at byte <p>`; the matched index + 1 becomes the
   month and the cursor advances by the entry length;
5. after the pattern is consumed, leftover text is
   `date: trailing text at byte <p>`;
6. the assembled triplet is validated exactly like `date_make`
   (`date: invalid month: <m>` / `date: invalid day: <d>`), which is why
   absent fields default to 1970-01-01 and `"02-29"` with `"MM-DD"` fails
   (1970 is not a leap year).

`M`/`D` read greedily up to two digits, so adjacent numeric tokens split
greedily (`"123"` with `"MD"` -> `M=12`, `D=3`). Examples:
`("2024-02-29", "YYYY-MM-DD") -> Ok`; `("29 February 2024", "D MMMM YYYY") ->
Ok`; `("70/01/01", "YY/MM/DD") -> Ok(1970-01-01)`; `("69/12/31", "YY/MM/DD")
-> Ok(1969-12-31)`.

## 8. ISO 8601 convenience pair

`date_iso_format(d)` validates the date, requires year 0..9999, and returns
`Ok("YYYY-MM-DD")` (exactly 10 bytes).

`date_iso_parse(text)` requires exactly 10 bytes and then:

1. `date: expected 10 bytes for iso date: <text>` when `len != 10`;
2. `date: bad iso separator at byte 4` / `... byte 7` when the `-` is missing;
3. `date: expected 4 digits for iso year at byte 0`,
   `date: expected 2 digits for iso month at byte 5`,
   `date: expected 2 digits for iso day at byte 8` for non-digit fields;
4. the same month/day validation as `date_make`.

`date_iso_parse(date_iso_format(d)) == d` for every valid date with year
0..9999.

## 9. Error catalog

All errors are `Err` values with the prefix `date: `.

| Condition | Message |
|---|---|
| month table length != 12 (format and parse) | `date: month table must have 12 entries` |
| `date_parse` with an empty pattern | `date: empty pattern` |
| letter run that is not a token (format and parse) | `date: unknown pattern token: <run>` |
| `month < 1 || month > 12` (any validating path) | `date: invalid month: <m>` |
| `day < 1 || day > days_in_month` (any validating path) | `date: invalid day: <d>` |
| format `YYYY`/`YY` with year outside 0..9999 | `date: year out of range: <y>` |
| parse `YYYY` without 4 digits at `<p>` | `date: expected 4 digits for YYYY at byte <p>` |
| parse `YY` without 2 digits | `date: expected 2 digits for YY at byte <p>` |
| parse `MM` without 2 digits | `date: expected 2 digits for MM at byte <p>` |
| parse `DD` without 2 digits | `date: expected 2 digits for DD at byte <p>` |
| parse `M` without 1..2 digits | `date: expected digits for M at byte <p>` |
| parse `D` without 1..2 digits | `date: expected digits for D at byte <p>` |
| no table entry matches at `<p>` | `date: bad month name at byte <p>` |
| literal pattern byte != text byte (or text ended) | `date: literal mismatch at byte <p>` |
| text longer than the pattern consumes | `date: trailing text at byte <p>` |
| ISO text length != 10 | `date: expected 10 bytes for iso date: <text>` |
| ISO `-` missing at positions 4 / 7 | `date: bad iso separator at byte 4` / `... byte 7` |
| ISO year/month/day not digits | `date: expected 4 digits for iso year at byte 0`, `... 2 digits for iso month at byte 5`, `... 2 digits for iso day at byte 8` |

Validation is left to right and the first error wins; the final month/day
check runs only after the whole pattern has been consumed.

## 10. Test plan (`tests/test_conformance.xi`, 18 checks)

Fixtures are cross-checked against the .NET proleptic Gregorian and
`JulianCalendar` implementations plus the Fliegel-Van Flandern JDN formulas.

| # | Name | Expectation |
|---|---|---|
| t1 | leap years | 2024/2000/1600/1968 leap; 1900/1700/2100/2023/1969 not |
| t2 | month lengths | 31/30/29/28 per month; 0 for months 0 and 13 |
| t3 | date_make | `2024-02-29` valid, `2023-02-29`/`1900-02-29`/`04-31`/`01-00`/`01-32` invalid day, `month 0`/`13` invalid month; accessors |
| t4 | epoch days | 0, -1, -2, -365, -25567, -141427, -40587, 10957, 11017, 19782, 20088 |
| t5 | epoch inverse | `from_epoch_day` inverts pre- and post-1970 values (0, -1, -365, -25567, -141427, 11017, 19782, 19783) |
| t6 | weekday | 1970-01-01=4, 1969-12-31=3, 1900-01-01=1, 2000-01-01=6, 2024-02-29=4, 1582-10-15=5, ... |
| t7 | day of year | 1, 60, 61, 365, 366, 60 (1900), 61 (2000), 365 (1969) |
| t8 | JDN Gregorian | 2440588, 2451545, 2400001, 2299161, 2460370, 2415021 and ±1 day steps |
| t9 | JDN inverse | `date_gregorian_from_jdn` decodes the reference JDN values and round-trips |
| t10 | Gregorian -> Julian | reform 1582-10-15 -> 1582-10-05; 12/13/14-day drift; shared JDN equality |
| t11 | Julian -> Gregorian | inverse pairs plus full round-trips (2024, 1969, 1900, 1582, 2100) |
| t12 | format tokens | ISO, full/abbr names, composite patterns, adjacent `YYYYMMDD`, `YY` for 1969/2068 |
| t13 | format errors | unknown tokens (`QQ`, `Y`, `YYYYY`), year range 10000/-1, invalid dates, 11-entry table |
| t14 | parse | ISO, full/abbr names, `M/D/YYYY`, `YYYYMMDD`, default year 1970 for `MM-DD`, garbage sentinel |
| t15 | YY window | 69->1969, 68->2068, 00->2000, 99->1999, 70->1970; format 69/68 |
| t16 | parse errors | empty pattern, unknown token, literal mismatch, trailing text, digit-width errors, bad month name, invalid month/day (full catalog with byte offsets) |
| t17 | ISO pair | format values, round-trips, all ISO error paths, invalid dates, year 10000 |
| t18 | non-ASCII tables | German multi-byte `M\u{00E4}rz` format/parse; 12+12 entries; every abbreviation is a prefix of its full name; per-month `MMMM`/`MMM` expansion |

Every test folds its sub-checks into one `assert(cond, name)` and `main`
returns the number of failing checks (0 = green). `port.ps1` must end
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## 11. Compiler / stdlib notes (XIOM v0.62.0)

- Free functions only; no `self` methods, no lambdas, no `Vec[StructType]`,
  no indexed `Vec[fn]` dispatch (the tests use a direct `t1..t18` call chain).
- `Ok`/`Err` are constructed only in the leaf helpers `_date_ok`,
  `_date_err`, `_str_ok`, `_str_err`.
- Every `Str` comparison goes through `compare.str_compare`; `Vec[Str]`
  entries are bound to typed locals before use.
- Byte reads use `(string.byte_at(s, i) as Int) & 255`; ASCII constants are
  masked Ints, so no comparison depends on sign-extended bytes.
- `use` statements end with `;`, `module` does not; `while` loops and
  `if/elif/else` only (no `mut` match patterns).
- The module is deterministic and allocation-light: only short `Str`
  concatenations and the caller's vectors.

## 12. Known limitations

- **No locale data**: no CLDR, no bundled month names, no day names, no era
  or time-zone handling, no time of day. The caller owns both month tables.
- **Year range**: `YYYY`/`YY` cover 0..9999 only; the JDN/epoch path covers
  years >= -4700 (division operands stay non-negative).
- **Strict grammar**: exact digit widths, byte-wise literals, no optional
  separators, no surrounding text, no escaped/quoted literals.
- `YY` round-trips only within 1969..2068 (windowed mapping).
- Missing fields in a pattern default to 1970-01-01 and the assembled date is
  validated, so year-less February 29 patterns fail.
- Month-name matching is byte-wise and picks the longest entry within the
  requested table; `MMMM` never consults the abbreviation table and vice
  versa.
- No ISO week dates, ordinal dates, weekdays in patterns, or overflow-safe
  arithmetic outside the documented ranges.
