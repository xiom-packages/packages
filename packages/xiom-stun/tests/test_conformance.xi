// XIOM -- xiom.stun conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.stun codec against RFC 5389 and the
// RFC 5769 sample messages.
//
// The first four fixtures are the RFC 5769 sample messages verbatim,
// including their nonzero padding bytes (spaces in the ICE vectors, zeroes
// in the long-term-credentials vector); the remaining messages are
// assembled by hand in hex. Every error string is compared through
// xiom.string.compare.str_compare (BUG 17: `==` on a Str read from a Vec
// lowers to a pointer comparison) and every Vec element is read into a
// typed local first.

module stun_tests
use xiom.io; use xiom.test;
use xiom.stun;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers
// --------------------------------------------------

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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Result inspectors
// --------------------------------------------------

fn err_msg_is(r: Result[StunMessage, Str], want: Str) -> Bool {
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

fn err_addr_is(r: Result[StunAddress, Str], want: Str) -> Bool {
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

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn bytes_is(r: Result[Vec[UInt8], Str], want: Vec[UInt8]) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  return bytes_equal(v, want);
}

fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn str_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return str_eq(v, want);
}

fn addr_is(r: Result[StunAddress, Str], family: Int, port: Int, want: Vec[UInt8]) -> Bool {
  if !r.is_ok {
    return false;
  }
  let a: StunAddress = r.value;
  if a.family != family {
    return false;
  }
  if a.port != port {
    return false;
  }
  let ab: Vec[UInt8] = a.address;
  return bytes_equal(ab, want);
}

fn value_is(data: &Vec[UInt8], m: &StunMessage, i: Int, want: Vec[UInt8]) -> Bool {
  let r = stun_attr_value(data, m, i);
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  return bytes_equal(v, want);
}

