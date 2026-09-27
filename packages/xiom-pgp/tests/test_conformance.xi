// XIOM -- xiom.pgp conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: packet constants and names, old-format length
// types 0-3, new-format one/two/five-octet and partial body lengths, every
// truncation/bad-tag path, packet accessors and encoding, MPI decode/encode
// (including canonicality), v4 signature bodies and subpacket length forms,
// v4 key bodies for RSA/DSA/ElGamal/ECC algorithms, user-id validation and
// structural binding, CRC24 (pinned to the CRC-24/OPENPGP check value) and
// the ASCII armor codec (headers, base64, checksum, canonical encode).
//
// All synthetic packets and armored blocks are built in-test from raw bytes,
// so the parser is exercised against pinned inputs rather than against the
// package's own encoders. All Str equality goes through str_compare (BUG 17
// discipline); every byte read is widened with `(x as Int) & 0xFF`.

module pgp_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.encoding.hex; use xiom.encoding.base64;
use xiom.pgp;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Bytes of a Str, byte-for-byte.
fn ab(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// Bytes of a hex string ("" on malformed input; the test then fails).
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
    if (((a[i] as Int) & 0xFF) != ((b[i] as Int) & 0xFF)) {
      return false;
    }
    i = i + 1;
  }
  return true;
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

fn concat_bytes(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    v.push(b[i]);
    i = i + 1;
  }
  return v;
}

