// XIOM -- xiom.i2c conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the pure-XIOM xiom.i2c codec against the documented byte layouts:
// 7-bit address bytes (address << 1 | R/W) with reserved-range validation,
// the 10-bit two-byte addressing form, the typed bus event model with tagged
// stream encode/decode round-trips, ACK/NACK framing rules, the SMBus PEC
// (CRC-8 polynomial 0x07, init 0x00, catalogue check value 0xF4 over
// "123456789") and the SMBus quick/send-byte builders.
//
// Every error message is compared exactly through xiom.string.compare
// (BUG 17: no Str is compared with `==` and none is read from a Vec). All
// synthetic streams are built in-test with xiom.encoding.hex or explicit
// pushes; the PEC catalogue value is cross-checked against a test-local
// polynomial-long-division reference (a different code path from the
// module's byte-wise shift register). All Vec element reads are bound to
// widened typed locals.
//
// BUG 17 discipline: no Str value is ever compared with `==`; error
// messages go through xiom.string.compare.str_compare. BUG: byte widening is
// applied to every Vec[UInt8] read before it enters Int arithmetic.

module i2c_tests
use xiom.io; use xiom.test;
use xiom.i2c;
use xiom.string;
use xiom.string.compare;
use xiom.convert.int;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers (independent of src/i2c.xi)
// --------------------------------------------------

