// XIOM -- xiom.eeprom conformance tests (17 checks)
// Port task: prove the pure-XIOM xiom.eeprom codecs against the documented
// 24Cxx (I2C) and 93Cxx (Microwire) wire layouts, the density tables, the
// page/device boundary math, the bit-stream round-trips and the full error
// catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every pinned byte string below was derived by hand from the bit tables in
// SPEC.md and is additionally cross-checked where practical against a
// test-local, independently written bit packer (ref_pack), so an error in
// the module's own bit loop cannot pass unnoticed. All synthetic buffers are
// built in-test from hex strings or explicit pushes; no file or device is
// touched (the library is codec-only).
//
// BUG 17 discipline: no Str value is compared with `==`; error messages go
// through xiom.string.compare.str_compare. All Vec element reads are bound
// to typed locals.

module eeprom_tests
use xiom.io; use xiom.test;
use xiom.eeprom;
use xiom.string.compare;
use xiom.convert;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers (independent of src/eeprom.xi)
// --------------------------------------------------

// Bytes for a hex string; "" on malformed input (the test then fails on the
// byte comparison). Lowercase or uppercase digits both parse.
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_density_is(r: Result[EepromDensity, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_decoded_is(r: Result[Ee93Decoded, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Test-local bit packer, written independently of the module's _pack_bits:
// emit each value MSB-first with the paired width, then chunk the bit list
// into bytes with a running accumulator and an explicit final padding loop.
// `values` and `widths` must have equal lengths (a drift guard returns an
// empty vector, which fails the comparison).
fn ref_pack(values: Vec[Int], widths: Vec[Int]) -> Vec[UInt8] {
  if values.len() != widths.len() {
    return Vec[UInt8].new();
  }
  var bits = Vec[Int].new();
  var i = 0;
  while i < values.len() {
    let v: Int = values[i];
    let w: Int = widths[i];
    var k = w - 1;
    while k >= 0 {
      var p = 1;
      var j = 0;
      while j < k {
        p = p * 2;
        j = j + 1;
      }
      bits.push((v / p) % 2);
      k = k - 1;
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  var acc = 0;
  var count = 0;
  var m = 0;
  while m < bits.len() {
    let bit: Int = bits[m];
    acc = acc * 2;
    if bit != 0 {
      acc = acc + 1;
    }
    count = count + 1;
    if count == 8 {
      out.push(acc as UInt8);
      acc = 0;
      count = 0;
    }
    m = m + 1;
  }
  if count > 0 {
    var q = 0;
    while q < 8 - count {
      acc = acc * 2;
      q = q + 1;
    }
    out.push(acc as UInt8);
  }
  return out;
}

// Canonical 93Cxx density name by table index (0..5).
fn dens_name(i: Int) -> Str {
  if i == 0 {
    return "93C46";
  }
  if i == 1 {
    return "93C56";
  }
  if i == 2 {
    return "93C66";
  }
  if i == 3 {
    return "93C76";
  }
  if i == 4 {
    return "93C86";
  }
  return "93C106";
}

// Expected wire bit count of a 93Cxx command: prefix (3 for READ/WRITE/
// ERASE, 5 for the specials) + address bits + org bits for WRITE/WRAL.
fn ebits(op: Int, ab: Int, org: Int) -> Int {
  var p = 3;
  if op == EE93_EWEN || op == EE93_EWDS || op == EE93_ERAL || op == EE93_WRAL {
    p = 5;
  }
  var extra = 0;
  if op == EE93_WRITE || op == EE93_WRAL {
    extra = org;
  }
  return p + ab + extra;
}

// Encode then decode a 93Cxx command and compare every decoded field.
fn rt_ok(nm: Str, org: Int, op: Int, address: Int, data: Int) -> Bool {
  let c = Ee93Command{ density: nm; org: org; opcode: op; address: address; data: data; };
  let r = ee93_encode(&c);
  if !r.is_ok {
    return false;
  }
  let fb: Vec[UInt8] = r.value;
  let dd = ee93_decode(&fb, nm, org);
  if !dd.is_ok {
    return false;
  }
  let dec: Ee93Decoded = dd.value;
  let ab = ee93_address_bits(nm, org);
  if dec.opcode != op {
    return false;
  }
  if dec.address != address {
    return false;
  }
  if dec.bits != ebits(op, ab, org) {
    return false;
  }
  if op == EE93_WRITE || op == EE93_WRAL {
    if dec.data != data {
      return false;
    }
  } else {
    if dec.data != 0 {
      return false;
    }
  }
  return true;
}

// 24Cxx density row check against the pinned table values.
fn d24_ok(name: Str, bits: Int, bytes: Int, ab: Int, page: Int) -> Bool {
  let r = ee24_density(name);
  if !r.is_ok {
    return false;
  }
  let d: EepromDensity = r.value;
  if !str_eq(d.name, name) {
    return false;
  }
  if d.bits != bits {
    return false;
  }
  if d.bytes != bytes {
    return false;
  }
  if d.addr_bytes != ab {
    return false;
  }
  if d.page_size != page {
    return false;
  }
  if d.org != 8 {
    return false;
  }
  return true;
}

// 93Cxx density row check against the pinned table values.
fn d93_ok(name: Str, org: Int, bits: Int, ab: Int, words: Int) -> Bool {
  let r = ee93_density(name, org);
  if !r.is_ok {
    return false;
  }
  let d: EepromDensity = r.value;
  if d.bits != bits {
    return false;
  }
  if d.bytes != bits / 8 {
    return false;
  }
  if d.page_size != 0 {
    return false;
  }
  if d.org != org {
    return false;
  }
  if ee93_address_bits(name, org) != ab {
    return false;
  }
  if ee93_word_count(name, org) != words {
    return false;
  }
  if ee93_bytes(name, org) != bits / 8 {
    return false;
  }
  if d.addr_bytes != (ab + 7) / 8 {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  24Cxx tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = int_is(ee24_control_byte(0, false), 160);
  if !int_is(ee24_control_byte(0, true), 161) { ok = false; }
  if !int_is(ee24_control_byte(7, false), 174) { ok = false; }
  if !int_is(ee24_control_byte(5, true), 171) { ok = false; }
  if !int_is(ee24_control_byte(3, false), 166) { ok = false; }
  if !int_is(ee24_control_byte(3, true), 167) { ok = false; }
  if !int_is(ee24_device_address_write(1), 162) { ok = false; }
  if !int_is(ee24_device_address_read(1), 163) { ok = false; }
  let e_neg = "eeprom.24cxx: address pins " + convert.int_to_string(-1) + " out of range 0..7";
  let e_hi = "eeprom.24cxx: address pins " + convert.int_to_string(8) + " out of range 0..7";
  if !err_int_is(ee24_control_byte(-1, false), e_neg) { ok = false; }
  if !err_int_is(ee24_control_byte(8, true), e_hi) { ok = false; }
  return assert(ok, "24cxx control byte: 1010 A2A1A0 R/W, pins 0..7");
}

fn t2() -> TestResult {
  var ok = true;
  let r1 = ee24_word_address(165, 1);
  if !r1.is_ok { return assert(false, "1-byte word address must build"); }
  let b1: Vec[UInt8] = r1.value;
  if !bytes_equal(b1, hb("A5")) { ok = false; }
  let r2 = ee24_word_address(165, 2);
  if !r2.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = r2.value;
    if !bytes_equal(b2, hb("00A5")) { ok = false; }
  }
  let r3 = ee24_word_address(255, 1);
  if !r3.is_ok { ok = false; } else {
    let b3: Vec[UInt8] = r3.value;
    if !bytes_equal(b3, hb("FF")) { ok = false; }
  }
  let r4 = ee24_word_address(65535, 2);
  if !r4.is_ok { ok = false; } else {
    let b4: Vec[UInt8] = r4.value;
    if !bytes_equal(b4, hb("FFFF")) { ok = false; }
  }
  let e1 = "eeprom.24cxx: word address " + convert.int_to_string(256) + " does not fit in " + convert.int_to_string(1) + " address byte(s)";
  let e2 = "eeprom.24cxx: word address " + convert.int_to_string(65536) + " does not fit in " + convert.int_to_string(2) + " address byte(s)";
  let e3 = "eeprom.24cxx: word address " + convert.int_to_string(-1) + " does not fit in " + convert.int_to_string(2) + " address byte(s)";
  if !err_bytes_is(ee24_word_address(256, 1), e1) { ok = false; }
  if !err_bytes_is(ee24_word_address(65536, 2), e2) { ok = false; }
  if !err_bytes_is(ee24_word_address(-1, 2), e3) { ok = false; }
  if !err_bytes_is(ee24_word_address(0, 3), "eeprom.24cxx: invalid address width 3") { ok = false; }
  if ee24_addr_bytes("24C16") != 1 { ok = false; }
  if ee24_addr_bytes("24C32") != 2 { ok = false; }
  if ee24_addr_bytes("24C00") != -1 { ok = false; }
  return assert(ok, "24cxx word address: 1/2 big-endian bytes, field-width bounds");
}

fn t3() -> TestResult {
  var ok = d24_ok("24C01", 1024, 128, 1, 8);
  if !d24_ok("24C02", 2048, 256, 1, 8) { ok = false; }
  if !d24_ok("24C04", 4096, 512, 1, 16) { ok = false; }
  if !d24_ok("24C08", 8192, 1024, 1, 16) { ok = false; }
  if !d24_ok("24C16", 16384, 2048, 1, 16) { ok = false; }
  if !d24_ok("24C32", 32768, 4096, 2, 32) { ok = false; }
  if !d24_ok("24C64", 65536, 8192, 2, 32) { ok = false; }
  if !d24_ok("24C128", 131072, 16384, 2, 64) { ok = false; }
  if !d24_ok("24C256", 262144, 32768, 2, 64) { ok = false; }
  if !d24_ok("24C512", 524288, 65536, 2, 128) { ok = false; }
  if !d24_ok("24C1024", 1048576, 131072, 2, 256) { ok = false; }
  if !d24_ok("24C2048", 2097152, 262144, 2, 256) { ok = false; }
  if ee24_page_size("24C64") != 32 { ok = false; }
  if ee24_page_size("24C2048") != 256 { ok = false; }
  if ee24_bytes("24C2048") != 262144 { ok = false; }
  if ee24_bits("24C512") != 524288 { ok = false; }
  if ee24_bits("24C00") != -1 { ok = false; }
  if !err_density_is(ee24_density("24C00"), "eeprom.24cxx: unknown density \"24C00\"") { ok = false; }
  return assert(ok, "24cxx density table: bits/bytes/address bytes/page size 01..2048");
}

fn t4() -> TestResult {
  var ok = ee24_page_start(0, 8) == 0;
  if ee24_page_start(6, 8) != 0 { ok = false; }
  if ee24_page_start(8, 8) != 8 { ok = false; }
  if ee24_page_start(15, 8) != 8 { ok = false; }
  if ee24_page_start(124, 8) != 120 { ok = false; }
  if ee24_page_start(5, 0) != 0 { ok = false; }
  if ee24_next_page_start(6, 8) != 8 { ok = false; }
  if ee24_next_page_start(124, 8) != 128 { ok = false; }
  if ee24_next_page_start(0, 0) != 0 { ok = false; }
  if ee24_page_remaining(0, 8) != 8 { ok = false; }
  if ee24_page_remaining(6, 8) != 2 { ok = false; }
  if ee24_page_remaining(7, 8) != 1 { ok = false; }
  if ee24_page_remaining(124, 8) != 4 { ok = false; }
  if ee24_page_remaining(6, 0) != 0 { ok = false; }
  if ee24_write_target(124, 0, 8) != 124 { ok = false; }
  if ee24_write_target(124, 3, 8) != 127 { ok = false; }
  if ee24_write_target(124, 4, 8) != 120 { ok = false; }
  if ee24_write_target(125, 4, 8) != 121 { ok = false; }
  if ee24_write_target(120, 8, 8) != 120 { ok = false; }
  if ee24_write_target(0, 0, 0) != 0 { ok = false; }
  return assert(ok, "24cxx page math: start, next, remaining, in-page target wrap");
}

fn t5() -> TestResult {
  var ok = ee24_wrap_address(0, 128) == 0;
  if ee24_wrap_address(127, 128) != 127 { ok = false; }
  if ee24_wrap_address(128, 128) != 0 { ok = false; }
  if ee24_wrap_address(130, 128) != 2 { ok = false; }
  if ee24_wrap_address(-1, 128) != 127 { ok = false; }
  if ee24_wrap_address(5, 0) != 0 { ok = false; }
  if ee24_seq_address(126, 1, 128) != 127 { ok = false; }
  if ee24_seq_address(127, 1, 128) != 0 { ok = false; }
  if ee24_seq_address(120, 8, 128) != 0 { ok = false; }
  if ee24_seq_address(120, 9, 128) != 1 { ok = false; }
  if ee24_write_span(6, 8, 128) != 2 { ok = false; }
  if ee24_write_span(0, 8, 128) != 8 { ok = false; }
  if ee24_write_span(124, 8, 128) != 4 { ok = false; }
  if ee24_write_span(120, 8, 128) != 8 { ok = false; }
  if ee24_write_span(128, 8, 128) != 8 { ok = false; }
  if ee24_write_span(0, 8, 0) != 0 { ok = false; }
  return assert(ok, "24cxx device-end wrap: current-address read and write span");
}

fn t6() -> TestResult {
  var ok = true;
  let e_neg = "eeprom.24cxx: byte address " + convert.int_to_string(-1) + " out of range 0.." + convert.int_to_string(127);
  let e_hi = "eeprom.24cxx: byte address " + convert.int_to_string(128) + " out of range 0.." + convert.int_to_string(127);
  if !err_unit_is(ee24_validate_address(-1, 128), e_neg) { ok = false; }
  if !err_unit_is(ee24_validate_address(128, 128), e_hi) { ok = false; }
  if !err_unit_is(ee24_validate_address(0, 0), "eeprom.24cxx: invalid device size 0") { ok = false; }
  if !ee24_validate_address(0, 128).is_ok { ok = false; }
  if !ee24_validate_address(127, 128).is_ok { ok = false; }
  if !ee24_validate_page_write(0, 8, 8).is_ok { ok = false; }
  let e_cross = "eeprom.24cxx: page write of " + convert.int_to_string(9) + " bytes at address " + convert.int_to_string(0) + " crosses the page boundary at byte offset " + convert.int_to_string(8) + " (page size " + convert.int_to_string(8) + ")";
  if !err_unit_is(ee24_validate_page_write(0, 9, 8), e_cross) { ok = false; }
  let e_cross2 = "eeprom.24cxx: page write of " + convert.int_to_string(5) + " bytes at address " + convert.int_to_string(6) + " crosses the page boundary at byte offset " + convert.int_to_string(2) + " (page size " + convert.int_to_string(8) + ")";
  if !err_unit_is(ee24_validate_page_write(6, 5, 8), e_cross2) { ok = false; }
  if !err_unit_is(ee24_validate_page_write(0, 0, 8), "eeprom.24cxx: page write count 0 must be at least 1") { ok = false; }
  if !err_unit_is(ee24_validate_page_write(-5, 1, 8), "eeprom.24cxx: negative byte address -5") { ok = false; }
  if !err_unit_is(ee24_validate_page_write(0, 1, 0), "eeprom.24cxx: invalid page size 0") { ok = false; }
  return assert(ok, "24cxx validation: address range and page-write boundary errors");
}

// --------------------------------------------------
//  93Cxx tests
// --------------------------------------------------

fn t7() -> TestResult {
  var ok = d93_ok("93C46", 8, 1024, 7, 128);
  if !d93_ok("93C46", 16, 1024, 6, 64) { ok = false; }
  if !d93_ok("93C56", 8, 2048, 8, 256) { ok = false; }
  if !d93_ok("93C56", 16, 2048, 7, 128) { ok = false; }
  if !d93_ok("93C66", 8, 4096, 9, 512) { ok = false; }
  if !d93_ok("93C66", 16, 4096, 8, 256) { ok = false; }
  if !d93_ok("93C76", 8, 8192, 10, 1024) { ok = false; }
  if !d93_ok("93C76", 16, 8192, 9, 512) { ok = false; }
  if !d93_ok("93C86", 8, 16384, 11, 2048) { ok = false; }
  if !d93_ok("93C86", 16, 16384, 10, 1024) { ok = false; }
  if !d93_ok("93C106", 8, 65536, 13, 8192) { ok = false; }
  if !d93_ok("93C106", 16, 65536, 12, 4096) { ok = false; }
  if !err_density_is(ee93_density("93C45", 8), "eeprom.93cxx: unknown density \"93C45\" for org 8") { ok = false; }
  if !err_density_is(ee93_density("93C46", 12), "eeprom.93cxx: org 12 is not 8 or 16") { ok = false; }
  if ee93_address_bits("93C45", 8) != -1 { ok = false; }
  if ee93_address_bits("93C46", 12) != -1 { ok = false; }
  if ee93_word_count("93C45", 8) != -1 { ok = false; }
  if ee93_bytes("93C45", 8) != -1 { ok = false; }
  return assert(ok, "93cxx density table: bits/bytes/address bits/words for org 8 and 16");
}

fn t8() -> TestResult {
  var ok = EE93_READ == 2;
  if EE93_WRITE != 5 { ok = false; }
  if EE93_ERASE != 7 { ok = false; }
  if EE93_EWEN != 19 { ok = false; }
  if EE93_EWDS != 16 { ok = false; }
  if EE93_ERAL != 18 { ok = false; }
  if EE93_WRAL != 17 { ok = false; }
  if !str_eq(ee93_opcode_name(EE93_READ), "READ") { ok = false; }
  if !str_eq(ee93_opcode_name(EE93_WRITE), "WRITE") { ok = false; }
  if !str_eq(ee93_opcode_name(EE93_ERASE), "ERASE") { ok = false; }
  if !str_eq(ee93_opcode_name(EE93_EWEN), "EWEN") { ok = false; }
  if !str_eq(ee93_opcode_name(EE93_EWDS), "EWDS") { ok = false; }
  if !str_eq(ee93_opcode_name(EE93_ERAL), "ERAL") { ok = false; }
  if !str_eq(ee93_opcode_name(EE93_WRAL), "WRAL") { ok = false; }
  if !str_eq(ee93_opcode_name(6), "unknown") { ok = false; }
  if !str_eq(ee93_opcode_name(0), "unknown") { ok = false; }
  return assert(ok, "93cxx opcode constants and names match the documented patterns");
}

fn t9() -> TestResult {
  var ok = true;
  // READ "110" + 6-bit word address 3 -> 11000001 1 0000000 = C1 80.
  let c1 = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_READ; address: 6; data: 0; };
  let r1 = ee93_encode(&c1);
  if !r1.is_ok { return assert(false, "READ org16 must encode"); }
  let b1: Vec[UInt8] = r1.value;
  if !bytes_equal(b1, hb("C180")) { ok = false; }
  // Test-local cross-check of the same frame.
  var v1 = Vec[Int].new();
  v1.push(6);
  v1.push(3);
  var w1 = Vec[Int].new();
  w1.push(3);
  w1.push(6);
  if !bytes_equal(b1, ref_pack(v1, w1)) { ok = false; }
  // READ "110" + 7-bit byte address 5 -> 11000001 01 000000 = C1 40.
  let c2 = Ee93Command{ density: "93C46"; org: 8; opcode: EE93_READ; address: 5; data: 0; };
  let r2 = ee93_encode(&c2);
  if !r2.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = r2.value;
    if !bytes_equal(b2, hb("C140")) { ok = false; }
  }
  // ERASE "111" + word address 1 -> 11100000 1 0000000 = E0 80.
  let c3 = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_ERASE; address: 2; data: 0; };
  let r3 = ee93_encode(&c3);
  if !r3.is_ok { ok = false; } else {
    let b3: Vec[UInt8] = r3.value;
    if !bytes_equal(b3, hb("E080")) { ok = false; }
  }
  return assert(ok, "93cxx READ/ERASE frames: pinned bits, MSB first");
}

fn t10() -> TestResult {
  var ok = true;
  // WRITE "101" + word address 2 + data 0x1234 = A1 09 1A 00 (25 bits).
  let c1 = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_WRITE; address: 4; data: 4660; };
  let r1 = ee93_encode(&c1);
  if !r1.is_ok { return assert(false, "WRITE org16 must encode"); }
  let b1: Vec[UInt8] = r1.value;
  if !bytes_equal(b1, hb("A1091A00")) { ok = false; }
  var v1 = Vec[Int].new();
  v1.push(5);
  v1.push(2);
  v1.push(4660);
  var w1 = Vec[Int].new();
  w1.push(3);
  w1.push(6);
  w1.push(16);
  if !bytes_equal(b1, ref_pack(v1, w1)) { ok = false; }
  // WRITE org8, byte address 0, data 0xA5 = A0 29 40 (18 bits).
  let c2 = Ee93Command{ density: "93C46"; org: 8; opcode: EE93_WRITE; address: 0; data: 165; };
  let r2 = ee93_encode(&c2);
  if !r2.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = r2.value;
    if !bytes_equal(b2, hb("A02940")) { ok = false; }
  }
  return assert(ok, "93cxx WRITE frame: pinned 25-bit and 18-bit sequences");
}

fn t11() -> TestResult {
  var ok = true;
  let e1 = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_EWEN; address: 0; data: 0; };
  let r1 = ee93_encode(&e1);
  if !r1.is_ok { return assert(false, "EWEN must encode"); }
  let b1: Vec[UInt8] = r1.value;
  if !bytes_equal(b1, hb("9800")) { ok = false; }
  let e2 = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_EWDS; address: 0; data: 0; };
  let r2 = ee93_encode(&e2);
  if !r2.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = r2.value;
    if !bytes_equal(b2, hb("8000")) { ok = false; }
  }
  let e3 = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_ERAL; address: 0; data: 0; };
  let r3 = ee93_encode(&e3);
  if !r3.is_ok { ok = false; } else {
    let b3: Vec[UInt8] = r3.value;
    if !bytes_equal(b3, hb("9000")) { ok = false; }
  }
  // WRAL "10001" + 6 zero address bits + data 0x55AA = 88 0A B5 40.
  let e4 = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_WRAL; address: 0; data: 21930; };
  let r4 = ee93_encode(&e4);
  if !r4.is_ok { ok = false; } else {
    let b4: Vec[UInt8] = r4.value;
    if !bytes_equal(b4, hb("880AB540")) { ok = false; }
  }
  // EWEN's address field is don't-care: any address encodes the same frame.
  let e5 = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_EWEN; address: 4; data: 0; };
  let r5 = ee93_encode(&e5);
  if !r5.is_ok { ok = false; } else {
    let b5: Vec[UInt8] = r5.value;
    if !bytes_equal(b5, b1) { ok = false; }
  }
  return assert(ok, "93cxx special commands: EWEN/EWDS/ERAL/WRAL pinned frames");
}

