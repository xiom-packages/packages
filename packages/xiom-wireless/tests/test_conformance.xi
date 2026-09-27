// XIOM -- xiom.wireless conformance tests (33 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every fixture is assembled byte by byte in this file, so the parser is
// exercised against bytes the test controls: beacon (SSID, supported rates,
// DS parameter set, RSN with CCMP/PSK), probe response (QoS capability and
// TIM), probe request, open-system and SAE authentication, association and
// reassociation frames, disassociation/deauthentication, ATIM, action,
// QoS data (with and without HT control), 4-address WDS data, RTS/CTS/ACK
// and the other control subtypes, plus the malformed cases: truncation at
// each header stage, malformed information elements (TLV framing and
// impossible semantic lengths), invalid DS bits, reserved subtypes and
// unknown elements that must be preserved raw.
//
// Error strings are compared through compare.str_compare (BUG 17
// discipline: `==` on a Str read from a Vec lowers to a pointer compare).

module wireless_tests
use xiom.io; use xiom.test;
use xiom.wireless;
use xiom.string.compare;
use xiom.string;

// --------------------------------------------------
//  Helpers (independent of src/wireless.xi)
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_frame_is(r: Result[WirelessFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_mgmt_is(r: Result[WirelessMgmt, Str], want: Str) -> Bool {
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

// Widened byte of a byte vector (0..255).
fn bv(v: Vec[UInt8], i: Int) -> Int {
  let b: UInt8 = v[i];
  return (b as Int) & 0xFF;
}

fn str_bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// Decimal text of a non-negative Int (expected error messages build the
// same offsets the library reports).
fn digit_char(d: Int) -> Str {
  if d == 0 { return "0"; }
  if d == 1 { return "1"; }
  if d == 2 { return "2"; }
  if d == 3 { return "3"; }
  if d == 4 { return "4"; }
  if d == 5 { return "5"; }
  if d == 6 { return "6"; }
  if d == 7 { return "7"; }
  if d == 8 { return "8"; }
  if d == 9 { return "9"; }
  return "?";
}

fn ints(n: Int) -> Str {
  if n == 0 {
    return "0";
  }
  var v = n;
  var s = "";
  while v > 0 {
    s = digit_char(v % 10) + s;
    v = v / 10;
  }
  return s;
}

fn vb(a: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  return v;
}

fn vb2(a: Int, b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return v;
}

fn vb3(a: Int, b: Int, c: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  return v;
}

fn vb4(a: Int, b: Int, c: Int, d: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  v.push(d as UInt8);
  return v;
}

fn vb6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  v.push(d as UInt8);
  v.push(e as UInt8);
  v.push(f as UInt8);
  return v;
}

fn pb(v: &mut Vec[UInt8], b: Int) {
  v.push(b as UInt8);
}

fn push_le16(v: &mut Vec[UInt8], n: Int) {
  pb(v, n % 256);
  pb(v, (n / 256) % 256);
}

fn push_le32(v: &mut Vec[UInt8], n: Int) {
  pb(v, n % 256);
  pb(v, (n / 256) % 256);
  pb(v, (n / 65536) % 256);
  pb(v, (n / 16777216) % 256);
}

fn push_le64(v: &mut Vec[UInt8], n: Int) {
  pb(v, n % 256);
  pb(v, (n / 256) % 256);
  pb(v, (n / 65536) % 256);
  pb(v, (n / 16777216) % 256);
  pb(v, (n / 4294967296) % 256);
  pb(v, (n / 1099511627776) % 256);
  pb(v, (n / 281474976710656) % 256);
  pb(v, (n / 72057594037927936) % 256);
}

fn push_mac(v: &mut Vec[UInt8], a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) {
  pb(v, a);
  pb(v, b);
  pb(v, c);
  pb(v, d);
  pb(v, e);
  pb(v, f);
}

// Frame Control: version + type*4 + subtype*16 + flags*256, little-endian.
fn push_fc(v: &mut Vec[UInt8], version: Int, ftype: Int, subtype: Int, flags: Int) {
  push_le16(v, version + ftype * 4 + subtype * 16 + flags * 256);
}

// 24-byte management header: broadcast addr1, addr2 02..07, addr3 10..15,
// sequence control 4657 (fragment 1, sequence 291).
fn push_mgmt_header(v: &mut Vec[UInt8], subtype: Int, flags: Int) {
  push_fc(v, 0, 0, subtype, flags);
  push_le16(v, 0);
  push_mac(v, 255, 255, 255, 255, 255, 255);
  push_mac(v, 2, 3, 4, 5, 6, 7);
  push_mac(v, 16, 17, 18, 19, 20, 21);
  push_le16(v, 4657);
}

// Data header with addr1 01.., addr2 02.., addr3 03.., optional addr4 04..
// and sequence control 16 (fragment 0, sequence 1).
fn push_data_header(v: &mut Vec[UInt8], subtype: Int, flags: Int, wds: Bool) {
  push_fc(v, 0, 2, subtype, flags);
  push_le16(v, 0);
  push_mac(v, 1, 1, 1, 1, 1, 1);
  push_mac(v, 2, 2, 2, 2, 2, 2);
  push_mac(v, 3, 3, 3, 3, 3, 3);
  if wds {
    push_mac(v, 4, 4, 4, 4, 4, 4);
  }
  push_le16(v, 16);
}

// Control header: duration 320, addr1 01.., optional addr2 02.. (no
// sequence control on control frames).
fn push_ctrl_header(v: &mut Vec[UInt8], subtype: Int, flags: Int, two_addrs: Bool) {
  push_fc(v, 0, 1, subtype, flags);
  push_le16(v, 320);
  push_mac(v, 1, 1, 1, 1, 1, 1);
  if two_addrs {
    push_mac(v, 2, 2, 2, 2, 2, 2);
  }
}

fn push_ie_bytes(v: &mut Vec[UInt8], id: Int, payload: Vec[UInt8]) {
  pb(v, id);
  pb(v, payload.len());
  var i = 0;
  while i < payload.len() {
    v.push(payload[i]);
    i = i + 1;
  }
}

fn push_ie_empty(v: &mut Vec[UInt8], id: Int) {
  pb(v, id);
  pb(v, 0);
}

fn push_ie1(v: &mut Vec[UInt8], id: Int, a: Int) {
  pb(v, id);
  pb(v, 1);
  pb(v, a);
}

fn push_ie2(v: &mut Vec[UInt8], id: Int, a: Int, b: Int) {
  pb(v, id);
  pb(v, 2);
  pb(v, a);
  pb(v, b);
}

fn ssid_ie(v: &mut Vec[UInt8], s: Str) {
  push_ie_bytes(v, 0, str_bytes(s));
}

// RSN element: version 1, group CCMP (00:0f:ac type 4), one CCMP pairwise
// suite, one PSK AKM suite (00:0f:ac type 2), capabilities 12. 20 bytes.
fn push_rsn_ccmp_psk(v: &mut Vec[UInt8]) {
  pb(v, 48);
  pb(v, 20);
  push_le16(v, 1);
  pb(v, 0);
  pb(v, 15);
  pb(v, 172);
  pb(v, 4);
  push_le16(v, 1);
  pb(v, 0);
  pb(v, 15);
  pb(v, 172);
  pb(v, 4);
  push_le16(v, 1);
  pb(v, 0);
  pb(v, 15);
  pb(v, 172);
  pb(v, 2);
  push_le16(v, 12);
}

// Beacon body: timestamp 4660, interval 100, capability 1073 (ESS +
// privacy + short preamble + short slot), SSID "TEST", rates 2/4/5.5/11,
// DS channel 6, RSN.
fn push_beacon_body(v: &mut Vec[UInt8]) {
  push_le64(v, 4660);
  push_le16(v, 100);
  push_le16(v, 1073);
  ssid_ie(v, "TEST");
  push_ie_bytes(v, 1, vb4(130, 132, 139, 22));
  push_ie1(v, 3, 6);
  push_rsn_ccmp_psk(v);
}

// 73-byte beacon: 24-byte header + 49-byte body.
fn beacon_frame() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 8, 0);
  push_beacon_body(&mut v);
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

// A copy of `v` with `b` appended.
fn with_extra(v: Vec[UInt8], b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  out.push(b as UInt8);
  return out;
}

// Combined cipher suite identifier: OUI in the high 24 bits, type in the
// low byte.
fn suite(oui_b0: Int, oui_b1: Int, oui_b2: Int, suite_type: Int) -> Int {
  return (oui_b0 * 65536 + oui_b1 * 256 + oui_b2) * 256 + suite_type;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = beacon_frame();
  var ok = data.len() == 73;
  let r = wireless_parse(&data);
  if !r.is_ok {
    return assert(false, "beacon must parse");
  }
  let f: WirelessFrame = r.value;
  if wireless_frame_type(&f) != WIRELESS_TYPE_MANAGEMENT { ok = false; }
  if wireless_subtype(&f) != WIRELESS_MGMT_BEACON { ok = false; }
  if wireless_protocol_version(&f) != 0 { ok = false; }
  if wireless_address_count(&f) != 3 { ok = false; }
  if wireless_header_length(&f) != 24 { ok = false; }
  if wireless_body_offset(&f) != 24 { ok = false; }
  if wireless_body_length(&f) != 49 { ok = false; }
  if wireless_sequence_control(&f) != 4657 { ok = false; }
  if wireless_fragment_number(&f) != 1 { ok = false; }
  if wireless_sequence_number(&f) != 291 { ok = false; }
  if wireless_duration_id(&f) != 0 { ok = false; }
  if wireless_address_byte(&f, 1, 0) != 255 { ok = false; }
  if wireless_address_byte(&f, 1, 5) != 255 { ok = false; }
  if wireless_address_byte(&f, 2, 0) != 2 { ok = false; }
  if wireless_address_byte(&f, 3, 1) != 17 { ok = false; }
  if wireless_qos_present(&f) { ok = false; }
  if wireless_ht_control_present(&f) { ok = false; }
  if wireless_flag(&f, 0) { ok = false; }
  if wireless_flag(&f, 6) { ok = false; }
  let a3r = wireless_address(&f, 3);
  if !a3r.is_ok { ok = false; } else {
    let a3: Vec[UInt8] = a3r.value;
    if !bytes_equal(a3, vb6(16, 17, 18, 19, 20, 21)) { ok = false; }
  }
  return assert(ok, "beacon header: type, addresses, sequence split and consumed count");
}

fn t2() -> TestResult {
  let data = beacon_frame();
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "beacon body must parse");
  }
  let m: WirelessMgmt = r.value;
  var ok = wireless_mgmt_subtype(&m) == WIRELESS_MGMT_BEACON;
  if wireless_timestamp(&m) != 4660 { ok = false; }
  if wireless_beacon_interval(&m) != 100 { ok = false; }
  if wireless_capability(&m) != 1073 { ok = false; }
  if !wireless_cap_ess(wireless_capability(&m)) { ok = false; }
  if wireless_cap_ibss(wireless_capability(&m)) { ok = false; }
  if !wireless_cap_privacy(wireless_capability(&m)) { ok = false; }
  if !wireless_cap_short_preamble(wireless_capability(&m)) { ok = false; }
  if !wireless_cap_short_slot_time(wireless_capability(&m)) { ok = false; }
  if wireless_cap_spectrum_management(wireless_capability(&m)) { ok = false; }
  if wireless_cap_qos(wireless_capability(&m)) { ok = false; }
  if !wireless_capability_bit(wireless_capability(&m), 10) { ok = false; }
  if wireless_capability_bit(wireless_capability(&m), 16) { ok = false; }
  if !str_eq(wireless_body_kind_name(1), "beacon-like") { ok = false; }
  if wireless_aid(&m) != -1 { ok = false; }
  if wireless_status_code(&m) != -1 { ok = false; }
  if wireless_ie_count(&m) != 4 { ok = false; }
  return assert(ok, "beacon body: timestamp, interval, capability bits and IE count");
}

