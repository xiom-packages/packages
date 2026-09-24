# xiom.nmea -- specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.nmea` (`src/nmea.xi`). Pure XIOM, no FFI.

## 1. Scope and model

Parse NMEA 0183 sentence text into plain values:

- `nmea_compute_checksum`, `nmea_checksum_ok` -- checksum arithmetic,
- `nmea_sentence_type`, `nmea_fields`, `nmea_field`, `nmea_field_count` --
  sentence structure,
- `nmea_dm_to_micro_deg` -- coordinate conversion to micro-degrees,
- `nmea_gga_quality`, `nmea_gga_satellites`, `nmea_gga_altitude_cm` --
  GGA accessors,
- `nmea_rmc_valid` -- RMC data validity.

Parsing is **stateless and byte-oriented**: nothing allocates a sentence
object, every function rescans its input, and malformed text yields an empty
value or a documented `Err`, never a crash. All arithmetic is 64-bit signed
integer arithmetic; there is no floating point, no locale, no I/O and no
global state.

## 2. Sentence grammar

```
sentence := start body [ '*' hex hex ] tail
start    := '$' | '!'
body     := type ',' payload
type     := bytes up to the first ','
payload  := fields separated by single ','; fields may be empty
```

- The **start delimiter** is the first `'$'` (36) or `'!'` (33) anywhere in
  the string. Leading garbage before it is ignored; a string with neither is
  malformed.
- The **body** is the byte run after the start delimiter, up to the first
  `'*'` that follows it (or up to the end of the string when there is no
  `'*'`). A `'*'` before the first `','` makes the type malformed.
- The **type** is the text between the start delimiter and the first `','`
  after it, returned verbatim (case preserved). `"$GPGGA*47"` has no `','`,
  so its type is malformed (`""`).
- The **payload** is everything after that first `','`, up to the first `'*'`
  after it (or the end). It is split on single `','` bytes; empty fields are
  kept. `"a,,b,"` has four fields: `"a"`, `""`, `"b"`, `""`.
- **Field numbering in this document** counts the sentence type as field 0:
  `$GPGGA,time,lat,N,...` has field 1 = time. The API counts fields **after**
  the type (`nmea_field(s, i)` with `i = document_field - 1`), so a table row
  for "field 6" is `nmea_field(s, 5)`.
- No CR/LF or whitespace handling is applied: bytes after the checksum digits
  are simply ignored. A sentence without `'*'` has its fields parsed to the
  end of the string.

## 3. Checksum

The checksum is the XOR of every payload byte (the bytes after the start
delimiter up to the `'*'`, excluded), each byte widened to `Int`. The result
is an integer 0-255.

- `nmea_compute_checksum(s)` returns that value, or `0` when the string
  contains no `'$'`/`'!'` ("absent"); a payload whose XOR genuinely is 0 also
  returns 0, so the two cases are not distinguishable by the return value.
- `nmea_checksum_ok(s)` requires a start delimiter, a `'*'` after it, and two
  hex digits (either case, `0-9A-Fa-f`) immediately after that `'*'`. It
  recomputes the checksum and compares it with those two digits as an
  integer; anything after the two digits is ignored. Missing start, missing
  `'*'`, a short suffix, a non-hex suffix and a mismatched value all return
  `false` (there is no error type on this function).

Known fixtures (used by the tests):

| Sentence | XOR |
|---|---|
| `$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47` | `0x47` = 71 |
| `$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A` | `0x6A` = 106 |
| `!AIVDM,1,1,,A,13HOI:0P0000VOHLCnHQKwvL05Ip,0*23` | `0x23` = 35 |

## 4. Field table (standard GGA / RMC)

Document field numbers count the type as field 0; the API index is one less.

| Doc field | GGA (API index `nmea_field(s, i)`) | RMC (API index) |
|---|---|---|
| 1 | UTC time (`i = 0`) | UTC time (`i = 0`) |
| 2 | latitude `ddmm.mmmm` (`i = 1`) | status `A`/`V` (`i = 1`) |
| 3 | N/S (`i = 2`) | latitude (`i = 2`) |
| 4 | longitude `dddmm.mmmm` (`i = 3`) | N/S (`i = 3`) |
| 5 | E/W (`i = 4`) | longitude (`i = 4`) |
| 6 | fix quality (`i = 5`) | E/W (`i = 5`) |
| 7 | satellites used (`i = 6`) | speed over ground (`i = 6`) |
| 8 | HDOP (`i = 7`) | track made good (`i = 7`) |
| 9 | altitude meters (`i = 8`) | date (`i = 8`) |
| 10 | `M` (i = 9) | magnetic variation (`i = 9`) |
| 11 | geoidal separation (`i = 10`) | variation E/W (`i = 10`) |
| 12 | `M` (`i = 11`) | -- |
| 13 | age of differential (`i = 12`) | -- |
| 14 | differential station id (`i = 13`) | -- |

