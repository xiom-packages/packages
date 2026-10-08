# xiom.sd -- Specification

Version: 0.1.3 (stable; published on the XIOM registry).
Module: `src/sd.xi` (`module xiom.sd`).
Depends on `xiom.std`; the library module imports `xiom.convert`
(`int_to_string`) and `xiom.string.builder` (`sb_to_str`); the tests also
import `xiom.test`, `xiom.io`, `xiom.string.compare` and
`xiom.encoding.hex`.

## Scope

A pure-XIOM (no FFI) codec for the register and framing layer of SD/MMC
memory cards:

- **CID register** (128-bit): manufacturer id, OEM id, product name,
  product revision, serial number, manufacturing date, stored CRC7 and end
  bit, plus a validating `sd_cid_parse`;
- **CSD register** v1.0 and v2.0 (128-bit): structure version detection,
  TAAC/NSAC decode to nanoseconds, TRAN_SPEED decode to bit/s,
  READ_BL_LEN/WRITE_BL_LEN, C_SIZE/C_SIZE_MULT, the two capacity formulas,
  ERASE_BLK_EN and erase-unit decoding, DSR_IMP, plus a validating
  `sd_csd_parse`;
- **OCR register** (32-bit): busy/ready, CCS, UHS-II, XPC, the nine voltage
  window bits [23:15] and a validating `sd_ocr_parse`;
- **CRC7** (generator `x^7 + x^3 + 1`): computation over arbitrary byte
  vectors, CID/CSD register checksums (first 15 bytes vs. bits [7:1]) and
  stored-vs-computed validation;
- **SPI-mode framing**: 6-byte command frames `[0x40 | index]` + 32-bit
  big-endian argument + `[(CRC7 << 1) | 1]`, the documented CMD0 trailer
  `0x95` and CMD8 check pattern `0xAA` (with computed CMD8 trailer `0x87`),
  frame inspection and validation;
- a deterministic `Err(Str)` catalog for malformed input and invalid
  fields, with bit ranges and byte offsets in the messages.

## Non-goals

- **No bus I/O.** No CMD/DAT/CLK/CS handling, no init state machine
  (CMD0/CMD8/ACMD41/CMD58 sequences), no R1/R2/R3/R7 response parsing, no
  timing or NCR/NAC enforcement.
- **No card state.** Registers are 16-byte / 4-byte values in memory; no
  RCA assignment, no transfer-state tracking.
- **No CSD v3.0 (SDUC) decoding.** Structure value 2 is detected and
  rejected with a dedicated error; structure value 3 is reported reserved.
- **No SCR, SSR, switch-function or EXT_CSD registers**, no MMC-specific
  CSD field meanings (the SD interpretation of bits [30:29], [16] and
  [9:8] is used).
- **No data-block CRC16**, no data tokens, no write-protect command
  semantics.
- **No file system or partition logic.**

## CID register (128-bit, 16 bytes)

Bit 127 is the MSB of byte 0; bits [7:1] hold the CRC7 and bit 0 is the end
bit (1). All real register images published by card dumps end with an odd
byte and a CRC7 that matches the first 15 bytes.

| Bits | Width | Field | Decode |
|---|---|---|---|
| 127:120 | 8 | MID | manufacturer id 0..255 |
| 119:104 | 16 | OID | two printable ASCII chars |
| 103:64 | 40 | PNM | five printable ASCII chars |
| 63:56 | 8 | PRV | major [63:60], minor [59:56] |
| 55:24 | 32 | PSN | unsigned 32-bit serial |
| 23:20 | 4 | reserved | must be 0 |
| 19:8 | 12 | MDT | year = 2000 + [19:12], month = [11:8] 1..12 |
| 7:1 | 7 | CRC7 | computed over bits [127:8] |
| 0 | 1 | end bit | must be 1 |

## CSD register (128-bit, 16 bytes)

`CSD_STRUCTURE` (bits [127:126]): 0 = v1.0 (SDSC), 1 = v2.0 (SDHC/SDXC),
2 = v3.0 (SDUC, not decoded), 3 = reserved. Bit 0 is the end bit and bits
[7:1] the CRC7 over bits [127:8].

### CSD v1.0 (structure 0)

