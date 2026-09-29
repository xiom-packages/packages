// XIOM -- xiom.streaming conformance tests (21 checks)
// Port task: prove the pure-XIOM RTP/RTCP/RTSP codecs against the byte-level
// tables pinned in SPEC.md: RTP header round-trips (basic, CSRC list, header
// extension, padding), wrap-safe sequence and timestamp arithmetic, the
// RFC 3550 A.8 jitter estimator and its sliding window, RTCP SR/RR headers
// and 24-byte report blocks (fraction lost, signed cumulative loss,
// extended highest sequence, jitter, LSR, DLSR), RTSP request/response
// parse and canonical build, and the full error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every pinned byte string below was derived by hand from the layouts in
// SPEC.md. All fixtures are built in-test; no file, socket, or device is
// touched (the library is codec-only).
//
// BUG 17 discipline: no Str value is compared with `==`; string equality
// goes through xiom.string.compare.str_compare. Vec element reads are bound
// to typed locals and every Bool comparison uses bool_eq instead of `==`.

module streaming_tests
use xiom.io; use xiom.test;
use xiom.streaming;
use xiom.string.compare;
use xiom.convert;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers (independent of src/streaming.xi)
// --------------------------------------------------

// Bytes for a hex string; "" on malformed input (the test then fails on the
// byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.value;
  return v;
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bool_eq(a: Bool, b: Bool) -> Bool {
  if a {
    if b {
      return true;
    }
    return false;
  }
  if b {
    return false;
  }
  return true;
}

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
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

