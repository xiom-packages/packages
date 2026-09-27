// XIOM -- xiom.zigbee conformance tests (26 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pins the documented API against the xiom.zigbee SPEC.md: synthetic frame
// buffers built in-test for every MAC frame type (data, beacon, command,
// acknowledgement), short and extended addressing, PAN ID compression, the
// opaque auxiliary security header, superframe/GTS/pending-address beacon
// fields, the MAC command identifier table, NWK data and command frames
// (multicast, source route, IEEE addresses), APS unicast/broadcast/group/ack
// frames and the extended-header fragmentation bits, every documented error
// (with its byte offset), the frame-type/address/group classification
// helpers, and one cross-layer MAC -> NWK -> APS parse chain.
//
// Str values read from Results go through xiom.string.compare.str_compare
// (BUG 17: `==` on such a Str lowers to a pointer comparison).

module zigbee_tests
use xiom.io; use xiom.test;
use xiom.zigbee;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string (empty on malformed input, so the test
// then fails on the byte comparison).
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

fn empty() -> Vec[UInt8] {
  return Vec[UInt8].new();
}

fn err_mac_is(r: Result[MacFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_nwk_is(r: Result[NwkFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_aps_is(r: Result[ApsFrame, Str], want: Str) -> Bool {
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

// Prefix of a byte vector, for truncation tests.
fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Concatenation of two byte vectors.
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

// The standard MAC data frame reused by several tests: FCF 0x9801 (data,
// destination and source short, version 2006), seq 42, PAN 0x1234 on both
// sides, destination 0x0001, source 0x0002, payload "dead", FCS 0xbeef.
fn mac_data() -> Vec[UInt8] {
  return hb("01982a3412010034120200deadefbe");
}

// --------------------------------------------------
//  MAC tests
// --------------------------------------------------

fn t1() -> TestResult {
  let buf = mac_data();
  let r = mac_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: MacFrame = r.value;
    if mac_frame_type(&f) != 1 { ok = false; }
    if mac_dest_mode(&f) != 2 { ok = false; }
    if mac_src_mode(&f) != 2 { ok = false; }
    if mac_frame_version(&f) != 1 { ok = false; }
    if mac_reserved_bits(&f) != 0 { ok = false; }
    if mac_seq(&f) != 42 { ok = false; }
    if mac_dest_pan(&f) != 4660 { ok = false; }
    if mac_dest_short(&f) != 1 { ok = false; }
    if mac_src_pan(&f) != 4660 { ok = false; }
    if mac_src_short(&f) != 2 { ok = false; }
    if mac_pan_compression(&f) { ok = false; }
    if mac_security_enabled(&f) { ok = false; }
    if mac_frame_pending(&f) { ok = false; }
    if mac_ack_request(&f) { ok = false; }
    if mac_aux_security_present(&f) { ok = false; }
    if mac_aux_security_off(&f) != -1 { ok = false; }
    if mac_header_len(&f) != 11 { ok = false; }
    if mac_payload_off(&f) != 11 { ok = false; }
    if mac_payload_len(&f) != 2 { ok = false; }
    if mac_fcs_off(&f) != 13 { ok = false; }
    if mac_consumed(&f) != 15 { ok = false; }
    let p = mac_payload(&buf, &f);
    if !p.is_ok { ok = false; } else {
      let pv: Vec[UInt8] = p.value;
      if !bytes_equal(pv, hb("dead")) { ok = false; }
    }
    let fv = mac_fcs_value(&buf, &f);
    if !fv.is_ok { ok = false; } else {
      let fvv: Int = fv.value;
      if fvv != 48879 { ok = false; }
    }
    let fb = mac_fcs_bytes(&buf, &f);
    if !fb.is_ok { ok = false; } else {
      let fbv: Vec[UInt8] = fb.value;
      if !bytes_equal(fbv, hb("efbe")) { ok = false; }
    }
  }
  return assert(ok, "MAC data frame with short addressing parses field by field");
}

fn t2() -> TestResult {
  let buf = hb("41982a341201000200deadefbe");
  let r = mac_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: MacFrame = r.value;
    if !mac_pan_compression(&f) { ok = false; }
    if mac_dest_pan(&f) != 4660 { ok = false; }
    if mac_src_pan(&f) != 4660 { ok = false; }
    if mac_dest_short(&f) != 1 { ok = false; }
    if mac_src_short(&f) != 2 { ok = false; }
    if mac_header_len(&f) != 9 { ok = false; }
    if mac_payload_len(&f) != 2 { ok = false; }
    if mac_fcs_off(&f) != 11 { ok = false; }
    if mac_consumed(&f) != 13 { ok = false; }
    let p = mac_payload(&buf, &f);
    if !p.is_ok { ok = false; } else {
      let pv: Vec[UInt8] = p.value;
      if !bytes_equal(pv, hb("dead")) { ok = false; }
    }
  }
  return assert(ok, "PAN ID compression omits the source PAN and echoes the destination PAN");
}

fn t3() -> TestResult {
  let a = hb("019c07341211223344556677883412ffff0000");
  let ra = mac_parse(&a);
  var ok = ra.is_ok;
  if ok {
    let f: MacFrame = ra.value;
    if mac_dest_mode(&f) != 3 { ok = false; }
    if mac_src_mode(&f) != 2 { ok = false; }
    if mac_dest_ext_len(&f) != 8 { ok = false; }
    if mac_dest_ext_byte(&f, 0) != 17 { ok = false; }
    if mac_dest_ext_byte(&f, 7) != 136 { ok = false; }
    if mac_dest_ext_byte(&f, 8) != -1 { ok = false; }
    if mac_src_ext_len(&f) != 0 { ok = false; }
    if mac_src_short(&f) != 65535 { ok = false; }
    if mac_dest_pan(&f) != 4660 { ok = false; }
    if mac_header_len(&f) != 17 { ok = false; }
    if mac_payload_len(&f) != 0 { ok = false; }
    if mac_fcs_off(&f) != 17 { ok = false; }
    if mac_consumed(&f) != 19 { ok = false; }
  }
  let b = hb("01d00834128899aabbccddeeff0000");
  let rb = mac_parse(&b);
  if !rb.is_ok { ok = false; } else {
    let g: MacFrame = rb.value;
    if mac_dest_mode(&g) != 0 { ok = false; }
    if mac_src_mode(&g) != 3 { ok = false; }
    if mac_dest_pan(&g) != -1 { ok = false; }
    if mac_dest_short(&g) != -1 { ok = false; }
    if mac_src_pan(&g) != 4660 { ok = false; }
    if mac_src_ext_len(&g) != 8 { ok = false; }
    if mac_src_ext_byte(&g, 0) != 136 { ok = false; }
    if mac_src_ext_byte(&g, 1) != 153 { ok = false; }
    if mac_src_ext_byte(&g, 7) != 255 { ok = false; }
    if mac_header_len(&g) != 13 { ok = false; }
    if mac_fcs_off(&g) != 13 { ok = false; }
  }
  return assert(ok, "extended 64-bit addresses stay raw bytes and address modes drive the walk");
}

fn t4() -> TestResult {
  let buf = hb("0210010000");
  let r = mac_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: MacFrame = r.value;
    if mac_frame_type(&f) != 2 { ok = false; }
    if mac_seq(&f) != 1 { ok = false; }
    if mac_dest_pan(&f) != -1 { ok = false; }
    if mac_src_pan(&f) != -1 { ok = false; }
    if mac_header_len(&f) != 3 { ok = false; }
    if mac_payload_len(&f) != 0 { ok = false; }
    if mac_fcs_off(&f) != 3 { ok = false; }
    if mac_consumed(&f) != 5 { ok = false; }
  }
  return assert(ok, "acknowledgement frame has a bare 3-byte header and no payload");
}

fn t5() -> TestResult {
  let a = hb("63982a34120100020004abcdefbe");
  let ra = mac_parse(&a);
  var ok = ra.is_ok;
  if ok {
    let f: MacFrame = ra.value;
    if mac_frame_type(&f) != 3 { ok = false; }
    if !mac_pan_compression(&f) { ok = false; }
    if !mac_ack_request(&f) { ok = false; }
    if mac_dest_pan(&f) != 4660 { ok = false; }
    if mac_dest_short(&f) != 1 { ok = false; }
    if mac_src_short(&f) != 2 { ok = false; }
    if mac_command_id(&f) != 4 { ok = false; }
    if mac_command_data_off(&f) != 10 { ok = false; }
    if mac_command_data_len(&f) != 2 { ok = false; }
    if mac_header_len(&f) != 9 { ok = false; }
    if mac_payload_len(&f) != 3 { ok = false; }
  }
  let b = hb("63982a34120100020004efbe");
  let rb = mac_parse(&b);
  if !rb.is_ok { ok = false; } else {
    let g: MacFrame = rb.value;
    if mac_command_id(&g) != 4 { ok = false; }
    if mac_command_data_len(&g) != 0 { ok = false; }
    if mac_payload_len(&g) != 1 { ok = false; }
  }
  if !str_eq(mac_command_name(1), "Association request") { ok = false; }
  if !str_eq(mac_command_name(2), "Association response") { ok = false; }
  if !str_eq(mac_command_name(3), "Disassociation notification") { ok = false; }
  if !str_eq(mac_command_name(4), "Data request") { ok = false; }
  if !str_eq(mac_command_name(5), "PAN ID conflict notification") { ok = false; }
  if !str_eq(mac_command_name(6), "Orphan notification") { ok = false; }
  if !str_eq(mac_command_name(7), "Beacon request") { ok = false; }
  if !str_eq(mac_command_name(8), "Coordinator realignment") { ok = false; }
  if !str_eq(mac_command_name(9), "GTS request") { ok = false; }
  if !str_eq(mac_command_name(10), "Reserved") { ok = false; }
  return assert(ok, "MAC command frames carry the command identifier and a raw data span");
}

fn t6() -> TestResult {
  let buf = hb("00d00f3412010203040506070823d581aa004211bb0010203040506070807a0000");
  let r = mac_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: MacFrame = r.value;
    if mac_frame_type(&f) != 0 { ok = false; }
    if mac_src_mode(&f) != 3 { ok = false; }
    if mac_src_pan(&f) != 4660 { ok = false; }
    if mac_src_ext_byte(&f, 0) != 1 { ok = false; }
    if mac_src_ext_byte(&f, 7) != 8 { ok = false; }
    if mac_beacon_order(&f) != 3 { ok = false; }
    if mac_superframe_order(&f) != 2 { ok = false; }
    if mac_final_cap_slot(&f) != 5 { ok = false; }
    if !mac_battery_life(&f) { ok = false; }
    if !mac_pan_coordinator(&f) { ok = false; }
    if !mac_assoc_permit(&f) { ok = false; }
    if !mac_gts_permit(&f) { ok = false; }
    if mac_gts_count(&f) != 1 { ok = false; }
    if mac_gts_addr(&f, 0) != 170 { ok = false; }
    if mac_gts_start_slot(&f, 0) != 2 { ok = false; }
    if mac_gts_length(&f, 0) != 4 { ok = false; }
    if mac_gts_addr(&f, 1) != -1 { ok = false; }
    if mac_pending_short_count(&f) != 1 { ok = false; }
    if mac_pending_ext_count(&f) != 1 { ok = false; }
    if mac_pending_short(&f, 0) != 187 { ok = false; }
    if mac_pending_short(&f, 1) != -1 { ok = false; }
    if mac_pending_ext_byte(&f, 0, 0) != 16 { ok = false; }
    if mac_pending_ext_byte(&f, 0, 7) != 128 { ok = false; }
    if mac_pending_ext_byte(&f, 0, 8) != -1 { ok = false; }
    if mac_pending_ext_byte(&f, 1, 0) != -1 { ok = false; }
    if mac_beacon_end(&f) != 30 { ok = false; }
    if mac_payload_off(&f) != 13 { ok = false; }
    if mac_payload_len(&f) != 18 { ok = false; }
    if mac_fcs_off(&f) != 31 { ok = false; }
    if mac_consumed(&f) != 33 { ok = false; }
  }
  return assert(ok, "beacon frame parses superframe spec, GTS and pending addresses");
}

fn t7() -> TestResult {
  let buf = hb("08d00f34120102030405060708ff0102030405aa0000");
  let r = mac_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: MacFrame = r.value;
    if mac_frame_type(&f) != 0 { ok = false; }
    if !mac_security_enabled(&f) { ok = false; }
    if !mac_aux_security_present(&f) { ok = false; }
    if mac_aux_security_off(&f) != 13 { ok = false; }
    if mac_payload_off(&f) != 13 { ok = false; }
    if mac_payload_len(&f) != 7 { ok = false; }
    if mac_fcs_off(&f) != 20 { ok = false; }
    if mac_beacon_order(&f) != -1 { ok = false; }
    if mac_command_id(&f) != -1 { ok = false; }
    if mac_src_ext_byte(&f, 0) != 1 { ok = false; }
  }
  return assert(ok, "a secured frame keeps the auxiliary security header opaque");
}

fn t8() -> TestResult {
  var ok = err_mac_is(mac_parse(&hb("0114000000")), "zigbee: bad mac addressing mode at byte 0");
  if !err_mac_is(mac_parse(&hb("0150000000")), "zigbee: bad mac addressing mode at byte 0") { ok = false; }
  if !err_mac_is(mac_parse(&hb("0400000000")), "zigbee: unsupported mac frame type at byte 0") { ok = false; }
  if !err_mac_is(mac_parse(&hb("0500000000")), "zigbee: unsupported mac frame type at byte 0") { ok = false; }
  if !err_mac_is(mac_parse(&hb("0600000000")), "zigbee: unsupported mac frame type at byte 0") { ok = false; }
  if !err_mac_is(mac_parse(&hb("0700000000")), "zigbee: unsupported mac frame type at byte 0") { ok = false; }
  if !err_mac_is(mac_parse(&hb("01990f000000")), "zigbee: mac sequence number suppression unsupported at byte 0") { ok = false; }
  if !err_mac_is(mac_parse(&hb("019a0f000000")), "zigbee: mac information elements unsupported at byte 0") { ok = false; }
  return assert(ok, "reserved frame types, bad addressing modes and 2015 options are rejected");
}

fn t9() -> TestResult {
  let full = mac_data();
  var ok = true;
  var n = 0;
  while n < 13 {
    let cut = prefix(full, n);
    let rr = mac_parse(&cut);
    if rr.is_ok { ok = false; }
    n = n + 1;
  }
  if !mac_parse(&full).is_ok { ok = false; }
  let short13 = prefix(full, 13);
  let r13 = mac_parse(&short13);
  if !r13.is_ok { ok = false; } else {
    let f13: MacFrame = r13.value;
    if mac_payload_len(&f13) != 0 { ok = false; }
  }
  if !err_mac_is(mac_parse(&prefix(full, 0)), "zigbee: truncated mac frame at byte 0") { ok = false; }
  if !err_mac_is(mac_parse(&prefix(full, 2)), "zigbee: truncated mac frame at byte 2") { ok = false; }
  if !err_mac_is(mac_parse(&prefix(full, 4)), "zigbee: truncated mac frame at byte 2") { ok = false; }
  if !err_mac_is(mac_parse(&prefix(full, 5)), "zigbee: truncated mac frame at byte 3") { ok = false; }
  if !err_mac_is(mac_parse(&prefix(full, 11)), "zigbee: truncated mac frame at byte 9") { ok = false; }
  if !err_mac_is(mac_parse(&hb("63982a3412010002000000")), "zigbee: truncated mac command frame at byte 9") { ok = false; }
  return assert(ok, "every truncated MAC header is rejected with its byte offset");
}

fn t10() -> TestResult {
  var ok = err_mac_is(mac_parse(&hb("00d00f3412010203040506070823d5010000")), "zigbee: impossible mac length at byte 16");
  if !err_mac_is(mac_parse(&hb("00d00f3412010203040506070823d500100000")), "zigbee: impossible mac length at byte 17") { ok = false; }
  return assert(ok, "beacon GTS and pending address counts that cannot fit are impossible lengths");
}

fn t11() -> TestResult {
  let buf = mac_data();
  let r = mac_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: MacFrame = r.value;
    if mac_command_id(&f) != -1 { ok = false; }
    if mac_command_data_off(&f) != -1 { ok = false; }
    if mac_command_data_len(&f) != 0 { ok = false; }
    if mac_beacon_order(&f) != -1 { ok = false; }
    if mac_beacon_end(&f) != -1 { ok = false; }
    if mac_gts_count(&f) != 0 { ok = false; }
    if mac_gts_addr(&f, 0) != -1 { ok = false; }
    if mac_gts_start_slot(&f, 0) != -1 { ok = false; }
    if mac_gts_length(&f, 0) != -1 { ok = false; }
    if mac_pending_short_count(&f) != 0 { ok = false; }
    if mac_pending_ext_count(&f) != 0 { ok = false; }
    if mac_dest_ext_len(&f) != 0 { ok = false; }
    if mac_dest_ext_byte(&f, 0) != -1 { ok = false; }
    let short = prefix(buf, 10);
    if !err_bytes_is(mac_payload(&short, &f), "zigbee: mac payload out of bounds at byte 10") { ok = false; }
    if !err_bytes_is(mac_fcs_bytes(&short, &f), "zigbee: mac fcs out of bounds at byte 10") { ok = false; }
  }
  let res = mac_parse(&hb("8110010000"));
  if !res.is_ok { ok = false; } else {
    let g: MacFrame = res.value;
    if mac_reserved_bits(&g) != 1 { ok = false; }
    if mac_frame_type(&g) != 1 { ok = false; }
    if mac_payload_len(&g) != 0 { ok = false; }
  }
  return assert(ok, "non-applicable accessors return -1 and span extraction is bounds-checked");
}

