# xiom.weather -- specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.weather` (`src/weather.xi`). Pure XIOM, no FFI.

## 1. Scope and model

Decode **one** raw METAR observation string into a `Metar` record and derive
the flight category and a one-line summary:

- `metar_parse` -- text -> `Result[Metar, Str]`,
- `metar_flight_category` -- record -> `"LIFR" | "IFR" | "MVFR" | "VFR"`,
- `metar_wind_kt`, `metar_temperature_c` -- convenience accessors,
- `metar_summary` -- record -> human-readable one-liner.

Units are fixed and spelled out in the field names: degrees true, knots,
meters, degrees Celsius, hectopascals, feet AGL. All arithmetic is 64-bit
integer arithmetic; there is no floating point, no date math, no I/O and no
global state.

The decoder is **token-based**, not section-aware: the input is split on runs
of ASCII space/tab and every token is offered to each token recognizer
independently. A token that matches a recognized shape fills its value; every
other token is ignored. Later recognized tokens of the same kind overwrite
earlier ones, and `ceiling_ft` keeps the minimum. This is what makes real
reports decodable despite remarks, trend groups, RVR and other extensions
(section 9 lists the limits of that approach).

## 2. Data model

```xi
pub type Metar = {
  station: Str;        // first token, verbatim (four ASCII letters)
  day: Int;            // 1-31, or -1
  hour: Int;           // 0-23, or -1
  minute: Int;         // 0-59, or -1
  wind_dir_deg: Int;   // 0-360, -1 = variable (VRB) or missing
  wind_speed_kt: Int;  // knots, or -1
  wind_gust_kt: Int;   // knots, or -1
  visibility_m: Int;   // meters, or -1
  temp_c: Int;         // degrees Celsius, or -1
  dewpoint_c: Int;     // degrees Celsius, or -1
  altimeter_hpa: Int;  // hectopascals, or -1
  ceiling_ft: Int;     // feet AGL, or -1
}
```

## 3. Token grammar

Tokenization: runs of ASCII space (32) or tab (9) separate tokens; leading and
trailing whitespace is dropped. An input with no token at all is an error
(section 7); an input whose first token is not a station is an error; all
later tokens are optional and order-independent.

| Token | Shape | Meaning |
|---|---|---|
| station | exactly 4 bytes in `[A-Za-z]` | stored verbatim; must be the first token |
| time | `DDHHMMZ` (7 bytes, trailing `Z`) | day 1-31, hour 0-23, minute 0-59 |
| wind | `dddssKT` (7 bytes) | `ddd` 0-360, `ss` exactly 2 digits |
| wind gust | `dddssGggKT` (10 bytes) | as wind plus a 2-digit gust |
| variable wind | `VRBssKT` (7 bytes) | direction stored as -1, speed as reported |
| metric visibility | `dddd` (exactly 4 digits) | meters, 0000-9999 |
| CAVOK | `CAVOK` | visibility 10000 m and `ceiling_ft = -1` |
| statute miles | 1-4 digits + `SM` (3-7 bytes) | `n * 1609` meters |
| cloud layer | `FEW`/`SCT`/`BKN`/`OVC` + 3 digits (6 bytes) | hundreds of feet; `BKN`/`OVC` form a ceiling candidate |
| temp/dewpoint | one `/`, each side empty or `M` + 1-2 digits | degrees Celsius; empty side = -1 |
| altimeter | `Q` + 4 digits, or `A` + 4 digits (5 bytes) | `Q` = hPa as-is; `A` = hundredths of inHg converted |

Rules per kind:

1. **Time** -- all six leading bytes must be digits and the ranges must hold;
   otherwise the token is ignored entirely (`321200Z`, `121260Z`, `1250Z`,
   `121150` without `Z` all leave day/hour/minute at -1).
2. **Wind** -- the direction must be 0-360; an out-of-range direction
   (`36112KT`) makes the whole token unrecognized, so neither direction nor
   speed is taken. `VRB` sets the direction to -1. Speeds and gusts are
   exactly two digits; gust >= speed is not required or checked.
3. **Visibility** -- `CAVOK` is matched as an exact string and additionally
   clears the ceiling. Otherwise, a `SM` suffix (1-4 digits) yields
   `miles * 1609` (e.g. `1SM` -> 1609, `10SM` -> 16090, `0SM` -> 0); when the
   bytes before `SM` are not all digits (`P6SM`) the token is ignored. A token
   of exactly four digits is meters (`9999` -> 9999, `0750` -> 750, `0000` ->
   0). A 4-digit token is always visibility: bare trend numbers such as
   `BECMG 3000` are decoded like any other `dddd` token.
4. **Clouds** -- the prefix must be one of `FEW`, `SCT`, `BKN`, `OVC` and the
   height exactly three digits; `FEW`/`SCT` never affect the ceiling, while
   each valid `BKN`/`OVC` token contributes `nnn * 100` ft and the **lowest**
   candidate is kept (`BKN005 OVC012` -> 500; `OVC000` -> 0). Suffixed layers
   (`FEW020TCU`) and vertical visibility (`VV///`) are ignored.
