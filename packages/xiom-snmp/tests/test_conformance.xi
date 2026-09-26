// XIOM -- xiom.snmp conformance tests (19 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every fixture is synthetic: hex strings decoded in-test plus messages
// assembled from the library's own encoders (no external data files). The
// error strings are compared through xiom.string.compare.str_compare (BUG
// 17: `==` on a Str read from a Vec lowers to a pointer comparison), every
// Vec element is read into a typed local first, and PDU tags are only ever
// compared as widened Ints.

module snmp_tests
use xiom.io; use xiom.test;
use xiom.snmp;
use xiom.string;
use xiom.string.compare;
use xiom.string.builder;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers
// --------------------------------------------------

// Bytes for a hex string ("" on malformed input; the test then fails on the
// byte comparison).
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
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn arcs_equal(a: Vec[Int], b: Vec[Int]) -> Bool {
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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// The library's error-message format, rebuilt here so expected strings stay
// readable: "<msg> at offset <off>".
fn eat(msg: Str, off: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, msg);
  builder.sb_push_str(&mut sb, " at offset ");
  builder.sb_push_int(&mut sb, off);
  return builder.sb_to_str(&sb);
}

fn oid4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn oid9(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int, i: Int) -> Vec[Int] {
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
  return v;
}

fn mv(tag: Int, iv: Int, b: Vec[UInt8], o: Vec[Int]) -> SnmpValue {
  return SnmpValue{ tag: tag; int_val: iv; bytes: b; oid: o; next: 0; };
}

// Encoded OID TLV, or an empty vector on error (fixtures only).
fn oid_tlv(arcs: Vec[Int]) -> Vec[UInt8] {
  let r = ber_oid_encode(&arcs);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.value;
  return v;
}

