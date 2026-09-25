# xiom.modbus

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) Modbus frame codec: PDU encode/decode, RTU
> framing with CRC-16/Modbus validation, TCP framing with MBAP validation,
> function 03 and 06 request/response codecs, and the exception response
> codec.
> **Deps:** `xiom.std` only. The library module imports nothing; the tests
> use `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex`.

## What it is

`xiom.modbus` turns Modbus protocol data units and frames into byte vectors
and back:

- **PDU codec** -- `ModbusPdu` (function code plus data bytes) and its
  encode/decode, with the 253-byte Modbus PDU limit enforced;
- **RTU framing** -- address + PDU + CRC-16/Modbus, with the checksum
  computed over address + PDU and transmitted low byte first, and full CRC
  validation on decode;
- **TCP framing** -- the 7-byte MBAP header (transaction id, protocol id 0,
  length, unit id) with protocol-id and length-consistency validation;
- **Function 03** (read holding registers) -- request and response codecs,
  1..125 registers per request, big-endian 16-bit register values;
- **Function 06** (write single register) -- request and response codecs
  (the response echoes the request), big-endian address and value;
- **Exception responses** -- function `| 0x80` plus exception code 1..4,
  with a name lookup.

Everything is a free function over `Vec[UInt8]` and small struct types.
There is no I/O and no hidden state: the codec only formats and validates
bytes. The error model is a deterministic `Err(Str)` catalog (see below);
an `Err` never carries a partially built result.

Byte order summary: Modbus is big-endian on the wire for all multi-byte
fields (addresses, quantities, register values, MBAP fields); the only
little-endian item is the RTU CRC, which is appended low byte first.

## Install / use

```
xiom pkg install xiom.modbus@0.1.0     # consumer
xiom pkg publish                      # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xi
use xiom.modbus;
use xiom.io;
use xiom.encoding.hex;

// Function 03 request: read 10 holding registers starting at address 0.
let rq = read_holding_registers_request_pdu(0, 10);
if rq.is_ok {
  let pdu: ModbusPdu = rq.value;

  // RTU frame for slave 1: 01 03 00 00 00 0A C5 CD
  let rtu = rtu_encode(1, &pdu);
  if rtu.is_ok {
    let bytes: Vec[UInt8] = rtu.value;
    io.println(hex.hex_encode(&bytes));
  }

  // TCP frame, transaction 1, unit 1:
  // 00 01 00 00 00 06 01 03 00 00 00 0A
  let tcp = tcp_encode(1, 1, &pdu);
  if tcp.is_ok {
    let frame: Vec[UInt8] = tcp.value;
    io.println(hex.hex_encode(&frame));
  }
}
```

Decoding is the mirror image:

```xi
let r = rtu_decode(&frame_bytes);       // &Vec[UInt8] off the wire
if r.is_ok {
  let f: ModbusRtuFrame = r.value;      // f.address, f.pdu
  let q = read_holding_registers_request_from_pdu(&f.pdu);
  if q.is_ok {
    let req: ReadHoldingRegistersRequest = q.value;
    // req.start_address, req.quantity
  }
}
```

## API

All functions are free functions in module `xiom.modbus`.

### Generic PDU

| Function | Returns | Description |
|---|---|---|
| `pdu_function(p)` | `Int` | Function code (0..255). |
| `pdu_data_len(p)` | `Int` | Number of data bytes. |
| `pdu_is_exception(p)` | `Bool` | True when the exception bit is set (function >= 128). |
| `pdu_encode(p)` | `Result[Vec[UInt8], Str]` | Function byte + data bytes; enforces function 0..255 and data <= 252. |
| `pdu_decode(data)` | `Result[ModbusPdu, Str]` | Byte 0 is the function, the rest is data; enforces 1..253 bytes. |

### CRC and framing

| Function | Returns | Description |
|---|---|---|
| `modbus_crc16(data)` | `Int` | CRC-16/Modbus (reflected 0xA001, init 0xFFFF); `"123456789"` = 0x4B37. |
| `rtu_encode(address, p)` | `Result[Vec[UInt8], Str]` | address[1] + PDU + CRC[2] (low byte first); address 1..247. |
| `rtu_decode(data)` | `Result[ModbusRtuFrame, Str]` | Validates length 4..256, CRC, address 1..247. |
| `tcp_encode(transaction_id, unit_id, p)` | `Result[Vec[UInt8], Str]` | MBAP(7) + PDU; length = 1 + PDU length. |
| `tcp_decode(data)` | `Result[ModbusTcpFrame, Str]` | Validates length >= 8, protocol id 0, length consistency. |

### Function 03 (read holding registers)

| Function | Returns | Description |
|---|---|---|
| `read_holding_registers_request_pdu(start_address, quantity)` | `Result[ModbusPdu, Str]` | start 0..65535, quantity 1..125, no address overflow. |
| `read_holding_registers_request_from_pdu(p)` | `Result[ReadHoldingRegistersRequest, Str]` | Function 3, data exactly 4 bytes. |
| `read_holding_registers_response_pdu(registers)` | `Result[ModbusPdu, Str]` | 1..125 values, each 0..65535, big-endian. |
| `read_holding_registers_response_from_pdu(p)` | `Result[Vec[Int], Str]` | Validates byte count and 1..125 registers. |