fn t3() -> TestResult {
  let data = beacon_frame();
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "beacon body must parse");
  }
  let m: WirelessMgmt = r.value;
  var ok = wireless_ie_count(&m) == 4;
  if wireless_ie_id(&m, 0) != 0 { ok = false; }
  if wireless_ie_id(&m, 1) != 1 { ok = false; }
  if wireless_ie_id(&m, 2) != 3 { ok = false; }
  if wireless_ie_id(&m, 3) != 48 { ok = false; }
  if wireless_ie_id(&m, 4) != -1 { ok = false; }
  if !str_eq(wireless_ie_name(0), "ssid") { ok = false; }
  if !str_eq(wireless_ie_name(3), "ds-parameter-set") { ok = false; }
  if !str_eq(wireless_ie_name(48), "rsn") { ok = false; }
  if m.ie_area_off != 36 { ok = false; }
  if m.ie_area_len != 37 { ok = false; }
  if wireless_ie_offset(&m, 0) != 38 { ok = false; }
  if wireless_ie_length(&m, 0) != 4 { ok = false; }
  if wireless_ie_find(&m, 48) != 3 { ok = false; }
  if wireless_ie_find(&m, 99) != -1 { ok = false; }
  if !wireless_ie_present(&m, 3) { ok = false; }
  let sr = wireless_ssid(&m);
  if !sr.is_ok { ok = false; } else {
    let ssid: Vec[UInt8] = sr.value;
    if !bytes_equal(ssid, str_bytes("TEST")) { ok = false; }
  }
  let rr = wireless_rates(&m);
  if !rr.is_ok { ok = false; } else {
    let rates: Vec[UInt8] = rr.value;
    if !bytes_equal(rates, vb4(130, 132, 139, 22)) { ok = false; }
    if !wireless_rate_is_basic(bv(rates, 0)) { ok = false; }
    if wireless_rate_half_mbps(bv(rates, 0)) != 2 { ok = false; }
    if wireless_rate_is_basic(bv(rates, 3)) { ok = false; }
    if wireless_rate_half_mbps(bv(rates, 3)) != 22 { ok = false; }
  }
  let dr = wireless_ds_channel(&m);
  if !dr.is_ok { ok = false; } else {
    let ch: Int = dr.value;
    if ch != 6 { ok = false; }
  }
  return assert(ok, "beacon IEs: SSID, rates, DS channel and pool accessors");
}

fn t4() -> TestResult {
  let data = beacon_frame();
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "beacon body must parse");
  }
  let m: WirelessMgmt = r.value;
  var ok = true;
  let vr = wireless_rsn_version(&m);
  if !vr.is_ok { ok = false; } else {
    let v: Int = vr.value;
    if v != 1 { ok = false; }
  }
  let gr = wireless_rsn_group(&m);
  if !gr.is_ok { ok = false; } else {
    let g: Int = gr.value;
    if g != suite(0, 15, 172, 4) { ok = false; }
    if wireless_suite_oui(g) != 4012 { ok = false; }
    if wireless_suite_type(g) != 4 { ok = false; }
    if wireless_suite_oui_byte(g, 0) != 0 { ok = false; }
    if wireless_suite_oui_byte(g, 1) != 15 { ok = false; }
    if wireless_suite_oui_byte(g, 2) != 172 { ok = false; }
    if wireless_suite_oui_byte(g, 3) != -1 { ok = false; }
  }
  if wireless_rsn_pairwise_count(&m) != 1 { ok = false; }
  let pr = wireless_rsn_pairwise(&m, 0);
  if !pr.is_ok { ok = false; } else {
    let p: Int = pr.value;
    if p != suite(0, 15, 172, 4) { ok = false; }
  }
  if !err_int_is(wireless_rsn_pairwise(&m, 1), "wireless: rsn pairwise index out of range") { ok = false; }
  if wireless_rsn_akm_count(&m) != 1 { ok = false; }
  let ar = wireless_rsn_akm(&m, 0);
  if !ar.is_ok { ok = false; } else {
    let a: Int = ar.value;
    if a != suite(0, 15, 172, 2) { ok = false; }
  }
  let cr = wireless_rsn_capabilities(&m);
  if !cr.is_ok { ok = false; } else {
    let c: Int = cr.value;
    if c != 12 { ok = false; }
  }
  let mr = wireless_rsn_pmkid_count(&m);
  if !mr.is_ok { ok = false; } else {
    let pc: Int = mr.value;
    if pc != -1 { ok = false; }
  }
  return assert(ok, "RSN element: version, group, pairwise, AKM and capabilities");
}