fn append_bytes(out: &mut Vec[UInt8], v: Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// n copies of a byte value.
fn rep_byte(n: Int, value: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push((value % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// Deterministic byte sequence of length n.
fn seq_bytes(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((i * 37 + 7) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// New-format packet from explicit length-field bytes.
fn pkt_hdr(tag: Int, lenbytes: Vec[UInt8], body: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((192 + tag % 64) as UInt8);
  append_bytes(&mut out, lenbytes);
  append_bytes(&mut out, body);
  return out;
}

fn le1(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push((n % 256) as UInt8);
  return v;
}

fn le2(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push((n / 256) as UInt8);
  v.push((n % 256) as UInt8);
  return v;
}

fn le5(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push((n / 16777216) as UInt8);
  v.push(((n / 65536) % 256) as UInt8);
  v.push(((n / 256) % 256) as UInt8);
  v.push((n % 256) as UInt8);
  return v;
}

// New-format two-octet length field (lengths 192..8383).
fn nf2(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  let x = n - 192;
  v.push((x / 256 + 192) as UInt8);
  v.push((x % 256) as UInt8);
  return v;
}

// New-format five-octet length field (lengths >= 16320).
fn nf5(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(255 as UInt8);
  append_bytes(&mut v, le5(n));
  return v;
}

// Old-format packet: tag byte (128 + tag*4 + ltype), length-field bytes, body.
fn old_pkt(tag: Int, ltype: Int, lenbytes: Vec[UInt8], body: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((128 + tag * 4 + ltype) as UInt8);
  append_bytes(&mut out, lenbytes);
  append_bytes(&mut out, body);
  return out;
}

// Subpacket with a one-octet length header (content < 192).
fn sub1(kind: Int, payload: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(((payload.len() + 1) % 256) as UInt8);
  out.push(kind as UInt8);
  append_bytes(&mut out, payload);
  return out;
}

// Subpacket with a two-octet length header (content 192..8383).
fn sub2(kind: Int, payload: Vec[UInt8]) -> Vec[UInt8] {
  let clen = payload.len() + 1;
  let v = clen - 192;
  var out = Vec[UInt8].new();
  out.push((v / 256 + 192) as UInt8);
  out.push((v % 256) as UInt8);
  out.push(kind as UInt8);
  append_bytes(&mut out, payload);
  return out;
}

// Subpacket with a five-octet length header (content >= 16320).
fn sub5(kind: Int, payload: Vec[UInt8]) -> Vec[UInt8] {
  let clen = payload.len() + 1;
  var out = Vec[UInt8].new();
  out.push(255 as UInt8);
  out.push((clen / 16777216) as UInt8);
  out.push(((clen / 65536) % 256) as UInt8);
  out.push(((clen / 256) % 256) as UInt8);
  out.push((clen % 256) as UInt8);
  out.push(kind as UInt8);
  append_bytes(&mut out, payload);
  return out;
}

// v4 signature body from raw regions.
fn sig_body(st: Int, pka: Int, ha: Int, hashed: Vec[UInt8], unhashed: Vec[UInt8], l16: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(4 as UInt8);
  out.push(st as UInt8);
  out.push(pka as UInt8);
  out.push(ha as UInt8);
  out.push((hashed.len() / 256) as UInt8);
  out.push((hashed.len() % 256) as UInt8);
  append_bytes(&mut out, hashed);
  out.push((unhashed.len() / 256) as UInt8);
  out.push((unhashed.len() % 256) as UInt8);
  append_bytes(&mut out, unhashed);
  append_bytes(&mut out, l16);
  return out;
}

// v4 key header: version 4, creation time, algorithm.
fn key_head(created: Int, algo: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(4 as UInt8);
  out.push((created / 16777216) as UInt8);
  out.push(((created / 65536) % 256) as UInt8);
  out.push(((created / 256) % 256) as UInt8);
  out.push((created % 256) as UInt8);
  out.push(algo as UInt8);
  return out;
}

// MPI bytes via the library encoder ("" on error).
fn mpi(v: Vec[UInt8]) -> Vec[UInt8] {
  let r = pgp_mpi_encode(&v);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  return r.value;
}

// Four base64 characters of a 24-bit CRC value.
fn crc4_text(crc: Int) -> Str {
  let alpha = pgp_base64_alphabet();
  let c0 = crc / 262144;
  let c1 = (crc / 4096) % 64;
  let c2 = (crc / 64) % 64;
  let c3 = crc % 64;
  return string.str_slice(alpha, c0, c0 + 1) + string.str_slice(alpha, c1, c1 + 1)
       + string.str_slice(alpha, c2, c2 + 1) + string.str_slice(alpha, c3, c3 + 1);
}

// An armored block with optional checksum line.
fn armor_block(label: Str, hdrs: Vec[Str], payload: Vec[UInt8], with_crc: Int) -> Str {
  var text = "-----BEGIN " + label + "-----\n";
  var i = 0;
  while i < hdrs.len() {
    let h: Str = hdrs[i];
    text = text + h + "\n";
    i = i + 1;
  }
  text = text + "\n";
  let b = base64.base64_encode(&payload);
  var i2 = 0;
  while i2 < b.len() {
    var bend = i2 + 64;
    if bend > b.len() {
      bend = b.len();
    }
    text = text + string.str_slice(b, i2, bend) + "\n";
    i2 = i2 + 64;
  }
  if with_crc == 1 {
    text = text + "=" + crc4_text(pgp_crc24(&payload)) + "\n";
  }
  text = text + "-----END " + label + "-----\n";
  return text;
}

// --- error checkers ---

fn doc_err_is(r: Result[PgpDocument, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn mpi_err_is(r: Result[PgpMpi, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn sig_err_is(r: Result[PgpSignature, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn key_err_is(r: Result[PgpKey, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn armor_err_is(r: Result[PgpArmor, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when decoding `text` and re-encoding yields exactly `want`.
fn reencode_is(text: Str, want: Str) -> Bool {
  let r = pgp_armor_decode(text);
  if !r.is_ok {
    return false;
  }
  let a: PgpArmor = r.value;
  let e = pgp_armor_encode(&a);
  if !e.is_ok {
    return false;
  }
  return streq(e.value, want);
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = pgp_packet_type_public_key() == 6;
  if pgp_packet_type_public_subkey() != 14 { ok = false; }
  if pgp_packet_type_secret_key() != 5 { ok = false; }
  if pgp_packet_type_signature() != 2 { ok = false; }
  if pgp_packet_type_user_id() != 13 { ok = false; }
  if pgp_packet_type_user_attribute() != 17 { ok = false; }
  if pgp_packet_type_literal_data() != 11 { ok = false; }
  if pgp_packet_type_compressed_data() != 8 { ok = false; }
  if pgp_packet_type_marker() != 10 { ok = false; }
  if pgp_packet_type_trust() != 12 { ok = false; }
  if !streq(pgp_packet_type_name(2), "Signature") { ok = false; }
  if !streq(pgp_packet_type_name(5), "Secret-Key") { ok = false; }
  if !streq(pgp_packet_type_name(6), "Public-Key") { ok = false; }
  if !streq(pgp_packet_type_name(8), "Compressed Data") { ok = false; }
  if !streq(pgp_packet_type_name(10), "Marker") { ok = false; }
  if !streq(pgp_packet_type_name(11), "Literal Data") { ok = false; }
  if !streq(pgp_packet_type_name(12), "Trust") { ok = false; }
  if !streq(pgp_packet_type_name(13), "User ID") { ok = false; }
  if !streq(pgp_packet_type_name(14), "Public-Subkey") { ok = false; }
  if !streq(pgp_packet_type_name(17), "User Attribute") { ok = false; }
  if !streq(pgp_packet_type_name(4), "Unknown") { ok = false; }
  if !streq(pgp_armor_label_message(), "PGP MESSAGE") { ok = false; }
  if !streq(pgp_armor_label_public_key(), "PGP PUBLIC KEY BLOCK") { ok = false; }
  if !streq(pgp_armor_label_private_key(), "PGP PRIVATE KEY BLOCK") { ok = false; }
  if !streq(pgp_armor_label_signature(), "PGP SIGNATURE") { ok = false; }
  if pgp_armor_line_width() != 64 { ok = false; }
  return assert(ok, "constants: ten packet tags, names and armor labels");
}

fn t2() -> TestResult {
  let body = ab("Alice");
  // hand-built: tag byte for tag 13, one-octet length 5, then the body
  var raw = Vec[UInt8].new();
  raw.push(205 as UInt8);
  raw.push(5 as UInt8);
  append_bytes(&mut raw, body);
  let r = pgp_document_parse(raw);
  var ok = r.is_ok;
  if r.is_ok {
    let d: PgpDocument = r.value;
    if pgp_packet_count(&d) != 1 { ok = false; }
    if pgp_packet_tag(&d, 0) != 13 { ok = false; }
    if pgp_packet_format(&d, 0) != 1 { ok = false; }
    if pgp_packet_length_type(&d, 0) != 1 { ok = false; }
    if pgp_packet_header_len(&d, 0) != 2 { ok = false; }
    if pgp_packet_body_len(&d, 0) != 5 { ok = false; }
    if pgp_packet_is_partial(&d, 0) != 0 { ok = false; }
    if pgp_packet_chunk_count(&d, 0) != 1 { ok = false; }
    if pgp_packet_start(&d, 0) != 0 { ok = false; }
    if !bytes_equal(pgp_packet_body(&d, 0), body) { ok = false; }
    if pgp_packet_tag(&d, 1) != -1 { ok = false; }
    if pgp_packet_length_type(&d, -1) != -1 { ok = false; }
    if pgp_packet_body_len(&d, 9) != -1 { ok = false; }
    if pgp_packet_body(&d, 9).len() != 0 { ok = false; }
  }
  return assert(ok, "new-format one-octet header: tag 13 User ID and accessors");
}

fn t3() -> TestResult {
  var ok = true;
  let p191 = pkt_hdr(11, le1(191), rep_byte(191, 65));
  let r1 = pgp_document_parse(p191);
  if !r1.is_ok { ok = false; } else {
    let d1: PgpDocument = r1.value;
    if pgp_packet_length_type(&d1, 0) != 1 { ok = false; }
    if pgp_packet_body_len(&d1, 0) != 191 { ok = false; }
    if !bytes_slice_is(pgp_packet_body(&d1, 0), 0, ab("A")) { ok = false; }
  }
  let p192 = pkt_hdr(11, nf2(192), rep_byte(192, 66));
  let r2 = pgp_document_parse(p192);
  if !r2.is_ok { ok = false; } else {
    let d2: PgpDocument = r2.value;
    if pgp_packet_length_type(&d2, 0) != 2 { ok = false; }
    if pgp_packet_header_len(&d2, 0) != 3 { ok = false; }
    if pgp_packet_body_len(&d2, 0) != 192 { ok = false; }
  }
  let p8383 = pkt_hdr(11, nf2(8383), rep_byte(8383, 67));
  let r3 = pgp_document_parse(p8383);
  if !r3.is_ok { ok = false; } else {
    let d3: PgpDocument = r3.value;
    if pgp_packet_length_type(&d3, 0) != 2 { ok = false; }
    if pgp_packet_body_len(&d3, 0) != 8383 { ok = false; }
  }
  let p8384 = pkt_hdr(11, nf5(8384), rep_byte(8384, 69));
  let r35 = pgp_document_parse(p8384);
  if !r35.is_ok { ok = false; } else {
    let d35: PgpDocument = r35.value;
    if pgp_packet_length_type(&d35, 0) != 5 { ok = false; }
    if pgp_packet_body_len(&d35, 0) != 8384 { ok = false; }
  }
  let p16320 = pkt_hdr(11, nf5(16320), rep_byte(16320, 68));
  let r4 = pgp_document_parse(p16320);
  if !r4.is_ok { ok = false; } else {
    let d4: PgpDocument = r4.value;
    if pgp_packet_length_type(&d4, 0) != 5 { ok = false; }
    if pgp_packet_header_len(&d4, 0) != 6 { ok = false; }
    if pgp_packet_body_len(&d4, 0) != 16320 { ok = false; }
  }
  return assert(ok, "new-format lengths: 191/192/8383/8384/16320 boundaries");
}

fn t4() -> TestResult {
  var ok = true;
  let p0 = old_pkt(11, 0, le1(3), ab("xyz"));
  let r0 = pgp_document_parse(p0);
  if !r0.is_ok { ok = false; } else {
    let d0: PgpDocument = r0.value;
    if pgp_packet_format(&d0, 0) != 0 { ok = false; }
    if pgp_packet_length_type(&d0, 0) != 0 { ok = false; }
    if pgp_packet_header_len(&d0, 0) != 2 { ok = false; }
    if !bytes_equal(pgp_packet_body(&d0, 0), ab("xyz")) { ok = false; }
  }
  let p1 = old_pkt(2, 1, le2(260), rep_byte(260, 70));
  let r1 = pgp_document_parse(p1);
  if !r1.is_ok { ok = false; } else {
    let d1: PgpDocument = r1.value;
    if pgp_packet_length_type(&d1, 0) != 1 { ok = false; }
    if pgp_packet_header_len(&d1, 0) != 3 { ok = false; }
    if pgp_packet_body_len(&d1, 0) != 260 { ok = false; }
  }
  let p2 = old_pkt(6, 2, le5(70000), rep_byte(70000, 71));
  let r2 = pgp_document_parse(p2);
  if !r2.is_ok { ok = false; } else {
    let d2: PgpDocument = r2.value;
    if pgp_packet_length_type(&d2, 0) != 2 { ok = false; }
    if pgp_packet_header_len(&d2, 0) != 5 { ok = false; }
    if pgp_packet_body_len(&d2, 0) != 70000 { ok = false; }
  }
  let p3 = old_pkt(11, 3, Vec[UInt8].new(), ab("rest"));
  let r3 = pgp_document_parse(p3);
  if !r3.is_ok { ok = false; } else {
    let d3: PgpDocument = r3.value;
    if pgp_packet_length_type(&d3, 0) != 3 { ok = false; }
    if pgp_packet_header_len(&d3, 0) != 1 { ok = false; }
    if !bytes_equal(pgp_packet_body(&d3, 0), ab("rest")) { ok = false; }
  }
  return assert(ok, "old-format length types 0/1/2/3 including indeterminate");
}

fn t5() -> TestResult {
  var raw = Vec[UInt8].new();
  raw.push(203 as UInt8);
  raw.push(234 as UInt8);
  append_bytes(&mut raw, rep_byte(1024, 170));
  raw.push(233 as UInt8);
  append_bytes(&mut raw, rep_byte(512, 187));
  raw.push(100 as UInt8);
  append_bytes(&mut raw, rep_byte(100, 204));
  let r = pgp_document_parse(raw);
  var ok = r.is_ok;
  if r.is_ok {
    let d: PgpDocument = r.value;
    if pgp_packet_count(&d) != 1 { ok = false; }
    if pgp_packet_is_partial(&d, 0) != 1 { ok = false; }
    if pgp_packet_chunk_count(&d, 0) != 3 { ok = false; }
    if pgp_packet_body_len(&d, 0) != 1636 { ok = false; }
    if pgp_packet_length_type(&d, 0) != 0 { ok = false; }
    if pgp_packet_header_len(&d, 0) != 2 { ok = false; }
    let body = pgp_packet_body(&d, 0);
    if (((body[0] as Int) & 0xFF) != 170) { ok = false; }
    if (((body[1024] as Int) & 0xFF) != 187) { ok = false; }
    if (((body[1536] as Int) & 0xFF) != 204) { ok = false; }
    if (((body[1635] as Int) & 0xFF) != 204) { ok = false; }
  }
  // a partial packet followed by a definite packet
  var raw2 = Vec[UInt8].new();
  raw2.push(203 as UInt8);
  raw2.push(234 as UInt8);
  append_bytes(&mut raw2, rep_byte(1024, 1));
  raw2.push(2 as UInt8);
  raw2.push(2 as UInt8);
  raw2.push(3 as UInt8);
  append_bytes(&mut raw2, pkt_hdr(13, le1(1), ab("X")));
  let r2 = pgp_document_parse(raw2);
  if !r2.is_ok { ok = false; } else {
    let d2: PgpDocument = r2.value;
    if pgp_packet_count(&d2) != 2 { ok = false; }
    if pgp_packet_body_len(&d2, 0) != 1026 { ok = false; }
    if pgp_packet_tag(&d2, 1) != 13 { ok = false; }
    if pgp_packet_start(&d2, 1) != 1029 { ok = false; }
  }
  // first partial chunk below 512 is rejected
  var raw3 = Vec[UInt8].new();
  raw3.push(203 as UInt8);
  raw3.push(232 as UInt8);
  append_bytes(&mut raw3, rep_byte(256, 1));
  if !doc_err_is(pgp_document_parse(raw3), "pgp: partial body length below 512 at offset 1") { ok = false; }
  // truncated partial chunk
  var raw4 = Vec[UInt8].new();
  raw4.push(203 as UInt8);
  raw4.push(234 as UInt8);
  append_bytes(&mut raw4, rep_byte(10, 1));
  if !doc_err_is(pgp_document_parse(raw4), "pgp: truncated packet body at offset 2") { ok = false; }
  return assert(ok, "partial body lengths: chunk chain, 512 minimum, truncation");
}

fn t6() -> TestResult {
  var ok = true;
  let empty = pgp_document_parse(Vec[UInt8].new());
  if !empty.is_ok { ok = false; } else {
    let d0: PgpDocument = empty.value;
    if pgp_packet_count(&d0) != 0 { ok = false; }
  }
  if !doc_err_is(pgp_document_parse(hb("00")), "pgp: invalid packet tag 0 at offset 0") { ok = false; }
  if !doc_err_is(pgp_document_parse(hb("80")), "pgp: invalid packet tag 128 at offset 0") { ok = false; }
  if !doc_err_is(pgp_document_parse(hb("c0")), "pgp: invalid packet tag 192 at offset 0") { ok = false; }
  if !doc_err_is(pgp_document_parse(hb("89")), "pgp: truncated packet header at offset 1") { ok = false; }
  if !doc_err_is(pgp_document_parse(hb("cd")), "pgp: truncated packet header at offset 1") { ok = false; }
  if !doc_err_is(pgp_document_parse(hb("cdc8")), "pgp: truncated packet header at offset 1") { ok = false; }
  if !doc_err_is(pgp_document_parse(hb("cdff0000")), "pgp: truncated packet header at offset 1") { ok = false; }
  if !doc_err_is(pgp_document_parse(hb("cd0a414141")), "pgp: truncated packet body at offset 2") { ok = false; }
  if !doc_err_is(pgp_document_parse(hb("ac054142")), "pgp: truncated packet body at offset 2") { ok = false; }
  // a valid packet followed by an invalid tag byte
  let good = pkt_hdr(13, le1(1), ab("A"));
  if !doc_err_is(pgp_document_parse(concat_bytes(good, hb("05"))), "pgp: invalid packet tag 5 at offset 3") { ok = false; }
  return assert(ok, "rejections: empty ok, reserved/plain tags, truncated headers and bodies");
}

fn t7() -> TestResult {
  let p1 = pkt_hdr(13, le1(5), ab("Alice"));
  let p2 = pkt_hdr(2, le1(3), ab("sig"));
  let doc = concat_bytes(p1, p2);
  let r = pgp_document_parse(doc);
  var ok = r.is_ok;
  if r.is_ok {
    let d: PgpDocument = r.value;
    if pgp_packet_count(&d) != 2 { ok = false; }
    if pgp_packet_tag(&d, 0) != 13 { ok = false; }
    if pgp_packet_tag(&d, 1) != 2 { ok = false; }
    if pgp_packet_start(&d, 1) != 7 { ok = false; }
    if !bytes_equal(pgp_packet_body(&d, 0), ab("Alice")) { ok = false; }
    if !bytes_equal(pgp_packet_body(&d, 1), ab("sig")) { ok = false; }
  }
  return assert(ok, "two sequential packets: offsets and independent bodies");
}

// Shared signature fixture: sig_type 0, RSA, SHA-256, hashed subpackets
// (creation time + issuer), one unhashed issuer subpacket, left16 ABCD.
fn sig_fixture() -> Vec[UInt8] {
  let hashed = concat_bytes(sub1(2, hb("5f5e1000")), sub1(16, hb("0123456789abcdef")));
  let unhashed = sub1(16, hb("fedcba9876543210"));
  return sig_body(0, 1, 8, hashed, unhashed, hb("abcd"));
}

// Minimal v4 RSA public key body: created 1600000000, algo 1, n=C0DE,
// e=010001.
fn rsa_key_body() -> Vec[UInt8] {
  var body = key_head(1600000000, 1);
  append_bytes(&mut body, mpi(hb("c0de")));
  append_bytes(&mut body, mpi(hb("010001")));
  return body;
}

fn t8() -> TestResult {
  var ok = true;
  let d = hb("ffff00390123456789abcdef");
  let r = pgp_mpi_decode(&d, 2);
  if !r.is_ok { ok = false; } else {
    let m: PgpMpi = r.value;
    if m.bits != 57 { ok = false; }
    if m.value_len != 8 { ok = false; }
    if m.next != 12 { ok = false; }
    if !bytes_equal(pgp_mpi_value_bytes(&d, &m), hb("0123456789abcdef")) { ok = false; }
  }
  let z = hb("0000");
  let rz = pgp_mpi_decode(&z, 0);
  if !rz.is_ok { ok = false; } else {
    let mz: PgpMpi = rz.value;
    if mz.bits != 0 { ok = false; }
    if mz.value_len != 0 { ok = false; }
    if mz.next != 2 { ok = false; }
  }
  let b9 = hb("00090123");
  let r9 = pgp_mpi_decode(&b9, 0);
  if !r9.is_ok { ok = false; } else {
    let m9: PgpMpi = r9.value;
    if m9.bits != 9 { ok = false; }
    if m9.value_len != 2 { ok = false; }
    if m9.next != 4 { ok = false; }
    if !bytes_equal(pgp_mpi_value_bytes(&b9, &m9), hb("0123")) { ok = false; }
  }
  let bad1 = hb("000801");
  if !mpi_err_is(pgp_mpi_decode(&bad1, 0), "pgp: non-canonical MPI at offset 0") { ok = false; }
  let bad2 = hb("00100080");
  if !mpi_err_is(pgp_mpi_decode(&bad2, 0), "pgp: non-canonical MPI at offset 0") { ok = false; }
  let tr1 = hb("00");
  if !mpi_err_is(pgp_mpi_decode(&tr1, 0), "pgp: truncated MPI at offset 0") { ok = false; }
  let tr2 = hb("0010ff");
  if !mpi_err_is(pgp_mpi_decode(&tr2, 0), "pgp: truncated MPI at offset 0") { ok = false; }
  let off = hb("ffff00090102");
  let ro = pgp_mpi_decode(&off, 2);
  if !ro.is_ok { ok = false; } else {
    let mo: PgpMpi = ro.value;
    if mo.bits != 9 { ok = false; }
    if mo.next != 6 { ok = false; }
    if !bytes_equal(pgp_mpi_value_bytes(&off, &mo), hb("0102")) { ok = false; }
  }
  return assert(ok, "MPI decode: bit counts, zero, offsets, truncation, canonicality");
}

fn t9() -> TestResult {
  var ok = true;
  let empty = Vec[UInt8].new();
  let e0 = pgp_mpi_encode(&empty);
  if !e0.is_ok { ok = false; } else { if !bytes_equal(e0.value, hb("0000")) { ok = false; } }
  let v2 = hb("0000");
  let e2 = pgp_mpi_encode(&v2);
  if !e2.is_ok { ok = false; } else { if !bytes_equal(e2.value, hb("0000")) { ok = false; } }
  let v3 = hb("000001");
  let e3 = pgp_mpi_encode(&v3);
  if !e3.is_ok { ok = false; } else { if !bytes_equal(e3.value, hb("000101")) { ok = false; } }
  let v4 = hb("0123");
  let e4 = pgp_mpi_encode(&v4);
  if !e4.is_ok { ok = false; } else { if !bytes_equal(e4.value, hb("00090123")) { ok = false; } }
  let v5 = hb("80");
  let e5 = pgp_mpi_encode(&v5);
  if !e5.is_ok { ok = false; } else { if !bytes_equal(e5.value, hb("000880")) { ok = false; } }
  let v6 = hb("0100");
  let e6 = pgp_mpi_encode(&v6);
  if !e6.is_ok { ok = false; } else { if !bytes_equal(e6.value, hb("00090100")) { ok = false; } }
  let enc = mpi(hb("0123456789abcdef"));
  let dec = pgp_mpi_decode(&enc, 0);
  if !dec.is_ok { ok = false; } else {
    let m: PgpMpi = dec.value;
    if m.bits != 57 { ok = false; }
    if !bytes_equal(pgp_mpi_value_bytes(&enc, &m), hb("0123456789abcdef")) { ok = false; }
  }
  let big = rep_byte(8192, 255);
  if !bytes_err_is(pgp_mpi_encode(&big), "pgp: MPI too large") { ok = false; }
  return assert(ok, "MPI encode: canonical magnitudes, round trip, bit-count limit");
}

fn t10() -> TestResult {
  let body = sig_fixture();
  let r = pgp_signature_v4_decode(&body);
  var ok = r.is_ok;
  if r.is_ok {
    let s: PgpSignature = r.value;
    if pgp_signature_version(&s) != 4 { ok = false; }
    if pgp_signature_type(&s) != 0 { ok = false; }
    if pgp_signature_pubkey_algo(&s) != 1 { ok = false; }
    if pgp_signature_hash_algo(&s) != 8 { ok = false; }
    if pgp_signature_hashed_len(&s) != 16 { ok = false; }
    if pgp_signature_unhashed_len(&s) != 10 { ok = false; }
    if pgp_signature_subpacket_count(&s) != 3 { ok = false; }
    if pgp_signature_subpacket_hashed(&s, 0) != 1 { ok = false; }
    if pgp_signature_subpacket_hashed(&s, 1) != 1 { ok = false; }
    if pgp_signature_subpacket_hashed(&s, 2) != 0 { ok = false; }
    if pgp_signature_subpacket_len(&s, 0) != 5 { ok = false; }
    if pgp_signature_subpacket_len(&s, 1) != 9 { ok = false; }
    if pgp_signature_subpacket_len(&s, 2) != 9 { ok = false; }
    if pgp_signature_subpacket_start(&s, 0) != 7 { ok = false; }
    if pgp_signature_subpacket_start(&s, 1) != 13 { ok = false; }
    if pgp_signature_subpacket_start(&s, 2) != 25 { ok = false; }
    let b0 = pgp_signature_subpacket_bytes(&s, 0);
    if !bytes_slice_is(b0, 0, hb("02")) { ok = false; }
    if !bytes_slice_is(b0, 1, hb("5f5e1000")) { ok = false; }
    let b2 = pgp_signature_subpacket_bytes(&s, 2);
    if !bytes_slice_is(b2, 0, hb("10")) { ok = false; }
    if !bytes_equal(pgp_signature_left16(&s), hb("abcd")) { ok = false; }
    if pgp_signature_subpacket_hashed(&s, 3) != -1 { ok = false; }
    if pgp_signature_subpacket_len(&s, -1) != -1 { ok = false; }
    if pgp_signature_subpacket_bytes(&s, 3).len() != 0 { ok = false; }
  }
  return assert(ok, "v4 signature: fields, subpacket framing and left16");
}

fn t11() -> TestResult {
  let s1 = sub1(60, rep_byte(99, 65));
  let s2 = sub2(61, rep_byte(199, 66));
  let s3 = sub5(62, rep_byte(16319, 67));
  let s4 = sub1(63, rep_byte(190, 68));
  var hashed = Vec[UInt8].new();
  append_bytes(&mut hashed, s1);
  append_bytes(&mut hashed, s2);
  append_bytes(&mut hashed, s3);
  append_bytes(&mut hashed, s4);
  let body = sig_body(0, 1, 8, hashed, Vec[UInt8].new(), hb("0102"));
  let r = pgp_signature_v4_decode(&body);
  var ok = r.is_ok;
  if r.is_ok {
    let s: PgpSignature = r.value;
    if pgp_signature_subpacket_count(&s) != 4 { ok = false; }
    if pgp_signature_subpacket_len(&s, 0) != 100 { ok = false; }
    if pgp_signature_subpacket_len(&s, 1) != 200 { ok = false; }
    if pgp_signature_subpacket_len(&s, 2) != 16320 { ok = false; }
    if pgp_signature_subpacket_len(&s, 3) != 191 { ok = false; }
    let c1 = pgp_signature_subpacket_bytes(&s, 1);
    if !bytes_slice_is(c1, 0, hb("3d")) { ok = false; }
    if c1.len() != 200 { ok = false; }
  }
  return assert(ok, "subpacket length forms: 1/2/5-octet headers at boundaries");
}

fn t12() -> TestResult {
  var ok = true;
  let e0 = Vec[UInt8].new();
  if !sig_err_is(pgp_signature_v4_decode(&e0), "pgp: truncated signature at offset 0") { ok = false; }
  let v3 = hb("0300010a");
  if !sig_err_is(pgp_signature_v4_decode(&v3), "pgp: unsupported signature version 3 at offset 0") { ok = false; }
  let short = hb("04000108");
  if !sig_err_is(pgp_signature_v4_decode(&short), "pgp: truncated signature at offset 4") { ok = false; }
  let hshort = hb("04000108000a414141");
  if !sig_err_is(pgp_signature_v4_decode(&hshort), "pgp: truncated hashed subpackets at offset 6") { ok = false; }
  let zsub = hb("04000108000100");
  if !sig_err_is(pgp_signature_v4_decode(&zsub), "pgp: bad subpacket length at offset 6") { ok = false; }
  let psub = hb("040001080001e0");
  if !sig_err_is(pgp_signature_v4_decode(&psub), "pgp: bad subpacket length at offset 6") { ok = false; }
  let tsub = hb("04000108000405020101");
  if !sig_err_is(pgp_signature_v4_decode(&tsub), "pgp: truncated subpacket at offset 6") { ok = false; }
  let ushort = hb("04000108000000030502");
  if !sig_err_is(pgp_signature_v4_decode(&ushort), "pgp: truncated unhashed subpackets at offset 8") { ok = false; }
  let lmiss = hb("0400010800000000");
  if !sig_err_is(pgp_signature_v4_decode(&lmiss), "pgp: truncated signature at offset 8") { ok = false; }
  let l1 = hb("0400010800000000ab");
  if !sig_err_is(pgp_signature_v4_decode(&l1), "pgp: truncated signature at offset 8") { ok = false; }
  let trail = hb("0400010800000000abcd00");
  if !sig_err_is(pgp_signature_v4_decode(&trail), "pgp: trailing signature data at offset 10") { ok = false; }
  return assert(ok, "v4 signature errors: version, truncation, subpackets, trailing data");
}

fn t13() -> TestResult {
  var ok = true;
  let l0 = pgp_subpacket_length_encode(0);
  if !bytes_err_is(l0, "pgp: bad subpacket length") { ok = false; }
  let l1 = pgp_subpacket_length_encode(1);
  if !l1.is_ok { ok = false; } else { if !bytes_equal(l1.value, hb("01")) { ok = false; } }
  let l191 = pgp_subpacket_length_encode(191);
  if !l191.is_ok { ok = false; } else { if !bytes_equal(l191.value, hb("bf")) { ok = false; } }
  let l192 = pgp_subpacket_length_encode(192);
  if !l192.is_ok { ok = false; } else { if !bytes_equal(l192.value, hb("c000")) { ok = false; } }
  let l8383 = pgp_subpacket_length_encode(8383);
  if !l8383.is_ok { ok = false; } else { if !bytes_equal(l8383.value, hb("dfff")) { ok = false; } }
  let l8384 = pgp_subpacket_length_encode(8384);
  if !l8384.is_ok { ok = false; } else { if !bytes_equal(l8384.value, hb("ff000020c0")) { ok = false; } }
  let l16320 = pgp_subpacket_length_encode(16320);
  if !l16320.is_ok { ok = false; } else { if !bytes_equal(l16320.value, hb("ff00003fc0")) { ok = false; } }
  let lbig = pgp_subpacket_length_encode(4294967296);
  if !bytes_err_is(lbig, "pgp: subpacket too large") { ok = false; }
  let sp = pgp_subpacket_encode(2, hb("5f5e1000"));
  if !sp.is_ok { ok = false; } else { if !bytes_equal(sp.value, hb("05025f5e1000")) { ok = false; } }
  let spbad = pgp_subpacket_encode(300, Vec[UInt8].new());
  if !bytes_err_is(spbad, "pgp: bad subpacket type") { ok = false; }
  let hashed = concat_bytes(sub1(2, hb("5f5e1000")), sub1(16, hb("0123456789abcdef")));
  let unhashed = sub1(16, hb("fedcba9876543210"));
  let l16 = hb("abcd");
  let body_r = pgp_signature_v4_encode(0, 1, 8, &hashed, &unhashed, &l16);
  if !body_r.is_ok { ok = false; } else {
    let enc: Vec[UInt8] = body_r.value;
    if !bytes_equal(enc, sig_fixture()) { ok = false; }
    let d = pgp_signature_v4_decode(&enc);
    if !d.is_ok { ok = false; } else {
      let s: PgpSignature = d.value;
      if pgp_signature_subpacket_count(&s) != 3 { ok = false; }
      if !bytes_equal(pgp_signature_left16(&s), l16) { ok = false; }
    }
  }
  let l16bad = hb("ab");
  if !bytes_err_is(pgp_signature_v4_encode(0, 1, 8, &hashed, &unhashed, &l16bad), "pgp: bad left16 length") { ok = false; }
  let big = rep_byte(70000, 1);
  let none = Vec[UInt8].new();
  if !bytes_err_is(pgp_signature_v4_encode(0, 1, 8, &big, &none, &l16), "pgp: subpacket region too long") { ok = false; }
  if !bytes_err_is(pgp_signature_v4_encode(300, 1, 8, &none, &none, &l16), "pgp: bad signature field value") { ok = false; }
  return assert(ok, "signature and subpacket encode: pinned forms, round trip, limits");
}

fn t14() -> TestResult {
  let body = rsa_key_body();
  let r = pgp_key_v4_decode(&body);
  var ok = r.is_ok;
  if r.is_ok {
    let k: PgpKey = r.value;
    if pgp_key_version(&k) != 4 { ok = false; }
    if pgp_key_created(&k) != 1600000000 { ok = false; }
    if pgp_key_algo(&k) != 1 { ok = false; }
    if pgp_key_mpi_count(&k) != 2 { ok = false; }
    if pgp_key_mpi_bits(&k, 0) != 16 { ok = false; }
    if pgp_key_mpi_bits(&k, 1) != 17 { ok = false; }
    if pgp_key_mpi_value_len(&k, 0) != 2 { ok = false; }
    if pgp_key_mpi_value_len(&k, 1) != 3 { ok = false; }
    if !bytes_equal(pgp_key_mpi_value_bytes(&k, 0), hb("c0de")) { ok = false; }
    if !bytes_equal(pgp_key_mpi_value_bytes(&k, 1), hb("010001")) { ok = false; }
    if pgp_key_public_end(&k) != 15 { ok = false; }
    if pgp_key_oid_len(&k) != 0 { ok = false; }
    if pgp_key_oid_bytes(&k).len() != 0 { ok = false; }
    if pgp_key_mpi_bits(&k, 2) != -1 { ok = false; }
    if pgp_key_mpi_value_bytes(&k, 9).len() != 0 { ok = false; }
  }
  // secret material after the public MPIs is accepted and does not move
  // public_end
  var sec = Vec[UInt8].new();
  append_bytes(&mut sec, body);
  append_bytes(&mut sec, mpi(hb("01")));
  append_bytes(&mut sec, mpi(hb("02")));
  append_bytes(&mut sec, mpi(hb("03")));
  append_bytes(&mut sec, mpi(hb("04")));
  let rs = pgp_key_v4_decode(&sec);
  if !rs.is_ok { ok = false; } else {
    let ks: PgpKey = rs.value;
    if pgp_key_mpi_count(&ks) != 2 { ok = false; }
    if pgp_key_public_end(&ks) != 15 { ok = false; }
  }
  return assert(ok, "v4 RSA key body: creation time, n/e MPIs, secret-material split");
}

fn t15() -> TestResult {
  var ok = true;
  // DSA: p, q, g, y
  var dsa = key_head(1000, 17);
  append_bytes(&mut dsa, mpi(hb("0102030405")));
  append_bytes(&mut dsa, mpi(hb("0102")));
  append_bytes(&mut dsa, mpi(hb("0304")));
  append_bytes(&mut dsa, mpi(hb("0506")));
  let rd = pgp_key_v4_decode(&dsa);
  if !rd.is_ok { ok = false; } else {
    let kd: PgpKey = rd.value;
    if pgp_key_algo(&kd) != 17 { ok = false; }
    if pgp_key_mpi_count(&kd) != 4 { ok = false; }
  }
  // ElGamal: p, g, y
  var eg = key_head(2000, 16);
  append_bytes(&mut eg, mpi(hb("0102")));
  append_bytes(&mut eg, mpi(hb("03")));
  append_bytes(&mut eg, mpi(hb("04")));
  let re = pgp_key_v4_decode(&eg);
  if !re.is_ok { ok = false; } else {
    let ke: PgpKey = re.value;
    if pgp_key_algo(&ke) != 16 { ok = false; }
    if pgp_key_mpi_count(&ke) != 3 { ok = false; }
  }
  // ECDSA (algo 19): one-octet OID length, OID, one point MPI
  var ec = key_head(3000, 19);
  ec.push(8 as UInt8);
  append_bytes(&mut ec, hb("2a8648ce3d030107"));
  append_bytes(&mut ec, mpi(hb("04ff")));
  let rc = pgp_key_v4_decode(&ec);
  if !rc.is_ok { ok = false; } else {
    let kc: PgpKey = rc.value;
    if pgp_key_algo(&kc) != 19 { ok = false; }
    if pgp_key_oid_len(&kc) != 8 { ok = false; }
    if !bytes_equal(pgp_key_oid_bytes(&kc), hb("2a8648ce3d030107")) { ok = false; }
    if pgp_key_mpi_count(&kc) != 1 { ok = false; }
    if pgp_key_public_end(&kc) != 19 { ok = false; }
  }
  // EdDSA (algo 22): OID + one MPI
  var ed = key_head(4000, 22);
  ed.push(9 as UInt8);
  append_bytes(&mut ed, hb("2b06010401da470f01"));
  append_bytes(&mut ed, mpi(hb("0102")));
  let red = pgp_key_v4_decode(&ed);
  if !red.is_ok { ok = false; } else {
    let ked: PgpKey = red.value;
    if pgp_key_oid_len(&ked) != 9 { ok = false; }
    if pgp_key_mpi_count(&ked) != 1 { ok = false; }
  }
  // RFC 9580 native X25519 (algo 25): no OID, one MPI
  var x = key_head(5000, 25);
  append_bytes(&mut x, mpi(hb("09")));
  let rx = pgp_key_v4_decode(&x);
  if !rx.is_ok { ok = false; } else {
    let kx: PgpKey = rx.value;
    if pgp_key_oid_len(&kx) != 0 { ok = false; }
    if pgp_key_mpi_count(&kx) != 1 { ok = false; }
  }
  // unsupported algorithm and version
  let badalgo = key_head(1, 99);
  if !key_err_is(pgp_key_v4_decode(&badalgo), "pgp: unsupported key algorithm 99 at offset 5") { ok = false; }
  let badver = hb("030000000001");
  if !key_err_is(pgp_key_v4_decode(&badver), "pgp: unsupported key version 3 at offset 0") { ok = false; }
  // truncations and OID failures
  let e0 = Vec[UInt8].new();
  if !key_err_is(pgp_key_v4_decode(&e0), "pgp: truncated key at offset 0") { ok = false; }
  let v4only = hb("04");
  if !key_err_is(pgp_key_v4_decode(&v4only), "pgp: truncated key at offset 1") { ok = false; }
  let noalgo = hb("0400000000");
  if !key_err_is(pgp_key_v4_decode(&noalgo), "pgp: truncated key at offset 5") { ok = false; }
  let bado = hb("04000000001300");
  if !key_err_is(pgp_key_v4_decode(&bado), "pgp: bad curve OID at offset 6") { ok = false; }
  let trunco = hb("040000000013082a");
  if !key_err_is(pgp_key_v4_decode(&trunco), "pgp: truncated key at offset 7") { ok = false; }
  let noncanon = hb("040000000001000801");
  if !key_err_is(pgp_key_v4_decode(&noncanon), "pgp: non-canonical MPI at offset 6") { ok = false; }
  return assert(ok, "v4 key bodies: DSA/ElGamal/ECDSA/EdDSA/X25519 and key errors");
}

fn t16() -> TestResult {
  var ok = true;
  let key = pkt_hdr(6, le1(15), rsa_key_body());
  let uid = pkt_hdr(13, le1(25), ab("Alice <alice@example.com>"));
  let none = Vec[UInt8].new();
  let l16 = hb("abcd");
  let sb = pgp_signature_v4_encode(19, 1, 8, &none, &none, &l16);
  if !sb.is_ok { ok = false; } else {
    let sbv: Vec[UInt8] = sb.value;
    let sigp = pkt_hdr(2, le1(sbv.len()), sbv);
    let r = pgp_document_parse(concat_bytes(concat_bytes(key, uid), sigp));
    if !r.is_ok { ok = false; } else {
      let doc: PgpDocument = r.value;
      if pgp_packet_count(&doc) != 3 { ok = false; }
      let tn = pgp_user_id_text(&doc, 1);
      if !tn.is_ok { ok = false; } else {
        if !streq(tn.value, "Alice <alice@example.com>") { ok = false; }
      }
      if pgp_user_id_key_index(&doc, 1) != 0 { ok = false; }
      if pgp_user_id_binding_signature(&doc, 1) != 2 { ok = false; }
      if pgp_user_id_key_index(&doc, 0) != -1 { ok = false; }
      if pgp_user_id_binding_signature(&doc, 0) != -1 { ok = false; }
      let t0 = pgp_user_id_text(&doc, 0);
      if t0.is_ok { ok = false; } else {
        if !streq(t0.error, "pgp: not a user id packet") { ok = false; }
      }
      let t9 = pgp_user_id_text(&doc, 9);
      if t9.is_ok { ok = false; } else {
        if !streq(t9.error, "pgp: not a user id packet") { ok = false; }
      }
    }
  }
  // a user id with no preceding key and no following signature
  let uid_only = pkt_hdr(13, le1(25), ab("Alice <alice@example.com>"));
  let r2 = pgp_document_parse(uid_only);
  if !r2.is_ok { ok = false; } else {
    let doc2: PgpDocument = r2.value;
    if pgp_user_id_key_index(&doc2, 0) != -1 { ok = false; }
    if pgp_user_id_binding_signature(&doc2, 0) != -1 { ok = false; }
  }
  // empty and control-byte user ids
  let uempty = pkt_hdr(13, le1(0), Vec[UInt8].new());
  let re = pgp_document_parse(uempty);
  if !re.is_ok { ok = false; } else {
    let de: PgpDocument = re.value;
    let te = pgp_user_id_text(&de, 0);
    if te.is_ok { ok = false; } else {
      if !streq(te.error, "pgp: user id is empty") { ok = false; }
    }
  }
  let uctl = pkt_hdr(13, le1(5), ab("ab\ncd"));
  let rc = pgp_document_parse(uctl);
  if !rc.is_ok { ok = false; } else {
    let dc: PgpDocument = rc.value;
    let tc = pgp_user_id_text(&dc, 0);
    if tc.is_ok { ok = false; } else {
      if !streq(tc.error, "pgp: user id has a non-printable byte at offset 2") { ok = false; }
    }
  }
  return assert(ok, "user id: printable text, empty/control rejection, key binding");
}

fn t17() -> TestResult {
  var ok = true;
  let l0 = pgp_new_length_encode(0);
  if !bytes_equal(l0, hb("00")) { ok = false; }
  let l191 = pgp_new_length_encode(191);
  if !bytes_equal(l191, hb("bf")) { ok = false; }
  let l192 = pgp_new_length_encode(192);
  if !bytes_equal(l192, hb("c000")) { ok = false; }
  let l8383 = pgp_new_length_encode(8383);
  if !bytes_equal(l8383, hb("dfff")) { ok = false; }
  let l8384 = pgp_new_length_encode(8384);
  if !bytes_equal(l8384, hb("ff000020c0")) { ok = false; }
  let l16320 = pgp_new_length_encode(16320);
  if !bytes_equal(l16320, hb("ff00003fc0")) { ok = false; }
  let l70000 = pgp_new_length_encode(70000);
  if !bytes_equal(l70000, hb("ff00011170")) { ok = false; }
  let bob = ab("Bob");
  let pkt = pgp_packet_encode(13, &bob);
  if !bytes_equal(pkt, hb("cd03426f62")) { ok = false; }
  let r = pgp_document_parse(pkt);
  if !r.is_ok { ok = false; } else {
    let d: PgpDocument = r.value;
    if pgp_packet_tag(&d, 0) != 13 { ok = false; }
    if !bytes_equal(pgp_packet_body(&d, 0), bob) { ok = false; }
  }
  let b200 = rep_byte(200, 7);
  let p200 = pgp_packet_encode(11, &b200);
  let r200 = pgp_document_parse(p200);
  if !r200.is_ok { ok = false; } else {
    let d200: PgpDocument = r200.value;
    if pgp_packet_length_type(&d200, 0) != 2 { ok = false; }
    if pgp_packet_body_len(&d200, 0) != 200 { ok = false; }
  }
  let b16k = rep_byte(16320, 8);
  let p16k = pgp_packet_encode(11, &b16k);
  let r16k = pgp_document_parse(p16k);
  if !r16k.is_ok { ok = false; } else {
    let d16k: PgpDocument = r16k.value;
    if pgp_packet_length_type(&d16k, 0) != 5 { ok = false; }
    if pgp_packet_body_len(&d16k, 0) != 16320 { ok = false; }
  }
  let e1 = pgp_packet_encode(13, &bob);
  let e2 = pgp_packet_encode(2, &b200);
  let r2 = pgp_document_parse(concat_bytes(e1, e2));
  if !r2.is_ok { ok = false; } else {
    let d2: PgpDocument = r2.value;
    if pgp_packet_count(&d2) != 2 { ok = false; }
    if pgp_packet_tag(&d2, 0) != 13 { ok = false; }
    if pgp_packet_tag(&d2, 1) != 2 { ok = false; }
  }
  return assert(ok, "packet encode: length boundaries and parse round trips");
}

fn t18() -> TestResult {
  var ok = true;
  let check = ab("123456789");
  if pgp_crc24(&check) != 2215682 { ok = false; }
  let empty = Vec[UInt8].new();
  if pgp_crc24(&empty) != 11994318 { ok = false; }
  let hello = ab("Hello");
  if pgp_crc24(&hello) != 1077836 { ok = false; }
  let hp = ab("Hello, PGP!");
  if pgp_crc24(&hp) != 9346619 { ok = false; }
  let fox = ab("The quick brown fox jumps over the lazy dog");
  if pgp_crc24(&fox) != 10641804 { ok = false; }
  if !streq(crc4_text(2215682), "Ic8C") { ok = false; }
  if !streq(crc4_text(11994318), "twTO") { ok = false; }
  if !streq(crc4_text(1077836), "EHJM") { ok = false; }
  if !streq(crc4_text(9346619), "jp47") { ok = false; }
  return assert(ok, "CRC24: pinned check values and armor checksum characters");
}

fn t19() -> TestResult {
  var ok = true;
  let hello = ab("Hello");
  var hdrs = Vec[Str].new();
  hdrs.push("Version: XIOM 0.1");
  hdrs.push("Comment: test");
  let block = armor_block("PGP MESSAGE", hdrs, hello, 1);
  let r = pgp_armor_decode(block);
  if !r.is_ok { ok = false; } else {
    let a: PgpArmor = r.value;
    if !streq(pgp_armor_label(&a), "PGP MESSAGE") { ok = false; }
    if pgp_armor_header_count(&a) != 2 { ok = false; }
    if !streq(pgp_armor_header_line(&a, 0), "Version: XIOM 0.1") { ok = false; }
    if !streq(pgp_armor_header_line(&a, 1), "Comment: test") { ok = false; }
    if !streq(pgp_armor_header_line(&a, 2), "") { ok = false; }
    if pgp_armor_has_crc(&a) != 1 { ok = false; }
    if pgp_armor_crc(&a) != 1077836 { ok = false; }
    if pgp_armor_payload_len(&a) != 5 { ok = false; }
    if !bytes_equal(pgp_armor_payload(&a), hello) { ok = false; }
  }
  let pinned = "-----BEGIN PGP MESSAGE-----\nVersion: XIOM 0.1\n\nSGVsbG8=\n=EHJM\n-----END PGP MESSAGE-----\n";
  let rp = pgp_armor_decode(pinned);
  if !rp.is_ok { ok = false; } else {
    let ap: PgpArmor = rp.value;
    if !bytes_equal(pgp_armor_payload(&ap), hello) { ok = false; }
    if pgp_armor_crc(&ap) != 1077836 { ok = false; }
  }
  if !reencode_is(pinned, pinned) { ok = false; }
  let nocrc = armor_block("PGP SIGNATURE", Vec[Str].new(), hello, 0);
  let rn = pgp_armor_decode(nocrc);
  if !rn.is_ok { ok = false; } else {
    let an: PgpArmor = rn.value;
    if pgp_armor_has_crc(&an) != 0 { ok = false; }
    if !bytes_equal(pgp_armor_payload(&an), hello) { ok = false; }
  }
  let p60 = seq_bytes(60);
  let multi = armor_block("PGP MESSAGE", Vec[Str].new(), p60, 1);
  let rm = pgp_armor_decode(multi);
  if !rm.is_ok { ok = false; } else {
    let am: PgpArmor = rm.value;
    if !bytes_equal(pgp_armor_payload(&am), p60) { ok = false; }
  }
  let crlf = string.replace(pinned, "\n", "\r\n");
  let rc = pgp_armor_decode(crlf);
  if !rc.is_ok { ok = false; } else {
    let ac: PgpArmor = rc.value;
    if !bytes_equal(pgp_armor_payload(&ac), hello) { ok = false; }
  }
  return assert(ok, "armor decode: headers, checksum, no-CRC, CRLF, multi-line body");
}

fn t20() -> TestResult {
  var ok = true;
  let hello = ab("Hello");
  let good = armor_block("PGP MESSAGE", Vec[Str].new(), hello, 1);
  let bad = string.replace(good, "=EHJM", "=EHJN");
  if !armor_err_is(pgp_armor_decode(bad), "pgp: armor checksum mismatch") { ok = false; }
  let b1 = "-----BEGIN PGP MESSAGE-----\n\nSGVsbG8=\n=ABC\n-----END PGP MESSAGE-----\n";
  if !armor_err_is(pgp_armor_decode(b1), "pgp: armor bad checksum line") { ok = false; }
  let b2 = "-----BEGIN PGP MESSAGE-----\n\nSGVsbG8=\n=ABC!D\n-----END PGP MESSAGE-----\n";
  if !armor_err_is(pgp_armor_decode(b2), "pgp: armor bad checksum line") { ok = false; }
  let b3 = "-----BEGIN PGP MESSAGE-----\n\nSGVsbG8=\n=EHJM\nAAAA\n-----END PGP MESSAGE-----\n";
  if !armor_err_is(pgp_armor_decode(b3), "pgp: armor text after checksum") { ok = false; }
  let b4 = "-----BEGIN PGP MESSAGE-----\n\n=twTO\n-----END PGP MESSAGE-----\n";
  let r4 = pgp_armor_decode(b4);
  if !r4.is_ok { ok = false; } else {
    let a4: PgpArmor = r4.value;
    if pgp_armor_payload_len(&a4) != 0 { ok = false; }
    if pgp_armor_has_crc(&a4) != 1 { ok = false; }
    if pgp_armor_crc(&a4) != 11994318 { ok = false; }
  }
  return assert(ok, "armor checksum: mismatch, malformed line, text after, empty payload");
}

fn t21() -> TestResult {
  var ok = true;
  let empty = pgp_armor_decode("");
  if !armor_err_is(empty, "pgp: armor no block found") { ok = false; }
  let malformed = "-----BEGIN PGP MESSAGE----\n\nSGVsbG8=\n-----END PGP MESSAGE-----\n";
  if !armor_err_is(pgp_armor_decode(malformed), "pgp: armor malformed block marker") { ok = false; }
  let mismatch = "-----BEGIN PGP MESSAGE-----\n\nSGVsbG8=\n-----END PGP SIGNATURE-----\n";
  if !armor_err_is(pgp_armor_decode(mismatch), "pgp: armor label mismatch") { ok = false; }
  let badchar = "-----BEGIN PGP MESSAGE-----\n\nAA!A\n-----END PGP MESSAGE-----\n";
  if !armor_err_is(pgp_armor_decode(badchar), "pgp: armor invalid base64 character") { ok = false; }
  let badpad = "-----BEGIN PGP MESSAGE-----\n\nAAA\n-----END PGP MESSAGE-----\n";
  if !armor_err_is(pgp_armor_decode(badpad), "pgp: armor bad padding") { ok = false; }
  let noncanon = "-----BEGIN PGP MESSAGE-----\n\nTR==\n-----END PGP MESSAGE-----\n";
  if !armor_err_is(pgp_armor_decode(noncanon), "pgp: armor non-canonical trailing bits") { ok = false; }
  let unterm = "-----BEGIN PGP MESSAGE-----\n\nSGVsbG8=\n";
  if !armor_err_is(pgp_armor_decode(unterm), "pgp: armor unterminated block") { ok = false; }
  let good = armor_block("PGP MESSAGE", Vec[Str].new(), ab("Hello"), 1);
  if !armor_err_is(pgp_armor_decode("junk\n" + good), "pgp: armor text outside blocks") { ok = false; }
  if !armor_err_is(pgp_armor_decode(good + "junk\n"), "pgp: armor text outside blocks") { ok = false; }
  let hterm = "-----BEGIN PGP MESSAGE-----\nVersion: 1\n-----END PGP MESSAGE-----\n";
  if !armor_err_is(pgp_armor_decode(hterm), "pgp: armor header section not terminated") { ok = false; }
  let hafter = "-----BEGIN PGP MESSAGE-----\n\nAAAA\nVersion: 1\n-----END PGP MESSAGE-----\n";
  if !armor_err_is(pgp_armor_decode(hafter), "pgp: armor header after body") { ok = false; }
  let blk = "-----BEGIN PGP MESSAGE-----\n\nAAAA\n\nAAAA\n-----END PGP MESSAGE-----\n";
  if !armor_err_is(pgp_armor_decode(blk), "pgp: armor blank line in body") { ok = false; }
  let longline = "-----BEGIN PGP MESSAGE-----\n\n" + string.str_repeat("A", 77) + "\n-----END PGP MESSAGE-----\n";
  if !armor_err_is(pgp_armor_decode(longline), "pgp: armor bad body line length") { ok = false; }
  let nested = "-----BEGIN PGP MESSAGE-----\n-----BEGIN PGP SIGNATURE-----\n\nAAAA\n-----END PGP SIGNATURE-----\n-----END PGP MESSAGE-----\n";
  if !armor_err_is(pgp_armor_decode(nested), "pgp: armor nested block not allowed") { ok = false; }
  return assert(ok, "armor framing errors: markers, text, headers, body rules");
}

fn t22() -> TestResult {
  var ok = true;
  let pinned = "-----BEGIN PGP MESSAGE-----\nVersion: XIOM 0.1\n\nSGVsbG8=\n=EHJM\n-----END PGP MESSAGE-----\n";
  let nocrc = "-----BEGIN PGP MESSAGE-----\nVersion: XIOM 0.1\n\nSGVsbG8=\n-----END PGP MESSAGE-----\n";
  if !reencode_is(nocrc, pinned) { ok = false; }
  let h1 = ab("Hello");
  let badlabel = PgpArmor{ label: "BAD-LABEL"; headers: Vec[Str].new(); data: h1; crc: 0; has_crc: 0; };
  if !str_err_is(pgp_armor_encode(&badlabel), "pgp: armor invalid label") { ok = false; }
  let h2 = ab("Hello");
  var hdrs2 = Vec[Str].new();
  hdrs2.push("NoColon");
  let badhdr = PgpArmor{ label: "PGP MESSAGE"; headers: hdrs2; data: h2; crc: 0; has_crc: 0; };
  if !str_err_is(pgp_armor_encode(&badhdr), "pgp: armor bad header line") { ok = false; }
  let p60 = seq_bytes(60);
  let b60 = base64.base64_encode(&p60);
  let expect = "-----BEGIN PGP MESSAGE-----\n\n" + string.str_slice(b60, 0, 64) + "\n"
    + string.str_slice(b60, 64, b60.len()) + "\n=" + crc4_text(pgp_crc24(&p60))
    + "\n-----END PGP MESSAGE-----\n";
  let a60 = PgpArmor{ label: "PGP MESSAGE"; headers: Vec[Str].new(); data: p60; crc: 0; has_crc: 0; };
  let e60 = pgp_armor_encode(&a60);
  if !e60.is_ok { ok = false; } else {
    if !streq(e60.value, expect) { ok = false; }
  }
  return assert(ok, "armor encode: canonical form, wrapping, validation errors");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.pgp conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.pgp: all tests passed");
  } else {
    io.println("xiom.pgp: tests failed");
  }
  return failed;
}


