# xiom.sd

> **Status:** `stable` -- conformance-tested (21/21); published at `v0.1.1` on the XIOM registry.
> **Scope:** pure-XIOM (no FFI) SD/MMC card register codec: CID, CSD
> v1.0/v2.0, OCR, CRC7 and SPI-mode command framing.
> **Deps:** `xiom.std` only. The library module imports `xiom.convert` and
> `xiom.string.builder`; the tests also use `xiom.test`, `xiom.io`,
> `xiom.string.compare` and `xiom.encoding.hex`.

## What it is

`xiom.sd` turns SD/MMC card register images and SPI command frames into
typed values and back:

- **CID register** -- the 128-bit card identification: manufacturer id,
  OEM id, product name, revision, serial, manufacturing date, stored CRC7
  and mandated end bit, with a validating `sd_cid_parse`;
- **CSD register** -- the 128-bit card-specific data in both structures:
  v1.0 (SDSC) and v2.0 (SDHC/SDXC), with structure-version detection,
  TAAC/NSAC decode to nanoseconds, TRAN_SPEED decode to bit/s,
  READ_BL_LEN/WRITE_BL_LEN, the full v1.0 capacity formula
  `(C_SIZE+1) * 2^(C_SIZE_MULT+2) * 2^READ_BL_LEN` and the v2.0 formula
  `(C_SIZE+1) * 512 KiB`, ERASE_BLK_EN / SECTOR_SIZE erase-unit decoding,
  DSR_IMP and the write-protect flags;
- **OCR register** -- the 32-bit operation conditions: busy/ready, CCS
  (high capacity), UHS-II, XPC and the nine voltage windows 2.7-3.6 V,
  with `sd_ocr_supports_voltage`;
- **CRC7** -- `x^7 + x^3 + 1` computation over arbitrary byte vectors plus
  stored-vs-computed validation for CID/CSD and SPI frames;
- **SPI framing** -- 6-byte command frames `[0x40 | index]` + big-endian
  argument + `[(CRC7 << 1) | 1]`, pinned CMD0 (`0x95` trailer) and CMD8
  (`0xAA` check pattern, `0x87` trailer) frames, frame inspection and
  structural validation.

Everything is a free function over `Int`, `Bool`, `Str` and `Vec[UInt8]`,
plus four small struct types. There is no bus I/O, no init state machine
and no timing: the codec only decodes, computes and validates. The error
model is a deterministic `Err(Str)` catalog (see `SPEC.md`); an `Err` never
carries a half-built result.

## Install / use

```
xiom pkg install xiom.sd@0.1.0     # consumer
xiom pkg publish                   # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xi
use xiom.sd;
use xiom.io;
use xiom.convert;

// CID of a SanDisk Ultra II 1GB: 03 53 44 53 55 30 31 47 80 40 1c 75 13 00 63 7d
let cid = Vec[UInt8].new();
// ... fill cid with the 16 register bytes ...
let cr = sd_cid_parse(&cid);
if cr.is_ok {
  let c: SdCid = cr.value;
  io.println(c.product_name);                 // "SU01G"
  io.println(convert.int_to_string(c.serial)); // 1075606803
}

// CSD of a 32GB SDHC card: 40 0e 00 32 5b 59 00 00 ed c8 7f 80 0a 40 40 c3
let csd = Vec[UInt8].new();
// ... fill csd with the 16 register bytes ...
let sr = sd_csd_parse(&csd);
if sr.is_ok {
  let s: SdCsd = sr.value;                    // structure = 1 (v2.0)
  io.println(convert.int_to_string(s.capacity_bytes)); // 31914983424
  io.println(convert.int_to_string(s.tran_speed_bps)); // 25000000
}

// SPI CMD0 frame and the canonical CMD8 frame.
let f0 = sd_spi_cmd0_frame();      // 40 00 00 00 00 95
let f8 = sd_spi_cmd8_frame(1, 170); // 48 00 00 01 AA 87
```

## API

All functions are free functions in module `xiom.sd`.

### CRC7