### Function 06 (write single register)

| Function | Returns | Description |
|---|---|---|
| `write_single_register_request_pdu(address, value)` | `Result[ModbusPdu, Str]` | address 0..65535, value 0..65535. |
| `write_single_register_response_pdu(address, value)` | `Result[ModbusPdu, Str]` | Echo of the request (same bytes); delegates. |
| `write_single_register_request_from_pdu(p)` | `Result[WriteSingleRegister, Str]` | Function 6, data exactly 4 bytes. |
| `write_single_register_response_from_pdu(p)` | `Result[WriteSingleRegister, Str]` | Same layout; delegates. |

### Exception responses

| Function | Returns | Description |
|---|---|---|
| `exception_pdu(base_function, code)` | `Result[ModbusPdu, Str]` | base 1..127, code 1..4; function becomes base + 0x80. |
| `exception_from_pdu(p)` | `Result[ModbusException, Str]` | Exception bit set, data exactly 1 byte, code 1..4. |
| `exception_name(code)` | `Str` | `"illegal function"`, `"illegal data address"`, `"illegal data value"`, `"server device failure"`, else `"unknown exception"`. |

### Types

```xi
pub type ModbusPdu = { function: Int; data: Vec[UInt8]; }
pub type ModbusRtuFrame = { address: Int; pdu: ModbusPdu; }
pub type ModbusTcpFrame = { transaction_id: Int; unit_id: Int; pdu: ModbusPdu; }
pub type ReadHoldingRegistersRequest = { start_address: Int; quantity: Int; }
pub type WriteSingleRegister = { address: Int; value: Int; }
pub type ModbusException = { function: Int; code: Int; }   // base function, exception code
```

## Error model

Every fallible function returns `Result[T, Str]` with a stable, lowercase
`modbus:` message. Decoders validate in a fixed order (documented per
function in `SPEC.md`), so an error message is deterministic for a given
input. `Err` never carries a partial index or a half-built buffer.

| Error text | Raised when |
|---|---|
| `modbus: empty pdu` | `pdu_decode` on a zero-byte buffer. |
| `modbus: invalid function code` | PDU function outside 0..255, or exception base function outside 1..127. |
| `modbus: pdu too long` | PDU data exceeds 252 bytes (encode) or the buffer exceeds 253 bytes (decode). |
| `modbus: invalid register address` | Address outside 0..65535 (FC03 start address, FC06 address). |
| `modbus: invalid register count` | Register count outside 1..125. |
| `modbus: address range overflow` | start_address + quantity exceeds 65536. |
| `modbus: invalid register value` | Register value outside 0..65535. |
| `modbus: wrong function` | A function-specific decoder saw a different function code. |
| `modbus: bad pdu length` | The PDU data length is not the fixed size the codec expects. |
| `modbus: bad byte count` | FC03 response byte_count is odd or differs from the data length. |
| `modbus: invalid exception code` | Exception code outside 1..4. |
| `modbus: invalid rtu address` | RTU address outside 1..247. |
| `modbus: truncated rtu frame` | Fewer than 4 bytes (address + function + CRC). |
| `modbus: rtu frame too long` | More than 256 bytes. |
| `modbus: bad crc` | Received CRC differs from the computed CRC-16/Modbus. |
| `modbus: truncated mbap header` | Fewer than 8 bytes (MBAP header plus one function byte). |
| `modbus: bad protocol id` | MBAP protocol identifier is not 0. |
| `modbus: length mismatch` | MBAP length field differs from the bytes after it. |
| `modbus: invalid transaction id` | Transaction id outside 0..65535. |
| `modbus: invalid unit id` | Unit id outside 0..255. |

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.modbus
```

Expected: the namespace check passes, 23 `[PASS]` lines, and a final
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`. See `SPEC.md` for
the full test matrix. Pinned frames were cross-checked against an
independent CRC-16/Modbus implementation and the published example frame
`01 03 00 00 00 0A C5 CD`; the suite also compares the module checksum
against a second, structurally different CRC implementation on 300-byte and
high-bit buffers.

## Limitations

- **No I/O.** There is no serial port, TCP socket, TLS or timing layer:
  frames go in and out as `Vec[UInt8]`. RTU inter-frame timing (3.5
  character times) is the transport's job.
- **No client or server state machine.** No transaction tracking, no
  request/response matching, no retries or timeouts. A decoded transaction
  id is returned but not validated against anything.
- **Documented subset.** Typed codecs exist only for function 03 and 06
  and the exception response; other function codes can be carried and
  examined as generic `ModbusPdu` values but have no typed codec.
- **No broadcast.** RTU frames require a slave address in 1..247;
  address 0 (broadcast) is rejected by `rtu_encode` and `rtu_decode`.
- **No Modbus ASCII.** Only RTU and TCP framing are implemented.
- **Registers are unsigned 16-bit Ints.** 32-bit values, float register
  pairs and device-specific scaling are out of scope; callers combine
  register values themselves.
- **Bitwise, table-free CRC.** 8 bit-steps per byte: correct and portable,
  but slower than a `[256]` lookup table for bulk work.
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
