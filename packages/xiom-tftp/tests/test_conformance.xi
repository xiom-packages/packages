// XIOM -- xiom.tftp conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 9. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// Every Str comparison goes through compare.str_compare (BUG 17: `==` on
// Str values read from a Vec lowers to a pointer comparison), Result
// payloads are read through .is_ok/.value/.error, no match arms are used at
// all, and no test function builds a Vec inside a tuple-Result.

module tftp_tests
use xiom.io; use xiom.test;
use xiom.tftp;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Byte and string helpers
// --------------------------------------------------

// Expected bytes for a hex string (empty on malformed input; the affected
// check then fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  return r.value;
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

fn no_opts() -> Vec[Str] {
  var v = Vec[Str].new();
  return v;
}

// --------------------------------------------------
//  Result helpers
// --------------------------------------------------

fn bytes_of(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  return r.value;
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Build an RRQ for "f.bin"/octet carrying exactly one option.
fn build_rrq1(name: Str, value: Str) -> Result[Vec[UInt8], Str] {
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  names.push(name);
  values.push(value);
  return tftp_build_rrq("f.bin", "octet", &names, &values);
}

// Build an OACK carrying exactly one option.
fn build_oack1(name: Str, value: Str) -> Result[Vec[UInt8], Str] {
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  names.push(name);
  values.push(value);
  return tftp_build_oack(&names, &values);
}

// --------------------------------------------------
//  Parsed-packet accessors used by the checks
// --------------------------------------------------

fn p_err(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse(data);
  if r.is_ok {
    return "";
  }
  return r.error;
}

fn p_opcode(data: &Vec[UInt8]) -> Int {
  let r = tftp_parse(data);
  if !r.is_ok {
    return -1;
  }
  let p: TftpPacket = r.value;
  return tftp_opcode(&p);
}

fn p_filename(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse(data);
  if !r.is_ok {
    return "";
  }
  let p: TftpPacket = r.value;
  return tftp_filename(&p);
}

fn p_mode(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse(data);
  if !r.is_ok {
    return "";
  }
  let p: TftpPacket = r.value;
  return tftp_mode(&p);
}

fn p_block(data: &Vec[UInt8]) -> Int {
  let r = tftp_parse(data);
  if !r.is_ok {
    return -1;
  }
  let p: TftpPacket = r.value;
  return tftp_block(&p);
}

fn p_code(data: &Vec[UInt8]) -> Int {
  let r = tftp_parse(data);
  if !r.is_ok {
    return -1;
  }
  let p: TftpPacket = r.value;
  return tftp_error_code(&p);
}

fn p_msg(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse(data);
  if !r.is_ok {
    return "";
  }
  let p: TftpPacket = r.value;
  return tftp_error_message(&p);
}

fn p_count(data: &Vec[UInt8]) -> Int {
  let r = tftp_parse(data);
  if !r.is_ok {
    return -1;
  }
  let p: TftpPacket = r.value;
  return tftp_option_count(&p);
}

fn p_opt_name(data: &Vec[UInt8], i: Int) -> Str {
  let r = tftp_parse(data);
  if !r.is_ok {
    return "";
  }
  let p: TftpPacket = r.value;
  return tftp_option_name(&p, i);
}

fn p_opt_value(data: &Vec[UInt8], i: Int) -> Str {
  let r = tftp_parse(data);
  if !r.is_ok {
    return "";
  }
  let p: TftpPacket = r.value;
  return tftp_option_value(&p, i);
}

fn p_plen(data: &Vec[UInt8]) -> Int {
  let r = tftp_parse(data);
  if !r.is_ok {
    return -1;
  }
  let p: TftpPacket = r.value;
  return tftp_payload_len(&p);
}

fn p_payload(data: &Vec[UInt8]) -> Vec[UInt8] {
  let r = tftp_parse(data);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let p: TftpPacket = r.value;
  return tftp_payload_copy(&p);
}

// 1 = last at blksize, 0 = not last, -1 = parse error.
fn p_last(data: &Vec[UInt8], blksize: Int) -> Int {
  let r = tftp_parse(data);
  if !r.is_ok {
    return -1;
  }
  let p: TftpPacket = r.value;
  if tftp_is_last_block(&p, blksize) {
    return 1;
  }
  return 0;
}

// Parse-then-emit stability check for one packet.
fn emit_is(data: &Vec[UInt8]) -> Bool {
  let r = tftp_parse(data);
  if !r.is_ok {
    return false;
  }
  let p: TftpPacket = r.value;
  let e = tftp_emit(&p);
  if !e.is_ok {
    return false;
  }
  let eb: Vec[UInt8] = e.value;
  if eb.len() != data.len() {
    return false;
  }
  var i = 0;
  while i < eb.len() {
    if eb[i] != data[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Per-kind parser error helpers
// --------------------------------------------------

fn rrq_err(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse_rrq(data);
  if r.is_ok {
    return "";
  }
  return r.error;
}

fn wrq_err(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse_wrq(data);
  if r.is_ok {
    return "";
  }
  return r.error;
}

fn data_err(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse_data(data);
  if r.is_ok {
    return "";
  }
  return r.error;
}

fn ack_err(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse_ack(data);
  if r.is_ok {
    return "";
  }
  return r.error;
}

fn error_err(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse_error(data);
  if r.is_ok {
    return "";
  }
  return r.error;
}

fn oack_err(data: &Vec[UInt8]) -> Str {
  let r = tftp_parse_oack(data);
  if r.is_ok {
    return "";
  }
  return r.error;
}

fn op_of(data: &Vec[UInt8]) -> Int {
  let r = tftp_op(data);
  if !r.is_ok {
    return -1;
  }
  return r.value;
}

fn op_err(data: &Vec[UInt8]) -> Str {
  let r = tftp_op(data);
  if r.is_ok {
    return "";
  }
  return r.error;
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  let none = no_opts();
  let b = tftp_build_rrq("hello.txt", "octet", &none, &none);
  var ok = b.is_ok;
  if ok {
    let pkt: Vec[UInt8] = b.value;
    if pkt.len() != 18 { ok = false; }
    if !bytes_equal(pkt, hb("000168656c6c6f2e747874006f6374657400")) { ok = false; }
    if p_opcode(&pkt) != 1 { ok = false; }
    if !str_eq(p_filename(&pkt), "hello.txt") { ok = false; }
    if !str_eq(p_mode(&pkt), "octet") { ok = false; }
    if p_count(&pkt) != 0 { ok = false; }
    if !str_eq(tftp_opcode_name(1), "RRQ") { ok = false; }
  }
  return assert(ok, "RRQ hello.txt/octet is exact 18 bytes");
}

fn t2() -> TestResult {
  let none = no_opts();
  let b = tftp_build_wrq("upload.bin", "octet", &none, &none);
  var ok = b.is_ok;
  if ok {
    let pkt: Vec[UInt8] = b.value;
    if pkt.len() != 19 { ok = false; }
    if !bytes_equal(pkt, hb("000275706c6f61642e62696e006f6374657400")) { ok = false; }
    if p_opcode(&pkt) != 2 { ok = false; }
    if !str_eq(p_filename(&pkt), "upload.bin") { ok = false; }
    if !str_eq(p_mode(&pkt), "octet") { ok = false; }
    if !str_eq(tftp_opcode_name(2), "WRQ") { ok = false; }
  }
  return assert(ok, "WRQ upload.bin/octet is exact 19 bytes");
}

fn t3() -> TestResult {
  let none = no_opts();
  let mixed = hb("000161004f4354455400");
  var ok = p_opcode(&mixed) == 1;
  if !str_eq(p_mode(&mixed), "octet") { ok = false; }
  if !str_eq(p_filename(&mixed), "a") { ok = false; }
  let nat = tftp_build_rrq("a", "NeTaScIi", &none, &none);
  if !nat.is_ok { ok = false; } else {
    let np: Vec[UInt8] = nat.value;
    if !bytes_equal(np, hb("000161006e6574617363696900")) { ok = false; }
  }
  if !bytes_err_is(tftp_build_wrq("a", "binary", &none, &none), "tftp: bad mode") { ok = false; }
  if !str_eq(rrq_err(&hb("0001610062696e61727900")), "tftp: bad mode") { ok = false; }
  return assert(ok, "mode matches case-insensitively and emits lowercase");
}

fn t4() -> TestResult {
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  names.push("blksize");
  values.push("1428");
  names.push("timeout");
  values.push("5");
  names.push("tsize");
  values.push("1048576");
  let b = tftp_build_rrq("f.bin", "octet", &names, &values);
  var ok = b.is_ok;
  if ok {
    let pkt: Vec[UInt8] = b.value;
    if !bytes_equal(pkt, hb("0001662e62696e006f6374657400626c6b73697a6500313432380074696d656f75740035007473697a65003130343835373600")) { ok = false; }
    if p_count(&pkt) != 3 { ok = false; }
    if !str_eq(p_opt_name(&pkt, 0), "blksize") { ok = false; }
    if !str_eq(p_opt_value(&pkt, 0), "1428") { ok = false; }
    if !str_eq(p_opt_name(&pkt, 1), "timeout") { ok = false; }
    if !str_eq(p_opt_value(&pkt, 1), "5") { ok = false; }
    if !str_eq(p_opt_name(&pkt, 2), "tsize") { ok = false; }
    if !str_eq(p_opt_value(&pkt, 2), "1048576") { ok = false; }
    let rr = tftp_parse_rrq(&pkt);
    if !rr.is_ok { ok = false; }
  }
  return assert(ok, "RRQ carries blksize/timeout/tsize TLVs exactly");
}

fn t5() -> TestResult {
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  names.push("blksize");
  values.push("512");
  names.push("timeout");
  values.push("3");
  let b = tftp_build_oack(&names, &values);
  var ok = b.is_ok;
  if ok {
    let pkt: Vec[UInt8] = b.value;
    if !bytes_equal(pkt, hb("0006626c6b73697a65003531320074696d656f7574003300")) { ok = false; }
    if p_opcode(&pkt) != 6 { ok = false; }
    if !str_eq(tftp_opcode_name(6), "OACK") { ok = false; }
    if p_count(&pkt) != 2 { ok = false; }
    if !str_eq(p_opt_name(&pkt, 0), "blksize") { ok = false; }
    if !str_eq(p_opt_value(&pkt, 0), "512") { ok = false; }
    if !str_eq(p_opt_name(&pkt, 1), "timeout") { ok = false; }
    if !str_eq(p_opt_value(&pkt, 1), "3") { ok = false; }
  }
  return assert(ok, "OACK carries the accepted TLVs exactly");
}

fn t6() -> TestResult {
  let none = no_opts();
  var ok = bytes_err_is(tftp_build_oack(&none, &none), "tftp: empty OACK");
  if !str_eq(oack_err(&hb("0006")), "tftp: empty OACK") { ok = false; }
  if !str_eq(oack_err(&hb("0006626c6b")), "tftp: missing NUL") { ok = false; }
  let one = hb("0006610000");
  if p_opcode(&one) != 6 { ok = false; }
  if p_count(&one) != 1 { ok = false; }
  if !str_eq(p_opt_name(&one, 0), "a") { ok = false; }
  if !str_eq(p_opt_value(&one, 0), "") { ok = false; }
  return assert(ok, "OACK requires at least one complete TLV");
}

fn t7() -> TestResult {
  var ok = bytes_err_is(build_rrq1("blksize", "7"), "tftp: bad block size");
  if !bytes_err_is(build_rrq1("blksize", "65465"), "tftp: bad block size") { ok = false; }
  if !bytes_err_is(build_rrq1("blksize", "0"), "tftp: bad block size") { ok = false; }
  if !bytes_err_is(build_rrq1("blksize", "08"), "tftp: bad block size") { ok = false; }
  if !bytes_err_is(build_rrq1("blksize", ""), "tftp: bad block size") { ok = false; }
  if !bytes_err_is(build_rrq1("blksize", "8x"), "tftp: bad block size") { ok = false; }
  if !bytes_err_is(build_rrq1("timeout", "0"), "tftp: bad option value") { ok = false; }
  if !bytes_err_is(build_rrq1("timeout", "256"), "tftp: bad option value") { ok = false; }
  if !bytes_err_is(build_rrq1("tsize", "007"), "tftp: bad option value") { ok = false; }
  if !bytes_err_is(build_rrq1("tsize", "4294967296"), "tftp: bad option value") { ok = false; }
  if !bytes_err_is(build_rrq1("tsize", "-1"), "tftp: bad option value") { ok = false; }
  if !build_rrq1("blksize", "8").is_ok { ok = false; }
  if !build_rrq1("blksize", "65464").is_ok { ok = false; }
  if !build_rrq1("timeout", "1").is_ok { ok = false; }
  if !build_rrq1("timeout", "255").is_ok { ok = false; }
  if !build_rrq1("tsize", "0").is_ok { ok = false; }
  if !build_rrq1("tsize", "4294967295").is_ok { ok = false; }
  if !str_eq(rrq_err(&hb("000166006f6374657400626c6b73697a65003400")), "tftp: bad block size") { ok = false; }
  return assert(ok, "blksize/timeout/tsize ranges and canonical decimals");
}

fn t8() -> TestResult {
  let w = build_rrq1("windowsize", "4");
  var ok = w.is_ok;
  if ok {
    let pkt: Vec[UInt8] = w.value;
    if !bytes_equal(pkt, hb("0001662e62696e006f637465740077696e646f7773697a65003400")) { ok = false; }
    if p_count(&pkt) != 1 { ok = false; }
    if !str_eq(p_opt_name(&pkt, 0), "windowsize") { ok = false; }
    if !str_eq(p_opt_value(&pkt, 0), "4") { ok = false; }
  }
  var n1 = Vec[Str].new();
  n1.push("blksize");
  let v0 = no_opts();
  if !bytes_err_is(tftp_build_rrq("f.bin", "octet", &n1, &v0), "tftp: option pool mismatch") { ok = false; }
  if !bytes_err_is(tftp_build_oack(&n1, &v0), "tftp: option pool mismatch") { ok = false; }
  let mixed = build_rrq1("BLKSIZE", "1024");
  if !mixed.is_ok { ok = false; } else {
    let mp: Vec[UInt8] = mixed.value;
    if !str_eq(p_opt_name(&mp, 0), "blksize") { ok = false; }
  }
  if !bytes_err_is(build_rrq1("a\u{0009}b", "1"), "tftp: bad option name") { ok = false; }
  return assert(ok, "unknown options pass through, known names canonicalize");
}

fn t9() -> TestResult {
  let payload = hb("010203");
  let b = tftp_build_data(1, &payload);
  var ok = b.is_ok;
  if ok {
    let pkt: Vec[UInt8] = b.value;
    if !bytes_equal(pkt, hb("00030001010203")) { ok = false; }
    if p_opcode(&pkt) != 3 { ok = false; }
    if p_block(&pkt) != 1 { ok = false; }
    if !bytes_equal(p_payload(&pkt), payload) { ok = false; }
  }
  return assert(ok, "DATA block 1 payload 010203 is exact bytes");
}

fn t10() -> TestResult {
  var empty = Vec[UInt8].new();
  let b = tftp_build_data(7, &empty);
  var ok = b.is_ok;
  if ok {
    let pkt: Vec[UInt8] = b.value;
    if pkt.len() != 4 { ok = false; }
    if !bytes_equal(pkt, hb("00030007")) { ok = false; }
    if p_block(&pkt) != 7 { ok = false; }
    if p_plen(&pkt) != 0 { ok = false; }
    if p_last(&pkt, 512) != 1 { ok = false; }
  }
  if !str_eq(data_err(&hb("0003")), "tftp: short packet") { ok = false; }
  if !str_eq(data_err(&hb("000300")), "tftp: short packet") { ok = false; }
  if !str_eq(data_err(&hb("")), "tftp: short packet") { ok = false; }
  if !str_eq(data_err(&hb("00040000")), "tftp: not a DATA packet") { ok = false; }
  return assert(ok, "empty DATA payload round-trips; short headers rejected");
}

fn t11() -> TestResult {
  let full = repeat_byte(65, 65464);
  let b = tftp_build_data(1, &full);
  var ok = b.is_ok;
  if ok {
    let pkt: Vec[UInt8] = b.value;
    if pkt.len() != 65468 { ok = false; }
    if p_plen(&pkt) != 65464 { ok = false; }
    if !bytes_equal(p_payload(&pkt), full) { ok = false; }
    if p_last(&pkt, 65464) != 0 { ok = false; }
  }
  let over = repeat_byte(65, 65465);
  if !bytes_err_is(tftp_build_data(1, &over), "tftp: payload too long") { ok = false; }
  let huge = concat_bytes(hb("00030001"), over);
  if !str_eq(data_err(&huge), "tftp: payload too long") { ok = false; }
  return assert(ok, "DATA payload caps at the 65464-byte protocol maximum");
}

fn t12() -> TestResult {
  var ok = bytes_equal(bytes_of(tftp_build_ack(0)), hb("00040000"));
  if !bytes_equal(bytes_of(tftp_build_ack(1)), hb("00040001")) { ok = false; }
  if !bytes_equal(bytes_of(tftp_build_ack(65535)), hb("0004ffff")) { ok = false; }
  if !bytes_equal(bytes_of(tftp_build_ack(-1)), hb("00040000")) { ok = false; }
  if !bytes_equal(bytes_of(tftp_build_ack(100000)), hb("0004ffff")) { ok = false; }
  let a300 = bytes_of(tftp_build_ack(300));
  if p_block(&a300) != 300 { ok = false; }
  if p_opcode(&a300) != 4 { ok = false; }
  if !str_eq(tftp_opcode_name(4), "ACK") { ok = false; }
  if !str_eq(ack_err(&hb("00040000ff")), "tftp: trailing bytes") { ok = false; }
  if !str_eq(ack_err(&hb("000400")), "tftp: short packet") { ok = false; }
  if !str_eq(ack_err(&hb("0004")), "tftp: short packet") { ok = false; }
  if !str_eq(ack_err(&hb("")), "tftp: short packet") { ok = false; }
  if !str_eq(ack_err(&hb("0003000102")), "tftp: not an ACK") { ok = false; }
  return assert(ok, "ACK is exactly 4 bytes with clamped block numbers");
}

fn t13() -> TestResult {
  let b = tftp_build_error(1, "File not found");
  var ok = b.is_ok;
  if ok {
    let pkt: Vec[UInt8] = b.value;
    if !bytes_equal(pkt, hb("0005000146696c65206e6f7420666f756e6400")) { ok = false; }
    if p_opcode(&pkt) != 5 { ok = false; }
    if p_code(&pkt) != 1 { ok = false; }
    if !str_eq(p_msg(&pkt), "File not found") { ok = false; }
    if !str_eq(tftp_opcode_name(5), "ERROR") { ok = false; }
  }
  let eb = tftp_build_error(0, "");
  if !eb.is_ok { ok = false; } else {
    let e0: Vec[UInt8] = eb.value;
    if !bytes_equal(e0, hb("0005000000")) { ok = false; }
  }
  if !bytes_equal(bytes_of(tftp_build_error(-3, "x")), hb("000500007800")) { ok = false; }
  if !bytes_equal(bytes_of(tftp_build_error(70000, "x")), hb("0005ffff7800")) { ok = false; }
  if !str_eq(tftp_error_name(0), "not defined") { ok = false; }
  if !str_eq(tftp_error_name(1), "file not found") { ok = false; }
  if !str_eq(tftp_error_name(2), "access violation") { ok = false; }
  if !str_eq(tftp_error_name(3), "disk full") { ok = false; }
  if !str_eq(tftp_error_name(4), "illegal operation") { ok = false; }
  if !str_eq(tftp_error_name(5), "unknown transfer id") { ok = false; }
  if !str_eq(tftp_error_name(6), "file already exists") { ok = false; }
  if !str_eq(tftp_error_name(7), "no such user") { ok = false; }
  if !str_eq(tftp_error_name(12), "unknown") { ok = false; }
  return assert(ok, "ERROR code table and 0..65535 clamping");
}

fn t14() -> TestResult {
  var ok = str_eq(error_err(&hb("000500014162630000")), "tftp: trailing bytes");
  if !str_eq(error_err(&hb("00050001416263")), "tftp: missing NUL") { ok = false; }
  if !str_eq(error_err(&hb("00050001")), "tftp: short packet") { ok = false; }
  if !str_eq(error_err(&hb("0005")), "tftp: short packet") { ok = false; }
  if !str_eq(error_err(&hb("00040000")), "tftp: not an ERROR packet") { ok = false; }
  let em = hb("0005000200");
  if !(p_err(&em).len() == 0) { ok = false; }
  if p_code(&em) != 2 { ok = false; }
  if !str_eq(p_msg(&em), "") { ok = false; }
  return assert(ok, "ERROR message is verbatim and ends exactly at its NUL");
}

fn t15() -> TestResult {
  var ok = op_of(&hb("0001")) == 1;
  if op_of(&hb("0002")) != 2 { ok = false; }
  if op_of(&hb("0003")) != 3 { ok = false; }
  if op_of(&hb("0004")) != 4 { ok = false; }
  if op_of(&hb("0005")) != 5 { ok = false; }
  if op_of(&hb("0006")) != 6 { ok = false; }
  if !str_eq(op_err(&hb("0000")), "tftp: unknown opcode") { ok = false; }
  if !str_eq(op_err(&hb("0007")), "tftp: unknown opcode") { ok = false; }
  if !str_eq(op_err(&hb("ffff")), "tftp: unknown opcode") { ok = false; }
  if !str_eq(op_err(&hb("00")), "tftp: short packet") { ok = false; }
  if !str_eq(op_err(&hb("")), "tftp: short packet") { ok = false; }
  if !str_eq(p_err(&hb("0000")), "tftp: unknown opcode") { ok = false; }
  if !str_eq(p_err(&hb("")), "tftp: short packet") { ok = false; }
  if !str_eq(tftp_opcode_name(0), "UNKNOWN") { ok = false; }
  return assert(ok, "tftp_op accepts 1..6 and rejects unknown/short input");
}

fn t16() -> TestResult {
  let canon_in = hb("0001612e62696e004f4354455400424c4b53495a45003130323400");
  var ok = true;
  if emit_is(&canon_in) { ok = false; }
  let want = hb("0001612e62696e006f6374657400626c6b73697a65003130323400");
  let r = tftp_parse(&canon_in);
  if !r.is_ok { ok = false; } else {
    let p: TftpPacket = r.value;
    let e = tftp_emit(&p);
    if !e.is_ok { ok = false; } else {
      let eb: Vec[UInt8] = e.value;
      if !bytes_equal(eb, want) { ok = false; }
    }
  }
  let unknown_in = hb("000161006f637465740057694e644f7753695a65003400");
  if !emit_is(&unknown_in) { ok = false; }
  return assert(ok, "emitter canonicalizes known names and preserves unknown ones");
}

fn t17() -> TestResult {
  let none = no_opts();
  var rn = Vec[Str].new();
  var rv = Vec[Str].new();
  rn.push("blksize");
  rv.push("512");
  let pl = hb("deadbeef");
  let s1 = bytes_of(tftp_build_rrq("a.txt", "octet", &rn, &rv));
  let s2 = bytes_of(tftp_build_wrq("b.txt", "netascii", &none, &none));
  let s3 = bytes_of(tftp_build_data(7, &pl));
  let s4 = bytes_of(tftp_build_ack(7));
  let s5 = bytes_of(tftp_build_error(1, "File not found"));
  let s6 = bytes_of(tftp_build_oack(&rn, &rv));
  var ok = p_opcode(&s1) == 1;
  if p_opcode(&s2) != 2 { ok = false; }
  if p_opcode(&s3) != 3 { ok = false; }
  if p_opcode(&s4) != 4 { ok = false; }
  if p_opcode(&s5) != 5 { ok = false; }
  if p_opcode(&s6) != 6 { ok = false; }
  if !emit_is(&s1) { ok = false; }
  if !emit_is(&s2) { ok = false; }
  if !emit_is(&s3) { ok = false; }
  if !emit_is(&s4) { ok = false; }
  if !emit_is(&s5) { ok = false; }
  if !emit_is(&s6) { ok = false; }
  return assert(ok, "all six packet kinds round-trip parse->emit byte-for-byte");
}

fn t18() -> TestResult {
  let none = no_opts();
  var ok = bytes_err_is(tftp_build_rrq("", "octet", &none, &none), "tftp: bad filename");
  if !bytes_err_is(tftp_build_wrq("", "octet", &none, &none), "tftp: bad filename") { ok = false; }
  if !bytes_err_is(tftp_build_rrq("a\u{0009}b", "octet", &none, &none), "tftp: bad filename") { ok = false; }
  if !bytes_err_is(tftp_build_rrq("a\u{007F}b", "octet", &none, &none), "tftp: bad filename") { ok = false; }
  if !str_eq(rrq_err(&hb("0001006f6374657400")), "tftp: bad filename") { ok = false; }
  if !str_eq(rrq_err(&hb("0001618062006f6374657400")), "tftp: bad filename") { ok = false; }
  if !str_eq(rrq_err(&hb("0001610962006f6374657400")), "tftp: bad filename") { ok = false; }
  if !str_eq(rrq_err(&hb("000168656c6c6f2e74787400")), "tftp: missing NUL") { ok = false; }
  return assert(ok, "RRQ/WRQ filenames are non-empty printable ASCII");
}

fn t19() -> TestResult {
  let payload = hb("00ff807f0102");
  let b = tftp_build_data(42, &payload);
  var ok = b.is_ok;
  if ok {
    let pkt: Vec[UInt8] = b.value;
    if !bytes_equal(pkt, hb("0003002a00ff807f0102")) { ok = false; }
    if p_block(&pkt) != 42 { ok = false; }
    if p_plen(&pkt) != 6 { ok = false; }
    if !bytes_equal(p_payload(&pkt), payload) { ok = false; }
    let r = tftp_parse(&pkt);
    if !r.is_ok { ok = false; } else {
      let p: TftpPacket = r.value;
      if tftp_payload_byte(&p, 0) != 0 { ok = false; }
      if tftp_payload_byte(&p, 1) != 255 { ok = false; }
      if tftp_payload_byte(&p, 2) != 128 { ok = false; }
      if tftp_payload_byte(&p, 3) != 127 { ok = false; }
      if tftp_payload_byte(&p, 4) != 1 { ok = false; }
      if tftp_payload_byte(&p, 5) != 2 { ok = false; }
    }
  }
  return assert(ok, "DATA payload carries NUL and high bytes verbatim");
}

fn t20() -> TestResult {
  var empty = Vec[UInt8].new();
  let p511 = repeat_byte(65, 511);
  let p512 = repeat_byte(65, 512);
  let d0 = bytes_of(tftp_build_data(1, &empty));
  let d511 = bytes_of(tftp_build_data(1, &p511));
  let d512 = bytes_of(tftp_build_data(1, &p512));
  var ok = p_last(&d0, 512) == 1;
  if p_last(&d511, 512) != 1 { ok = false; }
  if p_last(&d512, 512) != 0 { ok = false; }
  let p1427 = repeat_byte(66, 1427);
  let p1428 = repeat_byte(66, 1428);
  let d1427 = bytes_of(tftp_build_data(2, &p1427));
  let d1428 = bytes_of(tftp_build_data(2, &p1428));
  if p_last(&d1427, 1428) != 1 { ok = false; }
  if p_last(&d1428, 1428) != 0 { ok = false; }
  if p_last(&d511, 0) != 1 { ok = false; }
  if p_last(&d512, 70000) != 0 { ok = false; }
  let ack = bytes_of(tftp_build_ack(1));
  if p_last(&ack, 512) != 0 { ok = false; }
  return assert(ok, "is_last_block: 512 default, negotiated blksize, non-DATA");
}

fn t21() -> TestResult {
  var ok = str_eq(rrq_err(&hb("000161")), "tftp: missing NUL");
  if !str_eq(rrq_err(&hb("000161006f63746574")), "tftp: missing NUL") { ok = false; }
  if !str_eq(rrq_err(&hb("000161006f6374657400626c6b")), "tftp: missing NUL") { ok = false; }
  if !str_eq(rrq_err(&hb("000161006f6374657400626c6b00")), "tftp: missing NUL") { ok = false; }
  if !str_eq(oack_err(&hb("0006626c6b")), "tftp: missing NUL") { ok = false; }
  if !str_eq(error_err(&hb("00050001416263")), "tftp: missing NUL") { ok = false; }
  return assert(ok, "unterminated filename/mode/option/message report missing NUL");
}

fn t22() -> TestResult {
  var ok = str_eq(ack_err(&hb("0004000000")), "tftp: trailing bytes");
  if !str_eq(error_err(&hb("000500014162630000")), "tftp: trailing bytes") { ok = false; }
  if !str_eq(oack_err(&hb("000600")), "tftp: missing NUL") { ok = false; }
  let full = hb("000161006f6374657400626c6b73697a650035313200");
  if !(p_err(&full).len() == 0) { ok = false; }
  if p_count(&full) != 1 { ok = false; }
  if p_opcode(&full) != 1 { ok = false; }
  return assert(ok, "exact-size policy: consumed options, no trailing bytes");
}

fn t23() -> TestResult {
  let optp = hb("000161006f6374657400626c6b73697a65003130323400");
  let dp = hb("00030005010203");
  let r = tftp_parse(&optp);
  let dr = tftp_parse(&dp);
  var ok = r.is_ok;
  if !dr.is_ok { ok = false; }
  if r.is_ok {
    let p: TftpPacket = r.value;
    if tftp_option_count(&p) != 1 { ok = false; }
    if !str_eq(tftp_option_name(&p, -1), "") { ok = false; }
    if !str_eq(tftp_option_name(&p, 1), "") { ok = false; }
    if !str_eq(tftp_option_value(&p, 9), "") { ok = false; }
    if tftp_payload_byte(&p, 0) != -1 { ok = false; }
  }
  if dr.is_ok {
    let d: TftpPacket = dr.value;
    if tftp_block(&d) != 5 { ok = false; }
    if tftp_payload_len(&d) != 3 { ok = false; }
    if tftp_payload_byte(&d, -1) != -1 { ok = false; }
    if tftp_payload_byte(&d, 3) != -1 { ok = false; }
    if tftp_payload_byte(&d, 2) != 3 { ok = false; }
    if !str_eq(tftp_filename(&d), "") { ok = false; }
  }
  if !str_eq(tftp_opcode_name(9), "UNKNOWN") { ok = false; }
  if !str_eq(tftp_error_name(99), "unknown") { ok = false; }
  return assert(ok, "out-of-range accessors return empty/-1 sentinels");
}

fn t24() -> TestResult {
  let none = no_opts();
  var empty = Vec[UInt8].new();
  let rrq = bytes_of(tftp_build_rrq("a", "octet", &none, &none));
  let wrq = bytes_of(tftp_build_wrq("a", "octet", &none, &none));
  let dat = bytes_of(tftp_build_data(1, &empty));
  let ack = bytes_of(tftp_build_ack(1));
  let err = bytes_of(tftp_build_error(1, "e"));
  var ok = str_eq(wrq_err(&rrq), "tftp: not a WRQ");
  if !str_eq(rrq_err(&wrq), "tftp: not an RRQ") { ok = false; }
  if !str_eq(data_err(&rrq), "tftp: not a DATA packet") { ok = false; }
  if !str_eq(ack_err(&dat), "tftp: not an ACK") { ok = false; }
  if !str_eq(error_err(&ack), "tftp: not an ERROR packet") { ok = false; }
  if !str_eq(oack_err(&ack), "tftp: not an OACK") { ok = false; }
  if !str_eq(p_err(&hb("0009")), "tftp: unknown opcode") { ok = false; }
  if !str_eq(rrq_err(&hb("0009")), "tftp: not an RRQ") { ok = false; }
  return assert(ok, "per-kind parsers reject other opcodes with stable errors");
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