| Function | Returns | Description |
|---|---|---|
| `sd_crc7(data)` | `Int` | CRC7 over the whole vector. |
| `sd_cid_crc(data)` | `Result[Int, Str]` | CRC7 over the first 15 CID bytes. |
| `sd_cid_crc_stored(data)` | `Result[Int, Str]` | CID CRC field (bits [7:1]). |
| `sd_csd_crc(data)` | `Result[Int, Str]` | CRC7 over the first 15 CSD bytes. |
| `sd_csd_crc_stored(data)` | `Result[Int, Str]` | CSD CRC field (bits [7:1]). |

### CID

| Function | Returns | Description |
|---|---|---|
| `sd_cid_parse(data)` | `Result[SdCid, Str]` | Full validation + decoded struct. |
| `sd_cid_manufacturer_id(data)` | `Result[Int, Str]` | MID bits [127:120]. |
| `sd_cid_oem_id(data)` | `Result[Str, Str]` | OID, two printable chars. |
| `sd_cid_product_name(data)` | `Result[Str, Str]` | PNM, five printable chars. |
| `sd_cid_revision(data)` | `Result[Int, Str]` | PRV byte (major high nibble). |
| `sd_cid_serial(data)` | `Result[Int, Str]` | PSN, unsigned 32-bit. |
| `sd_cid_manufacturing_date(data)` | `Result[SdMdt, Str]` | `{ year, month }`, month 1..12. |

### CSD

| Function | Returns | Description |
|---|---|---|
| `sd_csd_parse(data)` | `Result[SdCsd, Str]` | Full validation + decoded struct. |
| `sd_csd_structure(data)` | `Result[Int, Str]` | Raw CSD_STRUCTURE 0..3. |
| `sd_csd_structure_label(n)` | `Str` | `"1.0"`, `"2.0"`, `"3.0"`, `"reserved"`. |
| `sd_csd_taac(data)` / `sd_csd_nsac(data)` / `sd_csd_tran_speed(data)` | `Result[Int, Str]` | Raw timing bytes. |
| `sd_csd_read_bl_len(data)` / `sd_csd_write_bl_len(data)` | `Result[Int, Str]` | Block-length exponents. |
| `sd_csd_c_size(data)` / `sd_csd_c_size_mult(data)` | `Result[Int, Str]` | Version-aware size fields. |
| `sd_csd_erase_blk_en(data)` / `sd_csd_dsr_imp(data)` | `Result[Bool, Str]` | CSD flags. |
| `sd_csd_erase_unit_bytes(data)` | `Result[Int, Str]` | 512 or (SECTOR_SIZE+1)*2^WRITE_BL_LEN. |
| `sd_csd_capacity_bytes(data)` | `Result[Int, Str]` | v1.0 or v2.0 capacity formula. |
| `sd_taac_ns(byte)` | `Result[Int, Str]` | TAAC byte -> nanoseconds. |
| `sd_nsac_ns(byte)` | `Result[Int, Str]` | NSAC byte -> nanoseconds. |
| `sd_tran_speed_bps(byte)` | `Result[Int, Str]` | TRAN_SPEED byte -> bit/s. |

### OCR

| Function | Returns | Description |
|---|---|---|
| `sd_ocr_parse(data)` | `Result[SdOcr, Str]` | Full validation + decoded struct. |
| `sd_ocr_value(data)` | `Result[Int, Str]` | Raw unsigned 32-bit value. |
| `sd_ocr_ready(data)` / `sd_ocr_ccs(data)` | `Result[Bool, Str]` | Ready (bit 31) / CCS (bit 30). |
| `sd_ocr_voltage_mask(data)` | `Result[Int, Str]` | 9-bit window mask [23:15]. |
| `sd_ocr_voltage_bit(mv)` | `Result[Int, Str]` | 2700..3500 mV -> bit 15..23. |
| `sd_ocr_supports_voltage(data, mv)` | `Result[Bool, Str]` | Window query. |

### SPI framing