fn t12() -> TestResult {
  var ok = true;
  var i = 0;
  while i < 6 {
    let nm = dens_name(i);
    var org = 8;
    while org <= 16 {
      let bc = ee93_bytes(nm, org);
      var maxa = bc - 1;
      if org == 16 {
        maxa = bc - 2;
      }
      if !rt_ok(nm, org, EE93_READ, 0, 0) { ok = false; }
      if !rt_ok(nm, org, EE93_READ, maxa, 0) { ok = false; }
      var wdata = 165;
      if org == 16 {
        wdata = 4660;
      }
      if !rt_ok(nm, org, EE93_WRITE, 0, wdata) { ok = false; }
      if !rt_ok(nm, org, EE93_WRITE, maxa, wdata) { ok = false; }
      if !rt_ok(nm, org, EE93_ERASE, 0, 0) { ok = false; }
      if !rt_ok(nm, org, EE93_ERASE, maxa, 0) { ok = false; }
      if !rt_ok(nm, org, EE93_EWEN, 0, 0) { ok = false; }
      if !rt_ok(nm, org, EE93_EWDS, 0, 0) { ok = false; }
      if !rt_ok(nm, org, EE93_ERAL, 0, 0) { ok = false; }
      var rdata = 90;
      if org == 16 {
        rdata = 21930;
      }
      if !rt_ok(nm, org, EE93_WRAL, 0, rdata) { ok = false; }
      org = org + 8;
    }
    i = i + 1;
  }
  return assert(ok, "93cxx round-trip: all seven opcodes across every density and org");
}

