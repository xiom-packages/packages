// XIOM -- xiom.pcapng conformance tests (19 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The canonical fixture is a 368-byte two-section capture assembled byte by
// byte (byte pushes), so the parser is exercised against bytes this test
// file controls. Section 0 is little-endian and holds an SHB with a
// shb_userappl option, an IDB with an if_name option, an EPB with an
// epb_flags option, an SPB, an NRB with one IPv4 and one IPv6 record, and an
// unknown-type block. Section 1 is big-endian and holds an SHB (explicit
// section length 108), an IDB, an EPB and an ISB with ifrecv/ifdrop 64-bit
// counters. Block types, offsets, lengths, section/interface/packet fields,
// option spans, NRB record spans, name spans, the error catalog and the
// is_file sniff are pinned. Str equality goes through str_compare (BUG 17
// discipline: `==` on a Str read from a Vec lowers to a pointer comparison).

module pcapng_tests
use xiom.io; use xiom.test;
use xiom.pcapng;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Helpers (independent of src/pcapng.xi)
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_file_is(r: Result[PcapngFile, Str], want: Str) -> Bool {
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

fn bytes1(a: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
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

fn bytes8(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  v.push(d as UInt8);
  v.push(e as UInt8);
  v.push(f as UInt8);
  v.push(g as UInt8);
  v.push(h as UInt8);
  return v;
}

fn iv1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn iv2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn iv3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn iv5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

fn iv10(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int, i: Int, j: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  v.push(i);
  v.push(j);
  return v;
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

fn push_bytes(v: &mut Vec[UInt8], b: &Vec[UInt8]) {
  var i = 0;
  while i < b.len() {
    v.push(b[i]);
    i = i + 1;
  }
}

// Zero bytes so that `len` bytes reach the next 4-byte boundary.
fn push_pad4(v: &mut Vec[UInt8], len: Int) {
  var r = len % 4;
  if r != 0 {
    var k = 4 - r;
    while k > 0 {
      push_byte(v, 0);
      k = k - 1;
    }
  }
}

// Prefix of a byte vector, used to build short source buffers.
fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Copy of `v` with the little-endian u32 at `at` replaced by `n`.
fn patched_le32(v: Vec[UInt8], at: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == at { out.push(n % 256); }
    elif i == at + 1 { out.push((n / 256) % 256); }
    elif i == at + 2 { out.push((n / 65536) % 256); }
    elif i == at + 3 { out.push((n / 16777216) % 256); }
    else { out.push(v[i]); }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Fixture builders
// --------------------------------------------------

// One TLV option: u16 code, u16 value length, value, zero padding to 4.
fn opt_le(code: Int, value: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_le16(&mut v, code);
  push_le16(&mut v, value.len());
  push_bytes(&mut v, value);
  push_pad4(&mut v, value.len());
  return v;
}

fn opt_be(code: Int, value: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_be16(&mut v, code);
  push_be16(&mut v, value.len());
  push_bytes(&mut v, value);
  push_pad4(&mut v, value.len());
  return v;
}

// One block: type, total length, body, trailing total length.
fn block_le(v: &mut Vec[UInt8], btype: Int, body: &Vec[UInt8]) {
  let total = body.len() + 12;
  push_le32(v, btype);
  push_le32(v, total);
  push_bytes(v, body);
  push_le32(v, total);
}

fn block_be(v: &mut Vec[UInt8], btype: Int, body: &Vec[UInt8]) {
  let total = body.len() + 12;
  push_be32(v, btype);
  push_be32(v, total);
  push_bytes(v, body);
  push_be32(v, total);
}

fn shb_body_le(minor: Int, sec_lo: Int, sec_hi: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 77);
  push_byte(&mut v, 60);
  push_byte(&mut v, 43);
  push_byte(&mut v, 26);
  push_le16(&mut v, 1);
  push_le16(&mut v, minor);
  push_le32(&mut v, sec_lo);
  push_le32(&mut v, sec_hi);
  return v;
}

fn shb_body_be(minor: Int, sec_lo: Int, sec_hi: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 26);
  push_byte(&mut v, 43);
  push_byte(&mut v, 60);
  push_byte(&mut v, 77);
  push_be16(&mut v, 1);
  push_be16(&mut v, minor);
  push_be32(&mut v, sec_hi);
  push_be32(&mut v, sec_lo);
  return v;
}

fn idb_body_le(linktype: Int, snaplen: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_le16(&mut v, linktype);
  push_le16(&mut v, 0);
  push_le32(&mut v, snaplen);
  return v;
}

fn idb_body_be(linktype: Int, snaplen: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_be16(&mut v, linktype);
  push_be16(&mut v, 0);
  push_be32(&mut v, snaplen);
  return v;
}

// EPB body: interface, timestamp high/low, caplen, origlen, padded data.
// Options (if any) are appended by the caller.
fn epb_body_le(iface: Int, ts_hi: Int, ts_lo: Int, caplen: Int, origlen: Int, data: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_le32(&mut v, iface);
  push_le32(&mut v, ts_hi);
  push_le32(&mut v, ts_lo);
  push_le32(&mut v, caplen);
  push_le32(&mut v, origlen);
  push_bytes(&mut v, data);
  push_pad4(&mut v, data.len());
  return v;
}

fn epb_body_be(iface: Int, ts_hi: Int, ts_lo: Int, caplen: Int, origlen: Int, data: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_be32(&mut v, iface);
  push_be32(&mut v, ts_hi);
  push_be32(&mut v, ts_lo);
  push_be32(&mut v, caplen);
  push_be32(&mut v, origlen);
  push_bytes(&mut v, data);
  push_pad4(&mut v, data.len());
  return v;
}

// SPB body: original length, padded data.
fn spb_body_le(origlen: Int, data: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_le32(&mut v, origlen);
  push_bytes(&mut v, data);
  push_pad4(&mut v, data.len());
  return v;
}

// One NRB record: u16 type, u16 value length, address + NUL-terminated name,
// zero padding to 4.
fn nrb_rec_le(rtype: Int, addr: &Vec[UInt8], name: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  let vlen = addr.len() + name.len() + 1;
  push_le16(&mut v, rtype);
  push_le16(&mut v, vlen);
  push_bytes(&mut v, addr);
  push_bytes(&mut v, name);
  push_byte(&mut v, 0);
  push_pad4(&mut v, vlen);
  return v;
}

// ISB body: interface, timestamp high/low, ifrecv option 6, ifdrop option 7,
// end-of-options.
fn isb_body_be(iface: Int, ts_hi: Int, ts_lo: Int, ifrecv: Int, ifdrop: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_be32(&mut v, iface);
  push_be32(&mut v, ts_hi);
  push_be32(&mut v, ts_lo);
  var rv = Vec[UInt8].new();
  push_be32(&mut rv, 0);
  push_be32(&mut rv, ifrecv);
  let o6 = opt_be(6, &rv);
  push_bytes(&mut v, &o6);
  var dv = Vec[UInt8].new();
  push_be32(&mut dv, 0);
  push_be32(&mut dv, ifdrop);
  let o7 = opt_be(7, &dv);
  push_bytes(&mut v, &o7);
  var ev = Vec[UInt8].new();
  let o0 = opt_be(0, &ev);
  push_bytes(&mut v, &o0);
  return v;
}

fn ipv6_2001_db8_1() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 32);
  push_byte(&mut v, 1);
  push_byte(&mut v, 13);
  push_byte(&mut v, 184);
  var i = 0;
  while i < 10 {
    push_byte(&mut v, 0);
    i = i + 1;
  }
  push_byte(&mut v, 0);
  push_byte(&mut v, 1);
  return v;
}

