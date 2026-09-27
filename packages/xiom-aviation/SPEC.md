# xiom.aviation -- specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.aviation` (`src/aviation.xi`). Pure XIOM, no FFI.
Library dependency: `xiom.string` only (`str_slice` for the callsign
charset). All arithmetic is 64-bit signed integer arithmetic; there is no
floating point, no trigonometry, no I/O and no global mutable state.

## 1. Scope and model

Decode Mode S downlink frames and the ADS-B extended-squitter payload they
carry, at the bit level:

- frame intake (`aviation_parse_frame`, `aviation_bit`, `aviation_bits`),
- DF classification (`aviation_df_length`, `aviation_df_name`),
- ME decoding by type code (identification, surface position, airborne
  position, velocity, emergency, target state, operational status),
- altitude decoders (12-bit ADS-B AC, 13-bit Mode S AC),
- CPR position helpers (NL, pack/unpack, local decode, global decode).

No RF/PHY handling: demodulation, pulse shaping, CRC/parity verification and
serial framing are all out of scope. Bytes in, values out. Parity is
preserved raw (DF11 overlays the interrogator code, so verification is
caller-side; DF17/18 address parity likewise).

## 2. Frames

A Mode S frame is 56 bits (7 bytes) or 112 bits (14 bytes). Bit 1 is the
most significant bit of byte 0. Layout of the fields this codec reads:

| Bits | Field | Meaning |
|---|---|---|
| 1-5 | DF | downlink format (0..31) |
| 6-8 | CA / FS / CF | format-dependent 3-bit field, raw |
| 9-32 | ICAO / AA / ... | 24-bit address field, raw |
| 33-88 | ME / MB / MV | 56-bit payload, long frames only |
| last 24 | AP / PI / DP | parity, raw, no verification |

`aviation_parse_frame` reads DF first and derives the length; a buffer that
does not hold a whole frame is rejected, a reserved DF is rejected.

| DF | Encoded length | Name |
|---|---|---|
| 0 | 7 | short air-air surveillance (ACAS) |
| 4 | 7 | surveillance altitude reply |
| 5 | 7 | surveillance identity reply |
| 11 | 7 | all-call reply |
| 16 | 14 | long air-air surveillance (ACAS) |
| 17 | 14 | extended squitter (ADS-B) |
| 18 | 14 | extended squitter (TIS-B / non-transponder) |
| 19 | 14 | military extended squitter |
| 20 | 14 | Comm-B altitude reply |
| 21 | 14 | Comm-B identity reply |
| 24 | 14 | Comm-D extended length message |
| any other | -- | reserved, rejected |

`consumed` equals the frame length; extra bytes in the buffer are ignored
(streaming). The reader is MSB-first and absolute: bit 0 is the MSB of
byte 0, and bit spans up to 56 bits can be read with `aviation_bits`.

## 3. ME payload layouts (56 bits, DF17/DF18)

All ME field descriptions are 1-based inside ME. `TC` is ME bits 1-5 and
`aviation_frame_tc` reports it for DF17/DF18 (DF19 and the Comm-B formats
carry a differently defined top field, so `tc` stays -1 there).

### TC 1-4 -- aircraft identification

| Bits | Field |
|---|---|
| 1-5 | TC |
| 6-8 | category (CA) |
| 9-56 | eight 6-bit characters |

6-bit charset: 1-26 = A-Z, 32 = space, 48-57 = 0-9; code 0 and every other
code decode to `#`. The callsign keeps all eight characters (padding
spaces and `#` preserved); `aviation_ident_callsign_trim` strips trailing
spaces and `#`.

### TC 5-8 -- surface position

| Bits | Field |
|---|---|
| 1-5 | TC |
| 6-12 | MOV movement code |
| 13 | track status |
| 14-20 | TRK ground track |
| 21 | T time flag (0 = UTC) |
| 22 | F odd/even |
| 23-39 | CPR latitude (17 bits) |
| 40-56 | CPR longitude (17 bits) |

Movement decode (`aviation_movement_k8`, speed in eighths of a knot):

| MOV | Speed |
|---|---|
| 0 | no information (-1) |
| 1 | 0 (stopped) |
| 2-8 | (MOV-1) eighths (0.125 kt steps) |
| 9-12 | 8 + 2*(MOV-9) eighths (1 kt + 0.25 kt steps) |
| 13-38 | 16 + 4*(MOV-13) eighths (2 kt + 0.5 kt steps) |
| 39-93 | 120 + 8*(MOV-39) eighths (15 kt + 1 kt steps) |
| 94-108 | 560 + 16*(MOV-94) eighths (70 kt + 2 kt steps) |
| 109-123 | 800 + 40*(MOV-109) eighths (100 kt + 5 kt steps) |
| 124 | 1400 eighths (175 kt) |
| 125-127 | reserved (-2) |

