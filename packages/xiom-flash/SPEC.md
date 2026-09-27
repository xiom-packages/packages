# xiom.flash -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.flash`, version `0.1.0`).
Module: `src/flash.xi` (`module xiom.flash`).
Depends on `xiom.std`; the library module imports nothing from it. The tests
import `xiom.test`, `xiom.io`, `xiom.string.compare` and
`xiom.encoding.hex`.

## Scope

A pure-XIOM (no FFI) codec for the identification layer of SPI NOR flash
memory, bytes in / typed values out:

- **JEDEC ID** (RDID 0x9F, 3 bytes): manufacturer byte, memory type byte,
  capacity byte -> `2^N` bytes, with a documented manufacturer subset;
- **command set**: 18 pinned 25-series opcodes as constants plus a
  table/name/index API;
- **status register 1**: WIP, WEL, BP0..BP2, TB, SEC, SRP0;
- **SFDP (JESD216)**: header, parameter header table, and the Basic Flash
  Parameter Table (density, address modes, DTR, fast-read commands and
  clocks, page size, erase types and derived erase flags);
- **sector map**: address -> sector index / offset and index -> range with
  divisor/modulo and documented boundary rules;
- a deterministic `Err(FlashError)` catalog with byte offsets.

## Non-goals

- **No device access.** No SPI transactions, chip-select handling, dummy
  cycles, address phases, timing or busy polling. The caller supplies the
  RDID/SFDP images; this module never touches a bus.
- **No RES/REMS ID formats** (0xAB/0x90) and no vendor-specific ID tables
  beyond the documented subset.
- **No optional SFDP table decoding.** The sector map table (0xFF81), the
  4-byte address instruction table (0xFF84) and xSPI tables are identified
  by their parameter IDs but not decoded. Only the JEDEC basic table
  (0xFF00) is decoded, structurally.
- **No octal/DTR command details** beyond the BFPT DTR support flag, and no
  vendor quad-enable procedures (QER).
- **No write/erase execution semantics**, no protection-bit enforcement, no
  timing.
- No FFI, no `extern "C"`, no unsafe code.

## Integer and encoding rules

All arithmetic is signed 64-bit `Int` on non-negative values in this
decoder.

- Every byte read from a `Vec[UInt8]` is widened and masked:
  `(data[i] as Int) & 0xFF` (v0.61.3: widening a byte >= 0x80 must be
  masked).
- Little-endian 32-bit SFDP fields are composed byte by byte:
  `b0 + b1*256 + b2*65536 + b3*16777216`; 24-bit pointers:
  `b0 + b1*256 + b2*65536`; 16-bit parameter IDs: `lsb + msb*256`. No
  shifts are used on values that can carry a sign bit.
- All bit tests are `(value / 2^k) % 2` on non-negative values.
- Division is truncating; all operands here are non-negative, so it is
  floor division. Ceiling division for `flash_sector_count` is
  `q = a / b; r = a % b; if r > 0 { q + 1 } else { q }`.
- Capacity/density truncation: BFPT density is in bits and
  `capacity_bytes = density_bits / 8`.
- The decoder is deterministic and independent of time or device state:
  repeated parses of the same buffer are byte-for-byte equivalent.

## JEDEC ID (RDID 0x9F response)

Three bytes are read, in order:

| Offset | Field | Meaning |
|---|---|---|
| 0 | manufacturer ID | JEDEC manufacturer byte |
| 1 | memory type | vendor memory-type byte (not decoded) |
| 2 | capacity code N | capacity = `2^N` bytes, N accepted in 8..32 |

`flash_jedec_id_parse(id)` reads only the first three bytes; extra bytes
are ignored. Capacity code 8 = 256 B, 24 = 16 MiB, 32 = 4 GiB.

### Manufacturer subset (documented)

| Index | ID | Name |
|---|---|---|
| 0 | 0x01 | Spansion/Cypress |
| 1 | 0x1F | Adesto |
| 2 | 0x20 | Micron |
| 3 | 0xBF | SST/Microchip |
| 4 | 0xC2 | Macronix |
| 5 | 0xEF | Winbond |
| 6 | 0x62 | Sanyo |
| 7 | 0x8C | ESMT |
| 8 | 0x5E | Zbit |

