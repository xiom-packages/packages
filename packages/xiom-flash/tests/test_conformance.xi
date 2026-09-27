// XIOM -- xiom.flash conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pins the documented API against the xiom.flash SPEC.md: the 18 pinned
// 25-series command opcodes and their names, the documented manufacturer
// subset, the JEDEC ID (RDID 0x9F) decode with capacity codes 8..32 and its
// error offsets, status register 1 bit decode (WIP, WEL, BP0..BP2, TB, SEC,
// SRP0), the SFDP header and parameter header byte layouts (little-endian
// IDs and 24-bit pointers), the Basic Flash Parameter Table decode (density
// in both encodings, address modes, the four fast-read commands and their
// clocks, page size, erase types and derived flags), deterministic malformed
// input errors (bad signature, bad revisions, short tables, out-of-bounds
// pointers) and the sector-map boundary rules.
//
// All buffers are synthetic, built inside the tests from pinned hex images
// (xiom.encoding.hex) or byte pushes. Str values go through
// xiom.string.compare.str_compare (BUG 17: `==` on a Str read from a
// Vec[Str] lowers to a pointer comparison).

module flash_tests
use xiom.io; use xiom.test;
use xiom.flash;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string (empty on malformed input, so the test
// then fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

// SFDP header: signature + minor + major + NPH + unused.
fn sfdp_head(minor: Int, major: Int, nph: Int) -> Vec[UInt8] {
  var v = hb("53464450");
  v.push((minor % 256) as UInt8);
  v.push((major % 256) as UInt8);
  v.push((nph % 256) as UInt8);
  v.push(255 as UInt8);
  return v;
}

// 8-byte parameter header: ID LSB/MSB, major, minor, 24-bit LE pointer,
// length in DWORDs.
fn param_head(id_lsb: Int, id_msb: Int, major: Int, minor: Int, ptr: Int, len_dw: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push((id_lsb % 256) as UInt8);
  v.push((id_msb % 256) as UInt8);
  v.push((major % 256) as UInt8);
  v.push((minor % 256) as UInt8);
  v.push((ptr % 256) as UInt8);
  v.push(((ptr / 256) % 256) as UInt8);
  v.push(((ptr / 65536) % 256) as UInt8);
  v.push((len_dw % 256) as UInt8);
  return v;
}

// Assemble a 112-byte SFDP image: header, one basic parameter header
// (pointer 0x30, 16 DWORDs), 32 bytes of padding, then the BFPT DWORDs.
fn sfdp_with(d1_4: Vec[UInt8], d5_8: Vec[UInt8], d9_12: Vec[UInt8]) -> Vec[UInt8] {
  let a = sfdp_head(6, 1, 0);
  let ph = param_head(0, 255, 1, 6, 48, 16);
  let r1 = cat(a, ph);
  let r2 = cat(r1, zeros(32));
  let r3 = cat(r2, d1_4);
  let r4 = cat(r3, d5_8);
  let r5 = cat(r4, d9_12);
  let r6 = cat(r5, zeros(16));
  return r6;
}

// Canonical synthetic fixture: 16 MiB Winbond-like BFPT.
//   D1 = 0x00730000: addr mode 1 (3 or 4), 1-1-2/1-2-2/1-1-4/1-4-4 all on
//   D2 = 0x07FFFFFF: density = value + 1 = 2^27 bits = 16 MiB
//   D3 = 0x6B44EB45: 1-4-4 opcode 0xEB / 2 mode clocks / 5 wait; 1-1-4
//                    0x6B / 2 / 4
//   D4 = 0xBB463B08: 1-1-2 opcode 0x3B / 0 / 8; 1-2-2 0xBB / 2 / 6
//   D8 = 0x520F200C: 4 KiB erase 0x20, 32 KiB erase 0x52
//   D9 = 0x0000D810: 64 KiB erase 0xD8, fourth type unsupported
//   D11 = 0x00000080: page size 2^8 = 256 bytes
fn sfdp_winbond() -> Vec[UInt8] {
  return sfdp_with(hb("00007300FFFFFF0745EB446B083B46BB"), hb("0000000000000000000000000C200F52"), hb("10D80000000000008000000000000000"));
}

// Density as 2^27 bits via the bit-31 exponent encoding.
fn sfdp_density_exp() -> Vec[UInt8] {
  return sfdp_with(hb("000073001B00008045EB446B083B46BB"), hb("0000000000000000000000000C200F52"), hb("10D80000000000008000000000000000"));
}

// Density exponent 200: rejected as out of range.
fn sfdp_density_exp_bad() -> Vec[UInt8] {
  return sfdp_with(hb("00007300C800008045EB446B083B46BB"), hb("0000000000000000000000000C200F52"), hb("10D80000000000008000000000000000"));
}

// D1 = 0x00690000: DTR on, 1-2-2 unsupported, address mode 0 (3-byte only).
fn sfdp_d1_alt() -> Vec[UInt8] {
  return sfdp_with(hb("00006900FFFFFF0745EB446B083B46BB"), hb("0000000000000000000000000C200F52"), hb("10D80000000000008000000000000000"));
}

// D9 = 0xD818D812: 256 KiB erase 0xD8 and a 16 MiB (whole chip) type.
fn sfdp_erase_bulk() -> Vec[UInt8] {
  return sfdp_with(hb("00007300FFFFFF0745EB446B083B46BB"), hb("0000000000000000000000000C200F52"), hb("12D818D8000000008000000000000000"));
}

// D8 low half size exponent 41: rejected as out of range.
fn sfdp_erase_bad() -> Vec[UInt8] {
  return sfdp_with(hb("00007300FFFFFF0745EB446B083B46BB"), hb("00000000000000000000000029200F52"), hb("10D80000000000008000000000000000"));
}

// Parameter header claims 8 DWORDs: shorter than the 9-DWORD minimum.
fn sfdp_short() -> Vec[UInt8] {
  let a = sfdp_head(6, 1, 0);
  let ph = param_head(0, 255, 1, 6, 48, 8);
  let r1 = cat(a, ph);
  let r2 = cat(r1, zeros(64));
  return r2;
}

// Parameter header points at 0x40 with 16 DWORDs; the 96-byte buffer cannot
// hold it (64 + 64 > 96).
fn sfdp_ptr_bad() -> Vec[UInt8] {
  let a = sfdp_head(6, 1, 0);
  let ph = param_head(0, 255, 1, 6, 64, 16);
  let r1 = cat(a, ph);
  let r2 = cat(r1, zeros(32));
  let r3 = cat(r2, hb("00007300FFFFFF0745EB446B083B46BB"));
  let r4 = cat(r3, hb("0000000000000000000000000C200F52"));
  let r5 = cat(r4, hb("10D80000000000008000000000000000"));
  return r5;
}

// Parameter header claims 9 DWORDs: valid table, but no page-size DWORD.
fn sfdp_page_absent() -> Vec[UInt8] {
  let a = sfdp_head(6, 1, 0);
  let ph = param_head(0, 255, 1, 6, 48, 9);
  let r1 = cat(a, ph);
  let r2 = cat(r1, zeros(32));
  let r3 = cat(r2, hb("00007300FFFFFF0745EB446B083B46BB"));
  let r4 = cat(r3, hb("0000000000000000000000000C200F52"));
  let r5 = cat(r4, hb("10D80000000000008000000000000000"));
  return r5;
}

// Two parameter headers: sector map 0xFF81 first, basic table 0xFF00 second
// with pointer 0x130 (LE24 byte composition: 0x30 + 0x01 * 256).
fn sfdp_two_headers() -> Vec[UInt8] {
  let a = sfdp_head(6, 1, 1);
  let h0 = param_head(129, 255, 1, 0, 32, 4);
  let h1 = param_head(0, 255, 1, 6, 304, 16);
  let r1 = cat(a, h0);
  let r2 = cat(r1, h1);
  return r2;
}

// Only a sector map header: no basic table.
fn sfdp_no_basic() -> Vec[UInt8] {
  let a = sfdp_head(6, 1, 0);
  let ph = param_head(129, 255, 1, 0, 32, 4);
  return cat(a, ph);
}

// Basic table header with major revision 2: rejected at offset 10.
fn sfdp_basic_major_bad() -> Vec[UInt8] {
  let a = sfdp_head(6, 1, 0);
  let ph = param_head(0, 255, 2, 6, 48, 16);
  return cat(a, ph);
}

fn sfdp_bad_sig() -> Vec[UInt8] {
  let a = hb("00464450060100FF");
  let ph = param_head(0, 255, 1, 6, 48, 16);
  return cat(a, ph);
}

fn sfdp_major_bad() -> Vec[UInt8] {
  let a = hb("53464450060200FF");
  let ph = param_head(0, 255, 1, 6, 48, 16);
  return cat(a, ph);
}

fn sfdp_minor_bad() -> Vec[UInt8] {
  let a = hb("534644500A0100FF");
  let ph = param_head(0, 255, 1, 6, 48, 16);
  return cat(a, ph);
}

// --------------------------------------------------
//  Error checkers per result type
// --------------------------------------------------

fn err_int(r: Result[Int, FlashError], off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: FlashError = r.error;
  let o: Int = e.offset;
  let m: Str = e.message;
  if o != off {
    return false;
  }
  return str_eq(m, msg);
}

fn err_jedec(r: Result[FlashJedecId, FlashError], off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: FlashError = r.error;
  let o: Int = e.offset;
  let m: Str = e.message;
  if o != off {
    return false;
  }
  return str_eq(m, msg);
}

fn err_status(r: Result[FlashStatus1, FlashError], off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: FlashError = r.error;
  let o: Int = e.offset;
  let m: Str = e.message;
  if o != off {
    return false;
  }
  return str_eq(m, msg);
}

fn err_shdr(r: Result[FlashSfdpHeader, FlashError], off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: FlashError = r.error;
  let o: Int = e.offset;
  let m: Str = e.message;
  if o != off {
    return false;
  }
  return str_eq(m, msg);
}

fn err_phdr(r: Result[FlashSfdpParamHeader, FlashError], off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: FlashError = r.error;
  let o: Int = e.offset;
  let m: Str = e.message;
  if o != off {
    return false;
  }
  return str_eq(m, msg);
}

fn err_bfpt(r: Result[FlashBfpt, FlashError], off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: FlashError = r.error;
  let o: Int = e.offset;
  let m: Str = e.message;
  if o != off {
    return false;
  }
  return str_eq(m, msg);
}

fn err_sector(r: Result[FlashSector, FlashError], off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: FlashError = r.error;
  let o: Int = e.offset;
  let m: Str = e.message;
  if o != off {
    return false;
  }
  return str_eq(m, msg);
}

fn err_range(r: Result[FlashSectorRange, FlashError], off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: FlashError = r.error;
  let o: Int = e.offset;
  let m: Str = e.message;
  if o != off {
    return false;
  }
  return str_eq(m, msg);
}

// Address -> (index, offset) check.
fn smap_is(sec: Int, cap: Int, addr: Int, idx: Int, off: Int) -> Bool {
  let r = flash_sector_map(sec, cap, addr);
  if !r.is_ok {
    return false;
  }
  let s: FlashSector = r.value;
  if s.index != idx {
    return false;
  }
  if s.offset != off {
    return false;
  }
  if s.sector_count != cap / sec {
    return false;
  }
  return true;
}

// Sector -> [start, end) check.
fn srange_is(sec: Int, cap: Int, idx: Int, start: Int, stop: Int) -> Bool {
  let r = flash_sector_range(sec, cap, idx);
  if !r.is_ok {
    return false;
  }
  let s: FlashSectorRange = r.value;
  if s.start_address != start {
    return false;
  }
  if s.end_address != stop {
    return false;
  }
  if s.sector_count != cap / sec {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let tab = flash_command_table();
  var ok = tab.len() == 18;
  if flash_command_count() != 18 { ok = false; }
  if flash_command_code(0) != 3 { ok = false; }
  if flash_command_code(1) != 11 { ok = false; }
  if flash_command_code(2) != 235 { ok = false; }
  if flash_command_code(3) != 2 { ok = false; }
  if flash_command_code(4) != 32 { ok = false; }
  if flash_command_code(5) != 216 { ok = false; }
  if flash_command_code(6) != 6 { ok = false; }
  if flash_command_code(7) != 4 { ok = false; }
  if flash_command_code(8) != 5 { ok = false; }
  if flash_command_code(9) != 53 { ok = false; }
  if flash_command_code(10) != 1 { ok = false; }
  if flash_command_code(11) != 159 { ok = false; }
  if flash_command_code(12) != 90 { ok = false; }
  if flash_command_code(13) != 199 { ok = false; }
  if flash_command_code(14) != 96 { ok = false; }
  if flash_command_code(15) != 75 { ok = false; }
  if flash_command_code(16) != 102 { ok = false; }
  if flash_command_code(17) != 153 { ok = false; }
  if flash_command_code(18) != -1 { ok = false; }
  if flash_command_code(-1) != -1 { ok = false; }
  var i = 0;
  while i < tab.len() {
    let x: Int = tab[i];
    if flash_command_code(i) != x { ok = false; }
    i = i + 1;
  }
  return assert(ok, "the 18 pinned 25-series opcodes are present and ordered");
}

fn t2() -> TestResult {
  var names = Vec[Str].new();
  names.push("READ");
  names.push("FAST_READ");
  names.push("FAST_READ_QUAD_IO");
  names.push("PAGE_PROGRAM");
  names.push("SECTOR_ERASE");
  names.push("BLOCK_ERASE");
  names.push("WRITE_ENABLE");
  names.push("WRITE_DISABLE");
  names.push("READ_STATUS1");
  names.push("READ_STATUS2");
  names.push("WRITE_STATUS");
  names.push("READ_ID");
  names.push("READ_SFDP");
  names.push("CHIP_ERASE");
  names.push("CHIP_ERASE_ALT");
  names.push("READ_4B");
  names.push("RESET_ENABLE");
  names.push("RESET");
  var ok = names.len() == flash_command_count();
  var i = 0;
  while i < names.len() {
    let want: Str = names[i];
    if !str_eq(flash_command_name_at(i), want) { ok = false; }
    i = i + 1;
  }
  if !str_eq(flash_command_name(0), "unknown") { ok = false; }
  if !str_eq(flash_command_name(255), "unknown") { ok = false; }
  if !str_eq(flash_command_name_at(18), "unknown") { ok = false; }
  return assert(ok, "command names are stable and table-indexed");
}

fn t3() -> TestResult {
  let tab = flash_manufacturer_table();
  var ok = tab.len() == 9;
  if flash_manufacturer_count() != 9 { ok = false; }
  let v0: Int = tab[0];
  if v0 != 1 { ok = false; }
  if flash_manufacturer_id_at(8) != 94 { ok = false; }
  if flash_manufacturer_id_at(9) != -1 { ok = false; }
  if flash_manufacturer_id_at(-1) != -1 { ok = false; }
  if !str_eq(flash_manufacturer_name(1), "Spansion/Cypress") { ok = false; }
  if !str_eq(flash_manufacturer_name(31), "Adesto") { ok = false; }
  if !str_eq(flash_manufacturer_name(32), "Micron") { ok = false; }
  if !str_eq(flash_manufacturer_name(191), "SST/Microchip") { ok = false; }
  if !str_eq(flash_manufacturer_name(194), "Macronix") { ok = false; }
  if !str_eq(flash_manufacturer_name(239), "Winbond") { ok = false; }
  if !str_eq(flash_manufacturer_name(98), "Sanyo") { ok = false; }
  if !str_eq(flash_manufacturer_name(140), "ESMT") { ok = false; }
  if !str_eq(flash_manufacturer_name(94), "Zbit") { ok = false; }
  if !str_eq(flash_manufacturer_name(18), "unknown") { ok = false; }
  if !str_eq(flash_manufacturer_name_at(6), "Sanyo") { ok = false; }
  if !str_eq(flash_manufacturer_name_at(9), "unknown") { ok = false; }
  if !flash_manufacturer_known(239) { ok = false; }
  if flash_manufacturer_known(18) { ok = false; }
  return assert(ok, "documented manufacturer subset decodes to names");
}

fn t4() -> TestResult {
  let id = hb("EF4018");
  let r = flash_jedec_id_parse(&id);
  var ok = r.is_ok;
  if ok {
    let j: FlashJedecId = r.value;
    if j.manufacturer_id != 239 { ok = false; }
    if !str_eq(j.manufacturer_name, "Winbond") { ok = false; }
    if j.memory_type != 64 { ok = false; }
    if j.capacity_code != 24 { ok = false; }
    if j.capacity_bytes != 16777216 { ok = false; }
  }
  return assert(ok, "Winbond-like RDID EF 40 18 is a 16 MiB Winbond flash");
}

fn t5() -> TestResult {
  var ok = true;
  let rm = flash_jedec_id_parse(&hb("20BA17"));
  if !rm.is_ok { ok = false; } else {
    let j: FlashJedecId = rm.value;
    if !str_eq(j.manufacturer_name, "Micron") { ok = false; }
    if j.memory_type != 186 { ok = false; }
    if j.capacity_code != 23 { ok = false; }
    if j.capacity_bytes != 8388608 { ok = false; }
  }
  let rx = flash_jedec_id_parse(&hb("123418"));
  if !rx.is_ok { ok = false; } else {
    let j2: FlashJedecId = rx.value;
    if !str_eq(j2.manufacturer_name, "unknown") { ok = false; }
    if j2.capacity_bytes != 16777216 { ok = false; }
  }
  let rc = flash_jedec_id_parse(&hb("C22018"));
  if !rc.is_ok { ok = false; } else {
    let j3: FlashJedecId = rc.value;
    if !str_eq(j3.manufacturer_name, "Macronix") { ok = false; }
  }
  let r32 = flash_jedec_id_parse(&hb("EF4020"));
  if !r32.is_ok { ok = false; } else {
    let j4: FlashJedecId = r32.value;
    if j4.capacity_code != 32 { ok = false; }
    if j4.capacity_bytes != 4294967296 { ok = false; }
  }
  if !flash_jedec_id_parse(&hb("EF4018010203")).is_ok { ok = false; }
  return assert(ok, "RDID decode covers vendors, unknown IDs and the 4 GiB boundary");
}

fn t6() -> TestResult {
  var ok = err_jedec(flash_jedec_id_parse(&hb("")), 0, "flash: jedec id truncated");
  if !err_jedec(flash_jedec_id_parse(&hb("EF")), 1, "flash: jedec id truncated") { ok = false; }
  if !err_jedec(flash_jedec_id_parse(&hb("EF40")), 2, "flash: jedec id truncated") { ok = false; }
  if !err_jedec(flash_jedec_id_parse(&hb("EF4007")), 2, "flash: invalid capacity code") { ok = false; }
  if !err_jedec(flash_jedec_id_parse(&hb("EF40FF")), 2, "flash: invalid capacity code") { ok = false; }
  let rc = flash_capacity_bytes(8);
  if !rc.is_ok { ok = false; } else {
    let v: Int = rc.value;
    if v != 256 { ok = false; }
  }
  let r32 = flash_capacity_bytes(32);
  if !r32.is_ok { ok = false; } else {
    let v2: Int = r32.value;
    if v2 != 4294967296 { ok = false; }
  }
  if !err_int(flash_capacity_bytes(7), -1, "flash: invalid capacity code") { ok = false; }
  if !err_int(flash_capacity_bytes(33), -1, "flash: invalid capacity code") { ok = false; }
  return assert(ok, "RDID length and capacity-code errors carry offsets");
}

fn t7() -> TestResult {
  let r = flash_sr1_parse(0);
  var ok = r.is_ok;
  if ok {
    let s: FlashStatus1 = r.value;
    if s.wip || s.wel || s.bp0 || s.bp1 || s.bp2 || s.tb || s.sec || s.srp0 { ok = false; }
    if s.block_protect != 0 { ok = false; }
    if s.raw != 0 { ok = false; }
  }
  let r3 = flash_sr1_parse(3);
  if !r3.is_ok { ok = false; } else {
    let s3: FlashStatus1 = r3.value;
    if !s3.wip { ok = false; }
    if !s3.wel { ok = false; }
    if s3.block_protect != 0 { ok = false; }
  }
  let rbc = flash_sr1_parse(188);
  if !rbc.is_ok { ok = false; } else {
    let sb: FlashStatus1 = rbc.value;
    if sb.wip { ok = false; }
    if !sb.bp0 || !sb.bp1 || !sb.bp2 { ok = false; }
    if !sb.tb { ok = false; }
    if sb.sec { ok = false; }
    if !sb.srp0 { ok = false; }
    if sb.block_protect != 7 { ok = false; }
  }
  if !flash_sr1_wip(3) { ok = false; }
  if flash_sr1_wip(2) { ok = false; }
  if !flash_sr1_wel(2) { ok = false; }
  if flash_sr1_wel(1) { ok = false; }
  if flash_sr1_block_protect(188) != 7 { ok = false; }
  if flash_sr1_block_protect(0) != 0 { ok = false; }
  if flash_sr1_block_protect(300) != -1 { ok = false; }
  if flash_sr1_wip(300) { ok = false; }
  if !err_status(flash_sr1_parse(256), -1, "flash: status byte out of range") { ok = false; }
  if !err_status(flash_sr1_parse(-1), -1, "flash: status byte out of range") { ok = false; }
  return assert(ok, "status register 1 bits decode WIP/WEL/BP/TB/SEC/SRP0");
}

fn t8() -> TestResult {
  let buf = sfdp_winbond();
  let r = flash_sfdp_parse_header(&buf);
  var ok = r.is_ok;
  if ok {
    let h: FlashSfdpHeader = r.value;
    if h.major != 1 { ok = false; }
    if h.minor != 6 { ok = false; }
    if h.nph != 0 { ok = false; }
    if h.parameter_header_count != 1 { ok = false; }
  }
  let two = sfdp_two_headers();
  let r2 = flash_sfdp_parse_header(&two);
  if !r2.is_ok { ok = false; } else {
    let h2: FlashSfdpHeader = r2.value;
    if h2.nph != 1 { ok = false; }
    if h2.parameter_header_count != 2 { ok = false; }
  }
  return assert(ok, "SFDP header decodes revision and the NPH+1 count");
}

fn t9() -> TestResult {
  var ok = err_shdr(flash_sfdp_parse_header(&hb("53464450060100")), 7, "flash: sfdp header truncated");
  let bad = sfdp_bad_sig();
  if !err_shdr(flash_sfdp_parse_header(&bad), 0, "flash: bad sfdp signature") { ok = false; }
  let maj = sfdp_major_bad();
  if !err_shdr(flash_sfdp_parse_header(&maj), 5, "flash: sfdp major revision unsupported") { ok = false; }
  let min = sfdp_minor_bad();
  if !err_shdr(flash_sfdp_parse_header(&min), 4, "flash: sfdp minor revision unsupported") { ok = false; }
  let empty = Vec[UInt8].new();
  if !err_shdr(flash_sfdp_parse_header(&empty), 0, "flash: sfdp header truncated") { ok = false; }
  return assert(ok, "SFDP header errors carry the field offset");
}

fn t10() -> TestResult {
  let buf = sfdp_two_headers();
  let r0 = flash_sfdp_parse_param_header(&buf, 0);
  var ok = r0.is_ok;
  if ok {
    let p0: FlashSfdpParamHeader = r0.value;
    if p0.id != 65409 { ok = false; }
    if p0.id_lsb != 129 { ok = false; }
    if p0.id_msb != 255 { ok = false; }
    if p0.major != 1 { ok = false; }
    if p0.minor != 0 { ok = false; }
    if p0.pointer != 32 { ok = false; }
    if p0.length_dwords != 4 { ok = false; }
  }
  let r1 = flash_sfdp_parse_param_header(&buf, 1);
  if !r1.is_ok { ok = false; } else {
    let p1: FlashSfdpParamHeader = r1.value;
    if p1.id != 65280 { ok = false; }
    if p1.pointer != 304 { ok = false; }
    if p1.length_dwords != 16 { ok = false; }
    if p1.minor != 6 { ok = false; }
  }
  if !flash_sfdp_id_is_basic(65280) { ok = false; }
  if flash_sfdp_id_is_basic(65409) { ok = false; }
  if !flash_sfdp_id_is_unused(65535) { ok = false; }
  if !flash_sfdp_id_is_sector_map(65409) { ok = false; }
  return assert(ok, "parameter headers compose LE16 IDs and LE24 pointers");
}

fn t11() -> TestResult {
  let buf = sfdp_two_headers();
  var ok = err_phdr(flash_sfdp_parse_param_header(&buf, 2), -1, "flash: sfdp parameter index out of range");
  if !err_phdr(flash_sfdp_parse_param_header(&buf, -1), -1, "flash: sfdp parameter index out of range") { ok = false; }
  let trunc = hb("53464450060101FF00FF0106");
  if !err_phdr(flash_sfdp_parse_param_header(&trunc, 0), 12, "flash: sfdp parameter header truncated") { ok = false; }
  if !err_phdr(flash_sfdp_parse_param_header(&trunc, 1), 12, "flash: sfdp parameter header truncated") { ok = false; }
  return assert(ok, "parameter header bounds and index errors");
}

fn t12() -> TestResult {
  let buf = sfdp_two_headers();
  let r = flash_sfdp_basic_param(&buf);
  var ok = r.is_ok;
  if ok {
    let p: FlashSfdpParamHeader = r.value;
    if p.id != 65280 { ok = false; }
    if p.pointer != 304 { ok = false; }
    if p.minor != 6 { ok = false; }
  }
  let no = sfdp_no_basic();
  if !err_phdr(flash_sfdp_basic_param(&no), -1, "flash: sfdp basic table missing") { ok = false; }
  let bad = sfdp_basic_major_bad();
  if !err_phdr(flash_sfdp_basic_param(&bad), 10, "flash: sfdp basic table major revision unsupported") { ok = false; }
  return assert(ok, "basic table selection scans entries and reports absence");
}

fn t13() -> TestResult {
  let buf = sfdp_winbond();
  let r = flash_sfdp_bfpt_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let b: FlashBfpt = r.value;
    if b.table_id != 65280 { ok = false; }
    if b.param.pointer != 48 { ok = false; }
    if b.param.length_dwords != 16 { ok = false; }
    if b.param.minor != 6 { ok = false; }
    if b.density_bits != 134217728 { ok = false; }
    if b.capacity_bytes != 16777216 { ok = false; }
    if b.addr_mode != 1 { ok = false; }
    if !b.supports_3_byte { ok = false; }
    if !b.supports_4_byte { ok = false; }
    if b.supports_dtr { ok = false; }
    if !b.supports_1_1_2 || !b.supports_1_2_2 || !b.supports_1_1_4 || !b.supports_1_4_4 { ok = false; }
    if b.page_size_exp != 8 { ok = false; }
    if b.page_size_bytes != 256 { ok = false; }
    if b.erase1_size != 4096 { ok = false; }
    if b.erase1_opcode != 32 { ok = false; }
    if b.erase2_size != 32768 { ok = false; }
    if b.erase2_opcode != 82 { ok = false; }
    if b.erase3_size != 65536 { ok = false; }
    if b.erase3_opcode != 216 { ok = false; }
    if b.erase4_size != 0 { ok = false; }
    if b.erase4_opcode != 0 { ok = false; }
    if b.erase_count != 3 { ok = false; }
    if !b.erase_4k || !b.erase_32k || !b.erase_64k { ok = false; }
    if b.erase_256k { ok = false; }
    if b.erase_bulk { ok = false; }
  }
  return assert(ok, "BFPT decode: Winbond-like 16 MiB image");
}

fn t14() -> TestResult {
  let a = sfdp_density_exp();
  let ra = flash_sfdp_bfpt_parse(&a);
  var ok = ra.is_ok;
  if ok {
    let ba: FlashBfpt = ra.value;
    if ba.density_bits != 134217728 { ok = false; }
    if ba.capacity_bytes != 16777216 { ok = false; }
  }
  let x = sfdp_density_exp_bad();
  if !err_bfpt(flash_sfdp_bfpt_parse(&x), 52, "flash: sfdp density exponent out of range") { ok = false; }
  return assert(ok, "density decodes both BFPT encodings and rejects bad exponents");
}

fn t15() -> TestResult {
  let s = sfdp_short();
  var ok = err_bfpt(flash_sfdp_bfpt_parse(&s), 48, "flash: sfdp basic table too short");
  let p = sfdp_ptr_bad();
  if !err_bfpt(flash_sfdp_bfpt_parse(&p), 64, "flash: sfdp table out of bounds") { ok = false; }
  let q = sfdp_page_absent();
  let rq = flash_sfdp_bfpt_parse(&q);
  if !rq.is_ok { ok = false; } else {
    let bq: FlashBfpt = rq.value;
    if bq.page_size_exp != -1 { ok = false; }
    if bq.page_size_bytes != 0 { ok = false; }
    if flash_bfpt_page_size_known(&bq) { ok = false; }
    if bq.capacity_bytes != 16777216 { ok = false; }
    if flash_bfpt_page_size_bytes(&bq) != 0 { ok = false; }
  }
  return assert(ok, "short tables, out-of-bounds pointers and 9-DWORD tables");
}

fn t16() -> TestResult {
  let b = sfdp_erase_bulk();
  let r = flash_sfdp_bfpt_parse(&b);
  var ok = r.is_ok;
  if ok {
    let x: FlashBfpt = r.value;
    if x.erase_count != 4 { ok = false; }
    if x.erase3_size != 262144 { ok = false; }
    if !x.erase_256k { ok = false; }
    if x.erase_64k { ok = false; }
    if !x.erase_bulk { ok = false; }
    if flash_bfpt_erase_size(&x, 3) != 16777216 { ok = false; }
    if flash_bfpt_smallest_erase_size(&x) != 4096 { ok = false; }
  }
  let e = sfdp_erase_bad();
  if !err_bfpt(flash_sfdp_bfpt_parse(&e), 76, "flash: sfdp erase size exponent out of range") { ok = false; }
  return assert(ok, "erase flags cover 256 KiB and bulk; bad exponents are rejected");
}

fn t17() -> TestResult {
  let cap = 16777216;
  var ok = smap_is(4096, cap, 0, 0, 0);
  if !smap_is(4096, cap, 4095, 0, 4095) { ok = false; }
  if !smap_is(4096, cap, 4096, 1, 0) { ok = false; }
  if !smap_is(4096, cap, 16777215, 4095, 4095) { ok = false; }
  if !smap_is(65536, cap, 65535, 0, 65535) { ok = false; }
  if !smap_is(65536, cap, 65536, 1, 0) { ok = false; }
  if !smap_is(65536, cap, 16777215, 255, 65535) { ok = false; }
  if !err_sector(flash_sector_map(4096, cap, 16777216), 16777216, "flash: address out of range") { ok = false; }
  if !err_sector(flash_sector_map(4096, cap, -1), -1, "flash: negative address") { ok = false; }
  if !err_sector(flash_sector_map(0, cap, 0), -1, "flash: invalid sector size") { ok = false; }
  if !err_sector(flash_sector_map(4096, 0, 0), -1, "flash: invalid capacity") { ok = false; }
  if !err_sector(flash_sector_map(4096, 10000, 0), -1, "flash: capacity not sector aligned") { ok = false; }
  return assert(ok, "sector map boundaries map addresses with divisor/modulo");
}

fn t18() -> TestResult {
  let cap = 16777216;
  var ok = srange_is(4096, cap, 0, 0, 4096);
  if !srange_is(4096, cap, 4095, 16773120, 16777216) { ok = false; }
  if !srange_is(65536, cap, 255, 16711680, 16777216) { ok = false; }
  if !err_range(flash_sector_range(4096, cap, 4096), -1, "flash: sector index out of range") { ok = false; }
  if !err_range(flash_sector_range(4096, cap, -1), -1, "flash: sector index out of range") { ok = false; }
  if !err_range(flash_sector_range(0, cap, 0), -1, "flash: invalid sector size") { ok = false; }
  if !err_range(flash_sector_range(4096, 10000, 0), -1, "flash: capacity not sector aligned") { ok = false; }
  if flash_sector_count(4096, cap) != 4096 { ok = false; }
  if flash_sector_count(65536, cap) != 256 { ok = false; }
  if flash_sector_count(4096, 10000) != 3 { ok = false; }
  if flash_sector_count(0, cap) != -1 { ok = false; }
  if flash_sector_count(4096, 0) != -1 { ok = false; }
  let buf = sfdp_winbond();
  let rb = flash_sfdp_bfpt_parse(&buf);
  if !rb.is_ok { ok = false; } else {
    let b: FlashBfpt = rb.value;
    let sec = flash_bfpt_smallest_erase_size(&b);
    if sec != 4096 { ok = false; }
    if !smap_is(sec, b.capacity_bytes, 16777215, 4095, 4095) { ok = false; }
  }
  return assert(ok, "sector ranges, ceiling sector count and BFPT-derived geometry");
}

fn t19() -> TestResult {
  let buf = sfdp_winbond();
  let r = flash_sfdp_bfpt_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let b: FlashBfpt = r.value;
    let f0 = flash_bfpt_fast_read(&b, 0);
    if !f0.supported { ok = false; }
    if f0.opcode != 59 { ok = false; }
    if f0.mode_clocks != 0 { ok = false; }
    if f0.wait_states != 8 { ok = false; }
    let f1 = flash_bfpt_fast_read(&b, 1);
    if !f1.supported { ok = false; }
    if f1.opcode != 187 { ok = false; }
    if f1.mode_clocks != 2 { ok = false; }
    if f1.wait_states != 6 { ok = false; }
    let f2 = flash_bfpt_fast_read(&b, 2);
    if !f2.supported { ok = false; }
    if f2.opcode != 107 { ok = false; }
    if f2.mode_clocks != 2 { ok = false; }
    if f2.wait_states != 4 { ok = false; }
    let f3 = flash_bfpt_fast_read(&b, 3);
    if !f3.supported { ok = false; }
    if f3.opcode != 235 { ok = false; }
    if f3.mode_clocks != 2 { ok = false; }
    if f3.wait_states != 5 { ok = false; }
    let f9 = flash_bfpt_fast_read(&b, 9);
    if f9.supported { ok = false; }
    if flash_bfpt_fast_read_clocks(&b, 0) != 8 { ok = false; }
    if flash_bfpt_fast_read_clocks(&b, 1) != 8 { ok = false; }
    if flash_bfpt_fast_read_clocks(&b, 2) != 6 { ok = false; }
    if flash_bfpt_fast_read_clocks(&b, 3) != 7 { ok = false; }
    if flash_bfpt_fast_read_clocks(&b, 4) != -1 { ok = false; }
    if flash_bfpt_smallest_erase_size(&b) != 4096 { ok = false; }
    if flash_bfpt_erase_size(&b, 0) != 4096 { ok = false; }
    if flash_bfpt_erase_size(&b, 3) != 0 { ok = false; }
    if flash_bfpt_erase_size(&b, 4) != -1 { ok = false; }
    if flash_bfpt_erase_opcode(&b, 2) != 216 { ok = false; }
    if flash_bfpt_erase_opcode(&b, 3) != 0 { ok = false; }
    if flash_bfpt_erase_opcode(&b, -1) != -1 { ok = false; }
    if flash_bfpt_erase_type_count(&b) != 3 { ok = false; }
    if !flash_bfpt_page_size_known(&b) { ok = false; }
    if flash_bfpt_page_size_bytes(&b) != 256 { ok = false; }
    if !flash_bfpt_supports_4byte(&b) { ok = false; }
    if !flash_bfpt_supports_3byte(&b) { ok = false; }
    if flash_bfpt_capacity_bytes(&b) != 16777216 { ok = false; }
    if flash_bfpt_density_bits(&b) != 134217728 { ok = false; }
    if flash_fast_read_mode(1, 1, 2) != 0 { ok = false; }
    if flash_fast_read_mode(1, 2, 2) != 1 { ok = false; }
    if flash_fast_read_mode(1, 1, 4) != 2 { ok = false; }
    if flash_fast_read_mode(1, 4, 4) != 3 { ok = false; }
    if flash_fast_read_mode(1, 1, 1) != -1 { ok = false; }
  }
  return assert(ok, "BFPT fast-read settings, page size and erase queries");
}