Ground track is TRK * 360/128 degrees; `aviation_track_deg100` returns
hundredths of a degree rounded to nearest.

### TC 9-18 (barometric) and TC 20-22 (GNSS) -- airborne position

| Bits | Field |
|---|---|
| 1-5 | TC |
| 6-7 | SS surveillance status (TC 20-22: reserved) |
| 8 | SAF / NIC supplement B |
| 9-20 | altitude, 12-bit AC |
| 21 | T time flag |
| 22 | F odd/even |
| 23-39 | CPR latitude (17 bits) |
| 40-56 | CPR longitude (17 bits) |

TC 9-18: the AC12 field is decoded with the Q bit (see section 5) into feet
and reported as `alt_ft` (-1 when the field is not a Q=1 code).
TC 20-22: the same 12 bits are the GNSS height above ellipsoid in metres;
reported as `gnss_m` and `alt_ft` is -1.

### TC 19 -- airborne velocity

| Bits | Field |
|---|---|
| 1-5 | TC |
| 6-8 | subtype (1/2 ground speed, 3/4 airspeed) |
| 9 | intent change |
| 10 | IFR capability |
| 11-13 | NACv |
| 14 | EW sign (1 = west) / heading status (3/4) |
| 15-24 | EW velocity (10 bits) / heading (10 bits) |
| 25 | NS sign (1 = south) / airspeed type (0 IAS, 1 TAS) |
| 26-35 | NS velocity (10 bits) / airspeed (10 bits) |
| 36 | vertical rate source (0 GNSS, 1 baro) |
| 37 | vertical rate sign (1 = down) |
| 38-46 | vertical rate (9 bits) |
| 47-48 | reserved |
| 49 | GNSS/baro difference sign (1 = below) |
| 50-56 | GNSS/baro difference (7 bits) |

Velocity components: `raw - 1` knots, raw 0 = no information (-1).
Vertical rate: `(raw - 1) * 64` ft/min with sign, raw 0 = no information.
GNSS/baro difference: `(raw - 1) * 25` ft with sign, raw 0 = no
information. Ground speed is the integer sqrt of EW^2 + NS^2 when both
components are known. Heading for subtypes 3/4 is raw * 360/512 degrees
(`aviation_velocity_heading_deg100`, rounded).

### TC 28 -- aircraft status (emergency / TCAS RA)

| Bits | Field |
|---|---|
| 1-5 | TC |
| 6-8 | subtype (1 = emergency/priority, 2 = TCAS RA) |
| 9-11 | emergency state (subtype 1 only) |

Emergency state: 0 no emergency, 1 general, 2 lifeguard/medical, 3 minimum
fuel, 4 no communications, 5 unlawful interference, 6-7 reserved.
Subtype 2 payloads are not decoded (state = -1).

### TC 29 -- target state and status (subtype 1)

| Bits | Field |
|---|---|
| 1-5 | TC |
| 6-7 | subtype (only 1 is decoded) |
| 8 | SIL supplement |
| 9-19 | selected altitude, returned raw |
| 20-28 | barometric pressure setting (0.8 hPa steps from 800.0) |
| 29 | selected heading status |
| 30-38 | selected heading (360/512 degree steps) |
| 39-42 | NACp |
| 43 | NICbaro |
| 44-45 | SIL |
| 46-47 | mode-bits status |
| 48-53 | autopilot, VNAV, alt hold, approach, TCAS, LNAV |

The selected-altitude field is returned raw: its M/Q sub-encoding is not
interpreted (documented boundary). Subtypes other than 1 are rejected with
`aviation: unsupported target state subtype`.

### TC 31 -- operational status (subtype 0, version-2 layout)

| Bits | Field |
|---|---|
| 1-5 | TC |
| 6-8 | subtype (only 0, airborne, is decoded) |
| 9-24 | airborne capability class, raw |
| 25-40 | operational mode, raw |
| 41-43 | ADS-B version |
| 44 | NIC supplement A |
| 45-48 | NACp |
| 49-50 | GVA (version 2) |
| 51-52 | SIL |

Version 0/1 messages share the version/NIC/NACp positions but use the tail
bits differently; only the version-2 tail is documented here. Subtype 1
(surface) has a different payload and is rejected with
`aviation: unsupported operational status subtype`.