// The canonical 368-byte two-section capture.
fn fixture() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  // Section 0 (little-endian): SHB with shb_userappl "xiom-test".
  var shb1 = shb_body_le(0, 4294967295, 4294967295);
  let app = bytes_of("xiom-test");
  let o1 = opt_le(4, &app);
  push_bytes(&mut shb1, &o1);
  block_le(&mut v, 168627466, &shb1);
  // IDB linktype 1, snaplen 65535, if_name "eth0".
  var idb1 = idb_body_le(1, 65535);
  let eth = bytes_of("eth0");
  let o2 = opt_le(2, &eth);
  push_bytes(&mut idb1, &o2);
  block_le(&mut v, 1, &idb1);
  // EPB interface 0, ts 0/1600000, caplen 4, origlen 6, data 01 02 03 04,
  // epb_flags option value 3.
  let d1 = bytes4(1, 2, 3, 4);
  var epb1 = epb_body_le(0, 0, 1600000, 4, 6, &d1);
  let flags = bytes4(3, 0, 0, 0);
  let o3 = opt_le(2, &flags);
  push_bytes(&mut epb1, &o3);
  block_le(&mut v, 6, &epb1);
  // SPB origlen 3, data de ad be.
  let d2 = bytes3(222, 173, 190);
  let spb = spb_body_le(3, &d2);
  block_le(&mut v, 3, &spb);
  // NRB: IPv4 192.0.2.1 + "host1.example", IPv6 2001:db8::1 +
  // "host2.example", end-of-records.
  var nrb = Vec[UInt8].new();
  let a4 = bytes4(192, 0, 2, 1);
  let n1 = bytes_of("host1.example");
  let r1 = nrb_rec_le(1, &a4, &n1);
  push_bytes(&mut nrb, &r1);
  let a16 = ipv6_2001_db8_1();
  let n2 = bytes_of("host2.example");
  let r2 = nrb_rec_le(2, &a16, &n2);
  push_bytes(&mut nrb, &r2);
  push_le16(&mut nrb, 0);
  push_le16(&mut nrb, 0);
  block_le(&mut v, 4, &nrb);
  // Unknown block type 65535, body aa bb cc dd 00 00 00 00.
  let unk = bytes8(170, 187, 204, 221, 0, 0, 0, 0);
  block_le(&mut v, 65535, &unk);
  // Section 1 (big-endian): SHB with explicit section length 108.
  let shb2 = shb_body_be(0, 108, 0);
  block_be(&mut v, 168627466, &shb2);
  // IDB linktype 101, snaplen 262144.
  let idb2 = idb_body_be(101, 262144);
  block_be(&mut v, 1, &idb2);
  // EPB interface 0, ts high 1 low 2, caplen 3, origlen 3, data aa bb cc.
  let d3 = bytes3(170, 187, 204);
  let epb2 = epb_body_be(0, 1, 2, 3, 3, &d3);
  block_be(&mut v, 6, &epb2);
  // ISB interface 0, ts 0/5, ifrecv 100, ifdrop 2.
  let isb = isb_body_be(0, 0, 5, 100, 2);
  block_be(&mut v, 5, &isb);
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let fx = fixture();
  var ok = fx.len() == 368;
  if !pcapng_is_file(&fx) { ok = false; }
  let pr = pcapng_parse(&fx);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let p = pr.value;
  if pcapng_block_count(&p) != 10 { ok = false; }
  let got_types: Vec[Int] = p.types;
  if !ints_equal(got_types, iv10(168627466, 1, 6, 3, 4, 65535, 168627466, 1, 6, 5)) { ok = false; }
  let got_offs: Vec[Int] = p.offsets;
  if !ints_equal(got_offs, iv10(0, 44, 72, 116, 136, 212, 232, 260, 280, 316)) { ok = false; }
  let got_tot: Vec[Int] = p.total_lengths;
  if !ints_equal(got_tot, iv10(44, 28, 44, 20, 76, 20, 28, 20, 36, 52)) { ok = false; }
  let got_blen: Vec[Int] = p.body_lengths;
  if !ints_equal(got_blen, iv10(32, 16, 32, 8, 64, 8, 16, 8, 24, 40)) { ok = false; }
  let got_sec: Vec[Int] = p.sections;
  if !ints_equal(got_sec, iv10(0, 0, 0, 0, 0, 0, 1, 1, 1, 1)) { ok = false; }
  if pcapng_block_type(&p, 5) != 65535 { ok = false; }
  if pcapng_block_type(&p, -1) != -1 { ok = false; }
  if pcapng_block_type(&p, 10) != -1 { ok = false; }
  return assert(ok, "fixture: blocks, types, offsets, lengths and sections pinned");
}

