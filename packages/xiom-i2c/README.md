# xiom.i2c

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM I2C/SMBus codec: 7-bit address bytes
> (`address << 1 | R/W`) with reserved-range validation, the 10-bit two-byte
> addressing form, a typed START / repeated START / STOP / address / data /
> ACK / NACK event model with a tagged stream encode/decode round-trip, the
> SMBus PEC (CRC-8, polynomial 0x07, initial value 0x00) and SMBus
> quick/send-byte builders.
> **Deps:** `xiom.std` only. The library module is dependency-free (no `use`
> at all); the tests use `xiom.test`, `xiom.io`, `xiom.string`,
> `xiom.string.compare`, `xiom.convert.int` and `xiom.encoding.hex` from it.
> No FFI.

## What it is

`xiom.i2c` models I2C transfers at the byte/event level. It does not touch a
bus: it converts between address forms, a logical event sequence and an
in-memory byte stream, applying the protocol's validation rules and
reporting deterministic errors that carry byte or event offsets.

- **7-bit addressing.** `i2c_addr7_wire_byte(address, read)` produces the
  on-the-wire address byte (`address * 2 + R/W`) and rejects addresses
  outside 0..127 and the reserved ranges `0x00..0x07` and `0x78..0x7F`.
  `i2c_addr7_from_wire(byte)` decodes a byte back into an address plus
  direction.
- **10-bit addressing.** `i2c_addr10_high_byte` / `i2c_addr10_low_byte`
  produce the two-byte form (`1111 0xx` lead byte plus the low byte) for
  addresses 8..1015 (0x008..0x3F7); `i2c_addr10_from_bytes` decodes it.
- **Event model.** An `I2cTransaction` is two index-aligned `Vec[Int]`
  arrays (`kinds`, `values`); builders append START, repeated START, STOP,
  7-bit and 10-bit address events, data bytes, ACK and NACK, mirroring every
  push into both arrays. `i2c_txn_validate` enforces the framing rules: first
  event START, last STOP, address and data events acknowledged, ACK/NACK
  only after an address or data event, repeated START after an ACK/NACK,
  and exactly one START at position 0.
- **Stream codec.** `i2c_events_encode` serializes a transaction into a
  tagged byte stream (one tag byte plus payload per event);
  `i2c_events_decode` parses it back and validates it, so every accepted
  stream round-trips field for field.
- **SMBus PEC.** `i2c_pec` is the SMBus CRC-8 (polynomial 0x07, init 0x00,
  no reflection, no final XOR; catalogue check value `0xF4` over
  `"123456789"`). `i2c_pec_cover` returns a copy of a frame with its PEC
  appended; `i2c_pec_verify` validates a PEC-protected frame.
- **SMBus helpers.** `smbus_quick(address, read)` and
  `smbus_send_byte(address, value)` build the corresponding transactions.

## Stream format

| Byte | Meaning |
|---|---|
| `0x01` | START |
| `0x02` | repeated START |
| `0x03` | STOP |
| `0x04` + addr | 7-bit address, write (payload = 7-bit address) |
| `0x05` + addr | 7-bit address, read |
| `0x06` + hi + lo | 10-bit address, write (payload = high, low) |
| `0x07` + hi + lo | 10-bit address, read |
| `0x08` + byte | data byte |
| `0x09` | ACK |
| `0x0A` | NACK |

The tag value is the event kind constant itself. This is a logical tagged
serialization of the event model, not a raw bus capture: the physical
address byte is derived with `i2c_addr7_wire_byte`, and on a real bus the
ACK/NACK bits share the ninth clock slot of each byte.

## API