// Value bytes of attribute `i`, or an empty vector on error (callers only
// use it after a successful parse and a checked index).
fn value_at(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Vec[UInt8] {
  let r = stun_attr_value(data, m, i);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

// One-attribute Binding request carrying `value` as an attribute of type
// `atype`; an empty vector when the (always valid) build fails.
fn msg_with(atype: Int, value: Vec[UInt8]) -> Vec[UInt8] {
  let tid = hb("000102030405060708090a0b");
  var types = Vec[Int].new();
  types.push(atype);
  var values = Vec[Vec[UInt8]].new();
  values.push(value);
  let br = stun_build(STUN_METHOD_BINDING, &tid, &types, &values);
  match br {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let req = hb("000100582112a442b7e7a701bc34d686fa87dfae802200105354554e207465737420636c69656e74002400046e0001ff80290008932ff9b151263b36000600096576746a3a68367659202020000800149aeaa70cbfd8cb56781ef2b5b2d3f249c1b571a280280004e57a3bcf");
  let pr = stun_parse(&req);
  if !pr.is_ok { return assert(false, "RFC 5769 sample request must parse"); }
  let m: StunMessage = pr.value;
  var ok = m.msg_type == 1;
  if m.method != STUN_METHOD_BINDING { ok = false; }
  if m.msg_class != STUN_CLASS_REQUEST { ok = false; }
  if m.message_length != 88 { ok = false; }
  if m.magic_cookie != STUN_MAGIC_COOKIE { ok = false; }
  let tid: Vec[UInt8] = m.transaction_id;
  if !bytes_equal(tid, hb("b7e7a701bc34d686fa87dfae")) { ok = false; }
  if stun_attr_count(&m) != 6 { ok = false; }
  if stun_attr_type(&m, 0) != STUN_ATTR_SOFTWARE { ok = false; }
  if stun_attr_type(&m, 1) != 36 { ok = false; }
  if stun_attr_type(&m, 2) != 32809 { ok = false; }
  if stun_attr_type(&m, 3) != STUN_ATTR_USERNAME { ok = false; }
  if stun_attr_type(&m, 4) != 8 { ok = false; }
  if stun_attr_type(&m, 5) != 32808 { ok = false; }
  if !value_is(&req, &m, 0, bytes_of("STUN test client")) { ok = false; }
  if !value_is(&req, &m, 1, hb("6e0001ff")) { ok = false; }
  if !value_is(&req, &m, 3, bytes_of("evtj:h6vY")) { ok = false; }
  if !value_is(&req, &m, 4, hb("9aeaa70cbfd8cb56781ef2b5b2d3f249c1b571a2")) { ok = false; }
  if !value_is(&req, &m, 5, hb("e57a3bcf")) { ok = false; }
  let tx = stun_attr_text(&req, &m, 0);
  if !str_is(tx, "STUN test client") { ok = false; }
  let un = stun_attr_text(&req, &m, 3);
  if !str_is(un, "evtj:h6vY") { ok = false; }
  let an1: Str = stun_attr_name(36);
  if !str_eq(an1, "unknown") { ok = false; }
  let an2: Str = stun_attr_name(STUN_ATTR_SOFTWARE);
  if !str_eq(an2, "SOFTWARE") { ok = false; }
  return assert(ok, "RFC 5769 request: header, six attributes, 3-space padding skipped");
}

fn t2() -> TestResult {
  let resp = hb("0101003c2112a442b7e7a701bc34d686fa87dfae8022000b7465737420766563746f7220002000080001a147e112a643000800142b91f599fd9e90c38c7489f92af9ba53f06be7d780280004c07d4c96");
  let pr = stun_parse(&resp);
  if !pr.is_ok { return assert(false, "RFC 5769 IPv4 response must parse"); }
  let m: StunMessage = pr.value;
  var ok = m.msg_type == 257;
  if m.method != STUN_METHOD_BINDING { ok = false; }
  if m.msg_class != STUN_CLASS_SUCCESS { ok = false; }
  if m.message_length != 60 { ok = false; }
  if stun_attr_count(&m) != 4 { ok = false; }
  let cn: Str = stun_class_name(m.msg_class);
  if !str_eq(cn, "success response") { ok = false; }
  if stun_find_attr(&m, STUN_ATTR_XOR_MAPPED_ADDRESS) != 1 { ok = false; }
  let tx = stun_attr_text(&resp, &m, 0);
  if !str_is(tx, "test vector") { ok = false; }
  let xr = stun_attr_xor_mapped_address(&resp, &m, 1);
  if !addr_is(xr, STUN_FAMILY_IPV4, 32853, hb("c0000201")) { ok = false; }
  if !value_is(&resp, &m, 2, hb("2b91f599fd9e90c38c7489f92af9ba53f06be7d7")) { ok = false; }
  if !value_is(&resp, &m, 3, hb("c07d4c96")) { ok = false; }
  return assert(ok, "RFC 5769 IPv4 response: XOR un-maps to 192.0.2.1:32853");
}

fn t3() -> TestResult {
  let resp = hb("010100482112a442b7e7a701bc34d686fa87dfae8022000b7465737420766563746f7220002000140002a1470113a9faa5d3f179bc25f4b5bed2b9d900080014a382954e4be67bf11784c97c8292c275bfe3ed4180280004c8fb0b4c");
  let pr = stun_parse(&resp);
  if !pr.is_ok { return assert(false, "RFC 5769 IPv6 response must parse"); }
  let m: StunMessage = pr.value;
  var ok = m.msg_type == 257;
  if m.msg_class != STUN_CLASS_SUCCESS { ok = false; }
  if m.message_length != 72 { ok = false; }
  if stun_attr_count(&m) != 4 { ok = false; }
  let tx = stun_attr_text(&resp, &m, 0);
  if !str_is(tx, "test vector") { ok = false; }
  let xr = stun_attr_xor_mapped_address(&resp, &m, 1);
  if !addr_is(xr, STUN_FAMILY_IPV6, 32853, hb("20010db8123456780011223344556677")) { ok = false; }
  if !value_is(&resp, &m, 2, hb("a382954e4be67bf11784c97c8292c275bfe3ed41")) { ok = false; }
  if !value_is(&resp, &m, 3, hb("c8fb0b4c")) { ok = false; }
  return assert(ok, "RFC 5769 IPv6 response: 128-bit XOR un-maps to 2001:db8::1:2233:4455:6677");
}

fn t4() -> TestResult {
  let req = hb("000100602112a44278ad3433c6ad72c029da412e00060012e3839ee38388e383aae38383e382afe382b900000015001c662f2f3439396b39353464364f4c33346f4c394653547679363473410014000b6578616d706c652e6f72670000080014f67024656dd64a3e02b8e0712e85c9a28ca89666");
  let pr = stun_parse(&req);
  if !pr.is_ok { return assert(false, "RFC 5769 long-term request must parse"); }
  let m: StunMessage = pr.value;
  var ok = stun_attr_count(&m) == 4;
  if stun_attr_type(&m, 0) != STUN_ATTR_USERNAME { ok = false; }
  if stun_attr_type(&m, 1) != 21 { ok = false; }
  if stun_attr_type(&m, 2) != 20 { ok = false; }
  if stun_attr_type(&m, 3) != 8 { ok = false; }
  if !value_is(&req, &m, 0, hb("e3839ee38388e383aae38383e382afe382b9")) { ok = false; }
  let ut = stun_attr_text(&req, &m, 0);
  if !str_is(ut, "マトリックス") { ok = false; }
  if !value_is(&req, &m, 1, hb("662f2f3439396b39353464364f4c33346f4c39465354767936347341")) { ok = false; }
  let rt = stun_attr_text(&req, &m, 2);
  if !str_is(rt, "example.org") { ok = false; }
  var types = Vec[Int].new();
  types.push(STUN_ATTR_USERNAME);
  types.push(21);
  types.push(20);
  types.push(8);
  var values = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < 4 {
    let v: Vec[UInt8] = value_at(&req, &m, i);
    values.push(v);
    i = i + 1;
  }
  let tid: Vec[UInt8] = m.transaction_id;
  let br = stun_build(m.msg_type, &tid, &types, &values);
  if !br.is_ok { ok = false; } else {
    let built: Vec[UInt8] = br.value;
    if !bytes_equal(built, req) { ok = false; }
  }
  return assert(ok, "UTF-8 USERNAME/REALM and unknown NONCE/MESSAGE-INTEGRITY; rebuild is byte-identical");
}

fn t5() -> TestResult {
  let v4 = hb("c0000201");
  let v6 = hb("20010db8123456780011223344556677");
  let tid = hb("b7e7a701bc34d686fa87dfae");
  var ok = bytes_is(stun_encode_mapped_address(STUN_FAMILY_IPV4, 32853, &v4), hb("00018055c0000201"));
  if !bytes_is(stun_encode_mapped_address(STUN_FAMILY_IPV6, 32853, &v6), hb("0002805520010db8123456780011223344556677")) { ok = false; }
  if !bytes_is(stun_encode_xor_mapped_address(STUN_FAMILY_IPV4, 32853, &v4, &tid), hb("0001a147e112a643")) { ok = false; }
  if !bytes_is(stun_encode_xor_mapped_address(STUN_FAMILY_IPV6, 32853, &v6, &tid), hb("0002a1470113a9faa5d3f179bc25f4b5bed2b9d9")) { ok = false; }
  return assert(ok, "address encoders reproduce the RFC 5769 IPv4/IPv6 values byte for byte");
}

fn t6() -> TestResult {
  let tid = hb("aabbccddeeff001122334455");
  var types = Vec[Int].new();
  types.push(STUN_ATTR_MAPPED_ADDRESS);
  var values = Vec[Vec[UInt8]].new();
  let v4 = hb("c0000201");
  let mv = stun_encode_mapped_address(STUN_FAMILY_IPV4, 8080, &v4);
  if !mv.is_ok { return assert(false, "mapped address encode must succeed"); }
  let mvv: Vec[UInt8] = mv.value;
  values.push(mvv);
  let br = stun_build(STUN_METHOD_BINDING, &tid, &types, &values);
  if !br.is_ok { return assert(false, "build must succeed"); }
  let built: Vec[UInt8] = br.value;
  var ok = bytes_equal(built, hb("0001000c2112a442aabbccddeeff0011223344550001000800011f90c0000201"));
  if built.len() != 32 { ok = false; }
  let pr = stun_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let m: StunMessage = pr.value;
    if stun_attr_count(&m) != 1 { ok = false; }
    if stun_attr_type(&m, 0) != STUN_ATTR_MAPPED_ADDRESS { ok = false; }
    let ar = stun_attr_mapped_address(&built, &m, 0);
    if !addr_is(ar, STUN_FAMILY_IPV4, 8080, hb("c0000201")) { ok = false; }
  }
  return assert(ok, "build writes the exact 32-byte MAPPED-ADDRESS message and parses back");
}

fn t7() -> TestResult {
  let tid = hb("aabbccddeeff001122334455");
  var types = Vec[Int].new();
  types.push(STUN_ATTR_USERNAME);
  types.push(STUN_ATTR_SOFTWARE);
  types.push(36);
  var values = Vec[Vec[UInt8]].new();
  values.push(stun_encode_username("evtj:h6vY"));
  values.push(stun_encode_software("test"));
  values.push(hb("6e0001ff"));
  let br = stun_build(STUN_METHOD_BINDING, &tid, &types, &values);
  if !br.is_ok { return assert(false, "build must succeed"); }
  let built: Vec[UInt8] = br.value;
  var ok = bytes_equal(built, hb("000100202112a442aabbccddeeff001122334455000600096576746a3a683676590000008022000474657374002400046e0001ff"));
  if built.len() != 52 { ok = false; }
  let pr = stun_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let m: StunMessage = pr.value;
    if stun_attr_count(&m) != 3 { ok = false; }
    if !value_is(&built, &m, 0, bytes_of("evtj:h6vY")) { ok = false; }
    if !value_is(&built, &m, 1, bytes_of("test")) { ok = false; }
    if !value_is(&built, &m, 2, hb("6e0001ff")) { ok = false; }
    let tx = stun_attr_text(&built, &m, 0);
    if !str_is(tx, "evtj:h6vY") { ok = false; }
  }
  return assert(ok, "build pads a 9-byte USERNAME with zeroes and keeps attribute order");
}

fn t8() -> TestResult {
  let hdr = hb("000100002112a442000102030405060708090a0b");
  let req_head = hb("000100582112a442b7e7a701bc34d686fa87dfae");
  let bad_type = hb("800100002112a442000102030405060708090a0b");
  let over = hb("000100ff2112a442000102030405060708090a0b");
  var ok = stun_is_message(&hdr);
  if !stun_is_message(&req_head) { ok = false; }
  if !stun_is_message(&over) { ok = false; }
  let short = prefix(hdr, 19);
  if stun_is_message(&short) { ok = false; }
  let zero = hb("0000000000000000000000000000000000000000");
  if stun_is_message(&zero) { ok = false; }
  if stun_is_message(&bad_type) { ok = false; }
  var empty = Vec[UInt8].new();
  if stun_is_message(&empty) { ok = false; }
  return assert(ok, "is_message: cookie and 14-bit type are sniffed, attributes are not");
}

fn t9() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_msg_is(stun_parse(&empty), "stun: truncated header");
  let magic = hb("2112a442");
  if !err_msg_is(stun_parse(&magic), "stun: truncated header") { ok = false; }
  let req = hb("000100582112a442b7e7a701bc34d686fa87dfae");
  let cut = prefix(req, 19);
  if !err_msg_is(stun_parse(&cut), "stun: truncated header") { ok = false; }
  return assert(ok, "inputs shorter than the 20-byte header are Err");
}

