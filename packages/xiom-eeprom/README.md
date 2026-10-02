# xiom.eeprom

> **Status:** `stable` -- conformance-tested (17/17); published at `v0.1.1` on the XIOM registry.
> **Scope:** pure-XIOM (no FFI) serial EEPROM device protocol codecs for two
> families: 24Cxx (I2C) addressing/page math and 93Cxx (Microwire) command
> bit streams.
> **Deps:** `xiom.std` only. The library module imports `xiom.convert` and
> `xiom.string.compare`; the tests also use `xiom.test`, `xiom.io` and
> `xiom.encoding.hex`.

## What it is

`xiom.eeprom` turns serial EEPROM protocol elements into values and byte
vectors and back:

- **24Cxx control byte** -- `1010 A2A1A0 R/W` (`0xA0 + pins * 2 + read`) with
  the pin strapping validated to 0..7;
- **24Cxx density table** -- 24C01..24C2048 (1..2048 Kbit): bits, bytes,
  word-address width (1 byte up to 24C16, 2 bytes from 24C32) and page size
  (8/16/32/64/128/256 bytes);
- **24Cxx word address** -- the 1- or 2-byte big-endian memory address field,
  with field-width bounds (`<= 0xFF` / `<= 0xFFFF`);
- **24Cxx page and device math** -- page start, next page start, bytes left
  in the page, the address a page-write byte lands on (the write pointer
  wraps inside the page), the contiguous write span before the next boundary
  or the device end, and current-address read wrap (`addr mod device_bytes`);
- **24Cxx validation** -- byte-address range checks and page-write boundary
  checks whose error text names the byte offset of the boundary;
- **93Cxx opcodes** -- READ `10`, WRITE `101`, ERASE `111`, EWEN `10011`,
  EWDS `10000`, ERAL `10010`, WRAL `10001` (the encoder prefixes READ's
  2-bit pattern with the mandatory start bit, giving the wire prefix `110`);
- **93Cxx encode/decode** -- command + address (+ data for WRITE/WRAL)
  packed MSB first into bytes and decoded back into opcode, byte address,
  data and bit count; per-density address widths for org 8 and org 16 across
  93C46..93C106 (1..64 Kbit);
- **93Cxx rules** -- READ/WRITE/ERASE byte addresses must be word-aligned on
  org 16, WRAL requires address 0, EWEN/EWDS/ERAL addresses are don't-care
  zeros, and READ responses are plain MSB-first data frames.

Everything is a free function over `Int`, `Bool` and `Vec[UInt8]`, plus
three small struct types. There is no I/O, no clock/CS handling and no device
state: the codec only formats, wraps and validates. The error model is a
deterministic `Err(Str)` catalog (see `SPEC.md`); an `Err` never carries a
half-built buffer.

## Install / use

```
xiom pkg install xiom.eeprom@0.1.1     # consumer
xiom pkg publish                       # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xi
use xiom.eeprom;
use xiom.io;
use xiom.encoding.hex;

// 24C64 (64 Kbit, 2-byte word address, 32-byte pages) at pin strapping
// A2A1A0 = 011, write direction: control byte 0xA6.
let cb = ee24_control_byte(3, false);
if cb.is_ok {
  let cbyte: Int = cb.value;                          // 166
}

// Word address 0x1234 in 2 bytes: 12 34.
let wa = ee24_word_address(4660, ee24_addr_bytes("24C64"));
if wa.is_ok {
  let wbytes: Vec[UInt8] = wa.value;
  io.println(hex.hex_encode(&wbytes));
}

// 24C64 page write of 2 bytes at the last page (8190): accepted; 3 bytes
// would cross the boundary at byte offset 2.
if ee24_validate_page_write(8190, 2, 32).is_ok {
  io.println("fits");
}

// 93C46, org 16: READ word 3 -> C1 80 (110 000011, 9 bits).
let cmd = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_READ; address: 6; data: 0; };
let enc = ee93_encode(&cmd);
if enc.is_ok {
  let frame: Vec[UInt8] = enc.value;
  io.println(hex.hex_encode(&frame));   // "c180"

  let dec = ee93_decode(&frame, "93C46", 16);
  if dec.is_ok {
    let d: Ee93Decoded = dec.value;     // d.opcode == EE93_READ, d.address == 6, d.bits == 9
  }
}

// 93C46 org 16 WRITE word 2 with data 0x1234: A1 09 1A 00 (25 bits).
let wr = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_WRITE; address: 4; data: 4660; };
// -> ee93_encode(&wr) == { 0xA1, 0x09, 0x1A, 0x00 }
```

## API

All functions are free functions in module `xiom.eeprom`.

### 24Cxx (I2C)

