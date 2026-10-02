# xiom.aviation

> **Status:** `incubating` -- conformance-tested (21/21); published at `v0.1.2` on the XIOM registry.
> **Scope:** pure-XIOM (no FFI) bit-oriented codec for Mode S / ADS-B
> downlink frames: 56-bit (7-byte) and 112-bit (14-byte) frame intake, DF
> classification, ICAO address extraction, extended-squitter ME decoding by
> type code, altitude decoders and CPR position helpers. No RF/PHY, no
> demodulation, no parity verification.
> **Deps:** `xiom.std` only. The library module uses `xiom.string`; the
> tests use `xiom.test`, `xiom.io`, `xiom.string` and `xiom.string.compare`.

## What it is

`xiom.aviation` turns raw Mode S frame bytes -- the 7- or 14-byte frames a
1090 MHz receiver hands to software -- into decoded values:

```
[DF 5 bits][CA/FS/CF 3 bits][24-bit address][56-bit ME/MB][24-bit parity]
```

`aviation_parse_frame` reads the DF field first, derives the frame length
from it (short formats 0/4/5/11 are 7 bytes, long formats 16/17/18/19/20/21/24
are 14 bytes), extracts the address field and keeps the 56-bit payload and
the parity bytes raw. Reserved DFs and buffers that do not hold a whole
frame are rejected with stable error strings; a buffer may hold more than
one frame (`consumed` reports the frame length).

For DF17/DF18 extended squitters the ME payload is decoded by type code:
identification (TC 1-4, callsign + category), surface position (TC 5-8,
movement/track/CPR), airborne position (TC 9-18 barometric, TC 20-22 GNSS
height), airborne velocity (TC 19, ground speed or airspeed + heading,
vertical rate, GNSS/baro difference), aircraft status / emergency (TC 28),
target state (TC 29) and operational status (TC 31, version/NIC/NACp/SIL).
Type codes without a decoder (0, 23-27, 30) are not an error: the frame
parses, the TC is reported and the raw 56-bit payload stays available.

Altitude decoding implements the binary 25 ft encoding selected by the Q
bit, for both the 12-bit ADS-B field (`aviation_ac12_altitude_ft`) and the
13-bit Mode S AC field (`aviation_ac13_altitude_ft`). The Gillham/Gray
coded (Q=0) and metric (M=1) subsets are documented in `SPEC.md` but
deliberately return an error instead of a guessed value.

CPR position decoding is pure integer math (no floating point, no
trigonometry): `aviation_cpr_nl` (the 58 boundary latitudes), pack/unpack
helpers, `aviation_cpr_decode_local` against a reference position and
`aviation_cpr_decode_global` from an even/odd frame pair. Positions are
`Int`s in units of 10^-5 degrees. The hemisphere rule and the frame-order
choice are documented boundaries (caller-side), see `SPEC.md` section 6.

## API