| Bits | Width | Field |
|---|---|---|
| 125:120 | 6 | reserved (0) |
| 119:112 | 8 | TAAC |
| 111:104 | 8 | NSAC |
| 103:96 | 8 | TRAN_SPEED |
| 95:84 | 12 | CCC |
| 83:80 | 4 | READ_BL_LEN |
| 79 | 1 | READ_BL_PARTIAL |
| 78 | 1 | WRITE_BLK_MISALIGN |
| 77 | 1 | READ_BLK_MISALIGN |
| 76 | 1 | DSR_IMP |
| 75:74 | 2 | reserved (0) |
| 73:62 | 12 | C_SIZE |
| 61:50 | 12 | VDD read/write current codes (not decoded) |
| 49:47 | 3 | C_SIZE_MULT |
| 46 | 1 | ERASE_BLK_EN |
| 45:39 | 7 | SECTOR_SIZE |
| 38:32 | 7 | WP_GRP_SIZE |
| 31 | 1 | WP_GRP_ENABLE |
| 30:29 | 2 | reserved (0) |
| 28:26 | 3 | R2W_FACTOR |
| 25:22 | 4 | WRITE_BL_LEN |
| 21 | 1 | WRITE_BL_PARTIAL |
| 20:16 | 5 | reserved (0) |
| 15 | 1 | FILE_FORMAT_GRP |
| 14 | 1 | COPY |
| 13 | 1 | PERM_WRITE_PROTECT |
| 12 | 1 | TMP_WRITE_PROTECT |
| 11:10 | 2 | FILE_FORMAT |
| 9:8 | 2 | reserved (0) |
| 7:1 | 7 | CRC7 |
| 0 | 1 | end bit (1) |

### CSD v2.0 (structure 1)

The upper half is shared with v1.0; C_SIZE expands and C_SIZE_MULT
disappears:

| Bits | Width | Field |
|---|---|---|
| 125:120 | 6 | reserved (0) |
| 119:112 | 8 | TAAC (fixed 0x0E on real cards) |
| 111:104 | 8 | NSAC |
| 103:96 | 8 | TRAN_SPEED |
| 95:84 | 12 | CCC |
| 83:80 | 4 | READ_BL_LEN (real cards: 9) |
| 79 | 1 | READ_BL_PARTIAL |
| 78 | 1 | WRITE_BLK_MISALIGN |
| 77 | 1 | READ_BLK_MISALIGN |
| 76 | 1 | DSR_IMP |
| 75:70 | 6 | reserved (0) |
| 69:48 | 22 | C_SIZE |
| 47 | 1 | reserved (0) |
| 46 | 1 | ERASE_BLK_EN |
| 45:39 | 7 | SECTOR_SIZE |
| 38:32 | 7 | WP_GRP_SIZE |
| 31 | 1 | WP_GRP_ENABLE |
| 30:29 | 2 | reserved (0) |
| 28:26 | 3 | R2W_FACTOR |
| 25:22 | 4 | WRITE_BL_LEN |
| 21 | 1 | WRITE_BL_PARTIAL |
| 20:16 | 5 | reserved (0) |
| 15:8 | 8 | file format / write protect / reserved |
| 7:1 | 7 | CRC7 |
| 0 | 1 | end bit (1) |

### TAAC decode (nanoseconds)

Bits [6:3] are the time value, bits [2:0] the time unit; bit 7 is reserved
and time value 0 is a reserved code (both rejected by `sd_taac_ns`). The
time value table is shared with TRAN_SPEED:

| Code | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Multiplier | res | 1.0 | 1.2 | 1.3 | 1.5 | 2.0 | 2.5 | 3.0 | 3.5 | 4.0 | 4.5 | 5.0 | 5.5 | 6.0 | 7.0 | 8.0 |

| Unit code | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| Unit | 1 ns | 10 ns | 100 ns | 1 us | 10 us | 100 us | 1 ms | 10 ms |

`taac_ns = multiplier_tenths * unit_ns / 10` (truncating; e.g. 0x0E =
1.0 x 1 ms = 1000000 ns, 0x2D = 2.0 x 100 us = 200000 ns).

### NSAC decode

