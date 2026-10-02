# xiom.flash

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.3` on the XIOM registry.
> **Scope:** pure-XIOM (no FFI) SPI NOR flash identification and SFDP
> (JESD216) structure parsing. Bytes in, typed values out: no device access.
> **Deps:** `xiom.std` only; the library module imports nothing from it. The
> tests use `xiom.test`, `xiom.io`, `xiom.string.compare` and
> `xiom.encoding.hex`.

## What it is

`xiom.flash` decodes the identification layer of SPI NOR flash memory from
buffer images the caller already has:

- **JEDEC ID** -- the 3-byte RDID (0x9F) response: manufacturer byte,
  memory type byte and capacity byte, with a documented manufacturer subset
  (`0x01` Spansion/Cypress, `0x1F` Adesto, `0x20` Micron, `0xBF`
  SST/Microchip, `0xC2` Macronix, `0xEF` Winbond, `0x62` Sanyo, `0x8C`
  ESMT, `0x5E` Zbit; anything else decodes as `"unknown"`, not an error) and
  capacity byte `N` -> `2^N` bytes, accepted only for `N` in 8..32 (256 B ..
  4 GiB);
- **Command set** -- 18 pinned 25-series opcodes (READ, FAST_READ,
  FAST_READ_QUAD_IO, PAGE_PROGRAM, SECTOR_ERASE, BLOCK_ERASE, WRITE_ENABLE,
  WRITE_DISABLE, READ_STATUS1, READ_STATUS2, WRITE_STATUS, READ_ID,
  READ_SFDP, CHIP_ERASE, CHIP_ERASE_ALT, READ_4B, RESET_ENABLE, RESET) as
  constants plus a table/name/index API, and status-register-1 bit decode
  (WIP, WEL, BP0..BP2, TB, SEC, SRP0);
- **SFDP / JESD216** -- the header (`SFDP` signature, minor/major revision,
  NPH+1 parameter header count), the 8-byte parameter header entries
  (little-endian 16-bit IDs, 24-bit little-endian table pointers, length in
  DWORDs), and the Basic Flash Parameter Table (BFPT): density, 3/4-byte
  addressing, DTR, the four classic fast-read commands with opcode, mode
  clocks and wait states, page size and the four erase types with derived
  4 KiB / 32 KiB / 64 KiB / 256 KiB / bulk flags;
- **Sector map** -- address -> sector index and intra-sector offset with
  truncating division and modulo, and the inverse index -> `[start, end)`
  range, with documented boundary rules.

Everything is a free function over `Int`, `Bool`, `Str` and `Vec[UInt8]`
plus six small leaf structs. There is no bus I/O, no CS handling, no dummy
cycles, no command execution, no timing and no polling: the codec only
decodes and validates. The error model is a deterministic
`Err(FlashError)` catalog (see `SPEC.md`); errors carry byte offsets and an
`Err` never carries a half-built result.

## Install / use

```
xiom pkg install xiom.flash@0.1.2   # consumer
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xi
use xiom.flash;

// RDID (0x9F) response of a Winbond W25Q128: EF 40 18.
let id = Vec[UInt8].new();
// ... fill id with the three RDID bytes ...
let jr = flash_jedec_id_parse(&id);
if jr.is_ok {
  let j: FlashJedecId = jr.value;
  // j.manufacturer_name == "Winbond"
  // j.memory_type == 0x40
  // j.capacity_code == 24, j.capacity_bytes == 16777216 (16 MiB)
}

// A full SFDP image in memory: header + parameter headers + BFPT.
// The header is literally "SFDP" (53 46 44 50), the basic parameter header
// has ID bytes 00 FF (LE word 0xFF00) and the BFPT starts at its pointer.
let sfdp = Vec[UInt8].new();
// ... fill sfdp ...
let br = flash_sfdp_bfpt_parse(&sfdp);
if br.is_ok {
  let b: FlashBfpt = br.value;
  // b.capacity_bytes, b.page_size_bytes, b.erase_count, b.erase_4k, ...
  // flash_bfpt_fast_read(&b, 3).opcode  -- the 1-4-4 fast-read opcode
}

