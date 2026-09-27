# xiom.meteorology -- specification

Version: 0.1.0 (`stable`, not published).
Module: `xiom.meteorology` (`src/meteorology.xi`, 2401 lines). Pure XIOM,
no FFI. Compiler: XIOM v0.61.3. Dependency: `xiom.std >=0.60.0 <1.0.0`.

This document describes exactly what `src/meteorology.xi` and
`tests/test_conformance.xi` implement. Where the placeholder banner mentioned
atmospheric layers, precipitation, storms, sounding and visibility libraries,
those are **not** part of this package: the implemented scope is decode-only
METAR/SPECI and TAF report parsing.

## 1. Scope and model

Exactly two public decoders:

- `metar_decode(s) -> Result[MetarReport, Str]` -- one METAR/SPECI observation,
- `taf_decode(s) -> Result[TafReport, Str]` -- one TAF forecast,

plus 87 field accessors (50 for `MetarReport`, 37 for `TafReport`) and the two
public result types. All recognizers and helpers are private (leading `_`).

Both decoders are stateless and byte-oriented: the input is scanned once into
tokens, every function is a free function, and no object is allocated beyond
the `Vec` fields of the returned value. All arithmetic is 64-bit signed
integer arithmetic in fixed units; there is no floating point, no I/O, no
locale and no global state.

Failure is always a value: the decoders return `Err("metar: ...")` or
`Err("taf: ...")` with the byte offset of the offending token (section 7).
There is no other failure mode; no input can make a decoder panic.

## 2. Token model

- Tokens are separated by runs of ASCII space (32) or horizontal tab (9).
  Leading and trailing separators are ignored; an empty input has zero tokens.
- Any other byte -- including carriage return and line feed -- is an ordinary
  token byte. Reports copied from CRLF text files are therefore **not**
  normalized: `A3005\r\n` is a 7-byte token, not an altimeter.
- Each token is recorded with its 0-based byte offset in `s`. Error messages
  use that offset (for a missing trailing token: `len(s)`).
- Recognition is byte-exact and case-sensitive for every keyword (`METAR`,
  `SPECI`, `AUTO`, `COR`, `TAF`, `AMD`, `RMK`, `NOSIG`, `CAVOK`, `NDV`, `VRB`,
  `KT`, `MPS`, `SM`, `FT`, `CB`, `TCU`, `NSW`, `TEMPO`, `BECMG`, `FM`). The
  station designator is the only case-insensitive field: it accepts ASCII
  letters in either case.
- There is no trimming and no re-quoting: raw tokens in `extra` lists are
  returned exactly as they appeared.
- Lexical shapes (digit runs, letter checks) are checked byte by byte; a
  non-ASCII byte therefore fails any numeric or letter position.

## 3. METAR/SPECI grammar

```
report  := [ "METAR" | "SPECI" ] flags* station time flags* wind group*
flags   := "AUTO" | "COR"
station := 4 ASCII letters (A-Z or a-z), preserved verbatim
time    := DDHHMMZ                    (exact 7 bytes, last byte "Z")
wind    := ( "VRB" | ddd ) ff [ "G" gg ] ( "KT" | "MPS" )
group   := variability | visibility | rvr | weather | sky
         | temperature | altimeter | "NOSIG"
```

- `METAR` selects `report_type = 1`, `SPECI` selects `2`; with no keyword
  `report_type = 0` and the first token is the station candidate.
- `AUTO`/`COR` are consumed only in two header slots: any number before the
  station, and any number immediately after the observation time (their usual
  position). Elsewhere they are ordinary tokens (and land in `extra` unless
  they collide with another grammar).
- The station is required: exactly 4 ASCII letters, either case.
- The time is required: `DDHHMMZ` with day 01-31 (00 rejected), hour 00-23,
  minute 00-59.
- The wind group is required and comes immediately after the time/flags.
  It is the only position-sensitive group.
- The remaining tokens are classified independently and order-tolerantly
  (section 3.3). Parsing stops when `RMK` is seen.

### 3.1 Wind

- Token length at least 7 bytes. Suffix `KT` selects unit 0 (knots), `MPS`
  selects unit 1 (metres per second); anything else is not a wind.
- Direction: the literal `VRB`, or exactly 3 digits with value 0-360
  (361-999 is not a wind; `000` is a valid direction).
- Speed: 2-3 digits. Optional gust: `G` followed by 2-3 digits.
- `VRB` sets `wind_vrb = true` and `wind_dir = -1`.
- `wind_calm` is true only for a non-VRB group with direction `000`, speed
  `0` and no gust (i.e. exactly `00000KT`/`00000MPS`).
