// XIOM -- xiom.flash: SPI NOR flash identification and SFDP (JESD216) codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) codec for the identification layer of SPI NOR flash
// memory. Scope: bytes in, typed values out. There is NO device access: no
// bus I/O, no CS handling, no timing, no command execution. Everything is a
// free function over Int, Bool, Str and Vec[UInt8] plus small leaf structs.
//
// What is implemented:
//
//   1. JEDEC ID (RDID 0x9F response, 3 bytes):
//      manufacturer byte + memory type byte + capacity byte. A documented
//      manufacturer subset is decoded to names; the capacity byte N maps to
//      2^N bytes with N accepted only in 8..32 (256 B .. 4 GiB).
//
//   2. The common 25-series command set (18 opcodes, see the constants
//      below) plus status register 1 bit decode (WIP, WEL, BP0..BP2, TB,
//      SEC, SRP0).
//
//   3. SFDP (JESD216) structure parsing:
//      * header: "SFDP" signature (bytes 53 46 44 50, i.e. the little-endian
//        word 0x50444653), minor revision (byte 4), major revision (byte 5),
//        NPH (byte 6, 0-based number of parameter headers, so the header
//        count is NPH + 1) and the unused byte 7;
//      * parameter header table: 8-byte entries from offset 8; each entry is
//        ID LSB (byte 0), ID MSB (byte 1) -> 16-bit little-endian parameter
//        ID (the JEDEC basic table is 0xFF00, i.e. bytes 00 FF; the "not
//        supported" marker is 0xFFFF), table major (byte 2), table minor
//        (byte 3), a 24-bit little-endian parameter table pointer
//        (bytes 4..6) and the table length in DWORDs (byte 7);
//      * Basic Flash Parameter Table (BFPT) decode from the parameter table
//        selected by ID 0xFF00 (highest minor revision, then longest):
//        density (DWORD 2: either value+1 bits, or 2^exponent bits when
//        bit 31 is set), 4-byte addressing support (DWORD 1 bits [18:17]),
//        the four classic fast-read commands 1-1-2 / 1-2-2 / 1-1-4 / 1-4-4
//        (support bits 16/20/22/21 of DWORD 1; opcode, mode clocks and wait
//        states in DWORD 3 and DWORD 4), DTR support (bit 19), page size
//        (DWORD 11 bits [7:4], N -> 2^N bytes) and the four erase types
//        (DWORD 8 and DWORD 9: size exponent and opcode per 16-bit half).
//        Erase flags for 4 KiB / 32 KiB / 64 KiB / 256 KiB plus a "bulk"
//        flag (a supported erase type covers the whole capacity) are
//        derived, never invented: DWORDs the table does not carry decode as
//        absent (page size exponent -1) or unsupported (size 0).
//
//   4. Sector map helper: address -> sector index and intra-sector offset
//      with truncating division and modulo, and the inverse index -> range.
//      Documented boundary rules: 0 <= address < capacity, whole sectors
//      only (capacity % sector_size == 0), index in 0..sector_count-1.
//
// Error model: every fallible function returns Result[T, FlashError] with a
// stable lowercase "flash: ..." message and a byte offset. The offset is the
// position of the offending field or byte in the input buffer, data.len()
// when the buffer ended mid-parse, -1 when the error concerns a scalar input
// with no stream position, and for an out-of-range sector address the
// offending address itself. An Err never carries a half-built result.
//
// Layer boundary: BFPT values (capacity, erase sizes, page size) feed the
// sector-map helper; nothing here is coupled to xiom.spi or any bus driver.
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no methods, no lambdas, no Vec[fn] dispatch, no
//     Vec[StructType]; structs are leaf values (nested struct fields only);
//   * Ok/Err construction is confined to the tiny leaf helpers `_ok_*` /
//     `_err_*` below (constructing Results directly inside other functions
//     miscompiles);
//   * every byte read from a Vec[UInt8] is widened with `(x as Int) & 0xFF`
//     before entering Int arithmetic, including bytes >= 0x80;
//   * little-endian 32-bit SFDP fields are composed explicitly byte by byte
//     (b0 + b1*256 + b2*65536 + b3*16777216), never with shifts;
//   * all bit tests use division and `% 2` on non-negative Ints; every
//     computed field is bound to a typed local before it enters a struct
//     literal;
//   * no Str value is ever compared with `==` in this module (BUG 17);
//   * no `&struct.field` is passed as a `&Vec[UInt8]` parameter: this module
//     has no Vec fields in structs at all;
//   * no function named `log`, no `&mut` out-params, no `as` identifier.

module xiom.flash

// --------------------------------------------------
//  Command-set constants (common 25-series SPI NOR)
// --------------------------------------------------

/// READ (0x03): read data bytes, low frequency.
pub const FLASH_CMD_READ: Int = 3;
/// FAST_READ (0x0B): read data bytes, high frequency.
pub const FLASH_CMD_FAST_READ: Int = 11;
/// FAST_READ_QUAD_IO (0xEB): quad I/O fast read.
pub const FLASH_CMD_FAST_READ_QUAD_IO: Int = 235;
/// PAGE_PROGRAM (0x02): program up to one page.
pub const FLASH_CMD_PAGE_PROGRAM: Int = 2;
/// SECTOR_ERASE (0x20): erase a 4 KiB sector.
pub const FLASH_CMD_SECTOR_ERASE: Int = 32;
/// BLOCK_ERASE (0xD8): erase a 64 KiB block.
pub const FLASH_CMD_BLOCK_ERASE: Int = 216;
/// WRITE_ENABLE (0x06): set the write enable latch.
pub const FLASH_CMD_WRITE_ENABLE: Int = 6;
/// WRITE_DISABLE (0x04): clear the write enable latch.
pub const FLASH_CMD_WRITE_DISABLE: Int = 4;
/// READ_STATUS1 (0x05): read status register 1.
pub const FLASH_CMD_READ_STATUS1: Int = 5;
/// READ_STATUS2 (0x35): read status register 2 (vendor config register).
pub const FLASH_CMD_READ_STATUS2: Int = 53;
/// WRITE_STATUS (0x01): write status register 1.
pub const FLASH_CMD_WRITE_STATUS: Int = 1;
/// READ_ID (0x9F): read the JEDEC ID (RDID).
pub const FLASH_CMD_READ_ID: Int = 159;
/// READ_SFDP (0x5A): read Serial Flash Discoverable Parameters (RDSFDP).
pub const FLASH_CMD_READ_SFDP: Int = 90;
/// CHIP_ERASE (0xC7): erase the whole chip.
pub const FLASH_CMD_CHIP_ERASE: Int = 199;
/// CHIP_ERASE_ALT (0x60): alternate/legacy chip erase opcode.
pub const FLASH_CMD_CHIP_ERASE_ALT: Int = 96;
/// READ_4B (0x4B): fast read with a 32-bit address (vendor-common).
pub const FLASH_CMD_READ_4B: Int = 75;
/// RESET_ENABLE (0x66): software reset enable.
pub const FLASH_CMD_RESET_ENABLE: Int = 102;
/// RESET (0x99): software reset.
pub const FLASH_CMD_RESET: Int = 153;
/// Number of commands in the pinned 25-series subset.
pub const FLASH_COMMAND_COUNT: Int = 18;