fn t5() -> TestResult {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 5, 0);
  push_le64(&mut v, 1000000);
  push_le16(&mut v, 200);
  push_le16(&mut v, 1569);
  ssid_ie(&mut v, "PROBE");
  push_ie_bytes(&mut v, 1, vb2(130, 132));
  push_ie1(&mut v, 3, 11);
  push_ie_bytes(&mut v, 5, vb4(2, 3, 0, 4));
  let data = v;
  var ok = data.len() == 56;
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "probe response must parse");
  }
  let m: WirelessMgmt = r.value;
  if wireless_mgmt_subtype(&m) != 5 { ok = false; }
  if wireless_timestamp(&m) != 1000000 { ok = false; }
  if wireless_beacon_interval(&m) != 200 { ok = false; }
  if !wireless_cap_qos(wireless_capability(&m)) { ok = false; }
  if !wireless_cap_ess(wireless_capability(&m)) { ok = false; }
  if !wireless_cap_short_preamble(wireless_capability(&m)) { ok = false; }
  if !wireless_cap_short_slot_time(wireless_capability(&m)) { ok = false; }
  let cr = wireless_tim_dtim_count(&m);
  if !cr.is_ok { ok = false; } else {
    let c: Int = cr.value;
    if c != 2 { ok = false; }
  }
  let pr = wireless_tim_dtim_period(&m);
  if !pr.is_ok { ok = false; } else {
    let p: Int = pr.value;
    if p != 3 { ok = false; }
  }
  let lr = wireless_tim_bitmap_len(&m);
  if !lr.is_ok { ok = false; } else {
    let l: Int = lr.value;
    if l != 2 { ok = false; }
  }
  let br = wireless_tim_bitmap(&data, &m);
  if !br.is_ok { ok = false; } else {
    let b: Vec[UInt8] = br.value;
    if !bytes_equal(b, vb2(0, 4)) { ok = false; }
  }
  let sr = wireless_ssid(&m);
  if !sr.is_ok { ok = false; } else {
    let s: Vec[UInt8] = sr.value;
    if !bytes_equal(s, str_bytes("PROBE")) { ok = false; }
  }
  let dr = wireless_ds_channel(&m);
  if !dr.is_ok { ok = false; } else {
    let ch: Int = dr.value;
    if ch != 11 { ok = false; }
  }
  return assert(ok, "probe response: capability, SSID, DS and TIM (count/period/bitmap)");
}

fn t6() -> TestResult {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 4, 0);
  ssid_ie(&mut v, "P");
  push_ie_bytes(&mut v, 1, vb(130));
  push_ie_bytes(&mut v, 250, vb3(1, 2, 3));
  let data = v;
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "probe request must parse");
  }
  let m: WirelessMgmt = r.value;
  var ok = data.len() == 35;
  if wireless_mgmt_subtype(&m) != 4 { ok = false; }
  if !str_eq(wireless_body_kind_name(m.body_kind), "probe-req") { ok = false; }
  if wireless_timestamp(&m) != -1 { ok = false; }
  if wireless_capability(&m) != -1 { ok = false; }
  if wireless_ie_count(&m) != 3 { ok = false; }
  if m.ie_area_off != 24 { ok = false; }
  let sr = wireless_ssid(&m);
  if !sr.is_ok { ok = false; } else {
    let s: Vec[UInt8] = sr.value;
    if !bytes_equal(s, str_bytes("P")) { ok = false; }
  }
  if !err_int_is(wireless_ds_channel(&m), "wireless: ds parameter set ie absent") { ok = false; }
  return assert(ok, "probe request: IE-only body and absent DS error");
}

fn t7() -> TestResult {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 11, 0);
  push_le16(&mut v, 0);
  push_le16(&mut v, 1);
  push_le16(&mut v, 0);
  let data = v;
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "open auth must parse");
  }
  let m: WirelessMgmt = r.value;
  var ok = data.len() == 30;
  if !str_eq(wireless_body_kind_name(m.body_kind), "auth") { ok = false; }
  if wireless_auth_algorithm(&m) != 0 { ok = false; }
  if !str_eq(wireless_auth_algorithm_name(0), "open-system") { ok = false; }
  if wireless_auth_sequence(&m) != 1 { ok = false; }
  if wireless_status_code(&m) != 0 { ok = false; }
  if !str_eq(wireless_status_name(0), "success") { ok = false; }
  if wireless_ie_count(&m) != 0 { ok = false; }
  if wireless_listen_interval(&m) != -1 { ok = false; }
  if !err_bytes_is(wireless_ssid(&m), "wireless: ssid ie absent") { ok = false; }
  return assert(ok, "open-system authentication: algorithm, sequence, status");
}

fn t8() -> TestResult {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 11, 0);
  push_le16(&mut v, 3);
  push_le16(&mut v, 2);
  push_le16(&mut v, 0);
  push_rsn_ccmp_psk(&mut v);
  let data = v;
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "SAE auth must parse");
  }
  let m: WirelessMgmt = r.value;
  var ok = wireless_auth_algorithm(&m) == 3;
  if !str_eq(wireless_auth_algorithm_name(3), "sae") { ok = false; }
  if wireless_auth_sequence(&m) != 2 { ok = false; }
  if wireless_status_code(&m) != 0 { ok = false; }
  if wireless_ie_count(&m) != 1 { ok = false; }
  let vr = wireless_rsn_version(&m);
  if !vr.is_ok { ok = false; } else {
    let ver: Int = vr.value;
    if ver != 1 { ok = false; }
  }
  if !str_eq(wireless_auth_algorithm_name(1), "shared-key") { ok = false; }
  if !str_eq(wireless_auth_algorithm_name(2), "fast-bss-transition") { ok = false; }
  if !str_eq(wireless_auth_algorithm_name(4), "fils-shared-key") { ok = false; }
  if !str_eq(wireless_auth_algorithm_name(5), "fils-shared-key-pfs") { ok = false; }
  return assert(ok, "SAE authentication: algorithm 3 with a trailing RSN element");
}

fn t9() -> TestResult {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 0, 0);
  push_le16(&mut v, 1);
  push_le16(&mut v, 10);
  ssid_ie(&mut v, "AS");
  push_ie_bytes(&mut v, 1, vb(130));
  let data = v;
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "assoc request must parse");
  }
  let m: WirelessMgmt = r.value;
  var ok = data.len() == 35;
  if wireless_mgmt_subtype(&m) != 0 { ok = false; }
  if !str_eq(wireless_body_kind_name(m.body_kind), "assoc-req") { ok = false; }
  if wireless_capability(&m) != 1 { ok = false; }
  if !wireless_cap_ess(wireless_capability(&m)) { ok = false; }
  if wireless_listen_interval(&m) != 10 { ok = false; }
  if wireless_aid(&m) != -1 { ok = false; }
  if wireless_status_code(&m) != -1 { ok = false; }
  if wireless_ie_count(&m) != 2 { ok = false; }
  let sr = wireless_ssid(&m);
  if !sr.is_ok { ok = false; } else {
    let s: Vec[UInt8] = sr.value;
    if !bytes_equal(s, str_bytes("AS")) { ok = false; }
  }
  return assert(ok, "association request: capability, listen interval and SSID");
}