Any other ID is valid input: the decoded name is `"unknown"`.
`flash_manufacturer_id_at` / `flash_manufacturer_name_at` accept 0..8 and
return -1 / `"unknown"` outside that range.

### Validation order and errors

| Order | Condition | Result |
|---|---|---|
| 1 | `id.len() < 3` | `Err(id.len(), "flash: jedec id truncated")` |
| 2 | capacity code outside 8..32 | `Err(2, "flash: invalid capacity code")` |
| 3 | otherwise | `Ok(FlashJedecId)` |

`flash_capacity_bytes(code)` is the standalone form:
`Err(-1, "flash: invalid capacity code")` outside 8..32, else `Ok(2^code)`.

## Command set (25-series subset)

`flash_command_table()` returns exactly this order; `flash_command_code(i)`
is a bounds-checked read (0..17, else -1).

| Index | Constant | Opcode | `flash_command_name` |
|---|---|---|---|
| 0 | FLASH_CMD_READ | 0x03 | READ |
| 1 | FLASH_CMD_FAST_READ | 0x0B | FAST_READ |
| 2 | FLASH_CMD_FAST_READ_QUAD_IO | 0xEB | FAST_READ_QUAD_IO |
| 3 | FLASH_CMD_PAGE_PROGRAM | 0x02 | PAGE_PROGRAM |
| 4 | FLASH_CMD_SECTOR_ERASE | 0x20 | SECTOR_ERASE |
| 5 | FLASH_CMD_BLOCK_ERASE | 0xD8 | BLOCK_ERASE |
| 6 | FLASH_CMD_WRITE_ENABLE | 0x06 | WRITE_ENABLE |
| 7 | FLASH_CMD_WRITE_DISABLE | 0x04 | WRITE_DISABLE |
| 8 | FLASH_CMD_READ_STATUS1 | 0x05 | READ_STATUS1 |
| 9 | FLASH_CMD_READ_STATUS2 | 0x35 | READ_STATUS2 |
| 10 | FLASH_CMD_WRITE_STATUS | 0x01 | WRITE_STATUS |
| 11 | FLASH_CMD_READ_ID | 0x9F | READ_ID |
| 12 | FLASH_CMD_READ_SFDP | 0x5A | READ_SFDP |
| 13 | FLASH_CMD_CHIP_ERASE | 0xC7 | CHIP_ERASE |
| 14 | FLASH_CMD_CHIP_ERASE_ALT | 0x60 | CHIP_ERASE_ALT |
| 15 | FLASH_CMD_READ_4B | 0x4B | READ_4B |
| 16 | FLASH_CMD_RESET_ENABLE | 0x66 | RESET_ENABLE |
| 17 | FLASH_CMD_RESET | 0x99 | RESET |

Any opcode outside the table decodes to `"unknown"`; no error is raised.

## Status register 1

| Bit | Name | Constant |
|---|---|---|
| 0 | WIP write in progress | FLASH_SR1_BIT_WIP |
| 1 | WEL write enable latch | FLASH_SR1_BIT_WEL |
| 2 | BP0 | FLASH_SR1_BIT_BP0 |
| 3 | BP1 | FLASH_SR1_BIT_BP1 |
| 4 | BP2 | FLASH_SR1_BIT_BP2 |
| 5 | TB top/bottom protect | FLASH_SR1_BIT_TB |
| 6 | SEC sector/block protect | FLASH_SR1_BIT_SEC |
| 7 | SRP0 status register protect | FLASH_SR1_BIT_SRP0 |

`block_protect = BP2*4 + BP1*2 + BP0` (0..7).
`flash_sr1_parse(byte)` requires `0 <= byte <= 255`, otherwise
`Err(-1, "flash: status byte out of range")`. The scalar helpers
`flash_sr1_wip` / `flash_sr1_wel` return false and
`flash_sr1_block_protect` returns -1 for out-of-range bytes.

