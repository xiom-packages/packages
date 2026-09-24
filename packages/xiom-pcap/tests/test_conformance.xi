// XIOM -- xiom.pcap conformance tests (17 checks)
// Port task: prove the pure-XIOM xiom.pcap reader against classic PCAP
// capture files in both byte orders.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The two fixtures are assembled byte by byte (byte pushes), so the parser
// is exercised against bytes this test file controls: a 62-byte
// little-endian file with two packet records (4- and 2-byte payloads) and a
// 43-byte big-endian file with one 3-byte record. Global-header fields,
// record offsets, timestamps, caplen/origlen, packet slices and the error
// catalog are pinned. Str equality goes through str_compare (BUG 17
// discipline: `==` on Str values read from a Vec lowers to a pointer
// comparison).

module pcap_tests
use xiom.io; use xiom.test;
use xiom.pcap;
use xiom.string.compare;

// --------------------------------------------------
//  Helpers (independent of src/pcap.xi)
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_file_is(r: Result[PcapFile, Str], want: Str) -> Bool {
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

fn bytes1(a: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  return v;
}

fn bytes2(a: Int, b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return v;
}

fn bytes3(a: Int, b: Int, c: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  return v;
}

fn bytes4(a: Int, b: Int, c: Int, d: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  v.push(d as UInt8);
  return v;
}

fn push_byte(v: &mut Vec[UInt8], b: Int) {
  v.push(b as UInt8);
}

fn push_le16(v: &mut Vec[UInt8], n: Int) {
  push_byte(v, n % 256);
  push_byte(v, (n / 256) % 256);
}

fn push_le32(v: &mut Vec[UInt8], n: Int) {
  push_byte(v, n % 256);
  push_byte(v, (n / 256) % 256);
  push_byte(v, (n / 65536) % 256);
  push_byte(v, (n / 16777216) % 256);
}

fn push_be16(v: &mut Vec[UInt8], n: Int) {
  push_byte(v, (n / 256) % 256);
  push_byte(v, n % 256);
}

fn push_be32(v: &mut Vec[UInt8], n: Int) {
  push_byte(v, (n / 16777216) % 256);
  push_byte(v, (n / 65536) % 256);
  push_byte(v, (n / 256) % 256);
  push_byte(v, n % 256);
}

// One little-endian packet-record header (ts_sec, ts_usec, incl_len,
// orig_len); the payload bytes are pushed by the caller.
fn push_rec_le(v: &mut Vec[UInt8], ts_sec: Int, ts_usec: Int, incl: Int, orig: Int) {
  push_le32(v, ts_sec);
  push_le32(v, ts_usec);
  push_le32(v, incl);
  push_le32(v, orig);
}

// 24-byte little-endian global header: magic D4 C3 B2 A1, version 2.4,
// thiszone 0, sigfigs 0, then the given snaplen and linktype.
fn header_le(snaplen: Int, linktype: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 212);
  push_byte(&mut v, 195);
  push_byte(&mut v, 178);
  push_byte(&mut v, 161);
  push_le16(&mut v, 2);
  push_le16(&mut v, 4);
  push_le32(&mut v, 0);
  push_le32(&mut v, 0);
  push_le32(&mut v, snaplen);
  push_le32(&mut v, linktype);
  return v;
}

// 62-byte LE file: header_le(65535, 1) + record(1600000000, 123456, incl 4,
// orig 6, payload 01 02 03 04) + record(1600000001, 7, incl 2, orig 2,
// payload aa bb).
fn le_fixture() -> Vec[UInt8] {
  var v = header_le(65535, 1);
  push_rec_le(&mut v, 1600000000, 123456, 4, 6);
  push_byte(&mut v, 1);
  push_byte(&mut v, 2);
  push_byte(&mut v, 3);
  push_byte(&mut v, 4);
  push_rec_le(&mut v, 1600000001, 7, 2, 2);
  push_byte(&mut v, 170);
  push_byte(&mut v, 187);
  return v;
}

