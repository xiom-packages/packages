// XIOM -- xiom.dhcp conformance tests (16 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the pure-XIOM DHCPv4 codec against the RFC 2131/2132 subset that
// SPEC.md promises: a hand-built OFFER fixture with pinned header fields,
// option index offsets/lengths and value slices; flags/quiet variants; the
// five parse errors (short packet, bad cookie, truncated option, bad option
// length, missing end); append_option bytes and atomic errors; exact
// build_client/build_discover/build_request frames checked against frames
// this test file assembles byte by byte; and unsigned boundary values.
//
// Str values are never compared with `==` (BUG 17 discipline: `==` on a Str
// read from a Vec lowers to a pointer comparison); error messages go through
// compare.str_compare. Struct Vec fields are bound to typed locals before
// being referenced (compiler trap 4).

module dhcp_tests
use xiom.io; use xiom.test;
use xiom.dhcp;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Helpers (independent of src/dhcp.xi)
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_packet_is(r: Result[DhcpPacket, Str], want: Str) -> Bool {
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

// Widened byte read, so byte values are never compared to Int constants
// without the `& 0xFF` widening (compiler trap 3).
fn byte_at(v: Vec[UInt8], i: Int) -> Int {
  return (v[i] as Int) & 0xFF;
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

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
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

fn concat2(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
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

fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn push_byte(v: &mut Vec[UInt8], b: Int) {
  v.push(b as UInt8);
}

fn push_zeros(v: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
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

fn ip4(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_be32(&mut v, n);
  return v;
}

fn mac6() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 222);
  push_byte(&mut v, 173);
  push_byte(&mut v, 190);
  push_byte(&mut v, 239);
  push_byte(&mut v, 0);
  push_byte(&mut v, 1);
  return v;
}

fn client_id(mac: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 1);
  var i = 0;
  while i < mac.len() {
    v.push(mac[i]);
    i = i + 1;
  }
  return v;
}

fn param_list() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 1);
  push_byte(&mut v, 3);
  push_byte(&mut v, 6);
  push_byte(&mut v, 12);
  push_byte(&mut v, 51);
  push_byte(&mut v, 54);
  return v;
}

// One TLV option: code, value length, value bytes.
fn opt(code: Int, value: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, code);
  push_byte(&mut v, value.len());
  var i = 0;
  while i < value.len() {
    v.push(value[i]);
    i = i + 1;
  }
  return v;
}

// 240 zero fixed bytes with a valid magic cookie (no options).
fn header_only() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_zeros(&mut v, 236);
  push_byte(&mut v, 99);
  push_byte(&mut v, 130);
  push_byte(&mut v, 83);
  push_byte(&mut v, 99);
  return v;
}

fn with_options(opts: Vec[UInt8]) -> Vec[UInt8] {
  return concat2(header_only(), opts);
}

// 236-byte BOOTP header + cookie for a BOOTREQUEST built independently of
// dhcp_build_client; chaddr is padded to 16 bytes with zeros.
fn client_frame(xid: Int, mac: &Vec[UInt8], flags: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 1);
  push_byte(&mut v, 1);
  push_byte(&mut v, mac.len());
  push_byte(&mut v, 0);
  push_be32(&mut v, xid);
  push_be16(&mut v, 0);
  push_be16(&mut v, flags);
  push_be32(&mut v, 0);
  push_be32(&mut v, 0);
  push_be32(&mut v, 0);
  push_be32(&mut v, 0);
  var i = 0;
  while i < mac.len() {
    v.push(mac[i]);
    i = i + 1;
  }
  push_zeros(&mut v, 16 - mac.len());
  push_zeros(&mut v, 64);
  push_zeros(&mut v, 128);
  push_byte(&mut v, 99);
  push_byte(&mut v, 130);
  push_byte(&mut v, 83);
  push_byte(&mut v, 99);
  return v;
}