- `wind_gust = -1` when the `G` group is absent.
- Pinned shapes: `24012G22KT`, `180115G125KT` (3-digit speed and gust),
  `VRB03KT`, `18003MPS`, `00000KT`.

### 3.2 Variability group

`ddd V ddd`: exactly 3 digits, byte `V`, exactly 3 digits. Both values must be
0-360; a shape-valid group with a value above 360 is an error
(`metar: invalid variable wind ...`). At most one group; a second one is an
error. Absent: `var_from = var_to = -1`.

### 3.3 Classification precedence

Within the free-order loop each token is tested in this order; the first
matching branch claims it:

| # | Test | Branch |
|---|---|---|
| 1 | `RMK` | opaque tail: the token and all following tokens go to `extra`; parsing stops |
| 2 | `NOSIG` | sets `nosig` (repeatable, no error) |
| 3 | `CAVOK` | visibility (duplicate if already present) |
| 4 | first byte `R` and second byte a digit | RVR; malformed -> error |
| 5 | exactly 4 digits, or 4 digits + `NDV` | meter visibility |
| 6 | ends with `SM` | statute-mile visibility; malformed -> error |
| 7 | 1-2 digit whole token whose next token is a prefix-free `p/qSM` | mixed statute-mile visibility |
| 8 | 3 digits + `V` + 3 digits | variability; > 360 or duplicate -> error |
| 9 | ends with `KT` or `MPS` | wind attempt: parse -> duplicate error, else invalid-wind error |
| 10 | sky layer shape | sky layer |
| 11 | present-weather shape | weather group |
| 12 | contains `/` | temperature attempt; malformed -> error |
| 13 | exactly 5 bytes starting with `A` or `Q` | altimeter attempt; malformed -> error |
| 14 | otherwise | `extra` |

Consequences: `VV///` is sky (10) not temperature (12); `M1/4SM` is SM
visibility (6) not temperature; `TX32/1218Z` in a METAR is an invalid
temperature (12); a bare `5` is an extra unless followed by a plain `p/qSM`
(7); a second wind-shaped token (9) is always an error, never an extra.

### 3.4 Visibility

At most one visibility group. The recognized forms:

| Form | Example | `vis_m` | Flags |
|---|---|---|---|
| 4 digits | `0800` | 800 | -- |
| 4 digits + `NDV` | `0800NDV` | 800 | `vis_ndv` |
| `9999` | `9999` | 9999 | `vis_ge_10km` |
| `CAVOK` | `CAVOK` | 10000 | `vis_cavok`, `vis_ge_10km` |
| whole SM | `10SM` | truncated metres of 10.000 SM | `vis_sm` |
| fraction SM | `1/2SM` | truncated metres of 0.500 SM | `vis_sm` |
| prefixed SM | `M1/4SM`, `P6SM` | as above | `vis_sm`, `vis_prefix` 1/2 |
| mixed SM | `1 1/2SM` | truncated metres of 1.500 SM | `vis_sm` |

- Whole-SM numeral: 1-3 digits, value 0-999. Fractions: digit run `p`,
  single `/`, digit run `q` with `q >= 1` and `p <= q` (`p = 0` is accepted
  and yields 0 m; a second `/` and a bare `/` are invalid). `M` means "less
  than" (`vis_prefix = 1`), `P` "greater than" (`2`).
- Mixed form: the whole token is 1-2 digits (0-99) and the following token is
  a **prefix-free** `p/qSM` fraction (a prefixed fraction such as `M1/4SM`
  parses on its own via the SM branch). The two tokens are consumed together.
- A token that ends with `SM` but fails the SM grammar is an error
  (`metar: invalid visibility ...`), not an extra.
- A token of four digits is a meter visibility even when it is `0000`.
  `9999` sets `vis_ge_10km`; CAVOK also sets it and stores 10000.
- A malformed NDV suffix makes the token unrecognizable for this branch
  (`0800ND`, `0800NDVX` fall through to the later branches, normally `extra`).

### 3.5 RVR

Trigger: token whose first byte is `R` and second byte is a digit. The shape
is:

```
rvr := "R" runway "/" [ "M" | "P" ] vvvv [ "V" [ "M" | "P" ] vvvv ]
       [ "FT" ] [ "/" ] [ "U" | "D" | "N" ]
runway := 1-2 digits with value 1-36, optionally suffixed L, C or R
vvvv   := exactly 4 ASCII digits
```

- The runway designator is the text between `R` and the first `/`; it must be
  2-3 bytes long with a digit run of 1-2 bytes and a value 1-36. Because of
  the 2-byte minimum, a bare one-digit runway is rejected (`R1/0400` is
  invalid) while `R01/0400` and `R1L/0400` are accepted. `L`/`C`/`R`
  suffixes select the parallel runway.
