# xiom.meteorology

> **Status:** `stable` -- implemented in pure XIOM (no FFI) and green under the
> repo harness: 22/22 conformance checks on compiler v0.61.3. **NOT published**
> to the XIOM registry (`publish: false` in `STATUS.json`).
> **Scope:** decode-only codecs for aviation weather reports -- one METAR/SPECI
> observation or one TAF forecast per call: report header, wind, visibility,
> RVR, present weather, sky cover, temperature/dewpoint, altimeter and NOSIG,
> plus the TAF TEMPO/BECMG/FM change groups.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.meteorology` turns raw report text such as

```
METAR EGLL 121850Z AUTO 24012G22KT 220V260 9999 -RA SCT020 BKN035 12/09 Q1015 NOSIG
SPECI KLAX 282359Z COR VRB03KT 0800 R16L/0400V0800FT/U FG VV002 02/M01 Q1009
TAF LBBG 041600Z 0418/0518 18008KT 9999 BKN020 TEMPO 0420/0423 20015G25KT 3000 -RA BKN010 BECMG 0502/0504 25006KT 9999 SCT025 FM050600 22010KT
```

into plain values: a `MetarReport` or `TafReport` built only from `Str`, `Int`,
`Bool` and parallel `Vec` fields, or a deterministic `Err("metar: ...")` /
`Err("taf: ...")` message carrying the byte offset of the offending token.
Unrecognized tokens are preserved in per-report extra-token lists instead of
being dropped; malformed tokens in recognized positions are rejected. Parsing
is stateless and byte-oriented; all arithmetic is 64-bit signed integer math in
fixed units (metres, tenths of a degree, hundredths of inHg), with no floating
point, no I/O and no global state.

## Package layout

| Path | Purpose |
|---|---|
| `package.xi` | Manifest: package `xiom.meteorology` 0.1.0, module `xiom.meteorology`, dep `xiom.std`. |
| `src/meteorology.xi` | The whole library (2401 lines): token helpers, recognizers, `metar_decode` + 50 accessors, `taf_decode` + 37 accessors. |
| `tests/test_conformance.xi` | 22-check conformance suite; every fixture is built in-test, no data files. |
| `README.md` / `SPEC.md` | This overview; the format spec, unit conventions, error catalog and test plan. |
| `STATUS.json` | Harness metadata (stage, last recorded run, publish state). |

## Build and test

From the repository root:

```
.\scripts\port.ps1 -Package xiom.meteorology
```

The harness enforces the namespace rule, compiles the package, runs
`tests/test_conformance.xi`, and is expected to end with:

```
port: PASS (passed=22 failed=0 program_exit=0 exit=0)
```

## Usage

```xi
use xiom.meteorology;
use xiom.io; use xiom.convert;

