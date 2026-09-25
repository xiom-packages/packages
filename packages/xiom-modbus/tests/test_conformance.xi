// XIOM -- xiom.modbus conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.modbus codec against the documented
// PDU, RTU (CRC-16/Modbus) and TCP (MBAP) layouts, the function 03/06 and
// exception codecs, and the full error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every pinned byte string and checksum below was cross-checked against an
// independent CRC-16/Modbus implementation (bitwise reflected poly 0xA001,
// init 0xFFFF) and the published example frame 01 03 00 00 00 0A C5 CD; the
// catalogue check value "123456789" is 0x4B37 (19255). t2 additionally
// cross-checks the module CRC against a test-local implementation written
// in the mirrored formulation (reflect each input byte, MSB-first poly
// 0x8005, reflect the 16-bit result) so an error in the module's shift/XOR
// direction cannot pass unnoticed.
//
// BUG 17 discipline: no Str value is ever compared with `==`; error
// messages go through xiom.string.compare.str_compare. All Vec element
// reads are bound to typed locals.

module modbus_tests
use xiom.io; use xiom.test;
use xiom.modbus;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers (independent of src/modbus.xi)
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
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn ints_equal(a: Vec[Int], b: Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
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

// ff 00 80 7f 01: exercises byte widening for values with bit 7 set.
fn high_bytes() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(255);
  v.push(0);
  v.push(128);
  v.push(127);
  v.push(1);
  return v;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_pdu_is(r: Result[ModbusPdu, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_rtu_is(r: Result[ModbusRtuFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_tcp_is(r: Result[ModbusTcpFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_read_is(r: Result[ReadHoldingRegistersRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_write_is(r: Result[WriteSingleRegister, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_exc_is(r: Result[ModbusException, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_regs_is(r: Result[Vec[Int], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  Test-local CRC-16/Modbus reference (mirrored formulation)
// --------------------------------------------------

fn reflect8(v: Int) -> Int {
  var out = 0;
  var x = v;
  var i = 0;
  while i < 8 {
    out = out * 2 + (x & 1);
    x = x >> 1;
    i = i + 1;
  }
  return out;
}

fn reflect16(v: Int) -> Int {
  var out = 0;
  var x = v;
  var i = 0;
  while i < 16 {
    out = out * 2 + (x & 1);
    x = x >> 1;
    i = i + 1;
  }
  return out;
}

// CRC-16/Modbus in the mirrored formulation: reflect each input byte,
// process MSB-first with the normal polynomial 0x8005, reflect the result.
// Mathematically equal to the module's reflected-poly loop, but a
// different code path.
fn ref_crc16(data: &Vec[UInt8]) -> Int {
  var reg = 65535;
  var i = 0;
  while i < data.len() {
    let b: Int = (data[i] as Int) & 0xFF;
    reg = reg ^ (reflect8(b) << 8);
    var j = 0;
    while j < 8 {
      if reg >= 32768 {
        reg = ((reg << 1) ^ 32773) % 65536;
      } else {
        reg = (reg << 1) % 65536;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return reflect16(reg);
}

// Raw RTU frame from address and PDU bytes, CRC appended low byte first.
// Uses the test-local reference CRC, so malformed fixtures (bad address,
// wrong function) are not built with the implementation under test.
fn raw_rtu(addr: Int, pdu_bytes: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(addr as UInt8);
  var i = 0;
  while i < pdu_bytes.len() {
    out.push(pdu_bytes[i]);
    i = i + 1;
  }
  let crc = ref_crc16(&out);
  out.push((crc % 256) as UInt8);
  out.push(((crc / 256) % 256) as UInt8);
  return out;
}

// Raw TCP ADU with caller-chosen MBAP fields, so malformed headers (bad
// protocol id, wrong length) can be built.
fn raw_tcp_full(tid: Int, proto: Int, length: Int, unit: Int, pdu_bytes: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(((tid / 256) % 256) as UInt8);
  out.push((tid % 256) as UInt8);
  out.push(((proto / 256) % 256) as UInt8);
  out.push((proto % 256) as UInt8);
  out.push(((length / 256) % 256) as UInt8);
  out.push((length % 256) as UInt8);
  out.push(unit as UInt8);
  var i = 0;
  while i < pdu_bytes.len() {
    out.push(pdu_bytes[i]);
    i = i + 1;
  }
  return out;
}

// Raw TCP ADU with a correct protocol id and correct length.
fn raw_tcp(tid: Int, unit: Int, pdu_bytes: Vec[UInt8]) -> Vec[UInt8] {
  return raw_tcp_full(tid, 0, 1 + pdu_bytes.len(), unit, pdu_bytes);
}

// Register vector 0, 2, 4, ... (n values), used for 125-register frames.
fn even_regs(n: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < n {
    v.push(i * 2);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  CRC tests
// --------------------------------------------------

fn t1() -> TestResult {
  let check = bytes_of("123456789");
  var ok = modbus_crc16(&check) == 19255;
  var empty = Vec[UInt8].new();
  if modbus_crc16(&empty) != 65535 { ok = false; }
  let z = hb("00");
  if modbus_crc16(&z) != 16575 { ok = false; }
  let zz = hb("0000");
  if modbus_crc16(&zz) != 45057 { ok = false; }
  let f3 = hb("ffffff");
  if modbus_crc16(&f3) != 16448 { ok = false; }
  let r4 = hb("010304000a0102");
  if modbus_crc16(&r4) != 24666 { ok = false; }
  return assert(ok, "crc published vectors: 0x4B37 check, empty init, pinned buffers");
}

fn t2() -> TestResult {
  let p = pattern_300();
  var ok = modbus_crc16(&p) == 62621;
  if ref_crc16(&p) != 62621 { ok = false; }
  let h = high_bytes();
  if modbus_crc16(&h) != 3280 { ok = false; }
  if ref_crc16(&h) != 3280 { ok = false; }
  if modbus_crc16(&h) != ref_crc16(&h) { ok = false; }
  let a1 = hb("01030000000a");
  if modbus_crc16(&a1) != ref_crc16(&a1) { ok = false; }
  let a2 = hb("018302");
  if modbus_crc16(&a2) != ref_crc16(&a2) { ok = false; }
  let a3 = hb("f703ffff007d");
  if modbus_crc16(&a3) != ref_crc16(&a3) { ok = false; }
  return assert(ok, "crc matches the mirrored reference on 300-byte and high-bit buffers");
}

// --------------------------------------------------
//  PDU codec tests
// --------------------------------------------------

fn t3() -> TestResult {
  var d = Vec[UInt8].new();
  d.push(0);
  d.push(0);
  d.push(0);
  d.push(10);
  let p = ModbusPdu{ function: 3; data: d; };
  var ok = pdu_function(&p) == 3;
  if pdu_data_len(&p) != 4 { ok = false; }
  if pdu_is_exception(&p) { ok = false; }
  let er = pdu_encode(&p);
  if !er.is_ok { return assert(false, "pdu_encode must succeed"); }
  let enc: Vec[UInt8] = er.value;
  if !bytes_equal(enc, hb("030000000a")) { ok = false; }
  let dr = pdu_decode(&enc);
  if !dr.is_ok { ok = false; } else {
    let q: ModbusPdu = dr.value;
    if pdu_function(&q) != 3 { ok = false; }
    if pdu_data_len(&q) != 4 { ok = false; }
    let qd: Vec[UInt8] = q.data;
    if !bytes_equal(qd, hb("0000000a")) { ok = false; }
  }
  var empty = Vec[UInt8].new();
  let bare = ModbusPdu{ function: 131; data: empty; };
  if !pdu_is_exception(&bare) { ok = false; }
  let ber = pdu_encode(&bare);
  if !ber.is_ok { ok = false; } else {
    let be: Vec[UInt8] = ber.value;
    if !bytes_equal(be, hb("83")) { ok = false; }
  }
  return assert(ok, "pdu encode/decode round-trip and accessors");
}

fn t4() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_pdu_is(pdu_decode(&empty), "modbus: empty pdu");
  let neg = ModbusPdu{ function: -1; data: Vec[UInt8].new() };
  if !err_bytes_is(pdu_encode(&neg), "modbus: invalid function code") { ok = false; }
  let big = ModbusPdu{ function: 256; data: Vec[UInt8].new() };
  if !err_bytes_is(pdu_encode(&big), "modbus: invalid function code") { ok = false; }
  let over = ModbusPdu{ function: 3; data: repeat_byte(7, 253) };
  if !err_bytes_is(pdu_encode(&over), "modbus: pdu too long") { ok = false; }
  let maxp = ModbusPdu{ function: 3; data: repeat_byte(7, 252) };
  let mr = pdu_encode(&maxp);
  if !mr.is_ok { ok = false; } else {
    let me: Vec[UInt8] = mr.value;
    if me.len() != 253 { ok = false; }
  }
  let long = repeat_byte(0, 254);
  if !err_pdu_is(pdu_decode(&long), "modbus: pdu too long") { ok = false; }
  let maxbuf = repeat_byte(0, 253);
  let md = pdu_decode(&maxbuf);
  if !md.is_ok { ok = false; } else {
    let mp: ModbusPdu = md.value;
    if pdu_data_len(&mp) != 252 { ok = false; }
  }
  return assert(ok, "pdu error catalog: empty, invalid function, too long");
}

// --------------------------------------------------
//  RTU framing tests
// --------------------------------------------------

fn t5() -> TestResult {
  let r1 = read_holding_registers_request_pdu(0, 10);
  if !r1.is_ok { return assert(false, "fc03 request must build"); }
  let p1: ModbusPdu = r1.value;
  let e1 = rtu_encode(1, &p1);
  if !e1.is_ok { return assert(false, "rtu encode must succeed"); }
  let f1: Vec[UInt8] = e1.value;
  var ok = bytes_equal(f1, hb("01030000000ac5cd"));
  if f1.len() != 8 { ok = false; }
  let r2 = read_holding_registers_request_pdu(107, 3);
  if !r2.is_ok { ok = false; } else {
    let p2: ModbusPdu = r2.value;
    let e2 = rtu_encode(1, &p2);
    if !e2.is_ok { ok = false; } else {
      let f2: Vec[UInt8] = e2.value;
      if !bytes_equal(f2, hb("0103006b00037417")) { ok = false; }
    }
  }
  let r3 = write_single_register_request_pdu(16, 3);
  if !r3.is_ok { ok = false; } else {
    let p3: ModbusPdu = r3.value;
    let e3 = rtu_encode(17, &p3);
    if !e3.is_ok { ok = false; } else {
      let f3: Vec[UInt8] = e3.value;
      if !bytes_equal(f3, hb("110600100003ca9e")) { ok = false; }
    }
  }
  let r4 = exception_pdu(3, 2);
  if !r4.is_ok { ok = false; } else {
    let p4: ModbusPdu = r4.value;
    let e4 = rtu_encode(1, &p4);
    if !e4.is_ok { ok = false; } else {
      let f4: Vec[UInt8] = e4.value;
      if !bytes_equal(f4, hb("018302c0f1")) { ok = false; }
    }
  }
  let r5 = read_holding_registers_request_pdu(65411, 125);
  if !r5.is_ok { ok = false; } else {
    let p5: ModbusPdu = r5.value;
    let e5 = rtu_encode(247, &p5);
    if !e5.is_ok { ok = false; } else {
      let f5: Vec[UInt8] = e5.value;
      if !bytes_equal(f5, hb("f703ff83007d5081")) { ok = false; }
    }
  }
  return assert(ok, "rtu_encode pinned frames with CRC low byte first");
}

fn t6() -> TestResult {
  let f1 = hb("01030000000ac5cd");
  let d1 = rtu_decode(&f1);
  if !d1.is_ok { return assert(false, "pinned frame must decode"); }
  let fr1: ModbusRtuFrame = d1.value;
  var ok = fr1.address == 1;
  if pdu_function(&fr1.pdu) != 3 { ok = false; }
  let pd1: Vec[UInt8] = fr1.pdu.data;
  if !bytes_equal(pd1, hb("0000000a")) { ok = false; }
  let re1 = rtu_encode(fr1.address, &fr1.pdu);
  if !re1.is_ok { ok = false; } else {
    let rb1: Vec[UInt8] = re1.value;
    if !bytes_equal(rb1, f1) { ok = false; }
  }
  let f2 = hb("110600100003ca9e");
  let d2 = rtu_decode(&f2);
  if !d2.is_ok { ok = false; } else {
    let fr2: ModbusRtuFrame = d2.value;
    if fr2.address != 17 { ok = false; }
    if pdu_function(&fr2.pdu) != 6 { ok = false; }
    let pd2: Vec[UInt8] = fr2.pdu.data;
    if !bytes_equal(pd2, hb("00100003")) { ok = false; }
  }
  let f3 = hb("018302c0f1");
  let d3 = rtu_decode(&f3);
  if !d3.is_ok { ok = false; } else {
    let fr3: ModbusRtuFrame = d3.value;
    if pdu_function(&fr3.pdu) != 131 { ok = false; }
    if !pdu_is_exception(&fr3.pdu) { ok = false; }
  }
  let f4 = hb("f703ffff007d9159");
  let d4 = rtu_decode(&f4);
  if !d4.is_ok { ok = false; } else {
    let fr4: ModbusRtuFrame = d4.value;
    if fr4.address != 247 { ok = false; }
    let pd4: Vec[UInt8] = fr4.pdu.data;
    if !bytes_equal(pd4, hb("ffff007d")) { ok = false; }
  }
  return assert(ok, "rtu_decode round-trips pinned frames and re-encodes them");
}

fn t7() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_rtu_is(rtu_decode(&empty), "modbus: truncated rtu frame");
  let three = hb("010300");
  if !err_rtu_is(rtu_decode(&three), "modbus: truncated rtu frame") { ok = false; }
  let huge = repeat_byte(0, 257);
  if !err_rtu_is(rtu_decode(&huge), "modbus: rtu frame too long") { ok = false; }
  let badcrc = hb("01030000000ac5ce");
  if !err_rtu_is(rtu_decode(&badcrc), "modbus: bad crc") { ok = false; }
  let addr0 = raw_rtu(0, hb("030000000a"));
  if !err_rtu_is(rtu_decode(&addr0), "modbus: invalid rtu address") { ok = false; }
  let addr248 = raw_rtu(248, hb("030000000a"));
  if !err_rtu_is(rtu_decode(&addr248), "modbus: invalid rtu address") { ok = false; }
  let addr247 = raw_rtu(247, hb("030000000a"));
  if !rtu_decode(&addr247).is_ok { ok = false; }
  return assert(ok, "rtu error catalog: truncation, max length, crc, address bounds");
}

// --------------------------------------------------
//  Function 03 tests
// --------------------------------------------------

fn t8() -> TestResult {
  let r = read_holding_registers_request_pdu(107, 3);
  if !r.is_ok { return assert(false, "fc03 request must build"); }
  let p: ModbusPdu = r.value;
  var ok = pdu_function(&p) == 3;
  let d: Vec[UInt8] = p.data;
  if !bytes_equal(d, hb("006b0003")) { ok = false; }
  let br = pdu_encode(&p);
  if !br.is_ok { ok = false; } else {
    let b: Vec[UInt8] = br.value;
    if !bytes_equal(b, hb("03006b0003")) { ok = false; }
  }
  let back = read_holding_registers_request_from_pdu(&p);
  if !back.is_ok { ok = false; } else {
    let q: ReadHoldingRegistersRequest = back.value;
    if q.start_address != 107 { ok = false; }
    if q.quantity != 3 { ok = false; }
  }
  let r2 = read_holding_registers_request_pdu(65535, 1);
  if !r2.is_ok { ok = false; } else {
    let p2: ModbusPdu = r2.value;
    let b2 = read_holding_registers_request_from_pdu(&p2);
    if !b2.is_ok { ok = false; } else {
      let q2: ReadHoldingRegistersRequest = b2.value;
      if q2.start_address != 65535 { ok = false; }
      if q2.quantity != 1 { ok = false; }
    }
  }
  return assert(ok, "fc03 request: exact bytes and field round-trip");
}

fn t9() -> TestResult {
  var ok = err_pdu_is(read_holding_registers_request_pdu(-1, 1), "modbus: invalid register address");
  if !err_pdu_is(read_holding_registers_request_pdu(65536, 1), "modbus: invalid register address") { ok = false; }
  if !err_pdu_is(read_holding_registers_request_pdu(0, 0), "modbus: invalid register count") { ok = false; }
  if !err_pdu_is(read_holding_registers_request_pdu(0, 126), "modbus: invalid register count") { ok = false; }
  if !err_pdu_is(read_holding_registers_request_pdu(65535, 2), "modbus: address range overflow") { ok = false; }
  if !read_holding_registers_request_pdu(65535, 1).is_ok { ok = false; }
  if !read_holding_registers_request_pdu(0, 125).is_ok { ok = false; }
  // Decode-side catalog.
  var bad_fn = Vec[UInt8].new();
  bad_fn.push(0);
  bad_fn.push(0);
  bad_fn.push(0);
  bad_fn.push(1);
  let p4 = ModbusPdu{ function: 4; data: bad_fn };
  if !err_read_is(read_holding_registers_request_from_pdu(&p4), "modbus: wrong function") { ok = false; }
  let short = ModbusPdu{ function: 3; data: hb("000001") };
  if !err_read_is(read_holding_registers_request_from_pdu(&short), "modbus: bad pdu length") { ok = false; }
  let zeroq = ModbusPdu{ function: 3; data: hb("00000000") };
  if !err_read_is(read_holding_registers_request_from_pdu(&zeroq), "modbus: invalid register count") { ok = false; }
  let over = ModbusPdu{ function: 3; data: hb("ffff0002") };
  if !err_read_is(read_holding_registers_request_from_pdu(&over), "modbus: address range overflow") { ok = false; }
  return assert(ok, "fc03 request bounds: address, count 1..125, range overflow");
}

fn t10() -> TestResult {
  var regs = Vec[Int].new();
  regs.push(10);
  regs.push(258);
  let r = read_holding_registers_response_pdu(&regs);
  if !r.is_ok { return assert(false, "fc03 response must build"); }
  let p: ModbusPdu = r.value;
  var ok = pdu_function(&p) == 3;
  let d: Vec[UInt8] = p.data;
  if !bytes_equal(d, hb("04000a0102")) { ok = false; }
  let back = read_holding_registers_response_from_pdu(&p);
  if !back.is_ok { ok = false; } else {
    let v: Vec[Int] = back.value;
    if !ints_equal(v, regs) { ok = false; }
  }
  let full = rtu_encode(1, &p);
  if !full.is_ok { ok = false; } else {
    let fb: Vec[UInt8] = full.value;
    if !bytes_equal(fb, hb("010304000a01025a60")) { ok = false; }
  }
  let one = read_holding_registers_response_pdu(&even_regs(125));
  if !one.is_ok { ok = false; } else {
    let p125: ModbusPdu = one.value;
    if pdu_data_len(&p125) != 251 { ok = false; }
    let d125: Vec[UInt8] = p125.data;
    let bc: Int = (d125[0] as Int) & 0xFF;
    if bc != 250 { ok = false; }
    let b125 = read_holding_registers_response_from_pdu(&p125);
    if !b125.is_ok { ok = false; } else {
      let v125: Vec[Int] = b125.value;
      if v125.len() != 125 { ok = false; }
      let first: Int = v125[0];
      let last: Int = v125[124];
      if first != 0 { ok = false; }
      if last != 248 { ok = false; }
    }
  }
  return assert(ok, "fc03 response: exact bytes, register round-trip, 125-register frame");
}

fn t11() -> TestResult {
  let r = read_holding_registers_response_pdu(&even_regs(126));
  var ok = err_pdu_is(r, "modbus: invalid register count");
  var none = Vec[Int].new();
  if !err_pdu_is(read_holding_registers_response_pdu(&none), "modbus: invalid register count") { ok = false; }
  var bad = Vec[Int].new();
  bad.push(65536);
  if !err_pdu_is(read_holding_registers_response_pdu(&bad), "modbus: invalid register value") { ok = false; }
  var neg = Vec[Int].new();
  neg.push(-1);
  if !err_pdu_is(read_holding_registers_response_pdu(&neg), "modbus: invalid register value") { ok = false; }
  let p6 = ModbusPdu{ function: 6; data: hb("020001") };
  if !err_regs_is(read_holding_registers_response_from_pdu(&p6), "modbus: wrong function") { ok = false; }
  let pempty = ModbusPdu{ function: 3; data: Vec[UInt8].new() };
  if !err_regs_is(read_holding_registers_response_from_pdu(&pempty), "modbus: bad pdu length") { ok = false; }
  let podd = ModbusPdu{ function: 3; data: hb("03000102") };
  if !err_regs_is(read_holding_registers_response_from_pdu(&podd), "modbus: bad byte count") { ok = false; }
  let pmis = ModbusPdu{ function: 3; data: hb("04000102") };
  if !err_regs_is(read_holding_registers_response_from_pdu(&pmis), "modbus: bad byte count") { ok = false; }
  let pzero = ModbusPdu{ function: 3; data: hb("00") };
  if !err_regs_is(read_holding_registers_response_from_pdu(&pzero), "modbus: invalid register count") { ok = false; }
  var d126 = Vec[UInt8].new();
  d126.push(252);
  var i = 0;
  while i < 252 {
    d126.push(0);
    i = i + 1;
  }
  let p126 = ModbusPdu{ function: 3; data: d126 };
  if !err_regs_is(read_holding_registers_response_from_pdu(&p126), "modbus: invalid register count") { ok = false; }
  return assert(ok, "fc03 response error catalog: count, value, function, byte count");
}

// --------------------------------------------------
//  Function 06 tests
// --------------------------------------------------

fn t12() -> TestResult {
  let r = write_single_register_request_pdu(16, 3);
  if !r.is_ok { return assert(false, "fc06 request must build"); }
  let p: ModbusPdu = r.value;
  var ok = pdu_function(&p) == 6;
  let d: Vec[UInt8] = p.data;
  if !bytes_equal(d, hb("00100003")) { ok = false; }
  let back = write_single_register_request_from_pdu(&p);
  if !back.is_ok { ok = false; } else {
    let q: WriteSingleRegister = back.value;
    if q.address != 16 { ok = false; }
    if q.value != 3 { ok = false; }
  }
  let resp = write_single_register_response_pdu(16, 3);
  if !resp.is_ok { ok = false; } else {
    let rp: ModbusPdu = resp.value;
    let rd: Vec[UInt8] = rp.data;
    if !bytes_equal(rd, d) { ok = false; }
    let rb = write_single_register_response_from_pdu(&rp);
    if !rb.is_ok { ok = false; } else {
      let rq: WriteSingleRegister = rb.value;
      if rq.address != 16 { ok = false; }
      if rq.value != 3 { ok = false; }
    }
  }
  let boundary = write_single_register_request_pdu(65535, 65535);
  if !boundary.is_ok { ok = false; } else {
    let bp: ModbusPdu = boundary.value;
    let bd: Vec[UInt8] = bp.data;
    if !bytes_equal(bd, hb("ffffffff")) { ok = false; }
  }
  return assert(ok, "fc06 request/response: exact bytes and field round-trip");
}

fn t13() -> TestResult {
  var ok = err_pdu_is(write_single_register_request_pdu(-1, 0), "modbus: invalid register address");
  if !err_pdu_is(write_single_register_request_pdu(65536, 0), "modbus: invalid register address") { ok = false; }
  if !err_pdu_is(write_single_register_request_pdu(0, -1), "modbus: invalid register value") { ok = false; }
  if !err_pdu_is(write_single_register_request_pdu(0, 65536), "modbus: invalid register value") { ok = false; }
  let p3 = ModbusPdu{ function: 3; data: hb("00000003") };
  if !err_write_is(write_single_register_request_from_pdu(&p3), "modbus: wrong function") { ok = false; }
  let short = ModbusPdu{ function: 6; data: hb("000003") };
  if !err_write_is(write_single_register_request_from_pdu(&short), "modbus: bad pdu length") { ok = false; }
  let long = ModbusPdu{ function: 6; data: hb("0000000300") };
  if !err_write_is(write_single_register_request_from_pdu(&long), "modbus: bad pdu length") { ok = false; }
  if !err_write_is(write_single_register_response_from_pdu(&p3), "modbus: wrong function") { ok = false; }
  return assert(ok, "fc06 error catalog: address/value bounds and pdu shape");
}

// --------------------------------------------------
//  Exception tests
// --------------------------------------------------

fn t14() -> TestResult {
  let r = exception_pdu(3, 2);
  if !r.is_ok { return assert(false, "exception must build"); }
  let p: ModbusPdu = r.value;
  var ok = pdu_function(&p) == 131;
  if !pdu_is_exception(&p) { ok = false; }
  let d: Vec[UInt8] = p.data;
  if !bytes_equal(d, hb("02")) { ok = false; }
  let br = pdu_encode(&p);
  if !br.is_ok { ok = false; } else {
    let b: Vec[UInt8] = br.value;
    if !bytes_equal(b, hb("8302")) { ok = false; }
  }
  let back = exception_from_pdu(&p);
  if !back.is_ok { ok = false; } else {
    let e: ModbusException = back.value;
    if e.function != 3 { ok = false; }
    if e.code != 2 { ok = false; }
  }
  var code = 1;
  while code <= 4 {
    let cr = exception_pdu(6, code);
    if !cr.is_ok { ok = false; } else {
      let cp: ModbusPdu = cr.value;
      if pdu_function(&cp) != 134 { ok = false; }
      let cb = exception_from_pdu(&cp);
      if !cb.is_ok { ok = false; } else {
        let ce: ModbusException = cb.value;
        if ce.function != 6 { ok = false; }
        if ce.code != code { ok = false; }
      }
    }
    code = code + 1;
  }
  var empty = Vec[UInt8].new();
  let norm = ModbusPdu{ function: 3; data: empty; };
  if !err_exc_is(exception_from_pdu(&norm), "modbus: wrong function") { ok = false; }
  let two = ModbusPdu{ function: 131; data: hb("0202") };
  if !err_exc_is(exception_from_pdu(&two), "modbus: bad pdu length") { ok = false; }
  let zero = ModbusPdu{ function: 131; data: hb("00") };
  if !err_exc_is(exception_from_pdu(&zero), "modbus: invalid exception code") { ok = false; }
  let five = ModbusPdu{ function: 131; data: hb("05") };
  if !err_exc_is(exception_from_pdu(&five), "modbus: invalid exception code") { ok = false; }
  return assert(ok, "exception pdu: exact bytes, codes 1..4, error catalog");
}

fn t15() -> TestResult {
  var ok = err_pdu_is(exception_pdu(0, 1), "modbus: invalid function code");
  if !err_pdu_is(exception_pdu(128, 1), "modbus: invalid function code") { ok = false; }
  if !err_pdu_is(exception_pdu(-1, 1), "modbus: invalid function code") { ok = false; }
  if !err_pdu_is(exception_pdu(3, 0), "modbus: invalid exception code") { ok = false; }
  if !err_pdu_is(exception_pdu(3, 5), "modbus: invalid exception code") { ok = false; }
  if exception_pdu(1, 1).is_ok == false { ok = false; }
  if !str_eq(exception_name(1), "illegal function") { ok = false; }
  if !str_eq(exception_name(2), "illegal data address") { ok = false; }
  if !str_eq(exception_name(3), "illegal data value") { ok = false; }
  if !str_eq(exception_name(4), "server device failure") { ok = false; }
  if !str_eq(exception_name(0), "unknown exception") { ok = false; }
  if !str_eq(exception_name(5), "unknown exception") { ok = false; }
  return assert(ok, "exception builder bounds and exception_name mapping");
}

// --------------------------------------------------
//  TCP framing tests
// --------------------------------------------------

fn t16() -> TestResult {
  let r1 = read_holding_registers_request_pdu(0, 10);
  if !r1.is_ok { return assert(false, "fc03 request must build"); }
  let p1: ModbusPdu = r1.value;
  let e1 = tcp_encode(1, 1, &p1);
  if !e1.is_ok { return assert(false, "tcp encode must succeed"); }
  let f1: Vec[UInt8] = e1.value;
  var ok = bytes_equal(f1, hb("00010000000601030000000a"));
  if f1.len() != 12 { ok = false; }
  let r2 = write_single_register_request_pdu(16, 3);
  if !r2.is_ok { ok = false; } else {
    let p2: ModbusPdu = r2.value;
    let e2 = tcp_encode(4660, 255, &p2);
    if !e2.is_ok { ok = false; } else {
      let f2: Vec[UInt8] = e2.value;
      if !bytes_equal(f2, hb("123400000006ff0600100003")) { ok = false; }
    }
  }
  let r3 = exception_pdu(3, 2);
  if !r3.is_ok { ok = false; } else {
    let p3: ModbusPdu = r3.value;
    let e3 = tcp_encode(1, 1, &p3);
    if !e3.is_ok { ok = false; } else {
      let f3: Vec[UInt8] = e3.value;
      if !bytes_equal(f3, hb("000100000003018302")) { ok = false; }
    }
  }
  return assert(ok, "tcp_encode pinned MBAP frames");
}

fn t17() -> TestResult {
  let f1 = hb("00010000000601030000000a");
  let d1 = tcp_decode(&f1);
  if !d1.is_ok { return assert(false, "pinned tcp frame must decode"); }
  let tf1: ModbusTcpFrame = d1.value;
  var ok = tf1.transaction_id == 1;
  if tf1.unit_id != 1 { ok = false; }
  if pdu_function(&tf1.pdu) != 3 { ok = false; }
  let pd1: Vec[UInt8] = tf1.pdu.data;
  if !bytes_equal(pd1, hb("0000000a")) { ok = false; }
  let re1 = tcp_encode(tf1.transaction_id, tf1.unit_id, &tf1.pdu);
  if !re1.is_ok { ok = false; } else {
    let rb1: Vec[UInt8] = re1.value;
    if !bytes_equal(rb1, f1) { ok = false; }
  }
  let f2 = hb("123400000006ff0600100003");
  let d2 = tcp_decode(&f2);
  if !d2.is_ok { ok = false; } else {
    let tf2: ModbusTcpFrame = d2.value;
    if tf2.transaction_id != 4660 { ok = false; }
    if tf2.unit_id != 255 { ok = false; }
    if pdu_function(&tf2.pdu) != 6 { ok = false; }
  }
  let f3 = hb("000100000003018302");
  let d3 = tcp_decode(&f3);
  if !d3.is_ok { ok = false; } else {
    let tf3: ModbusTcpFrame = d3.value;
    if pdu_function(&tf3.pdu) != 131 { ok = false; }
    if !pdu_is_exception(&tf3.pdu) { ok = false; }
  }
  let f4 = hb("000100000002ff03");
  let d4 = tcp_decode(&f4);
  if !d4.is_ok { ok = false; } else {
    let tf4: ModbusTcpFrame = d4.value;
    if tf4.unit_id != 255 { ok = false; }
    if pdu_function(&tf4.pdu) != 3 { ok = false; }
    if pdu_data_len(&tf4.pdu) != 0 { ok = false; }
  }
  return assert(ok, "tcp_decode round-trips pinned frames including the 8-byte minimum");
}

fn t18() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_tcp_is(tcp_decode(&empty), "modbus: truncated mbap header");
  let seven = raw_tcp_full(1, 0, 2, 1, Vec[UInt8].new());
  if !err_tcp_is(tcp_decode(&seven), "modbus: truncated mbap header") { ok = false; }
  let good = hb("00010000000601030000000a");
  let badproto = raw_tcp_full(1, 1, 6, 1, hb("030000000a"));
  if !err_tcp_is(tcp_decode(&badproto), "modbus: bad protocol id") { ok = false; }
  let bothbad = raw_tcp_full(1, 1, 7, 1, hb("030000000a"));
  if !err_tcp_is(tcp_decode(&bothbad), "modbus: bad protocol id") { ok = false; }
  let longlen = raw_tcp_full(1, 0, 7, 1, hb("030000000a"));
  if !err_tcp_is(tcp_decode(&longlen), "modbus: length mismatch") { ok = false; }
  let shortlen = raw_tcp_full(1, 0, 5, 1, hb("030000000a"));
  if !err_tcp_is(tcp_decode(&shortlen), "modbus: length mismatch") { ok = false; }
  let cut = hb("0001000000060103000000");
  if !err_tcp_is(tcp_decode(&cut), "modbus: length mismatch") { ok = false; }
  if !tcp_decode(&good).is_ok { ok = false; }
  return assert(ok, "tcp error catalog: truncation, protocol id, length consistency");
}

fn t19() -> TestResult {
  let over = ModbusPdu{ function: 3; data: Vec[UInt8].new() };
  var ok = err_bytes_is(tcp_encode(-1, 0, &over), "modbus: invalid transaction id");
  if !err_bytes_is(tcp_encode(65536, 0, &over), "modbus: invalid transaction id") { ok = false; }
  if !err_bytes_is(tcp_encode(0, -1, &over), "modbus: invalid unit id") { ok = false; }
  if !err_bytes_is(tcp_encode(0, 256, &over), "modbus: invalid unit id") { ok = false; }
  let badpdu = ModbusPdu{ function: 3; data: repeat_byte(1, 253) };
  if !err_bytes_is(tcp_encode(0, 0, &badpdu), "modbus: pdu too long") { ok = false; }
  var ok2 = err_bytes_is(rtu_encode(0, &over), "modbus: invalid rtu address");
  if !err_bytes_is(rtu_encode(248, &over), "modbus: invalid rtu address") { ok2 = false; }
  if !err_bytes_is(rtu_encode(1, &badpdu), "modbus: pdu too long") { ok2 = false; }
  if !rtu_encode(1, &over).is_ok { ok2 = false; }
  if !rtu_encode(247, &over).is_ok { ok2 = false; }
  return assert(ok && ok2, "rtu/tcp builder validation and pdu error propagation");
}

// --------------------------------------------------
//  Boundary and pipeline tests
// --------------------------------------------------

fn t20() -> TestResult {
  // Minimum RTU ADU: address + 1-byte PDU + CRC = 4 bytes.
  let minp = ModbusPdu{ function: 7; data: Vec[UInt8].new() };
  let e1 = rtu_encode(1, &minp);
  if !e1.is_ok { return assert(false, "minimal rtu frame must encode"); }
  let f1: Vec[UInt8] = e1.value;
  var ok = f1.len() == 4;
  let d1 = rtu_decode(&f1);
  if !d1.is_ok { ok = false; } else {
    let fr: ModbusRtuFrame = d1.value;
    if fr.address != 1 { ok = false; }
    if pdu_function(&fr.pdu) != 7 { ok = false; }
  }
  // Maximum RTU ADU: address + 253-byte PDU + CRC = 256 bytes.
  let maxp = ModbusPdu{ function: 8; data: repeat_byte(170, 252) };
  let e2 = rtu_encode(247, &maxp);
  if !e2.is_ok { ok = false; } else {
    let f2: Vec<UInt8> = e2.value;
    if f2.len() != 256 { ok = false; }
    let d2 = rtu_decode(&f2);
    if !d2.is_ok { ok = false; } else {
      let fr2: ModbusRtuFrame = d2.value;
      if fr2.address != 247 { ok = false; }
      if pdu_function(&fr2.pdu) != 8 { ok = false; }
      let pd2: Vec<UInt8> = fr2.pdu.data;
      if pd2.len() != 252 { ok = false; }
      let b0: Int = (pd2[0] as Int) & 0xFF;
      let b251: Int = (pd2[251] as Int) & 0xFF;
      if b0 != 170 { ok = false; }
      if b251 != 170 { ok = false; }
    }
  }
  // Maximum TCP ADU for a 125-register response: 7-byte MBAP header plus a
  // 252-byte PDU = 259 bytes; the length field is 1 + 252 = 253.
  let regs = even_regs(125);
  let rp = read_holding_registers_response_pdu(&regs);
  if !rp.is_ok { ok = false; } else {
    let p: ModbusPdu = rp.value;
    let e3 = tcp_encode(65535, 0, &p);
    if !e3.is_ok { ok = false; } else {
      let f3: Vec[UInt8] = e3.value;
      if f3.len() != 259 { ok = false; }
      let lhi: Int = (f3[4] as Int) & 0xFF;
      let llo: Int = (f3[5] as Int) & 0xFF;
      if lhi != 0 { ok = false; }
      if llo != 253 { ok = false; }
      let d3 = tcp_decode(&f3);
      if !d3.is_ok { ok = false; } else {
        let tf: ModbusTcpFrame = d3.value;
        if tf.transaction_id != 65535 { ok = false; }
        if tf.unit_id != 0 { ok = false; }
        let back = read_holding_registers_response_from_pdu(&tf.pdu);
        if !back.is_ok { ok = false; } else {
          let v: Vec[Int] = back.value;
          if !ints_equal(v, regs) { ok = false; }
        }
      }
    }
  }
  return assert(ok, "boundary sizes: 4/256-byte RTU and 259-byte TCP frames");
}

fn t21() -> TestResult {
  // Full pipelines: PDU -> RTU -> decode -> function codec.
  let rq = read_holding_registers_request_pdu(100, 8);
  if !rq.is_ok { return assert(false, "request must build"); }
  let p1: ModbusPdu = rq.value;
  let e1 = rtu_encode(3, &p1);
  if !e1.is_ok { return assert(false, "rtu encode must succeed"); }
  let f1: Vec<UInt8> = e1.value;
  let d1 = rtu_decode(&f1);
  if !d1.is_ok { return assert(false, "rtu decode must succeed"); }
  let fr1: ModbusRtuFrame = d1.value;
  var ok = fr1.address == 3;
  let b1 = read_holding_registers_request_from_pdu(&fr1.pdu);
  if !b1.is_ok { ok = false; } else {
    let q1: ReadHoldingRegistersRequest = b1.value;
    if q1.start_address != 100 { ok = false; }
    if q1.quantity != 8 { ok = false; }
  }
  let regs = even_regs(4);
  let rp = read_holding_registers_response_pdu(&regs);
  if !rp.is_ok { ok = false; } else {
    let p2: ModbusPdu = rp.value;
    let e2 = rtu_encode(3, &p2);
    if !e2.is_ok { ok = false; } else {
      let f2: Vec<UInt8> = e2.value;
      let d2 = rtu_decode(&f2);
      if !d2.is_ok { ok = false; } else {
        let fr2: ModbusRtuFrame = d2.value;
        let b2 = read_holding_registers_response_from_pdu(&fr2.pdu);
        if !b2.is_ok { ok = false; } else {
          let v2: Vec[Int] = b2.value;
          if !ints_equal(v2, regs) { ok = false; }
        }
      }
    }
  }
  let ex = exception_pdu(3, 4);
  if !ex.is_ok { ok = false; } else {
    let p3: ModbusPdu = ex.value;
    let e3 = rtu_encode(9, &p3);
    if !e3.is_ok { ok = false; } else {
      let f3: Vec<UInt8> = e3.value;
      let d3 = rtu_decode(&f3);
      if !d3.is_ok { ok = false; } else {
        let fr3: ModbusRtuFrame = d3.value;
        let b3 = exception_from_pdu(&fr3.pdu);
        if !b3.is_ok { ok = false; } else {
          let x3: ModbusException = b3.value;
          if x3.function != 3 { ok = false; }
          if x3.code != 4 { ok = false; }
        }
      }
    }
  }
  return assert(ok, "RTU pipeline: fc03 request/response and exception end to end");
}

fn t22() -> TestResult {
  // Full pipelines: PDU -> TCP -> decode -> function codec.
  let rq = write_single_register_request_pdu(1234, 5678);
  if !rq.is_ok { return assert(false, "fc06 request must build"); }
  let p1: ModbusPdu = rq.value;
  let e1 = tcp_encode(7, 5, &p1);
  if !e1.is_ok { return assert(false, "tcp encode must succeed"); }
  let f1: Vec<UInt8> = e1.value;
  let d1 = tcp_decode(&f1);
  if !d1.is_ok { return assert(false, "tcp decode must succeed"); }
  let tf1: ModbusTcpFrame = d1.value;
  var ok = tf1.transaction_id == 7;
  if tf1.unit_id != 5 { ok = false; }
  let b1 = write_single_register_request_from_pdu(&tf1.pdu);
  if !b1.is_ok { ok = false; } else {
    let q1: WriteSingleRegister = b1.value;
    if q1.address != 1234 { ok = false; }
    if q1.value != 5678 { ok = false; }
  }
  let resp = write_single_register_response_pdu(1234, 5678);
  if !resp.is_ok { ok = false; } else {
    let p2: ModbusPdu = resp.value;
    let e2 = tcp_encode(7, 5, &p2);
    if !e2.is_ok { ok = false; } else {
      let f2: Vec<UInt8> = e2.value;
      if !bytes_equal(f1, f2) { ok = false; }
      let d2 = tcp_decode(&f2);
      if !d2.is_ok { ok = false; } else {
        let tf2: ModbusTcpFrame = d2.value;
        let b2 = write_single_register_response_from_pdu(&tf2.pdu);
        if !b2.is_ok { ok = false; } else {
          let q2: WriteSingleRegister = b2.value;
          if q2.address != 1234 { ok = false; }
          if q2.value != 5678 { ok = false; }
        }
      }
    }
  }
  let ex = exception_pdu(6, 1);
  if !ex.is_ok { ok = false; } else {
    let p3: ModbusPdu = ex.value;
    let e3 = tcp_encode(1, 255, &p3);
    if !e3.is_ok { ok = false; } else {
      let f3: Vec<UInt8> = e3.value;
      let d3 = tcp_decode(&f3);
      if !d3.is_ok { ok = false; } else {
        let tf3: ModbusTcpFrame = d3.value;
        let b3 = exception_from_pdu(&tf3.pdu);
        if !b3.is_ok { ok = false; } else {
          let x3: ModbusException = b3.value;
          if x3.function != 6 { ok = false; }
          if x3.code != 1 { ok = false; }
        }
      }
    }
  }
  return assert(ok, "TCP pipeline: fc06 request/response echo and exception end to end");
}

fn t23() -> TestResult {
  // Determinism: repeated encodings agree byte for byte, repeated decodes
  // agree field for field, and independent Pdus with equal content encode
  // identically.
  let r = read_holding_registers_request_pdu(9, 9);
  if !r.is_ok { return assert(false, "request must build"); }
  let p: ModbusPdu = r.value;
  let a = rtu_encode(1, &p);
  let b = rtu_encode(1, &p);
  var ok = a.is_ok && b.is_ok;
  if ok {
    let fa: Vec<UInt8> = a.value;
    let fb: Vec[UInt8] = b.value;
    if !bytes_equal(fa, fb) { ok = false; }
    let da = rtu_decode(&fa);
    let db = rtu_decode(&fb);
    if !da.is_ok || !db.is_ok { ok = false; } else {
      let qa: ModbusRtuFrame = da.value;
      let qb: ModbusRtuFrame = db.value;
      if qa.address != qb.address { ok = false; }
      if pdu_function(&qa.pdu) != pdu_function(&qb.pdu) { ok = false; }
      let xa: Vec[UInt8] = qa.pdu.data;
      let xb: Vec[UInt8] = qb.pdu.data;
      if !bytes_equal(xa, xb) { ok = false; }
    }
  }
  var d1 = Vec[UInt8].new();
  d1.push(0);
  d1.push(9);
  d1.push(0);
  d1.push(9);
  let p2 = ModbusPdu{ function: 3; data: d1 };
  let c = pdu_encode(&p2);
  let e = pdu_encode(&p);
  if !c.is_ok || !e.is_ok { ok = false; } else {
    let fc: Vec[UInt8] = c.value;
    let fe: Vec[UInt8] = e.value;
    if !bytes_equal(fc, fe) { ok = false; }
  }
  return assert(ok, "determinism: repeat encode/decode and equal-content pdus");
}

fn main() -> Int {
  io.println("=== xiom.modbus conformance tests ===");
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
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.modbus: all tests passed");
  } else {
    io.println("xiom.modbus: tests failed");
  }
  return failed;
}
