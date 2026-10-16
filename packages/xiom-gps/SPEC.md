# xiom.gps -- SPEC (declared surface, phase 1)

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.

This document is the contract for **xiom.gps 0.1.0**. The package
declares exactly the surface below; "100% of the declared set" is the
lane's done-definition. Upstream oracle: **gpsd** at pin
`a184c8a4c028dae94b7599ba01688fb3ddeddd97` (BSD-2-Clause): the JSON
protocol per `man/gpsd_json.adoc`, the NMEA semantics per
`drivers/driver_nmea0183.c` and the checksum rules per
`gpsd/packet.c`. File-level provenance is in PROVENANCE.md.

Module: `xiom.gps` (single module, `src/gps.xi`). Imports:
`xiom.net.socket` (client leg), `xiom.serialize.json` (JSON engine),
`xiom.string`, `xiom.string.compare`, `xiom.string.split`,
`xiom.string.builder`, `xiom.convert.parse`. Platform dep `xiom.std`.

## 1. Constants

| Constant | Value | Meaning (oracle) |
|---|---|---|
| `GPSD_PROTO_MAJOR` | 3 | Upstream `GPSD_PROTO_VERSION_MAJOR` at the pin. |
| `GPSD_PROTO_MINOR` | 15 | Upstream `GPSD_PROTO_VERSION_MINOR` at the pin. |
| `GPS_MODE_UNKNOWN` | 0 | TPV `mode` (gpsd_json.adoc). |
| `GPS_MODE_NO_FIX` | 1 | TPV `mode`. |
| `GPS_MODE_2D` | 2 | TPV `mode`. |
| `GPS_MODE_3D` | 3 | TPV `mode`. |
| `GPS_ERR_ABSENT` | 0 | Client kind: nothing accepted the connection -> SKIP. |
| `GPS_ERR_IO` | 1 | Client kind: socket I/O failure / closed peer / closed client. |
| `GPS_ERR_TIMEOUT` | 2 | Client kind: no complete line within the deadline. |
| `GPS_ERR_PARSE` | 3 | Client kind: malformed line or over-long line. |

## 2. gpsd JSON message types

Absent JSON attributes decode to `None`. Extra attributes in a message
are ignored. A present attribute whose JSON type does not match the
declared slot decodes to `None` (lenient optional typing; `gpsd`
itself never emits mismatched types -- the rule protects against
foreign senders). Required attributes are typed errors when missing or
mistyped. Integer slots require an integral JSON number.

### 2.1 GpsTpv

| Field | JSON key | Req | Notes |
|---|---|---|---|
| `mode` | `mode` | yes | 0..3 (see constants). |
| `status` | `status` | no | gpsd status code. |
| `time` | `time` | no | ISO8601 UTC string as emitted by the daemon. |
| `device` | `device` | no | Only present when more than one device. |
| `lat`,`lon` | `lat`,`lon` | no | Signed degrees. |
| `alt_hae` | `altHAE` | no | Meters above the WGS84 ellipsoid. |
| `alt_msl` | `altMSL` | no | Meters above MSL. |
| `speed`,`track`,`climb` | `speed`,`track`,`climb` | no | m/s, degrees true, m/s. |
| `eph`,`epv`,`ept`,`eps` | `eph`,`epv`,`ept`,`eps` | no | Estimated errors. |
| `geoid_sep` | `geoidSep` | no | Meters. |
| `magvar` | `magvar` | no | Degrees. |
| `dgps_age`,`dgps_sta` | `dgpsAge`,`dgpsSta` | no | Seconds, station id. |
| `leapseconds` | `leapseconds` | no | Only some firmware. |

(Not declared: ECEF vectors, relative vectors, `alt`, `magtrack`,
`velN/E/D`, wind, jam indicators -- future phases.)

### 2.2 GpsSky / GpsSatellite

`GpsSky`: `device`, `time` (optional strings); `gdop`, `hdop`, `pdop`,
`tdop`, `vdop`, `xdop`, `ydop` (optional floats); `n_sat` (`nSat`),
`u_sat` (`uSat`) (optional ints); `satellites: Vec[GpsSatellite]`
(absent attribute -> empty list).