fn t10() -> TestResult {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 1, 0);
  push_le16(&mut v, 513);
  push_le16(&mut v, 0);
  push_le16(&mut v, 1);
  ssid_ie(&mut v, "AS");
  let data = v;
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "assoc response must parse");
  }
  let m: WirelessMgmt = r.value;
  var ok = data.len() == 34;
  if !str_eq(wireless_body_kind_name(m.body_kind), "assoc-resp") { ok = false; }
  if wireless_capability(&m) != 513 { ok = false; }
  if !wireless_cap_qos(wireless_capability(&m)) { ok = false; }
  if !wireless_cap_ess(wireless_capability(&m)) { ok = false; }
  if wireless_status_code(&m) != 0 { ok = false; }
  if !str_eq(wireless_status_name(wireless_status_code(&m)), "success") { ok = false; }
  if wireless_aid(&m) != 1 { ok = false; }
  if wireless_listen_interval(&m) != -1 { ok = false; }
  if wireless_ie_count(&m) != 1 { ok = false; }
  return assert(ok, "association response: capability, status and AID");
}

fn t11() -> TestResult {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 2, 0);
  push_le16(&mut v, 1);
  push_le16(&mut v, 5);
  push_mac(&mut v, 10, 11, 12, 13, 14, 15);
  ssid_ie(&mut v, "RA");
  let data = v;
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "reassoc request must parse");
  }
  let m: WirelessMgmt = r.value;
  var ok = data.len() == 38;
  if !str_eq(wireless_body_kind_name(m.body_kind), "reassoc-req") { ok = false; }
  if wireless_listen_interval(&m) != 5 { ok = false; }
  if wireless_ie_count(&m) != 1 { ok = false; }
  let ap = wireless_current_ap(&m);
  if !bytes_equal(ap, vb6(10, 11, 12, 13, 14, 15)) { ok = false; }
  if !str_eq(wireless_subtype_name(WIRELESS_TYPE_MANAGEMENT, 2), "reassoc-req") { ok = false; }
  return assert(ok, "reassociation request: current AP address and IEs");
}

fn t12() -> TestResult {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 10, 0);
  push_le16(&mut v, 3);
  let disassoc = v;
  let r1 = wireless_parse_mgmt(&disassoc);
  var ok = r1.is_ok;
  if !r1.is_ok {
    return assert(false, "disassoc must parse");
  }
  let m1: WirelessMgmt = r1.value;
  if wireless_reason_code(&m1) != 3 { ok = false; }
  if !str_eq(wireless_reason_name(3), "sta-leaving-ibss-ess") { ok = false; }
  if wireless_ie_count(&m1) != 0 { ok = false; }
  var w = Vec[UInt8].new();
  push_mgmt_header(&mut w, 12, 0);
  push_le16(&mut w, 15);
  let deauth = w;
  let r2 = wireless_parse_mgmt(&deauth);
  if !r2.is_ok { ok = false; } else {
    let m2: WirelessMgmt = r2.value;
    if wireless_reason_code(&m2) != 15 { ok = false; }
    if !str_eq(wireless_reason_name(15), "4way-handshake-timeout") { ok = false; }
  }
  let extra = with_extra(disassoc, 0);
  if !err_mgmt_is(wireless_parse_mgmt(&extra), "wireless: unexpected management body bytes at offset 26: 1") { ok = false; }
  let short = prefix(disassoc, 25);
  if !err_mgmt_is(wireless_parse_mgmt(&short), "wireless: truncated management body at offset 24: need 2 bytes, have 1") { ok = false; }
  return assert(ok, "disassoc/deauth reasons and exact body length");
}

fn t13() -> TestResult {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 9, 0);
  let atim = v;
  let r = wireless_parse_mgmt(&atim);
  var ok = r.is_ok;
  if !r.is_ok {
    return assert(false, "ATIM must parse");
  }
  let m: WirelessMgmt = r.value;
  if !str_eq(wireless_body_kind_name(m.body_kind), "atim") { ok = false; }
  if wireless_ie_count(&m) != 0 { ok = false; }
  if wireless_action_category(&m) != -1 { ok = false; }
  if atim.len() != 24 { ok = false; }
  let extra = with_extra(atim, 0);
  if !err_mgmt_is(wireless_parse_mgmt(&extra), "wireless: unexpected management body bytes at offset 24: 1") { ok = false; }
  return assert(ok, "ATIM: empty body and rejection of trailing bytes");
}

fn t14() -> TestResult {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 13, 0);
  pb(&mut v, 0);
  pb(&mut v, 0);
  pb(&mut v, 1);
  pb(&mut v, 2);
  pb(&mut v, 3);
  let data = v;
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "action frame must parse");
  }
  let m: WirelessMgmt = r.value;
  var ok = data.len() == 29;
  if !str_eq(wireless_subtype_name(WIRELESS_TYPE_MANAGEMENT, 13), "action") { ok = false; }
  if !str_eq(wireless_body_kind_name(m.body_kind), "action") { ok = false; }
  if wireless_action_category(&m) != 0 { ok = false; }
  if wireless_action_code(&m) != 0 { ok = false; }
  if m.action_off != 26 { ok = false; }
  if m.action_len != 3 { ok = false; }
  if wireless_ie_count(&m) != 0 { ok = false; }
  var w = Vec[UInt8].new();
  push_mgmt_header(&mut w, 14, 0);
  pb(&mut w, 4);
  pb(&mut w, 1);
  let r2 = wireless_parse_mgmt(&w);
  if !r2.is_ok { ok = false; } else {
    let m2: WirelessMgmt = r2.value;
    if wireless_action_category(&m2) != 4 { ok = false; }
    if wireless_action_code(&m2) != 1 { ok = false; }
    if m2.action_len != 0 { ok = false; }
    if !str_eq(wireless_subtype_name(WIRELESS_TYPE_MANAGEMENT, 14), "action-no-ack") { ok = false; }
  }
  return assert(ok, "action and action-no-ack: category, code and raw payload span");
}

fn t15() -> TestResult {
  var ok = true;
  var a = Vec[UInt8].new();
  push_mgmt_header(&mut a, 6, 0);
  if !err_mgmt_is(wireless_parse_mgmt(&a), "wireless: unsupported management subtype 6") { ok = false; }
  var b = Vec[UInt8].new();
  push_mgmt_header(&mut b, 7, 0);
  if !err_mgmt_is(wireless_parse_mgmt(&b), "wireless: unsupported management subtype 7") { ok = false; }
  var c = Vec[UInt8].new();
  push_mgmt_header(&mut c, 15, 0);
  if !err_mgmt_is(wireless_parse_mgmt(&c), "wireless: unsupported management subtype 15") { ok = false; }
  return assert(ok, "reserved management subtypes 6, 7 and 15 are rejected");
}

fn t16() -> TestResult {
  var v = Vec[UInt8].new();
  push_data_header(&mut v, 8, 0, false);
  push_le16(&mut v, 726);
  pb(&mut v, 9);
  pb(&mut v, 9);
  pb(&mut v, 9);
  pb(&mut v, 9);
  let data = v;
  let r = wireless_parse(&data);
  if !r.is_ok {
    return assert(false, "QoS data must parse");
  }
  let f: WirelessFrame = r.value;
  var ok = data.len() == 30;
  if wireless_frame_type(&f) != WIRELESS_TYPE_DATA { ok = false; }
  if wireless_subtype(&f) != 8 { ok = false; }
  if !str_eq(wireless_subtype_name(2, 8), "qos-data") { ok = false; }
  if wireless_header_length(&f) != 26 { ok = false; }
  if wireless_body_length(&f) != 4 { ok = false; }
  if !wireless_qos_present(&f) { ok = false; }
  if f.qos_control_off != 24 { ok = false; }
  if wireless_tid(&f) != 6 { ok = false; }
  if !wireless_eosp(&f) { ok = false; }
  if wireless_ack_policy(&f) != 2 { ok = false; }
  if !str_eq(wireless_ack_policy_name(wireless_ack_policy(&f)), "no-explicit-ack") { ok = false; }
  if !wireless_a_msdu_present(&f) { ok = false; }
  if wireless_txop_limit(&f) != 2 { ok = false; }
  if wireless_flag(&f, 4) { ok = false; }
  if wireless_ht_control_present(&f) { ok = false; }
  return assert(ok, "QoS data: QoS control TID/EOSP/ack policy/A-MSDU/TXOP and offsets");
}

