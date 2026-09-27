// XIOM -- xiom.ssh2 conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Synthetic packets are built in-test with the library's own writers
// (ssh2_write_*) plus ssh2_encode_* and a small local msg() helper, then
// re-parsed: packet framing and alignment, the field primitives
// (byte/boolean/uint32/string/mpint/name-list) and their truncation catalog,
// DISCONNECT/IGNORE/UNIMPLEMENTED/DEBUG, a full KEXINIT (10 name-lists),
// KEXDH/ECDH inits and replies including the classic negative-mpint check,
// NEWKEYS and SERVICE_*, USERAUTH_REQUEST password/publickey matrices,
// USERAUTH_FAILURE/SUCCESS/BANNER, GLOBAL_REQUEST/RESPONSE, the CHANNEL_OPEN
// type matrix (session/direct-tcpip/forwarded-tcpip/unknown), open
// confirmation/failure, WINDOW_ADJUST, the CHANNEL_REQUEST matrix
// (pty-req/env/exec/shell/subsystem/window-change/unknown), channel
// success/failure/eof/close, CHANNEL_DATA/EXTENDED_DATA, one-message-at-a-time
// parsing with consumed counts, unknown message types preserved raw, and the
// byte-offset error convention at a non-zero packet offset.
//
// Str values are compared with xiom.string.compare.str_compare (BUG 17
// discipline); every Vec read is bound to a typed local; no Ok/Err is
// constructed in the tests (error Results are inspected via is_ok/error).

module ssh2_tests
use xiom.io; use xiom.test;
use xiom.ssh2;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  helpers
// --------------------------------------------------

fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    return r.value;
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

// One 8-aligned packet whose payload is msg_type + body.
fn msg(mt: Int, body: Vec[UInt8]) -> Vec[UInt8] {
  var payload = Vec[UInt8].new();
  payload.push(mt as UInt8);
  var i = 0;
  while i < body.len() {
    payload.push(body[i]);
    i = i + 1;
  }
  return ssh2_write_packet_aligned(&payload, 8);
}

