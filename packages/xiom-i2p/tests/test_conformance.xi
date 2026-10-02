// XIOM -- xiom.i2p conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: size constants, base64/base32 KATs (RFC 4648
// vectors) and strict error cases, canonical 516-character destination
// parse/encode and key split, certificate and signature-type tables, b32
// and .i2p host validation, SAM line parse/build with quoting and bounds,
// reply-code tables and reply parsing, version packing, session create/
// status/add/remove, stream connect/accept/forward state transitions and
// inbound peers, command line builders parsing back through sam_parse_line,
// the address book (naming store) and the lease-set shape.
//
// All deterministic: no clock, no I/O beyond stdout, no crypto, no sockets.
// Str values are compared with xiom.string.compare.str_compare (BUG-17
// discipline), Vec[Str] elements are bound to typed locals, and byte
// values are widened before comparison.

module i2p_tests
use xiom.io; use xiom.test;
use xiom.i2p;
use xiom.string;
use xiom.string.compare;
use xiom.string.builder;

// --------------------------------------------------
//  Small helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
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

fn rep(s: Str, n: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    builder.sb_push_str(&mut out, s);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

// 384 pattern key bytes + a null certificate (3 zero bytes).
fn dest_bytes() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 384 {
    v.push(((i * 5 + 1) % 256) as UInt8);
    i = i + 1;
  }
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  return v;
}

fn dest_bytes_alt() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 384 {
    v.push(((i * 11 + 7) % 256) as UInt8);
    i = i + 1;
  }
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  return v;
}

// k-th distinct canonical destination string (k = 1..).
fn dest_k(k: Int) -> Str {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 384 {
    v.push(((i * 3 + k * 7) % 256) as UInt8);
    i = i + 1;
  }
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  return b64_encode(&v);
}

fn good_dest() -> Str {
  let b = dest_bytes();
  return b64_encode(&b);
}

fn alt_dest() -> Str {
  let b = dest_bytes_alt();
  return b64_encode(&b);
}