// 299-byte hand-built DHCPOFFER: broadcast flag, yiaddr 192.168.1.100,
// siaddr 192.168.1.1, giaddr 10.0.0.1, sname "dhcpd", file "pxelinux.0",
// options (after a pad byte): 53=OFFER, 54, 51, 1, 3, 6 (two DNS), 12, 61,
// then 255 and four trailing bytes that must be ignored. Value offsets:
// 243, 246, 252, 258, 264, 270, 280, 291; lengths 1, 4, 4, 4, 4, 8, 9, 3.
fn offer_fixture() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 2);
  push_byte(&mut v, 1);
  push_byte(&mut v, 6);
  push_byte(&mut v, 0);
  push_be32(&mut v, 305419896);
  push_be16(&mut v, 5);
  push_be16(&mut v, 32768);
  push_be32(&mut v, 0);
  push_be32(&mut v, 3232235876);
  push_be32(&mut v, 3232235777);
  push_be32(&mut v, 167772161);
  push_byte(&mut v, 222);
  push_byte(&mut v, 173);
  push_byte(&mut v, 190);
  push_byte(&mut v, 239);
  push_byte(&mut v, 0);
  push_byte(&mut v, 1);
  push_zeros(&mut v, 10);
  push_byte(&mut v, 100);
  push_byte(&mut v, 104);
  push_byte(&mut v, 99);
  push_byte(&mut v, 112);
  push_byte(&mut v, 100);
  push_zeros(&mut v, 59);
  push_byte(&mut v, 112);
  push_byte(&mut v, 120);
  push_byte(&mut v, 101);
  push_byte(&mut v, 108);
  push_byte(&mut v, 105);
  push_byte(&mut v, 110);
  push_byte(&mut v, 117);
  push_byte(&mut v, 120);
  push_byte(&mut v, 46);
  push_byte(&mut v, 48);
  push_zeros(&mut v, 118);
  push_byte(&mut v, 99);
  push_byte(&mut v, 130);
  push_byte(&mut v, 83);
  push_byte(&mut v, 99);
  push_byte(&mut v, 0);
  push_byte(&mut v, 53);
  push_byte(&mut v, 1);
  push_byte(&mut v, 2);
  push_byte(&mut v, 54);
  push_byte(&mut v, 4);
  push_be32(&mut v, 3232235777);
  push_byte(&mut v, 51);
  push_byte(&mut v, 4);
  push_be32(&mut v, 86400);
  push_byte(&mut v, 1);
  push_byte(&mut v, 4);
  push_be32(&mut v, 4294967040);
  push_byte(&mut v, 3);
  push_byte(&mut v, 4);
  push_be32(&mut v, 3232235777);
  push_byte(&mut v, 6);
  push_byte(&mut v, 8);
  push_be32(&mut v, 134744072);
  push_be32(&mut v, 134743044);
  push_byte(&mut v, 12);
  push_byte(&mut v, 9);
  push_byte(&mut v, 120);
  push_byte(&mut v, 105);
  push_byte(&mut v, 111);
  push_byte(&mut v, 109);
  push_byte(&mut v, 45);
  push_byte(&mut v, 104);
  push_byte(&mut v, 111);
  push_byte(&mut v, 115);
  push_byte(&mut v, 116);
  push_byte(&mut v, 61);
  push_byte(&mut v, 3);
  push_byte(&mut v, 1);
  push_byte(&mut v, 222);
  push_byte(&mut v, 173);
  push_byte(&mut v, 255);
  push_byte(&mut v, 222);
  push_byte(&mut v, 173);
  push_byte(&mut v, 190);
  push_byte(&mut v, 239);
  return v;
}

// 244-byte BOOTREQUEST fixture: flags 0 (no broadcast), secs 65535, ciaddr
// set, sname "A...", file "BOOT...", one option 53 = 8 (INFORM).
fn info_fixture() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 1);
  push_byte(&mut v, 1);
  push_byte(&mut v, 6);
  push_byte(&mut v, 0);
  push_be32(&mut v, 305419896);
  push_be16(&mut v, 65535);
  push_be16(&mut v, 0);
  push_be32(&mut v, 3232235876);
  push_be32(&mut v, 0);
  push_be32(&mut v, 0);
  push_be32(&mut v, 0);
  push_byte(&mut v, 171);
  push_byte(&mut v, 205);
  push_byte(&mut v, 239);
  push_byte(&mut v, 1);
  push_byte(&mut v, 35);
  push_byte(&mut v, 69);
  push_zeros(&mut v, 10);
  push_byte(&mut v, 65);
  push_zeros(&mut v, 63);
  push_byte(&mut v, 66);
  push_byte(&mut v, 79);
  push_byte(&mut v, 79);
  push_byte(&mut v, 84);
  push_zeros(&mut v, 124);
  push_byte(&mut v, 99);
  push_byte(&mut v, 130);
  push_byte(&mut v, 83);
  push_byte(&mut v, 99);
  push_byte(&mut v, 53);
  push_byte(&mut v, 1);
  push_byte(&mut v, 8);
  push_byte(&mut v, 255);
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let fx = offer_fixture();
  var ok = fx.len() == 299;
  if !dhcp_is_packet(&fx) { ok = false; }
  let r = dhcp_parse(&fx);
  if !r.is_ok { return assert(false, "offer fixture must parse"); }
  let p: DhcpPacket = r.value;
  if p.op != 2 { ok = false; }
  if p.htype != 1 { ok = false; }
  if p.hlen != 6 { ok = false; }
  if p.hops != 0 { ok = false; }
  if p.xid != 305419896 { ok = false; }
  if p.secs != 5 { ok = false; }
  if p.flags != 32768 { ok = false; }
  if !p.broadcast { ok = false; }
  if p.ciaddr != 0 { ok = false; }
  if p.yiaddr != 3232235876 { ok = false; }
  if p.siaddr != 3232235777 { ok = false; }
  if p.giaddr != 167772161 { ok = false; }
  let ch: Vec[UInt8] = p.chaddr;
  if ch.len() != 16 { ok = false; }
  if byte_at(ch, 0) != 222 { ok = false; }
  if byte_at(ch, 5) != 1 { ok = false; }
  var i = 6;
  while i < 16 {
    if byte_at(ch, i) != 0 { ok = false; }
    i = i + 1;
  }
  let sn: Vec[UInt8] = p.sname;
  if sn.len() != 64 { ok = false; }
  if byte_at(sn, 0) != 100 { ok = false; }
  if byte_at(sn, 4) != 100 { ok = false; }
  if byte_at(sn, 5) != 0 { ok = false; }
  if byte_at(sn, 63) != 0 { ok = false; }
  let fl: Vec[UInt8] = p.file;
  if fl.len() != 128 { ok = false; }
  if byte_at(fl, 0) != 112 { ok = false; }
  if byte_at(fl, 9) != 48 { ok = false; }
  if byte_at(fl, 10) != 0 { ok = false; }
  if byte_at(fl, 127) != 0 { ok = false; }
  if dhcp_option_count(&p) != 8 { ok = false; }
  return assert(ok, "hand-built OFFER: fixed header, chaddr/sname/file pinned");
}