fn t12() -> TestResult {
  var ok = str_eq(mac_frame_type_name(0), "Beacon");
  if !str_eq(mac_frame_type_name(1), "Data") { ok = false; }
  if !str_eq(mac_frame_type_name(2), "Acknowledgement") { ok = false; }
  if !str_eq(mac_frame_type_name(3), "MAC command") { ok = false; }
  if !str_eq(mac_frame_type_name(4), "Reserved") { ok = false; }
  if !str_eq(mac_frame_type_name(5), "Multipurpose") { ok = false; }
  if !str_eq(mac_frame_type_name(6), "Fragment") { ok = false; }
  if !str_eq(mac_frame_type_name(7), "Extended") { ok = false; }
  if !str_eq(mac_frame_type_name(8), "Unknown") { ok = false; }
  if !str_eq(mac_addr_mode_name(0), "None") { ok = false; }
  if !str_eq(mac_addr_mode_name(1), "Reserved") { ok = false; }
  if !str_eq(mac_addr_mode_name(2), "Short") { ok = false; }
  if !str_eq(mac_addr_mode_name(3), "Extended") { ok = false; }
  if !str_eq(mac_addr_mode_name(4), "Unknown") { ok = false; }
  if !str_eq(mac_frame_version_name(0), "2003") { ok = false; }
  if !str_eq(mac_frame_version_name(1), "2006") { ok = false; }
  if !str_eq(mac_frame_version_name(2), "2015") { ok = false; }
  if !str_eq(mac_frame_version_name(3), "Reserved") { ok = false; }
  if !str_eq(mac_frame_version_name(4), "Unknown") { ok = false; }
  if mac_short_class(65535) != 1 { ok = false; }
  if mac_short_class(65534) != 2 { ok = false; }
  if mac_short_class(1) != 0 { ok = false; }
  if mac_short_class(0) != 0 { ok = false; }
  if !str_eq(mac_short_class_name(0), "unicast") { ok = false; }
  if !str_eq(mac_short_class_name(1), "broadcast") { ok = false; }
  if !str_eq(mac_short_class_name(2), "no-address") { ok = false; }
  if !mac_short_is_broadcast(65535) { ok = false; }
  if mac_short_is_broadcast(65534) { ok = false; }
  return assert(ok, "MAC frame type, version, address mode names and short address classes");
}