fn t17() -> TestResult {
  var v = Vec[UInt8].new();
  push_data_header(&mut v, 8, 128, false);
  push_le16(&mut v, 6);
  push_le32(&mut v, 0);
  let data = v;
  let r = wireless_parse(&data);
  if !r.is_ok {
    return assert(false, "QoS data with order must parse");
  }
  let f: WirelessFrame = r.value;
  var ok = data.len() == 30;
  if wireless_header_length(&f) != 30 { ok = false; }
  if !wireless_ht_control_present(&f) { ok = false; }
  if f.ht_control_off != 26 { ok = false; }
  if wireless_body_length(&f) != 0 { ok = false; }
  if wireless_tid(&f) != 6 { ok = false; }
  return assert(ok, "QoS data with Order bit: 4-byte HT control counted in the header");
}

fn t18() -> TestResult {
  var v = Vec[UInt8].new();
  push_data_header(&mut v, 0, 3, true);
  pb(&mut v, 7);
  pb(&mut v, 8);
  let data = v;
  let r = wireless_parse(&data);
  if !r.is_ok {
    return assert(false, "WDS data must parse");
  }
  let f: WirelessFrame = r.value;
  var ok = data.len() == 32;
  if !f.to_ds { ok = false; }
  if !f.from_ds { ok = false; }
  if wireless_address_count(&f) != 4 { ok = false; }
  if wireless_header_length(&f) != 30 { ok = false; }
  if wireless_address_byte(&f, 4, 0) != 4 { ok = false; }
  if wireless_address_byte(&f, 4, 5) != 4 { ok = false; }
  if wireless_qos_present(&f) { ok = false; }
  let a4r = wireless_address(&f, 4);
  if !a4r.is_ok { ok = false; } else {
    let a4: Vec[UInt8] = a4r.value;
    if !bytes_equal(a4, vb6(4, 4, 4, 4, 4, 4)) { ok = false; }
  }
  return assert(ok, "4-address WDS data: To DS + From DS matrix and addr4");
}

fn t19() -> TestResult {
  var v = Vec[UInt8].new();
  push_data_header(&mut v, 4, 0, false);
  let null_data = v;
  let r1 = wireless_parse(&null_data);
  var ok = r1.is_ok;
  if !r1.is_ok {
    return assert(false, "null data must parse");
  }
  let f1: WirelessFrame = r1.value;
  if !str_eq(wireless_subtype_name(2, 4), "null") { ok = false; }
  if wireless_header_length(&f1) != 24 { ok = false; }
  if wireless_qos_present(&f1) { ok = false; }
  if wireless_tid(&f1) != -1 { ok = false; }
  var w = Vec[UInt8].new();
  push_data_header(&mut w, 12, 0, false);
  push_le16(&mut w, 5);
  let qos_null = w;
  let r2 = wireless_parse(&qos_null);
  if !r2.is_ok { ok = false; } else {
    let f2: WirelessFrame = r2.value;
    if !str_eq(wireless_subtype_name(2, 12), "qos-null") { ok = false; }
    if !wireless_qos_present(&f2) { ok = false; }
    if wireless_header_length(&f2) != 26 { ok = false; }
    if wireless_tid(&f2) != 5 { ok = false; }
  }
  return assert(ok, "null data has no QoS control, QoS null has one");
}

fn t20() -> TestResult {
  var v = Vec[UInt8].new();
  push_ctrl_header(&mut v, 11, 0, true);
  let data = v;
  let r = wireless_parse(&data);
  if !r.is_ok {
    return assert(false, "RTS must parse");
  }
  let f: WirelessFrame = r.value;
  var ok = data.len() == 16;
  if wireless_frame_type(&f) != WIRELESS_TYPE_CONTROL { ok = false; }
  if wireless_subtype(&f) != 11 { ok = false; }
  if !str_eq(wireless_subtype_name(1, 11), "rts") { ok = false; }
  if wireless_header_length(&f) != 16 { ok = false; }
  if wireless_address_count(&f) != 2 { ok = false; }
  if wireless_duration_id(&f) != 320 { ok = false; }
  if wireless_sequence_control(&f) != -1 { ok = false; }
  if wireless_sequence_number(&f) != -1 { ok = false; }
  if wireless_fragment_number(&f) != -1 { ok = false; }
  if wireless_body_length(&f) != 0 { ok = false; }
  if !err_bytes_is(wireless_address(&f, 3), "wireless: address absent") { ok = false; }
  if wireless_address_byte(&f, 1, 0) != 1 { ok = false; }
  if wireless_address_byte(&f, 2, 5) != 2 { ok = false; }
  return assert(ok, "RTS: 16-byte header, 2 addresses, no sequence control");
}

fn t21() -> TestResult {
  var v = Vec[UInt8].new();
  push_ctrl_header(&mut v, 12, 0, false);
  let cts = v;
  let r1 = wireless_parse(&cts);
  var ok = r1.is_ok;
  if !r1.is_ok {
    return assert(false, "CTS must parse");
  }
  let f1: WirelessFrame = r1.value;
  if !str_eq(wireless_subtype_name(1, 12), "cts") { ok = false; }
  if wireless_header_length(&f1) != 10 { ok = false; }
  if wireless_address_count(&f1) != 1 { ok = false; }
  if wireless_address_byte(&f1, 1, 0) != 1 { ok = false; }
  if !err_bytes_is(wireless_address(&f1, 2), "wireless: address absent") { ok = false; }
  var w = Vec[UInt8].new();
  push_ctrl_header(&mut w, 13, 0, false);
  let ack = w;
  let r2 = wireless_parse(&ack);
  if !r2.is_ok { ok = false; } else {
    let f2: WirelessFrame = r2.value;
    if !str_eq(wireless_subtype_name(1, 13), "ack") { ok = false; }
    if wireless_header_length(&f2) != 10 { ok = false; }
    if wireless_address_count(&f2) != 1 { ok = false; }
    if wireless_duration_id(&f2) != 320 { ok = false; }
  }
  return assert(ok, "CTS and ACK: 10-byte header with a single address");
}

fn t22() -> TestResult {
  var ok = true;
  var a = Vec[UInt8].new();
  push_ctrl_header(&mut a, 8, 0, true);
  let r8 = wireless_parse(&a);
  if !r8.is_ok { ok = false; } else {
    let f8: WirelessFrame = r8.value;
    if wireless_header_length(&f8) != 16 { ok = false; }
    if wireless_address_count(&f8) != 2 { ok = false; }
  }
  var b = Vec[UInt8].new();
  push_ctrl_header(&mut b, 9, 0, true);
  let r9 = wireless_parse(&b);
  if !r9.is_ok { ok = false; } else {
    let f9: WirelessFrame = r9.value;
    if wireless_header_length(&f9) != 16 { ok = false; }
    if wireless_address_count(&f9) != 2 { ok = false; }
  }
  var c = Vec[UInt8].new();
  push_ctrl_header(&mut c, 10, 0, true);
  let r10 = wireless_parse(&c);
  if !r10.is_ok { ok = false; } else {
    let f10: WirelessFrame = r10.value;
    if wireless_header_length(&f10) != 16 { ok = false; }
    if wireless_address_count(&f10) != 2 { ok = false; }
    if wireless_subtype(&f10) != WIRELESS_CTRL_PS_POLL { ok = false; }
  }
  if !str_eq(wireless_subtype_name(1, 8), "bar") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 9), "ba") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 10), "ps-poll") { ok = false; }
  return assert(ok, "BAR, BA and PS-Poll use 16-byte headers with two addresses");
}

fn t23() -> TestResult {
  var ok = true;
  var s = 0;
  while s < 8 {
    var v = Vec[UInt8].new();
    push_ctrl_header(&mut v, s, 0, false);
    let want = "wireless: unsupported control subtype " + ints(s);
    if !err_frame_is(wireless_parse(&v), want) { ok = false; }
    s = s + 1;
  }
  var m = Vec[UInt8].new();
  push_mgmt_header(&mut m, 8, 1);
  if !err_frame_is(wireless_parse(&m), "wireless: invalid ds bits for management frame") { ok = false; }
  var c = Vec[UInt8].new();
  push_ctrl_header(&mut c, 13, 2, false);
  if !err_frame_is(wireless_parse(&c), "wireless: invalid ds bits for control frame") { ok = false; }
  return assert(ok, "control subtypes 0..7 rejected and invalid management/control DS bits");
}

