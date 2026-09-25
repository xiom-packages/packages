// XIOM -- xiom.ble conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: hand-built advertising payloads with pinned
// types/offsets/lengths, unknown AD type preservation, empty and lone-type
// structures, the zero-length / truncated / overrun error catalog, every
// typed builder (flags, names, TX power, 16/32/128-bit UUIDs, slave
// interval range, service data, manufacturer data) with exact bytes and
// range errors, the typed data decoders, generic ble_ad / ble_append_ad /
// ble_build_from behavior (including atomic failure), the 31-byte legacy
// limit in ble_validate, accessor bounds, and a full build -> parse ->
// rebuild round-trip.
//
// Str values are never compared with `==` (BUG 17 discipline: `==` on a Str
// read from a Vec lowers to a pointer comparison); error messages go through
// compare.str_compare.

module ble_tests
use xiom.io; use xiom.test;
use xiom.ble;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

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

fn seq_byte(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push((i % 256) as UInt8);
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

// Prefix of a byte vector, used to build short source buffers.
fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Bytes [start, end) of a byte vector (callers guarantee the bounds).
fn slice_of(v: Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn ints2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_list_is(r: Result[AdList, Str], want: Str) -> Bool {
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

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_ints_is(r: Result[Vec[Int], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn ok_bytes_is(r: Result[Vec[UInt8], Str], want: Vec[UInt8]) -> Bool {
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

fn ints_are(r: Result[Vec[Int], Str], want: Vec[Int]) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Vec[Int] = r.value;
  if v.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < v.len() {
    let a: Int = v[i];
    let b: Int = want[i];
    if a != b {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn data_is(data: &Vec[UInt8], l: &AdList, i: Int, want: Vec[UInt8]) -> Bool {
  let r = ble_data(data, l, i);
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  return bytes_equal(v, want);
}

// Typed decoder shims: always bind the hex bytes to a local first (taking a
// reference to a temporary is not portable in this compiler).
fn dec_flags(hexstr: Str) -> Result[Int, Str] {
  let v = hb(hexstr);
  return ble_decode_flags(&v);
}

fn dec_tx(hexstr: Str) -> Result[Int, Str] {
  let v = hb(hexstr);
  return ble_decode_tx_power(&v);
}

fn dec_uuid16(hexstr: Str) -> Result[Int, Str] {
  let v = hb(hexstr);
  return ble_decode_uuid16(&v);
}

fn dec_uuid32(hexstr: Str) -> Result[Int, Str] {
  let v = hb(hexstr);
  return ble_decode_uuid32(&v);
}

fn dec_manu(hexstr: Str) -> Result[Int, Str] {
  let v = hb(hexstr);
  return ble_decode_manufacturer_id(&v);
}

fn dec_interval(hexstr: Str) -> Result[Vec[Int], Str] {
  let v = hb(hexstr);
  return ble_decode_slave_interval(&v);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = hb("02010603094142020afc03030d18");
  let r = ble_parse(&data);
  if !r.is_ok { return assert(false, "valid payload must parse"); }
  let l: AdList = r.value;
  var ok = ble_count(&l) == 4;
  if ble_type(&l, 0) != 1 { ok = false; }
  if ble_type(&l, 1) != 9 { ok = false; }
  if ble_type(&l, 2) != 10 { ok = false; }
  if ble_type(&l, 3) != 3 { ok = false; }
  let o0: Int = l.data_offsets[0];
  let o1: Int = l.data_offsets[1];
  let o2: Int = l.data_offsets[2];
  let o3: Int = l.data_offsets[3];
  let n0: Int = l.data_lengths[0];
  let n1: Int = l.data_lengths[1];
  let n2: Int = l.data_lengths[2];
  let n3: Int = l.data_lengths[3];
  if o0 != 2 { ok = false; }
  if o1 != 5 { ok = false; }
  if o2 != 9 { ok = false; }
  if o3 != 12 { ok = false; }
  if n0 != 1 { ok = false; }
  if n1 != 2 { ok = false; }
  if n2 != 1 { ok = false; }
  if n3 != 2 { ok = false; }
  if !data_is(&data, &l, 0, hb("06")) { ok = false; }
  if !data_is(&data, &l, 1, hb("4142")) { ok = false; }
  if !data_is(&data, &l, 2, hb("fc")) { ok = false; }
  if !data_is(&data, &l, 3, hb("0d18")) { ok = false; }
  if ble_ad_size(&l, 0) != 3 { ok = false; }
  if ble_ad_size(&l, 1) != 4 { ok = false; }
  if ble_ad_size(&l, 2) != 3 { ok = false; }
  if ble_ad_size(&l, 3) != 4 { ok = false; }
  if ble_total_length(&l) != 14 { ok = false; }
  return assert(ok, "four-entry payload: pinned types, offsets, lengths and data");
}

fn t2() -> TestResult {
  let data = hb("0455deadbe02aa01033d0000");
  let r = ble_parse(&data);
  if !r.is_ok { return assert(false, "unknown-type payload must parse"); }
  let l: AdList = r.value;
  var ok = ble_count(&l) == 3;
  if ble_type(&l, 0) != 85 { ok = false; }
  if ble_type(&l, 1) != 170 { ok = false; }
  if ble_type(&l, 2) != 61 { ok = false; }
  if !data_is(&data, &l, 0, hb("deadbe")) { ok = false; }
  if !data_is(&data, &l, 1, hb("01")) { ok = false; }
  if !data_is(&data, &l, 2, hb("0000")) { ok = false; }
  if ble_find(&l, 85) != 0 { ok = false; }
  if ble_find(&l, 170) != 1 { ok = false; }
  if ble_find(&l, 61) != 2 { ok = false; }
  if ble_find(&l, 1) != -1 { ok = false; }
  if !ble_has(&l, 85) { ok = false; }
  if ble_has(&l, 1) { ok = false; }
  return assert(ok, "unknown AD types 0x55/0xaa/0x3d are preserved and searchable");
}

fn t3() -> TestResult {
  var empty = Vec[UInt8].new();
  let r = ble_parse(&empty);
  if !r.is_ok { return assert(false, "empty buffer must parse"); }
  let l: AdList = r.value;
  var ok = ble_count(&l) == 0;
  if ble_type(&l, 0) != -1 { ok = false; }
  if ble_type(&l, -1) != -1 { ok = false; }
  if ble_ad_size(&l, 0) != -1 { ok = false; }
  if ble_ad_size(&l, -1) != -1 { ok = false; }
  if ble_total_length(&l) != 0 { ok = false; }
  if ble_find(&l, 1) != -1 { ok = false; }
  if ble_has(&l, 1) { ok = false; }
  if !err_bytes_is(ble_data(&empty, &l, 0), "ble: index out of range") { ok = false; }
  if !err_bytes_is(ble_data(&empty, &l, -1), "ble: index out of range") { ok = false; }
  return assert(ok, "empty buffer yields zero entries and out-of-range accessors");
}

fn t4() -> TestResult {
  let a = hb("02010600");
  let b = hb("00");
  let c = hb("010600");
  var ok = err_list_is(ble_parse(&a), "ble: zero-length AD structure");
  if !err_list_is(ble_parse(&b), "ble: zero-length AD structure") { ok = false; }
  if !err_list_is(ble_parse(&c), "ble: zero-length AD structure") { ok = false; }
  return assert(ok, "a zero length byte is Err(ble: zero-length AD structure)");
}

fn t5() -> TestResult {
  let a = hb("0501");
  let b = hb("030941");
  let c = hb("0201060501");
  var ok = err_list_is(ble_parse(&a), "ble: AD length overruns buffer");
  if !err_list_is(ble_parse(&b), "ble: AD length overruns buffer") { ok = false; }
  if !err_list_is(ble_parse(&c), "ble: AD length overruns buffer") { ok = false; }
  return assert(ok, "declared lengths that exceed the remaining bytes are Err");
}

fn t6() -> TestResult {
  let a = hb("01");
  let b = hb("02010603");
  let c = hb("0201060309");
  var ok = err_list_is(ble_parse(&a), "ble: truncated AD structure");
  if !err_list_is(ble_parse(&b), "ble: truncated AD structure") { ok = false; }
  if !err_list_is(ble_parse(&c), "ble: AD length overruns buffer") { ok = false; }
  return assert(ok, "a dangling length byte is truncated; a lone type byte overruns");
}

fn t7() -> TestResult {
  let data = hb("0106");
  let r = ble_parse(&data);
  if !r.is_ok { return assert(false, "lone length+type must parse"); }
  let l: AdList = r.value;
  var ok = ble_count(&l) == 1;
  if ble_type(&l, 0) != 6 { ok = false; }
  if !data_is(&data, &l, 0, Vec[UInt8].new()) { ok = false; }
  if ble_ad_size(&l, 0) != 2 { ok = false; }
  if ble_total_length(&l) != 2 { ok = false; }
  if !err_int_is(dec_flags(""), "ble: wrong data length") { ok = false; }
  return assert(ok, "a length-1 structure is valid with empty data");
}

fn t8() -> TestResult {
  var ok = ok_bytes_is(ble_ad_flags(0), hb("020100"));
  if !ok_bytes_is(ble_ad_flags(6), hb("020106")) { ok = false; }
  if !ok_bytes_is(ble_ad_flags(255), hb("0201ff")) { ok = false; }
  if !err_bytes_is(ble_ad_flags(256), "ble: flags out of range") { ok = false; }
  if !err_bytes_is(ble_ad_flags(-1), "ble: flags out of range") { ok = false; }
  let built = ble_ad_flags(6);
  if !built.is_ok { return assert(false, "flags build must succeed"); }
  let b: Vec[UInt8] = built.value;
  let pr = ble_parse(&b);
  if !pr.is_ok { ok = false; } else {
    let l: AdList = pr.value;
    if ble_count(&l) != 1 { ok = false; }
    if ble_type(&l, 0) != 1 { ok = false; }
    let p = ble_data(&b, &l, 0);
    if !p.is_ok { ok = false; } else {
      let pv: Vec[UInt8] = p.value;
      if !int_is(ble_decode_flags(&pv), 6) { ok = false; }
    }
  }
  return assert(ok, "flags: exact bytes, range errors and decode round-trip");
}

fn t9() -> TestResult {
  var ok = ok_bytes_is(ble_ad_name_short("AB"), hb("03084142"));
  if !ok_bytes_is(ble_ad_name_complete("AB"), hb("03094142")) { ok = false; }
  if !err_bytes_is(ble_ad_name_complete(""), "ble: empty local name") { ok = false; }
  if !err_bytes_is(ble_ad_name_short(""), "ble: empty local name") { ok = false; }
  let n254 = string.str_repeat("a", 254);
  let r254 = ble_ad_name_complete(n254);
  if !r254.is_ok { ok = false; } else {
    let b: Vec[UInt8] = r254.value;
    if b.len() != 256 { ok = false; }
    if ((b[0] as Int) & 0xFF) != 255 { ok = false; }
    if ((b[1] as Int) & 0xFF) != 9 { ok = false; }
  }
  let n255 = string.str_repeat("a", 255);
  if !err_bytes_is(ble_ad_name_complete(n255), "ble: name too long") { ok = false; }
  let built = ble_ad_name_complete("AB");
  if !built.is_ok { return assert(false, "name build must succeed"); }
  let b2: Vec[UInt8] = built.value;
  let pr = ble_parse(&b2);
  if !pr.is_ok { ok = false; } else {
    let l: AdList = pr.value;
    if !data_is(&b2, &l, 0, hb("4142")) { ok = false; }
  }
  return assert(ok, "names: 0x09/0x08 bytes, empty and 254/255-byte limits");
}

fn t10() -> TestResult {
  var ok = ok_bytes_is(ble_ad_tx_power(-4), hb("020afc"));
  if !ok_bytes_is(ble_ad_tx_power(127), hb("020a7f")) { ok = false; }
  if !ok_bytes_is(ble_ad_tx_power(-128), hb("020a80")) { ok = false; }
  if !err_bytes_is(ble_ad_tx_power(128), "ble: TX power out of range") { ok = false; }
  if !err_bytes_is(ble_ad_tx_power(-129), "ble: TX power out of range") { ok = false; }
  if !int_is(dec_tx("fc"), -4) { ok = false; }
  if !int_is(dec_tx("7f"), 127) { ok = false; }
  if !int_is(dec_tx("80"), -128) { ok = false; }
  if !int_is(dec_tx("00"), 0) { ok = false; }
  if !err_int_is(dec_tx(""), "ble: wrong data length") { ok = false; }
  if !err_int_is(dec_tx("0000"), "ble: wrong data length") { ok = false; }
  return assert(ok, "TX power: signed 1-byte encode/decode and range errors");
}

fn t11() -> TestResult {
  var ok = ok_bytes_is(ble_ad_service_uuid16(6157, true), hb("03030d18"));
  if !ok_bytes_is(ble_ad_service_uuid16(6157, false), hb("03020d18")) { ok = false; }
  if !ok_bytes_is(ble_ad_service_uuid16(0, true), hb("03030000")) { ok = false; }
  if !ok_bytes_is(ble_ad_service_uuid16(65535, true), hb("0303ffff")) { ok = false; }
  if !int_is(dec_uuid16("0d18"), 6157) { ok = false; }
  if !int_is(dec_uuid16("0000"), 0) { ok = false; }
  if !int_is(dec_uuid16("ffff"), 65535) { ok = false; }
  if !err_bytes_is(ble_ad_service_uuid16(65536, true), "ble: UUID out of range") { ok = false; }
  if !err_bytes_is(ble_ad_service_uuid16(-1, true), "ble: UUID out of range") { ok = false; }
  if !err_int_is(dec_uuid16("0d"), "ble: wrong data length") { ok = false; }
  return assert(ok, "16-bit UUIDs: complete/incomplete bytes, LE decode, range errors");
}

fn t12() -> TestResult {
  var ok = ok_bytes_is(ble_ad_service_uuid32(305419896, true), hb("050578563412"));
  if !ok_bytes_is(ble_ad_service_uuid32(305419896, false), hb("050478563412")) { ok = false; }
  if !ok_bytes_is(ble_ad_service_uuid32(4294967295, true), hb("0505ffffffff")) { ok = false; }
  if !int_is(dec_uuid32("78563412"), 305419896) { ok = false; }
  if !int_is(dec_uuid32("ffffffff"), 4294967295) { ok = false; }
  if !err_bytes_is(ble_ad_service_uuid32(4294967296, true), "ble: UUID out of range") { ok = false; }
  if !err_bytes_is(ble_ad_service_uuid32(-1, false), "ble: UUID out of range") { ok = false; }
  if !err_int_is(dec_uuid32("785634"), "ble: wrong data length") { ok = false; }
  return assert(ok, "32-bit UUIDs: complete/incomplete bytes, LE decode, range errors");
}

fn t13() -> TestResult {
  let u = seq_byte(16);
  let u15 = seq_byte(15);
  let u17 = seq_byte(17);
  let want_complete = hb("1107000102030405060708090a0b0c0d0e0f");
  let want_incomplete = hb("1106000102030405060708090a0b0c0d0e0f");
  var ok = ok_bytes_is(ble_ad_service_uuid128(&u, true), want_complete);
  if !ok_bytes_is(ble_ad_service_uuid128(&u, false), want_incomplete) { ok = false; }
  if !err_bytes_is(ble_ad_service_uuid128(&u15, true), "ble: 128-bit UUID must be 16 bytes") { ok = false; }
  if !err_bytes_is(ble_ad_service_uuid128(&u17, true), "ble: 128-bit UUID must be 16 bytes") { ok = false; }
  let built = ble_ad_service_uuid128(&u, true);
  if !built.is_ok { return assert(false, "uuid128 build must succeed"); }
  let b: Vec[UInt8] = built.value;
  if b.len() != 18 { ok = false; }
  let pr = ble_parse(&b);
  if !pr.is_ok { ok = false; } else {
    let l: AdList = pr.value;
    if ble_count(&l) != 1 { ok = false; }
    if ble_type(&l, 0) != 7 { ok = false; }
    if !data_is(&b, &l, 0, u) { ok = false; }
  }
  return assert(ok, "128-bit UUIDs: 16 verbatim bytes, 0x06/0x07, exact-length error");
}

fn t14() -> TestResult {
  var ok = ok_bytes_is(ble_ad_slave_interval(6, 12), hb("051206000c00"));
  if !ok_bytes_is(ble_ad_slave_interval(3200, 3200), hb("0512800c800c")) { ok = false; }
  if !ints_are(dec_interval("06000c00"), ints2(6, 12)) { ok = false; }
  if !ints_are(dec_interval("800c800c"), ints2(3200, 3200)) { ok = false; }
  if !err_bytes_is(ble_ad_slave_interval(5, 12), "ble: connection interval out of range") { ok = false; }
  if !err_bytes_is(ble_ad_slave_interval(6, 3201), "ble: connection interval out of range") { ok = false; }
  if !err_bytes_is(ble_ad_slave_interval(12, 6), "ble: connection interval min above max") { ok = false; }
  if !err_ints_is(dec_interval("0c000600"), "ble: connection interval min above max") { ok = false; }
  if !err_ints_is(dec_interval("0600"), "ble: wrong data length") { ok = false; }
  return assert(ok, "slave connection interval range: bytes, units, ordering errors");
}

fn t15() -> TestResult {
  let ab = bytes_of("AB");
  let big252 = repeat_byte(238, 252);
  let big253 = repeat_byte(238, 253);
  var ok = ok_bytes_is(ble_ad_service_data16(6157, &ab), hb("05160d184142"));
  if !err_bytes_is(ble_ad_service_data16(65536, &ab), "ble: UUID out of range") { ok = false; }
  if !err_bytes_is(ble_ad_service_data16(6157, &big253), "ble: payload too large") { ok = false; }
  let r252 = ble_ad_service_data16(6157, &big252);
  if !r252.is_ok { ok = false; } else {
    let b: Vec[UInt8] = r252.value;
    if b.len() != 256 { ok = false; }
    if ((b[0] as Int) & 0xFF) != 255 { ok = false; }
    if ((b[1] as Int) & 0xFF) != 22 { ok = false; }
  }
  let built = ble_ad_service_data16(6157, &ab);
  if !built.is_ok { return assert(false, "service data build must succeed"); }
  let b2: Vec[UInt8] = built.value;
  let pr = ble_parse(&b2);
  if !pr.is_ok { ok = false; } else {
    let l: AdList = pr.value;
    if ble_type(&l, 0) != 22 { ok = false; }
    let d = ble_data(&b2, &l, 0);
    if !d.is_ok { ok = false; } else {
      let dv: Vec[UInt8] = d.value;
      if dv.len() != 4 { ok = false; }
      let uuid_bytes = slice_of(dv, 0, 2);
      let tail = slice_of(dv, 2, 4);
      if !int_is(ble_decode_uuid16(&uuid_bytes), 6157) { ok = false; }
      if !bytes_equal(tail, ab) { ok = false; }
    }
  }
  return assert(ok, "service data 16: UUID + payload bytes and 252/253-byte boundary");
}

fn t16() -> TestResult {
  let ab = bytes_of("AB");
  var empty = Vec[UInt8].new();
  let big253 = repeat_byte(238, 253);
  var ok = ok_bytes_is(ble_ad_manufacturer(76, &ab), hb("05ff4c004142"));
  if !ok_bytes_is(ble_ad_manufacturer(76, &empty), hb("03ff4c00")) { ok = false; }
  if !int_is(dec_manu("4c004142"), 76) { ok = false; }
  if !int_is(dec_manu("4c00"), 76) { ok = false; }
  if !err_bytes_is(ble_ad_manufacturer(65536, &ab), "ble: manufacturer ID out of range") { ok = false; }
  if !err_bytes_is(ble_ad_manufacturer(-1, &ab), "ble: manufacturer ID out of range") { ok = false; }
  if !err_bytes_is(ble_ad_manufacturer(76, &big253), "ble: payload too large") { ok = false; }
  if !err_int_is(dec_manu("4c"), "ble: wrong data length") { ok = false; }
  let built = ble_ad_manufacturer(76, &ab);
  if !built.is_ok { return assert(false, "manufacturer build must succeed"); }
  let b: Vec[UInt8] = built.value;
  let pr = ble_parse(&b);
  if !pr.is_ok { ok = false; } else {
    let l: AdList = pr.value;
    if ble_type(&l, 0) != 255 { ok = false; }
    if !data_is(&b, &l, 0, hb("4c004142")) { ok = false; }
  }
  return assert(ok, "manufacturer data: company id LE + payload and range errors");
}

fn t17() -> TestResult {
  var empty = Vec[UInt8].new();
  let dead = hb("dead");
  let p254 = repeat_byte(7, 254);
  let p255 = repeat_byte(7, 255);
  var ok = ok_bytes_is(ble_ad(85, &empty), hb("0155"));
  if !ok_bytes_is(ble_ad(85, &dead), hb("0355dead")) { ok = false; }
  if !ok_bytes_is(ble_ad(0, &empty), hb("0100")) { ok = false; }
  if !err_bytes_is(ble_ad(256, &empty), "ble: AD type out of range") { ok = false; }
  if !err_bytes_is(ble_ad(-1, &empty), "ble: AD type out of range") { ok = false; }
  if !err_bytes_is(ble_ad(85, &p255), "ble: payload too large") { ok = false; }
  let r254 = ble_ad(85, &p254);
  if !r254.is_ok { ok = false; } else {
    let b: Vec[UInt8] = r254.value;
    if b.len() != 256 { ok = false; }
    if ((b[0] as Int) & 0xFF) != 255 { ok = false; }
  }
  var out = Vec[UInt8].new();
  let f = ble_append_ad(&mut out, 1, &empty);
  let m = ble_append_ad(&mut out, 255, &dead);
  if !f.is_ok || !m.is_ok { ok = false; }
  if !bytes_equal(out, hb("010103ffdead")) { ok = false; }
  let before = out.len();
  let bad = ble_append_ad(&mut out, 300, &dead);
  if !err_unit_is(bad, "ble: AD type out of range") { ok = false; }
  if out.len() != before { ok = false; }
  var types = Vec[Int].new();
  types.push(1);
  types.push(255);
  var payloads = Vec[Vec[UInt8]].new();
  payloads.push(empty);
  payloads.push(dead);
  let br = ble_build_from(&types, &payloads);
  if !ok_bytes_is(br, hb("010103ffdead")) { ok = false; }
  var types1 = Vec[Int].new();
  types1.push(1);
  if !err_bytes_is(ble_build_from(&types1, &payloads), "ble: types/payloads length mismatch") { ok = false; }
  var no_types = Vec[Int].new();
  var no_payloads = Vec[Vec[UInt8]].new();
  let er = ble_build_from(&no_types, &no_payloads);
  if !er.is_ok { ok = false; } else {
    let eb: Vec[UInt8] = er.value;
    if eb.len() != 0 { ok = false; }
  }
  var joined = Vec[UInt8].new();
  let fa = ble_ad_flags(6);
  let na = ble_ad_name_complete("AB");
  if !fa.is_ok || !na.is_ok { ok = false; } else {
    let fav: Vec[UInt8] = fa.value;
    let nav: Vec[UInt8] = na.value;
    ble_append_structure(&mut joined, &fav);
    ble_append_structure(&mut joined, &nav);
    if !bytes_equal(joined, hb("02010603094142")) { ok = false; }
  }
  var bad_types = Vec[Int].new();
  bad_types.push(1);
  bad_types.push(300);
  var bad_payloads = Vec[Vec[UInt8]].new();
  bad_payloads.push(empty);
  bad_payloads.push(empty);
  if !err_bytes_is(ble_build_from(&bad_types, &bad_payloads), "ble: AD type out of range") { ok = false; }
  return assert(ok, "generic AD, structure append, atomicity and build_from");
}

fn t18() -> TestResult {
  var empty = Vec[UInt8].new();
  let flags = ble_ad_flags(6);
  if !flags.is_ok { return assert(false, "flags build must succeed"); }
  let f: Vec[UInt8] = flags.value;
  let n26 = string.str_repeat("a", 26);
  let n27 = string.str_repeat("a", 27);
  let r26 = ble_ad_name_complete(n26);
  let r27 = ble_ad_name_complete(n27);
  if !r26.is_ok || !r27.is_ok { return assert(false, "name builds must succeed"); }
  let name26: Vec[UInt8] = r26.value;
  let name27: Vec[UInt8] = r27.value;
  let p31 = concat2(f, name26);
  let p32 = concat2(f, name27);
  var ok = p31.len() == 31;
  if p32.len() != 32 { ok = false; }
  if !ble_validate(&p31).is_ok { ok = false; }
  if !err_unit_is(ble_validate(&p32), "ble: payload exceeds 31-byte legacy limit") { ok = false; }
  if !ble_validate(&empty).is_ok { ok = false; }
  let bad = hb("01");
  if !err_unit_is(ble_validate(&bad), "ble: truncated AD structure") { ok = false; }
  if ble_legacy_limit() != 31 { ok = false; }
  return assert(ok, "ble_validate enforces the 31-byte legacy limit after parsing");
}

fn t19() -> TestResult {
  let data = hb("02010603094142020afc03030d18");
  let r = ble_parse(&data);
  if !r.is_ok { return assert(false, "valid payload must parse"); }
  let l: AdList = r.value;
  var ok = ble_type(&l, -1) == -1;
  if ble_type(&l, 4) != -1 { ok = false; }
  if ble_ad_size(&l, 4) != -1 { ok = false; }
  if ble_ad_size(&l, -1) != -1 { ok = false; }
  if !data_is(&data, &l, 3, hb("0d18")) { ok = false; }
  let cut = prefix(data, 6);
  if !data_is(&cut, &l, 0, hb("06")) { ok = false; }
  if !err_bytes_is(ble_data(&cut, &l, 1), "ble: data out of bounds") { ok = false; }
  if !err_bytes_is(ble_data(&cut, &l, 3), "ble: data out of bounds") { ok = false; }
  if !err_bytes_is(ble_data(&data, &l, -1), "ble: index out of range") { ok = false; }
  if !err_bytes_is(ble_data(&data, &l, 4), "ble: index out of range") { ok = false; }
  return assert(ok, "accessors report -1 / Err out of range and short buffers");
}

fn t20() -> TestResult {
  let ab = bytes_of("AB");
  let sd_payload = hb("01ff");
  let f = ble_ad_flags(6);
  let nm = ble_ad_name_complete("Xiom");
  let tp = ble_ad_tx_power(-4);
  let uu = ble_ad_service_uuid16(6157, true);
  let mf = ble_ad_manufacturer(76, &ab);
  let sd = ble_ad_service_data16(6157, &sd_payload);
  if !f.is_ok || !nm.is_ok || !tp.is_ok || !uu.is_ok || !mf.is_ok || !sd.is_ok {
    return assert(false, "all builders must succeed");
  }
  let fv: Vec[UInt8] = f.value;
  let nmv: Vec[UInt8] = nm.value;
  let tpv: Vec[UInt8] = tp.value;
  let uuv: Vec[UInt8] = uu.value;
  let mfv: Vec[UInt8] = mf.value;
  let sdv: Vec[UInt8] = sd.value;
  let p1 = concat2(fv, nmv);
  let p2 = concat2(p1, tpv);
  let p3 = concat2(p2, uuv);
  let p4 = concat2(p3, mfv);
  let payload = concat2(p4, sdv);
  var ok = payload.len() == 28;
  let pr = ble_parse(&payload);
  if !pr.is_ok { return assert(false, "built payload must parse"); }
  let l: AdList = pr.value;
  if ble_count(&l) != 6 { ok = false; }
  if ble_find(&l, 1) != 0 { ok = false; }
  if ble_find(&l, 9) != 1 { ok = false; }
  if ble_find(&l, 10) != 2 { ok = false; }
  if ble_find(&l, 3) != 3 { ok = false; }
  if ble_find(&l, 255) != 4 { ok = false; }
  if ble_find(&l, 22) != 5 { ok = false; }
  if ble_total_length(&l) != 28 { ok = false; }
  if !ble_validate(&payload).is_ok { ok = false; }
  var types = Vec[Int].new();
  var payloads = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < ble_count(&l) {
    types.push(ble_type(&l, i));
    let d = ble_data(&payload, &l, i);
    if !d.is_ok { ok = false; return assert(ok, "data slice must succeed"); }
    let dv: Vec[UInt8] = d.value;
    payloads.push(dv);
    i = i + 1;
  }
  let br = ble_build_from(&types, &payloads);
  if !br.is_ok { ok = false; } else {
    let rebuilt: Vec[UInt8] = br.value;
    if !bytes_equal(rebuilt, payload) { ok = false; }
  }
  return assert(ok, "build -> parse -> rebuild round-trip is byte-exact");
}

fn main() -> Int {
  io.println("=== xiom.ble conformance tests ===");
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
    io.println("xiom.ble: all tests passed");
  } else {
    io.println("xiom.ble: tests failed");
  }
  return failed;
}