fn t2() -> TestResult {
  let fx = info_fixture();
  var ok = fx.len() == 244;
  if !dhcp_is_packet(&fx) { ok = false; }
  let r = dhcp_parse(&fx);
  if !r.is_ok { return assert(false, "info fixture must parse"); }
  let p: DhcpPacket = r.value;
  if p.op != 1 { ok = false; }
  if p.secs != 65535 { ok = false; }
  if p.flags != 0 { ok = false; }
  if p.broadcast { ok = false; }
  if p.ciaddr != 3232235876 { ok = false; }
  if p.hlen != 6 { ok = false; }
  let ch: Vec[UInt8] = p.chaddr;
  if byte_at(ch, 0) != 171 { ok = false; }
  if byte_at(ch, 5) != 69 { ok = false; }
  if byte_at(ch, 6) != 0 { ok = false; }
  let sn: Vec[UInt8] = p.sname;
  if byte_at(sn, 0) != 65 { ok = false; }
  if byte_at(sn, 1) != 0 { ok = false; }
  if byte_at(sn, 63) != 0 { ok = false; }
  let fl: Vec[UInt8] = p.file;
  if byte_at(fl, 0) != 66 { ok = false; }
  if byte_at(fl, 3) != 84 { ok = false; }
  if byte_at(fl, 4) != 0 { ok = false; }
  if dhcp_message_type(&fx, &p) != 8 { ok = false; }
  if dhcp_option_count(&p) != 1 { ok = false; }
  return assert(ok, "flags=0 unicast, secs boundary and sname/file markers");
}

fn t3() -> TestResult {
  let fx = offer_fixture();
  let r = dhcp_parse(&fx);
  if !r.is_ok { return assert(false, "offer fixture must parse"); }
  let p: DhcpPacket = r.value;
  var ok = dhcp_option_count(&p) == 8;
  if dhcp_option_code(&p, 0) != 53 { ok = false; }
  if dhcp_option_code(&p, 1) != 54 { ok = false; }
  if dhcp_option_code(&p, 2) != 51 { ok = false; }
  if dhcp_option_code(&p, 3) != 1 { ok = false; }
  if dhcp_option_code(&p, 4) != 3 { ok = false; }
  if dhcp_option_code(&p, 5) != 6 { ok = false; }
  if dhcp_option_code(&p, 6) != 12 { ok = false; }
  if dhcp_option_code(&p, 7) != 61 { ok = false; }
  let o0: Int = p.option_offsets[0];
  let o1: Int = p.option_offsets[1];
  let o2: Int = p.option_offsets[2];
  let o3: Int = p.option_offsets[3];
  let o4: Int = p.option_offsets[4];
  let o5: Int = p.option_offsets[5];
  let o6: Int = p.option_offsets[6];
  let o7: Int = p.option_offsets[7];
  if o0 != 243 { ok = false; }
  if o1 != 246 { ok = false; }
  if o2 != 252 { ok = false; }
  if o3 != 258 { ok = false; }
  if o4 != 264 { ok = false; }
  if o5 != 270 { ok = false; }
  if o6 != 280 { ok = false; }
  if o7 != 291 { ok = false; }
  if dhcp_option_length(&p, 0) != 1 { ok = false; }
  if dhcp_option_length(&p, 1) != 4 { ok = false; }
  if dhcp_option_length(&p, 2) != 4 { ok = false; }
  if dhcp_option_length(&p, 5) != 8 { ok = false; }
  if dhcp_option_length(&p, 6) != 9 { ok = false; }
  if dhcp_option_length(&p, 7) != 3 { ok = false; }
  if dhcp_find_option(&p, 53) != 0 { ok = false; }
  if dhcp_find_option(&p, 6) != 5 { ok = false; }
  if dhcp_find_option(&p, 61) != 7 { ok = false; }
  if dhcp_find_option(&p, 55) != -1 { ok = false; }
  if dhcp_find_option(&p, 0) != -1 { ok = false; }
  if dhcp_find_option(&p, 255) != -1 { ok = false; }
  if dhcp_option_code(&p, -1) != -1 { ok = false; }
  if dhcp_option_code(&p, 8) != -1 { ok = false; }
  if dhcp_option_length(&p, 8) != -1 { ok = false; }
  return assert(ok, "option index: codes, absolute offsets, lengths, first-match find");
}