fn t10() -> TestResult {
  let bad_type = hb("800100002112a442000102030405060708090a0b");
  let bad_cookie = hb("0001000000000000000102030405060708090a0b");
  let both = hb("8001000000000000000102030405060708090a0b");
  var ok = err_msg_is(stun_parse(&bad_type), "stun: bad message type");
  if !err_msg_is(stun_parse(&bad_cookie), "stun: bad magic cookie") { ok = false; }
  if !err_msg_is(stun_parse(&both), "stun: bad message type") { ok = false; }
  return assert(ok, "nonzero top type bits and a wrong cookie are Err; type wins the tie");
}

fn t11() -> TestResult {
  let short = hb("000100082112a442aabbccddeeff001122334455");
  let long = hb("000100582112a442aabbccddeeff001122334455");
  var ok = err_msg_is(stun_parse(&short), "stun: truncated message");
  if !err_msg_is(stun_parse(&long), "stun: truncated message") { ok = false; }
  let fit = hb("000100042112a442aabbccddeeff00112233445500060000");
  let pr = stun_parse(&fit);
  if !pr.is_ok { ok = false; } else {
    let m: StunMessage = pr.value;
    if stun_attr_count(&m) != 1 { ok = false; }
    if stun_attr_type(&m, 0) != STUN_ATTR_USERNAME { ok = false; }
    if !value_is(&fit, &m, 0, Vec[UInt8].new()) { ok = false; }
  }
  return assert(ok, "declared length beyond the buffer is Err; an exact fit with a zero-length attribute parses");
}

