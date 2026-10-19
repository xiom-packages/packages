# SPEC: xiom.firmata -- Firmata 2.x host-side protocol bindings (pure XIOM)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.firmata` |
| Version | 0.1.0 |
| Kind | binding (host protocol codec; `keywords: ["binding"]`) |
| Target API | Firmata protocol 2.x, declared subset below (oracle: protocol 2.8.0) |
| Implementation oracle | `firmata/protocol` `protocol.md` @ `7908873e` (Firmata 2.8.0) |
| Reference client (NOT vendored) | `firmata/firmata.js` @ `4a3b86b4` (MIT), read-only cross-check |
| Package license | MIT OR Apache-2.0 |
| Platform | Any (pure XIOM; no FFI, no I/O, no C) |
| Compiler pin | v0.64.7 |
| Landing | bindings lane MCU Phase-1 wave 2026-10-19 (`BINDINGS-SESSION.md`) |

## 2. Decision: independent pure-XIOM implementation, no vendoring

Firmata is a wire protocol, not a library. The implementation is original
XIOM written against the protocol document and cross-checked, reference
only, against the MIT-licensed `firmata.js` client. No upstream code is
vendored, ported or copied; no C is shipped; there is no runtime library.
The package is therefore host-independent and the conformance suite runs
without hardware or a transport.

## 3. Wire format (declared subset)

### 3.1 Fixed frames

All data bytes are 7-bit (0..127). Multi-byte values are little-endian
7-bit groups: `value = lsb + msb * 128` (0..16383).

| Bytes | Status | Direction | Fields |
|---|---|---|---|
| `f9 major minor` | REPORT_VERSION `0xF9` | board -> host (query is `f9`) | major/minor 0..127 |
| `90\|port lsb msb` | DIGITAL_MESSAGE `0x90..0x9F` | both | port 0..15; 14-bit mask (bits 0..7 are the eight pins) |
| `e0\|channel lsb msb` | ANALOG_MESSAGE `0xE0..0xEF` | both (PWM out / analog in) | channel/pin 0..15; 14-bit value |
| `c0\|channel 0\|1` | REPORT_ANALOG `0xC0..0xCF` | host -> board | analog channel 0..15 |
| `d0\|port 0\|1` | REPORT_DIGITAL `0xD0..0xDF` | host -> board | port 0..15 |
| `f4 pin mode` | SET_PIN_MODE `0xF4` | host -> board | pin 0..127; mode 0..127 |
| `f5 pin 0\|1` | SET_DIGITAL_PIN_VALUE `0xF5` | host -> board | pin 0..127 (Firmata 2.5+) |
| `ff` | SYSTEM_RESET `0xFF` | host -> board | -- |

### 3.2 Sysex frames

`f0 id payload... f7`, where every byte between the framing bytes is
7-bit. Declared ids:

| Id | Name | Payload | Decode |
|---|---|---|---|
| `0x71` | STRING_DATA | characters, 2 x 7-bit each | `StringData(Str)` |
| `0x79` | REPORT_FIRMWARE | major, minor, name chars (2 x 7-bit each) | `Firmware{major, minor, name}` |
| other | -- | -- | `Other{command: id, length}` |

A REPORT_FIRMWARE frame with zero payload (`f0 79 f7`) is the host query
and decodes as `Other{command: 0x79, length: 0}`. A payload of exactly one
byte is malformed (`BAD_SYSEX`).

Characters: `char = lsb + msb * 128` (14-bit code point). The decoder
encodes the code point as UTF-8 (valid for the full 14-bit range), and a
zero code point terminates the string (C-string transport semantics). A
name/payload with an odd number of 7-bit groups is `BAD_STRING`.

### 3.3 Framing rules

`firmata_frame_len` returns:

- `0` -- incomplete: empty buffer, short fixed frame, or sysex without
  `0xF7` yet;
- `n` -- one complete frame of `n` bytes;
- `BAD_STATUS` -- first byte is not a declared Firmata status (or a
  declared MIDI realtime byte);