fn t2() -> TestResult {
  let fx = fixture();
  let pr = pcapng_parse(&fx);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let p = pr.value;
  var ok = pcapng_section_count(&p) == 2;
  if pcapng_section_length(&p, 0) != -1 { ok = false; }
  if pcapng_section_length(&p, 1) != 108 { ok = false; }
  if pcapng_section_order(&p, 0) != 1 { ok = false; }
  if pcapng_section_order(&p, 1) != 0 { ok = false; }
  if pcapng_section_major(&p, 0) != 1 { ok = false; }
  if pcapng_section_major(&p, 1) != 1 { ok = false; }
  if pcapng_section_minor(&p, 0) != 0 { ok = false; }
  if pcapng_section_minor(&p, 1) != 0 { ok = false; }
  if pcapng_section_length(&p, -1) != -1 { ok = false; }
  if pcapng_section_length(&p, 2) != -1 { ok = false; }
  if pcapng_section_order(&p, 2) != -1 { ok = false; }
  if pcapng_section_major(&p, 2) != -1 { ok = false; }
  if pcapng_section_minor(&p, 2) != -1 { ok = false; }
  return assert(ok, "both sections: order, explicit/unspecified length, version 1.0");
}

fn t3() -> TestResult {
  let fx = fixture();
  let pr = pcapng_parse(&fx);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let p = pr.value;
  var ok = pcapng_interface_count(&p) == 2;
  if pcapng_interface_linktype(&p, 0) != 1 { ok = false; }
  if pcapng_interface_linktype(&p, 1) != 101 { ok = false; }
  if pcapng_interface_snaplen(&p, 0) != 65535 { ok = false; }
  if pcapng_interface_snaplen(&p, 1) != 262144 { ok = false; }
  if pcapng_interface_block(&p, 0) != 1 { ok = false; }
  if pcapng_interface_block(&p, 1) != 7 { ok = false; }
  if pcapng_interface_section(&p, 0) != 0 { ok = false; }
  if pcapng_interface_section(&p, 1) != 1 { ok = false; }
  if pcapng_interface_linktype(&p, -1) != -1 { ok = false; }
  if pcapng_interface_linktype(&p, 2) != -1 { ok = false; }
  if pcapng_interface_snaplen(&p, 2) != -1 { ok = false; }
  if pcapng_interface_block(&p, 2) != -1 { ok = false; }
  if pcapng_interface_section(&p, 2) != -1 { ok = false; }
  return assert(ok, "interfaces: linktype/snaplen/section/block pinned per section");
}