- Lower (first) value: 4 digits `0000`-`9999`, no range validation. Optional
  `M` (prefix 1, below) or `P` (prefix 2, above).
- `V` makes the group a variable range; the second value has its own optional
  `M`/`P` prefix. Without `V`, `max_m == min_m` and `rvr_variable` is 0.
- `FT` selects unit 1 (feet); without it unit 0 (metres). The stored bounds
  are always **metres**: `v * 3048 / 10000` truncated for the FT form.
- Optional `/` and trend letter: `U` = 1, `D` = 2, `N` = 3, absent = 0. A
  trailing bare `/` (no letter) is accepted and leaves the trend 0.
- Anything left over is an error (`metar: invalid RVR ...`).
- Any number of RVR groups is accepted, in report order; `extra` does not
  receive them.
- Pins: `R16L/0400V0800FT/U` -> min 121 m, max 243 m, variable, unit 1,
  trend 1; `R16L/M0400N` -> min = max = 400 m, prefix 1, trend 3;
  `R24R/1200V2000FT` -> 365 m / 609 m.

### 3.6 Present weather

```
wx := [ "+" | "-" | "VC" ] [ descriptor ] phenomenon+
descriptor := MI BC PR DR BL SH TS FZ
phenomenon := DZ RA SN SG IC PL GR GS UP          (precipitation)
            | BR FG FU VA DU SA HZ PY            (obscuration)
            | PO SQ FC SS DS                     (other)
```

- Intensity: absent = 0 (moderate), `-` = 1 (light), `+` = 2 (heavy),
  `VC` = 3 (in the vicinity). `VC` requires at least two bytes after it.
- Phenomena are two-letter codes, repeated and concatenated in token order
  (`-SHRASN` -> descriptor `SH`, phenomena `RASN`).
- A lone descriptor is accepted only when it is `TS`, or when the token
  carries the `VC` prefix (`VCTS`, `VCSH`, ...). Otherwise a token with no
  phenomenon is not a weather group.
- `NSW` is special-cased: it is a weather group with `wx_nsw = 1` (raw token
  preserved, descriptor and phenomena empty).
- Unknown code combinations (`RERA`, `TSXX`, `FZ` alone, ...) are not weather
  groups; they fall through the precedence table (normally to `extra`).
- Any number of weather groups is accepted.

### 3.7 Sky cover

```
sky := ( FEW | SCT | BKN | OVC ) hhh [ "CB" | "TCU" ]
     | "VV" hhh
     | "VV" "///"
```

- Cover codes: `FEW` = 0, `SCT` = 1, `BKN` = 2, `OVC` = 3, `VV` = 4.
- `hhh` is exactly 3 digits (000-999), stored as height `hhh * 100` feet.
- `CB`/`TCU` suffixes are recognized only on the four cover words
  (8- and 9-byte tokens); the vertical-visibility form has no type suffix.
- `VV///` stores cover 4 with height -1 (unknown).
- Any number of layers is accepted, in report order.

### 3.8 Temperature and dewpoint

```
temp := tt "/" tt
tt   := [ "M" ] digit | digit digit
```

- Exactly one `/`; both sides are required. Each side is an optional `M`
  followed by 1-2 digits; the value is `digits * 10` (tenths of a degree
  Celsius), negated when `M` is present and the value is nonzero (so `M0` and
  `M00` store 0, never a negative zero).
- A token containing `/` that reaches this branch and fails the grammar is an
  error (`metar: invalid temperature ...`); a second temperature group is an
  error (`metar: duplicate temperature ...`).
- `metar_has_temperature` is the only indication that the (zero-initialized)
  temperature fields are meaningful.

### 3.9 Altimeter

Exactly 5 bytes: `A` or `Q` followed by 4 digits.

- `Axxxx` stores `xxxx` in `alt_inhg100` (hundredths of an inch of mercury;
  `A2992` = 29.92 inHg).
- `Qxxxx` stores `xxxx` in `alt_hpa` (whole hectopascals; `Q0995` = 995).
- No range validation; the not-reported value is -1 for the missing form.
- Only 5-byte `A`/`Q` tokens are candidates. A malformed one is an error; an
  `A`/`Q` token of another length (e.g. `A29`) is an extra.
- At most one altimeter group; a second is an error.

### 3.10 NOSIG, RMK and extras