// --------------------------------------------------
//  Status register 1 bit positions
// --------------------------------------------------

/// SR1 bit 0: write in progress.
pub const FLASH_SR1_BIT_WIP: Int = 0;
/// SR1 bit 1: write enable latch.
pub const FLASH_SR1_BIT_WEL: Int = 1;
/// SR1 bit 2: block protect 0.
pub const FLASH_SR1_BIT_BP0: Int = 2;
/// SR1 bit 3: block protect 1.
pub const FLASH_SR1_BIT_BP1: Int = 3;
/// SR1 bit 4: block protect 2.
pub const FLASH_SR1_BIT_BP2: Int = 4;
/// SR1 bit 5: top/bottom protect.
pub const FLASH_SR1_BIT_TB: Int = 5;
/// SR1 bit 6: sector/block protect.
pub const FLASH_SR1_BIT_SEC: Int = 6;
/// SR1 bit 7: status register protect 0.
pub const FLASH_SR1_BIT_SRP0: Int = 7;

// --------------------------------------------------
//  JEDEC ID and SFDP constants
// --------------------------------------------------

/// Smallest accepted JEDEC capacity byte (2^8 = 256 bytes).
pub const FLASH_JEDEC_MIN_CAPACITY_CODE: Int = 8;
/// Largest accepted JEDEC capacity byte (2^32 = 4 GiB).
pub const FLASH_JEDEC_MAX_CAPACITY_CODE: Int = 32;
/// Number of manufacturers in the documented subset.
pub const FLASH_MANUFACTURER_COUNT: Int = 9;
/// SFDP signature bytes 53 46 44 50 read as a little-endian 32-bit word.
pub const FLASH_SFDP_SIGNATURE: Int = 1346651731;
/// SFDP/JESD216 major revision accepted by this decoder.
pub const FLASH_SFDP_MAJOR: Int = 1;
/// Highest accepted SFDP/JESD216 minor revision (revision J or lower).
pub const FLASH_SFDP_MAX_MINOR: Int = 9;
/// JEDEC basic flash parameter table ID (bytes 00 FF, LE word 0xFF00).
pub const FLASH_SFDP_BASIC_ID: Int = 65280;
/// "Not supported"/unused parameter ID (bytes FF FF).
pub const FLASH_SFDP_UNUSED_ID: Int = 65535;
/// Sector map parameter table ID (bytes 81 FF, LE word 0xFF81).
pub const FLASH_SFDP_SECTOR_MAP_ID: Int = 65409;
/// 4-byte address instruction table ID (bytes 84 FF, LE word 0xFF84).
pub const FLASH_SFDP_4BAIT_ID: Int = 65412;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// A codec error. `offset` is the byte offset of the offending field in the
/// input buffer, `data.len()` when the buffer ended mid-parse, -1 for scalar
/// inputs with no stream position, and the offending address itself for an
/// out-of-range sector address. `message` is a stable lowercase "flash:"
/// text from the catalog in SPEC.md.
pub type FlashError = {
  offset: Int;
  message: Str;
}

/// Decoded 3-byte JEDEC ID (RDID 0x9F response). `manufacturer_name` is
/// "unknown" for an ID outside the documented subset; `capacity_bytes` is
/// 2^capacity_code (256 B .. 4 GiB).
pub type FlashJedecId = {
  manufacturer_id: Int;
  manufacturer_name: Str;
  memory_type: Int;
  capacity_code: Int;
  capacity_bytes: Int;
}

/// Decoded status register 1. `block_protect` is the 3-bit (BP2 BP1 BP0)
/// value 0..7; the individual bits are exposed as booleans.
pub type FlashStatus1 = {
  raw: Int;
  wip: Bool;
  wel: Bool;
  bp0: Bool;
  bp1: Bool;
  bp2: Bool;
  tb: Bool;
  sec: Bool;
  srp0: Bool;
  block_protect: Int;
}

/// Decoded SFDP header. `nph` is the raw byte (0-based count) and
/// `parameter_header_count` is nph + 1.
pub type FlashSfdpHeader = {
  major: Int;
  minor: Int;
  nph: Int;
  parameter_header_count: Int;
}

/// Decoded 8-byte SFDP parameter header. `id` is the 16-bit little-endian
/// parameter ID (ID LSB from byte 0, ID MSB from byte 1); `pointer` is the
/// 24-bit little-endian parameter table offset (bytes 4..6) and
/// `length_dwords` is the DWORD count (byte 7).
pub type FlashSfdpParamHeader = {
  id: Int;
  id_lsb: Int;
  id_msb: Int;
  major: Int;
  minor: Int;
  pointer: Int;
  length_dwords: Int;
}

/// One fast-read command setting. `opcode`/`mode_clocks`/`wait_states` are
/// decoded only when `supported`; otherwise all three are 0. The total
/// dummy clock count is mode_clocks + wait_states.
pub type FlashFastRead = {
  supported: Bool;
  opcode: Int;
  mode_clocks: Int;
  wait_states: Int;
}

/// Decoded Basic Flash Parameter Table (BFPT, JEDEC basic table 0xFF00).
/// `param` is the parameter header the table was read through; the erase
/// fields carry size 0 / opcode 0 for unsupported types; `page_size_exp` is
/// -1 when the table is too short to carry DWORD 11; `erase_bulk` is true
/// when a supported erase type covers the whole capacity.
pub type FlashBfpt = {
  param: FlashSfdpParamHeader;
  table_id: Int;
  density_bits: Int;
  capacity_bytes: Int;
  addr_mode: Int;
  supports_3_byte: Bool;
  supports_4_byte: Bool;
  supports_dtr: Bool;
  supports_1_1_2: Bool;
  supports_1_2_2: Bool;
  supports_1_1_4: Bool;
  supports_1_4_4: Bool;
  fr_1_1_2: FlashFastRead;
  fr_1_2_2: FlashFastRead;
  fr_1_1_4: FlashFastRead;
  fr_1_4_4: FlashFastRead;
  page_size_exp: Int;
  page_size_bytes: Int;
  erase1_size: Int;
  erase1_opcode: Int;
  erase2_size: Int;
  erase2_opcode: Int;
  erase3_size: Int;
  erase3_opcode: Int;
  erase4_size: Int;
  erase4_opcode: Int;
  erase_count: Int;
  erase_4k: Bool;
  erase_32k: Bool;
  erase_64k: Bool;
  erase_256k: Bool;
  erase_bulk: Bool;
}

/// Sector-map lookup result: `index = address / sector_size` and
/// `offset = address % sector_size` with truncating division.
pub type FlashSector = {
  sector_size: Int;
  capacity: Int;
  sector_count: Int;
  address: Int;
  index: Int;
  offset: Int;
}

/// Sector range: sector `index` covers [start_address, end_address) in bytes.
pub type FlashSectorRange = {
  sector_size: Int;
  capacity: Int;
  sector_count: Int;
  index: Int;
  start_address: Int;
  end_address: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, FlashError].
fn _ok_int(v: Int) -> Result[Int, FlashError] {
  return Ok(v);
}

// Err(offset, message) for Result[Int, FlashError].
fn _err_int(offset: Int, message: Str) -> Result[Int, FlashError] {
  let e = FlashError{ offset: offset; message: message; };
  return Err(e);
}

