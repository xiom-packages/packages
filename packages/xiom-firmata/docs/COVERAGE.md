# COVERAGE: xiom.firmata 0.1.0

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0
>
> Every public function in the declared 0.1.0 surface (`SPEC.md` sec. 4)
> maps to at least one conformance check. Suite: 122 checks, 122/122 x2 on
> compiler pin v0.64.7 (commit `4113fb53`). This file is the detailed
> companion to the summary table in `SPEC.md` sec. 7.

## 1. Encoders

| Function | Checks |
|---|---|
| `firmata_encode_version_query` | `encode: version query -> f9`; `encode: full host command stream matches the recorded golden fixture` |
| `firmata_encode_firmware_query` | `encode: firmware query -> f0 79 f7`; full stream |
| `firmata_encode_set_pin_mode` | `encode: SET_PIN_MODE pin 13 OUTPUT -> f4 0d 01`; `... pin 14 ANALOG -> f4 0e 02`; `... pin 9 PWM -> f4 09 03`; three rejection checks (pin 128, mode 128, negative pin) |
| `firmata_encode_digital_write` | `... pin 13 HIGH -> f5 0d 01`; `... pin 0 LOW -> f5 00 00`; `... pin 128 rejected` |
| `firmata_encode_digital_port_write` | `... port 1 mask 0x2A -> 91 2a 00`; `... port 0 mask 16383 -> 90 7f 7f`; port 16 and mask 16384 rejections |
| `firmata_encode_pwm_write` | `... pin 9 value 1023 -> e9 7f 07`; `... pin 15 value 16383 -> ef 7f 7f`; pin 16 and value 16384 rejections |
| `firmata_encode_analog_report` | `... channel 0 enable -> c0 01`; `... channel 15 disable -> cf 00`; channel 16 rejection |
| `firmata_encode_digital_report` | `... port 1 enable -> d1 01`; `... port 15 disable -> df 00`; port 16 rejection |
| `firmata_encode_system_reset` | `encode: SYSTEM_RESET -> ff`; full stream |

## 2. Framing and decode

| Function | Checks |
|---|---|
| `firmata_frame_len` | version 3, digital 3, analog 3, set-mode 3, set-pin 3, report-analog 2, report-digital 2, reset 1, realtime 1, short version 0, empty 0, unterminated sysex 0, terminated sysex 5, data byte as status (BAD_STATUS), 0x80 status (BAD_STATUS), interrupted sysex (BAD_SYSEX) |
| `firmata_decode_frame` | Version 2.5; Firmware `StandardFirmata`; Digital ports 0/1/15; Analog channels 0/1/2 (42/1023/1024); ReportAnalog/ReportDigital; SetPinMode; SetDigitalPin; SystemReset; MIDI realtime Other; unknown sysex Other; firmware-query Other; truncated; trailing bytes; embedded status; set-pin value 2; empty sysex; 1-byte firmware payload; odd firmware name; odd string; data-byte status |
| `firmata_decode_version_message` | happy path (`returns the version struct`); wrong type (`analog frame -> UNSUPPORTED`) |
| `firmata_decode_firmware_message` | happy path; wrong type |
| `firmata_decode_digital_message` | happy path (`port 0 mask 1`); wrong type |
| `firmata_decode_analog_message` | happy path (`channel 0 = 42`); wrong type |
| `firmata_decode_string_message` | `"READY"`; 14-bit U+00E9 UTF-8; NUL termination; empty payload; wrong type |

## 3. Helpers and catalogs

| Function | Checks |
|---|---|
| `firmata_digital_mask_pin` | mask 0x2A bits 1/0/5/13 set/clear checks; mask 16384, bit 14 and negative-bit rejections |
| `firmata_error_name` | one check asserts all 8 kinds plus `UNKNOWN` |
| `firmata_mode_name` | one check asserts all 12 named modes plus `UNKNOWN` (0x0C) |

## 4. Session

| Function | Checks |
|---|---|
| `firmata_session_new` | `16 zeroed ports, default rx limit, not ready`; `BUFFER_FULL, nothing appended` (limit path) |
| `firmata_session_reset` | `clears rx/out/ports/handshake, preserves rx_limit` |
| `firmata_session_feed` | empty input `Ok(0)`; accepts the 38-byte handshake trace; `rx_limit` exceeded -> `BUFFER_FULL` with no append |
| `firmata_session_pending` | `0 after consuming the trace`; `0 after a malformed-frame resync` |
| `firmata_session_poll` | first/second handshake messages + no third; byte-at-a-time feed yields 2; truncated sysex -> None then firmware; garbage-byte resync; interrupted-sysex resync; malformed-frame consume + next Version |
| `firmata_session_begin_handshake` | queues `f9 f0 79 f7`; second drain empty |
| `firmata_session_is_ready` | false before handshake; true after both reports; false after firmware-only; false after reset |
| `firmata_session_set_pin_mode` | queues `f4 0d 01`; invalid pin queues nothing |
| `firmata_session_digital_write` | pin 13 high; pin 8 high (accumulate); pin 13 low (clear); incoming `90 01 00` updates shadow then pin 2 high -> `90 05 00`; invalid pin queues nothing; hand-built short shadow -> `INVALID_ARG` (no panic) |
| `firmata_session_pwm_write` | queues `e9 7f 07`; invalid pin queues nothing |
| `firmata_session_enable_analog_report` | queues `c0 01`; invalid channel queues nothing |
| `firmata_session_enable_digital_report` | queues `d1 01`; invalid port queues nothing |
| `firmata_session_take_output` | drains the handshake bytes; second drain is empty; reset clears output |

## 5. Fixtures

| Fixture | Used by |
|---|---|
| `tests/fixtures/handshake.hex` | fixture load; handshake decode; session handshake; chunked feed |
| `tests/fixtures/io_reports.hex` | fixture load; 10-frame IO decode; 33/33-byte consumption |
| `tests/fixtures/strings.hex` | fixture load; 4 string decodes |
| `tests/fixtures/host_commands.hex` | fixture load; full host-command stream golden |
| `tests/fixtures/noise.hex` | fixture load; garbage-byte resync |

## 6. Transport / SKIP

| Check | Meaning |
|---|---|
| `transport: SKIP -- no hardware/transport required (inject bytes with firmata_session_feed)` | The suite opens no port. A real device would feed this session; absence is the normal pure-leg state and is reported as a pass with an explicit SKIP note. |