- `NOSIG` sets the `nosig` flag; it may occur more than once without error.
- `RMK` and every token after it are appended verbatim to `extra` (the `RMK`
  token itself included) and are never interpreted. This happens before any
  other branch, so `RMK` always wins.
- Every token that no branch claims is appended verbatim to `extra`, in
  order. This includes METAR trend groups (`BECMG`, `TEMPO`, ...), `NSC`/
  `NCD`, station remarks and any unrecognized shape.

## 4. `MetarReport` fields

Parallel vectors: index `i` of each `rvr_*`, `wx_*` and `sky_*` vector
describes the same group; every push mirrors all vectors of the family.

| Field | Type | Accessor(s) | Meaning / sentinel |
|---|---|---|---|
| `station` | `Str` | `metar_station` | Station as written. |
| `report_type` | `Int` | `metar_report_type` | 0 plain, 1 METAR, 2 SPECI. |
| `auto_flag`, `cor_flag` | `Bool` | `metar_is_auto`, `metar_is_cor` | Header flags. |
| `day`, `hour`, `minute` | `Int` | `metar_day`, `metar_hour`, `metar_minute` | Observation time. |
| `wind_dir` | `Int` | `metar_wind_dir` | Degrees 0-360; -1 for VRB. |
| `wind_speed`, `wind_gust` | `Int` | `metar_wind_speed`, `metar_wind_gust` | KT or MPS; gust -1 absent. |
| `wind_unit` | `Int` | `metar_wind_unit` | 0 KT, 1 MPS. |
| `wind_calm`, `wind_vrb` | `Bool` | `metar_wind_is_calm`, `metar_wind_is_variable` | Calm group / VRB. |
| `var_from`, `var_to` | `Int` | `metar_var_from`, `metar_var_to` | Variability degrees; -1 absent. |
| `vis_m` | `Int` | `metar_vis_m` | Metres; -1 absent, 10000 CAVOK. |
| `vis_cavok`, `vis_sm`, `vis_ge_10km`, `vis_ndv` | `Bool` | `metar_is_cavok`, `metar_vis_is_sm`, `metar_vis_at_least_10km`, `metar_vis_is_ndv` | Visibility form flags. |
| `vis_prefix` | `Int` | `metar_vis_prefix` | 0 none, 1 M, 2 P. |
| `rvr_raw`, `rvr_runway` | `Vec[Str]` | `metar_rvr_raw`, `metar_rvr_runway` | Token text / runway. |
| `rvr_min_m`, `rvr_max_m` | `Vec[Int]` | `metar_rvr_min_m`, `metar_rvr_max_m` | Bounds in metres. |
| `rvr_prefix`, `rvr_prefix2` | `Vec[Int]` | `metar_rvr_prefix`, `metar_rvr_prefix2` | 0/1/2 per bound. |
| `rvr_variable` | `Vec[Int]` | `metar_rvr_is_variable` | 0/1 (accessor returns `Bool`). |
| `rvr_unit`, `rvr_trend` | `Vec[Int]` | `metar_rvr_unit`, `metar_rvr_trend` | 0 m/1 ft; 0-3 trend. |
| `wx_raw`, `wx_descriptor`, `wx_phenomena` | `Vec[Str]` | `metar_weather_raw`, `metar_weather_descriptor`, `metar_weather_phenomena` | Weather text parts. |
| `wx_intensity`, `wx_nsw` | `Vec[Int]` | `metar_weather_intensity`, `metar_weather_is_nsw` | 0-3; NSW 0/1. |
| `sky_raw`, `sky_type` | `Vec[Str]` | `metar_sky_raw`, `metar_sky_type` | Token text / `""`/`CB`/`TCU`. |
| `sky_cover`, `sky_height` | `Vec[Int]` | `metar_sky_cover`, `metar_sky_height_ft` | Cover 0-4; feet (-1 `VV///`). |
| `temp_tenths`, `dew_tenths` | `Int` | `metar_temperature_tenths`, `metar_dewpoint_tenths` | Tenths of a degree C. |
| `have_temp` | `Bool` | `metar_has_temperature` | Temperature group decoded. |
| `alt_inhg100`, `alt_hpa` | `Int` | `metar_altimeter_inhg100`, `metar_altimeter_hpa` | A form / Q form; -1 absent. |
| `nosig` | `Bool` | `metar_is_nosig` | NOSIG seen. |
| `extra` | `Vec[Str]` | `metar_extra_count`, `metar_extra` | Unclassified tokens + RMK tail. |

## 5. TAF grammar and `TafReport`

```
forecast := [ "TAF" ] flags* station issue validity change*
flags    := "AMD" | "COR"
issue    := DDHHMMZ | DDHHZ
validity := DDHH "/" DDHH
change   := ( "TEMPO" | "BECMG" ) validity
          | "FMDDHH" | "FMDDHHMM"
```