fn t12() -> TestResult {
  let cut2 = hb("000100022112a442aabbccddeeff0011223344550006");
  let cut3 = hb("000100032112a442aabbccddeeff001122334455000600");
  let over = hb("000100042112a442aabbccddeeff00112233445500060004");
  let over2 = hb("000100082112a442aabbccddeeff0011223344550006000800000000");
  let pad1 = hb("000100062112a442aabbccddeeff001122334455000600020001");
  let pad2 = hb("000100052112a442aabbccddeeff00112233445500060001ff");
  var ok = err_msg_is(stun_parse(&cut2), "stun: truncated attribute");
  if !err_msg_is(stun_parse(&cut3), "stun: truncated attribute") { ok = false; }
  if !err_msg_is(stun_parse(&over), "stun: attribute overruns message") { ok = false; }
  if !err_msg_is(stun_parse(&over2), "stun: attribute overruns message") { ok = false; }
  if !err_msg_is(stun_parse(&pad1), "stun: bad padding") { ok = false; }
  if !err_msg_is(stun_parse(&pad2), "stun: bad padding") { ok = false; }
  return assert(ok, "partial headers, overflowing values and unaligned padding are Err");
}

fn t13() -> TestResult {
  let tid = hb("aabbccddeeff001122334455");
  var no_t = Vec[Int].new();
  var no_v = Vec[Vec[UInt8]].new();
  var ok = err_bytes_is(stun_build(16384, &tid, &no_t, &no_v), "stun: bad message type");
  if !err_bytes_is(stun_build(-1, &tid, &no_t, &no_v), "stun: bad message type") { ok = false; }
  let tid11 = hb("aabbccddeeff0011223344");
  if !err_bytes_is(stun_build(STUN_METHOD_BINDING, &tid11, &no_t, &no_v), "stun: bad transaction id") { ok = false; }
  var types2 = Vec[Int].new();
  types2.push(1);
  types2.push(2);
  var values1 = Vec[Vec[UInt8]].new();
  values1.push(hb("00"));
  if !err_bytes_is(stun_build(STUN_METHOD_BINDING, &tid, &types2, &values1), "stun: attribute count mismatch") { ok = false; }
  var types3 = Vec[Int].new();
  types3.push(65536);
  var values3 = Vec[Vec[UInt8]].new();
  values3.push(hb("00"));
  if !err_bytes_is(stun_build(STUN_METHOD_BINDING, &tid, &types3, &values3), "stun: bad attribute type") { ok = false; }
  var types4 = Vec[Int].new();
  types4.push(32767);
  var values4 = Vec[Vec[UInt8]].new();
  values4.push(repeat_byte(7, 65536));
  if !err_bytes_is(stun_build(STUN_METHOD_BINDING, &tid, &types4, &values4), "stun: attribute too large") { ok = false; }
  var types5 = Vec[Int].new();
  types5.push(32767);
  var values5 = Vec[Vec[UInt8]].new();
  values5.push(repeat_byte(7, 65535));
  if !err_bytes_is(stun_build(STUN_METHOD_BINDING, &tid, &types5, &values5), "stun: message too large") { ok = false; }
  return assert(ok, "build rejects bad type/tid/count/size and an oversized message");
}

