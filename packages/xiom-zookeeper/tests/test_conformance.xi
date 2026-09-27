// XIOM -- xiom.zookeeper conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: jute primitives (byte, bool, int, long,
// float/double raw bits, buffer, ustring, vectors) with exact big-endian
// bytes and byte-offset error messages; the connect handshake records;
// request and reply headers; the opcode / xid / error / event / state
// tables; Stat, Id, ACL and ACL vectors; watch events (including the
// null path); create, delete, exists, getData, setData, getChildren,
// getAcl, setAcl, sync, check and auth records; parse-one-message and
// parse-one-reply with consumed counts; and the malformed-input paths
// (truncation, negative lengths, bad vectors, invalid bools, bad UTF-8,
// NUL, unsupported opcodes, trailing data).
//
// Harness style mirrors xiom.cbor / xiom.iso8583 / xiom.thrift: one
// fn tN() -> TestResult per check, called directly from main; main
// prints [PASS]/[FAIL] and returns the failure count. Synthetic buffers
// are built in-test from hex literals (xiom.encoding.hex); no external
// data files. Str payloads are compared with str_compare (BUG 17
// discipline: `==` on Str values read from a Vec lowers to a pointer
// comparison).

module zookeeper_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.encoding.hex;
use xiom.zookeeper;

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