fn t4() -> TestResult {
  let fx = fixture();
  let pr = pcapng_parse(&fx);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let p = pr.value;
  var ok = pcapng_packet_count(&p) == 3;
  let kinds: Vec[Int] = p.pkt_kinds;
  if !ints_equal(kinds, iv3(0, 1, 0)) { ok = false; }
  let ifaces: Vec[Int] = p.pkt_interfaces;
  if !ints_equal(ifaces, iv3(0, -1, 1)) { ok = false; }
  let blocks: Vec[Int] = p.pkt_blocks;
  if !ints_equal(blocks, iv3(2, 3, 8)) { ok = false; }
  let secs: Vec[Int] = p.pkt_sections;
  if !ints_equal(secs, iv3(0, 0, 1)) { ok = false; }
  if pcapng_packet_kind(&p, -1) != -1 { ok = false; }
  if pcapng_packet_kind(&p, 3) != -1 { ok = false; }
  if pcapng_packet_interface(&p, 3) != -1 { ok = false; }
  if pcapng_packet_block(&p, 3) != -1 { ok = false; }
  if pcapng_packet_section(&p, 3) != -1 { ok = false; }
  return assert(ok, "packets: EPB/SPB kinds, global interfaces, sections, blocks");
}

fn t5() -> TestResult {
  let fx = fixture();
  let pr = pcapng_parse(&fx);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let p = pr.value;
  var ok = true;
  let his: Vec[Int] = p.pkt_ts_highs;
  if !ints_equal(his, iv3(0, 0, 1)) { ok = false; }
  let los: Vec[Int] = p.pkt_ts_lows;
  if !ints_equal(los, iv3(1600000, 0, 2)) { ok = false; }
  if pcapng_packet_timestamp(&p, 0) != 1600000 { ok = false; }
  if pcapng_packet_timestamp(&p, 1) != 0 { ok = false; }
  if pcapng_packet_timestamp(&p, 2) != 4294967298 { ok = false; }
  if pcapng_packet_timestamp(&p, 3) != -1 { ok = false; }
  let cls: Vec[Int] = p.pkt_caplens;
  if !ints_equal(cls, iv3(4, 3, 3)) { ok = false; }
  let ols: Vec[Int] = p.pkt_origlens;
  if !ints_equal(ols, iv3(6, 3, 3)) { ok = false; }
  let offs: Vec[Int] = p.pkt_data_offsets;
  if !ints_equal(offs, iv3(100, 128, 308)) { ok = false; }
  if pcapng_packet_ts_high(&p, 3) != -1 { ok = false; }
  if pcapng_packet_ts_low(&p, 3) != -1 { ok = false; }
  if pcapng_packet_caplen(&p, 3) != -1 { ok = false; }
  if pcapng_packet_origlen(&p, 3) != -1 { ok = false; }
  if pcapng_packet_data_offset(&p, 3) != -1 { ok = false; }
  return assert(ok, "packet timestamps, caplen/origlen and data spans pinned");
}

fn t6() -> TestResult {
  let fx = fixture();
  let pr = pcapng_parse(&fx);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let p = pr.value;
  var ok = true;
  let r0 = pcapng_packet_data(&fx, &p, 0);
  if !r0.is_ok { ok = false; } else {
    let v0: Vec[UInt8] = r0.value;
    if !bytes_equal(v0, bytes4(1, 2, 3, 4)) { ok = false; }
  }
  let r1 = pcapng_packet_data(&fx, &p, 1);
  if !r1.is_ok { ok = false; } else {
    let v1: Vec[UInt8] = r1.value;
    if !bytes_equal(v1, bytes3(222, 173, 190)) { ok = false; }
  }
  let r2 = pcapng_packet_data(&fx, &p, 2);
  if !r2.is_ok { ok = false; } else {
    let v2: Vec[UInt8] = r2.value;
    if !bytes_equal(v2, bytes3(170, 187, 204)) { ok = false; }
  }
  if !err_bytes_is(pcapng_packet_data(&fx, &p, 3), "pcapng: packet out of range") { ok = false; }
  if !err_bytes_is(pcapng_packet_data(&fx, &p, -1), "pcapng: packet out of range") { ok = false; }
  let cut = prefix(fx, 200);
  let c1 = pcapng_packet_data(&cut, &p, 1);
  if !c1.is_ok { ok = false; } else {
    let cv: Vec[UInt8] = c1.value;
    if !bytes_equal(cv, bytes3(222, 173, 190)) { ok = false; }
  }
  if !err_bytes_is(pcapng_packet_data(&cut, &p, 2), "pcapng: span out of bounds") { ok = false; }
  return assert(ok, "packet data copies exactly; short buffers are span errors");
}

