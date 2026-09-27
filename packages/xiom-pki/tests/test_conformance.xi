// XIOM -- xiom.pki conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every DER fixture is built in-test from small typed helpers; there are no
// external files. Covers: length forms (short/long/minimal/indefinite/
// truncated/overflow), tag classes, constructed bits, the high-tag-number
// form, container-bounded walking, BOOLEAN/INTEGER/BIT STRING/OCTET STRING/
// NULL/OID/string/time primitives and their error offsets, a minimal v1
// certificate, a fully loaded v3 certificate (basicConstraints, keyUsage,
// extKeyUsage, subjectAltName, subjectKeyIdentifier, authorityKeyIdentifier,
// unknown extension), RDN structure including multi-valued RDNs, version and
// serial variants, malformed certificates, and the PEM unwrap catalog.
//
// Discipline: Str equality goes through str_compare (BUG 17), every byte
// read from a Vec of UInt8 is widened with `(x as Int) & 0xFF`, no `==` on
// Str values read out of vectors, no shifts, no `match`.

module pki_tests
use xiom.io; use xiom.test; use xiom.pki;
use xiom.string; use xiom.string.compare; use xiom.string.builder;

// --------------------------------------------------
//  Comparison helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn has_prefix(s: Str, p: Str) -> Bool {
  if p.len() > s.len() {
    return false;
  }
  let head = string.str_slice(s, 0, p.len());
  return streq(head, p);
}

// True when a Result-ish pair is Err with exactly `want`.
fn bad_is(ok: Bool, msg: Str, want: Str) -> Bool {
  if ok {
    return false;
  }
  return streq(msg, want);
}

// True when a Result-ish pair is Err with a message starting with `prefix`.
fn bad_prefix(ok: Bool, msg: Str, prefix: Str) -> Bool {
  if ok {
    return false;
  }
  return has_prefix(msg, prefix);
}

// "`msg` at offset N" (mirrors the library's error rendering).
fn at(msg: Str, off: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, msg);
  builder.sb_push_str(&mut sb, " at offset ");
  builder.sb_push_int(&mut sb, off);
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

fn str_bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn bvec(xs: Vec[Int]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < xs.len() {
    let x: Int = xs[i];
    out.push(x as UInt8);
    i = i + 1;
  }
  return out;
}

fn ints1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn b1(a: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  return v;
}

fn b2(a: Int, b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return v;
}

fn b3(a: Int, b: Int, c: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  return v;
}

fn b4(a: Int, b: Int, c: Int, d: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  v.push(d as UInt8);
  return v;
}

