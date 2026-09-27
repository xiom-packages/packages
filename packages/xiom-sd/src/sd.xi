// XIOM -- xiom.sd: SD/MMC card register codec (CID, CSD v1.0/v2.0, OCR, CRC7, SPI framing)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) codec for the register and framing layer of SD/MMC
// memory cards. Codec only: 128-bit / 32-bit register images in memory and
// byte frames; no bus I/O, no init state machine, no timing.
//
// CID (128-bit, 16 bytes), bit 127 = MSB of byte 0:
//   * manufacturer id [127:120]; OEM id [119:104] (2 printable chars);
//     product name [103:64] (5 printable chars); product revision [63:56]
//     (major [63:60], minor [59:56]); product serial [55:24];
//     reserved [23:20]; manufacturing date [19:8] (year offset from 2000
//     [19:12], month [11:8], 1..12); CRC7 [7:1]; end bit [0] = 1.
//
// CSD (128-bit, 16 bytes), structure selected by [127:126]:
//   * structure 0 = v1.0 (SDSC): TAAC [119:112], NSAC [111:104],
//     TRAN_SPEED [103:96], CCC [95:84], READ_BL_LEN [83:80], flags
//     [79:76], C_SIZE [73:62], C_SIZE_MULT [49:47], ERASE_BLK_EN [46],
//     SECTOR_SIZE [45:39], WP_GRP_SIZE [38:32], WP_GRP_ENABLE [31],
//     R2W_FACTOR [28:26], WRITE_BL_LEN [25:22], flags [21:12];
//     capacity = (C_SIZE+1) * 2^(C_SIZE_MULT+2) * 2^READ_BL_LEN bytes;
//   * structure 1 = v2.0 (SDHC/SDXC): C_SIZE [69:48]; capacity =
//     (C_SIZE+1) * 512 KiB; C_SIZE_MULT and the timing fields are dummy;
//   * structure 2 = v3.0 (SDUC) is detected but not decoded; structure 3
//     is reserved;
//   * TAAC byte: [6:3] time value (tenths table), [2:0] time unit
//     (1 ns..10 ms), bit 7 reserved; TRAN_SPEED byte: [6:3] time value,
//     [2:0] transfer unit (100 kbit/s..100 Mbit/s), bit 7 reserved;
//     NSAC is in 100 ns units; CRC7 [7:1], end bit [0] = 1.
//
// OCR (32-bit, 4 big-endian bytes): busy/ready [31], CCS [30], UHS-II
// [29], XPC [28], 2T [27], reserved [26:25], S18A [24], voltage window
// [23:15] (bit 15 = 2.7-2.8 V .. bit 23 = 3.5-3.6 V), reserved [14:0].
//
// CRC7 (x^7 + x^3 + 1): byte loop with an 8-bit accumulator; verified
// against the documented CMD0 (0x4A) and CMD8 (0x43) checksums and against
// 22 published CID/CSD register images.
//
// SPI mode: command frames are 6 bytes: [0x40 | index] + 32-bit big-endian
// argument + [(CRC7 << 1) | 1]. CMD0's computed trailer is 0x95 and the
// canonical CMD8 (argument 0x000001AA) trailer is 0x87; the 0xAA check
// pattern is the low argument byte of CMD8. In SPI mode the CRC of most
// commands is not checked, so the marker trailer (0x95 or 0x01) is also
// accepted by the frame builder.
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no methods, no lambdas, no Vec[fn] dispatch;
//     no Vec[StructType] and no parallel vectors are needed (structs are
//     leaf values);
//   * Ok/Err construction is confined to the tiny leaf helpers `_ok_*` /
//     `_err_*` below (constructing Results directly inside other functions
//     miscompiles);
//   * every byte read from a Vec[UInt8] is widened with
//     `(x as Int) & 0xFF` before entering Int arithmetic;
//   * Str values are never compared with `==`; structs with Str fields are
//     reported field by field;
//   * bit extraction uses division by powers of two (`_pow2`), never a
//     shift on a value that could carry the sign bit; capacity math uses
//     multiplication only;
//   * names are materialized with xiom.string.builder.sb_to_str over a
//     NUL-free, validated-printable byte run (sb_to_str aborts on 0x00).

module xiom.sd

use xiom.convert;
use xiom.string.builder;

// --------------------------------------------------
//  Register lengths, structure versions and framing markers
// --------------------------------------------------

/// CID register length in bytes (128 bits).
pub const SD_CID_LEN: Int = 16;
/// CSD register length in bytes (128 bits).
pub const SD_CSD_LEN: Int = 16;
/// OCR register length in bytes (32 bits).
pub const SD_OCR_LEN: Int = 4;
/// SPI-mode command frame length in bytes.
pub const SD_SPI_FRAME_LEN: Int = 6;
/// SPI-mode command prefix base: byte 0 is 0x40 | command index.
pub const SD_SPI_CMD_PREFIX: Int = 64;
/// Documented CMD0 SPI trailer: (CRC7 0x4A << 1) | 1 = 0x95.
pub const SD_SPI_TRAILER_CMD0: Int = 149;
/// Computed CMD8 SPI trailer for the canonical argument 0x000001AA:
/// (CRC7 0x43 << 1) | 1 = 0x87.
pub const SD_SPI_TRAILER_CMD8: Int = 135;
/// Canonical CMD8 check pattern byte 0xAA (the low argument byte of CMD8
/// with VHS = 1). The documented SPI start-up markers are the pair
/// 0x95 (CMD0 trailer) / 0xAA (CMD8 check pattern byte).
pub const SD_SPI_MARKER_AA: Int = 170;
/// CSD_STRUCTURE value of a v1.0 (SDSC) register.
pub const SD_CSD_STRUCTURE_V1: Int = 0;
/// CSD_STRUCTURE value of a v2.0 (SDHC/SDXC) register.
pub const SD_CSD_STRUCTURE_V2: Int = 1;
/// CSD_STRUCTURE value of a v3.0 (SDUC) register (not decoded here).
pub const SD_CSD_STRUCTURE_V3: Int = 2;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Manufacturing date decoded from the CID: `year` is the full year
/// (2000 + the stored offset), `month` is 1..12.
pub type SdMdt = {
  year: Int;
  month: Int;
}

/// Decoded CID register fields. All values are non-negative; `oem_id` and
/// `product_name` are printable ASCII and carry no NUL bytes.
pub type SdCid = {
  manufacturer_id: Int;
  oem_id: Str;
  product_name: Str;
  revision_major: Int;
  revision_minor: Int;
  serial: Int;
  mdt_year: Int;
  mdt_month: Int;
  crc7: Int;
}