// Bytes of a Str, byte-for-byte (UTF-8 literals included).
fn ab(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    v.push(b);
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
    if ((x as Int) & 0xFF) != ((y as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Append every byte of `v` to `out`.
fn append_bytes(out: &mut Vec[UInt8], v: Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// First byte of a vector as 0..255, or -1 when empty.
fn first_byte(v: Vec[UInt8]) -> Int {
  if v.len() == 0 {
    return -1;
  }
  let b: UInt8 = v[0];
  return (b as Int) & 0xFF;
}

// True when the result failed with exactly `want`. One helper per result
// payload type: a generic `err_is[T](r: Result[T, Str], ...)` miscompiles
// on v0.61.3 (it compares unrelated strings), so the harness uses
// monomorphic helpers.
fn err_is_i(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_b(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_s(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_bytes(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_names(r: Result[Vec[Str], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_hdr(r: Result[ZkRequestHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_rhdr(r: Result[ZkReplyHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_creq(r: Result[ZkConnectRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_cresp(r: Result[ZkConnectResponse, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_stat(r: Result[ZkStat, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_aclvec(r: Result[ZkAclVec, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_event(r: Result[ZkWatchEvent, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_crq(r: Result[ZkCreateRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_gcr(r: Result[ZkGetChildrenResponse, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_arq(r: Result[ZkAuthRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_msg(r: Result[ZkMessage, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_reply(r: Result[ZkReply, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

// A one-ACL ACL vector.
fn acl1(perms: Int, scheme: Str, id: Str) -> ZkAclVec {
  var v = zk_acl_vec_new();
  zk_acl_vec_push(&mut v, perms, scheme, id);
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var w = zk_writer_new();
  zk_write_int(&mut w, 16909060);
  zk_write_int(&mut w, -1);
  zk_write_int(&mut w, -2147483648);
  zk_write_int(&mut w, 2147483647);
  zk_write_long(&mut w, 1);
  zk_write_long(&mut w, -2);
  zk_write_long(&mut w, -9223372036854775807 - 1);
  zk_write_long(&mut w, 9223372036854775807);
  let want = hb("01020304ffffffff800000007fffffff0000000000000001fffffffffffffffe80000000000000007fffffffffffffff");
  var ok = bytes_equal(zk_writer_bytes(&w), want);
  var r = zk_reader_new(zk_writer_bytes(&w));
  let a = zk_read_int(&mut r);
  let b = zk_read_int(&mut r);
  let c = zk_read_int(&mut r);
  let d = zk_read_int(&mut r);
  if !a.is_ok || !b.is_ok || !c.is_ok || !d.is_ok { ok = false; } else {
    if a.value != 16909060 { ok = false; }
    if b.value != -1 { ok = false; }
    if c.value != -2147483648 { ok = false; }
    if d.value != 2147483647 { ok = false; }
  }
  let e = zk_read_long(&mut r);
  let f = zk_read_long(&mut r);
  let g = zk_read_long(&mut r);
  let h = zk_read_long(&mut r);
  if !e.is_ok || !f.is_ok || !g.is_ok || !h.is_ok { ok = false; } else {
    if e.value != 1 { ok = false; }
    if f.value != -2 { ok = false; }
    if g.value != -9223372036854775807 - 1 { ok = false; }
    if h.value != 9223372036854775807 { ok = false; }
  }
  let t = zk_read_int(&mut r);
  if !err_is_i(t, "zookeeper: truncated input at byte 48") { ok = false; }
  if zk_reader_remaining(&r) != 0 { ok = false; }
  return assert(ok, "int and long encode and decode exact big-endian signed boundaries");
}

fn t2() -> TestResult {
  var w = zk_writer_new();
  zk_write_byte(&mut w, 0);
  zk_write_byte(&mut w, 127);
  zk_write_byte(&mut w, -1);
  zk_write_byte(&mut w, -128);
  zk_write_bool(&mut w, true);
  zk_write_bool(&mut w, false);
  zk_write_float_bits(&mut w, 1065353216);
  zk_write_float_bits(&mut w, 3221225472);
  zk_write_double_bits(&mut w, 4607182418800017408);
  var ok = bytes_equal(zk_writer_bytes(&w), hb("007fff8001003f800000c00000003ff0000000000000"));
  var r = zk_reader_new(zk_writer_bytes(&w));
  let b1 = zk_read_byte(&mut r);
  let b2 = zk_read_byte(&mut r);
  let b3 = zk_read_byte(&mut r);
  let b4 = zk_read_byte(&mut r);
  let t1 = zk_read_bool(&mut r);
  let t2 = zk_read_bool(&mut r);
  if !b1.is_ok || !b2.is_ok || !b3.is_ok || !b4.is_ok { ok = false; } else {
    if b1.value != 0 { ok = false; }
    if b2.value != 127 { ok = false; }
    if b3.value != -1 { ok = false; }
    if b4.value != -128 { ok = false; }
  }
  if !t1.is_ok || !t2.is_ok { ok = false; } else {
    if !t1.value { ok = false; }
    if t2.value { ok = false; }
  }
  let f1 = zk_read_float_bits(&mut r);
  let f2 = zk_read_float_bits(&mut r);
  let d1 = zk_read_double_bits(&mut r);
  if !f1.is_ok || !f2.is_ok || !d1.is_ok { ok = false; } else {
    if f1.value != 1065353216 { ok = false; }
    if f2.value != 3221225472 { ok = false; }
    if d1.value != 4607182418800017408 { ok = false; }
  }
  if zk_reader_remaining(&r) != 0 { ok = false; }
  var r2 = zk_reader_new(hb("02"));
  if !err_is_b(zk_read_bool(&mut r2), "zookeeper: invalid bool byte 2 at byte 0") { ok = false; }
  var r3 = zk_reader_new(hb("ff"));
  if !err_is_b(zk_read_bool(&mut r3), "zookeeper: invalid bool byte 255 at byte 0") { ok = false; }
  var r4 = zk_reader_new(hb(""));
  if !err_is_b(zk_read_bool(&mut r4), "zookeeper: truncated input at byte 0") { ok = false; }
  var r5 = zk_reader_new(hb("3f80"));
  if !err_is_i(zk_read_float_bits(&mut r5), "zookeeper: truncated input at byte 0") { ok = false; }
  return assert(ok, "byte, bool (strict 0/1), float and double raw bits encode and decode");
}

fn t3() -> TestResult {
  var w = zk_writer_new();
  zk_write_buffer(&mut w, &Vec[UInt8].new());
  let payload = hb("00ff");
  zk_write_buffer(&mut w, &payload);
  zk_write_null_buffer(&mut w);
  var ok = bytes_equal(zk_writer_bytes(&w), hb("000000000000000200ffffffffff"));
  var r = zk_reader_new(zk_writer_bytes(&w));
  let e = zk_read_buffer(&mut r);
  let p = zk_read_buffer(&mut r);
  let n = zk_read_buffer(&mut r);
  if !e.is_ok || !p.is_ok || !n.is_ok { ok = false; } else {
    if e.value.len() != 0 { ok = false; }
    if !bytes_equal(p.value, payload) { ok = false; }
    if n.value.len() != 0 { ok = false; }
  }
  if zk_reader_remaining(&r) != 0 { ok = false; }
  var r2 = zk_reader_new(hb("fffffffe"));
  if !err_is_bytes(zk_read_buffer(&mut r2), "zookeeper: invalid buffer length -2 at byte 0") { ok = false; }
  var r3 = zk_reader_new(hb("000000056869"));
  if !err_is_bytes(zk_read_buffer(&mut r3), "zookeeper: truncated input at byte 4") { ok = false; }
  var r4 = zk_reader_new(hb("000000"));
  if !err_is_bytes(zk_read_buffer(&mut r4), "zookeeper: truncated input at byte 0") { ok = false; }
  var r5 = zk_reader_new(hb("0000000100"));
  let one = zk_read_buffer(&mut r5);
  if !one.is_ok { ok = false; } else {
    if one.value.len() != 1 { ok = false; }
    if first_byte(one.value) != 0 { ok = false; }
  }
  return assert(ok, "buffer encodes length + bytes, -1 is null, other negatives are rejected");
}

fn t4() -> TestResult {
  var w = zk_writer_new();
  zk_write_ustring(&mut w, "hi");
  zk_write_ustring(&mut w, "héllo");
  zk_write_ustring(&mut w, "");
  zk_write_null_ustring(&mut w);
  var ok = bytes_equal(zk_writer_bytes(&w), hb("0000000268690000000668c3a96c6c6f00000000ffffffff"));
  var r = zk_reader_new(zk_writer_bytes(&w));
  let a = zk_read_ustring(&mut r);
  let b = zk_read_ustring(&mut r);
  let c = zk_read_ustring(&mut r);
  let d = zk_read_ustring(&mut r);
  if !a.is_ok || !b.is_ok || !c.is_ok || !d.is_ok { ok = false; } else {
    if str_compare(a.value, "hi") != 0 { ok = false; }
    if str_compare(b.value, "héllo") != 0 { ok = false; }
    if str_compare(c.value, "") != 0 { ok = false; }
    if str_compare(d.value, "") != 0 { ok = false; }
  }
  if zk_reader_remaining(&r) != 0 { ok = false; }
  var r2 = zk_reader_new(hb("fffffffd"));
  if !err_is_s(zk_read_ustring(&mut r2), "zookeeper: invalid string length -3 at byte 0") { ok = false; }
  var r3 = zk_reader_new(hb("00000002c328"));
  if !err_is_s(zk_read_ustring(&mut r3), "zookeeper: invalid utf-8 at byte 4") { ok = false; }
  var r4 = zk_reader_new(hb("000000020041"));
  if !err_is_s(zk_read_ustring(&mut r4), "zookeeper: string contains nul at byte 4") { ok = false; }
  var r5 = zk_reader_new(hb("000000056869"));
  if !err_is_s(zk_read_ustring(&mut r5), "zookeeper: truncated input at byte 4") { ok = false; }
  var r6 = zk_reader_new(hb("00000004f09f9880"));
  let emoji = zk_read_ustring(&mut r6);
  if !emoji.is_ok { ok = false; } else {
    if str_compare(emoji.value, "😀") != 0 { ok = false; }
  }
  return assert(ok, "ustring encodes UTF-8 length + bytes, -1 is null, NUL and bad UTF-8 rejected");
}

fn t5() -> TestResult {
  var kids = Vec[Str].new();
  kids.push("a");
  kids.push("bb");
  var w = zk_writer_new();
  zk_write_ustring_vector(&mut w, &kids);
  var ok = bytes_equal(zk_writer_bytes(&w), hb("000000020000000161000000026262"));
  var r = zk_reader_new(zk_writer_bytes(&w));
  let back = zk_read_ustring_vector(&mut r);
  if !back.is_ok { ok = false; } else {
    let v: Vec[Str] = back.value;
    if v.len() != 2 { ok = false; }
    if str_compare(v[0], "a") != 0 { ok = false; }
    if str_compare(v[1], "bb") != 0 { ok = false; }
  }
  if zk_reader_remaining(&r) != 0 { ok = false; }
  var w2 = zk_writer_new();
  zk_write_vector_null(&w2);
  if !bytes_equal(zk_writer_bytes(&w2), hb("ffffffff")) { ok = false; }
  var r2 = zk_reader_new(hb("ffffffff"));
  let cnt = zk_read_vector_count(&mut r2);
  if !cnt.is_ok { ok = false; } else {
    if cnt.value != -1 { ok = false; }
  }
  var r3 = zk_reader_new(hb("fffffffe"));
  if !err_is_i(zk_read_vector_count(&mut r3), "zookeeper: invalid vector count -2 at byte 0") { ok = false; }
  var r4 = zk_reader_new(hb("0000000500"));
  if !err_is_names(zk_read_ustring_vector(&mut r4), "zookeeper: oversized vector count 5 at byte 0") { ok = false; }
  var r5 = zk_reader_new(hb("ffffffff"));
  let nulls = zk_read_ustring_vector(&mut r5);
  if !nulls.is_ok { ok = false; } else {
    if nulls.value.len() != 0 { ok = false; }
  }
  var r6 = zk_reader_new(hb("0000000100000005"));
  if !err_is_names(zk_read_ustring_vector(&mut r6), "zookeeper: truncated input at byte 8") { ok = false; }
  return assert(ok, "vector count and ustring vectors handle null, bad counts and oversized counts");
}

fn t6() -> TestResult {
  var w = zk_writer_new();
  zk_write_request_header(&mut w, 1, 4);
  zk_write_reply_header(&mut w, 1, 2, 0);
  var ok = bytes_equal(zk_writer_bytes(&w), hb("000000010000000400000001000000000000000200000000"));
  var r = zk_reader_new(zk_writer_bytes(&w));
  let h = zk_read_request_header(&mut r);
  if !h.is_ok { ok = false; } else {
    if h.value.xid != 1 { ok = false; }
    if h.value.op != 4 { ok = false; }
  }
  let rh = zk_read_reply_header(&mut r);
  if !rh.is_ok { ok = false; } else {
    if rh.value.xid != 1 { ok = false; }
    if rh.value.zxid != 2 { ok = false; }
    if rh.value.err != 0 { ok = false; }
  }
  if zk_reader_remaining(&r) != 0 { ok = false; }
  var r2 = zk_reader_new(hb("00000001000000"));
  if !err_is_hdr(zk_read_request_header(&mut r2), "zookeeper: truncated input at byte 4") { ok = false; }
  var r3 = zk_reader_new(hb(""));
  if !err_is_hdr(zk_read_request_header(&mut r3), "zookeeper: truncated input at byte 0") { ok = false; }
  var r4 = zk_reader_new(hb("0000000100000000000000"));
  if !err_is_rhdr(zk_read_reply_header(&mut r4), "zookeeper: truncated input at byte 4") { ok = false; }
  var r4b = zk_reader_new(hb("00000001000000000000000000"));
  if !err_is_rhdr(zk_read_reply_header(&mut r4b), "zookeeper: truncated input at byte 12") { ok = false; }
  var w2 = zk_writer_new();
  zk_write_reply_header(&mut w2, -1, -9223372036854775807 - 1, -101);
  var r5 = zk_reader_new(zk_writer_bytes(&w2));
  let rh2 = zk_read_reply_header(&mut r5);
  if !rh2.is_ok { ok = false; } else {
    if rh2.value.xid != -1 { ok = false; }
    if rh2.value.zxid != -9223372036854775807 - 1 { ok = false; }
    if rh2.value.err != -101 { ok = false; }
  }
  return assert(ok, "request header (xid+op) and reply header (xid+zxid+err) encode and decode");
}

// A copy of `v` without its final byte (for truncation tests).
fn drop_last(v: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if v.len() == 0 {
    return out;
  }
  var i = 0;
  while i < v.len() - 1 {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn t7() -> TestResult {
  var want = Vec[UInt8].new();
  append_bytes(&mut want, hb("00000000"));
  append_bytes(&mut want, hb("0000000000000000"));
  append_bytes(&mut want, hb("00007530"));
  append_bytes(&mut want, hb("0000000000000000"));
  append_bytes(&mut want, hb("00000010"));
  append_bytes(&mut want, hb("00000000000000000000000000000000"));
  append_bytes(&mut want, hb("00"));
  let pw = hb("00000000000000000000000000000000");
  let req = ZkConnectRequest{ protocol_version: 0; last_zxid_seen: 0; timeout: 30000; session_id: 0; passwd: pw; read_only: false; };
  let enc = zk_encode_connect_request(&req);
  var ok = bytes_equal(enc, want);
  if enc.len() != 45 { ok = false; }
  let dec = zk_decode_connect_request(enc);
  if !dec.is_ok { ok = false; } else {
    let d: ZkConnectRequest = dec.value;
    if d.protocol_version != 0 { ok = false; }
    if d.last_zxid_seen != 0 { ok = false; }
    if d.timeout != 30000 { ok = false; }
    if d.session_id != 0 { ok = false; }
    if d.passwd.len() != 16 { ok = false; }
    if d.read_only { ok = false; }
  }
  let pw2 = hb("010203");
  let req2 = ZkConnectRequest{ protocol_version: 0; last_zxid_seen: -2; timeout: 1000; session_id: 123456789; passwd: pw2; read_only: true; };
  let enc2 = zk_encode_connect_request(&req2);
  let dec2 = zk_decode_connect_request(enc2);
  if !dec2.is_ok { ok = false; } else {
    let d2: ZkConnectRequest = dec2.value;
    if d2.last_zxid_seen != -2 { ok = false; }
    if d2.timeout != 1000 { ok = false; }
    if d2.session_id != 123456789 { ok = false; }
    if !bytes_equal(d2.passwd, pw2) { ok = false; }
    if !d2.read_only { ok = false; }
  }
  var extra = zk_encode_connect_request(&req2);
  append_bytes(&mut extra, hb("00"));
  let tr = zk_decode_connect_request(extra);
  if !err_is_creq(tr, "zookeeper: trailing data at byte 32") { ok = false; }
  let cut = drop_last(zk_encode_connect_request(&req2));
  let trunc = zk_decode_connect_request(cut);
  if !err_is_creq(trunc, "zookeeper: truncated input at byte 31") { ok = false; }
  var r0 = zk_reader_new(hb("00000000"));
  let empty = zk_read_connect_request(&mut r0);
  if !err_is_creq(empty, "zookeeper: truncated input at byte 4") { ok = false; }
  return assert(ok, "ConnectRequest encodes the 45-byte record and round-trips with trailing/truncated guards");
}

fn t8() -> TestResult {
  var want = Vec[UInt8].new();
  append_bytes(&mut want, hb("00000000"));
  append_bytes(&mut want, hb("00007530"));
  append_bytes(&mut want, hb("0000000000000001"));
  append_bytes(&mut want, hb("00000001"));
  append_bytes(&mut want, hb("09"));
  append_bytes(&mut want, hb("01"));
  let pw = hb("09");
  let resp = ZkConnectResponse{ protocol_version: 0; timeout: 30000; session_id: 1; passwd: pw; read_only: true; };
  let enc = zk_encode_connect_response(&resp);
  var ok = bytes_equal(enc, want);
  if enc.len() != 22 { ok = false; }
  let dec = zk_decode_connect_response(enc);
  if !dec.is_ok { ok = false; } else {
    let d: ZkConnectResponse = dec.value;
    if d.timeout != 30000 { ok = false; }
    if d.session_id != 1 { ok = false; }
    if d.passwd.len() != 1 { ok = false; }
    if !d.read_only { ok = false; }
  }
  let neg = ZkConnectResponse{ protocol_version: 0; timeout: 4000; session_id: -9223372036854775807 - 1; passwd: hb("aabb"); read_only: false; };
  let dec2 = zk_decode_connect_response(zk_encode_connect_response(&neg));
  if !dec2.is_ok { ok = false; } else {
    let d2: ZkConnectResponse = dec2.value;
    if d2.session_id != -9223372036854775807 - 1 { ok = false; }
    if d2.passwd.len() != 2 { ok = false; }
    if d2.read_only { ok = false; }
  }
  var with_extra = zk_encode_connect_response(&resp);
  append_bytes(&mut with_extra, hb("00"));
  let tr = zk_decode_connect_response(with_extra);
  if !err_is_cresp(tr, "zookeeper: trailing data at byte 22") { ok = false; }
  let exact = zk_decode_connect_response(zk_encode_connect_response(&resp));
  if !exact.is_ok { ok = false; }
  var r = zk_reader_new(hb("0000000000007530000000"));
  let half = zk_read_connect_response(&mut r);
  if !err_is_cresp(half, "zookeeper: truncated input at byte 8") { ok = false; }
  return assert(ok, "ConnectResponse encodes the 22-byte record and round-trips");
}

fn t9() -> TestResult {
  var ok = zk_op_error() == -1;
  if zk_op_notification() != 0 { ok = false; }
  if zk_op_create() != 1 { ok = false; }
  if zk_op_delete() != 2 { ok = false; }
  if zk_op_exists() != 3 { ok = false; }
  if zk_op_get_data() != 4 { ok = false; }
  if zk_op_set_data() != 5 { ok = false; }
  if zk_op_get_acl() != 6 { ok = false; }
  if zk_op_set_acl() != 7 { ok = false; }
  if zk_op_get_children() != 8 { ok = false; }
  if zk_op_sync() != 9 { ok = false; }
  if zk_op_create_session() != -10 { ok = false; }
  if zk_op_ping() != 11 { ok = false; }
  if zk_op_get_children2() != 12 { ok = false; }
  if zk_op_check() != 13 { ok = false; }
  if zk_op_multi() != 14 { ok = false; }
  if zk_op_create2() != 15 { ok = false; }
  if zk_op_close() != -11 { ok = false; }
  if zk_op_auth() != 100 { ok = false; }
  if zk_op_set_watches() != 101 { ok = false; }
  if str_compare(zk_op_name(zk_op_create()), "CREATE") != 0 { ok = false; }
  if str_compare(zk_op_name(zk_op_close()), "CLOSE") != 0 { ok = false; }
  if str_compare(zk_op_name(zk_op_set_watches()), "SET_WATCHES") != 0 { ok = false; }
  if str_compare(zk_op_name(99), "UNKNOWN") != 0 { ok = false; }
  if !zk_op_known(zk_op_multi()) { ok = false; }
  if !zk_op_known(zk_op_close()) { ok = false; }
  if zk_op_known(99) { ok = false; }
  if zk_xid_notification() != -1 { ok = false; }
  if zk_xid_ping() != -2 { ok = false; }
  if zk_xid_auth() != -4 { ok = false; }
  if zk_xid_set_watches() != -8 { ok = false; }
  if !zk_xid_is_special(zk_xid_ping()) { ok = false; }
  if !zk_xid_is_special(zk_xid_auth()) { ok = false; }
  if zk_xid_is_special(7) { ok = false; }
  if str_compare(zk_xid_name(zk_xid_notification()), "NOTIFICATION") != 0 { ok = false; }
  if str_compare(zk_xid_name(7), "REQUEST") != 0 { ok = false; }
  if str_compare(zk_xid_name(-3), "UNKNOWN") != 0 { ok = false; }
  return assert(ok, "opcode and special-xid tables match the ZooKeeper wire values");
}

fn t10() -> TestResult {
  var ok = zk_err_ok() == 0;
  if zk_err_nonode() != -101 { ok = false; }
  if zk_err_noauth() != -102 { ok = false; }
  if zk_err_badversion() != -103 { ok = false; }
  if zk_err_nochildrenforephemerals() != -108 { ok = false; }
  if zk_err_nodeexists() != -110 { ok = false; }
  if zk_err_notempty() != -111 { ok = false; }
  if zk_err_sessionexpired() != -112 { ok = false; }
  if zk_err_invalidcallback() != -113 { ok = false; }
  if zk_err_invalidacl() != -114 { ok = false; }
  if zk_err_authfailed() != -115 { ok = false; }
  if zk_err_sessionmoved() != -118 { ok = false; }
  if zk_err_notreadonly() != -119 { ok = false; }
  if zk_err_connectionloss() != -4 { ok = false; }
  if zk_err_operationtimeout() != -7 { ok = false; }
  if zk_err_systemerror() != -1 { ok = false; }
  if zk_err_badarguments() != -8 { ok = false; }
  if str_compare(zk_err_name(zk_err_ok()), "OK") != 0 { ok = false; }
  if str_compare(zk_err_name(zk_err_nonode()), "NONODE") != 0 { ok = false; }
  if str_compare(zk_err_name(zk_err_sessionexpired()), "SESSIONEXPIRED") != 0 { ok = false; }
  if str_compare(zk_err_name(zk_err_badversion()), "BADVERSION") != 0 { ok = false; }
  if str_compare(zk_err_name(-105), "UNKNOWN") != 0 { ok = false; }
  if !zk_err_known(zk_err_nonode()) { ok = false; }
  if !zk_err_known(zk_err_ok()) { ok = false; }
  if zk_err_known(-105) { ok = false; }
  return assert(ok, "error-code table uses the canonical Apache ZooKeeper values");
}

fn t11() -> TestResult {
  var ok = zk_event_none() == -1;
  if zk_event_node_created() != 1 { ok = false; }
  if zk_event_node_deleted() != 2 { ok = false; }
  if zk_event_node_data_changed() != 3 { ok = false; }
  if zk_event_node_children_changed() != 4 { ok = false; }
  if str_compare(zk_event_name(zk_event_node_created()), "NODE_CREATED") != 0 { ok = false; }
  if str_compare(zk_event_name(zk_event_node_children_changed()), "NODE_CHILDREN_CHANGED") != 0 { ok = false; }
  if str_compare(zk_event_name(9), "UNKNOWN") != 0 { ok = false; }
  if zk_state_disconnected() != 0 { ok = false; }
  if zk_state_sync_connected() != 3 { ok = false; }
  if zk_state_auth_failed() != 4 { ok = false; }
  if zk_state_connected_read_only() != 5 { ok = false; }
  if zk_state_sasl_authenticated() != 6 { ok = false; }
  if zk_state_expired() != -112 { ok = false; }
  if str_compare(zk_state_name(zk_state_sync_connected()), "SYNC_CONNECTED") != 0 { ok = false; }
  if str_compare(zk_state_name(zk_state_expired()), "EXPIRED") != 0 { ok = false; }
  if str_compare(zk_state_name(2), "UNKNOWN") != 0 { ok = false; }
  if zk_create_flag_ephemeral() != 1 { ok = false; }
  if zk_create_flag_sequential() != 2 { ok = false; }
  if !zk_create_flag_is_ephemeral(1) { ok = false; }
  if !zk_create_flag_is_ephemeral(3) { ok = false; }
  if zk_create_flag_is_ephemeral(2) { ok = false; }
  if !zk_create_flag_is_sequential(2) { ok = false; }
  if !zk_create_flag_is_sequential(3) { ok = false; }
  if zk_create_flag_is_sequential(1) { ok = false; }
  if str_compare(zk_body_kind_name(1), "CREATE") != 0 { ok = false; }
  if str_compare(zk_body_kind_name(14), "PATH") != 0 { ok = false; }
  return assert(ok, "watch event/state tables and create-flag helpers match the wire values");
}

fn t12() -> TestResult {
  var want = Vec[UInt8].new();
  append_bytes(&mut want, hb("0000000000000001"));
  append_bytes(&mut want, hb("0000000000000002"));
  append_bytes(&mut want, hb("0000000000000003"));
  append_bytes(&mut want, hb("0000000000000004"));
  append_bytes(&mut want, hb("00000005"));
  append_bytes(&mut want, hb("00000006"));
  append_bytes(&mut want, hb("00000007"));
  append_bytes(&mut want, hb("0000000000000008"));
  append_bytes(&mut want, hb("00000009"));
  append_bytes(&mut want, hb("0000000a"));
  append_bytes(&mut want, hb("000000000000000b"));
  let s = ZkStat{ czxid: 1; mzxid: 2; ctime: 3; mtime: 4; version: 5; cversion: 6; aversion: 7; ephemeral_owner: 8; data_length: 9; num_children: 10; pzxid: 11; };
  var w = zk_writer_new();
  zk_write_stat(&mut w, &s);
  var ok = bytes_equal(zk_writer_bytes(&w), want);
  if zk_writer_len(&w) != 68 { ok = false; }
  if zk_stat_wire_size() != 68 { ok = false; }
  var r = zk_reader_new(zk_writer_bytes(&w));
  let back = zk_read_stat(&mut r);
  if !back.is_ok { ok = false; } else {
    let d: ZkStat = back.value;
    if d.czxid != 1 { ok = false; }
    if d.mzxid != 2 { ok = false; }
    if d.ctime != 3 { ok = false; }
    if d.mtime != 4 { ok = false; }
    if d.version != 5 { ok = false; }
    if d.cversion != 6 { ok = false; }
    if d.aversion != 7 { ok = false; }
    if d.ephemeral_owner != 8 { ok = false; }
    if d.data_length != 9 { ok = false; }
    if d.num_children != 10 { ok = false; }
    if d.pzxid != 11 { ok = false; }
  }
  let neg = ZkStat{ czxid: -1; mzxid: 0; ctime: -9223372036854775807 - 1; mtime: 9223372036854775807; version: -1; cversion: -2147483648; aversion: 2147483647; ephemeral_owner: -5; data_length: -10; num_children: 99999; pzxid: -7; };
  var w2 = zk_writer_new();
  zk_write_stat(&mut w2, &neg);
  var r2 = zk_reader_new(zk_writer_bytes(&w2));
  let back2 = zk_read_stat(&mut r2);
  if !back2.is_ok { ok = false; } else {
    let d2: ZkStat = back2.value;
    if d2.czxid != -1 { ok = false; }
    if d2.ctime != -9223372036854775807 - 1 { ok = false; }
    if d2.mtime != 9223372036854775807 { ok = false; }
    if d2.version != -1 { ok = false; }
    if d2.cversion != -2147483648 { ok = false; }
    if d2.aversion != 2147483647 { ok = false; }
    if d2.ephemeral_owner != -5 { ok = false; }
    if d2.data_length != -10 { ok = false; }
    if d2.num_children != 99999 { ok = false; }
    if d2.pzxid != -7 { ok = false; }
  }
  let cut = drop_last(want);
  var r3 = zk_reader_new(cut);
  if !err_is_stat(zk_read_stat(&mut r3), "zookeeper: truncated input at byte 60") { ok = false; }
  let z = zk_stat_zero();
  if z.czxid != 0 { ok = false; }
  if z.pzxid != 0 { ok = false; }
  return assert(ok, "Stat encodes the 68-byte record with long/int widths and round-trips");
}

fn t13() -> TestResult {
  var w = zk_writer_new();
  zk_write_id(&mut w, &ZkId{ scheme: "world"; id: "anyone"; });
  var ok = bytes_equal(zk_writer_bytes(&w), hb("00000005776f726c6400000006616e796f6e65"));
  var v = acl1(31, "world", "anyone");
  if zk_acl_vec_count(&v) != 1 { ok = false; }
  if zk_acl_vec_perms(&v, 0) != 31 { ok = false; }
  if str_compare(zk_acl_vec_scheme(&v, 0), "world") != 0 { ok = false; }
  if str_compare(zk_acl_vec_id(&v, 0), "anyone") != 0 { ok = false; }
  if zk_acl_vec_perms(&v, -1) != 0 { ok = false; }
  if str_compare(zk_acl_vec_scheme(&v, 5), "") != 0 { ok = false; }
  var w2 = zk_writer_new();
  zk_write_acl_vector(&mut w2, &v);
  var ok2 = bytes_equal(zk_writer_bytes(&w2), hb("000000010000001f00000005776f726c6400000006616e796f6e65"));
  if !ok2 { ok = false; }
  var r = zk_reader_new(zk_writer_bytes(&w2));
  let back = zk_read_acl_vector(&mut r);
  if !back.is_ok { ok = false; } else {
    let d: ZkAclVec = back.value;
    if zk_acl_vec_count(&d) != 1 { ok = false; }
    if zk_acl_vec_perms(&d, 0) != 31 { ok = false; }
    if str_compare(zk_acl_vec_scheme(&d, 0), "world") != 0 { ok = false; }
    if str_compare(zk_acl_vec_id(&d, 0), "anyone") != 0 { ok = false; }
  }
  var w3 = zk_writer_new();
  var empty = zk_acl_vec_new();
  zk_write_acl_vector(&mut w3, &empty);
  if !bytes_equal(zk_writer_bytes(&w3), hb("00000000")) { ok = false; }
  var r2 = zk_reader_new(hb("ffffffff"));
  let nul = zk_read_acl_vector(&mut r2);
  if !nul.is_ok { ok = false; } else {
    if zk_acl_vec_count(&nul.value) != 0 { ok = false; }
  }
  var r3 = zk_reader_new(hb("fffffffe"));
  if !err_is_aclvec(zk_read_acl_vector(&mut r3), "zookeeper: invalid vector count -2 at byte 0") { ok = false; }
  var r4 = zk_reader_new(hb("000000010000000000000000000000"));
  if !err_is_aclvec(zk_read_acl_vector(&mut r4), "zookeeper: oversized vector count 1 at byte 0") { ok = false; }
  var r5 = zk_reader_new(hb("00000001"));
  if !err_is_aclvec(zk_read_acl_vector(&mut r5), "zookeeper: oversized vector count 1 at byte 0") { ok = false; }
  return assert(ok, "Id, ACL and the flat ACL vector encode, decode and expose accessors");
}

fn t14() -> TestResult {
  var w = zk_writer_new();
  let ev = zk_watch_event_make(zk_event_node_created(), zk_state_sync_connected(), "/x");
  zk_write_watch_event(&mut w, &ev);
  var ok = bytes_equal(zk_writer_bytes(&w), hb("0000000100000003000000022f78"));
  var r = zk_reader_new(zk_writer_bytes(&w));
  let back = zk_read_watch_event(&mut r);
  if !back.is_ok { ok = false; } else {
    let e: ZkWatchEvent = back.value;
    if e.event_type != zk_event_node_created() { ok = false; }
    if e.state != zk_state_sync_connected() { ok = false; }
    if str_compare(e.path, "/x") != 0 { ok = false; }
    if e.path_is_null { ok = false; }
  }
  var w2 = zk_writer_new();
  let ev2 = ZkWatchEvent{ event_type: zk_event_node_deleted(); state: zk_state_expired(); path: ""; path_is_null: true; };
  zk_write_watch_event(&mut w2, &ev2);
  if !bytes_equal(zk_writer_bytes(&w2), hb("00000002ffffff90ffffffff")) { ok = false; }
  var r2 = zk_reader_new(zk_writer_bytes(&w2));
  let back2 = zk_read_watch_event(&mut r2);
  if !back2.is_ok { ok = false; } else {
    let e2: ZkWatchEvent = back2.value;
    if e2.event_type != 2 { ok = false; }
    if e2.state != -112 { ok = false; }
    if !e2.path_is_null { ok = false; }
    if str_compare(e2.path, "") != 0 { ok = false; }
  }
  var r3 = zk_reader_new(hb("0000000100000003fffffffe"));
  if !err_is_event(zk_read_watch_event(&mut r3), "zookeeper: invalid string length -2 at byte 8") { ok = false; }
  var r4 = zk_reader_new(hb("000000010000000300000001ff"));
  if !err_is_event(zk_read_watch_event(&mut r4), "zookeeper: invalid utf-8 at byte 12") { ok = false; }
  return assert(ok, "watch events encode type/state/path and preserve the jute null path");
}

fn t15() -> TestResult {
  var want = Vec[UInt8].new();
  append_bytes(&mut want, hb("000000022f61"));
  append_bytes(&mut want, hb("000000020102"));
  append_bytes(&mut want, hb("000000010000001f00000005776f726c6400000006616e796f6e65"));
  append_bytes(&mut want, hb("00000003"));
  let req = ZkCreateRequest{ path: "/a"; data: hb("0102"); acls: acl1(31, "world", "anyone"); flags: 3; };
  var w = zk_writer_new();
  zk_write_create_request(&mut w, &req);
  var ok = bytes_equal(zk_writer_bytes(&w), want);
  if zk_writer_len(&w) != 43 { ok = false; }
  var r = zk_reader_new(zk_writer_bytes(&w));
  let back = zk_read_create_request(&mut r);
  if !back.is_ok { ok = false; } else {
    let b: ZkCreateRequest = back.value;
    if str_compare(b.path, "/a") != 0 { ok = false; }
    if b.data.len() != 2 { ok = false; }
    if zk_acl_vec_count(&b.acls) != 1 { ok = false; }
    if zk_acl_vec_perms(&b.acls, 0) != 31 { ok = false; }
    if b.flags != 3 { ok = false; }
    if !zk_create_flag_is_ephemeral(b.flags) { ok = false; }
    if !zk_create_flag_is_sequential(b.flags) { ok = false; }
  }
  var w2 = zk_writer_new();
  zk_write_create_response(&mut w2, "/a000000001");
  var r2 = zk_reader_new(zk_writer_bytes(&w2));
  let p = zk_read_create_response(&mut r2);
  if !p.is_ok { ok = false; } else {
    if str_compare(p.value, "/a000000001") != 0 { ok = false; }
  }
  var w3 = zk_writer_new();
  var empty_data = Vec[UInt8].new();
  var empty_acls = zk_acl_vec_new();
  let bare = ZkCreateRequest{ path: ""; data: empty_data; acls: empty_acls; flags: 0; };
  zk_write_create_request(&mut w3, &bare);
  if !bytes_equal(zk_writer_bytes(&w3), hb("00000000000000000000000000000000")) { ok = false; }
  var r3 = zk_reader_new(drop_last(want));
  let cut = zk_read_create_request(&mut r3);
  if !err_is_crq(cut, "zookeeper: truncated input at byte 39") { ok = false; }
  return assert(ok, "CreateRequest (path/data/acls/flags) and CreateResponse encode and round-trip");
}

fn t16() -> TestResult {
  var kids = Vec[Str].new();
  kids.push("a");
  kids.push("bb");
  var st = zk_stat_zero();
  st.czxid = 5;
  st.num_children = 2;
  let resp = ZkGetChildrenResponse{ children: kids; stat: st; };
  var w = zk_writer_new();
  zk_write_get_children_response(&mut w, &resp);
  var want = Vec[UInt8].new();
  append_bytes(&mut want, hb("000000020000000161000000026262"));
  append_bytes(&mut want, hb("0000000000000005"));
  append_bytes(&mut want, hb("0000000000000000"));
  append_bytes(&mut want, hb("0000000000000000"));
  append_bytes(&mut want, hb("0000000000000000"));
  append_bytes(&mut want, hb("00000000"));
  append_bytes(&mut want, hb("00000000"));
  append_bytes(&mut want, hb("00000000"));
  append_bytes(&mut want, hb("0000000000000000"));
  append_bytes(&mut want, hb("00000000"));
  append_bytes(&mut want, hb("00000002"));
  append_bytes(&mut want, hb("0000000000000000"));
  var ok = bytes_equal(zk_writer_bytes(&w), want);
  if zk_writer_len(&w) != 83 { ok = false; }
  var r = zk_reader_new(zk_writer_bytes(&w));
  let back = zk_read_get_children_response(&mut r);
  if !back.is_ok { ok = false; } else {
    let d: ZkGetChildrenResponse = back.value;
    if d.children.len() != 2 { ok = false; }
    if str_compare(d.children[0], "a") != 0 { ok = false; }
    if str_compare(d.children[1], "bb") != 0 { ok = false; }
    if d.stat.czxid != 5 { ok = false; }
    if d.stat.num_children != 2 { ok = false; }
  }
  if zk_reader_remaining(&r) != 0 { ok = false; }
  var r2 = zk_reader_new(drop_last(want));
  let cut = zk_read_get_children_response(&mut r2);
  if !err_is_gcr(cut, "zookeeper: truncated input at byte 75") { ok = false; }
  var r3 = zk_reader_new(hb("0000000200000001610000000262"));
  let badstat = zk_read_get_children_response(&mut r3);
  if !err_is_gcr(badstat, "zookeeper: truncated input at byte 13") { ok = false; }
  return assert(ok, "GetChildrenResponse encodes the children vector and Stat with exact offsets");
}

fn t17() -> TestResult {
  let sd = ZkSetDataRequest{ path: "/p"; data: hb("07"); version: -1; };
  var w = zk_writer_new();
  zk_write_set_data_request(&mut w, &sd);
  var ok = bytes_equal(zk_writer_bytes(&w), hb("000000022f700000000107ffffffff"));
  var r = zk_reader_new(zk_writer_bytes(&w));
  let sdback = zk_read_set_data_request(&mut r);
  if !sdback.is_ok { ok = false; } else {
    let b: ZkSetDataRequest = sdback.value;
    if str_compare(b.path, "/p") != 0 { ok = false; }
    if b.data.len() != 1 { ok = false; }
    if first_byte(b.data) != 7 { ok = false; }
    if b.version != -1 { ok = false; }
  }
  var st = zk_stat_zero();
  st.data_length = 2;
  let gd = ZkGetDataResponse{ data: hb("0908"); stat: st; };
  var w2 = zk_writer_new();
  zk_write_get_data_response(&mut w2, &gd);
  if zk_writer_len(&w2) != 74 { ok = false; }
  var r2 = zk_reader_new(zk_writer_bytes(&w2));
  let gdback = zk_read_get_data_response(&mut r2);
  if !gdback.is_ok { ok = false; } else {
    let d: ZkGetDataResponse = gdback.value;
    if d.data.len() != 2 { ok = false; }
    if first_byte(d.data) != 9 { ok = false; }
    if d.stat.data_length != 2 { ok = false; }
  }
  var w3 = zk_writer_new();
  zk_write_path_watch_request(&mut w3, &ZkPathWatchRequest{ path: "/p"; watch: true; });
  if !bytes_equal(zk_writer_bytes(&w3), hb("000000022f7001")) { ok = false; }
  var r3 = zk_reader_new(zk_writer_bytes(&w3));
  let pwr = zk_read_path_watch_request(&mut r3);
  if !pwr.is_ok { ok = false; } else {
    if str_compare(pwr.value.path, "/p") != 0 { ok = false; }
    if !pwr.value.watch { ok = false; }
  }
  return assert(ok, "SetData/GetData records and the shared path+watch shape encode and decode");
}

fn t18() -> TestResult {
  var w = zk_writer_new();
  zk_write_path_version_request(&mut w, &ZkPathVersionRequest{ path: "/d"; version: 5; });
  var ok = bytes_equal(zk_writer_bytes(&w), hb("000000022f6400000005"));
  var r = zk_reader_new(zk_writer_bytes(&w));
  let pv = zk_read_path_version_request(&mut r);
  if !pv.is_ok { ok = false; } else {
    if str_compare(pv.value.path, "/d") != 0 { ok = false; }
    if pv.value.version != 5 { ok = false; }
  }
  var w2 = zk_writer_new();
  zk_write_path_watch_request(&mut w2, &ZkPathWatchRequest{ path: "/e"; watch: false; });
  if !bytes_equal(zk_writer_bytes(&w2), hb("000000022f6500")) { ok = false; }
  var w3 = zk_writer_new();
  var noacls = zk_acl_vec_new();
  zk_write_set_acl_request(&mut w3, &ZkSetAclRequest{ path: "/p"; acls: noacls; version: 0; });
  if !bytes_equal(zk_writer_bytes(&w3), hb("000000022f700000000000000000")) { ok = false; }
  var r3 = zk_reader_new(zk_writer_bytes(&w3));
  let sa = zk_read_set_acl_request(&mut r3);
  if !sa.is_ok { ok = false; } else {
    if str_compare(sa.value.path, "/p") != 0 { ok = false; }
    if zk_acl_vec_count(&sa.value.acls) != 0 { ok = false; }
    if sa.value.version != 0 { ok = false; }
  }
  var w4 = zk_writer_new();
  zk_write_sync_request(&mut w4, "/s");
  var w5 = zk_writer_new();
  zk_write_sync_response(&mut w5, "/s");
  if !bytes_equal(zk_writer_bytes(&w4), hb("000000022f73")) { ok = false; }
  if !bytes_equal(zk_writer_bytes(&w5), hb("000000022f73")) { ok = false; }
  var r5 = zk_reader_new(zk_writer_bytes(&w5));
  let sp = zk_read_sync_response(&mut r5);
  if !sp.is_ok { ok = false; } else {
    if str_compare(sp.value, "/s") != 0 { ok = false; }
  }
  return assert(ok, "delete/check path+version, exists path+watch, setAcl, sync records encode");
}

fn t19() -> TestResult {
  let a = ZkAuthRequest{ auth_type: 0; scheme: "digest"; auth_data: hb("757365723a7077"); };
  var w = zk_writer_new();
  zk_write_auth_request(&mut w, &a);
  var want = Vec[UInt8].new();
  append_bytes(&mut want, hb("00000000"));
  append_bytes(&mut want, hb("00000006646967657374"));
  append_bytes(&mut want, hb("00000007757365723a7077"));
  var ok = bytes_equal(zk_writer_bytes(&w), want);
  var r = zk_reader_new(zk_writer_bytes(&w));
  let back = zk_read_auth_request(&mut r);
  if !back.is_ok { ok = false; } else {
    let b: ZkAuthRequest = back.value;
    if b.auth_type != 0 { ok = false; }
    if str_compare(b.scheme, "digest") != 0 { ok = false; }
    if b.auth_data.len() != 7 { ok = false; }
    if first_byte(b.auth_data) != 117 { ok = false; }
  }
  var r2 = zk_reader_new(hb("00000000000000"));
  let cut = zk_read_auth_request(&mut r2);
  if !err_is_arq(cut, "zookeeper: truncated input at byte 4") { ok = false; }
  return assert(ok, "AuthPacket (type/scheme/data) encodes and round-trips");
}

// --------------------------------------------------
//  parse-one helpers
// --------------------------------------------------

fn wire_create(xid: Int, op: Int) -> Vec[UInt8] {
  var w = zk_writer_new();
  zk_write_request_header(&mut w, xid, op);
  let req = ZkCreateRequest{ path: "/a"; data: hb("0102"); acls: acl1(31, "world", "anyone"); flags: 3; };
  zk_write_create_request(&mut w, &req);
  return zk_writer_bytes(&w);
}

fn wire_path_watch(xid: Int, op: Int, path: Str, watch: Bool) -> Vec[UInt8] {
  var w = zk_writer_new();
  zk_write_request_header(&mut w, xid, op);
  zk_write_path_watch_request(&mut w, &ZkPathWatchRequest{ path: path; watch: watch; });
  return zk_writer_bytes(&w);
}

fn wire_path_version(xid: Int, op: Int, path: Str, version: Int) -> Vec[UInt8] {
  var w = zk_writer_new();
  zk_write_request_header(&mut w, xid, op);
  zk_write_path_version_request(&mut w, &ZkPathVersionRequest{ path: path; version: version; });
  return zk_writer_bytes(&w);
}

fn wire_path_only(xid: Int, op: Int, path: Str) -> Vec[UInt8] {
  var w = zk_writer_new();
  zk_write_request_header(&mut w, xid, op);
  zk_write_ustring(&mut w, path);
  return zk_writer_bytes(&w);
}

fn wire_empty(xid: Int, op: Int) -> Vec[UInt8] {
  var w = zk_writer_new();
  zk_write_request_header(&mut w, xid, op);
  return zk_writer_bytes(&w);
}

fn t20() -> TestResult {
  var ok = true;
  let ping = zk_parse_one(wire_empty(zk_xid_ping(), zk_op_ping()));
  if !ping.is_ok { ok = false; } else {
    let m: ZkMessage = ping.value;
    if m.xid != -2 { ok = false; }
    if m.op != 11 { ok = false; }
    if m.body_kind != 0 { ok = false; }
    if m.consumed != 8 { ok = false; }
  }
  let close = zk_parse_one(wire_empty(zk_xid_ping(), zk_op_close()));
  if !close.is_ok { ok = false; } else {
    if close.value.consumed != 8 { ok = false; }
    if close.value.op != -11 { ok = false; }
  }
  let sw = zk_parse_one(wire_empty(1, zk_op_set_watches()));
  if !sw.is_ok { ok = false; } else {
    if sw.value.consumed != 8 { ok = false; }
  }
  let cr = zk_parse_one(wire_create(1, zk_op_create()));
  if !cr.is_ok { ok = false; } else {
    let m: ZkMessage = cr.value;
    if m.consumed != 51 { ok = false; }
    if m.body_kind != 1 { ok = false; }
    if str_compare(m.path, "/a") != 0 { ok = false; }
    if m.data.len() != 2 { ok = false; }
    if zk_acl_vec_count(&m.acls) != 1 { ok = false; }
    if m.flags != 3 { ok = false; }
  }
  let cr2 = zk_parse_one(wire_create(1, zk_op_create2()));
  if !cr2.is_ok { ok = false; } else {
    if cr2.value.consumed != 51 { ok = false; }
    if cr2.value.op != 15 { ok = false; }
    if cr2.value.body_kind != 1 { ok = false; }
  }
  let del = zk_parse_one(wire_path_version(2, zk_op_delete(), "/d", 5));
  if !del.is_ok { ok = false; } else {
    if del.value.consumed != 18 { ok = false; }
    if del.value.body_kind != 2 { ok = false; }
    if del.value.version != 5 { ok = false; }
  }
  let ex = zk_parse_one(wire_path_watch(2, zk_op_exists(), "/a", true));
  if !ex.is_ok { ok = false; } else {
    if ex.value.consumed != 15 { ok = false; }
    if ex.value.body_kind != 3 { ok = false; }
    if str_compare(ex.value.path, "/a") != 0 { ok = false; }
    if !ex.value.watch { ok = false; }
  }
  let gd = zk_parse_one(wire_path_watch(3, zk_op_get_data(), "/a", false));
  if !gd.is_ok { ok = false; } else {
    if gd.value.body_kind != 4 { ok = false; }
    if gd.value.watch { ok = false; }
  }
  var wsd = zk_writer_new();
  zk_write_request_header(&mut wsd, 4, zk_op_set_data());
  zk_write_set_data_request(&mut wsd, &ZkSetDataRequest{ path: "/p"; data: hb("07"); version: -1; });
  let sd = zk_parse_one(zk_writer_bytes(&wsd));
  if !sd.is_ok { ok = false; } else {
    if sd.value.body_kind != 5 { ok = false; }
    if sd.value.consumed != 23 { ok = false; }
    if sd.value.version != -1 { ok = false; }
    if sd.value.data.len() != 1 { ok = false; }
  }
  let ga = zk_parse_one(wire_path_watch(5, zk_op_get_acl(), "/a", true));
  if !ga.is_ok { ok = false; } else {
    if ga.value.body_kind != 6 { ok = false; }
  }
  var wsa = zk_writer_new();
  zk_write_request_header(&mut wsa, 6, zk_op_set_acl());
  var noacls = zk_acl_vec_new();
  zk_write_set_acl_request(&mut wsa, &ZkSetAclRequest{ path: "/p"; acls: noacls; version: 0; });
  let sa = zk_parse_one(zk_writer_bytes(&wsa));
  if !sa.is_ok { ok = false; } else {
    if sa.value.body_kind != 7 { ok = false; }
    if sa.value.consumed != 8 + 14 { ok = false; }
  }
  let gc = zk_parse_one(wire_path_watch(7, zk_op_get_children(), "/a", true));
  if !gc.is_ok { ok = false; } else {
    if gc.value.body_kind != 8 { ok = false; }
    if gc.value.consumed != 15 { ok = false; }
  }
  let gc2 = zk_parse_one(wire_path_watch(7, zk_op_get_children2(), "/a", true));
  if !gc2.is_ok { ok = false; } else {
    if gc2.value.body_kind != 8 { ok = false; }
    if gc2.value.op != 12 { ok = false; }
  }
  let sy = zk_parse_one(wire_path_only(8, zk_op_sync(), "/s"));
  if !sy.is_ok { ok = false; } else {
    if sy.value.body_kind != 9 { ok = false; }
    if sy.value.consumed != 14 { ok = false; }
    if str_compare(sy.value.path, "/s") != 0 { ok = false; }
  }
  let ck = zk_parse_one(wire_path_version(9, zk_op_check(), "/c", 3));
  if !ck.is_ok { ok = false; } else {
    if ck.value.body_kind != 10 { ok = false; }
    if ck.value.version != 3 { ok = false; }
  }
  var wau = zk_writer_new();
  zk_write_request_header(&mut wau, zk_xid_auth(), zk_op_auth());
  zk_write_auth_request(&mut wau, &ZkAuthRequest{ auth_type: 0; scheme: "x"; auth_data: hb("79"); });
  let au = zk_parse_one(zk_writer_bytes(&wau));
  if !au.is_ok { ok = false; } else {
    if au.value.body_kind != 11 { ok = false; }
    if au.value.consumed != 22 { ok = false; }
    if str_compare(au.value.auth_scheme, "x") != 0 { ok = false; }
    if au.value.auth_data.len() != 1 { ok = false; }
  }
  var wno = zk_writer_new();
  zk_write_request_header(&mut wno, zk_xid_notification(), zk_op_notification());
  zk_write_watch_event(&mut wno, &zk_watch_event_make(1, 3, "/x"));
  let no = zk_parse_one(zk_writer_bytes(&wno));
  if !no.is_ok { ok = false; } else {
    if no.value.body_kind != 12 { ok = false; }
    if no.value.consumed != 22 { ok = false; }
    if no.value.event_type != 1 { ok = false; }
    if no.value.state != 3 { ok = false; }
    if str_compare(no.value.path, "/x") != 0 { ok = false; }
  }
  return assert(ok, "parse_one decodes every request body with exact consumed counts");
}

fn t21() -> TestResult {
  var ok = true;
  let r1 = zk_parse_one(hb(""));
  if !err_is_msg(r1, "zookeeper: truncated input at byte 0") { ok = false; }
  let r2 = zk_parse_one(hb("00000001"));
  if !err_is_msg(r2, "zookeeper: truncated input at byte 4") { ok = false; }
  let multi = zk_parse_one(wire_empty(9, zk_op_multi()));
  if !err_is_msg(multi, "zookeeper: unsupported opcode 14 at byte 4") { ok = false; }
  let unknown = zk_parse_one(wire_empty(9, 99));
  if !err_is_msg(unknown, "zookeeper: unsupported opcode 99 at byte 4") { ok = false; }
  let badbool = zk_parse_one(hb("0000000200000003000000022f6102"));
  if !err_is_msg(badbool, "zookeeper: invalid bool byte 2 at byte 14") { ok = false; }
  let badlen = zk_parse_one(hb("0000000200000003fffffffe"));
  if !err_is_msg(badlen, "zookeeper: invalid string length -2 at byte 8") { ok = false; }
  let negbuf = zk_parse_one(hb("0000000100000001000000022f61fffffffe"));
  if !err_is_msg(negbuf, "zookeeper: invalid buffer length -2 at byte 14") { ok = false; }
  let ov = zk_parse_one(hb("0000000100000001000000022f610000000000000001"));
  if !err_is_msg(ov, "zookeeper: oversized vector count 1 at byte 18") { ok = false; }
  let tr = zk_parse_one(hb("0000000100000001000000022f610000000301"));
  if !err_is_msg(tr, "zookeeper: truncated input at byte 18") { ok = false; }
  let ping = wire_empty(zk_xid_ping(), zk_op_ping());
  let exact = zk_parse_one_exact(ping);
  if !exact.is_ok { ok = false; } else {
    if exact.value.consumed != 8 { ok = false; }
  }
  var extra = wire_empty(zk_xid_ping(), zk_op_ping());
  append_bytes(&mut extra, hb("00"));
  let trail = zk_parse_one_exact(extra);
  if !err_is_msg(trail, "zookeeper: trailing data at byte 8") { ok = false; }
  return assert(ok, "parse_one rejects truncation, bad lengths, bad vectors, bad ops and trailing data");
}

fn t22() -> TestResult {
  var ok = true;
  var st = zk_stat_zero();
  st.czxid = 7;
  st.version = 3;
  var w = zk_writer_new();
  zk_write_reply_header(&mut w, 2, 100, 0);
  zk_write_stat(&mut w, &st);
  let ex = zk_parse_reply(zk_writer_bytes(&w), zk_op_exists());
  if !ex.is_ok { ok = false; } else {
    let rp: ZkReply = ex.value;
    if rp.xid != 2 { ok = false; }
    if rp.zxid != 100 { ok = false; }
    if rp.err != 0 { ok = false; }
    if rp.is_error { ok = false; }
    if rp.body_kind != 13 { ok = false; }
    if rp.consumed != 84 { ok = false; }
    if rp.stat.czxid != 7 { ok = false; }
    if rp.stat.version != 3 { ok = false; }
  }
  var we = zk_writer_new();
  zk_write_reply_header(&mut we, 2, 0, zk_err_nonode());
  let er = zk_parse_reply(zk_writer_bytes(&we), zk_op_exists());
  if !er.is_ok { ok = false; } else {
    if !er.value.is_error { ok = false; }
    if er.value.err != -101 { ok = false; }
    if er.value.consumed != 16 { ok = false; }
    if er.value.body_kind != 0 { ok = false; }
    if str_compare(zk_err_name(er.value.err), "NONODE") != 0 { ok = false; }
  }
  var st2 = zk_stat_zero();
  st2.data_length = 1;
  var w2 = zk_writer_new();
  zk_write_reply_header(&mut w2, 3, 0, 0);
  zk_write_get_data_response(&mut w2, &ZkGetDataResponse{ data: hb("05"); stat: st2; });
  let gd = zk_parse_reply(zk_writer_bytes(&w2), zk_op_get_data());
  if !gd.is_ok { ok = false; } else {
    if gd.value.body_kind != 4 { ok = false; }
    if gd.value.data.len() != 1 { ok = false; }
    if first_byte(gd.value.data) != 5 { ok = false; }
    if gd.value.stat.data_length != 1 { ok = false; }
    if gd.value.consumed != 89 { ok = false; }
  }
  var kids = Vec[Str].new();
  kids.push("a");
  var w3 = zk_writer_new();
  zk_write_reply_header(&mut w3, 4, 0, 0);
  zk_write_get_children_response(&mut w3, &ZkGetChildrenResponse{ children: kids; stat: zk_stat_zero(); });
  let gc = zk_parse_reply(zk_writer_bytes(&w3), zk_op_get_children());
  if !gc.is_ok { ok = false; } else {
    if gc.value.body_kind != 8 { ok = false; }
    if gc.value.children.len() != 1 { ok = false; }
    if str_compare(gc.value.children[0], "a") != 0 { ok = false; }
  }
  var w4 = zk_writer_new();
  zk_write_reply_header(&mut w4, 5, 0, 0);
  zk_write_get_acl_response(&mut w4, &ZkGetAclResponse{ acls: acl1(31, "world", "anyone"); stat: zk_stat_zero(); });
  let ga = zk_parse_reply(zk_writer_bytes(&w4), zk_op_get_acl());
  if !ga.is_ok { ok = false; } else {
    if ga.value.body_kind != 6 { ok = false; }
    if zk_acl_vec_count(&ga.value.acls) != 1 { ok = false; }
    if str_compare(zk_acl_vec_scheme(&ga.value.acls, 0), "world") != 0 { ok = false; }
  }
  var w5 = zk_writer_new();
  zk_write_reply_header(&mut w5, 6, 0, 0);
  zk_write_create_response(&mut w5, "/a1");
  let cp = zk_parse_reply(zk_writer_bytes(&w5), zk_op_create());
  if !cp.is_ok { ok = false; } else {
    if cp.value.body_kind != 14 { ok = false; }
    if str_compare(cp.value.path, "/a1") != 0 { ok = false; }
    if cp.value.consumed != 23 { ok = false; }
  }
  var w6 = zk_writer_new();
  zk_write_reply_header(&mut w6, zk_xid_ping(), 0, 0);
  let pg = zk_parse_reply(zk_writer_bytes(&w6), zk_op_ping());
  if !pg.is_ok { ok = false; } else {
    if pg.value.consumed != 16 { ok = false; }
    if pg.value.body_kind != 0 { ok = false; }
  }
  var w7 = zk_writer_new();
  zk_write_reply_header(&mut w7, 9, 0, 0);
  let ck = zk_parse_reply(zk_writer_bytes(&w7), zk_op_check());
  if !ck.is_ok { ok = false; } else {
    if ck.value.consumed != 16 { ok = false; }
  }
  var w8 = zk_writer_new();
  zk_write_reply_header(&mut w8, 10, 0, 0);
  zk_write_sync_response(&mut w8, "/s");
  let sy = zk_parse_reply(zk_writer_bytes(&w8), zk_op_sync());
  if !sy.is_ok { ok = false; } else {
    if sy.value.body_kind != 14 { ok = false; }
    if str_compare(sy.value.path, "/s") != 0 { ok = false; }
  }
  return assert(ok, "parse_reply decodes stat, data+stat, children+stat, acl+stat, path and error replies");
}

fn t23() -> TestResult {
  var ok = true;
  var w = zk_writer_new();
  zk_write_reply_header(&mut w, zk_xid_ping(), 0, 0);
  let ping = zk_writer_bytes(&w);
  let exact = zk_parse_reply_exact(ping, zk_op_ping());
  if !exact.is_ok { ok = false; } else {
    if exact.value.consumed != 16 { ok = false; }
  }
  var extra = zk_writer_bytes(&w);
  append_bytes(&mut extra, hb("00"));
  let trail = zk_parse_reply_exact(extra, zk_op_ping());
  if !err_is_reply(trail, "zookeeper: trailing data at byte 16") { ok = false; }
  var extra2 = zk_writer_bytes(&w);
  append_bytes(&mut extra2, hb("00"));
  let lax = zk_parse_reply(extra2, zk_op_ping());
  if !lax.is_ok { ok = false; } else {
    if lax.value.consumed != 16 { ok = false; }
  }
  var wst = zk_writer_new();
  zk_write_stat(&mut wst, &zk_stat_zero());
  let cut = drop_last(zk_writer_bytes(&wst));
  var wh = zk_writer_new();
  zk_write_reply_header(&mut wh, 1, 0, 0);
  var short_stat = zk_writer_bytes(&wh);
  append_bytes(&mut short_stat, cut);
  let rs = zk_parse_reply(short_stat, zk_op_exists());
  if !err_is_reply(rs, "zookeeper: truncated input at byte 76") { ok = false; }
  let rh = zk_parse_reply(hb("00000001"), zk_op_exists());
  if !err_is_reply(rh, "zookeeper: truncated input at byte 4") { ok = false; }
  var we = zk_writer_new();
  zk_write_reply_header(&mut we, 1, 0, zk_err_sessionexpired());
  var errbuf = zk_writer_bytes(&we);
  append_bytes(&mut errbuf, hb("00"));
  let errx = zk_parse_reply_exact(errbuf, zk_op_ping());
  if !err_is_reply(errx, "zookeeper: trailing data at byte 16") { ok = false; }
  return assert(ok, "parse_reply exactness, truncation and error-frame handling");
}

fn t24() -> TestResult {
  let w = zk_writer_new();
  var ok = zk_writer_len(&w) == 0;
  if zk_writer_bytes(&w).len() != 0 { ok = false; }
  var r = zk_reader_new(hb("010203"));
  if zk_reader_pos(&r) != 0 { ok = false; }
  if zk_reader_remaining(&r) != 3 { ok = false; }
  let b = zk_read_byte(&mut r);
  if !b.is_ok { ok = false; } else {
    if b.value != 1 { ok = false; }
  }
  if zk_reader_pos(&r) != 1 { ok = false; }
  if zk_reader_remaining(&r) != 2 { ok = false; }
  var empty = zk_reader_new(Vec[UInt8].new());
  if zk_reader_remaining(&empty) != 0 { ok = false; }
  if zk_reader_pos(&empty) != 0 { ok = false; }
  if zk_protocol_version() != 0 { ok = false; }
  if zk_stat_wire_size() != 68 { ok = false; }
  if zk_null_len() != -1 { ok = false; }
  if str_compare(zk_op_name(15), "CREATE2") != 0 { ok = false; }
  if str_compare(zk_body_kind_name(0), "EMPTY") != 0 { ok = false; }
  if str_compare(zk_body_kind_name(12), "NOTIFICATION") != 0 { ok = false; }
  if str_compare(zk_err_name(-119), "NOTREADONLY") != 0 { ok = false; }
  if str_compare(zk_xid_name(-8), "SET_WATCHES") != 0 { ok = false; }
  return assert(ok, "reader/writer lifecycle and codec metadata accessors");
}

fn main() -> Int {
  io.println("=== xiom.zookeeper conformance tests ===");
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
    io.println("xiom.zookeeper: all tests passed");
  } else {
    io.println("xiom.zookeeper: tests failed");
  }
  return failed;
}