- The `TAF` keyword is optional and not recorded; `AMD`/`COR` set flags.
- Issue time: 7 bytes `DDHHMMZ`, or 5 bytes `DDHHZ` (minute 0). Both with day
  01-31, hour 00-23, minute 00-59 for the long form.
- Validity: exactly 9 bytes, two `DDHH` halves with day 01-31, hour 00-23.
- Change groups, in order of appearance:

| Keyword | `fc_kind` | Validity stored |
|---|---|---|
| `TEMPO DDHH/DDHH` | 1 | from/to day+hour |
| `BECMG DDHH/DDHH` | 0 | from/to day+hour |
| `FMDDHH[MM]` | 2 | from = day+hour, to day/hour = -1 (open-ended) |

- `TEMPO`/`BECMG` must be followed by a valid `DDHH/DDHH` token; a missing one
  is an error, an invalid one is an error. `FM` must have a 6- or 8-byte
  all-digit payload after the letters, and valid day/hour/minute ranges;
  otherwise an error.
- Change-group content classification (first match wins): wind (the METAR
  wind grammar, including `VRB`, gusts and `MPS`) -> `CAVOK` -> 4-digit meter
  visibility with optional `NDV` -> token ending `SM` (`dSM`, `p/qSM` with
  optional `M`/`P`) -> sky layer -> weather -> the group's extra list. A mixed
  whole + `p/qSM` pair is recognized before this classification when the group
  is open; both its tokens are consumed as one visibility.
- Unlike METAR, group content never errors: a malformed wind/visibility/SM
  token simply falls through to the extra list. The first wind and the first
  visibility of a group win; a second one (including a second `CAVOK`) goes to
  the group's extra list, as does a mixed pair when visibility already exists.
- Weather inside groups stores only the raw token and the owning group index;
  intensity/descriptor/phenomena are validated but not retained. Sky stores
  raw token, group index, cover and height; a `CB`/`TCU` suffix is validated
  but not retained.
- Every token before the first change group (the base forecast period) goes to
  the report-level `extra` list, undecoded, in order.
- Groups may repeat and interleave in any order (`TEMPO` after `FM`, several
  `BECMG`, ...); they are stored in report order and the owning group index is
  explicit for weather/sky/extra entries.

| Field | Type | Accessor(s) | Meaning |
|---|---|---|---|
| `station` | `Str` | `taf_station` | Station as written. |
| `amd_flag`, `cor_flag` | `Bool` | `taf_is_amd`, `taf_is_cor` | Header flags. |
| `day`, `hour`, `minute` | `Int` | `taf_day`, `taf_hour`, `taf_minute` | Issue time. |
| `vfrom_day`, `vfrom_hour`, `vto_day`, `vto_hour` | `Int` | `taf_valid_*` | Validity period. |
| `fc_kind`, `fc_fday`, `fc_fhour`, `fc_tday`, `fc_thour` | `Vec[Int]` | `taf_fc_kind`, `taf_fc_from_*`, `taf_fc_to_*` | Kind and validity per group; `to_*` -1 for FM. |
| `fc_has_wind` | `Vec[Int]` | `taf_fc_has_wind` | 0/1 per group. |
| `fc_wdir`, `fc_wspd`, `fc_wgust`, `fc_wunit` | `Vec[Int]` | `taf_fc_wind_*` | Wind per group (dir -1 VRB/absent, gust -1 absent). |
| `fc_has_vis`, `fc_vis_m`, `fc_cavok`, `fc_vis_sm` | `Vec[Int]` | `taf_fc_has_vis`, `taf_fc_vis_m`, `taf_fc_is_cavok`, `taf_fc_vis_is_sm` | Visibility per group (vis -1 absent, 10000 CAVOK). |
| `wx_raw`, `wx_group` | `Vec[Str]`, `Vec[Int]` | `taf_weather_*` | Weather token / owning group. |
| `sky_raw`, `sky_group`, `sky_cover`, `sky_height` | `Vec[Str]`, `Vec[Int]` | `taf_sky_*` | Sky token / group / cover 0-4 / feet. |
| `fc_extra`, `fc_extra_group` | `Vec[Str]`, `Vec[Int]` | `taf_fc_extra_count`, `taf_fc_extra` | Unclassified tokens per group. |
| `extra` | `Vec[Str]` | `taf_extra_count`, `taf_extra` | Tokens before the first change group. |