// --------------------------------------------------
//  NWK tests
// --------------------------------------------------

fn t13() -> TestResult {
  let buf = hb("4800341278560509000106000401012adead");
  let r = nwk_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: NwkFrame = r.value;
    if nwk_frame_type(&f) != 0 { ok = false; }
    if nwk_protocol_version(&f) != 2 { ok = false; }
    if nwk_discover_route(&f) != 1 { ok = false; }
    if nwk_multicast(&f) { ok = false; }
    if nwk_security_enabled(&f) { ok = false; }
    if nwk_source_route(&f) { ok = false; }
    if nwk_dest_ieee_present(&f) { ok = false; }
    if nwk_src_ieee_present(&f) { ok = false; }
    if nwk_end_device_initiator(&f) { ok = false; }
    if nwk_dest(&f) != 4660 { ok = false; }
    if nwk_src(&f) != 22136 { ok = false; }
    if nwk_radius(&f) != 5 { ok = false; }
    if nwk_seq(&f) != 9 { ok = false; }
    if nwk_command_id(&f) != -1 { ok = false; }
    if nwk_header_len(&f) != 8 { ok = false; }
    if nwk_payload_off(&f) != 8 { ok = false; }
    if nwk_payload_len(&f) != 10 { ok = false; }
    if nwk_consumed(&f) != 18 { ok = false; }
    if nwk_multicast_control(&f) != -1 { ok = false; }
    if nwk_multicast_mode(&f) != -1 { ok = false; }
    if nwk_relay_count(&f) != -1 { ok = false; }
    if nwk_relay_index(&f) != -1 { ok = false; }
    if nwk_relay(&f, 0) != -1 { ok = false; }
    let p = nwk_payload(&buf, &f);
    if !p.is_ok { ok = false; } else {
      let pv: Vec[UInt8] = p.value;
      if !bytes_equal(pv, hb("000106000401012adead")) { ok = false; }
    }
  }
  return assert(ok, "NWK data frame parses frame control, addresses, radius and sequence");
}