| Function | Returns | Description |
|---|---|---|
| `sd_spi_command_frame(index, arg)` | `Result[Vec[UInt8], Str]` | 6-byte frame with computed CRC. |
| `sd_spi_command_frame_marker(index, arg, marker)` | `Result[Vec[UInt8], Str]` | Frame with an odd marker trailer. |
| `sd_spi_cmd0_frame()` | `Result[Vec[UInt8], Str]` | `40 00 00 00 00 95`. |
| `sd_spi_cmd8_frame(vhs, check)` | `Result[Vec[UInt8], Str]` | CMD8; `(1, 0xAA)` -> `48 00 00 01 AA 87`. |
| `sd_spi_frame_index(data)` / `sd_spi_frame_argument(data)` | `Result[Int, Str]` | Frame fields. |
| `sd_spi_frame_trailer(data)` / `sd_spi_frame_crc(data)` | `Result[Int, Str]` | Trailer byte / stored CRC7. |
| `sd_spi_frame_crc_ok(data)` | `Result[Bool, Str]` | Stored vs. computed CRC. |
| `sd_spi_frame_check(data)` | `Result[Unit, Str]` | Length + prefix + end bit + CRC. |

### Constants and types

```xi
pub const SD_CID_LEN: Int = 16;          // bytes
pub const SD_CSD_LEN: Int = 16;
pub const SD_OCR_LEN: Int = 4;
pub const SD_SPI_FRAME_LEN: Int = 6;
pub const SD_SPI_CMD_PREFIX: Int = 64;    // 0x40
pub const SD_SPI_TRAILER_CMD0: Int = 149; // 0x95
pub const SD_SPI_TRAILER_CMD8: Int = 135; // 0x87
pub const SD_SPI_MARKER_AA: Int = 170;    // 0xAA CMD8 check pattern
pub const SD_CSD_STRUCTURE_V1: Int = 0;
pub const SD_CSD_STRUCTURE_V2: Int = 1;
pub const SD_CSD_STRUCTURE_V3: Int = 2;

pub type SdMdt = { year: Int; month: Int; }
pub type SdCid = { ... }
pub type SdCsd = { ... }
pub type SdOcr = { raw: Int; ready: Bool; ccs: Bool; uhs2: Bool; xpc: Bool; voltage_mask: Int; }
```

## Error model

Every fallible function returns `Result[T, Str]` with a stable, lowercase
`sd.cid:` / `sd.csd:` / `sd.taac:` / `sd.nsac:` / `sd.transpeed:` /
`sd.ocr:` / `sd.spi:` message. Register validators name the offending bit
range (`reserved bits [30:29] must be zero`), register byte offset (`oem id
byte at offset 1 is not printable`), or field values (`crc7 mismatch:
stored 97, computed 61`). The full catalog and the validation order per
function are in `SPEC.md`; `Err` never carries a partial result.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.sd
```

Expected: the namespace check passes, 21 `[PASS]` lines, and a final
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

The suite pins published register images (SanDisk Ultra II 1GB CID, SanDisk
32GB SDHC and Kingston 2GB SDSC CSDs, plus a non-conforming SanDisk Ultra
II CSD used to prove reserved-bit enforcement), builds synthetic 16-byte
CID/CSD images in-test with pinned capacities (8388608 / 7948206080 bytes
and the structural minima and maxima), and cross-checks every CRC7 against
an independently written serial-LFSR implementation.

## Limitations

- **No bus I/O.** No CMD/DAT lines, no init sequence, no R1/R2/R3/R7
  responses, no timing. Frames and registers go in and out as values.
- **CSD v3.0/SDUC is detected but rejected**; only v1.0 and v2.0 capacity
  formulas are decoded.
- **Strict reserved-bit validation.** The SD spec is enforced, so a few
  legacy cards with non-conforming reserved bits (e.g. SanDisk Ultra II
  1GB CSD bit 30) fail `sd_csd_parse`; individual accessors still read
  them.
- **Product/OEM strings must be printable ASCII** (0x20..0x7E); trailing
  spaces are preserved.
- **Truncating decodes.** TAAC/TRAN_SPEED results are truncated to whole
  nanoseconds / bit per second.
- **SPI framing only.** No data tokens, no busy polling, no CMD12 stuff
  byte; CRC verification is meaningful for CMD0/CMD8 (other commands may
  use marker trailers).
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