// 43-byte BE file: magic A1 B2 C3 D4, version 2.4, thiszone 0, sigfigs 0,
// snaplen 262144, linktype 1, then record(1600000000, 0, incl 3, orig 3,
// payload de ad be).
fn be_fixture() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 161);
  push_byte(&mut v, 178);
  push_byte(&mut v, 195);
  push_byte(&mut v, 212);
  push_be16(&mut v, 2);
  push_be16(&mut v, 4);
  push_be32(&mut v, 0);
  push_be32(&mut v, 0);
  push_be32(&mut v, 262144);
  push_be32(&mut v, 1);
  push_be32(&mut v, 1600000000);
  push_be32(&mut v, 0);
  push_be32(&mut v, 3);
  push_be32(&mut v, 3);
  push_byte(&mut v, 222);
  push_byte(&mut v, 173);
  push_byte(&mut v, 190);
  return v;
}

fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let fx = le_fixture();
  var ok = fx.len() == 62;
  if !pcap_is_file(&fx) { ok = false; }
  let pr = pcap_parse(&fx);
  if !pr.is_ok { return assert(false, "LE fixture must parse"); }
  let p = pr.value;
  if p.magic != 2712847316 { ok = false; }
  if !p.little_endian { ok = false; }
  if p.version_major != 2 { ok = false; }
  if p.version_minor != 4 { ok = false; }
  if p.snaplen != 65535 { ok = false; }
  if p.linktype != 1 { ok = false; }
  if pcap_packet_count(&p) != 2 { ok = false; }
  return assert(ok, "LE fixture: header fields and packet count pinned");
}

fn t2() -> TestResult {
  let fx = le_fixture();
  let pr = pcap_parse(&fx);
  if !pr.is_ok { return assert(false, "LE fixture must parse"); }
  let p = pr.value;
  let r0 = pcap_packet(&fx, &p, 0);
  let r1 = pcap_packet(&fx, &p, 1);
  var ok = r0.is_ok;
  if !r1.is_ok { ok = false; }
  if ok {
    if !bytes_equal(r0.value, bytes4(1, 2, 3, 4)) { ok = false; }
    if !bytes_equal(r1.value, bytes2(170, 187)) { ok = false; }
  }
  return assert(ok, "LE fixture: packet slices are exact");
}

fn t3() -> TestResult {
  let fx = le_fixture();
  let pr = pcap_parse(&fx);
  if !pr.is_ok { return assert(false, "LE fixture must parse"); }
  let p = pr.value;
  let ts0: Int = pcap_ts_sec(&p, 0);
  let ts1: Int = pcap_ts_sec(&p, 1);
  let cl0: Int = pcap_caplen(&p, 0);
  let cl1: Int = pcap_caplen(&p, 1);
  let ol0: Int = pcap_origlen(&p, 0);
  let ol1: Int = pcap_origlen(&p, 1);
  let o0: Int = p.offsets[0];
  let o1: Int = p.offsets[1];
  var ok = ts0 == 1600000000;
  if ts1 != 1600000001 { ok = false; }
  if cl0 != 4 { ok = false; }
  if cl1 != 2 { ok = false; }
  if ol0 != 6 { ok = false; }
  if ol1 != 2 { ok = false; }
  if o0 != 40 { ok = false; }
  if o1 != 60 { ok = false; }
  if pcap_linktype(&p) != 1 { ok = false; }
  return assert(ok, "LE fixture: ts_sec/caplen/origlen/offsets pinned");
}

fn t4() -> TestResult {
  let hdr = prefix(le_fixture(), 24);
  var ok = hdr.len() == 24;
  if !pcap_is_file(&hdr) { ok = false; }
  let pr = pcap_parse(&hdr);
  if !pr.is_ok { return assert(false, "24-byte header must parse"); }
  let p = pr.value;
  if pcap_packet_count(&p) != 0 { ok = false; }
  if p.magic != 2712847316 { ok = false; }
  if !p.little_endian { ok = false; }
  if p.snaplen != 65535 { ok = false; }
  if pcap_linktype(&p) != 1 { ok = false; }
  if pcap_caplen(&p, 0) != -1 { ok = false; }
  if !err_bytes_is(pcap_packet(&hdr, &p, 0), "pcap: packet out of range") { ok = false; }
  return assert(ok, "24-byte header: empty record list, accessors guarded");
}

