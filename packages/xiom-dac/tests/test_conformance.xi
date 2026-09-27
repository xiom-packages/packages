// XIOM -- xiom.dac conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.dac codecs against the documented
// byte-level layouts -- MCP4725 fast / write-DAC / write-DAC+EEPROM frames
// with the power-down selection, MCP4728 address bits, multi-write, single
// write and fast write frames, the MCP4922 channel/BUF/gain/SHDN matrix and
// the MCP4921 single-channel restriction, plus the integer
// code-to-microvolt scaling for every family.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every pinned byte string below was derived by hand from the datasheet
// tables reproduced in SPEC.md and independently recomputed:
//   * MCP4725 fast C4 0A BC is address 0x62, code 0xABC (2748), PD 00;
//   * MCP4725 write DAC C4 40 AB C0 keeps the code left-aligned D11..D4;
//   * MCP4728 multi-write C0 40 98 00 is channel A, code 2048, internal
//     reference, gain 1x;
//   * MCP4922 F1 23 is channel B, buffered reference, 1x gain, output active.
// All synthetic frames are built in-test with xiom.encoding.hex or explicit
// pushes; no file or device is touched (the library is a codec).
//
// BUG 17 discipline: no Str value is compared with `==`; names and error
// messages go through xiom.string.compare.str_compare. All Vec element reads
// are bound to typed locals and every Vec[UInt8] byte is widened with
// `(x as Int) & 0xFF`.

module dac_tests
use xiom.io; use xiom.test;
use xiom.dac;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers (independent of src/dac.xi)
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