// Sector map: index = address / 4096, offset = address % 4096.
let sr = flash_sector_map(4096, 16777216, 16777215);
// sr.value.index == 4095, sr.value.offset == 4095
```

## API

All functions are free functions in module `xiom.flash`.

### JEDEC ID and manufacturers

| Function | Returns | Description |
|---|---|---|
| `flash_jedec_id_parse(id)` | `Result[FlashJedecId, FlashError]` | Full RDID decode (3 bytes, capacity 8..32). |
| `flash_capacity_bytes(code)` | `Result[Int, FlashError]` | `2^code` bytes for code 8..32. |
| `flash_manufacturer_count()` | `Int` | Table size (9). |
| `flash_manufacturer_table()` | `Vec[Int]` | The documented subset in table order. |
| `flash_manufacturer_id_at(index)` | `Int` | ID at 0..8, else -1. |
| `flash_manufacturer_name_at(index)` | `Str` | Name at 0..8, else "unknown". |
| `flash_manufacturer_known(id)` | `Bool` | Subset membership. |
| `flash_manufacturer_name(id)` | `Str` | Name or "unknown". |

### Commands and status

| Function | Returns | Description |
|---|---|---|
| `flash_command_count()` | `Int` | 18. |
| `flash_command_table()` | `Vec[Int]` | Pinned opcodes in table order. |
| `flash_command_code(index)` | `Int` | Opcode at 0..17, else -1. |
| `flash_command_name(cmd)` | `Str` | Stable name or "unknown". |
| `flash_command_name_at(index)` | `Str` | Name at 0..17, else "unknown". |
| `flash_sr1_parse(byte)` | `Result[FlashStatus1, FlashError]` | Bit decode for a byte 0..255. |
| `flash_sr1_wip(byte)` / `flash_sr1_wel(byte)` | `Bool` | Bit 0 / bit 1 helpers. |
| `flash_sr1_block_protect(byte)` | `Int` | BP2 BP1 BP0 as 0..7, else -1. |

### SFDP

| Function | Returns | Description |
|---|---|---|
| `flash_sfdp_parse_header(data)` | `Result[FlashSfdpHeader, FlashError]` | Signature, revisions, NPH+1. |
| `flash_sfdp_parse_param_header(data, index)` | `Result[FlashSfdpParamHeader, FlashError]` | One 8-byte entry. |
| `flash_sfdp_basic_param(data)` | `Result[FlashSfdpParamHeader, FlashError]` | Select the 0xFF00 entry. |
| `flash_sfdp_bfpt_parse(data)` | `Result[FlashBfpt, FlashError]` | Full BFPT decode. |
| `flash_sfdp_id_is_basic(id)` / `flash_sfdp_id_is_unused(id)` / `flash_sfdp_id_is_sector_map(id)` | `Bool` | ID markers 0xFF00 / 0xFFFF / 0xFF81. |

### BFPT queries

| Function | Returns | Description |
|---|---|---|
| `flash_bfpt_density_bits(b)` / `flash_bfpt_capacity_bytes(b)` | `Int` | Raw bits / truncated bytes. |
| `flash_bfpt_supports_3byte(b)` / `flash_bfpt_supports_4byte(b)` | `Bool` | Address modes. |
| `flash_bfpt_page_size_bytes(b)` / `flash_bfpt_page_size_known(b)` | `Int` / `Bool` | DWORD 11 page size. |
| `flash_bfpt_fast_read(b, mode)` | `FlashFastRead` | mode 0..3 = 1-1-2, 1-2-2, 1-1-4, 1-4-4. |
| `flash_bfpt_fast_read_clocks(b, mode)` | `Int` | mode clocks + wait states, -1 if unsupported. |
| `flash_fast_read_mode(inst, addr, data)` | `Int` | 1-1-2/1-2-2/1-1-4/1-4-4 -> 0..3, else -1. |
| `flash_bfpt_erase_size(b, index)` / `flash_bfpt_erase_opcode(b, index)` | `Int` | Erase type 0..3 in BFPT order. |
| `flash_bfpt_erase_type_count(b)` / `flash_bfpt_smallest_erase_size(b)` | `Int` | Derived erase stats. |

### Sector map and bit helpers

| Function | Returns | Description |
|---|---|---|
| `flash_sector_count(sector_size, capacity)` | `Int` | Ceiling count, -1 on bad inputs. |
| `flash_sector_map(sector_size, capacity, address)` | `Result[FlashSector, FlashError]` | index/offset split. |
| `flash_sector_range(sector_size, capacity, index)` | `Result[FlashSectorRange, FlashError]` | `[start, end)`. |
| `flash_bit_set(value, bit)` | `Bool` | Bit test, 0..62. |
| `flash_pow2(k)` | `Int` | `2^k` for 0..62, else -1. |

### Constants and types

```xi
pub const FLASH_CMD_READ: Int = 3;             // 0x03 ... 18 opcodes total
pub const FLASH_SR1_BIT_WIP: Int = 0;          // ... through SRP0 = 7
pub const FLASH_JEDEC_MIN_CAPACITY_CODE: Int = 8;
pub const FLASH_JEDEC_MAX_CAPACITY_CODE: Int = 32;
pub const FLASH_MANUFACTURER_COUNT: Int = 9;
pub const FLASH_SFDP_SIGNATURE: Int = 1346651731; // 0x50444653
pub const FLASH_SFDP_MAJOR: Int = 1;
pub const FLASH_SFDP_MAX_MINOR: Int = 9;
pub const FLASH_SFDP_BASIC_ID: Int = 65280;    // 0xFF00
pub const FLASH_SFDP_UNUSED_ID: Int = 65535;   // 0xFFFF
pub const FLASH_SFDP_SECTOR_MAP_ID: Int = 65409; // 0xFF81
pub const FLASH_SFDP_4BAIT_ID: Int = 65412;    // 0xFF84