fn t5() -> TestResult {
  let fx = be_fixture();
  var ok = fx.len() == 43;
  if !pcap_is_file(&fx) { ok = false; }
  let pr = pcap_parse(&fx);
  if !pr.is_ok { return assert(false, "BE fixture must parse"); }
  let p = pr.value;
  if p.magic != 2712847316 { ok = false; }
  if p.little_endian { ok = false; }
  if p.version_major != 2 { ok = false; }
  if p.version_minor != 4 { ok = false; }
  if p.snaplen != 262144 { ok = false; }
  if p.linktype != 1 { ok = false; }
  if pcap_packet_count(&p) != 1 { ok = false; }
  if pcap_ts_sec(&p, 0) != 1600000000 { ok = false; }
  if pcap_caplen(&p, 0) != 3 { ok = false; }
  if pcap_origlen(&p, 0) != 3 { ok = false; }
  let r = pcap_packet(&fx, &p, 0);
  if !r.is_ok { ok = false; } elif !bytes_equal(r.value, bytes3(222, 173, 190)) { ok = false; }
  return assert(ok, "byte-swapped magic: fields, endianness and slice");
}

fn t6() -> TestResult {
  var empty = Vec[UInt8].new();
  let full = le_fixture();
  let cut23 = prefix(full, 23);
  let magic4 = prefix(full, 4);
  var ok = err_file_is(pcap_parse(&empty), "pcap: truncated header");
  if !err_file_is(pcap_parse(&cut23), "pcap: truncated header") { ok = false; }
  if !err_file_is(pcap_parse(&magic4), "pcap: truncated header") { ok = false; }
  if pcap_is_file(&empty) { ok = false; }
  if pcap_is_file(&cut23) { ok = false; }
  if pcap_is_file(&magic4) { ok = false; }
  return assert(ok, "inputs shorter than 24 bytes: truncated header");
}

fn t7() -> TestResult {
  var zeros24 = Vec[UInt8].new();
  var i = 0;
  while i < 24 {
    push_byte(&mut zeros24, 0);
    i = i + 1;
  }
  var ok = err_file_is(pcap_parse(&zeros24), "pcap: bad magic");
  if pcap_is_file(&zeros24) { ok = false; }
  let full = le_fixture();
  var bad = Vec[UInt8].new();
  i = 0;
  while i < full.len() {
    if i == 0 {
      push_byte(&mut bad, 213);
    } else {
      bad.push(full[i]);
    }
    i = i + 1;
  }
  if !err_file_is(pcap_parse(&bad), "pcap: bad magic") { ok = false; }
  if pcap_is_file(&bad) { ok = false; }
  var junk = Vec[UInt8].new();
  push_byte(&mut junk, 10);
  push_byte(&mut junk, 13);
  push_byte(&mut junk, 13);
  push_byte(&mut junk, 10);
  i = 4;
  while i < 32 {
    push_byte(&mut junk, 0);
    i = i + 1;
  }
  if !err_file_is(pcap_parse(&junk), "pcap: bad magic") { ok = false; }
  return assert(ok, "unrecognized magic (including pcapng) is Err");
}

fn t8() -> TestResult {
  let full = le_fixture();
  let cut8 = prefix(full, 52);
  let cut15 = prefix(full, 59);
  var ok = err_file_is(pcap_parse(&cut8), "pcap: truncated record");
  if !err_file_is(pcap_parse(&cut15), "pcap: truncated record") { ok = false; }
  if !pcap_parse(&full).is_ok { ok = false; }
  return assert(ok, "partial record header is Err after a valid record");
}