fn bytes_slice_is(v: Vec[UInt8], off: Int, want: Vec[UInt8]) -> Bool {
  if off < 0 || off + want.len() > v.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if (((v[off + i] as Int) & 0xFF) != ((want[i] as Int) & 0xFF)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  return bytes_slice_is(a, 0, b);
}

fn copy_bytes(v: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  DER builders
// --------------------------------------------------

fn push_len(out: &mut Vec[UInt8], n: Int) {
  if n < 128 {
    out.push(n as UInt8);
    return;
  }
  var low = Vec[UInt8].new();
  var q = n;
  while q > 0 {
    low.push((q % 256) as UInt8);
    q = q / 256;
  }
  out.push((128 + low.len()) as UInt8);
  var i = low.len() - 1;
  while i >= 0 {
    out.push(low[i]);
    i = i - 1;
  }
}

fn cat2(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = copy_bytes(a);
  var i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

fn tlv(tag: Int, content: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(tag as UInt8);
  push_len(&mut out, content.len());
  var i = 0;
  while i < content.len() {
    out.push(content[i]);
    i = i + 1;
  }
  return out;
}

// Minimal big-endian two's complement content bytes of a non-negative Int.
fn der_int_bytes(v: Int) -> Vec[UInt8] {
  var low = Vec[UInt8].new();
  if v <= 0 {
    low.push(0 as UInt8);
    return low;
  }
  var x = v;
  while x > 0 {
    low.push((x % 256) as UInt8);
    x = x / 256;
  }
  var out = Vec[UInt8].new();
  let top: Int = (low[low.len() - 1] as Int) & 0xFF;
  if top >= 128 {
    out.push(0 as UInt8);
  }
  var i = low.len() - 1;
  while i >= 0 {
    out.push(low[i]);
    i = i - 1;
  }
  return out;
}

// DER OBJECT IDENTIFIER content bytes of an arc list (first two arcs packed,
// later arcs base-128).
fn oid_content(arcs: Vec[Int]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if arcs.len() < 2 {
    return out;
  }
  let a0: Int = arcs[0];
  let a1: Int = arcs[1];
  out.push((a0 * 40 + a1) as UInt8);
  var k = 2;
  while k < arcs.len() {
    let v: Int = arcs[k];
    var low = Vec[Int].new();
    var x = v;
    while x > 0 {
      low.push(x % 128);
      x = x / 128;
    }
    if low.len() == 0 {
      low.push(0);
    }
    var j = low.len() - 1;
    while j >= 0 {
      var b: Int = low[j];
      if j > 0 {
        b = b + 128;
      }
      out.push(b as UInt8);
      j = j - 1;
    }
    k = k + 1;
  }
  return out;
}

fn arc_list4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn oid4(a: Int, b: Int, c: Int, d: Int) -> Vec[UInt8] {
  return tlv(0x06, oid_content(arc_list4(a, b, c, d)));
}

fn oid5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[UInt8] {
  var v = arc_list4(a, b, c, d);
  v.push(e);
  return tlv(0x06, oid_content(v));
}

fn oid6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[UInt8] {
  var v = arc_list4(a, b, c, d);
  v.push(e);
  v.push(f);
  return tlv(0x06, oid_content(v));
}

fn oid7(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int) -> Vec[UInt8] {
  var v = arc_list4(a, b, c, d);
  v.push(e);
  v.push(f);
  v.push(g);
  return tlv(0x06, oid_content(v));
}

fn oid9(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int, i: Int) -> Vec[UInt8] {
  var v = arc_list4(a, b, c, d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  v.push(i);
  return tlv(0x06, oid_content(v));
}

fn seq_tlv(content: Vec[UInt8]) -> Vec[UInt8] {
  return tlv(0x30, content);
}

fn set_tlv(content: Vec[UInt8]) -> Vec[UInt8] {
  return tlv(0x31, content);
}

fn null_tlv() -> Vec[UInt8] {
  var empty = Vec[UInt8].new();
  return tlv(0x05, empty);
}

fn bool_tlv_of(byte: Int) -> Vec[UInt8] {
  return tlv(0x01, b1(byte));
}

fn bits_tlv(unused: Int, payload: Vec[UInt8]) -> Vec[UInt8] {
  var c = Vec[UInt8].new();
  c.push(unused as UInt8);
  var i = 0;
  while i < payload.len() {
    c.push(payload[i]);
    i = i + 1;
  }
  return tlv(0x03, c);
}

fn octets_tlv(content: Vec[UInt8]) -> Vec[UInt8] {
  return tlv(0x04, content);
}

fn utf8_tlv(s: Str) -> Vec[UInt8] {
  return tlv(0x0C, str_bytes(s));
}

fn printable_tlv(s: Str) -> Vec[UInt8] {
  return tlv(0x13, str_bytes(s));
}

// AlgorithmIdentifier with NULL parameters.
fn alg_null(oid: Vec[UInt8]) -> Vec[UInt8] {
  return seq_tlv(cat2(oid, null_tlv()));
}

// AlgorithmIdentifier with an INTEGER parameter (must be skipped).
fn alg_int_param(oid: Vec[UInt8]) -> Vec[UInt8] {
  return seq_tlv(cat2(oid, tlv(0x02, der_int_bytes(5))));
}

// AttributeTypeAndValue ::= SEQUENCE { OID, value }.
fn ava(oid: Vec[UInt8], value: Vec[UInt8]) -> Vec[UInt8] {
  return seq_tlv(cat2(oid, value));
}

// RDNSequence with a single commonName RDN.
fn name_cn(s: Str) -> Vec[UInt8] {
  return seq_tlv(set_tlv(ava(oid4(2, 5, 4, 3), utf8_tlv(s))));
}

// Validity: UTCTime notBefore 2025-01-01, GeneralizedTime notAfter 2050.
fn validity_tlv() -> Vec[UInt8] {
  return seq_tlv(cat2(tlv(0x17, str_bytes("250101000000Z")), tlv(0x18, str_bytes("20500101000000Z"))));
}

// SubjectPublicKeyInfo with rsaEncryption + NULL and the given key bits.
fn spki_rsa(key_bits: Vec[UInt8]) -> Vec[UInt8] {
  return seq_tlv(cat2(alg_null(rsa_oid()), bits_tlv(0, key_bits)));
}

fn sha_oid() -> Vec[UInt8] {
  return oid7(1, 2, 840, 113549, 1, 1, 11);
}

fn rsa_oid() -> Vec[UInt8] {
  return oid7(1, 2, 840, 113549, 1, 1, 1);
}

// Extension ::= SEQUENCE { OID, critical BOOLEAN OPTIONAL, OCTET STRING }.
fn ext_tlv(oid: Vec[UInt8], critical: Int, inner: Vec[UInt8]) -> Vec[UInt8] {
  var body = copy_bytes(oid);
  if critical != 0 {
    body = cat2(body, bool_tlv_of(255));
  }
  body = cat2(body, octets_tlv(inner));
  return seq_tlv(body);
}

// GeneralName [n] IMPLICIT IA5String.
fn gn(tag: Int, s: Str) -> Vec[UInt8] {
  return tlv(128 + tag, str_bytes(s));
}

fn gn_ip(b: Vec[UInt8]) -> Vec[UInt8] {
  return tlv(135, b);
}

// The standard seven-extension set of the v3 fixture, as the content of the
// Extensions SEQUENCE.
fn std_exts() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b = cat2(b, ext_tlv(oid4(2, 5, 29, 19), 0, seq_tlv(cat2(bool_tlv_of(255), tlv(0x02, der_int_bytes(3))))));
  b = cat2(b, ext_tlv(oid4(2, 5, 29, 15), 1, bits_tlv(0, b2(0x84, 0))));
  b = cat2(b, ext_tlv(oid4(2, 5, 29, 37), 0, seq_tlv(cat2(oid9(1, 3, 6, 1, 5, 5, 7, 3, 1), oid9(1, 3, 6, 1, 5, 5, 7, 3, 2)))));
  var san = Vec[UInt8].new();
  san = cat2(san, gn(2, "example.com"));
  san = cat2(san, gn(1, "a@example.com"));
  san = cat2(san, gn(6, "https://example.com"));
  san = cat2(san, gn_ip(b4(192, 0, 2, 1)));
  b = cat2(b, ext_tlv(oid4(2, 5, 29, 17), 0, seq_tlv(san)));
  b = cat2(b, ext_tlv(oid4(2, 5, 29, 14), 0, octets_tlv(b4(1, 2, 3, 4))));
  b = cat2(b, ext_tlv(oid4(2, 5, 29, 35), 0, seq_tlv(tlv(128, b2(0xAA, 0xBB)))));
  b = cat2(b, ext_tlv(oid5(1, 2, 3, 4, 5), 0, octets_tlv(b1(0))));
  return b;
}

// General certificate builder. `version` is -1 for the v1 default (no [0]
// field), else the encoded version number. `exts` is the content of the
// Extensions SEQUENCE and is used only when `has_exts` is 1.
fn build_cert(version: Int, serial: Vec[UInt8], sig_alg: Vec[UInt8], issuer: Vec[UInt8], subject: Vec[UInt8], spki_tlv: Vec[UInt8], exts: Vec[UInt8], has_exts: Int, sig_value: Vec[UInt8]) -> Vec[UInt8] {
  var tbs = Vec[UInt8].new();
  if version >= 0 {
    tbs = cat2(tbs, tlv(0xA0, tlv(0x02, der_int_bytes(version))));
  }
  tbs = cat2(tbs, tlv(0x02, serial));
  tbs = cat2(tbs, sig_alg);
  tbs = cat2(tbs, issuer);
  tbs = cat2(tbs, validity_tlv());
  tbs = cat2(tbs, subject);
  tbs = cat2(tbs, spki_tlv);
  if has_exts != 0 {
    tbs = cat2(tbs, tlv(0xA3, seq_tlv(exts)));
  }
  var body = Vec[UInt8].new();
  body = cat2(body, seq_tlv(tbs));
  body = cat2(body, sig_alg);
  body = cat2(body, sig_value);
  return seq_tlv(body);
}

fn empty_vec() -> Vec[UInt8] {
  return Vec[UInt8].new();
}

fn cert_v1() -> Vec[UInt8] {
  return build_cert(-1, der_int_bytes(42), alg_null(sha_oid()), name_cn("Test CA"), name_cn("Test Leaf"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b3(0xAA, 0xBB, 0xCC)));
}

fn cert_v3() -> Vec[UInt8] {
  return build_cert(2, der_int_bytes(0x012345), alg_null(sha_oid()), name_cn("Test CA"), name_cn("Test Leaf"), spki_rsa(b3(1, 2, 3)), std_exts(), 1, bits_tlv(0, b3(0xAA, 0xBB, 0xCC)));
}

fn cert_with_ext(e: Vec[UInt8]) -> Vec[UInt8] {
  return build_cert(2, der_int_bytes(1), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), e, 1, bits_tlv(0, b1(1)));
}

// --------------------------------------------------
//  PEM helpers
// --------------------------------------------------

fn base64(data: &Vec[UInt8]) -> Str {
  let alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  var out = Vec[UInt8].new();
  var i = 0;
  while i + 3 <= data.len() {
    let b0: Int = (data[i] as Int) & 0xFF;
    let b1v: Int = (data[i + 1] as Int) & 0xFF;
    let b2v: Int = (data[i + 2] as Int) & 0xFF;
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16 + b1v / 16));
    out.push(string.byte_at(alpha, (b1v % 16) * 4 + b2v / 64));
    out.push(string.byte_at(alpha, b2v % 64));
    i = i + 3;
  }
  let rem = data.len() - i;
  if rem == 1 {
    let b0: Int = (data[i] as Int) & 0xFF;
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16));
    out.push(61 as UInt8);
    out.push(61 as UInt8);
  } elif rem == 2 {
    let b0: Int = (data[i] as Int) & 0xFF;
    let b1v: Int = (data[i + 1] as Int) & 0xFF;
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16 + b1v / 16));
    out.push(string.byte_at(alpha, (b1v % 16) * 4));
    out.push(61 as UInt8);
  }
  return builder.sb_to_str(&out);
}

fn pem_of(der: Vec[UInt8]) -> Str {
  let b64 = base64(&der);
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, "-----BEGIN CERTIFICATE-----\n");
  var i = 0;
  while i < b64.len() {
    var j = i + 64;
    if j > b64.len() {
      j = b64.len();
    }
    builder.sb_push_str(&mut sb, string.str_slice(b64, i, j));
    builder.sb_push_byte(&mut sb, 10 as UInt8);
    i = i + 64;
  }
  builder.sb_push_str(&mut sb, "-----END CERTIFICATE-----\n");
  return builder.sb_to_str(&sb);
}