NSAC is an 8-bit count in 100 ns units: `nsac_ns = NSAC * 100`.

### TRAN_SPEED decode (bit/s)

Bits [6:3] are the time value (same table as TAAC), bits [2:0] the transfer
rate unit; bit 7 is reserved and time value 0 is reserved. Unit codes 4..7
are reserved and rejected.

| Unit code | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Unit | 100 kbit/s | 1 Mbit/s | 10 Mbit/s | 100 Mbit/s |

`tran_speed_bps = multiplier_tenths * unit_bps / 10` (truncating; e.g.
0x32 = 2.5 x 10 Mbit/s = 25000000, 0x5A = 5.0 x 10 Mbit/s = 50000000,
0x0B = 1.0 x 100 Mbit/s = 100000000).

### Capacity

- **v1.0**: `capacity_bytes = (C_SIZE + 1) * 2^(C_SIZE_MULT + 2) *
  2^READ_BL_LEN` (all multiplication; READ_BL_LEN must be 9..11).
  Min 2048 bytes (C_SIZE 0, C_SIZE_MULT 0, READ_BL_LEN 9); max 4294967296
  bytes (C_SIZE 4095, C_SIZE_MULT 7, READ_BL_LEN 11).
- **v2.0**: `capacity_bytes = (C_SIZE + 1) * 524288` (512 KiB units).
  Min 524288 bytes (C_SIZE 0); max 2199023255552 bytes (C_SIZE 4194303).

### Erase unit

- **v2.0**: always 512 bytes.
- **v1.0** with ERASE_BLK_EN = 1: 512 bytes.
- **v1.0** with ERASE_BLK_EN = 0: `(SECTOR_SIZE + 1) * 2^WRITE_BL_LEN`
  bytes (WRITE_BL_LEN must be 9..11 for this path).

## OCR register (32 bits, 4 big-endian bytes)

| Bit(s) | Field | Decode |
|---|---|---|
| 31 | busy | 0 = power-up in progress; `ready` is the inverse |
| 30 | CCS | 1 = block-addressed SDHC/SDXC |
| 29 | UHS-II | reported raw |
| 28 | XPC | reported raw |
| 27 | 2T (SDUC) | accepted, not decoded |
| 26:25 | reserved | must be 0 |
| 24 | S18A | accepted, not decoded |
| 23:15 | voltage window | bit 15 = 2.7-2.8 V .. bit 23 = 3.5-3.6 V |
| 14:0 | reserved | must be 0 |

`sd_ocr_voltage_bit(vdd_mv)` maps a 0.1 V window low bound (2700..3500 in
100 mV steps) to its bit 15..23; `sd_ocr_supports_voltage` tests the mask.

## CRC7

Generator polynomial `x^7 + x^3 + 1` (0x09 over the implicit `x^7`). The
module computes it with an 8-bit accumulator per byte:

```
crc = 0
for each byte d:
    crc = crc ^ d
    repeat 8 times:
        if crc bit 7: crc = crc ^ 0x09
        crc = (crc * 2) mod 256
return (crc / 2) mod 128
```

Verified values: CMD0 (bytes `40 00 00 00 00`) = 0x4A, CMD8 (`48 00 00 01
AA`) = 0x43, and the 22 published CID/CSD register images used in the tests
all satisfy `stored == computed` over the first 15 bytes.

CID/CSD registers carry the CRC in bits [7:1] and the end bit in bit 0;
`sd_cid_crc`/`sd_csd_crc` compute the checksum over the first 15 bytes and
`sd_cid_crc_stored`/`sd_csd_crc_stored` read bits [7:1].

## SPI-mode framing

A command frame is 6 bytes:

```
[0x40 | index] [arg31..24] [arg23..16] [arg15..8] [arg7..0] [(crc7 << 1) | 1]
```

- `sd_spi_command_frame(index, arg)` computes the CRC7 over the first five
  bytes; CMD0 (index 0, arg 0) yields `40 00 00 00 00 95` and the canonical
  CMD8 (index 8, arg 0x000001AA) yields `48 00 00 01 AA 87`;
- `sd_spi_command_frame_marker(index, arg, marker)` emits a caller-supplied
  odd trailer (for commands whose CRC is not checked, e.g. 0x95 or 0x01);