fn t13() -> TestResult {
  var ok = true;
  let b1 = hb("C180");
  let d1 = ee93_decode(&b1, "93C46", 16);
  if !d1.is_ok { return assert(false, "pinned READ must decode"); }
  let x1: Ee93Decoded = d1.value;
  if x1.opcode != EE93_READ { ok = false; }
  if x1.address != 6 { ok = false; }
  if x1.data != 0 { ok = false; }
  if x1.bits != 9 { ok = false; }
  let b2 = hb("A1091A00");
  let d2 = ee93_decode(&b2, "93C46", 16);
  if !d2.is_ok { ok = false; } else {
    let x2: Ee93Decoded = d2.value;
    if x2.opcode != EE93_WRITE { ok = false; }
    if x2.address != 4 { ok = false; }
    if x2.data != 4660 { ok = false; }
    if x2.bits != 25 { ok = false; }
  }
  let b3 = hb("9800");
  let d3 = ee93_decode(&b3, "93C46", 16);
  if !d3.is_ok { ok = false; } else {
    let x3: Ee93Decoded = d3.value;
    if x3.opcode != EE93_EWEN { ok = false; }
    if x3.address != 0 { ok = false; }
    if x3.bits != 11 { ok = false; }
  }
  // EWEN with nonzero don't-care address bits still decodes (address
  // reported as 0); ERAL likewise.
  let b4 = hb("9820");
  let d4 = ee93_decode(&b4, "93C46", 16);
  if !d4.is_ok { ok = false; } else {
    let x4: Ee93Decoded = d4.value;
    if x4.opcode != EE93_EWEN { ok = false; }
    if x4.address != 0 { ok = false; }
    if x4.bits != 11 { ok = false; }
  }
  let b5 = hb("9000");
  let d5 = ee93_decode(&b5, "93C46", 16);
  if !d5.is_ok { ok = false; } else {
    let x5: Ee93Decoded = d5.value;
    if x5.opcode != EE93_ERAL { ok = false; }
    if x5.bits != 11 { ok = false; }
  }
  // WRAL rule on decode: the address field must be zero.
  let b6 = hb("88200000");
  let d6 = ee93_decode(&b6, "93C46", 16);
  if !err_decoded_is(d6, "eeprom.93cxx: WRAL address field must be 0") { ok = false; }
  return assert(ok, "93cxx decode: pinned frames, don't-care specials, WRAL zero rule");
}