// Ok(v) for Result[FlashJedecId, FlashError].
fn _ok_jedec(v: FlashJedecId) -> Result[FlashJedecId, FlashError] {
  return Ok(v);
}

// Err(offset, message) for Result[FlashJedecId, FlashError].
fn _err_jedec(offset: Int, message: Str) -> Result[FlashJedecId, FlashError] {
  let e = FlashError{ offset: offset; message: message; };
  return Err(e);
}

// Ok(v) for Result[FlashStatus1, FlashError].
fn _ok_status(v: FlashStatus1) -> Result[FlashStatus1, FlashError] {
  return Ok(v);
}

// Err(offset, message) for Result[FlashStatus1, FlashError].
fn _err_status(offset: Int, message: Str) -> Result[FlashStatus1, FlashError] {
  let e = FlashError{ offset: offset; message: message; };
  return Err(e);
}

// Ok(v) for Result[FlashSfdpHeader, FlashError].
fn _ok_sfdp_header(v: FlashSfdpHeader) -> Result[FlashSfdpHeader, FlashError] {
  return Ok(v);
}

// Err(offset, message) for Result[FlashSfdpHeader, FlashError].
fn _err_sfdp_header(offset: Int, message: Str) -> Result[FlashSfdpHeader, FlashError] {
  let e = FlashError{ offset: offset; message: message; };
  return Err(e);
}

// Ok(v) for Result[FlashSfdpParamHeader, FlashError].
fn _ok_param_header(v: FlashSfdpParamHeader) -> Result[FlashSfdpParamHeader, FlashError] {
  return Ok(v);
}

// Err(offset, message) for Result[FlashSfdpParamHeader, FlashError].
fn _err_param_header(offset: Int, message: Str) -> Result[FlashSfdpParamHeader, FlashError] {
  let e = FlashError{ offset: offset; message: message; };
  return Err(e);
}

// Ok(v) for Result[FlashBfpt, FlashError].
fn _ok_bfpt(v: FlashBfpt) -> Result[FlashBfpt, FlashError] {
  return Ok(v);
}

// Err(offset, message) for Result[FlashBfpt, FlashError].
fn _err_bfpt(offset: Int, message: Str) -> Result[FlashBfpt, FlashError] {
  let e = FlashError{ offset: offset; message: message; };
  return Err(e);
}

// Ok(v) for Result[FlashSector, FlashError].
fn _ok_sector(v: FlashSector) -> Result[FlashSector, FlashError] {
  return Ok(v);
}

// Err(offset, message) for Result[FlashSector, FlashError].
fn _err_sector(offset: Int, message: Str) -> Result[FlashSector, FlashError] {
  let e = FlashError{ offset: offset; message: message; };
  return Err(e);
}

// Ok(v) for Result[FlashSectorRange, FlashError].
fn _ok_range(v: FlashSectorRange) -> Result[FlashSectorRange, FlashError] {
  return Ok(v);
}

// Err(offset, message) for Result[FlashSectorRange, FlashError].
fn _err_range(offset: Int, message: Str) -> Result[FlashSectorRange, FlashError] {
  let e = FlashError{ offset: offset; message: message; };
  return Err(e);
}

// --------------------------------------------------
//  Internal byte, bit and power helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// 2 raised to `k` for 0 <= k <= 62; callers guarantee the range.
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Little-endian 32-bit word at `pos` (explicit byte composition, BUG 18:
// shifts are avoided on values that can carry the sign bit).
fn _le32(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) + _byte(data, pos + 1) * 256 + _byte(data, pos + 2) * 65536 + _byte(data, pos + 3) * 16777216;
}

// Bit `k` of a non-negative `value` as 0 or 1; callers guarantee 0 <= k <= 62.
fn _bit(value: Int, k: Int) -> Int {
  return (value / _pow2(k)) % 2;
}

// Bit `k` of `value` as a Bool; false for a negative value or bit outside
// 0..62.
fn _bool_bit(value: Int, k: Int) -> Bool {
  if value < 0 {
    return false;
  }
  if k < 0 || k > 62 {
    return false;
  }
  return _bit(value, k) == 1;
}

// Decode one 16-bit erase-type half: size exponent byte [7:0], opcode [15:8].
fn _erase_exp(half: Int) -> Int {
  return half % 256;
}

// Opcode of one 16-bit erase-type half.
fn _erase_opcode(half: Int) -> Int {
  return (half / 256) % 256;
}

// One fast-read setting half: opcode [15:8], mode clocks [7:5], wait [4:0].
fn _fast_read(half: Int, supported: Bool) -> FlashFastRead {
  if !supported {
    let r0 = FlashFastRead{ supported: false; opcode: 0; mode_clocks: 0; wait_states: 0; };
    return r0;
  }
  let op = (half / 256) % 256;
  let mc = (half / 32) % 8;
  let ws = half % 32;
  let r1 = FlashFastRead{ supported: true; opcode: op; mode_clocks: mc; wait_states: ws; };
  return r1;
}

// --------------------------------------------------
//  Generic bit helper (public)
// --------------------------------------------------

/// True when bit `bit` of `value` is set. `value` must be non-negative;
/// `bit` must be in 0..62, otherwise the result is false.
/// Complexity: O(bit).
pub fn flash_bit_set(value: Int, bit: Int) -> Bool {
  return _bool_bit(value, bit);
}

/// 2 raised to `k`, or -1 when `k` is outside 0..62 (the byte count would
/// not fit a signed 64-bit integer).
/// Complexity: O(k).
pub fn flash_pow2(k: Int) -> Int {
  if k < 0 || k > 62 {
    return -1;
  }
  return _pow2(k);
}

// --------------------------------------------------
//  JEDEC manufacturer table (documented subset)
// --------------------------------------------------

/// Number of manufacturers in the documented subset (9).
/// Complexity: O(1).
pub fn flash_manufacturer_count() -> Int {
  return FLASH_MANUFACTURER_COUNT;
}

// Manufacturer ID at `index` in table order; -1 for an out-of-range index.
fn _manufacturer_id_at(index: Int) -> Int {
  if index == 0 {
    return 1;   // 0x01
  }
  if index == 1 {
    return 31;  // 0x1F
  }
  if index == 2 {
    return 32;  // 0x20
  }
  if index == 3 {
    return 191; // 0xBF
  }
  if index == 4 {
    return 194; // 0xC2
  }
  if index == 5 {
    return 239; // 0xEF
  }
  if index == 6 {
    return 98;  // 0x62
  }
  if index == 7 {
    return 140; // 0x8C
  }
  if index == 8 {
    return 94;  // 0x5E
  }
  return -1;
}

// Manufacturer name at `index` in table order; "unknown" when out of range.
fn _manufacturer_name_at(index: Int) -> Str {
  if index == 0 {
    return "Spansion/Cypress";
  }
  if index == 1 {
    return "Adesto";
  }
  if index == 2 {
    return "Micron";
  }
  if index == 3 {
    return "SST/Microchip";
  }
  if index == 4 {
    return "Macronix";
  }
  if index == 5 {
    return "Winbond";
  }
  if index == 6 {
    return "Sanyo";
  }
  if index == 7 {
    return "ESMT";
  }
  if index == 8 {
    return "Zbit";
  }
  return "unknown";
}