- `sd_spi_cmd0_frame()` uses the documented `SD_SPI_TRAILER_CMD0` (0x95)
  and `sd_spi_cmd8_frame(vhs, check)` builds CMD8 with argument
  `(vhs << 8) | check` and the computed CRC trailer.

Documented marker interpretation: the brief's "0x95/0xAA trailer" pair maps
to the two well-known SPI start-up marker bytes -- 0x95, the CMD0 trailer,
and 0xAA, the CMD8 check pattern byte (the CMD8 trailer itself is the
computed 0x87). The constants `SD_SPI_CMD_PREFIX` (0x40),
`SD_SPI_TRAILER_CMD0` (0x95), `SD_SPI_TRAILER_CMD8` (0x87) and
`SD_SPI_MARKER_AA` (0xAA) expose all four.

Frame inspection: `sd_spi_frame_index`, `sd_spi_frame_argument`,
`sd_spi_frame_trailer`, `sd_spi_frame_crc` (trailer >> 1),
`sd_spi_frame_crc_ok` and `sd_spi_frame_check` (length + prefix
`bits 7:6 = 01` + end bit + CRC).

## Types

```xi
pub type SdMdt = { year: Int; month: Int; }
pub type SdCid = {
  manufacturer_id: Int; oem_id: Str; product_name: Str;
  revision_major: Int; revision_minor: Int; serial: Int;
  mdt_year: Int; mdt_month: Int; crc7: Int;
}
pub type SdCsd = {
  structure: Int; taac: Int; taac_ns: Int; nsac: Int; nsac_ns: Int;
  tran_speed: Int; tran_speed_bps: Int; ccc: Int;
  read_bl_len: Int; read_bl_len_bytes: Int; read_bl_partial: Bool;
  write_blk_misalign: Bool; read_blk_misalign: Bool; dsr_imp: Bool;
  c_size: Int; c_size_mult: Int; erase_blk_en: Bool;
  sector_size: Int; erase_unit_bytes: Int;
  wp_grp_size: Int; wp_grp_enable: Bool; r2w_factor: Int;
  write_bl_len: Int; write_bl_len_bytes: Int; write_bl_partial: Bool;
  capacity_bytes: Int; crc7: Int;
}
pub type SdOcr = {
  raw: Int; ready: Bool; ccs: Bool; uhs2: Bool; xpc: Bool;
  voltage_mask: Int;
}
```

## API contract

All functions are free functions in module `xiom.sd`; there is no state.
Every fallible function validates in the order listed and returns `Err`
without a partial result; error text is stable.

```xi
pub fn sd_crc7(data: &Vec[UInt8]) -> Int
pub fn sd_cid_crc(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_cid_crc_stored(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_csd_crc(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_csd_crc_stored(data: &Vec[UInt8]) -> Result[Int, Str]

pub fn sd_cid_manufacturer_id(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_cid_oem_id(data: &Vec[UInt8]) -> Result[Str, Str]
pub fn sd_cid_product_name(data: &Vec[UInt8]) -> Result[Str, Str]
pub fn sd_cid_revision(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_cid_serial(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_cid_manufacturing_date(data: &Vec[UInt8]) -> Result[SdMdt, Str]
pub fn sd_cid_parse(data: &Vec[UInt8]) -> Result[SdCid, Str]

pub fn sd_csd_structure(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_csd_structure_label(structure: Int) -> Str
pub fn sd_csd_taac(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_csd_nsac(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_csd_tran_speed(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_csd_read_bl_len(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_csd_write_bl_len(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_csd_erase_blk_en(data: &Vec[UInt8]) -> Result[Bool, Str]
pub fn sd_csd_dsr_imp(data: &Vec[UInt8]) -> Result[Bool, Str]
pub fn sd_csd_c_size(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_csd_c_size_mult(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_csd_erase_unit_bytes(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_csd_capacity_bytes(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_csd_parse(data: &Vec[UInt8]) -> Result[SdCsd, Str]

pub fn sd_taac_ns(taac: Int) -> Result[Int, Str]
pub fn sd_nsac_ns(nsac: Int) -> Result[Int, Str]
pub fn sd_tran_speed_bps(b: Int) -> Result[Int, Str]

pub fn sd_ocr_value(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_ocr_ready(data: &Vec[UInt8]) -> Result[Bool, Str]
pub fn sd_ocr_ccs(data: &Vec[UInt8]) -> Result[Bool, Str]
pub fn sd_ocr_voltage_mask(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_ocr_voltage_bit(vdd_mv: Int) -> Result[Int, Str]
pub fn sd_ocr_supports_voltage(data: &Vec[UInt8], vdd_mv: Int) -> Result[Bool, Str]
pub fn sd_ocr_parse(data: &Vec[UInt8]) -> Result[SdOcr, Str]

pub fn sd_spi_command_frame(index: Int, arg: Int) -> Result[Vec[UInt8], Str]
pub fn sd_spi_command_frame_marker(index: Int, arg: Int, marker: Int) -> Result[Vec[UInt8], Str]
pub fn sd_spi_cmd0_frame() -> Result[Vec[UInt8], Str]
pub fn sd_spi_cmd8_frame(vhs: Int, check: Int) -> Result[Vec[UInt8], Str]
pub fn sd_spi_frame_index(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_spi_frame_argument(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_spi_frame_trailer(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_spi_frame_crc(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn sd_spi_frame_crc_ok(data: &Vec[UInt8]) -> Result[Bool, Str]
pub fn sd_spi_frame_check(data: &Vec[UInt8]) -> Result[Unit, Str]
```

