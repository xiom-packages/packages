# xiom.firmata

> **Status:** `incubating` -- conformance-tested (**122/122 x2** on the
> compiler pin v0.64.7; fixture-driven, no hardware or transport required);
> not yet published.
> **Scope (0.1.0):** pure-XIOM host-side Firmata 2.x bindings -- version and
> firmware handshake; pin modes; digital and PWM writes; analog and digital
> report enable; digital/analog/string decode; typed errors; a
> transport-agnostic session loop with an injectable byte transport.
> **Deps:** `xiom.std` only (the module imports `xiom.string.builder` and
> `xiom.utf8`; the suite uses `xiom.io`, `xiom.convert`,
> `xiom.string.compare` and `xiom.encoding.hex`).
> Optional: `xiom.serial` for a real device (documented below; not a
> dependency and not compiled by the suite).

## What it is

Firmata is a host/MCU protocol that frames messages with the MIDI wire
format: a status byte (0x80..0xFF), one or two 7-bit data bytes, plus sysex
frames (`0xF0 ... 0xF7`) for extended commands. `xiom.firmata` implements
the **host side**: it encodes commands for a board, decodes the board's
reports, and drives a handshake -- all in pure XIOM with no C, no vendored
code and no I/O of its own.

The transport is injected. A session owns a receive buffer, an output
queue, the digital port shadow and the handshake state; the caller moves
bytes in and out:

```
serial bytes  -> firmata_session_feed -> firmata_session_poll -> messages
host commands <- firmata_session_take_output <- encoders / session_* queues
```

Because no transport is opened, the conformance suite is fully
fixture-driven (recorded byte traces under `tests/fixtures/`) and stays
green on any host. "Transport absent" is the normal pure-leg state and is
reported as an explicit SKIP note, never a failure.

## Quick start

```xiom
use xiom.firmata;

var s = firmata_session_new();
firmata_session_begin_handshake(&mut s);   // queues f9 f0 79 f7
let hello = firmata_session_take_output(&mut s);
// write `hello` to your transport (see the xiom.serial sketch below)

// later, after reading transport bytes into `bytes`:
let fr = firmata_session_feed(&mut s, &bytes);
if fr.is_ok {
  var polling = true;
  while polling {
    let pr = firmata_session_poll(&mut s);
    if !pr.is_ok {
      // typed framing/decode error: the bad byte/frame was consumed,
      // so the next poll resynchronizes on the next valid status byte.
      polling = false;
    } elif pr.value.is_some {
      let msg = pr.value.value;
      match msg {
        Analog(a) => { /* a.channel 0..15, a.value 0..16383 */ }
        Digital(d) => { /* d.port 0..15, d.mask 14-bit */ }
        _ => { }
      }
    } else {
      polling = false;   // no complete message buffered
    }
  }
}

if firmata_session_is_ready(&s) {
  // both the version and firmware handshake reports were decoded
}
```

Host commands are pure encoders, or session wrappers that queue them:

```xiom
let pm = firmata_session_set_pin_mode(&mut s, 13, FIRMATA_MODE_OUTPUT);
let dw = firmata_session_digital_write(&mut s, 13, true);   // port message
let pw = firmata_session_pwm_write(&mut s, 9, 1023);
let ar = firmata_session_enable_analog_report(&mut s, 0, true);
let out = firmata_session_take_output(&mut s);
```

Pure encoders (no session) are available when the caller owns the state:

| Encoder | Bytes | Notes |
|---|---|---|
| `firmata_encode_version_query()` | `f9` | handshake step 1 |
| `firmata_encode_firmware_query()` | `f0 79 f7` | handshake step 2 |
| `firmata_encode_set_pin_mode(pin, mode)` | `f4 pin mode` | pin 0..127, mode 0..127 |
| `firmata_encode_digital_write(pin, high)` | `f5 pin 0|1` | Firmata 2.5+ |
| `firmata_encode_digital_port_write(port, mask)` | `90|port lsb msb` | port 0..15, mask 14-bit |
| `firmata_encode_pwm_write(pin, value)` | `e0|pin lsb msb` | pin 0..15, value 14-bit |
| `firmata_encode_analog_report(channel, enable)` | `c0|channel 0|1` | analog channel, not pin |
| `firmata_encode_digital_report(port, enable)` | `d0|port 0|1` | port 0..15 |
| `firmata_encode_system_reset()` | `ff` | |

