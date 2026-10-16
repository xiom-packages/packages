# xiom.gps

> **Status:** `incubating` -- conformance-tested (**28/28 x2** on the
> compiler pin v0.64.5; the live-daemon leg is a typed **SKIP** on hosts
> without gpsd);  not yet published.
> **Scope (phase 1):** the documented **gpsd JSON protocol** (VERSION,
> WATCH, DEVICES, DEVICE, TPV, SKY, ERROR typed; any other class passes
> through as `Other`), the `?WATCH`/`?VERSION` request builders and a
> plain TCP client session (open/watch/send/read/next/clean close) that
> classifies "no daemon" as `GPS_ERR_ABSENT` (SKIP), plus **NMEA 0183**
> sentence parsers for **GGA/RMC/GSA/GSV** with gpsd-compatible
> checksum validation and typed errors.
> **Deps:** `xiom.std` only (the module imports `xiom.net.socket`,
> `xiom.serialize.json`, `xiom.string`, `xiom.string.compare`,
> `xiom.string.split`, `xiom.string.builder`, `xiom.convert.parse`);
> tests use `xiom.io`, `xiom.convert`, `xiom.string.compare`.

## What it is

`xiom.gps` is a pure-XIOM GPS/GNSS data path for a device fleet. It
speaks the daemon side of the **gpsd** request/response protocol
(line-JSON over a TCP socket, default port 2947) and parses the raw
sensor side of the same fleet: **NMEA 0183** serial sentences from
whatever GPS/GNSS receivers are attached. Nothing is vendored: the
package re-derives both formats from the upstream documentation and
reference implementation (gpsd, pin below) and ships no C code.

Upstream reference (UPSTREAM-FIRST): **gpsd**,
`gitlab.com/gpsd/gpsd` @ `a184c8a4c028dae94b7599ba01688fb3ddeddd97`,
license **BSD-2-Clause**. The typed parsers are pinned against
recordings captured by the upstream regression suite and imported
verbatim into `tests/fixtures/` (see PROVENANCE.md for file-level
provenance and AUDIT.md for what the fixtures exercise).

## gpsd protocol surface

| Function | Returns | Description |
|---|---|---|
| `gpsd_parse_line(line)` | `Result[GpsMessage, Str]` | Parse + dispatch one response line by `class`. |
| `gpsd_message_class(line)` | `Result[Str, Str]` | The `class` attribute alone. |
| `gpsd_parse_tpv / _sky / _version / _devices / _device / _watch / _error` | typed `Result[T, Str]` | Per-class parsers (class checked). |
| `gpsd_proto_compatible(major, minor)` | `Bool` | The cgps rule: major equal, daemon minor >= 15. |
| `gpsd_watch_command(enable)` | `Str` | Canonical `?WATCH={"enable":...,"json":...};` line. |
| `gpsd_version_command()` | `Str` | `?VERSION;`. |

Types: `GpsTpv` (mode/status/time/device, lat/lon, altHAE/altMSL,
speed/track/climb, eph/epv/ept/eps, geoidSep, magvar, dgpsAge/dgpsSta,
leapseconds), `GpsSky` (DOP set + nSat/uSat + `Vec[GpsSatellite]`),
`GpsSatellite` (PRN, used, gnssid/svid/sigid/freqid, el/az/ss,
health), `GpsVersion` (release or legacy version, rev, proto_major,
proto_minor, remote), `GpsDevice` (path/driver/subtype/..., ISO
`activated` or legacy numeric `activated_num`, bps/parity/stopbits/...),
`GpsDevices`, `GpsWatch`, `GpsErrorMsg`, and the `GpsMessage` union
(`Version`, `Watch`, `Devices`, `Device`, `Tpv`, `Sky`, `Error`,
`Other(class)`).

Absent attributes decode to `None`; required attributes (`TPV.mode`,
satellite `PRN`/`used`, `VERSION` release + proto pair, `ERROR`
message, the `DEVICES` array) are typed errors when missing.