fn t14() -> TestResult {
  let buf = hb("493dcdab0100072b08070605040302018877665544332211a902111122220101ccdd");
  let r = nwk_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: NwkFrame = r.value;
    if nwk_frame_type(&f) != 1 { ok = false; }
    if nwk_protocol_version(&f) != 2 { ok = false; }
    if nwk_discover_route(&f) != 1 { ok = false; }
    if !nwk_multicast(&f) { ok = false; }
    if !nwk_source_route(&f) { ok = false; }
    if !nwk_dest_ieee_present(&f) { ok = false; }
    if !nwk_src_ieee_present(&f) { ok = false; }
    if !nwk_end_device_initiator(&f) { ok = false; }
    if nwk_dest(&f) != 43981 { ok = false; }
    if nwk_src(&f) != 1 { ok = false; }
    if nwk_radius(&f) != 7 { ok = false; }
    if nwk_seq(&f) != 43 { ok = false; }
    if nwk_dest_ext_len(&f) != 8 { ok = false; }
    if nwk_dest_ext_byte(&f, 0) != 8 { ok = false; }
    if nwk_dest_ext_byte(&f, 7) != 1 { ok = false; }
    if nwk_src_ext_len(&f) != 8 { ok = false; }
    if nwk_src_ext_byte(&f, 0) != 136 { ok = false; }
    if nwk_src_ext_byte(&f, 7) != 17 { ok = false; }
    if nwk_multicast_control(&f) != 169 { ok = false; }
    if nwk_multicast_mode(&f) != 1 { ok = false; }
    if nwk_multicast_radius(&f) != 2 { ok = false; }
    if nwk_multicast_max_radius(&f) != 5 { ok = false; }
    if nwk_relay_count(&f) != 2 { ok = false; }
    if nwk_relay(&f, 0) != 4369 { ok = false; }
    if nwk_relay(&f, 1) != 8738 { ok = false; }
    if nwk_relay(&f, 2) != -1 { ok = false; }
    if nwk_relay_index(&f) != 1 { ok = false; }
    if nwk_command_id(&f) != 1 { ok = false; }
    if nwk_header_len(&f) != 31 { ok = false; }
    if nwk_payload_len(&f) != 3 { ok = false; }
    if nwk_consumed(&f) != 34 { ok = false; }
  }
  return assert(ok, "NWK command frame with IEEE addresses, multicast and source route subframe");
}