fn t4() -> TestResult {
  let fx = offer_fixture();
  let r = dhcp_parse(&fx);
  if !r.is_ok { return assert(false, "offer fixture must parse"); }
  let p: DhcpPacket = r.value;
  var ok = true;
  let v0 = dhcp_option_value(&fx, &p, 0);
  if !v0.is_ok { ok = false; } elif !bytes_equal(v0.value, bytes1(2)) { ok = false; }
  let v6 = dhcp_option_value(&fx, &p, 6);
  if !v6.is_ok { ok = false; } elif !bytes_equal(v6.value, bytes_of("xiom-host")) { ok = false; }
  let v7 = dhcp_option_value(&fx, &p, 7);
  if !v7.is_ok { ok = false; } elif !bytes_equal(v7.value, bytes3(1, 222, 173)) { ok = false; }
  if !err_bytes_is(dhcp_option_value(&fx, &p, 8), "dhcp: option index out of range") { ok = false; }
  if !err_bytes_is(dhcp_option_value(&fx, &p, -1), "dhcp: option index out of range") { ok = false; }
  let cut = prefix(fx, 290);
  let vc = dhcp_option_value(&cut, &p, 7);
  if vc.is_ok { ok = false; }
  if !err_bytes_is(vc, "dhcp: option out of bounds") { ok = false; }
  let vh = dhcp_option_value(&cut, &p, 6);
  if !vh.is_ok { ok = false; } elif !bytes_equal(vh.value, bytes_of("xiom-host")) { ok = false; }
  return assert(ok, "option values slice exactly; bad index and short buffer are Err");
}

fn t5() -> TestResult {
  let fx = offer_fixture();
  let r = dhcp_parse(&fx);
  if !r.is_ok { return assert(false, "offer fixture must parse"); }
  let p: DhcpPacket = r.value;
  var ok = dhcp_message_type(&fx, &p) == 2;
  if dhcp_server_id(&fx, &p) != 3232235777 { ok = false; }
  if dhcp_lease_time(&fx, &p) != 86400 { ok = false; }
  if dhcp_subnet_mask(&fx, &p) != 4294967040 { ok = false; }
  if dhcp_requested_ip(&fx, &p) != -1 { ok = false; }
  if dhcp_option_u32(&fx, &p, 1) != 4294967040 { ok = false; }
  if dhcp_option_u32(&fx, &p, 53) != -1 { ok = false; }
  if dhcp_option_u32(&fx, &p, 55) != -1 { ok = false; }
  if dhcp_router_count(&fx, &p) != 1 { ok = false; }
  if dhcp_router_at(&fx, &p, 0) != 3232235777 { ok = false; }
  if dhcp_router_at(&fx, &p, 1) != -1 { ok = false; }
  if dhcp_router_at(&fx, &p, -1) != -1 { ok = false; }
  if dhcp_dns_count(&fx, &p) != 2 { ok = false; }
  if dhcp_dns_at(&fx, &p, 0) != 134744072 { ok = false; }
  if dhcp_dns_at(&fx, &p, 1) != 134743044 { ok = false; }
  if dhcp_dns_at(&fx, &p, 2) != -1 { ok = false; }
  return assert(ok, "typed accessors: message type, mask, lease, server, router/DNS lists");
}

fn t6() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_packet_is(dhcp_parse(&empty), "dhcp: short packet");
  let short100 = repeat_byte(0, 100);
  if !err_packet_is(dhcp_parse(&short100), "dhcp: short packet") { ok = false; }
  let fx = offer_fixture();
  let cut239 = prefix(fx, 239);
  if !err_packet_is(dhcp_parse(&cut239), "dhcp: short packet") { ok = false; }
  if dhcp_is_packet(&empty) { ok = false; }
  if dhcp_is_packet(&cut239) { ok = false; }
  if !dhcp_is_packet(&fx) { ok = false; }
  var bad1 = prefix(fx, 236);
  push_byte(&mut bad1, 98);
  push_byte(&mut bad1, 130);
  push_byte(&mut bad1, 83);
  push_byte(&mut bad1, 99);
  push_byte(&mut bad1, 255);
  if !err_packet_is(dhcp_parse(&bad1), "dhcp: bad cookie") { ok = false; }
  if dhcp_is_packet(&bad1) { ok = false; }
  var bad4 = prefix(fx, 236);
  push_byte(&mut bad4, 99);
  push_byte(&mut bad4, 130);
  push_byte(&mut bad4, 83);
  push_byte(&mut bad4, 98);
  push_byte(&mut bad4, 255);
  if !err_packet_is(dhcp_parse(&bad4), "dhcp: bad cookie") { ok = false; }
  let zeros240 = repeat_byte(0, 240);
  if !err_packet_is(dhcp_parse(&zeros240), "dhcp: bad cookie") { ok = false; }
  return assert(ok, "short packet and bad cookie are the first two errors");
}

