// XIOM -- xiom.multicast conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Conformance for the IGMPv2/v3 and MLD/MLDv2 codecs in xiom.multicast.
//
// The hardcoded wire fixtures were produced by an independent PowerShell
// one's-complement implementation:
//   * IGMPv2 query 224.0.0.1, Max Resp 100: 11 64 0e 9a e0 00 00 01;
//   * MLDv1 query fe80::1 -> ff02::1, delay 10000:
//     82 00 59 17 00 00 27 10 00*16;
//   * IGMPv2 report 239.1.2.3: 16 00 f8 fa ef 01 02 03.
// Every other packet is built in-test from the codec builders or assembled
// from byte helpers, then decoded and checked. Error strings are compared
// through xiom.string.compare.str_compare (BUG 17: `==` on a Str read from
// a Vec lowers to a pointer comparison) and every Vec element is read into
// a typed local first.

module multicast_tests
use xiom.io; use xiom.test;
use xiom.multicast;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;
use xiom.convert;

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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
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

fn suffix(v: Vec[UInt8], from: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = from;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn u16_vec(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((v / 256) as UInt8);
  out.push((v % 256) as UInt8);
  return out;
}

fn be32_vec(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((v / 16777216) as UInt8);
  out.push((v / 65536 % 256) as UInt8);
  out.push((v / 256 % 256) as UInt8);
  out.push((v % 256) as UInt8);
  return out;
}

fn zeros16() -> Vec[UInt8] {
  return repeat_byte(0, 16);
}

// --------------------------------------------------
//  Independent checksum reference
// --------------------------------------------------

fn ref_sum16(data: Vec[UInt8]) -> Int {
  var s = 0;
  var i = 0;
  while i + 1 < data.len() {
    let hi: Int = (data[i] as Int) & 0xFF;
    let lo: Int = (data[i + 1] as Int) & 0xFF;
    s = s + hi * 256 + lo;
    i = i + 2;
  }
  if i < data.len() {
    let hi2: Int = (data[i] as Int) & 0xFF;
    s = s + hi2 * 256;
  }
  return s;
}

fn ref_fold16(v: Int) -> Int {
  var s = v;
  while s > 65535 {
    s = s % 65536 + s / 65536;
  }
  return s;
}

fn ref_checksum16(data: Vec[UInt8]) -> Int {
  return 65535 - ref_fold16(ref_sum16(data));
}

// `body` with its zero checksum bytes at 2..3 replaced by the checksum
// computed by the independent reference.
fn insert_cs(body: Vec[UInt8]) -> Vec[UInt8] {
  let cs = ref_checksum16(body);
  return concat2(concat2(prefix(body, 2), u16_vec(cs)), suffix(body, 4));
}

// Word-level pseudo-header sum for a hand-checked ICMPv6 fixture.
fn ref_icmpv6_terms(src: Vec[UInt8], dst: Vec[UInt8], data: Vec[UInt8]) -> Int {
  var all = Vec[UInt8].new();
  all = concat2(all, src);
  all = concat2(all, dst);
  all = concat2(all, be32_vec(data.len()));
  all = concat2(all, hb("0000003a"));
  all = concat2(all, data);
  return ref_sum16(all);
}

// --------------------------------------------------
//  Packet assembly helpers
// --------------------------------------------------

fn igmp_query_v3_hdr(max_resp: Int, group: Int, flags: Int, qqic: Int, count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(17 as UInt8);
  out.push(max_resp as UInt8);
  out = concat2(out, u16_vec(0));
  out = concat2(out, be32_vec(group));
  out.push(flags as UInt8);
  out.push(qqic as UInt8);
  out = concat2(out, u16_vec(count));
  return out;
}

fn igmp_report_v3_hdr(count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(34 as UInt8);
  out.push(0 as UInt8);
  out = concat2(out, u16_vec(0));
  out = concat2(out, u16_vec(0));
  out = concat2(out, u16_vec(count));
  return out;
}

fn igmp_rec_hdr(rt: Int, aux_words: Int, n: Int, group: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(rt as UInt8);
  out.push(aux_words as UInt8);
  out = concat2(out, u16_vec(n));
  out = concat2(out, be32_vec(group));
  return out;
}

// MLDv2 query prefix: type 130, code 0, checksum 0, max resp, reserved 0,
// 16-byte group, flags/qqic zero.
fn mld_v2_prefix(max_resp: Int, group: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(130 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out = concat2(out, u16_vec(max_resp));
  out = concat2(out, u16_vec(0));
  out = concat2(out, group);
  out = concat2(out, u16_vec(0));
  return out;
}

fn mld_report_hdr(count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(143 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out = concat2(out, u16_vec(0));
  out = concat2(out, u16_vec(count));
  return out;
}

fn mld_rec_hdr(rt: Int, aux_words: Int, n: Int, group: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(rt as UInt8);
  out.push(aux_words as UInt8);
  out = concat2(out, u16_vec(n));
  out = concat2(out, group);
  return out;
}

// --------------------------------------------------
//  Result inspectors
// --------------------------------------------------

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_igmp_is(r: Result[IgmpMessage, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_mld_is(r: Result[MldMessage, Str], want: Str) -> Bool {
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

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  let br = igmp_build_query_v2(3758096385, 100);
  if !br.is_ok { return assert(false, "IGMPv2 query fixture round-trips"); }
  let pkt: Vec[UInt8] = br.value;
  if !bytes_equal(pkt, hb("11640e9ae0000001")) { ok = false; }
  if pkt.len() != 8 { ok = false; }
  let pr = igmp_parse(&pkt);
  if !pr.is_ok { ok = false; } else {
    let m: IgmpMessage = pr.value;
    if m.msg_type != IGMP_TYPE_QUERY { ok = false; }
    if m.version != 2 { ok = false; }
    if m.max_resp != 100 { ok = false; }
    if m.group != 3758096385 { ok = false; }
    if m.checksum != 3738 { ok = false; }
    if !m.checksum_ok { ok = false; }
    if igmp_query_variant(&m) != 1 { ok = false; }
    if igmp_version(&m) != 2 { ok = false; }
  }
  if igmp_checksum(&pkt) != 0 { ok = false; }
  if !igmp_checksum_valid(&pkt) { ok = false; }
  return assert(ok, "IGMPv2 query fixture 11 64 0e 9a e0 00 00 01 round-trips");
}

fn t2() -> TestResult {
  var ok = true;
  // v1 query: Max Resp Code 0 selects version 1
  let q1 = igmp_build_query_v2(0, 0);
  if !q1.is_ok { return assert(false, "IGMP v1/v2 reports, leave and v1 query"); }
  let qp: Vec[UInt8] = q1.value;
  let qr = igmp_parse(&qp);
  if !qr.is_ok { ok = false; } else {
    let m: IgmpMessage = qr.value;
    if m.version != 1 { ok = false; }
    if igmp_query_variant(&m) != 0 { ok = false; }
    if !m.checksum_ok { ok = false; }
  }
  // v1 report (0x12)
  let r1 = igmp_build_report_v1(3758096385);
  if !r1.is_ok { ok = false; } else {
    let p: Vec[UInt8] = r1.value;
    let rr = igmp_parse(&p);
    if !rr.is_ok { ok = false; } else {
      let m2: IgmpMessage = rr.value;
      if m2.msg_type != IGMP_TYPE_V1_REPORT { ok = false; }
      if m2.version != 1 { ok = false; }
      if m2.group != 3758096385 { ok = false; }
    }
  }
  // v2 report (0x16) and leave (0x17), plus the 239.1.2.3 fixture
  let r2 = igmp_build_report_v2(4026531839);
  if !r2.is_ok { ok = false; } else {
    let p2: Vec[UInt8] = r2.value;
    let rr2 = igmp_parse(&p2);
    if !rr2.is_ok { ok = false; } else {
      let m3: IgmpMessage = rr2.value;
      if m3.msg_type != IGMP_TYPE_V2_REPORT { ok = false; }
      if m3.version != 2 { ok = false; }
      if m3.group != 4026531839 { ok = false; }
    }
  }
  let lv = igmp_build_leave(3758096384);
  if !lv.is_ok { ok = false; } else {
    let lp: Vec[UInt8] = lv.value;
    let lr = igmp_parse(&lp);
    if !lr.is_ok { ok = false; } else {
      let m4: IgmpMessage = lr.value;
      if m4.msg_type != IGMP_TYPE_LEAVE { ok = false; }
      if m4.group != 3758096384 { ok = false; }
    }
  }
  let r3 = igmp_build_report_v2(4009820675);
  if !r3.is_ok { ok = false; } else {
    let p3: Vec[UInt8] = r3.value;
    if !bytes_equal(p3, hb("1600f8faef010203")) { ok = false; }
  }
  return assert(ok, "IGMPv1/v2 reports, leave and the v1 query round-trip; report fixture matches");
}

fn t3() -> TestResult {
  var ok = true;
  let body = concat2(hb("16000000"), hb("ef010203"));
  let cs = ref_checksum16(body);
  if cs != 63738 { ok = false; }
  if igmp_checksum(&body) != cs { ok = false; }
  let want = insert_cs(body);
  let br = igmp_build_report_v2(4009820675);
  if !br.is_ok { return assert(false, "IGMP checksum matches the independent reference"); }
  let pkt: Vec[UInt8] = br.value;
  if !bytes_equal(pkt, want) { ok = false; }
  // flip a bit in the group address: checksum flag must drop, parse still ok
  var bad = Vec[UInt8].new();
  var i = 0;
  while i < pkt.len() {
    if i == 6 {
      let b: Int = (pkt[i] as Int) & 0xFF;
      bad.push((b + 8) as UInt8);
    } else {
      bad.push(pkt[i]);
    }
    i = i + 1;
  }
  if igmp_checksum_valid(&bad) { ok = false; }
  let pr = igmp_parse(&bad);
  if !pr.is_ok { ok = false; } else {
    let m: IgmpMessage = pr.value;
    if m.checksum_ok { ok = false; }
    if m.checksum != 63738 { ok = false; }
  }
  return assert(ok, "IGMP checksum matches the independent reference and detects corruption");
}

fn t4() -> TestResult {
  var ok = true;
  var none = Vec[Int].new();
  let br = igmp_build_query_v3(0, 100, false, 2, 125, &none);
  if !br.is_ok { return assert(false, "IGMPv3 general query"); }
  let pkt: Vec[UInt8] = br.value;
  if pkt.len() != 12 { ok = false; }
  let b8: Int = (pkt[8] as Int) & 0xFF;
  let b9: Int = (pkt[9] as Int) & 0xFF;
  if b8 != 2 { ok = false; }
  if b9 != 125 { ok = false; }
  let pr = igmp_parse(&pkt);
  if !pr.is_ok { ok = false; } else {
    let m: IgmpMessage = pr.value;
    if m.version != 3 { ok = false; }
    if m.msg_type != IGMP_TYPE_QUERY { ok = false; }
    if m.group != 0 { ok = false; }
    if m.source_count != 0 { ok = false; }
    if m.suppress { ok = false; }
    if m.qrv != 2 { ok = false; }
    if m.qqic != 125 { ok = false; }
    if igmp_query_variant(&m) != 0 { ok = false; }
    if !m.checksum_ok { ok = false; }
  }
  // QRV 0 means "use default" and survives the round trip as raw 0
  let br2 = igmp_build_query_v3(0, 100, true, 0, 10, &none);
  if !br2.is_ok { ok = false; } else {
    let p2: Vec[UInt8] = br2.value;
    let pr2 = igmp_parse(&p2);
    if !pr2.is_ok { ok = false; } else {
      let m2: IgmpMessage = pr2.value;
      if !m2.suppress { ok = false; }
      if m2.qrv != 0 { ok = false; }
      if igmp_qrv_effective(m2.qrv) != 2 { ok = false; }
    }
  }
  return assert(ok, "IGMPv3 general query carries S/QRV/QQIC and defaults");
}

fn t5() -> TestResult {
  var ok = true;
  var srcs = Vec[Int].new();
  srcs.push(167772161);
  srcs.push(3758096385);
  let br = igmp_build_query_v3(3892379905, 100, false, 2, 0, &srcs);
  if !br.is_ok { return assert(false, "IGMPv3 group-and-source query"); }
  let pkt: Vec[UInt8] = br.value;
  if pkt.len() != 20 { ok = false; }
  let pr = igmp_parse(&pkt);
  if !pr.is_ok { ok = false; } else {
    let m: IgmpMessage = pr.value;
    if m.version != 3 { ok = false; }
    if m.group != 3892379905 { ok = false; }
    if m.source_count != 2 { ok = false; }
    if igmp_query_variant(&m) != 2 { ok = false; }
    if igmp_source_at(&pkt, &m, 0) != 167772161 { ok = false; }
    if igmp_source_at(&pkt, &m, 1) != 3758096385 { ok = false; }
    if igmp_source_at(&pkt, &m, 2) != -1 { ok = false; }
    if igmp_source_at(&pkt, &m, -1) != -1 { ok = false; }
    // a shorter buffer makes the recorded span unusable
    let short = prefix(pkt, 16);
    if igmp_source_at(&short, &m, 1) != -1 { ok = false; }
  }
  return assert(ok, "IGMPv3 group-and-source query exposes its source list");
}

fn t6() -> TestResult {
  var ok = true;
  var rts = Vec[Int].new();
  rts.push(1);
  rts.push(2);
  rts.push(3);
  rts.push(4);
  rts.push(5);
  rts.push(6);
  var grps = Vec[Int].new();
  var g = 3758096385;
  var i = 0;
  while i < 6 {
    grps.push(g + i);
    i = i + 1;
  }
  var scnts = Vec[Int].new();
  scnts.push(1);
  scnts.push(0);
  scnts.push(2);
  scnts.push(0);
  scnts.push(1);
  scnts.push(0);
  var srcs = Vec[Int].new();
  srcs.push(167772161);
  srcs.push(167772162);
  srcs.push(167772163);
  srcs.push(4294967295);
  var aux = Vec[Vec[UInt8]].new();
  aux.push(hb("deadbeef"));
  let empty = Vec[UInt8].new();
  aux.push(empty);
  aux.push(empty);
  aux.push(empty);
  aux.push(empty);
  aux.push(empty);
  let br = igmp_build_report_v3(&rts, &grps, &scnts, &srcs, &aux);
  if !br.is_ok { return assert(false, "IGMPv3 report with all six record types"); }
  let pkt: Vec[UInt8] = br.value;
  if pkt.len() != 76 { ok = false; }
  let pr = igmp_parse(&pkt);
  if !pr.is_ok { ok = false; } else {
    let m: IgmpMessage = pr.value;
    if m.version != 3 { ok = false; }
    if igmp_record_count(&m) != 6 { ok = false; }
    if !m.checksum_ok { ok = false; }
    var k = 0;
    while k < 6 {
      if igmp_record_type(&m, k) != rts[k] { ok = false; }
      if igmp_record_group(&m, k) != grps[k] { ok = false; }
      if igmp_record_source_count(&m, k) != scnts[k] { ok = false; }
      k = k + 1;
    }
    if igmp_record_aux_bytes(&m, 0) != 4 { ok = false; }
    if igmp_record_aux_bytes(&m, 1) != 0 { ok = false; }
    if !bytes_is(igmp_record_aux(&pkt, &m, 0), hb("deadbeef")) { ok = false; }
    if !bytes_is(igmp_record_aux(&pkt, &m, 1), Vec[UInt8].new()) { ok = false; }
    if igmp_record_source_at(&pkt, &m, 0, 0) != 167772161 { ok = false; }
    if igmp_record_source_at(&pkt, &m, 2, 0) != 167772162 { ok = false; }
    if igmp_record_source_at(&pkt, &m, 2, 1) != 167772163 { ok = false; }
    if igmp_record_source_at(&pkt, &m, 4, 0) != 4294967295 { ok = false; }
    if igmp_record_source_at(&pkt, &m, 2, 2) != -1 { ok = false; }
    if igmp_record_source_at(&pkt, &m, 6, 0) != -1 { ok = false; }
    if igmp_record_type(&m, -1) != -1 { ok = false; }
  }
  return assert(ok, "IGMPv3 report carries all six record types, sources and aux data");
}

fn t7() -> TestResult {
  var ok = true;
  var rts = Vec[Int].new();
  rts.push(1);
  rts.push(3);
  var grps = Vec[Int].new();
  grps.push(3758096385);
  grps.push(4026531839);
  var scnts = Vec[Int].new();
  scnts.push(2);
  scnts.push(1);
  var srcs = Vec[Int].new();
  srcs.push(167772161);
  srcs.push(167772162);
  srcs.push(167772163);
  var aux = Vec[Vec[UInt8]].new();
  aux.push(hb("01020304"));
  let empty = Vec[UInt8].new();
  aux.push(empty);
  let br = igmp_build_report_v3(&rts, &grps, &scnts, &srcs, &aux);
  if !br.is_ok { return assert(false, "IGMPv3 report decode/re-encode round-trip"); }
  let pkt: Vec[UInt8] = br.value;
  let pr = igmp_parse(&pkt);
  if !pr.is_ok { ok = false; } else {
    let m: IgmpMessage = pr.value;
    // rebuild the input vectors from the decoded accessors
    var rts2 = Vec[Int].new();
    var grps2 = Vec[Int].new();
    var scnts2 = Vec[Int].new();
    var srcs2 = Vec[Int].new();
    var aux2 = Vec[Vec[UInt8]].new();
    var k = 0;
    while k < igmp_record_count(&m) {
      rts2.push(igmp_record_type(&m, k));
      grps2.push(igmp_record_group(&m, k));
      let c = igmp_record_source_count(&m, k);
      scnts2.push(c);
      var q = 0;
      while q < c {
        srcs2.push(igmp_record_source_at(&pkt, &m, k, q));
        q = q + 1;
      }
      let ar = igmp_record_aux(&pkt, &m, k);
      if !ar.is_ok { ok = false; } else {
        let av: Vec[UInt8] = ar.value;
        aux2.push(av);
      }
      k = k + 1;
    }
    let br2 = igmp_build_report_v3(&rts2, &grps2, &scnts2, &srcs2, &aux2);
    if !br2.is_ok { ok = false; } else {
      let pkt2: Vec[UInt8] = br2.value;
      if !bytes_equal(pkt, pkt2) { ok = false; }
    }
  }
  return assert(ok, "IGMPv3 report decodes and re-encodes byte-identically");
}

fn t8() -> TestResult {
  var ok = true;
  if !err_igmp_is(igmp_parse(&hb("1100aabb0000")), "igmp: short message") { ok = false; }
  if !err_igmp_is(igmp_parse(&hb("ff00646400000000")), "igmp: bad message type at 0") { ok = false; }
  let ten = concat2(hb("11640000e0000001"), hb("0000"));
  if !err_igmp_is(igmp_parse(&ten), "igmp: bad v3 query length at 8") { ok = false; }
  let truncated = igmp_query_v3_hdr(100, 3758096385, 0, 0, 2);
  if !err_igmp_is(igmp_parse(&truncated), "igmp: truncated source list at 12") { ok = false; }
  let trailing = concat2(igmp_query_v3_hdr(100, 3758096385, 0, 0, 0), be32_vec(0));
  if !err_igmp_is(igmp_parse(&trailing), "igmp: trailing bytes at 12") { ok = false; }
  let longrep = concat2(hb("16000000ef010203"), be32_vec(0));
  if !err_igmp_is(igmp_parse(&longrep), "igmp: bad length at 8") { ok = false; }
  let nine = concat2(hb("11640000e0000001"), hb("00"));
  if !err_igmp_is(igmp_parse(&nine), "igmp: bad v3 query length at 8") { ok = false; }
  return assert(ok, "IGMP length, type and count errors carry byte offsets");
}

fn t9() -> TestResult {
  var ok = true;
  let badcount = igmp_report_v3_hdr(2);
  if badcount.len() != 8 { ok = false; }
  if !err_igmp_is(igmp_parse(&badcount), "igmp: bad record count at 6") { ok = false; }
  let trailing = concat2(igmp_report_v3_hdr(0), be32_vec(0));
  if !err_igmp_is(igmp_parse(&trailing), "igmp: trailing bytes at 8") { ok = false; }
  let trunc = concat2(concat2(concat2(concat2(igmp_report_v3_hdr(3), igmp_rec_hdr(1, 0, 0, 0)), igmp_rec_hdr(1, 0, 1, 0)), be32_vec(0)), be32_vec(0));
  if !err_igmp_is(igmp_parse(&trunc), "igmp: truncated record at 28") { ok = false; }
  let badrt = concat2(igmp_report_v3_hdr(1), igmp_rec_hdr(7, 0, 0, 3758096385));
  if !err_igmp_is(igmp_parse(&badrt), "igmp: bad record type at 8") { ok = false; }
  let truncsrc = concat2(igmp_report_v3_hdr(1), igmp_rec_hdr(1, 0, 1, 3758096385));
  if !err_igmp_is(igmp_parse(&truncsrc), "igmp: truncated source list at 16") { ok = false; }
  let badaux = concat2(igmp_report_v3_hdr(1), igmp_rec_hdr(1, 1, 0, 3758096385));
  if !err_igmp_is(igmp_parse(&badaux), "igmp: bad aux data length at 16") { ok = false; }
  return assert(ok, "IGMPv3 record errors reject bad types, counts and spans with offsets");
}

fn t10() -> TestResult {
  var ok = true;
  let src = hb("fe800000000000000000000000000001");
  let dst = hb("ff020000000000000000000000000001");
  let group = zeros16();
  let q = mld_build_query_v1(&src, &dst, &group, 10000);
  if !q.is_ok { return assert(false, "MLDv1 query fixture and report/done round-trips"); }
  let pkt: Vec[UInt8] = q.value;
  if !bytes_equal(pkt, hb("820059170000271000000000000000000000000000000000")) { ok = false; }
  if pkt.len() != 24 { ok = false; }
  let pr = mld_parse(&pkt);
  if !pr.is_ok { ok = false; } else {
    let m: MldMessage = pr.value;
    if m.msg_type != MLD_TYPE_QUERY { ok = false; }
    if m.version != 1 { ok = false; }
    if m.max_delay != 10000 { ok = false; }
    if m.checksum != 22807 { ok = false; }
    if mld_query_variant(&m) != 0 { ok = false; }
    if mld_version(&m) != 1 { ok = false; }
    let g: Vec[UInt8] = mld_group(&m);
    if !bytes_equal(g, zeros16()) { ok = false; }
  }
  if !icmpv6_checksum_valid(&src, &dst, &pkt) { ok = false; }
  let wrong = hb("fe800000000000000000000000000002");
  if icmpv6_checksum_valid(&src, &wrong, &pkt) { ok = false; }
  if icmpv6_checksum(&src, &dst, &pkt) != 0 { ok = false; }
  // the pseudo-header reference reproduces the independent fixture
  var zeroed = Vec[UInt8].new();
  var zi = 0;
  while zi < pkt.len() {
    if zi == 2 || zi == 3 {
      zeroed.push(0 as UInt8);
    } else {
      zeroed.push(pkt[zi]);
    }
    zi = zi + 1;
  }
  if 65535 - ref_fold16(ref_icmpv6_terms(src, dst, zeroed)) != 22807 { ok = false; }
  if icmpv6_checksum(&src, &dst, &zeroed) != 22807 { ok = false; }
  // MLDv1 report (131) and done (132) are sent to the group itself
  let mg = hb("ff3e0000000000000000000000000101");
  let r = mld_build_report_v1(&src, &mg, &mg);
  if !r.is_ok { ok = false; } else {
    let rp: Vec[UInt8] = r.value;
    if rp.len() != 24 { ok = false; }
    let rr = mld_parse(&rp);
    if !rr.is_ok { ok = false; } else {
      let m2: MldMessage = rr.value;
      if m2.msg_type != MLD_TYPE_REPORT { ok = false; }
      if m2.version != 1 { ok = false; }
      if m2.max_delay != 0 { ok = false; }
      let g2: Vec[UInt8] = mld_group(&m2);
      if !bytes_equal(g2, mg) { ok = false; }
    }
    if !icmpv6_checksum_valid(&src, &mg, &rp) { ok = false; }
  }
  let d = mld_build_done(&src, &mg, &mg);
  if !d.is_ok { ok = false; } else {
    let dp: Vec[UInt8] = d.value;
    let dr = mld_parse(&dp);
    if !dr.is_ok { ok = false; } else {
      let m3: MldMessage = dr.value;
      if m3.msg_type != MLD_TYPE_DONE { ok = false; }
      if m3.version != 1 { ok = false; }
    }
  }
  return assert(ok, "MLDv1 query fixture round-trips; report and done carry the group and checksum");
}

fn t11() -> TestResult {
  var ok = true;
  let src = hb("fe800000000000000000000000000001");
  let dst = hb("ff020000000000000000000000000001");
  let group = hb("ff3e0000000000000000000000000101");
  var srcs = Vec[Vec[UInt8]].new();
  srcs.push(hb("20010db8000000000000000000000001"));
  srcs.push(hb("20010db8000000000000000000000002"));
  let br = mld_build_query_v2(&src, &dst, &group, 10000, false, 2, 125, &srcs);
  if !br.is_ok { return assert(false, "MLDv2 query with sources"); }
  let pkt: Vec[UInt8] = br.value;
  if pkt.len() != 60 { ok = false; }
  let pr = mld_parse(&pkt);
  if !pr.is_ok { ok = false; } else {
    let m: MldMessage = pr.value;
    if m.version != 2 { ok = false; }
    if m.max_resp != 10000 { ok = false; }
    if m.reserved != 0 { ok = false; }
    if m.source_count != 2 { ok = false; }
    if m.qrv != 2 { ok = false; }
    if m.qqic != 125 { ok = false; }
    if m.suppress { ok = false; }
    if mld_query_variant(&m) != 2 { ok = false; }
    if !bytes_is(mld_source_at(&pkt, &m, 0), hb("20010db8000000000000000000000001")) { ok = false; }
    if !bytes_is(mld_source_at(&pkt, &m, 1), hb("20010db8000000000000000000000002")) { ok = false; }
    if !err_bytes_is(mld_source_at(&pkt, &m, 2), "mld: source index out of range") { ok = false; }
    if !err_bytes_is(mld_source_at(&pkt, &m, -1), "mld: source index out of range") { ok = false; }
  }
  if !icmpv6_checksum_valid(&src, &dst, &pkt) { ok = false; }
  if icmpv6_checksum_valid(&dst, &dst, &pkt) { ok = false; }
  // group-specific variant (no sources)
  var none = Vec[Vec[UInt8]].new();
  let b2 = mld_build_query_v2(&src, &dst, &group, 10000, true, 3, 10, &none);
  if !b2.is_ok { ok = false; } else {
    let p2: Vec[UInt8] = b2.value;
    if p2.len() != 28 { ok = false; }
    let pr2 = mld_parse(&p2);
    if !pr2.is_ok { ok = false; } else {
      let m2: MldMessage = pr2.value;
      if mld_query_variant(&m2) != 1 { ok = false; }
      if !m2.suppress { ok = false; }
    }
  }
  return assert(ok, "MLDv2 query with S/QRV/QQIC and sources round-trips over the pseudo-header");
}

fn t12() -> TestResult {
  var ok = true;
  let src = hb("fe800000000000000000000000000001");
  let dst = hb("ff020000000000000000000000000001");
  var rts = Vec[Int].new();
  rts.push(1);
  rts.push(2);
  var grps = Vec[Vec[UInt8]].new();
  grps.push(hb("ff3e0000000000000000000000000001"));
  grps.push(hb("ff3e0000000000000000000000000002"));
  var scnts = Vec[Int].new();
  scnts.push(1);
  scnts.push(1);
  var srcs = Vec[Vec[UInt8]].new();
  srcs.push(hb("20010db800000000000000000000000a"));
  srcs.push(hb("20010db800000000000000000000000b"));
  var aux = Vec[Vec[UInt8]].new();
  aux.push(hb("01020304"));
  let empty = Vec[UInt8].new();
  aux.push(empty);
  let br = mld_build_report_v2(&src, &dst, &rts, &grps, &scnts, &srcs, &aux);
  if !br.is_ok { return assert(false, "MLDv2 report records and round-trip"); }
  let pkt: Vec[UInt8] = br.value;
  if pkt.len() != 84 { ok = false; }
  let pr = mld_parse(&pkt);
  if !pr.is_ok { ok = false; } else {
    let m: MldMessage = pr.value;
    if m.version != 2 { ok = false; }
    if mld_record_count(&m) != 2 { ok = false; }
    if mld_record_type(&m, 0) != 1 { ok = false; }
    if mld_record_type(&m, 1) != 2 { ok = false; }
    if mld_record_source_count(&m, 0) != 1 { ok = false; }
    if !bytes_is(mld_record_group(&pkt, &m, 0), hb("ff3e0000000000000000000000000001")) { ok = false; }
    if !bytes_is(mld_record_group(&pkt, &m, 1), hb("ff3e0000000000000000000000000002")) { ok = false; }
    if !bytes_is(mld_record_source_at(&pkt, &m, 0, 0), hb("20010db800000000000000000000000a")) { ok = false; }
    if !bytes_is(mld_record_source_at(&pkt, &m, 1, 0), hb("20010db800000000000000000000000b")) { ok = false; }
    if mld_record_aux_bytes(&m, 0) != 4 { ok = false; }
    if !bytes_is(mld_record_aux(&pkt, &m, 0), hb("01020304")) { ok = false; }
    if !bytes_is(mld_record_aux(&pkt, &m, 1), Vec[UInt8].new()) { ok = false; }
    if !err_bytes_is(mld_record_group(&pkt, &m, 2), "mld: record index out of range") { ok = false; }
    if !err_bytes_is(mld_record_source_at(&pkt, &m, 0, 1), "mld: source index out of range") { ok = false; }
    // decode/re-encode round trip from the accessors
    var rts2 = Vec[Int].new();
    var grps2 = Vec[Vec[UInt8]].new();
    var scnts2 = Vec[Int].new();
    var srcs2 = Vec[Vec[UInt8]].new();
    var aux2 = Vec[Vec[UInt8]].new();
    var k = 0;
    while k < mld_record_count(&m) {
      rts2.push(mld_record_type(&m, k));
      scnts2.push(mld_record_source_count(&m, k));
      let gr = mld_record_group(&pkt, &m, k);
      if !gr.is_ok { ok = false; } else {
        let gv: Vec[UInt8] = gr.value;
        grps2.push(gv);
      }
      let c = mld_record_source_count(&m, k);
      var q = 0;
      while q < c {
        let sr = mld_record_source_at(&pkt, &m, k, q);
        if !sr.is_ok { ok = false; } else {
          let sv: Vec[UInt8] = sr.value;
          srcs2.push(sv);
        }
        q = q + 1;
      }
      let ar = mld_record_aux(&pkt, &m, k);
      if !ar.is_ok { ok = false; } else {
        let av: Vec[UInt8] = ar.value;
        aux2.push(av);
      }
      k = k + 1;
    }
    let br2 = mld_build_report_v2(&src, &dst, &rts2, &grps2, &scnts2, &srcs2, &aux2);
    if !br2.is_ok { ok = false; } else {
      let pkt2: Vec[UInt8] = br2.value;
      if !bytes_equal(pkt, pkt2) { ok = false; }
    }
  }
  if !icmpv6_checksum_valid(&src, &dst, &pkt) { ok = false; }
  return assert(ok, "MLDv2 report records, aux data and decode/re-encode round-trip");
}

fn t13() -> TestResult {
  var ok = true;
  if !err_mld_is(mld_parse(&hb("82000000")), "mld: short message") { ok = false; }
  if !err_mld_is(mld_parse(&hb("400000000000000000000000000000000000000000000000")), "mld: bad message type at 0") { ok = false; }
  let q26 = concat2(hb("82000000"), repeat_byte(0, 22));
  if !err_mld_is(mld_parse(&q26), "mld: bad query length at 24") { ok = false; }
  let trunc = concat2(mld_v2_prefix(10000, zeros16()), u16_vec(2));
  if !err_mld_is(mld_parse(&trunc), "mld: truncated source list at 28") { ok = false; }
  let trailing = concat2(concat2(mld_v2_prefix(10000, zeros16()), u16_vec(0)), zeros16());
  if !err_mld_is(mld_parse(&trailing), "mld: trailing bytes at 28") { ok = false; }
  let badrep = concat2(hb("83000000"), repeat_byte(0, 22));
  if !err_mld_is(mld_parse(&badrep), "mld: bad length at 24") { ok = false; }
  let badcount = mld_report_hdr(2);
  if !err_mld_is(mld_parse(&badcount), "mld: bad record count at 6") { ok = false; }
  let truncrec = concat2(concat2(concat2(mld_report_hdr(3), mld_rec_hdr(1, 0, 0, zeros16())), mld_rec_hdr(1, 2, 0, zeros16())), repeat_byte(0, 20));
  if !err_mld_is(mld_parse(&truncrec), "mld: truncated record at 56") { ok = false; }
  let badrt = concat2(mld_report_hdr(1), mld_rec_hdr(9, 0, 0, zeros16()));
  if !err_mld_is(mld_parse(&badrt), "mld: bad record type at 8") { ok = false; }
  let truncsrc = concat2(mld_report_hdr(1), mld_rec_hdr(1, 0, 1, zeros16()));
  if !err_mld_is(mld_parse(&truncsrc), "mld: truncated source list at 28") { ok = false; }
  let badaux = concat2(mld_report_hdr(1), mld_rec_hdr(1, 1, 0, zeros16()));
  if !err_mld_is(mld_parse(&badaux), "mld: bad aux data length at 28") { ok = false; }
  return assert(ok, "MLD length, type, count and record errors carry byte offsets");
}

fn t14() -> TestResult {
  var ok = true;
  if igmp_max_resp_ms(0) != 0 { ok = false; }
  if igmp_max_resp_ms(1) != 100 { ok = false; }
  if igmp_max_resp_ms(100) != 10000 { ok = false; }
  if igmp_max_resp_ms(127) != 12700 { ok = false; }
  if igmp_max_resp_ms(128) != 12800 { ok = false; }
  if igmp_max_resp_ms(255) != 3174400 { ok = false; }
  if igmp_max_resp_ms(-1) != -1 { ok = false; }
  if igmp_max_resp_ms(256) != -1 { ok = false; }
  if igmp_qqic_seconds(125) != 125 { ok = false; }
  if igmp_qqic_seconds(128) != 128 { ok = false; }
  if igmp_qqic_seconds(255) != 31744 { ok = false; }
  if igmp_qqic_seconds(-1) != -1 { ok = false; }
  if mld_max_resp_ms(10000) != 10000 { ok = false; }
  if mld_max_resp_ms(32767) != 32767 { ok = false; }
  if mld_max_resp_ms(32768) != 32768 { ok = false; }
  if mld_max_resp_ms(65535) != 8387584 { ok = false; }
  if mld_max_resp_ms(65536) != -1 { ok = false; }
  if igmp_qrv_effective(0) != 2 { ok = false; }
  if igmp_qrv_effective(7) != 7 { ok = false; }
  if !igmp_is_multicast(3758096384) { ok = false; }
  if !igmp_is_multicast(4026531839) { ok = false; }
  if igmp_is_multicast(3758096383) { ok = false; }
  if igmp_is_multicast(4026531840) { ok = false; }
  let mcast = hb("ff020000000000000000000000000001");
  let ucast = hb("fe800000000000000000000000000001");
  let short = hb("ff0200000000000000000000000000");
  if !mld_is_multicast(&mcast) { ok = false; }
  if mld_is_multicast(&ucast) { ok = false; }
  if mld_is_multicast(&short) { ok = false; }
  if !str_eq(igmp_message_name(17), "membership query") { ok = false; }
  if !str_eq(igmp_message_name(18), "v1 membership report") { ok = false; }
  if !str_eq(igmp_message_name(22), "v2 membership report") { ok = false; }
  if !str_eq(igmp_message_name(23), "leave group") { ok = false; }
  if !str_eq(igmp_message_name(34), "v3 membership report") { ok = false; }
  if !str_eq(igmp_message_name(0), "unknown") { ok = false; }
  if !str_eq(igmp_record_type_name(1), "mode is include") { ok = false; }
  if !str_eq(igmp_record_type_name(6), "block old sources") { ok = false; }
  if !str_eq(igmp_record_type_name(7), "unknown") { ok = false; }
  if !str_eq(mld_message_name(130), "multicast listener query") { ok = false; }
  if !str_eq(mld_message_name(131), "multicast listener report") { ok = false; }
  if !str_eq(mld_message_name(132), "multicast listener done") { ok = false; }
  if !str_eq(mld_message_name(143), "version 2 multicast listener report") { ok = false; }
  if !str_eq(mld_message_name(129), "unknown") { ok = false; }
  return assert(ok, "code decoding, multicast classification and name tables are stable");
}

fn t15() -> TestResult {
  var ok = true;
  let e1 = igmp_build_query_v2(-1, 100);
  if !err_bytes_is(e1, "igmp: bad group address") { ok = false; }
  let e2 = igmp_build_query_v2(0, 256);
  if !err_bytes_is(e2, "igmp: bad max resp code") { ok = false; }
  var none = Vec[Int].new();
  let e3 = igmp_build_query_v3(0, 100, false, 8, 0, &none);
  if !err_bytes_is(e3, "igmp: bad qrv") { ok = false; }
  let e4 = igmp_build_query_v3(0, 100, false, 0, 256, &none);
  if !err_bytes_is(e4, "igmp: bad qqic") { ok = false; }
  var big = Vec[Int].new();
  big.push(4294967296);
  let e5 = igmp_build_query_v3(0, 100, false, 0, 0, &big);
  if !err_bytes_is(e5, "igmp: bad source address") { ok = false; }
  var rt1 = Vec[Int].new();
  rt1.push(1);
  var none_i = Vec[Int].new();
  var none_a = Vec[Vec[UInt8]].new();
  let e6 = igmp_build_report_v3(&rt1, &none_i, &none_i, &none_i, &none_a);
  if !err_bytes_is(e6, "igmp: record vector length mismatch") { ok = false; }
  var rt7 = Vec[Int].new();
  rt7.push(7);
  var g0 = Vec[Int].new();
  g0.push(0);
  var c0 = Vec[Int].new();
  c0.push(0);
  var a0 = Vec[Vec[UInt8]].new();
  a0.push(Vec[UInt8].new());
  let e7 = igmp_build_report_v3(&rt7, &g0, &c0, &none_i, &a0);
  if !err_bytes_is(e7, "igmp: bad record type at index 0") { ok = false; }
  var rt1b = Vec[Int].new();
  rt1b.push(1);
  var g0b = Vec[Int].new();
  g0b.push(0);
  var c1b = Vec[Int].new();
  c1b.push(1);
  var a0b = Vec[Vec[UInt8]].new();
  a0b.push(Vec[UInt8].new());
  let e8 = igmp_build_report_v3(&rt1b, &g0b, &c1b, &none_i, &a0b);
  if !err_bytes_is(e8, "igmp: source vector length mismatch") { ok = false; }
  var c0c = Vec[Int].new();
  c0c.push(0);
  var a2c = Vec[Vec[UInt8]].new();
  a2c.push(hb("0102"));
  let e9 = igmp_build_report_v3(&rt1b, &g0b, &c0c, &none_i, &a2c);
  if !err_bytes_is(e9, "igmp: bad aux data length at index 0") { ok = false; }
  let src = hb("fe800000000000000000000000000001");
  let dst = hb("ff020000000000000000000000000001");
  let group = zeros16();
  let short15 = hb("fe80000000000000000000000000000");
  let me1 = mld_build_query_v1(&short15, &dst, &group, 0);
  if !err_bytes_is(me1, "mld: bad source address length") { ok = false; }
  let me2 = mld_build_query_v1(&src, &dst, &short15, 0);
  if !err_bytes_is(me2, "mld: bad group address length") { ok = false; }
  var bad_srcs = Vec[Vec[UInt8]].new();
  bad_srcs.push(short15);
  let me3 = mld_build_query_v2(&src, &dst, &group, 100, false, 0, 0, &bad_srcs);
  if !err_bytes_is(me3, "mld: bad source address length") { ok = false; }
  var grps_bad = Vec[Vec[UInt8]].new();
  grps_bad.push(short15);
  var sc0 = Vec[Int].new();
  sc0.push(0);
  var none16 = Vec[Vec[UInt8]].new();
  var aux0 = Vec[Vec[UInt8]].new();
  aux0.push(Vec[UInt8].new());
  let me4 = mld_build_report_v2(&src, &dst, &rt1b, &grps_bad, &sc0, &none16, &aux0);
  if !err_bytes_is(me4, "mld: bad group address length") { ok = false; }
  let me5 = mld_build_report_v2(&short15, &dst, &rt1b, &grps_bad, &sc0, &none16, &aux0);
  if !err_bytes_is(me5, "mld: bad source address length") { ok = false; }
  let me6 = mld_build_query_v1(&src, &dst, &group, -1);
  if !err_bytes_is(me6, "mld: bad max response delay") { ok = false; }
  return assert(ok, "every builder rejects malformed input with a stable error");
}

fn t16() -> TestResult {
  var ok = true;
  // accessor guards on a message with no records and no sources
  let src = hb("fe800000000000000000000000000001");
  let dst = hb("ff020000000000000000000000000001");
  let group = hb("ff3e0000000000000000000000000101");
  let r = mld_build_report_v1(&src, &dst, &group);
  if !r.is_ok { return assert(false, "accessor guards"); }
  let pkt: Vec[UInt8] = r.value;
  let pr = mld_parse(&pkt);
  if !pr.is_ok { ok = false; } else {
    let m: MldMessage = pr.value;
    if mld_record_count(&m) != 0 { ok = false; }
    if mld_record_type(&m, 0) != -1 { ok = false; }
    if mld_record_source_count(&m, 0) != -1 { ok = false; }
    if mld_record_aux_bytes(&m, 0) != -1 { ok = false; }
    if !err_bytes_is(mld_record_group(&pkt, &m, 0), "mld: record index out of range") { ok = false; }
    if !err_bytes_is(mld_record_aux(&pkt, &m, 0), "mld: record index out of range") { ok = false; }
    if !err_bytes_is(mld_source_at(&pkt, &m, 0), "mld: source index out of range") { ok = false; }
    let j = igmp_build_report_v2(3758096385);
    if j.is_ok {
      let jp: Vec[UInt8] = j.value;
      let jr = igmp_parse(&jp);
      if jr.is_ok {
        let jm: IgmpMessage = jr.value;
        if igmp_record_count(&jm) != 0 { ok = false; }
        if igmp_record_type(&jm, 0) != -1 { ok = false; }
        if igmp_record_group(&jm, 0) != -1 { ok = false; }
        if igmp_record_source_count(&jm, 0) != -1 { ok = false; }
        if igmp_record_aux_bytes(&jm, 0) != -1 { ok = false; }
        if !err_bytes_is(igmp_record_aux(&jp, &jm, 0), "igmp: record index out of range") { ok = false; }
        if igmp_source_at(&jp, &jm, 0) != -1 { ok = false; }
      } else { ok = false; }
    } else { ok = false; }
  }
  // pseudo-header helpers validate their address lengths
  let short15 = hb("fe80000000000000000000000000000");
  if icmpv6_checksum(&short15, &dst, &pkt) != -1 { ok = false; }
  if icmpv6_checksum(&src, &short15, &pkt) != -1 { ok = false; }
  if icmpv6_checksum_valid(&short15, &dst, &pkt) { ok = false; }
  return assert(ok, "accessor and checksum guards reject out-of-range indices and lengths");
}

fn t17() -> TestResult {
  var ok = true;
  // odd-length buffers pad the trailing byte on the right
  let three = hb("010203");
  if ref_sum16(three) != 1026 { ok = false; }
  if igmp_checksum(&three) != 64509 { ok = false; }
  let one = hb("ff");
  if igmp_checksum(&one) != 255 { ok = false; }
  let empty = Vec[UInt8].new();
  if igmp_checksum(&empty) != 65535 { ok = false; }
  if igmp_checksum_valid(&empty) { ok = false; }
  // a real message plus its checksum validates; flipping any byte breaks it
  let body = concat2(hb("11000000"), hb("e0000001"));
  let pkt = insert_cs(body);
  if !igmp_checksum_valid(&pkt) { ok = false; }
  var k = 0;
  while k < pkt.len() {
    var bad = Vec[UInt8].new();
    var i = 0;
    while i < pkt.len() {
      if i == k {
        let b: Int = (pkt[i] as Int) & 0xFF;
        bad.push((b + 1) as UInt8);
      } else {
        bad.push(pkt[i]);
      }
      i = i + 1;
    }
    if igmp_checksum_valid(&bad) { ok = false; }
    k = k + 1;
  }
  return assert(ok, "one's-complement checksum pads odd bytes and rejects every single-byte flip");
}

fn t18() -> TestResult {
  var ok = true;
  // high-bit addresses exercise widen-and-mask and unsigned packing
  var rts = Vec[Int].new();
  rts.push(1);
  var grps = Vec[Int].new();
  grps.push(4026531839);
  var scnts = Vec[Int].new();
  scnts.push(3);
  var srcs = Vec[Int].new();
  srcs.push(4294967295);
  srcs.push(2147483648);
  srcs.push(3758096385);
  var aux = Vec[Vec[UInt8]].new();
  aux.push(Vec[UInt8].new());
  let br = igmp_build_report_v3(&rts, &grps, &scnts, &srcs, &aux);
  if !br.is_ok { return assert(false, "high-bit address round-trip"); }
  let pkt: Vec[UInt8] = br.value;
  let pr = igmp_parse(&pkt);
  if !pr.is_ok { ok = false; } else {
    let m: IgmpMessage = pr.value;
    if igmp_record_group(&m, 0) != 4026531839 { ok = false; }
    if igmp_record_source_at(&pkt, &m, 0, 0) != 4294967295 { ok = false; }
    if igmp_record_source_at(&pkt, &m, 0, 1) != 2147483648 { ok = false; }
    if igmp_record_source_at(&pkt, &m, 0, 2) != 3758096385 { ok = false; }
    if !m.checksum_ok { ok = false; }
    if igmp_source_at(&pkt, &m, 0) != -1 { ok = false; }
  }
  // MLDv2 query with a high-bit-heavy source address
  let src = hb("fe800000000000000000000000000001");
  let dst = hb("ff020000000000000000000000000001");
  let group = hb("ff3e0000000000000000000000000101");
  var msrcs = Vec[Vec[UInt8]].new();
  msrcs.push(hb("ffffffffffffffffffffffffffffffff"));
  let mb = mld_build_query_v2(&src, &dst, &group, 100, false, 7, 255, &msrcs);
  if !mb.is_ok { ok = false; } else {
    let mp: Vec[UInt8] = mb.value;
    let mr = mld_parse(&mp);
    if !mr.is_ok { ok = false; } else {
      let mm: MldMessage = mr.value;
      if !bytes_is(mld_source_at(&mp, &mm, 0), hb("ffffffffffffffffffffffffffffffff")) { ok = false; }
      if mm.qrv != 7 { ok = false; }
      if mm.qqic != 255 { ok = false; }
    }
    if !icmpv6_checksum_valid(&src, &dst, &mp) { ok = false; }
  }
  return assert(ok, "addresses with the high bit set survive packing and unpacking");
}

// --------------------------------------------------
//  Driver
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.multicast conformance tests ===");
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
    io.println("xiom.multicast: all tests passed");
  } else {
    io.println("xiom.multicast: tests failed");
  }
  return failed;
}