TAF vectors are parallel family by family; `wx_group`, `sky_group` and
`fc_extra_group` carry the owning group index rather than position. The
accessors for `fc_extra` scan `fc_extra_group` and are O(number of group
extras); all other accessors are O(1).

## 6. Integer units and conversions

No value is ever stored as a floating-point number, and no conversion rounds:
every integer division truncates toward zero (all converted quantities are
non-negative).

| Quantity | Stored unit | Valid range / sentinel |
|---|---|---|
| Observation/issue/validity day, hour, minute | whole day 1-31, hour 0-23, minute 0-59 | required fields |
| Wind direction, variability bounds | whole degrees | 0-360; VRB / absent -1 |
| Wind speed, gust | whole KT (unit 0) or MPS (unit 1) | 0-999; gust absent -1 |
| Visibility | metres | 0-9999; CAVOK 10000; absent -1 |
| RVR bounds | metres | 0000-9999, FT form converted; max = min when fixed |
| Temperature, dewpoint | tenths of a degree C | -(99x10) .. +(99x10); `M0` -> 0 |
| Altimeter A form | hundredths of inHg | 0000-9999 |
| Altimeter Q form | whole hPa | 0000-9999 |
| Sky height | feet | 00000-99900; `VV///` -1 |
| Weather intensity | code | 0 moderate, 1 light, 2 heavy, 3 vicinity |
| Sky cover | code | 0 FEW, 1 SCT, 2 BKN, 3 OVC, 4 VV |
| RVR trend | code | 0 none, 1 U, 2 D, 3 N |
| RVR / visibility prefix | code | 0 none, 1 M, 2 P |

Conversions:

```
statute miles -> metres:
  milli = d * 1000                       (whole form: d = 0..999)
  milli = (p * 1000) / q                 (fraction form: q >= 1, p <= q)
  value_m = milli * 1609344 / 1000000    (1 SM = 1609.344 m)
  mixed: milli = w * 1000 + (p * 1000) / q, then the same scaling

RVR feet -> metres:
  value_m = v * 3048 / 10000             (1 ft = 0.3048 m)
```

Pinned conversions:

| Input | Stored |
|---|---|
| `1/2SM` | 804 m |
| `M1/4SM` | 402 m (prefix 1) |
| `1 1/2SM` | 2414 m |
| `10SM` | 16093 m |
| RVR `0400FT` | 121 m |
| RVR `0800FT` | 243 m |
| RVR `1200FT` | 365 m |
| RVR `2000FT` | 609 m |

## 7. Error catalog

Both decoders report a single error shape:

```
metar: <kind> at offset <N>
metar: <kind> at offset <N>: <token>
taf:   <kind> at offset <N>
taf:   <kind> at offset <N>: <token>
```

`N` is the 0-based byte offset of the offending token's first byte. When the
report simply ends too early ("missing ..."), `N = len(s)`. `<token>` is the
offending token text, appended only when a token is involved. Messages are
exact and stable; the test suite compares them byte for byte.

METAR errors:

| Message kind | Trigger |
|---|---|
| `missing station` | no token after the optional keyword/flags. |
| `invalid station` | station is not exactly 4 ASCII letters. |
| `missing time` | no token after the station. |
| `invalid time` | not `DDHHMMZ` or out-of-range day/hour/minute. |
| `missing wind` | no token after the time and flags. |
| `invalid wind` | the required wind fails its grammar, or a later `KT`/`MPS` token fails it. |
| `duplicate wind` | a later `KT`/`MPS` token parses as a wind. |
| `invalid variable wind` | `ddd V ddd` shape with a value above 360. |
| `duplicate variable wind` | a second variability group. |
| `invalid visibility` | a token ending in `SM` fails the statute-mile grammar. |
| `duplicate visibility` | a second CAVOK, meter, NDV, SM or mixed-SM group. |
| `invalid RVR` | an `R`+digit token fails the RVR grammar. |
| `invalid temperature` | a token containing `/` reaches the temperature branch and fails. |
| `duplicate temperature` | a second temperature group. |
| `invalid altimeter` | a 5-byte `A`/`Q` token whose payload is not 4 digits. |
| `duplicate altimeter` | a second `A`/`Q` group. |

TAF errors:

| Message kind | Trigger |
|---|---|
| `missing station` | no token after the optional keyword/flags. |
| `invalid station` | station is not exactly 4 ASCII letters. |
| `missing time` | no token after the station. |
| `invalid time` | issue time is not `DDHHMMZ` or `DDHHZ`, or out of range. |
| `missing validity` | no token after the issue time. |
| `invalid validity` | header validity is not `DDHH/DDHH` with valid ranges; also used for an invalid validity after `TEMPO`/`BECMG`. |
| `missing validity after TEMPO` / `... BECMG` | the change keyword is the last token. |
| `invalid FM time` | an `FM...`-shaped token fails its day/hour/minute checks. |

