# xiom.astronomy -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.astronomy` (`src/astronomy.xi`). Pure XIOM, no FFI, no floating
point.

## 1. Scope

Integer astronomy helpers for proleptic Gregorian civil dates, interpreted as
UTC civil dates:

- `astro_is_leap_year` -- Gregorian leap-year predicate,
- `astro_julian_day` -- integer Julian Day Number (Fliegel-Van Flandern),
- `astro_days_since_j2000` -- whole days from 2000-01-01,
- `astro_moon_phase_permille` -- day-granularity synodic phase in permille,
- `astro_moon_phase_name` -- phase interval -> name,
- `astro_zodiac_sign` -- tropical zodiac sign of a month/day.

Every entry point is a free function; the only imports are
`xiom.convert.int_to_string` (error-message rendering) from `xiom.std`.

## 2. Non-goals

- No ephemeris, no planetary/lunar positions, no orbital elements, no
  rise/set/transit times, no observation planning.
- No floating point anywhere: every division is integer division, and the
  moon model is a single mean synodic month.
- No time of day, no hour/minute/second inputs, no timezone or DST, no
  timescales (UT1/TT/TAI), no Delta-T, no leap seconds.
- No Julian-calendar (pre-1582) dates, no BCE year-numbering model; the
  proleptic Gregorian calendar is used for all years in the formula's range.
- No star catalogs, no coordinate systems, no magnitude/lightcurve data; the
  placeholder README's `ephemeris`/`orbits`/`bodies`/`lightcurve`/`cosmos`
  inventory is explicitly out of scope for this package.
- No structs, no `Vec[StructType]`, no `Vec[fn]` dispatch, no lambdas, no
  methods (XIOM v0.61.3 constraints).
- No astronomical validation of "known" anchors beyond the ones listed in
  section 3; the tests pin the algorithms below, not an external ephemeris
  (section 10).

## 3. Conventions and anchor values

### 3.1 Julian day convention

`astro_julian_day` returns the **integer Julian Day Number (JDN)**: the
integer whose value for 2000-01-01 is 2451545 -- the J2000.0 epoch value.
Equivalently, it is the astronomical Julian Date of the date at 12:00 UTC
(noon), so a date at 00:00 UTC would be `JDN - 0.5`; the half-day fraction is
not representable in this integer API.

### 3.2 Verified anchors

The following values are pinned by the suite:

| Civil date (UTC) | JD (integer) | Days since J2000 |
|---|---|---|
| 1970-01-01 | 2440588 | -10957 |
| 1999-12-31 | 2451544 | -1 |
| 2000-01-01 | 2451545 | 0 |
| 2000-01-06 | 2451550 | 5 |
| 2000-02-28 | 2451603 | 58 |
| 2000-02-29 | 2451604 | 59 |
| 2000-03-01 | 2451605 | 60 |
| 1900-02-28 | 2415079 | -36466 |
| 1900-03-01 | 2415080 | -36465 |
| 2100-02-28 | 2488128 | 36583 |
| 2100-03-01 | 2488129 | 36584 |
| 2024-02-29 | 2460370 | 8825 |
| 2026-01-01 | 2461042 | 9497 |

Cross-check with Unix time (also pinned): `JD(2026-01-01) - JD(1970-01-01) =
20454 = 1767225600 / 86400`, and `JD(2000-01-01) - JD(1970-01-01) = 10957`.

## 4. Algorithms

### 4.1 Leap years

```
leap(y) = (y mod 4 == 0) and (y mod 100 != 0 or y mod 400 == 0)
```

`%` divisibility is sign-symmetric for these purposes, so negative years
behave consistently. Pinned: 1600, 1996, 2000, 2024, 2400 leap; 1700, 1900,
2023, 2025, 2100 not leap.

### 4.2 Julian Day Number (Fliegel-Van Flandern)

```
a  = (14 - month) / 12                 // 1 for Jan/Feb, else 0
y  = year + 4800 - a
m  = month + 12*a - 3                  // 10 for Jan, ... 9 for Dec
JD = day + (153*m + 2)/5 + 365*y + y/4 - y/100 + y/400 - 32045
```