### Validation order

`sd_cid_parse`: length -> reserved [23:20] -> end bit -> month ->
OEM id printable -> product name printable -> CRC7.

`sd_cid_manufacturing_date`: length -> month 1..12.
`sd_cid_oem_id` / `sd_cid_product_name`: length -> printable byte run.

`sd_csd_parse`: length -> structure (2 unsupported, 3 reserved) ->
reserved zero fields by version -> end bit -> TAAC -> NSAC -> TRAN_SPEED ->
READ_BL_LEN 9..11 -> WRITE_BL_LEN 9..11 -> CRC7.

`sd_csd_c_size` / `sd_csd_c_size_mult` / `sd_csd_capacity_bytes` /
`sd_csd_erase_unit_bytes`: length -> structure -> structure-specific
checks.

`sd_ocr_parse`: length -> reserved [26:25] -> reserved [14:0].

`sd_spi_frame_check`: length -> prefix bits 7:6 = 01 -> end bit -> CRC7.

## Error string catalog

| Condition | Error text |
|---|---|
| CID length != 16 | `sd.cid: register needs 16 bytes, have N` |
| CID reserved bits [23:20] set | `sd.cid: reserved bits [23:20] must be zero` |
| CID end bit 0 clear | `sd.cid: end bit 0 must be 1` |
| CID month outside 1..12 | `sd.cid: manufacturing month N out of range 1..12` |
| CID OEM byte not printable | `sd.cid: oem id byte at offset N is not printable (value V)` |
| CID PNM byte not printable | `sd.cid: product name byte at offset N is not printable (value V)` |
| CID/CSD CRC mismatch | `sd.cid: crc7 mismatch: stored N, computed M` / `sd.csd: ...` |
| CSD length != 16 | `sd.csd: register needs 16 bytes, have N` |
| CSD structure 2 (v3.0) | `sd.csd: CSD structure value 2 (v3.0) is not supported` |
| CSD structure 3 | `sd.csd: reserved CSD structure value 3` |
| CSD reserved zero field set | `sd.csd: reserved bits [HI:LO] must be zero` |
| CSD end bit 0 clear | `sd.csd: end bit 0 must be 1` |
| CSD reserved block length | `sd.csd: READ_BL_LEN N is reserved (valid 9..11)` / WRITE_BL_LEN |
| TAAC out of byte range | `sd.taac: value N out of range 0..255` |
| TAAC bit 7 set | `sd.taac: value N has reserved bit 7 set` |
| TAAC time value 0 | `sd.taac: time value 0 is reserved` |
| NSAC out of byte range | `sd.nsac: value N out of range 0..255` |
| TRAN_SPEED out of byte range | `sd.transpeed: value N out of range 0..255` |
| TRAN_SPEED bit 7 set | `sd.transpeed: value N has reserved bit 7 set` |
| TRAN_SPEED time value 0 | `sd.transpeed: time value 0 is reserved` |
| TRAN_SPEED unit 4..7 | `sd.transpeed: transfer rate unit N is reserved` |
| OCR length != 4 | `sd.ocr: register needs 4 bytes, have N` |
| OCR reserved [26:25] set | `sd.ocr: reserved bits [26:25] must be zero` |
| OCR reserved [14:0] set | `sd.ocr: reserved bits [14:0] must be zero` |
| Voltage outside 2700..3500 | `sd.ocr: voltage N out of range 2700..3500` |
| Voltage not a 100 mV step | `sd.ocr: voltage N is not a multiple of 100` |
| SPI index outside 0..63 | `sd.spi: command index N out of range 0..63` |
| SPI argument > 2^32-1 | `sd.spi: argument N does not fit in 32 bits` |
| SPI marker outside 0..255 | `sd.spi: trailer marker N out of range 0..255` |
| SPI marker end bit 0 | `sd.spi: trailer marker N must have end bit 1` |
| CMD8 VHS outside 0..15 | `sd.spi: cmd8 voltage N out of range 0..15` |
| CMD8 check outside 0..255 | `sd.spi: cmd8 check pattern N out of range 0..255` |
| SPI length != 6 | `sd.spi: frame needs 6 bytes, have N` |
| SPI prefix bits 7:6 != 01 | `sd.spi: prefix byte N does not have bits 7:6 = 01` |
| SPI end bit 0 clear | `sd.spi: trailer byte N does not have end bit 1` |
| SPI CRC mismatch | `sd.spi: crc7 mismatch: stored N, computed M` |