fn t15() -> TestResult {
  var ok = err_nwk_is(nwk_parse(&hb("0200341278560509")), "zigbee: unsupported nwk frame type at byte 0");
  if !err_nwk_is(nwk_parse(&hb("0300341278560509")), "zigbee: unsupported nwk frame type at byte 0") { ok = false; }
  if !err_nwk_is(nwk_parse(&hb("")), "zigbee: truncated nwk frame at byte 0") { ok = false; }
  if !err_nwk_is(nwk_parse(&hb("48")), "zigbee: truncated nwk frame at byte 1") { ok = false; }
  if !err_nwk_is(nwk_parse(&hb("080434127856050902")), "zigbee: impossible nwk length at byte 9") { ok = false; }
  if !err_nwk_is(nwk_parse(&hb("0900341278560509")), "zigbee: truncated nwk command at byte 8") { ok = false; }
  let full = hb("4800341278560509000106000401012adead");
  var n = 0;
  while n < 8 {
    let cut = prefix(full, n);
    let rr = nwk_parse(&cut);
    if rr.is_ok { ok = false; }
    n = n + 1;
  }
  if !nwk_parse(&full).is_ok { ok = false; }
  return assert(ok, "NWK rejects reserved types, truncation, bad relay counts and missing command ids");
}

fn t16() -> TestResult {
  var ok = str_eq(nwk_frame_type_name(0), "Data");
  if !str_eq(nwk_frame_type_name(1), "NWK command") { ok = false; }
  if !str_eq(nwk_frame_type_name(2), "Reserved") { ok = false; }
  if !str_eq(nwk_frame_type_name(3), "Inter-PAN") { ok = false; }
  if !str_eq(nwk_command_name(1), "Route request") { ok = false; }
  if !str_eq(nwk_command_name(2), "Route reply") { ok = false; }
  if !str_eq(nwk_command_name(3), "Network status") { ok = false; }
  if !str_eq(nwk_command_name(4), "Leave") { ok = false; }
  if !str_eq(nwk_command_name(5), "Route record") { ok = false; }
  if !str_eq(nwk_command_name(6), "Rejoin request") { ok = false; }
  if !str_eq(nwk_command_name(7), "Rejoin response") { ok = false; }
  if !str_eq(nwk_command_name(8), "Link status") { ok = false; }
  if !str_eq(nwk_command_name(9), "Network report") { ok = false; }
  if !str_eq(nwk_command_name(10), "Network update") { ok = false; }
  if !str_eq(nwk_command_name(11), "End device timeout request") { ok = false; }
  if !str_eq(nwk_command_name(12), "End device timeout response") { ok = false; }
  if !str_eq(nwk_command_name(13), "Link power delta") { ok = false; }
  if !str_eq(nwk_command_name(14), "Commissioning request") { ok = false; }
  if !str_eq(nwk_command_name(15), "Commissioning response") { ok = false; }
  if !str_eq(nwk_command_name(16), "Reserved") { ok = false; }
  if nwk_addr_class(65535) != 1 { ok = false; }
  if nwk_addr_class(65533) != 4 { ok = false; }
  if nwk_addr_class(65532) != 3 { ok = false; }
  if nwk_addr_class(65531) != 2 { ok = false; }
  if nwk_addr_class(65534) != 5 { ok = false; }
  if nwk_addr_class(65528) != 5 { ok = false; }
  if nwk_addr_class(4660) != 0 { ok = false; }
  if !str_eq(nwk_addr_class_name(0), "unicast") { ok = false; }
  if !str_eq(nwk_addr_class_name(1), "broadcast to all devices") { ok = false; }
  if !str_eq(nwk_addr_class_name(2), "broadcast to low-power routers") { ok = false; }
  if !str_eq(nwk_addr_class_name(3), "broadcast to routers") { ok = false; }
  if !str_eq(nwk_addr_class_name(4), "broadcast to rx-on devices") { ok = false; }
  if !str_eq(nwk_addr_class_name(5), "reserved broadcast") { ok = false; }
  if !nwk_is_broadcast(65535) { ok = false; }
  if nwk_is_broadcast(65534) { ok = false; }
  return assert(ok, "NWK frame type and command names plus broadcast address classification");
}