fn t9() -> TestResult {
  var over = header_le(65535, 1);
  push_rec_le(&mut over, 9, 1, 10, 10);
  push_byte(&mut over, 55);
  push_byte(&mut over, 55);
  push_byte(&mut over, 55);
  push_byte(&mut over, 55);
  var ok = err_file_is(pcap_parse(&over), "pcap: truncated packet");
  var under = header_le(65535, 1);
  push_rec_le(&mut under, 9, 1, 10, 10);
  push_byte(&mut under, 55);
  push_byte(&mut under, 55);
  push_byte(&mut under, 55);
  if !err_file_is(pcap_parse(&under), "pcap: truncated packet") { ok = false; }
  var exact = header_le(65535, 1);
  push_rec_le(&mut exact, 9, 1, 4, 8);
  push_byte(&mut exact, 55);
  push_byte(&mut exact, 55);
  push_byte(&mut exact, 55);
  push_byte(&mut exact, 55);
  let pr = pcap_parse(&exact);
  if !pr.is_ok {
    ok = false;
  } else {
    let p = pr.value;
    if pcap_packet_count(&p) != 1 { ok = false; }
    if pcap_origlen(&p, 0) != 8 { ok = false; }
  }
  return assert(ok, "declared incl_len must fit the remaining buffer");
}

fn t10() -> TestResult {
  let fx = le_fixture();
  let pr = pcap_parse(&fx);
  if !pr.is_ok { return assert(false, "LE fixture must parse"); }
  let p = pr.value;
  var ok = err_bytes_is(pcap_packet(&fx, &p, -1), "pcap: packet out of range");
  if !err_bytes_is(pcap_packet(&fx, &p, 2), "pcap: packet out of range") { ok = false; }
  if !err_bytes_is(pcap_packet(&fx, &p, 99), "pcap: packet out of range") { ok = false; }
  return assert(ok, "packet index out of range is Err");
}

fn t11() -> TestResult {
  let fx = le_fixture();
  let pr = pcap_parse(&fx);
  if !pr.is_ok { return assert(false, "LE fixture must parse"); }
  let p = pr.value;
  var ok = pcap_caplen(&p, -1) == -1;
  if pcap_caplen(&p, 2) != -1 { ok = false; }
  if pcap_origlen(&p, -1) != -1 { ok = false; }
  if pcap_origlen(&p, 2) != -1 { ok = false; }
  if pcap_ts_sec(&p, -1) != -1 { ok = false; }
  if pcap_ts_sec(&p, 2) != -1 { ok = false; }
  return assert(ok, "record accessors return -1 out of range");
}

fn t12() -> TestResult {
  let le = le_fixture();
  let be = be_fixture();
  let le24 = prefix(le, 24);
  let be24 = prefix(be, 24);
  var ok = pcap_is_file(&le);
  if !pcap_is_file(&be) { ok = false; }
  if !pcap_is_file(&le24) { ok = false; }
  if !pcap_is_file(&be24) { ok = false; }
  var empty = Vec[UInt8].new();
  if pcap_is_file(&empty) { ok = false; }
  let le23 = prefix(le, 23);
  let le4 = prefix(le, 4);
  if pcap_is_file(&le23) { ok = false; }
  if pcap_is_file(&le4) { ok = false; }
  var zeros24 = Vec[UInt8].new();
  var i = 0;
  while i < 24 {
    push_byte(&mut zeros24, 0);
    i = i + 1;
  }
  if pcap_is_file(&zeros24) { ok = false; }
  var junk = Vec[UInt8].new();
  push_byte(&mut junk, 10);
  push_byte(&mut junk, 13);
  push_byte(&mut junk, 13);
  push_byte(&mut junk, 10);
  i = 4;
  while i < 24 {
    push_byte(&mut junk, 0);
    i = i + 1;
  }
  if pcap_is_file(&junk) { ok = false; }
  return assert(ok, "is_file: both magics true; short/wrong magic false");
}