fn pem_body(body: Str) -> Str {
  return "-----BEGIN CERTIFICATE-----\n" + body + "\n-----END CERTIFICATE-----\n";
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  let empty = Vec[UInt8].new();
  let r0 = der_length_decode(&empty, 0);
  if !bad_is(r0.is_ok, r0.error, at("pki: truncated length", 0)) { ok = false; }
  let d_neg = b1(5);
  let rn = der_length_decode(&d_neg, -1);
  if !bad_is(rn.is_ok, rn.error, "pki: negative offset") { ok = false; }
  let d_short = b1(0x7F);
  let r1 = der_length_decode(&d_short, 0);
  if !r1.is_ok { ok = false; } else {
    let l: DerLength = r1.value;
    if l.len != 127 || l.size != 1 { ok = false; }
  }
  let d_long = b2(0x81, 0x80);
  let r2 = der_length_decode(&d_long, 0);
  if !r2.is_ok { ok = false; } else {
    let l2: DerLength = r2.value;
    if l2.len != 128 || l2.size != 2 { ok = false; }
  }
  let d_long2 = b3(0x82, 0x01, 0x00);
  let r3 = der_length_decode(&d_long2, 0);
  if !r3.is_ok { ok = false; } else {
    let l3: DerLength = r3.value;
    if l3.len != 256 || l3.size != 3 { ok = false; }
  }
  let d_ind = b1(0x80);
  let r4 = der_length_decode(&d_ind, 0);
  if !bad_is(r4.is_ok, r4.error, at("pki: indefinite length", 0)) { ok = false; }
  let d_min = b2(0x81, 0x7F);
  let r5 = der_length_decode(&d_min, 0);
  if !bad_is(r5.is_ok, r5.error, at("pki: non-minimal length", 0)) { ok = false; }
  let d_min2 = b3(0x82, 0x00, 0x80);
  let r6 = der_length_decode(&d_min2, 0);
  if !bad_is(r6.is_ok, r6.error, at("pki: non-minimal length", 0)) { ok = false; }
  let d_tr = b2(0x82, 0x01);
  let r7 = der_length_decode(&d_tr, 0);
  if !bad_is(r7.is_ok, r7.error, at("pki: truncated length", 0)) { ok = false; }
  let d_big = b1(0x89);
  let r8 = der_length_decode(&d_big, 0);
  if !bad_is(r8.is_ok, r8.error, at("pki: long-form length overflow", 0)) { ok = false; }
  var xo = Vec[Int].new();
  xo.push(0x88);
  var fi = 0;
  while fi < 8 {
    xo.push(0xFF);
    fi = fi + 1;
  }
  let d_ff = bvec(xo);
  let r9 = der_length_decode(&d_ff, 0);
  if !bad_is(r9.is_ok, r9.error, at("pki: long-form length overflow", 0)) { ok = false; }
  return assert(ok, "der_length_decode: short/long forms; indefinite, overlong, truncated, overflow rejected");
}

fn t2() -> TestResult {
  var ok = true;
  let d1 = b2(0x30, 0x00);
  let r1 = der_tlv_decode(&d1, 0);
  if !r1.is_ok { ok = false; } else {
    let t: DerTlv = r1.value;
    if t.tag_class != 0 || !t.constructed || t.tag_number != 16 { ok = false; }
    if t.len != 0 || t.content != 2 || t.next != 2 { ok = false; }
  }
  let d2 = b3(0x31, 0x01, 0xAA);
  let r2 = der_tlv_decode(&d2, 0);
  if !r2.is_ok { ok = false; } else {
    let t2v: DerTlv = r2.value;
    if t2v.tag_number != 17 || t2v.len != 1 { ok = false; }
  }
  let d3 = b3(0x82, 0x01, 0x41);
  let r3 = der_tlv_decode(&d3, 0);
  if !r3.is_ok { ok = false; } else {
    let t3v: DerTlv = r3.value;
    if t3v.tag_class != 2 || t3v.constructed || t3v.tag_number != 2 { ok = false; }
  }
  let d4 = b2(0x63, 0x00);
  let r4 = der_tlv_decode(&d4, 0);
  if !r4.is_ok { ok = false; } else {
    let t4v: DerTlv = r4.value;
    if t4v.tag_class != 1 || !t4v.constructed || t4v.tag_number != 3 { ok = false; }
  }
  let d5 = b3(0xBF, 0x1F, 0x00);
  let r5 = der_tlv_decode(&d5, 0);
  if !r5.is_ok { ok = false; } else {
    let t5v: DerTlv = r5.value;
    if t5v.tag_class != 2 || !t5v.constructed || t5v.tag_number != 31 { ok = false; }
    if t5v.next != 3 { ok = false; }
  }
  let d6 = b4(0x9F, 0x81, 0x00, 0x00);
  let r6 = der_tlv_decode(&d6, 0);
  if !r6.is_ok { ok = false; } else {
    let t6v: DerTlv = r6.value;
    if t6v.tag_class != 2 || t6v.constructed || t6v.tag_number != 128 { ok = false; }
    if t6v.next != 4 { ok = false; }
  }
  let d7 = b1(0x1F);
  let r7 = der_tlv_decode(&d7, 0);
  if !bad_is(r7.is_ok, r7.error, at("pki: truncated tag", 0)) { ok = false; }
  let d8 = b4(0x1F, 0x80, 0x01, 0x00);
  let r8 = der_tlv_decode(&d8, 0);
  if !bad_is(r8.is_ok, r8.error, at("pki: non-minimal tag", 0)) { ok = false; }
  let d9 = b3(0x30, 0x05, 0x01);
  let r9 = der_tlv_decode(&d9, 0);
  if !bad_is(r9.is_ok, r9.error, at("pki: truncated value", 0)) { ok = false; }
  let d10 = b4(0x30, 0x02, 0x01, 0x01);
  let r10 = der_tlv_in(&d10, 0, 2);
  if !bad_is(r10.is_ok, r10.error, at("pki: value overruns container", 0)) { ok = false; }
  let r11 = der_tlv_in(&d10, 0, 4);
  if !r11.is_ok { ok = false; } else {
    let t11v: DerTlv = r11.value;
    if t11v.next != 4 { ok = false; }
  }
  return assert(ok, "der_tlv_decode: classes, constructed bit, high-tag-number form, truncation, container bounds");
}

fn t3() -> TestResult {
  var ok = true;
  let d1 = b3(0x01, 0x01, 0xFF);
  let r1 = der_bool_decode(&d1, 0);
  if !r1.is_ok { ok = false; } else {
    let b: DerBool = r1.value;
    if !b.value || b.next != 3 { ok = false; }
  }
  let d2 = b3(0x01, 0x01, 0x00);
  let r2 = der_bool_decode(&d2, 0);
  if !r2.is_ok { ok = false; } else {
    let b2v: DerBool = r2.value;
    if b2v.value { ok = false; }
  }
  let d3 = b3(0x01, 0x01, 0x01);
  let r3 = der_bool_decode(&d3, 0);
  if !r3.is_ok { ok = false; } else {
    let b3v: DerBool = r3.value;
    if !b3v.value { ok = false; }
  }
  let d4 = b4(0x01, 0x02, 0x00, 0x00);
  let r4 = der_bool_decode(&d4, 0);
  if !bad_is(r4.is_ok, r4.error, at("pki: bad boolean", 0)) { ok = false; }
  let d5 = b3(0x02, 0x01, 0x00);
  let r5 = der_bool_decode(&d5, 0);
  if !bad_is(r5.is_ok, r5.error, at("pki: tag mismatch", 0)) { ok = false; }
  return assert(ok, "BOOLEAN: 0x00 false, non-zero true, length and tag checks");
}

