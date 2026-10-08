# xiom.eeprom -- Specification

Version: 0.1.3 (stable; published on the XIOM registry).
Module: `src/eeprom.xi` (`module xiom.eeprom`).
Depends on `xiom.std`; the library module imports `xiom.convert`
(`int_to_string`) and `xiom.string.compare` (`str_compare`); the tests also
import `xiom.test`, `xiom.io` and `xiom.encoding.hex`.

## Scope

A pure-XIOM (no FFI) codec for the device-protocol layer of two serial
EEPROM families:

- **24Cxx (I2C)**: control byte `1010 A2A1A0 R/W`; the density table
  24C01..24C2048 (1..2048 Kbit) with word-address widths and page sizes;
  1/2-byte big-endian word-address fields; page-write boundary math
  (page start, next page start, bytes remaining, in-page write-pointer
  wrap); device-end wrap for current-address reads; range and page-write
  validation whose errors name the offending byte offset.
- **93Cxx (Microwire)**: the opcodes READ `10`, WRITE `101`, ERASE `111`,
  EWEN `10011`, EWDS `10000`, ERAL `10010`, WRAL `10001`; command + address
  (+ data for WRITE/WRAL) packed MSB first into bytes and decoded back into
  opcode, byte address, data and bit count; per-density address-field widths
  for org 8 and 16 over 93C46..93C106; word alignment for READ/WRITE/ERASE
  on org 16; the WRAL address-zero rule; READ-response data frames.
- A deterministic `Err(Str)` error catalog for malformed input and invalid
  fields.

## Non-goals

- **No bus I/O.** No I2C start/stop/ACK, no Microwire CS/CLK toggling, no
  timing (tCLK, write-cycle delays, ACK polling). Everything is in-memory
  `Vec[UInt8]` and `Int` values.
- **No device state.** No internal address-pointer register, no
  page-write scheduling, no READY/BUSY tracking, no EEPROM emulation.
- **No 24Cxx device-select high bits.** The codec models the 1/2-byte word
  address. On 24C1024/24C2048 the high address bit lives outside that
  field (device select pin / P0) and is the caller's responsibility.
- **No 24Cxx page-write scheduling.** The helper functions compute
  boundaries; splitting a long write into page-sized bursts is the
  caller's job (validation rejects a crossing burst).
- **No other densities.** 24C01..24C2048 and 93C46..93C106 only; no
  25-series SPI EEPROMs, no M95/95-series, no FRAM.
- **No datasheet timing parameters**, no pin-level electrical behavior.

## 24Cxx bit/byte-level description

### Control byte (device address)

| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|
| Value | 1 | 0 | 1 | 0 | A2 | A1 | A0 | R/W |

`ee24_control_byte(pins, read_op)` = `0xA0 + pins * 2 + read` where
`pins = A2*4 + A1*2 + A0` must be 0..7 and `read` is 1 for a read, 0 for a
write. Write base 0xA0 (160), read base 0xA1 (161).

### Density table

`ee24_density(name)` table (canonical names; `bits`/`bytes` are the memory
size, `addr_bytes` the word-address field width, `page_size` the page-write
size in bytes, `org` always 8):

| Name | bits | bytes | addr_bytes | page_size |
|---|---|---|---|---|
| 24C01 | 1024 | 128 | 1 | 8 |
| 24C02 | 2048 | 256 | 1 | 8 |
| 24C04 | 4096 | 512 | 1 | 16 |
| 24C08 | 8192 | 1024 | 1 | 16 |
| 24C16 | 16384 | 2048 | 1 | 16 |
| 24C32 | 32768 | 4096 | 2 | 32 |
| 24C64 | 65536 | 8192 | 2 | 32 |
| 24C128 | 131072 | 16384 | 2 | 64 |
| 24C256 | 262144 | 32768 | 2 | 64 |
| 24C512 | 524288 | 65536 | 2 | 128 |
| 24C1024 | 1048576 | 131072 | 2 | 256 |
| 24C2048 | 2097152 | 262144 | 2 | 256 |

### Word-address field

`ee24_word_address(addr, addr_bytes)` emits 1 byte (`addr` 0..255) or 2
bytes big-endian (most significant byte first, `addr` 0..65535). The field
carries no page bits; page selection is part of the byte address.

### Page-write math