fn t17() -> TestResult {
  let buf = hb("4800341278560509000106000401012adead");
  let r = nwk_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: NwkFrame = r.value;
    let short = prefix(buf, 9);
    if !err_bytes_is(nwk_payload(&short, &f), "zigbee: nwk payload out of bounds at byte 9") { ok = false; }
  }
  let sec = hb("0902341278560509aabb");
  let rs = nwk_parse(&sec);
  if !rs.is_ok { ok = false; } else {
    let g: NwkFrame = rs.value;
    if !nwk_security_enabled(&g) { ok = false; }
    if nwk_command_id(&g) != -1 { ok = false; }
    if nwk_payload_len(&g) != 2 { ok = false; }
    if nwk_header_len(&g) != 8 { ok = false; }
  }
  return assert(ok, "NWK payload extraction is bounds-checked and secured command ids stay opaque");
}

// --------------------------------------------------
//  APS tests
// --------------------------------------------------

fn t18() -> TestResult {
  let buf = hb("000106000401012adead");
  let r = aps_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: ApsFrame = r.value;
    if aps_frame_type(&f) != 0 { ok = false; }
    if aps_delivery_mode(&f) != 0 { ok = false; }
    if aps_ack_format(&f) { ok = false; }
    if aps_security_enabled(&f) { ok = false; }
    if aps_ack_request(&f) { ok = false; }
    if aps_ext_header_present(&f) { ok = false; }
    if aps_dest_endpoint(&f) != 1 { ok = false; }
    if aps_group_addr(&f) != -1 { ok = false; }
    if aps_cluster_id(&f) != 6 { ok = false; }
    if aps_profile_id(&f) != 260 { ok = false; }
    if aps_src_endpoint(&f) != 1 { ok = false; }
    if aps_counter(&f) != 42 { ok = false; }
    if aps_ext_frag_bits(&f) != -1 { ok = false; }
    if aps_ext_block(&f) != -1 { ok = false; }
    if aps_header_len(&f) != 8 { ok = false; }
    if aps_payload_off(&f) != 8 { ok = false; }
    if aps_payload_len(&f) != 2 { ok = false; }
    if aps_consumed(&f) != 10 { ok = false; }
    let p = aps_payload(&buf, &f);
    if !p.is_ok { ok = false; } else {
      let pv: Vec[UInt8] = p.value;
      if !bytes_equal(pv, hb("dead")) { ok = false; }
    }
  }
  return assert(ok, "APS unicast data frame parses endpoints, cluster, profile and counter");
}