## SFDP (JESD216)

### Header (8 bytes)

| Offset | Size | Field |
|---|---|---|
| 0x00 | 4 | signature bytes `53 46 44 50` ("SFDP"); LE word 0x50444653 |
| 0x04 | 1 | minor revision |
| 0x05 | 1 | major revision (must be 1) |
| 0x06 | 1 | NPH: 0-based parameter header count |
| 0x07 | 1 | unused (not enforced by the decoder) |

`parameter_header_count = NPH + 1`.

### Parameter header table

Entry `i` starts at `8 + 8*i`, for `i` in `0..parameter_header_count-1`:

| Offset | Size | Field |
|---|---|---|
| +0 | 1 | parameter ID LSB |
| +1 | 1 | parameter ID MSB |
| +2 | 1 | table major revision |
| +3 | 1 | table minor revision |
| +4 | 3 | parameter table pointer, 24-bit little-endian |
| +7 | 1 | parameter table length in DWORDs |

`id = id_lsb + id_msb*256`. Pinned IDs: `0xFF00` JEDEC basic flash
parameter table (`FLASH_SFDP_BASIC_ID`), `0xFFFF` unused/not supported
(`FLASH_SFDP_UNUSED_ID`), `0xFF81` sector map, `0xFF84` 4-byte address
instruction table. The sector-map/4BAIT IDs have predicate helpers but no
decoder.

**Basic table selection** (`flash_sfdp_basic_param`): every entry is
scanned in order. An entry with ID 0xFF00 and major revision != 1 is a hard
error; among valid basic entries the one with the highest minor revision
wins, ties broken by the largest length. No basic entry ->
`Err(-1, "flash: sfdp basic table missing")`.

### Basic Flash Parameter Table (BFPT)

Offsets are relative to the table pointer, which must be 4-byte aligned in
practice but is only bounds-checked. The table must have at least 9 DWORDs
(JESD216 rev A base). Fields implemented:

| DWORD (offset) | Bits | Field |
|---|---|---|
| 1 (0x00) | [18:17] | address mode: 0 = 3-byte only, 1 = 3 or 4, 2 = 4-byte only, 3 = reserved |
| 1 (0x00) | 19 | DTR (double transfer rate) support |
| 1 (0x00) | 16 / 20 / 22 / 21 | fast read 1-1-2 / 1-2-2 / 1-1-4 / 1-4-4 supported |
| 2 (0x04) | 31 | density encoding select: 1 = `2^[30:0]` bits, 0 = `[30:0] + 1` bits |
| 3 (0x08) | [15:0] / [31:16] | 1-4-4 / 1-1-4 setting half |
| 4 (0x0C) | [15:0] / [31:16] | 1-1-2 / 1-2-2 setting half |
| 8 (0x1C) | [15:0] / [31:16] | erase type 1 / 2: size exponent [7:0], opcode [15:8] |
| 9 (0x20) | [15:0] / [31:16] | erase type 3 / 4: size exponent [7:0], opcode [15:8] |
| 11 (0x28) | [7:4] | page size exponent N: page = `2^N` bytes |

Setting half decode: `opcode = (half / 256) % 256`,
`mode_clocks = (half / 32) % 8`, `wait_states = half % 32`. Settings of
unsupported commands decode to zeros (`supported` false).

Erase type: exponent byte 0 = unsupported (size 0, opcode 0); otherwise
`size = 2^exponent` bytes and the opcode is the high byte. Erase types are
exposed in BFPT order 0..3 (DWORD 8 low, DWORD 8 high, DWORD 9 low,
DWORD 9 high).

Derived fields:

- `capacity_bytes = density_bits / 8` (truncating);
- `supports_3_byte` = address mode 0 or 1; `supports_4_byte` = mode 1 or 2;
- `erase_4k` / `erase_32k` / `erase_64k` / `erase_256k` = some supported
  erase type is exactly 4096 / 32768 / 65536 / 262144 bytes;