fn t7() -> TestResult {
  let fx = fixture();
  let pr = pcapng_parse(&fx);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let p = pr.value;
  var ok = pcapng_option_count(&p) == 5;
  let obl: Vec[Int] = p.opt_blocks;
  if !ints_equal(obl, iv5(0, 1, 2, 9, 9)) { ok = false; }
  let ocd: Vec[Int] = p.opt_codes;
  if !ints_equal(ocd, iv5(4, 2, 2, 6, 7)) { ok = false; }
  let oof: Vec[Int] = p.opt_offsets;
  if !ints_equal(oof, iv5(28, 64, 108, 340, 352)) { ok = false; }
  let oln: Vec[Int] = p.opt_lengths;
  if !ints_equal(oln, iv5(9, 4, 4, 8, 8)) { ok = false; }
  if pcapng_option_block(&p, 0) != 0 { ok = false; }
  if pcapng_option_code(&p, 1) != 2 { ok = false; }
  if pcapng_option_offset(&p, 2) != 108 { ok = false; }
  if pcapng_option_length(&p, 3) != 8 { ok = false; }
  if pcapng_option_find(&p, 0, 4) != 0 { ok = false; }
  if pcapng_option_find(&p, 2, 2) != 2 { ok = false; }
  if pcapng_option_find(&p, 9, 6) != 3 { ok = false; }
  if pcapng_option_find(&p, 9, 7) != 4 { ok = false; }
  if pcapng_option_find(&p, 9, 99) != -1 { ok = false; }
  if pcapng_option_find(&p, 99, 6) != -1 { ok = false; }
  if pcapng_option_find(&p, -1, 6) != -1 { ok = false; }
  let v0 = pcapng_option_value(&fx, &p, 0);
  if !v0.is_ok { ok = false; } else {
    let x0: Vec[UInt8] = v0.value;
    if !bytes_equal(x0, bytes_of("xiom-test")) { ok = false; }
  }
  let v2 = pcapng_option_value(&fx, &p, 2);
  if !v2.is_ok { ok = false; } else {
    let x2: Vec[UInt8] = v2.value;
    if !bytes_equal(x2, bytes4(3, 0, 0, 0)) { ok = false; }
  }
  let v3 = pcapng_option_value(&fx, &p, 3);
  if !v3.is_ok { ok = false; } else {
    let x3: Vec[UInt8] = v3.value;
    if !bytes_equal(x3, bytes8(0, 0, 0, 0, 0, 0, 0, 100)) { ok = false; }
  }
  if !err_bytes_is(pcapng_option_value(&fx, &p, 5), "pcapng: option out of range") { ok = false; }
  if !err_bytes_is(pcapng_option_value(&fx, &p, -1), "pcapng: option out of range") { ok = false; }
  return assert(ok, "options: spans, first-match lookup and value copies");
}

fn t8() -> TestResult {
  let fx = fixture();
  let pr = pcapng_parse(&fx);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let p = pr.value;
  var ok = pcapng_record_count(&p) == 2;
  let rt: Vec[Int] = p.rec_types;
  if !ints_equal(rt, iv2(1, 2)) { ok = false; }
  let rb: Vec[Int] = p.rec_blocks;
  if !ints_equal(rb, iv2(4, 4)) { ok = false; }
  if pcapng_record_type(&p, 0) != 1 { ok = false; }
  if pcapng_record_type(&p, 1) != 2 { ok = false; }
  if pcapng_record_block(&p, 1) != 4 { ok = false; }
  let nc: Vec[Int] = p.rec_name_counts;
  if !ints_equal(nc, iv2(1, 1)) { ok = false; }
  if pcapng_record_name_count(&p, 0) != 1 { ok = false; }
  if pcapng_record_name_count(&p, 1) != 1 { ok = false; }
  if pcapng_record_name_count(&p, 2) != -1 { ok = false; }
  let r0 = pcapng_record_address(&fx, &p, 0);
  if !r0.is_ok { ok = false; } else {
    let a0: Vec[UInt8] = r0.value;
    if !bytes_equal(a0, bytes4(192, 0, 2, 1)) { ok = false; }
  }
  let r1 = pcapng_record_address(&fx, &p, 1);
  if !r1.is_ok { ok = false; } else {
    let a1: Vec[UInt8] = r1.value;
    if !bytes_equal(a1, ipv6_2001_db8_1()) { ok = false; }
  }
  if !err_bytes_is(pcapng_record_address(&fx, &p, 2), "pcapng: record out of range") { ok = false; }
  if pcapng_name_count(&p) != 2 { ok = false; }
  let nr: Vec[Int] = p.name_records;
  if !ints_equal(nr, iv2(0, 1)) { ok = false; }
  let no: Vec[Int] = p.name_offsets;
  if !ints_equal(no, iv2(152, 188)) { ok = false; }
  let nl: Vec[Int] = p.name_lengths;
  if !ints_equal(nl, iv2(13, 13)) { ok = false; }
  if pcapng_name_record(&p, 1) != 1 { ok = false; }
  if pcapng_name_offset(&p, 0) != 152 { ok = false; }
  if pcapng_name_length(&p, 0) != 13 { ok = false; }
  let n0 = pcapng_name_bytes(&fx, &p, 0);
  if !n0.is_ok { ok = false; } else {
    let x0: Vec[UInt8] = n0.value;
    if !bytes_equal(x0, bytes_of("host1.example")) { ok = false; }
  }
  let n1 = pcapng_name_bytes(&fx, &p, 1);
  if !n1.is_ok { ok = false; } else {
    let x1: Vec[UInt8] = n1.value;
    if !bytes_equal(x1, bytes_of("host2.example")) { ok = false; }
  }
  if !err_bytes_is(pcapng_name_bytes(&fx, &p, 2), "pcapng: name out of range") { ok = false; }
  if pcapng_name_record(&p, 2) != -1 { ok = false; }
  if pcapng_name_offset(&p, 2) != -1 { ok = false; }
  if pcapng_name_length(&p, 2) != -1 { ok = false; }
  return assert(ok, "NRB: record types, addresses and padded DNS name spans");
}