fn t14() -> TestResult {
  let req = hb("000100582112a442b7e7a701bc34d686fa87dfae802200105354554e207465737420636c69656e74002400046e0001ff80290008932ff9b151263b36000600096576746a3a68367659202020000800149aeaa70cbfd8cb56781ef2b5b2d3f249c1b571a280280004e57a3bcf");
  let pr = stun_parse(&req);
  if !pr.is_ok { return assert(false, "request must parse"); }
  let m: StunMessage = pr.value;
  var ok = stun_attr_count(&m) == 6;
  if stun_attr_type(&m, -1) != -1 { ok = false; }
  if stun_attr_type(&m, 6) != -1 { ok = false; }
  if stun_attr_type(&m, 100) != -1 { ok = false; }
  if stun_find_attr(&m, STUN_ATTR_MAPPED_ADDRESS) != -1 { ok = false; }
  if stun_find_attr(&m, 32808) != 5 { ok = false; }
  if !err_bytes_is(stun_attr_value(&req, &m, 6), "stun: attribute out of range") { ok = false; }
  if !err_bytes_is(stun_attr_value(&req, &m, -1), "stun: attribute out of range") { ok = false; }
  if !err_str_is(stun_attr_text(&req, &m, 9), "stun: attribute out of range") { ok = false; }
  let cut = prefix(req, 30);
  if !err_bytes_is(stun_attr_value(&cut, &m, 0), "stun: attribute out of bounds") { ok = false; }
  let hdr = hb("000100002112a442000102030405060708090a0b");
  let er = stun_parse(&hdr);
  if !er.is_ok { ok = false; } else {
    let em: StunMessage = er.value;
    if stun_attr_count(&em) != 0 { ok = false; }
    if stun_find_attr(&em, 6) != -1 { ok = false; }
    if stun_attr_type(&em, 0) != -1 { ok = false; }
    if !err_bytes_is(stun_attr_value(&hdr, &em, 0), "stun: attribute out of range") { ok = false; }
  }
  return assert(ok, "accessors guard -1/out of range and a short source buffer is Err");
}

