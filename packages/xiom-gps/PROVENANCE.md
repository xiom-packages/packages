# xiom.gps -- PROVENANCE

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.

## Upstream project

| | |
|---|---|
| Project | **gpsd** -- "a service daemon that monitors one or more GPSes or AIS receivers attached to a host computer through serial or USB ports" |
| Canonical repo | `https://gitlab.com/gpsd/gpsd` (mirror: `https://github.com/gpsd/gpsd`) |
| Clone pin | `a184c8a4c028dae94b7599ba01688fb3ddeddd97` (2026-10-14) |
| Clone | `git clone --depth 1 https://gitlab.com/gpsd/gpsd E:\repos\gpsd` (light clone; working tree clean at the pin) |
| License | **BSD-2-Clause** -- verified FIRST, before any study: the repo root carries `COPYING` (SPDX-License-Identifier: BSD-2-Clause) and `LICENSE`; every source file reviewed carries the BSD-2 header ("Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met..."). Copyright: the GPSD project (Eric S. Raymond and contributors). |
| Permissiveness check | BSD-2-Clause is permissive, no copyleft, no runtime linking obligation -- suitable for reference + test-vector import under this package's MIT OR Apache-2.0. |

## What was consulted (no code copied)

The package is a **pure-XIOM re-implementation** of the documented
formats. Upstream material was read as an oracle, nothing was
translated or vendored:

| Upstream path | Used for |
|---|---|
| `man/gpsd_json.adoc` | Every JSON attribute name, meaning, presence rule; request-line grammar; ERROR example. |
| `drivers/driver_nmea0183.c` | NMEA field layouts, decode rules (`decode_hhmmss`, `merge_ddmmyy`, `decode_lat_or_lon`/`do_lat_lon`, magvar rule, GSA PRN loop + DOP gates, GSV record/trailing-field rules, `faa_mode` sets). |
| `gpsd/packet.c` | Checksum validation rule (last `*`, two hex digits, XOR from index 1, `$STI,` exception noted). |
| `gpsd/gpsd_json.c` | VERSION dumper (`release` spelling, `rev`, proto pair), DEVICE/`activated` forms, WATCH policy dump, SKY satellite dump (`used` always emitted). |
| `libgps/libgps_sock.c`, `libgps/libgps_json.c` | Canonical `?WATCH={"enable":true,"json":true};` command line; `gps_close` shutdown semantics. |
| `SConstruct`, `android/gpsd_config.in` | `GPSD_PROTO_VERSION_MAJOR = 3`, `GPSD_PROTO_VERSION_MINOR = 15` at the pin. |
| `cgps/cgps.c` (dialog) | The protocol compatibility refusal rule (major equal, minor >= client). |

## Imported test vectors (data, verbatim)

Fixture files under `tests/fixtures/` embed sentences and JSON lines
**copied verbatim** from upstream regression data. Each file carries a
header citing the source path and the pin; each copied line is
unmodified. Copyright of the copied data remains with the GPSD
project (BSD-2-Clause); they are test data, not distributed runtime
material.

| Fixture | Copied from (pin a184c8a4) | Contents |
|---|---|---|
| `tests/fixtures/nmea-upstream.log` | `test/daemon/nmea-fuzzy-cases.log` (submitted by Fred Wright, 2020-06-29) and `test/daemon/quectel-l76k-nmea.log` | 4 GGA/RMC high-precision Trimble RTK sentences; 3 GNGSA (NMEA 4.10 system id); 5 GSV covering GP/GL/BD talkers, an empty-el/az record and the NMEA 4.1 signal id. |
| `tests/fixtures/gpsd-json-upstream.jsonl` | `test/daemon/jl-micro-jlt.log` (header captures), `test/daemon/nmea-fuzzy-cases.log.chk`, `test/daemon/ublox-neo-m9n-nmea.log.chk`, `man/gpsd_json.adoc` (ERROR example) | Recorded daemon output: VERSION, DEVICES, WATCH, two TPV (with/without `time`), a minimal SKY, a 16-satellite SKY with gnssid/svid/sigid, one ERROR notification. |
| Inline test sentences (in `tests/test_conformance.xi`) | same pin, quoted with source comments | The multipacket concatenation form (`test/clientlib/multipacket.log`), the legacy numeric `activated` DEVICE form, crafted sentences whose checksums the suite recomputes. |

Every checksum in the imported NMEA lines was independently
recomputed during fixture preparation; the suite re-validates all 12
on every run.

## Third-party dependencies at runtime

None beyond the XIOM standard library (`xiom.std`): the JSON engine is
`xiom.serialize.json`, sockets are `xiom.net.socket`, string/number
helpers are `xiom.string.*`/`xiom.convert.parse`. No gpsd code, no
libgps linkage, no vendored C, no data files are read at runtime.
