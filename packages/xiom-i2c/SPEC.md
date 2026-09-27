# xiom.i2c -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.i2c`, version `0.1.0`).
Module: `src/i2c.xi` (`module xiom.i2c`).
Depends on `xiom.std`; the library module imports nothing from it (tests add
`xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare`,
`xiom.convert.int`, `xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI, no bus I/O) codec for I2C/SMBus byte-level transfers:

- `I2cAddr` -- a decoded address (7-bit 0..127 or 10-bit 0..1023) plus its
  direction (`read` bool);
- `I2cTransaction` -- a logical transaction as two index-aligned `Vec[Int]`
  arrays (`kinds`, `values`);
- 7-bit address byte encoding (`address << 1 | R/W`) and decoding, with
  reserved-range validation;
- the 10-bit two-byte addressing form (`1111 0xx` lead byte plus the low
  address byte) and decoding;
- the typed event model: START, repeated START, STOP, 7-bit/10-bit address
  events, data bytes, ACK and NACK, with structural validation, a tagged
  stream encoding and a decoding round-trip;
- SMBus PEC: CRC-8 with polynomial 0x07 (`x^8 + x^2 + x + 1`), initial value
  0x00, no reflection, no final XOR, plus cover and verify helpers;
- SMBus quick and send-byte transaction builders;
- deterministic `Err(Str)` messages that carry the byte offset (stream
  errors) or the event index (structural errors).

## Non-goals

- **Bus/controller I/O.** No device files, sockets, ioctl or file access;
  everything operates on in-memory values.
- **Wire timing and electrical behavior.** No clock stretching, arbitration,
  bus timing, bus recovery, glitch filtering or timeouts; a transaction is a
  static event list.
- **Physical waveform reproduction.** The tagged event stream is this
  package's logical serialization (see the table below); it is not a capture
  format for the physical bus.
- **SMBus command protocols.** Only Quick and Send Byte transaction shapes
  are built; Read/Write Byte/Word/Block, Process Call, Block Read/Write and
  the Alert Response Address flow are out of scope.
- **PEC framing of SMBus protocols.** `i2c_pec_cover` / `i2c_pec_verify`
  operate on a caller-assembled byte sequence, not on a decoded protocol.
- **7-bit reserved-address exceptions.** General Call, CBUS, HS-mode and
  SMBus Host addresses (0x00..0x07) and the 0x78..0x7F range are rejected by
  the address helpers; callers who need them must build events directly.
- **Streaming/multi-transaction decode.** `i2c_events_decode` consumes the
  whole buffer and expects exactly one transaction; it does not split a
  stream of concatenated transactions.

## Address model

### 7-bit

A 7-bit address is 0..127. The reserved ranges are 0x00..0x07 and
0x78..0x7F. The wire byte is:

```
byte = address * 2 + (1 if read else 0)        // 0x10..0xEF, even = write
```

`i2c_addr7_wire_byte` validates before computing; `i2c_addr7_from_wire`
inverts (`address = byte / 2`, `read = (byte % 2 == 1)`) and rejects a
reserved decoded address (which also rejects every 10-bit lead byte, since
those decode to the reserved 0x78..0x7F range).

### 10-bit

A 10-bit address is 0..1023. The reserved ranges are 0x000..0x007 and
0x3F8..0x3FF. The two-byte form is:

```
high = 0xF0 + (address / 256) * 2 + (1 if read else 0)   // 0xF0..0xF7
low  = address % 256
```

`i2c_addr10_high_byte` and `i2c_addr10_low_byte` validate before computing;
`i2c_addr10_from_bytes` requires `high` in 0xF0..0xF7 (a `1111 0xx` lead
byte) and `low` in 0..255, then decodes
`address = ((high - 0xF0) / 2) * 256 + low` and `read = (high % 2 == 1)`.

## Event model

`I2cTransaction` fields:

| Field | Type | Meaning |
|---|---|---|
| `kinds` | `Vec[Int]` | event kind per position |
| `values` | `Vec[Int]` | event payload per position |

The two arrays are index-aligned; builders always push to both. Never push
to one without the other.

| Kind constant | Value | Payload (`values[i]`) |
|---|---|---|
| `I2C_EV_START` | 1 | 0 |
| `I2C_EV_RSTART` | 2 | 0 |
| `I2C_EV_STOP` | 3 | 0 |
| `I2C_EV_ADDR7_W` | 4 | 7-bit address (8..119) |
| `I2C_EV_ADDR7_R` | 5 | 7-bit address (8..119) |
| `I2C_EV_ADDR10_W` | 6 | 10-bit address (8..1015) |
| `I2C_EV_ADDR10_R` | 7 | 10-bit address (8..1015) |
| `I2C_EV_DATA` | 8 | data byte (0..255) |
| `I2C_EV_ACK` | 9 | 0 |
| `I2C_EV_NACK` | 10 | 0 |

Control events (START, repeated START, STOP, ACK, NACK) carry payload 0.
Address events carry the logical address, not the wire byte.

## Event stream format

One tag byte per event; the tag value equals the kind constant. Payload
bytes follow the tag:

| Tag | Payload | Total size |
|---|---|---|
| `0x01` START | none | 1 |
| `0x02` repeated START | none | 1 |
| `0x03` STOP | none | 1 |
| `0x04` 7-bit address write | 1 byte (7-bit address) | 2 |
| `0x05` 7-bit address read | 1 byte (7-bit address) | 2 |
| `0x06` 10-bit address write | 2 bytes (high, low) | 3 |
| `0x07` 10-bit address read | 2 bytes (high, low) | 3 |
| `0x08` data byte | 1 byte | 2 |
| `0x09` ACK | none | 1 |
| `0x0A` NACK | none | 1 |

Example -- SMBus Send Byte to 0x50 with data 0x42:
`01 04 50 09 08 42 09 03`
(START, address write, ACK, data, ACK, STOP).

Example -- a 10-bit read of 0x2A3 followed by a repeated START and a write
of the same address, then one zero byte:
`01 07 02 A3 09 02 06 02 A3 09 08 00 09 03`.

`i2c_events_encode` validates first, so an invalid transaction is an `Err`
and no bytes are produced. `i2c_events_encode_into` appends only on success
(atomic failure). `i2c_events_decode` parses the tags, then runs the full
validation, so every accepted stream round-trips field for field through
`i2c_txn_equal`.

## Validation rules

`i2c_txn_validate` checks, in exactly this order, and reports the first
failure:

1. `kinds.len() != values.len()` -> `i2c: event arrays out of step
   (a kinds, b values)`;
2. no events -> `i2c: empty transaction`;
3. `kinds[0] != START` -> `i2c: event 0: transaction must begin with
   START`;
4. `kinds[n-1] != STOP` -> `i2c: event n: transaction must end with STOP`;
5. for each event `i` from 0 to n-1, in this order:
   1. kind outside 1..10 -> `i2c: event i: invalid event kind (v)`;
   2. control event with `values[i] != 0` -> `i2c: event i: control event
      carries a value (v)`;
   3. ADDR7 event: 7-bit address range and reserved rules;
   4. ADDR10 event: 10-bit address range and reserved rules;
   5. DATA event: value outside 0..255 -> `i2c: event i: data byte out of
      range (v)`;
   6. ACK/NACK whose predecessor (`i-1`) is missing or not an address/data
      event -> `i2c: event i: ACK or NACK without a preceding byte event`;
   7. repeated START whose predecessor is missing or not ACK/NACK ->
      `i2c: event i: repeated START without a preceding ACK or NACK`
      (defensive; earlier checks reject every malformed stream that could
      reach it);
   8. START at `i != 0` -> `i2c: event i: START after position 0 (use
      repeated START)`;
   9. STOP at `i != n-1` -> `i2c: event i: STOP before the end of the
      transaction`;
   10. address/data event with no next event or a next event that is not
       ACK/NACK -> `i2c: event i: address or data event not followed by ACK
       or NACK`;
   11. START/repeated START with no next event or a next event that is not
       an address event -> `i2c: event i: START or repeated START not
       followed by an address event`.

Because rules 3 and 4 run before the loop, malformed transactions that both
lack a trailing STOP and contain an internal framing error report the
missing STOP first.

## Decode order

`i2c_events_decode` walks the buffer:

1. tag 1, 2, 3, 9 or 10 -> append a control event, advance 1 byte;
2. tag 4, 5 or 8 -> require one payload byte, else `i2c: truncated event at
   byte i`; append the address/data event, advance 2 bytes;
3. tag 6 or 7 -> require two payload bytes, else `i2c: truncated event at
   byte i`; append the 10-bit address event, advance 3 bytes;
4. any other tag -> `i2c: unknown event tag (v) at byte i`;
5. after the walk, run `i2c_txn_validate` and propagate its error (so an
   empty buffer is `i2c: empty transaction`, and framing errors carry event
   indexes).

## Error string catalog

| Condition | Error text |
|---|---|
| 7-bit address outside 0..127 | `i2c: 7-bit address out of range (v)` |
| 7-bit address in 0x00..0x07 or 0x78..0x7F | `i2c: reserved 7-bit address (v)` |
| 10-bit address outside 0..1023 | `i2c: 10-bit address out of range (v)` |
| 10-bit address in 0x000..0x007 or 0x3F8..0x3FF | `i2c: reserved 10-bit address (v)` |
| raw address byte outside 0..255 | `i2c: address byte out of range (v)` |
| 10-bit lead byte outside 0xF0..0xF7 | `i2c: bad 10-bit address lead byte (v)` |
| data value outside 0..255 | `i2c: data byte out of range (v)` |
| arrays out of step | `i2c: event arrays out of step (a kinds, b values)` |
| no events | `i2c: empty transaction` |
| first event not START | `i2c: event 0: transaction must begin with START` |
| last event not STOP | `i2c: event n: transaction must end with STOP` |
| unknown kind | `i2c: event i: invalid event kind (v)` |
| control event with a nonzero payload | `i2c: event i: control event carries a value (v)` |
| ACK/NACK predecessor invalid | `i2c: event i: ACK or NACK without a preceding byte event` |
| repeated START predecessor invalid | `i2c: event i: repeated START without a preceding ACK or NACK` |
| second START | `i2c: event i: START after position 0 (use repeated START)` |
| STOP not last | `i2c: event i: STOP before the end of the transaction` |
| address/data not acknowledged | `i2c: event i: address or data event not followed by ACK or NACK` |
| START/repeated START not followed by an address | `i2c: event i: START or repeated START not followed by an address event` |
| stream ends inside a payload | `i2c: truncated event at byte i` |
| unassigned tag byte | `i2c: unknown event tag (v) at byte i` |
| PEC frame shorter than 2 bytes | `i2c: short pec frame (n)` |
| trailing PEC mismatch | `i2c: bad pec (computed c, received r)` |

All values (`v`, `i`, `n`, `a`, `b`, `c`, `r`) are decimal.

## SMBus PEC

`i2c_pec(data)` is CRC-8 with polynomial 0x07 (x^8 + x^2 + x + 1), initial
value 0x00, no reflection and no final XOR, processed MSB-first, one byte at
a time; the register is masked to 8 bits after every step. An empty input
returns 0. Catalogue check: `"123456789"` -> 244 (0xF4).

`i2c_pec_cover(frame)` returns a fresh vector: the bytes of `frame` followed
by its PEC byte. Consequence: `i2c_pec` over the covered frame is 0.

`i2c_pec_verify(frame)` treats the last byte as the PEC and computes the
CRC-8 over the preceding bytes. Frames shorter than 2 bytes are
`i2c: short pec frame (n)`; a mismatch is
`i2c: bad pec (computed c, received r)`.

## SMBus helpers

`smbus_quick(address, read)` builds START, the 7-bit address event with the
requested direction, ACK, STOP.

`smbus_send_byte(address, value)` builds START, the 7-bit address event
(write), ACK, the data byte, ACK, STOP.

Both return the validation catalog of their inputs and build nothing on
`Err`.

## API contract

All functions are free functions in module `xiom.i2c`:

```xi
pub type I2cAddr = {
  address: Int;
  read: Bool;
}

pub type I2cTransaction = {
  kinds: Vec[Int];
  values: Vec[Int];
}

pub const I2C_EV_START: Int = 1;
pub const I2C_EV_RSTART: Int = 2;
pub const I2C_EV_STOP: Int = 3;
pub const I2C_EV_ADDR7_W: Int = 4;
pub const I2C_EV_ADDR7_R: Int = 5;
pub const I2C_EV_ADDR10_W: Int = 6;
pub const I2C_EV_ADDR10_R: Int = 7;
pub const I2C_EV_DATA: Int = 8;
pub const I2C_EV_ACK: Int = 9;
pub const I2C_EV_NACK: Int = 10;

pub fn i2c_addr7_ok(address: Int) -> Bool
pub fn i2c_addr10_ok(address: Int) -> Bool
pub fn i2c_addr7_wire_byte(address: Int, read: Bool) -> Result[Int, Str]
pub fn i2c_addr7_from_wire(byte: Int) -> Result[I2cAddr, Str]
pub fn i2c_addr10_high_byte(address: Int, read: Bool) -> Result[Int, Str]
pub fn i2c_addr10_low_byte(address: Int) -> Result[Int, Str]
pub fn i2c_addr10_from_bytes(high: Int, low: Int) -> Result[I2cAddr, Str]
pub fn i2c_kind_name(kind: Int) -> Str
pub fn i2c_txn_new() -> I2cTransaction
pub fn i2c_txn_len(t: &I2cTransaction) -> Int
pub fn i2c_txn_kind(t: &I2cTransaction, i: Int) -> Int
pub fn i2c_txn_value(t: &I2cTransaction, i: Int) -> Int
pub fn i2c_txn_push_start(t: &mut I2cTransaction)
pub fn i2c_txn_push_rstart(t: &mut I2cTransaction)
pub fn i2c_txn_push_stop(t: &mut I2cTransaction)
pub fn i2c_txn_push_ack(t: &mut I2cTransaction)
pub fn i2c_txn_push_nack(t: &mut I2cTransaction)
pub fn i2c_txn_push_addr7(t: &mut I2cTransaction, address: Int, read: Bool) -> Result[Unit, Str]
pub fn i2c_txn_push_addr10(t: &mut I2cTransaction, address: Int, read: Bool) -> Result[Unit, Str]
pub fn i2c_txn_push_data(t: &mut I2cTransaction, byte: Int) -> Result[Unit, Str]
pub fn i2c_txn_validate(t: &I2cTransaction) -> Result[Unit, Str]
pub fn i2c_txn_equal(a: &I2cTransaction, b: &I2cTransaction) -> Bool
pub fn i2c_event_encoded_len(kind: Int) -> Int
pub fn i2c_txn_encoded_len(t: &I2cTransaction) -> Int
pub fn i2c_events_encode(t: &I2cTransaction) -> Result[Vec[UInt8], Str]
pub fn i2c_events_encode_into(out: &mut Vec[UInt8], t: &I2cTransaction) -> Result[Unit, Str]
pub fn i2c_events_decode(bytes: &Vec[UInt8]) -> Result[I2cTransaction, Str]
pub fn i2c_pec(data: &Vec[UInt8]) -> Int
pub fn i2c_pec_cover(frame: &Vec[UInt8]) -> Vec[UInt8]
pub fn i2c_pec_verify(frame: &Vec[UInt8]) -> Result[Unit, Str]
pub fn smbus_quick(address: Int, read: Bool) -> Result[I2cTransaction, Str]
pub fn smbus_send_byte(address: Int, value: Int) -> Result[I2cTransaction, Str]
```

`i2c_txn_kind` / `i2c_txn_value` report an out-of-range index as -1 (no
error channel). `i2c_event_encoded_len` reports an unknown kind as -1;
`i2c_txn_encoded_len` reports -1 when any event kind is unknown.

## Complexity

| Operation | Complexity |
|---|---|
| address helpers (`i2c_addr7_*`, `i2c_addr10_*`) | O(1) |
| `i2c_kind_name`, `i2c_txn_len`, `i2c_txn_kind`, `i2c_txn_value` | O(1) |
| `i2c_txn_push_*` | O(1) |
| `i2c_txn_validate`, `i2c_txn_equal` | O(events) |
| `i2c_event_encoded_len`, `i2c_txn_encoded_len` | O(events) |
| `i2c_events_encode`, `i2c_events_encode_into` | O(events) |
| `i2c_events_decode` | O(bytes) |
| `i2c_pec`, `i2c_pec_cover`, `i2c_pec_verify` | O(bytes) |
| `smbus_quick`, `smbus_send_byte` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module i2c_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Coverage:

1. 7-bit wire byte encode at both reserved-range edges (0x08, 0x77) for
   both directions;
2. 7-bit validation catalog: out-of-range and reserved addresses;
3. 7-bit decode round-trip and rejection of reserved/out-of-range bytes;
4. 10-bit byte pair encode for 0x2A3, 0x100, 0x3F7 and the error catalog;
5. 10-bit decode round-trip, bad lead bytes, reserved decoded address;
6. builders append mirrored events; accessors; out-of-range indexes; atomic
   `Err` push leaves the transaction unchanged;
7. well-formed write and read transactions validate; all kind names pinned;
8. validation: empty, single event, missing START, START not followed by an
   address;
9. validation: ACK framing, second START, repeated START placement, STOP not
   last;
10. validation: control payloads, reserved addresses, data range, wrong
    kind, array skew;
11. write and repeated-START read transactions encode to pinned streams;
12. 10-bit address events encode with high-then-low payload bytes;
13. encode -> decode round-trips the write and 10-bit read transactions;
14. decode error catalog: empty, truncations, unknown tag, missing STOP,
    reserved address in a stream;
15. `encode_into` appends on success and leaves `out` untouched on `Err`;
16. PEC catalogue vector 0xF4, empty-input init, long-buffer agreement with
    the test-local polynomial-long-division reference;
17. PEC cover/verify: appended checksum, zero CRC of the covered frame,
    short frames, exact mismatch message;
18. SMBus quick/send-byte builders, pinned streams and error propagation;
19. equality and determinism: identical builds, repeated decodes;
20. end-to-end pipeline: SMBus send byte and a 10-bit repeated-START stream
    through encode/decode.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.i2c
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No bus, controller or socket access; no timing, clock stretching or
  arbitration modeling.
- The event stream is a logical tagged serialization, not the physical
  waveform; address bytes on the wire are derived separately.
- Reserved 7-bit and 10-bit ranges are rejected by the address helpers, so
  General Call / CBUS / SMBus Host users must construct events directly.
- Only SMBus Quick and Send Byte shapes are built; other SMBus protocols and
  their PEC framing are out of scope.
- `i2c_events_decode` expects exactly one complete transaction per buffer.
- `I2cTransaction` is a plain value type; copies are O(events) and it is not
  thread-safe.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers `_ok_unit`,
  `_err_unit`, `_ok_int`, `_err_int`, `_ok_bytes`, `_err_bytes`, `_ok_addr`,
  `_err_addr`, `_ok_txn`, `_err_txn` (constructing Results directly inside
  other functions miscompiles in this compiler).
- A transaction uses two index-aligned `Vec[Int]` arrays; no
  `Vec[StructType]` is used. Every push writes both arrays.
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before it
  enters Int arithmetic.
- `&struct.field` is never passed directly to a `&Vec` parameter; fields are
  bound to typed locals first, and Vec[Int] element reads go through typed
  locals.
- No Str value is compared with `==` and none is read from a Vec (BUG 17 is
  unreachable); decimal formatting for offset-bearing messages is hand-rolled
  in `_dec`, because the library module imports nothing (zero-import sibling
  style). This is the main stdlib gap: `xiom.convert.int.int_to_string`
  exists but would make the library module depend on stdlib imports the
  sibling codecs avoid.
- Numeric splitting uses multiplication, division and modulo only; no bit
  shift is used in the module.
- `&mut` appears at call sites explicitly (`i2c_txn_push_*(&mut t, ...)`);
  borrowed `&mut I2cTransaction` parameters are forwarded bare, mirroring
  `xiom.amqp`'s builder pattern. `&mut Int` out-parameters are avoided
  entirely: every fallible helper returns its value.
- No function named `log`, no indexed `Vec[fn]` dispatch, no generic
  callbacks; all functions are free functions.