| Function | Returns | Description |
|---|---|---|
| `i2c_addr7_ok(address)` | `Bool` | Valid, non-reserved 7-bit address (8..119). |
| `i2c_addr10_ok(address)` | `Bool` | Valid, non-reserved 10-bit address (8..1015). |
| `i2c_addr7_wire_byte(address, read)` | `Result[Int, Str]` | Wire byte `address * 2 + R/W`, validated. |
| `i2c_addr7_from_wire(byte)` | `Result[I2cAddr, Str]` | Decode a wire byte into address + direction. |
| `i2c_addr10_high_byte(address, read)` | `Result[Int, Str]` | Lead byte `1111 0xx` + R/W, validated. |
| `i2c_addr10_low_byte(address)` | `Result[Int, Str]` | Low address byte, validated. |
| `i2c_addr10_from_bytes(high, low)` | `Result[I2cAddr, Str]` | Decode the two-byte form. |
| `i2c_kind_name(kind)` | `Str` | Human-readable event kind name. |
| `i2c_txn_new()` | `I2cTransaction` | Empty transaction. |
| `i2c_txn_len(txn)` | `Int` | Event count. |
| `i2c_txn_kind(txn, i)` | `Int` | Kind of event `i`, or -1 out of range. |
| `i2c_txn_value(txn, i)` | `Int` | Payload of event `i`, or -1 out of range. |
| `i2c_txn_push_start/rstart/stop/ack/nack(txn)` | `Unit` | Append a control event. |
| `i2c_txn_push_addr7(txn, address, read)` | `Result[Unit, Str]` | Append a 7-bit address event (validated). |
| `i2c_txn_push_addr10(txn, address, read)` | `Result[Unit, Str]` | Append a 10-bit address event (validated). |
| `i2c_txn_push_data(txn, byte)` | `Result[Unit, Str]` | Append a data byte (0..255). |
| `i2c_txn_validate(txn)` | `Result[Unit, Str]` | Full framing and value validation. |
| `i2c_txn_equal(a, b)` | `Bool` | Same event kinds and values in order. |
| `i2c_event_encoded_len(kind)` | `Int` | Bytes one event occupies (or -1). |
| `i2c_txn_encoded_len(txn)` | `Int` | Bytes the whole stream occupies (or -1). |
| `i2c_events_encode(txn)` | `Result[Vec[UInt8], Str]` | Encode to a tagged stream. |
| `i2c_events_encode_into(out, txn)` | `Result[Unit, Str]` | Append to `out`; untouched on `Err`. |
| `i2c_events_decode(bytes)` | `Result[I2cTransaction, Str]` | Parse and validate a tagged stream. |
| `i2c_pec(data)` | `Int` | SMBus CRC-8 over `data` (0..255). |
| `i2c_pec_cover(frame)` | `Vec[UInt8]` | Copy of `frame` with its PEC appended. |
| `i2c_pec_verify(frame)` | `Result[Unit, Str]` | Validate the trailing PEC byte. |
| `smbus_quick(address, read)` | `Result[I2cTransaction, Str]` | SMBus Quick command transaction. |
| `smbus_send_byte(address, value)` | `Result[I2cTransaction, Str]` | SMBus Send Byte transaction. |

## Error model

Every failure is `Err(Str)` with a deterministic `i2c: ` message. Stream
errors carry the byte offset; structural errors carry the event index. The
full catalog and the exact check order live in SPEC.md.

| Condition | Error text |
|---|---|
| 7-bit address outside 0..127 | `i2c: 7-bit address out of range (v)` |
| 7-bit address 0x00..0x07 / 0x78..0x7F | `i2c: reserved 7-bit address (v)` |
| 10-bit address outside 0..1023 | `i2c: 10-bit address out of range (v)` |
| 10-bit address 0x000..0x007 / 0x3F8..0x3FF | `i2c: reserved 10-bit address (v)` |
| Raw address byte outside 0..255 | `i2c: address byte out of range (v)` |
| 10-bit lead byte outside 0xF0..0xF7 | `i2c: bad 10-bit address lead byte (v)` |
| Data byte outside 0..255 | `i2c: data byte out of range (v)` |
| `kinds.len() != values.len()` | `i2c: event arrays out of step (a kinds, b values)` |
| No events | `i2c: empty transaction` |
| First event not START | `i2c: event 0: transaction must begin with START` |
| Last event not STOP | `i2c: event n: transaction must end with STOP` |
| Unknown kind | `i2c: event i: invalid event kind (v)` |
| Control event with nonzero value | `i2c: event i: control event carries a value (v)` |
| ACK/NACK not after an address or data event | `i2c: event i: ACK or NACK without a preceding byte event` |
| Repeated START not after an ACK/NACK | `i2c: event i: repeated START without a preceding ACK or NACK` |
| Second START | `i2c: event i: START after position 0 (use repeated START)` |
| STOP not last | `i2c: event i: STOP before the end of the transaction` |
| Address/data not followed by ACK/NACK | `i2c: event i: address or data event not followed by ACK or NACK` |
| START/repeated START not followed by an address | `i2c: event i: START or repeated START not followed by an address event` |
| Stream ends inside a tag payload | `i2c: truncated event at byte i` |
| Unassigned tag byte | `i2c: unknown event tag (v) at byte i` |
| PEC frame shorter than 2 bytes | `i2c: short pec frame (n)` |
| Trailing PEC mismatch | `i2c: bad pec (computed c, received r)` |