fn t4() -> TestResult {
  var ok = true;
  let d1 = b3(0x02, 0x01, 0x2A);
  let r1 = der_integer_decode(&d1, 0);
  if !r1.is_ok { ok = false; } else {
    let u: DerUint = r1.value;
    if u.value != 42 || u.next != 3 { ok = false; }
  }
  let d2 = b4(0x02, 0x02, 0x00, 0x80);
  let r2 = der_integer_decode(&d2, 0);
  if !r2.is_ok { ok = false; } else {
    let u2: DerUint = r2.value;
    if u2.value != 128 { ok = false; }
  }
  var xs = Vec[Int].new();
  xs.push(0x02);
  xs.push(0x08);
  xs.push(0x7F);
  var i = 0;
  while i < 7 {
    xs.push(0xFF);
    i = i + 1;
  }
  let d3 = bvec(xs);
  let r3 = der_integer_decode(&d3, 0);
  if !r3.is_ok { ok = false; } else {
    let u3: DerUint = r3.value;
    if u3.value != 9223372036854775807 { ok = false; }
  }
  var xo = Vec[Int].new();
  xo.push(0x02);
  xo.push(0x09);
  var j = 0;
  while j < 9 {
    xo.push(0x01);
    j = j + 1;
  }
  let d4 = bvec(xo);
  let r4 = der_integer_decode(&d4, 0);
  if !bad_is(r4.is_ok, r4.error, at("pki: integer overflow", 0)) { ok = false; }
  let d5 = b3(0x02, 0x01, 0x80);
  let r5 = der_integer_decode(&d5, 0);
  if !bad_is(r5.is_ok, r5.error, at("pki: negative integer", 0)) { ok = false; }
  let d6 = b4(0x02, 0x02, 0x00, 0x01);
  let r6 = der_integer_decode(&d6, 0);
  if !bad_is(r6.is_ok, r6.error, at("pki: non-minimal integer", 0)) { ok = false; }
  let d7 = b2(0x02, 0x00);
  let r7 = der_integer_decode(&d7, 0);
  if !bad_is(r7.is_ok, r7.error, at("pki: empty integer", 0)) { ok = false; }
  return assert(ok, "positive INTEGER: minimal encoding, sign pad, overflow, empty rejected");
}

fn t5() -> TestResult {
  var ok = true;
  let d1 = b4(0x03, 0x02, 0x00, 0xFF);
  let r1 = der_bit_string_decode(&d1, 0);
  if !r1.is_ok { ok = false; } else {
    let b: DerBits = r1.value;
    if b.unused != 0 || b.bit_length != 8 || b.len != 1 { ok = false; }
    if b.offset != 3 { ok = false; }
  }
  let d2 = b4(0x03, 0x02, 0x07, 0x80);
  let r2 = der_bit_string_decode(&d2, 0);
  if !r2.is_ok { ok = false; } else {
    let b2v: DerBits = r2.value;
    if b2v.unused != 7 || b2v.bit_length != 1 { ok = false; }
  }
  let d3 = b4(0x03, 0x02, 0x03, 0x01);
  let r3 = der_bit_string_decode(&d3, 0);
  if !bad_is(r3.is_ok, r3.error, at("pki: non-zero unused bits", 3)) { ok = false; }
  let d4 = b2(0x03, 0x00);
  let r4 = der_bit_string_decode(&d4, 0);
  if !bad_is(r4.is_ok, r4.error, at("pki: empty bit string", 0)) { ok = false; }
  let d5 = b4(0x03, 0x02, 0x08, 0x00);
  let r5 = der_bit_string_decode(&d5, 0);
  if !bad_is(r5.is_ok, r5.error, at("pki: bad unused bits", 2)) { ok = false; }
  let d6 = b3(0x03, 0x01, 0x03);
  let r6 = der_bit_string_decode(&d6, 0);
  if !bad_is(r6.is_ok, r6.error, at("pki: bad unused bits", 2)) { ok = false; }
  return assert(ok, "BIT STRING: unused-bit count validated, bit length, unused-region bits zero");
}

fn t6() -> TestResult {
  var ok = true;
  let d1 = b4(0x04, 0x02, 0x01, 0x02);
  let r1 = der_octet_string_decode(&d1, 0);
  if !r1.is_ok { ok = false; } else {
    let b: DerBytes = r1.value;
    if b.bytes.len() != 2 || b.next != 4 { ok = false; }
    if !bytes_slice_is(b.bytes, 0, b2(1, 2)) { ok = false; }
  }
  let d2 = b2(0x04, 0x00);
  let r2 = der_octet_string_decode(&d2, 0);
  if !r2.is_ok { ok = false; } else {
    let b2v: DerBytes = r2.value;
    if b2v.bytes.len() != 0 { ok = false; }
  }
  let d3 = b2(0x05, 0x00);
  let r3 = der_null_decode(&d3, 0);
  if !r3.is_ok { ok = false; } else {
    let n: Int = r3.value;
    if n != 2 { ok = false; }
  }
  let d4 = b3(0x05, 0x01, 0x00);
  let r4 = der_null_decode(&d4, 0);
  if !bad_is(r4.is_ok, r4.error, at("pki: unexpected null content", 0)) { ok = false; }
  let r5 = der_null_decode(&d2, 0);
  if !bad_is(r5.is_ok, r5.error, at("pki: tag mismatch", 0)) { ok = false; }
  return assert(ok, "OCTET STRING copies bytes; NULL requires empty content");
}

fn t7() -> TestResult {
  var ok = true;
  let d1 = b4(0x06, 0x03, 0x55, 0x04);
  var d1b = copy_bytes(d1);
  d1b.push(0x03);
  let r1 = der_oid_decode(&d1b, 0);
  if !r1.is_ok { ok = false; } else {
    let o: DerOid = r1.value;
    if !streq(o.value, "2.5.4.3") { ok = false; }
  }
  var sx = Vec[Int].new();
  sx.push(0x06);
  sx.push(0x09);
  sx.push(0x2A);
  sx.push(0x86);
  sx.push(0x48);
  sx.push(0x86);
  sx.push(0xF7);
  sx.push(0x0D);
  sx.push(0x01);
  sx.push(0x01);
  sx.push(0x0B);
  let d2 = bvec(sx);
  let r2 = der_oid_decode(&d2, 0);
  if !r2.is_ok { ok = false; } else {
    let o2: DerOid = r2.value;
    if !streq(o2.value, "1.2.840.113549.1.1.11") { ok = false; }
  }
  let d3 = b3(0x06, 0x01, 0x27);
  let r3 = der_oid_decode(&d3, 0);
  if !r3.is_ok { ok = false; } else {
    let o3: DerOid = r3.value;
    if !streq(o3.value, "0.39") { ok = false; }
  }
  let d4 = b3(0x06, 0x01, 0x78);
  let r4 = der_oid_decode(&d4, 0);
  if !bad_is(r4.is_ok, r4.error, at("pki: bad oid", 0)) { ok = false; }
  let d5 = b2(0x06, 0x00);
  let r5 = der_oid_decode(&d5, 0);
  if !bad_is(r5.is_ok, r5.error, at("pki: empty oid", 0)) { ok = false; }
  let d6 = b4(0x06, 0x02, 0x2A, 0x86);
  let r6 = der_oid_decode(&d6, 0);
  if !bad_is(r6.is_ok, r6.error, at("pki: truncated oid", 0)) { ok = false; }
  let d7 = b4(0x06, 0x02, 0x2A, 0x80);
  let r7 = der_oid_decode(&d7, 0);
  if !bad_is(r7.is_ok, r7.error, at("pki: non-minimal oid arc", 3)) { ok = false; }
  var bx = Vec[Int].new();
  bx.push(0x06);
  bx.push(0x03);
  bx.push(0x2A);
  bx.push(0x81);
  bx.push(0x00);
  let d8 = bvec(bx);
  let r8 = der_oid_decode(&d8, 0);
  if !r8.is_ok { ok = false; } else {
    let o8: DerOid = r8.value;
    if !streq(o8.value, "1.2.128") { ok = false; }
  }
  let d9 = b3(0x06, 0x01, 0x2A);
  let r9 = der_oid_decode(&d9, 0);
  if !r9.is_ok { ok = false; } else {
    let o9: DerOid = r9.value;
    if !streq(o9.value, "1.2") { ok = false; }
  }
  return assert(ok, "OBJECT IDENTIFIER: first two arcs, base-128 arcs, non-minimal and truncation rejected");
}

