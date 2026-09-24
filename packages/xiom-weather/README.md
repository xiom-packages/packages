# xiom.weather

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** decode a single METAR observation into a typed record: wind,
> visibility, temperature/dewpoint, altimeter and cloud ceiling, plus the
> FAA-style flight category and a one-line summary.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.weather` turns one raw METAR string such as

```
EGLL 121150Z 24012KT 9999 SCT020 18/12 Q1013
```

into a `Metar` record with fixed units (knots, meters, degrees Celsius,
hectopascals, feet AGL) and derives the flight category. The decoder is
token-based: every recognized token shape fills its value; every other token
(remarks, trends, RVR, wind variation, ...) is ignored, so real-world reports
decode without failing on extensions. Missing numeric values are `-1`.

## API

| Function | Returns | Description |
|---|---|---|
| `metar_parse(raw)` | `Result[Metar, Str]` | Decode one observation. `Err("metar: empty observation")` / `Err("metar: invalid station: <tok>")` only. |
| `metar_flight_category(m)` | `Str` | `"LIFR"`, `"IFR"`, `"MVFR"` or `"VFR"` from visibility and ceiling. |
| `metar_wind_kt(m)` | `Int` | Sustained wind speed in knots (`Metar.wind_gust_kt` holds the gust). |
| `metar_temperature_c(m)` | `Int` | Air temperature in degrees Celsius. |
| `metar_summary(m)` | `Str` | `"<station> <dir>/<kt>kt vis=<vis>m <temp>/<dew> Q<hpa> <category>"`. |

`Metar` fields: `station: Str`, `day`/`hour`/`minute`, `wind_dir_deg`,
`wind_speed_kt`, `wind_gust_kt`, `visibility_m`, `temp_c`, `dewpoint_c`,
`altimeter_hpa`, `ceiling_ft` -- all `Int` except the station, all `-1` when
the report did not carry the value. `wind_dir_deg` is `-1` for `VRB`.
`ceiling_ft` is the lowest `BKN`/`OVC` layer; `CAVOK` sets visibility to
`10000` m and clears the ceiling.

## Token table

| Token | Shape | Effect |
|---|---|---|
| station | 4 ASCII letters (either case) | required first token, stored verbatim |
| time | `DDHHMMZ` | day 1-31, hour 0-23, minute 0-59 |
| wind | `dddssKT` | direction 0-360, speed |
| wind gust | `dddssGggKT` | direction, speed, gust |
| variable wind | `VRBssKT` | direction -1, speed |
| metric visibility | `dddd` | 0-9999 meters |
| CAVOK | `CAVOK` | visibility 10000 m, ceiling -1 |
| statute miles | digits + `SM` | `n * 1609` meters |
| clouds | `FEW`/`SCT`/`BKN`/`OVC` + 3 digits | hundreds of feet; `BKN`/`OVC` count for the ceiling |
| temp / dewpoint | `TT/TT` or `MTT/MTT`, either side may be empty | degrees Celsius |
| altimeter | `Qdddd` / `Adddd` | hPa as-is / hundredths of inHg -> hPa, truncated |

Tokens whose shape is not listed are ignored. Later recognized tokens of the
same kind overwrite earlier ones. The full grammar, conversions, category
thresholds and error catalog are in `SPEC.md`.

## Usage

```xi
use xiom.weather;
use xiom.io;

fn main() -> Int {
  match metar_parse("EGLL 121150Z 24012KT 9999 SCT020 18/12 Q1013") {
    Ok(m) => {
      io.println(metar_summary(&m));      // EGLL 240/12kt vis=9999m 18/12 Q1013 VFR
      io.println(metar_flight_category(&m)); // VFR
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.weather
```

Expected tail: 20 `[PASS]` lines, `xiom.weather: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **One observation at a time:** no report assembly, no `METAR`/`SPECI`
  prefix handling, no station databases, no date/timezone arithmetic (the
  day/hour/minute are stored exactly as reported).
- **No TAF, no trends, no remarks:** `RMK ...` is ignored; `BECMG`/`TEMPO`
  group markers are ignored, but a trend token that has a recognized value
  shape (e.g. a bare `3000`) is applied like any other token -- the decoder is
  token-based, not section-aware. Present-weather groups (`RA`, `BR`,
  `+TSRA`), RVR (`R06L/2000`) and wind variation (`240V300`) are ignored.
- **No fractional or `P`-prefixed statute miles:** `1 1/2SM` and `P6SM` are
  ignored (SM visibility must be one whitespace-free token of digits + `SM`).
- **Fixed token widths:** `dddssKT` / `dddssGggKT` / `VRBssKT` exactly (no
  `VRBssGggKT`, no 3-digit speeds or gusts); cloud layers must be exactly
  prefix + 3 digits (no `FEW020TCU`, no `VV///`).
- **`-1` sentinel:** a genuine `-1` degC temperature/dewpoint is
  indistinguishable from "not reported" (both render as `///`, see
  `SPEC.md` section 6); `wind_dir_deg` `-1` means variable or missing.
- **Not a validator:** only two errors exist (empty input, bad station);
  a syntactically odd report decodes as far as its recognizable tokens allow.

See `SPEC.md` for the exact grammar, conversions, thresholds, error catalog
and test plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