- `BAD_SYSEX` -- a status byte (>= 0x80 other than `0xF7`) interrupts a
  sysex frame.

Recognized one-byte MIDI realtime statuses: `0xF8`, `0xFA`, `0xFB`,
`0xFC`, `0xFE` (decoded as `Other`). Other MIDI statuses are outside the
declared set and are rejected as `BAD_STATUS` so the caller resynchronizes
quickly on a dedicated Firmata link.

`firmata_decode_frame` requires exactly one complete frame: fewer bytes are
`TRUNCATED`, trailing bytes are `INVALID_ARG`. Fixed frames reject a status
byte embedded in a data position (`BAD_STATUS`).

## 4. Declared surface (0.1.0) -- 32 public functions

**Encoders (9):** `firmata_encode_version_query`,
`firmata_encode_firmware_query`, `firmata_encode_set_pin_mode`,
`firmata_encode_digital_write`, `firmata_encode_digital_port_write`,
`firmata_encode_pwm_write`, `firmata_encode_analog_report`,
`firmata_encode_digital_report`, `firmata_encode_system_reset`.

**Framing/decode (7):** `firmata_frame_len`, `firmata_decode_frame`,
`firmata_decode_version_message`, `firmata_decode_firmware_message`,
`firmata_decode_digital_message`, `firmata_decode_analog_message`,
`firmata_decode_string_message`.

**Helpers/catalogs (3):** `firmata_digital_mask_pin`,
`firmata_error_name`, `firmata_mode_name`.

**Session (13):** `firmata_session_new`, `firmata_session_reset`,
`firmata_session_feed`, `firmata_session_pending`,
`firmata_session_poll`, `firmata_session_begin_handshake`,
`firmata_session_is_ready`, `firmata_session_set_pin_mode`,
`firmata_session_digital_write`, `firmata_session_pwm_write`,
`firmata_session_enable_analog_report`,
`firmata_session_enable_digital_report`,
`firmata_session_take_output`.

**Constants:** statuses (`FIRMATA_ANALOG_MESSAGE`, `FIRMATA_DIGITAL_MESSAGE`,
`FIRMATA_REPORT_ANALOG`, `FIRMATA_REPORT_DIGITAL`, `FIRMATA_SET_PIN_MODE`,
`FIRMATA_SET_DIGITAL_PIN_VALUE`, `FIRMATA_START_SYSEX`,
`FIRMATA_END_SYSEX`, `FIRMATA_REPORT_VERSION`, `FIRMATA_SYSTEM_RESET`,
`FIRMATA_STRING_DATA`, `FIRMATA_REPORT_FIRMWARE`); modes
(`FIRMATA_MODE_INPUT/OUTPUT/ANALOG/PWM/SERVO/SHIFT/I2C/ONEWIRE/STEPPER/
ENCODER/SERIAL/PULLUP`); ranges (`FIRMATA_MAX_PIN` 127, `FIRMATA_MAX_PORT`
15, `FIRMATA_MAX_ANALOG_CHANNEL` 15, `FIRMATA_MAX_7BIT` 127,
`FIRMATA_MAX_14BIT` 16383, `FIRMATA_SESSION_PORTS` 16,
`FIRMATA_RX_LIMIT_DEFAULT` 4096); error kinds (`FIRMATA_ERR_*`).

### 4.1 Argument ranges

| Function family | Validation |
|---|---|
| set pin mode | pin 0..127, mode 0..127 |
| digital write (pin) | pin 0..127, value is `Bool` |
| digital port write | port 0..15, mask 0..16383 |
| PWM write | pin 0..15, value 0..16383 |
| analog report | channel 0..15, value is `Bool` |
| digital report | port 0..15, value is `Bool` |
| session digital write | pin 0..127 (port = pin/8, bit = pin%8); the 16-entry port shadow must be intact (`INVALID_ARG` otherwise, no panic) |
| digital mask helper | mask 0..16383, bit 0..13 |