/// Decoded CSD register. `structure` is the raw CSD_STRUCTURE value
/// (0 = v1.0, 1 = v2.0); `c_size_mult` is 0 for v2.0; `taac`/`nsac`/
/// `tran_speed` are the raw bytes next to their decoded values;
/// `capacity_bytes` is the full user capacity in bytes.
pub type SdCsd = {
  structure: Int;
  taac: Int;
  taac_ns: Int;
  nsac: Int;
  nsac_ns: Int;
  tran_speed: Int;
  tran_speed_bps: Int;
  ccc: Int;
  read_bl_len: Int;
  read_bl_len_bytes: Int;
  read_bl_partial: Bool;
  write_blk_misalign: Bool;
  read_blk_misalign: Bool;
  dsr_imp: Bool;
  c_size: Int;
  c_size_mult: Int;
  erase_blk_en: Bool;
  sector_size: Int;
  erase_unit_bytes: Int;
  wp_grp_size: Int;
  wp_grp_enable: Bool;
  r2w_factor: Int;
  write_bl_len: Int;
  write_bl_len_bytes: Int;
  write_bl_partial: Bool;
  capacity_bytes: Int;
  crc7: Int;
}

/// Decoded OCR register. `raw` is the unsigned 32-bit value; `ready` is
/// bit 31 (true = card finished power-up), `ccs` bit 30 (true = block
/// addressed SDHC/SDXC), `uhs2` bit 29, `xpc` bit 28 and `voltage_mask`
/// bits [23:15] (bit 15 = 2.7-2.8 V .. bit 23 = 3.5-3.6 V).
pub type SdOcr = {
  raw: Int;
  ready: Bool;
  ccs: Bool;
  uhs2: Bool;
  xpc: Bool;
  voltage_mask: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[SdMdt, Str].
fn _ok_mdt(v: SdMdt) -> Result[SdMdt, Str] {
  return Ok(v);
}

// Err(m) for Result[SdMdt, Str].
fn _err_mdt(m: Str) -> Result[SdMdt, Str] {
  return Err(m);
}

// Ok(v) for Result[SdCid, Str].
fn _ok_cid(v: SdCid) -> Result[SdCid, Str] {
  return Ok(v);
}

// Err(m) for Result[SdCid, Str].
fn _err_cid(m: Str) -> Result[SdCid, Str] {
  return Err(m);
}

// Ok(v) for Result[SdCsd, Str].
fn _ok_csd(v: SdCsd) -> Result[SdCsd, Str] {
  return Ok(v);
}

// Err(m) for Result[SdCsd, Str].
fn _err_csd(m: Str) -> Result[SdCsd, Str] {
  return Err(m);
}

// Ok(v) for Result[SdOcr, Str].
fn _ok_ocr(v: SdOcr) -> Result[SdOcr, Str] {
  return Ok(v);
}

// Err(m) for Result[SdOcr, Str].
fn _err_ocr(m: Str) -> Result[SdOcr, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal arithmetic and register bit access
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// 2^k for 0 <= k <= 32, computed by repeated multiplication (no shift).
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Value of the bit at absolute position `bit` of a non-negative Int.
fn _int_bit(v: Int, bit: Int) -> Int {
  return (v / _pow2(bit)) % 2;
}

// `nbits` register bits starting at stream position `start`, MSB first,
// where stream position 0 is register bit 127 (the MSB of byte 0).
// Callers guarantee the bits are in bounds.
fn _bits(data: &Vec[UInt8], start: Int, nbits: Int) -> Int {
  var v = 0;
  var i = 0;
  while i < nbits {
    let pos = start + i;
    let b: Int = _byte(data, pos / 8);
    let shift = 7 - (pos % 8);
    v = v * 2 + (b / _pow2(shift)) % 2;
    i = i + 1;
  }
  return v;
}

// Register field [hi:lo] of a 128-bit register, MSB numbered 127.
fn _field(data: &Vec[UInt8], hi: Int, lo: Int) -> Int {
  return _bits(data, 127 - hi, hi - lo + 1);
}

// True when `v` is a printable ASCII byte (0x20..0x7E).
fn _printable(v: Int) -> Bool {
  return v >= 32 && v <= 126;
}

// CRC7 (x^7 + x^3 + 1) over the first `n` bytes of `data`. The accumulator
// is 8 bits: XOR the byte in, run eight shift/feedback steps, then the
// 7-bit result is the accumulator shifted down by one. Callers guarantee
// the bounds.
fn _crc7_first(data: &Vec[UInt8], n: Int) -> Int {
  var crc = 0;
  var i = 0;
  while i < n {
    crc = crc ^ _byte(data, i);
    var b = 0;
    while b < 8 {
      if (crc / 128) % 2 == 1 {
        crc = crc ^ 9;
      }
      crc = (crc * 2) % 256;
      b = b + 1;
    }
    i = i + 1;
  }
  return (crc / 2) % 128;
}

// Materialize `n` bytes starting at register byte offset `first` as a Str
// after validating every byte is printable. `label` names the field in the
// error text.
fn _register_str(data: &Vec[UInt8], first: Int, n: Int, label: Str) -> Result[Str, Str] {
  var i = 0;
  while i < n {
    let b: Int = _byte(data, first + i);
    if !_printable(b) {
      return _err_str("sd.cid: " + label + " byte at offset " + convert.int_to_string(first + i) + " is not printable (value " + convert.int_to_string(b) + ")");
    }
    i = i + 1;
  }
  var sb = Vec[UInt8].new();
  i = 0;
  while i < n {
    sb.push((_byte(data, first + i)) as UInt8);
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&sb));
}

// --------------------------------------------------
//  CRC7
// --------------------------------------------------

/// CRC7 (generator x^7 + x^3 + 1) of the whole byte vector, returned as a
/// 7-bit value. The SD command checksums 0x4A (CMD0) and 0x43 (CMD8)
/// follow from this function. Complexity: O(data.len()).
pub fn sd_crc7(data: &Vec[UInt8]) -> Int {
  return _crc7_first(data, data.len());
}

/// Computed CRC7 over the first 15 CID bytes (register bits [127:8]).
///
/// Err("sd.cid: register needs 16 bytes, have N") when the vector is not
/// exactly 16 bytes. Complexity: O(1).
pub fn sd_cid_crc(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CID_LEN {
    return _err_int("sd.cid: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_crc7_first(data, 15));
}

/// Stored CRC7 field of a CID (bits [7:1]), without validation.
///
/// Err("sd.cid: register needs 16 bytes, have N") when the vector is not
/// exactly 16 bytes. Complexity: O(1).
pub fn sd_cid_crc_stored(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CID_LEN {
    return _err_int("sd.cid: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_field(data, 7, 1));
}

/// Computed CRC7 over the first 15 CSD bytes (register bits [127:8]).
///
/// Err("sd.csd: register needs 16 bytes, have N") when the vector is not
/// exactly 16 bytes. Complexity: O(1).
pub fn sd_csd_crc(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_int("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_crc7_first(data, 15));
}

/// Stored CRC7 field of a CSD (bits [7:1]), without validation.
///
/// Err("sd.csd: register needs 16 bytes, have N") when the vector is not
/// exactly 16 bytes. Complexity: O(1).
pub fn sd_csd_crc_stored(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_int("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_field(data, 7, 1));
}

// --------------------------------------------------
//  CID accessors
// --------------------------------------------------

/// CID manufacturer id (MID, bits [127:120]), 0..255.
///
/// Err("sd.cid: register needs 16 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_cid_manufacturer_id(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CID_LEN {
    return _err_int("sd.cid: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_field(data, 127, 120));
}

/// CID OEM/application id (OID, bits [119:104]) as two printable ASCII
/// characters.
///
/// Err("sd.cid: register needs 16 bytes, have N") on a wrong length;
/// Err("sd.cid: oem id byte at offset B is not printable (value V)") when
/// a byte is outside 0x20..0x7E (B is the register byte offset 1..2).
/// Complexity: O(1).
pub fn sd_cid_oem_id(data: &Vec[UInt8]) -> Result[Str, Str] {
  if data.len() != SD_CID_LEN {
    return _err_str("sd.cid: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _register_str(data, 1, 2, "oem id");
}

/// CID product name (PNM, bits [103:64]) as five printable ASCII
/// characters, spaces preserved.
///
/// Err("sd.cid: register needs 16 bytes, have N") on a wrong length;
/// Err("sd.cid: product name byte at offset B is not printable (value V)")
/// when a byte is outside 0x20..0x7E (B is the register byte offset 3..7).
/// Complexity: O(1).
pub fn sd_cid_product_name(data: &Vec[UInt8]) -> Result[Str, Str] {
  if data.len() != SD_CID_LEN {
    return _err_str("sd.cid: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _register_str(data, 3, 5, "product name");
}

/// CID product revision (PRV, bits [63:56]) as the raw byte; the high
/// nibble is the major and the low nibble the minor revision.
///
/// Err("sd.cid: register needs 16 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_cid_revision(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CID_LEN {
    return _err_int("sd.cid: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_field(data, 63, 56));
}

/// CID product serial number (PSN, bits [55:24]) as an unsigned 32-bit
/// value.
///
/// Err("sd.cid: register needs 16 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_cid_serial(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CID_LEN {
    return _err_int("sd.cid: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_field(data, 55, 24));
}

/// CID manufacturing date (MDT, bits [19:8]): year = 2000 + bits [19:12],
/// month = bits [11:8].
///
/// Err("sd.cid: register needs 16 bytes, have N") on a wrong length;
/// Err("sd.cid: manufacturing month M out of range 1..12") when the month
/// nibble is 0 or 13..15. Complexity: O(1).
pub fn sd_cid_manufacturing_date(data: &Vec[UInt8]) -> Result[SdMdt, Str] {
  if data.len() != SD_CID_LEN {
    return _err_mdt("sd.cid: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  let year = 2000 + _field(data, 19, 12);
  let month = _field(data, 11, 8);
  if month < 1 || month > 12 {
    return _err_mdt("sd.cid: manufacturing month " + convert.int_to_string(month) + " out of range 1..12");
  }
  return _ok_mdt(SdMdt{ year: year; month: month; });
}

/// Parse and fully validate a 128-bit CID register image.
///
/// Validation order and errors:
///   1. wrong length -> "sd.cid: register needs 16 bytes, have N";
///   2. reserved bits [23:20] nonzero -> "sd.cid: reserved bits [23:20]
///      must be zero";
///   3. end bit 0 clear -> "sd.cid: end bit 0 must be 1";
///   4. month outside 1..12 -> the manufacturing-date error;
///   5. a non-printable OEM id or product name byte -> the offset error;
///   6. CRC7 mismatch -> "sd.cid: crc7 mismatch: stored N, computed M".
/// Complexity: O(1).
pub fn sd_cid_parse(data: &Vec[UInt8]) -> Result[SdCid, Str] {
  if data.len() != SD_CID_LEN {
    return _err_cid("sd.cid: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  if _field(data, 23, 20) != 0 {
    return _err_cid("sd.cid: reserved bits [23:20] must be zero");
  }
  if _field(data, 0, 0) != 1 {
    return _err_cid("sd.cid: end bit 0 must be 1");
  }
  let mdtr = sd_cid_manufacturing_date(data);
  if !mdtr.is_ok {
    return _err_cid(mdtr.error);
  }
  let oidr = sd_cid_oem_id(data);
  if !oidr.is_ok {
    return _err_cid(oidr.error);
  }
  let pnmr = sd_cid_product_name(data);
  if !pnmr.is_ok {
    return _err_cid(pnmr.error);
  }
  let stored = _field(data, 7, 1);
  let computed = _crc7_first(data, 15);
  if stored != computed {
    return _err_cid("sd.cid: crc7 mismatch: stored " + convert.int_to_string(stored) + ", computed " + convert.int_to_string(computed));
  }
  let oid: Str = oidr.value;
  let pnm: Str = pnmr.value;
  let mdt: SdMdt = mdtr.value;
  return _ok_cid(SdCid{
    manufacturer_id: _field(data, 127, 120);
    oem_id: oid;
    product_name: pnm;
    revision_major: _field(data, 63, 60);
    revision_minor: _field(data, 59, 56);
    serial: _field(data, 55, 24);
    mdt_year: mdt.year;
    mdt_month: mdt.month;
    crc7: stored;
  });
}

// --------------------------------------------------
//  CSD timing and TAAC / NSAC / TRAN_SPEED decoders
// --------------------------------------------------

// Time-value mantissa in tenths for a TAAC/TRAN_SPEED time value 1..15;
// 0 for the reserved time value 0.
fn _time_mant(tv: Int) -> Int {
  if tv == 1 {
    return 10;
  }
  if tv == 2 {
    return 12;
  }
  if tv == 3 {
    return 13;
  }
  if tv == 4 {
    return 15;
  }
  if tv == 5 {
    return 20;
  }
  if tv == 6 {
    return 25;
  }
  if tv == 7 {
    return 30;
  }
  if tv == 8 {
    return 35;
  }
  if tv == 9 {
    return 40;
  }
  if tv == 10 {
    return 45;
  }
  if tv == 11 {
    return 50;
  }
  if tv == 12 {
    return 55;
  }
  if tv == 13 {
    return 60;
  }
  if tv == 14 {
    return 70;
  }
  if tv == 15 {
    return 80;
  }
  return 0;
}

// TAAC time unit in nanoseconds (0 = 1 ns .. 7 = 10 ms).
fn _taac_unit_ns(unit: Int) -> Int {
  if unit == 0 {
    return 1;
  }
  if unit == 1 {
    return 10;
  }
  if unit == 2 {
    return 100;
  }
  if unit == 3 {
    return 1000;
  }
  if unit == 4 {
    return 10000;
  }
  if unit == 5 {
    return 100000;
  }
  if unit == 6 {
    return 1000000;
  }
  return 10000000;
}

// TRAN_SPEED transfer unit in bit/s (0 = 100 kbit/s .. 3 = 100 Mbit/s);
// 0 for the reserved units 4..7.
fn _tran_unit_bps(unit: Int) -> Int {
  if unit == 0 {
    return 100000;
  }
  if unit == 1 {
    return 1000000;
  }
  if unit == 2 {
    return 10000000;
  }
  if unit == 3 {
    return 100000000;
  }
  return 0;
}

/// Decode a TAAC byte to nanoseconds: value = time value x time unit,
/// where bits [6:3] select the tenths mantissa (1.0..8.0) and bits [2:0]
/// the unit (1 ns, 10 ns, 100 ns, 1 us, 10 us, 100 us, 1 ms, 10 ms).
/// The result is truncated to whole nanoseconds.
///
/// Err("sd.taac: value N out of range 0..255") outside a byte;
/// Err("sd.taac: value N has reserved bit 7 set"); Err("sd.taac: time
/// value 0 is reserved") for the reserved time value. Complexity: O(1).
pub fn sd_taac_ns(taac: Int) -> Result[Int, Str] {
  if taac < 0 || taac > 255 {
    return _err_int("sd.taac: value " + convert.int_to_string(taac) + " out of range 0..255");
  }
  if _int_bit(taac, 7) != 0 {
    return _err_int("sd.taac: value " + convert.int_to_string(taac) + " has reserved bit 7 set");
  }
  let tv = (taac / 8) % 16;
  if tv == 0 {
    return _err_int("sd.taac: time value 0 is reserved");
  }
  let unit = taac % 8;
  let mant = _time_mant(tv);
  let unit_ns = _taac_unit_ns(unit);
  return _ok_int((mant * unit_ns) / 10);
}

/// Decode an NSAC byte to nanoseconds: the unit is 100 ns, so the result
/// is NSAC * 100.
///
/// Err("sd.nsac: value N out of range 0..255") outside a byte.
/// Complexity: O(1).
pub fn sd_nsac_ns(nsac: Int) -> Result[Int, Str] {
  if nsac < 0 || nsac > 255 {
    return _err_int("sd.nsac: value " + convert.int_to_string(nsac) + " out of range 0..255");
  }
  return _ok_int(nsac * 100);
}

/// Decode a TRAN_SPEED byte to bit/s: value = time value x transfer unit,
/// where bits [6:3] select the tenths mantissa (1.0..8.0) and bits [2:0]
/// the unit (100 kbit/s, 1 Mbit/s, 10 Mbit/s, 100 Mbit/s). The result is
/// truncated to whole bit/s.
///
/// Err("sd.transpeed: value N out of range 0..255") outside a byte;
/// Err("sd.transpeed: value N has reserved bit 7 set"); Err("sd.transpeed:
/// time value 0 is reserved"); Err("sd.transpeed: transfer rate unit N is
/// reserved") for units 4..7. Complexity: O(1).
pub fn sd_tran_speed_bps(b: Int) -> Result[Int, Str] {
  if b < 0 || b > 255 {
    return _err_int("sd.transpeed: value " + convert.int_to_string(b) + " out of range 0..255");
  }
  if _int_bit(b, 7) != 0 {
    return _err_int("sd.transpeed: value " + convert.int_to_string(b) + " has reserved bit 7 set");
  }
  let tv = (b / 8) % 16;
  if tv == 0 {
    return _err_int("sd.transpeed: time value 0 is reserved");
  }
  let unit = b % 8;
  if unit > 3 {
    return _err_int("sd.transpeed: transfer rate unit " + convert.int_to_string(unit) + " is reserved");
  }
  let mant = _time_mant(tv);
  let unit_bps = _tran_unit_bps(unit);
  return _ok_int((mant * unit_bps) / 10);
}

// --------------------------------------------------
//  CSD accessors
// --------------------------------------------------

/// CSD_STRUCTURE value (bits [127:126]): 0 = v1.0, 1 = v2.0, 2 = v3.0, 3 =
/// reserved.
///
/// Err("sd.csd: register needs 16 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_csd_structure(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_int("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_field(data, 127, 126));
}

/// Human label for a CSD_STRUCTURE value: "1.0" (0), "2.0" (1), "3.0" (2)
/// or "reserved" (3 and anything else).
pub fn sd_csd_structure_label(structure: Int) -> Str {
  if structure == 0 {
    return "1.0";
  }
  if structure == 1 {
    return "2.0";
  }
  if structure == 2 {
    return "3.0";
  }
  return "reserved";
}

/// Raw TAAC byte of a CSD (bits [119:112]).
///
/// Err("sd.csd: register needs 16 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_csd_taac(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_int("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_field(data, 119, 112));
}

/// Raw NSAC byte of a CSD (bits [111:104]).
///
/// Err("sd.csd: register needs 16 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_csd_nsac(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_int("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_field(data, 111, 104));
}

/// Raw TRAN_SPEED byte of a CSD (bits [103:96]).
///
/// Err("sd.csd: register needs 16 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_csd_tran_speed(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_int("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_field(data, 103, 96));
}

/// READ_BL_LEN exponent of a CSD (bits [83:80]); the block length in bytes
/// is 2^READ_BL_LEN.
///
/// Err("sd.csd: register needs 16 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_csd_read_bl_len(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_int("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_field(data, 83, 80));
}

/// WRITE_BL_LEN exponent of a CSD (bits [25:22]); the block length in
/// bytes is 2^WRITE_BL_LEN.
///
/// Err("sd.csd: register needs 16 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_csd_write_bl_len(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_int("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_int(_field(data, 25, 22));
}

/// ERASE_BLK_EN flag of a CSD (bit 46): true means the erase unit is 512
/// bytes, false means the SECTOR_SIZE unit.
///
/// Err("sd.csd: register needs 16 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_csd_erase_blk_en(data: &Vec[UInt8]) -> Result[Bool, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_bool("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_bool(_field(data, 46, 46) == 1);
}

/// DSR_IMP flag of a CSD (bit 76): true when the configurable driver stage
/// register is implemented.
///
/// Err("sd.csd: register needs 16 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_csd_dsr_imp(data: &Vec[UInt8]) -> Result[Bool, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_bool("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_bool(_field(data, 76, 76) == 1);
}

/// C_SIZE of a CSD, version-aware: v1.0 bits [73:62] (12 bits), v2.0 bits
/// [69:48] (22 bits).
///
/// Err("sd.csd: register needs 16 bytes, have N") on a wrong length;
/// Err("sd.csd: reserved CSD structure value 3") for structure 3;
/// Err("sd.csd: CSD structure value 2 (v3.0) is not supported").
/// Complexity: O(1).
pub fn sd_csd_c_size(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_int("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  let st = _field(data, 127, 126);
  if st == SD_CSD_STRUCTURE_V1 {
    return _ok_int(_field(data, 73, 62));
  }
  if st == SD_CSD_STRUCTURE_V2 {
    return _ok_int(_field(data, 69, 48));
  }
  if st == SD_CSD_STRUCTURE_V3 {
    return _err_int("sd.csd: CSD structure value 2 (v3.0) is not supported");
  }
  return _err_int("sd.csd: reserved CSD structure value 3");
}

/// C_SIZE_MULT of a CSD: v1.0 bits [49:47] (3 bits); v2.0 has no such
/// field and reports 0.
///
/// Err("sd.csd: register needs 16 bytes, have N") on a wrong length;
/// Err("sd.csd: reserved CSD structure value 3") for structure 3;
/// Err("sd.csd: CSD structure value 2 (v3.0) is not supported").
/// Complexity: O(1).
pub fn sd_csd_c_size_mult(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_int("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  let st = _field(data, 127, 126);
  if st == SD_CSD_STRUCTURE_V1 {
    return _ok_int(_field(data, 49, 47));
  }
  if st == SD_CSD_STRUCTURE_V2 {
    return _ok_int(0);
  }
  if st == SD_CSD_STRUCTURE_V3 {
    return _err_int("sd.csd: CSD structure value 2 (v3.0) is not supported");
  }
  return _err_int("sd.csd: reserved CSD structure value 3");
}

/// Erase unit size of a CSD in bytes: 512 when ERASE_BLK_EN is set (and
/// always for v2.0), otherwise (SECTOR_SIZE + 1) * 2^WRITE_BL_LEN bytes.
///
/// Err("sd.csd: register needs 16 bytes, have N") on a wrong length;
/// Err("sd.csd: WRITE_BL_LEN N is reserved (valid 9..11)") when the
/// SECTOR_SIZE path is taken with a reserved write block length; the
/// structure errors of sd_csd_c_size. Complexity: O(1).
pub fn sd_csd_erase_unit_bytes(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_int("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  let st = _field(data, 127, 126);
  if st == SD_CSD_STRUCTURE_V2 {
    return _ok_int(512);
  }
  if st == SD_CSD_STRUCTURE_V3 {
    return _err_int("sd.csd: CSD structure value 2 (v3.0) is not supported");
  }
  if st != SD_CSD_STRUCTURE_V1 {
    return _err_int("sd.csd: reserved CSD structure value 3");
  }
  if _field(data, 46, 46) == 1 {
    return _ok_int(512);
  }
  let wbl = _field(data, 25, 22);
  if wbl < 9 || wbl > 11 {
    return _err_int("sd.csd: WRITE_BL_LEN " + convert.int_to_string(wbl) + " is reserved (valid 9..11)");
  }
  let sector = _field(data, 45, 39);
  return _ok_int((sector + 1) * _pow2(wbl));
}

/// User capacity of a CSD in bytes:
///   * v1.0: (C_SIZE + 1) * 2^(C_SIZE_MULT + 2) * 2^READ_BL_LEN;
///   * v2.0: (C_SIZE + 1) * 512 KiB.
///
/// Err("sd.csd: register needs 16 bytes, have N") on a wrong length;
/// Err("sd.csd: READ_BL_LEN N is reserved (valid 9..11)") on a reserved
/// v1.0 block length; the structure errors of sd_csd_c_size.
/// Complexity: O(1).
pub fn sd_csd_capacity_bytes(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_int("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  let st = _field(data, 127, 126);
  if st == SD_CSD_STRUCTURE_V2 {
    let cs = _field(data, 69, 48);
    return _ok_int((cs + 1) * 524288);
  }
  if st == SD_CSD_STRUCTURE_V3 {
    return _err_int("sd.csd: CSD structure value 2 (v3.0) is not supported");
  }
  if st != SD_CSD_STRUCTURE_V1 {
    return _err_int("sd.csd: reserved CSD structure value 3");
  }
  let bl = _field(data, 83, 80);
  if bl < 9 || bl > 11 {
    return _err_int("sd.csd: READ_BL_LEN " + convert.int_to_string(bl) + " is reserved (valid 9..11)");
  }
  let cs = _field(data, 73, 62);
  let cm = _field(data, 49, 47);
  return _ok_int((cs + 1) * _pow2(cm + 2) * _pow2(bl));
}

/// Parse and fully validate a 128-bit CSD register image.
///
/// Validation order and errors:
///   1. wrong length -> "sd.csd: register needs 16 bytes, have N";
///   2. structure 2 -> "sd.csd: CSD structure value 2 (v3.0) is not
///      supported"; structure 3 -> "sd.csd: reserved CSD structure
///      value 3";
///   3. reserved zero fields, by version: v1.0 [125:120], [75:74],
///      [30:29], [20:16], [9:8]; v2.0 [125:120], [75:70], [47], [30:29],
///      [20:16], [9:8] -> "sd.csd: reserved bits [HI:LO] must be zero";
///   4. end bit 0 clear -> "sd.csd: end bit 0 must be 1";
///   5. TAAC/NSAC/TRAN_SPEED decoding errors (see the decoders);
///   6. READ_BL_LEN or WRITE_BL_LEN outside 9..11 -> "sd.csd: <FIELD> N is
///      reserved (valid 9..11)";
///   7. CRC7 mismatch -> "sd.csd: crc7 mismatch: stored N, computed M".
/// Complexity: O(1).
pub fn sd_csd_parse(data: &Vec[UInt8]) -> Result[SdCsd, Str] {
  if data.len() != SD_CSD_LEN {
    return _err_csd("sd.csd: register needs 16 bytes, have " + convert.int_to_string(data.len()));
  }
  let st = _field(data, 127, 126);
  if st == SD_CSD_STRUCTURE_V3 {
    return _err_csd("sd.csd: CSD structure value 2 (v3.0) is not supported");
  }
  if st != SD_CSD_STRUCTURE_V1 && st != SD_CSD_STRUCTURE_V2 {
    return _err_csd("sd.csd: reserved CSD structure value 3");
  }
  if _field(data, 125, 120) != 0 {
    return _err_csd("sd.csd: reserved bits [125:120] must be zero");
  }
  if st == SD_CSD_STRUCTURE_V1 {
    if _field(data, 75, 74) != 0 {
      return _err_csd("sd.csd: reserved bits [75:74] must be zero");
    }
  } else {
    if _field(data, 75, 70) != 0 {
      return _err_csd("sd.csd: reserved bits [75:70] must be zero");
    }
    if _field(data, 47, 47) != 0 {
      return _err_csd("sd.csd: reserved bits [47] must be zero");
    }
  }
  if _field(data, 30, 29) != 0 {
    return _err_csd("sd.csd: reserved bits [30:29] must be zero");
  }
  if _field(data, 20, 16) != 0 {
    return _err_csd("sd.csd: reserved bits [20:16] must be zero");
  }
  if _field(data, 9, 8) != 0 {
    return _err_csd("sd.csd: reserved bits [9:8] must be zero");
  }
  if _field(data, 0, 0) != 1 {
    return _err_csd("sd.csd: end bit 0 must be 1");
  }
  let taac = _field(data, 119, 112);
  let taacr = sd_taac_ns(taac);
  if !taacr.is_ok {
    return _err_csd(taacr.error);
  }
  let nsac = _field(data, 111, 104);
  let nsacr = sd_nsac_ns(nsac);
  if !nsacr.is_ok {
    return _err_csd(nsacr.error);
  }
  let tran = _field(data, 103, 96);
  let tranr = sd_tran_speed_bps(tran);
  if !tranr.is_ok {
    return _err_csd(tranr.error);
  }
  let rbl = _field(data, 83, 80);
  if rbl < 9 || rbl > 11 {
    return _err_csd("sd.csd: READ_BL_LEN " + convert.int_to_string(rbl) + " is reserved (valid 9..11)");
  }
  let wbl = _field(data, 25, 22);
  if wbl < 9 || wbl > 11 {
    return _err_csd("sd.csd: WRITE_BL_LEN " + convert.int_to_string(wbl) + " is reserved (valid 9..11)");
  }
  let stored = _field(data, 7, 1);
  let computed = _crc7_first(data, 15);
  if stored != computed {
    return _err_csd("sd.csd: crc7 mismatch: stored " + convert.int_to_string(stored) + ", computed " + convert.int_to_string(computed));
  }
  let taac_ns: Int = taacr.value;
  let nsac_ns: Int = nsacr.value;
  let bps: Int = tranr.value;
  let capr = sd_csd_capacity_bytes(data);
  if !capr.is_ok {
    return _err_csd(capr.error);
  }
  let erase_r = sd_csd_erase_unit_bytes(data);
  if !erase_r.is_ok {
    return _err_csd(erase_r.error);
  }
  var c_size_mult = 0;
  if st == SD_CSD_STRUCTURE_V1 {
    c_size_mult = _field(data, 49, 47);
  }
  let capacity: Int = capr.value;
  let erase_unit: Int = erase_r.value;
  return _ok_csd(SdCsd{
    structure: st;
    taac: taac;
    taac_ns: taac_ns;
    nsac: nsac;
    nsac_ns: nsac_ns;
    tran_speed: tran;
    tran_speed_bps: bps;
    ccc: _field(data, 95, 84);
    read_bl_len: rbl;
    read_bl_len_bytes: _pow2(rbl);
    read_bl_partial: _field(data, 79, 79) == 1;
    write_blk_misalign: _field(data, 78, 78) == 1;
    read_blk_misalign: _field(data, 77, 77) == 1;
    dsr_imp: _field(data, 76, 76) == 1;
    c_size: _c_size_for_structure(st, data);
    c_size_mult: c_size_mult;
    erase_blk_en: _field(data, 46, 46) == 1;
    sector_size: _field(data, 45, 39);
    erase_unit_bytes: erase_unit;
    wp_grp_size: _field(data, 38, 32);
    wp_grp_enable: _field(data, 31, 31) == 1;
    r2w_factor: _field(data, 28, 26);
    write_bl_len: wbl;
    write_bl_len_bytes: _pow2(wbl);
    write_bl_partial: _field(data, 21, 21) == 1;
    capacity_bytes: capacity;
    crc7: stored;
  });
}

// C_SIZE for the already validated structure in sd_csd_parse; both
// structures are valid here, so this never fails for its caller.
fn _c_size_for_structure(st: Int, data: &Vec[UInt8]) -> Int {
  if st == SD_CSD_STRUCTURE_V2 {
    return _field(data, 69, 48);
  }
  return _field(data, 73, 62);
}

// --------------------------------------------------
//  OCR register
// --------------------------------------------------

/// Raw unsigned 32-bit OCR value from 4 big-endian bytes.
///
/// Err("sd.ocr: register needs 4 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_ocr_value(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() != SD_OCR_LEN {
    return _err_int("sd.ocr: register needs 4 bytes, have " + convert.int_to_string(data.len()));
  }
  let v = _byte(data, 0) * 16777216 + _byte(data, 1) * 65536 + _byte(data, 2) * 256 + _byte(data, 3);
  return _ok_int(v);
}

/// Ready flag of an OCR register (bit 31, the inverted busy bit): true =
/// card finished power-up.
///
/// Err("sd.ocr: register needs 4 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_ocr_ready(data: &Vec[UInt8]) -> Result[Bool, Str] {
  let r = sd_ocr_value(data);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: Int = r.value;
  return _ok_bool(_int_bit(v, 31) == 1);
}

/// CCS flag of an OCR register (bit 30): true = block-addressed high
/// capacity card (SDHC/SDXC); valid only once the card is ready.
///
/// Err("sd.ocr: register needs 4 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_ocr_ccs(data: &Vec[UInt8]) -> Result[Bool, Str] {
  let r = sd_ocr_value(data);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: Int = r.value;
  return _ok_bool(_int_bit(v, 30) == 1);
}

/// Voltage window mask of an OCR register (bits [23:15]); bit 0 of the
/// mask is the 2.7-2.8 V window, bit 8 the 3.5-3.6 V window.
///
/// Err("sd.ocr: register needs 4 bytes, have N") on a wrong length.
/// Complexity: O(1).
pub fn sd_ocr_voltage_mask(data: &Vec[UInt8]) -> Result[Int, Str] {
  let r = sd_ocr_value(data);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Int = r.value;
  return _ok_int((v / _pow2(15)) % 512);
}

/// OCR voltage-window bit index for the low bound of a 0.1 V window:
/// 2700 mV -> 15 (2.7-2.8 V) up to 3500 mV -> 23 (3.5-3.6 V).
///
/// Err("sd.ocr: voltage N out of range 2700..3500") and
/// Err("sd.ocr: voltage N is not a multiple of 100"). Complexity: O(1).
pub fn sd_ocr_voltage_bit(vdd_mv: Int) -> Result[Int, Str] {
  if vdd_mv < 2700 || vdd_mv > 3500 {
    return _err_int("sd.ocr: voltage " + convert.int_to_string(vdd_mv) + " out of range 2700..3500");
  }
  if vdd_mv % 100 != 0 {
    return _err_int("sd.ocr: voltage " + convert.int_to_string(vdd_mv) + " is not a multiple of 100");
  }
  return _ok_int(15 + (vdd_mv - 2700) / 100);
}

/// True when the OCR voltage window mask advertises the 0.1 V window whose
/// low bound is `vdd_mv` (2700..3500 in 100 mV steps).
///
/// Err("sd.ocr: register needs 4 bytes, have N") on a wrong length, plus
/// the sd_ocr_voltage_bit errors. Complexity: O(1).
pub fn sd_ocr_supports_voltage(data: &Vec[UInt8], vdd_mv: Int) -> Result[Bool, Str] {
  let bitr = sd_ocr_voltage_bit(vdd_mv);
  if !bitr.is_ok {
    return _err_bool(bitr.error);
  }
  let maskr = sd_ocr_voltage_mask(data);
  if !maskr.is_ok {
    return _err_bool(maskr.error);
  }
  let bit: Int = bitr.value;
  let mask: Int = maskr.value;
  return _ok_bool((mask / _pow2(bit - 15)) % 2 == 1);
}

/// Parse and validate a 32-bit OCR image.
///
/// Validation order and errors:
///   1. wrong length -> "sd.ocr: register needs 4 bytes, have N";
///   2. reserved bits [26:25] nonzero -> "sd.ocr: reserved bits [26:25]
///      must be zero";
///   3. reserved bits [14:0] nonzero -> "sd.ocr: reserved bits [14:0]
///      must be zero".
/// Complexity: O(1).
pub fn sd_ocr_parse(data: &Vec[UInt8]) -> Result[SdOcr, Str] {
  let vr = sd_ocr_value(data);
  if !vr.is_ok {
    return _err_ocr(vr.error);
  }
  let raw: Int = vr.value;
  if (raw / _pow2(25)) % 4 != 0 {
    return _err_ocr("sd.ocr: reserved bits [26:25] must be zero");
  }
  if raw % _pow2(15) != 0 {
    return _err_ocr("sd.ocr: reserved bits [14:0] must be zero");
  }
  return _ok_ocr(SdOcr{
    raw: raw;
    ready: _int_bit(raw, 31) == 1;
    ccs: _int_bit(raw, 30) == 1;
    uhs2: _int_bit(raw, 29) == 1;
    xpc: _int_bit(raw, 28) == 1;
    voltage_mask: (raw / _pow2(15)) % 512;
  });
}

// --------------------------------------------------
//  SPI-mode framing
// --------------------------------------------------

// Assemble a 6-byte SPI frame from validated pieces:
// [0x40 | index] + big-endian argument + trailer.
fn _spi_frame(index: Int, arg: Int, trailer: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((64 + index) as UInt8);
  out.push(((arg / 16777216) % 256) as UInt8);
  out.push(((arg / 65536) % 256) as UInt8);
  out.push(((arg / 256) % 256) as UInt8);
  out.push((arg % 256) as UInt8);
  out.push(trailer as UInt8);
  return out;
}

// Shared index/argument validation for the frame builders.
fn _spi_args_ok(index: Int, arg: Int) -> Result[Unit, Str] {
  if index < 0 || index > 63 {
    return _err_unit("sd.spi: command index " + convert.int_to_string(index) + " out of range 0..63");
  }
  if arg < 0 || arg > _pow2(32) - 1 {
    return _err_unit("sd.spi: argument " + convert.int_to_string(arg) + " does not fit in 32 bits");
  }
  return _ok_unit();
}

/// Build a 6-byte SPI command frame with the CRC7 trailer computed over
/// the first five bytes: [0x40 | index] + 32-bit big-endian argument +
/// [(CRC7 << 1) | 1].
///
/// CMD0 (index 0, argument 0) yields 40 00 00 00 00 95 and the canonical
/// CMD8 (index 8, argument 0x000001AA) yields 48 00 00 01 AA 87.
///
/// Err("sd.spi: command index N out of range 0..63");
/// Err("sd.spi: argument N does not fit in 32 bits").
/// Complexity: O(1).
pub fn sd_spi_command_frame(index: Int, arg: Int) -> Result[Vec[UInt8], Str] {
  let chk = _spi_args_ok(index, arg);
  if !chk.is_ok {
    return _err_bytes(chk.error);
  }
  var head = Vec[UInt8].new();
  head.push((64 + index) as UInt8);
  head.push(((arg / 16777216) % 256) as UInt8);
  head.push(((arg / 65536) % 256) as UInt8);
  head.push(((arg / 256) % 256) as UInt8);
  head.push((arg % 256) as UInt8);
  let crc = _crc7_first(&head, 5);
  return _ok_bytes(_spi_frame(index, arg, crc * 2 + 1));
}

/// Build a 6-byte SPI command frame with a caller-supplied marker trailer
/// (bit 0 must be the end bit 1). In SPI mode the CRC is only checked for
/// CMD0/CMD8, so hosts send 0x95, 0x01 or another odd byte for the rest;
/// this builder emits the documented marker instead of a computed CRC.
///
/// Err("sd.spi: command index N out of range 0..63");
/// Err("sd.spi: argument N does not fit in 32 bits");
/// Err("sd.spi: trailer marker N out of range 0..255");
/// Err("sd.spi: trailer marker N must have end bit 1").
/// Complexity: O(1).
pub fn sd_spi_command_frame_marker(index: Int, arg: Int, marker: Int) -> Result[Vec[UInt8], Str] {
  let chk = _spi_args_ok(index, arg);
  if !chk.is_ok {
    return _err_bytes(chk.error);
  }
  if marker < 0 || marker > 255 {
    return _err_bytes("sd.spi: trailer marker " + convert.int_to_string(marker) + " out of range 0..255");
  }
  if marker % 2 != 1 {
    return _err_bytes("sd.spi: trailer marker " + convert.int_to_string(marker) + " must have end bit 1");
  }
  return _ok_bytes(_spi_frame(index, arg, marker));
}

/// Canonical CMD0 (GO_IDLE_STATE) SPI frame using the documented 0x95
/// trailer: 40 00 00 00 00 95. Complexity: O(1).
pub fn sd_spi_cmd0_frame() -> Result[Vec[UInt8], Str] {
  return sd_spi_command_frame_marker(0, 0, SD_SPI_TRAILER_CMD0);
}

/// Canonical CMD8 (SEND_IF_COND) SPI frame: index 8, argument
/// (VHS << 8) | check, computed CRC trailer. `vhs` is the voltage class
/// 0..15 (1 = 2.7-3.6 V) and `check` the check pattern byte (0xAA).
/// With vhs = 1 and check = 0xAA the frame is 48 00 00 01 AA 87.
///
/// Err("sd.spi: cmd8 voltage N out of range 0..15");
/// Err("sd.spi: cmd8 check pattern N out of range 0..255").
/// Complexity: O(1).
pub fn sd_spi_cmd8_frame(vhs: Int, check: Int) -> Result[Vec[UInt8], Str] {
  if vhs < 0 || vhs > 15 {
    return _err_bytes("sd.spi: cmd8 voltage " + convert.int_to_string(vhs) + " out of range 0..15");
  }
  if check < 0 || check > 255 {
    return _err_bytes("sd.spi: cmd8 check pattern " + convert.int_to_string(check) + " out of range 0..255");
  }
  return sd_spi_command_frame(8, vhs * 256 + check);
}

// Frame length check shared by the inspectors.
fn _spi_len_ok(data: &Vec[UInt8]) -> Result[Unit, Str] {
  if data.len() != SD_SPI_FRAME_LEN {
    return _err_unit("sd.spi: frame needs 6 bytes, have " + convert.int_to_string(data.len()));
  }
  return _ok_unit();
}

// Prefix check shared by the inspectors: byte 0 bits 7:6 must be 01.
fn _spi_prefix_ok(data: &Vec[UInt8]) -> Result[Unit, Str] {
  let b0: Int = _byte(data, 0);
  if (b0 / 64) % 4 != 1 {
    return _err_unit("sd.spi: prefix byte " + convert.int_to_string(b0) + " does not have bits 7:6 = 01");
  }
  return _ok_unit();
}

// End bit check shared by the inspectors: trailer bit 0 must be 1.
fn _spi_end_bit_ok(data: &Vec[UInt8]) -> Result[Unit, Str] {
  let b5: Int = _byte(data, 5);
  if b5 % 2 != 1 {
    return _err_unit("sd.spi: trailer byte " + convert.int_to_string(b5) + " does not have end bit 1");
  }
  return _ok_unit();
}

/// Command index of an SPI frame (byte 0 low six bits).
///
/// Err("sd.spi: frame needs 6 bytes, have N");
/// Err("sd.spi: prefix byte N does not have bits 7:6 = 01").
/// Complexity: O(1).
pub fn sd_spi_frame_index(data: &Vec[UInt8]) -> Result[Int, Str] {
  let lc = _spi_len_ok(data);
  if !lc.is_ok {
    return _err_int(lc.error);
  }
  let pc = _spi_prefix_ok(data);
  if !pc.is_ok {
    return _err_int(pc.error);
  }
  return _ok_int(_byte(data, 0) % 64);
}

/// 32-bit big-endian argument of an SPI frame (bytes 1..4).
///
/// Err("sd.spi: frame needs 6 bytes, have N").
/// Complexity: O(1).
pub fn sd_spi_frame_argument(data: &Vec[UInt8]) -> Result[Int, Str] {
  let lc = _spi_len_ok(data);
  if !lc.is_ok {
    return _err_int(lc.error);
  }
  let v = _byte(data, 1) * 16777216 + _byte(data, 2) * 65536 + _byte(data, 3) * 256 + _byte(data, 4);
  return _ok_int(v);
}

/// Trailer byte of an SPI frame (byte 5), including the end bit.
///
/// Err("sd.spi: frame needs 6 bytes, have N").
/// Complexity: O(1).
pub fn sd_spi_frame_trailer(data: &Vec[UInt8]) -> Result[Int, Str] {
  let lc = _spi_len_ok(data);
  if !lc.is_ok {
    return _err_int(lc.error);
  }
  return _ok_int(_byte(data, 5));
}

/// Stored CRC7 of an SPI frame: the trailer shifted down by one (the low
/// bit is the end bit).
///
/// Err("sd.spi: frame needs 6 bytes, have N").
/// Complexity: O(1).
pub fn sd_spi_frame_crc(data: &Vec[UInt8]) -> Result[Int, Str] {
  let lc = _spi_len_ok(data);
  if !lc.is_ok {
    return _err_int(lc.error);
  }
  return _ok_int(_byte(data, 5) / 2);
}

/// True when the stored CRC7 of an SPI frame matches the CRC7 computed
/// over its first five bytes.
///
/// Err("sd.spi: frame needs 6 bytes, have N");
/// Err("sd.spi: trailer byte N does not have end bit 1");
/// Err("sd.spi: crc7 mismatch: stored N, computed M").
/// Complexity: O(1).
pub fn sd_spi_frame_crc_ok(data: &Vec[UInt8]) -> Result[Bool, Str] {
  let lc = _spi_len_ok(data);
  if !lc.is_ok {
    return _err_bool(lc.error);
  }
  let ec = _spi_end_bit_ok(data);
  if !ec.is_ok {
    return _err_bool(ec.error);
  }
  let stored = _byte(data, 5) / 2;
  let computed = _crc7_first(data, 5);
  if stored != computed {
    return _err_bool("sd.spi: crc7 mismatch: stored " + convert.int_to_string(stored) + ", computed " + convert.int_to_string(computed));
  }
  return _ok_bool(true);
}

/// Validate an SPI frame structurally (length, 0x40|index prefix, end bit)
/// and check its CRC7.
///
/// Errors: the sd_spi_frame_crc_ok catalog. Complexity: O(1).
pub fn sd_spi_frame_check(data: &Vec[UInt8]) -> Result[Unit, Str] {
  let lc = _spi_len_ok(data);
  if !lc.is_ok {
    return _err_unit(lc.error);
  }
  let pc = _spi_prefix_ok(data);
  if !pc.is_ok {
    return _err_unit(pc.error);
  }
  let cc = sd_spi_frame_crc_ok(data);
  if !cc.is_ok {
    return _err_unit(cc.error);
  }
  return _ok_unit();
}
