// XIOM -- xiom.tls conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Synthetic record/handshake buffers built in-test (hex literals plus a few
// builders): record parse and its error catalog, ClientHello with
// SNI/ALPN/supported_versions/supported_groups/signature_algorithms/
// key_share/unknown extensions, ServerHello, EncryptedExtensions,
// Certificate DER slice offsets, ServerKeyExchange/ClientKeyExchange,
// Finished, NewSessionTicket, alert and CCS decode, extension edge cases,
// multi-record handshake reassembly and one-message-at-a-time parsing with
// consumed counts.
//
// Str values are compared with xiom.string.compare.str_compare (BUG 17
// discipline); every Vec read is bound to a typed local; error Result values
// are matched without constructing Ok/Err in the test functions.

module tls_tests
use xiom.io; use xiom.test;
use xiom.tls;
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

fn slice_bytes(v: Vec[UInt8], start: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    out.push(v[start + i]);
    i = i + 1;
  }
  return out;
}

fn concat_bytes(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// One TLS record: type, legacy version 0x0303, u16 length, fragment.
fn rec_bytes(ct: Int, frag: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(ct as UInt8);
  out.push(3 as UInt8);
  out.push(3 as UInt8);
  out.push((frag.len() / 256) as UInt8);
  out.push((frag.len() % 256) as UInt8);
  var i = 0;
  while i < frag.len() {
    out.push(frag[i]);
    i = i + 1;
  }
  return out;
}

fn err_rec_is(r: Result[TlsRecord, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_hs_is(r: Result[TlsHandshake, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_ch_is(r: Result[TlsClientHello, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_sh_is(r: Result[TlsServerHello, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_ee_is(r: Result[TlsEncryptedExtensions, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_cert_is(r: Result[TlsCertificate, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_kx_is(r: Result[TlsKeyExchange, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_fin_is(r: Result[TlsFinished, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_nst_is(r: Result[TlsNewSessionTicket, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_alert_is(r: Result[TlsAlert, Str], want: Str) -> Bool {
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

fn err_exts_is(r: Result[TlsExtensions, Str], want: Str) -> Bool {
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

fn err_pair_is(r: Result[(Int, Int), Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// The full-featured ClientHello hex used by several tests: legacy 0x0303,
// 32-byte random, 4-byte session id, suites 1301 1302, null compression and
// extensions SNI(a.bc) ALPN(h2,http/1.1) supported_versions(0304,0303)
// supported_groups(x25519,secp256k1) signature_algorithms(ecdsa256,pss256)
// key_share(x25519:aabb) unknown(ff01:deadbeef).
fn ch_hex() -> Str {
  return "01000081" +
    "0303" +
    "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff" +
    "04aabbccdd" +
    "000413011302" +
    "0100" +
    "0050" +
    "000000090007000004" + "612e6263" +
    "0010000e000c02683208687474702f312e31" +
    "002b0005040304" + "0303" +
    "000a00060004001d0017" +
    "000d0006000404030804" +
    "003300080006" + "001d0002aabb" +
    "ff010004deadbeef";
}

// Minimal ClientHello: empty session id, one suite 002f, null compression,
// no extensions (41-byte body).
fn ch_min_hex() -> Str {
  return "01000029" +
    "0303" +
    "1111111111111111111111111111111111111111111111111111111111111111" +
    "00" +
    "0002" + "002f" +
    "0100";
}

// ServerHello: legacy 0x0303, random 22*32, empty session id, suite 1301,
// null compression, supported_versions selected 0x0304.
fn sh_hex() -> Str {
  return "0200002e" +
    "0303" +
    "2222222222222222222222222222222222222222222222222222222222222222" +
    "00" +
    "1301" +
    "00" +
    "0006" + "002b0002" + "0304";
}

// Finished with 32 bytes of verify data.
fn fin_hex() -> Str {
  return "14000020" +
    "3333333333333333333333333333333333333333333333333333333333333333";
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let two = hb("1603030004aabbccdd15030300020100");
  let r1 = tls_parse_record(&two, 0);
  var ok = r1.is_ok;
  if !ok {
    return assert(false, "record 0 must parse");
  }
  let rec1: TlsRecord = r1.value;
  if rec1.content_type != 22 { ok = false; }
  if rec1.version != 771 { ok = false; }
  if rec1.length != 4 { ok = false; }
  if rec1.start != 0 { ok = false; }
  if rec1.fragment_off != 5 { ok = false; }
  if rec1.end != 9 { ok = false; }
  let f1 = tls_record_fragment(&two, &rec1);
  if !bytes_equal(f1, hb("aabbccdd")) { ok = false; }
  let r2 = tls_parse_record(&two, 9);
  if !r2.is_ok { ok = false; } else {
    let rec2: TlsRecord = r2.value;
    if rec2.content_type != 21 { ok = false; }
    if rec2.length != 2 { ok = false; }
    if rec2.fragment_off != 14 { ok = false; }
    if rec2.end != 16 { ok = false; }
  }
  if !str_eq(tls_content_type_name(20), "change_cipher_spec") { ok = false; }
  if !str_eq(tls_content_type_name(21), "alert") { ok = false; }
  if !str_eq(tls_content_type_name(22), "handshake") { ok = false; }
  if !str_eq(tls_content_type_name(23), "application_data") { ok = false; }
  if !str_eq(tls_content_type_name(24), "heartbeat") { ok = false; }
  if !str_eq(tls_content_type_name(25), "") { ok = false; }
  if !str_eq(tls_legacy_version_name(769), "TLS 1.0") { ok = false; }
  if !str_eq(tls_legacy_version_name(770), "TLS 1.1") { ok = false; }
  if !str_eq(tls_legacy_version_name(771), "TLS 1.2") { ok = false; }
  if !str_eq(tls_legacy_version_name(772), "TLS 1.3") { ok = false; }
  if !str_eq(tls_legacy_version_name(768), "SSL 3.0") { ok = false; }
  if !tls_content_type_ok(20) || !tls_content_type_ok(24) { ok = false; }
  if tls_content_type_ok(19) || tls_content_type_ok(25) { ok = false; }
  if !tls_legacy_version_ok(769) || !tls_legacy_version_ok(772) { ok = false; }
  if tls_legacy_version_ok(768) || tls_legacy_version_ok(773) { ok = false; }
  if !tls_version_is_tls13(772) { ok = false; }
  if tls_version_is_tls13(771) { ok = false; }
  return assert(ok, "record parse pinned bytes, offsets and name helpers");
}

fn t2() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = err_rec_is(tls_parse_record(&empty, 0), "tls: truncated record header at 0");
  if !err_rec_is(tls_parse_record(&hb("1603030004aabbcc"), 0), "tls: truncated record fragment at 0") { ok = false; }
  if !err_rec_is(tls_parse_record(&hb("1a03030001aa"), 0), "tls: bad content type at 0") { ok = false; }
  if !err_rec_is(tls_parse_record(&hb("1603000001aa"), 0), "tls: bad record version at 0") { ok = false; }
  if !err_rec_is(tls_parse_record(&hb("1603050001aa"), 0), "tls: bad record version at 0") { ok = false; }
  if !err_rec_is(tls_parse_record(&hb("1603030000"), 0), "tls: zero-length record at 0") { ok = false; }
  if !err_rec_is(tls_parse_record(&hb("1603034001aa"), 0), "tls: record overlength at 0") { ok = false; }
  if !err_rec_is(tls_parse_record(&hb("ffff"), 3), "tls: truncated record header at 3") { ok = false; }
  if !err_rec_is(tls_parse_record(&hb("ffff"), -1), "tls: negative offset") { ok = false; }
  return assert(ok, "record errors: truncation, type, version, zero, overlength, offset");
}

fn t3() -> TestResult {
  var ok = true;
  var big = repeat_byte(90, 16384);
  var rec = Vec[UInt8].new();
  rec.push(23 as UInt8);
  rec.push(3 as UInt8);
  rec.push(3 as UInt8);
  rec.push(64 as UInt8);
  rec.push(0 as UInt8);
  var i = 0;
  while i < big.len() {
    rec.push(big[i]);
    i = i + 1;
  }
  let r = tls_parse_record(&rec, 0);
  if !r.is_ok { ok = false; } else {
    let parsed: TlsRecord = r.value;
    if parsed.length != 16384 { ok = false; }
    if parsed.end != 16389 { ok = false; }
    let frag = tls_record_fragment(&rec, &parsed);
    if frag.len() != 16384 { ok = false; }
    let last: UInt8 = frag[16383];
    if ((last as Int) & 0xFF) != 90 { ok = false; }
  }
  var over = Vec[UInt8].new();
  over.push(23 as UInt8);
  over.push(3 as UInt8);
  over.push(3 as UInt8);
  over.push(64 as UInt8);
  over.push(1 as UInt8);
  if !err_rec_is(tls_parse_record(&over, 0), "tls: record overlength at 0") { ok = false; }
  var short = Vec[UInt8].new();
  short.push(22 as UInt8);
  short.push(3 as UInt8);
  short.push(3 as UInt8);
  short.push(0 as UInt8);
  short.push(4 as UInt8);
  if !err_rec_is(tls_parse_record(&short, 0), "tls: truncated record fragment at 0") { ok = false; }
  return assert(ok, "record length boundary: exactly 2^14 accepted, 2^14+1 rejected");
}

fn t4() -> TestResult {
  let buffer = concat_bytes(concat_bytes(hb(ch_min_hex()), hb(sh_hex())), hb(fin_hex()));
  var ok = true;
  let r1 = tls_parse_handshake(&buffer, 0);
  if !r1.is_ok { ok = false; } else {
    let h1: TlsHandshake = r1.value;
    if h1.msg_type != 1 { ok = false; }
    if h1.body_off != 4 { ok = false; }
    if h1.total != 45 { ok = false; }
    if tls_handshake_next(&h1) != 45 { ok = false; }
  }
  let r2 = tls_parse_handshake(&buffer, 45);
  if !r2.is_ok { ok = false; } else {
    let h2: TlsHandshake = r2.value;
    if h2.msg_type != 2 { ok = false; }
    if h2.start != 45 { ok = false; }
    if h2.total != 50 { ok = false; }
    if tls_handshake_next(&h2) != 95 { ok = false; }
  }
  let r3 = tls_parse_handshake(&buffer, 95);
  if !r3.is_ok { ok = false; } else {
    let h3: TlsHandshake = r3.value;
    if h3.msg_type != 20 { ok = false; }
    if h3.total != 36 { ok = false; }
    if tls_handshake_next(&h3) != buffer.len() { ok = false; }
  }
  return assert(ok, "handshake envelope over a three-message buffer with consumed counts");
}

fn t5() -> TestResult {
  var ok = err_hs_is(tls_parse_handshake(&hb(""), 0), "tls: truncated handshake header at 0");
  if !err_hs_is(tls_parse_handshake(&hb("010000"), 0), "tls: truncated handshake header at 0") { ok = false; }
  if !err_hs_is(tls_parse_handshake(&hb("03000000"), 0), "tls: bad handshake type at 0") { ok = false; }
  if !err_hs_is(tls_parse_handshake(&hb("01000005aabb"), 0), "tls: truncated handshake body at 0") { ok = false; }
  if !err_hs_is(tls_parse_handshake(&hb("01000000"), -2), "tls: negative offset") { ok = false; }
  if !str_eq(tls_handshake_type_name(1), "client_hello") { ok = false; }
  if !str_eq(tls_handshake_type_name(2), "server_hello") { ok = false; }
  if !str_eq(tls_handshake_type_name(8), "encrypted_extensions") { ok = false; }
  if !str_eq(tls_handshake_type_name(11), "certificate") { ok = false; }
  if !str_eq(tls_handshake_type_name(20), "finished") { ok = false; }
  if !str_eq(tls_handshake_type_name(3), "") { ok = false; }
  return assert(ok, "handshake envelope errors and type names");
}

fn t6() -> TestResult {
  let data = hb(ch_hex());
  let r = tls_parse_client_hello(&data, 0);
  if !r.is_ok {
    return assert(false, "full ClientHello must parse");
  }
  let ch: TlsClientHello = r.value;
  var ok = ch.legacy_version == 771;
  if ch.total != data.len() { ok = false; }
  let rnd: Vec[UInt8] = ch.random;
  if rnd.len() != 32 { ok = false; }
  let r0: UInt8 = rnd[0];
  let r31: UInt8 = rnd[31];
  if ((r0 as Int) & 0xFF) != 0 { ok = false; }
  if ((r31 as Int) & 0xFF) != 255 { ok = false; }
  let sid: Vec[UInt8] = ch.session_id;
  if !bytes_equal(sid, hb("aabbccdd")) { ok = false; }
  let cs: Vec[Int] = ch.cipher_suites;
  if cs.len() != 2 { ok = false; }
  let c0: Int = cs[0];
  let c1: Int = cs[1];
  if c0 != 4865 { ok = false; }
  if c1 != 4866 { ok = false; }
  let cm: Vec[Int] = ch.compression_methods;
  if cm.len() != 1 { ok = false; }
  let m0: Int = cm[0];
  if m0 != 0 { ok = false; }
  if !ch.ext_present { ok = false; }
  if ch.ext_off != 51 { ok = false; }
  if ch.ext_end != data.len() { ok = false; }
  let xr = tls_parse_extensions(&data, ch.ext_off, ch.ext_end);
  if !xr.is_ok {
    return assert(false, "ClientHello extension block must parse");
  }
  let exts: TlsExtensions = xr.value;
  if tls_ext_count(&exts) != 7 { ok = false; }
  if tls_ext_type_at(&exts, 0) != 0 { ok = false; }
  if tls_ext_type_at(&exts, 1) != 16 { ok = false; }
  if tls_ext_type_at(&exts, 2) != 43 { ok = false; }
  if tls_ext_type_at(&exts, 3) != 10 { ok = false; }
  if tls_ext_type_at(&exts, 4) != 13 { ok = false; }
  if tls_ext_type_at(&exts, 5) != 51 { ok = false; }
  if tls_ext_type_at(&exts, 6) != 65281 { ok = false; }
  if tls_ext_type_at(&exts, 7) != -1 { ok = false; }
  if tls_ext_find(&exts, 0) != 0 { ok = false; }
  if tls_ext_find(&exts, 43) != 2 { ok = false; }
  if tls_ext_find(&exts, 4660) != -1 { ok = false; }
  let host = tls_ext_sni_host_name(&exts, 0);
  if !bytes_equal(host, bytes_of("a.bc")) { ok = false; }
  if tls_ext_alpn_count(&exts, 1) != 2 { ok = false; }
  let a0 = tls_ext_alpn_name(&exts, 1, 0);
  let a1 = tls_ext_alpn_name(&exts, 1, 1);
  if !bytes_equal(a0, bytes_of("h2")) { ok = false; }
  if !bytes_equal(a1, bytes_of("http/1.1")) { ok = false; }
  let vs = tls_ext_supported_versions(&exts, 2);
  if vs.len() != 2 { ok = false; }
  let v0: Int = vs[0];
  let v1: Int = vs[1];
  if v0 != 772 { ok = false; }
  if v1 != 771 { ok = false; }
  if !tls_version_is_tls13(v0) { ok = false; }
  if tls_ext_selected_version(&exts, 2) != -1 { ok = false; }
  let groups = tls_ext_supported_groups(&exts, 3);
  if groups.len() != 2 { ok = false; }
  let g0: Int = groups[0];
  let g1: Int = groups[1];
  if g0 != 29 { ok = false; }
  if g1 != 23 { ok = false; }
  if !str_eq(tls_group_name(g0), "x25519") { ok = false; }
  let sigs = tls_ext_signature_algorithms(&exts, 4);
  if sigs.len() != 2 { ok = false; }
  let s0: Int = sigs[0];
  if s0 != 1027 { ok = false; }
  if !str_eq(tls_signature_scheme_name(s0), "ecdsa_secp256r1_sha256") { ok = false; }
  if tls_ext_key_share_count(&exts, 5) != 1 { ok = false; }
  if tls_ext_key_share_group_at(&exts, 5, 0) != 29 { ok = false; }
  let share = tls_ext_key_share_bytes(&exts, 5, 0);
  if !bytes_equal(share, hb("aabb")) { ok = false; }
  if tls_ext_key_share_selected_group(&exts, 5) != -1 { ok = false; }
  let raw = tls_ext_bytes(&exts, 6);
  if !bytes_equal(raw, hb("deadbeef")) { ok = false; }
  if !str_eq(tls_ext_type_name(65281), "") { ok = false; }
  if !str_eq(tls_ext_type_name(0), "server_name") { ok = false; }
  if !str_eq(tls_ext_type_name(16), "application_layer_protocol_negotiation") { ok = false; }
  return assert(ok, "ClientHello full parse with SNI/ALPN/versions/groups/sigs/key_share/unknown");
}

fn t7() -> TestResult {
  let data = hb(ch_min_hex());
  let r = tls_parse_client_hello(&data, 0);
  if !r.is_ok {
    return assert(false, "minimal ClientHello must parse");
  }
  let ch: TlsClientHello = r.value;
  var ok = ch.legacy_version == 771;
  if ch.total != 45 { ok = false; }
  let sid: Vec[UInt8] = ch.session_id;
  if sid.len() != 0 { ok = false; }
  let cs: Vec[Int] = ch.cipher_suites;
  if cs.len() != 1 { ok = false; }
  let c0: Int = cs[0];
  if c0 != 47 { ok = false; }
  let cm: Vec[Int] = ch.compression_methods;
  if cm.len() != 1 { ok = false; }
  if ch.ext_present { ok = false; }
  if ch.ext_off != data.len() { ok = false; }
  if ch.ext_end != data.len() { ok = false; }
  let rnd: Vec[UInt8] = ch.random;
  if rnd.len() != 32 { ok = false; }
  let r5: UInt8 = rnd[5];
  if ((r5 as Int) & 0xFF) != 17 { ok = false; }
  return assert(ok, "ClientHello minimal (no extensions, empty session id)");
}

fn t8() -> TestResult {
  var ok = err_ch_is(tls_parse_client_hello(&hb(sh_hex()), 0), "tls: not a client hello at 0");
  let sid33 = hb("01000029" + "0303" +
    "1111111111111111111111111111111111111111111111111111111111111111" +
    "21" + "0002" + "002f" + "0100");
  if !err_ch_is(tls_parse_client_hello(&sid33, 0), "tls: bad session id length at 38") { ok = false; }
  let odd = hb("01000029" + "0303" +
    "1111111111111111111111111111111111111111111111111111111111111111" +
    "00" + "0003" + "002f" + "0100");
  if !err_ch_is(tls_parse_client_hello(&odd, 0), "tls: bad cipher suites length at 39") { ok = false; }
  let nosuites = hb("01000029" + "0303" +
    "1111111111111111111111111111111111111111111111111111111111111111" +
    "00" + "0000" + "002f" + "0100");
  if !err_ch_is(tls_parse_client_hello(&nosuites, 0), "tls: bad cipher suites length at 39") { ok = false; }
  let nocomp = hb("01000028" + "0303" +
    "1111111111111111111111111111111111111111111111111111111111111111" +
    "00" + "0002" + "002f" + "00");
  if !err_ch_is(tls_parse_client_hello(&nocomp, 0), "tls: bad compression methods length at 43") { ok = false; }
  let shortrand = hb("01000006" + "0303" + "11111111");
  if !err_ch_is(tls_parse_client_hello(&shortrand, 0), "tls: truncated client hello at 6") { ok = false; }
  let shortext = hb("0100002a" + "0303" +
    "1111111111111111111111111111111111111111111111111111111111111111" +
    "00" + "0002" + "002f" + "0100" + "ff");
  if !err_ch_is(tls_parse_client_hello(&shortext, 0), "tls: truncated extension block at 45") { ok = false; }
  let mism = hb("0100002c" + "0303" +
    "1111111111111111111111111111111111111111111111111111111111111111" +
    "00" + "0002" + "002f" + "0100" + "0002" + "ff");
  if !err_ch_is(tls_parse_client_hello(&mism, 0), "tls: extension block length mismatch at 45") { ok = false; }
  return assert(ok, "ClientHello rejects session/cipher/compression/extension violations with offsets");
}

fn t9() -> TestResult {
  let data = hb(sh_hex());
  let r = tls_parse_server_hello(&data, 0);
  if !r.is_ok {
    return assert(false, "ServerHello must parse");
  }
  let sh: TlsServerHello = r.value;
  var ok = sh.legacy_version == 771;
  if sh.cipher_suite != 4865 { ok = false; }
  if sh.compression_method != 0 { ok = false; }
  let rnd: Vec[UInt8] = sh.random;
  if rnd.len() != 32 { ok = false; }
  let sid: Vec[UInt8] = sh.session_id;
  if sid.len() != 0 { ok = false; }
  if !sh.ext_present { ok = false; }
  if sh.ext_off != 42 { ok = false; }
  if sh.ext_end != data.len() { ok = false; }
  if sh.total != 50 { ok = false; }
  let xr = tls_parse_extensions(&data, sh.ext_off, sh.ext_end);
  if !xr.is_ok {
    return assert(false, "ServerHello extension block must parse");
  }
  let exts: TlsExtensions = xr.value;
  if tls_ext_count(&exts) != 1 { ok = false; }
  if tls_ext_selected_version(&exts, 0) != 772 { ok = false; }
  let vs = tls_ext_supported_versions(&exts, 0);
  if vs.len() != 0 { ok = false; }
  if !err_sh_is(tls_parse_server_hello(&hb(ch_min_hex()), 0), "tls: not a server hello at 0") { ok = false; }
  let mismatch = hb("0200002e" + "0303" +
    "2222222222222222222222222222222222222222222222222222222222222222" +
    "00" + "1301" + "00" + "0004" + "002b0002" + "0304");
  if !err_sh_is(tls_parse_server_hello(&mismatch, 0), "tls: extension block length mismatch at 42") { ok = false; }
  return assert(ok, "ServerHello parse and selected_version extension");
}

fn t10() -> TestResult {
  let data = hb("08000008" + "0006" + "ff020002" + "0102");
  let r = tls_parse_encrypted_extensions(&data, 0);
  if !r.is_ok {
    return assert(false, "EncryptedExtensions must parse");
  }
  let ee: TlsEncryptedExtensions = r.value;
  var ok = ee.body_off == 4;
  if ee.list_len != 6 { ok = false; }
  if ee.total != 12 { ok = false; }
  let xr = tls_parse_extensions(&data, ee.body_off, ee.body_off + ee.list_len + 2);
  if !xr.is_ok {
    return assert(false, "EncryptedExtensions block must parse");
  }
  let exts: TlsExtensions = xr.value;
  if tls_ext_count(&exts) != 1 { ok = false; }
  if tls_ext_type_at(&exts, 0) != 65282 { ok = false; }
  let raw = tls_ext_bytes(&exts, 0);
  if !bytes_equal(raw, hb("0102")) { ok = false; }
  if !err_ee_is(tls_parse_encrypted_extensions(&hb(ch_min_hex()), 0), "tls: not encrypted extensions at 0") { ok = false; }
  let mism = hb("08000008" + "0004" + "ff020002" + "0102");
  if !err_ee_is(tls_parse_encrypted_extensions(&mism, 0), "tls: extension block length mismatch at 4") { ok = false; }
  let short = hb("08000001" + "ff");
  if !err_ee_is(tls_parse_encrypted_extensions(&short, 0), "tls: truncated extension block at 4") { ok = false; }
  return assert(ok, "EncryptedExtensions parse, unknown extension preserved, error catalog");
}

fn t11() -> TestResult {
  let data = hb("0b000012" + "00000f" + "000005" + "3003020101" + "000004" + "30020500");
  let r = tls_parse_certificate(&data, 0);
  if !r.is_ok {
    return assert(false, "Certificate must parse");
  }
  let c: TlsCertificate = r.value;
  var ok = c.body_off == 4;
  if c.list_len != 15 { ok = false; }
  if c.total != 22 { ok = false; }
  if c.cert_starts.len() != 2 { ok = false; }
  if c.cert_lens.len() != 2 { ok = false; }
  let s0: Int = c.cert_starts[0];
  let s1: Int = c.cert_starts[1];
  let l0: Int = c.cert_lens[0];
  let l1: Int = c.cert_lens[1];
  if s0 != 10 { ok = false; }
  if l0 != 5 { ok = false; }
  if s1 != 18 { ok = false; }
  if l1 != 4 { ok = false; }
  let d0 = tls_certificate_der(&data, &c, 0);
  let d1 = tls_certificate_der(&data, &c, 1);
  if !bytes_equal(d0, hb("3003020101")) { ok = false; }
  if !bytes_equal(d1, hb("30020500")) { ok = false; }
  let empty = tls_certificate_der(&data, &c, 2);
  if empty.len() != 0 { ok = false; }
  let mismatch = hb("0b000012" + "00000e" + "000005" + "3003020101" + "000004" + "30020500");
  if !err_cert_is(tls_parse_certificate(&mismatch, 0), "tls: certificate list length mismatch at 4") { ok = false; }
  let shortentry = hb("0b000007" + "000004" + "000005" + "30");
  if !err_cert_is(tls_parse_certificate(&shortentry, 0), "tls: truncated certificate entry at 7") { ok = false; }
  let empty_list = hb("0b000003" + "000000");
  let er = tls_parse_certificate(&empty_list, 0);
  if !er.is_ok { ok = false; } else {
    let ec: TlsCertificate = er.value;
    if ec.list_len != 0 { ok = false; }
    if ec.cert_starts.len() != 0 { ok = false; }
  }
  if !err_cert_is(tls_parse_certificate(&hb(ch_min_hex()), 0), "tls: not a certificate at 0") { ok = false; }
  return assert(ok, "Certificate DER slice offsets/lengths and error catalog");
}

fn t12() -> TestResult {
  let ske = hb("0c000008" + "03" + "001d" + "04aabbccdd");
  let r1 = tls_parse_server_key_exchange(&ske, 0);
  var ok = r1.is_ok;
  if !ok {
    return assert(false, "ServerKeyExchange must parse");
  }
  let kx1: TlsKeyExchange = r1.value;
  if kx1.msg_type != 12 { ok = false; }
  if kx1.curve_type != 3 { ok = false; }
  if kx1.named_curve != 29 { ok = false; }
  if !str_eq(tls_group_name(kx1.named_curve), "x25519") { ok = false; }
  if kx1.body_off != 4 { ok = false; }
  if kx1.body_len != 8 { ok = false; }
  if kx1.total != 12 { ok = false; }
  let cke = hb("10000005" + "04aabbccdd");
  let r2 = tls_parse_client_key_exchange(&cke, 0);
  if !r2.is_ok { ok = false; } else {
    let kx2: TlsKeyExchange = r2.value;
    if kx2.msg_type != 16 { ok = false; }
    if kx2.curve_type != -1 { ok = false; }
    if kx2.named_curve != -1 { ok = false; }
    if kx2.body_len != 5 { ok = false; }
  }
  if !err_kx_is(tls_parse_server_key_exchange(&hb("0c000002" + "0300"), 0), "tls: truncated key exchange body at 4") { ok = false; }
  if !err_kx_is(tls_parse_client_key_exchange(&hb("10000000"), 0), "tls: empty key exchange body at 4") { ok = false; }
  if !err_kx_is(tls_parse_client_key_exchange(&ske, 0), "tls: not a client key exchange at 0") { ok = false; }
  if !err_kx_is(tls_parse_server_key_exchange(&cke, 0), "tls: not a server key exchange at 0") { ok = false; }
  return assert(ok, "ServerKeyExchange named-curve hint and opaque ClientKeyExchange");
}

fn t13() -> TestResult {
  let fin = hb(fin_hex());
  let r1 = tls_parse_finished(&fin, 0);
  var ok = r1.is_ok;
  if !ok {
    return assert(false, "Finished must parse");
  }
  let f: TlsFinished = r1.value;
  if f.body_off != 4 { ok = false; }
  if f.body_len != 32 { ok = false; }
  if f.total != 36 { ok = false; }
  if !err_fin_is(tls_parse_finished(&hb("14000000"), 0), "tls: empty finished body at 4") { ok = false; }
  if !err_fin_is(tls_parse_finished(&hb(ch_min_hex()), 0), "tls: not a finished message at 0") { ok = false; }
  let nst = hb("04000016" + "00001c20" + "00000000" + "02" + "aabb" + "0003" + "ccddee" + "0004" + "ff030000");
  let r2 = tls_parse_new_session_ticket(&nst, 0);
  if !r2.is_ok {
    return assert(false, "NewSessionTicket must parse");
  }
  let t: TlsNewSessionTicket = r2.value;
  if t.lifetime != 7200 { ok = false; }
  if t.age_add != 0 { ok = false; }
  if t.nonce_off != 13 { ok = false; }
  if t.nonce_len != 2 { ok = false; }
  if t.ticket_off != 17 { ok = false; }
  if t.ticket_len != 3 { ok = false; }
  if t.ext_off != 20 { ok = false; }
  if t.ext_end != 26 { ok = false; }
  if t.total != 26 { ok = false; }
  let xr = tls_parse_extensions(&nst, t.ext_off, t.ext_end);
  if !xr.is_ok {
    return assert(false, "NewSessionTicket extension block must parse");
  }
  let exts: TlsExtensions = xr.value;
  if tls_ext_count(&exts) != 1 { ok = false; }
  if tls_ext_type_at(&exts, 0) != 65283 { ok = false; }
  if tls_ext_len(&exts, 0) != 0 { ok = false; }
  let badticket = hb("0400000d" + "00001c20" + "00000000" + "00" + "0000" + "0000");
  if !err_nst_is(tls_parse_new_session_ticket(&badticket, 0), "tls: bad ticket length at 13") { ok = false; }
  let badext = hb("04000016" + "00001c20" + "00000000" + "02" + "aabb" + "0003" + "ccddee" + "0005" + "ff030000");
  if !err_nst_is(tls_parse_new_session_ticket(&badext, 0), "tls: extension block length mismatch at 20") { ok = false; }
  let truncated = hb("0400000b" + "00001c20" + "00000000" + "00" + "0000");
  if !err_nst_is(tls_parse_new_session_ticket(&truncated, 0), "tls: truncated new session ticket at 4") { ok = false; }
  return assert(ok, "Finished and NewSessionTicket pinned bytes and error catalog");
}

fn t14() -> TestResult {
  let fatal_record = hb("15030300020228");
  let fr = tls_parse_record(&fatal_record, 0);
  var ok = fr.is_ok;
  if !ok {
    return assert(false, "fatal alert record must parse");
  }
  let rec: TlsRecord = fr.value;
  let a1r = tls_parse_alert(&fatal_record, rec.fragment_off);
  if !a1r.is_ok {
    return assert(false, "fatal alert must parse");
  }
  let a1: TlsAlert = a1r.value;
  if a1.level != 2 { ok = false; }
  if a1.description != 40 { ok = false; }
  if !str_eq(tls_alert_level_name(a1.level), "fatal") { ok = false; }
  if !str_eq(tls_alert_description_name(a1.description), "handshake_failure") { ok = false; }
  let warn = hb("15030300020100");
  let a2r = tls_parse_alert(&warn, 5);
  if !a2r.is_ok { ok = false; } else {
    let a2: TlsAlert = a2r.value;
    if a2.level != 1 { ok = false; }
    if a2.description != 0 { ok = false; }
    if !str_eq(tls_alert_level_name(1), "warning") { ok = false; }
    if !str_eq(tls_alert_description_name(0), "close_notify") { ok = false; }
  }
  let unknown = hb("150303000202c8");
  let a3r = tls_parse_alert(&unknown, 5);
  if !a3r.is_ok { ok = false; } else {
    let a3: TlsAlert = a3r.value;
    if a3.description != 200 { ok = false; }
    if !str_eq(tls_alert_description_name(200), "") { ok = false; }
  }
  if !str_eq(tls_alert_description_name(20), "bad_record_mac") { ok = false; }
  if !str_eq(tls_alert_description_name(50), "decode_error") { ok = false; }
  if !str_eq(tls_alert_description_name(70), "protocol_version") { ok = false; }
  if !str_eq(tls_alert_description_name(120), "no_application_protocol") { ok = false; }
  if !str_eq(tls_alert_level_name(3), "") { ok = false; }
  if !err_alert_is(tls_parse_alert(&hb("1503030001ff"), 5), "tls: truncated alert at 5") { ok = false; }
  if !err_alert_is(tls_parse_alert(&hb("15030300020328"), 5), "tls: bad alert level at 5") { ok = false; }
  if !err_alert_is(tls_parse_alert(&hb("0000"), -1), "tls: negative offset") { ok = false; }
  return assert(ok, "alert decode: levels, description names, unknown code, offsets");
}

fn t15() -> TestResult {
  let data = hb("140303000101");
  var ok = true;
  let rr = tls_parse_record(&data, 0);
  if !rr.is_ok { ok = false; } else {
    let rec: TlsRecord = rr.value;
    if rec.content_type != 20 { ok = false; }
    if rec.length != 1 { ok = false; }
    if !tls_parse_change_cipher_spec(&data, rec.fragment_off).is_ok { ok = false; }
  }
  if !err_unit_is(tls_parse_change_cipher_spec(&hb("140303000102"), 5), "tls: bad change cipher spec byte at 5") { ok = false; }
  if !err_unit_is(tls_parse_change_cipher_spec(&hb("ff"), 1), "tls: truncated change cipher spec at 1") { ok = false; }
  if !err_unit_is(tls_parse_change_cipher_spec(&hb("ff"), -1), "tls: negative offset") { ok = false; }
  return assert(ok, "ChangeCipherSpec single 0x01 byte and error catalog");
}

fn t16() -> TestResult {
  let ch = hb(ch_hex());
  let part1 = slice_bytes(ch, 0, 40);
  let part2 = slice_bytes(ch, 40, ch.len() - 40);
  var buf = tls_handshake_buffer_new();
  var ok = true;
  let r1 = rec_bytes(22, part1);
  let f1 = tls_hsbuf_feed_record(&mut buf, &r1, 0);
  if !f1.is_ok { ok = false; } else {
    let p1 = f1.value;
    let next1: Int = p1.0;
    let n1: Int = p1.1;
    if next1 != r1.len() { ok = false; }
    if n1 != 0 { ok = false; }
  }
  if tls_hsbuf_count(&buf) != 0 { ok = false; }
  if tls_hsbuf_pending_len(&buf) != 40 { ok = false; }
  let r2 = rec_bytes(22, part2);
  let f2 = tls_hsbuf_feed_record(&mut buf, &r2, 0);
  if !f2.is_ok { ok = false; } else {
    let p2 = f2.value;
    let n2: Int = p2.1;
    if n2 != 1 { ok = false; }
  }
  if tls_hsbuf_count(&buf) != 1 { ok = false; }
  if tls_hsbuf_pending_len(&buf) != 0 { ok = false; }
  if tls_hsbuf_message_len(&buf, 0) != ch.len() { ok = false; }
  if tls_hsbuf_message_type(&buf, 0) != 1 { ok = false; }
  let joined = tls_hsbuf_message(&buf, 0);
  if !bytes_equal(joined, ch) { ok = false; }
  if tls_hsbuf_message_len(&buf, 1) != -1 { ok = false; }
  let msgs = concat_bytes(hb(sh_hex()), hb(fin_hex()));
  let r3 = rec_bytes(22, msgs);
  let f3 = tls_hsbuf_feed_record(&mut buf, &r3, 0);
  if !f3.is_ok { ok = false; } else {
    let p3 = f3.value;
    let n3: Int = p3.1;
    if n3 != 2 { ok = false; }
  }
  if tls_hsbuf_count(&buf) != 3 { ok = false; }
  if tls_hsbuf_message_type(&buf, 1) != 2 { ok = false; }
  if tls_hsbuf_message_type(&buf, 2) != 20 { ok = false; }
  if tls_hsbuf_message_len(&buf, 1) != 50 { ok = false; }
  if tls_hsbuf_message_len(&buf, 2) != 36 { ok = false; }
  if !err_int_is(tls_hsbuf_feed(&mut buf, 21, &hb("0100")), "tls: not a handshake fragment") { ok = false; }
  if !err_pair_is(tls_hsbuf_feed_record(&mut buf, &hb("15030300020100"), 0), "tls: not a handshake record at 0") { ok = false; }
  if !err_pair_is(tls_hsbuf_feed_record(&mut buf, &hb("ffff"), 3), "tls: truncated record header at 3") { ok = false; }
  let partial = rec_bytes(22, hb("010000"));
  let f4 = tls_hsbuf_feed_record(&mut buf, &partial, 0);
  if !f4.is_ok { ok = false; } else {
    let p4 = f4.value;
    let n4: Int = p4.1;
    if n4 != 0 { ok = false; }
  }
  if tls_hsbuf_pending_len(&buf) != 3 { ok = false; }
  tls_hsbuf_reset(&mut buf);
  if tls_hsbuf_count(&buf) != 0 { ok = false; }
  if tls_hsbuf_pending_len(&buf) != 0 { ok = false; }
  return assert(ok, "handshake reassembly across records, multi-message records, reset");
}

fn t17() -> TestResult {
  var ok = err_exts_is(tls_parse_extensions(&hb("000c" + "00000000" + "00290000" + "ff010000"), 0, 14), "tls: pre_shared_key not last at 6");
  let psk_last = hb("0004" + "00290000");
  let lr = tls_parse_extensions(&psk_last, 0, 6);
  if !lr.is_ok { ok = false; } else {
    let le: TlsExtensions = lr.value;
    if tls_ext_count(&le) != 1 { ok = false; }
    if tls_ext_type_at(&le, 0) != 41 { ok = false; }
    if !str_eq(tls_ext_type_name(41), "pre_shared_key") { ok = false; }
  }
  if !err_exts_is(tls_parse_extensions(&hb("0008" + "00000000" + "00000000"), 0, 10), "tls: duplicate extension at 6") { ok = false; }
  if !err_exts_is(tls_parse_extensions(&hb("0003" + "000000"), 0, 5), "tls: truncated extension header at 2") { ok = false; }
  if !err_exts_is(tls_parse_extensions(&hb("0005" + "0000" + "0005" + "ff"), 0, 7), "tls: truncated extension body at 2") { ok = false; }
  if !err_exts_is(tls_parse_extensions(&hb("0002" + "0000" + "0000"), 0, 6), "tls: extension block length mismatch at 0") { ok = false; }
  if !err_exts_is(tls_parse_extensions(&hb("0000"), 0, 3), "tls: extension block out of bounds at 0") { ok = false; }
  if !err_exts_is(tls_parse_extensions(&hb("0000"), 4, 2), "tls: extension block out of bounds at 4") { ok = false; }
  if !err_exts_is(tls_parse_extensions(&hb("0000"), -1, 2), "tls: negative offset") { ok = false; }
  let snibad = hb("0009" + "00000005" + "0005000461");
  let r1 = tls_parse_extensions(&snibad, 0, snibad.len());
  if !r1.is_ok { ok = false; } else {
    let e1: TlsExtensions = r1.value;
    let host = tls_ext_sni_host_name(&e1, 0);
    if host.len() != 0 { ok = false; }
    if tls_ext_count(&e1) != 1 { ok = false; }
  }
  let alpnbad = hb("0009" + "00100005" + "0004056162");
  let r2 = tls_parse_extensions(&alpnbad, 0, alpnbad.len());
  if !r2.is_ok { ok = false; } else {
    let e2: TlsExtensions = r2.value;
    if tls_ext_alpn_count(&e2, 0) != 0 { ok = false; }
    let nm = tls_ext_alpn_name(&e2, 0, 0);
    if nm.len() != 0 { ok = false; }
  }
  let svbad = hb("0009" + "002b0005" + "0303040303");
  let r3 = tls_parse_extensions(&svbad, 0, svbad.len());
  if !r3.is_ok { ok = false; } else {
    let e3: TlsExtensions = r3.value;
    if tls_ext_supported_versions(&e3, 0).len() != 0 { ok = false; }
    if tls_ext_selected_version(&e3, 0) != -1 { ok = false; }
  }
  let ksbad = hb("000b" + "00330007" + "0004001d0004aa");
  let r4 = tls_parse_extensions(&ksbad, 0, ksbad.len());
  if !r4.is_ok { ok = false; } else {
    let e4: TlsExtensions = r4.value;
    if tls_ext_key_share_count(&e4, 0) != 0 { ok = false; }
    if tls_ext_key_share_group_at(&e4, 0, 0) != -1 { ok = false; }
    if tls_ext_key_share_bytes(&e4, 0, 0).len() != 0 { ok = false; }
    if tls_ext_key_share_selected_group(&e4, 0) != -1 { ok = false; }
  }
  return assert(ok, "extension block: psk-last rule, duplicates, truncation, malformed bodies");
}

fn t18() -> TestResult {
  let buffer = concat_bytes(concat_bytes(hb(ch_min_hex()), hb(fin_hex())), hb("010000"));
  var ok = true;
  var consumed = 0;
  let r1 = tls_parse_handshake(&buffer, 0);
  if !r1.is_ok { ok = false; } else {
    let h1: TlsHandshake = r1.value;
    if h1.total != 45 { ok = false; }
    consumed = tls_handshake_next(&h1);
  }
  let r2 = tls_parse_handshake(&buffer, consumed);
  if !r2.is_ok { ok = false; } else {
    let h2: TlsHandshake = r2.value;
    if h2.total != 36 { ok = false; }
    consumed = tls_handshake_next(&h2);
  }
  if consumed != 81 { ok = false; }
  if !err_hs_is(tls_parse_handshake(&buffer, consumed), "tls: truncated handshake header at 81") { ok = false; }
  if consumed >= buffer.len() { ok = false; }
  return assert(ok, "one-message-at-a-time parsing with consumed counts and trailing partial");
}

fn t19() -> TestResult {
  let buffer = concat_bytes(concat_bytes(rec_bytes(22, hb("01000000")), rec_bytes(20, hb("01"))), rec_bytes(21, hb("0128")));
  var ok = true;
  let r1 = tls_parse_record(&buffer, 0);
  if !r1.is_ok { ok = false; } else {
    let rec1: TlsRecord = r1.value;
    if rec1.content_type != 22 { ok = false; }
    if rec1.end != 9 { ok = false; }
  }
  let r2 = tls_parse_record(&buffer, 9);
  if !r2.is_ok { ok = false; } else {
    let rec2: TlsRecord = r2.value;
    if rec2.content_type != 20 { ok = false; }
    if rec2.fragment_off != 14 { ok = false; }
    if rec2.end != 15 { ok = false; }
    if !tls_parse_change_cipher_spec(&buffer, rec2.fragment_off).is_ok { ok = false; }
  }
  let r3 = tls_parse_record(&buffer, 15);
  if !r3.is_ok { ok = false; } else {
    let rec3: TlsRecord = r3.value;
    if rec3.content_type != 21 { ok = false; }
    if rec3.fragment_off != 20 { ok = false; }
    if rec3.end != 22 { ok = false; }
    let ar = tls_parse_alert(&buffer, rec3.fragment_off);
    if !ar.is_ok { ok = false; } else {
      let a: TlsAlert = ar.value;
      if a.level != 1 { ok = false; }
      if a.description != 40 { ok = false; }
    }
  }
  if buffer.len() != 22 { ok = false; }
  return assert(ok, "multi-record buffer: chained offsets, CCS and alert fragments");
}

fn t20() -> TestResult {
  var ok = err_rec_is(tls_parse_record(&hb("1603030010aa"), 4), "tls: truncated record header at 4");
  if !err_hs_is(tls_parse_handshake(&hb("ffff03000000"), 2), "tls: bad handshake type at 2") { ok = false; }
  if !str_eq(tls_ext_type_name(10), "supported_groups") { ok = false; }
  if !str_eq(tls_ext_type_name(13), "signature_algorithms") { ok = false; }
  if !str_eq(tls_ext_type_name(43), "supported_versions") { ok = false; }
  if !str_eq(tls_ext_type_name(51), "key_share") { ok = false; }
  if !str_eq(tls_ext_type_name(4660), "") { ok = false; }
  if !str_eq(tls_handshake_type_name(4), "new_session_ticket") { ok = false; }
  if !str_eq(tls_handshake_type_name(24), "key_update") { ok = false; }
  if !str_eq(tls_handshake_type_name(254), "message_hash") { ok = false; }
  if !str_eq(tls_alert_description_name(116), "certificate_required") { ok = false; }
  if !str_eq(tls_alert_description_name(86), "inappropriate_fallback") { ok = false; }
  if !str_eq(tls_group_name(23), "secp256r1") { ok = false; }
  if !str_eq(tls_group_name(256), "ffdhe2048") { ok = false; }
  if !str_eq(tls_group_name(99), "") { ok = false; }
  if !str_eq(tls_signature_scheme_name(2055), "ed25519") { ok = false; }
  if !str_eq(tls_signature_scheme_name(2054), "rsa_pss_rsae_sha512") { ok = false; }
  if !str_eq(tls_signature_scheme_name(99), "") { ok = false; }
  return assert(ok, "name catalogs and errors pinned to exact byte offsets");
}

fn main() -> Int {
  io.println("=== xiom.tls conformance tests ===");
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
    io.println("xiom.tls: all tests passed");
  } else {
    io.println("xiom.tls: tests failed");
  }
  return failed;
}