fn err_pkt_is(r: Result[Ssh2Packet, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_msg_is(r: Result[Ssh2Message, Str], want: Str) -> Bool {
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

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_dis_is(r: Result[Ssh2Disconnect, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_kexinit_is(r: Result[Ssh2KexInit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_dhinit_is(r: Result[Ssh2KexDhInit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_kexreply_is(r: Result[Ssh2KexReply, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_service_is(r: Result[Ssh2Service, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_uareq_is(r: Result[Ssh2UserAuthRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_uafail_is(r: Result[Ssh2UserAuthFailure, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_chopen_is(r: Result[Ssh2ChannelOpen, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_chreq_is(r: Result[Ssh2ChannelRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  t1: binary packet round trip and frame fields
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  var payload = Vec[UInt8].new();
  payload.push(20 as UInt8);
  payload.push(1 as UInt8);
  payload.push(2 as UInt8);
  let pad = ssh2_packet_padding_for(payload.len(), 8);
  let pkt = ssh2_write_packet(&payload, pad);
  let r = ssh2_parse_packet(&pkt, 0);
  if !r.is_ok {
    ok = false;
  } else {
    let p: Ssh2Packet = r.value;
    if p.start != 0 { ok = false; }
    if p.packet_length != 1 + payload.len() + pad { ok = false; }
    if p.padding_length != pad { ok = false; }
    if p.payload_len != payload.len() { ok = false; }
    if p.payload_off != 5 { ok = false; }
    if p.padding_off != 5 + payload.len() { ok = false; }
    if p.total != 4 + p.packet_length { ok = false; }
    if p.end != pkt.len() { ok = false; }
    if p.mac_off != pkt.len() { ok = false; }
    let copy = ssh2_packet_payload(&pkt, &p);
    if !bytes_equal(copy, payload) { ok = false; }
    if !ssh2_packet_is_aligned(&p, 8) { ok = false; }
  }
  return assert(ok, "packet: round trip and frame fields");
}

// --------------------------------------------------
//  t2: padding_for covers blocks 8 and 16 for every payload size
// --------------------------------------------------

fn t2() -> TestResult {
  var ok = true;
  var i = 0;
  while i <= 40 {
    let payload = repeat_byte(7, i);
    let p8 = ssh2_packet_padding_for(i, 8);
    if p8 < 4 { ok = false; }
    let p16 = ssh2_packet_padding_for(i, 16);
    if p16 < 4 { ok = false; }
    let pkt8 = ssh2_write_packet_aligned(&payload, 8);
    let r8 = ssh2_parse_packet(&pkt8, 0);
    if !r8.is_ok {
      ok = false;
    } else {
      let a: Ssh2Packet = r8.value;
      if !ssh2_packet_is_aligned(&a, 8) { ok = false; }
    }
    let pkt16 = ssh2_write_packet_aligned(&payload, 16);
    if pkt16.len() % 16 != 0 { ok = false; }
    i = i + 1;
  }
  // block < 8 is clamped up to 8: used 5 -> rem 5 -> pad 3 -> +8 = 11.
  if ssh2_packet_padding_for(0, 4) != 11 { ok = false; }
  if ssh2_packet_padding_for(0, 8) != 11 { ok = false; }
  return assert(ok, "packet: padding_for matrices (block 8 and 16)");
}

// --------------------------------------------------
//  t3: malformed packet lengths, padding and truncation
// --------------------------------------------------

fn t3() -> TestResult {
  var ok = true;
  // packet_length 3 < padding_length + 1
  var a = Vec[UInt8].new();
  ssh2_write_uint32(&mut a, 3);
  a.push(4 as UInt8);
  ssh2_write_byte(&mut a, 1);
  if !err_pkt_is(ssh2_parse_packet(&a, 0), "ssh2: packet length underflow at 0") { ok = false; }
  // padding_length 3 < 4
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, 6);
  b.push(3 as UInt8);
  ssh2_write_byte(&mut b, 1);
  if !err_pkt_is(ssh2_parse_packet(&b, 0), "ssh2: padding too short at 0") { ok = false; }
  // packet_length 40000 > 35000
  var c = Vec[UInt8].new();
  ssh2_write_uint32(&mut c, 40000);
  c.push(4 as UInt8);
  if !err_pkt_is(ssh2_parse_packet(&c, 0), "ssh2: packet too long at 0") { ok = false; }
  // packet_length 100 declared, buffer much shorter
  var d = Vec[UInt8].new();
  ssh2_write_uint32(&mut d, 100);
  d.push(4 as UInt8);
  if !err_pkt_is(ssh2_parse_packet(&d, 0), "ssh2: truncated packet payload at 0") { ok = false; }
  // fewer than 4 bytes for the length block
  let e = hb("0001");
  if !err_pkt_is(ssh2_parse_packet(&e, 0), "ssh2: truncated packet header at 0") { ok = false; }
  if !err_pkt_is(ssh2_parse_packet(&e, -1), "ssh2: negative offset") { ok = false; }
  // packet_length 0
  let f = hb("00000000");
  if !err_pkt_is(ssh2_parse_packet(&f, 0), "ssh2: packet length underflow at 0") { ok = false; }
  // same underflow seen from a non-zero offset
  let g = hb("ffff" + "00000003" + "04" + "000000");
  if !err_pkt_is(ssh2_parse_packet(&g, 2), "ssh2: packet length underflow at 2") { ok = false; }
  return assert(ok, "packet: malformed length/padding/truncation catalog");
}

// --------------------------------------------------
//  t4: byte / boolean / uint32 primitives
// --------------------------------------------------

fn t4() -> TestResult {
  var ok = true;
  let d = hb("00" + "01" + "02" + "ff" + "00000000" + "ffffffff" + "01020304");
  let b0 = ssh2_read_byte(&d, 0);
  if !b0.is_ok { ok = false; } else { if b0.value != 0 { ok = false; } }
  let b1 = ssh2_read_byte(&d, 1);
  if !b1.is_ok { ok = false; } else { if b1.value != 1 { ok = false; } }
  let b3 = ssh2_read_byte(&d, 3);
  if !b3.is_ok { ok = false; } else { if b3.value != 255 { ok = false; } }
  let q0 = ssh2_read_boolean(&d, 0);
  if !q0.is_ok { ok = false; } else { if q0.value { ok = false; } }
  let q1 = ssh2_read_boolean(&d, 1);
  if !q1.is_ok { ok = false; } else { if !q1.value { ok = false; } }
  let q3 = ssh2_read_boolean(&d, 3);
  if !q3.is_ok { ok = false; } else { if !q3.value { ok = false; } }
  let u0 = ssh2_read_uint32(&d, 4);
  if !u0.is_ok { ok = false; } else { if u0.value != 0 { ok = false; } }
  let u1 = ssh2_read_uint32(&d, 8);
  if !u1.is_ok { ok = false; } else { if u1.value != 4294967295 { ok = false; } }
  let u2 = ssh2_read_uint32(&d, 12);
  if !u2.is_ok { ok = false; } else { if u2.value != 16909060 { ok = false; } }
  if !err_int_is(ssh2_read_byte(&d, 16), "ssh2: truncated byte at 16") { ok = false; }
  if !err_int_is(ssh2_read_boolean(&d, 16), "ssh2: truncated boolean at 16") { ok = false; }
  if !err_int_is(ssh2_read_uint32(&d, 14), "ssh2: truncated uint32 at 14") { ok = false; }
  if !err_int_is(ssh2_read_byte(&d, -1), "ssh2: negative offset") { ok = false; }
  return assert(ok, "fields: byte/boolean/uint32 reads and truncation");
}

// --------------------------------------------------
//  t5: string round trip (binary safe) and truncation
// --------------------------------------------------

fn t5() -> TestResult {
  var ok = true;
  var data = Vec[UInt8].new();
  data.push(0 as UInt8);
  data.push(255 as UInt8);
  data.push(65 as UInt8);
  data.push(0 as UInt8);
  data.push(10 as UInt8);
  var buf = Vec[UInt8].new();
  ssh2_write_string(&mut buf, &data);
  if buf.len() != 4 + data.len() { ok = false; }
  let r = ssh2_read_string(&buf, 0);
  if !r.is_ok {
    ok = false;
  } else {
    let v: Vec[UInt8] = r.value;
    if !bytes_equal(v, data) { ok = false; }
  }
  let s = ssh2_read_string_slice(&buf, 0);
  if !s.is_ok {
    ok = false;
  } else {
    let sl: Ssh2Slice = s.value;
    if sl.start != 4 { ok = false; }
    if sl.len != data.len() { ok = false; }
    if sl.total != 4 + data.len() { ok = false; }
    let c = ssh2_slice_bytes(&buf, &sl);
    if !bytes_equal(c, data) { ok = false; }
  }
  // zero-length string
  var empty = Vec[UInt8].new();
  var eb = Vec[UInt8].new();
  ssh2_write_string(&mut eb, &empty);
  if eb.len() != 4 { ok = false; }
  let er = ssh2_read_string(&eb, 0);
  if !er.is_ok { ok = false; } else { if er.value.len() != 0 { ok = false; } }
  // declared length beyond the buffer
  if !err_bytes_is(ssh2_read_string(&hb("00000005aabb"), 0), "ssh2: truncated string at 0") { ok = false; }
  // length prefix itself truncated
  if !err_bytes_is(ssh2_read_string(&hb("0000"), 0), "ssh2: truncated string length at 0") { ok = false; }
  if !err_bytes_is(ssh2_read_string(&hb(""), 0), "ssh2: truncated string length at 0") { ok = false; }
  return assert(ok, "fields: string binary-safe round trip and truncation");
}

// --------------------------------------------------
//  t6: mpint raw round trip, sign inspection, classic DH check
// --------------------------------------------------

fn t6() -> TestResult {
  var ok = true;
  let pos = hb("00ff");
  let neg = hb("ff80");
  let empty = Vec[UInt8].new();
  if ssh2_mpint_is_negative(&pos) { ok = false; }
  if !ssh2_mpint_is_negative(&neg) { ok = false; }
  if ssh2_mpint_is_negative(&empty) { ok = false; }
  var buf = Vec[UInt8].new();
  ssh2_write_mpint(&mut buf, &pos);
  if buf.len() != 6 { ok = false; }
  let r = ssh2_read_mpint(&buf, 0);
  if !r.is_ok {
    ok = false;
  } else {
    let v: Vec[UInt8] = r.value;
    if !bytes_equal(v, pos) { ok = false; }
  }
  let s = ssh2_read_mpint_slice(&buf, 0);
  if !s.is_ok {
    ok = false;
  } else {
    let sl: Ssh2Slice = s.value;
    if sl.start != 4 { ok = false; }
    if sl.len != 2 { ok = false; }
    if sl.total != 6 { ok = false; }
  }
  if !err_bytes_is(ssh2_read_mpint(&hb("00000003aabb"), 0), "ssh2: truncated mpint at 0") { ok = false; }
  if !err_bytes_is(ssh2_read_mpint(&hb("00"), 0), "ssh2: truncated mpint length at 0") { ok = false; }
  // classic DH check: a negative e in KEXDH_INIT is rejected at the field offset
  let bad = ssh2_encode_kexdh_init(&hb("ff"));
  if !err_dhinit_is(ssh2_parse_kexdh_init(&bad, 0), "ssh2: negative DH value at 6") { ok = false; }
  return assert(ok, "fields: mpint raw round trip, sign, negative DH check");
}

// --------------------------------------------------
//  t7: name-list validation, counting, lookup, round trip
// --------------------------------------------------

fn t7() -> TestResult {
  var ok = true;
  let list = bytes_of("aes128-ctr,aes256-ctr,hmac-sha2-256");
  var buf = Vec[UInt8].new();
  ssh2_write_name_list(&mut buf, &list);
  if !ssh2_name_list_is_valid(&list) { ok = false; }
  if ssh2_name_list_count(&list) != 3 { ok = false; }
  let n1 = ssh2_name_list_name(&list, 1);
  if !bytes_equal(n1, bytes_of("aes256-ctr")) { ok = false; }
  let n9 = ssh2_name_list_name(&list, 9);
  if n9.len() != 0 { ok = false; }
  if !ssh2_name_list_contains(&list, &bytes_of("hmac-sha2-256")) { ok = false; }
  if ssh2_name_list_contains(&list, &bytes_of("none")) { ok = false; }
  let empty = bytes_of("");
  if ssh2_name_list_count(&empty) != 0 { ok = false; }
  if !ssh2_name_list_is_valid(&empty) { ok = false; }
  if ssh2_name_list_is_valid(&bytes_of("a,,b")) { ok = false; }
  if ssh2_name_list_is_valid(&bytes_of("a,")) { ok = false; }
  if ssh2_name_list_is_valid(&bytes_of("a b")) { ok = false; }
  let r = ssh2_read_name_list(&buf, 0);
  if !r.is_ok {
    ok = false;
  } else {
    let v: Vec[UInt8] = r.value;
    if !bytes_equal(v, list) { ok = false; }
  }
  let s = ssh2_read_name_list_slice(&buf, 0);
  if !s.is_ok {
    ok = false;
  } else {
    let sl: Ssh2Slice = s.value;
    if sl.total != 4 + list.len() { ok = false; }
  }
  if !err_bytes_is(ssh2_read_name_list(&hb("00000004" + "612c2c62"), 0), "ssh2: bad name-list at 0") { ok = false; }
  if !err_bytes_is(ssh2_read_name_list(&hb("0000000200ff"), 0), "ssh2: bad name-list at 0") { ok = false; }
  return assert(ok, "fields: name-list validation, lookup and round trip");
}

// --------------------------------------------------
//  t8: SSH_MSG_DISCONNECT
// --------------------------------------------------

fn t8() -> TestResult {
  var ok = true;
  let pkt = ssh2_encode_disconnect(SSH_DISCONNECT_BY_APPLICATION, "bye");
  let r = ssh2_parse_disconnect(&pkt, 0);
  if !r.is_ok {
    ok = false;
  } else {
    let d: Ssh2Disconnect = r.value;
    if d.reason != 11 { ok = false; }
    if !bytes_equal(d.description, bytes_of("bye")) { ok = false; }
    if d.language.len() != 0 { ok = false; }
    if d.total != pkt.len() { ok = false; }
  }
  if !str_eq(ssh2_disconnect_reason_name(11), "BY_APPLICATION") { ok = false; }
  if !str_eq(ssh2_disconnect_reason_name(15), "ILLEGAL_USER_NAME") { ok = false; }
  if !str_eq(ssh2_disconnect_reason_message(14), "no more authentication methods available") { ok = false; }
  if !str_eq(ssh2_disconnect_reason_name(99), "") { ok = false; }
  if !str_eq(ssh2_disconnect_reason_message(99), "") { ok = false; }
  // trailing byte after the language tag
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, 1);
  ssh2_write_string(&mut b, bytes_of("x"));
  ssh2_write_string(&mut b, bytes_of(""));
  b.push(9 as UInt8);
  if !err_dis_is(ssh2_parse_disconnect(&msg(SSH_MSG_DISCONNECT, b), 0), "ssh2: trailing bytes at 19") { ok = false; }
  // wrong message number
  let nk = ssh2_encode_newkeys();
  if !err_dis_is(ssh2_parse_disconnect(&nk, 0), "ssh2: not a disconnect message at 0") { ok = false; }
  return assert(ok, "disconnect: fields, reason table, trailing byte, type check");
}

// --------------------------------------------------
//  t9: IGNORE / UNIMPLEMENTED / DEBUG
// --------------------------------------------------

fn t9() -> TestResult {
  var ok = true;
  let ip = ssh2_encode_ignore(&hb("00ff10"));
  let ir = ssh2_parse_ignore(&ip, 0);
  if !ir.is_ok {
    ok = false;
  } else {
    let v: Ssh2Ignore = ir.value;
    if !bytes_equal(v.data, hb("00ff10")) { ok = false; }
    if v.total != ip.len() { ok = false; }
  }
  let up = ssh2_encode_unimplemented(42);
  let ur = ssh2_parse_unimplemented(&up, 0);
  if !ur.is_ok {
    ok = false;
  } else {
    let u: Ssh2Unimplemented = ur.value;
    if u.sequence != 42 { ok = false; }
  }
  let dp = ssh2_encode_debug(true, "hi");
  let dr = ssh2_parse_debug(&dp, 0);
  if !dr.is_ok {
    ok = false;
  } else {
    let d: Ssh2Debug = dr.value;
    if !d.always_display { ok = false; }
    if !bytes_equal(d.message, bytes_of("hi")) { ok = false; }
  }
  let dp2 = ssh2_encode_debug(false, "quiet");
  let dr2 = ssh2_parse_debug(&dp2, 0);
  if !dr2.is_ok {
    ok = false;
  } else {
    let d2: Ssh2Debug = dr2.value;
    if d2.always_display { ok = false; }
  }
  return assert(ok, "transport: IGNORE, UNIMPLEMENTED and DEBUG");
}

// --------------------------------------------------
//  t10: KEXINIT with the full ten name-lists
// --------------------------------------------------

fn t10() -> TestResult {
  var ok = true;
  var cookie = Vec[UInt8].new();
  var i = 0;
  while i < 16 {
    cookie.push(i as UInt8);
    i = i + 1;
  }
  let kex = bytes_of("curve25519-sha256,ecdh-sha2-nistp256");
  let hk = bytes_of("ssh-ed25519,rsa-sha2-256");
  let enc_a = bytes_of("aes128-ctr");
  let enc_b = bytes_of("aes256-ctr");
  let mac_a = bytes_of("hmac-sha2-256");
  let mac_b = bytes_of("hmac-sha2-512");
  let cmp_a = bytes_of("none");
  let cmp_b = bytes_of("zlib@openssh.com");
  let lang = bytes_of("");
  let pkt = ssh2_encode_kexinit(&cookie, &kex, &hk, &enc_a, &enc_b, &mac_a, &mac_b, &cmp_a, &cmp_b, &lang, &lang, true, 0);
  let r = ssh2_parse_kexinit(&pkt, 0);
  if !r.is_ok {
    ok = false;
  } else {
    let k: Ssh2KexInit = r.value;
    if k.cookie.len() != 16 { ok = false; }
    if !bytes_equal(k.cookie, cookie) { ok = false; }
    if !ssh2_name_list_contains(&k.kex_algorithms, &bytes_of("curve25519-sha256")) { ok = false; }
    if ssh2_name_list_count(&k.host_key_algorithms) != 2 { ok = false; }
    if !bytes_equal(k.encryption_c2s, enc_a) { ok = false; }
    if !bytes_equal(k.encryption_s2c, enc_b) { ok = false; }
    if !bytes_equal(k.mac_c2s, mac_a) { ok = false; }
    if !bytes_equal(k.mac_s2c, mac_b) { ok = false; }
    if !bytes_equal(k.compression_c2s, cmp_a) { ok = false; }
    if !bytes_equal(k.compression_s2c, cmp_b) { ok = false; }
    if k.languages_c2s.len() != 0 { ok = false; }
    if k.languages_s2c.len() != 0 { ok = false; }
    if !k.first_kex_packet_follows { ok = false; }
    if k.reserved != 0 { ok = false; }
    if k.total != pkt.len() { ok = false; }
  }
  // empty algorithm list is rejected at the field offset (cookie 16 bytes)
  let empty = bytes_of("");
  let bad = ssh2_encode_kexinit(&cookie, &empty, &hk, &enc_a, &enc_b, &mac_a, &mac_b, &cmp_a, &cmp_b, &lang, &lang, false, 0);
  if !err_kexinit_is(ssh2_parse_kexinit(&bad, 0), "ssh2: empty algorithm name-list at 22") { ok = false; }
  // truncated cookie
  let short = msg(SSH_MSG_KEXINIT, bytes_of("abc"));
  if !err_kexinit_is(ssh2_parse_kexinit(&short, 0), "ssh2: truncated cookie at 6") { ok = false; }
  // type check
  if !err_kexinit_is(ssh2_parse_kexinit(&ssh2_encode_newkeys(), 0), "ssh2: not a kexinit message at 0") { ok = false; }
  return assert(ok, "kex: KEXINIT with ten name-lists and empty-list rejection");
}

// --------------------------------------------------
//  t11: KEXDH / ECDH inits and replies
// --------------------------------------------------

fn t11() -> TestResult {
  var ok = true;
  let e = hb("00" + "9f8d");
  let ip = ssh2_encode_kexdh_init(&e);
  let ir = ssh2_parse_kexdh_init(&ip, 0);
  if !ir.is_ok {
    ok = false;
  } else {
    let init: Ssh2KexDhInit = ir.value;
    if !bytes_equal(init.e, e) { ok = false; }
    if init.total != ip.len() { ok = false; }
  }
  let hk = bytes_of("ssh-ed25519-AAAA");
  let f = hb("01ff00");
  let sig = bytes_of("sig-bytes");
  let rp = ssh2_encode_kexdh_reply(&hk, &f, &sig);
  let rr = ssh2_parse_kexdh_reply(&rp, 0);
  if !rr.is_ok {
    ok = false;
  } else {
    let reply: Ssh2KexReply = rr.value;
    if !bytes_equal(reply.host_key, hk) { ok = false; }
    if !bytes_equal(reply.value, f) { ok = false; }
    if !bytes_equal(reply.signature, sig) { ok = false; }
    if reply.total != rp.len() { ok = false; }
  }
  // negative f rejected by the classic check
  let bad = ssh2_encode_kexdh_reply(&hk, &hb("80"), &sig);
  if !err_kexreply_is(ssh2_parse_kexdh_reply(&bad, 0), "ssh2: negative DH value at 26") { ok = false; }
  // ECDH: Q_C / Q_S are raw strings, no sign check
  let qc = hb("04" + "00110022");
  let ep = ssh2_encode_kex_ecdh_init(&qc);
  let er = ssh2_parse_kex_ecdh_init(&ep, 0);
  if !er.is_ok {
    ok = false;
  } else {
    let ei: Ssh2KexEcdhInit = er.value;
    if !bytes_equal(ei.q_c, qc) { ok = false; }
  }
  let qs = hb("04ff");
  let xp = ssh2_encode_kex_ecdh_reply(&hk, &qs, &sig);
  let xr = ssh2_parse_kex_ecdh_reply(&xp, 0);
  if !xr.is_ok {
    ok = false;
  } else {
    let xv: Ssh2KexReply = xr.value;
    if !bytes_equal(xv.value, qs) { ok = false; }
    if !bytes_equal(xv.host_key, hk) { ok = false; }
    if !bytes_equal(xv.signature, sig) { ok = false; }
  }
  // message 30 is known to the envelope and validates as one blob
  let mr = ssh2_parse_message(&ip, 0);
  if !mr.is_ok {
    ok = false;
  } else {
    let m: Ssh2Message = mr.value;
    if m.msg_type != 30 { ok = false; }
    if !m.known { ok = false; }
  }
  return assert(ok, "kex: KEXDH and ECDH init/reply variants");
}

// --------------------------------------------------
//  t12: NEWKEYS and SERVICE_REQUEST / SERVICE_ACCEPT
// --------------------------------------------------

fn t12() -> TestResult {
  var ok = true;
  let nk = ssh2_encode_newkeys();
  if !ssh2_parse_newkeys(&nk, 0).is_ok { ok = false; }
  let sr = ssh2_encode_service_request("ssh-userauth");
  let rr = ssh2_parse_service_request(&sr, 0);
  if !rr.is_ok {
    ok = false;
  } else {
    let s: Ssh2Service = rr.value;
    if !bytes_equal(s.service, bytes_of("ssh-userauth")) { ok = false; }
    if s.total != sr.len() { ok = false; }
  }
  let sa = ssh2_encode_service_accept("ssh-connection");
  let ar = ssh2_parse_service_accept(&sa, 0);
  if !ar.is_ok {
    ok = false;
  } else {
    let s2: Ssh2Service = ar.value;
    if !bytes_equal(s2.service, bytes_of("ssh-connection")) { ok = false; }
  }
  // type confusion between request and accept
  if !err_service_is(ssh2_parse_service_request(&sa, 0), "ssh2: not a service request message at 0") { ok = false; }
  if !err_service_is(ssh2_parse_service_accept(&sr, 0), "ssh2: not a service accept message at 0") { ok = false; }
  // NEWKEYS must have an empty body
  if !err_unit_is(ssh2_parse_newkeys(&msg(SSH_MSG_NEWKEYS, bytes_of("x")), 0), "ssh2: trailing bytes at 6") { ok = false; }
  return assert(ok, "transport: NEWKEYS and service request/accept");
}

// --------------------------------------------------
//  t13: USERAUTH_REQUEST password / publickey / unknown methods
// --------------------------------------------------

fn t13() -> TestResult {
  var ok = true;
  let pp = ssh2_encode_userauth_password("alice", "ssh-connection", "s3cret");
  let pr = ssh2_parse_userauth_request(&pp, 0);
  if !pr.is_ok {
    ok = false;
  } else {
    let u: Ssh2UserAuthRequest = pr.value;
    if !u.decoded { ok = false; }
    if !bytes_equal(u.user, bytes_of("alice")) { ok = false; }
    if !bytes_equal(u.service, bytes_of("ssh-connection")) { ok = false; }
    if !bytes_equal(u.method, bytes_of("password")) { ok = false; }
    if u.change_password { ok = false; }
    if !bytes_equal(u.secret, bytes_of("s3cret")) { ok = false; }
    if u.old_password.len() != 0 { ok = false; }
    if u.total != pp.len() { ok = false; }
  }
  let cp = ssh2_encode_userauth_password_change("bob", "ssh-connection", "old", "new");
  let cr = ssh2_parse_userauth_request(&cp, 0);
  if !cr.is_ok {
    ok = false;
  } else {
    let c: Ssh2UserAuthRequest = cr.value;
    if !c.change_password { ok = false; }
    if !bytes_equal(c.old_password, bytes_of("old")) { ok = false; }
    if !bytes_equal(c.secret, bytes_of("new")) { ok = false; }
  }
  var nosig = Vec[UInt8].new();
  let blob = hb("0011");
  let kq = ssh2_encode_userauth_publickey("alice", "ssh-connection", "ssh-ed25519", &blob, &nosig);
  let kqr = ssh2_parse_userauth_request(&kq, 0);
  if !kqr.is_ok {
    ok = false;
  } else {
    let k1: Ssh2UserAuthRequest = kqr.value;
    if !k1.decoded { ok = false; }
    if k1.has_signature { ok = false; }
    if !bytes_equal(k1.algorithm, bytes_of("ssh-ed25519")) { ok = false; }
    if !bytes_equal(k1.secret, blob) { ok = false; }
    if k1.signature.len() != 0 { ok = false; }
  }
  let sig = hb("aabbcc");
  let ks = ssh2_encode_userauth_publickey("alice", "ssh-connection", "ssh-ed25519", &blob, &sig);
  let ksr = ssh2_parse_userauth_request(&ks, 0);
  if !ksr.is_ok {
    ok = false;
  } else {
    let k2: Ssh2UserAuthRequest = ksr.value;
    if !k2.has_signature { ok = false; }
    if !bytes_equal(k2.signature, sig) { ok = false; }
    if !bytes_equal(k2.secret, blob) { ok = false; }
  }
  // unknown method keeps its raw tail
  var b = Vec[UInt8].new();
  ssh2_write_string(&mut b, bytes_of("alice"));
  ssh2_write_string(&mut b, bytes_of("ssh-connection"));
  ssh2_write_string(&mut b, bytes_of("keyboard-interactive"));
  b.push(7 as UInt8);
  b.push(8 as UInt8);
  let ur = ssh2_parse_userauth_request(&msg(SSH_MSG_USERAUTH_REQUEST, b), 0);
  if !ur.is_ok {
    ok = false;
  } else {
    let u3: Ssh2UserAuthRequest = ur.value;
    if u3.decoded { ok = false; }
    if !bytes_equal(u3.method, bytes_of("keyboard-interactive")) { ok = false; }
    if u3.extra.len() != 2 { ok = false; }
    if u3.extra[0] != 7 { ok = false; }
  }
  // truncated password string at the field offset
  var tb = Vec[UInt8].new();
  ssh2_write_string(&mut tb, bytes_of("u"));
  ssh2_write_string(&mut tb, bytes_of("s"));
  ssh2_write_string(&mut tb, bytes_of("password"));
  tb.push(0 as UInt8);
  ssh2_write_uint32(&mut tb, 10);
  tb.push(65 as UInt8);
  tb.push(66 as UInt8);
  if !err_uareq_is(ssh2_parse_userauth_request(&msg(SSH_MSG_USERAUTH_REQUEST, tb), 0), "ssh2: truncated string at 29") { ok = false; }
  return assert(ok, "auth: USERAUTH_REQUEST password/publickey/unknown matrix");
}

// --------------------------------------------------
//  t14: USERAUTH_FAILURE / USERAUTH_SUCCESS / BANNER
// --------------------------------------------------

fn t14() -> TestResult {
  var ok = true;
  let methods = bytes_of("publickey,password");
  let fp = ssh2_encode_userauth_failure(&methods, true);
  let fr = ssh2_parse_userauth_failure(&fp, 0);
  if !fr.is_ok {
    ok = false;
  } else {
    let f: Ssh2UserAuthFailure = fr.value;
    if !f.partial { ok = false; }
    if ssh2_name_list_count(&f.methods) != 2 { ok = false; }
    if !ssh2_name_list_contains(&f.methods, &bytes_of("publickey")) { ok = false; }
    if f.total != fp.len() { ok = false; }
  }
  let empty = bytes_of("");
  let ep = ssh2_encode_userauth_failure(&empty, false);
  let er = ssh2_parse_userauth_failure(&ep, 0);
  if !er.is_ok {
    ok = false;
  } else {
    let e2: Ssh2UserAuthFailure = er.value;
    if e2.methods.len() != 0 { ok = false; }
    if e2.partial { ok = false; }
  }
  let sp = ssh2_encode_userauth_success();
  if !ssh2_parse_userauth_success(&sp, 0).is_ok { ok = false; }
  let bp = ssh2_encode_banner("Welcome");
  let br = ssh2_parse_banner(&bp, 0);
  if !br.is_ok {
    ok = false;
  } else {
    let b2: Ssh2Banner = br.value;
    if !bytes_equal(b2.message, bytes_of("Welcome")) { ok = false; }
    if b2.language.len() != 0 { ok = false; }
  }
  // malformed method name-list at the field offset
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, 4);
  b.push(97 as UInt8);
  b.push(44 as UInt8);
  b.push(44 as UInt8);
  b.push(98 as UInt8);
  b.push(0 as UInt8);
  if !err_uafail_is(ssh2_parse_userauth_failure(&msg(SSH_MSG_USERAUTH_FAILURE, b), 0), "ssh2: bad name-list at 6") { ok = false; }
  return assert(ok, "auth: USERAUTH_FAILURE/SUCCESS and BANNER");
}

// --------------------------------------------------
//  t15: GLOBAL_REQUEST / REQUEST_SUCCESS / REQUEST_FAILURE
// --------------------------------------------------

fn t15() -> TestResult {
  var ok = true;
  let gp = ssh2_encode_global_request("tcpip-forward", true, bytes_of("data"));
  let gr = ssh2_parse_global_request(&gp, 0);
  if !gr.is_ok {
    ok = false;
  } else {
    let g: Ssh2GlobalRequest = gr.value;
    if !bytes_equal(g.name, bytes_of("tcpip-forward")) { ok = false; }
    if !g.want_reply { ok = false; }
    if !bytes_equal(g.data, bytes_of("data")) { ok = false; }
    if g.total != gp.len() { ok = false; }
  }
  var none = Vec[UInt8].new();
  let ge = ssh2_encode_global_request("keepalive@openssh.com", false, &none);
  let ger = ssh2_parse_global_request(&ge, 0);
  if !ger.is_ok {
    ok = false;
  } else {
    let g2: Ssh2GlobalRequest = ger.value;
    if g2.want_reply { ok = false; }
    if g2.data.len() != 0 { ok = false; }
  }
  let rs = ssh2_encode_request_success(hb("00ff"));
  let rr = ssh2_parse_request_success(&rs, 0);
  if !rr.is_ok {
    ok = false;
  } else {
    let r: Ssh2RequestSuccess = rr.value;
    if !bytes_equal(r.data, hb("00ff")) { ok = false; }
  }
  let rse = ssh2_encode_request_success(&none);
  let rer = ssh2_parse_request_success(&rse, 0);
  if !rer.is_ok {
    ok = false;
  } else {
    let r2: Ssh2RequestSuccess = rer.value;
    if r2.data.len() != 0 { ok = false; }
  }
  let rf = ssh2_encode_request_failure();
  if !ssh2_parse_request_failure(&rf, 0).is_ok { ok = false; }
  if !err_unit_is(ssh2_parse_request_failure(&msg(SSH_MSG_REQUEST_FAILURE, bytes_of("z")), 0), "ssh2: trailing bytes at 6") { ok = false; }
  return assert(ok, "connection: global request and response messages");
}

// --------------------------------------------------
//  t16: CHANNEL_OPEN type matrix
// --------------------------------------------------

fn t16() -> TestResult {
  var ok = true;
  let sp = ssh2_encode_channel_open_session(7, 1048576, 32768);
  let sr = ssh2_parse_channel_open(&sp, 0);
  if !sr.is_ok {
    ok = false;
  } else {
    let s: Ssh2ChannelOpen = sr.value;
    if !s.decoded { ok = false; }
    if !bytes_equal(s.channel_type, bytes_of("session")) { ok = false; }
    if s.sender != 7 { ok = false; }
    if s.window != 1048576 { ok = false; }
    if s.max_packet != 32768 { ok = false; }
    if s.host.len() != 0 { ok = false; }
    if s.extra.len() != 0 { ok = false; }
    if s.total != sp.len() { ok = false; }
  }
  let dp = ssh2_encode_channel_open_direct_tcpip(8, 1000, 2000, "example.com", 2222, "10.0.0.5", 34567);
  let dr = ssh2_parse_channel_open(&dp, 0);
  if !dr.is_ok {
    ok = false;
  } else {
    let d: Ssh2ChannelOpen = dr.value;
    if !d.decoded { ok = false; }
    if !bytes_equal(d.channel_type, bytes_of("direct-tcpip")) { ok = false; }
    if !bytes_equal(d.host, bytes_of("example.com")) { ok = false; }
    if d.port != 2222 { ok = false; }
    if !bytes_equal(d.origin, bytes_of("10.0.0.5")) { ok = false; }
    if d.origin_port != 34567 { ok = false; }
  }
  let fp = ssh2_encode_channel_open_forwarded_tcpip(9, 10, 20, "srv", 22, "cli", 1234);
  let fr = ssh2_parse_channel_open(&fp, 0);
  if !fr.is_ok {
    ok = false;
  } else {
    let f: Ssh2ChannelOpen = fr.value;
    if !f.decoded { ok = false; }
    if !bytes_equal(f.channel_type, bytes_of("forwarded-tcpip")) { ok = false; }
    if !bytes_equal(f.host, bytes_of("srv")) { ok = false; }
    if f.port != 22 { ok = false; }
    if !bytes_equal(f.origin, bytes_of("cli")) { ok = false; }
    if f.origin_port != 1234 { ok = false; }
  }
  // unknown channel type preserves the type-specific tail
  var b = Vec[UInt8].new();
  ssh2_write_string(&mut b, bytes_of("x11"));
  ssh2_write_uint32(&mut b, 11);
  ssh2_write_uint32(&mut b, 100);
  ssh2_write_uint32(&mut b, 200);
  b.push(97 as UInt8);
  b.push(98 as UInt8);
  let xr = ssh2_parse_channel_open(&msg(SSH_MSG_CHANNEL_OPEN, b), 0);
  if !xr.is_ok {
    ok = false;
  } else {
    let x: Ssh2ChannelOpen = xr.value;
    if x.decoded { ok = false; }
    if !bytes_equal(x.channel_type, bytes_of("x11")) { ok = false; }
    if x.sender != 11 { ok = false; }
    if !bytes_equal(x.extra, bytes_of("ab")) { ok = false; }
  }
  // session with a trailing byte is rejected
  var tb = Vec[UInt8].new();
  ssh2_write_string(&mut tb, bytes_of("session"));
  ssh2_write_uint32(&mut tb, 1);
  ssh2_write_uint32(&mut tb, 2);
  ssh2_write_uint32(&mut tb, 3);
  tb.push(0 as UInt8);
  if !err_chopen_is(ssh2_parse_channel_open(&msg(SSH_MSG_CHANNEL_OPEN, tb), 0), "ssh2: trailing bytes at 29") { ok = false; }
  return assert(ok, "channel: CHANNEL_OPEN session/direct/forwarded/unknown matrix");
}

// --------------------------------------------------
//  t17: CHANNEL_OPEN_CONFIRMATION / CHANNEL_OPEN_FAILURE
// --------------------------------------------------

fn t17() -> TestResult {
  var ok = true;
  let extra = bytes_of("xy");
  let cp = ssh2_encode_channel_open_confirmation(3, 4, 65536, 32768, &extra);
  let cr = ssh2_parse_channel_open_confirmation(&cp, 0);
  if !cr.is_ok {
    ok = false;
  } else {
    let c: Ssh2ChannelOpenConfirmation = cr.value;
    if c.recipient != 3 { ok = false; }
    if c.sender != 4 { ok = false; }
    if c.window != 65536 { ok = false; }
    if c.max_packet != 32768 { ok = false; }
    if !bytes_equal(c.extra, extra) { ok = false; }
    if c.total != cp.len() { ok = false; }
  }
  let of = ssh2_encode_channel_open_failure(3, SSH_OPEN_CONNECT_FAILED, "nope");
  let orv = ssh2_parse_channel_open_failure(&of, 0);
  if !orv.is_ok {
    ok = false;
  } else {
    let o: Ssh2ChannelOpenFailure = orv.value;
    if o.recipient != 3 { ok = false; }
    if o.reason != 2 { ok = false; }
    if !bytes_equal(o.description, bytes_of("nope")) { ok = false; }
    if o.language.len() != 0 { ok = false; }
  }
  if !str_eq(ssh2_channel_open_failure_reason_name(1), "ADMINISTRATIVELY_PROHIBITED") { ok = false; }
  if !str_eq(ssh2_channel_open_failure_reason_name(3), "UNKNOWN_CHANNEL_TYPE") { ok = false; }
  if !str_eq(ssh2_channel_open_failure_reason_name(4), "RESOURCE_SHORTAGE") { ok = false; }
  if !str_eq(ssh2_channel_open_failure_reason_name(9), "") { ok = false; }
  return assert(ok, "channel: open confirmation and failure");
}

// --------------------------------------------------
//  t18: CHANNEL_WINDOW_ADJUST
// --------------------------------------------------

fn t18() -> TestResult {
  var ok = true;
  let wp = ssh2_encode_window_adjust(9, 4096);
  let wr = ssh2_parse_window_adjust(&wp, 0);
  if !wr.is_ok {
    ok = false;
  } else {
    let w: Ssh2WindowAdjust = wr.value;
    if w.recipient != 9 { ok = false; }
    if w.bytes != 4096 { ok = false; }
    if w.total != wp.len() { ok = false; }
  }
  if !err_int_is(ssh2_parse_channel_success(&wp, 0), "ssh2: not a channel success message at 0") { ok = false; }
  return assert(ok, "channel: WINDOW_ADJUST");
}

// --------------------------------------------------
//  t19: CHANNEL_REQUEST type matrix
// --------------------------------------------------

fn t19() -> TestResult {
  var ok = true;
  let modes = hb("00");
  let pp = ssh2_encode_channel_pty_req(5, "xterm-256color", 120, 40, 800, 600, &modes, true);
  let pr = ssh2_parse_channel_request(&pp, 0);
  if !pr.is_ok {
    ok = false;
  } else {
    let p: Ssh2ChannelRequest = pr.value;
    if !p.decoded { ok = false; }
    if p.recipient != 5 { ok = false; }
    if !bytes_equal(p.request, bytes_of("pty-req")) { ok = false; }
    if !p.want_reply { ok = false; }
    if !bytes_equal(p.text0, bytes_of("xterm-256color")) { ok = false; }
    if p.u32_0 != 120 { ok = false; }
    if p.u32_1 != 40 { ok = false; }
    if p.u32_2 != 800 { ok = false; }
    if p.u32_3 != 600 { ok = false; }
    if !bytes_equal(p.text1, modes) { ok = false; }
    if p.total != pp.len() { ok = false; }
  }
  let ep = ssh2_encode_channel_env(5, "LANG", "C.UTF-8", false);
  let er = ssh2_parse_channel_request(&ep, 0);
  if !er.is_ok {
    ok = false;
  } else {
    let e: Ssh2ChannelRequest = er.value;
    if !e.decoded { ok = false; }
    if e.want_reply { ok = false; }
    if !bytes_equal(e.text0, bytes_of("LANG")) { ok = false; }
    if !bytes_equal(e.text1, bytes_of("C.UTF-8")) { ok = false; }
  }
  let xp = ssh2_encode_channel_exec(5, "ls -la", true);
  let xr = ssh2_parse_channel_request(&xp, 0);
  if !xr.is_ok {
    ok = false;
  } else {
    let x: Ssh2ChannelRequest = xr.value;
    if !x.decoded { ok = false; }
    if !bytes_equal(x.text0, bytes_of("ls -la")) { ok = false; }
  }
  let shp = ssh2_encode_channel_shell(5, true);
  let shr = ssh2_parse_channel_request(&shp, 0);
  if !shr.is_ok {
    ok = false;
  } else {
    let s: Ssh2ChannelRequest = shr.value;
    if !s.decoded { ok = false; }
    if !bytes_equal(s.request, bytes_of("shell")) { ok = false; }
    if s.text0.len() != 0 { ok = false; }
  }
  let sup = ssh2_encode_channel_subsystem(5, "sftp", true);
  let sur = ssh2_parse_channel_request(&sup, 0);
  if !sur.is_ok {
    ok = false;
  } else {
    let u: Ssh2ChannelRequest = sur.value;
    if !u.decoded { ok = false; }
    if !bytes_equal(u.text0, bytes_of("sftp")) { ok = false; }
  }
  let wcp = ssh2_encode_channel_window_change(5, 100, 50, 1000, 500);
  let wcr = ssh2_parse_channel_request(&wcp, 0);
  if !wcr.is_ok {
    ok = false;
  } else {
    let w: Ssh2ChannelRequest = wcr.value;
    if !w.decoded { ok = false; }
    if w.want_reply { ok = false; }
    if w.u32_0 != 100 { ok = false; }
    if w.u32_1 != 50 { ok = false; }
    if w.u32_2 != 1000 { ok = false; }
    if w.u32_3 != 500 { ok = false; }
  }
  // unknown request type keeps its raw tail
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, 5);
  ssh2_write_string(&mut b, bytes_of("xon-xoff"));
  b.push(0 as UInt8);
  b.push(1 as UInt8);
  let kr = ssh2_parse_channel_request(&msg(SSH_MSG_CHANNEL_REQUEST, b), 0);
  if !kr.is_ok {
    ok = false;
  } else {
    let k: Ssh2ChannelRequest = kr.value;
    if k.decoded { ok = false; }
    if !bytes_equal(k.request, bytes_of("xon-xoff")) { ok = false; }
    if k.extra.len() != 1 { ok = false; }
    if k.extra[0] != 1 { ok = false; }
  }
  return assert(ok, "channel: CHANNEL_REQUEST pty/env/exec/shell/subsystem/window-change matrix");
}

// --------------------------------------------------
//  t20: CHANNEL_SUCCESS / FAILURE / EOF / CLOSE
// --------------------------------------------------

fn t20() -> TestResult {
  var ok = true;
  let sp = ssh2_encode_channel_success(7);
  let sr = ssh2_parse_channel_success(&sp, 0);
  if !sr.is_ok {
    ok = false;
  } else {
    if sr.value != 7 { ok = false; }
  }
  let fp = ssh2_encode_channel_failure(7);
  let fr = ssh2_parse_channel_failure(&fp, 0);
  if !fr.is_ok {
    ok = false;
  } else {
    if fr.value != 7 { ok = false; }
  }
  let ep = ssh2_encode_channel_eof(7);
  let er = ssh2_parse_channel_eof(&ep, 0);
  if !er.is_ok {
    ok = false;
  } else {
    if er.value != 7 { ok = false; }
  }
  let cp = ssh2_encode_channel_close(7);
  let cr = ssh2_parse_channel_close(&cp, 0);
  if !cr.is_ok {
    ok = false;
  } else {
    if cr.value != 7 { ok = false; }
  }
  if !err_int_is(ssh2_parse_channel_close(&sp, 0), "ssh2: not a channel close message at 0") { ok = false; }
  var eb = Vec[UInt8].new();
  ssh2_write_uint32(&mut eb, 7);
  eb.push(1 as UInt8);
  if !err_int_is(ssh2_parse_channel_eof(&msg(SSH_MSG_CHANNEL_EOF, eb), 0), "ssh2: trailing bytes at 10") { ok = false; }
  return assert(ok, "channel: success/failure/eof/close");
}

// --------------------------------------------------
//  t21: CHANNEL_DATA and CHANNEL_EXTENDED_DATA
// --------------------------------------------------

fn t21() -> TestResult {
  var ok = true;
  let data = hb("00ff4100");
  let dp = ssh2_encode_channel_data(7, &data);
  let dr = ssh2_parse_channel_data(&dp, 0);
  if !dr.is_ok {
    ok = false;
  } else {
    let d: Ssh2ChannelData = dr.value;
    if d.recipient != 7 { ok = false; }
    if !bytes_equal(d.data, data) { ok = false; }
    if d.total != dp.len() { ok = false; }
  }
  let ext = hb("ff00");
  let xp = ssh2_encode_channel_extended_data(7, SSH_EXTENDED_DATA_STDERR, &ext);
  let xr = ssh2_parse_channel_extended_data(&xp, 0);
  if !xr.is_ok {
    ok = false;
  } else {
    let x: Ssh2ChannelExtendedData = xr.value;
    if x.recipient != 7 { ok = false; }
    if x.data_type != 1 { ok = false; }
    if !bytes_equal(x.data, ext) { ok = false; }
  }
  if !str_eq(ssh2_extended_data_type_name(1), "STDERR") { ok = false; }
  if !str_eq(ssh2_extended_data_type_name(2), "") { ok = false; }
  return assert(ok, "channel: data and extended data");
}

// --------------------------------------------------
//  t22: parse-one-message envelope, consumed counts, unknown raw
// --------------------------------------------------

fn t22() -> TestResult {
  var ok = true;
  let p1 = ssh2_encode_disconnect(SSH_DISCONNECT_CONNECTION_LOST, "gone");
  let p2 = ssh2_encode_channel_data(5, &hb("00ff"));
  let two = concat_bytes(p1, p2);
  let m1 = ssh2_parse_message(&two, 0);
  if !m1.is_ok {
    ok = false;
  } else {
    let a: Ssh2Message = m1.value;
    if a.msg_type != 1 { ok = false; }
    if !a.known { ok = false; }
    if a.start != 0 { ok = false; }
    if a.total != p1.len() { ok = false; }
    if a.raw.len() != a.payload_len { ok = false; }
    if a.body_len != a.payload_len - 1 { ok = false; }
    if a.payload_off != 5 { ok = false; }
    if a.body_off != 6 { ok = false; }
    if a.mac_off != a.total { ok = false; }
    let m2 = ssh2_parse_message(&two, a.total);
    if !m2.is_ok {
      ok = false;
    } else {
      let b2: Ssh2Message = m2.value;
      if b2.msg_type != 94 { ok = false; }
      if b2.start != p1.len() { ok = false; }
    }
  }
  // unknown message type preserved raw
  let up = msg(200, bytes_of("xyz"));
  let um = ssh2_parse_message(&up, 0);
  if !um.is_ok {
    ok = false;
  } else {
    let u: Ssh2Message = um.value;
    if u.known { ok = false; }
    if u.msg_type != 200 { ok = false; }
    if !bytes_equal(u.raw, concat_bytes(hb("c8"), bytes_of("xyz"))) { ok = false; }
  }
  // empty payload is not a message
  var empty = Vec[UInt8].new();
  let ep = ssh2_write_packet(&empty, 4);
  if !err_msg_is(ssh2_parse_message(&ep, 0), "ssh2: empty payload at 0") { ok = false; }
  // a known type with a malformed body surfaces the field error
  var tb = Vec[UInt8].new();
  ssh2_write_uint32(&mut tb, 11);
  ssh2_write_uint32(&mut tb, 9);
  tb.push(65 as UInt8);
  if !err_msg_is(ssh2_parse_message(&msg(SSH_MSG_DISCONNECT, tb), 0), "ssh2: truncated string at 10") { ok = false; }
  if !str_eq(ssh2_message_type_name(1), "SSH_MSG_DISCONNECT") { ok = false; }
  if !str_eq(ssh2_message_type_name(94), "SSH_MSG_CHANNEL_DATA") { ok = false; }
  if !str_eq(ssh2_message_type_name(100), "SSH_MSG_CHANNEL_FAILURE") { ok = false; }
  if !str_eq(ssh2_message_type_name(200), "UNKNOWN") { ok = false; }
  if ssh2_message_type_known(200) { ok = false; }
  if !ssh2_message_type_known(50) { ok = false; }
  return assert(ok, "message: envelope, consumed counts, unknown types raw");
}

// --------------------------------------------------
//  t23: byte offsets are absolute inside the passed buffer
// --------------------------------------------------

fn t23() -> TestResult {
  var ok = true;
  let pkt = ssh2_encode_disconnect(SSH_DISCONNECT_BY_APPLICATION, "bye");
  var buf = Vec[UInt8].new();
  buf.push(255 as UInt8);
  buf.push(255 as UInt8);
  buf.push(255 as UInt8);
  var i = 0;
  while i < pkt.len() {
    buf.push(pkt[i]);
    i = i + 1;
  }
  let r = ssh2_parse_disconnect(&buf, 3);
  if !r.is_ok {
    ok = false;
  } else {
    let d: Ssh2Disconnect = r.value;
    if d.total != pkt.len() { ok = false; }
    if !bytes_equal(d.description, bytes_of("bye")) { ok = false; }
  }
  var tb = Vec[UInt8].new();
  ssh2_write_uint32(&mut tb, 11);
  ssh2_write_uint32(&mut tb, 9);
  tb.push(65 as UInt8);
  let bad = msg(SSH_MSG_DISCONNECT, tb);
  var buf2 = Vec[UInt8].new();
  buf2.push(1 as UInt8);
  buf2.push(2 as UInt8);
  buf2.push(3 as UInt8);
  var k = 0;
  while k < bad.len() {
    buf2.push(bad[k]);
    k = k + 1;
  }
  if !err_dis_is(ssh2_parse_disconnect(&buf2, 3), "ssh2: truncated string at 13") { ok = false; }
  return assert(ok, "errors: absolute byte offsets at a non-zero packet offset");
}

// --------------------------------------------------
//  t24: explicit packet writer and alignment helpers
// --------------------------------------------------

fn t24() -> TestResult {
  var ok = true;
  let payload = bytes_of("A");
  let pkt = ssh2_write_packet(&payload, 4);
  if pkt.len() != 10 { ok = false; }
  let u = ssh2_read_uint32(&pkt, 0);
  if !u.is_ok { ok = false; } else { if u.value != 6 { ok = false; } }
  let b4 = ssh2_read_byte(&pkt, 4);
  if !b4.is_ok { ok = false; } else { if b4.value != 4 { ok = false; } }
  let b5 = ssh2_read_byte(&pkt, 5);
  if !b5.is_ok { ok = false; } else { if b5.value != 65 { ok = false; } }
  let pr = ssh2_parse_packet(&pkt, 0);
  if !pr.is_ok {
    ok = false;
  } else {
    let p: Ssh2Packet = pr.value;
    if ssh2_packet_is_aligned(&p, 8) { ok = false; }
  }
  let a8 = ssh2_write_packet_aligned(&payload, 8);
  if a8.len() % 8 != 0 { ok = false; }
  let a16 = ssh2_write_packet_aligned(&payload, 16);
  if a16.len() % 16 != 0 { ok = false; }
  if a8.len() <= pkt.len() { ok = false; }
  return assert(ok, "packet: explicit writer and alignment helpers");
}

// --------------------------------------------------
//  main
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.ssh2 conformance tests ===");
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
    io.println("xiom.ssh2: all tests passed");
  } else {
    io.println("xiom.ssh2: tests failed");
  }
  return failed;
}