fn t24() -> TestResult {
  var ok = true;
  let short_mgmt = prefix(beacon_frame(), 20);
  if !err_frame_is(wireless_parse(&short_mgmt), "wireless: truncated frame at offset 0: need 24 bytes, have 20") { ok = false; }
  var c = Vec[UInt8].new();
  push_ctrl_header(&mut c, 12, 0, false);
  let short_cts = prefix(c, 8);
  if !err_frame_is(wireless_parse(&short_cts), "wireless: truncated frame at offset 0: need 10 bytes, have 8") { ok = false; }
  var q = Vec[UInt8].new();
  push_data_header(&mut q, 8, 0, false);
  pb(&mut q, 0);
  let short_qos = prefix(q, 25);
  if !err_frame_is(wireless_parse(&short_qos), "wireless: truncated qos control at offset 24: need 2 bytes, have 1") { ok = false; }
  var h = Vec[UInt8].new();
  push_data_header(&mut h, 8, 128, false);
  push_le16(&mut h, 0);
  push_le16(&mut h, 0);
  let short_ht = prefix(h, 28);
  if !err_frame_is(wireless_parse(&short_ht), "wireless: truncated ht control at offset 26: need 4 bytes, have 2") { ok = false; }
  var w = Vec[UInt8].new();
  push_data_header(&mut w, 0, 3, true);
  let short_wds = prefix(w, 29);
  if !err_frame_is(wireless_parse(&short_wds), "wireless: truncated frame at offset 0: need 30 bytes, have 29") { ok = false; }
  return assert(ok, "truncation at every header stage reports offset, need and have");
}

fn t25() -> TestResult {
  var ok = true;
  var a = Vec[UInt8].new();
  push_mgmt_header(&mut a, 8, 0);
  push_le64(&mut a, 4660);
  push_le16(&mut a, 100);
  push_le16(&mut a, 1);
  pb(&mut a, 0);
  if !err_mgmt_is(wireless_parse_mgmt(&a), "wireless: truncated ie header at offset 36: need 2 bytes, have 1") { ok = false; }
  var b = Vec[UInt8].new();
  push_mgmt_header(&mut b, 8, 0);
  push_le64(&mut b, 4660);
  push_le16(&mut b, 100);
  push_le16(&mut b, 1);
  pb(&mut b, 250);
  pb(&mut b, 10);
  pb(&mut b, 170);
  pb(&mut b, 187);
  pb(&mut b, 204);
  if !err_mgmt_is(wireless_parse_mgmt(&b), "wireless: bad ie length at offset 36: ie 250 length 10 exceeds 3 remaining bytes") { ok = false; }
  return assert(ok, "malformed IE TLV framing: truncated header and overlong length");
}

fn t26() -> TestResult {
  var ok = true;
  var a = Vec[UInt8].new();
  push_mgmt_header(&mut a, 4, 0);
  push_ie2(&mut a, 3, 1, 2);
  if !err_mgmt_is(wireless_parse_mgmt(&a), "wireless: bad ds parameter set ie length at offset 24: 2") { ok = false; }
  var b = Vec[UInt8].new();
  push_mgmt_header(&mut b, 4, 0);
  push_ie1(&mut b, 5, 0);
  if !err_mgmt_is(wireless_parse_mgmt(&b), "wireless: bad tim ie length at offset 24: 1") { ok = false; }
  var c = Vec[UInt8].new();
  push_mgmt_header(&mut c, 4, 0);
  push_ie_bytes(&mut c, 7, vb4(85, 83, 1, 2));
  if !err_mgmt_is(wireless_parse_mgmt(&c), "wireless: bad country ie length at offset 24: 4") { ok = false; }
  var d = Vec[UInt8].new();
  push_mgmt_header(&mut d, 4, 0);
  push_ie_bytes(&mut d, 48, vb4(1, 0, 0, 0));
  if !err_mgmt_is(wireless_parse_mgmt(&d), "wireless: bad rsn ie length at offset 24: 4") { ok = false; }
  var e = Vec[UInt8].new();
  push_mgmt_header(&mut e, 4, 0);
  push_ie_bytes(&mut e, 45, vb3(1, 2, 3));
  if !err_mgmt_is(wireless_parse_mgmt(&e), "wireless: bad ht capabilities ie length at offset 24: 3") { ok = false; }
  var g = Vec[UInt8].new();
  push_mgmt_header(&mut g, 4, 0);
  push_ie_bytes(&mut g, 191, vb4(1, 2, 3, 4));
  if !err_mgmt_is(wireless_parse_mgmt(&g), "wireless: bad vht capabilities ie length at offset 24: 4") { ok = false; }
  var i = Vec[UInt8].new();
  push_mgmt_header(&mut i, 4, 0);
  push_ie_empty(&mut i, 127);
  if !err_mgmt_is(wireless_parse_mgmt(&i), "wireless: bad extended capabilities ie length at offset 24: 0") { ok = false; }
  var j = Vec[UInt8].new();
  push_mgmt_header(&mut j, 4, 0);
  push_ie2(&mut j, 221, 1, 2);
  if !err_mgmt_is(wireless_parse_mgmt(&j), "wireless: bad vendor ie length at offset 24: 2") { ok = false; }
  return assert(ok, "impossible DS/TIM/country/RSN/HT/VHT/extended/vendor IE lengths");
}

fn t27() -> TestResult {
  var ok = true;
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 4, 0);
  push_ie_bytes(&mut v, 250, vb3(9, 8, 7));
  push_ie1(&mut v, 3, 6);
  push_ie_empty(&mut v, 250);
  let data = v;
  if data.len() != 34 { ok = false; }
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "unknown IEs must not fail the walk");
  }
  let m: WirelessMgmt = r.value;
  if wireless_ie_count(&m) != 3 { ok = false; }
  if m.ie_area_off != 24 { ok = false; }
  if m.ie_area_len != 10 { ok = false; }
  if wireless_ie_offset(&m, 0) != 26 { ok = false; }
  if wireless_ie_length(&m, 0) != 3 { ok = false; }
  if wireless_ie_offset(&m, 1) != 31 { ok = false; }
  if wireless_ie_offset(&m, 2) != 34 { ok = false; }
  if wireless_ie_length(&m, 2) != 0 { ok = false; }
  if !str_eq(wireless_ie_name(250), "unknown") { ok = false; }
  let p0r = wireless_ie_payload(&data, &m, 0);
  if !p0r.is_ok { ok = false; } else {
    let p0: Vec[UInt8] = p0r.value;
    if !bytes_equal(p0, vb3(9, 8, 7)) { ok = false; }
  }
  let p2r = wireless_ie_payload(&data, &m, 2);
  if !p2r.is_ok { ok = false; } else {
    let p2: Vec[UInt8] = p2r.value;
    if p2.len() != 0 { ok = false; }
  }
  let pr = wireless_ie_payload_of(&data, &m, 3);
  if !pr.is_ok { ok = false; } else {
    let p: Vec[UInt8] = pr.value;
    if !bytes_equal(p, vb(6)) { ok = false; }
  }
  if !err_bytes_is(wireless_ie_payload_of(&data, &m, 77), "wireless: ie absent") { ok = false; }
  if !err_bytes_is(wireless_ie_payload(&data, &m, 9), "wireless: ie index out of range") { ok = false; }
  return assert(ok, "unknown IEs are preserved raw with exact offsets and lengths");
}