// Wrap `content` in a TLV with a definite short/long length (test fixtures
// stay below 65536 bytes).
fn wrap(tag: Int, content: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(tag as UInt8);
  if content.len() < 128 {
    out.push(content.len() as UInt8);
  } elif content.len() < 256 {
    out.push(129 as UInt8);
    out.push(content.len() as UInt8);
  } else {
    out.push(130 as UInt8);
    out.push((content.len() / 256) as UInt8);
    out.push((content.len() % 256) as UInt8);
  }
  var i = 0;
  while i < content.len() {
    out.push(content[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Message-fixture helpers
// --------------------------------------------------

fn msg_with_community(version: Int, community: Vec[UInt8], pdu: Vec[UInt8]) -> Vec[UInt8] {
  let v = ber_int_encode(version);
  let c = ber_octet_string_encode(&community);
  return wrap(SNMP_TAG_SEQUENCE, concat2(concat2(v, c), pdu));
}

fn plain_msg(version: Int, pdu: Vec[UInt8]) -> Vec[UInt8] {
  return msg_with_community(version, bytes_of("public"), pdu);
}

// PDU body: request-id, second and third integers, varbind list.
fn req_body(rid: Int, e1: Int, e2: Int, list: Vec[UInt8]) -> Vec[UInt8] {
  let a = concat2(ber_int_encode(rid), ber_int_encode(e1));
  let b = concat2(ber_int_encode(e2), list);
  return concat2(a, b);
}

fn req_pdu(kind: Int) -> Vec[UInt8] {
  let list = wrap(SNMP_TAG_SEQUENCE, Vec[UInt8].new());
  return wrap(160 + kind, req_body(5, 0, 0, list));
}

fn msg_with_list(version: Int, list: Vec[UInt8]) -> Vec[UInt8] {
  let body = req_body(5, 0, 0, list);
  return plain_msg(version, wrap(160, body));
}

fn trap_pdu() -> Vec[UInt8] {
  let e = oid_tlv(oid4(1, 3, 6, 1, 4));
  let a = wrap(SNMP_TAG_IPADDRESS, hb("c0000201"));
  let g = ber_int_encode(6);
  let s = ber_int_encode(2);
  let t = wrap(SNMP_TAG_TIMETICKS, hb("000100"));
  let l = wrap(SNMP_TAG_SEQUENCE, Vec[UInt8].new());
  return wrap(160 + SNMP_PDU_TRAP_V1, concat2(concat2(e, a), concat2(concat2(g, s), concat2(t, l))));
}

// --------------------------------------------------
//  Result inspectors
// --------------------------------------------------

fn err_len_is(r: Result[BerLength, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn len_is(r: Result[BerLength, Str], len: Int, size: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BerLength = r.value;
  return v.len == len && v.size == size;
}

fn tlv_is(r: Result[BerTlv, Str], tag: Int, len: Int, size: Int, content: Int, next: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BerTlv = r.value;
  if v.tag != tag {
    return false;
  }
  if v.len != len {
    return false;
  }
  if v.size != size {
    return false;
  }
  if v.content != content {
    return false;
  }
  return v.next == next;
}

fn err_tlv_is(r: Result[BerTlv, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn bint_is(r: Result[BerInt, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BerInt = r.value;
  return v.value == want;
}

fn bint_is_next(r: Result[BerInt, Str], want: Int, next: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BerInt = r.value;
  return v.value == want && v.next == next;
}

fn err_bint_is(r: Result[BerInt, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn bbytes_is(r: Result[BerBytes, Str], want: Vec[UInt8]) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BerBytes = r.value;
  return bytes_equal(v.bytes, want);
}

fn bbytes_is_next(r: Result[BerBytes, Str], want: Vec[UInt8], next: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BerBytes = r.value;
  return bytes_equal(v.bytes, want) && v.next == next;
}

fn err_bbytes_is(r: Result[BerBytes, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn arcs_is(r: Result[BerOid, Str], want: Vec[Int]) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BerOid = r.value;
  return arcs_equal(v.arcs, want);
}

fn arcs_is_next(r: Result[BerOid, Str], want: Vec[Int], next: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BerOid = r.value;
  return arcs_equal(v.arcs, want) && v.next == next;
}

fn err_oid_is(r: Result[BerOid, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
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

fn bytes_is(r: Result[Vec[UInt8], Str], want: Vec[UInt8]) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  return bytes_equal(v, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_msg_is(r: Result[SnmpMessage, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Build a Response with `v` as the only value, parse it back and compare
// the varbind name and the typed value field by field.
fn value_roundtrip(v: SnmpValue, oid: Vec[Int]) -> Bool {
  let comm = bytes_of("public");
  let br = snmp_response_build(SNMP_VERSION_V2C, &comm, 9, &oid, &v);
  if !br.is_ok {
    return false;
  }
  let built: Vec[UInt8] = br.value;
  let pr = snmp_message_parse(&built);
  if !pr.is_ok {
    return false;
  }
  let m: SnmpMessage = pr.value;
  if snmp_varbind_count(&m) != 1 {
    return false;
  }
  let off = snmp_varbind_offset(&m, 0);
  let vbr = snmp_varbind_parse(&built, off);
  if !vbr.is_ok {
    return false;
  }
  let vb: SnmpVarBind = vbr.value;
  if !arcs_equal(vb.name, oid) {
    return false;
  }
  let pv: SnmpValue = vb.value;
  if pv.tag != v.tag {
    return false;
  }
  if pv.int_val != v.int_val {
    return false;
  }
  if !bytes_equal(pv.bytes, v.bytes) {
    return false;
  }
  return arcs_equal(pv.oid, v.oid);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = len_is(ber_length_decode(&hb("00"), 0), 0, 1);
  if !len_is(ber_length_decode(&hb("01"), 0), 1, 1) { ok = false; }
  if !len_is(ber_length_decode(&hb("7f"), 0), 127, 1) { ok = false; }
  if !len_is(ber_length_decode(&hb("8180"), 0), 128, 2) { ok = false; }
  if !len_is(ber_length_decode(&hb("820100"), 0), 256, 3) { ok = false; }
  if !len_is(ber_length_decode(&hb("8280ff"), 0), 33023, 3) { ok = false; }
  if !len_is(ber_length_decode(&hb("83000005"), 0), 5, 4) { ok = false; }
  if !len_is(ber_length_decode(&hb("81800102"), 0), 128, 2) { ok = false; }
  if !len_is(ber_length_decode(&hb("820005"), 0), 5, 3) { ok = false; }
  if !len_is(ber_length_decode(&hb("00ff"), 0), 0, 1) { ok = false; }
  let empty = Vec[UInt8].new();
  if !err_len_is(ber_length_decode(&empty, 0), "ber: truncated length at offset 0") { ok = false; }
  if !err_len_is(ber_length_decode(&hb("81"), 0), "ber: truncated length at offset 0") { ok = false; }
  if !err_len_is(ber_length_decode(&hb("8201"), 0), "ber: truncated length at offset 0") { ok = false; }
  if !err_len_is(ber_length_decode(&hb("80"), 0), "ber: indefinite length at offset 0") { ok = false; }
  if !err_len_is(ber_length_decode(&hb("88ffffffffffffffff"), 0), "ber: length overflow at offset 0") { ok = false; }
  if !err_len_is(ber_length_decode(&hb("89000000000000000000"), 0), "ber: length overflow at offset 0") { ok = false; }
  if !err_len_is(ber_length_decode(&hb("00"), -1), "ber: negative offset") { ok = false; }
  if !err_len_is(ber_length_decode(&hb("00"), 4), "ber: truncated length at offset 4") { ok = false; }
  return assert(ok, "BER length: short form, long form 1-3 bytes, indefinite/overflow/truncation rejected");
}

fn t2() -> TestResult {
  let h1 = hb("020105");
  var ok = tlv_is(ber_tlv_decode(&h1, 0), 2, 1, 2, 2, 3);
  let h2 = hb("3000");
  if !tlv_is(ber_tlv_decode(&h2, 0), 48, 0, 2, 2, 2) { ok = false; }
  let h3 = hb("020105ff");
  if !tlv_is(ber_tlv_decode(&h3, 0), 2, 1, 2, 2, 3) { ok = false; }
  let big = wrap(48, repeat_byte(7, 128));
  if !tlv_is(ber_tlv_decode(&big, 0), 48, 128, 3, 3, 131) { ok = false; }
  if big.len() != 131 { ok = false; }
  let h4 = hb("1f0100");
  if !err_tlv_is(ber_tlv_decode(&h4, 0), "ber: multi-byte tag at offset 0") { ok = false; }
  let h5 = hb("ff0100");
  if !err_tlv_is(ber_tlv_decode(&h5, 0), "ber: multi-byte tag at offset 0") { ok = false; }
  let h6 = hb("04054142");
  if !err_tlv_is(ber_tlv_decode(&h6, 0), "ber: value overruns buffer at offset 0") { ok = false; }
  let empty = Vec[UInt8].new();
  if !err_tlv_is(ber_tlv_decode(&empty, 0), "ber: truncated tag at offset 0") { ok = false; }
  if !err_tlv_is(ber_tlv_decode(&h1, 3), "ber: truncated tag at offset 3") { ok = false; }
  if !err_tlv_is(ber_tlv_decode(&h1, -3), "ber: negative offset") { ok = false; }
  let h7 = hb("048201");
  if !err_tlv_is(ber_tlv_decode(&h7, 0), "ber: truncated length at offset 1") { ok = false; }
  let h8 = hb("0489000000000000000000");
  if !err_tlv_is(ber_tlv_decode(&h8, 0), "ber: length overflow at offset 1") { ok = false; }
  return assert(ok, "BER TLV: header fields, long form, trailing bytes, malformed tags/lengths");
}

fn t3() -> TestResult {
  let v0 = hb("020100");
  var ok = bint_is_next(ber_int_decode(&v0, 0), 0, 3);
  if !bint_is(ber_int_decode(&hb("02017f"), 0), 127) { ok = false; }
  if !bint_is(ber_int_decode(&hb("02020080"), 0), 128) { ok = false; }
  if !bint_is(ber_int_decode(&hb("020200ff"), 0), 255) { ok = false; }
  if !bint_is(ber_int_decode(&hb("02020100"), 0), 256) { ok = false; }
  if !bint_is(ber_int_decode(&hb("020180"), 0), -128) { ok = false; }
  if !bint_is(ber_int_decode(&hb("0201ff"), 0), -1) { ok = false; }
  if !bint_is(ber_int_decode(&hb("0202ff7f"), 0), -129) { ok = false; }
  if !bint_is(ber_int_decode(&hb("0202ff00"), 0), -256) { ok = false; }
  if !bint_is(ber_int_decode(&hb("02080100000000000000"), 0), 72057594037927936) { ok = false; }
  if !bint_is(ber_int_decode(&hb("02087fffffffffffffff"), 0), 9223372036854775807) { ok = false; }
  if !bint_is(ber_int_decode(&hb("02088000000000000000"), 0), -9223372036854775808) { ok = false; }
  let tail = hb("020105ff");
  if !bint_is_next(ber_int_decode(&tail, 0), 5, 3) { ok = false; }
  if !err_bint_is(ber_int_decode(&hb("0200"), 0), eat("ber: empty integer", 0)) { ok = false; }
  if !err_bint_is(ber_int_decode(&hb("0202007f"), 0), eat("ber: non-minimal integer", 0)) { ok = false; }
  if !err_bint_is(ber_int_decode(&hb("0202ffff"), 0), eat("ber: non-minimal integer", 0)) { ok = false; }
  if !err_bint_is(ber_int_decode(&hb("0209010000000000000000"), 0), eat("ber: integer overflow", 0)) { ok = false; }
  if !err_bint_is(ber_int_decode(&hb("040100"), 0), eat("ber: tag mismatch", 0)) { ok = false; }
  let trunc = hb("02");
  if !err_bint_is(ber_int_decode(&trunc, 0), eat("ber: truncated length", 1)) { ok = false; }
  return assert(ok, "INTEGER decode: 0/127/128/255/-128/-129/-256/2^56/Int bounds and minimal-encoding rule");
}

fn t4() -> TestResult {
  let s1 = hb("0403616263");
  var ok = bbytes_is_next(ber_octet_string_decode(&s1, 0), bytes_of("abc"), 5);
  let s2 = hb("0400");
  if !bbytes_is(ber_octet_string_decode(&s2, 0), Vec[UInt8].new()) { ok = false; }
  let s3 = hb("040400ff4100");
  if !bbytes_is(ber_octet_string_decode(&s3, 0), hb("00ff4100")) { ok = false; }
  let n1 = hb("0500");
  if !int_is(ber_null_decode(&n1, 0), 2) { ok = false; }
  let n2 = hb("050100");
  if !err_int_is(ber_null_decode(&n2, 0), eat("ber: bad null", 0)) { ok = false; }
  if !err_int_is(ber_null_decode(&s2, 0), eat("ber: tag mismatch", 0)) { ok = false; }
  let o1 = hb("4402ff00");
  if !bbytes_is_next(ber_opaque_decode(&o1, 0), hb("ff00"), 4) { ok = false; }
  let o2 = hb("4400");
  if !bbytes_is(ber_opaque_decode(&o2, 0), Vec[UInt8].new()) { ok = false; }
  let i1 = hb("4004c0000201");
  if !bbytes_is_next(ber_ipaddress_decode(&i1, 0), hb("c0000201"), 6) { ok = false; }
  let i2 = hb("4003c00002");
  if !err_bbytes_is(ber_ipaddress_decode(&i2, 0), eat("ber: bad ipaddress", 0)) { ok = false; }
  let i3 = hb("4000");
  if !err_bbytes_is(ber_ipaddress_decode(&i3, 0), eat("ber: bad ipaddress", 0)) { ok = false; }
  if !err_bbytes_is(ber_opaque_decode(&i1, 0), eat("ber: tag mismatch", 0)) { ok = false; }
  return assert(ok, "OCTET STRING / NULL / Opaque / IpAddress: raw content and length rules");
}

fn t5() -> TestResult {
  var ok = true;
  var a = Vec[Int].new();
  a.push(0);
  a.push(0);
  if !arcs_is(ber_oid_decode(&hb("060100"), 0), a) { ok = false; }
  var a2 = Vec[Int].new();
  a2.push(0);
  a2.push(39);
  if !arcs_is(ber_oid_decode(&hb("060127"), 0), a2) { ok = false; }
  var a3 = Vec[Int].new();
  a3.push(1);
  a3.push(0);
  if !arcs_is(ber_oid_decode(&hb("060128"), 0), a3) { ok = false; }
  var a4 = Vec[Int].new();
  a4.push(1);
  a4.push(39);
  if !arcs_is(ber_oid_decode(&hb("06014f"), 0), a4) { ok = false; }
  var a5 = Vec[Int].new();
  a5.push(2);
  a5.push(0);
  if !arcs_is(ber_oid_decode(&hb("060150"), 0), a5) { ok = false; }
  var a6 = Vec[Int].new();
  a6.push(2);
  a6.push(1);
  if !arcs_is(ber_oid_decode(&hb("060151"), 0), a6) { ok = false; }
  if !arcs_is(ber_oid_decode(&hb("06032b0601"), 0), oid4(1, 3, 6, 1)) { ok = false; }
  var a8 = Vec[Int].new();
  a8.push(1);
  a8.push(3);
  a8.push(128);
  if !arcs_is(ber_oid_decode(&hb("06032b8100"), 0), a8) { ok = false; }
  var a9 = Vec[Int].new();
  a9.push(1);
  a9.push(3);
  a9.push(16384);
  if !arcs_is(ber_oid_decode(&hb("06042b818000"), 0), a9) { ok = false; }
  var a10 = Vec[Int].new();
  a10.push(2);
  a10.push(4294967295);
  if !arcs_is(ber_oid_decode(&hb("0605908080804f"), 0), a10) { ok = false; }
  if !arcs_is_next(ber_oid_decode(&hb("06032b0601ff"), 0), oid4(1, 3, 6, 1), 5) { ok = false; }
  if !err_oid_is(ber_oid_decode(&hb("0600"), 0), eat("ber: empty oid", 0)) { ok = false; }
  if !err_oid_is(ber_oid_decode(&hb("060181"), 0), eat("ber: truncated oid subidentifier", 0)) { ok = false; }
  if !err_oid_is(ber_oid_decode(&hb("06032b8001"), 0), eat("ber: non-minimal oid subidentifier", 0)) { ok = false; }
  if !err_oid_is(ber_oid_decode(&hb("060cffffffffffffffffffffffffff"), 0), eat("ber: oid subidentifier overflow", 0)) { ok = false; }
  if !err_oid_is(ber_oid_decode(&hb("040100"), 0), eat("ber: tag mismatch", 0)) { ok = false; }
  return assert(ok, "OID decode: first-arc 0/1/2 split, multi-byte subidentifiers, empty/truncated/overlong");
}

fn t6() -> TestResult {
  var ok = bytes_is(ber_oid_encode(&oid4(1, 3, 6, 1)), hb("06032b0601"));
  var z = Vec[Int].new();
  z.push(0);
  z.push(0);
  if !bytes_is(ber_oid_encode(&z), hb("060100")) { ok = false; }
  var z2 = Vec[Int].new();
  z2.push(0);
  z2.push(39);
  if !bytes_is(ber_oid_encode(&z2), hb("060127")) { ok = false; }
  var z3 = Vec[Int].new();
  z3.push(1);
  z3.push(0);
  if !bytes_is(ber_oid_encode(&z3), hb("060128")) { ok = false; }
  var z4 = Vec[Int].new();
  z4.push(2);
  z4.push(0);
  if !bytes_is(ber_oid_encode(&z4), hb("060150")) { ok = false; }
  var z5 = Vec[Int].new();
  z5.push(2);
  z5.push(16384);
  if !bytes_is(ber_oid_encode(&z5), hb("0603818050")) { ok = false; }
  var z6 = Vec[Int].new();
  z6.push(2);
  z6.push(4294967295);
  if !bytes_is(ber_oid_encode(&z6), hb("0605908080804f")) { ok = false; }
  var z7 = Vec[Int].new();
  z7.push(1);
  z7.push(3);
  z7.push(128);
  if !bytes_is(ber_oid_encode(&z7), hb("06032b8100")) { ok = false; }
  var one = Vec[Int].new();
  one.push(1);
  if !err_bytes_is(ber_oid_encode(&one), "ber: oid needs two arcs") { ok = false; }
  var bad1 = Vec[Int].new();
  bad1.push(3);
  bad1.push(0);
  if !err_bytes_is(ber_oid_encode(&bad1), "ber: bad first oid arc") { ok = false; }
  var bad1b = Vec[Int].new();
  bad1b.push(-1);
  bad1b.push(0);
  if !err_bytes_is(ber_oid_encode(&bad1b), "ber: bad first oid arc") { ok = false; }
  var bad2 = Vec[Int].new();
  bad2.push(0);
  bad2.push(40);
  if !err_bytes_is(ber_oid_encode(&bad2), "ber: bad second oid arc") { ok = false; }
  var bad2b = Vec[Int].new();
  bad2b.push(2);
  bad2b.push(-1);
  if !err_bytes_is(ber_oid_encode(&bad2b), "ber: bad second oid arc") { ok = false; }
  var neg = Vec[Int].new();
  neg.push(1);
  neg.push(3);
  neg.push(-5);
  if !err_bytes_is(ber_oid_encode(&neg), "ber: negative oid arc") { ok = false; }
  let ot = oid_tlv(oid9(1, 3, 6, 1, 2, 1, 1, 1, 0));
  if !arcs_is(ber_oid_decode(&ot, 0), oid9(1, 3, 6, 1, 2, 1, 1, 1, 0)) { ok = false; }
  return assert(ok, "OID encode: X*40+Y combination, base-128 arcs, arc bounds, round-trip");
}

fn t7() -> TestResult {
  var ok = bint_is_next(ber_counter32_decode(&hb("4104ffffffff"), 0), 4294967295, 6);
  if !bint_is(ber_counter32_decode(&hb("41017f"), 0), 127) { ok = false; }
  if !bint_is(ber_counter32_decode(&hb("410500ffffffff"), 0), 4294967295) { ok = false; }
  if !bint_is(ber_gauge32_decode(&hb("42020100"), 0), 256) { ok = false; }
  if !bint_is(ber_timeticks_decode(&hb("430400010000"), 0), 65536) { ok = false; }
  if !bint_is(ber_timeticks_decode(&hb("43020100"), 0), 256) { ok = false; }
  if !bint_is(ber_counter64_decode(&hb("46087fffffffffffffff"), 0), 9223372036854775807) { ok = false; }
  if !bint_is(ber_counter64_decode(&hb("460105"), 0), 5) { ok = false; }
  let o1 = hb("41050100000000");
  if !err_bint_is(ber_counter32_decode(&o1, 0), eat("ber: value overflow", 0)) { ok = false; }
  if !err_bint_is(ber_counter32_decode(&hb("4100"), 0), eat("ber: empty integer", 0)) { ok = false; }
  if !err_bint_is(ber_gauge32_decode(&hb("4200"), 0), eat("ber: empty integer", 0)) { ok = false; }
  if !err_bint_is(ber_counter64_decode(&hb("46088000000000000000"), 0), eat("ber: value overflow", 0)) { ok = false; }
  if !err_bint_is(ber_counter64_decode(&hb("4609008000000000000000"), 0), eat("ber: value overflow", 0)) { ok = false; }
  if !err_bint_is(ber_counter64_decode(&hb("4600"), 0), eat("ber: empty integer", 0)) { ok = false; }
  if !err_bint_is(ber_counter32_decode(&hb("42020100"), 0), eat("ber: tag mismatch", 0)) { ok = false; }
  if !err_bint_is(ber_gauge32_decode(&hb("4104ffffffff"), 0), eat("ber: tag mismatch", 0)) { ok = false; }
  if !err_bint_is(ber_timeticks_decode(&hb("41017f"), 0), eat("ber: tag mismatch", 0)) { ok = false; }
  return assert(ok, "Counter32/Gauge32/TimeTicks/Counter64: unsigned decode, leading zero, overflow, tag mismatch");
}

fn t8() -> TestResult {
  var ok = bytes_equal(ber_int_encode(0), hb("020100"));
  if !bytes_equal(ber_int_encode(127), hb("02017f")) { ok = false; }
  if !bytes_equal(ber_int_encode(128), hb("02020080")) { ok = false; }
  if !bytes_equal(ber_int_encode(255), hb("020200ff")) { ok = false; }
  if !bytes_equal(ber_int_encode(256), hb("02020100")) { ok = false; }
  if !bytes_equal(ber_int_encode(-1), hb("0201ff")) { ok = false; }
  if !bytes_equal(ber_int_encode(-128), hb("020180")) { ok = false; }
  if !bytes_equal(ber_int_encode(-129), hb("0202ff7f")) { ok = false; }
  if !bytes_equal(ber_int_encode(-256), hb("0202ff00")) { ok = false; }
  if !bytes_equal(ber_int_encode(-9223372036854775808), hb("02088000000000000000")) { ok = false; }
  if !bytes_equal(ber_int_encode(9223372036854775807), hb("02087fffffffffffffff")) { ok = false; }
  var vals = Vec[Int].new();
  vals.push(0);
  vals.push(1);
  vals.push(-1);
  vals.push(127);
  vals.push(128);
  vals.push(-128);
  vals.push(-129);
  vals.push(72057594037927936);
  vals.push(-72057594037927936);
  vals.push(4294967295);
  var i = 0;
  while i < vals.len() {
    let x: Int = vals[i];
    let e = ber_int_encode(x);
    let r = ber_int_decode(&e, 0);
    if !bint_is(r, x) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "INTEGER encode: minimal two's complement bytes and decode round-trip");
}

fn t9() -> TestResult {
  let oid = oid9(1, 3, 6, 1, 2, 1, 1, 1, 0);
  let comm = bytes_of("public");
  let br = snmp_get_request_build(SNMP_VERSION_V2C, &comm, 1234, &oid);
  if !br.is_ok {
    return assert(false, "GetRequest build must succeed");
  }
  let built: Vec[UInt8] = br.value;
  var ok = bytes_equal(built, hb("302702010104067075626c6963a01a020204d2020100020100300e300c06082b060102010101000500"));
  if built.len() != 41 { ok = false; }
  let pr = snmp_message_parse(&built);
  if !pr.is_ok {
    ok = false;
  } else {
    let m: SnmpMessage = pr.value;
    if m.version != SNMP_VERSION_V2C { ok = false; }
    if m.pdu_tag != 160 { ok = false; }
    if m.pdu_kind != SNMP_PDU_GET_REQUEST { ok = false; }
    if m.request_id != 1234 { ok = false; }
    if m.error_status != 0 { ok = false; }
    if m.error_index != 0 { ok = false; }
    if m.non_repeaters != -1 { ok = false; }
    if m.max_repetitions != -1 { ok = false; }
    if m.next != built.len() { ok = false; }
    let mc: Vec[UInt8] = m.community;
    if !bytes_equal(mc, comm) { ok = false; }
    if snmp_varbind_count(&m) != 1 { ok = false; }
    let off = snmp_varbind_offset(&m, 0);
    let vbr = snmp_varbind_parse(&built, off);
    if !vbr.is_ok {
      ok = false;
    } else {
      let vb: SnmpVarBind = vbr.value;
      if !arcs_equal(vb.name, oid) { ok = false; }
      let pv: SnmpValue = vb.value;
      if pv.tag != SNMP_TAG_NULL { ok = false; }
      if pv.next != built.len() { ok = false; }
    }
  }
  return assert(ok, "GetRequest build: pinned 41 bytes, parse round-trip, NULL varbind value");
}

fn t10() -> TestResult {
  let oid = oid9(1, 3, 6, 1, 2, 1, 1, 3, 0);
  let comm = bytes_of("public");
  let v = mv(SNMP_TAG_INTEGER, -42, Vec[UInt8].new(), Vec[Int].new());
  let br = snmp_response_build(SNMP_VERSION_V2C, &comm, 7, &oid, &v);
  if !br.is_ok {
    return assert(false, "Response build must succeed");
  }
  let built: Vec[UInt8] = br.value;
  let pr = snmp_message_parse(&built);
  if !pr.is_ok {
    return assert(false, "Response must parse");
  }
  let m: SnmpMessage = pr.value;
  var ok = m.pdu_tag == 162;
  if m.pdu_kind != SNMP_PDU_RESPONSE { ok = false; }
  if m.request_id != 7 { ok = false; }
  if m.error_status != 0 { ok = false; }
  if m.error_index != 0 { ok = false; }
  if snmp_varbind_count(&m) != 1 { ok = false; }
  let off = snmp_varbind_offset(&m, 0);
  let vbr = snmp_varbind_parse(&built, off);
  if !vbr.is_ok {
    ok = false;
  } else {
    let vb: SnmpVarBind = vbr.value;
    if !arcs_equal(vb.name, oid) { ok = false; }
    let pv: SnmpValue = vb.value;
    if pv.tag != SNMP_TAG_INTEGER { ok = false; }
    if pv.int_val != -42 { ok = false; }
    let rebuilt = snmp_response_build(m.version, &comm, m.request_id, &oid, &pv);
    if !rebuilt.is_ok {
      ok = false;
    } else {
      let rb: Vec[UInt8] = rebuilt.value;
      if !bytes_equal(rb, built) { ok = false; }
    }
  }
  return assert(ok, "Response build: INTEGER -42 round-trips through parse and rebuild");
}

fn t11() -> TestResult {
  let oid = oid4(1, 3, 6, 1);
  var ok = value_roundtrip(mv(SNMP_TAG_INTEGER, -1, Vec[UInt8].new(), Vec[Int].new()), oid);
  if !value_roundtrip(mv(SNMP_TAG_OCTET_STRING, 0, hb("00ff4100"), Vec[Int].new()), oid) { ok = false; }
  if !value_roundtrip(mv(SNMP_TAG_NULL, 0, Vec[UInt8].new(), Vec[Int].new()), oid) { ok = false; }
  if !value_roundtrip(mv(SNMP_TAG_OID, 0, Vec[UInt8].new(), oid9(1, 3, 6, 1, 4, 1, 311, 1, 9)), oid) { ok = false; }
  if !value_roundtrip(mv(SNMP_TAG_IPADDRESS, 0, hb("c0000201"), Vec[Int].new()), oid) { ok = false; }
  if !value_roundtrip(mv(SNMP_TAG_COUNTER32, 4294967295, Vec[UInt8].new(), Vec[Int].new()), oid) { ok = false; }
  if !value_roundtrip(mv(SNMP_TAG_GAUGE32, 100000, Vec[UInt8].new(), Vec[Int].new()), oid) { ok = false; }
  if !value_roundtrip(mv(SNMP_TAG_TIMETICKS, 123456, Vec[UInt8].new(), Vec[Int].new()), oid) { ok = false; }
  if !value_roundtrip(mv(SNMP_TAG_OPAQUE, 0, hb("deadbeef"), Vec[Int].new()), oid) { ok = false; }
  if !value_roundtrip(mv(SNMP_TAG_COUNTER64, 9223372036854775807, Vec[UInt8].new(), Vec[Int].new()), oid) { ok = false; }
  return assert(ok, "every varbind value type round-trips through the Response builder (10 types)");
}

fn t12() -> TestResult {
  var ok = true;
  var kinds = Vec[Int].new();
  kinds.push(SNMP_PDU_GET_REQUEST);
  kinds.push(SNMP_PDU_GET_NEXT_REQUEST);
  kinds.push(SNMP_PDU_RESPONSE);
  kinds.push(SNMP_PDU_SET_REQUEST);
  kinds.push(SNMP_PDU_INFORM_REQUEST);
  kinds.push(SNMP_PDU_V2_TRAP);
  var i = 0;
  while i < kinds.len() {
    let k: Int = kinds[i];
    let msg = plain_msg(SNMP_VERSION_V2C, req_pdu(k));
    let pr = snmp_message_parse(&msg);
    if !pr.is_ok {
      ok = false;
    } else {
      let m: SnmpMessage = pr.value;
      if m.pdu_tag != snmp_pdu_tag(k) { ok = false; }
      if m.pdu_kind != k { ok = false; }
      if m.request_id != 5 { ok = false; }
      if m.error_status != 0 { ok = false; }
      if m.error_index != 0 { ok = false; }
      if m.non_repeaters != -1 { ok = false; }
      if m.max_repetitions != -1 { ok = false; }
      if snmp_varbind_count(&m) != 0 { ok = false; }
      if m.next != msg.len() { ok = false; }
    }
    i = i + 1;
  }
  let list = wrap(SNMP_TAG_SEQUENCE, Vec[UInt8].new());
  let bulk_body = req_body(5, 2, 10, list);
  let bulk = plain_msg(SNMP_VERSION_V2C, wrap(160 + SNMP_PDU_GET_BULK_REQUEST, bulk_body));
  let prb = snmp_message_parse(&bulk);
  if !prb.is_ok {
    ok = false;
  } else {
    let bm: SnmpMessage = prb.value;
    if bm.pdu_kind != SNMP_PDU_GET_BULK_REQUEST { ok = false; }
    if bm.non_repeaters != 2 { ok = false; }
    if bm.max_repetitions != 10 { ok = false; }
    if bm.error_status != -1 { ok = false; }
    if bm.error_index != -1 { ok = false; }
  }
  return assert(ok, "PDU tags 0xA0..0xA7: Get/GetNext/Response/Set/Inform/v2Trap plus GetBulk counters");
}

fn t13() -> TestResult {
  let msg = plain_msg(SNMP_VERSION_V1, trap_pdu());
  let pr = snmp_message_parse(&msg);
  if !pr.is_ok {
    return assert(false, "Trap v1 must parse");
  }
  let m: SnmpMessage = pr.value;
  var ok = m.version == SNMP_VERSION_V1;
  if m.pdu_tag != 164 { ok = false; }
  if m.pdu_kind != SNMP_PDU_TRAP_V1 { ok = false; }
  if m.request_id != -1 { ok = false; }
  if m.error_status != -1 { ok = false; }
  if m.error_index != -1 { ok = false; }
  if m.generic_trap != 6 { ok = false; }
  if m.specific_trap != 2 { ok = false; }
  if m.timestamp != 256 { ok = false; }
  let ent: Vec[Int] = m.enterprise;
  if !arcs_equal(ent, oid4(1, 3, 6, 1, 4)) { ok = false; }
  let addr: Vec[UInt8] = m.agent_addr;
  if !bytes_equal(addr, hb("c0000201")) { ok = false; }
  if snmp_varbind_count(&m) != 0 { ok = false; }
  return assert(ok, "Trap v1: enterprise/agent-addr/generic/specific/timestamp fields, no request-id");
}

fn t14() -> TestResult {
  let uptime = oid9(1, 3, 6, 1, 2, 1, 1, 3, 0);
  let vb1_body = concat2(oid_tlv(uptime), wrap(SNMP_TAG_TIMETICKS, hb("000100")));
  let vb1 = wrap(SNMP_TAG_SEQUENCE, vb1_body);
  let trap_oid_name = oid4(1, 3, 6, 1, 6);
  let trap_oid_value = oid4(1, 3, 6, 1);
  let vb2_body = concat2(oid_tlv(trap_oid_name), oid_tlv(trap_oid_value));
  let vb2 = wrap(SNMP_TAG_SEQUENCE, vb2_body);
  let list = wrap(SNMP_TAG_SEQUENCE, concat2(vb1, vb2));
  let pdu_body = req_body(99, 0, 0, list);
  let msg = plain_msg(SNMP_VERSION_V2C, wrap(160 + SNMP_PDU_V2_TRAP, pdu_body));
  let pr = snmp_message_parse(&msg);
  if !pr.is_ok {
    return assert(false, "SNMPv2-Trap with varbinds must parse");
  }
  let m: SnmpMessage = pr.value;
  var ok = m.pdu_kind == SNMP_PDU_V2_TRAP;
  if m.request_id != 99 { ok = false; }
  if snmp_varbind_count(&m) != 2 { ok = false; }
  let o0 = snmp_varbind_offset(&m, 0);
  let o1 = snmp_varbind_offset(&m, 1);
  if !(o0 < o1) { ok = false; }
  let vb1r = snmp_varbind_parse(&msg, o0);
  if !vb1r.is_ok {
    ok = false;
  } else {
    let b: SnmpVarBind = vb1r.value;
    if !arcs_equal(b.name, uptime) { ok = false; }
    let v: SnmpValue = b.value;
    if v.tag != SNMP_TAG_TIMETICKS { ok = false; }
    if v.int_val != 256 { ok = false; }
  }
  let vb2r = snmp_varbind_parse(&msg, o1);
  if !vb2r.is_ok {
    ok = false;
  } else {
    let b: SnmpVarBind = vb2r.value;
    if !arcs_equal(b.name, trap_oid_name) { ok = false; }
    let v: SnmpValue = b.value;
    if v.tag != SNMP_TAG_OID { ok = false; }
    if !arcs_equal(v.oid, trap_oid_value) { ok = false; }
  }
  return assert(ok, "SNMPv2-Trap: two varbinds with TimeTicks and OID values, ordered offsets");
}

fn t15() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = err_msg_is(snmp_message_parse(&empty), eat("ber: truncated tag", 0));
  let not_seq = hb("020101");
  if !err_msg_is(snmp_message_parse(&not_seq), eat("ber: tag mismatch", 0)) { ok = false; }
  let v_wrong_tag = wrap(SNMP_TAG_SEQUENCE, concat2(ber_octet_string_encode(&bytes_of("x")), concat2(ber_octet_string_encode(&empty), req_pdu(0))));
  if !err_msg_is(snmp_message_parse(&v_wrong_tag), eat("ber: tag mismatch", 2)) { ok = false; }
  let bad_version = plain_msg(2, req_pdu(0));
  if !err_msg_is(snmp_message_parse(&bad_version), eat("snmp: unsupported version", 2)) { ok = false; }
  let bad_pdu_a8 = plain_msg(1, hb("a800"));
  if !err_msg_is(snmp_message_parse(&bad_pdu_a8), eat("snmp: bad pdu tag", 13)) { ok = false; }
  let bad_pdu_30 = plain_msg(1, hb("3000"));
  if !err_msg_is(snmp_message_parse(&bad_pdu_30), eat("snmp: bad pdu tag", 13)) { ok = false; }
  let pdu = req_pdu(0);
  let trailing = wrap(SNMP_TAG_SEQUENCE, concat2(concat2(ber_int_encode(1), ber_octet_string_encode(&bytes_of("public"))), concat2(pdu, ber_int_encode(0))));
  if !err_msg_is(snmp_message_parse(&trailing), eat("snmp: trailing bytes", 26)) { ok = false; }
  let list = wrap(SNMP_TAG_SEQUENCE, Vec[UInt8].new());
  let pdu_trailing = wrap(160, concat2(req_body(5, 0, 0, list), ber_int_encode(9)));
  let msg_pdu_trailing = plain_msg(1, pdu_trailing);
  if !err_msg_is(snmp_message_parse(&msg_pdu_trailing), eat("snmp: trailing bytes", 26)) { ok = false; }
  let short_msg_body = concat2(concat2(ber_int_encode(1), ber_octet_string_encode(&empty)), hb("a004"));
  let short_msg = concat2(wrap(SNMP_TAG_SEQUENCE, short_msg_body), concat2(hb("3006"), repeat_byte(0, 6)));
  if !err_msg_is(snmp_message_parse(&short_msg), eat("ber: value overruns container", 7)) { ok = false; }
  let truncated_pdu = concat2(concat2(ber_int_encode(1), ber_octet_string_encode(&empty)), hb("a005"));
  let msg_truncated = wrap(SNMP_TAG_SEQUENCE, truncated_pdu);
  if !err_msg_is(snmp_message_parse(&msg_truncated), eat("ber: value overruns buffer", 7)) { ok = false; }
  return assert(ok, "malformed messages: top tag, version tag/value, PDU tag, trailing bytes, container/buffer overrun");
}

fn t16() -> TestResult {
  let varbind_not_seq = wrap(SNMP_TAG_SEQUENCE, wrap(0x31, Vec[UInt8].new()));
  let msg1 = msg_with_list(1, varbind_not_seq);
  var ok = err_msg_is(snmp_message_parse(&msg1), eat("ber: tag mismatch", 26));
  let name_not_oid = wrap(SNMP_TAG_SEQUENCE, wrap(SNMP_TAG_SEQUENCE, concat2(wrap(0x04, Vec[UInt8].new()), wrap(SNMP_TAG_NULL, Vec[UInt8].new()))));
  let msg2 = msg_with_list(1, name_not_oid);
  if !err_msg_is(snmp_message_parse(&msg2), eat("ber: tag mismatch", 28)) { ok = false; }
  let oid = oid4(1, 3, 6, 1);
  let bad_value = wrap(SNMP_TAG_SEQUENCE, wrap(SNMP_TAG_SEQUENCE, concat2(oid_tlv(oid), wrap(0x45, hb("00")))));
  let msg3 = msg_with_list(1, bad_value);
  if !err_msg_is(snmp_message_parse(&msg3), eat("ber: unsupported value tag", 33)) { ok = false; }
  let extra = wrap(SNMP_TAG_SEQUENCE, wrap(SNMP_TAG_SEQUENCE, concat2(concat2(oid_tlv(oid), wrap(SNMP_TAG_NULL, Vec[UInt8].new())), ber_int_encode(7))));
  let msg4 = msg_with_list(1, extra);
  if !err_msg_is(snmp_message_parse(&msg4), eat("snmp: trailing bytes", 35)) { ok = false; }
  let cut_oid = wrap(SNMP_TAG_SEQUENCE, concat2(hb("30040603"), concat2(hb("0500"), hb("000000"))));
  let msg5 = msg_with_list(1, cut_oid);
  if !err_msg_is(snmp_message_parse(&msg5), eat("ber: value overruns container", 28)) { ok = false; }
  return assert(ok, "malformed varbinds: not a SEQUENCE, bad name tag, unsupported value, trailing, name overrun");
}

fn t17() -> TestResult {
  var ok = bytes_is(snmp_value_encode(&mv(SNMP_TAG_INTEGER, 5, Vec[UInt8].new(), Vec[Int].new())), hb("020105"));
  if !bytes_is(snmp_value_encode(&mv(SNMP_TAG_OCTET_STRING, 0, hb("00ff4100"), Vec[Int].new())), hb("040400ff4100")) { ok = false; }
  if !bytes_is(snmp_value_encode(&mv(SNMP_TAG_NULL, 0, Vec[UInt8].new(), Vec[Int].new())), hb("0500")) { ok = false; }
  if !bytes_is(snmp_value_encode(&mv(SNMP_TAG_OID, 0, Vec[UInt8].new(), oid4(1, 3, 6, 1))), hb("06032b0601")) { ok = false; }
  if !bytes_is(snmp_value_encode(&mv(SNMP_TAG_IPADDRESS, 0, hb("c0000201"), Vec[Int].new())), hb("4004c0000201")) { ok = false; }
  if !bytes_is(snmp_value_encode(&mv(SNMP_TAG_COUNTER32, 4294967295, Vec[UInt8].new(), Vec[Int].new())), hb("4104ffffffff")) { ok = false; }
  if !bytes_is(snmp_value_encode(&mv(SNMP_TAG_GAUGE32, 100000, Vec[UInt8].new(), Vec[Int].new())), hb("42030186a0")) { ok = false; }
  if !bytes_is(snmp_value_encode(&mv(SNMP_TAG_TIMETICKS, 256, Vec[UInt8].new(), Vec[Int].new())), hb("43020100")) { ok = false; }
  if !bytes_is(snmp_value_encode(&mv(SNMP_TAG_OPAQUE, 0, hb("dead"), Vec[Int].new())), hb("4402dead")) { ok = false; }
  if !bytes_is(snmp_value_encode(&mv(SNMP_TAG_COUNTER64, 5, Vec[UInt8].new(), Vec[Int].new())), hb("460105")) { ok = false; }
  let bad_tag = mv(0x99, 0, Vec[UInt8].new(), Vec[Int].new());
  if !err_bytes_is(snmp_value_encode(&bad_tag), "ber: unsupported value tag") { ok = false; }
  let bad_ip = mv(SNMP_TAG_IPADDRESS, 0, hb("c00002"), Vec[Int].new());
  if !err_bytes_is(snmp_value_encode(&bad_ip), "ber: bad ipaddress") { ok = false; }
  let neg_u = mv(SNMP_TAG_COUNTER32, -1, Vec[UInt8].new(), Vec[Int].new());
  if !err_bytes_is(snmp_value_encode(&neg_u), "ber: negative unsigned value") { ok = false; }
  let big_u = mv(SNMP_TAG_GAUGE32, 4294967296, Vec[UInt8].new(), Vec[Int].new());
  if !err_bytes_is(snmp_value_encode(&big_u), "ber: value too large") { ok = false; }
  var one = Vec[Int].new();
  one.push(1);
  let bad_oid = mv(SNMP_TAG_OID, 0, Vec[UInt8].new(), one);
  if !err_bytes_is(snmp_value_encode(&bad_oid), "ber: oid needs two arcs") { ok = false; }
  if !bytes_equal(ber_length_encode(0), hb("00")) { ok = false; }
  if !bytes_equal(ber_length_encode(127), hb("7f")) { ok = false; }
  if !bytes_equal(ber_length_encode(128), hb("8180")) { ok = false; }
  if !bytes_equal(ber_length_encode(300), hb("82012c")) { ok = false; }
  if !bytes_equal(ber_length_encode(-1), Vec[UInt8].new()) { ok = false; }
  if !err_bytes_is(ber_uint_encode(3, SNMP_TAG_INTEGER), "ber: bad unsigned tag") { ok = false; }
  if !err_bytes_is(ber_uint_encode(-1, SNMP_TAG_COUNTER32), "ber: negative unsigned value") { ok = false; }
  if !err_bytes_is(ber_uint_encode(4294967296, SNMP_TAG_GAUGE32), "ber: value too large") { ok = false; }
  if !bytes_is(ber_uint_encode(4294967295, SNMP_TAG_COUNTER32), hb("4104ffffffff")) { ok = false; }
  if !bytes_is(ber_uint_encode(0, SNMP_TAG_COUNTER64), hb("460100")) { ok = false; }
  return assert(ok, "value/length encoders: pinned bytes, negative/overflow/tag errors");
}

fn t18() -> TestResult {
  let comm = hb("00ff807f41");
  let oid = oid4(1, 3, 6, 1);
  let br = snmp_get_request_build(SNMP_VERSION_V1, &comm, 1, &oid);
  if !br.is_ok {
    return assert(false, "v1 GetRequest with binary community must build");
  }
  let built: Vec[UInt8] = br.value;
  let pr = snmp_message_parse(&built);
  if !pr.is_ok {
    return assert(false, "v1 message with binary community must parse");
  }
  let m: SnmpMessage = pr.value;
  var ok = m.version == SNMP_VERSION_V1;
  let mc: Vec[UInt8] = m.community;
  if !bytes_equal(mc, comm) { ok = false; }
  if m.community_length != 5 { ok = false; }
  if m.community_offset != 7 { ok = false; }
  if snmp_varbind_count(&m) != 1 { ok = false; }
  let zeros = hb("000000");
  let null_v = mv(SNMP_TAG_NULL, 0, Vec[UInt8].new(), Vec[Int].new());
  let br2 = snmp_response_build(SNMP_VERSION_V2C, &zeros, 2, &oid, &null_v);
  if !br2.is_ok {
    ok = false;
  } else {
    let built2: Vec[UInt8] = br2.value;
    let pr2 = snmp_message_parse(&built2);
    if !pr2.is_ok {
      ok = false;
    } else {
      let m2: SnmpMessage = pr2.value;
      let mc2: Vec[UInt8] = m2.community;
      if !bytes_equal(mc2, zeros) { ok = false; }
      if m2.community_length != 3 { ok = false; }
    }
  }
  return assert(ok, "community is raw bytes (0x00/0xFF/NUL) and survives build/parse");
}

fn t19() -> TestResult {
  var ok = snmp_pdu_tag(0) == 160;
  if snmp_pdu_tag(7) != 167 { ok = false; }
  if snmp_pdu_tag(-1) != -1 { ok = false; }
  if snmp_pdu_tag(8) != -1 { ok = false; }
  if snmp_pdu_kind(160) != 0 { ok = false; }
  if snmp_pdu_kind(167) != 7 { ok = false; }
  if snmp_pdu_kind(159) != -1 { ok = false; }
  if snmp_pdu_kind(168) != -1 { ok = false; }
  if snmp_pdu_kind(48) != -1 { ok = false; }
  let oid = oid4(1, 3, 6, 1);
  let vb1 = wrap(SNMP_TAG_SEQUENCE, concat2(oid_tlv(oid), wrap(SNMP_TAG_NULL, Vec[UInt8].new())));
  let vb2 = wrap(SNMP_TAG_SEQUENCE, concat2(oid_tlv(oid), ber_int_encode(3)));
  let list = wrap(SNMP_TAG_SEQUENCE, concat2(vb1, vb2));
  let msg = msg_with_list(1, list);
  let pr = snmp_message_parse(&msg);
  if !pr.is_ok {
    return assert(false, "two-varbind message must parse");
  }
  let m: SnmpMessage = pr.value;
  if snmp_varbind_count(&m) != 2 { ok = false; }
  let o0 = snmp_varbind_offset(&m, 0);
  let o1 = snmp_varbind_offset(&m, 1);
  if !(o0 >= 0) { ok = false; }
  if !(o1 > o0) { ok = false; }
  if snmp_varbind_offset(&m, -1) != -1 { ok = false; }
  if snmp_varbind_offset(&m, 2) != -1 { ok = false; }
  if snmp_varbind_offset(&m, 100) != -1 { ok = false; }
  let empty_msg = plain_msg(1, req_pdu(0));
  let er = snmp_message_parse(&empty_msg);
  if !er.is_ok {
    ok = false;
  } else {
    let em: SnmpMessage = er.value;
    if snmp_varbind_count(&em) != 0 { ok = false; }
    if snmp_varbind_offset(&em, 0) != -1 { ok = false; }
  }
  return assert(ok, "accessors: pdu tag/kind mapping guards and varbind count/offset bounds");
}

fn main() -> Int {
  io.println("=== xiom.snmp conformance tests ===");
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
    io.println("xiom.snmp: all tests passed");
  } else {
    io.println("xiom.snmp: tests failed");
  }
  return failed;
}