fn t7() -> TestResult {
  var ok = true;
  let q1 = with_options(hb("35"));
  if !err_packet_is(dhcp_parse(&q1), "dhcp: truncated option") { ok = false; }
  let q2 = with_options(hb("350201"));
  if !err_packet_is(dhcp_parse(&q2), "dhcp: truncated option") { ok = false; }
  let q3 = with_options(hb("3501010c"));
  if !err_packet_is(dhcp_parse(&q3), "dhcp: truncated option") { ok = false; }
  let q4 = with_options(hb("330400"));
  if !err_packet_is(dhcp_parse(&q4), "dhcp: truncated option") { ok = false; }
  let q5 = with_options(hb("0104"));
  if !err_packet_is(dhcp_parse(&q5), "dhcp: truncated option") { ok = false; }
  let ctl = with_options(hb("350101ff"));
  if !dhcp_parse(&ctl).is_ok { ok = false; }
  return assert(ok, "truncated option bytes are Err; the exact-fit control parses");
}

fn t8() -> TestResult {
  let bare = header_only();
  var ok = err_packet_is(dhcp_parse(&bare), "dhcp: missing end");
  let pads = with_options(hb("000000"));
  if !err_packet_is(dhcp_parse(&pads), "dhcp: missing end") { ok = false; }
  let no_end = with_options(hb("350102"));
  if !err_packet_is(dhcp_parse(&no_end), "dhcp: missing end") { ok = false; }
  let ended = with_options(hb("ff"));
  if ended.len() != 241 { ok = false; }
  let er = dhcp_parse(&ended);
  if !er.is_ok { ok = false; } else {
    let p: DhcpPacket = er.value;
    if dhcp_option_count(&p) != 0 { ok = false; }
  }
  let trail = with_options(hb("ffdeadbeef"));
  let tr = dhcp_parse(&trail);
  if !tr.is_ok { ok = false; } else {
    let p2: DhcpPacket = tr.value;
    if dhcp_option_count(&p2) != 0 { ok = false; }
  }
  return assert(ok, "missing end is Err; bytes after the end option are ignored");
}

fn t9() -> TestResult {
  var ok = true;
  let b1 = with_options(hb("35020102"));
  if !err_packet_is(dhcp_parse(&b1), "dhcp: bad option length") { ok = false; }
  let b2 = with_options(hb("0103010203"));
  if !err_packet_is(dhcp_parse(&b2), "dhcp: bad option length") { ok = false; }
  let b3 = with_options(hb("3603010203"));
  if !err_packet_is(dhcp_parse(&b3), "dhcp: bad option length") { ok = false; }
  let b4 = with_options(hb("0c00"));
  if !err_packet_is(dhcp_parse(&b4), "dhcp: bad option length") { ok = false; }
  let b5 = with_options(hb("3d0101"));
  if !err_packet_is(dhcp_parse(&b5), "dhcp: bad option length") { ok = false; }
  let b6 = with_options(hb("33020001"));
  if !err_packet_is(dhcp_parse(&b6), "dhcp: bad option length") { ok = false; }
  let b7 = with_options(hb("3700"));
  if !err_packet_is(dhcp_parse(&b7), "dhcp: bad option length") { ok = false; }
  let b8 = with_options(hb("03050102030405"));
  if !err_packet_is(dhcp_parse(&b8), "dhcp: bad option length") { ok = false; }
  let b9 = with_options(hb("0600"));
  if !err_packet_is(dhcp_parse(&b9), "dhcp: bad option length") { ok = false; }
  let c1 = with_options(hb("0c0161ff"));
  if !dhcp_parse(&c1).is_ok { ok = false; }
  let c2 = with_options(hb("3d0201deff"));
  if !dhcp_parse(&c2).is_ok { ok = false; }
  let c3 = with_options(hb("0304c0a80101ff"));
  if !dhcp_parse(&c3).is_ok { ok = false; }
  let c4 = with_options(hb("370101ff"));
  if !dhcp_parse(&c4).is_ok { ok = false; }
  let c5 = with_options(hb("c803010203ff"));
  let c5r = dhcp_parse(&c5);
  if !c5r.is_ok { ok = false; } else {
    let p5: DhcpPacket = c5r.value;
    if dhcp_option_count(&p5) != 1 { ok = false; }
    if dhcp_option_code(&p5, 0) != 200 { ok = false; }
    if dhcp_option_length(&p5, 0) != 3 { ok = false; }
  }
  return assert(ok, "documented option shapes reject bad lengths; unknown codes pass");
}