fn t8() -> TestResult {
  var ok = true;
  var ax = Vec[Int].new();
  ax.push(0x0C);
  ax.push(0x03);
  ax.push(0x41);
  ax.push(0x2A);
  ax.push(0x42);
  let d1 = bvec(ax);
  let r1 = der_string_decode(&d1, 0);
  if !r1.is_ok { ok = false; } else {
    let s: DerString = r1.value;
    if !streq(s.value, "A*B") { ok = false; }
  }
  let d2 = tlv(0x13, str_bytes("Hello"));
  let r2 = der_string_decode(&d2, 0);
  if !r2.is_ok { ok = false; } else {
    let s2: DerString = r2.value;
    if !streq(s2.value, "Hello") { ok = false; }
  }
  let d3 = tlv(0x16, str_bytes("abc"));
  let r3 = der_string_decode(&d3, 0);
  if !r3.is_ok { ok = false; } else {
    let s3: DerString = r3.value;
    if !streq(s3.value, "abc") { ok = false; }
  }
  let d4 = b4(0x0C, 0x02, 0xC3, 0xA9);
  let r4 = der_string_decode(&d4, 0);
  if !r4.is_ok { ok = false; } else {
    let s4: DerString = r4.value;
    if s4.value.len() != 2 { ok = false; }
  }
  let d5 = b3(0x0C, 0x01, 0x80);
  let r5 = der_string_decode(&d5, 0);
  if !bad_is(r5.is_ok, r5.error, at("pki: bad utf8 string", 2)) { ok = false; }
  let d6 = b3(0x0C, 0x01, 0x00);
  let r6 = der_string_decode(&d6, 0);
  if !bad_is(r6.is_ok, r6.error, at("pki: bad utf8 string", 2)) { ok = false; }
  let d7 = b3(0x13, 0x01, 0x1F);
  let r7 = der_string_decode(&d7, 0);
  if !bad_is(r7.is_ok, r7.error, at("pki: bad printable string", 2)) { ok = false; }
  let d8 = b3(0x16, 0x01, 0x80);
  let r8 = der_string_decode(&d8, 0);
  if !bad_is(r8.is_ok, r8.error, at("pki: bad ia5 string", 2)) { ok = false; }
  let d9 = b3(0x16, 0x01, 0x00);
  let r9 = der_string_decode(&d9, 0);
  if !bad_is(r9.is_ok, r9.error, at("pki: bad ia5 string", 2)) { ok = false; }
  let d10 = b3(0x04, 0x01, 0x41);
  let r10 = der_string_decode(&d10, 0);
  if !bad_is(r10.is_ok, r10.error, at("pki: tag mismatch", 0)) { ok = false; }
  return assert(ok, "strings: UTF8String/PrintableString/IA5String validation, NUL rejected, tag mismatch");
}

fn t9() -> TestResult {
  var ok = true;
  let d1 = tlv(0x17, str_bytes("490101000000Z"));
  let r1 = der_time_decode(&d1, 0);
  if !r1.is_ok { ok = false; } else {
    let t: DerTime = r1.value;
    if t.year != 2049 || !t.utc { ok = false; }
    if t.month != 1 || t.day != 1 || t.hour != 0 || t.minute != 0 || t.second != 0 { ok = false; }
  }
  let d2 = tlv(0x17, str_bytes("500101000000Z"));
  let r2 = der_time_decode(&d2, 0);
  if !r2.is_ok { ok = false; } else {
    let t2v: DerTime = r2.value;
    if t2v.year != 1950 { ok = false; }
  }
  let d3 = tlv(0x18, str_bytes("20260102030405Z"));
  let r3 = der_time_decode(&d3, 0);
  if !r3.is_ok { ok = false; } else {
    let t3v: DerTime = r3.value;
    if t3v.year != 2026 || t3v.month != 1 || t3v.day != 2 { ok = false; }
    if t3v.hour != 3 || t3v.minute != 4 || t3v.second != 5 { ok = false; }
    if t3v.utc { ok = false; }
  }
  let d4 = tlv(0x17, str_bytes("990101000000"));
  let r4 = der_time_decode(&d4, 0);
  if !bad_is(r4.is_ok, r4.error, at("pki: bad utc time", 0)) { ok = false; }
  let d5 = tlv(0x17, str_bytes("991301000000Z"));
  let r5 = der_time_decode(&d5, 0);
  if !bad_is(r5.is_ok, r5.error, at("pki: bad time month", 0)) { ok = false; }
  let d6 = tlv(0x17, str_bytes("990101000000X"));
  let r6 = der_time_decode(&d6, 0);
  if !bad_is(r6.is_ok, r6.error, at("pki: bad time zone", 14)) { ok = false; }
  let d7 = tlv(0x17, str_bytes("99A101000000Z"));
  let r7 = der_time_decode(&d7, 0);
  if !bad_is(r7.is_ok, r7.error, at("pki: bad time digit", 4)) { ok = false; }
  let d8 = tlv(0x18, str_bytes("20260102030460Z"));
  let r8 = der_time_decode(&d8, 0);
  if !bad_is(r8.is_ok, r8.error, at("pki: bad time second", 0)) { ok = false; }
  let d9 = tlv(0x04, str_bytes("20260102030405Z"));
  let r9 = der_time_decode(&d9, 0);
  if !bad_is(r9.is_ok, r9.error, at("pki: tag mismatch", 0)) { ok = false; }
  return assert(ok, "UTCTime YY pivot and GeneralizedTime fields, digit/zone/range errors with offsets");
}

fn t10() -> TestResult {
  let d = cert_v1();
  let r = pki_certificate_parse(&d);
  var ok = r.is_ok;
  if r.is_ok {
    let cert: PkiCertificate = r.value;
    if pki_certificate_version(&cert) != 0 { ok = false; }
    if pki_serial_len(&cert) != 1 { ok = false; }
    if !streq(pki_serial_hex(&cert), "2A") { ok = false; }
    let sb = pki_serial_bytes(&cert);
    if sb.len() != 1 || !bytes_slice_is(sb, 0, b1(42)) { ok = false; }
    if !streq(pki_tbs_signature_oid(&cert), "1.2.840.113549.1.1.11") { ok = false; }
    if !streq(pki_outer_signature_oid(&cert), "1.2.840.113549.1.1.11") { ok = false; }
    let iss: PkiName = cert.issuer;
    if pki_name_rdn_count(&iss) != 1 { ok = false; }
    if pki_name_attribute_count(&iss) != 1 { ok = false; }
    if pki_name_rdn_index(&iss, 0) != 0 { ok = false; }
    if !streq(pki_name_oid(&iss, 0), "2.5.4.3") { ok = false; }
    if pki_name_value_tag(&iss, 0) != 12 { ok = false; }
    if !streq(pki_name_value(&iss, 0), "Test CA") { ok = false; }
    let sub: PkiName = cert.subject;
    if !streq(pki_name_value(&sub, 0), "Test Leaf") { ok = false; }
    let nb: DerTime = cert.not_before;
    if pki_time_year(&nb) != 2025 || pki_time_month(&nb) != 1 || pki_time_day(&nb) != 1 { ok = false; }
    if !pki_time_is_utc(&nb) || pki_time_hour(&nb) != 0 { ok = false; }
    let na: DerTime = cert.not_after;
    if pki_time_year(&na) != 2050 { ok = false; }
    if pki_time_is_utc(&na) { ok = false; }
    if !streq(pki_spki_algorithm_oid(&cert), "1.2.840.113549.1.1.1") { ok = false; }
    if pki_spki_key_bits(&cert) != 24 { ok = false; }
    if pki_signature_bits(&cert) != 24 { ok = false; }
    let ex: PkiExtensions = cert.extensions;
    if pki_extension_count(&ex) != 0 { ok = false; }
    if pki_basic_constraints_present(&ex) || pki_key_usage_present(&ex) { ok = false; }
    if pki_san_count(&ex) != 0 || pki_has_subject_key_id(&ex) || pki_has_authority_key_id(&ex) { ok = false; }
  }
  return assert(ok, "v1 certificate: TBS split, names, validity, SPKI, empty extensions");
}