For a non-negative byte address `addr`, page size `p > 0` and device size
`d > 0`:

- page start: `start = (addr / p) * p` (truncating division);
- next page start: `start + p` (equal to `d` on the last page);
- bytes remaining in the page: `p - (addr % p)`, in 1..p;
- page-write target of byte `k`: `start + ((addr - start + k) % p)` -- the
  write pointer wraps inside the starting page, so a crossing burst
  overwrites the page from its start;
- device wrap: `wrap(addr, d) = ((addr % d) + d) % d`, so a
  current-address read that passes the last byte restarts at 0;
- sequential address: `wrap(addr + k, d)`;
- write span: `min(p - (a % p), d - a)` with `a = wrap(addr, d)`, the
  contiguous burst before the next page boundary or the device end.

A zero or negative `p` / `d` makes the raw helpers return 0 instead of
dividing by zero; the validators reject those inputs.

## 93Cxx bit/byte-level description

### Opcode patterns

| Opcode constant | Value | Pattern | Pattern bits | First wire bit |
|---|---|---|---|---|
| `EE93_READ` | 2 | `10` | 2 | start bit `1` emitted first, so the wire prefix is `110` |
| `EE93_WRITE` | 5 | `101` | 3 | `1` |
| `EE93_ERASE` | 7 | `111` | 3 | `1` |
| `EE93_EWEN` | 19 | `10011` | 5 | `1` |
| `EE93_EWDS` | 16 | `10000` | 5 | `1` |
| `EE93_ERAL` | 18 | `10010` | 5 | `1` |
| `EE93_WRAL` | 17 | `10001` | 5 | `1` |

The patterns of WRITE, ERASE and the four specials already include the
mandatory start bit; READ is the only two-bit pattern and the encoder emits
the start bit before it (`1` + `10` = wire prefix `110`). The seven wire
prefixes are prefix-free, so a decoder can match them greedily.

### Frame layout (MSB first)

