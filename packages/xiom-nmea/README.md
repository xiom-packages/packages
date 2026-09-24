# xiom.nmea

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** parse NMEA 0183 sentences: `$`/`!` delimiters, XOR checksums,
> sentence type, comma-separated fields, degrees/minutes -> micro-degree
> conversion, and the common GGA/RMC accessors (quality, satellites,
> altitude, data validity).
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice` and `xiom.math.bit_xor`). Tests additionally use
> `xiom.test`, `xiom.io` and `xiom.string.compare`.

## Scope

`xiom.nmea` turns raw serial/GPS text such as

```
$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47
$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A
!AIVDM,1,1,,A,13HOI:0P0000VOHLCnHQKwvL05Ip,0*23
```

into plain values: a checksum, a sentence type, a `Vec[Str]` of fields, and
typed accessors for the two sentences most consumers need first (GGA and
RMC). Parsing is byte-oriented and stateless: every function rescans its
input, so there is no sentence object to allocate, retain or invalidate.
All arithmetic is 64-bit integer math; there is no floating point, no I/O
and no global state.

## API

| Function | Returns | Description |
|---|---|---|
| `nmea_compute_checksum(s)` | `Int` | XOR of the payload bytes after the first `$`/`!` up to `*` (or end); `0` when there is no `$`/`!`. |
| `nmea_checksum_ok(s)` | `Bool` | Parses the two hex digits after `*` and compares them with the recomputed checksum; `false` when missing or invalid. |
| `nmea_sentence_type(s)` | `Str` | Bytes between the start delimiter and the first `,` (e.g. `GPGGA`); `""` when malformed. |
| `nmea_fields(s)` | `Vec[Str]` | Comma-split payload after the type, checksum suffix removed; empty fields kept. |
| `nmea_field(s, i)` | `Str` | Field `i` (0-based after the type); `""` when out of range. |
| `nmea_field_count(s)` | `Int` | Number of payload fields. |
| `nmea_dm_to_micro_deg(value, hemi)` | `Result[Int, Str]` | `"ddmm.mmmm"` -> micro-degrees; N/E positive, S/W negative; `Err("nmea: ...")` on bad input. |
| `nmea_gga_quality(s)` | `Result[Int, Str]` | GGA field 6: fix quality (`0` = no fix). |
| `nmea_gga_satellites(s)` | `Result[Int, Str]` | GGA field 7: satellites used. |
| `nmea_gga_altitude_cm(s)` | `Result[Int, Str]` | GGA field 9: antenna altitude in meters -> centimeters (truncated). |
| `nmea_rmc_valid(s)` | `Result[Bool, Str]` | RMC field 2: `A` -> `true`, `V` -> `false`. |

Field numbers above count the sentence type as field 0, so GGA field 6 is
`nmea_field(s, 5)`, field 7 is `nmea_field(s, 6)` and field 9 is
`nmea_field(s, 8)`. The exact grammar and error catalog are in `SPEC.md`.

## Usage

```xi
use xiom.nmea;
use xiom.io; use xiom.convert;

fn main() -> Int {
  let s = "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47";
  io.println(nmea_sentence_type(s));          // GPGGA
  io.println(nmea_field(s, 1));               // 4807.038
  match nmea_dm_to_micro_deg(nmea_field(s, 1), nmea_field(s, 2)) {
    Ok(micro) => { io.println("lat micro-degrees: " + convert.int_to_string(micro)); },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.nmea
```

Expected tail: 24 `[PASS]` lines, `xiom.nmea: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No sentence emission:** this package only parses; it cannot build or
  re-checksum sentences, and it does not reassemble multi-sentence payloads
  (AIS type 5/24 fragments, `$--GSA` aggregates, ...).
- **No GSA/GSV/VTG/...:** only the GGA and RMC accessors are typed; every
  other sentence is still splittable with `nmea_sentence_type`/`nmea_fields`,
  but no field-level helper exists for them (no VTG speed/course, no GSV
  satellite lists, no GSA DOP/FixType).
- **ASCII only:** `byte_at` reads raw bytes; non-ASCII input is not decoded,
  and a `Str` with multi-byte UTF-8 in place of ASCII digits/letters is
  treated byte-wise (and therefore malformed for the typed accessors).
- **Not a validator:** the only checks are the ones documented in `SPEC.md`:
  `nmea_checksum_ok` verifies the suffix, but the parsers do not require a
  valid checksum, so a sentence with a bad checksum still yields fields. The
  dm/GGA/RMC accessors validate their own field shapes only.
- **Fixed field positions:** GGA and RMC accessors use the standard field
  numbers; proprietary talker extensions that insert fields shift the
  meaning, and are read as-is.
- **Scaled integer truncation:** `nmea_dm_to_micro_deg` truncates the
  minutes division and ignores fraction digits past the fourth;
  `nmea_gga_altitude_cm` truncates past the second fraction digit. No
  rounding is applied anywhere.

See `SPEC.md` for the exact grammar, conversions, error catalog and test
plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