All divisions are integer divisions (operands are non-negative for the
supported range, so truncation equals floor). Valid for `year >= -4799`.
Pinned: 2451545 / 2440588 / 2461042 for 2000-01-01 / 1970-01-01 /
2026-01-01, plus the century-boundary rows in section 3.2.

### 4.3 Validation

A date is valid iff `1 <= month <= 12` and `1 <= day <=
days_in_month(year, month)`, where February has 29 days in a leap year and 28
otherwise, and April/June/September/November have 30 days. Invalid dates
produce `Err("astronomy: invalid date: <year>-<month>-<day>")`. This rejects
month 0 and 13, day 0 and 32, February 30, February 29 in 1900/2100,
February 29 in 2000/2024 is accepted.

### 4.4 Days since J2000

```
days_since_j2000(y, m, d) = JD(y, m, d) - 2451545
```

`2000-01-01 -> 0`, `1999-12-31 -> -1`; errors pass through unchanged.

### 4.5 Moon phase

Constants:

| Name | Value | Meaning |
|---|---|---|
| `_JD_J2000` | 2451545 | JD of 2000-01-01 |
| `_JD_PHASE_EPOCH` | 2451550 | JD of the reference new moon, 2000-01-06 |
| `_UNITS_PER_DAY` | 1000000 | sub-day units per day (1e-6 day) |
| `_SYNODIC_MILLI` | 29530589 | one synodic month = 29.530589 days, in the same 1e-6-day units |
| `_PERMILLE` | 1000 | permille scale |

Algorithm (integer only):

```
elapsed_units = (JD(y, m, d) - 2451550) * 1000000
Q             = floor_div(elapsed_units * 1000, 29530589)
phase         = floor_mod(Q, 1000)                // 0..999
```

The task formula `phase = ((days_since_epoch * 1000) / SYNODIC_MILLI) mod
1000` is applied with `days_since_epoch` expressed in the 1e-6-day unit that
`SYNODIC_MILLI` uses (so `elapsed_units` above); with a whole-day `days` value
the same expression would compare days against 1e-6 days and always yield 0.
`floor_div`/`floor_mod` (not the native truncating `/` and `%`) implement
floor semantics, so dates before the epoch wrap forward: `1999-12-31` is
796 permille, not -204.

The phase equals `frac(days_since_epoch / 29.530589) * 1000` at day
granularity, i.e. `0` is new moon and `500` is full moon. Accuracy is about
`+-1` day; the model has no time of day, no ephemeris corrections.

Pinned phase values (each computed and verified with this formula):

| Date | permille | `astro_moon_phase_name` |
|---|---|---|
| 1999-12-31 | 796 | `waning crescent` |
| 1900-01-01 | 11 | `new` |
| 2000-01-06 | 0 | `new` |
| 2000-01-07 | 33 | `new` |
| 2000-01-14 | 270 | `first quarter` |
| 2000-01-20 | 474 | `full` |
| 2000-01-21 | 507 | `full` |
| 2000-01-22 | 541 | `full` |
| 2000-01-29 | 778 | `last quarter` |
| 2000-02-04 | 982 | `new` |
| 2000-02-05 | 15 | `new` |
| 2024-02-28 | 639 | `waning gibbous` |
| 2024-02-29 | 673 | `waning gibbous` |
| 2024-03-01 | 707 | `last quarter` |

Context (not asserted as ephemeris): 2000-01-06 and 2000-02-05 were real new
moons, 2000-01-14 a real first quarter and 2000-01-21 a real full moon
(04:41 UTC); the day-granularity estimate lands in the right interval for all
four, which is why these dates were chosen as sanity anchors.

### 4.6 Phase names

`astro_moon_phase_name(p)` first computes `floor_mod(p, 1000)` (so any `Int`
is accepted) and then maps:

| Normalized permille | Name |
|---|---|
| 0..62 | `new` |
| 63..187 | `waxing crescent` |
| 188..312 | `first quarter` |
| 313..437 | `waxing gibbous` |
| 438..562 | `full` |
| 563..687 | `waning gibbous` |
| 688..812 | `last quarter` |
| 813..937 | `waning crescent` |
| 938..999 | `new` |

