// XIOM -- xiom.bonjour conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the 12-byte mDNS header (encode, decode,
// masking, truncation), domain names (pinned DNS-SD encodings, label and
// total-length boundaries, printable-byte validation, compression pointers
// including chains, loops and out-of-range targets, compression on encode
// against a prior-name table), questions, the class cache-flush /
// unicast-response bit, generic resource records, the PTR/SRV/TXT/A/AAAA
// RDATA layouts and their builders, TXT key=value lists, the DNS-SD names
// (enumeration, service type, instance, subtype, local checks), the
// advertise / browse / query builders and whole-message parsing including a
// pointer-compressed owner name.
//
// Str values are compared with str_compare (BUG 17 discipline: `==` on Str
// values read from Vec[Str] elements lowers to a pointer comparison); Vec
// elements are read into typed locals first. No test does table-driven
// Vec[fn] dispatch: every test is called directly from main.
//
// Fixture bytes are assembled from this file's own hex strings, so the
// decoder is exercised against bytes the tests control.

module bonjour_tests
use xiom.io; use xiom.test;
use xiom.bonjour;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Helpers (independent of src/bonjour.xi)
// --------------------------------------------------

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.value;
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

fn err_header_is(r: Result[BonjourHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_name_is(r: Result[BonjourName, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_labels_is(r: Result[Vec[Str], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_question_is(r: Result[BonjourQuestion, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_record_is(r: Result[BonjourRecord, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_message_is(r: Result[BonjourMessage, Str], want: Str) -> Bool {
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

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
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

// Encoded name bytes, or an empty vector on error (callers compare bytes,
// so a safe empty result fails the check).
fn enc(name: Str) -> Vec[UInt8] {
  let r = bonjour_name_encode(name);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.value;
  return v;
}

// A Str holding exactly the two given bytes (for non-printable tests).
fn str_two_bytes(a: Int, b: Int) -> Str {
  var sb = builder.sb_new();
  sb.push(a as UInt8);
  sb.push(b as UInt8);
  return builder.sb_to_str(&sb);
}

// One wire label: length byte + bytes (for long decode fixtures).
fn label_wire(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = s.len();
  out.push(n as UInt8);
  var i = 0;
  while i < n {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// A four-label name whose encoded wire length is sum(1 + label) + 1; used
// to pin the 255-byte upper bound.
fn long_name(label_len: Int, last_len: Int) -> Str {
  let a = string.str_repeat("a", label_len);
  let b = string.str_repeat("b", label_len);
  let c = string.str_repeat("c", label_len);
  let d = string.str_repeat("d", last_len);
  return a + "." + b + "." + c + "." + d;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let h = BonjourHeader{
    id: 4660;
    qr: 1;
    opcode: 0;
    aa: 1;
    tc: 0;
    rd: 0;
    ra: 0;
    z: 0;
    rcode: 0;
    qdcount: 0;
    ancount: 3;
    nscount: 0;
    arcount: 0;
  };
  let b = bonjour_header_encode(&h);
  var ok = b.len() == 12;
  if !bytes_equal(b, hb("123484000000000300000000")) { ok = false; }
  let ff = hb("ffffffffffffffffffffffff");
  let r = bonjour_header_decode(&ff);
  if !r.is_ok { return assert(false, "all-ones header must decode"); }
  let hd: BonjourHeader = r.value;
  if hd.id != 65535 { ok = false; }
  if hd.qr != 1 { ok = false; }
  if hd.opcode != 15 { ok = false; }
  if hd.aa != 1 { ok = false; }
  if hd.tc != 1 { ok = false; }
  if hd.rd != 1 { ok = false; }
  if hd.ra != 1 { ok = false; }
  if hd.z != 7 { ok = false; }
  if hd.rcode != 15 { ok = false; }
  if hd.qdcount != 65535 { ok = false; }
  if hd.ancount != 65535 { ok = false; }
  if hd.nscount != 65535 { ok = false; }
  if hd.arcount != 65535 { ok = false; }
  let zeros = hb("000000000000000000000000");
  let rz = bonjour_header_decode(&zeros);
  if !rz.is_ok {
    ok = false;
  } else {
    let hz: BonjourHeader = rz.value;
    if hz.id != 0 { ok = false; }
    if hz.qr != 0 { ok = false; }
    if hz.opcode != 0 { ok = false; }
    if hz.qdcount != 0 { ok = false; }
  }
  let short = hb("0000000000000000000000");
  if !err_header_is(bonjour_header_decode(&short), "bonjour: truncated header") { ok = false; }
  let hm = BonjourHeader{
    id: 65543;
    qr: 3;
    opcode: 20;
    aa: 2;
    tc: 0;
    rd: 0;
    ra: 0;
    z: 9;
    rcode: 16;
    qdcount: 65537;
    ancount: 0;
    nscount: 0;
    arcount: 0;
  };
  let bm = bonjour_header_encode(&hm);
  if !bytes_equal(bm, hb("0007a0100001000000000000")) { ok = false; }
  return assert(ok, "header encode/decode pins flags, counts, masking and truncation");
}

fn t2() -> TestResult {
  var ok = bytes_equal(enc("_http._tcp.local"), hb("055f68747470045f746370056c6f63616c00"));
  if !bytes_equal(enc("_http._tcp.local."), hb("055f68747470045f746370056c6f63616c00")) { ok = false; }
  if !bytes_equal(enc(""), hb("00")) { ok = false; }
  if !bytes_equal(enc("."), hb("00")) { ok = false; }
  if !bytes_equal(enc("local"), hb("056c6f63616c00")) { ok = false; }
  if !bytes_equal(enc(bonjour_service_enum_name()), hb("095f7365727669636573075f646e732d7364045f756470056c6f63616c00")) { ok = false; }
  return assert(ok, "name encode pins DNS-SD names, trailing dot and root");
}

fn t3() -> TestResult {
  var ok = err_bytes_is(bonjour_name_encode("a..b"), "bonjour: empty label");
  if !err_bytes_is(bonjour_name_encode(".a"), "bonjour: empty label") { ok = false; }
  if !err_bytes_is(bonjour_name_encode("a.b.."), "bonjour: empty label") { ok = false; }
  if !err_bytes_is(bonjour_name_encode(string.str_repeat("a", 64)), "bonjour: label too long") { ok = false; }
  if !err_bytes_is(bonjour_name_encode(long_name(63, 62)), "bonjour: name too long") { ok = false; }
  let r255 = bonjour_name_encode(long_name(63, 61));
  if !r255.is_ok {
    ok = false;
  } else {
    let v: Vec[UInt8] = r255.value;
    if v.len() != 255 { ok = false; }
  }
  let bad = str_two_bytes(97, 127);
  if !err_bytes_is(bonjour_name_encode(bad), "bonjour: label not printable") { ok = false; }
  let badlow = str_two_bytes(97, 9);
  if !err_bytes_is(bonjour_name_encode(badlow), "bonjour: label not printable") { ok = false; }
  return assert(ok, "name encode boundaries and non-printable labels");
}

fn t4() -> TestResult {
  let data = hb("095f7365727669636573075f646e732d7364045f756470056c6f63616c00");
  let r = bonjour_name_decode(&data, 0);
  if !r.is_ok { return assert(false, "name decode must succeed"); }
  let nm: BonjourName = r.value;
  var ok = nm.labels.len() == 4;
  if nm.next != data.len() { ok = false; }
  if nm.compressed { ok = false; }
  if !str_eq(bonjour_name_to_str(&nm), "_services._dns-sd._udp.local") { ok = false; }
  let pre = concat_bytes(hb("aabb"), hb("056c6f63616c00"));
  let r2 = bonjour_name_decode(&pre, 2);
  if !r2.is_ok {
    ok = false;
  } else {
    let nm2: BonjourName = r2.value;
    if !str_eq(bonjour_name_to_str(&nm2), "local") { ok = false; }
    if nm2.next != pre.len() { ok = false; }
  }
  let root = hb("00");
  let r3 = bonjour_name_decode(&root, 0);
  if !r3.is_ok {
    ok = false;
  } else {
    let nm3: BonjourName = r3.value;
    if nm3.labels.len() != 0 { ok = false; }
    if nm3.next != 1 { ok = false; }
  }
  return assert(ok, "name decode labels, next, root and non-zero offset");
}

fn t5() -> TestResult {
  let a = hb("076578616d706c6503636f6d00");
  let d1 = concat_bytes(a, hb("c000"));
  let r1 = bonjour_name_decode(&d1, 13);
  if !r1.is_ok { return assert(false, "pointer decode must succeed"); }
  let n1: BonjourName = r1.value;
  var ok = str_eq(bonjour_name_to_str(&n1), "example.com");
  if n1.next != 15 { ok = false; }
  if !n1.compressed { ok = false; }
  let d2 = concat_bytes(concat_bytes(a, hb("c000")), hb("c00d"));
  let r2 = bonjour_name_decode(&d2, 15);
  if !r2.is_ok {
    ok = false;
  } else {
    let n2: BonjourName = r2.value;
    if !str_eq(bonjour_name_to_str(&n2), "example.com") { ok = false; }
    if n2.next != 17 { ok = false; }
  }
  let d3 = concat_bytes(a, hb("c00c"));
  let r3 = bonjour_name_decode(&d3, 13);
  if !r3.is_ok {
    ok = false;
  } else {
    let n3: BonjourName = r3.value;
    if n3.labels.len() != 0 { ok = false; }
    if n3.next != 15 { ok = false; }
    if !n3.compressed { ok = false; }
  }
  return assert(ok, "compression pointer and pointer-to-pointer chain");
}

fn t6() -> TestResult {
  var ok = true;
  let tr = hb("");
  if !err_name_is(bonjour_name_decode(&tr, 0), "bonjour: truncated name") { ok = false; }
  let p1 = hb("c0");
  if !err_name_is(bonjour_name_decode(&p1, 0), "bonjour: truncated name") { ok = false; }
  let p2 = hb("036162");
  if !err_name_is(bonjour_name_decode(&p2, 0), "bonjour: truncated label") { ok = false; }
  let p3 = hb("03616263");
  if !err_name_is(bonjour_name_decode(&p3, 0), "bonjour: truncated name") { ok = false; }
  let p4 = hb("40");
  if !err_name_is(bonjour_name_decode(&p4, 0), "bonjour: unsupported label type") { ok = false; }
  let p5 = hb("80");
  if !err_name_is(bonjour_name_decode(&p5, 0), "bonjour: unsupported label type") { ok = false; }
  let p6 = hb("c009");
  if !err_name_is(bonjour_name_decode(&p6, 0), "bonjour: pointer out of range") { ok = false; }
  let p7 = hb("c002c000");
  if !err_name_is(bonjour_name_decode(&p7, 0), "bonjour: compression loop") { ok = false; }
  let p8 = hb("00");
  if !err_name_is(bonjour_name_decode(&p8, -1), "bonjour: negative offset") { ok = false; }
  let p9 = hb("0100");
  if !err_name_is(bonjour_name_decode(&p9, 0), "bonjour: label contains NUL byte") { ok = false; }
  let pa = hb("011f");
  if !err_name_is(bonjour_name_decode(&pa, 0), "bonjour: label not printable") { ok = false; }
  var big = Vec[UInt8].new();
  var i = 0;
  while i < 4 {
    big = concat_bytes(big, label_wire(string.str_repeat("a", 63)));
    i = i + 1;
  }
  big = concat_bytes(big, hb("00"));
  if !err_name_is(bonjour_name_decode(&big, 0), "bonjour: name too long") { ok = false; }
  return assert(ok, "name decode error catalog");
}

fn t7() -> TestResult {
  var names = Vec[Str].new();
  names.push("_http._tcp.local");
  var offs = Vec[Int].new();
  offs.push(12);
  let r1 = bonjour_name_encode_compressed("Office._http._tcp.local", &names, &offs);
  if !r1.is_ok { return assert(false, "compressed encode must succeed"); }
  let b1: Vec[UInt8] = r1.value;
  var ok = bytes_equal(b1, hb("064f6666696365c00c"));
  let r2 = bonjour_name_encode_compressed("printer._ipp._tcp.local", &names, &offs);
  if !r2.is_ok {
    ok = false;
  } else {
    let b2: Vec[UInt8] = r2.value;
    if !bytes_equal(b2, enc("printer._ipp._tcp.local")) { ok = false; }
  }
  var offs2 = Vec[Int].new();
  offs2.push(16384);
  let r3 = bonjour_name_encode_compressed("Office._http._tcp.local", &names, &offs2);
  if !r3.is_ok {
    ok = false;
  } else {
    let b3: Vec[UInt8] = r3.value;
    if !bytes_equal(b3, enc("Office._http._tcp.local")) { ok = false; }
  }
  let prior = hb("055f68747470045f746370056c6f63616c00");
  let joined = concat_bytes(concat_bytes(hb("000000000000000000000000"), prior), b1);
  let rd = bonjour_name_decode(&joined, 30);
  if !rd.is_ok {
    ok = false;
  } else {
    let nd: BonjourName = rd.value;
    if !str_eq(bonjour_name_to_str(&nd), "Office._http._tcp.local") { ok = false; }
    if !nd.compressed { ok = false; }
  }
  return assert(ok, "compression encode against a prior-name table");
}

fn t8() -> TestResult {
  let r = bonjour_question_encode("_http._tcp.local", 12, 1);
  if !r.is_ok { return assert(false, "question encode must succeed"); }
  let b: Vec[UInt8] = r.value;
  var ok = bytes_equal(b, hb("055f68747470045f746370056c6f63616c00000c0001"));
  let r2 = bonjour_question_encode("_http._tcp.local", 65537, 65536);
  if !r2.is_ok {
    ok = false;
  } else {
    let b2: Vec[UInt8] = r2.value;
    if !bytes_equal(b2, hb("055f68747470045f746370056c6f63616c0000010000")) { ok = false; }
  }
  let parsed = bonjour_question_parse(&b, 0);
  if !parsed.is_ok {
    ok = false;
  } else {
    let q: BonjourQuestion = parsed.value;
    if q.qtype != 12 { ok = false; }
    if q.qclass != 1 { ok = false; }
    if q.next != b.len() { ok = false; }
    let nm = q.name;
    if !str_eq(bonjour_name_to_str(&nm), "_http._tcp.local") { ok = false; }
  }
  let noq = hb("055f68747470045f746370056c6f63616c00");
  if !err_question_is(bonjour_question_parse(&noq, 0), "bonjour: truncated question") { ok = false; }
  if !err_question_is(bonjour_question_parse(&b, -1), "bonjour: negative offset") { ok = false; }
  return assert(ok, "question encode/parse with masking and truncation");
}

fn t9() -> TestResult {
  var ok = bonjour_class_value(false) == 1;
  if bonjour_class_value(true) != 32769 { ok = false; }
  if bonjour_class_base(32769) != 1 { ok = false; }
  if !bonjour_class_unicast(32769) { ok = false; }
  if bonjour_class_unicast(1) { ok = false; }
  if !bonjour_class_flush(32769) { ok = false; }
  if bonjour_class_flush(1) { ok = false; }
  return assert(ok, "class top bit: cache-flush and unicast-response");
}

fn t10() -> TestResult {
  let rd = hb("c0000201");
  let r = bonjour_rr_encode("host.local", 1, 1, 300, &rd);
  if !r.is_ok { return assert(false, "rr encode must succeed"); }
  let b: Vec[UInt8] = r.value;
  var ok = bytes_equal(b, hb("04686f7374056c6f63616c00000100010000012c0004c0000201"));
  let pr = bonjour_rr_parse(&b, 0);
  if !pr.is_ok { return assert(false, "rr parse must succeed"); }
  let rec: BonjourRecord = pr.value;
  if rec.rtype != 1 { ok = false; }
  if rec.rclass != 1 { ok = false; }
  if rec.ttl != 300 { ok = false; }
  if rec.rdata_length != 4 { ok = false; }
  if rec.rdata_offset != 22 { ok = false; }
  if rec.next != b.len() { ok = false; }
  let got = bonjour_rr_rdata(&b, &rec);
  if !got.is_ok {
    ok = false;
  } else {
    let gv: Vec[UInt8] = got.value;
    if !bytes_equal(gv, rd) { ok = false; }
  }
  let nameonly = hb("056c6f63616c00");
  if !err_record_is(bonjour_rr_parse(&nameonly, 0), "bonjour: truncated record") { ok = false; }
  let rdlarge = hb("056c6f63616c00000100010000012c00ff00");
  if !err_record_is(bonjour_rr_parse(&rdlarge, 0), "bonjour: truncated rdata") { ok = false; }
  if !err_record_is(bonjour_rr_parse(&b, -2), "bonjour: negative offset") { ok = false; }
  let short = prefix(b, 20);
  if !err_bytes_is(bonjour_rr_rdata(&short, &rec), "bonjour: rdata out of range") { ok = false; }
  return assert(ok, "resource record encode/parse, rdata span and truncation");
}

fn t11() -> TestResult {
  let r = bonjour_rdata_ptr("Office._http._tcp.local");
  if !r.is_ok { return assert(false, "ptr rdata must build"); }
  let rd: Vec[UInt8] = r.value;
  var ok = bytes_equal(rd, hb("064f6666696365055f68747470045f746370056c6f63616c00"));
  let owner = hb("055f68747470045f746370056c6f63616c00");
  let full = concat_bytes(owner, rd);
  let t = bonjour_rdata_ptr_target(&full, 18, rd.len());
  if !t.is_ok {
    ok = false;
  } else {
    let s: Str = t.value;
    if !str_eq(s, "Office._http._tcp.local") { ok = false; }
  }
  if !err_str_is(bonjour_rdata_ptr_target(&full, 18, 0), "bonjour: bad PTR rdata") { ok = false; }
  if !err_str_is(bonjour_rdata_ptr_target(&full, 18, 3), "bonjour: bad rdata name") { ok = false; }
  let er = bonjour_enum_rdata("_http._tcp.local");
  if !er.is_ok {
    ok = false;
  } else {
    let eb: Vec[UInt8] = er.value;
    if !bytes_equal(eb, enc("_http._tcp.local")) { ok = false; }
  }
  if !err_bytes_is(bonjour_enum_rdata("_http._tcp.example.com"), "bonjour: not a local domain") { ok = false; }
  return assert(ok, "PTR RDATA build/parse and enumeration rdata");
}

fn t12() -> TestResult {
  let r = bonjour_rdata_srv(0, 0, 8080, "myhost.local");
  if !r.is_ok { return assert(false, "srv rdata must build"); }
  let rd: Vec[UInt8] = r.value;
  var ok = bytes_equal(rd, hb("000000001f90066d79686f7374056c6f63616c00"));
  let full = concat_bytes(hb("aabbccddeeff"), rd);
  let pp = bonjour_rdata_srv_port(&full, 6, rd.len());
  if !pp.is_ok {
    ok = false;
  } else {
    let v: Int = pp.value;
    if v != 8080 { ok = false; }
  }
  let pw = bonjour_rdata_srv_weight(&full, 6, rd.len());
  if !pw.is_ok {
    ok = false;
  } else {
    let v: Int = pw.value;
    if v != 0 { ok = false; }
  }
  let tgt = bonjour_rdata_srv_target(&full, 6, rd.len());
  if !tgt.is_ok {
    ok = false;
  } else {
    let nm: BonjourName = tgt.value;
    if !str_eq(bonjour_name_to_str(&nm), "myhost.local") { ok = false; }
  }
  if !err_int_is(bonjour_rdata_srv_priority(&full, 6, 6), "bonjour: bad SRV rdata") { ok = false; }
  if !err_name_is(bonjour_rdata_srv_target(&full, 6, 6), "bonjour: bad SRV rdata") { ok = false; }
  let rm = bonjour_rdata_srv(65537, 2, 3, "x.local");
  if !rm.is_ok {
    ok = false;
  } else {
    let m: Vec[UInt8] = rm.value;
    let mp = prefix(m, 6);
    if !bytes_equal(mp, hb("000100020003")) { ok = false; }
  }
  return assert(ok, "SRV RDATA layout, parsers and masking");
}

fn t13() -> TestResult {
  var pairs = Vec[Str].new();
  pairs.push("txtvers=1");
  pairs.push("path=/");
  let r = bonjour_rdata_txt(&pairs);
  if !r.is_ok { return assert(false, "txt rdata must build"); }
  let rd: Vec[UInt8] = r.value;
  var ok = bytes_equal(rd, hb("09747874766572733d3106706174683d2f"));
  let pr = bonjour_rdata_txt_parse(&rd);
  if !pr.is_ok {
    ok = false;
  } else {
    let list: Vec[Str] = pr.value;
    if list.len() != 2 { ok = false; }
    let a: Str = list[0];
    let b: Str = list[1];
    if !str_eq(a, "txtvers=1") { ok = false; }
    if !str_eq(b, "path=/") { ok = false; }
  }
  let zr = hb("00");
  let z = bonjour_rdata_txt_parse(&zr);
  if !z.is_ok {
    ok = false;
  } else {
    let zl: Vec[Str] = z.value;
    if zl.len() != 1 { ok = false; }
    let z0: Str = zl[0];
    if z0.len() != 0 { ok = false; }
  }
  let trun = hb("05616263");
  if !err_labels_is(bonjour_rdata_txt_parse(&trun), "bonjour: truncated TXT string") { ok = false; }
  let np = hb("011f");
  if !err_labels_is(bonjour_rdata_txt_parse(&np), "bonjour: TXT byte not printable") { ok = false; }
  var longp = Vec[Str].new();
  longp.push(string.str_repeat("a", 256));
  if !err_bytes_is(bonjour_rdata_txt(&longp), "bonjour: TXT string too long") { ok = false; }
  return assert(ok, "TXT RDATA build/parse, empty and truncated strings");
}

fn t14() -> TestResult {
  var ok = true;
  let p1 = bonjour_txt_pair("txtvers", "1");
  if !p1.is_ok {
    ok = false;
  } else {
    let s1: Str = p1.value;
    if !str_eq(s1, "txtvers=1") { ok = false; }
  }
  let p2 = bonjour_txt_pair("secure", "");
  if !p2.is_ok {
    ok = false;
  } else {
    let s2: Str = p2.value;
    if !str_eq(s2, "secure") { ok = false; }
  }
  if !err_str_is(bonjour_txt_pair("", "x"), "bonjour: empty TXT key") { ok = false; }
  if !err_str_is(bonjour_txt_pair("a=b", "x"), "bonjour: TXT key contains '='") { ok = false; }
  let badkey = str_two_bytes(97, 9);
  if !err_str_is(bonjour_txt_pair(badkey, "x"), "bonjour: TXT byte not printable") { ok = false; }
  var pairs = Vec[Str].new();
  pairs.push("txtvers=1");
  pairs.push("secure");
  pairs.push("path=/");
  let g1 = bonjour_txt_get(&pairs, "txtvers");
  if !g1.is_ok {
    ok = false;
  } else {
    let v: Str = g1.value;
    if !str_eq(v, "1") { ok = false; }
  }
  let g2 = bonjour_txt_get(&pairs, "secure");
  if !g2.is_ok {
    ok = false;
  } else {
    let v: Str = g2.value;
    if v.len() != 0 { ok = false; }
  }
  let g3 = bonjour_txt_get(&pairs, "path");
  if !g3.is_ok {
    ok = false;
  } else {
    let v: Str = g3.value;
    if !str_eq(v, "/") { ok = false; }
  }
  if !err_str_is(bonjour_txt_get(&pairs, "missing"), "bonjour: TXT key not found") { ok = false; }
  return assert(ok, "TXT key=value pairs and lookups");
}

fn t15() -> TestResult {
  var ok = true;
  let a4 = hb("c0000201");
  let ra = bonjour_rdata_a(&a4);
  if !ra.is_ok {
    ok = false;
  } else {
    let a: Vec[UInt8] = ra.value;
    if !bytes_equal(a, a4) { ok = false; }
    let sa = bonjour_rdata_a_to_str(&a);
    if !sa.is_ok {
      ok = false;
    } else {
      let s: Str = sa.value;
      if !str_eq(s, "192.0.2.1") { ok = false; }
    }
  }
  let bad4 = hb("c00002");
  if !err_bytes_is(bonjour_rdata_a(&bad4), "bonjour: bad A rdata") { ok = false; }
  if !err_str_is(bonjour_rdata_a_to_str(&bad4), "bonjour: bad A rdata") { ok = false; }
  let a16 = hb("20010db8000000000000000000000001");
  let r6 = bonjour_rdata_aaaa(&a16);
  if !r6.is_ok {
    ok = false;
  } else {
    let v6: Vec[UInt8] = r6.value;
    let s6 = bonjour_rdata_aaaa_to_str(&v6);
    if !s6.is_ok {
      ok = false;
    } else {
      let s: Str = s6.value;
      if !str_eq(s, "2001:db8:0:0:0:0:0:1") { ok = false; }
    }
  }
  let bad6 = hb("2001");
  if !err_bytes_is(bonjour_rdata_aaaa(&bad6), "bonjour: bad AAAA rdata") { ok = false; }
  return assert(ok, "A/AAAA RDATA builders and renderers");
}

fn t16() -> TestResult {
  var ok = true;
  let st = bonjour_service_type_name("http", "_tcp");
  if !st.is_ok {
    ok = false;
  } else {
    let s: Str = st.value;
    if !str_eq(s, "_http._tcp.local") { ok = false; }
  }
  let st2 = bonjour_service_type_name("_ipp", "udp");
  if !st2.is_ok {
    ok = false;
  } else {
    let s2: Str = st2.value;
    if !str_eq(s2, "_ipp._udp.local") { ok = false; }
  }
  let st3 = bonjour_service_type("_HTTP", "TCP", "LOCAL");
  if !st3.is_ok {
    ok = false;
  } else {
    let s3: Str = st3.value;
    if !str_eq(s3, "_HTTP._tcp.LOCAL") { ok = false; }
  }
  if !err_str_is(bonjour_service_type_name("", "tcp"), "bonjour: empty service") { ok = false; }
  if !err_str_is(bonjour_service_type_name("a.b", "tcp"), "bonjour: service contains '.'") { ok = false; }
  if !err_str_is(bonjour_service_type_name("http", "sctp"), "bonjour: bad service protocol") { ok = false; }
  if !err_str_is(bonjour_service_type("http", "tcp", "example.com"), "bonjour: not a local domain") { ok = false; }
  let in1 = bonjour_instance_name("Office", "_http._tcp.local");
  if !in1.is_ok {
    ok = false;
  } else {
    let s4: Str = in1.value;
    if !str_eq(s4, "Office._http._tcp.local") { ok = false; }
  }
  if !err_str_is(bonjour_instance_name("", "_http._tcp.local"), "bonjour: empty instance") { ok = false; }
  if !err_str_is(bonjour_instance_name("a.b", "_http._tcp.local"), "bonjour: instance contains '.'") { ok = false; }
  let sub = bonjour_subtype_name("printer", "_http._tcp.local");
  if !sub.is_ok {
    ok = false;
  } else {
    let s5: Str = sub.value;
    if !str_eq(s5, "_printer._sub._http._tcp.local") { ok = false; }
  }
  if !err_str_is(bonjour_subtype_name("", "_http._tcp.local"), "bonjour: empty subtype") { ok = false; }
  let en = bonjour_service_enum_name();
  if !str_eq(en, "_services._dns-sd._udp.local") { ok = false; }
  return assert(ok, "DNS-SD service type, instance, subtype and enum names");
}

fn t17() -> TestResult {
  var ok = bonjour_is_local_name("local");
  if !bonjour_is_local_name("LOCAL") { ok = false; }
  if !bonjour_is_local_name("Office._http._tcp.local") { ok = false; }
  if !bonjour_is_local_name("myhost.LOCAL") { ok = false; }
  if bonjour_is_local_name("example.com") { ok = false; }
  if bonjour_is_local_name("local.") { ok = false; }
  if bonjour_is_local_name("") { ok = false; }
  if bonjour_is_local_name(".local") { ok = false; }
  if bonjour_is_local_name("notlocal") { ok = false; }
  let c = bonjour_check_local_name("x.local");
  if !c.is_ok {
    ok = false;
  } else {
    let s: Str = c.value;
    if !str_eq(s, "x.local") { ok = false; }
  }
  if !err_str_is(bonjour_check_local_name("x.example"), "bonjour: not a local domain") { ok = false; }
  return assert(ok, "local domain checks are case-insensitive and suffix-based");
}

fn t18() -> TestResult {
  let r = bonjour_enum_query("local");
  if !r.is_ok { return assert(false, "enum query must build"); }
  let b: Vec[UInt8] = r.value;
  var ok = b.len() == 46;
  let h = bonjour_header_decode(&b);
  if !h.is_ok {
    ok = false;
  } else {
    let hd: BonjourHeader = h.value;
    if hd.qdcount != 1 { ok = false; }
    if hd.qr != 0 { ok = false; }
    if hd.rd != 0 { ok = false; }
  }
  let q = bonjour_question_parse(&b, 12);
  if !q.is_ok {
    ok = false;
  } else {
    let qq: BonjourQuestion = q.value;
    if qq.qtype != 12 { ok = false; }
    if qq.qclass != 1 { ok = false; }
    let nm = qq.name;
    if !str_eq(bonjour_name_to_str(&nm), "_services._dns-sd._udp.local") { ok = false; }
  }
  let r2 = bonjour_service_query("_ipp._tcp.local", true);
  if !r2.is_ok {
    ok = false;
  } else {
    let b2: Vec[UInt8] = r2.value;
    let h2 = bonjour_header_decode(&b2);
    if !h2.is_ok {
      ok = false;
    } else {
      let hd2: BonjourHeader = h2.value;
      if hd2.rd != 1 { ok = false; }
    }
    let q2 = bonjour_question_parse(&b2, 12);
    if !q2.is_ok {
      ok = false;
    } else {
      let qq2: BonjourQuestion = q2.value;
      if !bonjour_class_unicast(qq2.qclass) { ok = false; }
      if bonjour_class_base(qq2.qclass) != 1 { ok = false; }
    }
  }
  let r3 = bonjour_instance_query("Office._ipp._tcp.local", false);
  if !r3.is_ok {
    ok = false;
  } else {
    let b3: Vec[UInt8] = r3.value;
    let q3 = bonjour_question_parse(&b3, 12);
    if !q3.is_ok {
      ok = false;
    } else {
      let qq3: BonjourQuestion = q3.value;
      if qq3.qtype != 33 { ok = false; }
    }
  }
  let r4 = bonjour_query_name("myhost.local", 255, false);
  if !r4.is_ok {
    ok = false;
  } else {
    let b4: Vec[UInt8] = r4.value;
    let q4 = bonjour_question_parse(&b4, 12);
    if !q4.is_ok {
      ok = false;
    } else {
      let qq4: BonjourQuestion = q4.value;
      if qq4.qtype != 255 { ok = false; }
    }
  }
  if !err_bytes_is(bonjour_service_query("_http._tcp.example.com", false), "bonjour: not a local domain") { ok = false; }
  if !err_bytes_is(bonjour_enum_query("example.com"), "bonjour: not a local domain") { ok = false; }
  return assert(ok, "enum/service/instance queries: QU bit, RD bit and QTYPE");
}

fn t19() -> TestResult {
  var ok = true;
  let p = bonjour_ptr_record("_http._tcp.local", "Office._http._tcp.local", 4500, false);
  if !p.is_ok {
    ok = false;
  } else {
    let b: Vec[UInt8] = p.value;
    let rec = bonjour_rr_parse(&b, 0);
    if !rec.is_ok {
      ok = false;
    } else {
      let r0: BonjourRecord = rec.value;
      if r0.rtype != 12 { ok = false; }
      if r0.rclass != 1 { ok = false; }
      if r0.ttl != 4500 { ok = false; }
      if bonjour_class_flush(r0.rclass) { ok = false; }
      let t = bonjour_rdata_ptr_target(&b, r0.rdata_offset, r0.rdata_length);
      if !t.is_ok {
        ok = false;
      } else {
        let s: Str = t.value;
        if !str_eq(s, "Office._http._tcp.local") { ok = false; }
      }
    }
  }
  let a4 = hb("c0000201");
  let a = bonjour_a_record("myhost.local", &a4, 120, true);
  if !a.is_ok {
    ok = false;
  } else {
    let ba: Vec[UInt8] = a.value;
    let ra = bonjour_rr_parse(&ba, 0);
    if !ra.is_ok {
      ok = false;
    } else {
      let ra0: BonjourRecord = ra.value;
      if ra0.rtype != 1 { ok = false; }
      if !bonjour_class_flush(ra0.rclass) { ok = false; }
      if ra0.ttl != 120 { ok = false; }
    }
  }
  let a16 = hb("20010db8000000000000000000000001");
  let s6 = bonjour_aaaa_record("myhost.local", &a16, 120, true);
  if !s6.is_ok {
    ok = false;
  } else {
    let b6: Vec[UInt8] = s6.value;
    let r6 = bonjour_rr_parse(&b6, 0);
    if !r6.is_ok {
      ok = false;
    } else {
      let rr6: BonjourRecord = r6.value;
      if rr6.rtype != 28 { ok = false; }
    }
  }
  var pairs = Vec[Str].new();
  pairs.push("txtvers=1");
  let tr = bonjour_txt_record("Office._http._tcp.local", &pairs, 4500, true);
  if !tr.is_ok {
    ok = false;
  } else {
    let bt: Vec[UInt8] = tr.value;
    let rt = bonjour_rr_parse(&bt, 0);
    if !rt.is_ok {
      ok = false;
    } else {
      let rt0: BonjourRecord = rt.value;
      if rt0.rtype != 16 { ok = false; }
      if !bonjour_class_flush(rt0.rclass) { ok = false; }
    }
  }
  let sv = bonjour_srv_record("Office._http._tcp.local", 0, 0, 8080, "myhost.local", 4500, true);
  if !sv.is_ok {
    ok = false;
  } else {
    let bs: Vec[UInt8] = sv.value;
    let rs = bonjour_rr_parse(&bs, 0);
    if !rs.is_ok {
      ok = false;
    } else {
      let rs0: BonjourRecord = rs.value;
      if rs0.rtype != 33 { ok = false; }
      let pp = bonjour_rdata_srv_port(&bs, rs0.rdata_offset, rs0.rdata_length);
      if !pp.is_ok {
        ok = false;
      } else {
        let pv: Int = pp.value;
        if pv != 8080 { ok = false; }
      }
    }
  }
  let g = bonjour_goodbye_ptr("_http._tcp.local", "Office._http._tcp.local");
  if !g.is_ok {
    ok = false;
  } else {
    let bg: Vec[UInt8] = g.value;
    let rg = bonjour_rr_parse(&bg, 0);
    if !rg.is_ok {
      ok = false;
    } else {
      let rg0: BonjourRecord = rg.value;
      if rg0.ttl != 0 { ok = false; }
    }
  }
  return assert(ok, "PTR/SRV/TXT/A/AAAA record builders and goodbye TTL 0");
}

fn t20() -> TestResult {
  var pairs = Vec[Str].new();
  pairs.push("txtvers=1");
  pairs.push("path=/");
  let r = bonjour_advertise("Office._http._tcp.local", "_http._tcp.local", 8080, "myhost.local", &pairs);
  if !r.is_ok { return assert(false, "advertise must build"); }
  let b: Vec[UInt8] = r.value;
  let mp = bonjour_message_parse(&b);
  if !mp.is_ok { return assert(false, "advertise must parse"); }
  let m: BonjourMessage = mp.value;
  let h: BonjourHeader = m.header;
  var ok = h.qr == 1;
  if h.aa != 1 { ok = false; }
  if h.ancount != 3 { ok = false; }
  if h.qdcount != 0 { ok = false; }
  if bonjour_message_question_count(&m) != 0 { ok = false; }
  if bonjour_message_record_count(&m) != 3 { ok = false; }
  let o0 = bonjour_message_record_offset(&m, 0);
  let r0 = bonjour_rr_parse(&b, o0);
  if !r0.is_ok {
    ok = false;
  } else {
    let rec0: BonjourRecord = r0.value;
    if rec0.rtype != 12 { ok = false; }
    if rec0.ttl != 4500 { ok = false; }
    if bonjour_class_flush(rec0.rclass) { ok = false; }
    let n0 = rec0.name;
    if !str_eq(bonjour_name_to_str(&n0), "_http._tcp.local") { ok = false; }
    let t0 = bonjour_rdata_ptr_target(&b, rec0.rdata_offset, rec0.rdata_length);
    if !t0.is_ok {
      ok = false;
    } else {
      let s0: Str = t0.value;
      if !str_eq(s0, "Office._http._tcp.local") { ok = false; }
    }
  }
  let o1 = bonjour_message_record_offset(&m, 1);
  let r1 = bonjour_rr_parse(&b, o1);
  if !r1.is_ok {
    ok = false;
  } else {
    let rec1: BonjourRecord = r1.value;
    if rec1.rtype != 33 { ok = false; }
    if !bonjour_class_flush(rec1.rclass) { ok = false; }
    let p1 = bonjour_rdata_srv_port(&b, rec1.rdata_offset, rec1.rdata_length);
    if !p1.is_ok {
      ok = false;
    } else {
      let pv: Int = p1.value;
      if pv != 8080 { ok = false; }
    }
    let t1 = bonjour_rdata_srv_target(&b, rec1.rdata_offset, rec1.rdata_length);
    if !t1.is_ok {
      ok = false;
    } else {
      let nm1: BonjourName = t1.value;
      if !str_eq(bonjour_name_to_str(&nm1), "myhost.local") { ok = false; }
    }
  }
  let o2 = bonjour_message_record_offset(&m, 2);
  let r2 = bonjour_rr_parse(&b, o2);
  if !r2.is_ok {
    ok = false;
  } else {
    let rec2: BonjourRecord = r2.value;
    if rec2.rtype != 16 { ok = false; }
    if !bonjour_class_flush(rec2.rclass) { ok = false; }
    if rec2.next != b.len() { ok = false; }
    let xr = bonjour_rr_rdata(&b, &rec2);
    if !xr.is_ok {
      ok = false;
    } else {
      let xd: Vec[UInt8] = xr.value;
      let lp = bonjour_rdata_txt_parse(&xd);
      if !lp.is_ok {
        ok = false;
      } else {
        let list: Vec[Str] = lp.value;
        let tv = bonjour_txt_get(&list, "txtvers");
        if !tv.is_ok {
          ok = false;
        } else {
          let s: Str = tv.value;
          if !str_eq(s, "1") { ok = false; }
        }
        let pv2 = bonjour_txt_get(&list, "path");
        if !pv2.is_ok {
          ok = false;
        } else {
          let s2: Str = pv2.value;
          if !str_eq(s2, "/") { ok = false; }
        }
      }
    }
  }
  if !err_bytes_is(bonjour_advertise("Office.example.com", "_http._tcp.local", 80, "myhost.local", &pairs), "bonjour: not a local domain") { ok = false; }
  return assert(ok, "advertise response: 3 answers with PTR/SRV/TXT");
}

fn t21() -> TestResult {
  var ok = true;
  let tiny = hb("00");
  if !err_message_is(bonjour_message_parse(&tiny), "bonjour: truncated header") { ok = false; }
  let qh = hb("000000000001000000000000");
  if !err_message_is(bonjour_message_parse(&qh), "bonjour: truncated question") { ok = false; }
  let rh = hb("000000000000000100000000");
  if !err_message_is(bonjour_message_parse(&rh), "bonjour: truncated record") { ok = false; }
  let shortr = hb("000000000000000100000000056c6f63616c00000100010000012c00ff00");
  if !err_message_is(bonjour_message_parse(&shortr), "bonjour: truncated rdata") { ok = false; }
  let extra = concat_bytes(hb("000084000000000000000000"), hb("deadbeef"));
  let m = bonjour_message_parse(&extra);
  if !m.is_ok {
    ok = false;
  } else {
    let mm: BonjourMessage = m.value;
    let hh: BonjourHeader = mm.header;
    if hh.ancount != 0 { ok = false; }
  }
  return assert(ok, "message parse rejects truncation and ignores trailing bytes");
}

fn t22() -> TestResult {
  var v = hb("000084000001000100000000");
  v = concat_bytes(v, hb("055f68747470045f746370056c6f63616c00"));
  v = concat_bytes(v, hb("000c0001"));
  v = concat_bytes(v, hb("c00c000c0001000011940019"));
  v = concat_bytes(v, hb("064f6666696365055f68747470045f746370056c6f63616c00"));
  let mp = bonjour_message_parse(&v);
  if !mp.is_ok { return assert(false, "compressed message must parse"); }
  let m: BonjourMessage = mp.value;
  var ok = m.header.ancount == 1;
  if bonjour_message_question_count(&m) != 1 { ok = false; }
  if bonjour_message_record_count(&m) != 1 { ok = false; }
  if bonjour_message_question_offset(&m, 0) != 12 { ok = false; }
  if bonjour_message_record_offset(&m, 0) != 34 { ok = false; }
  let q = bonjour_question_parse(&v, 12);
  if !q.is_ok {
    ok = false;
  } else {
    let qq: BonjourQuestion = q.value;
    if qq.qtype != 12 { ok = false; }
    let nm = qq.name;
    if nm.compressed { ok = false; }
  }
  let r = bonjour_rr_parse(&v, 34);
  if !r.is_ok {
    ok = false;
  } else {
    let rec: BonjourRecord = r.value;
    if rec.ttl != 4500 { ok = false; }
    let nm2 = rec.name;
    if !nm2.compressed { ok = false; }
    if !str_eq(bonjour_name_to_str(&nm2), "_http._tcp.local") { ok = false; }
    let t = bonjour_rdata_ptr_target(&v, rec.rdata_offset, rec.rdata_length);
    if !t.is_ok {
      ok = false;
    } else {
      let s: Str = t.value;
      if !str_eq(s, "Office._http._tcp.local") { ok = false; }
    }
  }
  return assert(ok, "message with pointer-compressed owner name");
}

fn t23() -> TestResult {
  let q = bonjour_enum_query("local");
  if !q.is_ok { return assert(false, "accessor fixture must build"); }
  let b: Vec[UInt8] = q.value;
  let mp = bonjour_message_parse(&b);
  if !mp.is_ok { return assert(false, "accessor message must parse"); }
  let m: BonjourMessage = mp.value;
  var ok = bonjour_message_question_count(&m) == 1;
  if bonjour_message_record_count(&m) != 0 { ok = false; }
  if bonjour_message_question_offset(&m, 0) != 12 { ok = false; }
  if bonjour_message_question_offset(&m, 1) != -1 { ok = false; }
  if bonjour_message_question_offset(&m, -1) != -1 { ok = false; }
  if bonjour_message_record_offset(&m, 0) != -1 { ok = false; }
  return assert(ok, "message index accessors and out-of-range -1");
}

fn t24() -> TestResult {
  var ok = true;
  let bq = bonjour_service_query("_ipp._tcp.local", false);
  if !bq.is_ok {
    ok = false;
  } else {
    let b: Vec[UInt8] = bq.value;
    let mp = bonjour_message_parse(&b);
    if !mp.is_ok {
      ok = false;
    } else {
      let m: BonjourMessage = mp.value;
      let hh: BonjourHeader = m.header;
      if hh.qdcount != 1 { ok = false; }
    }
  }
  var pairs = Vec[Str].new();
  pairs.push("txtvers=1");
  var reply = hb("000084000000000300000000");
  let p1 = bonjour_ptr_record("_ipp._tcp.local", "Office._ipp._tcp.local", 4500, false);
  if !p1.is_ok {
    ok = false;
  } else {
    let x: Vec[UInt8] = p1.value;
    reply = concat_bytes(reply, x);
  }
  let p2 = bonjour_srv_record("Office._ipp._tcp.local", 0, 0, 631, "myhost.local", 4500, true);
  if !p2.is_ok {
    ok = false;
  } else {
    let x: Vec[UInt8] = p2.value;
    reply = concat_bytes(reply, x);
  }
  let p3 = bonjour_txt_record("Office._ipp._tcp.local", &pairs, 4500, true);
  if !p3.is_ok {
    ok = false;
  } else {
    let x: Vec[UInt8] = p3.value;
    reply = concat_bytes(reply, x);
  }
  let rp = bonjour_message_parse(&reply);
  if !rp.is_ok {
    ok = false;
  } else {
    let rm: BonjourMessage = rp.value;
    if bonjour_message_record_count(&rm) != 3 { ok = false; }
    let o1 = bonjour_message_record_offset(&rm, 1);
    let rec = bonjour_rr_parse(&reply, o1);
    if !rec.is_ok {
      ok = false;
    } else {
      let rc: BonjourRecord = rec.value;
      let pp = bonjour_rdata_srv_port(&reply, rc.rdata_offset, rc.rdata_length);
      if !pp.is_ok {
        ok = false;
      } else {
        let pv: Int = pp.value;
        if pv != 631 { ok = false; }
      }
    }
  }
  let sn = bonjour_subtype_name("printer", "_ipp._tcp.local");
  if !sn.is_ok {
    ok = false;
  } else {
    let s: Str = sn.value;
    let se = bonjour_name_encode(s);
    if !se.is_ok {
      ok = false;
    } else {
      let sb2: Vec[UInt8] = se.value;
      let nd = bonjour_name_decode(&sb2, 0);
      if !nd.is_ok {
        ok = false;
      } else {
        let nm: BonjourName = nd.value;
        if !str_eq(bonjour_name_to_str(&nm), "_printer._sub._ipp._tcp.local") { ok = false; }
      }
    }
  }
  return assert(ok, "browse query and synthetic PTR/SRV/TXT reply round trip");
}

fn main() -> Int {
  io.println("=== xiom.bonjour conformance tests ===");
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
    io.println("xiom.bonjour: all tests passed");
  } else {
    io.println("xiom.bonjour: tests failed");
  }
  return failed;
}