fn t14() -> TestResult {
  var ok = true;
  let a1 = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_WRITE; address: 3; data: 1; };
  if !err_bytes_is(ee93_encode(&a1), "eeprom.93cxx: byte address 3 is not aligned for org 16") { ok = false; }
  let a2 = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_READ; address: 5; data: 0; };
  if !err_bytes_is(ee93_encode(&a2), "eeprom.93cxx: byte address 5 is not aligned for org 16") { ok = false; }
  let a3 = Ee93Command{ density: "93C46"; org: 8; opcode: EE93_READ; address: 128; data: 0; };
  let e_range = "eeprom.93cxx: byte address " + convert.int_to_string(128) + " out of range 0.." + convert.int_to_string(127) + " for 93C46 org " + convert.int_to_string(8);
  if !err_bytes_is(ee93_encode(&a3), e_range) { ok = false; }
  let a4 = Ee93Command{ density: "93C46"; org: 8; opcode: EE93_ERASE; address: -1; data: 0; };
  if !err_bytes_is(ee93_encode(&a4), "eeprom.93cxx: byte address -1 out of range 0..127 for 93C46 org 8") { ok = false; }
  let a5 = Ee93Command{ density: "93C46"; org: 8; opcode: EE93_WRITE; address: 0; data: 256; };
  if !err_bytes_is(ee93_encode(&a5), "eeprom.93cxx: data 256 out of range 0..255 for org 8") { ok = false; }
  let a6 = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_WRITE; address: 0; data: 65536; };
  if !err_bytes_is(ee93_encode(&a6), "eeprom.93cxx: data 65536 out of range 0..65535 for org 16") { ok = false; }
  let a7 = Ee93Command{ density: "93C46"; org: 16; opcode: 3; address: 0; data: 0; };
  if !err_bytes_is(ee93_encode(&a7), "eeprom.93cxx: invalid opcode 3") { ok = false; }
  let a8 = Ee93Command{ density: "93C46"; org: 16; opcode: EE93_WRAL; address: 2; data: 0; };
  if !err_bytes_is(ee93_encode(&a8), "eeprom.93cxx: WRAL address must be 0") { ok = false; }
  let a9 = Ee93Command{ density: "93C46"; org: 12; opcode: EE93_READ; address: 0; data: 0; };
  if !err_bytes_is(ee93_encode(&a9), "eeprom.93cxx: org 12 is not 8 or 16") { ok = false; }
  let a10 = Ee93Command{ density: "93C45"; org: 8; opcode: EE93_READ; address: 0; data: 0; };
  if !err_bytes_is(ee93_encode(&a10), "eeprom.93cxx: unknown density \"93C45\" for org 8") { ok = false; }
  // Decode-side truncation and prefix errors.
  let b1 = hb("C0");
  if !err_decoded_is(ee93_decode(&b1, "93C46", 16), "eeprom.93cxx: truncated command: need 9 bits, have 8") { ok = false; }
  var b2 = Vec[UInt8].new();
  if !err_decoded_is(ee93_decode(&b2, "93C46", 16), "eeprom.93cxx: truncated command: need 3 bits, have 0") { ok = false; }
  let b3 = hb("0000");
  if !err_decoded_is(ee93_decode(&b3, "93C46", 16), "eeprom.93cxx: unknown opcode prefix 0 at bit 0") { ok = false; }
  let b4 = hb("2000");
  if !err_decoded_is(ee93_decode(&b4, "93C46", 16), "eeprom.93cxx: unknown opcode prefix 1 at bit 0") { ok = false; }
  return assert(ok, "93cxx validation: alignment, ranges, data, opcode and decode truncation");
}