fn t10() -> TestResult {
  var out = Vec[UInt8].new();
  let v1 = bytes1(1);
  let ra = dhcp_append_option(&mut out, 53, &v1);
  let host = bytes_of("xiom");
  let rb = dhcp_append_option(&mut out, 12, &host);
  var ok = ra.is_ok && rb.is_ok;
  if !bytes_equal(out, hb("3501010c0478696f6d")) { ok = false; }
  let len_before = out.len();
  if !err_unit_is(dhcp_append_option(&mut out, 0, &v1), "dhcp: bad option code") { ok = false; }
  if !err_unit_is(dhcp_append_option(&mut out, 255, &v1), "dhcp: bad option code") { ok = false; }
  if !err_unit_is(dhcp_append_option(&mut out, -1, &v1), "dhcp: bad option code") { ok = false; }
  if !err_unit_is(dhcp_append_option(&mut out, 256, &v1), "dhcp: bad option code") { ok = false; }
  let big = repeat_byte(7, 256);
  if !err_unit_is(dhcp_append_option(&mut out, 200, &big), "dhcp: option value too long") { ok = false; }
  let mask3 = bytes3(1, 2, 3);
  if !err_unit_is(dhcp_append_option(&mut out, 1, &mask3), "dhcp: bad option length") { ok = false; }
  let sid3 = bytes3(1, 2, 3);
  if !err_unit_is(dhcp_append_option(&mut out, 54, &sid3), "dhcp: bad option length") { ok = false; }
  var empty = Vec[UInt8].new();
  if !err_unit_is(dhcp_append_option(&mut out, 12, &empty), "dhcp: bad option length") { ok = false; }
  if out.len() != len_before { ok = false; }
  let max = repeat_byte(9, 255);
  let rz = dhcp_append_option(&mut out, 200, &max);
  if !rz.is_ok { ok = false; } elif out.len() != len_before + 257 { ok = false; }
  return assert(ok, "append_option: exact bytes, atomic errors, 255-byte boundary");
}

fn t11() -> TestResult {
  let mac = mac6();
  var opts = Vec[UInt8].new();
  let m1 = bytes1(1);
  let a1 = dhcp_append_option(&mut opts, 53, &m1);
  let h2 = bytes_of("ab");
  let a2 = dhcp_append_option(&mut opts, 12, &h2);
  var ok = a1.is_ok && a2.is_ok;
  let br = dhcp_build_client(305419896, &mac, true, &opts);
  if !br.is_ok { return assert(false, "build_client must succeed"); }
  let built: Vec[UInt8] = br.value;
  if built.len() != 248 { ok = false; }
  var want = client_frame(305419896, &mac, 32768);
  want = concat2(want, opt(53, bytes1(1)));
  want = concat2(want, opt(12, bytes_of("ab")));
  want = concat2(want, bytes1(255));
  if !bytes_equal(built, want) { ok = false; }
  let pr = dhcp_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let p: DhcpPacket = pr.value;
    if p.op != 1 { ok = false; }
    if p.htype != 1 { ok = false; }
    if p.hlen != 6 { ok = false; }
    if p.xid != 305419896 { ok = false; }
    if !p.broadcast { ok = false; }
    if p.flags != 32768 { ok = false; }
    if p.ciaddr != 0 { ok = false; }
    if p.yiaddr != 0 { ok = false; }
    let ch: Vec[UInt8] = p.chaddr;
    if !bytes_equal(prefix(ch, 6), mac6()) { ok = false; }
    if byte_at(ch, 15) != 0 { ok = false; }
    if dhcp_message_type(&built, &p) != 1 { ok = false; }
    let hv = dhcp_option_value(&built, &p, 1);
    if !hv.is_ok { ok = false; } elif !bytes_equal(hv.value, bytes_of("ab")) { ok = false; }
    if dhcp_option_count(&p) != 2 { ok = false; }
  }
  return assert(ok, "build_client writes the exact frame and parses back");
}

fn t12() -> TestResult {
  let mac = mac6();
  var empty = Vec[UInt8].new();
  var ok = err_bytes_is(dhcp_build_client(-1, &mac, true, &empty), "dhcp: bad xid");
  if !err_bytes_is(dhcp_build_client(4294967296, &mac, true, &empty), "dhcp: bad xid") { ok = false; }
  if !err_bytes_is(dhcp_build_client(1, &empty, true, &empty), "dhcp: bad chaddr length") { ok = false; }
  let big = repeat_byte(7, 17);
  if !err_bytes_is(dhcp_build_client(1, &big, true, &empty), "dhcp: bad chaddr length") { ok = false; }
  let r0 = dhcp_build_client(0, &mac, false, &empty);
  if !r0.is_ok { ok = false; } else {
    let b0: Vec[UInt8] = r0.value;
    if b0.len() != 241 { ok = false; }
    let f: Int = (b0[10] as Int) & 0xFF;
    if f != 0 { ok = false; }
    let pr = dhcp_parse(&b0);
    if !pr.is_ok { ok = false; } else {
      let p: DhcpPacket = pr.value;
      if p.xid != 0 { ok = false; }
      if p.broadcast { ok = false; }
      if p.flags != 0 { ok = false; }
      let sn: Vec[UInt8] = p.sname;
      if sn.len() != 64 { ok = false; }
      if dhcp_option_count(&p) != 0 { ok = false; }
    }
  }
  let rmax = dhcp_build_client(4294967295, &mac, true, &empty);
  if !rmax.is_ok { ok = false; } else {
    let bmax: Vec[UInt8] = rmax.value;
    let pr2 = dhcp_parse(&bmax);
    if !pr2.is_ok { ok = false; } else {
      let p2: DhcpPacket = pr2.value;
      if p2.xid != 4294967295 { ok = false; }
    }
  }
  let c16 = repeat_byte(171, 16);
  let rc = dhcp_build_client(7, &c16, true, &empty);
  if !rc.is_ok { ok = false; } else {
    let bc: Vec[UInt8] = rc.value;
    if bc.len() != 241 { ok = false; }
    let pc = dhcp_parse(&bc);
    if !pc.is_ok { ok = false; } else {
      let p3: DhcpPacket = pc.value;
      if p3.hlen != 16 { ok = false; }
      let ch3: Vec[UInt8] = p3.chaddr;
      if byte_at(ch3, 0) != 171 { ok = false; }
      if byte_at(ch3, 15) != 171 { ok = false; }
    }
  }
  return assert(ok, "build_client validates xid and chaddr; boundaries accepted");
}