| Opcode | Wire bits |
|---|---|
| READ | `110` (3) + address (A bits) |
| WRITE | `101` (3) + address (A bits) + data (8 or 16) |
| ERASE | `111` (3) + address (A bits) |
| EWEN | `10011` (5) + address field (A zero bits, don't-care) |
| EWDS | `10000` (5) + address field (A zero bits, don't-care) |
| ERAL | `10010` (5) + address field (A zero bits, don't-care) |
| WRAL | `10001` (5) + address field (A zero bits) + data (8 or 16) |

Bits are emitted most-significant-first and packed into bytes from bit 7 of
byte 0; the final byte is zero-padded. The decoder reads only the command's
bits and ignores any trailing bits or bytes.

### Address field width A per density and org

| Name | bits (size) | org 8: A, words | org 16: A, words |
|---|---|---|---|
| 93C46 | 1024 | 7, 128 | 6, 64 |
| 93C56 | 2048 | 8, 256 | 7, 128 |
| 93C66 | 4096 | 9, 512 | 8, 256 |
| 93C76 | 8192 | 10, 1024 | 9, 512 |
| 93C86 | 16384 | 11, 2048 | 10, 1024 |
| 93C106 | 65536 | 13, 8192 | 12, 4096 |

`ee93_bytes(name, org)` = bits / 8 (org-independent storage bytes);
`ee93_address_bits(name, org)` = log2(bytes / org_bytes) where org_bytes is
1 for org 8 and 2 for org 16; `ee93_word_count(name, org)` =
`2^address_bits`. `EepromDensity.addr_bytes` for a 93Cxx row is
`ceil(address_bits / 8)`.

The public API addresses memory by byte offset on both orgs:

- org 8: byte address 0..bytes-1; the wire field is the byte address;
- org 16: byte address must be even (word-aligned); the wire field is the
  word address `byte_address / 2`, so the field covers 0..word_count-1.

### Data field

WRITE carries one data cell: 8 bits on org 8 (0..255), 16 bits on org 16
(0..65535). WRAL carries one data cell with the same width and writes it to
the whole array. Other opcodes carry no data.

### Rules

- **WRAL address zero**: `ee93_encode` rejects a WRAL with a nonzero
  address (Err "WRAL address must be 0") and `ee93_decode` rejects a WRAL
  frame whose address bits are nonzero (Err "WRAL address field must be 0").
- **Don't-care specials**: EWEN, EWDS and ERAL addresses are ignored on
  encode (zero bits are emitted) and reported as 0 on decode.
- **Alignment**: READ, WRITE and ERASE byte addresses must be divisible by
  the org cell size (2 on org 16).
- **Range**: READ/WRITE/ERASE byte addresses must be 0..bytes-1.

### READ responses

A READ response is a data frame of exactly org bits: 8 bits in 1 byte
(org 8) or 16 bits in 2 big-endian bytes (org 16). `ee93_encode_read_response`
validates the value range and emits it; `ee93_decode_read_response` reads
the first 1/2 bytes and ignores the rest.

## Types

```xi
pub type EepromDensity = { name: Str; bits: Int; bytes: Int; addr_bytes: Int; page_size: Int; org: Int; }
pub type Ee93Command = { density: Str; org: Int; opcode: Int; address: Int; data: Int; }
pub type Ee93Decoded = { opcode: Int; address: Int; data: Int; bits: Int; }
```

`EepromDensity.bytes` is always `bits / 8`. For 24Cxx rows `org` is 8; for
93Cxx rows `page_size` is 0. `Ee93Decoded.bits` is the exact wire bit count
of the decoded command; `address` is 0 for the specials.

## API contract

All functions are free functions in module `xiom.eeprom`; there are no
methods and no state. Every fallible function validates in the order listed
and returns `Err` without a partial result; error text is stable.

```xi
pub fn ee24_control_byte(addr_pins: Int, read_op: Bool) -> Result[Int, Str]
pub fn ee24_device_address_write(addr_pins: Int) -> Result[Int, Str]
pub fn ee24_device_address_read(addr_pins: Int) -> Result[Int, Str]
pub fn ee24_density(name: Str) -> Result[EepromDensity, Str]
pub fn ee24_page_size(name: Str) -> Int
pub fn ee24_addr_bytes(name: Str) -> Int
pub fn ee24_bytes(name: Str) -> Int
pub fn ee24_bits(name: Str) -> Int
pub fn ee24_word_address(addr: Int, addr_bytes: Int) -> Result[Vec[UInt8], Str]
pub fn ee24_page_start(addr: Int, page_size: Int) -> Int
pub fn ee24_next_page_start(addr: Int, page_size: Int) -> Int
pub fn ee24_page_remaining(addr: Int, page_size: Int) -> Int
pub fn ee24_write_target(addr: Int, offset: Int, page_size: Int) -> Int
pub fn ee24_wrap_address(addr: Int, device_bytes: Int) -> Int
pub fn ee24_seq_address(addr: Int, offset: Int, device_bytes: Int) -> Int
pub fn ee24_write_span(addr: Int, page_size: Int, device_bytes: Int) -> Int
pub fn ee24_validate_address(addr: Int, device_bytes: Int) -> Result[Unit, Str]
pub fn ee24_validate_page_write(addr: Int, count: Int, page_size: Int) -> Result[Unit, Str]
pub fn ee93_address_bits(name: Str, org: Int) -> Int
pub fn ee93_bytes(name: Str, org: Int) -> Int
pub fn ee93_word_count(name: Str, org: Int) -> Int
pub fn ee93_density(name: Str, org: Int) -> Result[EepromDensity, Str]
pub fn ee93_opcode_name(opcode: Int) -> Str
pub fn ee93_encode(cmd: &Ee93Command) -> Result[Vec[UInt8], Str]
pub fn ee93_decode(data: &Vec[UInt8], density: Str, org: Int) -> Result[Ee93Decoded, Str]
pub fn ee93_encode_read_response(value: Int, org: Int) -> Result[Vec[UInt8], Str]
pub fn ee93_decode_read_response(data: &Vec[UInt8], org: Int) -> Result[Int, Str]
```

### Semantics and validation order

`ee24_control_byte(pins, read_op)`
: 1. `pins` outside 0..7 -> `eeprom.24cxx: address pins N out of range 0..7`;
  2. `0xA0 + pins * 2 + read`.

`ee24_device_address_write(pins)` / `ee24_device_address_read(pins)`
: `ee24_control_byte(pins, false)` / `ee24_control_byte(pins, true)`
  (R/W = 0 / 1).

`ee24_density(name)`
: Twelve canonical names `24C01`..`24C2048`; anything else ->
  `eeprom.24cxx: unknown density "<name>"`. The match is exact and
  case-sensitive (`str_compare`).

`ee24_page_size(name)` / `ee24_addr_bytes(name)` / `ee24_bytes(name)` /
`ee24_bits(name)`
: Density row field, or -1 for an unknown name. They never fail.

`ee24_word_address(addr, addr_bytes)`
: 1. `addr_bytes` not 1 or 2 -> `eeprom.24cxx: invalid address width N`;
  2. `addr` outside `0..2^(8*addr_bytes)-1` -> `eeprom.24cxx: word address
  N does not fit in M address byte(s)`;
  3. 1 byte for `addr_bytes == 1`, otherwise high byte then low byte.

`ee24_page_start` / `ee24_next_page_start` / `ee24_page_remaining` /
`ee24_write_target`
: Pure formulas from the page-write math section. A non-positive
  `page_size` returns 0. `addr < 0` is not rejected (truncating division
  applies); callers validate first.

`ee24_wrap_address(addr, device_bytes)` / `ee24_seq_address(addr, offset,
device_bytes)`
: Device-end wrap formulas; a non-positive `device_bytes` returns 0;
  negative dividends are corrected to non-negative results.

`ee24_write_span(addr, page_size, device_bytes)`
: `min(page_remaining, device_bytes - a)` with `a = wrap(addr, d)`;
  non-positive sizes return 0.

`ee24_validate_address(addr, device_bytes)`
: 1. `device_bytes <= 0` -> `eeprom.24cxx: invalid device size N`;
  2. `addr` outside `0..device_bytes-1` -> `eeprom.24cxx: byte address N
  out of range 0..M`.

`ee24_validate_page_write(addr, count, page_size)`
: 1. `page_size <= 0` -> `eeprom.24cxx: invalid page size N`;
  2. `addr < 0` -> `eeprom.24cxx: negative byte address N`;
  3. `count < 1` -> `eeprom.24cxx: page write count N must be at least 1`;
  4. `count > page_remaining(addr, page_size)` -> `eeprom.24cxx: page write
  of N bytes at address A crosses the page boundary at byte offset R (page
  size P)`, where R is the number of bytes that fit.

`ee93_density(name, org)`
: 1. `org` not 8 or 16 -> `eeprom.93cxx: org N is not 8 or 16`;
  2. name not one of the six canonical names -> `eeprom.93cxx: unknown
  density "<name>" for org N`;
  3. row with `bytes = bits / 8`, `addr_bytes = ceil(A / 8)`,
  `page_size = 0`, `org` as given.

`ee93_address_bits` / `ee93_bytes` / `ee93_word_count`
: Computed values or -1 for an invalid org or unknown name; they never
  fail.

`ee93_opcode_name(opcode)`
: The seven names or `"unknown"`; never fails. `EE93_READ` is the 2-bit
  pattern value 2 (not the wire prefix 6).

`ee93_encode(cmd)`
: 1. density/org errors from `ee93_density` (org checked before name);
  2. unknown opcode -> `eeprom.93cxx: invalid opcode N`;
  3. WRAL with `address != 0` -> `eeprom.93cxx: WRAL address must be 0`;
  4. READ/WRITE/ERASE address outside `0..bytes-1` -> `eeprom.93cxx: byte
  address N out of range 0..M for <name> org O`;
  5. org 16 with an odd address -> `eeprom.93cxx: byte address N is not
  aligned for org 16`;
  6. WRITE/WRAL data outside `0..2^org - 1` -> `eeprom.93cxx: data N out
  of range 0..M for org O`;
  7. emit the frame bits (start bit + pattern + address + data) and pack
  them MSB first with zero padding.

`ee93_decode(data, density, org)`
: 1. density/org errors from `ee93_density`;
  2. fewer than 3 bits -> `eeprom.93cxx: truncated command: need 3 bits,
  have N` (with byte-aligned inputs the 5-bit variant of this check is
  defensive only);
  3. match the 3-bit prefix (110 READ, 101 WRITE, 111 ERASE); a 100 prefix
  reads 2 more bits (10011 EWEN, 10000 EWDS, 10010 ERAL, 10001 WRAL);
  4. unmatched prefix -> `eeprom.93cxx: unknown opcode prefix P at bit 0`;
  5. fewer bits than prefix + address (+ data) -> `eeprom.93cxx: truncated
  command: need N bits, have M`;
  6. WRAL address bits nonzero -> `eeprom.93cxx: WRAL address field must be
  0`;
  7. result: opcode, byte address (`raw * org_bytes` for READ/WRITE/ERASE,
  0 for the specials), data (WRITE/WRAL, else 0), exact bit count.

`ee93_encode_read_response(value, org)`
: 1. org not 8 or 16 -> `eeprom.93cxx: org N is not 8 or 16`;
  2. value outside `0..2^org - 1` -> `eeprom.93cxx: read response value N
  out of range 0..M for org O`;
  3. 1 byte (org 8) or big-endian 2 bytes (org 16).

`ee93_decode_read_response(data, org)`
: 1. org not 8 or 16 -> the org error above;
  2. fewer than `org / 8` bytes -> `eeprom.93cxx: read response needs N
  byte(s), have M`;
  3. value of the first `org / 8` bytes, MSB first.

## Error string catalog

| Condition | Error text |
|---|---|
| 24Cxx pin strapping outside 0..7 | `eeprom.24cxx: address pins N out of range 0..7` |
| Unknown 24Cxx density name | `eeprom.24cxx: unknown density "<name>"` |
| 24Cxx word-address width not 1 or 2 | `eeprom.24cxx: invalid address width N` |
| 24Cxx word address outside the field | `eeprom.24cxx: word address N does not fit in M address byte(s)` |
| Non-positive device size | `eeprom.24cxx: invalid device size N` |
| Byte address outside 0..size-1 | `eeprom.24cxx: byte address N out of range 0..M` |
| Non-positive page size | `eeprom.24cxx: invalid page size N` |
| Negative page-write address | `eeprom.24cxx: negative byte address N` |
| Page-write count below 1 | `eeprom.24cxx: page write count N must be at least 1` |
| Page write crossing its page | `eeprom.24cxx: page write of N bytes at address A crosses the page boundary at byte offset R (page size P)` |
| 93Cxx org not 8 or 16 | `eeprom.93cxx: org N is not 8 or 16` |
| Unknown 93Cxx density name | `eeprom.93cxx: unknown density "<name>" for org N` |
| Unknown 93Cxx opcode constant | `eeprom.93cxx: invalid opcode N` |
| READ/WRITE/ERASE address outside the device | `eeprom.93cxx: byte address N out of range 0..M for <name> org O` |
| Odd address on org 16 | `eeprom.93cxx: byte address N is not aligned for org 16` |
| WRAL with a nonzero address | `eeprom.93cxx: WRAL address must be 0` |
| WRAL frame with nonzero address bits | `eeprom.93cxx: WRAL address field must be 0` |
| WRITE/WRAL data outside the cell | `eeprom.93cxx: data N out of range 0..M for org O` |
| Fewer bits than the command needs | `eeprom.93cxx: truncated command: need N bits, have M` |
| Unmatched wire prefix | `eeprom.93cxx: unknown opcode prefix P at bit 0` |
| READ response value outside org | `eeprom.93cxx: read response value N out of range 0..M for org O` |
| READ response buffer too short | `eeprom.93cxx: read response needs N byte(s), have M` |

## Complexity

| Operation | Time | Space |
|---|---|---|
| `ee24_control_byte`, `ee24_word_address` | O(1) | O(1) |
| `ee24_density` and accessors | O(1) (twelve `str_compare` calls) | O(1) |
| 24Cxx page/wrap helpers and validators | O(1) | O(1) |
| `ee93_density`, `ee93_address_bits`, `ee93_bytes`, `ee93_word_count` | O(1) (six `str_compare` calls) | O(1) |
| `ee93_encode` | O(address bits + org) = O(1) per density | O(address bits + org) |
| `ee93_decode` | O(command bits) | O(1) |
| `ee93_*_read_response` | O(1) | O(1) |

## Test plan

`tests/test_conformance.xi` (`module eeprom_tests`, 17 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. 24Cxx control byte: pins 0..7 both directions, pinned values 160/161/
   174/171/166/167/162/163, pin -1 and 8 rejected;
2. 24Cxx word address: 1- and 2-byte encodings (`A5`, `00A5`, `FF`,
   `FFFF`), 256-in-1 and 65536-in-2 rejected, negative rejected, width 3
   rejected, 24C16/24C32 widths, -1 for an unknown name;
3. 24Cxx density table: all twelve rows against pinned bits/bytes/address
   bytes/page sizes, accessor spot checks, unknown name error;
4. 24Cxx page math: page start, next page start, bytes remaining, in-page
   write-target wrap, zero-page-size guards;
5. 24Cxx device-end wrap: current-address read wrap (including negative
   input), sequential address wrap, write-span clipping at page and device
   ends;
6. 24Cxx validation: address range errors, page-write crossing errors with
   the boundary byte offset, count/negative/page-size errors;
7. 93Cxx density table: all six densities at org 8 and 16 with pinned bits,
   address bits, word counts and derived `addr_bytes`, unknown name and org
   errors;
8. 93Cxx opcode constants: values 2/5/7/19/16/18/17 and the name mapping,
   including `"unknown"`;
9. 93Cxx READ/ERASE pinned frames (`C1 80`, `C1 40`, `E0 80`) with a
   test-local bit-packer cross-check;
10. 93Cxx WRITE pinned frames (`A1 09 1A 00` 25 bits, `A0 29 40` 18 bits)
    with the cross-check;
11. 93Cxx specials pinned frames (`98 00`, `80 00`, `90 00`, `88 0A B5 40`)
    plus the EWEN don't-care address rule;
12. 93Cxx round-trip: all seven opcodes across all six densities and both
    orgs, at address 0 and the maximum aligned address;
13. 93Cxx decode pinned frames (`C1 80`, `A1 09 1A 00`, `98 00`, `98 20`,
    `90 00`), don't-care specials reported as address 0, WRAL
    nonzero-address rejection (`88 20 00 00`);
14. 93Cxx validation: org-16 alignment for WRITE and READ, address range
    (128/-1 on org 8), data range (256 org 8, 65536 org 16), invalid
    opcode 3, WRAL nonzero address, org 12, unknown density, decode
    truncation (`C0`, empty) and unknown prefixes (`00 00` -> 0,
    `20 00` -> 1);
15. 93Cxx READ responses: encode/decode org 8 and 16, `FF 00` = 65280,
    value-range and short-buffer errors, round-trip loop;
16. 24C64/24C2048 pipeline: density lookup, control byte, 2-byte word
    address, last-page write boundary and in-page wrap, device-end wrap
    and write span at both device ends;
17. determinism: repeated encodes/decodes agree byte for byte and field for
    field, equal-content commands encode identically, repeated word
    addresses agree.

Fixtures: hex literals come from `xiom.encoding.hex`; 93Cxx frames are
additionally cross-checked against `ref_pack`, a test-local bit packer
written with a different chunking strategy, so a shared bug in the module
packer cannot pass unnoticed. No `Str` value is compared with `==` (BUG 17
discipline); error messages go through
`xiom.string.compare.str_compare`. All `Vec[UInt8]` element reads are bound
to typed locals and widened with `& 0xFF`.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.eeprom
```

Last verified: compiler 0.64.0,
`port: PASS (passed=17 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No transport, no timing, no ACK polling and no device state (see
  Non-goals).
- 24C1024/24C2048 need a high address bit outside the 2-byte word field
  (device select / P0); the codec validates only the field width.
- 24C01..24C16 pin strapping vs. embedded address bits is conventional:
  the table reports the standard density/pin layout, not per-vendor pin
  mapping.
- A crossing page write is rejected by validation; the raw wrap math is
  available through `ee24_write_target` for callers that want it.
- 93Cxx specials' address fields are don't-care and always emitted as
  zeros; decoded specials report address 0.
- READ responses are data bits only; no READY/BUSY bit and no clocking.
- `ee93_decode` ignores trailing bits/bytes after the command, so a byte
  buffer can hold a command followed by unrelated data.
- Only the seven documented opcodes are supported; no vendor extensions.

## Compiler / stdlib notes for v0.64.0

- Free functions only: no methods, no lambdas, no `Vec[fn]` dispatch, no
  `Vec[StructType]`.
- `Ok`/`Err` construction is confined to the tiny leaf helpers
  (`_ok_unit`/`_err_unit`, `_ok_bytes`/`_err_bytes`, `_ok_int`/`_err_int`,
  `_ok_density`/`_err_density`, `_ok_decoded`/`_err_decoded`), because
  constructing Results directly inside other functions miscompiles.
- Str comparisons go through `xiom.string.compare.str_compare` after the
  values are bound to typed locals (BUG 17: `==` on a Str from a `Vec[Str]`
  lowers to a pointer compare).
- `&struct.field` is never passed as a `&Vec[UInt8]` parameter (that yields
  an empty vector); fields are bound to typed locals first.
- Every `Vec[UInt8]` byte read is widened with `(x as Int) & 0xFF` before
  entering Int arithmetic.
- Bit extraction uses division by powers of two (`_pow2`), never a shift on
  a value that could carry the sign bit; ceil division is
  `q + (r > 0 ? 1 : 0)` rather than `(a + b - 1) / b`.
- Dynamic error strings are built with `xiom.convert.int_to_string` (the
  `xiom.convert` module, imported as `convert`).
- The package declares no `extern "C"` blocks (no FFI).

## Contracts (batch #37 hardening pass, 2026-10-07)

Runtime-checkable `ensures:` clauses added to `src/eeprom.xi` in the batch #37
hardening pass (compiler v0.64.0; `package.xi` is left for the coordinator to
bump at integration). 65 clauses over the 27 contracted public entry points,
all `ensures:` (no `requires:`), so the accepted-input domain is unchanged.
Two consecutive `& .\scripts\port.ps1 -Package xiom.eeprom -TimeoutSec 60`
runs ended `port: PASS (passed=17 failed=0 program_exit=0 exit=0)` with the
clauses active (5.44 s and 5.24 s); no clause trapped and none was dropped.
Every clause holds for hand-built values and structs: the guards keep the
source's own validation branches, and no clause strengthens a claim an
out-of-band `Ee93Command` or `Vec[UInt8]` buffer could falsify.

Clause inputs are parameters or parameter fields only. `EepromDensity` result
payload fields are never read; the table bands (bytes 128..262144, bits
1024..2097152, page 8..256, `addr_bytes` 1|2, 93Cxx address bits 6..13, bytes
128..8192, words 64..8192) are inlined as integer literals (no module
constants). The division/modulo clauses mirror the body formulas exactly
(`(addr / page_size) * page_size`, `page_size - (addr % page_size)`); the
`ee24_write_target` clause is deliberately weakened to the in-page range
`0 .. next_page_start - 1` (guarded by `page_size > 0 && addr >= 0 &&
offset >= 0`, since truncating `%` can go negative otherwise). The only
clause call is the definitional `ee24_seq_address` identity, whose callee
`ee24_wrap_address` never calls its caller (non-re-entrant). No clauses were
dropped and no probe-gated items applied.

`xiom-verify src/eeprom.xi --check` (Z3 bundled with v0.64.0) reported
**2 proven / 0 violated / 55 unknown / 15 errors**. The errors are SMT
emitter bugs on bodies that call private helpers (`unknown constant _pow2`,
`ee93_bits`, `_read_bits`, `_ee93_has_data`, `_ok_int`, "arguments missing"),
which the tool itself labels "not a proof failure of the code under test".
The two Z3-proven clauses are exactly `ee24_next_page_start`'s
`page_size <= 0 => result == 0` guard and the `ee24_seq_address` identity
(both emitted complete check-sat blocks); every other clause is enforced by
the v0.64.0 runtime evaluator when the conformance suite runs, with no Z3
claim.

| Entry point | Clause(s) added | Class |
|---|---|---|
| `ee24_control_byte` | `(addr_pins < 0 \|\| addr_pins > 7) => result is Err`; `result is Ok => result.value >= 160 && result.value <= 175` | runtime-checked |
| `ee24_device_address_write` | `(addr_pins < 0 \|\| addr_pins > 7) => result is Err`; `result is Ok => result.value >= 160 && result.value <= 174` | runtime-checked |
| `ee24_device_address_read` | `(addr_pins < 0 \|\| addr_pins > 7) => result is Err`; `result is Ok => result.value >= 161 && result.value <= 175` | runtime-checked |
| `ee24_density` | `name.len() == 0 => result is Err`; `result is Ok => name.len() >= 5 && name.len() <= 7` | runtime-checked |
| `ee24_page_size` | `name.len() == 0 => result == -1`; `result == -1 \|\| (result >= 8 && result <= 256)` | runtime-checked |
| `ee24_addr_bytes` | `name.len() == 0 => result == -1`; `result == -1 \|\| result == 1 \|\| result == 2` | runtime-checked |
| `ee24_bytes` | `name.len() == 0 => result == -1`; `result == -1 \|\| (result >= 128 && result <= 262144)` | runtime-checked |
| `ee24_bits` | `name.len() == 0 => result == -1`; `result == -1 \|\| (result >= 1024 && result <= 2097152)` | runtime-checked |
| `ee24_word_address` | `(addr_bytes != 1 && addr_bytes != 2) => result is Err`; `addr < 0 => result is Err`; `result is Ok => addr >= 0 && addr <= 65535` | runtime-checked |
| `ee24_page_start` | `page_size <= 0 => result == 0`; `page_size > 0 => result == (addr / page_size) * page_size` | runtime-checked |
| `ee24_next_page_start` | `page_size <= 0 => result == 0` (**Z3-proven**); `page_size > 0 => result == (addr / page_size) * page_size + page_size` | 1 Z3-proven / 1 runtime-checked |
| `ee24_page_remaining` | `page_size <= 0 => result == 0`; `page_size > 0 => result == page_size - (addr % page_size)` | runtime-checked |
| `ee24_write_target` | `page_size <= 0 => result == 0`; `page_size > 0 && addr >= 0 && offset >= 0 => result >= 0 && result < (addr / page_size) * page_size + page_size` | runtime-checked |
| `ee24_wrap_address` | `device_bytes <= 0 => result == 0`; `device_bytes > 0 => result >= 0 && result < device_bytes` | runtime-checked |
| `ee24_seq_address` | `result == ee24_wrap_address(addr + offset, device_bytes)` | Z3-proven |
| `ee24_write_span` | `(page_size <= 0 \|\| device_bytes <= 0) => result == 0`; `page_size > 0 && device_bytes > 0 => result >= 1 && result <= device_bytes` | runtime-checked |
| `ee24_validate_address` | `device_bytes <= 0 => result is Err`; `(addr < 0 \|\| addr >= device_bytes) => result is Err`; `result is Ok => addr >= 0`; `result is Ok => addr < device_bytes` | runtime-checked |
| `ee24_validate_page_write` | `page_size <= 0 => result is Err`; `count < 1 => result is Err`; `result is Ok => count >= 1`; `result is Ok => count <= page_size` | runtime-checked |
| `ee93_address_bits` | `(org != 8 && org != 16) => result == -1`; `name.len() == 0 => result == -1`; `result != -1 => result >= 6`; `result != -1 => result <= 13` | runtime-checked |
| `ee93_bytes` | `result == -1 \|\| (result >= 128 && result <= 8192)` | runtime-checked |
| `ee93_word_count` | `result == -1 \|\| (result >= 64 && result <= 8192)` | runtime-checked |
| `ee93_density` | `(org != 8 && org != 16) => result is Err`; `name.len() == 0 => result is Err`; `result is Ok => name.len() >= 5 && name.len() <= 6` | runtime-checked |
| `ee93_opcode_name` | `result.len() >= 4 && result.len() <= 7`; `(opcode != 2 && opcode != 5 && opcode != 7 && opcode != 16 && opcode != 17 && opcode != 18 && opcode != 19) => result.len() == 7` | runtime-checked |
| `ee93_encode` | `(cmd.org != 8 && cmd.org != 16) => result is Err`; `cmd.density.len() == 0 => result is Err`; `(cmd.opcode != 2 && cmd.opcode != 5 && cmd.opcode != 7 && cmd.opcode != 16 && cmd.opcode != 17 && cmd.opcode != 18 && cmd.opcode != 19) => result is Err` | runtime-checked |
| `ee93_decode` | `(org != 8 && org != 16) => result is Err`; `density.len() == 0 => result is Err`; `data.len() == 0 => result is Err` | runtime-checked |
| `ee93_encode_read_response` | `(org != 8 && org != 16) => result is Err`; `value < 0 => result is Err`; `result is Ok => value >= 0`; `result is Ok => value <= 65535` | runtime-checked |
| `ee93_decode_read_response` | `(org != 8 && org != 16) => result is Err`; `data.len() == 0 => result is Err`; `result is Ok => result.value >= 0`; `result is Ok => result.value <= 65535` | runtime-checked |