fn t15() -> TestResult {
  var ok = true;
  let r1 = ee93_encode_read_response(165, 8);
  if !r1.is_ok { return assert(false, "org8 response must encode"); }
  let b1: Vec[UInt8] = r1.value;
  if !bytes_equal(b1, hb("A5")) { ok = false; }
  let r2 = ee93_encode_read_response(4660, 16);
  if !r2.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = r2.value;
    if !bytes_equal(b2, hb("1234")) { ok = false; }
  }
  let b3 = hb("1234");
  if !int_is(ee93_decode_read_response(&b3, 16), 4660) { ok = false; }
  let b4 = hb("A5");
  if !int_is(ee93_decode_read_response(&b4, 8), 165) { ok = false; }
  let b5 = hb("FF00");
  if !int_is(ee93_decode_read_response(&b5, 16), 65280) { ok = false; }
  if !err_bytes_is(ee93_encode_read_response(256, 8), "eeprom.93cxx: read response value 256 out of range 0..255 for org 8") { ok = false; }
  if !err_bytes_is(ee93_encode_read_response(-1, 8), "eeprom.93cxx: read response value -1 out of range 0..255 for org 8") { ok = false; }
  if !err_bytes_is(ee93_encode_read_response(65536, 16), "eeprom.93cxx: read response value 65536 out of range 0..65535 for org 16") { ok = false; }
  if !err_bytes_is(ee93_encode_read_response(0, 12), "eeprom.93cxx: org 12 is not 8 or 16") { ok = false; }
  let b6 = hb("12");
  if !err_int_is(ee93_decode_read_response(&b6, 16), "eeprom.93cxx: read response needs 2 byte(s), have 1") { ok = false; }
  var b7 = Vec[UInt8].new();
  if !err_int_is(ee93_decode_read_response(&b7, 16), "eeprom.93cxx: read response needs 2 byte(s), have 0") { ok = false; }
  if !err_int_is(ee93_decode_read_response(&b7, 12), "eeprom.93cxx: org 12 is not 8 or 16") { ok = false; }
  // Round-trip a few pinned values.
  var vals = Vec[Int].new();
  vals.push(0);
  vals.push(1);
  vals.push(255);
  vals.push(65280);
  vals.push(65535);
  var i = 0;
  while i < vals.len() {
    let v: Int = vals[i];
    let org = 16;
    let er = ee93_encode_read_response(v, org);
    if !er.is_ok { ok = false; } else {
      let eb: Vec[UInt8] = er.value;
      let drr = ee93_decode_read_response(&eb, org);
      if !int_is(drr, v) { ok = false; }
    }
    i = i + 1;
  }
  return assert(ok, "93cxx READ responses: MSB-first data frames, org 8 and 16");
}

