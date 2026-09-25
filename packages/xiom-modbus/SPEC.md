# xiom.modbus -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.modbus`, version `0.1.0`).
Module: `src/modbus.xi` (`module xiom.modbus`).
Depends on `xiom.std`; the library module imports nothing (the tests import
`xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare`,
`xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) Modbus frame codec for a documented subset:

- generic PDU encode/decode (function code + data) with the 253-byte Modbus
  PDU limit;
- RTU framing: address + PDU + CRC-16/Modbus (reflected polynomial 0xA001,
  init 0xFFFF, transmitted low byte first) with CRC validation on decode;
- TCP framing: the 7-byte MBAP header (transaction id, protocol id 0,
  length, unit id) with protocol-id and length-consistency validation;
- function 03 (read holding registers) request/response codecs, 1..125
  registers;
- function 06 (write single register) request/response codecs;
- exception response codec: function `| 0x80` plus exception code 1..4;
- a deterministic `Err(Str)` error catalog for malformed input and invalid
  fields.

## Non-goals

- **No I/O.** No serial port, TCP socket, TLS, or RTU inter-frame timing
  (3.5 character times). Frames are in-memory `Vec[UInt8]` values.
- **No client/server state machine.** No transaction tracking, no
  request/response correlation, no retries, no timeouts, no device model.
- **No other function codes.** Typed codecs exist only for 03, 06 and the
  exception response. Any other function code can be carried as a generic
  `ModbusPdu` but has no typed codec here.
- **No broadcast.** RTU addresses are 1..247; address 0 is rejected.
- **No Modbus ASCII framing**, no RTU-over-TCP gateway semantics beyond the
  MBAP header itself.
- **No 32-bit/float register interpretation.** Register values are unsigned
  16-bit integers; combining pairs is the caller's job.
- **No validation of the MBAP transaction id** against a pending request:
  it is decoded and returned, nothing more.

## Byte-level layouts

All multi-byte wire fields are big-endian except the RTU CRC bytes, which
are low byte first.

### PDU (protocol data unit), 1..253 bytes

| Field | Width | Encoding |
|---|---|---|
| function | 1 | function code 0..255; >= 0x80 marks an exception response |
| data | 0..252 | function-specific payload |

### RTU ADU, 4..256 bytes

| Field | Width | Encoding |
|---|---|---|
| address | 1 | slave address 1..247 |
| PDU | 1..253 | as above |
| CRC | 2 | CRC-16/Modbus over address + PDU, low byte first |

CRC-16/Modbus: polynomial 0xA001 (the reflected form of 0x8005), initial
register 0xFFFF, no output reflection, no final XOR. Catalogue check
`"123456789"` = 0x4B37 (19255); empty input = 0xFFFF (the init survives).

### TCP ADU (MBAP), 8..260 bytes

| Field | Width | Encoding |
|---|---|---|
| transaction id | 2 | unsigned big-endian 0..65535 |
| protocol id | 2 | must be 0; `tcp_encode` writes 0 |
| length | 2 | unsigned big-endian; counts the unit byte + PDU, so length = 1 + PDU length |
| unit id | 1 | 0..255 |
| PDU | 1..253 | as above |

The MBAP header is the 7 bytes before the PDU. A decode accepts only a
buffer whose `length` field equals `data.len() - 6`.

### Function 03 (read holding registers)

Request PDU data (4 bytes):

| Field | Width | Range |
|---|---|---|
| start_address | 2 | 0..65535 |
| quantity | 2 | 1..125 |

start_address + quantity must not exceed 65536 (no register may lie beyond
address 65535).

Response PDU data (1 + 2N bytes):

| Field | Width | Encoding |
|---|---|---|
| byte_count | 1 | 2 * N, where N is 1..125 |
| register values | 2 * N | each register unsigned big-endian 0..65535 |

### Function 06 (write single register)

Request and response PDU data (4 bytes each; the response echoes the
request byte for byte):

| Field | Width | Range |
|---|---|---|
| register address | 2 | 0..65535 |
| register value | 2 | 0..65535 |

### Exception response

PDU:

| Field | Width | Encoding |
|---|---|---|
| function | 1 | base function + 0x80 (129..255) |
| exception code | 1 | 1 = illegal function, 2 = illegal data address, 3 = illegal data value, 4 = server device failure |

### Size summary

| Frame | Minimum | Maximum |
|---|---|---|
| PDU | 1 | 253 |
| RTU ADU | 4 | 256 |
| TCP ADU | 8 | 260 |
| FC03 response PDU | 3 (1 register) | 252 (125 registers) |
| RTU with 125-register response | -- | 255 |
| TCP with 125-register response | -- | 259 |

## Types

```xi
pub type ModbusPdu = { function: Int; data: Vec[UInt8]; }
pub type ModbusRtuFrame = { address: Int; pdu: ModbusPdu; }
pub type ModbusTcpFrame = { transaction_id: Int; unit_id: Int; pdu: ModbusPdu; }
pub type ReadHoldingRegistersRequest = { start_address: Int; quantity: Int; }
pub type WriteSingleRegister = { address: Int; value: Int; }
pub type ModbusException = { function: Int; code: Int; }
```

`ModbusRtuFrame.pdu` and `ModbusTcpFrame.pdu` are nested `ModbusPdu`
values. `ModbusException.function` is the *base* function code (the wire
function minus 0x80): an exception PDU for function 3 reports
`function = 3`.

## API contract

All functions are free functions in module `xiom.modbus`; there are no
methods and no state. Every fallible function validates in the order listed
and returns `Err` without a partial result; error text is stable.

```xi
pub fn modbus_crc16(data: &Vec[UInt8]) -> Int
pub fn pdu_function(p: &ModbusPdu) -> Int
pub fn pdu_data_len(p: &ModbusPdu) -> Int
pub fn pdu_is_exception(p: &ModbusPdu) -> Bool
pub fn pdu_encode(p: &ModbusPdu) -> Result[Vec[UInt8], Str]
pub fn pdu_decode(data: &Vec[UInt8]) -> Result[ModbusPdu, Str]
pub fn rtu_encode(address: Int, p: &ModbusPdu) -> Result[Vec[UInt8], Str]
pub fn rtu_decode(data: &Vec[UInt8]) -> Result[ModbusRtuFrame, Str]
pub fn tcp_encode(transaction_id: Int, unit_id: Int, p: &ModbusPdu) -> Result[Vec[UInt8], Str]
pub fn tcp_decode(data: &Vec[UInt8]) -> Result[ModbusTcpFrame, Str]
pub fn read_holding_registers_request_pdu(start_address: Int, quantity: Int) -> Result[ModbusPdu, Str]
pub fn read_holding_registers_request_from_pdu(p: &ModbusPdu) -> Result[ReadHoldingRegistersRequest, Str]
pub fn read_holding_registers_response_pdu(registers: &Vec[Int]) -> Result[ModbusPdu, Str]
pub fn read_holding_registers_response_from_pdu(p: &ModbusPdu) -> Result[Vec[Int], Str]
pub fn write_single_register_request_pdu(address: Int, value: Int) -> Result[ModbusPdu, Str]
pub fn write_single_register_response_pdu(address: Int, value: Int) -> Result[ModbusPdu, Str]
pub fn write_single_register_request_from_pdu(p: &ModbusPdu) -> Result[WriteSingleRegister, Str]
pub fn write_single_register_response_from_pdu(p: &ModbusPdu) -> Result[WriteSingleRegister, Str]
pub fn exception_pdu(base_function: Int, code: Int) -> Result[ModbusPdu, Str]
pub fn exception_from_pdu(p: &ModbusPdu) -> Result[ModbusException, Str]
pub fn exception_name(code: Int) -> Str
```

### Semantics and validation order

`modbus_crc16(data)`
: CRC-16/Modbus over `data` in order; returns 0..65535. Empty input returns
  65535. No error channel.

`pdu_encode(p)`
: 1. function outside 0..255 -> `modbus: invalid function code`;
  2. `data.len() > 252` -> `modbus: pdu too long`;
  3. otherwise the function byte followed by the data bytes verbatim.

`pdu_decode(data)`
: 1. empty -> `modbus: empty pdu`; 2. longer than 253 -> `modbus: pdu too
  long`; 3. otherwise byte 0 is the function and bytes 1.. are the data.

`pdu_function(p)` / `pdu_data_len(p)` / `pdu_is_exception(p)`
: Read the struct fields; `pdu_is_exception` is `function >= 128` and is
  meaningful for values constructed by the caller too.

`rtu_encode(address, p)`
: 1. address outside 1..247 -> `modbus: invalid rtu address`;
  2. `pdu_encode` errors propagated unchanged;
  3. address byte, PDU bytes, then CRC low byte first. A 253-byte PDU
  yields a 256-byte frame; no frame can exceed the RTU limit after PDU
  validation.

`rtu_decode(data)`
: 1. shorter than 4 -> `modbus: truncated rtu frame`;
  2. longer than 256 -> `modbus: rtu frame too long`;
  3. CRC over `data[0..len-2)` vs the last two bytes (low first) ->
  `modbus: bad crc`;
  4. address outside 1..247 -> `modbus: invalid rtu address`;
  5. `pdu_decode` over `data[1..len-2)`; errors propagated (a frame of at
  least 4 bytes always leaves a 1..253-byte PDU). The CRC is not retained
  in the result.

`tcp_encode(transaction_id, unit_id, p)`
: 1. transaction id outside 0..65535 -> `modbus: invalid transaction id`;
  2. unit id outside 0..255 -> `modbus: invalid unit id`;
  3. `pdu_encode` errors propagated;
  4. transaction[2] big-endian, protocol 0, length = 1 + PDU length, unit
  byte, PDU.

`tcp_decode(data)`
: 1. shorter than 8 -> `modbus: truncated mbap header`;
  2. protocol id not 0 -> `modbus: bad protocol id`;
  3. length field != `data.len() - 6` -> `modbus: length mismatch`;
  4. `pdu_decode` over `data[7..]`; errors propagated. Protocol id and the
  length check run before the PDU is touched, so a corrupted header never
  yields a partially decoded PDU.

`read_holding_registers_request_pdu(start_address, quantity)`
: 1. start outside 0..65535 -> `modbus: invalid register address`;
  2. quantity outside 1..125 -> `modbus: invalid register count`;
  3. start + quantity > 65536 -> `modbus: address range overflow`;
  4. data = start[2] + quantity[2] big-endian.

`read_holding_registers_request_from_pdu(p)`
: 1. function != 3 -> `modbus: wrong function`;
  2. data length != 4 -> `modbus: bad pdu length`;
  3. quantity outside 1..125 -> `modbus: invalid register count`;
  4. start + quantity > 65536 -> `modbus: address range overflow`.

`read_holding_registers_response_pdu(registers)`
: 1. count outside 1..125 -> `modbus: invalid register count`;
  2. any value outside 0..65535 -> `modbus: invalid register value`;
  3. data = byte_count (2 * count) followed by each value big-endian.

`read_holding_registers_response_from_pdu(p)`
: 1. function != 3 -> `modbus: wrong function`;
  2. data empty -> `modbus: bad pdu length`;
  3. byte_count odd, or byte_count != data.len() - 1 -> `modbus: bad byte
  count`;
  4. byte_count / 2 outside 1..125 -> `modbus: invalid register count`;
  5. values are read big-endian in wire order.

`write_single_register_request_pdu(address, value)`
: 1. address outside 0..65535 -> `modbus: invalid register address`;
  2. value outside 0..65535 -> `modbus: invalid register value`;
  3. data = address[2] + value[2] big-endian.

`write_single_register_response_pdu(address, value)`
: Same layout as the request (the response is an echo); delegates to
  `write_single_register_request_pdu`.

`write_single_register_request_from_pdu(p)`
: 1. function != 6 -> `modbus: wrong function`;
  2. data length != 4 -> `modbus: bad pdu length`;
  3. address = data[0..2], value = data[2..4] big-endian.

`write_single_register_response_from_pdu(p)`
: Same layout as the request; delegates to
  `write_single_register_request_from_pdu`.

`exception_pdu(base_function, code)`
: 1. base outside 1..127 -> `modbus: invalid function code`;
  2. code outside 1..4 -> `modbus: invalid exception code`;
  3. function = base + 128, data = [code].

`exception_from_pdu(p)`
: 1. function < 128 -> `modbus: wrong function`;
  2. data length != 1 -> `modbus: bad pdu length`;
  3. code outside 1..4 -> `modbus: invalid exception code`;
  4. result function = p.function - 128 (the base function).

`exception_name(code)`
: `"illegal function"` (1), `"illegal data address"` (2), `"illegal data
  value"` (3), `"server device failure"` (4), `"unknown exception"`
  otherwise. No error channel.

## Error string catalog

| Condition | Error text |
|---|---|
| `pdu_decode` on an empty buffer | `modbus: empty pdu` |
| function < 0 or > 255 (encode), exception base outside 1..127 | `modbus: invalid function code` |
| PDU data > 252 (encode) or buffer > 253 (decode) | `modbus: pdu too long` |
| address outside 0..65535 (FC03 start, FC06 address) | `modbus: invalid register address` |
| register count outside 1..125 | `modbus: invalid register count` |
| start_address + quantity > 65536 | `modbus: address range overflow` |
| register value outside 0..65535 | `modbus: invalid register value` |
| function-specific decoder on the wrong function code | `modbus: wrong function` |
| PDU data length not the fixed size for the codec | `modbus: bad pdu length` |
| FC03 response byte_count odd or != data.len() - 1 | `modbus: bad byte count` |
| exception code outside 1..4 | `modbus: invalid exception code` |
| RTU address outside 1..247 | `modbus: invalid rtu address` |
| RTU buffer shorter than 4 bytes | `modbus: truncated rtu frame` |
| RTU buffer longer than 256 bytes | `modbus: rtu frame too long` |
| received CRC differs from the computed CRC | `modbus: bad crc` |
| TCP buffer shorter than 8 bytes | `modbus: truncated mbap header` |
| MBAP protocol id != 0 | `modbus: bad protocol id` |
| MBAP length != bytes after the length field | `modbus: length mismatch` |
| transaction id outside 0..65535 | `modbus: invalid transaction id` |
| unit id outside 0..255 | `modbus: invalid unit id` |

## Complexity

| Operation | Time | Space |
|---|---|---|
| `modbus_crc16` | O(data.len()) (8 bit-steps/byte) | O(1) |
| `pdu_encode` / `pdu_decode` | O(PDU length) | O(PDU length) |
| `rtu_encode` | O(PDU length) | O(PDU length) |
| `rtu_decode` | O(frame length) | O(frame length) |
| `tcp_encode` | O(PDU length) | O(PDU length) |
| `tcp_decode` | O(frame length) | O(frame length) |
| `read_holding_registers_*_pdu` | O(registers) | O(registers) |
| `read_holding_registers_*_from_pdu` | O(registers) | O(registers) |
| `write_single_register_*` | O(1) | O(1) |
| `exception_*` | O(1) | O(1) |
| accessors and `exception_name` | O(1) | O(1) |

## Test plan

`tests/test_conformance.xi` (`module modbus_tests`, 23 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. CRC published vectors: `"123456789"` = 0x4B37 (19255), empty = 0xFFFF,
   `00` = 16575, `00 00` = 45057, `ff ff ff` = 16448, `01 03 04 00 0A 01
   02` = 24666;
2. CRC property: a 300-byte pattern (byte k = k % 256) = 62621 and
   `ff 00 80 7f 01` = 3280 against both the module and a test-local
   mirrored-formulation implementation; frame bodies agree on both
   implementations;
3. PDU encode/decode round-trip, accessors, and a 1-byte exception PDU;
4. PDU error catalog: empty decode, function -1 and 256, 253-byte data
   encode, 254-byte buffer decode, 252-byte/253-byte maxima accepted;
5. `rtu_encode` pinned frames: `01 03 00 00 00 0A C5 CD`, `01 03 00 6B 00
   03 74 17`, `11 06 00 10 00 03 CA 9E`, `01 83 02 C0 F1`, and the
   max-range `F7 03 FF 83 00 7D 50 81`;
6. `rtu_decode` round-trips those frames (address, function, data) and
   re-encodes them byte for byte;
7. RTU error catalog: empty and 3-byte truncation, 257-byte over-long,
   corrupted CRC, address 0 and 248 rejected, 247 accepted;
8. FC03 request exact bytes and field round-trip (including start 65535,
   quantity 1);
9. FC03 request bounds: address -1/65536, quantity 0/126, range overflow at
   start 65535 + quantity 2, acceptance at 65535 + 1 and 0 + 125;
10. FC03 response: exact bytes `01 03 04 00 0A 01 02 5A 60`, register
    round-trip, and the 125-register frame (byte_count 250, 251-byte PDU);
11. FC03 response error catalog: 0/126 registers, value 65536 and -1, wrong
    function, empty data, odd byte count, mismatched byte count, zero
    byte_count, 252-byte data with 126 registers;
12. FC06 request/response exact bytes, field round-trip, echo equality, and
    the 65535/65535 boundary;
13. FC06 error catalog: address/value bounds, wrong function, 3-byte and
    5-byte data;
14. exception PDU: exact `83 02` bytes, codes 1..4 round-trip for base
    function 6, and the decode error catalog (non-exception function,
    two-byte data, codes 0 and 5);
15. exception builder bounds (base 0/128/-1, code 0/5) and the
    `exception_name` mapping including unknown codes;
16. `tcp_encode` pinned MBAP frames: `00 01 00 00 00 06 01 03 00 00 00
    0A`, `12 34 00 00 00 06 FF 06 00 10 00 03`, `00 01 00 00 00 03 01 83
    02`;
17. `tcp_decode` round-trips those frames plus the 8-byte minimum
    (`00 01 00 00 00 02 FF 03`) and re-encodes the first byte for byte;
18. TCP error catalog: empty and 7-byte truncation, protocol id 1 (which
    also precedes the length check), length 7 and 5 mismatches, a truncated
    buffer, and a valid frame accepted;
19. RTU/TCP builder validation: transaction id -1/65536, unit id -1/256,
    RTU address 0/248 rejected and 1/247 accepted, PDU-too-long propagated
    by both framings;
20. boundary sizes: the 4-byte minimum RTU frame (function-only PDU), the
    256-byte maximum RTU frame (252 data bytes), and the 259-byte TCP frame
    for a 125-register response (length field 253);
21. RTU pipeline: FC03 request, FC03 response and an exception PDU through
    build -> `rtu_encode` -> `rtu_decode` -> function decoder;
22. TCP pipeline: FC06 request/response echo and an exception through
    build -> `tcp_encode` -> `tcp_decode` -> function decoder;
23. determinism: repeated `rtu_encode`/`rtu_decode` calls agree byte for
    byte and field for field, and independently built PDUs with equal
    content encode identically.

Fixture notes: hex literals come from `xiom.encoding.hex`; `raw_rtu` and
`raw_tcp_full` build malformed fixtures with a *test-local* CRC
implementation and explicit MBAP fields, so error-path fixtures do not
depend on the module under test. No `Str` value is compared with `==`
(BUG 17 discipline); error messages go through
`xiom.string.compare.str_compare`.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.modbus
```

Last verified: compiler 0.61.3,
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No transport, no timing, no state machine (see Non-goals).
- Only function codes 03, 06 and the exception response have typed codecs.
- RTU broadcast (address 0) is rejected; only 1..247 are accepted.
- The CRC is bitwise and table-free: 8 bit-steps per byte.
- Register values are unsigned 16-bit integers; no float/32-bit
  interpretation and no scaling.
- `pdu_decode` accepts any function byte 0..255: a frame can carry
  reserved or vendor function codes as generic PDUs.
- `rtu_decode` does not verify that a decoded request is semantically valid
  (that is the function-specific decoder's job), and `tcp_decode` does not
  correlate the transaction id with anything.

## Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, no lambdas, no `Vec[fn]` dispatch.
- `Ok`/`Err` construction is confined to the tiny leaf helpers
  (`_ok_pdu`/`_err_pdu`, `_ok_rtu`/`_err_rtu`, `_ok_tcp`/`_err_tcp`,
  `_ok_bytes`/`_err_bytes`, `_ok_regs`/`_err_regs`, `_ok_read`/`_err_read`,
  `_ok_write`/`_err_write`, `_ok_exc`/`_err_exc`), because constructing
  Results directly inside other functions miscompiles in this compiler.
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic; UInt8 values are never compared against Int
  constants >= 128 without widening.
- `&struct.field` is never passed as a `&Vec[UInt8]` parameter (that yields
  an empty vector in v0.61.3); fields are bound to typed locals first
  (`let d: Vec[UInt8] = p.data;`).
- The CRC register stays a non-negative Int below 65536 using `>>`, `^`
  and the small mask `& 1`; the top-bit tests in the tests' mirrored CRC
  use comparisons rather than a 16-bit AND.
- The package declares no `extern "C"` blocks (no FFI).