`i2c_events_encode_into` validates before writing, so an `Err` leaves `out`
exactly as it was. `i2c_txn_push_addr7`, `i2c_txn_push_addr10` and
`i2c_txn_push_data` validate before pushing, so a failed builder call does
not change the transaction.

## Usage

```xi
use xiom.i2c;
use xiom.io;

// Build an SMBus Send Byte transaction to address 0x50, data 0x42.
let built = smbus_send_byte(80, 66);
if built.is_ok {
  let t: I2cTransaction = built.value;
  let e = i2c_events_encode(&t);
  if e.is_ok {
    let bytes: Vec[UInt8] = e.value;
    io.println(i2c_kind_name(i2c_txn_kind(&t, 1)));   // 7-bit address write
  }
  // PEC-protect the raw frame A0 44 01 (address byte, command, data).
  var frame = Vec[UInt8].new();
  frame.push(160);
  frame.push(68);
  frame.push(1);
  let covered = i2c_pec_cover(&frame);
  let vr = i2c_pec_verify(&covered);
  if vr.is_ok {
    io.println("PEC ok");                              // PEC ok
  }
}

// Decode a tagged stream back into a transaction.
let raw = xiom.encoding.hex.hex_decode("0104500903");
match raw {
  Ok(bytes) => {
    let d = i2c_events_decode(&bytes);
    if d.is_ok {
      let t: I2cTransaction = d.value;
      io.println(i2c_kind_name(i2c_txn_kind(&t, 1)));  // 7-bit address write
    }
  },
  Err(_) => {},
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.i2c
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No bus or controller I/O.** The package never opens a device, socket or
  file; it works on in-memory values. Clock stretching, arbitration, bus
  timing, bus recovery, electrical details and device state are not modeled.
- **Logical event stream, not a wire capture.** The tagged encoding is this
  package's serialization of the event model. It does not attempt to
  reproduce the physical waveform (ACK/NACK share the ninth clock, START and
  STOP are level transitions). The 7-bit wire byte is derived separately with
  `i2c_addr7_wire_byte`.
- **Reserved-address policy is strict.** All of 0x00..0x07 and 0x78..0x7F is
  rejected for 7-bit addresses (and 0x000..0x007 / 0x3F8..0x3FF for 10-bit).
  Applications that intentionally use General Call, SMBus Host or CBUS
  addresses must bypass these helpers and build events directly.
- **No clock-stretching or timeout modeling.** A transaction is a static
  event list; there is no notion of time or retry.
- **No 10-bit reserved-range exceptions.** 10-bit mode uses exactly the
  two-byte form; mixed 7-bit/10-bit transactions are not special-cased.
- **SMBus PEC is the only checksum.** The CRC-8 covers a byte sequence the
  caller assembles (address byte, command, data); the package does not
  decode SMBus command protocols (read/write word, block, process call, ...)
  beyond quick and send-byte.
- **Validation is single-threaded and value-based.** `I2cTransaction` is a
  plain value type; copies are O(events) and there is no interior state.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