// --------------------------------------------------
//  Boundary and pipeline tests
// --------------------------------------------------

fn t16() -> TestResult {
  var ok = true;
  // 24C64: 64 Kbit = 8192 bytes, 2-byte word address, 32-byte pages.
  if ee24_bytes("24C64") != 8192 { ok = false; }
  if ee24_bits("24C64") != 65536 { ok = false; }
  if ee24_page_size("24C64") != 32 { ok = false; }
  if ee24_addr_bytes("24C64") != 2 { ok = false; }
  let cb = ee24_control_byte(3, false);
  if !int_is(cb, 166) { ok = false; }
  let wa = ee24_word_address(4660, 2);
  if !wa.is_ok { ok = false; } else {
    let wb: Vec[UInt8] = wa.value;
    if !bytes_equal(wb, hb("1234")) { ok = false; }
  }
  if !ee24_validate_page_write(8190, 2, 32).is_ok { ok = false; }
  let e_cross = "eeprom.24cxx: page write of " + convert.int_to_string(3) + " bytes at address " + convert.int_to_string(8190) + " crosses the page boundary at byte offset " + convert.int_to_string(2) + " (page size " + convert.int_to_string(32) + ")";
  if !err_unit_is(ee24_validate_page_write(8190, 3, 32), e_cross) { ok = false; }
  if ee24_write_target(8190, 2, 32) != 8160 { ok = false; }
  if ee24_write_target(8190, 3, 32) != 8161 { ok = false; }
  if ee24_next_page_start(8190, 32) != 8192 { ok = false; }
  if ee24_page_remaining(8190, 32) != 2 { ok = false; }
  if ee24_write_span(8190, 32, 8192) != 2 { ok = false; }
  if ee24_seq_address(8191, 1, 8192) != 0 { ok = false; }
  if ee24_seq_address(8000, 200, 8192) != 8 { ok = false; }
  // 24C2048: 2 Mbit = 262144 bytes, last-byte boundary.
  if ee24_page_start(262143, 256) != 261888 { ok = false; }
  if ee24_page_remaining(262143, 256) != 1 { ok = false; }
  if ee24_seq_address(262143, 1, 262144) != 0 { ok = false; }
  if ee24_write_span(262143, 256, 262144) != 1 { ok = false; }
  if ee24_write_target(261888, 256, 256) != 261888 { ok = false; }
  return assert(ok, "24C64/24C2048 pipeline: density, control byte, page and wrap boundaries");
}