5. **Temperature/dewpoint** -- exactly one `/`; each side is empty (missing,
   -1) or an optional `M` followed by one or two digits. `M` means negative,
   so `M05/M10` -> (-5, -10) and `M00/M02` -> (0, -2); `18/` -> (18, -1);
   `/12` -> (-1, 12). A side with three or more digits (`123/45`) makes the
   whole token unrecognized.
6. **Altimeter** -- `Q0998` -> 998 hPa. `A2992` -> `2992 * 3386 / 10000`
   (truncated) = 1013 hPa; `A3005` -> 1017 hPa. A bare `2992` is not an
   altimeter (and, at four digits, it is decoded as visibility instead).

## 4. Conversions

| From | To | Formula | Example |
|---|---|---|---|
| statute miles | meters | `miles * 1609` (truncating; integer miles only) | `10SM` -> 16090 m |
| inHg hundredths (`A` group) | hPa | `value * 3386 / 10000`, truncated | `A2992` -> 1013 |
| CAVOK | visibility | constant 10000 m | `CAVOK` -> 10000 m |
| cloud hundreds of feet | feet AGL | `nnn * 100` | `BKN005` -> 500 ft |

## 5. Flight category

`metar_flight_category` applies both rules and keeps the **most restrictive**
result. A missing visibility or ceiling (`-1`) imposes no restriction, so an
observation that carries neither is `VFR`.

| Category | Visibility | Ceiling |
|---|---|---|
| `LIFR` | `< 1600` m | `< 500` ft |
| `IFR` | `< 4800` m | `< 1000` ft |
| `MVFR` | `< 8000` m | `< 3000` ft |
| `VFR` | `>= 8000` m | `>= 3000` ft |

Boundary examples (pinned by the suite): 1599/1600, 4799/4800, 7999/8000 m and
400/500, 900/1000, 2900/3000 ft.

## 6. Missing values (`-1`)

Every numeric field is `-1` when the report did not carry a recognized token
for it. Two consequences are part of the contract:

1. **`wind_dir_deg = -1`** means variable (`VRB`) or missing; the two are
   told apart by `wind_speed_kt` -- a recognized wind token always sets both,
   so a non-negative speed with `-1` direction is `VRB`.
2. **A genuine `-1` degC** temperature or dewpoint is indistinguishable from
   "not reported". The summary renders `-1` as `///`; all other negative
   values render as signed integers (`-5`). This is a deliberate trade-off:
   missing must not be printed as a real reading, and the collision only
   affects exactly -1 degC.

`metar_summary` renders missing pieces as follows: unknown direction `///`,
unknown speed `///`, variable direction `VRB`, unknown visibility `///`
(without the `m` suffix), unknown temp or dew `///`, unknown altimeter `Q///`.

## 7. Error catalog

Only two conditions are errors; every other irregularity degrades to ignored
tokens and `-1` fields.

| Condition | Message |
|---|---|
| no token at all (empty or whitespace-only input) | `metar: empty observation` |
| first token is not exactly four ASCII letters | `metar: invalid station: <token>` |

## 8. Public API and summary format

```
metar_parse(raw: Str) -> Result[Metar, Str]
metar_flight_category(m: &Metar) -> Str
metar_wind_kt(m: &Metar) -> Int              // sustained speed (wind_speed_kt)
metar_temperature_c(m: &Metar) -> Int        // temp_c
metar_summary(m: &Metar) -> Str
```

`metar_summary` returns exactly:

```
<station> <dir>/<kt>kt vis=<vis>m <temp>/<dew> Q<hpa> <category>
```

where `<dir>` is three-digit zero-padded (`000`, `045`, `240`), `VRB` for a
variable direction, or `///`; `<kt>` is the sustained speed or `///`; `<vis>`
is the meter value with an `m` suffix, or `///`; `<temp>`/`<dew>` are signed
integers with `-1` rendered as `///`; `<hpa>` is the altimeter value or `///`
(prefixed by `Q`); `<category>` always appears.

Examples (pinned by the suite):

- `EGLL 121150Z 24012KT 9999 SCT020 18/12 Q1013` ->
  `EGLL 240/12kt vis=9999m 18/12 Q1013 VFR`
- `EGLL 24012KT` -> `EGLL 240/12kt vis=/// /////// Q/// VFR`

Complexity: `metar_parse` is `O(len(raw))` plus `O(1)` per token; the other
functions are `O(1)`.

## 9. Non-goals and limitations

- **One observation per call**: no report assembly, no `METAR`/`SPECI` prefix
  handling, no multi-report or multi-line input.
- **No TAF, no trend/remark decoding**: `RMK ...` contents, `NOSIG`, and
  `BECMG`/`TEMPO` semantics are not interpreted. Because decoding is
  token-based, a trend token that has a recognized value shape (`BECMG 3000`)
  is applied as a normal token; later tokens win.