fn main() -> Int {
  let raw = "METAR EGLL 121850Z AUTO 24012G22KT 220V260 9999 -RA SCT020 BKN035 12/09 Q1015 NOSIG";
  match metar_decode(raw) {
    Ok(m) => {
      io.println(metar_station(&m));                                   // EGLL
      io.println(convert.int_to_string(metar_wind_dir(&m)));           // 240
      io.println(convert.int_to_string(metar_wind_gust(&m)));          // 22
      io.println(convert.int_to_string(metar_vis_m(&m)));              // 9999
      if metar_weather_count(&m) > 0 { io.println(metar_weather_raw(&m, 0)); } // -RA
      io.println(convert.int_to_string(metar_temperature_tenths(&m))); // 120 (12.0 C)
      io.println(convert.int_to_string(metar_altimeter_hpa(&m)));      // 1015
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

A TAF decodes the same way: `match taf_decode(raw) { Ok(t) => { ... taf_fc_kind(&t, g) ... } }`.
See `SPEC.md` section 5 for the change-group field layout.

## API summary

89 exported functions: 2 decoders, 50 `MetarReport` accessors, 37 `TafReport`
accessors, plus the public types `MetarReport` and `TafReport`. Every accessor
takes the report by reference and returns `Str`, `Int` or `Bool`; indexed
accessors return `""` / `-1` / `false` for an out-of-range index.

METAR entry points:

| Entry point | Returns | Description |
|---|---|---|
| `metar_decode(s)` | `Result[MetarReport, Str]` | Decode one METAR/SPECI observation. |
| `metar_station(r)` | `Str` | Station designator as written (4 letters, either case). |
| `metar_report_type(r)` | `Int` | 0 plain, 1 METAR, 2 SPECI. |
| `metar_is_auto(r)`, `metar_is_cor(r)` | `Bool` | AUTO / COR token seen. |
| `metar_day(r)`, `metar_hour(r)`, `metar_minute(r)` | `Int` | Observation day 1-31, hour 0-23, minute 0-59. |
| `metar_wind_dir(r)` | `Int` | Whole degrees 0-360; -1 for VRB. |
| `metar_wind_speed(r)`, `metar_wind_gust(r)` | `Int` | Whole knots or m/s per `metar_wind_unit`; gust -1 when absent. |
| `metar_wind_unit(r)` | `Int` | 0 KT, 1 MPS. |
| `metar_wind_is_calm(r)`, `metar_wind_is_variable(r)` | `Bool` | `00000KT` calm group / VRB direction. |
| `metar_var_from(r)`, `metar_var_to(r)` | `Int` | `ddd V ddd` variability bounds; -1 when absent. |
| `metar_vis_m(r)` | `Int` | Visibility in metres; -1 absent, 10000 for CAVOK, truncated metres for SM. |
| `metar_is_cavok(r)`, `metar_vis_is_sm(r)`, `metar_vis_at_least_10km(r)`, `metar_vis_is_ndv(r)` | `Bool` | CAVOK / statute-mile form / 9999-or-CAVOK / NDV suffix. |
| `metar_vis_prefix(r)` | `Int` | Statute-mile prefix: 0 none, 1 M, 2 P. |
| `metar_rvr_count(r)` | `Int` | Number of RVR groups. |
| `metar_rvr_raw(r, i)`, `metar_rvr_runway(r, i)` | `Str` | RVR token / runway designator of group `i`. |
| `metar_rvr_min_m(r, i)`, `metar_rvr_max_m(r, i)` | `Int` | RVR bounds in metres (FT converted, truncated); max equals min when not variable. |
| `metar_rvr_is_variable(r, i)` | `Bool` | V range present. |
| `metar_rvr_prefix(r, i)`, `metar_rvr_prefix2(r, i)` | `Int` | 0 none, 1 M, 2 P for each bound. |
| `metar_rvr_unit(r, i)` | `Int` | 0 m, 1 ft. |
| `metar_rvr_trend(r, i)` | `Int` | 0 none, 1 U, 2 D, 3 N. |
| `metar_weather_count(r)` | `Int` | Number of present-weather groups. |
| `metar_weather_raw(r, i)`, `metar_weather_descriptor(r, i)`, `metar_weather_phenomena(r, i)` | `Str` | Token text / descriptor / concatenated phenomena. |
| `metar_weather_intensity(r, i)` | `Int` | 0 moderate, 1 light, 2 heavy, 3 vicinity. |
| `metar_weather_is_nsw(r, i)` | `Bool` | Token was NSW. |
| `metar_sky_count(r)` | `Int` | Number of sky layers. |
| `metar_sky_raw(r, i)`, `metar_sky_type(r, i)` | `Str` | Token text / `""` or `CB`/`TCU`. |
| `metar_sky_cover(r, i)` | `Int` | 0 FEW, 1 SCT, 2 BKN, 3 OVC, 4 VV. |
| `metar_sky_height_ft(r, i)` | `Int` | Layer height in feet; -1 for `VV///`. |
| `metar_has_temperature(r)` | `Bool` | Temperature/dewpoint group decoded. |
| `metar_temperature_tenths(r)`, `metar_dewpoint_tenths(r)` | `Int` | Tenths of a degree Celsius. |
| `metar_altimeter_inhg100(r)` | `Int` | Axxxx form, hundredths of inHg; -1 absent. |
| `metar_altimeter_hpa(r)` | `Int` | Qxxxx form, whole hPa; -1 absent. |
| `metar_is_nosig(r)` | `Bool` | NOSIG token seen. |
| `metar_extra_count(r)`, `metar_extra(r, i)` | `Int`, `Str` | Unclassified tokens, including the whole RMK tail. |

TAF entry points:

| Entry point | Returns | Description |
|---|---|---|
| `taf_decode(s)` | `Result[TafReport, Str]` | Decode one TAF forecast. |
| `taf_station(t)` | `Str` | Station designator as written. |
| `taf_is_amd(t)`, `taf_is_cor(t)` | `Bool` | AMD / COR token seen. |
| `taf_day(t)`, `taf_hour(t)`, `taf_minute(t)` | `Int` | Issue time; minute 0 for the short `DDHHZ` form. |
| `taf_valid_from_day(t)`, `taf_valid_from_hour(t)`, `taf_valid_to_day(t)`, `taf_valid_to_hour(t)` | `Int` | Validity period start/end. |
| `taf_forecast_count(t)` | `Int` | Number of TEMPO/BECMG/FM change groups. |
| `taf_fc_kind(t, g)` | `Int` | 0 BECMG, 1 TEMPO, 2 FM. |
| `taf_fc_from_day(t, g)`, `taf_fc_from_hour(t, g)`, `taf_fc_to_day(t, g)`, `taf_fc_to_hour(t, g)` | `Int` | Change-group validity; `to_*` are -1 for FM. |
| `taf_fc_has_wind(t, g)` | `Bool` | Group carried a wind group. |
| `taf_fc_wind_dir(t, g)`, `taf_fc_wind_speed(t, g)`, `taf_fc_wind_gust(t, g)`, `taf_fc_wind_unit(t, g)` | `Int` | Group wind (same units/sentinels as METAR). |
| `taf_fc_has_vis(t, g)` | `Bool` | Group carried a visibility group. |
| `taf_fc_vis_m(t, g)` | `Int` | Group visibility in metres; -1 absent, 10000 for CAVOK. |
| `taf_fc_is_cavok(t, g)`, `taf_fc_vis_is_sm(t, g)` | `Bool` | CAVOK / statute-mile form. |
| `taf_weather_count(t)` | `Int` | Weather tokens decoded inside change groups. |
| `taf_weather_raw(t, k)`, `taf_weather_group(t, k)` | `Str`, `Int` | Token text / owning group index. |
| `taf_sky_count(t)` | `Int` | Sky layers decoded inside change groups. |
| `taf_sky_raw(t, k)`, `taf_sky_group(t, k)` | `Str`, `Int` | Token text / owning group index. |
| `taf_sky_cover(t, k)`, `taf_sky_height_ft(t, k)` | `Int` | Cover 0-4 / height in feet (-1 for `VV///`). |
| `taf_fc_extra_count(t, g)`, `taf_fc_extra(t, g, k)` | `Int`, `Str` | Unclassified tokens inside change group `g` (O(entries)). |
| `taf_extra_count(t)`, `taf_extra(t, k)` | `Int`, `Str` | Tokens before the first change group (the undecoded base period). |

## Units and rounding

Everything is an integer in a fixed unit; there is no floating point anywhere.

| Quantity | Field / accessor | Stored as | Range / sentinel |
|---|---|---|---|
| Wind direction | `wind_dir` | whole degrees | 0-360; -1 for VRB |
| Wind speed / gust | `wind_speed`, `wind_gust` | whole KT or MPS (`wind_unit`) | 0-999; gust -1 when absent |
| Variability bounds | `var_from`, `var_to` | whole degrees | 0-360; -1 when absent |
| Visibility | `vis_m` | metres | 0-9999; 10000 for CAVOK; -1 when absent |
| RVR bounds | `rvr_min_m`, `rvr_max_m` | metres | 0000-9999 (FT truncated); max = min when not variable |
| Temperature / dewpoint | `temp_tenths`, `dew_tenths` | tenths of a degree C | +/-990; `M0` yields 0 |
| Altimeter, A form | `alt_inhg100` | hundredths of inHg | 0000-9999; -1 when absent |
| Altimeter, Q form | `alt_hpa` | whole hPa | 0000-9999; -1 when absent |
| Sky height | `sky_height` | feet | 0-99900; -1 for `VV///` |

Conversions are integer divisions that **truncate toward zero; nothing is
rounded**:

- statute miles -> metres: `milli * 1609344 / 1000000`, where `milli` is
  thousandths of a statute mile, itself `d * 1000` or `(p * 1000) / q` for the
  `p/qSM` fraction. Pins: `1/2SM` -> 804 m, `1 1/2SM` -> 2414 m,
  `M1/4SM` -> 402 m, `10SM` -> 16093 m.
- RVR feet -> metres: `ft * 3048 / 10000`. Pins: `0400FT` -> 121 m,
  `0800FT` -> 243 m, `1200FT` -> 365 m, `2000FT` -> 609 m.

The `Int` sentinel -1 marks "not reported" wherever the table says so;
out-of-range indexed accessors return `""` / `-1` / `false`.

## Errors and limits

- Both decoders return `Err("metar: <kind> at offset N[: <token>]")` /
  `Err("taf: <kind> at offset N[: <token>]")`. `N` is the 0-based byte offset
  of the offending token, or the input length for a missing trailing token.
  The full catalog is in `SPEC.md` section 7; no other failure mode exists
  (the decoders never panic).
- A token rejected in a recognized position is an error; tokens matching no
  group at all are preserved (in report order) in `metar_extra` /
  `taf_extra` / `taf_fc_extra`. `RMK` starts an opaque tail: the token and
  everything after it are preserved and never interpreted.
- Repeated single-instance groups (wind, variable wind, visibility,
  temperature, altimeter in METAR) are errors; RVR, weather and sky groups
  repeat freely. Inside a TAF change group, a second wind or visibility lands
  in that group's extra list instead of failing.
- Limits: decode-only (no encoding); METAR `BECMG`/`TEMPO` trend and
  `NSC`/`NCD` go to extras; the TAF base forecast period is not decoded (all
  extras), and TAF weather/sky detail is limited to what `SPEC.md` section 5
  lists; the RMK body is not decoded; no unit conversion (KT/MPS, inHg/hPa are
  reported separately); no real-world range validation beyond the token
  grammars; ASCII only; tokens are split on spaces and tabs only, so CR/LF
  bytes are part of the surrounding token.

## Conformance

`tests/test_conformance.xi` runs 22 checks, all passing:

```
port: PASS (passed=22 failed=0 program_exit=0 exit=0)
```

Coverage: full/partial METAR headers, AUTO/COR/SPECI, calm/VRB/gusting/MPS
wind, meter/NDV/CAVOK/SM/mixed-SM visibility, RVR with M/P, FT conversion,
variable ranges and trends, 26 present-weather groups (descriptors,
precipitation, obscuration, other, NSW), all sky layer forms (`CB`/`TCU`,
`VV///`, `VVhhh`), temperature and both altimeter forms, `NOSIG`, opaque RMK,
extra-token preservation, TAF header/issue/validity, TEMPO/BECMG/FM groups
with wind/visibility/weather/sky, AMD and short forms, and the malformed-input
catalog with exact byte offsets.

See `SPEC.md` for the exact grammar, field tables, error catalog, test plan
and implementation notes. License: MIT OR Apache-2.0.