fn t11() -> TestResult {
  let d = cert_v3();
  let r = pki_certificate_parse(&d);
  var ok = r.is_ok;
  if r.is_ok {
    let cert: PkiCertificate = r.value;
    if pki_certificate_version(&cert) != 2 { ok = false; }
    if !streq(pki_serial_hex(&cert), "012345") { ok = false; }
    if pki_serial_len(&cert) != 3 { ok = false; }
    let sub: PkiName = cert.subject;
    if !streq(pki_name_value(&sub, 0), "Test Leaf") { ok = false; }
    let ex: PkiExtensions = cert.extensions;
    if pki_extension_count(&ex) != 7 { ok = false; }
    if !streq(pki_extension_oid(&ex, 0), "2.5.29.19") { ok = false; }
    if !streq(pki_extension_oid(&ex, 1), "2.5.29.15") { ok = false; }
    if !streq(pki_extension_oid(&ex, 2), "2.5.29.37") { ok = false; }
    if !streq(pki_extension_oid(&ex, 3), "2.5.29.17") { ok = false; }
    if !streq(pki_extension_oid(&ex, 6), "1.2.3.4.5") { ok = false; }
    if pki_extension_critical(&ex, 0) != 0 { ok = false; }
    if pki_extension_critical(&ex, 1) != 1 { ok = false; }
    if !pki_basic_constraints_present(&ex) || !pki_ca(&ex) { ok = false; }
    if pki_path_len(&ex) != 3 { ok = false; }
    if !pki_key_usage_present(&ex) { ok = false; }
    if pki_key_usage_value(&ex) != 33792 { ok = false; }
    if !pki_key_usage_has(&ex, 0) { ok = false; }
    if !pki_key_usage_has(&ex, 5) { ok = false; }
    if pki_key_usage_has(&ex, 2) { ok = false; }
    if pki_key_usage_has(&ex, 7) { ok = false; }
    if pki_ext_key_usage_count(&ex) != 2 { ok = false; }
    if !streq(pki_ext_key_usage_oid(&ex, 0), "1.3.6.1.5.5.7.3.1") { ok = false; }
    if !streq(pki_ext_key_usage_oid(&ex, 1), "1.3.6.1.5.5.7.3.2") { ok = false; }
    if pki_san_count(&ex) != 4 { ok = false; }
    if pki_san_type(&ex, 0) != 2 || !streq(pki_san_value(&ex, 0), "example.com") { ok = false; }
    if pki_san_type(&ex, 1) != 1 || !streq(pki_san_value(&ex, 1), "a@example.com") { ok = false; }
    if pki_san_type(&ex, 2) != 6 || !streq(pki_san_value(&ex, 2), "https://example.com") { ok = false; }
    if pki_san_type(&ex, 3) != 7 || !streq(pki_san_value(&ex, 3), "192.0.2.1") { ok = false; }
    if !pki_has_subject_key_id(&ex) || !streq(pki_subject_key_id_hex(&ex), "01020304") { ok = false; }
    if !pki_has_authority_key_id(&ex) || !streq(pki_authority_key_id_hex(&ex), "AABB") { ok = false; }
  }
  return assert(ok, "v3 certificate: extension order, BC/KU/EKU/SAN/SKI/AKI, unknown OID preserved");
}

fn t12() -> TestResult {
  var ok = true;
  let d1 = cert_with_ext(ext_tlv(oid4(2, 5, 29, 19), 0, tlv(0x02, der_int_bytes(1))));
  let r1 = pki_certificate_parse(&d1);
  if !bad_prefix(r1.is_ok, r1.error, "pki: bad basic constraints") { ok = false; }
  let d2 = cert_with_ext(ext_tlv(oid4(2, 5, 29, 15), 0, seq_tlv(empty_vec())));
  let r2 = pki_certificate_parse(&d2);
  if !bad_prefix(r2.is_ok, r2.error, "pki: tag mismatch") { ok = false; }
  let d3 = cert_with_ext(ext_tlv(oid4(2, 5, 29, 37), 0, oid9(1, 3, 6, 1, 5, 5, 7, 3, 1)));
  let r3 = pki_certificate_parse(&d3);
  if !bad_prefix(r3.is_ok, r3.error, "pki: bad ext key usage") { ok = false; }
  let d4 = cert_with_ext(ext_tlv(oid4(2, 5, 29, 17), 0, seq_tlv(tlv(0x02, der_int_bytes(1)))));
  let r4 = pki_certificate_parse(&d4);
  if !bad_prefix(r4.is_ok, r4.error, "pki: bad general name") { ok = false; }
  var fx = Vec[Int].new();
  fx.push(1);
  fx.push(2);
  fx.push(3);
  fx.push(4);
  fx.push(5);
  let d5 = cert_with_ext(ext_tlv(oid4(2, 5, 29, 17), 0, seq_tlv(tlv(135, bvec(fx)))));
  let r5 = pki_certificate_parse(&d5);
  if !bad_prefix(r5.is_ok, r5.error, "pki: bad ip address") { ok = false; }
  let bad_ext = seq_tlv(cat2(oid4(2, 5, 29, 19), tlv(0x02, der_int_bytes(1))));
  let d6 = cert_with_ext(bad_ext);
  let r6 = pki_certificate_parse(&d6);
  if !bad_prefix(r6.is_ok, r6.error, "pki: bad extension") { ok = false; }
  let d7 = cert_with_ext(ext_tlv(oid4(2, 5, 29, 14), 0, octets_tlv(empty_vec())));
  let r7 = pki_certificate_parse(&d7);
  if !bad_prefix(r7.is_ok, r7.error, "pki: bad subject key id") { ok = false; }
  return assert(ok, "malformed known extensions fail the parse with offset-bearing nested errors");
}