- **No present-weather or RVR decoding**: `RA`, `+TSRA`, `R06L/2000`,
  `240V300` and similar groups are ignored.
- **No fractional or `P`-prefixed SM**: `1 1/2SM` and `P6SM` are ignored.
- **Fixed token widths**: no `VRBssGggKT`, no 3-digit speeds/gusts, no cloud
  type suffixes (`FEW020TCU`), no `VV///`.
- **No validation beyond the catalog**: altimeter and cloud heights are taken
  as reported; a `Q9999` is accepted.
- **`-1` sentinel**: see section 6.
- **No timezone/date arithmetic**: day/hour/minute are stored as reported,
  with no month/year context.

## 10. Test plan (`tests/test_conformance.xi`, 20 checks)

| # | Name | Expectation |
|---|---|---|
| t1 | EGLL sample fills every field and pins the summary | all 12 fields, both accessors, category, exact summary |
| t2 | negative temps, 15SM and A2992 -> 1013 hPa | `M05/M10`, 15SM -> 24135 m, `A2992` -> 1013, pinned summary |
| t3 | gust token records speed and gust; wind_kt is sustained | `24012G25KT` -> speed 12, gust 25, `metar_wind_kt` 12 |
| t4 | VRB wind has direction -1 and renders as VRB | speed 3, pinned `VRB/3kt` summary |
| t5 | CAVOK is 10000 m visibility and an open ceiling | visibility 10000, ceiling -1, VFR, pinned summary |
| t6 | statute-mile visibility converts at 1609 m/SM | 10SM -> 16090, 1SM -> 1609, 0SM -> 0, A3005 -> 1017 |
| t7 | Q is hPa as-is; A is hundredths of inHg truncated to hPa | Q0998 -> 998, A2992 -> 1013, Q1013 -> 1013, A3005 -> 1017, bare 2992 ignored |
| t8 | ceiling is the lowest BKN/OVC layer; FEW/SCT never count | BKN005 OVC012 -> 500, order-independent, FEW/SCT only -> -1, BKN000 -> 0 |
| t9 | visibility category boundaries 1600/4800/8000 m | 1599 LIFR, 1600 IFR, 4799 IFR, 4800 MVFR, 7999 MVFR, 8000 VFR |
| t10 | ceiling category boundaries 500/1000/3000 ft | 400 LIFR, 500 IFR, 900 IFR, 1000 MVFR, 2900 MVFR, 3000 VFR |
| t11 | the most restrictive of visibility and ceiling wins | four combinations plus station+time only -> VFR |
| t12 | values the report omits are -1 and render as /// | time/vis/temp/dew/alt/ceiling -1, VFR, pinned missing summary |
| t13 | station is exactly four letters (either case), stored verbatim | `EGLL`, `egll`, station-only input; 3/5 letters, digits rejected |
| t14 | empty input and bad station produce the documented errors | empty, spaces, tab/space; three exact `invalid station` messages |
| t15 | unknown tokens (remarks, trends, RVR, suffixed clouds) are ignored | `RMK ... T01800120` parses to the canonical sample; `FEW020TCU`, `P6SM`, `R06L/2000` ignored |
| t16 | 4-digit meters accepted exactly; 5 digits is not a visibility | 0000/0750/2400/9999 accepted, 12000 ignored |
| t17 | calm, gust and 360 deg accepted; 361 and missing KT ignored | `00000KT`, `09010G20KT`, `36015KT`; `36112KT` and `24012G25` ignored entirely |
| t18 | M-prefixed and missing temp/dew sides decode as documented | `M05/M10`, `M00/M02`, `M5/M10`, `18/`, `/12`, `123/45` ignored |
| t19 | DDHHMMZ requires valid ranges; malformed time is ignored | 121150Z, 011200Z, 311223Z accepted; day 32, minute 60, no Z, short token ignored |
| t20 | a later recognized token of a kind overwrites the earlier one | second wind, second altimeter, second visibility; pinned summary |

Every test folds its sub-checks into one `assert(cond, name)` and `main`
returns the number of failing checks (0 = green). `port.ps1` must end
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## 11. Compiler / stdlib notes (XIOM v0.61.3)

- Free functions only; no `self` methods, no lambdas, no `Vec[StructType]`
  (the module allocates only `Vec[Str]` for the token split).
- `Ok`/`Err` are constructed only in the leaf helpers `_ok_metar` /
  `_err_metar`; the `Metar` value is built by `_make_metar` (constructing a
  `Result` inline in a function that returns a struct miscompiles).
- All `Str` equality routes through `xiom.string.compare.str_compare`
  (BUG 17: `==` on a `Str` read from a `Vec[Str]` element lowers to a pointer
  comparison); the only equality test in the module is the `CAVOK` check.
- `xiom.string.byte_at` results are widened with `as Int` before arithmetic;
  byte classification compares against `UInt8` constants.
- Matches over `Result`/`Option` are exhaustive (`Ok`/`Err`, `Some`/`None`);
  no `mut` patterns.
- `use` statements end with `;`; `module` does not.