fn t17() -> TestResult {
  var ok = true;
  // Repeated encodes agree byte for byte.
  let c1 = Ee93Command{ density: "93C66"; org: 16; opcode: EE93_WRITE; address: 510; data: 43981; };
  let a = ee93_encode(&c1);
  let b = ee93_encode(&c1);
  if !a.is_ok || !b.is_ok { ok = false; } else {
    let ab: Vec[UInt8] = a.value;
    let bb: Vec[UInt8] = b.value;
    if !bytes_equal(ab, bb) { ok = false; }
    let da = ee93_decode(&ab, "93C66", 16);
    let db = ee93_decode(&bb, "93C66", 16);
    if !da.is_ok || !db.is_ok { ok = false; } else {
      let xa: Ee93Decoded = da.value;
      let xb: Ee93Decoded = db.value;
      if xa.opcode != xb.opcode { ok = false; }
      if xa.address != xb.address { ok = false; }
      if xa.data != xb.data { ok = false; }
      if xa.bits != xb.bits { ok = false; }
      if xa.address != 510 { ok = false; }
      if xa.data != 43981 { ok = false; }
    }
  }
  // Independent commands with equal content encode identically.
  let c2 = Ee93Command{ density: "93C66"; org: 16; opcode: EE93_WRITE; address: 510; data: 43981; };
  let c = ee93_encode(&c2);
  if !c.is_ok { ok = false; } else {
    let cb: Vec[UInt8] = c.value;
    if a.is_ok {
      let ab2: Vec[UInt8] = a.value;
      if !bytes_equal(cb, ab2) { ok = false; }
    } else {
      ok = false;
    }
  }
  // Repeated word addresses agree.
  let w1 = ee24_word_address(4660, 2);
  let w2 = ee24_word_address(4660, 2);
  if !w1.is_ok || !w2.is_ok { ok = false; } else {
    let wb1: Vec[UInt8] = w1.value;
    let wb2: Vec[UInt8] = w2.value;
    if !bytes_equal(wb1, wb2) { ok = false; }
  }
  return assert(ok, "determinism: repeated codec calls and equal-content commands");
}

fn main() -> Int {
  io.println("=== xiom.eeprom conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.eeprom: all tests passed");
  } else {
    io.println("xiom.eeprom: tests failed");
  }
  return failed;
}