// Expected bytes for a hex string; "" on malformed input (the test then
// fails on the byte comparison). Lowercase or uppercase digits both parse.
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_addr_is(r: Result[I2cAddr, Str], want: Str) -> Bool {
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

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_txn_is(r: Result[I2cTransaction, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Hand-built transaction (for malformed and kinds-only cases the builders
// intentionally do not enforce framing).
fn txn(kinds: Vec[Int], values: Vec[Int]) -> I2cTransaction {
  let t = I2cTransaction{ kinds: kinds; values: values; };
  return t;
}

fn iv1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn iv3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn iv4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn iv6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

fn high_bytes() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(255);
  v.push(0);
  v.push(128);
  v.push(127);
  v.push(1);
  return v;
}

// 300 bytes, byte k = k % 256 (the same pattern the xiom.crc suite pins).
fn pattern_300() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 300 {
    v.push((i % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Test-local CRC-8 reference (polynomial long division)
// --------------------------------------------------

// Bit `k` (0 = least significant) of `v`, for v >= 0.
fn bit_at(v: Int, k: Int) -> Int {
  var x = v;
  var i = 0;
  while i < k {
    x = x / 2;
    i = i + 1;
  }
  return x % 2;
}

// SMBus PEC CRC-8 by schoolbook polynomial division: the message is treated
// as a bit string, shifted left by eight zero bits, and reduced modulo the
// generator 0x107 (x^8 + x^2 + x + 1) with a 9-bit running remainder. This
// is a different code path from the module's byte-wise shift register, so
// agreement on the catalogue vector and on long buffers pins the module.
fn ref_pec(data: &Vec[UInt8]) -> Int {
  var rem = 0;
  var i = 0;
  while i < data.len() {
    let b: Int = (data[i] as Int) & 0xFF;
    var k = 7;
    while k >= 0 {
      let bit: Int = bit_at(b, k);
      rem = rem * 2 + bit;
      if rem >= 256 {
        rem = rem ^ 263;
      }
      k = k - 1;
    }
    i = i + 1;
  }
  var z = 0;
  while z < 8 {
    rem = rem * 2;
    if rem >= 256 {
      rem = rem ^ 263;
    }
    z = z + 1;
  }
  return rem;
}

// --------------------------------------------------
//  7-bit addressing tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = i2c_addr7_ok(8);
  if i2c_addr7_ok(7) { ok = false; }
  if !i2c_addr7_ok(119) { ok = false; }
  if i2c_addr7_ok(120) { ok = false; }
  if i2c_addr7_ok(-1) { ok = false; }
  let w1 = i2c_addr7_wire_byte(80, false);
  if !w1.is_ok { return assert(false, "addr7 write must build"); }
  let b1: Int = w1.value;
  if b1 != 160 { ok = false; }
  let r1 = i2c_addr7_wire_byte(80, true);
  if !r1.is_ok { ok = false; } else {
    let b2: Int = r1.value;
    if b2 != 161 { ok = false; }
  }
  let lo = i2c_addr7_wire_byte(8, false);
  if !lo.is_ok { ok = false; } else {
    let b3: Int = lo.value;
    if b3 != 16 { ok = false; }
  }
  let hi = i2c_addr7_wire_byte(119, true);
  if !hi.is_ok { ok = false; } else {
    let b4: Int = hi.value;
    if b4 != 239 { ok = false; }
  }
  return assert(ok, "addr7 wire byte: addr << 1 | R/W at both reserved edges");
}

fn t2() -> TestResult {
  var ok = err_int_is(i2c_addr7_wire_byte(-1, false), "i2c: 7-bit address out of range (-1)");
  if !err_int_is(i2c_addr7_wire_byte(128, false), "i2c: 7-bit address out of range (128)") { ok = false; }
  if !err_int_is(i2c_addr7_wire_byte(0, false), "i2c: reserved 7-bit address (0)") { ok = false; }
  if !err_int_is(i2c_addr7_wire_byte(7, true), "i2c: reserved 7-bit address (7)") { ok = false; }
  if !err_int_is(i2c_addr7_wire_byte(120, false), "i2c: reserved 7-bit address (120)") { ok = false; }
  if !err_int_is(i2c_addr7_wire_byte(127, true), "i2c: reserved 7-bit address (127)") { ok = false; }
  if !i2c_addr7_wire_byte(8, false).is_ok { ok = false; }
  if !i2c_addr7_wire_byte(119, true).is_ok { ok = false; }
  return assert(ok, "addr7 validation: range and reserved 0x00..0x07 / 0x78..0x7F");
}

fn t3() -> TestResult {
  let d1 = i2c_addr7_from_wire(160);
  if !d1.is_ok { return assert(false, "0xA0 must decode"); }
  let a1: I2cAddr = d1.value;
  var ok = a1.address == 80;
  if a1.read { ok = false; }
  let d2 = i2c_addr7_from_wire(161);
  if !d2.is_ok { ok = false; } else {
    let a2: I2cAddr = d2.value;
    if a2.address != 80 { ok = false; }
    if !a2.read { ok = false; }
  }
  let d3 = i2c_addr7_from_wire(16);
  if !d3.is_ok { ok = false; } else {
    let a3: I2cAddr = d3.value;
    if a3.address != 8 { ok = false; }
  }
  let d4 = i2c_addr7_from_wire(239);
  if !d4.is_ok { ok = false; } else {
    let a4: I2cAddr = d4.value;
    if a4.address != 119 { ok = false; }
    if !a4.read { ok = false; }
  }
  if !err_addr_is(i2c_addr7_from_wire(256), "i2c: address byte out of range (256)") { ok = false; }
  if !err_addr_is(i2c_addr7_from_wire(-1), "i2c: address byte out of range (-1)") { ok = false; }
  if !err_addr_is(i2c_addr7_from_wire(0), "i2c: reserved 7-bit address (0)") { ok = false; }
  if !err_addr_is(i2c_addr7_from_wire(254), "i2c: reserved 7-bit address (127)") { ok = false; }
  if !err_addr_is(i2c_addr7_from_wire(255), "i2c: reserved 7-bit address (127)") { ok = false; }
  return assert(ok, "addr7 decode round-trips and rejects reserved/out-of-range bytes");
}

// --------------------------------------------------
//  10-bit addressing tests
// --------------------------------------------------

fn t4() -> TestResult {
  var ok = i2c_addr10_ok(8);
  if i2c_addr10_ok(7) { ok = false; }
  if !i2c_addr10_ok(1015) { ok = false; }
  if i2c_addr10_ok(1016) { ok = false; }
  if i2c_addr10_ok(1023) { ok = false; }
  if i2c_addr10_ok(-1) { ok = false; }
  let h1 = i2c_addr10_high_byte(675, false);
  if !h1.is_ok { return assert(false, "10-bit high byte must build"); }
  let hb1: Int = h1.value;
  var ok2 = hb1 == 244;
  let l1 = i2c_addr10_low_byte(675);
  if !l1.is_ok { ok2 = false; } else {
    let lb1: Int = l1.value;
    if lb1 != 163 { ok2 = false; }
  }
  let h2 = i2c_addr10_high_byte(675, true);
  if !h2.is_ok { ok2 = false; } else {
    let hb2: Int = h2.value;
    if hb2 != 245 { ok2 = false; }
  }
  let h3 = i2c_addr10_high_byte(256, false);
  if !h3.is_ok { ok2 = false; } else {
    let hb3: Int = h3.value;
    if hb3 != 242 { ok2 = false; }
  }
  let l3 = i2c_addr10_low_byte(256);
  if !l3.is_ok { ok2 = false; } else {
    let lb3: Int = l3.value;
    if lb3 != 0 { ok2 = false; }
  }
  let h4 = i2c_addr10_high_byte(1015, true);
  if !h4.is_ok { ok2 = false; } else {
    let hb4: Int = h4.value;
    if hb4 != 247 { ok2 = false; }
  }
  let l4 = i2c_addr10_low_byte(1015);
  if !l4.is_ok { ok2 = false; } else {
    let lb4: Int = l4.value;
    if lb4 != 247 { ok2 = false; }
  }
  if !err_int_is(i2c_addr10_high_byte(1024, false), "i2c: 10-bit address out of range (1024)") { ok2 = false; }
  if !err_int_is(i2c_addr10_high_byte(7, false), "i2c: reserved 10-bit address (7)") { ok2 = false; }
  if !err_int_is(i2c_addr10_low_byte(1016), "i2c: reserved 10-bit address (1016)") { ok2 = false; }
  return assert(ok && ok2, "10-bit address bytes: 1111 0xx lead byte and low byte");
}

fn t5() -> TestResult {
  let d1 = i2c_addr10_from_bytes(245, 163);
  if !d1.is_ok { return assert(false, "lead 0xF5 must decode"); }
  let a1: I2cAddr = d1.value;
  var ok = a1.address == 675;
  if !a1.read { ok = false; }
  let d2 = i2c_addr10_from_bytes(244, 163);
  if !d2.is_ok { ok = false; } else {
    let a2: I2cAddr = d2.value;
    if a2.address != 675 { ok = false; }
    if a2.read { ok = false; }
  }
  let d3 = i2c_addr10_from_bytes(242, 0);
  if !d3.is_ok { ok = false; } else {
    let a3: I2cAddr = d3.value;
    if a3.address != 256 { ok = false; }
  }
  let d4 = i2c_addr10_from_bytes(246, 247);
  if !d4.is_ok { ok = false; } else {
    let a4: I2cAddr = d4.value;
    if a4.address != 1015 { ok = false; }
    if a4.read { ok = false; }
  }
  if !err_addr_is(i2c_addr10_from_bytes(239, 0), "i2c: bad 10-bit address lead byte (239)") { ok = false; }
  if !err_addr_is(i2c_addr10_from_bytes(248, 0), "i2c: bad 10-bit address lead byte (248)") { ok = false; }
  if !err_addr_is(i2c_addr10_from_bytes(244, 256), "i2c: address byte out of range (256)") { ok = false; }
  if !err_addr_is(i2c_addr10_from_bytes(240, 7), "i2c: reserved 10-bit address (7)") { ok = false; }
  return assert(ok, "10-bit decode round-trips and rejects bad lead/reserved bytes");
}

// --------------------------------------------------
//  Event model tests
// --------------------------------------------------

fn t6() -> TestResult {
  var t = i2c_txn_new();
  var ok = i2c_txn_len(&t) == 0;
  i2c_txn_push_start(&mut t);
  let p1 = i2c_txn_push_addr7(&mut t, 80, false);
  if !p1.is_ok { ok = false; }
  i2c_txn_push_ack(&mut t);
  i2c_txn_push_stop(&mut t);
  if i2c_txn_len(&t) != 4 { ok = false; }
  if i2c_txn_kind(&t, 0) != I2C_EV_START { ok = false; }
  if i2c_txn_kind(&t, 1) != I2C_EV_ADDR7_W { ok = false; }
  if i2c_txn_kind(&t, 2) != I2C_EV_ACK { ok = false; }
  if i2c_txn_kind(&t, 3) != I2C_EV_STOP { ok = false; }
  if i2c_txn_value(&t, 0) != 0 { ok = false; }
  if i2c_txn_value(&t, 1) != 80 { ok = false; }
  if i2c_txn_value(&t, 2) != 0 { ok = false; }
  if i2c_txn_kind(&t, -1) != -1 { ok = false; }
  if i2c_txn_kind(&t, 4) != -1 { ok = false; }
  if i2c_txn_value(&t, -1) != -1 { ok = false; }
  if i2c_txn_value(&t, 9) != -1 { ok = false; }
  var u = i2c_txn_new();
  i2c_txn_push_start(&mut u);
  let up1 = i2c_txn_push_addr7(&mut u, 80, false);
  i2c_txn_push_ack(&mut u);
  i2c_txn_push_stop(&mut u);
  if !up1.is_ok { ok = false; }
  let er = i2c_txn_push_addr7(&mut u, 3, false);
  if er.is_ok { ok = false; }
  if i2c_txn_len(&u) != 4 { ok = false; }
  return assert(ok, "builders append mirrored events; accessors and atomic Err");
}

fn t7() -> TestResult {
  var w = i2c_txn_new();
  i2c_txn_push_start(&mut w);
  let wp = i2c_txn_push_addr7(&mut w, 80, false);
  i2c_txn_push_ack(&mut w);
  let wd = i2c_txn_push_data(&mut w, 1);
  i2c_txn_push_ack(&mut w);
  i2c_txn_push_stop(&mut w);
  var ok = wp.is_ok && wd.is_ok;
  if !i2c_txn_validate(&w).is_ok { ok = false; }
  var r = i2c_txn_new();
  i2c_txn_push_start(&mut r);
  let rp = i2c_txn_push_addr7(&mut r, 80, true);
  i2c_txn_push_ack(&mut r);
  let rd = i2c_txn_push_data(&mut r, 66);
  i2c_txn_push_nack(&mut r);
  i2c_txn_push_stop(&mut r);
  if !rp.is_ok || !rd.is_ok { ok = false; }
  if !i2c_txn_validate(&r).is_ok { ok = false; }
  if !str_eq(i2c_kind_name(I2C_EV_START), "START") { ok = false; }
  if !str_eq(i2c_kind_name(I2C_EV_RSTART), "repeated START") { ok = false; }
  if !str_eq(i2c_kind_name(I2C_EV_STOP), "STOP") { ok = false; }
  if !str_eq(i2c_kind_name(I2C_EV_ADDR7_W), "7-bit address write") { ok = false; }
  if !str_eq(i2c_kind_name(I2C_EV_ADDR7_R), "7-bit address read") { ok = false; }
  if !str_eq(i2c_kind_name(I2C_EV_ADDR10_W), "10-bit address write") { ok = false; }
  if !str_eq(i2c_kind_name(I2C_EV_ADDR10_R), "10-bit address read") { ok = false; }
  if !str_eq(i2c_kind_name(I2C_EV_DATA), "data byte") { ok = false; }
  if !str_eq(i2c_kind_name(I2C_EV_ACK), "ACK") { ok = false; }
  if !str_eq(i2c_kind_name(I2C_EV_NACK), "NACK") { ok = false; }
  if !str_eq(i2c_kind_name(0), "unknown event") { ok = false; }
  if !str_eq(i2c_kind_name(11), "unknown event") { ok = false; }
  return assert(ok, "well-formed write/read transactions validate; kind names");
}

fn t8() -> TestResult {
  let empty = i2c_txn_new();
  var ok = err_unit_is(i2c_txn_validate(&empty), "i2c: empty transaction");
  let one = txn(iv1(I2C_EV_START), iv1(0));
  if !err_unit_is(i2c_txn_validate(&one), "i2c: event 0: transaction must end with STOP") { ok = false; }
  let no_start = txn(iv3(I2C_EV_ADDR7_W, I2C_EV_ACK, I2C_EV_STOP), iv3(80, 0, 0));
  if !err_unit_is(i2c_txn_validate(&no_start), "i2c: event 0: transaction must begin with START") { ok = false; }
  var sp = i2c_txn_new();
  i2c_txn_push_start(&mut sp);
  i2c_txn_push_stop(&mut sp);
  if !err_unit_is(i2c_txn_validate(&sp), "i2c: event 0: START or repeated START not followed by an address event") { ok = false; }
  var rr = i2c_txn_new();
  i2c_txn_push_start(&mut rr);
  let rp1 = i2c_txn_push_addr7(&mut rr, 80, false);
  i2c_txn_push_ack(&mut rr);
  i2c_txn_push_rstart(&mut rr);
  let rp2 = i2c_txn_push_addr7(&mut rr, 80, true);
  i2c_txn_push_ack(&mut rr);
  i2c_txn_push_stop(&mut rr);
  if !rp1.is_ok || !rp2.is_ok { ok = false; }
  if !i2c_txn_validate(&rr).is_ok { ok = false; }
  return assert(ok, "validation: empty, single event, missing START, START with no address");
}

fn t9() -> TestResult {
  var a = i2c_txn_new();
  i2c_txn_push_start(&mut a);
  let ap = i2c_txn_push_addr7(&mut a, 80, false);
  i2c_txn_push_stop(&mut a);
  var ok = ap.is_ok;
  if !err_unit_is(i2c_txn_validate(&a), "i2c: event 1: address or data event not followed by ACK or NACK") { ok = false; }
  var b = i2c_txn_new();
  i2c_txn_push_start(&mut b);
  let bp = i2c_txn_push_addr7(&mut b, 80, false);
  i2c_txn_push_ack(&mut b);
  i2c_txn_push_ack(&mut b);
  i2c_txn_push_stop(&mut b);
  if !bp.is_ok { ok = false; }
  if !err_unit_is(i2c_txn_validate(&b), "i2c: event 3: ACK or NACK without a preceding byte event") { ok = false; }
  var c = i2c_txn_new();
  i2c_txn_push_start(&mut c);
  let cp = i2c_txn_push_addr7(&mut c, 80, false);
  i2c_txn_push_ack(&mut c);
  i2c_txn_push_start(&mut c);
  let cp2 = i2c_txn_push_addr7(&mut c, 80, false);
  i2c_txn_push_ack(&mut c);
  i2c_txn_push_stop(&mut c);
  if !cp.is_ok || !cp2.is_ok { ok = false; }
  if !err_unit_is(i2c_txn_validate(&c), "i2c: event 3: START after position 0 (use repeated START)") { ok = false; }
  var d = i2c_txn_new();
  i2c_txn_push_start(&mut d);
  let dp = i2c_txn_push_addr7(&mut d, 80, false);
  i2c_txn_push_ack(&mut d);
  i2c_txn_push_rstart(&mut d);
  i2c_txn_push_stop(&mut d);
  if !dp.is_ok { ok = false; }
  if !err_unit_is(i2c_txn_validate(&d), "i2c: event 3: START or repeated START not followed by an address event") { ok = false; }
  var e = i2c_txn_new();
  i2c_txn_push_start(&mut e);
  let ep = i2c_txn_push_addr7(&mut e, 80, false);
  i2c_txn_push_ack(&mut e);
  i2c_txn_push_stop(&mut e);
  i2c_txn_push_rstart(&mut e);
  let ep2 = i2c_txn_push_addr7(&mut e, 80, true);
  i2c_txn_push_ack(&mut e);
  i2c_txn_push_stop(&mut e);
  if !ep.is_ok || !ep2.is_ok { ok = false; }
  if !err_unit_is(i2c_txn_validate(&e), "i2c: event 3: STOP before the end of the transaction") { ok = false; }
  return assert(ok, "validation: ACK framing, START placement, STOP placement, repeated START");
}

fn t10() -> TestResult {
  let ctrl = txn(iv4(I2C_EV_START, I2C_EV_ADDR7_W, I2C_EV_ACK, I2C_EV_STOP), iv4(1, 80, 0, 0));
  var ok = err_unit_is(i2c_txn_validate(&ctrl), "i2c: event 0: control event carries a value (1)");
  let res7 = txn(iv4(I2C_EV_START, I2C_EV_ADDR7_W, I2C_EV_ACK, I2C_EV_STOP), iv4(0, 3, 0, 0));
  if !err_unit_is(i2c_txn_validate(&res7), "i2c: event 1: reserved 7-bit address (3)") { ok = false; }
  let res10 = txn(iv4(I2C_EV_START, I2C_EV_ADDR10_R, I2C_EV_ACK, I2C_EV_STOP), iv4(0, 1016, 0, 0));
  if !err_unit_is(i2c_txn_validate(&res10), "i2c: event 1: reserved 10-bit address (1016)") { ok = false; }
  let big10 = txn(iv4(I2C_EV_START, I2C_EV_ADDR10_R, I2C_EV_ACK, I2C_EV_STOP), iv4(0, 1024, 0, 0));
  if !err_unit_is(i2c_txn_validate(&big10), "i2c: event 1: 10-bit address out of range (1024)") { ok = false; }
  let bigdata = txn(iv6(I2C_EV_START, I2C_EV_ADDR7_W, I2C_EV_ACK, I2C_EV_DATA, I2C_EV_ACK, I2C_EV_STOP), iv6(0, 80, 0, 256, 0, 0));
  if !err_unit_is(i2c_txn_validate(&bigdata), "i2c: event 3: data byte out of range (256)") { ok = false; }
  let negdata = txn(iv6(I2C_EV_START, I2C_EV_ADDR7_W, I2C_EV_ACK, I2C_EV_DATA, I2C_EV_ACK, I2C_EV_STOP), iv6(0, 80, 0, -1, 0, 0));
  if !err_unit_is(i2c_txn_validate(&negdata), "i2c: event 3: data byte out of range (-1)") { ok = false; }
  let badkind = txn(iv6(I2C_EV_START, I2C_EV_ADDR7_W, I2C_EV_ACK, 11, I2C_EV_ACK, I2C_EV_STOP), iv6(0, 80, 0, 0, 0, 0));
  if !err_unit_is(i2c_txn_validate(&badkind), "i2c: event 3: invalid event kind (11)") { ok = false; }
  let skew = txn(iv4(I2C_EV_START, I2C_EV_ADDR7_W, I2C_EV_ACK, I2C_EV_STOP), iv3(0, 80, 0));
  if !err_unit_is(i2c_txn_validate(&skew), "i2c: event arrays out of step (4 kinds, 3 values)") { ok = false; }
  return assert(ok, "validation: value ranges, reserved addresses, kind range, array skew");
}

// --------------------------------------------------
//  Event-stream codec tests
// --------------------------------------------------

fn t11() -> TestResult {
  var w = i2c_txn_new();
  i2c_txn_push_start(&mut w);
  let p1 = i2c_txn_push_addr7(&mut w, 80, false);
  i2c_txn_push_ack(&mut w);
  let p2 = i2c_txn_push_data(&mut w, 1);
  i2c_txn_push_ack(&mut w);
  i2c_txn_push_stop(&mut w);
  if !p1.is_ok || !p2.is_ok { return assert(false, "write transaction must build"); }
  var ok = i2c_txn_encoded_len(&w) == 8;
  let e1 = i2c_events_encode(&w);
  if !e1.is_ok { return assert(false, "write transaction must encode"); }
  let b1: Vec[UInt8] = e1.value;
  if !bytes_equal(b1, hb("0104500908010903")) { ok = false; }
  var r = i2c_txn_new();
  i2c_txn_push_start(&mut r);
  let q1 = i2c_txn_push_addr7(&mut r, 80, false);
  i2c_txn_push_ack(&mut r);
  let q2 = i2c_txn_push_data(&mut r, 1);
  i2c_txn_push_ack(&mut r);
  i2c_txn_push_rstart(&mut r);
  let q3 = i2c_txn_push_addr7(&mut r, 80, true);
  i2c_txn_push_ack(&mut r);
  let q4 = i2c_txn_push_data(&mut r, 66);
  i2c_txn_push_nack(&mut r);
  i2c_txn_push_stop(&mut r);
  if !q1.is_ok || !q2.is_ok || !q3.is_ok || !q4.is_ok { ok = false; }
  if i2c_txn_encoded_len(&r) != 15 { ok = false; }
  let e2 = i2c_events_encode(&r);
  if !e2.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = e2.value;
    if !bytes_equal(b2, hb("010450090801090205500908420a03")) { ok = false; }
  }
  if i2c_event_encoded_len(I2C_EV_START) != 1 { ok = false; }
  if i2c_event_encoded_len(I2C_EV_ADDR7_W) != 2 { ok = false; }
  if i2c_event_encoded_len(I2C_EV_DATA) != 2 { ok = false; }
  if i2c_event_encoded_len(I2C_EV_ADDR10_R) != 3 { ok = false; }
  if i2c_event_encoded_len(0) != -1 { ok = false; }
  if i2c_event_encoded_len(11) != -1 { ok = false; }
  return assert(ok, "write and repeated-START read encode to pinned streams");
}

fn t12() -> TestResult {
  var t = i2c_txn_new();
  i2c_txn_push_start(&mut t);
  let p1 = i2c_txn_push_addr10(&mut t, 675, true);
  i2c_txn_push_ack(&mut t);
  let p2 = i2c_txn_push_data(&mut t, 171);
  i2c_txn_push_ack(&mut t);
  i2c_txn_push_stop(&mut t);
  if !p1.is_ok || !p2.is_ok { return assert(false, "10-bit read must build"); }
  var ok = i2c_txn_kind(&t, 1) == I2C_EV_ADDR10_R;
  if i2c_txn_value(&t, 1) != 675 { ok = false; }
  if i2c_txn_encoded_len(&t) != 9 { ok = false; }
  let e1 = i2c_events_encode(&t);
  if !e1.is_ok { return assert(false, "10-bit read must encode"); }
  let b1: Vec[UInt8] = e1.value;
  if !bytes_equal(b1, hb("010702a30908ab0903")) { ok = false; }
  var w = i2c_txn_new();
  i2c_txn_push_start(&mut w);
  let p3 = i2c_txn_push_addr10(&mut w, 675, false);
  i2c_txn_push_ack(&mut w);
  i2c_txn_push_stop(&mut w);
  if !p3.is_ok { ok = false; } else {
    if i2c_txn_kind(&w, 1) != I2C_EV_ADDR10_W { ok = false; }
    let e2 = i2c_events_encode(&w);
    if !e2.is_ok { ok = false; } else {
      let b2: Vec[UInt8] = e2.value;
      if !bytes_equal(b2, hb("010602a30903")) { ok = false; }
    }
  }
  return assert(ok, "10-bit address events: two payload bytes, high then low");
}

fn t13() -> TestResult {
  var w = i2c_txn_new();
  i2c_txn_push_start(&mut w);
  let p1 = i2c_txn_push_addr7(&mut w, 80, false);
  i2c_txn_push_ack(&mut w);
  let p2 = i2c_txn_push_data(&mut w, 1);
  i2c_txn_push_ack(&mut w);
  i2c_txn_push_stop(&mut w);
  if !p1.is_ok || !p2.is_ok { return assert(false, "transaction must build"); }
  let e1 = i2c_events_encode(&w);
  if !e1.is_ok { return assert(false, "transaction must encode"); }
  let b1: Vec[UInt8] = e1.value;
  let d1 = i2c_events_decode(&b1);
  if !d1.is_ok { return assert(false, "encoded stream must decode"); }
  let dw: I2cTransaction = d1.value;
  var ok = i2c_txn_equal(&w, &dw);
  let pinned = hb("0104500908010903");
  let d2 = i2c_events_decode(&pinned);
  if !d2.is_ok { ok = false; } else {
    let dp: I2cTransaction = d2.value;
    if !i2c_txn_equal(&w, &dp) { ok = false; }
    if i2c_txn_kind(&dp, 1) != I2C_EV_ADDR7_W { ok = false; }
    if i2c_txn_value(&dp, 1) != 80 { ok = false; }
    if i2c_txn_value(&dp, 3) != 1 { ok = false; }
    if i2c_txn_len(&dp) != 6 { ok = false; }
  }
  var r = i2c_txn_new();
  i2c_txn_push_start(&mut r);
  let r1 = i2c_txn_push_addr10(&mut r, 675, true);
  i2c_txn_push_ack(&mut r);
  i2c_txn_push_rstart(&mut r);
  let r2 = i2c_txn_push_addr10(&mut r, 675, false);
  i2c_txn_push_ack(&mut r);
  let r3 = i2c_txn_push_data(&mut r, 0);
  i2c_txn_push_ack(&mut r);
  i2c_txn_push_stop(&mut r);
  if !r1.is_ok || !r2.is_ok || !r3.is_ok { ok = false; }
  let e2 = i2c_events_encode(&r);
  if !e2.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = e2.value;
    let d3 = i2c_events_decode(&b2);
    if !d3.is_ok { ok = false; } else {
      let dr: I2cTransaction = d3.value;
      if !i2c_txn_equal(&r, &dr) { ok = false; }
    }
  }
  return assert(ok, "encode -> decode round-trips the write and 10-bit read transactions");
}

fn t14() -> TestResult {
  let none = Vec[UInt8].new();
  var ok = err_txn_is(i2c_events_decode(&none), "i2c: empty transaction");
  let trunc7 = hb("0104");
  if !err_txn_is(i2c_events_decode(&trunc7), "i2c: truncated event at byte 1") { ok = false; }
  let trunc10 = hb("010702");
  if !err_txn_is(i2c_events_decode(&trunc10), "i2c: truncated event at byte 1") { ok = false; }
  let unk = hb("0163");
  if !err_txn_is(i2c_events_decode(&unk), "i2c: unknown event tag (99) at byte 1") { ok = false; }
  let nostop = hb("010450");
  if !err_txn_is(i2c_events_decode(&nostop), "i2c: event 1: transaction must end with STOP") { ok = false; }
  let nostop2 = hb("01045009");
  if !err_txn_is(i2c_events_decode(&nostop2), "i2c: event 2: transaction must end with STOP") { ok = false; }
  let quick = hb("0104500903");
  if !i2c_events_decode(&quick).is_ok { ok = false; }
  let reserved = hb("0104000903");
  if !err_txn_is(i2c_events_decode(&reserved), "i2c: event 1: reserved 7-bit address (0)") { ok = false; }
  return assert(ok, "decode error catalog: empty, truncation, unknown tag, framing");
}

fn t15() -> TestResult {
  let empty = i2c_txn_new();
  var ok = err_bytes_is(i2c_events_encode(&empty), "i2c: empty transaction");
  let bad = txn(iv4(I2C_EV_START, I2C_EV_ADDR7_W, I2C_EV_ACK, I2C_EV_STOP), iv4(1, 80, 0, 0));
  if !err_bytes_is(i2c_events_encode(&bad), "i2c: event 0: control event carries a value (1)") { ok = false; }
  var out = Vec[UInt8].new();
  out.push(170);
  let er = i2c_events_encode_into(&mut out, &bad);
  if er.is_ok { ok = false; }
  if out.len() != 1 { ok = false; }
  let b0: Int = (out[0] as Int) & 0xFF;
  if b0 != 170 { ok = false; }
  var w = i2c_txn_new();
  i2c_txn_push_start(&mut w);
  let p1 = i2c_txn_push_addr7(&mut w, 80, false);
  i2c_txn_push_ack(&mut w);
  let p2 = i2c_txn_push_data(&mut w, 1);
  i2c_txn_push_ack(&mut w);
  i2c_txn_push_stop(&mut w);
  if !p1.is_ok || !p2.is_ok { ok = false; }
  let er2 = i2c_events_encode_into(&mut out, &w);
  if !er2.is_ok { ok = false; }
  if out.len() != 9 { ok = false; }
  let b1: Int = (out[1] as Int) & 0xFF;
  if b1 != 1 { ok = false; }
  let b8: Int = (out[8] as Int) & 0xFF;
  if b8 != 3 { ok = false; }
  return assert(ok, "encode_into appends on success and leaves out untouched on Err");
}

// --------------------------------------------------
//  SMBus PEC tests
// --------------------------------------------------

fn t16() -> TestResult {
  let check = bytes_of("123456789");
  var ok = i2c_pec(&check) == 244;
  if ref_pec(&check) != 244 { ok = false; }
  let empty = Vec[UInt8].new();
  if i2c_pec(&empty) != 0 { ok = false; }
  if ref_pec(&empty) != 0 { ok = false; }
  let zero = hb("00");
  if i2c_pec(&zero) != 0 { ok = false; }
  if ref_pec(&zero) != 0 { ok = false; }
  let ff = hb("ff");
  if i2c_pec(&ff) != 243 { ok = false; }
  if ref_pec(&ff) != 243 { ok = false; }
  let hi = high_bytes();
  if i2c_pec(&hi) != ref_pec(&hi) { ok = false; }
  let pat = pattern_300();
  if i2c_pec(&pat) != ref_pec(&pat) { ok = false; }
  let a1 = hb("a04401");
  if i2c_pec(&a1) != ref_pec(&a1) { ok = false; }
  return assert(ok, "PEC: catalogue 0xF4 check, empty init, long-buffer reference agreement");
}

fn t17() -> TestResult {
  let body = hb("a04401");
  let covered = i2c_pec_cover(&body);
  var ok = covered.len() == 4;
  let c = i2c_pec(&body);
  if i2c_pec(&covered) != 0 { ok = false; }
  let cv: Int = (covered[3] as Int) & 0xFF;
  if cv != c { ok = false; }
  let vr = i2c_pec_verify(&covered);
  if !vr.is_ok { ok = false; }
  let none = Vec[UInt8].new();
  if !err_unit_is(i2c_pec_verify(&none), "i2c: short pec frame (0)") { ok = false; }
  let one = hb("01");
  if !err_unit_is(i2c_pec_verify(&one), "i2c: short pec frame (1)") { ok = false; }
  var bad = Vec[UInt8].new();
  bad.push(160);
  bad.push(68);
  bad.push(1);
  let wrong = (c + 1) % 256;
  bad.push(wrong as UInt8);
  let want = "i2c: bad pec (computed " + int_to_string(c) + ", received " + int_to_string(wrong) + ")";
  if !err_unit_is(i2c_pec_verify(&bad), want) { ok = false; }
  return assert(ok, "PEC cover appends the checksum; verify accepts it and reports mismatches");
}

// --------------------------------------------------
//  SMBus helper and pipeline tests
// --------------------------------------------------

fn t18() -> TestResult {
  let q = smbus_quick(80, false);
  if !q.is_ok { return assert(false, "smbus_quick must build"); }
  let qt: I2cTransaction = q.value;
  var ok = i2c_txn_len(&qt) == 4;
  if i2c_txn_kind(&qt, 0) != I2C_EV_START { ok = false; }
  if i2c_txn_kind(&qt, 1) != I2C_EV_ADDR7_W { ok = false; }
  if i2c_txn_kind(&qt, 2) != I2C_EV_ACK { ok = false; }
  if i2c_txn_kind(&qt, 3) != I2C_EV_STOP { ok = false; }
  if i2c_txn_value(&qt, 1) != 80 { ok = false; }
  if !i2c_txn_validate(&qt).is_ok { ok = false; }
  let qe = i2c_events_encode(&qt);
  if !qe.is_ok { ok = false; } else {
    let qb: Vec[UInt8] = qe.value;
    if !bytes_equal(qb, hb("0104500903")) { ok = false; }
  }
  let qr = smbus_quick(80, true);
  if !qr.is_ok { ok = false; } else {
    let qrt: I2cTransaction = qr.value;
    if i2c_txn_kind(&qrt, 1) != I2C_EV_ADDR7_R { ok = false; }
  }
  let s = smbus_send_byte(80, 66);
  if !s.is_ok { ok = false; } else {
    let st: I2cTransaction = s.value;
    if i2c_txn_len(&st) != 6 { ok = false; }
    if i2c_txn_value(&st, 3) != 66 { ok = false; }
    if !i2c_txn_validate(&st).is_ok { ok = false; }
    let se = i2c_events_encode(&st);
    if !se.is_ok { ok = false; } else {
      let sb: Vec[UInt8] = se.value;
      if !bytes_equal(sb, hb("0104500908420903")) { ok = false; }
    }
  }
  if !err_txn_is(smbus_quick(0, false), "i2c: reserved 7-bit address (0)") { ok = false; }
  if !err_txn_is(smbus_quick(128, true), "i2c: 7-bit address out of range (128)") { ok = false; }
  if !err_txn_is(smbus_send_byte(80, 256), "i2c: data byte out of range (256)") { ok = false; }
  return assert(ok, "SMBus quick/send-byte builders and their error propagation");
}

fn t19() -> TestResult {
  let a = smbus_quick(80, false);
  let b = smbus_quick(80, false);
  if !a.is_ok || !b.is_ok { return assert(false, "quick transactions must build"); }
  let ta: I2cTransaction = a.value;
  let tb: I2cTransaction = b.value;
  var ok = i2c_txn_equal(&ta, &tb);
  let empty1 = i2c_txn_new();
  let empty2 = i2c_txn_new();
  if !i2c_txn_equal(&empty1, &empty2) { ok = false; }
  let s = smbus_send_byte(80, 66);
  if !s.is_ok { ok = false; } else {
    let ts: I2cTransaction = s.value;
    if i2c_txn_equal(&ta, &ts) { ok = false; }
  }
  let ea = i2c_events_encode(&ta);
  let eb = i2c_events_encode(&tb);
  if !ea.is_ok || !eb.is_ok { ok = false; } else {
    let xa: Vec[UInt8] = ea.value;
    let xb: Vec[UInt8] = eb.value;
    if !bytes_equal(xa, xb) { ok = false; }
    let da = i2c_events_decode(&xa);
    let db = i2c_events_decode(&xb);
    if !da.is_ok || !db.is_ok { ok = false; } else {
      let da1: I2cTransaction = da.value;
      let db1: I2cTransaction = db.value;
      if !i2c_txn_equal(&da1, &db1) { ok = false; }
      if !i2c_txn_equal(&ta, &da1) { ok = false; }
    }
  }
  return assert(ok, "equality and determinism: identical builds and repeated decodes agree");
}

fn t20() -> TestResult {
  let s = smbus_send_byte(80, 66);
  if !s.is_ok { return assert(false, "send byte must build"); }
  let ts: I2cTransaction = s.value;
  let se = i2c_events_encode(&ts);
  if !se.is_ok { return assert(false, "send byte must encode"); }
      let sb: Vec[UInt8] = se.value;
  let sd = i2c_events_decode(&sb);
  if !sd.is_ok { return assert(false, "encoded send byte must decode"); }
  let td: I2cTransaction = sd.value;
  var ok = i2c_txn_equal(&ts, &td);
  if i2c_txn_kind(&td, 0) != I2C_EV_START { ok = false; }
  if i2c_txn_kind(&td, 5) != I2C_EV_STOP { ok = false; }
  var r = i2c_txn_new();
  i2c_txn_push_start(&mut r);
  let r1 = i2c_txn_push_addr10(&mut r, 675, true);
  i2c_txn_push_ack(&mut r);
  i2c_txn_push_rstart(&mut r);
  let r2 = i2c_txn_push_addr10(&mut r, 675, false);
  i2c_txn_push_ack(&mut r);
  let r3 = i2c_txn_push_data(&mut r, 0);
  i2c_txn_push_ack(&mut r);
  i2c_txn_push_stop(&mut r);
  if !r1.is_ok || !r2.is_ok || !r3.is_ok { ok = false; }
  if !i2c_txn_validate(&r).is_ok { ok = false; }
  let re = i2c_events_encode(&r);
  if !re.is_ok { ok = false; } else {
    let rb: Vec[UInt8] = re.value;
    if !bytes_equal(rb, hb("010702a309020602a30908000903")) { ok = false; }
    let rd = i2c_events_decode(&rb);
    if !rd.is_ok { ok = false; } else {
      let rt: I2cTransaction = rd.value;
      if !i2c_txn_equal(&r, &rt) { ok = false; }
    }
  }
  if !str_eq(i2c_kind_name(I2C_EV_ADDR10_R), "10-bit address read") { ok = false; }
  return assert(ok, "pipeline: SMBus send byte and 10-bit repeated-START stream end to end");
}

fn main() -> Int {
  io.println("=== xiom.i2c conformance tests ===");
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
    io.println("xiom.i2c: all tests passed");
  } else {
    io.println("xiom.i2c: tests failed");
  }
  return failed;
}