fn t28() -> TestResult {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 4, 0);
  push_ie_bytes(&mut v, 221, vb6(0, 80, 242, 1, 170, 187));
  push_ie_bytes(&mut v, 221, vb6(0, 80, 242, 2, 204, 221));
  push_ie_bytes(&mut v, 221, vb6(0, 17, 34, 3, 238, 255));
  let data = v;
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "vendor IEs must parse");
  }
  let m: WirelessMgmt = r.value;
  var ok = wireless_vendor_count(&m) == 3;
  if !wireless_vendor_wpa(&m) { ok = false; }
  if !wireless_vendor_wmm(&m) { ok = false; }
  let o0 = wireless_vendor_oui(&m, 0);
  if !o0.is_ok { ok = false; } else {
    let o: Int = o0.value;
    if o != 20722 { ok = false; }
  }
  let t0 = wireless_vendor_type(&m, 0);
  if !t0.is_ok { ok = false; } else {
    let ty: Int = t0.value;
    if ty != 1 { ok = false; }
  }
  let t1 = wireless_vendor_type(&m, 1);
  if !t1.is_ok { ok = false; } else {
    let ty: Int = t1.value;
    if ty != 2 { ok = false; }
  }
  let o2 = wireless_vendor_oui(&m, 2);
  if !o2.is_ok { ok = false; } else {
    let o: Int = o2.value;
    if o != 4386 { ok = false; }
  }
  let t2 = wireless_vendor_type(&m, 2);
  if !t2.is_ok { ok = false; } else {
    let ty: Int = t2.value;
    if ty != 3 { ok = false; }
  }
  if !err_int_is(wireless_vendor_oui(&m, 3), "wireless: vendor index out of range") { ok = false; }
  let p0r = wireless_ie_payload(&data, &m, 0);
  if !p0r.is_ok { ok = false; } else {
    let p0: Vec[UInt8] = p0r.value;
    if !bytes_equal(p0, vb6(0, 80, 242, 1, 170, 187)) { ok = false; }
  }
  return assert(ok, "vendor elements: WPA (00:50:F2 type 1) and WMM (type 2) recognized");
}

fn t29() -> TestResult {
  var v = Vec[UInt8].new();
  push_mgmt_header(&mut v, 5, 0);
  push_le64(&mut v, 500);
  push_le16(&mut v, 50);
  push_le16(&mut v, 1);
  pb(&mut v, 45);
  pb(&mut v, 26);
  push_le16(&mut v, 258);
  pb(&mut v, 3);
  var i = 0;
  while i < 23 {
    pb(&mut v, 0);
    i = i + 1;
  }
  pb(&mut v, 191);
  pb(&mut v, 12);
  push_le32(&mut v, 16909060);
  i = 0;
  while i < 8 {
    pb(&mut v, 0);
    i = i + 1;
  }
  pb(&mut v, 127);
  pb(&mut v, 8);
  i = 0;
  while i < 8 {
    pb(&mut v, i + 1);
    i = i + 1;
  }
  let data = v;
  let r = wireless_parse_mgmt(&data);
  if !r.is_ok {
    return assert(false, "HT/VHT/extended capabilities must parse");
  }
  let m: WirelessMgmt = r.value;
  var ok = wireless_ie_count(&m) == 3;
  if !m.ht_present { ok = false; }
  if !m.vht_present { ok = false; }
  if !m.ext_present { ok = false; }
  let hr = wireless_ht_cap_info(&m);
  if !hr.is_ok { ok = false; } else {
    let h: Int = hr.value;
    if h != 258 { ok = false; }
  }
  let ar = wireless_ht_ampdu(&m);
  if !ar.is_ok { ok = false; } else {
    let a: Int = ar.value;
    if a != 3 { ok = false; }
  }
  let vr = wireless_vht_cap_info(&m);
  if !vr.is_ok { ok = false; } else {
    let vi: Int = vr.value;
    if vi != 16909060 { ok = false; }
  }
  let er = wireless_ext_cap_len(&m);
  if !er.is_ok { ok = false; } else {
    let e: Int = er.value;
    if e != 8 { ok = false; }
  }
  if wireless_vendor_count(&m) != 0 { ok = false; }
  var empty = Vec[UInt8].new();
  push_mgmt_header(&mut empty, 4, 0);
  let er2 = wireless_parse_mgmt(&empty);
  if !er2.is_ok { ok = false; } else {
    let em: WirelessMgmt = er2.value;
    if !err_int_is(wireless_ht_cap_info(&em), "wireless: ht capabilities ie absent") { ok = false; }
    if !err_int_is(wireless_vht_cap_info(&em), "wireless: vht capabilities ie absent") { ok = false; }
    if !err_int_is(wireless_ext_cap_len(&em), "wireless: extended capabilities ie absent") { ok = false; }
    if !err_int_is(wireless_rsn_version(&em), "wireless: rsn ie absent") { ok = false; }
  }
  return assert(ok, "HT, VHT and extended capabilities decode");
}

fn t30() -> TestResult {
  let data = beacon_frame();
  let r = wireless_parse(&data);
  if !r.is_ok {
    return assert(false, "beacon must parse");
  }
  let f: WirelessFrame = r.value;
  var ok = true;
  let bodyr = wireless_body(&data, &f);
  if !bodyr.is_ok { ok = false; } else {
    let body: Vec[UInt8] = bodyr.value;
    if body.len() != 49 { ok = false; }
    if bv(body, 0) != 52 { ok = false; }
    if bv(body, 47) != 12 { ok = false; }
    if bv(body, 48) != 0 { ok = false; }
  }
  let short_data = prefix(data, 10);
  if !err_bytes_is(wireless_body(&short_data, &f), "wireless: body out of bounds") { ok = false; }
  if !err_bytes_is(wireless_address(&f, 0), "wireless: address index out of range") { ok = false; }
  if !err_bytes_is(wireless_address(&f, 5), "wireless: address index out of range") { ok = false; }
  if wireless_address_byte(&f, 0, 0) != -1 { ok = false; }
  if wireless_address_byte(&f, 1, 6) != -1 { ok = false; }
  if wireless_address_byte(&f, 4, 0) != -1 { ok = false; }
  let a1r = wireless_address(&f, 1);
  if !a1r.is_ok { ok = false; } else {
    let a1: Vec[UInt8] = a1r.value;
    if !bytes_equal(a1, vb6(255, 255, 255, 255, 255, 255)) { ok = false; }
    if bv(a1, 3) != 255 { ok = false; }
  }
  return assert(ok, "body copy and address accessors with absent/out-of-range guards");
}