| Function | Returns | Description |
|---|---|---|
| `ee24_control_byte(pins, read_op)` | `Result[Int, Str]` | `0xA0 + pins * 2 + read_op`; pins 0..7. |
| `ee24_device_address_write(pins)` | `Result[Int, Str]` | R/W = 0 shorthand. |
| `ee24_device_address_read(pins)` | `Result[Int, Str]` | R/W = 1 shorthand. |
| `ee24_density(name)` | `Result[EepromDensity, Str]` | One of the twelve 24C01..24C2048 rows. |
| `ee24_page_size(name)` | `Int` | Page size or -1 for an unknown name. |
| `ee24_addr_bytes(name)` | `Int` | Word-address width 1/2 or -1. |
| `ee24_bytes(name)` | `Int` | Size in bytes or -1. |
| `ee24_bits(name)` | `Int` | Size in bits or -1. |
| `ee24_word_address(addr, addr_bytes)` | `Result[Vec[UInt8], Str]` | 1/2 big-endian address bytes; field-width bounds. |
| `ee24_page_start(addr, page_size)` | `Int` | First byte of the page. |
| `ee24_next_page_start(addr, page_size)` | `Int` | First byte after the page. |
| `ee24_page_remaining(addr, page_size)` | `Int` | Bytes until the page boundary. |
| `ee24_write_target(addr, offset, page_size)` | `Int` | Address byte `offset` of a page write lands on (in-page wrap). |
| `ee24_wrap_address(addr, device_bytes)` | `Int` | Current-address read wrap; negative input wraps too. |
| `ee24_seq_address(addr, offset, device_bytes)` | `Int` | Address after `offset` sequential accesses with device-end wrap. |
| `ee24_write_span(addr, page_size, device_bytes)` | `Int` | Contiguous burst in the page, clipped by the device end. |
| `ee24_validate_address(addr, device_bytes)` | `Result[Unit, Str]` | Byte-address range check. |
| `ee24_validate_page_write(addr, count, page_size)` | `Result[Unit, Str]` | Page-write size and boundary check. |

### 93Cxx (Microwire)

| Function | Returns | Description |
|---|---|---|
| `ee93_address_bits(name, org)` | `Int` | Address field width in bits, or -1. |
| `ee93_bytes(name, org)` | `Int` | Size in bytes, or -1. |
| `ee93_word_count(name, org)` | `Int` | Addressable words (`2^address_bits`), or -1. |
| `ee93_density(name, org)` | `Result[EepromDensity, Str]` | One of the six densities for org 8/16. |
| `ee93_opcode_name(opcode)` | `Str` | `"READ"`..`"WRAL"` or `"unknown"`. |
| `ee93_encode(cmd)` | `Result[Vec[UInt8], Str]` | Command bit stream, MSB first, zero-padded. |
| `ee93_decode(data, density, org)` | `Result[Ee93Decoded, Str]` | Opcode, byte address, data and bit count. |
| `ee93_encode_read_response(value, org)` | `Result[Vec[UInt8], Str]` | org bits as 1/2 bytes. |
| `ee93_decode_read_response(data, org)` | `Result[Int, Str]` | org bits from the first 1/2 bytes. |

### Constants and types

```xi
pub const EE93_READ: Int = 2;    // "10"  (+ start bit on the wire => "110")
pub const EE93_WRITE: Int = 5;   // "101"
pub const EE93_ERASE: Int = 7;   // "111"
pub const EE93_EWEN: Int = 19;   // "10011"
pub const EE93_EWDS: Int = 16;   // "10000"
pub const EE93_ERAL: Int = 18;   // "10010"
pub const EE93_WRAL: Int = 17;   // "10001"

pub type EepromDensity = { name: Str; bits: Int; bytes: Int; addr_bytes: Int; page_size: Int; org: Int; }
pub type Ee93Command = { density: Str; org: Int; opcode: Int; address: Int; data: Int; }
pub type Ee93Decoded = { opcode: Int; address: Int; data: Int; bits: Int; }
```

## Error model

Every fallible function returns `Result[T, Str]` with a stable,
lowercase `eeprom.24cxx:` / `eeprom.93cxx:` message. Boundary errors carry
the offending byte offset or bit count (for example "crosses the page
boundary at byte offset 2 (page size 32)" or "need 9 bits, have 8").
Decoders validate in a fixed order documented per function in `SPEC.md`;
`Err` never carries a partial result.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.eeprom
```

Expected: the namespace check passes, 17 `[PASS]` lines, and a final
`port: PASS (passed=17 failed=0 program_exit=0 exit=0)`. Pinned 93Cxx frames
(`C1 80`, `C1 40`, `E0 80`, `A1 09 1A 00`, `A0 29 40`, `98 00`, `80 00`,
`90 00`, `88 0A B5 40`) are additionally cross-checked against a test-local,
independently written bit packer. See `SPEC.md` for the full matrix.

## Limitations

- **No bus I/O.** No I2C start/stop/ACK, no Microwire CS/CLK lines, no
  timing (tCLK, write-cycle delays) and no device state. Frames and bit
  streams go in and out as `Vec[UInt8]`; ACK polling and page-write
  scheduling are the transport's job.
- **24Cxx word-address field only.** The codec models the 1/2-byte word
  address. On 24C1024/24C2048 the memory exceeds 65536 bytes and the extra
  high address bit lives in the device select pins / a P0 pin; the caller
  must put it in the control byte itself. On 24C01..24C16 some A2..A0 pins
  double as memory address bits on the wire; the table still reports the
  conventional pin strapping and byte count.
- **24Cxx page wrap is modeled, not enforced by the helpers.** A page write
  that crosses a page boundary wraps inside the page (datasheet behavior);
  `ee24_validate_page_write` rejects such a write and names the boundary
  offset, while `ee24_write_target` computes the wrapped target when the
  caller wants the raw behavior.
- **93Cxx specials' address fields are don't-care.** EWEN, EWDS and ERAL
  ignore the address and emit zero bits; WRAL requires address 0. READ
  responses are plain data bits: the codec does not clock them, and no
  READY/BUSY handshake is modeled.
- **93Cxx org 16 alignment is enforced** for READ, WRITE and ERASE (byte
  addresses must be even and the wire field is the word address).
- **93C106** is modeled as the 64 Kbit member (8192 bytes, 13/12 address
  bits for org 8/16); parts sold under other density names are out of scope.
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