fn t19() -> TestResult {
  let buf = hb("0413000000012bbeef");
  let r = aps_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: ApsFrame = r.value;
    if aps_delivery_mode(&f) != 1 { ok = false; }
    if aps_dest_endpoint(&f) != -1 { ok = false; }
    if aps_group_addr(&f) != -1 { ok = false; }
    if aps_cluster_id(&f) != 19 { ok = false; }
    if aps_profile_id(&f) != 0 { ok = false; }
    if aps_src_endpoint(&f) != 1 { ok = false; }
    if aps_counter(&f) != 43 { ok = false; }
    if aps_header_len(&f) != 7 { ok = false; }
    if aps_payload_len(&f) != 2 { ok = false; }
    if aps_consumed(&f) != 9 { ok = false; }
  }
  return assert(ok, "APS broadcast frame omits the destination endpoint and keeps the source");
}

fn t20() -> TestResult {
  let buf = hb("080a0006000401012ccafe");
  let r = aps_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: ApsFrame = r.value;
    if aps_delivery_mode(&f) != 2 { ok = false; }
    if aps_dest_endpoint(&f) != -1 { ok = false; }
    if aps_group_addr(&f) != 10 { ok = false; }
    if aps_cluster_id(&f) != 6 { ok = false; }
    if aps_profile_id(&f) != 260 { ok = false; }
    if aps_src_endpoint(&f) != 1 { ok = false; }
    if aps_counter(&f) != 44 { ok = false; }
    if aps_header_len(&f) != 9 { ok = false; }
    if aps_payload_len(&f) != 2 { ok = false; }
  }
  return assert(ok, "APS group frame carries the group address before cluster and profile");
}

fn t21() -> TestResult {
  let buf = hb("02012a");
  let r = aps_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: ApsFrame = r.value;
    if aps_frame_type(&f) != 2 { ok = false; }
    if aps_dest_endpoint(&f) != 1 { ok = false; }
    if aps_cluster_id(&f) != -1 { ok = false; }
    if aps_profile_id(&f) != -1 { ok = false; }
    if aps_src_endpoint(&f) != -1 { ok = false; }
    if aps_counter(&f) != 42 { ok = false; }
    if aps_header_len(&f) != 3 { ok = false; }
    if aps_payload_len(&f) != 0 { ok = false; }
    if aps_consumed(&f) != 3 { ok = false; }
  }
  return assert(ok, "APS acknowledgement frame is frame control, endpoint and counter only");
}

fn t22() -> TestResult {
  let buf = hb("700106000401012aff");
  let r = aps_parse(&buf);
  var ok = r.is_ok;
  if ok {
    let f: ApsFrame = r.value;
    if aps_frame_type(&f) != 0 { ok = false; }
    if aps_delivery_mode(&f) != 0 { ok = false; }
    if !aps_ack_format(&f) { ok = false; }
    if !aps_security_enabled(&f) { ok = false; }
    if !aps_ack_request(&f) { ok = false; }
    if aps_ext_header_present(&f) { ok = false; }
    if aps_dest_endpoint(&f) != 1 { ok = false; }
    if aps_cluster_id(&f) != 6 { ok = false; }
    if aps_src_endpoint(&f) != 1 { ok = false; }
    if aps_counter(&f) != 42 { ok = false; }
    if aps_header_len(&f) != 8 { ok = false; }
    if aps_payload_len(&f) != 1 { ok = false; }
  }
  return assert(ok, "APS frame control flags (ack format, security, ack request) are decoded");
}

fn t23() -> TestResult {
  let a = hb("800106000401012a0207dead");
  let ra = aps_parse(&a);
  var ok = ra.is_ok;
  if ok {
    let f: ApsFrame = ra.value;
    if !aps_ext_header_present(&f) { ok = false; }
    if aps_ext_frag_bits(&f) != 2 { ok = false; }
    if aps_ext_block(&f) != 7 { ok = false; }
    if aps_header_len(&f) != 10 { ok = false; }
    if aps_payload_len(&f) != 2 { ok = false; }
  }
  let b = hb("800106000401012a00de");
  let rb = aps_parse(&b);
  if !rb.is_ok { ok = false; } else {
    let g: ApsFrame = rb.value;
    if !aps_ext_header_present(&g) { ok = false; }
    if aps_ext_frag_bits(&g) != 0 { ok = false; }
    if aps_ext_block(&g) != -1 { ok = false; }
    if aps_header_len(&g) != 9 { ok = false; }
    if aps_payload_len(&g) != 1 { ok = false; }
  }
  return assert(ok, "APS extended header fragmentation bits and block number are decoded");
}

fn t24() -> TestResult {
  var ok = err_aps_is(aps_parse(&hb("")), "zigbee: truncated aps frame at byte 0");
  if !err_aps_is(aps_parse(&hb("03")), "zigbee: unsupported aps frame type at byte 0") { ok = false; }
  if !err_aps_is(aps_parse(&hb("0c")), "zigbee: bad aps delivery mode at byte 0") { ok = false; }
  if !err_aps_is(aps_parse(&hb("00")), "zigbee: truncated aps frame at byte 1") { ok = false; }
  if !err_aps_is(aps_parse(&hb("800106000401012a")), "zigbee: truncated aps extended header at byte 8") { ok = false; }
  if !err_aps_is(aps_parse(&hb("800106000401012a02")), "zigbee: truncated aps extended header at byte 9") { ok = false; }
  let full = hb("000106000401012adead");
  var n = 0;
  while n < 8 {
    let cut = prefix(full, n);
    let rr = aps_parse(&cut);
    if rr.is_ok { ok = false; }
    n = n + 1;
  }
  if !aps_parse(&full).is_ok { ok = false; }
  let r = aps_parse(&full);
  if r.is_ok {
    let f: ApsFrame = r.value;
    let short = prefix(full, 8);
    if !err_bytes_is(aps_payload(&short, &f), "zigbee: aps payload out of bounds at byte 8") { ok = false; }
  } else {
    ok = false;
  }
  return assert(ok, "APS rejects reserved types, reserved delivery, truncation and bad spans");
}

