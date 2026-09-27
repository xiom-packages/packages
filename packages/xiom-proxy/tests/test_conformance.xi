// XIOM -- xiom.proxy conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: v1 TCP4/TCP6/UNKNOWN lines (pinned bytes,
// canonical IPv6 re-render, opaque tails, the 107-byte cap and every
// malformed-line class), v2 IPv4/IPv6/UNIX/LOCAL/UNSPEC headers (pinned
// bytes, address blocks, consumed counts), signature/version/command/family/
// protocol/length rejection, the canonical HAProxy TLV registry (ALPN,
// authority, CRC32C, NOOP, unique id, SSL 0x20 with its 0x21..0x25 sub-TLVs,
// NETNS 0x30, AWS 0xEA with its sub-TLV stream, unknown preservation),
// u16/u32/u64 readers, CRC32C (known vector plus header verification and
// tampering), version detection, header_len/payload spans, parse_one
// summaries and the IPv4/IPv6 text codecs.
//
// Str values are compared with str_compare (BUG 17 discipline), every Vec
// read is bound to a typed local, result values are unwrapped through
// .is_ok/.value and synthetic headers are built in-test (hex.decode plus
// byte/result helpers).

module proxy_tests
use xiom.io; use xiom.test;
use xiom.proxy;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string (empty on malformed input; the caller's
// byte comparison then fails).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    return r.value;
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

fn addb(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

fn cat(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < parts.len() {
    let p: Vec[UInt8] = parts[i];
    addb(&mut out, &p);
    i = i + 1;
  }
  return out;
}

fn rep(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push((b & 0xFF) as UInt8);
    i = i + 1;
  }
  return v;
}

fn span_copy(v: Vec[UInt8], a: Int, b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = a;
  while i < b {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn with_byte_at(v: Vec[UInt8], off: Int, b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == off {
      out.push((b & 0xFF) as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn with_u32_at(v: Vec[UInt8], off: Int, val: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == off {
      out.push(((val / 16777216) % 256) as UInt8);
    } else if i == off + 1 {
      out.push(((val / 65536) % 256) as UInt8);
    } else if i == off + 2 {
      out.push(((val / 256) % 256) as UInt8);
    } else if i == off + 3 {
      out.push((val % 256) as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn u16_at(v: Vec[UInt8], off: Int) -> Int {
  return ((v[off] as Int) & 0xFF) * 256 + ((v[off + 1] as Int) & 0xFF);
}

fn u32_at(v: Vec[UInt8], off: Int) -> Int {
  return u16_at(v, off) * 65536 + u16_at(v, off + 2);
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Result unwrap / error helpers
// --------------------------------------------------

fn enc_ok(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  if r.is_ok {
    return r.value;
  }
  return Vec[UInt8].new();
}

fn int_ok(r: Result[Int, Str]) -> Int {
  if r.is_ok {
    return r.value;
  }
  return -1;
}

fn bool_ok(r: Result[Bool, Str]) -> Bool {
  if r.is_ok {
    return r.value;
  }
  return false;
}

fn pair_ok(r: Result[(Int, Int), Str]) -> (Int, Int) {
  if r.is_ok {
    return r.value;
  }
  return (0, 0);
}

fn cursor_ok(r: Result[ProxyTlvCursor, Str]) -> ProxyTlvCursor {
  if r.is_ok {
    return r.value;
  }
  return ProxyTlvCursor{ tlv_type: -1; value_start: 0; value_end: 0; next: -1 };
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_pair_is(r: Result[(Int, Int), Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_v1_is(r: Result[ProxyV1, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_v2_is(r: Result[ProxyV2, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_sum_is(r: Result[ProxySummary, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_tlv_is(r: Result[ProxyTlvCursor, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  Sentinel-unwrapping parse helpers
// --------------------------------------------------

fn empty_v1() -> ProxyV1 {
  return ProxyV1{
    family: -1;
    src_addr: Vec[UInt8].new();
    dst_addr: Vec[UInt8].new();
    src_port: -1;
    dst_port: -1;
    opaque: Vec[UInt8].new();
    consumed: 0;
  };
}

fn v1_ok(data: Vec[UInt8], off: Int) -> ProxyV1 {
  let r = proxy_parse_v1(&data, off);
  if r.is_ok {
    return r.value;
  }
  return empty_v1();
}

fn empty_v2() -> ProxyV2 {
  return ProxyV2{
    version: -1;
    command: -1;
    family: -1;
    protocol: -1;
    src_addr: Vec[UInt8].new();
    dst_addr: Vec[UInt8].new();
    src_port: -1;
    dst_port: -1;
    unix_src: Vec[UInt8].new();
    unix_dst: Vec[UInt8].new();
    tlvs: Vec[UInt8].new();
    payload: Vec[UInt8].new();
    tlvs_off: -1;
    consumed: 0;
  };
}

fn v2_ok(data: Vec[UInt8], off: Int) -> ProxyV2 {
  let r = proxy_parse_v2(&data, off);
  if r.is_ok {
    return r.value;
  }
  return empty_v2();
}

fn empty_sum() -> ProxySummary {
  return ProxySummary{
    version: -1;
    command: -1;
    family: -1;
    protocol: -1;
    src_port: -1;
    dst_port: -1;
    consumed: 0;
  };
}

fn sum_ok(data: Vec[UInt8], off: Int) -> ProxySummary {
  let r = proxy_parse_one(&data, off);
  if r.is_ok {
    return r.value;
  }
  return empty_sum();
}

// --------------------------------------------------
//  Field comparison helpers (structs passed by reference)
// --------------------------------------------------

fn v1_src_is(v: &ProxyV1, want: Str) -> Bool {
  if v.src_addr.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if v.src_addr[i] != string.byte_at(want, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn v1_dst_is(v: &ProxyV1, want: Str) -> Bool {
  if v.dst_addr.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if v.dst_addr[i] != string.byte_at(want, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn v1_opaque_is(v: &ProxyV1, want: Str) -> Bool {
  if v.opaque.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if v.opaque[i] != string.byte_at(want, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn v2_hex_is(v: &Vec[UInt8], want: Str) -> Bool {
  let w = hb(want);
  if v.len() != w.len() {
    return false;
  }
  var i = 0;
  while i < w.len() {
    if v[i] != w[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn unix_src_is(v: &ProxyV2, want: Str) -> Bool {
  if v.unix_src.len() != 108 {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if v.unix_src[i] != string.byte_at(want, i) {
      return false;
    }
    i = i + 1;
  }
  while i < 108 {
    if v.unix_src[i] != (0 as UInt8) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn unix_dst_is(v: &ProxyV2, want: Str) -> Bool {
  if v.unix_dst.len() != 108 {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if v.unix_dst[i] != string.byte_at(want, i) {
      return false;
    }
    i = i + 1;
  }
  while i < 108 {
    if v.unix_dst[i] != (0 as UInt8) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  t1: v1 TCP4 pinned bytes, fields, consumed, offset parse
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  let line_text = "PROXY TCP4 192.168.0.1 192.168.0.11 56324 443\r\n";
  let op = v1_ok(bytes_of(line_text), 0);
  if op.family != 1 { ok = false; }
  if op.consumed != line_text.len() { ok = false; }
  if !v1_src_is(&op, "192.168.0.1") { ok = false; }
  if !v1_dst_is(&op, "192.168.0.11") { ok = false; }
  if op.src_port != 56324 { ok = false; }
  if op.dst_port != 443 { ok = false; }
  if op.opaque.len() != 0 { ok = false; }
  let enc = enc_ok(proxy_v1_encode_tcp4(&bytes_of("192.168.0.1"), &bytes_of("192.168.0.11"), 56324, 443));
  if !bytes_equal(enc, bytes_of(line_text)) { ok = false; }
  var framed = Vec[UInt8].new();
  addb(&mut framed, &bytes_of("XYZ"));
  addb(&mut framed, &bytes_of(line_text));
  let op2 = v1_ok(framed, 3);
  if op2.consumed != line_text.len() { ok = false; }
  if !v1_src_is(&op2, "192.168.0.1") { ok = false; }
  if op2.src_port != 56324 { ok = false; }
  return assert(ok, "v1 TCP4 pinned bytes, fields, consumed and offset parse");
}

// --------------------------------------------------
//  t2: v1 TCP6 parse and canonical re-render
// --------------------------------------------------

fn t2() -> TestResult {
  var ok = true;
  let line = bytes_of("PROXY TCP6 2001:DB8:0:0:0:0:0:1 ::2 1 65535\r\n");
  let op = v1_ok(line, 0);
  if op.family != 2 { ok = false; }
  if !v1_src_is(&op, "2001:DB8:0:0:0:0:0:1") { ok = false; }
  if !v1_dst_is(&op, "::2") { ok = false; }
  if op.src_port != 1 { ok = false; }
  if op.dst_port != 65535 { ok = false; }
  if op.consumed != 45 { ok = false; }
  let enc = enc_ok(proxy_v1_encode_tcp6(&bytes_of("2001:DB8:0:0:0:0:0:1"), &bytes_of("::2"), 1, 65535));
  if !bytes_equal(enc, bytes_of("PROXY TCP6 2001:db8::1 ::2 1 65535\r\n")) { ok = false; }
  let op2 = v1_ok(enc, 0);
  if !v1_src_is(&op2, "2001:db8::1") { ok = false; }
  if op2.consumed != 36 { ok = false; }
  return assert(ok, "v1 TCP6 parse and canonical re-render");
}

// --------------------------------------------------
//  t3: v1 UNKNOWN short, opaque tail, cap boundary
// --------------------------------------------------

fn t3() -> TestResult {
  var ok = true;
  let op = v1_ok(bytes_of("PROXY UNKNOWN\r\n"), 0);
  if op.family != 0 { ok = false; }
  if op.consumed != 15 { ok = false; }
  if op.opaque.len() != 0 { ok = false; }
  let op2 = v1_ok(bytes_of("PROXY UNKNOWN ffff::1 65535 65535\r\n"), 0);
  if op2.family != 0 { ok = false; }
  if !v1_opaque_is(&op2, "ffff::1 65535 65535") { ok = false; }
  let short = proxy_v1_encode_unknown();
  if !bytes_equal(short, bytes_of("PROXY UNKNOWN\r\n")) { ok = false; }
  let tail_enc = enc_ok(proxy_v1_encode_unknown_opaque(&bytes_of("abc def")));
  if !bytes_equal(tail_enc, bytes_of("PROXY UNKNOWN abc def\r\n")) { ok = false; }
  if !err_bytes_is(proxy_v1_encode_unknown_opaque(&hb("6162630d")), "proxy: bad opaque tail") { ok = false; }
  var parts = Vec[Vec[UInt8]].new();
  parts.push(bytes_of("PROXY UNKNOWN "));
  parts.push(rep(120, 91));
  parts.push(hb("0d0a"));
  let maxline = cat(&parts);
  if maxline.len() != 107 { ok = false; }
  let op3 = v1_ok(maxline, 0);
  if op3.family != 0 { ok = false; }
  if op3.consumed != 107 { ok = false; }
  if op3.opaque.len() != 91 { ok = false; }
  let over = enc_ok(proxy_v1_encode_unknown_opaque(&rep(120, 92)));
  if !err_bytes_is(proxy_v1_encode_unknown_opaque(&rep(120, 92)), "proxy: v1 line too long") { ok = false; }
  var parts2 = Vec[Vec[UInt8]].new();
  parts2.push(bytes_of("PROXY UNKNOWN "));
  parts2.push(rep(120, 92));
  parts2.push(hb("0d0a"));
  if !err_v1_is(proxy_parse_v1(&cat(&parts2), 0), "proxy: v1 line too long at 0") { ok = false; }
  if over.len() != 0 { ok = false; }
  return assert(ok, "v1 UNKNOWN short, opaque tail and the 107-byte cap");
}

// --------------------------------------------------
//  t4: v1 malformed lines (offset-bearing errors)
// --------------------------------------------------

fn t4() -> TestResult {
  var ok = true;
  if !err_v1_is(proxy_parse_v1(&bytes_of("PROXYX TCP4 1.2.3.4 5.6.7.8 1 2\r\n"), 0), "proxy: bad v1 prefix at 0") { ok = false; }
  if !err_v1_is(proxy_parse_v1(&bytes_of("PROXY TCP9 1.2.3.4 5.6.7.8 1 2\r\n"), 0), "proxy: bad v1 protocol at 6") { ok = false; }
  if !err_v1_is(proxy_parse_v1(&bytes_of("PROXY TCP4  1.2.3.4 5.6.7.8 1 2\r\n"), 0), "proxy: bad v1 fields at 11") { ok = false; }
  if !err_v1_is(proxy_parse_v1(&bytes_of("PROXY TCP4 1.2.3.4 5.6.7.8 1\r\n"), 0), "proxy: bad v1 fields at 11") { ok = false; }
  if !err_v1_is(proxy_parse_v1(&bytes_of("PROXY TCP4 010.0.0.1 5.6.7.8 1 2\r\n"), 0), "proxy: bad v1 address at 11") { ok = false; }
  if !err_v1_is(proxy_parse_v1(&bytes_of("PROXY TCP4 256.0.0.1 5.6.7.8 1 2\r\n"), 0), "proxy: bad v1 address at 11") { ok = false; }
  if !err_v1_is(proxy_parse_v1(&bytes_of("PROXY TCP4 1.2.3 5.6.7.8 1 2\r\n"), 0), "proxy: bad v1 address at 11") { ok = false; }
  if !err_v1_is(proxy_parse_v1(&bytes_of("PROXY TCP6 fe80::1%eth0 ::1 1 2\r\n"), 0), "proxy: bad v1 address at 11") { ok = false; }
  if !err_v1_is(proxy_parse_v1(&bytes_of("PROXY TCP6 1:2:3:4:5:6:7:8:9 ::1 1 2\r\n"), 0), "proxy: bad v1 address at 11") { ok = false; }
  if !err_v1_is(proxy_parse_v1(&bytes_of("PROXY TCP4 1.2.3.4 5.6.7.8 0123 2\r\n"), 0), "proxy: bad decimal at 27") { ok = false; }
  if !err_v1_is(proxy_parse_v1(&bytes_of("PROXY TCP4 1.2.3.4 5.6.7.8 1 2"), 0), "proxy: truncated header at 0") { ok = false; }
  if !err_v1_is(proxy_parse_v1(&bytes_of("PROXY TCP4 1.2.3.4 5.6.7.8 1 2\r\n"), -1), "proxy: negative offset at -1") { ok = false; }
  return assert(ok, "v1 malformed-line rejection with byte offsets");
}

// --------------------------------------------------
//  t5: v2 IPv4 TCP pinned bytes, encode round trip, summary
// --------------------------------------------------

fn t5() -> TestResult {
  var ok = true;
  let want = hb("0d0a0d0a000d0a515549540a2111000cc0a80001c0a8000b1f9001bb");
  let op = v2_ok(want, 0);
  if op.version != 2 { ok = false; }
  if op.command != 1 { ok = false; }
  if op.family != 1 { ok = false; }
  if op.protocol != 1 { ok = false; }
  if op.consumed != 28 { ok = false; }
  if op.src_port != 8080 { ok = false; }
  if op.dst_port != 443 { ok = false; }
  if op.tlvs.len() != 0 { ok = false; }
  if op.payload.len() != 12 { ok = false; }
  if !v2_hex_is(&op.src_addr, "c0a80001") { ok = false; }
  if !v2_hex_is(&op.dst_addr, "c0a8000b") { ok = false; }
  if op.tlvs_off != 28 { ok = false; }
  var none = Vec[UInt8].new();
  let enc = enc_ok(proxy_v2_encode_proxy_tcp4(&hb("c0a80001"), &hb("c0a8000b"), 8080, 443, &none));
  if !bytes_equal(enc, hb("0d0a0d0a000d0a515549540a2111000cc0a80001c0a8000b1f9001bb")) { ok = false; }
  let s = sum_ok(hb("0d0a0d0a000d0a515549540a2111000cc0a80001c0a8000b1f9001bb"), 0);
  if s.version != 2 { ok = false; }
  if s.command != 1 { ok = false; }
  if s.family != 1 { ok = false; }
  if s.protocol != 1 { ok = false; }
  if s.src_port != 8080 { ok = false; }
  if s.dst_port != 443 { ok = false; }
  if s.consumed != 28 { ok = false; }
  return assert(ok, "v2 IPv4/TCP pinned bytes, encode round trip and summary");
}

// --------------------------------------------------
//  t6: v2 IPv6 UDP parse/encode and block sizes
// --------------------------------------------------

fn t6() -> TestResult {
  var ok = true;
  let src_hex = "20010db8" + "0000" + "0000" + "0000" + "0000" + "0000" + "0001";
  let dst_hex = "20010db8" + "0000" + "0000" + "0000" + "0000" + "0000" + "0002";
  let hexline = "0d0a0d0a000d0a515549540a" + "21" + "22" + "0024" + src_hex + dst_hex + "3039" + "0043";
  let op = v2_ok(hb(hexline), 0);
  if op.family != 2 { ok = false; }
  if op.protocol != 2 { ok = false; }
  if op.consumed != 52 { ok = false; }
  if op.src_port != 12345 { ok = false; }
  if op.dst_port != 67 { ok = false; }
  if op.src_addr.len() != 16 { ok = false; }
  if !v2_hex_is(&op.src_addr, src_hex) { ok = false; }
  if !v2_hex_is(&op.dst_addr, dst_hex) { ok = false; }
  let s: Vec[UInt8] = op.src_addr;
  let d: Vec[UInt8] = op.dst_addr;
  var none = Vec[UInt8].new();
  let enc = enc_ok(proxy_v2_encode_proxy_udp6(&s, &d, 12345, 67, &none));
  if !bytes_equal(enc, hb(hexline)) { ok = false; }
  if proxy_v2_address_block_len(0) != 0 { ok = false; }
  if proxy_v2_address_block_len(1) != 12 { ok = false; }
  if proxy_v2_address_block_len(2) != 36 { ok = false; }
  if proxy_v2_address_block_len(3) != 216 { ok = false; }
  if proxy_v2_address_block_len(4) != -1 { ok = false; }
  if !err_bytes_is(proxy_v2_encode_proxy_udp6(&hb("c0a80001"), &d, 1, 2, &none), "proxy: bad ipv6 bytes") { ok = false; }
  return assert(ok, "v2 IPv6/UDP parse, encode round trip and address block sizes");
}

// --------------------------------------------------
//  t7: v2 UNIX stream (216-byte path block)
// --------------------------------------------------

fn t7() -> TestResult {
  var ok = true;
  let p1 = bytes_of("/run/xiom.sock");
  let p2 = bytes_of("/run/xiom2.sock");
  var none = Vec[UInt8].new();
  let enc = enc_ok(proxy_v2_encode_proxy_unix(&p1, &p2, &none));
  if enc.len() != 232 { ok = false; }
  if u16_at(enc, 14) != 216 { ok = false; }
  if ((enc[13] as Int) & 0xFF) != 0x31 { ok = false; }
  let op = v2_ok(enc, 0);
  if op.family != 3 { ok = false; }
  if op.protocol != 1 { ok = false; }
  if op.consumed != 232 { ok = false; }
  if op.unix_src.len() != 108 { ok = false; }
  if !unix_src_is(&op, "/run/xiom.sock") { ok = false; }
  if !unix_dst_is(&op, "/run/xiom2.sock") { ok = false; }
  if op.src_port != 0 { ok = false; }
  if op.src_addr.len() != 0 { ok = false; }
  if !err_bytes_is(proxy_v2_encode_proxy_unix(&rep(97, 109), &p2, &none), "proxy: unix path too long") { ok = false; }
  return assert(ok, "v2 UNIX/STREAM 216-byte path block and NUL padding");
}

// --------------------------------------------------
//  t8: v2 LOCAL and UNSPEC semantics
// --------------------------------------------------

fn t8() -> TestResult {
  var ok = true;
  let tlv = enc_ok(proxy_tlv_encode(4, bytes_of("pad")));
  let loc = enc_ok(proxy_v2_encode_local(&tlv));
  let op = v2_ok(loc, 0);
  if op.command != 0 { ok = false; }
  if !proxy_v2_is_local(op.command) { ok = false; }
  if op.family != 0 { ok = false; }
  if op.protocol != 0 { ok = false; }
  if op.tlvs.len() != 6 { ok = false; }
  if op.consumed != 22 { ok = false; }
  if op.tlvs_off != 16 { ok = false; }
  let uns = enc_ok(proxy_v2_encode_proxy_unspec(&tlv));
  let op2 = v2_ok(uns, 0);
  if op2.command != 1 { ok = false; }
  if op2.family != 0 { ok = false; }
  if op2.tlvs.len() != 6 { ok = false; }
  let short_body = hb("0102030405");
  let loc_short = enc_ok(proxy_v2_header(0, 1, 0, &short_body));
  let op3 = v2_ok(loc_short, 0);
  if op3.command != 0 { ok = false; }
  if op3.family != 1 { ok = false; }
  if op3.src_addr.len() != 0 { ok = false; }
  if op3.tlvs.len() != 0 { ok = false; }
  if op3.payload.len() != 5 { ok = false; }
  let prox_short = enc_ok(proxy_v2_header(1, 1, 0, &short_body));
  if !err_v2_is(proxy_parse_v2(&prox_short, 0), "proxy: bad address block at 14") { ok = false; }
  if !err_bytes_is(proxy_v2_header(2, 0, 0, &short_body), "proxy: bad command") { ok = false; }
  if !err_bytes_is(proxy_v2_header(0, 4, 0, &short_body), "proxy: bad family") { ok = false; }
  if !err_bytes_is(proxy_v2_header(0, 0, 3, &short_body), "proxy: bad protocol") { ok = false; }
  return assert(ok, "v2 LOCAL/UNSPEC semantics and short address blocks");
}

// --------------------------------------------------
//  t9: v2 signature/version/command/family/protocol rejection
// --------------------------------------------------

fn t9() -> TestResult {
  var ok = true;
  let base = hb("0d0a0d0a000d0a515549540a2111000cc0a80001c0a8000b1f9001bb");
  if !err_v2_is(proxy_parse_v2(&with_byte_at(base, 11, 11), 0), "proxy: bad signature at 11") { ok = false; }
  if !err_v2_is(proxy_parse_v2(&with_byte_at(base, 12, 0x31), 0), "proxy: bad version at 12") { ok = false; }
  if !err_v2_is(proxy_parse_v2(&with_byte_at(base, 12, 0x22), 0), "proxy: bad command at 12") { ok = false; }
  if !err_v2_is(proxy_parse_v2(&with_byte_at(base, 13, 0x41), 0), "proxy: bad family at 13") { ok = false; }
  if !err_v2_is(proxy_parse_v2(&with_byte_at(base, 13, 0x13), 0), "proxy: bad protocol at 13") { ok = false; }
  if proxy_detect_version(&with_byte_at(base, 11, 11), 0) != 0 { ok = false; }
  if proxy_detect_version(&base, 0) != 2 { ok = false; }
  if !err_v2_is(proxy_parse_v2(&hb("0d0a0d0a000d0a515549540a21"), 0), "proxy: truncated header at 0") { ok = false; }
  if !err_v2_is(proxy_parse_v2(&base, -5), "proxy: negative offset at -5") { ok = false; }
  return assert(ok, "v2 signature/version/command/family/protocol rejection");
}

// --------------------------------------------------
//  t10: v2 length and truncation handling, framing helpers
// --------------------------------------------------

fn t10() -> TestResult {
  var ok = true;
  let base = hb("0d0a0d0a000d0a515549540a2111000cc0a80001c0a8000b1f9001bb");
  if !err_v2_is(proxy_parse_v2(&span_copy(base, 0, 20), 0), "proxy: truncated header at 0") { ok = false; }
  if !err_v2_is(proxy_parse_v2(&with_byte_at(base, 15, 0xFF), 0), "proxy: truncated header at 0") { ok = false; }
  let prefix16 = span_copy(base, 0, 16);
  let hl = pair_ok(proxy_header_len(&prefix16, 0));
  let hv: Int = hl.0;
  let hc: Int = hl.1;
  if hv != 2 { ok = false; }
  if hc != 28 { ok = false; }
  if !err_pair_is(proxy_header_len(&with_byte_at(prefix16, 12, 0x32), 0), "proxy: bad version at 12") { ok = false; }
  if !err_pair_is(proxy_header_len(&bytes_of("GET / HTTP/1.1\r\n"), 0), "proxy: unknown version at 0") { ok = false; }
  if !err_pair_is(proxy_header_len(&hb("0d0a"), 0), "proxy: truncated header at 0") { ok = false; }
  if !err_pair_is(proxy_header_len(&bytes_of(""), 0), "proxy: truncated header at 0") { ok = false; }
  if !err_pair_is(proxy_header_len(&bytes_of("PROXY TCP4 1.2.3.4 5.6.7.8 1 2\r\n"), -1), "proxy: negative offset at -1") { ok = false; }
  if !err_pair_is(proxy_header_len(&bytes_of("PROXY TCP4 1.2.3.4 5.6.7.8 1 2"), 0), "proxy: truncated header at 0") { ok = false; }
  var framed = Vec[UInt8].new();
  addb(&mut framed, &base);
  addb(&mut framed, &bytes_of("PAYLOAD"));
  let ps = pair_ok(proxy_payload_span(&framed, 0, 28));
  let ps0: Int = ps.0;
  let ps1: Int = ps.1;
  if ps0 != 28 { ok = false; }
  if ps1 != 35 { ok = false; }
  if !err_pair_is(proxy_payload_span(&framed, 0, 36), "proxy: bad header size at 0") { ok = false; }
  if !err_pair_is(proxy_payload_span(&framed, -1, 28), "proxy: bad header size at -1") { ok = false; }
  return assert(ok, "v2 length/truncation errors, header_len and payload span");
}

// --------------------------------------------------
//  t11: TLV encoders and fixed-width readers
// --------------------------------------------------

fn t11() -> TestResult {
  var ok = true;
  if !bytes_equal(enc_ok(proxy_tlv_encode_u16(4, 4242)), hb("0400021092")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_tlv_encode_u32(3, 2864434397)), hb("030004aabbccdd")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_tlv_encode_u64(234, 16909060, 84281096)), hb("ea00080102030405060708")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_tlv_encode_empty(4)), hb("040000")) { ok = false; }
  if int_ok(proxy_tlv_read_u16(&hb("1092"))) != 4242 { ok = false; }
  if int_ok(proxy_tlv_read_u32(&hb("aabbccdd"))) != 2864434397 { ok = false; }
  let up = pair_ok(proxy_tlv_read_u64_parts(&hb("0102030405060708")));
  let hi: Int = up.0;
  let lo: Int = up.1;
  if hi != 16909060 { ok = false; }
  if lo != 84281096 { ok = false; }
  if int_ok(proxy_tlv_read_u64(&hb("0102030405060708"))) != hi * 4294967296 + lo { ok = false; }
  if !err_int_is(proxy_tlv_read_u64(&hb("ffffffffffffffff")), "proxy: u64 out of range") { ok = false; }
  if !err_int_is(proxy_tlv_read_u16(&hb("10")), "proxy: bad TLV value length") { ok = false; }
  if !err_int_is(proxy_tlv_read_u32(&hb("0a0b")), "proxy: bad TLV value length") { ok = false; }
  if !err_pair_is(proxy_tlv_read_u64_parts(&hb("0102")), "proxy: bad TLV value length") { ok = false; }
  if !err_bytes_is(proxy_tlv_encode(-1, &hb("00")), "proxy: bad TLV type") { ok = false; }
  if !err_bytes_is(proxy_tlv_encode(300, &hb("00")), "proxy: bad TLV type") { ok = false; }
  if !err_bytes_is(proxy_tlv_encode_u32(3, -1), "proxy: bad TLV value") { ok = false; }
  if !err_bytes_is(proxy_tlv_encode_u16(4, 65536), "proxy: bad TLV value") { ok = false; }
  if !err_bytes_is(proxy_tlv_encode_u64(234, -1, 0), "proxy: bad TLV value") { ok = false; }
  if proxy_tlv_expected_width(3) != 4 { ok = false; }
  if proxy_tlv_expected_width(32) != 0 { ok = false; }
  if proxy_tlv_expected_width(48) != 0 { ok = false; }
  if proxy_tlv_expected_width(234) != 0 { ok = false; }
  if proxy_tlv_expected_width(1) != 0 { ok = false; }
  if !str_eq(proxy_tlv_type_name(1), "ALPN") { ok = false; }
  if !str_eq(proxy_tlv_type_name(2), "AUTHORITY") { ok = false; }
  if !str_eq(proxy_tlv_type_name(3), "CRC32C") { ok = false; }
  if !str_eq(proxy_tlv_type_name(4), "NOOP") { ok = false; }
  if !str_eq(proxy_tlv_type_name(5), "UNIQUE_ID") { ok = false; }
  if !str_eq(proxy_tlv_type_name(32), "SSL") { ok = false; }
  if !str_eq(proxy_tlv_type_name(48), "NETNS") { ok = false; }
  if !str_eq(proxy_tlv_type_name(234), "AWS") { ok = false; }
  if !str_eq(proxy_tlv_type_name(170), "UNKNOWN") { ok = false; }
  return assert(ok, "TLV encoders, fixed-width readers, widths and type names");
}

// --------------------------------------------------
//  t12: TLV stream walking, unknown preservation, counts
// --------------------------------------------------

fn t12() -> TestResult {
  var ok = true;
  var empty_sub = Vec[UInt8].new();
  var aws_sub = Vec[Vec[UInt8]].new();
  aws_sub.push(enc_ok(proxy_tlv_encode(1, bytes_of("vpce-0abc123"))));
  aws_sub.push(enc_ok(proxy_tlv_encode(2, bytes_of("vpc-0def456"))));
  let aws_body = cat(&aws_sub);
  var parts = Vec[Vec[UInt8]].new();
  parts.push(enc_ok(proxy_tlv_encode(1, bytes_of("h2"))));
  parts.push(enc_ok(proxy_tlv_encode(2, bytes_of("example.com"))));
  parts.push(enc_ok(proxy_tlv_encode_u32(3, 123456789)));
  parts.push(enc_ok(proxy_tlv_encode(4, bytes_of("pad"))));
  parts.push(enc_ok(proxy_tlv_encode(5, bytes_of("conn-42"))));
  parts.push(enc_ok(proxy_tlv_encode_netns(&bytes_of("/run/netns/demo"))));
  parts.push(enc_ok(proxy_ssl_encode(1, 0, &empty_sub)));
  parts.push(enc_ok(proxy_tlv_encode(234, &aws_body)));
  parts.push(enc_ok(proxy_tlv_encode(170, hb("0102"))));
  let body = cat(&parts);
  let enc = enc_ok(proxy_v2_encode_proxy_tcp4(&hb("c0a80001"), &hb("c0a8000b"), 1, 2, &body));
  let op = v2_ok(enc, 0);
  let tv: Vec[UInt8] = op.tlvs;
  if tv.len() != body.len() { ok = false; }
  if proxy_tlv_count(&tv) != 9 { ok = false; }
  if op.tlvs_off != 28 { ok = false; }
  if proxy_tlv_first(&tv, 234) < 0 { ok = false; }
  if proxy_tlv_first(&tv, 99) != -1 { ok = false; }
  let c0 = cursor_ok(proxy_tlv_next(&tv, 0));
  if c0.tlv_type != 1 { ok = false; }
  let v0 = span_copy(tv, c0.value_start, c0.value_end);
  if !bytes_equal(v0, bytes_of("h2")) { ok = false; }
  let c1 = cursor_ok(proxy_tlv_next(&tv, c0.next));
  if c1.tlv_type != 2 { ok = false; }
  let v1 = span_copy(tv, c1.value_start, c1.value_end);
  if !bytes_equal(v1, bytes_of("example.com")) { ok = false; }
  let c2 = cursor_ok(proxy_tlv_next(&tv, c1.next));
  if c2.tlv_type != 3 { ok = false; }
  if int_ok(proxy_tlv_read_u32(&span_copy(tv, c2.value_start, c2.value_end))) != 123456789 { ok = false; }
  let c3 = cursor_ok(proxy_tlv_next(&tv, c2.next));
  if c3.tlv_type != 4 { ok = false; }
  if c3.value_end - c3.value_start != 3 { ok = false; }
  let c4 = cursor_ok(proxy_tlv_next(&tv, c3.next));
  if c4.tlv_type != 5 { ok = false; }
  let v4 = span_copy(tv, c4.value_start, c4.value_end);
  if !bytes_equal(v4, bytes_of("conn-42")) { ok = false; }
  let c5 = cursor_ok(proxy_tlv_next(&tv, c4.next));
  if c5.tlv_type != 48 { ok = false; }
  let v5 = span_copy(tv, c5.value_start, c5.value_end);
  if !bytes_equal(enc_ok(proxy_tlv_netns_path(&v5)), bytes_of("/run/netns/demo")) { ok = false; }
  let c6 = cursor_ok(proxy_tlv_next(&tv, c5.next));
  if c6.tlv_type != 32 { ok = false; }
  let v6 = span_copy(tv, c6.value_start, c6.value_end);
  if int_ok(proxy_ssl_client_flags(&v6)) != 1 { ok = false; }
  if int_ok(proxy_ssl_verify(&v6)) != 0 { ok = false; }
  let c7 = cursor_ok(proxy_tlv_next(&tv, c6.next));
  if c7.tlv_type != 234 { ok = false; }
  let v7 = span_copy(tv, c7.value_start, c7.value_end);
  if !bytes_equal(enc_ok(proxy_aws_vpc_endpoint_id(&v7)), bytes_of("vpce-0abc123")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_aws_vpc_id(&v7)), bytes_of("vpc-0def456")) { ok = false; }
  let c8 = cursor_ok(proxy_tlv_next(&tv, c7.next));
  if c8.tlv_type != 170 { ok = false; }
  if !bytes_equal(span_copy(tv, c8.value_start, c8.value_end), hb("0102")) { ok = false; }
  if c8.next != tv.len() { ok = false; }
  return assert(ok, "TLV stream walking, canonical types and unknown preservation");
}

// --------------------------------------------------
//  t13: nested SSL TLV
// --------------------------------------------------

fn t13() -> TestResult {
  var ok = true;
  var sub = Vec[Vec[UInt8]].new();
  sub.push(enc_ok(proxy_tlv_encode(33, bytes_of("TLSv1.3"))));
  sub.push(enc_ok(proxy_tlv_encode(34, bytes_of("client.example.com"))));
  sub.push(enc_ok(proxy_tlv_encode(35, bytes_of("TLS_AES_128_GCM_SHA256"))));
  sub.push(enc_ok(proxy_tlv_encode(36, bytes_of("SHA256"))));
  sub.push(enc_ok(proxy_tlv_encode(37, bytes_of("RSA2048"))));
  let subbody = cat(&sub);
  let ssl = enc_ok(proxy_ssl_encode(1, 0, &subbody));
  let c0 = cursor_ok(proxy_tlv_next(&ssl, 0));
  if c0.tlv_type != 32 { ok = false; }
  let val = span_copy(ssl, c0.value_start, c0.value_end);
  if int_ok(proxy_ssl_client_flags(&val)) != 1 { ok = false; }
  if int_ok(proxy_ssl_verify(&val)) != 0 { ok = false; }
  let sb = pair_ok(proxy_ssl_sub_tlvs(&val));
  let sb0: Int = sb.0;
  let sb1: Int = sb.1;
  if sb0 != 5 { ok = false; }
  if sb1 != val.len() { ok = false; }
  let nsub = span_copy(val, 5, val.len());
  if proxy_tlv_count(&nsub) != 5 { ok = false; }
  let n0 = cursor_ok(proxy_tlv_next(&nsub, 0));
  if n0.tlv_type != 33 { ok = false; }
  if !bytes_equal(span_copy(nsub, n0.value_start, n0.value_end), bytes_of("TLSv1.3")) { ok = false; }
  let n1 = cursor_ok(proxy_tlv_next(&nsub, n0.next));
  if n1.tlv_type != 34 { ok = false; }
  if !bytes_equal(span_copy(nsub, n1.value_start, n1.value_end), bytes_of("client.example.com")) { ok = false; }
  let n2 = cursor_ok(proxy_tlv_next(&nsub, n1.next));
  if n2.tlv_type != 35 { ok = false; }
  if !bytes_equal(span_copy(nsub, n2.value_start, n2.value_end), bytes_of("TLS_AES_128_GCM_SHA256")) { ok = false; }
  let n3 = cursor_ok(proxy_tlv_next(&nsub, n2.next));
  if n3.tlv_type != 36 { ok = false; }
  if !bytes_equal(span_copy(nsub, n3.value_start, n3.value_end), bytes_of("SHA256")) { ok = false; }
  let n4 = cursor_ok(proxy_tlv_next(&nsub, n3.next));
  if n4.tlv_type != 37 { ok = false; }
  if !bytes_equal(span_copy(nsub, n4.value_start, n4.value_end), bytes_of("RSA2048")) { ok = false; }
  if n4.next != nsub.len() { ok = false; }
  if !str_eq(proxy_ssl_subtype_name(33), "VERSION") { ok = false; }
  if !str_eq(proxy_ssl_subtype_name(34), "CN") { ok = false; }
  if !str_eq(proxy_ssl_subtype_name(35), "CIPHER") { ok = false; }
  if !str_eq(proxy_ssl_subtype_name(36), "SIG_ALG") { ok = false; }
  if !str_eq(proxy_ssl_subtype_name(37), "KEY_ALG") { ok = false; }
  if !str_eq(proxy_ssl_subtype_name(99), "UNKNOWN") { ok = false; }
  if !err_int_is(proxy_ssl_verify(&hb("01")), "proxy: bad ssl tlv") { ok = false; }
  if !err_pair_is(proxy_ssl_sub_tlvs(&hb("01020304")), "proxy: bad ssl tlv") { ok = false; }
  let op = v2_ok(enc_ok(proxy_v2_encode_proxy_tcp4(&hb("c0a80001"), &hb("c0a8000b"), 1, 2, &ssl)), 0);
  let otv: Vec[UInt8] = op.tlvs;
  if proxy_tlv_count(&otv) != 1 { ok = false; }
  return assert(ok, "SSL TLV 0x20 with canonical sub-TLV stream");
}

// --------------------------------------------------
//  t14: CRC32C known vector and header verification
// --------------------------------------------------

fn t14() -> TestResult {
  var ok = true;
  if int_ok(proxy_crc32c(&bytes_of("123456789"), 0, 9)) != 3808858755 { ok = false; }
  if !err_int_is(proxy_crc32c(&bytes_of("abc"), 0, 4), "proxy: bad crc range") { ok = false; }
  if !err_int_is(proxy_crc32c(&bytes_of("abc"), 2, 1), "proxy: bad crc range") { ok = false; }
  if !err_int_is(proxy_crc32c(&bytes_of("abc"), -1, 2), "proxy: bad crc range") { ok = false; }
  let crc_tlv = enc_ok(proxy_tlv_encode_u32(3, 0));
  let header = enc_ok(proxy_v2_encode_proxy_tcp4(&hb("c0a80001"), &hb("c0a8000b"), 8080, 443, &crc_tlv));
  let op = v2_ok(header, 0);
  let tv: Vec[UInt8] = op.tlvs;
  let coff = proxy_tlv_first(&tv, 3);
  if coff < 0 { ok = false; }
  let cur = cursor_ok(proxy_tlv_next(&tv, coff));
  let value_off = op.tlvs_off + cur.value_start;
  let crc = int_ok(proxy_v2_crc32c(&header, value_off));
  if crc == 0 { ok = false; }
  let patched = with_u32_at(header, value_off, crc);
  if !bool_ok(proxy_v2_verify_crc32c(&patched)) { ok = false; }
  if bool_ok(proxy_v2_verify_crc32c(&header)) { ok = false; }
  let tampered = with_byte_at(patched, 20, 0x55);
  if bool_ok(proxy_v2_verify_crc32c(&tampered)) { ok = false; }
  let no_crc = enc_ok(proxy_v2_encode_proxy_tcp4(&hb("c0a80001"), &hb("c0a8000b"), 1, 2, &Vec[UInt8].new()));
  if bool_ok(proxy_v2_verify_crc32c(&no_crc)) { ok = false; }
  return assert(ok, "CRC32C known vector and v2 header verification");
}

// --------------------------------------------------
//  t15: detection, header_len, parse_one dispatch
// --------------------------------------------------

fn t15() -> TestResult {
  var ok = true;
  if proxy_detect_version(&bytes_of("PROXY TCP4 1.2.3.4 5.6.7.8 1 2\r\n"), 0) != 1 { ok = false; }
  if proxy_detect_version(&hb("0d0a0d0a000d0a515549540a21"), 0) != 2 { ok = false; }
  if proxy_detect_version(&bytes_of("GET / HTTP/1.1\r\n"), 0) != 0 { ok = false; }
  if proxy_detect_version(&hb("0d0a0d0a"), 0) != 0 { ok = false; }
  if proxy_detect_version(&bytes_of(""), 0) != 0 { ok = false; }
  if proxy_detect_version(&hb("0d0a0d0a000d0a515549540a21"), -1) != 0 { ok = false; }
  let v1line = bytes_of("PROXY TCP4 192.168.0.1 192.168.0.11 56324 443\r\n");
  let hl1 = pair_ok(proxy_header_len(&v1line, 0));
  let hl1v: Int = hl1.0;
  let hl1c: Int = hl1.1;
  if hl1v != 1 { ok = false; }
  if hl1c != 47 { ok = false; }
  let s1 = sum_ok(v1line, 0);
  if s1.version != 1 { ok = false; }
  if s1.command != 1 { ok = false; }
  if s1.family != 1 { ok = false; }
  if s1.protocol != 1 { ok = false; }
  if s1.consumed != 47 { ok = false; }
  let s2 = sum_ok(bytes_of("PROXY UNKNOWN\r\n"), 0);
  if s2.version != 1 { ok = false; }
  if s2.family != 0 { ok = false; }
  if s2.protocol != 0 { ok = false; }
  let loc = enc_ok(proxy_v2_encode_local(&Vec[UInt8].new()));
  let s3 = sum_ok(loc, 0);
  if s3.version != 2 { ok = false; }
  if s3.command != 0 { ok = false; }
  if !err_sum_is(proxy_parse_one(&bytes_of("GET / HTTP/1.1\r\n"), 0), "proxy: unknown version at 0") { ok = false; }
  if !err_sum_is(proxy_parse_one(&hb("0d0a0d0a000d0a515549540a3111000c000000000000000000000000"), 0), "proxy: bad version at 12") { ok = false; }
  return assert(ok, "version detection, header_len and parse_one dispatch");
}

// --------------------------------------------------
//  t16: IPv4/IPv6 text codecs
// --------------------------------------------------

fn t16() -> TestResult {
  var ok = true;
  if !bytes_equal(enc_ok(proxy_ipv4_parse(&bytes_of("192.168.0.1"))), hb("c0a80001")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_ipv4_render(&hb("c0a80001"))), bytes_of("192.168.0.1")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_ipv4_render(&enc_ok(proxy_ipv4_parse(&bytes_of("0.0.0.0"))))), bytes_of("0.0.0.0")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_ipv4_render(&enc_ok(proxy_ipv4_parse(&bytes_of("255.255.255.255"))))), bytes_of("255.255.255.255")) { ok = false; }
  if !err_bytes_is(proxy_ipv4_parse(&bytes_of("1.2.3")), "proxy: bad ipv4") { ok = false; }
  if !err_bytes_is(proxy_ipv4_parse(&bytes_of("256.1.1.1")), "proxy: bad ipv4") { ok = false; }
  if !err_bytes_is(proxy_ipv4_parse(&bytes_of("01.2.3.4")), "proxy: bad ipv4") { ok = false; }
  if !err_bytes_is(proxy_ipv4_parse(&bytes_of("1.2.3.4.5")), "proxy: bad ipv4") { ok = false; }
  if !err_bytes_is(proxy_ipv4_parse(&bytes_of("")), "proxy: bad ipv4") { ok = false; }
  if !err_bytes_is(proxy_ipv4_parse(&bytes_of("a.b.c.d")), "proxy: bad ipv4") { ok = false; }
  if !err_bytes_is(proxy_ipv4_render(&hb("0102")), "proxy: bad ipv4 bytes") { ok = false; }
  if !bytes_equal(enc_ok(proxy_ipv6_render(&enc_ok(proxy_ipv6_parse(&bytes_of("::"))))), bytes_of("::")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_ipv6_render(&enc_ok(proxy_ipv6_parse(&bytes_of("::1"))))), bytes_of("::1")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_ipv6_render(&enc_ok(proxy_ipv6_parse(&bytes_of("1::"))))), bytes_of("1::")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_ipv6_render(&enc_ok(proxy_ipv6_parse(&bytes_of("2001:0db8:0000:0000:0000:0000:0000:0001"))))), bytes_of("2001:db8::1")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_ipv6_render(&enc_ok(proxy_ipv6_parse(&bytes_of("1:0:0:2:0:0:0:3"))))), bytes_of("1:0:0:2::3")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_ipv6_render(&enc_ok(proxy_ipv6_parse(&bytes_of("::FFFF:1.2.3.4"))))), Vec[UInt8].new()) { ok = false; }
  if !err_bytes_is(proxy_ipv6_parse(&bytes_of("fe80::1%eth0")), "proxy: bad ipv6") { ok = false; }
  if !err_bytes_is(proxy_ipv6_parse(&bytes_of("1:2:3:4:5:6:7:8:9")), "proxy: bad ipv6") { ok = false; }
  if !err_bytes_is(proxy_ipv6_parse(&bytes_of("1::2::3")), "proxy: bad ipv6") { ok = false; }
  if !err_bytes_is(proxy_ipv6_parse(&bytes_of("1:2:3:4:5:6:7")), "proxy: bad ipv6") { ok = false; }
  if !err_bytes_is(proxy_ipv6_parse(&bytes_of("1:2:3:4:5:6:7:8::")), "proxy: bad ipv6") { ok = false; }
  if !err_bytes_is(proxy_ipv6_parse(&bytes_of(":::")), "proxy: bad ipv6") { ok = false; }
  if !err_bytes_is(proxy_ipv6_render(&hb("0102")), "proxy: bad ipv6 bytes") { ok = false; }
  return assert(ok, "IPv4/IPv6 text parse and canonical render");
}

// --------------------------------------------------
//  t17: protocol constants
// --------------------------------------------------

fn t17() -> TestResult {
  var ok = true;
  if proxy_v1_max_line() != 107 { ok = false; }
  if proxy_v2_fixed_len() != 16 { ok = false; }
  if proxy_v2_max_len() != 65535 { ok = false; }
  if proxy_v2_recommended_max() != 536 { ok = false; }
  if !bytes_equal(proxy_magic_v2(), hb("0d0a0d0a000d0a515549540a")) { ok = false; }
  if !bytes_equal(proxy_v1_prefix(), bytes_of("PROXY ")) { ok = false; }
  if !str_eq(proxy_version_name(1), "V1") { ok = false; }
  if !str_eq(proxy_version_name(2), "V2") { ok = false; }
  if !str_eq(proxy_version_name(9), "UNKNOWN") { ok = false; }
  if !str_eq(proxy_command_name(0), "LOCAL") { ok = false; }
  if !str_eq(proxy_command_name(1), "PROXY") { ok = false; }
  if !str_eq(proxy_family_name(0), "UNSPEC") { ok = false; }
  if !str_eq(proxy_family_name(1), "INET") { ok = false; }
  if !str_eq(proxy_family_name(2), "INET6") { ok = false; }
  if !str_eq(proxy_family_name(3), "UNIX") { ok = false; }
  if !str_eq(proxy_family_name(9), "UNKNOWN") { ok = false; }
  if !str_eq(proxy_protocol_name(0), "UNSPEC") { ok = false; }
  if !str_eq(proxy_protocol_name(1), "STREAM") { ok = false; }
  if !str_eq(proxy_protocol_name(2), "DGRAM") { ok = false; }
  if !str_eq(proxy_v1_family_name(0), "UNKNOWN") { ok = false; }
  if !str_eq(proxy_v1_family_name(1), "TCP4") { ok = false; }
  if !str_eq(proxy_v1_family_name(2), "TCP6") { ok = false; }
  if proxy_v2_is_local(0) != true { ok = false; }
  if proxy_v2_is_local(1) != false { ok = false; }
  return assert(ok, "protocol constants and name tables");
}

// --------------------------------------------------
//  t18: TLV walk error cases
// --------------------------------------------------

fn t18() -> TestResult {
  var ok = true;
  if !err_tlv_is(proxy_tlv_next(&hb("01"), 0), "proxy: truncated TLV at 0") { ok = false; }
  if !err_tlv_is(proxy_tlv_next(&hb("01000561"), 0), "proxy: TLV length overrun at 0") { ok = false; }
  if !err_tlv_is(proxy_tlv_next(&hb("0102"), -1), "proxy: bad TLV at -1") { ok = false; }
  if !err_tlv_is(proxy_tlv_next(&hb("0102"), 5), "proxy: bad TLV at 5") { ok = false; }
  if !err_tlv_is(proxy_tlv_next_in(&hb("01000561"), 0, 4), "proxy: TLV length overrun at 0") { ok = false; }
  if !err_tlv_is(proxy_tlv_next_in(&hb("01000561"), 1, 4), "proxy: TLV length overrun at 1") { ok = false; }
  if !err_tlv_is(proxy_tlv_next_in(&hb("0100"), 0, 99), "proxy: bad TLV at 0") { ok = false; }
  if proxy_tlv_count(&hb("0100")) != 0 { ok = false; }
  if proxy_tlv_count(&hb("04000001000561")) != 1 { ok = false; }
  if proxy_tlv_first(&hb("04000001000561"), 1) != -1 { ok = false; }
  if proxy_tlv_first(&hb("04000001000561"), 4) != 0 { ok = false; }
  return assert(ok, "TLV walk error cases");
}

// --------------------------------------------------
//  t19: NETNS TLV (0x30, NUL-terminated path)
// --------------------------------------------------

fn t19() -> TestResult {
  var ok = true;
  let ns = enc_ok(proxy_tlv_encode_netns(&bytes_of("/run/netns/demo")));
  if !bytes_equal(ns, hb("3000102f72756e2f6e65746e732f64656d6f00")) { ok = false; }
  let c = cursor_ok(proxy_tlv_next(&ns, 0));
  if c.tlv_type != 48 { ok = false; }
  if !str_eq(proxy_tlv_type_name(c.tlv_type), "NETNS") { ok = false; }
  let val = span_copy(ns, c.value_start, c.value_end);
  if !bytes_equal(enc_ok(proxy_tlv_netns_path(&val)), bytes_of("/run/netns/demo")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_tlv_encode_netns(&bytes_of(""))), hb("30000100")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_tlv_netns_path(&hb("00"))), Vec[UInt8].new()) { ok = false; }
  if !err_bytes_is(proxy_tlv_netns_path(&hb("6162")), "proxy: bad netns") { ok = false; }
  if !err_bytes_is(proxy_tlv_netns_path(&Vec[UInt8].new()), "proxy: bad netns") { ok = false; }
  return assert(ok, "NETNS TLV 0x30 NUL-terminated path encode/decode");
}

// --------------------------------------------------
//  t20: AWS TLV (0xEA, sub-TLV stream)
// --------------------------------------------------

fn t20() -> TestResult {
  var ok = true;
  var sub = Vec[Vec[UInt8]].new();
  sub.push(enc_ok(proxy_tlv_encode(1, bytes_of("vpce-0abc123"))));
  sub.push(enc_ok(proxy_tlv_encode(2, bytes_of("vpc-0def456"))));
  sub.push(enc_ok(proxy_tlv_encode(127, hb("dead"))));
  let subbody = cat(&sub);
  let aws = enc_ok(proxy_tlv_encode(234, &subbody));
  let c = cursor_ok(proxy_tlv_next(&aws, 0));
  if c.tlv_type != 234 { ok = false; }
  if !str_eq(proxy_tlv_type_name(c.tlv_type), "AWS") { ok = false; }
  let val = span_copy(aws, c.value_start, c.value_end);
  if proxy_tlv_count(&val) != 3 { ok = false; }
  if !bytes_equal(enc_ok(proxy_aws_vpc_endpoint_id(&val)), bytes_of("vpce-0abc123")) { ok = false; }
  if !bytes_equal(enc_ok(proxy_aws_vpc_id(&val)), bytes_of("vpc-0def456")) { ok = false; }
  let u0 = cursor_ok(proxy_tlv_next(&val, 0));
  if u0.tlv_type != 1 { ok = false; }
  let u1 = cursor_ok(proxy_tlv_next(&val, u0.next));
  if u1.tlv_type != 2 { ok = false; }
  let u2 = cursor_ok(proxy_tlv_next(&val, u1.next));
  if u2.tlv_type != 127 { ok = false; }
  if !bytes_equal(span_copy(val, u2.value_start, u2.value_end), hb("dead")) { ok = false; }
  if u2.next != val.len() { ok = false; }
  if !str_eq(proxy_aws_subtype_name(1), "VPC_ENDPOINT_ID") { ok = false; }
  if !str_eq(proxy_aws_subtype_name(2), "VPC_ID") { ok = false; }
  if !str_eq(proxy_aws_subtype_name(127), "UNKNOWN") { ok = false; }
  if !err_bytes_is(proxy_aws_vpc_endpoint_id(&hb("040000")), "proxy: aws subtype missing") { ok = false; }
  if !err_bytes_is(proxy_aws_value(&Vec[UInt8].new(), 1), "proxy: aws subtype missing") { ok = false; }
  if !err_bytes_is(proxy_aws_vpc_endpoint_id(&hb("01")), "proxy: truncated TLV at 0") { ok = false; }
  return assert(ok, "AWS TLV 0xEA sub-TLV stream, subtype decoders and raw preservation");
}

fn main() -> Int {
  io.println("=== xiom.proxy conformance tests ===");
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
    io.println("xiom.proxy: all tests passed");
  } else {
    io.println("xiom.proxy: tests failed");
  }
  return failed;
}