- `erase_bulk` = `capacity_bytes > 0` and some supported erase type size is
  `>= capacity_bytes` (a whole-array erase type; JESD216 has no dedicated
  chip-erase flag);
- `erase_count` = number of supported erase types;
- `page_size_exp` = -1 and `page_size_bytes` = 0 when the table has fewer
  than 11 DWORDs or the page exponent field is 0.

### SFDP validation order and errors

`flash_sfdp_parse_header(data)`:

| Order | Condition | Result |
|---|---|---|
| 1 | `data.len() < 8` | `Err(data.len(), "flash: sfdp header truncated")` |
| 2 | signature mismatch | `Err(0, "flash: bad sfdp signature")` |
| 3 | major != 1 | `Err(5, "flash: sfdp major revision unsupported")` |
| 4 | minor > 9 | `Err(4, "flash: sfdp minor revision unsupported")` |

`flash_sfdp_parse_param_header(data, index)` runs the header checks first,
then:

| Order | Condition | Result |
|---|---|---|
| 1 | `index` outside 0..count-1 | `Err(-1, "flash: sfdp parameter index out of range")` |
| 2 | `8 + 8*index + 8 > data.len()` | `Err(data.len(), "flash: sfdp parameter header truncated")` |

`flash_sfdp_basic_param(data)` runs the header/entry checks, then:

| Order | Condition | Result |
|---|---|---|
| 1 | basic entry with major != 1 | `Err(8 + 8*i + 2, "flash: sfdp basic table major revision unsupported")` |
| 2 | no basic entry | `Err(-1, "flash: sfdp basic table missing")` |

`flash_sfdp_bfpt_parse(data)` selects the basic table, then:

| Order | Condition | Result |
|---|---|---|
| 1 | `length_dwords < 9` | `Err(pointer, "flash: sfdp basic table too short")` |
| 2 | `pointer + 4*length_dwords > data.len()` | `Err(pointer, "flash: sfdp table out of bounds")` |
| 3 | density exponent > 62 | `Err(pointer + 4, "flash: sfdp density exponent out of range")` |
| 4 | erase type 1/2 exponent > 40 | `Err(pointer + 28, "flash: sfdp erase size exponent out of range")` |
| 5 | erase type 3/4 exponent > 40 | `Err(pointer + 32, "flash: sfdp erase size exponent out of range")` |
| 6 | page exponent > 20 | `Err(pointer + 40, "flash: sfdp page size exponent out of range")` |

The exponent caps are overflow guards for absurd tables; real JESD216
values are far below them (density <= 35 bits, erase <= 21, page <= 12).

## Sector map

`flash_sector_count(sector_size, capacity)` = ceiling of
`capacity / sector_size`, -1 when either argument is not positive.

`flash_sector_map(sector_size, capacity, address)` boundary rules, in
order:

| Order | Rule | Error |
|---|---|---|
| 1 | `sector_size > 0` | `Err(-1, "flash: invalid sector size")` |
| 2 | `capacity > 0` | `Err(-1, "flash: invalid capacity")` |
| 3 | `capacity % sector_size == 0` (whole sectors) | `Err(-1, "flash: capacity not sector aligned")` |
| 4 | `address >= 0` | `Err(-1, "flash: negative address")` |
| 5 | `address < capacity` | `Err(address, "flash: address out of range")` -- the offending address is the offset |

Result: `sector_count = capacity / sector_size`,
`index = address / sector_size`, `offset = address % sector_size`.
Boundary convention: address 0 -> index 0 offset 0; the last byte of
sector `k` -> index `k`; the first byte of the next sector -> index `k+1`
offset 0; `address == capacity` is out of range.

`flash_sector_range(sector_size, capacity, index)` shares rules 1..3, then
requires `0 <= index < sector_count`
(`Err(-1, "flash: sector index out of range")`), and returns
`start_address = index * sector_size`,
`end_address = start_address + sector_size` (half-open interval).

## Determinism

No floating point, no time, no randomness, no device state: every function
is a pure function of its inputs, all errors are stable strings with stable
offsets, and repeated calls with the same buffer return equal values.
