# ROADMAP: xiom.firmata

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

Current shipped surface: 0.1.0 (`SPEC.md` sec. 4). Everything below is
unshipped and explicitly outside the declared 0.1.0 surface.

## 0.2.0 -- board capability discovery (proposed)

| Item | Basis |
|---|---|
| Capability query/response (`0x6B`/`0x6C`) | protocol.md Capability Query: pin count, supported modes, per-mode resolution; needed to validate PWM/servo ranges before writes |
| Analog mapping query/response (`0x69`/`0x6A`) | protocol.md Analog Mapping: A0..An channel -> physical pin; removes the caller's hard-coded map |
| Pin state query/response (`0x6D`/`0x6E`) | protocol.md Pin State: verify a mode/write after configuration |
| Sampling interval (`0x7A`/`0x7C`) | protocol.md Sampling Interval: analog/I2C report cadence |
| Firmware name normalization | `firmata.js` masks firmware name pairs to 8 bits; expose an optional compatibility flag if real boards need it |

## 0.3.0 -- optional feature surface (proposed)

| Item | Basis |
|---|---|
| EXTENDED_ANALOG (`0x6F`) | PWM/analog writes for pins > 15 and > 14-bit values (protocol 2.7 allows up to 32 bits / 5 octets) |
| Servo config (`0x70`) | min/max pulse configuration for SERVO mode |
| I2C request/reply/config (`0x76`/`0x77`/`0x78`) | protocol i2c.md; address/register framing with 7-bit pairs |
| OneWire data (`0x73`) | protocol onewire.md; search/read/write sub-commands |
| Serial feature (`0x60`) | protocol serial-1.0.md; port config/read/write/listen |
| Shift/stepper/encoder | remaining optional feature documents |

Each addition follows the same rules: typed errors, argument validation
before state changes, fixture traces, and a coverage-table row.

## 0.4.0 -- host loop conveniences (proposed)

- Response correlation helpers (expect a Version/Firmware within N
  messages) built from `firmata_session_poll` without adding timers to the
  session; the host loop keeps owning time.
- Optional `xiom.serial` adapter module (separate package or feature) once
  the serial binding's API is stable; the core stays transport-agnostic.
- A bounded-memory note parser: cap sysex length explicitly (the current
  cap is the session `rx_limit`).

## 1.0.0 -- stable (per doctrine sec. 7)

Promotion requires the full declared surface published plus at least one
settle cycle and no open defects. Candidate gates:

- [ ] 0.2.0 capability/mapping/pin-state surface green x2.
- [ ] A real-board conformance run (Arduino-class, StandardFirmata) with a
      recorded trace added to `tests/fixtures/`.
- [ ] `xiom.serial` adapter exercised on Windows hardware (device leg) or
      explicitly deferred with the SKIP path kept.
- [ ] No open relay items referencing the package; coverage table
      reaffirmed against the then-current SPEC.

## Non-goals (indefinite)

- Firmware/board implementation (this package is host-side only).
- Bundling or vendoring the Arduino core (`LGPL`) or any GPL tooling.
- A serial-port manager (open/configure/close stays with the transport
  package, e.g. `xiom.serial`).
- MIDI music semantics: Firmata reuses the MIDI framing, not the MIDI
  protocol; non-Firmata MIDI channel messages are rejected by design.