/// The documented manufacturer subset as a Vec[Int] of JEDEC manufacturer
/// bytes: [0x01, 0x1F, 0x20, 0xBF, 0xC2, 0xEF, 0x62, 0x8C, 0x5E].
/// Complexity: O(1).
pub fn flash_manufacturer_table() -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < FLASH_MANUFACTURER_COUNT {
    v.push(_manufacturer_id_at(i));
    i = i + 1;
  }
  return v;
}

/// Manufacturer ID at table `index` 0..8, or -1 when the index is outside
/// that range. Complexity: O(1).
pub fn flash_manufacturer_id_at(index: Int) -> Int {
  if index < 0 || index >= FLASH_MANUFACTURER_COUNT {
    return -1;
  }
  return _manufacturer_id_at(index);
}

/// Manufacturer name at table `index` 0..8, or "unknown" when the index is
/// outside that range. Complexity: O(1).
pub fn flash_manufacturer_name_at(index: Int) -> Str {
  if index < 0 || index >= FLASH_MANUFACTURER_COUNT {
    return "unknown";
  }
  return _manufacturer_name_at(index);
}

/// True when `id` is in the documented manufacturer subset.
/// Complexity: O(1).
pub fn flash_manufacturer_known(id: Int) -> Bool {
  let tab = flash_manufacturer_table();
  var i = 0;
  while i < tab.len() {
    let x: Int = tab[i];
    if x == id {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// Name of the manufacturer `id`: a name from the documented subset or
/// "unknown". Complexity: O(1).
pub fn flash_manufacturer_name(id: Int) -> Str {
  let tab = flash_manufacturer_table();
  var i = 0;
  while i < tab.len() {
    let x: Int = tab[i];
    if x == id {
      return _manufacturer_name_at(i);
    }
    i = i + 1;
  }
  return "unknown";
}

// --------------------------------------------------
//  Command table
// --------------------------------------------------

/// Number of pinned 25-series commands (18). Complexity: O(1).
pub fn flash_command_count() -> Int {
  return FLASH_COMMAND_COUNT;
}

/// The pinned command set as a Vec[Int], in this order: READ, FAST_READ,
/// FAST_READ_QUAD_IO, PAGE_PROGRAM, SECTOR_ERASE, BLOCK_ERASE,
/// WRITE_ENABLE, WRITE_DISABLE, READ_STATUS1, READ_STATUS2, WRITE_STATUS,
/// READ_ID, READ_SFDP, CHIP_ERASE, CHIP_ERASE_ALT, READ_4B, RESET_ENABLE,
/// RESET. Complexity: O(1).
pub fn flash_command_table() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(FLASH_CMD_READ);
  v.push(FLASH_CMD_FAST_READ);
  v.push(FLASH_CMD_FAST_READ_QUAD_IO);
  v.push(FLASH_CMD_PAGE_PROGRAM);
  v.push(FLASH_CMD_SECTOR_ERASE);
  v.push(FLASH_CMD_BLOCK_ERASE);
  v.push(FLASH_CMD_WRITE_ENABLE);
  v.push(FLASH_CMD_WRITE_DISABLE);
  v.push(FLASH_CMD_READ_STATUS1);
  v.push(FLASH_CMD_READ_STATUS2);
  v.push(FLASH_CMD_WRITE_STATUS);
  v.push(FLASH_CMD_READ_ID);
  v.push(FLASH_CMD_READ_SFDP);
  v.push(FLASH_CMD_CHIP_ERASE);
  v.push(FLASH_CMD_CHIP_ERASE_ALT);
  v.push(FLASH_CMD_READ_4B);
  v.push(FLASH_CMD_RESET_ENABLE);
  v.push(FLASH_CMD_RESET);
  return v;
}

/// Command opcode at table `index` 0..17, or -1 when the index is outside
/// that range. Complexity: O(1).
pub fn flash_command_code(index: Int) -> Int {
  let tab = flash_command_table();
  if index < 0 || index >= tab.len() {
    return -1;
  }
  let x: Int = tab[index];
  return x;
}

/// Stable name for a command opcode: "READ", "FAST_READ",
/// "FAST_READ_QUAD_IO", "PAGE_PROGRAM", "SECTOR_ERASE", "BLOCK_ERASE",
/// "WRITE_ENABLE", "WRITE_DISABLE", "READ_STATUS1", "READ_STATUS2",
/// "WRITE_STATUS", "READ_ID", "READ_SFDP", "CHIP_ERASE", "CHIP_ERASE_ALT",
/// "READ_4B", "RESET_ENABLE", "RESET", or "unknown".
/// Complexity: O(1).
pub fn flash_command_name(cmd: Int) -> Str {
  if cmd == FLASH_CMD_READ {
    return "READ";
  }
  if cmd == FLASH_CMD_FAST_READ {
    return "FAST_READ";
  }
  if cmd == FLASH_CMD_FAST_READ_QUAD_IO {
    return "FAST_READ_QUAD_IO";
  }
  if cmd == FLASH_CMD_PAGE_PROGRAM {
    return "PAGE_PROGRAM";
  }
  if cmd == FLASH_CMD_SECTOR_ERASE {
    return "SECTOR_ERASE";
  }
  if cmd == FLASH_CMD_BLOCK_ERASE {
    return "BLOCK_ERASE";
  }
  if cmd == FLASH_CMD_WRITE_ENABLE {
    return "WRITE_ENABLE";
  }
  if cmd == FLASH_CMD_WRITE_DISABLE {
    return "WRITE_DISABLE";
  }
  if cmd == FLASH_CMD_READ_STATUS1 {
    return "READ_STATUS1";
  }
  if cmd == FLASH_CMD_READ_STATUS2 {
    return "READ_STATUS2";
  }
  if cmd == FLASH_CMD_WRITE_STATUS {
    return "WRITE_STATUS";
  }
  if cmd == FLASH_CMD_READ_ID {
    return "READ_ID";
  }
  if cmd == FLASH_CMD_READ_SFDP {
    return "READ_SFDP";
  }
  if cmd == FLASH_CMD_CHIP_ERASE {
    return "CHIP_ERASE";
  }
  if cmd == FLASH_CMD_CHIP_ERASE_ALT {
    return "CHIP_ERASE_ALT";
  }
  if cmd == FLASH_CMD_READ_4B {
    return "READ_4B";
  }
  if cmd == FLASH_CMD_RESET_ENABLE {
    return "RESET_ENABLE";
  }
  if cmd == FLASH_CMD_RESET {
    return "RESET";
  }
  return "unknown";
}

/// Name of the command at table `index` 0..17, or "unknown" when the index
/// is outside that range. Complexity: O(1).
pub fn flash_command_name_at(index: Int) -> Str {
  return flash_command_name(flash_command_code(index));
}

// --------------------------------------------------
//  Status register 1
// --------------------------------------------------

/// Decode status register 1. Bit 0 WIP, bit 1 WEL, bits 2..4 BP0..BP2
/// (value `block_protect` = BP2*4 + BP1*2 + BP0), bit 5 TB, bit 6 SEC,
/// bit 7 SRP0.
///
/// Returns: Ok(FlashStatus1) for a byte 0..255.
/// Error case: Err(offset -1, "flash: status byte out of range") otherwise.
/// Complexity: O(1).
pub fn flash_sr1_parse(byte: Int) -> Result[FlashStatus1, FlashError] {
  if byte < 0 || byte > 255 {
    return _err_status(-1, "flash: status byte out of range");
  }
  let wip = _bool_bit(byte, FLASH_SR1_BIT_WIP);
  let wel = _bool_bit(byte, FLASH_SR1_BIT_WEL);
  let bp0 = _bool_bit(byte, FLASH_SR1_BIT_BP0);
  let bp1 = _bool_bit(byte, FLASH_SR1_BIT_BP1);
  let bp2 = _bool_bit(byte, FLASH_SR1_BIT_BP2);
  let tb = _bool_bit(byte, FLASH_SR1_BIT_TB);
  let sec = _bool_bit(byte, FLASH_SR1_BIT_SEC);
  let srp0 = _bool_bit(byte, FLASH_SR1_BIT_SRP0);
  let bp = _bit(byte, FLASH_SR1_BIT_BP0) * 4 + _bit(byte, FLASH_SR1_BIT_BP1) * 2 + _bit(byte, FLASH_SR1_BIT_BP2);
  let s = FlashStatus1{
    raw: byte;
    wip: wip;
    wel: wel;
    bp0: bp0;
    bp1: bp1;
    bp2: bp2;
    tb: tb;
    sec: sec;
    srp0: srp0;
    block_protect: bp;
  };
  return _ok_status(s);
}

/// True when the write-in-progress bit (bit 0) of `byte` is set; false for
/// a byte outside 0..255. Complexity: O(1).
pub fn flash_sr1_wip(byte: Int) -> Bool {
  if byte < 0 || byte > 255 {
    return false;
  }
  return _bool_bit(byte, FLASH_SR1_BIT_WIP);
}

/// True when the write-enable-latch bit (bit 1) of `byte` is set; false for
/// a byte outside 0..255. Complexity: O(1).
pub fn flash_sr1_wel(byte: Int) -> Bool {
  if byte < 0 || byte > 255 {
    return false;
  }
  return _bool_bit(byte, FLASH_SR1_BIT_WEL);
}

/// Block-protect value (BP2 BP1 BP0, 0..7) of the status byte; -1 for a
/// byte outside 0..255. Complexity: O(1).
pub fn flash_sr1_block_protect(byte: Int) -> Int {
  if byte < 0 || byte > 255 {
    return -1;
  }
  return _bit(byte, FLASH_SR1_BIT_BP0) * 4 + _bit(byte, FLASH_SR1_BIT_BP1) * 2 + _bit(byte, FLASH_SR1_BIT_BP2);
}

// --------------------------------------------------
//  JEDEC ID (RDID 0x9F response)
// --------------------------------------------------

/// Capacity byte N -> 2^N bytes.
///
/// Returns: Ok(2^N) for N in 8..32 (256 bytes .. 4 GiB).
/// Error case: Err(offset -1, "flash: invalid capacity code") otherwise.
/// Complexity: O(N).
pub fn flash_capacity_bytes(code: Int) -> Result[Int, FlashError] {
  if code < FLASH_JEDEC_MIN_CAPACITY_CODE || code > FLASH_JEDEC_MAX_CAPACITY_CODE {
    return _err_int(-1, "flash: invalid capacity code");
  }
  return _ok_int(_pow2(code));
}

/// Parse a 3-byte JEDEC ID (RDID 0x9F response): manufacturer byte, memory
/// type byte, capacity byte. Only the first three bytes are read.
///
/// Returns: Ok(FlashJedecId) for a buffer of at least 3 bytes and a capacity
/// code 8..32. An unknown manufacturer is NOT an error: the name is
/// "unknown".
/// Error case: Err(id.len(), "flash: jedec id truncated") for fewer than
/// 3 bytes; Err(2, "flash: invalid capacity code") when the capacity byte is
/// outside 8..32. Complexity: O(1).
pub fn flash_jedec_id_parse(id: &Vec[UInt8]) -> Result[FlashJedecId, FlashError] {
  if id.len() < 3 {
    return _err_jedec(id.len(), "flash: jedec id truncated");
  }
  let mid = _byte(id, 0);
  let mtype = _byte(id, 1);
  let code = _byte(id, 2);
  if code < FLASH_JEDEC_MIN_CAPACITY_CODE || code > FLASH_JEDEC_MAX_CAPACITY_CODE {
    return _err_jedec(2, "flash: invalid capacity code");
  }
  let name = flash_manufacturer_name(mid);
  let size = _pow2(code);
  let j = FlashJedecId{
    manufacturer_id: mid;
    manufacturer_name: name;
    memory_type: mtype;
    capacity_code: code;
    capacity_bytes: size;
  };
  return _ok_jedec(j);
}

// --------------------------------------------------
//  SFDP header and parameter headers
// --------------------------------------------------

/// True when `id` is the JEDEC basic flash parameter table ID (0xFF00).
/// Complexity: O(1).
pub fn flash_sfdp_id_is_basic(id: Int) -> Bool {
  return id == FLASH_SFDP_BASIC_ID;
}

/// True when `id` is the "not supported"/unused marker (0xFFFF).
/// Complexity: O(1).
pub fn flash_sfdp_id_is_unused(id: Int) -> Bool {
  return id == FLASH_SFDP_UNUSED_ID;
}

/// True when `id` is the sector map parameter table ID (0xFF81).
/// Complexity: O(1).
pub fn flash_sfdp_id_is_sector_map(id: Int) -> Bool {
  return id == FLASH_SFDP_SECTOR_MAP_ID;
}

/// Parse the 8-byte SFDP header: signature bytes 53 46 44 50 at offsets
/// 0..3 (little-endian word 0x50444653), minor revision at 4, major
/// revision at 5, NPH (0-based parameter header count) at 6.
///
/// Returns: Ok(FlashSfdpHeader) when the signature matches and the revision
/// is supported (major exactly 1, minor 0..9).
/// Error case: Err(data.len(), "flash: sfdp header truncated") for fewer
/// than 8 bytes; Err(0, "flash: bad sfdp signature"); Err(5, "flash: sfdp
/// major revision unsupported"); Err(4, "flash: sfdp minor revision
/// unsupported"). Complexity: O(1).
pub fn flash_sfdp_parse_header(data: &Vec[UInt8]) -> Result[FlashSfdpHeader, FlashError] {
  if data.len() < 8 {
    return _err_sfdp_header(data.len(), "flash: sfdp header truncated");
  }
  if _le32(data, 0) != FLASH_SFDP_SIGNATURE {
    return _err_sfdp_header(0, "flash: bad sfdp signature");
  }
  let major = _byte(data, 5);
  let minor = _byte(data, 4);
  if major != FLASH_SFDP_MAJOR {
    return _err_sfdp_header(5, "flash: sfdp major revision unsupported");
  }
  if minor > FLASH_SFDP_MAX_MINOR {
    return _err_sfdp_header(4, "flash: sfdp minor revision unsupported");
  }
  let nph = _byte(data, 6);
  let h = FlashSfdpHeader{
    major: major;
    minor: minor;
    nph: nph;
    parameter_header_count: nph + 1;
  };
  return _ok_sfdp_header(h);
}

/// Parse parameter header `index` (0-based) at offset 8 + 8*index: ID LSB
/// (byte 0), ID MSB (byte 1) composed as a 16-bit little-endian ID, table
/// major (byte 2), table minor (byte 3), 24-bit little-endian table pointer
/// (bytes 4..6) and length in DWORDs (byte 7).
///
/// Returns: Ok(FlashSfdpParamHeader).
/// Error case: the flash_sfdp_parse_header catalog, plus Err(-1, "flash:
/// sfdp parameter index out of range") when `index` is outside
/// 0..parameter_header_count-1, and Err(data.len(), "flash: sfdp parameter
/// header truncated") when the buffer ends inside the entry.
/// Complexity: O(1).
pub fn flash_sfdp_parse_param_header(data: &Vec[UInt8], index: Int) -> Result[FlashSfdpParamHeader, FlashError] {
  let hr = flash_sfdp_parse_header(data);
  if !hr.is_ok {
    let he: FlashError = hr.error;
    let hoff: Int = he.offset;
    let hmsg: Str = he.message;
    return _err_param_header(hoff, hmsg);
  }
  let h: FlashSfdpHeader = hr.value;
  let count: Int = h.parameter_header_count;
  if index < 0 || index >= count {
    return _err_param_header(-1, "flash: sfdp parameter index out of range");
  }
  let start = 8 + index * 8;
  if start + 8 > data.len() {
    return _err_param_header(data.len(), "flash: sfdp parameter header truncated");
  }
  let id_lsb = _byte(data, start);
  let id_msb = _byte(data, start + 1);
  let major = _byte(data, start + 2);
  let minor = _byte(data, start + 3);
  let pointer = _byte(data, start + 4) + _byte(data, start + 5) * 256 + _byte(data, start + 6) * 65536;
  let len_dw = _byte(data, start + 7);
  let p = FlashSfdpParamHeader{
    id: id_lsb + id_msb * 256;
    id_lsb: id_lsb;
    id_msb: id_msb;
    major: major;
    minor: minor;
    pointer: pointer;
    length_dwords: len_dw;
  };
  return _ok_param_header(p);
}

/// Select the JEDEC basic flash parameter table entry (ID 0xFF00) from the
/// parameter header table. Entries are scanned in order; an entry whose
/// table major is not 1 is rejected, and among the remaining basic entries
/// the one with the highest minor revision (then the largest length) wins.
///
/// Returns: Ok(FlashSfdpParamHeader) for the selected basic table entry.
/// Error case: the header/parameter-header catalog, plus Err(8 + 8*i + 2,
/// "flash: sfdp basic table major revision unsupported") for a basic entry
/// with a bad major, and Err(-1, "flash: sfdp basic table missing") when no
/// basic entry exists. Complexity: O(parameter_header_count).
pub fn flash_sfdp_basic_param(data: &Vec[UInt8]) -> Result[FlashSfdpParamHeader, FlashError] {
  let hr = flash_sfdp_parse_header(data);
  if !hr.is_ok {
    let he: FlashError = hr.error;
    let hoff: Int = he.offset;
    let hmsg: Str = he.message;
    return _err_param_header(hoff, hmsg);
  }
  let h: FlashSfdpHeader = hr.value;
  let count: Int = h.parameter_header_count;
  var best_index = -1;
  var best_minor = -1;
  var best_len = -1;
  var i = 0;
  while i < count {
    let pr = flash_sfdp_parse_param_header(data, i);
    if !pr.is_ok {
      let pe: FlashError = pr.error;
      let poff: Int = pe.offset;
      let pmsg: Str = pe.message;
      return _err_param_header(poff, pmsg);
    }
    let ph: FlashSfdpParamHeader = pr.value;
    let pid: Int = ph.id;
    if pid == FLASH_SFDP_BASIC_ID {
      let pmaj: Int = ph.major;
      if pmaj != FLASH_SFDP_MAJOR {
        return _err_param_header(8 + i * 8 + 2, "flash: sfdp basic table major revision unsupported");
      }
      let pmin: Int = ph.minor;
      let plen: Int = ph.length_dwords;
      if best_index < 0 || pmin > best_minor || (pmin == best_minor && plen > best_len) {
        best_index = i;
        best_minor = pmin;
        best_len = plen;
      }
    }
    i = i + 1;
  }
  if best_index < 0 {
    return _err_param_header(-1, "flash: sfdp basic table missing");
  }
  return flash_sfdp_parse_param_header(data, best_index);
}

// --------------------------------------------------
//  Basic Flash Parameter Table (BFPT)
// --------------------------------------------------

/// Decode the Basic Flash Parameter Table selected by
/// flash_sfdp_basic_param.
///
/// DWORD map (offsets relative to the table pointer; lengths in DWORDs):
///   * DWORD 1 (0x00): bits [18:17] address mode (0 = 3-byte only,
///     1 = 3 or 4, 2 = 4-byte only, 3 = reserved), bit 19 DTR, bit 16 fast
///     read 1-1-2, bit 20 fast read 1-2-2, bit 22 fast read 1-1-4, bit 21
///     fast read 1-4-4;
///   * DWORD 2 (0x04): flash memory density in bits; bit 31 set means
///     2^[30:0] bits, bit 31 clear means [30:0] + 1 bits;
///   * DWORD 3 (0x08): bits [15:0] 1-4-4 settings, [31:16] 1-1-4 settings;
///   * DWORD 4 (0x0C): bits [15:0] 1-1-2 settings, [31:16] 1-2-2 settings;
///     each setting half is opcode [15:8], mode clocks [7:5], wait [4:0];
///   * DWORD 8 (0x1C): erase types 1 and 2 (size exponent [7:0], opcode
///     [15:8] per half), DWORD 9 (0x20): erase types 3 and 4;
///   * DWORD 11 (0x28): page size exponent [7:4].
///
/// Returns: Ok(FlashBfpt) for a table of at least 9 DWORDs fully inside the
/// buffer. Page size is only decoded when the table has at least 11 DWORDs
/// (otherwise page_size_exp is -1 and page_size_bytes is 0); erase type
/// size 0 means unsupported (size 0, opcode 0).
/// Error case: the header/parameter-header catalog, plus Err(pointer,
/// "flash: sfdp basic table too short") for fewer than 9 DWORDs, Err(pointer,
/// "flash: sfdp table out of bounds") when pointer + 4*length exceeds the
/// buffer, Err(pointer + 4, "flash: sfdp density exponent out of range"),
/// Err(pointer + 28 or pointer + 32, "flash: sfdp erase size exponent out of
/// range") and Err(pointer + 40, "flash: sfdp page size exponent out of
/// range"). Complexity: O(1).
pub fn flash_sfdp_bfpt_parse(data: &Vec[UInt8]) -> Result[FlashBfpt, FlashError] {
  let pr = flash_sfdp_basic_param(data);
  if !pr.is_ok {
    let pe: FlashError = pr.error;
    let poff: Int = pe.offset;
    let pmsg: Str = pe.message;
    return _err_bfpt(poff, pmsg);
  }
  let ph: FlashSfdpParamHeader = pr.value;
  let ptr: Int = ph.pointer;
  let len_dw: Int = ph.length_dwords;
  if len_dw < 9 {
    return _err_bfpt(ptr, "flash: sfdp basic table too short");
  }
  if ptr + len_dw * 4 > data.len() {
    return _err_bfpt(ptr, "flash: sfdp table out of bounds");
  }
  let d1 = _le32(data, ptr);
  let d2 = _le32(data, ptr + 4);
  let d3 = _le32(data, ptr + 8);
  let d4 = _le32(data, ptr + 12);

  let addr_mode = (d1 / 131072) % 4;
  let addr_3 = addr_mode == 0 || addr_mode == 1;
  let addr_4 = addr_mode == 1 || addr_mode == 2;
  let dtr = _bool_bit(d1, 19);
  let s112 = _bool_bit(d1, 16);
  let s122 = _bool_bit(d1, 20);
  let s114 = _bool_bit(d1, 22);
  let s144 = _bool_bit(d1, 21);

  var density_bits = 0;
  if _bool_bit(d2, 31) {
    let e = d2 % 2147483648;
    if e > 62 {
      return _err_bfpt(ptr + 4, "flash: sfdp density exponent out of range");
    }
    density_bits = _pow2(e);
  } else {
    density_bits = d2 + 1;
  }
  let capacity = density_bits / 8;

  let h112 = d4 % 65536;
  let h122 = (d4 / 65536) % 65536;
  let h114 = (d3 / 65536) % 65536;
  let h144 = d3 % 65536;
  let fr112 = _fast_read(h112, s112);
  let fr122 = _fast_read(h122, s122);
  let fr114 = _fast_read(h114, s114);
  let fr144 = _fast_read(h144, s144);

  let d8 = _le32(data, ptr + 28);
  let d9 = _le32(data, ptr + 32);
  let e1 = d8 % 65536;
  let e2 = (d8 / 65536) % 65536;
  let e3 = d9 % 65536;
  let e4 = (d9 / 65536) % 65536;
  let x1 = _erase_exp(e1);
  let x2 = _erase_exp(e2);
  let x3 = _erase_exp(e3);
  let x4 = _erase_exp(e4);
  if x1 > 40 || x2 > 40 {
    return _err_bfpt(ptr + 28, "flash: sfdp erase size exponent out of range");
  }
  if x3 > 40 || x4 > 40 {
    return _err_bfpt(ptr + 32, "flash: sfdp erase size exponent out of range");
  }
  var s1 = 0;
  var s2 = 0;
  var s3 = 0;
  var s4 = 0;
  var o1 = 0;
  var o2 = 0;
  var o3 = 0;
  var o4 = 0;
  if x1 > 0 {
    s1 = _pow2(x1);
    o1 = _erase_opcode(e1);
  }
  if x2 > 0 {
    s2 = _pow2(x2);
    o2 = _erase_opcode(e2);
  }
  if x3 > 0 {
    s3 = _pow2(x3);
    o3 = _erase_opcode(e3);
  }
  if x4 > 0 {
    s4 = _pow2(x4);
    o4 = _erase_opcode(e4);
  }
  var erase_count = 0;
  if s1 > 0 {
    erase_count = erase_count + 1;
  }
  if s2 > 0 {
    erase_count = erase_count + 1;
  }
  if s3 > 0 {
    erase_count = erase_count + 1;
  }
  if s4 > 0 {
    erase_count = erase_count + 1;
  }
  let f4k = s1 == 4096 || s2 == 4096 || s3 == 4096 || s4 == 4096;
  let f32k = s1 == 32768 || s2 == 32768 || s3 == 32768 || s4 == 32768;
  let f64k = s1 == 65536 || s2 == 65536 || s3 == 65536 || s4 == 65536;
  let f256k = s1 == 262144 || s2 == 262144 || s3 == 262144 || s4 == 262144;
  var bulk = false;
  if capacity > 0 {
    if s1 >= capacity || s2 >= capacity || s3 >= capacity || s4 >= capacity {
      bulk = true;
    }
  }

  var page_exp = -1;
  var page_bytes = 0;
  if len_dw >= 11 {
    let d11 = _le32(data, ptr + 40);
    let pe = (d11 / 16) % 16;
    if pe > 20 {
      return _err_bfpt(ptr + 40, "flash: sfdp page size exponent out of range");
    }
    if pe > 0 {
      page_exp = pe;
      page_bytes = _pow2(pe);
    }
  }

  let tid: Int = ph.id;
  let b = FlashBfpt{
    param: ph;
    table_id: tid;
    density_bits: density_bits;
    capacity_bytes: capacity;
    addr_mode: addr_mode;
    supports_3_byte: addr_3;
    supports_4_byte: addr_4;
    supports_dtr: dtr;
    supports_1_1_2: s112;
    supports_1_2_2: s122;
    supports_1_1_4: s114;
    supports_1_4_4: s144;
    fr_1_1_2: fr112;
    fr_1_2_2: fr122;
    fr_1_1_4: fr114;
    fr_1_4_4: fr144;
    page_size_exp: page_exp;
    page_size_bytes: page_bytes;
    erase1_size: s1;
    erase1_opcode: o1;
    erase2_size: s2;
    erase2_opcode: o2;
    erase3_size: s3;
    erase3_opcode: o3;
    erase4_size: s4;
    erase4_opcode: o4;
    erase_count: erase_count;
    erase_4k: f4k;
    erase_32k: f32k;
    erase_64k: f64k;
    erase_256k: f256k;
    erase_bulk: bulk;
  };
  return _ok_bfpt(b);
}

/// Capacity in bits decoded from the BFPT (0 when the table carried 0).
/// Complexity: O(1).
pub fn flash_bfpt_density_bits(b: &FlashBfpt) -> Int {
  return b.density_bits;
}

/// Capacity in bytes: density_bits / 8 (truncating division).
/// Complexity: O(1).
pub fn flash_bfpt_capacity_bytes(b: &FlashBfpt) -> Int {
  return b.capacity_bytes;
}

/// True when the BFPT advertises 4-byte addressing support (address mode
/// "3 or 4" or "4 only"). Complexity: O(1).
pub fn flash_bfpt_supports_4byte(b: &FlashBfpt) -> Bool {
  return b.supports_4_byte;
}

/// True when the BFPT advertises 3-byte addressing support (address mode
/// "3 only" or "3 or 4"). Complexity: O(1).
pub fn flash_bfpt_supports_3byte(b: &FlashBfpt) -> Bool {
  return b.supports_3_byte;
}

/// Page size in bytes decoded from BFPT DWORD 11; 0 when the table is too
/// short to carry it or the exponent field is 0.
/// Complexity: O(1).
pub fn flash_bfpt_page_size_bytes(b: &FlashBfpt) -> Int {
  return b.page_size_bytes;
}

/// True when the BFPT carried DWORD 11 (page size present).
/// Complexity: O(1).
pub fn flash_bfpt_page_size_known(b: &FlashBfpt) -> Bool {
  return b.page_size_exp >= 0;
}

/// Fast-read setting for a mode index: 0 = 1-1-2, 1 = 1-2-2, 2 = 1-1-4,
/// 3 = 1-4-4; any other index yields an unsupported setting.
/// Complexity: O(1).
pub fn flash_bfpt_fast_read(b: &FlashBfpt, mode: Int) -> FlashFastRead {
  if mode == 0 {
    let r0: FlashFastRead = b.fr_1_1_2;
    return r0;
  }
  if mode == 1 {
    let r1: FlashFastRead = b.fr_1_2_2;
    return r1;
  }
  if mode == 2 {
    let r2: FlashFastRead = b.fr_1_1_4;
    return r2;
  }
  if mode == 3 {
    let r3: FlashFastRead = b.fr_1_4_4;
    return r3;
  }
  let z = FlashFastRead{ supported: false; opcode: 0; mode_clocks: 0; wait_states: 0; };
  return z;
}

/// Mode index for a fast-read command shape: 0 = 1-1-2, 1 = 1-2-2,
/// 2 = 1-1-4, 3 = 1-4-4, -1 for any other shape.
/// Complexity: O(1).
pub fn flash_fast_read_mode(inst: Int, addr: Int, data: Int) -> Int {
  if inst == 1 && addr == 1 && data == 2 {
    return 0;
  }
  if inst == 1 && addr == 2 && data == 2 {
    return 1;
  }
  if inst == 1 && addr == 1 && data == 4 {
    return 2;
  }
  if inst == 1 && addr == 4 && data == 4 {
    return 3;
  }
  return -1;
}

/// Total dummy clock count (mode clocks + wait states) for fast-read `mode`
/// 0..3; -1 when the mode index is invalid or the command is unsupported.
/// Complexity: O(1).
pub fn flash_bfpt_fast_read_clocks(b: &FlashBfpt, mode: Int) -> Int {
  let fr = flash_bfpt_fast_read(b, mode);
  let sup: Bool = fr.supported;
  if !sup {
    return -1;
  }
  let mc: Int = fr.mode_clocks;
  let ws: Int = fr.wait_states;
  return mc + ws;
}

/// Erase size in bytes at erase-type `index` 0..3 in BFPT order (DWORD 8
/// low half = 0, DWORD 8 high half = 1, DWORD 9 low half = 2, DWORD 9 high
/// half = 3; 0 when unsupported); -1 when the index is outside 0..3.
/// Complexity: O(1).
pub fn flash_bfpt_erase_size(b: &FlashBfpt, index: Int) -> Int {
  if index == 0 {
    let v0: Int = b.erase1_size;
    return v0;
  }
  if index == 1 {
    let v1: Int = b.erase2_size;
    return v1;
  }
  if index == 2 {
    let v2: Int = b.erase3_size;
    return v2;
  }
  if index == 3 {
    let v3: Int = b.erase4_size;
    return v3;
  }
  return -1;
}

/// Erase opcode at erase-type `index` 0..3 (0 when unsupported); -1 when
/// the index is outside 0..3. Complexity: O(1).
pub fn flash_bfpt_erase_opcode(b: &FlashBfpt, index: Int) -> Int {
  if index == 0 {
    let v0: Int = b.erase1_opcode;
    return v0;
  }
  if index == 1 {
    let v1: Int = b.erase2_opcode;
    return v1;
  }
  if index == 2 {
    let v2: Int = b.erase3_opcode;
    return v2;
  }
  if index == 3 {
    let v3: Int = b.erase4_opcode;
    return v3;
  }
  return -1;
}

/// Number of supported erase types (0..4). Complexity: O(1).
pub fn flash_bfpt_erase_type_count(b: &FlashBfpt) -> Int {
  return b.erase_count;
}

/// Smallest supported erase size in bytes, or 0 when no erase type is
/// supported. Complexity: O(1).
pub fn flash_bfpt_smallest_erase_size(b: &FlashBfpt) -> Int {
  var best = 0;
  let s1: Int = b.erase1_size;
  let s2: Int = b.erase2_size;
  let s3: Int = b.erase3_size;
  let s4: Int = b.erase4_size;
  if s1 > 0 {
    best = s1;
  }
  if s2 > 0 && (best == 0 || s2 < best) {
    best = s2;
  }
  if s3 > 0 && (best == 0 || s3 < best) {
    best = s3;
  }
  if s4 > 0 && (best == 0 || s4 < best) {
    best = s4;
  }
  return best;
}

// --------------------------------------------------
//  Sector map
// --------------------------------------------------

/// Number of whole sectors needed for `capacity` bytes at `sector_size`
/// (ceiling division via q = capacity / sector_size, r = capacity %
/// sector_size, q + 1 when r > 0); -1 when `sector_size` or `capacity` is
/// not positive. Complexity: O(1).
pub fn flash_sector_count(sector_size: Int, capacity: Int) -> Int {
  if sector_size <= 0 || capacity <= 0 {
    return -1;
  }
  let q = capacity / sector_size;
  let r = capacity % sector_size;
  if r > 0 {
    return q + 1;
  }
  return q;
}

// Validate the sector geometry shared by the sector-map helpers; 0 when the
// geometry is usable, otherwise the stable error message.
fn _geometry_error(sector_size: Int, capacity: Int) -> Str {
  if sector_size <= 0 {
    return "flash: invalid sector size";
  }
  if capacity <= 0 {
    return "flash: invalid capacity";
  }
  if capacity % sector_size != 0 {
    return "flash: capacity not sector aligned";
  }
  return "";
}

/// Map a byte address to its sector: index = address / sector_size,
/// offset = address % sector_size (truncating division).
///
/// Boundary rules: sector_size > 0; capacity > 0; capacity must be a whole
/// number of sectors; 0 <= address < capacity.
/// Returns: Ok(FlashSector) inside the array.
/// Error case: Err(-1, "flash: invalid sector size"), Err(-1, "flash:
/// invalid capacity"), Err(-1, "flash: capacity not sector aligned"),
/// Err(-1, "flash: negative address"), or Err(address, "flash: address out
/// of range") carrying the offending address in `offset`.
/// Complexity: O(1).
pub fn flash_sector_map(sector_size: Int, capacity: Int, address: Int) -> Result[FlashSector, FlashError] {
  let geo = _geometry_error(sector_size, capacity);
  if geo.len() > 0 {
    return _err_sector(-1, geo);
  }
  if address < 0 {
    return _err_sector(-1, "flash: negative address");
  }
  if address >= capacity {
    return _err_sector(address, "flash: address out of range");
  }
  let count = capacity / sector_size;
  let idx = address / sector_size;
  let off = address % sector_size;
  let s = FlashSector{
    sector_size: sector_size;
    capacity: capacity;
    sector_count: count;
    address: address;
    index: idx;
    offset: off;
  };
  return _ok_sector(s);
}

/// Range of sector `index`: [start_address, end_address) with
/// start_address = index * sector_size and end_address = start_address +
/// sector_size.
///
/// Boundary rules: sector_size > 0; capacity > 0; capacity must be a whole
/// number of sectors; 0 <= index < sector_count.
/// Returns: Ok(FlashSectorRange) inside the array.
/// Error case: the geometry catalog with offset -1, or Err(-1, "flash:
/// sector index out of range"). Complexity: O(1).
pub fn flash_sector_range(sector_size: Int, capacity: Int, index: Int) -> Result[FlashSectorRange, FlashError] {
  let geo = _geometry_error(sector_size, capacity);
  if geo.len() > 0 {
    return _err_range(-1, geo);
  }
  let count = capacity / sector_size;
  if index < 0 || index >= count {
    return _err_range(-1, "flash: sector index out of range");
  }
  let start = index * sector_size;
  let stop = start + sector_size;
  let r = FlashSectorRange{
    sector_size: sector_size;
    capacity: capacity;
    sector_count: count;
    index: index;
    start_address: start;
    end_address: stop;
  };
  return _ok_range(r);
}
