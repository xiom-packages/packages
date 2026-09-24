// XIOM -- xiom.tftp conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.tftp packet codec against RFC 1350.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: exact wire bytes for RRQ/WRQ/DATA/ACK/ERROR,
// parse round-trips, the 511/512 block boundary, unicode filename bytes,
// block clamping and the full error catalog.
//
// Str payloads are compared with str_compare (BUG 17 discipline: `==` on
// Str values read from a Vec lowers to a pointer comparison). Tuple-Result
// payloads are read through match arms, and no test function builds a Vec
// inside a match arm (stdlib probe p_result_tuple_vec_loop). Byte reads
// are cast to Int before comparison, so no UInt8 is compared against a
// literal >= 128.

module tftp_tests
use xiom.io; use xiom.test;
use xiom.tftp;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
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

fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn concat_bytes(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    v.push(b[j]);
    j = j + 1;
  }
  return v;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Result extractors and error assertions
// --------------------------------------------------

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_rq_is(r: Result[(Str, Str), Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_data_is(r: Result[(Int, Vec[UInt8]), Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_error_is(r: Result[(Int, Str), Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn op_int(data: &Vec[UInt8]) -> Int {
  let r = tftp_op(data);
  if !r.is_ok {
    return -1;
  }
  return r.value;
}

fn rq_filename(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse_rq(data);
  match r {
    Ok(t) => { return t.0; },
    Err(_) => {},
  }
  return "";
}

fn rq_mode(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse_rq(data);
  match r {
    Ok(t) => { return t.1; },
    Err(_) => {},
  }
  return "";
}

fn data_block(data: &Vec[UInt8]) -> Int {
  let r = tftp_parse_data(data);
  match r {
    Ok(t) => { return t.0; },
    Err(_) => {},
  }
  return -1;
}

fn data_payload(data: &Vec[UInt8]) -> Vec[UInt8] {
  let r = tftp_parse_data(data);
  match r {
    Ok(t) => { return t.1; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn ack_block(data: &Vec[UInt8]) -> Int {
  let r = tftp_parse_ack(data);
  if !r.is_ok {
    return -1;
  }
  return r.value;
}

fn error_code(data: &Vec[UInt8]) -> Int {
  let r = tftp_parse_error(data);
  match r {
    Ok(t) => { return t.0; },
    Err(_) => {},
  }
  return -1;
}

fn error_message(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse_error(data);
  match r {
    Ok(t) => { return t.1; },
    Err(_) => {},
  }
  return "";
}

// 1 = last, 0 = not last, -1 = error.
fn last_flag(data: &Vec[UInt8]) -> Int {
  let r = tftp_is_last_block(data);
  if !r.is_ok {
    return -1;
  }
  if r.value {
    return 1;
  }
  return 0;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let pkt = tftp_build_rrq("hello.txt", "octet");
  var ok = pkt.len() == 18;
  if !bytes_equal(pkt, hb("000168656c6c6f2e747874006f6374657400")) { ok = false; }
  if op_int(&pkt) != 1 { ok = false; }
  return assert(ok, "RRQ hello.txt/octet is exact 18 bytes");
}

fn t2() -> TestResult {
  let pkt = tftp_build_wrq("upload.bin", "octet");
  var ok = pkt.len() == 19;
  if !bytes_equal(pkt, hb("000275706c6f61642e62696e006f6374657400")) { ok = false; }
  if op_int(&pkt) != 2 { ok = false; }
  return assert(ok, "WRQ upload.bin/octet is exact 19 bytes");
}

fn t3() -> TestResult {
  let one = tftp_build_rrq("", "octet");
  let both = tftp_build_rrq("", "");
  var ok = bytes_equal(one, hb("0001006f6374657400"));
  if !bytes_equal(both, hb("00010000")) { ok = false; }
  if !str_eq(rq_filename(&one), "") { ok = false; }
  if !str_eq(rq_mode(&one), "octet") { ok = false; }
  if !str_eq(rq_filename(&both), "") { ok = false; }
  if !str_eq(rq_mode(&both), "") { ok = false; }
  return assert(ok, "empty filename and empty mode encode and parse");
}

fn t4() -> TestResult {
  let pkt = tftp_build_rrq("my file.txt", "netascii");
  var ok = bytes_equal(pkt, hb("00016d792066696c652e747874006e6574617363696900"));
  if !str_eq(rq_filename(&pkt), "my file.txt") { ok = false; }
  if !str_eq(rq_mode(&pkt), "netascii") { ok = false; }
  return assert(ok, "filename and mode with spaces round-trip");
}

fn t5() -> TestResult {
  let payload = hb("010203");
  let pkt = tftp_build_data(1, &payload);
  var ok = bytes_equal(pkt, hb("00030001010203"));
  if data_block(&pkt) != 1 { ok = false; }
  if !bytes_equal(data_payload(&pkt), payload) { ok = false; }
  return assert(ok, "DATA block 1 payload 010203 is exact bytes");
}

fn t6() -> TestResult {
  var empty = Vec[UInt8].new();
  let pkt = tftp_build_data(7, &empty);
  var ok = pkt.len() == 4;
  if !bytes_equal(pkt, hb("00030007")) { ok = false; }
  if data_block(&pkt) != 7 { ok = false; }
  if data_payload(&pkt).len() != 0 { ok = false; }
  if last_flag(&pkt) != 1 { ok = false; }
  return assert(ok, "empty DATA payload round-trips and is last");
}

fn t7() -> TestResult {
  let payload = repeat_byte(65, 512);
  let pkt = tftp_build_data(1, &payload);
  var ok = pkt.len() == 516;
  if (pkt[0] as Int) != 0 { ok = false; }
  if (pkt[1] as Int) != 3 { ok = false; }
  if (pkt[2] as Int) != 0 { ok = false; }
  if (pkt[3] as Int) != 1 { ok = false; }
  if (pkt[515] as Int) != 65 { ok = false; }
  if !bytes_equal(data_payload(&pkt), payload) { ok = false; }
  if last_flag(&pkt) != 0 { ok = false; }
  return assert(ok, "512-byte DATA payload is not last and round-trips");
}

fn t8() -> TestResult {
  let payload = repeat_byte(66, 511);
  let pkt = tftp_build_data(10, &payload);
  var ok = pkt.len() == 515;
  if !bytes_equal(data_payload(&pkt), payload) { ok = false; }
  if last_flag(&pkt) != 1 { ok = false; }
  let back = data_payload(&pkt);
  if back.len() != 511 { ok = false; }
  if (back[510] as Int) != 66 { ok = false; }
  return assert(ok, "511-byte DATA payload is last and round-trips");
}

fn t9() -> TestResult {
  let a0 = tftp_build_ack(0);
  let a1 = tftp_build_ack(1);
  let ahi = tftp_build_ack(65535);
  var ok = bytes_equal(a0, hb("00040000"));
  if !bytes_equal(a1, hb("00040001")) { ok = false; }
  if !bytes_equal(ahi, hb("0004ffff")) { ok = false; }
  if ack_block(&a0) != 0 { ok = false; }
  if ack_block(&a1) != 1 { ok = false; }
  if ack_block(&ahi) != 65535 { ok = false; }
  return assert(ok, "ACK blocks 0, 1 and 65535 are exact bytes");
}

fn t10() -> TestResult {
  var empty = Vec[UInt8].new();
  let dlo = tftp_build_data(-5, &empty);
  let dhi = tftp_build_data(70000, &empty);
  let alo = tftp_build_ack(-1);
  let ahi = tftp_build_ack(100000);
  var ok = bytes_equal(dlo, hb("00030000"));
  if !bytes_equal(dhi, hb("0003ffff")) { ok = false; }
  if !bytes_equal(alo, hb("00040000")) { ok = false; }
  if !bytes_equal(ahi, hb("0004ffff")) { ok = false; }
  if data_block(&dlo) != 0 { ok = false; }
  if data_block(&dhi) != 65535 { ok = false; }
  if ack_block(&alo) != 0 { ok = false; }
  if ack_block(&ahi) != 65535 { ok = false; }
  return assert(ok, "build_data/build_ack clamp blocks to 0..65535");
}

fn t11() -> TestResult {
  let pkt = tftp_build_error(1, "File not found");
  var ok = bytes_equal(pkt, hb("0005000146696c65206e6f7420666f756e6400"));
  if error_code(&pkt) != 1 { ok = false; }
  if !str_eq(error_message(&pkt), "File not found") { ok = false; }
  if op_int(&pkt) != 5 { ok = false; }
  return assert(ok, "ERROR code 1 File not found is exact bytes");
}

fn t12() -> TestResult {
  let pkt = tftp_build_error(0, "");
  var ok = bytes_equal(pkt, hb("0005000000"));
  if error_code(&pkt) != 0 { ok = false; }
  if !str_eq(error_message(&pkt), "") { ok = false; }
  return assert(ok, "ERROR code 0 with empty message");
}

fn t13() -> TestResult {
  let pkt = tftp_build_rrq("héllo/文件.bin", "octet");
  var ok = bytes_equal(pkt, hb("000168c3a96c6c6f2fe69687e4bbb62e62696e006f6374657400"));
  if !str_eq(rq_filename(&pkt), "héllo/文件.bin") { ok = false; }
  if !str_eq(rq_mode(&pkt), "octet") { ok = false; }
  return assert(ok, "unicode filename bytes are preserved exactly");
}

fn t14() -> TestResult {
  var empty = Vec[UInt8].new();
  let dat = tftp_build_data(1, &empty);
  let wrq = tftp_build_wrq("upload.bin", "octet");
  var ok = err_rq_is(tftp_parse_rq(&dat), "tftp: not an RRQ or WRQ");
  if !err_rq_is(tftp_parse_rq(&hb("")), "tftp: truncated header") { ok = false; }
  if !err_rq_is(tftp_parse_rq(&hb("0009")), "tftp: unknown opcode") { ok = false; }
  if !err_rq_is(tftp_parse_rq(&hb("000168656c6c6f")), "tftp: missing NUL terminator") { ok = false; }
  if !err_rq_is(tftp_parse_rq(&hb("000168656c6c6f006f63746574")), "tftp: missing NUL terminator") { ok = false; }
  if !str_eq(rq_filename(&wrq), "upload.bin") { ok = false; }
  if !str_eq(rq_mode(&wrq), "octet") { ok = false; }
  return assert(ok, "parse_rq round-trips WRQ and rejects malformed input");
}

fn t15() -> TestResult {
  var ok = op_int(&hb("0001")) == 1;
  if op_int(&hb("0002")) != 2 { ok = false; }
  if op_int(&hb("0003")) != 3 { ok = false; }
  if op_int(&hb("0004")) != 4 { ok = false; }
  if op_int(&hb("0005")) != 5 { ok = false; }
  if !err_int_is(tftp_op(&hb("0000")), "tftp: unknown opcode") { ok = false; }
  if !err_int_is(tftp_op(&hb("0006")), "tftp: unknown opcode") { ok = false; }
  if !err_int_is(tftp_op(&hb("ffff")), "tftp: unknown opcode") { ok = false; }
  if !err_int_is(tftp_op(&hb("00")), "tftp: truncated header") { ok = false; }
  if !err_int_is(tftp_op(&hb("")), "tftp: truncated header") { ok = false; }
  return assert(ok, "tftp_op accepts 1..5 and rejects other values");
}

fn t16() -> TestResult {
  let payload = hb("00ff807f0102");
  let pkt = tftp_build_data(42, &payload);
  var ok = pkt.len() == 10;
  if data_block(&pkt) != 42 { ok = false; }
  if !bytes_equal(data_payload(&pkt), payload) { ok = false; }
  let ack = tftp_build_ack(1);
  if !err_data_is(tftp_parse_data(&ack), "tftp: not a DATA packet") { ok = false; }
  if !err_data_is(tftp_parse_data(&hb("0003")), "tftp: truncated packet") { ok = false; }
  if !err_data_is(tftp_parse_data(&hb("000300")), "tftp: truncated packet") { ok = false; }
  if !err_data_is(tftp_parse_data(&hb("")), "tftp: truncated header") { ok = false; }
  return assert(ok, "parse_data round-trips NUL and high bytes; short buffers Err");
}

fn t17() -> TestResult {
  let a0 = tftp_build_ack(0);
  let a300 = tftp_build_ack(300);
  let ahi = tftp_build_ack(65535);
  var ok = ack_block(&a0) == 0;
  if ack_block(&a300) != 300 { ok = false; }
  if ack_block(&ahi) != 65535 { ok = false; }
  var empty = Vec[UInt8].new();
  let dat = tftp_build_data(1, &empty);
  if !err_int_is(tftp_parse_ack(&dat), "tftp: not an ACK") { ok = false; }
  if !err_int_is(tftp_parse_ack(&hb("00040000ff")), "tftp: bad ACK length") { ok = false; }
  if !err_int_is(tftp_parse_ack(&hb("000400")), "tftp: bad ACK length") { ok = false; }
  if !err_int_is(tftp_parse_ack(&hb("")), "tftp: truncated header") { ok = false; }
  return assert(ok, "parse_ack round-trips blocks and rejects bad lengths");
}

fn t18() -> TestResult {
  let pkt = tftp_build_error(2, "Access violation");
  var ok = error_code(&pkt) == 2;
  if !str_eq(error_message(&pkt), "Access violation") { ok = false; }
  let rrq = tftp_build_rrq("a", "octet");
  if !err_error_is(tftp_parse_error(&rrq), "tftp: not an ERROR packet") { ok = false; }
  if !err_error_is(tftp_parse_error(&hb("0005")), "tftp: truncated packet") { ok = false; }
  if !err_error_is(tftp_parse_error(&hb("00050001")), "tftp: truncated packet") { ok = false; }
  if !err_error_is(tftp_parse_error(&hb("00050001416263")), "tftp: missing NUL terminator") { ok = false; }
  if !err_error_is(tftp_parse_error(&hb("")), "tftp: truncated header") { ok = false; }
  return assert(ok, "parse_error round-trips and rejects malformed input");
}

fn t19() -> TestResult {
  var empty = Vec[UInt8].new();
  let last0 = tftp_build_data(1, &empty);
  let last1 = tftp_build_data(1, &repeat_byte(65, 511));
  let full = tftp_build_data(1, &repeat_byte(65, 512));
  var ok = last_flag(&last0) == 1;
  if last_flag(&last1) != 1 { ok = false; }
  if last_flag(&full) != 0 { ok = false; }
  return assert(ok, "is_last_block: 0 and 511 payloads last, 512 not");
}

fn t20() -> TestResult {
  let payload = repeat_byte(66, 511);
  let pkt = tftp_build_data(10, &payload);
  let want = concat_bytes(hb("0003000a"), payload);
  var ok = bytes_equal(pkt, want);
  if pkt.len() != 515 { ok = false; }
  if (pkt[514] as Int) != 66 { ok = false; }
  return assert(ok, "511-byte DATA is exact 515 bytes");
}

fn t21() -> TestResult {
  let pkt = tftp_build_ack(1);
  var ok = err_bool_is(tftp_is_last_block(&pkt), "tftp: not a DATA packet");
  if !err_bool_is(tftp_is_last_block(&hb("0003")), "tftp: truncated packet") { ok = false; }
  if !err_bool_is(tftp_is_last_block(&hb("")), "tftp: truncated header") { ok = false; }
  return assert(ok, "is_last_block propagates non-DATA and truncation errors");
}

fn t22() -> TestResult {
  let with_options = hb("000168656c6c6f2e747874006f6374657400626c6b73697a650035313200");
  var ok = str_eq(rq_filename(&with_options), "hello.txt");
  if !str_eq(rq_mode(&with_options), "octet") { ok = false; }
  return assert(ok, "parse_rq ignores RFC 2347 option bytes after the mode");
}

fn t23() -> TestResult {
  let pkt = tftp_build_data(65535, &hb("aabb"));
  var ok = bytes_equal(pkt, hb("0003ffffaabb"));
  if data_block(&pkt) != 65535 { ok = false; }
  if !bytes_equal(data_payload(&pkt), hb("aabb")) { ok = false; }
  return assert(ok, "DATA block 65535 round-trips with exact header bytes");
}

fn t24() -> TestResult {
  let rrq = tftp_build_rrq("readme.md", "octet");
  let wrq = tftp_build_wrq("write.md", "octet");
  var empty = Vec[UInt8].new();
  let dat = tftp_build_data(3, &empty);
  let ack = tftp_build_ack(3);
  let err = tftp_build_error(1, "oops");
  var ok = op_int(&rrq) == 1;
  if op_int(&wrq) != 2 { ok = false; }
  if op_int(&dat) != 3 { ok = false; }
  if op_int(&ack) != 4 { ok = false; }
  if op_int(&err) != 5 { ok = false; }
  if !str_eq(rq_filename(&rrq), "readme.md") { ok = false; }
  if !str_eq(rq_filename(&wrq), "write.md") { ok = false; }
  if data_block(&dat) != 3 { ok = false; }
  if ack_block(&ack) != 3 { ok = false; }
  if error_code(&err) != 1 { ok = false; }
  if !str_eq(error_message(&err), "oops") { ok = false; }
  return assert(ok, "all five packet types round-trip end to end");
}

fn main() -> Int {
  io.println("=== xiom.tftp conformance tests ===");
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
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.tftp: all tests passed");
  } else {
    io.println("xiom.tftp: tests failed");
  }
  return failed;
}