## Decode

`firmata_frame_len` reports the complete frame length at the front of a
buffer (`0` = need more bytes) and rejects bad status bytes. It is the
streaming primitive used by the session.

| Decoder | Returns |
|---|---|
| `firmata_decode_frame(bytes)` | `FirmataMessage` enum: Version, Firmware, Digital, Analog, StringData, ReportAnalog, ReportDigital, SetPinMode, SetDigitalPin, SystemReset, Other |
| `firmata_decode_version_message(bytes)` | `FirmataVersion{major, minor}` |
| `firmata_decode_firmware_message(bytes)` | `FirmataFirmware{major, minor, name}` |
| `firmata_decode_digital_message(bytes)` | `FirmataDigital{port, mask}` |
| `firmata_decode_analog_message(bytes)` | `FirmataAnalog{channel, value}` |
| `firmata_decode_string_message(bytes)` | `Str` (2 x 7-bit characters, UTF-8) |
| `firmata_digital_mask_pin(mask, bit)` | `Bool` (typed range errors) |

Decoding is strict: a decoder requires exactly one complete frame (trailing
bytes are `INVALID_ARG`), fixed frames reject an embedded status byte,
sysex frames reject interruptions, and string payloads must be an even
number of 7-bit groups. `STRING_DATA` and firmware names follow the
protocol's 14-bit-per-character encoding; a NUL code point terminates the
string (C-string transport semantics). Unknown but well-framed sysex ids
and MIDI realtime bytes decode as `Other{command, length}`.

## Typed errors

Every fallible API returns `Result[..., FirmataError]`, where
`FirmataError{kind, code, message}` carries a stable kind, an integer code
(offending byte/value/length, or 0) and a message. Kinds:
`INVALID_ARG` (1), `OUT_OF_RANGE` (2), `TRUNCATED` (3), `BAD_STATUS` (4),
`BAD_SYSEX` (5), `BAD_STRING` (6), `UNSUPPORTED` (7), `BUFFER_FULL` (8).
`firmata_error_name(kind)` and `firmata_mode_name(mode)` name the
catalogs. Public entry points validate arguments before touching state and
never panic on caller input.

## Optional xiom.serial wiring (documented, not a dependency)

`xiom.serial` is the lane's Win32 UART binding. The session has no serial
types; a host loop can adapt it in four lines:

```xiom
// Illustrative adapter -- not compiled by this package (no dependency).
// let rr = serial_read(&lib, &port, 256);        // typed TIMEOUT when idle
// if rr.is_ok { let _ = firmata_session_feed(&mut s, &rr.value); }
// let out = firmata_session_take_output(&mut s);
// if out.len() > 0 { let _ = serial_write(&lib, &port, &out); }
```

The board side is usually 57600 baud, 8N1 (the firmata.js default); the
host remains responsible for opening, configuring and closing the port.
No hardware is needed for the suite: feed recorded traces instead.

## SKIP behavior

- No transport/hardware: the pure leg runs every codec, fixture, session
  and error check; one explicit `transport: SKIP ...` note is reported as
  a pass.
- A file fixture that is missing is a FAIL (fixtures are repository
  artifacts, not optional hardware).

## Limitations (0.1.0)

- Fixed message subset only: no I2C, OneWire, capability query/response,
  analog mapping, pin state, sampling interval, servo config, shift,
  stepper, encoder, serial feature, or EXTENDED_ANALOG (pins > 15).
- No response timeouts inside the session: the host loop owns time (send a
  query, then decide when to retry).
- PWM values are 14-bit on the wire (`0..16383`); a board with 8-bit PWM
  may clamp. No board-specific resolution query in 0.1.0.
- No sysex payload passthrough beyond command/length in `Other`.

## Evidence

- Suite: `scripts/port.ps1 -Package xiom.firmata -TimeoutSec 300` --
  **122/122 x2** on v0.64.7 (logs `%TEMP%\kilo\firmata-runs\run-a/b.log`;
  recorded in `STATUS.json` at commit `4113fb53`).
- Per-function coverage: `docs/COVERAGE.md`; byte tables, declared subset
  and re-pin procedure: `SPEC.md`; upstream references: `PROVENANCE.md`;
  lane audit and probes: `AUDIT.md`.