`GpsSatellite`: `prn` (`PRN`, **required**), `used` (**required**,
always emitted by the daemon), `gnssid`, `svid`, `sigid`, `freqid`,
`health` (optional ints), `el`, `az`, `ss` (optional floats).

### 2.3 GpsVersion

| Field | JSON key | Req | Notes |
|---|---|---|---|
| `release` | `release` else `version` | yes | Current daemons emit `release`; the manual example uses `version`; both accepted. |
| `rev` | `rev` | no | |
| `proto_major`,`proto_minor` | same | yes | Daemon protocol numbers. |
| `remote` | `remote` | no | |

### 2.4 GpsDevice / GpsDevices

`GpsDevice` optional keys: `path`, `driver`, `subtype`, `subtype1`,
`bps`, `parity`, `stopbits`, `native`, `cycle`, `mincycle`, `flags`,
`readonly`, `sernum`, and `activated` in **either** form: the ISO8601
string populates `activated`, the legacy numeric timestamp populates
`activated_num` (both forms exist in upstream captures); at most one
is set. `GpsDevices`: `devices: Vec[GpsDevice]` (required, must be an
array of objects) and `remote` (optional).

### 2.5 GpsWatch

`enable`, `json`, `nmea`, `scaled`, `split24`, `pps`, `timing`
(optional bools); `raw` (optional int); `device`, `remote` (optional
strings). All optional: the response describes only the subscriber's
policy.

### 2.6 GpsErrorMsg and the union

`GpsErrorMsg.message` (required). `GpsMessage` variants: `Version`,
`Watch`, `Devices`, `Device`, `Tpv`, `Sky`, `Error`, and
`Other(class_name: Str)` for every class outside the declared set
(GST, ATT, IMU, PPS, OSC, TOFF, AIS, RTCM, POLL, ...), so a streaming
caller can skip forward classes without failing.

## 3. gpsd functions