fn t20() -> TestResult {
  let buf = sfdp_winbond();
  let r1 = flash_sfdp_bfpt_parse(&buf);
  let r2 = flash_sfdp_bfpt_parse(&buf);
  var ok = r1.is_ok && r2.is_ok;
  if ok {
    let a: FlashBfpt = r1.value;
    let b: FlashBfpt = r2.value;
    if a.capacity_bytes != b.capacity_bytes { ok = false; }
    if a.erase_count != b.erase_count { ok = false; }
    if a.page_size_bytes != b.page_size_bytes { ok = false; }
    if a.addr_mode != b.addr_mode { ok = false; }
    if a.param.pointer != b.param.pointer { ok = false; }
  }
  let j = flash_jedec_id_parse(&hb("EF4018"));
  let j2 = flash_jedec_id_parse(&hb("EF4018"));
  if !j.is_ok || !j2.is_ok { ok = false; } else {
    let x: FlashJedecId = j.value;
    let y: FlashJedecId = j2.value;
    if x.capacity_bytes != y.capacity_bytes { ok = false; }
    if x.manufacturer_id != y.manufacturer_id { ok = false; }
    if !str_eq(x.manufacturer_name, y.manufacturer_name) { ok = false; }
  }
  let d1 = sfdp_d1_alt();
  let rd = flash_sfdp_bfpt_parse(&d1);
  if !rd.is_ok { ok = false; } else {
    let bd: FlashBfpt = rd.value;
    if !bd.supports_dtr { ok = false; }
    if bd.supports_4_byte { ok = false; }
    if !bd.supports_3_byte { ok = false; }
    if bd.supports_1_2_2 { ok = false; }
    let f1 = flash_bfpt_fast_read(&bd, 1);
    if f1.supported { ok = false; }
    if f1.opcode != 0 { ok = false; }
    if f1.mode_clocks != 0 { ok = false; }
    if f1.wait_states != 0 { ok = false; }
    if flash_bfpt_fast_read_clocks(&bd, 1) != -1 { ok = false; }
  }
  return assert(ok, "repeated parses agree and unsupported settings zero out");
}

fn main() -> Int {
  io.println("=== xiom.flash conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.flash: all tests passed");
  } else {
    io.println("xiom.flash: tests failed");
  }
  return failed;
}
