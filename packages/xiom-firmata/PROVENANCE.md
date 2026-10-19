# PROVENANCE: xiom.firmata

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0
>
> Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% of the
> declared surface). This package is an **independent** implementation:
> no upstream code is vendored, ported, or copied.

## 1. Declaration

`xiom.firmata` 0.1.0 is original work. There is **no vendored upstream**
and no link dependency: the package is pure XIOM with no FFI and no C.
The implementation was written against the Firmata protocol document and
cross-checked, reference-only, against the MIT-licensed `firmata.js`
client. The repository stays MIT OR Apache-2.0; no third-party license
text ships with the package because no third-party code ships with it.

## 2. Implementation oracles (pinned)

### 2.1 Firmata protocol document

| Field | Value |
|---|---|
| Upstream | https://github.com/firmata/protocol |
| File | `protocol.md` (current version stated: 2.8.0) |
| Pin | commit `7908873e8faae33111143aa6cc236148b12118f2` (`HEAD`, fetched 2026-10-19) |
| License | MIT (per the project's repository metadata; reference-only) |
| Used for | message statuses and lengths; 7-bit pair value math; REPORT_VERSION, REPORT_FIRMWARE, STRING_DATA layouts; mode constants; SET_PIN_MODE / SET_DIGITAL_PIN_VALUE / REPORT_ANALOG / REPORT_DIGITAL / SYSTEM_RESET semantics; EXTENDED_ANALOG scope decision |

Key sections consulted: "Message Types", "Data Message Expansion"
(digital two-byte format, analog 14-bit format), "Control Messages
Expansion" (set pin mode/value, report toggles), "Sysex Message Format"
(core ids), "Query Firmware Name and Version", "String", "Capability
Query", "Analog Mapping Query", and "Pin State Query".

### 2.2 Reference client: firmata.js (reference-only, NEVER vendored)

| Field | Value |
|---|---|
| Upstream | https://github.com/firmata/firmata.js |
| Pin | commit `4a3b86b46bedf5d238e19ff9aed08742cc607114` (`HEAD`, fetched 2026-10-19) |
| File consulted | `packages/firmata-io/lib/firmata.js` (raw file fetched 2026-10-19) |
| License | MIT (reference-only; no code copied) |
| Status | Not a dependency, not distributed, not linked |

Semantics cross-checked (behavioral only):

| Reference location | What was verified |
|---|---|
| `MIDI_RESPONSE[ANALOG_MESSAGE]` | `pin = status & 0x0F`; `value = lsb | (msb << 7)` -- the package's 14-bit arithmetic matches |
| `MIDI_RESPONSE[DIGITAL_MESSAGE]` | `port = status & 0x0F`; port value is the 14-bit pair; pins are `8*port + i` -- the package's port/mask decode matches |
| `MIDI_RESPONSE[REPORT_VERSION]` | major = byte 1, minor = byte 2 -- matches |
| `SYSEX_RESPONSE[QUERY_FIRMWARE]` | major/minor then name pairs; the reference masks each pair to 8 bits (`& 0xFF`) -- the package follows the protocol's 14-bit definition instead (ASCII-identical; SPEC sec. 8) |
| `pwmWrite` | pins <= 15 use `ANALOG_MESSAGE | pin` + two 7-bit bytes; pins > 15 use EXTENDED_ANALOG (declared out of scope) -- the in-scope path matches |
| `digitalWrite`/`writeDigitalPort` | port = `pin >> 3`, bit = `pin & 7`, message `DIGITAL_MESSAGE | port` with `mask & 0x7F` and `mask >> 7` -- the session write path matches, including shadow accumulation |
| `reportAnalogPin` / `reportDigitalPin` | `REPORT_ANALOG | channel` and `REPORT_DIGITAL | port`, value 0/1 -- matches |
| `queryFirmware` | `[START_SYSEX, QUERY_FIRMWARE, END_SYSEX]` == `f0 79 f7` -- matches |
| `reportVersion` | sends `[REPORT_VERSION]` == `f9` -- matches |
| `sendString` | each UTF-8 byte is written as two 7-bit bytes (LSB, MSB) -- the protocol-faithful decode direction is implemented |

No code, structure or comments were copied. The client was read to confirm
byte-level behavior, exactly as recorded above.

## 3. Test vectors

The fixtures under `tests/fixtures/` are **recorded reference byte traces**,
not hardware captures:

| Fixture | Content | Derivation |
|---|---|---|
| `handshake.hex` | `f9 02 05` + REPORT_FIRMWARE `2.5 StandardFirmata` | protocol layouts sec. 2.1; ASCII name pairs computed from the wire rule `char = lsb + msb*128` |
| `io_reports.hex` | digital/analog reports, report toggles, set-mode/set-pin loopback, reset, MIDI clock, unknown sysex | protocol layouts; values chosen to exercise both 7-bit groups (42, 1023, 1024) |
| `strings.hex` | `"READY"`, U+00E9, `"A\0B"`, empty | protocol "String" section; U+00E9 = 105 + 1*128 |
| `host_commands.hex` | the concatenated encoder output sequence | package's own encoders, checked byte-for-byte against the protocol tables |
| `noise.hex` | two garbage bytes before a version report | resynchronization contract (SPEC sec. 6) |

The traces are deterministic and reviewed by hand against the protocol
tables; they are not claimed to be oscilloscope/serial captures. A real
board trace is a 1.0.0 gate (ROADMAP.md).

## 4. Owner instruction recorded (2026-10-19)

The MCU Phase-1 wave directive: host-side, fixture-testable packages with
no hardware, on compiler pin v0.64.7, suites x2 on `origin/bindings`;
I2C/OneWire only if cheap, otherwise declared out of scope. This package
declares both out of scope (SPEC sec. 8) and implements the fixed-frame
core plus sysex string/firmware decode.

## 5. Refresh procedure

1. **Protocol refresh:** fetch `firmata/protocol`, checkout the recorded
   pin (or a newer one), diff `protocol.md` against SPEC sec. 3. A change
   inside the declared subset requires a version bump, updated fixtures and
   a new coverage row.
2. **Reference refresh:** fetch `firmata/firmata.js`, checkout the recorded
   pin (or newer), re-run the sec. 2.2 cross-check table. No code is ever
   taken from it.
3. **Vectors:** update only when the wire tables change; keep the
   derivation notes in the fixture headers.
4. Record the refresh as a normal package touch (README/SPEC/STATUS/AUDIT
   in the same commit).
