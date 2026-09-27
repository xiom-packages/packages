// XIOM -- xiom.ldap conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every fixture is synthetic: hex strings decoded in-test plus structures
// assembled from the library's own encoders and small local wrap/concat
// helpers (no external data files). The error strings are compared through
// xiom.string.compare.str_compare (BUG 17: `==` on a Str read from a Vec
// lowers to a pointer comparison), every Vec element is read into a typed
// local first, and context tags >= 0x80 are only ever compared as widened
// Ints.

module ldap_tests
use xiom.io; use xiom.test;
use xiom.ldap;
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

fn concat3(a: Vec[UInt8], b: Vec[UInt8], c: Vec[UInt8]) -> Vec[UInt8] {
  return concat2(concat2(a, b), c);
}

fn concat4(a: Vec[UInt8], b: Vec[UInt8], c: Vec[UInt8], d: Vec[UInt8]) -> Vec[UInt8] {
  return concat2(concat3(a, b, c), d);
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

fn oct(s: Str) -> Vec[UInt8] {
  let b = bytes_of(s);
  return wrap(4, b);
}

fn oct_b(v: Vec[UInt8]) -> Vec[UInt8] {
  return wrap(4, v);
}

fn present_f(attr: Str) -> Vec[UInt8] {
  let b = bytes_of(attr);
  return wrap(135, b);
}

fn eq_f(attr: Str, val: Str) -> Vec[UInt8] {
  return wrap(163, concat2(oct(attr), oct(val)));
}

fn one(s: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(s);
  return v;
}

fn two(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn three(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

// PartialAttribute: SEQUENCE { type, SET OF value }.
fn pt(name: Str, values: Vec[Str]) -> Vec[UInt8] {
  var vb = Vec[UInt8].new();
  var i = 0;
  while i < values.len() {
    let v: Str = values[i];
    let t = oct(v);
    vb = concat2(vb, t);
    i = i + 1;
  }
  return wrap(48, concat2(oct(name), wrap(49, vb)));
}

// ModifyRequest change: SEQUENCE { operation, modification }.
fn change(op: Int, name: Str, values: Vec[Str]) -> Vec[UInt8] {
  return wrap(48, concat2(ber_enum_encode(op), pt(name, values)));
}

// --------------------------------------------------
//  Result checkers
// --------------------------------------------------

fn len_is(r: Result[BerLength, Str], len: Int, size: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BerLength = r.value;
  return v.len == len && v.size == size;
}

fn err_blen_is(r: Result[BerLength, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn tlv_is(r: Result[BerTlv, Str], tag: Int, len: Int, size: Int, content: Int, next: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BerTlv = r.value;
  return v.tag == tag && v.len == len && v.size == size && v.content == content && v.next == next;
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

fn bint_next_is(r: Result[BerInt, Str], want: Int, next: Int) -> Bool {
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

fn bbytes_next_is(r: Result[BerBytes, Str], want: Vec[UInt8], next: Int) -> Bool {
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

fn bbool_is(r: Result[BerBool, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BerBool = r.value;
  return v.value == want;
}

fn err_bbool_is(r: Result[BerBool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn benum_is(r: Result[BerEnum, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BerEnum = r.value;
  return v.value == want;
}

fn err_benum_is(r: Result[BerEnum, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn lstr_is(r: Result[LdapStr, Str], want: Str, next: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: LdapStr = r.value;
  return str_eq(v.value, want) && v.next == next;
}

fn err_lstr_is(r: Result[LdapStr, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_msg_is(r: Result[LdapMessage, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_filter_is(r: Result[LdapFilter, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bind_is(r: Result[LdapBindRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_result_is(r: Result[LdapResult, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_search_is(r: Result[LdapSearchRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_entry_is(r: Result[LdapSearchEntry, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_modify_is(r: Result[LdapModifyRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_add_is(r: Result[LdapAddRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_moddn_is(r: Result[LdapModifyDnRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_compare_is(r: Result[LdapCompareRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_ref_is(r: Result[LdapSearchReference, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_ext_is(r: Result[LdapExtendedRequest, Str], want: Str) -> Bool {
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
  if !len_is(ber_length_decode(&hb("83010000"), 0), 65536, 4) { ok = false; }
  if !err_blen_is(ber_length_decode(&hb("80"), 0), eat("ber: indefinite length", 0)) { ok = false; }
  if !err_blen_is(ber_length_decode(&hb("8105"), 0), eat("ber: overlong length", 0)) { ok = false; }
  if !err_blen_is(ber_length_decode(&hb("820005"), 0), eat("ber: overlong length", 0)) { ok = false; }
  if !err_blen_is(ber_length_decode(&hb("89000000000000000000"), 0), eat("ber: length overflow", 0)) { ok = false; }
  if !err_blen_is(ber_length_decode(&hb("88ffffffffffffffff"), 0), eat("ber: length overflow", 0)) { ok = false; }
  if !err_blen_is(ber_length_decode(&hb("8201"), 0), eat("ber: truncated length", 0)) { ok = false; }
  if !err_blen_is(ber_length_decode(&hb("01"), 1), eat("ber: truncated length", 1)) { ok = false; }
  if !err_blen_is(ber_length_decode(&hb("00"), -1), "ber: negative offset") { ok = false; }
  return assert(ok, "BER length: short form, long form 1-4 bytes, indefinite/overlong/overflow/truncation");
}

fn t2() -> TestResult {
  let h1 = hb("020105");
  var ok = tlv_is(ber_tlv_decode(&h1, 0), 2, 1, 2, 2, 3);
  let h2 = hb("3000");
  if !tlv_is(ber_tlv_decode(&h2, 0), 48, 0, 2, 2, 2) { ok = false; }
  let h3 = hb("020105ff");
  if !tlv_is(ber_tlv_decode(&h3, 0), 2, 1, 2, 2, 3) { ok = false; }
  let big = repeat_byte(65, 130);
  let h4 = wrap(4, big);
  if !tlv_is(ber_tlv_decode(&h4, 0), 4, 130, 3, 3, 133) { ok = false; }
  let h5 = wrap(48, hb("020105"));
  if !tlv_is(ber_tlv_decode(&h5, 2), 2, 1, 2, 4, 5) { ok = false; }
  let empty = Vec[UInt8].new();
  if !err_tlv_is(ber_tlv_decode(&empty, 0), eat("ber: truncated tag", 0)) { ok = false; }
  if !err_tlv_is(ber_tlv_decode(&hb("1f01"), 0), eat("ber: multi-byte tag", 0)) { ok = false; }
  if !err_tlv_is(ber_tlv_decode(&hb("04"), 0), eat("ber: truncated length", 1)) { ok = false; }
  if !err_tlv_is(ber_tlv_decode(&hb("04890000000000000000"), 0), eat("ber: length overflow", 1)) { ok = false; }
  if !err_tlv_is(ber_tlv_decode(&hb("0405aabb"), 0), eat("ber: value overruns buffer", 0)) { ok = false; }
  if !err_tlv_is(ber_tlv_decode(&hb("0400"), 3), eat("ber: truncated tag", 3)) { ok = false; }
  if !err_tlv_is(ber_tlv_decode(&hb("00"), -1), "ber: negative offset") { ok = false; }
  return assert(ok, "BER TLV: header fields, long form, non-zero start, malformed tags/lengths/bounds");
}

fn t3() -> TestResult {
  var ok = bint_next_is(ber_int_decode(&hb("020100"), 0), 0, 3);
  if !bint_is(ber_int_decode(&hb("02017f"), 0), 127) { ok = false; }
  if !bint_is(ber_int_decode(&hb("02020080"), 0), 128) { ok = false; }
  if !bint_is(ber_int_decode(&hb("020200ff"), 0), 255) { ok = false; }
  if !bint_is(ber_int_decode(&hb("02020100"), 0), 256) { ok = false; }
  if !bint_is(ber_int_decode(&hb("0201ff"), 0), -1) { ok = false; }
  if !bint_is(ber_int_decode(&hb("020180"), 0), -128) { ok = false; }
  if !bint_is(ber_int_decode(&hb("0202ff7f"), 0), -129) { ok = false; }
  if !bint_is(ber_int_decode(&hb("0202ff00"), 0), -256) { ok = false; }
  if !bint_is(ber_int_decode(&hb("02080100000000000000"), 0), 72057594037927936) { ok = false; }
  if !err_bint_is(ber_int_decode(&hb("0200"), 0), eat("ber: empty integer", 0)) { ok = false; }
  if !err_bint_is(ber_int_decode(&hb("0209010000000000000000"), 0), eat("ber: integer overflow", 0)) { ok = false; }
  if !err_bint_is(ber_int_decode(&hb("0202007f"), 0), eat("ber: non-minimal integer", 0)) { ok = false; }
  if !err_bint_is(ber_int_decode(&hb("0202ff80"), 0), eat("ber: non-minimal integer", 0)) { ok = false; }
  if !err_bint_is(ber_int_decode(&hb("040100"), 0), eat("ber: tag mismatch", 0)) { ok = false; }
  let trunc = hb("02");
  if !err_bint_is(ber_int_decode(&trunc, 0), eat("ber: truncated length", 1)) { ok = false; }
  return assert(ok, "INTEGER: bounds, minimal-encoding rule, empty/overflow/truncation");
}

fn t4() -> TestResult {
  let s1 = hb("0403616263");
  var ok = bbytes_next_is(ber_octet_string_decode(&s1, 0), bytes_of("abc"), 5);
  let s2 = hb("0400");
  if !bbytes_is(ber_octet_string_decode(&s2, 0), Vec[UInt8].new()) { ok = false; }
  let s3 = hb("040400ff4100");
  if !bbytes_is(ber_octet_string_decode(&s3, 0), hb("00ff4100")) { ok = false; }
  let s4 = hb("0405aabb");
  if !err_bbytes_is(ber_octet_string_decode(&s4, 0), eat("ber: value overruns buffer", 0)) { ok = false; }
  if !err_bbytes_is(ber_octet_string_decode(&hb("020101"), 0), eat("ber: tag mismatch", 0)) { ok = false; }
  if !err_bbytes_is(ber_octet_string_decode(&hb("0400"), 5), eat("ber: truncated tag", 5)) { ok = false; }
  if !bbool_is(ber_bool_decode(&hb("0101ff"), 0), 1) { ok = false; }
  if !bbool_is(ber_bool_decode(&hb("010100"), 0), 0) { ok = false; }
  if !bbool_is(ber_bool_decode(&hb("010101"), 0), 1) { ok = false; }
  if !err_bbool_is(ber_bool_decode(&hb("010200ff"), 0), eat("ber: bad boolean", 0)) { ok = false; }
  if !err_bbool_is(ber_bool_decode(&hb("0100"), 0), eat("ber: bad boolean", 0)) { ok = false; }
  if !err_bbool_is(ber_bool_decode(&hb("040101"), 0), eat("ber: tag mismatch", 0)) { ok = false; }
  if !benum_is(ber_enum_decode(&hb("0a0100"), 0), 0) { ok = false; }
  if !benum_is(ber_enum_decode(&hb("0a017f"), 0), 127) { ok = false; }
  if !benum_is(ber_enum_decode(&hb("0a020080"), 0), 128) { ok = false; }
  if !err_benum_is(ber_enum_decode(&hb("0a00"), 0), eat("ber: empty integer", 0)) { ok = false; }
  if !err_benum_is(ber_enum_decode(&hb("020100"), 0), eat("ber: tag mismatch", 0)) { ok = false; }
  return assert(ok, "OCTET STRING / BOOLEAN / ENUMERATED: raw content, single-byte bool, enum bounds");
}

fn t5() -> TestResult {
  let q1 = hb("3000");
  var ok = tlv_is(ber_sequence_decode(&q1, 0), 48, 0, 2, 2, 2);
  let q2 = hb("3100");
  if !tlv_is(ber_sequence_decode(&q2, 0), 49, 0, 2, 2, 2) { ok = false; }
  let q3 = wrap(48, hb("3100"));
  if !tlv_is(ber_sequence_decode(&q3, 2), 49, 0, 2, 4, 4) { ok = false; }
  if !err_tlv_is(ber_sequence_decode(&hb("020100"), 0), eat("ber: tag mismatch", 0)) { ok = false; }
  let trunc = hb("30");
  if !err_tlv_is(ber_sequence_decode(&trunc, 0), eat("ber: truncated length", 1)) { ok = false; }
  return assert(ok, "SEQUENCE/SET: both constructed tags accepted, tag mismatch and truncation");
}

fn t6() -> TestResult {
  var ok = bytes_equal(ber_length_encode(0), hb("00"));
  if !bytes_equal(ber_length_encode(127), hb("7f")) { ok = false; }
  if !bytes_equal(ber_length_encode(128), hb("8180")) { ok = false; }
  if !bytes_equal(ber_length_encode(300), hb("82012c")) { ok = false; }
  if !bytes_equal(ber_length_encode(65536), hb("83010000")) { ok = false; }
  if !bytes_equal(ber_length_encode(-1), Vec[UInt8].new()) { ok = false; }
  if !bytes_equal(ber_int_encode(0), hb("020100")) { ok = false; }
  if !bytes_equal(ber_int_encode(127), hb("02017f")) { ok = false; }
  if !bytes_equal(ber_int_encode(128), hb("02020080")) { ok = false; }
  if !bytes_equal(ber_int_encode(255), hb("020200ff")) { ok = false; }
  if !bytes_equal(ber_int_encode(256), hb("02020100")) { ok = false; }
  if !bytes_equal(ber_int_encode(-1), hb("0201ff")) { ok = false; }
  if !bytes_equal(ber_int_encode(-128), hb("020180")) { ok = false; }
  if !bytes_equal(ber_int_encode(-129), hb("0202ff7f")) { ok = false; }
  if !bytes_equal(ber_int_encode(-256), hb("0202ff00")) { ok = false; }
  var v = -300;
  while v <= 300 {
    let enc = ber_int_encode(v);
    if !bint_is(ber_int_decode(&enc, 0), v) { ok = false; }
    v = v + 7;
  }
  if !bytes_equal(ber_octet_string_encode(&bytes_of("abc")), hb("0403616263")) { ok = false; }
  let none = Vec[UInt8].new();
  if !bytes_equal(ber_octet_string_encode(&none), hb("0400")) { ok = false; }
  if !bytes_equal(ber_octet_string_encode(&hb("00ff4100")), hb("040400ff4100")) { ok = false; }
  if !bytes_equal(ber_bool_encode(true), hb("0101ff")) { ok = false; }
  if !bytes_equal(ber_bool_encode(false), hb("010100")) { ok = false; }
  if !bytes_equal(ber_enum_encode(2), hb("0a0102")) { ok = false; }
  if !bytes_equal(ber_enum_encode(128), hb("0a020080")) { ok = false; }
  if !bytes_equal(ber_tlv_wrap(163, hb("040161")), hb("a303040161")) { ok = false; }
  return assert(ok, "BER encode: pinned length/INTEGER/OCTET STRING/BOOLEAN/ENUM/wrap bytes and round-trip");
}

fn t7() -> TestResult {
  let pw = Vec[UInt8].new();
  let br = ldap_bind_request_encode(3, "", &pw);
  if !br.is_ok {
    return assert(false, "empty simple bind must encode");
  }
  let op: Vec[UInt8] = br.value;
  let mr = ldap_message_encode(5, &op);
  if !mr.is_ok {
    return assert(false, "message wrap must encode");
  }
  let msg: Vec[UInt8] = mr.value;
  var ok = true;
  let pr = ldap_message_parse(&msg);
  if !pr.is_ok {
    return assert(false, "encoded message must parse");
  }
  let m: LdapMessage = pr.value;
  if m.message_id != 5 { ok = false; }
  if m.op_tag != LDAP_OP_BIND_REQUEST { ok = false; }
  if m.op_offset != 5 { ok = false; }
  if m.op_length != op.len() { ok = false; }
  if m.next != msg.len() { ok = false; }
  if m.has_controls { ok = false; }
  let bp = ldap_bind_request_parse(&msg, m.op_offset);
  if !bp.is_ok {
    ok = false;
  } else {
    let b: LdapBindRequest = bp.value;
    if b.version != 3 { ok = false; }
  }
  let ctl = wrap(160, wrap(48, oct("1.2.3")));
  let msg2 = wrap(48, concat3(ber_int_encode(2), hb("4200"), ctl));
  let pr2 = ldap_message_parse(&msg2);
  if !pr2.is_ok {
    ok = false;
  } else {
    let m2: LdapMessage = pr2.value;
    if !m2.has_controls { ok = false; }
    if m2.controls_offset != 7 { ok = false; }
    if m2.controls_length != ctl.len() { ok = false; }
    if m2.next != msg2.len() { ok = false; }
  }
  if !ldap_op_tag_known(LDAP_OP_BIND_REQUEST) { ok = false; }
  if ldap_op_tag_known(95) { ok = false; }
  if !str_eq(ldap_op_tag_name(LDAP_OP_BIND_REQUEST), "BindRequest") { ok = false; }
  if !str_eq(ldap_op_tag_name(200), "unknown") { ok = false; }
  let empty = Vec[UInt8].new();
  if !err_msg_is(ldap_message_parse(&empty), eat("ber: truncated tag", 0)) { ok = false; }
  if !err_msg_is(ldap_message_parse(&hb("020101")), eat("ber: tag mismatch", 0)) { ok = false; }
  let neg = wrap(48, concat2(ber_int_encode(-1), hb("4200")));
  if !err_msg_is(ldap_message_parse(&neg), eat("ldap: negative message id", 2)) { ok = false; }
  let badop = wrap(48, concat2(ber_int_encode(1), wrap(143, Vec[UInt8].new())));
  if !err_msg_is(ldap_message_parse(&badop), eat("ldap: bad protocol op", 5)) { ok = false; }
  let trail = wrap(48, concat3(ber_int_encode(1), hb("4200"), hb("0500")));
  if !err_msg_is(ldap_message_parse(&trail), eat("ldap: trailing bytes", 7)) { ok = false; }
  if !err_msg_is(ldap_message_parse(&hb("30050201014202aabb")), eat("ber: value overruns container", 5)) { ok = false; }
  let noint = wrap(48, hb("4200"));
  if !err_msg_is(ldap_message_parse(&noint), eat("ber: tag mismatch", 2)) { ok = false; }
  return assert(ok, "LDAPMessage: framing, offsets, controls capture, bad id/op/trailing/overrun");
}

fn t8() -> TestResult {
  let name = "cn=admin,dc=example,dc=com";
  let pw = hb("00ff4100");
  let op = wrap(96, concat4(ber_int_encode(3), oct(name), wrap(128, pw), Vec[UInt8].new()));
  let r = ldap_bind_request_parse(&op, 0);
  if !r.is_ok {
    return assert(false, "simple bind must parse");
  }
  let b: LdapBindRequest = r.value;
  var ok = b.version == 3;
  if !str_eq(b.name, name) { ok = false; }
  if b.auth_tag != LDAP_AUTH_SIMPLE { ok = false; }
  if b.sasl_present { ok = false; }
  if !str_eq(b.mechanism, "") { ok = false; }
  let ab: Vec[UInt8] = b.auth_bytes;
  if !bytes_equal(ab, pw) { ok = false; }
  if b.next != op.len() { ok = false; }
  let anon = wrap(96, concat3(ber_int_encode(3), hb("0400"), hb("8000")));
  let ra = ldap_bind_request_parse(&anon, 0);
  if !ra.is_ok {
    ok = false;
  } else {
    let ab2: LdapBindRequest = ra.value;
    if !str_eq(ab2.name, "") { ok = false; }
    let anb: Vec[UInt8] = ab2.auth_bytes;
    if anb.len() != 0 { ok = false; }
  }
  let badver = wrap(96, concat3(ber_int_encode(0), hb("0400"), hb("8000")));
  if !err_bind_is(ldap_bind_request_parse(&badver, 0), eat("ldap: bad bind version", 2)) { ok = false; }
  let badauth = wrap(96, concat3(ber_int_encode(3), hb("0400"), wrap(129, Vec[UInt8].new())));
  if !err_bind_is(ldap_bind_request_parse(&badauth, 0), eat("ldap: bad authentication", 7)) { ok = false; }
  let badname = wrap(96, concat3(ber_int_encode(3), wrap(4, hb("0102")), hb("8000")));
  if !err_bind_is(ldap_bind_request_parse(&badname, 0), eat("ldap: non-printable string", 5)) { ok = false; }
  let trail = wrap(96, concat2(concat3(ber_int_encode(3), hb("0400"), hb("8000")), hb("0500")));
  if !err_bind_is(ldap_bind_request_parse(&trail, 0), eat("ldap: trailing bytes", 9)) { ok = false; }
  return assert(ok, "BindRequest simple: version/name/raw password bytes, anonymous, version/name/auth/trailing errors");
}

fn t9() -> TestResult {
  let sasl = concat2(oct("GSSAPI"), oct_b(hb("010203")));
  let op = wrap(96, concat3(ber_int_encode(3), oct("cn=x"), wrap(163, sasl)));
  let r = ldap_bind_request_parse(&op, 0);
  if !r.is_ok {
    return assert(false, "SASL bind placeholder must parse");
  }
  let b: LdapBindRequest = r.value;
  var ok = b.sasl_present;
  if b.auth_tag != LDAP_AUTH_SASL { ok = false; }
  if !str_eq(b.mechanism, "GSSAPI") { ok = false; }
  let ab: Vec[UInt8] = b.auth_bytes;
  if !bytes_equal(ab, hb("010203")) { ok = false; }
  let op2 = wrap(96, concat3(ber_int_encode(3), oct("cn=x"), wrap(163, oct("EXTERNAL"))));
  let r2 = ldap_bind_request_parse(&op2, 0);
  if !r2.is_ok {
    ok = false;
  } else {
    let b2: LdapBindRequest = r2.value;
    if !str_eq(b2.mechanism, "EXTERNAL") { ok = false; }
    let ab2: Vec[UInt8] = b2.auth_bytes;
    if ab2.len() != 0 { ok = false; }
  }
  let badmech = wrap(96, concat3(ber_int_encode(3), oct("cn=x"), wrap(163, wrap(5, Vec[UInt8].new()))));
  if !err_bind_is(ldap_bind_request_parse(&badmech, 0), eat("ber: tag mismatch", 13)) { ok = false; }
  let badauth = wrap(96, concat3(ber_int_encode(3), oct("cn=x"), wrap(130, Vec[UInt8].new())));
  if !err_bind_is(ldap_bind_request_parse(&badauth, 0), eat("ldap: bad authentication", 11)) { ok = false; }
  let sasltrail = wrap(163, concat2(concat2(oct("PLAIN"), oct_b(hb("61"))), hb("00")));
  let optrail = wrap(96, concat3(ber_int_encode(3), oct("cn=x"), sasltrail));
  if !err_bind_is(ldap_bind_request_parse(&optrail, 0), eat("ldap: trailing bytes", 23)) { ok = false; }
  return assert(ok, "BindRequest SASL placeholder: mechanism, credentials, tag/trailing errors");
}

fn t10() -> TestResult {
  var ok = str_eq(ldap_result_code_name(0), "success");
  if !str_eq(ldap_result_code_name(49), "invalidCredentials") { ok = false; }
  if !str_eq(ldap_result_code_name(80), "other") { ok = false; }
  if !str_eq(ldap_result_code_name(118), "canceled") { ok = false; }
  if !str_eq(ldap_result_code_name(123), "authorizationDenied") { ok = false; }
  if !str_eq(ldap_result_code_name(4096), "syncRefreshRequired") { ok = false; }
  if !str_eq(ldap_result_code_name(37), "reserved") { ok = false; }
  if !str_eq(ldap_result_code_name(200), "unknown") { ok = false; }
  if !ldap_result_code_known(49) { ok = false; }
  if ldap_result_code_known(37) { ok = false; }
  if ldap_result_code_known(200) { ok = false; }
  let resp = wrap(97, concat3(ber_enum_encode(0), oct(""), oct("")));
  let r = ldap_bind_response_parse(&resp, 0);
  if !r.is_ok {
    return assert(false, "empty success BindResponse must parse");
  }
  let res: LdapResult = r.value;
  if res.result_code != 0 { ok = false; }
  if !str_eq(res.matched_dn, "") { ok = false; }
  if !str_eq(res.diagnostic, "") { ok = false; }
  if res.has_referral { ok = false; }
  if res.has_sasl_creds { ok = false; }
  if res.next != resp.len() { ok = false; }
  let withref = wrap(97, concat2(concat3(ber_enum_encode(10), oct("dc=x"), oct("refer")), wrap(163, concat2(oct("ldap://a/"), oct("ldap://b/")))));
  let rr = ldap_bind_response_parse(&withref, 0);
  if !rr.is_ok {
    ok = false;
  } else {
    let res2: LdapResult = rr.value;
    if res2.result_code != 10 { ok = false; }
    if !str_eq(res2.matched_dn, "dc=x") { ok = false; }
    if !str_eq(res2.diagnostic, "refer") { ok = false; }
    if !res2.has_referral { ok = false; }
    let refs: Vec[Str] = res2.referrals;
    if refs.len() != 2 { ok = false; }
    let u0: Str = refs[0];
    let u1: Str = refs[1];
    if !str_eq(u0, "ldap://a/") { ok = false; }
    if !str_eq(u1, "ldap://b/") { ok = false; }
  }
  let creds = wrap(97, concat2(concat3(ber_enum_encode(14), oct(""), oct("")), wrap(135, hb("aabb"))));
  let cr = ldap_bind_response_parse(&creds, 0);
  if !cr.is_ok {
    ok = false;
  } else {
    let res3: LdapResult = cr.value;
    if res3.result_code != 14 { ok = false; }
    if !res3.has_sasl_creds { ok = false; }
    let sc: Vec[UInt8] = res3.sasl_creds;
    if !bytes_equal(sc, hb("aabb")) { ok = false; }
  }
  let negcode = wrap(97, concat3(ber_enum_encode(-1), oct(""), oct("")));
  if !err_result_is(ldap_bind_response_parse(&negcode, 0), eat("ldap: negative result code", 2)) { ok = false; }
  let trail = wrap(97, concat2(concat3(ber_enum_encode(0), oct(""), oct("")), hb("0500")));
  if !err_result_is(ldap_bind_response_parse(&trail, 0), eat("ldap: trailing bytes", 9)) { ok = false; }
  let wrongtag = wrap(101, concat3(ber_enum_encode(0), oct(""), oct("")));
  if !err_result_is(ldap_bind_response_parse(&wrongtag, 0), eat("ber: tag mismatch", 0)) { ok = false; }
  let plain = ldap_result_parse(&wrongtag, 0);
  if !plain.is_ok { ok = false; }
  return assert(ok, "results: result-code table names, matchedDN/diagnostic, referral, saslCreds, errors");
}

fn t11() -> TestResult {
  let filt = eq_f("cn", "admin");
  let attrs = wrap(48, concat2(oct("cn"), oct("mail")));
  let tail = concat2(concat3(ber_int_encode(500), ber_int_encode(30), ber_bool_encode(false)), concat2(filt, attrs));
  let head = concat3(oct("dc=example,dc=com"), ber_enum_encode(2), ber_enum_encode(0));
  let op = wrap(99, concat2(head, tail));
  let r = ldap_search_request_parse(&op, 0);
  if !r.is_ok {
    return assert(false, "search request must parse");
  }
  let sr: LdapSearchRequest = r.value;
  var ok = sr.scope == 2;
  if !str_eq(sr.base_object, "dc=example,dc=com") { ok = false; }
  if sr.deref_aliases != 0 { ok = false; }
  if sr.size_limit != 500 { ok = false; }
  if sr.time_limit != 30 { ok = false; }
  if sr.types_only { ok = false; }
  if sr.attributes.len() != 2 { ok = false; }
  let a0: Str = sr.attributes[0];
  let a1: Str = sr.attributes[1];
  if !str_eq(a0, "cn") { ok = false; }
  if !str_eq(a1, "mail") { ok = false; }
  if sr.filter_offset != 37 { ok = false; }
  if sr.filter_length != filt.len() { ok = false; }
  let f: LdapFilter = sr.filter;
  if f.kinds.len() != 1 { ok = false; }
  let k0: Int = f.kinds[0];
  if k0 != LDAP_FILTER_KIND_EQUALITY { ok = false; }
  let fa: Str = f.attrs[0];
  if !str_eq(fa, "cn") { ok = false; }
  let vo: Int = f.val_offsets[0];
  let vl: Int = f.val_lengths[0];
  let vb: Vec[UInt8] = ldap_bytes_copy(&op, vo, vl);
  if !bytes_equal(vb, bytes_of("admin")) { ok = false; }
  if sr.next != op.len() { ok = false; }
  let badscope = wrap(99, concat2(concat3(oct("dc=example,dc=com"), ber_enum_encode(3), ber_enum_encode(0)), tail));
  if !err_search_is(ldap_search_request_parse(&badscope, 0), eat("ldap: bad scope", 21)) { ok = false; }
  let badderef = wrap(99, concat2(concat3(oct("dc=example,dc=com"), ber_enum_encode(2), ber_enum_encode(4)), tail));
  if !err_search_is(ldap_search_request_parse(&badderef, 0), eat("ldap: bad deref aliases", 24)) { ok = false; }
  let negsize = concat2(concat3(ber_int_encode(-1), ber_int_encode(30), ber_bool_encode(false)), concat2(filt, attrs));
  let badsize = wrap(99, concat2(concat3(oct("dc=example,dc=com"), ber_enum_encode(2), ber_enum_encode(0)), negsize));
  if !err_search_is(ldap_search_request_parse(&badsize, 0), eat("ldap: negative integer", 27)) { ok = false; }
  let badattrs = wrap(48, concat2(oct("cn"), hb("0500")));
  let badattrreq = wrap(99, concat2(head, concat2(concat3(ber_int_encode(500), ber_int_encode(30), ber_bool_encode(false)), concat2(filt, badattrs))));
  if !err_search_is(ldap_search_request_parse(&badattrreq, 0), eat("ber: tag mismatch", 56)) { ok = false; }
  return assert(ok, "SearchRequest: fields, embedded flat filter, attributes, scope/deref/limit/attr errors");
}

fn t12() -> TestResult {
  let eq = eq_f("cn", "alice");
  let pres = present_f("objectClass");
  let andb = wrap(160, concat2(eq, pres));
  let r = ldap_filter_parse(&andb, 0);
  if !r.is_ok {
    return assert(false, "and filter must parse");
  }
  let f: LdapFilter = r.value;
  var ok = f.kinds.len() == 3;
  let k0: Int = f.kinds[0];
  let k1: Int = f.kinds[1];
  let k2: Int = f.kinds[2];
  if k0 != LDAP_FILTER_KIND_AND { ok = false; }
  if k1 != LDAP_FILTER_KIND_EQUALITY { ok = false; }
  if k2 != LDAP_FILTER_KIND_PRESENT { ok = false; }
  let p0: Int = f.parents[0];
  let p1: Int = f.parents[1];
  let p2: Int = f.parents[2];
  if p0 != -1 { ok = false; }
  if p1 != 0 { ok = false; }
  if p2 != 0 { ok = false; }
  let d1: Int = f.depths[1];
  let d2: Int = f.depths[2];
  if d1 != 1 { ok = false; }
  if d2 != 1 { ok = false; }
  let fc: Int = f.first_child[0];
  let cc: Int = f.child_count[0];
  if fc != 1 { ok = false; }
  if cc != 2 { ok = false; }
  let a1: Str = f.attrs[1];
  let a2: Str = f.attrs[2];
  if !str_eq(a1, "cn") { ok = false; }
  if !str_eq(a2, "objectClass") { ok = false; }
  let vo: Int = f.val_offsets[1];
  let vl: Int = f.val_lengths[1];
  let vb: Vec[UInt8] = ldap_bytes_copy(&andb, vo, vl);
  if !bytes_equal(vb, bytes_of("alice")) { ok = false; }
  let vl2: Int = f.val_lengths[2];
  if vl2 != 0 { ok = false; }
  if f.next != andb.len() { ok = false; }
  let orb = wrap(161, concat2(pres, present_f("sn")));
  let ro = ldap_filter_parse(&orb, 0);
  if !ro.is_ok {
    ok = false;
  } else {
    let fo: LdapFilter = ro.value;
    let ko: Int = fo.kinds[0];
    if ko != LDAP_FILTER_KIND_OR { ok = false; }
  }
  let nb = wrap(162, eq);
  let rn = ldap_filter_parse(&nb, 0);
  if !rn.is_ok {
    ok = false;
  } else {
    let fn2: LdapFilter = rn.value;
    let kn: Int = fn2.kinds[0];
    if kn != LDAP_FILTER_KIND_NOT { ok = false; }
    let cn2: Int = fn2.child_count[0];
    if cn2 != 1 { ok = false; }
    let dn2: Int = fn2.depths[1];
    if dn2 != 1 { ok = false; }
  }
  let geb = wrap(165, concat2(oct("age"), oct("21")));
  let rg = ldap_filter_parse(&geb, 0);
  if !rg.is_ok {
    ok = false;
  } else {
    let fg: LdapFilter = rg.value;
    let kg: Int = fg.kinds[0];
    if kg != LDAP_FILTER_KIND_GREATER_OR_EQUAL { ok = false; }
  }
  let leb = wrap(166, concat2(oct("age"), oct("21")));
  let rl = ldap_filter_parse(&leb, 0);
  if !rl.is_ok {
    ok = false;
  } else {
    let fl: LdapFilter = rl.value;
    let kl: Int = fl.kinds[0];
    if kl != LDAP_FILTER_KIND_LESS_OR_EQUAL { ok = false; }
  }
  let apb = wrap(168, concat2(oct("cn"), oct("jon")));
  let rap = ldap_filter_parse(&apb, 0);
  if !rap.is_ok {
    ok = false;
  } else {
    let fa: LdapFilter = rap.value;
    let ka: Int = fa.kinds[0];
    if ka != LDAP_FILTER_KIND_APPROX { ok = false; }
  }
  let andempty = wrap(160, Vec[UInt8].new());
  if !err_filter_is(ldap_filter_parse(&andempty, 0), eat("ldap: empty and/or filter", 0)) { ok = false; }
  let badtag = wrap(171, Vec[UInt8].new());
  if !err_filter_is(ldap_filter_parse(&badtag, 0), eat("ldap: bad filter tag", 0)) { ok = false; }
  let notempty = wrap(162, Vec[UInt8].new());
  if !err_filter_is(ldap_filter_parse(&notempty, 0), eat("ldap: bad not filter", 0)) { ok = false; }
  var chain = present_f("a");
  var i = 0;
  while i < 32 {
    chain = wrap(162, chain);
    i = i + 1;
  }
  let r32 = ldap_filter_parse(&chain, 0);
  if !r32.is_ok {
    ok = false;
  } else {
    let f32: LdapFilter = r32.value;
    if f32.kinds.len() != 33 { ok = false; }
    let dd: Int = f32.depths[32];
    if dd != 32 { ok = false; }
  }
  var chain33 = present_f("a");
  var j = 0;
  while j < 33 {
    chain33 = wrap(162, chain33);
    j = j + 1;
  }
  if !err_filter_is(ldap_filter_parse(&chain33, 0), eat("ldap: filter too deeply nested", 66)) { ok = false; }
  return assert(ok, "filters: flat tree parents/depths/children, and/or/not, ge/le/approx, depth cap, errors");
}

fn t13() -> TestResult {
  let parts = wrap(48, concat3(wrap(128, bytes_of("jo")), wrap(129, bytes_of("hn")), wrap(130, bytes_of("ny"))));
  let op = wrap(164, concat2(oct("cn"), parts));
  let r = ldap_filter_parse(&op, 0);
  if !r.is_ok {
    return assert(false, "substring filter must parse");
  }
  let f: LdapFilter = r.value;
  var ok = f.kinds.len() == 1;
  let k0: Int = f.kinds[0];
  if k0 != LDAP_FILTER_KIND_SUBSTRINGS { ok = false; }
  let a0: Str = f.attrs[0];
  if !str_eq(a0, "cn") { ok = false; }
  let sc: Int = f.sub_count[0];
  if sc != 3 { ok = false; }
  let sf: Int = f.sub_first[0];
  let pk0: Int = f.part_kinds[sf];
  let pk1: Int = f.part_kinds[sf + 1];
  let pk2: Int = f.part_kinds[sf + 2];
  if pk0 != LDAP_SUBSTR_INITIAL { ok = false; }
  if pk1 != LDAP_SUBSTR_ANY { ok = false; }
  if pk2 != LDAP_SUBSTR_FINAL { ok = false; }
  let po0: Int = f.part_offsets[sf];
  let pl0: Int = f.part_lengths[sf];
  if !bytes_equal(ldap_bytes_copy(&op, po0, pl0), bytes_of("jo")) { ok = false; }
  let po2: Int = f.part_offsets[sf + 2];
  let pl2: Int = f.part_lengths[sf + 2];
  if !bytes_equal(ldap_bytes_copy(&op, po2, pl2), bytes_of("ny")) { ok = false; }
  let bad1 = wrap(164, concat2(oct("cn"), wrap(48, concat2(wrap(129, bytes_of("a")), wrap(128, bytes_of("b"))))));
  if !err_filter_is(ldap_filter_parse(&bad1, 0), eat("ldap: bad substring filter", 11)) { ok = false; }
  let bad2 = wrap(164, concat2(oct("cn"), wrap(48, concat2(wrap(130, bytes_of("a")), wrap(129, bytes_of("b"))))));
  if !err_filter_is(ldap_filter_parse(&bad2, 0), eat("ldap: bad substring filter", 11)) { ok = false; }
  let bad3 = wrap(164, concat2(oct("cn"), wrap(48, Vec[UInt8].new())));
  if !err_filter_is(ldap_filter_parse(&bad3, 0), eat("ldap: bad substring filter", 0)) { ok = false; }
  let ext = wrap(169, concat2(concat3(wrap(129, bytes_of("caseIgnoreMatch")), wrap(130, bytes_of("cn")), wrap(131, hb("61"))), wrap(132, hb("ff"))));
  let re = ldap_filter_parse(&ext, 0);
  if !re.is_ok {
    ok = false;
  } else {
    let fe: LdapFilter = re.value;
    let ke: Int = fe.kinds[0];
    if ke != LDAP_FILTER_KIND_EXTENSIBLE { ok = false; }
    let rl: Str = fe.rules[0];
    let at: Str = fe.attrs[0];
    if !str_eq(rl, "caseIgnoreMatch") { ok = false; }
    if !str_eq(at, "cn") { ok = false; }
    let da: Int = fe.dn_attrs[0];
    if da != 1 { ok = false; }
    let vo: Int = fe.val_offsets[0];
    let vl: Int = fe.val_lengths[0];
    if !bytes_equal(ldap_bytes_copy(&ext, vo, vl), hb("61")) { ok = false; }
  }
  let ext2 = wrap(169, wrap(131, hb("78")));
  let re2 = ldap_filter_parse(&ext2, 0);
  if !re2.is_ok {
    ok = false;
  } else {
    let fe2: LdapFilter = re2.value;
    let rl2: Str = fe2.rules[0];
    let at2: Str = fe2.attrs[0];
    if !str_eq(rl2, "") { ok = false; }
    if !str_eq(at2, "") { ok = false; }
  }
  let ext3 = wrap(169, wrap(130, bytes_of("cn")));
  if !err_filter_is(ldap_filter_parse(&ext3, 0), eat("ldap: bad extensible match", 0)) { ok = false; }
  return assert(ok, "substrings parts and extensibleMatch: initial/any/final, rule/type/value/dnAttrs, errors");
}

fn t14() -> TestResult {
  let al = wrap(48, concat2(pt("cn", one("alice")), pt("mail", two("a@x", "b@y"))));
  let op = wrap(100, concat2(oct("cn=alice,dc=example"), al));
  let r = ldap_search_entry_parse(&op, 0);
  if !r.is_ok {
    return assert(false, "search entry must parse");
  }
  let e: LdapSearchEntry = r.value;
  var ok = str_eq(e.object_name, "cn=alice,dc=example");
  let attrs: LdapAttributeList = e.attrs;
  if attrs.names.len() != 2 { ok = false; }
  let n0: Str = attrs.names[0];
  let n1: Str = attrs.names[1];
  if !str_eq(n0, "cn") { ok = false; }
  if !str_eq(n1, "mail") { ok = false; }
  let c0: Int = attrs.value_count[0];
  let c1: Int = attrs.value_count[1];
  if c0 != 1 { ok = false; }
  if c1 != 2 { ok = false; }
  let f1: Int = attrs.first_value[1];
  if f1 != 1 { ok = false; }
  let vo: Int = attrs.value_offsets[f1];
  let vl: Int = attrs.value_lengths[f1];
  if !bytes_equal(ldap_bytes_copy(&op, vo, vl), bytes_of("a@x")) { ok = false; }
  let vo2: Int = attrs.value_offsets[f1 + 1];
  let vl2: Int = attrs.value_lengths[f1 + 1];
  if !bytes_equal(ldap_bytes_copy(&op, vo2, vl2), bytes_of("b@y")) { ok = false; }
  if e.next != op.len() { ok = false; }
  let op2 = wrap(100, concat2(oct("cn=x"), wrap(48, Vec[UInt8].new())));
  let r2 = ldap_search_entry_parse(&op2, 0);
  if !r2.is_ok {
    ok = false;
  } else {
    let e2: LdapSearchEntry = r2.value;
    let a2: LdapAttributeList = e2.attrs;
    if a2.names.len() != 0 { ok = false; }
  }
  let bad1 = wrap(100, concat2(oct("x"), hb("0500")));
  if !err_entry_is(ldap_search_entry_parse(&bad1, 0), eat("ber: tag mismatch", 5)) { ok = false; }
  let bad2 = wrap(100, concat3(oct("x"), wrap(48, Vec[UInt8].new()), hb("0500")));
  if !err_entry_is(ldap_search_entry_parse(&bad2, 0), eat("ldap: trailing bytes", 7)) { ok = false; }
  return assert(ok, "SearchResultEntry: objectName, attribute values/offsets, empty list, errors");
}

fn t15() -> TestResult {
  let chs = wrap(48, concat2(change(0, "description", one("hi")), change(2, "mail", two("a@x", "b@y"))));
  let op = wrap(102, concat2(oct("cn=alice,dc=x"), chs));
  let r = ldap_modify_request_parse(&op, 0);
  if !r.is_ok {
    return assert(false, "modify request must parse");
  }
  let m: LdapModifyRequest = r.value;
  var ok = str_eq(m.object, "cn=alice,dc=x");
  let ch: LdapChanges = m.changes;
  if ch.ops.len() != 2 { ok = false; }
  let o0: Int = ch.ops[0];
  let o1: Int = ch.ops[1];
  if o0 != 0 { ok = false; }
  if o1 != 2 { ok = false; }
  let n1: Str = ch.names[1];
  if !str_eq(n1, "mail") { ok = false; }
  let c1: Int = ch.value_count[1];
  if c1 != 2 { ok = false; }
  let f1: Int = ch.first_value[1];
  let vo: Int = ch.value_offsets[f1 + 1];
  let vl: Int = ch.value_lengths[f1 + 1];
  if !bytes_equal(ldap_bytes_copy(&op, vo, vl), bytes_of("b@y")) { ok = false; }
  if m.next != op.len() { ok = false; }
  let badchange = wrap(48, concat2(ber_enum_encode(3), pt("cn", one("a"))));
  let badop = wrap(102, concat2(oct("x"), wrap(48, badchange)));
  if !err_modify_is(ldap_modify_request_parse(&badop, 0), eat("ldap: bad modify operation", 9)) { ok = false; }
  let badch = wrap(102, concat2(oct("x"), wrap(48, hb("0500"))));
  if !err_modify_is(ldap_modify_request_parse(&badch, 0), eat("ber: tag mismatch", 7)) { ok = false; }
  return assert(ok, "ModifyRequest: object, change ops/attrs/values, bad operation and non-SEQUENCE change");
}

fn t16() -> TestResult {
  let add = wrap(104, concat2(oct("cn=bob,dc=x"), wrap(48, concat2(pt("objectClass", two("top", "person")), pt("sn", one("B"))))));
  let ra = ldap_add_request_parse(&add, 0);
  var ok = ra.is_ok;
  if ra.is_ok {
    let a: LdapAddRequest = ra.value;
    if !str_eq(a.entry, "cn=bob,dc=x") { ok = false; }
    let aa: LdapAttributeList = a.attrs;
    if aa.names.len() != 2 { ok = false; }
    let n0: Str = aa.names[0];
    if !str_eq(n0, "objectClass") { ok = false; }
    let c0: Int = aa.value_count[0];
    if c0 != 2 { ok = false; }
  }
  let del = wrap(74, bytes_of("cn=bob,dc=x"));
  if !lstr_is(ldap_del_request_parse(&del, 0), "cn=bob,dc=x", del.len()) { ok = false; }
  let delbad = wrap(74, hb("0102"));
  if !err_lstr_is(ldap_del_request_parse(&delbad, 0), eat("ldap: non-printable string", 0)) { ok = false; }
  let deltag = wrap(76, bytes_of("x"));
  if !err_lstr_is(ldap_del_request_parse(&deltag, 0), eat("ber: tag mismatch", 0)) { ok = false; }
  let md = wrap(108, concat4(oct("cn=a,dc=x"), oct("cn=b"), hb("0101ff"), wrap(128, bytes_of("ou=people,dc=x"))));
  let rm = ldap_modify_dn_request_parse(&md, 0);
  if !rm.is_ok {
    ok = false;
  } else {
    let m: LdapModifyDnRequest = rm.value;
    if !str_eq(m.entry, "cn=a,dc=x") { ok = false; }
    if !str_eq(m.new_rdn, "cn=b") { ok = false; }
    if !m.delete_old_rdn { ok = false; }
    if !m.has_new_superior { ok = false; }
    if !str_eq(m.new_superior, "ou=people,dc=x") { ok = false; }
  }
  let md2 = wrap(108, concat3(oct("cn=a,dc=x"), oct("cn=b"), hb("010100")));
  let rm2 = ldap_modify_dn_request_parse(&md2, 0);
  if !rm2.is_ok {
    ok = false;
  } else {
    let m2: LdapModifyDnRequest = rm2.value;
    if m2.delete_old_rdn { ok = false; }
    if m2.has_new_superior { ok = false; }
  }
  let mdtrail = wrap(108, concat4(oct("cn=a,dc=x"), oct("cn=b"), hb("010100"), hb("0500")));
  if !err_moddn_is(ldap_modify_dn_request_parse(&mdtrail, 0), eat("ldap: trailing bytes", 22)) { ok = false; }
  let cmp = wrap(110, concat2(oct("cn=a,dc=x"), wrap(48, concat2(oct("cn"), oct_b(hb("4142"))))));
  let rc = ldap_compare_request_parse(&cmp, 0);
  if !rc.is_ok {
    ok = false;
  } else {
    let c: LdapCompareRequest = rc.value;
    if !str_eq(c.entry, "cn=a,dc=x") { ok = false; }
    if !str_eq(c.attr, "cn") { ok = false; }
    let vb: Vec[UInt8] = ldap_bytes_copy(&cmp, c.value_offset, c.value_length);
    if !bytes_equal(vb, hb("4142")) { ok = false; }
  }
  let cmpbad = wrap(110, concat2(oct("cn=a"), wrap(4, oct("cn"))));
  if !err_compare_is(ldap_compare_request_parse(&cmpbad, 0), eat("ber: tag mismatch", 8)) { ok = false; }
  return assert(ok, "Add/Del/ModifyDN/Compare: entries, attrs, newSuperior, raw assertion values, errors");
}

fn t17() -> TestResult {
  let ra = ldap_abandon_request_parse(&hb("500107"), 0);
  var ok = ra.is_ok;
  if ra.is_ok {
    let v: Int = ra.value;
    if v != 7 { ok = false; }
  }
  if !err_int_is(ldap_abandon_request_parse(&hb("50020007"), 0), eat("ber: non-minimal integer", 0)) { ok = false; }
  if !err_int_is(ldap_abandon_request_parse(&hb("5001ff"), 0), eat("ldap: negative abandon id", 0)) { ok = false; }
  if !err_int_is(ldap_abandon_request_parse(&hb("5000"), 0), eat("ber: empty integer", 0)) { ok = false; }
  if !err_int_is(ldap_abandon_request_parse(&hb("4100"), 0), eat("ber: tag mismatch", 0)) { ok = false; }
  let ub = hb("4200");
  let ru = ldap_unbind_request_parse(&ub, 0);
  if !ru.is_ok {
    ok = false;
  } else {
    let n: Int = ru.value;
    if n != 2 { ok = false; }
  }
  if !err_int_is(ldap_unbind_request_parse(&hb("420100"), 0), eat("ldap: bad unbind", 0)) { ok = false; }
  if !err_int_is(ldap_unbind_request_parse(&hb("4300"), 0), eat("ber: tag mismatch", 0)) { ok = false; }
  let ref = wrap(115, concat2(oct("ldap://a/"), oct("ldap://b/")));
  let rr = ldap_search_reference_parse(&ref, 0);
  if !rr.is_ok {
    ok = false;
  } else {
    let s: LdapSearchReference = rr.value;
    let u: Vec[Str] = s.uris;
    if u.len() != 2 {
      ok = false;
    } else {
      let u0: Str = u[0];
      let u1: Str = u[1];
      if !str_eq(u0, "ldap://a/") { ok = false; }
      if !str_eq(u1, "ldap://b/") { ok = false; }
    }
  }
  let refbad = wrap(115, Vec[UInt8].new());
  if !err_ref_is(ldap_search_reference_parse(&refbad, 0), eat("ldap: empty search reference", 0)) { ok = false; }
  let ext = wrap(119, concat2(wrap(128, bytes_of("1.3.6.1.4.1.1466.20037")), wrap(129, hb("0102"))));
  let re = ldap_extended_request_parse(&ext, 0);
  if !re.is_ok {
    ok = false;
  } else {
    let e: LdapExtendedRequest = re.value;
    if !str_eq(e.request_name, "1.3.6.1.4.1.1466.20037") { ok = false; }
    if !e.has_value { ok = false; }
    let vb: Vec[UInt8] = ldap_bytes_copy(&ext, e.value_offset, e.value_length);
    if !bytes_equal(vb, hb("0102")) { ok = false; }
  }
  let extbad = wrap(119, Vec[UInt8].new());
  if !err_ext_is(ldap_extended_request_parse(&extbad, 0), eat("ldap: bad extended request", 2)) { ok = false; }
  let eresp = wrap(120, concat3(concat3(ber_enum_encode(0), oct(""), oct("")), wrap(138, bytes_of("1.2.3")), wrap(139, hb("aabb"))));
  let re2 = ldap_extended_response_parse(&eresp, 0);
  if !re2.is_ok {
    ok = false;
  } else {
    let res: LdapResult = re2.value;
    if res.result_code != 0 { ok = false; }
    if !res.has_response_name { ok = false; }
    if !str_eq(res.response_name, "1.2.3") { ok = false; }
    if !res.has_response_value { ok = false; }
    let rv: Vec[UInt8] = res.response_value;
    if !bytes_equal(rv, hb("aabb")) { ok = false; }
  }
  let erbad = wrap(120, concat2(concat3(ber_enum_encode(0), oct(""), oct("")), hb("0500")));
  if !err_result_is(ldap_extended_response_parse(&erbad, 0), eat("ldap: trailing bytes", 9)) { ok = false; }
  return assert(ok, "Abandon/Unbind/SearchReference/ExtendedRequest/ExtendedResponse: parsing and errors");
}

fn t18() -> TestResult {
  let pw0 = Vec[UInt8].new();
  let r0 = ldap_bind_request_encode(3, "", &pw0);
  if !r0.is_ok {
    return assert(false, "minimal bind encode must succeed");
  }
  let b0: Vec[UInt8] = r0.value;
  var ok = bytes_equal(b0, hb("600702010304008000"));
  let name = "cn=admin,dc=example,dc=com";
  let pw = hb("00ff41");
  let r1 = ldap_bind_request_encode(3, name, &pw);
  if !r1.is_ok {
    ok = false;
  } else {
    let b1: Vec[UInt8] = r1.value;
    let pr = ldap_bind_request_parse(&b1, 0);
    if !pr.is_ok {
      ok = false;
    } else {
      let b: LdapBindRequest = pr.value;
      if b.version != 3 { ok = false; }
      if !str_eq(b.name, name) { ok = false; }
      let ab: Vec[UInt8] = b.auth_bytes;
      if !bytes_equal(ab, pw) { ok = false; }
      let rb = ldap_bind_request_encode(b.version, b.name, &ab);
      if !rb.is_ok {
        ok = false;
      } else {
        let rb2: Vec[UInt8] = rb.value;
        if !bytes_equal(rb2, b1) { ok = false; }
      }
    }
    let msg = ldap_message_encode(42, &b1);
    if !msg.is_ok {
      ok = false;
    } else {
      let mv: Vec[UInt8] = msg.value;
      let mp = ldap_message_parse(&mv);
      if !mp.is_ok {
        ok = false;
      } else {
        let m: LdapMessage = mp.value;
        if m.message_id != 42 { ok = false; }
        if m.op_tag != LDAP_OP_BIND_REQUEST { ok = false; }
      }
    }
  }
  if !err_bytes_is(ldap_bind_request_encode(0, "", &pw0), "ldap: bad bind version") { ok = false; }
  if !err_bytes_is(ldap_bind_request_encode(128, "", &pw0), "ldap: bad bind version") { ok = false; }
  if !err_bytes_is(ldap_bind_request_encode(3, "a\tb", &pw0), "ldap: non-printable string") { ok = false; }
  return assert(ok, "BindRequest encode: pinned minimal bytes, parse/re-encode round-trip, version/name errors");
}

fn t19() -> TestResult {
  let attrs = two("cn", "mail");
  let val = bytes_of("admin");
  let r = ldap_search_request_encode("dc=example,dc=com", 2, 0, 500, 30, false, "cn", &val, &attrs);
  if !r.is_ok {
    return assert(false, "search encode must succeed");
  }
  let op: Vec[UInt8] = r.value;
  let pr = ldap_search_request_parse(&op, 0);
  if !pr.is_ok {
    return assert(false, "encoded search must parse");
  }
  let sr: LdapSearchRequest = pr.value;
  var ok = sr.scope == 2;
  if !str_eq(sr.base_object, "dc=example,dc=com") { ok = false; }
  if sr.deref_aliases != 0 { ok = false; }
  if sr.size_limit != 500 { ok = false; }
  if sr.time_limit != 30 { ok = false; }
  if sr.types_only { ok = false; }
  if sr.attributes.len() != 2 { ok = false; }
  let a1: Str = sr.attributes[1];
  if !str_eq(a1, "mail") { ok = false; }
  let f: LdapFilter = sr.filter;
  let k0: Int = f.kinds[0];
  if k0 != LDAP_FILTER_KIND_EQUALITY { ok = false; }
  let fa: Str = f.attrs[0];
  if !str_eq(fa, "cn") { ok = false; }
  let vo: Int = f.val_offsets[0];
  let vl: Int = f.val_lengths[0];
  if !bytes_equal(ldap_bytes_copy(&op, vo, vl), val) { ok = false; }
  let ab: Vec[Str] = sr.attributes;
  let vb2: Vec[UInt8] = ldap_bytes_copy(&op, vo, vl);
  let r2 = ldap_search_request_encode(sr.base_object, sr.scope, sr.deref_aliases, sr.size_limit, sr.time_limit, sr.types_only, fa, &vb2, &ab);
  if !r2.is_ok {
    ok = false;
  } else {
    let op2: Vec[UInt8] = r2.value;
    if !bytes_equal(op2, op) { ok = false; }
  }
  let msg = ldap_message_encode(9, &op);
  if !msg.is_ok {
    ok = false;
  } else {
    let mv: Vec[UInt8] = msg.value;
    let mp = ldap_message_parse(&mv);
    if !mp.is_ok {
      ok = false;
    } else {
      let m: LdapMessage = mp.value;
      if m.message_id != 9 { ok = false; }
      if m.op_tag != LDAP_OP_SEARCH_REQUEST { ok = false; }
    }
  }
  if !err_bytes_is(ldap_search_request_encode("x", 3, 0, 0, 0, false, "cn", &val, &attrs), "ldap: bad scope") { ok = false; }
  if !err_bytes_is(ldap_search_request_encode("x", 0, 4, 0, 0, false, "cn", &val, &attrs), "ldap: bad deref aliases") { ok = false; }
  if !err_bytes_is(ldap_search_request_encode("x", 0, 0, -1, 0, false, "cn", &val, &attrs), "ldap: negative integer") { ok = false; }
  return assert(ok, "SearchRequest encode: equality filter, parse round-trip, re-encode byte-identical, errors");
}

fn t20() -> TestResult {
  var ok = true;
  if !err_msg_is(ldap_message_parse(&hb("30")), eat("ber: truncated length", 1)) { ok = false; }
  if !err_msg_is(ldap_message_parse(&hb("3003020101")), eat("ber: truncated tag", 5)) { ok = false; }
  if !err_msg_is(ldap_message_parse(&hb("30050201014202aabb")), eat("ber: value overruns container", 5)) { ok = false; }
  let filt = eq_f("cn", "x");
  let attrs = wrap(48, oct("cn"));
  let sr_content = concat2(concat3(oct("dc=x"), ber_enum_encode(2), ber_enum_encode(0)), concat2(concat3(ber_int_encode(0), ber_int_encode(0), ber_bool_encode(false)), concat2(filt, attrs)));
  let good = wrap(99, sr_content);
  let rg = ldap_search_request_parse(&good, 0);
  if !rg.is_ok { ok = false; }
  let trail = wrap(99, concat2(sr_content, hb("00")));
  if !err_search_is(ldap_search_request_parse(&trail, 0), eat("ldap: trailing bytes", 38)) { ok = false; }
  let badfilter = wrap(171, Vec[UInt8].new());
  let badfilt = wrap(99, concat2(concat3(oct("dc=x"), ber_enum_encode(2), ber_enum_encode(0)), concat2(concat3(ber_int_encode(0), ber_int_encode(0), ber_bool_encode(false)), concat2(badfilter, attrs))));
  if !err_search_is(ldap_search_request_parse(&badfilt, 0), eat("ldap: bad filter tag", 23)) { ok = false; }
  let badset = wrap(100, concat2(oct("x"), wrap(48, wrap(48, concat2(oct("cn"), wrap(48, oct("a")))))));
  if !err_entry_is(ldap_search_entry_parse(&badset, 0), eat("ber: tag mismatch", 13)) { ok = false; }
  let emptybuf = Vec[UInt8].new();
  if !err_filter_is(ldap_filter_parse(&emptybuf, 0), eat("ber: truncated tag", 0)) { ok = false; }
  return assert(ok, "malformed/trailing: truncated TLVs, container overrun, exact trailing-byte offsets");
}

fn main() -> Int {
  io.println("=== xiom.ldap conformance tests ===");
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
    io.println("xiom.ldap: all tests passed");
  } else {
    io.println("xiom.ldap: tests failed");
  }
  return failed;
}
