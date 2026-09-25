// XIOM -- xiom.dns conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the 12-byte header (encode, decode, masking,
// truncation), domain names (pinned encodings, label and total-length
// boundaries, compression pointers, loops, out-of-range targets, bad label
// types, NUL labels), questions, resource records (A, AAAA, CNAME, MX,
// TXT), the query builder and whole-message parsing including a compressed
// owner name, plus the full error catalog.
//
// Str values are compared with str_compare (BUG 17 discipline: `==` on Str
// values read from Vec[Str] elements lowers to a pointer comparison); Vec
// elements are read into typed locals first. No test does table-driven
// Vec[fn] dispatch: every test is called directly from main.
//
// Fixture bytes are assembled from this file's own hex strings, so the
// decoder is exercised against bytes the tests control.

module dns_tests
use xiom.io; use xiom.test;
use xiom.dns;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Helpers (independent of src/dns.xi)
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

fn err_header_is(r: Result[DnsHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_name_is(r: Result[DnsName, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_question_is(r: Result[DnsQuestion, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_record_is(r: Result[DnsRecord, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_message_is(r: Result[DnsMessage, Str], want: Str) -> Bool {
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
  let r = dns_name_encode(name);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.value;
  return v;
}

// Presentation form of the name at `off`, or "" on error.
fn name_str(data: &Vec[UInt8], off: Int) -> Str {
  let r = dns_name_decode(data, off);
  match r {
    Ok(nm) => { return dns_name_to_str(&nm); },
    Err(_) => {},
  }
  return "";
}

// `next` of the name at `off`, or -1 on error.
fn name_next(data: &Vec[UInt8], off: Int) -> Int {
  let r = dns_name_decode(data, off);
  if !r.is_ok {
    return -1;
  }
  let nm: DnsName = r.value;
  return nm.next;
}

// True when the name at `off` used a compression pointer.
fn name_uses_pointer(data: &Vec[UInt8], off: Int) -> Bool {
  let r = dns_name_decode(data, off);
  if !r.is_ok {
    return false;
  }
  let nm: DnsName = r.value;
  return nm.compressed;
}

// Value of a header field through a decode (tests only).
fn header_ok(data: &Vec[UInt8]) -> Bool {
  let r = dns_header_decode(data);
  return r.is_ok;
}

// A four-label name with wire length sum(1 + label) + 1; used to pin the
// 255-byte upper bound (label_len 63 x 3 plus last_len).
fn long_name(label_len: Int, last_len: Int) -> Str {
  let a = string.str_repeat("a", label_len);
  let b = string.str_repeat("b", label_len);
  let c = string.str_repeat("c", label_len);
  let d = string.str_repeat("d", last_len);
  return a + "." + b + "." + c + "." + d;
}

// 12-byte header + one question (example.com A IN, 17 bytes) + one A
// answer whose owner name is the compression pointer C0 0C to offset 12.
fn response_fixture() -> Vec[UInt8] {
  var v = hb("123485800001000100000000");
  v = concat_bytes(v, hb("076578616d706c6503636f6d0000010001"));
  v = concat_bytes(v, hb("c00c000100010000003c0004c0000201"));
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let h = DnsHeader{
    id: 4660;
    qr: 1;
    opcode: 0;
    aa: 0;
    tc: 0;
    rd: 1;
    ra: 0;
    z: 0;
    rcode: 0;
    qdcount: 1;
    ancount: 0;
    nscount: 0;
    arcount: 0;
  };
  let b = dns_header_encode(&h);
  var ok = b.len() == 12;
  if !bytes_equal(b, hb("123481000001000000000000")) { ok = false; }
  return assert(ok, "header encode pins ID, flags and counts big-endian");
}

fn t2() -> TestResult {
  let ff = hb("ffffffffffffffffffffffff");
  let r = dns_header_decode(&ff);
  if !r.is_ok { return assert(false, "all-ones header must decode"); }
  let h: DnsHeader = r.value;
  var ok = h.id == 65535;
  if h.qr != 1 { ok = false; }
  if h.opcode != 15 { ok = false; }
  if h.aa != 1 { ok = false; }
  if h.tc != 1 { ok = false; }
  if h.rd != 1 { ok = false; }
  if h.ra != 1 { ok = false; }
  if h.z != 7 { ok = false; }
  if h.rcode != 15 { ok = false; }
  if h.qdcount != 65535 { ok = false; }
  if h.ancount != 65535 { ok = false; }
  if h.nscount != 65535 { ok = false; }
  if h.arcount != 65535 { ok = false; }
  let zeros = hb("000000000000000000000000");
  let rz = dns_header_decode(&zeros);
  if !rz.is_ok {
    ok = false;
  } else {
    let hz: DnsHeader = rz.value;
    if hz.id != 0 { ok = false; }
    if hz.qr != 0 { ok = false; }
    if hz.opcode != 0 { ok = false; }
    if hz.z != 0 { ok = false; }
    if hz.rcode != 0 { ok = false; }
    if hz.qdcount != 0 { ok = false; }
  }
  return assert(ok, "header decode: every all-ones bit and the all-zero header");
}

fn t3() -> TestResult {
  let h = DnsHeader{
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
  let b = dns_header_encode(&h);
  var ok = bytes_equal(b, hb("0007a0100001000000000000"));
  let r = dns_header_decode(&b);
  if !r.is_ok {
    ok = false;
  } else {
    let d: DnsHeader = r.value;
    if d.id != 7 { ok = false; }
    if d.qr != 1 { ok = false; }
    if d.opcode != 4 { ok = false; }
    if d.aa != 0 { ok = false; }
    if d.z != 1 { ok = false; }
    if d.rcode != 0 { ok = false; }
    if d.qdcount != 1 { ok = false; }
  }
  return assert(ok, "header fields outside their width are masked on encode");
}

fn t4() -> TestResult {
  let full = hb("123481000001000000000000");
  let cut11 = prefix(full, 11);
  var empty = Vec[UInt8].new();
  var ok = err_header_is(dns_header_decode(&empty), "dns: truncated header");
  if !err_header_is(dns_header_decode(&cut11), "dns: truncated header") { ok = false; }
  if !header_ok(&full) { ok = false; }
  let extra = concat_bytes(full, hb("aabb"));
  if !header_ok(&extra) { ok = false; }
  return assert(ok, "header decode needs 12 bytes and ignores trailing bytes");
}

fn t5() -> TestResult {
  var ok = bytes_equal(enc("www.example.com"), hb("03777777076578616d706c6503636f6d00"));
  if !bytes_equal(enc("example.com."), hb("076578616d706c6503636f6d00")) { ok = false; }
  if !bytes_equal(enc("_sip._tcp.example.com"), hb("045f736970045f746370076578616d706c6503636f6d00")) { ok = false; }
  if !bytes_equal(enc("a"), hb("016100")) { ok = false; }
  if !bytes_equal(enc(""), hb("00")) { ok = false; }
  if !bytes_equal(enc("."), hb("00")) { ok = false; }
  return assert(ok, "name encode: multi-label, trailing dot, underscores, root");
}

fn t6() -> TestResult {
  let l63 = string.str_repeat("a", 63);
  let e63 = enc(l63);
  var ok = e63.len() == 65;
  if (e63[0] as Int) != 63 { ok = false; }
  if (e63[64] as Int) != 0 { ok = false; }
  if !err_bytes_is(dns_name_encode(string.str_repeat("a", 64)), "dns: label too long") { ok = false; }
  let max = long_name(63, 61);
  let emax = enc(max);
  if emax.len() != 255 { ok = false; }
  let rmax = dns_name_decode(&emax, 0);
  if !rmax.is_ok {
    ok = false;
  } else {
    let nm: DnsName = rmax.value;
    if nm.labels.len() != 4 { ok = false; }
    if nm.next != 255 { ok = false; }
    if !str_eq(dns_name_to_str(&nm), max) { ok = false; }
  }
  if !err_bytes_is(dns_name_encode(long_name(63, 62)), "dns: name too long") { ok = false; }
  if !err_bytes_is(dns_name_encode("a..b"), "dns: empty label") { ok = false; }
  if !err_bytes_is(dns_name_encode(".a"), "dns: empty label") { ok = false; }
  if !err_bytes_is(dns_name_encode("a.b.."), "dns: empty label") { ok = false; }
  return assert(ok, "name encode: 63-byte label, 255-byte name, over-long cases");
}

fn t7() -> TestResult {
  let b = enc("example.com");
  let r = dns_name_decode(&b, 0);
  if !r.is_ok { return assert(false, "example.com must decode"); }
  let nm: DnsName = r.value;
  var ok = nm.labels.len() == 2;
  if nm.next != 13 { ok = false; }
  if nm.compressed { ok = false; }
  let l0: Str = nm.labels[0];
  let l1: Str = nm.labels[1];
  if !str_eq(l0, "example") { ok = false; }
  if !str_eq(l1, "com") { ok = false; }
  if !str_eq(dns_name_to_str(&nm), "example.com") { ok = false; }
  let buf = concat_bytes(concat_bytes(hb("aa"), enc("a")), hb("bb"));
  var ok2 = bytes_equal(buf, hb("aa016100bb"));
  let r2 = dns_name_decode(&buf, 1);
  if !r2.is_ok {
    ok2 = false;
  } else {
    let nm2: DnsName = r2.value;
    if nm2.labels.len() != 1 { ok2 = false; }
    if nm2.next != 4 { ok2 = false; }
    if !str_eq(dns_name_to_str(&nm2), "a") { ok2 = false; }
  }
  if !ok2 { ok = false; }
  return assert(ok, "name decode: labels, next offset, non-zero starting offset");
}

fn t8() -> TestResult {
  let base = enc("example.com");
  let buf = concat_bytes(concat_bytes(base, hb("03777777c000")), hb("c00d"));
  var ok = buf.len() == 21;
  var ok1 = name_str(&buf, 13);
  if !str_eq(ok1, "www.example.com") { ok = false; }
  if name_next(&buf, 13) != 19 { ok = false; }
  if !name_uses_pointer(&buf, 13) { ok = false; }
  var ok2 = name_str(&buf, 19);
  if !str_eq(ok2, "www.example.com") { ok = false; }
  if name_next(&buf, 19) != 21 { ok = false; }
  if !name_uses_pointer(&buf, 19) { ok = false; }
  let r = dns_name_decode(&buf, 13);
  if !r.is_ok {
    ok = false;
  } else {
    let nm: DnsName = r.value;
    if nm.labels.len() != 3 { ok = false; }
    let l0: Str = nm.labels[0];
    if !str_eq(l0, "www") { ok = false; }
  }
  return assert(ok, "name decode: compression pointers and pointer-to-pointer");
}

fn t9() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_name_is(dns_name_decode(&empty, 0), "dns: truncated name");
  if !err_name_is(dns_name_decode(&empty, -1), "dns: negative offset") { ok = false; }
  if !err_name_is(dns_name_decode(&hb("05"), 0), "dns: truncated label") { ok = false; }
  if !err_name_is(dns_name_decode(&hb("036162"), 0), "dns: truncated label") { ok = false; }
  if !err_name_is(dns_name_decode(&hb("03616263"), 0), "dns: truncated name") { ok = false; }
  if !err_name_is(dns_name_decode(&hb("40"), 0), "dns: unsupported label type") { ok = false; }
  if !err_name_is(dns_name_decode(&hb("80"), 0), "dns: unsupported label type") { ok = false; }
  if !err_name_is(dns_name_decode(&hb("c0"), 0), "dns: truncated name") { ok = false; }
  if !err_name_is(dns_name_decode(&hb("c009"), 0), "dns: pointer out of range") { ok = false; }
  if !err_name_is(dns_name_decode(&hb("c002c000"), 0), "dns: compression loop") { ok = false; }
  if !err_name_is(dns_name_decode(&hb("00"), 5), "dns: truncated name") { ok = false; }
  if !err_name_is(dns_name_decode(&hb("0100"), 0), "dns: label contains NUL byte") { ok = false; }
  return assert(ok, "name decode: truncation, bad types, bad pointers, loops, NUL");
}

fn t10() -> TestResult {
  let q = dns_question_encode("example.com", 1, 1);
  if !q.is_ok { return assert(false, "question must encode"); }
  let b: Vec[UInt8] = q.value;
  var ok = b.len() == 17;
  if !bytes_equal(b, hb("076578616d706c6503636f6d0000010001")) { ok = false; }
  let masked = dns_question_encode("example.com", 65537, 65536);
  if !masked.is_ok { ok = false; } else {
    let mb: Vec[UInt8] = masked.value;
    if !bytes_equal(mb, hb("076578616d706c6503636f6d0000010000")) { ok = false; }
  }
  if !err_bytes_is(dns_question_encode("a..b", 1, 1), "dns: empty label") { ok = false; }
  return assert(ok, "question encode: exact bytes, QTYPE/QCLASS masking");
}

fn t11() -> TestResult {
  let q = hb("076578616d706c6503636f6d0000010001");
  let r = dns_question_parse(&q, 0);
  if !r.is_ok { return assert(false, "question must parse"); }
  let d: DnsQuestion = r.value;
  var ok = d.qtype == 1;
  if d.qclass != 1 { ok = false; }
  if d.next != 17 { ok = false; }
  if d.name.labels.len() != 2 { ok = false; }
  if !str_eq(dns_name_to_str(&d.name), "example.com") { ok = false; }
  let buf = concat_bytes(hb("aa"), q);
  let r2 = dns_question_parse(&buf, 1);
  if !r2.is_ok {
    ok = false;
  } else {
    let d2: DnsQuestion = r2.value;
    if d2.next != 18 { ok = false; }
    if d2.qtype != 1 { ok = false; }
  }
  if !err_question_is(dns_question_parse(&prefix(q, 16), 0), "dns: truncated question") { ok = false; }
  if !err_question_is(dns_question_parse(&hb("00"), 0), "dns: truncated question") { ok = false; }
  if !err_question_is(dns_question_parse(&q, -1), "dns: negative offset") { ok = false; }
  return assert(ok, "question parse: fields, offsets, truncation and bad offset");
}

fn t12() -> TestResult {
  let rdata = hb("c0000201");
  let r = dns_rr_encode("example.com", 1, 1, 300, &rdata);
  if !r.is_ok { return assert(false, "A record must encode"); }
  let b: Vec[UInt8] = r.value;
  var ok = b.len() == 27;
  if !bytes_equal(b, hb("076578616d706c6503636f6d00000100010000012c0004c0000201")) { ok = false; }
  return assert(ok, "A record encode: NAME TYPE CLASS TTL RDLENGTH RDATA");
}

fn t13() -> TestResult {
  let b = hb("076578616d706c6503636f6d00000100010000012c0004c0000201");
  let r = dns_rr_parse(&b, 0);
  if !r.is_ok { return assert(false, "A record must parse"); }
  let d: DnsRecord = r.value;
  var ok = d.rtype == 1;
  if d.rclass != 1 { ok = false; }
  if d.ttl != 300 { ok = false; }
  if d.rdata_offset != 23 { ok = false; }
  if d.rdata_length != 4 { ok = false; }
  if d.next != 27 { ok = false; }
  if d.name.compressed { ok = false; }
  if !str_eq(dns_name_to_str(&d.name), "example.com") { ok = false; }
  let rd = dns_rr_rdata(&b, &d);
  if !rd.is_ok {
    ok = false;
  } else {
    let bytes: Vec[UInt8] = rd.value;
    if !bytes_equal(bytes, hb("c0000201")) { ok = false; }
    let s = dns_rdata_a_to_str(&bytes);
    if !s.is_ok {
      ok = false;
    } else {
      let ip: Str = s.value;
      if !str_eq(ip, "192.0.2.1") { ok = false; }
    }
  }
  return assert(ok, "A record parse: pinned span, TTL, RDATA copy and AToStr");
}

fn t14() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_record_is(dns_rr_parse(&empty, 0), "dns: truncated name");
  let name_only = enc("example.com");
  if !err_record_is(dns_rr_parse(&name_only, 0), "dns: truncated record") { ok = false; }
  let short_rdata = concat_bytes(concat_bytes(name_only, hb("000100010000003c0004")), hb("aabb"));
  if !err_record_is(dns_rr_parse(&short_rdata, 0), "dns: truncated rdata") { ok = false; }
  let good = hb("076578616d706c6503636f6d00000100010000012c0004c0000201");
  if !err_record_is(dns_rr_parse(&good, -1), "dns: negative offset") { ok = false; }
  let r = dns_rr_parse(&good, 0);
  if !r.is_ok {
    ok = false;
  } else {
    let d: DnsRecord = r.value;
    let cut = prefix(good, 25);
    if !err_bytes_is(dns_rr_rdata(&cut, &d), "dns: rdata out of range") { ok = false; }
  }
  return assert(ok, "record parse errors: truncation, negative offset, short buffer");
}

fn t15() -> TestResult {
  let a4 = hb("0a0000ff");
  let ra = dns_rdata_a(&a4);
  var ok = ra.is_ok;
  if ra.is_ok {
    let b: Vec[UInt8] = ra.value;
    if !bytes_equal(b, a4) { ok = false; }
  }
  if !err_bytes_is(dns_rdata_a(&hb("010203")), "dns: bad A rdata") { ok = false; }
  if !err_bytes_is(dns_rdata_a(&hb("0102030405")), "dns: bad A rdata") { ok = false; }
  let s = dns_rdata_a_to_str(&a4);
  if !s.is_ok {
    ok = false;
  } else {
    let ip: Str = s.value;
    if !str_eq(ip, "10.0.0.255") { ok = false; }
  }
  if !err_str_is(dns_rdata_a_to_str(&hb("0102")), "dns: bad A rdata") { ok = false; }
  let a16 = hb("20010db8000000000000000000000001");
  let ra6 = dns_rdata_aaaa(&a16);
  if !ra6.is_ok {
    ok = false;
  } else {
    let b6: Vec[UInt8] = ra6.value;
    if !bytes_equal(b6, a16) { ok = false; }
  }
  if !err_bytes_is(dns_rdata_aaaa(&prefix(a16, 15)), "dns: bad AAAA rdata") { ok = false; }
  let s6 = dns_rdata_aaaa_to_str(&a16);
  if !s6.is_ok {
    ok = false;
  } else {
    let ip6: Str = s6.value;
    if !str_eq(ip6, "2001:db8:0:0:0:0:0:1") { ok = false; }
  }
  if !err_str_is(dns_rdata_aaaa_to_str(&hb("010203")), "dns: bad AAAA rdata") { ok = false; }
  return assert(ok, "A/AAAA rdata: 4 and 16 octets, renderers, bad lengths");
}

fn t16() -> TestResult {
  let target = dns_rdata_cname("www.example.com");
  if !target.is_ok { return assert(false, "CNAME rdata must encode"); }
  let tb: Vec[UInt8] = target.value;
  var ok = bytes_equal(tb, hb("03777777076578616d706c6503636f6d00"));
  let r = dns_rdata_name(&tb, 0, tb.len());
  if !r.is_ok {
    ok = false;
  } else {
    let nm: DnsName = r.value;
    if nm.compressed { ok = false; }
    if nm.next != 17 { ok = false; }
    if !str_eq(dns_name_to_str(&nm), "www.example.com") { ok = false; }
  }
  let buf = concat_bytes(enc("example.com"), hb("c000"));
  let r2 = dns_rdata_name(&buf, 13, 2);
  if !r2.is_ok {
    ok = false;
  } else {
    let nm2: DnsName = r2.value;
    if !nm2.compressed { ok = false; }
    if nm2.next != 15 { ok = false; }
    if !str_eq(dns_name_to_str(&nm2), "example.com") { ok = false; }
  }
  if !err_name_is(dns_rdata_name(&tb, 0, 5), "dns: bad rdata name") { ok = false; }
  if !err_name_is(dns_rdata_name(&tb, 0, 0), "dns: bad rdata name") { ok = false; }
  if !err_name_is(dns_rdata_name(&hb("c009"), 0, 2), "dns: pointer out of range") { ok = false; }
  return assert(ok, "CNAME rdata: encode, uncompressed and compressed targets");
}

fn t17() -> TestResult {
  let mx = dns_rdata_mx(10, "mail.example.com");
  if !mx.is_ok { return assert(false, "MX rdata must encode"); }
  let mb: Vec[UInt8] = mx.value;
  var ok = bytes_equal(mb, hb("000a046d61696c076578616d706c6503636f6d00"));
  let pref = dns_rdata_mx_preference(&mb, 0, mb.len());
  if !pref.is_ok {
    ok = false;
  } else {
    let p: Int = pref.value;
    if p != 10 { ok = false; }
  }
  let ex = dns_rdata_mx_exchange(&mb, 0, mb.len());
  if !ex.is_ok {
    ok = false;
  } else {
    let nm: DnsName = ex.value;
    if nm.next != mb.len() { ok = false; }
    if !str_eq(dns_name_to_str(&nm), "mail.example.com") { ok = false; }
  }
  if !err_int_is(dns_rdata_mx_preference(&mb, 0, 2), "dns: bad MX rdata") { ok = false; }
  if !err_name_is(dns_rdata_mx_exchange(&mb, 0, 2), "dns: bad MX rdata") { ok = false; }
  let masked = dns_rdata_mx(65546, "a");
  if !masked.is_ok {
    ok = false;
  } else {
    let kb: Vec[UInt8] = masked.value;
    if !bytes_equal(kb, hb("000a016100")) { ok = false; }
  }
  return assert(ok, "MX rdata: preference and exchange, masking, short rdata");
}

fn t18() -> TestResult {
  let t = dns_rdata_txt("hello");
  if !t.is_ok { return assert(false, "TXT rdata must encode"); }
  let tb: Vec[UInt8] = t.value;
  var ok = bytes_equal(tb, hb("0568656c6c6f"));
  let s = dns_rdata_txt_parse(&tb);
  if !s.is_ok {
    ok = false;
  } else {
    let text: Str = s.value;
    if !str_eq(text, "hello") { ok = false; }
  }
  let e = dns_rdata_txt("");
  if !e.is_ok {
    ok = false;
  } else {
    let eb: Vec[UInt8] = e.value;
    if !bytes_equal(eb, hb("00")) { ok = false; }
    let se = dns_rdata_txt_parse(&eb);
    if !se.is_ok {
      ok = false;
    } else {
      let text: Str = se.value;
      if !str_eq(text, "") { ok = false; }
    }
  }
  let big = string.str_repeat("x", 255);
  let bt = dns_rdata_txt(big);
  if !bt.is_ok {
    ok = false;
  } else {
    let bb: Vec[UInt8] = bt.value;
    if bb.len() != 256 { ok = false; }
    if (bb[0] as Int) != 255 { ok = false; }
    let sb = dns_rdata_txt_parse(&bb);
    if !sb.is_ok {
      ok = false;
    } else {
      let text: Str = sb.value;
      if !str_eq(text, big) { ok = false; }
    }
  }
  if !err_bytes_is(dns_rdata_txt(string.str_repeat("x", 256)), "dns: txt too long") { ok = false; }
  if !err_str_is(dns_rdata_txt_parse(&hb("0261620163")), "dns: bad TXT rdata") { ok = false; }
  var empty = Vec[UInt8].new();
  if !err_str_is(dns_rdata_txt_parse(&empty), "dns: bad TXT rdata") { ok = false; }
  if !err_str_is(dns_rdata_txt_parse(&hb("0261")), "dns: bad TXT rdata") { ok = false; }
  return assert(ok, "TXT rdata: one character-string, 255 boundary, multi-string rejected");
}

fn t19() -> TestResult {
  let q = dns_query_build(4660, "www.example.com", 1);
  if !q.is_ok { return assert(false, "query must build"); }
  let qb: Vec[UInt8] = q.value;
  var ok = qb.len() == 33;
  let want = concat_bytes(hb("123401000001000000000000"), hb("03777777076578616d706c6503636f6d0000010001"));
  if !bytes_equal(qb, want) { ok = false; }
  let mr = dns_message_parse(&qb);
  if !mr.is_ok {
    ok = false;
  } else {
    let m: DnsMessage = mr.value;
    if m.header.id != 4660 { ok = false; }
    if m.header.qr != 0 { ok = false; }
    if m.header.rd != 1 { ok = false; }
    if m.header.ra != 0 { ok = false; }
    if m.header.qdcount != 1 { ok = false; }
    if m.header.ancount != 0 { ok = false; }
    if dns_message_question_count(&m) != 1 { ok = false; }
    if dns_message_record_count(&m) != 0 { ok = false; }
    if dns_message_question_offset(&m, 0) != 12 { ok = false; }
    if dns_message_question_offset(&m, 1) != -1 { ok = false; }
    if dns_message_record_offset(&m, 0) != -1 { ok = false; }
    let qr = dns_question_parse(&qb, 12);
    if !qr.is_ok {
      ok = false;
    } else {
      let d: DnsQuestion = qr.value;
      if d.qtype != 1 { ok = false; }
      if d.qclass != 1 { ok = false; }
      if d.next != 33 { ok = false; }
      if !str_eq(dns_name_to_str(&d.name), "www.example.com") { ok = false; }
    }
    let re = dns_question_encode("www.example.com", 1, 1);
    if !re.is_ok {
      ok = false;
    } else {
      let rb: Vec[UInt8] = re.value;
      if !bytes_equal(rb, hb("03777777076578616d706c6503636f6d0000010001")) { ok = false; }
    }
  }
  return assert(ok, "query build: exact bytes, message parse and question read-back");
}

fn t20() -> TestResult {
  let fx = response_fixture();
  var ok = fx.len() == 45;
  let mr = dns_message_parse(&fx);
  if !mr.is_ok { return assert(false, "response fixture must parse"); }
  let m: DnsMessage = mr.value;
  if m.header.id != 4660 { ok = false; }
  if m.header.qr != 1 { ok = false; }
  if m.header.aa != 1 { ok = false; }
  if m.header.rd != 1 { ok = false; }
  if m.header.ra != 1 { ok = false; }
  if m.header.rcode != 0 { ok = false; }
  if m.header.qdcount != 1 { ok = false; }
  if m.header.ancount != 1 { ok = false; }
  if dns_message_question_count(&m) != 1 { ok = false; }
  if dns_message_record_count(&m) != 1 { ok = false; }
  if dns_message_question_offset(&m, 0) != 12 { ok = false; }
  if dns_message_record_offset(&m, 0) != 29 { ok = false; }
  let rr = dns_rr_parse(&fx, 29);
  if !rr.is_ok {
    ok = false;
  } else {
    let d: DnsRecord = rr.value;
    if d.rtype != 1 { ok = false; }
    if d.rclass != 1 { ok = false; }
    if d.ttl != 60 { ok = false; }
    if d.next != 45 { ok = false; }
    if !d.name.compressed { ok = false; }
    if d.name.next != 31 { ok = false; }
    if !str_eq(dns_name_to_str(&d.name), "example.com") { ok = false; }
    let rd = dns_rr_rdata(&fx, &d);
    if !rd.is_ok {
      ok = false;
    } else {
      let bytes: Vec[UInt8] = rd.value;
      if !bytes_equal(bytes, hb("c0000201")) { ok = false; }
    }
  }
  return assert(ok, "message parse: response with a compressed owner name");
}

fn t21() -> TestResult {
  var ok = err_message_is(dns_message_parse(&hb("123400000001000000000000")), "dns: truncated question");
  let q_only = concat_bytes(hb("123481800001000100000000"), hb("076578616d706c6503636f6d0000010001"));
  if !err_message_is(dns_message_parse(&q_only), "dns: truncated record") { ok = false; }
  let short_rr = concat_bytes(q_only, hb("c00c000100010000003c0004c0"));
  if !err_message_is(dns_message_parse(&short_rr), "dns: truncated rdata") { ok = false; }
  if !err_message_is(dns_message_parse(&hb("1234")), "dns: truncated header") { ok = false; }
  let q = dns_query_build(1, "a", 1);
  if !q.is_ok {
    ok = false;
  } else {
    let qb: Vec[UInt8] = q.value;
    let trailing = concat_bytes(qb, hb("deadbeef"));
    let mr = dns_message_parse(&trailing);
    if !mr.is_ok {
      ok = false;
    } else {
      let m: DnsMessage = mr.value;
      if dns_message_question_count(&m) != 1 { ok = false; }
      if dns_message_record_count(&m) != 0 { ok = false; }
    }
  }
  return assert(ok, "message parse: section truncation, short header, trailing bytes");
}

fn t22() -> TestResult {
  var empty = Vec[UInt8].new();
  let rr = dns_rr_encode("a", 16, 1, 0, &empty);
  if !rr.is_ok { return assert(false, "empty RDATA record must encode"); }
  let b: Vec[UInt8] = rr.value;
  var ok = bytes_equal(b, hb("01610000100001000000000000"));
  let pr = dns_rr_parse(&b, 0);
  if !pr.is_ok {
    ok = false;
  } else {
    let d: DnsRecord = pr.value;
    if d.rdata_length != 0 { ok = false; }
    if d.rdata_offset != 13 { ok = false; }
    if d.next != 13 { ok = false; }
    let rd = dns_rr_rdata(&b, &d);
    if !rd.is_ok {
      ok = false;
    } else {
      let bytes: Vec[UInt8] = rd.value;
      if bytes.len() != 0 { ok = false; }
    }
  }
  return assert(ok, "zero-length RDATA encodes, parses and copies as empty");
}

fn t23() -> TestResult {
  let name = "café.example.com";
  let b = enc(name);
  var ok = bytes_equal(b, hb("05636166c3a9076578616d706c6503636f6d00"));
  let r = dns_name_decode(&b, 0);
  if !r.is_ok {
    ok = false;
  } else {
    let nm: DnsName = r.value;
    if nm.labels.len() != 3 { ok = false; }
    let l0: Str = nm.labels[0];
    if !str_eq(l0, "café") { ok = false; }
    if !str_eq(dns_name_to_str(&nm), name) { ok = false; }
  }
  return assert(ok, "non-ASCII label bytes are preserved verbatim");
}

fn t24() -> TestResult {
  let q = dns_query_build(7, "example.com", 28);
  if !q.is_ok { return assert(false, "query must build"); }
  let qb: Vec[UInt8] = q.value;
  let mr = dns_message_parse(&qb);
  if !mr.is_ok { return assert(false, "query must parse"); }
  let m: DnsMessage = mr.value;
  var ok = m.header.rd == 1;
  if m.header.arcount != 0 { ok = false; }
  if m.header.nscount != 0 { ok = false; }
  let qr = dns_question_parse(&qb, 12);
  if !qr.is_ok {
    ok = false;
  } else {
    let d: DnsQuestion = qr.value;
    if d.qtype != 28 { ok = false; }
    if d.qclass != 1 { ok = false; }
    if !str_eq(dns_name_to_str(&d.name), "example.com") { ok = false; }
  }
  if dns_message_record_offset(&m, -1) != -1 { ok = false; }
  if dns_message_question_offset(&m, -5) != -1 { ok = false; }
  if dns_message_question_count(&m) != 1 { ok = false; }
  return assert(ok, "AAAA query: qtype 28 reaches the wire and parses back");
}

fn main() -> Int {
  io.println("=== xiom.dns conformance tests ===");
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
    io.println("xiom.dns: all tests passed");
  } else {
    io.println("xiom.dns: tests failed");
  }
  return failed;
}