fn peer_hash() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 32 {
    v.push(((i * 3 + 2) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

fn peer_b64() -> Str {
  let h = peer_hash();
  return b64_encode(&h);
}

// k-th distinct ".i2p" hostname ("h<k>.i2p").
fn host_k(k: Int) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "h");
  builder.sb_push_int(&mut out, k);
  builder.sb_push_str(&mut out, ".i2p");
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Error and unwrap helpers
// --------------------------------------------------

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_dest_is(r: Result[I2pDestination, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_msg_is(r: Result[I2pMessage, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_session_is(r: Result[I2pSession, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_stream_is(r: Result[I2pStream, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_book_is(r: Result[I2pAddressBook, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_leaseset_is(r: Result[I2pLeaseSet, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn str_ok(r: Result[Str, Str]) -> Str {
  if r.is_ok { return r.value; }
  return "!unexpected-err!";
}

fn int_ok(r: Result[Int, Str]) -> Int {
  if r.is_ok { return r.value; }
  return -999999;
}

fn hash_ok(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  if r.is_ok { return r.value; }
  return Vec[UInt8].new();
}

fn dest_ok(r: Result[I2pDestination, Str]) -> I2pDestination {
  if r.is_ok { return r.value; }
  return I2pDestination{ data: Vec[UInt8].new() };
}

fn msg_ok(r: Result[I2pMessage, Str]) -> I2pMessage {
  if r.is_ok { return r.value; }
  return I2pMessage{ verb: "!"; sub: "!"; keys: Vec[Str].new(); values: Vec[Str].new() };
}

fn session_ok(r: Result[I2pSession, Str]) -> I2pSession {
  if r.is_ok { return r.value; }
  return I2pSession{
    session_id: "!";
    style: -1;
    state: -1;
    dests: Vec[Str].new();
    option_keys: Vec[Str].new();
    option_values: Vec[Str].new();
  };
}

fn stream_ok(r: Result[I2pStream, Str]) -> I2pStream {
  if r.is_ok { return r.value; }
  return I2pStream{
    stream_id: "!";
    session_id: "!";
    style: -1;
    state: -1;
    direction: -1;
    dest_b64: "";
    peer: "";
    port: -1;
    silent: false;
  };
}

fn book_ok(r: Result[I2pAddressBook, Str]) -> I2pAddressBook {
  if r.is_ok { return r.value; }
  return I2pAddressBook{ names: Vec[Str].new(); dests: Vec[Str].new() };
}

fn leaseset_ok(r: Result[I2pLeaseSet, Str]) -> I2pLeaseSet {
  if r.is_ok { return r.value; }
  return I2pLeaseSet{
    dest_b64: "!";
    peers: Vec[Str].new();
    tunnel_ids: Vec[Int].new();
    end_dates: Vec[Int].new();
  };
}

// Fresh ACTIVE STREAM session.
fn make_stream_session() -> I2pSession {
  let okv = Vec[Str].new();
  let ovv = Vec[Str].new();
  let s = session_ok(session_create("sess1", I2P_STYLE_STREAM, good_dest(), &okv, &ovv));
  return session_status(&s, I2P_RESULT_OK);
}

// Fresh ACTIVE DATAGRAM session.
fn make_datagram_session() -> I2pSession {
  let okv = Vec[Str].new();
  let ovv = Vec[Str].new();
  let s = session_ok(session_create("dgram1", I2P_STYLE_DATAGRAM, good_dest(), &okv, &ovv));
  return session_status(&s, I2P_RESULT_OK);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  if i2p_dest_len() != 387 { ok = false; }
  if i2p_dest_b64_len() != 516 { ok = false; }
  if i2p_b32_label_len() != 52 { ok = false; }
  if i2p_max_sam_line() != 4096 { ok = false; }
  if I2P_ENC_PUBKEY_LEN + I2P_SIGN_PUBKEY_LEN != I2P_KEY_MATERIAL_LEN { ok = false; }
  if I2P_KEY_MATERIAL_LEN + I2P_CERT_HEADER_LEN != I2P_DEST_LEN { ok = false; }
  if I2P_B32_LABEL_LEN + 8 != I2P_B32_HOST_LEN { ok = false; }
  if I2P_PEER_B64_LEN != 44 { ok = false; }
  if I2P_LEASESET_MAX_LEASES != 16 { ok = false; }
  if I2P_MAX_PORT != 65535 { ok = false; }
  if I2P_RESULT_MAX != 13 { ok = false; }
  if !str_eq(i2p_b32_suffix(), ".b32.i2p") { ok = false; }
  if !str_eq(i2p_suffix(), ".i2p") { ok = false; }
  return assert(ok, "size constants and address suffixes");
}

fn t2() -> TestResult {
  var ok = true;
  let e = Vec[UInt8].new();
  if !str_eq(b64_encode(&e), "") { ok = false; }
  let f = bytes_of("f");
  if !str_eq(b64_encode(&f), "Zg==") { ok = false; }
  let fo = bytes_of("fo");
  if !str_eq(b64_encode(&fo), "Zm8=") { ok = false; }
  let foo = bytes_of("foo");
  if !str_eq(b64_encode(&foo), "Zm9v") { ok = false; }
  let foob = bytes_of("foob");
  if !str_eq(b64_encode(&foob), "Zm9vYg==") { ok = false; }
  let fooba = bytes_of("fooba");
  if !str_eq(b64_encode(&fooba), "Zm9vYmE=") { ok = false; }
  let foobar = bytes_of("foobar");
  if !str_eq(b64_encode(&foobar), "Zm9vYmFy") { ok = false; }
  let r1 = b64_decode("Zg==");
  if !r1.is_ok { ok = false; } else {
    let b1: Vec[UInt8] = r1.value;
    if !bytes_equal(b1, f) { ok = false; }
  }
  let r2 = b64_decode("Zm9vYmFy");
  if !r2.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = r2.value;
    if !bytes_equal(b2, foobar) { ok = false; }
  }
  let r3 = b64_decode("");
  if !r3.is_ok { ok = false; } else {
    let b3: Vec[UInt8] = r3.value;
    if b3.len() != 0 { ok = false; }
  }
  return assert(ok, "base64 RFC 4648 vectors and round-trips");
}

fn t3() -> TestResult {
  var ok = true;
  if !err_bytes_is(b64_decode("Zg="), "i2p: base64 length not a multiple of 4") { ok = false; }
  if !err_bytes_is(b64_decode("Zm9="), "i2p: base64 non-canonical padding bits at offset 2") { ok = false; }
  if !err_bytes_is(b64_decode("Zg==Zg=="), "i2p: base64 invalid character at offset 2") { ok = false; }
  if !err_bytes_is(b64_decode("Zm9!"), "i2p: base64 invalid character at offset 3") { ok = false; }
  if !err_bytes_is(b64_decode("=AAA"), "i2p: base64 invalid character at offset 0") { ok = false; }
  if !err_bytes_is(b64_decode("Zg==="), "i2p: base64 length not a multiple of 4") { ok = false; }
  return assert(ok, "base64 strict errors (length, padding, alphabet)");
}

fn t4() -> TestResult {
  var ok = true;
  let f = bytes_of("f");
  if !str_eq(b32_encode(&f), "my") { ok = false; }
  let fo = bytes_of("fo");
  if !str_eq(b32_encode(&fo), "mzxq") { ok = false; }
  let foo = bytes_of("foo");
  if !str_eq(b32_encode(&foo), "mzxw6") { ok = false; }
  let foob = bytes_of("foob");
  if !str_eq(b32_encode(&foob), "mzxw6yq") { ok = false; }
  let fooba = bytes_of("fooba");
  if !str_eq(b32_encode(&fooba), "mzxw6ytb") { ok = false; }
  let foobar = bytes_of("foobar");
  if !str_eq(b32_encode(&foobar), "mzxw6ytboi") { ok = false; }
  let r1 = b32_decode("mzxw6ytboi");
  if !r1.is_ok { ok = false; } else {
    let b1: Vec[UInt8] = r1.value;
    if !bytes_equal(b1, foobar) { ok = false; }
  }
  let z = zeros(32);
  if !str_eq(b32_encode(&z), rep("a", 52)) { ok = false; }
  let host = str_ok(addr_b32_host(&z));
  if !str_eq(host, rep("a", 52) + ".b32.i2p") { ok = false; }
  if !addr_is_b32_host(host) { ok = false; }
  if !addr_is_i2p_host(host) { ok = false; }
  let back = hash_ok(addr_b32_hash(host));
  if back.len() != 32 { ok = false; }
  if !bytes_equal(back, z) { ok = false; }
  return assert(ok, "base32 RFC 4648 vectors and 32-byte b32 host");
}

fn t5() -> TestResult {
  var ok = true;
  if !err_bytes_is(b32_decode("m"), "i2p: base32 length invalid") { ok = false; }
  if !err_bytes_is(b32_decode("mz"), "i2p: base32 non-canonical padding bits") { ok = false; }
  if !err_bytes_is(b32_decode("mzxW"), "i2p: base32 invalid character at offset 3") { ok = false; }
  if !err_bytes_is(b32_decode("mY"), "i2p: base32 invalid character at offset 1") { ok = false; }
  if !err_bytes_is(b32_decode("mzxw6ytb!!"), "i2p: base32 invalid character at offset 8") { ok = false; }
  let short = zeros(31);
  if !err_str_is(addr_b32_host(&short), "i2p: b32 address requires a 32-byte hash") { ok = false; }
  if !err_bytes_is(addr_b32_hash("abc.b32.i2p"), "i2p: b32 address must be 52 base32 characters plus .b32.i2p") { ok = false; }
  let noncanon = rep("a", 51) + "b" + ".b32.i2p";
  if !err_bytes_is(addr_b32_hash(noncanon), "i2p: base32 non-canonical padding bits") { ok = false; }
  return assert(ok, "base32 and b32 strict errors");
}

fn t6() -> TestResult {
  var ok = true;
  let d = dest_bytes();
  let s = b64_encode(&d);
  if s.len() != 516 { ok = false; }
  let cA1 = (string.byte_at(s, 512) as Int) & 0xFF;
  let cA2 = (string.byte_at(s, 515) as Int) & 0xFF;
  if cA1 != 65 { ok = false; }
  if cA2 != 65 { ok = false; }
  let r = dest_parse_b64(s);
  if !r.is_ok { ok = false; } else {
    let dest: I2pDestination = r.value;
    if !dest_is_null_cert(&dest) { ok = false; }
    if !str_eq(dest_to_b64(&dest), s) { ok = false; }
    if int_ok(dest_cert_type(&dest)) != 0 { ok = false; }
    if int_ok(dest_cert_len(&dest)) != 0 { ok = false; }
    if int_ok(dest_sig_type(&dest)) != I2P_SIG_DSA_SHA1 { ok = false; }
    let enc = dest_enc_key(&dest);
    if enc.len() != 256 { ok = false; }
    if (enc[0] as Int) != 1 { ok = false; }
    let sig = dest_sign_key(&dest);
    if sig.len() != 128 { ok = false; }
    if (sig[127] as Int) != 124 { ok = false; }
  }
  if !str_eq(dest_sig_type_name(I2P_SIG_EDDSA_SHA512_ED25519), "EdDSA_SHA512_Ed25519") { ok = false; }
  if !str_eq(dest_sig_type_name(I2P_SIG_REDDSA_SHA512_ED25519), "RedDSA_SHA512_Ed25519") { ok = false; }
  if !str_eq(dest_sig_type_name(99), "UNKNOWN") { ok = false; }
  return assert(ok, "destination parse, key split and certificate fields");
}

fn t7() -> TestResult {
  var ok = true;
  let s = good_dest();
  let short = string.str_slice(s, 0, 515);
  if !err_dest_is(dest_parse_b64(short), "i2p: destination length must be 516") { ok = false; }
  let badChar = "!" + string.str_slice(s, 1, 516);
  if !err_dest_is(dest_parse_b64(badChar), "i2p: base64 invalid character at offset 0") { ok = false; }
  var bad = Vec[UInt8].new();
  var i = 0;
  while i < 384 {
    bad.push(((i * 5 + 1) % 256) as UInt8);
    i = i + 1;
  }
  bad.push(1 as UInt8);
  bad.push(0 as UInt8);
  bad.push(0 as UInt8);
  if !err_dest_is(dest_parse_b64(b64_encode(&bad)), "i2p: destination certificate invalid") { ok = false; }
  let malformed = I2pDestination{ data: zeros(10) };
  if !err_int_is(dest_cert_type(&malformed), "i2p: destination length must be 387") { ok = false; }
  if dest_is_null_cert(&malformed) { ok = false; }
  if !err_int_is(dest_sig_type(&malformed), "i2p: destination has no key certificate") { ok = false; }
  if dest_enc_key(&malformed).len() != 10 { ok = false; }
  if dest_sign_key(&malformed).len() != 0 { ok = false; }
  return assert(ok, "destination strict and malformed-input errors");
}

fn t8() -> TestResult {
  var ok = true;
  if addr_kind(good_dest()) != I2P_ADDR_B64_DEST { ok = false; }
  let z = zeros(32);
  let host = str_ok(addr_b32_host(&z));
  if addr_kind(host) != I2P_ADDR_B32_HOST { ok = false; }
  if addr_kind("example.i2p") != I2P_ADDR_I2P_HOST { ok = false; }
  if addr_kind("example.com") != I2P_ADDR_INVALID { ok = false; }
  if addr_kind("") != I2P_ADDR_INVALID { ok = false; }
  if addr_is_b64(host) { ok = false; }
  if addr_is_b32_host("example.i2p") { ok = false; }
  let h2 = hash_ok(addr_b32_hash(host));
  if !bytes_equal(h2, z) { ok = false; }
  return assert(ok, "address classification across all three kinds");
}

fn t9() -> TestResult {
  var ok = true;
  if !addr_is_i2p_host("a.i2p") { ok = false; }
  if !addr_is_i2p_host("foo.bar.i2p") { ok = false; }
  if !addr_is_i2p_host("my-host.i2p") { ok = false; }
  if !addr_is_i2p_host("123.i2p") { ok = false; }
  if !addr_is_i2p_host(rep("a", 63) + ".i2p") { ok = false; }
  if addr_is_i2p_host("Alice.i2p") { ok = false; }
  if addr_is_i2p_host("_svc.i2p") { ok = false; }
  if addr_is_i2p_host("-bad.i2p") { ok = false; }
  if addr_is_i2p_host("bad-.i2p") { ok = false; }
  if addr_is_i2p_host("foo..i2p") { ok = false; }
  if addr_is_i2p_host(".foo.i2p") { ok = false; }
  if addr_is_i2p_host("foo.i2p.") { ok = false; }
  if addr_is_i2p_host("foo.extra") { ok = false; }
  if addr_is_i2p_host(rep("a", 64) + ".i2p") { ok = false; }
  let longHost = rep("a", 63) + "." + rep("b", 63) + "." + rep("c", 63) + "." + rep("d", 63) + ".i2p";
  if longHost.len() <= 255 { ok = false; }
  if addr_is_i2p_host(longHost) { ok = false; }
  return assert(ok, ".i2p hostname label and length rules");
}

fn t10() -> TestResult {
  var ok = true;
  let m = msg_ok(sam_parse_line("HELLO VERSION MIN=3.0 MAX=3.3\n"));
  if !str_eq(m.verb, "HELLO") { ok = false; }
  if !str_eq(m.sub, "VERSION") { ok = false; }
  if sam_msg_count(&m) != 2 { ok = false; }
  if !sam_msg_has(&m, "MIN") { ok = false; }
  if !str_eq(str_ok(sam_msg_field(&m, "MIN")), "3.0") { ok = false; }
  if !str_eq(str_ok(sam_msg_field(&m, "MAX")), "3.3") { ok = false; }
  if sam_msg_has(&m, "NOPE") { ok = false; }
  if !err_str_is(sam_msg_field(&m, "NOPE"), "i2p: field not present") { ok = false; }
  let m2 = msg_ok(sam_parse_line("SESSION   CREATE  ID=x\n"));
  if !str_eq(str_ok(sam_msg_field(&m2, "ID")), "x") { ok = false; }
  let m3 = msg_ok(sam_parse_line("DEST REPLY RESULT=OK\r\n"));
  if !str_eq(m3.sub, "REPLY") { ok = false; }
  if !sam_is_reply(&m3) { ok = false; }
  if sam_is_reply(&m) { ok = false; }
  let m4 = msg_ok(sam_parse_line("NAMING LOOKUP NAME=\n"));
  if !str_eq(str_ok(sam_msg_field(&m4, "NAME")), "") { ok = false; }
  return assert(ok, "SAM line parse: fields, spacing, CRLF, empty value");
}

fn t11() -> TestResult {
  var ok = true;
  if !err_msg_is(sam_parse_line(""), "i2p: empty sam line") { ok = false; }
  if !err_msg_is(sam_parse_line("HELLO VERSION MIN=3.0"), "i2p: sam line not newline-terminated") { ok = false; }
  if !err_msg_is(sam_parse_line("HELLO\n"), "i2p: sam line needs a command and a subcommand") { ok = false; }
  if !err_msg_is(sam_parse_line("HELLO VERSION MIN3.0\n"), "i2p: sam field missing '='") { ok = false; }
  if !err_msg_is(sam_parse_line("FOO=BAR VERSION\n"), "i2p: sam command token must not be a field") { ok = false; }
  if !err_msg_is(sam_parse_line("HELLO VERSION \u{0009}MIN=3.0\n"), "i2p: sam line invalid byte at offset 14") { ok = false; }
  if !err_msg_is(sam_parse_line(rep("A", 4096) + "\n"), "i2p: sam line too long") { ok = false; }
  if !err_msg_is(sam_parse_line("HELLO VERSION MIN=\"3.0\n"), "i2p: sam line unterminated quote at offset 21") { ok = false; }
  return assert(ok, "SAM line parse errors: bounds, fields, controls, quotes");
}

fn t12() -> TestResult {
  var ok = true;
  var k1 = Vec[Str].new();
  var v1 = Vec[Str].new();
  k1.push("MIN");
  v1.push("3.0");
  k1.push("MAX");
  v1.push("3.3");
  let line = str_ok(sam_build_line("HELLO", "VERSION", &k1, &v1));
  if !str_eq(line, "HELLO VERSION MIN=3.0 MAX=3.3\n") { ok = false; }
  let m = msg_ok(sam_parse_line(line));
  if !str_eq(str_ok(sam_msg_field(&m, "MAX")), "3.3") { ok = false; }
  var k2 = Vec[Str].new();
  var v2 = Vec[Str].new();
  k2.push("NAME");
  v2.push("my host");
  let line2 = str_ok(sam_build_line("NAMING", "LOOKUP", &k2, &v2));
  let q = (string.byte_at(line2, 19) as Int) & 0xFF;
  if q != 34 { ok = false; }
  let m2 = msg_ok(sam_parse_line(line2));
  if !str_eq(str_ok(sam_msg_field(&m2, "NAME")), "my host") { ok = false; }
  var vb = Vec[UInt8].new();
  vb.push(97 as UInt8);
  vb.push(34 as UInt8);
  vb.push(98 as UInt8);
  vb.push(92 as UInt8);
  vb.push(99 as UInt8);
  let special = builder.sb_to_str(&vb);
  var k3 = Vec[Str].new();
  var v3 = Vec[Str].new();
  k3.push("X");
  v3.push(special);
  let line3 = str_ok(sam_build_line("HELLO", "REPLY", &k3, &v3));
  let m3 = msg_ok(sam_parse_line(line3));
  if !str_eq(str_ok(sam_msg_field(&m3, "X")), special) { ok = false; }
  let none = Vec[Str].new();
  if !err_str_is(sam_build_line("HELLO", "VERSION", &k1, &none), "i2p: sam field keys/values length mismatch") { ok = false; }
  var kbad = Vec[Str].new();
  var vbad = Vec[Str].new();
  kbad.push("BAD KEY");
  vbad.push("v");
  if !err_str_is(sam_build_line("HELLO", "VERSION", &kbad, &vbad), "i2p: sam field key invalid") { ok = false; }
  if !err_str_is(sam_build_line("HEL LO", "VERSION", &k1, &v1), "i2p: sam command token invalid") { ok = false; }
  var ctl = Vec[UInt8].new();
  ctl.push(1 as UInt8);
  let ctlStr = builder.sb_to_str(&ctl);
  var kc = Vec[Str].new();
  var vc = Vec[Str].new();
  kc.push("X");
  vc.push(ctlStr);
  if !err_str_is(sam_build_line("HELLO", "REPLY", &kc, &vc), "i2p: sam field value has invalid byte") { ok = false; }
  return assert(ok, "SAM line build: quoting, escapes and validation");
}

fn t13() -> TestResult {
  var ok = true;
  if !str_eq(sam_result_name(I2P_RESULT_OK), "OK") { ok = false; }
  if !str_eq(sam_result_name(I2P_RESULT_TIMEOUT), "TIMEOUT") { ok = false; }
  if !str_eq(sam_result_name(I2P_RESULT_I2P_ERROR), "I2P_ERROR") { ok = false; }
  if !str_eq(sam_result_name(999), "UNKNOWN") { ok = false; }
  if sam_result_code("ALREADY_ACCEPTING") != I2P_RESULT_ALREADY_ACCEPTING { ok = false; }
  if sam_result_code("NOPE") != I2P_RESULT_UNKNOWN { ok = false; }
  if !sam_result_is_ok(I2P_RESULT_OK) { ok = false; }
  if sam_result_is_ok(I2P_RESULT_TIMEOUT) { ok = false; }
  let gd = good_dest();
  let m1 = msg_ok(sam_parse_line("SESSION STATUS RESULT=OK DESTINATION=" + gd + "\n"));
  if int_ok(sam_reply_code(&m1)) != I2P_RESULT_OK { ok = false; }
  if !str_eq(str_ok(sam_msg_field(&m1, "DESTINATION")), gd) { ok = false; }
  let m2 = msg_ok(sam_parse_line("HELLO REPLY RESULT=NOVERSION\n"));
  if int_ok(sam_reply_code(&m2)) != I2P_RESULT_NOVERSION { ok = false; }
  let m3 = msg_ok(sam_parse_line("STREAM STATUS RESULT=CANT_REACH_PEER MESSAGE=\"peer unreachable\"\n"));
  if int_ok(sam_reply_code(&m3)) != I2P_RESULT_CANT_REACH_PEER { ok = false; }
  if !str_eq(sam_reply_message(&m3), "peer unreachable") { ok = false; }
  if !str_eq(sam_reply_message(&m1), "") { ok = false; }
  let m4 = msg_ok(sam_parse_line("STREAM STATUS RESULT=BOGUS\n"));
  if !err_int_is(sam_reply_code(&m4), "i2p: unknown result code") { ok = false; }
  let m5 = msg_ok(sam_parse_line("STREAM STATUS ID=1\n"));
  if !err_int_is(sam_reply_code(&m5), "i2p: field not present") { ok = false; }
  return assert(ok, "reply result tables and reply parsing");
}

fn t14() -> TestResult {
  var ok = true;
  if sam_version_pack(3, 3) != 303 { ok = false; }
  if int_ok(sam_version_parse("3.3")) != 303 { ok = false; }
  if int_ok(sam_version_parse("10.20")) != 1020 { ok = false; }
  if !err_int_is(sam_version_parse("3"), "i2p: version text invalid") { ok = false; }
  if !err_int_is(sam_version_parse("3."), "i2p: version text invalid") { ok = false; }
  if !err_int_is(sam_version_parse(".3"), "i2p: version text invalid") { ok = false; }
  if !err_int_is(sam_version_parse("3.3.3"), "i2p: version text invalid") { ok = false; }
  if !err_int_is(sam_version_parse("a.b"), "i2p: version text invalid") { ok = false; }
  if !err_int_is(sam_version_parse("300.1"), "i2p: version text invalid") { ok = false; }
  if !err_int_is(sam_version_parse(""), "i2p: version text invalid") { ok = false; }
  let h = str_ok(sam_hello_line(300, 303));
  if !str_eq(h, "HELLO VERSION MIN=3.0 MAX=3.3\n") { ok = false; }
  let m = msg_ok(sam_parse_line(h));
  if !str_eq(str_ok(sam_msg_field(&m, "MIN")), "3.0") { ok = false; }
  if !err_str_is(sam_hello_line(400, 300), "i2p: version range invalid") { ok = false; }
  if !err_str_is(sam_hello_line(-1, 300), "i2p: version range invalid") { ok = false; }
  return assert(ok, "version packing/parsing and HELLO builder");
}

fn t15() -> TestResult {
  var ok = true;
  if !str_eq(session_style_name(I2P_STYLE_STREAM), "STREAM") { ok = false; }
  if !str_eq(session_style_name(I2P_STYLE_DATAGRAM), "DATAGRAM") { ok = false; }
  if !str_eq(session_style_name(I2P_STYLE_RAW), "RAW") { ok = false; }
  if !str_eq(session_style_name(42), "UNKNOWN") { ok = false; }
  if session_style_code("DATAGRAM") != I2P_STYLE_DATAGRAM { ok = false; }
  if session_style_code("NOPE") != -1 { ok = false; }
  if !str_eq(session_state_name(I2P_SESSION_NEW), "NEW") { ok = false; }
  if !str_eq(session_state_name(I2P_SESSION_ACTIVE), "ACTIVE") { ok = false; }
  var okv = Vec[Str].new();
  var ovv = Vec[Str].new();
  okv.push("inbound.length");
  ovv.push("3");
  let s = session_ok(session_create("sess1", I2P_STYLE_STREAM, good_dest(), &okv, &ovv));
  if !str_eq(s.session_id, "sess1") { ok = false; }
  if s.style != I2P_STYLE_STREAM { ok = false; }
  if s.state != I2P_SESSION_NEW { ok = false; }
  if session_is_active(&s) { ok = false; }
  if session_dest_count(&s) != 1 { ok = false; }
  if !str_eq(session_dest_at(&s, 0), good_dest()) { ok = false; }
  if session_dest_at(&s, 1).len() != 0 { ok = false; }
  if session_option_count(&s) != 1 { ok = false; }
  if !str_eq(session_option_key_at(&s, 0), "inbound.length") { ok = false; }
  if !str_eq(session_option_value_at(&s, 0), "3") { ok = false; }
  if !err_session_is(session_create("", I2P_STYLE_STREAM, good_dest(), &okv, &ovv), "i2p: session id invalid") { ok = false; }
  if !err_session_is(session_create("bad id", I2P_STYLE_STREAM, good_dest(), &okv, &ovv), "i2p: session id invalid") { ok = false; }
  if !err_session_is(session_create(rep("x", 65), I2P_STYLE_STREAM, good_dest(), &okv, &ovv), "i2p: session id invalid") { ok = false; }
  if !err_session_is(session_create("sess1", 7, good_dest(), &okv, &ovv), "i2p: unknown session style") { ok = false; }
  if !err_session_is(session_create("sess1", I2P_STYLE_STREAM, "x", &okv, &ovv), "i2p: session destination invalid") { ok = false; }
  let empty = Vec[Str].new();
  if !err_session_is(session_create("sess1", I2P_STYLE_STREAM, good_dest(), &okv, &empty), "i2p: session options invalid") { ok = false; }
  var kbad = Vec[Str].new();
  var vbad = Vec[Str].new();
  kbad.push("BAD KEY");
  vbad.push("3");
  if !err_session_is(session_create("sess1", I2P_STYLE_STREAM, good_dest(), &kbad, &vbad), "i2p: session options invalid") { ok = false; }
  var kbig = Vec[Str].new();
  var vbig = Vec[Str].new();
  var i = 0;
  while i < 33 {
    kbig.push("k");
    vbig.push("v");
    i = i + 1;
  }
  if !err_session_is(session_create("sess1", I2P_STYLE_STREAM, good_dest(), &kbig, &vbig), "i2p: session options invalid") { ok = false; }
  if !stream_id_ok("ok") { ok = false; }
  if stream_id_ok("") { ok = false; }
  if stream_id_ok("a=b") { ok = false; }
  if stream_id_ok(rep("x", 65)) { ok = false; }
  return assert(ok, "session create: styles, ids, destinations, options");
}

fn t16() -> TestResult {
  var ok = true;
  let okv = Vec[Str].new();
  let ovv = Vec[Str].new();
  let s0 = session_ok(session_create("sess1", I2P_STYLE_STREAM, good_dest(), &okv, &ovv));
  let s = session_status(&s0, I2P_RESULT_OK);
  if !session_is_active(&s) { ok = false; }
  if s0.state != I2P_SESSION_NEW { ok = false; }
  let sf = session_status(&s0, I2P_RESULT_TIMEOUT);
  if sf.state != I2P_SESSION_FAILED { ok = false; }
  if !str_eq(session_state_name(sf.state), "FAILED") { ok = false; }
  let alt = alt_dest();
  let s2 = session_ok(session_add_dest(&s, alt));
  if session_dest_count(&s2) != 2 { ok = false; }
  if !str_eq(session_dest_at(&s2, 1), alt) { ok = false; }
  if !err_session_is(session_add_dest(&s2, alt), "i2p: destination already in session") { ok = false; }
  let s3 = session_ok(session_remove_dest(&s2, alt));
  if session_dest_count(&s3) != 1 { ok = false; }
  if !err_session_is(session_remove_dest(&s2, good_dest()), "i2p: cannot remove primary destination") { ok = false; }
  if !err_session_is(session_remove_dest(&s2, dest_k(99)), "i2p: destination not in session") { ok = false; }
  var cur = s;
  var i = 1;
  while i <= 8 {
    cur = session_ok(session_add_dest(&cur, dest_k(i)));
    i = i + 1;
  }
  if session_dest_count(&cur) != 9 { ok = false; }
  if !err_session_is(session_add_dest(&cur, dest_k(9)), "i2p: too many session destinations") { ok = false; }
  let closed = session_close(&s);
  if closed.state != I2P_SESSION_CLOSED { ok = false; }
  if !str_eq(session_state_name(closed.state), "CLOSED") { ok = false; }
  if !err_session_is(session_add_dest(&closed, alt), "i2p: session closed") { ok = false; }
  if !err_session_is(session_remove_dest(&closed, alt), "i2p: session closed") { ok = false; }
  return assert(ok, "session status, add/remove destinations, close");
}

fn t17() -> TestResult {
  var ok = true;
  let s = make_stream_session();
  let target = alt_dest();
  let st = stream_ok(stream_connect(&s, "str1", target));
  if !str_eq(st.stream_id, "str1") { ok = false; }
  if !str_eq(st.session_id, "sess1") { ok = false; }
  if st.state != I2P_STREAM_CONNECTING { ok = false; }
  if st.direction != I2P_DIR_CONNECT { ok = false; }
  if !str_eq(st.dest_b64, target) { ok = false; }
  if stream_can_send(&st) { ok = false; }
  if !str_eq(stream_state_name(st.state), "CONNECTING") { ok = false; }
  let open = stream_status(&st, I2P_RESULT_OK);
  if open.state != I2P_STREAM_OPEN { ok = false; }
  if !stream_can_send(&open) { ok = false; }
  let failed = stream_status(&st, I2P_RESULT_TIMEOUT);
  if failed.state != I2P_STREAM_FAILED { ok = false; }
  let again = stream_status(&failed, I2P_RESULT_OK);
  if again.state != I2P_STREAM_FAILED { ok = false; }
  let closed = stream_close(&open);
  if closed.state != I2P_STREAM_CLOSED { ok = false; }
  let after = stream_status(&closed, I2P_RESULT_OK);
  if after.state != I2P_STREAM_CLOSED { ok = false; }
  if !err_stream_is(stream_connect(&s, "", target), "i2p: stream id invalid") { ok = false; }
  if !err_stream_is(stream_connect(&s, "str1", "zz"), "i2p: stream target invalid") { ok = false; }
  let dg = make_datagram_session();
  if !err_stream_is(stream_connect(&dg, "str1", target), "i2p: streams require a STREAM session") { ok = false; }
  let okv = Vec[Str].new();
  let ovv = Vec[Str].new();
  let s0 = session_ok(session_create("sess1", I2P_STYLE_STREAM, good_dest(), &okv, &ovv));
  if !err_stream_is(stream_connect(&s0, "str1", target), "i2p: session not active") { ok = false; }
  let scl = session_close(&s);
  if !err_stream_is(stream_connect(&scl, "str1", target), "i2p: session not active") { ok = false; }
  if !str_eq(stream_state_name(42), "UNKNOWN") { ok = false; }
  return assert(ok, "stream connect states and session gates");
}

fn t18() -> TestResult {
  var ok = true;
  let s = make_stream_session();
  let a = stream_ok(stream_accept(&s, "acc1"));
  if a.state != I2P_STREAM_ACCEPTING { ok = false; }
  if a.direction != I2P_DIR_ACCEPT { ok = false; }
  if a.dest_b64.len() != 0 { ok = false; }
  let a2 = stream_status(&a, I2P_RESULT_OK);
  if a2.state != I2P_STREAM_ACCEPTING { ok = false; }
  let af = stream_status(&a2, I2P_RESULT_TIMEOUT);
  if af.state != I2P_STREAM_FAILED { ok = false; }
  let pb = peer_b64();
  if !err_stream_is(stream_inbound(&af, pb), "i2p: stream not accepting") { ok = false; }
  let inbound = stream_ok(stream_inbound(&a2, pb));
  if inbound.state != I2P_STREAM_OPEN { ok = false; }
  if !str_eq(inbound.peer, pb) { ok = false; }
  if !stream_can_send(&inbound) { ok = false; }
  if !err_stream_is(stream_inbound(&a2, "AAAA"), "i2p: invalid peer hash") { ok = false; }
  if !err_stream_is(stream_inbound(&a2, ""), "i2p: invalid peer hash") { ok = false; }
  let c = stream_ok(stream_connect(&s, "str1", alt_dest()));
  if !err_stream_is(stream_inbound(&c, pb), "i2p: stream not accepting") { ok = false; }
  let done = stream_close(&a2);
  if done.state != I2P_STREAM_CLOSED { ok = false; }
  return assert(ok, "stream accept, inbound peer and close");
}

fn t19() -> TestResult {
  var ok = true;
  let s = make_stream_session();
  if !err_stream_is(stream_forward(&s, "f1", 0), "i2p: forward port out of range") { ok = false; }
  if !err_stream_is(stream_forward(&s, "f1", 65536), "i2p: forward port out of range") { ok = false; }
  if !err_stream_is(stream_forward(&s, "", 8080), "i2p: stream id invalid") { ok = false; }
  let f = stream_ok(stream_forward(&s, "f1", 8080));
  if f.state != I2P_STREAM_FORWARDING { ok = false; }
  if f.port != 8080 { ok = false; }
  if f.direction != I2P_DIR_FORWARD { ok = false; }
  let f2 = stream_status(&f, I2P_RESULT_OK);
  if f2.state != I2P_STREAM_FORWARDING { ok = false; }
  let fmin = stream_ok(stream_forward(&s, "f2", 1));
  if fmin.port != 1 { ok = false; }
  let fmax = stream_ok(stream_forward(&s, "f3", 65535));
  if fmax.port != 65535 { ok = false; }
  let fs = stream_set_silent(&f, true);
  if !fs.silent { ok = false; }
  let fm = msg_ok(sam_parse_line(str_ok(sam_stream_forward_line(&fs))));
  if !str_eq(str_ok(sam_msg_field(&fm, "ID")), "f1") { ok = false; }
  if !str_eq(str_ok(sam_msg_field(&fm, "PORT")), "8080") { ok = false; }
  if !str_eq(str_ok(sam_msg_field(&fm, "SILENT")), "true") { ok = false; }
  let fm2 = msg_ok(sam_parse_line(str_ok(sam_stream_forward_line(&f))));
  if sam_msg_has(&fm2, "SILENT") { ok = false; }
  return assert(ok, "stream forward bounds, states and SILENT flag");
}

fn t20() -> TestResult {
  var ok = true;
  var okv = Vec[Str].new();
  var ovv = Vec[Str].new();
  okv.push("inbound.length");
  ovv.push("3");
  let s = session_status(&session_ok(session_create("sess1", I2P_STYLE_STREAM, good_dest(), &okv, &ovv)), I2P_RESULT_OK);
  let lm = msg_ok(sam_parse_line(str_ok(sam_session_create_line(&s))));
  if !str_eq(lm.verb, "SESSION") { ok = false; }
  if !str_eq(lm.sub, "CREATE") { ok = false; }
  if !str_eq(str_ok(sam_msg_field(&lm, "STYLE")), "STREAM") { ok = false; }
  if !str_eq(str_ok(sam_msg_field(&lm, "ID")), "sess1") { ok = false; }
  if !str_eq(str_ok(sam_msg_field(&lm, "DESTINATION")), good_dest()) { ok = false; }
  if !str_eq(str_ok(sam_msg_field(&lm, "inbound.length")), "3") { ok = false; }
  let alt = alt_dest();
  let st = stream_ok(stream_connect(&s, "str1", alt));
  let cm = msg_ok(sam_parse_line(str_ok(sam_stream_connect_line(&st))));
  if !str_eq(str_ok(sam_msg_field(&cm, "ID")), "str1") { ok = false; }
  if !str_eq(str_ok(sam_msg_field(&cm, "DESTINATION")), alt) { ok = false; }
  let ac = stream_ok(stream_accept(&s, "acc1"));
  let am = msg_ok(sam_parse_line(str_ok(sam_stream_accept_line(&ac))));
  if !str_eq(str_ok(sam_msg_field(&am, "ID")), "acc1") { ok = false; }
  if sam_msg_has(&am, "DESTINATION") { ok = false; }
  let addm = msg_ok(sam_parse_line(str_ok(sam_session_add_line(&s, alt))));
  if !str_eq(addm.sub, "ADD") { ok = false; }
  if !str_eq(str_ok(sam_msg_field(&addm, "DESTINATION")), alt) { ok = false; }
  let remm = msg_ok(sam_parse_line(str_ok(sam_session_remove_line(&s, alt))));
  if !str_eq(remm.sub, "REMOVE") { ok = false; }
  if !str_eq(sam_dest_generate_line(), "DEST GENERATE\n") { ok = false; }
  let nm = msg_ok(sam_parse_line(str_ok(sam_naming_lookup_line("alice.i2p"))));
  if !str_eq(str_ok(sam_msg_field(&nm, "NAME")), "alice.i2p") { ok = false; }
  if !err_str_is(sam_naming_lookup_line("not a host"), "i2p: naming lookup target invalid") { ok = false; }
  return assert(ok, "command line builders parse back through the framer");
}

fn t21() -> TestResult {
  var ok = true;
  let b0 = book_new();
  if book_count(&b0) != 0 { ok = false; }
  let gd = good_dest();
  let alt = alt_dest();
  let b1 = book_ok(book_set(&b0, "alice.i2p", gd));
  if book_count(&b1) != 1 { ok = false; }
  if !book_contains(&b1, "alice.i2p") { ok = false; }
  if !str_eq(str_ok(book_get(&b1, "alice.i2p")), gd) { ok = false; }
  if !str_eq(book_name_at(&b1, 0), "alice.i2p") { ok = false; }
  if !str_eq(book_dest_at(&b1, 0), gd) { ok = false; }
  let b2 = book_ok(book_set(&b1, "bob.i2p", alt));
  if book_count(&b2) != 2 { ok = false; }
  if !str_eq(str_ok(book_get(&b2, "bob.i2p")), alt) { ok = false; }
  let b3 = book_ok(book_set(&b2, "alice.i2p", alt));
  if book_count(&b3) != 2 { ok = false; }
  if !str_eq(str_ok(book_get(&b3, "alice.i2p")), alt) { ok = false; }
  if !str_eq(book_name_at(&b3, 0), "alice.i2p") { ok = false; }
  if !str_eq(book_dest_at(&b3, 0), alt) { ok = false; }
  let b4 = book_ok(book_remove(&b3, "alice.i2p"));
  if book_count(&b4) != 1 { ok = false; }
  if book_contains(&b4, "alice.i2p") { ok = false; }
  if !str_eq(book_name_at(&b4, 0), "bob.i2p") { ok = false; }
  if !err_str_is(book_get(&b4, "alice.i2p"), "i2p: name not in address book") { ok = false; }
  if !err_book_is(book_remove(&b4, "alice.i2p"), "i2p: name not in address book") { ok = false; }
  if book_name_at(&b4, 5).len() != 0 { ok = false; }
  if book_dest_at(&b4, 5).len() != 0 { ok = false; }
  if book_name_at(&b4, -1).len() != 0 { ok = false; }
  return assert(ok, "address book set/get/replace/remove and guards");
}

fn t22() -> TestResult {
  var ok = true;
  let b0 = book_new();
  if !err_book_is(book_set(&b0, "Alice.i2p", good_dest()), "i2p: invalid address book name") { ok = false; }
  if !err_book_is(book_set(&b0, "alice", good_dest()), "i2p: invalid address book name") { ok = false; }
  if !err_book_is(book_set(&b0, "alice.i2p", "AAAA"), "i2p: invalid address book destination") { ok = false; }
  if !err_str_is(book_get(&b0, "alice.i2p"), "i2p: name not in address book") { ok = false; }
  var cur = b0;
  var i = 1;
  while i <= 256 {
    cur = book_ok(book_set(&cur, host_k(i), dest_k(i + 1)));
    i = i + 1;
  }
  if book_count(&cur) != 256 { ok = false; }
  if !err_book_is(book_set(&cur, host_k(257), dest_k(258)), "i2p: address book full") { ok = false; }
  return assert(ok, "address book validation and capacity bound");
}

fn t23() -> TestResult {
  var ok = true;
  let gd = good_dest();
  let ls0 = leaseset_ok(leaseset_new(gd));
  if leaseset_count(&ls0) != 0 { ok = false; }
  if !str_eq(ls0.dest_b64, gd) { ok = false; }
  if !leaseset_all_expired(&ls0, 0) { ok = false; }
  let pb = peer_b64();
  let ls1 = leaseset_ok(leaseset_add(&ls0, pb, 1, 1000));
  if leaseset_count(&ls1) != 1 { ok = false; }
  if !str_eq(leaseset_peer_at(&ls1, 0), pb) { ok = false; }
  if leaseset_tunnel_at(&ls1, 0) != 1 { ok = false; }
  if leaseset_enddate_at(&ls1, 0) != 1000 { ok = false; }
  if leaseset_all_expired(&ls1, 999) { ok = false; }
  if !leaseset_all_expired(&ls1, 1000) { ok = false; }
  let ls2 = leaseset_ok(leaseset_add(&ls1, pb, I2P_MAX_U32, 2000));
  if leaseset_count(&ls2) != 2 { ok = false; }
  if leaseset_tunnel_at(&ls2, 1) != I2P_MAX_U32 { ok = false; }
  if leaseset_enddate_at(&ls2, 1) != 2000 { ok = false; }
  if leaseset_peer_at(&ls2, 5).len() != 0 { ok = false; }
  if leaseset_tunnel_at(&ls2, 5) != -1 { ok = false; }
  if leaseset_enddate_at(&ls2, 5) != -1 { ok = false; }
  var driftedPeers = Vec[Str].new();
  driftedPeers.push(pb);
  let drifted = I2pLeaseSet{ dest_b64: gd; peers: driftedPeers; tunnel_ids: Vec[Int].new(); end_dates: Vec[Int].new() };
  if leaseset_count(&drifted) != 0 { ok = false; }
  if !str_eq(leaseset_peer_at(&drifted, 0), pb) { ok = false; }
  if leaseset_tunnel_at(&drifted, 0) != -1 { ok = false; }
  return assert(ok, "lease set add/accessors and parallel-array guard");
}

fn t24() -> TestResult {
  var ok = true;
  if !err_leaseset_is(leaseset_new("x"), "i2p: lease set destination invalid") { ok = false; }
  let ls0 = leaseset_ok(leaseset_new(good_dest()));
  let pb = peer_b64();
  if !err_leaseset_is(leaseset_add(&ls0, "AAAA", 1, 1000), "i2p: invalid lease peer hash") { ok = false; }
  if !err_leaseset_is(leaseset_add(&ls0, "", 1, 1000), "i2p: invalid lease peer hash") { ok = false; }
  let short = zeros(31);
  if !err_leaseset_is(leaseset_add(&ls0, b64_encode(&short), 1, 1000), "i2p: invalid lease peer hash") { ok = false; }
  if !err_leaseset_is(leaseset_add(&ls0, pb, -1, 1000), "i2p: invalid lease tunnel id") { ok = false; }
  if !err_leaseset_is(leaseset_add(&ls0, pb, 4294967296, 1000), "i2p: invalid lease tunnel id") { ok = false; }
  if !err_leaseset_is(leaseset_add(&ls0, pb, 1, 0), "i2p: invalid lease end date") { ok = false; }
  var cur = ls0;
  var i = 0;
  while i < 16 {
    cur = leaseset_ok(leaseset_add(&cur, pb, i + 1, 5000));
    i = i + 1;
  }
  if leaseset_count(&cur) != 16 { ok = false; }
  if !err_leaseset_is(leaseset_add(&cur, pb, 17, 5000), "i2p: lease set full") { ok = false; }
  return assert(ok, "lease set bounds and validation errors");
}

fn main() -> Int {
  io.println("=== xiom.i2p conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.i2p: all tests passed");
  } else {
    io.println("xiom.i2p: tests failed");
  }
  return failed;
}