Violations return `OUT_OF_RANGE` with the offending value in `code`; a
session wrapper queues nothing on error.

## 5. Typed error model

| Kind | Value | Meaning |
|---|---|---|
| `FIRMATA_ERR_INVALID_ARG` | 1 | malformed argument/frame shape (e.g. trailing bytes) |
| `FIRMATA_ERR_OUT_OF_RANGE` | 2 | value outside a declared range |
| `FIRMATA_ERR_TRUNCATED` | 3 | incomplete frame passed to a decoder |
| `FIRMATA_ERR_BAD_STATUS` | 4 | unrecognized/interrupting status byte |
| `FIRMATA_ERR_BAD_SYSEX` | 5 | malformed/interrupted sysex |
| `FIRMATA_ERR_BAD_STRING` | 6 | malformed 2 x 7-bit string payload |
| `FIRMATA_ERR_UNSUPPORTED` | 7 | wrong message type for a typed decoder |
| `FIRMATA_ERR_BUFFER_FULL` | 8 | session receive buffer would exceed `rx_limit` |

`code` carries the offending byte, value or length (0 where none applies);
`message` is a stable human-readable string. Public functions never panic
on caller input (no input-condition `requires` clauses).

## 6. Session and transport contract

`FirmataSession` fields: `rx` (received bytes), `out` (queued host bytes),
`ports` (16-entry digital output shadow), `rx_limit` (default 4096),
`version_received`, `version_major`, `version_minor`,
`firmware_received`, `firmware_name`.

- **Feed:** `firmata_session_feed` appends bytes and returns the count
  accepted. It is all-or-nothing: if `rx.len() + input.len() > rx_limit`
  it appends nothing and returns `BUFFER_FULL`.
- **Poll:** `firmata_session_poll` returns `Ok(Some(msg))`,
  `Ok(None)` (need more bytes) or `Err`. On a framing error it consumes
  one byte; on a decode error it consumes the whole malformed frame. The
  caller may therefore keep polling to resynchronize on the next valid
  status byte. Successfully decoded Version/Firmware update the handshake
  state; a decoded Digital report updates the port shadow.
- **Handshake:** `firmata_session_begin_handshake` queues
  `f9 f0 79 f7` (version then firmware query). The session is ready when
  **both** reports have been decoded.
- **Output:** encoders/session wrappers append to `out`;
  `firmata_session_take_output` returns the queued bytes and empties the
  queue.
- **Digital write:** the session writes the classic port message
  (`90|port`), updating the shadow so sequential writes to the same port
  coalesce. The pin-addressed `f5` encoder remains available as
  `firmata_encode_digital_write`.
- **Reset:** clears `rx`, `out`, the port shadow and the handshake flags;
  `rx_limit` is preserved.
- **No I/O:** the module never opens a port. A device adapter reads bytes
  and calls `feed`, then writes `take_output` to the transport. The
  optional `xiom.serial` recipe is documented in README.md; it is not a
  dependency and is not compiled here.

## 7. 100% coverage table (0.1.0)

The suite (`tests/test_conformance.xi`, 122 checks) covers every public
function. Representative checks (full names and the complete matrix are in
`docs/COVERAGE.md`):

