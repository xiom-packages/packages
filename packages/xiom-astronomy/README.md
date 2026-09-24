# xiom.astronomy

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** integer astronomy helpers for civil dates: Julian Day Numbers,
> days since J2000, a day-granularity moon-phase estimate, moon-phase names,
> and tropical zodiac signs.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.convert.int_to_string`).
> Tests additionally use `xiom.test`, `xiom.io`, `xiom.string` and
> `xiom.string.compare`.

## Scope

`xiom.astronomy` is a dependency-light, floating-point-free toolkit for the
date arithmetic that planetary/app UI code usually needs before any real
ephemeris enters the picture: convert a proleptic Gregorian civil date to an
integer Julian Day Number (Fliegel-Van Flandern), measure whole days from the
J2000 reference date, estimate the lunar phase in permille of the synodic
cycle with day granularity, name that phase, and classify a month/day into a
tropical zodiac sign. Every result is an `Int`, a `Bool`, or a `Str`; dates
are UTC civil dates and there is no FFI. See `SPEC.md` for the algorithms,
constants, and the exact semantics of every edge case.

## API

| Function | Returns | Description |
|---|---|---|
| `astro_is_leap_year(year)` | `Bool` | Proleptic Gregorian rule: divisible by 4, except centuries, except every 400 years. |
| `astro_julian_day(year, month, day)` | `Result[Int, Str]` | Integer JDN (Fliegel-Van Flandern), anchored at `JD(2000-01-01) = 2451545`. `Err` on an invalid date (month outside 1..12, day outside the month, including Feb 30 and Feb 29 in a common year). |
| `astro_days_since_j2000(year, month, day)` | `Result[Int, Str]` | `JD - 2451545`: `2000-01-01 -> 0`, `1999-12-31 -> -1`. |
| `astro_moon_phase_permille(year, month, day)` | `Result[Int, Str]` | Phase estimate in permille (`0` = new, `500` = full), always in `0..999`; epoch `2000-01-06` (JD 2451550), mean synodic month 29.530589 days, day granularity (`+-1` day). |
| `astro_moon_phase_name(permille)` | `Str` | `new`, `waxing crescent`, `first quarter`, `waxing gibbous`, `full`, `waning gibbous`, `last quarter`, `waning crescent`; any `Int` is normalized into `0..999`. |
| `astro_zodiac_sign(month, day)` | `Result[Str, Str]` | Tropical sign for a month/day (no year); `Err` when the month/day is invalid (e.g. month 13, Feb 30, Apr 31). |

## Usage

```xi
use xiom.astronomy;
use xiom.io;

fn main() -> Int {
  let jd = astro_julian_day(2000, 1, 1);
  match jd {
    Ok(v) => { io.println("JD(2000-01-01) = 2451545: " + v); },
    Err(e) => { io.println(e); },
  }
  let phase = astro_moon_phase_permille(2000, 1, 21);   // 507 (full moon)
  match phase {
    Ok(p) => { io.println(astro_moon_phase_name(p)); }, // "full"
    Err(_) => {},
  }
  let sign = astro_zodiac_sign(3, 21);
  match sign {
    Ok(s) => { io.println(s); },                        // "Aries"
    Err(_) => {},
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.astronomy
```

Expected tail: 22 `[PASS]` lines, `xiom.astronomy: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Day granularity, no ephemeris.** The moon phase uses one mean synodic
  month (29.530589 days) and whole civil days: about `+-1` day of error, no
  time of day, no perturbation terms, no true epoch tables.
- **UTC civil dates only.** No timezone conversion, no DST, no leap seconds
  or timescales (UT/TT/Delta-T).
- **Integer JDN convention.** The Julian day returned is the integer JDN
  (`JD(2000-01-01) = 2451545`); the `.5`-day fraction of a `00:00 UTC`
  instant is not represented.
- **Proleptic Gregorian, year >= -4799** (the Fliegel-Van Flandern formula's
  valid range); no Julian-calendar dates and no BCE year numbering beyond
  that range.
- **Zodiac has no year.** February accepts day 29 (a leap day is possible)
  and 30-day months accept up to day 30; dates like Feb 30 are rejected.
- Moon-phase names lump the two new-moon windows (`0..62` and `938..999`)
  under `new`; the returned strings are the plain lowercase names above.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