fn slice_bytes(data: &Vec[UInt8], from: Int, to: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = from;
  while i < to {
    let b: UInt8 = data[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn int_at(v: &Vec[Int], i: Int) -> Int {
  let x: Int = v[i];
  return x;
}

fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn bool_is(r: Result[Bool, Str], want: Bool) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Bool = r.value;
  return bool_eq(v, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_ints_is(r: Result[Vec[Int], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_hdr_is(r: Result[RtpHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_reports_is(r: Result[RtcpReports, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_sr_is(r: Result[RtcpSr, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_req_is(r: Result[RtspRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_resp_is(r: Result[RtspResponse, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// Small typed Vec builders.
fn vec1(x: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(x);
  return v;
}

fn vec2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn vec3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn vec4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn bytes1(b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(b as UInt8);
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

fn bytes_1_to_12() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 1;
  while i <= 12 {
    v.push(i as UInt8);
    i = i + 1;
  }
  return v;
}

fn vec1s(x: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(x);
  return v;
}

fn vec2s(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn empty_bytes() -> Vec[UInt8] {
  return Vec[UInt8].new();
}

fn empty_ints() -> Vec[Int] {
  return Vec[Int].new();
}

fn empty_strs() -> Vec[Str] {
  return Vec[Str].new();
}

// RTP header fixture builder (every call site spells out exactly the fields
// it exercises; payload_offset mirrors header_bytes).
fn mk_hdr(version: Int, padding: Bool, extension: Bool, csrc_count: Int, marker: Bool, payload_type: Int, sequence: Int, timestamp: Int, ssrc: Int, csrcs: Vec[Int], extension_profile: Int, extension_words: Int, extension_data: Vec[UInt8], header_bytes: Int) -> RtpHeader {
  return RtpHeader{
    version: version;
    padding: padding;
    extension: extension;
    csrc_count: csrc_count;
    marker: marker;
    payload_type: payload_type;
    sequence: sequence;
    timestamp: timestamp;
    ssrc: ssrc;
    csrcs: csrcs;
    extension_profile: extension_profile;
    extension_words: extension_words;
    extension_data: extension_data;
    header_bytes: header_bytes;
    payload_offset: header_bytes;
  };
}

// RTCP reports fixture builder (parallel Vecs, one element per block).
fn mk_reports(receiver_ssrc: Int, ssrcs: Vec[Int], fraction_lost: Vec[Int], cumulative_lost: Vec[Int], highest_seq: Vec[Int], jitter: Vec[Int], lsr: Vec[Int], dlsr: Vec[Int]) -> RtcpReports {
  return RtcpReports{
    receiver_ssrc: receiver_ssrc;
    ssrcs: ssrcs;
    fraction_lost: fraction_lost;
    cumulative_lost: cumulative_lost;
    highest_seq: highest_seq;
    jitter: jitter;
    lsr: lsr;
    dlsr: dlsr;
  };
}

fn mk_sr(sender_ssrc: Int, ntp_msw: Int, ntp_lsw: Int, rtp_timestamp: Int, packet_count: Int, octet_count: Int, reports: RtcpReports) -> RtcpSr {
  return RtcpSr{
    sender_ssrc: sender_ssrc;
    ntp_msw: ntp_msw;
    ntp_lsw: ntp_lsw;
    rtp_timestamp: rtp_timestamp;
    packet_count: packet_count;
    octet_count: octet_count;
    reports: reports;
  };
}

fn mk_req(method: Str, uri: Str, version: Str, names: Vec[Str], values: Vec[Str], body: Str) -> RtspRequest {
  return RtspRequest{ method: method; uri: uri; version: version; names: names; values: values; body: body; };
}

fn mk_resp(version: Str, status: Int, reason: Str, names: Vec[Str], values: Vec[Str], body: Str) -> RtspResponse {
  return RtspResponse{ version: version; status: status; reason: reason; names: names; values: values; body: body; };
}

// --------------------------------------------------
//  RTP tests
// --------------------------------------------------

fn t1() -> TestResult {
  // V=2, P=0, X=0, CC=0, M=1, PT=96, seq=0x7724, ts=1000000,
  // SSRC=0xDEADBEEF, payload AA BB.
  let data = hb("80E07724000F4240DEADBEEFAABB");
  let r = rtp_parse_header(&data);
  if !r.is_ok {
    return assert(false, "rtp: parse pinned basic header");
  }
  let h: RtpHeader = r.value;
  var ok = h.version == 2;
  if !bool_eq(h.padding, false) { ok = false; }
  if !bool_eq(h.extension, false) { ok = false; }
  if h.csrc_count != 0 { ok = false; }
  if !bool_eq(h.marker, true) { ok = false; }
  if h.payload_type != 96 { ok = false; }
  if h.sequence != 30500 { ok = false; }
  if h.timestamp != 1000000 { ok = false; }
  if h.ssrc != 3735928559 { ok = false; }
  if rtp_csrc_len(&h) != 0 { ok = false; }
  if rtp_header_bytes(&h) != 12 { ok = false; }
  if rtp_extension_bytes(&h) != 0 { ok = false; }
  if rtp_payload_len(&data, &h) != 2 { ok = false; }
  if rtp_csrc(&h, 0) != -1 { ok = false; }
  return assert(ok, "rtp: parse pinned basic header, trailing payload ignored");
}

fn t2() -> TestResult {
  // V=2, P=0, X=1, CC=2, M=0, PT=97, seq=0, ts=0xFFFFFFFF, SSRC=0x01020304,
  // CSRCs 0x11121314 0x21222324, extension profile 0xBEDE, 3 words
  // (01..0C), payload DE AD.
  let data = hb("92610000FFFFFFFF010203041112131421222324BEDE00030102030405060708090A0B0CDEAD");
  let r = rtp_parse_header(&data);
  if !r.is_ok {
    return assert(false, "rtp: parse CSRC + extension frame");
  }
  let h: RtpHeader = r.value;
  var ok = h.version == 2;
  if !bool_eq(h.padding, false) { ok = false; }
  if !bool_eq(h.extension, true) { ok = false; }
  if h.csrc_count != 2 { ok = false; }
  if !bool_eq(h.marker, false) { ok = false; }
  if h.payload_type != 97 { ok = false; }
  if h.sequence != 0 { ok = false; }
  if h.timestamp != 4294967295 { ok = false; }
  if h.ssrc != 16909060 { ok = false; }
  if rtp_csrc_len(&h) != 2 { ok = false; }
  if rtp_csrc(&h, 0) != 286397204 { ok = false; }
  if rtp_csrc(&h, 1) != 555885348 { ok = false; }
  if rtp_csrc(&h, 2) != -1 { ok = false; }
  if rtp_csrc(&h, -1) != -1 { ok = false; }
  if h.extension_profile != 48862 { ok = false; }
  if h.extension_words != 3 { ok = false; }
  if rtp_extension_bytes(&h) != 12 { ok = false; }
  if rtp_header_bytes(&h) != 36 { ok = false; }
  if rtp_payload_len(&data, &h) != 2 { ok = false; }
  let e0: Int = (h.extension_data[0] as Int) & 0xFF;
  let e11: Int = (h.extension_data[11] as Int) & 0xFF;
  if e0 != 1 { ok = false; }
  if e11 != 12 { ok = false; }
  return assert(ok, "rtp: parse CSRC list and header extension, declared length honoured");
}

fn t3() -> TestResult {
  // Round trips: parsed -> built is byte-identical to the header prefix, and
  // a hand-built header produces the same bytes.
  let data = hb("92610000FFFFFFFF010203041112131421222324BEDE00030102030405060708090A0B0CDEAD");
  let r = rtp_parse_header(&data);
  if !r.is_ok {
    return assert(false, "rtp: round-trip parse");
  }
  let h: RtpHeader = r.value;
  let b = rtp_build_header(&h);
  if !b.is_ok {
    return assert(false, "rtp: round-trip build");
  }
  let bb: Vec[UInt8] = b.value;
  var ok = bytes_equal(&bb, &slice_bytes(&data, 0, 36));
  let h2 = mk_hdr(2, false, true, 2, false, 97, 0, 4294967295, 16909060, vec2(286397204, 555885348), 48862, 3, bytes_1_to_12(), 36);
  let b2 = rtp_build_header(&h2);
  if !b2.is_ok {
    ok = false;
  } else {
    let b2v: Vec[UInt8] = b2.value;
    if !bytes_equal(&b2v, &bb) { ok = false; }
  }
  // Basic header build: first 12 bytes of the t1 fixture.
  let h3 = mk_hdr(2, false, false, 0, true, 96, 30500, 1000000, 3735928559, empty_ints(), 0, 0, empty_bytes(), 12);
  let b3 = rtp_build_header(&h3);
  if !b3.is_ok {
    ok = false;
  } else {
    let b3v: Vec[UInt8] = b3.value;
    if !bytes_equal(&b3v, &hb("80E07724000F4240DEADBEEF")) { ok = false; }
  }
  // Determinism: repeated encodes agree byte for byte.
  let b4 = rtp_build_header(&h);
  if !b4.is_ok {
    ok = false;
  } else {
    let b4v: Vec[UInt8] = b4.value;
    if !bytes_equal(&b4v, &bb) { ok = false; }
  }
  return assert(ok, "rtp: build header matches pinned bytes (CSRC + extension + basic)");
}

fn t4() -> TestResult {
  // P=1, PT=96, seq=1, ts=90, SSRC=0xCAFEBABE, payload 41 42 43 03:
  // 4 payload bytes of which the last 3 are padding.
  let data = hb("A06000010000005ACAFEBABE41424303");
  let r = rtp_parse_header(&data);
  if !r.is_ok {
    return assert(false, "rtp: padding frame parses");
  }
  let h: RtpHeader = r.value;
  var ok = bool_eq(h.padding, true);
  if h.payload_type != 96 { ok = false; }
  if rtp_payload_len(&data, &h) != 4 { ok = false; }
  if !int_is(rtp_padding_len(&data, &h), 3) { ok = false; }
  // No padding bit -> 0, no error.
  let r0 = rtp_parse_header(&hb("80E07724000F4240DEADBEEFAABB"));
  if !r0.is_ok {
    ok = false;
  } else {
    let h0: RtpHeader = r0.value;
    if !int_is(rtp_padding_len(&hb("80E07724000F4240DEADBEEFAABB"), &h0), 0) { ok = false; }
  }
  // P set, no payload at all.
  let d1 = hb("A06000010000005ACAFEBABE");
  let r1 = rtp_parse_header(&d1);
  if !r1.is_ok {
    ok = false;
  } else {
    let h1: RtpHeader = r1.value;
    if !err_int_is(rtp_padding_len(&d1, &h1), "rtp: padding set but packet has no payload") { ok = false; }
  }
  // P set, pad count 0.
  let d2 = hb("A06000010000005ACAFEBABE00");
  let r2 = rtp_parse_header(&d2);
  if !r2.is_ok {
    ok = false;
  } else {
    let h2: RtpHeader = r2.value;
    if !err_int_is(rtp_padding_len(&d2, &h2), "rtp: padding length 0 out of range 1..1") { ok = false; }
  }
  // P set, pad count larger than the payload.
  let d3 = hb("A06000010000005ACAFEBABE4105");
  let r3 = rtp_parse_header(&d3);
  if !r3.is_ok {
    ok = false;
  } else {
    let h3: RtpHeader = r3.value;
    if !err_int_is(rtp_padding_len(&d3, &h3), "rtp: padding length 5 exceeds payload 2") { ok = false; }
  }
  return assert(ok, "rtp: padding bit and trailer length checks");
}

fn t5() -> TestResult {
  var ok = true;
  // 11 bytes: one short of the fixed header.
  if !err_hdr_is(rtp_parse_header(&hb("80E07724000F4240DEADBE")), "rtp: header needs 12 bytes, have 11") { ok = false; }
  // Version 1.
  if !err_hdr_is(rtp_parse_header(&hb("40E07724000F4240DEADBEEF")), "rtp: version 1 is not 2") { ok = false; }
  // CC=2 declares 8 CSRC bytes but only 12 bytes exist.
  if !err_hdr_is(rtp_parse_header(&hb("826000010000000100000001")), "rtp: header needs 20 bytes, have 12") { ok = false; }
  // X=1 but the profile/length preamble is cut short.
  if !err_hdr_is(rtp_parse_header(&hb("906000010000000100000001BEDE")), "rtp: header needs 16 bytes, have 14") { ok = false; }
  // X=1 declares 10 words but no extension bytes follow.
  if !err_hdr_is(rtp_parse_header(&hb("906000010000000100000001BEDE000A")), "rtp: extension declares 10 words, have 0 bytes") { ok = false; }
  // X=1 declares 2 words but only 4 bytes follow.
  if !err_hdr_is(rtp_parse_header(&hb("906000010000000100000001BEDE000201020304")), "rtp: extension declares 2 words, have 4 bytes") { ok = false; }
  return assert(ok, "rtp: parse error catalog (short, version, CSRC, extension overrun)");
}

fn t6() -> TestResult {
  var ok = true;
  let h_v1 = mk_hdr(1, false, false, 0, false, 96, 0, 0, 0, empty_ints(), 0, 0, empty_bytes(), 12);
  if !err_bytes_is(rtp_build_header(&h_v1), "rtp: version 1 is not 2") { ok = false; }
  let h_cc16 = mk_hdr(2, false, false, 16, false, 96, 0, 0, 0, empty_ints(), 0, 0, empty_bytes(), 12);
  if !err_bytes_is(rtp_build_header(&h_cc16), "rtp: csrc count 16 out of range 0..15") { ok = false; }
  let h_cc2 = mk_hdr(2, false, false, 2, false, 96, 0, 0, 0, vec1(7), 0, 0, empty_bytes(), 12);
  if !err_bytes_is(rtp_build_header(&h_cc2), "rtp: csrc count 2 does not match 1 identifiers") { ok = false; }
  let h_cs = mk_hdr(2, false, false, 1, false, 96, 0, 0, 0, vec1(-1), 0, 0, empty_bytes(), 16);
  if !err_bytes_is(rtp_build_header(&h_cs), "rtp: csrc -1 out of range 0..4294967295") { ok = false; }
  let h_pt = mk_hdr(2, false, false, 0, false, 128, 0, 0, 0, empty_ints(), 0, 0, empty_bytes(), 12);
  if !err_bytes_is(rtp_build_header(&h_pt), "rtp: payload type 128 out of range 0..127") { ok = false; }
  let h_seq = mk_hdr(2, false, false, 0, false, 96, 65536, 0, 0, empty_ints(), 0, 0, empty_bytes(), 12);
  if !err_bytes_is(rtp_build_header(&h_seq), "rtp: sequence 65536 out of range 0..65535") { ok = false; }
  let h_ts = mk_hdr(2, false, false, 0, false, 96, 0, -1, 0, empty_ints(), 0, 0, empty_bytes(), 12);
  if !err_bytes_is(rtp_build_header(&h_ts), "rtp: timestamp -1 out of range 0..4294967295") { ok = false; }
  let h_ssrc = mk_hdr(2, false, false, 0, false, 96, 0, 0, 4294967296, empty_ints(), 0, 0, empty_bytes(), 12);
  if !err_bytes_is(rtp_build_header(&h_ssrc), "rtp: ssrc 4294967296 out of range 0..4294967295") { ok = false; }
  let h_ew = mk_hdr(2, false, true, 0, false, 96, 0, 0, 0, empty_ints(), 0, 65536, empty_bytes(), 12);
  if !err_bytes_is(rtp_build_header(&h_ew), "rtp: extension words 65536 out of range 0..65535") { ok = false; }
  let h_ed = mk_hdr(2, false, true, 0, false, 96, 0, 0, 0, empty_ints(), 0, 2, bytes4(9, 8, 7, 6), 12);
  if !err_bytes_is(rtp_build_header(&h_ed), "rtp: extension declares 2 words but data is 4 bytes") { ok = false; }
  let h_ep = mk_hdr(2, false, true, 0, false, 96, 0, 0, 0, empty_ints(), 65536, 3, bytes_1_to_12(), 12);
  if !err_bytes_is(rtp_build_header(&h_ep), "rtp: extension profile 65536 out of range 0..65535") { ok = false; }
  let h_xw = mk_hdr(2, false, false, 0, false, 96, 0, 0, 0, empty_ints(), 0, 1, empty_bytes(), 12);
  if !err_bytes_is(rtp_build_header(&h_xw), "rtp: extension flag clear but extension words is 1") { ok = false; }
  let h_xd = mk_hdr(2, false, false, 0, false, 96, 0, 0, 0, empty_ints(), 0, 0, bytes1(9), 12);
  if !err_bytes_is(rtp_build_header(&h_xd), "rtp: extension flag clear but extension data is 1 bytes") { ok = false; }
  return assert(ok, "rtp: build error catalog (ranges, mismatches, extension consistency)");
}

fn t7() -> TestResult {
  var ok = rtp_seq_before(65534, 1);
  if !rtp_seq_before(65534, 1) { ok = false; }
  if rtp_seq_diff(65534, 1) != 3 { ok = false; }
  if rtp_seq_before(1, 65534) { ok = false; }
  if rtp_seq_diff(1, 65534) != -3 { ok = false; }
  if !rtp_seq_before(10, 20) { ok = false; }
  if rtp_seq_diff(10, 20) != 10 { ok = false; }
  if rtp_seq_before(20, 10) { ok = false; }
  if rtp_seq_diff(20, 10) != -10 { ok = false; }
  if !rtp_seq_before(0, 32767) { ok = false; }
  if rtp_seq_before(0, 32768) { ok = false; }
  if rtp_seq_before(32768, 0) { ok = false; }
  if rtp_seq_diff(0, 32768) != -32768 { ok = false; }
  if rtp_seq_diff(32768, 0) != -32768 { ok = false; }
  if rtp_seq_before(5, 5) { ok = false; }
  if rtp_seq_diff(5, 5) != 0 { ok = false; }
  if rtp_seq_next(65535) != 0 { ok = false; }
  if rtp_seq_next(0) != 1 { ok = false; }
  if rtp_seq_next(100) != 101 { ok = false; }
  return assert(ok, "rtp: 16-bit sequence wrap table (before/diff/next)");
}

fn t8() -> TestResult {
  var ok = rtp_ts_before(4294967290, 4);
  if !rtp_ts_before(4294967290, 4) { ok = false; }
  if rtp_ts_diff(4294967290, 4) != 10 { ok = false; }
  if rtp_ts_diff(4, 4294967290) != -10 { ok = false; }
  if rtp_ts_before(4, 4294967290) { ok = false; }
  if rtp_ts_add(4294967290, 10) != 4 { ok = false; }
  if rtp_ts_sub(4, 10) != 4294967290 { ok = false; }
  if rtp_ts_add(0, -1) != 4294967295 { ok = false; }
  if rtp_ts_sub(0, 1) != 4294967295 { ok = false; }
  if !rtp_ts_before(0, 2147483647) { ok = false; }
  if rtp_ts_before(0, 2147483648) { ok = false; }
  if rtp_ts_before(2147483648, 0) { ok = false; }
  if rtp_ts_diff(0, 2147483648) != -2147483648 { ok = false; }
  if rtp_ts_diff(0, 4294967295) != -1 { ok = false; }
  if !rtp_ts_before(4294967295, 0) { ok = false; }
  if rtp_ts_before(7, 7) { ok = false; }
  if rtp_ts_diff(7, 7) != 0 { ok = false; }
  return assert(ok, "rtp: 32-bit timestamp wrap table (before/diff/add/sub)");
}

fn t9() -> TestResult {
  // Arrival jumps +1600 ticks once, then the series returns to the clock.
  // RFC 3550 A.8 with truncating division: 100, 193, 181.
  var st = rtp_jitter_init();
  var ok = rtp_jitter_value(&st) == 0;
  st = rtp_jitter_update(&st, 0, 0);
  if rtp_jitter_value(&st) != 0 { ok = false; }
  st = rtp_jitter_update(&st, 4600, 3000);
  if rtp_jitter_value(&st) != 100 { ok = false; }
  st = rtp_jitter_update(&st, 6000, 6000);
  if rtp_jitter_value(&st) != 193 { ok = false; }
  st = rtp_jitter_update(&st, 9000, 9000);
  if rtp_jitter_value(&st) != 181 { ok = false; }
  // A perfect series keeps the estimate at zero.
  var st2 = rtp_jitter_init();
  st2 = rtp_jitter_update(&st2, 0, 0);
  st2 = rtp_jitter_update(&st2, 3000, 3000);
  st2 = rtp_jitter_update(&st2, 6000, 6000);
  if rtp_jitter_value(&st2) != 0 { ok = false; }
  // Wrap-safe arrivals: 0xFFFFFFF0 then 0x00000030 is a +64 advance.
  var st3 = rtp_jitter_init();
  st3 = rtp_jitter_update(&st3, 4294967280, 4294967280);
  st3 = rtp_jitter_update(&st3, 48, 4294967280);
  if rtp_jitter_value(&st3) != 4 { ok = false; }
  // Tick -> millisecond conversion at the 90 kHz video clock.
  if !int_is(rtp_jitter_to_ms(181, 90000), 2) { ok = false; }
  if !int_is(rtp_jitter_to_ms(0, 90000), 0) { ok = false; }
  if !err_int_is(rtp_jitter_to_ms(10, 0), "rtp: clock rate 0 out of range 1..1000000000") { ok = false; }
  return assert(ok, "rtp: jitter EWMA pinned series, wrap-safe deltas, ms conversion");
}

fn t10() -> TestResult {
  let arrivals = vec4(0, 4600, 6000, 9000);
  let sends = vec4(0, 3000, 6000, 9000);
  let dr = rtp_jitter_deltas(&arrivals, &sends);
  if !dr.is_ok {
    return assert(false, "rtp: jitter deltas build");
  }
  let d: Vec[Int] = dr.value;
  var ok = d.len() == 3;
  if int_at(&d, 0) != 1600 { ok = false; }
  if int_at(&d, 1) != 1600 { ok = false; }
  if int_at(&d, 2) != 0 { ok = false; }
  if !int_is(rtp_jitter_mean(&d, 2), 800) { ok = false; }
  if !int_is(rtp_jitter_mean(&d, 4), 1066) { ok = false; }
  if !int_is(rtp_jitter_mean(&d, 1), 0) { ok = false; }
  if !err_int_is(rtp_jitter_mean(&d, 0), "rtp: jitter window 0 is not positive") { ok = false; }
  // Fewer than two samples: no deltas, mean 0.
  let one = vec1(42);
  let dr1 = rtp_jitter_deltas(&one, &one);
  if !dr1.is_ok { ok = false; } else {
    let d1: Vec[Int] = dr1.value;
    if d1.len() != 0 { ok = false; }
  }
  if !int_is(rtp_jitter_mean(&empty_ints(), 3), 0) { ok = false; }
  // Length mismatch.
  if !err_ints_is(rtp_jitter_deltas(&vec3(1, 2, 3), &vec2(1, 2)), "rtp: arrivals 3 do not match sends 2") { ok = false; }
  return assert(ok, "rtp: jitter delta series and sliding-window mean");
}

// --------------------------------------------------
//  RTCP tests
// --------------------------------------------------

fn t11() -> TestResult {
  // RR: V=2, P=0, count=2, PT=201, length_words=13 (56 bytes), receiver
  // SSRC 0x0A0B0C0D, then the two blocks of t12.
  let data = hb("82C9000D0A0B0C0D010203041900012C00010001000000640000000100000002A1A2A3A400FFFFFB0000000080000000FFFFFFFF7FFFFFFF");
  if data.len() != 56 {
    return assert(false, "rtcp: RR fixture is 56 bytes");
  }
  let r = rtcp_parse_header(&data);
  if !r.is_ok {
    return assert(false, "rtcp: RR header parses");
  }
  let h: RtcpHeader = r.value;
  var ok = h.version == 2;
  if !bool_eq(h.padding, false) { ok = false; }
  if h.count != 2 { ok = false; }
  if h.packet_type != 201 { ok = false; }
  if h.length_words != 13 { ok = false; }
  if h.total_bytes != 56 { ok = false; }
  return assert(ok, "rtcp: parse pinned RR common header (length in words minus one)");
}

fn t12() -> TestResult {
  let data = hb("82C9000D0A0B0C0D010203041900012C00010001000000640000000100000002A1A2A3A400FFFFFB0000000080000000FFFFFFFF7FFFFFFF");
  let r = rtcp_parse_rr(&data);
  if !r.is_ok {
    return assert(false, "rtcp: RR with two blocks parses");
  }
  let rep: RtcpReports = r.value;
  var ok = rtcp_block_count(&rep) == 2;
  if rep.receiver_ssrc != 168496141 { ok = false; }
  // Block 0: positive cumulative loss 300, fraction 25, highest 65537.
  if rtcp_block_ssrc(&rep, 0) != 16909060 { ok = false; }
  if rtcp_block_fraction_lost(&rep, 0) != 25 { ok = false; }
  if rtcp_block_cumulative_lost(&rep, 0) != 300 { ok = false; }
  if rtcp_block_highest_seq(&rep, 0) != 65537 { ok = false; }
  if rtcp_block_jitter(&rep, 0) != 100 { ok = false; }
  if rtcp_block_lsr(&rep, 0) != 1 { ok = false; }
  if rtcp_block_dlsr(&rep, 0) != 2 { ok = false; }
  // Block 1: negative 24-bit cumulative loss, max-bit jitter, max LSR.
  if rtcp_block_ssrc(&rep, 1) != 2711790500 { ok = false; }
  if rtcp_block_fraction_lost(&rep, 1) != 0 { ok = false; }
  if rtcp_block_cumulative_lost(&rep, 1) != -5 { ok = false; }
  if rtcp_block_highest_seq(&rep, 1) != 0 { ok = false; }
  if rtcp_block_jitter(&rep, 1) != 2147483648 { ok = false; }
  if rtcp_block_lsr(&rep, 1) != 4294967295 { ok = false; }
  if rtcp_block_dlsr(&rep, 1) != 2147483647 { ok = false; }
  // Out-of-range accessors.
  if rtcp_block_ssrc(&rep, -1) != -1 { ok = false; }
  if rtcp_block_fraction_lost(&rep, 2) != -1 { ok = false; }
  if rtcp_block_cumulative_lost(&rep, 2) != 0 { ok = false; }
  if rtcp_block_lsr(&rep, 5) != -1 { ok = false; }
  return assert(ok, "rtcp: report-block iteration (fraction, cumulative loss, seq, jitter)");
}

fn t13() -> TestResult {
  let fixture = hb("82C9000D0A0B0C0D010203041900012C00010001000000640000000100000002A1A2A3A400FFFFFB0000000080000000FFFFFFFF7FFFFFFF");
  let rep = mk_reports(168496141, vec2(16909060, 2711790500), vec2(25, 0), vec2(300, -5), vec2(65537, 0), vec2(100, 2147483648), vec2(1, 4294967295), vec2(2, 2147483647));
  let b = rtcp_build_rr(&rep);
  if !b.is_ok {
    return assert(false, "rtcp: build RR");
  }
  let bb: Vec[UInt8] = b.value;
  var ok = bytes_equal(&bb, &fixture);
  // Determinism and parse round trip.
  let b2 = rtcp_build_rr(&rep);
  if !b2.is_ok { ok = false; } else {
    let b2v: Vec[UInt8] = b2.value;
    if !bytes_equal(&b2v, &bb) { ok = false; }
  }
  let p = rtcp_parse_rr(&bb);
  if !p.is_ok { ok = false; } else {
    let rep2: RtcpReports = p.value;
    if rtcp_block_count(&rep2) != 2 { ok = false; }
    if rtcp_block_cumulative_lost(&rep2, 1) != -5 { ok = false; }
    if rtcp_block_ssrc(&rep2, 0) != 16909060 { ok = false; }
  }
  return assert(ok, "rtcp: RR build matches pinned bytes, negative cumulative loss round trip");
}

fn t14() -> TestResult {
  // SR: V=2, count=1, PT=200, length_words=12 (52 bytes), sender SSRC 1,
  // NTP msw 0xE0000000, NTP lsw 1, RTP ts 60000, 100 packets, 12800 octets,
  // one block (SSRC 2, fraction 64, cumulative 100, highest 5, jitter 10,
  // LSR 3, DLSR 4).
  let data = hb("81C8000C00000001E0000000000000010000EA6000000064000032000000000240000064000000050000000A0000000300000004");
  if data.len() != 52 {
    return assert(false, "rtcp: SR fixture is 52 bytes");
  }
  let r = rtcp_parse_sr(&data);
  if !r.is_ok {
    return assert(false, "rtcp: SR with one block parses");
  }
  let sr: RtcpSr = r.value;
  var ok = sr.sender_ssrc == 1;
  if sr.ntp_msw != 3758096384 { ok = false; }
  if sr.ntp_lsw != 1 { ok = false; }
  if sr.rtp_timestamp != 60000 { ok = false; }
  if sr.packet_count != 100 { ok = false; }
  if sr.octet_count != 12800 { ok = false; }
  let rep: RtcpReports = sr.reports;
  if rtcp_block_count(&rep) != 1 { ok = false; }
  if rtcp_block_ssrc(&rep, 0) != 2 { ok = false; }
  if rtcp_block_fraction_lost(&rep, 0) != 64 { ok = false; }
  if rtcp_block_cumulative_lost(&rep, 0) != 100 { ok = false; }
  if rtcp_block_highest_seq(&rep, 0) != 5 { ok = false; }
  if rtcp_block_jitter(&rep, 0) != 10 { ok = false; }
  if rtcp_block_lsr(&rep, 0) != 3 { ok = false; }
  if rtcp_block_dlsr(&rep, 0) != 4 { ok = false; }
  return assert(ok, "rtcp: parse pinned SR sender info and report block");
}

fn t15() -> TestResult {
  let fixture = hb("81C8000C00000001E0000000000000010000EA6000000064000032000000000240000064000000050000000A0000000300000004");
  let rep = mk_reports(1, vec1(2), vec1(64), vec1(100), vec1(5), vec1(10), vec1(3), vec1(4));
  let sr = mk_sr(1, 3758096384, 1, 60000, 100, 12800, rep);
  let b = rtcp_build_sr(&sr);
  if !b.is_ok {
    return assert(false, "rtcp: build SR");
  }
  let bb: Vec[UInt8] = b.value;
  var ok = bytes_equal(&bb, &fixture);
  let p = rtcp_parse_sr(&bb);
  if !p.is_ok { ok = false; } else {
    let sr2: RtcpSr = p.value;
    if sr2.ntp_msw != 3758096384 { ok = false; }
    if sr2.packet_count != 100 { ok = false; }
    let rep2: RtcpReports = sr2.reports;
    if rtcp_block_count(&rep2) != 1 { ok = false; }
    if rtcp_block_cumulative_lost(&rep2, 0) != 100 { ok = false; }
  }
  return assert(ok, "rtcp: SR build matches pinned bytes and parses back");
}

fn t16() -> TestResult {
  var ok = true;
  // Header-level errors.
  if !err_reports_is(rtcp_parse_rr(&hb("82C9")), "rtcp: packet needs 4 bytes, have 2") { ok = false; }
  if !err_reports_is(rtcp_parse_rr(&hb("00C9000D")), "rtcp: version 0 is not 2") { ok = false; }
  if !err_reports_is(rtcp_parse_rr(&hb("82C80001")), "rtcp: packet type 200 is not 201") { ok = false; }
  if !err_reports_is(rtcp_parse_rr(&hb("82C90000")), "rtcp: packet needs 8 bytes, have 4") { ok = false; }
  if !err_reports_is(rtcp_parse_rr(&hb("82C9000D0A0B0C0D")), "rtcp: packet length says 56 bytes, have 8") { ok = false; }
  // Count field (3) does not fit the declared 56-byte packet.
  if !err_reports_is(rtcp_parse_rr(&hb("83C9000D0A0B0C0D010203041900012C00010001000000640000000100000002A1A2A3A400FFFFFB0000000080000000FFFFFFFF7FFFFFFF")), "rtcp: 3 report blocks need 80 bytes, packet has 56") { ok = false; }
  // SR-level errors.
  if !err_sr_is(rtcp_parse_sr(&hb("81C90001")), "rtcp: packet type 201 is not 200") { ok = false; }
  if !err_sr_is(rtcp_parse_sr(&hb("81C8000C00000001")), "rtcp: packet needs 28 bytes, have 8") { ok = false; }
  // Build errors: receiver ssrc, block count, field-count mismatch.
  let bad_ssrc = mk_reports(4294967296, empty_ints(), empty_ints(), empty_ints(), empty_ints(), empty_ints(), empty_ints(), empty_ints());
  if !err_bytes_is(rtcp_build_rr(&bad_ssrc), "rtcp: receiver ssrc 4294967296 out of range 0..4294967295") { ok = false; }
  var s32 = Vec[Int].new();
  var f32 = Vec[Int].new();
  var c32 = Vec[Int].new();
  var h32 = Vec[Int].new();
  var j32 = Vec[Int].new();
  var l32 = Vec[Int].new();
  var d32 = Vec[Int].new();
  var i = 0;
  while i < 32 {
    s32.push(0);
    f32.push(0);
    c32.push(0);
    h32.push(0);
    j32.push(0);
    l32.push(0);
    d32.push(0);
    i = i + 1;
  }
  let r32 = mk_reports(0, s32, f32, c32, h32, j32, l32, d32);
  if !err_bytes_is(rtcp_build_rr(&r32), "rtcp: block count 32 out of range 0..31") { ok = false; }
  let short_rep = mk_reports(0, vec2(1, 2), vec1(0), vec1(0), vec1(0), vec1(0), vec1(0), vec1(0));
  if !err_bytes_is(rtcp_build_rr(&short_rep), "rtcp: block field count 1 does not match 2") { ok = false; }
  // Build errors: block field ranges.
  let bad_f = mk_reports(0, vec1(1), vec1(256), vec1(0), vec1(0), vec1(0), vec1(0), vec1(0));
  if !err_bytes_is(rtcp_build_rr(&bad_f), "rtcp: fraction lost 256 out of range 0..255") { ok = false; }
  let bad_c = mk_reports(0, vec1(1), vec1(0), vec1(8388608), vec1(0), vec1(0), vec1(0), vec1(0));
  if !err_bytes_is(rtcp_build_rr(&bad_c), "rtcp: cumulative lost 8388608 out of range -8388608..8388607") { ok = false; }
  // SR sender-field errors.
  let good_rep = mk_reports(0, empty_ints(), empty_ints(), empty_ints(), empty_ints(), empty_ints(), empty_ints(), empty_ints());
  let bad_sr_ssrc = mk_sr(4294967296, 0, 0, 0, 0, 0, good_rep);
  if !err_bytes_is(rtcp_build_sr(&bad_sr_ssrc), "rtcp: sender ssrc 4294967296 out of range 0..4294967295") { ok = false; }
  let bad_sr_msw = mk_sr(0, 4294967296, 0, 0, 0, 0, good_rep);
  if !err_bytes_is(rtcp_build_sr(&bad_sr_msw), "rtcp: ntp msw 4294967296 out of range 0..4294967295") { ok = false; }
  return assert(ok, "rtcp: parse and build error catalog (bounds, PT, counts, ranges)");
}

// --------------------------------------------------
//  RTSP tests
// --------------------------------------------------

fn t17() -> TestResult {
  let text = "DESCRIBE rtsp://camera.example/stream RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\nContent-Length: 4\r\n\r\nbody";
  let r = rtsp_parse_request(text);
  if !r.is_ok {
    return assert(false, "rtsp: pinned request parses");
  }
  let req: RtspRequest = r.value;
  var ok = streq(req.method, "DESCRIBE");
  if !streq(req.uri, "rtsp://camera.example/stream") { ok = false; }
  if !streq(req.version, "RTSP/1.0") { ok = false; }
  if rtsp_request_header_count(&req) != 3 { ok = false; }
  if !streq(rtsp_request_header_name(&req, 0), "CSeq") { ok = false; }
  if !streq(rtsp_request_header_value(&req, 0), "2") { ok = false; }
  if !streq(rtsp_request_header_name(&req, 1), "Accept") { ok = false; }
  if !streq(rtsp_request_header_value(&req, 1), "application/sdp") { ok = false; }
  if !streq(rtsp_request_header_get(&req, "accept"), "application/sdp") { ok = false; }
  if !streq(rtsp_request_header_get(&req, "ACCEPT"), "application/sdp") { ok = false; }
  if !streq(rtsp_request_header_get(&req, "x-missing"), "") { ok = false; }
  if !streq(rtsp_request_header_name(&req, -1), "") { ok = false; }
  if !streq(rtsp_request_header_value(&req, 9), "") { ok = false; }
  if !streq(req.body, "body") { ok = false; }
  // LF-only line endings parse to the same message.
  let lf = "OPTIONS * RTSP/1.0\nCSeq: 1\n\n";
  let r2 = rtsp_parse_request(lf);
  if !r2.is_ok { ok = false; } else {
    let req2: RtspRequest = r2.value;
    if !streq(req2.method, "OPTIONS") { ok = false; }
    if !streq(req2.uri, "*") { ok = false; }
    if rtsp_request_header_count(&req2) != 1 { ok = false; }
    if !streq(rtsp_request_header_get(&req2, "cseq"), "1") { ok = false; }
    if !streq(req2.body, "") { ok = false; }
  }
  return assert(ok, "rtsp: parse pinned request (headers, body, case-insensitive lookup, LF)");
}

fn t18() -> TestResult {
  let text = "DESCRIBE rtsp://camera.example/stream RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\nContent-Length: 4\r\n\r\nbody";
  let r = rtsp_parse_request(text);
  if !r.is_ok {
    return assert(false, "rtsp: request build round trip");
  }
  let req: RtspRequest = r.value;
  let b = rtsp_build_request(&req);
  if !b.is_ok {
    return assert(false, "rtsp: build request");
  }
  let bb: Str = b.value;
  var ok = streq(bb, text);
  // Re-parse the canonical text: same fields again.
  let r2 = rtsp_parse_request(bb);
  if !r2.is_ok { ok = false; } else {
    let req2: RtspRequest = r2.value;
    if !streq(req2.method, "DESCRIBE") { ok = false; }
    if rtsp_request_header_count(&req2) != 3 { ok = false; }
    if !streq(req2.body, "body") { ok = false; }
  }
  // Hand-built canonical request with empty header list and no body.
  let req3 = mk_req("OPTIONS", "*", "RTSP/1.0", empty_strs(), empty_strs(), "");
  let b3 = rtsp_build_request(&req3);
  if !b3.is_ok { ok = false; } else {
    let b3v: Str = b3.value;
    if !streq(b3v, "OPTIONS * RTSP/1.0\r\n\r\n") { ok = false; }
  }
  return assert(ok, "rtsp: build request canonical CRLF text and parse round trip");
}

fn t19() -> TestResult {
  let text = "RTSP/1.0 200 OK\r\nCSeq: 1\r\nServer: xiom.streaming/0.1.0\r\nContent-Length: 5\r\n\r\nhello";
  let r = rtsp_parse_response(text);
  if !r.is_ok {
    return assert(false, "rtsp: pinned response parses");
  }
  let resp: RtspResponse = r.value;
  var ok = streq(resp.version, "RTSP/1.0");
  if resp.status != 200 { ok = false; }
  if !streq(resp.reason, "OK") { ok = false; }
  if rtsp_response_header_count(&resp) != 3 { ok = false; }
  if !streq(rtsp_response_header_get(&resp, "cseq"), "1") { ok = false; }
  if !streq(rtsp_response_header_value(&resp, 1), "xiom.streaming/0.1.0") { ok = false; }
  if !streq(resp.body, "hello") { ok = false; }
  let b = rtsp_build_response(&resp);
  if !b.is_ok { ok = false; } else {
    let bv: Str = b.value;
    if !streq(bv, text) { ok = false; }
  }
  // Empty reason phrase round-trips without a trailing space.
  let text2 = "RTSP/1.0 200\r\n\r\n";
  let r2 = rtsp_parse_response(text2);
  if !r2.is_ok { ok = false; } else {
    let resp2: RtspResponse = r2.value;
    if !streq(resp2.reason, "") { ok = false; }
    if !streq(resp2.body, "") { ok = false; }
    let b2 = rtsp_build_response(&resp2);
    if !b2.is_ok { ok = false; } else {
      let b2v: Str = b2.value;
      if !streq(b2v, text2) { ok = false; }
    }
  }
  // LF-only status line with a reason phrase.
  let r3 = rtsp_parse_response("RTSP/1.0 404 Not Found\n\n");
  if !r3.is_ok { ok = false; } else {
    let resp3: RtspResponse = r3.value;
    if resp3.status != 404 { ok = false; }
    if !streq(resp3.reason, "Not Found") { ok = false; }
  }
  return assert(ok, "rtsp: parse/build response (status, reason, headers, body)");
}

fn t20() -> TestResult {
  var ok = true;
  if !err_req_is(rtsp_parse_request(""), "rtsp: empty message") { ok = false; }
  if !err_req_is(rtsp_parse_request("\r\n"), "rtsp: empty message") { ok = false; }
  if !err_req_is(rtsp_parse_request("OPTIONS * RTSP/1.0"), "rtsp: missing blank line after headers") { ok = false; }
  if !err_req_is(rtsp_parse_request("OPTIONS *\r\n\r\n"), "rtsp: bad request line") { ok = false; }
  if !err_req_is(rtsp_parse_request("OPTIONS  * RTSP/1.0\r\n\r\n"), "rtsp: bad request line") { ok = false; }
  if !err_req_is(rtsp_parse_request("OPTIONS * HTTP/1.1\r\n\r\n"), "rtsp: bad version HTTP/1.1") { ok = false; }
  if !err_resp_is(rtsp_parse_response("RTSP/1.0 20x OK\r\n\r\n"), "rtsp: bad status code 20x") { ok = false; }
  if !err_resp_is(rtsp_parse_response("RTSP/1.0 099 OK\r\n\r\n"), "rtsp: status code 99 out of range 100..999") { ok = false; }
  if !err_resp_is(rtsp_parse_response("RTSP/1.0 X\r\n\r\n"), "rtsp: bad status code X") { ok = false; }
  if !err_req_is(rtsp_parse_request("OPTIONS * RTSP/1.0\r\nBadHeader\r\n\r\n"), "rtsp: bad header line") { ok = false; }
  if !err_req_is(rtsp_parse_request("OPTIONS * RTSP/1.0\r\nX: a\r\n b\r\n\r\n"), "rtsp: folded header not supported") { ok = false; }
  if !err_req_is(rtsp_parse_request("OPTIONS * RTSP/1.0\r\nBad Name: x\r\n\r\n"), "rtsp: bad header name Bad Name") { ok = false; }
  // Value trimming: leading/trailing SP/TAB around a header value.
  let r = rtsp_parse_request("OPTIONS * RTSP/1.0\r\nX:  padded \t\r\n\r\n");
  if !r.is_ok { ok = false; } else {
    let req: RtspRequest = r.value;
    if !streq(rtsp_request_header_value(&req, 0), "padded") { ok = false; }
  }
  return assert(ok, "rtsp: parse error catalog (lines, versions, status, headers)");
}

fn t21() -> TestResult {
  var ok = true;
  let e1 = mk_req("", "*", "RTSP/1.0", empty_strs(), empty_strs(), "");
  if !err_str_is(rtsp_build_request(&e1), "rtsp: method is empty") { ok = false; }
  let e2 = mk_req("OP TIONS", "*", "RTSP/1.0", empty_strs(), empty_strs(), "");
  if !err_str_is(rtsp_build_request(&e2), "rtsp: method contains space") { ok = false; }
  let e3 = mk_req("OPTIONS", "", "RTSP/1.0", empty_strs(), empty_strs(), "");
  if !err_str_is(rtsp_build_request(&e3), "rtsp: uri is empty") { ok = false; }
  let e4 = mk_req("OPTIONS", "rtsp://a b", "RTSP/1.0", empty_strs(), empty_strs(), "");
  if !err_str_is(rtsp_build_request(&e4), "rtsp: uri contains space") { ok = false; }
  let e5 = mk_req("OPTIONS", "*", "HTTP/1.1", empty_strs(), empty_strs(), "");
  if !err_str_is(rtsp_build_request(&e5), "rtsp: bad version HTTP/1.1") { ok = false; }
  let e6 = mk_req("OPTIONS", "*", "RTSP/1.0", vec1s("CSeq"), empty_strs(), "");
  if !err_str_is(rtsp_build_request(&e6), "rtsp: header count mismatch 1 vs 0") { ok = false; }
  let e7 = mk_req("OPTIONS", "*", "RTSP/1.0", vec1s(""), vec1s("1"), "");
  if !err_str_is(rtsp_build_request(&e7), "rtsp: header name 0 is empty") { ok = false; }
  let e8 = mk_req("OPTIONS", "*", "RTSP/1.0", vec1s("Bad Name"), vec1s("1"), "");
  if !err_str_is(rtsp_build_request(&e8), "rtsp: header name 0 is invalid") { ok = false; }
  let e9 = mk_req("OPTIONS", "*", "RTSP/1.0", vec1s("X"), vec1s("a\rb"), "");
  if !err_str_is(rtsp_build_request(&e9), "rtsp: header value 0 contains CR or LF") { ok = false; }
  let e10 = mk_resp("RTSP/1.0", 99, "OK", empty_strs(), empty_strs(), "");
  if !err_str_is(rtsp_build_response(&e10), "rtsp: status code 99 out of range 100..999") { ok = false; }
  let e11 = mk_resp("RTSP/1.0", 200, "O\rK", empty_strs(), empty_strs(), "");
  if !err_str_is(rtsp_build_response(&e11), "rtsp: reason contains CR or LF") { ok = false; }
  let e12 = mk_resp("HTTP/1.1", 200, "OK", empty_strs(), empty_strs(), "");
  if !err_str_is(rtsp_build_response(&e12), "rtsp: bad version HTTP/1.1") { ok = false; }
  return assert(ok, "rtsp: build error catalog (method, uri, version, headers, status, reason)");
}

// --------------------------------------------------
//  Runner
// --------------------------------------------------

fn report(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.streaming conformance tests ===");
  var failed: Int = 0;
  failed = failed + report(t1());
  failed = failed + report(t2());
  failed = failed + report(t3());
  failed = failed + report(t4());
  failed = failed + report(t5());
  failed = failed + report(t6());
  failed = failed + report(t7());
  failed = failed + report(t8());
  failed = failed + report(t9());
  failed = failed + report(t10());
  failed = failed + report(t11());
  failed = failed + report(t12());
  failed = failed + report(t13());
  failed = failed + report(t14());
  failed = failed + report(t15());
  failed = failed + report(t16());
  failed = failed + report(t17());
  failed = failed + report(t18());
  failed = failed + report(t19());
  failed = failed + report(t20());
  failed = failed + report(t21());
  if failed == 0 {
    io.println("xiom.streaming: all tests passed");
  } else {
    io.println("xiom.streaming: tests failed");
  }
  return failed;
}