## 5. Coordinate conversion (`nmea_dm_to_micro_deg`)

Input: `value` in `"ddmm.mmmm"` (latitude) or `"dddmm.mmmm"` (longitude)
form, `hemi` one of `N`, `S`, `E`, `W` (either case, exactly one byte).

Grammar of `value`:

- 4 or 5 ASCII digits for the integer part; the last two are whole minutes
  and must be `00`-`59`; the leading 2 or 3 digits are degrees.
- optionally `'.'` followed by one or more ASCII digits (fraction of a
  minute). A trailing `'.'` with no digits is accepted as zero fraction.
- No sign byte: the hemisphere carries the sign.

Scaling:

```
minutes_scaled = minutes * 10000 + first four fraction digits (zero-padded)
micro = degrees * 1_000_000 + (minutes_scaled * 5) / 3
```

The `/ 3` truncates toward zero. Fraction digits past the fourth are
validated but dropped, so they never affect the result. `N`/`E` return the
positive value, `S`/`W` its negation; `-0` cannot occur (a zero value is
returned as `0`).

Pinned examples:

| value | hemi | micro-degrees |
|---|---|---|
| `6011.000` | N | 60183333 |
| `02431.000` | E | 24516666 |
| `4807.038` | N | 48117300 |
| `6011` | N | 60183333 (trailing fraction may be omitted) |
| `6011.000` | S | -60183333 |
| `02431.000` | W | -24516666 |
| `6011.9` | N | 60198333 (short fraction is zero-padded) |
| `6011.99999` | N | 60199998 (past the fourth digit: truncated) |

Errors: value errors are reported before hemisphere errors (see section 8).

## 6. GGA accessors

Each GGA accessor first checks that the sentence type ends with `GGA`
(ignoring case), so `GPGGA`, `GNGGA`, `GLGGA`, ... all qualify; otherwise it
returns `Err("nmea: not a GGA sentence")`.

| Function | Doc field | API index | Returns |
|---|---|---|---|
| `nmea_gga_quality` | 6 | 5 | `Ok(quality)` for a non-empty run of ASCII digits; no range check (`0` = no fix, `1` = GPS, `2` = DGPS, ...). |
| `nmea_gga_satellites` | 7 | 6 | `Ok(count)` for a non-empty run of ASCII digits. |
| `nmea_gga_altitude_cm` | 9 | 8 | `Ok(centimeters)`. |

Altitude grammar: an optional `'+'` or `'-'`, then ASCII digits, optionally
`'.'` followed by digits. `centimeters = int_meters * 100 + first two
fraction digits (zero-padded)`; further fraction digits are truncated toward
zero and the sign applies to the whole value.

Pinned examples: `"545.4"` -> `54540`; `"-10.5"` -> `-1050`;
`"0.0"` -> `0`; `"545.456"` -> `54545` (truncated); `"545"` -> `54500`.

## 7. RMC accessor (`nmea_rmc_valid`)

The type must end with `RMC` (ignoring case). Doc field 2 (API index 1) is
the data status:

| Field | Result |
|---|---|
| `A` / `a` | `Ok(true)` -- valid |
| `V` / `v` | `Ok(false)` -- void |
| empty / absent | `Err("nmea: missing RMC status")` |
| anything else (including multi-byte values) | `Err("nmea: invalid RMC status: <field>")` |

Non-RMC sentences yield `Err("nmea: not an RMC sentence")`.

## 8. Error catalog

All `Err` payloads start with `nmea: ` and quote the offending field text
verbatim.

| Message | Function | Trigger |
|---|---|---|
| `nmea: empty coordinate` | `nmea_dm_to_micro_deg` | `value` is `""` (checked before the hemisphere). |
| `nmea: invalid coordinate: <value>` | `nmea_dm_to_micro_deg` | integer part not 4/5 digits, non-digit byte, a second `'.'`, minutes 60-99, or a non-digit fraction byte. |
| `nmea: invalid hemisphere: <hemi>` | `nmea_dm_to_micro_deg` | `hemi` is not exactly one of `N/S/E/W` (either case). |
| `nmea: not a GGA sentence` | GGA accessors | the sentence type is missing or does not end with `GGA`. |
| `nmea: missing GGA quality` | `nmea_gga_quality` | field 6 empty or absent. |
| `nmea: invalid GGA quality: <field>` | `nmea_gga_quality` | field 6 present but not all ASCII digits. |
| `nmea: missing GGA satellites` | `nmea_gga_satellites` | field 7 empty or absent. |
| `nmea: invalid GGA satellites: <field>` | `nmea_gga_satellites` | field 7 present but not all ASCII digits. |
| `nmea: missing GGA altitude` | `nmea_gga_altitude_cm` | field 9 empty or absent. |
| `nmea: invalid GGA altitude: <field>` | `nmea_gga_altitude_cm` | no digit, a second `'.'`, or an unexpected byte. |
| `nmea: GGA altitude too large` | `nmea_gga_altitude_cm` | magnitude would not fit the 64-bit signed range. |
| `nmea: not an RMC sentence` | `nmea_rmc_valid` | the sentence type is missing or does not end with `RMC`. |
| `nmea: missing RMC status` | `nmea_rmc_valid` | field 2 empty or absent. |
| `nmea: invalid RMC status: <field>` | `nmea_rmc_valid` | field 2 present but not a single `A`/`a`/`V`/`v`. |