fn t13() -> TestResult {
  var ok = true;
  let full = cert_v1();
  var cut = Vec[UInt8].new();
  var i = 0;
  while i < full.len() - 1 {
    cut.push(full[i]);
    i = i + 1;
  }
  let r1 = pki_certificate_parse(&cut);
  if !bad_is(r1.is_ok, r1.error, at("pki: truncated value", 0)) { ok = false; }
  let with_tail = cat2(full, b1(0x00));
  let r2 = pki_certificate_parse(&with_tail);
  if !bad_is(r2.is_ok, r2.error, at("pki: trailing data", full.len())) { ok = false; }
  let d3 = b4(0x30, 0x80, 0x02, 0x01);
  let r3 = pki_certificate_parse(&d3);
  if !bad_is(r3.is_ok, r3.error, at("pki: indefinite length", 1)) { ok = false; }
  let d4 = build_cert(3, der_int_bytes(1), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r4 = pki_certificate_parse(&d4);
  if !bad_prefix(r4.is_ok, r4.error, "pki: bad version") { ok = false; }
  let d5 = build_cert(-1, der_int_bytes(1), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r5 = pki_certificate_parse(&d5);
  if !r5.is_ok { ok = false; }
  var tbs = Vec[UInt8].new();
  tbs = cat2(tbs, tlv(0x02, der_int_bytes(7)));
  tbs = cat2(tbs, alg_null(sha_oid()));
  tbs = cat2(tbs, name_cn("A"));
  tbs = cat2(tbs, validity_tlv());
  tbs = cat2(tbs, name_cn("B"));
  tbs = cat2(tbs, spki_rsa(b3(1, 2, 3)));
  tbs = cat2(tbs, tlv(0x84, empty_vec()));
  var body = Vec[UInt8].new();
  body = cat2(body, seq_tlv(tbs));
  body = cat2(body, alg_null(sha_oid()));
  body = cat2(body, bits_tlv(0, b1(1)));
  let d6 = seq_tlv(body);
  let r6 = pki_certificate_parse(&d6);
  if !bad_prefix(r6.is_ok, r6.error, "pki: bad tbs field") { ok = false; }
  let empty = Vec[UInt8].new();
  let r7 = pki_certificate_parse(&empty);
  if !bad_is(r7.is_ok, r7.error, at("pki: truncated tag", 0)) { ok = false; }
  let d8 = b1(0x31);
  let r8 = pki_certificate_parse(&d8);
  if !bad_prefix(r8.is_ok, r8.error, "pki:") { ok = false; }
  return assert(ok, "malformed certificates: truncation, trailing data, indefinite length, bad version/TBS field");
}

fn t14() -> TestResult {
  var ok = true;
  let der = cert_v1();
  let text = pem_of(der);
  let r1 = pki_pem_to_der(text);
  if !r1.is_ok { ok = false; } else {
    let got: Vec[UInt8] = r1.value;
    if !bytes_equal(got, der) { ok = false; }
  }
  let crlf = string.replace(text, "\n", "\r\n");
  let r2 = pki_pem_to_der(crlf);
  if !r2.is_ok { ok = false; } else {
    let got2: Vec[UInt8] = r2.value;
    if !bytes_equal(got2, der) { ok = false; }
  }
  let no_lf = string.str_slice(text, 0, text.len() - 1);
  let r3 = pki_pem_to_der(no_lf);
  if !r3.is_ok { ok = false; } else {
    let got3: Vec[UInt8] = r3.value;
    if !bytes_equal(got3, der) { ok = false; }
  }
  let r4 = pki_pem_to_der(pem_body("TWFu"));
  if !r4.is_ok { ok = false; } else {
    let got4: Vec[UInt8] = r4.value;
    if !bytes_equal(got4, str_bytes("Man")) { ok = false; }
  }
  let r5 = pki_pem_to_der("");
  if !bad_is(r5.is_ok, r5.error, "pki pem: no certificate block") { ok = false; }
  let r6 = pki_pem_to_der("hello\n");
  if !bad_is(r6.is_ok, r6.error, at("pki pem: bad armor", 0)) { ok = false; }
  let r7 = pki_pem_to_der("-----BEGIN PRIVATE KEY-----\nTWFu\n-----END PRIVATE KEY-----\n");
  if !bad_is(r7.is_ok, r7.error, at("pki pem: bad armor", 0)) { ok = false; }
  let open = "-----BEGIN CERTIFICATE-----\nTWFu\n";
  let r8 = pki_pem_to_der(open);
  if !bad_is(r8.is_ok, r8.error, at("pki pem: unterminated block", open.len())) { ok = false; }
  let r9 = pki_pem_to_der(pem_body("TQ="));
  if !bad_is(r9.is_ok, r9.error, at("pki pem: bad padding", 28)) { ok = false; }
  let r10 = pki_pem_to_der(pem_body("TW!u"));
  if !bad_is(r10.is_ok, r10.error, at("pki pem: invalid base64 character", 30)) { ok = false; }
  let r11 = pki_pem_to_der(pem_body("TR=="));
  if !bad_is(r11.is_ok, r11.error, at("pki pem: non-canonical trailing bits", 29)) { ok = false; }
  let r12 = pki_pem_to_der(text + "junk\n");
  if !bad_is(r12.is_ok, r12.error, at("pki pem: text outside block", text.len())) { ok = false; }
  let long_line = pem_body(string.str_repeat("A", 65));
  let r13 = pki_pem_to_der(long_line);
  if !bad_prefix(r13.is_ok, r13.error, "pki pem: bad armor") { ok = false; }
  let r14 = pki_pem_to_der(pem_body("TWFu\n\nTWFu"));
  if !bad_prefix(r14.is_ok, r14.error, "pki pem: bad armor") { ok = false; }
  let r15 = pki_pem_to_der(pem_body("TWFu\nTWFu"));
  if !bad_prefix(r15.is_ok, r15.error, "pki pem: bad armor") { ok = false; }
  let r16 = pki_pem_to_der("-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n");
  if !bad_is(r16.is_ok, r16.error, "pki pem: empty body") { ok = false; }
  return assert(ok, "PEM unwrap: round trip, CRLF, padding/character/trailing-bit and armor errors");
}

fn t15() -> TestResult {
  var ok = true;
  var avas = Vec[UInt8].new();
  avas = cat2(avas, ava(oid4(2, 5, 4, 3), utf8_tlv("Multi")));
  avas = cat2(avas, ava(oid4(2, 5, 4, 10), printable_tlv("Org")));
  let rdn0 = set_tlv(avas);
  let rdn1 = set_tlv(ava(oid4(2, 5, 4, 6), printable_tlv("GR")));
  let issuer = seq_tlv(cat2(rdn0, rdn1));
  let d = build_cert(-1, der_int_bytes(9), alg_null(sha_oid()), issuer, name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r = pki_certificate_parse(&d);
  if !r.is_ok { ok = false; } else {
    let cert: PkiCertificate = r.value;
    let iss: PkiName = cert.issuer;
    if pki_name_rdn_count(&iss) != 2 { ok = false; }
    if pki_name_attribute_count(&iss) != 3 { ok = false; }
    if pki_name_rdn_index(&iss, 0) != 0 || pki_name_rdn_index(&iss, 1) != 0 { ok = false; }
    if pki_name_rdn_index(&iss, 2) != 1 { ok = false; }
    if !streq(pki_name_oid(&iss, 0), "2.5.4.3") { ok = false; }
    if !streq(pki_name_oid(&iss, 1), "2.5.4.10") { ok = false; }
    if !streq(pki_name_oid(&iss, 2), "2.5.4.6") { ok = false; }
    if !streq(pki_name_value(&iss, 0), "Multi") { ok = false; }
    if !streq(pki_name_value(&iss, 1), "Org") { ok = false; }
    if !streq(pki_name_value(&iss, 2), "GR") { ok = false; }
    if pki_name_value_tag(&iss, 0) != 12 { ok = false; }
    if pki_name_value_tag(&iss, 1) != 19 || pki_name_value_tag(&iss, 2) != 19 { ok = false; }
  }
  let odd_issuer = seq_tlv(set_tlv(ava(oid4(2, 5, 4, 3), octets_tlv(b1(0x41)))));
  let d2 = build_cert(-1, der_int_bytes(9), alg_null(sha_oid()), odd_issuer, name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r2 = pki_certificate_parse(&d2);
  if !r2.is_ok { ok = false; } else {
    let cert2: PkiCertificate = r2.value;
    let iss2: PkiName = cert2.issuer;
    if pki_name_attribute_count(&iss2) != 1 { ok = false; }
    if pki_name_value_tag(&iss2, 0) != -1 { ok = false; }
    if !streq(pki_name_value(&iss2, 0), "") { ok = false; }
    if !streq(pki_name_oid(&iss2, 0), "2.5.4.3") { ok = false; }
  }
  return assert(ok, "RDNSequence: multi-valued RDNs, ordinals, mixed string types, undecoded value type");
}

fn t16() -> TestResult {
  var ok = true;
  let d1 = build_cert(1, der_int_bytes(1), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r1 = pki_certificate_parse(&d1);
  if !r1.is_ok { ok = false; } else {
    let c1: PkiCertificate = r1.value;
    if pki_certificate_version(&c1) != 1 { ok = false; }
  }
  let d2 = build_cert(2, der_int_bytes(1), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r2 = pki_certificate_parse(&d2);
  if !r2.is_ok { ok = false; } else {
    let c2: PkiCertificate = r2.value;
    if pki_certificate_version(&c2) != 2 { ok = false; }
  }
  let d3 = build_cert(3, der_int_bytes(1), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r3 = pki_certificate_parse(&d3);
  if !bad_prefix(r3.is_ok, r3.error, "pki: bad version") { ok = false; }
  return assert(ok, "version: v1 default, v2 and v3 [0] EXPLICIT, out-of-range version rejected");
}

fn t17() -> TestResult {
  var ok = true;
  var s20 = Vec[UInt8].new();
  s20.push(0x01);
  var i = 0;
  while i < 19 {
    s20.push(0x22);
    i = i + 1;
  }
  let d1 = build_cert(2, s20, alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r1 = pki_certificate_parse(&d1);
  if !r1.is_ok { ok = false; } else {
    let c1: PkiCertificate = r1.value;
    if pki_serial_len(&c1) != 20 { ok = false; }
  }
  var s21 = Vec[UInt8].new();
  s21.push(0x01);
  var j = 0;
  while j < 20 {
    s21.push(0x22);
    j = j + 1;
  }
  let d2 = build_cert(2, s21, alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r2 = pki_certificate_parse(&d2);
  if !bad_prefix(r2.is_ok, r2.error, "pki: serial too long") { ok = false; }
  let d3 = build_cert(2, b2(0x00, 0x80), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r3 = pki_certificate_parse(&d3);
  if !r3.is_ok { ok = false; } else {
    let c3: PkiCertificate = r3.value;
    if pki_serial_len(&c3) != 2 { ok = false; }
    if !streq(pki_serial_hex(&c3), "0080") { ok = false; }
  }
  let d4 = build_cert(2, b1(0x80), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r4 = pki_certificate_parse(&d4);
  if !bad_prefix(r4.is_ok, r4.error, "pki: negative serial") { ok = false; }
  let d5 = build_cert(2, b2(0x00, 0x01), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r5 = pki_certificate_parse(&d5);
  if !bad_prefix(r5.is_ok, r5.error, "pki: non-minimal serial") { ok = false; }
  let d6 = build_cert(2, b1(0x00), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r6 = pki_certificate_parse(&d6);
  if !r6.is_ok { ok = false; } else {
    let c6: PkiCertificate = r6.value;
    if !streq(pki_serial_hex(&c6), "00") { ok = false; }
  }
  return assert(ok, "serialNumber: 20-byte cap, DER sign pad, negative and non-minimal rejected");
}

fn t18() -> TestResult {
  var ok = true;
  let d1 = build_cert(2, der_int_bytes(1), alg_int_param(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r1 = pki_certificate_parse(&d1);
  if !r1.is_ok { ok = false; } else {
    let c1: PkiCertificate = r1.value;
    if !streq(pki_tbs_signature_oid(&c1), "1.2.840.113549.1.1.11") { ok = false; }
  }
  let spki_param = seq_tlv(cat2(alg_int_param(rsa_oid()), bits_tlv(0, b3(1, 2, 3))));
  let d2 = build_cert(2, der_int_bytes(1), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_param, empty_vec(), 0, bits_tlv(0, b1(1)));
  let r2 = pki_certificate_parse(&d2);
  if !r2.is_ok { ok = false; } else {
    let c2: PkiCertificate = r2.value;
    if !streq(pki_spki_algorithm_oid(&c2), "1.2.840.113549.1.1.1") { ok = false; }
    if pki_spki_key_bits(&c2) != 24 { ok = false; }
  }
  let no_param = seq_tlv(sha_oid());
  let d3 = build_cert(2, der_int_bytes(1), no_param, name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(0, b1(1)));
  let r3 = pki_certificate_parse(&d3);
  if !r3.is_ok { ok = false; } else {
    let c3: PkiCertificate = r3.value;
    if !streq(pki_outer_signature_oid(&c3), "1.2.840.113549.1.1.11") { ok = false; }
  }
  let d4 = build_cert(2, der_int_bytes(1), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki_rsa(b3(1, 2, 3)), empty_vec(), 0, bits_tlv(7, b1(0x80)));
  let r4 = pki_certificate_parse(&d4);
  if !r4.is_ok { ok = false; } else {
    let c4: PkiCertificate = r4.value;
    if pki_signature_bits(&c4) != 1 { ok = false; }
  }
  return assert(ok, "AlgorithmIdentifier parameters skipped; signatureValue bit length honours unused bits");
}

fn t19() -> TestResult {
  var ok = true;
  let spki4 = seq_tlv(cat2(alg_null(rsa_oid()), bits_tlv(4, b1(0xF0))));
  let d1 = build_cert(2, der_int_bytes(1), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki4, empty_vec(), 0, bits_tlv(0, b1(1)));
  let r1 = pki_certificate_parse(&d1);
  if !r1.is_ok { ok = false; } else {
    let c1: PkiCertificate = r1.value;
    if pki_spki_key_bits(&c1) != 4 { ok = false; }
  }
  let spki0 = seq_tlv(cat2(alg_null(rsa_oid()), bits_tlv(0, empty_vec())));
  let d2 = build_cert(2, der_int_bytes(1), alg_null(sha_oid()), name_cn("A"), name_cn("B"), spki0, empty_vec(), 0, bits_tlv(0, b1(1)));
  let r2 = pki_certificate_parse(&d2);
  if !r2.is_ok { ok = false; } else {
    let c2: PkiCertificate = r2.value;
    if pki_spki_key_bits(&c2) != 0 { ok = false; }
  }
  let d3 = cert_with_ext(ext_tlv(oid5(1, 2, 3, 4, 6), 1, octets_tlv(b1(0))));
  let r3 = pki_certificate_parse(&d3);
  if !r3.is_ok { ok = false; } else {
    let c3: PkiCertificate = r3.value;
    let ex: PkiExtensions = c3.extensions;
    if pki_extension_count(&ex) != 1 { ok = false; }
    if pki_extension_critical(&ex, 0) != 1 { ok = false; }
    if !streq(pki_extension_oid(&ex, 0), "1.2.3.4.6") { ok = false; }
    if pki_basic_constraints_present(&ex) { ok = false; }
  }
  let d4 = cert_with_ext(ext_tlv(oid4(2, 5, 29, 15), 0, bits_tlv(0, b1(0x04))));
  let r4 = pki_certificate_parse(&d4);
  if !r4.is_ok { ok = false; } else {
    let c4: PkiCertificate = r4.value;
    let ex4: PkiExtensions = c4.extensions;
    if pki_key_usage_value(&ex4) != 1024 { ok = false; }
    if !pki_key_usage_has(&ex4, 5) { ok = false; }
    if pki_key_usage_has(&ex4, 0) { ok = false; }
  }
  return assert(ok, "SPKI bit lengths (4 and 0), unknown critical extension and one-byte keyUsage normalized");
}

fn t20() -> TestResult {
  let d = cert_v1();
  let r = pki_certificate_parse(&d);
  var ok = r.is_ok;
  if r.is_ok {
    let cert: PkiCertificate = r.value;
    let iss: PkiName = cert.issuer;
    if pki_name_rdn_index(&iss, -1) != -1 { ok = false; }
    if pki_name_rdn_index(&iss, 9) != -1 { ok = false; }
    if !streq(pki_name_oid(&iss, 9), "") { ok = false; }
    if pki_name_value_tag(&iss, 9) != -1 { ok = false; }
    if !streq(pki_name_value(&iss, 9), "") { ok = false; }
    let ex: PkiExtensions = cert.extensions;
    if pki_extension_count(&ex) != 0 { ok = false; }
    if !streq(pki_extension_oid(&ex, 0), "") { ok = false; }
    if pki_extension_critical(&ex, 0) != 0 { ok = false; }
    if pki_path_len(&ex) != -1 { ok = false; }
    if pki_key_usage_value(&ex) != 0 { ok = false; }
    if pki_key_usage_has(&ex, 0) { ok = false; }
    if pki_key_usage_has(&ex, 9) { ok = false; }
    if pki_ext_key_usage_count(&ex) != 0 { ok = false; }
    if !streq(pki_ext_key_usage_oid(&ex, 0), "") { ok = false; }
    if pki_san_count(&ex) != 0 { ok = false; }
    if pki_san_type(&ex, 0) != -1 { ok = false; }
    if !streq(pki_san_value(&ex, 0), "") { ok = false; }
    if !streq(pki_subject_key_id_hex(&ex), "") { ok = false; }
    if !streq(pki_authority_key_id_hex(&ex), "") { ok = false; }
    if pki_certificate_version(&cert) != 0 { ok = false; }
    if !streq(pki_serial_hex(&cert), "2A") { ok = false; }
    if pki_serial_len(&cert) != 1 { ok = false; }
    if pki_version() != 1 { ok = false; }
  }
  return assert(ok, "accessors return neutral values for out-of-range indexes");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.pki conformance tests ===");
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
    io.println("xiom.pki: all tests passed");
  } else {
    io.println("xiom.pki: tests failed");
  }
  return failed;
}