fn t13() -> TestResult {
  let mac = mac6();
  let r = dhcp_build_discover(305419896, &mac);
  if !r.is_ok { return assert(false, "build_discover must succeed"); }
  let built: Vec[UInt8] = r.value;
  var ok = built.len() == 261;
  let cid = client_id(&mac);
  let prl = param_list();
  var want = client_frame(305419896, &mac, 32768);
  want = concat2(want, opt(53, bytes1(1)));
  want = concat2(want, opt(61, cid));
  want = concat2(want, opt(55, prl));
  want = concat2(want, bytes1(255));
  if !bytes_equal(built, want) { ok = false; }
  let pr = dhcp_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let p: DhcpPacket = pr.value;
    if p.op != 1 { ok = false; }
    if p.hlen != 6 { ok = false; }
    if !p.broadcast { ok = false; }
    if p.yiaddr != 0 { ok = false; }
    if dhcp_message_type(&built, &p) != 1 { ok = false; }
    if dhcp_option_count(&p) != 3 { ok = false; }
    let cidx = dhcp_find_option(&p, 61);
    if cidx != 1 { ok = false; }
    let cv = dhcp_option_value(&built, &p, cidx);
    if !cv.is_ok { ok = false; } elif !bytes_equal(cv.value, cid) { ok = false; }
    let pidx = dhcp_find_option(&p, 55);
    let pv = dhcp_option_value(&built, &p, pidx);
    if !pv.is_ok { ok = false; } elif !bytes_equal(pv.value, prl) { ok = false; }
    if dhcp_find_option(&p, 50) != -1 { ok = false; }
  }
  return assert(ok, "build_discover: exact bytes, PRL and client id round-trip");
}

fn t14() -> TestResult {
  let mac = mac6();
  let r = dhcp_build_request(305419896, &mac, 3232235876, 3232235777);
  if !r.is_ok { return assert(false, "build_request must succeed"); }
  let built: Vec[UInt8] = r.value;
  var ok = built.len() == 273;
  let cid = client_id(&mac);
  let prl = param_list();
  var want = client_frame(305419896, &mac, 32768);
  want = concat2(want, opt(53, bytes1(3)));
  want = concat2(want, opt(61, cid));
  want = concat2(want, opt(50, ip4(3232235876)));
  want = concat2(want, opt(54, ip4(3232235777)));
  want = concat2(want, opt(55, prl));
  want = concat2(want, bytes1(255));
  if !bytes_equal(built, want) { ok = false; }
  let pr = dhcp_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let p: DhcpPacket = pr.value;
    if dhcp_message_type(&built, &p) != 3 { ok = false; }
    if dhcp_requested_ip(&built, &p) != 3232235876 { ok = false; }
    if dhcp_server_id(&built, &p) != 3232235777 { ok = false; }
    if dhcp_lease_time(&built, &p) != -1 { ok = false; }
    if p.ciaddr != 0 { ok = false; }
    if p.yiaddr != 0 { ok = false; }
    if dhcp_option_count(&p) != 5 { ok = false; }
  }
  let r2 = dhcp_build_request(77, &mac, -1, -1);
  if !r2.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = r2.value;
    if b2.len() != 261 { ok = false; }
    let p2r = dhcp_parse(&b2);
    if !p2r.is_ok { ok = false; } else {
      let p2: DhcpPacket = p2r.value;
      if dhcp_find_option(&p2, 50) != -1 { ok = false; }
      if dhcp_find_option(&p2, 54) != -1 { ok = false; }
      if dhcp_requested_ip(&b2, &p2) != -1 { ok = false; }
      if dhcp_server_id(&b2, &p2) != -1 { ok = false; }
      if dhcp_option_count(&p2) != 3 { ok = false; }
    }
  }
  if !err_bytes_is(dhcp_build_request(1, &mac, 4294967296, -1), "dhcp: bad ip address") { ok = false; }
  if !err_bytes_is(dhcp_build_request(1, &mac, -1, 4294967296), "dhcp: bad ip address") { ok = false; }
  if !err_bytes_is(dhcp_build_request(-1, &mac, -1, -1), "dhcp: bad xid") { ok = false; }
  let rb = dhcp_build_request(1, &mac, 4294967295, 0);
  if !rb.is_ok { ok = false; } else {
    let bb: Vec[UInt8] = rb.value;
    let pbr = dhcp_parse(&bb);
    if !pbr.is_ok { ok = false; } else {
      let pb: DhcpPacket = pbr.value;
      if dhcp_requested_ip(&bb, &pb) != 4294967295 { ok = false; }
      if dhcp_server_id(&bb, &pb) != 0 { ok = false; }
    }
  }
  return assert(ok, "build_request: exact bytes, optional 50/54, ip validation");
}