## Complexity

| Operation | Time | Space |
|---|---|---|
| `sd_crc7`, `sd_cid_crc`, `sd_csd_crc` | O(n) bytes | O(1) |
| CID/CSD/OCR accessors and parsers | O(1) bit extracts | O(1) |
| TAAC/NSAC/TRAN_SPEED decoders | O(1) | O(1) |
| SPI frame build/inspect | O(1) | O(1) |

## Test plan

`tests/test_conformance.xi` (`module sd_tests`, 21 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. real SanDisk Ultra II 1GB CID (`035344535530314780401c751300637d`):
   MID/OID/PNM/revision/serial/2006-03, CRC 0x3E;
2. synthetic CID built in-test bit by bit (`1b53444b58323536251234567801
   a985`) with pinned fields and CRC 0x42;
3. every CID accessor agrees with the parsed struct;
4. CID reserved bits, end bit and month errors (exact messages);
5. CID printable-byte errors with byte offsets, plus 15/16/17-byte lengths;
6. CID CRC mismatch messages with stored and computed values;
7. real SanDisk 32GB SDHC CSD (`400e00325b590000edc87f800a4040c3`):
   v2.0, C_SIZE 60872, capacity 31914983424 bytes, TAAC 1 ms,
   TRAN_SPEED 25 Mbit/s, CRC 0x61;
8. real Kingston 2GB SDSC CSD (`002d00325b5a83d5fefbff80168000cf`):
   v1.0, C_SIZE 3927, C_SIZE_MULT 7, READ_BL_LEN 10, capacity
   2059403264 bytes, CRC 0x67, all raw accessors;
9. synthetic CSD v1.0 (`002d00325b59807fc001ff8012400077`, capacity
   8388608) plus a SECTOR_SIZE erase-unit case (32768 bytes);
10. synthetic CSD v2.0 (`400e00325b5900003b377f8012400009`, capacity
    7948206080) plus capacity edges 524288 / 2199023255552 for v2.0 and
    2048 / 4294967296 for v1.0;
11. structure detection: labels ("1.0"/"2.0"/"3.0"/"reserved"), v3.0
    unsupported, structure 3 reserved;
12. reserved bit enforcement for [125:120], [75:74], [75:70], [47],
    [30:29], [20:16], [9:8], including a real non-conforming SanDisk
    Ultra II CSD whose bit 30 is set;
13. CSD end bit, READ_BL_LEN/WRITE_BL_LEN reserved values and CRC
    mismatch;
14. TAAC decode table (0x0E, 0x2D, 0x2A, 0x1A, 0x77, 0x7F) and reserved
    codes (0x00, 0x07, 0x80, 0x100, -1);
15. NSAC and TRAN_SPEED decode (0x32/0x5A/0x0B/0x2A/0x60) and reserved
    codes;
16. OCR parse (0xC0FF8000 ready/CCS/full window, 0x40FF8000 busy,
    0x80000000 bare) and voltage queries;
17. OCR reserved bits, length errors and voltage range errors;
18. SPI frames: pinned CMD0 `40 00 00 00 00 95` and CMD8
    `48 00 00 01 AA 87`, marker trailer, max index/argument, all range
    errors;
19. SPI frame inspection, CRC mismatch, prefix/end-bit/length errors;
20. CRC7 pinned CMD0 0x4A and CMD8 0x43 plus an independent serial-LFSR
    cross-check over every fixture (including an 8-byte all-0xFF buffer
    and the empty vector);
21. determinism: repeated parses, builds and capacity calls agree.

Fixtures: hex literals come from `xiom.encoding.hex`; synthetic registers
are assembled in-test with an explicit `set_field` bit writer and sealed
with a test-local CRC7 implementation written as a serial 7-bit LFSR (the
module uses a byte accumulator), so a shared CRC bug cannot pass unnoticed.
Real register images are taken from published card dumps. No `Str` value is
compared with `==` (BUG 17 discipline); error messages go through
`xiom.string.compare.str_compare`. All `Vec[UInt8]` element reads are bound
to typed locals and widened with `& 0xFF`.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.sd
```

Last verified: compiler 0.61.3,
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No transport, no init sequence and no card state (see Non-goals).
- CSD v3.0 (SDUC) is detected but not decoded; the v3.0 C_SIZE layout is
  out of scope.
- Reserved-bit validation follows the SD specification strictly, so a few
  legacy cards (e.g. the SanDisk Ultra II 1GB used in the tests, whose CSD
  bit 30 is set) are rejected by `sd_csd_parse` with a reserved-bits error;
  the individual accessors still read such registers.
- CID/CSD product and OEM strings must be printable ASCII (0x20..0x7E);
  trailing spaces are preserved and not trimmed.
- SPI framing models the 6-byte command frame only: no response parsing
  (R1/R2/R3/R7), no data tokens and no CMD12 stuff byte.
- The marker trailer builder emits any odd trailer; CRC verification is
  only meaningful for CMD0/CMD8 where the spec requires it.
- TAAC/TRAN_SPEED results are truncated (not rounded) to whole
  nanoseconds/bit-per-second.
- Single-bit ECC code fields (VDD currents, ECC, file format) are exposed
  only as raw C_SIZE_MULT-adjacent structure; MMC-specific field meanings
  are not decoded.

## Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, no lambdas, no `Vec[fn]` dispatch, no
  `Vec[StructType]`.
- `Ok`/`Err` construction is confined to the tiny leaf helpers
  (`_ok_unit`/`_err_unit`, `_ok_int`/`_err_int`, `_ok_bool`/`_err_bool`,
  `_ok_str`/`_err_str`, `_ok_bytes`/`_err_bytes`, `_ok_mdt`/`_err_mdt`,
  `_ok_cid`/`_err_cid`, `_ok_csd`/`_err_csd`, `_ok_ocr`/`_err_ocr`),
  because constructing Results directly inside other functions
  miscompiles.
- Str comparisons go through `xiom.string.compare.str_compare`; the library
  module itself never compares Str values.
- Every `Vec[UInt8]` byte read is widened with `(x as Int) & 0xFF` before
  entering Int arithmetic.
- Bit extraction uses division by powers of two (`_pow2`), never a shift on
  a value that could carry the sign bit; capacity math is multiplication
  only.
- Dynamic error strings are built with `xiom.convert.int_to_string`.
- Strings are materialized with `xiom.string.builder.sb_to_str` over a
  validated-printable, NUL-free byte run (the builder's length contract
  aborts on 0x00).
- The tests return the borrowed register body through a `seal_reg` helper
  that copies into a fresh vector: returning a vector that was passed by
  reference earlier in the function makes v0.61.3 lower the return into a
  stale borrow.
- The package declares no `extern "C"` blocks (no FFI).

## Contracts (batch #45 hardening pass, 2026-10-08)

Runtime-checkable `ensures:` clauses (36, across the 15 functions below) were
added to `src/sd.xi` in the batch #45 hardening pass (compiler v0.64.1;
`package.xi` is left for the coordinator to bump at integration). All are
`ensures:` with no `requires:`, so the accepted-input domain is unchanged.
Every clause is enforced as a runtime check; the 21-test conformance suite
exercises every contracted entry point (all 15 appear in
`tests/test_conformance.xi`) and no clause trapped, so none was dropped. Two
consecutive `& .\scripts\port.ps1 -Package xiom.sd -TimeoutSec 90` runs
ended `port: PASS (passed=21 failed=0 program_exit=0 exit=0)` with the
clauses active (16.60 s and 16.39 s). None is claimed Z3-provable:
`xiom-verify` was not run for this module and per the batch #37 finding a
bare `[OK] VERIFIED` can be a vacuous UNSAT, so the Z3-provable column is
"no" throughout.

Clause inputs are parameters or parameter fields only; no clause indexes a
vector, reads a `Vec` element, compares a `Str`, uses a module constant,
reads a bare `&mut` parameter or a struct-Result payload field. The guards
keep the plan's proven families: bounds (`result >= 0 && result <= 127`,
`... <= 4194303`, `... <= 80000000`), tag guard pairs (`result is Err` /
`result is Ok`), constant-only payload lengths (`result.value.len() == 2`,
`== 6`) and exact formulas (`result.value == nsac * 100`). Every planned
literal already matched the source (e.g. v2.0's 22-bit C_SIZE bound
`4194303`, the `8.0 x 10 ms` TAAC maximum `80000000`, the v1.0 capacity
minimum `2048` = `(0 + 1) * 2^2 * 2^9`, and the erase-unit minimum `512`),
so no expression needed refinement. The only cross-call is the body's
non-re-entrant `sd_spi_cmd8_frame` -> `sd_spi_command_frame` delegation; no
clause calls a helper. No probe-gated item applied and no doc/source
mismatch was found.

| Function | Clauses | Guarantee (abridged) | Z3-provable | Runtime-checked |
|---|---|---|---|---|
| `sd_crc7` | 2 | `result` in `0..127` | no | yes |
| `sd_cid_crc` | 3 | length != 16 => `Err`; `Ok` => length 16 and `0..127` | no | yes |
| `sd_cid_oem_id` | 2 | length != 16 => `Err`; `Ok` payload is 2 bytes | no | yes |
| `sd_cid_parse` | 2 | length != 16 => `Err`; `Ok` => length 16 | no | yes |
| `sd_taac_ns` | 3 | out-of-byte or bit 7 set => `Err`; `Ok` in `0..80000000` | no | yes |
| `sd_nsac_ns` | 2 | out-of-byte => `Err`; `Ok` == `nsac * 100` | no | yes |
| `sd_csd_structure` | 2 | length != 16 => `Err`; `Ok` in `0..3` | no | yes |
| `sd_csd_structure_label` | 3 | negative => 8 chars; 0 => 3 chars; > 3 => 8 chars | no | yes |
| `sd_csd_c_size` | 2 | length != 16 => `Err`; `Ok` in `0..4194303` | no | yes |
| `sd_csd_erase_unit_bytes` | 2 | length != 16 => `Err`; `Ok` >= 512 | no | yes |
| `sd_csd_capacity_bytes` | 2 | length != 16 => `Err`; `Ok` >= 2048 | no | yes |
| `sd_ocr_value` | 2 | length != 4 => `Err`; `Ok` in `0..4294967295` | no | yes |
| `sd_ocr_voltage_bit` | 3 | out-of-range or non-100 mV step => `Err`; `Ok` in `15..23` | no | yes |
| `sd_spi_command_frame` | 3 | bad index/argument => `Err`; `Ok` payload is 6 bytes | no | yes |
| `sd_spi_cmd8_frame` | 3 | bad VHS/check => `Err`; `Ok` payload is 6 bytes | no | yes |