## 4. Type codes not decoded

TC 0 (no position information), TC 23-27 and TC 30 (reserved) are named by
`aviation_tc_name` but have no decoder. A frame with an unsupported TC is
never rejected by `aviation_parse_frame`: it parses, `tc` is noted, and the
raw 56-bit `payload` stays available (`aviation_frame_tc`,
`aviation_frame_payload`).

## 5. Altitude decoders

The 12-bit ADS-B altitude field (airborne position, ME bits 9-20) and the
13-bit Mode S AC field (DF4/DF20, frame bits 20-32) share the bit order

```
MSB -> LSB:  C1 A1 C2 A2 C4 A4 [M] B1 Q B2 D2 B4 D4
```

with M present only in AC13 (bit 6; Q is bit 4 in both).

- M=0, Q=1 (implemented): N is the 11 bits left after removing M and Q
  (`AC12: (v/32)*16 + v%16`; `AC13: (v/128)*32 + ((v/32)%2)*16 + v%16`)
  and the altitude is `N * 25 - 1000` feet, covering -1000..50175 ft.
- M=0, Q=0 (documented, NOT decoded): the field is a Gillham
  (reflected-binary / Gray-coded) altitude assembled from the C/A/B/D bits;
  a wrong decode is worse than an error, so
  `aviation: gillham altitude code unsupported` is returned.
- M=1 (documented, NOT decoded): metric altitude;
  `aviation: metric altitude unsupported` is returned.

TC 20-22 GNSS height is the raw 12-bit field in metres
(`aviation_gnss_altitude_m`), with `aviation_gnss_altitude_ft` converting
with a fixed 3.28084 m/ft factor and half-away-from-zero rounding.

## 6. Compact Position Reporting

### Scales

Public positions are `Int`s in units of 10^-5 degrees: 52.25720 deg =
5225720. Internally the decode runs at 10^-7 degrees with integer rational
arithmetic; the result is rounded half away from zero to 10^-5, about 1.1 m
of quantisation, below the CPR grid step (~5 m). There is no floating
point and no trigonometry anywhere in this module.

### NL(lat)

`aviation_cpr_nl(lat_scaled)` returns the number of CPR longitude zones,
1..59 (59 at the equator, 1 at |lat| >= 87). The sign of the latitude is
ignored. The 58 standard boundary latitudes are compared at 10^-7 degree
resolution (10.47047130 -> 104704713, ..., 87.00000000 -> 870000000); a
latitude below boundary i has NL = 59 - i and everything at or above the
last boundary has NL = 1.

### CPR pair packing

`aviation_cpr_pack(lat_cpr, lon_cpr) = lat_cpr * 131072 + lon_cpr` joins the
two 17-bit fields of one frame into one Int, which is what the decoders
take. `aviation_cpr_pack_lat` / `aviation_cpr_pack_lon` take it apart.

### Local decode

`aviation_cpr_decode_local(odd, even, latest_odd, ref_lat_scaled,
ref_lon_scaled)` decodes the frame selected by `latest_odd` against a
reference position (`ref_*` in 10^-5 degrees):

```
span  = 60 - i                (i = 1 when the odd frame is used)
j     = floor(ref_lat / dLat) + floor(0.5 + mod(ref_lat, dLat)/dLat - yz/2^17)
lat   = dLat * (j + yz/2^17),   dLat = 360/span
nl    = NL(lat)
ni    = max(nl - i, 1)
m     = floor(ref_lon / dLon) + floor(0.5 + mod(ref_lon, dLon)/dLon - xz/2^17)
lon   = dLon * (m + xz/2^17),   dLon = 360/ni
```

The reference must be within half a zone of the true position (~3 deg of
latitude, ~3.05 deg for the odd zone, and dLon/2 in longitude); that is
what "local" CPR means and is the caller's responsibility. Longitude is
normalised to (-180, 180].

### Global decode

`aviation_cpr_decode_global(even, odd, latest_odd)` uses both frames of a
pair (both packed as above):

```
j       = floor( (59*yz_e - 60*yz_o)/2^17 + 0.5 )
lat_e   = 6   * (mod(j, 60) + yz_e/2^17)
lat_o   = 360/59 * (mod(j, 59) + yz_o/2^17)
          (each: if lat > 270, subtract 360)
require NL(lat_e) == NL(lat_o)
nl      = NL(selected lat);  i = latest_odd;  ni = max(nl - i, 1)
m       = floor( (xz_e*(nl-1) - xz_o*nl)/2^17 + 0.5 )
lon     = 360/ni * (mod(m, ni) + xz/2^17)
```