fn t25() -> TestResult {
  var ok = str_eq(aps_frame_type_name(0), "Data");
  if !str_eq(aps_frame_type_name(1), "Command") { ok = false; }
  if !str_eq(aps_frame_type_name(2), "Acknowledgement") { ok = false; }
  if !str_eq(aps_frame_type_name(3), "Inter-PAN") { ok = false; }
  if !str_eq(aps_frame_type_name(4), "Unknown") { ok = false; }
  if !str_eq(aps_delivery_name(0), "Unicast") { ok = false; }
  if !str_eq(aps_delivery_name(1), "Broadcast") { ok = false; }
  if !str_eq(aps_delivery_name(2), "Group") { ok = false; }
  if !str_eq(aps_delivery_name(3), "Reserved") { ok = false; }
  if !str_eq(aps_delivery_name(4), "Unknown") { ok = false; }
  if aps_group_class(0) != 0 { ok = false; }
  if aps_group_class(1) != 1 { ok = false; }
  if aps_group_class(65527) != 1 { ok = false; }
  if aps_group_class(65528) != 2 { ok = false; }
  if aps_group_class(65535) != 3 { ok = false; }
  if aps_group_class(-1) != 4 { ok = false; }
  if aps_group_class(65536) != 4 { ok = false; }
  if !str_eq(aps_group_class_name(0), "reserved") { ok = false; }
  if !str_eq(aps_group_class_name(1), "group") { ok = false; }
  if !str_eq(aps_group_class_name(2), "reserved range") { ok = false; }
  if !str_eq(aps_group_class_name(3), "broadcast group") { ok = false; }
  if !str_eq(aps_group_class_name(4), "out of range") { ok = false; }
  return assert(ok, "APS frame type and delivery names plus group address classification");
}

fn t26() -> TestResult {
  let buf = hb("4198333412010002004800341278560509000106000401012adeadefbe");
  let mr = mac_parse(&buf);
  var ok = mr.is_ok;
  if ok {
    let m: MacFrame = mr.value;
    if mac_frame_type(&m) != 1 { ok = false; }
    if mac_seq(&m) != 51 { ok = false; }
    if !mac_pan_compression(&m) { ok = false; }
    if mac_dest_short(&m) != 1 { ok = false; }
    if mac_src_short(&m) != 2 { ok = false; }
    if mac_payload_off(&m) != 9 { ok = false; }
    if mac_payload_len(&m) != 18 { ok = false; }
    if mac_fcs_off(&m) != 27 { ok = false; }
    if mac_consumed(&m) != 29 { ok = false; }
    let mp = mac_payload(&buf, &m);
    if !mp.is_ok { ok = false; } else {
      let nwkbuf: Vec[UInt8] = mp.value;
      if !bytes_equal(nwkbuf, hb("4800341278560509000106000401012adead")) { ok = false; }
      let nr = nwk_parse(&nwkbuf);
      if !nr.is_ok { ok = false; } else {
        let nwf: NwkFrame = nr.value;
        if nwk_dest(&nwf) != 4660 { ok = false; }
        if nwk_src(&nwf) != 22136 { ok = false; }
        if nwk_payload_off(&nwf) != 8 { ok = false; }
        if nwk_payload_len(&nwf) != 10 { ok = false; }
        let np = nwk_payload(&nwkbuf, &nwf);
        if !np.is_ok { ok = false; } else {
          let apsbuf: Vec[UInt8] = np.value;
          if !bytes_equal(apsbuf, hb("000106000401012adead")) { ok = false; }
          let ar = aps_parse(&apsbuf);
          if !ar.is_ok { ok = false; } else {
            let af: ApsFrame = ar.value;
            if aps_dest_endpoint(&af) != 1 { ok = false; }
            if aps_cluster_id(&af) != 6 { ok = false; }
            if aps_profile_id(&af) != 260 { ok = false; }
            if aps_counter(&af) != 42 { ok = false; }
            if aps_payload_off(&af) != 8 { ok = false; }
            if aps_payload_len(&af) != 2 { ok = false; }
            let ap = aps_payload(&apsbuf, &af);
            if !ap.is_ok { ok = false; } else {
              let apv: Vec[UInt8] = ap.value;
              if !bytes_equal(apv, hb("dead")) { ok = false; }
            }
          }
        }
      }
    }
    let fv = mac_fcs_value(&buf, &m);
    if !fv.is_ok { ok = false; } else {
      let fvv: Int = fv.value;
      if fvv != 48879 { ok = false; }
    }
  }
  return assert(ok, "MAC payload carries a NWK payload that carries an APS payload");
}

// --------------------------------------------------
//  Runner
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.zigbee conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.zigbee: all tests passed");
  } else {
    io.println("xiom.zigbee: tests failed");
  }
  return failed;
}