fn t15() -> TestResult {
  let d1 = msg_with(STUN_ATTR_MAPPED_ADDRESS, hb("0003000080808080"));
  let p1 = stun_parse(&d1);
  if !p1.is_ok { return assert(false, "family-3 message must parse"); }
  let m1: StunMessage = p1.value;
  var ok = err_addr_is(stun_attr_mapped_address(&d1, &m1, 0), "stun: bad address family");
  if !err_addr_is(stun_attr_xor_mapped_address(&d1, &m1, 0), "stun: bad address family") { ok = false; }
  let d2 = msg_with(STUN_ATTR_MAPPED_ADDRESS, hb("00010000808080808080808080808080"));
  let p2 = stun_parse(&d2);
  if !p2.is_ok { ok = false; } else {
    let m2: StunMessage = p2.value;
    if !err_addr_is(stun_attr_mapped_address(&d2, &m2, 0), "stun: bad address length") { ok = false; }
  }
  let d3 = msg_with(STUN_ATTR_MAPPED_ADDRESS, hb("000100"));
  let p3 = stun_parse(&d3);
  if !p3.is_ok { ok = false; } else {
    let m3: StunMessage = p3.value;
    if !err_addr_is(stun_attr_mapped_address(&d3, &m3, 0), "stun: truncated address") { ok = false; }
  }
  let v4 = hb("c0000201");
  if !err_bytes_is(stun_encode_mapped_address(3, 1, &v4), "stun: bad address family") { ok = false; }
  let v3 = hb("c00002");
  if !err_bytes_is(stun_encode_mapped_address(STUN_FAMILY_IPV4, 1, &v3), "stun: bad address length") { ok = false; }
  if !err_bytes_is(stun_encode_mapped_address(STUN_FAMILY_IPV4, 70000, &v4), "stun: bad port") { ok = false; }
  if !err_bytes_is(stun_encode_mapped_address(STUN_FAMILY_IPV4, -1, &v4), "stun: bad port") { ok = false; }
  let tid = hb("aabbccddeeff0011223344");
  if !err_bytes_is(stun_encode_xor_mapped_address(STUN_FAMILY_IPV4, 1, &v4, &tid), "stun: bad transaction id") { ok = false; }
  return assert(ok, "address codecs reject bad family, wrong length, short value and bad port");
}