## 9. Non-goals and limitations

- **No tag block** (`\...*hh\`) and no multi-sentence reassembly.
- **No sentence emission, no re-checksumming** -- parsing only.
- **No GSA/GSV/VTG (or any other) typed accessors;** use
  `nmea_sentence_type`/`nmea_fields` for those, or wait for follow-up
  packages.
- **No checksum enforcement:** `nmea_fields` and the accessors do not consult
  `nmea_checksum_ok`; callers that require integrity must check it first.
- **ASCII only:** the parser is byte-oriented; multi-byte UTF-8 is never
  decoded and never accepted as a digit.
- **No whitespace trimming:** fields are returned exactly as they appear;
  `" 1"` is not `"1"`.
- **Truncation, not rounding:** both the coordinate and altitude conversions
  truncate (see sections 5 and 6).
- **No timing/units/date logic:** UTC time, dates, speeds and courses are
  only exposed as text fields.

## 10. Test plan (`tests/test_conformance.xi`, 24 checks)

| # | Check |
|---|---|
| 1 | GPGGA fixture: type `GPGGA`, 14 fields, all field values, checksum 0x47. |
| 2 | GPRMC fixture: type `GPRMC`, 11 fields, all field values, checksum 0x6A. |
| 3 | Checksum fails on a flipped payload byte (`GPGGB`) and a flipped digit (`*48`). |
| 4 | Checksum accepts lower-case hex; rejects `*6G`, `*6` and a bare `*`. |
| 5 | `nmea_compute_checksum` pins (71, 106, 35, 85) and the absent-start `0`. |
| 6 | Sentence type extraction, including `""` for no start, no comma and `$GPGGA*47`. |
| 7 | Empty fields are preserved by the split (`a,,1,,2,` -> five fields). |
| 8 | Out-of-range and negative field indexes return `""`; malformed input has 0 fields. |
| 9 | Missing checksum is `false` but type/fields still parse; CRLF after the suffix is ignored. |
| 10 | dm pins: `6011.000 N` -> 60183333, `02431.000 E` -> 24516666, `4807.038 N` -> 48117300, dot-less forms. |
| 11 | dm S/W negatives; lower-case hemispheres accepted. |
| 12 | dm fraction scaling and truncation past the fourth digit. |
| 13 | dm value errors: empty, wrong width, non-digit, minutes 60-99, second dot, bad fraction. |
| 14 | dm hemisphere errors: empty, `X`, `NS`, `north`. |
| 15 | GGA quality: 1, 0, missing, invalid `x2`, wrong sentence type. |
| 16 | GGA satellites: 8, 12, missing, invalid `x2`, wrong sentence type. |
| 17 | GGA altitude: 54540, 54540 (quality-0 sentence), -1050, 54545 truncated, missing, `.`, `abc`, wrong type. |
| 18 | RMC status: `A` -> true, `V` -> false, `a` -> true, missing, invalid `X`, wrong type. |
| 19 | Empty input is inert for every entry point. |
| 20 | Malformed sentences (embedded `*`, bare trailing `*`, missing start) do not trap. |
| 21 | AIS `!` sentence: type `AIVDM`, six fields (one empty), checksum 0x23. |
| 22 | Accessors reject the wrong sentence type with the documented error. |
| 23 | Lower-case type (`$gpgga`) still satisfies the GGA accessors. |
| 24 | Checksum digits are not part of the last field. |

## 11. Compiler / stdlib notes (XIOM v0.61.3)

Written under the same constraints as its sibling packages:

- free functions only -- no self methods, no lambdas, no `Vec[StructType]`,
  no `Vec[fn]` dispatch, no `Vec[Float64]`;
- `Str` values are never compared with `==` (BUG 17: `==` on a `Str` read
  from a `Vec[Str]` element lowers to a pointer comparison); all decisions
  are made on `UInt8` values, and the tests route every text comparison
  through `xiom.string.compare.str_compare`;
- `Vec[Str]` element reads are bound with a typed `let` before use;
- `string.byte_at` results are widened with `as Int` before arithmetic;
- `Ok`/`Err` are constructed only in the four tiny leaf helpers
  (`_ok_int`, `_err_int`, `_ok_bool`, `_err_bool`) because constructing a
  `Result` inside a larger function miscompiles;
- `match` is not used in the library; the tests use the compiler-tested
  helpers that read `Result` directly through `.is_ok`/`.value`/`.error`.