| Function | Returns | Description |
|---|---|---|
| `aviation_version()` | `Str` | Library version. |
| `aviation_bit(data, off)` | `Result[Int, Str]` | Bit at MSB-first absolute offset. |
| `aviation_bits(data, start, len)` | `Result[Int, Str]` | Unsigned field of up to 56 bits. |
| `aviation_df_length(df)` | `Int` | Encoded length 7/14, or -1 reserved. |
| `aviation_df_name(df)` | `Str` | Human-readable downlink format name. |
| `aviation_parse_frame(data)` | `Result[AviationFrame, Str]` | Parse one frame; `consumed` bytes. |
| `aviation_frame_*` | `Int` | bytes, bits, df, ca, icao, payload, parity, tc, consumed. |
| `aviation_tc_name(tc)` | `Str` | Type-code name/range for 0..31. |
| `aviation_callsign_char(code)` | `Str` | 6-bit identification charset character. |
| `aviation_ident_decode(f)` | `Result[AviationIdent, Str]` | TC 1-4 identification. |
| `aviation_ident_*` | `Int`/`Str` | tc, category, callsign, callsign_trim. |
| `aviation_movement_k8(mov)` | `Int` | Surface movement, eighths of a knot. |
| `aviation_track_deg100(trk)` | `Int` | Ground track, hundredths of a degree. |
| `aviation_surface_decode(f)` | `Result[AviationSurface, Str]` | TC 5-8 surface position. |
| `aviation_surface_*` | `Int` | tc, movement, speed_k8, track_*, time_flag, odd, cpr_lat, cpr_lon. |
| `aviation_position_decode(f)` | `Result[AviationPosition, Str]` | TC 9-18 / 20-22 position. |
| `aviation_position_*` | `Int` | tc, ss, saf, alt_raw, alt_ft, gnss_m, time_flag, odd, cpr_lat, cpr_lon. |
| `aviation_velocity_decode(f)` | `Result[AviationVelocity, Str]` | TC 19 velocity. |
| `aviation_velocity_*` | `Int` | subtype, nac_v, ew_*, ns_*, gs_kt, heading_*, airspeed_*, vr_*, dif_ft. |
| `aviation_emergency_decode(f)` | `Result[AviationEmergency, Str]` | TC 28 status. |
| `aviation_emergency_state_name(state)` | `Str` | Emergency state table. |
| `aviation_target_state_decode(f)` | `Result[AviationTargetState, Str]` | TC 29 subtype 1. |
| `aviation_op_status_decode(f)` | `Result[AviationOpStatus, Str]` | TC 31 subtype 0. |
| `aviation_baro_hpa10(raw9)` | `Int` | TC29 pressure in tenths of hPa. |
| `aviation_selected_heading_deg100(raw9)` | `Int` | TC29 selected heading. |
| `aviation_ac12_qbit(v)` / `aviation_ac12_altitude_ft(v)` | `Int` / `Result[Int, Str]` | 12-bit ADS-B altitude. |
| `aviation_ac13_metric_flag(v)` / `aviation_ac13_qbit(v)` / `aviation_ac13_altitude_ft(v)` | `Int` / `Result[Int, Str]` | 13-bit Mode S altitude. |
| `aviation_gnss_altitude_m(v)` / `aviation_gnss_altitude_ft(v)` | `Int` | TC 20-22 GNSS height. |
| `aviation_cpr_nl(lat_scaled)` | `Int` | CPR NL (1..59) at degrees x 100000. |
| `aviation_cpr_pack(lat, lon)` / `_pack_lat` / `_pack_lon` | `Int` | CPR pair packing. |
| `aviation_cpr_decode_local(odd, even, latest_odd, ref_lat, ref_lon)` | `Result[AviationFix, Str]` | Local CPR fix. |
| `aviation_cpr_decode_global(even, odd, latest_odd)` | `Result[AviationFix, Str]` | Global CPR fix. |
| `aviation_fix_lat` / `_lon` / `_nl` / `_odd` | `Int` | Decoded fix fields. |

## Usage

```xi
use xiom.aviation;
use xiom.io;

fn main() -> Int {
  var frame = Vec[UInt8].new();
  // ... fill `frame` with one 7- or 14-byte Mode S frame ...
  let parsed = aviation_parse_frame(&frame);
  if !parsed.is_ok {
    io.println("parse error: " + parsed.error);
    return 1;
  }
  let f: AviationFrame = parsed.value;
  io.println(aviation_df_name(aviation_frame_df(&f)));

  if aviation_frame_tc(&f) == 11 {
    let pr = aviation_position_decode(&f);
    if pr.is_ok {
      let p: AviationPosition = pr.value;
      // aviation_position_alt_ft(&p) == 38000 (feet; -1 when not a Q=1 code)
      // aviation_position_cpr_lat(&p) / ..._cpr_lon(&p) -> CPR helpers below
    }
  }

  // Even/odd pair -> global position (units of 10^-5 degrees):
  let even = aviation_cpr_pack(93000, 51372);
  let odd = aviation_cpr_pack(74158, 50194);
  let fix = aviation_cpr_decode_global(even, odd, 0);
  if fix.is_ok {
    let x: AviationFix = fix.value;
    // aviation_fix_lat(&x) == 5225720  (52.25720 N)
    // aviation_fix_lon(&x) == 391937   (3.91937 E)
    // aviation_fix_nl(&x)  == 36
  }
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.aviation
```

Expected: the namespace check passes, 21 `[PASS]` lines and a final
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No RF/PHY.** Demodulation, bit/timing recovery and serial framing are
  out of scope; callers hand in complete frame bytes.
- **No parity verification.** AP/PI/DP bytes are returned raw. DF11
  overlays the interrogator code, so verification cannot be local anyway.
- **Documented altitude subsets.** Q=0 Gillham/Gray-coded and M=1 metric
  altitudes return errors rather than values (see `SPEC.md` section 5).
- **TC29 selected altitude is raw.** Its M/Q sub-encoding is not
  interpreted. TC29 subtypes other than 1 and TC31 subtypes other than 0
  are rejected.
- **DF19 / Comm-B payloads are raw.** DF20/21 MB and DF19 MV are preserved
  but not decoded.
- **CPR is a solver, not a tracker.** No time filtering, no outlier
  rejection, no single-frame (memory) decoding; the hemisphere rule and
  frame-order choice are documented caller-side boundaries.
- **Integer-only position precision.** 10^-5 degree output (about 1.1 m);
  NL comparisons use the standard table at 10^-7 degree resolution.
- **Not thread-safe by design, but immutable:** all values are plain
  structs and `Vec`s; nothing global or mutable is shared.
- **In-memory buffers.** All decode functions take `&Vec[UInt8]` or
  plain `Int`s; nothing allocates except the returned structs/strings.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