fn t13() -> TestResult {
  var fx = header_le(65535, 1);
  push_rec_le(&mut fx, 5, 0, 0, 5);
  push_rec_le(&mut fx, 6, 0, 2, 2);
  push_byte(&mut fx, 9);
  push_byte(&mut fx, 8);
  push_rec_le(&mut fx, 7, 0, 1, 1);
  push_byte(&mut fx, 7);
  var ok = fx.len() == 75;
  let pr = pcap_parse(&fx);
  if !pr.is_ok { return assert(false, "zero-length record fixture must parse"); }
  let p = pr.value;
  if pcap_packet_count(&p) != 3 { ok = false; }
  if pcap_caplen(&p, 0) != 0 { ok = false; }
  if pcap_origlen(&p, 0) != 5 { ok = false; }
  let o0: Int = p.offsets[0];
  let o1: Int = p.offsets[1];
  let o2: Int = p.offsets[2];
  if o0 != 40 { ok = false; }
  if o1 != 56 { ok = false; }
  if o2 != 74 { ok = false; }
  let r0 = pcap_packet(&fx, &p, 0);
  if !r0.is_ok { ok = false; } elif r0.value.len() != 0 { ok = false; }
  let r1 = pcap_packet(&fx, &p, 1);
  if !r1.is_ok { ok = false; } elif !bytes_equal(r1.value, bytes2(9, 8)) { ok = false; }
  let r2 = pcap_packet(&fx, &p, 2);
  if !r2.is_ok { ok = false; } elif !bytes_equal(r2.value, bytes1(7)) { ok = false; }
  return assert(ok, "zero-length record advances to the next record");
}

fn t14() -> TestResult {
  let fx = le_fixture();
  let pr = pcap_parse(&fx);
  if !pr.is_ok { return assert(false, "LE fixture must parse"); }
  let p = pr.value;
  let cut = prefix(fx, 61);
  let r0 = pcap_packet(&cut, &p, 0);
  var ok = r0.is_ok;
  if r0.is_ok {
    if !bytes_equal(r0.value, bytes4(1, 2, 3, 4)) { ok = false; }
  }
  if !err_bytes_is(pcap_packet(&cut, &p, 1), "pcap: truncated packet") { ok = false; }
  return assert(ok, "pcap_packet reports a shortened source buffer");
}

fn t15() -> TestResult {
  var fx = header_le(65535, 1);
  push_rec_le(&mut fx, 4294967295, 4294967294, 1, 2147483648);
  push_byte(&mut fx, 255);
  let pr = pcap_parse(&fx);
  if !pr.is_ok { return assert(false, "high-bit fixture must parse"); }
  let p = pr.value;
  var ok = pcap_ts_sec(&p, 0) == 4294967295;
  if pcap_caplen(&p, 0) != 1 { ok = false; }
  if pcap_origlen(&p, 0) != 2147483648 { ok = false; }
  let r = pcap_packet(&fx, &p, 0);
  if !r.is_ok { ok = false; } elif !bytes_equal(r.value, bytes1(255)) { ok = false; }
  return assert(ok, "unsigned 32-bit fields keep their high bits");
}

fn t16() -> TestResult {
  var ten = Vec[UInt8].new();
  var i = 0;
  while i < 10 {
    push_byte(&mut ten, 213);
    i = i + 1;
  }
  var ok = err_file_is(pcap_parse(&ten), "pcap: truncated header");
  var zeros10 = Vec[UInt8].new();
  i = 0;
  while i < 10 {
    push_byte(&mut zeros10, 0);
    i = i + 1;
  }
  if !err_file_is(pcap_parse(&zeros10), "pcap: truncated header") { ok = false; }
  return assert(ok, "truncated-header check precedes the magic check");
}

fn t17() -> TestResult {
  let hdr = header_le(96, 101);
  var ok = hdr.len() == 24;
  if !pcap_is_file(&hdr) { ok = false; }
  let pr = pcap_parse(&hdr);
  if !pr.is_ok { return assert(false, "header must parse"); }
  let p = pr.value;
  if p.snaplen != 96 { ok = false; }
  if p.linktype != 101 { ok = false; }
  if pcap_linktype(&p) != 101 { ok = false; }
  if pcap_packet_count(&p) != 0 { ok = false; }
  return assert(ok, "snaplen and linktype are read, not hardcoded");
}

fn main() -> Int {
  io.println("=== xiom.pcap conformance tests ===");
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
    io.println("xiom.pcap: all tests passed");
  } else {
    io.println("xiom.pcap: tests failed");
  }
  return failed;
}