fn t9() -> TestResult {
  let fx = fixture();
  let pr = pcapng_parse(&fx);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let p = pr.value;
  var ok = pcapng_isb_count(&p) == 1;
  let ii: Vec[Int] = p.isb_interfaces;
  if !ints_equal(ii, iv1(1)) { ok = false; }
  if pcapng_isb_interface(&p, 0) != 1 { ok = false; }
  if pcapng_isb_block(&p, 0) != 9 { ok = false; }
  if pcapng_isb_ifrecv(&p, 0) != 100 { ok = false; }
  if pcapng_isb_ifdrop(&p, 0) != 2 { ok = false; }
  if pcapng_isb_interface(&p, 1) != -1 { ok = false; }
  if pcapng_isb_block(&p, 1) != -1 { ok = false; }
  if pcapng_isb_ifrecv(&p, 1) != -1 { ok = false; }
  if pcapng_isb_ifdrop(&p, 1) != -1 { ok = false; }
  return assert(ok, "ISB: interface link, 64-bit ifrecv/ifdrop counters");
}

fn t10() -> TestResult {
  let fx = fixture();
  let pr = pcapng_parse(&fx);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let p = pr.value;
  var ok = pcapng_block_type(&p, 5) == 65535;
  if pcapng_block_offset(&p, 5) != 212 { ok = false; }
  if pcapng_block_body_offset(&p, 5) != 220 { ok = false; }
  if pcapng_block_body_length(&p, 5) != 8 { ok = false; }
  if pcapng_block_section(&p, 5) != 0 { ok = false; }
  let r = pcapng_block_body(&fx, &p, 5);
  if !r.is_ok { ok = false; } else {
    let b: Vec[UInt8] = r.value;
    if !bytes_equal(b, bytes8(170, 187, 204, 221, 0, 0, 0, 0)) { ok = false; }
  }
  if !err_bytes_is(pcapng_block_body(&fx, &p, 10), "pcapng: block out of range") { ok = false; }
  if pcapng_block_offset(&p, 10) != -1 { ok = false; }
  if pcapng_block_body_offset(&p, 10) != -1 { ok = false; }
  if pcapng_block_body_length(&p, 10) != -1 { ok = false; }
  if pcapng_block_section(&p, 10) != -1 { ok = false; }
  return assert(ok, "unknown block type keeps its raw body span");
}

fn t11() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_file_is(pcapng_parse(&empty), "pcapng: section header block must be first");
  if pcapng_is_file(&empty) { ok = false; }
  var idb_first = Vec[UInt8].new();
  let idb = idb_body_le(1, 65535);
  block_le(&mut idb_first, 1, &idb);
  if !err_file_is(pcapng_parse(&idb_first), "pcapng: section header block must be first") { ok = false; }
  var twelve = Vec[UInt8].new();
  push_le32(&mut twelve, 1);
  push_le32(&mut twelve, 12);
  push_le32(&mut twelve, 12);
  if !err_file_is(pcapng_parse(&twelve), "pcapng: section header block must be first") { ok = false; }
  let fx = fixture();
  var tail = fx;
  var i = 0;
  while i < 8 {
    push_byte(&mut tail, 0);
    i = i + 1;
  }
  if !err_file_is(pcapng_parse(&tail), "pcapng: truncated block header") { ok = false; }
  return assert(ok, "first block must be an SHB; short tails are truncated");
}

fn t12() -> TestResult {
  let fx = fixture();
  var ok = pcapng_parse(&fx).is_ok;
  let short = patched_le32(fx, 4, 10);
  if !err_file_is(pcapng_parse(&short), "pcapng: bad block length") { ok = false; }
  let unaligned = patched_le32(fx, 4, 13);
  if !err_file_is(pcapng_parse(&unaligned), "pcapng: bad block length") { ok = false; }
  let past = patched_le32(fx, 4, 400);
  if !err_file_is(pcapng_parse(&past), "pcapng: truncated block") { ok = false; }
  return assert(ok, "block length >= 12, multiple of 4 and inside the buffer");
}