fn t31() -> TestResult {
  var ok = str_eq(wireless_version(), "xiom.wireless 0.1.0");
  if !str_eq(wireless_type_name(0), "management") { ok = false; }
  if !str_eq(wireless_type_name(1), "control") { ok = false; }
  if !str_eq(wireless_type_name(2), "data") { ok = false; }
  if !str_eq(wireless_type_name(3), "extension") { ok = false; }
  if !str_eq(wireless_type_name(4), "unknown") { ok = false; }
  if !str_eq(wireless_subtype_name(0, 0), "assoc-req") { ok = false; }
  if !str_eq(wireless_subtype_name(0, 1), "assoc-resp") { ok = false; }
  if !str_eq(wireless_subtype_name(0, 4), "probe-req") { ok = false; }
  if !str_eq(wireless_subtype_name(0, 5), "probe-resp") { ok = false; }
  if !str_eq(wireless_subtype_name(0, 8), "beacon") { ok = false; }
  if !str_eq(wireless_subtype_name(0, 9), "atim") { ok = false; }
  if !str_eq(wireless_subtype_name(0, 10), "disassoc") { ok = false; }
  if !str_eq(wireless_subtype_name(0, 11), "auth") { ok = false; }
  if !str_eq(wireless_subtype_name(0, 12), "deauth") { ok = false; }
  if !str_eq(wireless_subtype_name(0, 15), "reserved") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 0), "reserved") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 1), "reserved") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 2), "trigger") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 3), "tack") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 4), "beamforming-report-poll") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 5), "vht-ndp-announcement") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 6), "control-frame-extension") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 7), "control-wrapper") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 8), "bar") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 9), "ba") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 10), "ps-poll") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 11), "rts") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 12), "cts") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 13), "ack") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 14), "cf-end") { ok = false; }
  if !str_eq(wireless_subtype_name(1, 15), "cf-end+cf-ack") { ok = false; }
  if !str_eq(wireless_subtype_name(2, 0), "data") { ok = false; }
  if !str_eq(wireless_subtype_name(2, 4), "null") { ok = false; }
  if !str_eq(wireless_subtype_name(2, 8), "qos-data") { ok = false; }
  if !str_eq(wireless_subtype_name(2, 12), "qos-null") { ok = false; }
  if !str_eq(wireless_subtype_name(3, 0), "dmg-beacon") { ok = false; }
  if !str_eq(wireless_subtype_name(2, 16), "unknown") { ok = false; }
  if !str_eq(wireless_flag_name(0), "to-ds") { ok = false; }
  if !str_eq(wireless_flag_name(1), "from-ds") { ok = false; }
  if !str_eq(wireless_flag_name(2), "more-fragments") { ok = false; }
  if !str_eq(wireless_flag_name(3), "retry") { ok = false; }
  if !str_eq(wireless_flag_name(4), "power-management") { ok = false; }
  if !str_eq(wireless_flag_name(5), "more-data") { ok = false; }
  if !str_eq(wireless_flag_name(6), "protected") { ok = false; }
  if !str_eq(wireless_flag_name(7), "order") { ok = false; }
  if !str_eq(wireless_flag_name(9), "unknown") { ok = false; }
  if !str_eq(wireless_status_name(1), "unspecified-failure") { ok = false; }
  if !str_eq(wireless_status_name(10), "capabilities-unsupported") { ok = false; }
  if !str_eq(wireless_status_name(17), "ap-unable-to-handle-stas") { ok = false; }
  if !str_eq(wireless_status_name(30), "temporarily-rejected") { ok = false; }
  if !str_eq(wireless_status_name(40), "invalid-ie") { ok = false; }
  if !str_eq(wireless_status_name(71), "unknown") { ok = false; }
  if !str_eq(wireless_reason_name(1), "unspecified") { ok = false; }
  if !str_eq(wireless_reason_name(4), "inactivity") { ok = false; }
  if !str_eq(wireless_reason_name(16), "group-key-handshake-timeout") { ok = false; }
  if !str_eq(wireless_reason_name(34), "qos-low-ack") { ok = false; }
  if !str_eq(wireless_reason_name(40), "qos-cipher-not-supported") { ok = false; }
  if !str_eq(wireless_reason_name(41), "unknown") { ok = false; }
  if !str_eq(wireless_ack_policy_name(0), "normal-ack") { ok = false; }
  if !str_eq(wireless_ack_policy_name(3), "block-ack") { ok = false; }
  if !str_eq(wireless_ack_policy_name(4), "unknown") { ok = false; }
  if !str_eq(wireless_ie_name(1), "supported-rates") { ok = false; }
  if !str_eq(wireless_ie_name(5), "tim") { ok = false; }
  if !str_eq(wireless_ie_name(7), "country") { ok = false; }
  if !str_eq(wireless_ie_name(45), "ht-capabilities") { ok = false; }
  if !str_eq(wireless_ie_name(127), "extended-capabilities") { ok = false; }
  if !str_eq(wireless_ie_name(221), "vendor-specific") { ok = false; }
  if !str_eq(wireless_ie_name(222), "unknown") { ok = false; }
  if !str_eq(wireless_body_kind_name(2), "probe-req") { ok = false; }
  if !str_eq(wireless_body_kind_name(5), "assoc-resp") { ok = false; }
  if !str_eq(wireless_body_kind_name(6), "reason") { ok = false; }
  if !str_eq(wireless_body_kind_name(8), "action") { ok = false; }
  if !str_eq(wireless_body_kind_name(9), "atim") { ok = false; }
  if !str_eq(wireless_body_kind_name(0), "unknown") { ok = false; }
  return assert(ok, "type, subtype, flag, status, reason, ack, IE and body-kind names");
}

fn t32() -> TestResult {
  var v = Vec[UInt8].new();
  push_ctrl_header(&mut v, 14, 0, false);
  let cf_end = v;
  let r1 = wireless_parse(&cf_end);
  var ok = r1.is_ok;
  if !r1.is_ok {
    return assert(false, "CF-End must parse");
  }
  let f1: WirelessFrame = r1.value;
  if !str_eq(wireless_subtype_name(1, 14), "cf-end") { ok = false; }
  if wireless_subtype(&f1) != WIRELESS_CTRL_CF_END { ok = false; }
  if wireless_header_length(&f1) != 10 { ok = false; }
  if wireless_address_count(&f1) != 1 { ok = false; }
  if wireless_address_byte(&f1, 1, 0) != 1 { ok = false; }
  if !err_bytes_is(wireless_address(&f1, 2), "wireless: address absent") { ok = false; }
  if wireless_sequence_control(&f1) != -1 { ok = false; }
  if wireless_body_length(&f1) != 0 { ok = false; }
  var w = Vec[UInt8].new();
  push_ctrl_header(&mut w, 15, 0, false);
  let cf_end_ack = w;
  let r2 = wireless_parse(&cf_end_ack);
  if !r2.is_ok { ok = false; } else {
    let f2: WirelessFrame = r2.value;
    if !str_eq(wireless_subtype_name(1, 15), "cf-end+cf-ack") { ok = false; }
    if wireless_subtype(&f2) != WIRELESS_CTRL_CF_END_ACK { ok = false; }
    if wireless_header_length(&f2) != 10 { ok = false; }
    if wireless_address_count(&f2) != 1 { ok = false; }
    if wireless_duration_id(&f2) != 320 { ok = false; }
  }
  return assert(ok, "CF-End and CF-End + CF-Ack: 10-byte headers with a single address");
}

fn t33() -> TestResult {
  var v = Vec[UInt8].new();
  push_ctrl_header(&mut v, 10, 0, true);
  let ps_poll = v;
  let r = wireless_parse(&ps_poll);
  var ok = r.is_ok;
  if !r.is_ok {
    return assert(false, "PS-Poll must parse");
  }
  let f: WirelessFrame = r.value;
  if wireless_subtype(&f) != WIRELESS_CTRL_PS_POLL { ok = false; }
  if wireless_header_length(&f) != 16 { ok = false; }
  if wireless_address_count(&f) != 2 { ok = false; }
  if wireless_duration_id(&f) != 320 { ok = false; }
  let ar = wireless_ps_poll_aid(&f);
  if !ar.is_ok { ok = false; } else {
    let aid: Int = ar.value;
    if aid != 320 { ok = false; }
  }
  var w = Vec[UInt8].new();
  push_ctrl_header(&mut w, 12, 0, false);
  let cts = w;
  let rr = wireless_parse(&cts);
  if !rr.is_ok { ok = false; } else {
    let fc: WirelessFrame = rr.value;
    if !err_int_is(wireless_ps_poll_aid(&fc), "wireless: not a ps-poll frame") { ok = false; }
  }
  var d = Vec[UInt8].new();
  push_data_header(&mut d, 0, 0, false);
  let df = wireless_parse(&d);
  if !df.is_ok { ok = false; } else {
    let fd: WirelessFrame = df.value;
    if !err_int_is(wireless_ps_poll_aid(&fd), "wireless: not a ps-poll frame") { ok = false; }
  }
  return assert(ok, "PS-Poll: Duration/ID carries the AID and the AID helper guards");
}

fn main() -> Int {
  io.println("=== xiom.wireless conformance tests ===");
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  let r31 = t31();
  if r31.passed { io.println("  [PASS] " + r31.name); } else { io.println("  [FAIL] " + r31.name); failed = failed + 1; }
  let r32 = t32();
  if r32.passed { io.println("  [PASS] " + r32.name); } else { io.println("  [FAIL] " + r32.name); failed = failed + 1; }
  let r33 = t33();
  if r33.passed { io.println("  [PASS] " + r33.name); } else { io.println("  [FAIL] " + r33.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.wireless: all tests passed");
  } else {
    io.println("xiom.wireless: tests failed");
  }
  return failed;
}