fn t16() -> TestResult {
  var ok = bytes_is(stun_encode_error_code(420, "Unknown Attribute"), hb("00000414556e6b6e6f776e20417474726962757465"));
  if !bytes_is(stun_encode_error_code(300, "x"), hb("0000030078")) { ok = false; }
  if !bytes_is(stun_encode_error_code(699, ""), hb("00000663")) { ok = false; }
  if !err_bytes_is(stun_encode_error_code(299, "x"), "stun: bad error code") { ok = false; }
  if !err_bytes_is(stun_encode_error_code(700, "x"), "stun: bad error code") { ok = false; }
  let d = msg_with(STUN_ATTR_ERROR_CODE, hb("000004"));
  let p = stun_parse(&d);
  if !p.is_ok { ok = false; } else {
    let m: StunMessage = p.value;
    if !err_int_is(stun_attr_error_code(&d, &m, 0), "stun: truncated error code") { ok = false; }
    if !err_str_is(stun_attr_error_reason(&d, &m, 0), "stun: truncated error code") { ok = false; }
  }
  let tid = hb("aabbccddeeff001122334455");
  var types = Vec[Int].new();
  types.push(STUN_ATTR_ERROR_CODE);
  var values = Vec[Vec[UInt8]].new();
  let ev = stun_encode_error_code(420, "Unknown Attribute");
  if !ev.is_ok { return assert(false, "error-code encode must succeed"); }
  let evv: Vec[UInt8] = ev.value;
  values.push(evv);
  let br = stun_build(273, &tid, &types, &values);
  if !br.is_ok { ok = false; } else {
    let built: Vec[UInt8] = br.value;
    let pr = stun_parse(&built);
    if !pr.is_ok { ok = false; } else {
      let m: StunMessage = pr.value;
      if m.msg_class != STUN_CLASS_ERROR { ok = false; }
      if m.method != STUN_METHOD_BINDING { ok = false; }
      if !int_is(stun_attr_error_code(&built, &m, 0), 420) { ok = false; }
      if !str_is(stun_attr_error_reason(&built, &m, 0), "Unknown Attribute") { ok = false; }
    }
  }
  return assert(ok, "ERROR-CODE class/number/reason round-trips and its bounds are enforced");
}