The returned fix is the solution of the frame named by `latest_odd`
(nonzero = odd). Ambiguity boundaries, documented and intentionally
caller-side:

- **North/south hemisphere rule.** A latitude above 270 deg is taken as
  southern (360 subtracted). This is the standard single-solution rule;
  a caller that tracks real traffic must additionally reject implausible
  jumps and prefer the newest frame, as dump1090/pyModeS do.
- **Frame order and freshness.** The 10 s pairing rule and which frame is
  newest are the caller's (the `latest_odd` argument carries the answer).
- **NL consistency check.** `aviation: cpr nl mismatch` is returned when
  the two implied latitudes fall in different NL bands. For well-formed
  pairs produced by the CPR arithmetic this is a defensive check; it can
  fire when a caller pairs unrelated frames.

## 7. Error catalog

All errors are stable strings.

| Error | Raised by |
|---|---|
| `aviation: bit offset out of range` | `aviation_bit`, `aviation_bits` |
| `aviation: bit width out of range` | `aviation_bits` (len < 0 or > 56) |
| `aviation: truncated frame` | `aviation_parse_frame` |
| `aviation: unknown df` | `aviation_parse_frame` (reserved DF) |
| `aviation: not an extended squitter frame` | all ME decoders (short frame or DF not 17/18) |
| `aviation: not an identification message` | `aviation_ident_decode` |
| `aviation: not a surface position message` | `aviation_surface_decode` |
| `aviation: not an airborne position message` | `aviation_position_decode` |
| `aviation: not an airborne velocity message` | `aviation_velocity_decode` |
| `aviation: not an aircraft status message` | `aviation_emergency_decode` |
| `aviation: not a target state message` | `aviation_target_state_decode` |
| `aviation: unsupported target state subtype` | `aviation_target_state_decode` |
| `aviation: not an operational status message` | `aviation_op_status_decode` |
| `aviation: unsupported operational status subtype` | `aviation_op_status_decode` |
| `aviation: altitude field out of range` | AC12/AC13 decoders |
| `aviation: gillham altitude code unsupported` | AC12/AC13 decoders (Q=0) |
| `aviation: metric altitude unsupported` | AC13 decoder (M=1) |
| `aviation: cpr field out of range` | CPR decoders (packed pair outside 0..2^34-1) |
| `aviation: cpr nl mismatch` | `aviation_cpr_decode_global` |

## 8. Test plan

`tests/test_conformance.xi`, 21 checks, all passing on the local harness.
Fixtures are real frames written as hex text and converted byte by byte
plus synthetic frames assembled with an in-test MSB-first bit builder
(independent of the library's reader). Golden frames:

| Frame | What it pins |
|---|---|
| `8D40621D58C382D690C8AC2863A7` (even) | TC 11, ICAO 40621D, 38000 ft, CPR (93000, 51372) |
| `8D40621D58C386435CC412692AD6` (odd) | TC 11, 38000 ft, CPR (74158, 50194) |
| `8D4840D6202CC371C32CE0576098` | TC 4 identification, callsign `KLM1023 ` |
| `8D485020994409940838175B284F` | TC 19 subtype 1: 8 kt W, 159 kt S, -832 fpm, +550 ft |

The pair decodes globally to 52.25720 N, 3.91937 E (NL 36), matching the
published reference position for those messages.

Coverage: bit reader and range errors, DF table and names, frame
intake/stream consumption, callsign charset, AC12/AC13 altitude and error
paths, TC28 emergency, TC5 surface (movement table boundaries, track), TC11
and TC20 position, TC19 subtypes 1 and 3 (unknown defaults), CPR NL
boundaries (0, 10.4704713, 52.2572, 58.8476378, 87), CPR global and local
decode (northern and southern reference), pack/unpack round trip, TC29,
TC31, DF4/DF11/DF24 shapes, truncated input and reserved DFs.

## 9. Known limits

- No RF/PHY, no demodulation, no parity/CRC verification, no error
  correction; parity bytes are returned raw.
- Gillham (Q=0) and metric (M=1) altitudes are documented but not decoded.
- TC29 selected altitude is raw; TC29 subtypes other than 1 and TC31
  subtypes other than 0 are rejected.
- TC 0 / 23-27 / 30 are named but not decoded.
- DF19 and Comm-B (DF20/21) payloads are preserved raw, not decoded.
- CPR decode is a position computation, not a tracker: no time filtering,
  no outlier rejection, no single-frame decoding.
- In-memory `Vec[UInt8]` inputs only; nothing allocates or caches.