| Public function | Checks |
|---|---|
| `firmata_encode_version_query` | `encode: version query -> f9`; golden stream |
| `firmata_encode_firmware_query` | `encode: firmware query -> f0 79 f7`; golden stream |
| `firmata_encode_set_pin_mode` | 3 byte goldens + 3 range rejections |
| `firmata_encode_digital_write` | 2 byte goldens + range rejection |
| `firmata_encode_digital_port_write` | 2 byte goldens + 2 range rejections |
| `firmata_encode_pwm_write` | 2 byte goldens + 2 range rejections |
| `firmata_encode_analog_report` | 2 byte goldens + range rejection |
| `firmata_encode_digital_report` | 2 byte goldens + range rejection |
| `firmata_encode_system_reset` | byte golden; golden stream |
| `firmata_frame_len` | 16 checks: all declared lengths, incomplete, bad status, interrupted sysex |
| `firmata_decode_frame` | handshake, 10 IO/report/set/reset frames, 3 Other frames, 9 error shapes |
| `firmata_decode_version_message` | happy path + wrong-type (`UNSUPPORTED`) |
| `firmata_decode_firmware_message` | happy path + wrong-type |
| `firmata_decode_digital_message` | happy path + wrong-type |
| `firmata_decode_analog_message` | happy path + wrong-type |
| `firmata_decode_string_message` | 4 strings (ASCII/UTF-8/NUL/empty) + wrong-type |
| `firmata_digital_mask_pin` | 4 set/clear bits + 3 range rejections |
| `firmata_error_name` | all 8 kinds + `UNKNOWN` |
| `firmata_mode_name` | all 12 named modes + `UNKNOWN` |
| `firmata_session_new` | shadow/limit/ready defaults; buffer-limit path |
| `firmata_session_reset` | clears state, preserves `rx_limit` |
| `firmata_session_feed` | empty input, accepted trace, `BUFFER_FULL` |
| `firmata_session_pending` | 0 after handshake; 0 after malformed-frame resync |
| `firmata_session_poll` | handshake, byte-at-a-time, IO shadow, 4 resync scenarios |
| `firmata_session_begin_handshake` | queues `f9 f0 79 f7` |
| `firmata_session_is_ready` | false before, true after both reports |
| `firmata_session_set_pin_mode` | queue golden + invalid-queues-nothing |
| `firmata_session_digital_write` | 5 writes incl. shadow accumulation/clear + incoming update; short-shadow guard -> `INVALID_ARG` |
| `firmata_session_pwm_write` | queue golden + invalid |
| `firmata_session_enable_analog_report` | queue golden + invalid |
| `firmata_session_enable_digital_report` | queue golden + invalid |
| `firmata_session_take_output` | drain content, second drain empty, reset clears |

Constants/status families are exercised by the encoders, decoders and mode
name catalog; every `FIRMATA_MODE_*` value is asserted through
`firmata_mode_name`.

## 8. Deliberate deviations and limitations

1. **STRING_DATA decode** follows the protocol's 2 x 7-bit character
   definition; the firmata.js client slices raw bytes in `STRING_DATA`.
   ASCII payloads are identical; the protocol-faithful form is implemented.
2. **Firmware names** are decoded as 14-bit code points and UTF-8 encoded.
   firmata.js masks each pair to 8 bits; again ASCII names such as
   `StandardFirmata` are byte-identical.
3. **PWM pin range** is 0..15 (ANALOG_MESSAGE). The protocol's
   EXTENDED_ANALOG sysex for pins > 15 is out of scope.
4. **No response timeouts** inside the session; the host loop owns time.
5. **Other sysex** is surfaced as `Other{command, length}` without payload
   passthrough.
6. **Strict fixed-frame decode** rejects an embedded status byte rather
   than guessing; the session resynchronizes on the next poll.

Explicit non-goals (0.1.0): I2C, OneWire, capability query/response,
analog mapping, pin state, sampling interval, servo config, shift,
stepper, encoder, serial feature, EXTENDED_ANALOG, hardware capture and
transport management. See `ROADMAP.md`.

## 9. Re-pin / refresh procedure

1. Fetch the protocol document at the pinned commit
   (`firmata/protocol` `7908873e`); diff the declared frame tables against
   sec. 3. A protocol change that touches the subset requires a package
   version bump and updated goldens.
2. Re-read the reference client (`firmata/firmata.js` `4a3b86b4`) only to
   cross-check semantics; never copy code. Update `PROVENANCE.md` if the
   pin moves.
3. Update `tests/fixtures/*.hex` and the expected values together.
4. Re-run `scripts/port.ps1 -Package xiom.firmata -TimeoutSec 300` x2 and
   record the result in `STATUS.json` / README / AUDIT in one commit.