Pinned examples (from `tests/test_conformance.xi`):

```
metar: missing station at offset 0
metar: invalid station at offset 6: EG
metar: invalid time at offset 11: 121850
metar: invalid wind at offset 19: 1800KT
metar: missing wind at offset 18
metar: invalid temperature at offset 27: 12/x8
metar: invalid altimeter at offset 32: A29x2
metar: invalid RVR at offset 27: R16L/04x0
metar: duplicate visibility at offset 32: 0800
metar: duplicate wind at offset 27: 18004KT
metar: invalid variable wind at offset 27: 220V999
metar: duplicate temperature at offset 33: 15/14
taf: missing station at offset 0
taf: missing time at offset 8
taf: invalid validity at offset 17: 1218-1318
taf: missing validity after TEMPO at offset 32
taf: invalid validity at offset 33: 1220/12x4
taf: invalid FM time at offset 27: FM9900
```

Error precedence follows the classification order of section 3.3: for
example, a 5-byte `A`-prefixed token with letters is an invalid altimeter,
not an extra; a token ending `SM` with a broken fraction is an invalid
visibility, not an extra; a second valid-looking wind is a duplicate wind.

## 8. Test suite (`tests/test_conformance.xi`, 22 checks)

Every fixture is built in-test; there are no data files. `main` prints one
`[PASS]`/`[FAIL]` line per check and returns the failure count, so the harness
reports `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

| # | Fixture (abridged) | What it pins |
|---|---|---|
| 1 | `METAR EGLL 121850Z AUTO 24012G22KT 220V260 9999 -RA SCT020 BKN035 12/09 Q1015 NOSIG` | type 1, AUTO, time, gusting wind, variability, 9999 + ge10, one `-RA` (1/`""`/`RA`), SCT020+BKN035 at 2000/3500 ft, 120/90 tenths, Q1015, NOSIG, no extras. |
| 2 | `METAR KJFK 010000Z 00000KT CAVOK M05/M08 A2992` | calm group, CAVOK (10000 + ge10), -50/-80 tenths, A2992 -> 2992, no Q value. |
| 3 | `SPECI KLAX 282359Z COR VRB03KT 0800 R16L/0400V0800FT/U FG VV002 02/M01 Q1009` | SPECI/COR, VRB -1, meter vis, FT RVR 121/243 with trend 1, FG, VV002 200 ft, 20/-10, Q1009. |
| 4 | `METAR KORD 121200Z 09005KT 1/2SM -SN FZFG BKN008 M02/M04 A3001` | `1/2SM` -> 804 m, `-SN`, `FZFG` (FZ+FG), BKN008, -20/-40, A3001. |
| 5 | `METAR KSFO 121200Z 27008KT 1 1/2SM BR OVC010 15/14 A2999` | mixed `1 1/2SM` -> 2414 m, BR, OVC010, 150 tenths. |
| 6 | `METAR KATL 010000Z 180115G125KT 10SM FEW250 33/22 A3010` | 3-digit speed/gust, `10SM` -> 16093 m, FEW250 -> 25000 ft, 330/220. |
| 7 | `METAR ENGM 121200Z 18003MPS 2000 RASN SCT005 OVC020 M01/M03 Q0995` | MPS unit, 2000 m vis, RASN, two layers, -10/-30, Q0995 -> 995. |
| 8 | `... A3005 RMK AO2 SLP132 T01230105 Q1013` | RMK opacity: `Q1013` after RMK is ignored; 5 extras starting with `RMK`; body temperature kept. |
| 9 | `... Q1013 BECMG TEMPO XTRATOKEN` | unknown tokens (`BECMG`, `TEMPO`, `XTRATOKEN`) land in extras without failing. |
| 10 | 26-token weather catalog | group count 26; intensities 1/2/3; descriptors SH/TS/MI/PR/DR/BL/FZ; `DRSA` -> phenomena `SA`; NSW with empty phenomena and the flag set. |
| 11 | 6-token sky catalog | FEW/SCT/BKN/OVC covers, `TCU`/`CB` types, `VV///` height -1, `VV004` height 400. |
| 12 | `COR AUTO egll 121850Z 24008KT ...` | no keyword -> report_type 0, lowercase station preserved, COR+AUTO flags. |
| 13 | malformed header snippets | exact messages and offsets for missing station (`""`), invalid station, invalid time, invalid wind, missing wind. |
| 14 | malformed/duplicate group snippets | invalid temperature/altimeter/RVR and duplicate visibility/wind/variable-wind/temperature messages with offsets. |
| 15 | `0800NDV` | NDV flag set, value 800, SM flag clear. |
| 16 | `M1/4SM` | SM flag, prefix 1, value 402 m. |
| 17 | `R16L/M0400N R24R/1200V2000FT` | M prefix + N trend (400 m, fixed); variable FT range 365/609 m, unit 1, trend 0. |
| 18 | `TAF EGLL 121700Z 1218/1318 24010KT 9999 SCT030` | TAF header/validity; 0 change groups; the three base-period tokens in report extras; out-of-range extra index `""`. |
| 19 | `TAF LBBG ... TEMPO 0420/0423 ... BECMG 0502/0504 ... FM050600 ...` | 3 groups kinds 1/0/2; TEMPO wind 20015G25/3000/`-RA`/BKN010; BECMG 25006KT/9999/SCT025; FM group open-ended (to -1) wind 220. |
| 20 | `TAF AMD EGLL 1217Z 1218/1318 FM0300 TX32/1218Z 22010KT` | AMD, short issue time (minute 0), short FM form, `TX32/1218Z` as a group extra. |
| 21 | `TAF EGLL 121700Z 1218/1318 BECMG 1220/1222 CAVOK` | BECMG CAVOK: has_vis, cavok, 10000 m, no wind. |
| 22 | TAF malformed snippets | missing station (`""`), missing time, invalid validity (`1218-1318`), missing validity after TEMPO, invalid validity after TEMPO, invalid FM time (`FM9900`). |

