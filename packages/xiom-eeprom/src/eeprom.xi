// XIOM -- xiom.eeprom: serial EEPROM device protocol codecs (24Cxx I2C, 93Cxx Microwire)
// Port task: greenfield pure-XIOM port (no FFI) of the documented subset of
// two serial EEPROM device protocol families. Codec only: frames and bit
// streams in memory, no bus transactions, no timing and no device state.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// 24Cxx (I2C) -- full tables in SPEC.md:
//   * control byte = 1010 A2A1A0 R/W, i.e. 0xA0 + pins * 2 + read;
//   * density table 24C01..24C2048 (1..2048 Kbit): bits, bytes, word-address
//     width (1 byte for 24C01..24C16, 2 bytes for 24C32..24C2048) and page
//     size (8/16/32/64/128/256 bytes);
//   * word-address field encoding (1 or 2 bytes, big-endian);
//   * page-write boundary math: page start, next page start, bytes remaining
//     in the page, the address a page-write byte lands on (the write pointer
//     wraps inside the page) and the contiguous span before the next
//     boundary or the device end;
//   * current-address read semantics: the internal address pointer wraps at
//     the device end (wrap_address / seq_address).
//
// 93Cxx (Microwire):
//   * opcode patterns: READ "10" (2 bits; the encoder emits the mandatory
//     start bit before it, so the wire prefix is "110"), WRITE "101",
//     ERASE "111", EWEN "10011", EWDS "10000", ERAL "10010", WRAL "10001";
//   * command + address (+ data for WRITE and WRAL) encoded MSB first into a
//     byte buffer and decoded back into opcode, byte address, data and bit
//     count;
//   * address-field width per density and org (8/16) for 93C46..93C106
//     (64..64K bit);
//   * on org 16, READ/WRITE/ERASE byte addresses must be word-aligned;
//     WRAL requires address 0 (the only opcode with that rule); EWEN, EWDS
//     and ERAL addresses are don't-care and are emitted as zero bits;
//   * READ responses are plain MSB-first data frames (org bits).
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no self methods, no lambdas, no Vec[fn] dispatch;
//   * no Vec[StructType]; parallel Vec fields are not needed here because no
//     table is ever returned as a vector;
//   * Ok/Err construction is confined to the tiny leaf helpers `_ok_*` /
//     `_err_*` below (constructing Results directly inside other functions
//     miscompiles);
//   * Str values are compared through xiom.string.compare.str_compare (BUG
//     17: `==` on a Str read from a Vec[Str] lowers to a pointer compare);
//   * every byte read from a Vec[UInt8] is widened with
//     `(x as Int) & 0xFF` before entering Int arithmetic;
//   * `&struct.field` is never passed as a `&Vec[UInt8]` parameter (that
//     yields an empty vector): fields are bound to typed locals first;
//   * bit extraction uses division by powers of two, never a shift on a
//     value that could carry the sign bit.

module xiom.eeprom

use xiom.convert;
use xiom.string.compare;

// --------------------------------------------------
//  93Cxx opcode constants (documented bit patterns)
// --------------------------------------------------

/// READ opcode pattern "10"; the encoder prefixes the mandatory start bit,
/// so the wire prefix is "110".
pub const EE93_READ: Int = 2;
/// WRITE opcode pattern "101" (start bit included).
pub const EE93_WRITE: Int = 5;
/// ERASE opcode pattern "111" (start bit included).
pub const EE93_ERASE: Int = 7;
/// EWEN opcode pattern "10011" (start bit included).
pub const EE93_EWEN: Int = 19;
/// EWDS opcode pattern "10000" (start bit included).
pub const EE93_EWDS: Int = 16;
/// ERAL opcode pattern "10010" (start bit included).
pub const EE93_ERAL: Int = 18;
/// WRAL opcode pattern "10001" (start bit included).
pub const EE93_WRAL: Int = 17;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// One density row of the canonical EEPROM table.
///
/// `name` is the canonical part name ("24C01".."24C2048", "93C46".."93C106");
/// `bits` the memory size in bits; `bytes` the size in bytes (bits / 8, the
/// number of addressable storage bytes for either org); `addr_bytes` the
/// width of the address field in bytes (24Cxx word address bytes, or
/// ceil(address bits / 8) for 93Cxx); `page_size` the page-write size in
/// bytes (0 when the family has no page concept, i.e. 93Cxx); `org` the
/// organization (8 or 16; always 8 for 24Cxx).
pub type EepromDensity = {
  name: Str;
  bits: Int;
  bytes: Int;
  addr_bytes: Int;
  page_size: Int;
  org: Int;
}