| Function | Contract |
|---|---|
| `gpsd_parse_line(line)` | Strip trailing CR/LF; parse JSON; require an object; read `class` (string, required); dispatch. Classes in the declared set are fully typed; other classes -> `Other(class)`. Errors: `gps: empty line`, `gps: json: <stdlib error>`, `gps: not a json object`, `gps: missing class`, per-class errors below. Trailing bytes after the value (a concatenated multipacket line) are a JSON error. |
| `gpsd_message_class(line)` | As above but returns only the class string. |
| `gpsd_parse_tpv/_sky/_version/_devices/_device/_watch/_error(line)` | Parse the line and require the matching class. Mismatch -> `gps: expected class X, got Y`. |
| `gpsd_proto_compatible(major, minor)` | `major == 3 && minor >= 15` -- the cgps `GPSD_API_MAJOR_VERSION != proto_major || GPSD_API_MINOR_VERSION > proto_minor` refusal rule. |
| `gpsd_watch_command(enable)` | `?WATCH={"enable":true,"json":true};` or `?WATCH={"enable":false,"json":false};` (byte-exact, matching libgps's command; the client appends CR-NL). |
| `gpsd_version_command()` | `?VERSION;`. |

Error channel: every parser returns `Result[T, Str]` whose messages
start with `gps: `.

## 4. Client session

`GpsClient { fd, host, port, timeout_ms, buf }`.

| Function | Contract |
|---|---|
| `gpsd_client_open(host, port, timeout_ms)` | `socket_tcp` + `socket_connect`. Any connect failure (refused, unreachable, DNS) -> `Err { kind: GPS_ERR_ABSENT, message: "gps: connect HOST:PORT refused: <socket error>" }` (the SKIP classification). Port outside 1..65535 or negative timeout -> `GPS_ERR_IO`. |
| `gpsd_client_send(&c, cmd)` | Appends CR-NL and sends; closed client -> `GPS_ERR_IO`; send failure -> `GPS_ERR_IO`. |
| `gpsd_client_watch(&c, enable)` | `gpsd_client_send` of `gpsd_watch_command(enable)`. |
| `gpsd_client_read_line(&c)` | Returns one complete line without terminator (CR stripped). Receive attempts are bounded by `timeout_ms` each: recv failure/deadline -> `GPS_ERR_TIMEOUT`; orderly peer close (0 bytes) -> `GPS_ERR_IO`; a line exceeding 65536 bytes or 1024 receive cycles -> `GPS_ERR_PARSE`/`GPS_ERR_TIMEOUT`. |
| `gpsd_client_next(&c)` | Skips empty lines; first non-empty line must parse; parse failure -> `GPS_ERR_PARSE` with the parser message. |
| `gpsd_client_close(&c)` | `shutdown(fd, 2)` + `close(fd)`, sets `fd = -1`; idempotent; returns `Ok(())`. |

## 5. NMEA 0183 surface

### 5.1 Checksum (`nmea_checksum` / `nmea_checksum_valid`)

The upstream `packet.c` rule, byte-exact:

1. Strip trailing CR/LF; find the **last** `*` scanning from the end.
   Missing -> `gps: nmea checksum missing`; fewer than two bytes after
   it -> `gps: nmea checksum truncated`.
2. The two following bytes must be hex digits (case-insensitive);
   otherwise `gps: nmea checksum not hex`.
3. The expected value is the XOR of every byte between the leading
   `$`/`!` (index 0, excluded) and the `*` (excluded). Mismatch ->
   `gps: nmea checksum mismatch`. Bytes after the two digits are
   ignored (daemon tolerance).

### 5.2 Line framing

`nmea_talker` / `nmea_kind` / every parser require a `$`-prefixed
line, a valid checksum, and at least one comma-separated field.
Field `f[0]` is talker + sentence kind (`GPGSV`); `talker` is
everything before the last three characters, `kind` the last three.
Reads beyond the field count are treated as empty (absent), matching
the daemon's zero-filled field table for shortened sentences.

### 5.3 Value decoding helpers

- **Time** `hhmmss[.frac]`: six digits required; optional fraction of
  digits (empty fraction allowed); hour <= 23, minute <= 59, second <=
  60 (leap second). Milliseconds = first three fraction digits, right
  padded (`"60"` -> 600 ms); digits beyond the third truncated.
- **Date** `ddmmyy`: exactly six digits, 1 <= day <= 31, 1 <= month <=
  12; year = 2000+yy for yy < 69, 1900+yy otherwise (the upstream
  window: 1969..2068).
- **Coordinates** `[d]ddmm.mmmm`: digits, decimal point (1..4 integer
  digits), optional fraction; minutes < 60; degrees <= 90 (lat) or
  <= 180 (lon); hemisphere `N`/`S`, `E`/`W` (case-sensitive), `S`/`W`
  negate. Value = `(deg*60 + min_int + frac) / 60`. All four lat/lon
  fields empty -> both absent; a partial quartet -> `gps: bad
  <kind> lat/lon`.

### 5.4 GGA (`nmea_parse_gga`)

Fields: 1 time, 2/3 lat+hemisphere, 4/5 lon+hemisphere, 6 fix
quality, 7 satellites used, 8 HDOP, 9/10 MSL altitude + units,
11/12 geoid separation + units, 13 DGPS age, 14 DGPS station.
Result `NmeaGga { talker, time?, lat?, lon?, fix_quality?, num_sats?,
hdop?, alt_msl?, geoid_sep?, dgps_age?, dgps_sta? }`. Units fields
(10, 12) are read and ignored (daemon parity). Empty quality ->
absent. Non-integer quality/num_sats/station -> typed error.

### 5.5 RMC (`nmea_parse_rmc`)

Fields: 1 time, 2 status (`A` accept / `V` void; empty -> absent,
other -> error), 3/4 lat, 5/6 lon, 7 speed (knots, as transmitted),
8 track (degrees true), 9 date, 10/11 magnetic variation + `E`/`W`,
12 FAA mode indicator, 13 NMEA 4.1 nav status.
`magvar_deg` is signed (E+, W-) and **absent when |v| <= 0.09**
(the upstream "some GPS set 0.0,E" rule); a partial variation pair is
ignored (daemon parity). Mode indicator set: `ACDEFMN0PRSUV`; nav
status set: `ADEFMNPRSV`; other characters -> typed error.

### 5.6 GSA (`nmea_parse_gsa`)

Fields: 1 mode (`A`/`M`), 2 fix type, 3..(len-4) satellite numbers,
then PDOP/HDOP/VDOP, optionally an 19th field (NMEA 4.10 system id).
Result: `mode?`, `fix_type` (upstream **atoi reading**: leading digit
run, no digits -> 0; `E` dead reckoning -> 0), `prns` (sentence order;
empty skipped; non-digits error; only 1..600 kept, 0 and >600
dropped), DOPs at the standard positions 15/16/17 with the sentinel
gate **absent unless 0.01 <= v <= 89.99**, `system_id` only for
19-field sentences whose field 18 is an integer (`gps` parity for
the Navior-24 layout is out of scope: sentences longer than 19 fields
skip the DOP/system-id block).

### 5.7 GSV (`nmea_parse_gsv`)

Fields: 1 number of messages (gate 1..10), 2 message number (gate
1..num), 3 satellites in view, records of four values from index 4,
then 0, 1 or 2 trailing fields. Trailing shape by `len % 4`: 0 =
pre-4.10; 1 = NMEA 4.1 **signal id** (leading hex digit, daemon
rule); 2 = Quectel PQGSV **signal id + system id** (system id must be
4 or 5); 3 = error. Records: empty PRN skips the record; PRN 0 skips
(the upstream bogus-field rule); non-digits error; elevation kept
only when `|el| <= 90` and azimuth only when `0 <= az < 360`, with
azimuth 360 normalized to 0, and the upstream **both-or-neither**
rule for el/az pairs; SNR optional. Result `NmeaGsv { talker,
num_msgs, msg_num, sats_in_view, signal_id?, system_id?,
satellites }`.

### 5.8 Dispatch

`nmea_parse_line` validates framing once and dispatches on the
sentence kind: `Gga`, `Rmc`, `Gsa`, `Gsv`, `Other(talker, kind)` for
everything else (VTG, ZDA, GNS, GLL, ...).

## 6. Declared divergences from the upstream C driver

These are deliberate, typed-contract choices; each is stricter than
the daemon and can never silently corrupt data:

1. **Malformed values are errors, not slop.** `gpsd` runs `atoi`/
   `safe_atof` and continues with 0/partial values for most fields;
   xiom.gps returns typed errors when a *present* field cannot be
   decoded (except the documented atoi-reading fields: GSA
   `fix_type`, GSV `sats_in_view`). The upstream fixture recordings
   contain only well-formed fields, so fixture parity holds.
2. **Value validation.** The daemon performs no range checks on
   time/date/coordinates; xiom.gps enforces structural ranges
   (hour/minute/second, day/month, minutes < 60, degrees in range,
   hemisphere letters).
3. **Strict checksum policy for parser entry points.** The daemon
   accepts `$STI,` without a checksum; xiom.gps requires a valid
   checksum on every line it frames (that vendor sentence is not in
   the declared set anyway).
4. **No aggregate state.** xiom.gps parses sentences, it does not
   run the daemon's NMEA state machine (no cycle merging, no epoch
   detection, no PRN re-mapping via `nmeaid_to_prn`, no dedup across
   GPGSA/GNGSA -- each parse reports its sentence as written).
5. **Fraction handling.** Milliseconds from the first three fraction
   digits (uniform padding); the daemon's `nsec = atoi(frac) *
   10^(9-len)` agrees for 1..3 digits and truncates to 0 for >9
   digits, where this package keeps three-digit precision.
6. **JSON typing is exact for required fields.** `TPV.mode`,
   `PRN`/`used`, version `release`+proto pair, device arrays and the
   ERROR message must be present and typed; the daemon always emits
   them.

## 7. Non-goals (phase 1)

RTCM/AIS decoding, `?POLL`/device activation commands, GST/ATT/IMU/TOFF
typed classes (they flow through `Other`), libgps multi-soname loader
(the pure-XIOM path replaced it), NMEA VTG/ZDA/GNS/GLL typed parsers
(`Other`), SkyTraq/U-blox proprietary frames, sentence aggregation and
fix-mode state machines, and a fixture gpsd server for live-socket
tests (ROADMAP).
