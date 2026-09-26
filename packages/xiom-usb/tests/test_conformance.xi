// XIOM -- xiom.usb conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pins the documented pure-XIOM USB descriptor codec against hand-built
// canonical streams: a 74-byte device+configuration+interface+two-endpoints
// +two-strings fixture, a device-only fixture, a raw-preserved
// qualifier/BOS/capability fixture and a UTF-16LE replacement fixture.
// Covers: device/configuration/interface/endpoint/string accessors, the
// endpoint-claim tolerance, string-index bounds, descriptor and raw-span
// accessors, the whole documented error catalog, and byte-exact canonical
// round-trips (including the emitter's drift guard).
//
// Str values read from Vec[Str] elements are bound to typed locals and
// compared with compare.str_compare (BUG 17: `==` on a Str read from a Vec
// lowers to a pointer comparison); every Vec[Int] element read is bound to
// a typed local.

module usb_tests
use xiom.io; use xiom.test;
use xiom.usb;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Byte and string helpers
// --------------------------------------------------

fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < string.str_len(s) {
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
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
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

fn prefix(v: &Vec[UInt8], n: Int) -> Vec[UInt8] {
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

fn err_usb_is(r: Result[Usb, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// DEVICE: bcdUSB 0x0200, idVendor 0x1234, idProduct 0x5678, bcdDevice
// 0x0100, iManufacturer 1, iProduct 2, iSerial 0, one configuration.
fn device_hex() -> Str {
  return "120100020000004034127856000101020001";
}

// CONFIGURATION: wTotalLength 0x0020 (9 + 9 + 7 + 7), one interface,
// bConfigurationValue 1, bmAttributes 0x80, bMaxPower 0x32.
fn config_hex() -> Str {
  return "090220000101008032";
}

// INTERFACE 0 alt 0, two endpoints, class 8 subclass 6 protocol 0x50.
fn interface_hex() -> Str {
  return "090400000208065000";
}

fn ep1_hex() -> Str {
  return "07058102000200";
}

fn ep2_hex() -> Str {
  return "07050202000200";
}

// STRING index 1 "ACME" and STRING index 2 "Widget" (each payload starts
// with the bStringIndex byte, then UTF-16LE units).
fn str1_hex() -> Str {
  return "0c030100410043004d004500";
}

fn str2_hex() -> Str {
  return "10030200570069006400670065007400";
}

// The canonical 74-byte stream: device, configuration, interface, endpoint
// 0x81, endpoint 0x02, string 1, string 2.
fn canon_hex() -> Str {
  return device_hex() + config_hex() + interface_hex() + ep1_hex() + ep2_hex() + str1_hex() + str2_hex();
}

// DEVICE only: all string indices 0, bNumConfigurations 1 (no configuration
// present; a documented tolerance).
fn device_only_hex() -> Str {
  return "120100020000004034127856000100000001";
}

// DEVICE with iProduct 2 but no STRING 2 in the stream.
fn missing_string_hex() -> Str {
  return "120100020000004034127856000100020000";
}

// DEVICE plus raw-preserved DEVICE_QUALIFIER, BOS and one
// DEVICE_CAPABILITY.
fn raw_hex() -> Str {
  return device_only_hex() + "0a060002e00101400100" + "050f090001" + "04100202";
}

// DEVICE with iProduct 1 plus STRING 1 whose five code units are
// 'A', U+00E9, U+0009, U+D83D, U+DE00: four replacements.
fn repl_hex() -> Str {
  return "120100020000004001000200000100010000" + "0e0301004100e90009003dd800de";
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = hb(canon_hex());
  let r = usb_parse(&data);
  if !r.is_ok { return assert(false, "canonical stream must parse"); }
  let u: Usb = r.value;
  var ok = usb_has_device(&u);
  if usb_device_bcd_usb(&u) != 512 { ok = false; }
  if usb_device_class(&u) != 0 { ok = false; }
  if usb_device_subclass(&u) != 0 { ok = false; }
  if usb_device_protocol(&u) != 0 { ok = false; }
  if usb_device_max_packet0(&u) != 64 { ok = false; }
  if usb_device_vendor(&u) != 4660 { ok = false; }
  if usb_device_product(&u) != 22136 { ok = false; }
  if usb_device_bcd_device(&u) != 256 { ok = false; }
  if usb_device_imanufacturer(&u) != 1 { ok = false; }
  if usb_device_iproduct(&u) != 2 { ok = false; }
  if usb_device_iserial(&u) != 0 { ok = false; }
  if usb_device_num_configurations(&u) != 1 { ok = false; }
  return assert(ok, "device descriptor fields are pinned");
}

fn t2() -> TestResult {
  let data = hb(canon_hex());
  let r = usb_parse(&data);
  if !r.is_ok { return assert(false, "canonical stream must parse"); }
  let u: Usb = r.value;
  var ok = usb_configuration_count(&u) == 1;
  if usb_configuration_total_length(&u, 0) != 32 { ok = false; }
  if usb_configuration_num_interfaces(&u, 0) != 1 { ok = false; }
  if usb_configuration_value(&u, 0) != 1 { ok = false; }
  if usb_configuration_istring(&u, 0) != 0 { ok = false; }
  if usb_configuration_attributes(&u, 0) != 128 { ok = false; }
  if usb_configuration_max_power(&u, 0) != 50 { ok = false; }
  if usb_configuration_interface_count(&u, 0) != 1 { ok = false; }
  if usb_configuration_total_length(&u, -1) != -1 { ok = false; }
  if usb_configuration_total_length(&u, 1) != -1 { ok = false; }
  return assert(ok, "configuration fields are pinned");
}

fn t3() -> TestResult {
  let data = hb(canon_hex());
  let r = usb_parse(&data);
  if !r.is_ok { return assert(false, "canonical stream must parse"); }
  let u: Usb = r.value;
  var ok = usb_interface_count(&u) == 1;
  if usb_interface_configuration(&u, 0) != 0 { ok = false; }
  if usb_interface_number(&u, 0) != 0 { ok = false; }
  if usb_interface_alternate(&u, 0) != 0 { ok = false; }
  if usb_interface_endpoint_claim(&u, 0) != 2 { ok = false; }
  if usb_interface_endpoint_count(&u, 0) != 2 { ok = false; }
  if usb_interface_unlisted_endpoints(&u, 0) != 0 { ok = false; }
  if usb_interface_class(&u, 0) != 8 { ok = false; }
  if usb_interface_subclass(&u, 0) != 6 { ok = false; }
  if usb_interface_protocol(&u, 0) != 80 { ok = false; }
  if usb_interface_istring(&u, 0) != 0 { ok = false; }
  if usb_interface_number(&u, 1) != -1 { ok = false; }
  return assert(ok, "interface fields are pinned");
}

fn t4() -> TestResult {
  let data = hb(canon_hex());
  let r = usb_parse(&data);
  if !r.is_ok { return assert(false, "canonical stream must parse"); }
  let u: Usb = r.value;
  var ok = usb_endpoint_count(&u) == 2;
  if usb_endpoint_count_for_interface(&u, 0) != 2 { ok = false; }
  if usb_endpoint_interface(&u, 0) != 0 { ok = false; }
  if usb_endpoint_interface(&u, 1) != 0 { ok = false; }
  if usb_endpoint_address(&u, 0) != 129 { ok = false; }
  if usb_endpoint_attributes(&u, 0) != 2 { ok = false; }
  if usb_endpoint_max_packet(&u, 0) != 512 { ok = false; }
  if usb_endpoint_interval(&u, 0) != 0 { ok = false; }
  if usb_endpoint_address(&u, 1) != 2 { ok = false; }
  if usb_endpoint_max_packet(&u, 1) != 512 { ok = false; }
  if usb_find_endpoint(&u, 0, 129) != 0 { ok = false; }
  if usb_find_endpoint(&u, 0, 2) != 1 { ok = false; }
  if usb_find_endpoint(&u, 0, 153) != -1 { ok = false; }
  if usb_find_endpoint(&u, 3, 129) != -1 { ok = false; }
  if usb_endpoint_address(&u, 2) != -1 { ok = false; }
  return assert(ok, "endpoint fields are pinned by interface");
}

fn t5() -> TestResult {
  let data = hb(canon_hex());
  let r = usb_parse(&data);
  if !r.is_ok { return assert(false, "canonical stream must parse"); }
  let u: Usb = r.value;
  var ok = usb_string_count(&u) == 2;
  if usb_string_index(&u, 0) != 1 { ok = false; }
  if usb_string_index(&u, 1) != 2 { ok = false; }
  let s0: Str = usb_string_text(&u, 0);
  let s1: Str = usb_string_text(&u, 1);
  if !str_eq(s0, "ACME") { ok = false; }
  if !str_eq(s1, "Widget") { ok = false; }
  if usb_string_replacements(&u, 0) != 0 { ok = false; }
  if usb_string_replacements(&u, 1) != 0 { ok = false; }
  if !usb_string_present(&u, 1) { ok = false; }
  if !usb_string_present(&u, 2) { ok = false; }
  if usb_string_present(&u, 3) { ok = false; }
  let sr = usb_string(&u, 2);
  if !sr.is_ok { ok = false; } else {
    let got: Str = sr.value;
    if !str_eq(got, "Widget") { ok = false; }
  }
  if !err_str_is(usb_string(&u, 5), "usb: string index not found") { ok = false; }
  if !str_eq(usb_string_text(&u, 9), "") { ok = false; }
  if usb_string_replacements(&u, 9) != -1 { ok = false; }
  return assert(ok, "string pool decodes ASCII and resolves by index");
}

fn t6() -> TestResult {
  let data = hb(canon_hex());
  let r = usb_parse(&data);
  if !r.is_ok { return assert(false, "canonical stream must parse"); }
  let u: Usb = r.value;
  let er = usb_emit(&data, &u);
  if !er.is_ok { return assert(false, "canonical emit must succeed"); }
  let out: Vec[UInt8] = er.value;
  var ok = bytes_equal(out, data);
  if out.len() != 78 { ok = false; }
  // Reparse of the emitted bytes keeps the device fields.
  let r2 = usb_parse(&out);
  if !r2.is_ok { ok = false; } else {
    let u2: Usb = r2.value;
    if usb_device_vendor(&u2) != 4660 { ok = false; }
    if usb_configuration_total_length(&u2, 0) != 32 { ok = false; }
    let s2: Str = usb_string_text(&u2, 1);
    if !str_eq(s2, "Widget") { ok = false; }
  }
  return assert(ok, "canonical device+config+interfaces+endpoints+strings round-trips byte-exact");
}

fn t7() -> TestResult {
  let data = hb(raw_hex());
  let r = usb_parse(&data);
  if !r.is_ok { return assert(false, "raw fixture must parse"); }
  let u: Usb = r.value;
  var ok = usb_raw_count(&u) == 3;
  if usb_raw_type(&u, 0) != 6 { ok = false; }
  if usb_raw_type(&u, 1) != 15 { ok = false; }
  if usb_raw_type(&u, 2) != 16 { ok = false; }
  if usb_raw_offset(&u, 0) != 18 { ok = false; }
  if usb_raw_offset(&u, 1) != 28 { ok = false; }
  if usb_raw_offset(&u, 2) != 33 { ok = false; }
  if usb_raw_length(&u, 0) != 10 { ok = false; }
  if usb_raw_length(&u, 1) != 5 { ok = false; }
  if usb_raw_length(&u, 2) != 4 { ok = false; }
  if usb_raw_find(&u, 6) != 0 { ok = false; }
  if usb_raw_find(&u, 15) != 1 { ok = false; }
  if usb_raw_find(&u, 16) != 2 { ok = false; }
  if usb_raw_find(&u, 99) != -1 { ok = false; }
  if usb_raw_type(&u, 3) != -1 { ok = false; }
  let qr = usb_raw_bytes(&data, &u, 0);
  if !qr.is_ok { ok = false; } else {
    let qv: Vec[UInt8] = qr.value;
    if !bytes_equal(qv, hb("0a060002e00101400100")) { ok = false; }
  }
  if !err_bytes_is(usb_raw_bytes(&data, &u, 9), "usb: raw index out of range") { ok = false; }
  return assert(ok, "raw descriptor spans and lookup are pinned");
}

fn t8() -> TestResult {
  let data = hb(raw_hex());
  let r = usb_parse(&data);
  if !r.is_ok { return assert(false, "raw fixture must parse"); }
  let u: Usb = r.value;
  var ok = usb_qualifier_present(&u);
  if usb_qualifier_bcd_usb(&data, &u) != 512 { ok = false; }
  if usb_qualifier_class(&data, &u) != 224 { ok = false; }
  if usb_qualifier_subclass(&data, &u) != 1 { ok = false; }
  if usb_qualifier_protocol(&data, &u) != 1 { ok = false; }
  if usb_qualifier_max_packet0(&data, &u) != 64 { ok = false; }
  if usb_qualifier_num_configs(&data, &u) != 1 { ok = false; }
  if !usb_bos_present(&u) { ok = false; }
  if usb_bos_total_length(&data, &u) != 9 { ok = false; }
  if usb_bos_num_capabilities(&data, &u) != 1 { ok = false; }
  if usb_capability_count(&u) != 1 { ok = false; }
  if usb_capability_type(&data, &u, 0) != 2 { ok = false; }
  if usb_capability_length(&u, 0) != 4 { ok = false; }
  let cr = usb_capability_bytes(&data, &u, 0);
  if !cr.is_ok { ok = false; } else {
    let cv: Vec[UInt8] = cr.value;
    if !bytes_equal(cv, hb("04100202")) { ok = false; }
  }
  if usb_capability_type(&data, &u, 4) != -1 { ok = false; }
  if usb_capability_length(&u, 4) != -1 { ok = false; }
  // Raw-preserved descriptors keep their order: device then the raw extras.
  let er = usb_emit(&data, &u);
  if !er.is_ok { ok = false; } else {
    let out: Vec[UInt8] = er.value;
    if !bytes_equal(out, data) { ok = false; }
  }
  return assert(ok, "qualifier/BOS/capability headers are readable and round-trip raw");
}

fn t9() -> TestResult {
  let data = hb(repl_hex());
  let r = usb_parse(&data);
  if !r.is_ok { return assert(false, "replacement fixture must parse"); }
  let u: Usb = r.value;
  var ok = usb_string_count(&u) == 1;
  if usb_string_index(&u, 0) != 1 { ok = false; }
  let s: Str = usb_string_text(&u, 0);
  if !str_eq(s, "A????") { ok = false; }
  if usb_string_replacements(&u, 0) != 4 { ok = false; }
  let sr = usb_string(&u, 1);
  if !sr.is_ok { ok = false; } else {
    let got: Str = sr.value;
    if !str_eq(got, "A????") { ok = false; }
  }
  return assert(ok, "non-ASCII UTF-16LE units are replaced by '?' and counted");
}

fn t10() -> TestResult {
  let data = hb(canon_hex());
  let r = usb_parse(&data);
  if !r.is_ok { return assert(false, "canonical stream must parse"); }
  let u: Usb = r.value;
  var ok = usb_descriptor_count(&u) == 7;
  if usb_descriptor_type(&u, 0) != 1 { ok = false; }
  if usb_descriptor_type(&u, 1) != 2 { ok = false; }
  if usb_descriptor_type(&u, 2) != 4 { ok = false; }
  if usb_descriptor_type(&u, 3) != 5 { ok = false; }
  if usb_descriptor_type(&u, 4) != 5 { ok = false; }
  if usb_descriptor_type(&u, 5) != 3 { ok = false; }
  if usb_descriptor_type(&u, 6) != 3 { ok = false; }
  if usb_descriptor_length(&u, 0) != 18 { ok = false; }
  if usb_descriptor_length(&u, 1) != 9 { ok = false; }
  if usb_descriptor_length(&u, 2) != 9 { ok = false; }
  if usb_descriptor_length(&u, 3) != 7 { ok = false; }
  if usb_descriptor_length(&u, 5) != 12 { ok = false; }
  if usb_descriptor_length(&u, 6) != 16 { ok = false; }
  if usb_descriptor_offset(&u, 0) != 0 { ok = false; }
  if usb_descriptor_offset(&u, 1) != 18 { ok = false; }
  if usb_descriptor_offset(&u, 2) != 27 { ok = false; }
  if usb_descriptor_offset(&u, 3) != 36 { ok = false; }
  if usb_descriptor_offset(&u, 4) != 43 { ok = false; }
  if usb_descriptor_offset(&u, 5) != 50 { ok = false; }
  if usb_descriptor_offset(&u, 6) != 62 { ok = false; }
  let dr = usb_descriptor_bytes(&data, &u, 0);
  if !dr.is_ok { ok = false; } else {
    let dv: Vec[UInt8] = dr.value;
    if !bytes_equal(dv, hb(device_hex())) { ok = false; }
  }
  if !err_bytes_is(usb_descriptor_bytes(&data, &u, 7), "usb: descriptor index out of range") { ok = false; }
  if !err_bytes_is(usb_descriptor_bytes(&data, &u, -1), "usb: descriptor index out of range") { ok = false; }
  let short = prefix(&data, 10);
  if !err_bytes_is(usb_descriptor_bytes(&short, &u, 0), "usb: descriptor span out of bounds") { ok = false; }
  if usb_descriptor_type(&u, 7) != -1 { ok = false; }
  if usb_descriptor_length(&u, -1) != -1 { ok = false; }
  if usb_descriptor_offset(&u, 99) != -1 { ok = false; }
  return assert(ok, "global descriptor spans and out-of-range accessors are pinned");
}

fn t11() -> TestResult {
  let one = hb("05");
  var ok = err_usb_is(usb_parse(&one), "usb: truncated descriptor header");
  let bad = hb("0100");
  if !err_usb_is(usb_parse(&bad), "usb: bad descriptor length") { ok = false; }
  let cut = hb("12010002000000400100");
  if !err_usb_is(usb_parse(&cut), "usb: truncated descriptor") { ok = false; }
  return assert(ok, "truncated headers, bad bLength and truncated descriptors are rejected");
}

fn t12() -> TestResult {
  let bad = hb("1101000200000040010002000001000000");
  var ok = err_usb_is(usb_parse(&bad), "usb: bad device descriptor length");
  let d2 = concat2(hb(device_only_hex()), hb(device_only_hex()));
  if !err_usb_is(usb_parse(&d2), "usb: duplicate device descriptor") { ok = false; }
  let c1 = concat2(hb(device_hex()), hb("0802200001010080"));
  if !err_usb_is(usb_parse(&c1), "usb: bad configuration descriptor length") { ok = false; }
  let c2 = concat2(hb(device_hex()), hb("090211000101008032"));
  let c2b = concat2(c2, hb("0804000002080650"));
  if !err_usb_is(usb_parse(&c2b), "usb: bad interface descriptor length") { ok = false; }
  let c3 = concat2(hb(device_hex()), hb("090218000101008032"));
  let c3b = concat2(c3, hb("090400000108065000"));
  let c3c = concat2(c3b, hb("060581020002"));
  if !err_usb_is(usb_parse(&c3c), "usb: bad endpoint descriptor length") { ok = false; }
  let c4 = concat2(hb(device_only_hex()), hb("030341"));
  if !err_usb_is(usb_parse(&c4), "usb: bad string descriptor length") { ok = false; }
  let c5 = concat2(hb(device_only_hex()), hb("0203"));
  if !err_usb_is(usb_parse(&c5), "usb: bad string descriptor length") { ok = false; }
  return assert(ok, "wrong per-type descriptor lengths are rejected");
}

fn t13() -> TestResult {
  let c1 = concat2(hb(device_hex()), hb("090208000101008032"));
  var ok = err_usb_is(usb_parse(&c1), "usb: configuration total length out of range");
  let c2 = concat2(hb(device_hex()), hb("090264000101008032"));
  if !err_usb_is(usb_parse(&c2), "usb: configuration total length out of range") { ok = false; }
  let c3 = concat2(hb(device_hex()), hb("090214000101008032"));
  let c3b = concat2(c3, hb(interface_hex()));
  let c3c = concat2(c3b, hb(ep1_hex()));
  if !err_usb_is(usb_parse(&c3c), "usb: configuration total length mismatch") { ok = false; }
  return assert(ok, "wTotalLength outside the buffer or not covering children exactly is rejected");
}

fn t14() -> TestResult {
  var ok = err_usb_is(usb_parse(&hb(interface_hex())), "usb: interface outside configuration");
  if !err_usb_is(usb_parse(&hb(ep1_hex())), "usb: endpoint outside interface") { ok = false; }
  return assert(ok, "interfaces need a configuration and endpoints need an interface");
}

fn t15() -> TestResult {
  // Claim 1 with two endpoints: the second endpoint exceeds the claim.
  let c1 = concat2(hb(device_only_hex()), hb("090220000101008032"));
  let c1b = concat2(c1, hb("090400000108065000"));
  let c1c = concat2(c1b, hb(ep1_hex()));
  let c1d = concat2(c1c, hb(ep2_hex()));
  var ok = err_usb_is(usb_parse(&c1d), "usb: endpoint count exceeds interface claim");
  // Claim 3 with two endpoints: tolerated, one unlisted.
  let c2 = concat2(hb(device_only_hex()), hb("090220000101008032"));
  let c2b = concat2(c2, hb("090400000308065000"));
  let c2c = concat2(c2b, hb(ep1_hex()));
  let c2d = concat2(c2c, hb(ep2_hex()));
  let r2 = usb_parse(&c2d);
  if !r2.is_ok { ok = false; } else {
    let u2: Usb = r2.value;
    if usb_interface_endpoint_claim(&u2, 0) != 3 { ok = false; }
    if usb_interface_endpoint_count(&u2, 0) != 2 { ok = false; }
    if usb_interface_unlisted_endpoints(&u2, 0) != 1 { ok = false; }
    let er2 = usb_emit(&c2d, &u2);
    if !er2.is_ok { ok = false; } else {
      let out2: Vec[UInt8] = er2.value;
      if !bytes_equal(out2, c2d) { ok = false; }
    }
  }
  return assert(ok, "the endpoint claim is an upper bound; fewer endpoints are tolerated");
}

fn t16() -> TestResult {
  var ok = err_usb_is(usb_parse(&hb(missing_string_hex())), "usb: string index out of range");
  let cfg_bad = concat2(hb(device_only_hex()), hb("090209000101038032"));
  if !err_usb_is(usb_parse(&cfg_bad), "usb: string index out of range") { ok = false; }
  return assert(ok, "nonzero string indices must resolve in the pool");
}

fn t17() -> TestResult {
  let empty = Vec[UInt8].new();
  let r = usb_parse(&empty);
  if !r.is_ok { return assert(false, "empty stream must parse"); }
  let u: Usb = r.value;
  var ok = usb_descriptor_count(&u) == 0;
  if usb_has_device(&u) { ok = false; }
  if usb_device_bcd_usb(&u) != -1 { ok = false; }
  if usb_device_vendor(&u) != -1 { ok = false; }
  if usb_device_num_configurations(&u) != -1 { ok = false; }
  if usb_configuration_count(&u) != 0 { ok = false; }
  if usb_interface_count(&u) != 0 { ok = false; }
  if usb_endpoint_count(&u) != 0 { ok = false; }
  if usb_string_count(&u) != 0 { ok = false; }
  if usb_raw_count(&u) != 0 { ok = false; }
  if usb_descriptor_type(&u, 0) != -1 { ok = false; }
  if usb_endpoint_address(&u, 0) != -1 { ok = false; }
  if usb_configuration_interface_count(&u, 0) != -1 { ok = false; }
  if !err_str_is(usb_string(&u, 1), "usb: string index not found") { ok = false; }
  let er = usb_emit(&empty, &u);
  if !er.is_ok { ok = false; } else {
    let out: Vec[UInt8] = er.value;
    if out.len() != 0 { ok = false; }
  }
  return assert(ok, "an empty stream parses to an empty store with -1 / empty accessors");
}

fn t18() -> TestResult {
  let d = hb(device_only_hex());
  let r = usb_parse(&d);
  if !r.is_ok { return assert(false, "device-only stream must parse"); }
  let u: Usb = r.value;
  var ok = usb_has_device(&u);
  if usb_configuration_count(&u) != 0 { ok = false; }
  if usb_device_num_configurations(&u) != 1 { ok = false; }
  if usb_qualifier_present(&u) { ok = false; }
  if usb_bos_present(&u) { ok = false; }
  if usb_capability_count(&u) != 0 { ok = false; }
  if usb_raw_count(&u) != 0 { ok = false; }
  let er = usb_emit(&d, &u);
  if !er.is_ok { ok = false; } else {
    let out: Vec[UInt8] = er.value;
    if !bytes_equal(out, d) { ok = false; }
  }
  return assert(ok, "a device-only dump parses (bNumConfigurations is not enforced)");
}

fn t19() -> TestResult {
  let data = hb(canon_hex());
  let r = usb_parse(&data);
  if !r.is_ok { return assert(false, "canonical stream must parse"); }
  var u: Usb = r.value;
  let short = prefix(&data, 10);
  var ok = err_bytes_is(usb_emit(&short, &u), "usb: invalid store");
  let good = usb_emit(&data, &u);
  if !good.is_ok { ok = false; }
  u.if_number.push(0);
  if !err_bytes_is(usb_emit(&data, &u), "usb: invalid store") { ok = false; }
  let r2 = usb_parse(&data);
  if !r2.is_ok { ok = false; } else {
    var u2: Usb = r2.value;
    u2.raw_desc.push(999);
    if !err_bytes_is(usb_emit(&data, &u2), "usb: invalid store") { ok = false; }
  }
  return assert(ok, "the emitter refuses drifted stores and short buffers");
}

fn t20() -> TestResult {
  // Wire check for the structured-length constants: the two endpoint
  // descriptors in the canonical fixture claim 512-byte packets and the
  // interface claims exactly the two parsed endpoints.
  let data = hb(canon_hex());
  let r = usb_parse(&data);
  if !r.is_ok { return assert(false, "canonical stream must parse"); }
  let u: Usb = r.value;
  var ok = usb_endpoint_max_packet(&u, 0) == 512;
  if usb_endpoint_max_packet(&u, 1) != 512 { ok = false; }
  if usb_endpoint_attributes(&u, 1) != 2 { ok = false; }
  if usb_endpoint_interval(&u, 1) != 0 { ok = false; }
  if usb_interface_endpoint_claim(&u, 0) != usb_endpoint_count_for_interface(&u, 0) { ok = false; }
  if usb_configuration_interface_count(&u, 0) != usb_interface_count(&u) { ok = false; }
  return assert(ok, "endpoint/interface aggregate counts agree with the fixture");
}

fn main() -> Int {
  io.println("=== xiom.usb conformance tests ===");
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
    io.println("xiom.usb: all tests passed");
  } else {
    io.println("xiom.usb: tests failed");
  }
  return failed;
}