/// A 93Cxx command to encode: the canonical density name, the org strap
/// (8 or 16), one of the EE93_* opcode constants, a byte address and the
/// data word for WRITE/WRAL (ignored for the other opcodes).
pub type Ee93Command = {
  density: Str;
  org: Int;
  opcode: Int;
  address: Int;
  data: Int;
}

/// A decoded 93Cxx command: the opcode constant, the byte address (0 for
/// EWEN/EWDS/ERAL/WRAL, whose address field is don't-care), the data word
/// (0 unless WRITE or WRAL) and the number of wire bits the command spans.
pub type Ee93Decoded = {
  opcode: Int;
  address: Int;
  data: Int;
  bits: Int;
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

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
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

// Ok(v) for Result[EepromDensity, Str].
fn _ok_density(v: EepromDensity) -> Result[EepromDensity, Str] {
  return Ok(v);
}

// Err(m) for Result[EepromDensity, Str].
fn _err_density(m: Str) -> Result[EepromDensity, Str] {
  return Err(m);
}

// Ok(v) for Result[Ee93Decoded, Str].
fn _ok_decoded(v: Ee93Decoded) -> Result[Ee93Decoded, Str] {
  return Ok(v);
}

// Err(m) for Result[Ee93Decoded, Str].
fn _err_decoded(m: Str) -> Result[Ee93Decoded, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal arithmetic
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// 2^k for 0 <= k <= 30, computed by repeated multiplication (no shift).
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Ceiling of a / b for a >= 0, b > 0: truncating division plus a remainder
// correction (never (a + b - 1) / b).
fn _ceil_div(a: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  if r > 0 {
    return q + 1;
  }
  return q;
}

// Base-2 logarithm of an exact power of two v >= 1; 0 for v <= 1.
fn _log2i(v: Int) -> Int {
  var x = v;
  var k = 0;
  while x > 1 {
    x = x / 2;
    k = k + 1;
  }
  return k;
}

// --------------------------------------------------
//  24Cxx (I2C): control byte and densities
// --------------------------------------------------

/// Control byte for a 24Cxx device: 1010 A2A1A0 R/W = 0xA0 + pins * 2 +
/// (1 for a read, 0 for a write).
///
/// Err("eeprom.24cxx: address pins N out of range 0..7") when the A2..A0
/// pin strapping `addr_pins` is outside 0..7.
/// Complexity: O(1).
pub fn ee24_control_byte(addr_pins: Int, read_op: Bool) -> Result[Int, Str] {
  if addr_pins < 0 || addr_pins > 7 {
    return _err_int("eeprom.24cxx: address pins " + convert.int_to_string(addr_pins) + " out of range 0..7");
  }
  var rw = 0;
  if read_op {
    rw = 1;
  }
  return _ok_int(160 + addr_pins * 2 + rw);
}

/// Write-direction control byte (R/W = 0) for the given pin strapping; same
/// validation and error as ee24_control_byte. Complexity: O(1).
pub fn ee24_device_address_write(addr_pins: Int) -> Result[Int, Str] {
  return ee24_control_byte(addr_pins, false);
}

/// Read-direction control byte (R/W = 1) for the given pin strapping; same
/// validation and error as ee24_control_byte. Complexity: O(1).
pub fn ee24_device_address_read(addr_pins: Int) -> Result[Int, Str] {
  return ee24_control_byte(addr_pins, true);
}

/// Density row of a 24Cxx part: 24C01 (1 Kbit, 128 B, page 8), 24C02 (2 Kbit,
/// 256 B, page 8), 24C04 (4 Kbit, 512 B, page 16), 24C08 (8 Kbit, 1024 B,
/// page 16), 24C16 (16 Kbit, 2048 B, page 16), 24C32 (32 Kbit, 4096 B,
/// page 32), 24C64 (64 Kbit, 8192 B, page 32), 24C128 (128 Kbit, 16384 B,
/// page 64), 24C256 (256 Kbit, 32768 B, page 64), 24C512 (512 Kbit, 65536 B,
/// page 128), 24C1024 (1 Mbit, 131072 B, page 256) and 24C2048 (2 Mbit,
/// 262144 B, page 256). Address width is 1 byte for 24C01..24C16 and 2 bytes
/// for 24C32..24C2048.
///
/// Err("eeprom.24cxx: unknown density \"<name>\"") when the name is not one
/// of the twelve canonical names.
/// Complexity: O(1) (twelve str_compare calls).
pub fn ee24_density(name: Str) -> Result[EepromDensity, Str] {
  if compare.str_compare(name, "24C01") == 0 {
    return _ok_density(EepromDensity{ name: "24C01"; bits: 1024; bytes: 128; addr_bytes: 1; page_size: 8; org: 8; });
  }
  if compare.str_compare(name, "24C02") == 0 {
    return _ok_density(EepromDensity{ name: "24C02"; bits: 2048; bytes: 256; addr_bytes: 1; page_size: 8; org: 8; });
  }
  if compare.str_compare(name, "24C04") == 0 {
    return _ok_density(EepromDensity{ name: "24C04"; bits: 4096; bytes: 512; addr_bytes: 1; page_size: 16; org: 8; });
  }
  if compare.str_compare(name, "24C08") == 0 {
    return _ok_density(EepromDensity{ name: "24C08"; bits: 8192; bytes: 1024; addr_bytes: 1; page_size: 16; org: 8; });
  }
  if compare.str_compare(name, "24C16") == 0 {
    return _ok_density(EepromDensity{ name: "24C16"; bits: 16384; bytes: 2048; addr_bytes: 1; page_size: 16; org: 8; });
  }
  if compare.str_compare(name, "24C32") == 0 {
    return _ok_density(EepromDensity{ name: "24C32"; bits: 32768; bytes: 4096; addr_bytes: 2; page_size: 32; org: 8; });
  }
  if compare.str_compare(name, "24C64") == 0 {
    return _ok_density(EepromDensity{ name: "24C64"; bits: 65536; bytes: 8192; addr_bytes: 2; page_size: 32; org: 8; });
  }
  if compare.str_compare(name, "24C128") == 0 {
    return _ok_density(EepromDensity{ name: "24C128"; bits: 131072; bytes: 16384; addr_bytes: 2; page_size: 64; org: 8; });
  }
  if compare.str_compare(name, "24C256") == 0 {
    return _ok_density(EepromDensity{ name: "24C256"; bits: 262144; bytes: 32768; addr_bytes: 2; page_size: 64; org: 8; });
  }
  if compare.str_compare(name, "24C512") == 0 {
    return _ok_density(EepromDensity{ name: "24C512"; bits: 524288; bytes: 65536; addr_bytes: 2; page_size: 128; org: 8; });
  }
  if compare.str_compare(name, "24C1024") == 0 {
    return _ok_density(EepromDensity{ name: "24C1024"; bits: 1048576; bytes: 131072; addr_bytes: 2; page_size: 256; org: 8; });
  }
  if compare.str_compare(name, "24C2048") == 0 {
    return _ok_density(EepromDensity{ name: "24C2048"; bits: 2097152; bytes: 262144; addr_bytes: 2; page_size: 256; org: 8; });
  }
  return _err_density("eeprom.24cxx: unknown density \"" + name + "\"");
}

/// Page size of a 24Cxx density, or -1 for an unknown name.
/// Complexity: O(1).
pub fn ee24_page_size(name: Str) -> Int {
  let r = ee24_density(name);
  if !r.is_ok {
    return -1;
  }
  let d: EepromDensity = r.value;
  return d.page_size;
}

/// Word-address width in bytes of a 24Cxx density (1 or 2), or -1 for an
/// unknown name. Complexity: O(1).
pub fn ee24_addr_bytes(name: Str) -> Int {
  let r = ee24_density(name);
  if !r.is_ok {
    return -1;
  }
  let d: EepromDensity = r.value;
  return d.addr_bytes;
}

/// Size in bytes of a 24Cxx density, or -1 for an unknown name.
/// Complexity: O(1).
pub fn ee24_bytes(name: Str) -> Int {
  let r = ee24_density(name);
  if !r.is_ok {
    return -1;
  }
  let d: EepromDensity = r.value;
  return d.bytes;
}

/// Size in bits of a 24Cxx density, or -1 for an unknown name.
/// Complexity: O(1).
pub fn ee24_bits(name: Str) -> Int {
  let r = ee24_density(name);
  if !r.is_ok {
    return -1;
  }
  let d: EepromDensity = r.value;
  return d.bits;
}

// --------------------------------------------------
//  24Cxx (I2C): word address field
// --------------------------------------------------

/// Encode the 24Cxx word-address field: `addr` as 1 or 2 big-endian bytes
/// (most significant byte first for 2 bytes).
///
/// Err("eeprom.24cxx: invalid address width N") when `addr_bytes` is not 1
/// or 2; Err("eeprom.24cxx: word address N does not fit in M address
/// byte(s)") when `addr` is negative or exceeds 2^(8*M) - 1.
/// Complexity: O(1).
pub fn ee24_word_address(addr: Int, addr_bytes: Int) -> Result[Vec[UInt8], Str] {
  if addr_bytes != 1 && addr_bytes != 2 {
    return _err_bytes("eeprom.24cxx: invalid address width " + convert.int_to_string(addr_bytes));
  }
  let maxv = _pow2(addr_bytes * 8) - 1;
  if addr < 0 || addr > maxv {
    return _err_bytes("eeprom.24cxx: word address " + convert.int_to_string(addr) + " does not fit in " + convert.int_to_string(addr_bytes) + " address byte(s)");
  }
  var out = Vec[UInt8].new();
  if addr_bytes == 2 {
    out.push(((addr / 256) % 256) as UInt8);
  }
  out.push((addr % 256) as UInt8);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  24Cxx (I2C): page-write and device-end math
// --------------------------------------------------

/// First byte address of the page containing `addr`: addr - (addr mod
/// page_size). A page_size <= 0 returns 0 instead of dividing by zero.
/// Complexity: O(1).
pub fn ee24_page_start(addr: Int, page_size: Int) -> Int {
  if page_size <= 0 {
    return 0;
  }
  return (addr / page_size) * page_size;
}

/// First byte address of the page after the one containing `addr`:
/// page_start + page_size (equal to the device size on the last page).
/// A page_size <= 0 returns 0.
/// Complexity: O(1).
pub fn ee24_next_page_start(addr: Int, page_size: Int) -> Int {
  if page_size <= 0 {
    return 0;
  }
  return ee24_page_start(addr, page_size) + page_size;
}

/// Bytes remaining in the page containing `addr`, from `addr` up to (not
/// including) the page boundary: page_size - (addr mod page_size). A
/// page_size <= 0 returns 0.
/// Complexity: O(1).
pub fn ee24_page_remaining(addr: Int, page_size: Int) -> Int {
  if page_size <= 0 {
    return 0;
  }
  return page_size - (addr % page_size);
}

/// Address the `offset`-th byte of a page write started at `addr` lands on.
/// A page write keeps its write pointer inside the starting page, so the
/// target wraps to the page start after the page boundary:
/// page_start + ((addr - page_start + offset) mod page_size). A page_size
/// <= 0 returns 0.
/// Complexity: O(1).
pub fn ee24_write_target(addr: Int, offset: Int, page_size: Int) -> Int {
  if page_size <= 0 {
    return 0;
  }
  let start = ee24_page_start(addr, page_size);
  return start + ((addr - start + offset) % page_size);
}

/// Wrap an address into 0..device_bytes-1: the internal address pointer of a
/// current-address read (or a sequential read) restarts at 0 after the last
/// byte. A device_bytes <= 0 returns 0.
/// Complexity: O(1).
pub fn ee24_wrap_address(addr: Int, device_bytes: Int) -> Int {
  if device_bytes <= 0 {
    return 0;
  }
  var a = addr % device_bytes;
  if a < 0 {
    a = a + device_bytes;
  }
  return a;
}

/// Byte address reached after `offset` sequential accesses from `addr` with
/// device-end wrap (current-address read): wrap_address(addr + offset).
/// Complexity: O(1).
pub fn ee24_seq_address(addr: Int, offset: Int, device_bytes: Int) -> Int {
  return ee24_wrap_address(addr + offset, device_bytes);
}

/// Number of bytes a page write started at `addr` can move in one burst:
/// the smaller of the bytes left in the page and the bytes left before the
/// device end. An out-of-range `addr` wraps first (device-end rule). A
/// non-positive page_size or device_bytes returns 0.
/// Complexity: O(1).
pub fn ee24_write_span(addr: Int, page_size: Int, device_bytes: Int) -> Int {
  if page_size <= 0 || device_bytes <= 0 {
    return 0;
  }
  let a = ee24_wrap_address(addr, device_bytes);
  var rem_page = ee24_page_remaining(a, page_size);
  let rem_dev = device_bytes - a;
  if rem_page > rem_dev {
    rem_page = rem_dev;
  }
  return rem_page;
}

// --------------------------------------------------
//  24Cxx (I2C): validation
// --------------------------------------------------

/// Validate a byte address against a device size.
///
/// Err("eeprom.24cxx: invalid device size N") when device_bytes <= 0;
/// Err("eeprom.24cxx: byte address N out of range 0..M") when addr is
/// outside 0..device_bytes-1.
/// Complexity: O(1).
pub fn ee24_validate_address(addr: Int, device_bytes: Int) -> Result[Unit, Str] {
  if device_bytes <= 0 {
    return _err_unit("eeprom.24cxx: invalid device size " + convert.int_to_string(device_bytes));
  }
  if addr < 0 || addr >= device_bytes {
    return _err_unit("eeprom.24cxx: byte address " + convert.int_to_string(addr) + " out of range 0.." + convert.int_to_string(device_bytes - 1));
  }
  return _ok_unit();
}

/// Validate a page write: 1..page_size bytes starting at `addr` that do not
/// cross the page boundary (the write pointer would wrap inside the page
/// and corrupt earlier bytes, so a crossing write is rejected).
///
/// Err("eeprom.24cxx: invalid page size N") when page_size <= 0;
/// Err("eeprom.24cxx: negative byte address N") when addr < 0;
/// Err("eeprom.24cxx: page write count N must be at least 1") when count < 1;
/// Err("eeprom.24cxx: page write of N bytes at address A crosses the page
/// boundary at byte offset R (page size P)") when the write crosses the
/// boundary, where R is the number of bytes that fit before it
/// (page_remaining).
/// Complexity: O(1).
pub fn ee24_validate_page_write(addr: Int, count: Int, page_size: Int) -> Result[Unit, Str] {
  if page_size <= 0 {
    return _err_unit("eeprom.24cxx: invalid page size " + convert.int_to_string(page_size));
  }
  if addr < 0 {
    return _err_unit("eeprom.24cxx: negative byte address " + convert.int_to_string(addr));
  }
  if count < 1 {
    return _err_unit("eeprom.24cxx: page write count " + convert.int_to_string(count) + " must be at least 1");
  }
  let rem = ee24_page_remaining(addr, page_size);
  if count > rem {
    return _err_unit("eeprom.24cxx: page write of " + convert.int_to_string(count) + " bytes at address " + convert.int_to_string(addr) + " crosses the page boundary at byte offset " + convert.int_to_string(rem) + " (page size " + convert.int_to_string(page_size) + ")");
  }
  return _ok_unit();
}

// --------------------------------------------------
//  93Cxx (Microwire): densities and opcodes
// --------------------------------------------------

// Memory size in bits of a 93Cxx density, or -1 for an unknown name:
// 93C46 = 1024, 93C56 = 2048, 93C66 = 4096, 93C76 = 8192, 93C86 = 16384,
// 93C106 = 65536.
fn ee93_bits(name: Str) -> Int {
  if compare.str_compare(name, "93C46") == 0 {
    return 1024;
  }
  if compare.str_compare(name, "93C56") == 0 {
    return 2048;
  }
  if compare.str_compare(name, "93C66") == 0 {
    return 4096;
  }
  if compare.str_compare(name, "93C76") == 0 {
    return 8192;
  }
  if compare.str_compare(name, "93C86") == 0 {
    return 16384;
  }
  if compare.str_compare(name, "93C106") == 0 {
    return 65536;
  }
  return -1;
}

/// Organization size of one 93Cxx storage cell in bytes: 2 for org 16, 1 for
/// any other org (callers validate org first). Complexity: O(1).
fn _ee93_org_bytes(org: Int) -> Int {
  if org == 16 {
    return 2;
  }
  return 1;
}

/// Address-field width in bits of a 93Cxx density for the given org strap:
/// 93C46 7/6, 93C56 8/7, 93C66 9/8, 93C76 10/9, 93C86 11/10 and 93C106
/// 13/12 for org 8/16 (the field addresses words on org 16). Returns -1 when
/// org is not 8 or 16 or the name is unknown.
/// Complexity: O(1).
pub fn ee93_address_bits(name: Str, org: Int) -> Int {
  if org != 8 && org != 16 {
    return -1;
  }
  let b = ee93_bits(name);
  if b < 0 {
    return -1;
  }
  return _log2i((b / 8) / _ee93_org_bytes(org));
}

/// Number of storage bytes (bits / 8) of a 93Cxx density, or -1 when org is
/// not 8 or 16 or the name is unknown. The byte count is org-independent:
/// the org only changes how many bytes one address cell covers.
/// Complexity: O(1).
pub fn ee93_bytes(name: Str, org: Int) -> Int {
  if org != 8 && org != 16 {
    return -1;
  }
  let b = ee93_bits(name);
  if b < 0 {
    return -1;
  }
  return b / 8;
}

/// Number of addressable words of a 93Cxx density for the given org strap:
/// 2^address_bits. Returns -1 when org is not 8 or 16 or the name is
/// unknown.
/// Complexity: O(1).
pub fn ee93_word_count(name: Str, org: Int) -> Int {
  let ab = ee93_address_bits(name, org);
  if ab < 0 {
    return -1;
  }
  return _pow2(ab);
}

/// Density row of a 93Cxx part for an org strap (8 or 16). `bytes` is the
/// org-independent size (bits / 8), `addr_bytes` is ceil(address bits / 8)
/// and `page_size` is 0 (the family has no page-write concept).
///
/// Err("eeprom.93cxx: org N is not 8 or 16") when org is not 8 or 16;
/// Err("eeprom.93cxx: unknown density \"<name>\" for org N") when the name
/// is not one of the six canonical names.
/// Complexity: O(1).
pub fn ee93_density(name: Str, org: Int) -> Result[EepromDensity, Str] {
  if org != 8 && org != 16 {
    return _err_density("eeprom.93cxx: org " + convert.int_to_string(org) + " is not 8 or 16");
  }
  let b = ee93_bits(name);
  if b < 0 {
    return _err_density("eeprom.93cxx: unknown density \"" + name + "\" for org " + convert.int_to_string(org));
  }
  let ab = ee93_address_bits(name, org);
  return _ok_density(EepromDensity{ name: name; bits: b; bytes: b / 8; addr_bytes: _ceil_div(ab, 8); page_size: 0; org: org; });
}

/// Human-readable opcode name: "READ", "WRITE", "ERASE", "EWEN", "EWDS",
/// "ERAL", "WRAL" or "unknown". Complexity: O(1).
pub fn ee93_opcode_name(opcode: Int) -> Str {
  if opcode == EE93_READ {
    return "READ";
  }
  if opcode == EE93_WRITE {
    return "WRITE";
  }
  if opcode == EE93_ERASE {
    return "ERASE";
  }
  if opcode == EE93_EWEN {
    return "EWEN";
  }
  if opcode == EE93_EWDS {
    return "EWDS";
  }
  if opcode == EE93_ERAL {
    return "ERAL";
  }
  if opcode == EE93_WRAL {
    return "WRAL";
  }
  return "unknown";
}

// Number of wire bits the opcode pattern itself occupies: READ 2 ("10"),
// WRITE and ERASE 3, EWEN/EWDS/ERAL/WRAL 5. Returns 0 for an unknown opcode.
fn _ee93_op_bits(opcode: Int) -> Int {
  if opcode == EE93_READ {
    return 2;
  }
  if opcode == EE93_WRITE || opcode == EE93_ERASE {
    return 3;
  }
  if opcode == EE93_EWEN || opcode == EE93_EWDS || opcode == EE93_ERAL || opcode == EE93_WRAL {
    return 5;
  }
  return 0;
}

// True when the opcode carries a data word after the address field (WRITE
// and WRAL).
fn _ee93_has_data(opcode: Int) -> Bool {
  return opcode == EE93_WRITE || opcode == EE93_WRAL;
}

// --------------------------------------------------
//  93Cxx (Microwire): bit-stream helpers
// --------------------------------------------------

// Bit at absolute bit position `pos` of `data`, MSB first (bit 0 is the
// high bit of byte 0). Callers guarantee the bounds.
fn _bit_at(data: &Vec[UInt8], pos: Int) -> Int {
  let b: Int = _byte(data, pos / 8);
  let shift = 7 - (pos % 8);
  return (b / _pow2(shift)) % 2;
}

// Value of `nbits` bits starting at absolute bit position `start`, MSB
// first. Callers guarantee the bits are in bounds.
fn _read_bits(data: &Vec[UInt8], start: Int, nbits: Int) -> Int {
  var v = 0;
  var i = 0;
  while i < nbits {
    v = v * 2 + _bit_at(data, start + i);
    i = i + 1;
  }
  return v;
}

// Append the `nbits` low bits of `value`, most significant first, to `bits`.
fn _emit_bits(bits: &mut Vec[Int], value: Int, nbits: Int) {
  var k = nbits - 1;
  while k >= 0 {
    bits.push((value / _pow2(k)) % 2);
    k = k - 1;
  }
}

// Pack a MSB-first bit vector into bytes, zero-padding the final byte.
fn _pack_bits(bits: &Vec[Int]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = bits.len();
  var i = 0;
  while i < n {
    var b = 0;
    var j = 0;
    while j < 8 {
      b = b * 2;
      if i + j < n {
        let bit: Int = bits[i + j];
        if bit != 0 {
          b = b + 1;
        }
      }
      j = j + 1;
    }
    out.push(b as UInt8);
    i = i + 8;
  }
  return out;
}

// --------------------------------------------------
//  93Cxx (Microwire): encode
// --------------------------------------------------

/// Encode a 93Cxx command as an MSB-first bit stream packed into bytes
/// (the final byte is zero-padded).
///
/// Wire layout: opcode pattern + address field + data field (WRITE and WRAL
/// only, org bits). READ's 2-bit pattern "10" is preceded by the mandatory
/// start bit, giving the wire prefix "110". The address field is the byte
/// address divided by the org cell size (2 on org 16), so on org 16 the
/// emitted field is the word address. EWEN/EWDS/ERAL addresses are
/// don't-care and are emitted as zero bits.
///
/// Validation order and errors:
///   1. org not 8 or 16, or unknown density -> the ee93_density errors;
///   2. opcode is not an EE93_* constant -> Err("eeprom.93cxx: invalid
///      opcode N");
///   3. WRAL with address != 0 -> Err("eeprom.93cxx: WRAL address must be
///      0");
///   4. READ/WRITE/ERASE address outside 0..bytes-1 ->
///      Err("eeprom.93cxx: byte address N out of range 0..M for <name> org
///      O");
///   5. org 16 and the address is odd -> Err("eeprom.93cxx: byte address N
///      is not aligned for org 16");
///   6. WRITE/WRAL data outside 0..2^org - 1 -> Err("eeprom.93cxx: data N
///      out of range 0..M for org O").
/// Complexity: O(address bits + org).
pub fn ee93_encode(cmd: &Ee93Command) -> Result[Vec[UInt8], Str] {
  let name: Str = cmd.density;
  let org = cmd.org;
  let dr = ee93_density(name, org);
  if !dr.is_ok {
    return _err_bytes(dr.error);
  }
  let d: EepromDensity = dr.value;
  let op = cmd.opcode;
  let opb = _ee93_op_bits(op);
  if opb == 0 {
    return _err_bytes("eeprom.93cxx: invalid opcode " + convert.int_to_string(op));
  }
  let ab = ee93_address_bits(name, org);
  let addr = cmd.address;
  if op == EE93_WRAL {
    if addr != 0 {
      return _err_bytes("eeprom.93cxx: WRAL address must be 0");
    }
  } elif op == EE93_READ || op == EE93_WRITE || op == EE93_ERASE {
    if addr < 0 || addr >= d.bytes {
      return _err_bytes("eeprom.93cxx: byte address " + convert.int_to_string(addr) + " out of range 0.." + convert.int_to_string(d.bytes - 1) + " for " + name + " org " + convert.int_to_string(org));
    }
    if org == 16 && addr % 2 != 0 {
      return _err_bytes("eeprom.93cxx: byte address " + convert.int_to_string(addr) + " is not aligned for org 16");
    }
  }
  let data = cmd.data;
  if _ee93_has_data(op) {
    let maxd = _pow2(org) - 1;
    if data < 0 || data > maxd {
      return _err_bytes("eeprom.93cxx: data " + convert.int_to_string(data) + " out of range 0.." + convert.int_to_string(maxd) + " for org " + convert.int_to_string(org));
    }
  }
  var bits = Vec[Int].new();
  if op == EE93_READ {
    _emit_bits(&mut bits, 1, 1);
  }
  _emit_bits(&mut bits, op, opb);
  var raw = 0;
  if op == EE93_READ || op == EE93_WRITE || op == EE93_ERASE {
    raw = addr / _ee93_org_bytes(org);
  }
  _emit_bits(&mut bits, raw, ab);
  if _ee93_has_data(op) {
    _emit_bits(&mut bits, data, org);
  }
  return _ok_bytes(_pack_bits(&bits));
}

// --------------------------------------------------
//  93Cxx (Microwire): decode
// --------------------------------------------------

/// Decode a 93Cxx command bit stream (MSB first) into its opcode, byte
/// address, data word and bit count. Bytes beyond the command are ignored.
///
/// The 3-bit wire prefixes are matched first: 110 READ, 101 WRITE, 111
/// ERASE; a 100 prefix selects the 5-bit special commands 10011 EWEN, 10000
/// EWDS, 10010 ERAL, 10001 WRAL. The address field is read next, then the
/// data field for WRITE and WRAL.
///
/// Validation order and errors:
///   1. org not 8 or 16, or unknown density -> the ee93_density errors;
///   2. fewer than 3 bits -> Err("eeprom.93cxx: truncated command: need 3
///      bits, have N") (or 5 bits when the 100 prefix needs the second
///      half);
///   3. an unrecognized prefix -> Err("eeprom.93cxx: unknown opcode prefix
///      P at bit 0");
///   4. fewer bits than the full command -> Err("eeprom.93cxx: truncated
///      command: need N bits, have M");
///   5. WRAL with a nonzero address field -> Err("eeprom.93cxx: WRAL
///      address field must be 0").
/// The decoded address is 0 for EWEN/EWDS/ERAL/WRAL (don't-care fields);
/// READ/WRITE/ERASE addresses are byte addresses (raw field * org cell).
/// Complexity: O(command bits).
pub fn ee93_decode(data: &Vec[UInt8], density: Str, org: Int) -> Result[Ee93Decoded, Str] {
  let dr = ee93_density(density, org);
  if !dr.is_ok {
    return _err_decoded(dr.error);
  }
  let have = data.len() * 8;
  if have < 3 {
    return _err_decoded("eeprom.93cxx: truncated command: need 3 bits, have " + convert.int_to_string(have));
  }
  let p3 = _read_bits(data, 0, 3);
  var op = -1;
  var prefix_bits = 3;
  if p3 == 6 {
    op = EE93_READ;
  } elif p3 == 5 {
    op = EE93_WRITE;
  } elif p3 == 7 {
    op = EE93_ERASE;
  } elif p3 == 4 {
    if have < 5 {
      return _err_decoded("eeprom.93cxx: truncated command: need 5 bits, have " + convert.int_to_string(have));
    }
    let p5 = _read_bits(data, 0, 5);
    prefix_bits = 5;
    if p5 == 19 {
      op = EE93_EWEN;
    } elif p5 == 16 {
      op = EE93_EWDS;
    } elif p5 == 18 {
      op = EE93_ERAL;
    } elif p5 == 17 {
      op = EE93_WRAL;
    }
  }
  if op < 0 {
    let bad = _read_bits(data, 0, prefix_bits);
    return _err_decoded("eeprom.93cxx: unknown opcode prefix " + convert.int_to_string(bad) + " at bit 0");
  }
  let ab = ee93_address_bits(density, org);
  var need = prefix_bits + ab;
  if _ee93_has_data(op) {
    need = need + org;
  }
  if have < need {
    return _err_decoded("eeprom.93cxx: truncated command: need " + convert.int_to_string(need) + " bits, have " + convert.int_to_string(have));
  }
  let raw = _read_bits(data, prefix_bits, ab);
  if op == EE93_WRAL {
    if raw != 0 {
      return _err_decoded("eeprom.93cxx: WRAL address field must be 0");
    }
  }
  var addr = 0;
  if op == EE93_READ || op == EE93_WRITE || op == EE93_ERASE {
    addr = raw * _ee93_org_bytes(org);
  }
  var dv = 0;
  if _ee93_has_data(op) {
    dv = _read_bits(data, prefix_bits + ab, org);
  }
  return _ok_decoded(Ee93Decoded{ opcode: op; address: addr; data: dv; bits: need; });
}

// --------------------------------------------------
//  93Cxx (Microwire): READ responses
// --------------------------------------------------

/// Encode a 93Cxx READ response: `value` as org bits, MSB first, in
/// ceil(org / 8) bytes (1 byte for org 8, 2 bytes big-endian for org 16).
///
/// Err("eeprom.93cxx: org N is not 8 or 16") when org is not 8 or 16;
/// Err("eeprom.93cxx: read response value N out of range 0..M for org O")
/// when value is negative or exceeds 2^org - 1.
/// Complexity: O(1).
pub fn ee93_encode_read_response(value: Int, org: Int) -> Result[Vec[UInt8], Str] {
  if org != 8 && org != 16 {
    return _err_bytes("eeprom.93cxx: org " + convert.int_to_string(org) + " is not 8 or 16");
  }
  let maxd = _pow2(org) - 1;
  if value < 0 || value > maxd {
    return _err_bytes("eeprom.93cxx: read response value " + convert.int_to_string(value) + " out of range 0.." + convert.int_to_string(maxd) + " for org " + convert.int_to_string(org));
  }
  var out = Vec[UInt8].new();
  if org == 16 {
    out.push(((value / 256) % 256) as UInt8);
  }
  out.push((value % 256) as UInt8);
  return _ok_bytes(out);
}

/// Decode a 93Cxx READ response: org bits, MSB first, from the start of
/// `data` (bytes beyond org / 8 are ignored).
///
/// Err("eeprom.93cxx: org N is not 8 or 16") when org is not 8 or 16;
/// Err("eeprom.93cxx: read response needs N byte(s), have M") when `data`
/// is shorter than org / 8 bytes.
/// Complexity: O(1).
pub fn ee93_decode_read_response(data: &Vec[UInt8], org: Int) -> Result[Int, Str] {
  if org != 8 && org != 16 {
    return _err_int("eeprom.93cxx: org " + convert.int_to_string(org) + " is not 8 or 16");
  }
  let need = org / 8;
  if data.len() < need {
    return _err_int("eeprom.93cxx: read response needs " + convert.int_to_string(need) + " byte(s), have " + convert.int_to_string(data.len()));
  }
  var v = 0;
  var i = 0;
  while i < need {
    v = v * 256 + _byte(data, i);
    i = i + 1;
  }
  return _ok_int(v);
}