pub type FlashError = { offset: Int; message: Str; }
pub type FlashJedecId = { ... }
pub type FlashStatus1 = { ... }
pub type FlashSfdpHeader = { ... }
pub type FlashSfdpParamHeader = { ... }
pub type FlashFastRead = { supported: Bool; opcode: Int; mode_clocks: Int; wait_states: Int; }
pub type FlashBfpt = { ... }
pub type FlashSector = { ... }
pub type FlashSectorRange = { ... }
```

## Error model

Every fallible function returns `Result[T, FlashError]` with a stable,
lowercase `flash:` message. `offset` is the byte position of the offending
field, `data.len()` when the buffer ended mid-parse, -1 when the error
concerns a scalar input, and for an out-of-range sector address the
offending address itself. The full catalog per function and the validation
order are in `SPEC.md`; `Err` never carries a partial result.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.flash
```

Expected: the namespace check passes, 20 `[PASS]` lines, and a final
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

The suite builds all buffers in-test: a Winbond-like RDID image (`EF 40
18`), a 112-byte SFDP image (header minor 6 / major 1 / NPH 0, one basic
parameter header at 0x08 with pointer 0x30 and 16 DWORDs, and a BFPT with
pinned DWORD values), the same image variants for the bit-31 density
encoding, a DTR/3-byte-only address mode, 256 KiB + whole-chip erase types
and malformed images (bad signature, bad major/minor revision, truncated
header, 8-DWORD table, out-of-bounds pointer, bad density/page/erase
exponents). Sector-map tests pin the boundary addresses around each sector
division.

## Limitations

- **No device access.** No SPI transfers, no chip-select, no address/dummy
  phase construction; the caller provides the RDID/SFDP images.
- **Only RDID 0x9F three-byte IDs.** No RES (0xAB) / REMS (0x90) ID
  formats, no vendor-specific ID tables beyond the documented subset.
- **BFPT structural decode only.** The sector map (0xFF81), 4-byte address
  instruction (0xFF84) and xSPI tables are identified by ID but not
  decoded; the BFPT decode covers the classic single-line commands. DTR is
  exposed as a support flag only.
- **Page size needs an 11+ DWORD BFPT.** 9/10-DWORD JESD216 rev A tables
  decode `page_size_exp = -1` and `page_size_bytes = 0` instead of failing.
- **The "bulk" erase flag is derived**: true when a supported erase type
  covers the whole capacity; JESD216 has no dedicated chip-erase flag. The
  chip-erase opcodes (0xC7/0x60) are constants only.
- **Capacity rounding.** JEDEC ID capacity is exactly `2^N` (codes 8..32);
  BFPT density is truncated to whole bytes (`density_bits / 8`).
- **No write/erase semantics.** Status bits are decoded but never polled;
  program/erase timing and protection rules are out of scope.
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