Pinned boundaries: 0, 62, 63, 187, 188, 312, 313, 437, 438, 562, 563, 687,
688, 812, 813, 937, 938, 999, plus the normalization examples 1000 -> `new`,
-1 -> `new`, -63 -> `waning crescent`, 1562 -> `full`, 1563 -> `waning
gibbous`.

### 4.7 Tropical zodiac

`astro_zodiac_sign(month, day)` validates `1 <= month <= 12` and
`1 <= day <= max_days(month)`, where `max_days` is the longest possible month
(February 29, April/June/September/November 30, the rest 31). Then:

| Sign | Dates |
|---|---|
| Aries | Mar 21 - Apr 19 |
| Taurus | Apr 20 - May 20 |
| Gemini | May 21 - Jun 20 |
| Cancer | Jun 21 - Jul 22 |
| Leo | Jul 23 - Aug 22 |
| Virgo | Aug 23 - Sep 22 |
| Libra | Sep 23 - Oct 22 |
| Scorpio | Oct 23 - Nov 21 |
| Sagittarius | Nov 22 - Dec 21 |
| Capricorn | Dec 22 - Jan 19 |
| Aquarius | Jan 20 - Feb 18 |
| Pisces | Feb 19 - Mar 20 |

The implementation is a month switch with the in-month cutoff day: Jan 19/20,
Feb 18/19, Mar 20/21, Apr 19/20, May 20/21, Jun 20/21, Jul 22/23, Aug 22/23,
Sep 22/23, Oct 22/23, Nov 21/22, Dec 21/22. Every boundary is pinned by the
suite, as is a mid-range date for each of the twelve signs.

Because no year is available, `2-29` is accepted (a leap day is possible) and
`2-30`, `4-31`, `6-31`, `9-31`, `11-31` are rejected. Invalid input produces
`Err("astronomy: invalid date: <month>-<day>")`.

## 5. API signatures

```xi
pub fn astro_is_leap_year(year: Int) -> Bool
pub fn astro_julian_day(year: Int, month: Int, day: Int) -> Result[Int, Str]
pub fn astro_days_since_j2000(year: Int, month: Int, day: Int) -> Result[Int, Str]
pub fn astro_moon_phase_permille(year: Int, month: Int, day: Int) -> Result[Int, Str]
pub fn astro_moon_phase_name(permille: Int) -> Str
pub fn astro_zodiac_sign(month: Int, day: Int) -> Result[Str, Str]
```

Complexity: every entry point is O(1) (a handful of scalar operations; no
loops, no allocation beyond error-message strings).

## 6. Error catalog

Every `Err` message starts with `"astronomy: "` and reads
`"astronomy: invalid date: Y-M-D"` (or `"astronomy: invalid date: M-D"` for
the zodiac, which has no year):

| Trigger | Channel |
|---|---|
| month < 1 or month > 12 | `astro_julian_day`, `astro_days_since_j2000`, `astro_moon_phase_permille` |
| day < 1 or day > days_in_month(year, month) | same three |
| month outside 1..12 | `astro_zodiac_sign` |
| day outside 1..max_days(month) | `astro_zodiac_sign` |

The three date-taking functions share the validation: errors from
`astro_julian_day` propagate unchanged through `astro_days_since_j2000` and
`astro_moon_phase_permille`; `astro_moon_phase_name` and
`astro_is_leap_year` cannot fail.

## 7. Test plan