fn t13() -> TestResult {
  let fx = fixture();
  var ok = pcapng_parse(&fx).is_ok;
  let bad = patched_le32(fx, 40, 43);
  if !err_file_is(pcapng_parse(&bad), "pcapng: total length mismatch") { ok = false; }
  let bad2 = patched_le32(fx, 112, 40);
  if !err_file_is(pcapng_parse(&bad2), "pcapng: total length mismatch") { ok = false; }
  return assert(ok, "trailing total length must match the leading copy");
}

fn t14() -> TestResult {
  var v = Vec[UInt8].new();
  let shb = shb_body_le(0, 4294967295, 4294967295);
  block_le(&mut v, 168627466, &shb);
  let idb = idb_body_le(1, 65535);
  block_le(&mut v, 1, &idb);
  let d = bytes4(1, 2, 3, 4);
  var epb = epb_body_le(0, 0, 1, 4, 4, &d);
  push_le16(&mut epb, 2);
  push_le16(&mut epb, 8);
  push_le32(&mut epb, 9);
  block_le(&mut v, 6, &epb);
  var ok = err_file_is(pcapng_parse(&v), "pcapng: option overruns block");
  var v2 = Vec[UInt8].new();
  let shb2 = shb_body_le(0, 4294967295, 4294967295);
  block_le(&mut v2, 168627466, &shb2);
  let idb2 = idb_body_le(1, 65535);
  block_le(&mut v2, 1, &idb2);
  var isb = Vec[UInt8].new();
  push_le32(&mut isb, 0);
  push_le32(&mut isb, 0);
  push_le32(&mut isb, 0);
  push_le16(&mut isb, 6);
  push_le16(&mut isb, 4);
  push_le32(&mut isb, 5);
  block_le(&mut v2, 5, &isb);
  if !err_file_is(pcapng_parse(&v2), "pcapng: bad statistics counter") { ok = false; }
  return assert(ok, "option padding overrun and short statistics counters are Err");
}

fn t15() -> TestResult {
  var v = Vec[UInt8].new();
  let shb = shb_body_le(0, 4294967295, 4294967295);
  block_le(&mut v, 168627466, &shb);
  let d8 = bytes8(1, 2, 3, 4, 5, 6, 7, 8);
  let over = epb_body_le(0, 0, 1, 8, 4, &d8);
  block_le(&mut v, 6, &over);
  var ok = err_file_is(pcapng_parse(&v), "pcapng: captured length exceeds original");
  var v2 = Vec[UInt8].new();
  let shb2 = shb_body_le(0, 4294967295, 4294967295);
  block_le(&mut v2, 168627466, &shb2);
  let d4 = bytes4(1, 2, 3, 4);
  let short = epb_body_le(0, 0, 1, 8, 8, &d4);
  block_le(&mut v2, 6, &short);
  if !err_file_is(pcapng_parse(&v2), "pcapng: truncated packet data") { ok = false; }
  var v3 = Vec[UInt8].new();
  let shb3 = shb_body_le(0, 4294967295, 4294967295);
  block_le(&mut v3, 168627466, &shb3);
  let d1 = bytes1(1);
  let noif = epb_body_le(1, 0, 1, 1, 1, &d1);
  block_le(&mut v3, 6, &noif);
  if !err_file_is(pcapng_parse(&v3), "pcapng: packet interface out of range") { ok = false; }
  return assert(ok, "EPB caplen/origlen, data bounds and interface bounds validated");
}

fn t16() -> TestResult {
  var v = Vec[UInt8].new();
  push_le32(&mut v, 168627466);
  push_le32(&mut v, 20);
  push_le32(&mut v, 67305985);
  push_le32(&mut v, 0);
  push_le32(&mut v, 20);
  var ok = err_file_is(pcapng_parse(&v), "pcapng: bad byte-order magic");
  var v2 = Vec[UInt8].new();
  var shbv = Vec[UInt8].new();
  push_byte(&mut shbv, 77);
  push_byte(&mut shbv, 60);
  push_byte(&mut shbv, 43);
  push_byte(&mut shbv, 26);
  push_le16(&mut shbv, 2);
  push_le16(&mut shbv, 0);
  push_le32(&mut shbv, 0);
  push_le32(&mut shbv, 0);
  block_le(&mut v2, 168627466, &shbv);
  if !err_file_is(pcapng_parse(&v2), "pcapng: unsupported version") { ok = false; }
  var v3 = Vec[UInt8].new();
  var shbt = Vec[UInt8].new();
  push_byte(&mut shbt, 77);
  push_byte(&mut shbt, 60);
  push_byte(&mut shbt, 43);
  push_byte(&mut shbt, 26);
  push_le16(&mut shbt, 1);
  push_le16(&mut shbt, 0);
  block_le(&mut v3, 168627466, &shbt);
  if !err_file_is(pcapng_parse(&v3), "pcapng: truncated section header") { ok = false; }
  return assert(ok, "SHB: byte-order magic, version 1 and 16-byte body validated");
}