## Client session

| Function | Returns | Description |
|---|---|---|
| `gpsd_client_open(host, port, timeout_ms)` | `Result[GpsClient, GpsError]` | TCP connect; **connect failure => `GPS_ERR_ABSENT` (SKIP)**. |
| `gpsd_client_watch(&c, enable)` | `Result[Unit, GpsError]` | Send the canonical `?WATCH` command. |
| `gpsd_client_send(&c, cmd)` | `Result[Unit, GpsError]` | Send any command line (CR-NL appended). |
| `gpsd_client_read_line(&c)` | `Result[Str, GpsError]` | One complete line (deadline-bounded recv). |
| `gpsd_client_next(&c)` | `Result[GpsMessage, GpsError]` | Read until a JSON message parses. |
| `gpsd_client_close(&c)` | `Result[Unit, GpsError]` | Shutdown + close; idempotent. |

`GpsError { kind, message }` kinds: `GPS_ERR_ABSENT` (0, no daemon ->
SKIP), `GPS_ERR_IO` (1), `GPS_ERR_TIMEOUT` (2), `GPS_ERR_PARSE` (3).

## NMEA 0183 surface

| Function | Returns | Description |
|---|---|---|
| `nmea_checksum(line)` | `Result[Int, Str]` | Validated XOR checksum (last `*`, case-insensitive hex, trailing bytes ignored). |
| `nmea_checksum_valid(line)` | `Bool` | Convenience predicate. |
| `nmea_talker(line)` / `nmea_kind(line)` | `Result[Str, Str]` | `GP...` / sentence kind. |
| `nmea_parse_line(line)` | `Result[NmeaMessage, Str]` | Dispatch: `Gga`, `Rmc`, `Gsa`, `Gsv`, `Other(talker, kind)`. |
| `nmea_parse_gga / _rmc / _gsa / _gsv` | typed `Result[T, Str]` | Sentence parsers. |

Typed fields follow the upstream driver semantics: hhmmss.ss with
millisecond truncation, ddmmyy with the 1969..2068 window, `S`/`W`
sign negation, minutes < 60, RMC magnetic variation signed E+/W- and
absent within 0.09 degrees, GSA `fix_type` with atoi reading
(`E` -> 0), PRN gate 1..600 with sentence order preserved, DOP
sentinel gate 0.01..89.99, GSV both-or-neither el/az, az 360 -> 0,
NMEA 4.1 signal id (hex) and the Quectel PQGSV signal+system id pair
(4/5 only). See SPEC.md for the byte-level rules and every declared
divergence.

## Quick use

```xiom
use xiom.gps;

// daemon side
let r = gpsd_client_open("127.0.0.1", 2947, 250);
if !r.is_ok {
  if r.error.kind == GPS_ERR_ABSENT {
    // no gpsd on this host: skip cleanly (typed SKIP)
  }
} else {
  var c: GpsClient = r.value;
  let w = gpsd_client_watch(&mut c, true);
  let m = gpsd_client_next(&mut c);
  let _ = m;
  let _ = gpsd_client_close(&mut c);
}

// sensor side
let g = nmea_parse_gga("$GPGGA,132820.60,4134.49821229,N,09345.03351845,W,2,09,1.0,278.020,M,-31.442,M,7.6,0133*7E");
```

## Tests

`tests/test_conformance.xi` (consumer-style: asserts through helper
functions, run by `scripts/port.ps1 -Package xiom.gps`): recorded
fixture sweeps, exact-value pins against upstream node captures,
error-path coverage, the client SKIP classification and crafted
sentences for every upstream value rule. Result on the pin:
**28/28 x2**. Hosts with a live gpsd exercise the daemon leg; hosts
without one stay green through the typed SKIP path.

## Docs

SPEC.md (declared surface + semantics), ROADMAP.md (later phases),
PROVENANCE.md (clone pin, license, imported vectors), AUDIT.md
(compiler-pin findings and coverage evidence).