fn err_4725_is(r: Result[Mcp4725Frame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_4728_is(r: Result[Mcp4728Frame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_492x_is(r: Result[Mcp492xFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Expected frame bytes of a hex string, as a Result-style check.
fn bytes_are(r: Result[Vec[UInt8], Str], hexstr: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  return bytes_equal(v, hb(hexstr));
}

// --------------------------------------------------
//  MCP4725: addressing and frames
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = int_is(mcp4725_address_byte(96, false), 192);
  if !int_is(mcp4725_address_byte(96, true), 193) { ok = false; }
  if !int_is(mcp4725_address_byte(103, false), 206) { ok = false; }
  if !int_is(mcp4725_address_byte(103, true), 207) { ok = false; }
  if !int_is(mcp4725_read_address_byte(98), 197) { ok = false; }
  if !err_int_is(mcp4725_address_byte(95, false), "dac.mcp4725: address 95 out of range 96..103") { ok = false; }
  if !err_int_is(mcp4725_address_byte(104, true), "dac.mcp4725: address 104 out of range 96..103") { ok = false; }
  if MCP4725_ADDRESS_BASE != 96 { ok = false; }
  if MCP4725_ADDRESS_MAX != 103 { ok = false; }
  if mcp4725_resolution_bits() != 12 { ok = false; }
  if mcp4725_full_scale() != 4095 { ok = false; }
  return assert(ok, "MCP4725 address: 0x60..0x67 wire bytes with R/W bit, range errors");
}

fn t2() -> TestResult {
  var ok = bytes_are(mcp4725_fast_frame(98, 2748, 0), "C40ABC");
  if !bytes_are(mcp4725_fast_frame(98, 4095, 1), "C41FFF") { ok = false; }
  if !bytes_are(mcp4725_fast_frame(96, 0, 0), "C00000") { ok = false; }
  if !bytes_are(mcp4725_fast_frame(103, 2748, 3), "CE3ABC") { ok = false; }
  if !bytes_are(mcp4725_fast_frame(103, 2748, 2), "CE2ABC") { ok = false; }
  let f0 = mcp4725_fast_frame(98, 2748, 0);
  if !f0.is_ok {
    ok = false;
  } else {
    let fv: Vec[UInt8] = f0.value;
    if fv.len() != 3 { ok = false; }
  }
  return assert(ok, "MCP4725 fast frame: 3-byte 00 PD D11..D0 layout, golden bytes");
}

fn t3() -> TestResult {
  var ok = true;
  let r1 = mcp4725_decode(&hb("C40ABC"));
  if !r1.is_ok {
    ok = false;
  } else {
    let f: Mcp4725Frame = r1.value;
    if f.address != 98 { ok = false; }
    if f.mode != MCP4725_CMD_FAST { ok = false; }
    if f.pd != 0 { ok = false; }
    if f.code != 2748 { ok = false; }
  }
  let r2 = mcp4725_decode(&hb("CE3ABC"));
  if !r2.is_ok {
    ok = false;
  } else {
    let f: Mcp4725Frame = r2.value;
    if f.address != 103 { ok = false; }
    if f.pd != 3 { ok = false; }
    if f.code != 2748 { ok = false; }
  }
  let r3 = mcp4725_decode(&hb("C01FFF"));
  if !r3.is_ok {
    ok = false;
  } else {
    let f: Mcp4725Frame = r3.value;
    if f.pd != 1 { ok = false; }
    if f.code != 4095 { ok = false; }
  }
  return assert(ok, "MCP4725 fast decode: address, power-down and 12-bit code fields");
}

fn t4() -> TestResult {
  var ok = bytes_are(mcp4725_write_dac_frame(98, 2748, 0), "C440ABC0");
  if !bytes_are(mcp4725_write_dac_frame(98, 2748, 2), "C444ABC0") { ok = false; }
  if !bytes_are(mcp4725_write_dac_frame(96, 4095, 1), "C042FFF0") { ok = false; }
  let r1 = mcp4725_decode(&hb("C440ABC0"));
  if !r1.is_ok {
    ok = false;
  } else {
    let f: Mcp4725Frame = r1.value;
    if f.mode != MCP4725_CMD_WRITE_DAC { ok = false; }
    if f.pd != 0 { ok = false; }
    if f.code != 2748 { ok = false; }
  }
  let r2 = mcp4725_decode(&hb("C042FFF0"));
  if !r2.is_ok {
    ok = false;
  } else {
    let f: Mcp4725Frame = r2.value;
    if f.mode != MCP4725_CMD_WRITE_DAC { ok = false; }
    if f.pd != 1 { ok = false; }
    if f.code != 4095 { ok = false; }
  }
  return assert(ok, "MCP4725 write-DAC: 010 + PD command byte, D11..D4 / D3..D0 nibbles");
}

fn t5() -> TestResult {
  var ok = bytes_are(mcp4725_write_eeprom_frame(98, 2748, 1), "C462ABC0");
  if !bytes_are(mcp4725_write_eeprom_frame(103, 0, 3), "CE660000") { ok = false; }
  if !err_bytes_is(mcp4725_write_eeprom_frame(104, 0, 0), "dac.mcp4725: address 104 out of range 96..103") { ok = false; }
  let r1 = mcp4725_decode(&hb("CE660000"));
  if !r1.is_ok {
    ok = false;
  } else {
    let f: Mcp4725Frame = r1.value;
    if f.mode != MCP4725_CMD_WRITE_EEPROM { ok = false; }
    if f.pd != 3 { ok = false; }
    if f.code != 0 { ok = false; }
    if f.address != 103 { ok = false; }
  }
  if MCP4725_CMD_WRITE_DAC != 2 { ok = false; }
  if MCP4725_CMD_WRITE_EEPROM != 3 { ok = false; }
  return assert(ok, "MCP4725 write DAC+EEPROM: 011 command byte, same data layout");
}

fn t6() -> TestResult {
  var ok = err_bytes_is(mcp4725_fast_frame(98, -1, 0), "dac.mcp4725: code -1 out of range 0..4095");
  if !err_bytes_is(mcp4725_fast_frame(98, 4096, 0), "dac.mcp4725: code 4096 out of range 0..4095") { ok = false; }
  if !err_bytes_is(mcp4725_fast_frame(98, 0, 4), "dac.mcp4725: power-down 4 out of range 0..3") { ok = false; }
  if !err_bytes_is(mcp4725_fast_frame(98, 0, -1), "dac.mcp4725: power-down -1 out of range 0..3") { ok = false; }
  if !err_bytes_is(mcp4725_fast_frame(95, 0, 0), "dac.mcp4725: address 95 out of range 96..103") { ok = false; }
  if !err_bytes_is(mcp4725_write_dac_frame(98, 4096, 0), "dac.mcp4725: code 4096 out of range 0..4095") { ok = false; }
  if !err_bytes_is(mcp4725_write_dac_frame(95, 4096, 4), "dac.mcp4725: address 95 out of range 96..103") { ok = false; }
  if !err_4725_is(mcp4725_decode(&hb("C40A")), "dac.mcp4725: frame length 2 is not 3 (fast) or 4 (normal)") { ok = false; }
  if !err_4725_is(mcp4725_decode(&hb("C4A0ABC0")), "dac.mcp4725: byte 1 command 5 is not 2 (write DAC) or 3 (write DAC+EEPROM)") { ok = false; }
  if !err_4725_is(mcp4725_decode(&hb("C540AB00")), "dac.mcp4725: byte 0 is a read address byte (r/w is 1)") { ok = false; }
  if !err_4725_is(mcp4725_decode(&hb("BE40AB00")), "dac.mcp4725: byte 0 address 95 out of range 96..103") { ok = false; }
  return assert(ok, "MCP4725 validation: field ranges, decode offsets, first-error order");
}

fn t7() -> TestResult {
  var ok = str_eq(mcp4725_power_down_name(0), "normal");
  if !str_eq(mcp4725_power_down_name(1), "1k gnd") { ok = false; }
  if !str_eq(mcp4725_power_down_name(2), "100k gnd") { ok = false; }
  if !str_eq(mcp4725_power_down_name(3), "500k gnd") { ok = false; }
  if !str_eq(mcp4725_power_down_name(4), "unknown") { ok = false; }
  if !str_eq(dac_power_down_name(3), "500k gnd") { ok = false; }
  if !bytes_are(mcp4725_fast_frame(98, 0, 0), "C40000") { ok = false; }
  if !bytes_are(mcp4725_fast_frame(98, 0, 1), "C41000") { ok = false; }
  if !bytes_are(mcp4725_fast_frame(98, 0, 2), "C42000") { ok = false; }
  if !bytes_are(mcp4725_fast_frame(98, 0, 3), "C43000") { ok = false; }
  if DAC_PD_NORMAL != 0 { ok = false; }
  if DAC_PD_500K_GND != 3 { ok = false; }
  return assert(ok, "MCP4725 power-down table: names and PD1/PD0 bit packing");
}

fn t8() -> TestResult {
  var ok = int_is(mcp4725_code_to_uv(0, 5000000), 0);
  if !int_is(mcp4725_code_to_uv(2048, 3300000), 1650000) { ok = false; }
  if !int_is(mcp4725_code_to_uv(4095, 5000000), 4998779) { ok = false; }
  if !int_is(mcp4725_code_to_uv(1, 5000000), 1220) { ok = false; }
  if !err_int_is(mcp4725_code_to_uv(4096, 5000000), "dac.mcp4725: code 4096 out of range 0..4095") { ok = false; }
  if !err_int_is(mcp4725_code_to_uv(-1, 5000000), "dac.mcp4725: code -1 out of range 0..4095") { ok = false; }
  if !err_int_is(mcp4725_code_to_uv(0, 0), "dac.mcp4725: vref 0 uV must be positive") { ok = false; }
  if !err_int_is(mcp4725_code_to_uv(0, -5), "dac.mcp4725: vref -5 uV must be positive") { ok = false; }
  if !err_int_is(mcp4725_code_to_uv(4096, 0), "dac.mcp4725: code 4096 out of range 0..4095") { ok = false; }
  if MCP4725_FULL_SCALE != 4095 { ok = false; }
  return assert(ok, "MCP4725 voltage: vdd*code/4096 truncation, boundaries and range errors");
}

// --------------------------------------------------
//  MCP4728: addressing, frames, references
// --------------------------------------------------

fn t9() -> TestResult {
  var ok = int_is(mcp4728_address_from_bits(0, 0, 0), 96);
  if !int_is(mcp4728_address_from_bits(0, 0, 1), 97) { ok = false; }
  if !int_is(mcp4728_address_from_bits(0, 1, 0), 98) { ok = false; }
  if !int_is(mcp4728_address_from_bits(1, 1, 1), 103) { ok = false; }
  if !err_int_is(mcp4728_address_from_bits(0, 2, 0), "dac.mcp4728: a1 2 is not 0 or 1") { ok = false; }
  if !err_int_is(mcp4728_address_from_bits(-1, 0, 0), "dac.mcp4728: a2 -1 is not 0 or 1") { ok = false; }
  if !err_int_is(mcp4728_address_from_bits(0, 0, 5), "dac.mcp4728: a0 5 is not 0 or 1") { ok = false; }
  if !int_is(mcp4728_address_byte(96, false), 192) { ok = false; }
  if !int_is(mcp4728_address_byte(103, true), 207) { ok = false; }
  if !err_int_is(mcp4728_address_byte(95, false), "dac.mcp4728: address 95 out of range 96..103") { ok = false; }
  if mcp4728_resolution_bits() != 12 { ok = false; }
  if mcp4728_full_scale() != 4095 { ok = false; }
  if !str_eq(mcp4728_channel_name(0), "A") { ok = false; }
  if !str_eq(mcp4728_channel_name(3), "D") { ok = false; }
  if !str_eq(mcp4728_channel_name(4), "unknown") { ok = false; }
  return assert(ok, "MCP4728 address: A2 A1 A0 bits, wire bytes, channel names");
}

fn t10() -> TestResult {
  var ok = bytes_are(mcp4728_multi_write_frame(96, 0, 2048, 1, 0, 1, 0), "C0409800");
  if !bytes_are(mcp4728_multi_write_frame(96, 1, 2048, 1, 0, 1, 0), "C0429800") { ok = false; }
  if !bytes_are(mcp4728_multi_write_frame(96, 2, 2048, 1, 0, 1, 0), "C0449800") { ok = false; }
  if !bytes_are(mcp4728_multi_write_frame(96, 3, 2048, 1, 0, 1, 0), "C0469800") { ok = false; }
  let r1 = mcp4728_decode(&hb("C0409800"));
  if !r1.is_ok {
    ok = false;
  } else {
    let f: Mcp4728Frame = r1.value;
    if f.address != 96 { ok = false; }
    if f.mode != MCP4728_MODE_MULTI { ok = false; }
    if f.channel != 0 { ok = false; }
    if f.code != 2048 { ok = false; }
    if f.vref != 1 { ok = false; }
    if f.pd != 0 { ok = false; }
    if f.gain != 1 { ok = false; }
    if f.udac != 0 { ok = false; }
  }
  let r2 = mcp4728_decode(&hb("C0469800"));
  if !r2.is_ok {
    ok = false;
  } else {
    let f: Mcp4728Frame = r2.value;
    if f.channel != 3 { ok = false; }
    if f.gain != 1 { ok = false; }
  }
  if MCP4728_MODE_MULTI != 0 { ok = false; }
  return assert(ok, "MCP4728 multi-write: quad channel matrix 40 42 44 46, decode fields");
}

fn t11() -> TestResult {
  var ok = bytes_are(mcp4728_multi_write_frame(96, 3, 4095, 1, 3, 1, 1), "C047FFFF");
  if !bytes_are(mcp4728_multi_write_frame(96, 0, 2048, 0, 0, 0, 0), "C0400800") { ok = false; }
  if !bytes_are(mcp4728_multi_write_frame(103, 2, 291, 1, 1, 0, 0), "CE44A123") { ok = false; }
  let r1 = mcp4728_decode(&hb("C047FFFF"));
  if !r1.is_ok {
    ok = false;
  } else {
    let f: Mcp4728Frame = r1.value;
    if f.channel != 3 { ok = false; }
    if f.code != 4095 { ok = false; }
    if f.vref != 1 { ok = false; }
    if f.pd != 3 { ok = false; }
    if f.gain != 1 { ok = false; }
    if f.udac != 1 { ok = false; }
  }
  let r2 = mcp4728_decode(&hb("C0400800"));
  if !r2.is_ok {
    ok = false;
  } else {
    let f: Mcp4728Frame = r2.value;
    if f.vref != 0 { ok = false; }
    if f.gain != 0 { ok = false; }
    if f.code != 2048 { ok = false; }
  }
  return assert(ok, "MCP4728 multi-write fields: VREF/PD/GX/D11..D0 packing, external ref");
}

fn t12() -> TestResult {
  var ok = bytes_are(mcp4728_single_write_frame(96, 1, 291, 1, 1, 1, 0), "C05AB123");
  if !bytes_are(mcp4728_fast_frame(96, 2748, 2), "C02ABC") { ok = false; }
  let r1 = mcp4728_decode(&hb("C05AB123"));
  if !r1.is_ok {
    ok = false;
  } else {
    let f: Mcp4728Frame = r1.value;
    if f.mode != MCP4728_MODE_SINGLE { ok = false; }
    if f.channel != 1 { ok = false; }
    if f.code != 291 { ok = false; }
    if f.vref != 1 { ok = false; }
    if f.pd != 1 { ok = false; }
    if f.gain != 1 { ok = false; }
    if f.udac != 0 { ok = false; }
  }
  let r2 = mcp4728_decode(&hb("C02ABC"));
  if !r2.is_ok {
    ok = false;
  } else {
    let f: Mcp4728Frame = r2.value;
    if f.mode != MCP4728_MODE_FAST { ok = false; }
    if f.channel != -1 { ok = false; }
    if f.vref != -1 { ok = false; }
    if f.gain != -1 { ok = false; }
    if f.udac != -1 { ok = false; }
    if f.pd != 2 { ok = false; }
    if f.code != 2748 { ok = false; }
  }
  let r3 = mcp4728_decode(&hb("C0509800"));
  if !r3.is_ok {
    ok = false;
  } else {
    let f: Mcp4728Frame = r3.value;
    if f.mode != MCP4728_MODE_SEQUENTIAL { ok = false; }
    if f.channel != 0 { ok = false; }
    if f.code != 2048 { ok = false; }
  }
  if MCP4728_MODE_SINGLE != 2 { ok = false; }
  if MCP4728_MODE_FAST != 3 { ok = false; }
  return assert(ok, "MCP4728 single write 0x58, sequential 0x50 and fast 3-byte frames");
}

fn t13() -> TestResult {
  var ok = err_bytes_is(mcp4728_multi_write_frame(96, 4, 0, 1, 0, 0, 0), "dac.mcp4728: channel 4 is not 0 (A) .. 3 (D)");
  if !err_bytes_is(mcp4728_multi_write_frame(96, -1, 0, 1, 0, 0, 0), "dac.mcp4728: channel -1 is not 0 (A) .. 3 (D)") { ok = false; }
  if !err_bytes_is(mcp4728_multi_write_frame(96, 0, 4096, 1, 0, 0, 0), "dac.mcp4728: code 4096 out of range 0..4095") { ok = false; }
  if !err_bytes_is(mcp4728_multi_write_frame(96, 0, 0, 2, 0, 0, 0), "dac.mcp4728: vref 2 is not 0 or 1") { ok = false; }
  if !err_bytes_is(mcp4728_multi_write_frame(96, 0, 0, 1, 4, 0, 0), "dac.mcp4728: power-down 4 out of range 0..3") { ok = false; }
  if !err_bytes_is(mcp4728_multi_write_frame(96, 0, 0, 1, 0, 2, 0), "dac.mcp4728: gain 2 is not 0 or 1") { ok = false; }
  if !err_bytes_is(mcp4728_multi_write_frame(96, 0, 0, 1, 0, 0, 3), "dac.mcp4728: udac 3 is not 0 or 1") { ok = false; }
  if !err_bytes_is(mcp4728_multi_write_frame(95, 0, 0, 1, 0, 0, 0), "dac.mcp4728: address 95 out of range 96..103") { ok = false; }
  if !err_4728_is(mcp4728_decode(&hb("C040")), "dac.mcp4728: frame length 2 is not 3 (fast) or 4 (normal)") { ok = false; }
  if !err_4728_is(mcp4728_decode(&hb("C0409800FF")), "dac.mcp4728: frame length 5 is not 3 (fast) or 4 (normal)") { ok = false; }
  if !err_4728_is(mcp4728_decode(&hb("C0089800")), "dac.mcp4728: byte 1 command 0 is not 2 (010)") { ok = false; }
  if !err_4728_is(mcp4728_decode(&hb("C0489800")), "dac.mcp4728: byte 1 write function 01 is reserved") { ok = false; }
  if !err_4728_is(mcp4728_decode(&hb("C1409800")), "dac.mcp4728: byte 0 is a read address byte (r/w is 1)") { ok = false; }
  return assert(ok, "MCP4728 validation: channel/code/vref/gain ranges and decode offsets");
}

fn t14() -> TestResult {
  var ok = int_is(mcp4728_reference_uv(1, 0), 2048000);
  if !int_is(mcp4728_reference_uv(1, 12345), 2048000) { ok = false; }
  if !int_is(mcp4728_reference_uv(0, 3300000), 3300000) { ok = false; }
  if !err_int_is(mcp4728_reference_uv(0, 0), "dac.mcp4728: external vref 0 uV must be positive") { ok = false; }
  if !err_int_is(mcp4728_reference_uv(2, 1000), "dac.mcp4728: vref 2 is not 0 (external) or 1 (internal)") { ok = false; }
  if !int_is(mcp4728_effective_gain(1, 0), 1) { ok = false; }
  if !int_is(mcp4728_effective_gain(1, 1), 2) { ok = false; }
  if !int_is(mcp4728_effective_gain(0, 1), 1) { ok = false; }
  if !int_is(mcp4728_effective_gain(0, 0), 1) { ok = false; }
  if !err_int_is(mcp4728_effective_gain(1, 2), "dac.mcp4728: gain 2 is not 0 (1x) or 1 (2x)") { ok = false; }
  if !err_int_is(mcp4728_effective_gain(3, 0), "dac.mcp4728: vref 3 is not 0 (external) or 1 (internal)") { ok = false; }
  if !int_is(mcp4728_code_to_uv(2048, 1, 0, 0), 1024000) { ok = false; }
  if !int_is(mcp4728_code_to_uv(4095, 1, 1, 0), 4095000) { ok = false; }
  if !int_is(mcp4728_code_to_uv(4095, 0, 1, 5000000), 4998779) { ok = false; }
  if !int_is(mcp4728_code_to_uv(4095, 0, 0, 5000000), 4998779) { ok = false; }
  if !err_int_is(mcp4728_code_to_uv(0, 0, 0, 0), "dac.mcp4728: external vref 0 uV must be positive") { ok = false; }
  if !err_int_is(mcp4728_code_to_uv(4096, 1, 0, 0), "dac.mcp4728: code 4096 out of range 0..4095") { ok = false; }
  if MCP4728_INTERNAL_REF_UV != 2048000 { ok = false; }
  if MCP4728_VREF_INTERNAL != 1 { ok = false; }
  if MCP4728_GAIN_2X != 1 { ok = false; }
  return assert(ok, "MCP4728 references: internal 2.048 V, external gain forced to 1x, scaling");
}

// --------------------------------------------------
//  MCP4921/MCP4922: SPI frames
// --------------------------------------------------

fn t15() -> TestResult {
  var ok = bytes_are(mcp4922_frame(0, 291, 0, 1, 1), "3123");
  if !bytes_are(mcp4922_frame(0, 291, 0, 2, 1), "1123") { ok = false; }
  if !bytes_are(mcp4922_frame(0, 291, 0, 1, 0), "2123") { ok = false; }
  if !bytes_are(mcp4922_frame(0, 291, 1, 1, 1), "7123") { ok = false; }
  if !bytes_are(mcp4922_frame(1, 291, 0, 1, 1), "B123") { ok = false; }
  if !bytes_are(mcp4922_frame(1, 291, 0, 2, 1), "9123") { ok = false; }
  if !bytes_are(mcp4922_frame(1, 291, 0, 1, 0), "A123") { ok = false; }
  if !bytes_are(mcp4922_frame(1, 291, 1, 1, 1), "F123") { ok = false; }
  if !bytes_are(mcp4922_frame(1, 4095, 1, 1, 1), "FFFF") { ok = false; }
  if !bytes_are(mcp4922_frame(0, 0, 0, 2, 0), "0000") { ok = false; }
  return assert(ok, "MCP4922 frame matrix: channel/BUF/gain/SHDN 16-bit words, MSB first");
}

fn t16() -> TestResult {
  var ok = true;
  let r1 = mcp492x_decode(&hb("F123"));
  if !r1.is_ok {
    ok = false;
  } else {
    let f: Mcp492xFrame = r1.value;
    if f.channel != 1 { ok = false; }
    if f.buf != 1 { ok = false; }
    if f.gain != 1 { ok = false; }
    if f.shdn != 1 { ok = false; }
    if f.code != 291 { ok = false; }
  }
  let r2 = mcp492x_decode(&hb("0123"));
  if !r2.is_ok {
    ok = false;
  } else {
    let f: Mcp492xFrame = r2.value;
    if f.channel != 0 { ok = false; }
    if f.buf != 0 { ok = false; }
    if f.gain != 2 { ok = false; }
    if f.shdn != 0 { ok = false; }
    if f.code != 291 { ok = false; }
  }
  if !bytes_are(mcp4921_frame(291, 1, 2, 1), "5123") { ok = false; }
  if !err_492x_is(mcp4921_decode(&hb("F123")), "dac.mcp4921: channel B is not present on the single-channel part") { ok = false; }
  let r4 = mcp4921_decode(&hb("3123"));
  if !r4.is_ok {
    ok = false;
  } else {
    let f: Mcp492xFrame = r4.value;
    if f.channel != 0 { ok = false; }
    if f.code != 291 { ok = false; }
  }
  if !err_492x_is(mcp492x_decode(&hb("31")), "dac.mcp492x: frame needs 2 bytes, have 1") { ok = false; }
  if !err_492x_is(mcp492x_decode(&hb("312300")), "dac.mcp492x: frame needs 2 bytes, have 3") { ok = false; }
  return assert(ok, "MCP492x decode: channel/BUF/gain/SHDN fields, MCP4921 rejects DAC B");
}

fn t17() -> TestResult {
  var ok = err_bytes_is(mcp4922_frame(2, 0, 0, 1, 1), "dac.mcp4922: channel 2 is not 0 (DAC A) or 1 (DAC B)");
  if !err_bytes_is(mcp4922_frame(-1, 0, 0, 1, 1), "dac.mcp4922: channel -1 is not 0 (DAC A) or 1 (DAC B)") { ok = false; }
  if !err_bytes_is(mcp4922_frame(0, -1, 0, 1, 1), "dac.mcp4922: code -1 out of range 0..4095") { ok = false; }
  if !err_bytes_is(mcp4922_frame(0, 4096, 0, 1, 1), "dac.mcp4922: code 4096 out of range 0..4095") { ok = false; }
  if !err_bytes_is(mcp4922_frame(0, 0, 2, 1, 1), "dac.mcp4922: buf 2 is not 0 (unbuffered) or 1 (buffered)") { ok = false; }
  if !err_bytes_is(mcp4922_frame(0, 0, 0, 3, 1), "dac.mcp4922: gain 3 is not 1 (1x) or 2 (2x)") { ok = false; }
  if !err_bytes_is(mcp4922_frame(0, 0, 0, 1, 2), "dac.mcp4922: shdn 2 is not 0 (high-Z) or 1 (active)") { ok = false; }
  if !err_bytes_is(mcp4921_frame(4096, 0, 1, 1), "dac.mcp4921: code 4096 out of range 0..4095") { ok = false; }
  if !err_bytes_is(mcp4921_frame(0, 2, 1, 1), "dac.mcp4921: buf 2 is not 0 (unbuffered) or 1 (buffered)") { ok = false; }
  if mcp492x_ga_bit(1) != 1 { ok = false; }
  if mcp492x_ga_bit(2) != 0 { ok = false; }
  if mcp492x_ga_bit(3) != -1 { ok = false; }
  if mcp492x_shutdown_bit(true) != 0 { ok = false; }
  if mcp492x_shutdown_bit(false) != 1 { ok = false; }
  if !str_eq(mcp492x_channel_name(0), "A") { ok = false; }
  if !str_eq(mcp492x_channel_name(1), "B") { ok = false; }
  if !str_eq(mcp492x_channel_name(2), "unknown") { ok = false; }
  if MCP492X_SHDN_HIGH_Z != 0 { ok = false; }
  if MCP492X_GA_BIT_2X != 0 { ok = false; }
  return assert(ok, "MCP492x validation: field ranges, GA/SHDN bit helpers, names");
}

fn t18() -> TestResult {
  var ok = int_is(mcp492x_code_to_uv(0, 2048000, 1), 0);
  if !int_is(mcp492x_code_to_uv(4095, 2048000, 2), 4095000) { ok = false; }
  if !int_is(mcp492x_code_to_uv(2048, 2048000, 1), 1024000) { ok = false; }
  if !int_is(mcp492x_code_to_uv(4095, 5000000, 1), 4998779) { ok = false; }
  if !int_is(mcp492x_code_to_uv(1, 4096000, 1), 1000) { ok = false; }
  if !err_int_is(mcp492x_code_to_uv(4096, 2048000, 1), "dac.mcp492x: code 4096 out of range 0..4095") { ok = false; }
  if !err_int_is(mcp492x_code_to_uv(0, 0, 1), "dac.mcp492x: vref 0 uV must be positive") { ok = false; }
  if !err_int_is(mcp492x_code_to_uv(0, 2048000, 0), "dac.mcp492x: gain 0 is not 1 (1x) or 2 (2x)") { ok = false; }
  if !err_int_is(mcp492x_code_to_uv(0, 0, 0), "dac.mcp492x: gain 0 is not 1 (1x) or 2 (2x)") { ok = false; }
  if MCP492X_FULL_SCALE != 4095 { ok = false; }
  return assert(ok, "MCP492x voltage: vref*code*gain/4096, 2x doubling, range errors");
}

// --------------------------------------------------
//  Generic scaling, family accessors, determinism
// --------------------------------------------------

fn t19() -> TestResult {
  var ok = int_is(dac_code_to_uv(255, 8, 5000000, 1), 4980468);
  if !int_is(dac_code_to_uv(65535, 16, 2048000, 1), 2047968) { ok = false; }
  if !int_is(dac_code_to_uv(4095, 12, 4096000, 1), 4095000) { ok = false; }
  if !int_is(dac_code_to_uv(0, 12, 1000000, 3), 0) { ok = false; }
  if !int_is(dac_code_to_uv(4095, 12, 1000000, 3), 2999267) { ok = false; }
  if !int_is(dac_code_to_uv(255, 8, 5000000, 2), 9960937) { ok = false; }
  if !err_int_is(dac_code_to_uv(0, 7, 1000, 1), "dac: resolution 7 out of range 8..24") { ok = false; }
  if !err_int_is(dac_code_to_uv(0, 25, 1000, 1), "dac: resolution 25 out of range 8..24") { ok = false; }
  if !err_int_is(dac_code_to_uv(0, 12, 0, 1), "dac: vref 0 uV must be positive") { ok = false; }
  if !err_int_is(dac_code_to_uv(0, 12, -1, 1), "dac: vref -1 uV must be positive") { ok = false; }
  if !err_int_is(dac_code_to_uv(0, 12, 1000, 0), "dac: gain 0 must be at least 1") { ok = false; }
  if !err_int_is(dac_code_to_uv(256, 8, 1000, 1), "dac: code 256 out of range 0..255") { ok = false; }
  if !str_eq(dac_family_name(0), "mcp4725") { ok = false; }
  if !str_eq(dac_family_name(1), "mcp4728") { ok = false; }
  if !str_eq(dac_family_name(2), "mcp4921") { ok = false; }
  if !str_eq(dac_family_name(3), "mcp4922") { ok = false; }
  if !str_eq(dac_family_name(9), "unknown") { ok = false; }
  if dac_resolution_bits(0) != 12 { ok = false; }
  if dac_resolution_bits(3) != 12 { ok = false; }
  if dac_resolution_bits(4) != -1 { ok = false; }
  if dac_full_scale(0) != 4095 { ok = false; }
  if dac_full_scale(3) != 4095 { ok = false; }
  if dac_full_scale(9) != -1 { ok = false; }
  if dac_frame_byte(&hb("C40ABC"), 1) != 10 { ok = false; }
  if dac_frame_byte(&hb("C40ABC"), -1) != -1 { ok = false; }
  if dac_frame_byte(&hb("C40ABC"), 3) != -1 { ok = false; }
  if dac_frame_byte(&hb("FF"), 0) != 255 { ok = false; }
  return assert(ok, "generic scaling 8..24 bits, family accessors, frame byte helper");
}

fn t20() -> TestResult {
  var ok = true;
  var codes = Vec[Int].new();
  codes.push(0);
  codes.push(1);
  codes.push(2048);
  codes.push(4095);
  var pd = 0;
  while pd < 4 {
    var ci = 0;
    while ci < codes.len() {
      let code: Int = codes[ci];
      let fr = mcp4725_fast_frame(98, code, pd);
      if !fr.is_ok {
        ok = false;
      } else {
        let fv: Vec[UInt8] = fr.value;
        let back = mcp4725_decode(&fv);
        if !back.is_ok {
          ok = false;
        } else {
          let bf: Mcp4725Frame = back.value;
          if bf.address != 98 { ok = false; }
          if bf.mode != MCP4725_CMD_FAST { ok = false; }
          if bf.pd != pd { ok = false; }
          if bf.code != code { ok = false; }
        }
        let again = mcp4725_fast_frame(98, code, pd);
        if !again.is_ok {
          ok = false;
        } else {
          let av: Vec[UInt8] = again.value;
          if !bytes_equal(fv, av) { ok = false; }
        }
      }
      ci = ci + 1;
    }
    pd = pd + 1;
  }
  var ch = 0;
  while ch < 2 {
    var buf = 0;
    while buf < 2 {
      var gi = 0;
      while gi < 2 {
        var gain = 1;
        if gi == 1 { gain = 2; }
        var si = 0;
        while si < 2 {
          var shdn = 1;
          if si == 1 { shdn = 0; }
          let fr = mcp4922_frame(ch, 291, buf, gain, shdn);
          if !fr.is_ok {
            ok = false;
          } else {
            let fv: Vec[UInt8] = fr.value;
            let back = mcp492x_decode(&fv);
            if !back.is_ok {
              ok = false;
            } else {
              let bf: Mcp492xFrame = back.value;
              if bf.channel != ch { ok = false; }
              if bf.buf != buf { ok = false; }
              if bf.gain != gain { ok = false; }
              if bf.shdn != shdn { ok = false; }
              if bf.code != 291 { ok = false; }
            }
            let again = mcp4922_frame(ch, 291, buf, gain, shdn);
            if !again.is_ok {
              ok = false;
            } else {
              let av: Vec[UInt8] = again.value;
              if !bytes_equal(fv, av) { ok = false; }
            }
          }
          si = si + 1;
        }
        gi = gi + 1;
      }
      buf = buf + 1;
    }
    ch = ch + 1;
  }
  var qc = 0;
  while qc < 4 {
    let fr = mcp4728_multi_write_frame(96, qc, 2048, 1, 1, 0, 0);
    if !fr.is_ok {
      ok = false;
    } else {
      let fv: Vec[UInt8] = fr.value;
      let back = mcp4728_decode(&fv);
      if !back.is_ok {
        ok = false;
      } else {
        let bf: Mcp4728Frame = back.value;
        if bf.channel != qc { ok = false; }
        if bf.code != 2048 { ok = false; }
        if bf.mode != MCP4728_MODE_MULTI { ok = false; }
      }
    }
    qc = qc + 1;
  }
  let a = mcp4921_frame(291, 0, 1, 1);
  let b = mcp4921_frame(291, 0, 1, 1);
  if !a.is_ok || !b.is_ok {
    ok = false;
  } else {
    let av: Vec[UInt8] = a.value;
    let bv: Vec[UInt8] = b.value;
    if !bytes_equal(av, bv) { ok = false; }
    let ra = mcp4921_decode(&av);
    if !ra.is_ok {
      ok = false;
    } else {
      let fa: Mcp492xFrame = ra.value;
      if fa.code != 291 { ok = false; }
    }
  }
  return assert(ok, "determinism: encode/decode/re-encode over code, PD, channel and gain matrices");
}

fn main() -> Int {
  io.println("=== xiom.dac conformance tests ===");
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
    io.println("xiom.dac: all tests passed");
  } else {
    io.println("xiom.dac: tests failed");
  }
  return failed;
}