`tests/test_conformance.xi` (module `astronomy_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | 2000/1900/2024/2100 | mandated leap-year quartet |
| t2 | 1600/2400/1996/1700/2023/2025 | century and common-year rules |
| t3 | 2000-01-01, 1970-01-01, 2026-01-01 | mandated JD anchors 2451545/2440588/2461042 |
| t4 | 1900/2000/2100 Feb 28 - Mar 1 | century leap rules in JD |
| t5 | 1999-12-31, 2000-01-02/06, 2026-01-02 | epoch neighbors |
| t6 | month 0/13, day 0/32, Feb 30, 1900/2100 Feb 29, Apr 31 | invalid-date rejection; valid leap Feb 29 accepted |
| t7 | days since J2000 | 0, -1, 5, 9497, 10957 |
| t8 | Err propagation | days/phase channels reject invalid dates |
| t9 | 2000-01-06 (0), 2000-02-04 (982), 2000-02-05 (15) | near-new windows `<= 50 or >= 950` |
| t10 | 2000-01-20/21/22 (474/507/541) | full-moon window 500 +- 60 |
| t11 | 2000-01-14 (270), 2000-01-29 (778) | first/last quarter intervals |
| t12 | 1999-12-31 (796), 1900-01-01 (11), range checks | floor wrap, 0..999 invariant |
| t13 | 18 boundary values | every phase-name boundary |
| t14 | 1000, -1, -63, 1562, 1563 | normalization of out-of-range permille |
| t15 | Mar 20/21, Dec 21/22, Jan 19/20 | mandated zodiac boundaries |
| t16 | one mid-date per sign | all twelve signs reachable |
| t17 | the other 18 sign boundaries | full boundary coverage |
| t18 | 0/13 months, day 0/32, Feb 30, 30-day month 31 | zodiac rejection; Feb 29 accepted |
| t19 | exact Err text | `astronomy: invalid date: Y-M-D` / `M-D` |
| t20 | JD differences | 20454 = 1767225600/86400, 9497, 10957 |
| t21 | February lengths | 29 in 2000/2024, 28 in 1900/2100 |
| t22 | per-day phase step | 33 and 34 permille/day from 1000*1e6/29530589, wrap |

Assertions are never weakened to make the suite pass: every signed/panicking
value above was recomputed with the documented formula before being pinned.
`[PASS]`/`[FAIL]` printing and the `main() -> Int` failure-count return model
`xiom.csv`'s `tests/test_conformance.xi`.

## 8. Compiler / stdlib notes

No unsafe code and no FFI. The module follows the `xiom.scheduler` /
`xiom.bson` v0.61.3 idioms:

- Free functions only (no methods, no lambdas); `Vec[fn]` dispatch is not
  used in the suite either -- tests are dispatched as `t1()` ... `t22()`.
- `Ok`/`Err` are constructed only inside the `_ok_int` / `_err_int` /
  `_ok_str` / `_err_str` leaf helpers, never directly in the public bodies.
- No `Vec[StructType]` and no struct returns; the module is scalar-only.
- Every `match` on a `Result` has both `Ok` and `Err` arms (non-exhaustive
  match is a hard error).
- `Str` equality in the suite goes through `xiom.string.compare.str_compare`
  (BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
  pointer comparison).
- Integer floor division/modulo are explicit helpers; the native `/`
  truncates toward zero and is used only where operands are known
  non-negative (the JDN formula).

## 9. Known limitations

- Day granularity for the moon: about `+-1` day; the interval names are
  phase intervals of this model, not astronomical quarter instants.
- UTC civil dates only; no timescales, no leap seconds, no timezone/DST.
- Integer JDN only; the 0.5-day offset of 00:00 UTC is not represented.
- Proleptic Gregorian, `year >= -4799`; no Julian calendar, no epoch beyond
  that range, no validation of "real" historical dates.
- `astro_zodiac_sign` cannot know the year, so February 29 is accepted and
  the sign is consistent with the tropical table above.
- `astro_moon_phase_name` collapses the two new-moon windows (0..62 and
  938..999) into `"new"`, so its output is not invertible.
- No ephemeris, orbital elements, body catalog, light curves, or coordinate
  systems -- the original placeholder scope stays out of this package.

## 10. Provenance of expected values

Where an anchor could not be verified against an independent authoritative
source (moon-phase permille, exotic Julian days), the expected value in the
suite was derived from the formulas in section 4 and computed the same way
(integer, floor semantics). **The tests pin this package's algorithms, not an
external ephemeris.** Independently verifiable anchors that are pinned:
`JD(1970-01-01) = 2440588`, `JD(2000-01-01) = 2451545`, `JD(2026-01-01) =
2461042`, the Unix-days cross-check of section 3.2, and the century leap
rules.
