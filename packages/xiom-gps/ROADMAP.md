# xiom.gps -- ROADMAP

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.

## 0.1.0 -- shipped (this wave)

- gpsd JSON protocol: typed VERSION, WATCH, DEVICES, DEVICE, TPV, SKY,
  ERROR parsers; `Other(class)` passthrough; `gpsd_parse_line` dispatch
  and `gpsd_message_class` peek; `?WATCH`/`?VERSION` builders;
  cgps-compatible protocol check.
- Client session over `xiom.net.socket`: open (SKIP classification on
  connect failure), watch, send, read_line (deadline-bounded),
  next (JSON skip), idempotent clean close.
- NMEA 0183: gpsd-rule checksum validation; GGA/RMC/GSA/GSV parsers
  with typed errors; upstream value rules (time/date windows,
  hemisphere signs, magvar absence, DOP sentinel gates, GSV
  both-or-neither el/az, signal/system ids).
- Fixture-pinned conformance suite (28 tests) sourced from upstream
  regression recordings; x2 green on v0.64.5.

## 0.2.0 -- planned

- **Fixture gpsd server for live tests.** A tiny in-suite TCP listener
  that replays `tests/fixtures/gpsd-json-upstream.jsonl` byte-wise so
  `gpsd_client_open/watch/read_line/next/close` run their full paths on
  every host (today: SKIP when no daemon; see AUDIT.md coverage note).
- **Streaming helper.** `gpsd_client_stream(&c, kinds, limit)`:
  read N messages of selected classes with per-line skip accounting
  (fp error tolerance per gpsd_json.adoc).
- **More typed classes.** GST (rms triplet), ATT (heading/pitch/roll),
  IMU, TOFF, PPS -- promoted out of `Other` once each has upstream
  fixture coverage.
- **`?POLL` and device control.** `?DEVICES`, `?DEVICE=...`
  activation commands with typed responses.
- **NMEA extras.** VTG/ZDA/GLL/GNS typed parsers; talker-scoped PRN
  reporting for multi-constellation fleets.
- **TPV completeness.** ECEF and relative-vector fields, `alt`,
  `magtrack`, per-message `ss`/`gnssid` arrays.

## 0.3.0 -- candidate

- **libgps comparison leg.** Optional libgps multi-soname loader
  (BSD-2 system library, no vendoring) to cross-check parsed values
  against `libgps` on fleet hosts that have it; typed SKIP when
  absent. This is the fallback shape named in the lane mission and is
  deliberately *not* in 0.1.0: the pure-XIOM path is the product.
- **AIS/RTCM pass-through.** Typed `AisMessage`/`Rtcm3` envelopes so
  fleets that mix GNSS with marine traffic get one stream API
  (decode tables remain out of scope).
- **Publish readiness.** Registry scope for `xiom.gps`, allowlist
  entry, staging canary (see README publish checklist).

## Later / ideas

- Sentence aggregation layer (GSA/GSV cycles -> gpsd-style skyview)
  with explicit opt-in, to mirror daemon output for comparison.
- NMEA `!`-prefixed AIS framing; `$STI` tolerance flag.
- Time-accurate PPS (`pps` watch policy) tooling.
- Multi-device fan-in helper over `DEVICES`.