## 9. Non-goals and limitations

- **Decode-only.** There is no encoder, no report builder, no re-formatting,
  and no checksum or integrity concept (these formats have none).
- **METAR trends are not decoded.** `BECMG`/`TEMPO` (and `NOSIG` is a flag
  only) after the observation body land in `extra`; there is no forecast
  trend type.
- **RMK is opaque.** Nothing after `RMK` is interpreted, including `Q`/`A`
  values, sea-level pressure or hourly temperature groups.
- **TAF base period is not decoded.** Wind/visibility/weather/sky before the
  first change group are preserved verbatim in `taf_extra`; only change-group
  content is classified.
- **TAF detail is narrower than METAR.** Group weather keeps raw text and the
  owning group only; sky keeps cover/height but not `CB`/`TCU`; visibility
  keeps metres, CAVOK and SM flags but not the `M`/`P` prefix or `NDV`; wind
  keeps direction/speed/gust/unit but not calm/VRB booleans (`VRB` is dir -1).
- **No cross-unit conversion.** Knots and m/s, inHg and hPa are reported as
  given; RVR and visibility are the only quantities normalized to metres.
- **No real-world range validation.** Only token grammars and the documented
  ranges are enforced; implausible values (e.g. `180115G125KT`, `Q0000`,
  RVR `9999`) decode successfully.
- **No geographic or station validation.** Any 4 letters is a station.
- **ASCII and exact bytes only.** Keywords are case-sensitive (except the
  station letters); CR/LF are token bytes, not separators; no UTF-8 handling.
- **No multi-report input.** One report string per call; splitting report
  streams on newlines-with-trimming is the caller's job.
- **Truncation, never rounding** (section 6).

## 10. Compiler and stdlib notes (XIOM v0.61.3)

The implementation follows the same discipline as its sibling packages
(`xiom.nmea`, `xiom.weather`):

- Free functions only: no `self` methods, no lambdas, no `Vec[StructType]`,
  no `Vec[Float64]`. Variable-length data is carried by parallel
  `Vec[Str]`/`Vec[Int]` fields with mirrored pushes; booleans in vectors are
  encoded as 0/1 `Int`s (`rvr_variable`, `wx_nsw`, `fc_has_wind`,
  `fc_has_vis`, `fc_cavok`, `fc_vis_sm`).
- `Str` equality always goes through `xiom.string.compare.str_compare`
  (BUG 17: `==` on a `Str` read from a `Vec[Str]` element lowers to a pointer
  comparison). `Vec[Str]`/`Vec[Int]` element reads bind a typed `let` first.
- `Ok`/`Err` for the report types are constructed only in the four leaf
  helpers `_ok_metar`/`_err_metar`/`_ok_taf`/`_err_taf`; constructing a
  `Result` inside a larger function miscompiles.
- All arithmetic is 64-bit signed integer math; `string.byte_at` results are
  widened with `as Int` before arithmetic and are never compared against a
  `UInt8` constant >= 128.
- The library never uses `match`; the tests do, and route every text
  comparison through `str_compare`.