fn t17() -> TestResult {
  var v = Vec[UInt8].new();
  let shb = shb_body_le(0, 4294967295, 4294967295);
  block_le(&mut v, 168627466, &shb);
  let d8 = bytes8(1, 2, 3, 4, 5, 6, 7, 8);
  let bad = spb_body_le(3, &d8);
  block_le(&mut v, 3, &bad);
  var ok = err_file_is(pcapng_parse(&v), "pcapng: bad packet padding");
  var v2 = Vec[UInt8].new();
  let shb2 = shb_body_le(0, 4294967295, 4294967295);
  block_le(&mut v2, 168627466, &shb2);
  let d4 = bytes4(1, 2, 3, 4);
  let trunc = spb_body_le(8, &d4);
  block_le(&mut v2, 3, &trunc);
  if !err_file_is(pcapng_parse(&v2), "pcapng: truncated packet data") { ok = false; }
  var v3 = Vec[UInt8].new();
  let shb3 = shb_body_le(0, 4294967295, 4294967295);
  block_le(&mut v3, 168627466, &shb3);
  var empty_body = Vec[UInt8].new();
  block_le(&mut v3, 3, &empty_body);
  if !err_file_is(pcapng_parse(&v3), "pcapng: truncated simple packet") { ok = false; }
  return assert(ok, "SPB: padding inferred from origlen, bounds validated");
}

fn t18() -> TestResult {
  var v = Vec[UInt8].new();
  let shb = shb_body_le(0, 4294967295, 4294967295);
  block_le(&mut v, 168627466, &shb);
  var rec_bad = Vec[UInt8].new();
  push_le16(&mut rec_bad, 1);
  push_le16(&mut rec_bad, 2);
  push_le16(&mut rec_bad, 1);
  push_le16(&mut rec_bad, 2);
  block_le(&mut v, 4, &rec_bad);
  var ok = err_file_is(pcapng_parse(&v), "pcapng: bad name record");
  var v2 = Vec[UInt8].new();
  let shb2 = shb_body_le(0, 4294967295, 4294967295);
  block_le(&mut v2, 168627466, &shb2);
  var rec_un = Vec[UInt8].new();
  push_le16(&mut rec_un, 1);
  push_le16(&mut rec_un, 7);
  let a4 = bytes4(192, 0, 2, 1);
  push_bytes(&mut rec_un, &a4);
  push_byte(&mut rec_un, 97);
  push_byte(&mut rec_un, 98);
  push_byte(&mut rec_un, 99);
  push_pad4(&mut rec_un, 7);
  block_le(&mut v2, 4, &rec_un);
  if !err_file_is(pcapng_parse(&v2), "pcapng: unterminated name") { ok = false; }
  var v3 = Vec[UInt8].new();
  let shb3 = shb_body_le(0, 4294967295, 4294967295);
  block_le(&mut v3, 168627466, &shb3);
  var rec_tr = Vec[UInt8].new();
  push_le16(&mut rec_tr, 1);
  push_le16(&mut rec_tr, 100);
  push_le32(&mut rec_tr, 0);
  block_le(&mut v3, 4, &rec_tr);
  if !err_file_is(pcapng_parse(&v3), "pcapng: truncated name record") { ok = false; }
  var v4 = Vec[UInt8].new();
  let shb4 = shb_body_le(0, 4294967295, 4294967295);
  block_le(&mut v4, 168627466, &shb4);
  var rec_ok = Vec[UInt8].new();
  push_le16(&mut rec_ok, 9);
  push_le16(&mut rec_ok, 4);
  push_le32(&mut rec_ok, 7);
  push_le16(&mut rec_ok, 0);
  push_le16(&mut rec_ok, 0);
  push_le32(&mut rec_ok, 999);
  block_le(&mut v4, 4, &rec_ok);
  let pr = pcapng_parse(&v4);
  if !pr.is_ok { ok = false; } else {
    let p = pr.value;
    if pcapng_record_count(&p) != 0 { ok = false; }
    if pcapng_name_count(&p) != 0 { ok = false; }
  }
  return assert(ok, "NRB: record bounds, NUL termination, unknown records skipped");
}

fn t19() -> TestResult {
  let fx = fixture();
  var ok = pcapng_is_file(&fx);
  let head = prefix(fx, 12);
  if !pcapng_is_file(&head) { ok = false; }
  var empty = Vec[UInt8].new();
  if pcapng_is_file(&empty) { ok = false; }
  let short = prefix(fx, 11);
  if pcapng_is_file(&short) { ok = false; }
  var bom = Vec[UInt8].new();
  push_byte(&mut bom, 26);
  push_byte(&mut bom, 43);
  push_byte(&mut bom, 60);
  push_byte(&mut bom, 77);
  var j = 0;
  while j < 8 {
    push_byte(&mut bom, 0);
    j = j + 1;
  }
  if pcapng_is_file(&bom) { ok = false; }
  return assert(ok, "is_file: SHB magic and 12-byte minimum only");
}

fn main() -> Int {
  io.println("=== xiom.pcapng conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.pcapng: all tests passed");
  } else {
    io.println("xiom.pcapng: tests failed");
  }
  return failed;
}