fn t17() -> TestResult {
  var ok = stun_message_type(1, STUN_CLASS_REQUEST) == 1;
  if stun_message_type(1, STUN_CLASS_INDICATION) != 17 { ok = false; }
  if stun_message_type(1, STUN_CLASS_SUCCESS) != 257 { ok = false; }
  if stun_message_type(1, STUN_CLASS_ERROR) != 273 { ok = false; }
  if stun_message_type(291, STUN_CLASS_SUCCESS) != 1347 { ok = false; }
  if stun_type_method(1347) != 291 { ok = false; }
  if stun_type_class(1347) != STUN_CLASS_SUCCESS { ok = false; }
  if stun_type_method(273) != 1 { ok = false; }
  if stun_type_class(273) != STUN_CLASS_ERROR { ok = false; }
  if stun_message_type(4096, 0) != -1 { ok = false; }
  if stun_message_type(0, 4) != -1 { ok = false; }
  if stun_message_type(-1, 0) != -1 { ok = false; }
  if stun_message_type(0, -1) != -1 { ok = false; }
  if stun_type_method(16384) != -1 { ok = false; }
  if stun_type_method(-1) != -1 { ok = false; }
  if stun_type_class(16384) != -1 { ok = false; }
  if stun_type_class(-1) != -1 { ok = false; }
  let c0: Str = stun_class_name(STUN_CLASS_REQUEST);
  if !str_eq(c0, "request") { ok = false; }
  let c1: Str = stun_class_name(STUN_CLASS_INDICATION);
  if !str_eq(c1, "indication") { ok = false; }
  let c3: Str = stun_class_name(STUN_CLASS_ERROR);
  if !str_eq(c3, "error response") { ok = false; }
  let c4: Str = stun_class_name(4);
  if !str_eq(c4, "unknown") { ok = false; }
  let mn1: Str = stun_method_name(STUN_METHOD_BINDING);
  if !str_eq(mn1, "binding") { ok = false; }
  let mn2: Str = stun_method_name(2);
  if !str_eq(mn2, "unknown") { ok = false; }
  let a1: Str = stun_attr_name(STUN_ATTR_MAPPED_ADDRESS);
  if !str_eq(a1, "MAPPED-ADDRESS") { ok = false; }
  let a9: Str = stun_attr_name(STUN_ATTR_ERROR_CODE);
  if !str_eq(a9, "ERROR-CODE") { ok = false; }
  let a32: Str = stun_attr_name(STUN_ATTR_XOR_MAPPED_ADDRESS);
  if !str_eq(a32, "XOR-MAPPED-ADDRESS") { ok = false; }
  let a6: Str = stun_attr_name(STUN_ATTR_USERNAME);
  if !str_eq(a6, "USERNAME") { ok = false; }
  if stun_padded_len(0) != 0 { ok = false; }
  if stun_padded_len(1) != 4 { ok = false; }
  if stun_padded_len(4) != 4 { ok = false; }
  if stun_padded_len(5) != 8 { ok = false; }
  if stun_padded_len(9) != 12 { ok = false; }
  if stun_padded_len(13) != 16 { ok = false; }
  if stun_padded_len(-1) != -1 { ok = false; }
  return assert(ok, "type packing inverts, names are stable, padded_len rounds up");
}

fn t18() -> TestResult {
  let hdr = hb("000100002112a442000102030405060708090a0b");
  let pr = stun_parse(&hdr);
  if !pr.is_ok { return assert(false, "header-only message must parse"); }
  let m: StunMessage = pr.value;
  var ok = stun_attr_count(&m) == 0;
  if m.message_length != 0 { ok = false; }
  if m.method != STUN_METHOD_BINDING { ok = false; }
  if m.msg_class != STUN_CLASS_REQUEST { ok = false; }
  let junk = concat2(hdr, hb("deadbeef0102030405060708090a"));
  let jr = stun_parse(&junk);
  if !jr.is_ok { ok = false; } else {
    let jm: StunMessage = jr.value;
    if stun_attr_count(&jm) != 0 { ok = false; }
  }
  let tid = hb("000102030405060708090a0b");
  var no_t = Vec[Int].new();
  var no_v = Vec[Vec[UInt8]].new();
  let br = stun_build(STUN_METHOD_BINDING, &tid, &no_t, &no_v);
  if !br.is_ok { ok = false; } else {
    let built: Vec[UInt8] = br.value;
    if !bytes_equal(built, hdr) { ok = false; }
  }
  let z = msg_with(STUN_ATTR_SOFTWARE, Vec[UInt8].new());
  let zr = stun_parse(&z);
  if !zr.is_ok { ok = false; } else {
    let zm: StunMessage = zr.value;
    if stun_attr_count(&zm) != 1 { ok = false; }
    if !value_is(&z, &zm, 0, Vec[UInt8].new()) { ok = false; }
    if z.len() != 24 { ok = false; }
  }
  return assert(ok, "header-only messages, trailing junk and zero-length attributes");
}

fn main() -> Int {
  io.println("=== xiom.stun conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.stun: all tests passed");
  } else {
    io.println("xiom.stun: tests failed");
  }
  return failed;
}