fn t15() -> TestResult {
  let mac = mac6();
  let r1 = dhcp_build_request(123456, &mac, 3232235876, 3232235777);
  if !r1.is_ok { return assert(false, "first build must succeed"); }
  let b1: Vec[UInt8] = r1.value;
  let p1r = dhcp_parse(&b1);
  if !p1r.is_ok { return assert(false, "built request must parse"); }
  let p1: DhcpPacket = p1r.value;
  let r2 = dhcp_build_request(p1.xid, &mac, dhcp_requested_ip(&b1, &p1), dhcp_server_id(&b1, &p1));
  if !r2.is_ok { return assert(false, "rebuild must succeed"); }
  let b2: Vec[UInt8] = r2.value;
  var ok = bytes_equal(b1, b2);
  let offer = offer_fixture();
  let orr = dhcp_parse(&offer);
  if !orr.is_ok { return assert(false, "offer must parse"); }
  let op: DhcpPacket = orr.value;
  let didx = dhcp_find_option(&op, 6);
  let dv = dhcp_option_value(&offer, &op, didx);
  if !dv.is_ok { return assert(false, "DNS value must copy out"); }
  let dns_bytes: Vec[UInt8] = dv.value;
  var opts = Vec[UInt8].new();
  let a = dhcp_append_option(&mut opts, 6, &dns_bytes);
  if !a.is_ok { ok = false; }
  let nr = dhcp_build_client(999, &mac, true, &opts);
  if !nr.is_ok { ok = false; } else {
    let nb: Vec<UInt8> = nr.value;
    let npr = dhcp_parse(&nb);
    if !npr.is_ok { ok = false; } else {
      let np: DhcpPacket = npr.value;
      if dhcp_dns_count(&nb, &np) != 2 { ok = false; }
      if dhcp_dns_at(&nb, &np, 0) != 134744072 { ok = false; }
      if dhcp_dns_at(&nb, &np, 1) != 134743044 { ok = false; }
      if dhcp_message_type(&nb, &np) != -1 { ok = false; }
      if np.xid != 999 { ok = false; }
    }
  }
  return assert(ok, "build -> parse -> rebuild is stable; DNS values survive re-frame");
}

fn t16() -> TestResult {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 2);
  push_byte(&mut v, 255);
  push_byte(&mut v, 255);
  push_byte(&mut v, 255);
  push_be32(&mut v, 4294967295);
  push_be16(&mut v, 65535);
  push_be16(&mut v, 65535);
  push_be32(&mut v, 4294967295);
  push_be32(&mut v, 4294967295);
  push_be32(&mut v, 4294967295);
  push_be32(&mut v, 4294967295);
  push_zeros(&mut v, 16);
  push_zeros(&mut v, 64);
  push_zeros(&mut v, 128);
  push_byte(&mut v, 99);
  push_byte(&mut v, 130);
  push_byte(&mut v, 83);
  push_byte(&mut v, 99);
  push_byte(&mut v, 51);
  push_byte(&mut v, 4);
  push_be32(&mut v, 4294967295);
  push_byte(&mut v, 1);
  push_byte(&mut v, 4);
  push_be32(&mut v, 4294967040);
  push_byte(&mut v, 53);
  push_byte(&mut v, 1);
  push_byte(&mut v, 255);
  push_byte(&mut v, 255);
  var ok = v.len() == 256;
  let r = dhcp_parse(&v);
  if !r.is_ok { return assert(false, "boundary packet must parse"); }
  let p: DhcpPacket = r.value;
  if p.xid != 4294967295 { ok = false; }
  if p.secs != 65535 { ok = false; }
  if p.flags != 65535 { ok = false; }
  if !p.broadcast { ok = false; }
  if p.ciaddr != 4294967295 { ok = false; }
  if p.yiaddr != 4294967295 { ok = false; }
  if p.siaddr != 4294967295 { ok = false; }
  if p.giaddr != 4294967295 { ok = false; }
  if p.hlen != 255 { ok = false; }
  if p.htype != 255 { ok = false; }
  if p.hops != 255 { ok = false; }
  if dhcp_lease_time(&v, &p) != 4294967295 { ok = false; }
  if dhcp_subnet_mask(&v, &p) != 4294967040 { ok = false; }
  if dhcp_message_type(&v, &p) != 255 { ok = false; }
  if dhcp_option_u32(&v, &p, 53) != -1 { ok = false; }
  return assert(ok, "unsigned fields keep high bits; message type value is raw");
}

fn main() -> Int {
  io.println("=== xiom.dhcp conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.dhcp: all tests passed");
  } else {
    io.println("xiom.dhcp: tests failed");
  }
  return failed;
}
